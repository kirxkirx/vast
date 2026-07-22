#!/usr/bin/env bash
#
# This script will try to calibrate the current field using V magnitudes (transformed to Johnson, not vt)
# of Tycho-2 stars in the field. This is useful mostly for wide-field images with blue-sensitive CCD chips.
#
#########################################################
# SET APPROXIMAE FIELD OF VIEW IN ARCMINUTES HERE
#FIELD_OF_VIEW=120
# NOT NEEDED ANYMORE
#########################################################

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

function download_tycho2_from_scan {
 # Download the Tycho-2 catalog files. The file set is fixed (a frozen
 # catalog), so no directory listing is needed: the known file names are
 # tried against a chain of mirrors (same logic as in
 # lib/update_offline_catalogs.sh). A file that is already present and
 # passes the gzip integrity test is never re-downloaded; a failed transfer
 # keeps its partial file so '--continue-at -' resumes it from the next
 # mirror, while a complete-but-corrupt file is discarded for a clean
 # re-download. cdsarc.u-strasbg.fr redirects to cdsarc.cds.unistra.fr,
 # so the latter is used directly as the authoritative upstream fallback.
 local mirror_base_url
 local item
 local n_missing
 local tycho2_gz_files="tyc2.dat.00.gz tyc2.dat.01.gz tyc2.dat.02.gz tyc2.dat.03.gz tyc2.dat.04.gz tyc2.dat.05.gz tyc2.dat.06.gz tyc2.dat.07.gz tyc2.dat.08.gz tyc2.dat.09.gz tyc2.dat.10.gz tyc2.dat.11.gz tyc2.dat.12.gz tyc2.dat.13.gz tyc2.dat.14.gz tyc2.dat.15.gz tyc2.dat.16.gz tyc2.dat.17.gz tyc2.dat.18.gz tyc2.dat.19.gz"
 if command -v curl >/dev/null 2>&1 ;then
  for mirror_base_url in "http://scan.sai.msu.ru/~kirx/data/tycho2/" "http://tau.kirx.net/vast_test_data/tycho2/" "https://cdsarc.cds.unistra.fr/ftp/I/259/" ;do
   echo "Trying Tycho-2 mirror $mirror_base_url" >&2
   # ReadMe is kept for provenance, but its absence is not fatal
   if [ ! -s ReadMe ];then
    curl $VAST_CURL_PROXY --silent --max-time 60 --insecure -o ReadMe "${mirror_base_url}ReadMe" 2>/dev/null
   fi
   n_missing=0
   for item in $tycho2_gz_files ;do
    # keep a complete, integrity-checked file from a previous mirror or run
    if [ -s "$item" ] && gzip -t "$item" 2>/dev/null ;then
     continue
    fi
    echo "Downloading: $item" >&2
    curl $VAST_CURL_PROXY --silent --show-error --max-time 600 \
         --insecure --continue-at - --retry 5 --retry-delay 2 \
         -o "$item" "${mirror_base_url}${item}"
    if [ $? -eq 0 ];then
     if gzip -t "$item" 2>/dev/null ;then
      continue
     fi
     echo "Warning: $item fails the gzip integrity test - discarding it" >&2
     rm -f "$item"
    fi
    # transfer failed: keep the partial file for resuming from the next mirror
    n_missing=$((n_missing+1))
   done
   if [ "$n_missing" -eq 0 ];then
    echo "All Tycho-2 files downloaded successfully" >&2
    return 0
   fi
   echo "Warning: $n_missing Tycho-2 file(s) still missing after trying $mirror_base_url" >&2
  done
  echo "curl-based download incomplete, falling back to wget" >&2
 fi
 if command -v wget >/dev/null 2>&1 ;then
  wget -nH --cut-dirs=4 --no-parent -r -l0 -c -A 'ReadMe,*.gz,robots.txt' "http://scan.sai.msu.ru/~kirx/data/tycho2/"
  return $?
 fi
 echo "ERROR: neither curl nor wget is available to download Tycho-2" >&2
 return 1
}

function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=$(readlink -f "$1" 2>/dev/null)
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=$(greadlink -f "$1" 2>/dev/null)
   if [ $? -ne 0 ];then
    REALPATH=$(realpath "$1" 2>/dev/null)
    if [ $? -ne 0 ];then
     REALPATH=$(grealpath "$1" 2>/dev/null)
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")" || return
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || return
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

##### Check if a local copy of Tycho-2 is available and if its usable?
VASTDIR=$(vastrealpath "$PWD")
TYCHO_PATH=lib/catalogs/tycho2

# Check if there is a symbolic link, but it is broken
if [ -L "$TYCHO_PATH/tyc2.dat.00" ];then
 # test if symlink is broken (by seeing if it links to an existing file)
 if [ ! -e "$TYCHO_PATH/tyc2.dat.00" ] ; then
  # code if the symlink is broken
  echo "The symbolic link to Tycho-2 is broken!"
  rm -rf "$TYCHO_PATH"
 fi
fi

# Check if there is a copy of Tycho-2
if [ ! -f "$TYCHO_PATH/tyc2.dat.00" ];then
 echo "No local copy of Tycho-2 found (no $TYCHO_PATH/tyc2.dat.00)"
 # Check if there is a local copy of Tycho-2 in the top directory
 if [ -s ../tycho2/tyc2.dat.19 ];then
  echo "Found nonempty ../tycho2/tyc2.dat.19, creating symlink to $TYCHO_PATH"
  #ln -s `readlink -f ../tycho2` $TYCHO_PATH
  ln -s "$(vastrealpath ../tycho2)" "$TYCHO_PATH"
 else
  #
  echo "Tycho-2 catalog was not found at $TYCHO_PATH"
  echo "Would you like to download it now (it's big, ~160M)? (y/n)"
  read -r ANSWER
  if [ "$ANSWER" = "n" ];then
   echo "Well, maybe next time..."
   exit 1
  else
   if [ ! -d "$TYCHO_PATH" ];then
    mkdir "$TYCHO_PATH"
   fi
   cd "$TYCHO_PATH" || exit 1
   # remove any incomplete copy of Tycho-2
   for i in tyc2.dat.* ;do
    if [ -f "$i" ];then
     rm -f "$i"
    fi
   done
   #
   #wget -nH --cut-dirs=4 --no-parent -r -l0 -c -R 'guide.*,*.gif' "ftp://cdsarc.u-strasbg.fr/pub/cats/I/259/"
   download_tycho2_from_scan
   echo "Download complete. Unpacking..."
   for i in tyc2.dat.*gz ;do
    # handle a very special case: `basename $i .gz` is a broken symlink
    if [ -L "$(basename "$i" .gz)" ];then
     # if this is a symlink
     if [ ! -e "$(basename "$i" .gz)" ];then
      # if it is broken
      rm -f "$(basename "$i" .gz)"
      # remove that symlink
     fi
    fi
    #
    gunzip "$i"
   done
   cd "$VASTDIR" || exit 1
  fi
 fi # if [ -s ../tycho2/tyc2.dat.19 ];then 
else
 echo "Tycho-2 catalog is found at $TYCHO_PATH"
 # Make sure the catalog is fully downloaded and unpacked
 if [ ! -f "$TYCHO_PATH/tyc2.dat.19" ] ;then
  echo "WARNING! One of the catalog files was not found! Will attempt to re-download the catalog."
  cd "$TYCHO_PATH" || exit 1
  # remove any incomplete copy of Tycho-2
  for i in tyc2.dat.* ;do
   if [ -f "$i" ];then
    rm -f "$i"
   fi
  done
  #
  #wget -nH --cut-dirs=4 --no-parent -r -l0 -c -R 'guide.*,*.gif' "ftp://cdsarc.u-strasbg.fr/pub/cats/I/259/"
  download_tycho2_from_scan
  echo "Download complete. Unpacking..."
  for i in tyc2.dat.*gz ;do
   # handle a very special case: `basename $i .gz` is a broken symlink
   if [ -L "$(basename "$i" .gz)" ];then
    # if this is a symlink
    if [ ! -e "$(basename "$i" .gz)" ];then
     # if it is broken
     rm -f "$(basename "$i" .gz)"
     # remove that symlink
    fi
   fi
   #
   gunzip "$i"
  done
  cd "$VASTDIR" || exit 1
 fi
fi

if [ ! -s lib/catalogs/list_of_bright_stars_from_tycho2.txt ];then
 # Create a list of stars brighter than mag 9.1 for filtering transient candidates
 # also in lib/update_offline_catalogs.sh !!!
 lib/catalogs/create_tycho2_list_of_bright_stars_to_exclude_from_transient_search 9.1
fi

echo "Tycho-2 catalog and the derived bright star exclusion list are ready"

# WCS-calibrate the reference image if it has not been done
REFERENCE_IMAGE=$(grep "Ref.  image:" vast_summary.log | awk '{print $6}')
TEST_SUBSTRING=$(basename "$REFERENCE_IMAGE")
TEST_SUBSTRING="${TEST_SUBSTRING:0:4}"
if [ "$TEST_SUBSTRING" = "wcs_" ];then
 cp "$REFERENCE_IMAGE" .
 WCS_CALIBRATED_REFERENCE_IMAGE=$(basename "$REFERENCE_IMAGE")
else
 WCS_CALIBRATED_REFERENCE_IMAGE=wcs_$(basename "$REFERENCE_IMAGE")
fi
SEXTRACTOR_CATALOG_NAME="$WCS_CALIBRATED_REFERENCE_IMAGE".wcscat
echo "Checking for the presence of non-empty $WCS_CALIBRATED_REFERENCE_IMAGE and $SEXTRACTOR_CATALOG_NAME "
if [ ! -s "$WCS_CALIBRATED_REFERENCE_IMAGE" ] || [ ! -s "$SEXTRACTOR_CATALOG_NAME" ] ;then
 util/wcs_image_calibration.sh "$REFERENCE_IMAGE"
 if [ $? -ne 0 ];then
  echo "ERROR in $0 : cannot plate-solve the reference image $REFERENCE_IMAGE"
  exit 1
 fi
else
 echo "Found non-empty $WCS_CALIBRATED_REFERENCE_IMAGE and $SEXTRACTOR_CATALOG_NAME"
fi # if [ ! -s "$WCS_CALIBRATED_REFERENCE_IMAGE" ] || [ ! -s "$SEXTRACTOR_CATALOG_NAME" ] ;then


# Final check for $WCS_CALIBRATED_REFERENCE_IMAGE and $SEXTRACTOR_CATALOG_NAME
if [ ! -s "$WCS_CALIBRATED_REFERENCE_IMAGE" ];then
 echo "ERROR in $0 : cannot find the WCS-calibrated image $WCS_CALIBRATED_REFERENCE_IMAGE which was supposed to be created by util/wcs_image_calibration.sh"
 exit 1
fi
if [ ! -s "$SEXTRACTOR_CATALOG_NAME" ];then
 echo "ERROR in $0 : cannot find the catalog file $SEXTRACTOR_CATALOG_NAME which was supposed to be created by util/wcs_image_calibration.sh"
 exit 1
fi

# If we are still here
echo "The reference image ($WCS_CALIBRATED_REFERENCE_IMAGE) and catalog ($SEXTRACTOR_CATALOG_NAME) found"

cp -v "$SEXTRACTOR_CATALOG_NAME" wcsmag.cat

#valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes lib/catalogs/read_tycho2
lib/catalogs/read_tycho2
if [ $? -ne 0 ];then
 echo "ERROR running lib/catalogs/read_tycho2"
 exit 1
fi

# Calibration-star yield check: with a healthy reference-image plate
# solution at least a few percent of the detected stars match Tycho-2
# (typically 8-60% depending on the detection depth); a broken plate
# solution leaves ~0.1% of chance matches, and a zero point fitted from
# those is off by magnitudes. Report an ERROR (which the nightly summary
# page picks up from the log) but DO NOT exit: the calibration proceeds so
# the report is still produced for inspection. The check is skipped for
# very shallow catalogs where small-number statistics would make the
# fraction meaningless.
# The threshold is env-overridable so cameras with a naturally low match
# fraction can set a per-camera value in transient_factory_test31.sh.
: "${MIN_PERCENT_OF_DETECTED_STARS_MATCHED_FOR_MAG_CALIBRATION:=1.0}"
# Stricter companion threshold used when the matched fraction is normalized by
# the number of catalog stars available in the frame (see below): a healthy
# plate solution matches 4-17 percent of the AVAILABLE catalog stars, while a
# broken one still reaches ~1.5 percent there (65 chance matches of 4411
# catalog stars in the NMW-STL plate-solve-failure test), so the 1.0 default
# tuned for the detected-star denominator is far too lenient for this one.
: "${MIN_PERCENT_OF_CATALOG_STARS_MATCHED_FOR_MAG_CALIBRATION:=2.5}"
MIN_DETECTED_STARS_FOR_MATCH_FRACTION_CHECK=1000
if [ -s calib.txt ] && [ -s wcsmag.cat ];then
 N_CALIBRATION_STARS=$(wc -l < calib.txt)
 N_DETECTED_STARS_FOR_CALIBRATION=$(wc -l < wcsmag.cat)
 # The matched fraction is capped by the number of catalog stars in the frame,
 # not only by the plate solution quality: a deep detection catalog (hundreds
 # of thousands of sources in a Milky Way field) can never match more than the
 # ~30k Tycho-2 stars available there. Normalize by the smaller of the two
 # counts. lib/catalogs/read_tycho2 writes the in-frame catalog star count to
 # calibration_catalog_stars_in_frame.count; fall back to the old
 # detected-only denominator when the count file is absent (older binary).
 N_FRACTION_CHECK_DENOMINATOR="$N_DETECTED_STARS_FOR_CALIBRATION"
 MIN_PERCENT_FOR_FRACTION_CHECK="$MIN_PERCENT_OF_DETECTED_STARS_MATCHED_FOR_MAG_CALIBRATION"
 if [ -s calibration_catalog_stars_in_frame.count ];then
  N_CATALOG_STARS_IN_FRAME=$(head -n 1 calibration_catalog_stars_in_frame.count | awk '{print $1}')
  if [ -n "$N_CATALOG_STARS_IN_FRAME" ] && [ "$N_CATALOG_STARS_IN_FRAME" -gt 0 ] 2>/dev/null && [ "$N_CATALOG_STARS_IN_FRAME" -lt "$N_DETECTED_STARS_FOR_CALIBRATION" ];then
   N_FRACTION_CHECK_DENOMINATOR="$N_CATALOG_STARS_IN_FRAME"
   MIN_PERCENT_FOR_FRACTION_CHECK="$MIN_PERCENT_OF_CATALOG_STARS_MATCHED_FOR_MAG_CALIBRATION"
  fi
 fi
 if [ "$N_DETECTED_STARS_FOR_CALIBRATION" -ge "$MIN_DETECTED_STARS_FOR_MATCH_FRACTION_CHECK" ];then
  if awk -v n="$N_CALIBRATION_STARS" -v d="$N_FRACTION_CHECK_DENOMINATOR" -v p="$MIN_PERCENT_FOR_FRACTION_CHECK" 'BEGIN { exit !( 100.0 * n / d < p ) }' ;then
   MATCH_PERCENT_FOR_DISPLAY=$(awk -v n="$N_CALIBRATION_STARS" -v d="$N_FRACTION_CHECK_DENOMINATOR" 'BEGIN { printf "%.2f", 100.0 * n / d }')
   echo "ERROR: only $N_CALIBRATION_STARS of $N_FRACTION_CHECK_DENOMINATOR matchable stars ($N_DETECTED_STARS_FOR_CALIBRATION detected on the reference image) matched the Tycho-2 photometric calibration catalog ($MATCH_PERCENT_FOR_DISPLAY%) - the reference image plate solution is likely broken and the magnitude calibration is unreliable"
  fi
 fi
fi

MAGNITUDE_CALIBRATION_PARAMETERS=$(lib/fit_zeropoint)
if [ $? -ne 0 ];then
 echo "ERROR fitting the magnitude scale with lib/fit_zeropoint"
 exit 1
fi
echo "util/calibrate_magnitude_scale $MAGNITUDE_CALIBRATION_PARAMETERS"
util/calibrate_magnitude_scale $MAGNITUDE_CALIBRATION_PARAMETERS
if [ $? -ne 0 ];then
 echo "ERROR: non-zero exit code of util/calibrate_magnitude_scale"
fi
echo "1.0 0.0 $MAGNITUDE_CALIBRATION_PARAMETERS" > calib.txt_param_tycho2

# Update the "Magnitude scale:" line in vast_summary.log
if [ -f vast_summary.log ];then
 # 'sed -i' works differently on MacOS
 #sed -i "s/Magnitude scale: instrumental/Magnitude scale: CV/" vast_summary.log
 sed 's/Magnitude scale: instrumental/Magnitude scale: CV/' vast_summary.log > vast_summary.log.tmp && mv vast_summary.log.tmp vast_summary.log
fi
