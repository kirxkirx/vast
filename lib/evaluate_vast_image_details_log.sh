#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ ! -f vast_image_details.log ];then
 echo "ERROR: cannot find vast_image_details.log"
 exit 1
fi
if [ ! -s vast_image_details.log ];then
 echo "ERROR: vast_image_details.log is empty"
 exit 1
fi

if [ ! -f vast_summary.log ];then
 echo "ERROR: cannot find vast_summary.log"
 exit 1
fi
if [ ! -s vast_summary.log ];then
 echo "ERROR: vast_summary.log is empty"
 exit 1
fi

# Check if the reference image is much worth than the other images
REF_IMAGE=`grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
N_STARS_DETECTED_ON_REF_IMG=`grep --max-count=1 "$REF_IMAGE" vast_image_details.log | awk '{print $13}'`
MEDIAN_N_STARS_DETECTED=`cat vast_image_details.log | awk '{print $13}' | util/colstat 2>/dev/null | grep 'MEDIAN=' | awk '{print $2}'`
SIGMA_N_STARS_DETECTED=`cat vast_image_details.log | awk '{print $13}' | util/colstat 2>/dev/null | grep 'MAD\*1.48=' | awk '{print $2}'`

#echo "$N_STARS_DETECTED_ON_REF_IMG $MEDIAN_N_STARS_DETECTED $SIGMA_N_STARS_DETECTED" | awk '{if ( $1 < $2-$3 ) printf "\n\n #### Check the reference image - it seems to have too few stars! ####\n\n" ;else printf "The reference image seems OK.\n" }'

#echo "$N_STARS_DETECTED_ON_REF_IMG $MEDIAN_N_STARS_DETECTED $SIGMA_N_STARS_DETECTED"

echo "$N_STARS_DETECTED_ON_REF_IMG $MEDIAN_N_STARS_DETECTED $SIGMA_N_STARS_DETECTED" | awk '{if ( $1 < $2-$3 && $2-$1 > 10 ) printf "\n\n #### Check the reference image - it seems to have too few stars! ####\n\n" ;else printf "The reference image seems OK.\n" }'


