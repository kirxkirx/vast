#!/usr/bin/env bash
#
# Find the most suitable flat field frame for a given science image among
# the flat field frames found in the directory FLAT_FIELDS_DIR.
#
# A suitable flat field must have the same image dimensions (NAXIS1/NAXIS2)
# and, if the corresponding keywords are present in both the science image
# and the flat, the same FILTER, CAMERA (camera name), CAMERAID (camera code)
# and TELESCOP. If a keyword is absent (or set to a placeholder like 'Unknown'
# or 'None') in either file, that keyword is assumed to match.
# Among the compatible flats, the one closest in time (JD) to the science
# image is selected.
#
# This mirrors the matching logic of util/ccd/md.c (the flat field applier)
# and parallels util/find_best_dark.sh.

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

VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
export VAST_PATH


# Extract a FITS keyword value from the header, handling single-quoted
# string values that may contain spaces (e.g. 'SBIG ST-9'). Returns an empty
# string if the keyword is not found. Mirrors the value CFITSIO's
# fits_read_key() would return (trailing blanks trimmed).
get_fits_string_value() {
 GFSV_FILE="$1"
 GFSV_KEYWORD="$2"
 GFSV_LINE=$("$VAST_PATH"util/listhead "$GFSV_FILE" 2>/dev/null | grep "^${GFSV_KEYWORD}[[:space:]]*=" | head -n1)
 if [ -z "$GFSV_LINE" ];then
  echo ""
  return
 fi
 # Drop everything up to and including the first '='
 GFSV_VALUE="${GFSV_LINE#*=}"
 # Trim leading whitespace
 GFSV_VALUE="${GFSV_VALUE#"${GFSV_VALUE%%[![:space:]]*}"}"
 if [ "${GFSV_VALUE:0:1}" = "'" ];then
  # Quoted string: take the content between the first pair of single quotes
  GFSV_VALUE="${GFSV_VALUE#\'}"
  GFSV_VALUE="${GFSV_VALUE%%\'*}"
 else
  # Unquoted value: drop the trailing comment and take the first token
  GFSV_VALUE="${GFSV_VALUE%%/*}"
  GFSV_VALUE=$(echo "$GFSV_VALUE" | awk '{print $1}')
 fi
 # Trim trailing whitespace
 GFSV_VALUE="${GFSV_VALUE%"${GFSV_VALUE##*[![:space:]]}"}"
 echo "$GFSV_VALUE"
}

# Decide if a FITS keyword value looks like a real identifier rather than a
# placeholder. Mirrors is_meaningful_keyword_value() in src/ccd/md.c.
# The second (optional) argument is the minimum acceptable string length:
# use 2 for TELESCOP/CAMERA/CAMERAID (matching md.c), but 1 for FILTER because
# single-character filter names (R, V, B, I, ...) are perfectly normal.
# Returns 0 (success) if the value is meaningful, 1 otherwise.
is_meaningful_keyword_value() {
 IMKV_VALUE="$1"
 IMKV_MINLEN="${2:-2}"
 if [ -z "$IMKV_VALUE" ];then
  return 1
 fi
 if [ "${#IMKV_VALUE}" -lt "$IMKV_MINLEN" ];then
  return 1
 fi
 IMKV_LOWER=$(echo "$IMKV_VALUE" | tr '[:upper:]' '[:lower:]')
 if [ "$IMKV_LOWER" = "unknown telescope" ] || [ "$IMKV_LOWER" = "unknown" ] || [ "$IMKV_LOWER" = "none" ];then
  return 1
 fi
 # Require at least one character that is not a separator ('_', '-', ' ', '.')
 if echo "$IMKV_VALUE" | grep -q '[^_. -]';then
  return 0
 fi
 return 1
}

# Compare a keyword value between the science image and a candidate flat.
# The third (optional) argument is the minimum meaningful string length
# (2 by default, 1 for FILTER).
# Returns 0 (compatible) if either value is not meaningful (assume match) or
# both are meaningful and equal; returns 1 (incompatible) only if both are
# meaningful and differ.
keyword_compatible() {
 KC_IMAGE_VALUE="$1"
 KC_FLAT_VALUE="$2"
 KC_MINLEN="${3:-2}"
 if ! is_meaningful_keyword_value "$KC_IMAGE_VALUE" "$KC_MINLEN";then
  return 0
 fi
 if ! is_meaningful_keyword_value "$KC_FLAT_VALUE" "$KC_MINLEN";then
  return 0
 fi
 if [ "$KC_IMAGE_VALUE" = "$KC_FLAT_VALUE" ];then
  return 0
 fi
 return 1
}


if [ -z "$1" ];then
 echo "Usage:
 export FLAT_FIELDS_DIR=/path/to/flat/fields/for/this/camera
 $0 science_image.fits" >&2
 exit 1
fi

if [ -z "$FLAT_FIELDS_DIR" ];then
 echo "FLAT_FIELDS_DIR is not set" >&2
 exit 1
fi
if [ ! -d "$FLAT_FIELDS_DIR" ];then
 echo "FLAT_FIELDS_DIR=$FLAT_FIELDS_DIR is not a directory" >&2
 exit 1
fi

############### Input image ###############

FITSFILE="$1"

# Check if the image actually exists
if [ ! -f "$FITSFILE" ];then
 echo "ERROR: cannot find the image file $FITSFILE" >&2
 exit 1
fi
# Check if the image file is not empty
if [ ! -s "$FITSFILE" ];then
 echo "ERROR: the input image file $FITSFILE is empty" >&2
 exit 1
fi
###############
# Verify that the input file is a valid FITS file
"$VAST_PATH"lib/fitsverify -q -e "$FITSFILE" &>/dev/null
if [ $? -ne 0 ];then
 ## Exampt from the rule for files that have at least some correct keywords
 echo "$FITSFILE" | grep  -e ".fits"  -e ".FITS"  -e ".fts" -e ".FTS"  -e ".fit"  -e ".FIT" && "$VAST_PATH"util/listhead "$FITSFILE" | grep -q -e "SIMPLE  =                    T" -e "TELESCOP= 'Aristarchos'" && "$VAST_PATH"util/listhead "$FITSFILE" | grep -q -e "NAXIS   =                    2"  -e "NAXIS3  =                    1" -e "TELESCOP= 'Aristarchos'"
 if [ $? -ne 0 ];then
  echo "ERROR: the input image file $FITSFILE did not pass verification as a valid FITS file"  >&2
  exit 1
 fi
fi

OUTPUT_OF_GET_IMAGE_DATE=$("$VAST_PATH"util/get_image_date "$FITSFILE" 2>&1)
if [ -z "$OUTPUT_OF_GET_IMAGE_DATE" ];then
 echo "ERROR: empty OUTPUT_OF_GET_IMAGE_DATE" >&2
 exit 1
fi

IMAGE_JD=$(echo "$OUTPUT_OF_GET_IMAGE_DATE" | grep '  JD ' | awk '{print $2}' | head -n1)
if [ -z "$IMAGE_JD" ];then
 echo "ERROR: empty IMAGE_JD" >&2
 exit 1
fi
IMAGE_NAXIS1=$(echo "$OUTPUT_OF_GET_IMAGE_DATE" | grep ' FITS image ' | grep 'x' | awk '{print $1}' | awk -F'x' '{print $1}' | head -n1)
if [ -z "$IMAGE_NAXIS1" ];then
 echo "ERROR: empty IMAGE_NAXIS1" >&2
 exit 1
fi
IMAGE_NAXIS2=$(echo "$OUTPUT_OF_GET_IMAGE_DATE" | grep ' FITS image ' | grep 'x' | awk '{print $1}' | awk -F'x' '{print $2}' | head -n1)
if [ -z "$IMAGE_NAXIS2" ];then
 echo "ERROR: empty IMAGE_NAXIS2" >&2
 exit 1
fi

# Camera/filter identification keywords (may be absent - that is fine)
IMAGE_FILTER=$(get_fits_string_value "$FITSFILE" "FILTER")
IMAGE_CAMERA=$(get_fits_string_value "$FITSFILE" "CAMERA")
IMAGE_CAMERAID=$(get_fits_string_value "$FITSFILE" "CAMERAID")
IMAGE_TELESCOP=$(get_fits_string_value "$FITSFILE" "TELESCOP")


# Initialize a variable to hold the minimum JD difference and the corresponding flat field file name
MIN_JD_DIFF=9999999999
SELECTED_FLAT_IMAGE=""

############### Characterize flat field frames ###############
for FLAT in "$FLAT_FIELDS_DIR"/* ;do
 if [ ! -f "$FLAT" ];then
  continue
 fi
 if [ ! -s "$FLAT" ];then
  continue
 fi

 ###############
 # On-the fly convert the input image if necessary
 FLAT=$("$VAST_PATH"lib/on_the_fly_symlink_or_convert "$FLAT")
 ###############
 # Verify that the input file is a valid FITS file
 "$VAST_PATH"lib/fitsverify -q -e "$FLAT" &>/dev/null
 if [ $? -ne 0 ];then
  ## Exampt from the rule for files that have at least some correct keywords
  echo "$FLAT" | grep -q  -e ".fits"  -e ".FITS"  -e ".fts" -e ".FTS"  -e ".fit"  -e ".FIT" && "$VAST_PATH"util/listhead "$FLAT" | grep -q -e "SIMPLE  =                    T" -e "TELESCOP= 'Aristarchos'" && "$VAST_PATH"util/listhead "$FLAT" | grep -q -e "NAXIS   =                    2"  -e "NAXIS3  =                    1" -e "TELESCOP= 'Aristarchos'"
  if [ $? -ne 0 ];then
   # Not a usable FITS file - skip it rather than aborting, as the flat field
   # directory may legitimately contain other files.
   continue
  fi
 fi

 OUTPUT_OF_GET_FLAT_DATE=$("$VAST_PATH"util/get_image_date "$FLAT" 2>&1)
 if [ -z "$OUTPUT_OF_GET_FLAT_DATE" ];then
  continue
 fi

 FLAT_JD=$(echo "$OUTPUT_OF_GET_FLAT_DATE" | grep '  JD ' | awk '{print $2}' | head -n1)
 if [ -z "$FLAT_JD" ];then
  # Cannot determine the time of this flat - cannot rank it by time, skip it
  continue
 fi
 FLAT_NAXIS1=$(echo "$OUTPUT_OF_GET_FLAT_DATE" | grep ' FITS image ' | grep 'x' | awk '{print $1}' | awk -F'x' '{print $1}' | head -n1)
 if [ -z "$FLAT_NAXIS1" ];then
  continue
 fi
 FLAT_NAXIS2=$(echo "$OUTPUT_OF_GET_FLAT_DATE" | grep ' FITS image ' | grep 'x' | awk '{print $1}' | awk -F'x' '{print $2}' | head -n1)
 if [ -z "$FLAT_NAXIS2" ];then
  continue
 fi

 # Image dimensions must match exactly
 if [ "$IMAGE_NAXIS1" != "$FLAT_NAXIS1" ];then
  continue
 fi
 if [ "$IMAGE_NAXIS2" != "$FLAT_NAXIS2" ];then
  continue
 fi

 # Camera/filter identification keywords must match if present in both files.
 # FILTER uses a minimum meaningful length of 1 (single-letter filter names).
 FLAT_FILTER=$(get_fits_string_value "$FLAT" "FILTER")
 if ! keyword_compatible "$IMAGE_FILTER" "$FLAT_FILTER" 1;then
  continue
 fi
 FLAT_CAMERA=$(get_fits_string_value "$FLAT" "CAMERA")
 if ! keyword_compatible "$IMAGE_CAMERA" "$FLAT_CAMERA";then
  continue
 fi
 FLAT_CAMERAID=$(get_fits_string_value "$FLAT" "CAMERAID")
 if ! keyword_compatible "$IMAGE_CAMERAID" "$FLAT_CAMERAID";then
  continue
 fi
 FLAT_TELESCOP=$(get_fits_string_value "$FLAT" "TELESCOP")
 if ! keyword_compatible "$IMAGE_TELESCOP" "$FLAT_TELESCOP";then
  continue
 fi

 # Calculate the absolute JD difference
 JD_DIFF=$(echo "$FLAT_JD $IMAGE_JD" | awk '{print ($1 > $2) ? $1 - $2 : $2 - $1}')

 # Update the minimum JD difference and selected flat image if the current one is closer
 if awk -v jd_diff="$JD_DIFF" -v min_jd_diff="$MIN_JD_DIFF" 'BEGIN {exit !(jd_diff < min_jd_diff)}'; then
  MIN_JD_DIFF=$JD_DIFF
  SELECTED_FLAT_IMAGE="$FLAT"
 fi

done

# Output the selected flat field image
if [ -n "$SELECTED_FLAT_IMAGE" ];then
 echo "$SELECTED_FLAT_IMAGE"
else
 echo "No matching flat field image found in $FLAT_FIELDS_DIR" >&2
 exit 1
fi
