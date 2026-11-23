#!/usr/bin/env bash
#
# Test of the bright-star check of the NMW-TexasTech transient search.
#
# Both new images of a field can be lost to clouds at the same time, with similar backgrounds
# and enough peaks to get past the closed-roof check. The transient factory
# (util/transients/transient_factory_test31.sh) therefore asks VaST, in its pass with the
# bright-star SExtractor settings, to compare the number of stars on the new images with the
# number on the reference images of the field:
#   VAST_MIN_NEW_IMAGE_BRIGHT_STAR_PERCENT  the lowest acceptable percentage (the factory: 10)
#   VAST_BRIGHT_STAR_CHECK_IMAGE_MASK       one digit per new image, 1 = check this image (the
#                                           factory: 1 for an image taken with its center at
#                                           least 20 degrees above the horizon, CENTALT)
# VaST (check_bright_star_counts() in src/vast.c) writes a "Bright-star check: ..." line for
# each image it checked and, if an image has too few stars, stops before matching the stars with
#   ERROR: too few bright stars on second-epoch image ...
# The factory copies these lines to the report and skips the passes with fainter stars.
#
# The test data are the 1024x1024 crops of real NMW-TexasTech frames of the dataset
# NMW-TexasTech__closed_roof_test (see its README.txt): two reference images of the field
# Pup-02-Q2b1x1 with about 500 stars each, open-sky frames of other fields (Lac-01: more stars
# than the references, And-05: about half as many), a frame taken while the roof was closing
# (Com-01: a few percent) and two frames taken with the roof closed (no stars at all).
#
# VaST is run on four images as the factory runs it:
#  - open-sky new images pass, and VaST goes on to match the stars;
#  - a new image that has lost nearly all stars is rejected, the other one is not;
#  - new images without any star are rejected. SExtractor finds nothing to measure the seeing
#    from on such an image, so VaST never makes its star catalog: the check has to take the
#    missing catalog for "no stars", not for "cannot tell";
#  - the limit is the percentage given in the variable;
#  - each digit of the mask belongs to its own image;
#  - no check without the variables, with the mask 00 or with values that make no sense;
#  - no verdict when the exposure times differ or a reference image has no stars.
# The transient factory is run on fresh copies of the two closed-roof frames, with the
# closed-roof check switched off so that they reach VaST:
#  - both images are checked (their CENTALT is 22 and 23 degrees), the ERROR lines are in the
#    report, the pass with fainter stars does not start and the run takes seconds;
#  - with CENTALT of the first image changed to 15 degrees only the second image is checked.
# The checks look for the stable parts of the messages, not for their exact wording.
#
# Usage: util/examples/test_bright_star_check.sh
# The script works in the VaST directory it belongs to. The test data are expected in
# ../NMW-TexasTech__closed_roof_test (next to the VaST directory) and are downloaded if they are
# not there. BRIGHT_STAR_CHECK_TEST_SKIP_FACTORY_RUNS=yes leaves out the runs of the transient
# factory (util/examples/test_vast.sh sets it on GitHub Actions, like it leaves out the other
# NMW-TexasTech transient factory tests there). The script prints "FAILED: CODE description"
# for every failed check and exits with code 1 if any check failed, 0 if all of them passed.
# At the end it puts back bad_region.lst, neverexclude_list.txt and default.sex of the VaST
# directory and removes the files of its VaST runs with util/clean_data.sh.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# A manual TELESCOP override would change how the images are handled (see util/examples/test_vast.sh)
unset TELESCOP
# The settings under test come from the runs below, never from the environment of this script
unset CAMERA_SETTINGS CHECK_FOR_CLOSED_ROOF DARK_FRAMES_DIR_OR_FILE FLAT_FIELD_DIR_OR_FILE REFERENCE_IMAGES
unset VAST_MIN_NEW_IMAGE_BRIGHT_STAR_PERCENT VAST_BRIGHT_STAR_CHECK_IMAGE_MASK

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
BRIGHT_STAR_SEXTRACTOR_CONFIG="default.sex.telephoto_lens_onlybrightstars_v1"
FAINT_STAR_SEXTRACTOR_CONFIG="default.sex.telephoto_lens_vSTL"
REFERENCE_1_NAME="Pup-02-Q2b1x1_2026-03-20_21-03-09_20.00sec_-15.00C_LIGHT_0013.fits"
REFERENCE_2_NAME="Pup-02-Q2b1x1_2026-04-05_21-28-35_20.00sec_-4.90C_LIGHTs_0000.fits"
OPEN_DENSE_NAME="Lac-01-Q2b1x1_2026-11-12_19-22-04_20.00sec_-0.00C_LIGHT_0042.fits"
OPEN_MODERATE_NAME="And-05-Q2b1x1_2026-11-11_23-37-44_20.00sec_-0.00C_LIGHT_0282.fits"
PARTLY_DARK_NAME="Com-01-Q2b1x1_2026-11-13_05-03-55_20.00sec_0.00C_LIGHT_0517.fits"
STARLESS_1_NAME="Pup-02-Q2b1x1_2026-11-12_02-48-08_20.00sec_-0.00C_LIGHT_0326.fits"
STARLESS_2_NAME="Pup-02-Q2b1x1_2026-11-12_02-56-16_20.00sec_-0.00C_LIGHT_0327.fits"
# A field stopped by the check is done in seconds; without the check the starless images go
# through both SExtractor passes and a blind plate solution, a minute or more
MAX_FACTORY_RUN_TIME_SEC=120

if [ ! -x ./vast ] || [ ! -x util/modhead ] || [ ! -x util/transients/transient_factory_test31.sh ];then
 fail BRIGHTSTARCHECK_TOOL_NOT_FOUND "VaST is not built (run make in the VaST directory)"
 exit 1
fi
if [ ! -f "$BRIGHT_STAR_SEXTRACTOR_CONFIG" ];then
 fail BRIGHTSTARCHECK_TOOL_NOT_FOUND "no $BRIGHT_STAR_SEXTRACTOR_CONFIG in the VaST directory"
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
 fail BRIGHTSTARCHECK_TEST_NOT_PERFORMED "the test data $TEST_DATA_DIR are not available"
 exit 1
fi
# Absolute paths: the transient factory hands them on to other scripts
TEST_DATA_DIR=$(cd "$TEST_DATA_DIR" && pwd)
REFERENCE_IMAGES_DIR="$TEST_DATA_DIR/reference_images"
CAMERA_DARK_FRAMES_DIR="$TEST_DATA_DIR/$CAMERA/darks"
REFERENCE_1="$REFERENCE_IMAGES_DIR/$REFERENCE_1_NAME"
REFERENCE_2="$REFERENCE_IMAGES_DIR/$REFERENCE_2_NAME"
OPEN_DENSE="$TEST_DATA_DIR/$CAMERA/open/$OPEN_DENSE_NAME"
OPEN_MODERATE="$TEST_DATA_DIR/$CAMERA/open/$OPEN_MODERATE_NAME"
PARTLY_DARK="$TEST_DATA_DIR/$CAMERA/partly_dark/$PARTLY_DARK_NAME"
STARLESS_1="$TEST_DATA_DIR/$CAMERA/closed/$STARLESS_1_NAME"
STARLESS_2="$TEST_DATA_DIR/$CAMERA/closed/$STARLESS_2_NAME"
if [ "$(count_files "$REFERENCE_1" "$REFERENCE_2" "$OPEN_DENSE" "$OPEN_MODERATE" "$PARTLY_DARK" "$STARLESS_1" "$STARLESS_2")" != "7" ] || [ "$(count_files "$CAMERA_DARK_FRAMES_DIR"/*)" != "1" ] || [ "$(count_files "$REFERENCE_IMAGES_DIR"/"$FIELD"_*.fits)" != "2" ];then
 fail BRIGHTSTARCHECK000 "the test data in $TEST_DATA_DIR are incomplete"
 exit 1
fi

# The private work directory. The path of the new images given to the transient factory has to
# contain the camera name (the factory takes CAMERA_SETTINGS from it) and the word 'test' (then
# the factory does not update the exclusion list).
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vast_bright_star_check_test.XXXXXX" 2>/dev/null)
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ];then
 fail BRIGHTSTARCHECK000 "cannot create a work directory"
 exit 1
fi
NEW_IMAGES_DIR="$WORK_DIR/$CAMERA/starless"
# No flat fielding: the transient factory would look for a flat field in the NMW calibration
# directory of this machine (if there is one)
EMPTY_FLAT_FIELDS_DIR="$WORK_DIR/empty_flat_fields_dir"
SAVED_FILES_DIR="$WORK_DIR/saved_files_of_the_vast_directory"
if ! mkdir -p "$EMPTY_FLAT_FIELDS_DIR" "$SAVED_FILES_DIR" ;then
 fail BRIGHTSTARCHECK000 "cannot create directories in $WORK_DIR"
 rm -rf "$WORK_DIR"
 exit 1
fi

# The runs below replace these files of the VaST directory: put back the files that were there before
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

# Copies with another exposure time in the header: a new image and a reference image
OTHER_EXPOSURE_NEW_1="$WORK_DIR/other_exposure_$OPEN_DENSE_NAME"
OTHER_EXPOSURE_NEW_2="$WORK_DIR/other_exposure_$STARLESS_2_NAME"
OTHER_EXPOSURE_REFERENCE="$WORK_DIR/other_exposure_$REFERENCE_2_NAME"
if ! cp "$OPEN_DENSE" "$OTHER_EXPOSURE_NEW_1" || ! cp "$STARLESS_2" "$OTHER_EXPOSURE_NEW_2" || ! cp "$REFERENCE_2" "$OTHER_EXPOSURE_REFERENCE" ;then
 fail BRIGHTSTARCHECK000 "cannot copy the test images to $WORK_DIR"
 exit 1
fi
for IMAGE_TO_CHANGE in "$OTHER_EXPOSURE_NEW_1" "$OTHER_EXPOSURE_NEW_2" "$OTHER_EXPOSURE_REFERENCE" ;do
 util/modhead "$IMAGE_TO_CHANGE" EXPTIME 10.0 > /dev/null 2>&1
 if ! util/listhead "$IMAGE_TO_CHANGE" 2>/dev/null | grep -q '^EXPTIME = *10\.0' ;then
  fail BRIGHTSTARCHECK000 "cannot change EXPTIME of $IMAGE_TO_CHANGE"
  exit 1
 fi
done

##### VaST runs #####

# Run VaST on two reference and two new images the way the transient factory runs its
# bright-star pass for the NMW-TexasTech cameras
# $1 - a name of the run for its log file $WORK_DIR/vast_<name>.log
# $2 - VAST_MIN_NEW_IMAGE_BRIGHT_STAR_PERCENT, or 'unset' to run without the two variables
# $3 - VAST_BRIGHT_STAR_CHECK_IMAGE_MASK
# $4 $5 - the reference images, $6 $7 - the new images
# Sets VAST_EXIT_CODE
run_vast() {
 RUN_NAME="$1"
 RUN_MINIMUM="$2"
 RUN_MASK="$3"
 shift 3
 cp "$BRIGHT_STAR_SEXTRACTOR_CONFIG" default.sex
 (
  if [ "$RUN_MINIMUM" = "unset" ];then
   unset VAST_MIN_NEW_IMAGE_BRIGHT_STAR_PERCENT VAST_BRIGHT_STAR_CHECK_IMAGE_MASK
  else
   export VAST_MIN_NEW_IMAGE_BRIGHT_STAR_PERCENT="$RUN_MINIMUM" VAST_BRIGHT_STAR_CHECK_IMAGE_MASK="$RUN_MASK"
  fi
  ./vast --noflagimage --starmatchraius 5 --matchstarnumber 500 --selectbestaperture --sysrem 0 --type 4 --maxsextractorflag 99 --UTC --nofind --nojdkeyword "$@" > "$WORK_DIR/vast_$RUN_NAME.log" 2>&1
 )
 VAST_EXIT_CODE=$?
}

# What VaST said about the check in the run $1
check_lines() {
 grep '^Bright-star check: ' "$WORK_DIR/vast_$1.log" 2>/dev/null
}
# The line with the number of stars of the image $2 (its file name) in the run $1
count_line_of_image() {
 check_lines "$1" | grep ' stars (' | grep -F "$2 has "
}
# The percentage in that line, or nothing if there is no such line
percent_of_image() {
 count_line_of_image "$1" "$2" | head -n 1 | sed -e 's/.* stars (//' -e 's/% of .*//'
}
# The ERROR lines of the check in the run $1 (all of them, or those about the image $2)
error_lines() {
 if [ -n "$2" ];then
  grep '^ERROR: too few bright stars on second-epoch image ' "$WORK_DIR/vast_$1.log" 2>/dev/null | grep -F "$2 ("
 else
  grep '^ERROR: too few bright stars on second-epoch image ' "$WORK_DIR/vast_$1.log" 2>/dev/null
 fi
}
# Return 0 if VaST went on to match the stars in the run $1
matching_started() {
 grep -q 'Matching stars between images' "$WORK_DIR/vast_$1.log" 2>/dev/null
}
# Return 0 if $1 is a number and $1 $2 $3 holds, for example: number_is "$PERCENT" '>=' 10
number_is() {
 awk -v x="$1" -v op="$2" -v y="$3" 'BEGIN {
  if (x !~ /^[0-9]+([.][0-9]*)?$/) exit 1
  if (op == ">=") exit !(x + 0 >= y + 0)
  if (op == "<") exit !(x + 0 < y + 0)
  exit 1
 }'
}
# Print what VaST said about the check in the run $1
show_vast_run() {
 echo " the bright-star check lines of the VaST run $1 (VaST exit code $VAST_EXIT_CODE):"
 { check_lines "$1" ; error_lines "$1" ; } | sed 's/^/  /'
}

echo "VaST run with open-sky new images"
run_vast open 10 11 "$REFERENCE_1" "$REFERENCE_2" "$OPEN_DENSE" "$OPEN_MODERATE"
FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
REFERENCE_STAR_COUNT=$(count_line_of_image open "$OPEN_DENSE_NAME" | head -n 1 | sed -e 's/.*% of //' -e 's/ on the shallower reference.*//')
if ! number_is "$REFERENCE_STAR_COUNT" '>=' 100 ;then
 fail BRIGHTSTARCHECK001 "the check does not report a few hundred stars on the reference images: '$REFERENCE_STAR_COUNT'"
fi
if ! number_is "$(percent_of_image open "$OPEN_DENSE_NAME")" '>=' 10 || ! number_is "$(percent_of_image open "$OPEN_MODERATE_NAME")" '>=' 10 ;then
 fail BRIGHTSTARCHECK002 "no star count of at least 10 percent for both open-sky images"
fi
if [ -n "$(error_lines open)" ];then
 fail BRIGHTSTARCHECK003 "an open-sky image is rejected"
fi
if ! matching_started open ;then
 fail BRIGHTSTARCHECK004 "VaST did not go on to match the stars of the open-sky images"
fi
if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
 show_vast_run open
fi

echo "VaST run with a new image that lost nearly all stars"
run_vast partly_dark 10 11 "$REFERENCE_1" "$REFERENCE_2" "$OPEN_DENSE" "$PARTLY_DARK"
FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
if [ -z "$(error_lines partly_dark "$PARTLY_DARK_NAME")" ] || ! number_is "$(percent_of_image partly_dark "$PARTLY_DARK_NAME")" '<' 10 ;then
 fail BRIGHTSTARCHECK005 "the image that lost nearly all stars is not rejected"
fi
if [ -n "$(error_lines partly_dark "$OPEN_DENSE_NAME")" ];then
 fail BRIGHTSTARCHECK006 "the open-sky image is rejected together with the bad one"
fi
if [ $VAST_EXIT_CODE -eq 0 ] || matching_started partly_dark ;then
 fail BRIGHTSTARCHECK007 "VaST did not stop before matching the stars (exit code $VAST_EXIT_CODE)"
fi
if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
 show_vast_run partly_dark
fi

echo "VaST run with new images without stars"
run_vast starless 10 11 "$REFERENCE_1" "$REFERENCE_2" "$STARLESS_1" "$STARLESS_2"
FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
if [ -z "$(error_lines starless "$STARLESS_1_NAME")" ] || [ -z "$(error_lines starless "$STARLESS_2_NAME")" ];then
 fail BRIGHTSTARCHECK008 "the images without stars are not rejected (a missing star catalog taken for 'cannot tell'?)"
fi
if [ $VAST_EXIT_CODE -eq 0 ] || matching_started starless ;then
 fail BRIGHTSTARCHECK009 "VaST did not stop before matching the stars (exit code $VAST_EXIT_CODE)"
fi
if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
 show_vast_run starless
fi

echo "VaST run with open-sky new images and a minimum of 90 percent"
run_vast minimum90 90 11 "$REFERENCE_1" "$REFERENCE_2" "$OPEN_DENSE" "$OPEN_MODERATE"
FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
if [ -z "$(error_lines minimum90 "$OPEN_MODERATE_NAME")" ] || [ -n "$(error_lines minimum90 "$OPEN_DENSE_NAME")" ];then
 fail BRIGHTSTARCHECK010 "with a minimum of 90 percent the image with half the stars has to be rejected and the one with more stars than the references kept"
fi
if ! count_line_of_image minimum90 "$OPEN_MODERATE_NAME" | grep -q 'minimum 90\.0%' ;then
 fail BRIGHTSTARCHECK011 "the star count line does not show the minimum of 90 percent"
fi
if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
 show_vast_run minimum90
fi

echo "VaST runs with one image to check: a starless first and an open-sky second new image"
run_vast second_only 10 01 "$REFERENCE_1" "$REFERENCE_2" "$STARLESS_1" "$OPEN_DENSE"
FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
if [ "$(check_lines second_only | grep -c .)" != "1" ] || [ -z "$(count_line_of_image second_only "$OPEN_DENSE_NAME")" ] || [ -n "$(error_lines second_only)" ] || ! matching_started second_only ;then
 fail BRIGHTSTARCHECK012 "with the mask 01 only the second new image has to be checked, and it is an open-sky one"
fi
if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
 show_vast_run second_only
fi
run_vast first_only 10 10 "$REFERENCE_1" "$REFERENCE_2" "$STARLESS_1" "$OPEN_DENSE"
FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
if [ -z "$(error_lines first_only "$STARLESS_1_NAME")" ] || check_lines first_only | grep -q -F "$OPEN_DENSE_NAME" || [ $VAST_EXIT_CODE -eq 0 ] ;then
 fail BRIGHTSTARCHECK013 "with the mask 10 only the first new image has to be checked, and it has no stars"
fi
if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
 show_vast_run first_only
fi

echo "VaST runs that must not check anything: no variables, the mask 00, values that make no sense"
# name:minimum:mask
for SETTINGS_WITHOUT_CHECK in no_variables:unset:unset mask_00:10:00 minimum_0:0:11 minimum_101:101:11 minimum_10x:10x:11 no_minimum::11 mask_1:10:1 mask_111:10:111 ;do
 RUN_NAME_WITHOUT_CHECK="${SETTINGS_WITHOUT_CHECK%%:*}"
 SETTINGS_WITHOUT_CHECK="${SETTINGS_WITHOUT_CHECK#*:}"
 run_vast "$RUN_NAME_WITHOUT_CHECK" "${SETTINGS_WITHOUT_CHECK%%:*}" "${SETTINGS_WITHOUT_CHECK#*:}" "$REFERENCE_1" "$REFERENCE_2" "$STARLESS_1" "$STARLESS_2"
 if [ -n "$(check_lines "$RUN_NAME_WITHOUT_CHECK")" ] || [ -n "$(error_lines "$RUN_NAME_WITHOUT_CHECK")" ] || ! matching_started "$RUN_NAME_WITHOUT_CHECK" ;then
  fail "BRIGHTSTARCHECK014_$RUN_NAME_WITHOUT_CHECK" "the check ran (minimum '${SETTINGS_WITHOUT_CHECK%%:*}', mask '${SETTINGS_WITHOUT_CHECK#*:}')"
  show_vast_run "$RUN_NAME_WITHOUT_CHECK"
 fi
done

echo "VaST runs without a verdict: other exposure times, a reference image without stars"
run_vast new_images_other_exposure 10 11 "$REFERENCE_1" "$REFERENCE_2" "$OTHER_EXPOSURE_NEW_1" "$OTHER_EXPOSURE_NEW_2"
if [ "$(check_lines new_images_other_exposure | grep -c 'exposure time differs from the references')" != "2" ] || [ -n "$(error_lines new_images_other_exposure)" ] || ! matching_started new_images_other_exposure ;then
 fail BRIGHTSTARCHECK015 "new images with another exposure time are not left without a verdict"
 show_vast_run new_images_other_exposure
fi
run_vast reference_other_exposure 10 11 "$REFERENCE_1" "$OTHER_EXPOSURE_REFERENCE" "$STARLESS_1" "$STARLESS_2"
if ! check_lines reference_other_exposure | grep -q 'the references need matching exposure times' || [ -n "$(error_lines reference_other_exposure)" ] || ! matching_started reference_other_exposure ;then
 fail BRIGHTSTARCHECK016 "reference images with different exposure times do not leave the new images without a verdict"
 show_vast_run reference_other_exposure
fi
# (open-sky new images: should SExtractor find a few spurious sources on the closed-roof frame
# used as a reference here, the check may compare with them, but it must not reject anything)
run_vast starless_reference 10 11 "$REFERENCE_1" "$STARLESS_1" "$OPEN_DENSE" "$OPEN_MODERATE"
if [ -z "$(check_lines starless_reference)" ] || [ -n "$(error_lines starless_reference)" ] || ! matching_started starless_reference ;then
 fail BRIGHTSTARCHECK017 "a reference image without stars made the check reject the new images or say nothing"
 show_vast_run starless_reference
fi

##### Transient factory runs #####

# Run the transient factory on the images in $NEW_IMAGES_DIR with the closed-roof check
# switched off, so that the starless images reach VaST
# $1 - a name of the run for its log file $WORK_DIR/factory_<name>.log
# Sets FACTORY_EXIT_CODE and RUN_TIME_SEC
run_factory() {
 util/clean_data.sh > /dev/null 2>&1
 rm -f transient_report/index.html
 RUN_START_UNIXSEC=$(date +%s)
 # GAIA_DR2_CLIENT=none: the known-star check of the candidates is not needed here, and with an
 # online Gaia client the transient factory would first probe the VizieR mirrors (that takes
 # minutes when they do not answer)
 env GAIA_DR2_CLIENT=none CHECK_FOR_CLOSED_ROOF=no REFERENCE_IMAGES="$REFERENCE_IMAGES_DIR" DARK_FRAMES_DIR_OR_FILE="$CAMERA_DARK_FRAMES_DIR" FLAT_FIELD_DIR_OR_FILE="$EMPTY_FLAT_FIELDS_DIR" util/transients/transient_factory_test31.sh "$NEW_IMAGES_DIR" > "$WORK_DIR/factory_$1.log" 2>&1
 FACTORY_EXIT_CODE=$?
 RUN_TIME_SEC=$(( $(date +%s) - RUN_START_UNIXSEC ))
 echo " the transient factory exited with code $FACTORY_EXIT_CODE after $RUN_TIME_SEC s"
}

# Put fresh copies of the two closed-roof images into $NEW_IMAGES_DIR
copy_new_images_for_factory() {
 rm -rf "${WORK_DIR:?}/$CAMERA"
 if ! mkdir -p "$NEW_IMAGES_DIR" || ! cp "$STARLESS_1" "$STARLESS_2" "$NEW_IMAGES_DIR"/ ;then
  fail BRIGHTSTARCHECK000 "cannot copy the test images to $NEW_IMAGES_DIR"
  exit 1
 fi
}

# The lines of the report about the check: all of them, or those about the image taken at $1
# (the time in its file name; the factory may give the image a prefix when it calibrates it)
report_check_lines() {
 grep 'Bright-star check: ' transient_report/index.html 2>/dev/null | grep -F "$1"
}
report_error_lines() {
 grep 'ERROR: too few bright stars on second-epoch image ' transient_report/index.html 2>/dev/null | grep -F "$1"
}

# Print what may help to find out why a check of the run $1 failed
show_factory_run() {
 echo " ERROR, WARNING and bright-star check lines of transient_report/index.html:"
 grep -e 'ERROR' -e 'WARNING' -e 'Bright-star check' -e 'Field altitude during imaging' transient_report/index.html 2>/dev/null | head -n 16 | sed 's/^/  /'
 echo " the last lines of the output of the transient factory:"
 tail -n 15 "$WORK_DIR/factory_$1.log" 2>/dev/null | sed 's/^/  /'
}

STARLESS_1_TIME="2026-11-12_02-48-08"
STARLESS_2_TIME="2026-11-12_02-56-16"

if [ "$BRIGHT_STAR_CHECK_TEST_SKIP_FACTORY_RUNS" = "yes" ];then
 echo "The transient factory runs are left out (BRIGHT_STAR_CHECK_TEST_SKIP_FACTORY_RUNS=yes)"
else
 # Every run of the transient factory starts by bringing the offline catalogs up to date: do it
 # first, so that downloading a catalog does not count against the run time limit below
 lib/update_offline_catalogs.sh all > "$WORK_DIR/update_offline_catalogs.log" 2>&1

 echo "Transient factory run on two new images without stars, the closed-roof check switched off"
 FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
 copy_new_images_for_factory
 run_factory starless
 if [ $FACTORY_EXIT_CODE -ne 0 ] || [ ! -s transient_report/index.html ] || ! grep -q 'Processing complete!' transient_report/index.html ;then
  fail BRIGHTSTARCHECK101 "no complete transient_report/index.html (the transient factory exited with code $FACTORY_EXIT_CODE)"
 else
  # Both images were taken more than 20 degrees above the horizon: both are checked
  if [ -z "$(report_check_lines "$STARLESS_1_TIME")" ] || [ -z "$(report_check_lines "$STARLESS_2_TIME")" ];then
   fail BRIGHTSTARCHECK102 "the report has no 'Bright-star check:' line for each of the two new images"
  fi
  if [ -z "$(report_error_lines "$STARLESS_1_TIME")" ] || [ -z "$(report_error_lines "$STARLESS_2_TIME")" ];then
   fail BRIGHTSTARCHECK103 "the report has no 'ERROR: too few bright stars' line for each of the two new images"
  fi
  if ! grep -q -F -e "------ $BRIGHT_STAR_SEXTRACTOR_CONFIG ------" transient_report/index.html ;then
   fail BRIGHTSTARCHECK104 "the report does not show the pass with $BRIGHT_STAR_SEXTRACTOR_CONFIG"
  fi
  if grep -q -F -e "------ $FAINT_STAR_SEXTRACTOR_CONFIG ------" transient_report/index.html ;then
   fail BRIGHTSTARCHECK105 "the pass with $FAINT_STAR_SEXTRACTOR_CONFIG started after the field was rejected"
  fi
  if grep -q 'less than 4 images processed' transient_report/index.html ;then
   fail BRIGHTSTARCHECK106 "the images went through the VaST run (less than 4 images processed) instead of stopping at the bright-star check"
  fi
 fi
 if [ $RUN_TIME_SEC -ge $MAX_FACTORY_RUN_TIME_SEC ];then
  fail BRIGHTSTARCHECK107 "the run took $RUN_TIME_SEC s - the field did not stop at the bright-star check"
 fi
 if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
  show_factory_run starless
 fi

 echo "Transient factory run with the first of the two images 15 degrees above the horizon"
 FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
 copy_new_images_for_factory
 util/modhead "$NEW_IMAGES_DIR/$STARLESS_1_NAME" CENTALT 15.0 > /dev/null 2>&1
 if ! util/listhead "$NEW_IMAGES_DIR/$STARLESS_1_NAME" 2>/dev/null | grep -q '^CENTALT = *15\.0' ;then
  fail BRIGHTSTARCHECK000 "cannot change CENTALT of $NEW_IMAGES_DIR/$STARLESS_1_NAME"
 else
  run_factory low_first_image
  if [ $FACTORY_EXIT_CODE -ne 0 ] || [ ! -s transient_report/index.html ] || ! grep -q 'Processing complete!' transient_report/index.html ;then
   fail BRIGHTSTARCHECK111 "no complete transient_report/index.html (the transient factory exited with code $FACTORY_EXIT_CODE)"
  else
   if [ -n "$(report_check_lines "$STARLESS_1_TIME")" ] || [ -n "$(report_error_lines "$STARLESS_1_TIME")" ];then
    fail BRIGHTSTARCHECK112 "the image taken 15 degrees above the horizon was checked"
   fi
   if [ -z "$(report_check_lines "$STARLESS_2_TIME")" ] || [ -z "$(report_error_lines "$STARLESS_2_TIME")" ];then
    fail BRIGHTSTARCHECK113 "the image taken 23 degrees above the horizon was not checked and rejected"
   fi
   if grep -q -F -e "------ $FAINT_STAR_SEXTRACTOR_CONFIG ------" transient_report/index.html ;then
    fail BRIGHTSTARCHECK114 "the pass with $FAINT_STAR_SEXTRACTOR_CONFIG started after the field was rejected"
   fi
  fi
  if [ $RUN_TIME_SEC -ge $MAX_FACTORY_RUN_TIME_SEC ];then
   fail BRIGHTSTARCHECK115 "the run took $RUN_TIME_SEC s - the field did not stop at the bright-star check"
  fi
  if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
   show_factory_run low_first_image
  fi
 fi
fi

if [ -n "$FAILED_CODES" ];then
 echo "Failed checks:$FAILED_CODES"
 exit 1
fi
echo "All checks of the bright-star check passed"
exit 0
