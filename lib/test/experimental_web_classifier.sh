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
# Find a web browser
WEBBROWSER="none"
if command -v firefox &>/dev/null ;then
 WEBBROWSER="firefox"
elif command -v firefox-bin &>/dev/null ;then
 WEBBROWSER="firefox-bin"
elif command -v chromium &>/dev/null ;then
 WEBBROWSER="chromium"
elif command -v midori &>/dev/null ;then
 WEBBROWSER="midori"
fi
if [ "$WEBBROWSER" = "none" ];then
 echo "ERROR cannot find a known webbrowser in $PATH"
 echo "Please edit the script $0 to specify a browser manually!"
 exit 1
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
#################################
# Do the actual work

#RESULTURL=`$CURL -F file=@$1 -F submit="Classify" http://scan.sai.msu.ru/cgi-bin/wwwupsilon/process_lightcurve.py | grep Refresh | grep "url=" | awk '{print $2}' FS='url=' | awk '{print $1}' FS='"'`
RESULTURL=`$CURL -F file=@$1 -F submit="Classify" http://scan.sai.msu.ru/cgi-bin/wwwupsilon/process_lightcurve.py | grep Refresh | grep "url=" | awk -F 'url=' '{print $2}' | awk -F '"' '{print $1}'`

# Start web browser
echo "# Starting $WEBBROWSER web browser..."
echo "$WEBBROWSER $RESULTURL"
$WEBBROWSER $RESULTURL &>/dev/null &
