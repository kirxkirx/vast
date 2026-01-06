#!/usr/bin/env bash

#
# This script tests util/transients/fastplot.sh
# Run after util/transients/transient_factory_test31.sh has completed.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# A more portable realpath wrapper
function vastrealpath {
  REALPATH=`readlink -f "$1" 2>/dev/null`
  if [ $? -ne 0 ];then
   REALPATH=`greadlink -f "$1" 2>/dev/null`
   if [ $? -ne 0 ];then
    REALPATH=`realpath "$1" 2>/dev/null`
    if [ $? -ne 0 ];then
     REALPATH=`grealpath "$1" 2>/dev/null`
     if [ $? -ne 0 ];then
      OURPWD=$PWD
      cd "$(dirname "$1")" || exit 1
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit 1
     fi
    fi
   fi
  fi
  echo "$REALPATH"
}

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

get_vast_path_ends_with_slash_from_this_script_name() {
 VAST_PATH=$(vastrealpath $0)
 VAST_PATH=$(dirname "$VAST_PATH")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "util")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "lib")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "examples")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "transients")
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")
 LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
 if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
  VAST_PATH="$VAST_PATH/"
 fi
 echo "$VAST_PATH"
}

VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")

TEST_PASSED=0
TEST_FAILED=1

cd "$VAST_PATH" || exit $TEST_FAILED

# Check if transient_factory_test31.sh has been run
if [ ! -s transient_report/index.html ];then
 echo "ERROR: transient_report/index.html does not exist or is empty."
 echo "Please run util/transients/transient_factory_test31.sh first."
 exit $TEST_FAILED
fi

# Extract the first transient name from the report
FIRST_TRANSIENT=$(grep -o "printCandidateNameWithAbsLink('[^']*')" transient_report/index.html | head -n1 | sed "s/printCandidateNameWithAbsLink('//;s/')//")

if [ -z "$FIRST_TRANSIENT" ];then
 echo "ERROR: Cannot find any transient in transient_report/index.html"
 exit $TEST_FAILED
fi

echo "Found transient: $FIRST_TRANSIENT"

# Construct file:// URL
TRANSIENT_REPORT_FULL_PATH=$(vastrealpath "transient_report/index.html")
TRANSIENT_URL="file://$TRANSIENT_REPORT_FULL_PATH#$FIRST_TRANSIENT"
echo "Testing with URL: $TRANSIENT_URL"

# Run fastplot.sh
echo "Running fastplot.sh..."
util/transients/fastplot.sh "$TRANSIENT_URL"
FASTPLOT_EXIT_CODE=$?

if [ $FASTPLOT_EXIT_CODE -ne 0 ];then
 echo "ERROR: fastplot.sh exited with code $FASTPLOT_EXIT_CODE"
 exit $TEST_FAILED
fi

# Find the output directory (use -d to only match directories, not tar.bz2 archives)
OUTPUT_DIR=$(ls -dt -d fastplot__*__*/ 2>/dev/null | head -n1)
# Remove trailing slash
OUTPUT_DIR="${OUTPUT_DIR%/}"

if [ -z "$OUTPUT_DIR" ];then
 echo "ERROR: Cannot find fastplot output directory (fastplot__*__*)"
 exit $TEST_FAILED
fi

echo "Found output directory: $OUTPUT_DIR"

# Verify the directory structure
for SUBDIR in reference_platesolved_FITS new_platesolved_FITS resampled_FITS finder_charts_PNG animation_GIF ;do
 if [ ! -d "$OUTPUT_DIR/$SUBDIR" ];then
  echo "ERROR: Expected subdirectory $OUTPUT_DIR/$SUBDIR does not exist"
  rm -rf "$OUTPUT_DIR" "$OUTPUT_DIR.tar.bz2"
  exit $TEST_FAILED
 fi
done

# Check for required files
for REQUIRED_FILE in ds9.reg readme.txt ;do
 if [ ! -f "$OUTPUT_DIR/$REQUIRED_FILE" ];then
  echo "ERROR: $OUTPUT_DIR/$REQUIRED_FILE does not exist"
  rm -rf "$OUTPUT_DIR" "$OUTPUT_DIR.tar.bz2"
  exit $TEST_FAILED
 fi
done

# Check for PNG files
PNG_COUNT=$(ls "$OUTPUT_DIR/finder_charts_PNG"/*.png 2>/dev/null | wc -l)
if [ "$PNG_COUNT" -lt 1 ];then
 echo "ERROR: No PNG files found in finder_charts_PNG"
 rm -rf "$OUTPUT_DIR" "$OUTPUT_DIR.tar.bz2"
 exit $TEST_FAILED
fi
echo "OK: Found $PNG_COUNT PNG files"

# Check for GIF files
GIF_COUNT=$(ls "$OUTPUT_DIR/animation_GIF"/*.gif 2>/dev/null | wc -l)
if [ "$GIF_COUNT" -lt 1 ];then
 echo "ERROR: No GIF files found in animation_GIF"
 rm -rf "$OUTPUT_DIR" "$OUTPUT_DIR.tar.bz2"
 exit $TEST_FAILED
fi
echo "OK: Found $GIF_COUNT GIF files"

# Check for archive
if [ ! -f "$OUTPUT_DIR.tar.bz2" ];then
 echo "ERROR: Archive $OUTPUT_DIR.tar.bz2 does not exist"
 rm -rf "$OUTPUT_DIR"
 exit $TEST_FAILED
fi
echo "OK: Archive exists"

# Check compressed FITS handling - filenames should not have _fz_ in them
if ls "$OUTPUT_DIR/finder_charts_PNG" | grep -q '_fz_' ;then
 echo "ERROR: Found '_fz_' in finder chart filenames"
 rm -rf "$OUTPUT_DIR" "$OUTPUT_DIR.tar.bz2"
 exit $TEST_FAILED
fi

if ls "$OUTPUT_DIR/animation_GIF" | grep -q '_fz_' ;then
 echo "ERROR: Found '_fz_' in animation GIF filenames"
 rm -rf "$OUTPUT_DIR" "$OUTPUT_DIR.tar.bz2"
 exit $TEST_FAILED
fi

echo ""
echo "TEST PASSED: fastplot.sh works correctly"

# Cleanup
echo "Cleaning up..."
rm -rf "$OUTPUT_DIR" "$OUTPUT_DIR.tar.bz2"
echo "Done."

exit $TEST_PASSED
