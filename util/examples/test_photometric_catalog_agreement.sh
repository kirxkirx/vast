#!/usr/bin/env bash
#
# Compare the photometry util/solve_plate_with_UCAC5 gets from APASS DR9 with the photometry it
# gets from Gaia DR3 synthetic photometry for the same stars of the same image. The two
# catalogs were measured independently, so an error in a transformation that turns catalog
# magnitudes into the bands VaST uses shows up as an offset between them. The sign error of the
# R-I term of Jester et al. (2005), which made every APASS Cousins I magnitude 0.42 mag too faint
# from 2019 to 2026-11-23, gives APASS Ic - Gaia Ic = +0.35 mag for the image used here; with
# the correct sign the difference is -0.07 mag. The tests had not
# noticed the error because their expected magnitudes had been taken from VaST itself.
#
# Both catalogs are fetched live (lib/photometric_field_catalog.sh: APASS from the ESA Gaia
# Archive or SkyMapper, Gaia from ESA or ARI; the APASS list query via VizieR is the last APASS
# source), so this test needs the internet. When a catalog cannot be had, the test is reported
# as not performed, not as failed.
#
# The plate solver runs twice on the plate-solved NMW archive image
# wcs_fd_Per3_2011-10-31_001.fts of the VaST test data: with APASS (the default) and with
# VAST_PHOTOMETRIC_CATALOG=gaia. For the stars that have a magnitude in a band from both
# catalogs, the median of APASS minus Gaia has to stay within these limits:
#   B 0.10   V 0.10   Rc 0.15   Ic 0.15   g 0.10   r 0.10   i 0.10
# APASS g', r', i' are compared with the SDSS g, r, i of Gaia; Rc and Ic come from APASS V, r'
# and i' through Jester et al. (2005), and directly from Gaia. The two catalogs do not agree
# exactly, and how well depends on the field: the medians were B +0.001, V -0.034, Rc -0.063,
# Ic -0.067, g -0.002, r -0.027, i -0.038 for this image (3778 stars, the same offsets from
# V = 10 to 13.5), and B -0.015, V -0.010, Rc -0.044, Ic -0.053 for 26,420 stars of the TESS
# field, both on 2026-11-23. The limits leave room for that and still catch an error of about
# 0.2 mag in a transformation. At least 100 stars per band are needed. Both catalogs also have
# to follow the colours of real stars (util/examples/check_photometric_catalog_colors.sh).
#
# Usage: util/examples/test_photometric_catalog_agreement.sh
# The script works in the VaST directory it belongs to. The image is expected in
# ../individual_images_test (next to the VaST directory) and is downloaded if it is not there.
# It prints "FAILED: CODE description" for every failed check and "NOT_PERFORMED: CODE reason"
# if a catalog could not be had; it exits with code 1 if a check failed and 0 otherwise. At the
# end it puts back default.sex of the VaST directory and removes the files the plate solver made
# there (wcs_fd_Per3_2011-10-31_001.fts* and the image_pid*.cat.aperture and
# image_pid*.cat.sex_log files of its SExtractor runs).
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# A manual TELESCOP override would change how the image is handled (see util/examples/test_vast.sh)
unset TELESCOP
# With this setting the plate solver does not ask for photometry at all
unset FORCED_PHOTOMETRY_CALIBRATION_METHOD
# The settings this test sets itself
unset VAST_PHOTOMETRIC_CATALOG VAST_FIELD_CATALOG_PROVIDERS VAST_FIELD_CATALOG_CACHE_DIR

# Work in the VaST directory this script belongs to
cd "$(dirname "$0")/../.." || exit 1

FAILED_CODES=""
fail() {
 FAILED_CODES="$FAILED_CODES $1"
 echo "FAILED: $1 $2"
}
not_performed() {
 echo "NOT_PERFORMED: NOT_PERFORMED_PHOTCATAGREE_$1 $2"
}

SOLVER_IMAGE_NAME="wcs_fd_Per3_2011-10-31_001.fts"
SOLVER_IMAGE_DIR="../individual_images_test"
SOLVER_CATALOG="$SOLVER_IMAGE_NAME.wcscat.ucac5"
MIN_STARS_PER_BAND=100

if [ ! -x util/solve_plate_with_UCAC5 ] || [ ! -f default.sex.NMW_mass_processing ] || [ ! -x util/examples/check_photometric_catalog_colors.sh ];then
 fail PHOTCATAGREE_TOOL_NOT_FOUND "util/solve_plate_with_UCAC5 is not built (run make in the VaST directory) or a script is missing"
 exit 1
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vast_photometric_catalog_agreement_test.XXXXXX" 2>/dev/null)
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ];then
 fail PHOTCATAGREE000 "cannot create a work directory"
 exit 1
fi

# Get the image if it is not there yet: the GitHub release asset first (unless
# VAST_TEST_DATA_NO_GITHUB=yes), then the mirrors, as download_test_data_file() in
# util/examples/test_vast.sh does
if [ ! -s "$SOLVER_IMAGE_DIR/$SOLVER_IMAGE_NAME" ];then
 echo "Downloading the test image $SOLVER_IMAGE_NAME"
 TEST_DATA_URLS="http://tau.kirx.net/vast_test_data/$SOLVER_IMAGE_NAME.bz2 http://scan.sai.msu.ru/~kirx/pub/$SOLVER_IMAGE_NAME.bz2"
 if [ "$VAST_TEST_DATA_NO_GITHUB" != "yes" ];then
  TEST_DATA_URLS="https://github.com/kirxkirx/vast/releases/download/test-data-v1/$SOLVER_IMAGE_NAME.bz2 $TEST_DATA_URLS"
 fi
 (
  mkdir -p "$SOLVER_IMAGE_DIR" && cd "$SOLVER_IMAGE_DIR" || exit 1
  for URL in $TEST_DATA_URLS ;do
   rm -f "$SOLVER_IMAGE_NAME.bz2"
   if curl -L --fail --silent --show-error --connect-timeout 30 --speed-limit 1024 --speed-time 60 -o "$SOLVER_IMAGE_NAME.bz2" "$URL" && bunzip2 -t "$SOLVER_IMAGE_NAME.bz2" 2>/dev/null ;then
    bunzip2 "$SOLVER_IMAGE_NAME.bz2"
    break
   fi
  done
  rm -f "$SOLVER_IMAGE_NAME.bz2"
 )
fi
if [ ! -s "$SOLVER_IMAGE_DIR/$SOLVER_IMAGE_NAME" ];then
 rm -rf "$WORK_DIR"
 not_performed nodata "the test image $SOLVER_IMAGE_DIR/$SOLVER_IMAGE_NAME is not available"
 exit 0
fi

if [ -f default.sex ];then
 cp -p default.sex "$WORK_DIR/default.sex_of_the_vast_directory"
fi
# The SExtractor runs of the plate solver leave image_pid<PID>.cat.aperture and
# image_pid<PID>.cat.sex_log files behind: remember the ones that are here already
PID_FILES_BEFORE_THE_TEST=""
for PID_FILE in image_pid*.cat.aperture image_pid*.cat.sex_log ;do
 if [ -f "$PID_FILE" ];then
  PID_FILES_BEFORE_THE_TEST="$PID_FILES_BEFORE_THE_TEST $PID_FILE"
 fi
done
# clean_up() is called by the EXIT trap below
# shellcheck disable=SC2329
clean_up() {
 if [ -f "$WORK_DIR/default.sex_of_the_vast_directory" ] && ! cmp -s "$WORK_DIR/default.sex_of_the_vast_directory" default.sex ;then
  cp -p "$WORK_DIR/default.sex_of_the_vast_directory" default.sex
 fi
 rm -f "$SOLVER_IMAGE_NAME" "$SOLVER_IMAGE_NAME".*
 for PID_FILE in image_pid*.cat.aperture image_pid*.cat.sex_log ;do
  if [ -f "$PID_FILE" ];then
   case " $PID_FILES_BEFORE_THE_TEST " in
    *" $PID_FILE "*) ;;
    *) rm -f "$PID_FILE" ;;
   esac
  fi
 done
 if [ "$PHOTCATAGREE_KEEP_WORK_DIR" != "yes" ];then
  rm -rf "$WORK_DIR"
 else
  echo "The work directory $WORK_DIR is kept (PHOTCATAGREE_KEEP_WORK_DIR=yes)"
 fi
}
trap clean_up EXIT
trap 'exit 1' HUP INT TERM

rm -f "$SOLVER_IMAGE_NAME" "$SOLVER_IMAGE_NAME".*
cp default.sex.NMW_mass_processing default.sex

# Run the plate solver on the test image with a fresh cache of field catalogs, so that both
# catalogs are really fetched
# $1 - the name of the run: apass or gaia; the log goes to $WORK_DIR/solver_<name>.log and the
# output catalog to $WORK_DIR/catalog_<name>.txt
run_solver() {
 rm -f "$SOLVER_CATALOG"
 if [ "$1" = "gaia" ];then
  VAST_PHOTOMETRIC_CATALOG=gaia VAST_FIELD_CATALOG_CACHE_DIR="$WORK_DIR/cache_$1" util/solve_plate_with_UCAC5 "$SOLVER_IMAGE_DIR/$SOLVER_IMAGE_NAME" > "$WORK_DIR/solver_$1.log" 2>&1
 else
  VAST_FIELD_CATALOG_CACHE_DIR="$WORK_DIR/cache_$1" util/solve_plate_with_UCAC5 "$SOLVER_IMAGE_DIR/$SOLVER_IMAGE_NAME" > "$WORK_DIR/solver_$1.log" 2>&1
 fi
 SOLVER_EXIT_CODE=$?
 cp "$SOLVER_CATALOG" "$WORK_DIR/catalog_$1.txt" 2>/dev/null
}
show_solver_run() {
 echo " what the plate solver said about the photometric catalogs in the $1 run (exit code $SOLVER_EXIT_CODE):"
 grep -e 'APASS' -e 'Gaia DR3' -e 'Pan-STARRS' -e 'Positional cut' -e 'Fetched' -e 'Using the' -e 'WARNING: ' "$WORK_DIR/solver_$1.log" 2>/dev/null | grep -v '^export ' | head -n 12 | sed 's/^/  /'
}

NOT_PERFORMED_REASON=""
echo "Plate solver run with APASS"
run_solver apass
if [ $SOLVER_EXIT_CODE -ne 0 ] || [ ! -s "$WORK_DIR/catalog_apass.txt" ];then
 fail PHOTCATAGREE001 "the plate solver did not write $SOLVER_CATALOG (exit code $SOLVER_EXIT_CODE)"
 show_solver_run apass
 exit 1
fi
# APASS from a field catalog, or from the VizieR list query; not Pan-STARRS1
APASS_SOURCE=$(grep -e '^Using [0-9]* stars matched with APASS DR9 (' "$WORK_DIR/solver_apass.log" | tail -n 1)
if [ -z "$APASS_SOURCE" ] && ! grep -q 'ERROR running search_APASS()' "$WORK_DIR/solver_apass.log" && grep -q '^Matched [0-9]* stars with APASS\.' "$WORK_DIR/solver_apass.log" ;then
 APASS_SOURCE="the APASS list query via VizieR"
fi
if [ -z "$APASS_SOURCE" ];then
 NOT_PERFORMED_REASON="noapass"
 not_performed noapass "the plate solver could not get APASS (no service answered?)"
 show_solver_run apass
fi

if [ -z "$NOT_PERFORMED_REASON" ];then
 echo "Plate solver run with Gaia DR3 synthetic photometry"
 run_solver gaia
 if [ $SOLVER_EXIT_CODE -ne 0 ] || [ ! -s "$WORK_DIR/catalog_gaia.txt" ];then
  fail PHOTCATAGREE002 "the plate solver did not write $SOLVER_CATALOG (exit code $SOLVER_EXIT_CODE)"
  show_solver_run gaia
  exit 1
 fi
 GAIA_SOURCE=$(grep -e '^Using [0-9]* stars matched with Gaia DR3 synthetic photometry (' "$WORK_DIR/solver_gaia.log" | tail -n 1)
 if [ -z "$GAIA_SOURCE" ];then
  NOT_PERFORMED_REASON="nogaia"
  not_performed nogaia "the plate solver could not get Gaia DR3 synthetic photometry (no service answered?)"
  show_solver_run gaia
 fi
fi

if [ -z "$NOT_PERFORMED_REASON" ];then
 echo " APASS: $APASS_SOURCE"
 echo " Gaia:  $GAIA_SOURCE"
 # Both runs have to describe the same image stars: the output catalogs list every detected
 # star in the same order, with the same numbers
 if [ "$(awk '{print $1}' "$WORK_DIR/catalog_apass.txt" | cksum)" != "$(awk '{print $1}' "$WORK_DIR/catalog_gaia.txt" | cksum)" ];then
  fail PHOTCATAGREE003 "the two runs did not detect the same stars"
 fi
 # The differences APASS - Gaia for each band: "band difference" lines
 awk '
  BEGIN {
   nb = split("B V Rc Ic g r i", name, " ")
   split("13 15 21 23 25 17 19", column, " ")
  }
  FNR == NR { for (b = 1; b <= nb; b++) apass[$1, b] = $(column[b]) + 0 ; next }
  {
   for (b = 1; b <= nb; b++) {
    a = apass[$1, b] ; g = $(column[b]) + 0
    if (a != 0 && g != 0) printf "%s %.4f\n", name[b], a - g
   }
  }' "$WORK_DIR/catalog_apass.txt" "$WORK_DIR/catalog_gaia.txt" > "$WORK_DIR/differences.txt"
 # The median of the numbers on stdin (sorted by sort -n, so any number of them)
 median_of_input() {
  sort -n | awk '{ x[NR] = $1 } END { if (NR == 0) print "none" ; else if (NR % 2) printf "%.4f\n", x[(NR + 1) / 2] ; else printf "%.4f\n", (x[NR / 2] + x[NR / 2 + 1]) / 2 }'
 }
 # band, stars, median, robust sigma (1.4826 MAD), limit for the median
 COMPARISON=""
 for BAND_AND_LIMIT in B:0.10 V:0.10 Rc:0.15 Ic:0.15 g:0.10 r:0.10 i:0.10 ;do
  BAND="${BAND_AND_LIMIT%%:*}"
  LIMIT="${BAND_AND_LIMIT#*:}"
  N_STARS=$(awk -v band="$BAND" '$1 == band' "$WORK_DIR/differences.txt" | wc -l | awk '{print $1}')
  if [ "$N_STARS" -lt "$MIN_STARS_PER_BAND" ];then
   COMPARISON="$COMPARISON$BAND $N_STARS too_few none $LIMIT
"
   continue
  fi
  MEDIAN=$(awk -v band="$BAND" '$1 == band { print $2 }' "$WORK_DIR/differences.txt" | median_of_input)
  SIGMA=$(awk -v band="$BAND" -v m="$MEDIAN" '$1 == band { d = $2 - m ; if (d < 0) d = -d ; print d }' "$WORK_DIR/differences.txt" | median_of_input | awk '{ printf "%.3f", 1.4826 * $1 }')
  COMPARISON="$COMPARISON$(echo "$BAND $N_STARS $MEDIAN $SIGMA $LIMIT" | awk '{ printf "%s %d %+.3f %s %s", $1, $2, $3, $4, $5 }')
"
 done
 COMPARISON=$(printf '%s' "$COMPARISON")
 echo " APASS minus Gaia, the same image stars (band, stars, median, robust sigma, limit for the median):"
 echo "$COMPARISON" | awk '{ print "  " $0 }'
 while read -r BAND N_STARS MEDIAN SIGMA LIMIT ;do
  if [ "$MEDIAN" = "too_few" ];then
   fail "PHOTCATAGREE010_$BAND" "only $N_STARS stars have a $BAND magnitude from both catalogs, at least $MIN_STARS_PER_BAND are needed"
  elif ! echo "$MEDIAN $LIMIT" | awk '{ exit !($1 + 0 <= $2 + 0 && $1 + 0 >= -$2) }' ;then
   fail "PHOTCATAGREE011_$BAND" "the median of APASS minus Gaia in $BAND is $MEDIAN mag for $N_STARS stars (robust sigma $SIGMA), the limit is $LIMIT"
  fi
 done <<< "$COMPARISON"
 # Both catalogs against the colours of real stars
 for CATALOG_NAME in apass gaia ;do
  COLORS=$(util/examples/check_photometric_catalog_colors.sh "$WORK_DIR/catalog_$CATALOG_NAME.txt")
  COLORS_EXIT_CODE=$?
  echo " ${COLORS#"$WORK_DIR"/}"
  if [ $COLORS_EXIT_CODE -ne 0 ];then
   fail "PHOTCATAGREE020_$CATALOG_NAME" "the $CATALOG_NAME catalog does not follow the colours of real stars: ${COLORS#"$WORK_DIR"/}"
  fi
 done
fi

if [ -n "$FAILED_CODES" ];then
 echo "Failed checks:$FAILED_CODES"
 exit 1
fi
if [ -z "$NOT_PERFORMED_REASON" ];then
 echo "APASS and Gaia DR3 synthetic photometry agree"
else
 echo "The comparison of APASS and Gaia was not performed ($NOT_PERFORMED_REASON)"
fi
exit 0
