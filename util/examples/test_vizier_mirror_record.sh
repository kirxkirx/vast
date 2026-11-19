#!/usr/bin/env bash
#
# Unit test of the shared record of lib/choose_vizier_mirror.sh probe results: reuse of a
# recent success or failure, expiry (also with VIZIER_MIRROR_RECORD_FAIL_SEC from the
# environment), records that are not trusted, VIZIER_MIRROR_RECORD=no, a separate record
# per catalog, and VIZIER_MIRROR_RECORD_ONLY=yes, which must never probe; also that the UCAC5
# test asks for all columns (vizier.idia.ac.za fails most UCAC5 queries that name some). A
# stand-in lib/vizquery fails at once and logs its calls, so no network is needed and the test
# runs everywhere, GitHub Actions included. Run it from the VaST directory; it prints the
# failed check codes and exits with code 1 if any check fails.
#
# Usage: util/examples/test_vizier_mirror_record.sh

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

FAILED_CODES=""
fail() {
 FAILED_CODES="$FAILED_CODES $1"
 echo "FAILED: $1 $2"
}

if [ ! -s lib/choose_vizier_mirror.sh ];then
 echo "FAILED: VIZIERRECORD_NO_SCRIPT lib/choose_vizier_mirror.sh is not found (run this test from the VaST directory)"
 exit 1
fi

WORK_DIR=$(mktemp -d 2>/dev/null || echo "vizier_mirror_record_test_$$")
mkdir -p "$WORK_DIR/lib/catalogs" || exit 1
cp lib/choose_vizier_mirror.sh "$WORK_DIR/lib/" || exit 1
# The stand-in for lib/vizquery: no mirror answers, every call is logged with its arguments
cat > "$WORK_DIR/lib/vizquery" << 'VIZQUERY_STANDIN'
#!/usr/bin/env bash
echo "call $*" >> "$(dirname "$0")/vizquery_calls.txt"
exit 1
VIZQUERY_STANDIN
chmod +x "$WORK_DIR/lib/vizquery"
RECORD="$WORK_DIR/lib/catalogs/.vizier_mirror_probe_GAIADR2"
RECORD_APASS="$WORK_DIR/lib/catalogs/.vizier_mirror_probe_APASS"
RECORD_UCAC5="$WORK_DIR/lib/catalogs/.vizier_mirror_probe_UCAC5"

# Run lib/choose_vizier_mirror.sh with the given environment settings (and "APASS" or "UCAC5"
# as the argument if the last setting is one of them); print "<output> <exit code> <vizquery calls>"
probe() {
 local ARGUMENT=""
 local SETTINGS=( "$@" )
 if [ "${#SETTINGS[@]}" -gt 0 ];then
  case "${SETTINGS[${#SETTINGS[@]}-1]}" in
   APASS|UCAC5)
    ARGUMENT="${SETTINGS[${#SETTINGS[@]}-1]}"
    unset 'SETTINGS[${#SETTINGS[@]}-1]'
    ;;
  esac
 fi
 rm -f "$WORK_DIR/lib/vizquery_calls.txt"
 OUTPUT=$(env -u VIZIER_MIRROR_RECORD -u VIZIER_MIRROR_RECORD_ONLY -u VIZIER_MIRROR_RECORD_OK_SEC -u VIZIER_MIRROR_RECORD_FAIL_SEC VAST_PATH="$WORK_DIR/" "${SETTINGS[@]}" "$WORK_DIR/lib/choose_vizier_mirror.sh" ${ARGUMENT:+"$ARGUMENT"} 2>/dev/null)
 EXIT_CODE=$?
 CALLS=0
 if [ -f "$WORK_DIR/lib/vizquery_calls.txt" ];then
  CALLS=$(wc -l < "$WORK_DIR/lib/vizquery_calls.txt" | awk '{print $1}')
 fi
 echo "$OUTPUT $EXIT_CODE $CALLS"
}
check() {
 local CODE="$1"
 local EXPECTED="$2"
 local GOT="$3"
 if [ "$GOT" != "$EXPECTED" ];then
  fail "$CODE" "expected #$EXPECTED# got #$GOT#"
 fi
}
NOW=$(date +%s)

# No record: record-only does not probe; a normal call probes the four mirrors and records the failure
check VIZIERRECORD_ONLY_NO_RECORD "vizier.cds.unistra.fr 2 0" "$(probe VIZIER_MIRROR_RECORD_ONLY=yes)"
check VIZIERRECORD_PROBE_FAIL "vizier.cds.unistra.fr 1 4" "$(probe)"
if [ ! -s "$RECORD" ] || ! awk -v now="$NOW" '{exit !(NF == 3 && $1 >= now && $2 == 1 && $3 == "vizier.cds.unistra.fr")}' "$RECORD" ;then
 fail VIZIERRECORD_FAIL_RECORDED "record #$(cat "$RECORD" 2>/dev/null)#"
fi
# A recent failure is reused, also by record-only
check VIZIERRECORD_REUSE_FAIL "vizier.cds.unistra.fr 1 0" "$(probe)"
check VIZIERRECORD_ONLY_FRESH_FAIL "vizier.cds.unistra.fr 1 0" "$(probe VIZIER_MIRROR_RECORD_ONLY=yes)"
# The record is per catalog: no APASS record yet
check VIZIERRECORD_ONLY_OTHER_CATALOG "vizier.cds.unistra.fr 2 0" "$(probe VIZIER_MIRROR_RECORD_ONLY=yes APASS)"
if [ -e "$RECORD_APASS" ];then
 fail VIZIERRECORD_OTHER_CATALOG_WRITTEN "record-only wrote $RECORD_APASS"
fi
# A recent success is reused with its mirror
echo "$NOW 0 vizier.nao.ac.jp" > "$RECORD"
check VIZIERRECORD_REUSE_OK "vizier.nao.ac.jp 0 0" "$(probe)"
check VIZIERRECORD_ONLY_FRESH_OK "vizier.nao.ac.jp 0 0" "$(probe VIZIER_MIRROR_RECORD_ONLY=yes)"
# A failure older than VIZIER_MIRROR_RECORD_FAIL_SEC (300 s by default) is not reused
echo "$((NOW - 400)) 1 vizier.cds.unistra.fr" > "$RECORD"
check VIZIERRECORD_ONLY_FAIL_EXPIRED "vizier.cds.unistra.fr 2 0" "$(probe VIZIER_MIRROR_RECORD_ONLY=yes)"
check VIZIERRECORD_ONLY_FAIL_SEC_ENV "vizier.cds.unistra.fr 1 0" "$(probe VIZIER_MIRROR_RECORD_FAIL_SEC=1800 VIZIER_MIRROR_RECORD_ONLY=yes)"
check VIZIERRECORD_FAIL_EXPIRED_PROBES "vizier.cds.unistra.fr 1 4" "$(probe)"
# A success older than VIZIER_MIRROR_RECORD_OK_SEC (900 s by default) is not reused
echo "$((NOW - 1000)) 0 vizier.nao.ac.jp" > "$RECORD"
check VIZIERRECORD_ONLY_OK_EXPIRED "vizier.cds.unistra.fr 2 0" "$(probe VIZIER_MIRROR_RECORD_ONLY=yes)"
# Records from the future or unreadable ones are not trusted
echo "$((NOW + 100)) 1 vizier.cds.unistra.fr" > "$RECORD"
check VIZIERRECORD_ONLY_FUTURE "vizier.cds.unistra.fr 2 0" "$(probe VIZIER_MIRROR_RECORD_ONLY=yes)"
echo "garbage" > "$RECORD"
check VIZIERRECORD_ONLY_GARBAGE "vizier.cds.unistra.fr 2 0" "$(probe VIZIER_MIRROR_RECORD_ONLY=yes)"
# VIZIER_MIRROR_RECORD=no ignores the record: probes, or with record-only reports nothing
echo "$NOW 0 vizier.nao.ac.jp" > "$RECORD"
check VIZIERRECORD_BYPASS_PROBES "vizier.cds.unistra.fr 1 4" "$(probe VIZIER_MIRROR_RECORD=no)"
echo "$NOW 0 vizier.nao.ac.jp" > "$RECORD"
check VIZIERRECORD_BYPASS_ONLY "vizier.cds.unistra.fr 2 0" "$(probe VIZIER_MIRROR_RECORD=no VIZIER_MIRROR_RECORD_ONLY=yes)"
# The UCAC5 test of the plate solver probes the four mirrors, keeps its own record and asks
# for all columns: no '-out=' list, as vizier.idia.ac.za fails most of those for UCAC5
check VIZIERRECORD_UCAC5_PROBE_FAIL "vizier.cds.unistra.fr 1 4" "$(probe UCAC5)"
if [ ! -s "$RECORD_UCAC5" ] || ! awk -v now="$NOW" '{exit !(NF == 3 && $1 >= now && $2 == 1 && $3 == "vizier.cds.unistra.fr")}' "$RECORD_UCAC5" ;then
 fail VIZIERRECORD_UCAC5_FAIL_RECORDED "record #$(cat "$RECORD_UCAC5" 2>/dev/null)#"
fi
if [ "$(grep -c -e '-source=UCAC5' "$WORK_DIR/lib/vizquery_calls.txt" 2>/dev/null)" != "4" ] || grep -q -e '-out=' "$WORK_DIR/lib/vizquery_calls.txt" ;then
 fail VIZIERRECORD_UCAC5_QUERY "#$(head -n 1 "$WORK_DIR/lib/vizquery_calls.txt" 2>/dev/null)#"
fi
check VIZIERRECORD_UCAC5_REUSE_FAIL "vizier.cds.unistra.fr 1 0" "$(probe UCAC5)"

rm -rf "$WORK_DIR"
if [ -n "$FAILED_CODES" ];then
 echo "Failed checks:$FAILED_CODES"
 exit 1
fi
echo "All VizieR mirror probe record checks passed"
exit 0
