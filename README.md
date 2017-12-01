# voip.ms
programs for using API of voip.ms service

## Description
This set of programs uses a config file to supply authentication information to
use the API of the VOIP service at voip.ms.  There is an included example config
file that needs to have the userid and password changed, and the file installed
into your HOME directory.

## Example usage
get-cdrs.plx --from 2017-11-15 --to 2017-11-22 --reverse

There is a help option:
    get-cdrs.plx --help

## API setup.
You need to set up your voip.ms service to permit access to it.  This includes
providing which IP addresses can use it.  Please see the foloowing URL on instructions:
    https://voip.ms/m/api.php
