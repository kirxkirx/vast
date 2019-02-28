#!/usr/bin/env bash                                                                                                                                   
#################################
# This script will try to find a web browser and open a page in it.
#################################
# You may set a browser manually by uncommenting and changing the line below.
#WEBBROWSER=firefox
#################################
# You probably don't need to change anything below this line.
#################################
URL_TO_OPEN=$1
#################################
# Find a web browser
if [ -z "$WEBBROWSER" ];then
 WEBBROWSER="none"
 if [ ! -z "$BROWSER" ];then
  WEBBROWSER="$BROWSER"
 else
  if command -v firefox &>/dev/null ;then
   WEBBROWSER="firefox"
  elif command -v firefox-bin &>/dev/null ;then
   WEBBROWSER="firefox-bin"
  elif command -v chromium &>/dev/null ;then
   WEBBROWSER="chromium"
  elif command -v google-chrome-stable &>/dev/null ;then
   WEBBROWSER="google-chrome-stable"
  elif command -v google-chrome-unstable &>/dev/null ;then
   WEBBROWSER="google-chrome-unstable"
  elif command -v google-chrome-beta &>/dev/null ;then
   WEBBROWSER="google-chrome-beta"
  elif command -v google-chrome &>/dev/null ;then
   WEBBROWSER="google-chrome"
  elif command -v chrome &>/dev/null ;then
   WEBBROWSER="chrome"
  elif command -v midori &>/dev/null ;then
   WEBBROWSER="midori"
  elif command -v torbrowser &>/dev/null ;then
   WEBBROWSER="torbrowser"
  elif command -v sensible-browser &>/dev/null ;then
   WEBBROWSER="sensible-browser"
  elif command -v x-www-browser &>/dev/null ;then
   WEBBROWSER="x-www-browser"
  elif command -v gnome-www-browser &>/dev/null ;then
   WEBBROWSER="gnome-www-browser"
  elif command -v xdg-open &>/dev/null ;then
   WEBBROWSER="xdg-open"
  elif command -v gnome-open &>/dev/null ;then
   WEBBROWSER="gnome-open"
  elif command -v /Applications/Firefox.app/Contents/MacOS/firefox &>/dev/null ;then
   WEBBROWSER="/Applications/Firefox.app/Contents/MacOS/firefox"
  elif command -v "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" &>/dev/null ;then
   WEBBROWSER="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  elif command -v /Applications/Safari.app/Contents/MacOS/safari &>/dev/null ;then
   WEBBROWSER="/Applications/Safari.app/Contents/MacOS/safari"
  elif command -v open &>/dev/null ;then
   WEBBROWSER="open"
  elif command -v w3m &>/dev/null ;then
   WEBBROWSER="w3m"
  elif command -v links &>/dev/null ;then
   WEBBROWSER="links"
  elif command -v lynx &>/dev/null ;then
   WEBBROWSER="lynx"
  elif command -v curl &>/dev/null ;then
   WEBBROWSER="curl"
  fi
 fi # if [ ! -z "$BROWSER" ];then
 if [ "$WEBBROWSER" = "none" ];then
  echo "ERROR cannot find a known webbrowser in $PATH"
  echo "Please edit the script $0 to specify a browser manually!"
  exit 1
 fi
fi
#################################

#################################
# Start web browser
echo "# Starting $WEBBROWSER web browser..."
echo "$WEBBROWSER $URL_TO_OPEN"
if [ "$WEBBROWSER" != "curl" ];then
 "$WEBBROWSER" "$URL_TO_OPEN" &>/dev/null &
else
 "$WEBBROWSER" "$URL_TO_OPEN"
fi

