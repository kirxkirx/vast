#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

#echo -e "Starting $0"

# Check if MPC_CODE is empty and set default value
if [ -z "$MPC_CODE" ];then
 # Default MPC code is 500 - geocenter
 MPC_CODE=500
fi
# Check if MPC_CODE contains '@' symbol like 500@399
if [[ "$MPC_CODE" = *@* ]];then
 # No HORIZONS codes for astcheck - just the plain MPC codes please
 MPC_CODE=500
fi
# Check if the length of MPC_CODE is not equal to 3 characters
if [ ${#MPC_CODE} -ne 3 ];then
 MPC_CODE=500
fi

# Test the command line arguments
if [ -z "$5" ];then
 echo " "
 echo "ERROR: search coordinates are not given! :("
 echo " "
 echo "Usage: $0 RA DEC YEAR MONTH DAYFRAC"
 echo "Example: $0 01:02:03.5 +05:06:07.8 2010 07 15.16789"
 exit 1
fi
RA=$1
DEC=$2

RAHH=`echo $RA |awk -F":" '{print $1}'`
RAMM=`echo $RA |awk -F":" '{print $2}'`
RASS=`echo $RA |awk -F":" '{print $3}'`

DECDD=`echo $DEC |awk -F":" '{print $1}'`
DECMM=`echo $DEC |awk -F":" '{print $2}'`
DECSS=`echo $DEC |awk -F":" '{print $3}'`

YEAR="$3"
MONTH="$4"
DAYFRAC="$5"

if [ -z "$6" ];then
 COLOR=1
else
 COLOR=0
fi  

MEASURED_TRANSIENT_MAG=""
if [ -z "$7" ];then
 MAG_FOR_MPC_REPORT="20.1"
else
 MAG_FOR_MPC_REPORT="$7"
 # Remember that the measured magnitude was explicitly provided:
 # this enables the comparison of the measured transient brightness
 # with the astcheck-predicted asteroid brightness below
 MEASURED_TRANSIENT_MAG="$7"
fi

if [ -z "$8" ];then
 TEST_MPC_FILE="test.mpc"
else
 TEST_MPC_FILE="$8"
fi

         
# Querry local copy of astcheck
if [ $COLOR -eq 1 ];then
 DATABASE_NAME="\033[01;36mastcheck\033[00m"
else
 DATABASE_NAME="<font color=\"teal\">astcheck</font>"
fi

ASTCHECK_OUTPUT=""
# Set to 1 if astcheck fails to run (see below), so that an empty result from a
# FAILED astcheck run is treated as an error rather than silently mistaken for a
# successful run that found no asteroid.
ASTCHECK_RUN_FAILED=0

THIS_A_PLANET_OR_COMET=0
#####
# Check if the thing is a planetary moon
EXCLUSION_LIST_FILE="moons.txt"
if [ -s "$EXCLUSION_LIST_FILE" ] && [ $THIS_A_PLANET_OR_COMET -eq 0 ] ;then
 PLANET_SEARCH_RESULTS=$(lib/put_two_sources_in_one_field "$RAHH:$RAMM:$RASS" "$DECDD:$DECMM:$DECSS" "$EXCLUSION_LIST_FILE" 180)
 echo "$PLANET_SEARCH_RESULTS" | grep -q "FOUND"
 if [ $? -eq 0 ];then
  #echo "$PLANET_SEARCH_RESULTS" | awk -F'FOUND' '{print $2}'
  ASTCHECK_OUTPUT=$(echo "$PLANET_SEARCH_RESULTS" | awk -F'FOUND' '{print $2}')
  THIS_A_PLANET_OR_COMET=1
 fi
fi
#####
#####
# Check if the thing is (close to) a major planet
THIS_A_PLANET_OR_COMET=0
EXCLUSION_LIST_FILE="planets.txt"
if [ -s "$EXCLUSION_LIST_FILE" ] && [ $THIS_A_PLANET_OR_COMET -eq 0 ] ;then
 PLANET_SEARCH_RESULTS=$(lib/put_two_sources_in_one_field "$RAHH:$RAMM:$RASS" "$DECDD:$DECMM:$DECSS" "$EXCLUSION_LIST_FILE" 400)
 echo "$PLANET_SEARCH_RESULTS" | grep -q "FOUND"
 if [ $? -eq 0 ];then
  #echo "$PLANET_SEARCH_RESULTS" | awk -F'FOUND' '{print $2}'
  ASTCHECK_OUTPUT=$(echo "$PLANET_SEARCH_RESULTS" | awk -F'FOUND' '{print $2}')
  THIS_A_PLANET_OR_COMET=1
 fi
fi
#####
#####
# Check if the thing is a bright comet
EXCLUSION_LIST_FILE="comets.txt"
if [ -s "$EXCLUSION_LIST_FILE" ] && [ $THIS_A_PLANET_OR_COMET -eq 0 ] ;then
 # the search radius has to match the one in util/transients/report_transient.sh
 PLANET_SEARCH_RESULTS=$(lib/put_two_sources_in_one_field "$RAHH:$RAMM:$RASS" "$DECDD:$DECMM:$DECSS" "$EXCLUSION_LIST_FILE" 120)
 echo "$PLANET_SEARCH_RESULTS" | grep -q "FOUND"
 if [ $? -eq 0 ];then
  #echo "$PLANET_SEARCH_RESULTS" | awk -F'FOUND' '{print $2}'
  ASTCHECK_OUTPUT=$(echo "$PLANET_SEARCH_RESULTS" | awk -F'FOUND' '{print $2}')
  THIS_A_PLANET_OR_COMET=1
 fi
fi
#####

# moved here as we want to produce $TEST_MPC_FILE irrespective of running astcheck
# The $TEST_MPC_FILE is reused by the transient search script!
echo "$YEAR $MONTH $DAYFRAC $RAHH $RAMM $RASS  $DECDD $DECMM $DECSS  $MAG_FOR_MPC_REPORT" | awk -v mpccode=$MPC_CODE '{printf "     TAU0008  C%s %02.0f %08.5f %02.0f %02.0f %05.2f %+03.0f %02.0f %04.1f          %4.1f R      %s\n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,mpccode}' > "$TEST_MPC_FILE"

if [ -z "$ASTCHECK_OUTPUT" ];then
 # This script should take care of updating astorb.dat
 #lib/update_offline_catalogs.sh all
 #
 #if [ ! -f astorb.dat ];then
 # # astorb.dat needs to be downloaded
 # echo "Downloading the asteroid database (astorb.dat)" 1>&2
 # #wget -c ftp://ftp.lowell.edu/pub/elgb/astorb.dat.gz 1>&2
 # #wget -c --no-check-certificate https://kirx.net/~kirx/vast_catalogs/astorb.dat.gz 1>&2
 # curl $VAST_CURL_PROXY --continue-at - --insecure --output astorb.dat.gz https://kirx.net/~kirx/vast_catalogs/astorb.dat.gz 1>&2
 # if [ $? -ne 0 ];then
 #  # a desperate recovery attempt
 #  #wget -c http://kirx.net/~kirx/vast_catalogs/astorb.dat.gz 1>&2
 #  curl $VAST_CURL_PROXY --continue-at - --output astorb.dat.gz http://kirx.net/~kirx/vast_catalogs/astorb.dat.gz 1>&2
 #  if [ $? -ne 0 ];then
 #   echo "ERROR: cannot download astorb.dat.gz"
 #   exit 1
 #  fi
 # fi
 # gunzip astorb.dat.gz
 # if [ $? -ne 0 ];then
 #  echo "ERROR: cannot gunzip astorb.dat.gz"
 #  exit 1
 # fi
 # if [ ! -f astorb.dat ];then
 #  echo "ERROR: cannot find astorb.dat"
 #  exit 1
 # fi
 #fi
 # Using local copy of astcheck to identify asteroids! See http://home.gwi.net/~pluto/devel/astcheck.htm for details
 # move up
 #echo "$YEAR $MONTH $DAYFRAC $RAHH $RAMM $RASS  $DECDD $DECMM $DECSS  $MAG_FOR_MPC_REPORT" | awk -v mpccode=$MPC_CODE '{printf "     TAU0008  C%s %02.0f %08.5f %02.0f %02.0f %05.2f %+03.0f %02.0f %04.1f          %4.1f R      %s\n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,mpccode}' > "$TEST_MPC_FILE"
 # 400" is the search radius
 #ASTCHECK_OUTPUT=$(lib/astcheck test.mpc -r400 -m15 |grep -A 50 "TAU0008" |grep -v "TAU0008" |head -n 1 | grep -v ObsCodes.html)
 if [ -z "$ASTEROID_SEARCH_MAG_LIMIT" ];then
  ASTEROID_SEARCH_MAG_LIMIT=16
  if [ -n "$FILTER_FAINT_MAG_CUTOFF_TRANSIENT_SEARCH" ];then
   ASTEROID_SEARCH_MAG_LIMIT=$(echo "$FILTER_FAINT_MAG_CUTOFF_TRANSIENT_SEARCH" | awk '{printf "%.1f", 2+$1}')
  fi
 fi # if [ -z "$ASTEROID_SEARCH_MAG_LIMIT" ];then
 #cat $TEST_MPC_FILE
 if [ -z "$ASTCHECK_ASTEROID_SEARCH_RADIUS_ARCSEC" ];then
  ASTCHECK_ASTEROID_SEARCH_RADIUS_ARCSEC=600
 fi
 # I want a larger search radius because TESS
 #ASTCHECK_OUTPUT=$(lib/astcheck "$TEST_MPC_FILE" -r600 -m"$ASTEROID_SEARCH_MAG_LIMIT" | grep -A 50 "TAU0008" | grep -v "TAU0008" | head -n 1 | grep -v ObsCodes.html)
 # Run astcheck and verify it actually ran to completion. astcheck is a local,
 # deterministic computation, so a failure is a genuine error (missing/corrupt
 # astorb.dat, the process killed under load, an I/O error, ...) -- not transient
 # noise to retry away. But a failed run produces empty output, which must NOT be
 # confused with a successful run that found no asteroid: doing so would report a
 # real asteroid as a brand-new transient. astcheck echoes the input designation
 # (TAU0008) on stdout and exits 0 only once it has loaded the elements and
 # processed the observation, so that is our "astcheck ran to completion" signal.
 ASTCHECK_RAW=$(lib/astcheck "$TEST_MPC_FILE" -r"$ASTCHECK_ASTEROID_SEARCH_RADIUS_ARCSEC" -m"$ASTEROID_SEARCH_MAG_LIMIT" 2>/dev/null)
 ASTCHECK_RUN_EXIT_CODE=$?
 if [ $ASTCHECK_RUN_EXIT_CODE -eq 0 ] && echo "$ASTCHECK_RAW" | grep -q "TAU0008" ;then
  ASTCHECK_OUTPUT=$(echo "$ASTCHECK_RAW" | grep -A 50 "TAU0008" | grep -v "TAU0008" | head -n 1 | grep -v ObsCodes.html)
 else
  # astcheck did not run to completion -- a real error, not "no asteroid found".
  ASTCHECK_RUN_FAILED=1
  echo "ERROR: astcheck failed to run (exit code $ASTCHECK_RUN_EXIT_CODE) on $TEST_MPC_FILE -- asteroid status is UNKNOWN" >&2
 fi
fi

if [ $ASTCHECK_RUN_FAILED -eq 1 ] ;then
 # astcheck errored out: report it as an error. Do NOT print "not found", which
 # would let a real asteroid through as a brand-new transient.
 if [ $COLOR -eq 1 ];then
  echo -e "\033[01;31mERROR: astcheck failed to run\033[00m -- asteroid status UNKNOWN; please check manually (e.g. with the online MPChecker)."
 else
  echo -e "<b><font color=\"red\">ERROR: astcheck failed to run</font></b> -- asteroid status UNKNOWN; please check manually (e.g. with the online MPChecker)."
 fi
 exit 2 # return code: astcheck error -- asteroid status could not be determined
elif [ -z "$ASTCHECK_OUTPUT" ] && [ $THIS_A_PLANET_OR_COMET -eq 0 ] ;then
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;32mnot found\033[00m in $DATABASE_NAME."
 else
  echo -e "The object was <font color=\"green\">not found</font> in $DATABASE_NAME."
 fi
 exit 1 # return code will signal we have no ID
else
 if [ $COLOR -eq 1 ];then
  echo -e "The object was \033[01;31mfound\033[00m in $DATABASE_NAME.  "
  echo "$ASTCHECK_OUTPUT"
 else
  echo -e "<b>The object was <font color=\"red\">found</font> in $DATABASE_NAME.</b>  "
  # Put <b> </b> around the first two words (four words if the string includes 'C/')
  echo "$ASTCHECK_OUTPUT" | awk '{
    if (NF == 0) { 
        print; 
    } else if (index($0, "C/") > 0) {
        if (NF == 1) {
            print "<b>" $1 "</b>";
        } else if (NF == 2) {
            bolded = "<b>" $1 " " $2 "</b>";
            rest = substr($0, index($0, $2) + length($2));
            print bolded, rest;
        } else if (NF == 3) {
            bolded = "<b>" $1 " " $2 " " $3 "</b>";
            rest = substr($0, index($0, $3) + length($3));
            print bolded, rest;
        } else {
            bolded = "<b>" $1 " " $2 " " $3 " " $4 "</b>";
            rest = substr($0, index($0, $4) + length($4));
            print bolded, rest;
        }
    } else if (NF == 1) { 
        print "<b>" $1 "</b>"; 
    } else { 
        bolded = "<b>" $1 " " $2 "</b>";
        rest = substr($0, index($0, $2) + length($2));
        print bolded, rest;
    }
}'
 fi
 # Compare the measured brightness of the transient with the astcheck-predicted brightness of the matched asteroid.
 # A transient that is much brighter than the prediction deserves attention as the positional match
 # may be a chance coincidence. The comparison is done only if the measured magnitude was explicitly
 # provided on the command line and this is a real astcheck match (not a planet/moon/comet list match
 # that carries no magnitude). The wording of the ATTENTION line must not contain the phrases
 # 'The object was', 'found in' or 'not found' relied upon by the downstream parsers
 # (unmw filter_report.py, transient_factory_test31.sh, the artificial star test);
 # 'mag brighter than the' is the stable marker substring the downstream tools may key on.
 if [ -n "$MEASURED_TRANSIENT_MAG" ] && [ $THIS_A_PLANET_OR_COMET -eq 0 ];then
  # In the astcheck output line the predicted magnitude is the 3rd field from the end:
  # designation(s)  dRA"  dDec"  dist"  mag  dRA/hr  dDec/hr
  PREDICTED_ASTEROID_MAG=$(echo "$ASTCHECK_OUTPUT" | awk '{print $(NF-2)}')
  # Get the threshold from vast_limits.h, fall back to the default value if the file is not reachable
  TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD=$(grep '#define TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD ' src/vast_limits.h 2>/dev/null | awk '{print $3}')
  if [ -z "$TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD" ];then
   TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD=3.0
  fi
  # Require both magnitudes to be valid numbers in a plausible range and the difference to be large
  TEST=$(echo "$PREDICTED_ASTEROID_MAG $MEASURED_TRANSIENT_MAG $TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD" | awk '{if ( $1 != $1+0 || $2 != $2+0 || $1 <= 0 || $1 > 30 || $2 < -2 || $2 > 30 ) {print 0} else {if ( $1 - $2 > $3 ) {print 1} else {print 0}}}')
  if [ "$TEST" = "1" ];then
   MAG_DIFF_FOR_DISPLAY=$(echo "$PREDICTED_ASTEROID_MAG $MEASURED_TRANSIENT_MAG" | awk '{printf "%.1f", $1-$2}')
   if [ $COLOR -eq 1 ];then
    echo -e "\033[01;31mATTENTION: measured mag $MEASURED_TRANSIENT_MAG is $MAG_DIFF_FOR_DISPLAY mag brighter than the predicted asteroid brightness $PREDICTED_ASTEROID_MAG - the transient may be an unrelated new object!\033[00m"
   else
    echo "<b><font color=\"red\">ATTENTION: measured mag $MEASURED_TRANSIENT_MAG is $MAG_DIFF_FOR_DISPLAY mag brighter than the predicted asteroid brightness $PREDICTED_ASTEROID_MAG - the transient may be an unrelated new object!</font></b>"
   fi
  fi
 fi
 exit 0 # return code will signal we have an ID
fi # else lib/astcheck 
