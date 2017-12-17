#!/usr/bin/env perl

# black-list a phone number with the voip.ms service
# Uses a config file for authentication and defaults

# Needs WWW::Curl from CPAN.
# That will complain that you must install curl-config, which you can do 
# on a Linix Mint system with: 'apt-get install libcurl4-gnutls-dev'

# Needs Moxad::Config found on github.com under user rjwhite

# black-list.plx --help      ( print usage )
# black-list.plx             ( print the list of filters along with rule IDs )
# black-list.plx -X -f 12345 ( delete rule with filter ID 12345 )
# black-list.plx  --busy   --note 'DickHeads Inc'  4165551212 
# black-list.plx  --hangup --note 'DickHeads Inc'  --filterid 12345  4165551212


# Copyright 2017 RJ White
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
my $G_version    = "v0.1" ;
my $G_debug      = 0 ;

my $C_ROUTING_NO_SERVICE   = "noservice" ;
my $C_ROUTING_BUSY         = "busy" ;
my $C_ROUTING_HANG_UP      = "hangup" ;
my $C_ROUTING_DISCONNECTED = "disconnected" ;

$G_progname     =~ s/^.*\/// ;

if ( main() ) {
    exit(1) ;
} else {
    exit(0) ;
}



sub main {
    my $home        = $ENV{ HOME } ;
    my $config_file = "${home}/.voip-ms.conf" ;
    my $method      = "setCallerIDFiltering" ;
    my %routing_types   = (
        $C_ROUTING_NO_SERVICE   => 1,
        $C_ROUTING_BUSY         => 1,
        $C_ROUTING_HANG_UP      => 1,
        $C_ROUTING_DISCONNECTED => 1,
    ) ;
    my %black_list_keywords = () ;
    my $routing_default = $C_ROUTING_NO_SERVICE ;
    my $routing      = undef ;
    my $caller_id    = "" ;
    my $filtering_id = "" ;
    my $print_flag   = 0 ;
    my $delete_flag  = 0 ;

    my %defaults = (
        'note'      => "Added by $G_progname program",
        'routing'   => $routing_default,
        'callerid'  => undef,
        'did'       => undef,
    ) ;
    my %values = () ;
    my $error ;

    # get options

    for ( my $i = 0 ; $i <= $#ARGV ; $i++ ) {
        my $arg = $ARGV[ $i ] ;
        if (( $arg eq "-h" ) or ( $arg eq "--help" )) {
            my $routing_str = "${C_ROUTING_NO_SERVICE}|${C_ROUTING_BUSY}|" .
                              "${C_ROUTING_HANG_UP}|${C_ROUTING_DISCONNECTED} " .
                              "(default=$routing_default)" ;
            printf "usage: %s [options]* caller-id\n" .
                "%s %s %s %s %s %s %s %s %s %s %s %s %s %s",
                $G_progname,
                "\t[-c|--config]        config-file\n",
                "\t[-d|--debug]         (debugging output)\n",
                "\t[-f|--filterid]      number (existing rule filter ID to change rule)\n",
                "\t[-h|--help]          (help)\n",
                "\t[-l|--line]          phone-number (which line)\n",
                "\t[-n|--note]          string\n",
                "\t[-r|--routing]       $routing_str\n",
                "\t[-s|--sheldon]\n",
                "\t[-B|--busy]          (routing=sys:busy)\n",
                "\t[-D|--disconnected]  (routing=sys:disconnected)\n",
                "\t[-H|--hangup]        (routing=sys:hangup)\n",
                "\t[-N|--noservice]     (routing=sys:noservice)\n",
                "\t[-V|--version]       (print version of this program)\n",
                "\t[-X|--delete]        (delete an entry. Also needs --filterid)\n" ;

            return(0) ;
        } elsif (( $arg eq "-V" ) or ( $arg eq "--version" )) {
            print "version: $G_version\n" ;
            return(0) ;
        } elsif (( $arg eq "-d" ) or ( $arg eq "--debug" )) {
            $G_debug++ ;
        } elsif (( $arg eq "-X" ) or ( $arg eq "--delete" )) {
            $delete_flag++ ;
        } elsif (( $arg eq "-n" ) or ( $arg eq "--note" )) {
            $values{ 'note' } = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-r" ) or ( $arg eq "--routing" )) {
            $values{ 'routing' } = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-B" ) or ( $arg eq "--busy" )) {
            $values{ 'routing' } = 'busy' ;
        } elsif (( $arg eq "-N" ) or ( $arg eq "--noservice" )) {
            $values{ 'routing' } = 'noservice' ;
        } elsif (( $arg eq "-H" ) or ( $arg eq "--hangup" )) {
            $values{ 'routing' } = 'hangup' ;
        } elsif (( $arg eq "-l" ) or ( $arg eq "--line" )) {
            $values{ 'did' } = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-D" ) or ( $arg eq "--disconnected" )) {
            $values{ 'routing' } = 'disconnected' ;
        } elsif (( $arg eq "-c" ) or ( $arg eq "--config" )) {
            $config_file = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-f" ) or ( $arg eq "--filterid" )) {
            $filtering_id = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-s" ) or ( $arg eq "--sheldon" )) {
            print "Bazinga!\n" ;
            return(0) ;
        } elsif ( $arg =~ /^\-/ ) {
            print STDERR "$G_progname: unknown option: $arg\n" ;
            return(1) ;
        } else {
            if ( $caller_id ne "" ) {
                print STDERR "$G_progname: already provided a callerid: $caller_id\n" ;
                return(1) ;
            }
            $caller_id = $ARGV[ $i ] ;
        }
    }
    if ( $caller_id eq "" ) {
        if ( $delete_flag ) {
            if ( $filtering_id eq "" ) {
                print STDERR "$G_progname: Need to provide filter ID to delete an entry\n" ;
                return(1) ;
            }
            $method = "delCallerIDFiltering" ;
        } else {
            $print_flag++ ;
            $method = "getCallerIDFiltering" ;
        }
    } else {
        if ( $delete_flag ) {
            print STDERR "$G_progname: huh?!  You gave a --delete option as well!\n" ;
            return(1) ;
        }
        $caller_id =~ s/-//g ;      # remove dashes
        $caller_id =~ s/ //g ;      # remove any spaces
        if ( $caller_id !~ /^\d+$/ ) {
            print STDERR "$G_progname: invalid callerid: $caller_id\n" ;
            return(1) ;
        }
        $values{ 'callerid' } = $caller_id ;
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
    my @needed_sections = ( 'authentication', 'black-list' ) ;
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

    my @keywords = $cfg1->get_keywords( 'black-list' ) ;
    # get all the data we have in the config file
    foreach my $keyword ( @keywords ) {
        my $value = $cfg1->get_values( 'black-list', $keyword ) ;
        $defaults{ $keyword } = $value ;
    }

    # now make sure we have the values we need.
    # options over-ride anything from the config file or defaults

    foreach my $key ( keys( %defaults )) {
        my $val = $defaults{ $key } ;
        if ( not defined( $values{ $key } )) {
            $values{ $key } = $val ;
        }
    }

    # If we are setting a filter rule and not printing or deleting
    if (( $print_flag == 0 ) and ( $delete_flag == 0 )) {
        # Anything now undefined is a problem
        foreach my $key ( keys( %values )) {
            if ( not defined( $values{ $key } )) {
                print STDERR "$G_progname: undefined \'${key}\'\n" ;
                $num_errors++ ;
            }
        }
        return(1) if ( $num_errors ) ;

        # verify routing is OK

        $routing = $values{ 'routing' } ;
        $routing =~ tr/A-Z/a-z/ ;       # make lower case
        $routing =~ s/^sys:// ;         # in case the user already gave the prefix
        if ( not defined( $routing_types{ $routing } )) {
            print STDERR "$G_progname: Invalid routing type: \'$routing\'\n" ;
            return(1) ;
        }
        # prefix routing type
        $routing = "sys:${routing}" ;

    }
    my $note      = $values{ 'note' } ;
    my $did       = $values{ 'did' } ;

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

    my $user   = $auth_values{ 'user' } ;
    my $pass   = $auth_values{ 'pass' } ;

    # escape needed strings
    $note = URI::Escape::uri_escape( $note ) ;


    if (( $print_flag == 0 ) and ( $delete_flag == 0 )) {
        dprint( "Routing  = $routing" ) ;
        dprint( "DID      = $did" ) ;
        dprint( "Note     = $note" ) ;
        dprint( "callerID = $caller_id" ) ;
    }
    dprint( "user     = $user" ) ;
    dprint( "method   = $method" ) ;

    my $curl = WWW::Curl::Easy->new();
    if ( ! $curl ) {
        print STDERR "WWW::Curl::Easy->new() failed\n" ;
        return(1) ;
    }

    # finally...  build the URL we need

    my $url = "https://voip.ms/api/v1/rest.php" .
        "?api_username=${user}&api_password=${pass}&method=${method}" ;

    if (( $print_flag == 0 ) and ( $delete_flag == 0 )) {
        $url .= "&note=${note}&routing=${routing}&callerid=${caller_id}&did=${did}" ;
        # if it is a replacement rule
        $url .= "&filter=${filtering_id}" if ( $filtering_id ne "" ) ;
    }

    # if we are deleting a rule
    $url .= "&filtering=${filtering_id}" if ( $delete_flag ) ;

    dprint( "URL = \'$url\'" ) ;

    $curl->setopt( CURLOPT_HEADER, 0 );
    $curl->setopt( CURLOPT_URL, $url ) ;

    my $response_body;
    $curl->setopt( CURLOPT_WRITEDATA, \$response_body) ;

    my $retcode = $curl->perform() ;
    if ( $retcode ) {
        print STDERR "$G_progname: " . $curl->strerror($retcode), " ($retcode)\n" ;
        print STDERR "$G_progname: errbuf: ", $curl->errbuf . "\n" ;
        return(1) ;
    }

    my $json = decode_json( $response_body ) ;

    my $status = $json->{ 'status' } ;
    dprint( "status = $status" ) ;
    if ( $status ne "success" ) {
        my $reason = $status ;
        if ( $status eq "used_filter" ) {
            $reason = "Filter for this number ($caller_id) already used" ;
        }
        print STDERR "$G_progname: Failed status: $reason\n" ;
        return(1) ;
    }

    my $filtering = $json->{ 'filtering' } ;
    if (( $print_flag == 0 ) and ( $delete_flag == 0 )) {
        # setting a filter rule
        if ( not defined( $filtering )) {
            print STDERR "$G_progname: Could not get filtering ID from return\n" ;
            return(1) ;
        }
        dprint( "filtering ID number = $filtering" ) ;
    }
    if ( $print_flag ) {
        # find out how many entries we have and max length of 'note'
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
                'did'   => 'unknown',
                'note'  => '',
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



# debug print

sub dprint {
    my $msg = shift ;
    return(0) if ( $G_debug == 0 ) ;

    print "$msg\n" ;
    return(0) ;
}
