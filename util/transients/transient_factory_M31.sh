#!/usr/bin/env bash
#REFERENCE_IMAGES=../transients/reference
REFERENCE_IMAGES=/mnt/usb/transients/reference
echo "Reference image directory is set to $REFERENCE_IMAGES"
if [ -z $1 ]; then
 echo "Usage: $0 PATH_TO_DIRECTORY_WITH_IMAGE_PAIRS"
 exit
fi
NEW_IMAGES=$1

rm -f transient_report/*
echo "<HTML>" >> transient_report/index.html

for i in "$NEW_IMAGES"/*_001.fit ;do
 STR=`basename $i _001.fit` 
 FIELD=`echo ${STR: -13}`
 #./vast -x2 -a7 -u -f -m $REFERENCE_IMAGES/*$FIELD* $NEW_IMAGES/*$FIELD* &&  util/transients/calibrate_current_field_with_tycho2.sh && util/transients/make_report_in_HTML.sh
 ./vast -x2 -u -f $REFERENCE_IMAGES/*$FIELD* $NEW_IMAGES/*$FIELD* && util/transients/make_report_in_HTML.sh
done

echo "</HTML>" >> transient_report/index.html
