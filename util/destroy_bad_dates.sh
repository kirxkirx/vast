#!/usr/bin/env bash
#
# This script will remove selected Julian Dates from all lightcurve files
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

BAD_DATES="40395.474 40395.501 43274.581 43274.604 43274.626 45053.567 40395.474  40395.501 43274.581 43274.604 43274.626 45053.567 43275.49 43275.514 43275.541 43275.564 43275.587 43274.492 41391.556 43274.515 43274.537 43274.559 45368.269 44762.389 45326.649 46591.389 40701.34 43274.537 43274.559 46910.416 41391.556 43274.537 43275.514 43275.587 45051.384 46910.416 45326.649"
#
#
for i in out*.dat ;do
 mv -f $i tmp
 for j in $BAD_DATES ;do
  grep -v "$j" tmp > tmp2
  mv -f tmp2 tmp
 done 
 mv -f tmp $i
done
