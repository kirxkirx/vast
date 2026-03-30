#!/usr/bin/env bash

#################################
# Set the safe locale
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# This script downloads a list of recent transients from the Transient Name Server (TNS)
# and writes it to tns_transients_list.txt in the same format as tocp_transients_list.txt
# and asassn_transients_list.txt:
#   RA DEC  NAME  DATE MAG
# Example:
#   12:14:58.12 +63:47:16.4  SN 2026fvx  2026-03-21.12 15.6
#
# Rate limit: the TNS web search allows about 10 requests per 60-second window.

TNS_LIST_FILE="tns_transients_list.txt"

# Check for TNS credentials in environment
if [ -z "$TNS_ID" ] || [ -z "$TNS_NAME" ];then
 # Try to load from a config file
 if [ -f "$HOME/.tns_credentials" ];then
  . "$HOME/.tns_credentials"
 fi
fi

if [ -z "$TNS_ID" ] || [ -z "$TNS_NAME" ];then
 echo "WARNING: TNS credentials not set, skipping TNS update" 1>&2
 echo "To enable TNS checking, set environment variables:" 1>&2
 echo "  export TNS_ID=\"your_tns_id\"" 1>&2
 echo "  export TNS_NAME=\"your_tns_username\"" 1>&2
 echo "Or create ~/.tns_credentials with these exports." 1>&2
 echo "Get your TNS ID from https://www.wis-tns.org/user" 1>&2
 exit 1
fi

if [ -z "$TNS_TYPE" ];then
 TNS_TYPE="user"
fi

# Construct User-Agent with tns_marker
TNS_USER_AGENT="tns_marker{\"tns_id\":${TNS_ID},\"type\": \"${TNS_TYPE}\", \"name\":\"${TNS_NAME}\"}"

# TNS search URL - CSV format, last 30 days, up to 500 results, sorted by discovery date
TNS_SEARCH_URL="https://www.wis-tns.org/search?discovered_period_value=30&discovered_period_units=days&num_page=500&format=csv"

# Set timeout command
TIMEOUTCOMMAND=""
if command -v timeout > /dev/null 2>&1 ; then
 TIMEOUTCOMMAND="timeout 120"
fi

TNS_TEMP_FILE=$(mktemp /tmp/tns_csv_XXXXXX.tmp)

# Download the CSV
if command -v curl > /dev/null 2>&1 ; then
 $TIMEOUTCOMMAND curl $VAST_CURL_PROXY --connect-timeout 30 --retry 1 -s \
  -H "user-agent: ${TNS_USER_AGENT}" \
  "$TNS_SEARCH_URL" \
  -o "$TNS_TEMP_FILE" 2>/dev/null
 DOWNLOAD_EXIT_CODE=$?
elif command -v wget > /dev/null 2>&1 ; then
 $TIMEOUTCOMMAND wget -q --timeout=30 --tries=2 \
  -U "${TNS_USER_AGENT}" \
  "$TNS_SEARCH_URL" \
  -O "$TNS_TEMP_FILE" 2>/dev/null
 DOWNLOAD_EXIT_CODE=$?
else
 echo "ERROR: curl or wget is required" 1>&2
 rm -f "$TNS_TEMP_FILE"
 exit 1
fi

if [ $DOWNLOAD_EXIT_CODE -ne 0 ];then
 echo "ERROR: TNS download failed with exit code $DOWNLOAD_EXIT_CODE" 1>&2
 rm -f "$TNS_TEMP_FILE"
 exit 1
fi

if [ ! -s "$TNS_TEMP_FILE" ];then
 echo "ERROR: TNS returned empty response" 1>&2
 rm -f "$TNS_TEMP_FILE"
 exit 1
fi

# Check for error responses (HTML instead of CSV)
if grep -q '<title>403 Forbidden</title>' "$TNS_TEMP_FILE" 2>/dev/null ; then
 echo "ERROR: TNS returned 403 Forbidden (check credentials)" 1>&2
 rm -f "$TNS_TEMP_FILE"
 exit 1
fi

if grep -q '<title>429' "$TNS_TEMP_FILE" 2>/dev/null ; then
 echo "ERROR: TNS rate limit exceeded (429), try again later" 1>&2
 rm -f "$TNS_TEMP_FILE"
 exit 1
fi

# Verify it looks like CSV (first line should have "ID","Name","RA")
if ! head -1 "$TNS_TEMP_FILE" | grep -q '"ID","Name","RA"' ; then
 echo "ERROR: TNS response does not look like the expected CSV format" 1>&2
 head -3 "$TNS_TEMP_FILE" 1>&2
 rm -f "$TNS_TEMP_FILE"
 exit 1
fi

# Parse the CSV into the same format as tocp_transients_list.txt:
#   RA DEC  NAME  DATE MAG
#
# CSV columns (0-indexed):
#   0=ID, 1=Name, 2=RA, 3=DEC, 18=Discovery Mag/Flux, 20=Discovery Date (UT)
#
# The CSV is quoted, comma-separated. We use awk with FPAT to handle quoted fields.
awk 'BEGIN {
 FPAT = "([^,]*)|(\"[^\"]*\")"
}
NR > 1 {
 # Strip quotes from fields
 gsub(/"/, "", $2)   # Name
 gsub(/"/, "", $3)   # RA
 gsub(/"/, "", $4)   # DEC
 gsub(/"/, "", $19)  # Discovery Mag/Flux
 gsub(/"/, "", $21)  # Discovery Date (UT)
 # Skip entries with missing coordinates
 if ($3 == "" || $4 == "") next
 # Convert discovery date from "2026-03-29 20:24:01.728" to "2026-03-29.85"
 # (fractional day, matching the format used in other transient lists)
 date_str = $21
 split(date_str, dt, " ")
 if (dt[2] != "") {
  split(dt[2], tm, ":")
  frac_day = (tm[1] + tm[2]/60.0 + tm[3]/3600.0) / 24.0
  date_out = sprintf("%s.%02d", dt[1], int(frac_day * 100 + 0.5))
 } else {
  date_out = dt[1]
 }
 # Discovery magnitude (may be empty)
 mag = $19
 if (mag == "") mag = "---"
 printf "%s %s  %s  %s %s\n", $3, $4, $2, date_out, mag
}' "$TNS_TEMP_FILE" > "$TNS_LIST_FILE"

rm -f "$TNS_TEMP_FILE"

if [ ! -s "$TNS_LIST_FILE" ];then
 echo "WARNING: no transients parsed from TNS response" 1>&2
 touch "$TNS_LIST_FILE"
 exit 0
fi

NUM_ENTRIES=$(wc -l < "$TNS_LIST_FILE")
echo "TNS transients list updated: $NUM_ENTRIES entries"

exit 0
