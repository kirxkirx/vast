#!/usr/bin/env bash

#
# Prototype: aperture photometry on a raw Bayer-mosaic frame from a Seestar S50
# (or a similar one-shot-color camera) with magnitude calibration against
# Gaia DR3 synthetic photometry.
#
# The Bayer mosaic is split into half-resolution R, G, B superpixel images
# (util/ccd/split_bayer), each channel image is plate-solved independently
# (util/wcs_image_calibration.sh), SExtractor measures every star through a
# ladder of aperture diameters, the field is cross-matched with the Gaia DR3
# synthetic photometry catalog (GSPC, VizieR I/360/syntphot - homogeneous
# from G ~ 4 to G ~ 17.65, so it covers the bright and the faint end with
# one catalog) and the following calibration relations are explored,
# matching the AAVSO tricolor (TB/TG/TR) convention of calibrating the Bayer
# channels against Johnson B, Johnson V and Cousins R comparison magnitudes:
#   - B  channel instrumental mags vs Gaia synthetic Johnson B
#   - G  channel instrumental mags vs Gaia synthetic Johnson V
#   - R  channel instrumental mags vs Gaia synthetic Cousins R
#     (see the note at BAND_DEFINITIONS below on why Sloan r' would actually
#     fit the red channel better when an IR-cut filter is present)
# For every aperture a zero-point-only fit (lib/fit_zeropoint: slope fixed to 1,
# median for n>=11) is performed; for the chosen fixed aperture, fits with a free
# slope (lib/fit_robust_linear and weighted lib/fit_linear) are compared with the
# zero-point-only fit. Calibration quality per aperture is reported as a pair:
# the DETRENDED robust scatter (star-to-star precision about a running-median
# residual-vs-magnitude trend - the quantity the aperture actually controls)
# and the trend amplitude (the magnitude-dependent calibration bias, kept
# separate because it is a smooth correctable function). The fixed aperture is
# chosen by the smallest detrended G-channel scatter.
#
# Usage:
#   util/seestar_photometry.sh image.fit
#       calibration analysis only
#   util/seestar_photometry.sh image.fit RA DEC
#       + measure a target at this position (sexagesimal 19:46:22.0 +18:25:10
#         or decimal degrees 296.5917 18.4194)
#   util/seestar_photometry.sh image.fit --pixel X Y
#       + measure a target at 1-based pixel position (X,Y) of the ORIGINAL
#         full-resolution Bayer mosaic
#
# Environment overrides:
#   SEESTAR_APERTURES           comma-separated aperture diameters in binned
#                               (superpixel) pixels, default "1.5,2,2.5,3,4,5,6,8"
#   SEESTAR_FIXED_APERTURE      aperture diameter for the free-slope fits and
#                               the target report (default: the aperture with
#                               the smallest detrended G-channel calibration
#                               scatter)
#   SEESTAR_BRIGHT_APERTURE     large aperture diameter offered to targets
#                               that show a significant wing flux excess in
#                               the G channel (default: the list entry
#                               closest to twice the fixed aperture)
#   SEESTAR_MATCH_RADIUS_ARCSEC catalog cross-match radius, default 6
#   SEESTAR_MAG_BRIGHT/_FAINT   catalog V range for the Gaia query, default 6.0/16.5
#   SEESTAR_MAX_MAGERR          max instrumental mag error for calibration
#                               stars (in every aperture), default 0.5
#   SEESTAR_BAYER_PATTERN       override the BAYERPAT header keyword
#   SEESTAR_WORKDIR             working directory for all products
#   SEESTAR_RESOLVE=yes         force a re-plate-solve even if wcs_* files exist
#   SEESTAR_SATUR_LEVEL         SExtractor SATUR_LEVEL, default 65000
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
    echo "$1" | awk -F/ -v dir="$2" '{
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
 VAST_PATH=$(vastrealpath "$0")
 VAST_PATH=$(dirname "$VAST_PATH")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "util")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "lib")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "examples")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "transients")
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")
 LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
 if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
  VAST_PATH="$VAST_PATH/"
 fi
 echo "$VAST_PATH"
}

if [ -z "$VAST_PATH" ];then
 VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
fi
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi

#################################
# Parse command-line arguments
#################################
if [ -z "$1" ];then
 echo "Usage:" >&2
 echo "  $0 image.fit                  # calibration analysis only" >&2
 echo "  $0 image.fit RA DEC           # + measure a target (19:46:22.0 +18:25:10 or 296.5917 18.4194)" >&2
 echo "  $0 image.fit --pixel X Y      # + measure a target at this pixel of the original Bayer mosaic" >&2
 exit 1
fi

FITSFILE=$(vastrealpath "$1")
if [ ! -s "$FITSFILE" ];then
 echo "ERROR: cannot find the input image $1" >&2
 exit 1
fi

TARGET_MODE="none"
TARGET_RA_INPUT=""
TARGET_DEC_INPUT=""
TARGET_PIXEL_X=""
TARGET_PIXEL_Y=""
if [ -n "$2" ];then
 if [ "$2" = "--pixel" ];then
  if [ -z "$4" ];then
   echo "ERROR: --pixel requires X and Y" >&2
   exit 1
  fi
  TARGET_MODE="pixel"
  TARGET_PIXEL_X="$3"
  TARGET_PIXEL_Y="$4"
 else
  if [ -z "$3" ];then
   echo "ERROR: both RA and DEC are needed" >&2
   exit 1
  fi
  TARGET_MODE="sky"
  TARGET_RA_INPUT="$2"
  TARGET_DEC_INPUT="$3"
 fi
fi

#################################
# Settings
#################################
: "${SEESTAR_APERTURES:=1.5,2,2.5,3,4,5,6,8}"
: "${SEESTAR_MATCH_RADIUS_ARCSEC:=6.0}"
: "${SEESTAR_MAG_BRIGHT:=6.0}"
: "${SEESTAR_MAG_FAINT:=16.5}"
: "${SEESTAR_MAX_MAGERR:=0.5}"
: "${SEESTAR_SATUR_LEVEL:=65000}"
: "${SEESTAR_RESOLVE:=no}"

FITS_BASENAME=$(basename "$FITSFILE")
BASE_NO_EXT="${FITS_BASENAME%.*}"
if [ -z "$SEESTAR_WORKDIR" ];then
 SEESTAR_WORKDIR="${VAST_PATH}seestar_phot_${BASE_NO_EXT}"
fi

cd "$VAST_PATH" || exit 1

#################################
# Check the required tools
#################################
for REQUIRED_TOOL in util/ccd/split_bayer lib/bin/sex lib/bin/xy2sky lib/bin/sky2xy lib/bin/skycoor lib/bin/gethead lib/vizquery lib/choose_vizier_mirror.sh lib/find_timeout_command.sh lib/fit_zeropoint lib/fit_robust_linear lib/fit_linear lib/deg2hms lib/hms2deg util/forced_photometry util/get_image_date util/imstat_vast util/wcs_image_calibration.sh ;do
 if [ ! -x "${VAST_PATH}${REQUIRED_TOOL}" ];then
  echo "ERROR: cannot find ${VAST_PATH}${REQUIRED_TOOL} -- is VaST fully built? (run 'make')" >&2
  exit 1
 fi
done

mkdir -p "$SEESTAR_WORKDIR" || exit 1
WORKDIR=$(vastrealpath "$SEESTAR_WORKDIR")

# Remove the analysis products of any previous run in this working directory,
# so a band that gets skipped in the current run cannot silently pick up stale
# calibration files (the channel images, plate-solve logs and the cached
# catalog query are kept)
rm -f "$WORKDIR"/calib_* "$WORKDIR"/fitdata_* "$WORKDIR"/param_* "$WORKDIR"/aperture_curve_* "$WORKDIR"/sample_* "$WORKDIR"/matched_* "$WORKDIR"/det_* "$WORKDIR"/target_ladder_* "$WORKDIR"/colorterms.txt "$WORKDIR"/*.png 2>/dev/null

echo "###############################################################"
echo "# Seestar/Bayer photometry prototype"
echo "# Input image: $FITSFILE"
echo "# Working directory: $WORKDIR"
echo "###############################################################"

# Parse the aperture list
APERTURE_LIST_SPACE="${SEESTAR_APERTURES//,/ }"
NAPER=$(echo "$APERTURE_LIST_SPACE" | awk '{print NF}')
if [ "$NAPER" -lt 2 ];then
 echo "ERROR: at least two apertures are needed in SEESTAR_APERTURES" >&2
 exit 1
fi
APMAX=$(echo "$APERTURE_LIST_SPACE" | awk '{m=$1; for(i=2;i<=NF;i++){if($i>m)m=$i}; print m}')

#################################
# Split the Bayer mosaic into R G B superpixel channel images
#################################
echo " "
echo "### Splitting the Bayer mosaic into R, G, B superpixel channel images ###"
if [ -n "$SEESTAR_BAYER_PATTERN" ];then
 SPLIT_OUTPUT=$("${VAST_PATH}"util/ccd/split_bayer "$FITSFILE" "$WORKDIR" "$SEESTAR_BAYER_PATTERN")
else
 SPLIT_OUTPUT=$("${VAST_PATH}"util/ccd/split_bayer "$FITSFILE" "$WORKDIR")
fi
if [ $? -ne 0 ] || [ -z "$SPLIT_OUTPUT" ];then
 echo "ERROR splitting the Bayer mosaic $FITSFILE" >&2
 exit 1
fi
CHANNEL_IMAGE_R=$(echo "$SPLIT_OUTPUT" | head -n1)
CHANNEL_IMAGE_G=$(echo "$SPLIT_OUTPUT" | head -n2 | tail -n1)
CHANNEL_IMAGE_B=$(echo "$SPLIT_OUTPUT" | tail -n1)
for CHANNEL_IMAGE in "$CHANNEL_IMAGE_R" "$CHANNEL_IMAGE_G" "$CHANNEL_IMAGE_B" ;do
 if [ ! -s "$CHANNEL_IMAGE" ];then
  echo "ERROR: the expected channel image $CHANNEL_IMAGE was not created" >&2
  exit 1
 fi
done
echo "Channel images: $CHANNEL_IMAGE_R $CHANNEL_IMAGE_G $CHANNEL_IMAGE_B"

# Image scale of the binned channel images from the (already doubled) header keywords
FOCALLEN_MM=$("${VAST_PATH}"lib/bin/gethead "$CHANNEL_IMAGE_G" FOCALLEN)
XPIXSZ_UM=$("${VAST_PATH}"lib/bin/gethead "$CHANNEL_IMAGE_G" XPIXSZ)
NAXIS1_BIN=$("${VAST_PATH}"lib/bin/gethead "$CHANNEL_IMAGE_G" NAXIS1)
NAXIS2_BIN=$("${VAST_PATH}"lib/bin/gethead "$CHANNEL_IMAGE_G" NAXIS2)
SCALE_ARCSEC_PIX=""
FOV_ARCMIN=""
if [ -n "$FOCALLEN_MM" ] && [ -n "$XPIXSZ_UM" ];then
 SCALE_ARCSEC_PIX=$(echo "$FOCALLEN_MM $XPIXSZ_UM" | awk '{printf "%.4f", 206.265*$2/$1}')
 FOV_ARCMIN=$(echo "$SCALE_ARCSEC_PIX $NAXIS1_BIN $NAXIS2_BIN" | awk '{n=$2; if($3>n)n=$3; printf "%.0f", n*$1/60.0}')
 echo "Binned image scale: $SCALE_ARCSEC_PIX arcsec/pix, field of view along the long side: $FOV_ARCMIN arcmin"
else
 echo "WARNING: cannot determine the image scale from FOCALLEN/XPIXSZ -- the plate solver will guess the field of view and the scale will be derived from the plate solution"
 SCALE_ARCSEC_PIX=""
fi

echo "Aperture diameters (binned pix): $SEESTAR_APERTURES"

#################################
# Plate-solve each channel image independently
#################################
echo " "
echo "### Plate-solving the channel images ###"
# WCS_IMAGE_R and WCS_IMAGE_B are referenced through eval below
# shellcheck disable=SC2034
WCS_IMAGE_R="${VAST_PATH}wcs_$(basename "$CHANNEL_IMAGE_R")"
WCS_IMAGE_G="${VAST_PATH}wcs_$(basename "$CHANNEL_IMAGE_G")"
# shellcheck disable=SC2034
WCS_IMAGE_B="${VAST_PATH}wcs_$(basename "$CHANNEL_IMAGE_B")"
for CHANNEL_NAME in R G B ;do
 eval CHANNEL_IMAGE=\$CHANNEL_IMAGE_$CHANNEL_NAME
 eval WCS_IMAGE=\$WCS_IMAGE_$CHANNEL_NAME
 if [ "$SEESTAR_RESOLVE" = "yes" ];then
  rm -f "$WCS_IMAGE"
 fi
 if [ -s "$WCS_IMAGE" ];then
  echo "Re-using the existing plate solution $WCS_IMAGE (set SEESTAR_RESOLVE=yes to force a re-solve)"
  continue
 fi
 echo "Plate-solving the $CHANNEL_NAME channel image..."
 # shellcheck disable=SC2086
 "${VAST_PATH}"util/wcs_image_calibration.sh "$CHANNEL_IMAGE" $FOV_ARCMIN > "$WORKDIR/platesolve_$CHANNEL_NAME.log" 2>&1
 if [ ! -s "$WCS_IMAGE" ];then
  echo "ERROR plate-solving $CHANNEL_IMAGE -- see $WORKDIR/platesolve_$CHANNEL_NAME.log" >&2
  exit 1
 fi
 echo "Plate solution: $WCS_IMAGE"
done

# If the header did not provide the image scale, derive it from the plate
# solution: everything downstream (catalog search radius, isolation radius,
# arcsec aperture sizes) depends on it
if [ -z "$SCALE_ARCSEC_PIX" ];then
 CORNER1_RADEC=$("${VAST_PATH}"lib/bin/xy2sky -j -d "$WCS_IMAGE_G" 1 1 | head -n1)
 CORNER2_RADEC=$("${VAST_PATH}"lib/bin/xy2sky -j -d "$WCS_IMAGE_G" "$NAXIS1_BIN" "$NAXIS2_BIN" | head -n1)
 DIAGONAL_ARCSEC=$("${VAST_PATH}"lib/bin/skycoor -r "$(echo "$CORNER1_RADEC" | awk '{print $1}')" "$(echo "$CORNER1_RADEC" | awk '{print $2}')" "$(echo "$CORNER2_RADEC" | awk '{print $1}')" "$(echo "$CORNER2_RADEC" | awk '{print $2}')" 2>/dev/null)
 SCALE_ARCSEC_PIX=$(echo "$DIAGONAL_ARCSEC $NAXIS1_BIN $NAXIS2_BIN" | awk 'NF==3 && $1+0>0 {printf "%.4f", $1/sqrt(($2-1)^2+($3-1)^2)}')
 if [ -z "$SCALE_ARCSEC_PIX" ];then
  echo "ERROR: cannot derive the image scale from the plate solution $WCS_IMAGE_G" >&2
  exit 1
 fi
 echo "Image scale derived from the plate solution: $SCALE_ARCSEC_PIX arcsec/pix"
fi
echo "Aperture diameters (arcsec): $(echo "$APERTURE_LIST_SPACE" | awk -v s="$SCALE_ARCSEC_PIX" '{for(i=1;i<=NF;i++)printf "%.1f ", $i*s; print ""}')"

#################################
# SExtractor configuration
#################################
SEX_PARAM_FILE="$WORKDIR/seestar.param"
{
 echo "NUMBER"
 echo "XWIN_IMAGE"
 echo "YWIN_IMAGE"
 echo "FLUX_APER(1)"
 echo "FLUXERR_APER(1)"
 echo "MAG_APER($NAPER)"
 echo "MAGERR_APER($NAPER)"
 echo "FLAGS"
 echo "FWHM_IMAGE"
} > "$SEX_PARAM_FILE"

SEX_CONFIG_FILE="$WORKDIR/seestar.sex"
cat > "$SEX_CONFIG_FILE" <<EOF
# Self-contained SExtractor configuration for the Seestar/Bayer photometry
# prototype (independent of the current default.sex of the VaST installation)
CATALOG_NAME    test.cat
CATALOG_TYPE    ASCII
PARAMETERS_NAME $SEX_PARAM_FILE
DETECT_TYPE     CCD
DETECT_MINAREA  2.0
DETECT_THRESH   3.0
ANALYSIS_THRESH 3.0
SATUR_LEVEL     $SEESTAR_SATUR_LEVEL
FILTER          Y
FILTER_NAME     ${VAST_PATH}default.conv
DEBLEND_NTHRESH 32
DEBLEND_MINCONT 0.005
CLEAN           Y
CLEAN_PARAM     1.0
MASK_TYPE       CORRECT
PHOT_APERTURES  $SEESTAR_APERTURES
PHOT_AUTOPARAMS 2.5, 3.5
MAG_ZEROPOINT   0.0
GAIN            1.0
PIXEL_SCALE     1.0
SEEING_FWHM     7.0
STARNNW_NAME    ${VAST_PATH}default.nnw
BACK_SIZE       32
BACK_FILTERSIZE 3
BACKPHOTO_TYPE  LOCAL
BACKPHOTO_THICK 12
CHECKIMAGE_TYPE NONE
MEMORY_OBJSTACK 50000
MEMORY_PIXSTACK 3000000
MEMORY_BUFSIZE  2048
VERBOSE_TYPE    QUIET
WEIGHT_TYPE     BACKGROUND
EOF

#################################
# Run SExtractor on each solved channel image and attach sky coordinates
#################################
echo " "
echo "### Running SExtractor on the channel images ###"
for CHANNEL_NAME in R G B ;do
 eval WCS_IMAGE=\$WCS_IMAGE_$CHANNEL_NAME
 SEX_CATALOG="$WORKDIR/det_$CHANNEL_NAME.cat"

 # Estimate an effective gain (e-/ADU) from the sky background statistics:
 # for a background-limited image gain ~ (median-pedestal)/variance.
 # The GAIN header keyword of ZWO cameras is a gain SETTING, not e-/ADU,
 # so it must not be passed to SExtractor directly. The estimate below
 # includes read noise in the variance and is therefore slightly
 # conservative (errors somewhat overestimated).
 PEDESTAL=$("${VAST_PATH}"lib/bin/gethead "$WCS_IMAGE" BIAS)
 if [ -z "$PEDESTAL" ];then
  PEDESTAL=0
 fi
 GAIN_EFFECTIVE=$("${VAST_PATH}"util/imstat_vast "$WCS_IMAGE" 2>/dev/null | awk -v ped="$PEDESTAL" '
  $1=="MEDIAN=" {median=$2}
  $1=="MADx1.48=" {sigma=$2}
  END {
   if ( median == "" || sigma == "" || sigma+0 <= 0.0 ) { print "0"; exit }
   g= (median - ped)/(sigma*sigma)
   if ( g < 0.001 ) g= 0
   if ( g > 100.0 ) g= 100.0
   printf "%.4f", g
  }')
 echo "$CHANNEL_NAME channel: effective gain estimate $GAIN_EFFECTIVE e-/ADU"
 if [ "$GAIN_EFFECTIVE" = "0" ];then
  echo "WARNING: the effective gain is unknown -- photon noise will not be included in the SExtractor error estimates"
 fi

 "${VAST_PATH}"lib/bin/sex -c "$SEX_CONFIG_FILE" -CATALOG_NAME "$SEX_CATALOG" -GAIN "$GAIN_EFFECTIVE" "$WCS_IMAGE" 2> "$WORKDIR/sex_$CHANNEL_NAME.log"
 if [ ! -s "$SEX_CATALOG" ];then
  echo "ERROR: empty SExtractor catalog for the $CHANNEL_NAME channel -- see $WORKDIR/sex_$CHANNEL_NAME.log" >&2
  exit 1
 fi

 # Attach RA,Dec computed through the (possibly SIP-distorted) WCS header.
 # xy2sky -a prepends 'RA Dec J2000' to each input catalog line.
 "${VAST_PATH}"lib/bin/xy2sky -a -k 2 -j -d -n 7 "$WCS_IMAGE" "@$SEX_CATALOG" 2>/dev/null | sed '/^\s*$/d' | grep -v 'Off map' | \
  awk -v naper="$NAPER" '{
   # input: RA Dec J2000 NUMBER X Y FLUX FLUXERR MAG*naper ERR*naper FLAGS FWHM
   printf "%.7f %.7f %.3f %.3f %d %.2f", $1, $2, $5, $6, $(9+2*naper), $(10+2*naper)
   for (i=1;i<=2*naper;i++) printf " %.4f", $(8+i)
   printf "\n"
  }' > "$WORKDIR/det_$CHANNEL_NAME.sky"
 N_DETECTIONS=$(wc -l < "$WORKDIR/det_$CHANNEL_NAME.sky")
 echo "$CHANNEL_NAME channel: $N_DETECTIONS detections"
 if [ "$N_DETECTIONS" -lt 10 ];then
  echo "ERROR: too few detections in the $CHANNEL_NAME channel" >&2
  exit 1
 fi
done
# det_*.sky columns: 1 RA 2 Dec 3 X 4 Y 5 FLAGS 6 FWHM 7..6+N mags 7+N..6+2N magerrs

#################################
# Query Gaia DR3 synthetic photometry (GSPC, VizieR I/360/syntphot) around
# the field center. This is the ONLY calibration catalog: its Johnson B, V
# and Cousins R magnitudes (synthesized from the BP/RP spectra and
# standardized to the JKC system) are homogeneous from G ~ 4 to G ~ 17.65,
# covering the bright and the faint end alike - unlike APASS DR9, which is
# saturated brighter than V ~ 10 (verified on the 2026-08-28 test frame:
# APASS, Tycho-2 and Gaia synthetic V agree to 0.04 mag in zero point, and
# the bright-end residual trend of the G channel is the same against all
# three, i.e. instrumental).
#################################
echo " "
echo "### Querying Gaia DR3 synthetic photometry (GSPC, VizieR I/360) ###"
CENTER_XY_X=$(echo "$NAXIS1_BIN" | awk '{printf "%.1f",($1+1.0)/2.0}')
CENTER_XY_Y=$(echo "$NAXIS2_BIN" | awk '{printf "%.1f",($1+1.0)/2.0}')
CENTER_RADEC=$("${VAST_PATH}"lib/bin/xy2sky -j -d "$WCS_IMAGE_G" "$CENTER_XY_X" "$CENTER_XY_Y" | head -n1)
CENTER_RA_DEG=$(echo "$CENTER_RADEC" | awk '{print $1}')
CENTER_DEC_DEG=$(echo "$CENTER_RADEC" | awk '{print $2}')
CENTER_HMS=$("${VAST_PATH}"lib/deg2hms "$CENTER_RA_DEG" "$CENTER_DEC_DEG")
SEARCH_RADIUS_ARCMIN=$(echo "$SCALE_ARCSEC_PIX $NAXIS1_BIN $NAXIS2_BIN" | awk '{printf "%.0f", 0.5*sqrt(($2*$1)^2+($3*$1)^2)/60.0 + 2.0}')
echo "Field center: $CENTER_HMS ($CENTER_RA_DEG $CENTER_DEC_DEG), search radius $SEARCH_RADIUS_ARCMIN arcmin"

# Pick a VizieR mirror only when a query is actually needed (the catalog
# download is cached in the working directory)
VIZIER_SITE=""
ensure_vizier_site() {
 if [ -z "$VIZIER_SITE" ];then
  VIZIER_SITE=$("${VAST_PATH}"lib/choose_vizier_mirror.sh APASS 2>/dev/null)
  if [ -z "$VIZIER_SITE" ];then
   VIZIER_SITE="vizier.cds.unistra.fr"
  fi
  echo "VizieR mirror: $VIZIER_SITE"
  TIMEOUT_COMMAND=$("${VAST_PATH}"lib/find_timeout_command.sh 2>/dev/null)
 fi
}

GAIA_SYNTH_RAW="$WORKDIR/gaia_synth_raw.tsv"
if [ -s "$GAIA_SYNTH_RAW" ];then
 echo "Re-using the cached Gaia DR3 synthetic photometry query result $GAIA_SYNTH_RAW"
else
 ensure_vizier_site
 # Download to a temporary file first so an interrupted or timed-out query
 # cannot poison the cache with a truncated catalog
 # shellcheck disable=SC2086
 $TIMEOUT_COMMAND 300 "${VAST_PATH}"lib/vizquery -site="$VIZIER_SITE" -mime=tsv -source=I/360/syntphot -out.max=200000 -out="RA_ICRS,DE_ICRS,Bmag,FB,e_FB,Vmag,FV,e_FV,Rmag,FR,e_FR" Vmag="$(echo "$SEESTAR_MAG_BRIGHT" | awk '{print $1-1.0}')..$(echo "$SEESTAR_MAG_FAINT" | awk '{print $1+0.5}')" -c="$CENTER_HMS" -c.rm="$SEARCH_RADIUS_ARCMIN" > "$GAIA_SYNTH_RAW.tmp" 2> "$WORKDIR/vizquery_gaia_synth.log"
 VIZQUERY_EXIT_CODE=$?
 if [ $VIZQUERY_EXIT_CODE -ne 0 ] || [ ! -s "$GAIA_SYNTH_RAW.tmp" ];then
  rm -f "$GAIA_SYNTH_RAW.tmp"
  echo "ERROR: the Gaia DR3 synthetic photometry VizieR query failed (exit code $VIZQUERY_EXIT_CODE) -- see $WORKDIR/vizquery_gaia_synth.log" >&2
  exit 1
 fi
 mv -f "$GAIA_SYNTH_RAW.tmp" "$GAIA_SYNTH_RAW"
fi

# Parse the tab-separated VizieR output into a clean whitespace-separated
# table: RA Dec B eB V eV R eR. Missing values become 99. Positions are ICRS
# epoch 2016.0 without proper motions: the ~10 yr drift to the observation
# epoch is negligible for the cross-matching except for rare
# high-proper-motion stars. Magnitude errors are derived from the synthetic
# flux errors as 1.0857*e_F/F.
awk -F'\t' '
 function num(v) { gsub(/ /,"",v); if (v=="" || v !~ /^[-+]?[0-9.eE-]+$/) return 99; return v+0 }
 function magerr(f, ef) { if (f==99 || ef==99 || f<=0) return 0.03; e= 1.0857*ef/f; if (e<0.01) e=0.01; return e }
 {
  if ($0 ~ /^#/) next
  if ($1 !~ /^[ ]*[0-9]/) next
  if (NF < 11) next
  ra=num($1); dec=num($2)
  if (ra==99 || dec==99) next
  b=num($3); v=num($6); r=num($9)
  if (v>90) next
  eb= (b<90) ? magerr(num($4), num($5)) : 99
  ev= magerr(num($7), num($8))
  er= (r<90) ? magerr(num($10), num($11)) : 99
  printf "%.7f %.7f %.3f %.3f %.3f %.3f %.3f %.3f\n", ra, dec, b, eb, v, ev, r, er
 }' "$GAIA_SYNTH_RAW" > "$WORKDIR/catalog_clean.txt"
N_CATALOG=$(wc -l < "$WORKDIR/catalog_clean.txt")
echo "Gaia DR3 synthetic photometry stars in the field: $N_CATALOG"
if [ "$N_CATALOG" -lt 10 ];then
 echo "ERROR: too few catalog stars -- VizieR query failed? See $WORKDIR/vizquery_gaia_synth.log and $GAIA_SYNTH_RAW (delete $GAIA_SYNTH_RAW to force a fresh query)" >&2
 exit 1
fi

# Nearest-relevant-neighbor distance (arcsec) between catalog stars for the
# isolation filter. Since the Gaia catalog is deep, a neighbor is counted
# only when it is no more than 4 V magnitudes fainter than the star itself
# (a fainter one contributes negligible flux to the aperture). Stars are
# binned by declination to keep the search fast on this large catalog.
awk '
 { ra[NR]=$1; dec[NR]=$2; v[NR]=$5; line[NR]=$0; b=int($2*100); blist[b]=blist[b]" "NR }
 END {
  d2r= 3.14159265358979/180.0
  for (j=1;j<=NR;j++) {
   best= 1e30; cd= cos(dec[j]*d2r)
   b0= int(dec[j]*100)
   for (bb=b0-2;bb<=b0+2;bb++) {
    if (!(bb in blist)) continue
    n=split(blist[bb],idx," ")
    for (m=1;m<=n;m++) {
     k=idx[m]
     if (k==j) continue
     if (v[k] > v[j]+4.0) continue
     dx= (ra[k]-ra[j])*cd; dy= dec[k]-dec[j]
     d2= dx*dx+dy*dy
     if (d2<best) best=d2
    }
   }
   nn= (best<1e29) ? sqrt(best)*3600.0 : 999.0
   printf "%s %.2f\n", line[j], nn
  }
 }' "$WORKDIR/catalog_clean.txt" > "$WORKDIR/catalog_nn.txt"
# catalog_nn.txt columns: 1 RA 2 Dec 3 B 4 eB 5 V 6 eV 7 R 8 eR 9 nn_arcsec

#################################
# Cross-match the catalog with the detections in each channel
#################################
echo " "
echo "### Cross-matching the catalog with the detections ###"
for CHANNEL_NAME in R G B ;do
 awk -v mr="$SEESTAR_MATCH_RADIUS_ARCSEC" '
  NR==FNR { dra[FNR]=$1; ddec[FNR]=$2; dline[FNR]=$0; nd=FNR; next }
  {
   d2r= 3.14159265358979/180.0
   cd= cos($2*d2r)
   best= 1e30; bestk= 0
   for (k=1;k<=nd;k++) {
    dx= (dra[k]-$1)*cd; dy= ddec[k]-$2
    d2= dx*dx+dy*dy
    if (d2<best) { best=d2; bestk=k }
   }
   sep= sqrt(best)*3600.0
   if (bestk>0 && sep<=mr) {
    n=split(dline[bestk],df," ")
    printf "%s %.2f", $0, sep
    for (i=3;i<=n;i++) printf " %s", df[i]
    printf "\n"
   }
  }' "$WORKDIR/det_$CHANNEL_NAME.sky" "$WORKDIR/catalog_nn.txt" > "$WORKDIR/matched_$CHANNEL_NAME.txt"
 echo "$CHANNEL_NAME channel: $(wc -l < "$WORKDIR/matched_$CHANNEL_NAME.txt") catalog stars matched within $SEESTAR_MATCH_RADIUS_ARCSEC arcsec"
done
# matched_*.txt columns: 1-9 as catalog_nn, 10 sep_arcsec, 11 X 12 Y 13 FLAGS 14 FWHM, 15..14+N mags, 15+N..14+2N magerrs

#################################
# Select the calibration star sample (common for all apertures):
#  - clean SExtractor FLAGS
#  - valid measurement in EVERY aperture
#  - away from the frame edges
#  - no catalog neighbor (at most 4 mag fainter) within the isolation radius
#################################
ISOLATION_RADIUS_ARCSEC=$(echo "$APMAX $SCALE_ARCSEC_PIX" | awk '{printf "%.1f", 0.5*$1*$2 + 5.0}')
EDGE_MARGIN_PIX=$(echo "$APMAX" | awk '{printf "%.0f", 0.5*$1 + 3.0}')
echo " "
echo "### Selecting calibration stars (isolation radius $ISOLATION_RADIUS_ARCSEC arcsec, edge margin $EDGE_MARGIN_PIX pix, max mag err $SEESTAR_MAX_MAGERR) ###"

# band definitions: channel : band name : catalog mag column : catalog err column
# All three channels are calibrated against Gaia DR3 synthetic photometry
# (GSPC, JKC system), following the AAVSO tricolor (TB/TG/TR) convention of
# blue vs Johnson B, green vs Johnson V, red vs Cousins R comparison-star
# magnitudes.
# NOTE on the red channel: empirically the red channel of an
# IR-cut-filtered one-shot-color camera is a CLOSER match to Sloan r' than
# to Cousins Rc (Seestar S50, 2026-08-30: color term -0.045 vs -0.215 mag
# per mag of B-V) because the IR-cut filter removes the 700-800 nm tail
# that distinguishes Rc from r'. Cousins R is used nevertheless, as the
# AAVSO recommends R-band comparison magnitudes for TR photometry; Gaia
# synthetic SDSS r is available in I/360/syntphot (rmag,Fr,e_Fr) should an
# r' calibration be wanted.
# NOTE on the bright end: APASS DR9 (the previous calibration catalog) is
# saturated brighter than V ~ 10; cross-checks against Tycho-2 and Gaia
# synthetic V on the 2026-08-28 test frame showed all three zero points
# agree to 0.04 mag and the bright-end residual trend of the G channel is
# instrumental (star wings), not a catalog artifact.
BAND_DEFINITIONS="B:GaiaB:3:4 G:GaiaV:5:6 R:GaiaR:7:8"

for BAND_DEFINITION in $BAND_DEFINITIONS ;do
 CHANNEL_NAME="${BAND_DEFINITION%%:*}"
 REST="${BAND_DEFINITION#*:}"
 BAND_NAME="${REST%%:*}"
 REST="${REST#*:}"
 CATALOG_MAG_COLUMN="${REST%%:*}"

 awk -v naper="$NAPER" -v catcol="$CATALOG_MAG_COLUMN" -v iso="$ISOLATION_RADIUS_ARCSEC" \
     -v margin="$EDGE_MARGIN_PIX" -v nx="$NAXIS1_BIN" -v ny="$NAXIS2_BIN" -v maxerr="$SEESTAR_MAX_MAGERR" '
  {
   if ($13 != 0) next                     # SExtractor FLAGS
   if ($(catcol) > 90) next               # no catalog magnitude in this band
   if ($9 < iso) next                     # catalog neighbor too close
   if ($11 < margin || $11 > nx-margin) next
   if ($12 < margin || $12 > ny-margin) next
   if ($14 < 0.5 || $14 > 10.0) next      # FWHM sanity
   good=1
   for (i=1;i<=naper;i++) {
    if ($(14+i) > 90) good=0
    if ($(14+naper+i) > maxerr) good=0
   }
   if (good) print
  }' "$WORKDIR/matched_$CHANNEL_NAME.txt" > "$WORKDIR/sample_${CHANNEL_NAME}_${BAND_NAME}.txt"
 echo "$CHANNEL_NAME channel vs $BAND_NAME: $(wc -l < "$WORKDIR/sample_${CHANNEL_NAME}_${BAND_NAME}.txt") calibration stars"
 # A catalog error of exactly 0.000 would flag suspect photometry
 # (never expected from the flux-derived Gaia synthetic errors)
 N_ZERO_CATALOG_ERR=$(awk -v ec=$((CATALOG_MAG_COLUMN+1)) '$(ec)==0 {n++} END{print n+0}' "$WORKDIR/sample_${CHANNEL_NAME}_${BAND_NAME}.txt")
 if [ "$N_ZERO_CATALOG_ERR" -gt 0 ];then
  echo "WARNING: $N_ZERO_CATALOG_ERR of them have catalog error 0.000 in this band"
 fi
done

#################################
# Zero-point-only calibration as a function of the aperture size
#################################
echo " "
echo "### Zero-point-only calibration (slope fixed to 1) vs aperture size ###"
APERTURE_INDEX=0
for BAND_DEFINITION in $BAND_DEFINITIONS ;do
 CHANNEL_NAME="${BAND_DEFINITION%%:*}"
 REST="${BAND_DEFINITION#*:}"
 BAND_NAME="${REST%%:*}"
 REST="${REST#*:}"
 CATALOG_MAG_COLUMN="${REST%%:*}"

 SAMPLE_FILE="$WORKDIR/sample_${CHANNEL_NAME}_${BAND_NAME}.txt"
 CURVE_FILE="$WORKDIR/aperture_curve_${CHANNEL_NAME}_${BAND_NAME}.txt"
 : > "$CURVE_FILE"
 N_SAMPLE=$(wc -l < "$SAMPLE_FILE")
 if [ "$N_SAMPLE" -lt 5 ];then
  echo "WARNING: only $N_SAMPLE calibration stars for $CHANNEL_NAME vs $BAND_NAME -- skipping this band"
  continue
 fi

 echo " "
 echo "$CHANNEL_NAME channel vs $BAND_NAME ($N_SAMPLE stars):"
 printf "%12s %14s %8s %12s %12s %12s %12s\n" "aper[pix]" "aper[arcsec]" "Nstars" "ZP[mag]" "scatter[mag]" "detrend[mag]" "trend_pp[mag]"
 APERTURE_INDEX=0
 for APERTURE_DIAMETER in $APERTURE_LIST_SPACE ;do
  APERTURE_INDEX=$((APERTURE_INDEX+1))
  CALIB_FILE="$WORKDIR/calib_${CHANNEL_NAME}_${BAND_NAME}_ap${APERTURE_INDEX}.txt"
  awk -v naper="$NAPER" -v ai="$APERTURE_INDEX" -v catcol="$CATALOG_MAG_COLUMN" \
   '{printf "%.4f %.3f %.4f\n", $(14+ai), $(catcol), $(14+naper+ai)}' "$SAMPLE_FILE" > "$CALIB_FILE"
  FIT_OUTPUT=$(cd "$WORKDIR" && "${VAST_PATH}"lib/fit_zeropoint "$CALIB_FILE" 2>/dev/null)
  ZERO_POINT=$(echo "$FIT_OUTPUT" | awk '{print $3}')
  if [ -z "$ZERO_POINT" ];then
   echo "WARNING: zero-point fit failed for $CHANNEL_NAME $BAND_NAME aperture $APERTURE_DIAMETER"
   continue
  fi
  # Calibration quality is quantified as a PAIR of numbers:
  #  - the DETRENDED robust scatter: 1.4826*MAD of the residuals about a
  #    running-median trend of residual vs catalog magnitude (11-point
  #    window). This is the star-to-star precision the aperture actually
  #    controls, free of the faint-majority bias of a plain global scatter.
  #  - the TREND AMPLITUDE: peak-to-peak span of that running median, i.e.
  #    the magnitude-dependent calibration bias (mostly bright-star wing
  #    losses), reported separately because it is a smooth correctable
  #    function rather than random noise.
  # The plain global 1.4826*MAD is kept for reference.
  STATS=$(awk -v zp="$ZERO_POINT" '
   function median_of(a, n,  j,k,t) {
    for (j=1;j<n;j++) for (k=j+1;k<=n;k++) if (a[k]<a[j]) {t=a[j];a[j]=a[k];a[k]=t}
    return (n%2==1) ? a[(n+1)/2] : 0.5*(a[n/2]+a[n/2+1])
   }
   { r[NR]= $2-$1-zp; cm[NR]= $2 }
   END {
    n=NR
    if (n<1) exit
    # plain robust scatter about the median residual
    for (j=1;j<=n;j++) s[j]=r[j]
    med= median_of(s, n)
    for (j=1;j<=n;j++) d[j]= (r[j]>med) ? r[j]-med : med-r[j]
    mad= median_of(d, n)
    # running-median trend of residual vs catalog magnitude
    for (j=1;j<=n;j++) idx[j]=j
    for (j=1;j<n;j++) for (k=j+1;k<=n;k++) if (cm[idx[k]]<cm[idx[j]]) {t=idx[j];idx[j]=idx[k];idx[k]=t}
    half= 5
    if (n<11) half= int((n-1)/2)
    tmin= 1e30; tmax= -1e30
    for (j=1;j<=n;j++) {
     lo= j-half; hi= j+half
     if (lo<1) lo=1
     if (hi>n) hi=n
     m=0
     for (k=lo;k<=hi;k++) { m++; w[m]= r[idx[k]] }
     tr= median_of(w, m)
     trend[idx[j]]= tr
     if (tr<tmin) tmin=tr
     if (tr>tmax) tmax=tr
    }
    # robust scatter of the detrended residuals
    for (j=1;j<=n;j++) s2[j]= r[j]-trend[j]
    med2= median_of(s2, n)
    for (j=1;j<=n;j++) { v= r[j]-trend[j]; d2[j]= (v>med2) ? v-med2 : med2-v }
    mad2= median_of(d2, n)
    printf "%d %.4f %.4f %.4f", n, 1.4826*mad, 1.4826*mad2, tmax-tmin
   }' "$CALIB_FILE")
  N_USED=$(echo "$STATS" | awk '{print $1}')
  SCATTER=$(echo "$STATS" | awk '{print $2}')
  SCATTER_DETRENDED=$(echo "$STATS" | awk '{print $3}')
  TREND_AMPLITUDE=$(echo "$STATS" | awk '{print $4}')
  APERTURE_ARCSEC=$(echo "$APERTURE_DIAMETER $SCALE_ARCSEC_PIX" | awk '{printf "%.2f", $1*$2}')
  printf "%12s %14s %8d %12.4f %12.4f %12.4f %12.4f\n" "$APERTURE_DIAMETER" "$APERTURE_ARCSEC" "$N_USED" "$ZERO_POINT" "$SCATTER" "$SCATTER_DETRENDED" "$TREND_AMPLITUDE"
  echo "$APERTURE_DIAMETER $APERTURE_ARCSEC $N_USED $ZERO_POINT $SCATTER $SCATTER_DETRENDED $TREND_AMPLITUDE" >> "$CURVE_FILE"
 done
done
# aperture_curve_* columns: 1 ap_diam_pix 2 ap_diam_arcsec 3 N 4 ZP 5 global_MAD_scatter 6 detrended_scatter 7 trend_amplitude

#################################
# Choose the fixed aperture for the free-slope comparison and the target report
#################################
if [ -n "$SEESTAR_FIXED_APERTURE" ];then
 FIXED_APERTURE="$SEESTAR_FIXED_APERTURE"
else
 FIXED_APERTURE=$(awk 'BEGIN{best=1e30} {if ($6<best){best=$6; a=$1}} END{print a}' "$WORKDIR/aperture_curve_G_GaiaV.txt" 2>/dev/null)
 if [ -z "$FIXED_APERTURE" ];then
  # fall back to the middle of the aperture list
  FIXED_APERTURE=$(echo "$APERTURE_LIST_SPACE" | awk '{print $(int((NF+1)/2))}')
 fi
fi
# index of the fixed aperture in the list
FIXED_APERTURE_INDEX=$(echo "$APERTURE_LIST_SPACE" | awk -v a="$FIXED_APERTURE" '{for(i=1;i<=NF;i++) if ($i==a) {print i; exit}}')
if [ -z "$FIXED_APERTURE_INDEX" ];then
 echo "ERROR: the fixed aperture $FIXED_APERTURE is not in the aperture list $SEESTAR_APERTURES" >&2
 exit 1
fi
FIXED_APERTURE_ARCSEC=$(echo "$FIXED_APERTURE $SCALE_ARCSEC_PIX" | awk '{printf "%.2f", $1*$2}')
echo " "
echo "### Fixed aperture diameter for the free-slope comparison: $FIXED_APERTURE pix = $FIXED_APERTURE_ARCSEC arcsec ###"
echo "Note: the fixed aperture is chosen by the smallest DETRENDED G-channel calibration scatter (star-to-star scatter"
echo "      about a running-median residual-vs-magnitude trend); the trend_pp column quantifies the magnitude-dependent"
echo "      calibration bias separately. Differences between neighboring apertures are comparable to the estimator noise."

# The large aperture offered to bright targets whose wings spill out of the
# fixed aperture (empirically, on the Seestar S50 test frame the bright-star
# effective PSF is broader and 5-8 superpixel apertures minimize the residual
# scatter for stars in the top ~2 magnitudes below saturation)
if [ -n "$SEESTAR_BRIGHT_APERTURE" ];then
 BRIGHT_APERTURE=$(echo "$APERTURE_LIST_SPACE" | awk -v a="$SEESTAR_BRIGHT_APERTURE" '{for(i=1;i<=NF;i++) if ($i==a) {print a; exit}}')
 if [ -z "$BRIGHT_APERTURE" ];then
  echo "WARNING: SEESTAR_BRIGHT_APERTURE=$SEESTAR_BRIGHT_APERTURE is not in the aperture list $SEESTAR_APERTURES -- choosing automatically"
 fi
fi
if [ -z "$BRIGHT_APERTURE" ];then
 BRIGHT_APERTURE=$(echo "$APERTURE_LIST_SPACE" | awk -v f="$FIXED_APERTURE" '{bd=1e30; best=""; for(i=1;i<=NF;i++){if ($i>f) {d=$i-2*f; if(d<0)d=-d; if(d<bd){bd=d; best=$i}}} print best}')
fi
if [ -n "$BRIGHT_APERTURE" ];then
 echo "Large aperture diameter for targets with a wing flux excess: $BRIGHT_APERTURE pix"
fi

#################################
# Zero-point-only vs free-slope calibration at the fixed aperture
#################################
echo " "
echo "### Calibration fits at the fixed aperture (catalog_mag = slope * instrumental_mag + ZP) ###"
printf "%14s %10s | %-22s | %-32s | %-32s\n" "channel/band" "Nstars" "ZP-only (slope==1)" "robust linear (unweighted)" "weighted linear"
for BAND_DEFINITION in $BAND_DEFINITIONS ;do
 CHANNEL_NAME="${BAND_DEFINITION%%:*}"
 REST="${BAND_DEFINITION#*:}"
 BAND_NAME="${REST%%:*}"
 REST="${REST#*:}"
 CATALOG_MAG_COLUMN="${REST%%:*}"

 CALIB_FILE="$WORKDIR/calib_${CHANNEL_NAME}_${BAND_NAME}_ap${FIXED_APERTURE_INDEX}.txt"
 if [ ! -s "$CALIB_FILE" ];then
  continue
 fi
 N_SAMPLE=$(wc -l < "$CALIB_FILE")

 ZP_FIT=$(cd "$WORKDIR" && "${VAST_PATH}"lib/fit_zeropoint "$CALIB_FILE" 2>/dev/null)
 cp -f "$WORKDIR/calib.txt_param" "$WORKDIR/param_${CHANNEL_NAME}_${BAND_NAME}_zp.txt" 2>/dev/null
 ROBUST_FIT=$(cd "$WORKDIR" && "${VAST_PATH}"lib/fit_robust_linear "$CALIB_FILE" 2>/dev/null)
 cp -f "$WORKDIR/calib.txt_param" "$WORKDIR/param_${CHANNEL_NAME}_${BAND_NAME}_robust.txt" 2>/dev/null
 LINEAR_FIT=$(cd "$WORKDIR" && "${VAST_PATH}"lib/fit_linear "$CALIB_FILE" 2>/dev/null)

 ZP_C=$(echo "$ZP_FIT" | awk '{print $3}')
 ROBUST_B=$(echo "$ROBUST_FIT" | awk '{print $2}')
 ROBUST_C=$(echo "$ROBUST_FIT" | awk '{print $3}')
 LINEAR_B=$(echo "$LINEAR_FIT" | awk '{print $2}')
 LINEAR_C=$(echo "$LINEAR_FIT" | awk '{print $3}')
 if [ -z "$ZP_C" ];then
  echo "WARNING: the zero-point fit failed for ${CHANNEL_NAME}/${BAND_NAME} at the fixed aperture -- skipping this band"
  continue
 fi
 if [ -z "$ROBUST_B" ] || [ -z "$LINEAR_B" ];then
  # keep the zero-point calibration usable, degrade the slope fits to slope==1
  echo "WARNING: the free-slope fit failed for ${CHANNEL_NAME}/${BAND_NAME} -- only the zero-point calibration is available"
  ROBUST_B="1.0"
  ROBUST_C="$ZP_C"
  LINEAR_B="1.0"
  LINEAR_C="$ZP_C"
 fi

 # Residual scatter (1.4826*MAD) and OLS slope standard error for each model,
 # and the calibration scatter table row; also write the per-star data file
 # used for plotting: inst cat insterr resid_zp resid_robust B-V
 MODEL_STATS=$(awk -v zpc="$ZP_C" -v rb="$ROBUST_B" -v rc="$ROBUST_C" -v lb="$LINEAR_B" -v lc="$LINEAR_C" '
  function madsigma(arr, n,  j,k,t,med,dd) {
   for (j=1;j<n;j++) for (k=j+1;k<=n;k++) if (arr[k]<arr[j]) {t=arr[j];arr[j]=arr[k];arr[k]=t}
   med= (n%2==1) ? arr[(n+1)/2] : 0.5*(arr[n/2]+arr[n/2+1])
   for (j=1;j<=n;j++) { dd[j]= arr[j]-med; if (dd[j]<0) dd[j]=-dd[j] }
   for (j=1;j<n;j++) for (k=j+1;k<=n;k++) if (dd[k]<dd[j]) {t=dd[j];dd[j]=dd[k];dd[k]=t}
   return 1.4826*((n%2==1) ? dd[(n+1)/2] : 0.5*(dd[n/2]+dd[n/2+1]))
  }
  { x[NR]=$1; y[NR]=$2
    rzp[NR]= $2-$1-zpc
    rrob[NR]= $2-rb*$1-rc
    rlin[NR]= $2-lb*$1-lc
    sx+=$1; sy+=$2; sxx+=$1*$1; sxy+=$1*$2
  }
  END {
   n=NR
   szp= madsigma(rzp, n)
   # recompute robust residuals (rzp array got sorted in place by madsigma)
   for (j=1;j<=n;j++) rr[j]= y[j]-rb*x[j]-rc
   srob= madsigma(rr, n)
   for (j=1;j<=n;j++) rl[j]= y[j]-lb*x[j]-lc
   slin= madsigma(rl, n)
   # OLS slope standard error around the robust line
   ssr=0
   for (j=1;j<=n;j++) { d= y[j]-rb*x[j]-rc; ssr+= d*d }
   sxxc= sxx - sx*sx/n
   se= (n>2 && sxxc>0) ? sqrt(ssr/(n-2)/sxxc) : 0
   printf "%.4f %.4f %.4f %.4f", szp, srob, slin, se
  }' "$CALIB_FILE")
 SCATTER_ZP=$(echo "$MODEL_STATS" | awk '{print $1}')
 SCATTER_ROBUST=$(echo "$MODEL_STATS" | awk '{print $2}')
 SCATTER_LINEAR=$(echo "$MODEL_STATS" | awk '{print $3}')
 SLOPE_STDERR=$(echo "$MODEL_STATS" | awk '{print $4}')

 printf "%14s %10d | ZP=%8.4f s=%6.4f | slope=%7.4f+/-%6.4f s=%6.4f | slope=%7.4f ZP=%8.4f s=%6.4f\n" \
  "${CHANNEL_NAME}/${BAND_NAME}" "$N_SAMPLE" "$ZP_C" "$SCATTER_ZP" "$ROBUST_B" "$SLOPE_STDERR" "$SCATTER_ROBUST" "$LINEAR_B" "$LINEAR_C" "$SCATTER_LINEAR"

 # store for later use; the target error bar uses the DETRENDED scatter at
 # the fixed aperture (the trend is a separate systematic, not random noise)
 DETRENDED_AT_FIXED=$(awk -v a="$FIXED_APERTURE" '$1==a {print $6; exit}' "$WORKDIR/aperture_curve_${CHANNEL_NAME}_${BAND_NAME}.txt" 2>/dev/null)
 if [ -z "$DETRENDED_AT_FIXED" ];then
  DETRENDED_AT_FIXED="$SCATTER_ZP"
 fi
 eval "ZP_${CHANNEL_NAME}_${BAND_NAME}=\$ZP_C"
 eval "SCATTER_${CHANNEL_NAME}_${BAND_NAME}=\$DETRENDED_AT_FIXED"
 eval "ROBUSTB_${CHANNEL_NAME}_${BAND_NAME}=\$ROBUST_B"
 eval "ROBUSTC_${CHANNEL_NAME}_${BAND_NAME}=\$ROBUST_C"

 # per-star data file for plots and color-term diagnostics
 awk -v naper="$NAPER" -v ai="$FIXED_APERTURE_INDEX" -v catcol="$CATALOG_MAG_COLUMN" \
     -v zpc="$ZP_C" -v rb="$ROBUST_B" -v rc="$ROBUST_C" '
  {
   bv= ($3<90 && $5<90) ? $3-$5 : 99
   inst= $(14+ai); cat= $(catcol); err= $(14+naper+ai)
   printf "%.4f %.3f %.4f %.4f %.4f %.3f\n", inst, cat, err, cat-inst-zpc, cat-rb*inst-rc, bv
  }' "$WORKDIR/sample_${CHANNEL_NAME}_${BAND_NAME}.txt" > "$WORKDIR/fitdata_${CHANNEL_NAME}_${BAND_NAME}.txt"
done

#################################
# Color-term diagnostics: residual of the ZP-only calibration vs B-V color
#################################
echo " "
echo "### Color terms: ZP-only residual (catalog - instrumental - ZP) vs catalog B-V ###"
for BAND_DEFINITION in $BAND_DEFINITIONS ;do
 CHANNEL_NAME="${BAND_DEFINITION%%:*}"
 REST="${BAND_DEFINITION#*:}"
 BAND_NAME="${REST%%:*}"
 FITDATA_FILE="$WORKDIR/fitdata_${CHANNEL_NAME}_${BAND_NAME}.txt"
 if [ ! -s "$FITDATA_FILE" ];then
  continue
 fi
 awk -v ch="$CHANNEL_NAME" -v band="$BAND_NAME" '
  $6<90 { n++; sx+=$6; sy+=$4; sxx+=$6*$6; sxy+=$6*$4 }
  END {
   if (n<5) { printf "%s/%s: not enough stars with B-V for the color-term fit\n", ch, band; exit }
   det= n*sxx-sx*sx
   slope= (n*sxy-sx*sy)/det
   intercept= (sy-slope*sx)/n
   printf "%s vs %-5s: residual = %+.4f * (B-V) %+.4f   (N=%d)\n", ch, band, slope, intercept, n
   printf "%s %s %+.4f\n", ch, band, slope >> "'"$WORKDIR"'/colorterms.txt"
  }' "$FITDATA_FILE"
done
# A large color term means the channel bandpass differs substantially from the
# catalog band: the calibrated magnitudes are then on a natural system tied to
# the mean color of the calibration stars, not on the standard system
BLUE_COLOR_TERM=$(awk '$1=="B" && $2=="B" {print $3}' "$WORKDIR/colorterms.txt" 2>/dev/null)
if [ -n "$BLUE_COLOR_TERM" ] && echo "$BLUE_COLOR_TERM" | awk '{v=$1; if(v<0)v=-v; exit !(v>0.3)}' ;then
 echo "WARNING: the Bayer-blue channel has a large color term versus Johnson B ($BLUE_COLOR_TERM mag per mag of B-V):"
 echo "         treat the 'B' results as natural-system tricolor blue (AAVSO TB-like) unless a color correction"
 echo "         with the known target color is applied; for a color-changing target the bias is time-variable."
fi

#################################
# Residual vs magnitude: reveals the trends (bright-end aperture losses,
# faint-end detection bias, catalog systematics) that pull the free-slope
# fit away from slope==1
#################################
echo " "
echo "### ZP-only residual vs catalog magnitude at the fixed aperture ###"
for BAND_DEFINITION in $BAND_DEFINITIONS ;do
 CHANNEL_NAME="${BAND_DEFINITION%%:*}"
 REST="${BAND_DEFINITION#*:}"
 BAND_NAME="${REST%%:*}"
 FITDATA_FILE="$WORKDIR/fitdata_${CHANNEL_NAME}_${BAND_NAME}.txt"
 if [ ! -s "$FITDATA_FILE" ];then
  continue
 fi
 awk -v ch="$CHANNEL_NAME" -v band="$BAND_NAME" '
  { b=int($2); s[b]+=$4; n[b]++ }
  END {
   printf "%s vs %-5s:", ch, band
   for (b=5;b<=20;b++) if (n[b]>0) printf "  mag %d-%d: %+.3f (N=%d)", b, b+1, s[b]/n[b], n[b]
   printf "\n"
  }' "$FITDATA_FILE"
done

#################################
# Bayer R/B channel assignment sanity check from stellar colors:
# instrumental (Bchan - Gchan) must INCREASE with catalog B-V,
# instrumental (Rchan - Gchan) must DECREASE with catalog B-V.
#################################
echo " "
echo "### Bayer R/B channel assignment check ###"
awk -v naper="$NAPER" -v ai="$FIXED_APERTURE_INDEX" '
 function key(r,d) { return sprintf("%.5f_%.5f", r, d) }
 FILENAME ~ /matched_B\.txt$/ { if ($13==0 && $(14+ai)<90) binst[key($1,$2)]=$(14+ai); next }
 FILENAME ~ /matched_R\.txt$/ { if ($13==0 && $(14+ai)<90) rinst[key($1,$2)]=$(14+ai); next }
 {
  if ($13!=0 || $(14+ai)>90) next
  if ($3>90 || $5>90) next
  k= key($1,$2)
  bv= $3-$5
  if (k in binst) { nb++; bx[nb]=bv; by[nb]= binst[k]-$(14+ai) }
  if (k in rinst) { nr++; rx[nr]=bv; ry[nr]= rinst[k]-$(14+ai) }
 }
 END {
  if (nb>=5) {
   sx=sy=sxx=sxy=0
   for (j=1;j<=nb;j++) { sx+=bx[j]; sy+=by[j]; sxx+=bx[j]*bx[j]; sxy+=bx[j]*by[j] }
   bslope= (nb*sxy-sx*sy)/(nb*sxx-sx*sx)
   printf "d(Binst-Ginst)/d(B-V) = %+.3f (expected positive, N=%d)\n", bslope, nb
  } else { print "Not enough stars for the B-G color check"; bslope=0 }
  if (nr>=5) {
   sx=sy=sxx=sxy=0
   for (j=1;j<=nr;j++) { sx+=rx[j]; sy+=ry[j]; sxx+=rx[j]*rx[j]; sxy+=rx[j]*ry[j] }
   rslope= (nr*sxy-sx*sy)/(nr*sxx-sx*sx)
   printf "d(Rinst-Ginst)/d(B-V) = %+.3f (expected negative, N=%d)\n", rslope, nr
  } else { print "Not enough stars for the R-G color check"; rslope=0 }
  if (bslope<0 && rslope>0) {
   print "WARNING: the color slopes have the WRONG signs - the R and B Bayer channels appear to be SWAPPED!"
   print "WARNING: re-run with SEESTAR_BAYER_PATTERN set to the vertically-flipped pattern (e.g. GRBG <-> GBRG)"
  } else if (bslope>0 && rslope<0) {
   print "The R/B channel assignment looks correct."
  } else {
   print "WARNING: inconclusive R/B channel color check."
  }
 }' "$WORKDIR/matched_B.txt" "$WORKDIR/matched_R.txt" "$WORKDIR/matched_G.txt"

#################################
# Diagnostic plots (no background grids)
#################################
if command -v gnuplot > /dev/null 2>&1 ;then
 echo " "
 echo "### Making diagnostic plots ###"
 GNUPLOT_SCRIPT="$WORKDIR/plots.gnuplot"
 {
  echo 'set terminal pngcairo size 1000,750 font ",14"'
  echo "set xlabel 'aperture diameter [arcsec]'"
  echo "set ylabel 'zero point [mag]'"
  echo "set key top right"
  echo "set output '$WORKDIR/aperture_zeropoint.png'"
  echo "plot '$WORKDIR/aperture_curve_B_GaiaB.txt' u 2:4 w lp pt 7 t 'B channel vs Gaia B', '$WORKDIR/aperture_curve_G_GaiaV.txt' u 2:4 w lp pt 7 t 'G channel vs Gaia V', '$WORKDIR/aperture_curve_R_GaiaR.txt' u 2:4 w lp pt 7 t 'R channel vs Gaia R'"
  echo "set ylabel 'detrended calibration scatter 1.48*MAD [mag]'"
  echo "set output '$WORKDIR/aperture_scatter.png'"
  echo "plot '$WORKDIR/aperture_curve_B_GaiaB.txt' u 2:6 w lp pt 7 t 'B channel vs Gaia B', '$WORKDIR/aperture_curve_G_GaiaV.txt' u 2:6 w lp pt 7 t 'G channel vs Gaia V', '$WORKDIR/aperture_curve_R_GaiaR.txt' u 2:6 w lp pt 7 t 'R channel vs Gaia R'"
  for BAND_DEFINITION in $BAND_DEFINITIONS ;do
   CHANNEL_NAME="${BAND_DEFINITION%%:*}"
   REST="${BAND_DEFINITION#*:}"
   BAND_NAME="${REST%%:*}"
   FITDATA_FILE="$WORKDIR/fitdata_${CHANNEL_NAME}_${BAND_NAME}.txt"
   if [ ! -s "$FITDATA_FILE" ];then
    continue
   fi
   eval ZP_VALUE=\$ZP_${CHANNEL_NAME}_${BAND_NAME}
   eval RB_VALUE=\$ROBUSTB_${CHANNEL_NAME}_${BAND_NAME}
   eval RC_VALUE=\$ROBUSTC_${CHANNEL_NAME}_${BAND_NAME}
   # Magnitude-magnitude plots are drawn square with the SAME range along
   # both axes (the larger of the two data spans, 10 percent padding), so
   # a slope-1 relation always runs at 45 degrees
   MAGMAG_RANGES=$(awk 'NR==1{xmin=$1;xmax=$1;ymin=$2;ymax=$2} {if($1<xmin)xmin=$1; if($1>xmax)xmax=$1; if($2<ymin)ymin=$2; if($2>ymax)ymax=$2} END{xs=xmax-xmin; ys=ymax-ymin; s=(xs>ys?xs:ys)*1.1; if(s<=0)s=1; xm=(xmin+xmax)/2; ym=(ymin+ymax)/2; printf "%.3f %.3f %.3f %.3f", xm-s/2, xm+s/2, ym-s/2, ym+s/2}' "$FITDATA_FILE")
   echo "set size square"
   echo "set xrange [$(echo "$MAGMAG_RANGES" | awk '{print $1":"$2}')]"
   echo "set yrange [$(echo "$MAGMAG_RANGES" | awk '{print $3":"$4}')]"
   echo "set xlabel 'instrumental ${CHANNEL_NAME}-channel magnitude (aperture diameter $FIXED_APERTURE pix)'"
   echo "set ylabel 'catalog $BAND_NAME magnitude'"
   echo "set output '$WORKDIR/calibration_${CHANNEL_NAME}_${BAND_NAME}.png'"
   echo "plot '$FITDATA_FILE' u 1:2 pt 7 ps 0.6 t 'calibration stars', x+$ZP_VALUE t 'zero-point fit (slope 1)', $RB_VALUE*x+$RC_VALUE t 'robust linear fit'"
   echo "set size nosquare"
   echo "set xrange [*:*]"
   echo "set yrange [*:*]"
   echo "set xlabel 'catalog B-V [mag]'"
   echo "set ylabel 'ZP-only calibration residual [mag]'"
   echo "set output '$WORKDIR/residual_color_${CHANNEL_NAME}_${BAND_NAME}.png'"
   echo "plot '$FITDATA_FILE' u (\$6<90?\$6:1/0):4 pt 7 ps 0.6 t '${CHANNEL_NAME} vs ${BAND_NAME}', 0 lc 'black' dt 2 notitle"
  done
 } > "$GNUPLOT_SCRIPT"
 if ! gnuplot "$GNUPLOT_SCRIPT" 2> "$WORKDIR/gnuplot.log" ;then
  # pngcairo may be unavailable in this gnuplot build - retry with the basic png terminal
  sed -i.bak 's/set terminal pngcairo/set terminal png/' "$GNUPLOT_SCRIPT" 2>/dev/null
  gnuplot "$GNUPLOT_SCRIPT" 2>> "$WORKDIR/gnuplot.log" || echo "WARNING: gnuplot failed, see $WORKDIR/gnuplot.log"
 fi
 ls "$WORKDIR"/*.png > /dev/null 2>&1 && echo "Plots: $WORKDIR/aperture_zeropoint.png $WORKDIR/aperture_scatter.png and the calibration_*/residual_color_* PNGs"
else
 echo "WARNING: gnuplot is not installed - skipping the diagnostic plots"
fi

#################################
# Target measurement
#################################
if [ "$TARGET_MODE" != "none" ];then
 echo " "
 echo "###############################################################"
 echo "### Target measurement ###"

 if [ "$TARGET_MODE" = "pixel" ];then
  # Convert the full-resolution mosaic pixel position to the superpixel grid:
  # superpixel 1 covers full-resolution pixels 1 and 2 (1-based FITS convention)
  TARGET_XY_BINNED=$(echo "$TARGET_PIXEL_X $TARGET_PIXEL_Y" | awk '{printf "%.2f %.2f", ($1+0.5)/2.0, ($2+0.5)/2.0}')
  TARGET_X_BINNED=$(echo "$TARGET_XY_BINNED" | awk '{print $1}')
  TARGET_Y_BINNED=$(echo "$TARGET_XY_BINNED" | awk '{print $2}')
  TARGET_RADEC=$("${VAST_PATH}"lib/bin/xy2sky -j -d "$WCS_IMAGE_G" "$TARGET_X_BINNED" "$TARGET_Y_BINNED" | head -n1)
  TARGET_RA_DEG=$(echo "$TARGET_RADEC" | awk '{print $1}')
  TARGET_DEC_DEG=$(echo "$TARGET_RADEC" | awk '{print $2}')
  echo "Original-mosaic pixel ($TARGET_PIXEL_X,$TARGET_PIXEL_Y) -> binned pixel ($TARGET_X_BINNED,$TARGET_Y_BINNED) -> $TARGET_RA_DEG $TARGET_DEC_DEG"
 else
  if echo "$TARGET_RA_INPUT" | grep -q ':' ;then
   HMS2DEG_OUTPUT=$("${VAST_PATH}"lib/hms2deg "$TARGET_RA_INPUT" "$TARGET_DEC_INPUT")
   TARGET_RA_DEG=$(echo "$HMS2DEG_OUTPUT" | head -n1 | awk '{print $1}')
   TARGET_DEC_DEG=$(echo "$HMS2DEG_OUTPUT" | tail -n1 | awk '{print $1}')
  else
   TARGET_RA_DEG="$TARGET_RA_INPUT"
   TARGET_DEC_DEG="$TARGET_DEC_INPUT"
  fi
 fi
 if [ -z "$TARGET_RA_DEG" ] || [ -z "$TARGET_DEC_DEG" ];then
  echo "ERROR interpreting the target position" >&2
  exit 1
 fi
 echo "Target position: $("${VAST_PATH}"lib/deg2hms "$TARGET_RA_DEG" "$TARGET_DEC_DEG") = $TARGET_RA_DEG $TARGET_DEC_DEG"

 JD_MID=$("${VAST_PATH}"util/get_image_date "$CHANNEL_IMAGE_G" 2>&1 | grep '  JD ' | awk '{print $2}')
 echo "JD(mid.exposure) $JD_MID"

 # Identity calibration to extract the instrumental magnitude from util/forced_photometry
 printf "0.0 0.0 0.0 1.0 0.0\n" > "$WORKDIR/param_identity.txt"
 TARGET_X_G=""
 TARGET_Y_G=""
 # util/forced_photometry reads SATUR_LEVEL from a default.sex in its working
 # directory; provide one so it agrees with the calibration-star measurements
 echo "SATUR_LEVEL     $SEESTAR_SATUR_LEVEL" > "$WORKDIR/default.sex"

 printf "%14s %10s %10s %14s %20s %18s %8s\n" "channel/band" "pixel_X" "pixel_Y" "instr_mag" "ZP-cal mag+-err" "slope-cal(diag)" "status"
 for BAND_DEFINITION in $BAND_DEFINITIONS ;do
  CHANNEL_NAME="${BAND_DEFINITION%%:*}"
  REST="${BAND_DEFINITION#*:}"
  BAND_NAME="${REST%%:*}"
  eval WCS_IMAGE=\$WCS_IMAGE_$CHANNEL_NAME
  eval ZP_VALUE=\$ZP_${CHANNEL_NAME}_${BAND_NAME}
  eval SCATTER_VALUE=\$SCATTER_${CHANNEL_NAME}_${BAND_NAME}
  eval RB_VALUE=\$ROBUSTB_${CHANNEL_NAME}_${BAND_NAME}
  eval RC_VALUE=\$ROBUSTC_${CHANNEL_NAME}_${BAND_NAME}
  if [ -z "$ZP_VALUE" ];then
   printf "%14s   no calibration for this band\n" "${CHANNEL_NAME}/${BAND_NAME}"
   continue
  fi

  SKY2XY_OUTPUT=$("${VAST_PATH}"lib/bin/sky2xy "$WCS_IMAGE" "$TARGET_RA_DEG" "$TARGET_DEC_DEG" 2>/dev/null | head -n1)
  if [ -z "$SKY2XY_OUTPUT" ] || echo "$SKY2XY_OUTPUT" | grep -q -e 'off image' -e 'offscale' ;then
   printf "%14s   the target is outside the %s channel image\n" "${CHANNEL_NAME}/${BAND_NAME}" "$CHANNEL_NAME"
   continue
  fi
  TARGET_X=$(echo "$SKY2XY_OUTPUT" | awk '{print $5}')
  TARGET_Y=$(echo "$SKY2XY_OUTPUT" | awk '{print $6}')

  # Forward round-trip check guarding against sky-to-pixel conversion problems
  ROUNDTRIP_RADEC=$("${VAST_PATH}"lib/bin/xy2sky -j -d "$WCS_IMAGE" "$TARGET_X" "$TARGET_Y" 2>/dev/null | head -n1)
  ROUNDTRIP_RA=$(echo "$ROUNDTRIP_RADEC" | awk '{print $1}')
  ROUNDTRIP_DEC=$(echo "$ROUNDTRIP_RADEC" | awk '{print $2}')
  ROUNDTRIP_SEP=$("${VAST_PATH}"lib/bin/skycoor -r "$ROUNDTRIP_RA" "$ROUNDTRIP_DEC" "$TARGET_RA_DEG" "$TARGET_DEC_DEG" 2>/dev/null)
  if [ -n "$ROUNDTRIP_SEP" ] && ! echo "$ROUNDTRIP_SEP" | awk '{exit !($1+0<30.0)}' ;then
   printf "%14s   sky-to-pixel round-trip check FAILED (%s arcsec)\n" "${CHANNEL_NAME}/${BAND_NAME}" "$ROUNDTRIP_SEP"
   continue
  fi

  FORCED_OUTPUT=$(cd "$WORKDIR" && "${VAST_PATH}"util/forced_photometry "$WCS_IMAGE" "$TARGET_X" "$TARGET_Y" "$FIXED_APERTURE" --calib "$WORKDIR/param_identity.txt" 2>/dev/null | tail -n1)
  INSTRUMENTAL_MAG=$(echo "$FORCED_OUTPUT" | awk '{print $1}')
  INSTRUMENTAL_ERR=$(echo "$FORCED_OUTPUT" | awk '{print $2}')
  MEASUREMENT_STATUS=$(echo "$FORCED_OUTPUT" | awk '{print $3}')
  if [ -z "$INSTRUMENTAL_MAG" ] || [ "$INSTRUMENTAL_MAG" = "99.0000" ];then
   printf "%14s   forced photometry failed (%s)\n" "${CHANNEL_NAME}/${BAND_NAME}" "$MEASUREMENT_STATUS"
   continue
  fi
  CALIBRATED_LINE=$(echo "$INSTRUMENTAL_MAG $INSTRUMENTAL_ERR $ZP_VALUE $SCATTER_VALUE" | awk '{
   zpmag= $1+$3
   toterr= sqrt($2*$2+$4*$4)
   printf "%.4f %.4f", zpmag, toterr
  }')
  ZP_CALIBRATED_MAG=$(echo "$CALIBRATED_LINE" | awk '{print $1}')
  TOTAL_ERR=$(echo "$CALIBRATED_LINE" | awk '{print $2}')
  if [ -n "$RB_VALUE" ] && [ -n "$RC_VALUE" ];then
   ROBUST_CALIBRATED_MAG=$(echo "$INSTRUMENTAL_MAG $RB_VALUE $RC_VALUE" | awk '{printf "%.4f", $2*$1+$3}')
  else
   ROBUST_CALIBRATED_MAG="n/a"
  fi
  printf "%14s %10.2f %10.2f %14.4f %12.4f +- %.4f %18s %8s\n" "${CHANNEL_NAME}/${BAND_NAME}" "$TARGET_X" "$TARGET_Y" "$INSTRUMENTAL_MAG" "$ZP_CALIBRATED_MAG" "$TOTAL_ERR" "$ROBUST_CALIBRATED_MAG" "$MEASUREMENT_STATUS"

  # Nearest SExtractor detection for reference (offset and flags)
  NEAREST_DETECTION=$(awk -v tx="$TARGET_X" -v ty="$TARGET_Y" -v naper="$NAPER" -v ai="$FIXED_APERTURE_INDEX" '
   { dx=$3-tx; dy=$4-ty; d2=dx*dx+dy*dy; if (best=="" || d2<best) {best=d2; bx=$3; by=$4; bf=$5; bm=$(6+ai); be=$(6+naper+ai)} }
   END { if (best!="") printf "%.2f %d %.4f %.4f", sqrt(best), bf, bm, be }' "$WORKDIR/det_$CHANNEL_NAME.sky")
  if [ -n "$NEAREST_DETECTION" ];then
   DETECTION_OFFSET=$(echo "$NEAREST_DETECTION" | awk '{print $1}')
   DETECTION_FLAGS=$(echo "$NEAREST_DETECTION" | awk '{print $2}')
   DETECTION_MAG=$(echo "$NEAREST_DETECTION" | awk '{print $3}')
   if echo "$DETECTION_OFFSET" | awk '{exit !($1<3.0)}' ;then
    if echo "$DETECTION_MAG" | awk '{exit !($1<90)}' ;then
     DETECTION_CALIBRATED=$(echo "$DETECTION_MAG $ZP_VALUE" | awk '{printf "%.4f", $1+$2}')
     echo "               nearest detection: offset $DETECTION_OFFSET pix, FLAGS=$DETECTION_FLAGS, ZP-cal mag $DETECTION_CALIBRATED"
    else
     echo "               nearest detection: offset $DETECTION_OFFSET pix, FLAGS=$DETECTION_FLAGS, fixed-aperture measurement invalid"
    fi
    if [ "$DETECTION_FLAGS" -ge 4 ];then
     echo "               WARNING: the detection FLAGS mark a saturated, truncated or corrupted aperture (FLAGS=$DETECTION_FLAGS)"
    fi
   else
    echo "               no SExtractor detection within 3 pix of the target position"
   fi
  fi

  # Measure the target through the whole aperture ladder, calibrating each
  # aperture with its own zero point. The per-aperture zero point acts as a
  # built-in aperture correction, so mixing apertures between targets keeps
  # the magnitudes on a consistent scale.
  LADDER_FILE="$WORKDIR/target_ladder_${CHANNEL_NAME}_${BAND_NAME}.txt"
  : > "$LADDER_FILE"
  CURVE_FILE="$WORKDIR/aperture_curve_${CHANNEL_NAME}_${BAND_NAME}.txt"
  echo "               aperture ladder (diameters; each aperture calibrated with its own zero point):"
  for APERTURE_DIAMETER in $APERTURE_LIST_SPACE ;do
   ZP_SCATTER_K=$(awk -v a="$APERTURE_DIAMETER" '$1==a {print $4" "$6; exit}' "$CURVE_FILE" 2>/dev/null)
   if [ -z "$ZP_SCATTER_K" ];then
    continue
   fi
   FORCED_K=$(cd "$WORKDIR" && "${VAST_PATH}"util/forced_photometry "$WCS_IMAGE" "$TARGET_X" "$TARGET_Y" "$APERTURE_DIAMETER" --calib "$WORKDIR/param_identity.txt" 2>/dev/null | tail -n1)
   INSTRUMENTAL_MAG_K=$(echo "$FORCED_K" | awk '{print $1}')
   INSTRUMENTAL_ERR_K=$(echo "$FORCED_K" | awk '{print $2}')
   if [ -z "$INSTRUMENTAL_MAG_K" ] || [ "$INSTRUMENTAL_MAG_K" = "99.0000" ] || echo "$INSTRUMENTAL_ERR_K" | awk '{exit !($1+0>=90)}' ;then
    echo "                 ap $APERTURE_DIAMETER pix: measurement invalid"
    continue
   fi
   echo "$APERTURE_DIAMETER $ZP_SCATTER_K $INSTRUMENTAL_MAG_K $INSTRUMENTAL_ERR_K" | \
    awk -v s="$SCALE_ARCSEC_PIX" '{printf "                 ap %4s pix (%5.1f arcsec): instr %9.4f +- %.4f   cal %8.4f +- %.4f\n", $1, $1*s, $4, $5, $4+$2, sqrt($5*$5+$3*$3)}'
   echo "$APERTURE_DIAMETER $ZP_SCATTER_K $INSTRUMENTAL_MAG_K $INSTRUMENTAL_ERR_K" >> "$LADDER_FILE"
  done
  # ladder file columns: 1 aperture_diameter 2 ZP 3 detrended_calib_scatter 4 instmag 5 instmagerr

  # remember the G-channel pixel position for the aperture selection below
  if [ "$CHANNEL_NAME" = "G" ];then
   TARGET_X_G="$TARGET_X"
   TARGET_Y_G="$TARGET_Y"
  fi
 done

 # Aperture selection, made ONCE from the G channel and applied to ALL bands
 # so that color indices are formed from measurements through the same
 # aperture. Keep the fixed (small) aperture unless the target shows a
 # statistically significant flux excess in the large aperture of the G
 # channel (bright-star wings spilling out of the small one); the large
 # aperture is vetoed when another G detection sits within it.
 CHOSEN_APERTURE="$FIXED_APERTURE"
 SELECTION_REASON="no significant wing excess in G, fixed aperture kept"
 G_LADDER_FILE="$WORKDIR/target_ladder_G_GaiaV.txt"
 if [ ! -s "$G_LADDER_FILE" ] || [ -z "$TARGET_X_G" ];then
  SELECTION_REASON="no G-channel measurement available, fixed aperture used"
 elif [ -n "$BRIGHT_APERTURE" ];then
  FIXED_LADDER_ROW=$(awk -v a="$FIXED_APERTURE" '$1==a {print; exit}' "$G_LADDER_FILE")
  BRIGHT_LADDER_ROW=$(awk -v a="$BRIGHT_APERTURE" '$1==a {print; exit}' "$G_LADDER_FILE")
  if [ -n "$FIXED_LADDER_ROW" ] && [ -n "$BRIGHT_LADDER_ROW" ];then
   NEIGHBOR_VETO_RADIUS_PIX=$(echo "$BRIGHT_APERTURE" | awk '{printf "%.2f", 0.5*$1+1.0}')
   N_NEIGHBOR_DETECTIONS=$(awk -v tx="$TARGET_X_G" -v ty="$TARGET_Y_G" -v r="$NEIGHBOR_VETO_RADIUS_PIX" '
    {dx=$3-tx; dy=$4-ty; d=sqrt(dx*dx+dy*dy); if (d<r && d>1.5) n++} END{print n+0}' "$WORKDIR/det_G.sky")
   if [ "$N_NEIGHBOR_DETECTIONS" -gt 0 ];then
    SELECTION_REASON="large aperture vetoed by $N_NEIGHBOR_DETECTIONS G-channel neighbor detection(s) within $NEIGHBOR_VETO_RADIUS_PIX pix of the target"
   else
    # wing excess = (calibrated mag in the fixed aperture) - (calibrated mag
    # in the large aperture); a well-behaved star follows the mean curve of
    # growth already absorbed in the per-aperture zero points, so the excess
    # is consistent with zero. Require >0.05 mag at >2 sigma (instrumental
    # errors only) to switch to the large aperture.
    WING_TEST=$(echo "$FIXED_LADDER_ROW $BRIGHT_LADDER_ROW" | awk '{
     excess= ($4+$2)-($9+$7)
     sigma= sqrt($5*$5+$10*$10)
     if (sigma<0.0001) sigma=0.0001
     if (excess>0.05 && excess>2.0*sigma) verdict="bright"; else verdict="fixed"
     printf "%s %+.4f %.1f", verdict, excess, excess/sigma
    }')
    WING_VERDICT=$(echo "$WING_TEST" | awk '{print $1}')
    WING_EXCESS=$(echo "$WING_TEST" | awk '{print $2}')
    WING_SIGMA=$(echo "$WING_TEST" | awk '{print $3}')
    if [ "$WING_VERDICT" = "bright" ];then
     CHOSEN_APERTURE="$BRIGHT_APERTURE"
     SELECTION_REASON="wing excess $WING_EXCESS mag (${WING_SIGMA} sigma) in G, large aperture used"
    else
     SELECTION_REASON="wing excess $WING_EXCESS mag (${WING_SIGMA} sigma) in G not significant, fixed aperture kept"
    fi
   fi
  fi
 fi
 echo "Aperture selection from the G channel: diameter $CHOSEN_APERTURE pix ($SELECTION_REASON)"
 echo "The same aperture diameter is used for all bands so that color indices are formed consistently."
 for BAND_DEFINITION in $BAND_DEFINITIONS ;do
  CHANNEL_NAME="${BAND_DEFINITION%%:*}"
  REST="${BAND_DEFINITION#*:}"
  BAND_NAME="${REST%%:*}"
  LADDER_FILE="$WORKDIR/target_ladder_${CHANNEL_NAME}_${BAND_NAME}.txt"
  if [ ! -s "$LADDER_FILE" ];then
   continue
  fi
  BAND_NOTE=""
  CHOSEN_LADDER_ROW=$(awk -v a="$CHOSEN_APERTURE" '$1==a {print; exit}' "$LADDER_FILE")
  if [ -z "$CHOSEN_LADDER_ROW" ];then
   # the chosen-aperture measurement failed in this band: fall back to the
   # smallest combined error among its valid ladder rows
   CHOSEN_LADDER_ROW=$(awk 'BEGIN{best=1e30} {e=sqrt($5*$5+$3*$3); if (e<best) {best=e; row=$0}} END{print row}' "$LADDER_FILE")
   BAND_NOTE=" [chosen aperture invalid in this band, smallest-error ladder entry used instead]"
  fi
  if [ -n "$CHOSEN_LADDER_ROW" ];then
   echo "$CHOSEN_LADDER_ROW" | awk -v band="${CHANNEL_NAME}/${BAND_NAME}" -v note="$BAND_NOTE" \
    '{printf "RECOMMENDED %6s = %8.4f +- %.4f (aperture diameter %s pix)%s\n", band, $4+$2, sqrt($5*$5+$3*$3), $1, note}'
  fi
 done
 echo "Note: the RECOMMENDED values use one aperture diameter for all bands, chosen from the G channel: the large"
 echo "      aperture is used only when the target shows a significant wing flux excess in G and no neighbor"
 echo "      detection falls inside it; each aperture is calibrated with its own zero point per band, so"
 echo "      switching apertures between targets keeps the magnitudes on a consistent scale."
 echo "Note: the slope-cal column is a diagnostic only: slope != 1 usually reflects bright-end aperture"
 echo "      losses (star wings) and faint-end selection bias rather than detector nonlinearity"
 echo "      (verified against APASS, Tycho-2 and Gaia synthetic V on the 2026-08-28 test frame)."
 echo "Note: the quoted error combines the instrumental error and the DETRENDED field calibration scatter;"
 echo "      the magnitude-dependent calibration trend (trend_pp in the aperture tables, mostly bright-star wing"
 echo "      losses) and a catalog zero-point systematic (~0.02-0.03 mag) are not included in the error bar."
 echo "###############################################################"
fi

echo " "
echo "All data products are in $WORKDIR"
echo "Done."
