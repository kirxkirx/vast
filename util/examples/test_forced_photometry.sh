#!/usr/bin/env bash

#
# Test script for forced photometry.
#
# 1. Runs forced photometry on a specified target position.
# 2. Runs SExtractor on the same image, calibrates magnitudes,
#    randomly selects 100 detected stars, and compares forced
#    photometry results to SExtractor calibrated magnitudes.
#

#################################
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
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
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

if [ -z "$VAST_PATH" ];then
 VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
fi
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi

cd "$VAST_PATH" || exit 1

#################################
# Configuration
#################################
FITSFILE="fastplot__img_2026-04-05_CI_Sgr-05-Q2b1x1_060342_TTUQ2b1x1_27846_Cz33e2vo__131133_fd_Sgr-05-Q2b1x1_2026-04-05_05-33-14_20.00sec_-4.90C_LIGHT_0256/reference_platesolved_FITS/wcs_Sgr-05-Q2b1x1_2026-03-26_06-11-57_20.00sec_-15.00C_LIGHT_0682.fits"
TARGET_RA="19:32:43.67"
TARGET_DEC="-22:39:30.7"
FILTER="V"
N_RANDOM_STARS=1000

if [ ! -f "$FITSFILE" ];then
 echo "ERROR: test image not found: $FITSFILE" >&2
 exit 1
fi

echo "=============================================="
echo "Forced Photometry Test"
echo "=============================================="

#################################
# Clean previous data
#################################
echo ""
echo "Cleaning previous data..."
util/clean_data.sh

#################################
# Set up SExtractor config
#################################
echo ""
echo "Setting up SExtractor configuration..."
cp default.sex.telephoto_lens_vSTL default.sex

#################################
# Part 1: Forced photometry on target position
#################################
echo ""
echo "=============================================="
echo "Part 1: Forced photometry on target position"
echo "  RA=$TARGET_RA Dec=$TARGET_DEC"
echo "=============================================="
echo ""

util/forced_photometry.sh "$FITSFILE" "$TARGET_RA" "$TARGET_DEC" "$FILTER"
FORCED_EXIT=$?
if [ $FORCED_EXIT -ne 0 ];then
 echo "ERROR: forced photometry on target failed with exit code $FORCED_EXIT"
 exit 1
fi

#################################
# Part 2: Compare forced photometry with SExtractor
#         for 100 randomly selected stars
#################################
echo ""
echo "=============================================="
echo "Part 2: Comparing forced photometry vs SExtractor"
echo "  for $N_RANDOM_STARS randomly selected stars"
echo "=============================================="
echo ""

# The forced_photometry.sh run above already produced:
# - SExtractor catalog (wcs_*.cat)
# - Plate solution (wcs_*.cat.ucac5)
# - Calibration (calib.txt, calib.txt_param)
# We can reuse all of these.

# Find the WCS catalog produced by forced_photometry.sh
BASENAME_FITSFILE=$(basename "$FITSFILE")
WCS_CATALOG="wcs_${BASENAME_FITSFILE}.cat"
# Handle wcs_wcs_ prefix duplication
WCS_CATALOG="${WCS_CATALOG/wcs_wcs_/wcs_}"

if [ ! -s "$WCS_CATALOG" ];then
 echo "ERROR: SExtractor WCS catalog not found: $WCS_CATALOG" >&2
 exit 1
fi
echo "Using SExtractor catalog: $WCS_CATALOG"

# Read calibration zeropoint from calib.txt_param
# Format: fit_function p3 p2 p1 p0
if [ ! -s "calib.txt_param" ];then
 echo "ERROR: calib.txt_param not found" >&2
 exit 1
fi
CALIB_P0=$(awk '{print $5}' calib.txt_param)
CALIB_P1=$(awk '{print $4}' calib.txt_param)
CALIB_P2=$(awk '{print $3}' calib.txt_param)
echo "Calibration: cal_mag = ${CALIB_P2}*x^2 + ${CALIB_P1}*x + ${CALIB_P0}"

# Get aperture (reuse from forced_photometry.sh run -- it was already determined)
APERTURE=$(lib/sextract_single_image_noninteractive "$FITSFILE" 2>/dev/null)
echo "Aperture diameter: $APERTURE pixels"

# WCS catalog format (from correct_sextractor_wcs_catalog_using_xy2sky.sh):
#  $1=NUMBER $2=RA_deg $3=DEC_deg $4=X_IMAGE $5=Y_IMAGE
#  $6=FLUX $7=FLUX_ERR $8=MAG_APER $9=MAG_ERR $10=FLAGS

# Select good stars: unflagged ($10==0), moderate magnitude, away from edges
# Apply calibration to get SExtractor calibrated magnitude
# Then randomly pick N_RANDOM_STARS from these
echo ""
echo "Selecting $N_RANDOM_STARS random stars from SExtractor catalog..."

# Get image dimensions for edge exclusion
NAXIS1=$(lib/astrometry/get_image_dimentions "$FITSFILE" 2>/dev/null | awk '{print $2}')
NAXIS2=$(lib/astrometry/get_image_dimentions "$FITSFILE" 2>/dev/null | awk '{print $4}')
if [ -z "$NAXIS1" ] || [ -z "$NAXIS2" ];then
 echo "WARNING: could not determine image dimensions, using large defaults" >&2
 NAXIS1=9999
 NAXIS2=9999
fi
echo "Image dimensions: ${NAXIS1}x${NAXIS2}"

# Annulus outer radius sets the edge margin
EDGE_MARGIN=$(echo "$APERTURE" | awk '{printf "%.0f", 2.5 * $1 / 2.0 + 2}')
echo "Edge margin: $EDGE_MARGIN pixels"

# Filter good stars and randomly select N_RANDOM_STARS
# Requirements: flag==0, mag_err < 0.1 (well-measured), away from edges,
# instrumental mag between -15 and -5 (reasonable brightness range)
awk -v margin="$EDGE_MARGIN" -v nx="$NAXIS1" -v ny="$NAXIS2" \
    '{if ($10==0 && $9>0 && $9<0.1 && $8>-15 && $8<-5 && $4>margin && $4<nx-margin && $5>margin && $5<ny-margin) print}' \
    "$WCS_CATALOG" | shuf -n "$N_RANDOM_STARS" > forced_photometry_test_stars.tmp

N_SELECTED=$(wc -l < forced_photometry_test_stars.tmp)
echo "Selected $N_SELECTED stars for comparison"

if [ "$N_SELECTED" -lt 1 ];then
 echo "ERROR: no suitable stars found in catalog" >&2
 exit 1
fi

# Run forced photometry for each selected star and compare
echo ""
echo "Running forced photometry for each star and comparing..."
echo ""
printf "%-6s  %8s  %8s  %8s  %8s  %8s  %s\n" "#" "SEx_mag" "FP_C_mag" "FP_Py_mag" "dMag_C" "dMag_Py" "status"
echo "------  --------  --------  ---------  --------  --------  ------"

N_GOOD=0
N_FAIL=0
N_TESTED=0
SUM_DMAG_C=0
SUM_DMAG_C_SQ=0
SUM_DMAG_PY=0
SUM_DMAG_PY_SQ=0

while read -r LINE ; do
 N_TESTED=$((N_TESTED + 1))

 # Parse SExtractor catalog line
 RA_DEG=$(echo "$LINE" | awk '{print $2}')
 DEC_DEG=$(echo "$LINE" | awk '{print $3}')
 INST_MAG=$(echo "$LINE" | awk '{print $8}')

 # Compute SExtractor calibrated magnitude
 SEX_CAL_MAG=$(echo "$INST_MAG $CALIB_P2 $CALIB_P1 $CALIB_P0" | awk '{printf "%.4f", $2*$1*$1 + $3*$1 + $4}')

 # Convert RA/Dec from decimal degrees to sexagesimal for sky2xy
 RADEC_HMS=$(lib/deg2hms $RA_DEG $DEC_DEG)
 RA_HMS=$(echo "$RADEC_HMS" | awk '{print $1}')
 DEC_DMS=$(echo "$RADEC_HMS" | awk '{print $2}')

 # Run forced photometry C tool directly (reuse existing calibration + aperture)
 # We need pixel coordinates via sky2xy
 SKY2XY_OUT=$(lib/bin/sky2xy "$FITSFILE" $RA_HMS $DEC_DMS 2>/dev/null)
 if echo "$SKY2XY_OUT" | grep -q -e "off image" -e "offscale" ;then
  printf "%-6d  %8s  %8s  %9s  %8s  %8s  %s\n" "$N_TESTED" "$SEX_CAL_MAG" "---" "---" "---" "---" "off_image"
  N_FAIL=$((N_FAIL + 1))
  continue
 fi
 PIX_X=$(echo "$SKY2XY_OUT" | awk '{print $5}')
 PIX_Y=$(echo "$SKY2XY_OUT" | awk '{print $6}')

 # Run C forced photometry
 C_OUT=$(util/forced_photometry "$FITSFILE" $PIX_X $PIX_Y $APERTURE 2>/dev/null)
 C_MAG=$(echo "$C_OUT" | awk '{print $1}')
 C_STATUS=$(echo "$C_OUT" | awk '{print $3}')

 # Run Python forced photometry
 PY_OUT=$(util/forced_photometry.py "$FITSFILE" $PIX_X $PIX_Y $APERTURE 2>/dev/null)
 PY_MAG=$(echo "$PY_OUT" | awk '{print $1}')
 PY_STATUS=$(echo "$PY_OUT" | awk '{print $3}')

 if [ "$C_STATUS" != "detection" ] || [ "$PY_STATUS" != "detection" ];then
  printf "%-6d  %8s  %8s  %9s  %8s  %8s  %s\n" "$N_TESTED" "$SEX_CAL_MAG" "$C_MAG" "$PY_MAG" "---" "---" "C:$C_STATUS/Py:$PY_STATUS"
  N_FAIL=$((N_FAIL + 1))
  continue
 fi

 # Compute magnitude differences
 DMAG_C=$(echo "$SEX_CAL_MAG $C_MAG" | awk '{printf "%.4f", $2 - $1}')
 DMAG_PY=$(echo "$SEX_CAL_MAG $PY_MAG" | awk '{printf "%.4f", $2 - $1}')

 printf "%-6d  %8s  %8s  %9s  %8s  %8s  %s\n" "$N_TESTED" "$SEX_CAL_MAG" "$C_MAG" "$PY_MAG" "$DMAG_C" "$DMAG_PY" "ok"

 N_GOOD=$((N_GOOD + 1))
 SUM_DMAG_C=$(echo "$SUM_DMAG_C $DMAG_C" | awk '{printf "%.6f", $1 + $2}')
 SUM_DMAG_C_SQ=$(echo "$SUM_DMAG_C_SQ $DMAG_C" | awk '{printf "%.6f", $1 + $2*$2}')
 SUM_DMAG_PY=$(echo "$SUM_DMAG_PY $DMAG_PY" | awk '{printf "%.6f", $1 + $2}')
 SUM_DMAG_PY_SQ=$(echo "$SUM_DMAG_PY_SQ $DMAG_PY" | awk '{printf "%.6f", $1 + $2*$2}')

done < forced_photometry_test_stars.tmp

echo ""
echo "=============================================="
echo "Summary"
echo "=============================================="
echo "Stars tested:     $N_TESTED"
echo "Successful:       $N_GOOD"
echo "Failed/non-det:   $N_FAIL"

if [ "$N_GOOD" -gt 0 ];then
 MEAN_C=$(echo "$SUM_DMAG_C $N_GOOD" | awk '{printf "%.4f", $1/$2}')
 RMS_C=$(echo "$SUM_DMAG_C_SQ $SUM_DMAG_C $N_GOOD" | awk '{printf "%.4f", sqrt($1/$3 - ($2/$3)^2)}')
 MEAN_PY=$(echo "$SUM_DMAG_PY $N_GOOD" | awk '{printf "%.4f", $1/$2}')
 RMS_PY=$(echo "$SUM_DMAG_PY_SQ $SUM_DMAG_PY $N_GOOD" | awk '{printf "%.4f", sqrt($1/$3 - ($2/$3)^2)}')
 echo ""
 echo "Forced photometry (C)      vs SExtractor: mean offset = ${MEAN_C} mag, RMS = ${RMS_C} mag"
 echo "Forced photometry (Python) vs SExtractor: mean offset = ${MEAN_PY} mag, RMS = ${RMS_PY} mag"
 echo ""

 # Check C vs Python agreement
 CPYDIFF=$(echo "$MEAN_C $MEAN_PY" | awk '{d=$1-$2; if(d<0) d=-d; printf "%.4f", d}')
 echo "C vs Python mean offset difference: $CPYDIFF mag"

 # Pass/fail criteria
 PASS=1
 # Check that C and Python agree within 0.01 mag
 # (small differences expected due to independent implementations of
 # the iterative sigma-clipping convergence)
 TEST=$(echo "$CPYDIFF" | awk '{if($1 < 0.01) print 1; else print 0}')
 if [ "$TEST" -eq 0 ];then
  echo "FAIL: C and Python implementations disagree by more than 0.01 mag"
  PASS=0
 else
  echo "PASS: C and Python implementations agree within 0.01 mag"
 fi

 # Check that mean offset from SExtractor is within 0.1 mag
 TEST_C=$(echo "$MEAN_C" | awk '{if($1<0) $1=-$1; if($1 < 0.1) print 1; else print 0}')
 if [ "$TEST_C" -eq 0 ];then
  echo "FAIL: C forced photometry mean offset from SExtractor exceeds 0.1 mag"
  PASS=0
 else
  echo "PASS: C forced photometry mean offset from SExtractor within 0.1 mag"
 fi

 if [ "$PASS" -eq 1 ];then
  echo ""
  echo "*** ALL TESTS PASSED ***"
 else
  echo ""
  echo "*** SOME TESTS FAILED ***"
 fi
fi

# Clean up temp file
rm -f forced_photometry_test_stars.tmp

echo ""
