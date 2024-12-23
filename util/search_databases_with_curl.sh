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
if [ -z "$2" ];then
 echo " "
 echo "ERROR: search coordinates are not given! :("
 echo " "
 echo "Usage: $0 RA DEC"
 exit 1
fi
RA="$1"
DEC="$2"


if [ -z "$3" ];then
 COLOR=1
else
 COLOR=0
fi

function check_if_the_vsx_page_looks_legit_and_we_might_be_having_parsing_issues {
 if [ -z "$1" ];then
  echo "ERROR using check_if_the_vsx_page_looks_legit_and_we_might_be_having_parsing_issues() function - it needs an argument"
  return 1
 fi
 VSX_PAGE_CONTENT_FILE="$1"
 if [ ! -f "$VSX_PAGE_CONTENT_FILE" ];then
  # no file 
  return 1
 fi
 if [ ! -s "$VSX_PAGE_CONTENT_FILE" ];then
  # empty file 
  return 1
 fi
 grep --quiet --ignore-case '</html>' "$VSX_PAGE_CONTENT_FILE"
 if [ $? -ne 0 ];then
  # no closing html tag - possibly incomplete file?
  return 1
 fi
 grep --quiet --ignore-case 'Variable Star Index' "$VSX_PAGE_CONTENT_FILE"
 if [ $? -ne 0 ];then
  # expect to find words 'Variable Star Index' on the page
  return 1
 fi
 grep --quiet --ignore-case 'New Search' "$VSX_PAGE_CONTENT_FILE"
 if [ $? -ne 0 ];then
  # expect to find words 'New Search' on the page
  return 1
 fi
 grep --quiet --ignore-case 'AUID' "$VSX_PAGE_CONTENT_FILE"
 if [ $? -ne 0 ];then
  # expect to find word 'AUID' on the page
  return 1
 fi
 
 # if we are still here - the input looks like a legit VSX HTML page
 return 0
}


# A more portable realpath wrapper
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
      cd "$(dirname "$1")" || exit 1
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit 1
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

# Function to remove the last occurrence of a directory from a path
remove_last_occurrence() {
    echo "$1" | awk -F/ -v dir=$2 '{
        found = 0;
        for (i=NF; i>0; i--) {
            if ($i == dir && found == 0) {
                found = 1;
                continue;
            }
            res = (i==NF ? $i : $i "/" res);
        }
        print res;
    }'
}

# Function to get full path to vast main directory from the script name
get_vast_path_ends_with_slash_from_this_script_name() {
 VAST_PATH=$(vastrealpath $0)
 VAST_PATH=$(dirname "$VAST_PATH")

 # Remove last occurrences of util, lib, examples
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "util")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "lib")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "examples")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "transients")

 # Make sure no '//' are left in the path (they look ugly)
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")

 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")

 # Check that VAST_PATH ends with '/'
 LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
 if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
  VAST_PATH="$VAST_PATH/"
 fi

 echo "$VAST_PATH"
}


if [ -z "$VAST_PATH" ];then
 VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
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

# Test if curl is installed
CURL=$(command -v curl)
if [ $? -ne 0 ];then
 echo " "
 echo "ERROR: curl not found. :("
 echo "No web search will be done!"
 echo " "
 exit 1
fi

# Find timeout command
TIMEOUTCOMMAND=$("$VAST_PATH"lib/find_timeout_command.sh)
if [ $? -ne 0 ];then
 echo " "
 echo "WARNING: cannot find the timeout command :("
 echo " "
# We don't need to exit, we can try to work without timeout
 TIMEOUTCOMMAND=" "
else
 TIMEOUTCOMMAND="$TIMEOUTCOMMAND 300 "
fi

# Querry GCVS
if [ $COLOR -eq 1 ];then
 DATABASE_NAME="\033[01;35mGCVS\033[00m"
else
 DATABASE_NAME="<font color=\"purple\">GCVS</font>"
fi
DEC_STUPID_PLUS_GCVS=$(echo $DEC |awk -F: '{print $1}')
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
DATABASE_RESULTS=$($TIMEOUTCOMMAND $CURL $VAST_CURL_PROXY --silent --max-time 45 "http://www.sai.msu.su/gcvs/cgi-bin/co-h.cgi?coor=${RA//:/+}+${DEC_STUPID_PLUS_GCVS//:/+}&radius=60" | grep \| )
if [ "$DATABASE_RESULTS" != "" ];then
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;32mfound\033[00m in $DATABASE_NAME:  "
 else
  echo -e "The object was <font color=\"green\">found</font> in $DATABASE_NAME:  "
 fi
 DATABASE_RESULTS=$(echo $DATABASE_RESULTS | awk -F"<pre>" '{print $6}')
 DATABASE_RESULTS=$(echo ${DATABASE_RESULTS//"</pre>"/""})
 DATABASE_RESULTS=$(echo "$DATABASE_RESULTS" | sed 's/>[^<]*<//g' | sed 's/<[^>]*>//g')
 # Cut out the first word which is the distance from the specified position
 DATABASE_RESULTS=$(echo "${DATABASE_RESULTS#* }")
 #
 echo "$DATABASE_RESULTS"
 exit # no further search if the target is found in GCVS !!! 
else
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;31mnot found\033[00m in $DATABASE_NAME."
 else
  echo -e "The object was <font color=\"red\">not found</font> in $DATABASE_NAME."
 fi
fi

# clean up any rmains of a previous VSX interaction with the same PID - just in case
for FILE_TO_REMOVE in vsx_page_content$$.html vsx_page_content$$.error ;do
 if [ -f "$FILE_TO_REMOVE" ];then
  rm -f "$FILE_TO_REMOVE"
 fi
done

# Querry VSX now, but parse later, so this querry is parallel to SIMBAD
# --silent --show-error will suppress the progress bar but not error messages
#echo $CURL --insecure --max-time 60 --data "targetcenter=$RA%20$DEC&format=s&constid=0&fieldsize=0.5&fieldunit=2&geometry=r&order=9&ql=1&filter[]=0,1,2" "https://www.aavso.org/vsx/index.php?view=results.submit1" > /tmp/t
#echo "
#
#DEBUG - first try
#$CURL $VAST_CURL_PROXY --silent --show-error --insecure --connect-timeout 10 --max-time 120 --data \"targetcenter=$RA%20$DEC&format=s&constid=0&fieldsize=0.5&fieldunit=2&geometry=r&order=9&ql=1&filter[]=0,1,2\" \"https://www.aavso.org/vsx/index.php?view=results.submit1\"
#
#"
$TIMEOUTCOMMAND $CURL $VAST_CURL_PROXY --silent --show-error --insecure --connect-timeout 10 --max-time 120 --data "targetcenter=$RA%20$DEC&format=s&constid=0&fieldsize=0.5&fieldunit=2&geometry=r&order=9&ql=1&filter[]=0,1,2" "https://www.aavso.org/vsx/index.php?view=results.submit1" 2> vsx_page_content$$.error > vsx_page_content$$.html &
# a working example as of 2023-05-12:
#curl 'https://www.aavso.org/vsx/index.php?view=results.submit1' -X POST -H 'Content-Type: application/x-www-form-urlencoded' -H 'DNT: 1' -H 'Connection: keep-alive' -H 'Upgrade-Insecure-Requests: 1' -H 'Sec-Fetch-Dest: document' -H 'Sec-Fetch-Mode: navigate' -H 'Sec-Fetch-Site: same-origin' -H 'Sec-Fetch-User: ?1' --data-raw 'ql=1&getCoordinates=0&plotType=Search&special=index.php%3Fview%3Dresults.special%26sid%3D2&ident=&constid=0&targetcenter=07%3A29%3A19.69+-13%3A23%3A06.6&format=s&fieldsize=1&fieldunit=3&geometry=r&filter%5B%5D=0&filter%5B%5D=1&filter%5B%5D=2&filter%5B%5D=3&order=1' > vsx_page_content$$.html &

 
# Querry SIMBAD
if [ $COLOR -eq 1 ];then
 DATABASE_NAME="\033[01;31mSIMBAD\033[00m"
else
 DATABASE_NAME="<font color=\"maroon\">SIMBAD</font>"
fi
# Try to querry SIMBAD multiple times with different search radius 
# since the simple parser will recognize object if this is the single SIMBAD object in the field.
for SIMBAD_SEARCH_RADIUS in 0.05 1 0.02 0.5 ;do
 DATABASE_RESULTS=$($TIMEOUTCOMMAND $CURL $VAST_CURL_PROXY --silent --max-time 30 --data "Coord=$RA%20$DEC&CooDefinedFrames=J2000&Radius=$SIMBAD_SEARCH_RADIUS&Radius.unit=arcmin" "http://simbad.u-strasbg.fr/simbad/sim-coo" |grep -v \< |grep -A3 "Basic" |tail -n3)
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
# move up to speed up
#$TIMEOUTCOMMAND $CURL  --silent --max-time 30 --data "targetcenter=$RA%20$DEC&format=s&constid=0&fieldsize=0.5&fieldunit=2&geometry=r&order=9&ql=1&filter[]=0,1,2" "http://www.aavso.org/vsx/index.php?view=results.submit1" > vsx_page_content$$.html
wait
#
# disabled as kirx.net proxy is banned at VSX, thanks AAVSO
#
# vsx_page_content$$.error - will not be enpty if we are not using --silent !
#if [ -s vsx_page_content$$.error ] || ! check_if_the_vsx_page_looks_legit_and_we_might_be_having_parsing_issues vsx_page_content$$.html ;then
# echo "
# 
# YOHOHO, an error, see below the content of vsx_page_content$$.error
# 
# "
# cat vsx_page_content$$.error
# echo "
# 
# YOHOHO, an error, see above the content of vsx_page_content$$.error
# 
# "
# # There was en error connecting to VSX
# rm -f vsx_page_content$$.error
# # Retry connecting via the reverse proxy
# #$TIMEOUTCOMMAND $CURL                 --insecure --connect-timeout 10 --max-time 120         --data "targetcenter=$RA%20$DEC&format=s&constid=0&fieldsize=0.5&fieldunit=2&geometry=r&order=9&ql=1&filter[]=0,1,2" "https://www.aavso.org/vsx/index.php?view=results.submit1" 2> vsx_page_content$$.error > vsx_page_content$$.html &
## echo "
## 
## DEBUG -- second try
## 
## $CURL $VAST_CURL_PROXY --silent --show-error --insecure --connect-timeout 10 --max-time 30 --data \"targetcenter=$RA%20$DEC&format=s&constid=0&fieldsize=0.5&fieldunit=2&geometry=r&order=9&ql=1&filter[]=0,1,2\" \"https://kirx.net/vsx/index.php?view=results.submit1\" 
##
## "
# $TIMEOUTCOMMAND $CURL $VAST_CURL_PROXY --silent --show-error --insecure --connect-timeout 10 --max-time 30 --data "targetcenter=$RA%20$DEC&format=s&constid=0&fieldsize=0.5&fieldunit=2&geometry=r&order=9&ql=1&filter[]=0,1,2" "https://kirx.net/vsx/index.php?view=results.submit1" 2> vsx_page_content$$.error > vsx_page_content$$.html
# # There will be no vsx_page_content$$.error content if the request is timing out after --max-time becasue the request is outright blocked - thanks AAVSO
# if [ -s vsx_page_content$$.error ] || ! check_if_the_vsx_page_looks_legit_and_we_might_be_having_parsing_issues vsx_page_content$$.html ;then
#  cat vsx_page_content$$.error
#  # There was en error connecting to VSX
#  rm -f vsx_page_content$$.error
#  # Retry connecting via HTTP reverse proxy
#  $TIMEOUTCOMMAND $CURL $VAST_CURL_PROXY --silent --show-error --insecure --connect-timeout 20 --max-time 60 --data "targetcenter=$RA%20$DEC&format=s&constid=0&fieldsize=0.5&fieldunit=2&geometry=r&order=9&ql=1&filter[]=0,1,2" "http://kirx.net/vsx/index.php?view=results.submit1" 2> vsx_page_content$$.error > vsx_page_content$$.html
##  echo "
## 
## DEBUG -- third try
##
## $CURL $VAST_CURL_PROXY --silent --show-error --insecure --connect-timeout 20 --max-time 60 --data \"targetcenter=$RA%20$DEC&format=s&constid=0&fieldsize=0.5&fieldunit=2&geometry=r&order=9&ql=1&filter[]=0,1,2\" \"http://kirx.net/vsx/index.php?view=results.submit1\" 
##
## "
# fi
#fi
###
#cat vsx_page_content$$.html
##
if [ ! -s vsx_page_content$$.html ] ;then echo "!!! Network error: cannot connect to VSX !!!" ;fi
DATABASE_RESULTS=$(grep '\<desig' vsx_page_content$$.html |awk -F\> '{print $3}')
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
# clean up
for FILE_TO_REMOVE in vsx_page_content$$.html vsx_page_content$$.error ;do
 if [ -f "$FILE_TO_REMOVE" ];then
  rm -f "$FILE_TO_REMOVE"
 fi
done


