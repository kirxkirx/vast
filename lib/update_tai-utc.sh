#!/usr/bin/env bash

# Sadly, maia is long dead

# This script should check how old is the TAI-UTC file lib/tai-utc.dat
# and update it from http://maia.usno.navy.mil/ser7/tai-utc.dat if needed

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

############################################
exit 0
# There is no more proper way to update tai-utc.dat so we just quit
############################################


if [ -z "$1" ];then
 NEED_TO_UPDATE_THE_FILE=0
else
 NEED_TO_UPDATE_THE_FILE=1
fi

# Get current date from the system clock
CURRENT_DATE_UNIXSEC=`date +%s`

# check if the file is there at all
if [ ! -f lib/tai-utc.dat ];then
 echo "ERROR opening file lib/tai-utc.dat" 1>&2
 NEED_TO_UPDATE_THE_FILE=1
else
 # First try Linux-style stat
 TAImUTC_DAT_FILE_MODIFICATION_DATE=`stat -c "%Y" lib/tai-utc.dat 2>/dev/null`
 if [ $? -ne 0 ];then
  TAImUTC_DAT_FILE_MODIFICATION_DATE=`stat -f "%m" lib/tai-utc.dat 2>/dev/null`
  if [ $? -ne 0 ];then
   echo "ERROR cannot get modification time for lib/tai-utc.dat" 1>&2
   exit 1
  fi
 fi
fi

# 15552000 is about 6 months
if [ $[$CURRENT_DATE_UNIXSEC-$TAImUTC_DAT_FILE_MODIFICATION_DATE] -gt 15552000 ];then
 NEED_TO_UPDATE_THE_FILE=1
fi

# everything is down forever

# Update the file if needed
#if [ $NEED_TO_UPDATE_THE_FILE -eq 1 ];then
# # down forever
# wget --timeout=20 --tries=1 -O tai-utc.dat.new "http://maia.usno.navy.mil/ser7/tai-utc.dat"
# if [ $? -ne 0 ];then
#  echo "ERROR running wget" 1>&2
#  if [ -f tai-utc.dat.new ];then
#   rm -f tai-utc.dat.new
#  fi
##Here we would try other servers, but there are no other servers anymore
#  # down forever
#  wget --timeout=20 --tries=1 -O tai-utc.dat.new "ftp://toshi.nofs.navy.mil/ser7/tai-utc.dat"
#  if [ $? -ne 0 ];then
#   echo "ERROR2 running wget" 1>&2
#   if [ -f tai-utc.dat.new ];then
#    rm -f tai-utc.dat.new
#   fi
#   # ftp link down forever, http access requires registration
#   wget --timeout=20 --tries=1 -O tai-utc.dat.new "ftp://cddis.gsfc.nasa.gov/pub/products/iers/tai-utc.dat"
#   if [ $? -ne 0 ];then
#    echo "ERROR2 running wget" 1>&2
#    exit 1
#   fi
#  fi
# fi
 if [ ! -s tai-utc.dat.new ];then
  echo "ERROR: tai-utc.dat.new is EMPTY!" 1>&2
  exit 1
 fi
 mv -v tai-utc.dat.new lib/tai-utc.dat && touch lib/tai-utc.dat
fi
