#!/usr/bin/env bash
#
# Standalone test for forced photometry --list (batch) mode.
#
# Verifies:
#   1. Batch C output == single-position C output (per position, same mag to < 1e-4)
#   2. Batch Py output == single-position Py output (per position, same mag to < 1e-4)
#   3. Batch C mean offset from SExtractor-calibrated magnitudes |<| 0.02 mag; RMS < 0.1
#   4. Batch C vs Batch Py mean difference < 0.01 mag
#   5. util/forced_photometry.sh --list mode runs end-to-end and emits detections
#
# Run from the VaST top directory.  Uses the NMW telephoto-lens test image
# already exercised by util/examples/test_vast.sh.

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

FP_FITSFILE="../individual_images_test/wcs_Sgr-05-Q2b1x1_2026-03-26_06-11-57_20.00sec_-15.00C_LIGHT_0682.fits"
FP_FITSFILE_URL="http://tau.kirx.net/vast_test_data/wcs_Sgr-05-Q2b1x1_2026-03-26_06-11-57_20.00sec_-15.00C_LIGHT_0682.fits.bz2"
FP_WCS_CATALOG="wcs_Sgr-05-Q2b1x1_2026-03-26_06-11-57_20.00sec_-15.00C_LIGHT_0682.fits.cat"
FP_FILTER="V"
FP_TARGET_RA="19:32:43.67"
FP_TARGET_DEC="-22:39:30.7"
FP_N_STARS=20

TEST_PASSED=1
FAILED_TEST_CODES=""

echo "######### Forced photometry --list mode test #########" >&2
THIS_TEST_START_UNIXSEC=$(date +%s)

# Download test image if missing
if [ ! -f "$FP_FITSFILE" ];then
 echo "Downloading test image..." >&2
 if [ ! -d ../individual_images_test ];then
  mkdir ../individual_images_test
 fi
 ( cd ../individual_images_test && \
   curl --silent --show-error -O "$FP_FITSFILE_URL" && \
   bunzip2 wcs_Sgr-05-Q2b1x1_2026-03-26_06-11-57_20.00sec_-15.00C_LIGHT_0682.fits.bz2 )
fi
if [ ! -f "$FP_FITSFILE" ];then
 echo "Test image $FP_FITSFILE not available; skipping test." >&2
 exit 1
fi

util/clean_data.sh
cp default.sex.telephoto_lens_vSTL default.sex

# Step 1: run single-position pipeline once to produce calib files + catalog
util/forced_photometry.sh "$FP_FITSFILE" "$FP_TARGET_RA" "$FP_TARGET_DEC" "$FP_FILTER" \
    > fp_initial.log 2>fp_initial.err
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST001_PIPELINE_FAIL"
fi
if [ ! -s calib.txt_param ] || [ ! -s "$FP_WCS_CATALOG" ];then
 echo "Initial pipeline did not produce calib files or catalog; aborting." >&2
 exit 1
fi

FP_APERTURE=$(lib/sextract_single_image_noninteractive "$FP_FITSFILE" 2>/dev/null)
FP_EDGE_MARGIN=$(echo "$FP_APERTURE" | awk '{printf "%.0f", 10.0 * $1 / 2.0 + 2}')

# Step 2: pick N unflagged mid-magnitude stars far from the edge.
# Same selection filter used by the existing forced-photometry block in test_vast.sh.
awk -v margin="$FP_EDGE_MARGIN" -v nx="9576" -v ny="6388" \
    '{if ($10==0 && $9>0 && $9<0.1 && $8>-15 && $8<-5 && $4>margin && $4<nx-margin && $5>margin && $5<ny-margin) print}' \
    "$FP_WCS_CATALOG" | sort -k1,1n | head -n "$FP_N_STARS" > fp_catalog_stars.tmp

FP_N_ACTUAL=$(wc -l < fp_catalog_stars.tmp)
if [ "$FP_N_ACTUAL" -lt 5 ];then
 echo "Too few catalog stars ($FP_N_ACTUAL) for test; aborting." >&2
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST002_FEW_STARS_${FP_N_ACTUAL}"
fi

# Step 3: build pixel list, sky list, and a parallel SExtractor-calibrated
# magnitude file that the assertions below consult for reference.
FP_CAL_P2=$(awk '{print $3}' calib.txt_param)
FP_CAL_P1=$(awk '{print $4}' calib.txt_param)
FP_CAL_P0=$(awk '{print $5}' calib.txt_param)

: > fp_pix_list.txt
: > fp_sky_list.txt
: > fp_sex_mags.txt

FP_IDX=0
while read -r FP_LINE; do
 FP_IDX=$((FP_IDX + 1))
 FP_RA_DEG=$(echo "$FP_LINE" | awk '{print $2}')
 FP_DEC_DEG=$(echo "$FP_LINE" | awk '{print $3}')
 FP_PX=$(echo "$FP_LINE" | awk '{print $4}')
 FP_PY=$(echo "$FP_LINE" | awk '{print $5}')
 FP_INST_MAG=$(echo "$FP_LINE" | awk '{print $8}')
 FP_SEX_CAL=$(awk -v m="$FP_INST_MAG" -v p2="$FP_CAL_P2" -v p1="$FP_CAL_P1" -v p0="$FP_CAL_P0" \
              'BEGIN {printf "%.4f", p2*m*m + p1*m + p0}')
 FP_LABEL="s${FP_IDX}"
 echo "$FP_PX $FP_PY $FP_LABEL" >> fp_pix_list.txt
 FP_RADEC=$(lib/deg2hms "$FP_RA_DEG" "$FP_DEC_DEG")
 FP_RA_H=$(echo "$FP_RADEC" | awk '{print $1}')
 FP_DEC_D=$(echo "$FP_RADEC" | awk '{print $2}')
 echo "$FP_RA_H $FP_DEC_D $FP_LABEL" >> fp_sky_list.txt
 echo "$FP_LABEL $FP_SEX_CAL" >> fp_sex_mags.txt
done < fp_catalog_stars.tmp

# Step 4: run batch C
util/forced_photometry "$FP_FITSFILE" --list fp_pix_list.txt "$FP_APERTURE" \
    > fp_batch_c.txt 2>fp_batch_c.err
if [ $? -ne 0 ] || [ ! -s fp_batch_c.txt ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST003_BATCH_C_FAIL"
fi

# Step 5: run batch Python (if available)
FP_HAVE_PY=0
if command -v python3 &>/dev/null; then
 python3 -c "from photutils.aperture import CircularAperture; from photutils.background import SExtractorBackground; from astropy.io import fits; from astropy.stats import SigmaClip" 2>/dev/null
 if [ $? -eq 0 ];then
  FP_HAVE_PY=1
 fi
fi
if [ "$FP_HAVE_PY" -eq 1 ];then
 util/forced_photometry.py "$FP_FITSFILE" --list fp_pix_list.txt "$FP_APERTURE" \
     > fp_batch_py.txt 2>fp_batch_py.err
 if [ $? -ne 0 ] || [ ! -s fp_batch_py.txt ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST004_BATCH_PY_FAIL"
 fi
fi

#################################
# Test 1: Batch C == single-position C for every position.
# Re-run single-position with the ORIGINAL input px/py (from fp_pix_list.txt),
# not the echoed cx/cy in the batch output, so the comparison is unaffected by
# any decimal-rounding in the batch echo.  paste joins the two files by line;
# they are produced in matching order by construction.
#################################
FP_MAX_DIFF_C=0
while read -r FP_PX_ORIG FP_PY_ORIG FP_LBL_IN FP_LBL_OUT FP_CX_ECHO FP_CY_ECHO FP_BATCH_MAG FP_BATCH_ERR FP_BATCH_STATUS; do
 [ -z "$FP_LBL_IN" ] && continue
 if [ "$FP_LBL_IN" != "$FP_LBL_OUT" ];then
  echo "INTERNAL: label misalignment $FP_LBL_IN vs $FP_LBL_OUT" >&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST005_C_ORDER_${FP_LBL_IN}"
  continue
 fi
 FP_SINGLE=$(util/forced_photometry "$FP_FITSFILE" "$FP_PX_ORIG" "$FP_PY_ORIG" "$FP_APERTURE" 2>/dev/null)
 FP_SINGLE_MAG=$(echo "$FP_SINGLE" | awk '{print $1}')
 FP_SINGLE_STATUS=$(echo "$FP_SINGLE" | awk '{print $3}')
 if [ "$FP_BATCH_STATUS" != "$FP_SINGLE_STATUS" ];then
  echo "MISMATCH status (C): label=$FP_LBL_IN batch=$FP_BATCH_STATUS single=$FP_SINGLE_STATUS" >&2
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST005_C_STATUS_${FP_LBL_IN}"
  continue
 fi
 if [ "$FP_BATCH_STATUS" = "detection" ];then
  FP_DIFF=$(awk -v a="$FP_BATCH_MAG" -v b="$FP_SINGLE_MAG" 'BEGIN {d=a-b; if(d<0)d=-d; printf "%.6f", d}')
  FP_OK=$(awk -v d="$FP_DIFF" 'BEGIN {print (d < 1e-4) ? 1 : 0}')
  if [ "$FP_OK" != "1" ];then
   echo "MISMATCH mag (C): label=$FP_LBL_IN batch=$FP_BATCH_MAG single=$FP_SINGLE_MAG diff=$FP_DIFF" >&2
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST006_C_DIFF_${FP_LBL_IN}"
  fi
  FP_MAX_DIFF_C=$(awk -v a="$FP_MAX_DIFF_C" -v b="$FP_DIFF" 'BEGIN {print (a>b ? a : b)}')
 fi
done < <(paste -d' ' fp_pix_list.txt fp_batch_c.txt)
echo "Max batch-vs-single C diff: $FP_MAX_DIFF_C" >&2

#################################
# Test 2: Batch Py == single-position Py for every position (same approach)
#################################
FP_MAX_DIFF_PY=0
if [ "$FP_HAVE_PY" -eq 1 ];then
 while read -r FP_PX_ORIG FP_PY_ORIG FP_LBL_IN FP_LBL_OUT FP_CX_ECHO FP_CY_ECHO FP_BATCH_MAG FP_BATCH_ERR FP_BATCH_STATUS; do
  [ -z "$FP_LBL_IN" ] && continue
  if [ "$FP_LBL_IN" != "$FP_LBL_OUT" ];then
   echo "INTERNAL: label misalignment (Py) $FP_LBL_IN vs $FP_LBL_OUT" >&2
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST007_PY_ORDER_${FP_LBL_IN}"
   continue
  fi
  FP_SINGLE=$(util/forced_photometry.py "$FP_FITSFILE" "$FP_PX_ORIG" "$FP_PY_ORIG" "$FP_APERTURE" 2>/dev/null)
  FP_SINGLE_MAG=$(echo "$FP_SINGLE" | awk '{print $1}')
  FP_SINGLE_STATUS=$(echo "$FP_SINGLE" | awk '{print $3}')
  if [ "$FP_BATCH_STATUS" != "$FP_SINGLE_STATUS" ];then
   echo "MISMATCH status (Py): label=$FP_LBL_IN batch=$FP_BATCH_STATUS single=$FP_SINGLE_STATUS" >&2
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST007_PY_STATUS_${FP_LBL_IN}"
   continue
  fi
  if [ "$FP_BATCH_STATUS" = "detection" ];then
   FP_DIFF=$(awk -v a="$FP_BATCH_MAG" -v b="$FP_SINGLE_MAG" 'BEGIN {d=a-b; if(d<0)d=-d; printf "%.6f", d}')
   FP_OK=$(awk -v d="$FP_DIFF" 'BEGIN {print (d < 1e-4) ? 1 : 0}')
   if [ "$FP_OK" != "1" ];then
    echo "MISMATCH mag (Py): label=$FP_LBL_IN batch=$FP_BATCH_MAG single=$FP_SINGLE_MAG diff=$FP_DIFF" >&2
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST008_PY_DIFF_${FP_LBL_IN}"
   fi
   FP_MAX_DIFF_PY=$(awk -v a="$FP_MAX_DIFF_PY" -v b="$FP_DIFF" 'BEGIN {print (a>b ? a : b)}')
  fi
 done < <(paste -d' ' fp_pix_list.txt fp_batch_py.txt)
 echo "Max batch-vs-single Py diff: $FP_MAX_DIFF_PY" >&2
fi

#################################
# Test 3: Batch C vs SExtractor-calibrated magnitudes
#################################
FP_STATS_C=$(awk '
  NR==FNR {sex[$1]=$2; next}
  $6=="detection" && ($1 in sex) {
    d = $4 - sex[$1]
    sum += d; sum2 += d*d; n++
  }
  END {
    if (n > 0) {
      mean = sum / n; var = sum2/n - mean*mean; if (var < 0) var = 0
      printf "%d %.4f %.4f", n, mean, sqrt(var)
    } else {
      printf "0 0.0000 0.0000"
    }
  }
' fp_sex_mags.txt fp_batch_c.txt)
FP_N_DET_C=$(echo "$FP_STATS_C" | awk '{print $1}')
FP_MEAN_C=$(echo "$FP_STATS_C" | awk '{print $2}')
FP_RMS_C=$(echo "$FP_STATS_C" | awk '{print $3}')
echo "Batch C vs SExtractor: N=$FP_N_DET_C mean=$FP_MEAN_C RMS=$FP_RMS_C" >&2

if [ "$FP_N_DET_C" -lt 3 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST009_FEW_C_DETS_${FP_N_DET_C}"
else
 FP_ABS=$(awk -v m="$FP_MEAN_C" 'BEGIN {if(m<0)m=-m; printf "%.4f", m}')
 FP_OK=$(awk -v m="$FP_ABS" 'BEGIN {print (m < 0.02) ? 1 : 0}')
 if [ "$FP_OK" != "1" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST010_C_MEAN_${FP_MEAN_C}"
 fi
 FP_OK=$(awk -v r="$FP_RMS_C" 'BEGIN {print (r < 0.1) ? 1 : 0}')
 if [ "$FP_OK" != "1" ];then
  TEST_PASSED=0
  FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST011_C_RMS_${FP_RMS_C}"
 fi
fi

#################################
# Test 4: Batch Py vs SExtractor + Batch C vs Batch Py agreement
#################################
if [ "$FP_HAVE_PY" -eq 1 ];then
 FP_STATS_PY=$(awk '
   NR==FNR {sex[$1]=$2; next}
   $6=="detection" && ($1 in sex) {
     d = $4 - sex[$1]
     sum += d; sum2 += d*d; n++
   }
   END {
     if (n > 0) {
       mean = sum / n; var = sum2/n - mean*mean; if (var < 0) var = 0
       printf "%d %.4f %.4f", n, mean, sqrt(var)
     } else {
       printf "0 0.0000 0.0000"
     }
   }
 ' fp_sex_mags.txt fp_batch_py.txt)
 FP_N_DET_PY=$(echo "$FP_STATS_PY" | awk '{print $1}')
 FP_MEAN_PY=$(echo "$FP_STATS_PY" | awk '{print $2}')
 FP_RMS_PY=$(echo "$FP_STATS_PY" | awk '{print $3}')
 echo "Batch Py vs SExtractor: N=$FP_N_DET_PY mean=$FP_MEAN_PY RMS=$FP_RMS_PY" >&2
 if [ "$FP_N_DET_PY" -ge 3 ] && [ "$FP_N_DET_C" -ge 3 ];then
  FP_CPY=$(awk -v c="$FP_MEAN_C" -v p="$FP_MEAN_PY" 'BEGIN {d=c-p; if(d<0)d=-d; printf "%.4f", d}')
  FP_OK=$(awk -v d="$FP_CPY" 'BEGIN {print (d < 0.01) ? 1 : 0}')
  if [ "$FP_OK" != "1" ];then
   TEST_PASSED=0
   FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST012_CPY_${FP_CPY}"
  fi
 fi
fi

#################################
# Test 5: forced_photometry.sh --list end-to-end
#################################
util/forced_photometry.sh "$FP_FITSFILE" --list fp_sky_list.txt "$FP_FILTER" \
    > fp_shell_out.txt 2>fp_shell_out.err
if [ $? -ne 0 ] || [ ! -s fp_shell_out.txt ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST013_SHELL_FAIL"
fi
grep -q "^# C implementation:" fp_shell_out.txt
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST014_SHELL_NO_HEADER"
fi
# Count detection rows under the C section
FP_SHELL_N=$(awk 'BEGIN{go=0; n=0} /^# C implementation:/{go=1; next} /^# Python/{go=0} go && $0~/detection/{n++} END{print n+0}' fp_shell_out.txt)
if [ "$FP_SHELL_N" -lt 3 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES FPLIST015_SHELL_FEW_${FP_SHELL_N}"
fi
echo "Shell --list detections under C section: $FP_SHELL_N" >&2

#################################
# Cleanup
#################################
rm -f fp_catalog_stars.tmp fp_pix_list.txt fp_sky_list.txt fp_sex_mags.txt
rm -f fp_batch_c.txt fp_batch_c.err fp_batch_py.txt fp_batch_py.err
rm -f fp_shell_out.txt fp_shell_out.err fp_initial.log fp_initial.err

#################################
# Summary
#################################
THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_MIN_STR=$(echo "$THIS_TEST_STOP_UNIXSEC" "$THIS_TEST_START_UNIXSEC" | awk '{printf "%.1f min", ($1-$2)/60.0}')

if [ "$TEST_PASSED" -eq 1 ];then
 echo -e "\n\033[01;34mForced photometry list-mode test \033[01;32mPASSED\033[00m ($THIS_TEST_TIME_MIN_STR)"
 exit 0
else
 echo -e "\n\033[01;34mForced photometry list-mode test \033[01;31mFAILED\033[00m ($THIS_TEST_TIME_MIN_STR)"
 echo "Failure codes:$FAILED_TEST_CODES"
 exit 1
fi
