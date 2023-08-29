#!/usr/bin/env bash
#
# This script will interface with MPChecker: Minor Planet Checker
# http://scully.harvard.edu/~cgi/CheckMP
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

#echo -e "Starting $0"

# Test the command line arguments
if [ -z "$5" ];then
 echo " "
 echo "ERROR: search coordinates are not given! :("
 echo " "
 echo "Usage: $0 RA DEC YEAR MONTH DAYFRAC"
 echo "Example: $0 01:02:03.5 +05:06:07.8 2010 07 15.16789"
 exit 1
fi
RA=$1
DEC=$2

RAHH=`echo $RA |awk -F":" '{print $1}'`
RAMM=`echo $RA |awk -F":" '{print $2}'`
RASS=`echo $RA |awk -F":" '{print $3}'`

DECDD=`echo $DEC |awk -F":" '{print $1}'`
DECMM=`echo $DEC |awk -F":" '{print $2}'`
DECSS=`echo $DEC |awk -F":" '{print $3}'`

YEAR="$3"
MONTH="$4"
DAYFRAC="$5"

if [ -z "$6" ];then
 COLOR=1
else
 COLOR=0
fi  

if [ -z "$7" ];then
 MAG_FOR_MPC_REPORT="20.1"
else
 MAG_FOR_MPC_REPORT="$7"
fi

         
# Querry local copy of astcheck
if [ $COLOR -eq 1 ];then
 DATABASE_NAME="\033[01;36mastcheck\033[00m"
else
 DATABASE_NAME="<font color=\"teal\">astcheck</font>"
fi

ASTCHECK_OUTPUT=""

#####
# Check if the thing is (close to) a major planet
THIS_A_PLANET_OR_COMET=0
EXCLUSION_LIST_FILE="planets.txt"
if [ -s "$EXCLUSION_LIST_FILE" ];then
 PLANET_SEARCH_RESULTS=$(lib/put_two_sources_in_one_field "$RAHH:$RAMM:$RASS" "$DECDD:$DECMM:$DECSS" "$EXCLUSION_LIST_FILE" 400)
 echo "$PLANET_SEARCH_RESULTS" | grep --quiet "FOUND"
 if [ $? -eq 0 ];then
  #echo "$PLANET_SEARCH_RESULTS" | awk -F'FOUND' '{print $2}'
  ASTCHECK_OUTPUT=$(echo "$PLANET_SEARCH_RESULTS" | awk -F'FOUND' '{print $2}')
  THIS_A_PLANET_OR_COMET=1
 fi
fi
#####
#####
# Check if the thing is a bright comet
EXCLUSION_LIST_FILE="comets.txt"
if [ -s "$EXCLUSION_LIST_FILE" ] && [ $THIS_A_PLANET_OR_COMET -eq 0 ] ;then
 PLANET_SEARCH_RESULTS=$(lib/put_two_sources_in_one_field "$RAHH:$RAMM:$RASS" "$DECDD:$DECMM:$DECSS" "$EXCLUSION_LIST_FILE" 100)
 echo "$PLANET_SEARCH_RESULTS" | grep --quiet "FOUND"
 if [ $? -eq 0 ];then
  #echo "$PLANET_SEARCH_RESULTS" | awk -F'FOUND' '{print $2}'
  ASTCHECK_OUTPUT=$(echo "$PLANET_SEARCH_RESULTS" | awk -F'FOUND' '{print $2}')
  THIS_A_PLANET_OR_COMET=1
 fi
fi
#####



if [ -z "$ASTCHECK_OUTPUT" ];then
 # This script should take care of updating astorb.dat
 lib/update_offline_catalogs.sh all
 
 if [ ! -f astorb.dat ];then
  # astorb.dat needs to be downloaded
  echo "Downloading the asteroid database (astorb.dat)" 1>&2
  #wget -c ftp://ftp.lowell.edu/pub/elgb/astorb.dat.gz 1>&2
  wget -c --no-check-certificate https://kirx.net/~kirx/vast_catalogs/astorb.dat.gz 1>&2
  if [ $? -ne 0 ];then
   # a desperate recovery attempt
   wget -c http://kirx.net/~kirx/vast_catalogs/astorb.dat.gz 1>&2
   if [ $? -ne 0 ];then
    echo "ERROR: cannot download astorb.dat.gz"
    exit 1
   fi
  fi
  gunzip astorb.dat.gz
  if [ $? -ne 0 ];then
   echo "ERROR: cannot gunzip astorb.dat.gz"
   exit 1
  fi
  if [ ! -f astorb.dat ];then
   echo "ERROR: cannot find astorb.dat"
   exit 1
  fi
 fi
 # Using local copy of astcheck to identify asteroids! See http://home.gwi.net/~pluto/devel/astcheck.htm for details
 echo "$YEAR $MONTH $DAYFRAC $RAHH $RAMM $RASS  $DECDD $DECMM $DECSS  $MAG_FOR_MPC_REPORT" |awk '{printf "     TAU0008  C%s %02.0f %08.5f %02.0f %02.0f %05.2f %+02.0f %02.0f %05.2f         %4.1f R      500\n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10}' > test.mpc
 # 400" is the search radius
 ASTCHECK_OUTPUT=$(lib/astcheck test.mpc -r400 -m15 |grep -A 50 "TAU0008" |grep -v "TAU0008" |head -n 1 | grep -v ObsCodes.html)
fi 

if [ -z "$ASTCHECK_OUTPUT" ] && [ $THIS_A_PLANET_OR_COMET -eq 0 ] ;then
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;32mnot found\033[00m in $DATABASE_NAME."
 else
  echo -e "The object was <font color=\"green\">not found</font> in $DATABASE_NAME."
 fi
 exit 1 # return code will signal we have no ID
else
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;31mfound\033[00m in $DATABASE_NAME.  "
 else
  echo -e "<b>The object was <font color=\"red\">found</font> in $DATABASE_NAME.</b>  "
 fi 
 echo "$ASTCHECK_OUTPUT"
 exit 0 # return code will signal we have an ID
fi # else lib/astcheck 
