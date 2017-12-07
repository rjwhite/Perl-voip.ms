# voip.ms
programs for using API of voip.ms service

## Description
This set of programs uses a config file to supply authentication information to
use the API of the VOIP service at voip.ms.  There is an included example config
file that needs to have the userid and password changed, and the file installed
into your HOME directory.  You can tweak the config file to set which fields 
you are interested in, the order and size of the fields, and the titles.

## Example usage
This will print CDR records from November 11 to November 22, in reverse order
such that records will be numbered from oldest to newest:

    % get-cdrs.plx --from 2017-11-15 --to 2017-11-22 --reverse

This will print last months CDR records and the cost for account 'home':

    % get-cdrs --last-month --cost --account home

There is a help option:

    % get-cdrs.plx --help

    usage: get-cdrs.plx [options]*
        [-a|--account]     account-name
        [-c|--config]      config-file
        [-d|--debug]       (debugging output)
        [-f|--from]        YYYY-MM-DD (FROM date)
        [-h|--help]        (help)
        [-q|--quiet]       (quiet.  No headings and titles)
        [-r|--reverse]     (reverse date order of CDR output)
        [-s|--sheldon]
        [-t|--to]          YYYY-MM-DD (TO date)
        [-C|--cost]        (total up costs and duration of CDRs)
        [-L|--last-month]  (want CDR records for LAST month)
        [-T|--this-month]  (want CDR records for THIS month)
        [-V|--version]     (print version of this program)

To print all CDR records for the entire (current) month:

        % get-cdrs.plx --this-month

## API setup.
You need to set up your voip.ms service to permit access to it.  This includes
providing which IP addresses can use it.  Please see the following URL for instructions:

    https://voip.ms/m/api.php
