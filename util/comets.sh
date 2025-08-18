#!/usr/bin/env bash

CONNECTION_TIMEOUT_SEC=5

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

#if [ -z "$COMET_SH_LOCAL_OR_REMOTE" ] || [ "$COMET_SH_LOCAL_OR_REMOTE" != "remote" ];then
# # Run the comet search locally
# command -v python3 &>/dev/null && \
# python3 -c "import skyfield; print(skyfield.__version__)" &>/dev/null && \
# python3 -c "import numpy; print(numpy.__version__)" &>/dev/null && \
# python3 -c "import pandas; print(pandas.__version__)" &>/dev/null && \
# if [ -n "$MPC_CODE" ] && grep --quiet "$MPC_CODE " ObsCodes.html ;then
#  COMET_FINDER_OBSERVATORY_CODE_ARGUMENT="-observatory $MPC_CODE"
# else
#  COMET_FINDER_OBSERVATORY_CODE_ARGUMENT=""
# fi
# python3 util/comet_finder/main.py calc -qd $JD $COMET_FINDER_OBSERVATORY_CODE_ARGUMENT
# if [ $? -eq 0 ]; then
#   echo "Positions of bright comets computed with util/comet_finder/main.py for JD(UT)$JD $COMET_FINDER_OBSERVATORY_CODE_ARGUMENT" > comets_header.txt
#   cat comets_header.txt >&2
#   exit 0
# fi
#fi
#
#if [ -n "$COMET_SH_LOCAL_OR_REMOTE" ] && [ "$COMET_SH_LOCAL_OR_REMOTE" = "local" ];then
# echo "Local comet search failed!"
# exit 1
#fi

# Run comet search locally unless explicitly set to "remote"
if [ "$COMET_SH_LOCAL_OR_REMOTE" != "remote" ]; then
 if command -v python3 &>/dev/null && \
  python3 -c "import skyfield" &>/dev/null && \
  python3 -c "import numpy" &>/dev/null && \
  python3 -c "import pandas" &>/dev/null; then

  if [ -n "$MPC_CODE" ] && grep -q "$MPC_CODE " ObsCodes.html; then
   COMET_FINDER_OBSERVATORY_CODE_ARGUMENT="-observatory $MPC_CODE"
  else
   COMET_FINDER_OBSERVATORY_CODE_ARGUMENT=""
  fi

  python3 util/comet_finder/main.py calc -qd "$JD" $COMET_FINDER_OBSERVATORY_CODE_ARGUMENT
  if [ $? -eq 0 ]; then
   echo "Positions of bright comets computed with util/comet_finder/main.py for JD(UT)$JD $COMET_FINDER_OBSERVATORY_CODE_ARGUMENT" > comets_header.txt
   cat comets_header.txt >&2
   exit 0
  fi
 fi
fi

# Explicitly fail if local comet search was required but unsuccessful
if [ "$COMET_SH_LOCAL_OR_REMOTE" = "local" ]; then
 echo "Local comet search failed!"
 exit 1
fi

echo "Positions of bright comets (listed at http://astro.vanbuitenen.nl/comets and http://aerith.net/comet/weekly/current.html ) from JPL HORIZONS for JD(UT)$JD at $MPC_CODE" > comets_header.txt
cat comets_header.txt >&2

# Get a list of comets from Gideon van Buitenen's page
DATA=$(curl $VAST_CURL_PROXY --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 1 --silent --show-error --insecure 'https://astro.vanbuitenen.nl/comets')
LIST_OF_COMET_FULL_NAMES_vanBuitenen=$(echo "$DATA" | grep '</tr>' | grep -e 'C/' -e 'P/' -e 'I/' | sed 's:</tr>:\n:g' | awk -F'>' '{print $3}' | awk -F'<' '{print $1}')

#echo "##### van Buitenen #####
#$LIST_OF_COMET_FULL_NAMES_vanBuitenen"


# Get a list of comets from Seiichi Yoshida's page
LIST_OF_COMET_FULL_NAMES_Yoshida=$(curl $VAST_CURL_PROXY --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 1 --silent --show-error http://aerith.net/comet/weekly/current.html | grep 'A HREF' | awk -F'>' '{print $2}' | awk -F '<' '{print $1}' | grep '/' | sed 's/(\s*/(/g; s/\s*)/)/g' | sed 's/[[:space:]]*$//' ) 

#echo "##### Yoshida #####
#$LIST_OF_COMET_FULL_NAMES_Yoshida"


# Combine the two lists (and fix a problematic comet name)
LIST_OF_COMET_FULL_NAMES_from_vanBuitenen_and_Yoshida=$(echo "$LIST_OF_COMET_FULL_NAMES_vanBuitenen
$LIST_OF_COMET_FULL_NAMES_Yoshida" | sort | uniq | sed 's/323P-C\/SOHO/323P/g')
# The names may have different capitalizations in van Buitenen's and sYoshida's page - we'll keep only one version
LIST_OF_COMET_FULL_NAMES="$(echo "$LIST_OF_COMET_FULL_NAMES_from_vanBuitenen_and_Yoshida" | while read NAME1 NAME2 REST ;do echo "$LIST_OF_COMET_FULL_NAMES_from_vanBuitenen_and_Yoshida" | grep -m 1 "$NAME1 $NAME2" && continue ; echo "$LIST_OF_COMET_FULL_NAMES_from_vanBuitenen_and_Yoshida" | grep -m 1 "$NAME1" ;done | sort | uniq)"

#echo "##### Combined #####
#$LIST_OF_COMET_FULL_NAMES"


# If the list is empty - something is wrong so we stop
if [ -z "$LIST_OF_COMET_FULL_NAMES" ];then
 echo "ERROR in $0 getting a list of bright comets"
 exit 1
fi

# Check if MPC_CODE contains '@' as needed for JPL HORIZONS
if [[ "$MPC_CODE" != *@* ]]; then
 MPC_CODE="${MPC_CODE}@399"
fi

SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER=0

# Interstellar objects are not implemented yet!
# Below we treat the periodic and regular comets separately as the periodic comets often have many orbits in HORIZONS system

# periodic comets have multiple records in JPL HORIZONS
PERIODIC_COMETS=$(echo "$LIST_OF_COMET_FULL_NAMES" | grep 'P/')
echo "$PERIODIC_COMETS" | while read PERIODIC_COMET_DESIGNATION_AND_NAME ;do
 # newly discovered periodic comets may be named as P/2023 M4 (ATLAS)
 # normally, the periodic comets are named like 103P/Hartley 2
 #PERIODIC_COMET_DESIGNATION=$(echo "$PERIODIC_COMET_DESIGNATION_AND_NAME" | awk -F'/' '{print $1}')
 
 if [[ $PERIODIC_COMET_DESIGNATION_AND_NAME == P* ]]; then
  # newly discovered periodic comets may be named as P/2023 M4 (ATLAS) and we want just the P/2023 M4 part and need to urlencode the white space
  PERIODIC_COMET_DESIGNATION=$(echo "$PERIODIC_COMET_DESIGNATION_AND_NAME" | awk '{print $1" "$2}' | sed 's/ /%20/g')
 else
  # normally, the periodic comets are named like 103P/Hartley 2 and we want just the 103P part
  PERIODIC_COMET_DESIGNATION=$(echo "$PERIODIC_COMET_DESIGNATION_AND_NAME" | awk -F'/' '{print $1}')
 fi
 
 HORIZONS_REPLY=$(curl $VAST_CURL_PROXY --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 1 --silent --show-error --insecure "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_DESIGNATION'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'")
 if [ -n "$HORIZONS_REPLY" ];then
  SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER=$((SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER + 1))
 fi
 # Check if the reply contains ephemerides or the list of records
 echo "$HORIZONS_REPLY" | grep --quiet '$$EOE'
 if [ $? -ne 0 ];then
  # Manually set designations for some comets with particularly annoying horizons output
  if [ "$PERIODIC_COMET_DESIGNATION" = "103P" ];then
   PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER="90000950"
  elif [ "$PERIODIC_COMET_DESIGNATION" = "471P" ];then
   PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER="90004055"
  elif [ "$PERIODIC_COMET_DESIGNATION" = "487P" ];then
   PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER="90004169"
  elif [ "$PERIODIC_COMET_DESIGNATION" = "492P" ];then
   PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER="90004084"
  else
   # If this is not some special comet
   # assume this is a list of horizons records, not the ephemerides table
   PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER=$(echo "$HORIZONS_REPLY" | grep "$PERIODIC_COMET_DESIGNATION" | grep -v 'DES' | tail -n1 | awk '{print $1}')
   #if [ -z "$COMET_RA_DEC_MAG_STRING" ];then
   if [ -z "$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER" ];then
    # something is wrong - let's try to reconnect via the reverse proxy
    # this will be slow if connection with reverse proxy is fine, but there is no reply from upstream
    #PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER=$(curl $VAST_CURL_PROXY --max-time 30 --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 0 --silent --show-error --insecure "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_DESIGNATION'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep "$PERIODIC_COMET_DESIGNATION" | grep -v 'DES' | tail -n1 | awk '{print $1}')
    PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER=$(curl $VAST_CURL_PROXY --max-time 30 --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 0 --silent --show-error --insecure "http://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_DESIGNATION'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep "$PERIODIC_COMET_DESIGNATION" | grep -v 'DES' | tail -n1 | awk '{print $1}')
    # last attempt
    #sleep $[$RANDOM % 9]
    sleep $((RANDOM % 10 + 1))
    if [ -z "$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER" ];then
     #PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --silent --insecure "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_DESIGNATION'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep "$PERIODIC_COMET_DESIGNATION" | grep -v 'DES' | tail -n1 | awk '{print $1}')
     # Retry with the main horizons site, not the proxy
     PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER=$(curl $VAST_CURL_PROXY --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 0 --silent --show-error --insecure "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_DESIGNATION'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep "$PERIODIC_COMET_DESIGNATION" | grep -v 'DES' | tail -n1 | awk '{print $1}')
    else
     SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER=$((SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER + 1))
    fi
   else
    SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER=$((SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER + 1))
   fi
   if [ -z "$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER" ];then
    echo "00:00:00.00 +00:00:00.0 cannot get JPL HORIZONS designation for periodic comet $PERIODIC_COMET_DESIGNATION_AND_NAME  -- you may manually insert its ID in $0"
    #
    if [ $SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER -eq 0 ];then
     echo "Problem connecting to HORIZONS by $0" >&2
     # Looks like it wil exist only the while loop, not the whole script
     exit 1
    fi
    #
    continue
   fi
  fi
  #HORIZONS_REPLY=$(curl --connect-timeout 10 --retry 1 --insecure --silent "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'")
  HORIZONS_REPLY=$(curl $VAST_CURL_PROXY --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 1 --insecure --silent --show-error "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'")
  if [ -n "$HORIZONS_REPLY" ];then
   SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER=$((SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER + 1))
  fi
 fi
 
 
# echo curl --silent --insecure "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_DESIGNATION'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'"
# echo "
#xxxxxxxxxxxxxxxxxx
#$HORIZONS_REPLY
#xxxxxxxxxxxxxxxxxx
#$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER
#xxxxxxxxxxxxxxxxxx"


 # Make sure to print empty string if $3, $4, $5, $6, $7, $8 are undefined
 # sed 's/ [*CNAmrets] /   /g' is to remove Moon Sun presence markers and the likes - they may appear if MPC_CODE is set
 #COMET_RA_DEC_MAG_STRING=$(echo "$HORIZONS_REPLY" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
 COMET_RA_DEC_MAG_STRING=$(echo "$HORIZONS_REPLY" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %s:%02d:%04.1f %4.1fmag\n",$3,$4,$5,$6,$7,$8,$9}')
 if [ -z "$COMET_RA_DEC_MAG_STRING" ];then
  # Something is wrong - let's try to reconnect via the reverse proxy
  # Make sure to print empty string if $3, $4, $5, $6, $7, $8 are undefined
  #COMET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --max-time 30 --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 0 --insecure --silent --show-error "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
  #COMET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --max-time 30 --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 0 --insecure --silent --show-error "http://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
  COMET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --max-time 30 --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 0 --insecure --silent --show-error "http://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %s:%02d:%04.1f %4.1fmag\n",$3,$4,$5,$6,$7,$8,$9}')
 fi
 if [ -n "$COMET_RA_DEC_MAG_STRING" ];then
  # Verify the format of $PLANET_RA_DEC_MAG_STRING - lib/hms2deg will return non-zero exit code if something is wrong with the coordinates
  if lib/hms2deg $COMET_RA_DEC_MAG_STRING &> /dev/null ;then
   echo "$COMET_RA_DEC_MAG_STRING $PERIODIC_COMET_DESIGNATION_AND_NAME"
  else
   echo "00:00:00.00 +00:00:00.0 cannot parse JPL HORIZONS ephemerides #$COMET_RA_DEC_MAG_STRING# for periodic comet $PERIODIC_COMET_DESIGNATION_AND_NAME"
  fi
 else
  echo "00:00:00.00 +00:00:00.0 cannot get JPL HORIZONS ephemerides for periodic comet $PERIODIC_COMET_DESIGNATION_AND_NAME"
#  echo curl --insecure --silent "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$PERIODIC_COMET_JPLHORIZONS_LATEST_RECORD_NUMBER'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='500@399'&TLIST='$JD'&QUANTITIES='1,9'"
#  echo "-----------------------
#$HORIZONS_REPLY
#-----------------------"
  continue
 fi 
done

# Non-periodic comets
NON_PERIODIC_COMETS=$(echo "$LIST_OF_COMET_FULL_NAMES" | grep 'C/')
echo "$NON_PERIODIC_COMETS" | while read NON_PERIODIC_COMET_DESIGNATION_AND_NAME ;do
 NON_PERIODIC_COMET_DESIGNATION_URLENCODE=$(echo "$NON_PERIODIC_COMET_DESIGNATION_AND_NAME" | awk '{print $1"%20"$2}')
 # Make sure to print empty string if $3, $4, $5, $6, $7, $8 are undefined
 #COMET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 1 --insecure --silent --show-error "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$NON_PERIODIC_COMET_DESIGNATION_URLENCODE'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
 COMET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 1 --insecure --silent --show-error "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$NON_PERIODIC_COMET_DESIGNATION_URLENCODE'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %s:%02d:%04.1f %4.1fmag\n",$3,$4,$5,$6,$7,$8,$9}')
 if [ -z "$COMET_RA_DEC_MAG_STRING" ];then
  # Normally this isn't happening
  # Something is wrong - let's try to reconnect via the reverse proxy
  # Make sure to print empty string if $3, $4, $5, $6, $7, $8 are undefined
  #COMET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --max-time 30 --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 0 --insecure --silent --show-error "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$NON_PERIODIC_COMET_DESIGNATION_URLENCODE'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
  #COMET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --max-time 30 --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 0 --insecure --silent --show-error "http://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$NON_PERIODIC_COMET_DESIGNATION_URLENCODE'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
  COMET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --max-time 30 --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 0 --insecure --silent --show-error "http://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$NON_PERIODIC_COMET_DESIGNATION_URLENCODE'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %s:%02d:%04.1f %4.1fmag\n",$3,$4,$5,$6,$7,$8,$9}')
 else
  SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER=$((SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER + 1))
 fi
 if [ -z "$COMET_RA_DEC_MAG_STRING" ];then
  # Normally this isn't happening
  # Sleep and retry!
  # Generate a random number between 1 and 10
  random_delay=$((RANDOM % 10 + 1))
  sleep $random_delay
  # Something is wrong - let's try to reconnect via the reverse proxy
  # Make sure to print empty string if $3, $4, $5, $6, $7, $8 are undefined
  #COMET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 0 --insecure --silent "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$NON_PERIODIC_COMET_DESIGNATION_URLENCODE'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets] /   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
  # Retry with the main horizons site, not proxy
  #COMET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 0 --insecure --silent --show-error "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$NON_PERIODIC_COMET_DESIGNATION_URLENCODE'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
  COMET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout $CONNECTION_TIMEOUT_SEC --retry 0 --insecure --silent --show-error "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$NON_PERIODIC_COMET_DESIGNATION_URLENCODE'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{if ($3=="" || $4=="" || $5=="" || $6=="" || $7=="" || $8=="") print ""; else printf "%02d:%02d:%05.2f %s:%02d:%04.1f %4.1fmag\n",$3,$4,$5,$6,$7,$8,$9}')
 else
  SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER=$((SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER + 1))
 fi
 if [ -n "$COMET_RA_DEC_MAG_STRING" ];then
  # Verify the format of $PLANET_RA_DEC_MAG_STRING - lib/hms2deg will return non-zero exit code if something is wrong with the coordinates
  if lib/hms2deg $COMET_RA_DEC_MAG_STRING &> /dev/null ;then
   echo "$COMET_RA_DEC_MAG_STRING $NON_PERIODIC_COMET_DESIGNATION_AND_NAME"
  else
   echo "00:00:00.00 +00:00:00.0 cannot parse JPL HORIZONS ephemerides #$COMET_RA_DEC_MAG_STRING# for non-periodic comet $PERIODIC_COMET_DESIGNATION_AND_NAME"
  fi
 else
  echo "00:00:00.00 +00:00:00.0 cannot get JPL HORIZONS ephemerides for non-periodic comet $NON_PERIODIC_COMET_DESIGNATION_AND_NAME"
  #
  if [ $SUCCESSFULLY_CONECTED_TO_JPL_HORIZONS_COUNTER -eq 0 ];then
   exit 1
  fi
  #
  continue
 fi
done
