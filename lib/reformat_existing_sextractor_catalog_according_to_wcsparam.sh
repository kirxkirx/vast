#!/usr/bin/env bash

# This script should take an existing SExtractor catalog and simulate the output of 
# $SEXTRACTOR -PARAMETERS_NAME wcs.param 

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ -z $3 ];then
 echo "Usage: $0 ORIGINAL_FITSFILE.fit wcs_ORIGINAL_FITSFILE.fit OUTPUT_SEXTRACTOR_CATALOG.cat" >> /dev/stderr
 exit 1
fi

FITSFILE="$1"
WCS_IMAGE_NAME="$2"
OUTPUT_SEXTRACTOR_CATALOG="$3"

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
 VAST_PATH=`vastrealpath $0`
 VAST_PATH=`dirname "$VAST_PATH"`
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
#


# Make sure the input image files look reasonable
############################################
for FITSFILE_TO_CHECK in "$FITSFILE" "$WCS_IMAGE_NAME" ;do

 #echo "Checking $FITSFILE_TO_CHECK"
 if [ ! -f "$FITSFILE_TO_CHECK" ];then
  echo "ERROR in $0 : $FITSFILE_TO_CHECK does not exist!" >> /dev/stderr
  exit 1
 fi
 if [ ! -s "$FITSFILE_TO_CHECK" ];then
  echo "ERROR in $0 : $FITSFILE_TO_CHECK is empty!" >> /dev/stderr
  exit 1
 fi
 # Verify that the input file is a valid FITS file
 "$VAST_PATH"lib/fitsverify -q -e "$FITSFILE_TO_CHECK"
 if [ $? -ne 0 ];then
  echo "WARNING: the input file $FITSFILE_TO_CHECK seems to be a FITS image that does not fully comply with the FITS standard.
Checking if the filename extension and FITS header look reasonable..."
  ## Exampt from the rule for files that have at least some correct keywords
  echo "$FITSFILE_TO_CHECK" | grep  -e ".fits"  -e ".FITS"  -e ".fts" -e ".FTS"  -e ".fit"  -e ".FIT" && "$VAST_PATH"util/listhead "$FITSFILE_TO_CHECK" | grep -e "SIMPLE  =                    T" -e "TELESCOP= 'Aristarchos'" && "$VAST_PATH"util/listhead "$FITSFILE_TO_CHECK" | grep -e "NAXIS   =                    2" -e "TELESCOP= 'Aristarchos'"
  if [ $? -eq 0 ];then
   echo "OK, let's assume this is a valid FITS file"
  else
   echo "ERROR in $0 : the input image file $FITSFILE_TO_CHECK did not pass verification as a valid FITS file"
   exit 1
  fi
 fi
 #echo "$FITSFILE_TO_CHECK is OK"

done

# Check the input WCS image is acatually WCS-solved
"$VAST_PATH"lib/bin/xy2sky "$WCS_IMAGE_NAME" | grep --quiet 'No WCS'
if [ $? -eq 0 ];then
 echo "ERROR in $0 : $WCS_IMAGE_NAME does not seem to be WCS-solved!" >> /dev/stderr
 exit 1
fi
############################################

if [ ! -s vast_images_catalogs.log ];then
 # No image processing results are here
 exit 1
fi

grep --quiet "$FITSFILE" vast_images_catalogs.log
if [ $? -ne 0 ];then
 # The input image is not one of the previously processed ones
 exit 1
fi

ORIGONAL_SEXTRACTOR_CATALOG=`grep "$FITSFILE" vast_images_catalogs.log | awk '{print $1}'`
if [ ! -f "$ORIGONAL_SEXTRACTOR_CATALOG" ];then
 echo "ERROR in $0 : cannot find $ORIGONAL_SEXTRACTOR_CATALOG"
 exit 1
fi
if [ ! -s "$ORIGONAL_SEXTRACTOR_CATALOG" ];then
 echo "ERROR in $0 : the catalog file $ORIGONAL_SEXTRACTOR_CATALOG is empty"
 exit 1
fi

# OK, assume we are good
echo "Generating $OUTPUT_SEXTRACTOR_CATALOG from $ORIGONAL_SEXTRACTOR_CATALOG" >> /dev/stderr
cat "$ORIGONAL_SEXTRACTOR_CATALOG" | awk '{printf "%10d %11.7f %+11.7f %11.4f %11.4f %12.7g %12.7g %8.4f %8.4f %3d\n", $1, 0.0,0.0, $16,$17, $2,$3, $4,$10, $22}' > correct_sextractor_wcs_catalog_usingxy2sky$$.tmp
# The desired output:
# NUMBER
# ALPHAWIN_SKY
# DELTAWIN_SKY
# XWIN_IMAGE
# YWIN_IMAGE
# FLUX_APER(1)
# FLUXERR_APER(1)
# MAG_APER(1)
# MAGERR_APER(1)
# FLAGS
mv correct_sextractor_wcs_catalog_usingxy2sky$$.tmp "$OUTPUT_SEXTRACTOR_CATALOG"

