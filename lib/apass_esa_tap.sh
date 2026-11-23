#!/usr/bin/env bash
#
# Batch APASS DR9 cone search via the ESA Gaia Archive. Input is one
# RA Dec pair per line. Output is target number (1-based), B eB V eV
# r' er' i' ei' g' eg', space separated, with at most one match per target.

export LC_ALL=C
if [ "$#" -ne 4 ]; then
 echo "Usage: $0 positions_file radius_arcsec brightest_V faintest_V" >&2
 exit 1
fi

positions=$1
brightest=$3
faintest=$4
number='^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$'
radius=$(awk -v radius="$2" -v bright="$brightest" -v faint="$faintest" -v number="$number" '
 BEGIN {
  if (radius !~ number || radius <= 0 || bright !~ number || faint !~ number || bright + 0 > faint + 0)
   exit 1
  printf "%.10f", radius / 3600
 }
') || exit 1

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/vast-apass-esa.XXXXXXXX") || exit 1
trap 'rm -rf -- "$work_dir"' EXIT
trap 'exit 1' HUP INT TERM

if ! awk -v number="$number" '
 BEGIN {
  print "<?xml version=\"1.0\"?>"
  print "<VOTABLE xmlns=\"http://www.ivoa.net/xml/VOTable/v1.3\" version=\"1.3\"><RESOURCE><TABLE>"
  print "<FIELD name=\"target_id\" datatype=\"int\"/>"
  print "<FIELD name=\"target_ra\" datatype=\"double\" unit=\"deg\"/>"
  print "<FIELD name=\"target_dec\" datatype=\"double\" unit=\"deg\"/>"
  print "<DATA><TABLEDATA>"
 }
 NF != 2 || $1 !~ number || $2 !~ number {exit 1}
 {printf "<TR><TD>%d</TD><TD>%s</TD><TD>%s</TD></TR>\n", NR, $1, $2}
 END {
  if (NR == 0)
   exit 1
  print "</TABLEDATA></DATA></TABLE></RESOURCE></VOTABLE>"
 }
' "$positions" > "$work_dir/positions.vot"; then
 echo "ERROR: Invalid APASS target list" >&2
 exit 1
fi

# Use the brightest valid V match in each cone, as in the VizieR query.
# The extra row lets us detect a capped response even in CSV format.
max_rows=10001
query="SELECT TOP $max_rows t.target_id, a.bmag, a.e_bmag, a.vmag, a.e_vmag,
 a.r_mag, a.e_r_mag, a.i_mag, a.e_i_mag, a.g_mag, a.e_g_mag
 FROM tap_upload.targets AS t JOIN external.apassdr9 AS a
 ON 1 = CONTAINS(POINT('ICRS', a.raj2000, a.dej2000),
 CIRCLE('ICRS', t.target_ra, t.target_dec, $radius))
 WHERE a.vmag BETWEEN $brightest AND $faintest
 AND a.bmag IS NOT NULL AND a.r_mag IS NOT NULL AND a.i_mag IS NOT NULL
 ORDER BY t.target_id, a.vmag, a.recno"
if ! curl --fail --silent --show-error --compressed --connect-timeout 10 --max-time 90 \
 --form REQUEST=doQuery --form LANG=ADQL --form FORMAT=csv --form "MAXREC=$max_rows" \
 --form 'UPLOAD=targets,param:positions' \
 --form "positions=@$work_dir/positions.vot;type=application/x-votable+xml" \
 --form-string "QUERY=$query" -o "$work_dir/apass.csv" \
 'https://gea.esac.esa.int/tap-server/tap/sync'; then
 exit 1
fi

# ESA returns numeric CSV fields. Convert missing optional values to zero
# for the existing APASS error defaults and validate the response before use.
if ! awk -F, -v number="$number" -v max_rows="$max_rows" '
 {sub(/\r$/, "")}
 NR == 1 {
  if ($0 != "target_id,bmag,e_bmag,vmag,e_vmag,r_mag,e_r_mag,i_mag,e_i_mag,g_mag,e_g_mag")
   exit 1
  next
 }
 NR > max_rows || NF != 11 || $1 !~ /^[1-9][0-9]*$/ {exit 1}
 {
  for (i = 2; i <= NF; i++) {
   if ($i == "")
    $i = 0
   else if ($i !~ number)
    exit 1
  }
  if ($2 == 0 || $4 == 0 || $6 == 0 || $8 == 0 || seen[$1]++)
   next
  printf "%s %s %s %s %s %s %s %s %s %s %s\n", $1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11
 }
 END {if (NR == 0) exit 1}
' "$work_dir/apass.csv"; then
 echo "WARNING: Invalid or capped APASS response from ESA TAP" >&2
 exit 1
fi
