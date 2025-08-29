#!/usr/bin/env bash
#
# This script writes out a short summary about the possible transient.
# It is normally called by other scripts like util/transients/transient_factory_test31.sh
# and is not supposed to be run directly by user.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

trap 'clean_tmp_files' EXIT HUP INT QUIT TERM


# Parse the command line arguments
if [ -z $1 ]; then
 echo "Usage: $0 outNUMBER.dat"
 exit 1
fi
LIGHTCURVEFILE=$1

# Check that the input file is there
if [ ! -f "$LIGHTCURVEFILE" ];then
 echo "ERROR in $0: the input lightcurve file $LIGHTCURVEFILE does not exist!"
 exit 1
fi
if [ ! -s "$LIGHTCURVEFILE" ];then
 echo "ERROR in $0: the input lightcurve file $LIGHTCURVEFILE is empty!"
 exit 1
fi

## Find Source Extractor
#SEXTRACTOR=`command -v sex 2>/dev/null`
#if [ "" = "$SEXTRACTOR" ];then
# SEXTRACTOR=lib/bin/sex
#fi

#################################

REPORT_TRANSIENT_TMPFILE_JD=$(mktemp 2>/dev/null || echo "jd$$.dat")
export REPORT_TRANSIENT_TMPFILE_JD
REPORT_TRANSIENT_TMPFILE_RA=$(mktemp 2>/dev/null || echo "ra$$.dat")
export REPORT_TRANSIENT_TMPFILE_RA
REPORT_TRANSIENT_TMPFILE_DEC=$(mktemp 2>/dev/null || echo "dec$$.dat")
export REPORT_TRANSIENT_TMPFILE_DEC
REPORT_TRANSIENT_TMPFILE_MAG=$(mktemp 2>/dev/null || echo "mag$$.dat")
export REPORT_TRANSIENT_TMPFILE_MAG
REPORT_TRANSIENT_TMPFILE_X=$(mktemp 2>/dev/null || echo "x$$.dat")
export REPORT_TRANSIENT_TMPFILE_X
REPORT_TRANSIENT_TMPFILE_Y=$(mktemp 2>/dev/null || echo "y$$.dat")
export REPORT_TRANSIENT_TMPFILE_Y
REPORT_TRANSIENT_TMPFILE_SCRIPT=$(mktemp 2>/dev/null || echo "script$$.dat")
export REPORT_TRANSIENT_TMPFILE_SCRIPT

#################################


######### function to clean-up the temporary files before exiting #########
function clean_tmp_files {
 for TMP_FILE_TO_REMOVE in \
   "$REPORT_TRANSIENT_TMPFILE_JD" \
   "$REPORT_TRANSIENT_TMPFILE_RA" \
   "$REPORT_TRANSIENT_TMPFILE_DEC" \
   "$REPORT_TRANSIENT_TMPFILE_MAG" \
   "$REPORT_TRANSIENT_TMPFILE_X" \
   "$REPORT_TRANSIENT_TMPFILE_Y" \
   "$REPORT_TRANSIENT_TMPFILE_SCRIPT" \
   "${TEMP_FILE__SDWC_OUTPUT}" \
   "${TEMP_FILE__SDWC_OUTPUT}_exit_status.tmp" \
   "${TEMP_FILE__MPCheck_OUTPUT}" \
   "${TEMP_FILE__MPCheck_OUTPUT}_exit_status.tmp" \
   ra$$.dat dec$$.dat mag$$.dat script$$.dat dayfrac$$.dat jd$$.dat x$$.dat y$$.dat \
   tempilefallback_SDWC_OUTPUT_$$.tmp tempilefallback_MPCheck_OUTPUT_$$.tmp
 do
  if [ -n "$TMP_FILE_TO_REMOVE" ] && [ -f "$TMP_FILE_TO_REMOVE" ]; then
   rm -f "$TMP_FILE_TO_REMOVE"
  fi
 done
}


# TRAP!! If we whant to identify a flare, there will be no sense to search for an asteroid on the reference image.
# Use the first discovery image instead!
REFERENCE_IMAGE=$(cat vast_summary.log |grep "Ref.  image:" | awk '{print $6}')

# Assume that the second first-epoch image is always supplied as the second image on the command line
SECOND_REFERENCE_IMAGE=$(cat vast_image_details.log | head -n2 | tail -n1 | awk '{print $17}')

#     Reference image    2010 12 10.0833  2455540.5834  13.61  06:29:12.25 +26:24:19.4
echo "<table style='font-family:monospace;font-size:12px;'>
<tr><th></th><th>                     Date (UTC)   </th><th>    JD(UTC)  </th><th>    mag. </th><th> R.A. & Dec.(J2000)   </th><th>X & Y (pix)</th><th>    Image</th></tr>"

N=0

# Make sure there are no files with names we want to use
clean_tmp_files

while read JD MAG MERR X Y APP FITSFILE REST ;do
 # At this point, we should somehow have a WCS calibrated image named $WCS_IMAGE_NAME
 WCS_IMAGE_NAME=wcs_$(basename "$FITSFILE")
 WCS_IMAGE_NAME=${WCS_IMAGE_NAME/wcs_wcs_/wcs_}
 if [ ! -f $WCS_IMAGE_NAME ];then
  echo "ERROR: cannot find plate-solved image $WCS_IMAGE_NAME" 
  clean_tmp_files
  exit 1
 fi
 SEXTRACTOR_CATALOG_NAME="$WCS_IMAGE_NAME".cat
 UCAC5_SOLUTION_NAME="$WCS_IMAGE_NAME".cat.ucac5
 # util/solve_plate_with_UCAC5 is supposed to be called before running this script
 DATE_INFO=$(util/get_image_date "$FITSFILE" 2>&1)
 JD_FROM_IMAGE_HEADER=$(echo "$DATE_INFO" | grep -v '= JD' | grep '        JD ' | awk '{print $2}')
 YEAR=$(echo "$DATE_INFO" | grep 'MPC format' | awk '{print $3}')
 MONTH=$(echo "$DATE_INFO" | grep 'MPC format' | awk '{print $4}')
 # Currently util/get_image_date prints 'MPC format' with five decimal places
 DAYFRAC=$(echo "$DATE_INFO" | grep 'MPC format' | awk '{printf "%.6f", $5}')
 # If there is a UCAC5 plate solution with local corrections - use it,
 # otherwise rely on the positions computed using only the WCS header
 if [ -f $UCAC5_SOLUTION_NAME ];then
  # this is used by util/transients/transient_factory_test31.sh
  RADEC=$(lib/find_star_in_wcs_catalog $X $Y < $UCAC5_SOLUTION_NAME)
  if [ $? -ne 0 ];then
   echo "(1) error in $0 filed to run  lib/find_star_in_wcs_catalog $X $Y < $UCAC5_SOLUTION_NAME"
   clean_tmp_files
   exit 1
  fi
 elif [ -f $SEXTRACTOR_CATALOG_NAME ];then
  # this is used by util/transients/report_transient.sh
  RADEC=$(lib/find_star_in_wcs_catalog $X $Y < $SEXTRACTOR_CATALOG_NAME)
  if [ $? -ne 0 ];then
   echo "(2) error in $0 filed to run  lib/find_star_in_wcs_catalog $X $Y < $SEXTRACTOR_CATALOG_NAME"
   clean_tmp_files
   exit 1
  fi
 else
  echo "error in $0 cannot find any of the plate-solved-image-related catalogs: $UCAC5_SOLUTION_NAME $SEXTRACTOR_CATALOG_NAME" 
  clean_tmp_files
  exit 1
 fi
 #
 RA=$(echo $RADEC | awk '{print $1}')
 DEC=$(echo $RADEC | awk '{print $2}')
 MAG=$(echo $MAG | awk '{printf "%.2f",$1}')

 # Do not use the first-epoch images for computing average values (positions, dates, magnitdes)
 if [ "$FITSFILE" != "$REFERENCE_IMAGE" ] && [ "$FITSFILE" != "$SECOND_REFERENCE_IMAGE" ] ;then
  echo "$JD_FROM_IMAGE_HEADER" >> "$REPORT_TRANSIENT_TMPFILE_JD"
  echo "$RA" >> "$REPORT_TRANSIENT_TMPFILE_RA"
  echo "$DEC" >> "$REPORT_TRANSIENT_TMPFILE_DEC"
  echo "$MAG" >> "$REPORT_TRANSIENT_TMPFILE_MAG"
  echo "$X" >> "$REPORT_TRANSIENT_TMPFILE_X"
  echo "$Y" >> "$REPORT_TRANSIENT_TMPFILE_Y"
 fi
 
 if [ "$FITSFILE" != "$REFERENCE_IMAGE" ] ;then
  N=$[$N+1]
  echo -n "<tr><td>Discovery image $N   &nbsp;&nbsp;</td>"
 else
  echo -n "<tr><td>Reference image     &nbsp;&nbsp;</td>"
 fi # if [ "$FITSFILE" != "$REFERENCE_IMAGE" ] ;then
 #DAYFRAC_SHORT=$(echo "$DAYFRAC" | awk '{printf "%08.5f\n",$1}') # for visualisation purposes and will be used for MPC stub by make_report_in_HTML.sh
 #JD_SHORT=$(echo "$JD_FROM_IMAGE_HEADER" | awk '{printf "%.5f",$1}') # purely for visualisation purposes
 #X=$(echo "$X" | awk '{printf "%04.0f",$1}') # purely for visualisation purposes
 #Y=$(echo "$Y" | awk '{printf "%04.0f",$1}') # purely for visualisation purposes
 DAYFRAC_SHORT=$(printf "%08.5f" "$DAYFRAC") # for visualisation purposes and will be used for MPC stub by make_report_in_HTML.sh
 JD_SHORT=$(printf "%.5f" "$JD_FROM_IMAGE_HEADER") # purely for visualisation purposes
 X=$(printf "%04.0f" "$X") # purely for visualisation purposes
 Y=$(printf "%04.0f" "$Y") # purely for visualisation purposes
 echo "<td>$YEAR $MONTH $DAYFRAC_SHORT &nbsp;&nbsp;</td><td> $JD_SHORT &nbsp;&nbsp;</td><td> $MAG &nbsp;&nbsp;</td><td>" $(lib/deg2hms $RADEC) "&nbsp;&nbsp;</td><td>$X $Y &nbsp;&nbsp;</td><td>$FITSFILE</td></tr>"
done < $LIGHTCURVEFILE
echo "</table>"

# We need to reformat util/colstat output to make it look like a small shell script
util/colstat < "$REPORT_TRANSIENT_TMPFILE_RA" 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > "$REPORT_TRANSIENT_TMPFILE_SCRIPT"
if [ $? -ne 0 ];then
 echo "ERROR running util/colstat in $0" 
 clean_tmp_files
 exit 1
fi
. "$REPORT_TRANSIENT_TMPFILE_SCRIPT"
if [ $? -ne 0 ];then
 echo "ERROR running $REPORT_TRANSIENT_TMPFILE_SCRIPT in $0" 
 clean_tmp_files
 exit 1
fi
RA_MEAN=$MEAN
# We remove '+' because bc doesn't like it
RA_MEAN=${RA_MEAN//"+"/}
RA_MAX=$MAX
RA_MAX=${RA_MAX//"+"/}
RA_MIN=$MIN
RA_MIN=${RA_MIN//"+"/}

util/colstat < "$REPORT_TRANSIENT_TMPFILE_DEC" 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > "$REPORT_TRANSIENT_TMPFILE_SCRIPT"
if [ $? -ne 0 ];then
 echo "ERROR0003 in $0" 
 clean_tmp_files
 exit 1
fi
. "$REPORT_TRANSIENT_TMPFILE_SCRIPT"
if [ $? -ne 0 ];then
 echo "ERROR0004 in $0" 
 clean_tmp_files
 exit 1
fi
DEC_MEAN=$MEAN
DEC_MEAN=${DEC_MEAN//"+"/}
DEC_MAX=$MAX
DEC_MAX=${DEC_MAX//"+"/}
DEC_MIN=$MIN
DEC_MIN=${DEC_MIN//"+"/}

util/colstat < "$REPORT_TRANSIENT_TMPFILE_MAG" 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > "$REPORT_TRANSIENT_TMPFILE_SCRIPT"
if [ $? -ne 0 ];then
 echo "ERROR0005 in $0" 
 clean_tmp_files
 exit 1
fi
. "$REPORT_TRANSIENT_TMPFILE_SCRIPT"
if [ $? -ne 0 ];then
 echo "ERROR0006 in $0" 
 clean_tmp_files
 exit 1
fi
MAG_MEAN=$(echo "$MEAN" | awk '{printf "%5.2f",$1}')
MAG_MEAN=${MAG_MEAN//"+"/}


util/colstat < "$REPORT_TRANSIENT_TMPFILE_JD" 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > "$REPORT_TRANSIENT_TMPFILE_SCRIPT"
if [ $? -ne 0 ];then
 echo "ERROR0009 in $0" 
 clean_tmp_files
 exit 1
fi
##########################
# debug
#cp "$REPORT_TRANSIENT_TMPFILE_SCRIPT" /tmp/script_test.tmp
#cp "$REPORT_TRANSIENT_TMPFILE_JD" /tmp/jd_test.tmp
##########################
. "$REPORT_TRANSIENT_TMPFILE_SCRIPT"
if [ $? -ne 0 ];then
 echo "ERROR0010 in $0" 
 clean_tmp_files
 exit 1
fi
JD_MEAN="$MEAN"
JD_MEAN_SHORT=$(echo $JD_MEAN |awk '{printf "%.4f",$1}')
DATE_INFO=$(util/get_image_date "$JD_MEAN" 2>&1)
#YEAR_MEAN=$(echo "$DATE_INFO" | grep 'MPC format' | awk '{print $3}')
#MONTH_MEAN=$(echo "$DATE_INFO" | grep 'MPC format' | awk '{print $4}')
#DAYFRAC_MEAN=$(echo "$DATE_INFO" | grep 'MPC format' | awk '{printf "%08.5f",$5}')
#DAYFRAC_MEAN_SHORT=$(echo "$DAYFRAC_MEAN" | awk '{printf "%07.4f",$1}')
#DAYFRAC_MEAN_SUPERSHORT=$(echo "$DAYFRAC_MEAN" | awk '{printf "%05.2f",$1}')
YEAR_MEAN=$(echo "$DATE_INFO" | grep 'Dayfraction' | awk '{print $2}')
MONTH_MEAN=$(echo "$DATE_INFO" | grep 'Dayfraction' | awk '{print $3}')
DAYFRAC_MEAN=$(echo "$DATE_INFO" | grep 'Dayfraction' | awk '{printf "%08.5f",$4}')
DAYFRAC_MEAN_SHORT=$(echo "$DATE_INFO" | grep 'Dayfraction' | awk '{printf "%07.4f",$4}')
DAYFRAC_MEAN_SUPERSHORT=$(echo "$DATE_INFO" | grep 'Dayfraction' | awk '{printf "%05.2f",$4}')


#### Test for float numbers ####
for STRING_TO_TEST in "$RA_MEAN" "$RA_MAX" "$RA_MIN" "$DEC_MEAN" "$DEC_MAX" "$DEC_MIN" "$MAG_MEAN" "$DAYFRAC_MEAN" "$DAYFRAC_MEAN_SHORT" "$DAYFRAC_MEAN_SUPERSHORT" "$JD_MEAN" "$JD_MEAN_SHORT" ;do
 # remove leading and trailing white spaces from STRING_TO_TEST
 STRING_TO_TEST_NO_WHITESPCAES=$(echo "$STRING_TO_TEST" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
 re='^[+-]?[0-9]+([.][0-9]+)?$'
 #if ! [[ $STRING_TO_TEST =~ $re ]] ; then
 if ! [[ $STRING_TO_TEST_NO_WHITESPCAES =~ $re ]] ; then
  echo "ERROR in $0 : the string #$STRING_TO_TEST# is not a floating point number" 
  clean_tmp_files
  exit 1
 fi
done
################################
RA_SECOND_EPOCH_1=$(cat "$REPORT_TRANSIENT_TMPFILE_RA" | head -n1)
DEC_SECOND_EPOCH_1=$(cat "$REPORT_TRANSIENT_TMPFILE_DEC" | head -n1)
RA_SECOND_EPOCH_2=$(cat "$REPORT_TRANSIENT_TMPFILE_RA" | tail -n1)
DEC_SECOND_EPOCH_2=$(cat "$REPORT_TRANSIENT_TMPFILE_DEC" | tail -n1)

ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING=$(lib/put_two_sources_in_one_field "$RA_SECOND_EPOCH_1" "$DEC_SECOND_EPOCH_1"  "$RA_SECOND_EPOCH_2" "$DEC_SECOND_EPOCH_2" 2>&1 | grep 'Angular distance')
ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING="${ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING/Angular/angular}"
ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING="${ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING/degrees/deg}"
ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC=$(echo "$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING" | awk '{printf "%.1f", $5*3600}')
ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_STRING="$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC"
#
if [ -z "$MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_SOFTLIMIT" ];then
 MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_SOFTLIMIT=8.4
fi
if [ -z "$MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_HARDLIMIT" ];then
 MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_HARDLIMIT=11
fi
if [ -z "$MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC" ];then
 MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC=$MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_HARDLIMIT
fi
#
# Drop the coordinates consistencey test for super-bright objects (that will have large astrometic errors)
TEST=$(echo "$MAG_MEAN>7.0" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
 # Reject candidates with large distance between the two second-epoch detections
 ### ==> Assumptio about positional accuracy hardcoded here <===
 TEST=$(echo "$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC>$MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_HARDLIMIT" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
 if [ $TEST -eq 1 ];then
  echo "Rejecting candidate due to large distance ($ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC\") between the two second-epoch detections"
  clean_tmp_files
  exit 1
 fi
 #
fi
# Highlight candidates with suspiciously large distance between the two second-epoch detections
### ==> Assumptio about positional accuracy hardcoded here <===
TEST=$(echo "$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC>$MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_SOFTLIMIT" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
 ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_STRING="<b><font color=\"red\">$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC</font></b>"
else
 ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_STRING="<font color=\"green\">$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC</font>"
fi

PIX_X_SECOND_EPOCH_1=$(cat "$REPORT_TRANSIENT_TMPFILE_X" | head -n1)
PIX_Y_SECOND_EPOCH_1=$(cat "$REPORT_TRANSIENT_TMPFILE_Y" | head -n1)
PIX_X_SECOND_EPOCH_2=$(cat "$REPORT_TRANSIENT_TMPFILE_X" | tail -n1)
PIX_Y_SECOND_EPOCH_2=$(cat "$REPORT_TRANSIENT_TMPFILE_Y" | tail -n1)
PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS=$(echo "$PIX_X_SECOND_EPOCH_1 $PIX_X_SECOND_EPOCH_2 $PIX_Y_SECOND_EPOCH_1 $PIX_Y_SECOND_EPOCH_2" | awk '{printf "%.1f", sqrt( ($1-$2)*($1-$2) + ($3-$4)*($3-$4) )}')
PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING="$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS"
### ==> Assumptio about shift between secon-spoch images hardcoded here <===
if [ "$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS" = "0.0" ] || [ "$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS" = "0.1" ] || [ "$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS" = "0.2" ] || [ "$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS" = "0.3" ] ;then
 PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING="<b><font color=\"red\">$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS</font></b>"
 if [ -n "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" ];then
  if [ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" = "yes" ];then
   echo "Rejecting candidate as there is no shift in pixel posiiton (shift $PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS pix) between the two second-epoch detections and REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES is set to '$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES'"
   clean_tmp_files
   exit 1   
  fi
 fi
else
 PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING="<font color=\"green\">$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS</font>"
fi

# Remove temporary files in case the script will exit after the final check
clean_tmp_files


RADEC_MEAN_HMS="$(lib/deg2hms $RA_MEAN $DEC_MEAN)"
RADEC_MEAN_HMS=${RADEC_MEAN_HMS//'\n'/}
RA_MEAN_HMS=$(echo "$RADEC_MEAN_HMS" | awk '{print $1}')
DEC_MEAN_HMS=$(echo "$RADEC_MEAN_HMS" | awk '{print $2}')
RA_MEAN_SPACES=${RA_MEAN_HMS//":"/" "}
DEC_MEAN_SPACES=${DEC_MEAN_HMS//":"/" "}



############
### Apply the never_exclude list to override all the following exclusion lists
SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT=0
STAR_IN_NEVEREXCLUDE_LIST_MESSAGE=""
EXCLUSION_LIST_FILE="neverexclude_list.txt"
if [ -s "$EXCLUSION_LIST_FILE" ];then
 lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC | grep --quiet "FOUND"
 if [ $? -eq 0 ];then
  SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT=1
  STAR_IN_NEVEREXCLUDE_LIST_MESSAGE="<b><font color=\"red\">This object is listed in $EXCLUSION_LIST_FILE</font> "$(lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC | grep "FOUND" | awk -F'FOUND' '{print $2}')"</b>"
 fi
fi
#
# Check if the transient is a planetary moon
# The difference with the never_exclude list is the search radius
if [ $SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT -eq 0 ] && [ -z "$THIS_IS_ARTIFICIAL_STAR_TEST_DO_NO_ONLINE_VSX_SEARCH" ];then
 EXCLUSION_LIST_FILE="moons.txt"
 if [ -s "$EXCLUSION_LIST_FILE" ];then
  EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC=180
  lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC | grep --quiet "FOUND"
  if [ $? -eq 0 ];then
   if [ -z "$THIS_IS_VAST_TEST" ];then
    SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT=1
   fi
   STAR_IN_NEVEREXCLUDE_LIST_MESSAGE="<b><font color=\"red\">This object is listed in $EXCLUSION_LIST_FILE</font> "$(lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC | grep "FOUND" | awk -F'FOUND' '{print $2}')"</b>"
  fi
 fi
fi
#
# Check if the transient is a major planet
# The difference with the never_exclude list is the search radius
if [ $SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT -eq 0 ] && [ -z "$THIS_IS_ARTIFICIAL_STAR_TEST_DO_NO_ONLINE_VSX_SEARCH" ];then
 EXCLUSION_LIST_FILE="planets.txt"
 if [ -s "$EXCLUSION_LIST_FILE" ];then
  EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC=900
  lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC | grep --quiet "FOUND"
  if [ $? -eq 0 ];then
   if [ -z "$THIS_IS_VAST_TEST" ];then
    SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT=1
   fi
   STAR_IN_NEVEREXCLUDE_LIST_MESSAGE="<b><font color=\"red\">This object is listed in $EXCLUSION_LIST_FILE</font> "$(lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC | grep "FOUND" | awk -F'FOUND' '{print $2}')"</b>"
  fi
 fi
fi
#
#
# Check if the transient is a bright comet
# The difference with the never_exclude list is the search radius
if [ $SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT -eq 0 ] && [ -z "$THIS_IS_ARTIFICIAL_STAR_TEST_DO_NO_ONLINE_VSX_SEARCH" ];then
 EXCLUSION_LIST_FILE="comets.txt"
 if [ -s "$EXCLUSION_LIST_FILE" ];then
  # The search radius has to match the one in util/transients/MPCheck_v2.sh
  EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC=61
  lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC | grep --quiet "FOUND"
  if [ $? -eq 0 ];then
   if [ -z "$THIS_IS_VAST_TEST" ];then
    SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT=1
   fi
   STAR_IN_NEVEREXCLUDE_LIST_MESSAGE="<b><font color=\"red\">This object is listed in $EXCLUSION_LIST_FILE</font> "$(lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC | grep "FOUND" | awk -F'FOUND' '{print $2}')"</b>"
  fi
 fi
fi
#
# Check if the transient was reported at TOCP
# The difference with the never_exclude list is the search radius
if [ $SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT -eq 0 ] && [ -z "$THIS_IS_ARTIFICIAL_STAR_TEST_DO_NO_ONLINE_VSX_SEARCH" ];then
 EXCLUSION_LIST_FILE="tocp_transients_list.txt"
 if [ -s "$EXCLUSION_LIST_FILE" ];then
  EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC=10
  lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC | grep --quiet "FOUND"
  if [ $? -eq 0 ];then
   # note that this might cause different behavior between the test and manual runs
   # by affecting the content of exclusion_list_local.txt
   if [ -z "$THIS_IS_VAST_TEST" ];then
    SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT=1
   fi
   STAR_IN_NEVEREXCLUDE_LIST_MESSAGE="<b><font color=\"red\">This object is listed in $EXCLUSION_LIST_FILE</font> "$(lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC | grep "FOUND" | awk -F'FOUND' '{print $2}')"</b>"
  fi
 fi
fi
#
#
# Check if the transient was recently seen by ASAS-SN
# The difference with the never_exclude list is the search radius
if [ $SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT -eq 0 ] && [ -z "$THIS_IS_ARTIFICIAL_STAR_TEST_DO_NO_ONLINE_VSX_SEARCH" ];then
 EXCLUSION_LIST_FILE="asassn_transients_list.txt"
 if [ -s "$EXCLUSION_LIST_FILE" ];then
  lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC | grep --quiet "FOUND"
  if [ $? -eq 0 ];then
   if [ -z "$THIS_IS_VAST_TEST" ];then
    SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT=1
   fi
   STAR_IN_NEVEREXCLUDE_LIST_MESSAGE="<b><font color=\"red\">This object is listed in $EXCLUSION_LIST_FILE</font> "$(lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC | grep "FOUND" | awk -F'FOUND' '{print $2}')"</b>"
  fi
 fi
fi
#
#
# Check if the transient is a spacecraft
# The difference with the never_exclude list is the search radius
if [ $SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT -eq 0 ] && [ -z "$THIS_IS_ARTIFICIAL_STAR_TEST_DO_NO_ONLINE_VSX_SEARCH" ];then
 EXCLUSION_LIST_FILE="spacecraft.txt"
 if [ -s "$EXCLUSION_LIST_FILE" ];then
  EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC=1800
  lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC | grep --quiet "FOUND"
  if [ $? -eq 0 ];then
   # I don't want this set for spacecraft as false IDs are very likely
   #if [ -z "$THIS_IS_VAST_TEST" ];then
   # SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT=1
   #fi
   STAR_IN_NEVEREXCLUDE_LIST_MESSAGE="<b><font color=\"red\">This object is listed in $EXCLUSION_LIST_FILE</font> "$(lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $EXCLUSION_LIST_FILE_CUSTOM_SEARCH_RADIUS_ARCSEC | grep "FOUND" | awk -F'FOUND' '{print $2}')"</b>"
  fi
 fi
fi
#
if [ $SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT -eq 0 ];then
 ### Apply the exclusion list. It may be generated from the previous-day(s) report file(s) 
 #
 # We are not making a 'for' cycle here because we want different exclusion radii to be applied to different catalogs
 EXCLUSION_LIST_FILE="exclusion_list.txt"
 if [ -s "$EXCLUSION_LIST_FILE" ];then
  # Exclude previously considered candidates
  lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC | grep --quiet "FOUND"
  if [ $? -eq 0 ];then
   echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE ****"
   clean_tmp_files
   exit 1
  fi
 fi 
 ### Apply the bright BSC bright stars exclusion list
 EXCLUSION_LIST_FILE="exclusion_list_bbsc.txt"
 if [ -s "$EXCLUSION_LIST_FILE" ];then
  lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" 240 | grep --quiet "FOUND"
  if [ $? -eq 0 ];then
   echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE ****"
   clean_tmp_files
   exit 1
  fi
 fi
 ### Apply the BSC bright stars exclusion list
 EXCLUSION_LIST_FILE="exclusion_list_bsc.txt"
 if [ -s "$EXCLUSION_LIST_FILE" ];then
  lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" 130 | grep --quiet "FOUND"
  if [ $? -eq 0 ];then
   echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE ****"
   clean_tmp_files
   exit 1
  fi
 fi
 ### Apply the Tycho-2 bright stars exclusion list
 EXCLUSION_LIST_FILE="exclusion_list_tycho2.txt"
 if [ -s "$EXCLUSION_LIST_FILE" ];then
  lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" 20 | grep --quiet "FOUND"
  if [ $? -eq 0 ];then
   echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE ****"
   clean_tmp_files
   exit 1
  fi
 fi 
 # It may be generated from the local
 EXCLUSION_LIST_FILE="exclusion_list_local.txt"
 if [ -s "$EXCLUSION_LIST_FILE" ];then
  lib/put_two_sources_in_one_field "$RA_MEAN_HMS" "$DEC_MEAN_HMS" "$EXCLUSION_LIST_FILE" $MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC | grep --quiet "FOUND"
  if [ $? -eq 0 ];then
   echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE ****"
   clean_tmp_files
   exit 1
  fi
 fi
 ############
 # do this only if $VIZIER_SITE is set
 if [ -n "$VIZIER_SITE" ];then
  # if this is a new source
  NUBER_OF_LIGHTCURVE_POINTS=$(cat "$LIGHTCURVEFILE" | wc -l)
  # Assume that two-reference-images detections are good match, check only new sources and one-reference-images detections to speed things up
  # If it's a flare with only one reference-image detection - check Gaia anyway as the first detection migth be a mismatch
  if [ $NUBER_OF_LIGHTCURVE_POINTS -eq 2 ] || [ $NUBER_OF_LIGHTCURVE_POINTS -eq 3 ] ;then
   # New last-ditch effort, search Gaia DR2 for a known star of approximately the same brightenss
   if [ -z "$GAIA_BAND_FOR_CATALOGED_SOURCE_CHECK" ];then
    GAIA_BAND_FOR_CATALOGED_SOURCE_CHECK="Gmag"
   fi
   ### ===> MAGNITUDE LIMITS HARDCODED HERE <===
   MAG_BRIGHT_SEARCH_LIMIT=0.0
   # V1858 Sgr from NMW_Sgr9_crash_test is the borderline case
   MAG_FAINT_SEARCH_LIMIT=$(echo "$MAG_MEAN" | awk '{printf "%.2f", $1+0.98}')
   RA_MEAN_HMS_DEC_MEAN_HMS_ONSESTRING="$RA_MEAN_HMS $DEC_MEAN_HMS"
   # Special treatment for blends and individual Gaia DR2 source matches
   # 2pix blend rejection works well. Let's try 2.5 pix
   BLEND_SEARCH_RADIUS_ARCSEC=$(echo "$MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC" | awk '{printf "%.2f", $1*2.5}')
   VIZIER_COMMAND=("lib/vizquery"
                "-site=$VIZIER_SITE"
                "-mime=text"
                "-source=I/345/gaia2"
                "-out.max=3"
                "-out.add=_r"
                "-out.form=mini"
                "-sort=$GAIA_BAND_FOR_CATALOGED_SOURCE_CHECK"
                "$GAIA_BAND_FOR_CATALOGED_SOURCE_CHECK=$MAG_BRIGHT_SEARCH_LIMIT..$MAG_FAINT_SEARCH_LIMIT"
                "-c=$RA_MEAN_HMS_DEC_MEAN_HMS_ONSESTRING"
                "-c.rs=$BLEND_SEARCH_RADIUS_ARCSEC"
                "-out=Source,RA_ICRS,DE_ICRS,Gmag,RPmag,Var")
   #VIZIER_GAIADR2_OUTPUT=$($TIMEOUTCOMMAND_GAIA_VIZIER "${VIZIER_COMMAND[@]}" 2>/dev/null | grep -vE "#|---|sec|Gma|RA_ICRS" | grep -E "NOT_AVAILABLE|CONSTANT|VARIABLE")
   # let's be paranoid about $VIZIER_GAIADR2_OUTPUT containing only source records and no garbage
   VIZIER_GAIADR2_OUTPUT=$($TIMEOUTCOMMAND_GAIA_VIZIER "${VIZIER_COMMAND[@]}" 2>/dev/null | grep -B10 '#END#' | grep -vE "#|---|sec|Gma|RA_ICRS" | grep -E "NOT_AVAILABLE|CONSTANT|VARIABLE" | awk 'NF > 5' | awk '{if (NF >= 3 && length($1) > 0 && ($1 + 0) == $1 && $1 >= 0 && length($3) > 0 && ($3 + 0) == $3 && $3 > 0 && $3 < 360) print}')
   if [ -n "$VIZIER_GAIADR2_OUTPUT" ];then
    # | awk 'NF > 0' is needed to exclude empty lines as echo "$VIZIER_GAIADR2_OUTPUT" will produce an empty line even when $VIZIER_GAIADR2_OUTPUT contains nothing
    # let's do echo -n as the second line of defense against the empty lines
    N_GAIA_STARS_WITIN_BLEND_SEARCH_RADIUS=$(echo -n "$VIZIER_GAIADR2_OUTPUT" | awk 'NF > 0' | wc -l)
    if [ $N_GAIA_STARS_WITIN_BLEND_SEARCH_RADIUS -eq 1 ];then
     # If there is only one star - check how far is it from the candidate position
     #DISTANCE_ARCSEC=$(echo "$VIZIER_GAIADR2_OUTPUT" | head -n1 | awk '{print $1}')
     # Try to be robust against $VIZIER_GAIADR2_OUTPUT containing garbage - set DISTANCE_ARCSEC to 999.99 is unsure
     DISTANCE_ARCSEC=$(echo "$VIZIER_GAIADR2_OUTPUT" | head -n1 | awk '{print (NF > 0 && length($1) > 0 && ($1 + 0) == $1 && $1 >= 0) ? $1 : "999.99"}')
     if awk -v max="$MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC" -v dist="$DISTANCE_ARCSEC" 'BEGIN {if (dist < max) exit 0; exit 1}' ;then
      # Using the [*] instead of [@] treats the entire array as a single string, using the first character of the Internal Field Separator (IFS) variable as a delimiter (which is a space by default).
      echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in Gaia DR2 single (TIMEOUTCOMMAND_GAIA_VIZIER=#$TIMEOUTCOMMAND_GAIA_VIZIER#, MAG_MEAN=$MAG_MEAN, MAG_FAINT_SEARCH_LIMIT=$MAG_FAINT_SEARCH_LIMIT, VIZIER_COMMAND=#${VIZIER_COMMAND[*]}#)VIZIER_GAIADR2_OUTPUT=#$VIZIER_GAIADR2_OUTPUT#N_GAIA_STARS_WITIN_BLEND_SEARCH_RADIUS=#$N_GAIA_STARS_WITIN_BLEND_SEARCH_RADIUS#DISTANCE_ARCSEC=#$DISTANCE_ARCSEC#MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC=#$MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC#"
      echo "$RA_MEAN_HMS $DEC_MEAN_HMS" >> exclusion_list_gaiadr2.txt__"$LIGHTCURVEFILE"
      clean_tmp_files
      exit 1
     fi
    elif [ $N_GAIA_STARS_WITIN_BLEND_SEARCH_RADIUS -ge 2 ];then
     # Using the [*] instead of [@] treats the entire array as a single string, using the first character of the Internal Field Separator (IFS) variable as a delimiter (which is a space by default).
     echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in Gaia DR2 blend (TIMEOUTCOMMAND_GAIA_VIZIER=#$TIMEOUTCOMMAND_GAIA_VIZIER#, MAG_MEAN=$MAG_MEAN, BLEND_MAG_FAINT_SEARCH_LIMIT=$BLEND_MAG_FAINT_SEARCH_LIMIT, VIZIER_COMMAND=#${VIZIER_COMMAND[*]}#)"
     echo "$RA_MEAN_HMS $DEC_MEAN_HMS" >> exclusion_list_gaiadr2.txt__"$LIGHTCURVEFILE"
     clean_tmp_files
     exit 1
    fi # if Gaia DR2 match found (single star or blend)
   fi # non-empty $VIZIER_GAIADR2_OUTPUT
   #
   # The trouble is... Gaia catalog is missing many obvious bright stars
   # So if the Gaia search didn't work well - let's try APASS (chosen because it has good magnitudes and is deep enough for NMW)
   # The awk 'NF > 0' command is equivalent to sed '/^[[:space:]]*$/d', but is generally faster and more efficient. It checks if the number of fields (NF) is greater than 0, which means the line is not empty.
   #NUMBER_OF_NONEMPTY_LINES=$($TIMEOUTCOMMAND_GAIA_VIZIER lib/vizquery -site="$VIZIER_SITE" -mime=text -source=II/336  -out.max=1 -out.add=_r -out.form=mini  -sort=Vmag Vmag=$MAG_BRIGHT_SEARCH_LIMIT..$MAG_FAINT_SEARCH_LIMIT  -c="$RA_MEAN_HMS $DEC_MEAN_HMS" -c.rs=$MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC  -out=RAJ2000,DEJ2000,Vmag 2>/dev/null | grep -B10 '#END#' | grep -vE "#|---|sec|Vma|RAJ" | awk 'NF > 3' | wc -l)
   NUMBER_OF_NONEMPTY_LINES=$($TIMEOUTCOMMAND_GAIA_VIZIER lib/vizquery -site="$VIZIER_SITE" -mime=text -source=II/336  -out.max=1 -out.add=_r -out.form=mini  -sort=Vmag Vmag=$MAG_BRIGHT_SEARCH_LIMIT..$MAG_FAINT_SEARCH_LIMIT  -c="$RA_MEAN_HMS $DEC_MEAN_HMS" -c.rs=$MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC  -out=RAJ2000,DEJ2000,Vmag 2>/dev/null | grep -B10 '#END#' | grep -vE "#|---|sec|Vma|RAJ" | awk 'NF > 3' | awk '{if (NF >= 2 && length($1) > 0 && ($1 + 0) == $1 && $1 >= 0 && length($2) > 0 && ($2 + 0) == $2 && $2 >= 0 && $2 < 360) print}' | wc -l)
   if [ $NUMBER_OF_NONEMPTY_LINES -gt 0 ];then
    echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in APASS   (TIMEOUTCOMMAND_GAIA_VIZIER=#$TIMEOUTCOMMAND_GAIA_VIZIER#, MAG_MEAN=$MAG_MEAN, MAG_FAINT_SEARCH_LIMIT=$MAG_FAINT_SEARCH_LIMIT)"
    #echo "$RA_MEAN_HMS $DEC_MEAN_HMS" >> exclusion_list_apass.txt
    echo "$RA_MEAN_HMS $DEC_MEAN_HMS" >> exclusion_list_apass.txt__"$LIGHTCURVEFILE"
    clean_tmp_files
    exit 1
   fi # if APASS match found  
  fi # if this is a new source
 fi # if $VIZIER_SITE is set
 ############
fi # if [ SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT -eq 0 ];then

### Print it only if the source passes the final check in order not to confuse the test script
#     Reference image    2010 12 10.0833  2455540.5834  13.61  06:29:12.25 +26:24:19.4
echo "<pre class='folding-pre'>
Mean magnitude and position on the discovery images: 
                   $YEAR_MEAN $MONTH_MEAN $DAYFRAC_MEAN_SHORT  $JD_MEAN_SHORT  $MAG_MEAN  $RADEC_MEAN_HMS"



# Additional info
# Galactic coordinates of the transient
GALACTIC_COORDINATES=$(lib/bin/skycoor -g $RADEC_MEAN_HMS J2000)

# Constellation where the transient is located
CONSTELLATION=$(util/constellation.sh $RADEC_MEAN_HMS)

echo "$GALACTIC_COORDINATES  $CONSTELLATION  Second-epoch detections are separated by $ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_STRING\" and $PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING pix   $STAR_IN_NEVEREXCLUDE_LIST_MESSAGE"

# Check if this is a known source or if it looks like a hot pixel
TEMP_FILE__SDWC_OUTPUT=$(mktemp 2>/dev/null || echo "tempilefallback_SDWC_OUTPUT_$$.tmp")
{
 lib/catalogs/check_catalogs_offline $RA_MEAN $DEC_MEAN H > "$TEMP_FILE__SDWC_OUTPUT"
 echo $? > "${TEMP_FILE__SDWC_OUTPUT}_exit_status.tmp"
} &
TEMP_FILE__MPCheck_OUTPUT=$(mktemp 2>/dev/null || echo "tempilefallback_MPCheck_OUTPUT_$$.tmp")
{
 util/transients/MPCheck_v2.sh $RADEC_MEAN_HMS $YEAR_MEAN $MONTH_MEAN $DAYFRAC_MEAN H $MAG_MEAN test.mpc__"$LIGHTCURVEFILE" > "$TEMP_FILE__MPCheck_OUTPUT"
 echo $? > "${TEMP_FILE__MPCheck_OUTPUT}_exit_status.tmp"
} &
wait
VARIABLE_STAR_ID=$(cat "${TEMP_FILE__SDWC_OUTPUT}_exit_status.tmp")
ASTEROID_ID=$(cat "${TEMP_FILE__MPCheck_OUTPUT}_exit_status.tmp")
cat "$TEMP_FILE__SDWC_OUTPUT"
cat "$TEMP_FILE__MPCheck_OUTPUT"
rm -f "$TEMP_FILE__SDWC_OUTPUT" "$TEMP_FILE__MPCheck_OUTPUT" "${TEMP_FILE__SDWC_OUTPUT}_exit_status.tmp" "${TEMP_FILE__MPCheck_OUTPUT}_exit_status.tmp"
if [ -z "$VARIABLE_STAR_ID" ] || [ -z "$ASTEROID_ID" ] ;then
 echo "ERROR in $0  VARIABLE_STAR_ID or ASTEROID_ID are not set"
 clean_tmp_files
 exit 1
fi
# If the candidate transient is not a known variable star or asteroid and doesn't seem to be a hot pixel - try online search
if [ $VARIABLE_STAR_ID -ne 0 ] && [ $ASTEROID_ID -ne 0 ] && [ -z "$THIS_IS_ARTIFICIAL_STAR_TEST_DO_NO_ONLINE_VSX_SEARCH" ] ;then
 if [[ "$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS" != "0.0" ]] &&
    [[ "$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS" != "0.1" ]] &&
    [[ "$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS" != "0.2" ]] ||
    ( [[ ! -z "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" ]] &&
      [[ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" == "no" ]] ); then
  # Slow online ID
  # Instead of a guess, use the actual field of view - the reference image is supposed to be solved by now
  WCS_REFERENCE_IMAGE_NAME=wcs_$(basename $REFERENCE_IMAGE)
  WCS_REFERENCE_IMAGE_NAME=${WCS_REFERENCE_IMAGE_NAME/wcs_wcs_/wcs_}
  #util/search_databases_with_vizquery.sh $RADEC_MEAN_HMS online_id $(util/fov_of_wcs_calibrated_image.sh $WCS_REFERENCE_IMAGE_NAME | grep 'Image size:' | awk -F"[ 'x]" '{if ($3 > $4) print $3; else print $4}') 2>&1 | grep '|' | tail -n1
  # Disable online VSX search
  util/search_databases_with_vizquery.sh $RADEC_MEAN_HMS online_id $(util/fov_of_wcs_calibrated_image.sh $WCS_REFERENCE_IMAGE_NAME | grep 'Image size:' | awk -F"[ 'x]" '{if ($3 > $4) print $3; else print $4}') no_online_vsx 2>&1 | grep '|' | tail -n1
  #
 fi
fi

# Is the Online MPChecker search radius is not set - use the default one
if [ -z "$ONLINE_MPCHECKER_BUTTON_ASTEROID_SEARCH_RADIUS_ARCMIN" ];then
 ONLINE_MPCHECKER_BUTTON_ASTEROID_SEARCH_RADIUS_ARCMIN=20
fi

# Determine limiting magnitude for manual asteroid search
ASTEROID_SEARCH_MAG_LIMIT=16
if [ -n "$FILTER_FAINT_MAG_CUTOFF_TRANSIENT_SEARCH" ];then
 ASTEROID_SEARCH_MAG_LIMIT=$(echo "$FILTER_FAINT_MAG_CUTOFF_TRANSIENT_SEARCH" | awk '{printf "%.1f", 2.5+$1}')
fi


echo -n "<a href=\"https://wis-tns.weizmann.ac.il/search?ra=${RA_MEAN_HMS//:/%3A}&decl=${DEC_MEAN_HMS//:/%3A}&radius=15&coords_unit=arcsec\" target=\"_blank\">Check this position in <font color=\"DarkSalmon\">TNS</font>.</a>                         <a href='http://www.astronomy.ohio-state.edu/asassn/transients.html' target='_blank'>Manually check the ASAS-SN list of transients!</a>
<a href=\"http://simbad.u-strasbg.fr/simbad/sim-coo?Coord=$RA_MEAN%20$DEC_MEAN&CooDefinedFrames=J2000&Radius=1.0&Radius.unit=arcmin\" target=\"_blank\">Search this object in <font color=\"maroon\">SIMBAD</font>.</a>
<a href=\"http://vizier.u-strasbg.fr/viz-bin/VizieR?-source=&-out.add=_r&-out.add=_RAJ%2C_DEJ&-sort=_r&-to=&-out.max=20&-meta.ucd=2&-meta.foot=1&-c=$RA_MEAN+$DEC_MEAN&-c.rs=$MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC\" target=\"_blank\">Search this object in <font color=\"FF9900\">VizieR</font> catalogs.</a>  <a href=\"http://irsa.ipac.caltech.edu/applications/wise/#id=Hydra_wise_wise_1&RequestClass=ServerRequest&DoSearch=true&schema=allsky-4band&intersect=CENTER&subsize=0.16666666800000002&mcenter=mcen&band=1,2,3,4&dpLevel=3a&UserTargetWorldPt=$RA_MEAN;$DEC_MEAN;EQ_J2000&SimpleTargetPanel.field.resolvedBy=nedthensimbad&preliminary_data=no&coaddId=&projectId=wise&searchName=wise_1&shortDesc=Position&isBookmarkAble=true&isDrillDownRoot=true&isSearchResult=true\" target=\"_blank\"><font color=\"green\">WISE</font> atlas</a>  <a href=\"https://aladin.u-strasbg.fr/AladinLite/?target=$RA_MEAN+$DEC_MEAN\" target='_blank'>Aladin Lite</a>"
# Dispaly SNAD ZTF link only if there is a hope to have ZTF data for this declination
TEST=$(echo "$DEC_MEAN > -30" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
 echo -n "  <a href=\"https://ztf.snad.space/dr17/search/$RA_MEAN%20$DEC_MEAN/4\" target='_blank'>SNAD ZTF viewer</a>"
fi
#
echo -n "
Online MPChecker may fail to identify bright comets! Please manually check the <a href='http://aerith.net/comet/weekly/current.html' target='_blank'>Seiichi Yoshida's</a> and <a href='http://astro.vanbuitenen.nl/comets' target='_blank'>Gideon van Buitenen's</a> pages.
</pre>
<form style='display: inline;' NAME='$$FORMMPC$1' METHOD=POST TARGET='_blank' ACTION='https://minorplanetcenter.net/cgi-bin/mpcheck.cgi'>
<input type=submit value=' Online MPChecker '>
<input type='hidden' name='year' maxlength=4 size=4 value='$YEAR_MEAN'>
<input type='hidden' name='month' maxlength=2 size=2 value='$MONTH_MEAN'>
<input type='hidden' name='day' maxlength=5 size=5 value='$DAYFRAC_MEAN_SUPERSHORT'>
<input type='radio' name='which' VALUE='pos' CHECKED style='display:none;'>
<input type='hidden' name='ra' value='$RA_MEAN_SPACES' maxlength=12 size=12>
<input type='hidden' name='decl' value='$DEC_MEAN_SPACES' maxlength=12 size=12>
<input type='radio' name='which' VALUE='obs' style='display:none;'>
<textarea name='TextArea' cols=81 rows=10 style='display:none;'></textarea>
<input type='hidden' name='radius' maxlength=3 size=3 VALUE='$ONLINE_MPCHECKER_BUTTON_ASTEROID_SEARCH_RADIUS_ARCMIN'>
<input type='hidden' name='limit' maxlength=4 size=4 VALUE='$ASTEROID_SEARCH_MAG_LIMIT'>
<input type='hidden' name='oc' maxlength=3 size=3 VALUE='500'>
<input type='radio' name='sort' VALUE='d' CHECKED style='display:none;'>
<input type='radio' name='sort' VALUE='r' style='display:none;'>
<input type='radio' name='mot' VALUE='m' style='display:none;'>
<input type='radio' name='mot' VALUE='h' CHECKED style='display:none;'>
<input type='radio' name='mot' value='d' style='display:none;'>
<input type='radio' name='tmot' VALUE='t' style='display:none;'>
<input type='radio' name='tmot' VALUE='s' CHECKED style='display:none;'>
<input type='radio' name='pdes' VALUE='u' CHECKED style='display:none;'>
<input type='radio' name='pdes' VALUE='p' style='display:none;'>
<input type='radio' name='needed' VALUE='f' CHECKED style='display:none;'>
<input type='radio' name='needed' VALUE='t' style='display:none;'>
<input type='radio' name='needed' VALUE='n' style='display:none;'>
<input type='radio' name='needed' VALUE='u' style='display:none;'>
<input type='radio' name='needed' VALUE='N' style='display:none;'>
<input type='hidden' name='ps' VALUE='n'>
<input type='radio' name='type' VALUE='p' CHECKED style='display:none;'>
<input type='radio' name='type' VALUE='m' style='display:none;'>
</form>
<form style='display: inline;' NAME='$$FORMVSX$1' method='post' TARGET='_blank' action='https://vsx.aavso.org/index.php?view=results.submit1' enctype='application/x-www-form-urlencoded'>
<input type='hidden' name='ql' value='1'>
<input type='hidden' name='getCoordinates' value='0'>
<input type='hidden' name='plotType' value='Search'>
<input type='hidden' name='special' value='index.php?view=results.special&sid=2'>
<input type='hidden' name='ident' value=''>
<input type='hidden' name='constid' value='0'>
<input type='hidden' name='targetcenter' value='$RADEC_MEAN_HMS'>
<input type='hidden' name='format' value='s'>
<input type='hidden' name='fieldsize' value='60'>
<input type='hidden' name='fieldunit' value='3'>
<input type='hidden' name='geometry' value='r'>
<input type='hidden' name='filter[]' value='0'>
<input type='hidden' name='filter[]' value='1'>
<input type='hidden' name='filter[]' value='2'>
<input type='hidden' name='filter[]' value='3'>
<input type='hidden' name='order' value='9'>
<input class='formbutton' type='Submit' value='Search VSX online'>
</form>
<form style='display: inline;' NAME=\"$$FORMCATALINA$1\" method=\"post\" TARGET=\"_blank\" action=\"http://nunuku.caltech.edu/cgi-bin/getcssconedb_release_img.cgi\" enctype=\"multipart/form-data\">
<input type=\"hidden\" name=\"RA\"  size=\"12\" maxlength=\"20\" value=\"$RA_MEAN\" /><input type=\"hidden\" name=\"Dec\"  size=\"12\" maxlength=\"20\" value=\"$DEC_MEAN\" />
<input type=\"hidden\" name=\"Rad\"  size=\"5\" maxlength=\"10\" value=\"0.1\" />
<input type=\"hidden\" name=\"IMG\" value=\"dss\" />
<input type=\"hidden\" name=\"IMG\" value=\"nun\" checked=\"checked\" />
<input type=\"hidden\" name=\"IMG\" value=\"sdss\" />
<input type=\"hidden\" name=\"DB\" value=\"photcat\" checked=\"checked\" />
<input type=\"hidden\" name=\"DB\" value=\"orphancat\" />
<input type=\"submit\" name=\".submit\" value=\"Catalina photometry\" />
<input type=\"hidden\" name=\"OUT\" value=\"web\" />
<input type=\"hidden\" name=\"OUT\" value=\"csv\" checked=\"checked\" />
<input type=\"hidden\" name=\"OUT\" value=\"vot\" />
<input type=\"hidden\" name=\"SHORT\" value=\"short\" checked=\"checked\" />
<input type=\"hidden\" name=\"SHORT\" value=\"long\" />
<input type=\"hidden\" name=\"PLOT\" value=\"plot\" checked=\"checked\" />
</form>
<form style='display: inline;' NAME=\"$$FORMNMW$1\" method=\"get\" TARGET=\"_blank\" action=\"http://scan.sai.msu.ru/cgi-bin/nmw/sky_archive\" enctype=\"application/x-www-form-urlencoded\">
<input id=\"h2\" name=\"ra\" type=\"hidden\" required value=\"$RA_MEAN_HMS\">
<input id=\"h3\" name=\"dec\" type=\"hidden\" required value=\"$DEC_MEAN_HMS\"> 
<input id=\"h4\" name=\"r\" type=\"hidden\" required value=\"32\"> 
<input id=\"h5\" name=\"n\" type=\"hidden\" required value=\"0\">
<input type=\"submit\" value='NMW images'>
</form>
"

# Show the ASAS-3 button only for sources with declination below +28 
TEST=$(echo "$DEC_MEAN<28" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
re='^[0-9]+$'
if ! [[ $TEST =~ $re ]] ; then
 echo "TEST ERROR in $DEC_MEAN<28" 
 clean_tmp_files
 exit 1
else
 if [ $TEST -eq 1 ];then
  echo -n "<form style='display: inline;' action='https://www.astrouw.edu.pl/cgi-asas/asas_cat_input' method='post' target='_blank'><input type='hidden' name='source' value='asas3'><input type='hidden' name='coo' value='$RADEC_MEAN_HMS'><input type='hidden' name='equinox' value='2000'><input type='hidden' name='nmin' value='4'><input type='hidden' name='box' value='15'><input type='submit' name='submit' value='ASAS-3 lightcurve'></form>"
 fi
fi

echo "<br>"

# no local exclusions speed-up for the tests
if [ $SKIP_ALL_EXCLUSION_LISTS_FOR_THIS_TRANSIENT -eq 0 ] && [ -z "$THIS_IS_VAST_TEST" ];then
 # Write this transient to local exclusion list
 #echo "$RADEC_MEAN_HMS" >> exclusion_list_local.txt
 echo "$RADEC_MEAN_HMS" >> exclusion_list_local.txt__"$LIGHTCURVEFILE"
fi

# just in case
clean_tmp_files

exit 0
# everything is fine!
