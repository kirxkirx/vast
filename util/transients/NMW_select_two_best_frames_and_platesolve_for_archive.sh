#!/usr/bin/env bash

if [ ! -d solved_images ];then
 mkdir solved_images
fi

for NEW_IMAGES in "$@" ;do

LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR=`for IMGFILE in "$NEW_IMAGES"/*.fts ;do basename "$IMGFILE" ;done | awk '{print $1}' FS='_' | sort | uniq`

echo "Fields in the data directory: 
$LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR"

for FIELD in $LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR ;do
 
 echo "########### Starting $FIELD ###########"

 # first, count how many there are
 NUMBER_OF_SECOND_EPOCH_IMAGES=`ls "$NEW_IMAGES"/*"$FIELD"_*_*.fts | wc -l`
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
  ./vast --UTC --nofind --failsafe --nomagsizefilter --noerrorsrescale --notremovebadimages  "$NEW_IMAGES"/*"$FIELD"_*_*.fts  
  # column 9 in vast_image_details.log is the aperture size in pixels
  SECOND_EPOCH__FIRST_IMAGE=`cat vast_image_details.log | sort -nk9 | head -n1 | awk '{print $17}'`
  SECOND_EPOCH__SECOND_IMAGE=`cat vast_image_details.log | sort -nk9 | head -n2 | tail -n1 | awk '{print $17}'`
 fi
 ################################

 # Plate-solve
  echo "Plate-solving the images" 
 # WCS-calibration
 for i in $SECOND_EPOCH__FIRST_IMAGE $SECOND_EPOCH__SECOND_IMAGE ;do 
  TELESCOP="NMW_camera" util/wcs_image_calibration.sh $i #&
 done 

 # Wait for all children to end processing
 #wait
 
 # Check that the plates were actually solved
 for i in $SECOND_EPOCH__FIRST_IMAGE $SECOND_EPOCH__SECOND_IMAGE ;do 
  WCS_IMAGE_NAME_FOR_CHECKS=wcs_`basename $i`
  if [ ! -f "$WCS_IMAGE_NAME_FOR_CHECKS" ];then
   echo "***** PLATE SOLVE PROCESSING ERROR *****" >> transient_factory.log
   echo "***** cannot find $WCS_IMAGE_NAME_FOR_CHECKS  *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   echo 'UNSOLVED_PLATE'
  else
   mv "$WCS_IMAGE_NAME_FOR_CHECKS" solved_images/
  fi
 done

done # for FIELD in $LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR ;do
done # for NEW_IMAGES in "$@" ;do

echo "Solved images written to solved_images"
