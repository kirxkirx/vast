#!/usr/bin/env bash

EMPTY_OUTPUT_IMAGE_DIRECOTRY="/mnt/usb/VaST_test_VladimirB_2/GoodFrames/vast_test_VB"
if [ ! -d "$EMPTY_OUTPUT_IMAGE_DIRECOTRY" ];then
 EMPTY_OUTPUT_IMAGE_DIRECOTRY="../VaST_test_VladimirB_2/GoodFrames/vast_test_VB"
fi
EMPTY_OUTPUT_IMAGE_DIRECOTRY=`readlink -f $EMPTY_OUTPUT_IMAGE_DIRECOTRY`

TEST_DATA_ROOT="/mnt/usb/VaST_test_VladimirB_2"
if [ ! -d "$TEST_DATA_ROOT" ];then
 TEST_DATA_ROOT="../VaST_test_VladimirB_2"
fi
TEST_DATA_ROOT=`readlink -f $TEST_DATA_ROOT`

# EMPTY_OUTPUT_IMAGE_DIRECOTRY and TEST_DATA_ROOT have to be absolute paths, that's why we nead 'readlink -f'

######################################################################

if [ -z "$VAST_PATH" ];then
 VAST_PATH=`readlink -f $0`
 VAST_PATH=`dirname "$VAST_PATH"`
 VAST_PATH="${VAST_PATH/'util/'/}"
 VAST_PATH="${VAST_PATH/'lib/'/}"
 VAST_PATH="${VAST_PATH/'examples/'/}"
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH/examples/}"
 VAST_PATH="${VAST_PATH//'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=`echo "$VAST_PATH" | sed "s:'::g"`
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi

FAILED_TEST_CODES=""                            
TEST_PASSED=1

if [ ! -d "$TEST_DATA_ROOT" ];then
 echo "ERROR: the input image direcotry $TEST_DATA_ROOT is not found"
 exit 1
fi


if [ ! -d "$EMPTY_OUTPUT_IMAGE_DIRECOTRY" ];then
 echo "ERROR: the output image direcotry $EMPTY_OUTPUT_IMAGE_DIRECOTRY is not found"
 exit 1
fi

# Check that EMPTY_OUTPUT_IMAGE_DIRECOTRY is set, so we don't remove /*
if [ -z "$EMPTY_OUTPUT_IMAGE_DIRECOTRY" ];then
 echo "ERROR: EMPTY_OUTPUT_IMAGE_DIRECOTRY is not set"
 exit 1
fi
# Clear the output dir
for FILE in "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"/* ;do
 if [ -f "$FILE" ];then
  rm -f "$FILE"
 fi
done

########### Selftest ###########
#echo "Performing selftest"
## test that the certain records in the script are unique
#for RECORD in NIGHT IMAGE_DIR ;do
# LIST_OF_SUPPOSEDLY_UNIQE_RECORDS=`grep "$RECORD=" $0 | grep -v 'for ' | grep -v 'NIGHT_NUMBER'`
# for SUPPOSEDLY_UNIQE_RECORD in $LIST_OF_SUPPOSEDLY_UNIQE_RECORDS ;do
#  NUMBER_OF_SUPPOSEDLY_UNIQE_RECORDS=`grep -c "$SUPPOSEDLY_UNIQE_RECORD" $0`
#  if [ $NUMBER_OF_SUPPOSEDLY_UNIQE_RECORDS -ne 1 ];then
#   echo "ERROR: the record $SUPPOSEDLY_UNIQE_RECORD appears in $0 $NUMBER_OF_SUPPOSEDLY_UNIQE_RECORDS times, while we expect only one occurance!"
#   exit 1
#  fi
# done
#done
#echo "Done with the selftest"
################################



##########################################
############ Calibrate images ############
##########################################

##########################################################################################
NIGHT_NUMBER=1
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`
IMAGE_DIR=$TEST_DATA_ROOT/GoodFrames/20170827
DARK=$TEST_DATA_ROOT/GoodFrames/20170829/bdf/mdark60s.fit
FLAT=$TEST_DATA_ROOT/GoodFrames/20171013/bdf/bdf_20_b1-003FlatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
else
 echo "Processing images in $IMAGE_DIR"
fi
for IMAGE in "$IMAGE_DIR"/* "$DARK" "$FLAT" ;do
 if [ ! -f "$IMAGE" ];then
  echo "ERROR: cannot find image $IMAGE"
  exit 1
 fi
done

cd "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"
for IMAGE in "$IMAGE_DIR"/* ;do
 echo "### Calibrating $IMAGE"
# if [ -f "$IMAGE" ];then
  IMAGE_BASE=`basename "$IMAGE"`
  DARK_SUBTRACTED_IMAGE="$NIGHT"__d_"$IMAGE_BASE"
  FLAT_FIELD_CORRECTED_IMAGE="$NIGHT"__fd_"$IMAGE_BASE"
  echo "$VAST_PATH"/util/ccd/ms "$IMAGE" "$DARK" "$DARK_SUBTRACTED_IMAGE"
  "$VAST_PATH"/util/ccd/ms "$IMAGE" "$DARK" "$DARK_SUBTRACTED_IMAGE"
  echo "$VAST_PATH"/util/ccd/md "$DARK_SUBTRACTED_IMAGE" "$FLAT" "$FLAT_FIELD_CORRECTED_IMAGE"
  "$VAST_PATH"/util/ccd/md "$DARK_SUBTRACTED_IMAGE" "$FLAT" "$FLAT_FIELD_CORRECTED_IMAGE"
  rm -f "$DARK_SUBTRACTED_IMAGE"
# fi
done
##########################################################################################
##########################################################################################
NIGHT_NUMBER=$[$NIGHT_NUMBER+1]
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`
IMAGE_DIR=$TEST_DATA_ROOT/GoodFrames/20170829/V523Cas
DARK=$TEST_DATA_ROOT/GoodFrames/20170829/bdf/mdark60s.fit
FLAT=$TEST_DATA_ROOT/GoodFrames/20171013/bdf/bdf_20_b1-003FlatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
else
 echo "Processing images in $IMAGE_DIR"
fi
for IMAGE in "$IMAGE_DIR"/* "$DARK" "$FLAT" ;do
 if [ ! -f "$IMAGE" ];then
  echo "ERROR: cannot find image $IMAGE"
  exit 1
 fi
done

cd "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"
for IMAGE in "$IMAGE_DIR"/* ;do
 IMAGE_BASE=`basename "$IMAGE"`
 DARK_SUBTRACTED_IMAGE="$NIGHT"__d_"$IMAGE_BASE"
 FLAT_FIELD_CORRECTED_IMAGE="$NIGHT"__fd_"$IMAGE_BASE"
 "$VAST_PATH"/util/ccd/ms "$IMAGE" "$DARK" "$DARK_SUBTRACTED_IMAGE"
 "$VAST_PATH"/util/ccd/md "$DARK_SUBTRACTED_IMAGE" "$FLAT" "$FLAT_FIELD_CORRECTED_IMAGE"
 rm -f "$DARK_SUBTRACTED_IMAGE"
done
##########################################################################################
##########################################################################################
NIGHT_NUMBER=$[$NIGHT_NUMBER+1]
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`
IMAGE_DIR=$TEST_DATA_ROOT/GoodFrames/20170909/V523Cas
DARK=$TEST_DATA_ROOT/GoodFrames/20170909/bdf/mdark60s.fit
FLAT=$TEST_DATA_ROOT/GoodFrames/20171013/bdf/bdf_20_b1-003FlatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
else
 echo "Processing images in $IMAGE_DIR"
fi
for IMAGE in "$IMAGE_DIR"/* "$DARK" "$FLAT" ;do
 if [ ! -f "$IMAGE" ];then
  echo "ERROR: cannot find image $IMAGE"
  exit 1
 fi
done

cd "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"
for IMAGE in "$IMAGE_DIR"/* ;do
 IMAGE_BASE=`basename "$IMAGE"`
 DARK_SUBTRACTED_IMAGE="$NIGHT"__d_"$IMAGE_BASE"
 FLAT_FIELD_CORRECTED_IMAGE="$NIGHT"__fd_"$IMAGE_BASE"
 "$VAST_PATH"/util/ccd/ms "$IMAGE" "$DARK" "$DARK_SUBTRACTED_IMAGE"
 "$VAST_PATH"/util/ccd/md "$DARK_SUBTRACTED_IMAGE" "$FLAT" "$FLAT_FIELD_CORRECTED_IMAGE"
 rm -f "$DARK_SUBTRACTED_IMAGE"
done
##########################################################################################
##########################################################################################
NIGHT_NUMBER=$[$NIGHT_NUMBER+1]
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`
IMAGE_DIR=$TEST_DATA_ROOT/GoodFrames/20170910/V523Cas
DARK=$TEST_DATA_ROOT/GoodFrames/20170909/bdf/mdark60s.fit
FLAT=$TEST_DATA_ROOT/GoodFrames/20171013/bdf/bdf_20_b1-003FlatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
else
 echo "Processing images in $IMAGE_DIR"
fi
for IMAGE in "$IMAGE_DIR"/* "$DARK" "$FLAT" ;do
 if [ ! -f "$IMAGE" ];then
  echo "ERROR: cannot find image $IMAGE"
  exit 1
 fi
done

cd "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"
for IMAGE in "$IMAGE_DIR"/* ;do
 IMAGE_BASE=`basename "$IMAGE"`
 DARK_SUBTRACTED_IMAGE="$NIGHT"__d_"$IMAGE_BASE"
 FLAT_FIELD_CORRECTED_IMAGE="$NIGHT"__fd_"$IMAGE_BASE"
 "$VAST_PATH"/util/ccd/ms "$IMAGE" "$DARK" "$DARK_SUBTRACTED_IMAGE"
 "$VAST_PATH"/util/ccd/md "$DARK_SUBTRACTED_IMAGE" "$FLAT" "$FLAT_FIELD_CORRECTED_IMAGE"
 rm -f "$DARK_SUBTRACTED_IMAGE"
done
##########################################################################################
##########################################################################################
NIGHT_NUMBER=$[$NIGHT_NUMBER+1]
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`
IMAGE_DIR=$TEST_DATA_ROOT/GoodFrames/20171109
DARK=$TEST_DATA_ROOT/GoodFrames/20171116/bdf/mdark60s.fit
FLAT=$TEST_DATA_ROOT/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
else
 echo "Processing images in $IMAGE_DIR"
fi
for IMAGE in "$IMAGE_DIR"/* "$DARK" "$FLAT" ;do
 if [ ! -f "$IMAGE" ];then
  echo "ERROR: cannot find image $IMAGE"
  exit 1
 fi
done

cd "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"
for IMAGE in "$IMAGE_DIR"/* ;do
 IMAGE_BASE=`basename "$IMAGE"`
 DARK_SUBTRACTED_IMAGE="$NIGHT"__d_"$IMAGE_BASE"
 FLAT_FIELD_CORRECTED_IMAGE="$NIGHT"__fd_"$IMAGE_BASE"
 "$VAST_PATH"/util/ccd/ms "$IMAGE" "$DARK" "$DARK_SUBTRACTED_IMAGE"
 "$VAST_PATH"/util/ccd/md "$DARK_SUBTRACTED_IMAGE" "$FLAT" "$FLAT_FIELD_CORRECTED_IMAGE"
 rm -f "$DARK_SUBTRACTED_IMAGE"
done
##########################################################################################
##########################################################################################
NIGHT_NUMBER=$[$NIGHT_NUMBER+1]
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`
IMAGE_DIR=$TEST_DATA_ROOT/GoodFrames/20171111/V523Cas
DARK=$TEST_DATA_ROOT/GoodFrames/20171116/bdf/mdark60s.fit
FLAT=$TEST_DATA_ROOT/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
else
 echo "Processing images in $IMAGE_DIR"
fi
for IMAGE in "$IMAGE_DIR"/* "$DARK" "$FLAT" ;do
 if [ ! -f "$IMAGE" ];then
  echo "ERROR: cannot find image $IMAGE"
  exit 1
 fi
done

cd "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"
for IMAGE in "$IMAGE_DIR"/* ;do
 IMAGE_BASE=`basename "$IMAGE"`
 DARK_SUBTRACTED_IMAGE="$NIGHT"__d_"$IMAGE_BASE"
 FLAT_FIELD_CORRECTED_IMAGE="$NIGHT"__fd_"$IMAGE_BASE"
 "$VAST_PATH"/util/ccd/ms "$IMAGE" "$DARK" "$DARK_SUBTRACTED_IMAGE"
 "$VAST_PATH"/util/ccd/md "$DARK_SUBTRACTED_IMAGE" "$FLAT" "$FLAT_FIELD_CORRECTED_IMAGE"
 rm -f "$DARK_SUBTRACTED_IMAGE"
done
##########################################################################################
##########################################################################################
NIGHT_NUMBER=$[$NIGHT_NUMBER+1]
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`
IMAGE_DIR=$TEST_DATA_ROOT/GoodFrames/20171116/V523Cas
DARK=$TEST_DATA_ROOT/GoodFrames/20171116/bdf/mdark60s.fit
FLAT=$TEST_DATA_ROOT/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
else
 echo "Processing images in $IMAGE_DIR"
fi
for IMAGE in "$IMAGE_DIR"/* "$DARK" "$FLAT" ;do
 if [ ! -f "$IMAGE" ];then
  echo "ERROR: cannot find image $IMAGE"
  exit 1
 fi
done

cd "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"
for IMAGE in "$IMAGE_DIR"/* ;do
 IMAGE_BASE=`basename "$IMAGE"`
 DARK_SUBTRACTED_IMAGE="$NIGHT"__d_"$IMAGE_BASE"
 FLAT_FIELD_CORRECTED_IMAGE="$NIGHT"__fd_"$IMAGE_BASE"
 "$VAST_PATH"/util/ccd/ms "$IMAGE" "$DARK" "$DARK_SUBTRACTED_IMAGE"
 "$VAST_PATH"/util/ccd/md "$DARK_SUBTRACTED_IMAGE" "$FLAT" "$FLAT_FIELD_CORRECTED_IMAGE"
 rm -f "$DARK_SUBTRACTED_IMAGE"
done
##########################################################################################
##########################################################################################
NIGHT_NUMBER=$[$NIGHT_NUMBER+1]
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`
IMAGE_DIR=$TEST_DATA_ROOT/GoodFrames/20171122/V523Cas
DARK=$TEST_DATA_ROOT/GoodFrames/20171122/bdf/mdark60s.fit
FLAT=$TEST_DATA_ROOT/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
else
 echo "Processing images in $IMAGE_DIR"
fi
for IMAGE in "$IMAGE_DIR"/* "$DARK" "$FLAT" ;do
 if [ ! -f "$IMAGE" ];then
  echo "ERROR: cannot find image $IMAGE"
  exit 1
 fi
done

cd "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"
for IMAGE in "$IMAGE_DIR"/* ;do
 IMAGE_BASE=`basename "$IMAGE"`
 DARK_SUBTRACTED_IMAGE="$NIGHT"__d_"$IMAGE_BASE"
 FLAT_FIELD_CORRECTED_IMAGE="$NIGHT"__fd_"$IMAGE_BASE"
 "$VAST_PATH"/util/ccd/ms "$IMAGE" "$DARK" "$DARK_SUBTRACTED_IMAGE"
 "$VAST_PATH"/util/ccd/md "$DARK_SUBTRACTED_IMAGE" "$FLAT" "$FLAT_FIELD_CORRECTED_IMAGE"
 rm -f "$DARK_SUBTRACTED_IMAGE"
done
##########################################################################################
##########################################################################################
NIGHT_NUMBER=$[$NIGHT_NUMBER+1]
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`
IMAGE_DIR=$TEST_DATA_ROOT/GoodFrames/20171125/V523Cas
DARK=$TEST_DATA_ROOT/GoodFrames/20171125/bdf/mdark60s.fit
FLAT=$TEST_DATA_ROOT/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
else
 echo "Processing images in $IMAGE_DIR"
fi
for IMAGE in "$IMAGE_DIR"/* "$DARK" "$FLAT" ;do
 if [ ! -f "$IMAGE" ];then
  echo "ERROR: cannot find image $IMAGE"
  exit 1
 fi
done

cd "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"
for IMAGE in "$IMAGE_DIR"/* ;do
 IMAGE_BASE=`basename "$IMAGE"`
 DARK_SUBTRACTED_IMAGE="$NIGHT"__d_"$IMAGE_BASE"
 FLAT_FIELD_CORRECTED_IMAGE="$NIGHT"__fd_"$IMAGE_BASE"
 "$VAST_PATH"/util/ccd/ms "$IMAGE" "$DARK" "$DARK_SUBTRACTED_IMAGE"
 "$VAST_PATH"/util/ccd/md "$DARK_SUBTRACTED_IMAGE" "$FLAT" "$FLAT_FIELD_CORRECTED_IMAGE"
 rm -f "$DARK_SUBTRACTED_IMAGE"
done
##########################################################################################
##########################################################################################
NIGHT_NUMBER=$[$NIGHT_NUMBER+1]
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`
IMAGE_DIR=$TEST_DATA_ROOT/GoodFrames/20180206/V523Cas
DARK=$TEST_DATA_ROOT/GoodFrames/20171125/bdf/mdark60s.fit
FLAT=$TEST_DATA_ROOT/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
else
 echo "Processing images in $IMAGE_DIR"
fi
for IMAGE in "$IMAGE_DIR"/* "$DARK" "$FLAT" ;do
 if [ ! -f "$IMAGE" ];then
  echo "ERROR: cannot find image $IMAGE"
  exit 1
 fi
done

cd "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"
for IMAGE in "$IMAGE_DIR"/* ;do
 IMAGE_BASE=`basename "$IMAGE"`
 DARK_SUBTRACTED_IMAGE="$NIGHT"__d_"$IMAGE_BASE"
 FLAT_FIELD_CORRECTED_IMAGE="$NIGHT"__fd_"$IMAGE_BASE"
 "$VAST_PATH"/util/ccd/ms "$IMAGE" "$DARK" "$DARK_SUBTRACTED_IMAGE"
 "$VAST_PATH"/util/ccd/md "$DARK_SUBTRACTED_IMAGE" "$FLAT" "$FLAT_FIELD_CORRECTED_IMAGE"
 rm -f "$DARK_SUBTRACTED_IMAGE"
done
##########################################################################################
##########################################################################################
NIGHT_NUMBER=$[$NIGHT_NUMBER+1]
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`
IMAGE_DIR=$TEST_DATA_ROOT/GoodFrames/20180207/V523Cas
DARK=$TEST_DATA_ROOT/GoodFrames/20180207/bdf/mdark60s.fit
FLAT=$TEST_DATA_ROOT/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
else
 echo "Processing images in $IMAGE_DIR"
fi
for IMAGE in "$IMAGE_DIR"/* "$DARK" "$FLAT" ;do
 if [ ! -f "$IMAGE" ];then
  echo "ERROR: cannot find image $IMAGE"
  exit 1
 fi
done

cd "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"
for IMAGE in "$IMAGE_DIR"/* ;do
 IMAGE_BASE=`basename "$IMAGE"`
 DARK_SUBTRACTED_IMAGE="$NIGHT"__d_"$IMAGE_BASE"
 FLAT_FIELD_CORRECTED_IMAGE="$NIGHT"__fd_"$IMAGE_BASE"
 "$VAST_PATH"/util/ccd/ms "$IMAGE" "$DARK" "$DARK_SUBTRACTED_IMAGE"
 "$VAST_PATH"/util/ccd/md "$DARK_SUBTRACTED_IMAGE" "$FLAT" "$FLAT_FIELD_CORRECTED_IMAGE"
 rm -f "$DARK_SUBTRACTED_IMAGE"
done
##########################################################################################
##########################################################################################

# Go back to VaST home drecotry
cd "$VAST_PATH"


#######################################################
############ Run VaST on calibrated images ############
#######################################################


# Check that all the images are in good shape
for IMAGE in "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"/* ;do
 lib/fitsverify -q -e "$IMAGE"
 if [ $? -ne 0 ];then
  echo "ERROR: fitsverify failed for image $IMAGE"
  exit 1
 fi
done

# Clean-up results of the previous run
for SAVEDIR in TEST_VB_APPHOT ;do
 if [ -d "$SAVEDIR" ];then
  rm -rf "$SAVEDIR"
 fi
done

###### Run VaST in aperture photometry mode
util/clean_data.sh
cp default.sex.largestars default.sex
#./vast --nofind   --poly --sysrem 4 "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"/*
./vast --nofind   --poly  "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"/*
#util/save.sh TEST_VB_APPHOT
#util/load.sh TEST_VB_APPHOT
#exit 0 # !!!
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_000"
fi
# Check results
if [ -f vast_summary.log ];then
 grep --quiet "Images processed 1250" vast_summary.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_001"
 fi
 grep --quiet "Images used for photometry 1240" vast_summary.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_002"
 fi
 grep --quiet "Ref.  image: 2457993.39415 27.08.2017 21:25:55" vast_summary.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_000__REFIMAGE"
 fi
 grep --quiet "First image: 2457993.39415 27.08.2017 21:25:55" vast_summary.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_003"
 fi
 grep --quiet "Last  image: 2458157.35237 07.02.2018 20:25:46" vast_summary.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_004"
 fi
 grep --quiet "Magnitude-Size filter: Enabled" vast_summary.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_005"
 fi
 #grep --quiet "Photometric errors rescaling: YES" vast_summary.log
 grep --quiet "Photometric errors rescaling: NO" vast_summary.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_006"
 fi
 if [ ! -f vast_lightcurve_statistics.log ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_007"
 fi
 if [ ! -s vast_lightcurve_statistics.log ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_008"
 fi
 if [ ! -f vast_lightcurve_statistics_format.log ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_009"
 fi
 if [ ! -s vast_lightcurve_statistics_format.log ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_010"
 fi
 grep --quiet "IQR" vast_lightcurve_statistics_format.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_011"
 fi
 grep --quiet "eta" vast_lightcurve_statistics_format.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_012"
 fi
 grep --quiet "RoMS" vast_lightcurve_statistics_format.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_013"
 fi
 grep --quiet "rCh2" vast_lightcurve_statistics_format.log
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_014"
 fi
 N_AUTOCANDIDATES=`cat vast_autocandidates.log | wc -l | awk '{print $1}'`
 if [ $N_AUTOCANDIDATES -lt 2 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_000_N_AUTOCANDIDATES1__$N_AUTOCANDIDATES"
 fi
 #if [ $N_AUTOCANDIDATES -gt 6 ];then
 # TEST_PASSED=0
 # FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_000_N_AUTOCANDIDATES2"
 #fi
 #
 util/identify_noninteractive.sh `cat vast_autocandidates.log | while read A ;do grep "$A" vast_lightcurve_statistics.log ;done | sort -k2 | tail -n1 | awk '{print $5}'` | grep --quiet 'V0523 Cas'
 if [ $? -ne 0 ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_000_VARID"
 fi
 #
 #util/save.sh TEST_VB_APPHOT
else
 echo "ERROR: cannot find vast_summary.log" 1>&2
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_000__ALL"
fi




################# Cleanup
util/clean_data.sh
cp default.sex.ccd_example default.sex

################# Report
if [ $TEST_PASSED -ne 1 ];then
 echo "FAILED_TEST_CODES= $FAILED_TEST_CODES"
 echo "Test failed"
 exit 1
else
 echo "Test passed"
 exit 0
fi

