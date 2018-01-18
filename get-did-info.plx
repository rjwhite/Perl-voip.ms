#!/usr/bin/env perl

# get DID info
#
#   get-did-info.plx --help     - print options
#   get-did-info.plx            - print list of DID numbers
#   get-did-info.plx --account  - print list (sub)account:DID-number
#   get-did-info.plx --all      - print all data available about the DID(s)

# Needs WWW::Curl from CPAN.
# That will complain that you must install curl-config, which you can do 
# on a Linix Mint system with: 'apt-get install libcurl4-gnutls-dev'

# Needs Moxad::Config found on github.com under user rjwhite

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
use JSON ;

# Globals 
my $G_progname   = $0 ;
my $G_version    = "v0.1" ;
my $G_debug      = 0 ;

$G_progname     =~ s/^.*\/// ;

if ( main() ) {
    exit(1) ;
} else {
    exit(0) ;
}



sub main {
    my $home                = $ENV{ HOME } ;
    my $config_file =       "${home}/.voip-ms.conf" ;
    my $method              = "getDIDsInfo" ;
    my $did                 = undef ;
    my $account_names_flag  = 0 ;
    my $all_info_flag       = 0 ;
    my $error ;

    # get options

    for ( my $i = 0 ; $i <= $#ARGV ; $i++ ) {
        my $arg = $ARGV[ $i ] ;
        if (( $arg eq "-h" ) or ( $arg eq "--help" )) {
            printf "usage: %s [options]*\n" .
                "%s %s %s %s %s %s %s",
                $G_progname,
                "\t[-a|--all]           all info about did(s)\n",
                "\t[-c|--config]        config-file\n",
                "\t[-d|--debug]         (debugging output)\n",
                "\t[-h|--help]          (help)\n",
                "\t[-A|--account]       print (sub)account name(s) instead of DID\n",
                "\t[-D|--did]           specific phone-number (which line)\n",
                "\t[-V|--version]       (print version of this program)\n" ;
            return(0) ;
        } elsif (( $arg eq "-a" ) or ( $arg eq "--all" )) {
            $all_info_flag++ ;
        } elsif (( $arg eq "-c" ) or ( $arg eq "--config" )) {
            $config_file = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-d" ) or ( $arg eq "--debug" )) {
            $G_debug++ ;
        } elsif (( $arg eq "-A" ) or ( $arg eq "--account" )) {
            $account_names_flag++ ;
        } elsif (( $arg eq "-D" ) or ( $arg eq "--did" )) {
            $did = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-V" ) or ( $arg eq "--version" )) {
            print "version: $G_version\n" ;
            return(0) ;
        } elsif ( $arg =~ /^\-/ ) {
            print STDERR "$G_progname: unknown option: $arg\n" ;
            return(1) ;
        }
    }

    # check and format DID number if necessary

    if ( defined( $did )) {
        $did =~ s/-//g ;        # no dashes
        $did =~ s/ //g ;        # no spaces
        if ( $did !~ /^\d+$/ ) {
            print STDERR "$G_progname: did is not numeric: $did\n" ;
            return(1) ;
        }
        dprint( "Using a DID of $did" ) ;
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
    my @needed_sections = ( 'authentication' ) ;
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

    # see if user wants a specific DID
    $url .= "&did=${did}" if ( defined( $did )) ;

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
    if ( not defined( $status )) {
        print STDERR "$G_progname: could not get \'status\' in JSON return\n" ;
        return(1) ;
    }
    dprint( "status = $status" ) ;
    if ( $status ne "success" ) {
        my $reason = $status ;
        print STDERR "$G_progname: Failed status: $reason\n" ;
        return(1) ;
    }

    my $dids = $json->{ 'dids' } ;
    if ( not defined( $dids )) {
        print STDERR "$G_progname: could not get \'dids\' info array in JSON return\n" ;
        return(1) ;
    }

    # find out number of entries,  get an ordered list of keys, and get max length

    my $num_entries      = 0 ;
    my $got_ordered_keys = 0 ;
    my $max_len          = 0 ;
    my @ordered_keys ;

    foreach my $hash_ref ( @{$dids} ) {
        $num_entries++ ;
        if ( $got_ordered_keys == 0 ) {
            @ordered_keys = keys( %{$hash_ref} ) ;

            # get the maximum length of the keys
            foreach my $key ( @ordered_keys ) {
                my $len = length( $key ) ;
                $max_len = $len if ( $len > $max_len ) ;
            }
            $max_len += 4 ;     # add some spacing
            dprint( "MAX length of keys in data is $max_len" ) ;

            # only want to do it once
            $got_ordered_keys++ ;
        }
    }

    # now get our data

    foreach my $hash_ref ( @{$dids} ) {
        my $line = ${$hash_ref}{ 'did' } ;
        continue if ( not defined( $line )) ;

        my $account = ${$hash_ref}{ 'routing' } ;
        continue if ( not defined( $account)) ;

        if ( $account_names_flag ) {
            $account =~ s/^account:// ;
            print "${account}:${line}\n" ;        # prepend (sub)account name
        } else {
            print "$line\n" ;                   # print just the DID number
        }

        # print all our info for the DID
        if ( $all_info_flag ) {
            my %values = () ;

            foreach my $key ( @ordered_keys ) {
                my $val = ${$hash_ref}{ $key } ;
                $val = "undefined" if ( not defined( $val )) ;
                printf "\t%-${max_len}s %s\n", $key, $val ;
            }
            print "\n" if ( $num_entries > 1 ) ;
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
