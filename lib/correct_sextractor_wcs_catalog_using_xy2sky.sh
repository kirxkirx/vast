#!/usr/bin/env bash

#if [ -z "$2" ];then
# echo "Usage: $0 wcs_image.fits sextractor_catalog.cat"
# exit 1
#fi
#
#INPUT_SEXTRACTOR_CATALOG="$2"
#if [ ! -f "$INPUT_SEXTRACTOR_CATALOG" ];then
# echo "ERROR: cannot find the input SExtractor catalog $INPUT_SEXTRACTOR_CATALOG"
# exit 1
#fi
#if [ ! -s "$INPUT_SEXTRACTOR_CATALOG" ];then
# echo "ERROR: input SExtractor catalog $INPUT_SEXTRACTOR_CATALOG is empty!"
# exit 1
#fi

function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=`readlink -f "$1" 2>/dev/null`
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=`greadlink -f "$1" 2>/dev/null`
   if [ $? -ne 0 ];then
    # If not, resort to the black magic from
    # https://stackoverflow.com/questions/3572030/bash-script-absolute-path-with-os-x
    OURPWD=$PWD
    cd "$(dirname "$1")"
    LINK=$(readlink "$(basename "$1")")
    while [ "$LINK" ]; do
      cd "$(dirname "$LINK")"
      LINK=$(readlink "$(basename "$1")")
    done
    REALPATH="$PWD/$(basename "$1")"
    cd "$OURPWD"
   fi
  fi
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
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
#
echo "DEBUG: VAST_PATH=$VAST_PATH"

WCS_IMAGE="$1"
if [ ! -s "$WCS_IMAGE" ];then
 echo "ERROR reading the input FITS image $WCS_IMAGE"
 exit 1
fi
"$VAST_PATH"lib/fitsverify -q -e "$WCS_IMAGE" >> /dev/stderr
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

echo "
 ### Converting SExtractor-derived pixel positions to celestial coordinates using xy2sky from WCSTools ###"

# sed '/^\s*$/d' -- removes empty lines
"$VAST_PATH"lib/bin/xy2sky -a -k 4 -j -d -n 7 "$WCS_IMAGE" "@$INPUT_SEXTRACTOR_CATALOG" | sed '/^\s*$/d' | grep -v 'Off map' | awk '{printf "%10d %11.7f %+11.7f %11.4f %11.4f %12.7g %12.7g %8.4f %8.4f %3d\n",$4,$1,$2,$7,$8,$9,$10,$11,$12,$13}' > correct_sextractor_wcs_catalog_usingxy2sky$$.tmp
if [ $? -ne 0 ];then
 echo "ERROR running xy2sky"
 exit 1
fi
if [ ! -s "correct_sextractor_wcs_catalog_usingxy2sky$$.tmp" ];then
 echo "ERROR: the output file correct_sextractor_wcs_catalog_usingxy2sky$$.tmp is EMPTY"
 rm -f "correct_sextractor_wcs_catalog_usingxy2sky$$.tmp"
 exit 1
fi

mv -f correct_sextractor_wcs_catalog_usingxy2sky$$.tmp "$INPUT_SEXTRACTOR_CATALOG"
