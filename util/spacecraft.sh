#!/usr/bin/env bash

# This script will query JPL HORIZONS for position of
# a few selected (bright and distant) planetary moons.

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ -z "$MPC_CODE" ];then
 # Default MPC code is 500 - geocenter
 MPC_CODE=500
fi
if [[ "$MPC_CODE" != *@* ]]; then
 MPC_CODE="${MPC_CODE}@399"
fi

isFloat() {
    local num
    num=$(echo "$1" | awk '{$1=$1};1')  # remove leading/trailing white space
    if [[ $num =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
        return 0  # is a float (or an integer), return true (0)
    else
        return 1  # is not a float, return false (1)
    fi
}

JD="$1"

if [ -z "$JD" ];then
 echo "Usage: $0 JD(UT)"
 exit 1
fi

isFloat "$JD"
if [ $? -ne 0 ];then
 echo "ERROR in $0: the input JD #$JD# does not look like a floating point number"
 exit 1
fi

min=2400000.0
max=2500000.0
value=$JD

awk -v val="$value" -v min="$min" -v max="$max" 'BEGIN {if (val>=min && val<=max) exit 0; else exit 1}'
if [ $? -ne 0 ];then
 echo "ERROR in $0: the input JD #$JD# is out of the expected range between $min and $max"
 exit 1
fi



for SPACECRAFT_NAME in JWST Chandra XMM-Newton ;do
 # Match the planet name to its SPACECRAFT_ID
 case "$SPACECRAFT_NAME" in
  # Jupiter
  "JWST") SPACECRAFT_ID="-170" ;;
  "Chandra") SPACECRAFT_ID="-151" ;;
  "XMM-Newton") SPACECRAFT_ID="-125989" ;;
  *) echo "Invalid spacecraft name" ; exit 1 ;;
 esac
 # As far as I can tell, JD is in UT time system
 #SPACECRAFT_RA_DEC_MAG_STRING=$(curl --connect-timeout 10 --retry 1 --insecure --silent --show-error "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$SPACECRAFT_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'" | grep -A1 '$$SOE' | tail -n1 | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
 SPACECRAFT_RA_DEC_MAG_STRING=$(curl --connect-timeout 10 --retry 1 --insecure --silent --show-error "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$SPACECRAFT_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -A1 '$$SOE' | tail -n1 | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
 if [ -z "$SPACECRAFT_RA_DEC_MAG_STRING" ];then
  # something is wrong - let's try to reconnect via the reverse proxy
  #SPACECRAFT_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --insecure --silent --show-error "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$SPACECRAFT_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'" | grep -A1 '$$SOE' | tail -n1 | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
  SPACECRAFT_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --insecure --silent --show-error "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$SPACECRAFT_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -A1 '$$SOE' | tail -n1 | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
  if [ -z "$SPACECRAFT_RA_DEC_MAG_STRING" ];then
   # last dirch effort - try to reconnect via HTTP reverse proxy
   #SPACECRAFT_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --insecure --silent --show-error "http://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$SPACECRAFT_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'" | grep -A1 '$$SOE' | tail -n1 | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
   SPACECRAFT_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --insecure --silent --show-error "http://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$SPACECRAFT_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -A1 '$$SOE' | tail -n1 | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
  fi
 fi
 # print results only if communication with Horizons worked
 if [ -n "$SPACECRAFT_RA_DEC_MAG_STRING" ];then
  #echo "$SPACECRAFT_RA_DEC_MAG_STRING $SPACECRAFT_NAME" | awk '{print $1" "$2" "$4" ("$3")"}'
  echo "$SPACECRAFT_RA_DEC_MAG_STRING $SPACECRAFT_NAME" | awk '{print $1" "$2" "$4}'
 fi
done

