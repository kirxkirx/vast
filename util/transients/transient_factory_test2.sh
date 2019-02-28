#!/usr/bin/env bash

#
# This script is an example of how an automated transient-detection pipeline may be set up using VaST.
# Note, that in this example there are two reference and two second-epoch images.
# The results will be presented as an HTML page transient_report/index.html
#

REFERENCE_IMAGES=/home/kirx/reference_images


echo "Reference image directory is set to $REFERENCE_IMAGES"
if [ -z $1 ]; then
 echo "Usage: $0 PATH_TO_DIRECTORY_WITH_IMAGE_PAIRS"
 exit
fi
NEW_IMAGES=$1

rm -f transient_report/* transient_factory.log
echo "<HTML>" >> transient_report/index.html

for i in "$NEW_IMAGES"/*_001.fts ;do
 STR=`basename $i _001.fts` 
 FIELD=`echo ${STR:0:8}`
 # check if all images are actually there
 if [ ! -f $REFERENCE_IMAGES/*$FIELD*_002.fts ];then 
  echo "Script ERROR! Cannot find image $REFERENCE_IMAGES/*$FIELD*_002.fts"
  continue
 fi
 if [ ! -f $NEW_IMAGES/*$FIELD*_001.fts ];then 
  echo "Script ERROR! Cannot find image $NEW_IMAGES/*$FIELD*_001.fts"
  continue
 fi
 if [ ! -f $NEW_IMAGES/*$FIELD*_002.fts ];then 
  echo "Script ERROR! Cannot find image $NEW_IMAGES/*$FIELD*_002.fts"
  continue
 fi
 # Run VaST
 ./vast -x99 -u -f -k $REFERENCE_IMAGES/*$FIELD* $NEW_IMAGES/*$FIELD*
 cat vast_summary.log >> transient_factory.log
 # Check if the number of detected transients is suspiciously large
 NUMBER_OF_DETECTED_TRANSIENTS=`cat vast_summary.log |grep "Transient candidates found:" | awk '{print $4}'`
 if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt 200 ];then
  echo "WARNING! Too many candidates... Skipping field..."
  continue
 fi
 if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt 50 ];then
  echo "WARNING! Too many candidates... Dropping flares..."
  # if yes, remove flares, keep only new objects
  while reaf FLAREOUTFILE A B ;do
   grep -v $FLAREOUTFILE candidates-transients.lst > candidates-transients.tmp
   mv candidates-transients.tmp candidates-transients.lst
  done < candidates-flares.lst
 fi
 # WCS-calibration
 for i in `cat vast_image_details.log |awk '{print $17}'` ;do 
  util/wcs_image_calibration.sh $i 120 
  if [ ! -f wcs_`basename $i` ];then
   for N_RETRY_WCS in `seq 1 3` ;do
    echo "WARNING!!! WCS-calibrated file was not created! Retrying..."
    sleep 10
    util/wcs_image_calibration.sh $i 120
   done
  fi
 done 
 util/transients/calibrate_current_field_with_tycho2.sh 
 util/transients/make_report_in_HTML.sh #$FIELD
 #echo $FIELD
 
done

echo "<H2>Processig complete!</H2>" >> transient_report/index.html

echo "<H3>Processing log:</H3>" >> transient_report/index.html
echo "<pre>" >> transient_report/index.html
cat transient_factory.log >> transient_report/index.html
echo "</pre>" >> transient_report/index.html

echo "</HTML>" >> transient_report/index.html
