#!/usr/bin/env bash
#
# This script will search for transients in a single field.
# The field should be imaged four times: two first-epoch and two second-epoch images should be present
# Run VaST like this before starting the script:
# ./vast -x99 -u -f -k /data/first_epoch_image_1.fit /data/first_epoch_image_2.fit /data/second_epoch_image_1.fit /data/second_epoch_image_2.fit
#


# Check if candidates-transients.lst is not empty
if [ ! -s candidates-transients.lst ];then
 echo "candidates-transients.lst is empty!" >> /dev/stderr
 exit 1
fi

# This script should take care of updating astorb.dat
lib/update_offline_catalogs.sh all

# Plate-solve all images
for i in `cat vast_image_details.log |awk '{print $17}'` ;do 
 util/wcs_image_calibration.sh $i &
# Moved the following check outside this loop
# if [ $? -ne 0 ];then
#  echo "ERROR plate solving $i" >> /dev/stderr
#  exit 1 # Makes no sence to go on if not all images were plate-solved
# fi
done

# whait for all the plate solving tasks to finish
wait

# Check if all the images are solved
for i in `cat vast_image_details.log |awk '{print $17}'` ;do
 ls wcs_`basename $i`
 if [ $? -ne 0 ];then
  echo "ERROR plate solving $i" >> /dev/stderr
  exit 1 # Makes no sence to go on if not all images were plate-solved
 fi
done

# Remove old report files
rm -f transient_report/*

# Calibrate magnitude scale using Tycho-2
util/transients/calibrate_current_field_with_tycho2.sh

# Filter-out faint candidates
for i in `cat candidates-transients.lst | awk '{print $1}'` ;do 
 A=`tail -n2 $i | awk '{print $2}'` 
 #### The limiting magnitude is HARDCODED HERE!!! ####
 TEST=`echo ${A/\n/} | awk '{print ($1+$2)/2">13.5"}'|bc -ql`
 if [ -z "$TEST" ];then
  echo "ERROR in $0 
  cannot run 
echo ${A/\n/} | awk '{print (\$1+\$2)/2\">13.5\"}'|bc -ql
" >> /dev/stderr
  continue
 fi
 # the test below will fail if $TEST is not set
 if [ $TEST -eq 0 ];then 
  grep $i candidates-transients.lst 
 fi
done > candidates-transients.tmp 
mv candidates-transients.tmp candidates-transients.lst

# Prepare the transient search report as an HTML page
echo "<HTML>" > transient_report/index.html
util/transients/make_report_in_HTML.sh
echo "</HTML>" >> transient_report/index.html

# View the transient search report in a web-browser
#firefox file://$PWD/transient_report/index.html &
lib/start_web_browser.sh file://$PWD/transient_report/index.html
