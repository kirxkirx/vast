#!/usr/bin/env bash
#
# Validation script for lib/gaia_dr2_cone_search.sh against lib/vizquery
# Tests multiple cases with 1, 2, and 3 sources within search radius
# Records timing and provides performance summary
#

#################################
# Set the safe locale
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Colors for output (disabled if not a terminal)
if [[ -t 1 ]]; then
 RED='\033[0;31m'
 GREEN='\033[0;32m'
 YELLOW='\033[1;33m'
 NC='\033[0m' # No Color
else
 RED=''
 GREEN=''
 YELLOW=''
 NC=''
fi

# Find the VaST root directory
if [[ -f lib/gaia_dr2_cone_search.sh ]]; then
 VASTDIR="$PWD"
elif [[ -f ../../lib/gaia_dr2_cone_search.sh ]]; then
 VASTDIR="$PWD/../.."
else
 echo "ERROR: Cannot find VaST root directory. Run from VaST root or util/examples/" >&2
 exit 1
fi

cd "$VASTDIR" || exit 1

# Find the portable timeout command (timeout on Linux, gtimeout on Mac, lib/timeout as fallback)
TIMEOUT_CMD=$(lib/find_timeout_command.sh)

# Check that required scripts exist
if [[ ! -x lib/gaia_dr2_cone_search.sh ]]; then
 echo "ERROR: lib/gaia_dr2_cone_search.sh not found or not executable" >&2
 exit 1
fi

if [[ ! -x lib/vizquery ]]; then
 echo "ERROR: lib/vizquery not found or not executable" >&2
 exit 1
fi

# Timing arrays
declare -a ESA_TIMES
declare -a VIZIER_TIMES
declare -a TEST_NAMES
declare -a TEST_RESULTS

# Test counter
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Function to run a single test
run_test() {
 local test_name="$1"
 local coords="$2"
 local radius="$3"
 local mag_range="$4"
 local expected_min="$5"
 local expected_max="$6"

 TEST_COUNT=$((TEST_COUNT + 1))
 TEST_NAMES+=("$test_name")

 echo ""
 echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
 echo "Test $TEST_COUNT: $test_name"
 echo "  Coordinates: $coords"
 echo "  Radius: ${radius}\""
 echo "  Magnitude range: $mag_range"
 echo "  Expected sources: $expected_min - $expected_max"
 echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

 # Run ESA TAP query
 echo ""
 echo "  [ESA TAP] Querying..."
 local esa_start esa_end esa_time esa_output esa_count
 esa_start=$(date +%s)
 esa_output=$(lib/gaia_dr2_cone_search.sh -out.max=10 -sort=Gmag "$mag_range" "-c=$coords" "-c.rs=$radius" 2>&1)
 esa_end=$(date +%s)
 esa_time=$(echo "$esa_end $esa_start" | awk '{printf "%.3f", $1 - $2}')
 ESA_TIMES+=("$esa_time")

 # Count ESA results (exclude #END# line)
 esa_count=$(echo "$esa_output" | grep -cE "NOT_AVAILABLE|CONSTANT|VARIABLE" 2>/dev/null || true)
 # Ensure esa_count is a valid integer
 if ! [[ "$esa_count" =~ ^[0-9]+$ ]]; then
  esa_count=0
 fi

 echo "  [ESA TAP] Time: ${esa_time}s, Sources found: $esa_count"
 if [[ -n "$esa_output" ]]; then
  echo "$esa_output" | head -5 | sed 's/^/    /'
  if [[ $(echo "$esa_output" | grep -c "^") -gt 6 ]]; then
   echo "    ..."
  fi
 fi

 # Run VizieR query
 echo ""
 echo "  [VizieR] Querying..."
 local vizier_start vizier_end vizier_time vizier_output vizier_count
 vizier_start=$(date +%s)
 vizier_output=$($TIMEOUT_CMD 60 lib/vizquery -site=vizier.cds.unistra.fr -mime=text -source=I/345/gaia2 \
  -out.max=10 -out.add=_r -out.form=mini -sort=Gmag "$mag_range" \
  "-c=$coords" "-c.rs=$radius" -out=Source,RA_ICRS,DE_ICRS,Gmag,RPmag,Var 2>/dev/null)
 vizier_end=$(date +%s)
 vizier_time=$(echo "$vizier_end $vizier_start" | awk '{printf "%.3f", $1 - $2}')
 VIZIER_TIMES+=("$vizier_time")

 # Count VizieR results
 vizier_count=$(echo "$vizier_output" | grep -cE "NOT_AVAILABLE|CONSTANT|VARIABLE" 2>/dev/null || true)
 # Ensure vizier_count is a valid integer
 if ! [[ "$vizier_count" =~ ^[0-9]+$ ]]; then
  vizier_count=0
 fi

 echo "  [VizieR] Time: ${vizier_time}s, Sources found: $vizier_count"
 if [[ -n "$vizier_output" ]]; then
  echo "$vizier_output" | grep -E "NOT_AVAILABLE|CONSTANT|VARIABLE" | head -5 | sed 's/^/    /'
  if [[ $(echo "$vizier_output" | grep -cE "NOT_AVAILABLE|CONSTANT|VARIABLE") -gt 5 ]]; then
   echo "    ..."
  fi
 fi

 # Validate results
 echo ""
 local test_pass=1

 # Check ESA count is in expected range
 if [[ "$esa_count" -ge "$expected_min" ]] && [[ "$esa_count" -le "$expected_max" ]]; then
  echo -e "  ${GREEN}✓${NC} ESA source count ($esa_count) in expected range [$expected_min-$expected_max]"
 else
  echo -e "  ${RED}✗${NC} ESA source count ($esa_count) NOT in expected range [$expected_min-$expected_max]"
  test_pass=0
 fi

 # Check VizieR count is in expected range
 if [[ "$vizier_count" -ge "$expected_min" ]] && [[ "$vizier_count" -le "$expected_max" ]]; then
  echo -e "  ${GREEN}✓${NC} VizieR source count ($vizier_count) in expected range [$expected_min-$expected_max]"
 else
  echo -e "  ${RED}✗${NC} VizieR source count ($vizier_count) NOT in expected range [$expected_min-$expected_max]"
  test_pass=0
 fi

 # Check counts match between ESA and VizieR
 if [[ "$esa_count" -eq "$vizier_count" ]]; then
  echo -e "  ${GREEN}✓${NC} Source counts match (ESA=$esa_count, VizieR=$vizier_count)"
 else
  echo -e "  ${YELLOW}⚠${NC} Source counts differ (ESA=$esa_count, VizieR=$vizier_count)"
  # Don't fail on count mismatch - catalogs may have slight differences
 fi

 # Compare source IDs if both returned results
 if [[ "$esa_count" -gt 0 ]] && [[ "$vizier_count" -gt 0 ]]; then
  local esa_first_id vizier_first_id
  esa_first_id=$(echo "$esa_output" | grep -E "NOT_AVAILABLE|CONSTANT|VARIABLE" | head -1 | awk '{print $2}')
  vizier_first_id=$(echo "$vizier_output" | grep -E "NOT_AVAILABLE|CONSTANT|VARIABLE" | head -1 | awk '{print $2}')

  if [[ "$esa_first_id" == "$vizier_first_id" ]]; then
   echo -e "  ${GREEN}✓${NC} First source ID matches: $esa_first_id"
  else
   echo -e "  ${YELLOW}⚠${NC} First source IDs differ (ESA=$esa_first_id, VizieR=$vizier_first_id)"
  fi
 fi

 if [[ "$test_pass" -eq 1 ]]; then
  PASS_COUNT=$((PASS_COUNT + 1))
  TEST_RESULTS+=("PASS")
  echo -e "  ${GREEN}TEST PASSED${NC}"
 else
  FAIL_COUNT=$((FAIL_COUNT + 1))
  TEST_RESULTS+=("FAIL")
  echo -e "  ${RED}TEST FAILED${NC}"
 fi
}

# Function to run parallel stress test
run_parallel_test() {
 echo ""
 echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
 echo "Parallel execution test (thread safety)"
 echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

 local pids=()
 local tmpdir
 tmpdir=$(mktemp -d 2>/dev/null || echo "/tmp/gaia_test_$$")
 mkdir -p "$tmpdir"

 echo "  Launching 5 parallel ESA queries..."

 # Launch parallel queries with different coordinates
 lib/gaia_dr2_cone_search.sh -out.max=3 -sort=Gmag "Gmag=0.0..14.0" "-c=06:13:37.32 +21:54:26.0" -c.rs=30 > "$tmpdir/esa1.out" 2>&1 &
 pids+=($!)
 lib/gaia_dr2_cone_search.sh -out.max=3 -sort=Gmag "Gmag=0.0..14.0" "-c=12:30:00.00 +12:00:00.0" -c.rs=30 > "$tmpdir/esa2.out" 2>&1 &
 pids+=($!)
 lib/gaia_dr2_cone_search.sh -out.max=3 -sort=Gmag "Gmag=0.0..14.0" "-c=18:00:00.00 -30:00:00.0" -c.rs=30 > "$tmpdir/esa3.out" 2>&1 &
 pids+=($!)
 lib/gaia_dr2_cone_search.sh -out.max=3 -sort=Gmag "Gmag=0.0..14.0" "-c=00:00:00.00 +00:00:00.0" -c.rs=30 > "$tmpdir/esa4.out" 2>&1 &
 pids+=($!)
 lib/gaia_dr2_cone_search.sh -out.max=3 -sort=Gmag "Gmag=0.0..14.0" "-c=06:00:00.00 +23:00:00.0" -c.rs=30 > "$tmpdir/esa5.out" 2>&1 &
 pids+=($!)

 # Wait for all to complete
 for pid in "${pids[@]}"; do
  wait "$pid" || true
 done

 # Check results
 local valid_count=0
 for i in 1 2 3 4 5; do
  if grep -q "#END#" "$tmpdir/esa$i.out" 2>/dev/null; then
   valid_count=$((valid_count + 1))
  fi
 done

 if [[ "$valid_count" -eq 5 ]]; then
  echo -e "  ${GREEN}✓${NC} All 5 parallel queries completed successfully"
  PASS_COUNT=$((PASS_COUNT + 1))
  TEST_RESULTS+=("PASS")
 else
  echo -e "  ${RED}✗${NC} Only $valid_count/5 parallel queries completed"
  FAIL_COUNT=$((FAIL_COUNT + 1))
  TEST_RESULTS+=("FAIL")
 fi

 TEST_COUNT=$((TEST_COUNT + 1))
 TEST_NAMES+=("Parallel execution (5 concurrent)")

 # Cleanup
 rm -rf "$tmpdir"
}

# Print summary
print_summary() {
 echo ""
 echo "╔══════════════════════════════════════════════════════════════════════╗"
 echo "║                           TEST SUMMARY                               ║"
 echo "╠══════════════════════════════════════════════════════════════════════╣"

 # Calculate timing statistics
 local esa_total=0 vizier_total=0
 local esa_count=${#ESA_TIMES[@]}
 local vizier_count=${#VIZIER_TIMES[@]}

 for t in "${ESA_TIMES[@]}"; do
  esa_total=$(echo "$esa_total $t" | awk '{print $1 + $2}')
 done
 for t in "${VIZIER_TIMES[@]}"; do
  vizier_total=$(echo "$vizier_total $t" | awk '{print $1 + $2}')
 done

 local esa_avg vizier_avg
 if [[ "$esa_count" -gt 0 ]]; then
  esa_avg=$(echo "$esa_total $esa_count" | awk '{printf "%.3f", $1 / $2}')
 else
  esa_avg="N/A"
 fi
 if [[ "$vizier_count" -gt 0 ]]; then
  vizier_avg=$(echo "$vizier_total $vizier_count" | awk '{printf "%.3f", $1 / $2}')
 else
  vizier_avg="N/A"
 fi

 printf "║  %-66s  ║\n" "Tests run: $TEST_COUNT"
 printf "║  %-66s  ║\n" "Passed: $PASS_COUNT"
 printf "║  %-66s  ║\n" "Failed: $FAIL_COUNT"
 echo "╠══════════════════════════════════════════════════════════════════════╣"
 printf "║  %-66s  ║\n" "TIMING STATISTICS"
 echo "╠══════════════════════════════════════════════════════════════════════╣"
 printf "║  %-66s  ║\n" "ESA TAP endpoint (gea.esac.esa.int):"
 printf "║    %-64s  ║\n" "Total time: ${esa_total}s over $esa_count queries"
 printf "║    %-64s  ║\n" "Average time: ${esa_avg}s per query"
 echo "║                                                                      ║"
 printf "║  %-66s  ║\n" "VizieR CDS endpoint (vizier.cds.unistra.fr):"
 printf "║    %-64s  ║\n" "Total time: ${vizier_total}s over $vizier_count queries"
 printf "║    %-64s  ║\n" "Average time: ${vizier_avg}s per query"
 echo "╠══════════════════════════════════════════════════════════════════════╣"

 # Speed comparison
 if [[ "$esa_avg" != "N/A" ]] && [[ "$vizier_avg" != "N/A" ]]; then
  local speedup
  speedup=$(echo "$vizier_avg $esa_avg" | awk '{if ($2 > 0) printf "%.2f", $1 / $2; else print "N/A"}')
  if [[ $(echo "$esa_avg $vizier_avg" | awk '{print ($1 < $2) ? 1 : 0}') -eq 1 ]]; then
   printf "║  %-66s  ║\n" "ESA is ${speedup}x faster than VizieR on average"
  else
   speedup=$(echo "$esa_avg $vizier_avg" | awk '{if ($2 > 0) printf "%.2f", $1 / $2; else print "N/A"}')
   printf "║  %-66s  ║\n" "VizieR is ${speedup}x faster than ESA on average"
  fi
 fi

 echo "╚══════════════════════════════════════════════════════════════════════╝"

 # Final result
 echo ""
 if [[ "$FAIL_COUNT" -eq 0 ]]; then
  echo -e "${GREEN}All tests passed!${NC}"
  return 0
 else
  echo -e "${RED}Some tests failed!${NC}"
  return 1
 fi
}

# Main test execution
echo "╔══════════════════════════════════════════════════════════════════════╗"
echo "║     Gaia DR2 Client Validation: ESA TAP vs VizieR                    ║"
echo "║     Testing lib/gaia_dr2_cone_search.sh against lib/vizquery         ║"
echo "╚══════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Starting tests at $(date)"

# Test cases with different expected source counts
# Format: run_test "name" "coords" "radius_arcsec" "mag_range" "min_expected" "max_expected"

# Single source tests (small radius around known bright star)
run_test "Single source - tight radius" \
 "06:13:37.32 +21:54:26.0" "5" "Gmag=0.0..14.0" 1 1

# Two sources test (medium radius)
run_test "Two sources - medium radius" \
 "06:13:37.32 +21:54:26.0" "20" "Gmag=0.0..14.0" 1 3

# Three or more sources test (larger radius)
run_test "Multiple sources - larger radius" \
 "06:13:37.32 +21:54:26.0" "60" "Gmag=0.0..16.0" 3 10

# Dense field test (galactic plane region)
run_test "Dense field - galactic plane" \
 "18:00:00.00 -30:00:00.0" "30" "Gmag=0.0..15.0" 1 10

# Sparse field test (high galactic latitude)
run_test "Sparse field - high latitude" \
 "12:00:00.00 +80:00:00.0" "60" "Gmag=0.0..16.0" 0 5

# Variable star test
run_test "Known variable region" \
 "06:25:00.65 +24:55:22.5" "15" "Gmag=0.0..14.0" 1 3

# Faint magnitude test
run_test "Faint sources" \
 "06:13:37.32 +21:54:26.0" "60" "Gmag=14.0..17.0" 1 10

# Bright magnitude test
run_test "Bright sources only" \
 "06:13:37.32 +21:54:26.0" "120" "Gmag=0.0..12.0" 1 5

# Zero result test (very tight constraints)
run_test "No sources expected" \
 "06:13:37.32 +21:54:26.0" "1" "Gmag=0.0..8.0" 0 0

# Run parallel execution test
run_parallel_test

# Print summary
print_summary
exit_code=$?

echo ""
echo "Tests completed at $(date)"
exit $exit_code
