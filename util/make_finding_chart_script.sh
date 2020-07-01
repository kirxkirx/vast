#!/usr/bin/env bash

# Specify how many pixels around the target you want to display
# (how big the finding chart should be)
PIXELS_AROUND_TARGET=64

# Tweak the util/make_finding_chart command line options below
# to switch on/off the display of observing date and image size
############################################

# Check the command line arguments
if [ $3 -eq 0 ];then
 echo "This script will make a good looking finder chart from the input image.
 
Usage: $0 wcs_calibrated_image.fits RA DEC
Example: $0 wcs_calibrated_image.fits 12:34:56.78 -01:23:45.6"

fi

# Check if Swarp is installed
command -v swarp &>/dev/null
if [ $? -ne 0 ];then
 echo "Please install Swarp"
 exit 1
fi

# Check if the input image
FITSFILE=$1
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
# Verify that the input file is a valid FITS file
"$VAST_PATH"lib/fitsverify -q -e "$FITSFILE"
if [ $? -ne 0 ];then
 echo "WARNING: the input file $FITSFILE seems to be a FITS image that does not fully comply with the FITS standard.
Checking if the filename extension and FITS header look reasonable..."
 ## Exampt from the rule for files that have at least some correct keywords
 echo "$FITSFILE" | grep  -e ".fits"  -e ".FITS"  -e ".fts" -e ".FTS"  -e ".fit"  -e ".FIT" && "$VAST_PATH"util/listhead "$FITSFILE" | grep -e "SIMPLE  =                    T" -e "TELESCOP= 'Aristarchos'" && "$VAST_PATH"util/listhead "$FITSFILE" | grep -e "NAXIS   =                    2" -e "TELESCOP= 'Aristarchos'"
 if [ $? -eq 0 ];then
  echo "OK, let's assume this is a valid FITS file"
 else
  echo "ERROR: the input image file $FITSFILE did not pass verification as a valid FITS file"
  exit 1
 fi
fi

# Check if the input image is WCS-calibrated
FITSFILE_HEADER=`"$VAST_PATH"util/listhead "$FITSFILE"`
# Check if it has WCS keywords
for TYPICAL_WCS_KEYWORD in CTYPE1 CTYPE2 CRVAL1 CRVAL2 CRPIX1 CRPIX2 CD1_1 CD1_2 CD2_1 CD2_2 ;do
 echo "$FITSFILE_HEADER" | grep --quiet "$TYPICAL_WCS_KEYWORD"
 if [ $? -ne 0 ];then
  echo "Some of the expected WCS keywords are misssing. Please make sure the input image is plate-solved!"
  exit 1
 fi
done

########### End of checks - start the work ###########

# R
swarp -SUBTRACT_BACK N "$FITSFILE"
if [ $? -ne 0 ];then
 echo "ERROR running swarp"
 exit 1
fi
mv coadd.fits resample_"$FITSFILE"

# Get the pixel position we want to mark
PIXEL_POSITION_TO_MARK=`lib/bin/sky2xy resample_"$FITSFILE" 16:34:35.13 -26:58:03.4 | awk '{print $5" "$6}'`
if [ $? -ne 0 ];then
 echo "ERROR converting RA, Dec to the pixel coordinates"
 exit 1
fi
if [ -z "$PIXEL_POSITION_TO_MARK" ] || [ " " = "$PIXEL_POSITION_TO_MARK" ] ;then
 echo "ERROR converting RA, Dec to the pixel coordinates (empty result)"
 exit 1
fi

# Make the PNG finding chart
util/make_finding_chart resample_"$FITSFILE" $PIXEL_POSITION_TO_MARK -w $PIXELS_AROUND_TARGET -l -d -s
if [ $? -ne 0 ];then
 echo "ERROR running util/make_finding_chart"
 exit 1
fi
if [ ! -s pgplot.png ];then
 echo "ERROR: the output image pgplot.png does not exist or is empty"
 exit 1
fi

# Everything is fine
PIXEL_POSITION_TO_MARK=${PIXEL_POSITION_TO_MARK//" "/_}
FITSFILE=${FITSFILE//./_}
mv -v "pgplot.png" resample_"$FITSFILE"__"$PIXEL_POSITION_TO_MARK"pix.png

# Note that you may combine multiple images side-by-side using something like
# montage resample_wcs_Sco3_20*png -tile 3x2 -geometry +0+0 out.png
