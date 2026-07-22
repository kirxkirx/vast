#!/usr/bin/env bash
#
# Plate-solve a FITS image choosing the SIP polynomial order that gives the
# best astrometric residuals.
#
# Background
# ----------
# util/solve_plate_with_UCAC5 plate-solves an image and matches the detected
# stars to UCAC5, printing a single "WCS_QUALITY_DIAG:" line with the
# pre-local-correction residual sigma (robust, MAD-based) and the
# worst-quadrant-to-overall sigma ratio (a spatial-inhomogeneity proxy). The
# SIP polynomial order that solve-field fits is controlled by the
# VAST_TWEAK_ORDER environment variable (default 3, see util/identify.sh).
#
# Order 3 is fine for fields with real optical distortion but over-fits on
# fields whose optics has very little distortion (e.g. wide-field lenses),
# where dropping to order 2 collapses the spurious SIP terms and recovers a
# uniform residual coverage. The transient pipeline
# (util/transients/transient_factory_test31.sh) handles this by comparing each
# new image to two reference images and retrying with order 2. Outside that
# context there is no reference baseline, so this tool instead solves the image
# at each candidate order and keeps whichever minimizes the sigma*ratio score.
#
# Forcing a real re-solve
# -----------------------
# An image that already carries an Astrometry.net WCS is "blindly trusted" by
# wcs_image_calibration.sh: it copies the embedded WCS and never re-runs
# solve-field, so VAST_TWEAK_ORDER would have no effect. To actually choose the
# SIP order we strip the WCS (and the Astrometry.net provenance markers, which
# lib/astrometry/strip_wcs_keywords now also removes) from a private working
# COPY of each image -- the original is never modified -- so solve-field runs
# and honors --tweak-order.
#
# Working directory
# -----------------
# wcs_image_calibration.sh cd's into the VaST root and writes the wcs_* products
# there, and solve_plate_with_UCAC5 reads them back from its own cwd; the two
# only agree when the solver runs from the VaST root. We therefore run the
# solves from VAST_PATH, using a unique working basename so the products never
# collide with (or clobber) a real wcs_<image> kept in the VaST directory, then
# copy the winning order's products -- renamed to the normal wcs_<image> names
# -- into the directory the tool was invoked from.
#
# Usage
# -----
#   util/solve_plate_with_best_sip_order.sh image1.fits [image2.fits ...] \
#        [--fov APPROXIMATE_FIELD_OF_VIEW_ARCMIN] [--iterations N]
#
# Outputs (per image, written to the invocation directory, keyed by image
# basename, exactly as util/solve_plate_with_UCAC5 writes them):
#   wcs_<basename>                         plate-solved image, winning WCS
#   wcs_<basename>.wcscat                   matched image catalog
#   wcs_<basename>.wcscat.ucac5             UCAC5-matched catalog
#   wcs_<basename>.wcscat.ds9.reg           DS9 region of matched stars
#   wcs_<basename>.wcscat.astrometric_residuals  residual vector field
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Candidate SIP orders to try. The solution minimizing the WORST-quadrant
# astrometric residual sigma wins (we want a solution that is good across the
# whole frame, not one that fits three quadrants well and fails in the fourth);
# on a tie (within SIP_ORDER_SELECTION_TIE_ARCSEC) the lower overall sigma wins.
SIP_ORDERS="4 3 2"
SIP_ORDER_SELECTION_TIE_ARCSEC=0.01
# Validity gate: a candidate whose astrometric-match count collapses relative
# to the best candidate is disqualified before the residual comparison. A
# globally-warped solution can match only a small self-consistent subset of
# stars and then show deceptively uniform per-quadrant residuals on that
# subset (test case: Cas-05 order-4, uniform 2.4 arcsec quadrants built on a
# collapsed match set while healthy orders match twice as many stars).
SIP_ORDER_SELECTION_MIN_NMATCH_FRACTION=0.5
# The WCS_QUALITY_DIAG N_match alone is NOT sufficient for the gate: its
# generous match radius plus outlier exclusion makes a globally-warped
# solution look as star-rich as a healthy one (Cas-05 order-4: N_match=899,
# the largest of all candidates, yet only 311 tight-radius Tycho-2 matches
# against thousands for the healthy orders). So when the local Tycho-2 copy
# is available, the tight-radius Tycho-2 match count of each candidate is
# measured with lib/catalogs/read_tycho2 and the same 0.5-of-best floor is
# applied to it. Candidates ranked by worst-quadrant sigma among survivors.
SIP_ORDER_SELECTION_MIN_TYCHO_FRACTION=0.5

# A more portable realpath wrapper (same idiom as util/identify.sh)
function vastrealpath {
  REALPATH=$(readlink -f "$1" 2>/dev/null)
  if [ $? -ne 0 ];then
   REALPATH=$(greadlink -f "$1" 2>/dev/null)
   if [ $? -ne 0 ];then
    REALPATH=$(realpath "$1" 2>/dev/null)
    if [ $? -ne 0 ];then
     REALPATH=$(grealpath "$1" 2>/dev/null)
     if [ $? -ne 0 ];then
      OURPWD="$PWD"
      cd "$(dirname "$1")" || exit 1
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit 1
     fi
    fi
   fi
  fi
  echo "$REALPATH"
}

# Determine the VaST root directory (with a trailing slash) from this script's
# location: the script lives in util/, so its parent directory is the root.
function get_vast_path {
 local script_path script_dir vast_dir
 script_path=$(vastrealpath "$0")
 script_dir=$(dirname "$script_path")
 vast_dir=$(dirname "$script_dir")
 case "$vast_dir" in
  */) echo "$vast_dir" ;;
  *)  echo "$vast_dir/" ;;
 esac
}

# Extract one numeric field from the WCS_QUALITY_DIAG line for the given image
# basename in the supplied log file. Echoes the value, or empty if the field
# is absent or NaN. Mirrors extract_wcs_quality_field in transient_factory_test31.sh.
function extract_diag_field {
 # $1 = logfile, $2 = image basename, $3 = field name
 awk -v img="$2" -v fld="$3" '
  $0 ~ ("WCS_QUALITY_DIAG: file=" img " ") {
   for ( i= 1; i <= NF; i++ ) {
    if ( substr( $i, 1, length(fld) + 1 ) == ( fld "=" ) ) {
     last_val= substr( $i, length(fld) + 2 )
    }
   }
  }
  END { if ( last_val != "" && last_val != "NaN" ) print last_val }
 ' "$1"
}

function print_usage {
 echo "Usage: $0 image1.fits [image2.fits ...] [--fov ARCMIN] [--iterations N]" >&2
 echo "Solves each image at SIP orders ${SIP_ORDERS// /, } and keeps the one with the lowest worst-quadrant astrometric residual sigma (ties broken by the lowest overall sigma)." >&2
 echo "The WCS is stripped from a private working copy before solving, so the original file is never modified." >&2
}

# Solve a single image at all candidate orders and keep the best result in the
# invocation directory. Never modifies the original input file.
function process_one_image {
 local image="$1"
 local base wcs_base abs_image workbase
 local order runlog sigma ratio worstq q1 q2 q3 q4 nmatch
 local best_order best_worstq best_sigma
 local -a cand_order cand_worstq cand_sigma cand_nmatch cand_tycho
 local i max_nmatch nmatch_floor wcat tycho tycho_max tycho_floor
 local master_workdir stripped f suffix
 local report

 base=$(basename "$image")
 wcs_base="wcs_${base/.fz/}"
 wcs_base="${wcs_base/wcs_wcs_/wcs_}"

 # Resolve the input to a real file (the references may be symlinks) so we can
 # copy it into the working directory.
 abs_image=$(vastrealpath "$image")
 if [ ! -f "$abs_image" ]; then
  echo "ERROR: cannot resolve input image to a readable file: $image" >&2
  return 1
 fi

 master_workdir=$(mktemp -d "${INVOCATION_DIR}/sip_order_select_${base}.XXXXXX" 2>/dev/null || echo "${INVOCATION_DIR}/sip_order_select_${base}_$$")
 mkdir -p "$master_workdir"

 # Unique working basename. wcs_image_calibration.sh writes wcs_<workbase>*
 # into VAST_PATH; the tag keeps those from colliding with, or clobbering, a
 # real wcs_<image> the user may keep in the VaST directory.
 # Any 'wcs_' substring is removed from the working basename: the working
 # copy has its WCS deliberately stripped, and a 'wcs_' in the filename makes
 # util/solve_plate_with_UCAC5 take the exact-FOV-from-WCS shortcut, which
 # returns a zero field of view for the WCS-less copy and breaks the blind
 # solve (bites when re-solving already-solved archive images named wcs_*).
 workbase="vastsiptmp$$_${base//wcs_/}"
 stripped="$master_workdir/$workbase"
 if ! cp "$abs_image" "$stripped" ; then
  echo "ERROR: could not copy $abs_image to $stripped" >&2
  rm -rf "$master_workdir"
  return 1
 fi
 # Strip WCS + Astrometry.net provenance so the image is treated as unsolved and
 # actually re-solved (honoring VAST_TWEAK_ORDER) instead of blindly trusted.
 "$VAST_PATH"lib/astrometry/strip_wcs_keywords "$stripped" > "$master_workdir/strip.log" 2>&1

 best_order=""
 best_worstq=""
 best_sigma=""
 report=""

 for order in $SIP_ORDERS ; do
  # Clear any prior products for our working base from VAST_PATH so the solver
  # does not skip the image and so each order starts clean.
  rm -f "$VAST_PATH"wcs_"$workbase"*

  runlog="$master_workdir/solve_order_${order}.log"
  echo "Solving $base with VAST_TWEAK_ORDER=$order (WCS stripped, fresh solve) ..."
  # The solver must run with cwd=VAST_PATH: wcs_image_calibration.sh cd's there
  # and writes the wcs_* products, and the solver reads them back from its cwd.
  ( cd "$VAST_PATH" && VAST_TWEAK_ORDER="$order" "$VAST_PATH"util/solve_plate_with_UCAC5 --no_photometric_catalog "${PASSTHROUGH[@]}" "$stripped" ) > "$runlog" 2>&1
  # Do not abort on a non-zero exit: a failed order simply yields no score.

  sigma=$(extract_diag_field "$runlog" "$workbase" "sigma_overall_arcsec")
  ratio=$(extract_diag_field "$runlog" "$workbase" "worst_quadrant_to_overall_ratio")
  q1=$(extract_diag_field "$runlog" "$workbase" "sigma_q1_arcsec")
  q2=$(extract_diag_field "$runlog" "$workbase" "sigma_q2_arcsec")
  q3=$(extract_diag_field "$runlog" "$workbase" "sigma_q3_arcsec")
  q4=$(extract_diag_field "$runlog" "$workbase" "sigma_q4_arcsec")
  # The selection criterion: the worst (largest) per-quadrant residual sigma.
  # We want a solution that is good across the WHOLE frame, so a fit that is
  # excellent in three quadrants but fails in the fourth must lose to a fit
  # that is uniformly acceptable everywhere.
  worstq=$(awk -v a="$q1" -v b="$q2" -v c="$q3" -v d="$q4" 'BEGIN { if ( a == "" || b == "" || c == "" || d == "" ) exit; w=a+0; if ( b+0 > w ) w=b+0; if ( c+0 > w ) w=c+0; if ( d+0 > w ) w=d+0; printf "%.6f", w }')
  nmatch=$(extract_diag_field "$runlog" "$workbase" "N_match")

  report="${report}  order ${order}: worst_quadrant_sigma=${worstq:-N/A} overall_sigma=${sigma:-N/A} quadrants=${q1:-N/A}/${q2:-N/A}/${q3:-N/A}/${q4:-N/A} N_match=${nmatch:-N/A} ratio=${ratio:-N/A}"$'\n'

  if [ -n "$worstq" ] && [ -n "$sigma" ] && [ -n "$nmatch" ]; then
   # Stash this order's products, renamed from wcs_<workbase>* to the normal
   # wcs_<base>* names.
   mkdir -p "$master_workdir/order_${order}"
   for f in "$VAST_PATH"wcs_"$workbase"* ; do
    if [ -f "$f" ]; then
     suffix="${f##*wcs_"$workbase"}"
     cp -p "$f" "$master_workdir/order_${order}/${wcs_base}${suffix}"
    fi
   done
   cand_order+=("$order")
   cand_worstq+=("$worstq")
   cand_sigma+=("$sigma")
   cand_nmatch+=("$nmatch")
  fi
 done

 # Measure each candidate's tight-radius Tycho-2 match count (the ground-truth
 # validity signal; see the SIP_ORDER_SELECTION_MIN_TYCHO_FRACTION comment).
 # Empty when the local Tycho-2 copy or the candidate catalog is unavailable.
 for i in "${!cand_order[@]}" ; do
  tycho=""
  wcat="$master_workdir/order_${cand_order[$i]}/${wcs_base}.wcscat"
  if [ -s "$wcat" ] && [ -x "$VAST_PATH"lib/catalogs/read_tycho2 ] && [ -d "$VAST_PATH"lib/catalogs/tycho2 ]; then
   cp "$wcat" "$VAST_PATH"wcsmag.cat
   tycho=$( cd "$VAST_PATH" && lib/catalogs/read_tycho2 2>&1 | awk '/Matched with Tycho-2 /{print $4}' | tail -n 1 )
   rm -f "$VAST_PATH"wcsmag.cat
  fi
  cand_tycho+=("$tycho")
  report="${report}  order ${cand_order[$i]}: tight-radius Tycho-2 matches: ${tycho:-N/A}"$'\n'
 done

 # Candidate selection. A candidate whose match count collapsed below
 # SIP_ORDER_SELECTION_MIN_NMATCH_FRACTION of the best candidate's count is
 # disqualified (deceptively uniform residuals on a tiny matched subset),
 # and likewise for the tight-radius Tycho-2 count when measured.
 # Among the survivors: lowest worst-quadrant sigma wins; when two tie within
 # SIP_ORDER_SELECTION_TIE_ARCSEC, the lower overall sigma wins.
 tycho_max=0
 for i in "${!cand_order[@]}" ; do
  if [ -n "${cand_tycho[$i]}" ] && awk -v n="${cand_tycho[$i]}" -v m="$tycho_max" 'BEGIN { exit !( n+0 > m+0 ) }' ; then
   tycho_max="${cand_tycho[$i]}"
  fi
 done
 tycho_floor=$(awk -v m="$tycho_max" -v f="$SIP_ORDER_SELECTION_MIN_TYCHO_FRACTION" 'BEGIN { printf "%.1f", (m+0)*(f+0) }')
 max_nmatch=0
 for i in "${!cand_order[@]}" ; do
  if awk -v n="${cand_nmatch[$i]}" -v m="$max_nmatch" 'BEGIN { exit !( n+0 > m+0 ) }' ; then
   max_nmatch="${cand_nmatch[$i]}"
  fi
 done
 nmatch_floor=$(awk -v m="$max_nmatch" -v f="$SIP_ORDER_SELECTION_MIN_NMATCH_FRACTION" 'BEGIN { printf "%.1f", (m+0)*(f+0) }')
 for i in "${!cand_order[@]}" ; do
  if awk -v n="${cand_nmatch[$i]}" -v fl="$nmatch_floor" 'BEGIN { exit !( n+0 < fl+0 ) }' ; then
   report="${report}  order ${cand_order[$i]}: DISQUALIFIED - N_match=${cand_nmatch[$i]} is below $nmatch_floor (${SIP_ORDER_SELECTION_MIN_NMATCH_FRACTION} of the best candidate's $max_nmatch)"$'\n'
   continue
  fi
  if [ -n "${cand_tycho[$i]}" ] && awk -v n="${cand_tycho[$i]}" -v fl="$tycho_floor" 'BEGIN { exit !( n+0 < fl+0 ) }' ; then
   report="${report}  order ${cand_order[$i]}: DISQUALIFIED - tight-radius Tycho-2 match count ${cand_tycho[$i]} is below $tycho_floor (${SIP_ORDER_SELECTION_MIN_TYCHO_FRACTION} of the best candidate's $tycho_max)"$'\n'
   continue
  fi
  if [ -z "$best_worstq" ] || awk -v w="${cand_worstq[$i]}" -v bw="$best_worstq" -v s="${cand_sigma[$i]}" -v bs="$best_sigma" -v t="$SIP_ORDER_SELECTION_TIE_ARCSEC" 'BEGIN { d= (w+0) - (bw+0); if ( d < -t ) exit 0; if ( d <= t && (s+0) < (bs+0) ) exit 0; exit 1 }' ; then
   best_worstq="${cand_worstq[$i]}"
   best_sigma="${cand_sigma[$i]}"
   best_order="${cand_order[$i]}"
  fi
 done

 # Remove our working products from VAST_PATH so the VaST directory is left clean.
 rm -f "$VAST_PATH"wcs_"$workbase"*

 if [ -n "$best_order" ]; then
  for f in "$master_workdir/order_${best_order}/"* ; do
   if [ -f "$f" ]; then
    cp -p "$f" "$INVOCATION_DIR/"
   fi
  done
  echo "RESULT $base: best SIP order = $best_order (worst_quadrant_sigma=$best_worstq overall_sigma=$best_sigma)"
  printf "%s" "$report"
  # Diagnostic aid: keep the per-order solve logs and the strip log when
  # requested (set VAST_KEEP_SIP_ORDER_SELECT_LOGS=1) - they are the only
  # record of WHY a particular order won or produced a poor solution.
  if [ "$VAST_KEEP_SIP_ORDER_SELECT_LOGS" = "1" ]; then
   mkdir -p "$INVOCATION_DIR/sip_order_select_logs_${base%.fits}"
   cp -p "$master_workdir"/*.log "$INVOCATION_DIR/sip_order_select_logs_${base%.fits}/" 2>/dev/null
  fi
  rm -rf "$master_workdir"
  return 0
 else
  echo "RESULT $base: FAILED -- no valid solution at any tried order ($SIP_ORDERS)" >&2
  printf "%s" "$report" >&2
  echo "Solve logs kept in $master_workdir for inspection." >&2
  return 1
 fi
}

##### main #####

VAST_PATH=$(get_vast_path)
INVOCATION_DIR="$PWD"

if [ ! -x "$VAST_PATH"util/solve_plate_with_UCAC5 ];then
 echo "ERROR: ${VAST_PATH}util/solve_plate_with_UCAC5 not found or not executable. Did you run 'make'?" >&2
 exit 1
fi
if [ ! -x "$VAST_PATH"lib/astrometry/strip_wcs_keywords ];then
 echo "ERROR: ${VAST_PATH}lib/astrometry/strip_wcs_keywords not found or not executable. Did you run 'make'?" >&2
 exit 1
fi

PASSTHROUGH=()
IMAGES=()
while [ $# -gt 0 ]; do
 case "$1" in
  --fov)
   if [ -z "$2" ];then
    echo "ERROR: --fov requires an argument" >&2
    exit 1
   fi
   PASSTHROUGH+=( --fov "$2" )
   shift 2
   ;;
  --iterations)
   if [ -z "$2" ];then
    echo "ERROR: --iterations requires an argument" >&2
    exit 1
   fi
   PASSTHROUGH+=( --iterations "$2" )
   shift 2
   ;;
  -h|--help)
   print_usage
   exit 0
   ;;
  -*)
   echo "ERROR: unknown option $1" >&2
   print_usage
   exit 1
   ;;
  *)
   IMAGES+=( "$1" )
   shift
   ;;
 esac
done

if [ "${#IMAGES[@]}" -eq 0 ]; then
 print_usage
 exit 1
fi

EXIT_STATUS=0
for IMG in "${IMAGES[@]}" ; do
 if [ ! -e "$IMG" ]; then
  echo "ERROR: input image not found: $IMG" >&2
  EXIT_STATUS=1
  continue
 fi
 if ! process_one_image "$IMG" ; then
  EXIT_STATUS=1
 fi
done

exit "$EXIT_STATUS"
