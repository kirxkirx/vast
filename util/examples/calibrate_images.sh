#!/usr/bin/env bash

EMPTY_OUTPUT_IMAGE_DIRECOTRY="/mnt/usb/VaST_test_VladimirB_2/GoodFrames/vast_test_VB"

######################################################################

# A more portable realpath wrapper
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
      cd "$(dirname "$1")" || exit 1
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit 1
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

# Function to remove the last occurrence of a directory from a path
remove_last_occurrence() {
    echo "$1" | awk -F/ -v dir=$2 '{
        found = 0;
        for (i=NF; i>0; i--) {
            if ($i == dir && found == 0) {
                found = 1;
                continue;
            }
            res = (i==NF ? $i : $i "/" res);
        }
        print res;
    }'
}

# Function to get full path to vast main directory from the script name
get_vast_path_ends_with_slash_from_this_script_name() {
 VAST_PATH=$(vastrealpath $0)
 VAST_PATH=$(dirname "$VAST_PATH")

 # Remove last occurrences of util, lib, examples
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "util")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "lib")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "examples")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "transients")

 # Make sure no '//' are left in the path (they look ugly)
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")

 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")

 # Check that VAST_PATH ends with '/'
 LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
 if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
  VAST_PATH="$VAST_PATH/"
 fi

 echo "$VAST_PATH"
}


if [ -z "$VAST_PATH" ];then
 VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
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
for INPUT_DIR in `grep IMAGE_DIR= $0 | grep -v 'for ' | awk -F '=' '{print $2}'` ;do
 if [ ! -d "$INPUT_DIR" ];then
  echo "ERROR: the input directory $INPUT_DIR does not exist!"
  if [ -f "$INPUT_DIR" ];then
   echo "ERROR: $INPUT_DIR is a file!"
  fi
  exit 1
 fi
 # make sure it is not empty
 for TESTFILE in "$INPUT_DIR"/* ;do
  if [ ! -f "$TESTFILE" ];then
   echo "ERROR: the input directory $INPUT_DIR is empty!"
   exit 1
  fi
 done
done
# test that all the input files actually exist
for INPUT_FILE in `grep -e "DARK=" -e "FLAT=" $0 | grep -v 'for ' | awk -F '=' '{print $2}'` ;do
 if [ ! -f "$INPUT_FILE" ];then
  echo "ERROR: the input directory $INPUT_FILE does not exist!"
  if [ -d "$INPUT_FILE" ];then
   echo "ERROR: $INPUT_FILE is a directory!"
  fi
  exit 1
 fi
done
################################



##########################################
############ Calibrate images ############
##########################################

##########################################################################################
NIGHT_NUMBER=1
NIGHT=`echo "$NIGHT_NUMBER" | awk '{printf "%03d",$1}'`
IMAGE_DIR=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20170827
DARK=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20170829/bdf/mdark60s.fit
FLAT=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171013/bdf/bdf_20_b1-003FlatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
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
IMAGE_DIR=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20170829/V523Cas
DARK=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20170829/bdf/mdark60s.fit
FLAT=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171013/bdf/bdf_20_b1-003FlatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
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
IMAGE_DIR=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20170909/V523Cas
DARK=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20170909/bdf/mdark60s.fit
FLAT=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171013/bdf/bdf_20_b1-003FlatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
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
IMAGE_DIR=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20170910/V523Cas
DARK=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20170909/bdf/mdark60s.fit
FLAT=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171013/bdf/bdf_20_b1-003FlatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
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
IMAGE_DIR=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171109
DARK=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171116/bdf/mdark60s.fit
FLAT=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
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
IMAGE_DIR=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171111/V523Cas
DARK=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171116/bdf/mdark60s.fit
FLAT=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
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
IMAGE_DIR=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171116/V523Cas
DARK=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171116/bdf/mdark60s.fit
FLAT=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
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
IMAGE_DIR=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171122/V523Cas
DARK=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171122/bdf/mdark60s.fit
FLAT=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
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
IMAGE_DIR=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171125/V523Cas
DARK=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171125/bdf/mdark60s.fit
FLAT=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
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
IMAGE_DIR=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20180206/V523Cas
DARK=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171125/bdf/mdark60s.fit
FLAT=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
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
IMAGE_DIR=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20180207/V523Cas
DARK=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20180207/bdf/mdark60s.fit
FLAT=/mnt/usb/VaST_test_VladimirB_2/GoodFrames/20171116/bdf/mflatG.fit

if [ ! -d "$IMAGE_DIR" ];then
 echo "ERROR: cannot find the image directory $IMAGE_DIR"
 exit 1
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
 grep --quiet "Photometric errors rescaling: YES" vast_summary.log
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
  FAILED_TEST_CODES="$FAILED_TEST_CODES TEST_VB_000_N_AUTOCANDIDATES1"
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

