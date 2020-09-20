#!/usr/bin/env bash

# When adapting this script for a new dataset, watch for the signs
### ===> MAGNITUDE LIMITS HARDCODED HERE <===
### ===> APERTURE LIMITS HARDCODED HERE <===
### ===> POINTING ACCURACY LIMITS HARDCODED HERE <===

# Also watch for
### ===> SExtractor config file <===
### ===> IMAGE EDGE OFFSET HARDCODED HERE <===
### ===> ASSUMED MAX NUMBER OF CANDIDATES <===

#
# This script is an example of how an automated transient-detection pipeline may be set up using VaST.
# Note, that in this example there are two reference and two second-epoch images.
# The results will be presented as an HTML page transient_report/index.html
#

# Set the directory with reference images
# You may set a few alternative locations, but only the first one that exist will be used
if [ -z "$REFERENCE_IMAGES" ];then
 REFERENCE_IMAGES=/mnt/usb/NMW_NG/NMW_reference_images_2012
 # scan
 if [ ! -d "$REFERENCE_IMAGES" ];then
  REFERENCE_IMAGES=/home/NMW_reference_images_2012
 fi
 # vast
 if [ ! -d "$REFERENCE_IMAGES" ];then
  REFERENCE_IMAGES=/dataX/kirx/NMW_reference_images_2012 
 fi
 if [ ! -d "$REFERENCE_IMAGES" ];then
  REFERENCE_IMAGES=/dataY/kirx/NMW_reference_images_2012 
 fi
 if [ ! -d "$REFERENCE_IMAGES" ];then
  REFERENCE_IMAGES=/home/kirx/current_work/NMW_crashtest/ref 
 fi
 # saturn test
 if [ ! -d "$REFERENCE_IMAGES" ];then
  REFERENCE_IMAGES="../NMW_Saturn_test/1referenceepoch/"
 fi
fi

# Clean whatever may remain from a possible incomplete previous run
if [ -f transient_factory_test31.txt ];then
 rm -f transient_factory_test31.txt
fi
# clean up the local cache
for FILE_TO_REMOVE in local_wcs_cache/* exclusion_list.txt exclusion_list_bsc.txt exclusion_list_bbsc.txt exclusion_list_tycho2.txt exclusion_list_gaiadr2.txt exclusion_list_apass.txt ;do
 if [ -f "$FILE_TO_REMOVE" ];then
  rm -f "$FILE_TO_REMOVE"
  echo "Removing $FILE_TO_REMOVE" >> transient_factory_test31.txt
 fi
done



if [ ! -d "$REFERENCE_IMAGES" ];then
 echo "ERROR: cannot find the reference image directory REFERENCE_IMAGES=$REFERENCE_IMAGES"
 echo "ERROR: cannot find the reference image directory REFERENCE_IMAGES=$REFERENCE_IMAGES" >> transient_factory_test31.txt
 exit 1
fi

# Check for a local copy of UCAC5
# (this is specific to our in-house setup)
if [ ! -d lib/catalogs/ucac5 ];then
 for TEST_THIS_DIR in /mnt/usb/UCAC5 /dataX/kirx/UCAC5 /home/kirx/UCAC5 $HOME/UCAC5 ../UCAC5 ;do
  if [ -d $TEST_THIS_DIR ];then
   ln -s $TEST_THIS_DIR lib/catalogs/ucac5
   echo "Linking the local copy of UCAC5 from $TEST_THIS_DIR"
   echo "Linking the local copy of UCAC5 from $TEST_THIS_DIR" >> transient_factory_test31.txt
   break
  fi
 done
fi
#### Even more specific case: /mnt/usb/UCAC5 is present but the link is set to /dataX/kirx/UCAC5 ####
if [ -d /mnt/usb/UCAC5 ];then
 LINK_POINTS_TO=`readlink -f lib/catalogs/ucac5`
 if [ "$LINK_POINTS_TO" = "/dataX/kirx/UCAC5" ];then
  rm -f lib/catalogs/ucac5
  ln -s /mnt/usb/UCAC5 lib/catalogs/ucac5
 fi
fi
#####################################################################################################
# This script should take care of updating astorb.dat
lib/update_offline_catalogs.sh all

echo "Reference image directory is set to $REFERENCE_IMAGES"
if [ -z $1 ]; then
 echo "Usage: $0 PATH_TO_DIRECTORY_WITH_IMAGE_PAIRS"
 echo "Usage: $0 PATH_TO_DIRECTORY_WITH_IMAGE_PAIRS" >> transient_factory_test31.txt
 exit 1
fi

# We may need it for the new transients check in util/transients/report_transient.sh
export VIZIER_SITE=`lib/choose_vizier_mirror.sh`
### 
TIMEOUTCOMMAND=`"$VAST_PATH"lib/find_timeout_command.sh`
if [ $? -ne 0 ];then
 echo "WARNING: cannot find timeout command"
else
 #TIMEOUTCOMMAND="$TIMEOUTCOMMAND 20 "
 TIMEOUTCOMMAND="$TIMEOUTCOMMAND 40 "
fi
export TIMEOUTCOMMAND

# Remove filenames that will confuse vast command line parser
for SUSPICIOUS_FILE in 1 2 3 4 5 6 7 8 9 10 11 12 ;do
 if [ -f "$SUSPICIOUS_FILE" ];then
  rm -f "$SUSPICIOUS_FILE"
 fi
done


# do this only if transient_report is not a symlink
if [ ! -L transient_report ];then
 if [ ! -d transient_report ];then
  mkdir transient_report
 fi
fi

rm -f transient_report/* transient_factory.log

echo "<HTML>

<HEAD>
<style>
 body {
       font-family:monospace;
       font-size:12px;'
      }
</style>

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

function printCandidateNameWithAbsLink( transientname) {

 var currentLocation = window.location.href;
 
 var n = currentLocation.indexOf('#');
 currentLocation = currentLocation.substring(0, n != -1 ? n : currentLocation.length);
 var transientLink = \"#\";
 transientLink = transientLink.concat(transientname);
 var targetURL = currentLocation.concat(transientLink);
 
 var outputString = \"<h3><a href='\";
 outputString = outputString.concat(targetURL);
 outputString = outputString.concat(\"'>\");
 outputString = outputString.concat(transientname);
 outputString = outputString.concat(\"</a></h3>\");

 document.write(outputString); 

}

</script>

</HEAD>

<BODY>
<h2>NMW transient search results</h2>
This analysis is done by the script  <code>$0 $@</code><br><br>
The list of candidates will appear below. Please <b>manually reload the page</b> every few minutes untill the 'Processing complete' message appears.
<br><br>" >> transient_report/index.html

# Allow for multiple image directories to be specified on the command line

for NEW_IMAGES in "$@" ;do

if [ ! -d "$NEW_IMAGES" ];then
 echo "ERROR: $NEW_IMAGES is not a directory"
 echo "ERROR: $NEW_IMAGES is not a directory" >> transient_factory_test31.txt
 continue
fi

LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR=`for IMGFILE in "$NEW_IMAGES"/*.fts ;do if [ -f "$IMGFILE" ];then basename "$IMGFILE" ;fi ;done | awk '{print $1}' FS='_' | sort | uniq`

echo "Fields in the data directory: 
$LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR"

echo "Processing fields $LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR <br>" >> transient_report/index.html

if [ -z "$LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR" ];then
 echo "ERROR: cannot find image files obeying the assumed naming convention in $@"
 echo "ERROR: cannot find image files obeying the assumed naming convention in $@" >> transient_factory_test31.txt
 continue
fi

#exit # !!!
echo "$LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR" >> transient_factory_test31.txt

PREVIOUS_FIELD="none"
#for i in "$NEW_IMAGES"/*_001.fts ;do
for FIELD in $LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR ;do
 
 echo "########### Starting $FIELD ###########" >> transient_factory_test31.txt

 echo "Processing $FIELD" >> transient_factory_test31.txt
 #STR=`basename $i _001.fts` 
 #FIELD=`echo ${STR:0:8}`
 #FIELD=`echo $FIELD | awk '{print $1}' FS='_'`
 if [ "$FIELD" == "$PREVIOUS_FIELD" ];then
  echo "Script ERROR! This field has been processed before!"
  echo "Script ERROR! This field has been processed before!" >> transient_factory_test31.txt
  continue
 fi
 PREVIOUS_FIELD="$FIELD"
 ############## Two reference images and two second-epoch images # check if all images are actually there
 # check if all images are actually there
 N=`ls "$REFERENCE_IMAGES"/*"$FIELD"_*_*.fts | wc -l`
 if [ $N -lt 2 ];then
  echo "ERROR: too few refereence images for the field $FIELD"
  echo "ERROR: too few refereence images for the field $FIELD" >> transient_factory_test31.txt
  continue
 fi
 N=`ls "$NEW_IMAGES"/*"$FIELD"_*_*.fts | wc -l`
 if [ $N -lt 2 ];then
  echo "ERROR: too few new images for the field $FIELD"
  echo "ERROR: too few new images for the field $FIELD" >> transient_factory_test31.txt
  continue
 fi
 echo "Checking input images ($N new)" >> transient_factory_test31.txt
 ################################
 # choose first epoch images
 REFERENCE_EPOCH__FIRST_IMAGE=`ls "$REFERENCE_IMAGES"/*"$FIELD"_*_*.fts | head -n1`
 echo "REFERENCE_EPOCH__FIRST_IMAGE= $REFERENCE_EPOCH__FIRST_IMAGE" >> transient_factory_test31.txt
 REFERENCE_EPOCH__SECOND_IMAGE=`ls "$REFERENCE_IMAGES"/*"$FIELD"_*_*.fts | tail -n1`
 echo "REFERENCE_EPOCH__SECOND_IMAGE= $REFERENCE_EPOCH__SECOND_IMAGE" >> transient_factory_test31.txt
 # choose second epoch images
 # first, count how many there are
 NUMBER_OF_SECOND_EPOCH_IMAGES=`ls "$NEW_IMAGES"/*"$FIELD"_*_*.fts | wc -l`
 
 if [ $NUMBER_OF_SECOND_EPOCH_IMAGES -gt 1 ];then
  # Make image previews
  echo "Previews of the second-epoch images:<br>" >> transient_factory_test31.txt
  for FITS_IMAGE_TO_PREVIEW in "$NEW_IMAGES"/*"$FIELD"_*_*.fts ;do
   BASENAME_FITS_IMAGE_TO_PREVIEW=`basename $FITS_IMAGE_TO_PREVIEW`
   PREVIEW_IMAGE="$BASENAME_FITS_IMAGE_TO_PREVIEW"_preview.png
   util/fits2png $FITS_IMAGE_TO_PREVIEW &> /dev/null && mv pgplot.png transient_report/$PREVIEW_IMAGE
   echo "<br>$BASENAME_FITS_IMAGE_TO_PREVIEW<br><img src=\"$PREVIEW_IMAGE\"><br>" >> transient_factory_test31.txt
  done
  echo "<br>" >> transient_factory_test31.txt
 fi
 
 if [ $NUMBER_OF_SECOND_EPOCH_IMAGES -lt 2 ];then
  echo "ERROR processing the image series - only $NUMBER_OF_SECOND_EPOCH_IMAGES second-epoch images found"
  echo "ERROR processing the image series - only $NUMBER_OF_SECOND_EPOCH_IMAGES second-epoch images found" >> transient_factory_test31.txt
  continue
 elif [ $NUMBER_OF_SECOND_EPOCH_IMAGES -eq 2 ];then
  SECOND_EPOCH__FIRST_IMAGE=`ls "$NEW_IMAGES"/*"$FIELD"_*_*.fts | head -n1`
  SECOND_EPOCH__SECOND_IMAGE=`ls "$NEW_IMAGES"/*"$FIELD"_*_*.fts | head -n2 | tail -n1`
 else
  # There are more than two second-epoch images - do a preliminary VaST run to choose the two images with best seeing
  cp -v default.sex.telephoto_lens_onlybrightstars_v1 default.sex >> transient_factory_test31.txt
  echo "Preliminary VaST run" >> transient_factory_test31.txt
  echo "./vast --autoselectrefimage --matchstarnumber 100 --UTC --nofind --failsafe --nomagsizefilter --noerrorsrescale --notremovebadimages"  "$NEW_IMAGES"/*"$FIELD"_*_*.fts >> transient_factory_test31.txt
  ./vast --autoselectrefimage --matchstarnumber 100 --UTC --nofind --failsafe --nomagsizefilter --noerrorsrescale --notremovebadimages  "$NEW_IMAGES"/*"$FIELD"_*_*.fts  2>&1 > prelim_vast_run.log
  wait
  ## Special test for stuck camera ##
  if [ -s vast_image_details.log ];then
   N_SAME_IMAGE=`grep -c ' rotation= 180.000 ' vast_image_details.log`
   if [ $N_SAME_IMAGE -gt 1 ];then
    # Stuck camera
    echo "ERROR the camera is stuck repeatedly sending the same image!"
    echo "***** IMAGE PROCESSING ERROR (stuck camera repeatedly sending the same image) *****" >> transient_factory.log
    echo "###################################################################################" >> transient_factory.log
    echo "ERROR the camera is stuck repeatedly sending the same image!" >> transient_factory_test31.txt
    rm -f prelim_vast_run.log
    continue
   fi
  fi
  cat prelim_vast_run.log | grep 'Bad reference image...' >> transient_factory.log
  if [ $? -eq 0 ];then
   # Bad reference image
   echo "ERROR clouds on second-epoch images?"
   echo "***** IMAGE PROCESSING ERROR (clouds?) *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   echo "ERROR clouds on second-epoch images?" >> transient_factory_test31.txt
   rm -f prelim_vast_run.log
   continue
  fi
  if [ -f prelim_vast_run.log ];then
   rm -f prelim_vast_run.log
  fi
  if [ ! -s vast_summary.log ];then
   echo "ERROR: vast_summary.log is not created during the preliminary VaST run" >> transient_factory_test31.txt
   continue
  fi
  N_PROCESSED_IMAGES_PRELIM_RUN=`cat vast_summary.log | grep 'Images processed' | awk '{print $3}'`
  if [ $N_PROCESSED_IMAGES_PRELIM_RUN -lt 2 ];then
   echo "ERROR processing second-epoch images!"
   echo "***** IMAGE PROCESSING ERROR (preliminary VaST run) *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   echo "ERROR processing second-epoch images (preliminary VaST run 01)!" >> transient_factory_test31.txt
   continue   
  fi
  N_PROCESSED_IMAGES_PRELIM_RUN=`cat vast_summary.log | grep 'Images used for photometry' | awk '{print $5}'`
  if [ $N_PROCESSED_IMAGES_PRELIM_RUN -lt 2 ];then
   echo "ERROR processing second-epoch images!"
   echo "***** IMAGE PROCESSING ERROR (preliminary VaST run) *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   echo "ERROR processing second-epoch images (preliminary VaST run 02)!" >> transient_factory_test31.txt
   continue   
  fi
  if [ ! -s vast_image_details.log ];then
   echo "ERROR: vast_image_details.log is not created (preliminary VaST run)" >> transient_factory_test31.txt
   continue
  fi
  # column 9 in vast_image_details.log is the aperture size in pixels
  ### ===> APERTURE LIMITS HARDCODED HERE <===
  NUMBER_OF_IMAGES_WITH_REASONABLE_SEEING=`cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' | awk '{if ( $9 > 2 ) print }' | awk '{if ( $9 < 8.5 ) print }' | wc -l`
  if [ $NUMBER_OF_IMAGES_WITH_REASONABLE_SEEING -lt 2 ];then
   echo "ERROR: seeing on second-epoch images is out of range"
   echo "***** ERROR: seeing on second-epoch images is out of range *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   echo "ERROR: seeing on second-epoch images is out of range" >> transient_factory_test31.txt
   continue
  fi
  ### ===> APERTURE LIMITS HARDCODED HERE <===
  SECOND_EPOCH__FIRST_IMAGE=`cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' | awk '{if ( $9 > 2 ) print }' | awk '{if ( $9 < 8.5 ) print }' | sort -nk9 | head -n1 | awk '{print $17}'`
  echo "SECOND_EPOCH__FIRST_IMAGE= $SECOND_EPOCH__FIRST_IMAGE" >> transient_factory_test31.txt
  ### ===> APERTURE LIMITS HARDCODED HERE <===
  SECOND_EPOCH__SECOND_IMAGE=`cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' | awk '{if ( $9 > 2 ) print }' | awk '{if ( $9 < 8.5 ) print }' | sort -nk9 | head -n2 | tail -n1 | awk '{print $17}'`
  echo "SECOND_EPOCH__SECOND_IMAGE= $SECOND_EPOCH__SECOND_IMAGE" >> transient_factory_test31.txt
  if [ -z "$SECOND_EPOCH__FIRST_IMAGE" ];then
   echo "ERROR: SECOND_EPOCH__FIRST_IMAGE is not defined!" >> transient_factory_test31.txt
   cat vast_image_details.log >> transient_factory_test31.txt
   continue
  fi
  if [ -z "$SECOND_EPOCH__SECOND_IMAGE" ];then
   echo "ERROR: SECOND_EPOCH__SECOND_IMAGE is not defined!" >> transient_factory_test31.txt
   cat vast_image_details.log >> transient_factory_test31.txt
   continue
  fi
  if [ "$SECOND_EPOCH__FIRST_IMAGE" = "$SECOND_EPOCH__SECOND_IMAGE" ];then
   echo "ERROR: SECOND_EPOCH__FIRST_IMAGE = SECOND_EPOCH__SECOND_IMAGE"
   cat vast_image_details.log >> transient_factory_test31.txt
   continue
  fi
  ###
  # Check for elliptical star images (tracking error)
  SE_CATALOG_FOR_SECOND_EPOCH__FIRST_IMAGE=`grep "$SECOND_EPOCH__FIRST_IMAGE" vast_images_catalogs.log | awk '{print $1}'`
  MEDIAN_DIFFERENCE_AminusB_PIX=`cat $SE_CATALOG_FOR_SECOND_EPOCH__FIRST_IMAGE | awk '{print $18-$20}' | util/colstat 2> /dev/null | grep 'MEDIAN=' | awk '{printf "%.2f", $2}'`
  ### ===> APERTURE LIMITS HARDCODED HERE <=== (this is median difference in pixels between semi-major and semi-minor axes of the source)
  TEST=`echo "$MEDIAN_DIFFERENCE_AminusB_PIX < 0.6" | bc -ql`
  if [ $TEST -eq 0 ];then
   echo "ERROR: tracking error (elongated stars), median(A-B)=$MEDIAN_DIFFERENCE_AminusB_PIX pix  "`basename $SECOND_EPOCH__FIRST_IMAGE` >> transient_factory_test31.txt
   continue
  else
   echo "The star elongation is within the allowed range: median(A-B)=$MEDIAN_DIFFERENCE_AminusB_PIX pix  "`basename $SECOND_EPOCH__FIRST_IMAGE` >> transient_factory_test31.txt
  fi
  SE_CATALOG_FOR_SECOND_EPOCH__SECOND_IMAGE=`grep "$SECOND_EPOCH__SECOND_IMAGE" vast_images_catalogs.log | awk '{print $1}'`
  MEDIAN_DIFFERENCE_AminusB_PIX=`cat $SE_CATALOG_FOR_SECOND_EPOCH__SECOND_IMAGE | awk '{print $18-$20}' | util/colstat 2> /dev/null | grep 'MEDIAN=' | awk '{printf "%.2f", $2}'`
  ### ===> APERTURE LIMITS HARDCODED HERE <=== (this is median difference in pixels between semi-major and semi-minor axes of the source)
  TEST=`echo "$MEDIAN_DIFFERENCE_AminusB_PIX < 0.6" | bc -ql`
  if [ $TEST -eq 0 ];then
   echo "ERROR: tracking error (elongated stars) median(A-B)=$MEDIAN_DIFFERENCE_AminusB_PIX pix  "`basename $SECOND_EPOCH__SECOND_IMAGE` >> transient_factory_test31.txt
   continue
  else
   echo "The star elongation is within the allowed range: median(A-B)=$MEDIAN_DIFFERENCE_AminusB_PIX pix  "`basename $SECOND_EPOCH__SECOND_IMAGE` >> transient_factory_test31.txt
  fi
  ###
 fi
 ################################
 # double-check the files
 for FILE_TO_CHECK in "$REFERENCE_EPOCH__FIRST_IMAGE" "$REFERENCE_EPOCH__SECOND_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE" ;do
  ls "$FILE_TO_CHECK" 
  if [ $? -ne 0 ];then
   echo "ERROR opening file $FILE_TO_CHECK" >> /dev/stderr
  fi
 done | grep "ERROR opening file"
 if [ $? -eq 0 ];then
  echo "ERROR processing the image series"
  echo "ERROR processing the image series" >> transient_factory_test31.txt
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

 ###############################################
 # We may have images from two different cameras that require two different bad region lists
 # ./Nazar_bad_region.lst and ../bad_region.lst
 echo "Choosing bad regions list" >> transient_factory_test31.txt
 # Set custom bad_region.lst if there is one
 # test the file name
 echo "$SECOND_EPOCH__FIRST_IMAGE" | grep --quiet -e "Nazar" -e "nazar" -e "NAZAR"
 if [ $? -eq 0 ];then
  if [ -f ../Nazar_bad_region.lst ];then
   cp -v ../Nazar_bad_region.lst bad_region.lst >> transient_factory_test31.txt
  fi
 else
  if [ -f ../bad_region.lst ];then
   cp -v ../bad_region.lst . >> transient_factory_test31.txt
  else
   echo "No bad regions file found ../bad_region.lst" >> transient_factory_test31.txt
  fi
 fi
 ###############################################

 # We need a local exclusion list not to find the same things in multiple SExtractor runs
 if [ -f exclusion_list_local.txt ];then
  rm -f exclusion_list_local.txt
 fi 

 # Make multiple VaST runs with different SExtractor config files
 ### ===> SExtractor config file <===
 for SEXTRACTOR_CONFIG_FILE in default.sex.telephoto_lens_onlybrightstars_v1 default.sex.telephoto_lens_v4 ;do

 # make sure nothing is left running from the previous run (in case it ended early with 'continue')
 wait
 #
 
 # just to make sure all the child loops will see it
 export SEXTRACTOR_CONFIG_FILE
 
 echo "*------ $SEXTRACTOR_CONFIG_FILE ------*" >> transient_factory_test31.txt
 
 ## Set the SExtractor parameters file
 if [ ! -f "$SEXTRACTOR_CONFIG_FILE" ];then
  echo "ERROR finding $SEXTRACTOR_CONFIG_FILE" >> transient_factory_test31.txt
  continue
 fi
 cp -v "$SEXTRACTOR_CONFIG_FILE" default.sex >> transient_factory_test31.txt

 echo "Starting VaST with $SEXTRACTOR_CONFIG_FILE" >> transient_factory_test31.txt
 # Run VaST
 echo "./vast --starmatchraius 4.0 --matchstarnumber 500 --selectbestaperture --sysrem 1 --poly --maxsextractorflag 99 --UTC --nofind --nojdkeyword $REFERENCE_EPOCH__FIRST_IMAGE $REFERENCE_EPOCH__SECOND_IMAGE $SECOND_EPOCH__FIRST_IMAGE $SECOND_EPOCH__SECOND_IMAGE" >> transient_factory_test31.txt
 ###./vast -x99 -u -f -k $REFERENCE_IMAGES/*$FIELD* $NEW_IMAGES/*$FIELD*
 ##./vast --selectbestaperture -y1 -p -x99 -u -f -k $REFERENCE_IMAGES/*"$FIELD"_* `ls $NEW_IMAGES/*"$FIELD"_*_001.fts | head -n1` `ls $NEW_IMAGES/*"$FIELD"_*_002.fts | head -n1`
 #./vast --selectbestaperture -y1 -p -x99 -u -f -k "$REFERENCE_EPOCH__FIRST_IMAGE" "$REFERENCE_EPOCH__SECOND_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE"
 #./vast --matchstarnumber 500 --selectbestaperture -y1 -p -x99 -u -f -k "$REFERENCE_EPOCH__FIRST_IMAGE" "$REFERENCE_EPOCH__SECOND_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE"
 ./vast --starmatchraius 4.0 --matchstarnumber 500 --selectbestaperture --sysrem 1 --poly --maxsextractorflag 99 --UTC --nofind --nojdkeyword "$REFERENCE_EPOCH__FIRST_IMAGE" "$REFERENCE_EPOCH__SECOND_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE"
 if [ $? -ne 0 ];then
  echo "ERROR running VaST on the field $FIELD"
  echo "ERROR running VaST on the field $FIELD" >> transient_factory_test31.txt
  echo "ERROR running VaST on the field $FIELD" >> transient_factory.log
  # drop this field and continue to the next one
  # We want to break from the SExtractor settings files loop here
  break
 else
  echo "VaST run complete" >> transient_factory_test31.txt
 fi
 echo "The four input images were $REFERENCE_EPOCH__FIRST_IMAGE" "$REFERENCE_EPOCH__SECOND_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE"  >> transient_factory_test31.txt
 cat vast_summary.log >> transient_factory.log
 grep --quiet 'Images used for photometry 4' vast_summary.log
 if [ $? -ne 0 ];then
  echo "***** IMAGE PROCESSING ERROR (less than 4 images processed) *****" >> transient_factory.log
  echo "############################################################" >> transient_factory.log
  echo "ERROR running VaST on the field $FIELD (less than 4 images processed)" >> transient_factory_test31.txt
  cat vast_image_details.log >> transient_factory_test31.txt
  continue
 fi
 echo "############################################################" >> transient_factory.log
 
 # Use cache if possible to speed-up WCS calibration
 for WCSCACHEDIR in "local_wcs_cache" "/mnt/usb/NMW_NG/solved_reference_images" "/home/NMW_web_upload/solved_reference_images" "/dataX/kirx/NMW_NG_rt3_autumn2019/solved_reference_images" ;do
  echo "Checking WCS cache directory $WCSCACHEDIR" >> transient_factory_test31.txt
  if [ -d "$WCSCACHEDIR" ];then
   echo "Found WCS cache directory $WCSCACHEDIR" >> transient_factory_test31.txt
   #ls "$WCSCACHEDIR" >> transient_factory_test31.txt
   ### ===> SExtractor config file <===
   if [ "$SEXTRACTOR_CONFIG_FILE" = "default.sex.telephoto_lens_v4" ];then
    echo "(SExtractor parameter file $SEXTRACTOR_CONFIG_FILE -- faint objects)" >> transient_factory_test31.txt
    # link the solved images and catalogs created with this SExtractorconfig file
    for i in "$WCSCACHEDIR/wcs_"$FIELD"_"*.fts "$WCSCACHEDIR/exclusion_list"* ;do
     if [ -s "$i" ];then
      echo "Creating symlink $i" >> transient_factory_test31.txt
      ln -s $i
     fi
    done
   else
    # we are using a different config file
    # link only the solved images (and the exclusion lists)
    echo "(SExtractor parameter file $SEXTRACTOR_CONFIG_FILE -- bright objects)" >> transient_factory_test31.txt
    for i in "$WCSCACHEDIR/wcs_"$FIELD"_"*.fts "$WCSCACHEDIR/exclusion_list"* ;do
     if [ -s "$i" ];then
      echo "Creating symlink $i" >> transient_factory_test31.txt
      ln -s $i
     fi
    done
   fi
   #break
  fi
 done
 
 echo "Plate-solving the images" >> transient_factory_test31.txt
 # WCS-calibration
 for i in `cat vast_image_details.log | awk '{print $17}' | sort | uniq` ;do 
  # This should ensure the correct field-of-view guess by setting the TELESCOP keyword
  #util/modhead $i TELESCOP NMW_camera
  #
  TELESCOP="NMW_camera" util/wcs_image_calibration.sh $i &
  #TELESCOP="NMW_camera" util/solve_plate_with_UCAC5 $i &
 done 

 # Wait for all children to end processing
 ps --forest $(ps -e --no-header -o pid,ppid|awk -vp=$$ 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')  >> transient_factory_test31.txt
 echo "wait"   >> transient_factory_test31.txt
 wait
 ps --forest $(ps -e --no-header -o pid,ppid|awk -vp=$$ 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')  >> transient_factory_test31.txt
 
 # Check that the plates were actually solved
 for i in `cat vast_image_details.log |awk '{print $17}'` ;do 
  WCS_IMAGE_NAME_FOR_CHECKS=wcs_`basename $i`
  if [ ! -s "$WCS_IMAGE_NAME_FOR_CHECKS" ];then
   echo "***** PLATE SOLVE PROCESSING ERROR *****" >> transient_factory.log
   echo "***** cannot find $WCS_IMAGE_NAME_FOR_CHECKS  *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   echo 'UNSOLVED_PLATE'
  else
   echo "$WCS_IMAGE_NAME_FOR_CHECKS exists and is non-empty" >> transient_factory_test31.txt
   if [ ! -d local_wcs_cache/ ];then
    mkdir local_wcs_cache
   fi
   if [ ! -L "$WCS_IMAGE_NAME_FOR_CHECKS" ];then
    ### ===> SExtractor config file <===
    if [ "$SEXTRACTOR_CONFIG_FILE" != "default.sex.telephoto_lens_v4" ];then
     # save the solved plate to local cache, but only if it's not already a symlink
     echo "Saving $WCS_IMAGE_NAME_FOR_CHECKS to local_wcs_cache/" >> transient_factory_test31.txt
     cp "$WCS_IMAGE_NAME_FOR_CHECKS" local_wcs_cache/
    else
     echo "NOT SAVING $WCS_IMAGE_NAME_FOR_CHECKS to local_wcs_cache/ as this is the run with $SEXTRACTOR_CONFIG_FILE" >> transient_factory_test31.txt
    fi
   fi
  fi
 done | grep --quiet 'UNSOLVED_PLATE'
 if [ $? -eq 0 ];then
  echo "ERROR found an unsoved plate in the field $FIELD" >> transient_factory_test31.txt
  continue
 fi

 # Compare image centers of the reference and second-epoch image
 WCS_IMAGE_NAME_FOR_CHECKS=wcs_`basename $REFERENCE_EPOCH__FIRST_IMAGE`
 WCS_IMAGE_NAME_FOR_CHECKS="${WCS_IMAGE_NAME_FOR_CHECKS/wcs_wcs_/wcs_}"
 IMAGE_CENTER__REFERENCE_EPOCH__FIRST_IMAGE=`util/fov_of_wcs_calibrated_image.sh $WCS_IMAGE_NAME_FOR_CHECKS | grep 'Image center:' | awk '{print $3" "$4}'` 
 WCS_IMAGE_NAME_FOR_CHECKS=wcs_`basename $SECOND_EPOCH__FIRST_IMAGE`
 WCS_IMAGE_NAME_FOR_CHECKS="${WCS_IMAGE_NAME_FOR_CHECKS/wcs_wcs_/wcs_}"
 IMAGE_CENTER__SECOND_EPOCH__FIRST_IMAGE=`util/fov_of_wcs_calibrated_image.sh $WCS_IMAGE_NAME_FOR_CHECKS | grep 'Image center:' | awk '{print $3" "$4}'`
 DISTANCE_BETWEEN_IMAGE_CENTERS_DEG=`lib/put_two_sources_in_one_field $IMAGE_CENTER__REFERENCE_EPOCH__FIRST_IMAGE $IMAGE_CENTER__SECOND_EPOCH__FIRST_IMAGE 2>/dev/null | grep 'Angular distance' | awk '{printf "%.2f", $5}'`
 echo "###################################
# Check the image center offset between the reference and the secondepoch image (pointing accuracy)
Reference image center $IMAGE_CENTER__REFERENCE_EPOCH__FIRST_IMAGE
Second-epoch image center $IMAGE_CENTER__SECOND_EPOCH__FIRST_IMAGE
Angular distance between the image centers $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg.
###################################" >> transient_factory_test31.txt
 ### ===> POINTING ACCURACY LIMITS HARDCODED HERE <===
 TEST=`echo "$DISTANCE_BETWEEN_IMAGE_CENTERS_DEG>1.0" | bc -ql`
 if [ $TEST -eq 1 ];then
  echo "ERROR: (NO CANDIDATES LISTED) distance between reference and second-epoch image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg."
  echo "ERROR: (NO CANDIDATES LISTED) distance between reference and second-epoch image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg." >> transient_factory_test31.txt
  break
  # This should break us form the SEXTRACTOR_CONFIG_FILE cycle
 fi
 ### ===> POINTING ACCURACY LIMITS HARDCODED HERE <===
 TEST=`echo "$DISTANCE_BETWEEN_IMAGE_CENTERS_DEG>0.2" | bc -ql`
 if [ $TEST -eq 1 ];then
  echo "ERROR: distance between reference and second-epoch image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg."
  echo "ERROR: distance between reference and second-epoch image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg." >> transient_factory_test31.txt
  #break
  # Not break'ing here, the offset is not hpelessly large and we want to keep candidates from this field
 fi

 
 echo "Running solve_plate_with_UCAC5" >> transient_factory_test31.txt
 for i in `cat vast_image_details.log | awk '{print $17}' | sort | uniq` ;do 
  # This should ensure the correct field-of-view guess by setting the TELESCOP keyword
  TELESCOP="NMW_camera" util/solve_plate_with_UCAC5 --no_photometric_catalog --iterations 1  $i  &
 done 

 # We need UCAC5 solution for the first and the third images
# util/solve_plate_with_UCAC5 --no_photometric_catalog --iterations 1 `cat vast_image_details.log | awk '{print $17}' | head -n1 | tail -n1` &
# util/solve_plate_with_UCAC5 --no_photometric_catalog --iterations 1 `cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1` &
 #
# util/solve_plate_with_UCAC5 --no_photometric_catalog --iterations 1 `cat vast_image_details.log | awk '{print $17}' | head -n2 | tail -n1` &
# util/solve_plate_with_UCAC5 --no_photometric_catalog --iterations 1 `cat vast_image_details.log | awk '{print $17}' | head -n4 | tail -n1` &
 # wait # moved down

 
 echo "Calibrating the magnitude scale with Tycho-2 stars" >> transient_factory_test31.txt
 if [ -f 'lightcurve.tmp_emergency_stop_debug' ];then
  rm -f 'lightcurve.tmp_emergency_stop_debug'
 fi
 # Calibrate magnitude scale with Tycho-2 stars in the field
 # In order for this to work, we need the plate-solved reference image 
 WCS_IMAGE_NAME_FOR_CHECKS=wcs_`basename $REFERENCE_EPOCH__FIRST_IMAGE`
 WCS_IMAGE_NAME_FOR_CHECKS="${WCS_IMAGE_NAME_FOR_CHECKS/wcs_wcs_/wcs_}"
 if [ ! -s "$WCS_IMAGE_NAME_FOR_CHECKS" ];then
  echo "$WCS_IMAGE_NAME_FOR_CHECKS does not exist or is empty: waiting for solve_plate_with_UCAC5" >> transient_factory_test31.txt
  # Wait here hoping util/solve_plate_with_UCAC5 will plate-solve the reference image
  ps --forest $(ps -e --no-header -o pid,ppid|awk -vp=$$ 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')  >> transient_factory_test31.txt
  echo "wait"   >> transient_factory_test31.txt
  wait
  ps --forest $(ps -e --no-header -o pid,ppid|awk -vp=$$ 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')  >> transient_factory_test31.txt
 else
  echo "Found non-empty $WCS_IMAGE_NAME_FOR_CHECKS" >> transient_factory_test31.txt
 fi
 # Print the process tree
 ps --forest $(ps -e --no-header -o pid,ppid|awk -vp=$$ 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')  >> transient_factory_test31.txt
 echo "____ Start of magnitude calibration ____" >> transient_factory_test31.txt
 echo "y" | util/transients/calibrate_current_field_with_tycho2.sh 2>&1 >> transient_factory_test31.txt
 echo "____ End of magnitude calibration ____" >> transient_factory_test31.txt
 MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=$?
 # Check that the magnitude calibration actually worked
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do 
  ### ===> MAGNITUDE LIMITS HARDCODED HERE <===
  cat "$i" | awk '{print $2}' | util/colstat 2>&1 | grep 'MEAN=' | awk '{if ( $2 < -5 && $2 >18 ) print "ERROR"}' | grep 'ERROR' && break
 done | grep --quiet 'ERROR'
 #
 if [ $? -eq 0 ];then
  # Wait for the solve_plate_with_UCAC5 stuff to finish
  wait
  # Throw an error
  echo "ERROR calibrating magnitudes in the field $FIELD (mean mag outside of range)"
  echo "ERROR calibrating magnitudes in the field $FIELD (mean mag outside of range)" >> transient_factory_test31.txt
  echo "***** MAGNITUDE CALIBRATION ERROR (candidate mag is out of the expected range) *****" >> transient_factory.log
  echo "############################################################" >> transient_factory.log
  # continue to the next field
  continue
 fi
 if [ $MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE -ne 0 ];then
  # Wait for the solve_plate_with_UCAC5 stuff to finish
  wait
  # Throw an error
  echo "ERROR calibrating magnitudes in the field $FIELD MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=$MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE"
  echo "ERROR calibrating magnitudes in the field $FIELD MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=$MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE" >> transient_factory_test31.txt
  echo "***** MAGNITUDE CALIBRATION ERROR (mag calibration script exited with code $MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE) *****" >> transient_factory.log
  echo "############################################################" >> transient_factory.log
  # continue to the next field
  continue
 fi
 if [ -f 'lightcurve.tmp_emergency_stop_debug' ];then
  # Wait for the solve_plate_with_UCAC5 stuff to finish
  wait
  # Throw an error
  echo "ERROR calibrating magnitudes in the field $FIELD (found lightcurve.tmp_emergency_stop_debug)"
  echo "ERROR calibrating magnitudes in the field $FIELD (found lightcurve.tmp_emergency_stop_debug)" >> transient_factory_test31.txt
  echo "############################################################" >> transient_factory_test31.txt
  cat lightcurve.tmp_emergency_stop_debug >> transient_factory_test31.txt
  echo "############################################################" >> transient_factory_test31.txt
  echo "***** MAGNITUDE CALIBRATION ERROR (lightcurve.tmp_emergency_stop_debug) *****" >> transient_factory.log
  echo "############################################################" >> transient_factory.log
  # continue to the next field
  continue
 fi

 ################## Quality cuts applied to calibrated magnitudes of the candidate transients ##################
 echo "Filter-out faint candidates..." >> transient_factory_test31.txt
 echo "Filter-out faint candidates..."
 # Filter-out faint candidates
 ### ===> MAGNITUDE LIMITS HARDCODED HERE <===
 #for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2">11.5"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 #for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2">12.0"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 #for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($1+$2)/2>12.0 ) print 1; else print 0 }'` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 #for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2">12.5"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 #for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2">13.0"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2">13.5"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

 echo "Filter-out suspiciously bright candidates..." >> transient_factory_test31.txt
 echo "Filter-out suspiciously bright candidates..."
 # Filter-out suspiciously bright candidates
 ### ===> MAGNITUDE LIMITS HARDCODED HERE <===
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2"<-5.0"}'|bc -ql` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

 echo "Filter-out candidates with large difference between measured mags in one epoch..." >> transient_factory_test31.txt
 echo "Filter-out candidates with large difference between measured mags in one epoch..."
 # 2nd epoch
 #cp candidates-transients.lst DEBUG_BACKUP_candidates-transients.lst
 # Filter-out candidates with large difference between measured mags
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($1-$2)>0.4 ) print 1; else print 0 }'` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 # Filter-out candidates with large difference between measured mags
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do A=`tail -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($2-$1)>0.4 ) print 1; else print 0 }'` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 # 1st epoch (only for sources detected on two reference images)
 # Filter-out candidates with large difference between measured mags
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do if [ `cat $i | wc -l` -lt 4 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=`head -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($1-$2)>1.0 ) print 1; else print 0 }'` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 # Filter-out candidates with large difference between measured mags
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do if [ `cat $i | wc -l` -lt 4 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=`head -n2 $i | awk '{print $2}'` ; TEST=`echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($2-$1)>1.0 ) print 1; else print 0 }'` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

 ############################################
 # Remove candidates close to frame edge
 DIMX=`util/listhead "$SECOND_EPOCH__SECOND_IMAGE" | grep NAXIS1 | awk '{print $3}'`
 DIMY=`util/listhead "$SECOND_EPOCH__SECOND_IMAGE" | grep NAXIS2 | awk '{print $3}'`
 ### ===> IMAGE EDGE OFFSET HARDCODED HERE <===
 FRAME_EDGE_OFFSET_PIX=30
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do 
  cat $i | awk "{if ( \$4>$FRAME_EDGE_OFFSET_PIX && \$4<$DIMX-$FRAME_EDGE_OFFSET_PIX && \$5>$FRAME_EDGE_OFFSET_PIX && \$5<$DIMY-$FRAME_EDGE_OFFSET_PIX ) print \"YES\"; else print \"NO\" }" | grep --quiet 'NO'
  if [ $TEST -eq 0 ];then 
   grep $i candidates-transients.lst | head -n1 
  fi
 done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
 ############################################

 echo "Filter-out small-amplitude flares..." >> transient_factory_test31.txt
 echo "Filter-out small-amplitude flares..."
 # Filter-out small-amplitude flares
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do if [ `cat $i | wc -l` -eq 2 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=`head -n1 $i | awk '{print $2}'` ; B=`tail -n2 $i | awk '{print $2}'` ; MEANMAGSECONDEPOCH=`echo ${B//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2}'` ; TEST=`echo $A $MEANMAGSECONDEPOCH | awk '{if ( ($1-$2)<0.5 ) print 1; else print 0 }'` ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

 # Make sure each candidate is detected on the two second-epoch images, not any other combination
 for i in `cat candidates-transients.lst | awk '{print $1}'` ;do 
  grep --quiet "$SECOND_EPOCH__FIRST_IMAGE" "$i"
  if [ $? -ne 0 ];then
   continue
  fi
  grep --quiet "$SECOND_EPOCH__SECOND_IMAGE" "$i"
  if [ $? -ne 0 ];then
   continue
  fi
  grep $i candidates-transients.lst | head -n1 
 done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

 ### Prepare the exclusion lists for this field
 echo "Preparing the exclusion lists for this field" >> transient_factory_test31.txt
 # Exclude the previously considered candidates
 if [ ! -s exclusion_list.txt ];then
  if [ -s ../exclusion_list.txt ];then
   SECOND_EPOCH_IMAGE_ONE=`cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1`
   WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE=wcs_`basename $SECOND_EPOCH_IMAGE_ONE`
   lib/bin/sky2xy $WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE @../exclusion_list.txt | grep -v -e 'off image' -e 'offscale' | awk '{print $1" "$2}' > exclusion_list.txt
   cp -v exclusion_list.txt local_wcs_cache/ >> transient_factory_test31.txt
  fi
 fi
 # Exclude stars from the Bright Star Catalog with magnitudes < 3
 if [ ! -s exclusion_list_bbsc.txt ];then
  if [ -s lib/catalogs/brightbright_star_catalog_radeconly.txt ];then
   SECOND_EPOCH_IMAGE_ONE=`cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1`
   WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE=wcs_`basename $SECOND_EPOCH_IMAGE_ONE`
   lib/bin/sky2xy $WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE @lib/catalogs/brightbright_star_catalog_radeconly.txt | grep -v -e 'off image' -e 'offscale' | awk '{print $1" "$2}' > exclusion_list_bbsc.txt
   cp -v exclusion_list_bbsc.txt local_wcs_cache/ >> transient_factory_test31.txt
  fi
 fi
 # Exclude stars from the Bright Star Catalog with magnitudes < 7
 if [ ! -s exclusion_list_bsc.txt ];then
  if [ -s lib/catalogs/bright_star_catalog_radeconly.txt ];then
   SECOND_EPOCH_IMAGE_ONE=`cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1`
   WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE=wcs_`basename $SECOND_EPOCH_IMAGE_ONE`
   lib/bin/sky2xy $WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE @lib/catalogs/bright_star_catalog_radeconly.txt | grep -v -e 'off image' -e 'offscale' | awk '{print $1" "$2}' > exclusion_list_bsc.txt
   cp -v exclusion_list_bsc.txt local_wcs_cache/ >> transient_factory_test31.txt
  fi
 fi
 # Exclude bright Tycho-2 stars, by default the magnitude limit is set to vt < 9
 if [ ! -s exclusion_list_tycho2.txt ];then
  if [ -s lib/catalogs/list_of_bright_stars_from_tycho2.txt ];then
   SECOND_EPOCH_IMAGE_ONE=`cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1`
   WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE=wcs_`basename $SECOND_EPOCH_IMAGE_ONE`
   lib/bin/sky2xy $WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE @lib/catalogs/list_of_bright_stars_from_tycho2.txt | grep -v -e 'off image' -e 'offscale' | awk '{print $1" "$2}' | while read A ;do lib/deg2hms $A ;done > exclusion_list_tycho2.txt
   cp -v exclusion_list_tycho2.txt local_wcs_cache/ >> transient_factory_test31.txt
  fi
 fi
 ###
 echo "Done with filtering" >> transient_factory_test31.txt
 echo "Done with filtering! =)"
 ###############################################################################################################

 # Check if the number of detected transients is suspiciously large
 #NUMBER_OF_DETECTED_TRANSIENTS=`cat vast_summary.log |grep "Transient candidates found:" | awk '{print $4}'`
 NUMBER_OF_DETECTED_TRANSIENTS=`cat candidates-transients.lst | wc -l`
 echo "Found $NUMBER_OF_DETECTED_TRANSIENTS candidate transients before the final filtering." >> transient_factory_test31.txt
 if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt 500 ];then
  echo "WARNING! Too many candidates before filtering ($NUMBER_OF_DETECTED_TRANSIENTS)... Skipping field..."
  echo "ERROR Too many candidates before filtering ($NUMBER_OF_DETECTED_TRANSIENTS)... Skipping field..." >> transient_factory_test31.txt
  continue
 fi
 if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt 400 ];then
  echo "WARNING! Too many candidates before filtering ($NUMBER_OF_DETECTED_TRANSIENTS)... Dropping flares..."
  echo "ERROR Too many candidates before filtering ($NUMBER_OF_DETECTED_TRANSIENTS)... Dropping flares..." >> transient_factory_test31.txt
  # if yes, remove flares, keep only new objects
  while read FLAREOUTFILE A B ;do
   grep -v $FLAREOUTFILE candidates-transients.lst > candidates-transients.tmp
   mv candidates-transients.tmp candidates-transients.lst
  done < candidates-flares.lst
 fi

 echo "Waiting for UCAC5 plate solver" >> transient_factory_test31.txt  
 echo "Waiting for UCAC5 plate solver"
 # this is for UCAC5 plate solver
 wait
 echo "Preparing the HTML report for the field $FIELD with $SEXTRACTOR_CONFIG_FILE" >> transient_factory_test31.txt
 echo "Preparing the HTML report for the field $FIELD with $SEXTRACTOR_CONFIG_FILE"
 util/transients/make_report_in_HTML.sh >> transient_factory_test31.txt
 echo "Prepared the HTML report for the field $FIELD with $SEXTRACTOR_CONFIG_FILE" >> transient_factory_test31.txt
 echo "Prepared the HTML report for the field $FIELD with $SEXTRACTOR_CONFIG_FILE"
 
 echo "*------ done with $SEXTRACTOR_CONFIG_FILE ------*" >> transient_factory_test31.txt
 echo "*------ done with $SEXTRACTOR_CONFIG_FILE ------*"

 # Update the local exclusion list (but actually util/transients/report_transient.sh is supposed to take care of that already)
 echo "Updating exclusion_list_local.txt" >> transient_factory_test31.txt
 echo "Updating exclusion_list_local.txt"
 grep -A1 'Mean magnitude and position on the discovery images:' transient_report/index.html | grep -v 'Mean magnitude and position on the discovery images:' | awk '{print $6" "$7}' | sed '/^\s*$/d' >> exclusion_list_local.txt
 echo "#### The local exclusion list is exclusion_list_local.txt ####" >> transient_factory_test31.txt
 cat exclusion_list_local.txt >> transient_factory_test31.txt
 #

 done # for SEXTRACTOR_CONFIG_FILE in default.sex.telephoto_lens_onlybrightstars_v1 default.sex.telephoto_lens_v4 ;do

 # clean up the local cache
 # We should not remove exclusion_list_gaiadr2.txt and exclusion_list_apass.txt as we want to use them later
 for FILE_TO_REMOVE in local_wcs_cache/* exclusion_list.txt exclusion_list_bsc.txt exclusion_list_bbsc.txt exclusion_list_tycho2.txt ;do
  if [ -f "$FILE_TO_REMOVE" ];then
   rm -f "$FILE_TO_REMOVE"
   echo "Removing $FILE_TO_REMOVE" >> transient_factory_test31.txt
  fi
 done

 # We need a local exclusion list not to find the same things in multiple SExtractor runs
 if [ -f exclusion_list_local.txt ];then
  rm -f exclusion_list_local.txt
 fi
 
 echo "########### Completed $FIELD ###########" >> transient_factory_test31.txt
 
done # for i in "$NEW_IMAGES"/*_001.fts ;do

done # for NEW_IMAGES in $@ ;do

## Automatically update the exclusion list if we are on a production server
HOST=`hostname`
echo "The analysis was running at $HOST" >> transient_factory_test31.txt
# remove restrictions on host for exclusion list update
#if [ "$HOST" = "scan" ] || [ "$HOST" = "vast" ] || [ "$HOST" = "eridan" ];then
 echo "We are allowed to update the exclusion list at $HOST host" >> transient_factory_test31.txt
 IS_THIS_TEST_RUN="NO"
 # if we are not in the test directory
 echo "$PWD" "$@" | grep --quiet -e 'vast_test' -e 'saturn_test' -e 'test' -e 'Test' -e 'TEST'
 if [ $? -ne 0 ] ;then
  IS_THIS_TEST_RUN="YES"
  echo "The names $PWD $@ suggest this is a test run"
  echo "The names $PWD $@ suggest this is a test run" >> transient_factory_test31.txt
 fi
 echo "$1" | grep --quiet -e 'NMW_Vul2_magnitude_calibration_exit_code_test' -e 'NMW_Sgr9_crash_test'
 if [ $? -eq 0 ] ;then
  IS_THIS_TEST_RUN="NO"
  echo "Allowing the exclusion list update for $1"
  echo "Allowing the exclusion list update for $1" >> transient_factory_test31.txt
 fi
 if [ "$IS_THIS_TEST_RUN" != "YES" ];then
  # the NMW_Vul2_magnitude_calibration_exit_code_test tests for exclusion listupdate
  # and ../NMW_Sgr9_crash_test/second_epoch_images is for that purpose too
  echo "This does not look like a test run" >> transient_factory_test31.txt
  if [ -f ../exclusion_list.txt ];then
   echo "Found ../exclusion_list.txt" >> transient_factory_test31.txt
   grep -A1 'Mean magnitude and position on the discovery images:' transient_report/index.html | grep -v 'Mean magnitude and position on the discovery images:' | awk '{print $6" "$7}' | sed '/^\s*$/d' > exclusion_list_index_html.txt
   # Filter-out asteroids
   echo "#### The exclusion list before filtering-out asteroids, bad pixels and adding Gaia sources ####" >> transient_factory_test31.txt
   cat exclusion_list_index_html.txt >> transient_factory_test31.txt
   echo "###################################################################################" >> transient_factory_test31.txt
   while read RADECSTR ;do
    grep --max-count=1 -A8 "$RADECSTR" transient_report/index.html | grep 'astcheck' | grep --quiet 'not found'
    if [ $? -eq 0 ];then
     echo "$RADECSTR"
     echo "$RADECSTR  -- not an asteroid (will add it to exclusion list)" >> transient_factory_test31.txt
    else
     echo "$RADECSTR  -- asteroid (will NOT add it to exclusion list)" >> transient_factory_test31.txt
    fi
   done < exclusion_list_index_html.txt > exclusion_list_index_html.txt_noasteroids
   mv -v exclusion_list_index_html.txt_noasteroids exclusion_list_index_html.txt >> transient_factory_test31.txt
   #
   while read RADECSTR ;do
    grep --max-count=1 -A8 "$RADECSTR" transient_report/index.html | grep 'galactic' | grep --quiet '<font color="red">0.0</font></b> pix'
    if [ $? -ne 0 ];then
     echo "$RADECSTR"
     echo "$RADECSTR  -- does not seem to be a hot pixel (will add it to exclusion list)" >> transient_factory_test31.txt
    else
     echo "$RADECSTR  -- seems to be a hot pixel (will NOT add it to exclusion list)" >> transient_factory_test31.txt
    fi
   done < exclusion_list_index_html.txt > exclusion_list_index_html.txt_nohotpixels
   mv -v exclusion_list_index_html.txt_nohotpixels exclusion_list_index_html.txt >> transient_factory_test31.txt
   #
   echo "###################################################################################" >> transient_factory_test31.txt
   ALLOW_EXCLUSION_LIST_UPDATE="YES"
   N_CANDIDATES_EXCLUDING_ASTEROIDS_AND_HOT_PIXELS=`cat exclusion_list_index_html.txt | wc -l`
   echo "$N_CANDIDATES_EXCLUDING_ASTEROIDS_AND_HOT_PIXELS candidates found (excluding asteroids and hot pixels)" >> transient_factory_test31.txt
   # Do this check only if we are processing a single field
   if [ -z "$2" ];then
    ### ===> ASSUMED MAX NUMBER OF CANDIDATES <===
    if [ $N_CANDIDATES_EXCLUDING_ASTEROIDS_AND_HOT_PIXELS -gt 20 ];then
     echo "ERROR: too many candidates -- $N_CANDIDATES_EXCLUDING_ASTEROIDS_AND_HOT_PIXELS (excluding ateroids and hot pixels), not updating the exclusion list!"
     echo "ERROR: too many candidates -- $N_CANDIDATES_EXCLUDING_ASTEROIDS_AND_HOT_PIXELS (excluding ateroids and hot pixels), not updating the exclusion list!" >> transient_factory_test31.txt
     ALLOW_EXCLUSION_LIST_UPDATE="NO"
    fi
   fi
   echo "###################################################################################" >> transient_factory_test31.txt
   if [ "$ALLOW_EXCLUSION_LIST_UPDATE" = "YES" ];then
    #
    if [ -f exclusion_list_gaiadr2.txt ];then
     if [ -s exclusion_list_gaiadr2.txt ];then
      echo "Adding identified Gaia sources from exclusion_list_gaiadr2.txt" >> transient_factory_test31.txt
      cat exclusion_list_gaiadr2.txt >> exclusion_list_index_html.txt
     else
      echo "exclusion_list_gaiadr2.txt is empty - nothing to add to the exclusion list" >> transient_factory_test31.txt
     fi
     rm -f exclusion_list_gaiadr2.txt
    else
     echo "exclusion_list_gaiadr2.txt NOT FOUND" >> transient_factory_test31.txt
    fi
    #
    if [ -f exclusion_list_apass.txt ];then
     if [ -s exclusion_list_apass.txt ];then
      echo "Adding identified Gaia sources from exclusion_list_apass.txt" >> transient_factory_test31.txt
      cat exclusion_list_apass.txt >> exclusion_list_index_html.txt
     else
      echo "exclusion_list_apass.txt is empty - nothing to add to the exclusion list" >> transient_factory_test31.txt
     fi
     rm -f exclusion_list_apass.txt
    else
     echo "exclusion_list_apass.txt NOT FOUND" >> transient_factory_test31.txt
    fi
    #
    # Write to ../exclusion_list.txt in a single operation in a miserable attempt to minimize chances of a race condition
    if [ -f exclusion_list_index_html.txt ];then
     if [ -s exclusion_list_index_html.txt ];then
      echo "#### Adding the following to the exclusion list ####" >> transient_factory_test31.txt
      cat exclusion_list_index_html.txt >> transient_factory_test31.txt
      echo "####################################################" >> transient_factory_test31.txt
      cat exclusion_list_index_html.txt >> ../exclusion_list.txt
     else
      echo "#### Nothing to add to the exclusion list ####" >> transient_factory_test31.txt
     fi
     rm -f exclusion_list_index_html.txt
    else
     echo "exclusion_list_index_html.txt NOT FOUND" >> transient_factory_test31.txt
    fi
   else
    echo "NOT found ../exclusion_list.txt" >> transient_factory_test31.txt
   fi
  else
   echo "This looks like a test run so we are not updating exclusion list" >> transient_factory_test31.txt
   echo "$PWD" | grep --quiet -e 'vast_test' -e 'saturn_test' -e 'test' -e 'Test' -e 'TEST' >> transient_factory_test31.txt
  fi
 else
  echo "We are not updating exclusion list - too many candidates for a single field" >> transient_factory_test31.txt
 fi # if [ "$ALLOW_EXCLUSION_LIST_UPDATE" = "YES" ];then
#fi # host
## exclusion list update
 

## Finalize the HTML report
echo "<H2>Processig complete!</H2>" >> transient_report/index.html

echo "<H3>Processing log:</H3>
<pre>" >> transient_report/index.html
cat transient_factory.log >> transient_report/index.html
echo "</pre>" >> transient_report/index.html

echo "<H3>Filtering log:</H3>
<pre>" >> transient_report/index.html
cat transient_factory_test31.txt >> transient_report/index.html
echo "</pre>" >> transient_report/index.html

echo "</BODY></HTML>" >> transient_report/index.html


# The uncleaned directory is needed for the test script
#util/clean_data.sh

