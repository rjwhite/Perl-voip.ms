#!/usr/bin/env perl

# set/unset/check the recording flag for INCOMING calls for a phone
# number using the voip.ms API
# usage:
#    phone_recording on/off/check
# eg:
#   phone-recording --quiet on      # phone number taken from config-file
#
#   phone-recording --phone 555-123-4567  check      # check a different phone
#       555-123-4567 currently has 'record_calls' set to '1' (on)
#
# It gets the phone number (did) from the config file, which
# can be over-ridden with the -p/--phone option.
# The phone number in the config file is optional and is in the
# section 'record' and uses keyword 'did'.  eg:
#
#   record:
#       did = 123-456-7890
#
# Requirements:
#   LWP::UserAgent from CPAN
#   Moxad::Config found on github.com under user rjwhite

# Copyright 2022 RJ White
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
# ---------------------------------------------------------------------

use strict ;
use warnings ;
use LWP::UserAgent() ;
use lib "/usr/local/Moxad/lib" ;
use Moxad::Config ;
use JSON ;
use Data::Dumper ;

# Globals 
my $G_progname   = $0 ;
my $G_version    = "v0.3.1" ;
my $G_debug_flag = 0 ;

# Constants
my $C_DEFAULT_TIMEOUT = 30  ;
my $C_RECORD_KEY      = 'record_calls' ;
my $C_WARNING         = 0 ;
my $C_FATAL           = 1 ;

# run the program.  exit with 1 if any problems
exit(1) if ( main() ) ;
exit(0) ;



sub main {
    my $home         = $ENV{ HOME } ;
    my $get_method   = "getDIDsInfo" ;
    my $set_method   = "setDIDInfo" ;
    my $did          = undef ;
    my $help_flag    = 0 ;
    my $verbose_flag = 1 ;
    my $config_file  = undef ;
    my $action       = undef ;
    my $cmd_line_ph  = undef ;

    $G_progname     =~ s/^.*\/// ;

    my $i_am = (caller(0))[3] . '()' ;

    # get options

    for ( my $i = 0 ; $i <= $#ARGV ; $i++ ) {
        my $arg = $ARGV[ $i ] ;
        if (( $arg eq "-h" ) or ( $arg eq "--help" )) {
            $help_flag++ ;
            $action = 'check' ;    # just to pass sanity check below
        } elsif (( $arg eq "-c" ) or ( $arg eq "--config" )) {
            $config_file = $ARGV[ ++$i ] ;
            if ( ! -f $config_file ) {
                error( "no such file: $config_file", $C_FATAL ) ;
            }
        } elsif (( $arg eq "-d" ) or ( $arg eq "--debug" )) {
            $G_debug_flag++ ;
        } elsif (( $arg eq "-q" ) or ( $arg eq "--quiet" )) {
            $verbose_flag = 0 ;
        } elsif (( $arg eq "-p" ) or ( $arg eq "--phone" )) {
            $cmd_line_ph = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-V" ) or ( $arg eq "--version" )) {
            print "Program version: $G_version\n" ;
            print "Config module version: $Moxad::Config::VERSION\n" ;
            return(0) ;
        } elsif ( $arg =~ /^\-/ ) {
            error( "unknown option: $arg", $C_FATAL ) ;
        } else {
            $action = $arg ;
        }
    }

    # check for valid action of 'on', 'off' or 'check'

    if ( not defined( $action )) {
        my $err = "need to provide an action of 'on', 'off' or 'check'" ;
        error( $err, $C_FATAL ) ;
    }
    my $recording_flag = undef ;
    my $check_flag = undef ;
    $recording_flag = 1 if ( $action =~ /on/i ) ;
    $recording_flag = 0 if ( $action =~ /off/i ) ;
    $check_flag = 1 if ( $action =~ /check/i ) ;
    if (( not defined( $recording_flag )) and ( not defined( $check_flag ))) {
        error( "unknown action: $action", $C_FATAL ) ;
    }

    # find the config file we really want

    $config_file = find_config_file( $config_file ) ;
    if ( not defined( $config_file )) {
        error( "no config file found", $C_FATAL ) ;
    }
    dprint( "$i_am: using config file: $config_file" ) ;

    # read in config data

    # show config debug if -d/--debug flag used more than once
    my $config_debug = 0 ;
    $config_debug = 1 if ( $G_debug_flag > 1 ) ;

    Moxad::Config->set_debug( $config_debug ) ;
    my $cfg1 = Moxad::Config->new(
        $config_file, "",
        { 'AcceptUndefinedKeywords' => 'no' } ) ;
    if ( $cfg1->errors() ) {
        my @errors = $cfg1->errors() ;
        foreach my $error ( @errors ) {
            error( $error, $C_WARNING ) ;
        }
        return(1) ;
    }
    dprint( "$i_am: config data read ok" ) ;

    # sanity checking required sections

    my %got_sections = () ;
    my @needed_sections = ( 'authentication' ) ;
    my @sections = $cfg1->get_sections() ;
    foreach my $section ( @sections ) {
        $got_sections{ $section } = 1 ;
    }
    my $num_errors = 0 ;
    foreach my $section ( @needed_sections ) {
        if ( not defined( $got_sections{ $section } )) {
            my $err = "missing section \'$section\' in $config_file" ;
            error( $err, $C_WARNING ) ;
            $num_errors++ ;
        }
    }
    return(1) if ( $num_errors ) ;

    # good to go.  get authentication info

    my %auth_values = () ;
    my @values_i_need = ( 'user', 'pass' ) ;
    foreach my $keyword ( @values_i_need ) {
        my $value = $cfg1->get_values( 'authentication', $keyword ) ;
        $auth_values{ $keyword } = $value ;
    }
    if ( $cfg1->errors() ) {
        my @errors = $cfg1->errors() ;
        foreach my $error ( @errors ) {
            error( $error, $C_WARNING ) ;
        }
        return(1) ;
    }
    my $user   = $auth_values{ 'user' } ;
    my $pass   = $auth_values{ 'pass' } ;

    # get the phone number.  It's optional in the config file,
    # so we ignore any errors that would be found with $cfg1->errors().
    # We over-ride the config file value if given on the command line

    my $phone_number = $cfg1->get_values( 'record', 'did' ) ;
    if ( defined( $cmd_line_ph )) {
        $phone_number = $cmd_line_ph ;
    }
    if ( not defined( $phone_number )) {
        error( "no phone number provided", $C_FATAL ) ;
    }

    # check and format DID number if necessary

    my $original_ph = $phone_number ;
    $phone_number =~ s/-//g ;        # remove dashes
    $phone_number =~ s/ //g ;        # remove spaces
    if ( $phone_number !~ /^\d+$/ ) {
        error( "phone_number is not numeric: $original_ph", $C_FATAL ) ;
    }
    if ( length( $phone_number ) < 10 ) {
        error( "phone_number ($original_ph) too short", $C_FATAL ) ;
    }
    dprint( "$i_am: using a DID (phone number) of $phone_number" ) ;

    # we finally have the info we want to provide useful data if
    # the --help option was used

    if ( $help_flag ) {
        printf "usage: %s [option]* on|off|check\n" .
            "%s %s %s %s %s %s",
            $G_progname,
            "\t[-c|--config file]   ($config_file)\n",
            "\t[-d|--debug]         (print debugging messages)\n",
            "\t[-h|--help]          (print usage)\n",
            "\t[-p|--phone num]     ($original_ph)\n",
            "\t[-q|--quiet]         (don't print status messages)\n",
            "\t[-V|--version]       ($G_version)\n" ;
        return(0) ;
    }

    # get the optional timeout from the config file. 

    my $timeout = $cfg1->get_values( 'info', 'timeout' ) ;
    if ( not defined( $timeout )) {
        dprint( "$i_am: using default timeout of $C_DEFAULT_TIMEOUT seconds" ) ;
        $timeout = $C_DEFAULT_TIMEOUT ;
    } else {
        if ( $timeout !~ /^\d+$/ ) {
            error( "timeout ($timeout) is non-numeric", $C_FATAL ) ;
        }
        dprint( "$i_am: using timeout from config file: $timeout seconds" ) ;
    }

    my %did_info = ( 'did' => $phone_number ) ;
    my $json = voip_service( $get_method, $user, $pass, $timeout, \%did_info ) ;

    # get fields we need for changing record_calls in API call

    my $dids = $json->{ 'dids' } ;
    if ( not defined( $dids )) {
        error( "could not get \'dids\' info array in JSON return", $C_FATAL ) ;
    }

    # These are the only fields that seem to need to have their values
    # preserved between calls for "getDIDsInfo" and "setDIDInfo"

    my %required_fields = (
        'did'           => undef,
        'routing'       => undef,
        'pop'           => undef,
        'dialtime'      => undef,
        'cnam',         => undef,
        'billing_type'  => undef,
        'voicemail'     => undef,
        $C_RECORD_KEY   => undef,
    ) ;
    return(1) if get_fields( $dids, \%required_fields ) ;
    dprint( "$i_am: info collected using $get_method:" ) ;
    print Dumper( \%required_fields ) if ( $G_debug_flag ) ;

    # get the current value for record_calls.  check if already what we want
    my $record_value = $required_fields{ $C_RECORD_KEY } ;

    # see if we only want to know what it is currently set to.

    if ( $check_flag ) {
        my $value = 'unknown' ;
        $value = "'1' (on)"  if ( $record_value eq "1" ) ;
        $value = "'0' (off)" if ( $record_value eq "0" ) ;
        print( "$original_ph currently has '$C_RECORD_KEY' set to $value\n" ) ;
        return(0) ;
    }

    # if we made it to here, we know that $recording_flag is set

    if ( $record_value eq $recording_flag ) {
        if ( $verbose_flag  ) {
            my $msg = "'$C_RECORD_KEY' is already set to $recording_flag " .
                    "for phone# $original_ph" ;
            print( "$msg\n" ) ;
        }
        return(0) ;
    }

    $required_fields{ $C_RECORD_KEY } = $recording_flag ;

    # set the new value for recording

    $json = voip_service( $set_method, $user, $pass, 
                          $timeout, \%required_fields ) ;
    dprint( "$i_am: return collected using $set_method:" ) ;
    print Dumper( $json ) if ( $G_debug_flag ) ;

    if ( $verbose_flag ) {
        my $nice_value = "" ;
        $nice_value = "(on)"  if $recording_flag eq "1" ; 
        $nice_value = "(off)" if $recording_flag eq "0" ; 
        print "Set '$C_RECORD_KEY' to '$recording_flag' ${nice_value} for " .
            "phone number $original_ph\n" ;
    }
    return(0) ;
}


# make the API call to voip.ms
#
# Arguments:
#   1:  method to be used( getDIDsInfo, setDIDInfo, etc )
#   2:  userid
#   3:  API password
#   4:  timeout
#   5:  reference of hash of values to send
# Returns:
#   reference to hash of return data

sub voip_service {
    my $method       = shift ;
    my $userid       = shift ;
    my $password     = shift ;
    my $timeout      = shift ;
    my $fields_ref   = shift ;

    my $i_am = (caller(0))[3] . '()' ;

    # build the URL we need to get our information

    my $base_url = "https://voip.ms/api/v1/rest.php" .
        "?api_username=${userid}&api_password=${password}&method=${method}" ;

    my $ref = ref( $fields_ref ) ;
    if (( not defined( $ref )) or ( $ref ne 'HASH' )) {
        error( "5th arg to $i_am is not a HASH reference", $C_FATAL ) ;
    }

    my $extra_fields = "" ;
    my @keys = keys( %{$fields_ref} ) ;
    foreach my $key ( @keys ) {
        my $val = ${$fields_ref}{$key} ;
        $extra_fields .= "&${key}=${val}" ;
    }
    my $url = $base_url . $extra_fields ;
    dprint( "$i_am: URL = \'$url\'" ) ;

    my $ua = LWP::UserAgent->new( timeout => $timeout );

    # you need to look like a browser to get past Cloudflare
    $ua->default_header( 'User-Agent' => 'Mozilla/5.0' ) ;
    $ua->cookie_jar( {} ) ;     # maybe needed by Cloudflare in future?
    $ua->env_proxy;
    my $response = $ua->get( $url ) ;

    my $response_body;
    if ( $response->is_success ) {
        $response_body = $response->decoded_content ;
    } else {
        error( $response->status_line, $C_FATAL ) ;
    }

    # decode the JSON
    if ( $response_body !~ /^\{/ ) {
        error( "No JSON structure returned", $C_FATAL ) ;
    }
    my $json = decode_json( $response_body ) ;

    my $status = $json->{ 'status' } ;
    if ( not defined( $status )) {
        error( "could not get \'status\' in JSON return", $C_FATAL ) ;
    }
    dprint( "$i_am: status from API call = $status" ) ;
    if ( $status ne "success" ) {
        error( "failed status returned: $status", $C_FATAL ) ;
    }
    return( $json ) ;
}


# extract the data we need for the return data from the voip.ms API.
# The 2nd argument is the reference to the HASH containing keys of
# data we are interested in, all with values set to undef.  Those
# values will be updated with data collected from the hash reference
# in the 1st argument.  All of the keys provided must end up having
# their values set for the call to be considered successful.
#
# Args:
#   1: reference to hash of data returned by voip.ms API call
#   2: reference to hash of data we are interested in
# Returns:
#   0:  OK
#   1:  not OK

sub get_fields {
    my $data_ref   = shift ;
    my $fields_ref = shift ;

    my $num_entries = 0 ;
    my @lines = () ;

    # there should only be 1 entry in this array

    foreach my $hash_ref ( @{$data_ref} ) {
        my $line = ${$hash_ref}{ 'did' } ;
        continue if ( not defined( $line )) ;
        push( @lines, $line ) ;

        $num_entries++ ;

        my @keys = keys( %{$hash_ref} ) ;
        foreach my $key ( @keys ) {
            my $val = ${$hash_ref}{ $key } ;
            $val = "undefined" if ( not defined( $val )) ;

            if ( exists( ${$fields_ref}{ $key } )) {
                ${$fields_ref}{ $key } = $val ;
            }
        }
    }
    my $num_errs = 0 ;
    if ( $num_entries > 1 ) {
        error( "Got more than 1 entry in data", $C_WARNING ) ;
        error( "lines found: @lines", $C_WARNING ) ;
        $num_errs++ ;
    }

    my @keys = keys( %{$fields_ref} ) ;
    foreach my $key ( @keys ) {
        if ( not defined( ${$fields_ref}{ $key } )) {
            error( "required key for '$key' not found", $C_WARNING ) ;
            $num_errs++ ;
        }
    }
    return(1) if ( $num_errs ) ;
    return(0) ;
}


# debug print
# Arguments:
#     1: string to print
# Returns:
#     0
# Globals:
#     $G_debug_flag

sub dprint {
    my $msg = shift ;
    return(0) if ( $G_debug_flag == 0 ) ;

    print "debug: $msg\n" ;
    return(0) ;
}


# find the config file we really want and that exists
# accept the *last* existing one in the order of:
#   $ENV{ HOME }/.voip-ms.conf
#   $ENV{ VOIP_MS_CONFIG_FILE }
#   given by opition -c or --config
#
# Arguments:
#     1:  value given with option to program
# Returns:
#     config-file (which could be undef)

sub find_config_file {
    my $config_option = shift ;

    my @configs = () ;
    my $final_config = undef ;

    # first the HOME directory
    my $home = $ENV{ HOME } ;
    push( @configs, "${home}/.voip-ms.conf" ) ;

    # next an environment variable
    my $c = $ENV{ 'VOIP_MS_CONFIG_FILE' } ;
    push( @configs, $c ) if ( defined( $c )) ;

    # finally if an over-riding option was given
    push( @configs, $config_option ) if defined( $config_option ) ;

    # accept the last one found that exists
    foreach my $c ( @configs ) {
        $final_config = $c if ( -f $c ) ;
    }
    return( $final_config ) ;
}


# print an error.
# exit the program if a flag (2nd arg) is $C_FATAL.
# default to $C_FATAL if flag not given.
#
# Args:
#   1: string to print to STDERR
#   2: optional flag, default to $C_FATAL
# Returns:
#   0 - if the program does not exit because of $C_FATAL
# Globals:
#     $G_progname

sub error {
    my $str = shift ;
    my $flag = shift ;

    $flag = $C_FATAL if ( not defined( $flag )) ;

    print STDERR "$G_progname: $str\n" ;
    exit(1) if ( $flag eq $C_FATAL ) ;
    return(0) ;
}
