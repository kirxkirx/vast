#!/usr/bin/env bash
#
# Dedicated test of the plate-solution refit policy implemented in
# src/solve_plate_with_UCAC5.c (refit_sip_from_catalog_matches) and
# util/identify.sh.
#
# THE POLICY UNDER TEST
# ---------------------
# 1. If the input image carries a WCS that VaST trusts, that solution is kept
#    as it is and is NOT refit. "Trusted" is decided in exactly one place,
#    check_if_we_know_the_telescope_and_can_blindly_trust_wcs_from_the_image()
#    in util/identify.sh, and covers both solutions made by Astrometry.net,
#    SCAMP or SWarp and the mission pipelines (ZTF, TESS, ATLAS, ASTAP).
#    util/identify.sh passes the decision to util/solve_plate_with_UCAC5 in a
#    <plate-solved image>.blindly_trusted_wcs marker file.
# 2. If the input image has no trusted WCS, VaST solves it and then figures
#    out the best-fit distortion model from the UCAC5 cross-matches: the SIP
#    order is chosen from the data (orders 2, 3 and - given enough
#    matches - 5 are tried, the higher one
#    has to earn its extra terms) together with the coefficients.
# 3. A refit of a trusted solution happens only when it is explicitly asked
#    for with VAST_FORCE_SIP_REFIT=1 - which is what
#    util/solve_plate_with_best_sip_order.sh does.
# 4. util/solve_plate_with_UCAC5 never rewrites the WCS of the image it was
#    handed, and never writes through a symbolic link (the transient search
#    links cached solved reference images into the working directory).
#
# WHY A SEPARATE SCRIPT
# ---------------------
# util/examples/test_vast.sh exercises the pipeline end to end and would only
# notice a policy regression indirectly, through a shifted magnitude or a
# moved position. This script asserts the policy itself, per camera, and is
# cheap enough to run on its own after touching the plate-solving code.
#
# USAGE
# -----
#   util/examples/test_sip_refit_policy.sh [CAMERA_TAG]
#
# Runs from the VaST root directory. Exits 0 when every check passed,
# 1 otherwise, and prints a list of failed test codes.
# With an optional camera tag (NMW, NMWSTL, NMWTTU, TICATESS) only that
# camera is exercised - handy while chasing down a single failure.
#
# The cases that need a fresh blind plate solve (the "no trusted WCS" half of
# the policy) are skipped unless a local copy of the Astrometry.net code is
# available: the remote plate-solve service is slow and, on wide fields,
# accurate only to tens of arcsec, which is not a useful baseline for
# checking a distortion model.

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Work from the VaST root directory
if [ -n "$VAST_PATH" ];then
 cd "$VAST_PATH" || exit 1
else
 SCRIPT_DIR="$(dirname "$0")"
 cd "$SCRIPT_DIR/../.." || exit 1
fi
VAST_PATH="$PWD/"
export VAST_PATH

TEST_DATA_DIR="../SIP_refit_policy_test"
TEST_DATA_URL_LIST="http://tau.kirx.net/vast_test_data/SIP_refit_policy_test.tar.bz2 http://scan.sai.msu.ru/~kirx/data/vast_tests/SIP_refit_policy_test.tar.bz2"

FAILED_TEST_CODES=""
N_CHECKS_RUN=0
N_CHECKS_FAILED=0
ONLY_THIS_CAMERA="$1"

# The images this test is built around, one per camera:
#   "<file>|<tag>|<max residual arcsec accepted after a refit>|<blind-solvable>"
# The tag is used in the failure codes. The residual limits are generous -
# this test is about the policy, not about squeezing the last tenth of an
# arcsecond.
#   NMW      SBIG ST-8300, 8.4"/pix telephoto lens
#   NMWSTL   SBIG STL-11000M, ~14"/pix telephoto lens
#   NMWTTU   QHY600M, ~6"/pix, the widest frame we handle (9576x6388)
#   TICATESS TESS full frame image, ~21"/pix, mission TAN-SIP solution
#
# The last field says whether the frame can be blind-solved from scratch, and
# so whether the "no trusted WCS" case can be exercised on it. A TICA TESS
# full frame image cannot: it spans about 12.5 degrees, and over such a field
# the quads astrometry.net builds from the detected stars no longer match the
# index quads well enough (verified on this machine, which does have the
# matching index-4117 scale range - every index from 4205 down to 4113 was
# tried and reported "Field 1 did not solve"). That is not a VaST defect, and
# it is a neat illustration of why this policy exists at all: for a TESS FFI
# the mission solution is the only practical astrometry there is, so it must
# be trusted rather than recomputed.
IMAGE_LIST="Sco6_2012-4-18_0-30-54_002.fts|NMW|4.0|yes
025_2022-8-27_20-27-36_002.fts|NMWSTL|8.0|yes
Aql-03-Q1b1x1_2026-05-15_03-45-29_20.00sec_0.00C_LIGHT_0122.fits|NMWTTU|4.0|yes
s0081-o2a-cam2-ccd3__hlsp_tica_tess_ffi_s0081-o2-00990938-cam2-ccd3_tess_v01_img.fits|TICATESS|25.0|no"

#################################
# Helpers

function record_check {
 # $1 - 0 for pass, anything else for fail
 # $2 - failure code
 # $3 - human readable description
 N_CHECKS_RUN=$((N_CHECKS_RUN + 1))
 if [ "$1" -eq 0 ];then
  echo "  PASSED  $3"
 else
  N_CHECKS_FAILED=$((N_CHECKS_FAILED + 1))
  FAILED_TEST_CODES="$FAILED_TEST_CODES $2"
  echo "  FAILED  $3   [$2]"
 fi
}

function file_checksum {
 if command -v md5sum &>/dev/null ;then
  md5sum < "$1" | awk '{print $1}'
 elif command -v md5 &>/dev/null ;then
  md5 -q "$1"
 else
  # last resort: size plus a byte count, enough to notice a rewritten header
  wc -c < "$1" | awk '{print $1}'
 fi
}

# Print the WCS-defining keywords of an image as one line, so two solutions
# can be compared with a plain string comparison.
function wcs_signature {
 "$VAST_PATH"util/listhead "$1" 2>/dev/null | grep -E "^(CTYPE1|CTYPE2|CRVAL1|CRVAL2|CRPIX1|CRPIX2|CD1_1|CD1_2|CD2_1|CD2_2|A_ORDER|B_ORDER|A_0_0|A_1_1|A_2_0|B_0_0|B_1_1|B_2_0)" | tr -s ' ' | tr '\n' ' '
}

function sip_order_of_image {
 "$VAST_PATH"util/listhead "$1" 2>/dev/null | awk '/^A_ORDER/{print $3; exit}'
}

function wcs_quality_sigma_from_log {
 grep 'WCS_QUALITY_DIAG:' "$1" | tail -n1 | tr ' ' '\n' | awk -F'=' '$1 == "sigma_overall_arcsec" {print $2}'
}

# Remove everything a previous case left behind, without touching the
# pristine dataset
function clean_workspace {
 rm -f wcs_sippolicy_* sippolicy_* 2>/dev/null
 rm -rf sip_refit_policy_input sip_refit_policy_shared_cache 2>/dev/null
 "$VAST_PATH"util/clean_data.sh >/dev/null 2>&1
}

#################################
# Preconditions

if [ ! -x "$VAST_PATH"util/solve_plate_with_UCAC5 ];then
 echo "ERROR: util/solve_plate_with_UCAC5 not found. Run 'make' first."
 exit 1
fi
if [ ! -x "$VAST_PATH"lib/astrometry/strip_wcs_keywords ];then
 echo "ERROR: lib/astrometry/strip_wcs_keywords not found. Run 'make' first."
 exit 1
fi

# Get the test data if we do not have them yet
if [ ! -d "$TEST_DATA_DIR" ];then
 echo "Downloading the test dataset..."
 cd .. || exit 1
 for URL in $TEST_DATA_URL_LIST ;do
  curl --silent --show-error --retry 2 --retry-delay 30 --continue-at - -O "$URL" && break
 done
 if [ -s SIP_refit_policy_test.tar.bz2 ];then
  tar -xjf SIP_refit_policy_test.tar.bz2 && rm -f SIP_refit_policy_test.tar.bz2
 fi
 cd "$VAST_PATH" || exit 1
fi
if [ ! -d "$TEST_DATA_DIR" ];then
 echo "SIP refit policy test: NOT PERFORMED (test dataset $TEST_DATA_DIR is not available)"
 exit 0
fi

# Do we have a local copy of the Astrometry.net code? Mirror util/identify.sh
# so the binary is found where it is normally installed.
if [ -d /usr/local/astrometry/bin ] && ! echo "$PATH" | grep -q '/usr/local/astrometry/bin' ;then
 export PATH="$PATH:/usr/local/astrometry/bin"
fi
if [ -d /usr/share/astrometry/bin ] && ! echo "$PATH" | grep -q '/usr/share/astrometry/bin' ;then
 export PATH="$PATH:/usr/share/astrometry/bin"
fi
HAVE_LOCAL_SOLVE_FIELD=0
if command -v solve-field &>/dev/null && [ -x "$(command -v solve-field)" ];then
 HAVE_LOCAL_SOLVE_FIELD=1
fi

echo "########################################################"
echo "# SIP refit policy test"
echo "# dataset: $TEST_DATA_DIR"
if [ $HAVE_LOCAL_SOLVE_FIELD -eq 1 ];then
 echo "# local Astrometry.net: yes (the no-trusted-WCS cases will run)"
else
 echo "# local Astrometry.net: NO (the no-trusted-WCS cases will be skipped)"
fi
echo "########################################################"

#################################
# The tests

for IMAGE_ENTRY in $IMAGE_LIST ;do

 IMAGE_BASENAME=$(echo "$IMAGE_ENTRY" | awk -F'|' '{print $1}')
 CAMERA_TAG=$(echo "$IMAGE_ENTRY" | awk -F'|' '{print $2}')
 MAX_RESIDUAL_ARCSEC=$(echo "$IMAGE_ENTRY" | awk -F'|' '{print $3}')
 BLIND_SOLVABLE=$(echo "$IMAGE_ENTRY" | awk -F'|' '{print $4}')
 SOURCE_IMAGE="$TEST_DATA_DIR/$IMAGE_BASENAME"

 # An optional argument restricts the run to one camera, which makes a
 # debugging loop on a single frame much shorter than the full set.
 if [ -n "$ONLY_THIS_CAMERA" ] && [ "$ONLY_THIS_CAMERA" != "$CAMERA_TAG" ];then
  continue
 fi

 echo ""
 echo "=== $CAMERA_TAG  ($IMAGE_BASENAME) ==="

 if [ ! -s "$SOURCE_IMAGE" ];then
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_IMAGE_MISSING" "test image is present in the dataset"
  continue
 fi

 ############################################################
 # Case 1: a trusted WCS is kept, and the input file is not touched
 ############################################################
 clean_workspace
 WORK_IMAGE="sippolicy_${CAMERA_TAG}.fits"
 cp "$SOURCE_IMAGE" "$WORK_IMAGE"
 CHECKSUM_BEFORE=$(file_checksum "$WORK_IMAGE")
 SIGNATURE_BEFORE=$(wcs_signature "$WORK_IMAGE")
 RUN_LOG="sip_refit_policy_trusted_${CAMERA_TAG}.log"
 "$VAST_PATH"util/solve_plate_with_UCAC5 --no_photometric_catalog "$WORK_IMAGE" > "$RUN_LOG" 2>&1

 grep -q -e 'trusts the WCS' -e 'blindly trusting it, no refit' "$RUN_LOG"
 record_check $? "SIPPOLICY_${CAMERA_TAG}_TRUSTED_NOT_DETECTED" "the trusted WCS is recognized and kept"

 if grep -q 'applied the refit solution' "$RUN_LOG" ;then
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_REFIT_ON_TRUSTED" "no refit is applied to a trusted solution"
 else
  record_check 0 "" "no refit is applied to a trusted solution"
 fi

 CHECKSUM_AFTER=$(file_checksum "$WORK_IMAGE")
 if [ "$CHECKSUM_BEFORE" = "$CHECKSUM_AFTER" ];then
  record_check 0 "" "the input image file is left byte-identical"
 else
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_INPUT_MODIFIED" "the input image file is left byte-identical"
 fi

 SIGNATURE_AFTER=$(wcs_signature "wcs_$WORK_IMAGE")
 if [ "$SIGNATURE_BEFORE" = "$SIGNATURE_AFTER" ];then
  record_check 0 "" "the plate-solved copy carries the original, unmodified WCS"
 else
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_WCS_CHANGED" "the plate-solved copy carries the original, unmodified WCS"
 fi

 # util/identify.sh has to have left the marker that carries its decision
 if [ -s "wcs_$WORK_IMAGE.blindly_trusted_wcs" ];then
  record_check 0 "" "util/identify.sh recorded its trust decision in a marker file"
 else
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_NO_TRUST_MARKER" "util/identify.sh recorded its trust decision in a marker file"
 fi

 ############################################################
 # Case 2: an explicitly requested refit does run on the same image
 ############################################################
 clean_workspace
 cp "$SOURCE_IMAGE" "$WORK_IMAGE"
 RUN_LOG="sip_refit_policy_forced_${CAMERA_TAG}.log"
 VAST_FORCE_SIP_REFIT=1 "$VAST_PATH"util/solve_plate_with_UCAC5 --no_photometric_catalog "$WORK_IMAGE" > "$RUN_LOG" 2>&1

 grep -q 'VAST_FORCE_SIP_REFIT is set' "$RUN_LOG"
 record_check $? "SIPPOLICY_${CAMERA_TAG}_FORCE_NOT_HONORED" "VAST_FORCE_SIP_REFIT=1 overrides the trusted-WCS rule"

 # The trusted-WCS skip must have been bypassed...
 if grep -q 'trusts the WCS' "$RUN_LOG" ;then
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_FORCE_DID_NOT_BYPASS_TRUST" "the trusted-WCS skip is bypassed"
 else
  record_check 0 "" "the trusted-WCS skip is bypassed"
 fi

 # ... and the refit must have reached a decision of its own. Reaching a
 # decision does NOT mean the refit is applied: the frame-coverage guard and
 # the minimum-matches guard legitimately decline a forced refit too. The
 # NMW-STL plate-solve-failure reference image is the standing example - its
 # UCAC5 matches sit almost entirely in the upper half of the frame, so an
 # order-3 polynomial fitted on them would extrapolate wildly into the lower
 # half, and the guard is right to refuse.
 if grep -q -e 'SIP order . trial' -e 'do not cover the frame' -e 'catalog matches (<' "$RUN_LOG" ;then
  record_check 0 "" "the forced refit reaches a refit decision"
 else
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_FORCED_REFIT_NO_DECISION" "the forced refit reaches a refit decision"
 fi

 # ... and the caller's file still must not be rewritten
 CHECKSUM_AFTER=$(file_checksum "$WORK_IMAGE")
 if [ "$CHECKSUM_BEFORE" = "$CHECKSUM_AFTER" ];then
  record_check 0 "" "a forced refit still does not rewrite the input image"
 else
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_FORCED_INPUT_MODIFIED" "a forced refit still does not rewrite the input image"
 fi

 ############################################################
 # Case 3: the write target is a symbolic link - never followed
 ############################################################
 clean_workspace
 cp "$SOURCE_IMAGE" "$WORK_IMAGE"
 mkdir -p sip_refit_policy_shared_cache
 cp "$SOURCE_IMAGE" "sip_refit_policy_shared_cache/wcs_$WORK_IMAGE"
 CACHE_CHECKSUM_BEFORE=$(file_checksum "sip_refit_policy_shared_cache/wcs_$WORK_IMAGE")
 ln -sf "sip_refit_policy_shared_cache/wcs_$WORK_IMAGE" "wcs_$WORK_IMAGE"
 RUN_LOG="sip_refit_policy_symlink_${CAMERA_TAG}.log"
 VAST_FORCE_SIP_REFIT=1 "$VAST_PATH"util/solve_plate_with_UCAC5 --no_photometric_catalog "$WORK_IMAGE" > "$RUN_LOG" 2>&1
 CACHE_CHECKSUM_AFTER=$(file_checksum "sip_refit_policy_shared_cache/wcs_$WORK_IMAGE")
 if [ "$CACHE_CHECKSUM_BEFORE" = "$CACHE_CHECKSUM_AFTER" ];then
  record_check 0 "" "a shared file reached through a symbolic link is not rewritten"
 else
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_SYMLINK_TARGET_MODIFIED" "a shared file reached through a symbolic link is not rewritten"
 fi
 rm -rf sip_refit_policy_shared_cache
 rm -f "wcs_$WORK_IMAGE"

 ############################################################
 # Case 4: no trusted WCS - solve, then figure out order and coefficients
 ############################################################
 if [ $HAVE_LOCAL_SOLVE_FIELD -eq 0 ];then
  echo "  SKIPPED the no-trusted-WCS cases (no local Astrometry.net)"
  clean_workspace
  continue
 fi
 if [ "$BLIND_SOLVABLE" != "yes" ];then
  echo "  SKIPPED the no-trusted-WCS cases (this frame cannot be blind-solved from scratch - see the comment on IMAGE_LIST)"
  clean_workspace
  continue
 fi

 clean_workspace
 # Keep the unsolved image OUTSIDE the current directory. util/identify.sh
 # treats an input that already sits in the working directory as its own
 # scratch copy and strips the WCS keywords out of it in place - it says so
 # ("Not creating a local copy of the FITS image as the input image is
 # already in the current directory. The input image will be modified!",
 # util/identify.sh:759). That is long-standing behaviour and not what this
 # case is about; passing the image by a path outside the working directory
 # is also how VaST is normally used.
 rm -rf sip_refit_policy_input
 mkdir -p sip_refit_policy_input
 UNTRUSTED_IMAGE="sip_refit_policy_input/$WORK_IMAGE"
 cp "$SOURCE_IMAGE" "$UNTRUSTED_IMAGE"
 "$VAST_PATH"lib/astrometry/strip_wcs_keywords "$UNTRUSTED_IMAGE" > /dev/null 2>&1
 # After stripping, the image must genuinely look unsolved
 if "$VAST_PATH"util/listhead "$UNTRUSTED_IMAGE" 2>/dev/null | grep -q '^CTYPE1' ;then
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_STRIP_FAILED" "the WCS keywords were stripped from the working copy"
  rm -rf sip_refit_policy_input
  continue
 else
  record_check 0 "" "the WCS keywords were stripped from the working copy"
 fi
 CHECKSUM_BEFORE=$(file_checksum "$UNTRUSTED_IMAGE")
 RUN_LOG="sip_refit_policy_untrusted_${CAMERA_TAG}.log"
 "$VAST_PATH"util/solve_plate_with_UCAC5 --no_photometric_catalog "$UNTRUSTED_IMAGE" > "$RUN_LOG" 2>&1

 if grep -q -e 'trusts the WCS' -e 'blindly trusting it, no refit' "$RUN_LOG" ;then
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_UNTRUSTED_TREATED_AS_TRUSTED" "an image with no WCS is not treated as trusted"
 else
  record_check 0 "" "an image with no WCS is not treated as trusted"
 fi

 # Both candidate orders have to be tried and one of them selected
 grep -q 'SIP order 2 trial' "$RUN_LOG"
 record_check $? "SIPPOLICY_${CAMERA_TAG}_ORDER2_NOT_TRIED" "SIP order 2 is tried"
 grep -q 'SIP order 3 trial' "$RUN_LOG"
 record_check $? "SIPPOLICY_${CAMERA_TAG}_ORDER3_NOT_TRIED" "SIP order 3 is tried"
 grep -q 'selected SIP order' "$RUN_LOG"
 record_check $? "SIPPOLICY_${CAMERA_TAG}_NO_ORDER_SELECTED" "one of the orders is selected"

 # The refit has to run to a DECISION on the untrusted image: it either
 # applies its solution or - just as legitimately - keeps the fresh
 # solve-field solution when that one is already within the keep-if-better
 # margin. Which way it goes depends on how good the blind solve happened
 # to be (under heavy CPU load solve-field works with a different time
 # budget and its tweak quality varies run to run - observed when this
 # test ran inside test_vast.sh next to other load), so BOTH outcomes are
 # accepted; the TAN-SIP and residual checks below must hold either way.
 grep -q -e 'applied the refit solution' -e 'does not sufficiently improve' "$RUN_LOG"
 record_check $? "SIPPOLICY_${CAMERA_TAG}_REFIT_NO_DECISION" "the refit reached an apply-or-keep decision"
 REFIT_WAS_APPLIED=0
 grep -q 'applied the refit solution' "$RUN_LOG" && REFIT_WAS_APPLIED=1

 # The header of the solved copy has to describe the selected order when
 # the refit applied; when the original was kept, the header carries
 # whatever order solve-field fitted, which merely has to be present
 SELECTED_ORDER=$(grep 'selected SIP order' "$RUN_LOG" | tail -n1 | awk '{print $NF}')
 HEADER_ORDER=$(sip_order_of_image "wcs_$WORK_IMAGE")
 if [ "$REFIT_WAS_APPLIED" -eq 1 ];then
  if [ -n "$SELECTED_ORDER" ] && [ "$SELECTED_ORDER" = "$HEADER_ORDER" ];then
   record_check 0 "" "the solved image header carries the selected SIP order ($SELECTED_ORDER)"
  else
   record_check 1 "SIPPOLICY_${CAMERA_TAG}_ORDER_MISMATCH_${SELECTED_ORDER}_vs_${HEADER_ORDER}" "the solved image header carries the selected SIP order"
  fi
 else
  if [ -n "$HEADER_ORDER" ];then
   record_check 0 "" "the kept solve-field solution carries a SIP order ($HEADER_ORDER)"
  else
   record_check 1 "SIPPOLICY_${CAMERA_TAG}_KEPT_SOLUTION_NO_SIP_ORDER" "the kept solve-field solution carries a SIP order"
  fi
 fi

 CTYPE1_AFTER=$("$VAST_PATH"util/listhead "wcs_$WORK_IMAGE" 2>/dev/null | awk -F"'" '/^CTYPE1 /{print $2; exit}' | awk '{print $1}')
 if [ "$CTYPE1_AFTER" = "RA---TAN-SIP" ];then
  record_check 0 "" "the refit solution is a TAN-SIP solution"
 else
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_NOT_TAN_SIP_${CTYPE1_AFTER}" "the refit solution is a TAN-SIP solution"
 fi

 # ... and it has to be good
 RESIDUAL_ARCSEC=$(wcs_quality_sigma_from_log "$RUN_LOG")
 if [ -n "$RESIDUAL_ARCSEC" ] && echo "$RESIDUAL_ARCSEC $MAX_RESIDUAL_ARCSEC" | awk '{if ($1+0 < $2+0) exit 0; exit 1}' ;then
  record_check 0 "" "the refit residual is below $MAX_RESIDUAL_ARCSEC arcsec (got $RESIDUAL_ARCSEC)"
 else
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_RESIDUAL_${RESIDUAL_ARCSEC:-none}" "the refit residual is below $MAX_RESIDUAL_ARCSEC arcsec (got ${RESIDUAL_ARCSEC:-none})"
 fi

 # even here the file we were handed stays untouched
 CHECKSUM_AFTER=$(file_checksum "$UNTRUSTED_IMAGE")
 if [ "$CHECKSUM_BEFORE" = "$CHECKSUM_AFTER" ];then
  record_check 0 "" "the unsolved input image is left byte-identical"
 else
  record_check 1 "SIPPOLICY_${CAMERA_TAG}_UNSOLVED_INPUT_MODIFIED" "the unsolved input image is left byte-identical"
 fi

 rm -rf sip_refit_policy_input
 clean_workspace

done

#################################
# util/solve_plate_with_best_sip_order.sh has to ask for a refit explicitly,
# otherwise it would compare orders that were never actually fitted.
echo ""
echo "=== the explicit-refit entry point ==="
grep -q 'VAST_FORCE_SIP_REFIT=1' "$VAST_PATH"util/solve_plate_with_best_sip_order.sh
record_check $? "SIPPOLICY_BESTSIPORDER_DOES_NOT_FORCE_REFIT" "util/solve_plate_with_best_sip_order.sh requests the refit explicitly"

#################################
# Summary
echo ""
echo "########################################################"
echo "SIP refit policy test: $((N_CHECKS_RUN - N_CHECKS_FAILED)) of $N_CHECKS_RUN checks passed"
if [ -n "$FAILED_TEST_CODES" ];then
 echo "Failed test codes: $FAILED_TEST_CODES"
 echo "########################################################"
 exit 1
fi
echo "ALL CHECKS PASSED"
echo "########################################################"
exit 0
