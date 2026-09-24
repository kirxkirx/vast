# VaST Maintenance Notes

Notes on things that work and don't work when maintaining VaST code.
Update this file as you learn new things.

## Git Workflow

- Tracked in git from the `.claude/` folder: `CLAUDE.md`, `notes.md` (this file) and the design docs
  `airmass_zeropoint_forced_photometry_design.md` and `forced_photometry_reference_filter_design.md`
  (tracked scripts cite them by their `.claude/` path, so do not move them). Stage them when they change.
- **Never stage** `.claude/settings.local.json`, `.claude/projects/` or editor backup files (`*~`) -
  they are per-machine and are listed in `.gitignore`.
- After making changes, use `git add` only on the source code files and docs that were modified

## Running VaST

- **Never run `./vast` directly** - it opens a GUI (pgplot) window for image display.
  Use headless tools like `util/solve_plate_with_UCAC5` or test scripts instead.
- **Never run `util/examples/test_vast.sh`** - it takes many hours.

## UCAC5 Remote Servers

- Three servers: scan.sai.msu.ru, vast.sai.msu.ru, tau.kirx.net
- All serve the same CGI endpoint: `/cgi-bin/ucac5/search_ucac5.py`
- The CGI expects multipart form upload with fields: `file` (RA/Dec text), `submit`, `brightmag`, `faintmag`, `searcharcsec`
- **The CGI needs a large input file** (hundreds/thousands of star positions). With only a few stars it returns just the startup message and no catalog data. Use the M31 test input (`../vast_test_lightcurves/test_vizquery_M31.input`, 2000 positions) for testing.
- The C code uses `--max-time 600` (10 minutes) for UCAC5 requests

## Build System

- `make` must be run without `-j` (no parallel builds)
- `gcc -fsyntax-only -I src` is fast for checking C syntax before full build
- Full build takes several minutes

## Shell Scripts

- Many scripts use `$RANDOM` and process substitution - require bash, not sh
- `shellcheck` catches most issues but some warnings (SC2181, SC2034 for unused read vars) are intentional patterns
- **Never use `gawk`** - rely only on portable `awk` functionality for maximum portability across platforms

## bash 3.2 traps (macOS /bin/bash 3.2.57 runs every `#!/usr/bin/env bash` script on the macOS CI runner)

- A `case` statement inside `$( ... )` fails to parse (`syntax error near unexpected token ;;`)
  unless every pattern has the leading paren form `(pattern)`. bash reads a script as it
  runs, so the error hits only when execution reaches that compound command - in test_vast.sh
  this killed the macOS CI run 80 min in (Sep 19 and 24, 2026, SGR04NOVA_DEBUG=$( ... ) block).
  Simplest: no `case` inside `$( )`; use `echo "$X" | grep -q ... || continue`. The first
  test_vast.sh section now also runs `bash -n` on util/examples/*.sh, so on macOS such an
  error fails the run in its first minute. Caveat: bash 3.2 `-n` does not parse the BODIES
  of `$( )` blocks, it only catches this extraction failure.
- A `/` inside a QUOTED pattern of `${var//pattern/repl}` still ends the pattern in bash 3.2:
  `${R//"</a"/ }` on 'V0615 Vul</a' gives 'V0615 Vula"/ /a'. This garbled VSX names in
  util/search_databases_with_curl.sh on macOS since 2019 and, whenever GCVS did not answer,
  broke the CBA/AAVSO report file names (NMWNVUL24ST_CBASCRIPTTEST_NOOUTPUTFILE, Jun 27 and
  Sep 12, 2026). Use `sed 's:</a:...:g'` for patterns containing '/'. (The common
  `${VAST_PATH/'//'/'/'}` idiom is also a no-op under 3.2 but is followed by a sed fallback.)
- To test for these on Linux, build bash 3.2.57 in a scratch dir: download
  bash-3.2.57.tar.gz from ftp.gnu.org, `./configure --without-bash-malloc
  CFLAGS='-O1 -std=gnu89 -Wno-implicit-function-declaration -Wno-int-conversion' && make`
  (works with gcc 11), then run `./bash -n` on the scripts and run suspicious snippets with it.
- Never edit util/examples/test_vast.sh in place while a test_vast.sh run is using it (bash
  reads it incrementally through fd 255). Replace it atomically instead: `cp` the new version
  to a temp file in the same directory, then `mv` it over the original. The running bash keeps
  reading the old inode.
- shellcheck on the whole 36k-line test_vast.sh gets OOM-killed on a 15 GB machine. Check the
  edited sections by extracting them into a separate file with a bash shebang.

## C Code

- C89/C90 style required: all variables declared at the very start of the function, before any executable statements
- Do NOT use `{ }` block scopes to introduce new variable declarations mid-function - move them to the function top instead. This applies even though C89 technically allows declarations at the start of any block; the project style requires function-top only for uniformity.
- Use `gcc -Wdeclaration-after-statement -fsyntax-only -I src` to find all mixed declarations and code violations. This catches declarations after executable statements, including inside `#if` preprocessor blocks.
- GSL library is used for sorting and statistics (gsl_sort, gsl_stats_median_from_sorted_data)
- `lightcurve_io.h` has a known mixed-declaration violation (line 23, `nonzero_mag_err`). This shows up as a warning in many files that include it but is outside the scope of individual file fixes.
- When moving block-scope variable declarations to the function top, watch for name collisions (e.g., both `float x` and `double x` in different scopes of the same function). Rename the conflicting variables to avoid shadowing (e.g., `loop_x` for the float version, `xd` for the double version).
- When moving declarations out of `{ }` block scopes, remember to also move any initializers to assignment statements at the original location (split declaration from initialization).

## Calibration frame selection (darks/flats)

- `util/find_best_dark.sh` (env `DARK_FRAMES_DIR`) and `util/find_best_flat.sh` (env `FLAT_FIELDS_DIR`) each take the science image as `$1` and print the best-matching calibration frame. Darks match on NAXIS1/2 + EXPTIME + SET-TEMP; flats match on NAXIS1/2 + FILTER + CAMERA + CAMERAID + TELESCOP (no exptime/temp). Both then pick the minimum |JD diff| via `util/get_image_date`.
- The flat finder's keyword matching MUST agree with `util/ccd/md.c` (the applier), otherwise the finder can hand `md` a flat that `md` then rejects (-> flat-fielding silently skipped). `md.c` errors out on a real TELESCOP/CAMERA/CAMERAID/FILTER mismatch but assumes-match when a keyword is absent.
- GOTCHA: `is_meaningful_keyword_value()` in `md.c` rejected values shorter than 2 chars. That is wrong for FILTER, where single-letter names (R, V, B, I, C) are normal -> it made FILTER matching always assume-match. Fixed by giving it a `min_len` parameter: 2 for TELESCOP/CAMERA/CAMERAID, 1 for FILTER. The bash finder mirrors this (`keyword_compatible ... 1` for FILTER).
- `util/listhead` prints raw 80-char FITS cards (8-char keyword, `=` at col 9, single-quoted string values). To read a string keyword robustly in bash (multi-word values like 'SBIG ST-9'), extract the text between the first pair of single quotes and trim trailing blanks, rather than `awk '{print $1}'`.
- `transient_factory_test31.sh` and `calibrate_and_platesolve.sh` use env vars `DARK_FRAMES_DIR_OR_FILE` / `FLAT_FIELD_DIR_OR_FILE` (a directory -> finder picks best; a single file -> used directly). The finder scripts themselves keep their original `DARK_FRAMES_DIR` / `FLAT_FIELDS_DIR` interfaces; the callers do the file-vs-dir branching and pass the directory to the finder inline.
- These env vars are NOT set by `unmw` or `astrocam-go` (verified), so renaming them in the factory is safe externally. But `util/examples/test_vast.sh` sets them for its calibration tests AND calls `find_best_dark.sh`/`util/ccd/md` directly, so those test blocks set BOTH the old names (for the direct tool calls) and the new `*_OR_FILE` names (for the factory).
- `util/find_best_dark.sh` aborts on the first unreadable/dateless file in the directory; `util/find_best_flat.sh` instead SKIPS such candidates (a flats directory may legitimately contain other files).

## HISTORY entries

- Keep them brief: a few lines per change, user-facing only. State what the feature does and key user-visible behavior.
- Omit: variable renames, internal "kept in sync" notes, applier/helper-level details, edge cases (e.g. single-letter filters), and "handy for..." justification sentences.

## VSX vsx.dat parsing (lib/catalogs/vsx.dat, CDS B/vsx)

- The byte positions in the CDS B/vsx ReadMe are off by 1-4 columns relative to the actual vsx.dat file. Empirically (verified against 8.5M records): max mag digits at bytes 96-101, u_max ':' at 103, n_max passband from 105, the "min field holds an amplitude" flag is a standalone 'Y' at byte 113 (1.93M records) or 114 (2.7k records), min mag digits at 118-123, n_min passband from 127, Epoch (JD) from 137, Period from ~158.
- Parse the magnitude fields by whitespace tokens + position windows, never by exact columns or naive field counting: passbands and JD0 may be absent, shifting field numbers (this bug affected the old LOCAL_PERIOD extraction in util/search_databases_with_vizquery.sh, which took awk field 6 and got the JD0 for amplitude-flagged records).
- Do not confuse the 'Y' amplitude flag with the near-IR "Y" passband: 3 records (HK CMa, V0352 Aur, AQ CVn) have n_max = 'Y' at byte 105. Position matters: a standalone 'Y' before the min value at byte >= ~110 is the amplitude flag.
- When the amplitude flag is set, the max field holds the MEAN magnitude and the amplitude is the FULL peak-to-peak range (per AAVSO VSX docs); the mean may sit near quiescence for dwarf-nova-like stars, so "brightest expected" = mean - full amplitude is the conservative choice.
- ASAS-SN sentinel mean mags of 99.99 exist in asassnv.csv - always range-check magnitudes (accept roughly -5..30) before arithmetic.
- asassnv.csv format detection in check_catalogs_offline.c skips lines shorter than 180 chars BEFORE looking for the 'source_id' header token - a short header line silently leaves the parser in old-format mode (matters when crafting test CSVs).

## Airmass-aware zero-point for forced photometry (2026-07-06)

- Design doc: `.claude/airmass_zeropoint_forced_photometry_design.md`. Feature flag
  `FORCED_PHOTOMETRY_AIRMASS_ZEROPOINT` (default no); gates (`AIRMASS_ZP_*`) in `src/vast_limits.h`.
- `util/pixel_flux_airmass_correction` output-stream discipline: in `--fit-airmass-zeropoint`
  mode stdout carries ONLY the one-line result; the info block goes to stderr. In the other
  modes (`--print-info`, `--predict-list`) the info block IS on stdout - callers extracting
  predict values must skip everything before the `# X_pix ...` header line
  (`awk 'f {print $4} /^# X_pix/ {f=1}'`), not just `grep -v '^#'`.
- The dev machine has NO system matplotlib (Gentoo). For plot-producing runs use the disposable
  venv `~/vast_test/airmass_correction_experiment/venv-matplotlib` by prefixing PATH; the
  plotter (`lib/plot_airmass_zeropoint.py`) exits gracefully when matplotlib is missing and
  callers must treat that as "no plot", never an error.
- Never trust SITELAT/SITELONG on NMW Stas/STL frames (seen swapped since 2024 on STL; Stas
  may be affected too per the user). The factory exports `AIRMASS_ZP_SITELAT/SITELONG` per
  camera; `forced_photometry.sh` falls back to an INSTRUME-based table (ST-8300/STL-11000).

## New ERROR-level log messages vs test_vast.sh report checks (2026-07-06 lesson)

- Many test sections assert `grep -v -i 'Soft' transient_report/index.html | grep -q 'ERROR'`
  finds nothing. Any NEW 'ERROR...' message added to pipeline/calibration scripts will fail
  those sections on datasets that legitimately trigger it - including datasets whose brokenness
  is the test premise (e.g. NMW-STL plate solve failure). When adding an ERROR message:
  grep test_vast.sh for `_ERROR_MESSAGE_IN_index_html` and whitelist the expected message in
  affected sections (and consider a positive presence assertion there, since the message firing
  IS the desired behavior on such datasets).
- Camera-dependent thresholds: the calibration-star yield check (1 percent default) is
  env-overridable via MIN_PERCENT_OF_DETECTED_STARS_MATCHED_FOR_MAG_CALIBRATION; TICA TESS
  FFIs at 21"/pix have a NORMAL yield of ~0.6 percent (227-235 of 38129) with a healthy
  solution, so the TICA camera block exports 0.2. The STL plate-solve-failure dataset yields
  a deterministic 65/19893 = 0.33 percent (same numbers on every host).

## Candidate HTML report block parsers (must not break when changing report output)

- The per-candidate <pre> block "The object was found in X" lines are parsed by: unmw/filter_report.py (is_variable_star reads the FIRST token of the line RIGHT AFTER the sentinel line as the match distance; _extract_crossmatches keys on the regex 'The object was (found|not found) in X'), unmw/autoprocess.sh (grep -A4 ... | grep -c 'not found'), transient_factory_test31.sh (grep -A10 "$RADECSTR" ... | grep 'astcheck' | grep 'not found'), make_report_in_HTML.sh (grep -A1 of the exact VSX found string -> variable name from the next line), util/artificial_star_test_for_transient_search (awk '/not found/ && /VSX|ASASSN-V|astcheck/'), util/search_databases_with_vizquery.sh (grep -A 1 '#   Max.' -> record line).
- Therefore: new information lines must be APPENDED AT THE END of a match block, and must never contain the substrings 'The object was', 'found in' or 'not found'. The large-mag-difference ATTENTION lines use the stable marker substring 'mag brighter than the' that unmw/filter_report.py keys on (LARGE_MAG_DIFF_MARKER) - keep it verbatim in all three producers (search_vsx, search_asassnv in check_catalogs_offline.c, and MPCheck_v2.sh).

## test_vast.sh flag-image greps and PSF sections

- lib/autodetect_aperture_main in STANDALONE mode names its temp files image_pid<PID>.* (not image00000.*). Test assertions must grep 'FLAG_IMAGE image' + '.flag', never the literal 'FLAG_IMAGE image00000.flag'. The non-PSF exclude-ref-image section was updated for this long ago; the PSF variant (EXCLUDEREFIMAGEPSF006) and the photographic-plates check (PHOTOPLATE, inverted logic) still had the old pattern - fixed 2026-07-03.
- The PSF test sections only run when psfex is installed; PSFEX_NOT_INSTALLED is auto-stripped from FAILED_TEST_CODES. psfex appeared on this dev machine only on 2026-06-15 (/usr/local/bin/psfex 3.24.2), so PSF sections had not run here for a long time - expect stale assertions when a new tool enables a long-skipped section.
- To edit a test script WHILE the suite is running from it: cp to a temp file, edit the copy, bash -n, then mv over the original (atomic rename). The running bash keeps its fd on the old inode and is not disturbed. Never edit the file in place mid-run.
- test_vast.sh strips known-environmental failure codes at the end (STANDALONEDBSCRIPT001a/001b_GCVS, scan.sai.msu.ru_REMOTEPLATESOLVE007-009, PSFEX/WCSTOOLS/VARTOOLS_NOT_INSTALLED, ...) - check that list before investigating a FAILED section summary line.
- PGPLOT truncates long device filenames: around 90 characters the /png driver opens a chopped path, prints "PGPLOT /png: could not open file ... plotting disabled" to stderr, every plot call becomes a no-op, and cpgbeg() STILL RETURNS SUCCESS - so a tool can "succeed" while writing nothing. lightcurve_png.c handles this (2026-07-03) by rendering to a short temp name in cwd and rename()/copying to the destination, plus a stat() check that the output exists before claiming success. Any other PGPLOT-PNG tool given a user-supplied output path needs the same treatment; never trust cpgbeg's return value as proof the file opened.

## Source monitoring implementation (2026-07-06)
- vast_image_details.log fields are NOT stable by position ($4 is 'exp=', the aperture value
  is $9): always extract by key, e.g. `sed 's/.*ap=[ ]*//' | awk '{print $1}'`. A positional
  awk grab of 'exp=' passed the -z emptiness check and silently broke util/forced_photometry
  (invalid aperture -> empty output, no error message) - add explicit numeric validation and
  a WARNING line when a tool that should produce output produces none.
- Never edit a shell script while a background instance of it is running (bash reads the file
  incrementally - the running instance can execute garbage). Wait for completion, then edit.
- The unmw monitoring entry point resolves its own directory via realpath(__file__):
  a SYMLINKED copy of monitoring_update.py resolves to the target dir and reads the wrong
  local_config.sh. Sandbox deployments need a real file copy of the entry point (imported
  libs may stay symlinked).
- aavso.org returns 403 to python/urllib user agents; curl with a browser UA string works
  for fetching the AAVSO Extended Format spec. Fainter-than records: MAG field prefixed
  with '<' (dot required), MERR field 'na'; 15 comma-separated fields per record.
- nmw_forced_phot_lib._read_numeric_columns parses only the leading N numeric columns and
  ignores trailing tokens, so 4-column monitoring lightcurve.dat (JD mag err camera) feeds
  render_lightcurve_plots directly - no projection files needed (lib/lightcurve_png also
  tolerates trailing columns).

## NMW kadar STL-11000M reference image astrometry and the Tycho-2 yield check (2026-07-10)
- The 'ERROR: only N of M stars ... matched the Tycho-2 photometric calibration catalog' lines that
  appeared on scan.sai.msu.ru summary pages starting the night of 2026-07-08/09 are NOT a regression:
  the yield check itself is new (added 2026-07-04, first live on kadar with the Jul 8 build); the
  underlying low match counts are bit-identical in runs from at least 2026-06-10 (reference-image
  .wcscat files are cached in the persistent per-camera VaST work dir and reused every night).
- Root cause (verified by downloading the actual reference image and reproducing the server numbers
  bit-exactly, 246/8670 matched, ZP 21.4766): the reference images carry DEGENERATE Astrometry.net
  TAN-SIP order-2 solutions made in Jul/Aug 2025, when the local solve path (util/identify.sh, which
  util/wcs_image_calibration.sh symlinks to) passed no --tweak-order (so solve-field used its default
  order 2) and had no verify re-tweak (the SIP was fitted only on quad-index stars). The bad fit has
  quadratic SIP terms ~4e-6 (100x larger than a good solve; the header's own SIP correction reaches
  465") and a skewed CD matrix (CD1_1 off by 1% from the true scale); residuals vs Tycho-2 are
  50-100" over the WHOLE frame including 92" median at the field center. xy2sky evaluates the header
  exactly (verified against an independent SIP implementation) - the stored solution itself is bad.
  --tweak-order 3 came 2025-12-13..16, the verify re-tweak 2026-05-13 (526d9167), so nightly
  second-epoch solves are fine (order 3, FoV 921.8', 78% Tycho-2 yield) but the trusted-because-
  Astrometry.net reference headers from mid-2025 never got re-solved.
- Re-solving the same 2025 reference file with current VaST (lib/astrometry/strip_wcs_keywords +
  util/wcs_image_calibration.sh, local astrometry.net at /usr/local/astrometry/bin on this machine,
  not in PATH) recovers 6720/8670 = 77.5% yield (vs 246 = 2.8%), calibration rms 0.166 vs 0.296 mag,
  ZP shift 0.02 mag. So the fix is real: re-solve the reference images (util/
  solve_plate_with_best_sip_order.sh automates the order choice), replace their embedded WCS, and
  clear the cached wcs_<ref>.fts/.wcscat in per-camera work dirs. Deleting only the caches is NOT
  enough - the broken trusted header would be re-copied from the reference file itself.
- The check flags only crowded MW fields because the deep default.sex.telephoto_lens_vSTL catalog
  (60-100k detections) inflates the denominator; the same astrometric deficiency in sparse fields
  stays above the 1% threshold. Bright-config matching (2.8%) passes everywhere, masking the issue.
- Data access for reproducing server runs on another machine: results_* dirs serve HTML/logs/PNGs;
  the sibling img_<origname>_<suffix> dirs serve raw + fd_ + wcs_fd_*.fz images of the SECOND epoch
  (old img_ dirs get pruned); reference images ARE downloadable from
  uploads/NMW_reference_images_2012/ (linked under 'Full images' in candidate blocks). As of
  2026-07-10 transient_factory_test31.sh also writes a 'FITS images used in this processing run'
  link section after 'Processing complete!' so the links exist even for zero-candidate runs.

## Source monitoring auto-update never fired on production (found 2026-07-10)
- Symptom: monitoring pages (e.g. AT_2026rdg on tau.kirx.net) frozen at the Jul 7 manual
  --reconcile data although covering fields were observed nightly; no monitoring_update.log,
  no monitoring_positions.txt, no monitoring_raw_measurements.txt anywhere = the autoprocess
  hook never executed, ingest included.
- Root cause: autoprocess.sh resolved its own directory with $(dirname $(readlink -f "$0"))
  INSIDE the monitoring hook, i.e. AFTER 'cd "$IMAGE_DATA_ROOT"' / 'cd "$ABSOLUTE_PATH_TO_IMAGES"'.
  wrapper.sh invokes it as './autoprocess.sh', so the relative $0 resolved against the CURRENT
  directory (the image dir) where monitoring_update.py does not exist -> the gate
  '[ -s $DIR/monitoring_update.py ]' failed silently on every upload. GNU 'readlink -f' happily
  resolves nonexistent paths, so nothing errored. Manual tests used absolute paths and worked.
- Lesson (generalizes the earlier realpath(__file__) symlink note): resolve $0 to an absolute
  script dir ONCE at the very top of a script, before any cd; never re-derive it later. A
  relative $0 is only meaningful in the initial working directory.
- Fix: /tmp/unmw autoprocess.sh defines UNMW_SCRIPT_DIR right after the local_config block and
  the monitoring hook uses it. Deploy = copy to /var/www/tau.kirx.net/cgi-bin/unmw/ (root-owned).
  Gap backfill = 'sudo -u apache python3 .../monitoring_update.py --reconcile' (incremental,
  measures only ledger-missing images; also activates any not-yet-reconciled list entries,
  e.g. the two blazars, which adds their archive backfill time).

## UCAC5-based TAN-SIP refit in solve_plate_with_UCAC5 (added 2026-07-24)
- refit_sip_from_catalog_matches() in src/solve_plate_with_UCAC5.c refits CRVAL+CD+SIP
  (order 3 default, VAST_SIP_REFIT_ORDER=2..5) by linear least squares in intermediate TAN
  coordinates from the ~900 UCAC5 matches, with iterative 3sigma-MAD clipping. Applied only
  if the clipped robust RMS beats the incumbent raw-header residuals by >10%
  (SIP_REFIT_MIN_IMPROVEMENT_FACTOR 0.9) - this margin makes repeated runs stable (a second
  pass on an already-refit image keeps the original). VAST_DISABLE_UCAC5_SIP_REFIT=1 turns
  it off. After applying, the .wcscat is regenerated via
  lib/correct_sextractor_wcs_catalog_using_xy2sky.sh so all products describe the header WCS.
- Do NOT re-fit the plane/mag corrections on top of a sub-arcsecond solution: they only add
  their own fit noise (Peg-04: raw 0.44" but DIAG jumped to 0.64" with corrections stacked;
  0.49" without). After the refit the corrected-position chains are set to the model itself.
- The plane-fit stage of correct_measured_positions() consumes stars[].d_ra/d_dec cached at
  match time; any code that changes measured positions afterwards must refresh those offsets
  or the old error field gets re-applied.
- solve-field's --verify image re-tweak on dense wide fields scores log-odds ~0 and degenerates
  into a many-minute blind quad search; identify.sh now wraps it in TIMEOUT 120 and
  solve_plate_with_UCAC5 exports VAST_SKIP_IMAGE_BASED_RETWEAK=1 for its own blind-solve path
  (the refit supersedes the re-tweak there).
- identify.sh used to delete the input FITS during cleanup when the input already sits in the
  vast dir (the "local working copy" is the input itself); guarded with -ef checks. This was
  breaking the post-solve gettime() image-size read: 0 good stars, 0 UCAC5 matches.
- Timing measurements on this box: bash 'time' user CPU is inflated by OpenMP spin-wait under
  high load (440s "CPU" at load 40 vs 158s wall at load 17 for the same run) - use wall time
  at low load, not user time, to judge intrinsic cost.

## SIP refit fallout in Ubuntu CI run 1108 (diagnosed AND fixed 2026-07-24)
- Fixes applied (full `make` clean, NOT yet validated by a real test run):
  the accept gate now compares against `min(raw, corrected)` via the new `rms_before_corrected`
  and prints both baselines; a frame-coverage guard (`SIP_REFIT_MIN_MATCHED_STARS_PER_QUADRANT`
  10 and `SIP_REFIT_MIN_QUADRANT_SHARE` 0.25 of the uniform per-quadrant share) rejects refits
  fitted on part of the frame; util/forced_photometry.sh now runs sky2xy on the plate-solved cwd
  copy the .wcscat describes, with a fallback to the input image on a hard sky2xy failure; the
  Cas-02 test is gated on a local solve-field; the Nova Sgr / TICA literal patterns were widened
  and their empty-DISTANCE_ARCSEC hole closed.

## Plate-solution refit POLICY (settled 2026-07-24)
- A WCS that VaST trusts is KEPT, never refit. Trust is decided in one place only,
  check_if_we_know_the_telescope_and_can_blindly_trust_wcs_from_the_image() in util/identify.sh,
  and that covers Astrometry.net/SCAMP/SWarp provenance as well as the mission pipelines
  (ZTF, TESS, ATLAS, ASTAP). An earlier attempt to split those two groups (refit the
  Astrometry.net ones, keep the mission ones) was rejected: "trusted is trusted".
- The decision reaches the C code through a `<plate-solved image>.blindly_trusted_wcs` marker
  file that identify.sh writes next to the solved copy. An environment variable cannot be used
  for this: util/solve_plate_with_UCAC5 is the PARENT that invokes util/wcs_image_calibration.sh
  (a symlink to identify.sh, as are all five identify_*.sh names), so the child cannot export
  anything back. identify.sh removes any stale marker before it decides; util/clean_data.sh:50
  already deletes it along with the other `wcs_*` files.
- An image with NO trusted WCS is solved and then gets its distortion model determined from the
  UCAC5 matches: orders 2 and 3 are each fitted and the better one wins, but order 3 must beat
  order 2 by more than SIP_REFIT_HIGHER_ORDER_GAIN (0.95) or the simpler model is kept - on
  low-distortion wide-field lenses the extra terms only fit noise. VAST_SIP_REFIT_ORDER still
  pins the order and skips the search. Implementation detail: the selection loop runs one extra
  final pass with the winning order so the coefficients, CRVAL and the clipping mask that the
  rest of the function uses all belong to the order that won - cheaper and far less error-prone
  than trying to keep the winner's GSL objects alive across candidates.
- VAST_FORCE_SIP_REFIT=1 is the user/script switch meaning "I really do want this recomputed";
  util/solve_plate_with_best_sip_order.sh sets it. It overrides the trusted-WCS and TESS checks
  and permits rewriting the caller's own input file.
- Two file-safety rules: never write through a symbolic link (UNCONDITIONAL, not lifted by the
  force switch - transient_factory_test31.sh:2630 links cached solved reference images into the
  run directory and cfitsio follows the link straight into the shared cache, where a concurrent
  run may be reading it); and never rewrite the caller's input image itself, which is detected by
  comparing stat() device+inode of the write target with the input path. The inode test ALONE is
  not enough for the cache case: the factory passes the ORIGINAL reference image path at :2948
  and :2971 while the cwd symlink points somewhere else entirely, so the two inodes differ -
  lstat() on the write target is what catches it.
## THIS DEV BOX IS tau.kirx.net (established 2026-07-26)
- The machine at /home/kirx/vast_test/vast, hostname `tau`, IS the host reachable over http and
  https at tau.kirx.net - confirmed by the user. Production unmw lives here at
  /var/www/tau.kirx.net/cgi-bin/unmw (root-owned, runs as apache); the summary pages served at
  http://tau.kirx.net/unmw/uploads/ are byte-identical to the files in that directory.
- The public name resolves to a REVERSE PROXY (188.226.149.203) in front of this box, so the
  address tau.kirx.net resolves to is NOT the box's own outbound address (129.118.254.21).
  Do not use an IP comparison to decide whether this machine "is" tau.kirx.net - it says no
  while the answer is yes. That mistake was made on 2026-07-25, see below.
- Practical consequence: dev work and production share this machine. util/examples/test_vast.sh
  and any VaST run here touch the same box that serves the nightly transient search.

## Remote plate-solve servers and the self-exclusion (found + fixed 2026-07-25)
- setup_remote_astrometry() in util/identify.sh tests server reachability with ICMP
  `ping -c1 -W1`. On networks where ICMP is filtered NO server answers - on this box both
  tau.kirx.net and scan.sai.msu.ru fail ping while returning HTTP 200. There is a fallback for
  that (an HTTP probe of http://<server>/lk/ looking for /cgi-bin/lk/process_lightcurve.py).
- The fallback skips any server whose name contains the local hostname. Since this box IS
  tau.kirx.net that exclusion is correct in intent; the bug is what happens next. The test forces
  a single server (FORCE_PLATE_SOLVE_SERVER=tau.kirx.net), so excluding it left the candidate
  list EMPTY and the run died with "no servers could be reached" instead of using the server it
  was explicitly told to use.
- THIS INVALIDATES the older note that tau.kirx.net_REMOTEPLATESOLVE001/003/005/007 are
  known-environmental failures caused by kirx.net storage being full. They were this bug, and
  they now pass.
- Fix: apply the self-exclusion only while at least one OTHER candidate server remains. Talking
  to ourselves still works; having no server does not. Production behaviour is unchanged - with
  both servers listed, tau is still excluded in favour of scan.
- Superseded reasoning, recorded so it is not repeated: this was first written up as a
  hostname-SUBSTRING collision ("a box merely named tau losing a different machine's server"),
  justified with the IP mismatch above. Wrong on both counts.

## strip_wcs_keywords removed only the FIRST card of each keyword (found + fixed 2026-07-25)
- cfitsio's fits_delete_key() deletes only the first matching card. src/astrometry/
  strip_wcs_keywords.c called it once per keyword name, so a header holding the same WCS keyword
  twice kept a copy. Real specimen: the NMW Sco6 reference image (SIP_refit_policy_test dataset)
  carries TWO WCSAXES cards; 025_* (STL) and Aql-03 (TTU) carry one, the TICA FFI none - which is
  exactly why only the NMW camera failed the "input left byte-identical" check in the policy test.
- Consequences went beyond non-idempotency: the same single-shot pattern covered CTYPE1, CRVAL1,
  CD1_1 and the TPV/TR/SIP-coefficient keywords, so a duplicated card could leave a partial WCS in
  an image that is supposed to look unsolved. util/identify.sh decides "already solved" by
  grepping for exactly those keywords, so a survivor can make a stripped image look trusted and
  defeat the forced re-solve util/solve_plate_with_best_sip_order.sh relies on.
- Duplicates arise routinely: src/astrometry/insert_wcs_header.c:510 writes the new WCS cards with
  fits_write_record(), which APPENDS rather than replaces. strip-then-insert is safe only if the
  strip is complete; with the bug it was a ratchet that could accumulate cards across solves.
- Fix: bounded helper delete_all_cards_with_this_keyword() looping until KEY_NO_EXIST (cap
  STRIP_WCS_MAX_DUPLICATE_CARDS 1000), used at all 13 deletion sites. Verified: all three frame
  types now strip to zero WCS cards in one pass and are idempotent.
- Cheap way to test a single tool without disturbing a running test suite: compile it standalone,
  e.g. `gcc -O1 -o /tmp/strip_test src/astrometry/strip_wcs_keywords.c -I src -I src/cfitsio-4.6.4
  -L src/cfitsio-4.6.4 -lcfitsio -lm -lz` and run with LD_LIBRARY_PATH=src/cfitsio-4.6.4. Never
  run `make` while a test suite is executing - it swaps the binaries under the running tests.

- Dedicated test: util/examples/test_sip_refit_policy.sh with the SIP_refit_policy_test dataset
  (one frame each from NMW/ST-8300, NMW-STL/STL-11000M, NMW-TTU/QHY600M and TICA TESS). It
  asserts properties (checksums, header signatures) rather than log wording wherever it can, and
  skips the no-trusted-WCS half when there is no local Astrometry.net.
- The refit call at src/solve_plate_with_UCAC5.c:4729 is unconditional, so it fires on EVERY
  plate solve in the whole suite: 0 SIP_REFIT lines in the last green CI log (ea1982e4),
  86 attempts / 85 applied in the failing one (707770a9). Four of the five new failures trace
  to it. Full logs are downloadable per run: gh run download <id> -R kirxkirx/vast
  -n test-artifacts (test_vast_full_output.log, ~15 MB, retained 7 days).
- The accept gate compares the WRONG baseline: rms_before (:3998-4004) is built from
  stars[].ra_deg_measured_orig, i.e. the RAW header WCS, while what acceptance overwrites
  (:4339-4343) is corrected_ra_planefit / corrected_mag_ra / corrected_ra_local, the chain
  AFTER the plane/mag/local corrections - which is already better than raw. So a refit can
  pass the 0.9 gate while making the delivered positions worse. Measured on TICA TESS
  (20"/pix, identical N_match=863): sigma_overall 2.324 -> 2.445", sigma_q1 2.358 -> 3.056".
  The "corrections only add fit noise" premise at :4722-4728 holds for sub-arcsecond
  residuals but not for a 2.4" residual on a 20"/pix camera.
- The accept gate has NO spatial-coverage term (only SIP_REFIT_MIN_MATCHED_STARS 100 and the
  global robust-RMS ratio at :4139). On the NMW-STL plate-solve-failure reference image the
  UCAC5 matches are almost all in the upper half (n_q1=6 n_q2=9 vs n_q3=194 n_q4=223), so the
  order-3 polynomial interpolates that half to ~2" and EXTRAPOLATES into the lower half, which
  gets worse: q1 26.9 -> 30.1", q2 29.9 -> 57.5" (vSTL pass, the one feeding the report), while
  the global sigma falls 5.77 -> 2.21". That is enough for the spatially-blind yield check in
  calibrate_current_field_with_tycho2.sh:286 to stop firing 'plate solution is likely broken'.
  The frame is NOT repaired - a half-broken reference now passes on its good half.
- refit_sip_from_catalog_matches resolves its target through basename() (:396, :3935-3938), so
  it rewrites the header of the CWD working copy only, then regenerates the .wcscat from it
  (:4353). A caller that passed an image from another directory still holds the pre-refit file,
  and the .wcscat then carries refit RA/Dec next to unchanged SExtractor x,y. Any code that
  round-trips .wcscat RA/Dec back through sky2xy on the ORIGINAL file gets apertures displaced
  by the old solution's error - this is what broke the forced photometry test
  (mean -0.0038 -> +0.0235 mag, RMS 0.0145 -> 0.0696); the --list variant, which uses the
  .wcscat pixel columns directly, passed on the same image with the same thresholds.
- Tycho-2 zero points are coupled to the plate solution through a 5" match radius
  (src/catalogs/read_tycho2.h:11 MAX_DISTANCE_ARCSEC): re-solving a reference image reshuffles
  the cross-match and moves the median ZP by ~0.01-0.02 mag. That is what pushed the Nova Sgr
  2024 N1 test magnitude to 11.21 out of its 0.1-mag-wide 11.1x window.
- On GitHub Actions there is NO local astrometry.net ("Local solve-field not found" x37 in both
  logs), so the identify.sh --verify re-tweak block never runs there: the TIMEOUT 120 wrapper
  and VAST_SKIP_IMAGE_BASED_RETWEAK cannot explain any CI failure (they can still matter on
  this dev box and on production servers that do have solve-field).
- The remote blind-solve branch of identify.sh stops after iteration01 and has no second,
  position-hinted solve-field pass like the local branch (:842-882). On the 15.7 deg Cas-02
  field that leaves ~47" astrometry, so only ~210 of 1000 stars fall inside the 46" UCAC5 match
  radius and the refit can only reach ~30" (vs 0.44" locally) - yet the result is still stamped
  RA---TAN-SIP and reported as a success. This is why CAS02RA0SIP002 fails on CI only.
- test_vast.sh gotcha: when a strict candidate-line grep matches nothing, DISTANCE_ARCSEC ends
  up empty and `echo "" | awk '{if ($1 < N) print 1}'` still prints 1, so the companion
  _TOO_FAR guard silently PASSES on a missing detection. Do not read a passing _TOO_FAR code
  as evidence that the object was found.

## UCAC5 spatial index (added 2026-07-30)
- All three UCAC5 matchers (search_UCAC5_localcopy, search_UCAC5_at_scan,
  read_UCAC5_from_vizquery) use a Dec-band/RA-column CSR grid over the detected stars
  (build once per call, stream catalog records, 3-band x 5-column lookup, candidates in
  ascending index order - the ordering is load-bearing for first-match semantics).
  Pre-index implementations kept compiled as *_bruteforce(); VAST_UCAC5_MATCH_BRUTEFORCE=1
  selects them at runtime for A/B tests.
- Column span must be +-2, not +-1: the remote re-match loops accept on a BOX test
  (|dDec|<r AND dRA*cosDec<r) whose RA extreme reaches a full column width from the query.
- The remote UCAC5 service returns slightly varying row sets between identical queries
  (+-1-2 stars run-to-run, verified brute-vs-brute); remote A/B comparisons can only be
  done at the envelope level. The local path is deterministic and A/B bit-identical.
- Local grid A/B verified bit-identical on Cas-02 (RA=0 wrap) and Cyg-08; saves roughly
  half the matching-stage time (matching is ~7% of a solve; SExtraction ~89% dominates).
- WARNING found during A/B (not grid-related): order-5 refit on the Cyg-08 single-frame
  1307 reference produces sigma_q4=145 arcsec (ratio 235) - order-5 corner extrapolation
  with the count-only quadrant coverage guard passing. Needs a per-quadrant minimax check
  in the refit order selection before trusting order-5 defaults on marginal-coverage frames.
- Minimax follow-up (2026-07-28): SIP order selection AND the keep-if-better guard now
  judge on the WORST-QUADRANT robust RMS (sip_refit_worst_quadrant_robust_rms), not the
  overall clipped RMS which is blind to a sacrificed quadrant. On Cyg-08 1307 all orders
  show 155-214 arcsec worst quadrants (structurally unfittable corner) and the refit now
  correctly keeps the original (corrected-chain worst-q 21 arcsec); Cas-02 still selects
  order 5 (0.31 worst-q); good archive solutions still kept. Trial lines now print
  worst_quadrant_rms=..., the order= summary line prints worst_quadrant_rms_before/after.
- Local-correction spatial index (2026-07-28): the 5000-star default slowed nightly TTU
  solves by ~27 s/image - measured NOT in the order selection (<1 s) or the grid-indexed
  matching, but in correct_measured_positions(): the radius-annealing ladder (~44 steps)
  rescanned the whole matched pool per target star (250k targets x 44 x 4600). Fixed with
  a pixel-coordinate CSR bucket grid over the matched pool (cell = the 500 px search box,
  one query per target, candidates in DESCENDING pool order to reproduce the 501-cap
  membership); per-thread candidate buffers because this loop IS OpenMP-parallel.
  VAST_LOCAL_CORRECTION_BRUTEFORCE=1 selects the compiled backup. A/B bit-identical on
  Cas-02; corrections ~12 s -> ~1-3 s per iteration.
- TICA TESS zero-RA regression hunt (2026-07-28): the 5000-star default shifted positions
  ~1 arcsec, pushing one of two second-epoch detections of asteroid Whittemora across the
  RA=0 seam. report_transient.sh computed the mean position as a naive column mean of RA
  359.9998 and 0.0005 deg -> RA 180 (opposite sky!), so astcheck/VSX/exclusion lookups all
  queried the wrong place and the candidate silently vanished. Fixed with a wrap-aware
  recompute (spread>180 -> unwrap low side by +360, mean mod 360). Also fixed the (real
  but not causal here) raw RA subtraction in the local-correction second scan. Lesson:
  candidate-loss bugs at RA=0 can hide in POST-detection reporting statistics, not just in
  matching; grep for naive RA means/diffs when touching anything near the seam.
- Wrong-field vs cleanup-crash disambiguation (2026-08-18): VaST prints 'Done with
  measurements! =)' even when it then deliberately exits 1 with 'Low percentage of matched
  images' (<75% of input images matched, end of main() in src/vast.c). Any wrapper heuristic
  keying on 'Done with measurements' alone will mislabel genuine wrong-pointing/clouds
  failures as the dense-field cleanup crash - check the 'Low percentage' marker FIRST
  (transient_factory_test31.sh now does). On such a matching failure the factory now
  blind-solves one second-epoch image (once per field) and prints the standard 'Angular
  distance between the image centers X.XXXX deg.' line, so the unmw summary Pointing.Offset
  column (max of awk field 7 over those lines in index.html) fills in even for failed runs
  and the Comments column shows 'telescope pointing problem?' with the offset. Worst-case
  cost on unsolvable (cloudy) frames measured at ~2-3 min per failed field: astrometry.cfg
  'cpulimit 300' caps each attempt, --depth limits quad search to ~50 brightest objects, and
  frames with <4 high-SNR detections never reach solve-field. Real-world trigger: Stas
  camera mount lost sync on 2026-08-18/19, every frame offset +4h27m/-32.7 deg from what
  the FITS headers (OBJCTRA/OBJCTDEC) claimed; blind plate solve of the actual images is
  the only way to catch this since header coordinates report the mount's wrong belief.

## sky2xy and far-off-frame positions (2026-08-24)
- A bare lib/bin/sky2xy on-frame verdict cannot be trusted for positions far from the field center: the inverse SIP polynomial can fold a position 50 deg away onto valid-looking pixels even for a GOOD plate solution (GK Per / Lac-01 incident). Verify with a forward xy2sky round trip (check_sky2xy_roundtrip in util/forced_photometry.sh, 30 arcsec tolerance) or a center + half-diagonal distance check. Fail open when the verification tooling itself fails.

## Silently failed solve-field tweak (2026-08-28)
- A wide-field WCS with CTYPE=TAN (no SIP), an exactly rigid CD matrix and CRPIX far from image center is a silently failed solve-field SIP tweak on a marginal quad match - the solution is only valid near the quad. The UCAC5 refit cannot repair it (matching is poisoned). Guard in util/identify.sh discards such solutions for FOV>5 deg and escalates to the remote plate-solve server. Do not blame image quality for the ~13"/28"-per-quadrant WCS_QUALITY_DIAG signature.

## make can leave a freshly-edited small tool stale (2026-08-30)
- After editing a one-file utility (e.g. src/ccd/split_bayer.c) while a previous 'make' is
  running or right after it, a subsequent plain 'make' can SKIP recompiling that target:
  a build step sweeps mtimes so the old binary ends up a few ms newer than the source, and
  the hardcoded 'clean' rm list only removes the tools it knows about, so a new target is
  not force-rebuilt the way the sibling ccd tools are. Symptom: the binary keeps old
  behavior after a successful 'make' (here: a fixed buffer overflow kept aborting).
  Fix: rm the binary and re-run plain 'make' (never compile components manually into the
  tree); verify with md5sum that the binary actually changed. Consider adding new tools to
  the clean list.

## Seestar S50 Bayer photometry prototype (2026-08-30)
- util/ccd/split_bayer (src/ccd/split_bayer.c) splits a Bayer FITS into R/G/B superpixel
  images; util/seestar_photometry.sh runs the full APASS-calibrated multi-aperture pipeline.
  The GRBG BAYERPAT of the Seestar is correct in FITS storage order (verified empirically
  via color-slope signs d(Binst-Ginst)/d(B-V)>0, d(Rinst-Ginst)/d(B-V)<0).
- The GAIN=80 keyword of ZWO cameras is a gain SETTING, not e-/ADU - never pass it to
  SExtractor; the script estimates an effective gain from sky stats instead.
- APASS DR9 is unreliable brighter than V~10 (saturation); expect bright-end residual
  trends in B and V that masquerade as slope!=1 in catalog-vs-instrumental fits.

## Seestar G-channel bright-star deficit is mostly instrumental (2026-08-31)
- Direct Tycho-2 V cross-check (G:TycV band in util/seestar_photometry.sh) shows the
  bright-end negative residual trend of the G channel persists against Tycho-2, only
  0.05-0.08 mag smaller than against APASS: at the 2.5 superpix aperture V=9-10 stars
  are -0.30 (Tycho) vs -0.38 (APASS), V=10-11 -0.19 vs -0.24. So APASS bright-end
  saturation contributes only ~0.05-0.08 mag; the dominant cause is real bright-star
  flux outside small apertures (wing bloat). Doubling the aperture recovers about
  half the deficit; even at 38 arcsec V=9-10 stars stay ~ -0.17 vs Tycho-2. Treat
  V<~10 G-channel photometry on 5 s Seestar frames as systematically uncertain at
  the 0.1-0.3 mag level whatever the catalog; the wing-excess aperture switch is
  the mitigation, not a slope fit.

## Transient factory run outcome: exit code is not a status (2026-09-09)
- Field-level ERRORs in util/transients/transient_factory_test31.sh never change the
  exit code: every such site ends in continue/break and the script falls off its
  cleanup loop, so it exits 0 (46,919 of 46,922 production runs). unmw's
  autoprocess.sh gated the monitoring ingest on the exit code only, so rows from
  runs with ERROR lines were ingested and published. The only persistent record of a
  run's outcome is results_<ts>_<upload>/index.html with both logs embedded; the
  nightly summary (combine_reports.sh) defines "error" as a plain grep for ERROR in
  that file. The source-monitoring block sits AFTER the SExtractor-config loop inside
  the field loop, so continue/break sites of the inner loop (low-match VaST exit,
  unsolved plate, pointing, magnitude calibration) still let it measure.
- Fix applied: the block now greps the current field's section of the filtering log
  (line count captured at the field start, tail -n +N) for ERROR before measuring,
  and autoprocess.sh greps ERROR in the report before ingesting. Any ERROR counts,
  no fatal/non-fatal distinction, no pattern list. Every banner in transient_factory.log
  has a paired ERROR line in transient_factory_test31.txt, so the filtering log alone
  is sufficient. Not covered: the manual backfill (--reconcile/--rescan), and cloudy
  frames from runs without any ERROR line (the U Gem 2026-08-25 case).
- Frame-edge margin for monitored sources (2026-09-10): util/forced_photometry honours
  FORCED_PHOTOMETRY_EDGE_MARGIN_PIX (default 0 = only the sky annulus must fit, i.e.
  five aperture diameters) and reports closer positions as 'edge'. The factory sets it
  from MONITORING_EDGE_MARGIN_PIX (default 100) for its list-mode call, and the unmw
  backfill passes the same-name local_config.sh setting through the subprocess
  environment; util/forced_photometry.sh needs no change because the variable passes
  through it. Verified on a 9576x6388 frame: 50/76/88 px from an edge -> edge, 150 px
  and the centre -> measured; unset/empty/negative -> unchanged output.

## Astrometric residual plots can show stale mismatches after a SIP refit (2026-09-10)
- The <image>_astrometric_residuals.png in a results dir is drawn from the FINAL solve
  (after the WCS_QUALITY_RETRY tweak-order-2 re-solve and VaST's own SIP refit): the
  star count in its title equals the last SIP_REFIT/WCS_QUALITY_DIAG N_match. But when
  the refit is applied, solve_plate_with_UCAC5 recomputes the star positions from the
  refit model and keeps the catalog partners assigned by the earlier matching pass with
  the pre-refit WCS (no re-match). Stars mismatched in a region where the initial
  solution was badly off then show tens-of-arcsec "residuals" although the header is
  right. Seen on Lac-01-Q2 2026-08-16 (initial solution 25-28 arcsec off in the left
  quadrants): plots show a far-left strip of 20-175 arcsec outliers, yet the final
  header puts bright stars at X<600 within 0.9 arcsec (median) of Tycho-2, the same as
  the frame centre, and agrees with the reference-frame WCS to <1.5 px. Check the
  header directly (xy2sky + Tycho-2, or a pixel grid mapped onto the reference WCS)
  before believing an edge strip in the plot. A re-match after the refit, before the
  residual file and the DIAG line are written, would remove the artefact.
- Implemented 2026-09-10 (post-refit catalog re-match in main() of
  src/solve_plate_with_UCAC5.c): when the SIP refit is applied, the match flags are
  cleared and the catalog dispatcher runs once more at the refit positions with a
  radius of 5x the refit robust rms (floor 3 arcsec, cap = second-step radius); a
  second refit on the new pairs is accepted if not worse than the first; the local
  position corrections are recomputed; on a failed re-match or a collapsed pair count
  the saved pairs are restored (struct detected_star_match_backup) with a warning.
  VAST_SIP_REFIT_NO_REMATCH disables it. Cost with the local UCAC5 copy: ~3 s for the
  catalog pass + <1 s refit + corrections (measured on a 9576x6388 TTU frame); remote
  catalogs pay one more query of up to 5000 positions, same as one existing iteration.
  Lac-01-Q2 A/B (same astrometry.net start): residual file outliers >10 arcsec
  153 -> 0, worst-quadrant robust rms 0.709 -> 0.656 arcsec on identical pairs,
  header vs Tycho-2 at X<600 2.08 -> 1.96 arcsec median (centre unchanged). The header
  itself moves little when the first refit was already well anchored; the gain is honest
  pairs/diagnostics and real anchors where the initial solution was badly off. Observed:
  the 5% worst-quadrant gain rule for order 5 rejected a 3.5%-better order-5 trial here.

## astcheck segfault (exit 139) from parallel candidate checks (found + fixed 2026-09-21)
- Symptom in the transient report: "ERROR: astcheck failed to run (exit code 139)" for some
  candidates of one field while others in the same field are fine; the same MPC line runs
  cleanly when re-run alone. 139 = SIGSEGV, not "no asteroid found".
- Cause: make_report_in_HTML.sh runs up to REPORT_MAX_THREADS (5) report_transient.sh jobs
  in ONE working directory; each runs lib/astcheck, which caches per-day asteroid positions
  in the cwd as YYYYMMDD.chk (16-byte header + n*4 bytes) and curr_unc (n*2 bytes, no
  header). unmw rsyncs a fresh VaST copy per field with no cache, so all 5 jobs race to
  create it. The vendored code wrote the files non-atomically and read them unchecked
  (fread results ignored, fopen("curr_unc") used without a NULL test): a reader that saw
  a half-written .chk or no curr_unc yet crashed. Reproduce deterministically: keep a
  valid .chk and delete curr_unc, or truncate the .chk -> exit 139.
- Fix in src/astcheck/astcheck.cpp (get_cached_day_data + write_cache_file_atomically):
  temp file + rename() (curr_unc first, then .chk), every fread/fopen checked, fallback
  to compute_day_data() when the cache is unusable, unwritable cache = stderr WARNING.
  Cache file format unchanged (old and new binaries accept each other's files).
  The temp names are YYYYMMDD.chk.<pid> / curr_unc.<pid>; only a kill between fopen()
  and rename() leaves one behind, and util/clean_data.sh now removes those too.
- Before 2026-06-08 (commit 80f5aee1) a crashed astcheck was reported as "not found in
  astcheck", i.e. a real asteroid could pass as a new transient. Since then it is a red
  ERROR in the report; 2 field runs out of ~50000 archived on tau showed it.
- astcheck.cpp has CRLF line endings; edit it with a script that preserves them.
- When comparing astcheck outputs between runs, drop the "ASTCHECK version <build date>"
  and "Run time:" lines first.

## test_vast.sh on tau is not hermetic: host calibration and leftover fd_ frames (2026-09-24)
- util/transients/transient_factory_test31.sh picks NMW_CALIBRATION from a fixed list
  ($HOME/nmw_calibration, /dataX/..., /home/apache/..., /var/www/nmw_calibration; the
  environment cannot override it). On tau it finds /home/kirx/nmw_calibration, so for the
  TTU/STL/Stas cameras the factory dark/flat-calibrates RAW test frames and also swaps in
  tau's bad-region lists and neverexclude_list.txt. GitHub runners find nothing and process
  the raw frames. A tau pass therefore does not predict CI for factory sections on raw data.
- The calibration writes d_/fd_ frames into the INPUT (dataset) directory, and nothing
  removes them for test paths (the test wrapper deletes only *.cat). On the next run any
  fd_*/wcs_fd_* file sets CALIBRATION_STATUS_PREFIX, the raw frames are ignored and the
  stale calibration is reused. check_transient_factory_wcs_leak_in_input_dir() only sees
  wcs_*.fits(.fz) and is blind to these, and to all .fts datasets.
- Example: SGR04NOVA_NOVA_NOT_FOUND failed on every CI runner and passed on tau. The raw
  _0000 frame does not yield the nova at DETECT_THRESH 2.0 at all; the calibrated one gives
  SNR 4.87. Raw-frame SExtractor catalogs are bit-identical between tau and CI, so it was
  never a CPU/build flip. To emulate CI on tau, point the factory's calibration search list
  at nonexistent paths in a THROWAWAY copy (HOME alone is not enough: /var/www/nmw_calibration
  is a symlink to the same dir).
- A catalog needed by an early test_vast.sh section must be downloaded before that section:
  on GitHub Actions the database query section ('lib/update_offline_catalogs.sh all') is
  disabled, and the first download there is the 'force' call thousands of lines later.
- Reproduction sandboxes: never put a VaST copy under a path containing "lib/" or "util/"
  (e.g. /tmp/vast_repro_calib/vast). src/get_path_to_vast.c removeSubstring() strips EVERY
  such substring from /proc/self/exe, so the tools chdir() to a wrong, nonexistent path.
