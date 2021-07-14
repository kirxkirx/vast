#!/usr/bin/env bash
#
# This script will search the web for known variable stars
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

echo -e "Starting $0"

# Test the command line arguments
if [ -z $2 ];then
 echo " "
 echo "ERROR: search coordinates are not given! :("
 echo " "
 echo "Usage: $0 RA DEC"
 exit 1
fi
RA=$1
DEC=$2


if [ -z $3 ];then
 COLOR=1
else
 COLOR=0
fi


function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=`readlink -f "$1" 2>/dev/null`
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=`greadlink -f "$1" 2>/dev/null`
   if [ $? -ne 0 ];then
    REALPATH=`realpath "$1" 2>/dev/null`
    if [ $? -ne 0 ];then
     REALPATH=`grealpath "$1" 2>/dev/null`
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")"
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD"
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}


if [ -z "$VAST_PATH" ];then
 #VAST_PATH=`readlink -f $0`
 VAST_PATH=`vastrealpath $0`
 VAST_PATH=`dirname "$VAST_PATH"`
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=`echo "$VAST_PATH" | sed "s:'::g"`
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
#

# Check if the input coordinates are good
if "$VAST_PATH"lib/hms2deg "$RA" "$DEC" &>/dev/null || "$VAST_PATH"lib/deg2hms "$RA" "$DEC" &>/dev/null ;then echo YES ;fi | grep --quiet 'YES'
if [ $? -ne 0 ];then
 echo "ERROR parding the input coordinates!"
 exit 1
fi


echo "Searching databases for object $RA $DEC"

# Thest if curl is installed
CURL=`command -v curl`
if [ $? -ne 0 ];then
 echo " "
 echo "ERROR: curl not found. :("
 echo "No web search will be done!"
 echo " "
 exit 1
fi

# Find timeout command
TIMEOUTCOMMAND=`"$VAST_PATH"lib/find_timeout_command.sh`
if [ $? -ne 0 ];then
 echo " "
 echo "WARNING: cannot find the timeout command :("
 echo " "
# We don't need to exit, we can try to work without timeout
# exit 1
else
 TIMEOUTCOMMAND="$TIMEOUTCOMMAND 300 "
fi

# Querry GCVS
if [ $COLOR -eq 1 ];then
 DATABASE_NAME="\033[01;35mGCVS\033[00m"
else
 DATABASE_NAME="<font color=\"purple\">GCVS</font>"
fi
DEC_STUPID_PLUS_GCVS=`echo $DEC |awk -F: '{print $1}'`
echo $DEC_STUPID_PLUS_GCVS |grep \- &>/dev/null
if [ $? -eq 0 ];then
 DEC_STUPID_PLUS_GCVS="$DEC"
else
 DEC_STUPID_PLUS_GCVS=\%2B${DEC//+/""}
fi
#echo "
#
#$CURL --silent --max-time 30 \"http://www.sai.msu.su/gcvs/cgi-bin/co-h.cgi?coor=${RA//:/+}+${DEC_STUPID_PLUS_GCVS//:/+}&radius=60\"
#
#" 1>&2
DATABASE_RESULTS=`$TIMEOUTCOMMAND $CURL --silent --max-time 30 "http://www.sai.msu.su/gcvs/cgi-bin/co-h.cgi?coor=${RA//:/+}+${DEC_STUPID_PLUS_GCVS//:/+}&radius=60"|grep \|`
#DATABASE_RESULTS=`$CURL --silent --max-time 30 "http://www.sai.msu.su/gcvs/cgi-bin/co-h.cgi?coor=${RA//:/+}+${DEC_STUPID_PLUS_GCVS//:/+}&radius=60" |grep \|`
#echo $CURL --silent --max-time 30 \""http://www.sai.msu.su/gcvs/cgi-bin/co-h.cgi?coor=${RA//:/+}+${DEC_STUPID_PLUS_GCVS//:/+}&radius=60"\"
#echo "## $DATABASE_RESULTS ##"
if [ "$DATABASE_RESULTS" != "" ];then
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;32mfound\033[00m in $DATABASE_NAME:  "
 else
  echo -e "The object was <font color=\"green\">found</font> in $DATABASE_NAME:  "
 fi
 #DATABASE_RESULTS=`echo $DATABASE_RESULTS |awk -F"<P>" '{print $6}'`
 # the above seems not to work anymore due to changes output of the GCVS querry form
 DATABASE_RESULTS=`echo $DATABASE_RESULTS |awk -F"<pre>" '{print $6}'`
 DATABASE_RESULTS=`echo ${DATABASE_RESULTS//"</pre>"/""}`
 DATABASE_RESULTS=`echo "$DATABASE_RESULTS" | sed 's/>[^<]*<//g' | sed 's/<[^>]*>//g'`
 # Cut out the first word which is the distance from the specified position
 DATABASE_RESULTS=`echo "${DATABASE_RESULTS#* }"`
 #
 echo "$DATABASE_RESULTS"
 exit # !!! 
else
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;31mnot found\033[00m in $DATABASE_NAME."
 else
  echo -e "The object was <font color=\"red\">not found</font> in $DATABASE_NAME."
 fi
fi
 
# Querry SIMBAD
if [ $COLOR -eq 1 ];then
 DATABASE_NAME="\033[01;31mSIMBAD\033[00m"
else
 DATABASE_NAME="<font color=\"maroon\">SIMBAD</font>"
fi
# Try to querry SIMBAD multiple times with different search radius 
# since the simple parser will recognize object if this is the single SIMBAD object in the field.
for SIMBAD_SEARCH_RADIUS in 0.05 1 0.02 0.5 ;do
 DATABASE_RESULTS=`$TIMEOUTCOMMAND $CURL --silent --max-time 30 --data "Coord=$RA%20$DEC&CooDefinedFrames=J2000&Radius=$SIMBAD_SEARCH_RADIUS&Radius.unit=arcmin" "http://simbad.u-strasbg.fr/simbad/sim-coo" |grep -v \< |grep -A3 "Basic" |tail -n3`
 if [ "$DATABASE_RESULTS" != "" ];then
  if [ $COLOR -eq 1 ];then
   echo -e "The object was \033[01;32mfound\033[00m in $DATABASE_NAME:  "
  else
   echo -e "The object was <font color=\"green\">found</font> in $DATABASE_NAME:  "
  fi
  echo $DATABASE_RESULTS
  break
 fi
done
if [ "$DATABASE_RESULTS" = "" ];then
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;31mnot found\033[00m in $DATABASE_NAME."
 else
  echo -e "The object was <font color=\"red\">not found</font> in $DATABASE_NAME."
 fi
fi

#Querry VSX
if [ $COLOR -eq 1 ];then
 DATABASE_NAME="\033[01;34mVSX\033[00m"
else
 DATABASE_NAME="<font color=\"blue\">VSX</font>"
fi
$TIMEOUTCOMMAND $CURL  --silent --max-time 30 --data "targetcenter=$RA%20$DEC&format=s&constid=0&fieldsize=0.5&fieldunit=2&geometry=r&order=9&ql=1&filter[]=0,1,2" "http://www.aavso.org/vsx/index.php?view=results.submit1" > curlhack.html
if [ ! -s curlhack.html ] ;then echo "!!! Network error: cannot connect to VSX !!!" ;fi
DATABASE_RESULTS=`grep '\<desig' curlhack.html |awk -F\> '{print $3}'`
if [ "$DATABASE_RESULTS" != "" ];then
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;32mfound\033[00m in $DATABASE_NAME:  "
 else
  echo -e "The object was <font color=\"green\">found</font> in $DATABASE_NAME:  "
 fi
 echo -e "${DATABASE_RESULTS//"</a"/     }"
else
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;31mnot found\033[00m in $DATABASE_NAME."
 else
  echo -e "The object was <font color=\"red\">not found</font> in $DATABASE_NAME."
 fi
fi
rm -f curlhack.html
