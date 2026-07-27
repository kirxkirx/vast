#!/usr/bin/env bash
#
# Batch plate-solution quality audit (and conservative repair) for an archive
# of already-solved FITS images, built around the UCAC5-based TAN-SIP refit
# in util/solve_plate_with_UCAC5.
#
# For every image the audit runs
#   VAST_FORCE_SIP_REFIT=1 util/solve_plate_with_UCAC5 --no_photometric_catalog <copy>
# in a per-worker VaST directory, which
#   * measures the astrometric quality of the EXISTING solution
#     (WCS_QUALITY_DIAG line: overall and per-quadrant MAD sigmas, N_match),
#   * refits the TAN-SIP solution from the UCAC5 matches and REPLACES it only
#     when the refit beats the incumbent by >10% (the keep-if-better guard in
#     refit_sip_from_catalog_matches), so good solutions are never touched.
# The archive itself is treated as READ-ONLY: each image is copied to worker
# scratch space first, and when the refit improves a solution the improved
# file is stored under <output_dir>/repaired/ carrying the original file
# name. Copying repaired files back into the archive is a manual decision.
#
# The run is resumable: images already present in the results ledger are
# skipped, so the script can be interrupted and restarted at any time.
#
# Usage:
#   util/batch_sip_refit_audit.sh <image_list_file> <output_dir> [N_workers] [max_load]
#
#   image_list_file : text file with one absolute image path per line
#                     (e.g. made with: find /mnt/nmwttu1/NMW-TexasTech_archive -name '*.fits' | sort > list.txt)
#   output_dir      : where the ledger, logs, worker dirs and repaired/ go
#                     (needs ~15 GB for the worker VaST copies plus room for
#                     repaired images, ~123 MB each)
#   N_workers       : parallel workers, each in its own VaST copy (default 8)
#   max_load        : workers pause while the 1-min load average exceeds
#                     this value (default 20) so the nightly transient
#                     processing keeps priority
#
# Output files in <output_dir>:
#   audit_results.txt : one line per image:
#                       <basename> | <SIP_REFIT summary line> | <WCS_QUALITY_DIAG line>
#   repaired/         : images whose solution the refit improved (>10%)
#   failed_list.txt   : images where the solver exited nonzero
#   worker_NN/        : per-worker VaST copies (reusable across restarts)
#
# The default.sex used is default.sex.telephoto_lens_vSTL, appropriate for
# the NMW-TexasTech 135 mm f/2.2 + QHY600M frames. Change WORKER_DEFAULT_SEX
# below for other cameras.

LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL

WORKER_DEFAULT_SEX="default.sex.telephoto_lens_vSTL"

if [ -z "$2" ];then
 echo "Usage: $0 <image_list_file> <output_dir> [N_workers] [max_load]"
 exit 1
fi

IMAGE_LIST=$(readlink -f "$1")
OUTPUT_DIR=$(readlink -f "$2")
N_WORKERS="${3:-8}"
MAX_LOAD="${4:-20}"

if [ ! -s "$IMAGE_LIST" ];then
 echo "ERROR: image list $IMAGE_LIST not found or empty"
 exit 1
fi

# The VaST copy this script lives in is the master for the worker clones
VAST_MASTER_DIR=$(dirname "$(readlink -f "$0")")/..
VAST_MASTER_DIR=$(readlink -f "$VAST_MASTER_DIR")
if [ ! -x "$VAST_MASTER_DIR"/util/solve_plate_with_UCAC5 ];then
 echo "ERROR: $VAST_MASTER_DIR does not look like a compiled VaST copy"
 exit 1
fi

mkdir -p "$OUTPUT_DIR"/repaired || exit 1
LEDGER="$OUTPUT_DIR"/audit_results.txt
FAILED_LIST="$OUTPUT_DIR"/failed_list.txt
LOCKFILE="$OUTPUT_DIR"/.queue.lock
QUEUE_POS_FILE="$OUTPUT_DIR"/.queue_position
touch "$LEDGER" "$FAILED_LIST"

# ---------------------------------------------------------------------------
# One-time worker setup: local git clone of the master copy, full build,
# shared (symlinked) star catalogs, camera-appropriate default.sex.
# Reused on restart if the solver binary is already there.
# ---------------------------------------------------------------------------
setup_worker() {
 WORKER_DIR="$OUTPUT_DIR"/worker_"$1"
 if [ -x "$WORKER_DIR"/util/solve_plate_with_UCAC5 ];then
  return 0
 fi
 echo "Setting up $WORKER_DIR (clone + build, takes a few minutes)"
 git clone -q "$VAST_MASTER_DIR" "$WORKER_DIR" || return 1
 cd "$WORKER_DIR" || return 1
 make > build.log 2>&1
 if [ ! -x util/solve_plate_with_UCAC5 ];then
  echo "ERROR: build failed in $WORKER_DIR (see build.log)"
  return 1
 fi
 # share the big read-only catalogs instead of copying them
 for CATALOG_DIR_TO_SHARE in ucac5 tycho2 ;do
  if [ -d "$VAST_MASTER_DIR"/lib/catalogs/"$CATALOG_DIR_TO_SHARE" ] && [ ! -e lib/catalogs/"$CATALOG_DIR_TO_SHARE" ];then
   ln -s "$VAST_MASTER_DIR"/lib/catalogs/"$CATALOG_DIR_TO_SHARE" lib/catalogs/"$CATALOG_DIR_TO_SHARE"
  fi
 done
 if [ -f "$WORKER_DEFAULT_SEX" ];then
  cp "$WORKER_DEFAULT_SEX" default.sex
 fi
 return 0
}

# ---------------------------------------------------------------------------
# Atomically fetch the next not-yet-audited image path from the list
# ---------------------------------------------------------------------------
next_image() {
 (
  flock 9
  CURRENT_POS=$(cat "$QUEUE_POS_FILE" 2>/dev/null)
  if [ -z "$CURRENT_POS" ];then
   CURRENT_POS=0
  fi
  TOTAL_LINES=$(wc -l < "$IMAGE_LIST")
  while [ "$CURRENT_POS" -lt "$TOTAL_LINES" ];do
   CURRENT_POS=$(( CURRENT_POS + 1 ))
   CANDIDATE=$(sed -n "${CURRENT_POS}p" "$IMAGE_LIST")
   CANDIDATE_BASE=$(basename "$CANDIDATE")
   # resumability: skip images already in the ledger or failed list
   if grep -q -m 1 "^$CANDIDATE_BASE " "$LEDGER" || grep -q -m 1 -x "$CANDIDATE_BASE" "$FAILED_LIST" ;then
    continue
   fi
   echo "$CURRENT_POS" > "$QUEUE_POS_FILE"
   echo "$CANDIDATE"
   exit 0
  done
  echo "$CURRENT_POS" > "$QUEUE_POS_FILE"
  exit 1
 ) 9>"$LOCKFILE"
}

# ---------------------------------------------------------------------------
# Worker loop
# ---------------------------------------------------------------------------
run_worker() {
 WORKER_DIR="$OUTPUT_DIR"/worker_"$1"
 cd "$WORKER_DIR" || return 1
 while true ;do
  # yield to the nightly transient processing when the box is busy
  while true ;do
   LOAD_1MIN=$(awk '{printf "%d", $1}' /proc/loadavg)
   if [ "$LOAD_1MIN" -le "$MAX_LOAD" ];then
    break
   fi
   sleep 120
  done
  IMAGE_PATH=$(next_image)
  if [ $? -ne 0 ] || [ -z "$IMAGE_PATH" ];then
   break # queue exhausted
  fi
  IMAGE_BASE=$(basename "$IMAGE_PATH")
  rm -f wcs_*.fits wcs_*.fits.wcscat* audit_image.log
  cp "$IMAGE_PATH" "$IMAGE_BASE" || { echo "$IMAGE_BASE" >> "$FAILED_LIST" ; continue ; }
  VAST_FORCE_SIP_REFIT=1 util/solve_plate_with_UCAC5 --no_photometric_catalog "$IMAGE_BASE" > audit_image.log 2>&1
  SOLVER_EXIT=$?
  SIP_REFIT_SUMMARY=$(grep -E '^SIP_REFIT: (order=|refit does not|applied|only [0-9]+ catalog matches)' audit_image.log | tail -n 2 | tr '\n' ';')
  DIAG_LINE=$(grep '^WCS_QUALITY_DIAG:' audit_image.log | tail -n 1)
  if [ $SOLVER_EXIT -ne 0 ] || [ -z "$DIAG_LINE" ];then
   (
    flock 8
    echo "$IMAGE_BASE" >> "$FAILED_LIST"
   ) 8>"$LOCKFILE".ledger
   cp audit_image.log "$OUTPUT_DIR"/failed_"$IMAGE_BASE".log 2>/dev/null
  else
   (
    flock 8
    echo "$IMAGE_BASE | $SIP_REFIT_SUMMARY | $DIAG_LINE" >> "$LEDGER"
   ) 8>"$LOCKFILE".ledger
   # a successful refit rewrites the working copy's header in place;
   # keep the improved image (under its original name) for manual review
   if grep -q 'SIP_REFIT: applied the refit solution' audit_image.log ;then
    if util/listhead "$IMAGE_BASE" 2>/dev/null | grep -q 'VaST SIP refit' ;then
     cp "$IMAGE_BASE" "$OUTPUT_DIR"/repaired/"$IMAGE_BASE"
    elif [ -s wcs_"$IMAGE_BASE" ] && util/listhead wcs_"$IMAGE_BASE" 2>/dev/null | grep -q 'VaST SIP refit' ;then
     cp wcs_"$IMAGE_BASE" "$OUTPUT_DIR"/repaired/"$IMAGE_BASE"
    fi
   fi
  fi
  rm -f "$IMAGE_BASE" wcs_*.fits wcs_*.fits.wcscat* ./*.blindly_trusted_wcs
 done
 return 0
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
echo "Batch SIP-refit audit: $(wc -l < "$IMAGE_LIST") images, $N_WORKERS workers, load cap $MAX_LOAD"
echo "Ledger: $LEDGER"

# restart the queue scan from the top on every invocation: the ledger and
# failed-list greps in next_image() skip everything already processed, and
# rescanning ensures images that were handed out but never finished (e.g.
# a worker killed mid-solve) are picked up again
echo 0 > "$QUEUE_POS_FILE"

for WORKER_ID in $(seq 1 "$N_WORKERS") ;do
 setup_worker "$WORKER_ID" || exit 1
done

for WORKER_ID in $(seq 1 "$N_WORKERS") ;do
 run_worker "$WORKER_ID" &
done
wait

TOTAL_DONE=$(wc -l < "$LEDGER")
TOTAL_FAILED=$(wc -l < "$FAILED_LIST")
TOTAL_REPAIRED=$(ls "$OUTPUT_DIR"/repaired/ 2>/dev/null | wc -l)
echo "Audit finished: $TOTAL_DONE audited, $TOTAL_REPAIRED improved (in $OUTPUT_DIR/repaired/), $TOTAL_FAILED failed (see $FAILED_LIST)"
