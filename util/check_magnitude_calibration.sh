#!/usr/bin/env bash
if [ ! -d vast_magnitude_calibration_details_log/ ];then
 echo "Can't open vast_magnitude_calibration_details_log/ "
 exit
fi
for i in vast_magnitude_calibration_details_log/*.calib ;do
 grep `basename $i .calib` vast_image_details.log | awk '{print $17}'
 lib/fit_mag_calib "$i" "$i"_param
done
