#!/usr/bin/env bash
#
# Select the Gaia DR2 client (VizieR or ESA TAP) based on availability: VizieR whenever it
# answers a test query for a known Gaia DR2 star, ESA TAP only when VizieR does not.
#
# Usage: lib/choose_gaia_dr2_client.sh [VIZIER_SITE]
# Output: prints "vizquery" or "esa_tap" to stdout
#
# Environment variables:
#   GAIA_DR2_CLIENT - if set to "vizquery" or "esa_tap", skips probing and returns that value
#   VIZIER_SITE - VizieR mirror to use (can also be passed as argument)
#

#################################
# Set the safe locale
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Check for forced client selection
if [ -n "$GAIA_DR2_CLIENT" ]; then
 if [ "$GAIA_DR2_CLIENT" = "vizquery" ] || [ "$GAIA_DR2_CLIENT" = "esa_tap" ]; then
  echo "$GAIA_DR2_CLIENT"
  exit 0
 fi
 # If GAIA_DR2_CLIENT is set to something else (like "auto"), continue with probing
fi

# Get VIZIER_SITE from argument or environment
if [ -n "$1" ]; then
 VIZIER_SITE="$1"
fi

# Test position: a G=12.2 star (Gaia DR2 3376888109148417664) 1.9" from the position used
# by the "Single source - tight radius" case of util/examples/test_gaia_dr2_clients.sh.
# Do not use Vega here: it is too bright to be in Gaia DR2 (I/345/gaia2 has no source within
# 30" of it), so a healthy service returns no source and the probe can never succeed.
TEST_RA="06:13:37.32"
TEST_DEC="+21:54:26.0"
TEST_RADIUS_ARCSEC=5
TEST_MAG_LIMIT=14.0
PROBE_TIMEOUT=15  # seconds for each probe
# macOS has no 'timeout' unless GNU coreutils is installed (as 'gtimeout'); without this the
# VizieR probe always fails there. lib/find_timeout_command.sh falls back to lib/timeout
TIMEOUT_COMMAND=$(lib/find_timeout_command.sh)

# Temporary files for results (use process substitution where possible, but we need timing)
VIZQUERY_RESULT=""
ESA_TAP_RESULT=""

# Function to check if vizquery is available and VIZIER_SITE is set
can_use_vizquery() {
 [ -x lib/vizquery ] && [ -n "$VIZIER_SITE" ]
}

# Function to check if ESA TAP client is available
can_use_esa_tap() {
 [ -x lib/gaia_dr2_cone_search.sh ] && command -v curl &>/dev/null
}

# Function to probe VizieR
probe_vizquery() {
 if ! can_use_vizquery; then
  echo "unavailable"
  return
 fi
 local start_time end_time
 start_time=$(date +%s.%N 2>/dev/null || date +%s)
 local result
 result=$($TIMEOUT_COMMAND "$PROBE_TIMEOUT" lib/vizquery \
  -site="$VIZIER_SITE" \
  -mime=text \
  -source=I/345/gaia2 \
  -out.max=1 \
  -out.add=_r \
  -out.form=mini \
  -sort=Gmag \
  "Gmag=0.0..$TEST_MAG_LIMIT" \
  -c="$TEST_RA $TEST_DEC" \
  -c.rs=$TEST_RADIUS_ARCSEC \
  -out=Source,RA_ICRS,DE_ICRS,Gmag,RPmag,Var 2>/dev/null)
 local exit_code=$?
 end_time=$(date +%s.%N 2>/dev/null || date +%s)

 # Check if query succeeded (has #END# marker and at least one data line)
 if [ $exit_code -eq 0 ] && echo "$result" | grep -q '#END#'; then
  local data_lines
  data_lines=$(echo "$result" | grep -v '^#' | grep -v '^---' | grep -v '^$' | grep -v 'sec' | grep -v 'Gmag' | grep -v 'RA_ICRS' | wc -l)
  if [ "$data_lines" -gt 0 ]; then
   # Calculate elapsed time
   local elapsed
   elapsed=$(echo "$end_time $start_time" | awk '{printf "%.3f", $1 - $2}')
   echo "success $elapsed"
   return
  fi
 fi
 echo "failed"
}

# Function to probe ESA TAP
probe_esa_tap() {
 if ! can_use_esa_tap; then
  echo "unavailable"
  return
 fi
 local start_time end_time
 start_time=$(date +%s.%N 2>/dev/null || date +%s)
 local result
 result=$(lib/gaia_dr2_cone_search.sh \
  -c="$TEST_RA $TEST_DEC" \
  -c.rs=$TEST_RADIUS_ARCSEC \
  -out.max=1 \
  -sort=Gmag \
  "Gmag=0.0..$TEST_MAG_LIMIT" \
  -timeout=$PROBE_TIMEOUT 2>/dev/null)
 local exit_code=$?
 end_time=$(date +%s.%N 2>/dev/null || date +%s)

 # Check if query succeeded (has #END# marker and at least one data line)
 if [ $exit_code -eq 0 ] && echo "$result" | grep -q '#END#'; then
  local data_lines
  data_lines=$(echo "$result" | grep -v '^#' | grep -v '^$' | wc -l)
  if [ "$data_lines" -gt 0 ]; then
   # Calculate elapsed time
   local elapsed
   elapsed=$(echo "$end_time $start_time" | awk '{printf "%.3f", $1 - $2}')
   echo "success $elapsed"
   return
  fi
 fi
 echo "failed"
}

# Run probes in parallel
VIZQUERY_PROBE_FILE=$(mktemp)
ESA_TAP_PROBE_FILE=$(mktemp)

# Clean up temp files on exit
cleanup() {
 rm -f "$VIZQUERY_PROBE_FILE" "$ESA_TAP_PROBE_FILE"
}
trap cleanup EXIT

# Start both probes in background
probe_vizquery > "$VIZQUERY_PROBE_FILE" &
VIZQUERY_PID=$!

probe_esa_tap > "$ESA_TAP_PROBE_FILE" &
ESA_TAP_PID=$!

# Wait for both to complete
wait $VIZQUERY_PID 2>/dev/null
wait $ESA_TAP_PID 2>/dev/null

# Read results
VIZQUERY_RESULT=$(cat "$VIZQUERY_PROBE_FILE")
ESA_TAP_RESULT=$(cat "$ESA_TAP_PROBE_FILE")

# Parse results
VIZQUERY_STATUS=$(echo "$VIZQUERY_RESULT" | awk '{print $1}')
ESA_TAP_STATUS=$(echo "$ESA_TAP_RESULT" | awk '{print $1}')

# Decision logic: VizieR whenever it answers, ESA TAP only as the fallback
if [ "$VIZQUERY_STATUS" = "success" ]; then
 echo "vizquery"
elif [ "$ESA_TAP_STATUS" = "success" ]; then
 # Only ESA TAP succeeded
 echo "esa_tap"
else
 # Neither succeeded - default to vizquery (will fail gracefully later)
 # This allows the calling code to handle the failure
 echo "vizquery"
fi
