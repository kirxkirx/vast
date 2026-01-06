#!/usr/bin/env bash


FAILED_TEST_CODES=""                            
TEST_PASSED=1

if [ ! -d ../vast_test__dark_flat_flag ];then
 echo "ERROR: test data not found"
 exit 1
fi

util/clean_data.sh
cp default.sex.largestars default.sex

if [ -f d_test4.fit ];then
 rm -f d_test4.fit
fi
util/ccd/ms ../vast_test__dark_flat_flag/V523Cas_20_b1-001G60s.fit ../vast_test__dark_flat_flag/mdark60s.fit d_test4.fit
if [ $? -ne 0 ];then
 echo "DARK_FLAT_FLAG__ERROR001"
 exit 1
fi
if [ ! -f d_test4.fit ];then
 echo "DARK_FLAT_FLAG__ERROR002"
 exit 1
fi
if [ ! -s d_test4.fit ];then
 echo "DARK_FLAT_FLAG__ERROR003"
 exit 1
fi
# Verify that the input file is a valid FITS file
lib/fitsverify -q -e d_test4.fit     
if [ $? -ne 0 ];then
 echo "DARK_FLAT_FLAG__ERROR004"
 exit 1
fi

# There should be no flag image for d_test4.fit
#lib/autodetect_aperture_main d_test4.fit 2>&1 | grep "FLAG_IMAGE image00000.flag"
#lib/sextract_single_image_noninteractive d_test4.fit 2>&1 | grep "FLAG_IMAGE image00000.flag"
lib/sextract_single_image_noninteractive d_test4.fit 2>&1 | grep "FLAG_IMAGE image" | grep "\.flag"
if [ $? -eq 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR005"
fi

# Get catalog name from vast_images_catalogs.log (new PID-based naming convention)
if [ ! -s vast_images_catalogs.log ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR006a_no_vast_images_catalogs_log"
else
 CATALOG_NAME=$(grep 'd_test4.fit' vast_images_catalogs.log | awk '{print $1}')
 if [ -z "$CATALOG_NAME" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR006b_catalog_not_in_log"
 else
  if [ ! -f "$CATALOG_NAME" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR006_$CATALOG_NAME"
  fi
  # Derive flag and weight filenames from catalog name
  FLAG_NAME="${CATALOG_NAME%.cat}.flag"
  WEIGHT_NAME="${CATALOG_NAME%.cat}.weight"
  for FILE_TO_TEST in "$FLAG_NAME" "$WEIGHT_NAME" ;do
   if [ -f "$FILE_TO_TEST" ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR007_$FILE_TO_TEST"
   fi
  done

  N_LINES_SEXTRACTOR_CATALOG=$(cat "$CATALOG_NAME" | wc -l)
  # expect 563
  if [ $N_LINES_SEXTRACTOR_CATALOG -gt 700 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR008_$N_LINES_SEXTRACTOR_CATALOG"
  fi
  if [ $N_LINES_SEXTRACTOR_CATALOG -lt 350 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR009_$N_LINES_SEXTRACTOR_CATALOG"
  fi

  for FILE_TO_TEST in "$CATALOG_NAME" "$FLAG_NAME" "$WEIGHT_NAME" ;do
   if [ -f "$FILE_TO_TEST" ];then
    rm -f "$FILE_TO_TEST"
   fi
  done
 fi
fi
if [ -f fd_test4.fit ];then
 rm -f fd_test4.fit
fi
util/ccd/md d_test4.fit ../vast_test__dark_flat_flag/mflatG.fit fd_test4.fit
if [ $? -ne 0 ];then
 echo "DARK_FLAT_FLAG__ERROR101"
 exit 1
fi
if [ ! -f fd_test4.fit ];then
 echo "DARK_FLAT_FLAG__ERROR102"
 exit 1
fi
if [ ! -s fd_test4.fit ];then
 echo "DARK_FLAT_FLAG__ERROR103"
 exit 1
fi
# Verify that the input file is a valid FITS file
lib/fitsverify -q -e fd_test4.fit     
if [ $? -ne 0 ];then
 echo "DARK_FLAT_FLAG__ERROR104"
 exit 1
fi

# There should be a flag image for fd_test4.fit
#lib/autodetect_aperture_main fd_test4.fit 2>&1 | grep "FLAG_IMAGE image00000.flag"
#lib/sextract_single_image_noninteractive fd_test4.fit 2>&1 | grep "FLAG_IMAGE image00000.flag"
lib/sextract_single_image_noninteractive fd_test4.fit 2>&1 | grep "FLAG_IMAGE image" | grep "\.flag"
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR105"
fi

# Get catalog name from vast_images_catalogs.log (new PID-based naming convention)
if [ ! -s vast_images_catalogs.log ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR106a_no_vast_images_catalogs_log"
else
 CATALOG_NAME=$(grep 'fd_test4.fit' vast_images_catalogs.log | awk '{print $1}')
 if [ -z "$CATALOG_NAME" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR106b_catalog_not_in_log"
 else
  if [ ! -f "$CATALOG_NAME" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR106_$CATALOG_NAME"
  else
   # grep '         0' will select only sources with 0 external flag
   N_LINES_SEXTRACTOR_CATALOG=$(cat "$CATALOG_NAME" | grep '         0' | wc -l)
   # expect 571
   if [ $N_LINES_SEXTRACTOR_CATALOG -gt 700 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR107_$N_LINES_SEXTRACTOR_CATALOG"
   fi
   if [ $N_LINES_SEXTRACTOR_CATALOG -lt 350 ];then
     TEST_PASSED=0
     FAILED_TEST_CODES="$FAILED_TEST_CODES DARK_FLAT_FLAG__ERROR108_$N_LINES_SEXTRACTOR_CATALOG"
   fi
  fi
 fi
fi



# Cleanup
if [ -f d_test4.fit ];then
 rm -f d_test4.fit
fi
if [ -f fd_test4.fit ];then
 rm -f fd_test4.fit
fi
util/clean_data.sh
cp default.sex.ccd_example default.sex

# Report
if [ $TEST_PASSED -ne 1 ];then
 echo "FAILED_TEST_CODES= $FAILED_TEST_CODES"
 echo "Test failed"
 exit 1
else
 echo "Test passed"
 exit 0
fi

