#!/usr/bin/env bash


FAILED_TEST_CODES=""                            
TEST_PASSED=1

if [ ! -d /mnt/usb/NMW_NG_transient_detection_test ];then
 echo "ERROR: test data not found"
 exit 1
fi

# The following script is not supposed to override this
export REFERENCE_IMAGES=/mnt/usb/NMW_NG_transient_detection_test/reference_images

#
if [ -f ../exclusion_list.txt ];then
 mv ../exclusion_list.txt ../exclusion_list.txt_backup
fi
#

util/transients/transient_factory_test30.sh /mnt/usb/NMW_NG_transient_detection_test/second_epoch
if [ $? -ne 0 ];then
 echo "ERROR001"
 exit 1
fi

#
if [ -f ../exclusion_list.txt_backup ];then
 mv ../exclusion_list.txt_backup ../exclusion_list.txt
fi
#

for VARIABLE_TO_FIND in 'LX Aql' 'KS Aql' 'V0536 Aql' 'KU Aql' 'RT Aql' 'W Sge' ;do
 grep -q "$VARIABLE_TO_FIND" transient_report/index.html
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES  $VARIABLE_TO_FIND" 
 fi
done

NUMBER_OF_CANDIDATES=`grep '<h3>' transient_report/index.html | grep '_Aql10_' | wc -l`
if [ $NUMBER_OF_CANDIDATES -gt 21 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES  _Aql10_"
fi

if [ $TEST_PASSED -ne 1 ];then
 echo "FAILED_TEST_CODES= $FAILED_TEST_CODES"
 echo "Test failed"
 exit 1
else
 echo "Test passed"
 exit 0
fi

