#!/usr/bin/env perl

# print Call Display Records (CDR)

# Needs LWP::UserAgent from CPAN

# Needs Moxad::Config found on github.com under user rjwhite

# get-cdrs.plx --help

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
use LWP::UserAgent();
use lib "/usr/local/Moxad/lib" ;
use Moxad::Config ;
use JSON ;
use POSIX qw(mktime) ;

# Globals 
my $G_progname   = $0 ;
my $G_version    = "v0.6" ;
my $G_debug      = 0 ;

# Constants
my $C_START_OF_DAY    = 0 ;
my $C_END_OF_DAY      = 1 ;
my $C_DEFAULT_TIMEOUT = 30  ;


$G_progname     =~ s/^.*\/// ;

if ( main() ) {
    exit(1) ;
} else {
    exit(0) ;
}



sub main {
    my $home        = $ENV{ HOME } ;
    my $config_file = undef ;
    my $error ;

    my $help_flag    = 0 ;
    my $expect_flag  = 0 ;
    my $quiet_flag   = 0 ;
    my $reverse_flag = 0 ;
    my $costs_flag   = 0 ;
    my $ignore_flag  = 0 ;      # set if we want 'ignore-cdrs' from config
    my $from_date    = "" ;
    my $to_date      = "" ;
    my $padding      = 3 ;
    my $account      = undef ;
    my ( $day, $month, $year ) = (localtime())[3,4,5] ;
    $year += 1900 ;
    $month++ ;
    my @days_in_month = ( 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 ) ;

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
        } elsif (( $arg eq "-E" ) or ( $arg eq "--expected-account" )) {
            $expect_flag++ ;
        } elsif (( $arg eq "-q" ) or ( $arg eq "--quiet" )) {
            $quiet_flag++ ;
        } elsif (( $arg eq "-c" ) or ( $arg eq "--config" )) {
            $config_file = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-p" ) or ( $arg eq "--padding" )) {
            $padding = $ARGV[ ++$i ] ;
        } elsif (( $arg eq "-r" ) or ( $arg eq "--reverse" )) {
            $reverse_flag++ ;
        } elsif (( $arg eq "-I" ) or ( $arg eq "--ignore" )) {
            $ignore_flag++ ;
        } elsif (( $arg eq "-a" ) or ( $arg eq "--account" )) {
            $account = $ARGV[ ++$i ] ;
            if ( not defined( $account )) {
                my $error = "account name not provided with -a option" ;
                print STDERR "$G_progname: $error\n" ;
                return(1) ;
            }
        } elsif (( $arg eq "-C" ) or ( $arg eq "--cost" )) {
            $costs_flag++ ;
        } elsif (( $arg eq "-s" ) or ( $arg eq "--sheldon" )) {
            print "Bazinga!\n" ;
            return(0) ;
        } elsif (( $arg eq "-T" ) or ( $arg eq "--this-month" )) {
            my $num_days = $days_in_month[ $month - 1 ] ;
            $month = sprintf( "%02s", $month ) ;
            my $ret = IsLeapYear( $year, \$error ) ;
            if ( $ret < 0 ) {
                print STDERR "$G_progname: $error\n" ;
                return(1) ;
            } 
            $num_days++ if ( $ret and $month eq "02" ) ;    # February
            $num_days = sprintf( "%02s", $num_days ) ;
            $from_date = "${year}-${month}-01" ;
            $to_date   = "${year}-${month}-${num_days}" ;
        } elsif (( $arg eq "-L" ) or ( $arg eq "--last-month" )) {
            $month-- ;
            if ( $month == 0 ) {
                $month = 12 ;
                $year-- ;
            }
            my $num_days = $days_in_month[ $month - 1 ] ;
            $month = sprintf( "%02s", $month ) ;
            my $ret = IsLeapYear( $year, \$error ) ;
            if ( $ret < 0 ) {
                print STDERR "$G_progname: $error\n" ;
                return(1) ;
            } 
            $num_days++ if ( $ret and $month eq "02" ) ;    # February
            $num_days = sprintf( "%02s", $num_days ) ;
            $from_date = "${year}-${month}-01" ;
            $to_date   = "${year}-${month}-${num_days}" ;
        } elsif (( $arg eq "-f" ) or ( $arg eq "--from" )) {
            $from_date = $ARGV[ ++$i ] ;
            if ( $from_date !~ /^(\d{2,4})\-(\d{1,2})\-(\d{1,2})$/ ) {
                my $err = "invalid \'from\' date format ( YYYY-MM-DD): " .
                          "$from_date" ;
                print STDERR "$G_progname: $err\n" ;
                return(1) ;
            }
        } elsif (( $arg eq "-t" ) or ( $arg eq "--to" )) {
            $to_date = $ARGV[ ++$i ] ;
            if ( $to_date !~ /^(\d{2,4})\-(\d{1,2})\-(\d{1,2})$/ ) {
                my $err = "invalid \'to\' date format ( YYYY-MM-DD): " .
                          "$to_date" ;
                print STDERR "$G_progname: $err\n" ;
                return(1) ;
            }
        } elsif ( $arg =~ /^\-/ ) {
            print STDERR "$G_progname: unknown option: $arg\n" ;
            return(1) ;
        } else {
            print STDERR "$G_progname: unknown option: $arg\n" ;
            return(1) ;
        }
    }

    # We need 'from' and 'to' dates.  Make it only today if nothing given.

    if ( $from_date eq "" ) {
        $month = sprintf( "%02s", $month ) ;
        $day   = sprintf( "%02s", $day ) ;
        $from_date = "${year}-${month}-${day}" ;
    }
    if ( $to_date eq "" ) {
        $month = sprintf( "%02s", $month ) ;
        $day   = sprintf( "%02s", $day ) ;
        $to_date = "${year}-${month}-${day}" ;
    }
    # sanity check
    my $to_timestamp   = convert_to_timestamp( $to_date,   $C_END_OF_DAY ) ;
    my $from_timestamp = convert_to_timestamp( $from_date, $C_START_OF_DAY ) ;
    dprint( "FROM timestamp $from_timestamp -> TO timestamp $to_timestamp" ) ;
    if ( $from_timestamp <= 0 ) {
        my $err = "failed to convert FROM date ($from_date) to a timestamp" ;
        print STDERR "$G_progname: $err\n" ;
        return(1) ;
    }
    if ( $to_timestamp <= 0 ) {
        print STDERR "$G_progname: failed to convert TO date ($to_date) " .
            "to a timestamp\n" ;
        return(1) ;
    }
    if ( $from_timestamp > $to_timestamp ) {
        print STDERR "$G_progname: FROM date ($from_date) is after " .
            "TO ($to_date) date\n" ;
        return(1) ;
    }
    dprint( "using date from $from_date to $to_date" ) ;

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
    my @needed_sections = ( 'authentication', 'time', 'cdrs' ) ;
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

    # sanity checking required keywords in 'cdr' section

    my @cdr_keywords_needed = ( 'order', 'title', 'cdrs-wanted' ) ;
    my %got_keywords = () ;
    my @keywords = $cfg1->get_keywords( 'cdrs' ) ;
    foreach my $keyword ( @keywords ) {
        $got_keywords{ $keyword } = 1 ;
    }
    $num_errors = 0 ;
    foreach my $keyword ( @cdr_keywords_needed ) {
        if ( not defined( $got_keywords{ $keyword } )) {
            print STDERR "$G_progname: missing keyword \'$keyword\' " .
                "in section \'cdrs\' in $config_file\n" ;
            $num_errors++ ;
        }
    }
    return(1) if ( $num_errors ) ;

    # we defer printing out the help info till after we have set defaults
    # and read our config file, so we can see defaults in the usage printed

    if ( $help_flag ) {
        printf "usage: %s [options]*\n" .
            "%s %s %s %s %s %s %s %s %s %s %s %s %s %s %s %s",
            $G_progname,
            "\t[-a|--account str]         account name\n",
            "\t[-c|--config file]         config-file (default=$config_file)\n",
            "\t[-d|--debug]               debug output.  Twice for more info\n",
            "\t[-f|--from YYYY-MM-DD]     FROM date\n",
            "\t[-h|--help]                help\n",
            "\t[-p|--padding num]         padding between output fields " .
                "  (default=$padding)\n",
            "\t[-q|--quiet]               quiet.  No headings and titles\n",
            "\t[-r|--reverse]             reverse date order of CDR output\n",
            "\t[-s|--sheldon]\n",
            "\t[-t|--to YYYY-MM-DD]       TO date\n",
            "\t[-C|--cost]                total up costs and duration of CDRs\n",
            "\t[-E|--expected-account]    CDRs expected in each (sub)account\n",
            "\t[-I|--ignore]              show ignored CDRs as specified in " .
                "config file\n",
            "\t[-L|--last-month]          want CDR records for LAST month\n",
            "\t[-T|--this-month]          want CDR records for THIS month\n",
            "\t[-V|--version]             version of this program ($G_version)\n" ;
        return  (0) ;
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

    my $user = $auth_values{ 'user' } ;
    my $pass = $auth_values{ 'pass' } ;

    # get the timeout

    my $timeout = $cfg1->get_values( 'cdrs', 'timeout' ) ;
    $cfg1->clear_errors()  if ( $cfg1->errors() ) ;
    if ( not defined( $timeout )) {
        dprint( "Using default timeout of $C_DEFAULT_TIMEOUT seconds" ) ;
        $timeout = $C_DEFAULT_TIMEOUT ;
    } else {
        if ( $timeout !~ /^\d+$/ ) {
            print STDERR "$G_progname: timeout ($timeout) is non-numeric\n" ;
            return(1) ;
        }
        dprint( "Using timeout found in config file of $timeout seconds" ) ;
    }

    # get the timezone

    my $DEFAULT_TIMEZONE = -5 ;
    my $timezone = $cfg1->get_values( 'time', 'timezone' ) ;
    if ( $cfg1->errors() ) {
        $timezone = $DEFAULT_TIMEZONE ;
        $cfg1->clear_errors() ;
    }

    # see if we want to change the default behaviour in which (sub)account
    # a CDR is associated with

    my $cdr_acct = $cfg1->get_values( 'cdrs', 'show-in-expected-account' ) ;
    $cfg1->clear_errors()  if ( $cfg1->errors() ) ;
    if ( defined( $cdr_acct )) {
        if ( $cdr_acct =~ /yes/i ) {
            $expect_flag++ ;
            dprint( "show-in-expected-account set to YES in config" ) ;
        }
    }

    # get the fields we want, and the order to print them

    my @fields = $cfg1->get_values( 'cdrs', 'order' ) ;
    if ( $cfg1->errors() ) {
        my @errors = $cfg1->errors() ;
        foreach my $error ( @errors ) {
            print STDERR "$G_progname: $error\n" ;
        }
        return(1) ;
    }

    # get the titles

    my %titles = $cfg1->get_values( 'cdrs', 'title' ) ;
    if ( $cfg1->errors() ) {
        %titles = () ;
        $cfg1->clear_errors()  ;
    }

    # fill in any missing titles using the field names
    # Capitalize the first letter

    foreach my $field ( @fields ) {
        # if any titles are missing, just use the field name
        if ( not defined( $titles{ $field } )) {
            $titles{ $field } = ucfirst( $field ) ;
        }
    }

    # get the field sizes from the config file.

    my %field_sizes = () ;
    if ( $got_keywords{ 'field-size' } ) {
        dprint( "Got \'field-size\' keyword in section \'cdrs\'" ) ;
        %field_sizes = $cfg1->get_values( 'cdrs', 'field-size' ) ;
        if ( $cfg1->errors() ) {
            # just recover and keep going
            %field_sizes = () ;
            $cfg1->clear_errors()  ;
        }

        # Only use them if they are big enough to accomodate the size
        # of the title + padding

        foreach my $field ( @fields ) {
            if ( defined( $titles{ $field } )) {
                my $title_len = length( $titles{ $field } ) + $padding ;
                if ( defined( $field_sizes{ $field } )) {
                    my $field_len = $field_sizes{ $field } ;
                    if ( $field_len < $title_len ) {
                        dprint( "not enough room for title for \'$field\'" ) ;
                        my $msg = "ignoring config value field size " .
                                  "($field_len) for \'$field\'" ;
                        dprint( $msg ) ;

                        # setting instead to value big enough for title
                        $field_sizes{ $field } = $title_len ;
                    }
                }
            }
        }
    } else {
        dprint( "don't have \'field-size\' keyword in section \'cdrs\'" ) ;
    }

    dprint( "FROM date = $from_date" ) ;
    dprint( "TO   date = $to_date" ) ;
    dprint( "USER = \'$user\' PASS = \'$pass\' TIMEZONE = $timezone" ) ;

    # see if we want to ignore any CDRs
    my @ignore_cdrs = () ;
    my %ignore_cdrs = () ;
    if ( $ignore_flag == 0 ) {
        if ( $got_keywords{ 'ignore-cdrs' } ) {
            @ignore_cdrs = $cfg1->get_values( 'cdrs', 'ignore-cdrs' ) ;
            if ( $cfg1->errors() ) {
                my @errors = $cfg1->errors() ;
                foreach my $error ( @errors ) {
                    print STDERR "$G_progname: $error\n" ;
                }
                return(1) ;
            }
            foreach my $ignore ( @ignore_cdrs ) {
                dprint( "will ignore CDRs with description: \'$ignore\'" ) ;
                $ignore_cdrs{ $ignore } = 1 ;
            }
        }
    }

    # finally...  build the URL we need
    my $method = "getCDR" ;

    my %cdrs_wanted = $cfg1->get_values( 'cdrs', 'cdrs-wanted' ) ;
    if ( $cfg1->errors() ) {
        my @errors = $cfg1->errors() ;
        foreach my $error ( @errors ) {
            print STDERR "$G_progname: $error\n" ;
        }
        return(1) ;
    }

    # just ask for the CDRs we want.  Our choices are:
    #    answered, noanswer, busy, and failed   
    # if set to non-zero, ask for them

    my $cdrs_we_want = "" ;
    foreach my $key ( keys( %cdrs_wanted )) {
        my $item = $key ; $item =~ tr/A-Z/a-z/ ;  # make lower case
        my $val = $cdrs_wanted{ $key } ;
        if ( defined( $val ) and ( $val ne 0 )) {
            $cdrs_we_want .= "${item}=1&" ;
            dprint( "We want type \'$item\' CDRs" ) ;
        }
    }

    # If we specified an account and we want the voip.ms default 
    # (broken) behaviour

    if ( defined( $account )) {
        dprint( "we ONLY want account $account" ) ;
        $cdrs_we_want .= "account=${account}&" if ( $expect_flag == 0 ) ;
    }
    chop( $cdrs_we_want ) if ( $cdrs_we_want ne "" ) ;  # remove trailing '&'

    # if we want a specific account

    # We used to modify the REST URL to also contain account=${account}
    # believing that both outgoing and incoming calls associated with the
    # phone number for that (sub)account would be reported.  But No.
    # See Ticket # OBIEL5.  From voip.ms:
    #
    #    Note that ALL incoming calls will show up 220306 as the account
    #    This is because incoming calls are filtered per number, not
    #    per subaccounts, in fact, subaccounts are not related to the number.
    #
    #    On the other hand, outgoing calls will always be filtered per
    #    subaccount, since this is the entity that actually makes the
    #    outgoing call.
    #
    # So we have to handle this differently

    my $did_number = undef ;
    if ( defined( $account ) and $expect_flag ) {

        # we need the DID number.
        # First see if we can avoid an API call using getDIDsInfo by seeing
        # if we've already seeded our config file with a list of 'accounts'

        if ( $got_keywords{ 'accounts' } ) {
            # check that the type is a hash
            my $type = $cfg1->get_type( 'cdrs', 'accounts') ;
            if ( $type !~ /hash/i ) {
                my $err = "non-hash entries from config for cdrs/accounts" ;
                print STDERR "$G_progname: $err\n" ;
                return(1) ;
            }
            my %accounts = $cfg1->get_values( 'cdrs', 'accounts' ) ;
            if ( defined( $accounts{ $account } )) {
                $did_number = $accounts{ $account } ;
                $did_number =~ s/\D//g ;    # make it just numbers
                dprint( "found ACCOUNT of $account = \'$did_number\'" ) ;
            }
        }

        if ( defined( $did_number )) {
            dprint( "skipping API call of getDIDsInfo to get DID" ) ;
        } else {
            dprint( "looking up DID number for account $account" ) ;
            dprint( "Using timeout of $timeout secs for getDIDsInfo" ) ;

            # find out the DID number associated with the (sub)account given
            my $get_did_method  = 'getDIDsInfo' ;
            return(1) if ( get_DID_from_account( $account, $user, $pass, 
                                                $get_did_method, $timeout,
                                                \$did_number )) ;
        }

        if (( not defined( $did_number )) or ( $did_number eq 1 )) {
            my $error = "can't get DID number from account: $account" ;
            print STDERR "$G_progname: $error\n" ;
            return(1) ;
        }
        dprint( "DID for account $account is $did_number" ) ;
    }

    # build our URL.  Get *all* CDR's - even if we only want a specific
    # (sub)account

    my $url = "https://voip.ms/api/v1/rest.php" .
        "?api_username=${user}&api_password=${pass}&method=${method}" .
        "&date_from=${from_date}&date_to=${to_date}&${cdrs_we_want}" .
        "&timezone=${timezone}" ;
    dprint( "URL = \'$url\'" ) ;

    my $json = undef ;
    my $status = undef ;
    return(1) if ( get_json_data( $url, $timeout, \$json, \$status )) ;

    if ( $status ne "success" ) {
        if ( $status eq "no_cdr" ) {
            my $pretty_from = pretty_date( $from_date ) ;
            my $pretty_to   = pretty_date( $to_date ) ;
            print "No CDR records found from $pretty_from to " .
                         "$pretty_to\n" ;
        } else {
            print STDERR "$G_progname: CDR retrieval failed. " .
                         "status = \'$status\'\n" ;
        }
        return(1) ;
    }

    my $cdrs = $json->{ 'cdr' } ;

    # get the number of records found

    my $num_records = 0 ;
    foreach my $cdr_hash ( @{$cdrs} ) {
        $num_records++ ;
    }
    dprint( "Found TOTAL of $num_records CDR records" ) ;

    # we have a bunch of CDR's .  See if we need to eliminate some.

    # we may not want some CDRs if 'ignore-cdrs' was set

    my @cdrs = () ;
    foreach my $cdr_hash ( @{$cdrs} ) {
        my $description = ${$cdr_hash}{ 'description' } ;
        if ( $ignore_cdrs{ $description } ) {
            dprint( "ignoring CDR record with description: \'$description\'" ) ;
            next ;
        }

        # see if we want a specific account.  If so, we'll check both the
        # 'destination' and the 'callerid' to see if we match the number
        # we got that is associated with the account name given.
        # Note that the 'calledid' could be of the form:
        #       "\"TORONTO ON\" <5551234567>",

        if ( defined( $account ) and $expect_flag ) {
            my $want_it = 0 ;
            my $destination = ${$cdr_hash}{ 'destination' } ;
            $destination =~ s/\D//g ;   # get rid of all non-digits
            $destination =~ s/^1// ;    # get rid of long-distance '1' prefix
            if ( $did_number eq $destination ) {
                dprint( "DESTINATION match: $destination for acct $account" ) ;
                $want_it++ ;
            }

            my $callerid = ${$cdr_hash}{ 'callerid' } ;
            $callerid =~ s/\D//g ;  # get rid of all non-digits
            $callerid =~ s/^1// ;    # get rid of long-distance '1' prefix
            if ( $did_number eq $callerid ) {
                dprint( "CALLERID match: $callerid for acct $account" ) ;
                $want_it++ ;
            }
            next if ( ! $want_it ) ;
        }
        push( @cdrs, $cdr_hash ) ;
    }

    $num_records = @cdrs ;
    dprint( "processing $num_records matching CDR records" ) ;

    # the user may want the records in reverse order

    @cdrs = reverse( @cdrs ) if ( $reverse_flag ) ;

    if ( $num_records == 0 ) {
        print "No CDR records were found\n" ;
        return(0) ;
    }

    my $full_title      = 'call#' ;
    my $full_dash_title = '-----' ;

    # get the sizes of the data

    my %data_sizes = () ;
    foreach my $field ( @fields ) {
        my $max_len = 0 ;
        foreach my $cdr_hash ( @cdrs ) {
            my $size = length( ${$cdr_hash}{ $field} ) ;
            $max_len = $size if ( $size > $max_len ) ;
        }
        $data_sizes{ $field } = $max_len ;
    }

    # now set any field sizes that are missing

    foreach my $field ( @fields ) {
        my $data_len = $data_sizes{ $field } ;

        # skip if given by config file.  value found in config file
        # should include padding

        if ( defined( $field_sizes{ $field } )) {
            my $field_size = $field_sizes{ $field } ;
            my $msg = "using field size ($field_size) given by config file " .
                      " for \'$field\'" ;
            dprint( $msg ) ;
        } else {
            # not in the config file.  Use the MAX size of data plus padding
            # But first check the titel size

            my $title_len = length( $titles{ $field } ) ;
            if ( $title_len > $data_len ) {
                my $msg = "using TITLE size of ($title_len) for \'$field\' " .
                          "+ padding ($padding)." ;
                dprint( $msg ) ;
                $data_len = $title_len ;
            } else {
                my $msg = "using MAX size of data ($data_len) for \'$field\' " .
                          "+ padding ($padding)." ;
                dprint( $msg ) ;
            }
            $field_sizes{ $field } = $data_len + $padding ;
        }
    }

    # get the data.  we may need to truncate some data 

    my $count = 0 ;
    foreach my $cdr_hash ( @cdrs ) {
        if ( $G_debug > 1 ) {
            my $pretty_json_text = JSON::to_json($cdr_hash, {utf8 => 1, pretty => 1}) ;
            print "debug: CDR record:" ;
                print "$pretty_json_text\n" ;
        }

        foreach my $field ( @fields ) {
            my $data = ${$cdr_hash}{ $field } ;
            my $data_len = length( $data ) ;
            my $field_size = $field_sizes{ $field } ;
            my $diff = ( $data_len + $padding ) - $field_size ;
            if ( $diff > 0 ) {
                dprint( "Need to truncate data for field \'$field\'" ) ;
                # 3 for adding 3 dots on end
                $data = substr( $data, 0, $field_size - $padding - 3 ) ;
                $data .= "..." ;
                ${$cdr_hash}{ $field } = $data ;
            }
        }
        $count++ ;
    }

    # build the title

    if ( ! $quiet_flag ) {
        # create titles
        foreach my $field ( @fields ) {
            my $title = $titles{ $field } ;
            $title = "?" if ( not defined( $title )) ;

            my $field_size = 20 ;    # won't happen
            if ( defined( $field_sizes{ $field } )) {
                # has to be defined...
                $field_size = $field_sizes{ $field } ;
            }

            my $dash_size = $field_size - $padding ;
            my $dash_title = ( ' ' x $padding ) . ( '-' x $dash_size ) ;
            $full_dash_title .= $dash_title ;

            $title = center_str( $title, $dash_size ) ;

            $full_title .= ( ' ' x $padding ) . $title ;
        }
    }

    my $total_cost       = 0 ;
    my $total_duration   = 0 ;
    my %account_cost     = () ;
    my %account_duration = () ;
    my %account_calls    = () ;

    if ( ! $quiet_flag ) {
        my $pretty_from = pretty_date( $from_date ) ;
        my $pretty_to   = pretty_date( $to_date ) ;
        print "$num_records CDR records found from $pretty_from to $pretty_to" ;
        if ( defined( $account )) {
            print " for account \'$account\'" ;
        }
        print "\n\n" ;
        print "$full_title\n" ;
        print "$full_dash_title\n" ;

    }

    # print the records
    $count = 1 ;
    foreach my $cdr_hash ( @cdrs ) {
        my $full_cdr_record = sprintf( "%4d ", $count ) ;
        $count++ ;
        foreach my $field ( @fields ) {
            my $val = ${$cdr_hash}{ $field} ;
            my $size = $field_sizes{ $field } ;

            $full_cdr_record .= sprintf( "%${size}s", $val ) ; 
        }
        print "$full_cdr_record\n" ;

        if ( $costs_flag ) {
            if ( defined( ${$cdr_hash}{ 'total' } )) {
                $total_cost += ${$cdr_hash}{ 'total' } ;
            }
            if ( defined( ${$cdr_hash}{ 'seconds' } )) {
                $total_duration += ${$cdr_hash}{ 'seconds' } ;
            }

            # keep tally of individual accounts
            if ( defined( ${$cdr_hash}{ 'account' } )) {
                my $account = ${$cdr_hash}{ 'account' } ;
                if ( not defined( $account_cost{ $account } )) {
                    # initialize the lot of them (even though we don't have to)
                    $account_cost{ $account }     = 0 ;
                    $account_duration{ $account } = 0 ;
                    $account_calls{ $account }    = 0 ;
                }
                $account_calls{ $account }    += 1 ;
                $account_cost{ $account }     += ${$cdr_hash}{ 'total' } ;
                $account_duration{ $account } += ${$cdr_hash}{ 'seconds' } ;
            }
        }
    }

    if ( $costs_flag ) {
        # Total of all calls for all accounts combined

        printf "\nTotal cost is \$%.2f\n" , $total_cost ;
        my $pretty_time = convert_seconds( $total_duration ) ;
        print "Total duration of calls is ${pretty_time}" ;
        if ( $total_duration > 60 ) {
            print " ($total_duration seconds)" ;
        }
        print "\n" ;

        # now for each account if more than one
        my @accounts = keys( %account_cost ) ;
        if ( @accounts > 1 ) {
            foreach my $account ( @accounts ) {
                printf "\nTotal cost of %d calls for account \'%s\' is \$%.2f\n",
                    $account_calls{ $account }, $account,
                    $account_cost{ $account } ;
                my $a_duration = $account_duration{ $account } ;
                my $pretty_time = convert_seconds( $a_duration ) ;
                print "Total duration of calls for account \'$account\' is " .
                      "${pretty_time}" ;
                if ( $a_duration > 60 ) {
                    print " ($a_duration seconds)" ;
                }
                print "\n" ;
            }
        }
    }
    return(0) ;
}


# convert a number of seconds into a pretty string of
# hours, minutes and seconds
#
# Arguments:
#     1: seconds
# Returns:
#     string

sub convert_seconds {
    my $seconds = shift ;

    my $str = "" ;
    $seconds = 0 if ( not defined( $seconds )) ;

    my $hours = int( $seconds / ( 60 * 60 )) ;
    if ( $hours ) {
        $seconds -= ( $hours * ( 60 * 60 )) ;
        $str = "$hours hours, " ;
    }

    my $mins = int( $seconds / 60 ) ;
    if ( $mins ) {
        $seconds -= ( $mins * 60 )  ;
        $str .= "$mins mins, " ;
    }

    $str .= "$seconds secs" ;
    return( $str ) ;
}


# debug print
# print a debug string if the global debug flag is set
#
# Arguments:
#     1: string to print
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


# Is it a leap year
# Assume a 2-digit year is 20xx
#
# Arguments:
#     1: year (YYYY)
# Returns:
#    -1: Argument 1 (year) year
#    -2: Invalid year - not digits
#    -3: Invalid year - not correct length
#     0: No
#     1: yes

sub IsLeapYear {
    my $year    = shift;
    my $err_ref = shift ;

    my $i_am = "IsLeapYear()" ;

    if ( not defined( $year )) {
        ${$err_ref} = "$i_am: Argument 1 is undefined" ;
        return( -1 ) ;
    }
    if ( $year !~ /^\d+$/ ) {
        ${$err_ref} = "$i_am: Argument 1 (year) is not digits" ;
        return( -2 ) ;
    }

    # handle 2-digit years
    $year += 2000 if ( $year =~ /^\d\d/ ) ;

    if ( $year !~ /^\d\d\d\d$/ ) {
        ${$err_ref} = "$i_am: Argument 1 (year) is not 4 digits" ;
        return( -3 ) ;
    }

    return(0) if ( $year % 4 ) ;
    return(1) if ( $year % 100 ) ;
    return(0) if ( $year % 400 ) ;
    return(1);
}



# convert a date to a timestamp (Unix epoch = Jan 1, 1970 GMT)
#
# Date must be of the format YY-MM-DD or YYYY-MM-DD
#
# Arguments :
#     1:    date (YY-MM-DD or YYYY-MM-DD)
#     2:    flag: $C_START_OF_DAY | $C_END_OF_DAY (default = $C_START_OF_DAY)
# Returns :
#     0:    Don't understand date format
#     > 0:  timestamp

sub convert_to_timestamp {
    my $date      = shift ;
    my $time_flag = shift ;

    return(0) if (( not defined( $date )) or ( $date eq "" )) ;
    $time_flag = $C_START_OF_DAY if ( not defined( $time_flag )) ;

    my ( $sec, $min, $hour ) = ( 0, 0, 0 ) ;
    if ( $time_flag == $C_END_OF_DAY ) {
        $sec  = 59 ;
        $min  = 59 ;
        $hour = 23 ;
    }

    my ( $year, $month, $day ) ;
    if ( $date =~ /^(\d{2,4})\-(\d{1,2})\-(\d{1,2})$/ ) {
        $year  = $1 ;
        $month = $2 ;
        $day   = $3 ;
    } else {
        return(0) ;
    }

    $month-- ;
    if ( length( $year ) == 4 ) {
        $year -= 1900 ;
    } else {
        $year = $year + 100 ;
    }

    return( mktime( $sec, $min, $hour, $day, $month, $year, 0, 0, -1 )) ;
}


# Make a date prettier for a human
# 2017-12-4 will become 'Dec 4, 2017'
#
# Arguments :
#     1:    date (YY-MM-DD or YYYY-MM-DD)
# Returns :
#     MMM DD, YYYY

sub pretty_date {
    my $date = shift ;

    my ( $year, $mon, $day ) ;
    my %months = (
        0  => "?",    1  => "Jan",  2  => "Feb",   3  => "Mar",
        4  => "Apr",  5  => "May",  6  => "June",  7  => "July",
        8  => "Aug",  9  => "Sept", 10 => "Oct",  11  => "Nov",  12 => "Dec",
    ) ;

    if ( $date =~ /^(\d{2,4})\-(\d{1,2})\-(\d{1,2})$/ ) {
        my $year  = $1 ;
        my $month = $2 ;
        my $day   = $3 ;

        $month =~ s/^0// ;      # remove any leading 0
        $day   =~ s/^0// ;

        if ( defined( $months{ $month } )) {
            $month = $months{ $month } ;
        }

        return( "$month ${day}, $year" ) ;
    }
    return( $date ) ;
}


# center a string
#
# Arguments:
#     1: string to center
#     2: field size
# Returns:
#     string

sub center_str {
    my $str         = shift ;
    my $field_size  = shift ;

    if (( not defined( $field_size )) or ( $field_size == 0 )) {
        return( $str ) ;
    }

    my $size_of_str = length( $str ) ;
    if ( $size_of_str >= $field_size ) {
        return( $str ) ;
    }

    my $diff = $field_size - $size_of_str ;
    my $num_spaces = int( $diff / 2 ) ;

    my $new_str = ( ' ' x $num_spaces ) . $str ;
    $size_of_str = length( $new_str ) ;
    $new_str .= ' ' x ( $field_size - $size_of_str ) ;

    return( $new_str ) ;
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


# get the DID (line) for a given account
# If there is an error, the efrror will be printed from this routine
# and it will return with a value of 1.
#
# Arguments:
#   1:  account name wanted
#   2:  userid
#   3:  password
#   4:  method
#   5:  timeout for request
#   6:  reference of DID number to return
# Returns one of:
#   0:  OK
#   1:  NOT ok
# Globals:
#   $G_progname

sub get_DID_from_account {
    my $account = shift ;
    my $user    = shift ;
    my $pass    = shift ;
    my $method  = shift ;
    my $timeout = shift ;
    my $did_ref = shift ;

    my $i_am = 'get_DID_from_account()' ;

    # build our REST API to voip.ms

    my $url = "https://voip.ms/api/v1/rest.php" .
        "?api_username=${user}&api_password=${pass}&method=${method}" ;

    dprint( "$i_am: URL = \'$url\'" ) ;

    my $json   = undef ;
    my $status = undef ;
    return(1) if ( get_json_data( $url, $timeout, \$json, \$status )) ;

    if ( $status ne "success" ) {
        print STDERR "$G_progname: $i_am: JSON returned failed status. " .
                        "(\'$status\')\n" ;
        return(1) ;
    }

    my $dids = $json->{ 'dids' } ;
    if ( not defined( $dids )) {
        my $err = "could not get \'dids\' info array in JSON return data" ;
        print STDERR "$G_progname: $i_am: $err\n" ;
        return(1) ;
    }

    # now get our data

    foreach my $hash_ref ( @{$dids} ) {
        my $line = ${$hash_ref}{ 'did' } ;
        continue if ( not defined( $line )) ;

        my $acct = ${$hash_ref}{ 'routing' } ;
        $acct =~ s/account:// ;
        dprint( "$i_am: got DID $line for account $acct" ) ;
        if ( $acct eq $account ) {
            dprint( "$i_am: FOUND DID $line for account $account" ) ;
            $line =~ s/ //g ;   # remove any spacing
            $line =~ s/^1// ;   # remove any leading '1'
            ${$did_ref} = $line ;
            return(0) ;
        }
    }
    my $err = "failed to find DID for account $account" ;
    dprint( "$i_am: $err" ) ;
    print STDERR "$G_progname: $i_am: $err\n" ;
    return(1) ;         # not found
}


# Get some JSON data given a pre-built URL and a timeout
# If there is an error, the error will be printed from this routine
# and it will return with a value of 1.
#
# Arguments:
#   1:  URL
#   2:  timeout
#   3:  reference of JSON data to return
#   4:  reference of value of 'status' in JSON returned
# Returns one of:
#   0:  OK
#   1:  NOT ok
# Globals:
#   $G_progname

sub get_json_data {
    my $url = shift ;
    my $timeout = shift ;
    my $json_ref = shift ;
    my $status_ref = shift ;

    my $i_am = "get_json_data()" ;
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
        print STDERR "$G_progname: $i_am: $reason\n" ;
        return(1) ;
    }

    # decode the JSON

    if ( $response_body !~ /^\{/ ) {
        print STDERR "$G_progname: $i_am: no JSON structure returned\n" ;
        return(1) ;
    }
    my $json = decode_json( $response_body ) ;
    if ( not defined( $json )) {
        my $err = "failed to decode JSON" ;
        print STDERR "$G_progname: $i_am: $err\n" ;
        return(1) ;
    }

    my $status = $json->{ 'status' } ;
    if ( not defined( $status )) {
        my $err = "undefined \'status\' in JSON return" ;
        print STDERR "$G_progname: $i_am: $err\n" ;
        return(1) ;
    }
    dprint( "$i_am: status = $status" ) ;

    ${$status_ref} = $status ;
    ${$json_ref}   = $json ;
    return(0) ;
}
