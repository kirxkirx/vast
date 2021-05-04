#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ ! -d solved_images ];then
 mkdir solved_images
fi

for NEW_IMAGES in "$@" ;do

LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR=`for IMGFILE in "$NEW_IMAGES"/*.fts ;do basename "${IMGFILE/wcs_fd_/}" ;done | awk -F'_' '{print $1}' | sort | uniq`

echo "Fields in the data directory: 
$LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR"

for FIELD in $LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR ;do
 
 echo "########### Starting $FIELD ###########"

 # first, count how many there are
 NUMBER_OF_SECOND_EPOCH_IMAGES=`ls "$NEW_IMAGES"/*"$FIELD"_*_*.fts | wc -l`



 if [ $NUMBER_OF_SECOND_EPOCH_IMAGES -lt 10 ];then
  continue
 fi

 if [ ${#FIELD} -lt 4 ];then
  continue
 fi

 if [ $NUMBER_OF_SECOND_EPOCH_IMAGES -lt 2 ];then
  echo "ERROR processing the image series - only $NUMBER_OF_SECOND_EPOCH_IMAGES second-epoch images found"
  continue
 elif [ $NUMBER_OF_SECOND_EPOCH_IMAGES -eq 2 ];then
  SECOND_EPOCH__FIRST_IMAGE=`ls "$NEW_IMAGES"/*"$FIELD"_*_*.fts | head -n1`
  SECOND_EPOCH__SECOND_IMAGE=`ls "$NEW_IMAGES"/*"$FIELD"_*_*.fts | head -n2 | tail -n1`
 else
  # There are more than two second-epoch images - do a preliminary VaST run to choose the two images with best seeing
  cp -v default.sex.telephoto_lens_onlybrightstars_v1 default.sex 
  echo "Preliminary VaST run" 
  ./vast --autoselectrefimage --matchstarnumber 100 --UTC --nofind --failsafe --nomagsizefilter --noerrorsrescale --notremovebadimages  "$NEW_IMAGES"/*"$FIELD"_*_*.fts  
  if [ ! -s vast_image_details.log ];then
   echo "ERROR: vast_image_details.log is not created"
   continue
  fi
  if [ $NUMBER_OF_SECOND_EPOCH_IMAGES -lt 10 ];then
   # Simple selection based on seeing
   # column 9 in vast_image_details.log is the aperture size in pixels
   SECOND_EPOCH__FIRST_IMAGE=`cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' | sort -nk9 | head -n1 | awk '{print $17}'`
   SECOND_EPOCH__SECOND_IMAGE=`cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' | sort -nk9 | head -n2 | tail -n1 | awk '{print $17}'`
  else
   # A more careful selection with additional filters (with multi-night image sets in mind)
   grep 'status=OK' vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' > vast_image_details.log_filtered
   MEDIAN_NUMBER_OF_DETECTED_STARS=`cat vast_image_details.log_filtered | awk '{print $13}' | util/colstat 2>/dev/null | grep 'MEDIAN=' | awk '{printf "%.0f",$2}'`
   cat vast_image_details.log_filtered | awk "{if ( \$13 > $MEDIAN_NUMBER_OF_DETECTED_STARS && \$13 <2*$MEDIAN_NUMBER_OF_DETECTED_STARS ) print }" | sort -nk9  > vast_image_details.log_filtered_sorted
   mv vast_image_details.log_filtered_sorted vast_image_details.log_filtered
   SECOND_EPOCH__FIRST_IMAGE=`cat vast_image_details.log_filtered | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' | head -n1 | awk '{print $17}'`
   SECOND_EPOCH__SECOND_IMAGE=`cat vast_image_details.log_filtered | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' | head -n2 | tail -n1 | awk '{print $17}'`
   rm -f vast_image_details.log_filtered
  fi
 fi
 ################################

 # Plate-solve
 echo "Plate-solving the images" 
 # WCS-calibration
 for i in $SECOND_EPOCH__FIRST_IMAGE $SECOND_EPOCH__SECOND_IMAGE ;do 
  WCS_IMAGE_NAME_FOR_CHECKS=wcs_`basename $i`
  if [ ! -f "solved_images/$WCS_IMAGE_NAME_FOR_CHECKS" ];then
   TELESCOP="NMW_camera" util/wcs_image_calibration.sh $i #&
  else
   echo "Found an already solved image solved_images/$WCS_IMAGE_NAME_FOR_CHECKS"
  fi
 done 

 # Wait for all children to end processing
 #wait
 
 # Check that the plates were actually solved
 for i in $SECOND_EPOCH__FIRST_IMAGE $SECOND_EPOCH__SECOND_IMAGE ;do 
  WCS_IMAGE_NAME_FOR_CHECKS=wcs_`basename $i`
  WCS_IMAGE_NAME_FOR_CHECKS="${WCS_IMAGE_NAME_FOR_CHECKS/wcs_wcs_/wcs_}"
  if [ ! -f "$WCS_IMAGE_NAME_FOR_CHECKS" ];then
   if [ ! -f `basename "${i/wcs_fd_/}"` ];then
    if [ ! -f `basename "${i/fd_/}"` ];then
     echo "***** PLATE SOLVE PROCESSING ERROR *****" >> transient_factory.log
     echo "***** cannot find $WCS_IMAGE_NAME_FOR_CHECKS  *****" >> transient_factory.log
     echo "############################################################" >> transient_factory.log
     echo 'UNSOLVED_PLATE'
    else
     mv "$WCS_IMAGE_NAME_FOR_CHECKS" solved_images/
    fi
   else
    mv "$WCS_IMAGE_NAME_FOR_CHECKS" solved_images/  
   fi
  else
   mv "$WCS_IMAGE_NAME_FOR_CHECKS" solved_images/
  fi
 done

 ###########!!!!!!!!!!!!!!!!!!!!!!!
 #exit

done # for FIELD in $LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR ;do
done # for NEW_IMAGES in "$@" ;do

echo "Solved images written to solved_images"
