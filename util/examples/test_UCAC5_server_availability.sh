#!/usr/bin/env bash

# This script checks the availability of all UCAC5 remote servers
# used for plate solving. It sends a valid UCAC5 search request
# using the M31 test star list and verifies that each server returns
# catalog matches (same success criterion as the C code: >= 5 lines).

UCAC5_SERVERS="scan.sai.msu.ru vast.sai.msu.ru tau.kirx.net"
CONNECT_TIMEOUT=10
MAX_TIME=600

FAILED_SERVERS=""
UNREACHABLE_SERVERS=""
OK_SERVERS=""

# Determine VaST path
VAST_PATH=$(dirname "$0")/../..
VAST_PATH=$(cd "$VAST_PATH" && pwd)

# Download the M31 test input if needed (same as test_vast.sh)
if [ ! -d "$VAST_PATH"/../vast_test_lightcurves ];then
 mkdir "$VAST_PATH"/../vast_test_lightcurves
fi
if [ ! -f "$VAST_PATH"/../vast_test_lightcurves/test_vizquery_M31.input ];then
 echo "Downloading M31 test input..."
 cd "$VAST_PATH"/../vast_test_lightcurves || exit 1
 curl --silent --show-error -O "http://tau.kirx.net/vast_test_data/vast_test_lightcurves/test_vizquery_M31.input.bz2" && bunzip2 test_vizquery_M31.input.bz2
 if [ $? -ne 0 ];then
  echo "ERROR: cannot download test data"
  exit 1
 fi
 cd "$VAST_PATH" || exit 1
fi

TEST_INPUT="$VAST_PATH/../vast_test_lightcurves/test_vizquery_M31.input"
if [ ! -s "$TEST_INPUT" ];then
 echo "ERROR: test input file $TEST_INPUT not found or empty"
 exit 1
fi

TMPOUTPUT=$(mktemp ucac5_test_output_XXXXXX)

for SERVER in $UCAC5_SERVERS ;do
 echo -n "Testing UCAC5 server $SERVER ... "
 # Send a valid UCAC5 search request using the M31 test star list
 curl --silent --show-error --insecure \
  --connect-timeout "$CONNECT_TIMEOUT" --retry 1 --max-time "$MAX_TIME" \
  -F file=@"$TEST_INPUT" -F submit="Upload Image" \
  -F brightmag=9.0 -F faintmag=16.5 -F searcharcsec=6.0 \
  --output "$TMPOUTPUT" \
  "http://$SERVER/cgi-bin/ucac5/search_ucac5.py" 2>/dev/null
 CURL_EXIT=$?
 if [ $CURL_EXIT -ne 0 ];then
  echo "UNREACHABLE (curl exit code $CURL_EXIT)"
  UNREACHABLE_SERVERS="$UNREACHABLE_SERVERS $SERVER"
  continue
 fi
 if [ ! -s "$TMPOUTPUT" ];then
  echo "UNREACHABLE (empty response)"
  UNREACHABLE_SERVERS="$UNREACHABLE_SERVERS $SERVER"
  continue
 fi
 # Count total lines in the output (same criterion as the C code: >= 5)
 N_LINES=$(wc -l < "$TMPOUTPUT")
 if [ "$N_LINES" -lt 5 ];then
  echo "FAILED ($N_LINES lines returned, need >=5)"
  echo "  Server response: $(tr '\n' ' ' < "$TMPOUTPUT" | head -c 200)"
  FAILED_SERVERS="$FAILED_SERVERS $SERVER"
 else
  echo "OK ($N_LINES lines returned)"
  OK_SERVERS="$OK_SERVERS $SERVER"
 fi
done

rm -f "$TMPOUTPUT"

echo ""
echo "=== UCAC5 Server Status Summary ==="
if [ -n "$OK_SERVERS" ];then
 echo "WORKING:     $OK_SERVERS"
fi
if [ -n "$FAILED_SERVERS" ];then
 echo "CGI_BROKEN:  $FAILED_SERVERS"
fi
if [ -n "$UNREACHABLE_SERVERS" ];then
 echo "UNREACHABLE: $UNREACHABLE_SERVERS"
fi

if [ -n "$FAILED_SERVERS" ] || [ -n "$UNREACHABLE_SERVERS" ];then
 echo ""
 if [ -z "$OK_SERVERS" ];then
  echo "ERROR: no UCAC5 servers are returning valid results!"
  echo "Remote plate solving will fail. VizieR fallback may still work."
  exit 1
 else
  echo "WARNING: some UCAC5 servers are not working."
  echo "Plate solving should still work via the remaining server(s)."
  exit 1
 fi
fi

echo ""
echo "All UCAC5 servers are responding correctly."
exit 0
