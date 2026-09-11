#!/usr/bin/env bash
# Exercise the non-fatal transient-search quadrant-count error without VaST.
# No image data, compiled programs, or network access are needed.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PIPELINE="$SCRIPT_DIR/../transients/transient_factory_test31.sh"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vast-quadrant-count-test.XXXXXX")
trap 'rm -rf -- "$TEST_DIR"' EXIT

# Extract only this self-contained function; sourcing the pipeline would run it.
awk '
 /^function report_new_image_quadrant_count_changes[[:space:]]*\{/ { copying=1 }
 copying { print }
 copying && /^\}/ { found=1; exit }
 END { if (!found) exit 1 }
' "$PIPELINE" > "$TEST_DIR/function.sh"
# shellcheck source=/dev/null
source "$TEST_DIR/function.sh"

FIRST='new.1[0].fits'
SECOND='new.2[0].fits'
N_CASES=0

fail() {
 echo "FAIL: $CASE_NAME: $*" >&2
 exit 1
}

start_case() {
 CASE_NAME=$1
 mkdir -- "$TEST_DIR/$CASE_NAME"
 cd -- "$TEST_DIR/$CASE_NAME"
 printf 'existing diagnostic log content\n' > transient_factory_test31.txt
 printf 'existing summary log content\n' > transient_factory.log
}

diagnostic() {
 # Actual solver field names; residual values are deliberately irrelevant.
 printf 'WCS_QUALITY_DIAG: file=%s N_match=400 sigma_overall_arcsec=%s n_q1=%s n_q2=%s n_q3=%s n_q4=%s worst_quadrant_to_overall_ratio=99\n' \
  "$1" "${6:-0.25}" "$2" "$3" "$4" "$5" >> transient_factory_test31.txt
}

check_case() {
 local expected=$1 log
 # Under set -e a nonzero return or exit here fails the test before CONTINUED.
 report_new_image_quadrant_count_changes "$FIRST" "$SECOND" > stdout.txt
 printf 'CONTINUED\n' >> stdout.txt
 grep -qx 'CONTINUED' stdout.txt || fail 'processing did not continue'
 for log in stdout.txt transient_factory_test31.txt transient_factory.log ; do
  if [ "$expected" = error ]; then
   grep -q 'ERROR' "$log" || fail "ERROR missing from $log"
  else
   if grep -q 'ERROR' "$log"; then
    fail "unexpected ERROR in $log"
   fi
  fi
 done
 if [ "$expected" = unavailable ]; then
  grep -q 'INFO' stdout.txt || fail 'unavailable counts were not reported as INFO'
 fi
 if [ "$expected" = disabled ]; then
  [ "$(wc -l < stdout.txt)" -eq 1 ] || fail 'disabled check produced output'
 fi
 grep -qx 'existing diagnostic log content' transient_factory_test31.txt || fail 'diagnostic log was overwritten'
 grep -qx 'existing summary log content' transient_factory.log || fail 'summary log was overwritten'
 N_CASES=$((N_CASES + 1))
 echo "PASS: $CASE_NAME"
}

# A large change must remain silent by default and on non-TTU cameras.
unset CAMERA_SETTINGS
start_case camera_unset
diagnostic "$FIRST" 100 100 100 100
diagnostic "$SECOND" 0 0 0 0
check_case disabled

for camera in '' unknown Stas STL-11000M TICA_TESS_FFI ED80__Black STEREO-A-H1 TTUQ3b1x1 TTUQ1b1x1_extra ; do
 CAMERA_SETTINGS="$camera"
 start_case "camera_disabled_${camera:-empty}"
 diagnostic "$FIRST" 100 100 100 100
 diagnostic "$SECOND" 0 0 0 0
 check_case disabled
done

for camera in TTUQ1b1x1 TTUQ2b1x1 ; do
 CAMERA_SETTINGS="$camera"
 start_case "camera_enabled_$camera"
 diagnostic "$FIRST" 100 100 100 100
 diagnostic "$SECOND" 0 0 0 0
 check_case error
done

# Exercise the existing threshold and input checks with a supported camera.
export CAMERA_SETTINGS=TTUQ1b1x1
start_case exactly_20_percent
diagnostic "$FIRST" 80 100 100 100
diagnostic "$SECOND" 100 80 100 100
check_case clear

start_case just_over_20_percent
diagnostic "$FIRST" 3999 100 100 100
diagnostic "$SECOND" 4999 100 100 100
check_case error

for quadrant in 1 2 3 4 ; do
 start_case "over_20_percent_q$quadrant"
 counts=(100 100 100 100)
 counts[quadrant-1]=79
 diagnostic "$FIRST" "${counts[@]}"
 diagnostic "$SECOND" 100 100 100 100
 check_case error
done

start_case reverse_change
diagnostic "$FIRST" 100 100 100 100
diagnostic "$SECOND" 79 100 100 100
check_case error

start_case zeros_and_small_counts
diagnostic "$FIRST" 0 1 0 100
diagnostic "$SECOND" 0 1 0 100
check_case clear

start_case zero_to_five
diagnostic "$FIRST" 0 100 100 100
diagnostic "$SECOND" 5 100 100 100
check_case error

start_case five_to_zero
diagnostic "$FIRST" 100 100 100 5
diagnostic "$SECOND" 100 100 100 0
check_case error

start_case unrelated_images_and_residuals
diagnostic "$FIRST" 100 100 100 100 0.01
diagnostic "$SECOND" 100 100 100 100 200
diagnostic reference.fits 0 0 0 0
diagnostic 'newX10Xfits' 0 0 0 0
diagnostic "prefix$FIRST" 0 0 0 0
diagnostic "$SECOND.extra" 0 0 0 0
check_case clear

start_case newest_diagnostic_wins
diagnostic "$FIRST" 0 100 100 100
diagnostic "$SECOND" 100 0 100 100
diagnostic "$FIRST" 100 100 100 100
diagnostic "$SECOND" 100 100 100 100
check_case clear

start_case newest_diagnostic_flags
diagnostic "$FIRST" 100 100 100 100
diagnostic "$SECOND" 100 100 100 100
diagnostic "$SECOND" 100 79 100 100
check_case error

start_case missing_image_diagnostic
diagnostic "$FIRST" 100 100 100 100
check_case unavailable

for bad_count in NaN missing -1 1.5 100oops ; do
 start_case "invalid_count_$bad_count"
 diagnostic "$FIRST" 100 100 100 100
 diagnostic "$SECOND" "$bad_count" 100 100 100
 check_case unavailable
done

start_case newest_diagnostic_missing_count
diagnostic "$FIRST" 100 100 100 100
diagnostic "$SECOND" 0 100 100 100
printf 'WCS_QUALITY_DIAG: file=%s n_q2=100 n_q3=100 n_q4=100\n' "$SECOND" >> transient_factory_test31.txt
check_case unavailable

# Recorded initial bright-pass counts from the September 9 TTU examples.
start_case recorded_clear_aql02
diagnostic "$FIRST" 1708 1016 1377 828
diagnostic "$SECOND" 1699 1026 1371 829
check_case clear

start_case recorded_small_cloud_cas01_below_20_percent
diagnostic "$FIRST" 1346 878 1549 1109
diagnostic "$SECOND" 1350 919 1534 1080
check_case clear

start_case recorded_large_cloud_change_aql01
diagnostic "$FIRST" 2375 252 1920 393
diagnostic "$SECOND" 1957 589 1796 602
check_case error

echo "All $N_CASES quadrant-count tests passed."
