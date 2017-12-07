#!/bin/sh

# write out the previous months phone CDR records
# Typically run from the crontab on the 1st of the month, to
# collect all CDR records from the previous month

#   write-phone-CDR-records.sh [account]*

# eg crontab entry run on first of month at 3:15am:
#   15 3 1 * * $HOME/bin/write-phone-CDR-records home business alarm

prog=`basename $0`
export PATH=$HOME/bin:$PATH

today=`date +%m/%d/%Y`
month=`echo $today | cut -f1 -d/`
day=`echo $today | cut -f2 -d/`
year=`echo $today | cut -f3 -d/`
accounts=$*

# we want the previous month
month=`echo $month - 1 | bc`
if [ x$month = x0 ]; then
    month=12
    year=`echo $year - 1 | bc`
fi
# convert to non-numeric
month=`date -d ${month}/${day}/${year} +%b`

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
