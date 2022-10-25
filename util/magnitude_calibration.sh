#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ -f calib.txt ];then
 rm -f calib.txt
fi

if [ ! -f data.m_sigma ];then
 util/nopgplot.sh
fi

if [ -z "$1" ] ;then
 echo "Performing manual magnitude calibration."
 echo "Please specify the comparison stars and their magnitudes!
Opening the reference image..."
 if ! ./pgfv calib ;then
  echo "ERROR running './pgfv calib'"
  exit 1
 fi
else
 # Magnitude calibration for BVRIri bands using APASS magnitudes
 BAND="$1"
 case "$BAND" in
 "C")
 ;;
 "B")
 ;;
 "V")
 ;;
 "R")
 ;;
 "Rc")
 ;;
 "I")
 ;;
 "Ic")
 ;;
 "r")
 ;;
 "i")
 ;;
 "g")
 ;;
 *) 
  echo "ERROR: unknown band $BAND"
  exit 1
 esac
 
 echo "Performing automatic magnitude calibration using $BAND APASS magnitudes."
 
 if [ ! -f vast_summary.log ];then
  echo "ERROR: cannot find vast_summary.log file!"
  exit 1
 fi

 grep "Ref.  image: " vast_summary.log &>/dev/null
 if [ $? -ne 0 ];then
  echo "ERROR: cannot parse vast_summary.log file!"
  exit 1
 fi 
 
 REFERENCE_IMAGE=`grep "Ref.  image: " vast_summary.log  |awk '{print $6}'`

 # Test if the original image is already a calibrated one
 # (Test by checking the file name)
 TEST_SUBSTRING=`basename $REFERENCE_IMAGE`
 TEST_SUBSTRING="${TEST_SUBSTRING:0:4}"
 #TEST_SUBSTRING=`expr substr $TEST_SUBSTRING  1 4`
 if [ "$TEST_SUBSTRING" = "wcs_" ];then
  UCAC5_REFERENCE_IMAGE_MATCH_FILE=`basename $REFERENCE_IMAGE`.cat.ucac5
 else
  UCAC5_REFERENCE_IMAGE_MATCH_FILE=wcs_`basename $REFERENCE_IMAGE`.cat.ucac5
 fi
 # if the output catalog file is present and is not empty
 if [ ! -s "$UCAC5_REFERENCE_IMAGE_MATCH_FILE" ];then
  if ! util/solve_plate_with_UCAC5 $REFERENCE_IMAGE ;then
   echo "Sorry, the reference image could not be solved... :("
   exit 1
  fi
 fi
 # yeah, I know: util/solve_plate_with_UCAC5 is supposed to either produce a correct 
 # output file of fail. But still, let's check that.
 # ERROR check (just in case)
 if [ ! -f $UCAC5_REFERENCE_IMAGE_MATCH_FILE ];then
  echo "ERROR in $0: cannot find file $UCAC5_REFERENCE_IMAGE_MATCH_FILE" 1>&2
  exit 1
 fi
 if [ ! -s $UCAC5_REFERENCE_IMAGE_MATCH_FILE ];then
  echo "ERROR in $0: empty file $UCAC5_REFERENCE_IMAGE_MATCH_FILE" 1>&2
  exit 1
 fi

 # Parse the catalog match file
 case "$BAND" in
 "C")
  export N_COMP_STARS=`cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$11,$12}' | grep -v '0.000000' | wc -l`
  cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$11,$12}' | while read OUTDATFILE A B C ;do 
   if [ -z $C ];then
    continue
   fi
   if [ "$B" == "0.000000" ];then
    continue
   fi
   # strict variability check only if we have many comparison stars
   if [ $N_COMP_STARS -gt 100 ];then
    # Check if this star is constant
    grep --quiet "$OUTDATFILE" vast_list_of_likely_constant_stars.log
    if [ $? -ne 0 ];then
     continue
    fi
   fi
   # Check if this star not variable
   grep --quiet "$OUTDATFILE" vast_autocandidates.log
   if [ $? -eq 0 ];then
    continue
   fi
   # Check if this star is good enough to be listed in vast_lightcurve_statistics.log (useful if we did not check vast_list_of_likely_constant_stars.log )
   grep --quiet "$OUTDATFILE" vast_lightcurve_statistics.log
   if [ $? -ne 0 ];then
    continue
   fi
   # Replace the magnitude and error measured at this image with the median mag and scatter from all images
   MEDIAN_MAG_AND_SCATTER=`grep "$OUTDATFILE" vast_lightcurve_statistics.log | awk '{print $1" "$2}'`
   MEDIAN_MAG=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $1}'`
   SCATTER=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $2}'`
   COMBINED_ERROR=`echo "$SCATTER $C" | awk '{print sqrt($1*$1+$2*$2)}'`
   # Write output
   echo "$MEDIAN_MAG  $B  $COMBINED_ERROR"
  done | sort -n > calib.txt
 ;;
 "B")
  export N_COMP_STARS=`cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$13,$14}' | grep -v '0.000000' | wc -l`
  cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$13,$14}' | while read OUTDATFILE A B C ;do 
   if [ -z $C ];then
    continue
   fi
   if [ "$B" == "0.000000" ];then
    continue
   fi
   # strict variability check only if we have many comparison stars
   if [ $N_COMP_STARS -gt 100 ];then
    # Check if this star is constant
    grep --quiet "$OUTDATFILE" vast_list_of_likely_constant_stars.log
    if [ $? -ne 0 ];then
     continue
    fi
   fi
   # Check if this star not variable
   grep --quiet "$OUTDATFILE" vast_autocandidates.log
   if [ $? -eq 0 ];then
    continue
   fi
   # Check if this star is good enough to be listed in vast_lightcurve_statistics.log (useful if we did not check vast_list_of_likely_constant_stars.log )
   grep --quiet "$OUTDATFILE" vast_lightcurve_statistics.log
   if [ $? -ne 0 ];then
    continue
   fi
   # Replace the magnitude and error measured at this image with the median mag and scatter from all images
   MEDIAN_MAG_AND_SCATTER=`grep "$OUTDATFILE" vast_lightcurve_statistics.log | awk '{print $1" "$2}'`
   MEDIAN_MAG=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $1}'`
   SCATTER=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $2}'`
   COMBINED_ERROR=`echo "$SCATTER $C" | awk '{print sqrt($1*$1+$2*$2)}'`
   # Write output
   echo "$MEDIAN_MAG  $B  $COMBINED_ERROR"
  done | sort -n > calib.txt
 ;;
 "V")
  export N_COMP_STARS=`cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$15,$16}' | grep -v '0.000000' | wc -l`
  cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$15,$16}' | while read OUTDATFILE A B C ;do 
   if [ -z $C ];then
    continue
   fi
   if [ "$B" == "0.000000" ];then
    continue
   fi
   # strict variability check only if we have many comparison stars
   if [ $N_COMP_STARS -gt 100 ];then
    # Check if this star is constant
    grep --quiet "$OUTDATFILE" vast_list_of_likely_constant_stars.log
    if [ $? -ne 0 ];then
     continue
    fi
   fi
   # Check if this star not variable
   grep --quiet "$OUTDATFILE" vast_autocandidates.log
   if [ $? -eq 0 ];then
    continue
   fi
   # Check if this star is good enough to be listed in vast_lightcurve_statistics.log (useful if we did not check vast_list_of_likely_constant_stars.log )
   grep --quiet "$OUTDATFILE" vast_lightcurve_statistics.log
   if [ $? -ne 0 ];then
    continue
   fi
   # Replace the magnitude and error measured at this image with the median mag and scatter from all images
   MEDIAN_MAG_AND_SCATTER=`grep "$OUTDATFILE" vast_lightcurve_statistics.log | awk '{print $1" "$2}'`
   MEDIAN_MAG=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $1}'`
   SCATTER=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $2}'`
   COMBINED_ERROR=`echo "$SCATTER $C" | awk '{print sqrt($1*$1+$2*$2)}'`
   # Write output
   echo "$MEDIAN_MAG  $B  $COMBINED_ERROR"
  done | sort -n > calib.txt
 ;;
 "r")
  export N_COMP_STARS=`cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$17,$18}' | grep -v '0.000000' | wc -l`
  cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$17,$18}' | while read OUTDATFILE A B C ;do 
   if [ -z $C ];then
    continue
   fi
   if [ "$B" == "0.000000" ];then
    continue
   fi
   # strict variability check only if we have many comparison stars
   if [ $N_COMP_STARS -gt 100 ];then
    # Check if this star is constant
    grep --quiet "$OUTDATFILE" vast_list_of_likely_constant_stars.log
    if [ $? -ne 0 ];then
     continue
    fi
   fi
   # Check if this star not variable
   grep --quiet "$OUTDATFILE" vast_autocandidates.log
   if [ $? -eq 0 ];then
    continue
   fi
   # Check if this star is good enough to be listed in vast_lightcurve_statistics.log (useful if we did not check vast_list_of_likely_constant_stars.log )
   grep --quiet "$OUTDATFILE" vast_lightcurve_statistics.log
   if [ $? -ne 0 ];then
    continue
   fi
   # Replace the magnitude and error measured at this image with the median mag and scatter from all images
   MEDIAN_MAG_AND_SCATTER=`grep "$OUTDATFILE" vast_lightcurve_statistics.log | awk '{print $1" "$2}'`
   MEDIAN_MAG=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $1}'`
   SCATTER=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $2}'`
   COMBINED_ERROR=`echo "$SCATTER $C" | awk '{print sqrt($1*$1+$2*$2)}'`
   # Write output
   echo "$MEDIAN_MAG  $B  $COMBINED_ERROR"
  done | sort -n > calib.txt
 ;;
 "i")
  export N_COMP_STARS=`cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$19,$20}' | grep -v '0.000000' | wc -l`
  cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$19,$20}' | while read OUTDATFILE A B C ;do 
   if [ -z $C ];then
    continue
   fi
   if [ "$B" == "0.000000" ];then
    continue
   fi
   # strict variability check only if we have many comparison stars
   if [ $N_COMP_STARS -gt 100 ];then
    # Check if this star is constant
    grep --quiet "$OUTDATFILE" vast_list_of_likely_constant_stars.log
    if [ $? -ne 0 ];then
     continue
    fi
   fi
   # Check if this star not variable
   grep --quiet "$OUTDATFILE" vast_autocandidates.log
   if [ $? -eq 0 ];then
    continue
   fi
   # Check if this star is good enough to be listed in vast_lightcurve_statistics.log (useful if we did not check vast_list_of_likely_constant_stars.log )
   grep --quiet "$OUTDATFILE" vast_lightcurve_statistics.log
   if [ $? -ne 0 ];then
    continue
   fi
   # Replace the magnitude and error measured at this image with the median mag and scatter from all images
   MEDIAN_MAG_AND_SCATTER=`grep "$OUTDATFILE" vast_lightcurve_statistics.log | awk '{print $1" "$2}'`
   MEDIAN_MAG=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $1}'`
   SCATTER=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $2}'`
   COMBINED_ERROR=`echo "$SCATTER $C" | awk '{print sqrt($1*$1+$2*$2)}'`
   # Write output
   echo "$MEDIAN_MAG  $B  $COMBINED_ERROR"
  done | sort -n > calib.txt
 ;;
 "R"|"Rc")
  export N_COMP_STARS=`cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$21,$22}' | grep -v '0.000000' | wc -l`
  cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$21,$22}' | while read OUTDATFILE A B C ;do 
   if [ -z $C ];then
    continue
   fi
   if [ "$B" == "0.000000" ];then
    continue
   fi
   # strict variability check only if we have many comparison stars
   if [ $N_COMP_STARS -gt 100 ];then
    # Check if this star is constant
    grep --quiet "$OUTDATFILE" vast_list_of_likely_constant_stars.log
    if [ $? -ne 0 ];then
     continue
    fi
   fi
   # Check if this star not variable
   grep --quiet "$OUTDATFILE" vast_autocandidates.log
   if [ $? -eq 0 ];then
    continue
   fi
   # Check if this star is good enough to be listed in vast_lightcurve_statistics.log (useful if we did not check vast_list_of_likely_constant_stars.log )
   grep --quiet "$OUTDATFILE" vast_lightcurve_statistics.log
   if [ $? -ne 0 ];then
    continue
   fi
   # Replace the magnitude and error measured at this image with the median mag and scatter from all images
   MEDIAN_MAG_AND_SCATTER=`grep "$OUTDATFILE" vast_lightcurve_statistics.log | awk '{print $1" "$2}'`
   MEDIAN_MAG=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $1}'`
   SCATTER=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $2}'`
   COMBINED_ERROR=`echo "$SCATTER $C" | awk '{print sqrt($1*$1+$2*$2)}'`
   # Write output
   echo "$MEDIAN_MAG  $B  $COMBINED_ERROR"
  done | sort -n > calib.txt
 ;;
 "I"|"Ic")
  export N_COMP_STARS=`cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$23,$24}' | grep -v '0.000000' | wc -l`
  cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$23,$24}' | while read OUTDATFILE A B C ;do 
   if [ -z $C ];then
    continue
   fi
   if [ "$B" == "0.000000" ];then
    continue
   fi
   # strict variability check only if we have many comparison stars
   if [ $N_COMP_STARS -gt 100 ];then
    # Check if this star is constant
    grep --quiet "$OUTDATFILE" vast_list_of_likely_constant_stars.log
    if [ $? -ne 0 ];then
     continue
    fi
   fi
   # Check if this star not variable
   grep --quiet "$OUTDATFILE" vast_autocandidates.log
   if [ $? -eq 0 ];then
    continue
   fi
   # Check if this star is good enough to be listed in vast_lightcurve_statistics.log (useful if we did not check vast_list_of_likely_constant_stars.log )
   grep --quiet "$OUTDATFILE" vast_lightcurve_statistics.log
   if [ $? -ne 0 ];then
    continue
   fi
   # Replace the magnitude and error measured at this image with the median mag and scatter from all images
   MEDIAN_MAG_AND_SCATTER=`grep "$OUTDATFILE" vast_lightcurve_statistics.log | awk '{print $1" "$2}'`
   MEDIAN_MAG=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $1}'`
   SCATTER=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $2}'`
   COMBINED_ERROR=`echo "$SCATTER $C" | awk '{print sqrt($1*$1+$2*$2)}'`
   # Write output
   echo "$MEDIAN_MAG  $B  $COMBINED_ERROR"
  done | sort -n > calib.txt
 ;;
 "g")
  export N_COMP_STARS=`cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$25,$26}' | grep -v '0.000000' | wc -l`
  cat $UCAC5_REFERENCE_IMAGE_MATCH_FILE | awk '{printf "out%05d.dat %f %f %f \n", $1, $8,$25,$26}' | while read OUTDATFILE A B C ;do 
   if [ -z $C ];then
    continue
   fi
   if [ "$B" == "0.000000" ];then
    continue
   fi
   # strict variability check only if we have many comparison stars
   if [ $N_COMP_STARS -gt 100 ];then
    # Check if this star is constant
    grep --quiet "$OUTDATFILE" vast_list_of_likely_constant_stars.log
    if [ $? -ne 0 ];then
     continue
    fi
   fi
   # Check if this star not variable
   grep --quiet "$OUTDATFILE" vast_autocandidates.log
   if [ $? -eq 0 ];then
    continue
   fi
   # Check if this star is good enough to be listed in vast_lightcurve_statistics.log (useful if we did not check vast_list_of_likely_constant_stars.log )
   grep --quiet "$OUTDATFILE" vast_lightcurve_statistics.log
   if [ $? -ne 0 ];then
    continue
   fi
   # Replace the magnitude and error measured at this image with the median mag and scatter from all images
   MEDIAN_MAG_AND_SCATTER=`grep "$OUTDATFILE" vast_lightcurve_statistics.log | awk '{print $1" "$2}'`
   MEDIAN_MAG=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $1}'`
   SCATTER=`echo $MEDIAN_MAG_AND_SCATTER | awk '{print $2}'`
   COMBINED_ERROR=`echo "$SCATTER $C" | awk '{print sqrt($1*$1+$2*$2)}'`
   # Write output
   echo "$MEDIAN_MAG  $B  $COMBINED_ERROR"
  done | sort -n > calib.txt
 ;;
 *) 
  echo "ERROR: unknown band $BAND"
  exit 1
 esac

fi

if [ -f calib.txt ];then
 echo "Saving a copy of calib.txt in calib.txt_backup"
 cp calib.txt calib.txt_backup
fi
if [ -f calib.txt_param ];then
 echo "Saving a copy of calib.txt_param in calib.txt_param_backup"
 cp calib.txt_param calib.txt_param_backup
fi

if [ "$2" == "linear" ];then
 FIT_MAG_CALIB_RESULTING_PARARMETERS=`lib/fit_linear`
 if [ $? -ne 0 ];then
  echo "ERROR fitting the magnitude scale! :("
  exit 1
 fi
elif [ "$2" == "robust_linear" ];then
 FIT_MAG_CALIB_RESULTING_PARARMETERS=`lib/fit_robust_linear`
 if [ $? -ne 0 ];then
  echo "ERROR fitting the magnitude scale! :("
  exit 1
 fi
elif [ "$2" == "zero_point" ];then
 FIT_MAG_CALIB_RESULTING_PARARMETERS=`lib/fit_zeropoint`
 if [ $? -ne 0 ];then
  echo "ERROR fitting the magnitude scale! :("
  exit 1
 fi
elif [ "$2" == "photocurve" ];then
 FIT_MAG_CALIB_RESULTING_PARARMETERS=`lib/fit_photocurve`
 if [ $? -ne 0 ];then
  echo "ERROR fitting the magnitude scale! :("
  exit 1
 fi
else
 FIT_MAG_CALIB_RESULTING_PARARMETERS=`lib/fit_mag_calib`
 if [ $? -ne 0 ];then
  echo "ERROR fitting the magnitude scale! :("
  exit 1
 fi
fi

if [ -z "$FIT_MAG_CALIB_RESULTING_PARARMETERS" ];then
 echo "ERROR in the output parameters of the magnitude scale fit! :("
 exit 1
fi
echo "Proceeding with the calibration..."
util/calibrate_magnitude_scale $FIT_MAG_CALIB_RESULTING_PARARMETERS
if [ $? -ne 0 ];then
 echo "ERROR running 'util/calibrate_magnitude_scale $FIT_MAG_CALIB_RESULTING_PARARMETERS'"
 exit 1
fi
util/nopgplot.sh -q
echo "Magnitde calibration complete. :)"
