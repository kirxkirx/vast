#!/usr/bin/env bash

# THIS IS A FROZEN VERSION OF THE SCRIPT USED FOR BACKWARD_COMPATIBILITY TESTING
# by util/examples/test_NMW.sh test script. 
# Please refer to a newer version of transient_factory_* that should be found in the same directory.

#
# This script is an example of how an automated transient-detection pipeline may be set up using VaST.
# Note, that in this example there are two reference and two second-epoch images.
# The results will be presented as an HTML page transient_report/index.html
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Set the directory with reference images
# You may set a few alternative locations, but only the first one that exist will be used
if [ -z "$REFERENCE_IMAGES" ];then
 REFERENCE_IMAGES=/mnt/usb/NMW_NG/NMW_reference_images_2012
 if [ ! -d "$REFERENCE_IMAGES" ];then
  REFERENCE_IMAGES=/dataX/kirx/NMW_reference_images_2012 
 fi
 if [ ! -d "$REFERENCE_IMAGES" ];then
  REFERENCE_IMAGES=/dataY/kirx/NMW_reference_images_2012 
 fi
 if [ ! -d "$REFERENCE_IMAGES" ];then
  REFERENCE_IMAGES=/home/kirx/current_work/NMW_crashtest/ref 
 fi
fi

if [ ! -d "$REFERENCE_IMAGES" ];then
 echo "ERROR: cannot find the reference image directory REFERENCE_IMAGES=$REFERENCE_IMAGES"
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

# Set the SExtractor parameters file
cp default.sex.telephoto_lens_v3 default.sex

echo "Reference image directory is set to $REFERENCE_IMAGES"
if [ -z $1 ]; then
 echo "Usage: $0 PATH_TO_DIRECTORY_WITH_IMAGE_PAIRS"
 exit
fi


if [ ! -d transient_report ];then
 mkdir transient_report
fi

rm -f transient_report/* transient_factory.log
echo "<HTML>

<script type='text/javascript'>
function toggleElement(id)
{
    if(document.getElementById(id).style.display == 'none')
    {
        document.getElementById(id).style.display = '';
    }
    else
    {   
        document.getElementById(id).style.display = 'none';
    }
}
</script>

<BODY>" >> transient_report/index.html

# Allow for multiple image directories to be specified on the command line

for NEW_IMAGES in "$@" ;do

LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR=`for IMGFILE in "$NEW_IMAGES"/*.fts ;do basename "$IMGFILE" ;done | awk '{print $1}' FS='_' | sort | uniq`

echo "Fields in the data directory: 
$LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR"

#exit # !!!

PREVIOUS_FIELD="none"
#for i in "$NEW_IMAGES"/*_001.fts ;do
for FIELD in $LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR ;do
 #STR=`basename $i _001.fts` 
 #FIELD=`echo ${STR:0:8}`
 #FIELD=`echo $FIELD | awk '{print $1}' FS='_'`
 if [ "$FIELD" == "$PREVIOUS_FIELD" ];then
  echo "Script ERROR! This field has been processed before!"
  continue
 fi
 PREVIOUS_FIELD="$FIELD"
 ############## Two reference images and two second-epoch images # check if all images are actually there
 # check if all images are actually there
 N=`ls "$REFERENCE_IMAGES"/*"$FIELD"_*_*.fts | wc -l`
 if [ $N -lt 2 ];then
  echo "ERROR: to few refereence images for the field $FIELD"
  continue
 fi
 N=`ls "$NEW_IMAGES"/*"$FIELD"_*_*.fts | wc -l`
 if [ $N -lt 2 ];then
  echo "ERROR: to few refereence images for the field $FIELD"
  continue
 fi
 REFERENCE_EPOCH__FIRST_IMAGE=`ls "$REFERENCE_IMAGES"/*"$FIELD"_*_*.fts | head -n1`
 REFERENCE_EPOCH__SECOND_IMAGE=`ls "$REFERENCE_IMAGES"/*"$FIELD"_*_*.fts | tail -n1`
 SECOND_EPOCH__FIRST_IMAGE=`ls "$NEW_IMAGES"/*"$FIELD"_*_*.fts | head -n1`
 SECOND_EPOCH__SECOND_IMAGE=`ls "$NEW_IMAGES"/*"$FIELD"_*_*.fts | head -n2 | tail -n1`
 # double-check the files
 for FILE_TO_CHECK in "$REFERENCE_EPOCH__FIRST_IMAGE" "$REFERENCE_EPOCH__SECOND_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE" ;do
  ls "$FILE_TO_CHECK" 
  if [ $? -ne 0 ];then
   echo "ERROR opening file $FILE_TO_CHECK" 1>&2
  fi
 done | grep "ERROR opening file"
 if [ $? -eq 0 ];then
  echo "ERROR processing the image series"
  continue
 fi
# # check if all images are actually there
# if [ ! -f $REFERENCE_IMAGES/*"$FIELD"_*_002.fts ];then 
#  echo "Script ERROR! Cannot find image $REFERENCE_IMAGES/*$FIELD*_002.fts"
#  continue
# fi
# if [ ! -f $NEW_IMAGES/*"$FIELD"_*_001.fts ];then 
#  echo "Script ERROR! Cannot find image $NEW_IMAGES/*$FIELD*_001.fts"
#  continue
# fi
# if [ ! -f $NEW_IMAGES/*"$FIELD"_*_002.fts ];then 
#  echo "Script ERROR! Cannot find image $NEW_IMAGES/*$FIELD*_002.fts"
#  continue
# fi
 # Run VaST
 ###./vast -x99 -u -f -k $REFERENCE_IMAGES/*$FIELD* $NEW_IMAGES/*$FIELD*
 ##./vast --selectbestaperture -y1 -p -x99 -u -f -k $REFERENCE_IMAGES/*"$FIELD"_* `ls $NEW_IMAGES/*"$FIELD"_*_001.fts | head -n1` `ls $NEW_IMAGES/*"$FIELD"_*_002.fts | head -n1`
 #./vast --selectbestaperture -y1 -p -x99 -u -f -k "$REFERENCE_EPOCH__FIRST_IMAGE" "$REFERENCE_EPOCH__SECOND_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE"
 ./vast --matchstarnumber 500 --selectbestaperture -y1 -p -x99 -u -f -k "$REFERENCE_EPOCH__FIRST_IMAGE" "$REFERENCE_EPOCH__SECOND_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE"
 cat vast_summary.log >> transient_factory.log
 grep -q 'Images used for photometry 4' vast_summary.log
 if [ $? -ne 0 ];then
  echo "***** IMAGE PROCESSING ERROR *****" >> transient_factory.log
  echo "############################################################" >> transient_factory.log
  continue
 fi
 echo "############################################################" >> transient_factory.log
 
# # Use cache if possible to speed-up WCS calibration
# if [ -d wcscache ];then
#  for i in wcscache/*$FIELD* ;do
#   ln -s $i
#  done
# else
#  mkdir wcscache
# fi
 
 # WCS-calibration
 for i in `cat vast_image_details.log |awk '{print $17}'` ;do 
  # This should ensure the correct field-of-view guess by setting the TELESCOP keyword
  #util/modhead $i TELESCOP NMW_camera
  #
  TELESCOP="NMW_camera" util/wcs_image_calibration.sh $i &
  #TELESCOP="NMW_camera" util/solve_plate_with_UCAC5 $i &
 done 

 # Wait for all children to end processing
 wait
 
 # Check that the plates were actually solved
 for i in `cat vast_image_details.log |awk '{print $17}'` ;do 
  if [ ! -f wcs_`basename $i` ];then
   echo "***** PLATE SOLVE PROCESSING ERROR *****" >> transient_factory.log
   echo "***** cannot find wcs_"`basename $i`"  *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   continue
  fi
 done 
 
 # We need UCAC5 solution for the first and the third images
 util/solve_plate_with_UCAC5 `cat vast_image_details.log | awk '{print $17}' | head -n1 | tail -n1` &
 util/solve_plate_with_UCAC5 `cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1` &
# wait
 
# # Save astrometrically calibrated reference images to cache, if they are not there already
# # Here we assume we have two reference images
# for i in `cat vast_image_details.log | head -n2 |awk '{print $17}'` ;do
#  if [ ! -f wcscache/wcs_`basename $i` ];then
#   # We want to copy both images and catalogs
#   cp wcs_`basename $i`* wcscache/
#  fi
# done
 
 # Calibrate magnitude scale with Tycho-2 stars in the field 
 echo "y" | util/transients/calibrate_current_field_with_tycho2.sh 

 ################## Quality cits applied to calibrated magnitudes of the candidate transients ##################

 echo "Filter-out faint candidates..."
 # Filter-out faint candidates
 #for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2">12.5"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2">13.0"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

 echo "Filter-out candidates with large difference between measured mags in one epoch..."
 # 2nd epoch
 cp candidates-transients.lst DEBUG_BACKUP_candidates-transients.lst
 # Filter-out candidates with large difference between measured mags
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($1-$2)>0.4 ) print 1; else print 0 }'` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 # Filter-out candidates with large difference between measured mags
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($2-$1)>0.4 ) print 1; else print 0 }'` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 # 1st epoch (only for sources detected on two reference images)
 # Filter-out candidates with large difference between measured mags
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do if [ `cat $i | wc -l` -lt 4 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=`head -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($1-$2)>1.0 ) print 1; else print 0 }'` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 # Filter-out candidates with large difference between measured mags
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do if [ `cat $i | wc -l` -lt 4 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=`head -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($2-$1)>1.0 ) print 1; else print 0 }'` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

 ##### THIS IS WHAT I WANT TO REMOVE ##### 
 # replaced by checking the list of bright stars in util/transients/report_transient.sh
 #echo "Filter-out spurious flares of bright stars..."
 ## Filter-out spurious flares of bright stars
 #for i in `cat candidates-transients.lst | awk '{print $1}'` ;do if [ `cat $i | wc -l` -eq 2 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=`head -n1 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($1)<9.0 ) print 1; else print 0 }'` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 #########################################

 echo "Filter-out small-amplitude flares..."
 # Filter-out small-amplitude flares
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do if [ `cat $i | wc -l` -eq 2 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=`head -n1 $i | awk '{print $2}'` ; B=`tail -n2 $i | awk '{print $2}'` ; MEANMAGSECONDEPOCH=`echo ${B//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2}'` ; TEST=`echo $A $MEANMAGSECONDEPOCH | awk '{if ( ($1-$2)<0.5 ) print 1; else print 0 }'` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

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

 echo "Done with filtering! =)"
 ###############################################################################################################

 # Check if the number of detected transients is suspiciously large
 #NUMBER_OF_DETECTED_TRANSIENTS=`cat vast_summary.log |grep "Transient candidates found:" | awk '{print $4}'`
 NUMBER_OF_DETECTED_TRANSIENTS=`cat candidates-transients.lst | wc -l`
# if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt 200 ];then
 if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt 2000 ];then
  echo "WARNING! Too many candidates... Skipping field..."
  continue
 fi
# if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt 50 ];then
 if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt 500 ];then
  echo "WARNING! Too many candidates... Dropping flares..."
  # if yes, remove flares, keep only new objects
  while read FLAREOUTFILE A B ;do
   grep -v $FLAREOUTFILE candidates-transients.lst > candidates-transients.tmp
   mv candidates-transients.tmp candidates-transients.lst
  done < candidates-flares.lst
 fi
 
 # this is for UCAC5 plate solver
 wait

 util/transients/make_report_in_HTML.sh #$FIELD
 #echo $FIELD
 
done # for i in "$NEW_IMAGES"/*_001.fts ;do

done # for NEW_IMAGES in $@ ;do

echo "<H2>Processig complete!</H2>" >> transient_report/index.html

echo "<H3>Processing log:</H3>" >> transient_report/index.html
echo "<pre>" >> transient_report/index.html
cat transient_factory.log >> transient_report/index.html
echo "</pre>" >> transient_report/index.html

echo "</BODY></HTML>" >> transient_report/index.html

#util/clean_data.sh

