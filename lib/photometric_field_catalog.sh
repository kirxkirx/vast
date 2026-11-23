#!/usr/bin/env bash
#
# Fetch the photometric catalog stars around the reference stars of an image. The plate
# solver util/solve_plate_with_UCAC5 (search_photometric_field_catalog()) matches them to
# the image stars itself.
#
# Usage: lib/photometric_field_catalog.sh CATALOG POSITIONS_FILE MATCH_RADIUS_ARCSEC MAG_MIN MAG_MAX OUTPUT_FILE
#
#  CATALOG             apass - APASS DR9 (B V g' r' i'), selected by V
#                      gaia  - Gaia DR3 synthetic photometry (GSPC: Johnson B V, Cousins R I,
#                              SDSS g r i), selected by Gaia G; Gaia stars without synthetic
#                              photometry are listed too, so the matching can tell when the
#                              brightest star near a position has none
#  POSITIONS_FILE      the reference star positions, one "RA Dec" (degrees) per line
#  MATCH_RADIUS_ARCSEC the radius the solver will search around each position
#  MAG_MIN MAG_MAX     the magnitude range (V for APASS, G for Gaia)
#  OUTPUT_FILE         the table written for the solver (format below)
#
# The positions are covered with one cone around the field, or with up to four cones (the
# positions split into quadrants around the field center) when one cone would be wider
# than VAST_FIELD_CATALOG_TILE_RADIUS_DEG degrees (default 4); the cones are fetched in
# parallel. Fetching the field and matching locally replaced one upload join per reference
# star, which the ESA Gaia Archive cannot finish for 1000 positions within its 60 s limit
# (see doc/gaia_synthetic_photometry_handoff.md).
#
# Providers, tried in this order until one delivers every cone:
#  apass: esa       - ESA Gaia Archive, external.apassdr9
#         skymapper - SkyMapper TAP (NCI, Australia), ext.apass_dr9: the same catalog, the
#                     same rows; it accepts no table uploads, but cone queries are fine
#  gaia:  esa       - ESA Gaia Archive, gaiadr3.gaia_source + gaiadr3.synthetic_photometry_gspc
#         ari       - the same tables at ARI Heidelberg (slower)
# VAST_FIELD_CATALOG_PROVIDERS="..." replaces this list (names that do not serve CATALOG
# are skipped). A request that gets HTTP 408, 429, 5xx or no reply at all is repeated once
# after VAST_FIELD_CATALOG_RETRY_PAUSE_SEC seconds (default 10); any other failure, such as
# the maintenance page the ESA archive serves with HTTP 200, moves on to the next provider.
#
# The magnitude condition is written "mag + 0 BETWEEN a AND b": with "mag BETWEEN a AND b"
# the database behind the ESA archive may scan the table by magnitude instead of by
# position and run past its time limit (seen for external.apassdr9 on 2026-11-23).
#
# Cache: the tables are kept in VAST_FIELD_CATALOG_CACHE_DIR (default lib/catalogs/
# field_catalog_cache; "none" disables the cache), and a cached table is used instead of a
# new request when its cones contain every position (with the match radius around it, for
# Gaia 60 arcsec more) and its magnitude range contains MAG_MIN..MAG_MAX. The tables used
# least recently are removed when the cache grows beyond VAST_FIELD_CATALOG_CACHE_MAX_MB
# megabytes (default 1000; a Gaia table of the 24 by 24 degree TESS field to G = 13.5 takes
# 47 MB, an APASS one 9 MB).
#
# OUTPUT_FILE: comment lines starting with "#" (format version, catalog, provider, epoch of
# the positions, magnitude range, cones, number of rows, column names), then one
# whitespace-separated row per star:
#  id ra dec pmra pmdec ref_mag in_phot c_star variable  B eB fB  V eV fV  Rc eRc fRc  Ic eIc fIc  g eg fg  r er fr  i ei fi
# ra dec in degrees at the epoch given in the header, pmra (with cos Dec) and pmdec in
# mas/yr (0 when unknown); ref_mag is the selection magnitude (APASS V, Gaia G); in_phot is
# 0 for a Gaia star without synthetic photometry; c_star is the Gaia BP/RP excess factor
# (0 for APASS); variable is 1 for phot_variable_flag = VARIABLE; then magnitude, error and
# flag for each band (Gaia: the validity flag, APASS: 1). A missing magnitude, error or
# flag is 0. APASS gives no Rc and Ic: the solver computes them from V, r' and i'.
#
# Exit code: 0 - OUTPUT_FILE written (it may hold no stars), 1 - bad arguments,
#            2 - no provider delivered the stars.
# Messages go to stderr; a failed provider is a WARNING, not an ERROR, because the solver
# goes on with the next source.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ "$#" -ne 6 ];then
 echo "Usage: $0 apass|gaia POSITIONS_FILE MATCH_RADIUS_ARCSEC MAG_MIN MAG_MAX OUTPUT_FILE" >&2
 exit 1
fi
CATALOG="$1"
POSITIONS_FILE="$2"
MATCH_RADIUS_ARCSEC="$3"
MAG_MIN="$4"
MAG_MAX="$5"
OUTPUT_FILE="$6"

NUMBER_REGEX='^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$'
case "$CATALOG" in
 apass)
  CATALOG_NAME="APASS DR9"
  DEFAULT_PROVIDERS="esa skymapper"
  CATALOG_EPOCH="2000.0"
  ;;
 gaia)
  CATALOG_NAME="Gaia DR3 synthetic photometry"
  DEFAULT_PROVIDERS="esa ari"
  CATALOG_EPOCH="2016.0"
  ;;
 *)
  echo "$0: unknown catalog '$CATALOG' (expecting apass or gaia)" >&2
  exit 1
  ;;
esac
if ! awk -v r="$MATCH_RADIUS_ARCSEC" -v a="$MAG_MIN" -v b="$MAG_MAX" -v number="$NUMBER_REGEX" 'BEGIN {
  if (r !~ number || a !~ number || b !~ number || r + 0 <= 0 || r + 0 > 3600 || a + 0 > b + 0) exit 1
 }' ;then
 echo "$0: bad match radius or magnitude range: '$MATCH_RADIUS_ARCSEC' '$MAG_MIN' '$MAG_MAX'" >&2
 exit 1
fi
if [ ! -s "$POSITIONS_FILE" ];then
 echo "$0: no positions in '$POSITIONS_FILE'" >&2
 exit 1
fi
if [ -z "$OUTPUT_FILE" ];then
 echo "$0: no output file name" >&2
 exit 1
fi
# The synthetic photometry ends at G = 17.65: a fainter Gaia star can never be matched, and
# leaving it out cannot change which star is the brightest near a position that has one
QUERY_MAG_MAX="$MAG_MAX"
# The cones reach this far beyond the positions. The Gaia positions are those of 2016.0: the
# solver moves them to the epoch of the image with their proper motions, so the Gaia cones
# reach 60 arcsec further, enough for 3 arcsec/yr over 20 years.
CONE_MARGIN_ARCSEC="$MATCH_RADIUS_ARCSEC"
if [ "$CATALOG" = "gaia" ];then
 QUERY_MAG_MAX=$(awk -v b="$MAG_MAX" 'BEGIN {printf "%s", (b + 0 > 17.7) ? "17.7" : b}')
 CONE_MARGIN_ARCSEC=$(awk -v r="$MATCH_RADIUS_ARCSEC" 'BEGIN {printf "%.3f", r + 60}')
fi

VAST_DIR=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT_NAME=$(basename "$0")
TILE_RADIUS_DEG="${VAST_FIELD_CATALOG_TILE_RADIUS_DEG:-4}"
RETRY_PAUSE_SEC="${VAST_FIELD_CATALOG_RETRY_PAUSE_SEC:-10}"
CACHE_MAX_MB="${VAST_FIELD_CATALOG_CACHE_MAX_MB:-1000}"
MAX_ROWS=1000000
if ! echo "$TILE_RADIUS_DEG $RETRY_PAUSE_SEC $CACHE_MAX_MB" | awk -v number="$NUMBER_REGEX" '{exit !($1 ~ number && $1 + 0 > 0 && $2 ~ /^[0-9]+$/ && $3 ~ /^[0-9]+$/)}' ;then
 echo "$0: bad VAST_FIELD_CATALOG_TILE_RADIUS_DEG, VAST_FIELD_CATALOG_RETRY_PAUSE_SEC or VAST_FIELD_CATALOG_CACHE_MAX_MB" >&2
 exit 1
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vast-field-catalog.XXXXXXXX") || exit 2
trap 'rm -rf -- "$WORK_DIR"' EXIT
trap 'exit 2' HUP INT TERM

# Great-circle distances in degrees, shared by the awk programs below
AWK_SPHERE='
function rad(x) { return x * 3.14159265358979 / 180.0 }
function deg(x) { return x * 180.0 / 3.14159265358979 }
function sep(ra1, de1, ra2, de2,   c) {
 c = sin(rad(de1)) * sin(rad(de2)) + cos(rad(de1)) * cos(rad(de2)) * cos(rad(ra1 - ra2))
 if (c > 1) c = 1
 if (c < -1) c = -1
 return deg(atan2(sqrt(1 - c * c), c))
}'

# Validate the positions and cover them with cones: "cone RA Dec RADIUS" lines
if ! awk -v number="$NUMBER_REGEX" -v margin="$CONE_MARGIN_ARCSEC" -v tile="$TILE_RADIUS_DEG" "$AWK_SPHERE"'
 NF == 0 { next }
 NF < 2 || $1 !~ number || $2 !~ number || $2 + 0 > 90 || $2 + 0 < -90 { bad = 1; exit 1 }
 {
  n++
  ra[n] = ($1 + 0) % 360
  if (ra[n] < 0) ra[n] += 360
  de[n] = $2 + 0
  x += cos(rad(de[n])) * cos(rad(ra[n]))
  y += cos(rad(de[n])) * sin(rad(ra[n]))
  z += sin(rad(de[n]))
 }
 END {
  if (bad || n == 0) exit 1
  m = margin / 3600.0
  cra = deg(atan2(y, x))
  if (cra < 0) cra += 360
  cde = deg(atan2(z, sqrt(x * x + y * y)))
  r = 0
  for (i = 1; i <= n; i++) {
   s = sep(cra, cde, ra[i], de[i])
   if (s > r) r = s
  }
  r += m
  if (r <= tile + 0) {
   printf "cone %.7f %.7f %.7f\n", cra, cde, r
   exit 0
  }
  # Quadrants around the field center; each cone covers the positions of its quadrant
  for (i = 1; i <= n; i++) {
   dra = ra[i] - cra
   if (dra > 180) dra -= 360
   if (dra < -180) dra += 360
   q = (dra >= 0 ? 1 : 0) + (de[i] >= cde ? 2 : 0)
   qmember[i] = q
   qx[q] += cos(rad(de[i])) * cos(rad(ra[i]))
   qy[q] += cos(rad(de[i])) * sin(rad(ra[i]))
   qz[q] += sin(rad(de[i]))
   qn[q]++
  }
  for (q = 0; q < 4; q++) {
   if (qn[q] == 0) continue
   qra = deg(atan2(qy[q], qx[q]))
   if (qra < 0) qra += 360
   qde = deg(atan2(qz[q], sqrt(qx[q] * qx[q] + qy[q] * qy[q])))
   qr = 0
   for (i = 1; i <= n; i++) {
    if (qmember[i] != q) continue
    s = sep(qra, qde, ra[i], de[i])
    if (s > qr) qr = s
   }
   printf "cone %.7f %.7f %.7f\n", qra, qde, qr + m
  }
 }' "$POSITIONS_FILE" > "$WORK_DIR/cones.txt" ;then
 echo "$0: the positions in '$POSITIONS_FILE' are not 'RA Dec' pairs in degrees" >&2
 exit 1
fi
N_CONES=$(grep -c '^cone ' "$WORK_DIR/cones.txt")
N_POSITIONS=$(awk 'NF >= 2' "$POSITIONS_FILE" | wc -l | awk '{print $1}')

# Write the table: header lines, then the rows of $1 (without duplicates: the cones overlap)
# $2 - the provider name
write_table() {
 awk '!seen[$1]++' "$1" > "$WORK_DIR/rows_unique.txt" || return 1
 {
  echo "# vast_field_catalog 1"
  echo "# catalog $CATALOG"
  echo "# provider $2"
  echo "# epoch $CATALOG_EPOCH"
  echo "# mag_range $MAG_MIN $QUERY_MAG_MAX"
  sed 's/^/# /' "$WORK_DIR/cones.txt"
  echo "# fetched $(date +%s)"
  echo "# rows $(wc -l < "$WORK_DIR/rows_unique.txt" | awk '{print $1}')"
  echo "# columns id ra dec pmra pmdec ref_mag in_phot c_star variable B eB fB V eV fV Rc eRc fRc Ic eIc fIc g eg fg r er fr i ei fi"
  cat "$WORK_DIR/rows_unique.txt"
 } > "$WORK_DIR/table.txt" || return 1
 return 0
}

# Return 0 if the table $1 is complete: a known format and as many rows as its header says
table_is_complete() {
 awk '
  /^# vast_field_catalog / { version = $3 }
  /^# rows / { expected = $3 }
  !/^#/ { n++ }
  END { exit !(version == "1" && expected != "" && n == expected + 0) }' "$1" 2>/dev/null
}

# Cache
CACHE_DIR="${VAST_FIELD_CATALOG_CACHE_DIR:-${VAST_DIR}/lib/catalogs/field_catalog_cache}"
if [ "$CACHE_DIR" = "none" ];then
 CACHE_DIR=""
elif [ ! -d "$CACHE_DIR" ];then
 if ! mkdir -p "$CACHE_DIR" 2>/dev/null ;then
  CACHE_DIR=""
 fi
fi
if [ -n "$CACHE_DIR" ] && [ ! -w "$CACHE_DIR" ];then
 CACHE_DIR=""
fi
if [ -n "$CACHE_DIR" ];then
 # The newest tables first (the file names carry no white space); the loop runs in this
 # shell, so that it can end the script when a cached table will do
 # shellcheck disable=SC2012
 CACHED_TABLES=$(ls -t "$CACHE_DIR"/"$CATALOG"_*.txt 2>/dev/null)
 while IFS= read -r CACHED_TABLE ;do
  if [ -z "$CACHED_TABLE" ];then
   continue
  fi
  if ! table_is_complete "$CACHED_TABLE" ;then
   # An incomplete table is not supposed to get here (tables are renamed into place),
   # but if one does, it is of no use to anybody
   rm -f "$CACHED_TABLE"
   continue
  fi
  # Does it cover every position, with the margin around it, and the magnitude range?
  # (an exit in END replaces the exit status of an earlier exit, hence the flag)
  if awk -v margin="$CONE_MARGIN_ARCSEC" -v a="$MAG_MIN" -v b="$QUERY_MAG_MAX" "$AWK_SPHERE"'
    FNR == NR {
     if ($1 == "#" && $2 == "mag_range") {
      if ($3 + 0 > a + 0 || $4 + 0 < b + 0) { failed = 1; exit }
      magok = 1
     }
     if ($1 == "#" && $2 == "cone") { nc++; cra[nc] = $3; cde[nc] = $4; cr[nc] = $5 }
     next
    }
    NF >= 2 {
     covered = 0
     for (k = 1; k <= nc; k++) {
      # (the radii are written with 7 decimals: allow for their rounding)
      if (sep(cra[k], cde[k], $1, $2) + margin / 3600.0 <= cr[k] + 1e-6) { covered = 1; break }
     }
     if (!covered) { failed = 1; exit }
    }
    END {
     if (failed || !magok || nc == 0) exit 1
     exit 0
    }' <(grep '^#' "$CACHED_TABLE") "$POSITIONS_FILE" ;then
   if cp "$CACHED_TABLE" "$OUTPUT_FILE.tmp$$" && mv -f "$OUTPUT_FILE.tmp$$" "$OUTPUT_FILE" ;then
    touch "$CACHED_TABLE" 2>/dev/null
    echo "Using the $CATALOG_NAME stars cached in $CACHED_TABLE (provider $(awk '$1 == "#" && $2 == "provider" {print $3; exit}' "$CACHED_TABLE"), $(awk '$1 == "#" && $2 == "rows" {print $3; exit}' "$CACHED_TABLE") stars)" >&2
    exit 0
   fi
   rm -f "$OUTPUT_FILE.tmp$$"
  fi
 done <<< "$CACHED_TABLES"
fi

# The ADQL query of provider $1 for the cone $2 $3 $4 (RA Dec radius in degrees)
make_query() {
 local PROVIDER="$1" RA="$2" DEC="$3" RADIUS="$4"
 local BANDS=""
 local BAND
 case "$CATALOG:$PROVIDER" in
  apass:esa)
   echo "SELECT recno, raj2000, dej2000, vmag, bmag, e_bmag, e_vmag, r_mag, e_r_mag, i_mag, e_i_mag, g_mag, e_g_mag FROM external.apassdr9 WHERE 1 = CONTAINS(POINT('ICRS', raj2000, dej2000), CIRCLE('ICRS', $RA, $DEC, $RADIUS)) AND vmag + 0 BETWEEN $MAG_MIN AND $QUERY_MAG_MAX"
   ;;
  apass:skymapper)
   echo "SELECT recno, raj2000, dej2000, vmag, bmag, e_bmag, e_vmag, rmag, e_rmag, imag, e_imag, gmag, e_gmag FROM ext.apass_dr9 WHERE 1 = CONTAINS(POINT('ICRS', raj2000, dej2000), CIRCLE('ICRS', $RA, $DEC, $RADIUS)) AND vmag + 0 BETWEEN $MAG_MIN AND $QUERY_MAG_MAX"
   ;;
  gaia:esa|gaia:ari)
   for BAND in b_jkc v_jkc r_jkc i_jkc g_sdss r_sdss i_sdss ;do
    BANDS="$BANDS, s.${BAND}_mag, 1.0857 * s.${BAND}_flux_error / s.${BAND}_flux AS e_${BAND}_mag, s.${BAND}_flag"
   done
   echo "SELECT g.source_id, g.ra, g.dec, g.pmra, g.pmdec, g.phot_g_mean_mag, g.phot_variable_flag, s.source_id AS gspc_source_id, s.c_star$BANDS FROM gaiadr3.gaia_source AS g LEFT OUTER JOIN gaiadr3.synthetic_photometry_gspc AS s ON s.source_id = g.source_id WHERE 1 = CONTAINS(POINT('ICRS', g.ra, g.dec), CIRCLE('ICRS', $RA, $DEC, $RADIUS)) AND g.phot_g_mean_mag + 0 BETWEEN $MAG_MIN AND $QUERY_MAG_MAX"
   ;;
  *)
   return 1
   ;;
 esac
 return 0
}

# The column names the reply of provider $1 has to start with
expected_header() {
 case "$CATALOG:$1" in
  apass:esa) echo "recno,raj2000,dej2000,vmag,bmag,e_bmag,e_vmag,r_mag,e_r_mag,i_mag,e_i_mag,g_mag,e_g_mag" ;;
  apass:skymapper) echo "recno,raj2000,dej2000,vmag,bmag,e_bmag,e_vmag,rmag,e_rmag,imag,e_imag,gmag,e_gmag" ;;
  gaia:esa|gaia:ari) echo "source_id,ra,dec,pmra,pmdec,phot_g_mean_mag,phot_variable_flag,gspc_source_id,c_star,b_jkc_mag,e_b_jkc_mag,b_jkc_flag,v_jkc_mag,e_v_jkc_mag,v_jkc_flag,r_jkc_mag,e_r_jkc_mag,r_jkc_flag,i_jkc_mag,e_i_jkc_mag,i_jkc_flag,g_sdss_mag,e_g_sdss_mag,g_sdss_flag,r_sdss_mag,e_r_sdss_mag,r_sdss_flag,i_sdss_mag,e_i_sdss_mag,i_sdss_flag" ;;
 esac
}

provider_url() {
 case "$1" in
  esa) echo "https://gea.esac.esa.int/tap-server/tap/sync" ;;
  skymapper) echo "https://api.skymapper.nci.org.au/public/tap/sync" ;;
  ari) echo "https://gaia.ari.uni-heidelberg.de/tap/sync" ;;
 esac
}

# Fetch the cone number $2 for provider $1 into $WORK_DIR/reply_$1_$2.csv and its HTTP
# status into $WORK_DIR/reply_$1_$2.http
fetch_cone() {
 local PROVIDER="$1" K="$2"
 local CONE_WORD CONE_RA CONE_DEC CONE_RADIUS QUERY
 read -r CONE_WORD CONE_RA CONE_DEC CONE_RADIUS < <(sed -n "${K}p" "$WORK_DIR/cones.txt")
 if [ "$CONE_WORD" != "cone" ];then
  return 1
 fi
 QUERY=$(make_query "$PROVIDER" "$CONE_RA" "$CONE_DEC" "$CONE_RADIUS") || return 1
 # VAST_CURL_PROXY holds extra curl options and is split into words on purpose
 # shellcheck disable=SC2086
 curl $VAST_CURL_PROXY --silent --show-error --compressed --connect-timeout 10 --max-time 180 \
  -o "$WORK_DIR/reply_${PROVIDER}_$K.csv" -w '%{http_code}' \
  -d REQUEST=doQuery -d LANG=ADQL -d FORMAT=csv -d MAXREC=$MAX_ROWS \
  --data-urlencode "QUERY=$QUERY" "$(provider_url "$PROVIDER")" > "$WORK_DIR/reply_${PROVIDER}_$K.http" 2> "$WORK_DIR/reply_${PROVIDER}_$K.curl_err"
 return 0
}

# Convert the reply of provider $1 for cone $2 into table rows ($WORK_DIR/rows_$1_$2.txt).
# Return 0 for a complete, valid reply; 2 - not the table that was asked for (an error or
# maintenance page); 3 - a row is not valid; 4 - the reply may be cut at MAX_ROWS rows.
# (The awk program sets "status" and exits; END keeps that status, because an exit in END
# would replace it.)
convert_reply() {
 local PROVIDER="$1" K="$2"
 awk -F, -v number="$NUMBER_REGEX" -v expected="$(expected_header "$PROVIDER")" -v catalog="$CATALOG" -v max_rows="$MAX_ROWS" '
  function val(s) {
   if (s == "") return "0"
   if (s !~ number) { bad = 1; return "0" }
   return s
  }
  function band(m, e, f) {
   # magnitude, error and flag of one band; a missing magnitude leaves all three at 0
   if (m == "") return "0 0 0"
   return val(m) " " val(e) " " val(f)
  }
  { sub(/\r$/, ""); gsub(/"/, "") }
  FNR == 1 {
   if ($0 != expected) { status = 2; exit }
   header_ok = 1
   next
  }
  $0 == "" { next }
  catalog == "apass" {
   if (NF != 13 || $1 !~ /^[0-9]+$/ || $2 == "" || $3 == "" || $4 == "") { status = 3; exit }
   # recno ra dec vmag bmag e_bmag e_vmag r e_r i e_i g e_g
   out = $1 " " val($2) " " val($3) " 0 0 " val($4) " 1 0 0 "
   out = out ($5 == "" ? "0 0 0" : val($5) " " val($6) " 1") " "
   out = out val($4) " " val($7) " 1 0 0 0 0 0 0 "
   out = out ($12 == "" ? "0 0 0" : val($12) " " val($13) " 1") " "
   out = out ($8 == "" ? "0 0 0" : val($8) " " val($9) " 1") " "
   out = out ($10 == "" ? "0 0 0" : val($10) " " val($11) " 1")
  }
  catalog == "gaia" {
   if (NF != 30 || $1 !~ /^[0-9]+$/ || $2 == "" || $3 == "" || $6 == "") { status = 3; exit }
   var = ($7 == "VARIABLE") ? 1 : 0
   inphot = ($8 == "") ? 0 : 1
   out = $1 " " val($2) " " val($3) " " val($4) " " val($5) " " val($6) " " inphot " " val($9) " " var
   for (b = 0; b < 7; b++) out = out " " band($(10 + 3 * b), $(11 + 3 * b), $(12 + 3 * b))
  }
  {
   if (bad) { status = 3; exit }
   n++
   print out
  }
  END {
   if (status) exit status
   if (!header_ok) exit 2
   if (n >= max_rows) exit 4
   exit 0
  }' "$WORK_DIR/reply_${PROVIDER}_$K.csv" > "$WORK_DIR/rows_${PROVIDER}_$K.txt"
}

# Try the providers in order
PROVIDERS="${VAST_FIELD_CATALOG_PROVIDERS:-$DEFAULT_PROVIDERS}"
for PROVIDER in $PROVIDERS ;do
 if [ -z "$(provider_url "$PROVIDER")" ] || ! make_query "$PROVIDER" 0 0 1 > /dev/null ;then
  echo "WARNING: $SCRIPT_NAME: '$PROVIDER' does not serve $CATALOG_NAME - skipping it" >&2
  continue
 fi
 START_UNIXSEC=$(date +%s)
 K=1
 while [ "$K" -le "$N_CONES" ] ;do
  fetch_cone "$PROVIDER" "$K" &
  K=$((K + 1))
 done
 wait
 PROVIDER_OK=1
 K=1
 while [ "$K" -le "$N_CONES" ] ;do
  HTTP_CODE=$(cat "$WORK_DIR/reply_${PROVIDER}_$K.http" 2>/dev/null)
  case "$HTTP_CODE" in
   408|429|5*|000|"")
    echo "WARNING: $SCRIPT_NAME: $PROVIDER replied with HTTP status '${HTTP_CODE:-none}' $(head -c 200 "$WORK_DIR/reply_${PROVIDER}_$K.curl_err" 2>/dev/null) - asking again in $RETRY_PAUSE_SEC s" >&2
    sleep "$RETRY_PAUSE_SEC"
    fetch_cone "$PROVIDER" "$K"
    HTTP_CODE=$(cat "$WORK_DIR/reply_${PROVIDER}_$K.http" 2>/dev/null)
    ;;
  esac
  if [ "$HTTP_CODE" != "200" ];then
   echo "WARNING: $SCRIPT_NAME: $PROVIDER replied with HTTP status '${HTTP_CODE:-none}' for cone $K of $N_CONES" >&2
   PROVIDER_OK=0
   break
  fi
  convert_reply "$PROVIDER" "$K"
  CONVERT_EXIT_CODE=$?
  if [ "$CONVERT_EXIT_CODE" -ne 0 ];then
   case "$CONVERT_EXIT_CODE" in
    2) REASON="it is not the table that was asked for: $(head -c 120 "$WORK_DIR/reply_${PROVIDER}_$K.csv" | tr -c '\040-\176' ' ' | sed -e 's/</[/g' -e 's/>/]/g' -e 's/ERROR/Error/g')" ;;
    4) REASON="it has $MAX_ROWS rows, so it may be cut" ;;
    *) REASON="a row is not valid" ;;
   esac
   echo "WARNING: $SCRIPT_NAME: unusable reply from $PROVIDER for cone $K of $N_CONES: $REASON" >&2
   PROVIDER_OK=0
   break
  fi
  K=$((K + 1))
 done
 if [ "$PROVIDER_OK" -ne 1 ];then
  continue
 fi
 cat "$WORK_DIR"/rows_"${PROVIDER}"_*.txt > "$WORK_DIR/rows_all.txt" || continue
 write_table "$WORK_DIR/rows_all.txt" "$PROVIDER" || continue
 if ! cp "$WORK_DIR/table.txt" "$OUTPUT_FILE.tmp$$" || ! mv -f "$OUTPUT_FILE.tmp$$" "$OUTPUT_FILE" ;then
  rm -f "$OUTPUT_FILE.tmp$$"
  echo "$0: cannot write $OUTPUT_FILE" >&2
  exit 2
 fi
 echo "Fetched $(awk '$1 == "#" && $2 == "rows" {print $3; exit}' "$OUTPUT_FILE") $CATALOG_NAME stars from $PROVIDER for $N_POSITIONS positions ($N_CONES cone(s), up to $(awk '{if ($4 > r) r = $4} END {printf "%.2f", r}' "$WORK_DIR/cones.txt") deg) in $(( $(date +%s) - START_UNIXSEC )) s" >&2
 if [ -n "$CACHE_DIR" ];then
  CACHE_FILE="$CACHE_DIR/${CATALOG}_$(date +%s)_$$.txt"
  if cp "$WORK_DIR/table.txt" "$CACHE_FILE.tmp" 2>/dev/null && mv -f "$CACHE_FILE.tmp" "$CACHE_FILE" 2>/dev/null ;then
   # Keep the cache below CACHE_MAX_MB: remove the tables used least recently (a table is
   # touched when it is used), but never the one just written
   # shellcheck disable=SC2012
   ls -t "$CACHE_DIR"/*.txt 2>/dev/null | while IFS= read -r CACHED_TABLE ;do
    echo "$(wc -c < "$CACHED_TABLE" 2>/dev/null | tr -d ' ') $CACHED_TABLE"
   done | awk -v limit_mb="$CACHE_MAX_MB" -v keep="$CACHE_FILE" '{
    total += $1
    name = substr($0, index($0, " ") + 1)
    if (total > limit_mb * 1048576 && name != keep) print name
   }' | while IFS= read -r OLD_TABLE ;do
    rm -f "$OLD_TABLE"
   done
  else
   rm -f "$CACHE_FILE.tmp"
  fi
 fi
 exit 0
done
echo "WARNING: $SCRIPT_NAME: no provider delivered the $CATALOG_NAME stars (tried: $PROVIDERS)" >&2
exit 2
