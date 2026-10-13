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
for FUNCTION_NAME in image_basename_for_wcs_quality_diag extract_wcs_quality_field retry_wcs_with_small_radius retry_wcs_with_lower_tweak_order report_new_image_bad_worst_quadrant ; do
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
# whose worst quadrant was 12.6x and 4.4x the frame average. The first was
# repaired by the retry; the second traded a 14% lower worst quadrant (10 stars)
# for three quadrants 27-36% worse. Both must still be retried.
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

# Both solutions broken in the same quadrants: the worst-quadrant sigma
# saturates near the matching radius (27.55 vs 27.48 arcsec) and the score
# comparison is noise, while the re-solve turned a 3.5 arcsec quadrant into a
# 19.9 arcsec one. Real Her-09-Q1b1x1 numbers of 2026-10-08 (frame 0113) and
# 2026-10-06 (frame 0104); the later pass confirmed the re-solve was worse.
for broken_case in '5.925 4.650 15.191 1.809' '5.926 4.675 14.307 1.885' ; do
 set -- $broken_case
 start_case "both_broken_sigma_doubled_$1_$3" "$1" "$2" "$3" "$4"
 retry_wcs_with_lower_tweak_order "$IMAGE" "2nd new image" "$1" "$2" 0.4315 1.193 2.0 2 1.48 5.92
 grep -q 'did NOT improve' transient_factory_test31.txt || fail "a re-solve that more than doubled the overall sigma ($1->$3) was kept"
 grep -q 'overall sigma more than doubled' transient_factory_test31.txt || fail 'the reason for the rejection was not logged'
 grep -qx 'order-3 WCS' "wcs_$IMAGE" || fail 'the order-3 WCS was not restored'
 [ "$(extract_wcs_quality_field "$IMAGE" sigma_overall_arcsec)" = "$1" ] || fail 'the kept diagnostic was not restated'
 finish_case
done

# Genuine repairs that RAISE the overall sigma must still be kept: more stars
# get matched in the repaired region. Real For-04-Q1 (2026-09-21 0254: all four
# quadrants improved, sigma 3.027->4.067; 2026-09-01 0454), Lyn-02-Q1 (2026-10-07
# 0345) and For-04-Q1 (2026-10-01 0165) numbers.
for repair_case in '3.027 6.391 4.067 4.560 0.283 1.067' '4.507 5.148 4.193 5.503 0.283 1.067' '5.605 4.893 2.471 10.835 0.361 1.237' '3.479 9.918 3.771 5.648 0.283 1.067' ; do
 set -- $repair_case
 start_case "repair_kept_$1_$3" "$1" "$2" "$3" "$4"
 retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" "$1" "$2" "$5" "$6" 2.0 2 1.48 5.92
 grep -q 'keeping retry result' transient_factory_test31.txt || fail "the repair $1/$2 -> $3/$4 was not kept"
 grep -qx 'order-2 WCS' "wcs_$IMAGE" || fail 'the retried WCS was not kept on disk'
 finish_case
done

# A re-solve that doubles a sigma which is still inside the floor is not a
# reason to refuse it (synthetic: worst quadrant 4.00 -> 0.99 arcsec).
start_case doubled_sigma_inside_floor_is_kept 0.400 10.000 0.900 1.100
retry_wcs_with_lower_tweak_order "$IMAGE" "1st new image" 0.400 10.000 0.314 1.089 2.0 2 1.47 5.87
grep -q 'keeping retry result' transient_factory_test31.txt || fail 'a re-solve inside the floor was refused for doubling its sigma'
finish_case

# A re-solve whose diagnostic could not be computed (NaN) is no better: awk
# would read NaN as 0, a perfect score, and keep it.
start_case nan_retry_diagnostic_reverts 5.925 4.650 NaN NaN
retry_wcs_with_lower_tweak_order "$IMAGE" "2nd new image" 5.925 4.650 0.4315 1.193 2.0 2 1.48 5.92
grep -q 'keeping retry result' transient_factory_test31.txt && fail 'a NaN re-solve diagnostic was kept'
grep -q 'no usable diagnostic for the re-solve' transient_factory_test31.txt || fail 'the NaN rejection was not explained'
grep -qx 'order-3 WCS' "wcs_$IMAGE" || fail 'the order-3 WCS was not restored'
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

# The absolute check after the retries. Real Her-09-Q1b1x1 2026-10-08 frame 0112
# numbers: both new images ended about 27 arcsec off in their worst quadrant,
# which the count comparison between the two images cannot see.
start_case bad_final_worst_quadrant_is_an_error 5.983 4.410 '' ''
CAMERA_SETTINGS=TTUQ1b1x1 report_new_image_bad_worst_quadrant "$IMAGE" "1st new image" 5.92
grep -q '^ERROR: bad plate solution of the 1st new image' transient_factory_test31.txt || fail 'a 26.4 arcsec worst quadrant raised no ERROR'
grep -q '^ERROR: bad plate solution' transient_factory.log || fail 'the ERROR did not reach transient_factory.log'
finish_case

# A good solution (the repaired Lac-01-Q2b1x1 2026-09-13 frame, 0.574 arcsec
# worst quadrant) and the worst quadrant of an ordinary frame stay silent.
for good_case in '0.516 1.113' '0.540 1.155' ; do
 set -- $good_case
 start_case "good_final_worst_quadrant_is_silent_$1" "$1" "$2" '' ''
 CAMERA_SETTINGS=TTUQ2b1x1 report_new_image_bad_worst_quadrant "$IMAGE" "2nd new image" 5.92
 grep -q 'ERROR' transient_factory_test31.txt && fail "a $1 arcsec solution raised an ERROR"
 finish_case
done

# Other cameras are not judged: the limit was calibrated on NMW-TTU data only.
start_case bad_final_worst_quadrant_other_camera_silent 5.983 4.410 '' ''
CAMERA_SETTINGS=STL-11000M report_new_image_bad_worst_quadrant "$IMAGE" "1st new image" 5.92
grep -q 'ERROR' transient_factory_test31.txt && fail 'the check fired for a camera it was not calibrated on'
finish_case

# A NaN diagnostic or a missing limit is not something to judge.
start_case nan_diagnostic_is_silent NaN NaN '' ''
CAMERA_SETTINGS=TTUQ1b1x1 report_new_image_bad_worst_quadrant "$IMAGE" "1st new image" 5.92
grep -q 'ERROR' transient_factory_test31.txt && fail 'a NaN diagnostic raised an ERROR'
finish_case
start_case missing_limit_is_silent 5.983 4.410 '' ''
CAMERA_SETTINGS=TTUQ1b1x1 report_new_image_bad_worst_quadrant "$IMAGE" "1st new image" ''
grep -q 'ERROR' transient_factory_test31.txt && fail 'the check fired without a limit'
finish_case

# Exercise the new candidate transaction independently of Astrometry.net.
# The real-image system case covers accuracy; these failures cover preserving
# all original products when a solver, quality check or publication fails.
start_small_radius_case() {
 start_case "$1" 3.000 6.000 '' ''
 mkdir -p bin local_wcs_cache
 printf '#!/bin/sh\nexit 0\n' > bin/solve-field
 chmod +x bin/solve-field
 cat > util/fov_of_wcs_calibrated_image.sh <<'EOF'
#!/bin/sh
echo "Image size: 900.0'x600.0' 15.0(deg)x10.0(deg) 9576x6388 pix"
EOF
 chmod +x util/fov_of_wcs_calibrated_image.sh
 cp "wcs_$IMAGE" "local_wcs_cache/wcs_$IMAGE"
 printf 'original sidecar\n' > "wcs_$IMAGE.original"
 printf 'WCS_HEADER_DIAG: file=%s selection=current_pairs N_selected=4000 N_valid=4000 p95_sep_arcsec=45 n_q1=1000 n_q2=1000 n_q3=1000 n_q4=1000 occupied_cells_4x4=16/16\n' "$IMAGE" >> transient_factory_test31.txt
 cat > util/solve_plate_with_UCAC5 <<'EOF'
#!/usr/bin/env bash
printf 'called\n' >> solver_calls
[ -s "$VAST_ASTROMETRY_SMALL_RADIUS_SEED" ] || exit 9
printf 'candidate WCS\n' > "wcs_$SMALL_TEST_IMAGE"
printf 'candidate catalog\n' > "wcs_$SMALL_TEST_IMAGE.wcscat"
printf 'candidate UCAC5\n' > "wcs_$SMALL_TEST_IMAGE.wcscat.ucac5"
printf 'candidate-only sidecar\n' > "wcs_$SMALL_TEST_IMAGE.new_only"
sigma=0.300; count=4000; q1=1000; p95=2.0; cells=16/16
case "$SMALL_TEST_MODE" in
 no_diagnostic) exit 0 ;;
 nonfinite) sigma=NaN ;;
 bad_header) p95=30 ;;
 lost_quadrant) q1=1; count=3001 ;;
 lost_cells) cells=15/16 ;;
 missing_output) rm -f "wcs_$SMALL_TEST_IMAGE.wcscat.ucac5" ;;
esac
printf 'WCS_QUALITY_DIAG: file=%s N_match=%s sigma_overall_arcsec=%s sigma_q1_arcsec=0.36 sigma_q2_arcsec=0.36 sigma_q3_arcsec=0.36 sigma_q4_arcsec=0.36 n_q1=%s n_q2=1000 n_q3=1000 n_q4=1000 worst_quadrant_to_overall_ratio=1.2\n' "$SMALL_TEST_IMAGE" "$count" "$sigma" "$q1"
printf 'WCS_HEADER_DIAG: file=%s selection=current_pairs N_selected=%s N_valid=%s p95_sep_arcsec=%s n_q1=%s n_q2=1000 n_q3=1000 n_q4=1000 occupied_cells_4x4=%s\n' "$SMALL_TEST_IMAGE" "$count" "$count" "$p95" "$q1" "$cells"
[ "$SMALL_TEST_MODE" != failed_solver ] || exit 8
exit 0
EOF
 chmod +x util/solve_plate_with_UCAC5
 export SMALL_TEST_IMAGE="$IMAGE" SMALL_TEST_MODE="$1"
}

for mode in accepted failed_solver no_diagnostic nonfinite bad_header lost_quadrant lost_cells missing_output cache_failure backup_failure rollback_failure disabled no_local good_original ; do
 start_small_radius_case "$mode"
 # File operations are fault-injected in the caller, not in the child solver.
 cp() {
  local destination="" arg
  for arg in "$@"; do
   destination="$arg"
  done
  case "$SMALL_TEST_MODE:$destination" in
   cache_failure:local_wcs_cache/.wcs_small_radius_retry.*) return 1 ;;
   backup_failure:*/wcs_small_radius_retry.*/) return 1 ;;
  esac
  if [ "$SMALL_TEST_MODE" = rollback_failure ] && [ "$destination" = "wcs_$IMAGE" ];then return 1; fi
  command cp "$@"
 }
 if [ "$mode" = rollback_failure ];then SMALL_TEST_MODE=failed_solver; fi
 # The rollback fault must stay enabled while the child returns failure.
 if [ "$mode" = rollback_failure ];then
  cp() { if [ "${*: -1}" = "wcs_$IMAGE" ];then return 1; fi; command cp "$@"; }
 fi
 if [ "$mode" = good_original ];then diag_line 0.5 1.1 >> transient_factory_test31.txt; fi
 status=0
 if [ "$mode" = no_local ];then
  command() { if [ "$1" = -v ] && [ "$2" = solve-field ];then return 1; fi; builtin command "$@"; }
 fi
 if [ "$mode" = disabled ];then export VAST_SKIP_LOCAL_ASTROMETRY_REPAIR=1; fi
 CAMERA_SETTINGS=TTUQ1b1x1 PATH="$PWD/bin:$PATH" retry_wcs_with_small_radius "$IMAGE" "test image" 5.87 2 || status=$?
 unset -f cp
 if [ "$mode" = no_local ];then unset -f command; fi
 unset VAST_SKIP_LOCAL_ASTROMETRY_REPAIR
 if [ "$mode" = accepted ];then
  [ "$status" -eq 0 ] && [ "$WCS_SMALL_RADIUS_RETRY_KEPT" -eq 1 ] || fail 'good small-radius candidate rejected'
  grep -qx 'candidate WCS' "wcs_$IMAGE" || fail 'accepted WCS missing'
  cmp -s "wcs_$IMAGE" "local_wcs_cache/wcs_$IMAGE" || fail 'cache did not follow accepted WCS'
 elif [ "$mode" = rollback_failure ];then
  [ "$status" -ne 0 ] || fail 'failed rollback reported success'
  grep -q 'rollback failed' transient_factory_test31.txt || fail 'rollback failure not explained'
  backup_image=$(echo wcs_small_radius_retry.*/"wcs_$IMAGE")
  grep -qx 'order-3 WCS' "$backup_image" || fail 'rollback lost recovery copy'
 else
  [ "$status" -eq 0 ] && [ "$WCS_SMALL_RADIUS_RETRY_KEPT" -eq 0 ] || fail 'bad/skipped candidate reported accepted'
  grep -qx 'order-3 WCS' "wcs_$IMAGE" || fail 'original WCS lost'
  grep -qx 'order-3 catalog' "wcs_$IMAGE.wcscat" || fail 'original catalog lost'
  grep -qx 'original sidecar' "wcs_$IMAGE.original" || fail 'original sidecar lost'
  grep -qx 'order-3 WCS' "local_wcs_cache/wcs_$IMAGE" || fail 'rejected candidate changed cache'
  [ ! -e "wcs_$IMAGE.new_only" ] && [ ! -e "wcs_$IMAGE.wcscat.ucac5" ] || fail 'candidate-only sidecar survived rollback'
  kept_header=$(awk '$1=="WCS_HEADER_DIAG:" {line=$0} END {print line}' transient_factory_test31.txt)
  echo "$kept_header" | grep -q 'p95_sep_arcsec=45 ' || fail 'header diagnostic describes discarded candidate'
 fi
 case "$mode" in
  backup_failure|disabled|no_local|good_original) [ ! -e solver_calls ] || fail 'solver called for a skipped retry' ;;
  *) [ "$(wc -l < solver_calls)" -eq 1 ] || fail 'retry was not bounded to one solver call' ;;
 esac
 finish_case
done

echo "All $N_CASES WCS-quality retry tests passed."
