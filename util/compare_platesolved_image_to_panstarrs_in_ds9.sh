#!/usr/bin/env bash

#
# This script downloads a PanSTARRS1 image matching the field of view
# of a user-supplied plate-solved FITS image and opens both in DS9
# for visual comparison (blinking).
#
# Uses the CDS HiPS2FITS service to obtain PanSTARRS1 DR1 images.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Print usage if no arguments
if [ -z "$1" ];then
 echo "This script downloads a PanSTARRS1 image matching the field of view
of a plate-solved FITS image and opens both in DS9 for visual comparison.

 Usage: $0 wcs_image.fits [PS1_filter]

 PS1_filter is one of: g r i z y (default: r)

 Example: $0 wcs_Vul2_2020-6-4_21-58-11_002.fts i" 1>&2
 exit 1
fi

FITS_IMAGE_TO_CHECK="$1"

# Check input image
if [ ! -f "$FITS_IMAGE_TO_CHECK" ];then
 echo "ERROR: cannot find the input FITS image $FITS_IMAGE_TO_CHECK" 1>&2
 exit 1
fi
if [ ! -s "$FITS_IMAGE_TO_CHECK" ];then
 echo "ERROR: the input image $FITS_IMAGE_TO_CHECK is empty" 1>&2
 exit 1
fi

# Parse filter argument
PS1_FILTER="$2"
if [ -z "$PS1_FILTER" ];then
 PS1_FILTER="r"
 echo "No PanSTARRS1 filter specified, defaulting to '$PS1_FILTER'"
fi

# Validate filter name
case "$PS1_FILTER" in
 g|r|i|z|y)
  # valid filter
  ;;
 *)
  echo "ERROR: unknown PanSTARRS1 filter '$PS1_FILTER'. Must be one of: g r i z y" 1>&2
  exit 1
  ;;
esac

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


# Set the VaST path to find external programs
if [ -z "$VAST_PATH" ];then
 VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi

# Check that required VaST tools exist
for REQUIRED_TOOL in lib/bin/xy2sky lib/bin/skycoor lib/astrometry/get_image_dimentions ;do
 if [ ! -x "${VAST_PATH}${REQUIRED_TOOL}" ];then
  echo "ERROR: required tool ${VAST_PATH}${REQUIRED_TOOL} not found. Please compile VaST first with 'make'." 1>&2
  exit 1
 fi
done

# Check that curl is available
command -v curl &>/dev/null
if [ $? -ne 0 ];then
 echo "ERROR: curl is not found. Please install curl." 1>&2
 exit 1
fi

# Check that ds9 is available
command -v ds9 &>/dev/null
if [ $? -ne 0 ];then
 echo "ERROR: ds9 is not found. Please install SAOImageDS9." 1>&2
 exit 1
fi

# Verify that the input file is a valid FITS file
"$VAST_PATH"lib/fitsverify -q -e "$FITS_IMAGE_TO_CHECK" 2>/dev/null
if [ $? -ne 0 ];then
 echo "WARNING: the input file $FITS_IMAGE_TO_CHECK may not fully comply with the FITS standard.
Attempting to proceed anyway..." 1>&2
fi

# Get image dimensions in pixels
IMG_SIZE_STR=$("$VAST_PATH"lib/astrometry/get_image_dimentions "$FITS_IMAGE_TO_CHECK")
NAXIS1=$(echo "$IMG_SIZE_STR" | awk '{print $2}')
NAXIS2=$(echo "$IMG_SIZE_STR" | awk '{print $4}')
if [ -z "$NAXIS1" ] || [ -z "$NAXIS2" ];then
 echo "ERROR: cannot determine image dimensions for $FITS_IMAGE_TO_CHECK" 1>&2
 exit 1
fi

# Get the image center RA, Dec (in degrees, J2000)
IMAGE_CENTER_XY=$(echo "$NAXIS1 $NAXIS2" | awk '{printf "%.3f %.3f",$1/2+1,$2/2+1}')
# Use -d flag to get decimal degrees (needed for the HiPS2FITS URL and Dec range check)
IMAGE_CENTER_RA_Dec=$("$VAST_PATH"lib/bin/xy2sky -j -d "$FITS_IMAGE_TO_CHECK" $IMAGE_CENTER_XY)
if [ $? -ne 0 ] || [ -z "$IMAGE_CENTER_RA_Dec" ];then
 echo "ERROR: failed to convert image center to sky coordinates.
Is the input image $FITS_IMAGE_TO_CHECK actually plate-solved?" 1>&2
 exit 1
fi
CENTER_RA=$(echo "$IMAGE_CENTER_RA_Dec" | awk '{print $1}')
CENTER_DEC=$(echo "$IMAGE_CENTER_RA_Dec" | awk '{print $2}')
if [ -z "$CENTER_RA" ] || [ -z "$CENTER_DEC" ];then
 echo "ERROR: failed to parse image center coordinates from xy2sky output: $IMAGE_CENTER_RA_Dec" 1>&2
 exit 1
fi

# Check PanSTARRS1 sky coverage (Dec > -30)
DEC_TOO_SOUTH=$(echo "$CENTER_DEC" | awk '{if ($1 < -30.0) print 1; else print 0}')
if [ "$DEC_TOO_SOUTH" = "1" ];then
 echo "ERROR: the image center Dec=$CENTER_DEC is south of -30 degrees.
PanSTARRS1 3pi survey does not cover this part of the sky." 1>&2
 exit 1
fi

# Determine the image field of view
XY2SKY_OUTPUT=$("$VAST_PATH"lib/bin/xy2sky -j "$FITS_IMAGE_TO_CHECK" 0 0 $NAXIS1 0 0 $NAXIS2)
CORNER_0_0=$(echo "$XY2SKY_OUTPUT" | head -n1 | awk '{print $1" "$2}')
CORNER_NAXIS1_0=$(echo "$XY2SKY_OUTPUT" | head -n2 | tail -n1 | awk '{print $1" "$2}')
CORNER_0_NAXIS2=$(echo "$XY2SKY_OUTPUT" | head -n3 | tail -n1 | awk '{print $1" "$2}')
X_SIZE_ARCMIN=$("$VAST_PATH"lib/bin/skycoor -r $CORNER_0_0 $CORNER_NAXIS1_0 | awk '{printf "%.1f",$1/60}')
Y_SIZE_ARCMIN=$("$VAST_PATH"lib/bin/skycoor -r $CORNER_0_0 $CORNER_0_NAXIS2 | awk '{printf "%.1f",$1/60}')

if [ -z "$X_SIZE_ARCMIN" ] || [ -z "$Y_SIZE_ARCMIN" ];then
 echo "ERROR: failed to determine the image field of view" 1>&2
 exit 1
fi

X_SIZE_DEG=$(echo "$X_SIZE_ARCMIN" | awk '{printf "%.4f",$1/60}')
Y_SIZE_DEG=$(echo "$Y_SIZE_ARCMIN" | awk '{printf "%.4f",$1/60}')

# Use the larger FOV dimension for the HiPS2FITS request
FOV_DEG=$(echo "$X_SIZE_DEG $Y_SIZE_DEG" | awk '{if ($1 > $2) printf "%.4f",$1; else printf "%.4f",$2}')

echo "Image center: RA=$CENTER_RA Dec=$CENTER_DEC (J2000 degrees)"
echo "Image FOV: ${X_SIZE_ARCMIN}'x${Y_SIZE_ARCMIN}' (${X_SIZE_DEG}x${Y_SIZE_DEG} deg)"
echo "Requesting PanSTARRS1 DR1 ${PS1_FILTER}-band image..."

# Determine output pixel dimensions
# Scale both axes proportionally, capping the largest dimension at 4096
MAX_OUTPUT_PIX=4096
OUTPUT_WIDTH="$NAXIS1"
OUTPUT_HEIGHT="$NAXIS2"
LARGER_DIM=$(echo "$NAXIS1 $NAXIS2" | awk '{if ($1 > $2) print $1; else print $2}')
NEEDS_SCALING=$(echo "$LARGER_DIM" | awk -v max="$MAX_OUTPUT_PIX" '{if ($1 > max) print 1; else print 0}')
if [ "$NEEDS_SCALING" = "1" ];then
 OUTPUT_WIDTH=$(echo "$NAXIS1 $LARGER_DIM" | awk -v max="$MAX_OUTPUT_PIX" '{printf "%d",$1*max/$2}')
 OUTPUT_HEIGHT=$(echo "$NAXIS2 $LARGER_DIM" | awk -v max="$MAX_OUTPUT_PIX" '{printf "%d",$1*max/$2}')
fi

# Construct the output filename
INPUT_BASENAME=$(basename "$FITS_IMAGE_TO_CHECK")
# Remove extension
INPUT_BASENAME_NOEXT="${INPUT_BASENAME%.*}"
PS1_OUTPUT_FITS="panstarrs1_${PS1_FILTER}_${INPUT_BASENAME_NOEXT}.fits"

# Download the PanSTARRS1 image from HiPS2FITS
HIPS2FITS_URL="http://alasky.cds.unistra.fr/hips-image-services/hips2fits?hips=CDS/P/PanSTARRS/DR1/${PS1_FILTER}&width=${OUTPUT_WIDTH}&height=${OUTPUT_HEIGHT}&ra=${CENTER_RA}&dec=${CENTER_DEC}&fov=${FOV_DEG}&projection=TAN&format=fits"

echo "Downloading from HiPS2FITS service..."
curl -s --retry 3 --retry-delay 5 --connect-timeout 30 --max-time 300 -o "$PS1_OUTPUT_FITS" "$HIPS2FITS_URL"
CURL_EXIT_CODE=$?
if [ $CURL_EXIT_CODE -ne 0 ];then
 echo "ERROR: curl failed to download the PanSTARRS1 image (exit code $CURL_EXIT_CODE).
URL: $HIPS2FITS_URL" 1>&2
 rm -f "$PS1_OUTPUT_FITS"
 exit 1
fi

# Verify the download produced a non-empty file
if [ ! -s "$PS1_OUTPUT_FITS" ];then
 echo "ERROR: downloaded PanSTARRS1 image file is empty.
The HiPS2FITS service may be temporarily unavailable. Please try again later.
URL: $HIPS2FITS_URL" 1>&2
 rm -f "$PS1_OUTPUT_FITS"
 exit 1
fi

# Check that the downloaded file is a valid FITS file (not an error page)
# FITS files must start with "SIMPLE"
FIRST_BYTES=$(head -c 6 "$PS1_OUTPUT_FITS" 2>/dev/null)
if [ "$FIRST_BYTES" != "SIMPLE" ];then
 echo "ERROR: downloaded file is not a valid FITS image (possibly an error message from the server).
The image center may be outside PanSTARRS1 coverage or the service may be temporarily unavailable.
URL: $HIPS2FITS_URL" 1>&2
 rm -f "$PS1_OUTPUT_FITS"
 exit 1
fi

echo "PanSTARRS1 ${PS1_FILTER}-band image saved to $PS1_OUTPUT_FITS"
echo "Starting DS9 with WCS-locked frames for blinking..."
echo "Use DS9 menu: Frame -> Blink to blink between the images."

ds9 "$FITS_IMAGE_TO_CHECK" "$PS1_OUTPUT_FITS" -frame lock wcs -xpa no &

echo "Done."
