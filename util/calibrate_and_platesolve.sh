#!/usr/bin/env bash

#################################
# This script takes an uncalibrated CCD image, applies dark subtraction
# and flat-fielding using the same calibration strategy as
# util/transients/transient_factory_test31.sh, then plate-solves the result.
#
# Usage: util/calibrate_and_platesolve.sh /path/to/uncalibrated_image.fits
#
# Environment variables that can be set before running:
#   DARK_FRAMES_DIR_OR_FILE  - directory of dark frames (best match is picked) or a single dark frame file
#   FLAT_FIELD_DIR_OR_FILE   - directory of flat fields (best match is picked) or a single flat field file
#   CAMERA_SETTINGS          - camera configuration name (auto-detected if not set)
#
# The calibrated image will be written to the current working directory.
# Output file naming:
#   d_<original_name>     - dark-subtracted only (if flat field not available)
#   fd_<original_name>    - flat-fielded (and dark-subtracted)
#   wcs_fd_<original_name> - plate-solved calibrated image
#################################

# shellcheck disable=SC2012,SC2086,SC2181

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# A more portable realpath wrapper
function vastrealpath {
  REALPATH=$(readlink -f "$1" 2>/dev/null)
  if [ $? -ne 0 ];then
   REALPATH=$(greadlink -f "$1" 2>/dev/null)
   if [ $? -ne 0 ];then
    REALPATH=$(realpath "$1" 2>/dev/null)
    if [ $? -ne 0 ];then
     REALPATH=$(grealpath "$1" 2>/dev/null)
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

# Function to remove the last occurrence of a directory from a path
remove_last_occurrence() {
    echo "$1" | awk -F/ -v dir="$2" '{
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
 VAST_PATH=$(vastrealpath "$0")
 VAST_PATH=$(dirname "$VAST_PATH")

 # Remove last occurrences of util, lib, examples
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "util")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "lib")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "examples")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "transients")

 # Make sure no '//' are left in the path
 VAST_PATH="${VAST_PATH/'//'/'/'}"
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

VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
export VAST_PATH

#################################
# Check command line arguments
if [ -z "$1" ];then
 echo "Usage: $0 /path/to/uncalibrated_image.fits"
 echo ""
 echo "This script calibrates (dark subtract + flat field) an image and plate-solves it."
 echo ""
 echo "Environment variables (optional - will be auto-detected if not set):"
 echo "  DARK_FRAMES_DIR_OR_FILE  - directory of dark frames or a single dark frame file"
 echo "  FLAT_FIELD_DIR_OR_FILE   - directory of flat fields or a single flat field file"
 echo "  CAMERA_SETTINGS          - camera configuration name"
 exit 1
fi

INPUT_IMAGE="$1"

# Check if the input image exists
if [ ! -f "$INPUT_IMAGE" ];then
 echo "ERROR: input image file does not exist: $INPUT_IMAGE"
 exit 1
fi
if [ ! -s "$INPUT_IMAGE" ];then
 echo "ERROR: input image file is empty: $INPUT_IMAGE"
 exit 1
fi

# Get absolute path to input image
INPUT_IMAGE=$(vastrealpath "$INPUT_IMAGE")
INPUT_BASENAME=$(basename "$INPUT_IMAGE")

echo "Input image: $INPUT_IMAGE"

#################################
# Auto-detect camera settings from the input path if not already set
if [ -z "$CAMERA_SETTINGS" ];then
 if [[ "$INPUT_IMAGE" == *"Stas"* ]];then
  export CAMERA_SETTINGS="Stas"
 elif [[ "$INPUT_IMAGE" == *"STL-11000M"* ]] || [[ "$INPUT_IMAGE" == *"NMW-STL"* ]];then
  export CAMERA_SETTINGS="STL-11000M"
 elif [[ "$INPUT_IMAGE" == *"ED80__Black"* ]];then
  export CAMERA_SETTINGS="ED80__Black"
 elif [[ "$INPUT_IMAGE" == *"TTUQ1b1x1"* ]] || [[ "$INPUT_IMAGE" == *"Q1b1x1"* ]];then
  export CAMERA_SETTINGS="TTUQ1b1x1"
 elif [[ "$INPUT_IMAGE" == *"TTUQ2b1x1"* ]] || [[ "$INPUT_IMAGE" == *"Q2b1x1"* ]];then
  export CAMERA_SETTINGS="TTUQ2b1x1"
 fi
fi

if [ -n "$CAMERA_SETTINGS" ];then
 echo "Camera settings: $CAMERA_SETTINGS"
fi

#################################
# Find calibration data directory
for dir in "$HOME/nmw_calibration" \
           "/dataX/cgi-bin/unmw/uploads/nmw_calibration" \
           "/home/apache/nmw_calibration" \
           "/var/www/nmw_calibration"; do
  if [ -d "$dir" ];then
   NMW_CALIBRATION="$dir"
   break
  fi
done

if [ -n "$NMW_CALIBRATION" ] && [ -n "$CAMERA_SETTINGS" ];then
 echo "Calibration data directory: $NMW_CALIBRATION/$CAMERA_SETTINGS"
fi

#################################
# Set DARK_FRAMES_DIR_OR_FILE if not already set
if [ -z "$DARK_FRAMES_DIR_OR_FILE" ];then
 if [ -n "$NMW_CALIBRATION" ] && [ -n "$CAMERA_SETTINGS" ];then
  if [ -d "$NMW_CALIBRATION/$CAMERA_SETTINGS/darks" ];then
   export DARK_FRAMES_DIR_OR_FILE="$NMW_CALIBRATION/$CAMERA_SETTINGS/darks"
  fi
 fi
fi

# Check if we have dark frames (a directory of them, or a single file)
if [ -z "$DARK_FRAMES_DIR_OR_FILE" ];then
 echo "ERROR: DARK_FRAMES_DIR_OR_FILE is not set and could not be auto-detected."
 echo "Please set DARK_FRAMES_DIR_OR_FILE to a directory of dark frames or a single dark frame file."
 exit 1
fi
if [ ! -d "$DARK_FRAMES_DIR_OR_FILE" ] && [ ! -f "$DARK_FRAMES_DIR_OR_FILE" ];then
 echo "ERROR: DARK_FRAMES_DIR_OR_FILE=$DARK_FRAMES_DIR_OR_FILE is neither a directory nor a file"
 exit 1
fi

echo "Dark frames directory or file: $DARK_FRAMES_DIR_OR_FILE"

#################################
# Set FLAT_FIELD_DIR_OR_FILE if not already set
if [ -z "$FLAT_FIELD_DIR_OR_FILE" ];then
 if [ -n "$NMW_CALIBRATION" ] && [ -n "$CAMERA_SETTINGS" ];then
  # Point at the whole flats directory: the best matching flat (same
  # dimensions/FILTER/CAMERA/CAMERAID/TELESCOP, closest in time) will be
  # selected automatically by util/find_best_flat.sh
  FLAT_DIR="$NMW_CALIBRATION/$CAMERA_SETTINGS/flats"
  if [ -d "$FLAT_DIR" ];then
   export FLAT_FIELD_DIR_OR_FILE="$FLAT_DIR"
  fi
 fi
fi

if [ -n "$FLAT_FIELD_DIR_OR_FILE" ];then
 if [ -d "$FLAT_FIELD_DIR_OR_FILE" ] || [ -s "$FLAT_FIELD_DIR_OR_FILE" ];then
  echo "Flat field directory or file: $FLAT_FIELD_DIR_OR_FILE"
 else
  echo "WARNING: FLAT_FIELD_DIR_OR_FILE=$FLAT_FIELD_DIR_OR_FILE does not exist or is empty"
  unset FLAT_FIELD_DIR_OR_FILE
 fi
else
 echo "WARNING: No flat field found. Will perform dark subtraction only."
fi

#################################
# Check if the image was already calibrated
"$VAST_PATH"util/listhead "$INPUT_IMAGE" | grep -q 'Dark frame subtraction'
if [ $? -eq 0 ];then
 echo "WARNING: the dark frame has already been subtracted from the input image."
 echo "The image appears to be already calibrated."
 # Continue anyway to plate-solve it
 OUTPUT_CALIBRATED_IMAGE="$INPUT_IMAGE"
else
 #################################
 # Resolve the dark frame: use the specified file directly, or search the directory
 if [ -f "$DARK_FRAMES_DIR_OR_FILE" ];then
  DARK_FRAME="$DARK_FRAMES_DIR_OR_FILE"
  echo "Using the specified dark frame file: $DARK_FRAME"
 else
  echo "Finding the best matching dark frame..."
  DARK_FRAME=$(DARK_FRAMES_DIR="$DARK_FRAMES_DIR_OR_FILE" "$VAST_PATH"util/find_best_dark.sh "$INPUT_IMAGE")
  if [ $? -ne 0 ];then
   echo "ERROR: cannot find a matching dark frame"
   echo "Make sure the dark frames have matching EXPTIME, SET-TEMP, and image dimensions"
   exit 1
  fi
 fi
 if [ ! -s "$DARK_FRAME" ];then
  echo "ERROR: dark frame file does not exist or is empty: $DARK_FRAME"
  exit 1
 fi
 echo "Selected dark frame: $DARK_FRAME"

 #################################
 # Output goes to current working directory
 OUTPUT_DIRNAME="$PWD"

 # Define output file names
 OUTPUT_DARK_SUBTRACTED_BASENAME="d_$INPUT_BASENAME"
 OUTPUT_DARK_SUBTRACTED_PATH="$OUTPUT_DIRNAME/$OUTPUT_DARK_SUBTRACTED_BASENAME"
 OUTPUT_FLATFIELDED_BASENAME="fd_$INPUT_BASENAME"
 OUTPUT_FLATFIELDED_PATH="$OUTPUT_DIRNAME/$OUTPUT_FLATFIELDED_BASENAME"

 # Check that the output directory is writable
 if [ ! -w "$OUTPUT_DIRNAME" ];then
  echo "ERROR: the current directory $OUTPUT_DIRNAME is not writable"
  exit 1
 fi

 #################################
 # Perform dark frame subtraction
 echo "Subtracting dark frame..."

 # Clean up from any previous run
 if [ -f "$OUTPUT_DARK_SUBTRACTED_PATH" ];then
  rm -f "$OUTPUT_DARK_SUBTRACTED_PATH"
 fi

 "$VAST_PATH"util/ccd/ms "$INPUT_IMAGE" "$DARK_FRAME" "$OUTPUT_DARK_SUBTRACTED_PATH"
 if [ $? -ne 0 ];then
  echo "ERROR: dark frame subtraction failed"
  exit 1
 fi
 if [ ! -s "$OUTPUT_DARK_SUBTRACTED_PATH" ];then
  echo "ERROR: dark-subtracted output file was not created"
  exit 1
 fi
 echo "Dark-subtracted image: $OUTPUT_DARK_SUBTRACTED_PATH"

 OUTPUT_CALIBRATED_IMAGE="$OUTPUT_DARK_SUBTRACTED_PATH"

 #################################
 # Perform flat fielding if a flat field is available
 if [ -n "$FLAT_FIELD_DIR_OR_FILE" ];then
  # Resolve the flat field: use the specified file directly, or pick the best
  # matching flat from the specified directory
  FLAT_FIELD_FILE_TO_USE=""
  if [ -f "$FLAT_FIELD_DIR_OR_FILE" ];then
   FLAT_FIELD_FILE_TO_USE="$FLAT_FIELD_DIR_OR_FILE"
  elif [ -d "$FLAT_FIELD_DIR_OR_FILE" ];then
   FLAT_FIELD_FILE_TO_USE=$(FLAT_FIELDS_DIR="$FLAT_FIELD_DIR_OR_FILE" "$VAST_PATH"util/find_best_flat.sh "$INPUT_IMAGE")
   if [ $? -ne 0 ];then
    echo "WARNING: cannot find a matching flat field in $FLAT_FIELD_DIR_OR_FILE, using dark-subtracted image only"
    FLAT_FIELD_FILE_TO_USE=""
   else
    echo "Selected flat field: $FLAT_FIELD_FILE_TO_USE"
   fi
  fi

  if [ -n "$FLAT_FIELD_FILE_TO_USE" ] && [ -s "$FLAT_FIELD_FILE_TO_USE" ];then
   echo "Applying flat field correction..."

   # Clean up from any previous run
   if [ -f "$OUTPUT_FLATFIELDED_PATH" ];then
    rm -f "$OUTPUT_FLATFIELDED_PATH"
   fi

   "$VAST_PATH"util/ccd/md "$OUTPUT_DARK_SUBTRACTED_PATH" "$FLAT_FIELD_FILE_TO_USE" "$OUTPUT_FLATFIELDED_PATH"
   if [ $? -ne 0 ];then
    echo "WARNING: flat field correction failed, using dark-subtracted image only"
   else
    if [ -s "$OUTPUT_FLATFIELDED_PATH" ];then
     # Remove the intermediate dark-subtracted image to save space
     rm -f "$OUTPUT_DARK_SUBTRACTED_PATH"
     OUTPUT_CALIBRATED_IMAGE="$OUTPUT_FLATFIELDED_PATH"
     echo "Flat-fielded image: $OUTPUT_FLATFIELDED_PATH"
    else
     echo "WARNING: flat-fielded output file was not created, using dark-subtracted image"
    fi
   fi
  fi
 fi
fi

#################################
# Plate-solve the calibrated image
echo ""
echo "Plate-solving the calibrated image..."
echo "Running: $VAST_PATH"util/wcs_image_nocatalog.sh "$OUTPUT_CALIBRATED_IMAGE"

"$VAST_PATH"util/wcs_image_nocatalog.sh "$OUTPUT_CALIBRATED_IMAGE"
WCS_EXIT_CODE=$?

# Determine the expected WCS output filename (in current directory)
OUTPUT_CALIBRATED_BASENAME=$(basename "$OUTPUT_CALIBRATED_IMAGE")
OUTPUT_WCS_IMAGE="wcs_$OUTPUT_CALIBRATED_BASENAME"

if [ $WCS_EXIT_CODE -eq 0 ] && [ -s "$OUTPUT_WCS_IMAGE" ];then
 echo ""
 echo "SUCCESS: Calibration and plate-solving complete!"
 echo "Final output: $(pwd)/$OUTPUT_WCS_IMAGE"
else
 echo ""
 echo "WARNING: Plate-solving may have failed (exit code: $WCS_EXIT_CODE)"
 echo "Calibrated image is available at: $OUTPUT_CALIBRATED_IMAGE"
fi

exit 0
