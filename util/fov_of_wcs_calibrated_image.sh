#!/usr/bin/env bash
#
# This script should print filed of view of an input WCS-calibrated image
#

if [ -z "$1" ];then
 echo "This script should print filed of view of an input WCS-calibrated image
 
 Usage: $0 wcs_image.fits" >> /dev/stderr
 exit 1
fi

FITS_IMAGE_TO_CHECK="$1"

# Check input
if [ ! -f "$FITS_IMAGE_TO_CHECK" ];then
 echo "ERROR in $0 cannot find the input FITS image $FITS_IMAGE_TO_CHECK" >> /dev/stderr
 exit 1
fi
if [ ! -s "$FITS_IMAGE_TO_CHECK" ];then
 echo "ERROR in $0 the input image $FITS_IMAGE_TO_CHECK is empty" >> /dev/stderr
 exit 1
fi

# Set the VaST path to find external programs
if [ -z "$VAST_PATH" ];then
 VAST_PATH=`readlink -f $0`
 VAST_PATH=`dirname "$VAST_PATH"`
 VAST_PATH="${VAST_PATH/'util/'/}"
 VAST_PATH="${VAST_PATH/'lib/'/}"
 VAST_PATH="${VAST_PATH/'examples/'/}"
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH/examples/}"
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

# Check that the image does seem to contain a WCS solution
FITS_IMAGE_TO_CHECK_HEADER=`"$VAST_PATH"util/listhead "$FITS_IMAGE_TO_CHECK"`
# Check if it has WCS keywords
for TYPICAL_WCS_KEYWORD in CTYPE1 CTYPE2 CRVAL1 CRVAL2 CRPIX1 CRPIX2 CD1_1 CD1_2 CD2_1 CD2_2 ;do
 echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep --quiet "$TYPICAL_WCS_KEYWORD"
 if [ $? -ne 0 ];then
  echo "ERROR in $0 $TYPICAL_WCS_KEYWORD keyword is not found in the image header" >> /dev/stderr
  exit 1
 fi
done

# Get image dimentions in pixels
FITSHEADER=`"$VAST_PATH"util/listhead "$FITS_IMAGE_TO_CHECK"`
NAXIS1=`echo "$FITSHEADER" | grep --max-count=1 'NAXIS1' | awk -F '=' '{print $2}' | awk '{print $1}'`
NAXIS2=`echo "$FITSHEADER" | grep --max-count=1 'NAXIS2' | awk -F '=' '{print $2}' | awk '{print $1}'`

# Determine the image size
XY2SKY_OUTPUT=`"$VAST_PATH"lib/bin/xy2sky -j "$FITS_IMAGE_TO_CHECK" 0 0 $NAXIS1 0 0 $NAXIS2`
CORNER_0_0=`echo "$XY2SKY_OUTPUT" | head -n1 | awk '{print $1" "$2}'`
CORNER_NAXIS1_0=`echo "$XY2SKY_OUTPUT" | head -n2 | tail -n1 | awk '{print $1" "$2}'`
CORNER_0_NAXIS2=`echo "$XY2SKY_OUTPUT" | head -n3 | tail -n1 | awk '{print $1" "$2}'`
X_SIZE_ARCMIN=`"$VAST_PATH"lib/bin/skycoor -r $CORNER_0_0 $CORNER_NAXIS1_0 | awk '{printf "%.1f",$1/60}'`
Y_SIZE_ARCMIN=`"$VAST_PATH"lib/bin/skycoor -r $CORNER_0_0 $CORNER_0_NAXIS2 | awk '{printf "%.1f",$1/60}'`

IMAGE_SCALE_X_ARCSECpix=`echo "$X_SIZE_ARCMIN $NAXIS1" | awk '{printf "%.2f",$1*60/$2}'`
IMAGE_SCALE_Y_ARCSECpix=`echo "$Y_SIZE_ARCMIN $NAXIS2" | awk '{printf "%.2f",$1*60/$2}'`

IMAGE_CENTER_XY=`echo "$NAXIS1 $NAXIS2" | awk '{printf "%.3f %.3f",($1+1)/2,($2+1)/2}'`
IMAGE_CENTER_RA_Dec=`"$VAST_PATH"lib/bin/xy2sky -j "$FITS_IMAGE_TO_CHECK" $IMAGE_CENTER_XY`

# Print the results
echo "Image size: $X_SIZE_ARCMIN'"x"$Y_SIZE_ARCMIN'"
echo "Image scale: $IMAGE_SCALE_X_ARCSECpix\"/pix along the X axis and $IMAGE_SCALE_Y_ARCSECpix\"/pix along the Y axis"
echo "Image center: $IMAGE_CENTER_RA_Dec"