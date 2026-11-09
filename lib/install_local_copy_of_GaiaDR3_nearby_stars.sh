#!/usr/bin/env bash
#
# Build a local copy of the Gaia DR3 nearby stars for the UV Ceti (nearby red dwarf) check
# of transient candidates, util/transients/check_nearby_red_dwarf.sh, so that the check does
# not depend on the ESA Gaia archive or CDS VizieR being reachable while a field is processed.
#
# The copy holds every Gaia DR3 source with parallax > 5 mas (closer than 200 pc) and
# parallax_over_error > 3: 4.7 million sources (2026-11), 190 MB in the zone format of
# lib/catalogs/local_star_catalog (40-byte records with the parallax, its error, the proper
# motion, RUWE, G, BP and RP). The stars are downloaded from the ESA Gaia archive with
# synchronous TAP queries: the sky is cut into declination bands of equal area, each band is
# counted once, a band of up to GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY sources is one query, a
# larger band is cut into equal RA pieces (the Galactic plane and the Magellanic Clouds add
# many sources with spurious parallaxes), and the rows of the pieces must add up to the
# count. What the archive allowed an anonymous user on 2026-11-09: asynchronous jobs are
# aborted after 60 s of execution; synchronous replies are cut at 50000 rows unless a larger
# MAXREC is requested (the request asks for 1000000) - a cut reply looks complete, hence
# the counts; the rows come at about 1500 per second; requests that follow each other within
# seconds, or too many of them, are refused with HTTP 429, so the script pauses after every
# reply and waits a minute before trying a refused query again.
#
# Usage:
#   lib/install_local_copy_of_GaiaDR3_nearby_stars.sh [DESTINATION_DIR]
#
# DESTINATION_DIR defaults to lib/catalogs/gaia_dr3_nearby. A directory elsewhere (for
# example /data_ssd/GaiaDR3_nearby) may be linked as lib/catalogs/gaia_dr3_nearby, or
# util/transients/transient_factory_test31.sh links it from one of the directories it
# searches for the local catalog copies. A copy outside the VaST tree survives
# lib/prepare_vast_release.sh, which deletes everything in lib/catalogs/.
#
# The build is resumable: the pieces already downloaded are kept in DESTINATION_DIR/.staging
# as .part files, run the script again with the same DESTINATION_DIR to continue (with the
# same number of bands: the band boundaries depend on it).
#
# Settings (environment variables):
#   GAIA_DR3_NEARBY_MIN_PARALLAX_MAS    default 5.0 (200 pc)
#   GAIA_DR3_NEARBY_MIN_PLX_OVER_ERROR  default 3.0
#   GAIA_DR3_NEARBY_DEC_BANDS           equal-area declination bands, default 100
#   GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY  a band with more sources is cut into RA pieces, default 60000
#   GAIA_DR3_NEARBY_QUERY_TIMEOUT_SEC   time allowed for one query, default 900
#   GAIA_DR3_NEARBY_PAUSE_SEC           pause between queries (the archive refuses rapid ones), default 15
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
: "${GAIA_DR3_NEARBY_MIN_PARALLAX_MAS:=5.0}"
: "${GAIA_DR3_NEARBY_MIN_PLX_OVER_ERROR:=3.0}"
: "${GAIA_DR3_NEARBY_DEC_BANDS:=100}"
: "${GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY:=60000}"
: "${GAIA_DR3_NEARBY_QUERY_TIMEOUT_SEC:=900}"
: "${GAIA_DR3_NEARBY_PAUSE_SEC:=15}"
: "${GAIA_TAP_URL:=https://gea.esac.esa.int/tap-server/tap}"
# the row limit asked for with every query (the archive's own default for anonymous
# synchronous queries is 50000); the row count check catches a reply cut below it
TAP_MAXREC=1000000
# attempts at one query while the archive refuses (HTTP 429, 5xx) or does not answer in time
TAP_RETRY_ATTEMPTS=20
TAP_RETRY_SLEEP_SEC=60

for TOOL in curl awk ;do
 if ! command -v "$TOOL" &>/dev/null ;then
  echo "ERROR: $TOOL is required" 1>&2
  exit 1
 fi
done
if ! [[ "$GAIA_DR3_NEARBY_DEC_BANDS" =~ ^[0-9]+$ ]] || [ "$GAIA_DR3_NEARBY_DEC_BANDS" -lt 1 ] || [ "$GAIA_DR3_NEARBY_DEC_BANDS" -gt 1000 ];then
 echo "ERROR: GAIA_DR3_NEARBY_DEC_BANDS=$GAIA_DR3_NEARBY_DEC_BANDS is not a number between 1 and 1000" 1>&2
 exit 1
fi
if ! [[ "$GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY" =~ ^[0-9]+$ ]] || [ "$GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY" -lt 1000 ] || [ "$GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY" -gt "$TAP_MAXREC" ];then
 echo "ERROR: GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY=$GAIA_DR3_NEARBY_MAX_ROWS_PER_QUERY is not a number between 1000 and $TAP_MAXREC" 1>&2
 exit 1
fi
# compressed transfers when curl can decode them (the CSV shrinks about three times)
CURL_COMPRESSED=""
if curl --version 2>/dev/null | grep -q -i -e "libz" -e "zlib" -e "brotli" ;then
 CURL_COMPRESSED="--compressed"
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
 for ATTEMPT in $(seq 1 $TAP_RETRY_ATTEMPTS) ;do
  if tap_sync_to_file "$1" "$2" "$3" ;then
   sleep "$GAIA_DR3_NEARBY_PAUSE_SEC"
   return 0
  fi
  echo "WARNING: the query got HTTP status $TAP_HTTP_STATUS (attempt $ATTEMPT of $TAP_RETRY_ATTEMPTS): $(head -c 200 "$2" 2>/dev/null | tr '\n' ' ')" 1>&2
  rm -f "${2:?}"
  sleep $TAP_RETRY_SLEEP_SEC
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
# the transient search may run as another user (the web server account)
chmod -R a+rX "$DESTINATION_DIR"

echo "The local copy of the Gaia DR3 nearby stars is ready:"
cat "$DESTINATION_DIR/catalog_info.txt"
du -sh "$DESTINATION_DIR"
exit 0
