#!/usr/bin/env bash
#
# Install a local copy of the Gaia DR3 nearby stars for the UV Ceti (nearby red dwarf) check
# of transient candidates, util/transients/check_nearby_red_dwarf.sh, so that the check does
# not depend on the ESA Gaia archive or CDS VizieR being reachable while a field is processed.
#
# The copy holds every Gaia DR3 source with parallax > 5 mas (closer than 200 pc) and
# parallax_over_error > 3: 4.7 million sources (2026-11), 190 MB in the zone format of
# lib/catalogs/local_star_catalog (40-byte records with the parallax, its error, the proper
# motion, RUWE, G, BP and RP).
#
# The copy is first downloaded ready-made: gaia_dr3_nearby.tar.gz (about 160 MB) from the
# VaST catalog mirrors on tau.kirx.net and scan.sai.msu.ru (the one in the user's part of
# the world first), unpacked, and accepted only when every zone file and index is there and
# the zone files add up to the record count of catalog_info.txt. The same tarball is made
# from a finished copy with
#   tar --owner=0 --group=0 --numeric-owner -C DIR_ABOVE_THE_COPY -czf gaia_dr3_nearby.tar.gz gaia_dr3_nearby
# (the top directory inside the archive may have any name; the installer looks for
# catalog_info.txt one level down). Only when no mirror delivers the copy is it built from
# the ESA Gaia archive, which takes hours: the stars are downloaded with synchronous TAP
# queries, the sky is cut into declination bands of equal area, each band is counted once, a
# band of up to GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY sources is one query, a larger band is cut
# into equal RA pieces (the Galactic plane and the Magellanic Clouds add many sources with
# spurious parallaxes), and the rows of the pieces must add up to the count. What the archive
# allowed an anonymous user on 2026-11-09: asynchronous jobs are aborted after 60 s of
# execution; synchronous replies are cut at 50000 rows unless a larger MAXREC is requested
# (the request asks for 1000000) - a cut reply looks complete, hence the counts; the rows come
# at about 1500 per second; requests that follow each other within seconds, or too many of
# them, are refused with HTTP 429, so the script pauses after every reply and waits a minute
# before trying a refused query again.
#
# Usage:
#   lib/install_local_copy_of_GaiaDR3_nearby_stars.sh [DESTINATION_DIR]
#
# DESTINATION_DIR defaults to lib/catalogs/gaia_dr3_nearby. A directory elsewhere (for
# example /data_ssd/GaiaDR3_nearby) may be linked as lib/catalogs/gaia_dr3_nearby, or
# util/transients/transient_factory_test31.sh links it from one of the directories it
# searches for the local catalog copies. A copy outside the VaST tree survives
# lib/prepare_vast_release.sh, which deletes everything in lib/catalogs/. The download
# needs about 350 MB of free space in DESTINATION_DIR while it unpacks. A complete copy
# already in DESTINATION_DIR is left alone (remove the directory to reinstall).
#
# The ESA build is resumable: the pieces already downloaded are kept in
# DESTINATION_DIR/.staging as .part files, run the script again with the same DESTINATION_DIR
# to continue (with the same number of bands: the band boundaries depend on it). The tarball
# is downloaded and unpacked in DESTINATION_DIR/.download, which is removed afterwards.
#
# Settings (environment variables):
#   GAIA_DR3_NEARBY_SOURCE              auto (default: the mirrors, then the ESA archive),
#                                       mirror (never build from the archive), esa (never ask the mirrors)
#   GAIA_DR3_NEARBY_MIRRORS             space-separated base URLs of directories holding gaia_dr3_nearby.tar.gz;
#                                       the default is tau.kirx.net then scan.sai.msu.ru, the other way round
#                                       for a host in Russia (VAST_COUNTRY_CODE or lib/get_country_code.sh)
#   VAST_CURL_PROXY                     extra curl options (a proxy) for the mirror download
#   GAIA_DR3_NEARBY_MIN_PARALLAX_MAS    default 5.0 (200 pc); another value means an ESA build
#   GAIA_DR3_NEARBY_MIN_PLX_OVER_ERROR  default 3.0; another value means an ESA build
#   GAIA_DR3_NEARBY_DEC_BANDS           equal-area declination bands, default 100
#   GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY  a band with more sources is cut into RA pieces, default 60000
#   GAIA_DR3_NEARBY_QUERY_TIMEOUT_SEC   time allowed for one query, default 900
#   GAIA_DR3_NEARBY_PAUSE_SEC           pause between queries (the archive refuses rapid ones), default 15
#   GAIA_DR3_NEARBY_RETRY_ATTEMPTS      attempts at one query while the archive refuses or does not answer, default 20
#   GAIA_DR3_NEARBY_RETRY_SLEEP_SEC     pause between the attempts, default 60
#   GAIA_TAP_URL                        default https://gea.esac.esa.int/tap-server/tap
#
# Exit codes: 0 the copy is ready, 1 an error (the message says whether a rerun will continue).

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

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

DESTINATION_DIR="${1:-lib/catalogs/gaia_dr3_nearby}"
: "${GAIA_DR3_NEARBY_SOURCE:=auto}"
: "${GAIA_DR3_NEARBY_MIN_PARALLAX_MAS:=5.0}"
: "${GAIA_DR3_NEARBY_MIN_PLX_OVER_ERROR:=3.0}"
: "${GAIA_DR3_NEARBY_DEC_BANDS:=100}"
: "${GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY:=60000}"
: "${GAIA_DR3_NEARBY_QUERY_TIMEOUT_SEC:=900}"
: "${GAIA_DR3_NEARBY_PAUSE_SEC:=15}"
: "${GAIA_DR3_NEARBY_RETRY_ATTEMPTS:=20}"
: "${GAIA_DR3_NEARBY_RETRY_SLEEP_SEC:=60}"
: "${GAIA_TAP_URL:=https://gea.esac.esa.int/tap-server/tap}"
# the row limit asked for with every query (the archive's own default for anonymous
# synchronous queries is 50000); the row count check catches a reply cut below it
TAP_MAXREC=1000000
# the ready-made copy on the mirrors: the file name and the selection it was built with
DIST_FILE_NAME="gaia_dr3_nearby.tar.gz"
DIST_MIN_PARALLAX_MAS=5.0
DIST_MIN_PLX_OVER_ERROR=3.0
# a complete copy of that selection has 4.7 million stars; a much smaller one is a stub
DIST_MIN_RECORDS=4000000
MIRROR_TAU="http://tau.kirx.net/vast_catalogs/gaia_dr3_nearby"
MIRROR_SCAN="http://scan.sai.msu.ru/~kirx/data/gaia_dr3_nearby"

for TOOL in curl awk gzip tar ;do
 if ! command -v "$TOOL" &>/dev/null ;then
  echo "ERROR: $TOOL is required" 1>&2
  exit 1
 fi
done
case "$GAIA_DR3_NEARBY_SOURCE" in
 auto|mirror|esa)
  ;;
 *)
  echo "ERROR: GAIA_DR3_NEARBY_SOURCE=$GAIA_DR3_NEARBY_SOURCE is not one of auto, mirror, esa" 1>&2
  exit 1
  ;;
esac
if ! [[ "$GAIA_DR3_NEARBY_DEC_BANDS" =~ ^[0-9]+$ ]] || [ "$GAIA_DR3_NEARBY_DEC_BANDS" -lt 1 ] || [ "$GAIA_DR3_NEARBY_DEC_BANDS" -gt 1000 ];then
 echo "ERROR: GAIA_DR3_NEARBY_DEC_BANDS=$GAIA_DR3_NEARBY_DEC_BANDS is not a number between 1 and 1000" 1>&2
 exit 1
fi
if ! [[ "$GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY" =~ ^[0-9]+$ ]] || [ "$GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY" -lt 1000 ] || [ "$GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY" -gt "$TAP_MAXREC" ];then
 echo "ERROR: GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY=$GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY is not a number between 1000 and $TAP_MAXREC" 1>&2
 exit 1
fi
if ! [[ "$GAIA_DR3_NEARBY_RETRY_ATTEMPTS" =~ ^[0-9]+$ ]] || [ "$GAIA_DR3_NEARBY_RETRY_ATTEMPTS" -lt 1 ];then
 echo "ERROR: GAIA_DR3_NEARBY_RETRY_ATTEMPTS=$GAIA_DR3_NEARBY_RETRY_ATTEMPTS is not a positive number" 1>&2
 exit 1
fi
# compressed transfers when curl can decode them (the CSV shrinks about three times)
CURL_COMPRESSED=""
if curl --version 2>/dev/null | grep -q -i -e "libz" -e "zlib" -e "brotli" ;then
 CURL_COMPRESSED="--compressed"
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
 echo "ERROR: refusing to build in $DESTINATION_DIR" 1>&2
 exit 1
fi
STAGING_DIR="$DESTINATION_DIR/.staging"
DOWNLOAD_DIR="$DESTINATION_DIR/.download"

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
 if [ ! -s "$INFO_FILE" ] || ! grep -q '^catalog=gaia_dr3_nearby$' "$INFO_FILE" ;then
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
 TOTAL_BYTES=$(cat "$DIR"/z[0-9][0-9][0-9] | wc -c | tr -d ' ')
 if [ "$TOTAL_BYTES" -ne $((CATALOG_RECORDS * RECORD_SIZE)) ];then
  return 1
 fi
 return 0
}

report_ready_copy() {
 # the transient search may run as another user (the web server account)
 chmod -R a+rX "$DESTINATION_DIR"
 echo "The local copy of the Gaia DR3 nearby stars is ready in $DESTINATION_DIR:"
 cat "$DESTINATION_DIR/catalog_info.txt"
 du -sh "$DESTINATION_DIR"
}

if catalog_is_complete "$DESTINATION_DIR" ;then
 echo "A complete local copy of the Gaia DR3 nearby stars ($CATALOG_RECORDS stars) is already in $DESTINATION_DIR - nothing to do (remove the directory to reinstall)"
 report_ready_copy
 exit 0
fi

##### The ready-made copy from the mirrors #####

# Download a gzip file with resume and a few attempts; 0 when FILE passes 'gzip -t'.
# Arguments: URL FILE
download_gzip_file() {
 local URL="$1"
 local FILE="$2"
 local ATTEMPT
 local CURL_EXIT
 local HTTP_CODE
 for ATTEMPT in 1 2 3 ;do
  # a complete file from an earlier attempt
  if [ -s "$FILE" ] && gzip -t "$FILE" 2>/dev/null ;then
   return 0
  fi
  # -C -: continue a partial download; --fail: no error page saved under the file name;
  # --speed-limit/--speed-time: give up a stalled transfer, the next attempt resumes it
  # shellcheck disable=SC2086
  HTTP_CODE=$(curl $VAST_CURL_PROXY -L --fail --silent --show-error --connect-timeout 30 --max-time 3600 --speed-limit 1024 --speed-time 60 -C - -o "$FILE" -w '%{http_code}' "$URL")
  CURL_EXIT=$?
  if [ "$CURL_EXIT" -eq 0 ];then
   if gzip -t "$FILE" 2>/dev/null ;then
    return 0
   fi
   # a complete reply that is not the archive (an error page sent with status 200, a stub
   # file): this mirror will not do better on another attempt
   echo "WARNING: $URL delivered a file that is not a gzip archive, it starts with: $(head -c 200 "$FILE" 2>/dev/null | LC_ALL=C tr -cd '\011\040-\176')" 1>&2
   rm -f "${FILE:?}"
   return 1
  fi
  echo "WARNING: $URL (attempt $ATTEMPT of 3) failed with curl exit code $CURL_EXIT, HTTP status $HTTP_CODE" 1>&2
  # 22: an HTTP error (a missing file, or a range the server cannot serve), 33: the server
  # does not resume - nothing to continue from; other errors (a dropped connection, a
  # stalled transfer) leave the partial file for the next attempt to continue
  if [ "$CURL_EXIT" -eq 22 ] || [ "$CURL_EXIT" -eq 33 ];then
   rm -f "${FILE:?}"
   # the file is not on this mirror: no point in asking again
   if [ "$HTTP_CODE" = "404" ];then
    return 1
   fi
  fi
  if [ "$ATTEMPT" -lt 3 ];then
   sleep 10
  fi
 done
 rm -f "${FILE:?}"
 return 1
}

# Install the ready-made copy from one mirror; 0 when the catalog files are in
# DESTINATION_DIR. Argument: the base URL of the directory holding DIST_FILE_NAME
install_from_mirror() {
 local BASE_URL="${1%/}"
 local TARBALL="$DOWNLOAD_DIR/$DIST_FILE_NAME"
 local EXTRACT_DIR="$DOWNLOAD_DIR/extract"
 local INFO_FILE
 local SOURCE_DIR=""
 echo "Downloading the ready-made copy $BASE_URL/$DIST_FILE_NAME"
 if ! download_gzip_file "$BASE_URL/$DIST_FILE_NAME" "$TARBALL" ;then
  return 1
 fi
 rm -rf "${EXTRACT_DIR:?}"
 if ! mkdir -p "$EXTRACT_DIR" || ! gzip -dc "$TARBALL" | ( cd "$EXTRACT_DIR" && tar xf - ) ;then
  echo "WARNING: the archive from $BASE_URL could not be unpacked" 1>&2
  rm -rf "${EXTRACT_DIR:?}"
  rm -f "${TARBALL:?}"
  return 1
 fi
 for INFO_FILE in "$EXTRACT_DIR"/catalog_info.txt "$EXTRACT_DIR"/*/catalog_info.txt ;do
  if [ -f "$INFO_FILE" ];then
   SOURCE_DIR=$(dirname "$INFO_FILE")
   break
  fi
 done
 if [ -z "$SOURCE_DIR" ] || ! catalog_is_complete "$SOURCE_DIR" ;then
  echo "WARNING: the archive from $BASE_URL does not hold a complete catalog (no catalog_info.txt, a zone file or an index missing, or the zone files do not add up to the record count)" 1>&2
  rm -rf "${EXTRACT_DIR:?}"
  rm -f "${TARBALL:?}"
  return 1
 fi
 if [ "$CATALOG_RECORDS" -lt "$DIST_MIN_RECORDS" ];then
  echo "WARNING: the copy from $BASE_URL has only $CATALOG_RECORDS stars, the whole-sky selection has about 4.7 million" 1>&2
  rm -rf "${EXTRACT_DIR:?}"
  rm -f "${TARBALL:?}"
  return 1
 fi
 echo "The archive holds a complete copy with $CATALOG_RECORDS stars"
 # the ready-made copy replaces whatever an interrupted build or install left behind
 rm -rf "${STAGING_DIR:?}"
 rm -f "${DESTINATION_DIR:?}"/catalog_info.txt "${DESTINATION_DIR:?}"/z[0-9][0-9][0-9] "${DESTINATION_DIR:?}"/z[0-9][0-9][0-9].idx
 if ! mv "$SOURCE_DIR"/catalog_info.txt "$SOURCE_DIR"/z[0-9][0-9][0-9] "$SOURCE_DIR"/z[0-9][0-9][0-9].idx "$DESTINATION_DIR"/ ;then
  echo "ERROR: could not move the catalog files from $SOURCE_DIR to $DESTINATION_DIR" 1>&2
  return 1
 fi
 rm -rf "${DOWNLOAD_DIR:?}"
 return 0
}

if [ "$GAIA_DR3_NEARBY_SOURCE" != "esa" ];then
 if awk -v a="$GAIA_DR3_NEARBY_MIN_PARALLAX_MAS" -v b="$DIST_MIN_PARALLAX_MAS" -v c="$GAIA_DR3_NEARBY_MIN_PLX_OVER_ERROR" -v d="$DIST_MIN_PLX_OVER_ERROR" 'BEGIN { exit (a == b && c == d) ? 0 : 1 }' ;then
  if [ -z "$GAIA_DR3_NEARBY_MIRRORS" ];then
   if [ -z "$VAST_COUNTRY_CODE" ] && [ -x lib/get_country_code.sh ];then
    VAST_COUNTRY_CODE=$(lib/get_country_code.sh 2>/dev/null)
   fi
   if [ "$VAST_COUNTRY_CODE" = "RU" ];then
    GAIA_DR3_NEARBY_MIRRORS="$MIRROR_SCAN $MIRROR_TAU"
   else
    GAIA_DR3_NEARBY_MIRRORS="$MIRROR_TAU $MIRROR_SCAN"
   fi
  fi
  if ! mkdir -p "$DOWNLOAD_DIR" ;then
   echo "ERROR: cannot create $DOWNLOAD_DIR" 1>&2
   exit 1
  fi
  for MIRROR in $GAIA_DR3_NEARBY_MIRRORS ;do
   if install_from_mirror "$MIRROR" ;then
    if catalog_is_complete "$DESTINATION_DIR" ;then
     report_ready_copy
     exit 0
    fi
    echo "ERROR: the files moved to $DESTINATION_DIR do not make a complete catalog" 1>&2
    exit 1
   fi
  done
  rm -rf "${DOWNLOAD_DIR:?}"
  if [ "$GAIA_DR3_NEARBY_SOURCE" = "mirror" ];then
   echo "ERROR: no mirror delivered the ready-made copy ($GAIA_DR3_NEARBY_MIRRORS) and GAIA_DR3_NEARBY_SOURCE=mirror forbids building it from the ESA archive" 1>&2
   exit 1
  fi
  echo "No mirror delivered the ready-made copy, building it from the ESA Gaia archive instead (this takes hours)"
 else
  if [ "$GAIA_DR3_NEARBY_SOURCE" = "mirror" ];then
   echo "ERROR: the mirrors hold the selection parallax > $DIST_MIN_PARALLAX_MAS mas, parallax_over_error > $DIST_MIN_PLX_OVER_ERROR only; the requested parallax > $GAIA_DR3_NEARBY_MIN_PARALLAX_MAS mas, parallax_over_error > $GAIA_DR3_NEARBY_MIN_PLX_OVER_ERROR can only be built from the ESA archive (GAIA_DR3_NEARBY_SOURCE=auto or esa)" 1>&2
   exit 1
  fi
  echo "The requested selection (parallax > $GAIA_DR3_NEARBY_MIN_PARALLAX_MAS mas, parallax_over_error > $GAIA_DR3_NEARBY_MIN_PLX_OVER_ERROR) is not the one on the mirrors, building it from the ESA Gaia archive"
 fi
fi

##### The build from the ESA Gaia archive #####

if ! mkdir -p "$STAGING_DIR" ;then
 echo "ERROR: cannot create $STAGING_DIR" 1>&2
 exit 1
fi

TAP_SELECT="SELECT source_id, ra, dec, parallax, parallax_error, pmra, pmdec, phot_g_mean_mag, phot_bp_mean_mag, phot_rp_mean_mag, ruwe, phot_variable_flag FROM gaiadr3.gaia_source"
TAP_WHERE_COMMON="parallax > $GAIA_DR3_NEARBY_MIN_PARALLAX_MAS AND parallax_over_error > $GAIA_DR3_NEARBY_MIN_PLX_OVER_ERROR"

echo "Building the local copy of the Gaia DR3 nearby stars (parallax > $GAIA_DR3_NEARBY_MIN_PARALLAX_MAS mas, parallax_over_error > $GAIA_DR3_NEARBY_MIN_PLX_OVER_ERROR) in $DESTINATION_DIR"
echo "from $GAIA_TAP_URL in $GAIA_DR3_NEARBY_DEC_BANDS declination bands, about $GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY sources per query"

# The declination condition of band K (0-based) of N equal-area bands
band_condition() {
 local K="$1"
 local N="$2"
 awk -v k="$K" -v n="$N" 'function asin_deg(x) { if (x <= -1.0) return -90.0; if (x >= 1.0) return 90.0; return atan2(x, sqrt(1.0 - x*x)) * 180.0 / 3.14159265358979323846 }
 BEGIN {
  lo = asin_deg(-1.0 + 2.0*k/n);
  hi = asin_deg(-1.0 + 2.0*(k+1)/n);
  if (k == 0) lo_cond = "dec >= -90.0"; else lo_cond = sprintf("dec >= %.6f", lo);
  if (k == n-1) hi_cond = "dec <= 90.0"; else hi_cond = sprintf("dec < %.6f", hi);
  printf "%s AND %s", lo_cond, hi_cond;
 }'
}

# Synchronous TAP query saved to a file; the HTTP status goes to TAP_HTTP_STATUS ("000" when
# curl got no complete reply). Returns 0 only for an HTTP 200 reply that starts with the
# requested CSV header (anything else is an error message or a web page).
tap_sync_to_file() {
 local QUERY="$1"
 local OUTPUT_FILE="$2"
 local FIRST_COLUMN="$3"
 local CURL_EXIT
 TAP_HTTP_STATUS=$(curl -s --max-time "$GAIA_DR3_NEARBY_QUERY_TIMEOUT_SEC" $CURL_COMPRESSED -o "$OUTPUT_FILE" -w '%{http_code}' "$GAIA_TAP_URL/sync" -d "REQUEST=doQuery" -d "LANG=ADQL" -d "FORMAT=csv" -d "MAXREC=$TAP_MAXREC" --data-urlencode "QUERY=$QUERY" 2>/dev/null)
 CURL_EXIT=$?
 if [ "$CURL_EXIT" -ne 0 ];then
  TAP_HTTP_STATUS="000"
  return 1
 fi
 if [ "$TAP_HTTP_STATUS" != "200" ];then
  return 1
 fi
 if [ "$(head -n 1 "$OUTPUT_FILE" | cut -d, -f1 | tr -d '\r')" != "$FIRST_COLUMN" ];then
  TAP_HTTP_STATUS="200 (not the requested table)"
  return 1
 fi
 return 0
}

# A query with retries while the archive refuses or does not answer; same arguments
tap_sync_with_retries() {
 local ATTEMPT
 for ATTEMPT in $(seq 1 "$GAIA_DR3_NEARBY_RETRY_ATTEMPTS") ;do
  if tap_sync_to_file "$1" "$2" "$3" ;then
   sleep "$GAIA_DR3_NEARBY_PAUSE_SEC"
   return 0
  fi
  echo "WARNING: the query got HTTP status $TAP_HTTP_STATUS (attempt $ATTEMPT of $GAIA_DR3_NEARBY_RETRY_ATTEMPTS): $(head -c 200 "$2" 2>/dev/null | tr '\n' ' ')" 1>&2
  rm -f "${2:?}"
  if [ "$ATTEMPT" -lt "$GAIA_DR3_NEARBY_RETRY_ATTEMPTS" ];then
   sleep "$GAIA_DR3_NEARBY_RETRY_SLEEP_SEC"
  fi
 done
 return 1
}

# Download one declination band. Its sources are counted once; a band of up to
# GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY sources is one query (BAND_NAME.part), a larger band is
# cut into equal RA pieces, twice as many as the count alone would need because the stars are
# not spread evenly in RA (BAND_NAME_pNNN_of_MMM.part, with the rows of each piece in a .rows
# file), and the rows of all pieces must add up to the count. Done pieces are skipped on a
# rerun; a band whose pieces do not add up is cleared and gets twice as many pieces next time
# (the number is kept in BAND_NAME.pieces). Arguments: BAND_NAME DEC_CONDITION
download_band() {
 local BAND_NAME="$1"
 local DEC_CONDITION="$2"
 local COUNT_FILE="$STAGING_DIR/$BAND_NAME.count"
 local PIECES_FILE="$STAGING_DIR/$BAND_NAME.pieces"
 local EXPECTED_COUNT
 local N_PIECES
 local PIECE
 local PIECE_NAME
 local RA_LO
 local RA_HI
 local CONDITION
 local CSV_FILE
 local N_DATA_LINES
 local SUM_ROWS
 # a band downloaded as a whole in an earlier run
 if [ -f "$STAGING_DIR/$BAND_NAME.part" ];then
  return 0
 fi
 if ! tap_sync_with_retries "SELECT COUNT(*) AS n FROM gaiadr3.gaia_source WHERE $TAP_WHERE_COMMON AND $DEC_CONDITION" "$COUNT_FILE" "n" ;then
  echo "ERROR: no row count from the archive for this band" 1>&2
  return 1
 fi
 EXPECTED_COUNT=$(sed -n '2p' "$COUNT_FILE" | tr -d '\r ')
 rm -f "${COUNT_FILE:?}"
 if ! [[ "$EXPECTED_COUNT" =~ ^[0-9]+$ ]] ;then
  echo "ERROR: unexpected row count '$EXPECTED_COUNT' from the archive for this band" 1>&2
  return 1
 fi
 if [ -s "$PIECES_FILE" ];then
  N_PIECES=$(tr -d '\r\n ' < "$PIECES_FILE")
 else
  N_PIECES=$(( (EXPECTED_COUNT + GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY - 1) / GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY ))
  if [ "$N_PIECES" -gt 1 ];then
   N_PIECES=$((N_PIECES * 2))
  fi
 fi
 if ! [[ "$N_PIECES" =~ ^[0-9]+$ ]] || [ "$N_PIECES" -lt 1 ];then
  N_PIECES=1
 fi
 echo "The archive has $EXPECTED_COUNT sources in this band: $N_PIECES query(ies)"
 echo "$N_PIECES" > "$PIECES_FILE"
 SUM_ROWS=0
 for (( PIECE=0; PIECE<N_PIECES; PIECE++ )) ;do
  if [ "$N_PIECES" -eq 1 ];then
   PIECE_NAME="$BAND_NAME"
   CONDITION="$DEC_CONDITION"
  else
   PIECE_NAME=$(printf "%s_p%03d_of_%03d" "$BAND_NAME" "$PIECE" "$N_PIECES")
   RA_LO=$(awk -v i="$PIECE" -v n="$N_PIECES" 'BEGIN { printf "%.6f", 360.0 * i / n }')
   RA_HI=$(awk -v i="$PIECE" -v n="$N_PIECES" 'BEGIN { printf "%.6f", 360.0 * (i + 1) / n }')
   CONDITION="$DEC_CONDITION AND ra >= $RA_LO AND ra < $RA_HI"
  fi
  if [ -f "$STAGING_DIR/$PIECE_NAME.part" ] && [ -s "$STAGING_DIR/$PIECE_NAME.rows" ];then
   SUM_ROWS=$(( SUM_ROWS + $(tr -d '\r\n ' < "$STAGING_DIR/$PIECE_NAME.rows") ))
   continue
  fi
  echo "Piece $PIECE_NAME: $CONDITION"
  CSV_FILE="$STAGING_DIR/$PIECE_NAME.csv"
  if ! tap_sync_with_retries "$TAP_SELECT WHERE $TAP_WHERE_COMMON AND $CONDITION" "$CSV_FILE" "source_id" ;then
   echo "ERROR: could not download this piece" 1>&2
   return 1
  fi
  N_DATA_LINES=$(($(wc -l < "$CSV_FILE") - 1))
  if ! lib/catalogs/local_star_catalog nearby-extract "$STAGING_DIR" "$PIECE_NAME" "$GAIA_DR3_NEARBY_MIN_PARALLAX_MAS" < "$CSV_FILE" ;then
   echo "ERROR: extraction of $CSV_FILE failed" 1>&2
   rm -f "${STAGING_DIR:?}/${PIECE_NAME:?}.part"
   return 1
  fi
  rm -f "${CSV_FILE:?}"
  echo "$N_DATA_LINES" > "$STAGING_DIR/$PIECE_NAME.rows"
  SUM_ROWS=$(( SUM_ROWS + N_DATA_LINES ))
 done
 if [ "$SUM_ROWS" -ne "$EXPECTED_COUNT" ];then
  echo "ERROR: the $N_PIECES query(ies) of this band returned $SUM_ROWS rows, the archive counted $EXPECTED_COUNT - a reply was cut or incomplete; the band is cleared and will be fetched in $((N_PIECES * 2)) pieces on the next run" 1>&2
  rm -f "${STAGING_DIR:?}/${BAND_NAME:?}".part "${STAGING_DIR:?}/${BAND_NAME:?}".rows "${STAGING_DIR:?}/${BAND_NAME:?}"_p*.part "${STAGING_DIR:?}/${BAND_NAME:?}"_p*.rows
  echo "$((N_PIECES * 2))" > "$PIECES_FILE"
  return 1
 fi
 rm -f "${PIECES_FILE:?}"
 return 0
}

N_BANDS_DONE=0
for (( BAND=0; BAND<GAIA_DR3_NEARBY_DEC_BANDS; BAND++ )) ;do
 BAND_NAME=$(printf "band_%04d_of_%04d" "$BAND" "$GAIA_DR3_NEARBY_DEC_BANDS")
 DEC_CONDITION=$(band_condition "$BAND" "$GAIA_DR3_NEARBY_DEC_BANDS")
 if [ ! -f "$STAGING_DIR/$BAND_NAME.part" ];then
  echo "Band $((BAND + 1)) of $GAIA_DR3_NEARBY_DEC_BANDS: $DEC_CONDITION"
 fi
 if ! download_band "$BAND_NAME" "$DEC_CONDITION" ;then
  echo "ERROR: band $((BAND + 1)) is incomplete - rerun $0 $DESTINATION_DIR later to continue" 1>&2
  break
 fi
 N_BANDS_DONE=$((N_BANDS_DONE + 1))
done

if [ "$N_BANDS_DONE" -ne "$GAIA_DR3_NEARBY_DEC_BANDS" ];then
 echo "ERROR: $N_BANDS_DONE of $GAIA_DR3_NEARBY_DEC_BANDS bands are done - rerun $0 $DESTINATION_DIR to continue" 1>&2
 exit 1
fi

echo "All $GAIA_DR3_NEARBY_DEC_BANDS bands downloaded, sorting the stars into zones"
if ! lib/catalogs/local_star_catalog finalize "$STAGING_DIR" "$DESTINATION_DIR" gaia_dr3_nearby "Gaia DR3 gaia_source with parallax > $GAIA_DR3_NEARBY_MIN_PARALLAX_MAS mas and parallax_over_error > $GAIA_DR3_NEARBY_MIN_PLX_OVER_ERROR, from $GAIA_TAP_URL on $(date -u +%Y-%m-%d)" ;then
 echo "ERROR: sorting the stars into zones failed; the staged files are kept in $STAGING_DIR" 1>&2
 exit 1
fi
rm -rf "${STAGING_DIR:?}"
if ! catalog_is_complete "$DESTINATION_DIR" ;then
 echo "ERROR: the catalog written to $DESTINATION_DIR is not complete (a zone file or an index is missing, or the zone files do not add up to the record count)" 1>&2
 exit 1
fi

report_ready_copy
exit 0
