#!/usr/bin/env bash
#
# Per-field cloud-affected-image filter for the NMW archive.
#
# For each plate-solved FITS in the given INPUT_DIR, runs util/imstat_vast
# and records MEAN, SD, MAD, and the SD/MAD ratio. The images are grouped
# by NMW target field name (the substring between 'wcs_fd_' and the next
# '_' in the basename). For every field the script writes 4 sorted log
# tables and partitions the field's images into "keep" plus three
# rejection bins.
#
# Why these metrics:
#   - HIGH MEAN    -- bright sky background; usually clouds or twilight.
#   - LOW SD       -- few stars detected on the frame.
#   - LOW SD/MAD   -- SD is sensitive to point sources, MAD to variable
#                     background, so a low ratio means the background
#                     dominates the noise (cloud-contaminated frame).
#
# Side effects in INPUT_DIR (the script REQUIRES write access here):
#   log/      one per-field 3-column table per metric, sorted by metric:
#               MAD_SD_cloud_filter_<FIELD>.txt
#               SD_cloud_filter_<FIELD>.txt
#               MAD_cloud_filter_<FIELD>.txt
#               MEAN_cloud_filter_<FIELD>.txt
#             Columns: <value>  <percentile 0..100>  <full path>
#             Paths reflect the file's location AFTER the moves below.
#   MEAN/     FITS files in the top 20% MEAN (likely cloudy / bright sky)
#   SD/       FITS files in the bottom 20% SD (few detectable stars)
#   MAD_SD/   FITS files in the bottom 20% SD/MAD ratio (cloud-affected)
# Overlap priority is MEAN > SD > MAD_SD: each file lands in at most one
# rejection bin.
#
# Usage:  util/MAD_SD_cloud_filter_for_NMW_archive.sh <directory>
# Tuning: NPROC=<n> in env to set parallelism (default: $(nproc)).

#################################
# Safe POSIX locale -- numeric awk parses imstat_vast output reliably.
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Per-field parallelism for imstat_vast. imstat_vast is a single-threaded
# CPU+IO worker and most fields have many images; running N copies in
# parallel cuts wall-clock time roughly linearly until disk or CPU
# saturates. Default to nproc; override with `NPROC=4 ./script ...`.
NPROC=${NPROC:-$(nproc 2>/dev/null || echo 4)}

# Filter cutoff -- percentile fraction used to pick files to move into the
# rejection bins. 0.20 = top/bottom 20%. For a field with N images, the
# number moved per criterion is floor(N * FILTER_FRACTION); fields with
# fewer than ceil(1/FILTER_FRACTION) images cannot meet the cutoff and
# none of their files are moved (the log files are still written).
FILTER_FRACTION=0.20

if [ $# -ne 1 ];then
 echo "Usage: $0 <directory containing wcs_fd_*.fits images>" >&2
 exit 1
fi

INPUT_DIR="$1"
if [ ! -d "$INPUT_DIR" ];then
 echo "ERROR: '$INPUT_DIR' is not a directory" >&2
 exit 1
fi
if [ ! -w "$INPUT_DIR" ];then
 echo "ERROR: input directory '$INPUT_DIR' is not writable; the script needs" >&2
 echo "       to create log/, MEAN/, SD/, MAD_SD/ subdirectories inside it" >&2
 echo "       and move filtered FITS files there." >&2
 exit 1
fi

# Per-run output subdirectories inside INPUT_DIR:
#   log/    -- per-field MAD_SD/SD/MAD/MEAN cloud_filter_<FIELD>.txt tables
#   MEAN/   -- FITS files in the top 20% MEAN (likely bright sky / clouds)
#   SD/     -- FITS files in the bottom 20% SD (few stars detectable)
#   MAD_SD/ -- FITS files in the bottom 20% SD/MAD ratio (cloud-affected)
# Pre-create them once so the per-field loop just has to write/move into them.
for sub in log MEAN SD MAD_SD; do
 mkdir -p "$INPUT_DIR/$sub" || {
  echo "ERROR: failed to create '$INPUT_DIR/$sub'" >&2
  exit 1
 }
done

# This script lives in util/ next to the imstat_vast binary; resolve the
# binary relative to the script's own directory so the script works
# regardless of the caller's cwd.
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
IMSTAT="$SCRIPT_DIR/imstat_vast"
if [ ! -x "$IMSTAT" ];then
 echo "ERROR: imstat_vast binary not found / not executable at $IMSTAT" >&2
 echo "Build VaST first ('make') so util/imstat_vast is produced." >&2
 exit 1
fi

# Per-image worker. Reads one FITS path on argv, runs imstat_vast, parses
# MAD and SD, appends "<ratio> <path>" to the file in $RAW_OUT and emits a
# progress line on stderr. Skip on imstat failure, missing fields, or
# MAD == 0 (degenerate image -- saturated, blank -- would divide by zero).
#
# Race-free across parallel workers:
#   - The result line is appended to $RAW_OUT via the shell's `>>` redirect,
#     which opens the file with O_APPEND. POSIX guarantees that for a file
#     opened with O_APPEND, the seek-to-end and the write() of a single
#     call are performed atomically with respect to other writes. Each
#     line emitted here is one short (<200 byte) printf, well under
#     PIPE_BUF on every platform of interest, so two concurrent workers
#     finishing at the same instant cannot interleave bytes inside a row
#     or cause the file to be truncated.
#   - The progress line on stderr is a single short printf per worker as
#     well; the same atomicity rules apply to the terminal/pipe stderr.
#
# Exported below so xargs -P workers (each a fresh `bash -c`) can call it.
process_one_image() {
 local f="$1"
 local out mad sd mean ratio
 out=$("$IMSTAT" "$f" 2>/dev/null)
 if [ $? -ne 0 ] || [ -z "$out" ];then
  printf '  SKIP (imstat fail): %s\n' "$(basename "$f")" >&2
  return
 fi
 mad=$(printf '%s\n' "$out" | awk '$1 == "MAD=" {print $2}')
 sd=$(printf '%s\n' "$out" | awk '$1 == "SD=" {print $2}')
 mean=$(printf '%s\n' "$out" | awk '$1 == "MEAN=" {print $2}')
 if [ -z "$mad" ] || [ -z "$sd" ] || [ -z "$mean" ];then
  printf '  SKIP (parse fail): %s\n' "$(basename "$f")" >&2
  return
 fi
 ratio=$(awk -v sd="$sd" -v mad="$mad" \
             'BEGIN { if (mad + 0 == 0) exit 1; printf "%.6f", sd / mad }')
 if [ $? -ne 0 ] || [ -z "$ratio" ];then
  printf '  SKIP (MAD=0): %s\n' "$(basename "$f")" >&2
  return
 fi
 printf '  SD=%-12s MAD=%-12s MEAN=%-12s SD/MAD=%-12s %s\n' \
        "$sd" "$mad" "$mean" "$ratio" "$(basename "$f")" >&2
 # Each worker opens $RAW_OUT independently with O_APPEND -- avoids the
 # shared-fd corner case where a parent-opened (no O_APPEND) descriptor
 # inherited by all xargs children might allow writes to step on each
 # other on platforms outside Linux's f_pos_lock serialisation.
 # Five columns: ratio sd mad mean path. The path is always the LAST
 # column and contains no whitespace (NMW filename convention), so $NF
 # in the post-processing awk reliably recovers it.
 printf '%s %s %s %s %s\n' "$ratio" "$sd" "$mad" "$mean" "$f" >> "$RAW_OUT"
}
export -f process_one_image
export IMSTAT

# Collect unique target-field names. NMW images are named
#   wcs_fd_<FIELD>_<rest-of-name>.fits
# so the field is the substring between 'wcs_fd_' and the next '_'.
# Only top-level REGULAR files matching the full pattern are considered:
# subdirectories (e.g. the script's own MEAN/, SD/, MAD_SD/, log/ bins),
# symlinks to non-files, and basenames missing the field/rest separator
# (e.g. wcs_fd_something.fits with no second underscore) are skipped.
FIELDS_TMP=$(mktemp)
trap 'rm -f "$FIELDS_TMP"' EXIT

for f in "$INPUT_DIR"/wcs_fd_*.fits; do
 # If the glob matched nothing, bash leaves it literal -- skip such pseudo-entries.
 [ -e "$f" ] || continue
 # Skip directories and anything that isn't a regular file.
 [ -f "$f" ] || continue
 base=$(basename "$f")
 rest=${base#wcs_fd_}
 field=${rest%%_*}
 # Reject basenames that don't have a '_' after the field part -- "$field"
 # equals "$rest" exactly when no '_' was found in rest, i.e. the basename
 # is wcs_fd_<something>.fits with no field/rest separator.
 if [ -z "$field" ] || [ "$field" = "$rest" ];then
  continue
 fi
 echo "$field"
done | sort -u > "$FIELDS_TMP"

N_FIELDS_TOTAL=$(wc -l < "$FIELDS_TMP")
if [ "$N_FIELDS_TOTAL" -eq 0 ];then
 echo "ERROR: no wcs_fd_*.fits files found in $INPUT_DIR" >&2
 exit 1
fi
echo "Found $N_FIELDS_TOTAL unique field(s) in $INPUT_DIR; processing all of them."

n_processed=0
n_skipped=0
while read -r FIELD; do
 n_processed=$((n_processed + 1))
 echo "--- field $n_processed/$N_FIELDS_TOTAL: $FIELD ---"

 # Skip fields that were already processed in a previous run. Detection
 # uses the per-field log tables this script writes: if all four exist
 # and are non-empty, the field was handled before. Re-processing would
 # be misleading -- some of the field's FITS may already have been moved
 # into MEAN/, SD/, MAD_SD/ subdirs, so a fresh imstat_vast pass over
 # what is left in INPUT_DIR would only see the surviving "keep" set and
 # the new log tables would no longer describe the full field.
 SKIP_FIELD=1
 for metric in MAD_SD SD MAD MEAN; do
  logf="$INPUT_DIR/log/${metric}_cloud_filter_${FIELD}.txt"
  if [ ! -s "$logf" ];then
   SKIP_FIELD=0
   break
  fi
 done
 if [ "$SKIP_FIELD" -eq 1 ];then
  echo "  SKIP: log/{MAD_SD,SD,MAD,MEAN}_cloud_filter_${FIELD}.txt already present"
  n_skipped=$((n_skipped + 1))
  continue
 fi

 # Collect the field's FITS paths into a list. Using a nullglob-style guard
 # via the -e test inside the loop keeps the script working with old bash
 # versions that lack `shopt -s nullglob`. The -f test additionally drops
 # any subdirectory whose name happens to match wcs_fd_<FIELD>_*.fits.
 FILES=()
 for f in "$INPUT_DIR"/wcs_fd_"${FIELD}"_*.fits; do
  [ -e "$f" ] || continue
  [ -f "$f" ] || continue
  FILES+=("$f")
 done
 N_IMAGES=${#FILES[@]}
 if [ "$N_IMAGES" -eq 0 ];then
  echo "  (no FITS files matched for $FIELD)"
  continue
 fi
 echo "  running imstat_vast on $N_IMAGES image(s) with $NPROC parallel worker(s)..."

 # Parallel imstat_vast. Workers append their result lines directly to
 # $RAW_OUT (exported below) with O_APPEND -- see the comment block above
 # process_one_image() for the atomicity reasoning. Skip / progress
 # diagnostics go to stderr (visible on the terminal).
 RAW=$(mktemp)
 RAW_OUT="$RAW"
 export RAW_OUT
 printf '%s\n' "${FILES[@]}" \
  | xargs -d '\n' -I{} -P "$NPROC" bash -c 'process_one_image "$@"' _ {}
 unset RAW_OUT
 N_OK=$(wc -l < "$RAW")

 if [ "$N_OK" -eq 0 ];then
  echo "WARNING: no usable imstat_vast results for field $FIELD" >&2
  rm -f "$RAW"
  continue
 fi

 # Helper: take the per-field RAW (5 columns: ratio sd mad mean path),
 # sort ascending by the metric column $1, and emit a 3-column file
 # "<metric> <percentile> <path>" to $2. Percentile uses
 # (i - 1) / (n - 1) * 100 so smallest is 0%, largest is 100%; n == 1
 # short-circuits to 50% to avoid a 0/0. The path is recovered as $NF
 # (always the last column; NMW filenames contain no whitespace).
 write_metric_file() {
  local col="$1" outfile="$2"
  sort -k"$col","$col" -g "$RAW" | awk -v col="$col" -v n="$N_OK" '
   { val[NR] = $col; path[NR] = $NF }
   END {
    for (i = 1; i <= n; i++) {
     if (n == 1) {
      pct = 50.0
     } else {
      pct = (i - 1) / (n - 1) * 100.0
     }
     printf "%-12s %7.3f %s\n", val[i], pct, path[i]
    }
   }' > "$outfile"
 }

 # Number of files to move per criterion. floor(N * FILTER_FRACTION) so
 # small fields (N * FRACTION < 1) get NO moves but still get log files.
 N_CUTOFF=$(awk -v n="$N_OK" -v frac="$FILTER_FRACTION" \
            'BEGIN { v = int(n * frac); if (v < 0) v = 0; printf "%d", v }')

 # Build the move plan: "<original_path> <dest_subdir>" lines.
 # Priority is MEAN > SD > MAD_SD (first occurrence wins for overlaps).
 # MEAN moves the HIGHEST values (top 20% MEAN -- bright sky / clouds);
 # SD and MAD_SD move the LOWEST values (bottom 20% -- few stars, or
 # cloud-dominated background).
 DEST_MAP=$(mktemp)
 if [ "$N_CUTOFF" -gt 0 ];then
  {
   sort -k4,4 -g -r "$RAW" | head -n "$N_CUTOFF" | awk '{ print $NF, "MEAN" }'
   sort -k2,2 -g    "$RAW" | head -n "$N_CUTOFF" | awk '{ print $NF, "SD" }'
   sort -k1,1 -g    "$RAW" | head -n "$N_CUTOFF" | awk '{ print $NF, "MAD_SD" }'
  } | awk '!seen[$1]++ { print }' > "$DEST_MAP"
 fi
 N_MOVES=$(wc -l < "$DEST_MAP")
 echo "  cutoff = floor($N_OK * $FILTER_FRACTION) = $N_CUTOFF per criterion; planning $N_MOVES move(s) total"

 # Rewrite RAW so the path column reflects each file's FINAL location
 # AFTER the moves below. The log files written next then point to the
 # files where they actually live after the script finishes.
 if [ "$N_MOVES" -gt 0 ];then
  RAW_REWRITTEN=$(mktemp)
  awk -v input_dir="$INPUT_DIR" -v dmf="$DEST_MAP" '
   BEGIN {
    while ((getline line < dmf) > 0) {
     m = split(line, a, " ")
     if (m >= 2) dest[a[1]] = a[m]
    }
    close(dmf)
   }
   {
    p = $NF
    if (p in dest) {
     n = split(p, parts, "/")
     base = parts[n]
     $NF = input_dir "/" dest[p] "/" base
    }
    print
   }' "$RAW" > "$RAW_REWRITTEN"
  mv "$RAW_REWRITTEN" "$RAW"
 fi

 write_metric_file 1 "$INPUT_DIR/log/MAD_SD_cloud_filter_${FIELD}.txt"
 write_metric_file 2 "$INPUT_DIR/log/SD_cloud_filter_${FIELD}.txt"
 write_metric_file 3 "$INPUT_DIR/log/MAD_cloud_filter_${FIELD}.txt"
 write_metric_file 4 "$INPUT_DIR/log/MEAN_cloud_filter_${FIELD}.txt"

 echo "  wrote $N_OK rows to log/{MAD_SD,SD,MAD,MEAN}_cloud_filter_${FIELD}.txt"

 # Perform the moves. A file may have been planned for one bin only (priority
 # already resolved when DEST_MAP was built), so each plan line is a single
 # mv. The "[ -e ]" guard handles the case where the source was renamed
 # under the script's feet between planning and execution -- defensive but
 # unlikely with a single-writer per request.
 if [ "$N_MOVES" -gt 0 ];then
  while IFS=' ' read -r src dest; do
   [ -z "$src" ] && continue
   if [ ! -e "$src" ];then
    echo "  WARNING: source vanished before move: $src" >&2
    continue
   fi
   bn=$(basename "$src")
   if mv "$src" "$INPUT_DIR/$dest/$bn";then
    echo "  moved -> $dest/: $bn"
   else
    echo "  WARNING: mv failed for $bn -> $dest/" >&2
   fi
  done < "$DEST_MAP"
 fi

 rm -f "$RAW" "$DEST_MAP"
done < "$FIELDS_TMP"

echo "Done. Processed $((N_FIELDS_TOTAL - n_skipped))/$N_FIELDS_TOTAL field(s); skipped $n_skipped already-logged field(s)."
exit 0
