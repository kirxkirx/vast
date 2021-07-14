#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ -z "$2" ];then
 echo "Usage: $0 wcs_image.fits sextractor_catalog.cat"
 exit 1
fi

INPUT_SEXTRACTOR_CATALOG="$2"
if [ ! -f "$INPUT_SEXTRACTOR_CATALOG" ];then
 echo "ERROR: cannot find the input SExtractor catalog $INPUT_SEXTRACTOR_CATALOG"
 exit 1
fi
if [ ! -s "$INPUT_SEXTRACTOR_CATALOG" ];then
 echo "ERROR: input SExtractor catalog $INPUT_SEXTRACTOR_CATALOG is empty!"
 exit 1
fi

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


# Always use the internal copy of WCSTools as the system installation of WCSTools may be corrputed
if [ -z "$VAST_PATH" ];then
# VAST_PATH=`readlink -f $0`
 VAST_PATH=`vastrealpath $0`
 VAST_PATH=`dirname "$VAST_PATH"`
 VAST_PATH="${VAST_PATH/'util/'/}"
 VAST_PATH="${VAST_PATH/'lib/'/}"
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH//'//'/'/'}"
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
#echo "DEBUG: VAST_PATH=$VAST_PATH"

TEMPORARY_CATALOG_NAME="$VAST_PATH"correct_sextractor_wcs_catalog_usingxy2sky$$.tmp

WCS_IMAGE="$1"
if [ ! -s "$WCS_IMAGE" ];then
 echo "ERROR reading the input FITS image $WCS_IMAGE"
 exit 1
fi
"$VAST_PATH"lib/fitsverify -q -e "$WCS_IMAGE" 1>&2
if [ $? -ne 0 ];then
 echo "WARNING: the input file $WCS_IMAGE seems to be a FITS image that does not fully comply with the FITS standard.
Checking if the filename extension and FITS header look reasonable..."
 ## Exampt from the rule for files that have at least some correct keywords
 echo "$WCS_IMAGE" | grep  -e ".fits"  -e ".FITS"  -e ".fts" -e ".FTS"  -e ".fit"  -e ".FIT" && util/listhead "$WCS_IMAGE" | grep "SIMPLE  =                    T" && util/listhead "$WCS_IMAGE" | grep "NAXIS   =                    2"
 if [ $? -eq 0 ];then
  echo "OK, let's assume this is a valid FITS file"
 else
  echo "ERROR: the input image file $WCS_IMAGE did not pass verification as a valid FITS file"
  exit 1
 fi
fi

# Silently test that xy2sky does not crash on the input image
"$VAST_PATH"lib/bin/xy2sky "$WCS_IMAGE" 10 10 &> /dev/null
if [ $? -ne 0 ];then
 # Run it again to see the error message
 "$VAST_PATH"lib/bin/xy2sky "$WCS_IMAGE" 10 10
 echo "ERROR in the test run of xy2sky"
 exit 1
fi

# Print out stats of the WCS-solved image
"$VAST_PATH"util/fov_of_wcs_calibrated_image.sh "$WCS_IMAGE"

echo "
 ### Converting SExtractor-derived pixel positions to celestial coordinates using xy2sky from WCSTools ###"

# sed '/^\s*$/d' -- removes empty lines
"$VAST_PATH"lib/bin/xy2sky -a -k 4 -j -d -n 7 "$WCS_IMAGE" "@$INPUT_SEXTRACTOR_CATALOG" | sed '/^\s*$/d' | grep -v 'Off map' | awk '{printf "%10d %11.7f %+11.7f %11.4f %11.4f %12.7g %12.7g %8.4f %8.4f %3d\n",$4,$1,$2,$7,$8,$9,$10,$11,$12,$13}' > "$TEMPORARY_CATALOG_NAME"
if [ $? -ne 0 ];then
 echo "ERROR running xy2sky"
 exit 1
fi
if [ ! -s "$TEMPORARY_CATALOG_NAME" ];then
 echo "ERROR: the output file $TEMPORARY_CATALOG_NAME is EMPTY"
 rm -f "$TEMPORARY_CATALOG_NAME"
 exit 1
fi

N_LINES_OUTPUT_CAT=`cat "$TEMPORARY_CATALOG_NAME" | wc -l`
echo " ### Converted positions of $N_LINES_OUTPUT_CAT stars ###"

################### DEBUG
cp -v $INPUT_SEXTRACTOR_CATALOG vast_debug_catalog_before_xy2sky_correction.cat.log
cp -v "$VAST_PATH"correct_sextractor_wcs_catalog_usingxy2sky$$.tmp vast_debug_catalog_after_xy2sky_correction.cat.log
#########################

mv -f "$TEMPORARY_CATALOG_NAME" "$INPUT_SEXTRACTOR_CATALOG"
