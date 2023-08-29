#!/bin/bash

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


DATA=$(curl --silent http://astro.vanbuitenen.nl/comets)

LIST_OF_COMET_FULL_NAMES=$(echo "$DATA" | grep '</tr>' | grep -e 'C/' -e 'P/' -e 'I/' | sed 's:</tr>:\n:g' | awk -F'>' '{print $3}' | awk -F'<' '{print $1}')
#echo "$LIST_OF_COMET_FULL_NAMES"

# interstellar objects are not implemented yet

# periodic comets have multiple records in JPL HORIZONS
PERIODIC_COMETS=$(echo "$LIST_OF_COMET_FULL_NAMES" | grep 'P/')
echo "$PERIODIC_COMETS" | while read PERIODIC_COMET_DESIGNATION_AND_NAME ;do
 PERIODIC_COMET_DESIGNATION=$(echo "$PERIODIC_COMET_DESIGNATION_AND_NAME" | awk -F'/' '{print $1}')
 HORIZONS_REPLY=$(curl --silent --insecure "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_DESIGNATION'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'")
 # Check if the reply contains ephemerides or the list of records
 echo "$HORIZONS_REPLY" | grep --quiet '$$SOE'
 if [ $? -ne 0 ];then
  # assume this is a list of horizons records, not the ephemerides table
  PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER=$(echo "$HORIZONS_REPLY" | grep "$PERIODIC_COMET_DESIGNATION" | grep -v 'DES' | tail -n1 | awk '{print $1}')
  if [ -z "$PLANET_RA_DEC_MAG_STRING" ];then
   # something is wrong - let's try to reconnect via the reverse proxy
   PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER=$(curl --silent --insecure "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_DESIGNATION'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'" | grep "$PERIODIC_COMET_DESIGNATION" | grep -v 'DES' | tail -n1 | awk '{print $1}')
  fi
  if [ -z "$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER" ];then
   echo "ERROR getting JPL HORIZONS designation for periodic comet $PERIODIC_COMET_DESIGNATION_AND_NAME"
   continue
  fi
  HORIZONS_REPLY=$(curl --insecure --silent "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'")
 fi
 PLANET_RA_DEC_MAG_STRING=$(echo "$HORIZONS_REPLY" | grep -A1 '$$SOE' | tail -n1 | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
 if [ -z "$PLANET_RA_DEC_MAG_STRING" ];then
  # something is wrong - let's try to reconnect via the reverse proxy
  PLANET_RA_DEC_MAG_STRING=$(curl --insecure --silent "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'" | grep -A1 '$$SOE' | tail -n1 | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
 fi
 if [ -n "$PLANET_RA_DEC_MAG_STRING" ];then
  echo "$PLANET_RA_DEC_MAG_STRING $PERIODIC_COMET_DESIGNATION_AND_NAME"
 fi
 
done

# !!!!!!
#exit 0

# non-periodic comets
NON_PERIODIC_COMETS=$(echo "$LIST_OF_COMET_FULL_NAMES" | grep 'C/')
echo "$NON_PERIODIC_COMETS" | while read NON_PERIODIC_COMET_DESIGNATION_AND_NAME ;do
 NON_PERIODIC_COMET_DESIGNATION_URLENCODE=$(echo "$NON_PERIODIC_COMET_DESIGNATION_AND_NAME" | awk '{print $1"%20"$2}')
 PLANET_RA_DEC_MAG_STRING=$(curl --insecure --silent "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$NON_PERIODIC_COMET_DESIGNATION_URLENCODE'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'" | grep -A1 '$$SOE' | tail -n1 | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
 if [ -z "$PLANET_RA_DEC_MAG_STRING" ];then
  # something is wrong - let's try to reconnect via the reverse proxy
  PLANET_RA_DEC_MAG_STRING=$(curl --insecure --silent "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$NON_PERIODIC_COMET_DESIGNATION_URLENCODE'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'" | grep -A1 '$$SOE' | tail -n1 | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
 fi
 echo "$PLANET_RA_DEC_MAG_STRING $NON_PERIODIC_COMET_DESIGNATION_AND_NAME"
done


