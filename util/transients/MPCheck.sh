#!/usr/bin/env bash
#
# This script will interface with MPChecker: Minor Planet Checker
# http://scully.harvard.edu/~cgi/CheckMP
#
echo -e "Starting $0"

# Test the command line arguments
if [ -z $4 ];then
 echo " "
 echo "ERROR: search coordinates are not given! :("
 echo " "
 echo "Usage: $0 RA DEC DATE TIME"
 echo "Example: $0 01:02:03.5 +05:06:07.8 10.12.2010 00:23:40"
 exit
fi
RA=$1
DEC=$2
DATE=$3
TIME=$4

RAHH=`echo $RA |awk -F":" '{print $1}'`
RAMM=`echo $RA |awk -F":" '{print $2}'`
RASS=`echo $RA |awk -F":" '{print $3}'`

DECDD=`echo $DEC |awk -F":" '{print $1}'`
DECMM=`echo $DEC |awk -F":" '{print $2}'`
DECSS=`echo $DEC |awk -F":" '{print $3}'`

DAY=`echo $DATE |awk -F"." '{print $1}'`
MONTH=`echo $DATE |awk -F"." '{print $2}'`
YEAR=`echo $DATE |awk -F"." '{print $3}'`

TIMEH=`echo $TIME |awk -F":" '{print $1}'`
TIMEM=`echo $TIME |awk -F":" '{print $2}'`
TIMES=`echo $TIME |awk -F":" '{print $2}'`

#DAYFRAC=`echo "$DAY+$TIMEH/24+$TIMEM/1440+$TIMES/86400"|bc -ql|awk '{printf "%08.5f\n",$1}'`
DAYFRAC=`echo "$DAY $TIMEH $TIMEM $TIMES"| awk '{printf "%08.5f\n",$1+$2/24+$3/1440+$4/86400}'`

if [ -z "$5" ];then
 COLOR=1
else
 COLOR=0
fi  

if [ -z "$6" ];then
 MAG_FOR_MPC_REPORT="20.1"
else
 MAG_FOR_MPC_REPORT="$6"
fi

# Thest if curl is installed
CURL=`command -v curl`
if [ $? -ne 0 ];then
 echo " "
 echo "ERROR: curl not found. :("
 echo "No web search will be done!"
 echo " "
 exit
fi
CURL="$CURL -H 'Expect:'"
         
# Querry local copy of astcheck
if [ $COLOR -eq 1 ];then
 DATABASE_NAME="\033[01;36mastcheck\033[00m"
else
 DATABASE_NAME="<font color=\"teal\">astcheck</font>"
fi

# This script should take care of updating astorb.dat
lib/update_offline_catalogs.sh all


if [ -f lib/astcheck ];then
 if [ ! -f astorb.dat ];then
  # astorb.dat needs to be downloaded
  echo "Downloading the asteroid database (astorb.dat)" >> /dev/stderr
  #wget -c ftp://ftp.lowell.edu/pub/elgb/astorb.dat.gz &> /dev/stderr
  wget -c http://scan.sai.msu.ru/~kirx/pub/astorb.dat.gz &> /dev/stderr
  gunzip astorb.dat.gz
  if [ ! -f astorb.dat ];then
   echo "ERROR: cannot download astorb.dat.gz"
   exit
  fi
 fi
# echo "Using local copy of astcheck to identify asteroids! See http://home.gwi.net/~pluto/devel/astcheck.htm for details."
 echo "$YEAR $MONTH $DAYFRAC $RAHH $RAMM $RASS  $DECDD $DECMM $DECSS  $MAG_FOR_MPC_REPORT" |awk '{printf "     TAU0008  C%s %02.0f %08.5f %02.0f %02.0f %05.2f %+02.0f %02.0f %05.2f         %4.1f R      500\n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10}' > test.mpc
 #lib/astcheck test.mpc -r100 -m15 |grep -A 50 "TAU0008" |grep -v "TAU0008" |head -n 1 | grep -v ObsCodes.html
 # We need the 250" search radius to find ceres with the available custom (=old) astorb.dat
 #lib/astcheck test.mpc -r300 -m15 |grep -A 50 "TAU0008" |grep -v "TAU0008" |head -n 1 | grep -v ObsCodes.html
 lib/astcheck test.mpc -r400 -m15 |grep -A 50 "TAU0008" |grep -v "TAU0008" |head -n 1 | grep -v ObsCodes.html
 if [ $? -eq 1 ];then
  if [ $COLOR -eq 1 ];then
   echo -e "The object was \033[01;31mnot found\033[00m in $DATABASE_NAME."
  else
   echo -e "The object was <font color=\"red\">not found</font> in $DATABASE_NAME."
  fi
  else
  if [ $COLOR -eq 1 ];then
   echo -e "The object was \033[01;32mfound\033[00m in $DATABASE_NAME.  "
  else
   echo -e "The object was <font color=\"green\">found</font> in $DATABASE_NAME.  "
  fi 
 fi
fi

# !!!
exit

# Querry MPChecker (works only for recent data!)
if [ $COLOR -eq 1 ];then
 DATABASE_NAME="\033[01;36mMPChecker\033[00m"
else
 DATABASE_NAME="<font color=\"teal\">MPChecker</font>"
fi

echo -e "$DATABASE_NAME querry:  $RAHH $RAMM $RASS  $DECDD $DECMM $DECSS  $YEAR $MONTH $DAYFRAC"

#$CURL  --silent --max-time 90 --data "year=$YEAR&month=$MONTH&day=$DAYFRAC&which=pos&ra=$RAHH+$RAMM+$RASS&decl=$DECDD+$DECMM+$DECSS&TextArea=&radius=5&limit=15.0&oc=500&sort=d&mot=h&tmot=t&pdes=u&needed=f&ps=n&type=p" "http://scully.cfa.harvard.edu/~cgi/MPCheck.COM" > curlhack.html
grep "No known minor planets" curlhack.html
if [ $? -eq 0 ];then
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;31mnot found\033[00m in $DATABASE_NAME."
 else
  echo -e "The object was <font color=\"red\">not found</font> in $DATABASE_NAME."
 fi
else
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;32mfound\033[00m in $DATABASE_NAME:  "
 else
  echo -e "The object was <font color=\"green\">found</font> in $DATABASE_NAME:  "
 fi 
 SWITCH=1
 while read STR ;do
  if [ $SWITCH -eq 0 ];then
   echo $STR
  fi
  echo "$STR" | grep "<pre>" &>/dev/null
  if [ $? -eq 0 ];then
   SWITCH=0
  fi
  echo "$STR" | grep "</pre>" &>/dev/null
  if [ $? -eq 0 ];then
   break
  fi
 done < curlhack.html
fi
   
