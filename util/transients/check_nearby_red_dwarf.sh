#!/usr/bin/env bash
#
# UV Ceti check: is there a nearby red dwarf at the position of a transient candidate?
#
# A UV Ceti-type flare on a K or M dwarf closer than 200 pc is the most common kind of
# short-lived brightening a wide-field transient search picks up. The check looks for
# Gaia DR3 sources with parallax > 5 mas (closer than 200 pc) around the position, moves
# each of them from the Gaia epoch 2016.0 to the epoch of the observation with its proper
# motion (nearby stars move by arcseconds in a decade), and reports the one that lands at
# the position: its distance, G, BP-RP, absolute magnitude M_G and where it sits with
# respect to the main sequence of K/M dwarfs. A red dwarf on or above the main sequence
# makes a UV Ceti-type flare the likely explanation. A star far below the main sequence is
# a white dwarf + red dwarf binary or a cataclysmic variable rather than a single red dwarf.
#
# Usage:
#   util/transients/check_nearby_red_dwarf.sh RA DEC [EPOCH] [MATCH_RADIUS_ARCSEC]
#
#   RA DEC   J2000/ICRS position, sexagesimal (04:49:22.53 +29:26:01.6) or decimal degrees
#   EPOCH    when the candidate was observed: a JD (2461353.7293), a decimal year (2026.855)
#            or a date (2026-11-09 or 2026-11-09T05:29:41); the default is now
#   MATCH_RADIUS_ARCSEC  how close the propagated Gaia position must be, default 5.0
#            (the transient search passes its catalog-match tolerance, the image scale)
#
# Where the Gaia DR3 stars come from (the first one that works):
#   1. the local copy lib/catalogs/gaia_dr3_nearby installed by
#      lib/install_local_copy_of_GaiaDR3_nearby_stars.sh (no network, instant),
#   2. the ESA Gaia archive (TAP, 1-90 s),
#   3. the Gaia DR3 table I/355/gaiadr3 at a VizieR mirror (lib/vizquery).
#
# Output: one line on stdout, meant to be printed as is in the HTML candidate report:
#   UV Ceti check (Gaia DR3 stars closer than 200 pc, SOURCE, positions at EPOCH): ...
# The line never contains the phrases the report parsers key on ('The object was',
# 'found in', 'not found', 'mag brighter than the'), see .claude/notes.md.
#
# Exit codes:
#   0  a nearby red dwarf (K or M dwarf on, above or slightly below the main sequence) is
#      at the position: a UV Ceti-type flare is likely
#   1  no star closer than 200 pc at the position (the search was completed)
#   2  a nearby star is at the position, but it is not a single red dwarf (far below the
#      main sequence, bluer than K0, a giant)
#   3  the check could not be done (no local copy and no reply from the online services)
#   4  usage error
#
# Environment variables:
#   UVCETI_SOURCE           auto (default), local, esa_tap or vizquery: where to take the stars from
#   UVCETI_LOCAL_CATALOG    the local copy, default lib/catalogs/gaia_dr3_nearby
#   UVCETI_MAX_DISTANCE_PC  200: stars with a parallax below 1000/this are not considered
#   UVCETI_MIN_PLX_OVER_ERROR  3: stars with a less significant parallax are not considered
#   UVCETI_MIN_BP_RP        1.0: the bluest 'red dwarf' colour (K0V has BP-RP = 0.98)
#   UVCETI_MIN_G_RP         0.58: the same limit in G-RP, used when BP is missing or unreliable
#   UVCETI_BP_UNRELIABLE_G  19.5: G-RP places stars fainter than this (BP is biased there)
#   UVCETI_MAX_PM_ARCSEC_YR 11: the search cone grows by this times the years since 2016.0
#                           (Barnard's star moves 10.4"/yr, the fastest star known)
#   UVCETI_ESA_TIMEOUT_SEC  90: time limit of one ESA TAP query
#   VIZIER_SITE, VIZIER_UNREACHABLE  from the transient search; without them the mirror is
#                           chosen with lib/choose_vizier_mirror.sh
#   UVCETI_VERBOSE          yes: list every nearby star in the cone on stderr
#
# The main-sequence locus and the spectral type labels come from the Pecaut & Mamajek
# (2013, and the 2022 update of their online table) dwarf colour sequence with G - V from
# the Gaia DR2 photometric relations; they are good to about 0.3 mag. The intrinsic width
# of the main sequence (metallicity, age, unresolved binaries) is about 0.5 mag, which is
# added to the parallax error when the distance from the main sequence is expressed in
# sigmas. BP-RP places the star; BP of faint red stars (G > 19.5) is biased by background
# flux, so G-RP takes over for them and for stars without BP. G-RP is not used as a
# cross-check: the main sequence is too steep in G-RP for late M dwarfs (UV Cet itself would
# land 1.6 mag below the locus by G-RP while it sits on it by BP-RP).

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Find the VaST directory (this script lives in util/transients/) and work from there
VAST_DIR=$(cd "$(dirname "$0")/../.." && pwd)
if [ -z "$VAST_DIR" ] || ! cd "$VAST_DIR" ;then
 echo "UV Ceti check: not performed (cannot change to the VaST directory)"
 exit 3
fi

: "${UVCETI_SOURCE:=auto}"
: "${UVCETI_LOCAL_CATALOG:=lib/catalogs/gaia_dr3_nearby}"
: "${UVCETI_MAX_DISTANCE_PC:=200}"
: "${UVCETI_MIN_PLX_OVER_ERROR:=3}"
: "${UVCETI_MIN_BP_RP:=1.0}"
: "${UVCETI_MIN_G_RP:=0.58}"
: "${UVCETI_BP_UNRELIABLE_G:=19.5}"
: "${UVCETI_MAX_PM_ARCSEC_YR:=11}"
: "${UVCETI_ESA_TIMEOUT_SEC:=90}"
: "${UVCETI_TAP_URL:=https://gea.esac.esa.int/tap-server/tap}"
# the main-sequence band: a star this much above or below the locus is still 'on' it, a
# red star further below than the second limit (and by more than UVCETI_MS_MIN_SIGMA) is
# far below it
UVCETI_MS_HALFWIDTH_MAG=1.0
UVCETI_MS_FAR_BELOW_MAG=2.5
UVCETI_MS_MIN_SIGMA=3.0
GAIA_DR3_EPOCH=2016.0
GAIA_DR3_EPOCH_JD=2457389.0

print_usage() {
 echo "Usage: $0 RA DEC [EPOCH] [MATCH_RADIUS_ARCSEC]
 RA DEC are sexagesimal (04:49:22.53 +29:26:01.6) or decimal degrees,
 EPOCH is a JD, a decimal year or a date (2026-11-09 or 2026-11-09T05:29:41), default now,
 MATCH_RADIUS_ARCSEC defaults to 5.0" 1>&2
}

if [ -z "$1" ] || [ -z "$2" ] || [ "$1" = "-h" ] || [ "$1" = "--help" ];then
 print_usage
 exit 4
fi

# ---------- the position in degrees ----------
# sexagesimal RA/Dec or decimal degrees; prints "RA_DEG DEC_DEG" or nothing when unparsable
parse_position() {
 echo "$1 $2" | awk '
 function angle(s, is_ra,   sign, n, a, parts) {
  sign = 1;
  if (substr(s, 1, 1) == "-") { sign = -1; s = substr(s, 2) }
  else if (substr(s, 1, 1) == "+") { s = substr(s, 2) }
  if (index(s, ":") > 0) {
   n = split(s, parts, ":");
   if (n < 2) return "bad";
   a = parts[1] + parts[2] / 60.0;
   if (n >= 3) a += parts[3] / 3600.0;
   if (is_ra) a *= 15.0;
   return sign * a;
  }
  if (s !~ /^[0-9]*\.?[0-9]+([eE][-+]?[0-9]+)?$/) return "bad";
  return sign * s;
 }
 {
  ra = angle($1, 1); dec = angle($2, 0);
  if (ra == "bad" || dec == "bad") exit;
  if (ra < 0.0 || ra >= 360.0 || dec < -90.0 || dec > 90.0) exit;
  printf "%.8f %.8f\n", ra, dec;
 }'
}
POSITION_DEG=$(parse_position "$1" "$2")
if [ -z "$POSITION_DEG" ];then
 echo "ERROR: cannot parse the position '$1 $2'" 1>&2
 print_usage
 exit 4
fi
RA_DEG=${POSITION_DEG% *}
DEC_DEG=${POSITION_DEG#* }

# ---------- the epoch as a decimal (Julian) year ----------
EPOCH_INPUT="$3"
if [ -z "$EPOCH_INPUT" ];then
 EPOCH_INPUT=$(date -u +%Y-%m-%dT%H:%M:%S)
fi
EPOCH_YEAR=$(echo "$EPOCH_INPUT" | awk -v jd0="$GAIA_DR3_EPOCH_JD" -v y0="$GAIA_DR3_EPOCH" '
 function jd_from_date(y, m, d, hh, mm, ss,   a, y2, m2, jdn) {
  a = int((14 - m) / 12); y2 = y + 4800 - a; m2 = m + 12 * a - 3;
  jdn = d + int((153 * m2 + 2) / 5) + 365 * y2 + int(y2 / 4) - int(y2 / 100) + int(y2 / 400) - 32045;
  return jdn - 0.5 + (hh + mm / 60.0 + ss / 3600.0) / 24.0;
 }
 {
  s = $1;
  if (s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]?-[0-9][0-9]?(T[0-9][0-9]?(:[0-9][0-9]?(:[0-9][0-9]?(\.[0-9]*)?)?)?)?$/) {
   n = split(s, dt, "T"); split(dt[1], ymd, "-"); hh = 0; mm = 0; ss = 0;
   if (n > 1) { k = split(dt[2], hms, ":"); hh = hms[1]; if (k > 1) mm = hms[2]; if (k > 2) ss = hms[3] }
   jd = jd_from_date(ymd[1] + 0, ymd[2] + 0, ymd[3] + 0, hh + 0, mm + 0, ss + 0);
   printf "%.4f\n", y0 + (jd - jd0) / 365.25; exit;
  }
  if (s !~ /^[0-9]*\.?[0-9]+$/) exit;
  v = s + 0;
  if (v > 2400000.0) { printf "%.4f\n", y0 + (v - jd0) / 365.25; exit }
  if (v > 1900.0 && v < 2200.0) { printf "%.4f\n", v; exit }
 }')
if [ -z "$EPOCH_YEAR" ];then
 echo "ERROR: cannot understand the epoch '$EPOCH_INPUT' (a JD, a decimal year or YYYY-MM-DD[THH:MM:SS])" 1>&2
 print_usage
 exit 4
fi

# ---------- the match radius ----------
MATCH_RADIUS_ARCSEC="${4:-5.0}"
if ! echo "$MATCH_RADIUS_ARCSEC" | grep -q -E '^[0-9]*\.?[0-9]+$' || ! awk -v r="$MATCH_RADIUS_ARCSEC" 'BEGIN { exit (r > 0.0 && r < 3600.0) ? 0 : 1 }' ;then
 echo "ERROR: bad MATCH_RADIUS_ARCSEC '$MATCH_RADIUS_ARCSEC'" 1>&2
 print_usage
 exit 4
fi

# The cone to search at the Gaia epoch: a star may have moved from anywhere within
# the proper motion times the epoch difference, but never less than 60"
SEARCH_RADIUS_ARCSEC=$(awk -v r="$MATCH_RADIUS_ARCSEC" -v dt="$EPOCH_YEAR" -v y0="$GAIA_DR3_EPOCH" -v pm="$UVCETI_MAX_PM_ARCSEC_YR" 'BEGIN { d = dt - y0; if (d < 0) d = -d; s = r + pm * d; if (s < 60.0) s = 60.0; printf "%.1f", s }')
MIN_PARALLAX_MAS=$(awk -v d="$UVCETI_MAX_DISTANCE_PC" 'BEGIN { printf "%.4f", 1000.0 / d }')

# ---------- the Gaia DR3 stars in the cone ----------
# Every source is turned into lines of 12 space-separated columns:
#   source_id ra dec parallax parallax_error pmra pmdec G BP RP RUWE var_flag
# (degrees, mas, mas/yr, mag; a missing value is the word null)
STARS=""
STARS_SOURCE=""
FAILURE_REASONS=""

# the local copy built by lib/install_local_copy_of_GaiaDR3_nearby_stars.sh
stars_from_local_copy() {
 local REPLY
 if [ ! -x lib/catalogs/local_star_catalog ] || [ ! -s "$UVCETI_LOCAL_CATALOG/catalog_info.txt" ];then
  FAILURE_REASONS="$FAILURE_REASONS no local copy of the Gaia DR3 nearby stars;"
  return 1
 fi
 if ! REPLY=$(lib/catalogs/local_star_catalog search -cat=gaia_dr3_nearby:"$UVCETI_LOCAL_CATALOG" -c="$RA_DEG $DEC_DEG" -c.rs="$SEARCH_RADIUS_ARCSEC" -out.max=1000 -sort=_r 2>/dev/null) || ! echo "$REPLY" | grep -q '#END#' ;then
  FAILURE_REASONS="$FAILURE_REASONS the local copy of the Gaia DR3 nearby stars could not be read;"
  return 1
 fi
 # data lines: _r Source RA_ICRS DE_ICRS Gmag BPmag RPmag Plx e_Plx pmRA pmDE RUWE Var
 # (99.9999 = no magnitude; the word null = no parallax error or no proper motion in the
 # catalog, passed through as is; the parallax itself is always present and may well be
 # several hundred mas - AD Leo has 201 mas - so no number stands for 'unknown' there)
 STARS=$(echo "$REPLY" | awk 'NF == 13 && $1 ~ /^[0-9.]+$/ && $2 ~ /^[0-9]+$/ {
  g = ($5 >= 99.0) ? "null" : $5; bp = ($6 >= 99.0) ? "null" : $6; rp = ($7 >= 99.0) ? "null" : $7;
  ruwe = ($12 == "null" || $12 <= 0.0) ? "null" : $12;
  print $2, $3, $4, $8, $9, $10, $11, g, bp, rp, ruwe, $13 }')
 STARS_SOURCE="local copy"
 return 0
}

# the ESA Gaia archive, the same checks of the reply as in lib/gaia_dr2_cone_search.sh
stars_from_esa_archive() {
 local RADIUS_DEG
 local ADQL
 local RESPONSE
 local CURL_EXIT
 local HTTP_STATUS
 if ! command -v curl &>/dev/null ;then
  FAILURE_REASONS="$FAILURE_REASONS no curl for the ESA archive;"
  return 1
 fi
 RADIUS_DEG=$(awk -v r="$SEARCH_RADIUS_ARCSEC" 'BEGIN { printf "%.7f", r / 3600.0 }')
 ADQL="SELECT TOP 1000 source_id, ra, dec, parallax, parallax_error, pmra, pmdec, phot_g_mean_mag, phot_bp_mean_mag, phot_rp_mean_mag, ruwe, phot_variable_flag FROM gaiadr3.gaia_source WHERE 1=CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', $RA_DEG, $DEC_DEG, $RADIUS_DEG)) AND parallax > $MIN_PARALLAX_MAS AND parallax_over_error > $UVCETI_MIN_PLX_OVER_ERROR"
 RESPONSE=$(curl -s --max-time "$UVCETI_ESA_TIMEOUT_SEC" -w '\n%{http_code}' "$UVCETI_TAP_URL/sync" -d "REQUEST=doQuery" -d "LANG=ADQL" -d "FORMAT=csv" --data-urlencode "QUERY=$ADQL" 2>/dev/null)
 CURL_EXIT=$?
 HTTP_STATUS=$(echo "$RESPONSE" | tail -n 1)
 RESPONSE=$(echo "$RESPONSE" | sed '$d')
 if [ "$CURL_EXIT" -ne 0 ];then
  FAILURE_REASONS="$FAILURE_REASONS no complete reply from the ESA archive within $UVCETI_ESA_TIMEOUT_SEC s;"
  return 1
 fi
 if [ "$HTTP_STATUS" != "200" ];then
  FAILURE_REASONS="$FAILURE_REASONS the ESA archive replied with HTTP status $HTTP_STATUS;"
  return 1
 fi
 # the first line must be the header of the requested table, not an error or web page
 if [ "$(echo "$RESPONSE" | head -n 1 | cut -d, -f1 | tr -d '\r')" != "source_id" ];then
  FAILURE_REASONS="$FAILURE_REASONS the ESA archive reply is not the requested table;"
  return 1
 fi
 STARS=$(echo "$RESPONSE" | tr -d '\r' | awk -F, 'NR > 1 && NF >= 12 && $1 ~ /^[0-9]+$/ {
  for (i = 1; i <= 12; i++) if ($i == "") $i = "null";
  print $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12 }')
 STARS_SOURCE="ESA archive"
 return 0
}

# VizieR: the Gaia DR3 main table I/355/gaiadr3 as tab-separated values (empty fields
# are kept in TSV, in the text format they would shift the columns)
stars_from_vizier() {
 local TIMEOUT_COMMAND
 local REPLY
 local MIRROR
 if [ ! -x lib/vizquery ];then
  FAILURE_REASONS="$FAILURE_REASONS no lib/vizquery;"
  return 1
 fi
 if [ "$VIZIER_UNREACHABLE" = "yes" ];then
  FAILURE_REASONS="$FAILURE_REASONS VizieR unreachable;"
  return 1
 fi
 MIRROR="$VIZIER_SITE"
 if [ -z "$MIRROR" ] && [ -x lib/choose_vizier_mirror.sh ];then
  MIRROR=$(lib/choose_vizier_mirror.sh 2>/dev/null | head -n 1)
 fi
 if [ -z "$MIRROR" ];then
  FAILURE_REASONS="$FAILURE_REASONS no VizieR mirror answers;"
  return 1
 fi
 TIMEOUT_COMMAND=""
 if [ -x lib/find_timeout_command.sh ];then
  TIMEOUT_COMMAND="$(lib/find_timeout_command.sh) 180"
 fi
 # A mirror in trouble may answer with a complete but empty table (vizier.cfa.harvard.edu
 # did so on 2026-11-09 for every query), which would pass as 'no nearby star here'. Gaia
 # DR3 has stars within 5' of any position, so a control query without constraints must
 # list at least one star before the reply to the real query is trusted.
 # shellcheck disable=SC2086
 REPLY=$($TIMEOUT_COMMAND lib/vizquery -site="$MIRROR" -mime=tsv -source=I/355/gaiadr3 -out.max=1 -out.add=_r -sort=_r -c="$RA_DEG $DEC_DEG" -c.rs=300 -out=Source 2>/dev/null)
 if ! echo "$REPLY" | tr -d '\r' | awk -F'\t' '$1 !~ /^#/ && NF >= 2 && $2 ~ /^[0-9]+$/ { found = 1 } END { exit found ? 0 : 1 }' ;then
  FAILURE_REASONS="$FAILURE_REASONS VizieR ($MIRROR) lists no Gaia DR3 star at all around the position, so its reply cannot be trusted;"
  return 1
 fi
 # shellcheck disable=SC2086
 REPLY=$($TIMEOUT_COMMAND lib/vizquery -site="$MIRROR" -mime=tsv -source=I/355/gaiadr3 -out.max=1000 -out.add=_r -sort=_r -c="$RA_DEG $DEC_DEG" -c.rs="$SEARCH_RADIUS_ARCSEC" "Plx=$MIN_PARALLAX_MAS..9999" "RPlx=$UVCETI_MIN_PLX_OVER_ERROR..9999" -out=Source,RA_ICRS,DE_ICRS,Plx,e_Plx,pmRA,pmDE,Gmag,BPmag,RPmag,RUWE,VarFlag 2>/dev/null)
 # a complete reply describes the requested columns, whether or not any star is listed
 if ! echo "$REPLY" | grep -q -E '^#Column[[:space:]]+Source|^_r[[:space:]]+Source' ;then
  FAILURE_REASONS="$FAILURE_REASONS no complete reply from VizieR ($MIRROR);"
  return 1
 fi
 # data lines: _r Source RA_ICRS DE_ICRS Plx e_Plx pmRA pmDE Gmag BPmag RPmag RUWE VarFlag
 STARS=$(echo "$REPLY" | tr -d '\r' | awk -F'\t' '$1 !~ /^#/ && NF >= 13 && $2 ~ /^[0-9]+$/ && $1 ~ /^[0-9.]+$/ {
  for (i = 1; i <= 13; i++) { gsub(/^ +| +$/, "", $i); if ($i == "") $i = "null" }
  print $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13 }')
 STARS_SOURCE="VizieR"
 return 0
}

GOT_STARS=0
case "$UVCETI_SOURCE" in
 local)
  stars_from_local_copy && GOT_STARS=1
  ;;
 esa_tap)
  stars_from_esa_archive && GOT_STARS=1
  ;;
 vizquery)
  stars_from_vizier && GOT_STARS=1
  ;;
 *)
  if stars_from_local_copy || stars_from_esa_archive || stars_from_vizier ;then
   GOT_STARS=1
  fi
  ;;
esac
if [ "$GOT_STARS" -ne 1 ];then
 FAILURE_REASONS=$(echo "$FAILURE_REASONS" | sed 's/^ *//; s/;$//')
 echo "UV Ceti check: not performed ($FAILURE_REASONS)"
 exit 3
fi

# ---------- propagate, match and classify ----------
echo "$STARS" | awk -v ra0="$RA_DEG" -v dec0="$DEC_DEG" -v epoch="$EPOCH_YEAR" -v epoch0="$GAIA_DR3_EPOCH" \
 -v rmatch="$MATCH_RADIUS_ARCSEC" -v rsearch="$SEARCH_RADIUS_ARCSEC" -v maxdist="$UVCETI_MAX_DISTANCE_PC" \
 -v minplx="$MIN_PARALLAX_MAS" -v minoe="$UVCETI_MIN_PLX_OVER_ERROR" -v minbprp="$UVCETI_MIN_BP_RP" -v mingrp="$UVCETI_MIN_G_RP" \
 -v mshalf="$UVCETI_MS_HALFWIDTH_MAG" -v msfar="$UVCETI_MS_FAR_BELOW_MAG" -v minsigma="$UVCETI_MS_MIN_SIGMA" \
 -v bpfaintg="$UVCETI_BP_UNRELIABLE_G" -v source="$STARS_SOURCE" -v verbose="$UVCETI_VERBOSE" '
function sep_arcsec(ra1, dec1, ra2, dec2,   d2r, sdd, sdr, a) {
 d2r = 3.14159265358979323846 / 180.0;
 sdd = sin((dec2 - dec1) * d2r / 2.0); sdr = sin((ra2 - ra1) * d2r / 2.0);
 a = sdd * sdd + cos(dec1 * d2r) * cos(dec2 * d2r) * sdr * sdr;
 if (a > 1.0) a = 1.0; if (a < 0.0) a = 0.0;
 return 2.0 * atan2(sqrt(a), sqrt(1.0 - a)) / d2r * 3600.0;
}
function log10(x) { return log(x) / log(10.0) }
# piecewise-linear interpolation in a table of n points (flat beyond the ends)
function interp(x, xs, ys, n,   i, f) {
 if (x <= xs[1]) return ys[1];
 if (x >= xs[n]) return ys[n];
 for (i = 1; i < n; i++) if (x < xs[i + 1]) { f = (x - xs[i]) / (xs[i + 1] - xs[i]); return ys[i] + f * (ys[i + 1] - ys[i]) }
 return ys[n];
}
function nearest_type(x, xs, n,   i, best, bestd, d) {
 best = 1; bestd = 1.0e9;
 for (i = 1; i <= n; i++) { d = x - xs[i]; if (d < 0) d = -d; if (d < bestd) { bestd = d; best = i } }
 return best;
}
function fmt_sep(s) { return (s < 10.0) ? sprintf("%.1f\"", s) : sprintf("%.0f\"", s) }
BEGIN {
 # the dwarf sequence: spectral type, BP-RP, G-RP, M_G (Pecaut & Mamajek with G-V from the
 # Gaia DR2 photometric relations, about 0.3 mag accurate)
 n = split("K0 K2 K5 K7 M0 M1 M2 M3 M4 M5 M6 M7 M8 M9", type, " ");
 split("0.98 1.10 1.39 1.60 1.84 1.98 2.17 2.50 2.84 3.36 3.84 4.25 4.60 4.80", bprp_tab, " ");
 split("0.58 0.63 0.78 0.88 0.98 1.04 1.10 1.20 1.30 1.43 1.52 1.58 1.63 1.67", grp_tab, " ");
 split("5.6 6.2 7.1 7.8 8.4 9.1 9.55 10.2 11.35 12.4 14.0 14.8 15.4 16.0", mg_tab, " ");
 for (i = 1; i <= n; i++) { bprp_tab[i] += 0; grp_tab[i] += 0; mg_tab[i] += 0 }
 dt = epoch - epoch0;
 d2r = 3.14159265358979323846 / 180.0;
 nstars = 0; nmatch = 0; best = 0; nearest = 1.0e9;
 prefix = sprintf("UV Ceti check (Gaia DR3 stars closer than %d pc, %s, positions at %.3f):", maxdist, source, epoch);
}
NF >= 12 && $1 ~ /^[0-9]+$/ {
 id = $1; ra = $2 + 0; dec = $3 + 0; plx = $4; eplx = $5; pmra = $6; pmdec = $7; g = $8; bp = $9; rp = $10; ruwe = $11; var = $12;
 if (plx == "null") next;
 plx += 0;
 if (!(plx > minplx)) next;
 if (eplx == "null") next;
 eplx += 0;
 if (eplx <= 0.0 || plx / eplx < minoe) next;
 nstars++;
 # move the star from the Gaia epoch to the epoch of the observation
 ra1 = ra; dec1 = dec; haspm = 1;
 if (pmra == "null" || pmdec == "null") { haspm = 0 } else {
  pmra += 0; pmdec += 0;
  dec1 = dec + pmdec * dt / 3.6e6;
  if (dec < 89.99 && dec > -89.99) ra1 = ra + pmra * dt / 3.6e6 / cos(dec * d2r);
  if (ra1 < 0.0) ra1 += 360.0; if (ra1 >= 360.0) ra1 -= 360.0;
 }
 sep0 = sep_arcsec(ra0, dec0, ra, dec);
 sep1 = sep_arcsec(ra0, dec0, ra1, dec1);
 if (verbose == "yes") printf "Gaia DR3 %s: %s at %.1f, %s at %.1f, plx %.2f +/- %.2f mas, pm %s %s mas/yr, G %s BP %s RP %s RUWE %s %s\n", id, fmt_sep(sep0), epoch0, fmt_sep(sep1), epoch, plx, eplx, pmra, pmdec, g, bp, rp, ruwe, var > "/dev/stderr";
 if (sep1 < nearest) nearest = sep1;
 if (sep1 > rmatch) next;
 nmatch++;
 if (best == 0 || sep1 < best_sep1) {
  best = 1; best_id = id; best_sep0 = sep0; best_sep1 = sep1; best_plx = plx; best_eplx = eplx; best_g = g; best_bp = bp; best_rp = rp; best_ruwe = ruwe; best_var = var; best_haspm = haspm;
 }
}
END {
 if (nstars == 0 || best == 0) {
  if (nstars == 0) printf "%s no such star within %s of the position.\n", prefix, fmt_sep(rsearch);
  else printf "%s no such star within %s of the position (the nearest is %s away).\n", prefix, fmt_sep(rmatch), fmt_sep(nearest);
  exit 1;
 }
 more = (nmatch > 1) ? sprintf(" (and %d more within %s)", nmatch - 1, fmt_sep(rmatch)) : "";
 dist = 1000.0 / best_plx; edist = dist * best_eplx / best_plx;
 where = sprintf("Gaia DR3 %s at %s (%s at %.1f)%s, d = %.0f +/- %.0f pc", best_id, fmt_sep(best_sep1), fmt_sep(best_sep0), epoch0, more, dist, edist);
 if (best_haspm == 0) where = where ", no proper motion in Gaia";
 if (best_g == "null") {
  printf "%s %s, no G magnitude in Gaia: cannot tell what kind of star it is.\n", prefix, where;
  exit 2;
 }
 g = best_g + 0;
 absmag = g + 5.0 * log10(best_plx) - 10.0;
 sigma_abs = 2.1715 * best_eplx / best_plx;
 sigma_tot = sqrt(sigma_abs * sigma_abs + 0.5 * 0.5);
 have_bprp = (best_bp != "null" && best_rp != "null");
 have_grp = (best_rp != "null");
 colours = sprintf("G = %.2f", g);
 if (have_bprp) { bprp = best_bp - best_rp; colours = colours sprintf(", BP-RP = %.2f", bprp) }
 if (have_grp) { grp = g - best_rp; if (!have_bprp) colours = colours sprintf(", G-RP = %.2f", grp) }
 if (!have_grp) {
  printf "%s %s, %s, M_G = %.1f: no Gaia colour, cannot tell whether it is a red dwarf.\n", prefix, where, colours, absmag;
  exit 2;
 }
 # The colour that places the star, and its offset from the main sequence (positive =
 # below). BP-RP decides whenever BP exists and the star is brighter than bpfaintg: BP
 # of fainter stars is biased by background flux. G-RP is only the fallback: the main
 # sequence is so steep in G-RP for late M dwarfs that a 0.1 mag colour difference means
 # 1.5 mag in M_G (UV Cet itself, BP-RP 3.83 and G-RP 1.39, would land 1.6 mag below the
 # locus by G-RP), so it cannot serve as a cross-check.
 if (have_bprp && g <= bpfaintg) {
  off = absmag - interp(bprp, bprp_tab, mg_tab, n);
  itype = nearest_type(bprp, bprp_tab, n);
  isred = (bprp >= minbprp);
  colour_note = "";
 } else {
  off = absmag - interp(grp, grp_tab, mg_tab, n);
  itype = nearest_type(grp, grp_tab, n);
  isred = (grp >= mingrp);
  if (have_bprp) colour_note = sprintf(" (G-RP is used: BP is unreliable at G > %.1f)", bpfaintg);
  else colour_note = " (no BP, G-RP is used)";
 }
 nsigma = (off < 0 ? -off : off) / sigma_tot;
 ident = sprintf("%s, %s, M_G = %.1f", where, colours, absmag);
 if (absmag < 4.0) {
  printf "%s %s is a giant or subgiant%s: not a red dwarf, a flare is unlikely.\n", prefix, ident, colour_note;
  exit 2;
 }
 if (!isred) {
  if (absmag > 10.0) printf "%s %s is a white dwarf (blue and faint)%s: not a red dwarf; a brightening here may still come from an unseen companion.\n", prefix, ident, colour_note;
  else printf "%s %s is a dwarf earlier than K0%s: not a red dwarf, a large flare is unlikely.\n", prefix, ident, colour_note;
  exit 2;
 }
 if (off > msfar && nsigma >= minsigma) {
  printf "%s %s is %.1f mag (%.0f sigma) below the main sequence%s: a white dwarf + red dwarf binary or a cataclysmic variable rather than a single red dwarf; the brightening may be a flare on the red dwarf companion or a dwarf nova outburst.\n", prefix, ident, off, nsigma, colour_note;
  exit 2;
 }
 if (off > mshalf && nsigma >= minsigma) {
  printf "%s %s is %.1f mag (%.0f sigma) below the main sequence (a metal-poor subdwarf or a composite system, about %s)%s: a UV Ceti-type flare is plausible.\n", prefix, ident, off, nsigma, type[itype], colour_note;
  exit 0;
 }
 if (off < -mshalf && nsigma >= minsigma) {
  printf "%s %s is %.1f mag above the main sequence (a young star or an unresolved binary, about %s)%s: a UV Ceti-type flare is likely.\n", prefix, ident, -off, type[itype], colour_note;
  exit 0;
 }
 printf "%s %s is on the main sequence (about %s dwarf)%s: a UV Ceti-type flare is likely.\n", prefix, ident, type[itype], colour_note;
 exit 0;
}'
exit $?
