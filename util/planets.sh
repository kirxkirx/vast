#!/usr/bin/env bash

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



for PLANET_NAME in Mercury Venus Mars Jupiter Saturn Uranus Neptune Pluto Moon ;do
 # Match the planet name to its PLANET_ID
 case "$PLANET_NAME" in
  "Mercury") PLANET_ID="199" ;;
  "Venus") PLANET_ID="299" ;;
  "Earth") PLANET_ID="399" ;;
  "Mars") PLANET_ID="499" ;;
  "Jupiter") PLANET_ID="599" ;;
  "Saturn") PLANET_ID="699" ;;
  "Uranus") PLANET_ID="799" ;;
  "Neptune") PLANET_ID="899" ;;
  "Pluto") PLANET_ID="999" ;;
  "Moon") PLANET_ID="301" ;;
  *) echo "Invalid planet name" ; exit 1 ;;
 esac
 # As far as I can tell, JD is in UT time system
 PLANET_RA_DEC_MAG_STRING=$(curl --insecure --silent "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$PLANET_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'" | grep -A1 '$$SOE' | tail -n1 | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
 if [ -z "$PLANET_RA_DEC_MAG_STRING" ];then
  # something is wrong - let's try to reconnect via the reverse proxy
  PLANET_RA_DEC_MAG_STRING=$(curl --insecure --silent "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PLANET_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'" | grep -A1 '$$SOE' | tail -n1 | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
 fi
 echo "$PLANET_RA_DEC_MAG_STRING $PLANET_NAME" | awk '{print $1" "$2" "$4" ("$3")"}'
done

