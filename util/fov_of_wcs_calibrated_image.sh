#!/usr/bin/env bash
#
# This script should print filed of view of an input WCS-calibrated image
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ -z "$1" ];then
 echo "This script should print filed of view of an input WCS-calibrated image
 
 Usage: $0 wcs_image.fits" 1>&2
 exit 1
fi

FITS_IMAGE_TO_CHECK="$1"

# Check input
if [ ! -f "$FITS_IMAGE_TO_CHECK" ];then
 echo "ERROR in $0 cannot find the input FITS image $FITS_IMAGE_TO_CHECK" 1>&2
 exit 1
fi
if [ ! -s "$FITS_IMAGE_TO_CHECK" ];then
 echo "ERROR in $0 the input image $FITS_IMAGE_TO_CHECK is empty" 1>&2
 exit 1
fi

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


# Set the VaST path to find external programs
if [ -z "$VAST_PATH" ];then
 VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
#

# Verify that the input file is a valid FITS file
"$VAST_PATH"lib/fitsverify -q -e "$FITS_IMAGE_TO_CHECK"
if [ $? -ne 0 ];then
 echo "WARNING: the input file $FITS_IMAGE_TO_CHECK seems to be a FITS image that does not fully comply with the FITS standard.
Checking if the filename extension and FITS header look reasonable..."
 ## Exampt from the rule for files that have at least some correct keywords
 echo "$FITS_IMAGE_TO_CHECK" | grep  -e ".fits"  -e ".FITS"  -e ".fts" -e ".FTS"  -e ".fit"  -e ".FIT" && "$VAST_PATH"util/listhead "$FITS_IMAGE_TO_CHECK" | grep -e "SIMPLE  =                    T" -e "TELESCOP= 'Aristarchos'" && "$VAST_PATH"util/listhead "$FITS_IMAGE_TO_CHECK" | grep -e "NAXIS   =                    2" -e "TELESCOP= 'Aristarchos'"
 if [ $? -eq 0 ];then
  echo "OK, let's assume this is a valid FITS file"
 else
  echo "ERROR: the input image file $FITS_IMAGE_TO_CHECK did not pass verification as a valid FITS file"
  exit 1
 fi
fi

# Handle compressed FITS
echo $(basename "$FITS_IMAGE_TO_CHECK") | grep -q '\.fz$' || file "$FITS_IMAGE_TO_CHECK" | grep 'FITS image' | grep 'compress'
if [ $? -eq 0 ];then
 # funpack -S image.fits.fz | listhead STDIN
 FITS_IMAGE_TO_CHECK_HEADER=$("$VAST_PATH"util/funpack -S "$FITS_IMAGE_TO_CHECK" | "$VAST_PATH"util/listhead STDIN)
else
 FITS_IMAGE_TO_CHECK_HEADER=$("$VAST_PATH"util/listhead "$FITS_IMAGE_TO_CHECK")
fi

if [ -z "$FITS_IMAGE_TO_CHECK_HEADER" ];then
 echo "ERROR getting FITS header from $FITS_IMAGE_TO_CHECK"
 exit 1
fi

# Check that the FITS image does seem to contain a WCS solution

# Check if it has WCS keywords
for TYPICAL_WCS_KEYWORD in NAXIS1 NAXIS2  CTYPE1 CTYPE2 CRVAL1 CRVAL2 CRPIX1 CRPIX2 CD1_1 CD1_2 CD2_1 CD2_2 ;do
 echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep -q "$TYPICAL_WCS_KEYWORD"
 if [ $? -ne 0 ];then
  echo "ERROR in $0 $TYPICAL_WCS_KEYWORD keyword is not found in the image header.
Is the input image $FITS_IMAGE_TO_CHECK actually plate-solved?" 1>&2
  exit 1
 fi
done

# Get image dimentions in pixels
# We assume the image is uncompressed above and we have a proper image header
# Would it be safer to use head instead of grep --max-count= in case we have busybox grep?
#NAXIS1=$(echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep --max-count=1 'NAXIS1' | awk -F '=' '{print $2}' | awk '{print $1}')
#NAXIS2=$(echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep --max-count=1 'NAXIS2' | awk -F '=' '{print $2}' | awk '{print $1}')
IMG_SIZE_STR=$("$VAST_PATH"lib/astrometry/get_image_dimentions "$FITS_IMAGE_TO_CHECK")
NAXIS1=$(echo "$IMG_SIZE_STR" | awk '{print $2}')
NAXIS2=$(echo "$IMG_SIZE_STR" | awk '{print $4}')
if [ -z "$NAXIS1" ] || [ -z "$NAXIS2" ]; then
 echo "ERROR in $0 -- cannot get image size using  lib/astrometry/get_image_dimentions  $FITS_IMAGE_TO_CHECK_HEADER"
 exit 1
fi

# Determine the image size
XY2SKY_OUTPUT=$("$VAST_PATH"lib/bin/xy2sky -j "$FITS_IMAGE_TO_CHECK" 0 0 $NAXIS1 0 0 $NAXIS2)
CORNER_0_0=$(echo "$XY2SKY_OUTPUT" | head -n1 | awk '{print $1" "$2}')
CORNER_NAXIS1_0=$(echo "$XY2SKY_OUTPUT" | head -n2 | tail -n1 | awk '{print $1" "$2}')
CORNER_0_NAXIS2=$(echo "$XY2SKY_OUTPUT" | head -n3 | tail -n1 | awk '{print $1" "$2}')
X_SIZE_ARCMIN=$("$VAST_PATH"lib/bin/skycoor -r $CORNER_0_0 $CORNER_NAXIS1_0 | awk '{printf "%.1f",$1/60}')
Y_SIZE_ARCMIN=$("$VAST_PATH"lib/bin/skycoor -r $CORNER_0_0 $CORNER_0_NAXIS2 | awk '{printf "%.1f",$1/60}')

X_SIZE_DEG=$(echo "$X_SIZE_ARCMIN" | awk '{printf "%.1f",$1/60}')
Y_SIZE_DEG=$(echo "$Y_SIZE_ARCMIN" | awk '{printf "%.1f",$1/60}')

IMAGE_SCALE_X_ARCSECpix=$(echo "$X_SIZE_ARCMIN $NAXIS1" | awk '{printf "%.2f",$1*60/$2}')
IMAGE_SCALE_Y_ARCSECpix=$(echo "$Y_SIZE_ARCMIN $NAXIS2" | awk '{printf "%.2f",$1*60/$2}')

# why +1??
#IMAGE_CENTER_XY=$(echo "$NAXIS1 $NAXIS2" | awk '{printf "%.3f %.3f",($1+1)/2,($2+1)/2}')
IMAGE_CENTER_XY=$(echo "$NAXIS1 $NAXIS2" | awk '{printf "%.3f %.3f",$1/2+1,$2/2+1}')
IMAGE_CENTER_RA_Dec=$("$VAST_PATH"lib/bin/xy2sky -j "$FITS_IMAGE_TO_CHECK" $IMAGE_CENTER_XY)

# Print the results
echo "Image size: ${X_SIZE_ARCMIN}'x${Y_SIZE_ARCMIN}'  ${X_SIZE_DEG}(deg)x${Y_SIZE_DEG}(deg)  ${NAXIS1}x${NAXIS2} pix"
echo "Image scale: $IMAGE_SCALE_X_ARCSECpix\"/pix along the X axis and $IMAGE_SCALE_Y_ARCSECpix\"/pix along the Y axis"
echo "Image center: $IMAGE_CENTER_RA_Dec"
