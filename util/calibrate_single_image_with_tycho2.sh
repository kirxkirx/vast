#!/usr/bin/env bash
#
# Per-image magnitude calibration against the LOCAL Tycho-2 catalog.
#
# Purpose:
#   Same role as util/calibrate_single_image.sh but uses Tycho-2 V magnitudes
#   via lib/catalogs/read_tycho2 instead of VizieR APASS/UCAC5.  Intended
#   for fields with PHOTOMETRIC_CALIBRATION=TYCHO2_V (typically NMW telephoto
#   lens data), where a VizieR round trip for each reference-image calibration
#   is both wrong (inconsistent with the lightcurve calibration catalogue) and
#   unnecessarily slow.
#
# Usage:
#   util/calibrate_single_image_with_tycho2.sh image.fits
#
# Inputs expected in CWD:
#   - wcs_<basename>.cat          SExtractor catalog of the plate-solved image
#                                 (produced by the transient-factory plate-solve
#                                 pass; if absent this script will try to
#                                 (re)produce it via util/wcs_image_calibration.sh)
#   - lib/catalogs/tycho2/tyc2.*  Local Tycho-2 catalog files
#
# Side effects (CWD):
#   - writes calib.txt            instrumental_mag  catalog_mag  error
#   - writes calib.txt_param      via lib/fit_zeropoint (5 whitespace-separated
#                                 floats: fit_function p3 p2 p1 p0)
#   - temporarily overwrites wcsmag.cat (input path read_tycho2 expects);
#     not restored -- any caller that relied on wcsmag.cat should re-produce
#     its own copy.
#
# Exit codes:
#   0 = success; calib.txt_param exists and is non-empty.
#   1 = any step failed (missing Tycho-2, missing image, missing .cat, too few
#       Tycho-2 matches, fit_zeropoint failure, etc.)
#
#################################
# Safe locale
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

function vastrealpath {
 REALPATH=$(readlink -f "$1" 2>/dev/null)
 if [ $? -ne 0 ];then
  REALPATH=$(greadlink -f "$1" 2>/dev/null)
  if [ $? -ne 0 ];then
   REALPATH=$(realpath "$1" 2>/dev/null)
   if [ $? -ne 0 ];then
    REALPATH=$(grealpath "$1" 2>/dev/null)
    if [ $? -ne 0 ];then
     OURPWD=$PWD
     cd "$(dirname "$1")" || return 1
     REALPATH="$PWD/$(basename "$1")"
     cd "$OURPWD" || return 1
    fi
   fi
  fi
 fi
 echo "$REALPATH"
}

if [ -z "$1" ];then
 echo "Usage: $0 image.fits" >&2
 echo "  Produces calib.txt and calib.txt_param in the current directory using" >&2
 echo "  the local Tycho-2 catalog (lib/catalogs/tycho2/)." >&2
 exit 1
fi
FITSFILE="$1"

if [ ! -s "$FITSFILE" ];then
 echo "ERROR in $0: input image $FITSFILE does not exist or is empty" >&2
 exit 1
fi

# Require local Tycho-2 to be present.  Caller (normally
# transient_factory_test31.sh after the lightcurve calibration already ran
# and downloaded Tycho-2 via util/transients/calibrate_current_field_with_tycho2.sh)
# must ensure this.
if [ ! -s lib/catalogs/tycho2/tyc2.dat.00 ] || [ ! -s lib/catalogs/tycho2/tyc2.dat.19 ];then
 echo "ERROR in $0: local Tycho-2 catalog not found or incomplete at lib/catalogs/tycho2/" >&2
 echo "       This helper is intended for PHOTOMETRIC_CALIBRATION=TYCHO2_V fields where" >&2
 echo "       the lightcurve calibration has already made the Tycho-2 catalog available." >&2
 exit 1
fi

# Resolve the WCS-solved counterpart basename.
BASENAME_FITSFILE=$(basename "$FITSFILE")
case "$BASENAME_FITSFILE" in
 wcs_*) WCS_IMAGE_NAME="$BASENAME_FITSFILE" ;;
 *)     WCS_IMAGE_NAME="wcs_$BASENAME_FITSFILE" ;;
esac
# Normalise: drop .fz, collapse wcs_wcs_
WCS_IMAGE_NAME="${WCS_IMAGE_NAME/wcs_wcs_/wcs_}"
WCS_IMAGE_NAME="${WCS_IMAGE_NAME/.fz/}"

# The WCS image itself must be on disk (in CWD or at the provided path).
# Prefer the CWD copy if present (pipeline normally plate-solves there).
if [ ! -s "$WCS_IMAGE_NAME" ];then
 if [ -s "$(dirname "$FITSFILE")/$WCS_IMAGE_NAME" ];then
  WCS_IMAGE_NAME="$(dirname "$FITSFILE")/$WCS_IMAGE_NAME"
 else
  echo "ERROR in $0: plate-solved image $WCS_IMAGE_NAME not found in CWD or at $(dirname "$FITSFILE")" >&2
  exit 1
 fi
fi

# The corresponding SExtractor catalog.  Look alongside the image first, then
# fall back to running wcs_image_calibration.sh to (re)produce it.
SEX_CATALOG="${WCS_IMAGE_NAME}.cat"
# If the image path is absolute, CAT might also be absolute; read_tycho2 expects
# wcsmag.cat in CWD so we always copy there regardless.
if [ ! -s "$SEX_CATALOG" ];then
 echo "$0: $SEX_CATALOG not found, running util/wcs_image_calibration.sh $WCS_IMAGE_NAME" >&2
 util/wcs_image_calibration.sh "$WCS_IMAGE_NAME" >/dev/null 2>&1
 if [ ! -s "$SEX_CATALOG" ];then
  echo "ERROR in $0: could not produce $SEX_CATALOG" >&2
  exit 1
 fi
fi

# Stage the catalog as wcsmag.cat (hardcoded filename expected by read_tycho2)
# and clear any previous calib outputs so we can detect read_tycho2/fit_zeropoint
# failures explicitly.
cp -f "$SEX_CATALOG" wcsmag.cat
if [ ! -s wcsmag.cat ];then
 echo "ERROR in $0: failed to stage wcsmag.cat from $SEX_CATALOG" >&2
 exit 1
fi
rm -f calib.txt calib.txt_param

lib/catalogs/read_tycho2
if [ $? -ne 0 ] || [ ! -s calib.txt ];then
 echo "ERROR in $0: lib/catalogs/read_tycho2 failed for $WCS_IMAGE_NAME" >&2
 exit 1
fi

lib/fit_zeropoint > /dev/null 2>&1
if [ $? -ne 0 ] || [ ! -s calib.txt_param ];then
 echo "ERROR in $0: lib/fit_zeropoint failed for $WCS_IMAGE_NAME" >&2
 exit 1
fi

echo "$0: calibrated $WCS_IMAGE_NAME via Tycho-2" >&2
exit 0
