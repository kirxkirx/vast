#!/usr/bin/env bash
#
# Test of the closed-roof check of util/transients/transient_factory_test31.sh.
#
# The NMW-TexasTech cameras keep imaging when the observatory roof closes without the camera
# control software knowing it. util/detect_closed_roof recognizes such images (no stars, the
# background at the dark-frame level; the tool itself is tested in util/examples/test_vast.sh),
# and the transient factory runs it on the new images of the TTUQ1b1x1 and TTUQ2b1x1 cameras
# (CHECK_FOR_CLOSED_ROOF). When the latest new image of a field was taken with the roof closed,
# the field is not processed further: the report gets the banner
#   ***** ACTION NEEDED - OBSERVATORY ROOF CLOSED? *****
# as its first ERROR line, and a line "ERROR: OBSERVATORY ROOF CLOSED? ..." naming the image, the
# field and the camera. unmw sends an alert for a report line that has both ERROR and OBSERVATORY
# ROOF CLOSED, and reads the camera, the field and the time of the image from the report, so all
# of this is a contract with unmw (see .claude/notes.md).
#
# The transient factory runs on fresh copies of the two TTUQ2b1x1 closed-roof crops of the
# NMW-TexasTech__closed_roof_test dataset, with its two Pup-02-Q2b1x1 reference crops:
#  - default settings with the dark-frame directory of the camera: the banner is the first ERROR
#    line of the report, the ERROR line names the latest image, the field and the camera, unmw
#    reads the right camera, field and time of the latest image, the report is complete, and the
#    field stops at the check (in seconds, instead of failing in the VaST run with "less than 4
#    images processed");
#  - CLOSED_ROOF_CHECK_MAX_STARS=0 (not a valid value): a WARNING says that it is ignored, and the
#    closed roof is still reported;
#  - an empty dark-frame directory: without a dark frame a closed roof cannot be told from thick
#    clouds, so no closed roof is reported, but an ERROR says that there is no matching dark frame;
#  - CHECK_FOR_CLOSED_ROOF=no: nothing mentions a closed roof (the starless images then go through
#    the rest of the pipeline, which takes a minute or more).
# The checks look for the stable parts of the messages, not for their exact wording.
#
# Usage: util/examples/test_closed_roof_check.sh
# The script works in the VaST directory it belongs to. The test data are expected in
# ../NMW-TexasTech__closed_roof_test (next to the VaST directory) and are downloaded if they are
# not there. The script prints "FAILED: CODE description" for every failed check and exits with
# code 1 if any check failed, 0 if all of them passed. At the end it puts back bad_region.lst,
# neverexclude_list.txt and default.sex of the VaST directory (the transient factory replaces them
# with the files of the camera) and removes the files of its VaST runs with util/clean_data.sh.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# A manual TELESCOP override would change how the images are handled (see util/examples/test_vast.sh)
unset TELESCOP
# The settings under test come from the camera settings of the transient factory or from the
# runs below, never from the environment of this script
unset CAMERA_SETTINGS CHECK_FOR_CLOSED_ROOF CLOSED_ROOF_CHECK_MAX_STARS CLOSED_ROOF_CHECK_MAX_SKY_ADU_PER_SEC CLOSED_ROOF_CHECK_MAX_NOISE_ADU DARK_FRAMES_DIR_OR_FILE FLAT_FIELD_DIR_OR_FILE REFERENCE_IMAGES

# Work in the VaST directory this script belongs to
cd "$(dirname "$0")/../.." || exit 1

FAILED_CODES=""
fail() {
 FAILED_CODES="$FAILED_CODES $1"
 echo "FAILED: $1 $2"
}

# Print the number of files among the arguments (an unmatched glob pattern counts as none)
count_files() {
 N_FILES=0
 for FILE_TO_COUNT in "$@" ;do
  if [ -f "$FILE_TO_COUNT" ];then
   N_FILES=$((N_FILES + 1))
  fi
 done
 echo "$N_FILES"
}

TEST_DATA_DIR="../NMW-TexasTech__closed_roof_test"
TEST_DATA_ARCHIVE="NMW-TexasTech__closed_roof_test.tar.bz2"
CAMERA="TTUQ2b1x1"
FIELD="Pup-02-Q2b1x1"
EARLIER_IMAGE="Pup-02-Q2b1x1_2026-11-12_02-48-08_20.00sec_-0.00C_LIGHT_0326.fits"
# The later of the two closed-roof images (DATE-OBS 2026-11-12T08:56:16.8)
LATEST_IMAGE="Pup-02-Q2b1x1_2026-11-12_02-56-16_20.00sec_-0.00C_LIGHT_0327.fits"
LATEST_IMAGE_DATE_UTC="12.11.2026 08:56:16"
# With the closed-roof check the field stops within seconds
MAX_RUN_TIME_SEC=60

if [ ! -x util/detect_closed_roof ] || [ ! -x util/transients/transient_factory_test31.sh ];then
 fail CLOSEDROOFCHECK_TOOL_NOT_FOUND "util/detect_closed_roof is not built (run make in the VaST directory)"
 exit 1
fi

# Get the test data if they are not there yet: the GitHub release asset first (unless
# VAST_TEST_DATA_NO_GITHUB=yes), then the mirrors, as download_test_data_file() in
# util/examples/test_vast.sh does
if [ ! -d "$TEST_DATA_DIR" ];then
 echo "Downloading the test data $TEST_DATA_ARCHIVE"
 TEST_DATA_URLS="http://tau.kirx.net/vast_test_data/$TEST_DATA_ARCHIVE http://scan.sai.msu.ru/~kirx/data/vast_tests/$TEST_DATA_ARCHIVE"
 if [ "$VAST_TEST_DATA_NO_GITHUB" != "yes" ];then
  TEST_DATA_URLS="https://github.com/kirxkirx/vast/releases/download/test-data-v1/$TEST_DATA_ARCHIVE $TEST_DATA_URLS"
 fi
 (
  cd .. || exit 1
  for URL in $TEST_DATA_URLS ;do
   rm -f "$TEST_DATA_ARCHIVE"
   if curl -L --fail --silent --show-error --connect-timeout 30 --speed-limit 1024 --speed-time 60 -o "$TEST_DATA_ARCHIVE" "$URL" && bunzip2 -t "$TEST_DATA_ARCHIVE" 2>/dev/null ;then
    tar -xjf "$TEST_DATA_ARCHIVE"
    break
   fi
  done
  rm -f "$TEST_DATA_ARCHIVE"
 )
fi
if [ ! -d "$TEST_DATA_DIR" ];then
 fail CLOSEDROOFCHECK_TEST_NOT_PERFORMED "the test data $TEST_DATA_DIR are not available"
 exit 1
fi
# Absolute paths: the transient factory hands them on to other scripts
TEST_DATA_DIR=$(cd "$TEST_DATA_DIR" && pwd)
CLOSED_IMAGES_DIR="$TEST_DATA_DIR/$CAMERA/closed"
CAMERA_DARK_FRAMES_DIR="$TEST_DATA_DIR/$CAMERA/darks"
REFERENCE_IMAGES_DIR="$TEST_DATA_DIR/reference_images"
if [ ! -f "$CLOSED_IMAGES_DIR/$EARLIER_IMAGE" ] || [ ! -f "$CLOSED_IMAGES_DIR/$LATEST_IMAGE" ] || [ "$(count_files "$CAMERA_DARK_FRAMES_DIR"/*)" != "1" ] || [ "$(count_files "$REFERENCE_IMAGES_DIR"/"$FIELD"_*.fits)" != "2" ];then
 fail CLOSEDROOFCHECK000 "the test data in $TEST_DATA_DIR are incomplete"
 exit 1
fi

# The private work directory. The path of the new images has to contain the camera name (the
# transient factory takes CAMERA_SETTINGS from it) and the word 'test' (then the transient
# factory does not update the exclusion list).
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vast_closed_roof_check_test.XXXXXX" 2>/dev/null)
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ];then
 fail CLOSEDROOFCHECK000 "cannot create a work directory"
 exit 1
fi
NEW_IMAGES_DIR="$WORK_DIR/$CAMERA/closed"
EMPTY_DARK_FRAMES_DIR="$WORK_DIR/empty_dark_frames_dir"
# No flat fielding: the transient factory would look for a flat field in the NMW calibration
# directory of this machine (if there is one); the closed-roof check comes before it anyway
EMPTY_FLAT_FIELDS_DIR="$WORK_DIR/empty_flat_fields_dir"
SAVED_FILES_DIR="$WORK_DIR/saved_files_of_the_vast_directory"
if ! mkdir -p "$EMPTY_DARK_FRAMES_DIR" "$EMPTY_FLAT_FIELDS_DIR" "$SAVED_FILES_DIR" ;then
 fail CLOSEDROOFCHECK000 "cannot create directories in $WORK_DIR"
 rm -rf "$WORK_DIR"
 exit 1
fi

# The transient factory replaces these files of the VaST directory with the files of the camera
# when a field gets past the closed-roof check: put back the files that were there before
FILES_TO_PUT_BACK="bad_region.lst neverexclude_list.txt default.sex"
for FILE_TO_SAVE in $FILES_TO_PUT_BACK ;do
 if [ -f "$FILE_TO_SAVE" ];then
  cp -p "$FILE_TO_SAVE" "$SAVED_FILES_DIR/"
 fi
done
# clean_up() is called by the EXIT trap below
# shellcheck disable=SC2329
clean_up() {
 for FILE_TO_PUT_BACK in $FILES_TO_PUT_BACK ;do
  if [ -f "$SAVED_FILES_DIR/$FILE_TO_PUT_BACK" ] && ! cmp -s "$SAVED_FILES_DIR/$FILE_TO_PUT_BACK" "$FILE_TO_PUT_BACK" ;then
   cp -p "$SAVED_FILES_DIR/$FILE_TO_PUT_BACK" "$FILE_TO_PUT_BACK"
  fi
 done
 util/clean_data.sh > /dev/null 2>&1
 rm -rf "$WORK_DIR"
}
trap clean_up EXIT
trap 'exit 1' HUP INT TERM

# Run the transient factory on fresh copies of the two closed-roof images
# $1 - a name of the run for its log file $WORK_DIR/factory_<name>.log
# $2 and later - the settings of this run (VARIABLE=value)
# Sets FACTORY_EXIT_CODE and RUN_TIME_SEC
run_factory() {
 RUN_NAME="$1"
 shift
 rm -rf "${WORK_DIR:?}/$CAMERA"
 if ! mkdir -p "$NEW_IMAGES_DIR" || ! cp "$CLOSED_IMAGES_DIR/$EARLIER_IMAGE" "$CLOSED_IMAGES_DIR/$LATEST_IMAGE" "$NEW_IMAGES_DIR"/ ;then
  fail CLOSEDROOFCHECK000 "cannot copy the test images to $NEW_IMAGES_DIR"
  exit 1
 fi
 util/clean_data.sh > /dev/null 2>&1
 rm -f transient_report/index.html
 RUN_START_UNIXSEC=$(date +%s)
 # GAIA_DR2_CLIENT=none: the known-star check of the candidates is not needed here, and with an
 # online Gaia client the transient factory would first probe the VizieR mirrors (that takes
 # minutes when they do not answer)
 env GAIA_DR2_CLIENT=none REFERENCE_IMAGES="$REFERENCE_IMAGES_DIR" DARK_FRAMES_DIR_OR_FILE="$CAMERA_DARK_FRAMES_DIR" FLAT_FIELD_DIR_OR_FILE="$EMPTY_FLAT_FIELDS_DIR" "$@" util/transients/transient_factory_test31.sh "$NEW_IMAGES_DIR" > "$WORK_DIR/factory_$RUN_NAME.log" 2>&1 < /dev/null
 FACTORY_EXIT_CODE=$?
 RUN_TIME_SEC=$(( $(date +%s) - RUN_START_UNIXSEC ))
 echo " the transient factory exited with code $FACTORY_EXIT_CODE after $RUN_TIME_SEC s"
}

# The first line of the report that contains ERROR: unmw shows it in its summary of the night
first_error_line_of_the_report() {
 grep 'ERROR' transient_report/index.html 2>/dev/null | head -n 1
}

# Return 0 if the report or a log of the run $1 mentions a closed roof
closed_roof_is_mentioned() {
 for FILE_TO_SEARCH in transient_report/index.html transient_factory_test31.txt transient_factory.log "$WORK_DIR/factory_$1.log" ;do
  if [ -f "$FILE_TO_SEARCH" ] && grep -q 'OBSERVATORY ROOF CLOSED' "$FILE_TO_SEARCH" ;then
   return 0
  fi
 done
 return 1
}

# Print what may help to find out why a check of the run $1 failed
show_run_diagnostics() {
 echo " ERROR and WARNING lines of transient_report/index.html:"
 grep -e 'ERROR' -e 'WARNING' transient_report/index.html 2>/dev/null | head -n 10 | sed 's/^/  /'
 echo " the closed-roof check in the report:"
 grep -A 4 'Closed roof check of the new images' transient_report/index.html 2>/dev/null | head -n 8 | sed 's/^/  /'
 echo " the last lines of the output of the transient factory:"
 tail -n 15 "$WORK_DIR/factory_$1.log" 2>/dev/null | sed 's/^/  /'
}

# Every run of the transient factory starts by bringing the offline catalogs up to date: do it
# first, so that downloading a catalog does not count against the run time limit below
lib/update_offline_catalogs.sh all > "$WORK_DIR/update_offline_catalogs.log" 2>&1

##### The default settings of the camera with its dark-frame directory #####
echo "Transient factory run with the default settings of $CAMERA and its dark-frame directory"
FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
run_factory default
if [ $FACTORY_EXIT_CODE -ne 0 ];then
 fail CLOSEDROOFCHECK001 "the transient factory exited with code $FACTORY_EXIT_CODE"
fi
if [ ! -s transient_report/index.html ];then
 fail CLOSEDROOFCHECK002 "no transient_report/index.html"
else
 # unmw shows the first ERROR line of a report and sends the alert for this banner
 FIRST_ERROR_LINE=$(first_error_line_of_the_report)
 if ! echo "$FIRST_ERROR_LINE" | grep -q -F 'ACTION NEEDED - OBSERVATORY ROOF CLOSED?' ;then
  fail CLOSEDROOFCHECK003 "the first ERROR line of the report is not the closed-roof banner: $FIRST_ERROR_LINE"
 fi
 ROOF_CLOSED_ERROR_LINE=$(grep -F 'ERROR: OBSERVATORY ROOF CLOSED?' transient_report/index.html | head -n 1)
 # The field name is also a part of the image names, so look for it in the rest of the line
 ROOF_CLOSED_ERROR_LINE_WITHOUT_IMAGE_NAMES=$(echo "$ROOF_CLOSED_ERROR_LINE" | sed -e "s/$LATEST_IMAGE//g" -e "s/$EARLIER_IMAGE//g")
 if [ -z "$ROOF_CLOSED_ERROR_LINE" ];then
  fail CLOSEDROOFCHECK004 "no 'ERROR: OBSERVATORY ROOF CLOSED?' line in the report"
 elif ! echo "$ROOF_CLOSED_ERROR_LINE" | grep -q -F "$LATEST_IMAGE" || ! echo "$ROOF_CLOSED_ERROR_LINE_WITHOUT_IMAGE_NAMES" | grep -q -F "$FIELD" || ! echo "$ROOF_CLOSED_ERROR_LINE_WITHOUT_IMAGE_NAMES" | grep -q -F "$CAMERA" ;then
  fail CLOSEDROOFCHECK005 "the 'ERROR: OBSERVATORY ROOF CLOSED?' line does not name the latest image $LATEST_IMAGE, the field $FIELD and the camera $CAMERA: $ROOF_CLOSED_ERROR_LINE"
 fi
 if ! grep -q 'Processing complete!' transient_report/index.html ;then
  fail CLOSEDROOFCHECK006 "no 'Processing complete!' in the report"
 fi
 if grep -q 'less than 4 images processed' transient_report/index.html ;then
  fail CLOSEDROOFCHECK007 "the images went to the VaST run (less than 4 images processed) instead of stopping at the closed-roof check"
 fi
 # The camera, the field and the time of the latest image, read the way unmw (roof_closed_alert.sh) reads them
 REPORT_CAMERA=$(grep '^CAMERA_SETTINGS= ' transient_report/index.html | head -n 1 | awk '{print $2}')
 REPORT_FIELD=$(grep 'Processing fields' transient_report/index.html | head -n 1 | sed -e 's/.*Processing fields//' -e 's/<br>.*//' | awk '{print $1}')
 REPORT_IMAGE_TIME=$(grep 'Last  image:' transient_report/index.html | head -n 1 | awk '{print $4" "$5}')
 if [ "$REPORT_CAMERA" != "$CAMERA" ] || [ "$REPORT_FIELD" != "$FIELD" ] || ! echo "$REPORT_IMAGE_TIME" | grep -q "^$LATEST_IMAGE_DATE_UTC" ;then
  fail CLOSEDROOFCHECK009 "unmw would read the camera '$REPORT_CAMERA', the field '$REPORT_FIELD' and the time '$REPORT_IMAGE_TIME' (expected $CAMERA, $FIELD and $LATEST_IMAGE_DATE_UTC)"
 fi
 # Both images were compared with the dark frame found in the dark-frame directory of the camera
 IMAGES_NOT_SHOWN_CLOSED=""
 for IMAGE_TO_CHECK in "$EARLIER_IMAGE" "$LATEST_IMAGE" ;do
  if ! grep 'CLOSED_ROOF stars=' transient_report/index.html | grep ' zero_level=dark ' | grep -q -F "image=$IMAGE_TO_CHECK" ;then
   IMAGES_NOT_SHOWN_CLOSED="$IMAGES_NOT_SHOWN_CLOSED $IMAGE_TO_CHECK"
  fi
 done
 if [ -n "$IMAGES_NOT_SHOWN_CLOSED" ];then
  fail CLOSEDROOFCHECK010 "the report does not show these images as CLOSED_ROOF at the level of the dark frame of the camera:$IMAGES_NOT_SHOWN_CLOSED"
 fi
fi
if [ $RUN_TIME_SEC -ge $MAX_RUN_TIME_SEC ];then
 fail CLOSEDROOFCHECK008 "the run took $RUN_TIME_SEC s - the field did not stop at the closed-roof check"
fi
if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
 show_run_diagnostics default
fi

##### An invalid value of CLOSED_ROOF_CHECK_MAX_STARS #####
echo "Transient factory run with CLOSED_ROOF_CHECK_MAX_STARS=0 (not a valid value)"
FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
run_factory maxstars0 CLOSED_ROOF_CHECK_MAX_STARS=0
if [ ! -s transient_report/index.html ];then
 fail CLOSEDROOFCHECK012 "no transient_report/index.html"
else
 if ! grep -q 'WARNING: ignoring CLOSED_ROOF_CHECK_MAX_STARS' transient_report/index.html ;then
  fail CLOSEDROOFCHECK011 "no 'WARNING: ignoring CLOSED_ROOF_CHECK_MAX_STARS' line in the report"
 fi
 if ! first_error_line_of_the_report | grep -q -F 'ACTION NEEDED - OBSERVATORY ROOF CLOSED?' || ! grep -q -F 'ERROR: OBSERVATORY ROOF CLOSED?' transient_report/index.html ;then
  fail CLOSEDROOFCHECK012 "the closed roof is not reported: $(first_error_line_of_the_report)"
 fi
fi
if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
 show_run_diagnostics maxstars0
fi

##### No dark frame #####
echo "Transient factory run with an empty dark-frame directory"
FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
run_factory emptydarkdir DARK_FRAMES_DIR_OR_FILE="$EMPTY_DARK_FRAMES_DIR"
if [ $FACTORY_EXIT_CODE -ne 0 ] || [ ! -s transient_report/index.html ] || ! grep -q 'Processing complete!' transient_report/index.html ;then
 fail CLOSEDROOFCHECK013 "no complete transient_report/index.html (the transient factory exited with code $FACTORY_EXIT_CODE)"
else
 if closed_roof_is_mentioned emptydarkdir ;then
  fail CLOSEDROOFCHECK014 "OBSERVATORY ROOF CLOSED is reported without a dark frame to tell a closed roof from clouds"
 fi
 if ! grep 'ERROR' transient_report/index.html | grep -q 'no matching dark frame' ;then
  fail CLOSEDROOFCHECK015 "no ERROR line saying that there is no matching dark frame"
 fi
fi
if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
 show_run_diagnostics emptydarkdir
fi

##### The check switched off #####
echo "Transient factory run with CHECK_FOR_CLOSED_ROOF=no (the starless images go through the whole pipeline: a minute or more)"
FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
run_factory checkoff CHECK_FOR_CLOSED_ROOF=no
if [ $FACTORY_EXIT_CODE -ne 0 ] || [ ! -s transient_report/index.html ];then
 fail CLOSEDROOFCHECK016 "no transient_report/index.html (the transient factory exited with code $FACTORY_EXIT_CODE)"
else
 if closed_roof_is_mentioned checkoff ;then
  fail CLOSEDROOFCHECK017 "OBSERVATORY ROOF CLOSED is reported with CHECK_FOR_CLOSED_ROOF=no"
 fi
 if grep -q 'Closed roof check of the new images' transient_report/index.html "$WORK_DIR/factory_checkoff.log" ;then
  fail CLOSEDROOFCHECK018 "the closed-roof check ran with CHECK_FOR_CLOSED_ROOF=no"
 fi
fi
if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
 show_run_diagnostics checkoff
fi

if [ -n "$FAILED_CODES" ];then
 echo "Failed checks:$FAILED_CODES"
 exit 1
fi
echo "All checks of the closed-roof check passed"
exit 0
