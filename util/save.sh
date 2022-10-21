#!/usr/bin/env bash
#
# This small script will create a new directory named REGION_NAME and save the current VaST work to it.
# To resume work with the current field, just copy all files from the directory REGION_NAME to to the
# VaST directory and run ./find_candidates aa
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ ! -z $1 ];then
 REGION_NAME="$1""$2""$3""$4""$5"
else
 echo "Region name?"
 read REGION_NAME
fi

# Remove white spaces if any
REGION_NAME=${REGION_NAME//" "/""}
# Remove trainling slash '/' if htere is one
REGION_NAME=`basename $REGION_NAME`

if [ -d "$REGION_NAME" ];then
 echo "ERROR: the directory $REGION_NAME already exist. Please pick another name!"
 exit 1
fi

echo -n "Creating directory $REGION_NAME ... "
mkdir "$REGION_NAME"
if [ $? = 0 ];then
 echo "OK"
else
 echo "ERROR: Can't create directory $REGION_NAME"
 exit 1
fi

if [ ! -d "$REGION_NAME" ];then
 echo "ERROR: Can't open directory $REGION_NAME"
 exit 1
fi

for WCS_IMAGE in wcs_* ;do
 if [ -f $WCS_IMAGE ];then
  echo -n "Saving WCS-calibrated image/catalog  $WCS_IMAGE ... "
  mv $WCS_IMAGE "$REGION_NAME" && echo "OK"
 fi
done

# For compatibility with an ancient matching technique.
# The wcs.fit file is produced by ./pgfv match
if [ -f wcs.fit ];then
 echo -n "Saving wcs.fit ... "
 mv wcs.fit "$REGION_NAME" && echo "OK"
fi
 
if [ -f calib.txt ];then
 echo -n "Saving calib.txt ... "
 mv calib.txt "$REGION_NAME" && echo "OK"
fi
if [ -f calib.txt_param ];then
 echo -n "Saving calib.txt_param ... "
 mv calib.txt_param "$REGION_NAME" && echo "OK"
fi
if [ -d vast_magnitude_calibration_details_log ];then
 echo -n "Saving vast_magnitude_calibration_details_log ... "
 mv vast_magnitude_calibration_details_log/ "$REGION_NAME" && echo "OK"
fi

if [ -d symlinks_to_images ];then
 echo -n "Saving symlinks_to_images ... "
 mv symlinks_to_images/ "$REGION_NAME" && echo "OK"
fi

if [ -f vast_summary.log ];then
 echo -n "Saving" `grep "SExtractor parameter file:" vast_summary.log |awk '{print $4}'`" ... " 
 SEXTRACTOR_PARAMETER_FILE=`grep "SExtractor parameter file:" vast_summary.log |awk '{print $4}'`
 cp "$SEXTRACTOR_PARAMETER_FILE" "$REGION_NAME" && echo "OK"
 echo -n "Saving default.psfex ... " 
 cp default.psfex "$REGION_NAME" && echo "OK"
 CONVOLUTION_FILE=`grep .conv "$SEXTRACTOR_PARAMETER_FILE" | awk '{print $1" "$2}' | grep -v \# | grep '.conv' | head -n1 | awk '{print $2}'`
 echo -n "Saving $CONVOLUTION_FILE ... "
 cp "$CONVOLUTION_FILE" "$REGION_NAME" && echo "OK"
else
 echo "Not saving default.sex and default.psfex - assuming this is some kind of imported data since there is no vast_summary.log"
fi

for SPECIAL_FILE_TO_COPY in manually_selected_comparison_stars.lst manually_selected_aperture.txt exclude.lst bad_region.lst ;do
 if [ -f "$SPECIAL_FILE_TO_COPY" ];then
  cp -v "$SPECIAL_FILE_TO_COPY" "$REGION_NAME"/
 fi
done

#echo -n "Saving the program source code ... "
#cp -r src/ "$REGION_NAME"/vast_src_"$REGION_NAME" && echo "OK"

# Save the VaST settings file for the record
cp src/vast_limits.h "$REGION_NAME"_saved_limits.h ; mv "$REGION_NAME"_saved_limits.h "$REGION_NAME"/

if [ -d candidates_report/ ];then
 mv candidates_report/ "$REGION_NAME"/
fi

echo -n "Saving the lightcurves and the other files ... "
for i in vast_input_user_specified_moving_object_position.txt vast_list_of_input_images_with_time_corrections.txt vast_list_of_FITS_keywords_to_record_in_lightcurves.txt vast_list_of_all_stars.ds9.reg out*dat candidates*lst data* vast*.log sysrem_input_star_list.lst ref_frame_sextractor.cat aavso_* image*.cat*  vast_index_vs_mag*.txt vast_index_vs_mag*.eps ;do 
 if [ -f $i ];then
  mv $i "$REGION_NAME" 
 fi
done && echo -e "OK\nAll data and processing parameters saved!\nTo restore them use:\n util/load.sh $REGION_NAME" && exit 0

echo "Something is wrong..."
exit 1
