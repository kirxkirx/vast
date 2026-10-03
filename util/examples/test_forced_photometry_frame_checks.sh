#!/usr/bin/env bash
#
# Standalone test for the frame-level sanity checks of util/forced_photometry
# that FORCED_PHOTOMETRY_FRAME_CHECKS=yes turns on (see the comment above
# wcs_is_tan_only_wide_field() in src/forced_photometry.c).
#
# Verifies:
#   1. Without FORCED_PHOTOMETRY_FRAME_CHECKS nothing changes, even on a
#      TAN-only plate solution or with a star catalog that has a hole
#   2. With the checks on, a position with plenty of catalog stars around it
#      on the SIP-solved image keeps its status and magnitude
#   3. A TAN-only copy of the (16 deg wide) test image gives the status
#      bad_wcs, keeping the measured magnitude; FORCED_PHOTOMETRY_WCS_IMAGE
#      makes the check judge the plate solution it names instead
#   4. Fewer than FORCED_PHOTOMETRY_STAR_COVERAGE_MIN_STARS catalog stars within
#      FORCED_PHOTOMETRY_STAR_COVERAGE_RADIUS_ARCSEC of the position give the
#      status no_nearby_stars, keeping the measured magnitude; exactly
#      MIN_STARS stars pass
#   5. A catalog too sparse for the test (fewer than
#      FORCED_PHOTOMETRY_STAR_COVERAGE_MIN_EXPECTED stars expected per circle)
#      leaves the status alone
#   6. --list mode applies the checks per position
#   7. The catalog is found next to the image without
#      FORCED_PHOTOMETRY_STAR_CATALOG; with no catalog at all the coverage
#      test is skipped
#   8. Catalog lines with non-finite or absurd positions are ignored
#   9. Clouds over most of the frame do not switch the test off
#
# No network access, no plate solving and no SExtractor run: the magnitude
# calibration is a fixed linear relation and the star catalogs are synthetic
# grids of positions in the .wcscat layout. The thresholds are read from
# src/vast_limits.h. Run from the VaST top directory; uses the NMW
# telephoto-lens test image of util/examples/test_vast.sh.

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################
# Settings inherited from the caller's environment would change the results
unset FORCED_PHOTOMETRY_FRAME_CHECKS FORCED_PHOTOMETRY_WCS_IMAGE FORCED_PHOTOMETRY_STAR_CATALOG FORCED_PHOTOMETRY_EDGE_MARGIN_PIX

FPFC_IMAGE_NAME="wcs_Sgr-05-Q2b1x1_2026-03-26_06-11-57_20.00sec_-15.00C_LIGHT_0682.fits"
FPFC_IMAGE="../individual_images_test/$FPFC_IMAGE_NAME"
FPFC_IMAGE_URL="http://tau.kirx.net/vast_test_data/$FPFC_IMAGE_NAME.bz2"
FPFC_TARGET_RA="19:32:43.67"
FPFC_TARGET_DEC="-22:39:30.7"
FPFC_APERTURE="6.0"

TEST_PASSED=1
FAILED_TEST_CODES=""

echo "######### Forced photometry frame-level checks test #########" >&2
THIS_TEST_START_UNIXSEC=$(date +%s)

# Download the test image if missing
if [ ! -f "$FPFC_IMAGE" ];then
 echo "Downloading test image..." >&2
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 ( cd ../individual_images_test && \
   curl --silent --show-error -O "$FPFC_IMAGE_URL" && \
   bunzip2 "$FPFC_IMAGE_NAME.bz2" )
fi
if [ ! -f "$FPFC_IMAGE" ];then
 echo "Test image $FPFC_IMAGE not available; skipping test." >&2
 exit 1
fi
for FPFC_TOOL in util/forced_photometry util/listhead util/modhead lib/bin/sky2xy lib/astrometry/strip_wcs_keywords ;do
 if [ ! -x "$FPFC_TOOL" ];then
  echo "$FPFC_TOOL is not built; skipping test." >&2
  exit 1
 fi
done

FPFC_VAST_DIR="$PWD"
FPFC_IMAGE_ABS="$FPFC_VAST_DIR/$FPFC_IMAGE"

# Thresholds of the checks, from the header the C tool is compiled with
FPFC_MIN_STARS=$(awk '$1=="#define" && $2=="FORCED_PHOTOMETRY_STAR_COVERAGE_MIN_STARS" {print $3}' src/vast_limits.h)
FPFC_MIN_EXPECTED=$(awk '$1=="#define" && $2=="FORCED_PHOTOMETRY_STAR_COVERAGE_MIN_EXPECTED" {print $3}' src/vast_limits.h)
FPFC_RADIUS_ARCSEC=$(awk '$1=="#define" && $2=="FORCED_PHOTOMETRY_STAR_COVERAGE_RADIUS_ARCSEC" {print $3}' src/vast_limits.h)
if [ -z "$FPFC_MIN_STARS" ] || [ -z "$FPFC_MIN_EXPECTED" ] || [ -z "$FPFC_RADIUS_ARCSEC" ];then
 echo "Cannot read the star coverage thresholds from src/vast_limits.h" >&2
 echo "Failure codes: FPFC000_NO_THRESHOLDS"
 exit 1
fi

# The image geometry and the target position
FPFC_NAXIS1=$(util/listhead "$FPFC_IMAGE" | awk '$1=="NAXIS1" {print $3}')
FPFC_NAXIS2=$(util/listhead "$FPFC_IMAGE" | awk '$1=="NAXIS2" {print $3}')
FPFC_PIXSCALE=$(util/listhead "$FPFC_IMAGE" | awk '$1=="CD1_1" {a=$3} $1=="CD1_2" {b=$3} $1=="CD2_1" {c=$3} $1=="CD2_2" {d=$3} END {det=a*d-b*c; if (det<0) det=-det; printf "%.6f", 3600.0*sqrt(det)}')
FPFC_XY=$(lib/bin/sky2xy "$FPFC_IMAGE" "$FPFC_TARGET_RA" "$FPFC_TARGET_DEC" 2>/dev/null | awk '{print $5" "$6}')
FPFC_X=$(echo "$FPFC_XY" | awk '{print $1}')
FPFC_Y=$(echo "$FPFC_XY" | awk '{print $2}')
if [ -z "$FPFC_NAXIS1" ] || [ -z "$FPFC_NAXIS2" ] || [ -z "$FPFC_X" ] || [ -z "$FPFC_Y" ];then
 echo "Cannot read the geometry of $FPFC_IMAGE or place the target on it" >&2
 echo "Failure codes: FPFC000_NO_GEOMETRY"
 exit 1
fi
# The test circle radius in pixels, a second position far from the target
# (for --list mode) and the grid spacings of the dense and sparse catalogs:
# a dense grid puts about 200 stars into the circle, a sparse one half of
# MIN_EXPECTED
FPFC_RADIUS_PIX=$(echo "$FPFC_RADIUS_ARCSEC $FPFC_PIXSCALE" | awk '{printf "%.2f", $1/$2}')
FPFC_X2=$(echo "$FPFC_X $FPFC_NAXIS1" | awk '{x=$1-3000; if (x<1000) x=$1+3000; if (x>$2-1000) x=$2/2; printf "%.3f", x}')
FPFC_Y2=$(echo "$FPFC_NAXIS2" | awk '{printf "%.3f", $1/2}')
FPFC_DENSE_SPACING=$(echo "$FPFC_RADIUS_PIX" | awk '{printf "%.3f", $1/8.0}')
FPFC_SPARSE_SPACING=$(echo "$FPFC_RADIUS_PIX $FPFC_MIN_EXPECTED" | awk '{printf "%.3f", $1*sqrt(3.14159265/(0.5*$2))}')
echo "Target at ($FPFC_X, $FPFC_Y) on a ${FPFC_NAXIS1}x${FPFC_NAXIS2} frame, ${FPFC_PIXSCALE}\"/pix: test radius $FPFC_RADIUS_PIX pix, MIN_STARS=$FPFC_MIN_STARS MIN_EXPECTED=$FPFC_MIN_EXPECTED" >&2

FPFC_WORKDIR="fpfc_test_workdir_$$"
rm -rf "$FPFC_WORKDIR"
mkdir "$FPFC_WORKDIR" || exit 1
cd "$FPFC_WORKDIR" || exit 1
# util/forced_photometry reads default.sex (SATUR_LEVEL) and bad_region.lst
# from the current directory: an empty working directory keeps the test
# independent of whatever the VaST directory holds
cp "$FPFC_VAST_DIR/default.sex.telephoto_lens_vSTL" default.sex
echo "4 0.0 0.0 1.0 25.0" > fpfc_calib.txt_param
ln -s "$FPFC_IMAGE_ABS" wcs_fpfc_sip.fits

# Synthetic star catalog in the .wcscat layout (the pixel position is in
# columns 4 and 5): a square grid with the given spacing, optionally an
# empty hole of radius 1.2*R around (x, y) with n_in stars put back into it
# at 0.5*R from (x, y), optionally only up to x_max (a cloud over the rest)
# Arguments: output_file spacing hole(0|1) n_in x y [x_max]
fpfc_make_catalog() {
 awk -v nx="$FPFC_NAXIS1" -v ny="$FPFC_NAXIS2" -v s="$2" -v hole="$3" -v nin="$4" -v cx="$5" -v cy="$6" -v r="$FPFC_RADIUS_PIX" -v xmax="${7:-$FPFC_NAXIS1}" 'BEGIN {
  n=0
  for (x=s/2.0; x<nx && x<=xmax; x+=s) {
   for (y=s/2.0; y<ny; y+=s) {
    dx=x-cx; dy=y-cy
    if (hole==1 && dx*dx+dy*dy < 1.44*r*r) continue
    n++
    printf "%d 0.0 0.0 %.3f %.3f -10.0 0.01 0.0 0.0 0\n", n, x, y
   }
  }
  for (i=0; i<nin; i++) {
   a=6.28318531*i/nin
   n++
   printf "%d 0.0 0.0 %.3f %.3f -10.0 0.01 0.0 0.0 0\n", n, cx+0.5*r*cos(a), cy+0.5*r*sin(a)
  }
 }' > "$1"
}
FPFC_MIN_STARS_MINUS_ONE=$((FPFC_MIN_STARS - 1))
fpfc_make_catalog fpfc_dense.wcscat "$FPFC_DENSE_SPACING" 0 0 "$FPFC_X" "$FPFC_Y"
fpfc_make_catalog fpfc_hole.wcscat "$FPFC_DENSE_SPACING" 1 0 "$FPFC_X" "$FPFC_Y"
fpfc_make_catalog fpfc_hole_below.wcscat "$FPFC_DENSE_SPACING" 1 "$FPFC_MIN_STARS_MINUS_ONE" "$FPFC_X" "$FPFC_Y"
fpfc_make_catalog fpfc_hole_at.wcscat "$FPFC_DENSE_SPACING" 1 "$FPFC_MIN_STARS" "$FPFC_X" "$FPFC_Y"
fpfc_make_catalog fpfc_sparse_hole.wcscat "$FPFC_SPARSE_SPACING" 1 0 "$FPFC_X" "$FPFC_Y"
# Clouds over 60% of the frame, the target under them
FPFC_CLEAR_XMAX=$(echo "$FPFC_NAXIS1" | awk '{printf "%.1f", 0.4*$1}')
fpfc_make_catalog fpfc_mostly_cloudy.wcscat "$FPFC_DENSE_SPACING" 0 0 "$FPFC_X" "$FPFC_Y" "$FPFC_CLEAR_XMAX"

# A TAN-only copy of the image: the same linear solution, no SIP polynomial
cp "$FPFC_IMAGE_ABS" wcs_fpfc_tan.fits
"$FPFC_VAST_DIR/util/listhead" wcs_fpfc_tan.fits | awk '$1=="CRPIX1" || $1=="CRPIX2" || $1=="CRVAL1" || $1=="CRVAL2" || $1=="CD1_1" || $1=="CD1_2" || $1=="CD2_1" || $1=="CD2_2" {print $1, $3}' > fpfc_linear_wcs.txt
"$FPFC_VAST_DIR/lib/astrometry/strip_wcs_keywords" wcs_fpfc_tan.fits > /dev/null 2>&1
"$FPFC_VAST_DIR/util/modhead" wcs_fpfc_tan.fits CTYPE1 "'RA---TAN'" > /dev/null 2>&1
"$FPFC_VAST_DIR/util/modhead" wcs_fpfc_tan.fits CTYPE2 "'DEC--TAN'" > /dev/null 2>&1
while read -r FPFC_KEY FPFC_VALUE ;do
 "$FPFC_VAST_DIR/util/modhead" wcs_fpfc_tan.fits "$FPFC_KEY" "$FPFC_VALUE" > /dev/null 2>&1
done < fpfc_linear_wcs.txt
if [ "$(grep -c '' fpfc_linear_wcs.txt)" -ne 8 ] || \
   [ "$("$FPFC_VAST_DIR/util/listhead" wcs_fpfc_tan.fits | grep -c -e '^A_ORDER' -e '^CTYPE[12] .*SIP')" -ne 0 ] || \
   [ "$("$FPFC_VAST_DIR/util/listhead" wcs_fpfc_tan.fits | grep -c -e '^CTYPE1  = .RA---TAN' -e '^CD2_2 ')" -ne 2 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES FPFC001_CANNOT_MAKE_TAN_ONLY_COPY"
fi

# One measurement: prints "mag err status" (single position)
# Arguments: image [environment assignments...]
fpfc_measure() {
 local IMAGE="$1"
 shift
 env "$@" "$FPFC_VAST_DIR/util/forced_photometry" "$IMAGE" "$FPFC_X" "$FPFC_Y" "$FPFC_APERTURE" --calib fpfc_calib.txt_param 2> fpfc_last_stderr.txt
}

# Compare one measurement with the expected status; the magnitude and error
# must equal those of the reference measurement (the checks keep them)
# Arguments: code expected_status measured_line
fpfc_expect() {
 local CODE="$1"
 local EXPECTED_STATUS="$2"
 local LINE="$3"
 local STATUS MAGERR
 STATUS=$(echo "$LINE" | awk '{print $3}')
 MAGERR=$(echo "$LINE" | awk '{print $1, $2}')
 if [ "$STATUS" != "$EXPECTED_STATUS" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ${CODE}_STATUS_${STATUS:-none}"
  echo "$CODE: expected status $EXPECTED_STATUS, got '$LINE'" >&2
 elif [ "$MAGERR" != "$FPFC_REF_MAGERR" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES ${CODE}_VALUES_CHANGED"
  echo "$CODE: the measured values changed: '$LINE' vs '$FPFC_REF'" >&2
 else
  echo "$CODE: OK ($LINE)" >&2
 fi
}

#################################
# The reference measurement: no checks
#################################
FPFC_REF=$(fpfc_measure wcs_fpfc_sip.fits)
FPFC_REF_STATUS=$(echo "$FPFC_REF" | awk '{print $3}')
FPFC_REF_MAGERR=$(echo "$FPFC_REF" | awk '{print $1, $2}')
echo "Reference measurement without the checks: $FPFC_REF" >&2
if [ "$FPFC_REF_STATUS" != "detection" ] && [ "$FPFC_REF_STATUS" != "upperlimit" ];then
 # Nothing below can be tested: the checks only judge these two statuses
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES FPFC002_REFERENCE_STATUS_${FPFC_REF_STATUS:-none}"
else
 # 1. The checks are off unless requested
 fpfc_expect FPFC003_TAN_ONLY_CHECKS_OFF "$FPFC_REF_STATUS" "$(fpfc_measure wcs_fpfc_tan.fits)"
 fpfc_expect FPFC004_HOLE_CHECKS_OFF "$FPFC_REF_STATUS" "$(fpfc_measure wcs_fpfc_sip.fits FORCED_PHOTOMETRY_STAR_CATALOG=fpfc_hole.wcscat)"
 # 2. Plenty of stars around the position on the SIP-solved image
 fpfc_expect FPFC005_DENSE_CATALOG "$FPFC_REF_STATUS" "$(fpfc_measure wcs_fpfc_sip.fits FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_STAR_CATALOG=fpfc_dense.wcscat)"
 grep -q "Local star coverage at" fpfc_last_stderr.txt || {
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FPFC006_NO_COVERAGE_REPORT"
 }
 # 3. The TAN-only plate solution of a wide field
 fpfc_expect FPFC007_TAN_ONLY bad_wcs "$(fpfc_measure wcs_fpfc_tan.fits FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_STAR_CATALOG=fpfc_dense.wcscat)"
 fpfc_expect FPFC008_TAN_ONLY_PIXELS_SIP_WCS "$FPFC_REF_STATUS" "$(fpfc_measure wcs_fpfc_tan.fits FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_WCS_IMAGE=wcs_fpfc_sip.fits FORCED_PHOTOMETRY_STAR_CATALOG=fpfc_dense.wcscat)"
 fpfc_expect FPFC009_SIP_PIXELS_TAN_ONLY_WCS bad_wcs "$(fpfc_measure wcs_fpfc_sip.fits FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_WCS_IMAGE=wcs_fpfc_tan.fits FORCED_PHOTOMETRY_STAR_CATALOG=fpfc_dense.wcscat)"
 # 4. No stars around the position, and the MIN_STARS boundary
 fpfc_expect FPFC010_EMPTY_HOLE no_nearby_stars "$(fpfc_measure wcs_fpfc_sip.fits FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_STAR_CATALOG=fpfc_hole.wcscat)"
 fpfc_expect FPFC011_BELOW_MIN_STARS no_nearby_stars "$(fpfc_measure wcs_fpfc_sip.fits FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_STAR_CATALOG=fpfc_hole_below.wcscat)"
 fpfc_expect FPFC012_AT_MIN_STARS "$FPFC_REF_STATUS" "$(fpfc_measure wcs_fpfc_sip.fits FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_STAR_CATALOG=fpfc_hole_at.wcscat)"
 # 5. A catalog too sparse to tell a hole from a sparse patch of sky
 fpfc_expect FPFC013_SPARSE_CATALOG "$FPFC_REF_STATUS" "$(fpfc_measure wcs_fpfc_sip.fits FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_STAR_CATALOG=fpfc_sparse_hole.wcscat)"
 grep -q "local star coverage test not applied" fpfc_last_stderr.txt || {
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FPFC014_NO_NOT_APPLIED_NOTE"
 }
 # 7. The catalog next to the image is found without FORCED_PHOTOMETRY_STAR_CATALOG
 cp fpfc_hole.wcscat wcs_fpfc_sip.fits.wcscat
 fpfc_expect FPFC015_CATALOG_NEXT_TO_IMAGE no_nearby_stars "$(fpfc_measure wcs_fpfc_sip.fits FORCED_PHOTOMETRY_FRAME_CHECKS=yes)"
 rm -f wcs_fpfc_sip.fits.wcscat
 fpfc_expect FPFC016_NO_CATALOG "$FPFC_REF_STATUS" "$(fpfc_measure wcs_fpfc_sip.fits FORCED_PHOTOMETRY_FRAME_CHECKS=yes)"
 grep -q "no detection catalog" fpfc_last_stderr.txt || {
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FPFC017_NO_SKIPPED_NOTE"
 }
 # Neither check may print the word the pipelines scan their logs for
 for FPFC_CATALOG in fpfc_hole.wcscat fpfc_sparse_hole.wcscat ;do
  env FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_STAR_CATALOG="$FPFC_CATALOG" "$FPFC_VAST_DIR/util/forced_photometry" wcs_fpfc_tan.fits "$FPFC_X" "$FPFC_Y" "$FPFC_APERTURE" --calib fpfc_calib.txt_param > /dev/null 2>> fpfc_all_stderr.txt
  env FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_STAR_CATALOG="$FPFC_CATALOG" "$FPFC_VAST_DIR/util/forced_photometry" wcs_fpfc_sip.fits "$FPFC_X" "$FPFC_Y" "$FPFC_APERTURE" --calib fpfc_calib.txt_param > /dev/null 2>> fpfc_all_stderr.txt
 done
 if grep -q 'ERROR' fpfc_all_stderr.txt ;then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FPFC018_ERROR_WORD_IN_STDERR"
 fi
 # 8. Non-finite and absurd catalog positions are ignored (they used to index
 # the density cells out of bounds)
 cp fpfc_dense.wcscat fpfc_nonfinite.wcscat
 printf '999991 0.0 0.0 nan 100.0 -10.0 0.01 0.0 0.0 0\n999992 0.0 0.0 100.0 inf -10.0 0.01 0.0 0.0 0\n999993 0.0 0.0 1e30 -1e30 -10.0 0.01 0.0 0.0 0\n999994 0.0 0.0 -nan -nan -10.0 0.01 0.0 0.0 0\n' >> fpfc_nonfinite.wcscat
 fpfc_expect FPFC021_NONFINITE_CATALOG "$FPFC_REF_STATUS" "$(fpfc_measure wcs_fpfc_sip.fits FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_STAR_CATALOG=fpfc_nonfinite.wcscat)"
 # 9. Clouds over 60% of the frame: the frame's mean star density still says
 # stars are expected around the target (the median would have been zero)
 fpfc_expect FPFC022_MOSTLY_CLOUDY_FRAME no_nearby_stars "$(fpfc_measure wcs_fpfc_sip.fits FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_STAR_CATALOG=fpfc_mostly_cloudy.wcscat)"
 # 6. --list mode: the target in the hole, a second position far from it
 printf '%s %s target\n%s %s far\n' "$FPFC_X" "$FPFC_Y" "$FPFC_X2" "$FPFC_Y2" > fpfc_positions.txt
 env FORCED_PHOTOMETRY_FRAME_CHECKS=yes FORCED_PHOTOMETRY_STAR_CATALOG=fpfc_hole.wcscat "$FPFC_VAST_DIR/util/forced_photometry" wcs_fpfc_sip.fits --list fpfc_positions.txt "$FPFC_APERTURE" --calib fpfc_calib.txt_param > fpfc_list_out.txt 2> /dev/null
 FPFC_LIST_TARGET=$(awk '$1=="target" {print $4, $5, $6}' fpfc_list_out.txt)
 FPFC_LIST_FAR_STATUS=$(awk '$1=="far" {print $6}' fpfc_list_out.txt)
 fpfc_expect FPFC019_LIST_TARGET no_nearby_stars "$FPFC_LIST_TARGET"
 if [ "$FPFC_LIST_FAR_STATUS" != "detection" ] && [ "$FPFC_LIST_FAR_STATUS" != "upperlimit" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FPFC020_LIST_FAR_STATUS_${FPFC_LIST_FAR_STATUS:-none}"
 fi
fi

#################################
# Cleanup
#################################
cd "$FPFC_VAST_DIR" || exit 1
rm -rf "$FPFC_WORKDIR"

#################################
# Summary
#################################
THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

if [ "$TEST_PASSED" -eq 1 ];then
 echo -e "\n\033[01;34mForced photometry frame-level checks test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)"
 exit 0
else
 echo -e "\n\033[01;34mForced photometry frame-level checks test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)"
 echo "Failure codes:$FAILED_TEST_CODES"
 exit 1
fi
