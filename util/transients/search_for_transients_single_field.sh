#!/usr/bin/env bash
#
# This script will search for transients in a single field.
# The field should be imaged four times: two first-epoch and two second-epoch images should be present
# Run VaST like this before starting the script:
# ./vast -x99 -u -f -k /data/first_epoch_image_1.fit /data/first_epoch_image_2.fit /data/second_epoch_image_1.fit /data/second_epoch_image_2.fit
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

TEST_MODE=0
if [ "$1" = "test" ];then
 # Do not start the browser if this is a test run
 TEST_MODE=1
fi

# Check if candidates-transients.lst is not empty
if [ ! -s candidates-transients.lst ];then
 echo "candidates-transients.lst is empty!" 1>&2
 exit 1
fi

# Check if we are expected to produce PNG images or just text
MAKE_PNG_PLOTS="yes"
if [ -x lib/test_libpng_justtest_nomovepgplot.sh ];then
 lib/test_libpng_justtest_nomovepgplot.sh
 if [ $? -ne 0 ];then
  MAKE_PNG_PLOTS="no"
 fi
fi
export MAKE_PNG_PLOTS

# This script should take care of updating astorb.dat
lib/update_offline_catalogs.sh all

# This should disable Gaia DR2 search for transient candidates performed by util/transients/report_transient.sh
unset VIZIER_SITE

# Plate-solve all images
for i in `cat vast_image_details.log |awk '{print $17}'` ;do 
 # 
 util/wcs_image_calibration.sh $i &
 # Replace the above line with the line below to enable local astrometric corrections.
 # This will result in better astrometry but will take more time to compute.
 # (The slow part is communicating with VizieR.)
 # util/solve_plate_with_UCAC5 $i &
 #
 #
 # Moved the following check outside this loop
 # if [ $? -ne 0 ];then
 #  echo "ERROR plate solving $i" 1>&2
 #  exit 1 # Makes no sence to go on if not all images were plate-solved
 # fi
done

# whait for all the plate solving tasks to finish
wait

# Check if all the images are solved
for i in `cat vast_image_details.log |awk '{print $17}'` ;do
 ls wcs_`basename $i`
 if [ $? -ne 0 ];then
  echo "ERROR plate solving $i" 1>&2
  exit 1 # Makes no sence to go on if not all images were plate-solved
 fi
done

# Remove old report files
rm -f transient_report/*

# Calibrate magnitude scale using Tycho-2
util/transients/calibrate_current_field_with_tycho2.sh

# Filter-out faint candidates
for i in `cat candidates-transients.lst | awk '{print $1}'` ;do 
 MAG_ON_FIRST_SECOND_EPOCH_IMAGE=`tail -n2 $i | head -n1 | awk '{print $2}'`
 MAG_ON_SECOND_SECOND_EPOCH_IMAGE=`tail -n1 $i | awk '{print $2}'`
 #### The limiting magnitude is HARDCODED HERE!!! ####
 #TEST=`echo ${A/\n/} | awk '{print ($1+$2)/2">13.5"}'`
 #echo "################### DEBUG ${A/\n/} ###################"
 #     !!!!!!!!!!!! HARDCODED MAGNITUDE LIMIT !!!!!!!!!!!!
 TEST=`echo "$MAG_ON_FIRST_SECOND_EPOCH_IMAGE $MAG_ON_SECOND_SECOND_EPOCH_IMAGE" | awk '{if ( ($1+$2)/2 > 13.5 ) print 1 ;else print 0 }'`
 if [ -z "$TEST" ];then
  echo "ERROR in $0 
  cannot run 
echo $MAG_ON_FIRST_SECOND_EPOCH_IMAGE $MAG_ON_SECOND_SECOND_EPOCH_IMAGE | awk '{print (\$1+\$2)/2\">13.5\"}'
" 1>&2
  continue
 fi
 # the test below will fail if $TEST is not set
 if [ $TEST -eq 0 ];then 
  grep $i candidates-transients.lst 
 fi
done > candidates-transients.tmp 
mv candidates-transients.tmp candidates-transients.lst

######################################################################################################################################
####### util/transients/make_report_in_HTML.sh will not report candidate transients listed in the following files              #######
####### ../exclusion_list.txt lib/catalogs/bright_star_catalog_radeconly.txt lib/catalogs/list_of_bright_stars_from_tycho2.txt #######
######################################################################################################################################
### Prepare the exclusion lists for this field
# Exclude the previously considered candidates
if [ -f ../exclusion_list.txt ];then
 SECOND_EPOCH_IMAGE_ONE=`cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1`
 WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE=wcs_`basename $SECOND_EPOCH_IMAGE_ONE`
 lib/bin/sky2xy $WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE @../exclusion_list.txt | grep -v -e 'off image' -e 'offscale' | awk '{print $1" "$2}' > exclusion_list.txt
fi
# Exclude stars from the Bright Star Catalog with magnitudes < 7
if [ -f lib/catalogs/bright_star_catalog_radeconly.txt ];then
 SECOND_EPOCH_IMAGE_ONE=`cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1`
 WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE=wcs_`basename $SECOND_EPOCH_IMAGE_ONE`
 lib/bin/sky2xy $WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE @lib/catalogs/bright_star_catalog_radeconly.txt | grep -v -e 'off image' -e 'offscale' | awk '{print $1" "$2}' > exclusion_list_bsc.txt
fi
# Exclude bright Tycho-2 stars, by default the magnitude limit is set to vt < 9
if [ -f lib/catalogs/list_of_bright_stars_from_tycho2.txt ];then
 SECOND_EPOCH_IMAGE_ONE=`cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1`
 WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE=wcs_`basename $SECOND_EPOCH_IMAGE_ONE`
 lib/bin/sky2xy $WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE @lib/catalogs/list_of_bright_stars_from_tycho2.txt | grep -v -e 'off image' -e 'offscale' | awk '{print $1" "$2}' | while read A ;do lib/deg2hms $A ;done > exclusion_list_tycho2.txt
fi
###
# We need a local exclusion list for multiple SExtractor runs on the same field.
# This file should not be present if we do single-run analysis
if [ -f exclusion_list_local.txt ];then
 rm -f exclusion_list_local.txt
fi
# This file is for including Gaia DR2 matches to the exclusio list (not used in this script)
if [ -f exclusion_list_gaiadr2.txt ];then
 rm -f exclusion_list_gaiadr2.txt
fi
######################################################################################################################################
######################################################################################################################################

# Prepare the transient search report as an HTML page
echo "<HTML>" > transient_report/index.html
util/transients/make_report_in_HTML.sh
echo "</HTML>" >> transient_report/index.html

if [ $TEST_MODE -ne 1 ];then
 # View the transient search report in a web-browser
 #firefox file://$PWD/transient_report/index.html &
 lib/start_web_browser.sh file://$PWD/transient_report/index.html
fi
