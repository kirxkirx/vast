#!/usr/bin/env bash
#
# Quick functional test for util/pixel_flux_airmass_correction - the tool that corrects
# image pixel counts for differential atmospheric extinction (airmass changing across
# a wide field of view).
#
# The test uses the NMW_Sgr1_NovaSgr20N4_test dataset (a low-altitude Sagittarius field):
# the second-epoch images carry an approximate PinPoint TAN WCS and SITELAT/SITELONG
# keywords, the reference images carry an Astrometry.net TAN-SIP solution.
#

FAILED_TEST_CODES=""
TEST_PASSED=1

# Make sure we are in the VaST root directory
if [ ! -f src/pixel_flux_airmass_correction.c ];then
 cd "$(dirname "$0")/../.." || exit 1
fi
if [ ! -f src/pixel_flux_airmass_correction.c ];then
 echo "ERROR: cannot find the VaST root directory"
 exit 1
fi

if [ ! -x util/pixel_flux_airmass_correction ];then
 echo "ERROR: util/pixel_flux_airmass_correction is not found or not executable - please run 'make'"
 exit 1
fi

# Get the test dataset if it's not already here
TEST_DATA_DIR="../NMW_Sgr1_NovaSgr20N4_test"
if [ ! -d "$TEST_DATA_DIR" ];then
 WORKDIR="$PWD"
 cd .. || exit 1
 curl --silent --show-error -O "http://tau.kirx.net/vast_test_data/NMW_Sgr1_NovaSgr20N4_test.tar.bz2" && tar -xjf NMW_Sgr1_NovaSgr20N4_test.tar.bz2
 cd "$WORKDIR" || exit 1
fi
if [ ! -d "$TEST_DATA_DIR" ];then
 echo "ERROR: cannot get the test dataset $TEST_DATA_DIR"
 exit 1
fi

REF_IMAGE=$(ls "$TEST_DATA_DIR"/reference_images/*.fts 2>/dev/null | head -n 1)
NEW_IMAGE=$(ls "$TEST_DATA_DIR"/second_epoch_images/*.fts 2>/dev/null | head -n 1)
if [ -z "$REF_IMAGE" ] || [ -z "$NEW_IMAGE" ];then
 echo "ERROR: cannot find the test images in $TEST_DATA_DIR"
 exit 1
fi

TEST_TMPDIR="pixel_flux_airmass_correction_test_tmp$$"
mkdir "$TEST_TMPDIR" || exit 1
trap 'rm -rf "$TEST_TMPDIR"' EXIT

##### --print-info on a plate-solved reference image #####
echo "Check: --print-info on the reference image"
if ! util/pixel_flux_airmass_correction --print-info "$REF_IMAGE" > "$TEST_TMPDIR/printinfo.out" 2> "$TEST_TMPDIR/printinfo.err" ;then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_PRINTINFO_EXIT_CODE"
fi
CENTER_AIRMASS=$(awk '/^Frame center: alt=/ {print $NF}' "$TEST_TMPDIR/printinfo.out")
if [ -z "$CENTER_AIRMASS" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_PRINTINFO_NO_AIRMASS"
else
 if [ "$(echo "$CENTER_AIRMASS" | awk '{if ( $1 > 1.0 && $1 < 40.0 ) print 1; else print 0}')" != "1" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_PRINTINFO_AIRMASS_RANGE_$CENTER_AIRMASS"
 fi
fi

##### default correction run on a second-epoch image #####
echo "Check: correcting a second-epoch image (default k)"
CORRECTED_IMAGE="$TEST_TMPDIR/ac_second_epoch.fits"
if ! util/pixel_flux_airmass_correction "$NEW_IMAGE" "$CORRECTED_IMAGE" > "$TEST_TMPDIR/correct.out" 2> "$TEST_TMPDIR/correct.err" ;then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_CORRECT_EXIT_CODE"
fi
if [ ! -f "$CORRECTED_IMAGE" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_CORRECT_NO_OUTPUT"
 echo "The corrected image was not created - cannot run the remaining checks"
 echo "Failed test codes: $FAILED_TEST_CODES"
 exit 1
fi
INPUT_BITPIX=$(util/listhead "$NEW_IMAGE" 2>/dev/null | awk '$1=="BITPIX" {print $3}')
OUTPUT_BITPIX=$(util/listhead "$CORRECTED_IMAGE" 2>/dev/null | awk '$1=="BITPIX" {print $3}')
if [ "$INPUT_BITPIX" != "$OUTPUT_BITPIX" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_BITPIX_NOT_PRESERVED_${INPUT_BITPIX}_${OUTPUT_BITPIX}"
fi
INPUT_NAXIS1=$(util/listhead "$NEW_IMAGE" 2>/dev/null | awk '$1=="NAXIS1" {print $3}')
OUTPUT_NAXIS1=$(util/listhead "$CORRECTED_IMAGE" 2>/dev/null | awk '$1=="NAXIS1" {print $3}')
if [ "$INPUT_NAXIS1" != "$OUTPUT_NAXIS1" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_NAXIS1_CHANGED"
fi
if ! util/listhead "$CORRECTED_IMAGE" 2>/dev/null | grep -q 'Airmass flux correction applied by VaST pixel_flux_airmass_correction' ;then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_NO_HISTORY_RECORD"
fi

##### double-correction protection #####
echo "Check: double-correction protection"
if util/pixel_flux_airmass_correction "$CORRECTED_IMAGE" "$TEST_TMPDIR/ac_ac.fits" > /dev/null 2>&1 ;then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_DOUBLE_CORRECTION_NOT_REFUSED"
fi
if ! util/pixel_flux_airmass_correction --force "$CORRECTED_IMAGE" "$TEST_TMPDIR/ac_ac.fits" > /dev/null 2>&1 ;then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_FORCE_NOT_WORKING"
fi

##### k=0 should reproduce the input pixel values #####
echo "Check: k=0 run reproduces the input image"
K0_IMAGE="$TEST_TMPDIR/k0.fits"
if ! util/pixel_flux_airmass_correction -k 0.0 "$NEW_IMAGE" "$K0_IMAGE" > /dev/null 2>&1 ;then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_K0_EXIT_CODE"
else
 for STATKEY in MIN= MAX= MEDIAN= ;do
  STAT_INPUT=$(util/imstat_vast "$NEW_IMAGE" 2>/dev/null | awk -v key="$STATKEY" '$1==key {print $2}')
  STAT_K0=$(util/imstat_vast "$K0_IMAGE" 2>/dev/null | awk -v key="$STATKEY" '$1==key {print $2}')
  if [ -z "$STAT_INPUT" ] || [ -z "$STAT_K0" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_K0_NO_IMSTAT_$STATKEY"
   continue
  fi
  if [ "$(echo "$STAT_INPUT $STAT_K0" | awk '{d=$1-$2; if(d<0)d=-d; if(d<0.01) print 1; else print 0}')" != "1" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_K0_PIXELS_CHANGED_${STATKEY}${STAT_INPUT}_vs_${STAT_K0}"
  fi
 done
fi

##### command-line site coordinates override #####
echo "Check: --sitelat/--sitelong override"
if ! util/pixel_flux_airmass_correction --print-info --sitelat '43 38 58' --sitelong '41 25 34' "$NEW_IMAGE" > "$TEST_TMPDIR/override.out" 2>/dev/null ;then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_SITE_OVERRIDE_EXIT_CODE"
fi
if ! grep '^Observing site:' "$TEST_TMPDIR/override.out" | grep -q 'command line' ;then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_SITE_OVERRIDE_NOT_APPLIED"
fi

##### an image without a WCS must be refused with a plate-solve suggestion #####
# (the second Sgr1 second-epoch frame carries no WCS in its header)
echo "Check: image without WCS is refused"
NOWCS_IMAGE=$(ls "$TEST_DATA_DIR"/second_epoch_images/*.fts 2>/dev/null | sed -n 2p)
if [ -n "$NOWCS_IMAGE" ];then
 if ! util/listhead "$NOWCS_IMAGE" 2>/dev/null | grep -q '^CTYPE1' ;then
  if util/pixel_flux_airmass_correction "$NOWCS_IMAGE" "$TEST_TMPDIR/nowcs.fits" > /dev/null 2> "$TEST_TMPDIR/nowcs.err" ;then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_NOWCS_NOT_REFUSED"
  fi
  if ! grep -q 'plate-solve' "$TEST_TMPDIR/nowcs.err" ;then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_NOWCS_NO_HINT"
  fi
 fi
fi

##### delta-mag map output #####
echo "Check: --map output"
if ! util/pixel_flux_airmass_correction --map "$TEST_TMPDIR/map.fits" "$NEW_IMAGE" "$TEST_TMPDIR/ac_with_map.fits" > /dev/null 2>&1 ;then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_MAP_EXIT_CODE"
fi
MAP_BITPIX=$(util/listhead "$TEST_TMPDIR/map.fits" 2>/dev/null | awk '$1=="BITPIX" {print $3}')
if [ "$MAP_BITPIX" != "-32" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_MAP_BITPIX_$MAP_BITPIX"
fi

##### the WCS should survive the correction #####
echo "Check: WCS preservation"
if [ -x lib/bin/xy2sky ];then
 XY2SKY_INPUT=$(lib/bin/xy2sky -d "$NEW_IMAGE" 1000 1000 2>/dev/null | awk '{print $1" "$2}')
 XY2SKY_OUTPUT=$(lib/bin/xy2sky -d "$CORRECTED_IMAGE" 1000 1000 2>/dev/null | awk '{print $1" "$2}')
 if [ -z "$XY2SKY_INPUT" ] || [ "$XY2SKY_INPUT" != "$XY2SKY_OUTPUT" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_WCS_NOT_PRESERVED"
 fi
else
 echo "lib/bin/xy2sky is not found - skipping the WCS preservation check"
fi

##### airmass-aware zero-point fit mode (--fit-airmass-zeropoint) #####
# Synthetic inputs with known truth: a grid of fake stars across the solved
# reference image, catalog mags built with zero-point 25.0 and k_true=0.2.
echo "Check: --fit-airmass-zeropoint recovers a synthetic k=0.2"
awk 'BEGIN {for (x=100; x<=3200; x+=200) for (y=100; y<=2400; y+=200) print x, y}' > "$TEST_TMPDIR/syn_xy.txt"
util/pixel_flux_airmass_correction -k 1 --predict-list "$TEST_TMPDIR/syn_xy.txt" "$REF_IMAGE" 2>/dev/null | awk 'f {print $1, $2, $4} /^# X_pix/ {f=1}' > "$TEST_TMPDIR/syn_xya.txt"
awk -v dir="$TEST_TMPDIR" '{i++; mag=-14.0+i*0.0037; printf "%d 100.0 10.0 %.4f %.4f 1000 10 %.4f 0.01 0\n", i, $1, $2, mag > (dir"/syn.wcscat"); printf "%.4f %.4f 0.01\n", mag, mag+25.0-0.2*$3 > (dir"/syn_calib.txt")}' "$TEST_TMPDIR/syn_xya.txt"
echo "3 0.0 0.0 1.0 25.0" > "$TEST_TMPDIR/syn_calib.txt_param"
SYN_FIT_LINE=$(util/pixel_flux_airmass_correction --fit-airmass-zeropoint --calib-param "$TEST_TMPDIR/syn_calib.txt_param" --fit-table "$TEST_TMPDIR/syn_table.txt" "$TEST_TMPDIR/syn_calib.txt" "$TEST_TMPDIR/syn.wcscat" "$REF_IMAGE" 2>/dev/null)
if [ "$(echo "$SYN_FIT_LINE" | awk '{print $1}')" != "OK" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_FITMODE_NOT_OK_$(echo "$SYN_FIT_LINE" | awk '{print $1}')"
else
 if [ "$(echo "$SYN_FIT_LINE" | awk '{k=$5; d=k-0.2; if(d<0)d=-d; if (d<0.005) print 1; else print 0}')" != "1" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_FITMODE_WRONG_K_$(echo "$SYN_FIT_LINE" | awk '{print $5}')"
 fi
 if [ "$(echo "$SYN_FIT_LINE" | awk '{d=$2; if(d<0)d=-d; if (d<0.01) print 1; else print 0}')" != "1" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_FITMODE_WRONG_D0_$(echo "$SYN_FIT_LINE" | awk '{print $2}')"
 fi
fi
if [ ! -s "$TEST_TMPDIR/syn_table.txt" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_FITMODE_NO_TABLE"
fi

echo "Check: fit-mode gates (narrow-field provision)"
# too few stars
head -n 50 "$TEST_TMPDIR/syn_calib.txt" > "$TEST_TMPDIR/syn_calib_small.txt"
GATE_LINE=$(util/pixel_flux_airmass_correction --fit-airmass-zeropoint --calib-param "$TEST_TMPDIR/syn_calib.txt_param" "$TEST_TMPDIR/syn_calib_small.txt" "$TEST_TMPDIR/syn.wcscat" "$REF_IMAGE" 2>/dev/null)
if [ "$(echo "$GATE_LINE" | awk '{print $1}')" != "REJECT_NO_POSITIONS" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_GATE_FEWSTARS_$(echo "$GATE_LINE" | awk '{print $1}')"
fi
# narrow airmass span: many stars confined to a small box
awk 'BEGIN {for (x=100; x<=400; x+=10) for (y=100; y<=400; y+=10) print x, y}' > "$TEST_TMPDIR/synn_xy.txt"
util/pixel_flux_airmass_correction -k 1 --predict-list "$TEST_TMPDIR/synn_xy.txt" "$REF_IMAGE" 2>/dev/null | awk 'f {print $1, $2, $4} /^# X_pix/ {f=1}' > "$TEST_TMPDIR/synn_xya.txt"
awk -v dir="$TEST_TMPDIR" '{i++; mag=-14.0+i*0.0037; printf "%d 100.0 10.0 %.4f %.4f 1000 10 %.4f 0.01 0\n", i, $1, $2, mag > (dir"/synn.wcscat"); printf "%.4f %.4f 0.01\n", mag, mag+25.0-0.2*$3 > (dir"/synn_calib.txt")}' "$TEST_TMPDIR/synn_xya.txt"
GATE_LINE=$(util/pixel_flux_airmass_correction --fit-airmass-zeropoint --calib-param "$TEST_TMPDIR/syn_calib.txt_param" "$TEST_TMPDIR/synn_calib.txt" "$TEST_TMPDIR/synn.wcscat" "$REF_IMAGE" 2>/dev/null)
if [ "$(echo "$GATE_LINE" | awk '{print $1}')" != "REJECT_NARROW_SPAN" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_GATE_NARROWSPAN_$(echo "$GATE_LINE" | awk '{print $1}')"
fi
# implausible slope
awk -v dir="$TEST_TMPDIR" '{i++; mag=-14.0+i*0.0037; printf "%.4f %.4f 0.01\n", mag, mag+25.0-0.8*$3 > (dir"/synk_calib.txt")}' "$TEST_TMPDIR/syn_xya.txt"
GATE_LINE=$(util/pixel_flux_airmass_correction --fit-airmass-zeropoint --calib-param "$TEST_TMPDIR/syn_calib.txt_param" "$TEST_TMPDIR/synk_calib.txt" "$TEST_TMPDIR/syn.wcscat" "$REF_IMAGE" 2>/dev/null)
if [ "$(echo "$GATE_LINE" | awk '{print $1}')" != "REJECT_K_RANGE" ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_GATE_KRANGE_$(echo "$GATE_LINE" | awk '{print $1}')"
fi

##### diagnostic plotter (gated on matplotlib availability) #####
if [ -s "$TEST_TMPDIR/syn_table.txt" ];then
 echo "$SYN_FIT_LINE" > "$TEST_TMPDIR/syn_airmass_param.txt"
 if python3 -c "import matplotlib" > /dev/null 2>&1 ;then
  echo "Check: diagnostic plot production"
  if ! python3 lib/plot_airmass_zeropoint.py "$TEST_TMPDIR/syn_table.txt" "$TEST_TMPDIR/syn_airmass_param.txt" "$TEST_TMPDIR/syn_plot.png" "synthetic test" > /dev/null 2>&1 ;then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_PLOT_EXIT_CODE"
  fi
  if [ ! -s "$TEST_TMPDIR/syn_plot.png" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_PLOT_NO_PNG"
  fi
 else
  echo "Check: diagnostic plotter skips gracefully without matplotlib"
  if python3 lib/plot_airmass_zeropoint.py "$TEST_TMPDIR/syn_table.txt" "$TEST_TMPDIR/syn_airmass_param.txt" "$TEST_TMPDIR/syn_plot.png" "synthetic test" > /dev/null 2>&1 ;then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_PLOT_NOT_GATED"
  fi
 fi
fi

##### optional cross-check against acquisition-software AIRMASS keyword #####
TTU_TEST_DATA_DIR="../NMW-TexasTech__Gem-03-Q1b1x1_test"
if [ -d "$TTU_TEST_DATA_DIR" ];then
 echo "Check: airmass agreement with the AIRMASS keyword of NMW-TexasTech images"
 TTU_IMAGE=$(ls "$TTU_TEST_DATA_DIR"/second_epoch_images/*.fits 2>/dev/null | head -n 1)
 if [ -n "$TTU_IMAGE" ];then
  if ! util/pixel_flux_airmass_correction --print-info "$TTU_IMAGE" > "$TEST_TMPDIR/ttu.out" 2> "$TEST_TMPDIR/ttu.err" ;then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_TTU_EXIT_CODE"
  fi
  if ! grep -q 'Header cross-check: AIRMASS=' "$TEST_TMPDIR/ttu.out" ;then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_TTU_NO_AIRMASS_CROSSCHECK"
  fi
  if grep -q 'WARNING: the computed frame center airmass differs' "$TEST_TMPDIR/ttu.err" ;then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES PIXFLUXAIRMASS_TTU_AIRMASS_MISMATCH"
  fi
 fi
fi

##### report #####
if [ $TEST_PASSED -eq 1 ];then
 echo "
 pixel_flux_airmass_correction test PASSED"
 exit 0
else
 echo "
 pixel_flux_airmass_correction test FAILED
Failed test codes: $FAILED_TEST_CODES"
 exit 1
fi
