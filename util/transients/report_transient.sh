#!/usr/bin/env bash
#
# This script writes out a short summary about the possible transient
#
# Parse the command line arguments
if [ -z $1 ]; then
 echo "Usage: $0 outNUMBER.dat"
fi
LIGHTCURVEFILE=$1

#. util/transients/transient_factory_setup.sh

# Find SExtractor
SEXTRACTOR=`command -v sex 2>/dev/null`
if [ "" = "$SEXTRACTOR" ];then
 SEXTRACTOR=lib/bin/sex
fi

######### function to clean-up the temporary files before exiting #########
function clean_tmp_files {
 for TMP_FILE_TO_REMOVE in ra$$.dat dec$$.dat mag$$.dat script$$.dat dayfrac$$.dat jd$$.dat x$$.dat y$$.dat ;do
  if [ -f "$TMP_FILE_TO_REMOVE" ];then
   #
   #echo "DEBUG:  REMOVING  $TMP_FILE_TO_REMOVE" >> /dev/stderr
   #
   rm -f "$TMP_FILE_TO_REMOVE"
  fi
 done
 return 0
}


# TRAP!! If we whant to identify a flare, there will be no sence to search for an asteroid on the reference image.
# Use the first discovery image instead!
REFERENCE_IMAGE=`cat vast_summary.log |grep "Ref.  image:" | awk '{print $6}'`

# Assume that the second first-epoch image is always supplied as the second image on the command line
SECOND_REFERENCE_IMAGE=`cat vast_image_details.log | head -n2 | tail -n1 | awk '{print $17}'`

#     Reference image    2010 12 10.0833  2455540.5834  13.61  06:29:12.25 +26:24:19.4
echo "<table style='font-family:monospace;font-size:12px;'>
<tr><th></th><th>                     Date (UTC)   </th><th>    JD(UTC)  </th><th>    mag. </th><th> R.A. & Dec.(J2000)   </th><th>X & Y (pix)</th><th>    Image</th></tr>"
N=0

# Make sure there are no files with names we want to use
clean_tmp_files

while read JD MAG MERR X Y APP FITSFILE REST ;do
 #util/wcs_image_calibration.sh $FITSFILE $FOV &>/dev/null
 # At this point, we should somehow have a WCS calibrated image named $WCS_IMAGE_NAME
 WCS_IMAGE_NAME=wcs_`basename $FITSFILE`
 if [ ! -f $WCS_IMAGE_NAME ];then
  echo "ERROR: cannot find plate-solved image $WCS_IMAGE_NAME" 
  clean_tmp_files
  exit 1
 fi
 SEXTRACTOR_CATALOG_NAME="$WCS_IMAGE_NAME".cat
 UCAC5_SOLUTION_NAME="$WCS_IMAGE_NAME".cat.ucac5
 # We believe this should be done before calling this script
 #if [ ! -f $SEXTRACTOR_CATALOG_NAME ];then  
 # $SEXTRACTOR -c `grep "SExtractor parameter file:" vast_summary.log |awk '{print $4}'` -PARAMETERS_NAME wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME $WCS_IMAGE_NAME
 #fi # if [ ! -f $SEXTRACTOR_CATALOG_NAME ];then
 # Keeping this step for backward compatibility with the old scripts used in the tests
 #if [ ! -f $UCAC5_SOLUTION_NAME ];then
 # util/solve_plate_with_UCAC5 $FITSFILE >> /dev/stderr
 #fi
 DATETIMEJD=`grep $FITSFILE vast_image_details.log |awk '{print $2" "$3"  "$5"  "$7}'`
 DATE=`echo $DATETIMEJD|awk '{print $1}'`
 TIME=`echo $DATETIMEJD|awk '{print $2}'`
 EXPTIME=`echo $DATETIMEJD|awk '{print $3}'`
 JD=`echo $DATETIMEJD|awk '{print $4}'`
 DAY=`echo $DATE |awk -F"." '{print $1}'`
 MONTH=`echo $DATE |awk -F"." '{print $2}'`
 YEAR=`echo $DATE |awk -F"." '{print $3}'` 
 TIMEH=`echo $TIME |awk -F":" '{print $1}'`
 TIMEM=`echo $TIME |awk -F":" '{print $2}'`
 TIMES=`echo $TIME |awk -F":" '{print $3}'`
 #DAYFRAC=`echo "$DAY+$TIMEH/24+$TIMEM/1440+$TIMES/86400+$EXPTIME/(2*86400)" |bc -ql`
 DAYFRAC=`echo "$DAY $TIMEH $TIMEM $TIMES $EXPTIME" | awk '{printf "%.6f",$1+$2/24+$3/1440+$4/86400+$5/(2*86400)}'`
 # If there is a UCAC5 plate solution with local corrections - use it,
 # otherwise rely on the positions computed using only the WCS header
 if [ -f $UCAC5_SOLUTION_NAME ];then
  # this is used by util/transients/transient_factory_test31.sh
  RADEC=`lib/find_star_in_wcs_catalog $X $Y < $UCAC5_SOLUTION_NAME`
  if [ $? -ne 0 ];then
   echo "(1) error in $0 filed to run  lib/find_star_in_wcs_catalog $X $Y < $UCAC5_SOLUTION_NAME"
   clean_tmp_files
   exit 1
  fi
 elif [ -f $SEXTRACTOR_CATALOG_NAME ];then
  # this is used by util/transients/report_transient.sh
  RADEC=`lib/find_star_in_wcs_catalog $X $Y < $SEXTRACTOR_CATALOG_NAME`
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
 RA=`echo $RADEC | awk '{print $1}'`
 DEC=`echo $RADEC | awk '{print $2}'`
 MAG=`echo $MAG|awk '{printf "%.2f",$1}'`

 # Do not use the first-epoch images for computing average values (positions, dates, magnitdes)
 if [ "$FITSFILE" != "$REFERENCE_IMAGE" ] && [ "$FITSFILE" != "$SECOND_REFERENCE_IMAGE" ] ;then
  echo "$JD" >> jd$$.dat
  echo "$DAYFRAC" >> dayfrac$$.dat
  echo "$RA" >> ra$$.dat
  echo "$DEC" >> dec$$.dat
  echo "$MAG" >> mag$$.dat
  #
  echo "$X" >> x$$.dat
  echo "$Y" >> y$$.dat
  #
 fi
 
 if [ "$FITSFILE" != "$REFERENCE_IMAGE" ] ;then
  #N=`echo $N+1|bc -q`
  N=$[$N+1]
  echo -n "<tr><td>Discovery image $N   &nbsp;&nbsp;</td>"
 else
  echo -n "<tr><td>Reference image     &nbsp;&nbsp;</td>"
 fi # if [ "$FITSFILE" != "$REFERENCE_IMAGE" ] ;then
 DAYFRAC=`echo $DAYFRAC |awk '{printf "%07.4f\n",$1}'` # purely for visualisation purposes
 JD=`echo $JD|awk '{printf "%.4f",$1}'` # purely for visualisation purposes
 X=`echo "$X" |awk '{printf "%04.0f",$1}'` # purely for visualisation purposes
 Y=`echo "$Y" |awk '{printf "%04.0f",$1}'` # purely for visualisation purposes
 echo "<td>$YEAR $MONTH $DAYFRAC &nbsp;&nbsp;</td><td> $JD &nbsp;&nbsp;</td><td> $MAG &nbsp;&nbsp;</td><td>" `lib/deg2hms $RADEC` "&nbsp;&nbsp;</td><td>$X $Y &nbsp;&nbsp;</td><td>$FITSFILE</td></tr>"
done < $LIGHTCURVEFILE
echo "</table>"

#lib/stat_array < ra$$.dat > script$$.dat
# We need to reformat util/colstat output to make it look like a small shell script
util/colstat < ra$$.dat 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script$$.dat
# AAAA ###################
#cp script$$.dat /tmp/
###################
if [ $? -ne 0 ];then
 echo "ERROR0001 in $0" 
 clean_tmp_files
 exit 1
fi
. script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0002 in $0" 
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

#lib/stat_array < dec$$.dat > script$$.dat
util/colstat < dec$$.dat 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0003 in $0" 
 clean_tmp_files
 exit 1
fi
. script$$.dat
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

#lib/stat_array < mag$$.dat > script$$.dat
util/colstat < mag$$.dat 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0005 in $0" 
 clean_tmp_files
 exit 1
fi
. script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0006 in $0" 
 clean_tmp_files
 exit 1
fi
MAG_MEAN=`echo $MEAN|awk '{printf "%.2f",$1}'`
MAG_MEAN=${MAG_MEAN//"+"/}

#lib/stat_array < dayfrac$$.dat > script$$.dat
util/colstat < dayfrac$$.dat 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0007 in $0" 
 clean_tmp_files
 exit 1
fi
. script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0008 in $0" 
 clean_tmp_files
 exit 1
fi
DAYFRAC_MEAN=`echo $MEAN|awk '{printf "%07.4f",$1}'`
DAYFRAC_MEAN_SHORT=`echo $MEAN|awk '{printf "%05.2f",$1}'`


#lib/stat_array < jd$$.dat > script$$.dat
util/colstat < jd$$.dat 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0009 in $0" 
 clean_tmp_files
 exit 1
fi
##########################
# debug
#cp script$$.dat /tmp/script_test.tmp
#cp jd$$.dat /tmp/jd_test.tmp
##########################
. script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0010 in $0" 
 clean_tmp_files
 exit 1
fi
JD_MEAN=`echo $MEAN |awk '{printf "%.4f",$1}'`

#### Test for float numbers ####
for STRING_TO_TEST in "$RA_MEAN" "$RA_MAX" "$RA_MIN" "$DEC_MEAN" "$DEC_MAX" "$DEC_MIN" "$MAG_MEAN" "$DAYFRAC_MEAN" "$DAYFRAC_MEAN_SHORT" "$JD_MEAN" ;do
 re='^[+-]?[0-9]+([.][0-9]+)?$'
 if ! [[ $STRING_TO_TEST =~ $re ]] ; then
  echo "ERROR in $0 : the string #$STRING_TO_TEST# is not a floating point number" 
  clean_tmp_files
  exit 1
 fi
done
################################
RA_SECOND_EPOCH_1=`cat ra$$.dat | head -n1`
DEC_SECOND_EPOCH_1=`cat dec$$.dat | head -n1`
RA_SECOND_EPOCH_2=`cat ra$$.dat | tail -n1`
DEC_SECOND_EPOCH_2=`cat dec$$.dat | tail -n1`

ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING=`lib/put_two_sources_in_one_field "$RA_SECOND_EPOCH_1" "$DEC_SECOND_EPOCH_1"  "$RA_SECOND_EPOCH_2" "$DEC_SECOND_EPOCH_2" 2>&1 | grep 'Angular distance'`
ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING="${ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING/Angular/angular}"
ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING="${ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING/degrees/deg}"
ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC=`echo "$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING" | awk '{printf "%.1f", $5*3600}'`
ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_STRING="$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC"
# Reject candidates with large distance between the two second-epoch detections
### ==> Assumptio about positional accuracy hardcoded here <===
#TEST=`echo "$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC > 11" | bc -ql`
TEST=`echo "$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC>11" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
if [ $TEST -eq 1 ];then
 echo "Rejecting candidate due to large distance ($ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC\") between the two second-epoch detections"
 clean_tmp_files
 exit 1
fi
# Highlight candidates with suspiciously large distance between the two second-epoch detections
### ==> Assumptio about positional accuracy hardcoded here <===
#TEST=`echo "$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC > 8.4" | bc -ql`
TEST=`echo "$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC>8.4" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
if [ $TEST -eq 1 ];then
 ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_STRING="<b><font color=\"red\">$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC</font></b>"
else
 ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_STRING="<font color=\"green\">$ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC</font>"
fi

PIX_X_SECOND_EPOCH_1=`cat x$$.dat | head -n1`
PIX_Y_SECOND_EPOCH_1=`cat y$$.dat | head -n1`
PIX_X_SECOND_EPOCH_2=`cat x$$.dat | tail -n1`
PIX_Y_SECOND_EPOCH_2=`cat y$$.dat | tail -n1`
PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS=`echo "$PIX_X_SECOND_EPOCH_1 $PIX_X_SECOND_EPOCH_2 $PIX_Y_SECOND_EPOCH_1 $PIX_Y_SECOND_EPOCH_2" | awk '{printf "%.1f", sqrt( ($1-$2)*($1-$2) + ($3-$4)*($3-$4) )}'`
PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING="$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS"
### ==> Assumptio about shift between secon-spoch images hardcoded here <===
if [ "$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS" = "0.0" ];then
 PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING="<b><font color=\"red\">$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS</font></b>"
else
 PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING="<font color=\"green\">$PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS</font>"
fi

# Remove temporary files in case the script will exit after the final check
clean_tmp_files
#for TMP_FILE_TO_REMOVE in ra$$.dat dec$$.dat mag$$.dat script$$.dat dayfrac$$.dat jd$$.dat x$$.dat y$$.dat ;do
# if [ -f "$TMP_FILE_TO_REMOVE" ];then
#  rm -f "$TMP_FILE_TO_REMOVE"
# fi
#done


RADEC_MEAN_HMS=`lib/deg2hms $RA_MEAN $DEC_MEAN`
RADEC_MEAN_HMS=${RADEC_MEAN_HMS//'\n'/}
RA_MEAN_HMS=`echo "$RADEC_MEAN_HMS" | awk '{print $1}'`
DEC_MEAN_HMS=`echo "$RADEC_MEAN_HMS" | awk '{print $2}'`
#RA_MEAN_SPACES=`lib/deg2hms $RA_MEAN $DEC_MEAN | awk '{print $1}'`
RA_MEAN_SPACES=${RA_MEAN_HMS//":"/" "}
#DEC_MEAN_SPACES=`lib/deg2hms $RA_MEAN $DEC_MEAN | awk '{print $2}'`
DEC_MEAN_SPACES=${DEC_MEAN_HMS//":"/" "}

#echo "<pre style='font-family:monospace;font-size:12px;'>
#Mean magnitude and position on the discovery images: 
#                   $YEAR $MONTH $DAYFRAC_MEAN  $JD_MEAN  $MAG_MEAN " `lib/deg2hms $RA_MEAN $DEC_MEAN`
#     Reference image    2010 12 10.0833  2455540.5834  13.61  06:29:12.25 +26:24:19.4
echo "<pre style='font-family:monospace;font-size:12px;'>
Mean magnitude and position on the discovery images: 
                   $YEAR $MONTH $DAYFRAC_MEAN  $JD_MEAN  $MAG_MEAN  $RADEC_MEAN_HMS"


### FINAL CHECK: make sure the transient is not jumping in RA or DEC ###
#EXTREME_POSITION_1=`lib/deg2hms $RA_MAX $DEC_MAX`
#EXTREME_POSITION_2=`lib/deg2hms $RA_MIN $DEC_MIN`
#JUMP=`lib/put_two_sources_in_one_field $EXTREME_POSITION_1 $EXTREME_POSITION_2 |grep "Angular distance" | awk '{print $5}'`
#JUMP_ARCSEC=`echo "$JUMP*3600"|bc -ql`
#echo "Maximum position difference between discovery images is $JUMP degrees ($JUMP_ARCSEC arcsec)."
# CONSERVATIVE_ASTROMETRIC_ACCURACY_ARCSEC is not defined!!!
#TEST=`echo "$JUMP_ARCSEC>$CONSERVATIVE_ASTROMETRIC_ACCURACY_ARCSEC"|bc -ql`
#if [ $TEST -eq 1 ];then
# exit 1
#fi  
### end of FINAL CHECK ###

#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#

############
### Apply the exclusion list. It may be generated from the previous-day(s) report file(s) 
#
# We are not making a 'for' cycle here because we want different exclusion radii to be applied to different catalogs
EXCLUSION_LIST_FILE="exclusion_list.txt"
if [ -s "$EXCLUSION_LIST_FILE" ];then
 # Exclude previously considered candidates
 #echo "Checking $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE" 
 while read RA_EXLUSION_LIST DEC_EXLUSION_LIST REST_JUST_IN_CASE ;do
  lib/put_two_sources_in_one_field "$RA_EXLUSION_LIST" "$DEC_EXLUSION_LIST" "$RA_MEAN_HMS" "$DEC_MEAN_HMS" 2>/dev/null | grep 'Angular distance' | awk '{if ( $5 < 17/3600.0 ) print "FOUND" }' | grep "FOUND" && break
 done < "$EXCLUSION_LIST_FILE" | grep --quiet "FOUND"
 if [ $? -eq 0 ];then
  echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE ****"
  clean_tmp_files
  exit 1
 fi
fi 
### Apply the bright BSC bright stars exclusion list
EXCLUSION_LIST_FILE="exclusion_list_bbsc.txt"
if [ -s "$EXCLUSION_LIST_FILE" ];then
 # Exclude previously considered candidates
 #echo "Checking $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE" 
 while read RA_EXLUSION_LIST DEC_EXLUSION_LIST REST_JUST_IN_CASE ;do
  lib/put_two_sources_in_one_field "$RA_EXLUSION_LIST" "$DEC_EXLUSION_LIST" "$RA_MEAN_HMS" "$DEC_MEAN_HMS" 2>/dev/null | grep 'Angular distance' | awk '{if ( $5 < 240/3600.0 ) print "FOUND" }' | grep "FOUND" && break
 done < "$EXCLUSION_LIST_FILE" | grep --quiet "FOUND" 
 if [ $? -eq 0 ];then
  echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE ****"
  clean_tmp_files
  exit 1
 fi
fi
### Apply the BSC bright stars exclusion list
EXCLUSION_LIST_FILE="exclusion_list_bsc.txt"
if [ -s "$EXCLUSION_LIST_FILE" ];then
 # Exclude previously considered candidates
 #echo "Checking $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE" 
 while read RA_EXLUSION_LIST DEC_EXLUSION_LIST REST_JUST_IN_CASE ;do
  lib/put_two_sources_in_one_field "$RA_EXLUSION_LIST" "$DEC_EXLUSION_LIST" "$RA_MEAN_HMS" "$DEC_MEAN_HMS" 2>/dev/null | grep 'Angular distance' | awk '{if ( $5 < 130/3600.0 ) print "FOUND" }' | grep "FOUND" && break
 done < "$EXCLUSION_LIST_FILE" | grep --quiet "FOUND"
 if [ $? -eq 0 ];then
  echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE ****"
  clean_tmp_files
  exit 1
 fi
fi
### Apply the Tycho-2 bright stars exclusion list
EXCLUSION_LIST_FILE="exclusion_list_tycho2.txt"
if [ -s "$EXCLUSION_LIST_FILE" ];then
 # Exclude previously considered candidates
 #echo "Checking $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE" 
 while read RA_EXLUSION_LIST DEC_EXLUSION_LIST REST_JUST_IN_CASE ;do
  lib/put_two_sources_in_one_field "$RA_EXLUSION_LIST" "$DEC_EXLUSION_LIST" "$RA_MEAN_HMS" "$DEC_MEAN_HMS" 2>/dev/null | grep 'Angular distance' | awk '{if ( $5 < 20/3600.0 ) print "FOUND" }' | grep "FOUND" && break
 done < "$EXCLUSION_LIST_FILE" | grep --quiet "FOUND"
 if [ $? -eq 0 ];then
  echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE ****"
  clean_tmp_files
  exit 1
 fi
fi 
# It may be generated from the local
EXCLUSION_LIST_FILE="exclusion_list_local.txt"
if [ -s "$EXCLUSION_LIST_FILE" ];then
 # Exclude previously considered candidates
 #echo "Checking $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE" 
 while read RA_EXLUSION_LIST DEC_EXLUSION_LIST REST_JUST_IN_CASE ;do
  lib/put_two_sources_in_one_field "$RA_EXLUSION_LIST" "$DEC_EXLUSION_LIST" "$RA_MEAN_HMS" "$DEC_MEAN_HMS" 2>/dev/null | grep 'Angular distance' | awk '{if ( $5 < 17/3600.0 ) print "FOUND" }' | grep "FOUND" && break
 done < "$EXCLUSION_LIST_FILE" | grep --quiet "FOUND"
 if [ $? -eq 0 ];then
  echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in the exclusion list $EXCLUSION_LIST_FILE ****"
  clean_tmp_files
  exit 1
 fi
fi
############
# do this only if $VIZIER_SITE is set
if [ ! -z "$VIZIER_SITE" ];then
 # if this is a new source
 if [ `cat $LIGHTCURVEFILE | wc -l` -eq 2 ];then
  # New last-ditch effort, search Gaia DR2 for a known star of approximately the same brightenss
  ### ===> MAGNITUDE LIMITS HARDCODED HERE <===
  #MAG_BRIGHT_SEARCH_LIMIT=`echo "$MAG_MEAN" | awk '{printf "%.2f", $1-0.5}'`
  MAG_BRIGHT_SEARCH_LIMIT=0.0
  MAG_FAINT_SEARCH_LIMIT=`echo "$MAG_MEAN" | awk '{printf "%.2f", $1+1.00}'`
  # We assume $TIMEOUTCOMMAND is set by the parent script
  $TIMEOUTCOMMAND lib/vizquery -site="$VIZIER_SITE" -mime=text -source=I/345/gaia2  -out.max=1 -out.add=_r -out.form=mini  -sort=Gmag Gmag=$MAG_BRIGHT_SEARCH_LIMIT..$MAG_FAINT_SEARCH_LIMIT  -c="$RA_MEAN_HMS $DEC_MEAN_HMS" -c.rs=17  -out=Source,RA_ICRS,DE_ICRS,Gmag,Var 2>/dev/null | grep -v \# | grep -v "\-\-\-" |grep -v "sec" | grep -v 'Gma' | grep -v "RA_ICRS" | grep --quiet -e 'NOT_AVAILABLE' -e 'CONSTANT' -e 'VARIABLE'
  if [ $? -eq 0 ];then
   echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in Gaia DR2   (TIMEOUTCOMMAND=#$TIMEOUTCOMMAND#)"
   echo "$RA_MEAN_HMS $DEC_MEAN_HMS" >> exclusion_list_gaiadr2.txt
   clean_tmp_files
   exit 1
  fi # if Gaia DR2 match found
  # The trouble is... Gaia catalog is missing many obvious bright stars
  # So if the Gaia search didn't work well - let's try APASS (chosen because it has good magnitudes and is deep enough for NMW)
  NUMBER_OF_NONEMPTY_LINES=`$TIMEOUTCOMMAND lib/vizquery -site="$VIZIER_SITE" -mime=text -source=II/336  -out.max=1 -out.add=_r -out.form=mini  -sort=Vmag Vmag=$MAG_BRIGHT_SEARCH_LIMIT..$MAG_FAINT_SEARCH_LIMIT  -c="$RA_MEAN_HMS $DEC_MEAN_HMS" -c.rs=17  -out=recno,RAJ2000,DEJ2000,Vmag 2>/dev/null | grep -v \# | grep -v "\-\-\-" |grep -v "sec" | grep -v 'Vma' | grep -v "RAJ" | sed '/^[[:space:]]*$/d' | wc -l`
  if [ $NUMBER_OF_NONEMPTY_LINES -gt 0 ];then
   echo "**** FOUND  $RA_MEAN_HMS $DEC_MEAN_HMS in APASS   (TIMEOUTCOMMAND=#$TIMEOUTCOMMAND#)"
   echo "$RA_MEAN_HMS $DEC_MEAN_HMS" >> exclusion_list_apass.txt
   clean_tmp_files
   exit 1
  fi # if APASS match found  
 fi # if this is a new source
fi # if $VIZIER_SITE is set
############
# Additional info
# Galactic coordinates of the transient
GALACTIC_COORDINATES=`lib/bin/skycoor -g $RADEC_MEAN_HMS J2000`

echo "$GALACTIC_COORDINATES   Second-epoch detections are separated by $ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_STRING\" and $PIX_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_STRING pix"

# Check if this is a known source
lib/catalogs/check_catalogs_offline $RA_MEAN $DEC_MEAN
util/transients/MPCheck.sh $RADEC_MEAN_HMS $DATE $TIME H $MAG_MEAN | grep -v "Starting"

echo -n "<a href=\"https://wis-tns.weizmann.ac.il/search?ra=${RA_MEAN_HMS//:/%3A}&decl=${DEC_MEAN_HMS//:/%3A}&radius=15&coords_unit=arcsec\" target=\"_blank\">Check this position in <font color=\"tomato\">TNS</font>.</a>                         <a href='http://www.astronomy.ohio-state.edu/asassn/transients.html' target='_blank'>Manually check the ASAS-SN list of transients!</a>
<a href=\"http://simbad.u-strasbg.fr/simbad/sim-coo?Coord=$RA_MEAN%20$DEC_MEAN&CooDefinedFrames=J2000&Radius=1.0&Radius.unit=arcmin\" target=\"_blank\">Search this object in <font color=\"maroon\">SIMBAD</font>.</a>
<a href=\"http://vizier.u-strasbg.fr/viz-bin/VizieR?-source=&-out.add=_r&-out.add=_RAJ%2C_DEJ&-sort=_r&-to=&-out.max=20&-meta.ucd=2&-meta.foot=1&-c=$RA_MEAN+$DEC_MEAN&-c.rs=60\" target=\"_blank\">Search this object in <font color=\"FF9900\">VizieR</font> catalogs.</a>
<a href=\"http://skydot.lanl.gov/nsvs/cone_search.php?ra=$RA_MEAN&dec=$DEC_MEAN&rad=1&saturated=on&nocorr=on&lonpts=on&hiscat=on&hicorr=on&hisigcorr=on&radecflip=on\" target=\"_blank\">Search for previous observations of this object in the <font color=#006600>NSVS</font> database.</a>
<a href=\"http://irsa.ipac.caltech.edu/applications/wise/#id=Hydra_wise_wise_1&RequestClass=ServerRequest&DoSearch=true&schema=allsky-4band&intersect=CENTER&subsize=0.16666666800000002&mcenter=mcen&band=1,2,3,4&dpLevel=3a&UserTargetWorldPt=$RA_MEAN;$DEC_MEAN;EQ_J2000&SimpleTargetPanel.field.resolvedBy=nedthensimbad&preliminary_data=no&coaddId=&projectId=wise&searchName=wise_1&shortDesc=Position&isBookmarkAble=true&isDrillDownRoot=true&isSearchResult=true\" target=\"_blank\">Show this position in <font color=\"#FF0033\">WISE</font> atlas</a>
<a href=\"http://irsa.ipac.caltech.edu/cgi-bin/FinderChart/nph-finder?locstr=$RA_MEAN+$DEC_MEAN&markervis_shrunk=true\" target=\"_blank\"><font color=\"#339999\">2MASS</font>, <font color=\"#339999\">SDSS</font>, and <font color=\"#339999\">DSS</font> Finder Chart</a>
</pre>
<form style='display: inline;' NAME='$$FORMMPC$1' METHOD=POST TARGET='_blank' ACTION='https://minorplanetcenter.net/cgi-bin/mpcheck.cgi'>
<input type=submit value=' Online MPChecker '>
<input type='hidden' name='year' maxlength=4 size=4 value='$YEAR'>
<input type='hidden' name='month' maxlength=2 size=2 value='$MONTH'>
<input type='hidden' name='day' maxlength=5 size=5 value='$DAYFRAC_MEAN_SHORT'>
<input type='radio' name='which' VALUE='pos' CHECKED style='display:none;'>
<input type='hidden' name='ra' value='$RA_MEAN_SPACES' maxlength=12 size=12>
<input type='hidden' name='decl' value='$DEC_MEAN_SPACES' maxlength=12 size=12>
<input type='radio' name='which' VALUE='obs' style='display:none;'>
<textarea name='TextArea' cols=81 rows=10 style='display:none;'></textarea>
<input type='hidden' name='radius' maxlength=3 size=3 VALUE='15'>
<input type='hidden' name='limit' maxlength=4 size=4 VALUE='16.0'>
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
<form style='display: inline;' NAME='$$FORMVSX$1' method='post' TARGET='_blank' action='https://www.aavso.org/vsx/index.php?view=results.submit1' enctype='multipart/form-data'>
<input type='Hidden' name='ql' value='1'>
<input type='Hidden' name='getCoordinates' value='0'>
<input type='Hidden' name='plotType' value='Search'>
<select style='display:none;' class='formselect' style='width: 160px' name='special' size='1'>
<option value='index.php?view=results.special&sid=2'>Changes in last week...</option>
</select>
<input  type='hidden' class='forminput' type='Text' name='ident' style='width: 205px' value=''>
<select style='display:none;' class='formselect' name='constid' size='1'>
<option value='0' selected>--</option>
</select>
<input type='hidden' class='forminput' type='Text' name='targetcenter' style='width: 140px' value='$RADEC_MEAN_HMS'>
<input type='hidden' class='formbutton' type='Radio' name='format' value='s' checked>
<input type='hidden' class='forminput' type='Text' name='fieldsize' size='3' value='30'>
<select style='display:none;' class='formselect' name='fieldunit' size='1'>
<option value='3' selected>arc seconds</option>
</select>
<input style='display:none;' class='formbutton' type='Radio' name='geometry' value='r' checked>
<input type='hidden' name='filter[]' value='0' checked>
<input type='hidden' name='filter[]' value='1' checked>
<input type='hidden' name='filter[]' value='2' checked>
<input type='hidden' name='filter[]' value='3' checked>
<select style='display:none;' class='formselect' name='order' size='1' style='width: 140px'>
<option value='9' selected>Angular sep.</option>
</select>
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
<input id=\"h4\" name=\"r\" type=\"hidden\" required=\"\" value=\"32\" size=\"3\"> 
<input type=\"submit\" value='NMW images'>
</form>
"

# Show the ASAS-3 button only for sources with declination below +28 
#TEST=`echo "($DEC_MEAN)<28" |bc -ql`
TEST=`echo "$DEC_MEAN<28" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
re='^[0-9]+$'
if ! [[ $TEST =~ $re ]] ; then
 echo "TEST ERROR in $DEC_MEAN<28" 
 clean_tmp_files
 exit 1
else
 if [ $TEST -eq 1 ];then
  echo -n "<form style='display: inline;' NAME=\"$$FORMASAS$1\" ACTION='http://www.astrouw.edu.pl/cgi-asas/asas_cat_input' METHOD=POST TARGET=\"data_list\"><input type='radio' name='source' value='asas3' CHECKED style=\"display:none;\"><TEXTAREA NAME='coo' ROWS=1 COLS=30 WRAP=virtual style=\"display:none;\">$RADEC_MEAN_HMS</TEXTAREA><INPUT NAME=equinox VALUE=2000 SIZE=4 style=\"display:none;\"><INPUT NAME=nmin VALUE=4 SIZE=4 style=\"display:none;\"><INPUT NAME=box VALUE=15 SIZE=4 style=\"display:none;\"><INPUT TYPE=submit NAME=submit VALUE=\"ASAS-3 lightcurve\" ></form>"
 fi
fi

echo "<br>"

# Write this transient to local exclusion list
echo "$RADEC_MEAN_HMS" >> exclusion_list_local.txt

# just in case
clean_tmp_files

exit 0
# everything is fine!
