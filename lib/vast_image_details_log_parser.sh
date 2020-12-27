#!/usr/bin/env bash
#
# This script will parse vast_image_details.log and generate a stub vast_summary.log
# It is not intended to be run by a user, the main vast program will start it automatically...
#
LAST_JD=0
FIRST_JD=9953219
IS_REF_IMAGE=1
# Fix the log (just in case it was if broken)
if [ ! -f vast_image_details.log ];then
 echo "WARNING! Something is terribly wrong: the log file vast_image_details.log is not found."
 exit
fi
lib/fix_photo_log < vast_image_details.log > tmp.log
mv -f tmp.log vast_image_details.log
#
if [ ! -f vast_image_details.log ];then
 echo "WARNING! Something is terribly wrong: the log file vast_image_details.log is not found."
 exit
fi
#############################
# See if we need to exclude the reference image
# We'll know that by parsing command line or by looking for a designated log file
EXCLUDE_REF_IMAGE=0
cat vast_command_line.log | grep --quiet -e ' --excluderefimage ' -e ' -8 '
if [ $? -eq 0 ];then
 EXCLUDE_REF_IMAGE=1
fi
if [ -f vast_exclude_reference_image.log ];then
 EXCLUDE_REF_IMAGE=1
fi
#############################
while read exp_start_name exp_start_date exp_start_time exp_name exp JD_name JD ap_name ap rotation_name rotation detected_name detected matched_name matched status  filename ;do
 if [ $IS_REF_IMAGE -eq 1 ];then
  if [ -f vast_automatically_selected_reference_image.log ];then
   # An alternate reference image was selected by the program
   REF_IMAGE_NAME=`cat vast_automatically_selected_reference_image.log`
   if [ "$filename" == "$REF_IMAGE_NAME" ];then
    IS_REF_IMAGE=0
    JD_REF=$JD
    exp_start_date_ref=$exp_start_date
    exp_start_time_ref=$exp_start_time
    # This is to make sure JD_REF matches filename_ref
    filename_ref=$filename
   fi
  else
   # The first image in the log file is the reference one
   IS_REF_IMAGE=0
   JD_REF=$JD
   exp_start_date_ref=$exp_start_date
   exp_start_time_ref=$exp_start_time
   filename_ref=$filename
  fi # if [ -f vast_automatically_selected_reference_image.log ];then
 fi
 #
 if [ "$status" != "status=OK" ];then
  continue
 fi
 #
 if [ $EXCLUDE_REF_IMAGE -eq 1 ];then
  if [ "$filename" == "$filename_ref" ];then
   continue
  fi
 fi
 #
 if [ "$JD" != "0.000000" ];then
  #TEST=`echo "$JD < $FIRST_JD"|bc -ql`
  TEST=`echo "$JD<$FIRST_JD"| awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
  if [ $TEST -eq 1 ];then
   FIRST_JD=$JD
   exp_start_date_first=$exp_start_date
   exp_start_time_first=$exp_start_time
   filename_first=$filename
  fi
  #TEST=`echo "$JD > $LAST_JD"|bc -ql`
  TEST=`echo "$JD>$LAST_JD" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
  if [ $TEST -eq 1 ];then
   LAST_JD=$JD
   exp_start_date_last=$exp_start_date
   exp_start_time_last=$exp_start_time
   filename_last=$filename
  fi
 fi
done < vast_image_details.log
echo -n "Images processed " ; grep -c JD vast_image_details.log
echo -n "Images used for photometry " ; grep -c OK vast_image_details.log
echo  "Ref.  image: $JD_REF $exp_start_date_ref $exp_start_time_ref   $filename_ref"
echo  "First image: $FIRST_JD $exp_start_date_first $exp_start_time_first   $filename_first"
echo  "Last  image: $LAST_JD $exp_start_date_last $exp_start_time_last   $filename_last" 
