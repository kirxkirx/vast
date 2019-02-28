#!/usr/bin/env bash
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
  