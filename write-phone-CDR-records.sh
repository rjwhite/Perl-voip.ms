#!/bin/sh

# write out the previous months phone CDR records
# Typically run from the crontab on the 1st of the month, to
# collect all CDR records from the previous month

#   write-phone-CDR-records.sh [account]*

# eg crontab entry run on first of month at 3:15am:
#   15 3 1 * * $HOME/bin/write-phone-CDR-records home business alarm

prog=`basename $0`
export PATH=$HOME/bin:$PATH

accounts=$*
month=`date --date="last month" +%b`
year=`date --date="last month" +%Y`

dir=$HOME/data/phone-records/$year

if [ ! -d $dir ]; then
    mkdir -p $dir
    echo $prog: created $dir
fi

# sanity check that directory was created ok
if [ ! -d $dir ]; then
    echo $prog: No such directory: $dir
    exit 1
fi

if [ "x$accounts" = x ]; then
    file=${dir}/${month}
    get-cdrs --last-month  --reverse  --cost > $file

    echo $prog: Phone CDR records account written to $file
else
    for account in $accounts ; do
        file=${dir}/${month}-${account}

        get-cdrs --last-month  --reverse  --cost --account $account > $file

        echo $prog: Phone CDR records for account $account written to $file
    done
fi

exit 0
