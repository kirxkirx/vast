#!/usr/bin/env bash

TARGET_NAME=TCPJ0538
IMG_FILE_PREFIX="fd_${TARGET_NAME}"

IMG_DIR="$1"

# Remove trailing / if present
IMG_DIR="${IMG_DIR%/}"

# Check if the input image directory exists
if [ ! -d "$IMG_DIR" ];then
 echo "ERROR: no input data dir $IMG_DIR"
 exit 1
fi
# Check if the input image directory contains a file named according to the expected pattern
for i in "${IMG_DIR}/${IMG_FILE_PREFIX}"* ;do
 if [ ! -f "$i" ];then
  echo "ERROR: cannot find input calibrated images matching pattern $IMG_DIR/fd_$TARGET_NAME*"
  exit 1
 else
  break
 fi
done

# Check if the Source Extractor settings file exist
if [ ! -s default.sex."$TARGET_NAME" ];then
 echo "ERROR: no Source Extractor settings file default.sex.$TARGET_NAME"
 exit 1
fi
cp -v default.sex."$TARGET_NAME" default.sex

# Main analysis command
# --aperture 10   manually set fixed measurement aperture diameter of 10 pix
# --type 4        robust linear image-to-image magnitude calibration (vary zero-point and slope, automated outlier rejection, no weights)
./vast --aperture 10 --autoselectrefimage --type 4 --nofind --UTC "${IMG_DIR}/${IMG_FILE_PREFIX}"*

# Magnitude scale instrumental-to-catalog calibration (specify band and calibration function)
util/magnitude_calibration.sh V robust_linear

# Visually select the variable star on reference image to plot its lightcurve
./select_star_on_reference_image

# Note the variable star lightcurve file name (something like out01234.dat)
#
# You may re-format that lightcurve to AAVSO-friendly format using
# util/format_lightcurve_AAVSO.sh out01234.dat
# or to CBA-friendly format using 
# util/format_lightcurve_CBA.sh out01234.dat
# Note that you will need to edit the text files produced by these scripts
# to specify the observing filter, observer code and maybe some other information.
