#!/usr/bin/env bash


FAILED_TEST_CODES=""                            
TEST_PASSED=1

if [ ! -d /mnt/usb/vast_test_NMW_isolated_nonmatch/ ];then
 echo "ERROR: test data not found"
 exit 1
fi

# The following script is not supposed to override this
#export REFERENCE_IMAGES=/mnt/usb/NMW_NG_transient_detection_test/reference_images

#
if [ -f ../exclusion_list.txt ];then
 mv ../exclusion_list.txt ../exclusion_list.txt_backup
fi
#
if [ -f bad_region.lst ];then
 mv bad_region.lst bad_region.lst_backup
fi

if [ -f /mnt/usb/vast_test_NMW_isolated_nonmatch/bad_region.lst ];then
 cp /mnt/usb/vast_test_NMW_isolated_nonmatch/bad_region.lst .
else
 echo "ERROR000"
 exit 1
fi

util/transients/transient_factory_test31.sh /mnt/usb/vast_test_NMW_isolated_nonmatch/
if [ $? -ne 0 ];then
 echo "ERROR001"
 exit 1
fi

#
if [ -f ../exclusion_list.txt_backup ];then
 mv ../exclusion_list.txt_backup ../exclusion_list.txt
fi
#
if [ -f bad_region.lst_backup ];then
 mv bad_region.lst_backup bad_region.lst
fi

if [ ! -s transient_report/index.html ];then
 echo "ERROR002"
 exit 1
fi

# test for two objects that should not be among the candidates
grep -q -e '0457 1795' -e '0459 1776' transient_report/index.html
if [ $? -eq 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES  0457"
fi
grep -q -e '0572 0665' -e '0572 0665' transient_report/index.html
if [ $? -eq 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES  0572"
fi

NUMBER_OF_CANDIDATES=`grep '<h3>' transient_report/index.html | grep '_Tau3_' | wc -l`
if [ $NUMBER_OF_CANDIDATES -gt 1 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES  _Tau3_"
fi

if [ $TEST_PASSED -ne 1 ];then
 echo "FAILED_TEST_CODES= $FAILED_TEST_CODES"
 echo "Test failed"
 exit 1
else
 echo "Test passed"
 exit 0
fi

