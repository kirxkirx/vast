#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2329
#
# Install a local copy of Gaia DR2 for the known-star check of transient candidates
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
# The copy holds the stars brighter than G = 19 (568135077 of them), written with
# lib/catalogs/local_star_catalog as 900 declination zones sorted by RA, each with an RA
# index, plus catalog_info.txt: 1801 files, 13 GB.
#
# The script first downloads a ready-made copy from the VaST catalog mirrors on
# scan.sai.msu.ru and tau.kirx.net (the one in the user's part of the world first): the
# 1801 files as they are, each checked against MD5SUM.txt in the same directory. The
# download runs GAIA_DR2_MIRROR_DOWNLOAD_JOBS files at a time, needs about 14 GB of free
# space and is resumable: verified files are kept in DESTINATION_DIR/.mirror_download, and a
# rerun continues with the rest (also a file cut in the middle, when the server can resume).
# A copy is published on a mirror by placing the files of a finished copy together with their
# checksum list in one web directory, for example
#   cd /data_ssd/GaiaDR2 && md5sum catalog_info.txt z[0-9][0-9][0-9] z[0-9][0-9][0-9].idx > /some/where/MD5SUM.txt
# and then copying /data_ssd/GaiaDR2/* and MD5SUM.txt to the directory the mirror serves.
#
# Only when no mirror delivers the copy is it built from the official Gaia DR2 gaia_source
# files of the ESA bulk-download server (61234 files, 588 GB in total), which needs about
# 35 GB of free space: the extracted stars are staged before they are sorted into zones. The
# first build (2026-11-04) took 2 hours 8 minutes with the 12 default parallel downloads,
# about 75 MB/s from ESA. This build is resumable too: run the script again with the same
# DESTINATION_DIR and it continues with the files not processed yet.
#
# Usage:
#   lib/install_local_copy_of_GaiaDR2.sh [DESTINATION_DIR]
#
# DESTINATION_DIR defaults to lib/catalogs/gaia_dr2, like lib/install_local_copy_of_UCAC5.sh
# puts UCAC5 in lib/catalogs/ucac5. To keep the catalog on a big disk, give a directory
# there (for example /data_ssd/GaiaDR2) and either link it as lib/catalogs/gaia_dr2 or let
# util/transients/transient_factory_test31.sh find it in one of the directories it
# searches for the local catalog copies. A copy outside the VaST tree survives
# lib/prepare_vast_release.sh, which deletes everything in lib/catalogs/ (for a link
# there it removes only the link). unmw's working copies of VaST share lib/catalogs/ of
# the reference copy through a symlink, so the catalog is never copied per run.
# A complete copy already in DESTINATION_DIR is left alone (remove it to reinstall).
#
# Settings (environment variables):
#   GAIA_DR2_SOURCE                auto (default: the mirrors, then the ESA bulk download),
#                                  mirror (never build from ESA), esa (never ask the mirrors)
#   GAIA_DR2_MIRRORS               space-separated base URLs of directories holding the copy and
#                                  MD5SUM.txt; the default is tau.kirx.net then scan.sai.msu.ru,
#                                  the other way round for a host in Russia (VAST_COUNTRY_CODE
#                                  or lib/get_country_code.sh)
#   GAIA_DR2_MIRROR_DOWNLOAD_JOBS  files downloaded from a mirror in parallel, default 4
#   VAST_CURL_PROXY                extra curl options (a proxy) for the mirror download
#   GAIA_DR2_LOCAL_COPY_MAX_GMAG   faint limit in G of an ESA build, default 19.0
#   GAIA_DR2_DOWNLOAD_JOBS         files downloaded and extracted in parallel in an ESA build, default 12
#   GAIA_DR2_BULK_URL              default https://cdn.gea.esac.esa.int/Gaia/gdr2/gaia_source/csv
#   GAIA_DR2_MD5_LIST_NAME         the list of files with checksums there, default MD5SUM.txt
#   GAIA_DR2_FINALIZE_MEMORY_MB    memory for sorting the zones, default 8192
#
# This is a large one-time download meant for the machines that run the transient
# search. It refuses to run on GitHub Actions; the CI tests use small synthetic data.
#
# Exit codes: 0 the copy is ready, 1 an error (the message says whether a rerun will continue).

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ "$GITHUB_ACTIONS" = "true" ];then
 echo "$0: not downloading the Gaia DR2 catalog (13 GB, or 588 GB from ESA) on GitHub Actions" 1>&2
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
: "${GAIA_DR2_SOURCE:=auto}"
: "${GAIA_DR2_MIRROR_DOWNLOAD_JOBS:=4}"
: "${GAIA_DR2_LOCAL_COPY_MAX_GMAG:=19.0}"
: "${GAIA_DR2_DOWNLOAD_JOBS:=12}"
: "${GAIA_DR2_BULK_URL:=https://cdn.gea.esac.esa.int/Gaia/gdr2/gaia_source/csv}"
: "${GAIA_DR2_MD5_LIST_NAME:=MD5SUM.txt}"
: "${GAIA_DR2_FINALIZE_MEMORY_MB:=8192}"
# the ready-made copy on the mirrors: the catalog files and the list of their checksums
DIST_MD5_LIST_NAME="MD5SUM.txt"
# a complete copy (G < 19) has 568 million stars; a much smaller one is a stub
DIST_MIN_RECORDS=500000000
MIRROR_TAU="http://tau.kirx.net/vast_catalogs/gaia_dr2"
MIRROR_SCAN="http://scan.sai.msu.ru/~kirx/data/gaia_dr2"

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
case "$GAIA_DR2_SOURCE" in
 auto|mirror|esa)
  ;;
 *)
  echo "ERROR: GAIA_DR2_SOURCE=$GAIA_DR2_SOURCE is not one of auto, mirror, esa" 1>&2
  exit 1
  ;;
esac
if ! [[ "$GAIA_DR2_MIRROR_DOWNLOAD_JOBS" =~ ^[0-9]+$ ]] || [ "$GAIA_DR2_MIRROR_DOWNLOAD_JOBS" -lt 1 ];then
 echo "ERROR: GAIA_DR2_MIRROR_DOWNLOAD_JOBS=$GAIA_DR2_MIRROR_DOWNLOAD_JOBS is not a positive number" 1>&2
 exit 1
fi

if [ -L "$DESTINATION_DIR" ] && [ ! -e "$DESTINATION_DIR" ];then
 echo "ERROR: $DESTINATION_DIR is a symbolic link to $(readlink "$DESTINATION_DIR"), which does not exist - remove the link or create that directory first" 1>&2
 exit 1
fi
if ! mkdir -p "$DESTINATION_DIR" ;then
 echo "ERROR: cannot create $DESTINATION_DIR" 1>&2
 exit 1
fi
DESTINATION_DIR=$(cd "$DESTINATION_DIR" && pwd)
if [ -z "$DESTINATION_DIR" ] || [ "$DESTINATION_DIR" = "/" ];then
 echo "ERROR: refusing to install in $DESTINATION_DIR" 1>&2
 exit 1
fi
STAGING_DIR="$DESTINATION_DIR/.staging"
DOWNLOAD_DIR="$DESTINATION_DIR/.mirror_download"

# 0 when DIR holds a complete catalog: catalog_info.txt names it, every zone file has its
# index, and the zone files add up to records * record_size bytes. The record count goes to
# CATALOG_RECORDS. Argument: DIR
catalog_is_complete() {
 local DIR="$1"
 local INFO_FILE="$DIR/catalog_info.txt"
 local N_ZONES
 local RECORD_SIZE
 local N_ZONE_FILES
 local ZONE_FILE
 local TOTAL_BYTES
 CATALOG_RECORDS=""
 if [ ! -s "$INFO_FILE" ] || ! grep -q '^catalog=gaia_dr2$' "$INFO_FILE" ;then
  return 1
 fi
 CATALOG_RECORDS=$(grep '^records=' "$INFO_FILE" | head -n 1 | cut -d= -f2 | tr -d '\r ')
 N_ZONES=$(grep '^zones=' "$INFO_FILE" | head -n 1 | cut -d= -f2 | tr -d '\r ')
 RECORD_SIZE=$(grep '^record_size=' "$INFO_FILE" | head -n 1 | cut -d= -f2 | tr -d '\r ')
 if ! [[ "$CATALOG_RECORDS" =~ ^[0-9]+$ ]] || ! [[ "$N_ZONES" =~ ^[0-9]+$ ]] || ! [[ "$RECORD_SIZE" =~ ^[0-9]+$ ]] || [ "$N_ZONES" -lt 1 ] || [ "$RECORD_SIZE" -lt 1 ];then
  return 1
 fi
 N_ZONE_FILES=0
 for ZONE_FILE in "$DIR"/z[0-9][0-9][0-9] ;do
  if [ -f "$ZONE_FILE" ] && [ -f "$ZONE_FILE.idx" ];then
   N_ZONE_FILES=$((N_ZONE_FILES + 1))
  fi
 done
 if [ "$N_ZONE_FILES" -ne "$N_ZONES" ];then
  return 1
 fi
 # wc -c takes the size of a named regular file without reading it (13 GB here); printf
 # "%.0f" because some awk versions print large sums in exponential notation
 TOTAL_BYTES=$(wc -c "$DIR"/z[0-9][0-9][0-9] | awk '$2 != "total" {s += $1} END {printf "%.0f\n", s}')
 if [ "$TOTAL_BYTES" -ne $((CATALOG_RECORDS * RECORD_SIZE)) ];then
  return 1
 fi
 return 0
}

report_ready_copy() {
 # the transient search may run as another user (the web server account)
 chmod -R a+rX "$DESTINATION_DIR"
 echo "The local Gaia DR2 copy is ready in $DESTINATION_DIR:"
 cat "$DESTINATION_DIR/catalog_info.txt"
 du -sh "$DESTINATION_DIR"
}

# Free space in kB in the file system of DESTINATION_DIR (empty if df does not tell)
free_kb() {
 df -Pk "$DESTINATION_DIR" | awk 'NR==2 {print $4}'
}

if catalog_is_complete "$DESTINATION_DIR" ;then
 echo "A complete local Gaia DR2 copy ($CATALOG_RECORDS stars) is already in $DESTINATION_DIR - nothing to do (remove the directory to reinstall)"
 report_ready_copy
 exit 0
fi

##### The ready-made copy from the mirrors #####

# Download one file of the copy from MIRROR_BASE_URL into DOWNLOAD_DIR and check it against
# its MD5 sum. A verified file loses the .part suffix, so a rerun skips it. Runs in parallel
# under xargs. Arguments: EXPECTED_MD5 NAME
download_one_mirror_file() {
 local EXPECTED_MD5="$1"
 local NAME="$2"
 local FILE="$DOWNLOAD_DIR/$NAME"
 local ATTEMPT
 local CURL_EXIT
 if [ -f "$FILE" ];then
  return 0
 fi
 for ATTEMPT in 1 2 3 ;do
  # a complete .part file left by an interrupted run
  if [ -s "$FILE.part" ] && [ "$($MD5_COMMAND "$FILE.part" | awk '{print $1}')" = "$EXPECTED_MD5" ];then
   mv -f "$FILE.part" "$FILE"
   return 0
  fi
  # -C -: continue a partial file; --fail: no error page saved under the file name;
  # --speed-limit/--speed-time: give up a stalled transfer, the next attempt resumes it
  # shellcheck disable=SC2086
  curl $VAST_CURL_PROXY -L --fail --silent --show-error --connect-timeout 30 --max-time 3600 --speed-limit 1024 --speed-time 60 -C - -o "$FILE.part" "$MIRROR_BASE_URL/$NAME"
  CURL_EXIT=$?
  if [ "$CURL_EXIT" -eq 0 ];then
   if [ "$($MD5_COMMAND "$FILE.part" | awk '{print $1}')" = "$EXPECTED_MD5" ];then
    mv -f "$FILE.part" "$FILE"
    return 0
   fi
   echo "Checksum mismatch for $NAME from $MIRROR_BASE_URL (attempt $ATTEMPT)" 1>&2
   rm -f "${FILE:?}.part"
  else
   echo "Download of $NAME from $MIRROR_BASE_URL failed with curl exit code $CURL_EXIT (attempt $ATTEMPT)" 1>&2
   # 22: an HTTP error (a missing file, or a range the server cannot serve), 33: the server
   # does not resume - start the file over; other errors (a dropped connection, a stalled
   # transfer) leave the partial file for the next attempt to continue
   if [ "$CURL_EXIT" -eq 22 ] || [ "$CURL_EXIT" -eq 33 ];then
    rm -f "${FILE:?}.part"
   fi
  fi
  if [ "$ATTEMPT" -lt 3 ];then
   sleep 5
  fi
 done
 echo "GAVE UP on $NAME from $MIRROR_BASE_URL" 1>&2
 return 1
}
export -f download_one_mirror_file

# Install the ready-made copy from one mirror; 0 when the catalog files are in
# DESTINATION_DIR. Argument: the base URL of the directory holding the copy and MD5SUM.txt
install_from_mirror() {
 local BASE_URL="${1%/}"
 local LIST_FILE="$DOWNLOAD_DIR/$DIST_MD5_LIST_NAME"
 local N_LISTED
 local N_READY
 local NAME
 echo "Downloading the ready-made copy from $BASE_URL"
 # shellcheck disable=SC2086
 if ! curl $VAST_CURL_PROXY -L --fail --silent --show-error --connect-timeout 30 --max-time 600 -o "$LIST_FILE.new" "$BASE_URL/$DIST_MD5_LIST_NAME" ;then
  echo "WARNING: cannot download $BASE_URL/$DIST_MD5_LIST_NAME" 1>&2
  rm -f "${LIST_FILE:?}.new"
  return 1
 fi
 # Every line must be "md5 name" with one of the catalog's own file names (no paths): an error
 # page sent with status 200, or a list of something else, is rejected here. No {32} interval
 # in the regular expression: mawk 1.3.3 does not know it.
 N_LISTED=$(awk 'NF == 2 && length($1) == 32 && $1 ~ /^[0-9a-f]+$/ && ($2 == "catalog_info.txt" || $2 ~ /^z[0-9][0-9][0-9]$/ || $2 ~ /^z[0-9][0-9][0-9][.]idx$/) {n++} END {print n + 0}' "$LIST_FILE.new")
 if [ "$N_LISTED" -lt 3 ] || [ "$N_LISTED" -ne "$(awk 'NF > 0' "$LIST_FILE.new" | wc -l | tr -d ' ')" ];then
  echo "WARNING: $BASE_URL/$DIST_MD5_LIST_NAME is not a list of the catalog files with their MD5 sums" 1>&2
  rm -f "${LIST_FILE:?}.new"
  return 1
 fi
 # Files verified against another list (another mirror, another build) must not be mixed in
 if [ -f "$LIST_FILE" ] && ! cmp -s "$LIST_FILE" "$LIST_FILE.new" ;then
  echo "The checksum list differs from the one of the files downloaded before - starting the download over"
  for NAME in catalog_info.txt "$DOWNLOAD_DIR"/z[0-9][0-9][0-9] "$DOWNLOAD_DIR"/z[0-9][0-9][0-9].idx "$DOWNLOAD_DIR"/*.part ;do
   rm -f "${DOWNLOAD_DIR:?}/$(basename "$NAME")"
  done
 fi
 mv -f "$LIST_FILE.new" "$LIST_FILE"
 echo "$N_LISTED files to download, $GAIA_DR2_MIRROR_DOWNLOAD_JOBS at a time"
 MIRROR_BASE_URL="$BASE_URL"
 export MIRROR_BASE_URL DOWNLOAD_DIR MD5_COMMAND VAST_CURL_PROXY
 awk 'NF == 2 {print $1, $2}' "$LIST_FILE" | xargs -P "$GAIA_DR2_MIRROR_DOWNLOAD_JOBS" -n 2 bash -c 'download_one_mirror_file "$1" "$2"' _
 N_READY=0
 for NAME in $(awk 'NF == 2 {print $2}' "$LIST_FILE") ;do
  if [ -f "$DOWNLOAD_DIR/$NAME" ];then
   N_READY=$((N_READY + 1))
  fi
 done
 if [ "$N_READY" -ne "$N_LISTED" ];then
  echo "WARNING: only $N_READY of $N_LISTED files came from $BASE_URL (the verified ones are kept, a rerun continues)" 1>&2
  return 1
 fi
 if ! catalog_is_complete "$DOWNLOAD_DIR" ;then
  echo "WARNING: the files from $BASE_URL do not make a complete catalog (no catalog_info.txt, a zone file or an index missing, or the zone files do not add up to the record count)" 1>&2
  return 1
 fi
 if [ "$CATALOG_RECORDS" -lt "$DIST_MIN_RECORDS" ];then
  echo "WARNING: the copy from $BASE_URL has only $CATALOG_RECORDS stars, the G < 19 copy has about 568 million" 1>&2
  return 1
 fi
 echo "Downloaded a complete copy with $CATALOG_RECORDS stars"
 # the ready-made copy replaces whatever an interrupted ESA build left behind
 rm -rf "${STAGING_DIR:?}"
 rm -f "${DESTINATION_DIR:?}"/catalog_info.txt "${DESTINATION_DIR:?}"/z[0-9][0-9][0-9] "${DESTINATION_DIR:?}"/z[0-9][0-9][0-9].idx
 if ! mv "$DOWNLOAD_DIR"/catalog_info.txt "$DOWNLOAD_DIR"/z[0-9][0-9][0-9] "$DOWNLOAD_DIR"/z[0-9][0-9][0-9].idx "$DESTINATION_DIR"/ ;then
  echo "ERROR: could not move the catalog files from $DOWNLOAD_DIR to $DESTINATION_DIR" 1>&2
  return 1
 fi
 rm -rf "${DOWNLOAD_DIR:?}"
 return 0
}

if [ "$GAIA_DR2_SOURCE" != "esa" ];then
 if [ -z "$GAIA_DR2_MIRRORS" ];then
  if [ -z "$VAST_COUNTRY_CODE" ] && [ -x lib/get_country_code.sh ];then
   VAST_COUNTRY_CODE=$(lib/get_country_code.sh 2>/dev/null)
  fi
  if [ "$VAST_COUNTRY_CODE" = "RU" ];then
   GAIA_DR2_MIRRORS="$MIRROR_SCAN $MIRROR_TAU"
  else
   GAIA_DR2_MIRRORS="$MIRROR_TAU $MIRROR_SCAN"
  fi
 fi
 # the files being downloaded share the disk with the finished copy only for a moment (mv)
 FREE_KB=$(free_kb)
 NEEDED_KB=$(( 14 * 1024 * 1024 ))
 if [ -n "$FREE_KB" ] && [ "$FREE_KB" -lt "$NEEDED_KB" ] 2>/dev/null ;then
  echo "ERROR: only $(( FREE_KB / 1024 / 1024 )) GB free in $DESTINATION_DIR, the copy needs about 14 GB" 1>&2
  exit 1
 fi
 if ! mkdir -p "$DOWNLOAD_DIR" ;then
  echo "ERROR: cannot create $DOWNLOAD_DIR" 1>&2
  exit 1
 fi
 for MIRROR in $GAIA_DR2_MIRRORS ;do
  if install_from_mirror "$MIRROR" ;then
   if catalog_is_complete "$DESTINATION_DIR" ;then
    report_ready_copy
    exit 0
   fi
   echo "ERROR: the files moved to $DESTINATION_DIR do not make a complete catalog" 1>&2
   exit 1
  fi
 done
 if [ "$GAIA_DR2_SOURCE" = "mirror" ];then
  echo "ERROR: no mirror delivered the ready-made copy ($GAIA_DR2_MIRRORS) and GAIA_DR2_SOURCE=mirror forbids building it from the ESA bulk download; the files verified so far are kept in $DOWNLOAD_DIR, rerun $0 $DESTINATION_DIR to continue" 1>&2
  exit 1
 fi
 echo "No mirror delivered the ready-made copy, building it from the ESA bulk download instead (588 GB, hours)"
fi

##### The build from the ESA bulk download #####

if ! mkdir -p "$STAGING_DIR" ;then
 echo "ERROR: cannot create $STAGING_DIR" 1>&2
 exit 1
fi

# The build needs room for the staged stars, the final zones and the files in flight
FREE_KB=$(free_kb)
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
report_ready_copy
exit 0
