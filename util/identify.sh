#!/usr/bin/env bash
#
# This script will conduct astrometric calibration of an image. It may also identify a star using this calibrated image.
#
# ERROR_STATUS indicates error conditions
# 0 - OK
# 1 - field not solved, no need to retry
# 2 - possible server communication error, retry (with another plate solve server?)
ERROR_STATUS=0

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# A more portable realpath wrapper
function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=`readlink -f "$1" 2>/dev/null`
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=`greadlink -f "$1" 2>/dev/null`
   if [ $? -ne 0 ];then
    REALPATH=`realpath "$1" 2>/dev/null`
    if [ $? -ne 0 ];then
     REALPATH=`grealpath "$1" 2>/dev/null`
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")" || exit 1
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit 1
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

# Function to remove the last occurrence of a directory from a path
remove_last_occurrence() {
    echo "$1" | awk -F/ -v dir="$2" '{
        found = 0;
        for (i=NF; i>0; i--) {
            if ($i == dir && found == 0) {
                found = 1;
                continue;
            }
            res = (i==NF ? $i : $i "/" res);
        }
        print res;
    }'
}

# Function to get full path to vast main directory from the script name
get_vast_path_ends_with_slash_from_this_script_name() {
 VAST_PATH=$(vastrealpath $0)
 VAST_PATH=$(dirname "$VAST_PATH")

 # Remove last occurrences of util, lib, examples
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "util")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "lib")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "examples")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "transients")

 # Make sure no '//' are left in the path (they look ugly)
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")

 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")

 # Check that VAST_PATH ends with '/'
 LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
 if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
  VAST_PATH="$VAST_PATH/"
 fi

 echo "$VAST_PATH"
}

# 0 - no, unknown telescope - have to plate-solve the image in the normal way
# 1 - yes, we trust WCS solution in images from this telescope
function check_if_we_know_the_telescope_and_can_blindly_trust_wcs_from_the_image {
 if [ -z "$1" ];then
  return 0
 fi
 FITS_IMAGE_TO_CHECK="$1"
 if [ -z "$VAST_PATH" ];then
  VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
 fi
 # Check that VAST_PATH ends with '/'
 LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
 if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
  VAST_PATH="$VAST_PATH/"
 fi
 #
 FITS_IMAGE_TO_CHECK_HEADER=`"$VAST_PATH"util/listhead "$FITS_IMAGE_TO_CHECK"`
 # Check if it has WCS keywords
 for TYPICAL_WCS_KEYWORD in CTYPE1 CTYPE2 CRVAL1 CRVAL2 CRPIX1 CRPIX2 CD1_1 CD1_2 CD2_1 CD2_2 ;do
  echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep -q "$TYPICAL_WCS_KEYWORD"
  if [ $? -ne 0 ];then
   return 0
  fi
 done
 
 ### Some keywords identifying specific telescopes are to be added here in the future
 ### But for now...
 
 ### !!! Blindly trust WCS if it was created by Astrometry.net code !!! ###
 echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep -q -e 'HISTORY Created by the Astrometry.net suite.' -e 'HISTORY WCS created by AIJ link to Astronomy.net website'
 if [ $? -eq 0 ];then
  # TEST for the possibility that this is one of the messed-up NMW archive images
  echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep -q -e 'A_0_0' -e 'A_2_0' && echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep -q 'PV1_1'
  if [ $? -eq 0 ];then
   echo "$0  -- WARNING, the input image has both A_0_0 and PV1_1 distortions kewords! Will try to re-solve the image."
  else
   # Trust this image
   return 1
  fi
 fi
 
 ### !!! Blindly trust WCS if it was created by SCAMP code !!! ###
 echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep -q -e 'HISTORY   Astrometric solution by SCAMP version'
 if [ $? -eq 0 ];then
  return 1
 fi
 
 ### !!! Blindly trust WCS if it was created by SWarp image stacking code !!! ###
 echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep -q "SOFTNAME= 'SWarp"
 if [ $? -eq 0 ];then
  return 1
 fi
 
 ### !!! Blindly trust ZTF image astrometry !!! ###
 # (actually it will have the above SCAMP keyword too)
 echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep -B500 -A500 "ORIGIN  = 'Zwicky Transient Facility'" | grep -B500 -A500 "INSTRUME= 'ZTF/MOSAIC'" |  grep -q "CTYPE1  = 'RA---TPV'"
 if [ $? -eq 0 ];then
  return 1
 fi

 ### !!! Blindly trust TESS FFI astrometry !!! ###
 echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep -B500 -A500 "TELESCOP= 'TESS    '" | grep -B500 -A500 "INSTRUME= 'TESS Photometer'" |  grep -q "CTYPE1  = 'RA---TAN-SIP'"
 if [ $? -eq 0 ];then
  return 1
 fi
 
 ### !!! Blindly trust ATLAS astrometry !!! ###
 echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep -B500 -A500 "ATLAS camera ID" |  grep -q "CTYPE2  = 'DEC--TPV'"
 if [ $? -eq 0 ];then
  return 1
 fi
 
 ### !!! Blindly trust ASTAP astrometry !!! ###
 echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep -B500 -A500 "ASTAP" |  grep -q "PLTSOLVD=                    T"
 if [ $? -eq 0 ];then
  return 1
 fi
 
 # Nope, uncorrected LBT/LBC astrometry is pretty bad actually - can't trust it
 #### !!! Blindly trust LBT/LBC astrometry !!! ###
 #echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep -B500 -A500 "LBCOBFIL" | grep -B500 -A500 "LBCCHIP" |  grep -q "CTYPE2  = 'DEC--TAN'"
 #if [ $? -eq 0 ];then
 # return 1
 #fi
 
 return 0
}

# Function to determine local vs remote astrometry.net availability
function determine_astrometry_method {
 echo "Determining astrometry method..." 1>&2
 
 # Check the default Astrometry.net install locations first
 if [ -d /usr/local/astrometry/bin ];then
  echo "$PATH" | grep -q '/usr/local/astrometry/bin'
  if [ $? -ne 0 ];then
   export PATH=$PATH:/usr/local/astrometry/bin
  fi
 fi
 # Check another default Astrometry.net install location
 if [ -d /usr/share/astrometry/bin ];then
  echo "$PATH" | grep -q '/usr/share/astrometry/bin'
  if [ $? -ne 0 ];then
   export PATH=$PATH:/usr/share/astrometry/bin
  fi
 fi

 # if ASTROMETRYNET_LOCAL_OR_REMOTE was not set externally to the script
 if [ -z "$ASTROMETRYNET_LOCAL_OR_REMOTE" ];then
  command -v solve-field &>/dev/null
  if [ $? -eq 0 ];then
   # Check that this is an executable file
   if [ -x $(command -v solve-field) ];then
    echo "Using the local copy of Astrometry.net software..." 1>&2
    ASTROMETRYNET_LOCAL_OR_REMOTE="local"
   else
    echo "WARNING: solve-field is found, but it is not an executable file!" 1>&2
    echo "Will try remote server..." 1>&2
    ASTROMETRYNET_LOCAL_OR_REMOTE="remote"
   fi
  else
   echo "Local solve-field not found, will try remote server..." 1>&2
   ASTROMETRYNET_LOCAL_OR_REMOTE="remote"
  fi
 else
  echo "environment variable set: ASTROMETRYNET_LOCAL_OR_REMOTE=$ASTROMETRYNET_LOCAL_OR_REMOTE" 1>&2
 fi
}

# Function to check remote server availability and set up remote astrometry
function setup_remote_astrometry {
 echo "Setting up remote astrometry servers..." 1>&2
 
 local HOST_WE_ARE_RUNNING_AT=$(hostname)
 local PLATE_SOLVE_SERVERS="tau.kirx.net scan.sai.msu.ru"

 # Check if we are requested to use a specific plate solve server
 if [ ! -z "$FORCE_PLATE_SOLVE_SERVER" ];then
  if [ "$FORCE_PLATE_SOLVE_SERVER" != "none" ];then
   echo "WARNING: using the user-specified plate solve server $FORCE_PLATE_SOLVE_SERVER" 1>&2
   PLATE_SOLVE_SERVER="$FORCE_PLATE_SOLVE_SERVER"
   PLATE_SOLVE_SERVERS="$PLATE_SOLVE_SERVER"
  fi
 fi

 ###################################################
 echo -n "Checking if we can reach any plate solve servers... " 1>&2
 # Decide on which plate solve server to use
 # first - set the initial list of servers
 for FILE_TO_CHECK in server$$_*.ping_ok ;do
  if [ -f "$FILE_TO_CHECK" ];then
   rm -f "$FILE_TO_CHECK"
  fi
 done
 for i in $PLATE_SOLVE_SERVERS ;do
  # ping to the outside world may be blocked
  if [ "$(uname)" = "Linux" ]; then
   # -W1 is set 1 sec timeout on Linux
   ping -c1 -n "$i" -W1 &>/dev/null && echo "$i" > server$$_"$i".ping_ok &
  else
   # -W1000 is set 1 sec timeout on FreeBSD/MacOS
   ping -c1 -n "$i" -W1000 &>/dev/null && echo "$i" > server$$_"$i".ping_ok &
  fi
  echo -n "$i " 1>&2
 done

 wait
 ### The ping test will not work if we are behind a firewall that doesn't let ping out
 # If no servers could be reached, try to test for this possibility
 ########################################
 for SERVER_PING_OK_FILE in server$$_*.ping_ok ;do
  if [ -f $SERVER_PING_OK_FILE ];then
   # OK we could ping at least one server
   break
  fi
  # If we are still here, that means we are either offline or behind a firewall that doesn't let ping out
  for i in $PLATE_SOLVE_SERVERS ;do
   # make sure we'll not remotely connect to ourselves
   if [ ! -z "$HOST_WE_ARE_RUNNING_AT" ];then
    echo "$i" | grep -q "$HOST_WE_ARE_RUNNING_AT"
    if [ $? -eq 0 ];then
     continue
    fi
   fi
   #
   #curl --max-time 10 --silent http://"$i"/astrometry_engine/files/ | grep -q 'Parent Directory' && echo "$i" > server$$_"$i".ping_ok &
   curl $VAST_CURL_PROXY --max-time 10 --silent http://"$i"/lk/ | grep -q '/cgi-bin/lk/process_lightcurve.py' && echo "$i" > server$$_"$i".ping_ok &
   echo -n "$i " 1>&2
  done
  wait
 done
 ########################################

 cat server$$_*.ping_ok > servers$$.ping_ok 2>/dev/null

 echo "" 1>&2
 echo "The reachable servers are:" 1>&2
 cat servers$$.ping_ok 1>&2

 if [ ! -s servers$$.ping_ok ];then
  echo "ERROR: no servers could be reached" 1>&2
  rm -f server$$_*.ping_ok servers$$.ping_ok 2>/dev/null
  return 1
 fi

 local N_REACHABLE_SERVERS=`cat servers$$.ping_ok | wc -l`
 if [ $N_REACHABLE_SERVERS -eq 1 ];then
  PLATE_SOLVE_SERVER=`head -n1 servers$$.ping_ok`
 else
  # Choose a random server among the available ones
  PLATE_SOLVE_SERVER=`$TIMEOUT_COMMAND 10 sort --random-sort --random-source=/dev/urandom servers$$.ping_ok | head -n1`
  # If the above fails because sort doesn't understand the '--random-sort' option
  if [ "$PLATE_SOLVE_SERVER" = "" ];then
   PLATE_SOLVE_SERVER=`head -n1 servers$$.ping_ok`
  fi
 fi # if [ $N_REACHABLE_SERVERS -eq 1 ];then

 # Update the list of available servers
 PLATE_SOLVE_SERVERS=""
 while read SERVER ;do
  PLATE_SOLVE_SERVERS="$PLATE_SOLVE_SERVERS $SERVER"
 done < servers$$.ping_ok
 echo "Updated list of available servers: $PLATE_SOLVE_SERVERS" 1>&2

 rm -f server$$_*.ping_ok servers$$.ping_ok

 if [ "$PLATE_SOLVE_SERVER" = "" ];then
  echo "ERROR choosing the plate solve server" 1>&2
  return 1
 else
  echo "We choose the plate solve server $PLATE_SOLVE_SERVER" 1>&2
 fi
 ###################################################

 # Find curl
 CURL=$(command -v curl)
 if [ $? -ne 0 ];then
  echo "ERROR: cannot find curl in PATH" 1>&2
  return 1
 else
  # Set max time for all network communications
  # note that this is ALSO acomplished by the timeout command before curl
  # AND at the server side
  #CURL="$CURL --max-time 299 "
  # Needed for POST queries to work with cURL
  CURL="$CURL $VAST_CURL_PROXY --max-time 299 -H 'Expect:'"
 fi 

 return 0
}

########### Main part of the script begins here ###########

VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")

export VAST_PATH
OLDDDIR_TO_CHECK_INPUT_FILE="$PWD"
cd "$VAST_PATH" || exit 1

# Set the correct path to 'timeout'
TIMEOUT_COMMAND=`"$VAST_PATH"lib/find_timeout_command.sh`
export TIMEOUT_COMMAND


# Set SExtractor executable
SEXTRACTOR=sex
echo "$PATH" | grep -q "$VAST_PATH"lib/bin/
if [ $? -ne 0 ];then
 export PATH=$PATH:"$VAST_PATH"lib/bin/
fi

# Determine working mode: star identification or image WCS calibration
START_NAME=$(basename $0)
if [ "$START_NAME" = "wcs_image_calibration.sh" ] || [ "$START_NAME" = "wcs_image_nocatalog.sh" ];then
 echo "Entering WCS image calibration mode."
 if [ -z "$1" ]; then
  echo "
Usage: $0 image.fit
 or
       $0 image.fit FIELD_OF_VIEW_IN_ARCMIN"
  exit 1
 fi
 FITSFILE="$1"
 if [ ! -f "$FITSFILE" ];then
  if [ -f "$OLDDDIR_TO_CHECK_INPUT_FILE"/"$FITSFILE" ];then
   FITSFILE="$OLDDDIR_TO_CHECK_INPUT_FILE/$FITSFILE"
  else
   echo "ERROR cannot find the input FITS image $FITSFILE"
   exit 1
  fi
 fi
 APP=6.0 
else
 echo "Entering star identification mode."
 if [ -z "$1" ]; then
  echo "
Usage: $0 outNUMBER.dat
 or
       $0 outNUMBER.dat FIELD_OF_VIEW_IN_ARCMIN"
  exit 1
 fi
 LIGHTCURVEFILE="$1"
 # Check if that file actually exists
 if [ ! -f "$LIGHTCURVEFILE" ];then
  if [ -f "$OLDDDIR_TO_CHECK_INPUT_FILE"/"$LIGHTCURVEFILE" ];then
   LIGHTCURVEFILE="$OLDDDIR_TO_CHECK_INPUT_FILE/$LIGHTCURVEFILE"
  else
   echo "ERROR: the lightcurve file $LIGHTCURVEFILE does not exist!"
   exit 1
  fi
 fi
 # Get the image name from the lightcurve file (first line, last column)
 echo -ne "reading light curve $LIGHTCURVEFILE - "
 read JD MAG MERR X Y APP FITSFILE REST < $LIGHTCURVEFILE && echo "ok"
 # TRAP!! If we whant to identify a flare, there will be no sence to search for an asteroid on the reference image.
 # Use the first discovery image instead!
 REFERENCE_IMAGE=`cat "$VAST_PATH"vast_summary.log |grep "Ref.  image:" | awk '{print $6}'`
 if [ "$START_NAME" = "identify_transient.sh" ];then
  while read JD MAG MERR X Y APP FITSFILE REST ;do
  if [ "$FITSFILE" != "$REFERENCE_IMAGE" ] ;then 
   break
  fi
  done < "$LIGHTCURVEFILE"
 fi
fi

# Check if FITSFILE variable is set correctly
if [ -z "$FITSFILE" ];then
 echo "ERROR: FITSFILE variable is not set while it is supposed to be set befor reaching this point in the script."
 exit 1
fi

# Check if the image actually exists
if [ ! -f "$FITSFILE" ];then
 echo "ERROR: cannot find the image file $FITSFILE"
 exit 1
fi
# Check if the image file is not empty
if [ ! -s "$FITSFILE" ];then
 echo "ERROR: the input image file $FITSFILE is empty"
 exit 1
fi
###############
# On-the fly convert the input image if necessary
FITSFILE=`"$VAST_PATH"lib/on_the_fly_symlink_or_convert "$FITSFILE"`
###############
# Verify that the input file is a valid FITS file
if [ -x "$VAST_PATH"lib/fitsverify ];then
 "$VAST_PATH"lib/fitsverify -q -e "$FITSFILE"
 if [ $? -ne 0 ];then
  echo "WARNING: the input file $FITSFILE seems to be a FITS image that does not fully comply with the FITS standard.
Checking if the filename extension and FITS header look reasonable..."
  ## Exampt from the rule for files that have at least some correct keywords
  echo "$FITSFILE" | grep  -e ".fits"  -e ".FITS"  -e ".fts" -e ".FTS"  -e ".fit"  -e ".FIT" && "$VAST_PATH"util/listhead "$FITSFILE" | grep -e "SIMPLE  =                    T" -e "TELESCOP= 'Aristarchos'" && "$VAST_PATH"util/listhead "$FITSFILE" | grep -e "NAXIS   =                    2"  -e "NAXIS3  =                    1" -e "TELESCOP= 'Aristarchos'"
  if [ $? -eq 0 ];then
   echo "OK, let's assume this is a valid FITS file"
  else
   echo "ERROR: the input image file $FITSFILE did not pass verification as a valid FITS file"
   exit 1
  fi
 fi
else
 echo "WARNING: ${VAST_PATH}lib/fitsverify is not an executable file! Skipping FITS format checks."
fi # else if [ -x "$VAST_PATH"lib/fitsverify ];then

###
BASENAME_FITSFILE=$(basename "$FITSFILE")
###

# Test if the original image is already a calibrated one
# (Test by checking the file name)
TEST_SUBSTRING="$BASENAME_FITSFILE"
TEST_SUBSTRING="${TEST_SUBSTRING:0:4}"
#TEST_SUBSTRING=`expr substr $TEST_SUBSTRING  1 4`
if [ "$TEST_SUBSTRING" = "wcs_" ];then
 echo "Special case: the file name suggests the file has already been plate-solved with VaST"
 cp -v "$FITSFILE" .
 WCS_IMAGE_NAME="$BASENAME_FITSFILE"
else
 WCS_IMAGE_NAME=wcs_"$BASENAME_FITSFILE"
 # Test if the original image has a WCS header and we should just blindly trust it
 check_if_we_know_the_telescope_and_can_blindly_trust_wcs_from_the_image "$FITSFILE"
 if [ $? -eq 1 ];then
  echo "The input image $FITSFILE has a WCS header - will blindly trust it is good..."
  cp -v "$FITSFILE" "$WCS_IMAGE_NAME" 
 fi
fi

SEXTRACTOR_CATALOG_NAME="$WCS_IMAGE_NAME".cat

# Check if vast_summary.log file is present
if [ ! -f "$VAST_PATH"vast_summary.log ];then
 echo "vast_summary.log not found! Creating a fake one..."
 # Note, we set default.sex.PHOTO instead of default.sex file because the situation when we have
 # a dataset reduced with an old version of vast which does not write the log file is more likely
 # to occur with photographic data
 #echo "SExtractor parameter file: default.sex.PHOTO " > vast_summary.log 
 # No, this was stupid! The data loading script will make sure the proper default.sex file is in the directory!
 echo "SExtractor parameter file: default.sex " > "$VAST_PATH"vast_summary.log 
fi


# Parse the command line arguments
if [ -z "$2" ];then 
 echo "Field of view for the image $FITSFILE was not set. Trying to guess..."
 FIELD_OF_VIEW_ARCMIN=$("$VAST_PATH"lib/try_to_guess_image_fov "$FITSFILE" 2>/dev/null)
 if [ -n "$FIELD_OF_VIEW_ARCMIN" ];then
  echo "The guess is $FIELD_OF_VIEW_ARCMIN arcmin."
 fi
  
else
 #FIELD_OF_VIEW_ARCMIN="$2"
 # Take maximum of 5 characters, just to be safe
 FIELD_OF_VIEW_ARCMIN="${2:0:5}"
fi

#### Check if FIELD_OF_VIEW_ARCMIN is reasonable ####
if [ -n "$FIELD_OF_VIEW_ARCMIN" ];then

 # Make sure there are no white spaces in FIELD_OF_VIEW_ARCMIN
 FIELD_OF_VIEW_ARCMIN="${FIELD_OF_VIEW_ARCMIN// /}"

 echo "$FIELD_OF_VIEW_ARCMIN" | awk '/^[0-9]*\.?[0-9]+$/ {exit !($1 > 0)}; {exit 1}'
 if [ $? -ne 0 ]; then
  echo "ERROR in $0: FIELD_OF_VIEW_ARCMIN=#$FIELD_OF_VIEW_ARCMIN# must be a positive number" >&2
  exit 1
 fi

 echo "$FIELD_OF_VIEW_ARCMIN" | awk '{exit !($1 > 0.0 && $1 < 21600)}'
 if [ $? -ne 0 ]; then
  echo "ERROR in $0: the supplied field-of-view guess ($FIELD_OF_VIEW_ARCMIN arcmin) seems totally unreasonable!"
  exit 1
 fi

 # Check if it's hopelessly small
 #TEST=`echo "$FIELD_OF_VIEW_ARCMIN<1.0"| awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
 #if [ $TEST -eq 1 ];then
 echo "$FIELD_OF_VIEW_ARCMIN<1.0" | awk -F'<' '{exit !($1 < $2)}'
 if [ $? -eq 0 ]; then
  # If we know FIELD_OF_VIEW_ARCMIN is so small we have no hope to blindly solve it 
  # - try to rely on WCS information that may be already inserted in the image
  if [ ! -f $WCS_IMAGE_NAME ];then
   echo $SEXTRACTOR -c $(grep "SExtractor parameter file:" "$VAST_PATH"vast_summary.log |awk '{print $4}') -PARAMETERS_NAME "$VAST_PATH"wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME -PHOT_APERTURES `"$VAST_PATH"lib/autodetect_aperture_main $FITSFILE 2>/dev/null` `"$VAST_PATH"lib/guess_saturation_limit_main $FITSFILE 2>/dev/null`  $FITSFILE 
   $SEXTRACTOR -c "$VAST_PATH"$(grep "SExtractor parameter file:" "$VAST_PATH"vast_summary.log |awk '{print $4}') -PARAMETERS_NAME "$VAST_PATH"wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME -PHOT_APERTURES `"$VAST_PATH"lib/autodetect_aperture_main $FITSFILE 2>/dev/null` `"$VAST_PATH"lib/guess_saturation_limit_main $FITSFILE 2>/dev/null`  $FITSFILE && echo "Using WCS information from the original image" 1>&2 && cp $FITSFILE $WCS_IMAGE_NAME
   "$VAST_PATH"lib/correct_sextractor_wcs_catalog_using_xy2sky.sh "$WCS_IMAGE_NAME" "$SEXTRACTOR_CATALOG_NAME"
  fi
 fi # if [ $TEST -eq 1 ];then
fi

# Set the default filed-of-view guess value if it was not set
if [ -z "$FIELD_OF_VIEW_ARCMIN" ];then
 echo "ERROR guessing the field of view, assuming the default value"
 FIELD_OF_VIEW_ARCMIN=40
fi

#### ####

# Now the interesting part...

if [ ! -s "$WCS_IMAGE_NAME" ];then
 # Handle the situation where the file exist but is empty
 if [ -f "$WCS_IMAGE_NAME" ];then
  rm -f "$WCS_IMAGE_NAME"
 fi
 #
 echo -n "No image with WCS calibration found for $FITSFILE .... "
 
 # Only NOW determine the astrometry method - when we actually need plate solving
 determine_astrometry_method
 
 #IMAGE_SIZE=`"$VAST_PATH"lib/astrometry/get_image_dimentions $FITSFILE | awk '{print "width="$2" -F hight="$4}'`
 # The stuff below seems to work fine
 CATALOG_NAME=`"$VAST_PATH"lib/fits2cat $FITSFILE`
 if [ -f "$CATALOG_NAME".apphot ];then
  CATALOG_NAME="$CATALOG_NAME".apphot
 fi
 "$VAST_PATH"lib/make_outxyls_for_astrometric_calibration "$CATALOG_NAME" out$$.xyls `"$VAST_PATH"lib/astrometry/get_image_dimentions $FITSFILE | awk '{print $2" "$4}'`
 if [ $? -ne 0 ];then
  echo "ERROR running $VAST_PATH""lib/make_outxyls_for_astrometric_calibration!"
  exit 1
 fi
 if [ ! -f out$$.xyls ];then
  echo "ERROR: out$$.xyls not found!"
  exit 1
 fi
 echo " 
This service uses tools provided by Astrometry.net.
For more information visit http://astrometry.net/ 
"

# Print the small FoV warning only if the guessed FoV is actually small
TEST=$(echo "$FIELD_OF_VIEW_ARCMIN" | awk '{if ( $1 < 20 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
 echo "Please note, the automatic identification usually works fine with a large field 
of view (say, >40 arcmin). If the images are smaller than 20', the automatic 
field identification have good chances to fail. Sorry... :(
"
fi

 # Try to solve the image with a range of trial FIELD_OF_VIEW_ARCMINs

 #for TRIAL_FIELD_OF_VIEW_ARCMIN in $FIELD_OF_VIEW_ARCMIN `echo "$FIELD_OF_VIEW_ARCMIN" | awk '{printf "%.1f",3*$1}'` `echo "$FIELD_OF_VIEW_ARCMIN" | awk '{printf "%.1f",$1*3/4}'` ;do
 for TRIAL_FIELD_OF_VIEW_ARCMIN in $FIELD_OF_VIEW_ARCMIN `echo "$FIELD_OF_VIEW_ARCMIN" | awk '{printf "%.1f",3*$1}'` `echo "$FIELD_OF_VIEW_ARCMIN" | awk '{if ( $1 < 60 ) printf "%.1f",$1*3/4; else printf "%.1f",0.5*$1}'` ;do
 
 echo "######### Trying to solve plate assuming $TRIAL_FIELD_OF_VIEW_ARCMIN' field of view #########
 $FITSFILE"

 ############################################################################
 # Local plate-solving software
 if [ "$ASTROMETRYNET_LOCAL_OR_REMOTE" = "local" ];then
  
  echo "Using the local copy of Astrometry.net code"
  
  IMAGE_SIZE=`"$VAST_PATH"lib/astrometry/get_image_dimentions $FITSFILE`
  # "0.9*$TRIAL_FIELD_OF_VIEW_ARCMIN matches the remote server parameters
  SCALE_LOW=`echo "$TRIAL_FIELD_OF_VIEW_ARCMIN" | awk '{printf "%.1f",0.9*$1}'`
  # Yes, works fine with 1.2*$TRIAL_FIELD_OF_VIEW_ARCMIN but does not work with 1.0*$TRIAL_FIELD_OF_VIEW_ARCMIN
  SCALE_HIGH=`echo "$TRIAL_FIELD_OF_VIEW_ARCMIN" | awk '{printf "%.1f",5.0*$1}'`
  #
  #
  echo "Using solve-field binary"
  command -v solve-field
  #
  # Blind solve
  # old parameters - they work
  #`"$VAST_PATH"lib/find_timeout_command.sh` 600 solve-field --objs 1000 --depth 10,20,30,40,50  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  $TIMEOUT_COMMAND 900 solve-field  --crpix-center --uniformize 0  --objs 1000 --depth 10,20,30-50  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH  out$$.xyls
  #$TIMEOUT_COMMAND 900 solve-field  --crpix-center --uniformize 0  --objs 1000 --depth 10,20,30-50  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  # the command below sometimes fails on STL images, so we try the above version that works at scab and also set SCALE_HIGH
  #$TIMEOUT_COMMAND 900 solve-field  --objs 1000 --depth 10,20,30-50  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  # the above 30-50 parameter is to handle the situation when there are many saturated stars that bleed out so their position cannot be determined well
  #$TIMEOUT_COMMAND 900 solve-field  --objs 1000 --depth 10,20,30  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  # has to be 900, otherwise cannot solve ../individual_images_test/J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit resulting in test error SAIRC600B000
  #$TIMEOUT_COMMAND 600 solve-field  --objs 1000 --depth 1-10,11-20,21-30  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  #$TIMEOUT_COMMAND 600 solve-field --objs 1000 --depth 10,20,30,40,50  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  #
  # The if below doesn't work, dont know why
  #if [ $? -ge 130 ];then
  # # Exit if solve-field was killed by user
  # exit 1
  #fi
  if [ $? -ne 0 ];then
   echo "ERROR running solve-field locally. Retrying with a remote plate-solve server."
   ASTROMETRYNET_LOCAL_OR_REMOTE="remote"
   # need the awk post-processing for curl request to work
   IMAGE_SIZE=`"$VAST_PATH"lib/astrometry/get_image_dimentions $FITSFILE | awk '{print "width="$2" -F hight="$4}'`
  else
   # solve-field didn't crash
   if [ ! -f out$$.solved ];then
    echo "The field could not be sloved :("
    continue
    #exit 1
   fi
   if [ -s out$$.wcs ];then
    echo -n "Inserting WCS header...  "
    if [[ "$FITSFILE" -ef "$BASENAME_FITSFILE" ]];then
     echo "Not creating a local copy of the FITS image as the input image is already in the current directory. The input image will be modified!"
    else
     cp -v "$FITSFILE" "$BASENAME_FITSFILE"
     if [ $? -ne 0 ];then
      echo "ERROR: cannot copy $FITSFILE to $BASENAME_FITSFILE"
      exit 1
     fi
    fi
    # Strip the input image from the old WCS header (if any)
    lib/astrometry/strip_wcs_keywords "$BASENAME_FITSFILE" 2>&1
    if [ $? -ne 0 ];then
     echo "ERROR: running lib/astrometry/strip_wcs_keywords $BASENAME_FITSFILE"
     exit 1
    fi
    # Double-check that the new WCS header is still here
    ls -lh out$$.wcs "$BASENAME_FITSFILE"
    # Insert the new WCS header from out$$.wcs
    echo -n "Inserting WCS header (1st iteration local)...  "
    "$VAST_PATH"lib/astrometry/insert_wcs_header out$$.wcs "$BASENAME_FITSFILE" 2>&1
    if [ $? -ne 0 ];then
     # This is a bad one, just exit
     echo " ERROR inserting WCS header in $FITSFILE !!! Aborting further actions! "
     WCS_IMAGE_TO_CHECK="wcs_$BASENAME_FITSFILE"
     WCS_IMAGE_TO_CHECK="${WCS_IMAGE_TO_CHECK/wcs_wcs_/wcs_}"
     if [ -f "$WCS_IMAGE_TO_CHECK" ];then
      echo "The output file $WCS_IMAGE_TO_CHECK exist"
      if [ -s "$WCS_IMAGE_TO_CHECK" ];then
       echo "#### Header of the existing image $WCS_IMAGE_TO_CHECK ####"
       util/listhead $WCS_IMAGE_TO_CHECK
       echo "#### end of header of the existing image $WCS_IMAGE_TO_CHECK ####"
      else
       echo "The output file $WCS_IMAGE_TO_CHECK is empty!"
      fi
     fi
     echo "#### Header we wanted to insert ####"
     util/listhead out$$.wcs
     echo "#### end of header we wanted to insert ####"
     exit 1
    else   
     ERROR_STATUS=0
     echo "done"
     echo "The WCS header appears to be added with no errors in $FITSFILE ($BASENAME_FITSFILE)"
     # Insert VaST headers for debugging
     if [ -z "$PLATE_SOLVE_SERVER" ];then
      PLATE_SOLVE_SERVER="local"
     fi
     "$VAST_PATH"util/modhead wcs_"$BASENAME_FITSFILE" VAST001 $(basename $0)" / VaST script name"
     "$VAST_PATH"util/modhead wcs_"$BASENAME_FITSFILE" VAST002 "$ASTROMETRYNET_LOCAL_OR_REMOTE / ASTROMETRYNET_LOCAL_OR_REMOTE"
     "$VAST_PATH"util/modhead wcs_"$BASENAME_FITSFILE" VAST003 "$PLATE_SOLVE_SERVER / PLATE_SOLVE_SERVER"
     "$VAST_PATH"util/modhead wcs_"$BASENAME_FITSFILE" VAST004 "iteration01 / astrometry.net run"
     #
    fi
    #
    # clean up
    #rm -f "$BASENAME_FITSFILE" out$$.wcs out$$.axy out$$.corr out$$.match out$$.rdls out$$.solved out$$.xyls out$$-indx.xyls
    # note that we will need "$BASENAME_FITSFILE" for the second iteration
    rm -f out$$.wcs out$$.axy out$$.corr out$$.match out$$.rdls out$$.solved out$$-indx.xyls
    ############
    # Attempt the second iteration with restricted parameters
    RADECCOMMAND=`"$VAST_PATH"util/fov_of_wcs_calibrated_image.sh wcs_"$BASENAME_FITSFILE" | grep 'Image center:' | awk '{print "--ra "$3" --dec "$4}'`
    FOV_MAJORAXIS_DEG=`"$VAST_PATH"util/fov_of_wcs_calibrated_image.sh wcs_"$BASENAME_FITSFILE" | grep 'Image size:' | awk '{print $3}' | sed "s:'::g" | sed "s:x: :g"  | awk '{if ( $1 < $2 ) print $2/60 ;else print $1/60 }'`
    IMAGE_SCALE_ARCSECPIX=`"$VAST_PATH"util/fov_of_wcs_calibrated_image.sh wcs_"$BASENAME_FITSFILE" | grep 'Image scale:' | awk '{print $3}' | awk -F '"' '{print $1}'`
    IMAGE_SCALE_ARCSECPIX_LOW=`echo "$IMAGE_SCALE_ARCSECPIX" | awk '{printf "%f",0.95*$1}'`
    IMAGE_SCALE_ARCSECPIX_HIGH=`echo "$IMAGE_SCALE_ARCSECPIX" | awk '{printf "%f",1.05*$1}'`
    # We need to add an additional parameter '--uniformize 0' for the newer version of Astrometry.net code
    # --uniformize <int> select sources uniformly using roughly this many boxes (0=disable; default 10)
    # as the quality of the solution degrades for wide-field images when this feature is enabled.
    # Test case: ../NMW-STL__plate_solve_failure_test/second_epoch_images/025_2023-8-20_20-51-4_003.fts
    # '--quad-size-max 0.25' seems to be useful for wide-field distorted images
    QUAD_SIZE_MAX_OPTION=""
    TEST=$(echo "$FOV_MAJORAXIS_DEG" | awk '{if ( $1 > 10.0 ) print 1 ;else print 0 }')
    if [ $TEST -eq 1 ];then
     #QUAD_SIZE_MAX_OPTION="--quad-size-max 0.25"
     QUAD_SIZE_MAX_OPTION="--quad-size-max 0.25 --uniformize 0"
    fi
    #RADECCOMMAND="$QUAD_SIZE_MAX_OPTION --crpix-center --uniformize 0 $RADECCOMMAND --radius $FOV_MAJORAXIS_DEG --scale-low $IMAGE_SCALE_ARCSECPIX_LOW --scale-high $IMAGE_SCALE_ARCSECPIX_HIGH --scale-units arcsecperpix"
    RADECCOMMAND="$QUAD_SIZE_MAX_OPTION --crpix-center $RADECCOMMAND --radius $FOV_MAJORAXIS_DEG --scale-low $IMAGE_SCALE_ARCSECPIX_LOW --scale-high $IMAGE_SCALE_ARCSECPIX_HIGH --scale-units arcsecperpix"
    #`"$VAST_PATH"lib/find_timeout_command.sh` 600 solve-field out$$.xyls $IMAGE_SIZE $RADECCOMMAND --objs 10000 --depth 10,20,30,40,50  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER 
    #$TIMEOUT_COMMAND 600 solve-field out$$.xyls $IMAGE_SIZE $RADECCOMMAND --objs 10000 --depth 10,20,30,40,50  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER 
    # Can't use --tweak-order 3 as tweaks are unreliable for wide-field images when using starlists rather than images - see below.
    $TIMEOUT_COMMAND 600 solve-field out$$.xyls $IMAGE_SIZE $RADECCOMMAND --objs 10000 --depth 100  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER  #--tweak-order 3
    if [ $? -ne 0 ];then
     echo "ERROR running the second iteration of solve-field on $BASENAME_FITSFILE"
     exit 1
    fi
    if [ ! -f out$$.solved ];then
     echo "The second iteration of solve-field failed to solve the field for $BASENAME_FITSFILE"
     exit 1
    fi
    if [ ! -f out$$.wcs ];then
     echo "The second iteration of solve-field failed to produce out$$.wcs for $BASENAME_FITSFILE"
     exit 1
    fi
    if [ ! -s out$$.wcs ];then
     echo "The second iteration of solve-field produced an empty out$$.wcs for $BASENAME_FITSFILE"
     exit 1
    fi
    # remove the plate-solved image produced by the 1st iteration
    rm -f wcs_"$BASENAME_FITSFILE"
    # We probably not need to strip_wcs_keywords again from $BASENAME_FITSFILE, but just in case
    # Strip the input image from the old WCS header (if any)
    lib/astrometry/strip_wcs_keywords "$BASENAME_FITSFILE" 2>&1
    if [ $? -ne 0 ];then
     echo "ERROR at 2nd iteration: running lib/astrometry/strip_wcs_keywords $BASENAME_FITSFILE"
     exit 1
    fi
    # Double-check that the new WCS header is still here
    ls -lh out$$.wcs "$BASENAME_FITSFILE"
    # Insert the new WCS header from out$$.wcs
    echo -n "Inserting WCS header (2nd iteration local)...  "
    "$VAST_PATH"lib/astrometry/insert_wcs_header out$$.wcs "$BASENAME_FITSFILE" 2>&1
    if [ $? -ne 0 ];then
     # This is a bad one, just exit
     echo " ERROR inserting WCS header! Aborting further actions! "
     WCS_IMAGE_TO_CHECK="wcs_$BASENAME_FITSFILE"
     WCS_IMAGE_TO_CHECK="${WCS_IMAGE_TO_CHECK/wcs_wcs_/wcs_}"
     if [ -f "$WCS_IMAGE_TO_CHECK" ];then
      echo "The output file $WCS_IMAGE_TO_CHECK exist"
      if [ -s "$WCS_IMAGE_TO_CHECK" ];then
       echo "#### Header of the existing image $WCS_IMAGE_TO_CHECK (2nd iteration) ####"
       util/listhead $WCS_IMAGE_TO_CHECK
       echo "#### end of eader of the existing image $WCS_IMAGE_TO_CHECK (2nd iteration) ####"
      else
       echo "The output file $WCS_IMAGE_TO_CHECK is empty!"
      fi
     fi
     echo "#### Header we wanted to insert (2nd iteration) ####"
     util/listhead out$$.wcs
     echo "#### end of header we wanted to insert (2nd iteration) ####"
     exit 1
    else   
     ERROR_STATUS=0
     echo "The WCS header appears to be added with no errors."
     # Insert VaST headers for debugging
     "$VAST_PATH"util/modhead wcs_"$BASENAME_FITSFILE" VAST001 $(basename $0)" / VaST script name"
     "$VAST_PATH"util/modhead wcs_"$BASENAME_FITSFILE" VAST002 "$ASTROMETRYNET_LOCAL_OR_REMOTE / ASTROMETRYNET_LOCAL_OR_REMOTE"
     "$VAST_PATH"util/modhead wcs_"$BASENAME_FITSFILE" VAST003 "$PLATE_SOLVE_SERVER / PLATE_SOLVE_SERVER"
     "$VAST_PATH"util/modhead wcs_"$BASENAME_FITSFILE" VAST004 "iteration02 / astrometry.net run"
     #
     ############
     ############
     # An absolute desperate move to get reliable astrometry with very wide-field images like STL
     # Just run solve-field on the _image_
     #
     # As Dustin Lang explains here https://groups.google.com/g/astrometry/c/1Pw6WjGmJD8
     # "At the moment, it "tweaks" using only the stars in the index containing the matching quad. 
     #  This means that for large quads (large in the image), there are few stars so the tweak might not be very good. 
     #  However, if you re-run solve-field using the "--verify" option on the wcs file you get, it will then check that WCS file against ALL the index files,
     # and tune up the best one.  Doing that can often produce improved results."
     #
     #TEST=$(echo "$FOV_MAJORAXIS_DEG" | awk '{if ( $1 > 10.0 ) print 1 ;else print 0 }')
     TEST=$(echo "$FOV_MAJORAXIS_DEG" | awk '{if ( $1 > 5.0 ) print 1 ;else print 0 }')
     if [ $TEST -eq 1 ];then
      #if fasle ;then
      echo "The field of view is large: we'll try to run Astromety.net code on the image itself rather than a star list"
      AN_WCS_BASE=wcs_"$BASENAME_FITSFILE"
      AN_WCS_BASE="${AN_WCS_BASE%.*}"
      AN_NEW_FITS_WITH_UPDATED_WCS="$AN_WCS_BASE".new
      AN_WCSONLY_FILE="$AN_WCS_BASE".wcs
      AN_AXY_FILE="$AN_WCS_BASE".axy
      echo wcs_"$BASENAME_FITSFILE" | solve-field --files-on-stdin --fits-image --overwrite --no-plots --corr none --index-xyls none --match none --rdls none --solved none  --nsigma 10  --tweak-order 3
      if [ $? -eq 0 ];then
       # if there is an output file - replace the original with it
       if [ -s "$AN_NEW_FITS_WITH_UPDATED_WCS" ];then
        mv -v "$AN_NEW_FITS_WITH_UPDATED_WCS" wcs_"$BASENAME_FITSFILE"
       fi
      fi # if [ $? -eq 0 ];then
      # cleanup
      for AN_TMP_FILE_TO_REMOVE in "$AN_NEW_FITS_WITH_UPDATED_WCS" "$AN_WCSONLY_FILE" "$AN_AXY_FILE" ;do
       if [ -f "$AN_TMP_FILE_TO_REMOVE" ];then
        rm -f "$AN_TMP_FILE_TO_REMOVE"
       fi
      done
     fi
     ############
    fi
    # clean up
    rm -f "$BASENAME_FITSFILE" out$$.wcs out$$.axy out$$.corr out$$.match out$$.rdls out$$.solved out$$.xyls out$$-indx.xyls
   else
    if [ -f out$$.wcs ];then
     echo "ERROR: out$$.wcs is empty"
    else
     echo "ERROR: cannot find out$$.wcs "
    fi
    ERROR_STATUS=2
   fi
   # Clean-up
   rm -f out$$.axy out$$.xyls
   # end of clean-up
  fi # solve-field didn't crash
 fi # if [ "$ASTROMETRYNET_LOCAL_OR_REMOTE" = "local" ];then
 ############################################################################
 
 if [ "$ASTROMETRYNET_LOCAL_OR_REMOTE" = "remote" ];then
 
  echo "Local astrometry not available or failed, trying remote servers..."
  
  # NOW we check for remote server availability - only when we actually need remote servers
  if ! setup_remote_astrometry; then
   echo "ERROR: Cannot reach any remote plate solve servers"
   ERROR_STATUS=2
   break
  fi
 
  echo "Using the remote server with Astrometry.net code"
 
  # Web-based processing
  while true ;do
   #################### Check if we want to retry with another server ####################
   if [ $ERROR_STATUS -eq 2 ];then
    echo "Will retry with another plate-solve server"
    # Remove the current server from the list
    PLATE_SOLVE_SERVERS=${PLATE_SOLVE_SERVERS//$PLATE_SOLVE_SERVER/}
    # Pick the next server in line
    PLATE_SOLVE_SERVER=`echo $PLATE_SOLVE_SERVERS | awk '{print $1}'`
    # break if there are no more servers left
    if [ "$PLATE_SOLVE_SERVER" = "" ];then
     echo "No more plate-solve servers left"
     break
    fi
   fi
   #################### Start of single-server communication ####################
   echo -e "Submitting the plates solving job to the server \033[01;34m $PLATE_SOLVE_SERVER \033[00m"
   echo -e "This may take \033[01;31mup to a few minutes\033[00m..."
   if [ ! -f out$$.xyls ];then
    echo "ERROR: the file out$$.xyls is lost somewhere on the way!"
    exit 1
   fi
   
   # Moved here as IMAGE_SIZE without awk postprocessing is defined and used above
   IMAGE_SIZE=`"$VAST_PATH"lib/astrometry/get_image_dimentions $FITSFILE | awk '{print "width="$2" -F hight="$4}'`
   
   echo "Plate solving parameters: -F fov=$TRIAL_FIELD_OF_VIEW_ARCMIN -F $IMAGE_SIZE http://$PLATE_SOLVE_SERVER/cgi-bin/process_file/process_sextractor_list.py"
   
   # Note that the timeout is also enforced at the server side
   $TIMEOUT_COMMAND 600 $CURL -F file=@out$$.xyls -F submit="Upload Image" -F fov=$TRIAL_FIELD_OF_VIEW_ARCMIN -F $IMAGE_SIZE "http://$PLATE_SOLVE_SERVER/cgi-bin/process_file/process_sextractor_list.py" --user vast48:khyzbaojMhztNkWd > server_reply$$.html
   CURL_EXIT_CODE=$?
   cp -v out$$.xyls test.xyls
   echo "$CURL -F file=@test.xyls -F submit='Upload Image' -F fov=$TRIAL_FIELD_OF_VIEW_ARCMIN -F $IMAGE_SIZE "http://$PLATE_SOLVE_SERVER/cgi-bin/process_file/process_sextractor_list.py" --user vast48:khyzbaojMhztNkWd > server_reply$$.html" > test.txt
   # A reminder from 'man timout':
   # If the command times out, and --preserve-status is not set, then exit with status 124.
   # Otherwise, exit with  the  status of  COMMAND.
   if [ $CURL_EXIT_CODE -eq 124 ];then
    # the command has timed out 
    # actually, the course of actions is exactly the same as with any other error
    echo "Communication with the plate solve server  $PLATE_SOLVE_SERVER  has timed out!"
    ERROR_STATUS=2
    continue
   fi
   if [ $CURL_EXIT_CODE -ne 0 ];then
    # something else went wrong
    echo "An ERROR has occured while uploading the star list to the server $PLATE_SOLVE_SERVER !"
    echo "The failed command (see test.txt): "
    cat test.txt
    ERROR_STATUS=2
    continue
   fi
   if [ ! -s server_reply$$.html ];then
    echo "ERROR: the server reply is empty!"
    ERROR_STATUS=2
    continue
   fi
   if grep -q -e  '404 Not Found' -e '500 Internal Server Error' server_reply$$.html ;then
    echo "ERROR in $0: plate-solve server reports an error!"
    echo "#### Server reply listing ####"
    cat server_reply$$.html
    echo "##############################"
    ERROR_STATUS=2
    continue    
   fi
   EXPECTED_WCS_HEAD_URL=`grep WCS_HEADER_FILE= server_reply$$.html | awk '{print $2}'`
   if [ "$EXPECTED_WCS_HEAD_URL" = "" ];then
    echo "ERROR in $0: cannot parse the plate-solve server reply to get 'WCS_HEADER_FILE=' line!"
    echo "#### Server reply listing ####"
    cat server_reply$$.html
    echo "##############################"
    ERROR_STATUS=2
    continue
   fi
   echo "#### Plate solution log ####"
   SOLVE_PROGRAM_LOG_URL=${EXPECTED_WCS_HEAD_URL//out.wcs/program.log}
   #`"$VAST_PATH"lib/find_timeout_command.sh` 300 $CURL "$SOLVE_PROGRAM_LOG_URL" --user vast48:khyzbaojMhztNkWd
   $TIMEOUT_COMMAND 300 $CURL "$SOLVE_PROGRAM_LOG_URL" --user vast48:khyzbaojMhztNkWd
   if [ $? != 0 ];then
    echo "ERROR: getting processing log from the server $PLATE_SOLVE_SERVER"
    ERROR_STATUS=2
    continue
   fi
   echo "############################"
   SOLVE_FILE_URL=${EXPECTED_WCS_HEAD_URL//out.wcs/out.solved}
   #`"$VAST_PATH"lib/find_timeout_command.sh` 300 $CURL "$SOLVE_FILE_URL" --user vast48:khyzbaojMhztNkWd 2>/dev/null |grep "404 Not Found" >/dev/null
   $TIMEOUT_COMMAND 300 $CURL "$SOLVE_FILE_URL" --user vast48:khyzbaojMhztNkWd 2>/dev/null | grep '404 Not Found' >/dev/null
   # Nope, this interfers with the if statement below
   #if [ $? -ge 130 ];then
   # # Exit if the process is killed by user
   # exit 1
   #fi
   if [ $? -eq 1 ];then
    echo -e "Field \033[01;32mSOLVED\033[00m =)"
    rm -f out.solved
    echo -n "Downloading WCS header...  "
    #`"$VAST_PATH"lib/find_timeout_command.sh` 300 $CURL "$EXPECTED_WCS_HEAD_URL" -o out$$.wcs --user vast48:khyzbaojMhztNkWd &>/dev/null  && echo "done"
    $TIMEOUT_COMMAND 300 $CURL "$EXPECTED_WCS_HEAD_URL" -o out$$.wcs --user vast48:khyzbaojMhztNkWd &>/dev/null 
    CURL_EXIT_CODE=$? 
    # This one should not interfere with the if below
    if [ $CURL_EXIT_CODE -ge 130 ];then
     # Exit if the process is killed by user
     exit 1
    fi
    if [ $CURL_EXIT_CODE -ne 0 ];then
     echo "The curl exit code was $CURL_EXIT_CODE
Retrying..."
     sleep 3
     $TIMEOUT_COMMAND 300 $CURL "$EXPECTED_WCS_HEAD_URL" -o out$$.wcs --user vast48:khyzbaojMhztNkWd &>/dev/null
     CURL_EXIT_CODE=$? 
     # This one should not interfere with the if below
     if [ $CURL_EXIT_CODE -ge 130 ];then
      # Exit if the process is killed by user
      exit 1
     fi
     if [ $CURL_EXIT_CODE -ne 0 ];then
      echo "The curl exit code is still $CURL_EXIT_CODE"
      ERROR_STATUS=2
     else
      echo "done"
     fi
    else
     echo "done"
    fi
    if [ -s out$$.wcs ];then
     cp -v $FITSFILE "$BASENAME_FITSFILE"
     # Strip the input image from the old WCS header (if any)
     lib/astrometry/strip_wcs_keywords "$BASENAME_FITSFILE" 2>&1
     if [ $? -ne 0 ];then
      echo "ERROR at 2nd iteration: running lib/astrometry/strip_wcs_keywords $BASENAME_FITSFILE"
      exit 1
     fi
     # Double-check that the new WCS header is still here
     ls -lh out$$.wcs "$BASENAME_FITSFILE"
     # Insert the new WCS header from out$$.wcs
     echo -n "Inserting WCS header in $BASENAME_FITSFILE (remote) ...  "
     "$VAST_PATH"lib/astrometry/insert_wcs_header out$$.wcs "$BASENAME_FITSFILE" 2>&1
     if [ $? -ne 0 ];then
      # This is a bad one, just exit
      echo " ERROR inserting WCS header in $BASENAME_FITSFILE ! Aborting further actions! "
      WCS_IMAGE_TO_CHECK="wcs_$BASENAME_FITSFILE"
      WCS_IMAGE_TO_CHECK="${WCS_IMAGE_TO_CHECK/wcs_wcs_/wcs_}"
      if [ -f "$WCS_IMAGE_TO_CHECK" ];then
       echo "The output file $WCS_IMAGE_TO_CHECK exist"
       if [ -s "$WCS_IMAGE_TO_CHECK" ];then
        echo "#### Header of the existing image $WCS_IMAGE_TO_CHECK ####"
        util/listhead $WCS_IMAGE_TO_CHECK
        echo "#### end of header of the existing image $WCS_IMAGE_TO_CHECK ####"
       else
        echo "The output file $WCS_IMAGE_TO_CHECK is empty!"
       fi
      fi
      echo "#### Header we wanted to insert ####"
      util/listhead out$$.wcs
      echo "#### end of header we wanted to insert ####"
      exit 1
     else
      ERROR_STATUS=0
      echo "The WCS header appears to be added with no errors."
      # Insert VaST headers for debugging
      "$VAST_PATH"util/modhead wcs_"$BASENAME_FITSFILE" VAST001 $(basename $0)" / VaST script name"
      "$VAST_PATH"util/modhead wcs_"$BASENAME_FITSFILE" VAST002 "$ASTROMETRYNET_LOCAL_OR_REMOTE / ASTROMETRYNET_LOCAL_OR_REMOTE"
      "$VAST_PATH"util/modhead wcs_"$BASENAME_FITSFILE" VAST003 "$PLATE_SOLVE_SERVER / PLATE_SOLVE_SERVER"
      "$VAST_PATH"util/modhead wcs_"$BASENAME_FITSFILE" VAST004 "iteration01 / astrometry.net run"
      #     
     fi
     #
     #
     # The output plate-solved image wcs_"$BASENAME_FITSFILE" will be produced by lib/astrometry/insert_wcs_header
     for FILE_TO_REMOVE in "$BASENAME_FITSFILE" out$$.wcs ;do
      if [ -f "$FILE_TO_REMOVE" ];then
       rm -f "$FILE_TO_REMOVE"
      else
       echo "Hmmm, the file $FILE_TO_REMOVE that we wanted to remove does not exist!"
      fi
     done
    else
     echo "ERROR: cannot download out.wcs for $BASENAME_FITSFILE"
     ERROR_STATUS=2
     continue
    fi
   else
    echo -e "Sadly, the field was \033[01;31mNOT SOLVED\033[00m. :("
    echo "Try to set a smaller field of view size, for example:  $0 $1 " `echo "$TRIAL_FIELD_OF_VIEW_ARCMIN" | awk '{printf "%.1f", $1/2}'`
    ERROR_STATUS=1
   fi
   # At this point we should remove the completed job from the server
   SERVER_JOB_ID=`grep "Job ID:" server_reply$$.html |head -n1 |awk '{print $3}'`
   if [ "$SERVER_JOB_ID" != "" ];then
    echo "Sending request to remove job $SERVER_JOB_ID from the server...  "
    VaSTID="XGkbtHTGfTPVLrZLBdtIDPzGAEAjaZWW"
    # Web-based processing - remove completed plate-solveing job from the server
    #`"$VAST_PATH"lib/find_timeout_command.sh` 300 $CURL -F JobID="$SERVER_JOB_ID" -F VaSTID=$VaSTID "http://$PLATE_SOLVE_SERVER/cgi-bin/process_file/remove_job.py" --user vast48:khyzbaojMhztNkWd 
    $TIMEOUT_COMMAND 300 $CURL -F JobID="$SERVER_JOB_ID" -F VaSTID=$VaSTID "http://$PLATE_SOLVE_SERVER/cgi-bin/process_file/remove_job.py" --user vast48:khyzbaojMhztNkWd 
    if [ $? -ne 0 ];then
     echo "Hmm... Some error?"
    fi
   else
    echo "ERROR: cannot get Job ID from server_reply$$.html"
    cat server_reply$$.html
   fi
   rm -f server_reply$$.html #out$$.xyls
   #################### End of single-server communication ####################
   # Check exit conditions
   if [ $ERROR_STATUS -eq 0 ];then
    break
   fi
   if [ $ERROR_STATUS -eq 1 ];then
    break
   fi
   ############################################################################
  done
 fi
 if [ "$ASTROMETRYNET_LOCAL_OR_REMOTE" != "remote" ] && [ "$ASTROMETRYNET_LOCAL_OR_REMOTE" != "local" ] ;then
  echo "ERROR: the variable ASTROMETRYNET_LOCAL_OR_REMOTE should be set to 'remote' or 'local', instead ASTROMETRYNET_LOCAL_OR_REMOTE=$ASTROMETRYNET_LOCAL_OR_REMOTE"
  exit 1
 fi # if [ "$ASTROMETRYNET_LOCAL_OR_REMOTE" = "remote" ];then
 
 
 # if the wcs-calibrated image is created one way or another...
 if [ -f $WCS_IMAGE_NAME ];then
  # Success
  break
 fi
 
 done # for TRIAL_FIELD_OF_VIEW_ARCMIN in ...

 ########## Special clean-up for multiple tries with a remote server
 if [ -f out$$.xyls ];then
  #cp out$$.xyls /tmp
  rm -f out$$.xyls
 fi

else
 echo "WCS-calibrated image found: $WCS_IMAGE_NAME"
fi

# Check if the wcs-solved image could not be created
if [ ! -f "$WCS_IMAGE_NAME" ];then
 # Failure
 echo "The output plate-solved image $WCS_IMAGE_NAME does not exist!"
 exit 1
fi

# Check if the wcs-solved image could not be created
if [ ! -s "$WCS_IMAGE_NAME" ];then
 # Failure
 echo "The output plate-solved image $WCS_IMAGE_NAME exist, but its empty!"
 exit 1
fi

# Check for errors on previous steps
if [ $ERROR_STATUS -ne 0 ];then
 echo "ERROR: $ERROR_STATUS"
 exit $ERROR_STATUS
fi

# Check if a catalog is needed
if [ "$START_NAME" != "wcs_image_nocatalog.sh" ];then
 
 # At this point, we should have a WCS calibrated image named $WCS_IMAGE_NAME
 # Now create the catalog needed for star identification and UCAC5 matching
 echo "Checking if the catalog $SEXTRACTOR_CATALOG_NAME corresponding to the image $WCS_IMAGE_NAME alredy exist and is non-empty..."
 if [ ! -s "$SEXTRACTOR_CATALOG_NAME" ];then
  echo "Catalog $SEXTRACTOR_CATALOG_NAME corresponding to the image $WCS_IMAGE_NAME was not found."
  # Try to generate the catalog without re-running SExtractor
  "$VAST_PATH"lib/reformat_existing_sextractor_catalog_according_to_wcsparam.sh "$FITSFILE" "$WCS_IMAGE_NAME" "$SEXTRACTOR_CATALOG_NAME"
  if [ $? -ne 0 ];then
   echo "lib/reformat_existing_sextractor_catalog_according_to_wcsparam.sh did not work. Re-running SExtractor..." 1>&2
   echo "Running command '$SEXTRACTOR' from $0"
   echo $SEXTRACTOR -c "$VAST_PATH"`grep "SExtractor parameter file:" "$VAST_PATH"vast_summary.log |awk '{print $4}'` -PARAMETERS_NAME "$VAST_PATH"wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME -PHOT_APERTURES `"$VAST_PATH"lib/autodetect_aperture_main $WCS_IMAGE_NAME 2>/dev/null` `"$VAST_PATH"lib/guess_saturation_limit_main $WCS_IMAGE_NAME 2>/dev/null`  $WCS_IMAGE_NAME 1>&2
   $SEXTRACTOR -c "$VAST_PATH"default.sex -PARAMETERS_NAME "$VAST_PATH"wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME -PHOT_APERTURES `"$VAST_PATH"lib/autodetect_aperture_main $WCS_IMAGE_NAME 2>/dev/null` `"$VAST_PATH"lib/guess_saturation_limit_main $WCS_IMAGE_NAME 2>/dev/null`  $WCS_IMAGE_NAME && echo "ok"
  fi
  echo "Catalog $SEXTRACTOR_CATALOG_NAME corresponding to the image $WCS_IMAGE_NAME created."
  "$VAST_PATH"lib/correct_sextractor_wcs_catalog_using_xy2sky.sh "$WCS_IMAGE_NAME" "$SEXTRACTOR_CATALOG_NAME"
 else
  echo "Catalog $SEXTRACTOR_CATALOG_NAME corresponding to the image $WCS_IMAGE_NAME found." 
  
  # Check if the catalog looks big enough
  TEST=`cat $SEXTRACTOR_CATALOG_NAME | wc -l`
  if [ $TEST -lt 100 ];then
   echo "The catalog seems suspiciously small (only $TEST lines), re-generating the catalog with SExtractor..."
   $SEXTRACTOR -c "$VAST_PATH"`grep "SExtractor parameter file:" "$VAST_PATH"vast_summary.log |awk '{print $4}'` -PARAMETERS_NAME "$VAST_PATH"wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME -PHOT_APERTURES `"$VAST_PATH"lib/autodetect_aperture_main $WCS_IMAGE_NAME 2>/dev/null` `"$VAST_PATH"lib/guess_saturation_limit_main $WCS_IMAGE_NAME 2>/dev/null`  $WCS_IMAGE_NAME && echo "ok"
   if [ -f $SEXTRACTOR_CATALOG_NAME ];then
    echo "Catalog $SEXTRACTOR_CATALOG_NAME corresponding to the image $WCS_IMAGE_NAME created."
    "$VAST_PATH"lib/correct_sextractor_wcs_catalog_using_xy2sky.sh "$WCS_IMAGE_NAME" "$SEXTRACTOR_CATALOG_NAME"
   else
    echo "ERROR running SExtractor on $WCS_IMAGE_NAME to create catalog $SEXTRACTOR_CATALOG_NAME"
   fi
  fi
  
  # Checking the catalog format
  TEST=`head -n1 "$SEXTRACTOR_CATALOG_NAME" | awk '{print $6}'`
  if [ "$TEST" = "" ];then
   echo "The catalog is in the old format, re-generating the catalog..."
   $SEXTRACTOR -c "$VAST_PATH"`grep "SExtractor parameter file:" "$VAST_PATH"vast_summary.log |awk '{print $4}'` -PARAMETERS_NAME "$VAST_PATH"wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME -PHOT_APERTURES `"$VAST_PATH"lib/autodetect_aperture_main $WCS_IMAGE_NAME 2>/dev/null` `"$VAST_PATH"lib/guess_saturation_limit_main $WCS_IMAGE_NAME 2>/dev/null`  $WCS_IMAGE_NAME && echo "ok"
   if [ -f "$SEXTRACTOR_CATALOG_NAME" ];then
    echo "Catalog $SEXTRACTOR_CATALOG_NAME corresponding to the image $WCS_IMAGE_NAME created."
    "$VAST_PATH"lib/correct_sextractor_wcs_catalog_using_xy2sky.sh "$WCS_IMAGE_NAME" "$SEXTRACTOR_CATALOG_NAME"
   else
    echo "ERROR running SExtractor on $WCS_IMAGE_NAME to create catalog $SEXTRACTOR_CATALOG_NAME"
   fi
  else
   echo "The catalog is in the new format, as expected."  
  fi
  
 fi
fi # if [ "$START_NAME" != "wcs_image_nocatalog.sh" ];then

# If we are in the star identification mode - identify the star!
if [ "$START_NAME" != "wcs_image_calibration.sh" ] && [ "$START_NAME" != "wcs_image_nocatalog.sh" ] ;then
 
 # Check if ucac5 plate solution is available
 UCAC5_SOLUTION_NAME="$SEXTRACTOR_CATALOG_NAME".ucac5
 if [ ! -f "$UCAC5_SOLUTION_NAME" ];then
  ############################################################################
  # Check for a local copy of UCAC5
  # (this is specific to our in-house setup)
  #
  # Reminder to kirx: /mnt/usb/UCAC5 -- local, /dataN/kirx/UCAC5 -- scan, /dataX/kirx/UCAC5 -- vast
  # /data/cgi-bin/unmw/uploads/UCAC5 -- kadar2
  #
  if [ ! -d lib/catalogs/ucac5 ];then
   for TEST_THIS_DIR in /mnt/usb/UCAC5 /dataN/kirx/UCAC5 /dataX/kirx/UCAC5 /home/kirx/UCAC5 "$HOME"/UCAC5 ../UCAC5 /data/cgi-bin/unmw/uploads/UCAC5 ;do
    if [ -d "$TEST_THIS_DIR" ];then
     ln -s "$TEST_THIS_DIR" lib/catalogs/ucac5
     echo "Linking the local copy of UCAC5 from $TEST_THIS_DIR"
     echo "Linking the local copy of UCAC5 from $TEST_THIS_DIR" >> transient_factory_test31.txt
     break
    fi
   done
  fi
  ############################################################################
  echo "Performing plate solution with UCAC5..."
  # If this is not the reference image - do not do the slow VizieR APASS search!
  REFERENCE_IMAGE=$(cat "$VAST_PATH"vast_summary.log |grep "Ref.  image:" | awk '{print $6}')
  BASENAME_REFERENCE_IMAGE=$(basename $REFERENCE_IMAGE)
  TEST_SUBSTRING="$BASENAME_REFERENCE_IMAGE"
  TEST_SUBSTRING="${TEST_SUBSTRING:0:4}"
  if [ "$TEST_SUBSTRING" = "wcs_" ];then
   WCS_REFERENCE_IMAGE_NAME="$BASENAME_REFERENCE_IMAGE"
  else
   WCS_REFERENCE_IMAGE_NAME=wcs_"$BASENAME_REFERENCE_IMAGE"
  fi
  if [ "$WCS_REFERENCE_IMAGE_NAME" = "$WCS_IMAGE_NAME" ];then
   echo "This is the reference image so we'll do the slow photometric catalog query"
   "$VAST_PATH"util/solve_plate_with_UCAC5 $WCS_IMAGE_NAME $FIELD_OF_VIEW_ARCMIN
   if [ $? -ne 0 ];then
    echo "ERROR matching the stars with UCAC5"
    exit 1
   fi
  else
   echo "This is not the reference image so we'll skip the slow photometric catalog query"
   "$VAST_PATH"util/solve_plate_with_UCAC5 --no_photometric_catalog $WCS_IMAGE_NAME $FIELD_OF_VIEW_ARCMIN
   if [ $? -ne 0 ];then
    echo "ERROR matching the stars with UCAC5"
    exit 1
   fi
  fi
  if [ ! -f $UCAC5_SOLUTION_NAME ];then
   echo "ERROR: cannot find the UCAC5 plate solution file $UCAC5_SOLUTION_NAME"
   exit 1
  fi
 else
  echo "Found the UCAC5 plate solution file $UCAC5_SOLUTION_NAME"
 fi

 STARNUM=$(basename $LIGHTCURVEFILE .dat)
 echo "Looking for a star near the position $X $Y (pix) in $UCAC5_SOLUTION_NAME ..."
  RADEC=$("$VAST_PATH"lib/find_star_in_wcs_catalog $X $Y < $UCAC5_SOLUTION_NAME)
  if [ $? -ne 0 ];then
   echo "ERROR searching for the target star in the WCS catalog $UCAC5_SOLUTION_NAME"
   exit 1
  fi
  echo " "
  echo "####### Catalog search for the star #######"
  echo "#########################################################################"
  echo "Star:   RA(J2000)   Dec(J2000)    X(pix)   Y(pix)   WCS_calibrated_image"
  ##################################################################################
  # Experimental feature: if you want to use spline correction for astrometry, uncomment
  # the following lines. The spline correction is useful for photographic plates
  # digitized using a flatbed scanner.
  ##################################################################################
  #RADEC_CORRECTED=`util/astrometric_correction.sh $SEXTRACTOR_CATALOG_NAME $RADEC`
  #RADEC=$RADEC_CORRECTED
  ##################################################################################
  #     00148  22:53:44.63 +16:09:08.1   283.894  280.149 wcs_3C454.3_R_20101127_0119.00027019.3C454.3.fts
  "$VAST_PATH"lib/deg2hms $RADEC &>/dev/null
  if [ $? -ne 0 ];then
   echo "ERROR parsing the coordinates string \"$RADEC\""
   exit 1
  fi
  echo ${STARNUM//out/" "} $("$VAST_PATH"lib/deg2hms $RADEC) $X $Y $WCS_IMAGE_NAME |awk '{printf "%s  %s %s  %8.3f %8.3f %s\n",$1,$2,$3,$4,$5,$6}'
  if [ "$START_NAME" = "identify_for_catalog.sh" ];then
   #rm -f tmp$$.cat
   exit 0
  fi
  echo " "
  if [ "$START_NAME" = "identify_transient.sh" ];then
   TEMP_FILE__SDWC_OUTPUT=$(mktemp 2>/dev/null || echo "tempilefallback_SDWC_OUTPUT_$$.tmp")
   # This will stop util/search_databases_with_curl.sh from using terminal colors
   "$VAST_PATH"util/search_databases_with_curl.sh $("$VAST_PATH"lib/deg2hms $RADEC) H > "$TEMP_FILE__SDWC_OUTPUT" &
   TEMP_FILE__MPCheck_OUTPUT=$(mktemp 2>/dev/null || echo "tempilefallback_MPCheck_OUTPUT_$$.tmp")
   UNCALIBRATED_IMAGE_NAME=$(echo ${WCS_IMAGE_NAME//"wcs_"/})
   # How did this work at all????
   DATEANDTIME=$(grep "$UNCALIBRATED_IMAGE_NAME" "$VAST_PATH"vast_image_details.log | head -n1 |awk '{print $2" "$3}')
   echo "$VAST_PATH"util/transients/MPCheck_v2.sh $("$VAST_PATH"lib/deg2hms $RADEC) $DATEANDTIME H
   #"$VAST_PATH"util/transients/MPCheck_v2.sh $("$VAST_PATH"lib/deg2hms $RADEC) $DATEANDTIME H > "$TEMP_FILE__MPCheck_OUTPUT" &
   "$VAST_PATH"util/transients/MPCheck_v2.sh $("$VAST_PATH"lib/deg2hms $RADEC) $(util/get_image_date $DATEANDTIME 2>&1 | grep 'MPC format ' | awk '{print $3" "$4" "$5}') H > "$TEMP_FILE__MPCheck_OUTPUT" &
   wait
   cat "$TEMP_FILE__SDWC_OUTPUT"
   cat "$TEMP_FILE__MPCheck_OUTPUT"
   rm -f "$TEMP_FILE__SDWC_OUTPUT" "$TEMP_FILE__MPCheck_OUTPUT"
  elif [ "$START_NAME" = "identify_justname.sh" ];then
   # awk -F'|' '{print $1}' is in case this will be a GCVS name
   # sed 's/^[ \t]*//;s/[ \t]*$//' is to remove the leading and trailing white spaces https://unix.stackexchange.com/questions/102008/how-do-i-trim-leading-and-trailing-whitespace-from-each-line-of-some-output
   # 's/^[[:space:]]*//;s/[[:space:]]*$//' is supposed to serve the same function
   #"$VAST_PATH"util/search_databases_with_curl.sh $("$VAST_PATH"lib/deg2hms $RADEC) | grep -v -e 'not found' -e 'Starting' -e 'Searching' | grep -v 'found' | tail -n1 | awk -F'|' '{print $1}' | sed 's/^[ \t]*//;s/[ \t]*$//'
   OUTPUTNAME=$("$VAST_PATH"util/search_databases_with_curl.sh $("$VAST_PATH"lib/deg2hms $RADEC) | grep -v -e 'not found' -e 'Starting' -e 'Searching' | grep -v 'found' | tail -n1 | awk -F'|' '{print $1}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
   if [ -z "$OUTPUTNAME" ];then
    OUTPUTNAME=$(util/search_databases_with_vizquery.sh $("$VAST_PATH"lib/deg2hms $RADEC) object 1 no_online_vsx 2>/dev/null | grep '\|' | grep 'object' | awk -F'|' '{print $2}')
   fi
   echo $OUTPUTNAME
   exit 0
  else
   "$VAST_PATH"util/search_databases_with_curl.sh $("$VAST_PATH"lib/deg2hms $RADEC)
   ### Give user a chance to interrupt the script
   if [ $? -ne 0 ];then
    exit 1
   fi
   ###
   echo " "
   "$VAST_PATH"util/search_databases_with_vizquery.sh $("$VAST_PATH"lib/deg2hms $RADEC) ${STARNUM//out/" "} $FIELD_OF_VIEW_ARCMIN
   ###################################
   # If identification failed, try to find this star on another image
   if [ $? -ne 0 ];then
    ####
    #if [ $? -ne 100 ];then
    # exit 1
    #fi
    ##
    echo -e "\n\nTrying to measure this star on another image... "
    tail -n1 "$LIGHTCURVEFILE" > lightcurve.tmp
    read JD MAG MERR X Y APP FITSFILE REST < lightcurve.tmp && echo "ok $FITSFILE"
    # Tesit if the original image is already a calibrated one
    TEST_SUBSTRING="$BASENAME_FITSFILE"
    TEST_SUBSTRING="${TEST_SUBSTRING:0:4}"
    #TEST_SUBSTRING=`expr substr $TEST_SUBSTRING  1 4`
    if [ "$TEST_SUBSTRING" = "wcs_" ];then
     cp -v $FITSFILE .
     WCS_IMAGE_NAME="$BASENAME_FITSFILE"
    else
     WCS_IMAGE_NAME=wcs_"$BASENAME_FITSFILE"
    fi
    SEXTRACTOR_CATALOG_NAME="$WCS_IMAGE_NAME".cat
    # Check if ucac5 plate solution is available
    UCAC5_SOLUTION_NAME="$SEXTRACTOR_CATALOG_NAME".ucac5
    if [ ! -f $UCAC5_SOLUTION_NAME ];then
     echo "Performing plate solution with UCAC5..."
     "$VAST_PATH"util/solve_plate_with_UCAC5 $FITSFILE $FIELD_OF_VIEW_ARCMIN
     ### Give user a chance to interrupt the script
     if [ $? -ne 0 ];then
      exit 1
     fi
     ###
    else
     echo "Found the UCAC5 plate solution file $UCAC5_SOLUTION_NAME"
    fi
    RADEC=$("$VAST_PATH"lib/find_star_in_wcs_catalog $X $Y < $UCAC5_SOLUTION_NAME)
    "$VAST_PATH"util/search_databases_with_curl.sh $("$VAST_PATH"lib/deg2hms $RADEC)
    ### Give user a chance to interrupt the script
    if [ $? -ne 0 ];then
     exit 1
    fi
    ###
    echo " "
    "$VAST_PATH"util/search_databases_with_vizquery.sh $("$VAST_PATH"lib/deg2hms $RADEC) ${STARNUM//out/" "}  $FIELD_OF_VIEW_ARCMIN
   fi 
   ###################################
  fi
  echo " "
  echo "#########################################################################"
  #rm -f tmp$$.cat 
 if [ "$START_NAME" = "identify.sh" ];then
  echo -e "The identified star is marked with the cross. Please compare the image with Aladin sky chart to make sure the identification is correct.\n"
  # Write Aladin script
  # old syntax
  #echo -n "rm all; load $WCS_IMAGE_NAME/;" `"$VAST_PATH"lib/deg2hms $RADEC`" ; zoom 5 arcmin ; stick ; get Aladin(POSSII J,JPEG)" `"$VAST_PATH"lib/deg2hms $RADEC`" ; get VizieR(USNO-B1)" `"$VAST_PATH"lib/deg2hms $RADEC`" 1'; get Simbad " `"$VAST_PATH"lib/deg2hms $RADEC`" 1'; get VizieR(2MASS)" `"$VAST_PATH"lib/deg2hms $RADEC`" 1' ;" > Aladin.script
  # new syntax
  RADEC_HMS=$("$VAST_PATH"lib/deg2hms $RADEC)
  echo -n "rm all; get hips(CDS/P/DSS2/color) $RADEC_HMS ; load $WCS_IMAGE_NAME/; $RADEC_HMS ; zoom 5 arcmin ; get VizieR(USNO-B1) $RADEC_HMS 1'; get Simbad $RADEC_HMS 1'; get VizieR(2MASS) $RADEC_HMS 1' ; get hips(CDS/I/350/gaiaedr3) $RADEC_HMS ; get VizieR(J/AJ/156/241/table4) 18:46:37.16 -12:38:49.7 1'" > Aladin.script
  # If the star is matched with USNO-B1.0 - mark the USNO-B1.0 star in Aladin
  #if [ -f search_databases_with_vizquery_USNOB_ID_OK.tmp ];then
  # search_databases_with_vizquery_USNOB_ID_OK.tmp is no longer produced by the new version of util/search_databases_with_vizquery.sh
  if [ -f search_databases_with_vizquery_GAIA_ID_OK.tmp ];then
   echo -n " draw green circle("`cat search_databases_with_vizquery_USNOB_ID_OK.tmp`" 2.5arcsec) ;" >> Aladin.script
  fi
  echo "" >> Aladin.script
  export PATH=$PATH:$HOME # Aladin is often saved in the home directory
  echo "Here is the Aladin script you may copy to Aladin console:"
  echo " "
  cat Aladin.script
  echo " "
  # Aladin command may be upper or lower case
  command -v Aladin &>/dev/null || command -v aladin &>/dev/null
  if [ $? -ne 0 ];then
   echo "Please note, that you may also put the Aladin executable and the Aladin.jar archive" 
   echo "into your home directory ( $HOME ) to let $0 start Aladin automatically."
  else
   echo "Aladin is starting..."
   if [ "$START_NAME" != "identify_noninteractive.sh" ];then
    command -v Aladin &>/dev/null
    if [ $? -ne 0 ];then
     Aladin < Aladin.script &>/dev/null &
    else
     aladin < Aladin.script &>/dev/null &
    fi
   fi # if [ "$START_NAME" != "identify_noninteractive.sh" ];then
  fi 
  echo " "
  if [ "$START_NAME" != "identify_noninteractive.sh" ];then
   "$VAST_PATH"pgfv $WCS_IMAGE_NAME $X $Y
  fi
 fi
else 
 echo "The plate-solved (WCS-calibrated) image is saved to $WCS_IMAGE_NAME"
fi # if [ "$START_NAME" != "wcs_image_calibration.sh" ] && [ "$START_NAME" != "wcs_image_nocatalog.sh" ];then
