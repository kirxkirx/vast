#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

#curl --connect-timeout 10 --retry 1 --silent http://www.cbat.eps.harvard.edu/unconf/tocp.html | grep -e 'PNV J' -e 'TCP J' -e 'PSN J' | awk -F'>' '{print $2" "$3}' | sed -e 's/<\/a//g' -e 's/*//g' -e 's/2015 11 16 8167/2015 11 16.8167/g' -e 's/04 17 54 27/04 17 54.27/g' -e 's/01 34 21.40 +30 23 26.6./01 34 21.40 +30 23 26.6 /g' -e 's/14 51 37 83 +40 35 51 4  17 0 U/14 51 37.83 +40 35 51.4  17.0 U/g' | awk '{print $6":"$7":"$8" "$9":"$10":"$11"  "$1" "$2"  "$3"-"$4"-"$5"  "$12"mag"}' | uniq
CURL_OUTPUT=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --silent --show-error http://www.cbat.eps.harvard.edu/unconf/tocp.html)
if [ $? -ne 0 ];then
 exit 1
elif [ -z "$CURL_OUTPUT" ];then
 exit 1
fi
# We want to exclude TCP J19500635-0736530, TCP J23294753+6218124, TCP J05493243+4636023 which are Mira variables posted to TOCP (so it may regularly appear in the candidates list)
# TCP J19395702+1018248 - not a real object
echo "$CURL_OUTPUT" | grep -e 'PNV J' -e 'TCP J' -e 'PSN J' | grep -v -e 'TCP J19500635-0736530' -e 'TCP J23294753+6218124' -e 'TCP J05493243+4636023' -e 'TCP J19395702+1018248' | awk -F'>' '{print $2" "$3}' | sed -e 's/<\/a//g' -e 's/*//g' -e 's/2015 11 16 8167/2015 11 16.8167/g' -e 's/04 17 54 27/04 17 54.27/g' -e 's/01 34 21.40 +30 23 26.6./01 34 21.40 +30 23 26.6 /g' -e 's/14 51 37 83 +40 35 51 4  17 0 U/14 51 37.83 +40 35 51.4  17.0 U/g' | awk '{print $6":"$7":"$8" "$9":"$10":"$11"  "$1" "$2"  "$3"-"$4"-"$5"  "$12"mag"}' | uniq

