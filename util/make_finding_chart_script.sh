#!/usr/bin/env bash

# Specify how many pixels around the target you want to display
# (how big the standard finding chart should be)
PIXELS_AROUND_TARGET=32

# Tweak the util/make_finding_chart command line options below
# to switch on/off the display of observing date and image size
############################################

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

RESAMPLED_IMAGE_NAME="r_$(basename $FITSFILE)"
RESAMPLED_WEIGHTS_NAME="r_weights_$(basename $FITSFILE)"

# Resample the image to the new grid
swarp -SUBTRACT_BACK N -IMAGEOUT_NAME "$RESAMPLED_IMAGE_NAME" -WEIGHTOUT_NAME "$RESAMPLED_WEIGHTS_NAME" "$FITSFILE"
if [ $? -ne 0 ];then
 echo "ERROR running swarp"
 exit 1
fi
#mv -v coadd.fits "$RESAMPLED_IMAGE_NAME"

# Solve the image again in attempt to mitigate this SIP vs TPV nonsesnse
util/wcs_image_calibration.sh "$RESAMPLED_IMAGE_NAME"
if [ -f wcs_"$RESAMPLED_IMAGE_NAME" ];then
 mv -vf wcs_"$RESAMPLED_IMAGE_NAME" "$RESAMPLED_IMAGE_NAME"
fi

# Get the pixel position we want to mark
PIXEL_POSITION_TO_MARK=`lib/bin/sky2xy "$RESAMPLED_IMAGE_NAME" $TARGET_RA $TARGET_DEC | awk '{print $5" "$6}'`
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
COMMAND="util/make_finding_chart  --width $PIXELS_AROUND_TARGET --nolabels --datestringinsideimg -- $RESAMPLED_IMAGE_NAME $PIXEL_POSITION_TO_MARK "
echo $COMMAND
$COMMAND
if [ $? -ne 0 ];then
 echo "ERROR running util/make_finding_chart"
 exit 1
fi
# multiple make_finding_chart scripts cannot work in parallell !!!
MAKE_FINDING_CHART_OUTPUT_PNG="$(basename ${RESAMPLED_IMAGE_NAME%.*}).png"
if [ ! -s "$MAKE_FINDING_CHART_OUTPUT_PNG" ];then
#if [ ! -s pgplot.png ];then
 echo "ERROR: the output image pgplot.png does not exist or is empty"
 exit 1
fi
# Everything is fine
PIXEL_POSITION_TO_MARK_FOR_PNG=${PIXEL_POSITION_TO_MARK//" "/_}
FITSFILE_NAME_FOR_PNG="r_$(basename "$FITSFILE")"
FITSFILE_NAME_FOR_PNG=${FITSFILE_NAME_FOR_PNG//./_}
#mv -v "pgplot.png" "$FITSFILE_NAME_FOR_PNG"__"$PIXEL_POSITION_TO_MARK_FOR_PNG"pix_nofov.png
mv -v "$MAKE_FINDING_CHART_OUTPUT_PNG" "$FITSFILE_NAME_FOR_PNG"__"$PIXEL_POSITION_TO_MARK_FOR_PNG"pix_nofov.png


############ Make plot with the FoV string ############
echo "Plotting the finder chart with the field of view label"
# Make the PNG finding chart
COMMAND="util/make_finding_chart  --width $PIXELS_AROUND_TARGET --nolabels --datestringinsideimg --imgsizestringinsideimg -- $RESAMPLED_IMAGE_NAME $PIXEL_POSITION_TO_MARK "
echo $COMMAND
$COMMAND
if [ $? -ne 0 ];then
 echo "ERROR running util/make_finding_chart"
 exit 1
fi
if [ ! -s "$MAKE_FINDING_CHART_OUTPUT_PNG" ];then
#if [ ! -s pgplot.png ];then
 echo "ERROR: the output image pgplot.png does not exist or is empty"
 exit 1
fi
# Everything is fine
#PIXEL_POSITION_TO_MARK_FOR_PNG=${PIXEL_POSITION_TO_MARK//" "/_}
#FITSFILE_NAME_FOR_PNG=${FITSFILE//./_}
mv -v "$MAKE_FINDING_CHART_OUTPUT_PNG" "$FITSFILE_NAME_FOR_PNG"__"$PIXEL_POSITION_TO_MARK_FOR_PNG"pix.png

# Note that you may combine multiple images side-by-side using something like
# montage r_wcs_Sco3_20*png -tile 3x2 -geometry +0+0 out.png


###################################################################
# Make a set of finding charts with different scales

for PIXELS_AROUND_TARGET in 20 32 64 128 256 512 ;do

 STR_PIXELS_AROUND_TARGET=$(echo "$PIXELS_AROUND_TARGET" | awk '{printf "%04d", $1}')

 echo "Plotting the finder chart with the field of view label"
 # Make the PNG finding chart
 COMMAND="util/make_finding_chart  --width $PIXELS_AROUND_TARGET --nolabels --targetmark --datestringinsideimg --imgsizestringinsideimg $RESAMPLED_IMAGE_NAME $PIXEL_POSITION_TO_MARK "
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
 if [ ! -s "$MAKE_FINDING_CHART_OUTPUT_PNG" ];then
# if [ ! -s pgplot.png ];then
  echo "ERROR: the output image pgplot.png does not exist or is empty"
  exit 1
 fi
 # Everything is fine
 #PIXEL_POSITION_TO_MARK_FOR_PNG=${PIXEL_POSITION_TO_MARK//" "/_}
 #FITSFILE_NAME_FOR_PNG=${FITSFILE//./_}
 mv -v "$MAKE_FINDING_CHART_OUTPUT_PNG" finder_"$STR_PIXELS_AROUND_TARGET"pix_"$FITSFILE_NAME_FOR_PNG"__"$PIXEL_POSITION_TO_MARK_FOR_PNG"pix.png
 # make the _nofov version
 COMMAND="util/make_finding_chart  --width $PIXELS_AROUND_TARGET --nolabels --targetmark --datestringinsideimg $RESAMPLED_IMAGE_NAME $PIXEL_POSITION_TO_MARK "
 echo $COMMAND
 $COMMAND
 mv -v "$MAKE_FINDING_CHART_OUTPUT_PNG" finder_"$STR_PIXELS_AROUND_TARGET"pix_"$FITSFILE_NAME_FOR_PNG"__"$PIXEL_POSITION_TO_MARK_FOR_PNG"pix_nofov.png
 # make the _nofov_notargetmark version
 COMMAND="util/make_finding_chart  --width $PIXELS_AROUND_TARGET --nolabels --datestringinsideimg $RESAMPLED_IMAGE_NAME $PIXEL_POSITION_TO_MARK "
 echo $COMMAND
 $COMMAND
 mv -v "$MAKE_FINDING_CHART_OUTPUT_PNG" finder_"$STR_PIXELS_AROUND_TARGET"pix_"$FITSFILE_NAME_FOR_PNG"__"$PIXEL_POSITION_TO_MARK_FOR_PNG"pix_nofov_notargetmark.png
 # make the _notargetmark version
 COMMAND="util/make_finding_chart  --width $PIXELS_AROUND_TARGET --nolabels --datestringinsideimg --imgsizestringinsideimg $RESAMPLED_IMAGE_NAME $PIXEL_POSITION_TO_MARK "
 echo $COMMAND
 $COMMAND
 mv -v "$MAKE_FINDING_CHART_OUTPUT_PNG" finder_"$STR_PIXELS_AROUND_TARGET"pix_"$FITSFILE_NAME_FOR_PNG"__"$PIXEL_POSITION_TO_MARK_FOR_PNG"pix_notargetmark.png

done
