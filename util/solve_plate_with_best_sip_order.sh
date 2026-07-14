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

# Candidate SIP orders to try, in preference order. The first one that ties on
# score wins, so list the conservative default (3) first.
SIP_ORDERS="3 2"

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
 echo "Solves each image at SIP orders ${SIP_ORDERS// /, } and keeps the one with the best (lowest) sigma*ratio astrometric residual score." >&2
 echo "The WCS is stripped from a private working copy before solving, so the original file is never modified." >&2
}

# Solve a single image at all candidate orders and keep the best result in the
# invocation directory. Never modifies the original input file.
function process_one_image {
 local image="$1"
 local base wcs_base abs_image workbase
 local order runlog sigma ratio score
 local best_order best_score
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
 best_score=""
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
  score=$(awk -v s="$sigma" -v r="$ratio" 'BEGIN { if ( s == "" || r == "" ) exit; printf "%.6f", (s+0)*(r+0) }')

  report="${report}  order ${order}: sigma=${sigma:-N/A} ratio=${ratio:-N/A} score=${score:-N/A}"$'\n'

  if [ -n "$score" ]; then
   # Stash this order's products, renamed from wcs_<workbase>* to the normal
   # wcs_<base>* names.
   mkdir -p "$master_workdir/order_${order}"
   for f in "$VAST_PATH"wcs_"$workbase"* ; do
    if [ -f "$f" ]; then
     suffix="${f##*wcs_"$workbase"}"
     cp -p "$f" "$master_workdir/order_${order}/${wcs_base}${suffix}"
    fi
   done
   # Keep order 3 on ties: best is set on the first valid order (3), and a
   # later order replaces it only if its score is strictly lower.
   if [ -z "$best_score" ] || awk -v n="$score" -v b="$best_score" 'BEGIN { exit !(n < b) }' ; then
    best_score="$score"
    best_order="$order"
   fi
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
  echo "RESULT $base: best SIP order = $best_order (score=$best_score)"
  printf "%s" "$report"
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
