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
# Check if lightcurve file was ($1) exist
if [ ! -f "$1" ];then
 echo "ERROR: lightcurve file $1 does not exist!"
 echo " "
 echo "Usage:  $0 outNNNN.dat"
 exit
fi
#################################
## Find a web browser
#if [ -z "$WEBBROWSER" ];then
# WEBBROWSER="none"
# if command -v firefox &>/dev/null ;then
#  WEBBROWSER="firefox"
# elif command -v firefox-bin &>/dev/null ;then
#  WEBBROWSER="firefox-bin"
# elif command -v chromium &>/dev/null ;then
#  WEBBROWSER="chromium"
# elif command -v midori &>/dev/null ;then
#  WEBBROWSER="midori"
# fi
# if [ "$WEBBROWSER" = "none" ];then
#  echo "ERROR cannot find a known webbrowser in $PATH"
#  echo "Please edit the script $0 to specify a browser manually!"
#  exit 1
# fi
#fi
#################################
#VAST_PATH=`readlink -f $0`
#VAST_PATH=`dirname "$VAST_PATH"`
if [ -z "$VAST_PATH" ];then
 VAST_PATH=`readlink -f $0`
 VAST_PATH=`dirname "$VAST_PATH"`
 VAST_PATH="${VAST_PATH/'util/'/}"
 VAST_PATH="${VAST_PATH/'lib/'/}"
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH//'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
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
CURL="$CURL -H 'Expect:'"
###################################################
echo -n "Checking if we can reach any period search servers... "
# Decide on which period search server to use
# first - set the initial list of servers
#PERIOD_SEARCH_SERVERS="scan.sai.msu.ru polaris.kirx.net vast.sai.msu.ru"
# polaris.kirx.net is actually pretty slow...
# vast.sai.msu.ru disabled until the software is updated there
PERIOD_SEARCH_SERVERS="scan.sai.msu.ru"
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
PERIOD_SEARCH_SERVER=`$("$VAST_PATH"lib/find_timeout_command.sh) 10 sort --random-sort --random-source=/dev/urandom servers.ping_ok | sort -R | head -n1`
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
   
if [ "$PERIOD_SEARCH_SERVER" = "" ];then
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
"$VAST_PATH"lib/formater_out_wfk "$1" > "$VAST_PATH"saved_period_search_lightcurves/"$NEWFILENAME" #lightcurve$$.tmp

# And save the file
echo "# "
echo "# Saving lightcurve file to "$VAST_PATH"saved_period_search_lightcurves/"$NEWFILENAME" for possible future use..."
echo "# "
echo "# "

# Determine good period search range
JD_MIN=`sort -n "$VAST_PATH"saved_period_search_lightcurves/$NEWFILENAME |head -n1 | awk '{print $1}'`
JD_MAX=`sort -n "$VAST_PATH"saved_period_search_lightcurves/$NEWFILENAME |tail -n1 | awk '{print $1}'`

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

### DEBUG
#cat server_reply$$.html

# Parse the server reply
RESULTURL=`grep "The output will be written to" server_reply$$.html |awk -F"<a" '{print $2}' |awk -F">" '{print $1}'`
RESULTURL=${RESULTURL//\"/ }
RESULTURL=`echo $RESULTURL | awk '{print $2}'`

# Remove temporary files
#rm -f lightcurve$$.tmp
rm -f server_reply$$.html

# Start web browser
#echo "# Starting $WEBBROWSER web browser..."
#echo "$WEBBROWSER $RESULTURL"
#if [ "$WEBBROWSER" != "curl" ];then
# $WEBBROWSER $RESULTURL &>/dev/null &
#else
# $WEBBROWSER $RESULTURL
#fi
"$VAST_PATH"lib/start_web_browser.sh $RESULTURL

