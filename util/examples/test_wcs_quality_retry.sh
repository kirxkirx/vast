#!/usr/bin/env bash
# Exercise the WCS-quality retry helper without VaST: no image data, no compiled
# programs, no network. The plate solver is replaced by a stub that appends
# whichever WCS_QUALITY_DIAG line the test asks for.
#
# Three behaviours are guarded here, all easy to break by accident:
#  - the absolute sigma floor, which stops a solution that is already good from
#    being re-solved just because the reference images were unusually sharp;
#  - that the floor applies to the overall sigma ONLY and never hides a blown-up
#    worst quadrant, which is the failure mode most worth retrying and the one a
#    naive floor would silently swallow;
#  - the re-statement of the kept diagnostic when a retry is rejected, without
#    which the last WCS_QUALITY_DIAG line in the log describes a solution that
#    was thrown away, and everything downstream that reads "the latest
#    diagnostic" silently reads the wrong numbers.
#
# The numbers in the cases below are real ones taken from the 2026-09-11 and
# 2026-09-13 NMW-TexasTech runs, so a future change to the thresholds is judged
# against traffic the pipeline has actually seen.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
PIPELINE="$SCRIPT_DIR/../transients/transient_factory_test31.sh"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vast-wcs-retry-test.XXXXXX")
trap 'rm -rf -- "$TEST_DIR"' EXIT

# Extract only the self-contained functions under test; sourcing the pipeline
# would run it.
for FUNCTION_NAME in image_basename_for_wcs_quality_diag extract_wcs_quality_field retry_wcs_with_lower_tweak_order ; do
 awk -v want="$FUNCTION_NAME" '
  $0 ~ ("^function " want "[[:space:]]*\\{") { copying=1 }
  copying { print }
  copying && /^\}/ { found=1; exit }
  END { if (!found) exit 1 }
 ' "$PIPELINE" >> "$TEST_DIR/functions.sh" || { echo "FAIL: cannot extract $FUNCTION_NAME from $PIPELINE" >&2; exit 1; }
done
# shellcheck source=/dev/null
source "$TEST_DIR/functions.sh"

IMAGE=fd_test_image.fits
N_CASES=0

fail() {
 echo "FAIL: $CASE_NAME: $*" >&2
 echo "--- transient_factory_test31.txt ---" >&2
 cat transient_factory_test31.txt >&2
 exit 1
}

diag_line() { # sigma ratio
 printf 'WCS_QUALITY_DIAG: file=%s N_match=4000 sigma_overall_arcsec=%s sigma_q1_arcsec=0.4 sigma_q2_arcsec=0.4 sigma_q3_arcsec=0.4 sigma_q4_arcsec=0.4 n_q1=1000 n_q2=1000 n_q3=1000 n_q4=1000 worst_quadrant_to_overall_ratio=%s\n' "$IMAGE" "$1" "$2"
}

start_case() { # name, original_sigma, original_ratio, stub_sigma, stub_ratio
 CASE_NAME=$1
 mkdir -p -- "$TEST_DIR/$CASE_NAME"
 cd -- "$TEST_DIR/$CASE_NAME"
 : > transient_factory_test31.txt
 diag_line "$2" "$3" >> transient_factory_test31.txt
 # The WCS products the helper backs up and, on the revert path, restores.
 printf 'order-3 WCS\n' > "wcs_$IMAGE"
 printf 'order-3 catalog\n' > "wcs_$IMAGE.wcscat"
 # Stub solver: appends the diagnostic the case asks for and overwrites the WCS.
 mkdir -p util
 {
  printf '#!/bin/sh\n'
  printf 'printf "order-2 WCS\\n" > "wcs_%s"\n' "$IMAGE"
  printf 'printf "order-2 catalog\\n" > "wcs_%s.wcscat"\n' "$IMAGE"
  if [ -n "$4" ]; then
   printf 'diag_line_text=$(printf '\''%s'\'')\n' "$(diag_line "$4" "$5" | tr -d '\n')"
   printf 'echo "$diag_line_text"\n'
  fi
 } > util/solve_plate_with_UCAC5
 chmod +x util/solve_plate_with_UCAC5
}

finish_case() {
 cd -- "$TEST_DIR"
 N_CASES=$((N_CASES + 1))
 echo "PASS: $CASE_NAME"
}

# The retry is skipped when only the overall sigma is flagged and it is inside
# the floor, even though 0.90 is 3x the 0.30 reference average.
start_case floor_suppresses_retry 0.90 1.05 '' ''
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 0.90 1.05 0.30 1.00 2.0 2 1.47
grep -q 'flagged: sigma=' transient_factory_test31.txt && fail 'a solution inside the floor was retried'
grep -q 'inside the 1.47 arcsec floor' transient_factory_test31.txt || fail 'the floor decision was not logged'
grep -qx 'order-3 WCS' "wcs_$IMAGE" || fail 'the WCS was touched'
finish_case

# The floor must NEVER suppress a blown-up worst quadrant. These are the real
# 2026-09-13 numbers of two images whose overall sigma was inside the floor but
# whose worst quadrant was 4.4x and 12.6x the frame average; both were repaired
# by the retry, so both must still be retried.
start_case floor_does_not_hide_a_bad_quadrant 1.198 12.595 0.391 1.103
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 1.198 12.595 0.314 1.089 2.0 2 1.47
grep -q 'flagged: sigma=' transient_factory_test31.txt || fail 'a 12.6x worst-quadrant ratio was suppressed by the sigma floor'
grep -q 'keeping retry result' transient_factory_test31.txt || fail 'the repair was not kept'
finish_case

start_case floor_does_not_hide_a_bad_quadrant_2 0.691 4.424 0.916 2.883
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 0.691 4.424 0.314 1.089 2.0 2 1.47
grep -q 'flagged: sigma=' transient_factory_test31.txt || fail 'a 4.4x worst-quadrant ratio was suppressed by the sigma floor'
finish_case

# The four re-solves the floor exists to prevent: overall sigma above the
# reference ratio but inside the floor, worst quadrant unremarkable.
for wasted_case in '0.984 1.008 0.282 1.183' '0.991 1.267 0.282 1.183' '0.797 1.414 0.2785 1.082' '0.654 1.827 0.314 1.0885' ; do
 set -- $wasted_case
 start_case "floor_suppresses_wasted_retry_$1" "$1" "$2" '' ''
 retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" "$1" "$2" "$3" "$4" 2.0 2 1.47
 grep -q 'flagged: sigma=' transient_factory_test31.txt && fail "sigma=$1 ratio=$2 was still re-solved for nothing"
 finish_case
done

# Without a floor the same solution is retried: the floor, not some other
# change, is what suppresses it.
start_case no_floor_still_retries 0.90 1.05 0.80 1.02
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 0.90 1.05 0.30 1.00 2.0 2 ''
grep -q 'flagged: sigma=' transient_factory_test31.txt || fail 'the retry did not trigger without a floor'
finish_case

# A solution far outside the floor is still retried, and a better result is kept.
start_case bad_solution_retried_and_kept 7.578 3.801 0.516 1.113
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 7.578 3.801 0.5265 1.068 2.0 2 1.47
grep -q 'flagged: sigma=' transient_factory_test31.txt || fail 'a bad solution was not retried'
grep -q 'keeping retry result' transient_factory_test31.txt || fail 'the improved retry was not kept'
grep -q 're-stating the kept diagnostic' transient_factory_test31.txt && fail 'a kept retry must not restate the old diagnostic'
grep -qx 'order-2 WCS' "wcs_$IMAGE" || fail 'the retried WCS was not kept on disk'
[ "$(extract_wcs_quality_field "$IMAGE" sigma_overall_arcsec)" = 0.516 ] || fail 'the latest diagnostic is not the kept one'
finish_case

# The case this test exists for: the retry makes things worse, the order-3 WCS
# is restored, and the diagnostic describing it must be restored with it.
start_case rejected_retry_restates_diagnostic 3.000 3.000 9.902 4.000
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 3.000 3.000 0.500 1.050 2.0 2 1.47
grep -q 'did NOT improve' transient_factory_test31.txt || fail 'the worse retry was not rejected'
grep -qx 'order-3 WCS' "wcs_$IMAGE" || fail 'the order-3 WCS was not restored'
grep -qx 'order-3 catalog' "wcs_$IMAGE.wcscat" || fail 'the order-3 catalog was not restored'
RESTORED_SIGMA=$(extract_wcs_quality_field "$IMAGE" sigma_overall_arcsec)
RESTORED_RATIO=$(extract_wcs_quality_field "$IMAGE" worst_quadrant_to_overall_ratio)
[ "$RESTORED_SIGMA" = 3.000 ] || fail "the latest diagnostic is $RESTORED_SIGMA, not the restored 3.000 - downstream would read the discarded solution"
[ "$RESTORED_RATIO" = 3.000 ] || fail "the latest ratio is $RESTORED_RATIO, not the restored 3.000"
finish_case

# A solver run that produces no new diagnostic leaves the old one as the latest,
# so the helper scores the retry as no better and reverts. It must restate the
# kept diagnostic just the same, so the log still ends on the restored solution.
start_case retry_without_new_diagnostic_reverts 3.000 3.000 '' ''
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 3.000 3.000 0.500 1.050 2.0 2 1.47
grep -q 'did NOT improve' transient_factory_test31.txt || fail 'a retry with no new diagnostic was not rejected'
grep -qx 'order-3 WCS' "wcs_$IMAGE" || fail 'the order-3 WCS was not restored'
[ "$(extract_wcs_quality_field "$IMAGE" sigma_overall_arcsec)" = 3.000 ] || fail 'the kept diagnostic was not restated'
finish_case

# Nothing at all happens when neither metric exceeds the threshold.
start_case below_threshold_no_retry 0.55 1.10 '' ''
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 0.55 1.10 0.50 1.05 2.0 2 0.10
grep -q 'flagged: sigma=' transient_factory_test31.txt && fail 'a good solution was retried'
grep -q 'floor' transient_factory_test31.txt && fail 'the floor message fired below the floor'
finish_case

# The solver's own verdict is a third, independent trigger. Both tests above are
# ratios to the reference images, so a badly solved frame sitting inside 2x of
# mediocre references is never retried - unless the SIP_REFIT_REJECTED line is
# taken into account. The numbers are the real Lac-01-Q2b1x1 2026-09-13 ones,
# with the reference averages inflated so that neither ratio test can fire.
start_case solver_rejection_triggers_retry 7.578 3.801 0.516 1.113
printf 'SIP_REFIT_REJECTED: file=%s worst_region_rms_kept=24.537 arcsec robust_rms_kept=18.160 arcsec matched=3216\n' "$IMAGE" >> transient_factory_test31.txt
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 7.578 3.801 5.000 3.000 2.0 2 1.47 5.87
grep -q 'flagged by the plate solver' transient_factory_test31.txt || fail 'the solver rejection did not trigger a retry'
grep -q 'keeping retry result' transient_factory_test31.txt || fail 'the repair was not kept'
[ "$(extract_wcs_quality_field "$IMAGE" sigma_overall_arcsec)" = 0.516 ] || fail 'the repaired solution is not the latest diagnostic'
finish_case

# The ordinary rejection - the overwhelming majority - means the solution was
# already good and there was nothing to improve. It must never cause a re-solve.
start_case ordinary_solver_rejection_is_not_a_trigger 0.55 1.10 '' ''
printf 'SIP_REFIT_REJECTED: file=%s worst_region_rms_kept=0.442 arcsec robust_rms_kept=0.410 arcsec matched=4800\n' "$IMAGE" >> transient_factory_test31.txt
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 0.55 1.10 0.50 1.05 2.0 2 1.47 5.87
grep -q 'flagged' transient_factory_test31.txt && fail 'a healthy refit rejection caused a re-solve'
finish_case

# The worst healthy baseline ever measured (1.098 arcsec) must stay below the
# one-pixel limit, and the smallest real one (19.763 arcsec) must stay above it.
start_case solver_rejection_threshold_edges 0.55 1.10 '' ''
printf 'SIP_REFIT_REJECTED: file=%s worst_region_rms_kept=1.098 arcsec robust_rms_kept=0.900 arcsec matched=4700\n' "$IMAGE" >> transient_factory_test31.txt
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 0.55 1.10 0.50 1.05 2.0 2 1.47 5.87
grep -q 'flagged' transient_factory_test31.txt && fail 'the worst healthy baseline crossed the limit'
finish_case

start_case solver_rejection_threshold_edges_bad 1.994 1.50 0.500 1.100
printf 'SIP_REFIT_REJECTED: file=%s worst_region_rms_kept=19.763 arcsec robust_rms_kept=12.000 arcsec matched=3500\n' "$IMAGE" >> transient_factory_test31.txt
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 1.994 1.50 1.500 1.400 2.0 2 1.47 5.87
grep -q 'flagged by the plate solver' transient_factory_test31.txt || fail 'the smallest real bad baseline did not cross the limit'
finish_case

# A rejection line belonging to a DIFFERENT image must not trigger this one.
start_case solver_rejection_for_another_image_ignored 0.55 1.10 '' ''
printf 'SIP_REFIT_REJECTED: file=some_other_frame.fits worst_region_rms_kept=24.537 arcsec robust_rms_kept=18.160 arcsec matched=3216\n' >> transient_factory_test31.txt
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 0.55 1.10 0.50 1.05 2.0 2 1.47 5.87
grep -q 'flagged' transient_factory_test31.txt && fail "another image's refit rejection triggered this one"
finish_case

# With no limit passed, the solver rejection is ignored entirely: the trigger is
# opt-in, so an older caller that passes nine arguments behaves as it always did.
start_case solver_rejection_needs_a_limit 0.55 1.10 '' ''
printf 'SIP_REFIT_REJECTED: file=%s worst_region_rms_kept=24.537 arcsec robust_rms_kept=18.160 arcsec matched=3216\n' "$IMAGE" >> transient_factory_test31.txt
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 0.55 1.10 0.50 1.05 2.0 2 1.47
grep -q 'flagged' transient_factory_test31.txt && fail 'the solver rejection fired without a limit'
finish_case

echo "All $N_CASES WCS-quality retry tests passed."
