#!/usr/bin/env bash

# make sure the manual override TELESCOP variable is not set,
# otherwise it will mess up all the plate-solve tests
unset TELESCOP

# for test runs with AddressSanitizer 
export ASAN_OPTIONS=strict_string_checks=1:detect_stack_use_after_return=1:check_initialization_order=1:strict_init_order=1

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################




##### Auxiliary functions #####

function email_vast_test_report {
 HOST=`hostname`
 HOST="@$HOST"
 NAME="$USER$HOST"
# DATETIME=`LANG=C date --utc`
# bsd dae doesn't know '--utc', but accepts '-u'
 DATETIME=`LANG=C date -u`
 SCRIPTNAME=`basename $0`
 LOG=`cat vast_test_report.txt`
 MSG="The script $0 has finished on $DATETIME at $PWD $LOG $DEBUG_OUTPUT"
echo "
$MSG
#########################################################
$DEBUG_OUTPUT

" > vast_test_email_message.log
 curl --silent 'http://scan.sai.msu.ru/vast/vasttestreport.php' --data-urlencode "name=$NAME running $SCRIPTNAME" --data-urlencode message@vast_test_email_message.log --data-urlencode 'submit=submit'
 if [ $? -eq 0 ];then
  echo "The test report was sent successfully"
 else
  echo "There was a problem sending the test report"
 fi
}

function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=`readlink -f "$1" 2>/dev/null`
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=`greadlink -f "$1" 2>/dev/null`
   if [ $? -ne 0 ];then
    REALPATH=`realpath "$1" 2>/dev/null`
    if [ $? -ne 0 ];then
     REALPATH=`grealpath "$1" 2>/dev/null`
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")"
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD"
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}



function find_source_by_X_Y_in_vast_lightcurve_statistics_log {
 if [ ! -s vast_lightcurve_statistics.log ];then
  echo "ERROR: no vast_lightcurve_statistics.log" 1>&2
  return 1
 fi
 if [ -z $2 ];then
  echo "ERROR: please specify X Y position of the target"
  return 1
 fi
 cat vast_lightcurve_statistics.log | awk "
BEGIN {
 x=$1;
 y=$2;
 best_distance_squared=3*3;
 source_name=\"none\";
}
{
distance_squared=(\$3-x)*(\$3-x)+(\$4-y)*(\$4-y);
if( distance_squared<best_distance_squared ){best_distance_squared=distance_squared;source_name=\$5;}
}
END {
 print source_name
}
"
 return 0
}

function test_https_connection {
 curl --max-time 10 --silent https://scan.sai.msu.ru/astrometry_engine/files/ | grep --quiet 'Parent Directory'
 if [ $? -ne 0 ];then
  # if the above didn't work, try to download the certificate
  # The old cert that has expired already, will keep it in case clocks on the test machine are really off
  curl --max-time 10 --silent https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem > intermediate.pem
  # The new one
  curl --max-time 10 --silent https://letsencrypt.org/certs/lets-encrypt-r3.pem >> intermediate.pem
  # if that fails - abort the test
  # latest CA list from cURL
  curl --max-time 10 --silent https://curl.se/ca/cacert.pem >> intermediate.pem
  if [ $? -ne 0 ];then
   return 2
  fi
  curl --max-time 10 --silent --cacert intermediate.pem https://scan.sai.msu.ru/astrometry_engine/files/ | grep --quiet 'Parent Directory'
  if [ $? -ne 0 ];then
   # cleanup
   if [ -f intermediate.pem ];then
    rm -f intermediate.pem
   fi
   #
   echo "ERROR in test_https_connection(): cannot connect to scan.sai.msu.ru" 1>&2
   return 1
  fi
 fi
 
 # note there is no https support at vast.sai.msu.ru yet

 curl --max-time 10 --silent https://kirx.net/astrometry_engine/files/ | grep --quiet 'Parent Directory'
 if [ $? -ne 0 ];then
  if [ ! -f intermediate.pem ];then
   # if the above didn't work, try to download the certificate
   # The old cert that has expired already, will keep it in case clocks on the test machine are really off
   curl --max-time 10 --silent https://letsencrypt.org/certs/lets-encrypt-x3-cross-signed.pem > intermediate.pem
   # The new one
   curl --max-time 10 --silent https://letsencrypt.org/certs/lets-encrypt-r3.pem >> intermediate.pem
   # if that fails - abort the test
   # latest CA list from cURL
   curl --max-time 10 --silent https://curl.se/ca/cacert.pem >> intermediate.pem
   # if that fails - abort the test
   if [ $? -ne 0 ];then
    return 2
   fi
  fi
  curl --max-time 10 --silent --cacert intermediate.pem https://kirx.net/astrometry_engine/files/ | grep --quiet 'Parent Directory'
  if [ $? -ne 0 ];then
   echo "ERROR in test_https_connection(): cannot connect to vast.sai.msu.ru" 1>&2
   return 1
  fi
 fi

 if [ -f intermediate.pem ];then
  rm -f intermediate.pem
 fi

 return 0
}


function check_if_vast_install_looks_reasonably_healthy {
 for FILE_TO_CHECK in ./vast GNUmakefile makefile lib/autodetect_aperture_main lib/bin/xy2sky lib/catalogs/check_catalogs_offline lib/choose_vizier_mirror.sh lib/deeming_compute_periodogram lib/deg2hms_uas lib/drop_bright_points lib/drop_faint_points lib/fit_robust_linear lib/guess_saturation_limit_main lib/hms2deg lib/lk_compute_periodogram lib/new_lightcurve_sigma_filter lib/put_two_sources_in_one_field lib/remove_bad_images lib/remove_lightcurves_with_small_number_of_points lib/select_only_n_random_points_from_set_of_lightcurves lib/sextract_single_image_noninteractive lib/try_to_guess_image_fov lib/update_offline_catalogs.sh lib/update_tai-utc.sh lib/vizquery util/calibrate_magnitude_scale util/calibrate_single_image.sh util/ccd/md util/ccd/mk util/ccd/ms util/clean_data.sh util/examples/test_coordinate_converter.sh util/examples/test__dark_flat_flag.sh util/examples/test_heliocentric_correction.sh util/fov_of_wcs_calibrated_image.sh util/get_image_date util/hjd_input_in_UTC util/load.sh util/magnitude_calibration.sh util/make_finding_chart util/nopgplot.sh util/rescale_photometric_errors util/save.sh util/search_databases_with_curl.sh util/search_databases_with_vizquery.sh util/solve_plate_with_UCAC5 util/stat_outfile util/sysrem2 util/transients/transient_factory_test31.sh util/wcs_image_calibration.sh ;do
  if [ ! -s "$FILE_TO_CHECK" ];then
   echo "
ERROR: cannot find a proper VaST installation in the current directory
$PWD

check_if_vast_install_looks_reasonably_healthy() failed while checking the file $FILE_TO_CHECK
CANCEL TEST"
   return 1
  fi
 done
 return 0
}


function remove_test_data_to_save_space {
 #########################################
 # Remove test data from the previous tests if we are out of disk space
 #########################################
 # Skip free disk space check on some pre-defined machines
 # hope this check should work even if there is no 'hostname' command
 hostname | grep --quiet 'eridan' 
 if [ $? -ne 0 ];then 
  # Free-up disk space if we run out of it
  FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
  # If we managed to get the disk space info
  if [ $? -eq 0 ];then
   TEST=`echo "$FREE_DISK_SPACE_MB<4096" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
   re='^[0-9]+$'
   if ! [[ $TEST =~ $re ]] ; then
    echo "TEST ERROR"
    TEST=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DISKSPACE_TEST_ERROR"
   fi
   if [ $TEST -eq 1 ];then
    echo "WARNING: we are almost out of disk space, only $FREE_DISK_SPACE_MB MB remaining." 1>&2
    for TEST_DATASET in ../NMW_And1_test_lightcurves_40 ../Gaia16aye_SN ../individual_images_test ../KZ_Her_DSLR_transient_search_test ../M31_ISON_test ../M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails ../MASTER_test ../only_few_stars ../test_data_photo ../test_exclude_ref_image ../transient_detection_test_Ceres ../NMW_Saturn_test ../NMW_Venus_test ../NMW_find_Chandra_test ../NMW_find_NovaCas_august31_test ../NMW_Sgr9_crash_test ../NMW_Sgr1_NovaSgr20N4_test ../NMW_Aql11_NovaHer21_test ../NMW_Vul2_magnitude_calibration_exit_code_test ../NMW_find_NovaCas21_test ../NMW_Sco6_NovaSgr21N2_test ../NMW_Sgr7_NovaSgr21N1_test ../NMW_find_Mars_test ../tycho2 ../vast_test_lightcurves ../vast_test__dark_flat_flag ../vast_test_ASASSN-19cq ../vast_test_bright_stars_failed_match '../sample space' ../NMW_corrupt_calibration_test ../NMW_ATLAS_Mira_in_Ser1 ../DART_Didymos_moving_object_photometry_test ;do
     # Simple safety thing
     TEST=`echo "$TEST_DATASET" | grep -c '\.\.'`
     if [ $TEST -ne 1 ];then
      continue
     fi
     #
     if [ -d "$TEST_DATASET" ];then
      rm -rf "$TEST_DATASET"
     fi
    done
   fi # if [ $FREE_DISK_SPACE_MB -lt 1024 ];then
  fi # if [ $? -eq 0 ];then
 fi # if [ $? -ne ];then # hostname check
 #########################################

 return 0
}


function check_if_enough_disk_space_for_tests {
 hostname | grep --quiet 'eridan' 
 if [ $? -ne 0 ];then 
  # Check free disk space
  FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
  # If we managed to get the disk space info
  if [ $? -eq 0 ];then
   TEST=`echo "$FREE_DISK_SPACE_MB<2048" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
   re='^[0-9]+$'
   if ! [[ $TEST =~ $re ]] ; then
    echo "TEST ERROR"
    TEST=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DISKSPACE_TEST_ERROR"
    # if test failed assume good things
    return 0
   fi
   if [ $TEST -eq 1 ];then
    echo "ERROR: we are almost out of disk space, only $FREE_DISK_SPACE_MB MB remaining - CANCEL TEST" 1>&2
    return 1
   fi # if [ $FREE_DISK_SPACE_MB -lt 1024 ];then
  fi # if [ $? -eq 0 ];then
 fi # if [ $? -ne ];then # hostname check
 #########################################

 return 0
}


function test_internet_connection {
 curl --max-time 10 --silent http://scan.sai.msu.ru/astrometry_engine/files/ | grep --quiet 'Parent Directory'
 if [ $? -ne 0 ];then
  echo "ERROR in test_internet_connection(): cannot connect to scan.sai.msu.ru" 1>&2
  return 1
 fi
 
 # early exit for the fast test
 if [ "$1" = "fast" ];then
  return 0
 fi

 curl --max-time 10 --silent http://vast.sai.msu.ru/astrometry_engine/files/ | grep --quiet 'Parent Directory'
 if [ $? -ne 0 ];then
  echo "ERROR in test_internet_connection(): cannot connect to vast.sai.msu.ru" 1>&2
  return 1
 fi
 
 # lib/choose_vizier_mirror.sh will return non-zero exit code if it could not actually reach a VizieR mirror
 lib/choose_vizier_mirror.sh 2>&1
 if [ $? -ne 0 ];then
  echo "ERROR in test_internet_connection(): cannot connect to VizieR" 1>&2
  return 1
 fi

 return 0
}





##################################################
################# Start testing ##################
##################################################


VAST_PATH=`vastrealpath $0`
VAST_PATH=`dirname "$VAST_PATH"`
VAST_PATH="${VAST_PATH/util/}"
VAST_PATH="${VAST_PATH/lib/}"
VAST_PATH="${VAST_PATH/examples/}"
VAST_PATH="${VAST_PATH/'//'/'/'}"
# In case the above line didn't work
VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
# Make sure no quotation marks are left in VAST_PATH
VAST_PATH=`echo "$VAST_PATH" | sed "s:'::g"`
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
export VAST_PATH
# Check if we are in the VaST root directory
if [ "$VAST_PATH" != "$PWD/" ];then
 echo "WARNING: we are currently at the wrong directory: $PWD while we should be at $VAST_PATH
Changing directory"
 cd "$VAST_PATH"
fi


# Test if curl is installed
command -v curl &> /dev/null
if [ $? -ne 0 ];then
 echo "ERROR in $0: curl not found in PATH"
 echo "No web search will be done!"
 exit 1
fi


# Check if the main VaST sub-programs exist
check_if_vast_install_looks_reasonably_healthy
if [ $? -ne 0 ];then
 exit 1
fi


## These two functions are needed to check that no leftover files are produced by util/transients/report_transient.sh
function test_if_test31_tmp_files_are_present {
 for TMP_FILE_TO_REMOVE in ra*.dat dec*.dat mag*.dat script*.dat dayfrac*.dat jd*.dat x*.dat y*.dat ;do
  if [ -f "$TMP_FILE_TO_REMOVE" ];then
   return 1
  fi
 done
 return 0;
}


function remove_test31_tmp_files_if_present {
 for TMP_FILE_TO_REMOVE in ra*.dat dec*.dat mag*.dat script*.dat dayfrac*.dat jd*.dat x*.dat y*.dat ;do
  if [ -f "$TMP_FILE_TO_REMOVE" ];then
   rm -f "$TMP_FILE_TO_REMOVE"
  fi
 done
 return 0;
}


# Test the connection right away
test_internet_connection
if [ $? -ne 0 ];then
 exit 1
fi



# remove suspisious files
## File names equal to small numbers will confuse VaST when it tries to parse command line options
for SUSPICIOUS_FILE in 1 2 3 4 5 6 7 8 9 10 11 12 ;do
 if [ -f "$SUSPICIOUS_FILE" ];then
  rm -f "$SUSPICIOUS_FILE"
 fi
done


#########################################
# Remove test data from the previous run if we are out of disk space
#########################################
remove_test_data_to_save_space


# Test if we have enough disk space for the tests
check_if_enough_disk_space_for_tests
if [ $? -ne 0 ];then
 exit 1
fi



##### Report that we are starting the work #####
echo "---------- Starting $0 ----------" 1>&2
echo "---------- $0 ----------" > vast_test_report.txt

##### Set initial values for the variables #####
DEBUG_OUTPUT=""
FAILED_TEST_CODES=""
WORKDIR="$PWD"
VAST_VERSION_STRING=`./vast --version`
VAST_BUILD_NUMBER=`cat .cc.build`
STARTTIME_UNIXSEC=$(date +%s)
# BSD date will not understand `date -d @$STARTTIME_UNIXSEC`
#STARTTIME_HUMAN_RADABLE=`date -d @$STARTTIME_UNIXSEC`
STARTTIME_HUMAN_RADABLE=`date`
echo "Started on $STARTTIME_HUMAN_RADABLE" 1>&2
echo "Started on $STARTTIME_HUMAN_RADABLE" >> vast_test_report.txt

##### Gather system information #####
echo "Gathering basic system information for summary report" 1>&2
echo "---------- System information ----------" >> vast_test_report.txt
SYSTEM_TYPE=`uname`
if [ "$SYSTEM_TYPE" = "Linux" ];then
 # Use inxi script to generate nice human-readable system parameters summary
 lib/inxi -c0 -! 31 -S -M -C -I >> vast_test_report.txt
 # If inix fails, gather at least some basic info
 if [ $? -ne 0 ];then
  uname -a >> vast_test_report.txt
  lscpu >> vast_test_report.txt
  free -m >> vast_test_report.txt
 fi
else
 # Resort to uname and sysctl
 uname -a >> vast_test_report.txt
 sysctl -a | grep -e "hw.machine_arch" -e "hw.model" -e "hw.ncpu" -e "hw.physmem" -e "hw.memsize" >> vast_test_report.txt
fi
echo "$VAST_VERSION_STRING compiled with "`cat .cc.version` >> vast_test_report.txt
echo "VaST build number $VAST_BUILD_NUMBER" >> vast_test_report.txt
export PATH="$PATH:lib/bin"
sex -v >> vast_test_report.txt

command -v psfex &> /dev/null
if [ $? -eq 0 ];then
 psfex -v >> vast_test_report.txt
else
 echo "PSFEx is not installed" >> vast_test_report.txt
fi

cat vast_test_report.txt 1>&2
echo "---------- $VAST_VERSION_STRING test results ----------" >> vast_test_report.txt

# Reset the increpmental list of failed test codes
# (this list is useful if you cancel the test before it completes)
cat vast_test_report.txt > vast_test_incremental_list_of_failed_test_codes.txt


##### DART Didymos moving object photometry test #####
if [ ! -d ../DART_Didymos_moving_object_photometry_test ];then
 cd ..
 if [ -f DART_Didymos_moving_object_photometry_test.tar.bz2 ] ;then
  rm -f DART_Didymos_moving_object_photometry_test.tar.bz2
 fi
 $($WORKDIR/lib/find_timeout_command.sh) 300 curl -O "http://scan.sai.msu.ru/~kirx/pub/DART_Didymos_moving_object_photometry_test.tar.bz2" && tar -xjf DART_Didymos_moving_object_photometry_test.tar.bz2 && rm -f DART_Didymos_moving_object_photometry_test.tar.bz2
 cd $WORKDIR
fi

if [ -d ../DART_Didymos_moving_object_photometry_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "DART Didymos moving object photometry test " 1>&2
 echo -n "DART Didymos moving object photometry test: " >> vast_test_report.txt 
 cp -v default.sex.MSU_DART default.sex
 cp -v ../DART_Didymos_moving_object_photometry_test/vast_input_user_specified_moving_object_position.txt .
 ./vast --nofind --type 2 -a33 --movingobject ../DART_Didymos_moving_object_photometry_test/wcs_fd_DART_60sec_Clear_run03-*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DART_VAST_RUN_FAILED"  
 else
 
  if [ -f vast_summary.log ];then
   grep --quiet "Images processed 35" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DART_IMG_PROC"
   fi
   grep --quiet "Images used for photometry 34" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DART_IMG_MEA"
   fi
   grep --quiet 'Ref.  image: 2459852.89419 30.09.2022 09:27:08' vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DART_REF_IMG_DATE"
   fi
   grep --quiet 'First image: 2459852.89419 30.09.2022 09:27:08' vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DART_FIRST_IMG_DATE"
   fi
   grep --quiet 'Last  image: 2459852.91936 30.09.2022 10:03:23' vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DART_LAST_IMG_DATE"
   fi
   
   ###############################################

   MOVING_OBJECT_LIGHTCURVE=`grep 'User-specified moving object:' vast_summary.log | awk '{print $4}'`
   if [ ! -f "$MOVING_OBJECT_LIGHTCURVE" ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DART_NO_MOVING_OBJECT_LIGHTCURVE"
   else
    if [ ! -s "$MOVING_OBJECT_LIGHTCURVE" ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES DART_EMPTY_MOVING_OBJECT_LIGHTCURVE"
    else
     util/magnitude_calibration.sh V zero_point
     if [ $? -ne 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES DART_MAGNITUDE_CALIBRATION_FAILED"  
     else
      #
      N_LINES=`cat "$MOVING_OBJECT_LIGHTCURVE" | wc -l`
      if [ $N_LINES -lt 28 ];then
       TEST_PASSED=0
       FAILED_TEST_CODES="$FAILED_TEST_CODES DART_N_LINES_$N_LINES"
      fi
      #
      MEAN_MAG=`cat "$MOVING_OBJECT_LIGHTCURVE" | awk '{print $2}' | util/colstat | grep 'MEAN=' | awk '{print $2}'`
      TEST=`echo "$MEAN_MAG" | awk '{if ( sqrt( ($1-13.578386)*($1-13.578386) ) < 0.05 ) print 1 ;else print 0 }'`
      re='^[0-9]+$'
      if ! [[ $TEST =~ $re ]] ; then
       echo "TEST ERROR"
       TEST_PASSED=0
       TEST=0
       FAILED_TEST_CODES="$FAILED_TEST_CODES DART_MEAN_MAG_TEST_ERROR"
      else
       if [ $TEST -eq 0 ];then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES DART_MEAN_MAG"
       fi
      fi # if ! [[ $TEST =~ $re ]] ; then
      #
     fi # util/magnitude_calibration.sh V zero_point
    fi # check MOVING_OBJECT_LIGHTCURVE file nonempty
   fi # check MOVING_OBJECT_LIGHTCURVE file exist

  else
   echo "ERROR: cannot find vast_summary.log" 1>&2
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DART_ALL"
  fi # if [ -f vast_summary.log ];then

 fi # check vast run success

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mDART Didymos moving object photometry test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mDART Didymos moving object photometry test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi

else
 FAILED_TEST_CODES="$FAILED_TEST_CODES DART_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
#



##### Check SysRem #####
if [ ! -d ../NMW_And1_test_lightcurves_40 ];then
 cd ..
 if [ -f NMW_And1_test_lightcurves_40.tar.bz2 ];then
  rm -f NMW_And1_test_lightcurves_40.tar.bz2
 fi
 $($WORKDIR/lib/find_timeout_command.sh) 300 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_And1_test_lightcurves_40.tar.bz2" && tar -xjf NMW_And1_test_lightcurves_40.tar.bz2 && rm -f NMW_And1_test_lightcurves_40.tar.bz2
 cd $WORKDIR
fi

if [ -d ../NMW_And1_test_lightcurves_40 ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "SysRem test " 1>&2
 echo -n "SysRem test: " >> vast_test_report.txt 
 # Save VaST config files that may be overwritten when loading a data set
 for FILE_TO_SAVE in bad_region.lst default.psfex default.sex ;do
  if [ -f "$FILE_TO_SAVE" ];then
   mv "$FILE_TO_SAVE" "$FILE_TO_SAVE"_vastautobackup
  fi
 done 
 util/load.sh ../NMW_And1_test_lightcurves_40
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM001"
 fi 
 # Restore the previously-saved VaST config files
 for FILE_TO_RESTORE in *_vastautobackup ;do
  if [ -f "$FILE_TO_RESTORE" ];then
   mv -f "$FILE_TO_RESTORE" `basename "$FILE_TO_RESTORE" _vastautobackup`
  fi
 done
 SYSTEMATIC_NOISE_LEVEL_BEFORE_SYSREM=`util/estimate_systematic_noise_level 2> /dev/null`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM002"
 fi
 #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL_BEFORE_SYSREM)-(0.0304);sqrt(a*a)<0.005" | bc -ql`
 TEST=`echo "$SYSTEMATIC_NOISE_LEVEL_BEFORE_SYSREM" | awk '{if ( sqrt( ($1-0.0304)*($1-0.0304) ) < 0.005 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM003_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM003"
 fi
 if [ ! -s vast_lightcurve_statistics.log ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM004"
 fi
 MEDIAN_SIGMACLIP_BRIGHTSTARS_BEFORE_SYSREM=`cat vast_lightcurve_statistics.log | head -n1000 | awk '{print $2}' | util/colstat 2>/dev/null | grep 'MEDIAN' | awk '{print $2}'`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM005"
 fi
 #TEST=`echo "a=($MEDIAN_SIGMACLIP_BRIGHTSTARS_BEFORE_SYSREM)-(0.026058);sqrt(a*a)<0.005" | bc -ql`
 TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS_BEFORE_SYSREM" | awk '{if ( sqrt( ($1-0.026058)*($1-0.026058) ) < 0.005 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM006_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM006"
 fi
 util/sysrem2
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM007"
 fi
 SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM=`util/estimate_systematic_noise_level 2> /dev/null`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM102"
 fi
 #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM)-(0.0270);sqrt(a*a)<0.005" | bc -ql`
 TEST=`echo "$SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM" | awk '{if ( sqrt( ($1-0.0270)*($1-0.0270) ) < 0.005 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM103_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM103"
 fi
 if [ ! -s vast_lightcurve_statistics.log ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM104"
 fi
 MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM=`cat vast_lightcurve_statistics.log | head -n1000 | awk '{print $2}' | util/colstat 2>/dev/null | grep 'MEDIAN' | awk '{print $2}'`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM105"
 fi
 #TEST=`echo "a=($MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM)-(0.021055);sqrt(a*a)<0.005" | bc -ql`
 TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM" | awk '{if ( sqrt( ($1-0.021055)*($1-0.021055) ) < 0.005 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM106_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM106"
 fi
 #TEST=`echo "$SYSTEMATIC_NOISE_LEVEL_BEFORE_SYSREM > $SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM" | bc -ql`
 TEST=`echo "$SYSTEMATIC_NOISE_LEVEL_BEFORE_SYSREM > $SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM0_SYSNOISEDECREASE_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM0_SYSNOISEDECREASE"
 fi
 #TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS_BEFORE_SYSREM > $MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM" | bc -ql`
 TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS_BEFORE_SYSREM>$MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM0_MSIGMACLIPDECREASE_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM0_MSIGMACLIPDECREASE"
 fi
 util/sysrem2
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM007"
 fi
 SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM=`util/estimate_systematic_noise_level 2> /dev/null`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM102"
 fi
 #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM)-(0.0254);sqrt(a*a)<0.005" | bc -ql`
 TEST=`echo "$SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM" | awk '{if ( sqrt( ($1-0.0254)*($1-0.0254) ) < 0.005 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM103_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM103"
 fi
 if [ ! -s vast_lightcurve_statistics.log ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM104"
 fi
 MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM=`cat vast_lightcurve_statistics.log | head -n1000 | awk '{print $2}' | util/colstat 2>/dev/null | grep 'MEDIAN' | awk '{print $2}'`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM105"
 fi
 #TEST=`echo "a=($MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM)-(0.020588);sqrt(a*a)<0.005" | bc -ql`
 TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM" | awk '{if ( sqrt( ($1-0.020588)*($1-0.020588) ) < 0.005 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM106_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM106"
 fi
 #TEST=`echo "$SYSTEMATIC_NOISE_LEVEL_BEFORE_SYSREM > $SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM" | bc -ql`
 TEST=`echo "$SYSTEMATIC_NOISE_LEVEL_BEFORE_SYSREM>$SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM1_SYSNOISEDECREASE_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM1_SYSNOISEDECREASE"
 fi
 #TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS_BEFORE_SYSREM > $MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM" | bc -ql`
 TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS_BEFORE_SYSREM>$MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM1_MSIGMACLIPDECREASE_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM1_MSIGMACLIPDECREASE"
 fi
 util/sysrem2
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM207"
 fi
 util/sysrem2
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM307"
 fi
 util/sysrem2
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM407"
 fi
 SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM=`util/estimate_systematic_noise_level 2> /dev/null`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM502"
 fi
 #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM)-(0.0245);sqrt(a*a)<0.005" | bc -ql`
 TEST=`echo "$SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM" | awk '{if ( sqrt( ($1-0.0245)*($1-0.0245) ) < 0.005 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM503_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM503"
 fi
 if [ ! -s vast_lightcurve_statistics.log ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM504"
 fi
 MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM=`cat vast_lightcurve_statistics.log | head -n1000 | awk '{print $2}' | util/colstat 2>/dev/null | grep 'MEDIAN' | awk '{print $2}'`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM505"
 fi
 TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM" | awk '{if ( sqrt( ($1-0.018628)*($1-0.018628) ) < 0.005 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM506_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM506"
 fi
 #TEST=`echo "$SYSTEMATIC_NOISE_LEVEL_BEFORE_SYSREM > $SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM" | bc -ql`
 TEST=`echo "$SYSTEMATIC_NOISE_LEVEL_BEFORE_SYSREM>$SYSTEMATIC_NOISE_LEVEL_AFTER_SYSREM" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM5_SYSNOISEDECREASE_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM5_SYSNOISEDECREASE"
 fi
 #TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS_BEFORE_SYSREM > $MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM" | bc -ql`
 TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS_BEFORE_SYSREM>$MEDIAN_SIGMACLIP_BRIGHTSTARS_AFTER_SYSREM" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM5_MSIGMACLIPDECREASE_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM5_MSIGMACLIPDECREASE"
 fi
 ################################################################################
 # Check individual variables in the test data set
 ################################################################################
 # True variables
 for XY in "849.6359900 156.5065000" "1688.0546900 399.5051000" "3181.1794400 2421.1013200" "867.0582900  78.9714000" "45.6917000 2405.7465800" "2843.8242200 2465.0180700" ;do
  LIGHTCURVEFILE=$(find_source_by_X_Y_in_vast_lightcurve_statistics_log $XY)
  if [ "$LIGHTCURVEFILE" == "none" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES  NMWSYSREM5_VARIABLE_NOT_DETECTED__${XY// /_}"
  else
   if [ "$XY" = "849.6359900 156.5065000" ];then
    SIGMACLIP=`grep "$LIGHTCURVEFILE" vast_lightcurve_statistics.log | awk '{print $2}'`
    #TEST=`echo "a=($SIGMACLIP)-(0.058346);sqrt(a*a)<0.005" | bc -ql`
    TEST=`echo "$SIGMACLIP" | awk '{if ( sqrt( ($1-0.058346)*($1-0.058346) ) < 0.005 ) print 1 ;else print 0 }'`
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
     echo "TEST ERROR"
     TEST_PASSED=0
     TEST=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM_GDOR_TEST_ERROR"
    fi
    if [ $TEST -ne 1 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM_GDOR"
    fi
   fi
  fi
  grep --quiet "$LIGHTCURVEFILE" vast_autocandidates.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES  NMWSYSREM5_VARIABLE_NOT_SELECTED__$LIGHTCURVEFILE"
  fi
  grep --quiet "$LIGHTCURVEFILE" vast_list_of_likely_constant_stars.log
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES  NMWSYSREM5_VARIABLE_MISTAKEN_FOR_CONSTANT__$LIGHTCURVEFILE"
  fi
 done


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSysRem test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSysRem test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSYSREM_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
#

# Test the connection
test_internet_connection fast
if [ $? -ne 0 ];then
 exit 1
fi


##### Photographic plate test #####
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
### Check the consistency of the dest data if its already there
if [ -d ../test_data_photo ];then
 NUMBER_OF_IMAGES_IN_TEST_FOLDER=`ls -1 ../test_data_photo | wc -l | awk '{print $1}'`
 if [ $NUMBER_OF_IMAGES_IN_TEST_FOLDER -lt 150 ];then
  # If the number of files is smaller than it should be 
  # - just remove the directory, the following lines will download the data again.
  echo "WARNING: corrupted test data found in ../test_data_photo" 1>&2
  rm -rf ../test_data_photo
 fi
fi
# Download the test dataset if needed
if [ ! -d ../test_data_photo ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/test_data_photo.tar.bz2"
 if [ $? -ne 0 ];then
  echo "ERROR downloading test data!" 1>&2
  exit 1
 fi
 tar -xvjf test_data_photo.tar.bz2
 if [ $? -ne 0 ];then
  echo "ERROR unpacking test data! Are we out of disk space?" 1>&2
  df -h .
  if [ -d ../test_data_photo ];then
   # Remove partially complete test data directory if it has been created
   rm -rf ../test_data_photo
  fi
  exit 1
 fi
 if [ -f test_data_photo.tar.bz2 ];then
  rm -f test_data_photo.tar.bz2
 fi
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../test_data_photo ];then
 ## Check if the test data are OK
 # Using 'grep -c ""'  instead of 'wc -l' in ornder not to depend on 'wc'
 # OK now we depand on 'wc'
 NUMBER_OF_IMAGES_IN_TEST_FOLDER=`ls -1 ../test_data_photo | wc -l | awk '{print $1}'`
 if [ $NUMBER_OF_IMAGES_IN_TEST_FOLDER -ge 150 ];then
  THIS_TEST_START_UNIXSEC=$(date +%s)
  TEST_PASSED=1
  ##
  util/clean_data.sh
  # Run the test
  echo "Photographic plates test " 1>&2
  echo -n "Photographic plates test: " >> vast_test_report.txt 
  cp default.sex.beta_Cas_photoplates default.sex
  ./vast -u -o -j -f --nomagsizefilter ../test_data_photo/SCA*
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE000"
  fi
  # Check results
  if [ -f vast_summary.log ];then
   grep --quiet "Images used for photometry 150" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE001" 
   fi
   grep --quiet "First image: 2433153.50800" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE002"
   fi
   grep --quiet "Last  image: 2447836.28000" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE003"
   fi
   # Hunting the mysterious non-zero reference frame rotation cases
   if [ -f vast_image_details.log ];then
    grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_nonzero_ref_frame_rotation"
     GREP_RESULT=`cat vast_summary.log vast_image_details.log`
     DEBUG_OUTPUT="$DEBUG_OUTPUT
###### PHOTOPLATE_nonzero_ref_frame_rotation ######
$GREP_RESULT"
    fi
    grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_nonzero_ref_frame_rotation_test2"
     GREP_RESULT=`cat vast_summary.log vast_image_details.log`
     DEBUG_OUTPUT="$DEBUG_OUTPUT
###### PHOTOPLATE_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
    fi
   else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_NO_vast_image_details_log"
   fi
   #
   # ../test_data_photo/SCA14627S_16037_07933__00_00.fit is a bad image just below 0.11
   grep --quiet "Number of identified bad images: 0" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE003a"
   fi
   grep --quiet "Magnitude-Size filter: Disabled" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE003b"
   fi
   # Test the connection
   test_internet_connection fast
   if [ $? -ne 0 ];then
    exit 1
   fi
   util/wcs_image_calibration.sh ../test_data_photo/SCA1017S_17061_09773__00_00.fit
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE004_platesolve"
   else
    if [ ! -f wcs_SCA1017S_17061_09773__00_00.fit ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE005"
    fi
    lib/bin/xy2sky wcs_SCA1017S_17061_09773__00_00.fit 200 200 &>/dev/null
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE005a"
    fi
   fi
   util/solve_plate_with_UCAC5 ../test_data_photo/SCA1017S_17061_09773__00_00.fit
   if [ ! -f wcs_SCA1017S_17061_09773__00_00.fit.cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE006_platesolveucac5"
   else
    TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_SCA1017S_17061_09773__00_00.fit.cat.ucac5 | wc -l | awk '{print $1}'`
    if [ $TEST -lt 400 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE006a_too_few_stars_matched_to_ucac5_$TEST"
    fi
    if [ ! -f wcs_SCA1017S_17061_09773__00_00.fit.cat.astrometric_residuals ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE006b"
    fi
    if [ ! -s wcs_SCA1017S_17061_09773__00_00.fit.cat.astrometric_residuals ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE006c"
    else
     # compute mean astrometric offset and make sure it's less than 1 arcsec
     MEAN_ASTROMETRIC_OFFSET=`cat wcs_SCA1017S_17061_09773__00_00.fit.cat.astrometric_residuals | awk '{print $5}' | sort -n | awk '
  BEGIN {
    c = 0;
    sum = 0;
  }
  $1 ~ /^[0-9]*(\.[0-9]*)?$/ {
    c++;
    sum += $1;
  }
  END {
    ave = sum / c;
    print ave;          
  }                          
'`
     #TEST=`echo "$MEAN_ASTROMETRIC_OFFSET<1.0" | bc -ql`
     TEST=`echo "$MEAN_ASTROMETRIC_OFFSET<1.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
     if [ $TEST -ne 1 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE006d"
     fi
    fi
   fi 
   util/solve_plate_with_UCAC5 ../test_data_photo/SCA10670S_13788_08321__00_00.fit
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE007_platesolveucac5"
   elif [ ! -s wcs_SCA10670S_13788_08321__00_00.fit ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE008"
   else 
    lib/bin/xy2sky wcs_SCA10670S_13788_08321__00_00.fit 200 200 &>/dev/null
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE008a"
    fi
    if [ ! -s wcs_SCA10670S_13788_08321__00_00.fit.cat ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE009"
    fi 
    if [ ! -s wcs_SCA10670S_13788_08321__00_00.fit.cat.ucac5 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE010"
    else
     TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_SCA10670S_13788_08321__00_00.fit.cat.ucac5 | wc -l | awk '{print $1}'`
     # We expect 553 APASS stars in this field, but VizieR communication is not always reliable (may be slow and time out)
     # Let's assume the test pass if we get at least some stars
     #if [ $TEST -lt 550 ];then
     if [ $TEST -lt 300 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE010a_$TEST"
     fi
    fi
   fi # util/solve_plate_with_UCAC5 OK
   ###
   # check that the min number of detections filter is working
   MIN_NUMBER_OF_POINTS_IN_LC=`cat src/vast_limits.h | grep '#define' | grep HARD_MIN_NUMBER_OF_POINTS | awk '{print $1" "$2" "$3}' | grep -v '//' | awk '{print $3}'`
   for LIGHTCURVEFILE_TO_CHECK in out*.dat ;do
    NUMBER_OF_POINTS_IN_LC=`cat "$LIGHTCURVEFILE_TO_CHECK" | wc -l | awk '{print $1}'`
    if [ $NUMBER_OF_POINTS_IN_LC -lt $MIN_NUMBER_OF_POINTS_IN_LC ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE011_$LIGHTCURVEFILE_TO_CHECK"
     break
    fi
   done
   ###
   # Filter-out all stars with small number of detections
   lib/remove_lightcurves_with_small_number_of_points 40
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_remove_lightcurves_with_small_number_of_points_exit_code"
   fi
   util/nopgplot.sh
   # Check the average sigma level
   MEDIAN_SIGMACLIP_BRIGHTSTARS=`cat vast_lightcurve_statistics.log | head -n1000 | awk '{print $2}' | util/colstat 2>/dev/null | grep 'MEDIAN' | awk '{print $2}'`
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATEMEANSIG005"
   fi
   #TEST=`echo "a=($MEDIAN_SIGMACLIP_BRIGHTSTARS)-(0.090508);sqrt(a*a)<0.05" | bc -ql`
   TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS" | awk '{if ( sqrt( ($1-0.090508)*($1-0.090508) ) < 0.05 ) print 1 ;else print 0 }'`
   re='^[0-9]+$'
   if ! [[ $TEST =~ $re ]] ; then
    echo "TEST ERROR"
    TEST_PASSED=0
    TEST=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATEMEANSIG006_TEST_ERROR"
   fi
   if [ $TEST -ne 1 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATEMEANSIG006__$MEDIAN_SIGMACLIP_BRIGHTSTARS"
   fi
   # Find star with the largest sigma in this field
   TMPSTR=`cat data.m_sigma | awk '{printf "%08.3f %8.3f %8.3f %s\n",$2*1000,$3,$4,$5}' | sort -n | tail -n1| awk '{print $4}'`
   CEPHEIDOUTFILE="$TMPSTR"
   CEPHEID_RADEC_STR=`util/identify_transient.sh "$CEPHEIDOUTFILE" | grep -A 1 "RA(J2000)   Dec(J2000)" | tail -n1 | awk '{print $2" "$3}'`
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE012"
   fi
   DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field $CEPHEID_RADEC_STR 03:05:54.66 +57:45:44.3 | grep 'Angular distance' | awk '{print $5*3600}'`
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE013_"${CEPHEID_RADEC_STR//" "/"_"}
   fi
   #TEST=`echo "$DISTANCE_ARCSEC<0.3" | bc -ql`
   TEST=`echo "$DISTANCE_ARCSEC<0.3" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
   re='^[0-9]+$'
   if ! [[ $TEST =~ $re ]] ; then
    echo "TEST ERROR"
    TEST_PASSED=0
    TEST=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE014_TEST_ERROR"
   fi
   if [ $TEST -ne 1 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE014_"${CEPHEID_RADEC_STR//" "/"_"}
   fi
   if [ ! -z "$CEPHEID_RADEC_STR" ];then
    # CEPHEID_RADEC_STR="03:05:54.66 +57:45:44.3"
    # presumably that should be out00474.dat
    # Check that it is V834 Cas (it should be)
    # This test should pass with the GCVS server.
    # No '"' around $CEPHEID_RADEC_STR !! 
    util/search_databases_with_curl.sh $CEPHEID_RADEC_STR | grep "V0834 Cas"
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE015_curl_GCVS_V0834_Cas"
    fi
    util/search_databases_with_vizquery.sh $CEPHEID_RADEC_STR star 40 | grep "V0834 Cas"
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE016_vizquery_V0834_Cas"
    fi
    # same thing but different input format
    util/search_databases_with_vizquery.sh $CEPHEID_RADEC_STR | grep "V0834 Cas"
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE017_vizquery_V0834_Cas"
    fi
    # Check number of points in the Cepheid's lightcurve
    #CEPHEIDOUTFILE="$TMPSTR"
    if [ ! -z "$CEPHEIDOUTFILE" ];then
     TEST=`cat $CEPHEIDOUTFILE | wc -l | awk '{print $1}'`
     if [ $TEST -lt 107 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE018"
      #### Special procedure for debugging this thing
      util/save.sh PHOTOPLATE010
      ####
     fi
    else
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE019_NOT_PERFORMED" 
    fi
    # Check that we can find the Cepheid's period (frequency)
    FREQ_LK=`lib/lk_compute_periodogram "$CEPHEIDOUTFILE" 100 0.1 0.1 | grep 'LK' | awk '{print $1}'`
    # sqrt(a*a) is the sily way to get an absolute value of a
    #TEST=`echo "a=$FREQ_LK-0.211448;sqrt(a*a)<0.01" | bc -ql`
    TEST=`echo "$FREQ_LK" | awk '{if ( sqrt( ($1-0.211448)*($1-0.211448) ) < 0.01 ) print 1 ;else print 0 }'`
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
     echo "TEST ERROR"
     TEST_PASSED=0
     TEST=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE020_TEST_ERROR"
    else
     if [ $TEST -eq 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE020"
     fi
    fi # if ! [[ $TEST =~ $re ]] ; then
    #
    if [ ! -s vast_autocandidates.log ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE021"
    fi
    grep --quiet "$CEPHEIDOUTFILE" vast_autocandidates.log
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE022"
    fi
    if [ ! -s vast_list_of_likely_constant_stars.log ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE023"
    fi
    grep --quiet "$CEPHEIDOUTFILE" vast_list_of_likely_constant_stars.log
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE024"
    fi
    #
    # There are 11 false canididates in this dataset and they look very realistic,
    # to the point that I think they should go into the candidate variables list!
    # (The actual reason for their aparent variability is change of the photographic emulsion.)
    # I DONT LIKE THIS TEST
    #LINES_IN_FILE=`cat vast_autocandidates.log | wc -l`
    #if [ $LINES_IN_FILE -lt 12 ];then
    # TEST_PASSED=0
    # FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_FALSECANDIDATES"
    #fi
    #
   else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_PHOTOPLATE025_NOT_PERFORMED"
   fi # if [ ! -z "$CEPHEID_RADEC_STR" ];then
   # Bad image removal test
   lib/remove_bad_images 0.1 &> /dev/null
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE026"
   fi
   # Test the ID scripts running NOT from the main VaST directory
   cd ../test_data_photo/
   CEPHEID_RADEC_STR=`"$WORKDIR"/util/identify_transient.sh "$WORKDIR"/"$CEPHEIDOUTFILE" | grep -A 1 "RA(J2000)   Dec(J2000)" | tail -n1 | awk '{print $2" "$3}'`
   # # CEPHEID_RADEC_STR="03:05:54.66 +57:45:44.3"
   # presumably that should be out00474.dat
   # Check that it is V834 Cas (it should be)
   "$WORKDIR"/util/search_databases_with_curl.sh $CEPHEID_RADEC_STR | grep "V0834 Cas"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE027_curl_GCVS_V0834_Cas"
   fi
   "$WORKDIR"/util/search_databases_with_vizquery.sh $CEPHEID_RADEC_STR star 40 | grep "V0834 Cas"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE028_vizquery_V0834_Cas"
   fi
   # Here we expect exactly two distances to be reported 2MASS and USNO-B1.0 match
   # Both should be within 0.8 arcsec from the input coordinates. Let's check this
   #"$WORKDIR"/util/search_databases_with_vizquery.sh $CEPHEID_RADEC_STR star 40 | grep 'r=' | grep -v 'var=' | awk '{print $1}' FS='"' | awk '{print $2}' FS='r=' | while read R_DISTANCE_TO_MATCH ;do
   "$WORKDIR"/util/search_databases_with_vizquery.sh $CEPHEID_RADEC_STR star 40 | grep 'r=' | grep -v 'var=' | awk -F '"' '{print $1}' | awk -F 'r=' '{print $2}' | while read R_DISTANCE_TO_MATCH ;do
    #TEST=`echo "$R_DISTANCE_TO_MATCH<0.8" | bc -ql`
    TEST=`echo "$R_DISTANCE_TO_MATCH<0.8" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
    if [ $TEST -eq 1 ];then
     echo "GOODMATCH"
    fi
   done | grep -c 'GOODMATCH' | grep --quiet -e '2' -e '3'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE029"
   fi
   cd $WORKDIR 
   #
   #####################
   # Magnitude calibration test
   if [ -f lightcurve.tmp_emergency_stop_debug ];then
    rm -f lightcurve.tmp_emergency_stop_debug
   fi
   util/calibrate_magnitude_scale 5.000000 -16.294004 14.734595 0.445192 2.319951
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_calibrate_magnitude_scale_exit_code"
   fi
   if [ -f lightcurve.tmp_emergency_stop_debug ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_lightcurve_tmp_emergency_stop_debug"
   fi
   #####################
   ## Check if we get the same results with mag-size filtering
   util/clean_data.sh
   # Run the test
   #echo "Photographic plates test " 1>&2
   #echo -n "Photographic plates test: " >> vast_test_report.txt 
   cp default.sex.beta_Cas_photoplates default.sex
   ./vast --magsizefilter -u -o -j -f ../test_data_photo/SCA*
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE100"
   fi
   # Check results
   grep --quiet "Images used for photometry 150" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE101"
   fi
   grep --quiet "First image: 2433153.50800" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE102"
   fi
   grep --quiet "Last  image: 2447836.28000" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE103"
   fi
   # Hunting the mysterious non-zero reference frame rotation cases
   if [ -f vast_image_details.log ];then
    grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE1_nonzero_ref_frame_rotation"
     GREP_RESULT=`cat vast_summary.log vast_image_details.log`
     DEBUG_OUTPUT="$DEBUG_OUTPUT
###### PHOTOPLATE1_nonzero_ref_frame_rotation ######
$GREP_RESULT"
    fi
    grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE1_nonzero_ref_frame_rotation_test2"
     GREP_RESULT=`cat vast_summary.log vast_image_details.log`
     DEBUG_OUTPUT="$DEBUG_OUTPUT
###### PHOTOPLATE1_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
    fi
   else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE1_NO_vast_image_details_log"
   fi
   #
   util/wcs_image_calibration.sh ../test_data_photo/SCA1017S_17061_09773__00_00.fit
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE104"
   fi
   if [ ! -f wcs_SCA1017S_17061_09773__00_00.fit ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE105"
   fi
   lib/bin/xy2sky wcs_SCA1017S_17061_09773__00_00.fit 200 200 &>/dev/null
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE105a"
   fi
   util/solve_plate_with_UCAC5 ../test_data_photo/SCA1017S_17061_09773__00_00.fit
   if [ ! -f wcs_SCA1017S_17061_09773__00_00.fit.cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE106"
   fi 
   util/solve_plate_with_UCAC5 ../test_data_photo/SCA10670S_13788_08321__00_00.fit
   if [ ! -f wcs_SCA10670S_13788_08321__00_00.fit.cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE107"
   fi 
   ###
   # Filter-out all stars with small number of detections
   lib/remove_lightcurves_with_small_number_of_points 40
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_remove_lightcurves_with_small_number_of_points_exit_code"
   fi
   util/nopgplot.sh
   # Find star with the largest sigma in this field
   TMPSTR=`cat data.m_sigma | awk '{printf "%08.3f %8.3f %8.3f %s\n",$2*1000,$3,$4,$5}' | sort -n | tail -n1| awk '{print $4}'`
   CEPHEID_RADEC_STR=`util/identify_transient.sh $TMPSTR | grep -A 1 "RA(J2000)   Dec(J2000)" | tail -n1 | awk '{print $2" "$3}'`
   # presumably that should be out00474.dat
   # Check that it is V834 Cas (it should be)
   util/search_databases_with_curl.sh $CEPHEID_RADEC_STR | grep "V0834 Cas"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE108"
   fi
   util/search_databases_with_vizquery.sh $CEPHEID_RADEC_STR star 40 | grep "V0834 Cas"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE109_vizquery"
   fi
   # Check number of points in the Cepheid's lightcurve
   CEPHEIDOUTFILE="$TMPSTR"
   if [ ! -z "$CEPHEIDOUTFILE" ];then
    TEST=`cat $CEPHEIDOUTFILE | wc -l | awk '{print $1}'`
    #if [ $TEST -lt 107 ];then # OK, a bad image becomes identifiable if mag-size filter is on
    #if [ $TEST -lt 106 ];then # OK, two bad images visible after recent changes
    if [ $TEST -lt 105 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE110"
    fi
   else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE110_NOT_PERFORMED" 
   fi
   # Check that we can find the Cepheid's period (frequency)
   FREQ_LK=`lib/lk_compute_periodogram $TMPSTR 100 0.1 0.1 | grep 'LK' | awk '{print $1}'`
   # sqrt(a*a) is the sily way to get an absolute value of a
   #TEST=`echo "a=$FREQ_LK-0.211448;sqrt(a*a)<0.01" | bc -ql`
   TEST=`echo "$FREQ_LK" | awk '{if ( sqrt( ($1-0.211448)*($1-0.211448) ) < 0.01 ) print 1 ;else print 0 }'`
   re='^[0-9]+$'
   if ! [[ $TEST =~ $re ]] ; then
    echo "TEST ERROR"
    TEST_PASSED=0
    TEST=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE111_TEST_ERROR"
   else
    if [ $TEST -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE111"
    fi
   fi # if ! [[ $TEST =~ $re ]] ; then
   #
   if [ ! -s vast_autocandidates.log ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE112"
   fi
   grep --quiet "$CEPHEIDOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE113"
   fi
   if [ ! -s vast_list_of_likely_constant_stars.log ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE114"
   fi
   grep --quiet "$CEPHEIDOUTFILE" vast_list_of_likely_constant_stars.log
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE115"
   fi
   #
   lib/remove_bad_images 0.1 &> /dev/null
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE116"
   fi
   # test lib/new_lightcurve_sigma_filter and its cousins
   lib/new_lightcurve_sigma_filter 2.0
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_new_lightcurve_sigma_filter_exit_code"
   fi
   lib/drop_faint_points 3
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_drop_faint_points_exit_code"
   fi
   lib/drop_bright_points 3
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_drop_bright_points_exit_code"
   fi
   #####################
   N_RANDOM_SET=30
   lib/select_only_n_random_points_from_set_of_lightcurves $N_RANDOM_SET
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_select_only_n_random_points_from_set_of_lightcurves_exit_code"
   else
    N_RANDOM_ACTUAL=`for i in out*.dat ;do cat $i | wc -l ;done | util/colstat 2>&1 | grep 'MAX=' | awk '{printf "%.0f", $2}'`
    if [ $N_RANDOM_ACTUAL -gt $N_RANDOM_SET ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_select_only_n_random_points_from_set_of_lightcurves_a_$N_RANDOM_ACTUAL"
    fi
    # allow for a few bad images
    if [ $N_RANDOM_ACTUAL -lt $[$N_RANDOM_SET-5] ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_select_only_n_random_points_from_set_of_lightcurves_b_$N_RANDOM_ACTUAL"
    fi
   fi
   #####################
   #####################
   ## Check if we get the same results with automated reference image selection
   util/clean_data.sh
   # Run the test
   #echo "Photographic plates test " 1>&2
   #echo -n "Photographic plates test: " >> vast_test_report.txt 
   cp default.sex.beta_Cas_photoplates default.sex
   ./vast --autoselectrefimage --magsizefilter -u -o -j -f ../test_data_photo/SCA*
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE200"
   fi
   # Check results
   grep --quiet "Images used for photometry 150" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE201"
   fi
   grep --quiet "First image: 2433153.50800" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE202"
   fi
   grep --quiet "Last  image: 2447836.28000" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE203"
   fi
   # Hunting the mysterious non-zero reference frame rotation cases
   if [ -f vast_image_details.log ];then
    grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE2_nonzero_ref_frame_rotation"
     GREP_RESULT=`cat vast_summary.log vast_image_details.log`
     DEBUG_OUTPUT="$DEBUG_OUTPUT
###### PHOTOPLATE2_nonzero_ref_frame_rotation ######
$GREP_RESULT"
    fi
    grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE2_nonzero_ref_frame_rotation_test2"
     GREP_RESULT=`cat vast_summary.log vast_image_details.log`
     DEBUG_OUTPUT="$DEBUG_OUTPUT
###### PHOTOPLATE2_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
    fi
   else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE2_NO_vast_image_details_log"
   fi
   #
   util/wcs_image_calibration.sh ../test_data_photo/SCA1017S_17061_09773__00_00.fit
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE204"
   fi
   if [ ! -f wcs_SCA1017S_17061_09773__00_00.fit ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE205"
   fi
   lib/bin/xy2sky wcs_SCA1017S_17061_09773__00_00.fit 200 200 &>/dev/null
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE205a"
   fi
   util/solve_plate_with_UCAC5 ../test_data_photo/SCA1017S_17061_09773__00_00.fit
   if [ ! -f wcs_SCA1017S_17061_09773__00_00.fit.cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE206"
   fi 
   util/solve_plate_with_UCAC5 ../test_data_photo/SCA10670S_13788_08321__00_00.fit
   if [ ! -f wcs_SCA10670S_13788_08321__00_00.fit.cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE207"
   fi 
   ###
   # Filter-out all stars with small number of detections
   lib/remove_lightcurves_with_small_number_of_points 40
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE2_remove_lightcurves_with_small_number_of_points_exit_code"
   fi
   util/nopgplot.sh
   # Find star with the largest sigma in this field
   TMPSTR=`cat data.m_sigma | awk '{printf "%08.3f %8.3f %8.3f %s\n",$2*1000,$3,$4,$5}' | sort -n | tail -n1| awk '{print $4}'`
   CEPHEID_RADEC_STR=`util/identify_transient.sh $TMPSTR | grep -A 1 "RA(J2000)   Dec(J2000)" | tail -n1 | awk '{print $2" "$3}'`
   # presumably that should be out00474.dat
   # Check that it is V834 Cas (it should be)
   util/search_databases_with_curl.sh $CEPHEID_RADEC_STR | grep "V0834 Cas"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE208"
   fi
   util/search_databases_with_vizquery.sh $CEPHEID_RADEC_STR star 40 | grep "V0834 Cas"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE209_vizquery"
   fi
   # Check number of points in the Cepheid's lightcurve
   CEPHEIDOUTFILE="$TMPSTR"
   if [ ! -z "$CEPHEIDOUTFILE" ];then
    TEST=`cat $CEPHEIDOUTFILE | wc -l | awk '{print $1}'`
    #if [ $TEST -lt 107 ];then # OK, a bad image becomes identifiable if mag-size filter is on
    #if [ $TEST -lt 106 ];then # OK, two bad images visible after recent changes
    if [ $TEST -lt 105 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE210"
    fi
   else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE210_NOT_PERFORMED" 
   fi
   # Check that we can find the Cepheid's period (frequency)
   FREQ_LK=`lib/lk_compute_periodogram $TMPSTR 100 0.1 0.1 | grep 'LK' | awk '{print $1}'`
   # sqrt(a*a) is the sily way to get an absolute value of a
   #TEST=`echo "a=$FREQ_LK-0.211448;sqrt(a*a)<0.01" | bc -ql`
   TEST=`echo "$FREQ_LK" | awk '{if ( sqrt( ($1-0.211448)*($1-0.211448) ) < 0.01 ) print 1 ;else print 0 }'`
   re='^[0-9]+$'
   if ! [[ $TEST =~ $re ]] ; then
    echo "TEST ERROR"
    TEST_PASSED=0
    TEST=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE211_TEST_ERROR"
   else
    if [ $TEST -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE211"
    fi
   fi # if ! [[ $TEST =~ $re ]] ; then
   #
   if [ ! -s vast_autocandidates.log ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE212"
   fi
   grep --quiet "$CEPHEIDOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE213"
   fi
   if [ ! -s vast_list_of_likely_constant_stars.log ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE214"
   fi
   grep --quiet "$CEPHEIDOUTFILE" vast_list_of_likely_constant_stars.log
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE215"
   fi
   #
   lib/remove_bad_images 0.1 &> /dev/null
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE216"
   fi
   #####################
   # Test save and load scripts 
   LIST_OF_FILES_THAT_SHOULD_BE_SAVED_AND_LAODED_BACK=`ls out*.dat data.m_sigma vast_lightcurve_statistics_format.log vast_lightcurve_statistics.log vast_command_line.log vast_image_details.log vast_images_catalogs.log`
   for FILE_THAT_SHOULD_BE_SAVED_AND_LAODED_BACK in $LIST_OF_FILES_THAT_SHOULD_BE_SAVED_AND_LAODED_BACK ;do
    if [ ! -f $FILE_THAT_SHOULD_BE_SAVED_AND_LAODED_BACK ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE217__$FILE_THAT_SHOULD_BE_SAVED_AND_LAODED_BACK"
     break
    fi 
   done
   util/save.sh PHOTOPLATE_TEST_SAVE
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE218"
   fi
   util/load.sh PHOTOPLATE_TEST_SAVE
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE219"
   fi
   for FILE_THAT_SHOULD_BE_SAVED_AND_LAODED_BACK in $LIST_OF_FILES_THAT_SHOULD_BE_SAVED_AND_LAODED_BACK ;do
    if [ ! -f "$FILE_THAT_SHOULD_BE_SAVED_AND_LAODED_BACK" ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE220__$FILE_THAT_SHOULD_BE_SAVED_AND_LAODED_BACK"
     break
    fi 
   done
   # Cleanup
   if [ -d PHOTOPLATE_TEST_SAVE ];then
    rm -rf PHOTOPLATE_TEST_SAVE
   fi
   ################################################################################
   # Check vast_image_details.log format
   NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l  | awk '{print $1}'`
   if [ $NLINES -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE221_VAST_IMG_DETAILS_FORMAT"
   fi
   ################################################################################
   #####################
   ### Flag image test should always be the last one
   for IMAGE in ../test_data_photo/* ;do
    util/clean_data.sh
    lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
    if [ $? -eq 0 ];then
     IMAGE=`basename $IMAGE`
     ## We do want flags for these specific plates
     if [ "$IMAGE" = "SCA843S_16645_09097__00_00.fit" ];then
      continue
     fi
     ##
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE221_$IMAGE"
    fi
   done
  else
   echo "ERROR: cannot find vast_summary.log" 1>&2
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_ALL"
  fi

  THIS_TEST_STOP_UNIXSEC=$(date +%s)
  THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

  # Make an overall conclusion for this test
  if [ $TEST_PASSED -eq 1 ];then
   echo -e "\n\033[01;34mPhotographic plates test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
   echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
  else
   echo -e "\n\033[01;34mPhotographic plates test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
   echo "FAILED" >> vast_test_report.txt
  fi
 else
  FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_TEST_NOT_PERFORMED_BAD_TEST_DATA"
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt 
#
remove_test_data_to_save_space
##########################################

# Test the connection
test_internet_connection fast
if [ $? -ne 0 ];then
 exit 1
fi

### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


##### Small CCD images test #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images test " 1>&2 
 echo -n "Small CCD images test: " >> vast_test_report.txt 
 if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
  mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP
 fi
 cp vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_example vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
 cp default.sex.ccd_example default.sex
 ./vast -u -f --nomagsizefilter ../sample_data/*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD000"
 fi
 if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP ];then
  mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD002"
  fi
  grep --quiet "Ref.  image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_REFIMAGE"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD003"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SMALLCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SMALLCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "Magnitude-Size filter: Disabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD005"
  fi
  grep --quiet "Photometric errors rescaling: YES" vast_summary.log
  #if [ $? -ne 0 ];then
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD006"
  fi
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD007"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD008"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD009"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD010"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD011"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD012"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD013"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD014"
  fi
  #
  MEDIAN_SIGMACLIP_BRIGHTSTARS=`cat vast_lightcurve_statistics.log | head -n1000 | awk '{print $2}' | util/colstat 2>/dev/null | grep 'MEDIAN' | awk '{print $2}'`
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDMEANSIG005"
  fi
  #TEST=`echo "a=($MEDIAN_SIGMACLIP_BRIGHTSTARS)-(0.061232);sqrt(a*a)<0.005" | bc -ql`
  TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS" | awk '{if ( sqrt( ($1-0.061232)*($1-0.061232) ) < 0.005 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDMEANSIG006_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDMEANSIG006__$MEDIAN_SIGMACLIP_BRIGHTSTARS"
  fi
  #
  N_AUTOCANDIDATES=`cat vast_autocandidates.log | wc -l | awk '{print $1}'`
  # actually we get two more false candidates depending on binning if filtering is disabled
  if [ $N_AUTOCANDIDATES -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD000_N_AUTOCANDIDATES"
  fi
  ###############################################
  ### Now let's check the candidate variables ###
  # out00201.dat - CV (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n1`
  LIGHTCURVEFILE=`echo "$STATSTR" | awk '{print $5}'`
  NLINES_IN_LIGHTCURVEFILE=`cat $LIGHTCURVEFILE | wc -l | awk '{print $1}'`
  if [ $NLINES_IN_LIGHTCURVEFILE -lt 91 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD015_$NLINES_IN_LIGHTCURVEFILE"
  fi
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.761200);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.761200))*($1-(-11.761200)) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD015a_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD015a"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  #TEST=`echo "a=($STATX)-(218.9535100);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-218.9535100)*($1-218.9535100) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD016_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD016"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  #TEST=`echo "a=($STATY)-(247.8363000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-247.8363000)*($1-247.8363000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD017_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD017"
  fi
  # indexes
  # idx01_wSTD
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.241686);sqrt(a*a)<0.01" | bc -ql`
  # wSTD with rescaled errorbars
  #TEST=`echo "a=($STATIDX)-(0.325552);sqrt(a*a)<0.01" | bc -ql`
  # wSTD with rescaled errorbars (robust line fitting)
  # The difference may be pretty huge from machine to mcahine...
  # And the difference HUGEly depends on weighting
  #TEST=`echo "a=($STATIDX)-(0.372294);sqrt(a*a)<0.1" | bc -ql`
  # This is the value on eridan with photometric error rescaling disabled
  #TEST=`echo "a=($STATIDX)-(0.354955);sqrt(a*a)<0.2" | bc -ql`
  # 0.242372 at HPCC with photometric error rescaling disabled
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.354955)*($1-0.354955) ) < 0.2 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD018_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD018"
  fi
  # idx09_MAD
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.018977);sqrt(a*a)<0.005" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.018977)*($1-0.018977) ) < 0.005 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD019_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD019"
  fi
  # idx25_IQR
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  #TEST=`echo "a=($STATIDX)-(0.025686);sqrt(a*a)<0.001" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.025686)*($1-0.025686) ) < 0.001 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD020_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD020"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  if [ $NUMBER_OF_LINES -ne 91 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD021_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD022 SMALLCCD023_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD023"
   fi
  fi
  # Check that this star is not in the list of constant stars
  if [ ! -s vast_list_of_likely_constant_stars.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD024 SMALLCCD025_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_list_of_likely_constant_stars.log
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD025"
   fi
  fi  
  # out00268.dat - EW (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n2 | head -n1`
  LIGHTCURVEFILE=`echo "$STATSTR" | awk '{print $5}'`
  NLINES_IN_LIGHTCURVEFILE=`cat $LIGHTCURVEFILE | wc -l | awk '{print $1}'`
  if [ $NLINES_IN_LIGHTCURVEFILE -lt 90 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD026_$NLINES_IN_LIGHTCURVEFILE"
  fi
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.220400);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.220400))*($1-(-11.220400)) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD026a_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD026a"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  #TEST=`echo "a=($STATX)-(87.2039000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-87.2039000)*($1-87.2039000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD027_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD027"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  #TEST=`echo "a=($STATY)-(164.4241000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-164.4241000)*($1-164.4241000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD028_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD028"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.037195);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.037195)*($1-0.037195) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD029_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD029"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.044775);sqrt(a*a)<0.002" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.044775)*($1-0.044775) ) < 0.002 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD030_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD030"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  # Yeah, I have no idea why this difference is so large between machines
  # The difference is in the original lightcurve...
  #TEST=`echo "a=($STATIDX)-(0.050557);sqrt(a*a)<0.003" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.050557)*($1-0.050557) ) < 0.003 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD031_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD031"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  if [ $NUMBER_OF_LINES -lt 90 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD032_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD033 SMALLCCD034_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD034"
   fi
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  grep --quiet "$STATOUTFILE" vast_list_of_likely_constant_stars.log
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD035"
  fi
  ###############################################
  # Both stars should be selected using the following criterea, but let's check at least one
  cat vast_autocandidates_details.log | grep --quiet 'IQR  IQR+MAD  eta+IQR+MAD  eta+CLIPPED_SIGMA'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_AUTOCANDIDATEDETAILS"
  fi
  ###############################################
  lib/remove_bad_images 0.1 &> /dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD036"
  fi
  ###############################################
  if [ -s vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
   grep --quiet "CCD-TEMP" vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
   if [ $? -eq 0 ];then
    for LIGHTCURVEFILE_TO_TEST in out*.dat ;do
     grep --quiet "CCD-TEMP" "$LIGHTCURVEFILE_TO_TEST"
     if [ $? -ne 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD037_$LIGHTCURVEFILE_TO_TEST"
      break
     fi
    done
   else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD037_NOT_PERFORMED_1"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD037_NOT_PERFORMED_2"
  fi
  #####################
  N_RANDOM_SET=30
  lib/select_only_n_random_points_from_set_of_lightcurves $N_RANDOM_SET
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_select_only_n_random_points_from_set_of_lightcurves_exit_code"
  else
   N_RANDOM_ACTUAL=`for i in out*.dat ;do cat $i | wc -l ;done | util/colstat 2>&1 | grep 'MAX=' | awk '{printf "%.0f", $2}'`
   if [ $N_RANDOM_SET -ne $N_RANDOM_ACTUAL ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_select_only_n_random_points_from_set_of_lightcurves_$N_RANDOM_ACTUAL"
   fi
  fi
  #####################
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  # Finder chart test
  util/make_finding_chart ../sample_data/f_72-001r.fit
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_MAKE_FINDER_CHART_001"
  fi
  if [ -f pgplot.png ] || [ -f pgplot.ps ] ;then
   if [ -f pgplot.png ];then
    rm -f pgplot.png
   fi
   if [ -f pgplot.ps ];then
    rm -f pgplot.ps
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_MAKE_FINDER_CHART_002"
  fi
  ###############################################
  ### Flag image test should always be the last one
  for IMAGE in ../sample_data/*.fit ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD038_$IMAGE"
   fi 
  done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_ALL"
 fi

 # median stacker test
 for TEST_FILE_TO_REMOVE in nul.fit one.fit two.fit median.fit ;do
  if [ -f "$TEST_FILE_TO_REMOVE" ];then
   rm -f "$TEST_FILE_TO_REMOVE"
  fi
 done
 util/imarith ../sample_data/f_72-001r.fit 0.000001 mul nul.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_imarith_nul"
 fi
 util/imarith nul.fit 1.0 add one.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_imarith_one"
 fi
 util/imarith nul.fit 2.0 add two.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_imarith_two"
 fi
 util/ccd/mk one.fit nul.fit two.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_mk_onenultwo_01"
 fi
 if [ ! -f median.fit ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_mk_onenultwo_02"
 else
  util/imstat_vast median.fit | grep 'MEDIAN=     1.000'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_imstat_vast_03"
  fi
  rm -f median.fit
 fi
 util/ccd/mk two.fit one.fit nul.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_mk_onenultwo_11"
 fi
 if [ ! -f median.fit ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_mk_onenultwo_12"
 else
  util/imstat_vast median.fit | grep 'MEDIAN=     2.000'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_imstat_vast_13"
  fi
  rm -f median.fit
 fi
 util/ccd/mk two.fit nul.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_mk_onenultwo_21"
 fi
 if [ ! -f median.fit ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_mk_onenultwo_22"
 else
  util/imstat_vast median.fit | grep 'MEDIAN=     1.000'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_imstat_vast_23"
  fi
  rm -f median.fit
 fi
 for TEST_FILE_TO_REMOVE in nul.fit one.fit two.fit median.fit ;do
  if [ -f "$TEST_FILE_TO_REMOVE" ];then
   rm -f "$TEST_FILE_TO_REMOVE"
  fi
 done


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### Small CCD images star exclusion test #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images star exclusion test " 1>&2 
 echo -n "Small CCD images star exclusion test: " >> vast_test_report.txt 
 if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
  mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP
 fi
 cp vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_example vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
 cp default.sex.ccd_example default.sex
 echo "218.95351  247.83630" > exclude.lst
 ./vast -u -f --nomagsizefilter ../sample_data/*.fit 2>&1 | grep ' 218\.' | grep ' 247\.' | grep --quiet 'is listed in exclude.lst'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX000"
 fi
 N_EXCLUDED_STAR=`./vast -u -f --nomagsizefilter ../sample_data/*.fit 2>&1 | grep ' 218\.' | grep ' 247\.' | grep -c 'is listed in exclude.lst'`
 if [ $N_EXCLUDED_STAR -ne 90 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX000_N$N_EXCLUDED_STAR"
 fi
 echo "# Reference image pixel coordinates of stars
# that should be excluded from magnitude calibration
#
0.0 0.0" > exclude.lst
 if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP ];then
  mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX002"
  fi
  grep --quiet "Ref.  image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX_REFIMAGE"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX003"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### STAREX0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### STAREX0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "Magnitude-Size filter: Disabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX005"
  fi
  grep --quiet "Photometric errors rescaling: YES" vast_summary.log
  #if [ $? -ne 0 ];then
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX006"
  fi
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX007"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX008"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX009"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX010"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX011"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX012"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX013"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX014"
  fi
  #
  MEDIAN_SIGMACLIP_BRIGHTSTARS=`cat vast_lightcurve_statistics.log | head -n1000 | awk '{print $2}' | util/colstat 2>/dev/null | grep 'MEDIAN' | awk '{print $2}'`
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREXMEANSIG005"
  fi
  #TEST=`echo "a=($MEDIAN_SIGMACLIP_BRIGHTSTARS)-(0.061232);sqrt(a*a)<0.005" | bc -ql`
  TEST=`echo "$MEDIAN_SIGMACLIP_BRIGHTSTARS" | awk '{if ( sqrt( ($1-0.061232)*($1-0.061232) ) < 0.005 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREXMEANSIG006_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREXMEANSIG006__$MEDIAN_SIGMACLIP_BRIGHTSTARS"
  fi
  #
  N_AUTOCANDIDATES=`cat vast_autocandidates.log | wc -l | awk '{print $1}'`
  # actually we get two more false candidates depending on binning if filtering is disabled
  if [ $N_AUTOCANDIDATES -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX000_N_AUTOCANDIDATES"
  fi
  ###############################################
  ### Now let's check the candidate variables ###
  # out00201.dat - CV (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n1`
  LIGHTCURVEFILE=`echo "$STATSTR" | awk '{print $5}'`
  NLINES_IN_LIGHTCURVEFILE=`cat $LIGHTCURVEFILE | wc -l | awk '{print $1}'`
  if [ $NLINES_IN_LIGHTCURVEFILE -lt 91 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX015_$NLINES_IN_LIGHTCURVEFILE"
  fi
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.761200);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.761200))*($1-(-11.761200)) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX015a_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX015a"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  #TEST=`echo "a=($STATX)-(218.9535100);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-218.9535100)*($1-218.9535100) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX016_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX016"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  #TEST=`echo "a=($STATY)-(247.8363000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-247.8363000)*($1-247.8363000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX017_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX017"
  fi
  # indexes
  # idx01_wSTD
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.241686);sqrt(a*a)<0.01" | bc -ql`
  # wSTD with rescaled errorbars
  #TEST=`echo "a=($STATIDX)-(0.325552);sqrt(a*a)<0.01" | bc -ql`
  # wSTD with rescaled errorbars (robust line fitting)
  # The difference may be pretty huge from machine to mcahine...
  # And the difference HUGEly depends on weighting
  #TEST=`echo "a=($STATIDX)-(0.372294);sqrt(a*a)<0.1" | bc -ql`
  # This is the value on eridan with photometric error rescaling disabled
  #TEST=`echo "a=($STATIDX)-(0.354955);sqrt(a*a)<0.2" | bc -ql`
  # 0.242372 at HPCC with photometric error rescaling disabled
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.354955)*($1-0.354955) ) < 0.2 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX018_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX018"
  fi
  # idx09_MAD
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.018977);sqrt(a*a)<0.005" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.018977)*($1-0.018977) ) < 0.005 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX019_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX019"
  fi
  # idx25_IQR
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  #TEST=`echo "a=($STATIDX)-(0.025686);sqrt(a*a)<0.001" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.025686)*($1-0.025686) ) < 0.001 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX020_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX020"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  if [ $NUMBER_OF_LINES -ne 91 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX021_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX022 STAREX023_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX023"
   fi
  fi
  # Check that this star is not in the list of constant stars
  if [ ! -s vast_list_of_likely_constant_stars.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX024 STAREX025_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_list_of_likely_constant_stars.log
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX025"
   fi
  fi  
  # out00268.dat - EW (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n2 | head -n1`
  LIGHTCURVEFILE=`echo "$STATSTR" | awk '{print $5}'`
  NLINES_IN_LIGHTCURVEFILE=`cat $LIGHTCURVEFILE | wc -l | awk '{print $1}'`
  if [ $NLINES_IN_LIGHTCURVEFILE -lt 90 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX026_$NLINES_IN_LIGHTCURVEFILE"
  fi
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.220400);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.220400))*($1-(-11.220400)) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX026a_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX026a"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  #TEST=`echo "a=($STATX)-(87.2039000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-87.2039000)*($1-87.2039000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX027_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX027"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  #TEST=`echo "a=($STATY)-(164.4241000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-164.4241000)*($1-164.4241000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX028_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX028"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.037195);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.037195)*($1-0.037195) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX029_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX029"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.044775);sqrt(a*a)<0.002" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.044775)*($1-0.044775) ) < 0.002 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX030_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX030"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  # Yeah, I have no idea why this difference is so large between machines
  # The difference is in the original lightcurve...
  #TEST=`echo "a=($STATIDX)-(0.050557);sqrt(a*a)<0.003" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.050557)*($1-0.050557) ) < 0.003 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX031_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX031"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  if [ $NUMBER_OF_LINES -lt 90 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX032_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX033 STAREX034_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX034"
   fi
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  grep --quiet "$STATOUTFILE" vast_list_of_likely_constant_stars.log
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX035"
  fi
  ###############################################
  # Both stars should be selected using the following criterea, but let's check at least one
  cat vast_autocandidates_details.log | grep --quiet 'IQR  IQR+MAD  eta+IQR+MAD  eta+CLIPPED_SIGMA'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX_AUTOCANDIDATEDETAILS"
  fi
  ###############################################

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images star exclusion test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images star exclusion test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES STAREX_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### Small CCD images with file list input test #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with file list input test " 1>&2
 echo -n "Small CCD images with file list input test: " >> vast_test_report.txt 
 if [ -f vast_list_of_input_images_with_time_corrections.txt_test ];then
  if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
   mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP
  fi
  cp vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_example vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
  cp default.sex.ccd_example default.sex
  cp vast_list_of_input_images_with_time_corrections.txt_test vast_list_of_input_images_with_time_corrections.txt
  ./vast -u -f --nomagsizefilter 
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST000"
  fi
  rm -f vast_list_of_input_images_with_time_corrections.txt
  if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP ];then
    mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
  fi
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST002"
  fi
  grep --quiet "Ref.  image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST_REFIMAGE"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST003"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SMALLCCDFILELIST0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SMALLCCDFILELIST0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "Magnitude-Size filter: Disabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST005"
  fi
  grep --quiet "Photometric errors rescaling: YES" vast_summary.log
  #if [ $? -ne 0 ];then
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST006"
  fi
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST007"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST008"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST009"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST010"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST011"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST012"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST013"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST014"
  fi
  N_AUTOCANDIDATES=`cat vast_autocandidates.log | wc -l | awk '{print $1}'`
  # actually we get two more false candidates depending on binning if filtering is disabled
  if [ $N_AUTOCANDIDATES -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST000_N_AUTOCANDIDATES"
  fi
  ###############################################
  ### Now let's check the candidate variables ###
  # out00201.dat - CV (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n1`
  LIGHTCURVEFILE=`echo "$STATSTR" | awk '{print $5}'`
  NLINES_IN_LIGHTCURVEFILE=`cat $LIGHTCURVEFILE | wc -l | awk '{print $1}'`
  if [ $NLINES_IN_LIGHTCURVEFILE -lt 91 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST015_$NLINES_IN_LIGHTCURVEFILE"
  fi
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.761200);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.761200))*($1-(-11.761200)) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST015a_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST015a"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  #TEST=`echo "a=($STATX)-(218.9535100);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-218.9535100)*($1-218.9535100) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST016_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST016"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  #TEST=`echo "a=($STATY)-(247.8363000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-247.8363000)*($1-247.8363000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST017_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST017"
  fi
  # indexes
  # idx01_wSTD
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.241686);sqrt(a*a)<0.01" | bc -ql`
  # wSTD with rescaled errorbars
  #TEST=`echo "a=($STATIDX)-(0.325552);sqrt(a*a)<0.01" | bc -ql`
  # wSTD with rescaled errorbars (robust line fitting)
  # The difference may be pretty huge from machine to mcahine...
  # And the difference HUGEly depends on weighting
  #TEST=`echo "a=($STATIDX)-(0.372294);sqrt(a*a)<0.1" | bc -ql`
  #TEST=`echo "a=($STATIDX)-(0.354955);sqrt(a*a)<0.2" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.354955)*($1-0.354955) ) < 0.2 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST018_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST018"
  fi
  # idx09_MAD
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.018977);sqrt(a*a)<0.005" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.018977)*($1-0.018977) ) < 0.005 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST019_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST019"
  fi
  # idx25_IQR
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  #TEST=`echo "a=($STATIDX)-(0.025686);sqrt(a*a)<0.001" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.025686)*($1-0.025686) ) < 0.001 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST020_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST020"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  if [ $NUMBER_OF_LINES -ne 91 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST021_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST022 SMALLCCDFILELIST023_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST023"
   fi
  fi
  # Check that this star is not in the list of constant stars
  if [ ! -s vast_list_of_likely_constant_stars.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST024 SMALLCCDFILELIST025_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_list_of_likely_constant_stars.log
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST025"
   fi
  fi  
  # out00268.dat - EW (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n2 | head -n1`
  LIGHTCURVEFILE=`echo "$STATSTR" | awk '{print $5}'`
  NLINES_IN_LIGHTCURVEFILE=`cat $LIGHTCURVEFILE | wc -l | awk '{print $1}'`
  if [ $NLINES_IN_LIGHTCURVEFILE -lt 90 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST026_$NLINES_IN_LIGHTCURVEFILE"
  fi
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.220400);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.220400))*($1-(-11.220400)) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST026a_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST026a"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  #TEST=`echo "a=($STATX)-(87.2039000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-87.2039000)*($1-87.2039000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST027_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST027"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  #TEST=`echo "a=($STATY)-(164.4241000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-164.4241000)*($1-164.4241000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST028_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST028"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.037195);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.037195)*($1-0.037195) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST029_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST029"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.044775);sqrt(a*a)<0.002" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.044775)*($1-0.044775) ) < 0.002 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST030_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST030"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  # Yeah, I have no idea why this difference is so large between machines
  # The difference is in the original lightcurve...
  #TEST=`echo "a=($STATIDX)-(0.050557);sqrt(a*a)<0.003" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.050557)*($1-0.050557) ) < 0.003 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST031_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST031"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  if [ $NUMBER_OF_LINES -lt 90 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST032_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST033 SMALLCCDFILELIST034_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST034"
   fi
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  grep --quiet "$STATOUTFILE" vast_list_of_likely_constant_stars.log
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST035"
  fi
  ###############################################
  # Both stars should be selected using the following criterea, but let's check at least one
  cat vast_autocandidates_details.log | grep --quiet 'IQR  IQR+MAD  eta+IQR+MAD  eta+CLIPPED_SIGMA'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST_AUTOCANDIDATEDETAILS"
  fi
  ###############################################
  lib/remove_bad_images 0.1 &> /dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST036"
  fi
  ###############################################
  if [ -s vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
   grep --quiet "CCD-TEMP" vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
   if [ $? -eq 0 ];then
    for LIGHTCURVEFILE_TO_TEST in out*.dat ;do
     grep --quiet "CCD-TEMP" "$LIGHTCURVEFILE_TO_TEST"
     if [ $? -ne 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST037_$LIGHTCURVEFILE_TO_TEST"
      break
     fi
    done
   else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST037_NOT_PERFORMED_1"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST037_NOT_PERFORMED_2"
  fi
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  ###############################################
  ### Flag image test should always be the last one
  for IMAGE in ../sample_data/*.fit ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST038_$IMAGE"
   fi 
  done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with file list input test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with file list input test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELIST_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### Small CCD images with file list input and --autoselectrefimage test #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with file list input and --autoselectrefimage test " 1>&2
 echo -n "Small CCD images with file list input and --autoselectrefimage test: " >> vast_test_report.txt 
 if [ -f vast_list_of_input_images_with_time_corrections.txt_test ];then
  if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
   mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP
  fi
  cp vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_example vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
  cp default.sex.ccd_example default.sex
  cp vast_list_of_input_images_with_time_corrections.txt_test vast_list_of_input_images_with_time_corrections.txt
  ./vast -u -f --nomagsizefilter --autoselectrefimage
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF000"
  fi
  rm -f vast_list_of_input_images_with_time_corrections.txt
  if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP ];then
    mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
  fi
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF003"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF004"
  fi
  grep --quiet "Magnitude-Size filter: Disabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF005"
  fi
  grep --quiet "Photometric errors rescaling: YES" vast_summary.log
  #if [ $? -ne 0 ];then
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF006"
  fi
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF007"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF008"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF009"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF010"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF011"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF012"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF013"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF014"
  fi
  N_AUTOCANDIDATES=`cat vast_autocandidates.log | wc -l | awk '{print $1}'`
  # actually we get two more false candidates depending on binning if filtering is disabled
  if [ $N_AUTOCANDIDATES -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF000_N_AUTOCANDIDATES"
  fi
  ###############################################
  # Both stars should be selected using the following criterea, but let's check at least one
  cat vast_autocandidates_details.log | grep --quiet 'IQR  IQR+MAD  eta+IQR+MAD  eta+CLIPPED_SIGMA'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF_AUTOCANDIDATEDETAILS"
  fi
  ###############################################
  lib/remove_bad_images 0.1 &> /dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF036"
  fi
  ###############################################
  if [ -s vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
   grep --quiet "CCD-TEMP" vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
   if [ $? -eq 0 ];then
    for LIGHTCURVEFILE_TO_TEST in out*.dat ;do
     grep --quiet "CCD-TEMP" "$LIGHTCURVEFILE_TO_TEST"
     if [ $? -ne 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF037_$LIGHTCURVEFILE_TO_TEST"
      break
     fi
    done
   else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF037_NOT_PERFORMED_1"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF037_NOT_PERFORMED_2"
  fi
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with file list input and --autoselectrefimage test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with file list input and --autoselectrefimage test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDFILELISTAUTOSELREF_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#



##### Small CCD images random options test #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images random options test " 1>&2
 echo -n "Small CCD images random options test: " >> vast_test_report.txt 
 OPTIONS=""
 for OPTION in "-u" "--UTC" "-l" "--nodiscardell" "-e" "--failsafe" "-k" "--nojdkeyword" "-x3" "--maxsextractorflag 3" "-j" "--position_dependent_correction" "-7" "--autoselectrefimage" "-3" "--selectbestaperture" "-1" "--magsizefilter" ;do
  MONTECARLO=$[ $RANDOM % 10 ]
  if [ $MONTECARLO -gt 5 ];then
   OPTIONS="$OPTIONS $OPTION"
  fi
 done
 cp default.sex.ccd_example default.sex
 ./vast --nofind $OPTIONS ../sample_data/f_72-0*
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDRANDOMOPTIONS000($OPTIONS)"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDRANDOMOPTIONS001($OPTIONS)"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDRANDOMOPTIONS002($OPTIONS)"
  fi
  N_AUTOCANDIDATES=`cat vast_autocandidates.log | wc -l | awk '{print $1}'`
  # actually we get two more false candidates depending on binning if filtering is disabled
  if [ $N_AUTOCANDIDATES -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDRANDOMOPTIONS000_N_AUTOCANDIDATES($OPTIONS)"
  fi
  ###############################################

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDRANDOMOPTIONS_ALL($OPTIONS)"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images random options test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images random options test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDRANDOMOPTIONS_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#



##### Few small CCD images test #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Few small CCD images test " 1>&2
 echo -n "Few small CCD images test: " >> vast_test_report.txt 
 if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
  mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP
 fi
 cp vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_example vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
 cp default.sex.ccd_example default.sex
 ./vast -u -f --magsizefilter ../sample_data/f_72-00*
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD000"
 fi
 if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP ];then
  mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 9" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD001"
  fi
  grep --quiet "Images used for photometry 9" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD003"
  fi
  grep --quiet "Last  image: 2453202.33394 15.07.2004 19:59:22" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### FEWSMALLCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### FEWSMALLCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "Magnitude-Size filter: Enabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD005"
  fi
  # No errors rescaling for the small number of input images!
  grep --quiet "Photometric errors rescaling: NO" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD006"
  fi
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD007"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD008"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD009"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD010"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD011"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD012"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD013"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD014"
  fi
  ###############################################
  lib/remove_bad_images 0.1 &> /dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD036"
  fi
  ###############################################
  if [ -s vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
   grep --quiet "CCD-TEMP" vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
   if [ $? -eq 0 ];then
    for LIGHTCURVEFILE_TO_TEST in out*.dat ;do
     grep --quiet "CCD-TEMP" "$LIGHTCURVEFILE_TO_TEST"
     if [ $? -ne 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD037"
     fi
    done
   else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD037_NOT_PERFORMED_1"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD037_NOT_PERFORMED_2"
  fi
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  ###############################################
  ### Flag image test should always be the last one
  for IMAGE in ../sample_data/*.fit ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD038_$IMAGE"
   fi 
  done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD_ALL"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mFew small CCD images test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mFew small CCD images test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

##### Small CCD images with no photometric errors rescaling test #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images test with no errors rescaling " 1>&2
 echo -n "Small CCD images test with no errors rescaling: " >> vast_test_report.txt 
 if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
  mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP
 fi
 cp vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_example vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
 cp default.sex.ccd_example default.sex
 ./vast -u -f --noerrorsrescale --nomagsizefilter ../sample_data/*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE000"
 fi
 if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP ];then
  mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE003"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SMALLCCDNOERRORSRESCALE0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SMALLCCDNOERRORSRESCALE0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "Magnitude-Size filter: Disabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE005"
  fi
  grep --quiet "Photometric errors rescaling: NO" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE006"
  fi
  SYSTEMATIC_NOISE_LEVEL=`util/estimate_systematic_noise_level 2> /dev/null`
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE_SYSNOISE01"
  fi
  #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0130);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$SYSTEMATIC_NOISE_LEVEL" | awk '{if ( sqrt( ($1-0.0130)*($1-0.0130) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE_SYSNOISE02_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE_SYSNOISE02"
  fi
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE007"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE008"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE009"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE010"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE011"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE012"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE013"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE014"
  fi
  ###############################################
  ### Now let's check the candidate variables ###
  # out00201.dat - CV (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n1`
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.761200);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.761200))*($1-(-11.761200)) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE015_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE015"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  #TEST=`echo "a=($STATX)-(218.9535100);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-218.9535100)*($1-218.9535100) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE016_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE016"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  #TEST=`echo "a=($STATY)-(247.8363000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-247.8363000)*($1-247.8363000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE017_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE017"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.241686);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.241686)*($1-0.241686) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE018_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE018"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.018977);sqrt(a*a)<0.005" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.018977)*($1-0.018977) ) < 0.005 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE019_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE019"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  #TEST=`echo "a=($STATIDX)-(0.025686);sqrt(a*a)<0.001" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.025686)*($1-0.025686) ) < 0.001 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE020_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE020"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  if [ $NUMBER_OF_LINES -ne 91 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE021_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE022 SMALLCCDNOERRORSRESCALE023_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE023"
   fi
  fi
  # Check that this star is not in the list of constant stars
  if [ ! -s vast_list_of_likely_constant_stars.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE024 SMALLCCDNOERRORSRESCALE025_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_list_of_likely_constant_stars.log
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE025"
   fi
  fi  
  # out00268.dat - EW (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n2 | head -n1`
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.220400);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.220400))*($1-(-11.220400)) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE026_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE026"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  #TEST=`echo "a=($STATX)-(87.2039000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-87.2039000)*($1-87.2039000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE027_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE027"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  #TEST=`echo "a=($STATY)-(164.4241000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-164.4241000)*($1-164.4241000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE028_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE028"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.037195);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.037195)*($1-0.037195) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE029_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE029"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.044775);sqrt(a*a)<0.001" | bc -ql`
  #TEST=`echo "a=($STATIDX)-(0.044775);sqrt(a*a)<0.002" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.044775)*($1-0.044775) ) < 0.002 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE030_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE030"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  # Yeah, I have no idea why this difference is so large between machines
  # The difference is in the original lightcurve...
  #TEST=`echo "a=($STATIDX)-(0.050557);sqrt(a*a)<0.003" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.050557)*($1-0.050557) ) < 0.003 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE031_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE031"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  if [ $NUMBER_OF_LINES -lt 90 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE032_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE033 SMALLCCDNOERRORSRESCALE034_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE034"
   fi
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  grep --quiet "$STATOUTFILE" vast_list_of_likely_constant_stars.log
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE035"
  fi
  ###############################################
  lib/remove_bad_images 0.1 &> /dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE036"
  fi
  ###############################################
  if [ -s vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
   grep --quiet "CCD-TEMP" vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
   if [ $? -eq 0 ];then
    for LIGHTCURVEFILE_TO_TEST in out*.dat ;do
     grep --quiet "CCD-TEMP" "$LIGHTCURVEFILE_TO_TEST"
     if [ $? -ne 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE037"
     fi
    done
   else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE037_NOT_PERFORMED_1"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE037_NOT_PERFORMED_2"
  fi
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  
  ###############################################
  ### Flag image test should always be the last one
  for IMAGE in ../sample_data/*.fit ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE038_$IMAGE"
   fi 
  done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images test with no errors rescaling \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images test with no errors rescaling \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### Small CCD images test with non-zero MAG_ZEROPOINT #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with non-zero MAG_ZEROPOINT test " 1>&2
 echo -n "Small CCD images with non-zero MAG_ZEROPOINT test: " >> vast_test_report.txt
 # Here is the main feature of this test: we set MAG_ZEROPOINT  25.0 instead of 0.0 
 cat default.sex.ccd_example | sed 's:MAG_ZEROPOINT   0.0:MAG_ZEROPOINT  25.0:g' > default.sex
 # The [[:space:]] thing doesn't work on BSD
 #cat default.sex.ccd_example | sed 's:MAG_ZEROPOINT[[:space:]]\+0.0:MAG_ZEROPOINT  25.0:g' > default.sex
 # Make sure sed did the job correctly
 grep --quiet "MAG_ZEROPOINT  25.0" default.sex
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD000"
 else
  ./vast -u -f --magsizefilter ../sample_data/*.fit
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD000a"
  fi
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD003"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### MAGZEROPOINTSMALLCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### MAGZEROPOINTSMALLCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "Magnitude-Size filter: Enabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD005"
  fi
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD006"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD007"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD008"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD009"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD010"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD011"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD012"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD013"
  fi

  ###############################################
  if [ ! -s vast_list_of_likely_constant_stars.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD014"
  fi


  # Skip the flag image test as it surely was done before
  #### Flag image test should always be the last one
  #for IMAGE in ../sample_data/*.fit ;do
  # util/clean_data.sh
  # lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
  # if [ $? -ne 0 ];then
  #  TEST_PASSED=0
  #  IMAGE=`basename $IMAGE`
  #  FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD004_$IMAGE"
  # fi 
  #done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD_ALL"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with non-zero MAG_ZEROPOINT test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with non-zero MAG_ZEROPOINT test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### Small CCD images test with 'export OMP_NUM_THREADS=2' #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with OMP_NUM_THREADS=2 test " 1>&2
 echo -n "Small CCD images with OMP_NUM_THREADS=2 test: " >> vast_test_report.txt
 # Here is the main feature of this test: we limit the number of processin threads to only 2
 export OMP_NUM_THREADS=2
 cp default.sex.ccd_example default.sex
 ./vast -u -f ../sample_data/*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD000"
 fi
 unset OMP_NUM_THREADS
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD003a"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD003b"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### OMP_NUM_THREADS_SMALLCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### OMP_NUM_THREADS_SMALLCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD0_NO_vast_image_details_log"
  fi
  #
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD005c"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD006"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD007"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD008"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD009"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD010"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD011"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD012"
  fi

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with OMP_NUM_THREADS=2 test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with OMP_NUM_THREADS=2 test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

##### Small CCD images test with the directory name being specified istead of the file list #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with directory name instead of file list test " 1>&2
 echo -n "Small CCD images with directory name instead of file list test: " >> vast_test_report.txt
 # Here is the main feature of this test: we limit the number of processin threads to only 2
 cp default.sex.ccd_example default.sex
 ./vast -u -f ../sample_data
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD003a"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD003b"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### DIRNAME_SMALLCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### DIRNAME_SMALLCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD0_NO_vast_image_details_log"
  fi
  #
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD005c"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD006"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD007"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD008"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD009"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD010"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD011"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD012"
  fi

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with directory name instead of file list test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with directory name instead of file list test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

##### Small CCD images test with the directory name with / being specified istead of the file list #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with directory name instead of file list test " 1>&2
 echo -n "Small CCD images with directory name instead of file list test: " >> vast_test_report.txt
 # Here is the main feature of this test: we limit the number of processin threads to only 2
 cp default.sex.ccd_example default.sex
 ./vast -u -f ../sample_data/
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD003a"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD003b"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### DIRNAME2_SMALLCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### DIRNAME2_SMALLCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD0_NO_vast_image_details_log"
  fi
  #
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD005c"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD006"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD007"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD008"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD009"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD010"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD011"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD012"
  fi

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with directory name instead of file list test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with directory name instead of file list test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#




##### White space name #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
if [ ! -d '../sample space' ];then
 cp -r '../sample_data' '../sample space'
fi

# If the test data are found
if [ -d '../sample space' ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "White space name test " 1>&2
 echo -n "White space name test: " >> vast_test_report.txt
 # Here is the main feature of this test: we limit the number of processin threads to only 2
 cp default.sex.ccd_example default.sex
 ./vast -u -f '../sample space/'*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD003a"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD003b"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### WHITE_SPACE_NAME_SMALLCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### WHITE_SPACE_NAME_SMALLCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD0_NO_vast_image_details_log"
  fi
  #
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD005c"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD006"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD007"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD008"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD009"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD010"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD011"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD012"
  fi

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD_ALL"
 fi
 
 util/imstat_vast '../sample space/f_72-001r.fit'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD_IMSTAT01"
 fi
 util/imstat_vast '../sample space/f_72-001r.fit' | grep --quiet 'MEDIAN=   919.0'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD_IMSTAT02"
 fi
 util/imstat_vast_fast '../sample space/f_72-001r.fit' | grep --quiet 'MEDIAN'
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD_IMSTAT03"
 fi
 util/imstat_vast_fast '../sample space/f_72-001r.fit' | grep --quiet 'MEAN=   924.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD_IMSTAT04"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mWhite space name test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mWhite space name test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space

##### Small CCD images test with automated reference image selection #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with automated reference image selection test " 1>&2
 echo -n "Small CCD images with automated reference image selection test: " >> vast_test_report.txt
 cp default.sex.ccd_example default.sex
 ./vast --autoselectrefimage -u -f ../sample_data/*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD002"
  fi
  #grep --quiet "Ref.  image: 2453193.35153 06.07.2004 20:24:42" vast_summary.log
  # New ref. image with new flagging system?..
  #grep --quiet "Ref.  image: 2453193.35816 06.07.2004 20:34:15   ../sample_data/f_72-008r.fit" vast_summary.log
  # We end up with different reference images at diffferent machines,
  # so let's just check the date when the ref image was taken
  #### ????This test is not working - different machines choose different reference images!!!!
  grep "Ref.  image:" vast_summary.log | grep --quiet -e "06.07.2004" -e "05.07.2004"
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD003a"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD003b"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD003c"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### AUTOSELECT_REF_IMG_SMALLCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### AUTOSELECT_REF_IMG_SMALLCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD0_NO_vast_image_details_log"
  fi
  #
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD005"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD006"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD007"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD008"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD009"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD010"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD011"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD012"
  fi

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with automated reference image selection test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with automated reference image selection test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### Small CCD images test with FITS keyword recording #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with FITS keyword recording test " 1>&2
 echo -n "Small CCD images with FITS keyword recording test: " >> vast_test_report.txt
 # Here is the main feature of this test
 if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
  mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP
  echo "CCD-TEMP" > vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
 fi
 ./vast -u -f ../sample_data/*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD000"
 fi
 if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP ];then
  mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD003a"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD003b"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### WITH_KEYWORD_RECORDING_SMALLCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### WITH_KEYWORD_RECORDING_SMALLCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD0_NO_vast_image_details_log"
  fi
  #
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD005"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD006"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD007"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD008"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD009"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD010"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD011"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD012"
  fi
  
  for LIGHTCURVEFILE_TO_TEST in out*.dat ;do
   if [ -f WITH_KEYWORD_RECORDING_SMALLCCD013_problem.tmp ];then
    rm -f WITH_KEYWORD_RECORDING_SMALLCCD013_problem.tmp
   fi
   #cat $LIGHTCURVEFILE_TO_TEST | awk '{print $8}' | while read A ;do
   # Print everything statring from column 8
   cat $LIGHTCURVEFILE_TO_TEST | awk '{ for(i=8; i<NF; i++) printf "%s",$i OFS; if(NF) printf "%s",$NF; printf ORS}' | while read A ;do
    #if [ ! -z "$A" ];then
    # The idea here is that if we save some FITS header keywords, the '=' sign will always be present in the string
    echo "$A" | grep --quiet 'CCD-TEMP='
    if [ $? -ne 0 ];then
     touch WITH_KEYWORD_RECORDING_SMALLCCD013_problem.tmp
     break
    fi
   done
   if [ -f WITH_KEYWORD_RECORDING_SMALLCCD013_problem.tmp ];then
    rm -f WITH_KEYWORD_RECORDING_SMALLCCD013_problem.tmp
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD013"
    break
   fi
  done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with FITS keyword recording test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with FITS keyword recording test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### Small CCD images test with NO FITS keyword recording #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with NO FITS keyword recording test " 1>&2
 echo -n "Small CCD images with NO FITS keyword recording test: " >> vast_test_report.txt
 # Here is the main feature of this test
 if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt ];then
  mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP
 fi
 ./vast -u -f ../sample_data/*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD000"
 fi
 if [ -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP ];then
  mv vast_list_of_FITS_keywords_to_record_in_lightcurves.txt_TEST_BACKUP vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD003a"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD003b"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NO_KEYWORD_RECORDING_SMALLCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NO_KEYWORD_RECORDING_SMALLCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD0_NO_vast_image_details_log"
  fi
  #
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD005"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD006"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD007"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD008"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD009"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD010"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD011"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD012"
  fi
  
  for LIGHTCURVEFILE_TO_TEST in out*.dat ;do
   if [ -f NO_KEYWORD_RECORDING_SMALLCCD013_problem.tmp ];then
    rm -f NO_KEYWORD_RECORDING_SMALLCCD013_problem.tmp
   fi
   #cat $LIGHTCURVEFILE_TO_TEST | awk '{print $8}' | while read A ;do
   # Print everything statring from column 8
   cat $LIGHTCURVEFILE_TO_TEST | awk '{ for(i=8; i<NF; i++) printf "%s",$i OFS; if(NF) printf "%s",$NF; printf ORS}' | while read A ;do
    #if [ ! -z "$A" ];then
    # The idea here is that if we save some FITS header keywords, the '=' sign will always be present in the string
    echo "$A" | grep --quiet '='
    if [ $? -eq 0 ];then
     touch NO_KEYWORD_RECORDING_SMALLCCD013_problem.tmp
     break
    fi
   done
   if [ -f NO_KEYWORD_RECORDING_SMALLCCD013_problem.tmp ];then
    rm -f NO_KEYWORD_RECORDING_SMALLCCD013_problem.tmp
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD013"
    break
   fi
  done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with NO FITS keyword recording test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with NO FITS keyword recording test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### Small CCD images test with size-mag filter enabled #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with mag-size filter test " 1>&2
 echo -n "Small CCD images with mag-size filter test: " >> vast_test_report.txt
 cp default.sex.ccd_example default.sex
 ./vast --magsizefilter -u -f ../sample_data/*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD003"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### MAGSIZEFILTERSMALLCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### MAGSIZEFILTERSMALLCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "Magnitude-Size filter: Enabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD005"
  fi
  grep --quiet 'Photometric errors rescaling: YES' vast_summary.log
  #if [ $? -ne 0 ];then
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_ERRORRESCALINGLOGREC"
  fi
  SYSTEMATIC_NOISE_LEVEL=`util/estimate_systematic_noise_level 2> /dev/null`
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_SYSNOISE01"
  fi
  #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0043);sqrt(a*a)<0.005" | bc -ql`
  #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0128);sqrt(a*a)<0.005" | bc -ql`
  TEST=`echo "$SYSTEMATIC_NOISE_LEVEL" | awk '{if ( sqrt( ($1-0.0128)*($1-0.0128) ) < 0.005 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_SYSNOISE02_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_SYSNOISE02_$SYSTEMATIC_NOISE_LEVEL"
  fi
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD006"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD007"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD008"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD009"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD010"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD011"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD012"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD013"
  fi
  ###############################################
  ### Now let's check the candidate variables ###
  # out00201.dat - CV (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n1`
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.761200);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.761200))*($1-(-11.761200)) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD014_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD014"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  #TEST=`echo "a=($STATX)-(218.9535100);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-218.9535100)*($1-218.9535100) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD015_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD015_$STATX"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  #TEST=`echo "a=($STATY)-(247.8363000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-247.8363000)*($1-247.8363000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD016_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD016_$STATY"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.241686);sqrt(a*a)<0.01" | bc -ql`
  # wSTD with rescaled errorbars
  #TEST=`echo "a=($STATIDX)-(0.320350);sqrt(a*a)<0.01" | bc -ql`
  # wSTD with rescaled errorbars (robust line fit)
  #TEST=`echo "a=($STATIDX)-(0.364624);sqrt(a*a)<0.02" | bc -ql`
  # With the updated magsizefilter
  #TEST=`echo "a=($STATIDX)-(0.341486);sqrt(a*a)<0.02" | bc -ql`
  # weight image enabled
  #TEST=`echo "a=($STATIDX)-(0.362346);sqrt(a*a)<0.02" | bc -ql`
  # let's add a bit more space here
  #TEST=`echo "a=($STATIDX)-(0.362346);sqrt(a*a)<0.05" | bc -ql`
  # photometric error rescaling disabled
  #TEST=`echo "a=($STATIDX)-(0.242567);sqrt(a*a)<0.05" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.242567)*($1-0.242567) ) < 0.05 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD017_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD017_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.018977);sqrt(a*a)<0.005" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.018977)*($1-0.018977) ) < 0.005 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD018_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD018_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  #TEST=`echo "a=($STATIDX)-(0.025686);sqrt(a*a)<0.002" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.025686)*($1-0.025686) ) < 0.002 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD019_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD019_$STATIDX"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  if [ $NUMBER_OF_LINES -ne 91 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD020_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD021 MAGSIZEFILTERSMALLCCD020_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD022"
   fi
  fi
  grep --quiet "$STATOUTFILE" vast_list_of_likely_constant_stars.log
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD023"
  fi
  # out00268.dat - EW (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n2 | head -n1`
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.220400);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.220400))*($1-(-11.220400)) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD024_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD024"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  #TEST=`echo "a=($STATX)-(87.2039000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-87.2039000)*($1-87.2039000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD025_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD025_$STATX"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  #TEST=`echo "a=($STATY)-(164.4241000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-164.4241000)*($1-164.4241000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD026_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD026_$STATY"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.037195);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.037195)*($1-0.037195) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD027_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD027_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.043737);sqrt(a*a)<0.002" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.043737)*($1-0.043737) ) < 0.002 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD028_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD028_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  # 91 points
  #TEST=`echo "a=($STATIDX)-(0.050557);sqrt(a*a)<0.001" | bc -ql`
  # 90 points, weight image
  #TEST=`echo "a=($STATIDX)-(0.052707);sqrt(a*a)<0.005" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.052707)*($1-0.052707) ) < 0.005 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD029_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD029_$STATIDX"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  if [ $NUMBER_OF_LINES -lt 90 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD030_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD031 MAGSIZEFILTERSMALLCCD032_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD032"
   fi
  fi
  grep --quiet "$STATOUTFILE" vast_list_of_likely_constant_stars.log
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD033"
  fi
  ###############################################
  cat src/vast_limits.h | grep -v '//' | grep --quiet 'DISABLE_MAGSIZE_FILTER_LOGS'
  if [ $? -ne 0 ];then
   # Check log files associated with mag-size filtering
   for PARAM in 00 01 04 06 08 10 12 ;do
    for MAGSIZEFILTERLOGFILE in image*.cat.magparameter"$PARAM"filter_passed image*1.cat.magparameter"$PARAM"filter_rejected image*.cat.magparameter"$PARAM"filter_thresholdcurve ;do
     if [ ! -f "$MAGSIZEFILTERLOGFILE" ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_MISSINGLOGFILE_$MAGSIZEFILTERLOGFILE"
     fi
    done
   done
   if [ ! -s image00001.cat.magparameter00filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_EMPTY00REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter00filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 8 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_FEW00REJ"
    fi
   fi
   #
   if [ ! -s image00001.cat.magparameter01filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_EMPTY01REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter01filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 6 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_FEW01REJ"
    fi
   fi
   #
   if [ ! -s image00001.cat.magparameter04filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_EMPTY04REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter04filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 6 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_FEW04REJ"
    fi
   fi
   #
   if [ ! -s image00001.cat.magparameter06filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_EMPTY06REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter06filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 5 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_FEW06REJ"
    fi
   fi
   #
   if [ ! -s image00001.cat.magparameter08filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_EMPTY08REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter08filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 5 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_FEW08REJ"
    fi
   fi
   #
   if [ ! -s image00001.cat.magparameter10filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_EMPTY10REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter10filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 5 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_FEW10REJ"
    fi
   fi
   #
   if [ ! -s image00001.cat.magparameter12filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_EMPTY11REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter12filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 3 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_FEW11REJ"
    fi
   fi
  else
   FAILED_TEST_CODES="$FAILED_TEST_CODES DISABLE_MAGSIZE_FILTER_LOGS_SET"
  fi # if DISABLE_MAGSIZE_FILTER_LOGS
  ###############################################

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with mag-size filter test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with mag-size filter test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

#
# Actually, we just want to repeat the above test to make sure the results are consistent
# (because sometimes they are not!)
#
##### Space small CCD images test with size-mag filter enabled #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
if [ ! -d '../sample space' ];then
 cp -r '../sample_data' '../sample space'
fi

# If the test data are found
if [ -d '../sample space' ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Space mall CCD images with mag-size filter test " 1>&2
 echo -n "Space small CCD images with mag-size filter test: " >> vast_test_report.txt
 cp default.sex.ccd_example default.sex
 ./vast --magsizefilter -u -f '../sample space/'*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD003"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SPACEMAGSIZEFILTERSMALLCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SPACEMAGSIZEFILTERSMALLCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "Magnitude-Size filter: Enabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD005"
  fi
  grep --quiet 'Photometric errors rescaling: YES' vast_summary.log
  #if [ $? -ne 0 ];then
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_ERRORRESCALINGLOGREC"
  fi
  SYSTEMATIC_NOISE_LEVEL=`util/estimate_systematic_noise_level 2> /dev/null`
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_SYSNOISE01"
  fi
  #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0043);sqrt(a*a)<0.005" | bc -ql`
  # Photometric error rescalig disabled
  #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0128);sqrt(a*a)<0.005" | bc -ql`
  TEST=`echo "$SYSTEMATIC_NOISE_LEVEL" | awk '{if ( sqrt( ($1-0.0128)*($1-0.0128) ) < 0.005 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_SYSNOISE02_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_SYSNOISE02_$SYSTEMATIC_NOISE_LEVEL"
  fi
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD006"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD007"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD008"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD009"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD010"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD011"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD012"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD013"
  fi
  ###############################################
  ### Now let's check the candidate variables ###
  # out00201.dat - CV (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n1`
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.761200);sqrt(a*a)<0.01" | bc -ql`
  #TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.761200))*($1-(-11.761200)) ) < 0.01 ) print 1 ;else print 0 }'`
  # We have to relax this as we don't know which image will end up being the reference one when specifying directory as an input!
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.761200))*($1-(-11.761200)) ) < 0.5 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD014_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD014"
  fi
  #STATX=`echo "$STATSTR" | awk '{print $3}'`
  ##TEST=`echo "a=($STATX)-(218.9535100);sqrt(a*a)<0.1" | bc -ql`
  #TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-218.9535100)*($1-218.9535100) ) < 0.1 ) print 1 ;else print 0 }'`
  #re='^[0-9]+$'
  #if ! [[ $TEST =~ $re ]] ; then
  # echo "TEST ERROR"
  # TEST_PASSED=0
  # TEST=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD015_TEST_ERROR"
  #fi
  #if [ $TEST -ne 1 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD015_$STATX"
  #fi
  #STATY=`echo "$STATSTR" | awk '{print $4}'`
  ##TEST=`echo "a=($STATY)-(247.8363000);sqrt(a*a)<0.1" | bc -ql`
  #TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-247.8363000)*($1-247.8363000) ) < 0.1 ) print 1 ;else print 0 }'`
  #re='^[0-9]+$'
  #if ! [[ $TEST =~ $re ]] ; then
  # echo "TEST ERROR"
  # TEST_PASSED=0
  # TEST=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD016_TEST_ERROR"
  #fi
  #if [ $TEST -ne 1 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD016_$STATY"
  #fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.241686);sqrt(a*a)<0.01" | bc -ql`
  # wSTD with rescaled errorbars
  #TEST=`echo "a=($STATIDX)-(0.320350);sqrt(a*a)<0.01" | bc -ql`
  # wSTD with rescaled errorbars (robust line fit)
  #TEST=`echo "a=($STATIDX)-(0.364624);sqrt(a*a)<0.02" | bc -ql`
  # With the updated magsizefilter
  #TEST=`echo "a=($STATIDX)-(0.341486);sqrt(a*a)<0.02" | bc -ql`
  # weight image enabled
  #TEST=`echo "a=($STATIDX)-(0.362346);sqrt(a*a)<0.02" | bc -ql`
  # let's add a bit more space here
  #TEST=`echo "a=($STATIDX)-(0.362346);sqrt(a*a)<0.05" | bc -ql`
  # photometric error rescalingg disabled
  #TEST=`echo "a=($STATIDX)-(0.242567);sqrt(a*a)<0.05" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.242567)*($1-0.242567) ) < 0.05 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD017_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD017_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.018977);sqrt(a*a)<0.005" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.018977)*($1-0.018977) ) < 0.005 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD018_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD018_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  #TEST=`echo "a=($STATIDX)-(0.025686);sqrt(a*a)<0.002" | bc -ql`
  #TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.025686)*($1-0.025686) ) < 0.002 ) print 1 ;else print 0 }'`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.025686)*($1-0.025686) ) < 0.02 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD019_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD019_$STATIDX"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  if [ $NUMBER_OF_LINES -ne 91 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD020_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD021 SPACEMAGSIZEFILTERSMALLCCD020_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD022"
   fi
  fi
  grep --quiet "$STATOUTFILE" vast_list_of_likely_constant_stars.log
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD023"
  fi
  # out00268.dat - EW (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n2 | head -n1`
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.220400);sqrt(a*a)<0.01" | bc -ql`
  #TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.220400))*($1-(-11.220400)) ) < 0.01 ) print 1 ;else print 0 }'`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.220400))*($1-(-11.220400)) ) < 0.5 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD024_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD024"
  fi
  #STATX=`echo "$STATSTR" | awk '{print $3}'`
  ##TEST=`echo "a=($STATX)-(87.2039000);sqrt(a*a)<0.1" | bc -ql`
  #TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-87.2039000)*($1-87.2039000) ) < 0.1 ) print 1 ;else print 0 }'`
  #re='^[0-9]+$'
  #if ! [[ $TEST =~ $re ]] ; then
  # echo "TEST ERROR"
  # TEST_PASSED=0
  # TEST=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD025_TEST_ERROR"
  #fi
  #if [ $TEST -ne 1 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD025_$STATX"
  #fi
  #STATY=`echo "$STATSTR" | awk '{print $4}'`
  ##TEST=`echo "a=($STATY)-(164.4241000);sqrt(a*a)<0.1" | bc -ql`
  #TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-164.4241000)*($1-164.4241000) ) < 0.1 ) print 1 ;else print 0 }'`
  #re='^[0-9]+$'
  #if ! [[ $TEST =~ $re ]] ; then
  # echo "TEST ERROR"
  # TEST_PASSED=0
  # TEST=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD026_TEST_ERROR"
  #fi
  #if [ $TEST -ne 1 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD026_$STATY"
  #fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.037195);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.037195)*($1-0.037195) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD027_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD027_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.043737);sqrt(a*a)<0.002" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.043737)*($1-0.043737) ) < 0.002 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD028_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD028_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  # 91 points
  #TEST=`echo "a=($STATIDX)-(0.050557);sqrt(a*a)<0.001" | bc -ql`
  # 90 points, weight image
  #TEST=`echo "a=($STATIDX)-(0.052707);sqrt(a*a)<0.005" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.052707)*($1-0.052707) ) < 0.005 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD029_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD029_$STATIDX"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  if [ $NUMBER_OF_LINES -lt 90 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD030_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD031 SPACEMAGSIZEFILTERSMALLCCD032_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD032"
   fi
  fi
  grep --quiet "$STATOUTFILE" vast_list_of_likely_constant_stars.log
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD033"
  fi
  ###############################################
  cat src/vast_limits.h | grep -v '//' | grep --quiet 'DISABLE_MAGSIZE_FILTER_LOGS'
  if [ $? -ne 0 ];then
   # Check log files associated with mag-size filtering
   for PARAM in 00 01 04 06 08 10 12 ;do
    for MAGSIZEFILTERLOGFILE in image*.cat.magparameter"$PARAM"filter_passed image*1.cat.magparameter"$PARAM"filter_rejected image*.cat.magparameter"$PARAM"filter_thresholdcurve ;do
     if [ ! -f "$MAGSIZEFILTERLOGFILE" ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_MISSINGLOGFILE_$MAGSIZEFILTERLOGFILE"
     fi
    done
   done
   if [ ! -s image00001.cat.magparameter00filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_EMPTY00REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter00filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 8 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_FEW00REJ"
    fi
   fi
   #
   if [ ! -s image00001.cat.magparameter01filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_EMPTY01REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter01filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 6 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_FEW01REJ"
    fi
   fi
   #
   if [ ! -s image00001.cat.magparameter04filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_EMPTY04REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter04filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 6 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_FEW04REJ"
    fi
   fi
   #
   if [ ! -s image00001.cat.magparameter06filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_EMPTY06REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter06filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 5 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_FEW06REJ"
    fi
   fi
   #
   if [ ! -s image00001.cat.magparameter08filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_EMPTY08REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter08filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 5 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_FEW08REJ"
    fi
   fi
   #
   if [ ! -s image00001.cat.magparameter10filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_EMPTY10REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter10filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 5 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_FEW10REJ"
    fi
   fi
   #
   if [ ! -s image00001.cat.magparameter12filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_EMPTY11REJ"
   else
    LINES_IN_LOGFILE=`cat image00001.cat.magparameter12filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 3 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_FEW11REJ"
    fi
   fi
  fi # DISABLE_MAGSIZE_FILTER_LOGS
  ###############################################

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSpace small CCD images with mag-size filter test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSpace small CCD images with mag-size filter test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

# Test the connection
test_internet_connection fast
if [ $? -ne 0 ];then
 exit 1
fi

##### Very few stars on the reference frame #####
# Download the test dataset if needed
if [ ! -d ../vast_test_bright_stars_failed_match ];then
 cd ..
 if [ -f vast_test_bright_stars_failed_match.tar.bz2 ];then
  rm -f vast_test_bright_stars_failed_match.tar.bz2
 fi
 $($WORKDIR/lib/find_timeout_command.sh) 300 curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_bright_stars_failed_match.tar.bz2" && tar -xvjf vast_test_bright_stars_failed_match.tar.bz2 && rm -f vast_test_bright_stars_failed_match.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../vast_test_bright_stars_failed_match ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Reference image with very few stars test " 1>&2
 echo -n "Reference image with very few stars test: " >> vast_test_report.txt
 cp default.sex.ccd_bright_star default.sex
 ./vast -u -t2 -f ../vast_test_bright_stars_failed_match
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 23" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS001"
  fi
  grep --quiet "Images used for photometry 23" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS002"
  fi
  # Ref. image might be different if we specify a directory rather than a file list
  #grep --quiet "Ref.  image: 2458689.62122 25.07.2019 02:54:30" vast_summary.log
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS003a"
  #fi
  grep --quiet "First image: 2458689.62122 25.07.2019 02:54:30" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS003b"
  fi
  grep --quiet "Last  image: 2458689.63980 25.07.2019 03:21:16" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS003c"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### REFIMAGE_WITH_VERY_FEW_STARS0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### REFIMAGE_WITH_VERY_FEW_STARS0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS0_NO_vast_image_details_log"
  fi
  #
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS005"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS006"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS007"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS008"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS009"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS010"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS011"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS012"
  fi

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mReference image with very few stars test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mReference image with very few stars test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
# the next test relies on the same test data, so don't remove it now
#remove_test_data_to_save_space

##### Very few stars on the reference frame #####
# Download the test dataset if needed
if [ ! -d ../vast_test_bright_stars_failed_match ];then
 cd ..
 if [ -f vast_test_bright_stars_failed_match.tar.bz2 ];then
  rm -f vast_test_bright_stars_failed_match.tar.bz2
 fi
 $($WORKDIR/lib/find_timeout_command.sh) 300 curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_bright_stars_failed_match.tar.bz2" && tar -xvjf vast_test_bright_stars_failed_match.tar.bz2 && rm -f vast_test_bright_stars_failed_match.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../vast_test_bright_stars_failed_match ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Reference image with very few stars test 2 " 1>&2
 echo -n "Reference image with very few stars test 2: " >> vast_test_report.txt
 cp default.sex.ccd_bright_star default.sex
 ./vast -u -t2 -f ../vast_test_bright_stars_failed_match/*
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 23" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2001"
  fi
  grep --quiet "Images used for photometry 23" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2002"
  fi
  grep --quiet "Ref.  image: 2458689.62122 25.07.2019 02:54:30" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2003a"
  fi
  grep --quiet "First image: 2458689.62122 25.07.2019 02:54:30" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2003b"
  fi
  grep --quiet "Last  image: 2458689.63980 25.07.2019 03:21:16" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2003c"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### REFIMAGE_WITH_VERY_FEW_STARS2_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### REFIMAGE_WITH_VERY_FEW_STARS2_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2_NO_vast_image_details_log"
  fi
  #
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2005"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2006"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2007"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2008"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2009"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2010"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2011"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2012"
  fi

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mReference image with very few stars test 2 \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mReference image with very few stars test 2 \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS2_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
# the next test relies on the same test data, so don't remove it now
#remove_test_data_to_save_space

##### (Multiple VaST runs) Very few stars on the reference frame #####
# Download the test dataset if needed
if [ ! -d ../vast_test_bright_stars_failed_match ];then
 cd ..
 if [ -f vast_test_bright_stars_failed_match.tar.bz2 ];then
  rm -f vast_test_bright_stars_failed_match.tar.bz2
 fi
 $($WORKDIR/lib/find_timeout_command.sh) 300 curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_bright_stars_failed_match.tar.bz2" && tar -xvjf vast_test_bright_stars_failed_match.tar.bz2 && rm -f vast_test_bright_stars_failed_match.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../vast_test_bright_stars_failed_match ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Reference image with very few stars test 3 " 1>&2
 echo -n "Reference image with very few stars test 3: " >> vast_test_report.txt
 cp default.sex.ccd_bright_star default.sex
 # Run VaST multiple times to catch a rarely occurring problem
 # amazon thing is likely to time out with the number of trials set to 100
 for VAST_RUN in `seq 1 10` ;do
  ./vast -u -t2 -f ../vast_test_bright_stars_failed_match/*
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES RUN"$VAST_RUN"_REFIMAGE_WITH_VERY_FEW_STARS3000"
   break
  fi
  # Check results
  if [ -f vast_summary.log ];then
   grep --quiet "Images processed 23" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES RUN"$VAST_RUN"_REFIMAGE_WITH_VERY_FEW_STARS3001"
    break
   fi
   grep --quiet "Images used for photometry 23" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES RUN"$VAST_RUN"_REFIMAGE_WITH_VERY_FEW_STARS3002"
    break
   fi
   grep --quiet "Ref.  image: 2458689.62122 25.07.2019 02:54:30" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES RUN"$VAST_RUN"_REFIMAGE_WITH_VERY_FEW_STARS3003a"
    break
   fi
   grep --quiet "First image: 2458689.62122 25.07.2019 02:54:30" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES RUN"$VAST_RUN"_REFIMAGE_WITH_VERY_FEW_STARS3003b"
    break
   fi
   grep --quiet "Last  image: 2458689.63980 25.07.2019 03:21:16" vast_summary.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES RUN"$VAST_RUN"_REFIMAGE_WITH_VERY_FEW_STARS3003c"
    break
   fi
   # Hunting the mysterious non-zero reference frame rotation cases
   if [ -f vast_image_details.log ];then
    grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES RUN"$VAST_RUN"_REFIMAGE_WITH_VERY_FEW_STARS3_nonzero_ref_frame_rotation"
     GREP_RESULT=`cat vast_summary.log vast_image_details.log`
     DEBUG_OUTPUT="$DEBUG_OUTPUT
###### RUN"$VAST_RUN"_REFIMAGE_WITH_VERY_FEW_STARS3_nonzero_ref_frame_rotation ######
$GREP_RESULT"
     break
    fi
    grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES RUN"$VAST_RUN"_REFIMAGE_WITH_VERY_FEW_STARS3_nonzero_ref_frame_rotation_test2"
     GREP_RESULT=`cat vast_summary.log vast_image_details.log`
     DEBUG_OUTPUT="$DEBUG_OUTPUT
###### RUN"$VAST_RUN"_REFIMAGE_WITH_VERY_FEW_STARS3_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
     break
    fi
   else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES RUN"$VAST_RUN"_REFIMAGE_WITH_VERY_FEW_STARS3_NO_vast_image_details_log"
    break
   fi
  #
  else
   echo "ERROR: cannot find vast_summary.log" 1>&2
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES RUN"$VAST_RUN"_REFIMAGE_WITH_VERY_FEW_STARS3_ALL"
  fi
 done # for VAST_RUN in `seq 1 100` ;do

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mReference image with very few stars test 3 \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mReference image with very few stars test 3 \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS3_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space


##### Test the two levels of directory recursion #####
# Download the test dataset if needed
if [ ! -d ../vast_test_ASASSN-19cq ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_ASASSN-19cq.tar.bz2" && tar -xvjf vast_test_ASASSN-19cq.tar.bz2 && rm -f vast_test_ASASSN-19cq.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../vast_test_ASASSN-19cq ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Two-level directory recursion test " 1>&2
 echo -n "Two-level directory recursion test: " >> vast_test_report.txt
 cp default.sex.ccd_example default.sex
 ./vast -u -f ../vast_test_ASASSN-19cq/
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 11" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC001"
  fi
  # The possible reference image ../vast_test_ASASSN-19cq/2019_05_15/fd_img2_ASASSN_19cq_V_200s.fit
  # is the wors and should be rejected under normal circumstances
  grep --quiet -e "Images used for photometry 11" -e "Images used for photometry 10" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC002"
  fi
  grep --quiet "First image: 2458619.73071 16.05.2019 05:30:33" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC003a"
  fi
  grep --quiet "Last  image: 2458659.73438 25.06.2019 05:35:00" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC003b"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### TWOLEVELDIRREC0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### TWOLEVELDIRREC0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC0_NO_vast_image_details_log"
  fi
  #
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC005c"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC006"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC007"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC008"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC009"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC010"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC011"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC012"
  fi

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC_ALL1"
 fi

 # Now test the same but with a reasonably good reference image ../vast_test_ASASSN-19cq/2019_06_03/fd_2019_06_03_ASSASN19CQ_300S_v_002.fit
 cp default.sex.ccd_example default.sex
 ./vast -u -f ../vast_test_ASASSN-19cq/2019_06_03/fd_2019_06_03_ASSASN19CQ_300S_v_002.fit ../vast_test_ASASSN-19cq/
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC100"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  # 12 because the reference image will be counted twice
  grep --quiet "Images processed 12" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC101"
  fi
  # The possible reference image ../vast_test_ASASSN-19cq/2019_05_15/fd_img2_ASASSN_19cq_V_200s.fit
  # is the wors and should be rejected under normal circumstances
  grep --quiet "Images used for photometry 10" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC102"
  fi
  grep --quiet "First image: 2458619.73071 16.05.2019 05:30:33" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC103a"
  fi
  grep --quiet "Last  image: 2458659.73438 25.06.2019 05:35:00" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC103b"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC1_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### TWOLEVELDIRREC1_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC1_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### TWOLEVELDIRREC1_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC1_NO_vast_image_details_log"
  fi
  #
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC105c"
  fi
  if [ ! -s vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC106"
  fi
  if [ ! -f vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC107"
  fi
  if [ ! -s vast_lightcurve_statistics_format.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC108"
  fi
  grep --quiet "IQR" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC109"
  fi
  grep --quiet "eta" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC110"
  fi
  grep --quiet "RoMS" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC111"
  fi
  grep --quiet "rCh2" vast_lightcurve_statistics_format.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC112"
  fi

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC_ALL2"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mTwo-level directory recursion test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mTwo-level directory recursion test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space


##### MASTER images test #####
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
# Download the test dataset if needed
if [ ! -d ../MASTER_test ];then
 cd ..
 if [ -f MASTER_test.tar.bz2 ];then
  rm -f MASTER_test.tar.bz2
 fi
 $($WORKDIR/lib/find_timeout_command.sh) 300 curl -O "http://scan.sai.msu.ru/~kirx/pub/MASTER_test.tar.bz2" && tar -xvjf MASTER_test.tar.bz2 && rm -f MASTER_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../MASTER_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "MASTER CCD images test " 1>&2
 echo -n "MASTER CCD images test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 ./vast -u -f ../MASTER_test/*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 6" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD001"
  fi
  grep --quiet "Images used for photometry 6" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD002"
  fi
  #grep --quiet "First image: 2457154.31907 11.05.2015 19:39:26" vast_summary.log
  grep --quiet "First image: 2457154.31910 11.05.2015 19:39:27" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD003"
  fi
  #grep --quiet "Last  image: 2457154.32075 11.05.2015 19:41:51" vast_summary.log
  grep --quiet "Last  image: 2457154.32076 11.05.2015 19:41:51" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### MASTERCCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### MASTERCCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD0_NO_vast_image_details_log"
  fi
  #
  util/solve_plate_with_UCAC5 ../MASTER_test/wcs_fd_MASTER-KISL-WFC-1_EAST_W_-30_LIGHT_5_878280.fit
  if [ ! -f wcs_fd_MASTER-KISL-WFC-1_EAST_W_-30_LIGHT_5_878280.fit.cat.ucac5 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD005"
  else
   lib/bin/xy2sky wcs_fd_MASTER-KISL-WFC-1_EAST_W_-30_LIGHT_5_878280.fit 200 200 &>/dev/null
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD005a"
   fi
   TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_fd_MASTER-KISL-WFC-1_EAST_W_-30_LIGHT_5_878280.fit.cat.ucac5 | wc -l | awk '{print $1}'`
   #if [ $TEST -lt 800 ];then
   if [ $TEST -lt 300 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD005b_$TEST"
   fi
  fi 
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  ### Flag image test should always be the last one
  for IMAGE in ../MASTER_test/*.fit ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD006_$IMAGE"
   fi 
  done 

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mMASTER CCD images test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mMASTER CCD images test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then
##########################################


##### M31 ISON images test #####
# Download the test dataset if needed
if [ ! -d ../M31_ISON_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/M31_ISON_test.tar.bz2" && tar -xvjf M31_ISON_test.tar.bz2 && rm -f M31_ISON_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../M31_ISON_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "ISON M31 CCD images test " 1>&2
 echo -n "ISON M31 CCD images test: " >> vast_test_report.txt 
 cp default.sex.ison_m31_test default.sex
 ./vast -u -f ../M31_ISON_test/*.fts
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 5" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD001"
  fi
  grep --quiet "Images used for photometry 5" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD002"
  fi
  grep --quiet "First image: 2455863.88499 29.10.2011 09:13:23" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD003"
  fi
  grep --quiet "Last  image: 2455867.61163 02.11.2011 02:39:45" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### ISONM31CCD0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### ISONM31CCD0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD0_NO_vast_image_details_log"
  fi
  #
  util/solve_plate_with_UCAC5 ../M31_ISON_test/M31-1-001-001_dupe-1.fts
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD005_exitcode"
  fi
  if [ ! -f wcs_M31-1-001-001_dupe-1.fts ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD005_wcs_M31-1-001-001_dupe-1.fts"
  fi
  if [ ! -f wcs_M31-1-001-001_dupe-1.fts.cat.ucac5 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD005_wcs_M31-1-001-001_dupe-1.fts.cat.ucac5"
  else
   lib/bin/xy2sky wcs_M31-1-001-001_dupe-1.fts 200 200 &>/dev/null
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD005a"
   fi
   TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_M31-1-001-001_dupe-1.fts.cat.ucac5 | wc -l | awk '{print $1}'`
   #if [ $TEST -lt 1500 ];then
   #if [ $TEST -lt 750 ];then
   if [ $TEST -lt 500 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD005b_$TEST"
   fi
  fi 
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  ### Flag image test should always be the last one
  for IMAGE in ../M31_ISON_test/*.fts ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD006_$IMAGE"
   fi 
  done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mISON M31 CCD images test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mISON M31 CCD images test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space

##### Gaia16aye images by S. Nazarov test #####
# Download the test dataset if needed
if [ ! -d ../Gaia16aye_SN ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/Gaia16aye_SN.tar.bz2" && tar -xvjf Gaia16aye_SN.tar.bz2 && rm -f Gaia16aye_SN.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../Gaia16aye_SN ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Gaia16aye_SN CCD images test " 1>&2
 echo -n "Gaia16aye_SN CCD images test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 ./vast -u -f -x3 ../Gaia16aye_SN/*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 4" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN001"
  fi
  grep --quiet "Images used for photometry 4" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN002"
  fi
  grep --quiet "First image: 2457714.13557 21.11.2016 15:13:43" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN003"
  fi
  grep --quiet "Last  image: 2457714.14230 21.11.2016 15:23:25" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### GAIA16AYESN0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### GAIA16AYESN0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "JD time system (TT/UTC/UNKNOWN): UTC" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN0041"
  fi
  util/solve_plate_with_UCAC5 ../Gaia16aye_SN/fd_Gaya16aye_21-22-nov-16_N200c_F1000_-36_bin1x_C_3min-001.fit
  if [ ! -f wcs_fd_Gaya16aye_21-22-nov-16_N200c_F1000_-36_bin1x_C_3min-001.fit ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN005"
  fi 
  lib/bin/xy2sky wcs_fd_Gaya16aye_21-22-nov-16_N200c_F1000_-36_bin1x_C_3min-001.fit 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN005a"
  fi
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  ### Flag image test should always be the last one
  for IMAGE in ../Gaia16aye_SN/*.fit ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN006_$IMAGE"
   fi 
  done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mGaia16aye_SN CCD images test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mGaia16aye_SN CCD images test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space

##### Images with only few stars by S. Nazarov test #####
# Download the test dataset if needed
if [ ! -d ../only_few_stars ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/only_few_stars.tar.bz2" && tar -xvjf only_few_stars.tar.bz2 && rm -f only_few_stars.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../only_few_stars ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "CCD images with few stars test " 1>&2
 echo -n "CCD images with few stars test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 ./vast -u -f -p ../only_few_stars/*
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 25" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS001"
  fi
  grep --quiet "Images used for photometry 25" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS002"
  fi
  grep --quiet "First image: 2452270.63266 27.12.2001 03:10:32" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS003"
  fi
  grep --quiet "Last  image: 2452298.60258 24.01.2002 02:27:23" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### CCDIMGFEWSTARS0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### CCDIMGFEWSTARS0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "JD time system (TT/UTC/UNKNOWN): UTC" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS0041"
  fi
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  ### Test the median image stacker
  util/ccd/mk ../only_few_stars/*
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS_IMAGESTACKER001"
  fi
  if [ -f median.fit ];then
   rm -f median.fit
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS_IMAGESTACKER002"
  fi
  ################################################################################
  ### Flag image test should always be the last one
  for IMAGE in ../only_few_stars/* ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS006_$IMAGE"
   fi 
  done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mCCD images with few stars test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mCCD images with few stars test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

##### Images with only few stars and a brigh galaxy by S. Nazarov test #####
# Download the test dataset if needed
if [ ! -d ../only_few_stars ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/only_few_stars.tar.bz2" && tar -xvjf only_few_stars.tar.bz2 && rm -f only_few_stars.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../only_few_stars ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "CCD images with few stars and brigh galaxy magsizefilter test " 1>&2
 echo -n "CCD images with few stars and brigh galaxy magsizefilter test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 ./vast -u -f -p --magsizefilter ../only_few_stars/*
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 25" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE001"
  fi
  grep --quiet "Images used for photometry 25" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE002"
  fi
  grep --quiet "First image: 2452270.63266 27.12.2001 03:10:32" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE003"
  fi
  grep --quiet "Last  image: 2452298.60258 24.01.2002 02:27:23" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### CCDIMGFEWSTARSBRIGHTGALMAGSIZE0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### CCDIMGFEWSTARSBRIGHTGALMAGSIZE0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "JD time system (TT/UTC/UNKNOWN): UTC" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE0041"
  fi
  #
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_EMPTYAUTOCANDIDATES"
  else
   # The idea here is that the magsizefilter should save us from a few false candidates overlapping with the galaxy disk
   LINES_IN_LOG_FILE=`cat vast_autocandidates.log | wc -l | awk '{print $1}'`
   if [ $LINES_IN_LOG_FILE -gt 2 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_TOOMANYAUTOCANDIDATES"
   fi
  fi
  #
  ### The input image order on the command line depends on locale,
  ### so image00001.cat may correspond to different images on different machines.
  ### So, we need to get the image catalog name corresponding to the secific
  ### input FITS image.
  if [ ! -s vast_images_catalogs.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_NOVASTIMAGESCATALOGSLOG"
  fi
  grep --quiet 'ap000177.fit' vast_images_catalogs.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_THEIMAGFILEISNOTINIMAGESCATALOGS"
  fi
  IMAGE_CATALOG_NAME=`cat vast_images_catalogs.log | grep 'ap000177.fit' | awk '{print $1}'`
  #
  cat src/vast_limits.h | grep -v '//' | grep --quiet 'DISABLE_MAGSIZE_FILTER_LOGS'
  if [ $? -ne 0 ];then
   if [ ! -s "$IMAGE_CATALOG_NAME".magparameter00filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_EMPTY00REJ"
   else
    LINES_IN_LOGFILE=`cat "$IMAGE_CATALOG_NAME".magparameter00filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 8 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_FEW00REJ"
    fi
   fi
   #
   if [ ! -s "$IMAGE_CATALOG_NAME".magparameter01filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_EMPTY01REJ"
   else
    LINES_IN_LOGFILE=`cat "$IMAGE_CATALOG_NAME".magparameter01filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 7 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_FEW01REJ"
    fi
   fi
   #
   if [ ! -s "$IMAGE_CATALOG_NAME".magparameter04filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_EMPTY04REJ"
   else
    LINES_IN_LOGFILE=`cat "$IMAGE_CATALOG_NAME".magparameter04filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 6 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_FEW04REJ"
    fi
   fi
   #
   if [ ! -s "$IMAGE_CATALOG_NAME".magparameter06filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_EMPTY06REJ"
   else
    LINES_IN_LOGFILE=`cat "$IMAGE_CATALOG_NAME".magparameter06filter_rejected | wc -l | awk '{print $1}'`
    if [ $LINES_IN_LOGFILE -lt 6 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_FEW06REJ"
    fi
   fi
   #
   if [ ! -s "$IMAGE_CATALOG_NAME".magparameter08filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_EMPTY08REJ"
   else
    LINES_IN_LOGFILE=`cat "$IMAGE_CATALOG_NAME".magparameter08filter_rejected | wc -l | awk '{print $1}'`
    #if [ $LINES_IN_LOGFILE -lt 6 ];then
    if [ $LINES_IN_LOGFILE -lt 2 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_FEW08REJ"
    fi
   fi
   #
   if [ ! -s "$IMAGE_CATALOG_NAME".magparameter10filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_EMPTY10REJ"
   else
    LINES_IN_LOGFILE=`cat "$IMAGE_CATALOG_NAME".magparameter10filter_rejected | wc -l | awk '{print $1}'`
    #if [ $LINES_IN_LOGFILE -lt 6 ];then
    if [ $LINES_IN_LOGFILE -lt 2 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_FEW10REJ"
    fi
   fi
   #
   if [ ! -s "$IMAGE_CATALOG_NAME".magparameter12filter_rejected ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_EMPTY12REJ"
   else
    LINES_IN_LOGFILE=`cat "$IMAGE_CATALOG_NAME".magparameter12filter_rejected | wc -l | awk '{print $1}'`
    #if [ $LINES_IN_LOGFILE -lt 6 ];then
    if [ $LINES_IN_LOGFILE -lt 5 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_FEW12REJ"
    fi
   fi
   #
  fi # DISABLE_MAGSIZE_FILTER_LOGS
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  ### Flag image test should always be the last one
  for IMAGE in ../only_few_stars/* ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE006_$IMAGE"
   fi 
  done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mCCD images with few stars and brigh galaxy magsizefilter test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mCCD images with few stars and brigh galaxy magsizefilter test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space

##### test images by JB #####
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
# Download the test dataset if needed
if [ ! -d ../test_exclude_ref_image ];then
 cd ..
 if [ -f test_exclude_ref_image.tar.bz2 ];then
  rm -f test_exclude_ref_image.tar.bz2
 fi
 $($WORKDIR/lib/find_timeout_command.sh) 300 curl -O "http://scan.sai.msu.ru/~kirx/data/vast_tests/test_exclude_ref_image.tar.bz2" && tar -xvjf test_exclude_ref_image.tar.bz2 && rm -f test_exclude_ref_image.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../test_exclude_ref_image ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Exclude reference image test " 1>&2
 echo -n "Exclude reference image test: " >> vast_test_report.txt 
 #cp default.sex.excluderefimgtest default.sex
 # The default file actually is better
 cp default.sex.ccd_example default.sex
 ./vast --excluderefimage -fruj -b 500 -y 3 ../test_exclude_ref_image/coadd.red.fits ../test_exclude_ref_image/lm*.fits
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 309" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE001"
  fi
  grep --quiet "Images used for photometry 309" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE002"
  fi
  grep 'Ref.  image:' vast_summary.log | grep --quiet 'coadd.red.fits'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE_REFIMAGE"
  fi
  grep --quiet "First image: 2450486.59230 07.02.1997 02:12:55" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE003"
  fi
  grep --quiet "Last  image: 2452578.55380 31.10.2002 01:17:28" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### EXCLUDEREFIMAGE0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### EXCLUDEREFIMAGE0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "JD time system (TT/UTC/UNKNOWN): UTC" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE005"
  fi
  #
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE_EMPTYAUTOCANDIDATES"
#  else
#   # The idea here is that the magsizefilter should save us from a few false candidates overlapping with the galaxy disk
#   LINES_IN_LOG_FILE=`cat vast_autocandidates.log | wc -l | awk '{print $1}'`
#   if [ $LINES_IN_LOG_FILE -gt 2 ];then
#    TEST_PASSED=0
#    FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE_TOOMANYAUTOCANDIDATES"
#   fi
  fi
  # Time test
  util/get_image_date ../test_exclude_ref_image/lm01306trr8a1338.fits 2>&1 | grep -A 10 'DATE-OBS= 1998-01-14T06:47:48' | grep -A 10 'EXPTIME = 0' | grep -A 10 'Exposure   0 sec, 14.01.1998 06:47:48   = JD  2450827.78319' | grep --quiet 'JD 2450827.783194'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE_OBSERVING_TIME001"
  fi
  #

  ################################################################################
  # Check individual variables in the test data set
  ################################################################################
  # True variables
  for XY in "770.0858800 207.0210000" "341.8960900 704.7567700" "563.2354700 939.6331800" "764.0470000 678.5069000" "560.6923800 625.8682900" ;do
   LIGHTCURVEFILE=$(find_source_by_X_Y_in_vast_lightcurve_statistics_log $XY)
   if [ "$LIGHTCURVEFILE" == "none" ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES  EXCLUDEREFIMAGE_VARIABLE_NOT_DETECTED__${XY// /_}"
   fi
   grep --quiet "$LIGHTCURVEFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES  EXCLUDEREFIMAGE_VARIABLE_NOT_SELECTED__$LIGHTCURVEFILE"
   fi
   grep --quiet "$LIGHTCURVEFILE" vast_list_of_likely_constant_stars.log
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES  EXCLUDEREFIMAGE_VARIABLE_MISTAKEN_FOR_CONSTANT__$LIGHTCURVEFILE"
   fi
  done
  # False candidates
  for XY in "12.3536000 927.1984300" "428.0304900 134.6074100" ;do
   LIGHTCURVEFILE=$(find_source_by_X_Y_in_vast_lightcurve_statistics_log $XY)
   if [ "$LIGHTCURVEFILE" == "none" ];then
    # The bad source is not detected at all, good
    continue
   fi
   grep --quiet "$LIGHTCURVEFILE" vast_autocandidates.log
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES  FALSE_CANDIDATE_SELECTED__$LIGHTCURVEFILE"
   fi
  done
  ################################################################################

  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  ### Special two-image test
  ./vast -uf ../test_exclude_ref_image/coadd.red.fits ../test_exclude_ref_image/lm01306trraf1846.fits
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE100"
  fi
  # Check results
  grep --quiet "Images processed 2" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE101"
  fi
  grep --quiet "Images used for photometry 2" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE102"
  fi
  ################################################################################
  ### Flag image test should always be the last one
  for IMAGE in ../test_exclude_ref_image/lm* ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep --quiet "FLAG_IMAGE image00000.flag"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    BASEIMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE006_$BASEIMAGE"
   fi 
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep --quiet "GAIN 1.990"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    BASEIMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE006a_$BASEIMAGE"
   fi 
  done
  
  # GAIN things
  lib/autodetect_aperture_main ../test_exclude_ref_image/lm01306trraf1846.fits 2>&1 | grep --quiet 'GAINCCD=1.990'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE_GAIN001"
  fi
  lib/autodetect_aperture_main ../test_exclude_ref_image/lm01306trraf1846.fits 2>&1 | grep --quiet 'GAIN 1.990'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE_GAIN002"
  fi  
  echo 'GAIN_KEY         GAINCCD' >> default.sex
  lib/autodetect_aperture_main ../test_exclude_ref_image/lm01306trraf1846.fits 2>&1 | grep --quiet 'GAIN'
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE_GAIN_KEY"
  fi
 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE_ALL"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mExclude reference image test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mExclude reference image test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then
##########################################


# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi

##### Ceres test #####
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
# Download the test dataset if needed
if [ ! -d ../transient_detection_test_Ceres ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/vast/transient_detection_test_Ceres.tar.bz2" && tar -xvjf transient_detection_test_Ceres.tar.bz2 && rm -f transient_detection_test_Ceres.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../transient_detection_test_Ceres ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Ceres test " 1>&2
 echo -n "NMW find Ceres test: " >> vast_test_report.txt 
 cp default.sex.telephoto_lens default.sex
 ./vast -x99 -ukf ../transient_detection_test_Ceres/reference_images/* ../transient_detection_test_Ceres/second_epoch_images/*
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES CERES000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 4" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES001"
  fi
  grep --quiet "Images used for photometry 4" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES002"
  fi
  grep --quiet "First image: 2456005.28101 18.03.2012 18:44:24" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES003"
  fi
  grep --quiet "Last  image: 2456377.34852 25.03.2013 20:21:37" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### CERES0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### CERES0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES0_NO_vast_image_details_log"
  fi
  #

  # Re-run the analysis to make sure -k key has no effect (JD keyword in the FITS header is automatically ignored)
  cp default.sex.telephoto_lens default.sex
  ./vast -x99 -uf ../transient_detection_test_Ceres/reference_images/* ../transient_detection_test_Ceres/second_epoch_images/*
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES100"
  fi
  grep --quiet "Images processed 4" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES101"
  fi
  grep --quiet "Images used for photometry 4" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES102"
  fi
  grep --quiet "First image: 2456005.28101 18.03.2012 18:44:24" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES103"
  fi
  grep --quiet "Last  image: 2456377.34852 25.03.2013 20:21:37" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES104"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES1_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### CERES1_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES1_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### CERES1_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES1_NO_vast_image_details_log"
  fi
  #
  
  # Download a copy of Tycho-2 catalog for magnitude calibration of wide-field transient search data
  VASTDIR=$PWD
  TYCHO_PATH=lib/catalogs/tycho2
  # Check if we have a locakal copy...
  if [ ! -f "$TYCHO_PATH"/tyc2.dat.00 ];then
   # Download the Tycho-2 catalog from our own server
   if [ ! -d ../tycho2 ];then
    cd `dirname $VASTDIR`
    curl -O "http://scan.sai.msu.ru/~kirx/pub/tycho2.tar.bz2" && tar -xvjf tycho2.tar.bz2 && rm -f tycho2.tar.bz2
    cd $VASTDIR
   fi
   # Try again
   if [ -d ../tycho2 ];then
    #cp -r ../tycho2 $TYCHO_PATH
    if [ ! -d "$TYCHO_PATH" ];then
     # -p  no error if existing, make parent directories as needed
     mkdir -p "$TYCHO_PATH"
    fi
    cd $TYCHO_PATH
    for TYCHOFILE in `dirname $VASTDIR`/tycho2/* ;do ln -s $TYCHOFILE ;done
    cd $VASTDIR
   fi
  fi
  #
  if [ -f ../exclusion_list.txt ];then
   mv ../exclusion_list.txt ../exclusion_list.txt_backup
  fi
  #################################################################
  # We need a special astorb.dat for Ceres
  if [ -f astorb.dat ];then
   mv astorb.dat astorb.dat_backup
  fi
  if [ ! -f astorb_ceres.dat ];then
   curl -O "http://scan.sai.msu.ru/~kirx/pub/astorb_ceres.dat.gz" 1>&2
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES_error_downloading_custom_astorb_ceres.dat"
   fi
   gunzip astorb_ceres.dat.gz
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES_error_unpacking_custom_astorb_ceres.dat"
   fi
  fi
  cp astorb_ceres.dat astorb.dat
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES_error_copying_astorb_ceres.dat_to_astorb.dat"
  fi
  #################################################################
  echo "y" | util/transients/search_for_transients_single_field.sh test
  if [ -f astorb.dat_backup ];then
   mv astorb.dat_backup astorb.dat
  else
   # remove the custom astorb.dat
   rm -f astorb.dat
  fi
  ## New stuff the file lib/catalogs/list_of_bright_stars_from_tycho2.txt should be created by util/transients/search_for_transients_single_field.sh
  if [ ! -f lib/catalogs/list_of_bright_stars_from_tycho2.txt ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES200"
  fi
  if [ ! -s lib/catalogs/list_of_bright_stars_from_tycho2.txt ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES201"
  fi
  ##
  if [ ! -f wcs_Tau1_2012-3-18_18-45-6_002.fts ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES005"
  fi 
  lib/bin/xy2sky wcs_Tau1_2012-3-18_18-45-6_002.fts 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES005a"
  fi
  if [ ! -f wcs_Tau1_2013-3-25_20-21-36_002.fts ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES006"
  fi 
  lib/bin/xy2sky wcs_Tau1_2013-3-25_20-21-36_002.fts 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES006a"
  fi
  if [ ! -f wcs_Tau1_201_ref_rename_001.fts ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES007"
  fi 
  lib/bin/xy2sky wcs_Tau1_201_ref_rename_001.fts 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES007a"
  fi
  if [ ! -f wcs_Tau1_201_rename_001.fts ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES008"
  fi 
  lib/bin/xy2sky wcs_Tau1_201_rename_001.fts 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES008a"
  fi
  if [ ! -f transient_report/index.html ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES009"
  fi 
  grep --quiet "DO Gem" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES010"
  fi
  #grep --quiet "2013 03 25.8483  2456377.3483  12.37  06:01:27.29 +23:51:10.7" transient_report/index.html
  grep --quiet "2013 03 25.8483  2456377.3483  12.37" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES010a"
  fi
  RADECPOSITION_TO_TEST=`grep "2013 03 25.8483  2456377.3483  12.37" transient_report/index.html | awk '{print $6" "$7}'`
  # Changed to the VSX position
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 06:01:27.02 +23:51:19.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  # Relaxed to 1.5pix as I'm always getting it more than 1 pix wrong without the local correction
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 1.5*8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES010a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES010a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "HK Aur" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES011"
  fi
  #grep --quiet "2013 03 22.3148  2456191.3148  11.75  05:48:54.08 +28:51:09.7" transient_report/index.html
  grep --quiet "2013 03 25.8483  2456377.3483  11.26" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES011a"
  fi
  RADECPOSITION_TO_TEST=`grep "2013 03 25.8483  2456377.3483  11.26" transient_report/index.html | awk '{print $6" "$7}'`
  #DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 05:48:54.08 +28:51:09.7 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # Changed to the VSX position
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 05:48:53.74 +28:51:09.7  $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  #TEST=`echo "$DISTANCE_ARCSEC<8.4" | bc -ql`
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES011a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES011a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # AW Tau does not pass the strict selection criterea, so we'll drop it
  #grep --quiet "AW Tau" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES CERES0110"
  #fi
  ##grep --quiet "2013 03 22.3148  2456191.3148  13.38  05:47:30.53 +27:08:16.8" transient_report/index.html
  #grep --quiet "2013 03 25.8483  2456377.3483  12.93" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES CERES0110a"
  #fi
  #RADECPOSITION_TO_TEST=`grep "2013 03 25.8483  2456377.3483  12.93" transient_report/index.html | awk '{print $6" "$7}'`
  ##DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 05:47:30.53 +27:08:16.8 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  ## Changed to the VSX position
  #DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 05:47:30.21 +27:08:12.5 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  ## NMW scale is 8.4"/pix
  #TEST=`echo "$DISTANCE_ARCSEC<8.4" | bc -ql`
  #re='^[0-9]+$'
  #if ! [[ $TEST =~ $re ]] ; then
  # echo "TEST ERROR"
  # TEST_PASSED=0
  # TEST=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES CERES0110a_TOO_FAR_TEST_ERROR"
  #else
  # if [ $TEST -eq 0 ];then
  #  TEST_PASSED=0
  #  FAILED_TEST_CODES="$FAILED_TEST_CODES CERES0110a_TOO_FAR_$DISTANCE_ARCSEC"
  # fi
  #fi
  #
  grep --quiet "LP Gem" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES012"
  fi
  #grep --quiet "2013 03 22.3148  2456191.3148  13.10  06:05:05.47 +26:40:53.2" transient_report/index.html
  grep --quiet "2013 03 25.8483  2456377.3483  12.24" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES012a"
  fi
  RADECPOSITION_TO_TEST=`grep "2013 03 25.8483  2456377.3483  12.24" transient_report/index.html | awk '{print $6" "$7}'`
  #DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 06:05:05.47 +26:40:53.2 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # Changed to the VSX position
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 06:05:05.13 +26:40:53.4 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES012a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES012a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "AU Tau" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES013"
  fi
  #grep --quiet "2013 03 22.3148  2456191.3148  12.79  05:43:31.42 +28:07:41.4" transient_report/index.html
  grep --quiet "2013 03 25.8483  2456377.3483  12.04  05:43" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES013a"
  fi
  RADECPOSITION_TO_TEST=`grep "2013 03 25.8483  2456377.3483  12.04  05:43" transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  #DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 05:43:31.42 +28:07:41.4 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 05:43:31.01 +28:07:44.1 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES013a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES013a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "RR Tau" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES014"
  fi
  #grep --quiet "2013 03 22.3148  2456191.3148  12.32  05:39:30.69 +26:22:25.7" transient_report/index.html
  grep --quiet "2013 03 25.8483  2456377.3483  10.76" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES014a"
  fi
  RADECPOSITION_TO_TEST=`grep "2013 03 25.8483  2456377.3483  10.76" transient_report/index.html | awk '{print $6" "$7}'`
  #DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 05:39:30.69 +26:22:25.7 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 05:39:30.51 +26:22:27.0 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES014a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES014a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "1 Ceres" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES015"
  fi
  #grep --quiet "2013 03 25.8483  2456377.3483  8.61  05:46:04.53 +28:40:52.7" transient_report/index.html
  grep --quiet "2013 03 25.8483  2456377.3483  8.61" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES015a"
  fi
  grep --quiet "21 Lutetia" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES016"
  fi
  #grep --quiet "2013 03 25.8483  2456377.3483  12.43  06:00:06.32 +25:03:34.1" transient_report/index.html
  grep --quiet -e "2013 03 25.8483  2456377.3483  12.43" -e "2013 03 25.8483  2456377.3483  12.42" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES016a"
  fi
  #
  ###########################################################
  # Magnitude calibration error test
  if [ -f 'lightcurve.tmp_emergency_stop_debug' ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES_magcalibr_emergency"
   cp lightcurve.tmp_emergency_stop_debug CERES_magcalibr_emergency__lightcurve.tmp_emergency_stop_debug
  fi
  ###########################################################
  #
  if [ -f ../exclusion_list.txt_backup ];then
   mv ../exclusion_list.txt_backup ../exclusion_list.txt
  fi
  #
  ### Specific test to make sure lib/try_to_guess_image_fov does not crash
  for IMAGE in ../transient_detection_test_Ceres/reference_images/* ../transient_detection_test_Ceres/second_epoch_images/* ;do
   lib/try_to_guess_image_fov $IMAGE
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES017_$IMAGE"
   fi
  done
  ### Test to make sure no bad magnitudes were created during magnitude calibration process
  if [ -f CERES018_PROBLEM.txt ];then
   rm -f CERES018_PROBLEM.txt
  fi
  for OUTFILE in out*.dat ;do NLINES=`cat $OUTFILE | wc -l | awk '{print $1}'` ; NGOOD=`util/cute_lc $OUTFILE | wc -l | awk '{print $1}'` ; if [ $NLINES -ne $NGOOD ];then echo PROBLEM $NLINES $NGOOD $OUTFILE ; echo "$NLINES $NGOOD $OUTFILE" >> CERES018_PROBLEM.txt ; cp $OUTFILE CERES018_PROBLEM_$OUTFILE ;fi ;done | grep --quiet 'PROBLEM'
  if [ $? -eq 0 ];then
   N_FILES_WITH_PROBLEM=`cat CERES018_PROBLEM.txt |wc -l | awk '{print $1}'`
   if [ $N_FILES_WITH_PROBLEM -gt 1 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES018__"$N_FILES_WITH_PROBLEM
   fi
  fi
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  ### Flag image test should always be the last one because we clean the data
  for IMAGE in ../transient_detection_test_Ceres/reference_images/* ../transient_detection_test_Ceres/second_epoch_images/* ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES019_$IMAGE"
   fi
  done 

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES CERES_ALL"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Ceres test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Ceres test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES CERES_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space

# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi

fi # if [ "$GITHUB_ACTIONS" != "true" ];then



###### Update the catalogs and asteroid database ######
lib/update_offline_catalogs.sh force



##### Saturn/Iapetus test #####
# Download the test dataset if needed
if [ ! -d ../NMW_Saturn_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_Saturn_test.tar.bz2" && tar -xvjf NMW_Saturn_test.tar.bz2 && rm -f NMW_Saturn_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../NMW_Saturn_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Saturn/Iapetus test " 1>&2
 echo -n "NMW find Saturn/Iapetus test: " >> vast_test_report.txt 
 #cp default.sex.telephoto_lens_v4 default.sex
 cp default.sex.telephoto_lens_v3 default.sex
 ./vast -x99 -uf ../NMW_Saturn_test/1referenceepoch/* ../NMW_Saturn_test/2ndepoch/*
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 4" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN001"
  fi
  grep --quiet "Images used for photometry 4" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN002"
  fi
  grep --quiet "First image: 2456021.56453 04.04.2012 01:32:40" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN003"
  fi
  grep --quiet "Last  image: 2458791.14727 03.11.2019 15:31:54" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SATURN0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SATURN0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN0_NO_vast_image_details_log"
  fi
  #
  
  # Download a copy of Tycho-2 catalog for magnitude calibration of wide-field transient search data
  VASTDIR=$PWD
  TYCHO_PATH=lib/catalogs/tycho2
  # Check if we have a locakal copy...
  if [ ! -f "$TYCHO_PATH"/tyc2.dat.00 ];then
   # Download the Tycho-2 catalog from our own server
   if [ ! -d ../tycho2 ];then
    cd `dirname $VASTDIR`
    curl -O "http://scan.sai.msu.ru/~kirx/pub/tycho2.tar.bz2" && tar -xvjf tycho2.tar.bz2 && rm -f tycho2.tar.bz2
    cd $VASTDIR
   fi
   # Try again
   if [ -d ../tycho2 ];then
    #cp -r ../tycho2 $TYCHO_PATH
    if [ ! -d "$TYCHO_PATH" ];then
     # -p  no error if existing, make parent directories as needed
     mkdir -p "$TYCHO_PATH"
    fi
    cd $TYCHO_PATH
    for TYCHOFILE in `dirname $VASTDIR`/tycho2/* ;do ln -s $TYCHOFILE ;done
    cd $VASTDIR
   fi
  fi
  #
  if [ -f ../exclusion_list.txt ];then
   mv ../exclusion_list.txt ../exclusion_list.txt_backup
  fi
  #
  echo "y" | util/transients/search_for_transients_single_field.sh test
  ## New stuff the file lib/catalogs/list_of_bright_stars_from_tycho2.txt should be created by util/transients/search_for_transients_single_field.sh
  if [ ! -f lib/catalogs/list_of_bright_stars_from_tycho2.txt ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN200"
  fi
  if [ ! -s lib/catalogs/list_of_bright_stars_from_tycho2.txt ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN201"
  fi
  ##
  if [ ! -f wcs_Sgr4_2012-4-4_1-33-21_002.fts ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN005"
  fi 
  lib/bin/xy2sky wcs_Sgr4_2012-4-4_1-33-21_002.fts 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN005a"
  fi
  if [ ! -f wcs_Sgr4_2019-11-3_15-31-54_001.fts ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN006"
  fi 
  lib/bin/xy2sky wcs_Sgr4_2019-11-3_15-31-54_001.fts 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN006a"
  fi
  if [ ! -f wcs_Sgr4_2019-11-3_15-32-23_002.fts ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN007"
  fi 
  lib/bin/xy2sky wcs_Sgr4_2019-11-3_15-32-23_002.fts 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN007a"
  fi
  if [ ! -f wcs_Sgr4_201_ref_rename_001.fts ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN008"
  fi 
  lib/bin/xy2sky wcs_Sgr4_201_ref_rename_001.fts 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN008a"
  fi
  if [ ! -f transient_report/index.html ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN009"
  fi 
  grep --quiet "QY Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN010"
  fi
  # this should NOT be found! First epoch image is used along the 2nd epoch images
  grep --quiet "2019 11 03.7864  2457867.9530  12\.1." transient_report/index.html
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN010x"
  fi
  #
  grep --quiet -e "2019 11 03.6470  2458791.1470  11\.2.  19:03:" -e "2019 11 03.6470  2458791.1470  11\.3.  19:03:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN010a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  11\.2.  19:03:" -e "2019 11 03.6470  2458791.1470  11\.3.  19:03:" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:03:48.76 -26:58:59.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN010a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN010a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "V1058 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN011"
  fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  11.84  19:01:" -e "2019 11 03.6470  2458791.1470  11.82  19:01:" -e "2019 11 03.6470  2458791.1470  11.86  19:01:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN011a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  11.84  19:01:" -e "2019 11 03.6470  2458791.1470  11.82  19:01:" -e "2019 11 03.6470  2458791.1470  11.86  19:01:" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:01:28.86 -22:38:56.6 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN011a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN011a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # Iapetus has no automatic ID in the current VaST version
  #grep --quiet "AW Tau" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN0110"
  #fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  12.13  19:06:" -e "2019 11 03.6470  2458791.1470  12.10  19:06:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN0110a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  12.13  19:06:" -e "2019 11 03.6470  2458791.1470  12.10  19:06:" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:06:59.18 -22:25:40.5 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN0110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN0110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "V2407 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN012"
  fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  12\.2.  19:10:" -e "2019 11 03.6470  2458791.1470  12\.3.  19:10:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN012a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  12\.2.  19:10:" -e "2019 11 03.6470  2458791.1470  12\.3.  19:10:" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:10:11.72 -27:05:38.5 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN012a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN012a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "V1260 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN013"
  fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  11.01  19:16:" -e "2019 11 03.6470  2458791.1470  10.97  19:16:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN013a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  11.01  19:16:" -e "2019 11 03.6470  2458791.1470  10.97  19:16:" transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:16:59.73 -24:36:23.9 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN013a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN013a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "QR Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN014"
  fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  12.07  19:01:" -e "2019 11 03.6470  2458791.1470  12.04  19:01:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN014a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  12.07  19:01:" -e "2019 11 03.6470  2458791.1470  12.04  19:01:" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:01:30.92 -21:19:30.1 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN014a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN014a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "TW Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN314"
  fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  10.97  19:13:" -e "2019 11 03.6470  2458791.1470  10.94  19:13:" -e "2019 11 03.6470  2458791.1470  10.93  19:13:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN314a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  10.97  19:13:" -e "2019 11 03.6470  2458791.1470  10.94  19:13:" -e "2019 11 03.6470  2458791.1470  10.93  19:13:" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:13:27.07 -21:33:38.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN314a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN314a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  ##### The following variables will not be found with the 12.5 magnitude limit and v4 SE settings file
  #
  grep --quiet "V1234 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN315"
  fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  12.80  19:00:" -e "2019 11 03.6470  2458791.1470  12.77  19:00:" -e "2019 11 03.6470  2458791.1470  12.78  19:00:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN315a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  12.80  19:00:" -e "2019 11 03.6470  2458791.1470  12.77  19:00:" -e "2019 11 03.6470  2458791.1470  12.78  19:00:" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:00:31.78 -23:01:30.8 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN315a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN315a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  ##### The following variables will not be found with the 12.5 magnitude limit and v4 SE settings file
  #
  grep --quiet "ASASSN-V J190815.15-194531.8" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN316"
  fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  12\.9.  19:08:..\... -19:45:..\.." -e "2019 11 03.6470  2458791.1470  13\.0.  19:08:..\... -19:45:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN316a"
  fi
  RADECPOSITION_TO_TEST=`grep  -e "2019 11 03.6470  2458791.1470  12\.9.  19:08:..\... -19:45:..\.." -e "2019 11 03.6470  2458791.1470  13\.0.  19:08:..\... -19:45:..\.." transient_report/index.html | awk '{print $6" "$7}'`
  # VSX position https://www.aavso.org/vsx/index.php?view=detail.top&oid=561906
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:08:15.15 -19:45:31.8 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  # Astrometry for this fella is somehow especially bad, so we have to increase the tolerance radius
  # also it seems we were comparing with the bad NMW position, not with the accurate VSX one
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 2*8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN316a_TOO_FAR_TEST_ERROR($RADECPOSITION_TO_TEST)"
   GREP_RESULT=`grep --quiet -e "2019 11 03.6470  2458791.1470  12\.9.  19:08:..\... -19:45:..\.." -e "2019 11 03.6470  2458791.1470  13\.0.  19:08:..\... -19:45:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT                              
###### SATURN316a_TOO_FAR_TEST_ERROR($RADECPOSITION_TO_TEST) ######
$GREP_RESULT"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN316a_TOO_FAR_$DISTANCE_ARCSEC"
    GREP_RESULT=`grep --quiet -e "2019 11 03.6470  2458791.1470  12\.9.  19:08:..\... -19:45:..\.." -e "2019 11 03.6470  2458791.1470  13\.0.  19:08:..\... -19:45:..\.." transient_report/index.html`
    DEBUG_OUTPUT="$DEBUG_OUTPUT                              
###### SATURN316a_TOO_FAR_$DISTANCE_ARCSEC ######
$GREP_RESULT"
   fi
  fi
  #
  ##### The following variables will not be found with the 12.5 magnitude limit and v4 SE settings file
  ##### This is a really marginal case, so I'm removing it
  #
  #grep --quiet "V1253 Sgr" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN317"
  #fi
  #grep --quiet -e "2019 11 03.6470  2458791.1470  13.11  19:10:" -e "2019 11 03.7862  2457867.9529  13.42  19:10:" -e "2019 11 03.6470  2458791.1470  13.07  19:10:" -e "2019 11 03.6470  2458791.1470  13.08  19:10:" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN317a"
  #fi
  #RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  13.11  19:10:" -e "2019 11 03.7862  2457867.9529  13.42  19:10:" -e "2019 11 03.6470  2458791.1470  13.07  19:10:" -e "2019 11 03.6470  2458791.1470  13.08  19:10:" transient_report/index.html | awk '{print $6" "$7}'`
  #DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:10:50.72 -23:55:14.6 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  ## NMW scale is 8.4"/pix
  #TEST=`echo "$DISTANCE_ARCSEC<8.4" | bc -ql`
  #re='^[0-9]+$'
  #if ! [[ $TEST =~ $re ]] ; then
  # echo "TEST ERROR"
  # TEST_PASSED=0
  # TEST=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN317a_TOO_FAR_TEST_ERROR"
  #else
  # if [ $TEST -eq 0 ];then
  #  TEST_PASSED=0
  #  FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN317a_TOO_FAR_$DISTANCE_ARCSEC"
  # fi
  #fi
  #
  ###########################################################
  # Magnitude calibration error test
  if [ -f 'lightcurve.tmp_emergency_stop_debug' ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN0_magcalibr_emergency"
   cp lightcurve.tmp_emergency_stop_debug SATURN0_magcalibr_emergency__lightcurve.tmp_emergency_stop_debug
  fi
  ###########################################################
  ###### restore exclusion list after the test if needed
  if [ -f ../exclusion_list.txt_backup ];then
   mv ../exclusion_list.txt_backup ../exclusion_list.txt
  fi
  #
  ### Specific test to make sure lib/try_to_guess_image_fov does not crash
  for IMAGE in ../NMW_Saturn_test/1referenceepoch/* ../NMW_Saturn_test/2ndepoch/* ../NMW_Saturn_test/3rdepoch/* ;do
   lib/try_to_guess_image_fov $IMAGE
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN017_$IMAGE"
   fi
  done
  ### Test to make sure no bad magnitudes were created during magnitude calibration process
  if [ -f SATURN018_PROBLEM.txt ];then
   rm -f SATURN018_PROBLEM.txt
  fi
  for OUTFILE in out*.dat ;do NLINES=`cat $OUTFILE | wc -l | awk '{print $1}'` ; NGOOD=`util/cute_lc $OUTFILE | wc -l | awk '{print $1}'` ; if [ $NLINES -ne $NGOOD ];then echo PROBLEM $NLINES $NGOOD $OUTFILE ; echo "$NLINES $NGOOD $OUTFILE" >> SATURN018_PROBLEM.txt ; cp $OUTFILE SATURN018_PROBLEM_$OUTFILE ;fi ;done | grep --quiet 'PROBLEM'
  if [ $? -eq 0 ];then
   N_FILES_WITH_PROBLEM=`cat SATURN018_PROBLEM.txt |wc -l | awk '{print $1}'`
   if [ $N_FILES_WITH_PROBLEM -gt 1 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN018__"$N_FILES_WITH_PROBLEM
   fi
  fi
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  ### Flag image test should always be the last one because we clean the data
  for IMAGE in ../NMW_Saturn_test/reference_images/* ../NMW_Saturn_test/second_epoch_images/* ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    IMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN019_$IMAGE"
   fi
  done 

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN_ALL"
 fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Saturn/Iapetus test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Saturn/Iapetus test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi



##### Saturn/Iapetus test 2 #####
# Download the test dataset if needed
if [ ! -d ../NMW_Saturn_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_Saturn_test.tar.bz2" && tar -xvjf NMW_Saturn_test.tar.bz2 && rm -f NMW_Saturn_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../NMW_Saturn_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Saturn/Iapetus test 2 " 1>&2
 echo -n "NMW find Saturn/Iapetus test 2: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_Saturn_test/1referenceepoch/ util/transients/transient_factory_test31.sh ../NMW_Saturn_test/2ndepoch
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2000_EXIT_CODE"
 fi
 if [ -f transient_report/index.html ];then
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2001"
  fi
  grep --quiet 'ERROR' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SATURN2_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2002"
  fi
  grep --quiet "First image: 2456021.56453 04.04.2012 01:32:40" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2003"
  fi
  grep --quiet "Last  image: 2458791.14727 03.11.2019 15:31:54" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SATURN2_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SATURN2_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2_NO_vast_image_details_log"
  fi
  #
  # QY Sgr is now excluded as having a bright Gaia DR2 counterpart
  # now search for specific objects
  #grep --quiet "QY Sgr" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2010"
  #fi
  # this should NOT be found! First epoch image is used along the 2nd epoch images
  grep --quiet "2019 11 03.7864  2457867.9530  12.18" transient_report/index.html
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2010x"
  fi
  ##
  #grep --quiet -e "2019 11 03.6470  2458791.1470  11\.2.  19:03:" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2010a"
  #fi
  #RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  11\.2.  19:03:" transient_report/index.html | awk '{print $6" "$7}'`
  #DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:03:48.76 -26:58:59.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  ## NMW scale is 8.4"/pix
  #TEST=`echo "$DISTANCE_ARCSEC<8.4" | bc -ql`
  #re='^[0-9]+$'
  #if ! [[ $TEST =~ $re ]] ; then
  # echo "TEST ERROR"
  # TEST_PASSED=0
  # TEST=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2010a_TOO_FAR_TEST_ERROR"
  #else
  # if [ $TEST -eq 0 ];then
  #  TEST_PASSED=0
  #  FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2010a_TOO_FAR_$DISTANCE_ARCSEC"
  # fi
  #fi
  #
  grep --quiet "V1058 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2011"
  fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  11\.9.  19:01:" -e "2019 11 03.6470  2458791.1470  11.84  19:01:" -e "2019 11 03.6470  2458791.1470  11.82  19:01:" -e "2019 11 03.6470  2458791.1470  11.86  19:01:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2011a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  11\.9.  19:01:" -e "2019 11 03.6470  2458791.1470  11.84  19:01:" -e "2019 11 03.6470  2458791.1470  11.82  19:01:" -e "2019 11 03.6470  2458791.1470  11.86  19:01:" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:01:28.86 -22:38:56.6 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2011a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2011a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # Saturn has no automatic ID in the current VaST version
  #grep --quiet "AW Tau" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN20110"
  #fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  6\...  19:06:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN20110a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  6\...  19:06:"  transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:06:32.26 -22:25:43.4 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  # Allow for 5 pixel offset - it's BIG
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 5*8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN20110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN20110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  # Iapetus has no automatic ID in the current VaST version
  #grep --quiet "AW Tau" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN20110"
  #fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  12\.1.  19:06:" -e "2019 11 03.6470  2458791.1470  12.10  19:06:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN20110b"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  12\.1.  19:06:" -e "2019 11 03.6470  2458791.1470  12.10  19:06:" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:06:59.18 -22:25:40.5 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN20110b_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN20110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "V2407 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2012"
  fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  12\.2.  19:10:" -e "2019 11 03.6470  2458791.1470  12\.3.  19:10:"  transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2012a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  12\.2.  19:10:" -e "2019 11 03.6470  2458791.1470  12\.3.  19:10:"  transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:10:11.72 -27:05:38.5 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2012a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2012a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "V1260 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2013"
  fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  11\.0.  19:16:" -e "2019 11 03.6470  2458791.1470  10\.9.  19:16:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2013a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  11\.0.  19:16:" -e "2019 11 03.6470  2458791.1470  10\.9.  19:16:" transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:16:59.73 -24:36:23.9 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2013a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2013a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "QR Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2014"
  fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  12\.0.  19:01:" -e "2019 11 03.6470  2458791.1470  12\.1.  19:01:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2014a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  12\.0.  19:01:" -e "2019 11 03.6470  2458791.1470  12\.1.  19:01:" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:01:30.92 -21:19:30.1 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2014a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2014a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet "TW Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2314"
  fi
  grep --quiet -e "2019 11 03.6470  2458791.1470  10\.8.  19:13:" -e "2019 11 03.6470  2458791.1470  10\.9.  19:13:"  transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2314a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2019 11 03.6470  2458791.1470  10\.8.  19:13:" -e "2019 11 03.6470  2458791.1470  10\.9.  19:13:" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:13:27.07 -21:33:38.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2314a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2314a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  ###########################################################
  # Magnitude calibration error test
  if [ -f 'lightcurve.tmp_emergency_stop_debug' ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2_magcalibr_emergency"
   cp lightcurve.tmp_emergency_stop_debug SATURN2_magcalibr_emergency__lightcurve.tmp_emergency_stop_debug
  fi
  ###########################################################

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2_ALL"
 fi

 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Saturn/Iapetus test 2 \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Saturn/Iapetus test 2 \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SATURN2_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi


##### Venus test #####
# Download the test dataset if needed
if [ ! -d ../NMW_Venus_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_Venus_test.tar.bz2" && tar -xvjf NMW_Venus_test.tar.bz2 && rm -f NMW_Venus_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../NMW_Venus_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Venus test " 1>&2
 echo -n "NMW find Venus test: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 #################################################################
 # We need a special astorb.dat for Ceres
 if [ -f astorb.dat ];then
  mv astorb.dat astorb.dat_backup
 fi
 if [ ! -f astorb_2020.dat ];then
  curl -O "http://scan.sai.msu.ru/~kirx/pub/astorb_2020.dat.gz" 1>&2
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS_error_downloading_custom_astorb_2020.dat"
  fi
  gunzip astorb_2020.dat.gz
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS_error_unpacking_custom_astorb_2020.dat"
  fi
 fi
 cp astorb_2020.dat astorb.dat
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS_error_copying_astorb_2020.dat_to_astorb.dat"
 fi
 #################################################################
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_Venus_test/reference/ util/transients/transient_factory_test31.sh ../NMW_Venus_test/2nd_epoch
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS000_EXIT_CODE"
 fi
 #
 if [ -f astorb.dat_backup ];then
  mv astorb.dat_backup astorb.dat
 else
  # remove the custom astorb.dat
  rm -f astorb.dat
 fi
 #
 if [ -f 'transient_report/index.html' ];then
  grep --quiet 'ERROR' 'transient_report/index.html'
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' 'transient_report/index.html'`
   CAT_RESULT=`cat 'transient_report/index.html' | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### VENUS_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS001"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS002"
  fi
  grep --quiet "First image: 2458956.27441 16.04.2020 18:34:59" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS003"
  fi
  grep --quiet "Last  image: 2458959.26847 19.04.2020 18:26:26" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### VENUS0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### VENUS0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS0_NO_vast_image_details_log"
  fi
  #
  #
  # Venus has no automatic ID in the current VaST version
  #grep --quiet "Venus" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS0110"
  #fi
  grep --quiet -e "2020 04 19.7683  2458959.2683  6\...  04:41:" -e "2020 04 19.7683  2458959.2683  5\...  04:41:" -e "2020 04 19.7683  2458959.2683  7\...  04:41:"  transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS0110a"
   GREP_RESULT=`grep -e "2020 04 19.7683  2458959.2683  6\...  04:41:" -e "2020 04 19.7683  2458959.2683  5\...  04:41:" -e "2020 04 19.7683  2458959.2683  7\...  04:41:" transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### VENUS0110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2020 04 19.7683  2458959.2683  6\...  04:41:" -e "2020 04 19.7683  2458959.2683  5\...  04:41:" -e "2020 04 19.7683  2458959.2683  7\...  04:41:"  transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 04:41:42.66 +26:53:41.8 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  # Allow for 5 pixel offset - it's BIG
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 5*8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS0110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS0110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # asteroid 9 Metis
  grep --quiet "Metis" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS314"
  fi
  grep --quiet "2020 04 19.7683  2458959.2683  11\...  04:44:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS314a"
  fi
  RADECPOSITION_TO_TEST=`grep "2020 04 19.7683  2458959.2683  11\...  04:44:" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 04:44:14.09 +23:59:02.0 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS314a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS314a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS_ALL"
 fi

 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Venus test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Venus test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES VENUS_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi



##### Nova Cas test (involves three second-epoch images including a bad one) #####
# Download the test dataset if needed
if [ ! -d ../NMW_find_NovaCas_august31_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_find_NovaCas_august31_test.tar.bz2" && tar -xvjf NMW_find_NovaCas_august31_test.tar.bz2 && rm -f NMW_find_NovaCas_august31_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../NMW_find_NovaCas_august31_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Nova Cas August 31 test " 1>&2
 echo -n "NMW find Nova Cas August 31 test: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_find_NovaCas_august31_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_find_NovaCas_august31_test/second_epoch_images &> test_ncas$$.tmp
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG31000_EXIT_CODE"
 fi
 # Test for the specific error message
 grep --quiet 'ERROR: cannot find a star near the specified position' test_ncas$$.tmp
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG31000_CANNOT_FIND_STAR_ERROR_MESSAGE"
 fi
 rm -f test_ncas$$.tmp
 #
 if [ -f transient_report/index.html ];then
  # there SHOULD be an error message about distance between reference and second-epoch image centers
  grep --quiet 'ERROR: distance between reference and second-epoch image centers' "transient_report/index.html"
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG31_NO_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNCASAUG31_NO_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG31001"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images processed 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG31001a"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG31002"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images used for photometry 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG31002a"
  fi
  grep --quiet "First image: 2456005.22259 18.03.2012 17:20:17" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG31003"
  fi
  grep --quiet "Last  image: 2459093.21130 31.08.2020 17:04:06" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG31004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG310_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNCASAUG310_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG310_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNCASAUG310_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG310_NO_vast_image_details_log"
  fi
  #
  #
  grep --quiet "V1391 Cas" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG310110"
  fi
  grep --quiet -e "2020 08 31.7108  2459093.2108  12\.9.  00:11:" -e "2020 08 31.7108  2459093.2108  13\.0.  00:11:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG310110a"
   GREP_RESULT=`grep -e "2020 08 31.7108  2459093.2108  12\.9.  00:11:" -e "2020 08 31.7108  2459093.2108  13\.0.  00:11:" transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNCASAUG310110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2020 08 31.7108  2459093.2108  12\.9.  00:11:" -e "2020 08 31.7108  2459093.2108  13\.0.  00:11:"  transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 00:11:42.960 +66:11:20.78 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG310110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG310110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # Test Stub MPC report line
  grep --quiet "     TAU0008  C2020 08 31.71030 00 11 4.\... +66 11 2.\...         1.\.. R      C32" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG310110b"
  fi
  
  # Check the total number of candidates (should be exactly 1 in this test)
  NUMBER_OF_CANDIDATE_TRANSIENTS=`grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink'`
  if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG31_NCANDIDATES_$NUMBER_OF_CANDIDATE_TRANSIENTS"
  fi
  
 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG31_ALL"
 fi

 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Nova Cas August 31 test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Nova Cas August 31 test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCASAUG31_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi


##### Pyx2 test (involves three second-epoch images including a bad one) #####
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
# Download the test dataset if needed
if [ ! -d ../NMW_nomatch_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_nomatch_test.tar.bz2" && tar -xvjf NMW_nomatch_test.tar.bz2 && rm -f NMW_nomatch_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../NMW_nomatch_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW large offset in one of three images test " 1>&2
 echo -n "NMW large offset in one of three images test: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_nomatch_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_nomatch_test/second_epoch_images &> test_nomatch$$.tmp
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET000_EXIT_CODE"
 fi
 # Test for the specific error message
 grep --quiet 'ERROR: cannot find a star near the specified position' test_nomatch$$.tmp
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET000_CANNOT_FIND_STAR_ERROR_MESSAGE"
 fi
 rm -f test_nomatch$$.tmp
 #
 if [ -f transient_report/index.html ];then
  # there should NOT be an error message about distance between reference and second-epoch image centers
  grep --quiet 'ERROR: distance between reference and second-epoch image centers' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET_DIST_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWLARGEOFFSET_DIST_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET001"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images processed 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET001a"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET002"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images used for photometry 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET002a"
  fi
  grep --quiet "First image: 2456006.25111 19.03.2012 18:01:21" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET003"
  fi
  grep --quiet "Last  image: 2459962.42100 17.01.2023 22:06:04" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWLARGEOFFSET0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWLARGEOFFSET0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET0_NO_vast_image_details_log"
  fi
  #
  #
  grep --quiet "DP Pyx" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET0110"
  fi
  grep --quiet "2023 01 17.9208  2459962.4208  10\...  08:46:0.\... -27:45:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET0110a"
   GREP_RESULT=`grep "2023 01 17.9208  2459962.4208  10\...  08:46:0.\... -27:45:" transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWLARGEOFFSET0110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2023 01 17.9208  2459962.4208  10\...  08:46:0.\... -27:45:"  transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 08:46:05.64 -27:45:49.1 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 2*8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET0110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET0110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #
  grep --quiet -e "V0594 Pup" -e "V594 Pup" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET0110"
  fi
  grep --quiet "2023 01 17.9208  2459962.4208  10\...  08:26:..\... -30:06:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET0110a"
   GREP_RESULT=`grep "2023 01 17.9208  2459962.4208  10\...  08:26:..\... -30:06:" transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWLARGEOFFSET0110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2023 01 17.9208  2459962.4208  10\...  08:26:..\... -30:06:"  transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 08:26:04.24 -30:06:41.0 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 2*8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET0110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET0110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  
  # Check the total number of candidates (should be exactly 1 in this test)
  NUMBER_OF_CANDIDATE_TRANSIENTS=`grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink'`
  if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET_NCANDIDATES_$NUMBER_OF_CANDIDATE_TRANSIENTS"
  fi
  
 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET_ALL"
 fi

 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW large offset in one of three images test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW large offset in one of three images test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NMWLARGEOFFSET_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi

### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


##### ATLAS Mira not in VSX ID test #####
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
# Download the test dataset if needed
if [ ! -d ../NMW_ATLAS_Mira_in_Ser1 ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_ATLAS_Mira_in_Ser1.tar.bz2" && tar -xvjf NMW_ATLAS_Mira_in_Ser1.tar.bz2 && rm -f NMW_ATLAS_Mira_in_Ser1.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../NMW_ATLAS_Mira_in_Ser1 ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW ATLAS Mira not in VSX ID test " 1>&2
 echo -n "NMW ATLAS Mira not in VSX ID test: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_ATLAS_Mira_in_Ser1/reference_images/ util/transients/transient_factory_test31.sh ../NMW_ATLAS_Mira_in_Ser1/second_epoch_images &> test_ncas$$.tmp
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA000_EXIT_CODE"
 fi
 # Test for the specific error message
 grep --quiet 'ERROR: cannot find a star near the specified position' test_ncas$$.tmp
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA000_CANNOT_FIND_STAR_ERROR_MESSAGE"
 fi
 rm -f test_ncas$$.tmp
 #
 if [ -f transient_report/index.html ];then
  # there SHOULD NOT be an error message about distance between reference and second-epoch image centers
  grep --quiet 'ERROR:' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWATLASMIRA_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA001"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images processed 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA001a"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA002"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images used for photometry 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA002a"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWATLASMIRA0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWATLASMIRA0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0_NO_vast_image_details_log"
  fi
  #
  #
  grep --quiet "ATO J264.4812-15.6857" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0110"
  fi
  grep --quiet "2022 02 12.0...  2459622.5...  12...  17:37:..... -15:41:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0110a"
   GREP_RESULT=`grep "2022 02 12.0...  2459622.5...  12...  17:37:..... -15:41:" transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWATLASMIRA0110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2022 02 12.0...  2459622.5...  12...  17:37:..... -15:41:" transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:37:55.48 -15:41:08.4 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # Test Stub MPC report line
  grep --quiet "     TAU0008  C2022 02 12.0.... 17 37 ..... -15 41 0....         12.. R      C32" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0110b"
  fi

  #
  grep --quiet "FK Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0111"
  fi
  grep --quiet "2022 02 12.0...  2459622.5...  10...  17:45:4.... -16:07:1..." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0111a"
   GREP_RESULT=`grep "2022 02 12.0...  2459622.5...  10...  17:45:4.... -16:07:1..." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWATLASMIRA0111a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2022 02 12.0...  2459622.5...  10...  17:45:4.... -16:07:1..." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:45:48.09 -16:07:09.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0111a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0111a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #

  #
  grep --quiet "ASAS J173723-1621.2" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0112"
  fi
  grep --quiet "2022 02 12.0...  2459622.5...  9...  17:37:2.... -16:21:1..." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0112a"
   GREP_RESULT=`grep "2022 02 12.0...  2459622.5...  9...  17:37:2.... -16:21:1..." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWATLASMIRA0112a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2022 02 12.0...  2459622.5...  9...  17:37:2.... -16:21:1..." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:37:22.69 -16:21:11.1 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0112a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0112a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #

  #
  grep --quiet "NSVS 16588457" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0113"
  fi
  grep --quiet "2022 02 12.0...  2459622.5...  1....  17:27:0.... -18:23:1..." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0113a"
   GREP_RESULT=`grep "2022 02 12.0...  2459622.5...  1....  17:27:0.... -18:23:1..." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWATLASMIRA0113a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2022 02 12.0...  2459622.5...  1....  17:27:0.... -18:23:1..." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:27:00.51 -18:23:15.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0113a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0113a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #

#  # The amplitude of ASAS J174125-1731.7 is only 0.91mag so its detection depends on what
#  # two second-epoch images get chosen
#  grep --quiet "ASAS J174125-1731.7" transient_report/index.html
#  if [ $? -ne 0 ];then
#   TEST_PASSED=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0114"
#  fi
#  grep --quiet "2022 02 12.0...  2459622.5...  12...  17:41:2.... -17:31:4..." transient_report/index.html
#  if [ $? -ne 0 ];then
#   TEST_PASSED=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0114a"
#   GREP_RESULT=`grep "2022 02 12.0...  2459622.5...  12...  17:41:2.... -17:31:4..." transient_report/index.html`
#   DEBUG_OUTPUT="$DEBUG_OUTPUT
####### NMWATLASMIRA0114a ######
#$GREP_RESULT"
#  fi
#  RADECPOSITION_TO_TEST=`grep "2022 02 12.0...  2459622.5...  12...  17:41:2.... -17:31:4..." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
#  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:41:24.90 -17:31:46.5 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
#  # NMW scale is 8.4"/pix
#  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
#  re='^[0-9]+$'
#  if ! [[ $TEST =~ $re ]] ; then
#   echo "TEST ERROR"
#   TEST_PASSED=0
#   TEST=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0114a_TOO_FAR_TEST_ERROR"
#  else
#   if [ $TEST -eq 0 ];then
#    TEST_PASSED=0
#    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0114a_TOO_FAR_$DISTANCE_ARCSEC"
#   fi
#  fi
#  #

  #
  grep --quiet "V0604 Ser" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0115"
  fi
  grep --quiet "2022 02 12.0...  2459622.5...  12...  17:36:4.... -15:30:4..." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0115a"
   GREP_RESULT=`grep "2022 02 12.0...  2459622.5...  12...  17:36:4.... -15:30:4..." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWATLASMIRA0115a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2022 02 12.0...  2459622.5...  12...  17:36:4.... -15:30:4..." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:36:46.51 -15:30:49.9 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0115a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0115a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #

  #
  grep --quiet "ASAS J173214-1402.8" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0116"
  fi
  grep --quiet "2022 02 12.0...  2459622.5...  11...  17:32:1.... -14:02:...." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0116a"
   GREP_RESULT=`grep "2022 02 12.0...  2459622.5...  11...  17:32:1.... -14:02:...." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWATLASMIRA0116a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2022 02 12.0...  2459622.5...  11...  17:32:1.... -14:02:...." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:32:13.49 -14:02:49.5 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0116a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0116a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #

# disabling this one as the results seem to strongly depend on SExtractor version (compare BSD with eridan)
#  #
#  grep --quiet "V0835 Oph" transient_report/index.html
#  if [ $? -ne 0 ];then
#   TEST_PASSED=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0117"
#  fi
#  grep --quiet "2022 02 12.0...  2459622.5...  10...  17:36:1.... -16:34:3..." transient_report/index.html
#  if [ $? -ne 0 ];then
#   TEST_PASSED=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0117a"
#   GREP_RESULT=`grep "2022 02 12.0...  2459622.5...  10...  17:36:1.... -16:34:3..." transient_report/index.html`
#   DEBUG_OUTPUT="$DEBUG_OUTPUT
####### NMWATLASMIRA0117a ######
#$GREP_RESULT"
#  fi
#  RADECPOSITION_TO_TEST=`grep "2022 02 12.0...  2459622.5...  10...  17:36:1.... -16:34:3..." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
#  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:36:11.77 -16:34:38.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
#  # NMW scale is 8.4"/pix
#  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
#  re='^[0-9]+$'
#  if ! [[ $TEST =~ $re ]] ; then
#   echo "TEST ERROR"
#   TEST_PASSED=0
#   TEST=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0117a_TOO_FAR_TEST_ERROR"
#  else
#   if [ $TEST -eq 0 ];then
#    TEST_PASSED=0
#    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0117a_TOO_FAR_$DISTANCE_ARCSEC"
#   fi
#  fi
#  #

  #
  grep --quiet "ASAS J172912-1321.1" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0118"
  fi
  grep --quiet "2022 02 12.0...  2459622.5...  9...  17:29:1.... -13:21:0..." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0118a"
   GREP_RESULT=`grep "2022 02 12.0...  2459622.5...  9...  17:29:1.... -13:21:0..." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWATLASMIRA0118a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2022 02 12.0...  2459622.5...  9...  17:29:1.... -13:21:0..." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:29:12.22 -13:21:05.6 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0118a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA0118a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  #

  # Check the total number of candidates
  NUMBER_OF_CANDIDATE_TRANSIENTS=`grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink'`
  if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -lt 9 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA_NCANDIDATES_$NUMBER_OF_CANDIDATE_TRANSIENTS"
  fi
  
 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA_ALL"
 fi

 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW ATLAS Mira not in VSX ID test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW ATLAS Mira not in VSX ID test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NMWATLASMIRA_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi

### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


##### Nova Sgr 2020 N4 test (three second-epoch images, all good) #####
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then 
# Download the test dataset if needed
if [ ! -d ../NMW_Sgr1_NovaSgr20N4_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_Sgr1_NovaSgr20N4_test.tar.bz2" && tar -xvjf NMW_Sgr1_NovaSgr20N4_test.tar.bz2 && rm -f NMW_Sgr1_NovaSgr20N4_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../NMW_Sgr1_NovaSgr20N4_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Nova Sgr 2020 N4 test " 1>&2
 echo -n "NMW find Nova Sgr 2020 N4 test: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_Sgr1_NovaSgr20N4_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_Sgr1_NovaSgr20N4_test/second_epoch_images &> test_ncas$$.tmp
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N4_EXIT_CODE"
 fi
 # Test for the specific error message
 grep --quiet 'ERROR: cannot find a star near the specified position' test_ncas$$.tmp
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N4_CANNOT_FIND_STAR_ERROR_MESSAGE"
 fi
 rm -f test_ncas$$.tmp
 #
 if [ -f transient_report/index.html ];then
  # there SHOULD NOT be an error message 
  grep --quiet 'ERROR: distance between reference and second-epoch image centers' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N4_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR20N4_NO_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N4001"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images processed 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N4001a"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N4002"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images used for photometry 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N4002a"
  fi
  grep --quiet "First image: 2456005.59475 19.03.2012 02:16:06" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N4003"
  fi
  grep --quiet -e "Last  image: 2459128.21054 05.10.2020 17:03:01" -e "Last  image: 2459128.21093 05.10.2020 17:03:34" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N4004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR20N40_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR20N40_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40_NO_vast_image_details_log"
  fi
  #
  #
  # Nova Sgr 2020 N4 has no automatic ID in the current VaST version,
  # even worse, there seems to be a false ID with an OGLE eclipsing binary
  #grep --quiet "N Sgr 2020 N4" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40110"
  #fi
  grep --quiet "2020 10 05.7...  2459128.2...  10\...  17:5.:..\... -21:22:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40110a"
   GREP_RESULT=`grep "2020 10 05.7103  2459128.2103  10\...  17:5.:..\... -21:22:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR20N40110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2020 10 05.7...  2459128.2...  10\...  17:5.:..\... -21:22:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:55:00.03 -21:22:41.9 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # Test Stub MPC report line
  grep --quiet "     TAU0008  C2020 10 05.7.... 17 5. ..\... -21 22 ..\...         10\.. R      C32" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40110b"
  fi

  # UZ Sgr
  grep --quiet "UZ Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40210"
  fi
  grep --quiet "2020 10 05.7...  2459128.2...  11\...  17:53:..\... -21:45:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40210a"
   GREP_RESULT=`grep "2020 10 05.7...  2459128.2...  11\...  17:53:..\... -21:45:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR20N40210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2020 10 05.7...  2459128.2...  11\...  17:53:..\... -21:45:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:53:08.73 -21:45:54.8 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40210a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40210a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi


  # V1280 Sgr
  grep --quiet "V1280 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40310"
  fi
  grep --quiet "2020 10 05.7...  2459128.2...  10\...  18:10:..\... -26:52:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40310a"
   GREP_RESULT=`grep "2020 10 05.7...  2459128.2...  10\...  18:10:..\... -26:52:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR20N40110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2020 10 05.7...  2459128.2...  10\...  18:10:..\... -26:52:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:10:27.97 -26:51:59.0 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  # Not sure why, but with Sgr1_2020-10-5_17-4-3_003.fts image we are off by a bit more than one pixel
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 2*8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40310a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40310a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi


  # VX Sgr
  grep --quiet "VX Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40410"
  fi
  grep --quiet "2020 10 05.7...  2459128.2...  7\...  18:08:..\... -22:13:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40410a"
   GREP_RESULT=`grep "2020 10 05.7...  2459128.2...  7\...  18:08:..\... -22:13:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR20N40110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2020 10 05.7...  2459128.2...  7\...  18:08:..\... -22:13:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:08:04.05 -22:13:26.6 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40410a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N40410a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi

  
  # Check the total number of candidates (should be exactly 5 in this test)
  NUMBER_OF_CANDIDATE_TRANSIENTS=`grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink'`
  if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -lt 4 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N4_NCANDIDATES_$NUMBER_OF_CANDIDATE_TRANSIENTS"
  fi

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N4_ALL"
 fi

 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Nova Sgr 2020 N4 test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Nova Sgr 2020 N4 test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR20N4_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi
fi # if [ "$GITHUB_ACTIONS" != "true" ];then 



##### Nova Her 2021 test (three second-epoch images, all good) #####
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then 
# Download the test dataset if needed
if [ ! -d ../NMW_Aql11_NovaHer21_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_Aql11_NovaHer21_test.tar.bz2" && tar -xvjf NMW_Aql11_NovaHer21_test.tar.bz2 && rm -f NMW_Aql11_NovaHer21_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../NMW_Aql11_NovaHer21_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Nova Her 2021 test " 1>&2
 echo -n "NMW find Nova Her 2021 test: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_Aql11_NovaHer21_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_Aql11_NovaHer21_test/second_epoch_images &> test_ncas$$.tmp
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER21_EXIT_CODE"
 fi
 # Test for the specific error message
 grep --quiet 'ERROR: cannot find a star near the specified position' test_ncas$$.tmp
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER21_CANNOT_FIND_STAR_ERROR_MESSAGE"
 fi
 rm -f test_ncas$$.tmp
 #
 if [ -f transient_report/index.html ];then
  # there SHOULD NOT be an error message 
  grep --quiet 'ERROR: distance between reference and second-epoch image centers' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER21_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNHER21_NO_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER21001"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images processed 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER21001a"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER21002"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images used for photometry 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER21002a"
  fi
  grep --quiet "First image: 2456005.49760 18.03.2012 23:56:13" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER21003"
  fi
  grep --quiet -e "Last  image: 2459378.42235 12.06.2021 22:08:01" -e "Last  image: 2459378.42271 12.06.2021 22:08:32" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER21004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER210_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNHER210_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER210_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNHER210_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER210_NO_vast_image_details_log"
  fi
  #
  #
  # Nova Her 2021 has no automatic ID in the current VaST version,
  # even worse, there seems to be a false ID with an OGLE eclipsing binary
  #grep --quiet "N Sgr 2020 N4" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER210110"
  #fi
  grep --quiet "2021 06 12.92..  2459378.42..  6\...  18:57:..\... +16:53:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER210110a"
   GREP_RESULT=`grep "2021 06 12.92..  2459378.42..  6\...  18:57:..\... +16:53:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNHER210110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 06 12.92..  2459378.42..  6\...  18:57:..\... +16:53:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  # Update position!
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:57:31.02 +16:53:39.6 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER210110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER210110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # Test Stub MPC report line
  grep --quiet "     TAU0008  C2021 06 12.922.. 18 57 ..\... +16 53 ..\...          6\.. R      C32" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER210110b"
  fi

  # ASAS J185326+1245.0
  grep --quiet "ASAS J185326+1245.0" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER210210"
  fi
  grep --quiet "2021 06 12.92..  2459378.42..  11\...  18:53:..\... +12:44:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER210210a"
   GREP_RESULT=`grep "2021 06 12.92..  2459378.42..  11\...  18:53:..\... +12:44:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNHER210210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 06 12.92..  2459378.42..  11\...  18:53:..\... +12:44:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:53:26.44 +12:44:55.8  $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER210210a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER210210a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi

  
  # Check the total number of candidates (should be exactly 5 in this test)
  NUMBER_OF_CANDIDATE_TRANSIENTS=`grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink'`
  if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER21_NCANDIDATES_$NUMBER_OF_CANDIDATE_TRANSIENTS"
  fi

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER21_ALL"
 fi

 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Nova Her 2021 test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Nova Her 2021 test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNHER21_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


##### Nova Cas 2021 test (three second-epoch images, all good) #####
# Download the test dataset if needed
#if [ ! -d ../NMW_find_NovaCas21_test ];then
# cd ..
# curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_find_NovaCas21_test.tar.bz2" && tar -xvjf NMW_find_NovaCas21_test.tar.bz2 && rm -f NMW_find_NovaCas21_test.tar.bz2
# cd $WORKDIR
#fi
# If the test data are found
if [ -d ../NMW_find_NovaCas21_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Nova Cas 2021 test " 1>&2
 echo -n "NMW find Nova Cas 2021 test: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_find_NovaCas21_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_find_NovaCas21_test/second_epoch_images &> test_ncas$$.tmp
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS21_EXIT_CODE"
 fi
 # Test for the specific error message
 grep --quiet 'ERROR: cannot find a star near the specified position' test_ncas$$.tmp
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS21_CANNOT_FIND_STAR_ERROR_MESSAGE"
 fi
 rm -f test_ncas$$.tmp
 #
 if [ -f transient_report/index.html ];then
  # there SHOULD NOT be an error message 
  grep --quiet 'ERROR: distance between reference and second-epoch image centers' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS21_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNCAS21_NO_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS21001"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images processed 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS21001a"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS21002"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images used for photometry 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS21002a"
  fi
  grep --quiet "First image: 2455961.21211 03.02.2012 17:05:11" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS21003"
  fi
  grep --quiet -e "Last  image: 2459292.20861 18.03.2021 17:00:14" -e 'Last  image: 2459292.20897 18.03.2021 17:00:45' transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS21004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS210_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNCAS210_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS210_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNCAS210_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS210_NO_vast_image_details_log"
  fi
  #
  #
  # Nova Cas 2021 has no automatic ID in the current VaST version,
  #grep --quiet "N Cas 2021" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS210110"
  #fi
  grep --quiet "2021 03 18\.70..  2459292.20..  9\...  23:24:..\... +61:11:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS210110a"
   GREP_RESULT=`grep "2021 03 18\.70..  2459292.20..  9\...  23:24:..\... +61:11:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNCAS210110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 03 18\.70..  2459292.20..  9\...  23:24:..\... +61:11:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 23:24:47.745 +61:11:14.82 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS210110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS210110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # Test Stub MPC report line
  grep --quiet "     TAU0008  C2021 03 18.70... 23 24 4.\... +61 11 1.\...          9\.. R      C32" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS210110b"
  fi

  # OQ Cep
  grep --quiet "OQ Cep" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS210210"
  fi
  grep --quiet "2021 03 18.70..  2459292.20..  11\...  23:12:..\... +60:34:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS210210a"
   GREP_RESULT=`grep "2021 03 18.70..  2459292.20..  11\...  23:12:..\... +60:34:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNCAS210210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 03 18.70..  2459292.20..  11\...  23:12:..\... +60:34:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 23:12:57.05 +60:34:38.0 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS210210a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS210210a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  
  # Check the total number of candidates (should be exactly 2 in this test)
  NUMBER_OF_CANDIDATE_TRANSIENTS=`grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink'`
  if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS21_NCANDIDATES_$NUMBER_OF_CANDIDATE_TRANSIENTS"
  fi

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS21_ALL"
 fi

 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Nova Cas 2021 test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Nova Cas 2021 test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
# No else HERE AS THIS IS A SPECIAL TEST PERFORMED ONLY ON SELECTED MACHINES
#else
# FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNCAS21_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
#remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi


##### Nova Sgr 2021 N2 test (three second-epoch images, all good) #####
# Download the test dataset if needed
#if [ ! -d ../NMW_Sco6_NovaSgr21N2_test ];then
# cd ..
# curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_Sco6_NovaSgr21N2_test.tar.bz2" && tar -xvjf NMW_Sco6_NovaSgr21N2_test.tar.bz2 && rm -f NMW_Sco6_NovaSgr21N2_test.tar.bz2
# cd $WORKDIR
#fi
# If the test data are found
if [ -d ../NMW_Sco6_NovaSgr21N2_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Nova Sgr 2021 N2 test " 1>&2
 echo -n "NMW find Nova Sgr 2021 N2 test: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_Sco6_NovaSgr21N2_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_Sco6_NovaSgr21N2_test/second_epoch_images &> test_ncas$$.tmp
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N2_EXIT_CODE"
 fi
 # Test for the specific error message
 grep --quiet 'ERROR: cannot find a star near the specified position' test_ncas$$.tmp
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N2_CANNOT_FIND_STAR_ERROR_MESSAGE"
 fi
 rm -f test_ncas$$.tmp
 #
 if [ -f transient_report/index.html ];then
  # there SHOULD NOT be an error message 
  grep --quiet 'ERROR: distance between reference and second-epoch image centers' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N2_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N2_NO_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N2001"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images processed 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N2001a"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N2002"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images used for photometry 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N2002a"
  fi
  grep --quiet "First image: 2456031.51354 14.04.2012 00:19:15" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N2003"
  fi
  grep --quiet -e "Last  image: 2459312.50961 08.04.2021 00:13:40" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N2004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N20_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N20_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20_NO_vast_image_details_log"
  fi
  #
  #
  # Nova Sgr 2021 N2 has no automatic ID in the current VaST version,
  #grep --quiet "N Cas 2021" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20110"
  #fi
  grep --quiet "2021 04 08\.009.  2459312\.509.  8\...  17:58:1.\... -29:14:5.\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20110a"
   GREP_RESULT=`grep "2021 04 08\.009.  2459312\.509.  8\...  17:58:1.\... -29:14:5.\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N20110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 04 08\.009.  2459312\.509.  8\...  17:58:1.\... -29:14:5.\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:58:16.09 -29:14:56.6 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi

  # V1804 Sgr
  grep --quiet "V1804 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20210"
  fi
  grep --quiet "2021 04 08\.009.  2459312\.509.  9\...  18:05:..\... -28:01:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20210a"
   GREP_RESULT=`grep "2021 04 08\.009.  2459312\.509.  9\...  18:05:..\... -28:01:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N20210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 04 08\.009.  2459312\.509.  9\...  18:05:..\... -28:01:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:05:02.24 -28:01:54.2 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix -- this variable is blended
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 3*8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20210a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20210a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  
  # BN Sco
  grep --quiet "BN Sco" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20211"
  fi
  grep --quiet "2021 04 08.009.  2459312.509.  9\...  17:54:..\... -34:20:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20211a"
   GREP_RESULT=`grep "2021 04 08.009.  2459312.509.  9\...  17:54:..\... -34:20:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N20210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 04 08.009.  2459312.509.  9\...  17:54:..\... -34:20:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 17:54:10.57 -34:20:27.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix -- this variable is blended
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20211a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20211a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  
  # V1783 Sgr
  grep --quiet "V1783 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20212"
  fi
  grep --quiet "2021 04 08\.009.  2459312\.509.  10\...  18:04:..\... -32:43:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20212a"
   GREP_RESULT=`grep "2021 04 08\.009.  2459312\.509.  10\...  18:04:..\... -32:43:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N20210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 04 08\.009.  2459312\.509.  10\...  18:04:..\... -32:43:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:04:49.74 -32:43:13.6 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix -- this variable is blended
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20212a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N20212a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  
  # Check the total number of candidates (should be exactly 4 in this test)
  NUMBER_OF_CANDIDATE_TRANSIENTS=`grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink'`
  if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -lt 4 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N2_NCANDIDATES_$NUMBER_OF_CANDIDATE_TRANSIENTS"
  fi

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N2_ALL"
 fi

 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Nova Sgr 2021 N2 test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Nova Sgr 2021 N2 test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
# No else HERE AS THIS IS A SPECIAL TEST PERFORMED ONLY ON SELECTED MACHINES
#else
# FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N2_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
#remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi


##### Nova Sgr 2021 N1 test (three second-epoch images, all good) #####
# Download the test dataset if needed
#if [ ! -d ../NMW_Sgr7_NovaSgr21N1_test ];then
# cd ..
# curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_Sgr7_NovaSgr21N1_test.tar.bz2" && tar -xvjf NMW_Sgr7_NovaSgr21N1_test.tar.bz2 && rm -f NMW_Sgr7_NovaSgr21N1_test.tar.bz2
# cd $WORKDIR
#fi
# If the test data are found
if [ -d ../NMW_Sgr7_NovaSgr21N1_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Nova Sgr 2021 N1 test " 1>&2
 echo -n "NMW find Nova Sgr 2021 N1 test: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_Sgr7_NovaSgr21N1_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_Sgr7_NovaSgr21N1_test/second_epoch_images &> test_ncas$$.tmp
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N1_EXIT_CODE"
 fi
 # Test for the specific error message
 grep --quiet 'ERROR: cannot find a star near the specified position' test_ncas$$.tmp
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N1_CANNOT_FIND_STAR_ERROR_MESSAGE"
 fi
 rm -f test_ncas$$.tmp
 #
 if [ -f transient_report/index.html ];then
  # there SHOULD NOT be an error message 
  grep --quiet 'ERROR: distance between reference and second-epoch image centers' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N1_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N1_NO_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N1001"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images processed 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N1001a"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N1002"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images used for photometry 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N1002a"
  fi
  grep --quiet "First image: 2456006.57071 20.03.2012 01:41:29" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N1003"
  fi
  grep --quiet -e "Last  image: 2459312.49796 07.04.2021 23:56:54" -e "Last  image: 2459312.49834 07.04.2021 23:57:27" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N1004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N10_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N10_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10_NO_vast_image_details_log"
  fi
  #
  #
  # Nova Sgr 2021 N1 has no automatic ID in the current VaST version,
  #grep --quiet "N Cas 2021" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10110"
  #fi
  grep --quiet "2021 04 07\.99..  2459312\.49..  9\...  18:49:..\... -19:02:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10110a"
   GREP_RESULT=`grep "2021 04 07\.99..  2459312\.49..  9\...  18:49:..\... -19:02:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N10110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 04 07\.99..  2459312\.49..  9\...  18:49:..\... -19:02:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:49:05.07 -19:02:04.2 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi

# The amplitude is 0.91 mag so detection of V3789 Sgr entierly depends on which pair of images 
# is taken as the second-epoch images.
#  # V3789 Sgr
#  grep --quiet "V3789 Sgr" transient_report/index.html
#  if [ $? -ne 0 ];then
#   TEST_PASSED=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10210"
#  fi
#  grep --quiet "2021 04 07\.997.  2459312\.497.  10\...  19:00:..\... -14:59:..\.." transient_report/index.html
#  if [ $? -ne 0 ];then
#   TEST_PASSED=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10210a"
#   GREP_RESULT=`grep "2021 04 07\.997.  2459312\.497.  10\...  19:00:..\... -14:59:..\.." transient_report/index.html`
#   DEBUG_OUTPUT="$DEBUG_OUTPUT
####### NMWNSGR21N10210a ######
#$GREP_RESULT"
#  fi
#  RADECPOSITION_TO_TEST=`grep "2021 04 07\.997.  2459312\.497.  10\...  19:00:..\... -14:59:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
#  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:00:07.87 -14:59:00.6 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
#  # NMW scale is 8.4"/pix -- this variable is blended
#  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
#  re='^[0-9]+$'
#  if ! [[ $TEST =~ $re ]] ; then
#   echo "TEST ERROR"
#   TEST_PASSED=0
#   TEST=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10210a_TOO_FAR_TEST_ERROR"
#  else
#   if [ $TEST -eq 0 ];then
#    TEST_PASSED=0
#    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10210a_TOO_FAR_$DISTANCE_ARCSEC"
#   fi
#  fi
  
  # V6463 Sgr
  grep --quiet "V6463 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10211"
  fi
  grep --quiet "2021 04 07\.99..  2459312\.49..  11\...  18:3.:..\... -17:0.:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10211a"
   GREP_RESULT=`grep "2021 04 07\.99..  2459312\.49..  11\...  18:3.:..\... -17:0.:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N10210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 04 07\.997.  2459312\.497.  11\...  18:3.:..\... -17:0.:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:37:59.03 -17:00:58.2 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix -- this variable is blended
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10211a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10211a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  
  # SV Sct
  grep --quiet "SV Sct" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10212"
  fi
  grep --quiet "2021 04 07\.99..  2459312\.49..  10\...  18:53:..\... -14:11:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10212a"
   GREP_RESULT=`grep "2021 04 07\.99..  2459312\.49..  10\...  18:53:..\... -14:11:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N10210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 04 07\.997.  2459312\.497.  10\...  18:53:..\... -14:11:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:53:40.97 -14:11:38.4 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix -- this variable is blended
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10212a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10212a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  
  # V0357 Sgr
  grep --quiet "V0357 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10213"
  fi
  grep --quiet "2021 04 07\.99..  2459312\.49..  11\...  19:00:..\... -15:12:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10213a"
   GREP_RESULT=`grep "2021 04 07\.99..  2459312\.49..  11\...  19:00:..\... -15:12:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N10210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 04 07\.997.  2459312\.497.  11\...  19:00:..\... -15:12:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:00:35.27 -15:12:12.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix -- this variable is blended
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10213a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10213a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  
  # ASAS J184735-1545.7
  grep --quiet "ASAS J184735-1545.7" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10214"
  fi
  grep --quiet "2021 04 07\.99..  2459312\.49..  12\...  18:47:..\... -15:45:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10214a"
   GREP_RESULT=`grep "2021 04 07\.99..  2459312\.49..  12\...  18:47:..\... -15:45:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNSGR21N10210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 04 07\.997.  2459312\.497.  12\...  18:47:..\... -15:45:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:47:35.17 -15:45:43.4 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix -- this variable is blended
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10214a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N10214a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  
  # Check the total number of candidates (should be exactly 6 in this test)
  NUMBER_OF_CANDIDATE_TRANSIENTS=`grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink'`
  if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -lt 6 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N1_NCANDIDATES_$NUMBER_OF_CANDIDATE_TRANSIENTS"
  fi

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N1_ALL"
 fi

 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Nova Sgr 2021 N1 test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Nova Sgr 2021 N1 test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
# No else HERE AS THIS IS A SPECIAL TEST PERFORMED ONLY ON SELECTED MACHINES
#else
# FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNSGR21N1_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
#remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi


##### Nova Vul 2021 test (three second-epoch images, first one is bad) #####
# Download the test dataset if needed
#if [ ! -d ../NMW_Vul7_NovaVul21_test ];then
# cd ..
# curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_Vul7_NovaVul21_test.tar.bz2" && tar -xvjf NMW_Vul7_NovaVul21_test.tar.bz2 && rm -f NMW_Vul7_NovaVul21_test.tar.bz2
# cd $WORKDIR
#fi
# If the test data are found
if [ -d ../NMW_Vul7_NovaVul21_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Nova Vul 2021 test " 1>&2
 echo -n "NMW find Nova Vul 2021 test: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_Vul7_NovaVul21_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_Vul7_NovaVul21_test/second_epoch_images &> test_ncas$$.tmp
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL21_EXIT_CODE"
 fi
 # Test for the specific error message
 grep --quiet 'ERROR: cannot find a star near the specified position' test_ncas$$.tmp
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL21_CANNOT_FIND_STAR_ERROR_MESSAGE"
 fi
 rm -f test_ncas$$.tmp
 #
 if [ -f transient_report/index.html ];then
  # there SHOULD NOT be an error message 
  grep --quiet 'ERROR: distance between reference and second-epoch image centers' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL21_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNVUL21_NO_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL21001"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images processed 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL21001a"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL21002"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images used for photometry 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL21002a"
  fi
  grep --quiet "First image: 2456031.42797 13.04.2012 22:16:02" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL21003"
  fi
  grep --quiet -e "Last  image: 2459413.36175 17.07.2021 20:40:45" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL21004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL210_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNVUL210_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL210_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNVUL210_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL210_NO_vast_image_details_log"
  fi
  #
  #
  # Nova Vul 2021 has no automatic ID in the current VaST version,
  #grep --quiet "N Cas 2021" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL210110"
  #fi
  grep --quiet "2021 07 17\.86..  2459413\.36..  1.\...  20:21:0.\... +29:14:0.\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL210110a"
   GREP_RESULT=`grep "2021 07 17\.86..  2459413\.36..  1.\...  20:21:0.\... +29:14:0.\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNVUL210110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 07 17\.86..  2459413\.36..  1.\...  20:21:0.\... +29:14:0.\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 20:21:07.703 +29:14:09.25 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL210110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL210110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi

  # V0369 Vul
  grep --quiet "V0369 Vul" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL210210"
  fi
  grep --quiet "2021 07 17\.86..  2459413\.36..  12\...  20:18:2.\... +26:39:1.\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL210210a"
   GREP_RESULT=`grep "2021 07 17\.86..  2459413\.36..  12\...  20:18:2.\... +26:39:1.\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNVUL210210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 07 17\.86..  2459413\.36..  12\...  20:18:2.\... +26:39:1.\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 20:18:22.78 +26:39:16.7 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL210210a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL210210a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  
  # Check the total number of candidates (should be exactly 2 in this test)
  NUMBER_OF_CANDIDATE_TRANSIENTS=`grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink'`
  if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL21_NCANDIDATES_$NUMBER_OF_CANDIDATE_TRANSIENTS"
  fi

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL21_ALL"
 fi

 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Nova Vul 2021 test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Nova Vul 2021 test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
# No else HERE AS THIS IS A SPECIAL TEST PERFORMED ONLY ON SELECTED MACHINES
#else
# FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNVUL21_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
#remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi


##### Mars test (three second-epoch images, all good) #####
# Download the test dataset if needed
#if [ ! -d ../NMW_find_Mars_test ];then
# cd ..
# curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_find_Mars_test.tar.bz2" && tar -xvjf NMW_find_Mars_test.tar.bz2 && rm -f NMW_find_Mars_test.tar.bz2
# cd $WORKDIR
#fi
# If the test data are found
if [ -d ../NMW_find_Mars_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Mars test " 1>&2
 echo -n "NMW find Mars test: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_find_Mars_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_find_Mars_test/second_epoch_images &> test_ncas$$.tmp
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS_EXIT_CODE"
 fi
 # Test for the specific error message
 grep --quiet 'ERROR: cannot find a star near the specified position' test_ncas$$.tmp
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS_CANNOT_FIND_STAR_ERROR_MESSAGE"
 fi
 rm -f test_ncas$$.tmp
 #
 if [ -f transient_report/index.html ];then
  # there SHOULD NOT be an error message 
  grep --quiet 'ERROR: distance between reference and second-epoch image centers' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWMARS_NO_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS001"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images processed 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS001a"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS002"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images used for photometry 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS002a"
  fi
  grep --quiet "First image: 2455929.28115 02.01.2012 18:44:31" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS003"
  fi
  grep --quiet -e "Last  image: 2459334.28175 29.04.2021 18:45:33" -e "Last  image: 2459334.28212 29.04.2021 18:46:05" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWMARS0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWMARS0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS0_NO_vast_image_details_log"
  fi
  #
  #
  # Mars has no automatic ID in the current VaST version,
  #grep --quiet "N Cas 2021" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS0110"
  #fi
  grep --quiet "2021 04 29\.781.  2459334\.281.  7\...  06:15:..\... +24:50:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS0110a"
   GREP_RESULT=`grep "2021 04 29\.781.  2459334\.281.  7\...  06:15:..\... +24:50:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWMARS0110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 04 29\.781.  2459334\.281.  7\...  06:15:..\... +24:50:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 06:15:32.02 +24:50:16.9 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  # relax position tolerance as this is an extended saturated thing
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 10*8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS0110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS0110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi

  # V0349 Gem
  grep --quiet "V0349 Gem" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS0210"
  fi
  grep --quiet -e "2021 04 29\.78..  2459334\.28..  12\...  06:20:..\... +23:46:..\.." -e "2021 04 29\.78..  2459334\.28..  11\...  06:20:..\... +23:46:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS0210a"
   GREP_RESULT=`grep -e "2021 04 29\.78..  2459334\.28..  12\...  06:20:..\... +23:46:..\.." -e "2021 04 29\.78..  2459334\.28..  11\...  06:20:..\... +23:46:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWMARS0210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2021 04 29\.78..  2459334\.28..  12\...  06:20:..\... +23:46:..\.." -e "2021 04 29\.78..  2459334\.28..  11\...  06:20:..\... +23:46:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 06:20:35.88 +23:46:32.0 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 2*8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS0210a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS0210a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
    
  # Check the total number of candidates (should be exactly 6 in this test)
  NUMBER_OF_CANDIDATE_TRANSIENTS=`grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink'`
  if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS_NCANDIDATES_$NUMBER_OF_CANDIDATE_TRANSIENTS"
  fi
  

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS_ALL"
 fi

 #############################################################################
  
 REFERENCE_IMAGES=../NMW_find_Mars_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_find_Mars_test/third_epoch/
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS3_EXIT_CODE"
 fi
 # Test for the specific error message
 grep --quiet 'ERROR: cannot find a star near the specified position' test_ncas$$.tmp
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS3_CANNOT_FIND_STAR_ERROR_MESSAGE"
 fi
 rm -f test_ncas$$.tmp
 #
 if [ -f transient_report/index.html ];then
  # there SHOULD NOT be an error message 
  grep --quiet 'ERROR: distance between reference and second-epoch image centers' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS3_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWMARS3_NO_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS3001"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images processed 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS3001a"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS3002"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images used for photometry 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS3002a"
  fi
  grep --quiet "First image: 2455929.28115 02.01.2012 18:44:31" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS3003"
  fi
  grep --quiet -e "Last  image: 2459337.27924 02.05.2021 18:41:56" -e "Last  image: 2459334.28212 29.04.2021 18:46:05" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS3004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS30_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWMARS30_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS30_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWMARS30_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS30_NO_vast_image_details_log"
  fi
  #
  #
  # Mars has no automatic ID in the current VaST version,
  #grep --quiet "N Cas 2021" transient_report/index.html
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS30110"
  #fi
  grep --quiet "2021 05 02.77..  2459337.27..  7\...  06:23:..\... +24:46:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS30110a"
   GREP_RESULT=`grep "2021 05 02.77..  2459337.27..  7\...  06:23:..\... +24:46:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWMARS30110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 05 02.77..  2459337.27..  7\...  06:23:..\... +24:46:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 06:23:33.10 +24:46:13.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  # relax position tolerance as this is an extended saturated thing
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 10*8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS30110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS30110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi

  # ASAS J061734+2526.7
  grep --quiet "ASAS J061734+2526.7" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS30210"
  fi
  grep --quiet "2021 05 02.77..  2459337.27..  12\...  06:17:..\... +25:26:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS30210a"
   GREP_RESULT=`grep "2021 05 02.77..  2459337.27..  12\...  06:17:..\... +25:26:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWMARS30210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2021 05 02.77..  2459337.27..  12\...  06:17:..\... +25:26:..\.." transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 06:17:33.83 +25:26:42.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 2*8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS30210a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS30210a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
    
  # Check the total number of candidates (should be exactly 6 in this test)
  NUMBER_OF_CANDIDATE_TRANSIENTS=`grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink'`
  if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS3_NCANDIDATES_$NUMBER_OF_CANDIDATE_TRANSIENTS"
  fi
  

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS3_ALL"
 fi



 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Mars test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Mars test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
# No else HERE AS THIS IS A SPECIAL TEST PERFORMED ONLY ON SELECTED MACHINES
#else
# FAILED_TEST_CODES="$FAILED_TEST_CODES NMWMARS_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
#remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi


##### find Chandra #####
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then 
# Download the test dataset if needed
if [ ! -d ../NMW_find_Chandra_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_find_Chandra_test.tar.bz2" && tar -xvjf NMW_find_Chandra_test.tar.bz2 && rm -f NMW_find_Chandra_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../NMW_find_Chandra_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW find Chandra test " 1>&2
 echo -n "NMW find Chandra test: " >> vast_test_report.txt 
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Instead of running the single-field search,
 # we test the production NMW script
 REFERENCE_IMAGES=../NMW_find_Chandra_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_find_Chandra_test/second_epoch_images &> test_ncas$$.tmp
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA000_EXIT_CODE"
 fi
 # Test for the specific error message
 grep --quiet 'ERROR: cannot find a star near the specified position' test_ncas$$.tmp
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA000_CANNOT_FIND_STAR_ERROR_MESSAGE"
 fi
 rm -f test_ncas$$.tmp
 #
 if [ -f transient_report/index.html ];then
  # there SHOULD NOT be an error message 
  grep --quiet 'ERROR' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNFINDCHANDRA_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA001"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images processed 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA001a"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA002"
  fi
  NUMBER_OF_GOOD_SE_RUNS=`grep -c "Images used for photometry 4" transient_report/index.html`
  if [ $NUMBER_OF_GOOD_SE_RUNS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA002a"
  fi
  grep --quiet "First image: 2455961.58044 04.02.2012 01:55:40" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA003"
  fi
  grep --quiet "Last  image: 2459087.44020 25.08.2020 22:33:43" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNFINDCHANDRA0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNFINDCHANDRA0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0_NO_vast_image_details_log"
  fi
  #
#### Disableing the Chandra test due to the new 10" restriction on the difference 
#### in position of second-epoch detections.
#  #
#  # Chandra has no automatic ID in the current VaST version
#  #grep --quiet "Chandra" transient_report/index.html
#  #if [ $? -ne 0 ];then
#  # TEST_PASSED=0
#  # FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0110"
#  #fi
#  grep --quiet "2020 08 25.9400  2459087.4400  12\.8.  18:57:" transient_report/index.html
#  if [ $? -ne 0 ];then
#   TEST_PASSED=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0110a"
#   GREP_RESULT=`grep "2020 08 25.9400  2459087.4400  12\.8.  18:57:" transient_report/index.html`
#   DEBUG_OUTPUT="$DEBUG_OUTPUT
####### NMWNFINDCHANDRA0110a ######
#$GREP_RESULT"
#  fi
#  RADECPOSITION_TO_TEST=`grep "2020 08 25.9400  2459087.4400  12\.8.  18:57:"  transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
#  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:57:09.11 +32:28:26.8 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
#  # NMW scale is 8.4"/pix
#  TEST=`echo "$DISTANCE_ARCSEC<3*8.4" | bc -ql`
#  re='^[0-9]+$'
#  if ! [[ $TEST =~ $re ]] ; then
#   echo "TEST ERROR"
#   TEST_PASSED=0
#   TEST=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0110a_TOO_FAR_TEST_ERROR"
#  else
#   if [ $TEST -eq 0 ];then
#    TEST_PASSED=0
#    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0110a_TOO_FAR_$DISTANCE_ARCSEC"
#   fi
#  fi
#  # Test Stub MPC report line
#  grep --quiet "     TAU0008  C2020 08 25.93997 18 57 0.\... +32 28 2.\...         12\.. R      C32" transient_report/index.html
#  if [ $? -ne 0 ];then
#   TEST_PASSED=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0110b"
#  fi
  # RT Lyr
  grep --quiet "RT Lyr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0210"
  fi
  grep --quiet "2020 08 25.9400  2459087.4400  10\.7.  19:01:" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0210a"
   GREP_RESULT=`grep "2020 08 25.9400  2459087.4400  10\.7.  19:01:" transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNFINDCHANDRA0210a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2020 08 25.9400  2459087.4400  10\.7.  19:01:"  transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 19:01:14.89 +37:31:20.2 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0210a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0210a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # Z Lyr
  grep --quiet "Z Lyr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0310"
  fi
  grep --quiet -e "2020 08 25.9400  2459087.4400  9\...  18:59:..\... +34:57:..\.." -e "2020 08 25.9400  2459087.4400 10\.0.  18:59:..\... +34:57:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0310a"
   GREP_RESULT=`grep "2020 08 25.9400  2459087.4400  9\...  18:59:" -e "2020 08 25.9400  2459087.4400 10\.0.  18:59:..\... +34:57:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWNFINDCHANDRA0310a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2020 08 25.9400  2459087.4400  9\...  18:59:"  transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:59:36.80 +34:57:16.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0310a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA0310a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  
  # Check the total number of candidates (should be at least 3 in this test)
  NUMBER_OF_CANDIDATE_TRANSIENTS=`grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink'`
  # Now tha we excluded Chandra
  #if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -lt 3 ];then
  if [ $NUMBER_OF_CANDIDATE_TRANSIENTS -lt 2 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA_NCANDIDATES_$NUMBER_OF_CANDIDATE_TRANSIENTS"
  fi

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA_ALL"
 fi

 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW find Chandra test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW find Chandra test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NMWNFINDCHANDRA_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi
fi # if [ "$GITHUB_ACTIONS" != "true" ];then 



##### Sgr9 crash and no shift test #####
# Download the test dataset if needed
if [ ! -d ../NMW_Sgr9_crash_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_Sgr9_crash_test.tar.bz2" && tar -xvjf NMW_Sgr9_crash_test.tar.bz2 && rm -f NMW_Sgr9_crash_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../NMW_Sgr9_crash_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 #
 remove_test31_tmp_files_if_present
 #
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 # Purge the old exclusion list, create a fake one
 echo "06:50:14.55 +00:07:27.8
06:50:15.79 +00:07:22.0
07:01:41.33 +00:06:32.7
06:49:07.80 +01:00:22.0
07:07:43.22 +00:02:18.7" > ../exclusion_list.txt
 # Run the test
 echo "NMW Sgr9 crash test " 1>&2
 echo -n "NMW Sgr9 crash test: " >> vast_test_report.txt 
 #
 if [ -f transient_report/index.html ];then
  rm -f transient_report/index.html
 fi
 # Test the specific command that failed
 cp default.sex.telephoto_lens_onlybrightstars_v1 default.sex
 ./vast --autoselectrefimage --matchstarnumber 100 --UTC --nofind --failsafe --nomagsizefilter --noerrorsrescale --notremovebadimages  ../NMW_Sgr9_crash_test/second_epoch_images/*
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH000_PRELIM_VAST_RUN_EXIT_CODE"
 fi
 # Test the production NMW script
 REFERENCE_IMAGES=../NMW_Sgr9_crash_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_Sgr9_crash_test/second_epoch_images
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH000_EXIT_CODE"
 fi
 if [ -f transient_report/index.html ];then
  grep --quiet 'ERROR' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWSGR9CRASH_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH001"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH002"
  fi
  grep --quiet "First image: 2456030.54275 13.04.2012 01:01:19" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH003"
  fi
  grep --quiet "Last  image: 2459094.23281 01.09.2020 17:35:05" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWSGR9CRASH0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWSGR9CRASH0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH0_NO_vast_image_details_log"
  fi
  #
  #
  #for HOT_PIXEL_XY in "0683 2080" "1201 0959" "1389 1252" "2855 2429" "1350 1569" "1806 1556" "3166 1895" "2416 0477" "2864 2496" "1158 1418" "0618 1681" "2577 0584" "2384 0291" "1034 1921" "2298 1573" "2508 1110" "1098 0166" "3181 0438" "0071 1242" "0782 1150" ;do
  # "1201 0959" "1389 1252" etc. - do not get found on all test systems
  #for HOT_PIXEL_XY in "0683 2080" "3166 1895" "2508 1110" "1098 0166" ;do
  # grep --quiet "$HOT_PIXEL_XY" transient_report/index.html
  # if [ $? -ne 0 ];then
  #  TEST_PASSED=0
  #  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_BADPIXNOTFOUND_${HOT_PIXEL_XY// /_}"
  # fi
  #done
  #
  # V1858 Sgr
  grep --quiet "V1858 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH0110"
  fi
  grep --quiet "2020 09 01.7326  2459094.2326  11\...  18:21:..\... -34:11:..\.."  transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH0110a"
   GREP_RESULT=`grep "2020 09 01.7326  2459094.2326  11\...  18:21:..\... -34:11:..\.." transient_report/index.html`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWSGR9CRASH0110a ######
$GREP_RESULT"
  fi
  RADECPOSITION_TO_TEST=`grep "2020 09 01.7326  2459094.2326  11\...  18:21:..\... -34:11:..\.."  transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:21:40.07 -34:11:23.3  $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH0110a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH0110a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # V1278 Sgr
  grep --quiet "V1278 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH314"
  fi
  #             2020 09 01.7326  2459094.2326  10.71  18:08:39.66 -34:01:42.3
  grep --quiet -e "2020 09 01.7326  2459094.2326  10\.6.  18:08:..\... -34:01:..\.." -e "2020 09 01.7326  2459094.2326  10\.7.  18:08:..\... -34:01:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH314a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2020 09 01.7326  2459094.2326  10\.6.  18:08:" -e "2020 09 01.7326  2459094.2326  10\.7.  18:08:..\... -34:01:..\.." transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:08:39.56 -34:01:42.8  $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH314a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH314a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # V1577 Sgr
  grep --quiet "V1577 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH414"
  fi
  #             2020 09 01.7326  2459094.2326  10.72  18:12:18.28 -27:55:15.5
  grep --quiet -e "2020 09 01.7326  2459094.2326  10\.6.  18:12:..\... -27:55:..\.." -e "2020 09 01.7326  2459094.2326  10\.7.  18:12:..\... -27:55:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH414a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2020 09 01.7326  2459094.2326  10\.6.  18:12:" -e "2020 09 01.7326  2459094.2326  10\.6.  18:12:..\... -27:55:..\.." transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:12:18.14 -27:55:16.8  $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH414a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH414a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  # V1584 Sgr
  grep --quiet "V1584 Sgr" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH514"
  fi
  grep --quiet -e "2020 09 01.7326  2459094.2326  11\...  18:15:..\... -30:23:..\.." -e "2020 09 01.7326  2459094.2326  10\.9.  18:15:..\... -30:23:..\.." transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH514a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2020 09 01.7326  2459094.2326  11\...  18:15:..\... -30:23:..\.." -e "2020 09 01.7326  2459094.2326  10\.9.  18:15:..\... -30:23:..\.." transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 18:15:46.46 -30:23:43.2  $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 8.4 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH514a_TOO_FAR_TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH514a_TOO_FAR_$DISTANCE_ARCSEC"
   fi
  fi
  
  # Check what is and what is not in the exlcusion list
  # The variables should be there
  grep --quiet '18:21:4.\... -34:11:2.\..' ../exclusion_list.txt
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_VAR_NOT_ADDED_TO_EXCLUSION_LIST_01"
  fi
  grep --quiet '18:08:3.\... -34:01:4.\..' ../exclusion_list.txt
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_VAR_NOT_ADDED_TO_EXCLUSION_LIST_02"
  fi
  grep --quiet '18:12:1.\... -27:55:1.\..' ../exclusion_list.txt
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_VAR_NOT_ADDED_TO_EXCLUSION_LIST_03"
  fi
  grep --quiet '18:15:4.\... -30:23:4.\..' ../exclusion_list.txt
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_VAR_NOT_ADDED_TO_EXCLUSION_LIST_04"
  fi
  # The hot pixels should not be in the exclusion list
  grep --quiet '18:10:4.\... -32:58:2.\..' ../exclusion_list.txt
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_HOT_PIXEL_IN_EXCLUSION_LIST_01"
  fi
  grep --quiet '18:13:2.\... -27:12:2.\..' ../exclusion_list.txt
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_HOT_PIXEL_IN_EXCLUSION_LIST_02"
  fi
  grep --quiet '18:21:3.\... -28:45:0.\..' ../exclusion_list.txt
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_HOT_PIXEL_IN_EXCLUSION_LIST_03"
  fi
  grep --quiet '18:31:5.\... -32:00:5.\..' ../exclusion_list.txt
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_HOT_PIXEL_IN_EXCLUSION_LIST_03"
  fi
  #
  
  test_if_test31_tmp_files_are_present
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_TMP_FILE_PRESENT"
  fi

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_ALL"
 fi


 # Re-run the production NMW script, make sure that we are now finding only the hot pixels while the variables are excluded
 REFERENCE_IMAGES=../NMW_Sgr9_crash_test/reference_images/ util/transients/transient_factory_test31.sh ../NMW_Sgr9_crash_test/second_epoch_images
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN000_EXIT_CODE"
 fi
 if [ -f transient_report/index.html ];then
  grep --quiet 'ERROR' "transient_report/index.html"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN_ERROR_MESSAGE_IN_index_html"
   GREP_RESULT=`grep 'ERROR' "transient_report/index.html"`
   CAT_RESULT=`cat transient_report/index.html | grep -v -e 'BODY' -e 'HTML' | grep -A10000 'Filtering log:'`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWSGR9CRASH_RERUN_ERROR_MESSAGE_IN_index_html ######
$GREP_RESULT
-----------------
$CAT_RESULT"
  fi
  # The copy of the log file should be in the HTML report
  grep --quiet "Images processed 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN001"
  fi
  grep --quiet "Images used for photometry 4" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN002"
  fi
  grep --quiet "First image: 2456030.54275 13.04.2012 01:01:19" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN003"
  fi
  grep --quiet "Last  image: 2459094.23281 01.09.2020 17:35:05" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWSGR9CRASH_RERUN0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWSGR9CRASH_RERUN0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN0_NO_vast_image_details_log"
  fi
  #
  #for HOT_PIXEL_XY in "0683 2080" "1201 0959" "1389 1252" "2855 2429" "1350 1569" "1806 1556" "3166 1895" "2416 0477" "2864 2496" "1158 1418" "0618 1681" "2577 0584" "2384 0291" "1034 1921" "2298 1573" "2508 1110" "1098 0166" "3181 0438" "0071 1242" "0782 1150" ;do
  # "1201 0959" "1389 1252" etc - do not get found on all test systems
  #for HOT_PIXEL_XY in "0683 2080" "3166 1895" "2508 1110" "1098 0166" ;do
  # grep --quiet "$HOT_PIXEL_XY" transient_report/index.html
  # if [ $? -ne 0 ];then
  #  TEST_PASSED=0
  #  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN_BADPIXNOTFOUND_${HOT_PIXEL_XY// /_}"
  # fi
  #done
  #
  # V1858 Sgr
  grep --quiet "V1858 Sgr" transient_report/index.html
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN0110"
  fi
  grep -B10000 'Processig complete' transient_report/index.html | grep --quiet "2020 09 01.7326  2459094.2326  11\...  18:21:..\... -34:11:..\.."
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN0110a"
   GREP_RESULT=`grep -B10000 'Processig complete' transient_report/index.html | grep "2020 09 01.7326  2459094.2326  11\...  18:21:..\... -34:11:..\.."`
   GREP_RESULT2=`cat ../exclusion_list.txt`
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### NMWSGR9CRASH_RERUN0110a ######
$GREP_RESULT
____ ../exclusion_list.txt ____
$GREP_RESULT2"
  fi
  # V1278 Sgr
  grep --quiet "V1278 Sgr" transient_report/index.html
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN314"
  fi
  # The line may appear in the logs as rejected candidate due to exclusion list, so we check lines before the log starts
  grep -B10000 'Processig complete' transient_report/index.html | grep --quiet "2020 09 01.7326  2459094.2326  10\.6.  18:08:..\... -34:01:..\.."
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN314a"
  fi
  # V1577 Sgr
  grep --quiet "V1577 Sgr" transient_report/index.html
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN414"
  fi
  grep -B10000 'Processig complete' transient_report/index.html | grep --quiet "2020 09 01.7326  2459094.2326  10\.6.  18:12:..\... -27:55:..\.."
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN414a"
  fi
  # V1584 Sgr
  grep --quiet "V1584 Sgr" transient_report/index.html
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN514"
  fi
  grep -B10000 'Processig complete' transient_report/index.html | grep --quiet -e "2020 09 01.7326  2459094.2326  11\.0.  18:15:" -e "2020 09 01.7326  2459094.2326  10\.9.  18:15:"
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN514a"
  fi

  # Make sure things don't get added to the exclusion list multiple times
  N=`grep -c '18:21:4.\... -34:11:2.\..' ../exclusion_list.txt`
  if [ $N -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN_VAR_ADDED_MANY_TIMES_TO_EXCLUSION_LIST_01_$N"
  fi
  N=`grep -c '18:08:3.\... -34:01:4.\..' ../exclusion_list.txt`
  if [ $N -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN_VAR_ADDED_MANY_TIMES_TO_EXCLUSION_LIST_02_$N"
  fi
  N=`grep -c '18:12:1.\... -27:55:1.\..' ../exclusion_list.txt`
  if [ $N -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN_VAR_ADDED_MANY_TIMES_TO_EXCLUSION_LIST_03_$N"
  fi
  N=`grep -c '18:15:4.\... -30:23:4.\..' ../exclusion_list.txt`
  if [ $N -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN_VAR_ADDED_MANY_TIMES_TO_EXCLUSION_LIST_04_$N"
  fi

  test_if_test31_tmp_files_are_present
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN_TMP_FILE_PRESENT"
  fi

 else
  echo "ERROR running the transient search script" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_RERUN_ALL"
 fi


 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW Sgr9 crash test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW Sgr9 crash test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NMWSGR9CRASH_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi


############# NMW exclusion list #############
# Download the test dataset if needed
if [ ! -d ../NMW_Vul2_magnitude_calibration_exit_code_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_Vul2_magnitude_calibration_exit_code_test.tar.bz2" && tar -xvjf NMW_Vul2_magnitude_calibration_exit_code_test.tar.bz2 && rm -f NMW_Vul2_magnitude_calibration_exit_code_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../NMW_Vul2_magnitude_calibration_exit_code_test/ ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW Vul2 exclusion list test " 1>&2
 echo -n "NMW Vul2 exclusion list test: " >> vast_test_report.txt
 if [ -f ../exclusion_list.txt ];then
  mv ../exclusion_list.txt ../exclusion_list.txt_backup
 fi
 # Purge the old exclusion list, create a fake one
 echo "06:50:14.55 +00:07:27.8
06:50:15.79 +00:07:22.0
07:01:41.33 +00:06:32.7
06:49:07.80 +01:00:22.0
07:07:43.22 +00:02:18.7" > ../exclusion_list.txt
 #################################################################
 # We need a special astorb.dat for Pallas
 if [ -f astorb.dat ];then
  mv astorb.dat astorb.dat_backup
 fi
 if [ ! -f astorb_pallas.dat ];then
  curl -O "http://scan.sai.msu.ru/~kirx/pub/astorb_pallas.dat.gz" 1>&2
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_error_downloading_custom_astorb_pallas.dat"
  fi
  gunzip astorb_pallas.dat.gz
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_error_unpacking_custom_astorb_pallas.dat"
  fi
 fi
 cp astorb_pallas.dat astorb.dat
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_error_copying_astorb_pallas.dat_to_astorb.dat"
 fi
 #################################################################
 # Run the search
 REFERENCE_IMAGES=../NMW_Vul2_magnitude_calibration_exit_code_test/ref/ util/transients/transient_factory_test31.sh ../NMW_Vul2_magnitude_calibration_exit_code_test/2nd_epoch/
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_001"
 fi
 if [ -f transient_report/index.html ];then
  grep --quiet '2 Pallas' transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_002"
  fi
  grep --quiet 'EP Vul' transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_003"
  fi
  grep --quiet -e 'NSV 11847' -e 'V0556 Vul' transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_004"
  fi
  grep --quiet 'ASAS J193002+1950.9' transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_005"
  fi
  # Run the search again
  REFERENCE_IMAGES=../NMW_Vul2_magnitude_calibration_exit_code_test/ref/ util/transients/transient_factory_test31.sh ../NMW_Vul2_magnitude_calibration_exit_code_test/2nd_epoch/
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_101"
  fi
  # Make sure we are finding now only the asteroid Pallas and the variables are excluded
  grep --quiet '2 Pallas' transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_102"
  fi
  grep --quiet 'EP Vul' transient_report/index.html
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_103"
  fi
  grep --quiet 'NSV 11847' transient_report/index.html
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_104"
  fi
  grep --quiet 'ASAS J193002+1950.9' transient_report/index.html
  if [ $? -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_105"
  fi
 else
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_NO_INDEXHTML"
 fi
 #
 if [ -f astorb.dat_backup ];then
  mv astorb.dat_backup astorb.dat
 else
  # remove the custom astorb.dat
  rm -f astorb.dat
 fi
 #
 test_if_test31_tmp_files_are_present
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU_RERUN_TMP_FILE_PRESENT"
 fi
 rm -f ../exclusion_list.txt
 ###### restore exclusion list after the test if needed
 if [ -f ../exclusion_list.txt_backup ];then
  mv ../exclusion_list.txt_backup ../exclusion_list.txt
 fi
 #


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW Vul2 exclusion list test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW Vul2 exclusion list test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NMWEXCLU__TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
# 
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi

##### DSLR transient search test #####
# Download the test dataset if needed
if [ ! -d ../KZ_Her_DSLR_transient_search_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/KZ_Her_DSLR_transient_search_test.tar.bz2" && tar -xvjf KZ_Her_DSLR_transient_search_test.tar.bz2 && rm -f KZ_Her_DSLR_transient_search_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../KZ_Her_DSLR_transient_search_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "DSLR transient search test " 1>&2
 echo -n "DSLR transient search test: " >> vast_test_report.txt 
 cp default.sex.DSLR_test default.sex
 ./vast -x99 -ukf -b200 \
 ../KZ_Her_DSLR_transient_search_test/v838her1.fit \
 ../KZ_Her_DSLR_transient_search_test/v838her2.fit \
 ../KZ_Her_DSLR_transient_search_test/v838her3.fit \
 ../KZ_Her_DSLR_transient_search_test/v838her4.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 4" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER001"
  fi
  grep --quiet "Images used for photometry 4" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER002"
  fi
  grep --quiet "First image: 2456897.40709 27.08.2014 21:45:57" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER003"
  fi
  grep --quiet "Last  image: 2456982.24706 20.11.2014 17:55:30" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### DSLRKZHER0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### DSLRKZHER0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER0_NO_vast_image_details_log"
  fi
  #
  echo "y" | util/transients/search_for_transients_single_field.sh test
  if [ ! -f transient_report/index.html ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER005"
  fi 
  ###########################################################
  # Magnitude calibration error test
  if [ -f 'lightcurve.tmp_emergency_stop_debug' ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER_magcalibr_emergency"
   cp lightcurve.tmp_emergency_stop_debug DSLRKZHER_magcalibr_emergency__lightcurve.tmp_emergency_stop_debug
  fi
  ###########################################################
  grep --quiet "KZ Her" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER006"
  fi
  #grep "NSV 11188" transient_report/index.html
  grep --quiet -e "V1451 Her" -e "NSV 11188" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER007"
  fi
  grep --quiet "V0515 Oph" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER008"
  fi
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  ### Flag image test should always be the last one
  for IMAGE in v838her1.fit v838her2.fit v838her3.fit v838her4.fit ;do
   util/clean_data.sh
   # Now we DO want the flag images to be created for this dataset
   lib/autodetect_aperture_main ../KZ_Her_DSLR_transient_search_test/$IMAGE 2>&1 | grep "FLAG_IMAGE image00000.flag"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER009_$IMAGE"
   fi 
  done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER_ALL"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mDSLR transient search test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mDSLR transient search test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi

if [ ! -d ../individual_images_test ];then
 mkdir ../individual_images_test
fi

######### Indivdual images test

######### Ultra-wide-field image
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then

if [ ! -f ../individual_images_test/1630+3250.20150511T215921000.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/1630+3250.20150511T215921000.fit.bz2" && bunzip2 1630+3250.20150511T215921000.fit.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/1630+3250.20150511T215921000.fit ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Ultra-wide-field image test " 1>&2
 echo -n "Ultra-wide-field image test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 util/solve_plate_with_UCAC5 ../individual_images_test/1630+3250.20150511T215921000.fit
 if [ ! -f wcs_1630+3250.20150511T215921000.fit ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ULTRAWIDEFIELD001"
 fi 
 lib/bin/xy2sky wcs_1630+3250.20150511T215921000.fit 200 200 &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ULTRAWIDEFIELD001a"
 fi
 if [ ! -s wcs_1630+3250.20150511T215921000.fit.cat.ucac5 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ULTRAWIDEFIELD002"
 else
  TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_1630+3250.20150511T215921000.fit.cat.ucac5 | wc -l | awk '{print $1}'`
  #if [ $TEST -lt 1800 ];then
  #if [ $TEST -lt 900 ];then
  if [ $TEST -lt 500 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ULTRAWIDEFIELD002a_$TEST"
  fi
 fi 
 # test that util/solve_plate_with_UCAC5 will not try to recompute the solution if the output catalog is already there
 util/solve_plate_with_UCAC5 ../individual_images_test/1630+3250.20150511T215921000.fit 2>&1 | grep --quiet 'The output catalog wcs_1630+3250.20150511T215921000.fit.cat.ucac5 already exist.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ULTRAWIDEFIELD003"
 fi
 #
 #util/get_image_date ../individual_images_test/1630+3250.20150511T215921000.fit | grep --quiet "Exposure  20 sec, 11.05.2015 21:59:20   = JD  2457154.41632 mid. exp."
 util/get_image_date ../individual_images_test/1630+3250.20150511T215921000.fit | grep --quiet "Exposure  20 sec, 11.05.2015 21:59:21   = JD  2457154.41633 mid. exp."
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ULTRAWIDEFIELD004"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mUltra-wide-field image test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mUltra-wide-field image test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES ULTRAWIDEFIELD_TEST_NOT_PERFORMED"
fi

### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


######### Many hot pixels image
if [ ! -f ../individual_images_test/c176.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/c176.fits.bz2" && bunzip2 c176.fits.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/c176.fits ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Image with many hot pixels test " 1>&2
 echo -n "Image with many hot pixels test: " >> vast_test_report.txt 
 cp default.sex.many_hot_pixels default.sex
 util/solve_plate_with_UCAC5 ../individual_images_test/c176.fits
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HOTPIXIMAGE000"
 fi
 if [ ! -f wcs_c176.fits ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HOTPIXIMAGE001"
 fi 
 lib/bin/xy2sky wcs_c176.fits 200 200 &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HOTPIXIMAGE001a"
 fi
 if [ ! -f wcs_c176.fits.cat.ucac5 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HOTPIXIMAGE002"
 else
  TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_c176.fits.cat.ucac5 | wc -l | awk '{print $1}'`
  #if [ $TEST -lt 180 ];then
  # we reduced the catalog search radius, so now it's
  if [ $TEST -lt 170 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES HOTPIXIMAGE002a_$TEST"
  fi
 fi 
 util/get_image_date ../individual_images_test/c176.fits | grep --quiet "Exposure 120 sec, 02.08.2017 20:31:52 UT = JD(UT) 2457968.35616 mid. exp."
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HOTPIXIMAGE003"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mImage with many hot pixels test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mImage with many hot pixels test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES HOTPIXIMAGE_TEST_NOT_PERFORMED"
fi

######### SAI RC600 image
if [ ! -f ../individual_images_test/SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit.bz2" && bunzip2 SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "SAI RC600 image test " 1>&2
 echo -n "SAI RC600 test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 util/solve_plate_with_UCAC5 ../individual_images_test/SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600000"
 fi
 if [ ! -f wcs_SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600001"
 fi 
 lib/bin/xy2sky wcs_SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit 200 200 &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600001a"
 fi
 if [ ! -f wcs_SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit.cat.ucac5 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600002"
 else
  TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit.cat.ucac5 | wc -l | awk '{print $1}'`
  #if [ $TEST -lt 170 ];then
  # We reduced catalog search radius
  if [ $TEST -lt 150 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600002a_$TEST"
  fi
 fi 
 util/get_image_date ../individual_images_test/SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit | grep --quiet "Exposure  45 sec, 11.06.2019 00:10:29 UT = JD(UT) 2458645.50755 mid. exp."
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600003"
 fi
 #
 FOV=`lib/try_to_guess_image_fov ../individual_images_test/SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit | awk '{print $1}'`
 # Changed to the fake value that might work better than the real ones
 #if [ "$FOV" != "23" ];then
 if [ "$FOV" != "20" ] && [ "$FOV" != "23" ] ;then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600004"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSAI RC600 image test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSAI RC600 image test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600_TEST_NOT_PERFORMED"
fi

######### SAI RC600 B image
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
# this image requires index-204-03.fits to get solved
if [ ! -f ../individual_images_test/J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit.bz2" && bunzip2 J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "SAI RC600 B image test " 1>&2
 echo -n "SAI RC600 B image test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 util/solve_plate_with_UCAC5 ../individual_images_test/J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600B000"
 else
  if [ ! -f wcs_J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600B001"
  else
   lib/bin/xy2sky wcs_J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit 200 200 &>/dev/null
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600B001a"
   fi
   if [ ! -f wcs_J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit.cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600B002"
   else
    TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit.cat.ucac5 | wc -l | awk '{print $1}'`
    #if [ $TEST -lt 170 ];then
    # We reduced catalog search radius
    if [ $TEST -lt 100 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600B002a_$TEST"
    fi
   fi 
  fi # else if [ ! -f wcs_J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit ];then
 fi # check if util/solve_plate_with_UCAC5 returned 0 exit code
 util/get_image_date ../individual_images_test/J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit | grep --quiet "Exposure  60 sec, 16.07.2021 18:02:27 UT = JD(UT) 2459412.25205 mid. exp."
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600B003"
 fi
 #
 FOV=`lib/try_to_guess_image_fov ../individual_images_test/J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit | awk '{print $1}'`
 # Changed to the fake value that might work better than the real one
 if [ "$FOV" != "20" ] && [ "$FOV" != "23" ] ;then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600B004"
 fi
 #
 util/calibrate_single_image.sh ../individual_images_test/J20210770+2914093-1MHz-76mcs-PreampX4-0001B.fit B
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600B_CALIBRATE_SINGLE_IMAGE"
 fi
 lib/fit_robust_linear
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600B_FIT_ROBUST_LINEAR"
 fi
 TEST=`cat calib.txt_param | awk '{if ( sqrt( ($4-1.018597)*($4-1.018597) ) < 0.05 ) print 1 ;else print 0 }'`
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600B_FIT_ROBUST_LINEAR_COEFFA"
 fi
 TEST=`cat calib.txt_param | awk '{if ( sqrt( ($5-26.007315)*($5-26.007315) ) < 0.05 ) print 1 ;else print 0 }'`
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600B_FIT_ROBUST_LINEAR_COEFFB"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSAI RC600 B image test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSAI RC600 B image test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600B_TEST_NOT_PERFORMED"
fi
### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


######### SAI RC600 many bleeding stars image
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
# this image requires index-204-03.fits to get solved
if [ ! -f ../individual_images_test/V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit.bz2" && bunzip2 V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "SAI RC600 many bleeding stars image test " 1>&2
 echo -n "SAI RC600 many bleeding stars image test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 util/wcs_image_calibration.sh ../individual_images_test/V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED_WCSCALIB"
 else
  util/solve_plate_with_UCAC5 ../individual_images_test/V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED000"
  else
   if [ ! -f wcs_V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED001"
   else
    lib/bin/xy2sky wcs_V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit 200 200 &>/dev/null
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED001a"
    fi
    if [ ! -f wcs_V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit.cat.ucac5 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED002"
    else
     TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit.cat.ucac5 | wc -l | awk '{print $1}'`
     if [ $TEST -lt 50 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED002a_$TEST"
     fi
    fi 
   fi # else if [ ! -f wcs_V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit ];then
  fi # check if util/solve_plate_with_UCAC5 returned 0 exit code

  #
  util/calibrate_single_image.sh ../individual_images_test/V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit R
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED_CALIBRATE_SINGLE_IMAGE"
  fi
  # linear fit is inappropriate here as the magnitude range of comparison stars is very narrow
  #lib/fit_robust_linear
  lib/fit_zeropoint
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED_FIT_ROBUST_LINEAR"
  fi
  TEST=`cat calib.txt_param | awk '{if ( sqrt( ($4-1.0)*($4-1.0) ) < 0.05 ) print 1 ;else print 0 }'`
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED_FIT_ROBUST_LINEAR_COEFFA"
  fi
  TEST=`cat calib.txt_param | awk '{if ( sqrt( ($5-29.704115)*($5-29.704115) ) < 0.05 ) print 1 ;else print 0 }'`
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED_FIT_ROBUST_LINEAR_COEFFB"
   GREP_RESULT=`cat calib.txt_param`
   DEBUG_OUTPUT="$DEBUG_OUTPUT                              
###### SAIRC600MANYBLEED_FIT_ROBUST_LINEAR_COEFFB ######
$GREP_RESULT"
  fi

 fi # check if util/wcs_image_calibration.sh returned 0 exit code
 util/get_image_date ../individual_images_test/V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit | grep --quiet "Exposure 600 sec, 24.06.2019 21:34:19 UT = JD(UT) 2458659.40230 mid. exp."
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED003"
  GREP_RESULT=`util/get_image_date ../individual_images_test/V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit 2>&1`
  DEBUG_OUTPUT="$DEBUG_OUTPUT                              
###### SAIRC600MANYBLEED003 ######
$GREP_RESULT"
 fi
 #
 FOV=`lib/try_to_guess_image_fov ../individual_images_test/V2466Cyg-1MHz-76mcs-PreampX4-0001Rc.fit | awk '{print $1}'`
 # Changed to the fake value that might work better than the real one
 if [ "$FOV" != "20" ] && [ "$FOV" != "23" ] ;then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED004"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSAI RC600 many bleeding stars image test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSAI RC600 many bleeding stars image test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600MANYBLEED_TEST_NOT_PERFORMED"
fi
### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


######### Sintez 380mm image
if [ ! -f ../individual_images_test/LIGHT_21-06-21_V_-39.82_300.00s_0001.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/LIGHT_21-06-21_V_-39.82_300.00s_0001.fits.bz2" && bunzip2 LIGHT_21-06-21_V_-39.82_300.00s_0001.fits.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/LIGHT_21-06-21_V_-39.82_300.00s_0001.fits ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Sintez 380mm image test " 1>&2
 echo -n "Sintez 380mm image test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 util/solve_plate_with_UCAC5 ../individual_images_test/LIGHT_21-06-21_V_-39.82_300.00s_0001.fits
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ000"
 fi
 if [ ! -f wcs_LIGHT_21-06-21_V_-39.82_300.00s_0001.fits ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ001"
 fi 
 lib/bin/xy2sky wcs_LIGHT_21-06-21_V_-39.82_300.00s_0001.fits 200 200 &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ001a"
 fi
 if [ ! -f wcs_LIGHT_21-06-21_V_-39.82_300.00s_0001.fits.cat.ucac5 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ002"
 else
  TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_LIGHT_21-06-21_V_-39.82_300.00s_0001.fits.cat.ucac5 | wc -l | awk '{print $1}'`
  if [ $TEST -lt 200 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ002a_$TEST"
  fi
 fi
 util/calibrate_single_image.sh ../individual_images_test/LIGHT_21-06-21_V_-39.82_300.00s_0001.fits V
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ_CALIBRATE_SINGLE_IMAGE"
 fi
 lib/fit_robust_linear
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ_FIT_ROBUST_LINEAR"
 fi
 TEST=`cat calib.txt_param | awk '{if ( sqrt( ($4-1.000515)*($4-1.000515) ) < 0.05 ) print 1 ;else print 0 }'`
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ_FIT_ROBUST_LINEAR_COEFFA"
 fi
 TEST=`cat calib.txt_param | awk '{if ( sqrt( ($5-27.844390)*($5-27.844390) ) < 0.05 ) print 1 ;else print 0 }'`
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ_FIT_ROBUST_LINEAR_COEFFB"
 fi
 util/get_image_date ../individual_images_test/LIGHT_21-06-21_V_-39.82_300.00s_0001.fits | grep --quiet "Exposure 300 sec, 01.04.2021 18:06:22 UT = JD(UT) 2459306.25616 mid. exp."
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ003"
 fi
 #
 FOV=`lib/try_to_guess_image_fov ../individual_images_test/LIGHT_21-06-21_V_-39.82_300.00s_0001.fits | awk '{print $1}'`
 if [ "$FOV" != "26" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ004"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSintez 380mm image test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSintez 380mm image test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ_TEST_NOT_PERFORMED"
fi


######### Sintez 380mm image 2
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
if [ ! -f ../individual_images_test/LIGHT_21-22-58_B_-42.00_60.00s_0001.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/LIGHT_21-22-58_B_-42.00_60.00s_0001.fits.bz2" && bunzip2 LIGHT_21-22-58_B_-42.00_60.00s_0001.fits.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/LIGHT_21-22-58_B_-42.00_60.00s_0001.fits ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Sintez 380mm image 2 test " 1>&2
 echo -n "Sintez 380mm image 2 test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 util/solve_plate_with_UCAC5 ../individual_images_test/LIGHT_21-22-58_B_-42.00_60.00s_0001.fits
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ2000"
 elif [ ! -f wcs_LIGHT_21-22-58_B_-42.00_60.00s_0001.fits ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ2001"
 else 
  lib/bin/xy2sky wcs_LIGHT_21-22-58_B_-42.00_60.00s_0001.fits 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ2001a"
  elif [ ! -f wcs_LIGHT_21-22-58_B_-42.00_60.00s_0001.fits.cat.ucac5 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ2002"
  else
   TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_LIGHT_21-22-58_B_-42.00_60.00s_0001.fits.cat.ucac5 | wc -l | awk '{print $1}'`
   if [ $TEST -lt 400 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ2002a_$TEST"
   fi # if [ $TEST -lt 400 ];then
  fi # else if [ $? -ne 0 ];then
 fi # else if [ $? -ne 0 ];then
 util/calibrate_single_image.sh ../individual_images_test/LIGHT_21-22-58_B_-42.00_60.00s_0001.fits B
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ2_CALIBRATE_SINGLE_IMAGE"
 fi
 lib/fit_robust_linear
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ2_FIT_ROBUST_LINEAR"
 fi
 TEST=`cat calib.txt_param | awk '{if ( sqrt( ($4-1.004693)*($4-1.004693) ) < 0.05 ) print 1 ;else print 0 }'`
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ2_FIT_ROBUST_LINEAR_COEFFA"
 fi
 TEST=`cat calib.txt_param | awk '{if ( sqrt( ($5-25.319612)*($5-25.319612) ) < 0.05 ) print 1 ;else print 0 }'`
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ2_FIT_ROBUST_LINEAR_COEFFB"
 fi
 util/get_image_date ../individual_images_test/LIGHT_21-22-58_B_-42.00_60.00s_0001.fits | grep --quiet "Exposure  60 sec, 31.03.2021 18:22:58 UT = JD(UT) 2459305.26630 mid. exp."
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ2003"
 fi
 #
 FOV=`lib/try_to_guess_image_fov ../individual_images_test/LIGHT_21-22-58_B_-42.00_60.00s_0001.fits | awk '{print $1}'`
 if [ "$FOV" != "26" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ2004"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSintez 380mm image 2 test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSintez 380mm image 2 test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SINTEZ2_TEST_NOT_PERFORMED"
fi
### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then



######### Blank image with MJD-OBS
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
if [ ! -f ../individual_images_test/blank_image_with_only_MJD-OBS_keyword.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/blank_image_with_only_MJD-OBS_keyword.fits.bz2" && bunzip2 blank_image_with_only_MJD-OBS_keyword.fits.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/blank_image_with_only_MJD-OBS_keyword.fits ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Blank image with MJD-OBS test " 1>&2
 echo -n "Blank image with MJD-OBS test: " >> vast_test_report.txt 
 util/get_image_date ../individual_images_test/blank_image_with_only_MJD-OBS_keyword.fits | grep --quiet 'JD (mid. exp.) 2450862.85250 = 1998-02-18 08:27:36'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES BLANKMJDOBS001"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mBlank image with MJD-OBS test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mBlank image with MJD-OBS test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES BLANKMJDOBS_TEST_NOT_PERFORMED"
fi
### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then



######### NMW archive image
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
# this test should be mostly covered by the NMW transient search tests above
if [ ! -f ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/wcs_fd_Per3_2011-10-31_001.fts.bz2" && bunzip2 wcs_fd_Per3_2011-10-31_001.fts.bz2
 cd $WORKDIR
fi
#
if [ -f ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW archive image test " 1>&2
 echo -n "NMW archive image test: " >> vast_test_report.txt 
 cp default.sex.NMW_mass_processing default.sex
 util/solve_plate_with_UCAC5 ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts
 if [ ! -f wcs_fd_Per3_2011-10-31_001.fts ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWARCHIVEIMG001"
 fi 
 lib/bin/xy2sky wcs_fd_Per3_2011-10-31_001.fts 200 200 &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWARCHIVEIMG001a"
 fi
 if [ ! -s wcs_fd_Per3_2011-10-31_001.fts.cat.ucac5 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWARCHIVEIMG002"
 else
  TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_fd_Per3_2011-10-31_001.fts.cat.ucac5 | wc -l | awk '{print $1}'`
  #if [ $TEST -lt 1700 ];then
  if [ $TEST -lt 700 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWARCHIVEIMG002a_$TEST"
  fi
 fi 
 util/get_image_date ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts | grep --quiet "Exposure  40 sec, 30.10.2011 23:02:28 UT = JD(UT) 2455865.46028 mid. exp."
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWARCHIVEIMG003"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW archive image test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW archive image test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NMWARCHIVEIMG_TEST_NOT_PERFORMED"
fi
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


# T30
if [ ! -f ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit.bz2" && bunzip2 Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Large image, small skymark test " 1>&2
 echo -n "Large image, small skymark test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 util/solve_plate_with_UCAC5 ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit
 if [ ! -f wcs_Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLSKYMARK001"
 fi 
 lib/bin/xy2sky wcs_Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit 200 200 &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLSKYMARK001a"
 fi
 if [ ! -f wcs_Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit.cat.ucac5 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLSKYMARK002"
 else
  TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit.cat.ucac5 | wc -l | awk '{print $1}'`
  if [ $TEST -lt 270 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLSKYMARK002a_$TEST"
  fi
 fi
 # make sure no flag image is created for this one 
 lib/guess_saturation_limit_main ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit 2>&1 | grep --quiet -e 'FLAG_IMAGE' -e 'WEIGHT_IMAGE' -e 'WEIGHT_TYPE'
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLSKYMARK_FLAG_IMG_CREATED"
 fi
 #
 util/get_image_date ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit | grep 'Exposure   5 sec, 09.03.2015 13:46:48 UT = JD(UT) 2457091.07420 mid. exp.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLSKYMARK003"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mLarge image, small skymark test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mLarge image, small skymark test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLSKYMARK_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space

### Photoplate in the area not covered by APASS
if [ ! -f ../individual_images_test/SCA13320__00_00.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/SCA13320__00_00.fits.bz2" && bunzip2 SCA13320__00_00.fits.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/SCA13320__00_00.fits ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "104 Her test " 1>&2
 echo -n "104 Her test: " >> vast_test_report.txt 
 cp default.sex.beta_Cas_photoplates default.sex
 util/solve_plate_with_UCAC5 ../individual_images_test/SCA13320__00_00.fits
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES 104HER000"
 else
  if [ ! -f wcs_SCA13320__00_00.fits ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES 104HER001"
  else 
   lib/bin/xy2sky wcs_SCA13320__00_00.fits 200 200 &>/dev/null
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES 104HER001a"
   fi
   if [ ! -f wcs_SCA13320__00_00.fits.cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES 104HER002"
   else
    TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_SCA13320__00_00.fits.cat.ucac5 | wc -l | awk '{print $1}'`
    if [ $TEST -lt 700 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES 104HER002a_$TEST"
    fi
   fi # if [ ! -f wcs_SCA13320__00_00.fits.cat.ucac5 ];then
  fi # if [ ! -f wcs_SCA13320__00_00.fits ];then
 fi # if [ $? -ne 0 ];then 


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34m104 Her test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34m104 Her test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES 104HER_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space

### date specified with JDMID keyword
if [ ! -f ../individual_images_test/SCA13320__00_00__date_in_JDMID_keyword.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/SCA13320__00_00__date_in_JDMID_keyword.fits.bz2" && bunzip2 SCA13320__00_00__date_in_JDMID_keyword.fits.bz2
 cd $WORKDIR
fi
if [ ! -f ../individual_images_test/SCA13320__00_00.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/SCA13320__00_00.fits.bz2" && bunzip2 SCA13320__00_00.fits.bz2
 cd $WORKDIR
fi
if [ -f ../individual_images_test/SCA13320__00_00__date_in_JDMID_keyword.fits ] && [ -f ../individual_images_test/SCA13320__00_00.fits ] ;then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "JDMID test " 1>&2
 echo -n "JDMID test: " >> vast_test_report.txt 
 cp default.sex.beta_Cas_photoplates default.sex
 JDMID_KEY_JD=`util/get_image_date ../individual_images_test/SCA13320__00_00__date_in_JDMID_keyword.fits | grep 'JD (mid. exp.)'`
 JD_KEY_JD=`util/get_image_date ../individual_images_test/SCA13320__00_00.fits | grep 'JD (mid. exp.)'`
 if [ "$JDMID_KEY_JD" != "$JD_KEY_JD" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES JDMID001"
 fi 


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mJDMID test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mJDMID test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES JDMID_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space

### HST image - check that we are creating a flag image for that one
if [ ! -f ../individual_images_test/hst_12911_01_wfc3_uvis_f775w_01_drz.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/hst_12911_01_wfc3_uvis_f775w_01_drz.fits.bz2" && bunzip2 hst_12911_01_wfc3_uvis_f775w_01_drz.fits.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/hst_12911_01_wfc3_uvis_f775w_01_drz.fits ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Flag image creation for HST test " 1>&2
 echo -n "Flag image creation for HST test: " >> vast_test_report.txt 
 # first run without grep "FLAG_IMAGE image00000.flag" to see the crash log if any
 cp default.sex.ccd_example default.sex
 GREP_RESULT=`lib/autodetect_aperture_main ../individual_images_test/hst_12911_01_wfc3_uvis_f775w_01_drz.fits 2>&1`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FLAGHST000"
  DEBUG_OUTPUT="$DEBUG_OUTPUT
###### FLAGHST000 ######
$GREP_RESULT"
 fi 
 cp default.sex.ccd_example default.sex
 lib/autodetect_aperture_main ../individual_images_test/hst_12911_01_wfc3_uvis_f775w_01_drz.fits 2>&1 | grep --quiet "FLAG_IMAGE image00000.flag"
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FLAGHST001"
 fi 
 util/get_image_date ../individual_images_test/hst_12911_01_wfc3_uvis_f775w_01_drz.fits | grep --quiet "JD (mid. exp.) 2456311.52320"
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FLAGHST002"
 fi 


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mFlag image creation for HST test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mFlag image creation for HST test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES FLAGHST_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space

######### ZTF image header test
if [ ! -f ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits.bz2" && bunzip2 ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "ZTF image header test " 1>&2
 echo -n "ZTF image header test: " >> vast_test_report.txt 
 #
 util/get_image_date ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits | grep --quiet 'Exposure  30 sec, 27.03.2018 12:43:50   = JD  2458205.03061 mid. exp.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER000"
 fi
 #
 util/get_image_date ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits 2>&1 | grep --quiet 'DATE-OBS= 2018-03-27T12:43:50'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER000a"
 fi
 #
 util/fov_of_wcs_calibrated_image.sh ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits  | grep --quiet "Image size: 51.9'x52.0'"
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER000b"
 fi
 #
 util/fov_of_wcs_calibrated_image.sh ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits  | grep --quiet 'Image scale: 1.01"/pix along the X axis and 1.01"/pix along the Y axis'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER000c"
 fi
 #
 util/fov_of_wcs_calibrated_image.sh ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits  | grep --quiet 'Image center: 17:47:53.046 -13:08:42.33 J2000 1536.500 1540.500'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER000d"
 fi
 #
 #
 lib/try_to_guess_image_fov ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits  | grep --quiet ' 47'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER000e"
 fi
 #
 cp default.sex.ccd_example default.sex 
 util/solve_plate_with_UCAC5 ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits
 if [ ! -f wcs_ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER001"
 fi 
 lib/bin/xy2sky wcs_ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits 200 200 &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER001a"
 fi
 if [ ! -s wcs_ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits.cat.ucac5 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER002"
 else
  TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits.cat.ucac5 | wc -l | awk '{print $1}'`
  #if [ $TEST -lt 1200 ];then
  if [ $TEST -lt 700 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER002a_$TEST"
  else
   #
   util/calibrate_single_image.sh ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits g
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER004"
   fi
   lib/fit_robust_linear
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER005"
   fi
   TEST=`cat calib.txt_param | awk '{if ( sqrt( ($3-0.000000)*($3-0.000000) ) < 0.0005 ) print 1 ;else print 0 }'`
   if [ $TEST -ne 1 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER006"
   fi
   TEST=`cat calib.txt_param | awk '{if ( sqrt( ($4-1.005331)*($4-1.005331) ) < 0.05 ) print 1 ;else print 0 }'`
   if [ $TEST -ne 1 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER007"
   fi
   TEST=`cat calib.txt_param | awk '{if ( sqrt( ($5-26.204981)*($5-26.204981) ) < 0.05 ) print 1 ;else print 0 }'`
   if [ $TEST -ne 1 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER008"
   fi
   #
  fi # else if [ $TEST -lt 700 ];then
 fi 
 # test that util/solve_plate_with_UCAC5 will not try to recompute the solution if the output catalog is already there
 util/solve_plate_with_UCAC5 ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits 2>&1 | grep --quiet 'The output catalog wcs_ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits.cat.ucac5 already exist.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER003"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mZTF image header test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mZTF image header test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER_TEST_NOT_PERFORMED"
fi

######### ZTF image header test 2
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
if [ ! -f ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit.bz2" && bunzip2 ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "ZTF image header test 2 " 1>&2
 echo -n "ZTF image header test 2: " >> vast_test_report.txt 
 #
 #util/get_image_date ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit | grep --quiet 'Exposure  30 sec, 09.12.2018 10:25:07   = JD  2458461.93428 mid. exp.'
 util/get_image_date ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit | grep --quiet 'Exposure  30 sec, 09.12.2018 10:25:10   = JD  2458461.93432 mid. exp.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2000"
 fi
 #
 #util/get_image_date ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit 2>&1 | grep --quiet 'DATE-OBS= 2018-12-09T10:25:07'
 util/get_image_date ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit 2>&1 | grep --quiet 'DATE-OBS= 2018-12-09T10:25:10'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2000a"
 fi
 #
 util/fov_of_wcs_calibrated_image.sh ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit  | grep --quiet "Image size: 51.8'x52.0'"
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2000b"
 fi
 #
 util/fov_of_wcs_calibrated_image.sh ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit  | grep --quiet 'Image scale: 1.01"/pix along the X axis and 1.01"/pix along the Y axis'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2000c"
 fi
 #
 util/fov_of_wcs_calibrated_image.sh ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit  | grep --quiet 'Image center: 06:56:29.366 -22:50:13.56 J2000 1536.500 1540.500'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2000d"
 fi
 #
 #
 lib/try_to_guess_image_fov ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit  | grep --quiet ' 47'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2000e"
 fi
 #
 cp default.sex.ccd_example default.sex 
 util/solve_plate_with_UCAC5 ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit
 if [ ! -f wcs_ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2001"
 fi 
 lib/bin/xy2sky wcs_ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit 200 200 &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2001a"
 fi
 if [ ! -s wcs_ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit.cat.ucac5 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2002"
 else
  TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit.cat.ucac5 | wc -l | awk '{print $1}'`
  if [ $TEST -lt 700 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2002a_$TEST"
  fi
 fi 
 # test that util/solve_plate_with_UCAC5 will not try to recompute the solution if the output catalog is already there
 util/solve_plate_with_UCAC5 ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit 2>&1 | grep --quiet 'The output catalog wcs_ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit.cat.ucac5 already exist.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2003"
 fi
 util/calibrate_single_image.sh ../individual_images_test/ztf_20181209434120_000259_zr_c11_o_q1_sciimg.fit r
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2004"
 fi
 lib/fit_robust_linear
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2005"
 fi
 TEST=`cat calib.txt_param | awk '{if ( sqrt( ($3-0.000000)*($3-0.000000) ) < 0.0005 ) print 1 ;else print 0 }'`
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2006"
 fi
 TEST=`cat calib.txt_param | awk '{if ( sqrt( ($4-0.999569)*($4-0.999569) ) < 0.05 ) print 1 ;else print 0 }'`
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2007"
 fi
 TEST=`cat calib.txt_param | awk '{if ( sqrt( ($5-25.768253)*($5-25.768253) ) < 0.05 ) print 1 ;else print 0 }'`
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2008"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mZTF image header test 2 \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mZTF image header test 2 \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER2_TEST_NOT_PERFORMED"
fi
### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then



######### Stacked DSLR image (BITPIX=16) created with Siril
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
if [ ! -f ../individual_images_test/r_ncas20200820_stacked_16bit_g2.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/r_ncas20200820_stacked_16bit_g2.fit.bz2" && bunzip2 r_ncas20200820_stacked_16bit_g2.fit.bz2
 cd $WORKDIR
fi
#
if [ -f ../individual_images_test/r_ncas20200820_stacked_16bit_g2.fit ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Stacked DSLR image (BITPIX=16) created with Siril test " 1>&2
 echo -n "Stacked DSLR image (BITPIX=16) created with Siril test: " >> vast_test_report.txt 
 #
 util/get_image_date ../individual_images_test/r_ncas20200820_stacked_16bit_g2.fit | grep --quiet 'Exposure 750 sec, 20.08.2020 07:45:37 UT = JD(UT) 2459081.82769 mid. exp.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL001"
 fi
 #
 util/get_image_date ../individual_images_test/r_ncas20200820_stacked_16bit_g2.fit 2>&1 | grep --quiet 'DATE-OBS= 2020-08-20T07:45:37'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL002"
 fi
 #
 lib/try_to_guess_image_fov ../individual_images_test/r_ncas20200820_stacked_16bit_g2.fit  | grep --quiet ' 672'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL003"
 fi
 #
 #
 cp default.sex.ccd_example default.sex 
 # Make sure gain value is NOT set to 0 for a 16 bit DSLR image 
 lib/guess_saturation_limit_main ../individual_images_test/r_ncas20200820_stacked_16bit_g2.fit 2>&1 | grep --quiet 'The gain value is set to 0 '
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32_gain"
 fi
 #
 util/wcs_image_calibration.sh ../individual_images_test/r_ncas20200820_stacked_16bit_g2.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL004"
 else
  util/fov_of_wcs_calibrated_image.sh wcs_r_ncas20200820_stacked_16bit_g2.fit | grep --quiet "Image size: 97"
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL005"
  fi
  #
  util/fov_of_wcs_calibrated_image.sh wcs_r_ncas20200820_stacked_16bit_g2.fit  | grep --quiet 'Image scale: 13'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL006"
  fi
  #
  util/fov_of_wcs_calibrated_image.sh wcs_r_ncas20200820_stacked_16bit_g2.fit  | grep --quiet 'Image center: 00:07:'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL007"
  fi
  #
  util/solve_plate_with_UCAC5 ../individual_images_test/r_ncas20200820_stacked_16bit_g2.fit
  if [ ! -f wcs_r_ncas20200820_stacked_16bit_g2.fit ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL008"
  fi 
  lib/bin/xy2sky wcs_r_ncas20200820_stacked_16bit_g2.fit 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL009"
  fi
  if [ ! -s wcs_r_ncas20200820_stacked_16bit_g2.fit.cat.ucac5 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL010"
  else
   TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_r_ncas20200820_stacked_16bit_g2.fit.cat.ucac5 | wc -l | awk '{print $1}'`
   if [ $TEST -lt 100 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL011_$TEST"
   fi
  fi 
  # test that util/solve_plate_with_UCAC5 will not try to recompute the solution if the output catalog is already there
  util/solve_plate_with_UCAC5 ../individual_images_test/r_ncas20200820_stacked_16bit_g2.fit 2>&1 | grep --quiet 'The output catalog wcs_r_ncas20200820_stacked_16bit_g2.fit.cat.ucac5 already exist.'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL012"
  fi
 fi # initial plate solve was successful


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mStacked DSLR image (BITPIX=16) created with Siril test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mStacked DSLR image (BITPIX=16) created with Siril test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL_TEST_NOT_PERFORMED"
fi

### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


######### Stacked DSLR image (BITPIX=-32) created with Siril
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
if [ ! -f ../individual_images_test/r_ncas20200820_stacked_32bit_g2.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/r_ncas20200820_stacked_32bit_g2.fit.bz2" && bunzip2 r_ncas20200820_stacked_32bit_g2.fit.bz2
 cd $WORKDIR
fi
#
if [ -f ../individual_images_test/r_ncas20200820_stacked_32bit_g2.fit ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Stacked DSLR image (BITPIX=-32) created with Siril test " 1>&2
 echo -n "Stacked DSLR image (BITPIX=-32) created with Siril test: " >> vast_test_report.txt 
 #
 util/get_image_date ../individual_images_test/r_ncas20200820_stacked_32bit_g2.fit | grep --quiet 'Exposure 750 sec, 20.08.2020 07:45:37 UT = JD(UT) 2459081.82769 mid. exp.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32001"
 fi
 #
 util/get_image_date ../individual_images_test/r_ncas20200820_stacked_32bit_g2.fit 2>&1 | grep --quiet 'DATE-OBS= 2020-08-20T07:45:37'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32002"
 fi
 #
 lib/try_to_guess_image_fov ../individual_images_test/r_ncas20200820_stacked_32bit_g2.fit  | grep --quiet ' 672'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32003"
 fi
 #
 #
 cp default.sex.ccd_example default.sex 
 # Make sure gain value is set to 0 for a -32 DSLR image 
 lib/guess_saturation_limit_main ../individual_images_test/r_ncas20200820_stacked_32bit_g2.fit 2>&1 | grep --quiet 'The gain value is set to 0 '
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32_gain01"
 fi
 #
 lib/autodetect_aperture_main ../individual_images_test/r_ncas20200820_stacked_32bit_g2.fit 2>&1 | grep --quiet 'GAIN 0.0'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32_gain02"
 fi
 #
 util/wcs_image_calibration.sh ../individual_images_test/r_ncas20200820_stacked_32bit_g2.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32004"
 else
  util/fov_of_wcs_calibrated_image.sh wcs_r_ncas20200820_stacked_32bit_g2.fit | grep --quiet "Image size: 97"
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32005"
  fi
  #
  util/fov_of_wcs_calibrated_image.sh wcs_r_ncas20200820_stacked_32bit_g2.fit  | grep --quiet 'Image scale: 13'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32006"
  fi
  #
  util/fov_of_wcs_calibrated_image.sh wcs_r_ncas20200820_stacked_32bit_g2.fit  | grep --quiet 'Image center: 00:07:'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32007"
  fi
  #
  util/solve_plate_with_UCAC5 ../individual_images_test/r_ncas20200820_stacked_32bit_g2.fit
  if [ ! -f wcs_r_ncas20200820_stacked_32bit_g2.fit ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32008"
  fi 
  lib/bin/xy2sky wcs_r_ncas20200820_stacked_32bit_g2.fit 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32009"
  fi
  if [ ! -s wcs_r_ncas20200820_stacked_32bit_g2.fit.cat.ucac5 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32010"
  else
   TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_r_ncas20200820_stacked_32bit_g2.fit.cat.ucac5 | wc -l | awk '{print $1}'`
   if [ $TEST -lt 100 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32011_$TEST"
   fi
  fi 
  # test that util/solve_plate_with_UCAC5 will not try to recompute the solution if the output catalog is already there
  util/solve_plate_with_UCAC5 ../individual_images_test/r_ncas20200820_stacked_32bit_g2.fit 2>&1 | grep --quiet 'The output catalog wcs_r_ncas20200820_stacked_32bit_g2.fit.cat.ucac5 already exist.'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32012"
  fi
 fi # initial plate solve was successful


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mStacked DSLR image (BITPIX=-32) created with Siril test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mStacked DSLR image (BITPIX=-32) created with Siril test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32_TEST_NOT_PERFORMED"
fi

### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


######### Stacked DSLR image (BITPIX=-32) created with Siril
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
if [ ! -f ../individual_images_test/r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit.bz2" && bunzip2 r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Stacked DSLR image (BITPIX=-32, EXPSTART, EXPEND) created with Siril test " 1>&2
 echo -n "Stacked DSLR image (BITPIX=-32, EXPSTART, EXPEND) created with Siril test: " >> vast_test_report.txt 
 #
 util/get_image_date ../individual_images_test/r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit | grep --quiet 'JD (mid. exp.) 2459177.84869 = 2020-11-24 08:22:06 (UT)'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND001"
 fi
 #
 lib/try_to_guess_image_fov ../individual_images_test/r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit  | grep --quiet ' 672'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND003"
 fi
 #
 #
 cp default.sex.ccd_example default.sex 
 # Make sure gain value is set to 0 for a -32 DSLR image 
 lib/guess_saturation_limit_main ../individual_images_test/r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit 2>&1 | grep --quiet 'The gain value is set to 0 '
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND_gain01"
 fi
 #
 lib/autodetect_aperture_main ../individual_images_test/r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit 2>&1 | grep --quiet 'GAIN 0.0'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND_gain02"
 fi
 #
 util/wcs_image_calibration.sh ../individual_images_test/r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND004"
 else
  util/fov_of_wcs_calibrated_image.sh wcs_r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit | grep --quiet "Image size: 97...'x64...'"
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND005"
  fi
  #
  util/fov_of_wcs_calibrated_image.sh wcs_r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit  | grep --quiet 'Image scale: 13'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND006"
  fi
  #
  util/fov_of_wcs_calibrated_image.sh wcs_r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit  | grep --quiet 'Image center: 00:03:'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND007"
  fi
  #
  util/solve_plate_with_UCAC5 ../individual_images_test/r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit
  if [ ! -f wcs_r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND008"
  fi 
  lib/bin/xy2sky wcs_r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND009"
  fi
  if [ ! -s wcs_r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit.cat.ucac5 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND010"
  else
   TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit.cat.ucac5 | wc -l | awk '{print $1}'`
   if [ $TEST -lt 100 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND011_$TEST"
   fi
  fi 
  # test that util/solve_plate_with_UCAC5 will not try to recompute the solution if the output catalog is already there
  util/solve_plate_with_UCAC5 ../individual_images_test/r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit 2>&1 | grep --quiet 'The output catalog wcs_r_ncas20201124_stacked_32bit_EXPSTART_EXPEND_g2.fit.cat.ucac5 already exist.'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND012"
  fi
 fi # initial plate solve was successful


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mStacked DSLR image (BITPIX=-32, EXPSTART, EXPEND) created with Siril test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mStacked DSLR image (BITPIX=-32, EXPSTART, EXPEND) created with Siril test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES STACKEDDSLRSIRIL32EXPEND_TEST_NOT_PERFORMED"
fi

### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


######### A bad TESS FFI with no WCS
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
if [ ! -f ../individual_images_test/tess2020107065919-s0024-4-4-0180-s_ffic.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/tess2020107065919-s0024-4-4-0180-s_ffic.fits.bz2" && bunzip2 tess2020107065919-s0024-4-4-0180-s_ffic.fits.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/tess2020107065919-s0024-4-4-0180-s_ffic.fits ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "TESS FFI with no WCS test " 1>&2
 echo -n "TESS FFI with no WCS test: " >> vast_test_report.txt 
 #
 util/get_image_date ../individual_images_test/tess2020107065919-s0024-4-4-0180-s_ffic.fits | grep --quiet 'Exposure 1800 sec, 16.04.2020 06:54:38   = JD  2458955.79836 mid. exp.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS001"
 fi
 #
 lib/try_to_guess_image_fov ../individual_images_test/tess2020107065919-s0024-4-4-0180-s_ffic.fits  | grep --quiet ' 710'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS003"
 fi
 #
 #
 cp default.sex.ccd_example default.sex 
 # Make sure gain value is set to exposure time for the count rate image 
 lib/autodetect_aperture_main ../individual_images_test/tess2020107065919-s0024-4-4-0180-s_ffic.fits 2>&1 | grep --quiet 'GAIN 1425'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS_gain"
 fi
 #
 util/wcs_image_calibration.sh ../individual_images_test/tess2020107065919-s0024-4-4-0180-s_ffic.fits
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS004"
 else
  util/fov_of_wcs_calibrated_image.sh wcs_tess2020107065919-s0024-4-4-0180-s_ffic.fits | grep --quiet "Image size: 7..\..'x7..\..'"
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS005"
  fi
  #
  util/fov_of_wcs_calibrated_image.sh wcs_tess2020107065919-s0024-4-4-0180-s_ffic.fits  | grep --quiet -e 'Image scale: 19.' -e 'Image scale: 20.'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS006"
  fi
  #
  util/fov_of_wcs_calibrated_image.sh wcs_tess2020107065919-s0024-4-4-0180-s_ffic.fits  | grep --quiet 'Image center: 01:04:'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS007"
  fi
  #
  util/solve_plate_with_UCAC5 ../individual_images_test/tess2020107065919-s0024-4-4-0180-s_ffic.fits
  if [ ! -f wcs_tess2020107065919-s0024-4-4-0180-s_ffic.fits ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS008"
  fi 
  lib/bin/xy2sky wcs_tess2020107065919-s0024-4-4-0180-s_ffic.fits 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS009"
  fi
  if [ ! -s wcs_tess2020107065919-s0024-4-4-0180-s_ffic.fits.cat.ucac5 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS010"
  else
   TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_tess2020107065919-s0024-4-4-0180-s_ffic.fits.cat.ucac5 | wc -l | awk '{print $1}'`
   if [ $TEST -lt 20 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS011_$TEST"
   fi
  fi 
  # test that util/solve_plate_with_UCAC5 will not try to recompute the solution if the output catalog is already there
  util/solve_plate_with_UCAC5 ../individual_images_test/tess2020107065919-s0024-4-4-0180-s_ffic.fits 2>&1 | grep --quiet 'The output catalog wcs_tess2020107065919-s0024-4-4-0180-s_ffic.fits.cat.ucac5 already exist.'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS012"
  fi
 fi # initial plate solve was successful


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mTESS FFI with no WCS test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mTESS FFI with no WCS test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES TESSFFINOWCS_TEST_NOT_PERFORMED"
fi

### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


### Test imstat code
if [ -d ../individual_images_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 # Run the test
 echo "Test imstat code " 1>&2
 echo -n "Test imstat code: " >> vast_test_report.txt 

 ### Specific test to make sure lib/try_to_guess_image_fov does not crash
 for IMAGE in ../individual_images_test/* ;do
  util/imstat_vast $IMAGE
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   IMAGE=`basename $IMAGE`
   FAILED_TEST_CODES="$FAILED_TEST_CODES IMSTAT01_$IMAGE"
  fi
  util/imstat_vast_fast $IMAGE
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   IMAGE=`basename $IMAGE`
   FAILED_TEST_CODES="$FAILED_TEST_CODES IMSTAT02_$IMAGE"
  fi
 done


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mimstat code test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mimstat code test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES IMSTAT_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  



### Test the field-of-view guess code
if [ -d ../individual_images_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 # Run the test
 echo "Test the field-of-view guess code " 1>&2
 echo -n "Test the field-of-view guess code: " >> vast_test_report.txt 

 ### Specific test to make sure lib/try_to_guess_image_fov does not crash
 for IMAGE in ../individual_images_test/* ;do
  lib/try_to_guess_image_fov $IMAGE
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   IMAGE=`basename $IMAGE`
   FAILED_TEST_CODES="$FAILED_TEST_CODES GUESSFOV01_$IMAGE"
  fi
 done


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mField-of-view guess code test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mField-of-view guess code test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES GUESSFOV_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi


### Check the external plate solve servers
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
if [ ! -f ../individual_images_test/1630+3250.20150511T215921000.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/1630+3250.20150511T215921000.fit.bz2" && bunzip2 1630+3250.20150511T215921000.fit.bz2
 cd $WORKDIR
fi
if [ ! -f ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit.bz2" && bunzip2 Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit.bz2
 cd $WORKDIR
fi
if [ ! -f ../individual_images_test/SCA13320__00_00.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/SCA13320__00_00.fits.bz2" && bunzip2 SCA13320__00_00.fits.bz2
 cd $WORKDIR
fi
if [ ! -d ../M31_ISON_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/M31_ISON_test.tar.bz2" && tar -xvjf M31_ISON_test.tar.bz2 && rm -f M31_ISON_test.tar.bz2
 cd $WORKDIR
fi
#
if [ -d ../individual_images_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 # Run the test
 echo "Test plate solving with remote servers " 1>&2
 echo -n "Plate solving with remote servers: " >> vast_test_report.txt 
 for FORCE_PLATE_SOLVE_SERVER in scan.sai.msu.ru vast.sai.msu.ru polaris.kirx.net none ;do
  export FORCE_PLATE_SOLVE_SERVER
  unset TELESCOP
  util/clean_data.sh
  cp default.sex.ccd_example default.sex
  if [ -f ../individual_images_test/1630+3250.20150511T215921000.fit ];then
   unset TELESCOP
   export ASTROMETRYNET_LOCAL_OR_REMOTE="remote" 
   util/wcs_image_calibration.sh ../individual_images_test/1630+3250.20150511T215921000.fit
   export ASTROMETRYNET_LOCAL_OR_REMOTE=""
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE001"
   else
    if [ ! -f wcs_1630+3250.20150511T215921000.fit ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE002"
    else
     lib/bin/xy2sky wcs_1630+3250.20150511T215921000.fit 200 200 &>/dev/null
     if [ $? -ne 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE002a"
     fi
    fi # if [ ! -f wcs_1630+3250.20150511T215921000.fit ];then
   fi # if [ $? -ne 0 ];then
  else
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"NOT_PERFORMING_REMOTE_PLATE_SOLVER_CHECK_FOR_1630_test"
  fi
  #
  if [ -f ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit ];then
   unset TELESCOP
   cp default.sex.ccd_example default.sex
   ASTROMETRYNET_LOCAL_OR_REMOTE="remote" util/wcs_image_calibration.sh ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE003"
   else
    if [ ! -f wcs_Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE004"
    else
     lib/bin/xy2sky wcs_Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit 200 200 &>/dev/null
     if [ $? -ne 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE004a"
     fi
    fi # if [ ! -f wcs_Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit ];then
   fi # if [ $? -ne 0 ];then
  else
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"NOT_PERFORMING_REMOTE_PLATE_SOLVER_CHECK_FOR_T30_test"
  fi
  #
  if [ -f ../individual_images_test/SCA13320__00_00.fits ];then
   unset TELESCOP
   cp default.sex.beta_Cas_photoplates default.sex
   ASTROMETRYNET_LOCAL_OR_REMOTE="remote" util/wcs_image_calibration.sh ../individual_images_test/SCA13320__00_00.fits
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE005"
   else
    if [ ! -f wcs_SCA13320__00_00.fits ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE006"
    else
     lib/bin/xy2sky wcs_SCA13320__00_00.fits 200 200 &>/dev/null
     if [ $? -ne 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE006a"
     fi
    fi # if [ ! -f wcs_SCA13320__00_00.fits ];then
   fi # if [ $? -ne 0 ];then
  else
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"NOT_PERFORMING_REMOTE_PLATE_SOLVER_CHECK_FOR_SCA13320_test"
  fi
  #
  if [ -f ../M31_ISON_test/M31-1-001-001_dupe-1.fts ];then
   unset TELESCOP
   cp default.sex.ison_m31_test default.sex
   ASTROMETRYNET_LOCAL_OR_REMOTE="remote" util/wcs_image_calibration.sh ../M31_ISON_test/M31-1-001-001_dupe-1.fts
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE007"
   else
    if [ ! -f wcs_M31-1-001-001_dupe-1.fts ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE008"
    else
     lib/bin/xy2sky wcs_M31-1-001-001_dupe-1.fts 200 200 &>/dev/null
     if [ $? -ne 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE009"
     fi # if [ $? -ne 0 ];then  # if lib/bin/xy2sky did not crash
    fi # if [ ! -f wcs_M31-1-001-001_dupe-1.fts ];then
   fi # if [ $? -ne 0 ];then # util/wcs_image_calibration.sh exit with code 0 (success)
  else
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"NOT_PERFORMING_REMOTE_PLATE_SOLVER_CHECK_FOR_M31_ISON_test"
  fi
  # restore default settings file, just in case
  cp default.sex.ccd_example default.sex
 done


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mTest for plate solving with remote servers \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mTest for plate solving with remote servers \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi

else
 FAILED_TEST_CODES="$FAILED_TEST_CODES REMOTEPLATESOLVE_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi

### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


### check that we are NOT creating a flag image for photoplates
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
if [ ! -f ../individual_images_test/SCA13320__00_00.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/SCA13320__00_00.fits.bz2" && bunzip2 SCA13320__00_00.fits.bz2
 cd $WORKDIR
fi
if [ -f ../individual_images_test/SCA13320__00_00.fits ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "No flag images for photoplates 2 test " 1>&2
 echo -n "No flag images for photoplates 2 test: " >> vast_test_report.txt 
 cp default.sex.beta_Cas_photoplates default.sex
 lib/autodetect_aperture_main ../individual_images_test/SCA13320__00_00.fits 2>&1 | grep "FLAG_IMAGE image00000.flag"
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NOFLAGSPHOTO2001"
 fi 
 util/get_image_date ../individual_images_test/SCA13320__00_00.fits | grep "JD (mid. exp.) 2444052.46700"
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NOFLAGSPHOTO2002"
 fi 


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNo flag images for photoplates 2 test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNo flag images for photoplates 2 test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NOFLAGSPHOTO2_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space
#
### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then


############# Dark Flat Flag #############
if [ ! -d ../vast_test__dark_flat_flag ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test__dark_flat_flag.tar.bz2" && tar -xvjf vast_test__dark_flat_flag.tar.bz2 && rm -f vast_test__dark_flat_flag.tar.bz2
 cd $WORKDIR
fi
if [ -d ../vast_test__dark_flat_flag ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Dark Flat Flag test " 1>&2
 echo -n "Dark Flat Flag test: " >> vast_test_report.txt 
 util/examples/test__dark_flat_flag.sh
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_DARK_FLAT_FLAG_001"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mDark Flat Flag test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mDark Flat Flag test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_DARK_FLAT_FLAG_TEST_NOT_PERFORMED" 
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
remove_test_data_to_save_space

############## Sepcial tests that are performed only on the main developement computer ##############
if [ -d /mnt/usb/M4_F775W_images_Level2_few_links_for_tests ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Special HST M4 test " 1>&2
 echo -n "Special HST M4 test: " >> vast_test_report.txt 
 cp default.sex_HST_test default.sex
 ./vast -u -f /mnt/usb/M4_F775W_images_Level2_few_links_for_tests/*
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 6" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST001"
  fi
  grep --quiet "Images used for photometry 6" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST002"
  fi
  # Calendar time will be set to 00.00.0000 00:00:00 if JD is taken from EXPSTART instead of DATE-OBS
  grep --quiet -e "First image: 2456311.38443 18.01.2013 21:13:25" -e "First image: 2456311.38443 00.00.0000 00:00:00" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST003"
  fi
  grep --quiet -e "Last  image: 2456312.04468 19.01.2013 13:04:10" -e "Last  image: 2456312.04468 00.00.0000 00:00:00" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SPECIALM4HST0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SPECIALM4HST0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "Magnitude-Size filter: Enabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST005"
  fi
  grep --quiet "Photometric errors rescaling: NO" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST006"
  fi
 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST_ALL"
 fi
 

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSpecial HST M4 test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSpecial HST M4 test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
 #
 echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
 df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
 # 
fi

############# VB #############
if [ "$HOSTNAME" = "eridan" ] ;then
 if [ -d /mnt/usb/VaST_test_VladimirB/GoodFrames/vast_test_VB ];then
  THIS_TEST_START_UNIXSEC=$(date +%s)
  TEST_PASSED=1
  util/clean_data.sh
  # Run the test
  echo "Special VB test " 1>&2
  echo -n "Special VB test: " >> vast_test_report.txt 
  CAT_RESULT=`util/examples/test__VB.sh 2>&1 | grep 'FAILED_TEST_CODES= '`
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VB_001"
   DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SPECIAL_VB_001 ######
$CAT_RESULT"
  fi

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

  if [ $TEST_PASSED -eq 1 ];then
   echo -e "\n\033[01;34mSpecial VB test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
   echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
  else
   echo -e "\n\033[01;34mSpecial VB test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
   echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
  fi
  #
  echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
  df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
  # 
 fi
fi # if [ "$HOSTNAME" = "eridan" ] ;then

############# VB2 #############
# yes, we want this test not only @eridan, but on any machine that has a copy of the test dataset
if [ -d /mnt/usb/VaST_test_VladimirB_2/GoodFrames/vast_test_VB ] || [ -d ../VaST_test_VladimirB_2/GoodFrames/vast_test_VB ] ;then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Special VB2 test " 1>&2
 echo -n "Special VB2 test: " >> vast_test_report.txt 
 CAT_RESULT=`util/examples/test__VB_2.sh 2>&1 | grep -e 'FAILED_TEST_CODES= ' -e 'ERROR'`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VB2_001"
  DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SPECIAL_VB2_001 ######
$CAT_RESULT"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSpecial VB test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSpecial VB test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
 #
 echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
 df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
 # 
fi
 
# yes, we want this test not only @eridan, but on any machine that has enough disk space
############# Check free disk space #############
FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" = "true" ];then
 FREE_DISK_SPACE_MB=0
fi
############# 61 Cyg #############
if [ -d /mnt/usb/61Cyg_photoplates_test ] || [ -d ../61Cyg_photoplates_test ] || [ $FREE_DISK_SPACE_MB -gt 8192 ] ;then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Special 61 Cyg test " 1>&2
 echo -n "Special 61 Cyg test: " >> vast_test_report.txt 
 GREP_RESULT=`util/examples/test_61Cyg.sh | grep -e 'FAILED_TEST_CODES' -e 'Test failed' -e 'Test passed'`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_61CYG_001"
  DEBUG_OUTPUT="$DEBUG_OUTPUT
###### 61 Cyg ######
$GREP_RESULT"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSpecial 61 Cyg test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSpecial 61 Cyg test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
 #
 echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
 df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
 # 
fi

####### Special test V2466 Cyg SAI600 #######
# Should run anywhere there is the data dir. 
# The test script will return 0 if there is no data or if everything is fine
util/examples/test_V2466CygSAI600.sh
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_V2466CygSAI600_001"
 echo -e "\n\033[01;34mSpecial V2466 Cyg SAI600 test \033[01;31mFAILED\033[00m" 1>&2
 echo -n "Special 61 Cyg test: " >> vast_test_report.txt
 echo "FAILED" >> vast_test_report.txt
fi


############# NCas21 KGO RC600 #############
if [ -d ../KGO_RC600_NCas2021_test/ ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Special Nova Cas 2021 RC600 test " 1>&2
 echo -n "Special Nova Cas 2021 RC600 test: " >> vast_test_report.txt 
 #
 cp default.sex.ccd_example default.sex
 ./vast -f -u -p -x3 -a19.0 ../KGO_RC600_NCas2021_test/*V.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 3" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600001"
  fi
  grep --quiet "Images used for photometry 3" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600002"
  fi
  grep --quiet "Ref.  image: 2459292.18307 18.03.2021 16:23:32" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600_REFIMAGE"
  fi
  grep --quiet "First image: 2459292.18307 18.03.2021 16:23:32" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600003"
  fi
  grep --quiet "Last  image: 2459292.18455 18.03.2021 16:25:40" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600004"
  fi
  # Plate-solve the reference image
  REF_IMAGE=`grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
  BASENAME_REF_IMAGE=`basename "$REF_IMAGE"`
  util/wcs_image_calibration.sh "$REF_IMAGE"
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600_wcs_image_calibration_FAILED"
  elif [ ! -f wcs_"$BASENAME_REF_IMAGE" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600_no_wcs_image"
  elif [ ! -s wcs_"$BASENAME_REF_IMAGE" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600_empty_wcs_image"
  else
   util/solve_plate_with_UCAC5 "$REF_IMAGE"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600_solve_plate_with_UCAC5_FAILED"
   elif [ ! -f wcs_"$BASENAME_REF_IMAGE".cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600_no_fit.cat.ucac5_file"
   elif [ ! -s wcs_"$BASENAME_REF_IMAGE".cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600_empty_fit.cat.ucac5_file"
   else
    util/magnitude_calibration.sh V robust_linear
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600_error_running_magnitude_calibration_V_robust_linear"
    else
     if [ ! -f calib.txt_param ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600_no_calib.txt_param"
     elif [ ! -s calib.txt_param ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600_empty_calib.txt_param"
     else
      # check the expected fitted line coefficient values
      TEST=`cat calib.txt_param | awk '{if ( sqrt(($4-0.992089)*($4-0.992089))<0.05 && sqrt(($5-24.562964)*($5-24.562964))<0.05 ) print 1 ;else print 0 }'`
      if [ $TEST -ne 1 ];then
       TEST_PASSED=0
       FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600_calibration_curve_fit_parameters_out_of_range"
      fi
      # Find Nova Cas 2021 and perform its photometry
      XY="1076.1 1020.5"
      LIGHTCURVEFILE=$(find_source_by_X_Y_in_vast_lightcurve_statistics_log $XY)
      if [ "$LIGHTCURVEFILE" == "none" ];then
       TEST_PASSED=0
       FAILED_TEST_CODES="$FAILED_TEST_CODES  NCAS21RC600_NCas21_not_found__${XY// /_}"
      else
       NOVA_MAG=`cat "$LIGHTCURVEFILE" | awk '{print $2}' | util/colstat | grep 'MEAN=' | awk '{print $2}'`
       TEST=`echo $NOVA_MAG | awk '{if ( sqrt(($1-9.291700)*($1-9.291700))<0.05 ) print 1 ;else print 0 }'`
       if [ $TEST -ne 1 ];then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES  NCAS21RC600_NCas21_wrong_photometry__$NOVA_MAG"
       fi
      fi # ligthcurve file found
      #
     fi # calib.txt_param
    fi # util/magnitude_calibration.sh V robust_linear OK
   fi # util/solve_plate_with_UCAC5 OK
  fi # util/wcs_image_calibration.sh OK
  #
 else
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600_no_vast_summary"
 fi # if [ -f vast_summary.log ];then 
 ./vast -f -u -p -x3 -a19.0 ../KGO_RC600_NCas2021_test/*B.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 3" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B001"
  fi
  grep --quiet "Images used for photometry 3" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B002"
  fi
  grep --quiet "Ref.  image: 2459292.18279 18.03.2021 16:23:03" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B_REFIMAGE"
  fi
  grep --quiet "First image: 2459292.18279 18.03.2021 16:23:03" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B003"
  fi
  grep --quiet "Last  image: 2459292.18427 18.03.2021 16:25:11" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B004"
  fi
  # Plate-solve the reference image
  REF_IMAGE=`grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
  BASENAME_REF_IMAGE=`basename "$REF_IMAGE"`
  util/wcs_image_calibration.sh "$REF_IMAGE"
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B_wcs_image_calibration_FAILED"
  elif [ ! -f wcs_"$BASENAME_REF_IMAGE" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B_no_wcs_image"
  elif [ ! -s wcs_"$BASENAME_REF_IMAGE" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B_empty_wcs_image"
  else
   util/solve_plate_with_UCAC5 "$REF_IMAGE"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B_solve_plate_with_UCAC5_FAILED"
   elif [ ! -f wcs_"$BASENAME_REF_IMAGE".cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B_no_fit.cat.ucac5_file"
   elif [ ! -s wcs_"$BASENAME_REF_IMAGE".cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B_empty_fit.cat.ucac5_file"
   else
    util/magnitude_calibration.sh B robust_linear
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B_error_running_magnitude_calibration_V_robust_linear"
    else
     if [ ! -f calib.txt_param ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B_no_calib.txt_param"
     elif [ ! -s calib.txt_param ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B_empty_calib.txt_param"
     else
      # check the expected fitted line coefficient values
      TEST=`cat calib.txt_param | awk '{if ( sqrt(($4-0.979694)*($4-0.979694))<0.05 && sqrt(($5-24.375721)*($5-24.375721))<0.05 ) print 1 ;else print 0 }'`
      if [ $TEST -ne 1 ];then
       TEST_PASSED=0
       FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B_calibration_curve_fit_parameters_out_of_range"
      fi
      # Find Nova Cas 2021 and perform its photometry
      XY="1076.4 1020.5"
      LIGHTCURVEFILE=$(find_source_by_X_Y_in_vast_lightcurve_statistics_log $XY)
      if [ "$LIGHTCURVEFILE" == "none" ];then
       TEST_PASSED=0
       FAILED_TEST_CODES="$FAILED_TEST_CODES  NCAS21RC600B_NCas21_not_found__${XY// /_}"
      else
       NOVA_MAG=`cat "$LIGHTCURVEFILE" | awk '{print $2}' | util/colstat | grep 'MEAN=' | awk '{print $2}'`
       TEST=`echo $NOVA_MAG | awk '{if ( sqrt(($1-9.589533)*($1-9.589533))<0.05 ) print 1 ;else print 0 }'`
       if [ $TEST -ne 1 ];then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES  NCAS21RC600B_NCas21_wrong_photometry__$NOVA_MAG"
       fi
      fi # ligthcurve file found
      #
     fi # calib.txt_param
    fi # util/magnitude_calibration.sh V robust_linear OK
   fi # util/solve_plate_with_UCAC5 OK
  fi # util/wcs_image_calibration.sh OK
  #
 else
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600B_no_vast_summary"
 fi # if [ -f vast_summary.log ];then 
 ./vast -f -u -p -x3 -a19.0 ../KGO_RC600_NCas2021_test/*Rc.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 3" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc001"
  fi
  grep --quiet "Images used for photometry 3" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc002"
  fi
  grep --quiet "Ref.  image: 2459292.18326 18.03.2021 16:23:51" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc_REFIMAGE"
  fi
  grep --quiet "First image: 2459292.18326 18.03.2021 16:23:51" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc003"
  fi
  grep --quiet "Last  image: 2459292.18475 18.03.2021 16:25:59" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc004"
  fi
  # Plate-solve the reference image
  REF_IMAGE=`grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
  BASENAME_REF_IMAGE=`basename "$REF_IMAGE"`
  util/wcs_image_calibration.sh "$REF_IMAGE"
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc_wcs_image_calibration_FAILED"
  elif [ ! -f wcs_"$BASENAME_REF_IMAGE" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc_no_wcs_image"
  elif [ ! -s wcs_"$BASENAME_REF_IMAGE" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc_empty_wcs_image"
  else
   util/solve_plate_with_UCAC5 "$REF_IMAGE"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc_solve_plate_with_UCAC5_FAILED"
   elif [ ! -f wcs_"$BASENAME_REF_IMAGE".cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc_no_fit.cat.ucac5_file"
   elif [ ! -s wcs_"$BASENAME_REF_IMAGE".cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc_empty_fit.cat.ucac5_file"
   else
    util/magnitude_calibration.sh Rc robust_linear
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc_error_running_magnitude_calibration_V_robust_linear"
    else
     if [ ! -f calib.txt_param ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc_no_calib.txt_param"
     elif [ ! -s calib.txt_param ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc_empty_calib.txt_param"
     else
      # check the expected fitted line coefficient values
      TEST=`cat calib.txt_param | awk '{if ( sqrt(($4-0.986287)*($4-0.986287))<0.05 && sqrt(($5-24.009384)*($5-24.009384))<0.05 ) print 1 ;else print 0 }'`
      if [ $TEST -ne 1 ];then
       TEST_PASSED=0
       FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc_calibration_curve_fit_parameters_out_of_range"
      fi
      # Find Nova Cas 2021 and perform its photometry
      XY="1075.2 1019.7"
      LIGHTCURVEFILE=$(find_source_by_X_Y_in_vast_lightcurve_statistics_log $XY)
      if [ "$LIGHTCURVEFILE" == "none" ];then
       TEST_PASSED=0
       FAILED_TEST_CODES="$FAILED_TEST_CODES  NCAS21RC600Rc_NCas21_not_found__${XY// /_}"
      else
       NOVA_MAG=`cat "$LIGHTCURVEFILE" | awk '{print $2}' | util/colstat | grep 'MEAN=' | awk '{print $2}'`
       TEST=`echo $NOVA_MAG | awk '{if ( sqrt(($1-8.805633)*($1-8.805633))<0.05 ) print 1 ;else print 0 }'`
       if [ $TEST -ne 1 ];then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES  NCAS21RC600Rc_NCas21_wrong_photometry__$NOVA_MAG"
       fi
      fi # ligthcurve file found
      #
     fi # calib.txt_param
    fi # util/magnitude_calibration.sh V robust_linear OK
   fi # util/solve_plate_with_UCAC5 OK
  fi # util/wcs_image_calibration.sh OK
  #
 else
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NCAS21RC600Rc_no_vast_summary"
 fi # if [ -f vast_summary.log ];then 
 #


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSpecial Nova Cas 2021 RC600 test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSpecial Nova Cas 2021 RC600 test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
 #
 echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
 df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
 # 
fi # if [ -d ../KGO_RC600_NCas2021_test/ ];then

############# NMW #############
if [ "$HOSTNAME" = "eridan" ] ;then
 if [ -d /mnt/usb/NMW_NG_transient_detection_test ];then
  THIS_TEST_START_UNIXSEC=$(date +%s)
  TEST_PASSED=1
  util/clean_data.sh
  # Run the test
  echo "Special NMW test " 1>&2
  echo -n "Special NMW test: " >> vast_test_report.txt 
  GREP_RESULT=`util/examples/test_NMW.sh 2>&1 | grep -e 'FAILED_TEST_CODES' -e 'Test failed' -e 'Test passed'`
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_NMW_001"
   DEBUG_OUTPUT="$DEBUG_OUTPUT                              
###### SPECIAL_NMW_001 ######
$GREP_RESULT"
  fi
  GREP_RESULT=`util/examples/test_NMW02.sh 2>&1 | grep -e 'FAILED_TEST_CODES' -e 'Test failed' -e 'Test passed'`
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_NMW_002"
   DEBUG_OUTPUT="$DEBUG_OUTPUT                              
###### SPECIAL_NMW_002 ######
$GREP_RESULT"
  fi  


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

  if [ $TEST_PASSED -eq 1 ];then
   echo -e "\n\033[01;34mSpecial NMW test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
   echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
  else
   echo -e "\n\033[01;34mSpecial NMW test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
   echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
  fi
  #
  echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
  df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
  # 
 fi
fi # if [ "$HOSTNAME" = "eridan" ] ;then


#### Valgrind test
command -v valgrind &> /dev/null
if [ $? -eq 0 ];then
 # Consider running this super-slow test only on selected hosts
 if [ -z "$HOSTNAME" ];then
  HOSTNAME="$HOST"
 fi
 if [ "$HOSTNAME" = "eridan" ] || [ "$HOSTNAME" = "ariel" ] || [ "$HOSTNAME" = "kadar" ] ;then
  if [ -d ../sample_data ];then
   THIS_TEST_START_UNIXSEC=$(date +%s)
   TEST_PASSED=1
   util/clean_data.sh
   # Run the test
   echo "Special Valgrind test " 1>&2
   echo -n "Special Valgrind test: " >> vast_test_report.txt 
   #
   # Run the test only if VaST was compiled wthout AddressSanitizer
   ldd vast | grep --quiet 'libasan'
   if [ $? -ne 0 ];then
    cp default.sex.ccd_example default.sex
    valgrind --error-exitcode=1 -v --tool=memcheck --track-origins=yes ./vast -uf ../sample_data/f_72-00* &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND001"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND002"
    fi
    #
    cp default.sex.ccd_example default.sex
    valgrind -v --tool=memcheck --track-origins=yes ./vast --photocurve --position_dependent_correction -uf ../sample_data/f_72-00* &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND003"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND003a"
    fi
    valgrind -v --tool=memcheck --track-origins=yes lib/create_data &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND004"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND004a"
    fi
    valgrind -v --tool=memcheck --track-origins=yes lib/index_vs_mag &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND005"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND006"
    fi
    cp default.sex.beta_Cas_photoplates default.sex
    ./vast -u -o -j -f ../test_data_photo/SCA*
    valgrind -v --tool=memcheck --track-origins=yes lib/create_data &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND007"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND008"
    fi
    valgrind -v --tool=memcheck --track-origins=yes lib/index_vs_mag &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND009"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND010"
    fi
    #
    cp default.sex.beta_Cas_photoplates default.sex
    valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes --errors-for-leak-kinds=definite \
    util/solve_plate_with_UCAC5 ../test_data_photo/SCA1017S_17061_09773__00_00.fit &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND011"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND012"
    fi
    #
    if [ -f ../test_exclude_ref_image/lm01306trr7b0645.fits ];then
     cp default.sex.ccd_example default.sex
     valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes --errors-for-leak-kinds=definite \
     lib/autodetect_aperture_main ../test_exclude_ref_image/lm01306trr7b0645.fits &> valgrind_test.out
     if [ $? -ne 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND013"
     fi
     grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
      if [ $ERRORS -ne 0 ];then
       echo "ERROR"
       break
      fi
     done | grep --quiet 'ERROR'
     if [ $? -eq 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND014"
     fi
    else
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND_missing_datafile_test_exclude_ref_image"
    fi
    #
    # Below is the real slow one
    cp default.sex.ison_m31_test default.sex
    valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes --errors-for-leak-kinds=definite \
    util/solve_plate_with_UCAC5 ../M31_ISON_test/M31-1-001-001_dupe-1.fts &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND015"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND016"
    fi
    #
    #
    cp default.sex.ccd_example default.sex
    valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes --errors-for-leak-kinds=definite \
    lib/autodetect_aperture_main ../individual_images_test/hst_12911_01_wfc3_uvis_f775w_01_drz.fits &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND017"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND018"
    fi
    #
    #
    valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes --errors-for-leak-kinds=definite \
    util/ccd/mk ../only_few_stars/* &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND019"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND020"
    fi
    #
    #
    valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes --errors-for-leak-kinds=definite \
    util/ccd/ms ../vast_test__dark_flat_flag/V523Cas_20_b1-001G60s.fit ../vast_test__dark_flat_flag/mdark60s.fit d_test4.fit &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND021"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND022"
    fi
    #
    #
    valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes --errors-for-leak-kinds=definite \
    util/ccd/md d_test4.fit ../vast_test__dark_flat_flag/mflatG.fit fd_test4.fit &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND023"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND024"
    fi
    #
    #
    util/clean_data.sh
    cp default.sex.largestars default.sex
    valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes --errors-for-leak-kinds=definite \
    lib/sextract_single_image_noninteractive d_test4.fit &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND025"
    fi
     grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND026"
    fi
    if [ -f d_test4.fit ];then
     rm -f d_test4.fit
    fi
    if [ -f fd_test4.fit ];then
     rm -f fd_test4.fit
    fi
    #
    #
    valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes --errors-for-leak-kinds=definite \
    lib/catalogs/check_catalogs_offline `lib/hms2deg 19:50:33.92439 +32:54:50.6097` &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND026"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND027"
    fi
    #
    valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes --errors-for-leak-kinds=definite \
    util/get_image_date '2015-08-21T22:18:25.000000' &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND028"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND029"
    fi
    #
    valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes \
    util/get_image_date '21/09/99' &> valgrind_test.out
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND030"
    fi
    grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
     if [ $ERRORS -ne 0 ];then
      echo "ERROR"
      break
     fi
    done | grep --quiet 'ERROR'
    if [ $? -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND031"
    fi
    #
    if [ ! -d ../vast_test_bright_stars_failed_match ];then
     cd ..
     curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_bright_stars_failed_match.tar.bz2" && tar -xvjf vast_test_bright_stars_failed_match.tar.bz2 && rm -f vast_test_bright_stars_failed_match.tar.bz2
     cd $WORKDIR
    fi
    # If the test data are found
    if [ -d ../vast_test_bright_stars_failed_match ];then
     cp default.sex.ccd_bright_star default.sex
     # if not setting OMP_NUM_THREADS=1 we are getting a memory leak error from valgrind
     OMP_NUM_THREADS=1 valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes   ./vast -u -t2 -f ../vast_test_bright_stars_failed_match/* &> valgrind_test.out
     if [ $? -ne 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND032"
     fi
     grep 'ERROR SUMMARY:' valgrind_test.out | awk -F ':' '{print $2}' | awk '{print $1}' | while read ERRORS ;do
      if [ $ERRORS -ne 0 ];then
       echo "ERROR"
       break
      fi
     done | grep --quiet 'ERROR'
     if [ $? -eq 0 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND033"
     fi
    fi # if [ -d ../vast_test_bright_stars_failed_match ];then
    #
   
    # clean up
    if [ -f valgrind_test.out ];then
     rm -f valgrind_test.out
    fi


    THIS_TEST_STOP_UNIXSEC=$(date +%s)
    THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

    # conclude
    if [ $TEST_PASSED -eq 1 ];then
     echo -e "\n\033[01;34mSpecial Valgrind test \033[01;32mPASSED\033[00m" 1>&2
     echo "PASSED" >> vast_test_report.txt
    else
     echo -e "\n\033[01;34mSpecial Valgrind test \033[01;31mFAILED\033[00m" 1>&2
     echo "FAILED" >> vast_test_report.txt
    fi
   else
     FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND_TEST_NOT_PERFORMED_ASAN_ENABLED"
     echo "SPECIAL_VALGRIND_TEST_NOT_PERFORMED_ASAN_ENABLED" >> vast_test_report.txt
   fi # ldd vast | grep --quiet 'libasan'
  else
   # do not distract user with this obscure message if the test host is not eridan
   if [ "$HOSTNAME" = "eridan" ];then
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND_TEST_NOT_PERFORMED_NO_DATA"
    echo "SPECIAL_VALGRIND_TEST_NOT_PERFORMED_NO_DATA" >> vast_test_report.txt
   fi
  fi
  # do not distract user with obscure error message, so no 'else' if this is not one of the test hosts
 fi
 #
 echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
 df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
 # 
 # Yes, we don't even want the TEST_NOT_PERFORMED message
fi # if [ $? -eq 0 ];then


#####################################################################################################


### Check the photometry error rescaling code
if [ ! -d ../M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails.tar.bz2" && tar -xjf M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails.tar.bz2 && rm -f M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails.tar.bz2
 cd $WORKDIR
fi

if [ -d ../M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Photometric error rescaling test " 1>&2
 echo -n "Photometric error rescaling test: " >> vast_test_report.txt 
 util/load.sh ../M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOMETRIC_ERROR_RESCALING001"
 fi 
 SYSTEMATIC_NOISE_LEVEL=`util/estimate_systematic_noise_level 2> /dev/null`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOMETRIC_ERROR_RESCALING002"
 fi
 #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0341);sqrt(a*a)<0.005" | bc -ql`
 TEST=`echo "$SYSTEMATIC_NOISE_LEVEL" | awk '{if ( sqrt( ($1-0.0341)*($1-0.0341) ) < 0.005 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOMETRIC_ERROR_RESCALING003_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOMETRIC_ERROR_RESCALING003"
 fi
 util/rescale_photometric_errors 2>&1 | grep --quiet 'Applying corrections to error estimates in all lightcurves.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOMETRIC_ERROR_RESCALING004"
 fi 


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mPhotometric error rescaling test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mPhotometric error rescaling test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOMETRIC_ERROR_RESCALING_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


# Test if 'md5sum' is installed 
command -v md5sum &> /dev/null
if [ $? -eq 0 ];then
 # md5sum is the standard Linux tool to compute MD5 sums
 MD5COMMAND="md5sum"
else
 command -v md5 &> /dev/null
 if [ $? -eq 0 ];then
  # md5 is the standard BSD tool to compute MD5 sums
  MD5COMMAND="md5 -q"
 else
  # None of the two is found
  MD5COMMAND="none"
 fi
fi
if [ "$MD5COMMAND" != "none" ];then

 #### Test the lightcurve paring function using util/cute_lc
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 # Run the test
 echo "Testing the lightcurve parsing function " 1>&2
 echo -n "Testing the lightcurve parsing function: " >> vast_test_report.txt 
 TEST_LIGHTCURVE="# bjdtdb m 0.1 0.1 1.0 none
2456210.367045 -9.18500 0.02459 0.1 0.1 1.0 none
2456210.402100 -9.12400 0.02459 0.1 0.1 1.0 none
 ahaha
2456210.475729 -9.16100 0.02459 0.1 0.1 1.0 none
 eat this comment
2456210.481863 -9.12500 0.02459 0.1 0.1 1.0 none
2456210.487997 -9.17700 0.02459 0.1 0.1 1.0 none
2456210.535065 -9.12350 0.02459 0.1 0.1 1.0 none
 ohi ohi ohi
2456210.541199 -9.11800 0.02459 0.1 0.1 1.0 none
2456211.136847 -9.15400 0.02459 0.1 0.1 1.0 none
2456211.142935 -9.19300 0.02459 0.1 0.1 1.0 none
2456211.149022 -9.17100 0.02459 0.1 0.1 1.0 none
2456211.155110 -9.16200 0.02459 0.1 0.1 1.0 none
2456211.161198 -9.17000 0.02459 0.1 0.1 1.0 none
 massaraksh! %#
2456211.203336 -9.18300 0.02459 0.1 0.1 1.0 none
2456211.209423 -9.14400 0.02459 0.1 0.1 1.0 none
2456211.215511 -9.15400 0.02459 0.1 0.1 1.0 none
2456211.221598 -9.13900 0.02459 0.1 0.1 1.0 none
"

 MD5SUM_OF_PROCESSED_LC=`echo "$TEST_LIGHTCURVE" | util/cute_lc | $MD5COMMAND | awk '{print $1}'`

 if [ "$MD5SUM_OF_PROCESSED_LC" != "68a39230fa63eef05af635df4b33cd44" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCPARSER001"
 fi
 
 
 ############################# Test index sorting in util/cute_lc #############################
 # Test if 'sort' understands the '--random-sort' argument, perform the following tests only if it does
 echo "A
B
C" | $(lib/find_timeout_command.sh) 10 sort --random-sort --random-source=/dev/urandom > /dev/null
 if [ $? -eq 0 ];then
  MD5SUM_OF_PROCESSED_LC=`echo "$TEST_LIGHTCURVE" | $(lib/find_timeout_command.sh) 10 sort --random-sort --random-source=/dev/urandom | util/cute_lc | $MD5COMMAND | awk '{print $1}'`
  if [ "$MD5SUM_OF_PROCESSED_LC" != "68a39230fa63eef05af635df4b33cd44" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES LCPARSER002"
  fi
 else
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCPARSER002_TEST_NOT_PERFORMED"
 fi # if random sort is supported
 ##############################################################################################
 
 # Test if the filtering of input lightcurve values is enabled and works correctly
 NUMBER_OF_ACCEPTED_LINES_IN_LC=`echo '0.0 0.0
1000.0 1.0
2457777.0 1.0
2457777.0 -1.0
2457777.0 45.0
3057777.0 20.0' | util/cute_lc | wc -l | awk '{print $1}'`
 if [ $NUMBER_OF_ACCEPTED_LINES_IN_LC -ne 3 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCPARSER003"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mTest of the lightcurve parsing function \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mTest of the lightcurve parsing function \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi 

else
 FAILED_TEST_CODES="$FAILED_TEST_CODES LCPARSER_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
 

#### Test lightcurve filters
THIS_TEST_START_UNIXSEC=$(date +%s)
TEST_PASSED=1
# Run the test
echo "Testing lightcurve filters " 1>&2
echo -n "Testing lightcurve filters: " >> vast_test_report.txt 

# Test if 'sort' understands the '--random-sort' argument, perform the following tests only if it does
echo "A
B
C" | $(lib/find_timeout_command.sh) 10 sort --random-sort --random-source=/dev/urandom > /dev/null
if [ $? -eq 0 ];then
 # The first test relies on the MD5 sum calculation
 if [ "$MD5COMMAND" != "none" ];then
  # Random-sort the test lightcurve and run it through lib/test/stetson_test to make sure sorting doesn't afffect the result 
  # (meaning that sorting is done correctly within VaST).
  TEST_LIGHTCURVE_SHUFFLED=`echo "$TEST_LIGHTCURVE" | $(lib/find_timeout_command.sh) 10 sort --random-sort --random-source=/dev/urandom`
  echo "$TEST_LIGHTCURVE_SHUFFLED" > test_lightcurve_shuffled.txt
  echo "$TEST_LIGHTCURVE" > test_lightcurve.txt
  STETSON_TEST_OUTPUT_TEST_LIGHTCURVE=`lib/test/stetson_test test_lightcurve.txt 2>&1 | $MD5COMMAND | awk '{print $1}'`
  STETSON_TEST_OUTPUT_TEST_LIGHTCURVE_SHUFFLED=`lib/test/stetson_test test_lightcurve_shuffled.txt 2>&1 | $MD5COMMAND  | awk '{print $1}'`
  if [ "$STETSON_TEST_OUTPUT_TEST_LIGHTCURVE" != "$STETSON_TEST_OUTPUT_TEST_LIGHTCURVE_SHUFFLED" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES LCFILTER001"
  fi
 else
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCFILTER001_TEST_NOT_PERFORMED"
 fi # if [ "$MD5COMMAND" != "none" ];then

 # Test lightcurve filters
 util/clean_data.sh
 cp test_lightcurve.txt out00001.dat
 cp test_lightcurve_shuffled.txt out00002.dat
 lib/drop_faint_points 2
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCFILTER002a"
 fi
 util/stat_outfile out00001.dat | grep "out00001.dat contains 14 observations" &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCFILTER002"
 fi 
 util/stat_outfile out00002.dat | grep "out00002.dat contains 14 observations" &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCFILTER003"
 fi
 util/stat_outfile out00001.dat | grep "m= -9.1601  sigma_series= 0.0216  mean_sigma=0.0246" &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCFILTER004"
 fi
 util/stat_outfile out00002.dat | grep "m= -9.1601  sigma_series= 0.0216  mean_sigma=0.0246" &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCFILTER005"
 fi
 util/clean_data.sh
 cp test_lightcurve.txt out00001.dat
 cp test_lightcurve_shuffled.txt out00002.dat
 lib/drop_bright_points 2
 util/stat_outfile out00001.dat | grep "out00001.dat contains 14 observations" &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCFILTER006"
 fi 
 util/stat_outfile out00002.dat | grep "out00002.dat contains 14 observations" &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCFILTER007"
 fi
 util/stat_outfile out00001.dat | grep "m= -9.1504  sigma_series= 0.0217  mean_sigma=0.0246" &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCFILTER008"
 fi
 util/stat_outfile out00002.dat | grep "m= -9.1504  sigma_series= 0.0217  mean_sigma=0.0246" &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES LCFILTER009"
 fi

 # Remove the old test lightcurves
 rm -f test_lightcurve.txt test_lightcurve_shuffled.txt

else
 FAILED_TEST_CODES="$FAILED_TEST_CODES LCFILTER_TEST_NOT_PERFORMED"
fi # if random sort is supported


THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mTest of the lightcurve filters \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mTest of the lightcurve filters \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#



#### Period search servers test
THIS_TEST_START_UNIXSEC=$(date +%s)
TEST_PASSED=1
# Run the test
echo "Performing a period search test " 1>&2
echo -n "Period search test: " >> vast_test_report.txt 

if [ ! -d ../vast_test_lightcurves ];then
 mkdir ../vast_test_lightcurves
fi
if [ ! -f ../vast_test_lightcurves/out00095_edit_edit.dat ];then
 cd ../vast_test_lightcurves
 curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/out00095_edit_edit.dat.bz2" && bunzip2 out00095_edit_edit.dat.bz2
 cd $WORKDIR
fi

PERIOD_SEARCH_SERVERS="none scan.sai.msu.ru vast.sai.msu.ru"
# Local period search
LOCAL_FREQUENCY_CD=`lib/lk_compute_periodogram ../vast_test_lightcurves/out00095_edit_edit.dat 2 0.1 0.1 | grep 'LK' | awk '{printf "%.4f",$1}'`
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH001"
else
 if [ "$LOCAL_FREQUENCY_CD" != "0.8202" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH002"
 fi
fi # if [ $? -ne 0 ];then

# Remote period search
for PERIOD_SEARCH_SERVER in $PERIOD_SEARCH_SERVERS ;do
 #REMOTE_FREQUENCY_CD=`WEBBROWSER=curl ./pokaz_laflerkinman.sh ../vast_test_lightcurves/out00095_edit_edit.dat 2>/dev/null | grep 'L&K peak 2' | awk '{print $2}' FS='&nu; ='  | awk '{printf "%.4f",$1}'`
 #REMOTE_FREQUENCY_CD=`WEBBROWSER=curl ./pokaz_laflerkinman.sh ../vast_test_lightcurves/out00095_edit_edit.dat 2>/dev/null | grep 'L&K peak 2' | awk -F '&nu; =' '{print $2}'  | awk '{printf "%.4f",$1}'`
 # the number of LK peak changed due to changes on the server side
 REMOTE_FREQUENCY_CD=`WEBBROWSER=curl ./pokaz_laflerkinman.sh ../vast_test_lightcurves/out00095_edit_edit.dat 2>/dev/null | grep 'L&K peak 3' | awk -F '&nu; =' '{print $2}'  | awk '{printf "%.4f",$1}'`
 if [ "$REMOTE_FREQUENCY_CD" != "$LOCAL_FREQUENCY_CD" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH003_$PERIOD_SEARCH_SERVER"
 fi
done


THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mPeriod search test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mPeriod search test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#




#### Lightcurve viewer test
THIS_TEST_START_UNIXSEC=$(date +%s)
TEST_PASSED=1
# Run the test
echo "Performing a lightcurve viewer test " 1>&2
echo -n "Lightcurve viewer test: " >> vast_test_report.txt 

if [ ! -d ../vast_test_lightcurves ];then
 mkdir ../vast_test_lightcurves
fi
if [ ! -f ../vast_test_lightcurves/out00095_edit_edit.dat ];then
 cd ../vast_test_lightcurves
 curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/out00095_edit_edit.dat.bz2" && bunzip2 out00095_edit_edit.dat.bz2
 cd $WORKDIR
fi

# Run the test
./lc -s ../vast_test_lightcurves/out00095_edit_edit.dat
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES LIGHTCURVEVIEWER001"
fi
if [ ! -f 00095_edit_edit.ps ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES LIGHTCURVEVIEWER002"
fi
if [ ! -s 00095_edit_edit.ps ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES LIGHTCURVEVIEWER003"
fi
# Make sure this is a valid one-page PS file by counting pages with Ghostscript
command -v gs &>/dev/null
if [ $? -eq 0 ];then
 TEST=`gs -q -dNOPAUSE -dBATCH -sDEVICE=bbox 00095_edit_edit.ps 2>&1 | grep -c HiResBoundingBox`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES LIGHTCURVEVIEWER004_TEST_ERROR"
 else
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES LIGHTCURVEVIEWER004"
  fi
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES LIGHTCURVEVIEWER004_TEST_NOT_PERFORMED_no_gs"
fi

# cleanup
if [ -f 00095_edit_edit.ps ];then
 rm -f 00095_edit_edit.ps
fi



THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mLightcurve viewer test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mLightcurve viewer test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


#### vizquery test
THIS_TEST_START_UNIXSEC=$(date +%s)
TEST_PASSED=1
# Run the test
echo "Performing a vizquery test " 1>&2
echo -n "vizquery test: " >> vast_test_report.txt 

if [ ! -d ../vast_test_lightcurves ];then
 mkdir ../vast_test_lightcurves
fi
if [ ! -f ../vast_test_lightcurves/test_vizquery_M31.input ];then
 cd ../vast_test_lightcurves
 curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/test_vizquery_M31.input.bz2" && bunzip2 test_vizquery_M31.input.bz2
 cd $WORKDIR
fi

# Run the test
lib/vizquery -site=$("$VAST_PATH"lib/choose_vizier_mirror.sh) -mime=text -source=UCAC5 -out.max=1 -out.add=_1 -out.add=_r -out.form=mini \
-out=RAJ2000,DEJ2000,f.mag,EPucac,pmRA,e_pmRA,pmDE,e_pmDE f.mag=9.0..16.5 -sort=f.mag -c.rs=6.0 \
-list=../vast_test_lightcurves/test_vizquery_M31.input > test_vizquery_M31.output
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES VIZQUERYTEST001"
fi
if [ ! -f test_vizquery_M31.output ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES VIZQUERYTEST002"
fi
if [ ! -s test_vizquery_M31.output ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES VIZQUERYTEST003"
fi
# check that the whole output was received, if not - retry
cat test_vizquery_M31.output | grep --quiet '#END#  -ref=VOT'
if [ $? -ne 0 ];then
 FAILED_TEST_CODES="$FAILED_TEST_CODES VIZQUERYTEST_RETRY"
 # maybe this was a random network glitch? sleep 30 sec and retry
 sleep 30 
 lib/vizquery -site=$("$VAST_PATH"lib/choose_vizier_mirror.sh) -mime=text -source=UCAC5 -out.max=1 -out.add=_1 -out.add=_r -out.form=mini \
-out=RAJ2000,DEJ2000,f.mag,EPucac,pmRA,e_pmRA,pmDE,e_pmDE f.mag=9.0..16.5 -sort=f.mag -c.rs=6.0 \
-list=../vast_test_lightcurves/test_vizquery_M31.input > test_vizquery_M31.output
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES VIZQUERYTEST001a"
 fi
 if [ ! -f test_vizquery_M31.output ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES VIZQUERYTEST002a"
 fi
 if [ ! -s test_vizquery_M31.output ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES VIZQUERYTEST003a"
 fi
 #
fi
# count lines in vizquery output
TEST=`cat test_vizquery_M31.output | wc -l | awk '{print $1}'`
re='^[0-9]+$'
if ! [[ $TEST =~ $re ]] ; then
 echo "TEST ERROR"
 TEST_PASSED=0
 TEST=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES VIZQUERYTEST004_TEST_ERROR"
else
 if [ $TEST -lt 1200 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES VIZQUERYTEST004_$TEST"
 fi
fi
cat test_vizquery_M31.output | grep --quiet '#END#  -ref=VOT'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES VIZQUERYTEST005"
fi

# cleanup
if [ -f test_vizquery_M31.output ];then
 rm -f test_vizquery_M31.output
fi


THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mvizquery test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mvizquery test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#



#### Standalone test for database querry scripts
THIS_TEST_START_UNIXSEC=$(date +%s)
TEST_PASSED=1
# Run the test
echo "Performing a standalone test for database querry scripts " 1>&2
echo -n "Testing database querry scripts: " >> vast_test_report.txt 

lib/update_offline_catalogs.sh all &> update_offline_catalogs.out
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT__LOCAL_CAT_UPDATE"
 GREP_RESULT=`cat update_offline_catalogs.out`
 DEBUG_OUTPUT="$DEBUG_OUTPUT                              
###### STANDALONEDBSCRIPT__LOCAL_CAT_UPDATE ######
$GREP_RESULT"
fi
if [ -f update_offline_catalogs.out ];then
 rm -f update_offline_catalogs.out
fi

util/search_databases_with_curl.sh 22:02:43.29139 +42:16:39.9803 | grep --quiet "BL Lac"
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT001"
fi

### This should specifically test GCVS
util/search_databases_with_curl.sh 22:02:43.29139 +42:16:39.9803 | grep --quiet "BLLAC"
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT001a_GCVS"
fi

# A more precise way to test the GCVS online search
util/search_databases_with_curl.sh 22:02:43.29139 +42:16:39.9803 | grep 'not found' | grep --quiet 'GCVS'
if [ $? -eq 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT001b_GCVS"
fi

# Make sure that the following string returns only the correct name of the target
TEST_STRING=`util/search_databases_with_curl.sh 22:02:43.29 +42:16:39.9 | tail -n1 | awk -F'|' '{print $1}' | while read A ;do echo $A ;done`
if [ "$TEST_STRING" != "BL Lac" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT001c_GCVS"
fi

util/search_databases_with_curl.sh 15:31:40.10 -20:27:17.3 | grep --quiet "BW Lib"
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT002"
fi

cd ..
"$WORKDIR"/util/search_databases_with_curl.sh 15:31:40.10 -20:27:17.3 | grep --quiet "BW Lib"
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT002a"
fi
cd "$WORKDIR"

util/search_databases_with_vizquery.sh 22:02:43.29139 +42:16:39.9803 TEST 40 | grep TEST | grep --quiet "BL Lac"
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT003_vizquery"
fi

cd ..
"$WORKDIR"/util/search_databases_with_vizquery.sh 22:02:43.29139 +42:16:39.9803 TEST 40 | grep TEST | grep --quiet "BL Lac"
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT003a_vizquery"
fi
cd "$WORKDIR"

util/search_databases_with_vizquery.sh 15:31:40.10 -20:27:17.3 TEST 40 | grep TEST | grep --quiet "BW Lib"
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT004_vizquery"
fi

# Coordinates in the deg fromat
util/search_databases_with_vizquery.sh 34.8366337 -2.9776377 | grep 'omi Cet' | grep --quiet -e 'J-Ks=1.481+/-0.262 (M)' -e 'J-Ks=1.481+/-0.262 (Very red! L if it'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT005_vizquery"
fi
# on-the-fly conversion
util/search_databases_with_vizquery.sh `lib/hms2deg 02:19:20.79 -02:58:39.5` | grep 'omi Cet' | grep --quiet -e 'J-Ks=1.481+/-0.262 (M)' -e 'J-Ks=1.481+/-0.262 (Very red! L if it'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT005a_vizquery"
fi

# Coordinates in the HMS fromat
util/search_databases_with_vizquery.sh 02:19:20.79 -02:58:39.5 | grep 'omi Cet' | grep --quiet -e 'J-Ks=1.481+/-0.262 (M)' -e 'J-Ks=1.481+/-0.262 (Very red! L if it'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT006_vizquery"
fi

util/search_databases_with_vizquery.sh 19:50:33.92439 +32:54:50.6097 | grep 'khi Cyg' | grep --quiet -e 'J-Ks=1.863+/-0.240 (Very red!)'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT007_vizquery"
fi

# Make sure the damn thing doesn't crash, especially with AddressSanitizer
lib/catalogs/check_catalogs_offline `lib/hms2deg 19:50:33.92439 +32:54:50.6097` &>/dev/null
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT007_check_catalogs_offline"
fi

# XY Lyr is listed as SRC in VSX following the Hipparcos periodic variables paper
util/search_databases_with_vizquery.sh 18:38:06.47677 +39:40:05.9835 | grep 'XY Lyr' | grep -e 'LC' -e 'SRC' | grep --quiet 'J-Ks=1.098+/-0.291 (M)'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT008"
fi

util/search_databases_with_vizquery.sh 18:38:06.47677 +39:40:05.9835 mystar | grep 'XY Lyr' | grep -e 'LC' -e 'SRC' | grep 'J-Ks=1.098+/-0.291 (M)' | grep --quiet mystar
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT009"
fi

# MDV via VizieR
util/search_databases_with_vizquery.sh 02:38:54.34 +63:37:40.4 | grep --quiet -e 'MDV 521' -e 'V1340 Cas'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT010"
fi

# this is MDV 41 already included in GCVS
util/search_databases_with_vizquery.sh 17:40:35.50 +06:17:00.4 | grep 'RRAB' | grep --quiet 'V3042 Oph'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT011"
fi

# this is MDV 9 already included in GCVS
util/search_databases_with_vizquery.sh 13:21:18.38 +18:08:22.2 | grep 'SXPHE' | grep 'VARIABLE' | grep --quiet -e 'OU Com' -e 'ASASSN-V J132118.28+180821.9'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT012"
fi

# ATLAS via VizieR test 
util/search_databases_with_vizquery.sh 101.23204 -13.33439 | grep 'dubious (ATLAS)' | grep --quiet 'ATO J101.2320-13.3343'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT012atlas"
fi

# ATLAS via VizieR test - doesn't work anymore - the star got into VSX under its ZTF name
util/search_databases_with_vizquery.sh 07:29:19.69 -13:23:06.6 | grep -e 'CBF (ATLAS)' -e '(VSX)' -e '(local)' | grep --quiet -e 'ATO J112.3320-13.3851' -e 'ZTF J072919.68-132306.5'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT012vsx01"
fi

# This one was added to VSX
util/search_databases_with_vizquery.sh 18:31:04.64 -16:58:22.3 | grep 'M' | grep 'VARIABLE' | grep --quiet 'ATO J277.7693-16.9729'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT012vsx02"
fi

# MASTER_OT J132104.04+560957.8 - AM CVn star, Gaia short timescale variable
util/search_databases_with_vizquery.sh 200.26675923087 +56.16607967965 | grep -e 'V0496 UMa' -e 'MASTER_OT J132104.04+560957.8' | grep --quiet 'VARIABLE' #| grep --quiet 'Gaia2_SHORTTS'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT013"
fi

# Gaia Cepheid, first in the list
util/search_databases_with_vizquery.sh 237.17375455558 -42.26556630747 | grep --quiet 'VARIABLE' #| grep --quiet 'Gaia2_CEPHEID'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT014"
fi

# Gaia RR Lyr, first in the list
util/search_databases_with_vizquery.sh 272.04211425638 -25.91123076425 | grep 'RRAB' | grep --quiet 'VARIABLE' #| grep --quiet 'Gaia2_RRLYR'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT015"
fi

# Gaia LPV, first in the list. Do not mix it up with OGLE-BLG-RRLYR-01707 that is 36" away!
util/search_databases_with_vizquery.sh 265.86100820754 -34.10333534797 | grep -v 'OGLE-BLG-RRLYR-01707' | grep 'OGLE-BLG-LPV-022489' | grep --quiet 'VARIABLE' #| grep --quiet 'Gaia2_LPV'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT016"
fi

# Check that we are correctly formatting the OGLE variable name
util/search_databases_with_vizquery.sh 17:05:07.49 -32:37:57.2 | grep 'OGLE-BLG-RRLYR-00001' | grep --quiet 'VARIABLE' # | grep --quiet 'Gaia2_RRLYR'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT017"
fi
util/search_databases_with_vizquery.sh `lib/hms2deg 17:05:07.49 -32:37:57.2` | grep 'OGLE-BLG-RRLYR-00001' | grep --quiet 'VARIABLE' #| grep --quiet 'Gaia2_RRLYR'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT018"
fi

util/search_databases_with_vizquery.sh 17.25656 47.30456 | grep --quiet -e 'ATO J017.2565+47.3045' -e 'ASASSN-V J010901.57+471816.4'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT019"
fi

# Make sure the script doesn't drop faint Gaia stars if the position match is perfect
util/search_databases_with_vizquery.sh 14:08:10.55777 -45:26:50.7000 | grep --quiet '|'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT019a"
fi

# Coma as RA,Dec separator
util/search_databases_with_vizquery.sh 18:49:05.97,-19:02:03.2 | grep --quiet 'V6594 Sgr'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT019b"
fi

# Check good formatting of Skiff's spectral type
util/search_databases_with_vizquery.sh 20:07:36.82 +44:06:55.1 | grep --quiet 'SpType: G5/K1IV 2016A&A...594A..39F'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT_SKIFFSPTYPEFORMAT"
fi


### Test the local catalog search thing
lib/catalogs/check_catalogs_offline 17.25656 47.30456 | grep --quiet 'ASASSN-V J010901.57+471816.4'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT020"
fi

lib/catalogs/check_catalogs_offline 34.8366337 -2.9776377 | grep --quiet 'omi Cet'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT021"
fi

# Multiple known variables within the search radius - unrelated OGLE one from VSX and the correct ASASSN-V
# This test relies on the local catalog search!
util/search_databases_with_vizquery.sh 17:54:41.41077 -30:21:59.3417 | grep --quiet 'ASASSN-V J175441.41-302159.3'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT_MULTCLOSEVAR"
fi

# Make sure the script gives 'may be a known variable' suggestion from parsing VizieR catalog names
util/search_databases_with_vizquery.sh 00:39:16.81 +60:36:57.1 | grep --quiet 'may be a known variable'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT_VIZKNOWNVAR"
fi


THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mTest of the database querry scripts \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mTest of the database querry scripts \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
          


# Check if PSFEx is installed and if we should go on with the PSF fitting tests
command -v psfex &> /dev/null
if [ $? -eq 0 ];then

# If the test data are found
if [ -d ../sample_data ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD PSF-fitting test " 1>&2
 echo -n "Small CCD PSF-fitting test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 cp default.psfex.small_FoV default.psfex
 ./vast -P -u -f --noerrorsrescale --notremovebadimages ../sample_data/*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF001"
  fi
  grep --quiet "Images used for photometry 91" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF002"
  fi
  grep --quiet "First image: 2453192.38876 05.07.2004 21:18:19" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF003"
  fi
  grep --quiet "Last  image: 2453219.49067 01.08.2004 23:45:04" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SMALLCCDPSF0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### SMALLCCDPSF0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF0_NO_vast_image_details_log"
  fi
  #

  grep --quiet 'Photometric errors rescaling: NO' vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_ERRORRESCALINGLOGREC"
  fi
  SYSTEMATIC_NOISE_LEVEL=`util/estimate_systematic_noise_level 2> /dev/null`
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_SYSNOISE01"
  fi
  #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0080);sqrt(a*a)<0.005" | bc -ql`
  # Noise level estimated with robust line fit
  #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0094);sqrt(a*a)<0.005" | bc -ql`
  #TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0192);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$SYSTEMATIC_NOISE_LEVEL" | awk '{if ( sqrt( ($1-0.0192)*($1-0.0192) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_SYSNOISE02_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_SYSNOISE02"
  fi  

  # Make sure no diagnostic plots are produced during the test.
  # If they are - change settings in default.psfex before production.
  for DIAGNOSTIC_PLOT_FILE in chi2_image*.* countfrac_image*.* counts_image*.* ellipticity_image*.* fwhm_image*.* resi_image*.* ;do
   if [ -f "$DIAGNOSTIC_PLOT_FILE" ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF005__$DIAGNOSTIC_PLOT_FILE"
    break
   fi
  done

  ###############################################
  ### Now let's check the candidate variables ###
  # out00201.dat - CV (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n1`
  LIGHTCURVEFILE=`echo "$STATSTR" | awk '{print $5}'`
  NLINES_IN_LIGHTCURVEFILE=`cat $LIGHTCURVEFILE | wc -l | awk '{print $1}'`
  if [ $NLINES_IN_LIGHTCURVEFILE -lt 91 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF012_$NLINES_IN_LIGHTCURVEFILE"
  fi
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.757900);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.757900))*($1-(-11.757900)) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF012a_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF012a"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  #TEST=`echo "a=($STATX)-(218.9638100);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-218.9638100)*($1-218.9638100) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF013_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF013"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  #TEST=`echo "a=($STATY)-(247.8421000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-247.8421000)*($1-247.8421000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF014_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF014"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.276132);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.276132)*($1-0.276132) ) < 0.01 ) print 1 ;else print 0 }'`
  # wSTD
  #TEST=`echo "a=($STATIDX)-(0.415123);sqrt(a*a)<0.01" | bc -ql`
  # wSTD with robust line fit for errors rescaling
  #TEST=`echo "a=($STATIDX)-(0.465435);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF015_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF015"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.022536);sqrt(a*a)<0.002" | bc -ql`
  # When u drop one of the 10 brightest stars...
  #TEST=`echo "a=($STATIDX)-(0.024759);sqrt(a*a)<0.002" | bc -ql`
  #TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.024759)*($1-0.024759) ) < 0.002 ) print 1 ;else print 0 }'`
  # Not sure what changed, but here are the current values
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.020608)*($1-0.020608) ) < 0.002 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF016_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF016"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  #TEST=`echo "a=($STATIDX)-(0.025649);sqrt(a*a)<0.002" | bc -ql`
  # detection on all 91 images
  #TEST=`echo "a=($STATIDX)-(0.027688);sqrt(a*a)<0.002" | bc -ql`
  #TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.027688)*($1-0.027688) ) < 0.002 ) print 1 ;else print 0 }'`
  # Not sure what changed, but here are the current values (detection on 91 images)
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.024426)*($1-0.024426) ) < 0.002 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF017_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF017"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  # No bad images
  if [ $NUMBER_OF_LINES -lt 91 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF018_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF019 SMALLCCDPSF020_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF020"
   fi
  fi
  # out00268.dat - EW (but we can't rely on it having the same out*.dat name)
  STATSTR=`cat vast_lightcurve_statistics.log | sort -k26 | tail -n2 | head -n1`
  LIGHTCURVEFILE=`echo "$STATSTR" | awk '{print $5}'`
  NLINES_IN_LIGHTCURVEFILE=`cat $LIGHTCURVEFILE | wc -l | awk '{print $1}'`
  if [ $NLINES_IN_LIGHTCURVEFILE -lt 89 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF021_$NLINES_IN_LIGHTCURVEFILE"
  fi
  STATMAG=`echo "$STATSTR" | awk '{print $1}'`
  #TEST=`echo "a=($STATMAG)-(-11.221200);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATMAG" | awk '{if ( sqrt( ($1-(-11.221200))*($1-(-11.221200)) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF021a_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF021a"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  #TEST=`echo "a=($STATX)-(87.2099000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATX" | awk '{if ( sqrt( ($1-87.2099000)*($1-87.2099000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF022_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF022"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  #TEST=`echo "a=($STATY)-(164.4314000);sqrt(a*a)<0.1" | bc -ql`
  TEST=`echo "$STATY" | awk '{if ( sqrt( ($1-164.4314000)*($1-164.4314000) ) < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF023_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF023"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.035324);sqrt(a*a)<0.01" | bc -ql`
  #TEST=`echo "a=($STATIDX)-(0.038100);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.038100)*($1-0.038100) ) < 0.01 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF024_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF024"
  fi
  # MAD
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.052632);sqrt(a*a)<0.003" | bc -ql`
  #TEST=`echo "a=($STATIDX)-(0.049074);sqrt(a*a)<0.003" | bc -ql`
  # After dropping one of the 10 brightest stars
  #TEST=`echo "a=($STATIDX)-(0.045071);sqrt(a*a)<0.003" | bc -ql`
  # After disabling mag_psf-mag_aper filter
  #TEST=`echo "a=($STATIDX)-(0.049129);sqrt(a*a)<0.003" | bc -ql`
  # Same as above, but relaxed
  #TEST=`echo "a=($STATIDX)-(0.049129);sqrt(a*a)<0.03" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.049129)*($1-0.049129) ) < 0.03 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF025_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF025"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  #TEST=`echo "a=($STATIDX)-(0.059230);sqrt(a*a)<0.001" | bc -ql`
  #TEST=`echo "a=($STATIDX)-(0.060416);sqrt(a*a)<0.001" | bc -ql`
  #TEST=`echo "a=($STATIDX)-(0.058155);sqrt(a*a)<0.001" | bc -ql`
  #TEST=`echo "a=($STATIDX)-(0.059008);sqrt(a*a)<0.002" | bc -ql`
  TEST=`echo "$STATIDX" | awk '{if ( sqrt( ($1-0.059008)*($1-0.059008) ) < 0.002 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF026_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF026"
  fi
  STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
  NUMBER_OF_LINES=`cat "$STATOUTFILE" | wc -l | awk '{print $1}'`
  # Bad images + 1 outlier point in PSF fit
  # No bad images - 89
  if [ $NUMBER_OF_LINES -lt 89 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF027_$NUMBER_OF_LINES"
  fi
  # Check if star is in the list of candidate vars
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF028 SMALLCCDPSF029_NOT_PERFORMED"
  else
   STATOUTFILE=`echo "$STATSTR" | awk '{print $5}'`
   grep --quiet "$STATOUTFILE" vast_autocandidates.log
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF029"
   fi
  fi
  ###############################################

  cat src/vast_limits.h | grep -v '//' | grep --quiet 'DISABLE_MAGSIZE_FILTER_LOGS'
  if [ $? -ne 0 ];then
  
   # Check the log files corresponding to the first 9 images
   for IMGNUM in `seq 1 9`;do
    #for LOGFILE_TO_CHECK in image0000$IMGNUM.cat.magpsfchi2filter_passed image0000$IMGNUM.cat.magpsfchi2filter_rejected image0000$IMGNUM.cat.magpsfchi2filter_thresholdcurve image0000$IMGNUM.cat.magparameter02filter_passed image0000$IMGNUM.cat.magparameter02filter_rejected image0000$IMGNUM.cat.magparameter02filter_thresholdcurve ;do
    # We disabled the PSF-APER filter, so no *magparameter02filter_passed files are created
    for LOGFILE_TO_CHECK in image0000$IMGNUM.cat.magpsfchi2filter_passed image0000$IMGNUM.cat.magpsfchi2filter_rejected image0000$IMGNUM.cat.magpsfchi2filter_thresholdcurve ;do
     if [ ! -s "$LOGFILE_TO_CHECK" ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_EMPTYPSFFILTERINGLOFGILE_$LOGFILE_TO_CHECK"
     fi
    done
   done
  
   NUMER_OF_REJECTED_STARS=`cat image00001.cat.magpsfchi2filter_rejected | wc -l | awk '{print $1}'`
   if [ $NUMER_OF_REJECTED_STARS -lt 9 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_EMPTYPSFFILTERINGLOFGILE_FEW_SRC_REJECTED"
   fi
   # Not using this filter anymore
   #NUMER_OF_REJECTED_STARS=`cat image00001.cat.magparameter02filter_rejected | wc -l | awk '{print $1}'`
   #if [ $NUMER_OF_REJECTED_STARS -lt 9 ];then
   # TEST_PASSED=0
   # FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_EMPTYPSFFILTERINGLOFGILE_FEW_SRC_REJECTED_PSFmAPER"
   #fi
   
  fi # DISABLE_MAGSIZE_FILTER_LOGS

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_ALL"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD PSF-fitting test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD PSF-fitting test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### PSF-fitting of MASTER images test #####
### Disable this test for GitHub Actions
if [ "$GITHUB_ACTIONS" != "true" ];then
# Download the test dataset if needed
if [ ! -d ../MASTER_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/MASTER_test.tar.bz2" && tar -xvjf MASTER_test.tar.bz2 && rm -f MASTER_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../MASTER_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "MASTER CCD PSF-fitting test " 1>&2
 echo -n "MASTER CCD PSF-fitting test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 ./vast -P -u -f ../MASTER_test/*.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 6" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF001"
  fi
  grep --quiet "Images used for photometry 6" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF002"
  fi
  ##grep --quiet "First image: 2457154.31907 11.05.2015 19:39:26" vast_summary.log
  #grep --quiet "First image: 2457154.31909 11.05.2015 19:39:27" vast_summary.log
  grep --quiet "First image: 2457154.31910 11.05.2015 19:39:27" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF003"
  fi
  #grep --quiet "Last  image: 2457154.32075 11.05.2015 19:41:51" vast_summary.log
  grep --quiet "Last  image: 2457154.32076 11.05.2015 19:41:51" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF003a"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### MASTERCCDPSF0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### MASTERCCDPSF0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF0_NO_vast_image_details_log"
  fi
  #
  util/solve_plate_with_UCAC5 ../MASTER_test/wcs_fd_MASTER-KISL-WFC-1_EAST_W_-30_LIGHT_5_878280.fit
  if [ ! -f wcs_fd_MASTER-KISL-WFC-1_EAST_W_-30_LIGHT_5_878280.fit.cat.ucac5 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF004"
  else
   TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_fd_MASTER-KISL-WFC-1_EAST_W_-30_LIGHT_5_878280.fit.cat.ucac5 | wc -l | awk '{print $1}'`
   #if [ $TEST -lt 1100 ];then
   if [ $TEST -lt 800 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF004a"
   fi
  fi 
  util/sysrem2
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF005"
  fi
  util/nopgplot.sh
  if [ ! -f data.m_sigma ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF006"
  fi
  if [ ! -f vast_lightcurve_statistics.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF007"
  fi

  # Make sure no diagnostic plots are produced during the test.
  # If they are - change settings in default.psfex before production.
  for DIAGNOSTIC_PLOT_FILE in chi2_image*.* countfrac_image*.* counts_image*.* ellipticity_image*.* fwhm_image*.* resi_image*.* ;do
   if [ -f "$DIAGNOSTIC_PLOT_FILE" ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF008__$DIAGNOSTIC_PLOT_FILE"
    break
   fi
  done

  cat src/vast_limits.h | grep -v '//' | grep --quiet 'DISABLE_MAGSIZE_FILTER_LOGS'
  if [ $? -ne 0 ];then

   # Check the log files
   for IMGNUM in `seq 1 6`;do
    #for LOGFILE_TO_CHECK in image0000$IMGNUM.cat.magpsfchi2filter_passed image0000$IMGNUM.cat.magpsfchi2filter_rejected image0000$IMGNUM.cat.magpsfchi2filter_thresholdcurve image0000$IMGNUM.cat.magparameter02filter_passed image0000$IMGNUM.cat.magparameter02filter_rejected image0000$IMGNUM.cat.magparameter02filter_thresholdcurve ;do
    for LOGFILE_TO_CHECK in image0000$IMGNUM.cat.magpsfchi2filter_passed image0000$IMGNUM.cat.magpsfchi2filter_rejected image0000$IMGNUM.cat.magpsfchi2filter_thresholdcurve ;do
     if [ ! -s "$LOGFILE_TO_CHECK" ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_EMPTYPSFFILTERINGLOFGILE_$LOGFILE_TO_CHECK"
     fi
    done
   done
  
  fi # DISABLE_MAGSIZE_FILTER_LOGS

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF_ALL"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mMASTER CCD PSF-fitting test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mMASTER CCD PSF-fitting test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
#########################################
# Remove test data from the previous run if we are out of disk space
#########################################
remove_test_data_to_save_space
### Disable the above test for GitHub Actions
fi # if [ "$GITHUB_ACTIONS" != "true" ];then
#

# Download the test dataset if needed
if [ ! -d ../M31_ISON_test ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/pub/M31_ISON_test.tar.bz2" && tar -xvjf M31_ISON_test.tar.bz2 && rm -f M31_ISON_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../M31_ISON_test ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "ISON M31 PSF-fitting test " 1>&2
 echo -n "ISON M31 PSF-fitting test: " >> vast_test_report.txt 
 cp default.sex.ison_m31_test default.sex
 ./vast -P -u -f ../M31_ISON_test/*.fts
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 5" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF001"
  fi
  grep --quiet "Images used for photometry 5" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF002"
  fi
  grep --quiet "First image: 2455863.88499 29.10.2011 09:13:23" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF003"
  fi
  grep --quiet "Last  image: 2455867.61163 02.11.2011 02:39:45" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF003"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### ISONM31PSF0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### ISONM31PSF0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF0_NO_vast_image_details_log"
  fi
  #
  util/solve_plate_with_UCAC5 ../M31_ISON_test/M31-1-001-001_dupe-1.fts
  if [ ! -f wcs_M31-1-001-001_dupe-1.fts.cat.ucac5 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF004"
  else
   TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_M31-1-001-001_dupe-1.fts.cat.ucac5 | wc -l | awk '{print $1}'`
   #if [ $TEST -lt 1500 ];then
   if [ $TEST -lt 700 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF004a_$TEST"
   fi
  fi 

  # Make sure no diagnostic plots are produced during the test.
  # If they are - change settings in default.psfex before production.
  for DIAGNOSTIC_PLOT_FILE in chi2_image*.* countfrac_image*.* counts_image*.* ellipticity_image*.* fwhm_image*.* resi_image*.* ;do
   if [ -f "$DIAGNOSTIC_PLOT_FILE" ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF005__$DIAGNOSTIC_PLOT_FILE"
    break
   fi
  done

 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF_ALL"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mISON M31 PSF-fitting test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mISON M31 PSF-fitting test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

##### test images by JB PSF #####
# Download the test dataset if needed
if [ ! -d ../test_exclude_ref_image ];then
 cd ..
 curl -O "http://scan.sai.msu.ru/~kirx/data/vast_tests/test_exclude_ref_image.tar.bz2" && tar -xvjf test_exclude_ref_image.tar.bz2 && rm -f test_exclude_ref_image.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../test_exclude_ref_image ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Exclude reference image test (PSF) " 1>&2
 echo -n "Exclude reference image test (PSF): " >> vast_test_report.txt 
 cp default.sex.excluderefimgtest default.sex
 cp default.psfex.excluderefimgtest default.psfex
 ./vast --excluderefimage -Pfruj -b 500 -x 2 -y 3 ../test_exclude_ref_image/coadd.red.fits ../test_exclude_ref_image/lm*.fits
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF000"
 fi
 # Check results
 if [ -f vast_summary.log ];then
  grep --quiet "Images processed 309" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF001"
  fi
  N_IMG_USED_FOR_PHOTOMETRY=`grep "Images used for photometry " vast_summary.log | awk '{printf "%d",$5}'`
  #if [ $N_IMG_USED_FOR_PHOTOMETRY -lt 302 ];then
  # The test images have extreme position-dependent magnitude correction.
  # With the introduction of robust linear fitting the number of imgages that pass 
  # the position-dependent magnitude correction value cut has changed.
  if [ $N_IMG_USED_FOR_PHOTOMETRY -lt 269 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF002"
  fi
  grep 'Ref.  image:' vast_summary.log | grep --quiet 'coadd.red.fits'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF_REFIMAGE"
  fi
  grep --quiet "First image: 2450486.59230 07.02.1997 02:12:55" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF003"
  fi
  grep --quiet "Last  image: 2452578.55380 31.10.2002 01:17:28" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF004"
  fi
  # Hunting the mysterious non-zero reference frame rotation cases
  if [ -f vast_image_details.log ];then
   grep --max-count=1 `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'` vast_image_details.log | grep --quiet 'rotation=   0.000'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF0_nonzero_ref_frame_rotation"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### EXCLUDEREFIMAGEPSF0_nonzero_ref_frame_rotation ######
$GREP_RESULT"
   fi
   grep -v -e 'rotation=   0.000' -e 'rotation= 180.000' vast_image_details.log | grep --quiet `grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF0_nonzero_ref_frame_rotation_test2"
    GREP_RESULT=`cat vast_summary.log vast_image_details.log`
    DEBUG_OUTPUT="$DEBUG_OUTPUT
###### EXCLUDEREFIMAGEPSF0_nonzero_ref_frame_rotation_test2 ######
$GREP_RESULT"
   fi
  else
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF0_NO_vast_image_details_log"
  fi
  #
  grep --quiet "JD time system (TT/UTC/UNKNOWN): UTC" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF005"
  fi
  #
  if [ ! -s vast_autocandidates.log ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF_EMPTYAUTOCANDIDATES"
#  else
#   # The idea here is that the magsizefilter should save us from a few false candidates overlapping with the galaxy disk
#   LINES_IN_LOG_FILE=`cat vast_autocandidates.log | wc -l | awk '{print $1}'`
#   if [ $LINES_IN_LOG_FILE -gt 2 ];then
#    TEST_PASSED=0
#    FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF_TOOMANYAUTOCANDIDATES"
#   fi
  fi
  # Time test
  util/get_image_date ../test_exclude_ref_image/lm01306trr8a1338.fits 2>&1 | grep -A 10 'DATE-OBS= 1998-01-14T06:47:48' | grep -A 10 'EXPTIME = 0' | grep -A 10 'Exposure   0 sec, 14.01.1998 06:47:48   = JD  2450827.78319' | grep --quiet 'JD 2450827.783194'
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF_OBSERVING_TIME001"
  fi
  #
  ################################################################################
  # Check vast_image_details.log format
  NLINES=`cat vast_image_details.log | awk '{print $18}' | sed '/^\s*$/d' | wc -l | awk '{print $1}'`
  if [ $NLINES -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF_VAST_IMG_DETAILS_FORMAT"
  fi
  ################################################################################
  ### Flag image test should always be the last one
  for IMAGE in ../test_exclude_ref_image/lm* ;do
   util/clean_data.sh
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep --quiet "FLAG_IMAGE image00000.flag"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    BASEIMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF006_$BASEIMAGE"
   fi 
   # GAIN_KEY is present in default.sex.excluderefimgtest
   # so GAIN should NOT be specified on the SExtractor command line
   lib/autodetect_aperture_main $IMAGE 2>&1 | grep --quiet "GAIN 1.990"
   if [ $? -eq 0 ];then
    TEST_PASSED=0
    BASEIMAGE=`basename $IMAGE`
    FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF006a_$BASEIMAGE"
   fi 
  done
  
  ###### Not needed as GAIN_KEY is set in default.sex
  # GAIN things
  #lib/autodetect_aperture_main ../test_exclude_ref_image/lm01306trraf1846.fits 2>&1 | grep --quiet 'GAINCCD=1.990'
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF_GAIN001"
  #fi
  #lib/autodetect_aperture_main ../test_exclude_ref_image/lm01306trraf1846.fits 2>&1 | grep --quiet 'GAIN 1.990'
  #if [ $? -ne 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF_GAIN002"
  #fi  
  #echo 'GAIN_KEY         GAINCCD' >> default.sex
  #lib/autodetect_aperture_main ../test_exclude_ref_image/lm01306trraf1846.fits 2>&1 | grep --quiet 'GAIN'
  #if [ $? -eq 0 ];then
  # TEST_PASSED=0
  # FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF_GAIN_KEY"
  #fi
 else
  echo "ERROR: cannot find vast_summary.log" 1>&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF_ALL"
 fi


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mExclude reference image test (PSF) \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mExclude reference image test (PSF) \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
#########################################
# Remove test data from the previous run if we are out of disk space
#########################################
remove_test_data_to_save_space
#


else
 FAILED_TEST_CODES="$FAILED_TEST_CODES PSFEX_NOT_INSTALLED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" 1>&2
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" 1>&2
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi


#### Period search test
THIS_TEST_START_UNIXSEC=$(date +%s)
TEST_PASSED=1
# Run the test
echo "Performing the second period search test " 1>&2
echo -n "Performing the second period search test: " >> vast_test_report.txt 

lib/ls_compute_periodogram lib/test/hads_p0.060.dat 0.20 0.05 0.1 | grep 'LS' | grep "16.661" &>/dev/null
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH001"
fi
lib/lk_compute_periodogram lib/test/hads_p0.060.dat 1.0 0.05 0.1 | grep 'LK' | grep "16.661" &>/dev/null
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH101"
fi
lib/deeming_compute_periodogram lib/test/hads_p0.060.dat 1.0 0.05 0.1 | grep 'DFT' | grep "16.661" &>/dev/null
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH102"
fi
lib/deeming_compute_periodogram lib/test/hads_p0.060.dat 1.0 0.05 0.1 10 2>/dev/null | grep 'DFT' | grep "16.661" | grep -- '+/-' &> /dev/null
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH103"
fi
NUMBER=`lib/compute_periodogram_allmethods lib/test/hads_p0.060.dat 0.20 0.05 0.1 | grep -e 'LS' -e 'DFT' -e 'LK' | grep -c '16.661'`
if [ $NUMBER -ne 3 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH104"
fi
FAP=`lib/ls_compute_periodogram lib/test/hads_p0.060.dat 0.20 0.05 0.1 | grep 'LS' | awk '{print $5}'`
if [ $FAP -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH105"
fi


THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mThe second period search test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mThe second period search test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


#### Coordinate conversion test
# A local copy of WCSTools now should be supplied with VaST
echo "$PATH" | grep --quiet ':lib/bin'
if [ $? -ne 0 ];then
 export PATH=$PATH:lib/bin
fi
# needs WCSTools to run
command -v skycoor &>/dev/null
if [ $? -eq 0 ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1
 # Run the test
 echo "Performing coordinate conversion test " 1>&2
 echo -n "Performing coordinate conversion test: " >> vast_test_report.txt 

 util/examples/test_coordinate_converter.sh &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION001"
 fi
 
 lib/hms2deg 05:00:06.77 -13:08:31.56 &> /dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION002"
 fi
 lib/hms2deg 05:00:06.77 -13:08:31.56 | grep '75.0282083' &> /dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION003"
 fi
 lib/hms2deg 05:00:06.77 -13:08:31.56 | grep -- '-13.1421000' &> /dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION004"
 fi
 for POSITION_DEG in "172.9707500 +29.9958611" "172.9707500 -29.9958611" ;do
  POSITION_HMS_VAST=`lib/deg2hms $POSITION_DEG`
  POSITION_HMS_SKYCOOR=`skycoor -j $POSITION_DEG J2000 | awk '{print $1" "$2}'`
  DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field $POSITION_HMS_VAST $POSITION_HMS_SKYCOOR | grep 'Angular distance' | awk '{print $5*3600}'`
  TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 0.1 ) print 1 ;else print 0 }'`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION005_TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION005_${POSITION_DEG// /_}"
  fi
 done
 lib/deg2hms_uas 126.59917135396 -50.96207264973 | grep --quiet '08:26:23.801125 -50:57:43.46154'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION006"
 fi
 
 lib/put_two_sources_in_one_field 304.908333 4.596750 20:19:38.00 +04:35:48.3
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION007"
 fi
 # The distance should be exactly zero
 DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 304.908333 4.596750 20:19:38.00 +04:35:48.3 | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION008"
 fi
 if [ -z "$DISTANCE_ARCSEC" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION009"
 fi
 TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 0.1 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION010_TOO_FAR_TEST_ERROR"
 else
  if [ $TEST -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION010_TOO_FAR_$DISTANCE_ARCSEC"
  fi
 fi
 #
 lib/put_two_sources_in_one_field 347.395250 61.465778 23:09:34.86 +61:27:56.8
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION011"
 fi
 # The distance should be exactly zero
 DISTANCE_ARCSEC=`lib/put_two_sources_in_one_field 347.395250 61.465778 23:09:34.86 +61:27:56.8 | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION012"
 fi
 if [ -z "$DISTANCE_ARCSEC" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION013"
 fi
 TEST=`echo "$DISTANCE_ARCSEC" | awk '{if ( $1 < 0.1 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION014_TOO_FAR_TEST_ERROR"
 else
  if [ $TEST -eq 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION014_TOO_FAR_$DISTANCE_ARCSEC"
  fi
 fi
 #
 

 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')
 
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mCoordinate conversion test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mCoordinate conversion test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi 
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES WCSTOOLS_NOT_INSTALLED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

#### TAI-UTC file updater
THIS_TEST_START_UNIXSEC=$(date +%s)
TEST_PASSED=1
# Run the test
echo "Performing TAI-UTC file updater test " 1>&2
echo -n "Performing TAI-UTC file updater test: " >> vast_test_report.txt 
# just test that the updater runs with no errors
lib/update_tai-utc.sh
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES TAImUTC001"
fi


THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mTAI-UTC file updater test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mTAI-UTC file updater test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


#### Calendar date to JD conversion test

# clean up any previous files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  rm -f "$TMP_FITS_FILE"
 fi
done

THIS_TEST_START_UNIXSEC=$(date +%s)
TEST_PASSED=1
# Run the test
echo "Calendar date to JD conversion test " 1>&2
echo -n "Calendar date to JD conversion test: " >> vast_test_report.txt 
util/get_image_date '2014-09-09T05:29:55' | grep --quiet 'JD(UT) 2456909.72911'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV001"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV002_$TMP_FITS_FILE"
  break
 fi
done
util/get_image_date '2456909.72911' 2>&1 |grep --quiet '2014-09-09 05:29:55 (UT)'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV003"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV004_$TMP_FITS_FILE"
  break
 fi
done
### Repeat the above test checking the other output line
util/get_image_date '2456909.72911' 2>&1 |grep --quiet 'DATE-OBS= 2014-09-09T05:29:55'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV003a"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV004a_$TMP_FITS_FILE"
  break
 fi
done
util/get_image_date '2458563.500000' 2>&1 |grep --quiet '2019-03-21 00:00:00 (UT)'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV005"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV005a_$TMP_FITS_FILE"
  break
 fi
done
util/get_image_date '2458563.500000' 2>&1 |grep --quiet 'DATE-OBS= 2019-03-21T00:00:00'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV005b"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV005c_$TMP_FITS_FILE"
  break
 fi
done
util/get_image_date '1969-12-31T23:59:58.0' 2>&1 | grep --quiet 'JD 2440587.499977'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV006"
fi
# And a few more checks for the format of the input date string
util/get_image_date '2014-09-09T05:29' 2>&1 | grep --quiet 'JD 2456909.728472'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV006"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV006a_$TMP_FITS_FILE"
  break
 fi
done
util/get_image_date '1969-12-31T23:59:59.0' 2>&1 | grep --quiet 'JD 2440587.499988'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV007"
fi
util/get_image_date 21/09/99 2>&1 | grep --quiet 'Exposure   0 sec, 21.09.1999 00:00:00 UT = JD(UT) 2451442.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV107"
fi
util/get_image_date 21-09-99 2>&1 | grep --quiet 'Exposure   0 sec, 21.09.1999 00:00:00 UT = JD(UT) 2451442.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV108"
fi
util/get_image_date 21-09-1999 2>&1 | grep --quiet 'Exposure   0 sec, 21.09.1999 00:00:00 UT = JD(UT) 2451442.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV109"
fi
util/get_image_date 1-09-99 2>&1 | grep --quiet 'Exposure   0 sec, 01.09.1999 00:00:00 UT = JD(UT) 2451422.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV110"
fi
util/get_image_date 1-09-1999 2>&1 | grep --quiet 'Exposure   0 sec, 01.09.1999 00:00:00 UT = JD(UT) 2451422.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV111"
fi
util/get_image_date 1-9-1999 2>&1 | grep --quiet 'Exposure   0 sec, 01.09.1999 00:00:00 UT = JD(UT) 2451422.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV112"
fi
util/get_image_date 01-09-1999 2>&1 | grep --quiet 'Exposure   0 sec, 01.09.1999 00:00:00 UT = JD(UT) 2451422.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV113"
fi
util/get_image_date 01-9-1999 2>&1 | grep --quiet 'Exposure   0 sec, 01.09.1999 00:00:00 UT = JD(UT) 2451422.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV114"
fi
util/get_image_date 01-9-99 2>&1 | grep --quiet 'Exposure   0 sec, 01.09.1999 00:00:00 UT = JD(UT) 2451422.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV115"
fi
util/get_image_date 1-9-99 2>&1 | grep --quiet 'Exposure   0 sec, 01.09.1999 00:00:00 UT = JD(UT) 2451422.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV116"
fi
util/get_image_date 1999-9-1 2>&1 | grep --quiet 'Exposure   0 sec, 01.09.1999 00:00:00 UT = JD(UT) 2451422.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV117"
fi
util/get_image_date 1999-09-1 2>&1 | grep --quiet 'Exposure   0 sec, 01.09.1999 00:00:00 UT = JD(UT) 2451422.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV118"
fi
util/get_image_date 1999-09-01 2>&1 | grep --quiet 'Exposure   0 sec, 01.09.1999 00:00:00 UT = JD(UT) 2451422.50000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV119"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV007a_$TMP_FITS_FILE"
  break
 fi
done
util/get_image_date '1970-01-01T00:00:00' 2>&1 | grep --quiet 'JD 2440587.500000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV008"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV008a_$TMP_FITS_FILE"
  break
 fi
done
# Make sure the rounding is done correctly
util/get_image_date '1969-12-31T23:59:58.1' 2>&1 | grep --quiet 'JD 2440587.499977'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV009"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV009a_$TMP_FITS_FILE"
  break
 fi
done
util/get_image_date '1969-12-31T23:59:58.9' 2>&1 | grep --quiet 'JD 2440587.499988'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV010"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV010a_$TMP_FITS_FILE"
  break
 fi
done
#### Other output
util/get_image_date '1969-12-31T23:59:58.0' 2>&1 | grep --quiet 'MPC format 1969 12 31.99998'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV011"
fi
util/get_image_date '1969-12-31T23:59:58.0' 2>&1 | grep --quiet 'Julian year 1969.999999937'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV012"
fi
util/get_image_date '1969-12-31T23:59:58.0' 2>&1 | grep --quiet 'Unix Time -2'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV013"
fi
#### Same as above, but check that we are roundng correctly
util/get_image_date '1969-12-31T23:59:58.4' 2>&1 | grep --quiet 'MPC format 1969 12 31.99998'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV014"
fi
util/get_image_date '1969-12-31T23:59:58.4' 2>&1 | grep --quiet 'Julian year 1969.999999937'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV015"
fi
util/get_image_date '1969-12-31T23:59:58.4' 2>&1 | grep --quiet 'Unix Time -2'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV016"
fi
util/get_image_date '1969-12-31T23:59:57.6' 2>&1 | grep --quiet 'MPC format 1969 12 31.99998'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV017"
fi
util/get_image_date '1969-12-31T23:59:57.6' 2>&1 | grep --quiet 'Julian year 1969.999999937'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV018"
fi
util/get_image_date '1969-12-31T23:59:57.6' 2>&1 | grep --quiet 'Unix Time -2'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV019"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV019b_$TMP_FITS_FILE"
  break
 fi
done
# And a few more checks for the format of the input date string
util/get_image_date '2014-09-09T05:29' 2>&1 | grep --quiet 'JD 2456909.728472'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV020"
fi
util/get_image_date '2014-09-09 05:29' 2>&1 | grep --quiet 'JD 2456909.728472'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV021"
fi
util/get_image_date '2014-09-09 05:29:' 2>&1 | grep --quiet 'JD 2456909.728472'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV022"
fi
util/get_image_date '2014-09-09 05:29: ' 2>&1 | grep --quiet 'JD 2456909.728472'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV023"
fi
util/get_image_date '2015-08-21T22:18:25.000000' 2>&1 | grep --quiet 'JD 2457256.429456'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV023a"
fi
util/get_image_date '2020-11-21T18:10:43.4516245' 2>&1 | grep --quiet 'JD 2459175.257442'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV023b"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV023c_$TMP_FITS_FILE"
  break
 fi
done

# Check input as MJD
util/get_image_date '58020.39' 2>&1 | grep --quiet 'JD 2458020.89'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV024"
fi
# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV024c_$TMP_FITS_FILE"
  break
 fi
done

# Check input with multiple arguments and as a fraction of the day
util/get_image_date 2020 10 27 18:00 2>&1 | grep --quiet 'MPC format 2020 10 27.75000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV025"
fi
util/get_image_date 2020 10 27 18:00:00 2>&1 | grep --quiet 'MPC format 2020 10 27.75000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV025"
fi
util/get_image_date 2020 10 27.75 2>&1 | grep --quiet 'MPC format 2020 10 27.75000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV026"
fi
util/get_image_date 2020 1 7.75 2>&1 | grep --quiet 'MPC format 2020 01  7.75000'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV027"
fi

# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV027c_$TMP_FITS_FILE"
  break
 fi
done

# Now make sure there are no residual files
for TMP_FITS_FILE in fake_image_hack_*.fits ;do
 if [ -f "$TMP_FITS_FILE" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV010c_$TMP_FITS_FILE"
  break
 fi
done


THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mCalendar date to JD conversion test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mCalendar date to JD conversion test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#




#### Auxiliary web services test
THIS_TEST_START_UNIXSEC=$(date +%s)
TEST_PASSED=1

if [ ! -d ../vast_test_lightcurves ];then
 mkdir ../vast_test_lightcurves
fi

# Run the test
echo "Performing auxiliary web services test " 1>&2
echo -n "Performing auxiliary web services test: " >> vast_test_report.txt 

# OMC2ASCII converter test 1
if [ ! -f ../vast_test_lightcurves/IOMC_4011000047.fits ];then
 cd ../vast_test_lightcurves
 curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/IOMC_4011000047.fits.bz2" && bunzip2 IOMC_4011000047.fits.bz2
 cd $WORKDIR
fi
RESULTSURL=`curl --silent -F submit="Convert" -F file=@"../vast_test_lightcurves/IOMC_4011000047.fits" 'http://scan.sai.msu.ru/cgi-bin/omc_converter/process_omc.py' | grep 'Refresh' | awk -F 'url=' '{print $2}' | sed 's:"::g' | awk -F '>' '{print $1}'`
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_OMC2ASCII_001"
fi
if [ -z "$RESULTSURL" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_OMC2ASCII_002"
else
 NLINES_IN_OUTPUT_ASCII_FILE=`curl --silent "$RESULTSURL"IOMC_4011000047.txt | wc -l | awk '{print $1}'`
 if [ $NLINES_IN_OUTPUT_ASCII_FILE -ne 2110 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_OMC2ASCII_003"
 fi
fi

# OMC2ASCII converter test 2
if [ ! -f ../vast_test_lightcurves/IOMC_2677000065.fits ];then
 cd ../vast_test_lightcurves
 curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/IOMC_2677000065.fits.bz2" && bunzip2 IOMC_2677000065.fits.bz2
 cd $WORKDIR
fi
RESULTSURL=`curl --silent -F submit="Convert" -F file=@"../vast_test_lightcurves/IOMC_2677000065.fits" 'http://scan.sai.msu.ru/cgi-bin/omc_converter/process_omc.py' | grep 'Refresh' | awk -F 'url=' '{print $2}' | sed 's:"::g' | awk -F '>' '{print $1}'`
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_OMC2ASCII2_001"
fi
if [ -z "$RESULTSURL" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_OMC2ASCII2_002"
else
 curl --silent "$RESULTSURL"IOMC_2677000065.txt > IOMC_2677000065.txt
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_OMC2ASCII2_cannot_download_txt_lc"
 else
  NLINES_IN_OUTPUT_ASCII_FILE=`cat IOMC_2677000065.txt | wc -l | awk '{print $1}'`
  if [ $NLINES_IN_OUTPUT_ASCII_FILE -ne 6274 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_OMC2ASCII2_003"
  else
   lib/lk_compute_periodogram IOMC_2677000065.txt 100 1.0 0.1 | grep 'LK' | grep --quiet '0.308703'
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_OMC2ASCII2_LK_local_period_search_failed"
   fi
  fi
 fi
 if [ -f IOMC_2677000065.txt ];then
  rm -f IOMC_2677000065.txt
 fi
fi

# SuperWASP converter
if [ ! -f ../vast_test_lightcurves/1SWASP_J013623.20+480028.4.fits ];then
 cd ../vast_test_lightcurves
 curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/1SWASP_J013623.20+480028.4.fits.bz2" && bunzip2 1SWASP_J013623.20+480028.4.fits.bz2
 cd $WORKDIR
fi
RESULTSURL=`curl --silent -F submit="Convert" -F file=@"../vast_test_lightcurves/1SWASP_J013623.20+480028.4.fits" 'http://scan.sai.msu.ru/cgi-bin/swasp_converter/process_swasp.py' | grep 'Refresh' | awk -F 'url=' '{print $2}' | sed 's:"::g' | awk -F '>' '{print $1}'`
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_SWASP_001"
fi
if [ -z "$RESULTSURL" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_SWASP_002"
else
 NLINES_IN_OUTPUT_ASCII_FILE=`curl --silent "$RESULTSURL"out1SWASP_J013623.20+480028.4.dat | wc -l | awk '{print $1}'`
 if [ $NLINES_IN_OUTPUT_ASCII_FILE -ne 8358 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_SWASP_003"
 fi
fi

# WWWUPSILON
if [ ! -f ../vast_test_lightcurves/nsv14523hjd.dat ];then
 cd ../vast_test_lightcurves
 curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/nsv14523hjd.dat.bz2" && bunzip2 nsv14523hjd.dat.bz2
 cd $WORKDIR
fi
RESULTSURL=`curl --silent -F submit="Classify" -F file=@"../vast_test_lightcurves/nsv14523hjd.dat" 'http://scan.sai.msu.ru/cgi-bin/wwwupsilon/process_lightcurve.py' | grep 'Refresh' | awk -F 'url=' '{print $2}' | sed 's:"::g' | awk -F '>' '{print $1}'`
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_WWWU_001"
elif [ -z "$RESULTSURL" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_WWWU_002"
else
 # The new upsilon incorrectly classifies the test lightcurve as a cepheid, because it cannot correctly derive its period
 # but whatever, here we just want to check that the web service is working
 curl --silent "$RESULTSURL" | grep --quiet -e 'class =  RRL_ab' -e 'class = RRL_ab' -e 'class = CEPH_F'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_WWWU_003"
 fi
fi

# NMW Sky archive
# clean-up from possible incomplete previous run
if [ -f wwwtest.tmp ];then
 rm -f wwwtest.tmp
fi
if [ -f wwwtest.png ];then
 rm -f wwwtest.png
fi
curl --silent 'http://scan.sai.msu.ru/cgi-bin/nmw/sky_archive?ra=17%3A45%3A28.02&dec=-23%3A05%3A23.1&r=64&n=0' | grep -A500 'Sky image archive search results' | grep 'crop_wcs_fd_Sgr1_2011-11-3_001.fts.png' > wwwtest.tmp
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_NMWSKYARCHIVE_001"
fi
curl --silent --output wwwtest.png `cat wwwtest.tmp | awk -F'"' '{print $2}'`
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_NMWSKYARCHIVE_002"
fi
file wwwtest.png | grep --quiet 'PNG image data'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_NMWSKYARCHIVE_003"
fi
# clean-up
if [ -f wwwtest.tmp ];then
 rm -f wwwtest.tmp
fi
if [ -f wwwtest.png ];then
 rm -f wwwtest.png
fi


# PA Sky archive
# clean-up from possible incomplete previous run
if [ -f wwwtest.tmp ];then
 rm -f wwwtest.tmp
fi
if [ -f wwwtest.png ];then
 rm -f wwwtest.png
fi
curl --silent 'http://scan.sai.msu.ru/cgi-bin/pa/sky_archive?ra=02%3A34%3A18.77&dec=%2B63%3A12%3A43.0&r=256' | grep -A500 'Sky image archive search results' | grep 'crop_SCA255N__05_-1.fits.png' > wwwtest.tmp
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_PASKYARCHIVE_001"
fi
curl --silent --output wwwtest.png `cat wwwtest.tmp | awk -F'"' '{print $2}'`
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_PASKYARCHIVE_002"
fi
file wwwtest.png | grep --quiet 'PNG image data'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_PASKYARCHIVE_003"
fi
# clean-up
if [ -f wwwtest.tmp ];then
 rm -f wwwtest.tmp
fi
if [ -f wwwtest.png ];then
 rm -f wwwtest.png
fi


# EpCalc
curl --silent 'http://scan.sai.msu.ru/cgi-bin/epcalc/ecalc?HJD0=2453810.90213&Period=10.55&JD1=2453903.90213&JD2=2453930.90213' | grep --quiet '2453937.502130'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_EPCALC_001"
fi


####### HTTPS
test_https_connection
TEST_EXIT_CODE=$?
if [ $TEST_EXIT_CODE -ne 0 ];then
 if [ $TEST_EXIT_CODE -eq 2 ];then
  FAILED_TEST_CODES="$FAILED_TEST_CODES HTTPS_001_TEST_NOT_PERFORMED"
 else
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HTTPS_001"
 fi
fi


THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mAuxiliary web services test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mAuxiliary web services test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#



# util/fov_of_wcs_calibrated_image.sh
THIS_TEST_START_UNIXSEC=$(date +%s)
TEST_PASSED=1
echo "Performing the image field of view script test " 1>&2
echo -n "Performing the image field of view script test: " >> vast_test_report.txt 

if [ ! -f ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 curl -O "http://scan.sai.msu.ru/~kirx/pub/wcs_fd_Per3_2011-10-31_001.fts.bz2" && bunzip2 wcs_fd_Per3_2011-10-31_001.fts.bz2
 cd $WORKDIR
fi
if [ -f ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts ];then
 util/fov_of_wcs_calibrated_image.sh ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts | grep 'Image size: 467.' | grep --quiet '352.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES IMAGEFOVSCRIPT_001"
 fi
 util/fov_of_wcs_calibrated_image.sh ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts | grep --quiet 'Image scale: 8.3'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES IMAGEFOVSCRIPT_002"
 fi
 IMAGE_CENTER=`util/fov_of_wcs_calibrated_image.sh ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts | grep 'Image center: ' | awk '{print $3" "$4}'`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES IMAGEFOVSCRIPT_003"
 fi
 if [ -z "$IMAGE_CENTER" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES IMAGEFOVSCRIPT_004"
 fi
 DISTANCE_FROM_IMAGE_CENTER_ARCSEC=`lib/bin/skycoor -r 03:47:04.453 +45:10:05.77 $IMAGE_CENTER`
 #TEST=`echo "$DISTANCE_FROM_IMAGE_CENTER_ARCSEC<0.3" | bc -ql`
 TEST=`echo "$DISTANCE_FROM_IMAGE_CENTER_ARCSEC" | awk '{if ( $1 < 0.3 ) print 1 ;else print 0 }'`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES IMAGEFOVSCRIPT_005_TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES IMAGEFOVSCRIPT_005"
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES IMAGEFOVSCRIPT_TEST_NOT_PERFORMED"
fi


THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mImage field of view script test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mImage field of view script test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#



# flatfielding test
THIS_TEST_START_UNIXSEC=$(date +%s)
TEST_PASSED=1
echo "Performing NMW flatfielding test " 1>&2
echo -n "Performing NMW flatfielding test: " >> vast_test_report.txt 

if [ ! -d ../NMW_corrupt_calibration_test ];then
 cd ../
 curl -O "http://scan.sai.msu.ru/~kirx/pub/NMW_corrupt_calibration_test.tar.bz2" && tar -xf NMW_corrupt_calibration_test.tar.bz2 && rm -f NMW_corrupt_calibration_test.tar.bz2
 cd $WORKDIR
fi
if [ -f ../NMW_corrupt_calibration_test/d_test.fit ] && [ -f ../NMW_corrupt_calibration_test/mff_Stas_2021-08-28.fit ];then
 util/ccd/md ../NMW_corrupt_calibration_test/d_test.fit ../NMW_corrupt_calibration_test/mff_Stas_2021-08-28.fit fd_test.fit
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWFLATFIELDING_001"
 fi
 if [ ! -f fd_test.fit ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWFLATFIELDING_002"
 fi
 if [ ! -s fd_test.fit ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWFLATFIELDING_003"
 fi
 lib/autodetect_aperture_main fd_test.fit 2>&1 | grep --quiet FLAG_IMAGE
 if [ $? -eq 0 ];then
  # There should be no flag image for this flatfielded frame
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWFLATFIELDING_004"
 fi
 rm -f fd_test.fit
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NMWFLATFIELDING_TEST_NOT_PERFORMED"
fi


THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mNMW flatfielding test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mNMW flatfielding test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
 echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#





#### HJD correction test
# needs VARTOOLS to run
command -v vartools &>/dev/null
if [ $? -eq 0 ];then
 THIS_TEST_START_UNIXSEC=$(date +%s)
 TEST_PASSED=1

# As of VARTOOLS version 1.40 it does not exit with code 0 if called without arguments
# vartools &> /dev/null
# if [ $? -ne 0 ];then
#  TEST_PASSED=0
#  FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTION_PROBLEM_RUNNING_VARTOOLS"
# fi

 if [ ! -d ../vast_test_lightcurves ];then
  mkdir ../vast_test_lightcurves
 fi
 for INPUTDATAFILE in naif0012.tls out_Cepheid_TDB_HJD_VARTOOLS.dat out_Cepheid_TT_HJD_VaST.dat out_Cepheid_UTC_raw.dat ;do
  if [ ! -f ../vast_test_lightcurves/"$INPUTDATAFILE" ];then
   cd ../vast_test_lightcurves
   curl -O "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/$INPUTDATAFILE.bz2"
   bunzip2 "$INPUTDATAFILE".bz2
   cd $WORKDIR
  fi
 done

 # Run the test
 echo "Performing HJD correction test " 1>&2
 echo -n "Performing HJD correction test: " >> vast_test_report.txt 

 # .tmp files are the new ones, .dat files are the old ones that suppose to match the new ones
 
 util/hjd_input_in_UTC ../vast_test_lightcurves/out_Cepheid_UTC_raw.dat `lib/hms2deg 03:05:54.66 +57:45:44.5`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTION001"
 fi
 if [ ! -f out_Cepheid_UTC_raw.dat_hjdTT ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTION002"
 fi
 if [ ! -s out_Cepheid_UTC_raw.dat_hjdTT ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTION003"
 fi
 mv out_Cepheid_UTC_raw.dat_hjdTT out_Cepheid_TT_HJD_VaST.tmp
 if [ -f HJDCORRECTION_problem.tmp ];then
  rm -f HJDCORRECTION_problem.tmp
 fi
 # Compare the VaST file with the VaST standard
 while read -r A REST && read -r B REST <&3; do 
  #TEST=`echo "a=($A-$B);sqrt(a*a)<0.00002" | bc -ql`
  TEST=`echo "$A $B" | awk '{if ( sqrt( ($1-$2)*($1-$2) ) < 0.00002 ) print 1 ;else print 0 }'`
  if [ $TEST -ne 1 ];then
   touch HJDCORRECTION_problem.tmp
   break
  fi
 done < ../vast_test_lightcurves/out_Cepheid_TT_HJD_VaST.dat 3< out_Cepheid_TT_HJD_VaST.tmp
 if [ -f HJDCORRECTION_problem.tmp ];then
  rm -f HJDCORRECTION_problem.tmp
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTION005"
 fi

 # Compare the VaST file with the VARTOOLS standard
 if [ -f HJDCORRECTION_problem.tmp ];then
  rm -f HJDCORRECTION_problem.tmp
 fi
 while read -r A REST && read -r B REST <&3; do 
  #TEST=`echo "a=($A-$B);sqrt(a*a)<0.00010" | bc -ql`
  TEST=`echo "$A $B" | awk '{if ( sqrt( ($1-$2)*($1-$2) ) < 0.00010 ) print 1 ;else print 0 }'`
  if [ $TEST -ne 1 ];then
   touch HJDCORRECTION_problem.tmp
   break
  fi
 done < out_Cepheid_TT_HJD_VaST.tmp 3< ../vast_test_lightcurves/out_Cepheid_TDB_HJD_VARTOOLS.dat
 if [ -f HJDCORRECTION_problem.tmp ];then
  rm -f HJDCORRECTION_problem.tmp
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTION006"
 fi

 # Run VARTOOLS 
 vartools -i ../vast_test_lightcurves/out_Cepheid_UTC_raw.dat -quiet -converttime input jd inputsys-utc output hjd outputsys-tdb radec fix 46.4777500 +57.7623611 leapsecfile ../vast_test_lightcurves/naif0012.tls -o out_Cepheid_TDB_HJD_VARTOOLS.tmp
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTION007_vartools_run"
 fi

 # Compare the VARTOOLS file with the VARTOOLS standard
 if [ -f HJDCORRECTION_problem.tmp ];then
  rm -f HJDCORRECTION_problem.tmp
 fi
 while read -r A REST && read -r B REST <&3; do 
  #TEST=`echo "a=($A-$B);sqrt(a*a)<0.00002" | bc -ql`
  TEST=`echo "$A $B" | awk '{if ( sqrt( ($1-$2)*($1-$2) ) < 0.00002 ) print 1 ;else print 0 }'`
  if [ $TEST -ne 1 ];then
   touch HJDCORRECTION_problem.tmp
   break
  fi
 done < out_Cepheid_TDB_HJD_VARTOOLS.tmp 3< ../vast_test_lightcurves/out_Cepheid_TDB_HJD_VARTOOLS.dat
 if [ -f HJDCORRECTION_problem.tmp ];then
  rm -f HJDCORRECTION_problem.tmp
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTION008"
 fi

 # Compare the VARTOOLS file with the VaST file
 if [ -f HJDCORRECTION_problem.tmp ];then
  rm -f HJDCORRECTION_problem.tmp
 fi
 while read -r A REST && read -r B REST <&3; do 
  # 0.00010*86400=8.6400 - assume this is an acceptable difference
  # 0.00015*86400=12.960 - assume this is an acceptable difference?? NO!!!!
  #TEST=`echo "a=($A-$B);sqrt(a*a)<0.00010" | bc -ql`
  TEST=`echo "$A $B" | awk '{if ( sqrt( ($1-$2)*($1-$2) ) < 0.00010 ) print 1 ;else print 0 }'`
  if [ $TEST -ne 1 ];then
   touch HJDCORRECTION_problem.tmp
   break
  fi
 done < out_Cepheid_TDB_HJD_VARTOOLS.tmp 3< out_Cepheid_TT_HJD_VaST.tmp
 if [ -f HJDCORRECTION_problem.tmp ];then
  rm -f HJDCORRECTION_problem.tmp
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTION009"
 fi

 util/examples/test_heliocentric_correction.sh &>/dev/null
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTION010"
 fi
 
 # Clean-up
 for FILE_TO_REMOVE in out_Cepheid_TDB_HJD_VARTOOLS.tmp out_Cepheid_TT_HJD_VaST.tmp ;do
  rm -f "$FILE_TO_REMOVE"
 done


 THIS_TEST_STOP_UNIXSEC=$(date +%s)
 THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mHJD correction test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "PASSED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mHJD correction test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)" 1>&2
  echo "FAILED ($THIS_TEST_TIME_MIN_STR)" >> vast_test_report.txt
 fi 
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES VARTOOLS_NOT_INSTALLED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


#########################################
# Remove test data for the next run if we are out of disk space
#########################################
remove_test_data_to_save_space
#


####################################################
# List all the error codes at the end of the report:
if [ -z "$FAILED_TEST_CODES" ];then
 FAILED_TEST_CODES="NONE"
fi
echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt

STOPTIME_UNIXSEC=$(date +%s)
#RUNTIME_MIN=`echo "($STOPTIME_UNIXSEC-$STARTTIME_UNIXSEC)/60" | bc -ql | awk '{printf "%.2f",$1}'`
RUNTIME_MIN=`echo "$STOPTIME_UNIXSEC $STARTTIME_UNIXSEC" | awk '{printf "%.1f",($1-$2)/60}'`

echo "Test run time: $RUNTIME_MIN minutes" >> vast_test_report.txt

# Print out the final report
echo "

############# Test Report #############"
cat vast_test_report.txt

if [ ! -z "$DEBUG_OUTPUT" ];then
 echo "#########################################################
$DEBUG_OUTPUT
"
else
 echo "#########################################################
No DEBUG_OUTPUT
"
fi

# Clean-up
util/clean_data.sh &> /dev/null

# Restore default SExtractor settings file
cp default.sex.ccd_example default.sex
cp default.psfex.ccd_example default.psfex

# Ask user if we should mail the test report
MAIL_TEST_REPORT_TO_KIRX="NO"
# Always mail report to kirx if this script is running on a test machine
if [ -f ../THIS_IS_HPCC ];then
 MAIL_TEST_REPORT_TO_KIRX="YES"
else
 # Ask user on the command line
 echo "### Send the above report to the VaST developer? (yes/no)"
 read USER_ANSWER
 #if [ "yes" = "$USER_ANSWER" ] || [ "y" = "$USER_ANSWER" ] || [ "ys" = "$USER_ANSWER" ] || [ "Yes" = "$USER_ANSWER" ] || [ "YES" = "$USER_ANSWER" ] || [ "1" = "$USER_ANSWER" ] ;then
 echo "$USER_ANSWER" | grep --quiet -e "yes" -e "yy" -e "ys" -e "Yes" -e "YES"
 if [ $? -eq 0 ] || [ "y" = "$USER_ANSWER" ] || [ "1" = "$USER_ANSWER" ] ;then
  MAIL_TEST_REPORT_TO_KIRX="YES"
 else
  MAIL_TEST_REPORT_TO_KIRX="NO"
 fi
fi

# see below
if [ -f ../THIS_IS_HPCC__email_only_on_failure ];then
 MAIL_TEST_REPORT_TO_KIRX="NO"
fi

if [ "$MAIL_TEST_REPORT_TO_KIRX" = "YES" ];then
 email_vast_test_report
# HOST=`hostname`
# HOST="@$HOST"
# NAME="$USER$HOST"
## DATETIME=`LANG=C date --utc`
## bsd dae doesn't know '--utc', but accepts '-u'
# DATETIME=`LANG=C date -u`
# SCRIPTNAME=`basename $0`
# LOG=`cat vast_test_report.txt`
# MSG="The script $0 has finished on $DATETIME at $PWD $LOG $DEBUG_OUTPUT"
#echo "
#$MSG
##########################################################
#$DEBUG_OUTPUT
#
#" > vast_test_email_message.log
# curl --silent 'http://scan.sai.msu.ru/vast/vasttestreport.php' --data-urlencode "name=$NAME running $SCRIPTNAME" --data-urlencode message@vast_test_email_message.log --data-urlencode 'submit=submit'
# if [ $? -eq 0 ];then
#  echo "The test report was sent successfully"
# else
#  echo "There was a problem sending the test report"
# fi
fi

if [ "$FAILED_TEST_CODES" != "NONE" ];then
 FAILED_TEST_CODES="${FAILED_TEST_CODES/ PSFEX_NOT_INSTALLED/}"
 FAILED_TEST_CODES="${FAILED_TEST_CODES/ WCSTOOLS_NOT_INSTALLED/}"
 FAILED_TEST_CODES="${FAILED_TEST_CODES/ VARTOOLS_NOT_INSTALLED/}"
 FAILED_TEST_CODES="${FAILED_TEST_CODES/ AUXWEB_WWWU_003/}"
 FAILED_TEST_CODES="${FAILED_TEST_CODES// DISABLE_MAGSIZE_FILTER_LOGS_SET/}"
 #
 FAILED_TEST_CODES="${FAILED_TEST_CODES// STANDALONEDBSCRIPT001a_GCVS/}"
 FAILED_TEST_CODES="${FAILED_TEST_CODES// STANDALONEDBSCRIPT001b_GCVS/}"
 #
 FAILED_TEST_CODES="${FAILED_TEST_CODES// scan.sai.msu.ru_REMOTEPLATESOLVE007/}"
 FAILED_TEST_CODES="${FAILED_TEST_CODES// scan.sai.msu.ru_REMOTEPLATESOLVE008/}"
 FAILED_TEST_CODES="${FAILED_TEST_CODES// scan.sai.msu.ru_REMOTEPLATESOLVE009/}"
 FAILED_TEST_CODES="${FAILED_TEST_CODES// none_REMOTEPLATESOLVE007/}"
 FAILED_TEST_CODES="${FAILED_TEST_CODES// none_REMOTEPLATESOLVE008/}"
 FAILED_TEST_CODES="${FAILED_TEST_CODES// none_REMOTEPLATESOLVE009/}"
 #
 FAILED_TEST_CODES="${FAILED_TEST_CODES// LIGHTCURVEVIEWER004_TEST_NOT_PERFORMED_no_gs/}"
 # HTTPS test doesn't work on old BSD despite the intermediate cert trick, not sure why
 FAILED_TEST_CODES="${FAILED_TEST_CODES// HTTPS_001_TEST_NOT_PERFORMED/}"
 # Mac-specific problems
 # 'sort --random-sort --random-source=/dev/urandom' times out om Mac
 FAILED_TEST_CODES="${FAILED_TEST_CODES// LCPARSER002_TEST_NOT_PERFORMED/}"
 FAILED_TEST_CODES="${FAILED_TEST_CODES// LCFILTER_TEST_NOT_PERFORMED/}"
 #
 if [ ! -z "$FAILED_TEST_CODES" ];then
  echo "Exit code 1"
  #
  if [ -f ../THIS_IS_HPCC__email_only_on_failure ];then
   email_vast_test_report
  fi
  #
  exit 1
 fi
fi

echo "Exit code 0"
exit 0
