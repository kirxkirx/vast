#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2329
#
# Build a local copy of Gaia DR2 for the known-star check of transient candidates
# (util/transients/report_transient.sh), so that the check no longer depends on CDS
# VizieR or the ESA Gaia archive being reachable while a field is processed.
#
# The copy is Gaia DR2 because the online check queries DR2 (VizieR I/345/gaia2, the ESA
# archive table gaiadr2.gaia_source) and the transient-search tests are tuned to DR2
# magnitudes. A Gaia DR3 copy was tried first (2026-11-04): DR3 mean magnitudes of
# large-amplitude variables differ from DR2 by up to a few tenths, which changes which
# Miras pass the check. The Saturn-field test in util/examples/test_vast.sh lost
# V2407 Sgr: DR2 G = 13.38 and DR3 G = 13.24, with the faint search limit at 13.29.
#
# The script streams the official Gaia DR2 gaia_source files from the ESA bulk-download
# server (61234 files, 588 GB in total), keeps the stars brighter than G = 19
# (568135077 of them) and writes them with lib/catalogs/local_star_catalog as 900
# declination zones sorted by RA, with an RA index: 13 GB. Only a few downloaded files
# are on disk at any time, but the build needs about 35 GB of free space: the extracted
# stars are staged before they are sorted into zones. The first build (2026-11-04) took
# 2 hours 8 minutes with the 12 default parallel downloads, about 75 MB/s from ESA.
#
# Usage:
#   lib/install_local_copy_of_GaiaDR2.sh [DESTINATION_DIR]
#
# DESTINATION_DIR defaults to lib/catalogs/gaia_dr2. To keep the catalog on a big disk,
# give a directory there (for example /data_ssd/GaiaDR2) and either link it as
# lib/catalogs/gaia_dr2 or let util/transients/transient_factory_test31.sh find it in
# one of the directories it searches for the local catalog copies.
#
# The download is resumable: after an interruption, run the script again with the same
# DESTINATION_DIR and it continues with the files not processed yet.
#
# Settings (environment variables):
#   GAIA_DR2_LOCAL_COPY_MAX_GMAG   faint limit in G, default 19.0
#   GAIA_DR2_DOWNLOAD_JOBS         files downloaded and extracted in parallel, default 12
#   GAIA_DR2_BULK_URL              default https://cdn.gea.esac.esa.int/Gaia/gdr2/gaia_source/csv
#   GAIA_DR2_MD5_LIST_NAME         the list of files with checksums there, default MD5SUM.txt
#   GAIA_DR2_FINALIZE_MEMORY_MB    memory for sorting the zones, default 8192
#
# This is a large one-time download meant for the machines that run the transient
# search. It refuses to run on GitHub Actions; the CI tests use small synthetic data.

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ "$GITHUB_ACTIONS" = "true" ];then
 echo "$0: not downloading the Gaia DR2 catalog (588 GB) on GitHub Actions" 1>&2
 exit 1
fi

# Work from the VaST directory: this script lives in its lib/ subdirectory
VAST_DIR=$(cd "$(dirname "$0")/.." && pwd)
if [ -z "$VAST_DIR" ] || ! cd "$VAST_DIR" ;then
 echo "ERROR: cannot change to the VaST directory" 1>&2
 exit 1
fi
if [ ! -x lib/catalogs/local_star_catalog ];then
 echo "ERROR: lib/catalogs/local_star_catalog is not built - please run 'make' in $VAST_DIR first" 1>&2
 exit 1
fi

DESTINATION_DIR="${1:-lib/catalogs/gaia_dr2}"
: "${GAIA_DR2_LOCAL_COPY_MAX_GMAG:=19.0}"
: "${GAIA_DR2_DOWNLOAD_JOBS:=12}"
: "${GAIA_DR2_BULK_URL:=https://cdn.gea.esac.esa.int/Gaia/gdr2/gaia_source/csv}"
: "${GAIA_DR2_MD5_LIST_NAME:=MD5SUM.txt}"
: "${GAIA_DR2_FINALIZE_MEMORY_MB:=8192}"

for TOOL in curl gzip awk xargs df ;do
 if ! command -v "$TOOL" &>/dev/null ;then
  echo "ERROR: $TOOL is required" 1>&2
  exit 1
 fi
done
if command -v md5sum &>/dev/null ;then
 MD5_COMMAND="md5sum"
elif command -v md5 &>/dev/null ;then
 MD5_COMMAND="md5 -q"
else
 echo "ERROR: md5sum or md5 is required to verify the downloaded files" 1>&2
 exit 1
fi

if ! mkdir -p "$DESTINATION_DIR" ;then
 echo "ERROR: cannot create $DESTINATION_DIR" 1>&2
 exit 1
fi
DESTINATION_DIR=$(cd "$DESTINATION_DIR" && pwd)
STAGING_DIR="$DESTINATION_DIR/.staging"
if ! mkdir -p "$STAGING_DIR" ;then
 echo "ERROR: cannot create $STAGING_DIR" 1>&2
 exit 1
fi

# The build needs room for the staged stars, the final zones and the files in flight
FREE_KB=$(df -Pk "$DESTINATION_DIR" | awk 'NR==2 {print $4}')
NEEDED_KB=$(( 35 * 1024 * 1024 ))
if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt "$NEEDED_KB" ] 2>/dev/null ;then
 echo "ERROR: only $(( FREE_KB / 1024 / 1024 )) GB free in $DESTINATION_DIR, the build needs about 35 GB" 1>&2
 exit 1
fi

echo "Building the local Gaia DR2 copy (G < $GAIA_DR2_LOCAL_COPY_MAX_GMAG) in $DESTINATION_DIR"
echo "from $GAIA_DR2_BULK_URL with $GAIA_DR2_DOWNLOAD_JOBS parallel downloads"

if ! curl --fail --silent --show-error --retry 5 --retry-delay 10 --connect-timeout 30 --max-time 600 -o "$STAGING_DIR/_MD5SUM.txt.tmp" "$GAIA_DR2_BULK_URL/$GAIA_DR2_MD5_LIST_NAME" ;then
 echo "ERROR: cannot download the list of files $GAIA_DR2_BULK_URL/$GAIA_DR2_MD5_LIST_NAME" 1>&2
 exit 1
fi
mv "$STAGING_DIR/_MD5SUM.txt.tmp" "$STAGING_DIR/_MD5SUM.txt"
N_FILES=$(awk '$2 ~ /^GaiaSource_.*\.csv\.gz$/' "$STAGING_DIR/_MD5SUM.txt" | wc -l | awk '{print $1}')
if [ "$N_FILES" -lt 1000 ] 2>/dev/null ;then
 echo "ERROR: the file list $GAIA_DR2_BULK_URL/$GAIA_DR2_MD5_LIST_NAME names only $N_FILES GaiaSource files" 1>&2
 exit 1
fi
N_DONE=$(find "$STAGING_DIR" -maxdepth 1 -name 'GaiaSource_*.csv.gz.part' | wc -l | awk '{print $1}')
echo "$N_FILES files to process, $N_DONE already done"

# Download, verify and extract one file. Runs in parallel under xargs.
process_one_gaia_file() {
 local EXPECTED_MD5="$1"
 local NAME="$2"
 local TMP_FILE="$STAGING_DIR/$NAME.download"
 local ACTUAL_MD5
 local ATTEMPT
 # the .part file appears atomically, only after a complete extraction
 if [ -f "$STAGING_DIR/$NAME.part" ];then
  return 0
 fi
 for ATTEMPT in 1 2 3 ;do
  if curl --fail --silent --show-error --retry 5 --retry-delay 10 --connect-timeout 30 --max-time 3600 -o "$TMP_FILE" "$GAIA_DR2_BULK_URL/$NAME" ;then
   ACTUAL_MD5=$($MD5_COMMAND "$TMP_FILE" | awk '{print $1}')
   if [ "$ACTUAL_MD5" = "$EXPECTED_MD5" ];then
    if gzip -dc "$TMP_FILE" | lib/catalogs/local_star_catalog gaia-extract "$STAGING_DIR" "$NAME" "$GAIA_DR2_LOCAL_COPY_MAX_GMAG" ;then
     rm -f "$TMP_FILE"
     return 0
    fi
    echo "Extraction of $NAME failed (attempt $ATTEMPT)" 1>&2
   else
    echo "Checksum mismatch for $NAME (attempt $ATTEMPT)" 1>&2
   fi
  else
   echo "Download of $NAME failed (attempt $ATTEMPT)" 1>&2
  fi
  rm -f "$TMP_FILE" "$STAGING_DIR/$NAME.part"
  sleep 10
 done
 echo "GAVE UP on $NAME - rerun the script to try again" 1>&2
 return 1
}
export -f process_one_gaia_file
export STAGING_DIR GAIA_DR2_BULK_URL GAIA_DR2_LOCAL_COPY_MAX_GMAG MD5_COMMAND

awk '$2 ~ /^GaiaSource_.*\.csv\.gz$/ {print $1, $2}' "$STAGING_DIR/_MD5SUM.txt" | xargs -P "$GAIA_DR2_DOWNLOAD_JOBS" -n 2 bash -c 'process_one_gaia_file "$1" "$2"' _

N_DONE=$(find "$STAGING_DIR" -maxdepth 1 -name 'GaiaSource_*.csv.gz.part' | wc -l | awk '{print $1}')
if [ "$N_DONE" -ne "$N_FILES" ];then
 echo "ERROR: $N_DONE of $N_FILES files are processed - rerun $0 $DESTINATION_DIR to continue" 1>&2
 exit 1
fi

echo "All $N_FILES files processed, sorting the stars into zones"
if ! lib/catalogs/local_star_catalog finalize "$STAGING_DIR" "$DESTINATION_DIR" gaia_dr2 "Gaia DR2 gaia_source, G < $GAIA_DR2_LOCAL_COPY_MAX_GMAG, built from $GAIA_DR2_BULK_URL on $(date -u +%Y-%m-%d)" "$GAIA_DR2_FINALIZE_MEMORY_MB" ;then
 echo "ERROR: sorting the stars into zones failed; the staged files are kept in $STAGING_DIR" 1>&2
 exit 1
fi
rm -rf "$STAGING_DIR"
# the transient search may run as another user (the web server account)
chmod -R a+rX "$DESTINATION_DIR"

echo "The local Gaia DR2 copy is ready:"
cat "$DESTINATION_DIR/catalog_info.txt"
du -sh "$DESTINATION_DIR"
exit 0
