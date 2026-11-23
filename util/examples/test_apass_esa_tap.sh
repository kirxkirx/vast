#!/usr/bin/env bash
#
# Test of the APASS query through the ESA Gaia Archive: the client lib/apass_esa_tap.sh and the
# code of util/solve_plate_with_UCAC5 (search_APASS() in src/solve_plate_with_UCAC5.c) that
# applies its result and falls back to the APASS query through VizieR.
#
# Nothing is asked from ESA or VizieR here. A 'curl' script put first in PATH takes their
# place: it records every request and answers the way each check needs. It stands in for the
# two services only, not for a star catalog: the magnitudes it returns encode the number of
# the position they were asked for (V = base + number/1000, the base being 10 for ESA and 13
# for VizieR), so a magnitude in the output of the plate solver shows which position it was
# returned for and which of the two services it came from.
#
# The client:
#  - the request: the URL, the form fields, the uploaded table of positions, the search radius
#    and the magnitude range in the query, the columns in the order of the reply header the
#    client checks for, and an ORDER BY clause without table-qualified names (the TAP service
#    of ARI rejects qualified names with HTTP 400; had ESA done the same, every call would
#    have fallen back to VizieR without a word - see .claude/notes.md);
#  - replies it has to accept: missing g magnitudes and missing errors (written as 0), CR LF
#    line ends, several rows for one position (the first one counts), a table without rows,
#    10000 rows;
#  - replies it has to refuse as a whole, without the word ERROR in its messages (the plate
#    solver goes on with VizieR, and an ERROR line marks a field as failed in the unmw
#    summary): an empty reply, the maintenance page ESA serves with HTTP 200, another header,
#    a value that is not a number, a wrong number of columns, a position number that is not a
#    positive integer, 10001 rows (the reply may be cut), an HTTP error;
#  - wrong arguments and unusable lists of positions end it before any request is made;
#  - its temporary directory is removed.
# The plate solver runs on the plate-solved NMW archive image wcs_fd_Per3_2011-10-31_001.fts
# of the VaST test data. It matches the stars with UCAC5 before it asks for photometry, so
# this part needs the local UCAC5 copy (lib/catalogs/ucac5) and is reported as not performed
# where there is none:
#  - ESA answers for every position: each star gets the magnitudes returned for its own
#    position in all bands, Cousins R and I follow from them, and VizieR is not asked;
#  - ESA answers with an HTTP error: the stars get the VizieR magnitudes;
#  - ESA answers for three positions only, or with a row for a position that was not sent:
#    nothing of that reply is used, the stars get the VizieR magnitudes;
#  - ESA serves its maintenance page and VizieR has neither APASS nor Pan-STARRS1 stars: the
#    output catalog is written without photometry.
#
# Usage: util/examples/test_apass_esa_tap.sh
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

# Work in the VaST directory this script belongs to
cd "$(dirname "$0")/../.." || exit 1

FAILED_CODES=""
fail() {
 FAILED_CODES="$FAILED_CODES $1"
 echo "FAILED: $1 $2"
}

CLIENT="$PWD/lib/apass_esa_tap.sh"
ESA_URL="https://gea.esac.esa.int/tap-server/tap/sync"
REPLY_HEADER="target_id,bmag,e_bmag,vmag,e_vmag,r_mag,e_r_mag,i_mag,e_i_mag,g_mag,e_g_mag"
SOLVER_IMAGE_NAME="wcs_fd_Per3_2011-10-31_001.fts"
SOLVER_IMAGE_DIR="../individual_images_test"
SOLVER_CATALOG="$SOLVER_IMAGE_NAME.wcscat.ucac5"
# The V magnitude the stand-in returns for the position number N is base + N/1000
ESA_V_BASE=10
VIZIER_V_BASE=13

if [ ! -x "$CLIENT" ];then
 fail APASSESATAP_TOOL_NOT_FOUND "no executable lib/apass_esa_tap.sh in the VaST directory"
 exit 1
fi

WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vast_apass_esa_tap_test.XXXXXX" 2>/dev/null)
if [ -z "$WORK_DIR" ] || [ ! -d "$WORK_DIR" ];then
 fail APASSESATAP000 "cannot create a work directory"
 exit 1
fi
CLIENT_TMP_DIR="$WORK_DIR/tmpdir_of_the_client"
if ! mkdir -p "$WORK_DIR/bin" "$CLIENT_TMP_DIR" ;then
 fail APASSESATAP000 "cannot create directories in $WORK_DIR"
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
 rm -rf "$WORK_DIR"
}
trap clean_up EXIT
trap 'exit 1' HUP INT TERM

# The stand-in for curl. It is told what to answer through the environment:
#   APASS_TEST_DIR           where it records the requests
#   APASS_TEST_ESA_REPLY     rows (a row for every position), first3 (for the first three),
#                            extra_row (also for a position that was not sent), http_error,
#                            or file:PATH (the content of that file)
#   APASS_TEST_VIZIER_REPLY  rows (an APASS row for every position of the list) or none; a
#                            reply to another catalog query never has rows
cat > "$WORK_DIR/bin/curl" <<'STAND_IN_FOR_CURL'
#!/usr/bin/env bash
URL=""
OUTPUT_FILE=""
DATA_FILE=""
POSITIONS_FILE=""
PREVIOUS_ARGUMENT=""
for ARGUMENT in "$@" ;do
 case "$PREVIOUS_ARGUMENT" in
  -o) OUTPUT_FILE="$ARGUMENT" ;;
  --data-binary) DATA_FILE="${ARGUMENT#@}" ;;
 esac
 case "$ARGUMENT" in
  http://*|https://*) URL="$ARGUMENT" ;;
  positions=@*) POSITIONS_FILE="${ARGUMENT#positions=@}" ; POSITIONS_FILE="${POSITIONS_FILE%%;*}" ;;
  QUERY=*) printf '%s\n' "${ARGUMENT#QUERY=}" > "$APASS_TEST_DIR/esa_query.txt" ;;
 esac
 PREVIOUS_ARGUMENT="$ARGUMENT"
done
case "$URL" in
 https://gea.esac.esa.int/tap-server/tap/sync)
  echo "ESA" >> "$APASS_TEST_DIR/requests.log"
  printf '%s\n' "$@" > "$APASS_TEST_DIR/esa_request_arguments.txt"
  cp "$POSITIONS_FILE" "$APASS_TEST_DIR/esa_positions.vot" 2>/dev/null
  case "$APASS_TEST_ESA_REPLY" in
   http_error)
    echo "curl: (22) The requested URL returned error: 503" >&2
    exit 22
    ;;
   file:*)
    cp "${APASS_TEST_ESA_REPLY#file:}" "$OUTPUT_FILE" || exit 23
    ;;
   *)
    awk -v v="$APASS_TEST_ESA_V_BASE" -v reply="$APASS_TEST_ESA_REPLY" '
     function row(id) {
      printf "%d,%.3f,0.011,%.3f,0.012,%.3f,0.013,%.3f,0.014,%.3f,0.015\n", id, v + 2 + id / 1000, v + id / 1000, v - 0.2 + id / 1000, v - 0.4 + id / 1000, v + 1 + id / 1000
     }
     BEGIN { print "target_id,bmag,e_bmag,vmag,e_vmag,r_mag,e_r_mag,i_mag,e_i_mag,g_mag,e_g_mag" }
     /<TR><TD>/ {
      n++
      if (reply == "first3" && n > 3) next
      row(n)
     }
     END { if (reply == "extra_row") row(n + 1) }
    ' "$POSITIONS_FILE" > "$OUTPUT_FILE" || exit 23
    ;;
  esac
  exit 0
  ;;
 */viz-bin/*)
  SOURCE=$(grep '^-source=' "$DATA_FILE" 2>/dev/null | head -n 1)
  echo "VizieR $SOURCE" >> "$APASS_TEST_DIR/requests.log"
  if [ "$APASS_TEST_VIZIER_REPLY" = "rows" ] && [ "$SOURCE" = "-source=II/336/apass9" ];then
   # One line for each position of the list in the form the plate solver asks for: the
   # position as it was sent, the distance, the catalog position and the ten values
   awk -v v="$APASS_TEST_VIZIER_V_BASE" '
    /^-c=<<====/ { in_list = 1 ; next }
    /^====/ { in_list = 0 }
    in_list && NF == 2 {
     id++
     printf "%-40s %6.3f %10.6f %+10.6f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f %6.3f\n", $1 " " $2, 0.123, $1, $2, v + 2 + id / 1000, 0.011, v + id / 1000, 0.012, v - 0.2 + id / 1000, 0.013, v - 0.4 + id / 1000, 0.014, v + 1 + id / 1000, 0.015
    }
   ' "$DATA_FILE"
  fi
  # The last line of a complete VizieR reply
  echo "#END#   "
  exit 0
  ;;
esac
echo "UNEXPECTED $URL" >> "$APASS_TEST_DIR/requests.log"
exit 7
STAND_IN_FOR_CURL
chmod +x "$WORK_DIR/bin/curl"
export APASS_TEST_DIR="$WORK_DIR"
export APASS_TEST_ESA_V_BASE="$ESA_V_BASE"
export APASS_TEST_VIZIER_V_BASE="$VIZIER_V_BASE"
: > "$WORK_DIR/requests.log"

##### The client #####

# Run the client with the stand-in for curl
# $1 - what the stand-in answers (APASS_TEST_ESA_REPLY), the rest - the arguments of the client
# Sets CLIENT_EXIT_CODE; the output is in $WORK_DIR/client.out, the messages in client.err
run_client() {
 CLIENT_REPLY="$1"
 shift
 APASS_TEST_ESA_REPLY="$CLIENT_REPLY" TMPDIR="$CLIENT_TMP_DIR" PATH="$WORK_DIR/bin:$PATH" "$CLIENT" "$@" > "$WORK_DIR/client.out" 2> "$WORK_DIR/client.err"
 CLIENT_EXIT_CODE=$?
}
number_of_requests() {
 grep -c . "$WORK_DIR/requests.log"
}
number_of_output_rows() {
 grep -c . "$WORK_DIR/client.out"
}

POSITIONS="$WORK_DIR/positions.txt"
printf '%s\n' '10.5 20.25' '350.123456 -45.5' '0.000001 89.9' > "$POSITIONS"

echo "The request of the client"
run_client rows "$POSITIONS" 2.0 7.0 16.5
if [ $CLIENT_EXIT_CODE -ne 0 ] || [ "$(number_of_output_rows)" != "3" ] || [ "$(head -n 1 "$WORK_DIR/client.out")" != "1 12.001 0.011 10.001 0.012 9.801 0.013 9.601 0.014 11.001 0.015" ] || [ "$(tail -n 1 "$WORK_DIR/client.out")" != "3 12.003 0.011 10.003 0.012 9.803 0.013 9.603 0.014 11.003 0.015" ];then
 fail APASSESATAP001 "the client does not return the three rows of the reply (exit code $CLIENT_EXIT_CODE): $(head -n 1 "$WORK_DIR/client.out")"
fi
if [ "$(number_of_requests)" != "1" ] || [ "$(cat "$WORK_DIR/requests.log")" != "ESA" ];then
 fail APASSESATAP002 "the client did not make exactly one request to $ESA_URL: $(tr '\n' ' ' < "$WORK_DIR/requests.log")"
else
 for REQUEST_ARGUMENT in "$ESA_URL" "REQUEST=doQuery" "LANG=ADQL" "FORMAT=csv" "MAXREC=10001" "UPLOAD=targets,param:positions" ;do
  if ! grep -q -x -F -e "$REQUEST_ARGUMENT" "$WORK_DIR/esa_request_arguments.txt" ;then
   fail APASSESATAP003 "the request has no $REQUEST_ARGUMENT"
  fi
 done
 QUERY_ON_ONE_LINE=$(tr '\n' ' ' < "$WORK_DIR/esa_query.txt" | tr -s ' ')
 for QUERY_PART in "FROM tap_upload.targets AS t JOIN external.apassdr9 AS a" "CIRCLE('ICRS', t.target_ra, t.target_dec, 0.0005555556)" "a.vmag BETWEEN 7.0 AND 16.5" "a.bmag IS NOT NULL AND a.r_mag IS NOT NULL AND a.i_mag IS NOT NULL" ;do
  if ! echo "$QUERY_ON_ONE_LINE" | grep -q -F -e "$QUERY_PART" ;then
   fail APASSESATAP004 "the query has no '$QUERY_PART': $QUERY_ON_ONE_LINE"
  fi
 done
 # The columns it asks for, in the order of the header it expects in the reply
 QUERY_COLUMNS=$(echo "$QUERY_ON_ONE_LINE" | sed -e 's/^ *SELECT TOP [0-9]* //' -e 's/ FROM .*//' -e 's/[at]\.//g' -e 's/ //g')
 if [ "$QUERY_COLUMNS" != "$REPLY_HEADER" ];then
  fail APASSESATAP005 "the query asks for the columns '$QUERY_COLUMNS', the client expects the reply header '$REPLY_HEADER'"
 fi
 # The first match of a position has to be its brightest one, and a TAP service of the Gaia
 # tables may refuse a table-qualified name in ORDER BY
 ORDER_BY_CLAUSE=$(echo "$QUERY_ON_ONE_LINE" | grep ' ORDER BY ' | sed -e 's/.* ORDER BY //' -e 's/ *$//')
 case "$ORDER_BY_CLAUSE" in
  "target_id, vmag"*) ;;
  *) fail APASSESATAP006 "the query does not order the rows by position and V magnitude: '$ORDER_BY_CLAUSE'" ;;
 esac
 case "$ORDER_BY_CLAUSE" in
  *.*) fail APASSESATAP007 "the ORDER BY clause has a table-qualified name: '$ORDER_BY_CLAUSE'" ;;
 esac
 if [ "$(grep -c '<TR><TD>' "$WORK_DIR/esa_positions.vot")" != "3" ] || ! grep -q -F '<TR><TD>2</TD><TD>350.123456</TD><TD>-45.5</TD></TR>' "$WORK_DIR/esa_positions.vot" || ! grep -q -F '<FIELD name="target_id" datatype="int"/>' "$WORK_DIR/esa_positions.vot" || ! grep -q -F '<FIELD name="target_ra" datatype="double" unit="deg"/>' "$WORK_DIR/esa_positions.vot" || ! grep -q -F '<FIELD name="target_dec" datatype="double" unit="deg"/>' "$WORK_DIR/esa_positions.vot" ;then
  fail APASSESATAP008 "the uploaded table does not hold the three numbered positions"
 fi
fi

echo "Replies the client has to accept"
# $1 - the name of the reply file $WORK_DIR/reply_<name>.csv, $2 - the number of rows expected
# in the output, $3 and $4 - its first and last row if given
expect_accepted() {
 run_client "file:$WORK_DIR/reply_$1.csv" "$POSITIONS" 2.0 7.0 16.5
 if [ $CLIENT_EXIT_CODE -ne 0 ] || [ "$(number_of_output_rows)" != "$2" ] || { [ -n "$3" ] && [ "$(head -n 1 "$WORK_DIR/client.out")" != "$3" ] ; } || { [ -n "$4" ] && [ "$(tail -n 1 "$WORK_DIR/client.out")" != "$4" ] ; } ;then
  fail "APASSESATAP010_$1" "exit code $CLIENT_EXIT_CODE, $(number_of_output_rows) rows, the first one: $(head -n 1 "$WORK_DIR/client.out")"
 fi
}
printf '%s\n' "$REPLY_HEADER" '1,12.5,0.02,11.9,0.03,11.7,0.02,11.5,0.04,,' '2,13.5,,12.9,,12.7,,12.5,,12.2,0.05' > "$WORK_DIR/reply_missing_g_and_errors.csv"
expect_accepted missing_g_and_errors 2 "1 12.5 0.02 11.9 0.03 11.7 0.02 11.5 0.04 0 0" "2 13.5 0 12.9 0 12.7 0 12.5 0 12.2 0.05"
printf '%s\r\n' "$REPLY_HEADER" '1,12.5,0.02,11.9,0.03,11.7,0.02,11.5,0.04,12.1,0.03' '2,13.5,0.02,12.9,0.03,12.7,0.02,12.5,0.04,13.1,0.03' > "$WORK_DIR/reply_cr_lf.csv"
expect_accepted cr_lf 2 "1 12.5 0.02 11.9 0.03 11.7 0.02 11.5 0.04 12.1 0.03" "2 13.5 0.02 12.9 0.03 12.7 0.02 12.5 0.04 13.1 0.03"
printf '%s\n' "$REPLY_HEADER" '1,12.5,0.02,11.9,0.03,11.7,0.02,11.5,0.04,12.1,0.03' '1,13.5,0.02,12.9,0.03,12.7,0.02,12.5,0.04,13.1,0.03' '2,10.5,0.02,9.9,0.03,9.7,0.02,9.5,0.04,10.1,0.03' > "$WORK_DIR/reply_two_rows_for_one_position.csv"
expect_accepted two_rows_for_one_position 2 "1 12.5 0.02 11.9 0.03 11.7 0.02 11.5 0.04 12.1 0.03" "2 10.5 0.02 9.9 0.03 9.7 0.02 9.5 0.04 10.1 0.03"
# A row without one of B, V, r, i is not a match: the next row of that position counts
printf '%s\n' "$REPLY_HEADER" '1,,,11.9,0.03,11.7,0.02,11.5,0.04,12.1,0.03' '1,13.5,0.02,12.9,0.03,12.7,0.02,12.5,0.04,13.1,0.03' > "$WORK_DIR/reply_row_without_b.csv"
expect_accepted row_without_b 1 "1 13.5 0.02 12.9 0.03 12.7 0.02 12.5 0.04 13.1 0.03" ""
printf '%s\n' "$REPLY_HEADER" > "$WORK_DIR/reply_no_rows.csv"
expect_accepted no_rows 0 "" ""
awk -v header="$REPLY_HEADER" 'BEGIN { print header ; for (i = 0; i < 10000; i++) printf "%d,12.5,0.02,11.9,0.03,11.7,0.02,11.5,0.04,12.1,0.03\n", (i % 1000) + 1 }' > "$WORK_DIR/reply_10000_rows.csv"
expect_accepted 10000_rows 1000 "1 12.5 0.02 11.9 0.03 11.7 0.02 11.5 0.04 12.1 0.03" "1000 12.5 0.02 11.9 0.03 11.7 0.02 11.5 0.04 12.1 0.03"

echo "Replies the client has to refuse"
# $1 - what the stand-in answers, $2 - a name for the failure code
expect_refused() {
 run_client "$1" "$POSITIONS" 2.0 7.0 16.5
 if [ $CLIENT_EXIT_CODE -eq 0 ];then
  fail "APASSESATAP011_$2" "the client accepted the reply and returned $(number_of_output_rows) rows"
 elif grep -q 'ERROR' "$WORK_DIR/client.err" ;then
  fail "APASSESATAP012_$2" "a message of the client has the word ERROR: $(head -n 1 "$WORK_DIR/client.err")"
 fi
}
: > "$WORK_DIR/reply_empty.csv"
expect_refused "file:$WORK_DIR/reply_empty.csv" empty
printf '%s\n' '<html class="ltr" dir="ltr" lang="en-GB">' '<head>' '<title>ESDC Archives downtime</title>' '</head>' '<body>Maintenance ongoing!</body>' '</html>' > "$WORK_DIR/reply_maintenance_page.csv"
expect_refused "file:$WORK_DIR/reply_maintenance_page.csv" maintenance_page
printf '%s\n' '"target_id","bmag","e_bmag","vmag","e_vmag","r_mag","e_r_mag","i_mag","e_i_mag","g_mag","e_g_mag"' '1,12.5,0.02,11.9,0.03,11.7,0.02,11.5,0.04,12.1,0.03' > "$WORK_DIR/reply_other_header.csv"
expect_refused "file:$WORK_DIR/reply_other_header.csv" other_header
printf '%s\n' "$REPLY_HEADER" '1,12.5,0.02,11.9,0.03,11.7,0.02,11.5,0.04,NaN,NaN' > "$WORK_DIR/reply_not_a_number.csv"
expect_refused "file:$WORK_DIR/reply_not_a_number.csv" not_a_number
printf '%s\n' "$REPLY_HEADER" '1,12.5,0.02,11.9,0.03,11.7,0.02,11.5,0.04,12.1' > "$WORK_DIR/reply_ten_columns.csv"
expect_refused "file:$WORK_DIR/reply_ten_columns.csv" ten_columns
printf '%s\n' "$REPLY_HEADER" '0,12.5,0.02,11.9,0.03,11.7,0.02,11.5,0.04,12.1,0.03' > "$WORK_DIR/reply_position_zero.csv"
expect_refused "file:$WORK_DIR/reply_position_zero.csv" position_zero
awk -v header="$REPLY_HEADER" 'BEGIN { print header ; for (i = 0; i < 10001; i++) printf "%d,12.5,0.02,11.9,0.03,11.7,0.02,11.5,0.04,12.1,0.03\n", (i % 1000) + 1 }' > "$WORK_DIR/reply_10001_rows.csv"
expect_refused "file:$WORK_DIR/reply_10001_rows.csv" 10001_rows
expect_refused http_error http_error

echo "Arguments and lists of positions the client has to refuse before any request"
printf '%s\n' '10.5 20.25' 'abc 20.0' > "$WORK_DIR/positions_not_a_number.txt"
printf '%s\n' '10.5 20.25 1.0' > "$WORK_DIR/positions_three_columns.txt"
: > "$WORK_DIR/positions_empty.txt"
REQUESTS_SO_FAR=$(number_of_requests)
# name:arguments (the word POSITIONS stands for the good list of positions)
for REFUSED_ARGUMENTS in "three_arguments:POSITIONS 2.0 7.0" "radius_zero:POSITIONS 0 7.0 16.5" "radius_not_a_number:POSITIONS abc 7.0 16.5" "bright_limit_fainter:POSITIONS 2.0 16.5 7.0" "no_such_file:$WORK_DIR/positions_no_such_file.txt 2.0 7.0 16.5" "empty_list:$WORK_DIR/positions_empty.txt 2.0 7.0 16.5" "position_not_a_number:$WORK_DIR/positions_not_a_number.txt 2.0 7.0 16.5" "position_three_columns:$WORK_DIR/positions_three_columns.txt 2.0 7.0 16.5" ;do
 REFUSED_NAME="${REFUSED_ARGUMENTS%%:*}"
 REFUSED_ARGUMENTS="${REFUSED_ARGUMENTS#*:}"
 # The arguments have no white space of their own, so they can be split on it
 # shellcheck disable=SC2086
 run_client rows ${REFUSED_ARGUMENTS/POSITIONS/$POSITIONS}
 if [ $CLIENT_EXIT_CODE -eq 0 ] || [ "$(number_of_requests)" != "$REQUESTS_SO_FAR" ];then
  fail "APASSESATAP020_$REFUSED_NAME" "exit code $CLIENT_EXIT_CODE, $(( $(number_of_requests) - REQUESTS_SO_FAR )) request(s) made"
  REQUESTS_SO_FAR=$(number_of_requests)
 fi
done

if grep -q '^UNEXPECTED' "$WORK_DIR/requests.log" ;then
 fail APASSESATAP030 "the client made a request to another address: $(grep '^UNEXPECTED' "$WORK_DIR/requests.log" | head -n 1)"
fi
# shellcheck disable=SC2012
if [ "$(ls -A "$CLIENT_TMP_DIR" | wc -l | awk '{print $1}')" != "0" ];then
 fail APASSESATAP031 "the client left files in its temporary directory: $(ls -A "$CLIENT_TMP_DIR" | head -n 3 | tr '\n' ' ')"
fi

##### The plate solver #####

SOLVER_PART_SKIP_REASON=""
if [ ! -x util/solve_plate_with_UCAC5 ] || [ ! -f default.sex.NMW_mass_processing ];then
 fail APASSESATAP_TOOL_NOT_FOUND "util/solve_plate_with_UCAC5 is not built (run make in the VaST directory)"
 SOLVER_PART_SKIP_REASON="notbuilt"
elif [ ! -f lib/catalogs/ucac5/z001 ];then
 SOLVER_PART_SKIP_REASON="noucac5"
 echo "NOT_PERFORMED: NOT_PERFORMED_APASSESATAP_SOLVER_noucac5 the plate solver part needs the local UCAC5 copy lib/catalogs/ucac5"
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
  echo "NOT_PERFORMED: NOT_PERFORMED_APASSESATAP_SOLVER_nodata the test image $SOLVER_IMAGE_DIR/$SOLVER_IMAGE_NAME is not available"
 fi
fi

# Run the plate solver on the test image with the stand-in for curl
# $1 - a name of the run for its log file $WORK_DIR/solver_<name>.log
# $2 - what the stand-in answers for ESA, $3 - for VizieR
# Sets SOLVER_EXIT_CODE
run_solver() {
 rm -f "$SOLVER_CATALOG" "$WORK_DIR/esa_positions.vot" "$WORK_DIR/esa_query.txt"
 : > "$WORK_DIR/requests.log"
 # VIZIER_MIRROR_RECORD_ONLY=yes: lib/choose_vizier_mirror.sh names a mirror without asking
 # one, and without recording what the stand-in would have told it
 APASS_TEST_ESA_REPLY="$2" APASS_TEST_VIZIER_REPLY="$3" VIZIER_MIRROR_RECORD_ONLY=yes PATH="$WORK_DIR/bin:$PATH" util/solve_plate_with_UCAC5 "$SOLVER_IMAGE_DIR/$SOLVER_IMAGE_NAME" > "$WORK_DIR/solver_$1.log" 2>&1
 SOLVER_EXIT_CODE=$?
}
# The requests of the last run on one line, for example: ESA|VizieR -source=II/336/apass9|
requests_of_the_run() {
 tr '\n' '|' < "$WORK_DIR/requests.log"
}
# Print two numbers: how many stars of the output catalog have a V magnitude, and how many of
# these V magnitudes the stand-in made for the service with the base magnitude $1
stars_with_v() {
 awk -v v="$1" '$15 + 0 != 0 { n++ ; if ($15 + 0 > v && $15 + 0 <= v + 1.0005) n_of_this_service++ } END { printf "%d %d\n", n, n_of_this_service }' "$SOLVER_CATALOG" 2>/dev/null
}
show_solver_run() {
 echo " the requests of the run $1: $(requests_of_the_run)"
 echo " what the plate solver said about the photometric catalogs (exit code $SOLVER_EXIT_CODE):"
 grep -e 'APASS' -e 'Pan-STARRS' -e 'photometric' -e 'END#' "$WORK_DIR/solver_$1.log" 2>/dev/null | grep -v '^export ' | head -n 12 | sed 's/^/  /'
}

if [ -z "$SOLVER_PART_SKIP_REASON" ];then
 SOLVER_PART_STARTED="yes"
 rm -f "$SOLVER_IMAGE_NAME" "$SOLVER_IMAGE_NAME".*
 cp default.sex.NMW_mass_processing default.sex

 echo "Plate solver run: ESA answers for every position"
 FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
 run_solver esa rows rows
 N_POSITIONS=$(grep -c '<TR><TD>' "$WORK_DIR/esa_positions.vot" 2>/dev/null)
 if [ $SOLVER_EXIT_CODE -ne 0 ] || [ ! -s "$SOLVER_CATALOG" ];then
  fail APASSESATAP101 "the plate solver did not write $SOLVER_CATALOG (exit code $SOLVER_EXIT_CODE)"
 elif [ -z "$N_POSITIONS" ] || [ "$N_POSITIONS" -lt 100 ];then
  fail APASSESATAP102 "the plate solver sent only '$N_POSITIONS' positions to ESA"
 else
  if [ "$(requests_of_the_run)" != "ESA|" ];then
   fail APASSESATAP103 "the plate solver asked more than ESA once: $(requests_of_the_run)"
  fi
  if ! grep -q "Matched $N_POSITIONS stars with APASS via ESA TAP" "$WORK_DIR/solver_esa.log" ;then
   fail APASSESATAP104 "the plate solver does not report $N_POSITIONS stars matched with APASS via ESA TAP"
  fi
  # Each star has to carry the magnitudes returned for the position it was sent as
  sed -n 's:.*<TR><TD>\([0-9]*\)</TD><TD>\([^<]*\)</TD><TD>\([^<]*\)</TD></TR>.*:\1 \2 \3:p' "$WORK_DIR/esa_positions.vot" > "$WORK_DIR/esa_positions.txt"
  SEARCH_RADIUS_DEG=$(tr '\n' ' ' < "$WORK_DIR/esa_query.txt" | sed -e 's/.*t\.target_dec, *//' -e 's/).*//')
  ESA_RUN_SUMMARY=$(awk -v v="$ESA_V_BASE" -v radius_deg="$SEARCH_RADIUS_DEG" '
   function abs(x) { return x < 0 ? -x : x }
   NR == FNR { ra[$1] = $2 ; dec[$1] = $3 ; n_positions++ ; next }
   $15 + 0 != 0 {
    n_stars++
    id = int(($15 - v) * 1000 + 0.5)
    if (id < 1 || id > n_positions) { n_other_number++ ; next }
    if (seen[id]++) n_repeated++
    if (abs($13 - (v + 2 + id / 1000)) > 0.0006 || abs($17 - (v - 0.2 + id / 1000)) > 0.0006 || abs($19 - (v - 0.4 + id / 1000)) > 0.0006 || abs($25 - (v + 1 + id / 1000)) > 0.0006) n_mixed_bands++
    if ($14 != "0.011" || $16 != "0.012" || $18 != "0.013" || $20 != "0.014" || $26 != "0.015") n_other_errors++
    # Cousins R and I as set_apass_photometry() derives them from V, r and i
    rc = $15 - 1.09 * ($17 - $19) - 0.22
    if (abs($21 - rc) > 0.002 || abs($23 - (rc - ($17 - $19) - 0.21)) > 0.002) n_other_cousins++
    # The star lies where the position with this number was sent (the positions are those
    # of the UCAC5 epoch, so the limit is generous)
    d_dec = $3 - dec[id]
    d_ra = $2 - ra[id]
    if (d_ra > 180) d_ra -= 360
    if (d_ra < -180) d_ra += 360
    d_ra = d_ra * cos(dec[id] * 3.14159265358979 / 180)
    if (sqrt(d_ra * d_ra + d_dec * d_dec) > 3 * radius_deg) n_elsewhere++
   }
   END { printf "positions=%d stars=%d other_number=%d repeated=%d mixed_bands=%d other_errors=%d other_cousins=%d elsewhere=%d\n", n_positions, n_stars, n_other_number, n_repeated, n_mixed_bands, n_other_errors, n_other_cousins, n_elsewhere }
  ' "$WORK_DIR/esa_positions.txt" "$SOLVER_CATALOG")
  if [ "$ESA_RUN_SUMMARY" != "positions=$N_POSITIONS stars=$N_POSITIONS other_number=0 repeated=0 mixed_bands=0 other_errors=0 other_cousins=0 elsewhere=0" ];then
   fail APASSESATAP105 "the stars did not get the magnitudes of their own positions: $ESA_RUN_SUMMARY (radius $SEARCH_RADIUS_DEG deg)"
  fi
 fi
 if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
  show_solver_run esa
 fi

 # The three runs in which the ESA reply is of no use and VizieR has the APASS stars
 for ESA_REPLY_OF_NO_USE in http_error first3 extra_row ;do
  echo "Plate solver run: ESA reply '$ESA_REPLY_OF_NO_USE', VizieR has the stars"
  run_solver "$ESA_REPLY_OF_NO_USE" "$ESA_REPLY_OF_NO_USE" rows
  if [ $SOLVER_EXIT_CODE -ne 0 ] || [ ! -s "$SOLVER_CATALOG" ];then
   fail "APASSESATAP111_$ESA_REPLY_OF_NO_USE" "the plate solver did not write $SOLVER_CATALOG (exit code $SOLVER_EXIT_CODE)"
   show_solver_run "$ESA_REPLY_OF_NO_USE"
   continue
  fi
  FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
  if [ "$(requests_of_the_run)" != "ESA|VizieR -source=II/336/apass9|" ];then
   fail "APASSESATAP112_$ESA_REPLY_OF_NO_USE" "the plate solver did not ask ESA and then VizieR for APASS, once each: $(requests_of_the_run)"
  fi
  if ! grep -q 'Trying APASS via VizieR' "$WORK_DIR/solver_$ESA_REPLY_OF_NO_USE.log" ;then
   fail "APASSESATAP113_$ESA_REPLY_OF_NO_USE" "the plate solver does not say that it goes on with VizieR"
  fi
  # Nothing of the ESA reply may be left in the catalog, and VizieR has a star for every position
  if [ "$(stars_with_v "$ESA_V_BASE" | awk '{print $2}')" != "0" ];then
   fail "APASSESATAP114_$ESA_REPLY_OF_NO_USE" "stars carry magnitudes of the ESA reply: $(stars_with_v "$ESA_V_BASE")"
  fi
  STARS_WITH_VIZIER_V=$(stars_with_v "$VIZIER_V_BASE")
  if [ "${STARS_WITH_VIZIER_V%% *}" != "${STARS_WITH_VIZIER_V##* }" ] || [ "${STARS_WITH_VIZIER_V%% *}" -lt $((N_POSITIONS * 9 / 10)) ];then
   fail "APASSESATAP115_$ESA_REPLY_OF_NO_USE" "the stars did not get the VizieR magnitudes: $STARS_WITH_VIZIER_V stars with V and with a VizieR V, $N_POSITIONS positions"
  fi
  if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
   show_solver_run "$ESA_REPLY_OF_NO_USE"
  fi
 done

 echo "Plate solver run: the ESA maintenance page, VizieR has neither APASS nor Pan-STARRS1 stars"
 FAILED_CODES_BEFORE_THIS_RUN="$FAILED_CODES"
 run_solver no_photometry "file:$WORK_DIR/reply_maintenance_page.csv" none
 if [ $SOLVER_EXIT_CODE -ne 0 ] || [ ! -s "$SOLVER_CATALOG" ];then
  fail APASSESATAP121 "the plate solver did not write $SOLVER_CATALOG (exit code $SOLVER_EXIT_CODE)"
 else
  if [ "$(requests_of_the_run)" != "ESA|VizieR -source=II/336/apass9|VizieR -source=PS1|" ];then
   fail APASSESATAP122 "the plate solver did not ask ESA, VizieR for APASS and VizieR for Pan-STARRS1, once each: $(requests_of_the_run)"
  fi
  if [ "$(stars_with_v 0 | awk '{print $1}')" != "0" ];then
   fail APASSESATAP123 "the output catalog has photometry although no service had any: $(stars_with_v 0)"
  fi
 fi
 if [ "$FAILED_CODES" != "$FAILED_CODES_BEFORE_THIS_RUN" ];then
  show_solver_run no_photometry
 fi
fi

if [ -n "$FAILED_CODES" ];then
 echo "Failed checks:$FAILED_CODES"
 exit 1
fi
if [ -z "$SOLVER_PART_SKIP_REASON" ];then
 echo "All checks of the APASS query through ESA passed"
else
 echo "All checks of the client passed, the plate solver part was not performed ($SOLVER_PART_SKIP_REASON)"
fi
exit 0
