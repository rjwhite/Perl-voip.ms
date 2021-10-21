#!/usr/bin/env perl

# black-list a phone number with the voip.ms service
# Uses a config file for authentication and defaults

# Needs LWP::UserAgent from CPAN

# Needs Moxad::Config found on github.com under user rjwhite
#   https://github.com/rjwhite/Perl-config-module

# black-list --help      ( print usage )
# black-list             ( print the list of filters along with rule IDs )
# black-list --busy   --note 'DickHeads Inc'  4165551212 ( add an entry )
# black-list --hangup --note 'DickHeads Inc'  --filterid 12345  4165551212
# black-list -X -f 12345 ( delete rule with filter ID 12345 )

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
use LWP::UserAgent();
use URI::Escape ;
use JSON ;

# Globals 
my $G_progname   = $0 ;
my $G_version    = "v0.11" ;
my $G_debug      = 0 ;

my $C_ROUTING_NO_SERVICE   = "noservice" ;
my $C_ROUTING_BUSY         = "busy" ;
my $C_ROUTING_HANG_UP      = "hangup" ;
my $C_ROUTING_DISCONNECTED = "disconnected" ;

my $C_DEFAULT_TIMEOUT = 30  ;

$G_progname     =~ s/^.*\/// ;

if ( main() ) {
    exit(1) ;
} else {
    exit(0) ;
}



sub main {
    my $config_file = undef ;
    my $method = "setCallerIDFiltering" ;
    my %routing_types = (
        $C_ROUTING_NO_SERVICE   => 1,
        $C_ROUTING_BUSY         => 1,
        $C_ROUTING_HANG_UP      => 1,
        $C_ROUTING_DISCONNECTED => 1,
    ) ;
    my $routing_default = $C_ROUTING_NO_SERVICE ;
    my $routing      = undef ;
    my $error        = "" ;
    my $caller_id    = "" ;
    my $filtering_id = "" ;

    my $print_flag   = 0 ;
    my $delete_flag  = 0 ;
    my $set_flag     = 0 ;
    my $help_flag    = 0 ;

    my %defaults = (
        'note'      => "Added by $G_progname program",
        'routing'   => $routing_default,
        'did'       => "unknown",
        'callerid'  => "unknown",
        'timeout'   => $C_DEFAULT_TIMEOUT,
    ) ;
    my %new_values = () ;
    my %options    = () ;

    # get options

    for ( my $i = 0 ; $i <= $#ARGV ; $i++ ) {
        my $arg = $ARGV[ $i ] ;
        if (( $arg eq "-h" ) or ( $arg eq "--help" )) {
            $help_flag++ ;
        } elsif (( $arg eq "-V" ) or ( $arg eq "--version" )) {
            print "Program version: $G_version\n" ;
            print "Config module version: $Moxad::Config::VERSION\n" ;
            return(0) ;
        } elsif (( $arg eq "-d" ) or ( $arg eq "--debug" )) {
            $G_debug++ ;
        } elsif (( $arg eq "-X" ) or ( $arg eq "--delete" )) {
            $delete_flag++ ;
        } elsif (( $arg eq "-n" ) or ( $arg eq "--note" )) {
            $options{ 'note' } = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-r" ) or ( $arg eq "--routing" )) {
            $options{ 'routing' } = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-B" ) or ( $arg eq "--busy" )) {
            $options{ 'routing' } = 'busy' ;
        } elsif (( $arg eq "-N" ) or ( $arg eq "--noservice" )) {
            $options{ 'routing' } = 'noservice' ;
        } elsif (( $arg eq "-H" ) or ( $arg eq "--hangup" )) {
            $options{ 'routing' } = 'hangup' ;
        } elsif (( $arg eq "-l" ) or ( $arg eq "--line" )) {
            $options{ 'did' } = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-D" ) or ( $arg eq "--disconnected" )) {
            $options{ 'routing' } = 'disconnected' ;
        } elsif (( $arg eq "-c" ) or ( $arg eq "--config" )) {
            $config_file = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-f" ) or ( $arg eq "--filterid" )) {
            $filtering_id = $ARGV[ ++$i ] ;
        } elsif ( $arg =~ /^\-/ ) {
            print STDERR "$G_progname: unknown option: $arg\n" ;
            return(1) ;
        } else {
            if ( $caller_id ne "" ) {
                my $err = "already provided a callerid: $caller_id" ;
                print STDERR "$G_progname: $err\n" ;
                return(1) ;
            }
            $caller_id = $ARGV[ $i ] ;
        }
    }

    if (( defined( $options{ 'routing' } )) or 
        ( defined( $options{ 'did' } )) or
        ( defined( $options{ 'note' } ))) {
            dprint( "SET flag set (changing/setting values)" ) ;
            $set_flag++ ;
    }

    if ( $caller_id eq "" ) {
        dprint( "No Caller ID given" ) ;
        if ( $delete_flag ) {
            if ( $filtering_id eq "" ) {
                my $err = "Need to provide filter ID to delete an entry" ;
                print STDERR "$G_progname: $err\n" ;
                return(1) ;
            }
            $method = "delCallerIDFiltering" ;
        } else {
            if ( $set_flag ) {
                    # should be making modifications to an exsiting rule
                    if ( $filtering_id eq "" ) {
                        my $err = "Need to provide filter ID to modify " .
                                  "an entry" ;
                        print STDERR "$G_progname: $err\n" ;
                        return(1) ;
                    }
                    $method = "setCallerIDFiltering" ;
            } else {
                $print_flag++ ;
                $method = "getCallerIDFiltering" ;
            }
        }
    } else {
        dprint( "Caller ID given: $caller_id" ) ;
        if ( $delete_flag ) {
            my $err = "huh?!  You gave a --delete option as well!" ;
            print STDERR "$G_progname: $err\n" ;
            return(1) ;
        }
        $method = "setCallerIDFiltering" ;
        $caller_id =~ s/-//g ;      # remove dashes
        $caller_id =~ s/ //g ;      # remove any spaces
        if ( $caller_id !~ /^\d+$/ ) {
            print STDERR "$G_progname: invalid callerid: $caller_id\n" ;
            return(1) ;
        }
    }

    # find the config file we really want

    $config_file = find_config_file( $config_file ) ;
    if ( not defined( $config_file )) {
        print STDERR "$G_progname: no config file found\n" ;
        return(1) ;
    }
    dprint( "using config file: $config_file" ) ;

    # read in config data

    # show config debug if -d/--debug flag used more than once
    my $config_debug = 0 ;
    $config_debug = 1 if ( $G_debug > 1 ) ;

    Moxad::Config->set_debug( $config_debug ) ;
    my $cfg1 = Moxad::Config->new(
        $config_file, "",
        { 'AcceptUndefinedKeywords' => 'no' } ) ;
    if ( $cfg1->errors() ) {
        my @errors = $cfg1->errors() ;
        foreach my $error ( @errors ) {
            print STDERR "$G_progname: $error\n" ;
        }
        return(1) ;
    }
    dprint( "Config data read ok" ) ;

    # sanity checking required sections

    my %got_sections = () ;
    my @needed_sections = ( 'authentication', 'black-list' ) ;
    my @sections = $cfg1->get_sections() ;
    foreach my $section ( @sections ) {
        $got_sections{ $section } = 1 ;
    }
    my $num_errors = 0 ;
    foreach my $section ( @needed_sections ) {
        if ( not defined( $got_sections{ $section } )) {
            my $err = "missing section \'$section\' in $config_file" ;
            print STDERR "$G_progname: $err\n" ;
            $num_errors++ ;
        }
    }
    return(1) if ( $num_errors ) ;

    # values in config file over-ride defaults

    my @keywords = $cfg1->get_keywords( 'black-list' ) ;
    # get all the data we have in the config file
    foreach my $keyword ( @keywords ) {
        my $value = $cfg1->get_values( 'black-list', $keyword ) ;
        $defaults{ $keyword } = $value ;
        dprint( "setting \'$keyword\' to $value from config file" ) ;
    }

    # we defer printing out the help info till after we have set defaults
    # and read our config file, so we can see defaults in the usage printed

    if ( $help_flag ) {
        my $routing_str = "${C_ROUTING_NO_SERVICE}|${C_ROUTING_BUSY}|" .
                          "${C_ROUTING_HANG_UP}|${C_ROUTING_DISCONNECTED} " .
                          "(default=$routing_default)" ;
        printf "usage: %s [options]* caller-id\n" .
            "%s %s %s %s %s %s %s %s %s %s %s %s %s",
            $G_progname,
            "\t[-c|--config]        config-file (default=$config_file)\n",
            "\t[-d|--debug]         (debugging output)\n",
            "\t[-f|--filterid]      number (existing rule filter ID to change rule)\n",
            "\t[-h|--help]          (help)\n",
            "\t[-l|--line]          DID-phone-number (default=$defaults{ 'did' })\n",
            "\t[-n|--note]          string\n",
            "\t[-r|--routing]       $routing_str\n",
            "\t[-B|--busy]          (routing=sys:busy)\n",
            "\t[-D|--disconnected]  (routing=sys:disconnected)\n",
            "\t[-H|--hangup]        (routing=sys:hangup)\n",
            "\t[-N|--noservice]     (routing=sys:noservice)\n",
            "\t[-V|--version]       (print version of this program)\n",
            "\t[-X|--delete]        (delete an entry. Also needs --filterid)\n" ;

        return(0) ;
    }

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
            print STDERR "$G_progname: $error\n" ;
        }
        return(1) ;
    }

    my $user   = $auth_values{ 'user' } ;
    my $pass   = $auth_values{ 'pass' } ;

    dprint( "user     = $user" ) ;
    dprint( "method   = $method" ) ;

    # finally...  build the base URL we need

    my $base_url = "https://voip.ms/api/v1/rest.php" .
        "?api_username=${user}&api_password=${pass}" ;

    my $url ;
    # if we want to print entries
    if ( $print_flag ) {
        $url = $base_url . "&method=${method}" ;
        if ( $filtering_id ne "" ) {
            # want to print a specific rule
            $url .= "&filtering=${filtering_id}" ;
        }
    } elsif ( $delete_flag ) {
        $url = $base_url . "&method=${method}&filtering=${filtering_id}" ;
    } elsif ( $set_flag ) {
        if ( $caller_id ne "" ) {
            # we are creating a new rule
            # make sure we have all the values we need

            foreach my $field ( keys( %defaults )) {
                # first grab the defaults - which were over-ridden by the 
                # config file
                if ( not defined( $new_values{ $field } )) {
                    my $default = $defaults{ $field } ;
                    dprint( "Setting default for $field of \'$default\'" ) ;
                    $new_values{ $field } = $default ;
                }

                # options given over-ride these defaults
                if ( defined( $options{ $field } )) {
                    my $value = $options{ $field } ;
                    my $msg = "Overriding default with option for $field " .
                               "with $value" ;
                    dprint( $msg ) ;
                    $new_values{ $field } = $value ;
                }
            }
            $new_values{ 'callerid' } = $caller_id ;
        } else {
            # we need to grab existing values for other stuff and preserve them

            my $old_values_ref ;
            my @errors = () ;
            $url =  $base_url .
                    "&method=getCallerIDFiltering&filtering=$filtering_id" ;

            my $ret = send_request( $url, \@errors, \$old_values_ref,
                                    $defaults{ 'timeout' } ) ;
            if ( $ret ) {
                if ( @errors == 0 ) {
                    my $err = "Arg 2 to send_request() must be bad" ;
                    print STDERR "${G_progname}: $err\n" ;
                    return(1) ;
                }
                foreach my $error ( @errors ) {
                    print STDERR "${G_progname}: $error\n" ;
                }
                return(1) ;
            }

            # there should only be 1 entry.  check for that.
            my $filtering = ${$old_values_ref}->{ 'filtering' } ;
            my $num_entries = @{$filtering} ;
            if ( $num_entries != 1 ) {
                my $err = "Got $num_entries instead of expected 1" ;
                print STDERR "${G_progname}: $err\n" ;
                return(1) ;
            }
            my $entry_ref = ${$filtering}[0] ;

            # now over-ride any new values we gave as options
            foreach my $field ( keys( %{$entry_ref} )) {
                my $value = ${$entry_ref}{ $field } ;
                dprint( "Got old value of \'$value\' for $field" ) ;

                if ( defined( $defaults{ $field } )) {
                    my $msg = "Replacing default value for \'$field\' with " .
                              "old value of \'$value\'" ;
                    dprint( $msg ) ;
                    $defaults{ $field } = $value ;

                    if ( defined( $options{ $field } )) {
                        $value = $options{ $field } ;
                        my $msg = "Now Replacing default value for " .
                                  "\'$field\' with \'$value\'from options" ;
                        dprint( $msg ) ;
                        $defaults{ $field } = $value ;
                    }
                }
            }
            # now copy over our over-ridden defaults to new_values
            %new_values = %defaults ;
        }

        # now a bunch of common code for changing a rule or creating a new one
        # At this point, we have the values we want in the hash %new_values

        # verify routing is OK

        my $routing = $new_values{ 'routing' } ;
        $routing =~ tr/A-Z/a-z/ ;       # make lower case
        $routing =~ s/^sys:// ;         # in case the user already gave the prefix
        if ( not defined( $routing_types{ $routing } )) {
            print STDERR "$G_progname: Invalid routing type: \'$routing\'\n" ;
            return(1) ;
        }
        # prefix routing type
        $routing = "sys:${routing}" ;

        # escape needed strings
        my $note = $new_values{ 'note' } ;
        $note    = URI::Escape::uri_escape( $note ) ;

        my $did       = $new_values{ 'did' } ;
        my $caller_id = $new_values{ 'callerid' } ;

        $url =  $base_url . "&method=${method}" .
                "&note=${note}&routing=${routing}" .
                "&callerid=${caller_id}&did=${did}" ;

        # note that it's 'filter' and not 'filtering'.  sheesh...
        $url .= "&filter=${filtering_id}" if ( $filtering_id ne "" ) ;
    } else {
        # can't happen...
        my $err = "Unclear what operation is being attempted" ;
        print STDERR "${G_progname}: $err\n" ;
        return(1) ;
    }

    # finally ready to send the request

    my @errors = () ;
    my $json_ref ;
    my $ret = send_request( $url, \@errors, \$json_ref, 
                            $defaults{ 'timeout' } ) ;
    if ( $ret ) {
        if ( @errors == 0 ) {
            my $err = "Arg 2 to send_request() must be bad" ;
            print STDERR "${G_progname}: $err\n" ;
            return(1) ;
        }
        foreach my $error ( @errors ) {
            print STDERR "${G_progname}: $error\n" ;
        }
        return(1) ;
    }

    return(0) if ( $set_flag ) ;        # we're done
    return(0) if ( $delete_flag ) ;     # ditto.

    my $filtering = ${$json_ref}->{ 'filtering' } ;
    if (( $print_flag == 0 ) and ( $delete_flag == 0 )) {
        # setting a filter rule
        if ( not defined( $filtering )) {
            my $err = "Could not get filtering ID from returned JSON data" ;
            print STDERR "$G_progname: $err\n" ;
            return(1) ;
        }
        dprint( "filtering ID number = $filtering" ) ;
    }

    if ( $print_flag ) {
        # find out how many entries we have and the max length of 'note'
        my $num_filters = 0 ;
        my $max_note_len = 0 ;
        foreach my $entry ( @{$filtering} ) {
            $num_filters++ ;
            my $note = $entry->{ 'note' } ;
            my $len_note = length( $note ) ;
            $max_note_len = $len_note if ( $len_note > $max_note_len ) ;
        }

        # print a title if we have some entries
        if ( $num_filters ) {
            printf "%-12s %-12s %-20s %-10s %s\n",
                'CallerID', 'line', 'Routing', 'Filter#', 'Note' ;
            printf "%-12s %-12s %-20s %-10s %s\n",
                '-' x 10, '-' x 10, '-' x 15, '-' x 7, '-' x $max_note_len ;
        }

        foreach my $entry ( @{$filtering} ) {
            my %things = (
                'did'       => 'unknown',
                'note'      => '',
                'routing'   => 'unknown',
                'filtering' => 'unknown',
                'callerid'  => 'unknown',
            ) ;

            foreach my $key ( keys( %{$entry} )) {
                my $value = $entry->{ $key } ;
                $things{ $key } = $value ;
            }

            my $caller_id   = $things{ 'callerid' } ;
            my $did         = $things{ 'did' } ;
            my $routing     = $things{ 'routing' } ;
            my $note        = $things{ 'note' } ;
            my $filter_id   = $things{ 'filtering' } ;

            printf "%-12s %-12s %-20s %-10d %s\n",
                $caller_id, $did, $routing, $filter_id, $note ;
        }
    }

    return(0) ;
}


# send a URL request
#
# Arguments:
#   1:  URL
#   2:  reference to array of errors to return
#   3:  reference of JSON data to return
#   4:  timeout - defaults to $C_DEFAULT_TIMEOUT secs
# Returns:
#   0:  ok
#   1:  error
# Globals:
#   none

sub send_request {
    my $url       = shift ;
    my $error_ref = shift ;
    my $json_ref  = shift ;
    my $timeout   = shift ;

    my $i_am = "send_request()" ;

    # sanity checking of arguments
    if (( ref( $error_ref ) eq "" ) or ( ref( $error_ref ) ne "ARRAY" )) {
        return(1) ;
    }
    if (( not defined( $url )) or ( $url eq "" )) {
        my $msg = "${i_am}: (Arg 1) URL is undefined or empty string" ;
        push( @{$error_ref}, $msg ) ;
        return(1) ;
    }
    if (( ref( $json_ref ) eq "" ) or ( ref( $json_ref ) ne "SCALAR" )) {
        my $err = "${i_am}: Arg 3 is not a SCALAR reference to return data" ;
        push( @{$error_ref},  $err ) ;
        return(1) ;
    }

    if (( not defined( $timeout )) or ( $timeout eq "" )) {
        $timeout = $C_DEFAULT_TIMEOUT ;
    }

    if ( $timeout !~ /^\d+$/ ) {
        my $err = "${i_am}: timeout ($timeout) is non-numeric" ;
        push( @{$error_ref}, $err ) ;
        return(1) ;
    }

    dprint( "${i_am}: URL = \'$url\'" ) ;
    dprint( "${i_am}: using timeout = \'$timeout\'" ) ;

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
        my $reason = $response->status_line ;
        push( @{$error_ref},  "${i_am}: $reason" ) ;
        return(1) ;
    }

    # decode the JSON

    if ( $response_body !~ /^\{/ ) {
        push( @{$error_ref},  "${i_am}: No JSON structure returned" ) ;
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
#     1:  message
# Returns:
#     0
# Globals:
#     $G_debug

sub dprint {
    my $msg = shift ;
    return(0) if ( $G_debug == 0 ) ;

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
# Globals:
#     none

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
