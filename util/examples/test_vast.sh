#!/usr/bin/env bash

# for test runs with AddressSanitizer 
export ASAN_OPTIONS=strict_string_checks=1:detect_stack_use_after_return=1:check_initialization_order=1:strict_init_order=1

##### auxiliary functions #####
function find_source_by_X_Y_in_vast_lightcurve_statistics_log {
 if [ ! -s vast_lightcurve_statistics.log ];then
  echo "ERROR: no vast_lightcurve_statistics.log" >> /dev/stderr
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

function test_internet_connection {
 curl --max-time 10 --silent http://scan.sai.msu.ru/astrometry_engine/files/ | grep --quiet 'Parent Directory'
 if [ $? -ne 0 ];then
  echo "ERROR in test_internet_connection(): cannot connect to scan.sai.msu.ru" >> /dev/stderr
  return 1
 fi
 curl --max-time 10 --silent http://vast.sai.msu.ru/astrometry_engine/files/ | grep --quiet 'Parent Directory'
 if [ $? -ne 0 ];then
  echo "ERROR in test_internet_connection(): cannot connect to vast.sai.msu.ru" >> /dev/stderr
  return 1
 fi
 
 lib/choose_vizier_mirror.sh 2>&1 | grep --quiet 'ERROR'
 if [ $? -eq 0 ];then
  echo "ERROR in test_internet_connection(): cannot connect to VizieR" >> /dev/stderr
  return 1
 fi

 return 0
}

# Test the connection right away
test_internet_connection
if [ $? -ne 0 ];then
 exit 1
fi

#########################################
# Remove test data from the previous run if we are out of disk space
#########################################
# Skip free disk space check on some pre-defined machines
# hope this check should work even if there is no 'hostname' command
hostname | grep --quiet eridan 
if [ $? -ne 0 ];then 
 # Free-up disk space if we run out of it
 #FREE_DISK_SPACE_MB=`df -l -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 # If we managed to get the disk space info
 if [ $? -eq 0 ];then
  TEST=`echo "($FREE_DISK_SPACE_MB)<4096" | bc -q`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DISKSPACE_TEST_ERROR"
  fi
  if [ $TEST -eq 1 ];then
   echo "WARNING: we are almost out of disk space, only $FREE_DISK_SPACE_MB MB remaining." >> /dev/stderr
   for TEST_DATASET in ../Gaia16aye_SN ../individual_images_test ../KZ_Her_DSLR_transient_search_test ../M31_ISON_test ../M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails ../MASTER_test ../only_few_stars ../test_data_photo ../test_exclude_ref_image ../transient_detection_test_Ceres ../tycho2 ../vast_test_lightcurves ../vast_test__dark_flat_flag ;do
    # Simple safety thing
    TEST=`echo "$TEST_DATASET" | grep -c '\.\.'`
    if [ $TEST -ne 1 ];then
     continue
    fi
    #
    if [ -d "$TEST_DATASET" ];then
     rm -rf "$TEST_DATASET"
     #FREE_DISK_SPACE_MB=`df -l -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
     FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
     TEST=`echo "($FREE_DISK_SPACE_MB)<4096" | bc -q`
     if [ $TEST -eq 0 ];then
      break
     fi
    fi
   done
  fi # if [ $FREE_DISK_SPACE_MB -lt 1024 ];then
 fi # if [ $? -eq 0 ];then
fi # if [ $? -ne ];then # hostname check
#########################################



##### Report that we are starting the work #####
echo "---------- Starting $0 ----------" >> /dev/stderr
echo "---------- $0 ----------" > vast_test_report.txt

##### Set initial values for the variables #####
FAILED_TEST_CODES=""
WORKDIR="$PWD"
VAST_VERSION_STRING=`./vast --version`
STARTTIME_UNIXSEC=`date +%s`
# BSD date will not understand `date -d @$STARTTIME_UNIXSEC`
#STARTTIME_HUMAN_RADABLE=`date -d @$STARTTIME_UNIXSEC`
STARTTIME_HUMAN_RADABLE=`date`
echo "Started on $STARTTIME_HUMAN_RADABLE" >> /dev/stderr
echo "Started on $STARTTIME_HUMAN_RADABLE" >> vast_test_report.txt

##### Gather system information #####
echo "Gathering basic system information for summary report" >> /dev/stderr
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
export PATH="$PATH:lib/bin"
sex -v >> vast_test_report.txt

command -v psfex &> /dev/null
if [ $? -eq 0 ];then
 psfex -v >> vast_test_report.txt
else
 echo "PSFEx is not installed" >> vast_test_report.txt
fi

cat vast_test_report.txt >> /dev/stderr
echo "---------- $VAST_VERSION_STRING test results ----------" >> vast_test_report.txt

# Reset the increpmental list of failed test codes
# (this list is useful if you cancel the test before it completes)
cat vast_test_report.txt > vast_test_incremental_list_of_failed_test_codes.txt

##### Photographic plate test #####
### Check the consistency of the dest data if its already there
if [ -d ../test_data_photo ];then
 NUMBER_OF_IMAGES_IN_TEST_FOLDER=`ls -1 ../test_data_photo | wc -l | awk '{print $1}'`
 if [ $NUMBER_OF_IMAGES_IN_TEST_FOLDER -lt 150 ];then
  # If the number of files is smaller than it should be 
  # - just remove the directory, the following lines will download the data again.
  echo "WARNING: corrupted test data found in ../test_data_photo" >> /dev/stderr
  rm -rf ../test_data_photo
 fi
fi
# Download the test dataset if needed
if [ ! -d ../test_data_photo ];then
 cd ..
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/test_data_photo.tar.bz2"
 if [ $? -ne 0 ];then
  echo "ERROR downloading test data!" >> /dev/stderr
  exit 1
 fi
 tar -xvjf test_data_photo.tar.bz2
 if [ $? -ne 0 ];then
  echo "ERROR unpacking test data! Are we out of disk space?" >> /dev/stderr
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
  TEST_PASSED=1
  ##
  util/clean_data.sh
  # Run the test
  echo "Photographic plates test " >> /dev/stderr
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
   util/wcs_image_calibration.sh ../test_data_photo/SCA1017S_17061_09773__00_00.fit
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE004"
   fi
   if [ ! -f wcs_SCA1017S_17061_09773__00_00.fit ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE005"
   fi
   lib/bin/xy2sky wcs_SCA1017S_17061_09773__00_00.fit 200 200 &>/dev/null
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE005a"
   fi
   util/solve_plate_with_UCAC5 ../test_data_photo/SCA1017S_17061_09773__00_00.fit
   if [ ! -f wcs_SCA1017S_17061_09773__00_00.fit.cat.ucac5 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE006"
   else
    TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_SCA1017S_17061_09773__00_00.fit.cat.ucac5 | wc -l | awk '{print $1}'`
    if [ $TEST -lt 420 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE006a_$TEST"
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
     TEST=`echo "$MEAN_ASTROMETRIC_OFFSET<1.0" | bc -ql`
     if [ $TEST -ne 1 ];then
      TEST_PASSED=0
      FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE006d"
     fi
    fi
   fi 
   util/solve_plate_with_UCAC5 ../test_data_photo/SCA10670S_13788_08321__00_00.fit
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE007"
   fi
   if [ ! -s wcs_SCA10670S_13788_08321__00_00.fit ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE008"
   fi 
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
    if [ $TEST -lt 550 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE010a_$TEST"
    fi
   fi
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
   util/nopgplot.sh
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
   TEST=`echo "$DISTANCE_ARCSEC<0.3" | bc -ql`
   re='^[0-9]+$'
   if ! [[ $TEST =~ $re ]] ; then
    echo "TEST ERROR"
    TEST_PASSED=0
    TEST=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
   fi
   if [ $TEST -ne 1 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE014_"${CEPHEID_RADEC_STR//" "/"_"}
   fi
   if [ ! -z "$CEPHEID_RADEC_STR" ];then
    # CEPHEID_RADEC_STR="03:05:54.66 +57:45:44.3"
    # presumably that should be out00474.dat
    # Check that it is V834 Cas (it should be)
    util/search_databases_with_curl.sh $CEPHEID_RADEC_STR | grep "V0834 Cas"
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE015"
    fi
    util/search_databases_with_vizquery.sh $CEPHEID_RADEC_STR star 40 | grep "V0834 Cas"
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE016_vizquery"
    fi
    # same thing but different input format
    util/search_databases_with_vizquery.sh $CEPHEID_RADEC_STR | grep "V0834 Cas"
    if [ $? -ne 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE017_vizquery"
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
    FREQ_LK=`lib/lk_compute_periodogram "$CEPHEIDOUTFILE" 100 0.1 0.1 | awk '{print $1}'`
    # sqrt(a*a) is the sily way to get an absolute value of a
    TEST=`echo "a=$FREQ_LK-0.211448;sqrt(a*a)<0.01" | bc -ql`
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
     echo "TEST ERROR"
     TEST_PASSED=0
     TEST=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
    fi
    if [ $TEST -eq 0 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE020"
    fi
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
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE027"
   fi
   "$WORKDIR"/util/search_databases_with_vizquery.sh $CEPHEID_RADEC_STR star 40 | grep "V0834 Cas"
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE028"
   fi
   # Here we expect exactly two distances to be reported 2MASS and USNO-B1.0 match
   # Both should be within 0.8 arcsec from the input coordinates. Let's check this
   #"$WORKDIR"/util/search_databases_with_vizquery.sh $CEPHEID_RADEC_STR star 40 | grep 'r=' | grep -v 'var=' | awk '{print $1}' FS='"' | awk '{print $2}' FS='r=' | while read R_DISTANCE_TO_MATCH ;do
   "$WORKDIR"/util/search_databases_with_vizquery.sh $CEPHEID_RADEC_STR star 40 | grep 'r=' | grep -v 'var=' | awk -F '"' '{print $1}' | awk -F 'r=' '{print $2}' | while read R_DISTANCE_TO_MATCH ;do
    TEST=`echo "$R_DISTANCE_TO_MATCH<0.8" | bc -ql`
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
   ## Check if we get the same results with mag-size filtering
   util/clean_data.sh
   # Run the test
   #echo "Photographic plates test " >> /dev/stderr
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
   FREQ_LK=`lib/lk_compute_periodogram $TMPSTR 100 0.1 0.1 | awk '{print $1}'`
   # sqrt(a*a) is the sily way to get an absolute value of a
   TEST=`echo "a=$FREQ_LK-0.211448;sqrt(a*a)<0.01" | bc -ql`
   re='^[0-9]+$'
   if ! [[ $TEST =~ $re ]] ; then
    echo "TEST ERROR"
    TEST_PASSED=0
    TEST=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
   fi
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE111"
   fi
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
   #####################
   #####################
   ## Check if we get the same results with automated reference image selection
   util/clean_data.sh
   # Run the test
   #echo "Photographic plates test " >> /dev/stderr
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
   FREQ_LK=`lib/lk_compute_periodogram $TMPSTR 100 0.1 0.1 | awk '{print $1}'`
   # sqrt(a*a) is the sily way to get an absolute value of a
   TEST=`echo "a=$FREQ_LK-0.211448;sqrt(a*a)<0.01" | bc -ql`
   re='^[0-9]+$'
   if ! [[ $TEST =~ $re ]] ; then
    echo "TEST ERROR"
    TEST_PASSED=0
    TEST=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
   fi
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE211"
   fi
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
   echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PHOTOPLATE_ALL"
  fi
  # Make an overall conclusion for this test
  if [ $TEST_PASSED -eq 1 ];then
   echo -e "\n\033[01;34mPhotographic plates test \033[01;32mPASSED\033[00m" >> /dev/stderr
   echo "PASSED" >> vast_test_report.txt
  else
   echo -e "\n\033[01;34mPhotographic plates test \033[01;31mFAILED\033[00m" >> /dev/stderr
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
#########################################
# Skip free disk space check on some pre-defined machines
# hope this check should work even if there is no 'hostname' command
hostname | grep --quiet eridan 
if [ $? -ne 0 ];then 
 # Free-up disk space if we run out of it
 #FREE_DISK_SPACE_MB=`df -l -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 # If we managed to get the disk space info
 if [ $? -eq 0 ];then
  TEST=`echo "($FREE_DISK_SPACE_MB)<4096" | bc -q`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DISKSPACE_TEST_ERROR"
  fi
  if [ $TEST -eq 1 ];then
   echo "WARNING: we are almost out of disk space, only $FREE_DISK_SPACE_MB MB remaining." >> /dev/stderr
   if [ $TEST_PASSED -eq 1 ];then
    if [ -d ../test_data_photo ];then
     echo "Deleting test data!" >> /dev/stderr
     rm -rf ../test_data_photo
    else
     echo "What was it? o_O" >> /dev/stderr
    fi
   else
    echo "The previous test did not pass - stopping here!
   
Failed test codes: $FAILED_TEST_CODES
" >> /dev/stderr
    exit 1
   fi # if [ $TEST_PASSED -eq 1 ];then
  fi # if [ $FREE_DISK_SPACE_MB -lt 1024 ];then
 fi # if [ $? -eq 0 ];then
fi # if [ $? -ne ];then # hostname check
#########################################

##### Small CCD images test #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images test " >> /dev/stderr
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
  grep --quiet "Magnitude-Size filter: Disabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD005"
  fi
  grep --quiet "Photometric errors rescaling: YES" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD006"
  fi
#  SYSTEMATIC_NOISE_LEVEL=`util/estimate_systematic_noise_level 2> /dev/null`
#  if [ $? -ne 0 ];then
#   TEST_PASSED=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_SYSNOISE01"
#  fi
#  TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0042);sqrt(a*a)<0.005" | bc -ql`
#  re='^[0-9]+$'
#  if ! [[ $TEST =~ $re ]] ; then
#   echo "TEST ERROR"
#   TEST_PASSED=0
#   TEST=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
#  fi
#  if [ $TEST -ne 1 ];then
#   TEST_PASSED=0
#   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_SYSNOISE02"
#  fi
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
  TEST=`echo "a=($STATMAG)-(-11.761200);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD015a"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  TEST=`echo "a=($STATX)-(218.9535100);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD016"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  TEST=`echo "a=($STATY)-(247.8363000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  TEST=`echo "a=($STATIDX)-(0.372294);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD018"
  fi
  # idx09_MAD
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  TEST=`echo "a=($STATIDX)-(0.018977);sqrt(a*a)<0.005" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD019"
  fi
  # idx25_IQR
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  TEST=`echo "a=($STATIDX)-(0.025686);sqrt(a*a)<0.001" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  TEST=`echo "a=($STATMAG)-(-11.220400);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD026a"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  TEST=`echo "a=($STATX)-(87.2039000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD027"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  TEST=`echo "a=($STATY)-(164.4241000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD028"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  TEST=`echo "a=($STATIDX)-(0.037195);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD029"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  TEST=`echo "a=($STATIDX)-(0.044775);sqrt(a*a)<0.002" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD030"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  # Yeah, I have no idea why this difference is so large between machines
  # The difference is in the original lightcurve...
  TEST=`echo "a=($STATIDX)-(0.050557);sqrt(a*a)<0.003" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### Few small CCD images test #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Few small CCD images test " >> /dev/stderr
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FEWSMALLCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mFew small CCD images test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mFew small CCD images test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images test with no errors rescaling " >> /dev/stderr
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
  TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0130);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  TEST=`echo "a=($STATMAG)-(-11.761200);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE015"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  TEST=`echo "a=($STATX)-(218.9535100);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE016"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  TEST=`echo "a=($STATY)-(247.8363000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE017"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  TEST=`echo "a=($STATIDX)-(0.241686);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE018"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  TEST=`echo "a=($STATIDX)-(0.018977);sqrt(a*a)<0.005" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE019"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  TEST=`echo "a=($STATIDX)-(0.025686);sqrt(a*a)<0.001" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  TEST=`echo "a=($STATMAG)-(-11.220400);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE026"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  TEST=`echo "a=($STATX)-(87.2039000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE027"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  TEST=`echo "a=($STATY)-(164.4241000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE028"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  TEST=`echo "a=($STATIDX)-(0.037195);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE029"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.044775);sqrt(a*a)<0.001" | bc -ql`
  TEST=`echo "a=($STATIDX)-(0.044775);sqrt(a*a)<0.002" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE030"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  # Yeah, I have no idea why this difference is so large between machines
  # The difference is in the original lightcurve...
  TEST=`echo "a=($STATIDX)-(0.050557);sqrt(a*a)<0.003" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDNOERRORSRESCALE_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images test with no errors rescaling \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images test with no errors rescaling \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with non-zero MAG_ZEROPOINT test " >> /dev/stderr
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES MAGZEROPOINTSMALLCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with non-zero MAG_ZEROPOINT test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with non-zero MAG_ZEROPOINT test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with OMP_NUM_THREADS=2 test " >> /dev/stderr
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES OMP_NUM_THREADS_SMALLCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with OMP_NUM_THREADS=2 test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with OMP_NUM_THREADS=2 test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with directory name instead of file list test " >> /dev/stderr
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME_SMALLCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with directory name instead of file list test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with directory name instead of file list test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with directory name instead of file list test " >> /dev/stderr
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DIRNAME2_SMALLCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with directory name instead of file list test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with directory name instead of file list test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
if [ ! -d '../sample space' ];then
 cp -r '../sample_data' '../sample space'
fi

# If the test data are found
if [ -d '../sample space' ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "White space name test " >> /dev/stderr
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mWhite space name test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mWhite space name test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES WHITE_SPACE_NAME_SMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### Small CCD images test with automated reference image selection #####
# Download the test dataset if needed
if [ ! -d ../sample_data ];then
 cd ..
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with automated reference image selection test " >> /dev/stderr
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES AUTOSELECT_REF_IMG_SMALLCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with automated reference image selection test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with automated reference image selection test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with FITS keyword recording test " >> /dev/stderr
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES WITH_KEYWORD_RECORDING_SMALLCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with FITS keyword recording test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with FITS keyword recording test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with NO FITS keyword recording test " >> /dev/stderr
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NO_KEYWORD_RECORDING_SMALLCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with NO FITS keyword recording test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with NO FITS keyword recording test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../sample_data ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD images with mag-size filter test " >> /dev/stderr
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
  grep --quiet "Magnitude-Size filter: Enabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD005"
  fi
  grep --quiet 'Photometric errors rescaling: YES' vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_ERRORRESCALINGLOGREC"
  fi
  SYSTEMATIC_NOISE_LEVEL=`util/estimate_systematic_noise_level 2> /dev/null`
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_SYSNOISE01"
  fi
  TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0043);sqrt(a*a)<0.005" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  TEST=`echo "a=($STATMAG)-(-11.761200);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD014"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  TEST=`echo "a=($STATX)-(218.9535100);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD015_$STATX"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  TEST=`echo "a=($STATY)-(247.8363000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  TEST=`echo "a=($STATIDX)-(0.362346);sqrt(a*a)<0.05" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD017_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  TEST=`echo "a=($STATIDX)-(0.018977);sqrt(a*a)<0.005" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD018_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  TEST=`echo "a=($STATIDX)-(0.025686);sqrt(a*a)<0.002" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  TEST=`echo "a=($STATMAG)-(-11.220400);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD024"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  TEST=`echo "a=($STATX)-(87.2039000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD025_$STATX"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  TEST=`echo "a=($STATY)-(164.4241000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD026_$STATY"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  TEST=`echo "a=($STATIDX)-(0.037195);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD027_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  TEST=`echo "a=($STATIDX)-(0.043737);sqrt(a*a)<0.002" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD028_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  # 91 points
  #TEST=`echo "a=($STATIDX)-(0.050557);sqrt(a*a)<0.001" | bc -ql`
  # 90 points, weight image
  TEST=`echo "a=($STATIDX)-(0.052707);sqrt(a*a)<0.005" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  ###############################################

 else
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES MAGSIZEFILTERSMALLCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD images with mag-size filter test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD images with mag-size filter test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/sample_data.tar.bz2" && tar -xvjf sample_data.tar.bz2 && rm -f sample_data.tar.bz2
 cd $WORKDIR
fi
if [ ! -d '../sample space' ];then
 cp -r '../sample_data' '../sample space'
fi

# If the test data are found
if [ -d '../sample space' ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Space mall CCD images with mag-size filter test " >> /dev/stderr
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
  grep --quiet "Magnitude-Size filter: Enabled" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD005"
  fi
  grep --quiet 'Photometric errors rescaling: YES' vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_ERRORRESCALINGLOGREC"
  fi
  SYSTEMATIC_NOISE_LEVEL=`util/estimate_systematic_noise_level 2> /dev/null`
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_SYSNOISE01"
  fi
  TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0043);sqrt(a*a)<0.005" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  TEST=`echo "a=($STATMAG)-(-11.761200);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD014"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  TEST=`echo "a=($STATX)-(218.9535100);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD015_$STATX"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  TEST=`echo "a=($STATY)-(247.8363000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD016_$STATY"
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
  TEST=`echo "a=($STATIDX)-(0.362346);sqrt(a*a)<0.05" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD017_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  TEST=`echo "a=($STATIDX)-(0.018977);sqrt(a*a)<0.005" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD018_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  TEST=`echo "a=($STATIDX)-(0.025686);sqrt(a*a)<0.002" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  TEST=`echo "a=($STATMAG)-(-11.220400);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD024"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  TEST=`echo "a=($STATX)-(87.2039000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD025_$STATX"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  TEST=`echo "a=($STATY)-(164.4241000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD026_$STATY"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  TEST=`echo "a=($STATIDX)-(0.037195);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD027_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  TEST=`echo "a=($STATIDX)-(0.043737);sqrt(a*a)<0.002" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD028_$STATIDX"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  # 91 points
  #TEST=`echo "a=($STATIDX)-(0.050557);sqrt(a*a)<0.001" | bc -ql`
  # 90 points, weight image
  TEST=`echo "a=($STATIDX)-(0.052707);sqrt(a*a)<0.005" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  ###############################################

 else
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSpace small CCD images with mag-size filter test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSpace small CCD images with mag-size filter test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SPACEMAGSIZEFILTERSMALLCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


### !!!!!!!!!!!!!
#echo $FAILED_TEST_CODES
#exit 1


##### Very few stars on the reference frame #####
# Download the test dataset if needed
if [ ! -d ../vast_test_bright_stars_failed_match ];then
 cd ..
 wget -c "http://scan.sai.msu.ru/~kirx/pub/vast_test_bright_stars_failed_match.tar.bz2" && tar -xvjf vast_test_bright_stars_failed_match.tar.bz2 && rm -f vast_test_bright_stars_failed_match.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../vast_test_bright_stars_failed_match ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Reference image with very few stars test " >> /dev/stderr
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
  grep --quiet "Ref.  image: 2458689.62122 25.07.2019 02:54:30" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS003a"
  fi
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mReference image with very few stars test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mReference image with very few stars test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES REFIMAGE_WITH_VERY_FEW_STARS_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

##### Test the two levels of directory recursion #####
# Download the test dataset if needed
if [ ! -d ../vast_test_ASASSN-19cq ];then
 cd ..
 wget -c "http://scan.sai.msu.ru/~kirx/pub/vast_test_ASASSN-19cq.tar.bz2" && tar -xvjf vast_test_ASASSN-19cq.tar.bz2 && rm -f vast_test_ASASSN-19cq.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../vast_test_ASASSN-19cq ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Two-level directory recursion test " >> /dev/stderr
 echo -n "Two-level directory recursion test: " >> vast_test_report.txt
 # Here is the main feature of this test: we limit the number of processin threads to only 2
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
  grep --quiet "Images used for photometry 11" vast_summary.log
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mTwo-level directory recursion test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mTwo-level directory recursion test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES TWOLEVELDIRREC_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#



##### MASTER images test #####
# Download the test dataset if needed
if [ ! -d ../MASTER_test ];then
 cd ..
 wget -c "http://scan.sai.msu.ru/~kirx/pub/MASTER_test.tar.bz2" && tar -xvjf MASTER_test.tar.bz2 && rm -f MASTER_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../MASTER_test ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "MASTER CCD images test " >> /dev/stderr
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
   if [ $TEST -lt 800 ];then
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mMASTER CCD images test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mMASTER CCD images test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
#########################################
# Skip free disk space check on some pre-defined machines
# hope this check should work even if there is no 'hostname' command
hostname | grep --quiet eridan 
if [ $? -ne 0 ];then 
 # Free-up disk space if we run out of it
 #FREE_DISK_SPACE_MB=`df -l -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 # If we managed to get the disk space info
 if [ $? -eq 0 ];then
  TEST=`echo "($FREE_DISK_SPACE_MB)<2048" | bc -q`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DISKSPACE_TEST_ERROR"
  fi

  if [ $TEST -eq 1 ];then
   echo "WARNING: we are almost out of disk space, only $FREE_DISK_SPACE_MB MB remaining." >> /dev/stderr
   if [ $TEST_PASSED -eq 1 ];then
    if [ -d ../MASTER_test ];then
     echo "Deleting test data!" >> /dev/stderr
     rm -rf ../MASTER_test
    else
     echo "What was it? o_O" >> /dev/stderr
    fi
   else
    echo "The previous test did not pass - stopping here!
   
Failed test codes: $FAILED_TEST_CODES
" >> /dev/stderr
    exit 1
   fi # if [ $TEST_PASSED -eq 1 ];then
  fi # if [ $FREE_DISK_SPACE_MB -lt 1024 ];then
 fi # if [ $? -eq 0 ];then
fi # if [ $? -ne ];then # hostname check
#########################################


##### M31 ISON images test #####
# Download the test dataset if needed
if [ ! -d ../M31_ISON_test ];then
 cd ..
 wget -c "http://scan.sai.msu.ru/~kirx/pub/M31_ISON_test.tar.bz2" && tar -xvjf M31_ISON_test.tar.bz2 && rm -f M31_ISON_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../M31_ISON_test ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "ISON M31 CCD images test " >> /dev/stderr
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
  util/solve_plate_with_UCAC5 ../M31_ISON_test/M31-1-001-001_dupe-1.fts
  if [ ! -f wcs_M31-1-001-001_dupe-1.fts.cat.ucac5 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD005"
  else
   lib/bin/xy2sky wcs_M31-1-001-001_dupe-1.fts 200 200 &>/dev/null
   if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD005a"
   fi
   TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_M31-1-001-001_dupe-1.fts.cat.ucac5 | wc -l | awk '{print $1}'`
   if [ $TEST -lt 1500 ];then
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mISON M31 CCD images test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mISON M31 CCD images test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31CCD_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

##### Gaia16aye images by S. Nazarov test #####
# Download the test dataset if needed
if [ ! -d ../Gaia16aye_SN ];then
 cd ..
 wget -c "http://scan.sai.msu.ru/~kirx/pub/Gaia16aye_SN.tar.bz2" && tar -xvjf Gaia16aye_SN.tar.bz2 && rm -f Gaia16aye_SN.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../Gaia16aye_SN ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Gaia16aye_SN CCD images test " >> /dev/stderr
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mGaia16aye_SN CCD images test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mGaia16aye_SN CCD images test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES GAIA16AYESN_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### Images with only few stars by S. Nazarov test #####
# Download the test dataset if needed
if [ ! -d ../only_few_stars ];then
 cd ..
 wget -c "http://scan.sai.msu.ru/~kirx/pub/only_few_stars.tar.bz2" && tar -xvjf only_few_stars.tar.bz2 && rm -f only_few_stars.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../only_few_stars ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "CCD images with few stars test " >> /dev/stderr
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARS_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mCCD images with few stars test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mCCD images with few stars test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "http://scan.sai.msu.ru/~kirx/pub/only_few_stars.tar.bz2" && tar -xvjf only_few_stars.tar.bz2 && rm -f only_few_stars.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../only_few_stars ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "CCD images with few stars and brigh galaxy magsizefilter test " >> /dev/stderr
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mCCD images with few stars and brigh galaxy magsizefilter test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mCCD images with few stars and brigh galaxy magsizefilter test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES CCDIMGFEWSTARSBRIGHTGALMAGSIZE_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### test images by JB #####
# Download the test dataset if needed
if [ ! -d ../test_exclude_ref_image ];then
 cd ..
 wget -c "http://scan.sai.msu.ru/~kirx/data/vast_tests/test_exclude_ref_image.tar.bz2" && tar -xvjf test_exclude_ref_image.tar.bz2 && rm -f test_exclude_ref_image.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../test_exclude_ref_image ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Exclude reference image test " >> /dev/stderr
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
  for XY in "770.0858800 207.0210000" "341.8960900 704.7567700" "563.2354700 939.6331800" "764.0470000 678.5069000" "560.6923800 625.8682900" "791.9907200 911.4987800"  "64.6611000 551.0836800" ;do
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mExclude reference image test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mExclude reference image test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGE_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
#########################################
# Skip free disk space check on some pre-defined machines
# hope this check should work even if there is no 'hostname' command
hostname | grep --quiet eridan 
if [ $? -ne 0 ];then 
 # Free-up disk space if we run out of it
 #FREE_DISK_SPACE_MB=`df -l -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 # If we managed to get the disk space info
 if [ $? -eq 0 ];then
  TEST=`echo "($FREE_DISK_SPACE_MB)<4096" | bc -q`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DISKSPACE_TEST_ERROR"
  fi
  if [ $TEST -eq 1 ];then
   echo "WARNING: we are almost out of disk space, only $FREE_DISK_SPACE_MB MB remaining." >> /dev/stderr
   if [ $TEST_PASSED -eq 1 ];then
    if [ -d ../test_exclude_ref_image ];then
     echo "Deleting test data!" >> /dev/stderr
     rm -rf ../test_exclude_ref_image
    else
     echo "What was it? o_O" >> /dev/stderr
    fi
   else
    echo "The previous test did not pass - stopping here!
   
Failed test codes: $FAILED_TEST_CODES
" >> /dev/stderr
    exit 1
   fi # if [ $TEST_PASSED -eq 1 ];then
  fi # if [ $FREE_DISK_SPACE_MB -lt 1024 ];then
 fi # if [ $? -eq 0 ];then
fi # if [ $? -ne ];then # hostname check
#########################################


# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" >> /dev/stderr
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" >> /dev/stderr
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi

##### Ceres test #####
# Download the test dataset if needed
if [ ! -d ../transient_detection_test_Ceres ];then
 cd ..
 wget -c "ftp://scan.sai.msu.ru/pub/software/vast/transient_detection_test_Ceres.tar.bz2" && tar -xvjf transient_detection_test_Ceres.tar.bz2 && rm -f transient_detection_test_Ceres.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../transient_detection_test_Ceres ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Find Ceres test " >> /dev/stderr
 echo -n "Find Ceres test: " >> vast_test_report.txt 
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
  
  # Download a copy of Tycho-2 catalog for magnitude calibration of wide-field transient search data
  VASTDIR=$PWD
  TYCHO_PATH=lib/catalogs/tycho2
  # Check if we have a locakal copy...
  if [ ! -f "$TYCHO_PATH"/tyc2.dat.00 ];then
   # Download the Tycho-2 catalog from our own server
   if [ ! -d ../tycho2 ];then
    cd `dirname $VASTDIR`
    wget -c "http://scan.sai.msu.ru/~kirx/pub/tycho2.tar.bz2" && tar -xvjf tycho2.tar.bz2 && rm -f tycho2.tar.bz2
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
  echo "y" | util/transients/search_for_transients_single_field.sh
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
  DISTANCE_DEGREES=`lib/put_two_sources_in_one_field 06:01:27.29 +23:51:10.7 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_DEGREES<8.4" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES010a_TOO_FAR_$DISTANCE_DEGREES"
   fi
  fi
  #
  grep --quiet "HK Aur" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES011"
  fi
  #grep --quiet "2013 03 22.3148  2456191.3148  11.75  05:48:54.08 +28:51:09.7" transient_report/index.html
  grep --quiet "2013 03 22.3148  2456191.3148  11.75" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES011a"
  fi
  RADECPOSITION_TO_TEST=`grep "2013 03 22.3148  2456191.3148  11.75" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_DEGREES=`lib/put_two_sources_in_one_field 05:48:54.08 +28:51:09.7 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_DEGREES<8.4" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES011a_TOO_FAR_$DISTANCE_DEGREES"
   fi
  fi
  #
  grep --quiet "AW Tau" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES0110"
  fi
  #grep --quiet "2013 03 22.3148  2456191.3148  13.38  05:47:30.53 +27:08:16.8" transient_report/index.html
  grep --quiet "2013 03 22.3148  2456191.3148  13.38" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES0110a"
  fi
  RADECPOSITION_TO_TEST=`grep "2013 03 22.3148  2456191.3148  13.38" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_DEGREES=`lib/put_two_sources_in_one_field 05:47:30.53 +27:08:16.8 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_DEGREES<8.4" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES0110a_TOO_FAR_$DISTANCE_DEGREES"
   fi
  fi
  #
  grep --quiet "LP Gem" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES012"
  fi
  #grep --quiet "2013 03 22.3148  2456191.3148  13.10  06:05:05.47 +26:40:53.2" transient_report/index.html
  grep --quiet "2013 03 22.3148  2456191.3148  13.10" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES012a"
  fi
  RADECPOSITION_TO_TEST=`grep "2013 03 22.3148  2456191.3148  13.10" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_DEGREES=`lib/put_two_sources_in_one_field 06:05:05.47 +26:40:53.2 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_DEGREES<8.4" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES012a_TOO_FAR_$DISTANCE_DEGREES"
   fi
  fi
  #
  grep --quiet "AU Tau" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES013"
  fi
  #grep --quiet "2013 03 22.3148  2456191.3148  12.79  05:43:31.42 +28:07:41.4" transient_report/index.html
  grep --quiet -e "2013 03 22.3148  2456191.3148  12.79" -e "2013 03 22.3148  2456191.3148  12.80" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES013a"
  fi
  RADECPOSITION_TO_TEST=`grep -e "2013 03 22.3148  2456191.3148  12.79" -e "2013 03 22.3148  2456191.3148  12.80" transient_report/index.html | head -n1 | awk '{print $6" "$7}'`
  DISTANCE_DEGREES=`lib/put_two_sources_in_one_field 05:43:31.42 +28:07:41.4 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_DEGREES<8.4" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES013a_TOO_FAR_$DISTANCE_DEGREES"
   fi
  fi
  #
  grep --quiet "RR Tau" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES014"
  fi
  #grep --quiet "2013 03 22.3148  2456191.3148  12.32  05:39:30.69 +26:22:25.7" transient_report/index.html
  grep --quiet "2013 03 22.3148  2456191.3148  12.32" transient_report/index.html
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES CERES014a"
  fi
  RADECPOSITION_TO_TEST=`grep "2013 03 22.3148  2456191.3148  12.32" transient_report/index.html | awk '{print $6" "$7}'`
  DISTANCE_DEGREES=`lib/put_two_sources_in_one_field 05:39:30.69 +26:22:25.7 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}'`
  # NMW scale is 8.4"/pix
  TEST=`echo "$DISTANCE_DEGREES<8.4" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  else
   if [ $TEST -eq 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES CERES014a_TOO_FAR_$DISTANCE_DEGREES"
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES CERES_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mFind Ceres test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mFind Ceres test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES CERES_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" >> /dev/stderr
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" >> /dev/stderr
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi

##### DSLR transient search test #####
# Download the test dataset if needed
if [ ! -d ../KZ_Her_DSLR_transient_search_test ];then
 cd ..
 wget -c "http://scan.sai.msu.ru/~kirx/pub/KZ_Her_DSLR_transient_search_test.tar.bz2" && tar -xvjf KZ_Her_DSLR_transient_search_test.tar.bz2 && rm -f KZ_Her_DSLR_transient_search_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../KZ_Her_DSLR_transient_search_test ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "DSLR transient search test " >> /dev/stderr
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
  echo "y" | util/transients/search_for_transients_single_field.sh
  if [ ! -f transient_report/index.html ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER005"
  fi 
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mDSLR transient search test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mDSLR transient search test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES DSLRKZHER_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" >> /dev/stderr
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" >> /dev/stderr
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi

if [ ! -d ../individual_images_test ];then
 mkdir ../individual_images_test
fi

######### Indivdual images test
if [ ! -f ../individual_images_test/1630+3250.20150511T215921000.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 wget -c "http://scan.sai.msu.ru/~kirx/pub/1630+3250.20150511T215921000.fit.bz2" && bunzip2 1630+3250.20150511T215921000.fit.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/1630+3250.20150511T215921000.fit ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Ultra-wide-field image test " >> /dev/stderr
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
  if [ $TEST -lt 1800 ];then
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
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mUltra-wide-field image test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mUltra-wide-field image test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES ULTRAWIDEFIELD_TEST_NOT_PERFORMED"
fi

######### Many hot pixels image
if [ ! -f ../individual_images_test/c176.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 wget -c "http://scan.sai.msu.ru/~kirx/pub/c176.fits.bz2" && bunzip2 c176.fits.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/c176.fits ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Image with many hot pixels test " >> /dev/stderr
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
  if [ $TEST -lt 180 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES HOTPIXIMAGE002a_$TEST"
  fi
 fi 
 util/get_image_date ../individual_images_test/c176.fits | grep --quiet "Exposure 120 sec, 02.08.2017 20:31:52 UT = JD(UT) 2457968.35616 mid. exp."
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES HOTPIXIMAGE003"
 fi
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mImage with many hot pixels test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mImage with many hot pixels test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "http://scan.sai.msu.ru/~kirx/pub/SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit.bz2" && bunzip2 SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/SS433-1MHz-76mcs-PreampX4-0016Rc-19-06-10.fit ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "SAI RC600 image test " >> /dev/stderr
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
  if [ $TEST -lt 170 ];then
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
 if [ "$FOV" != "23" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600004"
 fi
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSAI RC600 image test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSAI RC600 image test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SAIRC600_TEST_NOT_PERFORMED"
fi


######### NMW archive image
if [ ! -f ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 wget -c "http://scan.sai.msu.ru/~kirx/pub/wcs_fd_Per3_2011-10-31_001.fts.bz2" && bunzip2 wcs_fd_Per3_2011-10-31_001.fts.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "NMW archive image test " >> /dev/stderr
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
  if [ $TEST -lt 1700 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES NMWARCHIVEIMG002a_$TEST"
  fi
 fi 
 util/get_image_date ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts | grep --quiet "Exposure  40 sec, 30.10.2011 23:02:28 UT = JD(UT) 2455865.46028 mid. exp."
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES NMWARCHIVEIMG003"
 fi
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNMW archive image test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNMW archive image test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NMWARCHIVEIMG_TEST_NOT_PERFORMED"
fi


# T30
if [ ! -f ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 wget -c "http://scan.sai.msu.ru/~kirx/pub/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit.bz2" && bunzip2 Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Large image, small skymark test " >> /dev/stderr
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
 #util/get_image_date ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit | grep "Exposure   5 sec, 09.03.2015 13:46:48 UT = JD(UT) 2457091.07419 mid. exp."
 util/get_image_date ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit | grep 'Exposure   5 sec, 09.03.2015 13:46:48 UT = JD(UT) 2457091.07420 mid. exp.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLSKYMARK003"
 fi
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mLarge image, small skymark test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mLarge image, small skymark test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLSKYMARK_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


### Photoplate in the area not covered by APASS
if [ ! -f ../individual_images_test/SCA13320__00_00.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 wget -c "http://scan.sai.msu.ru/~kirx/pub/SCA13320__00_00.fits.bz2" && bunzip2 SCA13320__00_00.fits.bz2
 cd $WORKDIR
fi
if [ -f ../individual_images_test/SCA13320__00_00.fits ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "104 Her test " >> /dev/stderr
 echo -n "104 Her test: " >> vast_test_report.txt 
 cp default.sex.beta_Cas_photoplates default.sex
 util/solve_plate_with_UCAC5 ../individual_images_test/SCA13320__00_00.fits
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES 104HER000"
 fi
 if [ ! -f wcs_SCA13320__00_00.fits ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES 104HER001"
 fi 
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
 fi 
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34m104 Her test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34m104 Her test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES 104HER_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

### date specified with with JDMID keyword
if [ ! -f ../individual_images_test/SCA13320__00_00__date_in_JDMID_keyword.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 wget -c "http://scan.sai.msu.ru/~kirx/pub/SCA13320__00_00__date_in_JDMID_keyword.fits.bz2" && bunzip2 SCA13320__00_00__date_in_JDMID_keyword.fits.bz2
 cd $WORKDIR
fi
if [ -f ../individual_images_test/SCA13320__00_00__date_in_JDMID_keyword.fits ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "JDMID test " >> /dev/stderr
 echo -n "JDMID test: " >> vast_test_report.txt 
 cp default.sex.beta_Cas_photoplates default.sex
 JDMID_KEY_JD=`util/get_image_date ../individual_images_test/SCA13320__00_00__date_in_JDMID_keyword.fits | grep 'JD (mid. exp.)'`
 JD_KEY_JD=`util/get_image_date ../individual_images_test/SCA13320__00_00.fits | grep 'JD (mid. exp.)'`
 if [ "$JDMID_KEY_JD" != "$JD_KEY_JD" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES JDMID001"
 fi 
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mJDMID test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mJDMID test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES JDMID_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

### HST image - check that we are creating a flag image for that one
if [ ! -f ../individual_images_test/hst_12911_01_wfc3_uvis_f775w_01_drz.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 wget -c "http://scan.sai.msu.ru/~kirx/pub/hst_12911_01_wfc3_uvis_f775w_01_drz.fits.bz2" && bunzip2 hst_12911_01_wfc3_uvis_f775w_01_drz.fits.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/hst_12911_01_wfc3_uvis_f775w_01_drz.fits ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Flag image creation for HST test " >> /dev/stderr
 echo -n "Flag image creation for HST test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 lib/autodetect_aperture_main ../individual_images_test/hst_12911_01_wfc3_uvis_f775w_01_drz.fits 2>&1 | grep "FLAG_IMAGE image00000.flag"
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FLAGHST001"
 fi 
 util/get_image_date ../individual_images_test/hst_12911_01_wfc3_uvis_f775w_01_drz.fits | grep "JD (mid. exp.) 2456311.52320"
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FLAGHST002"
 fi 
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mFlag image creation for HST test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mFlag image creation for HST test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES FLAGHST_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


######### ZTF image header test
if [ ! -f ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 wget -c "http://scan.sai.msu.ru/~kirx/pub/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits.bz2" && bunzip2 ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits.bz2
 cd $WORKDIR
fi

if [ -f ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "ZTF image header test " >> /dev/stderr
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
  if [ $TEST -lt 1200 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER002a_$TEST"
  fi
 fi 
 # test that util/solve_plate_with_UCAC5 will not try to recompute the solution if the output catalog is already there
 util/solve_plate_with_UCAC5 ../individual_images_test/ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits 2>&1 | grep --quiet 'The output catalog wcs_ztf_20180327530417_000382_zg_c02_o_q3_sciimg.fits.cat.ucac5 already exist.'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER003"
 fi
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mZTF image header test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mZTF image header test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES ZTFHEADER_TEST_NOT_PERFORMED"
fi


### Test the field-of-view guess code
if [ -d ../individual_images_test ];then
 TEST_PASSED=1
 # Run the test
 echo "Test the field-of-view guess code " >> /dev/stderr
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

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mField-of-view guess code test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mField-of-view guess code test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES GUESSFOV_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

# Test that the Internet conncation has not failed
test_internet_connection
if [ $? -ne 0 ];then
 echo "Internet connection error!" >> /dev/stderr
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" >> /dev/stderr
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi

### Check the external plate solve servers
if [ -d ../individual_images_test ];then
 TEST_PASSED=1
 # Run the test
 echo "Test plate solving with remote servers " >> /dev/stderr
 echo -n "Plate solving with remote servers: " >> vast_test_report.txt 
 #for PLATE_SOLVE_SERVER in none scan.sai.msu.ru vast.sai.msu.ru polaris.kirx.net ;do
 for FORCE_PLATE_SOLVE_SERVER in scan.sai.msu.ru vast.sai.msu.ru polaris.kirx.net none ;do
  export FORCE_PLATE_SOLVE_SERVER
  util/clean_data.sh
  cp default.sex.ccd_example default.sex
  export ASTROMETRYNET_LOCAL_OR_REMOTE="remote" 
  util/wcs_image_calibration.sh ../individual_images_test/1630+3250.20150511T215921000.fit
  export ASTROMETRYNET_LOCAL_OR_REMOTE=""
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE001"
  fi
  if [ ! -f wcs_1630+3250.20150511T215921000.fit ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE002"
  fi
  lib/bin/xy2sky wcs_1630+3250.20150511T215921000.fit 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE002a"
  fi
  cp default.sex.ccd_example default.sex
  ASTROMETRYNET_LOCAL_OR_REMOTE="remote" util/wcs_image_calibration.sh ../individual_images_test/Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE003"
  fi
  if [ ! -f wcs_Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE004"
  fi
  lib/bin/xy2sky wcs_Calibrated-T30-ksokolovsky-ra-20150309-004645-Luminance-BIN1-W-005-001.fit 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE004a"
  fi
  cp default.sex.beta_Cas_photoplates default.sex
  ASTROMETRYNET_LOCAL_OR_REMOTE="remote" util/wcs_image_calibration.sh ../individual_images_test/SCA13320__00_00.fits
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE005"
  fi
  if [ ! -f wcs_SCA13320__00_00.fits ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE006"
  fi
  lib/bin/xy2sky wcs_SCA13320__00_00.fits 200 200 &>/dev/null
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES $FORCE_PLATE_SOLVE_SERVER"_"REMOTEPLATESOLVE006a"
  fi
 done

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mTest for plate solving with remote servers \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mTest for plate solving with remote servers \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi


else
 FAILED_TEST_CODES="$FAILED_TEST_CODES REMOTEPLATESOLVE_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


### check that we are NOT creating a flag image for photoplates
if [ -f ../individual_images_test/SCA13320__00_00.fits ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "No flag images for photoplates 2 test " >> /dev/stderr
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
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mNo flag images for photoplates 2 test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mNo flag images for photoplates 2 test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES NOFLAGSPHOTO2_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
#########################################
# Skip free disk space check on some pre-defined machines
# hope this check should work even if there is no 'hostname' command
hostname | grep --quiet eridan 
if [ $? -ne 0 ];then 
 # Free-up disk space if we run out of it
 #FREE_DISK_SPACE_MB=`df -l -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 # If we managed to get the disk space info
 if [ $? -eq 0 ];then
  TEST=`echo "($FREE_DISK_SPACE_MB)<2048" | bc -q`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DISKSPACE_TEST_ERROR"
  fi
  if [ $TEST -eq 1 ];then
   echo "WARNING: we are almost out of disk space, only $FREE_DISK_SPACE_MB MB remaining." >> /dev/stderr
   if [ $TEST_PASSED -eq 1 ];then
    if [ -d ../individual_images_test ];then
     echo "Deleting test data!" >> /dev/stderr
     rm -rf ../individual_images_test
    else
     echo "What was it? o_O" >> /dev/stderr
    fi
   else
    echo "The previous test did not pass - stopping here!
   
Failed test codes: $FAILED_TEST_CODES
" >> /dev/stderr
    exit 1
   fi # if [ $TEST_PASSED -eq 1 ];then
  fi # if [ $FREE_DISK_SPACE_MB -lt 1024 ];then
 fi # if [ $? -eq 0 ];then
fi # if [ $? -ne ];then # hostname check
#########################################

############# Dark Flat Flag #############
if [ ! -d ../vast_test__dark_flat_flag ];then
 cd ..
 wget -c "http://scan.sai.msu.ru/~kirx/pub/vast_test__dark_flat_flag.tar.bz2" && tar -xvjf vast_test__dark_flat_flag.tar.bz2 && rm -f vast_test__dark_flat_flag.tar.bz2
 cd $WORKDIR
fi
if [ -d ../vast_test__dark_flat_flag ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Special Dark Flat Flag test " >> /dev/stderr
 echo -n "Special Dark Flat Flag test: " >> vast_test_report.txt 
 util/examples/test__dark_flat_flag.sh
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_DARK_FLAT_FLAG_001"
 fi
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSpecial Dark Flat Flag test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSpecial Dark Flat Flag test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
 #
 echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
 df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
 #
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_DARK_FLAT_FLAG_TEST_NOT_PERFORMED" 
fi 


############## Sepcial tests that are performed only on the main developement computer ##############
if [ -d /mnt/usb/M4_F775W_images_Level2_few_links_for_tests ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Special HST M4 test " >> /dev/stderr
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
  grep --quiet "First image: 2456311.38443 18.01.2013 21:13:25" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST003"
  fi
  grep --quiet "Last  image: 2456312.04468 19.01.2013 13:04:10" vast_summary.log
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST004"
  fi
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIALM4HST_ALL"
 fi
 
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSpecial HST M4 test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSpecial HST M4 test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
 #
 echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
 df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
 # 
fi

if [ "$HOSTNAME" = "eridan" ] ;then
 ############# VB #############
 if [ -d /mnt/usb/VaST_test_VladimirB/GoodFrames/vast_test_VB ];then
  TEST_PASSED=1
  util/clean_data.sh
  # Run the test
  echo "Special VB test " >> /dev/stderr
  echo -n "Special VB test: " >> vast_test_report.txt 
  util/examples/test__VB.sh
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VB_001"
  fi
  if [ $TEST_PASSED -eq 1 ];then
   echo -e "\n\033[01;34mSpecial VB test \033[01;32mPASSED\033[00m" >> /dev/stderr
   echo "PASSED" >> vast_test_report.txt
  else
   echo -e "\n\033[01;34mSpecial VB test \033[01;31mFAILED\033[00m" >> /dev/stderr
   echo "FAILED" >> vast_test_report.txt
  fi
  #
  echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
  df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
  # 
 fi
 ############# VB2 #############
 if [ -d /mnt/usb/VaST_test_VladimirB_2/GoodFrames/vast_test_VB ];then
  TEST_PASSED=1
  util/clean_data.sh
  # Run the test
  echo "Special VB2 test " >> /dev/stderr
  echo -n "Special VB2 test: " >> vast_test_report.txt 
  util/examples/test__VB_2.sh
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VB_001"
  fi
  if [ $TEST_PASSED -eq 1 ];then
   echo -e "\n\033[01;34mSpecial VB test \033[01;32mPASSED\033[00m" >> /dev/stderr
   echo "PASSED" >> vast_test_report.txt
  else
   echo -e "\n\033[01;34mSpecial VB test \033[01;31mFAILED\033[00m" >> /dev/stderr
   echo "FAILED" >> vast_test_report.txt
  fi
  #
  echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
  df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
  # 
 fi
 ############# 61 Cyg #############
 if [ -d /mnt/usb/61Cyg_photoplates_test ];then
  TEST_PASSED=1
  util/clean_data.sh
  # Run the test
  echo "Special 61 Cyg test " >> /dev/stderr
  echo -n "Special 61 Cyg test: " >> vast_test_report.txt 
  util/examples/test_61Cyg.sh
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_61CYG_001"
  fi
  if [ $TEST_PASSED -eq 1 ];then
   echo -e "\n\033[01;34mSpecial 61 Cyg test \033[01;32mPASSED\033[00m" >> /dev/stderr
   echo "PASSED" >> vast_test_report.txt
  else
   echo -e "\n\033[01;34mSpecial 61 Cyg test \033[01;31mFAILED\033[00m" >> /dev/stderr
   echo "FAILED" >> vast_test_report.txt
  fi
  #
  echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
  df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
  # 
 fi
 ############# NMW #############
 if [ -d /mnt/usb/NMW_NG_transient_detection_test ];then
  TEST_PASSED=1
  util/clean_data.sh
  # Run the test
  echo "Special NMW test " >> /dev/stderr
  echo -n "Special NMW test: " >> vast_test_report.txt 
  util/examples/test_NMW.sh
  if [ $? -ne 0 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_NMW_001"
  fi
  if [ $TEST_PASSED -eq 1 ];then
   echo -e "\n\033[01;34mSpecial NMW test \033[01;32mPASSED\033[00m" >> /dev/stderr
   echo "PASSED" >> vast_test_report.txt
  else
   echo -e "\n\033[01;34mSpecial NMW test \033[01;31mFAILED\033[00m" >> /dev/stderr
   echo "FAILED" >> vast_test_report.txt
  fi
  #
  echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
  df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
  # 
 fi
fi

command -v valgrind &> /dev/null
if [ $? -eq 0 ];then
 if [ -z "$HOSTNAME" ];then
  HOSTNAME="$HOST"
 fi
 if [ -d ../sample_data ] && [ "$HOSTNAME" = "eridan" ] ;then
  TEST_PASSED=1
  util/clean_data.sh
  # Run the test
  echo "Special Valgrind test " >> /dev/stderr
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
   
   # clean up
   if [ -f valgrind_test.out ];then
    rm -f valgrind_test.out
   fi
   # conclude
   if [ $TEST_PASSED -eq 1 ];then
    echo -e "\n\033[01;34mSpecial Valgrind test \033[01;32mPASSED\033[00m" >> /dev/stderr
    echo "PASSED" >> vast_test_report.txt
   else
    echo -e "\n\033[01;34mSpecial Valgrind test \033[01;31mFAILED\033[00m" >> /dev/stderr
    echo "FAILED" >> vast_test_report.txt
   fi
  else
    FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND_TEST_NOT_PERFORMED_ASAN_ENABLED"
  fi # ldd vast | grep --quiet 'libasan'
  else
  # do not distract user with this obscure message if the test host is not eridan
  if [ "$HOSTNAME" = "eridan" ];then
   FAILED_TEST_CODES="$FAILED_TEST_CODES SPECIAL_VALGRIND_TEST_NOT_PERFORMED_NO_DATA"
  fi
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
 wget -c "http://scan.sai.msu.ru/~kirx/pub/M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails.tar.bz2" && tar -xjf M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails.tar.bz2 && rm -f M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails.tar.bz2
 cd $WORKDIR
fi

if [ -d ../M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Photometric error rescaling test " >> /dev/stderr
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
 TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0341);sqrt(a*a)<0.005" | bc -ql`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mPhotometric error rescaling test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mPhotometric error rescaling test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 TEST_PASSED=1
 # Run the test
 echo "Testing the lightcurve parsing function " >> /dev/stderr
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
 echo -e "A\nB\n" | $(lib/find_timeout_command.sh) 10 sort --random-sort > /dev/null
 if [ $? -eq 0 ];then
  MD5SUM_OF_PROCESSED_LC=`echo "$TEST_LIGHTCURVE" | $(lib/find_timeout_command.sh) 10 sort --random-sort | util/cute_lc | $MD5COMMAND | awk '{print $1}'`
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

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mTest of the lightcurve parsing function \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mTest of the lightcurve parsing function \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi 

else
 FAILED_TEST_CODES="$FAILED_TEST_CODES LCPARSER_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
 

#### Test lightcurve filters
TEST_PASSED=1
# Run the test
echo "Testing lightcurve filters " >> /dev/stderr
echo -n "Testing lightcurve filters: " >> vast_test_report.txt 

# Test if 'sort' understands the '--random-sort' argument, perform the following tests only if it does
echo -e "A\nB\n" | $(lib/find_timeout_command.sh) 10 sort --random-sort > /dev/null
if [ $? -eq 0 ];then
 # The first test relies on the MD5 sum calculation
 if [ "$MD5COMMAND" != "none" ];then
  # Random-sort the test lightcurve and run it through lib/test/stetson_test to make sure sorting doesn't afffect the result 
  # (meaning that sorting is done correctly within VaST).
  TEST_LIGHTCURVE_SHUFFLED=`echo "$TEST_LIGHTCURVE" | $(lib/find_timeout_command.sh) 10 sort --random-sort`
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
# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mTest of the lightcurve filters \033[01;32mPASSED\033[00m" >> /dev/stderr
 echo "PASSED" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mTest of the lightcurve filters \033[01;31mFAILED\033[00m" >> /dev/stderr
 echo "FAILED" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#



#### Period search servers test
TEST_PASSED=1
# Run the test
echo "Performing a period search test " >> /dev/stderr
echo -n "Period search test: " >> vast_test_report.txt 

if [ ! -d ../vast_test_lightcurves ];then
 mkdir ../vast_test_lightcurves
fi
if [ ! -f ../vast_test_lightcurves/out00095_edit_edit.dat ];then
 cd ../vast_test_lightcurves
 wget -c "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/out00095_edit_edit.dat.bz2" && bunzip2 out00095_edit_edit.dat.bz2
 cd $WORKDIR
fi

PERIOD_SEARCH_SERVERS="none scan.sai.msu.ru vast.sai.msu.ru"
# Local period search
LOCAL_FREQUENCY_CD=`lib/lk_compute_periodogram ../vast_test_lightcurves/out00095_edit_edit.dat 2 0.1 0.1 | awk '{printf "%.4f",$1}'`
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH001"
fi
if [ "$LOCAL_FREQUENCY_CD" != "0.8202" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH002"
fi

# Remote period search
for PERIOD_SEARCH_SERVER in $PERIOD_SEARCH_SERVERS ;do
 #REMOTE_FREQUENCY_CD=`WEBBROWSER=curl ./pokaz_laflerkinman.sh ../vast_test_lightcurves/out00095_edit_edit.dat 2>/dev/null | grep 'L&K peak 2' | awk '{print $2}' FS='&nu; ='  | awk '{printf "%.4f",$1}'`
 REMOTE_FREQUENCY_CD=`WEBBROWSER=curl ./pokaz_laflerkinman.sh ../vast_test_lightcurves/out00095_edit_edit.dat 2>/dev/null | grep 'L&K peak 2' | awk -F '&nu; =' '{print $2}'  | awk '{printf "%.4f",$1}'`
 if [ "$REMOTE_FREQUENCY_CD" != "$LOCAL_FREQUENCY_CD" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH003_$PERIOD_SEARCH_SERVER"
 fi
done

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mPeriod search test \033[01;32mPASSED\033[00m" >> /dev/stderr
 echo "PASSED" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mPeriod search test \033[01;31mFAILED\033[00m" >> /dev/stderr
 echo "FAILED" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#




#### Lightcurve viewer test
TEST_PASSED=1
# Run the test
echo "Performing a lightcurve viewer test " >> /dev/stderr
echo -n "Lightcurve viewer test: " >> vast_test_report.txt 

if [ ! -d ../vast_test_lightcurves ];then
 mkdir ../vast_test_lightcurves
fi
if [ ! -f ../vast_test_lightcurves/out00095_edit_edit.dat ];then
 cd ../vast_test_lightcurves
 wget -c "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/out00095_edit_edit.dat.bz2" && bunzip2 out00095_edit_edit.dat.bz2
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
 FAILED_TEST_CODES="$FAILED_TEST_CODES LIGHTCURVEVIEWER004_TEST_NOT_PERFORMED"
fi

# cleanup
if [ -f 00095_edit_edit.ps ];then
 rm -f 00095_edit_edit.ps
fi

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mPeriod search test \033[01;32mPASSED\033[00m" >> /dev/stderr
 echo "PASSED" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mPeriod search test \033[01;31mFAILED\033[00m" >> /dev/stderr
 echo "FAILED" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


#### vizquery test
TEST_PASSED=1
# Run the test
echo "Performing a vizquery test " >> /dev/stderr
echo -n "vizquery test: " >> vast_test_report.txt 

if [ ! -d ../vast_test_lightcurves ];then
 mkdir ../vast_test_lightcurves
fi
if [ ! -f ../vast_test_lightcurves/test_vizquery_M31.input ];then
 cd ../vast_test_lightcurves
 wget -c "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/test_vizquery_M31.input.bz2" && bunzip2 test_vizquery_M31.input.bz2
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
  FAILED_TEST_CODES="$FAILED_TEST_CODES VIZQUERYTEST004"
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

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mvizquery test \033[01;32mPASSED\033[00m" >> /dev/stderr
 echo "PASSED" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mvizquery test \033[01;31mFAILED\033[00m" >> /dev/stderr
 echo "FAILED" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#



#### Standalone test for database querry scripts
TEST_PASSED=1
# Run the test
echo "Performing a standalone test for database querry scripts " >> /dev/stderr
echo -n "Testing database querry scripts: " >> vast_test_report.txt 

lib/update_offline_catalogs.sh all
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT__LOCAL_CAT_UPDATE"
fi

util/search_databases_with_curl.sh 22:02:43.29139 +42:16:39.9803 | grep --quiet "BL Lac"
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT001"
fi

util/search_databases_with_curl.sh 22:02:43.29139 +42:16:39.9803 | grep --quiet "BLLAC"
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT001a"
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
util/search_databases_with_vizquery.sh 34.8366337 -2.9776377 | grep 'omi Cet' | grep --quiet 'J-Ks=1.481+/-0.262 (M)'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT005_vizquery"
fi
# on-the-fly conversion
util/search_databases_with_vizquery.sh `lib/hms2deg 02:19:20.79 -02:58:39.5` | grep 'omi Cet' | grep --quiet 'J-Ks=1.481+/-0.262 (M)'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT005a_vizquery"
fi

# Coordinates in the HMS fromat
util/search_databases_with_vizquery.sh 02:19:20.79 -02:58:39.5 | grep 'omi Cet' | grep --quiet 'J-Ks=1.481+/-0.262 (M)'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT006_vizquery"
fi

util/search_databases_with_vizquery.sh 19:50:33.92439 +32:54:50.6097 | grep 'khi Cyg' | grep --quiet 'J-Ks=1.863+/-0.240 (Very red!)'
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
util/search_databases_with_vizquery.sh 13:21:18.38 +18:08:22.2 | grep 'SXPHE' | grep 'VARIABLE' | grep --quiet 'OU Com'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT012"
fi

# MASTER_OT J132104.04+560957.8 - AM CVn star, Gaia shoer timescale variable
util/search_databases_with_vizquery.sh 200.26675923087 +56.16607967965 | grep 'MASTER_OT J132104.04+560957.8' | grep --quiet 'Gaia2_SHORTTS'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT013"
fi

# Gaia Cepheid, first in the list
util/search_databases_with_vizquery.sh 237.17375455558 -42.26556630747 | grep 'VARIABLE' | grep --quiet 'Gaia2_CEPHEID'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT014"
fi

# Gaia RR Lyr, first in the list
util/search_databases_with_vizquery.sh 272.04211425638 -25.91123076425 | grep 'RRAB' | grep 'VARIABLE' | grep --quiet 'Gaia2_RRLYR'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT015"
fi

# Gaia LPV, first in the list. Do not mix it up with OGLE-BLG-RRLYR-01707 that is 36" away!
util/search_databases_with_vizquery.sh 265.86100820754 -34.10333534797 | grep -v 'OGLE-BLG-RRLYR-01707' | grep 'OGLE BLG-LPV-022489' | grep 'VARIABLE' | grep --quiet 'Gaia2_LPV'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT016"
fi

# Check that we are correctly formatting the OGLE variable name
util/search_databases_with_vizquery.sh 17:05:07.49 -32:37:57.2 | grep 'OGLE-BLG-RRLYR-00001' | grep 'VARIABLE' | grep --quiet 'Gaia2_RRLYR'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT017"
fi
util/search_databases_with_vizquery.sh `lib/hms2deg 17:05:07.49 -32:37:57.2` | grep 'OGLE-BLG-RRLYR-00001' | grep 'VARIABLE' | grep --quiet 'Gaia2_RRLYR'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT018"
fi

util/search_databases_with_vizquery.sh 17.25656 47.30456 | grep --quiet 'ASASSN-V J010901.57+471816.4'
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT019"
fi

### Test the local catalog search thing
# MOVED UP
#lib/update_offline_catalogs.sh
#if [ $? -ne 0 ];then
# TEST_PASSED=0
# FAILED_TEST_CODES="$FAILED_TEST_CODES STANDALONEDBSCRIPT__LOCAL_CAT_UPDATE"
#fi

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


# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mTest of the database querry scripts \033[01;32mPASSED\033[00m" >> /dev/stderr
 echo "PASSED" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mTest of the database querry scripts \033[01;31mFAILED\033[00m" >> /dev/stderr
 echo "FAILED" >> vast_test_report.txt
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
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Small CCD PSF-fitting test " >> /dev/stderr
 echo -n "Small CCD PSF-fitting test: " >> vast_test_report.txt 
 cp default.sex.ccd_example default.sex
 cp default.psfex.small_FoV default.psfex
 ./vast -P -u -f --noerrorsrescale ../sample_data/*.fit
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
  TEST=`echo "a=($SYSTEMATIC_NOISE_LEVEL)-(0.0192);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  TEST=`echo "a=($STATMAG)-(-11.757900);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF012a"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  TEST=`echo "a=($STATX)-(218.9638100);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF013"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  TEST=`echo "a=($STATY)-(247.8421000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF014"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  TEST=`echo "a=($STATIDX)-(0.276132);sqrt(a*a)<0.01" | bc -ql`
  # wSTD
  #TEST=`echo "a=($STATIDX)-(0.415123);sqrt(a*a)<0.01" | bc -ql`
  # wSTD with robust line fit for errors rescaling
  #TEST=`echo "a=($STATIDX)-(0.465435);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF015"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $14}'`
  #TEST=`echo "a=($STATIDX)-(0.022536);sqrt(a*a)<0.002" | bc -ql`
  # When u drop one of the 10 brightest stars...
  TEST=`echo "a=($STATIDX)-(0.024759);sqrt(a*a)<0.002" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF016"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  #TEST=`echo "a=($STATIDX)-(0.025649);sqrt(a*a)<0.002" | bc -ql`
  # detection on all 91 images
  TEST=`echo "a=($STATIDX)-(0.027688);sqrt(a*a)<0.002" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  TEST=`echo "a=($STATMAG)-(-11.221200);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF021a"
  fi
  STATX=`echo "$STATSTR" | awk '{print $3}'`
  TEST=`echo "a=($STATX)-(87.2099000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF022"
  fi
  STATY=`echo "$STATSTR" | awk '{print $4}'`
  TEST=`echo "a=($STATY)-(164.4314000);sqrt(a*a)<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF023"
  fi
  # indexes
  STATIDX=`echo "$STATSTR" | awk '{print $6}'`
  #TEST=`echo "a=($STATIDX)-(0.035324);sqrt(a*a)<0.01" | bc -ql`
  TEST=`echo "a=($STATIDX)-(0.038100);sqrt(a*a)<0.01" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  TEST=`echo "a=($STATIDX)-(0.045071);sqrt(a*a)<0.003" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF025"
  fi
  STATIDX=`echo "$STATSTR" | awk '{print $30}'`
  #TEST=`echo "a=($STATIDX)-(0.059230);sqrt(a*a)<0.001" | bc -ql`
  #TEST=`echo "a=($STATIDX)-(0.060416);sqrt(a*a)<0.001" | bc -ql`
  #TEST=`echo "a=($STATIDX)-(0.058155);sqrt(a*a)<0.001" | bc -ql`
  TEST=`echo "a=($STATIDX)-(0.059008);sqrt(a*a)<0.002" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
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
  
  # Check the log files corresponding to the first 9 images
  for IMGNUM in `seq 1 9`;do
   for LOGFILE_TO_CHECK in image0000$IMGNUM.cat.magpsfchi2filter_passed image0000$IMGNUM.cat.magpsfchi2filter_rejected image0000$IMGNUM.cat.magpsfchi2filter_thresholdcurve image0000$IMGNUM.cat.magparameter02filter_passed image0000$IMGNUM.cat.magparameter02filter_rejected image0000$IMGNUM.cat.magparameter02filter_thresholdcurve ;do
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
  NUMER_OF_REJECTED_STARS=`cat image00001.cat.magparameter02filter_rejected | wc -l | awk '{print $1}'`
  if [ $NUMER_OF_REJECTED_STARS -lt 9 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_EMPTYPSFFILTERINGLOFGILE_FEW_SRC_REJECTED_PSFmAPER"
  fi

 else
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mSmall CCD PSF-fitting test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mSmall CCD PSF-fitting test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


##### PSF-fitting of MASTER images test #####
# Download the test dataset if needed
if [ ! -d ../MASTER_test ];then
 cd ..
 wget -c "http://scan.sai.msu.ru/~kirx/pub/MASTER_test.tar.bz2" && tar -xvjf MASTER_test.tar.bz2 && rm -f MASTER_test.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../MASTER_test ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "MASTER CCD PSF-fitting test " >> /dev/stderr
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
  util/solve_plate_with_UCAC5 ../MASTER_test/wcs_fd_MASTER-KISL-WFC-1_EAST_W_-30_LIGHT_5_878280.fit
  if [ ! -f wcs_fd_MASTER-KISL-WFC-1_EAST_W_-30_LIGHT_5_878280.fit.cat.ucac5 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF004"
  else
   TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_fd_MASTER-KISL-WFC-1_EAST_W_-30_LIGHT_5_878280.fit.cat.ucac5 | wc -l | awk '{print $1}'`
   if [ $TEST -lt 1100 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF004a"
   fi
  fi 
  util/sysrem
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

  # Check the log files
  for IMGNUM in `seq 1 6`;do
   for LOGFILE_TO_CHECK in image0000$IMGNUM.cat.magpsfchi2filter_passed image0000$IMGNUM.cat.magpsfchi2filter_rejected image0000$IMGNUM.cat.magpsfchi2filter_thresholdcurve image0000$IMGNUM.cat.magparameter02filter_passed image0000$IMGNUM.cat.magparameter02filter_rejected image0000$IMGNUM.cat.magparameter02filter_thresholdcurve ;do
    if [ ! -s "$LOGFILE_TO_CHECK" ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES SMALLCCDPSF_EMPTYPSFFILTERINGLOFGILE_$LOGFILE_TO_CHECK"
    fi
   done
  done


 else
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mMASTER CCD PSF-fitting test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mMASTER CCD PSF-fitting test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES MASTERCCDPSF_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
#########################################
# Skip free disk space check on some pre-defined machines
# hope this check should work even if there is no 'hostname' command
hostname | grep --quiet eridan 
if [ $? -ne 0 ];then 
 # Free-up disk space if we run out of it
 #FREE_DISK_SPACE_MB=`df -l -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 # If we managed to get the disk space info
 if [ $? -eq 0 ];then
  TEST=`echo "($FREE_DISK_SPACE_MB)<2048" | bc -q`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DISKSPACE_TEST_ERROR"
  fi
  if [ $TEST -eq 1 ];then
   echo "WARNING: we are almost out of disk space, only $FREE_DISK_SPACE_MB MB remaining." >> /dev/stderr
   if [ $TEST_PASSED -eq 1 ];then
    if [ -d ../MASTER_test ];then
     echo "Deleting test data!" >> /dev/stderr
     rm -rf ../MASTER_test
    else
     echo "What was it? o_O" >> /dev/stderr
    fi
   else
    echo "The previous test did not pass - stopping here!
   
Failed test codes: $FAILED_TEST_CODES
" >> /dev/stderr
    exit 1
   fi # if [ $TEST_PASSED -eq 1 ];then
  fi # if [ $FREE_DISK_SPACE_MB -lt 1024 ];then
 fi # if [ $? -eq 0 ];then
fi # if [ $? -ne ];then # hostname check
#########################################


# If the test data are found
if [ -d ../M31_ISON_test ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "ISON M31 PSF-fitting test " >> /dev/stderr
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
  util/solve_plate_with_UCAC5 ../M31_ISON_test/M31-1-001-001_dupe-1.fts
  if [ ! -f wcs_M31-1-001-001_dupe-1.fts.cat.ucac5 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF004"
  else
   TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' wcs_M31-1-001-001_dupe-1.fts.cat.ucac5 | wc -l | awk '{print $1}'`
   if [ $TEST -lt 1500 ];then
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ISONM31PSF_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mISON M31 PSF-fitting test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mISON M31 PSF-fitting test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
 wget -c "http://scan.sai.msu.ru/~kirx/data/vast_tests/test_exclude_ref_image.tar.bz2" && tar -xvjf test_exclude_ref_image.tar.bz2 && rm -f test_exclude_ref_image.tar.bz2
 cd $WORKDIR
fi
# If the test data are found
if [ -d ../test_exclude_ref_image ];then
 TEST_PASSED=1
 util/clean_data.sh
 # Run the test
 echo "Exclude reference image test (PSF) " >> /dev/stderr
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
  if [ $N_IMG_USED_FOR_PHOTOMETRY -lt 302 ];then
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
  echo "ERROR: cannot find vast_summary.log" >> /dev/stderr
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF_ALL"
 fi

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mExclude reference image test (PSF) \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mExclude reference image test (PSF) \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES EXCLUDEREFIMAGEPSF_TEST_NOT_PERFORMED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#
#########################################
# Skip free disk space check on some pre-defined machines
# hope this check should work even if there is no 'hostname' command
hostname | grep --quiet eridan 
if [ $? -ne 0 ];then 
 # Free-up disk space if we run out of it
 #FREE_DISK_SPACE_MB=`df -l -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 # If we managed to get the disk space info
 if [ $? -eq 0 ];then
  TEST=`echo "($FREE_DISK_SPACE_MB)<4096" | bc -q`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DISKSPACE_TEST_ERROR"
  fi
  if [ $TEST -eq 1 ];then
   echo "WARNING: we are almost out of disk space, only $FREE_DISK_SPACE_MB MB remaining." >> /dev/stderr
   if [ $TEST_PASSED -eq 1 ];then
    if [ -d ../test_exclude_ref_image ];then
     echo "Deleting test data!" >> /dev/stderr
     rm -rf ../test_exclude_ref_image
    else
     echo "What was it? o_O" >> /dev/stderr
    fi
   else
    echo "The previous test did not pass - stopping here!
   
Failed test codes: $FAILED_TEST_CODES
" >> /dev/stderr
    exit 1
   fi # if [ $TEST_PASSED -eq 1 ];then
  fi # if [ $FREE_DISK_SPACE_MB -lt 1024 ];then
 fi # if [ $? -eq 0 ];then
fi # if [ $? -ne ];then # hostname check
#########################################



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
 echo "Internet connection error!" >> /dev/stderr
 echo "Internet connection error!" >> vast_test_report.txt
 echo "Failed test codes: $FAILED_TEST_CODES" >> /dev/stderr
 echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt
 exit 1
fi


#### Period search test
TEST_PASSED=1
# Run the test
echo "Performing the second period search test " >> /dev/stderr
echo -n "Performing the second period search test: " >> vast_test_report.txt 

lib/lk_compute_periodogram lib/test/hads_p0.060.dat 1.0 0.05 0.1 | grep "16.661" &>/dev/null
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH101"
fi
lib/deeming_compute_periodogram lib/test/hads_p0.060.dat 1.0 0.05 0.1 | grep "16.661" &>/dev/null
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH102"
fi
lib/deeming_compute_periodogram lib/test/hads_p0.060.dat 1.0 0.05 0.1 10 2>/dev/null | grep "16.661" | grep -- '+/-' &> /dev/null
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PERIODSEARCH103"
fi

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mThe second period search test \033[01;32mPASSED\033[00m" >> /dev/stderr
 echo "PASSED" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mThe second period search test \033[01;31mFAILED\033[00m" >> /dev/stderr
 echo "FAILED" >> vast_test_report.txt
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
 TEST_PASSED=1
 # Run the test
 echo "Performing coordinate conversion test " >> /dev/stderr
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
  TEST=`echo "$DISTANCE_ARCSEC<0.1" | bc -ql`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST_PASSED=0
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
  fi
  if [ $TEST -ne 1 ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES COORDINATESCONVERTION005_${POSITION_DEG// /_}"
  fi
 done
 
 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mCoordinate conversion test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mCoordinate conversion test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
 fi 
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES WCSTOOLS_NOT_INSTALLED"
fi
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#

#### TAI-UTC file updater
TEST_PASSED=1
# Run the test
echo "Performing TAI-UTC file updater test " >> /dev/stderr
echo -n "Performing TAI-UTC file updater test: " >> vast_test_report.txt 
# just test that the updater runs with no errors
lib/update_tai-utc.sh
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES TAImUTC001"
fi
# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mTAI-UTC file updater test \033[01;32mPASSED\033[00m" >> /dev/stderr
 echo "PASSED" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mTAI-UTC file updater test \033[01;31mFAILED\033[00m" >> /dev/stderr
 echo "FAILED" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#


#### Calendar date to JD conversion test
TEST_PASSED=1
# Run the test
echo "Calendar date to JD conversion test " >> /dev/stderr
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
  FAILED_TEST_CODES="$FAILED_TEST_CODES DATE2JDCONV010a_$TMP_FITS_FILE"
  break
 fi
done

# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mCalendar date to JD conversion test \033[01;32mPASSED\033[00m" >> /dev/stderr
 echo "PASSED" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mCalendar date to JD conversion test \033[01;31mFAILED\033[00m" >> /dev/stderr
 echo "FAILED" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#




#### Auxiliary web services test
TEST_PASSED=1

if [ ! -d ../vast_test_lightcurves ];then
 mkdir ../vast_test_lightcurves
fi

# Run the test
echo "Performing auxiliary web services test " >> /dev/stderr
echo -n "Performing auxiliary web services test: " >> vast_test_report.txt 

# OMC2ASCII converter
if [ ! -f ../vast_test_lightcurves/IOMC_4011000047.fits ];then
 cd ../vast_test_lightcurves
 wget -c "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/IOMC_4011000047.fits.bz2" && bunzip2 IOMC_4011000047.fits.bz2
 cd $WORKDIR
fi
#RESULTSURL=`curl --silent -F submit="Convert" -F file=@"../vast_test_lightcurves/IOMC_4011000047.fits" 'http://scan.sai.msu.ru/cgi-bin/omc_converter/process_omc.py' | grep 'Refresh' | awk '{print $2}' FS='url=' | sed 's:"::g' | awk '{print $1}' FS='>'`
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

# SuperWASP converter
if [ ! -f ../vast_test_lightcurves/1SWASP_J013623.20+480028.4.fits ];then
 cd ../vast_test_lightcurves
 wget -c "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/1SWASP_J013623.20+480028.4.fits.bz2" && bunzip2 1SWASP_J013623.20+480028.4.fits.bz2
 cd $WORKDIR
fi
#RESULTSURL=`curl --silent -F submit="Convert" -F file=@"../vast_test_lightcurves/1SWASP_J013623.20+480028.4.fits" 'http://scan.sai.msu.ru/cgi-bin/swasp_converter/process_swasp.py' | grep 'Refresh' | awk '{print $2}' FS='url=' | sed 's:"::g' | awk '{print $1}' FS='>'`
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
 wget -c "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/nsv14523hjd.dat.bz2" && bunzip2 nsv14523hjd.dat.bz2
 cd $WORKDIR
fi
#RESULTSURL=`curl --silent -F submit="Classify" -F file=@"../vast_test_lightcurves/nsv14523hjd.dat" 'http://scan.sai.msu.ru/cgi-bin/wwwupsilon/process_lightcurve.py' | grep 'Refresh' | awk '{print $2}' FS='url=' | sed 's:"::g' | awk '{print $1}' FS='>'`
RESULTSURL=`curl --silent -F submit="Classify" -F file=@"../vast_test_lightcurves/nsv14523hjd.dat" 'http://scan.sai.msu.ru/cgi-bin/wwwupsilon/process_lightcurve.py' | grep 'Refresh' | awk -F 'url=' '{print $2}' | sed 's:"::g' | awk -F '>' '{print $1}'`
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_WWWU_001"
fi
if [ -z "$RESULTSURL" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_WWWU_002"
else
 NLINES_IN_OUTPUT_ASCII_FILE=`curl --silent "$RESULTSURL" | grep 'class =  RRL_ab'`
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES AUXWEB_WWWU_003"
 fi
fi



# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mAuxiliary web services test \033[01;32mPASSED\033[00m" >> /dev/stderr
 echo "PASSED" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mAuxiliary web services test \033[01;31mFAILED\033[00m" >> /dev/stderr
 echo "FAILED" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#



# util/fov_of_wcs_calibrated_image.sh
TEST_PASSED=1
echo "Performing the image field of view script test " >> /dev/stderr
echo -n "Performing the image field of view script test: " >> vast_test_report.txt 

if [ ! -f ../individual_images_test/wcs_fd_Per3_2011-10-31_001.fts ];then
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 cd ../individual_images_test
 wget -c "http://scan.sai.msu.ru/~kirx/pub/wcs_fd_Per3_2011-10-31_001.fts.bz2" && bunzip2 wcs_fd_Per3_2011-10-31_001.fts.bz2
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
 TEST=`echo "$DISTANCE_FROM_IMAGE_CENTER_ARCSEC<0.3" | bc -ql`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  echo "TEST ERROR"
  TEST_PASSED=0
  TEST=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_ERROR"
 fi
 if [ $TEST -ne 1 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES IMAGEFOVSCRIPT_005"
 fi
else
 FAILED_TEST_CODES="$FAILED_TEST_CODES IMAGEFOVSCRIPT_TEST_NOT_PERFORMED"
fi


# Make an overall conclusion for this test
if [ $TEST_PASSED -eq 1 ];then
 echo -e "\n\033[01;34mImage field of view script test \033[01;32mPASSED\033[00m" >> /dev/stderr
 echo "PASSED" >> vast_test_report.txt
else
 echo -e "\n\033[01;34mImage field of view script test \033[01;31mFAILED\033[00m" >> /dev/stderr
 echo "FAILED" >> vast_test_report.txt
fi 
#
echo "$FAILED_TEST_CODES" >> vast_test_incremental_list_of_failed_test_codes.txt
df -h >> vast_test_incremental_list_of_failed_test_codes.txt  
#





#### HJD correction test
# needs VARTOOLS to run
command -v vartools &>/dev/null
if [ $? -eq 0 ];then
 TEST_PASSED=1

 if [ ! -d ../vast_test_lightcurves ];then
  mkdir ../vast_test_lightcurves
 fi
 for INPUTDATAFILE in naif0012.tls out_Cepheid_TDB_HJD_VARTOOLS.dat out_Cepheid_TT_HJD_VaST.dat out_Cepheid_UTC_raw.dat ;do
  if [ ! -f ../vast_test_lightcurves/"$INPUTDATAFILE" ];then
   cd ../vast_test_lightcurves
   wget -c "http://scan.sai.msu.ru/~kirx/pub/vast_test_lightcurves/$INPUTDATAFILE.bz2"
   bunzip2 "$INPUTDATAFILE".bz2
   cd $WORKDIR
  fi
 done

 # Run the test
 echo "Performing HJD correction test " >> /dev/stderr
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
  TEST=`echo "a=($A-$B);sqrt(a*a)<0.00002" | bc -ql`
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
  TEST=`echo "a=($A-$B);sqrt(a*a)<0.00010" | bc -ql`
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
  FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTION007"
 fi

 # Compare the VARTOOLS file with the VARTOOLS standard
 if [ -f HJDCORRECTION_problem.tmp ];then
  rm -f HJDCORRECTION_problem.tmp
 fi
 while read -r A REST && read -r B REST <&3; do 
  TEST=`echo "a=($A-$B);sqrt(a*a)<0.00002" | bc -ql`
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
  TEST=`echo "a=($A-$B);sqrt(a*a)<0.00010" | bc -ql`
  #TEST=`echo "a=($A-$B);sqrt(a*a)<0.00015" | bc -ql`
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

 # Make an overall conclusion for this test
 if [ $TEST_PASSED -eq 1 ];then
  echo -e "\n\033[01;34mHJD correction test \033[01;32mPASSED\033[00m" >> /dev/stderr
  echo "PASSED" >> vast_test_report.txt
 else
  echo -e "\n\033[01;34mHJD correction test \033[01;31mFAILED\033[00m" >> /dev/stderr
  echo "FAILED" >> vast_test_report.txt
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
# Skip free disk space check on some pre-defined machines
# hope this check should work even if there is no 'hostname' command
hostname | grep --quiet eridan 
if [ $? -ne 0 ];then 
 # Free-up disk space if we run out of it
 #FREE_DISK_SPACE_MB=`df -l -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
 # If we managed to get the disk space info
 if [ $? -eq 0 ];then
  TEST=`echo "($FREE_DISK_SPACE_MB)<4096" | bc -q`
  re='^[0-9]+$'
  if ! [[ $TEST =~ $re ]] ; then
   echo "TEST ERROR"
   TEST=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DISKSPACE_TEST_ERROR"
  fi
  if [ $TEST -eq 1 ];then
   echo "WARNING: we are almost out of disk space, only $FREE_DISK_SPACE_MB MB remaining." >> /dev/stderr
   for TEST_DATASET in ../Gaia16aye_SN ../individual_images_test ../KZ_Her_DSLR_transient_search_test ../M31_ISON_test ../M4_WFC3_F775W_PoD_lightcurves_where_rescale_photometric_errors_fails ../MASTER_test ../only_few_stars ../test_data_photo ../test_exclude_ref_image ../transient_detection_test_Ceres ../tycho2 ../vast_test_lightcurves ../vast_test__dark_flat_flag ;do
    # Simple safety thing
    TEST=`echo "$TEST_DATASET" | grep -c '\.\.'`
    if [ $TEST -ne 1 ];then
     continue
    fi
    #
    if [ -d "$TEST_DATASET" ];then
     rm -rf "$TEST_DATASET"
     #FREE_DISK_SPACE_MB=`df -l -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
     FREE_DISK_SPACE_MB=`df -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
     TEST=`echo "($FREE_DISK_SPACE_MB)<4096" | bc -q`
     if [ $TEST -eq 0 ];then
      break
     fi
    fi
   done
  fi # if [ $FREE_DISK_SPACE_MB -lt 1024 ];then
 fi # if [ $? -eq 0 ];then
fi # if [ $? -ne ];then # hostname check
#########################################



####################################################
# List all the error codes at the end of the report:
if [ -z "$FAILED_TEST_CODES" ];then
 FAILED_TEST_CODES="NONE"
fi
echo "Failed test codes: $FAILED_TEST_CODES" >> vast_test_report.txt

STOPTIME_UNIXSEC=`date +%s`
RUNTIME_MIN=`echo "($STOPTIME_UNIXSEC-$STARTTIME_UNIXSEC)/60" | bc -ql | awk '{printf "%.2f",$1}'`

echo "Test run time: $RUNTIME_MIN minutes" >> vast_test_report.txt

# Print out the final report
echo "

############# Test Report #############"
cat vast_test_report.txt

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
 if [ "yes" = "$USER_ANSWER" ] || [ "y" = "$USER_ANSWER" ] || [ "ys" = "$USER_ANSWER" ] || [ "Yes" = "$USER_ANSWER" ] || [ "YES" = "$USER_ANSWER" ] || [ "1" = "$USER_ANSWER" ] ;then
  MAIL_TEST_REPORT_TO_KIRX="YES"
 else
  MAIL_TEST_REPORT_TO_KIRX="NO"
 fi
fi

if [ "$MAIL_TEST_REPORT_TO_KIRX" = "YES" ];then
 HOST=`hostname`
 HOST="@$HOST"
 NAME="$USER$HOST"
 DATETIME=`LANG=C date --utc`
 SCRIPTNAME=`basename $0`
 LOG=`cat vast_test_report.txt`
 MSG="The script $0 has finished on $DATETIME at $PWD $LOG"
echo "
$MSG

"
 curl --silent 'http://scan.sai.msu.ru/vast/vasttestreport.php' --data-urlencode "name=$NAME running $SCRIPTNAME" --data-urlencode "message=$MSG" --data-urlencode 'submit=submit'
 if [ $? -eq 0 ];then
  echo "The test report was sent successfully"
 else
  echo "There was a problem sending the test report"
 fi
fi

if [ "$FAILED_TEST_CODES" != "NONE" ];then
 exit 1
fi
