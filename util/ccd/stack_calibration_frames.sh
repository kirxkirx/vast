#!/usr/bin/env bash
#
# Process calibration frames: create master darks and master flats
# This script can be run from the vast directory or from a data directory containing DARK and FLAT subfolders
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

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

 # Remove last occurrences of util, lib, examples, ccd
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "util")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "lib")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "examples")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "transients")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "ccd")

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

# Verify VAST_PATH
if [ ! -d "$VAST_PATH" ];then
  echo "ERROR: Cannot find VaST directory at $VAST_PATH"
  exit 1
fi

# Determine the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# mk_fast and ms should be in the same directory as this script
MK_FAST="${SCRIPT_DIR}/mk_fast"
MS="${SCRIPT_DIR}/ms"

if [ ! -x "$MK_FAST" ];then
  echo "ERROR: Cannot find mk_fast tool at $MK_FAST"
  exit 1
fi

if [ ! -x "$MS" ];then
  echo "ERROR: Cannot find ms tool at $MS"
  exit 1
fi

if [ ! -x "${VAST_PATH}util/listhead" ];then
  echo "ERROR: Cannot find listhead tool at ${VAST_PATH}util/listhead"
  exit 1
fi

#################################
# Parse command line arguments
#################################

if [ -z "$1" ]; then
  # No argument - use current directory
  DATA_DIR="$PWD"
else
  DATA_DIR="$1"
fi

if [ ! -d "$DATA_DIR" ];then
  echo "ERROR: Directory $DATA_DIR does not exist"
  exit 1
fi

cd "$DATA_DIR" || exit 1
echo "Processing calibrations in: $PWD"

#################################
# Find BIAS, DARK and FLAT directories
#################################

BIAS_DIR=""
DARK_DIR=""
FLAT_DIR=""

# Look for BIAS directory (case-insensitive, singular or plural)
for dir in BIAS Bias bias Biases biases BIASES; do
  if [ -d "$dir" ]; then
    BIAS_DIR="$dir"
    break
  fi
done

# Look for DARK directory (case-insensitive, singular or plural)
for dir in DARK Dark dark Darks darks DARKS; do
  if [ -d "$dir" ]; then
    DARK_DIR="$dir"
    break
  fi
done

# Look for FLAT directory (case-insensitive, singular or plural)
for dir in FLAT Flat flat Flats flats FLATS; do
  if [ -d "$dir" ]; then
    FLAT_DIR="$dir"
    break
  fi
done

if [ -z "$BIAS_DIR" ] && [ -z "$DARK_DIR" ] && [ -z "$FLAT_DIR" ]; then
  echo "ERROR: Cannot find BIAS, DARK or FLAT directories in $PWD"
  exit 1
fi

#################################
# Helper functions
#################################

# Get FITS header value
get_header_value() {
  local file="$1"
  local keyword="$2"
  local line
  local value

  # Get the line containing the keyword
  line=$("${VAST_PATH}util/listhead" "$file" 2>/dev/null | grep "^${keyword}[[:space:]]*=")

  if [ -z "$line" ]; then
    echo ""
    return
  fi

  # Extract value after '=' sign (handles both "KEY=" and "KEY =" formats)
  value=$(echo "$line" | sed 's/^[^=]*=[[:space:]]*//' | awk '{print $1}')

  # Remove quotes if present and trim whitespace
  value=$(echo "$value" | sed "s/'//g" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

  echo "$value"
}

# Check if a file is a stacked frame (has "Median frame stacking:" in HISTORY)
is_stacked_frame() {
  local file="$1"
  "${VAST_PATH}util/listhead" "$file" 2>/dev/null | grep -q "Median frame stacking:"
  return $?
}

# Round a number to specified decimal places
round_number() {
  local num="$1"
  local places="$2"
  printf "%.${places}f" "$num"
}

#################################
# Process BIAS frames
#################################

if [ -n "$BIAS_DIR" ]; then
  echo ""
  echo "======================================"
  echo "Processing BIAS frames in $BIAS_DIR"
  echo "======================================"

  cd "$BIAS_DIR" || exit 1

  # Create temporary file for grouping
  GROUPING_FILE=$(mktemp)

  # Scan all FITS files
  total_bias=0
  rejected_bias=0
  stacked_bias=0

  shopt -s nullglob
  for file in *.fit *.fits *.fts *.FIT *.FITS *.FTS; do
    # Check if file exists (glob might not match anything)
    [ -f "$file" ] || continue

    # Skip files that are actually in subdirectories (via symlinks)
    if [ -L "$file" ]; then
      REAL_PATH=$(vastrealpath "$file")
      REAL_DIR=$(dirname "$REAL_PATH")
      CURRENT_DIR=$(pwd)
      if [ "$REAL_DIR" != "$CURRENT_DIR" ]; then
        continue
      fi
    fi

    # Skip if already stacked
    if is_stacked_frame "$file"; then
      echo "  Skipping already stacked frame: $file"
      ((stacked_bias++))
      continue
    fi

    # Get header values
    SET_TEMP=$(get_header_value "$file" "SET-TEMP")
    CCD_TEMP=$(get_header_value "$file" "CCD-TEMP")
    XBINNING=$(get_header_value "$file" "XBINNING")
    YBINNING=$(get_header_value "$file" "YBINNING")

    # Validate we got all values
    if [ -z "$SET_TEMP" ] || [ -z "$CCD_TEMP" ] || [ -z "$XBINNING" ] || [ -z "$YBINNING" ]; then
      echo "  WARNING: Missing header values in $file, skipping"
      ((rejected_bias++))
      continue
    fi

    # Check binning consistency
    if [ "$XBINNING" != "$YBINNING" ]; then
      echo "  WARNING: XBINNING ($XBINNING) != YBINNING ($YBINNING) in $file, skipping"
      ((rejected_bias++))
      continue
    fi

    # Check temperature stability
    TEMP_DIFF=$(echo "$SET_TEMP $CCD_TEMP" | awk '{d=$1-$2; if(d<0)d=-d; print d}')
    TEMP_OK=$(echo "$TEMP_DIFF" | awk '{if($1<=1.0)print "yes"; else print "no"}')

    if [ "$TEMP_OK" != "yes" ]; then
      echo "  WARNING: Temperature deviation too large (${TEMP_DIFF}°C) in $file, skipping"
      ((rejected_bias++))
      continue
    fi

    # Round values for grouping (bias frames don't need exposure grouping)
    TEMP_ROUNDED=$(round_number "$SET_TEMP" 0)
    BIN="$XBINNING"

    # Create group identifier
    GROUP_ID="${TEMP_ROUNDED}C_${BIN}x${BIN}"

    # Add to grouping file
    echo "$GROUP_ID|$file" >> "$GROUPING_FILE"
    ((total_bias++))
  done

  echo ""
  echo "Found $total_bias valid bias frames"
  echo "Rejected $rejected_bias frames (temperature/binning issues)"
  echo "Skipped $stacked_bias already-stacked frames"
  echo ""

  # Process each group
  if [ -s "$GROUPING_FILE" ]; then
    GROUP_LIST=$(cut -d'|' -f1 "$GROUPING_FILE" | sort -u)

    for group in $GROUP_LIST; do
      # Get files in this group
      FILES=$(grep "^${group}|" "$GROUPING_FILE" | cut -d'|' -f2)
      FILE_COUNT=$(echo "$FILES" | wc -l)

      echo "Group: $group"
      echo "  Files: $FILE_COUNT"

      if [ "$FILE_COUNT" -lt 3 ]; then
        echo "  WARNING: Not enough frames ($FILE_COUNT < 3) for group $group, skipping"
        continue
      fi

      OUTPUT_NAME="mbias_${group}.fit"

      # Check if output already exists
      if [ -f "$OUTPUT_NAME" ]; then
        echo "  Output $OUTPUT_NAME already exists, skipping"
        continue
      fi

      echo "  Creating $OUTPUT_NAME from $FILE_COUNT frames..."

      # Handle filenames starting with '-' by prefixing with --
      FILE_LIST=""
      for f in $FILES; do
        if [[ "$f" == -* ]]; then
          FILE_LIST="$FILE_LIST -- $f"
        else
          FILE_LIST="$FILE_LIST $f"
        fi
      done

      # Run mk_fast (outputs to median.fit)
      "$MK_FAST" $FILE_LIST

      if [ $? -eq 0 ]; then
        # mk_fast creates median.fit, rename it to our expected output name
        if [ -f "median.fit" ]; then
          mv median.fit "$OUTPUT_NAME"
          echo "  SUCCESS: Created $OUTPUT_NAME"
        else
          echo "  ERROR: mk_fast succeeded but median.fit not found"
        fi
      else
        echo "  ERROR: Failed to create $OUTPUT_NAME"
      fi
      echo ""
    done
  fi

  rm -f "$GROUPING_FILE"

  cd ..
fi

#################################
# Process DARK frames
#################################

if [ -n "$DARK_DIR" ]; then
  echo ""
  echo "======================================"
  echo "Processing DARK frames in $DARK_DIR"
  echo "======================================"

  cd "$DARK_DIR" || exit 1

  # Create temporary file for grouping
  GROUPING_FILE=$(mktemp)

  # Scan all FITS files
  total_darks=0
  rejected_darks=0
  stacked_darks=0

  shopt -s nullglob
  for file in *.fit *.fits *.fts *.FIT *.FITS *.FTS; do
    # Check if file exists (glob might not match anything)
    [ -f "$file" ] || continue

    # Skip files that are actually in subdirectories (via symlinks)
    if [ -L "$file" ]; then
      REAL_PATH=$(vastrealpath "$file")
      REAL_DIR=$(dirname "$REAL_PATH")
      CURRENT_DIR=$(pwd)
      if [ "$REAL_DIR" != "$CURRENT_DIR" ]; then
        continue
      fi
    fi

    # Skip if already stacked
    if is_stacked_frame "$file"; then
      echo "  Skipping already stacked frame: $file"
      ((stacked_darks++))
      continue
    fi

    # Get header values
    EXPOSURE=$(get_header_value "$file" "EXPOSURE")
    if [ -z "$EXPOSURE" ]; then
      EXPOSURE=$(get_header_value "$file" "EXPTIME")
    fi

    SET_TEMP=$(get_header_value "$file" "SET-TEMP")
    CCD_TEMP=$(get_header_value "$file" "CCD-TEMP")
    XBINNING=$(get_header_value "$file" "XBINNING")
    YBINNING=$(get_header_value "$file" "YBINNING")

    # Validate we got all values
    if [ -z "$EXPOSURE" ] || [ -z "$SET_TEMP" ] || [ -z "$CCD_TEMP" ] || [ -z "$XBINNING" ] || [ -z "$YBINNING" ]; then
      echo "  WARNING: Missing header values in $file, skipping"
      ((rejected_darks++))
      continue
    fi

    # Check binning consistency
    if [ "$XBINNING" != "$YBINNING" ]; then
      echo "  WARNING: XBINNING ($XBINNING) != YBINNING ($YBINNING) in $file, skipping"
      ((rejected_darks++))
      continue
    fi

    # Check temperature stability
    TEMP_DIFF=$(echo "$SET_TEMP $CCD_TEMP" | awk '{d=$1-$2; if(d<0)d=-d; print d}')
    TEMP_OK=$(echo "$TEMP_DIFF" | awk '{if($1<=1.0)print "yes"; else print "no"}')

    if [ "$TEMP_OK" != "yes" ]; then
      echo "  WARNING: Temperature deviation too large (${TEMP_DIFF}°C) in $file, skipping"
      ((rejected_darks++))
      continue
    fi

    # Round values for grouping
    EXP_ROUNDED=$(round_number "$EXPOSURE" 1)
    TEMP_ROUNDED=$(round_number "$SET_TEMP" 0)
    BIN="$XBINNING"

    # Create group identifier
    GROUP_ID="${EXP_ROUNDED}sec_${TEMP_ROUNDED}C_${BIN}x${BIN}"

    # Add to grouping file
    echo "$GROUP_ID|$file" >> "$GROUPING_FILE"
    ((total_darks++))
  done

  echo ""
  echo "Found $total_darks valid dark frames"
  echo "Rejected $rejected_darks frames (temperature/binning issues)"
  echo "Skipped $stacked_darks already-stacked frames"
  echo ""

  # Process each group
  if [ -s "$GROUPING_FILE" ]; then
    GROUP_LIST=$(cut -d'|' -f1 "$GROUPING_FILE" | sort -u)

    for group in $GROUP_LIST; do
      # Get files in this group
      FILES=$(grep "^${group}|" "$GROUPING_FILE" | cut -d'|' -f2)
      FILE_COUNT=$(echo "$FILES" | wc -l)

      echo "Group: $group"
      echo "  Files: $FILE_COUNT"

      if [ "$FILE_COUNT" -lt 3 ]; then
        echo "  WARNING: Not enough frames ($FILE_COUNT < 3) for group $group, skipping"
        continue
      fi

      OUTPUT_NAME="mdark_${group}.fit"

      # Check if output already exists
      if [ -f "$OUTPUT_NAME" ]; then
        echo "  Output $OUTPUT_NAME already exists, skipping"
        continue
      fi

      echo "  Creating $OUTPUT_NAME from $FILE_COUNT frames..."

      # Handle filenames starting with '-' by prefixing with --
      FILE_LIST=""
      for f in $FILES; do
        if [[ "$f" == -* ]]; then
          FILE_LIST="$FILE_LIST -- $f"
        else
          FILE_LIST="$FILE_LIST $f"
        fi
      done

      # Run mk_fast (outputs to median.fit)
      "$MK_FAST" $FILE_LIST

      if [ $? -eq 0 ]; then
        # mk_fast creates median.fit, rename it to our expected output name
        if [ -f "median.fit" ]; then
          mv median.fit "$OUTPUT_NAME"
          echo "  SUCCESS: Created $OUTPUT_NAME"
        else
          echo "  ERROR: mk_fast succeeded but median.fit not found"
        fi
      else
        echo "  ERROR: Failed to create $OUTPUT_NAME"
      fi
      echo ""
    done
  fi

  rm -f "$GROUPING_FILE"

  cd ..
fi

#################################
# Process FLAT frames
#################################

if [ -n "$FLAT_DIR" ]; then
  echo ""
  echo "======================================"
  echo "Processing FLAT frames in $FLAT_DIR"
  echo "======================================"

  cd "$FLAT_DIR" || exit 1

  if [ -z "$DARK_DIR" ] && [ -z "$BIAS_DIR" ]; then
    echo "WARNING: No DARK or BIAS directory found, cannot process flats"
  else
    # First pass: Dark/Bias subtraction
    echo ""
    echo "Step 1: Dark/Bias subtraction"
    echo "-----------------------------"

    total_flats=0
    subtracted_flats=0
    skipped_flats=0
    bias_fallback_count=0

    for file in *.fit *.fits *.fts *.FIT *.FITS *.FTS; do
      # Check if file exists
      [ -f "$file" ] || continue

      # Skip files that are actually in subdirectories (via symlinks)
      if [ -L "$file" ]; then
        REAL_PATH=$(vastrealpath "$file")
        REAL_DIR=$(dirname "$REAL_PATH")
        CURRENT_DIR=$(pwd)
        if [ "$REAL_DIR" != "$CURRENT_DIR" ]; then
          continue
        fi
      fi

      # Skip dark-subtracted files
      if [[ "$file" == d_* ]]; then
        continue
      fi

      # Skip if already stacked
      if is_stacked_frame "$file"; then
        echo "  Skipping already stacked frame: $file"
        ((skipped_flats++))
        continue
      fi

      ((total_flats++))

      # Get header values
      EXPOSURE=$(get_header_value "$file" "EXPOSURE")
      if [ -z "$EXPOSURE" ]; then
        EXPOSURE=$(get_header_value "$file" "EXPTIME")
      fi

      SET_TEMP=$(get_header_value "$file" "SET-TEMP")
      XBINNING=$(get_header_value "$file" "XBINNING")
      YBINNING=$(get_header_value "$file" "YBINNING")

      if [ -z "$EXPOSURE" ] || [ -z "$SET_TEMP" ] || [ -z "$XBINNING" ] || [ -z "$YBINNING" ]; then
        echo "  WARNING: Missing header values in $file, skipping"
        continue
      fi

      # Check binning consistency
      if [ "$XBINNING" != "$YBINNING" ]; then
        echo "  WARNING: XBINNING ($XBINNING) != YBINNING ($YBINNING) in $file, skipping"
        continue
      fi

      # Round values for matching calibration frames
      EXP_ROUNDED=$(round_number "$EXPOSURE" 1)
      TEMP_ROUNDED=$(round_number "$SET_TEMP" 0)
      BIN="$XBINNING"

      # Try to find matching dark frame first
      CALIB_FRAME=""
      CALIB_TYPE=""

      if [ -n "$DARK_DIR" ]; then
        DARK_NAME="../${DARK_DIR}/mdark_${EXP_ROUNDED}sec_${TEMP_ROUNDED}C_${BIN}x${BIN}.fit"
        if [ -f "$DARK_NAME" ]; then
          CALIB_FRAME="$DARK_NAME"
          CALIB_TYPE="dark"
        fi
      fi

      # If no matching dark, try bias as fallback
      if [ -z "$CALIB_FRAME" ] && [ -n "$BIAS_DIR" ]; then
        BIAS_NAME="../${BIAS_DIR}/mbias_${TEMP_ROUNDED}C_${BIN}x${BIN}.fit"
        if [ -f "$BIAS_NAME" ]; then
          CALIB_FRAME="$BIAS_NAME"
          CALIB_TYPE="bias"
          echo "  WARNING: No matching dark for $file (exposure ${EXP_ROUNDED}sec), using bias instead"
          ((bias_fallback_count++))
        fi
      fi

      # If still no calibration frame found, skip
      if [ -z "$CALIB_FRAME" ]; then
        echo "  WARNING: No matching dark or bias found for $file, skipping"
        continue
      fi

      # Output name for calibrated flat
      OUTPUT_NAME="d_${file}"

      # Skip if already exists
      if [ -f "$OUTPUT_NAME" ]; then
        echo "  Calibrated file $OUTPUT_NAME already exists, skipping"
        ((subtracted_flats++))
        continue
      fi

      echo "  Subtracting $CALIB_TYPE from $file..."

      # Handle filenames starting with '-'
      if [[ "$file" == -* ]]; then
        "$MS" -- "$file" "$CALIB_FRAME" "$OUTPUT_NAME"
      else
        "$MS" "$file" "$CALIB_FRAME" "$OUTPUT_NAME"
      fi

      if [ $? -eq 0 ]; then
        ((subtracted_flats++))
      else
        echo "  ERROR: Calibration subtraction failed for $file"
      fi
    done

    echo ""
    echo "Processed $total_flats flat frames"
    echo "Created/found $subtracted_flats calibrated frames"
    if [ $bias_fallback_count -gt 0 ]; then
      echo "Used bias fallback for $bias_fallback_count frames (no matching darks)"
    fi
    echo "Skipped $skipped_flats already-stacked frames"

    # Second pass: Group and stack calibrated flats
    echo ""
    echo "Step 2: Stacking calibrated flats"
    echo "----------------------------------"

    GROUPING_FILE=$(mktemp)

    for file in d_*.fit d_*.fits d_*.fts d_*.FIT d_*.FITS d_*.FTS; do
      # Check if file exists
      [ -f "$file" ] || continue

      # Skip files that are actually in subdirectories (via symlinks)
      if [ -L "$file" ]; then
        REAL_PATH=$(vastrealpath "$file")
        REAL_DIR=$(dirname "$REAL_PATH")
        CURRENT_DIR=$(pwd)
        if [ "$REAL_DIR" != "$CURRENT_DIR" ]; then
          continue
        fi
      fi

      # Get header values
      SET_TEMP=$(get_header_value "$file" "SET-TEMP")
      XBINNING=$(get_header_value "$file" "XBINNING")
      YBINNING=$(get_header_value "$file" "YBINNING")
      FILTER=$(get_header_value "$file" "FILTER")

      if [ -z "$SET_TEMP" ] || [ -z "$XBINNING" ] || [ -z "$YBINNING" ]; then
        echo "  WARNING: Missing header values in $file, skipping"
        continue
      fi

      # Use "NoFilter" if FILTER is empty
      if [ -z "$FILTER" ]; then
        FILTER="NoFilter"
      fi

      # Check binning consistency
      if [ "$XBINNING" != "$YBINNING" ]; then
        echo "  WARNING: XBINNING ($XBINNING) != YBINNING ($YBINNING) in $file, skipping"
        continue
      fi

      # Round values for grouping
      TEMP_ROUNDED=$(round_number "$SET_TEMP" 0)
      BIN="$XBINNING"

      # Create group identifier (sanitize filter name for filename)
      FILTER_SAFE=$(echo "$FILTER" | tr ' /' '_')
      GROUP_ID="${FILTER_SAFE}_${TEMP_ROUNDED}C_${BIN}x${BIN}"

      # Add to grouping file
      echo "$GROUP_ID|$file" >> "$GROUPING_FILE"
    done

    # Process each group
    if [ -s "$GROUPING_FILE" ]; then
      GROUP_LIST=$(cut -d'|' -f1 "$GROUPING_FILE" | sort -u)

      for group in $GROUP_LIST; do
        # Get files in this group
        FILES=$(grep "^${group}|" "$GROUPING_FILE" | cut -d'|' -f2)
        FILE_COUNT=$(echo "$FILES" | wc -l)

        echo "Group: $group"
        echo "  Files: $FILE_COUNT"

        if [ "$FILE_COUNT" -lt 3 ]; then
          echo "  WARNING: Not enough frames ($FILE_COUNT < 3) for group $group, skipping"
          continue
        fi

        OUTPUT_NAME="mflat_${group}.fit"

        # Check if output already exists
        if [ -f "$OUTPUT_NAME" ]; then
          echo "  Output $OUTPUT_NAME already exists, skipping"
          continue
        fi

        echo "  Creating $OUTPUT_NAME from $FILE_COUNT frames..."

        # Handle filenames starting with '-' by prefixing with --
        FILE_LIST=""
        for f in $FILES; do
          if [[ "$f" == -* ]]; then
            FILE_LIST="$FILE_LIST -- $f"
          else
            FILE_LIST="$FILE_LIST $f"
          fi
        done

        # Run mk_fast (outputs to median.fit)
        "$MK_FAST" $FILE_LIST

        if [ $? -eq 0 ]; then
          # mk_fast creates median.fit, rename it to our expected output name
          if [ -f "median.fit" ]; then
            mv median.fit "$OUTPUT_NAME"
            echo "  SUCCESS: Created $OUTPUT_NAME"
          else
            echo "  ERROR: mk_fast succeeded but median.fit not found"
          fi
        else
          echo "  ERROR: Failed to create $OUTPUT_NAME"
        fi
        echo ""
      done
    else
      echo "No calibrated flats found to stack"
    fi

    rm -f "$GROUPING_FILE"
  fi

  cd ..
fi

echo ""
echo "======================================"
echo "Calibration processing complete"
echo "======================================"
