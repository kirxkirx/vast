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

############ Initial segfault test ############
TEST_DIR="/mnt/usb/61Cyg_photoplates_test_edge_segfault"
if [ ! -d "$TEST_DIR" ];then
 TEST_DIR="../61Cyg_photoplates_test_edge_segfault"
 if [ ! -d "$TEST_DIR" ];then
  cd ..
  wget http://scan.sai.msu.ru/~kirx/data/vast_tests/61Cyg_photoplates_test_edge_segfault.tar.bz2 && tar -xf 61Cyg_photoplates_test_edge_segfault.tar.bz2 && rm -f 61Cyg_photoplates_test_edge_seg.tar.bz2
  WGET_AND_UNPACK_RETURN_STATUS=$?
  cd -
  if [ $WGET_AND_UNPACK_RETURN_STATUS -ne 0 ];then
   echo "ERROR: test data not found: $TEST_DIR"
   exit 1
  fi
 fi
fi


if [ -d "$TEST_DIR" ];then
 cp default.sex.61_Cyg_photoplates default.sex
 ./vast -d -u --selectbestaperture --position_dependent_correction -o -r -f $TEST_DIR/SCA*__-7_-7.fits
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  SEGFAULT_TEST_001"
 fi
else
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES  SEGFAULT_TEST_NOT_PERFORMED"
fi

############ Main test ############
TEST_DIR="/mnt/usb/61Cyg_photoplates_test"
if [ ! -d "$TEST_DIR" ];then
 TEST_DIR="../61Cyg_photoplates_test"
 if [ ! -d "$TEST_DIR" ];then
  cd ..
  wget http://scan.sai.msu.ru/~kirx/data/vast_tests/61Cyg_photoplates_test.tar.bz2 && tar -xf 61Cyg_photoplates_test.tar.bz2 && rm -f 61Cyg_photoplates_test.tar.bz2
  WGET_AND_UNPACK_RETURN_STATUS=$?
  cd -
  if [ $WGET_AND_UNPACK_RETURN_STATUS -ne 0 ];then
   echo "ERROR: test data not found: $TEST_DIR"
   exit 1
  fi
 fi
fi

# Run the test
cp default.sex.61_Cyg_photoplates default.sex
./vast -u --selectbestaperture -j -o -r -f $TEST_DIR/*

############ Uncalibrated lightcurves ############
#
# 1452.1687000 1144.3038300 - is a true variable that is very hard to recover
#
# 970.5773900 2131.2663600 - small-amplitude EW
#
# True variables
for XY in "482.9663100 1658.7934600" "1804.7764900 768.9890100" "138.2354000 1710.2705100" "279.6370800 384.3089000" "903.0775100 795.6828000" "1655.3160400 1404.8461900" "970.5773900 2131.2663600" ;do
 LIGHTCURVEFILE=$(find_source_by_X_Y_in_vast_lightcurve_statistics_log $XY)
 if [ "$LIGHTCURVEFILE" == "none" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  INSTRMAG_VARIABLE_NOT_DETECTED__${XY// /_}"
 fi
 grep --quiet "$LIGHTCURVEFILE" vast_autocandidates.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  INSTRMAG_VARIABLE_NOT_SELECTED__$LIGHTCURVEFILE"__${XY//" "/"_"}
 fi
 grep --quiet "$LIGHTCURVEFILE" vast_list_of_likely_constant_stars.log
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  VARIABLE_MISTAKEN_FOR_CONSTANT__$LIGHTCURVEFILE"__${XY//" "/"_"}
 fi
done

#
# 1545.0174600 2119.8383800 - a nasty blend
#
# False candidates
#for XY in "384.8848000 2162.4240700" "433.1528000 1952.2907700" "1601.8258100 293.3326100" "194.6116900 2114.5200200" "1243.8588900 596.4639300" "348.6729100 2109.0227100" "205.4760000 2129.5366200" "117.2828000 1714.1951900" "274.2864100 1762.4866900" "89.8596000 730.3389900" "538.6436200 1444.2902800" "384.4455000 2162.3833000" "724.4339000 1412.2819800" "1545.0174600 2119.8383800" ;do
for XY in "433.1528000 1952.2907700" "1601.8258100 293.3326100" "194.6116900 2114.5200200" "1243.8588900 596.4639300" "348.6729100 2109.0227100" "117.2828000 1714.1951900" "274.2864100 1762.4866900" "89.8596000 730.3389900" "538.6436200 1444.2902800" "724.4339000 1412.2819800" "1545.0174600 2119.8383800" ;do
 LIGHTCURVEFILE=$(find_source_by_X_Y_in_vast_lightcurve_statistics_log $XY)
 if [ "$LIGHTCURVEFILE" == "none" ];then
  # The bad source is not detected at all, good
  continue
 fi
 grep --quiet "$LIGHTCURVEFILE" vast_autocandidates.log
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  INSTRMAG_FALSE_CANDIDATE_SELECTED__$LIGHTCURVEFILE"__${XY//" "/"_"}
 fi
done
##################################################


############ Calibrate lightcurves ############
util/magnitude_calibration.sh B photocurve
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES  MAGNITUDE_CALIBRATION_FAILED"
fi

############ Calibrated lightcurves ############
# True variables
for XY in "482.9663100 1658.7934600" "1804.7764900 768.9890100" "138.2354000 1710.2705100" "279.6370800 384.3089000" "903.0775100 795.6828000" "1655.3160400 1404.8461900" "970.5773900 2131.2663600" ;do
 LIGHTCURVEFILE=$(find_source_by_X_Y_in_vast_lightcurve_statistics_log $XY)
 if [ "$LIGHTCURVEFILE" == "none" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  CALIBMAG_VARIABLE_NOT_DETECTED__${XY// /_}"
 fi
 grep --quiet "$LIGHTCURVEFILE" vast_autocandidates.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  CALIBMAG_VARIABLE_NOT_SELECTED__$LIGHTCURVEFILE"__${XY//" "/"_"}
 fi
 grep --quiet "$LIGHTCURVEFILE" vast_list_of_likely_constant_stars.log
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  CALIBMAG_VARIABLE_MISTAKEN_FOR_CONSTANT__$LIGHTCURVEFILE"__${XY//" "/"_"}
 fi
done

# False candidates
#for XY in "384.8848000 2162.4240700" "433.1528000 1952.2907700" "1601.8258100 293.3326100" "194.6116900 2114.5200200" "1243.8588900 596.4639300" "348.6729100 2109.0227100" "205.4760000 2129.5366200" "117.2828000 1714.1951900" "274.2864100 1762.4866900" "89.8596000 730.3389900" "538.6436200 1444.2902800" "384.4455000 2162.3833000" "724.4339000 1412.2819800" "1545.0174600 2119.8383800" ;do
# "1545.0174600 2119.8383800" aka out20124.dat is a nasty false candidate next to a bright star, cant think of a good way to get rid of it
#for XY in "384.8848000 2162.4240700" "433.1528000 1952.2907700" "1601.8258100 293.3326100" "194.6116900 2114.5200200" "1243.8588900 596.4639300" "348.6729100 2109.0227100" "205.4760000 2129.5366200" "117.2828000 1714.1951900" "274.2864100 1762.4866900" "89.8596000 730.3389900" "538.6436200 1444.2902800" "384.4455000 2162.3833000" "724.4339000 1412.2819800" ;do
for XY in "433.1528000 1952.2907700" "1601.8258100 293.3326100" "194.6116900 2114.5200200" "1243.8588900 596.4639300" "348.6729100 2109.0227100" "117.2828000 1714.1951900" "274.2864100 1762.4866900" "89.8596000 730.3389900" "538.6436200 1444.2902800" "724.4339000 1412.2819800" ;do
 LIGHTCURVEFILE=$(find_source_by_X_Y_in_vast_lightcurve_statistics_log $XY)
 if [ "$LIGHTCURVEFILE" == "none" ];then
  # The bad source is not detected at all, good
  continue
 fi
 grep --quiet "$LIGHTCURVEFILE" vast_autocandidates.log
 if [ $? -eq 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  CALIBMAG_FALSE_CANDIDATE_SELECTED__$LIGHTCURVEFILE"__${XY//" "/"_"}
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

