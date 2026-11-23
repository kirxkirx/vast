#!/usr/bin/env bash
#
# Test of the photometric field catalogs: lib/photometric_field_catalog.sh, which fetches the
# APASS DR9 or Gaia DR3 synthetic photometry stars around the reference stars of an image, and
# the code of util/solve_plate_with_UCAC5 that matches them to the image stars and rejects the
# matches with discrepant positions (search_photometric_field_catalog() and
# reject_photometric_catalog_position_outliers() in src/solve_plate_with_UCAC5.c).
#
# Nothing is asked from the real services. A 'curl' script put first in PATH stands in for the
# TAP services (ESA Gaia Archive, SkyMapper, ARI) and for VizieR: it answers the cone queries
# from lists of sky stars this script writes, or with the failure a check needs, and records
# every request. The sky stars are made for the reference stars of the test image, and their
# magnitudes encode the number of the reference star they are made for, so the output catalog
# of the plate solver shows which image star got which photometry.
#
# The fetcher:
#  - the query: the catalog table, one cone, the magnitude range written as "+ 0 BETWEEN"
#    (with "vmag BETWEEN" the ESA archive may scan the table by magnitude and time out),
#    MAXREC, no ORDER BY; four cones for a wide field, each covering its positions and the
#    match radius around them; 60 arcsec wider cones for Gaia (proper motions);
#  - the table it writes: the header, a row per star, missing values as 0, CR LF line ends and
#    quoted values of a reply;
#  - replies it has to refuse and go on with the next provider, without the word ERROR in its
#    messages: the maintenance page ESA serves with HTTP 200, another header, a value that is
#    not a number, a reply of MAXREC rows (it may be cut), HTTP errors and no reply (asked
#    once more first); when no provider delivers, it writes nothing and exits with code 2;
#  - its cache: a table is reused for positions and magnitude ranges it covers and only for
#    those, an incomplete table is removed, the size limit is kept;
#  - bad arguments end it before any request; its temporary directory is removed.
# The plate solver runs on the plate-solved NMW archive image wcs_fd_Per3_2011-10-31_001.fts
# of the VaST test data. It matches the stars with UCAC5 before it asks for photometry, so this
# part needs the local UCAC5 copy (lib/catalogs/ucac5) and is reported as not performed where
# there is none:
#  - each reference star gets the photometry of the brightest catalog star within the search
#    radius, or none if that star has no usable photometry (a fainter neighbour does not stand
#    in); APASS needs B, V, r' and i'; a Gaia star needs synthetic photometry, no VARIABLE flag
#    and |c_star| <= 0.1; stars outside the magnitude range are not considered;
#  - the Cousins R and I magnitudes derived from APASS follow the published relations of
#    Jester et al. (2005), V - R = 1.09 (r - i) + 0.22 and R - I = 1.00 (r - i) + 0.21, checked
#    in this form: the check restates the paper, not the code (a check that copied the code
#    would have kept the sign error that made every APASS Ic 0.42 mag too faint until
#    2026-11-23); Gaia gives Rc and Ic directly and its errors are raised to 0.01 mag;
#  - Gaia positions are moved from 2016.0 to the epoch of the image with their proper motions;
#  - the positional cut rejects exactly the matches more than 5 robust sigmas from the median
#    offset (sigma at least 1 arcsec), and is not applied to fewer than 20 matches;
#  - the order of the sources: Gaia (with VAST_PHOTOMETRIC_CATALOG=gaia), APASS from ESA, then
#    SkyMapper, then the APASS list query via VizieR (for at most 1000 reference stars), then
#    Pan-STARRS1; a complete field catalog with too few matches is not asked again elsewhere;
#  - a second run on the same field uses the cached table and makes no request.
#
# Usage: util/examples/test_photometric_field_catalog.sh
# The script works in the VaST directory it belongs to. The image is expected in
# ../individual_images_test (next to the VaST directory) and is downloaded if it is not there.
# The script prints "FAILED: CODE description" for every failed check and
# "NOT_PERFORMED: CODE reason" if the plate solver part could not run; it exits with code 1
# if any check failed and with 0 otherwise. At the end it puts back default.sex of the VaST
# directory and removes the files the plate solver made there (wcs_fd_Per3_2011-10-31_001.fts*
# and the image_pid*.cat.aperture and image_pid*.cat.sex_log files of its SExtractor runs).
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
# The settings of the fetcher and the solver this test sets itself for each run
unset VAST_PHOTOMETRIC_CATALOG VAST_FIELD_CATALOG_PROVIDERS VAST_FIELD_CATALOG_CACHE_DIR VAST_FIELD_CATALOG_CACHE_MAX_MB VAST_FIELD_CATALOG_TILE_RADIUS_DEG VAST_FIELD_CATALOG_RETRY_PAUSE_SEC VAST_CURL_PROXY

# Work in the VaST directory this script belongs to
cd "$(dirname "$0")/../.." || exit 1

FAILED_CODES=""
fail() {
 FAILED_CODES="$FAILED_CODES $1"
 echo "FAILED: $1 $2"
}

FETCHER="$PWD/lib/photometric_field_catalog.sh"
SOLVER_IMAGE_NAME="wcs_fd_Per3_2011-10-31_001.fts"
SOLVER_IMAGE_DIR="../individual_images_test"
SOLVER_CATALOG="$SOLVER_IMAGE_NAME.wcscat.ucac5"

if [ ! -x "$FETCHER" ];then
 fail PHOTFIELDCAT_TOOL_NOT_FOUND "no executable lib/photometric_field_catalog.sh in the VaST directory"
 exit 1
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vast_photometric_field_catalog_test.XXXXXX" 2>/dev/null)
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ];then
 fail PHOTFIELDCAT000 "cannot create a work directory"
 exit 1
fi
FETCHER_TMP_DIR="$WORK_DIR/tmpdir_of_the_fetcher"
if ! mkdir -p "$WORK_DIR/bin" "$FETCHER_TMP_DIR" ;then
 fail PHOTFIELDCAT000 "cannot create directories in $WORK_DIR"
 rm -rf "$WORK_DIR"
 exit 1
fi

SOLVER_PART_STARTED="no"
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
 if [ "$SOLVER_PART_STARTED" = "yes" ];then
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
 fi
 if [ "$FIELD_TEST_KEEP_WORK_DIR" != "yes" ];then
  rm -rf "$WORK_DIR"
 fi
}
trap clean_up EXIT
trap 'exit 1' HUP INT TERM
if [ "$FIELD_TEST_KEEP_WORK_DIR" = "yes" ];then
 echo "The work directory $WORK_DIR will be kept (FIELD_TEST_KEEP_WORK_DIR=yes)"
fi

# The stand-in for curl. What it answers is set through the environment:
#   FIELD_TEST_DIR                  where it finds the sky stars and records the requests
#   FIELD_TEST_REPLY_ESA            sky (default): the stars of the cone from the sky list of the
#   FIELD_TEST_REPLY_SKYMAPPER      catalog in the query; crlf_quoted: the same with CR LF line
#   FIELD_TEST_REPLY_ARI            ends and quotes; maintenance: the HTML page ESA serves with
#                                   HTTP 200; other_header; bad_row; maxrec: MAXREC rows;
#                                   http408, http429, http500: that HTTP status; noreply
#   FIELD_TEST_FIRST_REPLY_<NAME>   the answer to the first request to that service only
#   FIELD_TEST_VIZIER_REPLY         rows (an APASS row for every position of a list query) or none
# The sky lists: $FIELD_TEST_DIR/sky_apass.csv and sky_gaia.csv, rows of the columns the
# services return, in their order, without a header.
cat > "$WORK_DIR/bin/curl" <<'STAND_IN_FOR_CURL'
#!/usr/bin/env bash
URL=""
OUTPUT_FILE=""
WRITE_OUT=""
DATA_FILE=""
QUERY=""
MAXREC=""
PREVIOUS_ARGUMENT=""
for ARGUMENT in "$@" ;do
 case "$PREVIOUS_ARGUMENT" in
  -o) OUTPUT_FILE="$ARGUMENT" ;;
  -w) WRITE_OUT="$ARGUMENT" ;;
  --data-binary) DATA_FILE="${ARGUMENT#@}" ;;
  --data-urlencode) case "$ARGUMENT" in QUERY=*) QUERY="${ARGUMENT#QUERY=}" ;; esac ;;
  -d) case "$ARGUMENT" in MAXREC=*) MAXREC="${ARGUMENT#MAXREC=}" ;; esac ;;
 esac
 case "$ARGUMENT" in
  http://*|https://*) URL="$ARGUMENT" ;;
 esac
 PREVIOUS_ARGUMENT="$ARGUMENT"
done
# answer HTTP_CODE: write what -w '%{http_code}' would print
answer() {
 if [ "$WRITE_OUT" = "%{http_code}" ];then
  printf '%s' "$1"
 fi
}
case "$URL" in
 https://gea.esac.esa.int/tap-server/tap/sync) SERVICE=esa ;;
 https://api.skymapper.nci.org.au/public/tap/sync) SERVICE=skymapper ;;
 https://gaia.ari.uni-heidelberg.de/tap/sync) SERVICE=ari ;;
 */viz-bin/*)
  SOURCE=$(grep '^-source=' "$DATA_FILE" 2>/dev/null | head -n 1)
  echo "vizier ${SOURCE#-source=}" >> "$FIELD_TEST_DIR/requests.log"
  if [ "$FIELD_TEST_VIZIER_REPLY" = "rows" ] && [ "$SOURCE" = "-source=II/336/apass9" ];then
   # one line per position of the list: the position as it was sent, the distance, the
   # catalog position (the same) and the ten values, V = 13 + the number of the position/1000
   awk '
    /^-c=<<====/ { in_list = 1 ; next }
    /^====/ { in_list = 0 }
    in_list && NF == 2 {
     id++
     printf "%-40s %6.3f %10.6f %+10.6f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f\n", $1 " " $2, 0.123, $1, $2, 13.5 + id / 1000, 0.011, 13 + id / 1000, 0.012, 12.9 + id / 1000, 0.013, 12.7 + id / 1000, 0.014, 13.3 + id / 1000, 0.015
    }
    END { print id + 0 > "/dev/stderr" }
   ' "$DATA_FILE" 2> "$FIELD_TEST_DIR/vizier_list_length.txt"
  fi
  # the last line of a complete VizieR reply
  echo "#END#   "
  exit 0
  ;;
 *)
  echo "UNEXPECTED $URL" >> "$FIELD_TEST_DIR/requests.log"
  answer 000
  exit 7
  ;;
esac
case "$QUERY" in
 *" FROM external.apassdr9 "*|*" FROM ext.apass_dr9 "*) CATALOG=apass ;;
 *" FROM gaiadr3.gaia_source AS g "*) CATALOG=gaia ;;
 *) CATALOG=unknown ;;
esac
echo "$SERVICE $CATALOG" >> "$FIELD_TEST_DIR/requests.log"
printf '%s\n' "$QUERY" >> "$FIELD_TEST_DIR/queries_$SERVICE.txt"
printf '%s\n' "$@" > "$FIELD_TEST_DIR/last_arguments_$SERVICE.txt"
# Keep the positions the plate solver wrote for the fetcher, if it is the plate solver asking
# shellcheck disable=SC2012
NEWEST_POSITIONS_FILE=$(ls -t photometric_field_catalog_*.positions 2>/dev/null | head -n 1)
if [ -n "$NEWEST_POSITIONS_FILE" ];then
 cp "$NEWEST_POSITIONS_FILE" "$FIELD_TEST_DIR/positions_$CATALOG.txt"
fi
SERVICE_UPPER=$(echo "$SERVICE" | tr 'a-z' 'A-Z')
REPLY_VARIABLE="FIELD_TEST_REPLY_$SERVICE_UPPER"
REPLY="${!REPLY_VARIABLE:-sky}"
FIRST_REPLY_VARIABLE="FIELD_TEST_FIRST_REPLY_$SERVICE_UPPER"
if [ -n "${!FIRST_REPLY_VARIABLE}" ] && [ "$(grep -c "^$SERVICE " "$FIELD_TEST_DIR/requests.log")" = "1" ];then
 REPLY="${!FIRST_REPLY_VARIABLE}"
fi
case "$CATALOG:$SERVICE" in
 apass:esa) HEADER="recno,raj2000,dej2000,vmag,bmag,e_bmag,e_vmag,r_mag,e_r_mag,i_mag,e_i_mag,g_mag,e_g_mag" ; MAG_COLUMN=4 ;;
 apass:skymapper) HEADER="recno,raj2000,dej2000,vmag,bmag,e_bmag,e_vmag,rmag,e_rmag,imag,e_imag,gmag,e_gmag" ; MAG_COLUMN=4 ;;
 gaia:*) HEADER="source_id,ra,dec,pmra,pmdec,phot_g_mean_mag,phot_variable_flag,gspc_source_id,c_star,b_jkc_mag,e_b_jkc_mag,b_jkc_flag,v_jkc_mag,e_v_jkc_mag,v_jkc_flag,r_jkc_mag,e_r_jkc_mag,r_jkc_flag,i_jkc_mag,e_i_jkc_mag,i_jkc_flag,g_sdss_mag,e_g_sdss_mag,g_sdss_flag,r_sdss_mag,e_r_sdss_mag,r_sdss_flag,i_sdss_mag,e_i_sdss_mag,i_sdss_flag" ; MAG_COLUMN=6 ;;
 *) HEADER="unknown" ; MAG_COLUMN=4 ;;
esac
# the cone and the magnitude range of the query
CONE=$(printf '%s' "$QUERY" | sed -n "s/.*CIRCLE('ICRS', *\([^,]*\), *\([^,]*\), *\([^)]*\)).*/\1 \2 \3/p")
MAG_RANGE=$(printf '%s' "$QUERY" | sed -n 's/.* + 0 BETWEEN \([^ ]*\) AND \([^ ]*\).*/\1 \2/p')
sky_rows() {
 awk -F, -v cone="$CONE" -v range="$MAG_RANGE" -v mag_column="$MAG_COLUMN" '
  function rad(x) { return x * 3.14159265358979 / 180.0 }
  BEGIN { split(cone, c, " ") ; split(range, m, " ") }
  {
   d = sin(rad($3)) * sin(rad(c[2])) + cos(rad($3)) * cos(rad(c[2])) * cos(rad($2 - c[1]))
   if (d > 1) d = 1
   if (atan2(sqrt(1 - d * d), d) * 180.0 / 3.14159265358979 > c[3] + 0) next
   if ($mag_column + 0 < m[1] + 0 || $mag_column + 0 > m[2] + 0) next
   print
  }' "$FIELD_TEST_DIR/sky_$CATALOG.csv" 2>/dev/null
}
case "$REPLY" in
 sky)
  { echo "$HEADER" ; sky_rows ; } > "$OUTPUT_FILE"
  answer 200
  ;;
 crlf_quoted)
  { echo "$HEADER" | sed 's/[^,]*/"&"/g' ; sky_rows | sed 's/,\([A-Z_]*\),/,"\1",/' ; } | awk '{ printf "%s\r\n", $0 }' > "$OUTPUT_FILE"
  answer 200
  ;;
 maintenance)
  printf '%s\n' '<html class="ltr" dir="ltr" lang="en-GB">' '<head>' '<title>ESDC Archives downtime</title>' '</head>' '<body>Maintenance ongoing!</body>' '</html>' > "$OUTPUT_FILE"
  answer 200
  ;;
 other_header)
  { echo "${HEADER%,*},another_column" ; sky_rows ; } > "$OUTPUT_FILE"
  answer 200
  ;;
 bad_row)
  { echo "$HEADER" ; sky_rows | head -n 1 | sed 's/^\([^,]*\),[^,]*,/\1,not_a_number,/' ; } > "$OUTPUT_FILE"
  answer 200
  ;;
 maxrec)
  { echo "$HEADER" ; sky_rows | head -n 1 | awk -v n="$MAXREC" '{ for (i = 0; i < n; i++) print }' ; } > "$OUTPUT_FILE"
  answer 200
  ;;
 http408|http429|http500)
  echo '<VOTABLE><RESOURCE type="results"><INFO name="QUERY_STATUS" value="ERROR">Job timeout/aborted.</INFO></RESOURCE></VOTABLE>' > "$OUTPUT_FILE"
  answer "${REPLY#http}"
  ;;
 noreply)
  echo "curl: (7) Failed to connect" >&2
  answer 000
  exit 7
  ;;
esac
exit 0
STAND_IN_FOR_CURL
chmod +x "$WORK_DIR/bin/curl"
export FIELD_TEST_DIR="$WORK_DIR"
: > "$WORK_DIR/requests.log"

# The requests since the log was emptied, on one line, for example: esa apass|skymapper apass|
requests_on_one_line() {
 tr '\n' '|' < "$WORK_DIR/requests.log"
}
# The same, with repeated neighbouring requests merged into one: esa apass|vizier PS1|
requests_merged() {
 uniq < "$WORK_DIR/requests.log" | tr '\n' '|'
}
number_of_requests() {
 grep -c . "$WORK_DIR/requests.log"
}
# The number of files matching the pattern $1 (a glob)
number_of_files() {
 local N_FILES=0
 local FILE
 for FILE in $1 ;do
  if [ -e "$FILE" ];then
   N_FILES=$((N_FILES + 1))
  fi
 done
 echo "$N_FILES"
}

##### The fetcher #####

# Run the fetcher with the stand-in for curl and without its cache, unless
# VAST_FIELD_CATALOG_CACHE_DIR is set by the caller; the arguments are those of the fetcher.
# Sets FETCHER_EXIT_CODE; the messages are in $WORK_DIR/fetcher.err
run_fetcher() {
 TMPDIR="$FETCHER_TMP_DIR" VAST_FIELD_CATALOG_CACHE_DIR="${VAST_FIELD_CATALOG_CACHE_DIR:-none}" VAST_FIELD_CATALOG_RETRY_PAUSE_SEC=0 PATH="$WORK_DIR/bin:$PATH" "$FETCHER" "$@" 2> "$WORK_DIR/fetcher.err"
 FETCHER_EXIT_CODE=$?
}
table_rows() {
 grep -v '^#' "$1" 2>/dev/null
}
table_header_value() {
 awk -v key="$2" '$1 == "#" && $2 == key { $1 = "" ; $2 = "" ; sub(/^ +/, "") ; print ; exit }' "$1" 2>/dev/null
}

# A small field around RA 10.5, Dec +20.25 and a wide one, 12 by 12 degrees around RA 100,
# Dec -30; the sky stars are written for them below
printf '%s\n' '10.5 20.25' '10.51 20.26' '10.49 20.24' > "$WORK_DIR/positions_small.txt"
awk 'BEGIN { for (i = -6; i <= 6; i += 2) for (j = -6; j <= 6; j += 2) printf "%.4f %.4f\n", 100 + i / cos(30 * 3.14159265358979 / 180), -30 + j }' > "$WORK_DIR/positions_wide.txt"
# APASS: recno ra dec V B eB eV r er i ei g eg. The star 1000003 has no B, 1000004 no g and no
# errors, 1000005 is outside the magnitude range 2..16.5, 1000006 is outside the cone of the
# small field (2 arcmin north of its first position)
{
 echo '1000001,10.5,20.25,12.000,12.500,0.011,0.012,11.900,0.013,11.700,0.014,12.300,0.015'
 echo '1000002,10.51,20.26,12.100,12.600,0.021,0.022,12.000,0.023,11.800,0.024,12.400,0.025'
 echo '1000003,10.49,20.24,12.200,,,0.032,12.100,0.033,11.900,0.034,12.500,0.035'
 echo '1000004,10.5005,20.2505,12.300,12.800,,,12.200,,12.000,,,'
 echo '1000005,10.5003,20.2502,17.000,17.500,0.051,0.052,16.900,0.053,16.700,0.054,17.300,0.055'
 echo '1000006,10.5,20.2833333,12.400,12.900,0.061,0.062,12.300,0.063,12.100,0.064,12.700,0.065'
 awk '{ printf "%d,%s,%s,11.000,11.500,0.011,0.012,10.900,0.013,10.700,0.014,11.300,0.015\n", 2000000 + NR, $1, $2 }' "$WORK_DIR/positions_wide.txt"
} > "$WORK_DIR/sky_apass.csv"
# Gaia: a star with synthetic photometry and a VARIABLE one without it
{
 echo '3000000000000000001,10.5,20.25,5.5,-3.25,11.8,NOT_AVAILABLE,3000000000000000001,0.012,12.5,0.003,1,12.0,0.002,1,11.6,0.002,1,11.2,0.002,1,12.3,0.004,0,11.9,0.003,0,11.7,0.003,0'
 echo '3000000000000000002,10.51,20.26,,,12.4,VARIABLE,,,,,,,,,,,,,,,,,,,,,,,'
} > "$WORK_DIR/sky_gaia.csv"

echo "The fetcher: the request and the table for a small field"
: > "$WORK_DIR/requests.log"
rm -f "$WORK_DIR"/queries_*.txt
run_fetcher apass "$WORK_DIR/positions_small.txt" 10 2.0 16.5 "$WORK_DIR/table_small.txt" > /dev/null
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ ! -s "$WORK_DIR/table_small.txt" ];then
 fail PHOTFIELDCAT001 "the fetcher did not write the table (exit code $FETCHER_EXIT_CODE): $(head -n 2 "$WORK_DIR/fetcher.err")"
else
 if [ "$(requests_on_one_line)" != "esa apass|" ];then
  fail PHOTFIELDCAT002 "not exactly one request to ESA for APASS: $(requests_on_one_line)"
 fi
 QUERY=$(head -n 1 "$WORK_DIR/queries_esa.txt")
 for QUERY_PART in " FROM external.apassdr9 " "vmag + 0 BETWEEN 2.0 AND 16.5" "CIRCLE('ICRS', " ;do
  if ! echo "$QUERY" | grep -q -F -e "$QUERY_PART" ;then
   fail PHOTFIELDCAT003 "the query has no '$QUERY_PART': $QUERY"
  fi
 done
 if echo "$QUERY" | grep -q -e ' ORDER BY ' -e 'vmag BETWEEN' ;then
  fail PHOTFIELDCAT004 "the query has an ORDER BY clause or a magnitude condition an index could serve: $QUERY"
 fi
 for REQUEST_ARGUMENT in "REQUEST=doQuery" "LANG=ADQL" "FORMAT=csv" "MAXREC=1000000" ;do
  if ! grep -q -x -F -e "$REQUEST_ARGUMENT" "$WORK_DIR/last_arguments_esa.txt" ;then
   fail PHOTFIELDCAT005 "the request has no $REQUEST_ARGUMENT"
  fi
 done
 if [ "$(table_header_value "$WORK_DIR/table_small.txt" vast_field_catalog)" != "1" ] || [ "$(table_header_value "$WORK_DIR/table_small.txt" catalog)" != "apass" ] || [ "$(table_header_value "$WORK_DIR/table_small.txt" provider)" != "esa" ] || [ "$(table_header_value "$WORK_DIR/table_small.txt" mag_range)" != "2.0 16.5" ] || [ "$(grep -c '^# cone ' "$WORK_DIR/table_small.txt")" != "1" ] || [ "$(table_header_value "$WORK_DIR/table_small.txt" rows)" != "4" ];then
  fail PHOTFIELDCAT006 "the header of the table is not right: $(grep '^#' "$WORK_DIR/table_small.txt" | grep -v columns | tr '\n' ' ')"
 fi
 # The four stars of the cone in the magnitude range, missing values as 0
 table_rows "$WORK_DIR/table_small.txt" | sort > "$WORK_DIR/rows_small.txt"
 printf '%s\n' \
  '1000001 10.5 20.25 0 0 12.000 1 0 0 12.500 0.011 1 12.000 0.012 1 0 0 0 0 0 0 12.300 0.015 1 11.900 0.013 1 11.700 0.014 1' \
  '1000002 10.51 20.26 0 0 12.100 1 0 0 12.600 0.021 1 12.100 0.022 1 0 0 0 0 0 0 12.400 0.025 1 12.000 0.023 1 11.800 0.024 1' \
  '1000003 10.49 20.24 0 0 12.200 1 0 0 0 0 0 12.200 0.032 1 0 0 0 0 0 0 12.500 0.035 1 12.100 0.033 1 11.900 0.034 1' \
  '1000004 10.5005 20.2505 0 0 12.300 1 0 0 12.800 0 1 12.300 0 1 0 0 0 0 0 0 0 0 0 12.200 0 1 12.000 0 1' | sort > "$WORK_DIR/rows_small_expected.txt"
 if ! cmp -s "$WORK_DIR/rows_small.txt" "$WORK_DIR/rows_small_expected.txt" ;then
  fail PHOTFIELDCAT007 "the rows of the table are not the stars of the cone: $(diff "$WORK_DIR/rows_small_expected.txt" "$WORK_DIR/rows_small.txt" | head -n 4 | tr '\n' ' ')"
 fi
fi

echo "The fetcher: a wide field, and Gaia"
: > "$WORK_DIR/requests.log"
run_fetcher apass "$WORK_DIR/positions_wide.txt" 10 2.0 16.5 "$WORK_DIR/table_wide.txt" > /dev/null
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$(grep -c '^# cone ' "$WORK_DIR/table_wide.txt" 2>/dev/null)" != "4" ] || [ "$(number_of_requests)" != "4" ];then
 fail PHOTFIELDCAT010 "the wide field is not split into four cones fetched once each (exit code $FETCHER_EXIT_CODE, $(grep -c '^# cone ' "$WORK_DIR/table_wide.txt" 2>/dev/null) cones, requests $(requests_on_one_line))"
else
 # Each position lies in a cone, 10 arcsec or more inside its edge, and has its own star
 COVERAGE=$(awk '
  function rad(x) { return x * 3.14159265358979 / 180.0 }
  function sep(ra1, de1, ra2, de2,   c) {
   c = sin(rad(de1)) * sin(rad(de2)) + cos(rad(de1)) * cos(rad(de2)) * cos(rad(ra1 - ra2))
   if (c > 1) c = 1
   return atan2(sqrt(1 - c * c), c) * 180.0 / 3.14159265358979
  }
  FNR == NR { if ($1 == "#" && $2 == "cone") { n++ ; ra[n] = $3 ; de[n] = $4 ; r[n] = $5 } else if ($1 != "#") stars++ ; next }
  { covered = 0 ; for (k = 1; k <= n; k++) if (sep(ra[k], de[k], $1, $2) + 10 / 3600.0 <= r[k] + 1e-7) covered = 1 ; if (!covered) uncovered++ ; positions++ }
  END { printf "%d %d %d", positions, uncovered, stars }' "$WORK_DIR/table_wide.txt" "$WORK_DIR/positions_wide.txt")
 if [ "$COVERAGE" != "49 0 49" ];then
  fail PHOTFIELDCAT011 "the cones do not cover the positions (positions, not covered, stars): $COVERAGE"
 fi
fi
run_fetcher gaia "$WORK_DIR/positions_wide.txt" 10 2.0 16.5 "$WORK_DIR/table_wide_gaia.txt" > /dev/null
GAIA_MARGIN=$(awk 'FNR == NR { if ($1 == "#" && $2 == "cone") a[++n] = $5 ; next } $1 == "#" && $2 == "cone" { m++ ; d = ($5 - a[m]) * 3600 ; if (d < 59.99 || d > 60.01) bad++ } END { print m + 0, bad + 0 }' "$WORK_DIR/table_wide.txt" "$WORK_DIR/table_wide_gaia.txt" 2>/dev/null)
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$GAIA_MARGIN" != "4 0" ];then
 fail PHOTFIELDCAT012 "the Gaia cones are not 60 arcsec wider than the APASS ones (exit code $FETCHER_EXIT_CODE, cones and differences: $GAIA_MARGIN)"
fi
: > "$WORK_DIR/requests.log"
rm -f "$WORK_DIR"/queries_*.txt
run_fetcher gaia "$WORK_DIR/positions_small.txt" 10 2.0 19.0 "$WORK_DIR/table_gaia.txt" > /dev/null
GAIA_QUERY=$(head -n 1 "$WORK_DIR/queries_esa.txt" 2>/dev/null)
table_rows "$WORK_DIR/table_gaia.txt" | sort > "$WORK_DIR/rows_gaia.txt"
printf '%s\n' \
 '3000000000000000001 10.5 20.25 5.5 -3.25 11.8 1 0.012 0 12.5 0.003 1 12.0 0.002 1 11.6 0.002 1 11.2 0.002 1 12.3 0.004 0 11.9 0.003 0 11.7 0.003 0' \
 '3000000000000000002 10.51 20.26 0 0 12.4 0 0 1 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0' | sort > "$WORK_DIR/rows_gaia_expected.txt"
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || ! cmp -s "$WORK_DIR/rows_gaia.txt" "$WORK_DIR/rows_gaia_expected.txt" ;then
 fail PHOTFIELDCAT013 "the Gaia table is not right (exit code $FETCHER_EXIT_CODE): $(diff "$WORK_DIR/rows_gaia_expected.txt" "$WORK_DIR/rows_gaia.txt" 2>&1 | head -n 4 | tr '\n' ' ')"
fi
for QUERY_PART in " FROM gaiadr3.gaia_source AS g LEFT OUTER JOIN gaiadr3.synthetic_photometry_gspc AS s ON s.source_id = g.source_id " "g.phot_g_mean_mag + 0 BETWEEN 2.0 AND 17.7" ;do
 if ! echo "$GAIA_QUERY" | grep -q -F -e "$QUERY_PART" ;then
  fail PHOTFIELDCAT014 "the Gaia query has no '$QUERY_PART' (the synthetic photometry ends at G = 17.65): $GAIA_QUERY"
 fi
done

echo "The fetcher: replies to accept and to refuse"
FIELD_TEST_REPLY_ESA=crlf_quoted run_fetcher apass "$WORK_DIR/positions_small.txt" 10 2.0 16.5 "$WORK_DIR/table_crlf.txt" > /dev/null
export FIELD_TEST_REPLY_ESA
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$(table_rows "$WORK_DIR/table_crlf.txt" | sort)" != "$(cat "$WORK_DIR/rows_small_expected.txt")" ];then
 fail PHOTFIELDCAT020 "a reply with CR LF line ends and quotes is not read like a plain one (exit code $FETCHER_EXIT_CODE)"
fi
FIELD_TEST_REPLY_ESA=crlf_quoted run_fetcher gaia "$WORK_DIR/positions_small.txt" 10 2.0 19.0 "$WORK_DIR/table_crlf_gaia.txt" > /dev/null
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$(table_rows "$WORK_DIR/table_crlf_gaia.txt" | sort)" != "$(cat "$WORK_DIR/rows_gaia_expected.txt")" ];then
 fail PHOTFIELDCAT021 "a Gaia reply with CR LF line ends and a quoted VARIABLE flag is not read like a plain one (exit code $FETCHER_EXIT_CODE)"
fi
unset FIELD_TEST_REPLY_ESA
# Replies of ESA that are of no use: the fetcher has to go on with SkyMapper
for REFUSED in maintenance other_header bad_row maxrec http500 http429 noreply ;do
 : > "$WORK_DIR/requests.log"
 rm -f "$WORK_DIR/table_refused.txt"
 FIELD_TEST_REPLY_ESA="$REFUSED" run_fetcher apass "$WORK_DIR/positions_small.txt" 10 2.0 16.5 "$WORK_DIR/table_refused.txt" > /dev/null
 case "$REFUSED" in
  http*|noreply) EXPECTED_REQUESTS="esa apass|esa apass|skymapper apass|" ;;
  *) EXPECTED_REQUESTS="esa apass|skymapper apass|" ;;
 esac
 if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$(table_header_value "$WORK_DIR/table_refused.txt" provider)" != "skymapper" ] || [ "$(table_rows "$WORK_DIR/table_refused.txt" | sort)" != "$(cat "$WORK_DIR/rows_small_expected.txt")" ];then
  fail "PHOTFIELDCAT022_$REFUSED" "the fetcher did not go on with SkyMapper after the ESA reply '$REFUSED' (exit code $FETCHER_EXIT_CODE, provider '$(table_header_value "$WORK_DIR/table_refused.txt" provider)')"
 elif [ "$(requests_on_one_line)" != "$EXPECTED_REQUESTS" ];then
  fail "PHOTFIELDCAT023_$REFUSED" "the requests after the ESA reply '$REFUSED' are $(requests_on_one_line), expected $EXPECTED_REQUESTS"
 fi
 if grep -q 'ERROR' "$WORK_DIR/fetcher.err" ;then
  fail "PHOTFIELDCAT024_$REFUSED" "a message of the fetcher has the word ERROR: $(grep 'ERROR' "$WORK_DIR/fetcher.err" | head -n 1)"
 fi
done
# The first ESA request times out, the second one is answered
: > "$WORK_DIR/requests.log"
FIELD_TEST_FIRST_REPLY_ESA=http408 run_fetcher apass "$WORK_DIR/positions_small.txt" 10 2.0 16.5 "$WORK_DIR/table_retry.txt" > /dev/null
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$(table_header_value "$WORK_DIR/table_retry.txt" provider)" != "esa" ] || [ "$(requests_on_one_line)" != "esa apass|esa apass|" ];then
 fail PHOTFIELDCAT025 "an ESA request that timed out once is not asked again (exit code $FETCHER_EXIT_CODE, requests $(requests_on_one_line))"
fi
# No service delivers
: > "$WORK_DIR/requests.log"
rm -f "$WORK_DIR/table_none.txt"
FIELD_TEST_REPLY_ESA=maintenance FIELD_TEST_REPLY_SKYMAPPER=bad_row run_fetcher apass "$WORK_DIR/positions_small.txt" 10 2.0 16.5 "$WORK_DIR/table_none.txt" > /dev/null
if [ "$FETCHER_EXIT_CODE" -ne 2 ] || [ -e "$WORK_DIR/table_none.txt" ] || ! grep -q 'no provider delivered' "$WORK_DIR/fetcher.err" ;then
 fail PHOTFIELDCAT026 "when no service delivers, the fetcher has to write nothing and exit with code 2 (exit code $FETCHER_EXIT_CODE)"
fi
# The list of providers can be set; a provider that does not serve the catalog is skipped
: > "$WORK_DIR/requests.log"
VAST_FIELD_CATALOG_PROVIDERS="nosuch ari skymapper" run_fetcher apass "$WORK_DIR/positions_small.txt" 10 2.0 16.5 "$WORK_DIR/table_providers.txt" > /dev/null
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$(requests_on_one_line)" != "skymapper apass|" ] || [ "$(table_header_value "$WORK_DIR/table_providers.txt" provider)" != "skymapper" ];then
 fail PHOTFIELDCAT027 "VAST_FIELD_CATALOG_PROVIDERS is not followed (exit code $FETCHER_EXIT_CODE, requests $(requests_on_one_line))"
fi

echo "The fetcher: arguments to refuse before any request"
printf '%s\n' '10.5 20.25' 'abc 20.0' > "$WORK_DIR/positions_not_a_number.txt"
printf '%s\n' '10.5 95.0' > "$WORK_DIR/positions_dec_95.txt"
: > "$WORK_DIR/positions_empty.txt"
: > "$WORK_DIR/requests.log"
# name:arguments (the word POSITIONS stands for the good list of positions, OUT for an output file)
for REFUSED_ARGUMENTS in "five_arguments:apass POSITIONS 10 2.0 16.5" "no_such_catalog:ucac4 POSITIONS 10 2.0 16.5 OUT" "radius_zero:apass POSITIONS 0 2.0 16.5 OUT" "radius_not_a_number:apass POSITIONS abc 2.0 16.5 OUT" "bright_limit_fainter:apass POSITIONS 10 16.5 2.0 OUT" "no_such_file:apass $WORK_DIR/positions_no_such_file.txt 10 2.0 16.5 OUT" "empty_list:apass $WORK_DIR/positions_empty.txt 10 2.0 16.5 OUT" "position_not_a_number:apass $WORK_DIR/positions_not_a_number.txt 10 2.0 16.5 OUT" "dec_95:apass $WORK_DIR/positions_dec_95.txt 10 2.0 16.5 OUT" ;do
 REFUSED_NAME="${REFUSED_ARGUMENTS%%:*}"
 REFUSED_ARGUMENTS="${REFUSED_ARGUMENTS#*:}"
 REFUSED_ARGUMENTS="${REFUSED_ARGUMENTS/POSITIONS/$WORK_DIR/positions_small.txt}"
 REFUSED_ARGUMENTS="${REFUSED_ARGUMENTS/OUT/$WORK_DIR/table_refused_arguments.txt}"
 rm -f "$WORK_DIR/table_refused_arguments.txt"
 # The arguments have no white space of their own, so they can be split on it
 # shellcheck disable=SC2086
 run_fetcher $REFUSED_ARGUMENTS > /dev/null
 if [ "$FETCHER_EXIT_CODE" -ne 1 ] || [ "$(number_of_requests)" != "0" ] || [ -e "$WORK_DIR/table_refused_arguments.txt" ];then
  fail "PHOTFIELDCAT028_$REFUSED_NAME" "exit code $FETCHER_EXIT_CODE, $(number_of_requests) request(s) made"
  : > "$WORK_DIR/requests.log"
 fi
done

echo "The fetcher: its cache"
CACHE="$WORK_DIR/cache"
mkdir -p "$CACHE"
: > "$WORK_DIR/requests.log"
VAST_FIELD_CATALOG_CACHE_DIR="$CACHE" run_fetcher apass "$WORK_DIR/positions_small.txt" 10 2.0 16.5 "$WORK_DIR/table_cache1.txt" > /dev/null
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$(number_of_files "$CACHE/*")" != "1" ];then
 fail PHOTFIELDCAT030 "the fetched table is not kept in the cache (exit code $FETCHER_EXIT_CODE)"
fi
: > "$WORK_DIR/requests.log"
VAST_FIELD_CATALOG_CACHE_DIR="$CACHE" run_fetcher apass "$WORK_DIR/positions_small.txt" 10 2.0 16.5 "$WORK_DIR/table_cache2.txt" > /dev/null
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$(number_of_requests)" != "0" ] || ! cmp -s "$WORK_DIR/table_cache1.txt" "$WORK_DIR/table_cache2.txt" || ! grep -q 'cached in' "$WORK_DIR/fetcher.err" ;then
 fail PHOTFIELDCAT031 "the same request again is not answered from the cache (exit code $FETCHER_EXIT_CODE, $(number_of_requests) request(s))"
fi
# A narrower magnitude range and fewer positions are served by the cached table
head -n 2 "$WORK_DIR/positions_small.txt" > "$WORK_DIR/positions_small_two.txt"
: > "$WORK_DIR/requests.log"
VAST_FIELD_CATALOG_CACHE_DIR="$CACHE" run_fetcher apass "$WORK_DIR/positions_small_two.txt" 10 5.0 13.5 "$WORK_DIR/table_cache3.txt" > /dev/null
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$(number_of_requests)" != "0" ];then
 fail PHOTFIELDCAT032 "a request inside the cached field and magnitude range is not answered from the cache (exit code $FETCHER_EXIT_CODE, $(number_of_requests) request(s))"
fi
# A position outside the cached cone, a wider magnitude range and a larger match radius are not
printf '%s\n' '10.5 20.25' '10.52 20.25' > "$WORK_DIR/positions_small_moved.txt"
for NOT_COVERED in "position_outside:$WORK_DIR/positions_small_moved.txt 10 2.0 16.5" "wider_range:$WORK_DIR/positions_small.txt 10 2.0 17.5" "larger_radius:$WORK_DIR/positions_small.txt 30 2.0 16.5" ;do
 NOT_COVERED_NAME="${NOT_COVERED%%:*}"
 NOT_COVERED="${NOT_COVERED#*:}"
 : > "$WORK_DIR/requests.log"
 # shellcheck disable=SC2086
 VAST_FIELD_CATALOG_CACHE_DIR="$CACHE" run_fetcher apass $NOT_COVERED "$WORK_DIR/table_cache4.txt" > /dev/null
 if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$(requests_on_one_line)" != "esa apass|" ];then
  fail "PHOTFIELDCAT033_$NOT_COVERED_NAME" "a request the cached table does not cover is not fetched (exit code $FETCHER_EXIT_CODE, requests $(requests_on_one_line))"
 fi
done
# A table cut short is removed and not used
rm -f "$CACHE"/*.txt
VAST_FIELD_CATALOG_CACHE_DIR="$CACHE" run_fetcher apass "$WORK_DIR/positions_small.txt" 10 2.0 16.5 "$WORK_DIR/table_cache5.txt" > /dev/null
for CACHED_TABLE in "$CACHE"/*.txt ;do
 if [ -f "$CACHED_TABLE" ];then
  sed '$d' "$CACHED_TABLE" > "$WORK_DIR/cut_table.txt" && cat "$WORK_DIR/cut_table.txt" > "$CACHED_TABLE"
 fi
done
: > "$WORK_DIR/requests.log"
VAST_FIELD_CATALOG_CACHE_DIR="$CACHE" run_fetcher apass "$WORK_DIR/positions_small.txt" 10 2.0 16.5 "$WORK_DIR/table_cache6.txt" > /dev/null
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$(requests_on_one_line)" != "esa apass|" ] || [ "$(table_rows "$WORK_DIR/table_cache6.txt" | sort)" != "$(cat "$WORK_DIR/rows_small_expected.txt")" ];then
 fail PHOTFIELDCAT034 "a cached table cut short is used (exit code $FETCHER_EXIT_CODE, requests $(requests_on_one_line))"
fi
if [ "$(number_of_files "$CACHE/*")" != "1" ];then
 fail PHOTFIELDCAT035 "the cached table cut short is not removed: $(cd "$CACHE" && echo *)"
fi
# The size limit: with 0 MB only the table just written stays
VAST_FIELD_CATALOG_CACHE_DIR="$CACHE" run_fetcher apass "$WORK_DIR/positions_wide.txt" 10 2.0 16.5 "$WORK_DIR/table_cache7.txt" > /dev/null
VAST_FIELD_CATALOG_CACHE_MAX_MB=0 VAST_FIELD_CATALOG_CACHE_DIR="$CACHE" run_fetcher gaia "$WORK_DIR/positions_small.txt" 10 2.0 16.5 "$WORK_DIR/table_cache8.txt" > /dev/null
if [ "$FETCHER_EXIT_CODE" -ne 0 ] || [ "$(number_of_files "$CACHE/*")" != "1" ] || [ "$(number_of_files "$CACHE/gaia_*.txt")" != "1" ];then
 fail PHOTFIELDCAT036 "the cache is not cut to its size limit: $(cd "$CACHE" && echo *)"
fi

if grep -q '^UNEXPECTED' "$WORK_DIR/requests.log" ;then
 fail PHOTFIELDCAT037 "the fetcher made a request to another address: $(grep '^UNEXPECTED' "$WORK_DIR/requests.log" | head -n 1)"
fi
# shellcheck disable=SC2012
if [ "$(ls -A "$FETCHER_TMP_DIR" | wc -l | awk '{print $1}')" != "0" ];then
 fail PHOTFIELDCAT038 "the fetcher left files in its temporary directory: $(ls -A "$FETCHER_TMP_DIR" | head -n 3 | tr '\n' ' ')"
fi

##### The plate solver #####

SOLVER_PART_SKIP_REASON=""
if [ ! -x util/solve_plate_with_UCAC5 ] || [ ! -f default.sex.NMW_mass_processing ] || [ ! -x util/get_image_date ];then
 fail PHOTFIELDCAT_TOOL_NOT_FOUND "util/solve_plate_with_UCAC5 is not built (run make in the VaST directory)"
 SOLVER_PART_SKIP_REASON="notbuilt"
elif [ ! -f lib/catalogs/ucac5/z001 ];then
 SOLVER_PART_SKIP_REASON="noucac5"
 echo "NOT_PERFORMED: NOT_PERFORMED_PHOTFIELDCAT_SOLVER_noucac5 the plate solver part needs the local UCAC5 copy lib/catalogs/ucac5"
else
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
  SOLVER_PART_SKIP_REASON="nodata"
  echo "NOT_PERFORMED: NOT_PERFORMED_PHOTFIELDCAT_SOLVER_nodata the test image $SOLVER_IMAGE_DIR/$SOLVER_IMAGE_NAME is not available"
 fi
fi

# Run the plate solver on the test image with the stand-in for curl, without the cache of the
# fetcher unless VAST_FIELD_CATALOG_CACHE_DIR is set by the caller
# $1 - a name of the run for its log file $WORK_DIR/solver_<name>.log and the copy of its output
# catalog $WORK_DIR/catalog_<name>.txt
# Sets SOLVER_EXIT_CODE
run_solver() {
 rm -f "$SOLVER_CATALOG" "$WORK_DIR/vizier_list_length.txt"
 : > "$WORK_DIR/requests.log"
 # VIZIER_MIRROR_RECORD_ONLY=yes: lib/choose_vizier_mirror.sh names a mirror without asking
 # one, and without recording what the stand-in would have told it
 VAST_FIELD_CATALOG_CACHE_DIR="${VAST_FIELD_CATALOG_CACHE_DIR:-none}" VAST_FIELD_CATALOG_RETRY_PAUSE_SEC=0 VIZIER_MIRROR_RECORD_ONLY=yes PATH="$WORK_DIR/bin:$PATH" util/solve_plate_with_UCAC5 "$SOLVER_IMAGE_DIR/$SOLVER_IMAGE_NAME" > "$WORK_DIR/solver_$1.log" 2>&1
 SOLVER_EXIT_CODE=$?
 cp "$SOLVER_CATALOG" "$WORK_DIR/catalog_$1.txt" 2>/dev/null
}
show_solver_run() {
 echo " the requests of the run $1: $(requests_merged)"
 echo " what the plate solver said about the photometric catalogs (exit code $SOLVER_EXIT_CODE):"
 grep -e 'APASS' -e 'Gaia' -e 'Pan-STARRS' -e 'photometric' -e 'Positional cut' -e 'Matched' -e 'END#' "$WORK_DIR/solver_$1.log" 2>/dev/null | grep -v '^export ' | head -n 14 | sed 's/^/  /'
}
# The number of stars with a V magnitude in the output catalog $1
stars_with_photometry() {
 awk '$15 + 0 != 0 || $13 + 0 != 0 || $21 + 0 != 0 { n++ } END { print n + 0 }' "$1" 2>/dev/null
}

if [ -z "$SOLVER_PART_SKIP_REASON" ];then
 SOLVER_PART_STARTED="yes"
 rm -f "$SOLVER_IMAGE_NAME" "$SOLVER_IMAGE_NAME".*
 cp default.sex.NMW_mass_processing default.sex
 : > "$WORK_DIR/sky_apass.csv"
 : > "$WORK_DIR/sky_gaia.csv"
 rm -f "$WORK_DIR/positions_apass.txt" "$WORK_DIR/positions_gaia.txt"

 # The first run on the image leaves a refined plate solution behind, so the second and later
 # runs match a few more reference stars: the stars are counted from the second run on
 echo "Plate solver run: a first run to settle the plate solution"
 VAST_PHOTOMETRIC_CATALOG=gaia run_solver first
 echo "Plate solver run: Gaia first, empty sky - the reference stars and the order of the sources"
 FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
 VAST_PHOTOMETRIC_CATALOG=gaia run_solver discover
 if [ $SOLVER_EXIT_CODE -ne 0 ] || [ ! -s "$WORK_DIR/catalog_discover.txt" ];then
  fail PHOTFIELDCAT101 "the plate solver did not write $SOLVER_CATALOG (exit code $SOLVER_EXIT_CODE)"
  SOLVER_PART_SKIP_REASON="failed"
 elif [ ! -s "$WORK_DIR/positions_apass.txt" ] || [ ! -s "$WORK_DIR/positions_gaia.txt" ];then
  fail PHOTFIELDCAT102 "the plate solver did not hand the reference star positions to the fetcher"
  SOLVER_PART_SKIP_REASON="failed"
 else
  # A complete but empty field catalog: no other copy of it is asked, the next catalog is
  if [ "$(requests_merged)" != "esa gaia|esa apass|vizier PS1|" ];then
   fail PHOTFIELDCAT103 "the sources were not asked in the order Gaia, APASS, Pan-STARRS1, once each: $(requests_merged)"
  fi
  if [ "$(stars_with_photometry "$WORK_DIR/catalog_discover.txt")" != "0" ];then
   fail PHOTFIELDCAT104 "the output catalog has photometry although no source had any"
  fi
  if ! grep -q 'too few stars matched with Gaia DR3 synthetic photometry' "$WORK_DIR/solver_discover.log" || ! grep -q 'too few stars matched with APASS DR9' "$WORK_DIR/solver_discover.log" ;then
   fail PHOTFIELDCAT105 "the plate solver does not report too few matches with Gaia and APASS"
  fi
  # The fetcher command line in the log: the search radius and the magnitude range
  read -r SEARCH_RADIUS_ARCSEC BRIGHTEST_MAG FAINTEST_MAG < <(grep 'photometric_field_catalog.sh" apass ' "$WORK_DIR/solver_discover.log" | head -n 1 | awk '{print $4, $5, $6}')
  N_POSITIONS=$(grep -c . "$WORK_DIR/positions_apass.txt")
  if ! grep -q "Getting the APASS DR9 stars around the $N_POSITIONS good reference stars" "$WORK_DIR/solver_discover.log" || [ "$N_POSITIONS" != "$(grep -c . "$WORK_DIR/positions_gaia.txt")" ];then
   fail PHOTFIELDCAT106 "the positions handed to the fetcher are not those of all good reference stars ($N_POSITIONS for APASS, $(grep -c . "$WORK_DIR/positions_gaia.txt") for Gaia)"
  fi
  if [ -z "$FAINTEST_MAG" ] || [ "$N_POSITIONS" -lt 50 ];then
   fail PHOTFIELDCAT107 "cannot read the search radius and magnitude range from the plate solver log, or too few reference stars ($N_POSITIONS)"
   SOLVER_PART_SKIP_REASON="failed"
  fi
 fi
 if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
  show_solver_run discover
 fi
fi

if [ -z "$SOLVER_PART_SKIP_REASON" ];then
 # The epoch of the image, for the proper motions of the Gaia stars
 IMAGE_EPOCH=$(util/get_image_date "$SOLVER_IMAGE_DIR/$SOLVER_IMAGE_NAME" 2>&1 | awk '$1 == "JD" { printf "%.4f", 2000.0 + ($2 - 2451545.0) / 365.25 ; exit }')
 # The sky stars. Each reference star k (the k-th line of the position files) is paired with
 # its image star: the output row of the first run nearest to its position. A reference star
 # with another one within twice the search radius gets no sky stars at all (with its
 # neighbours it is not clear which catalog star is the brightest one around it).
 # The classes of reference stars, by k (each class decides what the sky has around it):
 #  k % 10 == 3 - its own star and a brighter one without B (APASS) or without synthetic
 #                photometry (Gaia) 0.3 search radii away: no photometry
 #  k % 10 == 7 - APASS: its own star and a fainter complete one 0.3 search radii away: its own
 #                photometry; Gaia: its own star has no B magnitude, the other bands count
 #  k % 10 == 5 - APASS: no g' magnitude (written as 0 with the default error 0.020);
 #                Gaia: its own star is VARIABLE: no photometry
 #  k % 10 == 9 - Gaia: its own star has c_star = 0.3: no photometry
 #  k % 20 == 1 - Gaia: its own star has a proper motion that puts it 1.5 search radii away
 #                in 2016.0: its own photometry, if the plate solver moves it to the epoch
 #  k % 25 == 11 (if not of a class above) - its only star lies 0.6 search radii from the
 #                reference position on the side away from the measured position: matched,
 #                then rejected by the positional cut
 #  k % 50 == 19 - its only star is 0.4 mag fainter than the faint limit: no photometry
 #  otherwise   - its own star, 0.2 arcsec north of the measured position
 # The own star of k has V = BASE + k/1000 (APASS) or G = BASE + k/1000 (Gaia), with BASE set
 # so that all of them are inside the magnitude range.
 awk -v radius="$SEARCH_RADIUS_ARCSEC" -v bright="$BRIGHTEST_MAG" -v faint="$FAINTEST_MAG" -v epoch="$IMAGE_EPOCH" \
     -v sky_apass="$WORK_DIR/sky_apass.csv" -v sky_gaia="$WORK_DIR/sky_gaia.csv" -v expected="$WORK_DIR/expected.txt" '
  function rad(x) { return x * 3.14159265358979 / 180.0 }
  function sep(ra1, de1, ra2, de2,   c) {
   c = sin(rad(de1)) * sin(rad(de2)) + cos(rad(de1)) * cos(rad(de2)) * cos(rad(ra1 - ra2))
   if (c > 1) c = 1
   return atan2(sqrt(1 - c * c), c) * 180.0 / 3.14159265358979 * 3600.0
  }
  # the point d arcsec from (ra, de) in the direction (east, north) given as a unit vector
  function move_ra(ra, de, d, east) { return ra + east * d / 3600.0 / cos(rad(de)) }
  function move_de(de, d, north) { return de + north * d / 3600.0 }
  FILENAME ~ /positions_apass/ { n++ ; ara[n] = $1 ; ade[n] = $2 ; next }
  FILENAME ~ /positions_gaia/ { m++ ; gra[m] = $1 ; gde[m] = $2 ; next }
  # the output rows of astrometrically matched stars: number, measured position
  $11 + 0 != 0 { rows++ ; rid[rows] = $1 ; rra[rows] = $2 ; rde[rows] = $3 }
  END {
   base = faint - 0.3 - (n + 1) / 1000.0
   if (base < bright + 1.0) base = bright + 1.0
   # Dec bins two search radii wide: whatever is within two radii of a position lies in its
   # own bin or in a neighbouring one
   bin = 2 * radius / 3600.0
   for (j = 1; j <= n; j++) { b = int((ade[j] + 90) / bin) ; position_bin[b] = position_bin[b] " " j }
   for (r = 1; r <= rows; r++) { b = int((rde[r] + 90) / bin) ; row_bin[b] = row_bin[b] " " r }
   for (k = 1; k <= n; k++) {
    b = int((ade[k] + 90) / bin)
    crowded = 0 ; best = 0 ; best_d = 1e9
    for (bb = b - 1; bb <= b + 1; bb++) {
     n_list = split(position_bin[bb], list, " ")
     for (t = 1; t <= n_list; t++) { j = list[t] + 0 ; if (j != k && sep(ara[k], ade[k], ara[j], ade[j]) < 2 * radius) crowded = 1 }
     n_list = split(row_bin[bb], list, " ")
     for (t = 1; t <= n_list; t++) { r = list[t] + 0 ; d = sep(ara[k], ade[k], rra[r], rde[r]) ; if (d < best_d) { best_d = d ; best = r } }
    }
    if (crowded) n_crowded++
    if (crowded || best == 0 || best_d > radius) { print k, "crowded", 0 > expected ; continue }
    mra = rra[best] ; mde = rde[best] ; star = rid[best]
    mag = base + k / 1000.0
    # the direction from the measured position to the reference position, for the class
    # whose star lies on the other side of the reference position
    east = (ara[k] - mra) * cos(rad(mde)) * 3600.0 ; north = (ade[k] - mde) * 3600.0 ; len = sqrt(east * east + north * north)
    if (len < 0.1) { east = 0 ; north = 1 } else { east /= len ; north /= len }
    cls = "normal"
    if (k % 10 == 3) cls = "brighter_without_photometry"
    else if (k % 10 == 7) cls = "seven"
    else if (k % 10 == 5) cls = "five"
    else if (k % 10 == 9) cls = "nine"
    if (k % 20 == 1) cls = "high_pm"
    else if (k % 25 == 11 && cls == "normal") cls = "misidentified"
    if (k % 50 == 19) cls = "out_of_range"
    # APASS stars: recno ra dec V B eB eV r er i ei g eg
    own_ra = mra ; own_de = move_de(mde, 0.2, 1)
    if (cls == "misidentified") { own_ra = move_ra(ara[k], ade[k], 0.6 * radius, east) ; own_de = move_de(ade[k], 0.6 * radius, north) }
    v = mag
    if (cls == "out_of_range") v = faint + 0.4
    g_value = sprintf("%.3f,0.015", v + 0.3)
    if (cls == "five") g_value = ","
    printf "%d,%.8f,%.8f,%.3f,%.3f,0.011,0.012,%.3f,0.013,%.3f,0.014,%s\n", 1000000 + k, own_ra, own_de, v, v + 0.5, v - 0.1, v - 0.3, g_value > sky_apass
    if (cls == "brighter_without_photometry")
     printf "%d,%.8f,%.8f,%.3f,,,0.012,%.3f,0.013,%.3f,0.014,%.3f,0.015\n", 5000000 + k, move_ra(ara[k], ade[k], 0.3 * radius, 1), ade[k], v - 0.5, v - 0.6, v - 0.8, v - 0.2 > sky_apass
    if (cls == "seven")
     printf "%d,%.8f,%.8f,%.3f,%.3f,0.011,0.012,%.3f,0.013,%.3f,0.014,%.3f,0.015\n", 5000000 + k, move_ra(ara[k], ade[k], 0.3 * radius, 1), ade[k], v + 0.3, v + 1.5, v + 0.2, v, v + 0.6 > sky_apass
    apass_expect = "photometry"
    if (cls == "brighter_without_photometry" || cls == "out_of_range") apass_expect = "none"
    if (cls == "misidentified") apass_expect = "cut"
    # Gaia stars: their 2016.0 positions; G = mag, B V Rc Ic g r i = G + 0.6 0.1 -0.3 -0.7 0.4 -0.05 -0.25
    gown_ra = mra ; gown_de = move_de(mde, 0.2, 1) ; pmra = 0 ; pmdec = 0
    if (cls == "misidentified") { gown_ra = move_ra(gra[k], gde[k], 0.6 * radius, east) ; gown_de = move_de(gde[k], 0.6 * radius, north) }
    if (cls == "high_pm") {
     # 1.5 search radii to the east in 2016.0
     pmra = 1.5 * radius / (2016.0 - epoch) * 1000.0
     gown_ra = move_ra(gown_ra, gown_de, 1.5 * radius, 1)
    }
    variable = (cls == "five") ? "VARIABLE" : "NOT_AVAILABLE"
    c_star = (cls == "nine") ? 0.3 : 0.01
    b_value = sprintf("%.3f,0.02,1", v + 0.6)
    if (cls == "seven") b_value = ",,"
    # (the identifiers are written as strings: awk numbers are doubles, 4e18 + k would lose k)
    gaia_id = sprintf("4%018d", k)
    printf "%s,%.8f,%.8f,%.3f,%.3f,%.3f,%s,%s,%.3f,%s,%.3f,0.002,1,%.3f,0.02,1,%.3f,0.02,1,%.3f,0.02,0,%.3f,0.02,0,%.3f,0.02,0\n", gaia_id, gown_ra, gown_de, pmra, pmdec, v, variable, gaia_id, c_star, b_value, v + 0.1, v - 0.3, v - 0.7, v + 0.4, v - 0.05, v - 0.25 > sky_gaia
    if (cls == "brighter_without_photometry")
     printf "%s,%.8f,%.8f,0,0,%.3f,NOT_AVAILABLE,,,,,,,,,,,,,,,,,,,,,,,\n", sprintf("41%017d", k), move_ra(gra[k], gde[k], 0.3 * radius, 1), gde[k], v - 0.5 > sky_gaia
    gaia_expect = "photometry"
    if (cls == "brighter_without_photometry" || cls == "out_of_range" || cls == "five" || cls == "nine") gaia_expect = "none"
    if (cls == "misidentified") gaia_expect = "cut"
    # k, the class, the image star, the measured position, the magnitude of its own star,
    # what APASS and Gaia should give it, and the offsets of the catalog positions of APASS
    # and Gaia from the measured position (arcsec, RA*cos(Dec) and Dec)
    printf "%d %s %d %.8f %.8f %.3f %s %s %.3f %.3f %.3f %.3f\n", k, cls, star, mra, mde, v, apass_expect, gaia_expect, (own_ra - mra) * cos(rad(mde)) * 3600, (own_de - mde) * 3600, (gown_ra - mra - ((cls == "high_pm") ? 1.5 * radius / 3600.0 / cos(rad(mde)) : 0)) * cos(rad(mde)) * 3600, (gown_de - mde) * 3600 > expected
   }
  }' "$WORK_DIR/positions_apass.txt" "$WORK_DIR/positions_gaia.txt" "$WORK_DIR/catalog_discover.txt"
 N_PAIRED=$(awk '$2 != "crowded"' "$WORK_DIR/expected.txt" | wc -l | awk '{print $1}')
 echo " $N_POSITIONS reference stars, $N_PAIRED of them with sky stars; search radius $SEARCH_RADIUS_ARCSEC arcsec, magnitudes $BRIGHTEST_MAG to $FAINTEST_MAG, image epoch $IMAGE_EPOCH"
 if [ "$N_PAIRED" -lt 40 ];then
  fail PHOTFIELDCAT108 "only $N_PAIRED reference stars could get sky stars"
  SOLVER_PART_SKIP_REASON="failed"
 fi
fi

# Compare the output catalog $1 of a run with the expected photometry of catalog $2 (apass or
# gaia; the class column of expected.txt and the positional cut line in the log $3 decide).
# Prints "OK" or the first problems.
check_photometry() {
 awk -v catalog="$2" -v log_file="$3" '
  function abs(x) { return x < 0 ? -x : x }
  BEGIN {
   # median and sigma of the offsets, from the positional cut line of the log
   while ((getline line < log_file) > 0) {
    if (line ~ /^Positional cut of the .* matches: [0-9]+ matches, median offset/) {
     n = split(line, w, " ")
     for (i = 1; i <= n; i++) {
      if (w[i] == "offset" && w[i + 1] == "of") { median_ra = w[i + 8] + 0 ; median_de = w[i + 14] + 0 }
      if (w[i] == "sigma" && w[i - 1] == "robust") { sigma_ra = w[i + 1] + 0 ; sigma_de = w[i + 3] + 0 }
      if (w[i] == "rejected") reported_rejected = w[i - 1] + 0
     }
     have_cut = 1
    }
   }
  }
  FILENAME ~ /expected/ {
   k_of_star[$3] = $1 ; cls[$1] = $2 ; mag[$1] = $6
   expect[$1] = (catalog == "apass") ? $7 : $8
   if (catalog == "apass") { dra[$1] = $9 ; dde[$1] = $10 } else { dra[$1] = $11 ; dde[$1] = $12 }
   next
  }
  {
   star = $1
   has = ($13 + 0 != 0 || $15 + 0 != 0 || $21 + 0 != 0 || $23 + 0 != 0)
   if (!(star in k_of_star)) { if (has) problem("star " star " has photometry but no sky star") ; next }
   k = k_of_star[star]
   want = expect[k]
   if (want == "cut") {
    # the positional cut decides: more than 5 sigma from the median offset
    want = "photometry"
    if (have_cut && sigma_ra > 0 && sigma_de > 0) {
     x = (dra[k] - median_ra) / sigma_ra ; y = (dde[k] - median_de) / sigma_de
     if (x * x + y * y > 25) { want = "none" ; expected_rejected++ }
    }
   }
   if (want == "crowded" || want == "none") { if (has) problem("star " star " (k=" k ", " cls[k] ") has photometry, expected none") ; next }
   if (!has) { problem("star " star " (k=" k ", " cls[k] ") has no photometry") ; next }
   n_ok_rows++
   m = mag[k]
   if (catalog == "apass") {
    if (abs($15 - m) > 0.0006 || abs($13 - (m + 0.5)) > 0.0006 || abs($17 - (m - 0.1)) > 0.0006 || abs($19 - (m - 0.3)) > 0.0006) problem("star " star " (k=" k ", " cls[k] ") has B V r i " $13 " " $15 " " $17 " " $19 ", expected V=" m)
    if ($14 != "0.011" || $16 != "0.012" || $18 != "0.013" || $20 != "0.014") problem("star " star " has the errors " $14 " " $16 " " $18 " " $20)
    if (cls[k] == "five") { if ($25 != "0.000" || $26 != "0.020") problem("star " star " without g has g " $25 " " $26) }
    else if (abs($25 - (m + 0.3)) > 0.0006 || $26 != "0.015") problem("star " star " has g " $25 " " $26)
    # Jester et al. (2005), as published: V-R = 1.09 (r-i) + 0.22 and R-I = 1.00 (r-i) + 0.21
    if (abs(($15 - $21) - (1.09 * ($17 - $19) + 0.22)) > 0.002 || abs(($21 - $23) - (1.00 * ($17 - $19) + 0.21)) > 0.002) problem("star " star ": V-Rc=" $15 - $21 " Rc-Ic=" $21 - $23 " do not follow Jester et al. (2005) for r-i=" $17 - $19)
   } else {
    if (abs($15 - (m + 0.1)) > 0.0006 || abs($21 - (m - 0.3)) > 0.0006 || abs($23 - (m - 0.7)) > 0.0006 || abs($25 - (m + 0.4)) > 0.0006 || abs($17 - (m - 0.05)) > 0.0006 || abs($19 - (m - 0.25)) > 0.0006) problem("star " star " (k=" k ", " cls[k] ") has V Rc Ic g r i " $15 " " $21 " " $23 " " $25 " " $17 " " $19 ", expected G=" m)
    if (cls[k] == "seven") { if ($13 != "0.000" || $14 != "0.000") problem("star " star " without B has B " $13 " " $14) }
    else if (abs($13 - (m + 0.6)) > 0.0006 || $14 != "0.020") problem("star " star " has B " $13 " " $14)
    # the V error of 0.002 mag is raised to 0.01
    if ($16 != "0.010" || $22 != "0.020" || $24 != "0.020") problem("star " star " has the errors V " $16 " Rc " $22 " Ic " $24 ", expected 0.010 0.020 0.020")
   }
  }
  function problem(text) { if (n_problems++ < 4) printf "%s; ", text }
  END {
   if (!have_cut) { n_problems++ ; printf "no positional cut line in the log; " }
   else if (reported_rejected != expected_rejected + 0) { n_problems++ ; printf "the log reports %d matches rejected by the positional cut, expected %d; ", reported_rejected, expected_rejected }
   if (n_ok_rows + 0 < 20) { n_problems++ ; printf "only %d stars with the expected photometry; ", n_ok_rows }
   if (n_problems == 0) printf "OK %d %d", n_ok_rows, expected_rejected
  }' "$WORK_DIR/expected.txt" "$1"
}

if [ -z "$SOLVER_PART_SKIP_REASON" ];then
 echo "Plate solver run: APASS from ESA"
 FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
 run_solver apass_esa
 RESULT=$(check_photometry "$WORK_DIR/catalog_apass_esa.txt" apass "$WORK_DIR/solver_apass_esa.log")
 if [ $SOLVER_EXIT_CODE -ne 0 ] || [ ! -s "$WORK_DIR/catalog_apass_esa.txt" ];then
  fail PHOTFIELDCAT111 "the plate solver did not write $SOLVER_CATALOG (exit code $SOLVER_EXIT_CODE)"
 else
  if [ "$(requests_merged)" != "esa apass|" ];then
   fail PHOTFIELDCAT112 "the plate solver did not ask ESA for APASS and nothing else: $(requests_merged)"
  fi
  case "$RESULT" in
   OK*) N_APASS_STARS=$(echo "$RESULT" | awk '{print $2}')
        if [ "$(echo "$RESULT" | awk '{print $3}')" = "0" ];then
         fail PHOTFIELDCAT113 "no match was rejected by the positional cut (the search radius $SEARCH_RADIUS_ARCSEC arcsec is too small for this check?)"
        fi
        if ! grep -q "Using $N_APASS_STARS stars matched with APASS DR9 (esa)" "$WORK_DIR/solver_apass_esa.log" ;then
         fail PHOTFIELDCAT114 "the plate solver does not report the $N_APASS_STARS stars it uses"
        fi ;;
   *) fail PHOTFIELDCAT115 "the APASS photometry of the stars is not right: $RESULT" ;;
  esac
 fi
 if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
  show_solver_run apass_esa
 fi

 echo "Plate solver run: APASS - the ESA maintenance page, then SkyMapper"
 FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
 FIELD_TEST_REPLY_ESA=maintenance run_solver apass_skymapper
 if [ "$(requests_merged)" != "esa apass|skymapper apass|" ] || [ "$(awk '{$2 = $3 = ""; print}' "$WORK_DIR/catalog_apass_skymapper.txt" 2>/dev/null | cksum)" != "$(awk '{$2 = $3 = ""; print}' "$WORK_DIR/catalog_apass_esa.txt" | cksum)" ];then
  fail PHOTFIELDCAT121 "with ESA in maintenance the plate solver did not get the same photometry from SkyMapper (requests $(requests_merged))"
  show_solver_run apass_skymapper
 fi

 echo "Plate solver run: APASS - an ESA timeout, then ESA again"
 FIELD_TEST_FIRST_REPLY_ESA=http408 run_solver apass_retry
 if [ "$(requests_merged)" != "esa apass|" ] || [ "$(number_of_requests)" -lt 2 ] || [ "$(awk '{$2 = $3 = ""; print}' "$WORK_DIR/catalog_apass_retry.txt" 2>/dev/null | cksum)" != "$(awk '{$2 = $3 = ""; print}' "$WORK_DIR/catalog_apass_esa.txt" | cksum)" ];then
  fail PHOTFIELDCAT122 "after one ESA timeout the plate solver did not get the photometry from ESA (requests $(requests_on_one_line))"
  show_solver_run apass_retry
 fi

 echo "Plate solver run: Gaia from ESA"
 FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
 VAST_PHOTOMETRIC_CATALOG=gaia run_solver gaia_esa
 RESULT=$(check_photometry "$WORK_DIR/catalog_gaia_esa.txt" gaia "$WORK_DIR/solver_gaia_esa.log")
 if [ $SOLVER_EXIT_CODE -ne 0 ] || [ ! -s "$WORK_DIR/catalog_gaia_esa.txt" ];then
  fail PHOTFIELDCAT131 "the plate solver did not write $SOLVER_CATALOG (exit code $SOLVER_EXIT_CODE)"
 else
  if [ "$(requests_merged)" != "esa gaia|" ];then
   fail PHOTFIELDCAT132 "the plate solver did not ask ESA for Gaia and nothing else: $(requests_merged)"
  fi
  case "$RESULT" in
   OK*) N_GAIA_STARS=$(echo "$RESULT" | awk '{print $2}')
        if ! grep -q "Using $N_GAIA_STARS stars matched with Gaia DR3 synthetic photometry (esa)" "$WORK_DIR/solver_gaia_esa.log" ;then
         fail PHOTFIELDCAT133 "the plate solver does not report the $N_GAIA_STARS stars it uses"
        fi ;;
   *) fail PHOTFIELDCAT134 "the Gaia photometry of the stars is not right: $RESULT" ;;
  esac
 fi
 if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
  show_solver_run gaia_esa
 fi

 echo "Plate solver run: Gaia - ESA in maintenance, ARI failing - then APASS from ESA"
 FIELD_TEST_REPLY_ESA=maintenance FIELD_TEST_REPLY_ARI=http500 VAST_PHOTOMETRIC_CATALOG=gaia run_solver gaia_fails
 # ESA answers APASS with the maintenance page too, so SkyMapper gives the APASS stars
 if [ "$(requests_merged)" != "esa gaia|ari gaia|esa apass|skymapper apass|" ] || [ "$(awk '{$2 = $3 = ""; print}' "$WORK_DIR/catalog_gaia_fails.txt" 2>/dev/null | cksum)" != "$(awk '{$2 = $3 = ""; print}' "$WORK_DIR/catalog_apass_esa.txt" | cksum)" ];then
  fail PHOTFIELDCAT135 "without Gaia the plate solver did not go on with APASS (requests $(requests_merged))"
  show_solver_run gaia_fails
 fi

 echo "Plate solver run: no APASS field catalog - the APASS list query via VizieR"
 FIELD_TEST_REPLY_ESA=noreply FIELD_TEST_REPLY_SKYMAPPER=other_header FIELD_TEST_VIZIER_REPLY=rows run_solver apass_vizier
 VIZIER_LIST_LENGTH=$(cat "$WORK_DIR/vizier_list_length.txt" 2>/dev/null)
 EXPECTED_LIST_LENGTH=$(( N_POSITIONS < 1000 ? N_POSITIONS : 1000 ))
 if [ "$(requests_merged)" != "esa apass|skymapper apass|vizier II/336/apass9|" ];then
  fail PHOTFIELDCAT141 "the plate solver did not go on with the APASS list query via VizieR: $(requests_merged)"
  show_solver_run apass_vizier
 elif [ "$VIZIER_LIST_LENGTH" != "$EXPECTED_LIST_LENGTH" ];then
  fail PHOTFIELDCAT142 "the VizieR list has $VIZIER_LIST_LENGTH positions, expected $EXPECTED_LIST_LENGTH (all good reference stars, at most 1000)"
 elif ! grep -q 'Positional cut of the APASS DR9 (VizieR) matches' "$WORK_DIR/solver_apass_vizier.log" || [ "$(awk '$15 + 0 > 13 && $15 + 0 < 14.01' "$WORK_DIR/catalog_apass_vizier.txt" | wc -l | awk '{print $1}')" -lt 20 ];then
  fail PHOTFIELDCAT143 "the VizieR magnitudes are not used, or the positional cut is not applied to them"
  show_solver_run apass_vizier
 fi

 echo "Plate solver run: few APASS stars"
 cp "$WORK_DIR/sky_apass.csv" "$WORK_DIR/sky_apass_full.csv"
 # The own stars of ten (then three) reference stars of the plain class
 awk '$2 == "normal" { print $1 }' "$WORK_DIR/expected.txt" | head -n 10 > "$WORK_DIR/ten.txt"
 awk -F, 'FNR == NR { keep[1000000 + $1] = 1 ; next } keep[$1]' "$WORK_DIR/ten.txt" "$WORK_DIR/sky_apass_full.csv" > "$WORK_DIR/sky_apass.csv"
 run_solver apass_ten
 if [ "$(stars_with_photometry "$WORK_DIR/catalog_apass_ten.txt")" != "10" ] || ! grep -q 'Positional cut of the APASS DR9 matches not applied: 10 matches' "$WORK_DIR/solver_apass_ten.log" ;then
  fail PHOTFIELDCAT151 "with 10 matches the positional cut is applied, or the stars lack photometry ($(stars_with_photometry "$WORK_DIR/catalog_apass_ten.txt") stars with photometry)"
  show_solver_run apass_ten
 fi
 awk -F, 'FNR == NR { if (FNR <= 3) keep[1000000 + $1] = 1 ; next } keep[$1]' "$WORK_DIR/ten.txt" "$WORK_DIR/sky_apass_full.csv" > "$WORK_DIR/sky_apass.csv"
 run_solver apass_three
 # The complete APASS catalog of the field has too few stars: VizieR is not asked for APASS,
 # Pan-STARRS1 is
 if [ "$(requests_merged)" != "esa apass|vizier PS1|" ] || [ "$(stars_with_photometry "$WORK_DIR/catalog_apass_three.txt")" != "0" ];then
  fail PHOTFIELDCAT152 "with three APASS stars the plate solver did not go on with Pan-STARRS1 alone, or kept photometry (requests $(requests_merged), $(stars_with_photometry "$WORK_DIR/catalog_apass_three.txt") stars with photometry)"
  show_solver_run apass_three
 fi
 cp "$WORK_DIR/sky_apass_full.csv" "$WORK_DIR/sky_apass.csv"

 echo "Plate solver runs: the cache"
 mkdir -p "$WORK_DIR/solver_cache"
 VAST_FIELD_CATALOG_CACHE_DIR="$WORK_DIR/solver_cache" run_solver apass_cache1
 VAST_FIELD_CATALOG_CACHE_DIR="$WORK_DIR/solver_cache" run_solver apass_cache2
 if [ "$(number_of_requests)" != "0" ] || ! cmp -s "$WORK_DIR/catalog_apass_cache2.txt" "$WORK_DIR/catalog_apass_esa.txt" ;then
  fail PHOTFIELDCAT161 "the second run on the field did not use the cached table, or got other photometry (requests $(requests_merged))"
  show_solver_run apass_cache2
 fi

 if grep -q '^UNEXPECTED' "$WORK_DIR/requests.log" ;then
  fail PHOTFIELDCAT171 "the plate solver made a request to another address: $(grep '^UNEXPECTED' "$WORK_DIR/requests.log" | head -n 1)"
 fi
 # shellcheck disable=SC2012
 if [ "$(ls photometric_field_catalog_*.positions photometric_field_catalog_*.table 2>/dev/null | wc -l | awk '{print $1}')" != "0" ];then
  fail PHOTFIELDCAT172 "the plate solver left its files for the fetcher behind: $(ls photometric_field_catalog_* | head -n 3 | tr '\n' ' ')"
 fi
fi

if [ -n "$FAILED_CODES" ];then
 echo "Failed checks:$FAILED_CODES"
 exit 1
fi
if [ -z "$SOLVER_PART_SKIP_REASON" ];then
 echo "All checks of the photometric field catalogs passed"
else
 echo "All checks of the fetcher passed, the plate solver part was not performed ($SOLVER_PART_SKIP_REASON)"
fi
exit 0
