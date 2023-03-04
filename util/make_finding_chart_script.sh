#!/usr/bin/env bash

# Specify how many pixels around the target you want to display
# (how big the standard finding chart should be)
PIXELS_AROUND_TARGET=64

# Tweak the util/make_finding_chart command line options below
# to switch on/off the display of observing date and image size
############################################

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


# Check the command line arguments
if [ -z "$3" ];then
 echo "This script will make a good looking finder chart from the input image.
 
Usage: 
$0 wcs_calibrated_image.fits RA DEC
or
$0 wcs_calibrated_image.fits RA DEC 'Target Name'
Examples: 
$0 wcs_calibrated_image.fits 12:34:56.78 -01:23:45.6
or 
$0 wcs_sds163_2022-6-6_22-14-49_001.fts 16:22:30.78 -17:52:42.8 'U Sco'"

fi

TARGET_RA="$2"
TARGET_DEC="$3"

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

# Resample the image to the new grid
swarp -SUBTRACT_BACK N -IMAGEOUT_NAME resample_"$FITSFILE" -WEIGHTOUT_NAME resample_weights_"$FITSFILE" "$FITSFILE"
if [ $? -ne 0 ];then
 echo "ERROR running swarp"
 exit 1
fi
#mv -v coadd.fits resample_"$FITSFILE"

# Solve the image again in attempt to mitigate this SIP vs TPV nonsesnse
util/wcs_image_calibration.sh resample_"$FITSFILE"
if [ -f wcs_resample_"$FITSFILE" ];then
 mv -vf wcs_resample_"$FITSFILE" resample_"$FITSFILE"
fi

# Get the pixel position we want to mark
PIXEL_POSITION_TO_MARK=`lib/bin/sky2xy resample_"$FITSFILE" $TARGET_RA $TARGET_DEC | awk '{print $5" "$6}'`
if [ $? -ne 0 ];then
 echo "ERROR converting RA, Dec to the pixel coordinates"
 exit 1
fi
if [ -z "$PIXEL_POSITION_TO_MARK" ] || [ " " = "$PIXEL_POSITION_TO_MARK" ] ;then
 echo "ERROR converting RA, Dec to the pixel coordinates (empty result)"
 exit 1
fi

############ Make plot without the FoV string ############
echo "Plotting the finder chart without the field of view label"
# Make the PNG finding chart
COMMAND="util/make_finding_chart  --width $PIXELS_AROUND_TARGET --nolabels --datestringinsideimg -- resample_$FITSFILE $PIXEL_POSITION_TO_MARK "
echo $COMMAND
$COMMAND
if [ $? -ne 0 ];then
 echo "ERROR running util/make_finding_chart"
 exit 1
fi
if [ ! -s pgplot.png ];then
 echo "ERROR: the output image pgplot.png does not exist or is empty"
 exit 1
fi
# Everything is fine
PIXEL_POSITION_TO_MARK_FOR_PNG=${PIXEL_POSITION_TO_MARK//" "/_}
FITSFILE_NAME_FOR_PNG=${FITSFILE//./_}
mv -v "pgplot.png" resample_"$FITSFILE_NAME_FOR_PNG"__"$PIXEL_POSITION_TO_MARK_FOR_PNG"pix_nofov.png


############ Make plot with the FoV string ############
echo "Plotting the finder chart with the field of view label"
# Make the PNG finding chart
COMMAND="util/make_finding_chart  --width $PIXELS_AROUND_TARGET --nolabels --datestringinsideimg --imgsizestringinsideimg -- resample_$FITSFILE $PIXEL_POSITION_TO_MARK "
echo $COMMAND
$COMMAND
if [ $? -ne 0 ];then
 echo "ERROR running util/make_finding_chart"
 exit 1
fi
if [ ! -s pgplot.png ];then
 echo "ERROR: the output image pgplot.png does not exist or is empty"
 exit 1
fi
# Everything is fine
PIXEL_POSITION_TO_MARK_FOR_PNG=${PIXEL_POSITION_TO_MARK//" "/_}
FITSFILE_NAME_FOR_PNG=${FITSFILE//./_}
mv -v "pgplot.png" resample_"$FITSFILE_NAME_FOR_PNG"__"$PIXEL_POSITION_TO_MARK_FOR_PNG"pix.png

# Note that you may combine multiple images side-by-side using something like
# montage resample_wcs_Sco3_20*png -tile 3x2 -geometry +0+0 out.png


###################################################################
# Make a set of finding charts with different scales

for PIXELS_AROUND_TARGET in 32 64 128 256 512 1024 ;do

 echo "Plotting the finder chart with the field of view label"
 # Make the PNG finding chart
 COMMAND="util/make_finding_chart  --width $PIXELS_AROUND_TARGET --nolabels --targetmark --datestringinsideimg --imgsizestringinsideimg resample_$FITSFILE $PIXEL_POSITION_TO_MARK "
 echo $COMMAND
 if [ ! -z "$4" ];then
  $COMMAND --namelabel "$4"
 else
  $COMMAND
 fi
 if [ $? -ne 0 ];then
  echo "ERROR running util/make_finding_chart"
  exit 1
 fi
 if [ ! -s pgplot.png ];then
  echo "ERROR: the output image pgplot.png does not exist or is empty"
  exit 1
 fi
 # Everything is fine
 PIXEL_POSITION_TO_MARK_FOR_PNG=${PIXEL_POSITION_TO_MARK//" "/_}
 FITSFILE_NAME_FOR_PNG=${FITSFILE//./_}
 mv -v "pgplot.png" finder_"$PIXELS_AROUND_TARGET"pix_resample_"$FITSFILE_NAME_FOR_PNG"__"$PIXEL_POSITION_TO_MARK_FOR_PNG"pix.png

done
