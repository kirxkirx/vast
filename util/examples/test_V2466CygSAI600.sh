#!/usr/bin/env bash

# make sure the manual override TELESCOP variable is not set,
# otherwise it will mess up all the plate-solve tests
unset TELESCOP

FAILED_TEST_CODES=""                            
TEST_PASSED=1

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


############ Main test ############
TEST_DIR="/dataX/zubareva/V2466"
if [ ! -d "$TEST_DIR" ];then
# TEST_DIR="../61Cyg_photoplates_test"
# if [ ! -d "$TEST_DIR" ];then
#  cd ..
#  wget http://scan.sai.msu.ru/~kirx/data/vast_tests/61Cyg_photoplates_test.tar.bz2 && tar -xf 61Cyg_photoplates_test.tar.bz2 && rm -f 61Cyg_photoplates_test.tar.bz2
#  WGET_AND_UNPACK_RETURN_STATUS=$?
#  cd -
#  if [ $WGET_AND_UNPACK_RETURN_STATUS -ne 0 ];then
#   echo "ERROR: test data not found: $TEST_DIR"
#   exit 1
#  fi
# fi
 # Test data directory not found
 exit 0
fi

# Run the test
cp default.sex.ccd_example default.sex
./vast -x3 --notremovebadimages -f $TEST_DIR/*/*

############ Uncalibrated lightcurves ############
#
# True variables
for XY in "324.2908000 395.8234900" "89.3177000 609.9127800" "13.4411000 683.0615800" "253.9174000 144.3881100" "386.7056000 1567.0581100" "490.5498000 1657.0260000" "525.0734300 153.9590000" "557.5206300 839.0488900" "694.1275000 1097.6557600" "769.1994000 501.9125100" "813.8674900 327.3450000" ;do
 LIGHTCURVEFILE=$(find_source_by_X_Y_in_vast_lightcurve_statistics_log $XY)
 if [ "$LIGHTCURVEFILE" == "none" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  INSTRMAG_VARIABLE_NOT_DETECTED__${XY// /_}"
 fi
 grep -q "$LIGHTCURVEFILE" vast_autocandidates.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  INSTRMAG_VARIABLE_NOT_SELECTED__$LIGHTCURVEFILE"__${XY//" "/"_"}
 fi
 grep -q "$LIGHTCURVEFILE" vast_list_of_likely_constant_stars.log
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  VARIABLE_MISTAKEN_FOR_CONSTANT__$LIGHTCURVEFILE"__${XY//" "/"_"}
 fi
done
##################################################


############ Calibrate lightcurves ############
util/magnitude_calibration.sh R zero_point
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES  MAGNITUDE_CALIBRATION_FAILED"
fi

############ Calibrated lightcurves ############
# True variables
for XY in "324.2908000 395.8234900" "89.3177000 609.9127800" "13.4411000 683.0615800" "253.9174000 144.3881100" "386.7056000 1567.0581100" "490.5498000 1657.0260000" "525.0734300 153.9590000" "557.5206300 839.0488900" "694.1275000 1097.6557600" "769.1994000 501.9125100" "813.8674900 327.3450000" ;do
 LIGHTCURVEFILE=$(find_source_by_X_Y_in_vast_lightcurve_statistics_log $XY)
 if [ "$LIGHTCURVEFILE" == "none" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  CALIBMAG_VARIABLE_NOT_DETECTED__${XY// /_}"
 fi
 grep -q "$LIGHTCURVEFILE" vast_autocandidates.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  CALIBMAG_VARIABLE_NOT_SELECTED__$LIGHTCURVEFILE"__${XY//" "/"_"}
 fi
 grep -q "$LIGHTCURVEFILE" vast_list_of_likely_constant_stars.log
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  CALIBMAG_VARIABLE_MISTAKEN_FOR_CONSTANT__$LIGHTCURVEFILE"__${XY//" "/"_"}
 fi
done


############ Conclusions ############

if [ $TEST_PASSED -ne 1 ];then
 echo "FAILED_TEST_CODES= $FAILED_TEST_CODES"
 echo "Test failed"
 exit 1
else
 echo "Test passed"
 exit 0
fi

