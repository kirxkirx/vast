#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

CONNECTION_TIMEOUT_SEC=10

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

# Try local skyfield-based computation first (unless explicitly set to "remote")
if [ "$PLANETS_SH_LOCAL_OR_REMOTE" != "remote" ]; then
 if command -v python3 &>/dev/null && \
  python3 -c "import skyfield" &>/dev/null; then

  # Strip MPC_CODE from @399 suffix if present
  MPC_CODE_LOCAL="${MPC_CODE%@*}"

  if [ -n "$MPC_CODE_LOCAL" ] && [ -f ObsCodes.html ] && grep -q "^$MPC_CODE_LOCAL " ObsCodes.html ; then
   PLANET_FINDER_OBSERVATORY_CODE_ARGUMENT="-observatory $MPC_CODE_LOCAL"
  else
   PLANET_FINDER_OBSERVATORY_CODE_ARGUMENT=""
  fi

  python3 util/planet_finder/main.py calc -q -d "$JD" $PLANET_FINDER_OBSERVATORY_CODE_ARGUMENT
  if [ $? -eq 0 ]; then
   echo "Positions of planets computed with util/planet_finder/main.py for JD(UT)$JD $PLANET_FINDER_OBSERVATORY_CODE_ARGUMENT" > planets_header.txt
   cat planets_header.txt >&2
   exit 0
  fi
 fi
fi

# Explicitly fail if local planet search was required but unsuccessful
if [ "$PLANETS_SH_LOCAL_OR_REMOTE" = "local" ]; then
 echo "Local planet position computation failed!"
 exit 1
fi

# Fall back to HORIZONS
echo "Positions of planets from JPL HORIZONS for JD(UT)$JD at $MPC_CODE" > planets_header.txt
cat planets_header.txt >&2

# Add @399 suffix for HORIZONS if not present
if [[ "$MPC_CODE" != *@* ]]; then
 MPC_CODE="${MPC_CODE}@399"
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
 # sed 's/ [*CNAmrets] /   /g' is to remove Moon Sun presence markers and the likes - they may appear if MPC_CODE is set
 #PLANET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --insecure --silent --show-error "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$PLANET_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
 # curl --connect-timeout 10 --retry 1 --insecure --silent --show-error "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='899'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='C32'&TLIST='2460905.4421'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{printf "%02d:%02d:%05.2f %s:%02d:%04.1f %4.1fmag\n",$3,$4,$5,$6,$7,$8,$9}'
 PLANET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --insecure --silent --show-error "https://ssd.jpl.nasa.gov/api/horizons.api?format=text&COMMAND='$PLANET_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{printf "%02d:%02d:%05.2f %s:%02d:%04.1f %4.1fmag\n",$3,$4,$5,$6,$7,$8,$9}')
 if [ -z "$PLANET_RA_DEC_MAG_STRING" ];then
  # something is wrong - let's try to reconnect via the reverse proxy
  #PLANET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --insecure --silent --show-error "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PLANET_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
  PLANET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --insecure --silent --show-error "https://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PLANET_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{printf "%02d:%02d:%05.2f %s:%02d:%04.1f %4.1fmag\n",$3,$4,$5,$6,$7,$8,$9}')
  if [ -z "$PLANET_RA_DEC_MAG_STRING" ];then
   # last ditch attempt - reconnect via HTTP reverse proxy
   #PLANET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --insecure --silent --show-error "http://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PLANET_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{printf "%02d:%02d:%05.2f %+03d:%02d:%04.1f %4.1fmag",$3,$4,$5,$6,$7,$8,$9}')
   PLANET_RA_DEC_MAG_STRING=$(curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --insecure --silent --show-error "http://kirx.net/horizons/api/horizons.api?format=text&COMMAND='$PLANET_ID'&OBJ_DATA='YES'&MAKE_EPHEM='YES'&EPHEM_TYPE='OBSERVER'&CENTER='$MPC_CODE'&TLIST='$JD'&QUANTITIES='1,9'" | grep -B1 '$$EOE' | head -n1 | sed 's/ [*CNAmrets][*CNAmrets ]/   /g' | awk '{printf "%02d:%02d:%05.2f %s:%02d:%04.1f %4.1fmag\n",$3,$4,$5,$6,$7,$8,$9}')
  fi
 fi
 # Print the results string only if we got the planet position from Horizons
 if [ -n "$PLANET_RA_DEC_MAG_STRING" ];then
  # Verify the format of $PLANET_RA_DEC_MAG_STRING - lib/hms2deg will return non-zero exit code if something is wrong with the coordinates
  if lib/hms2deg $PLANET_RA_DEC_MAG_STRING &> /dev/null ;then
   echo "$PLANET_RA_DEC_MAG_STRING $PLANET_NAME" | awk '{print $1" "$2" "$4" ("$3")"}'
  fi
 fi
done

