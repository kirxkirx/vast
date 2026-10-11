#!/usr/bin/env bash
# Fast failure-path tests. No sky catalog, network, plate solve or VaST run.
# The solver stub writes only FITS plumbing fixtures: these do not stand in
# for reference catalogs or validate astrometric accuracy. Real-field checks
# remain in test_vast.sh beside the Cyg-05 and Her-09 data-driven regressions.
set -eo pipefail
export LC_ALL=C
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$SCRIPT_DIR/../.." && pwd)
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vast-astrometry-safety.XXXXXX")
trap 'rm -rf -- "$TEST_DIR"' EXIT
export REAL_VAST_PATH="$REPO/"
export VAST_PATH="$TEST_DIR/stub/"
mkdir -p "$VAST_PATH"lib/astrometry "$VAST_PATH"util "$TEST_DIR/bin"
for name in vastrealpath wcs_header_file_looks_valid astrometry_wcs_is_valid log_astrometry_repair_strength astrometry_repair_seconds_left install_astrometry_wcs star_list_verify_retweak small_radius_hinted_resolve repair_tan_only_solution ;do
 awk -v name="$name" '
  $0=="function " name " {" { copy=1 }
  copy { print }
  copy && /^}/ { found=1; exit }
  END { if (!found) exit 1 }
 ' "$REPO/util/identify.sh" >> "$TEST_DIR/functions.sh"
done
awk '/^function select_ucac5_calibration_candidates / { copy=1 } copy {print} copy && /^}/ {exit}' "$REPO/util/magnitude_calibration.sh" >> "$TEST_DIR/functions.sh"
# shellcheck source=/dev/null
source "$TEST_DIR/functions.sh"
ln -s "$REPO/util/listhead" "$VAST_PATH"util/listhead
cat > "$VAST_PATH"lib/astrometry/get_image_dimentions <<'EOF'
#!/usr/bin/env bash
echo '--width 64 --height 64'
EOF
cat > "$VAST_PATH"util/fov_of_wcs_calibrated_image.sh <<'EOF'
#!/usr/bin/env bash
echo 'Image center: 270.0 31.0'
echo 'Image size: 900x600'
echo 'Image scale: 6.0"/pix'
EOF
cat > "$TEST_DIR/bin/solve-field" <<'EOF'
#!/usr/bin/env bash
while [ "$#" -gt 0 ];do
 case "$1" in --out) outname="$2"; shift 2 ;; --dir) outdir="$2"; shift 2 ;; *) shift ;; esac
done
outbase="$outdir/$outname"
echo "$outbase" >> "$SOLVER_CALLS"
if [ "$PROBE_PARTIAL" != 1 ];then
 cp "$PROBE_HEADER" "$outbase.wcs" || exit 1
 printf 1 > "$outbase.solved"
fi
exit "${PROBE_EXIT:-0}"
EOF
cat > "$TEST_DIR/bin/mv" <<'EOF'
#!/usr/bin/env bash
if [ "$PROBE_MV_FAIL" = 1 ];then exit 1; fi
exec "$REAL_MV" "$@"
EOF
cat > "$VAST_PATH"lib/astrometry/strip_wcs_keywords <<'EOF'
#!/usr/bin/env bash
if [ "$PROBE_STRIP_FAIL" = 1 ];then exit 1; fi
exec "$REAL_VAST_PATH"lib/astrometry/strip_wcs_keywords "$@"
EOF
cat > "$VAST_PATH"lib/astrometry/insert_wcs_header <<'EOF'
#!/usr/bin/env bash
if [ "$PROBE_INSERT_FAIL" = 1 ];then exit 1; fi
exec "$REAL_VAST_PATH"lib/astrometry/insert_wcs_header "$@"
EOF
cat > "$VAST_PATH"util/modhead <<'EOF'
#!/usr/bin/env bash
if [ "$PROBE_PROVENANCE_FAIL" = 1 ];then exit 1; fi
if [ "$PROBE_PROVENANCE_SILENT" = 1 ];then exit 0; fi
exec "$REAL_VAST_PATH"util/modhead "$@"
EOF
chmod +x "$TEST_DIR/bin/"* "$VAST_PATH"lib/astrometry/* "$VAST_PATH"util/modhead "$VAST_PATH"util/fov_of_wcs_calibrated_image.sh
REAL_MV=$(command -v mv)
export REAL_MV PATH="$TEST_DIR/bin:$PATH"
cd "$TEST_DIR"

fail() { echo "FAIL: $*" >&2; exit 1; }
pad_header() {
 local bytes
 bytes=$(wc -c < "$1")
 printf '%*s' "$(( (2880-bytes%2880)%2880 ))" '' >> "$1"
}
# A minimal FITS header, with genuine syntax and finite WCS values, solely
# for validation, output installation and injected write/rename failures.
printf '%-80s' 'SIMPLE  =                    T' 'BITPIX  =                    8' 'NAXIS   =                    0' 'EXTEND  =                    T' \
 "CTYPE1  = 'RA---TAN-SIP'" "CTYPE2  = 'DEC--TAN-SIP'" \
 'CRVAL1  =                270.0' 'CRVAL2  =                 31.0' 'CRPIX1  =                 32.0' 'CRPIX2  =                 32.0' \
 'CD1_1   =    -0.001666666666667' 'CD1_2   =                  0.0' 'CD2_1   =                  0.0' 'CD2_2   =     0.001666666666667' \
 'A_ORDER =                    2' 'B_ORDER =                    2' 'A_2_0   =                 1e-8' 'B_0_2   =                -1e-8' \
 'COMMENT log odds: 1575.11' 'COMMENT nmatch: 196' 'HISTORY failure-path test fixture' 'END' > good.wcs
pad_header good.wcs
printf '%-80s' 'SIMPLE  =                    T' 'BITPIX  =                   16' 'NAXIS   =                    2' 'NAXIS1  =                   64' 'NAXIS2  =                   64' 'END' > image.fits
pad_header image.fits
dd if=/dev/zero bs=2880 count=3 >> image.fits 2>/dev/null
printf 'solver input is not interpreted by this stub\n' > input.xyls
export FITSFILE="$TEST_DIR/image.fits" PROBE_HEADER="$TEST_DIR/good.wcs" SOLVER_CALLS="$TEST_DIR/calls.log"
export TIMEOUT_COMMAND=env VAST_TWEAK_ORDER=3
# env cannot act as timeout; a shell function consumes only its time argument.
probe_timeout() { shift; "$@"; }
TIMEOUT_COMMAND=probe_timeout
export ASTROMETRYNET_LOCAL_OR_REMOTE=remote PLATE_SOLVE_SERVER=test
unset VAST_SKIP_LOCAL_ASTROMETRY_REPAIR VAST_SKIP_SMALL_RADIUS_RESOLVE ASTROMETRY_REPAIR_DEADLINE VAST_LOCAL_ASTROMETRY_REPAIR_TIMEOUT
N_CASES=0
for helper in star_list_verify_retweak small_radius_hinted_resolve ;do
 for case_name in success timeout partial zero_order missing_b_order nonfinite singular rename_failure ;do
  export PROBE_EXIT=0 PROBE_PARTIAL=0 PROBE_MV_FAIL=0
  cp good.wcs trial.wcs
  case "$case_name" in
   timeout) PROBE_EXIT=124 ;;
   partial) PROBE_EXIT=124; PROBE_PARTIAL=1 ;;
   zero_order) "$REPO/util/modhead" trial.wcs A_ORDER 0 >/dev/null ;;
   missing_b_order) "$REPO/util/modhead" trial.wcs B_ORDER DELETE >/dev/null ;;
   nonfinite) "$REPO/util/modhead" trial.wcs CD1_1 NaN >/dev/null ;;
   singular) "$REPO/util/modhead" trial.wcs CD1_1 0 >/dev/null ;;
   rename_failure) PROBE_MV_FAIL=1 ;;
  esac
  PROBE_HEADER="$TEST_DIR/trial.wcs"
  printf 'previous result\n' > output.wcs
  status=0
  "$helper" input.xyls good.wcs output.wcs > case.log 2>&1 || status=$?
  if [ "$case_name" = success ];then
   if [ "$status" -ne 0 ] || ! astrometry_wcs_is_valid output.wcs sip ;then cat case.log; fail "$helper $case_name"; fi
   grep -q 'post_tweak_nmatch=196' case.log || fail 'post-tweak metrics missing'
  else
   [ "$status" -ne 0 ] || fail "$helper accepted $case_name"
   grep -qx 'previous result' output.wcs || fail "$helper overwrote fallback on $case_name"
  fi
  N_CASES=$((N_CASES+1))
 done
done
export PROBE_EXIT=0 PROBE_PARTIAL=0 PROBE_MV_FAIL=0 PROBE_HEADER="$TEST_DIR/good.wcs"
: > "$SOLVER_CALLS"
export VAST_SKIP_LOCAL_ASTROMETRY_REPAIR=1
for helper in star_list_verify_retweak small_radius_hinted_resolve repair_tan_only_solution ;do
 if "$helper" input.xyls good.wcs image.fits output.wcs > case.log 2>&1 ;then fail "$helper ignored opt-out"; fi
done
[ ! -s "$SOLVER_CALLS" ] || fail 'remote-only policy invoked local solve-field'
unset VAST_SKIP_LOCAL_ASTROMETRY_REPAIR
ASTROMETRY_REPAIR_DEADLINE=$(date +%s)
export ASTROMETRY_REPAIR_DEADLINE
if repair_tan_only_solution input.xyls good.wcs image.fits output.wcs > case.log 2>&1 ;then fail 'expired repair budget accepted'; fi
[ ! -s "$SOLVER_CALLS" ] || fail 'expired repair budget invoked solver'
unset ASTROMETRY_REPAIR_DEADLINE
N_CASES=$((N_CASES+2))

# Simultaneous attempts must not share work files, even for the same seed.
: > "$SOLVER_CALLS"
star_list_verify_retweak input.xyls good.wcs concurrent1.wcs > concurrent1.log 2>&1 &
pid1=$!
star_list_verify_retweak input.xyls good.wcs concurrent2.wcs > concurrent2.log 2>&1 &
pid2=$!
status=0
wait "$pid1" || status=1
wait "$pid2" || status=1
[ "$status" -eq 0 ] || fail 'concurrent attempts failed'
[ "$(sort -u "$SOLVER_CALLS" | wc -l)" -eq 2 ] || fail 'concurrent work files collided'
N_CASES=$((N_CASES+1))

for case_name in success strip insert provenance silent_provenance rename ;do
 export PROBE_STRIP_FAIL=0 PROBE_INSERT_FAIL=0 PROBE_PROVENANCE_FAIL=0 PROBE_PROVENANCE_SILENT=0 PROBE_MV_FAIL=0
 case "$case_name" in
  strip) PROBE_STRIP_FAIL=1 ;;
  insert) PROBE_INSERT_FAIL=1 ;;
  provenance) PROBE_PROVENANCE_FAIL=1 ;;
  silent_provenance) PROBE_PROVENANCE_SILENT=1 ;;
  rename) PROBE_MV_FAIL=1 ;;
 esac
 cp image.fits installed.fits
 status=0
 install_astrometry_wcs good.wcs image.fits installed.fits verify_retweak_remote > case.log 2>&1 || status=$?
 if [ "$case_name" = success ];then
  if [ "$status" -ne 0 ] || ! astrometry_wcs_is_valid installed.fits sip ;then cat case.log; fail 'WCS installation'; fi
  "$REPO/util/listhead" installed.fits | grep -q "VAST004.*verify_retweak_remote" || fail 'missing repair provenance'
 else
  [ "$status" -ne 0 ] || fail "installation accepted $case_name failure"
  cmp image.fits installed.fits || fail "installation changed fallback on $case_name failure"
 fi
 N_CASES=$((N_CASES+1))
done
export PROBE_MV_FAIL=0
ln -s image.fits protected.fits
if install_astrometry_wcs good.wcs image.fits protected.fits verify_retweak > case.log 2>&1 ;then fail 'replaced a protected symlink'; fi
[ -L protected.fits ] || fail 'protected symlink was removed'
N_CASES=$((N_CASES+1))

# Test only candidate selection, not photometric calibration: malformed
# numbers and the missing-match sentinel must not count as comparison stars.
printf '%s\n' \
 '1 0 0 1 1 100 1 -10 0.01 0 12.1 0' \
 '2 0 0 1 1 100 1 -10 0.01 0 12.2 0.02' \
 '3 0 0 1 1 100 1 -10 0.01 0 0 0' \
 '4 0 0 1 1 100 1 -10 0.01 0 NaN 0' \
 '5 0 0 1 1 100 1 -10 0.01 0 12.3 -1' \
 '6 0 0 1 1 100 1 -10 0.01 0 12.3 inf' > selection.txt
select_ucac5_calibration_candidates selection.txt > selected.txt
[ "$(wc -l < selected.txt)" -eq 2 ] || fail 'C-band candidate count'
grep -q '^out00001.dat .* 0.000000$' selected.txt || fail 'rejected legitimate zero magnitude error'
N_CASES=$((N_CASES+1))

# A real CFITSIO write/close failure: copying the small input fits below the
# limit, but adding this large header exceeds it. Ignore SIGXFSZ only in the
# constrained child so it can return the write error and remove its output.
dd if=good.wcs bs=80 count=21 of=large.wcs 2>/dev/null
for ((i=0; i<250; i++));do printf '%-80s' 'COMMENT bounded writer regression' >> large.wcs; done
printf '%-80s' END >> large.wcs
pad_header large.wcs
mkdir writer_control writer_limited
cp image.fits writer_control/input.fits
cp image.fits writer_limited/input.fits
(
 cd writer_control
 "$REPO/lib/astrometry/insert_wcs_header" ../large.wcs input.fits > writer.log 2>&1
) || fail 'writer control'
[ "$(wc -c < writer_control/wcs_input.fits)" -gt 24576 ] || fail 'writer control did not exercise header growth'
status=0
(
 cd writer_limited
 trap '' XFSZ
 ulimit -f 12 || exit 99
 "$REPO/lib/astrometry/insert_wcs_header" ../large.wcs input.fits > writer.log 2>&1
) || status=$?
[ "$status" -ne 0 ] && [ "$status" -ne 99 ] || fail 'writer did not report bounded write failure'
[ ! -e writer_limited/wcs_input.fits ] || fail 'writer left incomplete output'
if grep -q 'All done!' writer_limited/writer.log ;then fail 'writer printed success after write failure'; fi
N_CASES=$((N_CASES+1))

# Run the second-pass decision and final restoration blocks verbatim, without
# invoking the identify.sh main program or contacting a remote server.
awk '
 /^    SECOND_SOLVE_STATUS=/ {copy=1}
 copy && /^    # Keep the image-based diagnostic/ {found=1; exit}
 copy {print}
 END {if (!found) exit 1}
' "$REPO/util/identify.sh" > second_pass.sh
awk '
 /^ if \[ -n "\$TAN_ONLY_FALLBACK_IMAGE"/ {copy=1}
 copy {print}
 copy && /^ fi$/ {found=1; exit}
 END {if (!found) exit 1}
' "$REPO/util/identify.sh" > restore.sh
BASENAME_FITSFILE=second_pass.fits
cp writer_control/wcs_input.fits "wcs_$BASENAME_FITSFILE"
cp "wcs_$BASENAME_FITSFILE" first_pass.saved
if ! (
 set +e
 false
 # shellcheck source=/dev/null
 source ./second_pass.sh
) > case.log 2>&1 ;then fail 'second-pass failure lost the first pass'; fi
cmp "wcs_$BASENAME_FITSFILE" first_pass.saved || fail 'failed second pass altered the first pass'
cmp out$$.wcs first_pass.saved || fail 'failed second pass retained the wrong repair seed'
N_CASES=$((N_CASES+1))

for case_name in success failed_move ;do
 mv "wcs_$BASENAME_FITSFILE" fallback.fits
 export TAN_ONLY_FALLBACK_IMAGE=fallback.fits
 ERROR_STATUS=2
 export PROBE_MV_FAIL=0
 if [ "$case_name" = failed_move ];then PROBE_MV_FAIL=1; fi
 # shellcheck source=/dev/null
 source ./restore.sh > case.log 2>&1
 if [ "$case_name" = success ];then
  [ "$ERROR_STATUS" -eq 0 ] || fail 'offline fallback did not clear remote failure'
  cmp "wcs_$BASENAME_FITSFILE" first_pass.saved || fail 'restored fallback differs'
 else
  [ "$ERROR_STATUS" -ne 0 ] && [ -f fallback.fits ] || fail 'failed restoration reported success or lost fallback'
 fi
 N_CASES=$((N_CASES+1))
done
export PROBE_MV_FAIL=0

# Exercise the factory wait block verbatim. A failed child leaves a plausible
# image behind; every child must still be drained and failure must survive.
awk '
 /^  CALIBRATION_FAILED=0$/ {copy=1}
 copy && /^  record_timing / {found=1; exit}
 copy {print}
 END {if (!found) exit 1}
' "$REPO/util/transients/transient_factory_test31.sh" > wait_calibrations.sh
( printf 'partial image\n' > partial.fits; exit 7 ) &
pid1=$!
( printf 'finished\n' > other_completed.txt ) &
pid2=$!
# The arrays are consumed by the wait block extracted above.
# shellcheck disable=SC2034
calibrationPIDs=("$pid1" "$pid2")
# shellcheck disable=SC2034
calibrationImages=(partial.fits other.fits)
# shellcheck source=/dev/null
source ./wait_calibrations.sh
[ "$CALIBRATION_FAILED" -eq 1 ] && [ -s other_completed.txt ] || fail 'factory lost child failure or did not drain jobs'
grep -q 'partial.fits' transient_factory_test31.txt || fail 'factory lost failed image name'
N_CASES=$((N_CASES+1))
echo "All $N_CASES astrometry safety cases passed."
