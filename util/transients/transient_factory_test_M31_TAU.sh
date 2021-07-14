#!/usr/bin/env bash

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
 REFERENCE_IMAGES=/mnt/usb/M31_TAU/ref
 if [ ! -d "$REFERENCE_IMAGES" ];then
  # CHANGEME
  REFERENCE_IMAGES=/dataY/kirx/NMW_reference_images_2012 
 fi
fi

# Set the SExtractor parameters file
cp default.sex_M31_TAU default.sex

echo "Reference image directory is set to $REFERENCE_IMAGES"
if [ -z $1 ]; then
 echo "Usage: $0 PATH_TO_DIRECTORY_WITH_IMAGE_PAIRS"
 exit
fi

#NEW_IMAGES=$1

if [ ! -d transient_report ];then
 mkdir transient_report
fi

rm -f transient_report/* transient_factory.log
echo "<HTML>" >> transient_report/index.html

# Allow for multiple image directories to be specified on the command line

for NEW_IMAGES in "$@" ;do

LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR=`for IMGFILE in "$NEW_IMAGES"/fd_*.fit ;do basename "$IMGFILE" ;done | awk '{print $2"_"$3}' FS='_' | sort | uniq`

echo "Fields in the data directory: $LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR"

#exit # !!!

PREVIOUS_FIELD="none"
#for i in "$NEW_IMAGES"/*_001.fit ;do
for FIELD in $LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR ;do
 #STR=`basename $i _001.fit` 
 #FIELD=`echo ${STR:0:8}`
 #FIELD=`echo $FIELD | awk '{print $1}' FS='_'`
 if [ "$FIELD" == "$PREVIOUS_FIELD" ];then
  echo "Script ERROR! This field has been processed before!"
  continue
 fi
 PREVIOUS_FIELD="$FIELD"
 ############## Two reference images and two second-epoch images # check if all images are actually there
 # check if all images are actually there
 N=`ls "$REFERENCE_IMAGES"/*"$FIELD"_*.fit | wc -l`
 if [ $N -lt 2 ];then
  echo "ERROR: to few refereence images for the field $FIELD"
  continue
 fi
 N=`ls "$NEW_IMAGES"/*"$FIELD"_*.fit | wc -l`
 if [ $N -lt 2 ];then
  echo "ERROR: to few refereence images for the field $FIELD"
  continue
 fi
 REFERENCE_EPOCH__FIRST_IMAGE=`ls "$REFERENCE_IMAGES"/fd*"$FIELD"_*.fit | head -n1`
 REFERENCE_EPOCH__SECOND_IMAGE=`ls "$REFERENCE_IMAGES"/fd*"$FIELD"_*.fit | tail -n1`
 SECOND_EPOCH__FIRST_IMAGE=`ls "$NEW_IMAGES"/fd*"$FIELD"_*.fit | head -n1`
 SECOND_EPOCH__SECOND_IMAGE=`ls "$NEW_IMAGES"/fd*"$FIELD"_*.fit | tail -n1`
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
# if [ ! -f $REFERENCE_IMAGES/*"$FIELD"_*_002.fit ];then 
#  echo "Script ERROR! Cannot find image $REFERENCE_IMAGES/*$FIELD*_002.fit"
#  continue
# fi
# if [ ! -f $NEW_IMAGES/*"$FIELD"_*_001.fit ];then 
#  echo "Script ERROR! Cannot find image $NEW_IMAGES/*$FIELD*_001.fit"
#  continue
# fi
# if [ ! -f $NEW_IMAGES/*"$FIELD"_*_002.fit ];then 
#  echo "Script ERROR! Cannot find image $NEW_IMAGES/*$FIELD*_002.fit"
#  continue
# fi
 # Run VaST
 ##./vast -x99 -u -f -k $REFERENCE_IMAGES/*$FIELD* $NEW_IMAGES/*$FIELD*
 #./vast --selectbestaperture -y1 -p -x99 -u -f -k $REFERENCE_IMAGES/*"$FIELD"_* `ls $NEW_IMAGES/*"$FIELD"_*_001.fit | head -n1` `ls $NEW_IMAGES/*"$FIELD"_*_002.fit | head -n1`
 ./vast -P --magsizefilter -p -x99 -u -f "$REFERENCE_EPOCH__FIRST_IMAGE" "$REFERENCE_EPOCH__SECOND_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE"
 #exit #
 lib/remove_lightcurves_with_small_number_of_points
 cat vast_summary.log >> transient_factory.log
 grep --quiet 'Images used for photometry 4' vast_summary.log
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
  util/wcs_image_calibration.sh $i &
#  if [ ! -f wcs_`basename $i` ];then
#   for N_RETRY_WCS in `seq 1 3` ;do
#    echo "WARNING!!! WCS-calibrated file was not created! Retrying..."
#    sleep 10
#    util/wcs_image_calibration.sh $i $APPROXIMATE_FIELD_OF_VIEW_ARCMIN
#   done
#  fi
 done 

 # Wait for all children to end processing
 wait
 
# # Save astrometrically calibrated reference images to cache, if they are not there already
# # Here we assume we have two reference images
# for i in `cat vast_image_details.log | head -n2 |awk '{print $17}'` ;do
#  if [ ! -f wcscache/wcs_`basename $i` ];then
#   # We want to copy both images and catalogs
#   cp wcs_`basename $i`* wcscache/
#  fi
# done
 
 # Calibrate magnitude scale with Tycho-2 stars in the field 
 #echo "y" | util/transients/calibrate_current_field_with_tycho2.sh 
 util/magnitude_calibration.sh V linear

 ################## Quality cits applied to calibrated magnitudes of the candidate transients ##################

 echo "Filter-out faint candidates..."
 # Filter-out faint candidates
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A/\n/} | awk '{print ($1+$2)/2">18.0"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

# echo "Filter-out candidates with large difference between measured mags in one epoch..."
 # 2nd epoch
 # Filter-out candidates with large difference between measured mags
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A/\n/} | awk '{print ($1-$2)">0.4"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 # Filter-out candidates with large difference between measured mags
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A/\n/} | awk '{print ($2-$1)">0.4"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 # 1st epoch (only for sources detected on two reference images)
 # Filter-out candidates with large difference between measured mags
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do if [ `cat $i | wc -l` -lt 4 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=`head -n2 $i | awk '{print $2}'` ; TEST=`echo ${A/\n/} | awk '{print ($1-$2)">1.0"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 # Filter-out candidates with large difference between measured mags
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do if [ `cat $i | wc -l` -lt 4 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=`head -n2 $i | awk '{print $2}'` ; TEST=`echo ${A/\n/} | awk '{print ($2-$1)">1.0"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 
# echo "Filter-out spurious flares of bright stars..."
 # Filter-out spurious flares of bright stars
# for i in `cat candidates-transients.lst | awk '{print $1}'` ;do if [ `cat $i | wc -l` -eq 2 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=`head -n1 $i | awk '{print $2}'` ; TEST=`echo ${A/\n/} | awk '{print ($1)"<9.0"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

# echo "Filter-out small-amplitude flares..."
 # Filter-out small-amplitude flares
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do if [ `cat $i | wc -l` -eq 2 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=`head -n1 $i | awk '{print $2}'` ; B=`tail -n2 $i | awk '{print $2}'` ; MEANMAGSECONDEPOCH=`echo ${B/\n/} | awk '{print ($1+$2)/2}' |bc -ql` ; TEST=`echo $A $MEANMAGSECONDEPOCH | awk '{print ($1-$2)"<0.5"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

 ###

 echo "Done with filtering! =)"
 ###############################################################################################################

 # Check if the number of detected transients is suspiciously large
 #NUMBER_OF_DETECTED_TRANSIENTS=`cat vast_summary.log |grep "Transient candidates found:" | awk '{print $4}'`
 NUMBER_OF_DETECTED_TRANSIENTS=`cat candidates-transients.lst | wc -l`
 if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt 200 ];then
  echo "WARNING! Too many candidates... Skipping field..."
  continue
 fi
 if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt 50 ];then
  echo "WARNING! Too many candidates... Dropping flares..."
  # if yes, remove flares, keep only new objects
  while read FLAREOUTFILE A B ;do
   grep -v $FLAREOUTFILE candidates-transients.lst > candidates-transients.tmp
   mv candidates-transients.tmp candidates-transients.lst
  done < candidates-flares.lst
 fi
 



 util/transients/make_report_in_HTML.sh #$FIELD
 #echo $FIELD
 
done # for i in "$NEW_IMAGES"/*_001.fit ;do

done # for NEW_IMAGES in $@ ;do

echo "<H2>Processig complete!</H2>" >> transient_report/index.html

echo "<H3>Processing log:</H3>" >> transient_report/index.html
echo "<pre>" >> transient_report/index.html
cat transient_factory.log >> transient_report/index.html
echo "</pre>" >> transient_report/index.html

echo "</HTML>" >> transient_report/index.html

#util/clean_data.sh

