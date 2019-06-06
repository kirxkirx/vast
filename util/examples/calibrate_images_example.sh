#!/usr/bin/env bash

EMPTY_OUTPUT_IMAGE_DIRECOTRY="/mnt/usb/MSU_Obs/2019_05_13/processed_images"

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
fi

FAILED_TEST_CODES=""                            
TEST_PASSED=1

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
# test that the certain records in the script are unique
for RECORD in NIGHT IMAGE_DIR ;do
 LIST_OF_SUPPOSEDLY_UNIQE_RECORDS=`grep "$RECORD=" $0 | grep -v 'for ' | grep -v 'NIGHT_NUMBER'`
 for SUPPOSEDLY_UNIQE_RECORD in $LIST_OF_SUPPOSEDLY_UNIQE_RECORDS ;do
  NUMBER_OF_SUPPOSEDLY_UNIQE_RECORDS=`grep -c "$SUPPOSEDLY_UNIQE_RECORD" $0`
  if [ $NUMBER_OF_SUPPOSEDLY_UNIQE_RECORDS -ne 1 ];then
   echo "ERROR: the record $SUPPOSEDLY_UNIQE_RECORD appears in $0 $NUMBER_OF_SUPPOSEDLY_UNIQE_RECORDS times, while we expect only one occurance!"
   exit 1
  fi
 done
done
# test that all the input directories actually exist
for INPUT_DIR in `grep IMAGE_DIR= $0 | grep -v 'for ' | awk '{print $2}' FS='='` ;do
 if [ ! -d "$INPUT_DIR" ];then
  echo "ERROR: the input directory $INPUT_DIR does not exist!"
  if [ -f "$INPUT_DIR" ];then
   echo "ERROR: $INPUT_DIR is a file!"
  fi
  exit 1
 fi
 # make sure it is not empty
 for TESTFILE in "$INPUT_DIR"/* ;do
  if [ ! -f "$TESTFILE" ] && [ ! -d "$TESTFILE" ]; then
   echo "ERROR: the input directory $INPUT_DIR is empty!"
   exit 1
  fi
 done
done
################################

##################################################
############ Stack calibration frames ############
##################################################
BIAS_FRAMES_DIR="/mnt/usb/MSU_Obs/2019_05_13/bias"
cd "$BIAS_FRAMES_DIR"
# Stack bias frames
"$VAST_PATH"/util/ccd/mk bias_m28C-*.fit
mv median.fit mbias.fit
echo "Done with mbias.fit"
#
DARK_FRAMES_DIR="/mnt/usb/MSU_Obs/2019_05_13/dark"
cd "$DARK_FRAMES_DIR"
# Stack 60 sec darak frames
"$VAST_PATH"/util/ccd/mk dark_60s_m28C-*.fit
mv median.fit mdark60s.fit
echo "Done with mdark60s.fit"
FLAT_FRAMES_DIR="/mnt/usb/MSU_Obs/2019_05_13/flat"
cd "$FLAT_FRAMES_DIR"
# Bias-subtract all flats!
for FLAT_FIELD_FILE in flat*.fit ;do
 # The bias-subtracted flats will be named b_flat*.fit
 "$VAST_PATH"/util/ccd/ms "$FLAT_FIELD_FILE" "$BIAS_FRAMES_DIR"/mbias.fit b_"$FLAT_FIELD_FILE"
done
echo "Done with bias-subtracting the flat-field frames"
# Stack Clear filter frames
"$VAST_PATH"/util/ccd/mk b_flat_Clear-*C.fit
mv median.fit mflatClear.fit
echo "Done with mflatClear.fit"

##########################################
############ Calibrate images ############
##########################################

##########################################################################################
NIGHT_NUMBER=0
##########################################################################################
NIGHT_NUMBER=$[$NIGHT_NUMBER+1]
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`

################# Clear-band images
IMAGE_DIR=/mnt/usb/MSU_Obs/2019_05_13
DARK="$DARK_FRAMES_DIR"/mdark60s.fit
FLAT="$FLAT_FRAMES_DIR"/mflatClear.fit

# Check that the image directory and all the input images actually exist
if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
fi
for IMAGE in "$IMAGE_DIR"/* "$DARK" "$FLAT" ;do
 if [ ! -f "$IMAGE" ] && [ ! -d "$IMAGE" ];then
  echo "ERROR: cannot find image $IMAGE"
  exit 1
 fi
done

# perform the calibration
cd "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"
for IMAGE in "$IMAGE_DIR"/AM_CVn_Clear_60s-*C.fit ;do
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

###### run VaST in aperture photometry mode on Clear-band images
util/clean_data.sh
cp default.sex.largestars default.sex
./vast  --poly  "$EMPTY_OUTPUT_IMAGE_DIRECOTRY"/*__fd_AM_CVn_Clear_60s-*C.fit
