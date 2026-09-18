#!/usr/bin/env bash
# Exercise the "remember a failed catalog download" helpers of
# lib/update_offline_catalogs.sh without downloading anything.
#
# What this guards: lib/catalogs/check_catalogs_offline runs the update script,
# and it is itself run once per transient candidate. While a catalog cannot be
# obtained, every candidate used to pay for a fresh download and a fresh
# rejection - about 2 s each against 0.06 s for a no-op run. On 2026-09-14 that
# turned one test into a three-hour hang that burned the whole 300-minute
# GitHub Actions budget. The cooldown below is what stops it, so its edge cases
# (no marker, fresh marker, expired marker, unreadable timestamp, clock skew)
# are worth pinning down.
set -euo pipefail
export LC_ALL=C

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
UPDATER="$SCRIPT_DIR/../../lib/update_offline_catalogs.sh"
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vast-catalog-failure-memory.XXXXXX")
trap 'rm -rf -- "$TEST_DIR"' EXIT

# Extract only the self-contained helpers; sourcing the updater would run it.
for FUNCTION_NAME in catalog_download_failure_marker_name recent_catalog_download_failure remember_catalog_download_failure forget_catalog_download_failure ; do
 awk -v want="$FUNCTION_NAME" '
  $0 ~ ("^" want "\\(\\) \\{") { copying=1 }
  copying { print }
  copying && /^\}/ { found=1; exit }
  END { if (!found) exit 1 }
 ' "$UPDATER" >> "$TEST_DIR/functions.sh" || { echo "FAIL: cannot extract $FUNCTION_NAME from $UPDATER" >&2; exit 1; }
done
# shellcheck source=/dev/null
source "$TEST_DIR/functions.sh"

cd -- "$TEST_DIR"
CATALOG=fake_catalog.csv
MARKER="$CATALOG.download_failed"
N_CASES=0

fail() { echo "FAIL: $CASE_NAME: $*" >&2 ; exit 1 ; }
pass() { N_CASES=$((N_CASES + 1)) ; echo "PASS: $CASE_NAME" ; }

# The marker name must be derived from the catalog, so each catalog is
# remembered independently.
CASE_NAME=marker_name_follows_the_catalog
[ "$(catalog_download_failure_marker_name lib/catalogs/asassnv.csv)" = "lib/catalogs/asassnv.csv.download_failed" ] \
 || fail "unexpected marker name $(catalog_download_failure_marker_name lib/catalogs/asassnv.csv)"
pass

# No marker: the download must be attempted.
CASE_NAME=no_marker_means_try
rm -f "$MARKER"
CATALOG_DOWNLOAD_FAILURE_COOLDOWN_SEC=3600
if recent_catalog_download_failure "$CATALOG" ; then fail 'a download was suppressed with no marker present' ; fi
pass

# A marker just written: the download must be skipped.
CASE_NAME=fresh_marker_suppresses
remember_catalog_download_failure "$CATALOG"
[ -f "$MARKER" ] || fail 'the marker was not created'
if ! recent_catalog_download_failure "$CATALOG" ; then fail 'a just-recorded failure did not suppress the retry' ; fi
pass

# An old marker: the cooldown has expired and the download is attempted again,
# so a mirror that gets repaired is picked up without anyone intervening.
CASE_NAME=expired_marker_allows_retry
CATALOG_DOWNLOAD_FAILURE_COOLDOWN_SEC=1
sleep 2
if recent_catalog_download_failure "$CATALOG" ; then fail 'an expired marker still suppressed the retry' ; fi
pass

# Clearing on success: the next run must not be held back by a stale marker.
CASE_NAME=forget_clears_the_marker
CATALOG_DOWNLOAD_FAILURE_COOLDOWN_SEC=3600
remember_catalog_download_failure "$CATALOG"
forget_catalog_download_failure "$CATALOG"
[ -f "$MARKER" ] && fail 'the marker survived being cleared'
if recent_catalog_download_failure "$CATALOG" ; then fail 'a cleared failure still suppressed the retry' ; fi
pass

# Two catalogs are remembered independently.
CASE_NAME=markers_are_per_catalog
OTHER=other_catalog.dat
remember_catalog_download_failure "$CATALOG"
if recent_catalog_download_failure "$OTHER" ; then fail "one catalog's failure suppressed another catalog" ; fi
if ! recent_catalog_download_failure "$CATALOG" ; then fail 'the recorded catalog was not suppressed' ; fi
forget_catalog_download_failure "$CATALOG"
pass

# A marker whose timestamp cannot be read must be treated as fresh: falling back
# to "try again" would restore the retry storm this exists to prevent.
CASE_NAME=unreadable_timestamp_is_treated_as_fresh
remember_catalog_download_failure "$CATALOG"
stat() { return 1 ; }   # both the GNU and the BSD form fail
if ! recent_catalog_download_failure "$CATALOG" ; then
 unset -f stat
 fail 'an unreadable marker timestamp let the retry through'
fi
unset -f stat
forget_catalog_download_failure "$CATALOG"
pass

# A marker dated in the future (clock skew, a restored backup) must not lock the
# catalog out for however long the skew lasts.
CASE_NAME=future_marker_does_not_lock_us_out
remember_catalog_download_failure "$CATALOG"
if touch -d '+1 hour' "$MARKER" 2>/dev/null || touch -A 010000 "$MARKER" 2>/dev/null ; then
 if recent_catalog_download_failure "$CATALOG" ; then fail 'a marker dated in the future suppressed the retry forever' ; fi
 pass
else
 echo "SKIP: $CASE_NAME (this touch cannot set a future timestamp)"
fi
forget_catalog_download_failure "$CATALOG"

echo "All $N_CASES catalog-download-failure-memory tests passed."
