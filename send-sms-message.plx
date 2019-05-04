#!/usr/bin/env perl

# send a SMS message
# Uses a config file for authentication and defaults

# Needs WWW::Curl from CPAN.
# That will complain that you must install curl-config, which you can do 
# on a Linix Mint system with: 'apt-get install libcurl4-gnutls-dev'

# Needs Moxad::Config found on github.com under user rjwhite
#   https://github.com/rjwhite/Perl-config-module

# send-sms-message --help
# send-sms-message --recipient 555-123-4567 pick up some batter-tarts

# Copyright 2018 RJ White
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
use lib "/usr/local/Moxad/lib" ;
use Moxad::Config ;
use WWW::Curl::Easy ;
use URI::Escape ;
use JSON ;

# Globals 
my $G_progname   = $0 ;
my $G_version    = "v0.2" ;
my $G_debug      = 0 ;

$G_progname     =~ s/^.*\/// ;

if ( main() ) {
    exit(1) ;
} else {
    exit(0) ;
}



sub main {
    my $home        = $ENV{ HOME } ;
    my $config_file = "${home}/.voip-ms.conf" ;
    my $method      = "sendSMS" ;
    my $error       = "" ;

    my $help_flag    = 0 ;
    my $no_send_flag = 0 ;

    my %defaults = (
        'did'       => undef,
        'recipient' => undef,
    ) ;

    my $message = "" ;

    # get options

    my %options = () ;
    for ( my $i = 0 ; $i <= $#ARGV ; $i++ ) {
        my $arg = $ARGV[ $i ] ;
        if (( $arg eq "-h" ) or ( $arg eq "--help" )) {
            $help_flag++ ;
        } elsif (( $arg eq "-V" ) or ( $arg eq "--version" )) {
            print "version: $G_version\n" ;
            return(0) ;
        } elsif (( $arg eq "-d" ) or ( $arg eq "--debug" )) {
            $G_debug++ ;
        } elsif (( $arg eq "-n" ) or ( $arg eq "--no-send" )) {
            $no_send_flag++ ;
        } elsif (( $arg eq "-l" ) or ( $arg eq "--line" )) {
            $options{ 'did' } = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-r" ) or ( $arg eq "--recipient" )) {
            $options{ 'recipient' } = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-c" ) or ( $arg eq "--config" )) {
            $config_file = $ARGV[ ++$i ] ;
        } elsif ( $arg =~ /^\-/ ) {
            print STDERR "$G_progname: unknown option: $arg\n" ;
            return(1) ;
        } else {
            $message .= $ARGV[ $i ] . " " ;
        }
    }

    # read in config data

    Moxad::Config->set_debug( 0 ) ;
    my $cfg1 = Moxad::Config->new(
        $config_file, "",
        { 'AcceptUndefinedKeywords' => 'no' } ) ;
    if ( $cfg1->errors() ) {
        my @errors = $cfg1->errors() ;
        foreach my $error ( @errors ) {
            print "$G_progname: $error\n" ;
        }
        return(1) ;
    }
    dprint( "Config data read ok" ) ;

    # sanity checking required sections

    my %got_sections = () ;
    my @needed_sections = ( 'authentication', 'sms' ) ;
    my @sections = $cfg1->get_sections() ;
    foreach my $section ( @sections ) {
        $got_sections{ $section } = 1 ;
    }
    my $num_errors = 0 ;
    foreach my $section ( @needed_sections ) {
        if ( not defined( $got_sections{ $section } )) {
            print STDERR "$G_progname: missing section \'$section\' in $config_file\n" ;
            $num_errors++ ;
        }
    }
    return(1) if ( $num_errors ) ;

    # values in config file over-ride defaults

    my @keywords = $cfg1->get_keywords( 'sms' ) ;
    # get all the data we have in the config file
    foreach my $keyword ( @keywords ) {
        my $type = $cfg1->get_type( 'sms', $keyword ) ;
        if ( $type eq 'scalar' ) {
            $defaults{ $keyword } = $cfg1->get_values( 'sms', $keyword ) ;
        } elsif ( $type eq 'array' ) {
            @{$defaults{ $keyword }} = $cfg1->get_values( 'sms', $keyword ) ;
        } elsif ( $type eq 'hash' ) {
            %{$defaults{ $keyword }} = $cfg1->get_values( 'sms', $keyword ) ;
        }
    }

    # options on command line over-ride everything else
    my %values = %defaults ;
    foreach my $thing ( keys( %options )) {
        my $value = $options{ $thing } ;
        $values{ $thing } = $value ;
        dprint( "over-writing default of \'$thing\' with \'$value\'" ) ;
    }

    # now that the dust has settled with defaults, config values and options...
    if ( $help_flag ) {
        printf "usage: %s [options]* message-to-send\n" .
            "%s %s %s %s %s %s",
            $G_progname,
            "\t[-c|--config file]   (config-file. default=$config_file)\n",
            "\t[-d|--debug]         (debugging output)\n",
            "\t[-n|--no-send]       (don't send the message, but show URL to send)\n",
            "\t[-h|--help]          (help)\n",
            "\t[-l|--line]          sender DID-phone-number (default=$values{ 'did' })\n", 
            "\t[-V|--version]       (print version)\n",
            "\t-r|--recipient phone-number\n" ;

        return(0) ;
    }

    # check for missing needed values

    foreach my $thing ( keys( %values )) {
        if ( not defined( $values{ $thing } )) {
            print STDERR "$G_progname: need to provide --$thing option\n" ;
            $num_errors++ ;
        }
    }
    if ( $message eq "" ) {
        print STDERR "$G_progname: need to provide a message to send\n" ;
        $num_errors++ ;
    }
    $message =~ s/ $// ;     # remove trailing space we added

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
            print "$G_progname: $error\n" ;
        }
        return(1) ;
    }

    my $user = $auth_values{ 'user' } ;
    my $pass = $auth_values{ 'pass' } ;

    dprint( "user    = $user" ) ;
    dprint( "method  = $method" ) ;

    # finally...  build the base URL we need

    my $url = "https://voip.ms/api/v1/rest.php" .
        "?api_username=${user}&api_password=${pass}" ;

    # get the DID - the line the message will come from

    my $did = $values{ 'did' } ;

    # see if there are any aliases, and if one was used

    my $recipient = $values{ 'recipient' } ;
    if ( defined( $values{ 'aliases' } )) {
        my %aliases = %{$values{ 'aliases' }} ;
        foreach my $alias ( keys( %aliases )) {
            if ( $recipient eq $alias ) {
                dprint( "MATCHED alias of RECIPIENT \'$recipient\'" ) ;
                $recipient = $aliases{ $alias } ;
                dprint( "RECIPIENT changed to \'$recipient\'" ) ;
            }
            if ( $did eq $alias ) {
                dprint( "MATCHED alias of DID \'$did\'" ) ;
                $did = $aliases{ $alias } ;
                dprint( "DID changed to \'$did\'" ) ;
            }
        }
    } else {
        dprint( "No aliases defined" ) ;
    }

    # remove any dashes from phone numbers
    $did       =~ s/-//g ;
    $recipient =~ s/-//g ;

    if ( $recipient !~ /^\d+$/ ) {
        print "$G_progname: recipient ($recipient) must be a phone number\n" ;
        return(1) ;
    }
    if ( $did !~ /^\d+$/ ) {
        print "$G_progname: DID ($did) must be a phone number\n" ;
        return(1) ;
    }

    $message = URI::Escape::uri_escape( $message ) ;

    $url .= "&method=${method}&dst=${recipient}&did=${did}&message=${message}" ;
    dprint( "URL = $url" ) ;

    if ( $no_send_flag ) {
        print "URL to send: $url\n" ;
        return(0) ;
    }

    # finally ready to send the request

    my @errors = () ;
    my $json_ref ;
    my $ret = send_request( $url, \@errors, \$json_ref ) ;
    if ( $ret ) {
        if ( @errors == 0 ) {
            print STDERR "${G_progname}: Arg 2 to send_request() must be bad\n" ;
            return(1) ;
        }
        foreach my $error ( @errors ) {
            print STDERR "${G_progname}: $error\n" ;
        }
        return(1) ;
    }
    return(0) ;
}



# send a URL request
#
# Arguments:
#   1:  URL
#   2:  reference to array of errors to return
#   3:  reference of JSON data to return
# Returns:
#   0:  ok
#   1:  error
# Globals:
#   none

sub send_request {
    my $url       = shift ;
    my $error_ref = shift ;
    my $json_ref  = shift ;

    my $i_am = "send_request()" ;

    # sanity checking of arguments
    if (( ref( $error_ref ) eq "" ) or ( ref( $error_ref ) ne "ARRAY" )) {
        return(1) ;
    }
    if (( not defined( $url )) or ( $url eq "" )) {
        push( @{$error_ref},  "${i_am}: (Arg 1) URL is undefined or empty string" ) ;
        return(1) ;
    }
    if (( ref( $json_ref ) eq "" ) or ( ref( $json_ref ) ne "SCALAR" )) {
        push( @{$error_ref},  "${i_am}: Arg 3 is not a SCALAR reference to return data" ) ;
        return(1) ;
    }

    dprint( "${i_am}: URL = \'$url\'" ) ;

    my $curl = WWW::Curl::Easy->new();
    if ( ! $curl ) {
        push( @{$error_ref}, "${i_am}: WWW::Curl::Easy->new() failed" ) ;
        return(1) ;
    }

    $curl->setopt( CURLOPT_HEADER, 0 );
    $curl->setopt( CURLOPT_URL, $url ) ;

    my $response_body;
    $curl->setopt( CURLOPT_WRITEDATA, \$response_body) ;

    my $retcode = $curl->perform() ;
    if ( $retcode ) {
        push( @{$error_ref},  "${i_am}: " . $curl->strerror($retcode) . " ($retcode)" ) ;
        push( @{$error_ref}, "${i_am}: errbuf: " . $curl->errbuf . "\n" ) ;
        return(1) ;
    }

    my $json = decode_json( $response_body ) ;

    my $status = $json->{ 'status' } ;
    dprint( "status = $status" ) ;
    if ( $status ne "success" ) {
        my $reason = $status ;
        if ( $status eq "used_filter" ) {
            $reason = "Filter number already in use" ;
        }
        push( @{$error_ref},  "${i_am}: Failed status: $reason" ) ;
        return(1) ;
    }
    ${$json_ref} = \$json ;
    return(0) ;
}



# debug print
#
# Arguments:
#   1:  message
# Returns:
#   0
# Globals:
#   $G_debug

sub dprint {
    my $msg = shift ;
    return(0) if ( $G_debug == 0 ) ;

    print "$msg\n" ;
    return(0) ;
}
