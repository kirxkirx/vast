#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ -z $1 ]; then
 echo "Usage: ./date_shift.sh deltaJD < lightcurvefile.dat"
 echo "JDout = JDin + deltaJD"
 exit
else
# "JDout = JDin + $1"
 while read JD XXX ;do
  JD=`echo "$JD+($1)" |bc -ql`
  echo "$JD $XXX"
 done
fi
  