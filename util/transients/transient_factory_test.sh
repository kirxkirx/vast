#!/usr/bin/env bash
#REFERENCE_IMAGES=../transients/reference
#REFERENCE_IMAGES=../reference_test
REFERENCE_IMAGES=/mnt/usb/NMW_NG/NMW_reference_images_2012
echo "Reference image directory is set to $REFERENCE_IMAGES"
if [ -z $1 ]; then
# echo "Usage: $0 PATH_TO_DIRECTORY_WITH_IMAGE_PAIRS"
# exit
 NEW_IMAGES=../ultimate_test/
else
 NEW_IMAGES=$1
fi


rm -f transient_report/*
echo "<HTML>" >> transient_report/index.html

#for i in "$NEW_IMAGES"/*_001.fit ;do
# assuming filenames like Cas5_2017-11-20_23-2-32_001.fts
for i in "$NEW_IMAGES"/* ;do
 FIELDNAME=`basename "$i"`
 FIELDNAME=`echo "$FIELDNAME" | awk '{print $1}' FS='_'`
 echo "$FIELDNAME"
done | sort | uniq | while read FIELD ;do
 #STR=`basename $i _001.fit` 
 #FIELD=`echo ${STR: -13}`
 #./vast -x2 -a7 -u -f -m $REFERENCE_IMAGES/*$FIELD* $NEW_IMAGES/*$FIELD* &&  util/transients/calibrate_current_field_with_tycho2.sh && util/transients/make_report_in_HTML.sh
 #./vast -x99 -a7 -u -f -m $REFERENCE_IMAGES/*$FIELD* $NEW_IMAGES/*$FIELD* 
 ./vast -x99 -u -f "$REFERENCE_IMAGES"/*"$FIELD"_* "$NEW_IMAGES"/*"$FIELD"_* 
 #exit # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 for j in `cat vast_image_details.log |awk '{print $17}'` ;do util/wcs_image_calibration.sh $j ;done
 util/transients/calibrate_current_field_with_tycho2.sh
 util/transients/make_report_in_HTML.sh
done

echo "</HTML>" >> transient_report/index.html
