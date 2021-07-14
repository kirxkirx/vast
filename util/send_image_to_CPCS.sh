#!/usr/bin/env bash
#
# This script will plate-solve an image, run SExtractor on it
# and send the results to the Cambridge Photometry Calibration Server (CPCS)
# http://gsaweb.ast.cam.ac.uk/followup
#
# Before using the script, please specify your hashtag:
#CPCS_LOGIN_HASHTAG="CHANGE_ME"
#CPCS_LOGIN_HASHTAG="MSUO0.6_KSokolovsky_7dba8628e6b3c4113e6bce0b26cd77bc"
#CPCS_LOGIN_HASHTAG="AAVSO_5cc0bbac500993d82502e68c7be1ee4a"
#CPCS_LOGIN_HASHTAG="AZubareva_0.6_SAI16759d5188940315b9c7591049910831"
#CPCS_LOGIN_HASHTAG="CrAO_SNazarov_13bd755aea9d87608b9c68c66e2a02c4"
#CPCS_LOGIN_HASHTAG="Aristarchos_KSokolovsky_615f932fd0a2d1c0996723b7ec76df91"
CPCS_LOGIN_HASHTAG="MSUO0.6_KSokolovsky_7dba8628e6b3c4113e6bce0b26cd77bc"
# The hashtag should be requested from Lukasz Wyrzykowski.
# For more information see https://www.ast.cam.ac.uk/ioa/wikis/gsawgwiki/index.php/Calibration_Server
#
# Set DO_DRY_RUN=1 for testing, not changes are stored in the CPCS databse in this case!
# DO_DRY_RUN=0 - save changes to the CPCS databse.
DO_DRY_RUN=0
#
#DO_DRY_RUN=1
#
# This should be "no" under the normal circumstances
FORCE_FILTER="no"
#
#FORCE_FILTER="any/B"
#FORCE_FILTER="any/V"
#FORCE_FILTER="any/R"
#
#FORCE_FILTER="APASS/i"
#FORCE_FILTER="APASS/r"
#FORCE_FILTER="APASS/B"
#FORCE_FILTER="APASS/V"
#
##################################################################
# You probably don't want to change anything below this line.
##################################################################

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

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
      cd "$(dirname "$1")"
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD"
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}


if [ -z "$VAST_PATH" ];then
 #VAST_PATH=`readlink -f $0`
 VAST_PATH=`vastrealpath $0`
 VAST_PATH=`dirname "$VAST_PATH"`
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=`echo "$VAST_PATH" | sed "s:'::g"`
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
#


function write_vast_CPCS_log {
 if [ -z "$1" ];then
  STATUS="UNKNOWN"
 fi
 STATUS="$1"
 
 echo "$CPCS_LOGIN_HASHTAG  $INPUT_FITS_IMAGE $MJD $EXPOSURE  $STATUS" >> images_sent_to_CPCS.txt

}

function print_usage_notes {
 echo "
   Usage: $0 ivorn /path/to/image.fits

 Example: $0 ivo://Gaia16aye ../individual_images_test/Gaia16aye-001V.fit
"

# Check if the hashtag looks valid
if [ -z "$CPCS_LOGIN_HASHTAG" ];then
 echo "ERROR: something is very wrong - the variable CPCS_LOGIN_HASHTAG is not set"
fi
if [ "$CPCS_LOGIN_HASHTAG" = "CHANGE_ME" ];then
 echo "ERROR: you need to set your CPCS hashtag in the body of the script $0"
 exit 1
else
 echo "Note that your CPCS hashtag is currently set to $CPCS_LOGIN_HASHTAG 
inside the body of the script $0

  Please double-check that your hashtag is set correctly!"
 sleep 2
fi

# Check if FORCE_FILTER looks valid
if [ -z "$FORCE_FILTER" ];then
 echo "ERROR: something is very wrong - the variable FORCE_FILTER is not set"
fi
if [ "$FORCE_FILTER" != "no" ];then
 echo "Note that your FORCE_FILTER is currently set to $FORCE_FILTER 
inside the body of the script $0

  Please double-check that your FORCE_FILTER is set correctly!"
fi


}

# Check the command line input
IVORN="$1"
if [ -z "$IVORN" ];then
 print_usage_notes
 exit 1
fi
echo "$IVORN" | grep 'ivo://'
if [ $? -ne 0 ];then
 print_usage_notes
 exit 1
fi


INPUT_FITS_IMAGE="$2"
if [ -z "$INPUT_FITS_IMAGE" ];then
 print_usage_notes
 exit 1
fi
if [ ! -f "$INPUT_FITS_IMAGE" ];then
 echo "ERROR: cannot find the input image $INPUT_FITS_IMAGE"
 exit 1
fi
if [ ! -s "$INPUT_FITS_IMAGE" ];then
 echo "ERROR: the input image file $INPUT_FITS_IMAGE is empty"
 exit 1
fi
"$VAST_PATH"lib/fitsverify -q -e "$INPUT_FITS_IMAGE"
#if [ $? -ne 0 ];then
# echo "ERROR: the input image file $INPUT_FITS_IMAGE did not pass verification as a valid FITS file"
# exit 1
#fi
if [ $? -ne 0 ];then
 echo "
 $0
WARNING: the input file $INPUT_FITS_IMAGE seems to be a FITS image that does not fully comply with the FITS standard.
Checking if the filename extension and FITS header look reasonable..."
 ## Exampt from the rule for files that have at least some correct keywords
 echo "$INPUT_FITS_IMAGE" | grep  -e ".fits"  -e ".FITS"  -e ".fts" -e ".FTS"  -e ".fit"  -e ".FIT" && "$VAST_PATH"util/listhead "$INPUT_FITS_IMAGE" | grep -e "SIMPLE  =                    T" -e "TELESCOP= 'Aristarchos'" && "$VAST_PATH"util/listhead "$INPUT_FITS_IMAGE" | grep -e "NAXIS   =                    2" -e "TELESCOP= 'Aristarchos'"
 if [ $? -eq 0 ];then
  echo "OK, let's assume this is a valid FITS file"
 else
  echo "ERROR: the input image file $INPUT_FITS_IMAGE did not pass verification as a valid FITS file"
  exit 1
 fi
fi


# Check if the hashtag looks valid
if [ -z "$CPCS_LOGIN_HASHTAG" ];then
 echo "ERROR: something is very wrong - the variable CPCS_LOGIN_HASHTAG is not set"
 exit 1
fi
if [ "$CPCS_LOGIN_HASHTAG" = "CHANGE_ME" ];then
 echo "ERROR: please set your hashtag in the body of the script $0"
 exit 1
fi
# Check DO_DRY_RUN
if [ $DO_DRY_RUN -ne 0 ];then
 if [ $DO_DRY_RUN -ne 1 ];then
  echo "ERROR: incorrect value of DO_DRY_RUN=$DO_DRY_RUN (it should be 0 or 1)"
  exit 1
 fi
fi 

# Clean up from a previous run
#util/clean_data.sh

# Get image data
MJD=`util/get_image_date "$INPUT_FITS_IMAGE" | grep -A 10 "Observation date in various formats" | grep "  MJD  " | awk '{print $2}'`
echo " ##### Derived MJD $MJD for $INPUT_FITS_IMAGE ##### "
#EXPOSURE=`util/listhead "$INPUT_FITS_IMAGE" | grep -e EXPTIME -e EXPOSURE | head -n1 | awk '{print $2}' FS='=' | awk '{printf "%.2f",$1}'`
EXPOSURE=`util/listhead "$INPUT_FITS_IMAGE" | grep -e EXPTIME -e EXPOSURE | head -n1 | awk -F '=' '{print $2}' | awk '{printf "%.2f",$1}'`
if [ -z "$EXPOSURE" ];then
 echo "WARNING: cannot derive the exposure time from FITS image header!
Assuming EXPOSURE=0.0 !"
 EXPOSURE=0
fi
echo " ##### Derived exposue time $EXPOSURE s for $INPUT_FITS_IMAGE ##### "

# First, plate-solve the input image
util/wcs_image_calibration.sh "$INPUT_FITS_IMAGE"
if [ $? -ne 0 ];then
 echo "ERROR: unable to plate-solve the image $INPUT_FITS_IMAGE"
 write_vast_CPCS_log "ERROR: unable to plate-solve the image"
 exit 1
fi
PLATESOLVED_FITS_IMAGE=wcs_`basename "$INPUT_FITS_IMAGE"`
PLATESOLVED_FITS_IMAGE="${PLATESOLVED_FITS_IMAGE/wcs_wcs_/wcs_}"
if [ ! -f "$PLATESOLVED_FITS_IMAGE" ];then
 echo "ERROR: cannot find the plate-solved image $PLATESOLVED_FITS_IMAGE"
 write_vast_CPCS_log "ERROR: cannot find the plate-solved image"
 exit 1
fi

# Get flag image and gain parameters for the SExtractor run
FLAG_AND_GAIN_COMMAND_LINE_PARAMETERS=`lib/guess_saturation_limit_main $PLATESOLVED_FITS_IMAGE`

# Run SExtractor
# Set SExtractor executable
SEXTRACTOR=sex             
export PATH=$PATH:lib/bin/
if [ -f CPCS.cat ];then
 rm -f CPCS.cat
fi
SE_COMMAND="$SEXTRACTOR $FLAG_AND_GAIN_COMMAND_LINE_PARAMETERS -PARAMETERS_NAME CPCS.params -CATALOG_NAME CPCS.cat -CATALOG_TYPE ASCII_HEAD"
echo "Running SExtractor " `command -v sex`
echo "$SE_COMMAND" "$PLATESOLVED_FITS_IMAGE"
$SE_COMMAND "$PLATESOLVED_FITS_IMAGE"
if [ $? -ne 0 ];then
 echo "ERROR running SExtractor"
 write_vast_CPCS_log "ERROR running SExtractor"
 exit 1
fi

# Upload results
curl -F matchDist=2 -F EventID="$IVORN" -F sexCat="@CPCS.cat;filename=CPCS.cat" -F "hashtag=$CPCS_LOGIN_HASHTAG" -F "MJD=$MJD" -F expTime="$EXPOSURE" -F noPlot=1 -F forceFilter=$FORCE_FILTER -F dryRun=$DO_DRY_RUN -F outputFormat=json "http://gsaweb.ast.cam.ac.uk/followup/cgi/upload"
#curl -F matchDist=3 -F EventID="$IVORN" -F sexCat="@CPCS.cat;filename=CPCS.cat" -F "hashtag=$CPCS_LOGIN_HASHTAG" -F "MJD=$MJD" -F expTime="$EXPOSURE" -F noPlot=1 -F forceFilter=$FORCE_FILTER -F dryRun=$DO_DRY_RUN -F outputFormat=json "http://gsaweb.ast.cam.ac.uk/followup/cgi/upload"
if [ $? -ne 0 ];then
 echo "ERROR uploading the catalog to CPCS"
 write_vast_CPCS_log "ERROR uploading the catalog to CPCS"
 exit 1
fi

# Write log
write_vast_CPCS_log "OK"
echo "
 ### The image $INPUT_FITS_IMAGE is processed and uploaded. Life is good! =) ###
 "
