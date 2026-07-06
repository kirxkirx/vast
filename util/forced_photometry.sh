#!/usr/bin/env bash

#
# Forced aperture photometry at a specified sky position on a single FITS image.
#
# Usage: util/forced_photometry.sh image.fits HH:MM:SS.ss +DD:MM:SS.s FILTER
#
# Runs both C and Python implementations for cross-validation.
# Set FORCED_PHOTOMETRY_ONLY_C=yes to run only the C implementation (the Python
# step is skipped); in that case the script also prints, on stdout before the
# '# C implementation:' block, two machine-readable lines for the caller:
#   # aperture_diameter_pix: <APERTURE>
#   # target_pixel: <x> <y>
# The default (variable unset) keeps the original both-implementations behaviour.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# A more portable realpath wrapper
function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=`readlink -f "$1" 2>/dev/null`
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=`greadlink -f "$1" 2>/dev/null`
   if [ $? -ne 0 ];then
    REALPATH=`realpath "$1" 2>/dev/null`
    if [ $? -ne 0 ];then
     REALPATH=`grealpath "$1" 2>/dev/null`
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")" || exit 1
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit 1
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

# Function to remove the last occurrence of a directory from a path
remove_last_occurrence() {
    echo "$1" | awk -F/ -v dir=$2 '{
        found = 0;
        for (i=NF; i>0; i--) {
            if ($i == dir && found == 0) {
                found = 1;
                continue;
            }
            res = (i==NF ? $i : $i "/" res);
        }
        print res;
    }'
}

# Function to get full path to vast main directory from the script name
get_vast_path_ends_with_slash_from_this_script_name() {
 VAST_PATH=$(vastrealpath $0)
 VAST_PATH=$(dirname "$VAST_PATH")

 # Remove last occurrences of util, lib, examples
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "util")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "lib")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "examples")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "transients")

 # Make sure no '//' are left in the path (they look ugly)
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")

 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")

 # Check that VAST_PATH ends with '/'
 LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
 if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
  VAST_PATH="$VAST_PATH/"
 fi

 echo "$VAST_PATH"
}


if [ -z "$VAST_PATH" ];then
 VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi

#################################
# Airmass-aware zero-point (see .claude/airmass_zeropoint_forced_photometry_design.md):
# when enabled, the constant zero-point calibration is supplemented by a per-image
# linear-in-airmass term fitted from the calibration stars; the term is applied to
# the output magnitudes. The fit is gated (star count, airmass span, slope quality),
# and any rejected fit falls back to the constant zero-point - identical to the
# behaviour with the feature disabled.
#################################
: "${FORCED_PHOTOMETRY_AIRMASS_ZEROPOINT:=no}"
: "${FORCED_PHOTOMETRY_AIRMASS_ZEROPOINT_PLOT:=no}"

#################################
# Parse command-line arguments
#################################
LIST_MODE=0
TARGET_RA=""
TARGET_DEC=""
SKY_LISTFILE=""

if [ -z "$4" ];then
 echo "Usage:" >&2
 echo "  $0 image.fits HH:MM:SS.ss +DD:MM:SS.s FILTER" >&2
 echo "  $0 image.fits --list sky_listfile FILTER" >&2
 echo "  FILTER is one of: B V R Rc I Ic r i g" >&2
 echo "  sky_listfile: one position per line 'RA Dec [label]' (sexagesimal or decimal deg)" >&2
 exit 1
fi

FITSFILE="$1"
if [ "$2" = "--list" ];then
 LIST_MODE=1
 SKY_LISTFILE="$3"
 FILTER="$4"
 if [ ! -f "$SKY_LISTFILE" ];then
  echo "ERROR: list file $SKY_LISTFILE does not exist" >&2
  exit 1
 fi
 if [ ! -s "$SKY_LISTFILE" ];then
  echo "ERROR: list file $SKY_LISTFILE is empty" >&2
  exit 1
 fi
else
 TARGET_RA="$2"
 TARGET_DEC="$3"
 FILTER="$4"
fi

#################################
# Validate VaST tools exist
#################################
for TOOL in "${VAST_PATH}lib/bin/sky2xy" \
            "${VAST_PATH}lib/fit_zeropoint" \
            "${VAST_PATH}util/calibrate_single_image.sh" \
            "${VAST_PATH}util/get_image_date" \
            "${VAST_PATH}lib/sextract_single_image_noninteractive" \
            "${VAST_PATH}util/forced_photometry" \
            "${VAST_PATH}util/forced_photometry.py" ; do
 if [ ! -f "$TOOL" ] && [ ! -L "$TOOL" ];then
  echo "ERROR: required VaST tool not found: $TOOL" >&2
  echo "Please compile VaST first with 'make'" >&2
  exit 1
 fi
done

#################################
# Validate input image
#################################
if [ -z "$FITSFILE" ];then
 echo "ERROR: FITSFILE variable is not set" >&2
 exit 1
fi
if [ ! -f "$FITSFILE" ];then
 echo "ERROR: cannot find the image file $FITSFILE" >&2
 exit 1
fi
if [ ! -s "$FITSFILE" ];then
 echo "ERROR: the input image file $FITSFILE is empty" >&2
 exit 1
fi

#################################
# Validate filter name
#################################
case "$FILTER" in
 B|V|R|Rc|I|Ic|r|i|g)
  ;;
 *)
  echo "ERROR: unrecognized filter '$FILTER'" >&2
  echo "  Supported filters: B V R Rc I Ic r i g" >&2
  exit 1
  ;;
esac

if [ $LIST_MODE -eq 1 ];then
 echo "Forced photometry (list mode): image=$FITSFILE list=$SKY_LISTFILE filter=$FILTER" >&2
else
 echo "Forced photometry: image=$FITSFILE RA=$TARGET_RA Dec=$TARGET_DEC filter=$FILTER" >&2
fi

#################################
# Step 1: Run SExtractor to get aperture
#################################
echo "Step 1: Running SExtractor..." >&2
APERTURE=$("$VAST_PATH"lib/sextract_single_image_noninteractive "$FITSFILE" 2>/dev/null)
if [ $? -ne 0 ];then
 echo "ERROR: sextract_single_image_noninteractive failed" >&2
 exit 1
fi
if [ -z "$APERTURE" ];then
 echo "ERROR: empty aperture from sextract_single_image_noninteractive" >&2
 exit 1
fi
echo "  Aperture diameter: $APERTURE pixels" >&2

#################################
# Step 2: Calibrate (internally runs solve_plate_with_UCAC5)
#################################
echo "Step 2: Calibrating..." >&2
"$VAST_PATH"util/calibrate_single_image.sh "$FITSFILE" "$FILTER"
if [ $? -ne 0 ];then
 echo "ERROR: calibrate_single_image.sh failed" >&2
 exit 1
fi
if [ ! -s "calib.txt" ];then
 echo "ERROR: calib.txt not found or empty after calibration" >&2
 exit 1
fi

#################################
# Step 3: Fit zeropoint
#################################
echo "Step 3: Fitting zeropoint..." >&2
"$VAST_PATH"lib/fit_zeropoint > /dev/null 2>&1
if [ $? -ne 0 ];then
 echo "ERROR: fit_zeropoint failed" >&2
 exit 1
fi
if [ ! -s "calib.txt_param" ];then
 echo "ERROR: calib.txt_param not found or empty" >&2
 exit 1
fi

#################################
# Step 3a: Airmass-aware zero-point fit (optional)
#################################
AIRMASS_ZP_STATUS="off"
AIRMASS_ZP_D0=0
AIRMASS_ZP_B=0
AIRMASS_ZP_XMIN=0
AIRMASS_ZP_XMAX=0
AIRMASS_ZP_IMAGE="$FITSFILE"
AIRMASS_ZP_SITE_ARGS=()
if [ "$FORCED_PHOTOMETRY_AIRMASS_ZEROPOINT" = "yes" ];then
 echo "Step 3a: Fitting the airmass-aware zero-point..." >&2
 # The SExtractor catalog of this image produced by the calibration step
 AIRMASS_ZP_WCSNAME="wcs_$(basename "$FITSFILE")"
 AIRMASS_ZP_WCSNAME="${AIRMASS_ZP_WCSNAME/wcs_wcs_/wcs_}"
 AIRMASS_ZP_WCSNAME="${AIRMASS_ZP_WCSNAME/.fz/}"
 AIRMASS_ZP_CATALOG="${AIRMASS_ZP_WCSNAME}.wcscat"
 # The image whose WCS and time drive the airmass computation: prefer the solved copy
 if [ -s "$AIRMASS_ZP_WCSNAME" ];then
  AIRMASS_ZP_IMAGE="$AIRMASS_ZP_WCSNAME"
 fi
 # Site coordinates: never trust the header of NMW Stas/STL frames (SITELAT/SITELONG
 # have been seen swapped there); explicit env AIRMASS_ZP_SITELAT/SITELONG win over everything
 if [ -n "$AIRMASS_ZP_SITELAT" ] && [ -n "$AIRMASS_ZP_SITELONG" ];then
  AIRMASS_ZP_SITE_ARGS=(--sitelat "$AIRMASS_ZP_SITELAT" --sitelong "$AIRMASS_ZP_SITELONG")
 else
  if "$VAST_PATH"util/listhead "$FITSFILE" 2>/dev/null | grep '^INSTRUME' | grep -q -e 'ST-8300' -e 'STL-11000' ;then
   AIRMASS_ZP_SITE_ARGS=(--sitelat '43 38 58' --sitelong '41 25 34')
   echo "  NMW camera detected - using the known site coordinates instead of the header ones" >&2
  fi
 fi
 AIRMASS_ZP_LINE=$("$VAST_PATH"util/pixel_flux_airmass_correction --fit-airmass-zeropoint "${AIRMASS_ZP_SITE_ARGS[@]}" --fit-table airmass_zeropoint_fit_table.txt calib.txt "$AIRMASS_ZP_CATALOG" "$AIRMASS_ZP_IMAGE" 2>/dev/null)
 if [ $? -ne 0 ] || [ -z "$AIRMASS_ZP_LINE" ];then
  AIRMASS_ZP_LINE="REJECT_FIT_FAILED 0 0 0 0 0 0 0 0 0"
 fi
 echo "$AIRMASS_ZP_LINE" > calib.txt_param_airmass
 AIRMASS_ZP_STATUS=$(echo "$AIRMASS_ZP_LINE" | awk '{print $1}')
 AIRMASS_ZP_D0=$(echo "$AIRMASS_ZP_LINE" | awk '{print $2}')
 AIRMASS_ZP_B=$(echo "$AIRMASS_ZP_LINE" | awk '{print $3}')
 AIRMASS_ZP_XMIN=$(echo "$AIRMASS_ZP_LINE" | awk '{print $9}')
 AIRMASS_ZP_XMAX=$(echo "$AIRMASS_ZP_LINE" | awk '{print $10}')
 if [ "$AIRMASS_ZP_STATUS" = "OK" ];then
  echo "  airmass zero-point: OK  k=$(echo "$AIRMASS_ZP_LINE" | awk '{print $5}') mag/airmass  N=$(echo "$AIRMASS_ZP_LINE" | awk '{print $6}')  span=$(echo "$AIRMASS_ZP_LINE" | awk '{print $7}')" >&2
 else
  echo "  airmass zero-point: $AIRMASS_ZP_STATUS - constant zero-point used" >&2
 fi
 # Optional diagnostic plot (matplotlib-gated; failure to plot is never an error)
 if [ "$FORCED_PHOTOMETRY_AIRMASS_ZEROPOINT_PLOT" = "yes" ] && [ -f "$VAST_PATH"lib/plot_airmass_zeropoint.py ];then
  AIRMASS_ZP_PYBIN=""
  if command -v python3 >/dev/null 2>&1 ;then
   AIRMASS_ZP_PYBIN="python3"
  elif command -v python >/dev/null 2>&1 ;then
   AIRMASS_ZP_PYBIN="python"
  fi
  if [ -n "$AIRMASS_ZP_PYBIN" ];then
   "$AIRMASS_ZP_PYBIN" "$VAST_PATH"lib/plot_airmass_zeropoint.py airmass_zeropoint_fit_table.txt calib.txt_param_airmass "airmass_zeropoint_$(basename "$FITSFILE").png" "$(basename "$FITSFILE")" >&2 || true
  fi
 fi
fi

#################################
# Step 4: Convert RA/Dec to pixel coordinates
#################################
echo "Step 4: Converting RA/Dec to pixel coordinates..." >&2

# Temporary files used in list mode (also cleaned in single mode; trap is harmless).
FORCEDPHOT_PIXLIST=$(mktemp 2>/dev/null || echo "forcedphot_pixlist_$$.tmp")
FORCEDPHOT_SKYMAP=$(mktemp 2>/dev/null || echo "forcedphot_skymap_$$.tmp")
FORCEDPHOT_C_TMP=$(mktemp 2>/dev/null || echo "forcedphot_ctmp_$$.tmp")
FORCEDPHOT_PY_TMP=$(mktemp 2>/dev/null || echo "forcedphot_pytmp_$$.tmp")
# shellcheck disable=SC2064
trap "rm -f '$FORCEDPHOT_PIXLIST' '$FORCEDPHOT_SKYMAP' '$FORCEDPHOT_C_TMP' '$FORCEDPHOT_PY_TMP'" EXIT

if [ $LIST_MODE -eq 0 ];then
 SKY2XY_OUTPUT=$("$VAST_PATH"lib/bin/sky2xy "$FITSFILE" $TARGET_RA $TARGET_DEC 2>&1)
 if [ $? -ne 0 ];then
  echo "ERROR: sky2xy failed" >&2
  echo "  Output: $SKY2XY_OUTPUT" >&2
  exit 1
 fi
 if echo "$SKY2XY_OUTPUT" | grep -q -e "off image" -e "offscale" ;then
  echo "ERROR: target coordinates are off the image" >&2
  echo "  sky2xy output: $SKY2XY_OUTPUT" >&2
  exit 1
 fi
 PIXEL_X=$(echo "$SKY2XY_OUTPUT" | awk '{print $5}')
 PIXEL_Y=$(echo "$SKY2XY_OUTPUT" | awk '{print $6}')
 if [ -z "$PIXEL_X" ] || [ -z "$PIXEL_Y" ];then
  echo "ERROR: could not parse pixel coordinates from sky2xy output" >&2
  echo "  sky2xy output: $SKY2XY_OUTPUT" >&2
  exit 1
 fi
 echo "  Pixel position: $PIXEL_X $PIXEL_Y" >&2
else
 # List mode: read sky_listfile line by line, call sky2xy once per position,
 # build a pixel list for forced_photometry --list and a sky map for final join.
 : > "$FORCEDPHOT_PIXLIST"
 : > "$FORCEDPHOT_SKYMAP"
 FORCEDPHOT_LINE_IDX=0
 FORCEDPHOT_N_VALID=0
 while IFS= read -r FORCEDPHOT_LINE || [ -n "$FORCEDPHOT_LINE" ]; do
  FORCEDPHOT_LINE_IDX=$((FORCEDPHOT_LINE_IDX + 1))
  FORCEDPHOT_STRIPPED=$(echo "$FORCEDPHOT_LINE" | sed 's/^[[:space:]]*//')
  case "$FORCEDPHOT_STRIPPED" in
   ''|'#'*|'%'*) continue ;;
  esac
  FORCEDPHOT_RA=$(echo "$FORCEDPHOT_STRIPPED" | awk '{print $1}')
  FORCEDPHOT_DEC=$(echo "$FORCEDPHOT_STRIPPED" | awk '{print $2}')
  FORCEDPHOT_LABEL=$(echo "$FORCEDPHOT_STRIPPED" | awk -v idx="$FORCEDPHOT_LINE_IDX" '{if (NF >= 3) print $3; else print idx}')
  if [ -z "$FORCEDPHOT_RA" ] || [ -z "$FORCEDPHOT_DEC" ];then
   echo "WARNING: list line $FORCEDPHOT_LINE_IDX: cannot parse RA Dec: $FORCEDPHOT_LINE" >&2
   continue
  fi
  FORCEDPHOT_S2X=$("$VAST_PATH"lib/bin/sky2xy "$FITSFILE" "$FORCEDPHOT_RA" "$FORCEDPHOT_DEC" 2>&1)
  if [ $? -ne 0 ];then
   echo "WARNING: list line $FORCEDPHOT_LINE_IDX: sky2xy failed for $FORCEDPHOT_RA $FORCEDPHOT_DEC" >&2
   continue
  fi
  if echo "$FORCEDPHOT_S2X" | grep -q -e "off image" -e "offscale" ;then
   echo "WARNING: list line $FORCEDPHOT_LINE_IDX: $FORCEDPHOT_RA $FORCEDPHOT_DEC is off the image" >&2
   continue
  fi
  FORCEDPHOT_PX=$(echo "$FORCEDPHOT_S2X" | awk '{print $5}')
  FORCEDPHOT_PY=$(echo "$FORCEDPHOT_S2X" | awk '{print $6}')
  if [ -z "$FORCEDPHOT_PX" ] || [ -z "$FORCEDPHOT_PY" ];then
   echo "WARNING: list line $FORCEDPHOT_LINE_IDX: could not parse pixel coords" >&2
   continue
  fi
  echo "$FORCEDPHOT_PX $FORCEDPHOT_PY $FORCEDPHOT_LABEL" >> "$FORCEDPHOT_PIXLIST"
  echo "$FORCEDPHOT_LABEL $FORCEDPHOT_RA $FORCEDPHOT_DEC $FORCEDPHOT_PX $FORCEDPHOT_PY" >> "$FORCEDPHOT_SKYMAP"
  FORCEDPHOT_N_VALID=$((FORCEDPHOT_N_VALID + 1))
 done < "$SKY_LISTFILE"
 if [ "$FORCEDPHOT_N_VALID" -eq 0 ];then
  echo "ERROR: no valid positions in list file $SKY_LISTFILE" >&2
  exit 1
 fi
 echo "  Converted $FORCEDPHOT_N_VALID positions to pixel coordinates" >&2
fi

#################################
# Step 5: Extract JD
#################################
echo "Step 5: Extracting observation date..." >&2
JD=$("$VAST_PATH"util/get_image_date "$FITSFILE" 2>&1 | grep '  JD ' | awk '{print $2}' | head -n1)
if [ -z "$JD" ];then
 echo "WARNING: could not extract JD from image, using 0.0" >&2
 JD="0.0"
fi
echo "  JD: $JD" >&2

#################################
# Step 6: Run C implementation
#################################
echo "Step 6: Running C forced photometry..." >&2
C_START=$(date +%s%N)
if [ $LIST_MODE -eq 0 ];then
 C_RESULT=$("$VAST_PATH"util/forced_photometry "$FITSFILE" $PIXEL_X $PIXEL_Y $APERTURE 2>/dev/null)
 C_EXIT=$?
else
 "$VAST_PATH"util/forced_photometry "$FITSFILE" --list "$FORCEDPHOT_PIXLIST" $APERTURE > "$FORCEDPHOT_C_TMP" 2>/dev/null
 C_EXIT=$?
fi
C_END=$(date +%s%N)
C_TIME=$(echo "$C_START $C_END" | awk '{printf "%.3f", ($2-$1)/1000000000.0}')
echo "  C execution time: ${C_TIME}s" >&2
if [ $C_EXIT -ne 0 ];then
 echo "WARNING: C forced photometry exited with code $C_EXIT" >&2
 if [ $LIST_MODE -eq 0 ];then
  C_RESULT="99.0000 99.0000 fail"
 fi
fi
if [ $LIST_MODE -eq 0 ] && [ -z "$C_RESULT" ];then
 echo "WARNING: empty result from C forced photometry" >&2
 C_RESULT="99.0000 99.0000 fail"
fi

#################################
# Step 6a: Apply the airmass-aware zero-point term (optional)
#################################
if [ "$AIRMASS_ZP_STATUS" = "OK" ];then
 if [ $LIST_MODE -eq 0 ];then
  FORCEDPHOT_AMXY=$(mktemp 2>/dev/null || echo "forcedphot_amxy_$$.tmp")
  printf '%s %s\n' "$PIXEL_X" "$PIXEL_Y" > "$FORCEDPHOT_AMXY"
  AIRMASS_ZP_XT=$("$VAST_PATH"util/pixel_flux_airmass_correction -k 1 --predict-list "$FORCEDPHOT_AMXY" "${AIRMASS_ZP_SITE_ARGS[@]}" "$AIRMASS_ZP_IMAGE" 2>/dev/null | awk 'f {print $4} /^# X_pix/ {f=1}')
  rm -f "$FORCEDPHOT_AMXY"
  if [ -n "$AIRMASS_ZP_XT" ];then
   C_RESULT=$(echo "$C_RESULT" | awk -v xt="$AIRMASS_ZP_XT" -v d0="$AIRMASS_ZP_D0" -v b="$AIRMASS_ZP_B" -v xmin="$AIRMASS_ZP_XMIN" -v xmax="$AIRMASS_ZP_XMAX" '{x=xt+0; if (x<xmin) x=xmin; if (x>xmax) x=xmax; if ($1+0 < 90.0) {printf "%.4f %s %s\n", $1+d0+b*x, $2, $3} else {print $0} }')
   echo "  airmass zero-point term applied at airmass $AIRMASS_ZP_XT" >&2
  else
   echo "WARNING: could not evaluate the target airmass - airmass zero-point term NOT applied" >&2
  fi
 else
  FORCEDPHOT_AMTMP=$(mktemp 2>/dev/null || echo "forcedphot_amtmp_$$.tmp")
  "$VAST_PATH"util/pixel_flux_airmass_correction -k 1 --predict-list "$FORCEDPHOT_PIXLIST" "${AIRMASS_ZP_SITE_ARGS[@]}" "$AIRMASS_ZP_IMAGE" 2>/dev/null | awk 'f {print $4} /^# X_pix/ {f=1}' > "$FORCEDPHOT_AMTMP"
  if [ -s "$FORCEDPHOT_AMTMP" ] && [ "$(wc -l < "$FORCEDPHOT_AMTMP")" -eq "$(wc -l < "$FORCEDPHOT_C_TMP")" ];then
   FORCEDPHOT_AMADJ=$(mktemp 2>/dev/null || echo "forcedphot_amadj_$$.tmp")
   paste -d' ' "$FORCEDPHOT_C_TMP" "$FORCEDPHOT_AMTMP" | \
    awk -v d0="$AIRMASS_ZP_D0" -v b="$AIRMASS_ZP_B" -v xmin="$AIRMASS_ZP_XMIN" -v xmax="$AIRMASS_ZP_XMAX" \
        '{x=$NF+0; if (x<xmin) x=xmin; if (x>xmax) x=xmax; if ($4+0 < 90.0) {$4=sprintf("%.4f", $4+d0+b*x)}; NF=NF-1; print}' > "$FORCEDPHOT_AMADJ"
   mv "$FORCEDPHOT_AMADJ" "$FORCEDPHOT_C_TMP"
   echo "  airmass zero-point term applied to the position list" >&2
  else
   echo "WARNING: airmass prediction count mismatch - airmass zero-point term NOT applied" >&2
  fi
  rm -f "$FORCEDPHOT_AMTMP"
 fi
fi

#################################
# Step 7: Run Python implementation
# (skipped when FORCED_PHOTOMETRY_ONLY_C=yes)
#################################
if [ "$FORCED_PHOTOMETRY_ONLY_C" != "yes" ];then
 echo "Step 7: Running Python forced photometry..." >&2
 PY_START=$(date +%s%N)
 if [ $LIST_MODE -eq 0 ];then
  PY_RESULT=$("$VAST_PATH"util/forced_photometry.py "$FITSFILE" $PIXEL_X $PIXEL_Y $APERTURE 2>/dev/null)
  PY_EXIT=$?
 else
  "$VAST_PATH"util/forced_photometry.py "$FITSFILE" --list "$FORCEDPHOT_PIXLIST" $APERTURE > "$FORCEDPHOT_PY_TMP" 2>/dev/null
  PY_EXIT=$?
 fi
 PY_END=$(date +%s%N)
 PY_TIME=$(echo "$PY_START $PY_END" | awk '{printf "%.3f", ($2-$1)/1000000000.0}')
 echo "  Python execution time: ${PY_TIME}s" >&2
 if [ $PY_EXIT -ne 0 ];then
  echo "WARNING: Python forced photometry exited with code $PY_EXIT" >&2
  if [ $LIST_MODE -eq 0 ];then
   PY_RESULT="99.0000 99.0000 fail"
  fi
 fi
 if [ $LIST_MODE -eq 0 ] && [ -z "$PY_RESULT" ];then
  echo "WARNING: empty result from Python forced photometry" >&2
  PY_RESULT="99.0000 99.0000 fail"
 fi
fi

#################################
# Output results
#################################
BASENAME_FITSFILE=$(basename "$FITSFILE")

if [ $LIST_MODE -eq 0 ];then
 # When only the C implementation was requested, emit machine-readable lines
 # (aperture diameter and target pixel position) that the caller may need.
 if [ "$FORCED_PHOTOMETRY_ONLY_C" = "yes" ];then
  echo "# aperture_diameter_pix: $APERTURE"
  echo "# target_pixel: $PIXEL_X $PIXEL_Y"
 fi
 echo "# C implementation:"
 echo "$JD  $C_RESULT  $BASENAME_FITSFILE"
 if [ "$FORCED_PHOTOMETRY_ONLY_C" != "yes" ];then
  echo "# Python implementation:"
  echo "$JD  $PY_RESULT  $BASENAME_FITSFILE"
 fi
else
 # Join tool output (label cx cy mag err st) with sky map (label RA Dec px py)
 # to produce: JD label RA Dec px py mag err st basename.
 # The two files are in matching order by construction.
 echo "# C implementation:"
 paste -d' ' "$FORCEDPHOT_SKYMAP" "$FORCEDPHOT_C_TMP" | \
  awk -v jd="$JD" -v fn="$BASENAME_FITSFILE" \
      'NF >= 10 {printf "%s  %s  %s  %s  %s  %s  %s  %s  %s  %s\n", jd, $1, $2, $3, $4, $5, $9, $10, $11, fn}'
 if [ "$FORCED_PHOTOMETRY_ONLY_C" != "yes" ];then
  echo "# Python implementation:"
  paste -d' ' "$FORCEDPHOT_SKYMAP" "$FORCEDPHOT_PY_TMP" | \
   awk -v jd="$JD" -v fn="$BASENAME_FITSFILE" \
       'NF >= 10 {printf "%s  %s  %s  %s  %s  %s  %s  %s  %s  %s\n", jd, $1, $2, $3, $4, $5, $9, $10, $11, fn}'
 fi
fi
