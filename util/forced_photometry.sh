#!/usr/bin/env bash

#
# Forced aperture photometry at a specified sky position on a single FITS image.
#
# Usage: util/forced_photometry.sh image.fits HH:MM:SS.ss +DD:MM:SS.s FILTER
#
# Runs both C and Python implementations for cross-validation.
#

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
    echo "$1" | awk -F/ -v dir=$2 '{
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


if [ -z "$VAST_PATH" ];then
 VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi

#################################
# Parse command-line arguments
#################################
if [ -z "$4" ];then
 echo "Usage: $0 image.fits HH:MM:SS.ss +DD:MM:SS.s FILTER" >&2
 echo "  FILTER is one of: B V R Rc I Ic r i g" >&2
 exit 1
fi

FITSFILE="$1"
TARGET_RA="$2"
TARGET_DEC="$3"
FILTER="$4"

#################################
# Validate VaST tools exist
#################################
for TOOL in "${VAST_PATH}lib/bin/sky2xy" \
            "${VAST_PATH}lib/fit_zeropoint" \
            "${VAST_PATH}util/calibrate_single_image.sh" \
            "${VAST_PATH}util/get_image_date" \
            "${VAST_PATH}lib/sextract_single_image_noninteractive" \
            "${VAST_PATH}util/forced_photometry" \
            "${VAST_PATH}util/forced_photometry.py" ; do
 if [ ! -f "$TOOL" ] && [ ! -L "$TOOL" ];then
  echo "ERROR: required VaST tool not found: $TOOL" >&2
  echo "Please compile VaST first with 'make'" >&2
  exit 1
 fi
done

#################################
# Validate input image
#################################
if [ -z "$FITSFILE" ];then
 echo "ERROR: FITSFILE variable is not set" >&2
 exit 1
fi
if [ ! -f "$FITSFILE" ];then
 echo "ERROR: cannot find the image file $FITSFILE" >&2
 exit 1
fi
if [ ! -s "$FITSFILE" ];then
 echo "ERROR: the input image file $FITSFILE is empty" >&2
 exit 1
fi

#################################
# Validate filter name
#################################
case "$FILTER" in
 B|V|R|Rc|I|Ic|r|i|g)
  ;;
 *)
  echo "ERROR: unrecognized filter '$FILTER'" >&2
  echo "  Supported filters: B V R Rc I Ic r i g" >&2
  exit 1
  ;;
esac

echo "Forced photometry: image=$FITSFILE RA=$TARGET_RA Dec=$TARGET_DEC filter=$FILTER" >&2

#################################
# Step 1: Run SExtractor to get aperture
#################################
echo "Step 1: Running SExtractor..." >&2
APERTURE=$("$VAST_PATH"lib/sextract_single_image_noninteractive "$FITSFILE" 2>/dev/null)
if [ $? -ne 0 ];then
 echo "ERROR: sextract_single_image_noninteractive failed" >&2
 exit 1
fi
if [ -z "$APERTURE" ];then
 echo "ERROR: empty aperture from sextract_single_image_noninteractive" >&2
 exit 1
fi
echo "  Aperture diameter: $APERTURE pixels" >&2

#################################
# Step 2: Calibrate (internally runs solve_plate_with_UCAC5)
#################################
echo "Step 2: Calibrating..." >&2
"$VAST_PATH"util/calibrate_single_image.sh "$FITSFILE" "$FILTER"
if [ $? -ne 0 ];then
 echo "ERROR: calibrate_single_image.sh failed" >&2
 exit 1
fi
if [ ! -s "calib.txt" ];then
 echo "ERROR: calib.txt not found or empty after calibration" >&2
 exit 1
fi

#################################
# Step 3: Fit zeropoint
#################################
echo "Step 3: Fitting zeropoint..." >&2
"$VAST_PATH"lib/fit_zeropoint > /dev/null 2>&1
if [ $? -ne 0 ];then
 echo "ERROR: fit_zeropoint failed" >&2
 exit 1
fi
if [ ! -s "calib.txt_param" ];then
 echo "ERROR: calib.txt_param not found or empty" >&2
 exit 1
fi

#################################
# Step 4: Convert RA/Dec to pixel coordinates
#################################
echo "Step 4: Converting RA/Dec to pixel coordinates..." >&2
SKY2XY_OUTPUT=$("$VAST_PATH"lib/bin/sky2xy "$FITSFILE" $TARGET_RA $TARGET_DEC 2>&1)
if [ $? -ne 0 ];then
 echo "ERROR: sky2xy failed" >&2
 echo "  Output: $SKY2XY_OUTPUT" >&2
 exit 1
fi
# Check for off-image or offscale
if echo "$SKY2XY_OUTPUT" | grep -q -e "off image" -e "offscale" ;then
 echo "ERROR: target coordinates are off the image" >&2
 echo "  sky2xy output: $SKY2XY_OUTPUT" >&2
 exit 1
fi
PIXEL_X=$(echo "$SKY2XY_OUTPUT" | awk '{print $5}')
PIXEL_Y=$(echo "$SKY2XY_OUTPUT" | awk '{print $6}')
if [ -z "$PIXEL_X" ] || [ -z "$PIXEL_Y" ];then
 echo "ERROR: could not parse pixel coordinates from sky2xy output" >&2
 echo "  sky2xy output: $SKY2XY_OUTPUT" >&2
 exit 1
fi
echo "  Pixel position: $PIXEL_X $PIXEL_Y" >&2

#################################
# Step 5: Extract JD
#################################
echo "Step 5: Extracting observation date..." >&2
JD=$("$VAST_PATH"util/get_image_date "$FITSFILE" 2>&1 | grep '  JD ' | awk '{print $2}' | head -n1)
if [ -z "$JD" ];then
 echo "WARNING: could not extract JD from image, using 0.0" >&2
 JD="0.0"
fi
echo "  JD: $JD" >&2

#################################
# Step 6: Run C implementation
#################################
echo "Step 6: Running C forced photometry..." >&2
C_START=$(date +%s%N)
C_RESULT=$("$VAST_PATH"util/forced_photometry "$FITSFILE" $PIXEL_X $PIXEL_Y $APERTURE 2>/dev/null)
C_EXIT=$?
C_END=$(date +%s%N)
C_TIME=$(echo "$C_START $C_END" | awk '{printf "%.3f", ($2-$1)/1000000000.0}')
echo "  C execution time: ${C_TIME}s" >&2
if [ $C_EXIT -ne 0 ];then
 echo "WARNING: C forced photometry exited with code $C_EXIT" >&2
 C_RESULT="99.0000 99.0000 fail"
fi
if [ -z "$C_RESULT" ];then
 echo "WARNING: empty result from C forced photometry" >&2
 C_RESULT="99.0000 99.0000 fail"
fi

#################################
# Step 7: Run Python implementation
#################################
echo "Step 7: Running Python forced photometry..." >&2
PY_START=$(date +%s%N)
PY_RESULT=$("$VAST_PATH"util/forced_photometry.py "$FITSFILE" $PIXEL_X $PIXEL_Y $APERTURE 2>/dev/null)
PY_EXIT=$?
PY_END=$(date +%s%N)
PY_TIME=$(echo "$PY_START $PY_END" | awk '{printf "%.3f", ($2-$1)/1000000000.0}')
echo "  Python execution time: ${PY_TIME}s" >&2
if [ $PY_EXIT -ne 0 ];then
 echo "WARNING: Python forced photometry exited with code $PY_EXIT" >&2
 PY_RESULT="99.0000 99.0000 fail"
fi
if [ -z "$PY_RESULT" ];then
 echo "WARNING: empty result from Python forced photometry" >&2
 PY_RESULT="99.0000 99.0000 fail"
fi

#################################
# Output results
#################################
BASENAME_FITSFILE=$(basename "$FITSFILE")

echo "# C implementation:"
echo "$JD  $C_RESULT  $BASENAME_FITSFILE"
echo "# Python implementation:"
echo "$JD  $PY_RESULT  $BASENAME_FITSFILE"
