#!/usr/bin/env bash 
#################################
# This script will upload a lightcurve to the web-based period search service.
#################################
# Check if lightcurve file was supplied ($1)
if [ -z "$1" ];then
 echo "ERROR: no lightcurve file name is supplied!"
 echo " "
 echo "Usage:  $0 outNNNN.dat"
 exit
fi
#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################
#################################
# Check if lightcurve file ($1) exist
if [ ! -f "$1" ];then
 echo "ERROR: lightcurve file $1 does not exist!"
 echo " "
 echo "Usage:  $0 outNNNN.dat"
 exit
fi
# Check if the input lightcurve file is empty
if [ ! -s "$1" ];then
 echo "ERROR: lightcurve file $1 is empty!"
 echo " "
 echo "Usage:  $0 outNNNN.dat"
 exit
fi
#################################
#################################
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
#################################
# Thest if curl is installed
CURL=`command -v curl`
if [ $? -ne 0 ];then
 echo " "
 echo "ERROR: curl not found. :("
 echo "Please install curl ..."
 echo " "
 exit 1
fi
# -H 'Expect:' is specifically useful to suppress the default behavior of curl when sending large POST requests. By default, for POST requests larger than 1024 bytes, curl will add an Expect: 100-continue header automatically.
CURL="$CURL -H 'Expect:'"
###################################################
echo -n "Checking if we can reach any period search servers... "
if [ -z "$PERIOD_SEARCH_SERVER" ] || [ "$PERIOD_SEARCH_SERVER" = "none" ];then
 # Decide on which period search server to use
 # first - set the initial list of servers
 #PERIOD_SEARCH_SERVERS="scan.sai.msu.ru polaris.kirx.net vast.sai.msu.ru"
 # polaris.kirx.net is actually pretty slow...
 # vast.sai.msu.ru disabled until the software is updated there
 PERIOD_SEARCH_SERVERS="scan.sai.msu.ru"
else
 # PERIOD_SEARCH_SERVER is externally set, but we still want to check if it's rachable
 PERIOD_SEARCH_SERVERS="$PERIOD_SEARCH_SERVER"
fi
rm -f server_*.ping_ok
for i in $PERIOD_SEARCH_SERVERS ;do
 ping -c1 -n "$i" &>/dev/null && echo "$i" > server_"$i".ping_ok &
 echo -n "$i "
done

wait

### The ping test will not work if we are behind a firewall that doesn't let ping out
# If no servers could be reached, try to test for this possibility
########################################
for SERVER_PING_OK_FILE in server_*.ping_ok ;do
 if [ -f "$SERVER_PING_OK_FILE" ];then
  # OK we could ping at least one server
  break
 fi
 # If we are still here, that means we are either offline or behind a firewall that doesn't let ping out
 for i in $PERIOD_SEARCH_SERVERS ;do
  curl --max-time 10 --silent http://"$i"/astrometry_engine/files/ | grep --quiet 'Parent Directory' && echo "$i" > server_"$i".ping_ok &
  echo -n "$i "
 done
 wait
done
########################################

cat server_*.ping_ok > servers.ping_ok

echo "
The reachable servers are:"
cat servers.ping_ok

if [ ! -s servers.ping_ok ];then
 echo "ERROR: no servers could be reached!
Please check your internet connection..."
 exit 1
fi
   
# Choose a random server among the available ones
PERIOD_SEARCH_SERVER=`$("$VAST_PATH"lib/find_timeout_command.sh) 10 sort --random-sort --random-source=/dev/urandom servers.ping_ok | head -n1`
# If the above fails because sort doesn't understand the '--random-sort' option
if [ "$PERIOD_SEARCH_SERVER" = "" ];then
 PERIOD_SEARCH_SERVER=`head -n1 servers.ping_ok`
fi
   
# Update the list of available servers
PERIOD_SEARCH_SERVERS=""
while read SERVER ;do
 PERIOD_SEARCH_SERVERS="$PERIOD_SEARCH_SERVERS $SERVER"
done < servers.ping_ok
echo "Updated list of available servers: $PERIOD_SEARCH_SERVERS"
rm -f server_*.ping_ok servers.ping_ok

# Check if we are requested to use a specific server
if [ ! -z "$FORCE_PERIOD_SEARCH_SERVER" ];then
 if [ "$FORCE_PERIOD_SEARCH_SERVER" != "none" ];then
  echo "WARNING: using the user-specified period search server $FORCE_PERIOD_SEARCH_SERVER"
  PERIOD_SEARCH_SERVER="$FORCE_PERIOD_SEARCH_SERVER"
  PERIOD_SEARCH_SERVERS="$PERIOD_SEARCH_SERVER"
 fi
fi
   
if [ -z "$PERIOD_SEARCH_SERVER" ];then
 echo "Error choosing the period search server"
 exit 1
fi
###################################################

#################################
# Do the actual work

# Make up a good name for the converted file
NEWFILENAME=`basename "$1"`
NEWFILENAME=${NEWFILENAME// /_}

# Make sure we have a directory to save the converted file
if [ ! -d "$VAST_PATH"saved_period_search_lightcurves ];then
 mkdir "$VAST_PATH"saved_period_search_lightcurves
fi

# Convert the input lightcurve file to the software-friendly ASCII
echo "Pre-processing the lightcurve file by running"
echo "$VAST_PATH"lib/formater_out_wfk "$1"
"$VAST_PATH"lib/formater_out_wfk "$1" > "$VAST_PATH"saved_period_search_lightcurves/"$NEWFILENAME" #lightcurve$$.tmp
if [ $? -ne 0 ];then
 echo "ERROR: lib/formater_out_wfk $1 returned a non-zero exit status"
 exit 1
else
 echo "Pre-processing exist code is 0 (seems fine)"
fi

# And save the file
echo "# "
echo "# Saving lightcurve file to "$VAST_PATH"saved_period_search_lightcurves/"$NEWFILENAME" for possible future use..."
echo "# "
echo "# "

if [ ! -s "$VAST_PATH"saved_period_search_lightcurves/"$NEWFILENAME" ];then
 echo "ERROR: the pre-processed lightcurve file is empty"
 echo "$VAST_PATH"saved_period_search_lightcurves/"$NEWFILENAME"
 exit 1
fi

# Determine good period search range
JD_MIN=`sort -n "$VAST_PATH"saved_period_search_lightcurves/$NEWFILENAME |head -n1 | awk '{print $1}'`
if [ -z "$JD_MIN" ];then
 echo "ERROR: cannot determine JD_MIN"
 exit 1
fi
JD_MAX=`sort -n "$VAST_PATH"saved_period_search_lightcurves/$NEWFILENAME |tail -n1 | awk '{print $1}'`
if [ -z "$JD_MAX" ];then
 echo "ERROR: cannot determine JD_MAX"
 exit 1
fi

echo "# JD range: $JD_MIN -- $JD_MAX"

PMAX=`echo "
define i(x) {
    auto s
    s = scale
    scale = 0
    x /= 1   /* round x down */
    scale = s
    return (x)
}
define abs(i) {
 if (i < 0) return (-i)
 return (i)
}
define min(a, b) {
 if (a < b) {
  return (a);
 }
 return (b);
}
jd_range=abs(($JD_MAX)-($JD_MIN))
define max_period(jd_range) {
 max_period_frcation_of_jd_range = i(jd_range/5.0-0.5)
 max_period_hardcoded = 100
 max_period_suggested = min( max_period_frcation_of_jd_range , max_period_hardcoded )
 if( max_period_suggested < 1.0 ) return ( 1.0 )
 return ( max_period_suggested )
}
max_period(jd_range)
"|bc -ql`
# The above does not work on Mac

# if this didn't work
if [ -z "$PMAX" ];then
 PMAX=100
fi

# That's funny, what's so special about 0.3 ???
if [ "$PMAX" = ".3" ];then
 PMIN=0.03
else
 PMIN=0.1
fi

# Set time system
TIMESYSTEM="UTC"
if [ -s "$VAST_PATH"vast_summary.log ];then
 grep "JD time system" "$VAST_PATH"vast_summary.log &>/dev/null
 if [ $? -ne 0 ];then
  TIMESYSTEM=`cat "$VAST_PATH"vast_summary.log | grep "JD time system" |awk '{print $5}'`
 fi
fi

echo "# PMAX = $PMAX d   PMIN = $PMIN d"

echo "# Uploading the lightcurve to $PERIOD_SEARCH_SERVER"

# Upload the converted lightcurve file to the server
$CURL -F file=@$VAST_PATH"saved_period_search_lightcurves/$NEWFILENAME" -F submit="Compute" -F pmax=$PMAX -F pmin=$PMIN -F phaseshift=0.1 -F fileupload="True" -F applyhelcor="No" -F timesys="$TIMESYSTEM" -F position="00:00:00.00 +00:00:00.0" "http://$PERIOD_SEARCH_SERVER/cgi-bin/lk/process_lightcurve.py" --user vast48:khyzbaojMhztNkWd > server_reply$$.html
if [ $? -ne 0 ];then
 echo "WARNING: curl returned a non-zero exit status - something is wrong!"
else
 echo "# OK, got the server reply..."
fi

if [ ! -f server_reply$$.html ];then
 echo "ERROR in $0: no server reply file server_reply$$.html"
 exit 1
fi

if [ ! -s server_reply$$.html ];then
 echo "ERROR in $0: empty server reply file server_reply$$.html"
 exit 1
fi

### DEBUG
#cat server_reply$$.html

# Parse the server reply
RESULTURL=`grep "The output will be written to" server_reply$$.html | awk -F"<a" '{print $2}' |awk -F">" '{print $1}' | head -n 1`
RESULTURL=${RESULTURL//\"/ }
RESULTURL=`echo $RESULTURL | awk '{print $2}'`

if [ -z "$RESULTURL" ];then
 echo "ERROR in $0: cannot find the results URL
Here is the full server reply:

################################"
 cat server_reply$$.html
 echo "################################
The period search script $0 is terminated."
 rm -f server_reply$$.html
 exit 1
fi

# Remove temporary files
rm -f server_reply$$.html

# Start web browser to view the results
"$VAST_PATH"lib/start_web_browser.sh "$RESULTURL"
if [ $? -ne 0 ];then
 echo "ERROR in the script ${VAST_PATH}lib/start_web_browser.sh $RESULTURL"
fi
