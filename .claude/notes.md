# VaST Maintenance Notes

Notes on things that work and don't work when maintaining VaST code.
Update this file as you learn new things.

## Git Workflow

- Tracked in git from the `.claude/` folder: `CLAUDE.md`, `notes.md` (this file) and the design docs
  `airmass_zeropoint_forced_photometry_design.md`, `forced_photometry_reference_filter_design.md`
  and `nearby_red_dwarf_check_design.md` (tracked scripts cite them by their `.claude/` path, so do
  not move them). Stage them when they change.
- `.claude/` stays in the repository but not in release archives: the release workflow
  (.github/workflows/create_release_archive.yml) leaves it out of its rsync copy, and
  .gitattributes marks it export-ignore for git archive and GitHub's 'Source code' downloads.
  Code comments in the scripts cite the design docs by their .claude/ path only, so a tarball
  user has to look them up in the GitHub repository.
- Keep temporary investigation reports, session notes, deployment checklists and handoff documents
  outside the repository tree; never stage or commit them. Keep durable lessons in this consolidated
  maintenance-notes file instead (user preference, 2026-10-10).
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
- **Never use `gawk`** (the command or its extensions) - write POSIX awk that works with gawk, mawk,
  BSD awk and busybox awk alike (next section)

## awk portability (gawk, mawk, BSD awk, busybox awk)

Every script that uses awk - shell scripts, and awk commands that C code runs through system() -
has to work with all four: gawk (Gentoo/tau, Fedora/RHEL; Scientific Linux 5.6 has gawk 3.1.5),
mawk (the default awk of Debian and Ubuntu), BSD awk (the one-true-awk of macOS and FreeBSD) and
busybox awk (Alpine). Consider it for every awk line written or reviewed, not only when something
fails: the failures are often silent (empty output, a check skipped without a message), and tau
has only gawk.

Traps:
- A comparison in a print or printf argument list. mawk takes '>' there, also the one of '>=',
  for output redirection, and POSIX allows no unparenthesized comparison in a print list. Write
  printf "%d", (a >= 20), or better compute the value with if/else first. gawk --posix and
  gawk --lint both accept the bad form, so they do not catch it (the bright-star mask of
  2026-11-23, see the APASS section below).
- A print list that starts with a parenthesis followed by more expression - print (a) - (b),
  print (c) ? x : y - can be read as the parenthesized print (expr_list) form: assign to a
  variable first, then print it.
- gawk-only features: gensub, asort, asorti, strftime, systime, mktime, patsplit, length(array),
  IGNORECASE, PROCINFO, FPAT, FIELDWIDTHS, RT, BEGINFILE/ENDFILE, @include, switch, |&, ** (use
  ^), and the regex escapes \y \< \> \s \w. Count array elements yourself.
- Regex interval expressions {n,m}: missing in mawk 1.3.3 (Debian 10, Ubuntu 18.04) and off by
  default in gawk 3.x (Scientific Linux 5.6). Write the repetition out. In a regex passed as a
  string, prefer a bracket expression ([.]) to an escaped character ("\\.").
- No space between the name of a user-defined function and "(" in a call: f(x), not f (x).
- Numbers are doubles: integers above 2^53 lose digits (on 2026-11-23 every Gaia source_id
  4000000000000000000 + k came out as the same number). Keep such identifiers as strings and
  print them with %s; old mawk (1.3.3) also clips %d at 2^31-1, so use %.0f or strings.
- The awks differ in turning strings like nan, inf or 0x10 into numbers (gawk gives 0, an awk
  that uses the C library strtod may accept them): validate numeric input with a regex, as
  lib/photometric_field_catalog.sh does.
- An exit in END replaces the exit status of an earlier exit (all awks, POSIX): set a flag
  and decide in END.
- -v var=value processes backslash escapes: pass paths or regexes with backslashes through
  ENVIRON.
- RS longer than one character is an extension (RS = "" for paragraphs is POSIX). Start
  substr() at 1. split(s, a, "") into characters is undefined in POSIX.
- awk output into a pipe is block-buffered (notoriously by mawk): call fflush() where another
  process has to see the lines as they come.
- Run awk with LC_ALL=C, as VaST scripts do: character classes, ranges and length() then work
  on bytes in all four.

Checking:
- gawk --posix rejects gawk extensions (gensub, asort, length(array), ** ...) and warns about
  \y; gawk --lint reports, among other things, a space before "(" in a function call. Neither
  catches the print/printf comparison trap or {n,m}.
- Run the program with the other awks where possible: mawk and original-awk (the one-true-awk)
  are Debian/Ubuntu packages, busybox awk is "busybox awk", and macOS and FreeBSD have the
  one-true-awk as /usr/bin/awk. On tau only gawk is installed (2026-11-23), and docker run fails
  there.

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
  (works with gcc 11; gcc 14 needs `CC='gcc -std=gnu89'` because the build-helper programs
  do not get CFLAGS), then run `./bash -n` on the scripts and run suspicious snippets with it.
  The official Docker image `bash:3.2.57` is the same GNU bash (built on musl).
- `bash -n` coverage: bash 3.2 and 5.1 do NOT parse the bodies of `$( )` / backticks / `<( )`
  (a syntax error inside one surfaces only at run time); bash 5.2 does. A `case` inside a
  DOUBLE-QUOTED "$( ... )" even passes 3.2 -n and then silently runs a truncated command.
- shellcheck cannot target a bash version and passed the broken test_vast.sh; BASH_COMPAT=32
  in a modern bash does not reject bash-4 syntax either.
- CI guard (2026-09-24): the `bash32compatibility` job in build_and_test_ubuntu.yml runs
  `lib/check_bash32_compatibility.sh <bash 3.2>` on every push to master, in parallel with the
  long jobs. bash 3.2 comes from the official Docker image bash:3.2.57 pinned by digest (with
  public.ecr.aws and mirror.gcr.io fallbacks for the same digest). The script runs bash 3.2 -n
  and the runner's bash (5.2) -n over all tracked shell scripts outside src/, plus an awk lint
  for bash 4+ features that 3.2 parses but runs differently (quoted '/' in ${VAR//pat/rep},
  case inside "$( )", declare -A, ${v,,}, wait -n, ...). A line that is safe (e.g. guarded by
  BASH_VERSINFO) is silenced with a trailing '# bash32-ok: reason' comment. Run it locally with
  a self-built bash 3.2: `lib/check_bash32_compatibility.sh /path/to/bash-3.2.57/bash`.

## Remote plate-solve WCS download (util/identify.sh, 2026-09-24)

- curl without --fail saves an HTTP error page (or a file the server is still writing) and
  exits 0. On 2026-09-24 tau.kirx.net solved c176.fits but the client got 341 bytes that
  were not a FITS header; insert_wcs_header failed and identify.sh did `exit 1` without
  trying the other server (the 'many hot pixels' test failed). wcs_header_file_looks_valid()
  now requires 'SIMPLE  =' and a whole number of 2880-byte blocks (cfitsio rejects anything
  else); an invalid download is fetched once more, then the next server is tried. Anything
  echoed from a server reply must be sanitized (printable ASCII, no '<>' tags, no 'ERROR')
  because identify.sh output can end up in index.html.
- Known leftovers (not fixed): ERROR_STATUS=2 carries into the next field-of-view trial, so
  with a single reachable/forced server the later trials skip it; failed jobs are not removed
  from the server (remove_job.py) on the `continue` paths.
- lib/bin/xy2sky (bundled WCSTools 3.9.7) segfaults when the input file does not exist.

## `grep -C 'fd_'` typo disabled a test check for 3 years

- test_vast.sh NMWCALIB0_no_calibration_in_filename used `grep -C` (context) instead of
  `grep -c` (count) from 7abbf3ca (Dec 2023) until 2026-09-24: grep failed, N was empty and
  `[ $N -ne 2 ]` errored, so the check never fired. When a check compares an unquoted
  variable with -ne/-eq, a broken producer makes the test silently pass - look for
  'unary operator expected' in test_vast.sh output. N=2 comes from the two NMW SExtractor
  passes, each appending vast_summary.log ('Last  image:') to the report.
- Never edit util/examples/test_vast.sh in place while a test_vast.sh run is using it (bash
  reads it incrementally through fd 255). Replace it atomically instead: `cp` the new version
  to a temp file in the same directory, then `mv` it over the original. The running bash keeps
  reading the old inode.
- shellcheck on the whole 36k-line test_vast.sh gets OOM-killed on a 15 GB machine. Check the
  edited sections by extracting them into a separate file with a bash shebang.

## C Code

- C89/C90 style required: all variables declared at the very start of the function, before any executable statements
- `lib/check_no_for_loop_initial_declaration.sh` (run by `make`, GNUmakefile 'all' target) fails
  the build on any `for (int i ...` / `for (size_t ...` in a .c file below the VaST root and
  prints every finding. Until 2026-09-24 it always exited 0 (its failure flag was set inside a
  `find | while` subshell). Known exceptions, allowed by path in is_allowed_exception(), are
  bundled third-party files VaST does not compile: src/cfitsio-*/utilities/iter_image.c,
  iter_var.c and src/zlib-*/examples/enough.c. If a library upgrade adds such loops to code
  that IS compiled, fix that code (gcc 4.1 gnu89 rejects it) rather than adding an exception.
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
- Whitelisting is for messages a DATASET legitimately triggers. A message triggered by the
  host environment (an optional catalog that no source can deliver, a mirror outage) must not
  be an ERROR at all: since 2026-09-09 any ERROR line in index.html is a run status (unmw
  combine_reports.sh marks the field red and shows the FIRST ERROR line; autoprocess.sh skips
  the monitoring ingest). 'ERROR: ASASSN-V catalog ... is missing or empty' failed the VENUS,
  NMWCALIB and STEREOA sections on the macOS runner on 2026-09-19, when the kirx.net mirror
  served a 643888-byte stub that the 100 MB floor (8b776fbd) rightly refused. It is now a
  WARNING; test_vast.sh records the missing catalog as the informational code
  ASASSNV_CATALOG_UNAVAILABLE (not counted in the exit code). Do NOT repeat such a notice at
  the end of the report: unmw combine_reports.sh shows only the LAST WARNING line of a field,
  so a repeated catalog notice would hide field-specific warnings for the whole outage.
  stderr of lib/update_offline_catalogs.sh reaches index.html too (make_report_in_HTML.sh,
  and the system() call in check_catalogs_offline), so its failure messages use
  CATALOG_FAILURE_LEVEL: WARNING for an optional catalog and for a failed refresh of a
  required catalog whose installed copy is kept; ERROR only when a required catalog is
  missing or unusable.

## Candidate HTML report block parsers (must not break when changing report output)

- The per-candidate <pre> block "The object was found in X" lines are parsed by: unmw/filter_report.py (is_variable_star reads the FIRST token of the line RIGHT AFTER the sentinel line as the match distance; _extract_crossmatches keys on the regex 'The object was (found|not found) in X'), unmw/autoprocess.sh (grep -A4 ... | grep -c 'not found'), transient_factory_test31.sh (grep -A10 "$RADECSTR" ... | grep 'astcheck' | grep 'not found'), make_report_in_HTML.sh (grep -A1 of the exact VSX found string -> variable name from the next line), util/artificial_star_test_for_transient_search (awk '/not found/ && /VSX|ASASSN-V|astcheck/'), util/search_databases_with_vizquery.sh (grep -A 1 '#   Max.' -> record line).
- Therefore: new information lines must be APPENDED AT THE END of a match block, and must never contain the substrings 'The object was', 'found in' or 'not found'. The large-mag-difference ATTENTION lines use the stable marker substring 'mag brighter than the' that unmw/filter_report.py keys on (LARGE_MAG_DIFF_MARKER) - keep it verbatim in all three producers (search_vsx, search_asassnv in check_catalogs_offline.c, and MPCheck_v2.sh).

## test_vast.sh flag-image greps and PSF sections

- lib/autodetect_aperture_main in STANDALONE mode names its temp files image_pid<PID>.* (not image00000.*). Test assertions must grep 'FLAG_IMAGE image' + '.flag', never the literal 'FLAG_IMAGE image00000.flag'. The non-PSF exclude-ref-image section was updated for this long ago; the PSF variant (EXCLUDEREFIMAGEPSF006) and the photographic-plates check (PHOTOPLATE, inverted logic) still had the old pattern - fixed 2026-07-03.
- The PSF test sections only run when psfex is installed; PSFEX_NOT_INSTALLED is auto-stripped from FAILED_TEST_CODES. psfex appeared on this dev machine only on 2026-06-15 (/usr/local/bin/psfex 3.24.2), so PSF sections had not run here for a long time - expect stale assertions when a new tool enables a long-skipped section.
- To edit a test script WHILE the suite is running from it: cp to a temp file, edit the copy, bash -n, then mv over the original (atomic rename). The running bash keeps its fd on the old inode and is not disturbed. Never edit the file in place mid-run.
- The '###### X ######' header that a failed check adds to DEBUG_OUTPUT must name the code that
  the same check adds to FAILED_TEST_CODES, since the report is read by searching for the code.
  A block copied from a neighbour tends to keep the neighbour's header: nine position checks of
  the NMWNSGR20N4, NMWNSGR24N1, NMWNSGR21N2 and NMWNSGR21N1 sections were reported under the
  first check's header, the failed TICA selenium test under
  TICATESSZERORA_ERROR_MESSAGE_IN_index_html, and ten X_ERROR_MESSAGE_IN_index_html failures
  under X_NO_ERROR_MESSAGE_IN_index_html (all fixed 2026-11-16, with a few more). To find such
  slips, compare each header with the nearest FAILED_TEST_CODES addition above it.
- Every check also needs a code of its own, or a failure cannot be traced to its check. Copied
  blocks kept the codes of their neighbours: COLSTAT_MIN on the MAX, MEDIAN and MEAN checks, the
  second sysrem2 pass reusing NMWSYSREM007 and 102-106, valgrind runs of other programs reusing
  SPECIAL_VALGRIND017/018 and 026-028, the MASTER PSF section adding the small-CCD PSF
  section's SMALLCCDPSF_EMPTYPSFFILTERINGLOFGILE_$LOGFILE_TO_CHECK, and about twenty more (all
  renamed 2026-11-16; the second sysrem2 pass now uses 107 and 202-206; in the exclusion-list
  test the star-name checks of the commented list use 105-107 and the list with stray comment
  lines 201-207). DISKSPACE_TEST_ERROR stays shared on purpose: both disk-space helpers parse
  the same df value. To find duplicates, list the static codes that occur more than once and
  compare the static prefixes of the codes that end in a variable.
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

## solve-field silently keeps a TAN-only solution on wide fields; cure = --verify on the star list (2026-10-01)
- Signature: a wcs_ header without A_ORDER on a >5 deg field, CRPIX off centre, and in the
  solve-field log "fit-wcs.c:118:fit_sip_wcs: Too few correspondences for the SIP order specified
  (5 < 6)" right before "solved with index index-4116.fits". The tweak uses only the stars of the
  index that held the matching quad; a coarse index (4116+) has a few dozen stars in a 15 deg
  frame, and when the quad verifies with only ~8 of them the SIP fit gives up. The result is
  accurate near the quad and 10-30" off at the far corner (one quadrant loses half of its
  UCAC5 matches -> the "large change in astrometric-star counts" ERROR). Deterministic for a
  given star list: the retry with another tweak order and the remote server (same solve-field,
  same list) return the identical header. Excluding the coarse index files does NOT help - the
  tweak then fails on a finer index too ("2 < 3"). Case: Cas-04-Q2b1x1 0094, 2026-09-30.
- What works: `solve-field <xyls> --verify <tan.wcs> --tweak-order 3 --objs 10000 ...` on the
  star list - it verifies the solution against ALL index files and re-tweaks with the best one
  (176/179 stars of index-4113 here), 2-17 s. Now in util/identify.sh as
  star_list_verify_retweak(), run when the TAN-only guard fires, for local and remote results.
  The image-based form (--fits-image) is slow and skipped under solve_plate_with_UCAC5.
- The UCAC5 refit judges a candidate on the pairs made through the OLD solution; wrong pairs
  in the bad quadrant inflate the worst-region metric (69") even when the fit is 0.5" overall,
  so the refit was refused. src/solve_plate_with_UCAC5.c now rescues that case (overall RMS
  < 0.5 px while the kept baseline is > 1 px): provisional apply of the lowest order that fits,
  re-match, second refit, keep only if it beats the baseline (SIP_REFIT_RESCUED line), else the
  backed-up header/.wcscat/star array are restored and SIP_REFIT_REJECTED is printed as before.
- The plate-solve CGI (process_sextractor_list.py, deployed by hand on tau and scan, not in
  git) needs the same --verify step after its hinted pass; prepared copy:
  /home/kirx/vast_test/process_sextractor_list.py.verify_retweak.
- Reproducing a plate solve offline: SExtractor with default.sex.telephoto_lens_onlybrightstars_v1
  and the six VaST apertures (-PHOT_APERTURES A,A,0.9A,1.1A,1.2A,1.3A - with one aperture
  make_outxyls_for_astrometric_calibration rejects every line), then
  lib/make_outxyls_for_astrometric_calibration cat out.xyls W H, then solve-field with the
  options from identify.sh; --out <base> keeps the input .wcs intact.

## Run verdicts for the manual monitoring modes; frame-level forced photometry checks (2026-10-02)
- Case: GK Per got clearly wrong upper limits from Per-02-Q1b1x1 frames 0111/0112 of
  2026-09-17 (cloudy). The factory raised ERROR on that field and refused to measure,
  autoprocess.sh did not ingest - but a later manual --reconcile/--rescan-recent found the same
  wcs_ frames in the img_* directory and measured them: the manual path had no run-status gate.
  The 2026-10-01 --reconcile leaked 12 more rows the same way, 4 of them from runs killed by
  the power outage (their reports have no ERROR line, only no "Processing complete!").
- Verdict store (unmw): autoprocess.sh appends one line per image of the upload to
  $IMAGE_DATA_ROOT/transient_search_verdicts.txt - "pending" right before the factory starts
  (wcs_ frames appear in the img_* dir mid-run), then ok/error/failed. Key = uploaded frame
  name without wcs_/fd_/d_ and .fz, so the uploads, quarantine and archive copies all find it;
  the newest line wins (reprocessing). Legacy fallback for older images: the newest report of
  the run, found via the img_* name (results_* dirs stay in the workdir after the img_* dir moves
  to quarantine; reprocess runs are results_<ts>_reprocess_img_<name>_<pid>[_<rand8>]) or, for
  archive copies, via <frame>_preview.png in the run's results dir. About 11% of archive frames
  come from rejected runs, so "the archive is vetted clean" does not hold for run status.
  Manual modes: rejected -> run_error ledger row without measuring, pending -> skip.
  The factory's refusal branch now writes run_error raw rows itself, and autoprocess.sh calls
  `monitoring_update.py --ingest-rejected` for any non-ok run (the ledger then records the
  images as processed and rejected). A run_error row is replaced only by --ingest of a later
  successful reprocessing run.
- Details that came out of the review: a manual run follows the verdict list as it grows (it
  can last hours while uploads are processed); a successful run's "ok" is appended only AFTER
  its own monitoring ingest (until then "pending"), else a manual rescan could measure the
  frames first and bypass the ingest's frame-quality check; a later run that failed or never
  finished does not override an earlier ok/error verdict of the frame; a rejected run's plate
  solution is not trusted for on/off-frame decisions, so off-frame positions get NO row (never a
  permanent 'edge') in the factory refusal branch and the manual path; sky2xy says "off image"
  for every position on an fpack-compressed (.fz) file; results_* dirs also hold previews of
  their REFERENCE frames, so the archive-copy match checks fits_images_for_download.txt.
- Frame-level checks of util/forced_photometry are OPT-IN (FORCED_PHOTOMETRY_FRAME_CHECKS=yes),
  set by the factory monitoring block and by unmw's run_forced_photometry_c. Default-on would
  have changed report_transient.sh's reference-image filter (a TAN-only reference turns the
  filter off for the whole field; no_nearby_stars makes it ignore a reference measurement)
  and util/seestar_photometry.sh (it tells failures by mag 99.0000 while the new statuses keep
  the measured magnitude). util/forced_photometry.py does not implement them.
- no_nearby_stars calibration (797 TTU frames, last-pass catalogs, grid >= 100 px from edges):
  clean frames never had fewer than 7 stars within 0.5 deg (2.9 million positions, 140 frames at
  alt < 30 deg with the Moon up included), cloudy frames had 0.16% of positions with < 3. A
  ratio-to-frame-median test was REJECTED: clean Milky Way frames have 20x real density contrasts
  (dark nebulae; r_min down to 0.047), which would refuse a source in a dark cloud on every frame.
  The gate uses the frame's MEAN cell density: the median collapses to 0 when clouds cover more
  than half of the frame and switched the test off on the cloudiest frames (found in review).
  Shallow catalogs (the brightest stars only) have clean-frame circles with < 3 stars; at the
  mean-density gate 30 six such positions were refused, at 40 none -> MIN_EXPECTED 40. With the
  deep catalogs no clean position had < 3 stars at all, so the gate only matters for shallow
  catalogs. The img_*/<frame>.cat files are the LAST SExtractor pass (vSTL / vTTU on TTU), the
  same catalog depth the monitoring callers see as .wcscat. A NaN or 1e30 X/Y in the catalog
  used to index the density cells out of bounds (segfault) - now skipped when loading.
- Test: util/examples/test_forced_photometry_frame_checks.sh (no network, synthetic catalogs,
  TAN-only copy of the Sgr-05 test image; 6 s), called from test_vast.sh.
- Pitfalls met on the way: bash reads a running script incrementally - editing
  util/forced_photometry.sh while a run was in progress produced a bogus "syntax error near
  unexpected token" at a random line (bash -n on the file was fine). lib/astrometry/strip_wcs_keywords
  keeps the old values as _TYPE1/_TYPE2 cards, so "grep TAN-SIP" still matches a stripped header.
  In the Claude Code shell on tau, grep is a shell function that runs ugrep (scripts use GNU
  grep): a pattern that GNU grep matches may not match there.

## SExtractor 2.25.2 never built on tau; fixed with one mtime per source tree (2026-10-03)
- lib/compile_sextractor.sh touched aclocal.m4/configure/Makefile.in BEFORE m4/*.m4 (and never
  man/Makefile.in). On btrfs with sub-second mtimes GNU make 4.4 then found m4/*.m4 newer than
  aclocal.m4 and re-ran the exact automake version the shipped files came from
  ('autoconf/missing aclocal-1.16'); Gentoo has only automake 1.18, so Error 127 (Makefile:469),
  and the script silently fell back to sextractor-2.19.5. EVERY tau build since at least
  2025-12 (all production reports with a version line) used 2.19.5. Ubuntu CI (automake 1.16.5
  regenerates the files), FreeBSD and macOS built 2.25.2; WSL2, Docker and Alpine fell back.
- Fix: set_the_same_mtime_for_all_files_in_source_tree() copies one reference mtime
  (touch -r) to every file of each SExtractor tree before 'make clean' in both the clean and
  build branches - equal times count as up to date for GNU and BSD make at any timestamp
  resolution, and it also repairs trees left configured by a failed build (whose 'make clean'
  hit the same Error 127). The script now prints a WARNING when it uses the fallback.
- 2.19.5 vs 2.25.2 on the TTU test frame: same detections and FLAGS, MAG_APER within 0.01 mag;
  the user chose to keep the factory's SExtractor catalog cache (2.19.5 catalogs, keyed on the
  config md5 only) rather than purge it.

## sky2xy/xy2sky segfault on unreadable, empty or non-FITS images (2026-10-03)
- The bundled WCSTools 3.9.7 tools exit 139 (SIGSEGV), not 1, when the image cannot be read.
  sky2xy.c:298 passes GetFITShead()'s NULL (open failed, or no END card in an empty file) to
  GetFITSWCS(); ChangeFITSWCS dereferences it at libwcs/imgetwcs.c:395. xy2sky's isfits() is 0
  for anything not starting with "SIMPLE", so it falls into the command-line-WCS branch with a
  NULL filename (imgetwcs.c:390, then setwcsfile() wcs.c:2478). 'sky2xy RA Dec' and
  'xy2sky X Y' with no file crash the same way. Unmodified upstream code since fcc9b22d.
- Triggered on tau by the 4962 zero-byte root:root 0600 files that a 'sudo mv' left on the full
  nmwttu2 disk (2026-09-13). util/listhead, util/forced_photometry, util/get_image_date and
  util/forced_photometry.sh fail cleanly on the same input; callers of the two WCSTools tools
  must test the exit code, because a crash prints no coordinates and looks like "off the image".
- A two-guard patch (NULL header in ChangeFITSWCS, NULL filename in setwcsfile) turns every
  such crash into exit 1 with unchanged output on valid frames; not applied as of 2026-10-03.
- lib/compile_wcstools.sh:72 and lib/compile_gsl.sh:45,64,83 test 'if [ ! $? ]', which is never
  true, so a failed make there is not reported (the later binary-exists check passes on a
  stale binary from an earlier build).

## CI run 1156 (2026-10-03): proxy error pages in test-data downloads; ESA Gaia client bugs
- tau.kirx.net is served by Apache mod_proxy on polaris.kirx.net (188.226.149.203) through an SSH
  remote forward (autossh -R8890:localhost:80, started by ~/autoconnect_http.sh). polaris keeps
  pooled backend connections after tau's KeepAliveTimeout 15 has closed them (CLOSE-WAIT sockets on
  the tunnel ssh), so a request occasionally gets polaris's 341-byte "502 Proxy Error ... Error
  reading from remote server" page. tau's own error pages end with "Apache Server at tau.kirx.net
  Port 80"; polaris's do not. Confirmed 2026-10-04: tau's access log has 200 lines for the files
  fetched just before and after the failed IOMC_2677000065 download but no line for it, and
  polaris's 'ProxyPass / http://localhost:8890/' (sites-enabled/tau.kirx.net.conf, both vhosts)
  has no ttl. The remedy on polaris is ttl=10 (below tau's 15 s keep-alive).
- 'curl -O' without --fail saves such a page under the requested name and exits 0; bunzip2 then
  prints "is not a bzip2 file." (an empty or truncated download prints "Compressed file ends
  unexpectedly" instead). In run 1156 this hit IOMC_2677000065.fits.bz2 and the test blamed the OMC
  converter (AUXWEB_OMC2ASCII2_002); run 1102 went red the same way on astorb_2023.dat.gz.
  'curl --retry' retries 5xx (curl 7.15.5 only without --fail); '--continue-at -' completes a
  leftover error page with the tail of the real file, so the file stays corrupt on later runs.
- ESA Gaia TAP: a HEAD request to /tap-server/tap/sync always returns 500 and GitHub runners drop
  ping, so the GAIADR2CLIENTS001 network diagnostics prove nothing. lib/gaia_dr2_cone_search.sh
  drops 'RPmag=a..b' ranges silently, turns an HTML error page into fake sources with exit 0, and
  never checks curl's exit status. lib/choose_gaia_dr2_client.sh probes Vega, which is not in Gaia
  DR2, so only the fake rows of an ESA error page make a probe succeed: 276 production runs in
  2026 used esa_tap exactly while ESA was serving error pages, and lost most Gaia known-star
  exclusions (3.4% vs 11.9% of runs).
- Fixed 2026-10-04: test_vast.sh download_test_data_file() (--fail, 3 tries per URL, bunzip2/gzip
  integrity test, scan.sai.msu.ru/~kirx/pub mirror) for the auxiliary web services files and the
  17 astorb downloads, with *_TEST_DATA_DOWNLOAD_FAILED codes; the client honours RPmag and exits 2
  when ESA gives no query result; report_transient.sh falls back to VizieR; the chooser probes
  Gaia DR2 3376888109148417664 and prefers VizieR; test_gaia_dr2_clients.sh exits 3/4 for an ESA/
  VizieR outage (GAIADR2CLIENTS_ESA/VIZIER_UNAVAILABLE, stripped), so GAIADR2CLIENTS001 now means
  a client failure and is no longer stripped. Keep the RPmag fix whenever the chooser may pick ESA.

## The post-refit catalog re-match must be iterated until the pair set describes the final header (2026-10-06)
- Case: NMW-TexasTech Cyg-04-Q2b1x1 frame 0078 of 2026-10-05 (results_20261005_220644_...AGVuK51D).
  ERROR "large change in astrometric-star counts between the two new images (q4: 662 -> 1036)",
  run rejected, SS Cyg monitoring rows of both frames recorded as run_error. The image was fine
  (the same field one minute earlier was clean) and the final header was sub-arcsec over the
  used frame. The raw solve-field solution was ~20" off in the upper-right; the refit was
  refused and the rescue path applied order 5 provisionally (worst region 294"), re-matched at
  3" (4284 pairs - none in the upper-right band, the provisional model diverged there) and refit
  again (0.459"). main() ran the re-match + refit cycle ONCE: WCS_QUALITY_DIAG, the residual file
  and the .wcscat.ucac5 catalog all described the holed 4284-pair set (n_q4=662), although the
  final header paired ~1040 q4 stars within 3". The same single-cycle structure bites the NORMAL
  path when the first refit still has a bad region (Cyg-06-Q2 0072 of 2026-10-01: 3965 -> 3296
  pairs, n_q3 393 vs 1420 on the sibling). Reproduced bit-for-bit offline (same quad, same
  log-odds, same header): SExtractor star list via util/wcs_image_calibration.sh with the
  camera's bad_region.lst and default.sex.telephoto_lens_onlybrightstars_v1, then
  util/solve_plate_with_UCAC5 --no_photometric_catalog --iterations 2 on the raw wcs_ state.
- Archive 2026-10-01..06 (1239 runs): 88 distinct quadrant-count ERROR events in 52 runs; 17
  (11 runs, 10 fields) have this mechanism and ALL were contradicted by the later SExtractor
  pass; 30 rescued frames in 27 runs, 11 of them raised the ERROR. Every affected run with
  monitored positions was refused.
- The second refit, fitted without the hole, extrapolates into it: the on-disk 0078 header had
  a coherent ~2" (0.35 px) offset at x>7000, y>5900 only (frame-to-frame star pairing in pixel
  space plus a local-UCAC5 match; a header-only grid comparison with a constant pixel shift is
  INVALID on these frames, the gnomonic shift varies by +-0.3 px). The x>=7500 strip is masked
  by TTUQ2_bad_region.lst and must be excluded from any such check - counting it turns a 3%
  q4 deficit into "8 arcsec, 25% paired" and a wrong refutation.
- Fix: loop the re-match + refit while the refit was applied and the re-match changed the pair
  count by more than SIP_REFIT_REMATCH_CONVERGENCE_FRACTION (0.05), cap
  SIP_REFIT_MAX_REMATCH_CYCLES (4), radius recomputed from the last applied refit, match backup
  re-saved per cycle, local corrections via recompute_local_corrections_after_rematch(). On the
  real frames: 0078 three cycles -> 4764 pairs, n_q4=1036 (= sibling), header moved 0.7-3.5"
  only in the far corner; Cyg-04-Q1 0041 four cycles -> n_q4 203 -> 1364, sigma 0.51 -> 0.36";
  Cyg-06-Q2 0072 three cycles -> n_q3 377 -> 1459. A normal frame (0079) and the Cas-04-Q2
  TAN-only test frame are bit-identical to the old code (no extra cycle, no extra cost); a
  holed frame pays 8-13 s more with the local UCAC5 copy.
- The loop alone stalls when the provisional solution is more than the re-match radius off
  over a whole quadrant: nothing pairs there, the next refit is refused for lack of coverage
  ("do not cover the frame") and the rescue outcome gate - worst-region RMS of the pairs that
  EXIST - still declared the rescue a success with a header tens of arcsec off in the empty
  quadrant (Aql-01-Q2 0052 of 2026-10-01: 166 of 385 initial q4 pairs left, header 51" off
  there, production kept it and never retried; Cyg-05-Q2 0085, Cyg-06-Q1 0038, Cas-04-Q2 0129
  with 479 of 934 q1 pairs). SIP_REFIT_RESCUE_MIN_QUADRANT_RETENTION (0.7) now refuses such a
  rescue: the original solution is restored and SIP_REFIT_REJECTED is printed with the ~20"
  baseline, which is exactly what the factory's bad-refit-baseline retry trigger (1 pixel)
  listens for. Calibration on the replayed rescues: every quadrant of a recovered frame kept
  at least 96% of its initial pairs, the unmeasured quadrants kept 23-51%.
- Not covered: the diagnostic
  pair set has a different depth after an accepted refit (3" re-match) than after a rejected
  one (46.9" initial match), a separate source of count asymmetry between sibling frames;
  stars that lose their pair keep the stale catalog_mag/catalog_ra of the initial pairing
  (pre-existing).

## The re-match loop must stop on the header, not on the pair count (2026-10-08)
- Case: NMW-TexasTech Cyg-05-Q1b1x1 frame 0037 of 2026-10-08 (results_20261008_204440_...TSZiUYxn),
  ERROR "large change in astrometric-star counts (q4: 995 -> 648)", with d5bdb823 (the iterated
  re-match) already deployed. Normal path, no rescue: the raw solve-field solution came from a
  strong index-4113 quad but was 18.5" off in the worst region; the initial matching already had
  only 609 q4 pairs; the first refit extrapolated 13-26" off in an upper-right wedge. The cycle-1
  re-match went 4169 -> 4299 pairs (+3.1%), the refit on them was applied, and the loop stopped
  because the TOTAL count had moved less than 5% - although that refit moved 9827 of 50544 stars
  by more than 1". The total stays flat because the 3" re-match drops 3-7% of the spurious
  wide-radius pairs everywhere while the repaired region gains.
- This time the saved header itself was bad, not just the diagnostic: 0.3" at the wedge edge
  growing to 6.2" (1.07 px) at the far corner, more than 1" over 41% of the wedge (pixel-space
  star pairing against the sibling frame plus local UCAC5). The later vSTL pass does NOT prove a
  header good: its worst-region figures are MAD-clipped (the deep-wedge stars are dropped) and its
  per-quadrant counts come from a catalog-only refit applied in memory to a symlinked image. A
  telltale of a stale saved header: the vSTL pass accepts such a refit (3 of 3 hole frames, 0 of
  273 other one-cycle stops in the 10-06..10-08 archive).
- Fix: after every applied refit count ALL detections (matched or not - a hole is where no
  matched star can show the shift) moved by more than SIP_REFIT_SETTLE_RADIUS_FRACTION (1/3) of
  that cycle's re-match radius; re-match again unless their number is at most
  SIP_REFIT_SETTLE_MAX_MOVED_PER_PAIR (1%) of the pair count; a refused refit stops the loop (the
  header did not change since the re-match); the cycle limit ends on a re-match without a refit.
  0037: three cycles, n_q4 1006 against 995 on the sibling, header within 0.19" of the sibling's
  everywhere (was 6.24"). Normal frames: the refit on the re-matched pairs moves stars by
  hundredths of an arcsec, so they still pay exactly one re-match - and good frames that the
  total-count rule had sent into a useless second cycle (a cycle-1 change of -5..-7%) now stop
  after one.
- The other two stale-pair cases after the deployment (rescues Lac-01-Q2 0086 of 2026-10-07 and
  Cyg-08-Q2 0063) also had wrong SAVED headers, measured against the local UCAC5 in 1200-px corner
  boxes: 0063 upper-left median 8.4" (p90 12.8") where the settled solution gives 0.65" and the
  independently solved sibling 0.74"; 0086 1.9" in both upper corners against 0.60-0.65". 0063 hit
  the four-cycle limit, but forcing eight cycles gives the identical solution (the fourth refit
  is refused), so the limit costs nothing there.
- Post-deployment audit of d5bdb823 (1265 runs 10-06..10-08 vs 1265 before): quadrant-count ERROR
  runs 4.4% -> 0.95%; 13 rescue-coverage refusals, all followed by a WCS_QUALITY_RETRY (8 repaired,
  4 genuinely unsolvable that night); no cycle-limit hits, no crashes, no solver-time rise. The
  three remaining stale-pair cases (Cyg-05-Q1 0037, Lac-01-Q2 0086, Cyg-08-Q2 0063) all took the
  cycle-1 exit. The two rescues among them passed the 0.7 coverage gate because their initial
  matching was already depleted in the hole quadrant (retention 0.78 and 0.92).
- Replaying: the img_* directories are deleted after a few days, so offline replays only work for
  recent runs. Raw state = util/wcs_image_calibration.sh on the fd_ frame with the camera's
  bad_region.lst and default.sex.telephoto_lens_onlybrightstars_v1 as default.sex; then
  util/solve_plate_with_UCAC5 --no_photometric_catalog --iterations 2. Solve-field is
  deterministic, the replay reproduces production bit for bit.

## WCS retry keep rule and the absolute worst-quadrant ERROR (2026-10-09)
- Case: NMW-TexasTech Her-09-Q1b1x1 2026-10-08 (results_20261008_220920_...XxnKXyJs). The
  factory's tweak-order-2 retry kept the re-solve of frame 0113 as "improved" because sigma*ratio
  went 27.55 -> 27.48 arcsec, while the overall sigma went 5.925 -> 15.191 and the matched stars
  1990 -> 1673. sigma*ratio IS the worst quadrant's sigma (print_wcs_quality_diagnostic() divides
  the largest quadrant sigma by the overall sigma); when one quadrant is broken in both solutions
  it saturates near the matching radius and the comparison is noise. The log printed only the
  overall sigma, so "improved" sat next to a sigma that nearly tripled.
- Archive check before choosing the rule (233 retry decisions 2026-09-01..10-09): a 10% margin on
  the score is WRONG - it flips 16 decisions and discards real partial repairs (For-04-Q1 09-21
  0254 improved all four quadrants yet raised sigma 1.34x because 201 more stars were matched in
  the broken quadrants; also For-04-Q1 0454, Cnc-02-Q1 0410, Lyn-02-Q1 0345). "Sigma must not
  rise", a geometric mean of the quadrant sigmas and a per-quadrant star-count guard are wrong for
  the same reason. Chosen: keep only if the worst-quadrant sigma falls AND the overall sigma does
  not double, unless the new sigma is inside the floor. It changes exactly the two Her-09 decisions
  (10-06 0104, 10-08 0113), both for the better; the largest rise among the other keeps is 1.344x.
  A NaN re-solve diagnostic now reverts (awk read NaN as 0, a perfect score).
- The keep fix alone would have REMOVED the only ERROR of the Her-09 run: with 0113 reverted both
  frames are equally bad, and the quadrant-count check compares the two new images with each other.
  So report_new_image_bad_worst_quadrant() raises an ERROR when a new image's final worst quadrant is
  above one pixel (TTU cameras only, like the count check). Over the 2026-09..10 archive it fires on
  16 runs, all with retried frames; no frame that was not retried ended above one pixel; 5 of the
  16 runs had no other ERROR. util/examples/test_wcs_quality_retry.sh (standalone, not in
  test_vast.sh) pins all of this with real numbers: 32 cases.
- Her-09-Q1 itself was a bad RAW plate solve, which the settle rule cannot touch: identify.sh's
  hinted pass (--radius = FOV major axis, 15.5 deg) accepted a marginal quad from index-4115 (quads
  340-480 arcmin, 8 index stars, anchored at the left edge), the SIP tweak failed (TAN-only, rotated
  ~1.5 deg) and the star-list re-tweak failed too (5 stars). The star list was fine (stars in all
  quadrants) and the field solves to 0.3 arcsec on other nights. The same pass with --radius 2 found
  index-4113/4112 quads with 189-366 index stars (raw 1.0-1.4 arcsec vs UCAC5) on all three bad
  frames (0112/0113 of 10-08, 0104 of 10-06), but failed to solve 5 of 16 ordinary frames at
  --depth 100 - usable only as a fallback. At that point the TAN-only guard had not escalated to
  the remote solver since ca23497b; 1a8c12b2 fixes that and adds the stepped-depth fallback below.
- Reading report pages: re.sub('<[^>]*>','',...) eats text when a log line contains a bare '<'
  (e.g. "(<100)") - it runs to the next '>' such as the "->" in the decision line. Strip real tag
  names only.

## TAN-only repair: small-radius re-solve and the restored escalation (2026-10-09)
- The repair chain of the silently-failed-tweak guard in util/identify.sh is now: star-list verify
  re-tweak, then small_radius_hinted_resolve(), then escalation to a remote plate-solve server; the
  remote result's TAN-only check runs the same chain (repair_tan_only_solution()), minus the
  small-radius step when it already failed locally on the same star list.
- Small-radius re-solve: the hinted pass again on the star list with --radius = FOV major axis / 8
  (1.94 deg on NMW-TTU) around the solution centre, pixel scale from the CD matrix +-10% (the
  "Image scale" of an edge-anchored TAN solution is a few per cent low), --depth stepped to 500
  objects (at --depth 100 the small circle failed 5 of 16 ordinary frames), --odds-to-solve 1e50
  (good solutions score log-odds 1150-2250, the marginal coarse quads 32-34), --cpulimit 120, own
  work files. Her-09-Q1b1x1 0112/0113 (2026-10-08) and 0104 (2026-10-06): index-4113/4112 quads with
  189-366 index stars, raw 1.0-1.4 arcsec median against UCAC5, final 0.28-0.32 arcsec - the
  production solutions were 6-15 arcsec. Disable with VAST_SKIP_SMALL_RADIUS_RESOLVE=1.
- Why the hinted pass picks the marginal quad: its --radius is the full field (15.5 deg), and
  solve-field tries the largest-quad index first and accepts the first match above log-odds 20.7 -
  an index-4115 quad (340-480 arcmin) verified by 8 stars, anchored near the frame edge, whose tweak
  then fails. The plate-solve CGI's hinted pass uses --radius 5 and solved the same frame (scan
  returned an order-3 solution, 2.9 arcsec raw median, 0.315 after the UCAC5 refit).
- Escalation bug (ca23497b, 2026-10-01): a failed re-tweak left the TAN-only wcs_ file in place, so
  "if [ ! -s wcs_... ]" never escalated. Fixed - and the TAN-only solution is now set aside
  (out$$_tan_only_wcs.fits) instead of deleted, and put back after the solve loop when no server
  returns a solution (unreachable, NOT SOLVED), so an offline host behaves as before. The internal
  abort paths of the remote branch (exit 1) still lose it, as the 2026-08-28 escalation did.
- Known limitation: under VAST_TWEAK_ORDER=2 (the factory's WCS retry) the star-list re-tweak can
  "succeed" with an order-2 fit to ~5 index stars (Her-09-Q1 0113: final 15.2 arcsec), which bypasses
  the small-radius re-solve; the factory's keep rule reverts such a retry (overall sigma doubled).
  The re-tweak's printed log-odds is the pre-tune-up value (the good Cas-04-Q2 0094 re-tweak also
  prints 10 matches), so it cannot be used as an acceptance cut as it stands.

## Astrometry follow-up and regression coverage (2026-10-09)
- The settle rule, retry keep rule and TAN-only repair are committed as 1a8c12b2.
  /var/www/vast moved from d5bdb823 to 1a8c12b2 during this follow-up; its sources
  match the commit and its binary contains the new settle-rule messages. Claude's two project memories
  and their index entries must reflect committed status, not "not applied".
- util/examples/test_vast.sh now contains CYG05Q1SETTLE and HER09Q1TANONLY beside
  CAS04Q2TANONLY. Both real-frame archives include README.txt and SHA256SUMS;
  their names are NMW-TexasTech__Cyg-05-Q1b1x1_SIP_settle_test.tar.bz2 and
  NMW-TexasTech__Her-09-Q1b1x1_small_radius_test.tar.bz2. Prepared copies are in
  /tmp/vast_astrometry_regression_20261009. Publish to tau's
  /var/www/tau.kirx.net/htdocs/vast_test_data/ (apache:apache, mode 0644) and
  scan's public_html/data/vast_tests/ as kirx; verify both public downloads
  against SHA256SUMS_astrometry_20261009 before running the full system test.
  Cyg replays the genuine pre-refit WCS/star list and checks the SAVED header;
  scatter alone passes the old bad solution. Her starts from the unsolved image.
  No reference-catalog fixtures are used. The user runs the full system test.
- Forced remote solving already allowed local star-list repair in ca23497b;
  1a8c12b2 adds a local small-radius repair of remote TAN-only results. Neither
  VAST_SKIP_SMALL_RADIUS_RESOLVE nor VAST_SKIP_IMAGE_BASED_RETWEAK alone emulates
  a client without local Astrometry.net.
- The 120-second image-based verify cost occurs in direct identify.sh calls,
  including the factory's initial parallel calibration; solve_plate_with_UCAC5
  skips it by default. --verify can fall through to a blind search after failed
  verification. The targeted TAN-only guard runs after that image-based pass.
- Installed Astrometry.net writes post-tweak LOGODDS/NMATCH to .match and support
  positions/weights to .corr. These are useful for investigating weak order-2
  re-tweaks; the current helper deletes them before judging success. Do not use
  the console's pre-tweak match count as a strength cut.
- Unmatched stars' stale catalog_mag is exported without a status flag in
  .wcscat.ucac5 columns 11/12. The legacy magnitude-calibration branch reads those
  columns; astrometric diagnostics themselves filter by the match flag. Saved
  patched 0078/0079 outputs have 192/203 such nonzero magnitudes on unmatched
  detections. This does not establish an effect on the TTU Tycho-2 path.
- Other proposed fixes concern pair-selection asymmetry after accepted/rejected
  refits and remote/local failure-state inconsistencies. No solver behavior was
  changed during this follow-up. Temporary detailed reports and deployment
  instructions are outside git in /tmp/vast_cyg04_data/handoff/; preserved
  evidence is /tmp/vast_cyg04_data/evidence. The housekeeping README in handoff/
  explains the removed disposable builds.

## Deeper astrometry review (2026-10-10)
- insert_wcs_header reports final CFITSIO write/close errors but returns 0.
  Reproduced with the existing binary under a child-only file-size limit:
  status 106 (write error), truncated output, "All done!", exit 0. Fix the writer
  as well as shell checks. The C SIP refit also only warns on header-write or
  .wcscat regeneration failure; write_wcs_catalog cannot propagate write errors.
  These can leave saved outputs inconsistent with successful in-memory fits.
- Short probes of the current repair helpers show success after a simulated
  solver exit 124 with output artifacts, acceptance of A_ORDER=0 or missing
  B_ORDER, and success with no output after an injected failed rename. Preserve
  the old usable solution until replacement succeeds; check status, header and
  moves, and make factory calibration waits consume every child exit status.
- Astrometry.net's fresh .wcs COMMENT cards contain post-tweak "log odds:" and
  "nmatch:"; 76 saved headers agree with their .match rows within rounding.
  util/listhead can read these without a new dependency. Read fresh solver output:
  the comments in a later UCAC5-refitted image describe the earlier solver fit.
  .corr row counts differ from NMATCH, and a wide bounding box alone does not
  establish strong spatial support. Calibrate any acceptance threshold first.
- UCAC5 ingestion assigns zero catalog_mag_err to valid matches too. The C-band
  preliminary N_COMP_STARS filter rejects every such row, but its calibration
  loop accepts them; saved Cyg-05 0037/0036 outputs give count 0 despite 4963/4961
  nonzero catalog magnitudes. Suppress unmatched magnitudes at export and use
  the same explicit candidate selection for count and calibration. Do not reject
  all zero catalog errors. No TTU Tycho-2 calibration error was demonstrated.
- WCS_QUALITY_DIAG is median-centered scatter AFTER global plane/magnitude
  corrections, not a direct test of the saved FITS header. A separate final-header
  diagnostic should measure bias, absolute errors and coverage on consistently
  selected pairs; audit it before changing factory ERROR decisions.
- In the installed Astrometry.net solver every quad vertex must be within the
  hinted radius. FOV/8 therefore constrains centrality and excludes coarse quads
  wider than FOV/4. It is not equivalent to reducing quad-size-max alone. Keep
  the smaller radius a fallback pending broader validation. The implementation
  below addresses output consistency and adds instrumentation; broader policy
  changes still need calibration. Temporary review and probe details are in
  /tmp/vast_cyg04_data/handoff/astrometry_deeper_review_2026-10-10.md and
  /tmp/vast_astrometry_review_20261010/.

## Astrometry output consistency and diagnostics (2026-10-10)
- insert_wcs_header now fails on final CFITSIO write/close errors and removes
  its incomplete output. identify.sh prepares stripped images, inserts WCS and
  verifies provenance privately before replacement; it preserves the first
  pass after a failed second solve and checks offline TAN fallback restoration.
  The factory drains all initial WCS calibration children and records failures
  by image; the later UCAC5 collection still has legacy bare waits and log-based
  failure handling, which deserves a separate audit.
- Client repairs now check solver status, both SIP axes, finite WCS terms and
  a nonsingular CD matrix. Attempt directories are unique. Pass --dir and a
  plain --out basename separately: solve-field concatenates them even when
  --out looks absolute. A real Her replay caught this with an absolute xyls
  input. ASTROMETRY_REPAIR_DIAG reports final COMMENT log-odds and match count.
- VAST_SKIP_LOCAL_ASTROMETRY_REPAIR=1 disables optional client repairs,
  including the image verification. Combine with remote initial solving for
  a genuinely remote-only Astrometry.net test, and remove cached WCS results
  first. UCAC5 refinement is separate and retains its existing controls.
  VAST_LOCAL_ASTROMETRY_REPAIR_TIMEOUT defaults to 360 seconds, shared across
  star-list repairs/escalations, with each solver capped at 120 wall/CPU seconds.
  The retained image diagnostic has its own 120-second cap. It is documented
  as redundant for TAN-only frames; VAST_SKIP_IMAGE_BASED_RETWEAK=1 still skips it.
- SIP refits stage a full image copy and regenerated .wcscat before updating
  stars[]. A hard link holds the original image for checked rollback. An
  unrecoverable rollback returns failure and retains the original for recovery.
  Symlink targets remain untouched in the intentional catalog-only mode.
  Two publication renames are not atomic for concurrent readers or a crash
  between them. There is one additional full image copy per applied refit.
- The final .ucac5 writer checks writes/close and replaces the catalog by rename,
  preserves permissions, and zeros UCAC5 magnitude/error for unmatched stars.
  C-band count and selection share one explicit numeric filter; zero errors
  are valid. Other photometric bands and factory quality thresholds are unchanged.
- WCS_QUALITY_DIAG is retained with a human-readable redundancy/limitations
  comment. WCS_HEADER_DIAG measures the saved header through WCSTools, reports
  RA/Dec bias, median/p95 absolute separation and coverage. It explicitly uses
  selection=current_pairs, not a new independent match or an acceptance rule.
  On a protected old Cyg header, legacy scatter was 0.341 arcsec while saved-
  header median separation was 8.077 arcsec; this distinction is intentional.
- Validation: full serial build in /tmp/vast_astrometry_build_20261010;
  32 short astrometry safety cases (also called by test_vast.sh), 32 existing
  WCS retry cases, real Cyg replay (4719 matches, all 12 saved-header samples
  within 1.5 arcsec, exported nonzero magnitudes exactly equal the match count),
  and bounded writer/regeneration/publication/rollback/symlink probes passed.
  Real Her small-radius and star-list helpers produced valid SIP output with
  final match counts 196 and 1436. Full system test results follow below;
  production deployment remains separate. Temporary logs/probes are under
  /tmp/vast_astrometry_implementation_20261010/.
- Still open: calibrating post-tweak strength/spatial acceptance on broader
  cameras and index sets; independent saved-header matching with a uniform
  reference sample; portable process-tree termination (lib/timeout only kills
  its child). CPU limits, cancellation markers and private work directories
  reduce the orphan problem but do not guarantee prompt tree termination.
  Failed solver work directories retain cancellation markers for late engines.
  Do not delete them until those engines have stopped. Smaller-radius defaults
  and the tau/scan CGI port remain separate, unvalidated policy changes.

## WCS validation must allow repeated camera metadata (2026-10-11)
- The full system test on 77b5f372 found ISONM31CCD005_exitcode and then
  stopped with SATURN006_no_platesolved_img. Both solvers had succeeded:
  install_astrometry_wcs rejected the assembled image because the camera's
  DATE and Astrometry.net's creation DATE were both present. The validator
  runs on complete images as well as standalone solver headers; duplicate
  detection must be limited to the WCS cards it validates.
- test_astrometry_safety.sh now has 37 cases, including installation with
  both DATE cards and rejection of duplicate CTYPE, CD, SIP-order and SIP-
  coefficient cards. The existing test_vast.sh invocation runs these cases.
- fail_early() must save the current failure codes before copying report
  artifacts. Otherwise a fatal check between checkpoints appears only in
  the full console log, while the saved reports omit the stopping failure.
- Validation: a fresh serial build, all 37 safety cases and both real-image
  reproductions passed. The complete rerun finished in 284.8 minutes with
  exit 0: 144 sections passed, including both Saturn tests, M31, Cyg-05,
  Her-09, SIP policy and remote solving. The database section retained the
  two already-exempt GCVS lookup codes; a later exact HTTP lookup returned
  BL Lac/BLLAC, and the unchanged VaST wrapper also found it with exit 0.
  Local Solar System comparisons were skipped because skyfield is absent;
  the optional HJD comparison was skipped because vartools is not in PATH.
  Reports and reproduction logs are outside the tree in
  /tmp/vast_system_test_20261011/ (complete rerun: run2/).
- Repeat verification on 2026-10-12 at fdaf4b0f: a fresh serial build and
  full system rerun finished with exit 0 in 263.6 minutes. All 145 section
  statuses matched the preceding run: 144 passed, with the database section
  retaining only STANDALONEDBSCRIPT001b_GCVS. A subsequent unchanged database
  lookup found BL Lac/BLLAC with exit 0 in 23 seconds. The GCVS assertions
  make separate network requests, so one can pass while another reports
  no result; the silent lookup does not retain enough detail to distinguish
  the original transport failure from an empty server response. Local Solar
  System comparisons still lack skyfield (and pandas); vartools is also
  absent. No additional code changes were needed. Logs and the focused
  lookup are in /tmp/vast_system_test_20261012/.

## Valid SIP can still need small-radius recovery (2026-10-13)
- Production Her-09-Q1b1x1 frame 0091 of 2026-10-12 fails on deployed
  1a8c12b2 and current ac833127 (code identical to tested fdaf4b0f). Fresh
  local replay, including the optional image-verification path, reproduces
  all 54 WCS/SIP keywords of the bad production header exactly. Replaying
  the saved header with current UCAC5 code also retains the bad astrometry.
- A coarse index-4115 match with eight stars gives TAN-only WCS. Star-list
  verification returns structurally valid order-3 SIP (index-4114, 49 final
  matches, logodds 377.822), so repair_tan_only_solution returns before the
  small-radius helper. UCAC5 rescue correctly rejects lost quadrant coverage;
  the factory's order-2 retry worsens the result and restores the original.
- Calling the existing small-radius helper explicitly with the same 8257-star
  list finds index-4112, 374 final index matches and 4906 UCAC5 matches with
  balanced quadrant counts 1400/1027/1451/1028. Worst-quadrant scatter is
  0.347 arcsec instead of 17.076. No subsequent UCAC5 SIP refit was applied.
- Comparing both saved headers on the same 4906 repaired-solution matches
  gives median/p95 errors 25.457/1240.303 arcsec before and 0.905/2.664 after.
  Diagnostics using the original selected pairs conceal the most displaced
  stars; occupied grid cells alone do not establish adequate coverage.
- Next improvement: bounded quality-triggered small-radius recovery even
  for valid SIP, with candidate accuracy/coverage checks and rollback. Add
  this exact frame beside the existing 2026-10-08 Her frame 0112 regression;
  that older case's verifier fails outright and already reaches the helper.
  Investigation only: no solver changes or production deployment performed.
  Evidence and reproducible probes: /tmp/vast_her0091_20261013/.

## Factory recovery for inaccurate SIP and Her-0091 regression (2026-10-13)
- The factory's normal quality-retry entry point now tries one bounded
  small-radius recovery before its order-2 fallback, limited to TTUQ1/TTUQ2,
  fields wider than 5 degrees, a local solver, and measured absolute failure
  above one pixel. Existing local-repair/small-radius opt-outs still apply.
  Standalone solve_plate_with_UCAC5 policy is unchanged.
- VAST_ASTROMETRY_SMALL_RADIUS_SEED is an internal explicit retry mode in
  identify.sh. It consumes the retained bad WCS, shares the existing repair
  deadline, installs a candidate transactionally, and fails without an
  ordinary blind/remote fallback. The factory measures that candidate with
  UCAC5, requiring improved worst-quadrant scatter and saved-header p95
  within one pixel, all 16 spatial cells, and retained quadrant coverage.
  Checked backups preserve all WCS sidecars; rejected candidates restore
  both diagnostics. Cache replacement happens only after acceptance, and
  a failed rollback stops the factory with recovery files retained.
- test_vast.sh includes HER09Q1VALIDSIP, seeded from the real bad header and
  detected-source catalog, then calls the actual factory retry entry point.
  It checks 64 fixed UCAC5 reference positions, quadrant counts/scatter,
  local_wcs_cache equality and small-radius provenance. Missing local
  solve-field is an explicit optional skip; missing test data is a failure.
  The system safety section also runs test_wcs_quality_retry.sh.
- Validation: full serial build; 41 astrometry safety and 46 quality-retry
  cases; existing Cyg settle and Her TAN-only real regressions passed. The
  new case fails before the fix (57/64 fixed coordinates wrong) and passes
  after it: 4908 matches, worst quadrant 0.340 arcsec, saved-header median/
  p95 0.908/2.668 arcsec, all 64 reference positions within one pixel.
  Full system suite was not rerun for this change.
- New archive: NMW-TexasTech__Her-09-Q1b1x1_valid_sip_test.tar.bz2, about
  60 MiB, prepared with README and SHA256SUMS under
  /tmp/vast_her0091_fix_20261013/data/. Publish to the same tau and scan
  test-data directories as the earlier Cyg/Her cases. Deployment commands
  and validation logs remain outside the tree in that investigation directory.

## All test-data downloads in test_vast.sh go through download_test_data_file() (2026-10-14)
- 2026-10-13 ~21:52-22:01 UTC: polaris answered the tau.kirx.net vhost with its stock 299-byte
  "503 Service Unavailable" page (mod_proxy without a backend; HTML 2.0 doctype, no server
  signature, sha256 5764fed3...). Ubuntu CI run 38471824132 failed in the NMW_Venus_test download
  ("bzip2: (stdin) is not a bzip2 file") and all five unmw science jobs failed the same way on
  NMW__NovaVul24_Stas_test.tar.bz2; unmw now pins that archive's SHA256 (tests/fetch_fixture.sh).
- The remaining 127 plain 'curl -O' downloads were converted to
  download_test_data_file FILE "tau URL" "scan.sai.msu.ru URL" (tau first) and the 117 commented-out
  mirror lines were folded into the calls. Every URL was HEAD-probed on 2026-10-14; five files exist
  only on tau and are called with one URL (STEREO-A-H1__test, NMW-TexasTech__Aur-02-Q2b1x1,
  NMW-TexasTech__Cas-04_platesolve_failure_test, NMW_Cyg5_astrometry_problem_test,
  wcs_Sgr-05-Q2b1x1_2026-03-26_..._0682.fits.bz2). The seven 'timeout 300' wrappers were dropped
  (a shell function cannot be wrapped; --speed-limit 1024/60 s already ends a stalled transfer), and
  the dynamic edited_lightcurve_data.txt fetch of the period-search test only gained --fail.
  No 'curl -O' without --fail remains in the file.
## SExtractor flags in lightcurve metadata (2026-10-20)

- `Observation.sextractor_flag` carries the current detection's complete
  unsigned extraction flag through sorting and both lightcurve output paths.
  `write_obs_to_file()` emits `SE_FLAGS=N` after the ten optional aperture
  values and before FITS keywords, so flags are never cut off.
- The shared reader in lightcurve_io.h keeps up to 1023 metadata characters
  (512 until 2026-10-21; lc.c stores 1024 bytes per point). With 512, the
  11-12 characters of SE_FLAGS pushed captured-keyword tails of 422-432
  characters past the limit, and every tool that rewrites lightcurve lines
  silently cut the last keyword value. 1023 covers the longest line vast.c
  writes (aperture values, SE_FLAGS and FITS_KEYWORDS_IN_LC_LENGTH).
- `report_transient.sh` reads the named token, accepts decimal values 0-255,
  and tests bit 4 for saturation. Notes are emitted AFTER the measurement
  table, on the same output line as `</table>`. Keep its cells and numeric
  contents unchanged: unmw reads them, and make_report_in_HTML.sh's MPC
  formatter uses HTML tag positions. Do not add a newline between the
  table and the mean-position block: test_vast.sh's Nova Vul lookup uses
  `grep -B13`, while unmw/autoprocess.sh's bright-candidate checks use
  `grep -B6` and `grep -B17` to reach discovery rows and the candidate anchor.
  This annotation does not change candidate selection or export policy.
- Fixed metadata loss in MagSize_filter_standalone, random-point selection,
  and the lc editor (including both point-deletion paths). The old multi-image
  identification script also needs a trailing REST variable so metadata
  does not become part of the FITS filename. Simulation, binning and reduced
  export formats have different semantics from rewriting original observations.
- `python3 util/examples/test_lightcurve_metadata.py [build_directory]`
  tests all 256 flags in both writer formats, aperture replacement,
  calibration, sigma/MagSize filtering, random selection, legacy rows, and
  exact HTML-table and line-spacing compatibility. It also checks that
  the no-FITS-keyword assertion permits `SE_FLAGS=N` but still rejects
  captured header keywords. All test data are temporary.
- The sigma filter needs its own rows with scatter and an injected outlier:
  without a SIGMA argument lib/new_lightcurve_sigma_filter prints its usage
  and exits 0, and after aperture replacement every magnitude is identical
  (sigma 0, so a real SIGMA clips every point). A chained no-argument call
  passed vacuously until 2026-10-21.

## bash 3.2 lint: the named-FD rule matched parameter expansions (2026-10-21)
- BASH4_NAMED_FD in lib/check_bash32_compatibility.sh matched any `{NAME}<`
  or `{NAME}>`, so HTML built in bash (`"...${SE_FLAGS_NOTE}<br>"` in
  util/transients/report_transient.sh) failed the bash32compatibility CI job
  on c906334b and 7444f4b1 while the system test itself passed. The rule now
  requires the brace to start a word (the prefix class of the other rules):
  `exec {fd}>`, `cat {fd}<`, `{fd}>&-` and `;{fd}>` are still reported.
- To run the lint locally, build bash 3.2.57 as described in the bash 3.2
  section above; the build takes about a minute with gcc 11.

## Astrometry regression cases need the in-house local UCAC5 copy (2026-10-21)
- The CYG05Q1SETTLE, HER09Q1TANONLY and HER09Q1VALIDSIP floors (N_match >= 4000,
  n_q >= 800 per quadrant, 1.5 arcsec at fixed pixels) were set with
  lib/catalogs/ucac5, which matches up to 5000 stars
  (DEFAULT_UCAC5_LOCAL_QUERY_LIMIT). The remote UCAC5 servers return at most
  1000 (MAX_STARS_IN_VIZQUERY). The block is skipped on GitHub Actions, so the
  first remote-only host to run it (hawkeye: no local UCAC5, no solve-field)
  failed both runnable cases on counts alone: Cyg-05 889-890 matches, n_q
  190-272 and 1.56-2.85 arcsec at five corner pixels (centre and edges
  0.05-0.65); Her-09 973 matches with sigma 0.39 arcsec.
- test_vast.sh now reports each case as NOT_PERFORMED_<CASE>_no_local_ucac5
  (exempt) when lib/catalogs/ucac5/z001 is missing. util/identify.sh in
  identification mode (identify_transient.sh runs in the photographic plate
  section) links lib/catalogs/ucac5 from the in-house paths (/home/kirx/UCAC5,
  $HOME/UCAC5, ../UCAC5, ...), so on tau the link exists before this block.
  lib/install_local_copy_of_UCAC5.sh downloads the 5.3 GB catalog.
- Remote-only Her-09 side observation: the saved header measured median
  2.6 / p95 5.9 arcsec (WCS_HEADER_DIAG) while the corrected positions gave
  0.39 (WCS_QUALITY_DIAG). The refit (3.08 -> 0.55 arcsec on the raw header)
  was rejected because its worst region (0.764) did not beat the corrected
  baseline (0.633), so the header kept the remote solution's error. Tools
  that use the header (xy2sky/sky2xy) see that error on remote-only hosts.

## Full test_vast.sh run on hawkeye (2026-10-21, 7444f4b1)
- hawkeye (RHEL 9.8, i7-12700, 15 GB; no solve-field, psfex, vartools,
  astropy, skyfield, selenium, local UCAC5 or NMW calibration) ran the suite
  from a fresh GitHub clone: 134 of 139 sections passed in 563 minutes.
- Run it outside /tmp there: /tmp is on the 80 GB root disk, while the
  14 GB of test data in /export/home/hawkeye/vast_test sit on XFS with
  reflink, so `cp -a` makes an isolated copy in under a second. Unset
  DISPLAY (the desktop is :0) and give the script stdin </dev/null (the
  final report prompt reads a line).
- Failures: Cyg-05/Her-09 (no local UCAC5, now skipped), the known GCVS
  lookup, and two external problems that day: JPL Horizons refused
  connections (the kirx.net proxy forwards to it, so the Solar System section
  waited 88 minutes on timeouts and failed SOLAR_SYSTEM_INFO_Ganymede) and
  https://www.kirx.net/~kirx/ answered 403 (AUXWEB_INDEX_KIRX_PARENT_DIR_MISSING).
- util/moons.sh exits 0 with empty output when Horizons is unreachable, so the
  moons.txt format loop of the Solar System section passes vacuously; only
  the MPCheck Ganymede lookup catches the outage.
- Rerun on 2026-10-22 with the keyword-recording fix: 135 of 138 sections in
  428 minutes. vsx.aavso.org answered 504, which failed
  STANDALONEDBSCRIPT001c_VSX and made the CBA formatter name V615 Vul
  'PNV J19430751+2100204' (NMWNVUL24ST_CBASCRIPTTEST_*); the same section
  passed with the old and the new vast binary an hour later. The scan.sai.msu.ru
  plate archive search hung (AUXWEB_PASKYARCHIVE_001-003). The online
  database and web-service sections fail on whichever service is down that
  day: check the service before suspecting a regression.

## FITS keyword recording in lightcurves (fixed 2026-10-22)
- record_specified_fits_keywords() in src/vast.c read the list with
  fgets(...,9,...): a name shorter than 8 characters kept its newline and
  failed the character check, so AIRMASS, HA and PA of the shipped _example
  list were never recorded (only 8-character names like CCD-TEMP worked). The
  loop also never stopped at MAX_NUMBER_OF_FITS_KEYWORDS_TO_CAPTURE_IN_LC, so
  11+ valid names wrote past the list array on the stack.
- Two output defects in the same function: cards are concatenated, and a card
  without a comment has no trailing blank, so values ran into the next name
  ("XBINNING=   2YBINNING="); and the comment was cut at the first '/' even
  inside a quoted string ('NGC 224/M31'). Now: whole lines are read and the
  name is the first word (the rest of the line is a comment, as it was by
  accident for 8-character names; empty and '#' lines are ignored, CR ends
  the name), at most 10 names, cut at the first '/' outside quotes, trailing
  blanks trimmed, one space between cards.
- The list is re-read for every image, so list warnings are printed only for
  the first image (third argument print_list_warnings).
- test_vast.sh: the first Small CCD section copies the _example list into
  place and nothing removes it, so every later local section records
  keywords. Since this fix that includes AIRMASS (NMW-TexasTech, KGO, M31,
  Gaia16aye), PA (NMW-STL, Stas) and HA where present. The keyword section
  checks short names, separators, the 10-name limit and a quoted '/'
  (WITH_KEYWORD_RECORDING_SMALLCCD014-017) on sample_data; like the other
  Small CCD sections it is disabled on GitHub Actions.
- util/examples/test_lightcurve_metadata.py runs early in test_vast.sh
  ("Lightcurve metadata test", LCMETADATA001 on failure). Without python3 >=
  3.7 or a C compiler (cc, gcc or clang) it is skipped as
  NOT_PERFORMED_LCMETADATA_<reason>, which the end of the script exempts.

## Known-star check without CDS: local Gaia DR2 copy, VizieR probe record, APASS off (2026-11-04)
- From 2026-11-03 CDS (VizieR, SIMBAD, cdsarc) dropped connections. The china-vo and
  nao VizieR mirrors serve only small catalogs (china-vo answered a crowded bulge cone
  with an empty Gaia DR3 table), the CfA mirror is HTTPS-only and returns empty tables
  for I/345/gaia2, and the ESA Gaia archive answered intermittently.
- Why the known-star check (query_gaia_dr2 in util/transients/report_transient.sh) found
  nothing: lib/choose_gaia_dr2_client.sh picks the client once per run and returns
  vizquery when both 15 s probes fail, and there was no VizieR-to-ESA fallback. Runs of
  2026-11-02/03 used vizquery in about half the fields; crowded fields filled with known
  variables and failed the candidate limit (Vul-01 8 unidentified of 222, Cyg-08 5 of 217).
  ESA and VizieR now fall back to each other, and VizieR is not asked when the factory's
  mirror probe failed (VIZIER_UNREACHABLE=yes, one WARNING line per run).
- lib/choose_vizier_mirror.sh spent 162 s per run when no mirror answered. The result is
  now shared through lib/catalogs/.vizier_mirror_probe_<CATALOG> for 900 s (success) or
  300 s (failure); VIZIER_MIRROR_RECORD=no bypasses it (test_vast.sh's internet gate).
- util/solve_plate_with_UCAC5 no longer asks VizieR for UCAC5 when lib/catalogs/ucac5
  exists or one of our UCAC5 servers answered ("Not querying VizieR for UCAC5: ...").
- Local catalogs: lib/catalogs/local_star_catalog (src/catalogs/local_star_catalog.c)
  writes 900 Dec zones of 24-byte records with a 0.1 deg RA index and prints the vizquery
  text format, so report_transient.sh parses its answer unchanged. GAIA_DR2_CLIENT=auto
  picks it when lib/catalogs/gaia_dr2/catalog_info.txt exists; the factory links
  /data_ssd/GaiaDR2 and similar directories (the list next to the UCAC5 one).
- The local copy must be Gaia DR2, the release the online check and the test expectations
  use. A DR3 copy, tried first, failed five test_vast.sh checks: the Miras V2407 Sgr,
  V1858 Sgr, V6463 Sgr, WZ Aur and AT Cyg have DR3 mean G 0.03-0.46 mag brighter than
  DR2 and fell under the MAG_MEAN+0.98 faint limit (V2407 Sgr: DR2 13.38, DR3 13.24, limit
  13.29). This is a selection effect: the tests hold the Miras that DR2 lets through.
  WZ Aur (DR3 G = 12.8304, limit 12.83) failed only because the copy rounds to 0.001 mag;
  local_star_catalog now leaves out a star within 0.0005 mag of a limit. These are the
  losses in the 28 sections run with the DR3 copy, not an exhaustive list.
- lib/install_local_copy_of_GaiaDR2.sh: 61234 files, 588 GB, from
  https://cdn.gea.esac.esa.int/Gaia/gdr2/gaia_source/csv with checksums in MD5SUM.txt (the
  DR3 list is _MD5SUM.txt). The CDN directory pages are JavaScript; list the files with the
  S3 XML at https://gaia.eu-1.cdn77-storage.com/?prefix=Gaia/gdr2/gaia_source/csv/&delimiter=/
  (1000 keys per page, NextMarker). DR2 CSV has no quotes and empty fields for nulls; DR3
  quotes strings and writes null. G < 19: 568135077 stars, 13 GB, built in
  2 h 8 min on tau with 12 parallel downloads. It refuses to run on GitHub Actions;
  the test_vast.sh section "Local Gaia DR2 copy test" runs only elsewhere and records the
  exempt code GAIADR2LOCAL_NOT_INSTALLED when there is no copy.
- For all 747 candidates of the baseline system-test reports, the local copy and GAVO's
  online Gaia DR2 returned the same stars (same source_id, G within 1 mmag); a DR3 copy
  changed the reject/keep decision for 45 of them. A search takes about 1 ms.
- Cross-checks while CDS and ESA are down: GAVO TAP (https://dc.zah.uni-heidelberg.de/tap,
  table gaia.dr2light) answers DR2 cone searches in seconds. ARI
  (https://gaia.ari.uni-heidelberg.de/tap, gaiadr2.gaia_source) answers source_id lookups
  but took more than 30 s for every cone search, so it is no fallback for the check.
- System test (2026-11-04, CDS down): 26 NMW sections of test_vast.sh plus the Gem-03
  standalone test, run with GAIA_DR2_CLIENT forced. Candidates in total: no check 747,
  local Gaia DR2 501, Tycho-2 + UCAC5 682, local Gaia DR3 480. With the DR2 copy every
  section passed except Nova Sgr 2021 N1 and three that failed in all variants (the two
  TICA TESS sections, whose APASS_I calibration needs CDS, and the selenium check of
  Nova Vul 2024 ST). Nova Sgr 2021 N1 requires at least 6 candidates (a 2021 value; its
  dataset is not downloaded by default) and got 5 both with the local copy and with the
  ESA archive: the same four catalogued stars are rejected, so the bound is stale.
- Tycho-2 + UCAC5 (GAIA_DR2_CLIENT=tycho2_ucac5, experimental) against DR2: it lost 15
  known variables (14 Miras, 1 SR; AT Cyg fails the Cyg5 test) and kept 190 known
  variables that DR2 rejects (Sgr-04 218 candidates instead of 132, Gem-03 standalone
  19, over its limit of 17). No variant lost a nova, dwarf nova, planet, comet or
  asteroid. UCAC5 (Gaia DR1 stars matched to UCAC4) lacks many bright red variables:
  the G = 10.2 Mira at 17:43:02 -13:23:16 is in neither copy.
- "The object was found in astcheck" is not an asteroid identification:
  util/transients/MPCheck_v2.sh searches 600 arcsec. The "lost asteroids" of a first
  comparison were Miras with an asteroid 8-10 arcmin away.
- The APASS check is off unless APASS_KNOWN_STAR_CHECK=yes (and VizieR answers): APASS
  exists only at CDS VizieR. Stars brighter than V = 9.1 are excluded earlier by the BSC
  and Tycho-2 lists.
- Candidate limits: factory 80, or 400 (was 200) when at most 19 are unidentified, all
  three overridable from the environment; unmw combine_reports.sh 400. Deploy both: the
  factory's own "too many candidates" ERROR line marks a field red whatever unmw accepts.
- An optional build step in the factory must log to its own file
  (local_star_catalog_build.log): an ERROR line in transient_factory_test31.txt fails the
  field. The first tycho2_zones build failed because the parent of its staging
  directory did not exist; make_dir now creates parents like mkdir -p.

## Known-star check follow-up: what Tycho-2 + UCAC5 lets through, UCAC5 links, test margins (2026-11-04)
- The 190 candidates of the NMW test sections that the Tycho-2 + UCAC5 check keeps and
  Gaia DR2 drops are 151 distinct stars (39 reported twice): 150 VSX variables, mostly
  Miras and semiregulars, and one star not known to vary (STL Neptune field, measured at
  its Gaia G; the reference frames were too shallow). Gaia flags 188 of the 190 entries
  as variable (DR2 phot_variable_flag 122, DR3 184). Caveats from an independent check:
  one identification is weak (an "SRS:" ASAS-SN star with no Gaia flag), and 21 stars,
  mostly in Aql-03, brightened by more than their catalogued amplitude, possibly a
  photometry effect for very red stars.
- Why UCAC5 misses them: the Gaia stars behind 188 of the drops (152 distinct, G 8.2-14.3,
  median 12.6, median G - RP 1.87) have no UCAC5 entry within 2 arcsec (checked also
  with a separate numpy reader of the zone files), and 150 of the 152 are not in Gaia
  DR1, from which UCAC5 is built (gaiadr2.dr1_neighbourhood at the ARI Gaia TAP, cone
  searches agree). Within 60 arcsec of them, UCAC5 has 5 of the 21 other Gaia DR2 stars
  of similar G with G - RP > 1.3, and 162 of the 174 bluer ones. Tycho-2 does not reach
  such red stars in V.
- False candidates (not known to vary, no Gaia variability flag) are what matter: in the
  same sections Gaia DR2 drops 12 of them and Tycho-2 + UCAC5 drops 11.
- util/transients/search_for_transients_single_field.sh skips the known-star check by
  unsetting VIZIER_SITE; the factory always sets it. So the gate in report_transient.sh
  stays "VIZIER_SITE set, or GAIA_DR2_CLIENT=esa_tap" (and not none). Widening it to the
  local clients made "Saturn/Iapetus test" (single-field) lose QY Sgr, V1234 Sgr and an
  ASAS-SN variable when GAIA_DR2_CLIENT=local was exported.
- The UCAC5 search lists of the factory and util/identify.sh contain ../UCAC5; it was
  linked as is, and a relative link target is read from lib/catalogs/, so that link was
  broken. Link targets are absolute now. A link pointing exactly at ../UCAC5 or ../ucac5
  is replaced in one step with ln -s -n -f: removing it first let parallel runs on a
  shared lib/catalogs briefly find no link and print a false "no local copy of UCAC5"
  WARNING in a race test. Other broken links are kept (an unmounted disk).
- Nova Sgr 2021 N1 now requires at least 5 candidates (the 2021 bound was 6): the Gaia
  DR2 check drops the Miras V0358 Sgr, V2087 Sgr, V2048 Sgr and one of the two SV Sct
  detections, online (ESA) and from the local copy alike.
- Some Mira checks pass the Gaia DR2 check by a few hundredths of a magnitude: WZ Aur by
  0.03 (Aur-02; with DR3 it would be 0.0004), AT Cyg by 0.05 on one of its two
  detections (Cyg5). A small photometry change can fail them; the comments in
  test_vast.sh give the numbers.
- unmw's filter_report.py classes a candidate known_asteroid whenever the report says
  "found in astcheck", and MPCheck_v2.sh searches 600 arcsec: Miras with an asteroid
  8 arcmin away were classed as asteroids. Use the astcheck distance when analysing
  candidates.

## Report marker spelling, zlib build leftovers, test data on GitHub (2026-11-04)

- The end-of-report marker of transient_report/index.html is `<H2>Processing complete!</H2>`
  (transient_factory_test31.sh; unmw's combine_reports.sh, autoprocess.sh and
  nmw_monitoring_lib.py rely on exactly this string). transient_factory_test30.sh and
  NMW_transient_detection_test.sh, and old versions of test31, write `Processig complete!`.
  The Sgr9 crash test in test_vast.sh grepped only for the misspelling, so after the typo
  fix its 5 "excluded variable is not above the marker" checks could never fail. Match
  the marker as `grep -E -B10000 'Process(ing|ig) complete!'`: the '!' is required, the
  report also says "until the 'Processing complete' message appears" at the top and
  "Processing completed" after the marker.
- lib/compile_zlib.sh must finish with `make distclean`, not `make clean`: only distclean
  restores the tracked src/zlib-*/Makefile placeholder and zconf.h that ./configure rewrites.
  Otherwise every build leaves them modified in git status.
- The test data files of http://tau.kirx.net/vast_test_data/ are mirrored as assets of the
  GitHub pre-release test-data-v1 (asset name = path with '/' -> '__', other characters
  outside A-Za-z0-9._+- -> '_'); download_test_data_file() tries GitHub first. A new file
  in vast_test_data/ must also be uploaded there (gh release upload test-data-v1 ...).
- The build-product part of .gitignore was generated from a fresh clone + `make`
  (git ls-files --others); regenerate it the same way when programs are added.
- Building bash 3.2 (app-shells/bash:3.2) with gcc 16 fails in builtins/mkbuiltins.c
  (C23 treats `f()` as taking no arguments). CFLAGS alone does not reach mkbuiltins (it is
  compiled with CFLAGS_FOR_BUILD); CC="gcc -std=gnu89 -fpermissive" via package.env was
  suggested but not yet confirmed to work.

## VizieR probed only when needed, online name lookup skipped while VizieR is down, TTU FWHM limit (2026-11-05)
- After the 2026-11-04 deploy about half of the runs still waited 96-162 s at the start for
  lib/choose_vizier_mirror.sh: all three mirrors fail (CDS: two 10 s connect timeouts; china-vo
  and nao: HTTP 200 and no data for about 68 s, or nao's 3 s error page). The shared record has
  no lock and is trusted 300 s after a failure, and unmw's load gate releases runs in bursts that
  all probed at once. The probe only picks a mirror for the known-star check, and with the local
  Gaia DR2 copy nothing needs one up front. The factory now settles GAIA_DR2_CLIENT first and
  probes only for an online client or APASS_KNOWN_STAR_CHECK=yes. Otherwise it reads the record
  (VIZIER_MIRROR_RECORD_ONLY=yes: exit 0 or 1 from a recent result, 2 and the CDS site when
  there is none) and sets VIZIER_UNREACHABLE to yes, no or unknown. VIZIER_SITE stays set: the
  known-star check runs only when it is. test_vast.sh reads the first "VIZIER_SITE=" and
  "GAIA_DR2_CLIENT=" lines of the log, so no other log line may contain those strings.
- The online name lookup of unidentified candidates (util/search_databases_with_vizquery.sh,
  called by report_transient.sh) asks VizieR about ten catalogs in a row. With CDS down every
  query waited about 25 s: 4-8 min per affected field, and no names. report_transient.sh skips it
  when VizieR is unreachable (vizier_is_unreachable: VIZIER_UNREACHABLE from the factory; when
  that is unknown, choose_vizier_mirror.sh answers from the record and probes only without a
  recent result). The same function guards the VizieR fallback of query_gaia_dr2, which runs when
  a local catalog cannot be read: "unknown" must not mean a 40 s CDS timeout per candidate. The
  lookup script is unchanged: it
  also checks the local catalogs, and test_vast.sh calls it directly. The skip line is "online_id
  skipped: VizieR is unreachable", without a space before online_id:
  util/transients/make_report_in_HTML.sh takes the AAVSO object name from a line containing
  " online_id ", and unmw's filter_report.py only uses lines starting with "online_id" as the end
  of a crossmatch block.
- FILTER_BAD_IMG__MAX_APERTURE_STAR_SIZE_PIX limits the aperture diameter (6 x median A_IMAGE,
  about 1.9 x the median FWHM on the TTU cameras, scattered: 6.2-8.5 pix at FWHM 4.5-5 pix) and
  is applied only to uploads with more than two second-epoch images (the preliminary VaST run).
  TTU uploads have two, so blurred images went through. FILTER_BAD_IMG__MAX_FWHM_PIX (4.5 for
  TTUQ1b1x1 and TTUQ2b1x1, can be set in the environment; a large value switches it off) rejects
  the field when the median FWHM_IMAGE of FLAGS<2 sources on a second-epoch image is larger. It is
  measured on the catalogs of the bright-star pass (SEXTRACTOR_CONFIG_BRIGHTSTARPASS) right after
  its ./vast run, before the exit code is examined, and rounded to 0.1 pix like that pass's "Median
  FWHM seeing" lines. The pass matters: the passes with fainter stars measure the same images about
  15% smaller (4.2 instead of 4.9 pix for a blurred image), so the check must not move to a later
  pass when the first one fails. The values are printed as " N.N pix  <image>  (...)" lines, the
  format unmw's nmw_second_epoch_fwhm reads for its FWHM column. On failure the field gets
  "ERROR: seeing on second-epoch images is out of range (median FWHM X and Y pix, limit 4.5 pix)"
  and the remaining passes are skipped (a blurred field ended after 22 s in a test).
- Why: on 2026-11-04 the TTUQ1 focuser moved from 29479 to 29453 between the 19:09 and 19:14 CST
  exposures (29447 later), and its images went from 2.2 to 4.7-5.6 pix FWHM for the rest of the
  night, with up to 74 candidates per field instead of 0-3. Nov 3 had soft TTUQ1 images too.
- util/examples/test_vizier_mirror_record.sh tests the record offline with a stand-in vizquery.
- ESA's per-candidate Gaia DR2 query (report_transient.sh, both calls of lib/gaia_dr2_cone_search.sh)
  now waits 90 s instead of 30 s. Of 22 synchronous ESA queries on 2026-11-05, 18 were answered in
  1.5-89 s (median 23 s; 30 s would have kept 12 of them, 60 s 15, 90 s all 18) and 4 were refused
  within a second (HTTP 503, "maximum number of synchronous queued jobs (150) reached"). Refusals
  and outages fail fast, so the longer limit costs time only while ESA is slow but answering. The
  15 s start-of-run probe in lib/choose_gaia_dr2_client.sh stays: ESA is asked for every candidate
  whenever VizieR fails, so the probe only decides which service is tried first. Asynchronous
  queries (/tap/async) took 1-3 s while the synchronous ones were refused or slow.

## UV Ceti check (nearby red dwarf), Gaia DR3 nearby-star copy, vizquery https redirect (2026-11-09)

- New: util/transients/check_nearby_red_dwarf.sh tells whether a Gaia DR3 star closer than
  200 pc (parallax > 5 mas, parallax_over_error > 3) sits at a candidate's position once its
  proper motion is applied to the epoch of the observation, and where it sits with respect to
  the K/M dwarf main sequence. Design, thresholds, verdicts and caveats are in
  .claude/nearby_red_dwarf_check_design.md. Decisions of 2026-11-09: BP-RP >= 1.0 (all K and M
  dwarfs) counts as red; the check runs for VSX-matched candidates too; the local copy is the
  primary source, the ESA archive the fallback, VizieR the last resort.
- 2026-11-16: red now means K5 and later (BP-RP >= 1.39, G-RP >= 0.78, the K5V entries of the
  locus table). With all K dwarfs counted, SS Cyg in outburst (BP-RP 1.18, M_G 6.4: the K donor
  plus the disc sit on the main sequence) was called a likely UV Ceti-type flare.
- The report line starts with 'UV Ceti check' and is appended after the forced-photometry
  lines. It is a new entry for the parser list above: unmw/filter_report.py ends the astcheck
  match block at that prefix and exports the line as the uv_ceti_check JSON field (documented in
  unmw/filter_report_json_format.md). Keep the line free of 'The object was', 'found in',
  'not found' and 'mag brighter than the'. report_transient.sh runs the check in the background
  group with the VSX and asteroid checks; UV_CETI_CHECK=no disables it; with THIS_IS_VAST_TEST
  set it runs only when lib/catalogs/gaia_dr3_nearby exists, so the test suite never sends one
  online query per candidate.
- src/catalogs/local_star_catalog.c: the zone record size is a runtime variable (g_rec_size),
  24 bytes for gaia_dr2/tycho2 and 40 for gaia_dr3_nearby (parallax, its error, RUWE, pmRA,
  pmDec after the old 24 bytes; chosen by the catalog name at finalize, read from
  record_size= at search). The search prints the wide 13-column format whenever a 40-byte
  catalog is involved ('null null' in the proper-motion columns = none in the catalog) and
  -sort=_r orders by distance. The 24-byte catalogs are unchanged; test_local_star_catalog.sh
  covers both layouts.
- ESA Gaia archive, measured 2026-11-09: anonymous asynchronous jobs get executionDuration =
  60 s, a request for a longer one is ignored, and a job running longer ends ABORTED with an
  empty error summary (the installer's first version used 8 async declination bands of
  768000 rows and lost every job this way). Rows are delivered at about 1500 per second; a
  synchronous query of 39000 rows took 28 s and was complete; sync queries of at least 5000
  rows and 55 s worked. COUNT(*) by declination band takes seconds, by source_id range 48 s.
  Synchronous replies are cut at 50000 rows unless the request carries a larger MAXREC
  (MAXREC=1000000 is honoured; without it a band of 85024 sources came back as exactly 50000
  rows, which only the COUNT(*) comparison revealed). The archive answers a request that
  follows another within seconds, and bursts of requests, with HTTP 429 (also for the UV
  Ceti check's queries while a build runs). lib/install_local_copy_of_GaiaDR3_nearby_stars.sh
  therefore uses 100 synchronous equal-area declination bands, counts each band once, cuts
  a band of more than 60000 sources into equal RA pieces (twice as many as the count needs:
  dense Galactic-plane and Magellanic-Cloud bands hold many spurious large parallaxes that
  pass parallax_over_error > 3 and are not spread evenly in RA), requires the rows of the
  pieces to add up to the count (otherwise the band is cleared and gets twice as many pieces
  next run), pauses 15 s between queries and retries every 60 s on 429/5xx; it is resumable
  as long as the band count is kept. Counting every piece recursively (the first version)
  doubled the throttled requests: 5 min per southern band, 6 h for the sky. The first full
  build on tau (2026-11-09, /data_ssd/GaiaDR3_nearby) took about 4 h for 148 queries with
  30 refusals, including a 20-minute spell of HTTP 503 from the archive that the retries
  outlasted, and holds 4697159 records (195 MB) - exactly the whole-sky COUNT(*), which is
  the completeness check to repeat after any rebuild.
- VizieR, 2026-11-09: vizier.cfa.harvard.edu answers plain http with a 301 to https, which
  lib/my_vizquery.sh never followed (curl without -L), so every query there failed and the
  mirror chooser could never pick it; the wrapper now follows redirects keeping the POST body
  (-L --post301 --post302 --post303). The same mirror served complete-but-empty tables for
  every query all day (also for the Gaia DR2 probe of the chooser), which would pass as 'no
  star here': the UV Ceti check runs a control query (any Gaia DR3 star within 5') before it
  trusts an empty reply, and treats a failed control as 'not performed'. When no mirror
  answers, lib/choose_vizier_mirror.sh prints the CDS site, so a 'not performed (VizieR
  (vizier.cds.unistra.fr) ...)' line means 'no mirror answered', not a problem of that site.
- Tests: util/examples/test_nearby_red_dwarf_check.sh has the parts synthetic (default: a
  synthetic 40-byte catalog, no network), local (the real copy: record count 4697159, the
  real stars Aur-05, AD Leo, UV Cet and an empty position, the default source), online (the
  ESA archive and VizieR each on its own, plus the fallback without a copy) and realsky
  (local where a copy is there, online otherwise). test_vast.sh runs synthetic with the
  no-network tests and realsky next to the Gaia DR2 clients test on every machine (asked for
  on 2026-11-09: where there is no local copy the real-sky part uses the ESA archive and
  VizieR, and no test ever downloads the copy); a missing copy is the informational code
  UVCETI_LOCAL_COPY_NOT_INSTALLED, outages are UVCETI_ESA_UNAVAILABLE and
  UVCETI_VIZIER_UNAVAILABLE, all three stripped like the Gaia DR2 client outage codes. The
  synthetic test stars must have consistent BP-RP and G-RP (the first version of the check
  switched to G-RP when the two colours disagreed by more than 1.5 mag, and the first version
  of the test data tripped on that).
- The copy is distributed ready-made: gaia_dr3_nearby.tar.gz (160 MB; gzip, bzip2 saves 4%,
  xz 20% but is not everywhere) from http://tau.kirx.net/vast_catalogs/gaia_dr3_nearby/ and
  http://scan.sai.msu.ru/~kirx/data/gaia_dr3_nearby/ (source files and the deployment notes
  in /home/kirx/gaia_dr3_nearby_dist on tau; the directory on tau is deliberately not under
  vast_test_data/, so the GitHub release rule for test data does not apply).
  lib/install_local_copy_of_GaiaDR3_nearby_stars.sh asks the mirrors first (RU: scan first,
  GAIA_DR3_NEARBY_MIRRORS overrides), accepts an archive only when gzip -t passes, every zone
  file has its index, the zone files add up to records x record_size and there are at least
  4 million records, drops a mirror at once on a 404 or a non-gzip body (an error page sent
  with status 200 would otherwise be fetched three times), resumes a dropped connection, and
  builds from the ESA archive only when no mirror delivers (GAIA_DR3_NEARBY_SOURCE=auto;
  mirror forbids the build, esa skips the mirrors; the retry count and sleep of the ESA
  queries are GAIA_DR3_NEARBY_RETRY_ATTEMPTS/_SLEEP_SEC, handy for a quick failure test). A
  complete copy in the destination is left alone - the first version re-downloaded the whole
  sky from ESA when rerun over a finished copy. Tested with a local python http.server: a
  truncated archive, an HTML stub and a 404 are skipped, the good mirror installs in 2 s, and
  the installed copy passes the local test part.
- Placeholders for 'no value' in the wide search output are the word null, never a number:
  the first version printed 99.999 for an unknown parallax and the check's normalizer took
  every parallax >= 99 mas for it, which silently dropped all stars within 10 pc (AD Leo,
  201 mas, was 'no such star'; the synthetic tests had no parallax above 50 mas, a real-star
  check caught it). The offline test now has a 201 mas star.
- G-RP is no cross-check of BP-RP for M dwarfs: the main sequence is so steep in G-RP at the
  late end that 0.1 mag of colour is 1.5 mag of M_G. UV Cet itself (BP-RP 3.83, G-RP 1.39)
  sits on the locus by BP-RP and 1.6 mag below it by G-RP; the first version of the check
  switched to G-RP whenever the two disagreed by 1.5 mag and called UV Cet a subdwarf or
  composite. Now BP-RP decides for G <= 19.5 and G-RP only for fainter stars or without BP.
  Always try the classical flare stars (AD Leo, UV Cet, both in the online test) after
  touching the classification.

## External-service outages and the test suite: VizieR, UCAC5/plate-solve servers, JPL HORIZONS (2026-11-09)
- test_vast.sh's internet check counted "no VizieR mirror serves Gaia DR2" as "offline" and
  stopped the run before the first section; since the CDS outage of 2026-11-03 every CI system
  test (Ubuntu, macOS, Alpine, WSL2) died there. Only unreachable tau.kirx.net and
  scan.sai.msu.ru stop the run now; a VizieR outage is recorded once as the informational
  VIZIER_UNAVAILABLE, and VizieR is probed again at most hourly (a failed probe takes ~140 s).
  Never let one external service gate the whole run.
- VizieR mirrors hold only some catalogs and answer complete-but-empty tables for the others,
  so lib/choose_vizier_mirror.sh tests a catalog, with a record per catalog: GAIADR2 (default),
  APASS, 2MASS. vizier.idia.ac.za (added 2026-11-09) serves APASS, 2MASS, UCAC5, Gaia DR3,
  GCVS, VSX and the catalogs of the online identification, not the Gaia DR2/EDR3 source tables.
  util/search_databases_with_vizquery.sh uses the 2MASS test, and report_transient.sh decides
  whether to skip it with online_id_vizier_is_unreachable (2MASS), not with VIZIER_UNREACHABLE,
  which is about Gaia DR2 for the known-star check. The search over all catalogs ('may be a
  known variable') needs CDS itself. test_vizier_mirror_record.sh counts four mirror probes.
- 2026-11-23, CDS still down: the factory's 'WARNING: VizieR is unreachable ...' lines are
  commented out at the user's request (they scared the users on every run; re-enable them
  when CDS is back). On tau that warning was misleading anyway: VIZIER_UNREACHABLE is about
  the Gaia DR2 table, while tau's known-star check reads the local copy and the online
  identification ran through IDIA. Measured coverage of the 12 catalogs of the online
  identification: IDIA returned rows for 11; J/A+A/648/A44 (Mowlavi+ 2021) returned none on
  either mirror in a 10' bulge cone (inconclusive). vizier.cfa.harvard.edu now returns real
  rows for 2MASS, GCVS, VSX, J/AcA/61/1 and I/358/vclassre but empty tables for the other
  seven: never add it to the 2MASS probe list - the probe would pass and those catalogs would
  silently find nothing. Non-VizieR sources checked the same day: the ESA Gaia archive has
  2MASS (gaiadr1.tmass_original_valid) and every gaiadr3.vari_* table, and IRSA's cone search
  (SCS table fp_psc) serves 2MASS. (ESA TAP fails 'WHERE x IN (...)' with HTTP 500 - use OR.)
- Since 2026-11-23 util/search_databases_with_vizquery.sh asks the ESA Gaia archive first for
  2MASS (gaiadr1.tmass_original_valid), the Gaia DR3 cone (gaiadr3.gaia_source) and the Gaia DR3
  variability lookup (ONE query: vari_summary JOIN gaia_source LEFT JOIN
  vari_classifier_result, replacing the two VizieR queries varisum + vclassre); VizieR is the
  fallback (esa_gaia_archive_csv exit 1) and stays the only source of the other catalogs. The
  ESA rows are printed in VizieR's exact formats (%.3f, %015.11f, %+.11f, %.6f; a missing value
  as '-', shown as nothing) so the old parsing loops are untouched. Checked on the 12
  STANDALONEDBSCRIPT positions of test_vast.sh against the old script on IDIA: identical summary
  lines; only two distances differ by 0.001" (VizieR measures from another epoch). ESA first
  took 11-26 s per position, VizieR alone 32-51 s. When no mirror answers the 2MASS probe (or
  SEARCH_DATABASES_SKIP_VIZIER=yes) no VizieR query is made at all; SEARCH_DATABASES_SKIP_ESA=yes
  forces the VizieR path; exit code 3 = neither service searched Gaia DR3, and only then does
  report_transient.sh print 'online_id skipped: neither VizieR nor the ESA Gaia archive answers'.
  Pitfalls met: an empty ESA reply piped through the converter became a fake Gaia row (guard
  NF >= 6); lib/hms2deg prints RA and Dec on two lines and fails on decimal input; ORDER BY a
  computed alias (phot_g_mean_mag + 0 AS gmag_order) so that TOP + ORDER BY cannot make the
  archive scan the magnitude index. Do not run 'make' while comparing script runs: the
  rebuilt lib/hms2deg and lib/deg2hms vanish for a moment and the lookup fails to parse its
  coordinates.
- lib/install_local_copy_of_GaiaDR2.sh (2026-11-23) downloads the ready-made 13 GB copy from
  the VaST mirrors (scan.sai.msu.ru/~kirx/data/gaia_dr2, tau.kirx.net/vast_catalogs/gaia_dr2:
  the 1801 files as they are plus MD5SUM.txt) before it falls back to the 588 GB ESA build;
  per-file md5, resumable, GAIA_DR2_SOURCE=auto|mirror|esa. Tested against a local http.server
  mirror: full install, rerun, resume, a missing mirror skipped. The list for tau's copy is
  /home/kirx/gaia_dr2_dist/MD5SUM.txt; publishing it is up to the user (DEPLOY note there).
  GitHub releases would not do as a mirror: at most 1000 assets per release.
- One failing server must not produce an ERROR line while another server may still answer:
  every ERROR marks the field as failed on the unmw summary page. On 2026-11-09 the UCAC5 search
  and the plate-solve CGIs of scan.sai.msu.ru answered HTTP 500. solve_plate_with_UCAC5 took
  the 16-line error page for a catalog reply (it counted lines), matched no star and stopped
  without asking vast/tau ("ERROR running vizquery" although VizieR was not asked); now curl
  runs with --fail and a reply needs >=5 catalog data lines. util/identify.sh
  (= wcs_image_calibration.sh) printed ERROR and the raw error page before trying the next
  server; the page's </body></html> broke the HTML validation of the transient report. Now a
  WARNING and the reply made safe (no tags, no 'ERROR'), as already done for the WCS header.
  Machines with a local UCAC5 copy and solve-field are not affected.
- JPL HORIZONS has answered every TLIST request with "LTP: input TIM outside +-500K range"
  since the evening of 2026-11-09 MST (production still got its moons at 23:39 UTC on 11-09;
  failing from 03:40 UTC on 11-10), for any date and time format, also via the kirx.net proxy,
  while START_TIME/STOP_TIME works. util/planets.sh, moons.sh, spacecraft.sh and comets.sh now
  ask START_TIME='JD..', STOP_TIME=+0.0007 d, STEP_SIZE='1 m' and use the first row after
  $$SOE. The failure was silent: the scripts print nothing for an object they cannot get, so
  moons and spacecraft (always from HORIZONS) and planets and comets (from HORIZONS only when
  skyfield is missing) just stopped being identified. The Saturn/Iapetus 2, Venus and
  STEREO-A Ceres tests caught it.

## vast.sai.msu.ru / kirx.net dependencies, vsx.dat second mirror (2026-11-11)
- vsx.dat is now tried at LOCAL_SERVER, then ALTERNATIVE_SERVER, then CDS FTP (it used to
  be LOCAL_SERVER then CDS, so outside Russia kirx.net was the only mirror). Both mirrors
  serve the same 370150125-byte vsx.dat.gz. CDS timed out over FTP and HTTPS from tau that
  day. Tested in a scratch copy with VAST_COUNTRY_CODE=US, CATALOG_DOWNLOAD_ATTEMPTS=1 and
  VAST_CURL_PROXY="--resolve kirx.net:443:192.0.2.1": kirx.net times out after ~50 s, scan
  delivers, the 2.1 GB catalog installs, 136 s in all. The updater refuses to start without
  lib/catalogs/create_tycho2_list_of_bright_stars_to_exclude_from_transient_search, so a
  scratch copy needs it (and the BSC/Tycho-2 files) linked in.
- The Bright Star Catalogue (end of the same script) is now tried at LOCAL_SERVER, then
  ALTERNATIVE_SERVER, with --fail (it was LOCAL_SERVER only, so kirx.net only outside Russia,
  and an HTTP error page got saved as the catalog). The mirrors serve identical copies (md5
  bdb7b7c1...). A download is installed only if at least 9000 records carry a well-formed
  J2000 position in bytes 76-90 (the complete catalog: 9110 records, 9096 with a position);
  the lines are of varying length, so a line-length test would reject the real file. A
  complete copy on disk is reused when only the derived lists are missing, and a missing
  all-star list (bright_star_catalog_radeconly.txt) now triggers the rebuild too. Tested with
  a TLS stub (openssl s_server -WWW behind curl --connect-to) that answers HTTP 200 with an
  error page: rejected, scan used. Rebuilding the two lists takes ~27 s (a bash read loop).
- Every 'make' touches every file in the tree (lib/check_external_programs.sh, skipped only
  when out*.dat lightcurves are present), including lib/catalogs/vsx.dat, asassnv.csv and
  astorb.dat. That restarts the 50-day refresh clock of lib/update_offline_catalogs.sh, so a
  copy rebuilt more often than every 50 days never refreshes these catalogs by age.
- Probing the remote services by hand: the plate-solve CGI accepts only uploads named
  out[A-Za-z0-9]+.xyls (any other name gets "ERROR: Invalid filename" with HTTP 200), and
  pokaz_laflerkinman.sh keeps only the servers that answer over https if any does - vast has
  no https, so the ./lc L key reaches it only when tau and scan both fail over https.
- State on 2026-11-11: period search, UCAC5 and plate solving all worked on tau, scan and
  vast (vast runs an older plate-solve CGI and is the slowest; util/identify.sh does not list
  it for plate solving). kirx.net/polaris runs its own working period-search service that is
  in none of VaST's lists; kirx.net/ticaariel is gone.

## System test on tau 2026-11-12 (97952d25): dead CDS host names, CI vizquery gate
- Set-up: fresh clone in /tmp/vast, test data reflink-copied from /home/kirx/vast_test,
  lib/catalogs/ucac5, gaia_dr2 and gaia_dr3_nearby linked to /data_ssd as in the dev copy,
  nice 10 (the nightly search was running), stdin </dev/null, no DISPLAY, and no
  ../THIS_IS_HPCC (that file makes the suite e-mail its report). 149 of 153 sections
  passed in 289.7 min.
- simbad.u-strasbg.fr, vizier.u-strasbg.fr and aladin.u-strasbg.fr have had no address
  records since the u-strasbg.fr zone change of 2026-11-10 (cdsarc. and cdsweb.u-strasbg.fr
  still resolve; the CDS names kept changing afterwards, see the 2026-11-25 Aladin Lite
  section). The transient report links (util/transients/report_transient.sh) and the
  SIMBAD query of util/search_databases_with_curl.sh now use the cds.unistra.fr names; plain
  http works there without a redirect, which matters for old curl and for the POST. unmw's
  filter_report.py recognises both names, as older reports keep the old ones. Both selenium
  report tests failed on the dead SIMBAD link; while CDS serves its 'Page unavailable' page
  (HTTP 404) the cds.unistra.fr links fail too, so both tests now have cds.unistra.fr in
  FLAKY_LINK_PATTERNS next to minorplanetcenter.net: such a failure is logged as a warning
  and does not fail the test (each failing link still costs 2 x 120 s of retries). A passing
  test's output file is now deleted (the rm had a truncated file name, so none ever was);
  its [WARNING] lines are first copied into DEBUG_OUTPUT under '<code> passed with warnings',
  so the report still shows the flaky links that failed.
- The vizquery test (GitHub Actions only) ended every CI system test 14 minutes in while CDS
  was down (fail_early on VIZQUERYTEST004a_NO_END). It is now not performed, with the
  stripped code VIZQUERYTEST_VIZIER_UNAVAILABLE, when the internet check found VizieR
  unavailable.
- The UCAC5 VizieR fallback of solve_plate_with_UCAC5.c asked lib/choose_vizier_mirror.sh with
  the default Gaia DR2 test, so while CDS was down it got CDS, although vizier.idia.ac.za
  serves UCAC5. It now asks with a UCAC5 test. But IDIA fails most UCAC5 queries that name
  some of the columns with -out=..., the solver's own among them: its eight-column list query
  got one row per target holding nothing but the target position (the 1226 lines that the CI
  test's 2000-position list got from IDIA were such rows, not an answer), a single-position
  query gets an empty table, and the VOTable form says '(pipe) Request has been interrupted'.
  Which lists fail is unclear (all columns in any order worked, so did all but SrcIDgaia, all
  but Kmag did not); UCAC4, APASS, 2MASS and Gaia DR3 queries with -out= work. A query for all
  columns always worked, so the solver now asks for all columns as tab-separated values
  (-mime=tsv -out.all) and select_columns_from_vizier_tsv_reply() writes the columns
  read_UCAC5_from_vizquery() reads, found by name in the header line that VizieR repeats for
  every target with a match; the chooser's UCAC5 test asks the same way. A valid reply without
  any match counts as zero stars, an empty reply or an error page as a failed query, and a
  last line without its newline (a cut-off reply) is dropped.
  Checked end to end on 2026-11-12 in a scratch build with the local UCAC5 copy removed and
  our three UCAC5 servers renamed to unresolvable hosts: on a 9576x6388 Texas Tech frame the
  chooser picked IDIA in 2 s, 926 and 925 of the 1000 query stars matched in the two passes,
  and the catalog positions (proper motion applied) of all 923 stars used agreed with those
  of a run on the local UCAC5 copy to within 0.001 arcsec. The solve took 7.8-10.3 min
  instead of 4.8 min with the local copy.
  Not changed: the CI vizquery test still sends the eight-column query with the default test
  (so it can only pass at CDS), and the Pan-STARRS1 query still uses VIZIER_SITE (IDIA
  returns no PS1 rows either way).
- Outside VaST that day: GCVS at www.sai.msu.su answered 2 of 4 direct queries (17-30 s), the
  others reset after 68 s or hung past 120 s. scan's PA sky_archive CGI sent 727 bytes and
  then hung. All
  ~kirx directory listings on kirx.net answer 403 (the files themselves download), as they
  did on 2026-10-21. Cause, as far as can be seen from outside: polaris refuses *.php* files
  server-wide (a FilesMatch with 'Require all denied' in conf-enabled), Debian's DirectoryIndex
  lists index.php, and mod_dir answers a directory with the 403 of its index.php look-up
  instead of letting mod_autoindex list it, so Options +Indexes alone cannot help. Signature:
  a missing .php file gives 403 where a missing .txt gives 404, and OPTIONS on the directory
  gives 403. Fixed on polaris the same day, keeping the PHP ban:
  /etc/apache2/conf-available/kirx-userdir-listing.conf (enabled with a2enconf) gives
  <Directory /home/kirx/public_html> 'DirectoryIndex index.html index.htm' and
  'Options +Indexes'; the listing works again and .php URLs still get 403. Nothing in VaST
  reads these listings; only the AUXWEB_INDEX_KIRX_PARENT_DIR_MISSING check does.
- unmw's pytest suite does not start on this machine's Python 3.14: it needs the cgi module
  (legacy-cgi), which is not installed here and not in requirements-test.txt.
- CI after the gate (Ubuntu runs 43269700500 at fbdcc6b4 and 43280965083 at 71d7b86c, the
  first Ubuntu runs to reach the end since 2026-10-22): both ran to the end (243.7 and
  215.7 min) and exited 1 only on AUXWEB_PASKYARCHIVE_001-003; 002 and 003 followed from 001
  (the empty match file left the PNG download without a URL: 'curl: (2) no URL
  specified'), so they now run only when 001 found the image (the same for the NMW sky
  archive's AUXWEB_NMWSKYARCHIVE_002/003). NMWNVUL24ST_SELENIUM_TEST
  (SIMBAD 404; the next link, VizieR, gives the same 404) and all the VizieR codes are
  stripped before the exit decision. The PA check has failed since 2026-10-23 (WSL run
  39915054811; it last passed in Ubuntu run 39795286462 on 10-22), unseen in Ubuntu CI
  because no Ubuntu run reached that section in between. Signature: HTTP 200 and 727 bytes
  within 1 s listing one plate (SCA1017N), then nothing until scan closes the reply about
  320 s after the request (curl exit 18), well inside the test's 900 s. The expected
  plate's FITS file downloads from the archive at once; where the CGI blocks cannot be seen
  from outside. The new UCAC5 VizieR fallback got no CI coverage: all 183 UCAC5 searches
  were answered by our own servers; APASS used IDIA through the chooser (6 queries, all
  fine).
  The report upload's 'unexpected reply from the server' is in every CI run that reached the
  end since at least 2026-08-19, passing runs included: vasttestreport.php is no longer run
  as PHP on scan (a GET returns its source), so no report has been mailed. Even when it ran,
  its success reply was a single space (the file ends with '?> '), so the check for 'Thanks
  for the submission!' could never pass. The result does not affect the exit code.
  PHP-free replacements were written on 2026-11-12/13 (Python CGI programs in scan's cgi-bin,
  mapped to the old .php URLs with ScriptAlias; kept outside this repository) for
  vasttestreport.php, vastemail.php (the mailing-list form of doc/README.html) and
  anyemailkirx.php (used only by test_vast.sh of 2019-05-08). They went live on scan on
  2026-11-17, together with a rule that refuses every other .php file there (403 instead of
  the source), so the report upload should pass from then on; if 'unexpected reply from the
  server' comes back, look at scan first. For a
  report link during the outage: simbad.cfa.harvard.edu has V0615 Vul (PNV
  J19430751+2100204), simbad.idia.ac.za does not.

## Closed-roof detection: util/detect_closed_roof and the OBSERVATORY ROOF CLOSED alert (2026-11-15)
- Problem: the NMW-TexasTech roof sometimes closes without NINA knowing, and NINA keeps
  imaging the inside of the roof (13 nights between 2026-10-03 and 2026-11-13, both cameras,
  often only one of them). Such runs used to end as "less than 4 images processed", or as
  "passing clouds" when the roof moved between the two frames, and nobody was alerted.
- What the frames look like (a year of logs plus all raw frames that were still on disk):
  median(raw - matched master dark) is -1..+6 ADU (up to +18 ADU with moonlight or dawn
  leaking in), the pixel noise is the read noise (5-7 ADU), and there are 0-1 star-like peaks.
  The faintest open-roof sky in 11 months was +268 ADU (TTUQ2) / +326 ADU (TTUQ1) above the
  dark at 20 s, and every open frame had thousands of peaks. TTUQ2 closed frames sit 0.2-1 ADU
  BELOW their dark (bias offset), TTUQ1 ones 1-4 ADU above: that is why ms.c's
  "dark mean >= image mean" ERROR fires mostly for TTUQ2 (79 of 97 closed frames) and only
  occasionally for TTUQ1 (10 of 62) - do not use it as a roof indicator.
- util/detect_closed_roof [-n MAX_STARS] [-r ADU_PER_SEC] [-b ADU] [-s MAX_NOISE_ADU] [-v] image [dark] prints
  one line "VERDICT key=value ..." (OK, CLOSED_ROOF, NO_STARS, PARTLY_DARK); exit 0/1/2.
  Star-like peak: local maximum > 5 sigma above the 128-255 px tile median, with >= 6 of 8
  neighbours > 2 sigma (the neighbour rule rejects hot pixels and cosmic rays; a global
  background instead of the tiles gives thousands of false peaks on closed frames).
  The background limit is 5 ADU/s x EXPTIME (100 ADU at 20 s). Validated on all 1928 surviving
  raw frames of 2026-11-10..13: 34/34 closed -> CLOSED_ROOF, 1889/1889 open -> OK, both
  partly lit frames -> PARTLY_DARK (with the dark); without a dark closed -> NO_STARS.
- util/ccd/ms stores |image - dark|, so in an already dark-subtracted frame (HISTORY
  "Dark frame subtraction:") with a background near zero the noise is folded at zero: median
  and MAD then underestimate the noise (and are coarsely quantized: medians of 3 or 4 ADU) and
  ~20-230 folded noise peaks pass for stars. The tool measures the noise of such tiles as the
  clipped RMS around zero instead (closed fd_ frames: 0-5 peaks).
- Do not use src/quickselect.c on pixel data: it is quadratic in the number of equal values
  (minutes for a 61 Mpix integer frame). detect_closed_roof has its own three-way-partition
  quickselect; it reads the image strip by strip (one row of tiles + 2 rows), about 20 MB of
  RAM and 0.8 s per 61 Mpix frame with a dark.
- transient_factory_test31.sh runs the check after the Mean value check (new images only,
  never the references) when CHECK_FOR_CLOSED_ROOF=yes (default for TTUQ1b1x1/TTUQ2b1x1 only).
  The dark comes from util/find_best_dark.sh; if nothing matches the temperature/exposure,
  find_any_dark_frame_of_the_same_size_as_image() takes the newest dark of the same size (the
  bias level changes by only a few ADU between set-points). If the LATEST new image (by JD) is
  CLOSED_ROOF, the field gets the banner "***** ACTION NEEDED - OBSERVATORY ROOF CLOSED? *****"
  in transient_factory.log plus "ERROR: OBSERVATORY ROOF CLOSED? ..." in the filtering log and
  is skipped (7 s instead of 33 s of failing VaST runs and blind solves). Other cases (roof
  opening during the pair, part of the field dark, no stars on a bright background, no dark)
  get their own ERROR without that phrase. "OBSERVATORY ROOF CLOSED" is a cross-repo contract:
  unmw greps it to send the Slack alert, so no other message may contain it (only the two echo
  lines of closed_roof_check_report_closed_roof do). The per-image part is the function
  closed_roof_check_inspect_new_images; the "too few refereence images" branch calls it too, so
  a closed roof is reported (and alerted) also for fields without reference images (For-03,
  Scl-04): there only the alert case replaces the usual error, the field stays NOREF otherwise.
- Tests: the "Test detect_closed_roof tool" block of test_vast.sh (runs on GitHub CI too; it
  also checks that exactly two non-comment echo lines of the factory carry the contract phrase)
  and util/examples/test_closed_roof_check.sh (factory level, about 3.3 min, not on CI). Data:
  NMW-TexasTech__closed_roof_test.tar.bz2 - 1024x1024 crops of real closed, open, partly lit,
  cloudy and already calibrated frames of both cameras with dark crops cut at the same pixels and
  2 reference crops; its README.txt lists the expected verdict of every file. Raw img_* directories
  are pruned after a few days, so new real cases must be saved promptly.
- Review fixes (2026-11-15): util/find_best_dark.sh echoed the input image path to stdout
  (a grep without -q in its fitsverify fallback), so a frame failing fitsverify got its own
  path as "the dark": image - image = 0 looked like a closed roof, and in
  try_to_calibrate_the_input_frame the two-line DARK_FRAME broke the dark subtraction. The
  check now trusts find_best_dark.sh output only when it exits 0 and never compares an image
  with itself; the tool also refuses an image identical to its dark. A dark that does not
  match the camera settings (other OFFSET/readout mode) is the remaining false-alarm risk:
  if its level is far above the image, bright overcast can come out near "the dark level".
  The tool therefore sets zero_level=mismatch (no CLOSED_ROOF) when the background is more
  than max(3 sigma, half the limit) below the dark, or - with -s, CLOSED_ROOF_CHECK_MAX_NOISE_ADU,
  15 ADU for the TTU cameras - when a starless frame at the dark level is noisier than a frame
  without sky light can be (closed 4.4-7.4 ADU, faintest open sky 35.6 ADU in the sweep).
  Re-validated with the final binary called as the pipeline calls it (matching dark, -s 15):
  1928/1928 surviving frames of 2026-11-10..13 got the expected verdict, and the mismatch rule
  never fired on a real frame.

## APASS via ESA TAP, Gaia synthetic photometry facts, ESA and CDS down together (2026-11-23)
- Review of 2518cd35 (lib/apass_esa_tap.sh, search_APASS() and read_APASS_from_esa_tap() in
  src/solve_plate_with_UCAC5.c). ESA TAP was in maintenance all day, so the client has still
  not been run against the live archive. Its query ordered by table-qualified names (ORDER BY
  t.target_id, a.vmag, a.recno); the ARI Gaia TAP service, which has the same Gaia tables
  (https://gaia.ari.uni-heidelberg.de/tap/sync), answers that with HTTP 400 'Encountered "."',
  refuses a name two joined tables share (source_id: 'unresolved identifiers') and accepts
  column positions and names unique in the join. Fixed the same day: ORDER BY target_id, vmag,
  recno. Check on ESA before trusting the ESA path.
- A TAP client can be tried on ARI while ESA is down even when ARI lacks the table: a curl
  wrapper first in PATH swaps the URL, adds a second upload (a small VOTable) as
  tap_upload.apass and renames the table in the QUERY field. The client as committed got the
  HTTP 400 above; the fixed one got HTTP 200 in 0.6 s with the header line it checks for and
  the right row per position (brightest first, recno as the tie-break, a NULL as an empty CSV
  field). Two uploads are written UPLOAD=a,param:x;b,param:y and that field needs curl
  --form-string: --form cuts the value at the semicolon. A join of two uploaded tables is
  fast on ARI; only joins with gaia_source hang (see below).
- How it was checked offline: a curl script placed first in PATH that passes every request
  to /usr/bin/curl except the ESA URL, saves the uploaded VOTable and writes a prepared CSV to
  the -o file; a reply with V = 10 + target_id/1000 shows at once whether each star received
  its own row (it did, 1000 of 1000 on the TESS Nova Vul reference frame). Replacing
  lib/vizquery by 'cat prepared_output' in a scratch clone drives the VizieR reader the same
  way; both readers wrote byte-identical catalogs from the same values. The solver takes 5 s
  on that frame once wcs_* exists; move the old *.wcscat.ucac5 away or it skips the lookup.
- The ESA maintenance page comes with HTTP 200, and CDS was down at the same time (its page:
  'Page unavailable - CDS', HTTP 404). The photometric lookup of that frame then took about
  7 minutes to fail (ESA 1 s, 4 APASS and 4 Pan-STARRS1 attempts). The mirror chooser picked
  vizier.idia.ac.za for APASS: its single-cone probe passes, but the 1000-position list query
  returns nothing (20 positions take 37 s, a list of 150 is dropped after 80 s).
  vizier.cfa.harvard.edu answers a list query at once with a complete but empty table. A
  passed probe does not mean the list query works.
- The solver sends the 1000 brightest good UCAC5-matched stars to the photometric lookup
  (stars are sorted by instrumental magnitude; MAX_STARS_IN_LOCAL_CAT_QUERY), although the
  local UCAC5 match uses up to 5000. On the TESS frame 15 of the 20 brightest have no APASS
  source within the 35.4 arcsec cone: APASS is empty where these cameras need it.
- Gaia DR3 synthetic photometry (gaiadr3.synthetic_photometry_gspc, VizieR I/360/syntphot),
  measured on ARI: the per-band flag is 1 only inside the validated range - G >= 10.80 for
  B, V, R, I (B also needs 0.50 <= BP-RP <= 1.70) and G >= 14.20 for g, r, i - so a flag = 1
  requirement removes every bright comparison star. Magnitudes exist only for flux/error > 30
  (formal error at most 0.036 mag, about 0.001 mag for bright stars). The 44 bulk files
  (42.0 GB, _MD5SUM.txt) have no coordinates and are not in sky order; coordinates need the
  gaia_source bulk files (3386 files, 753.0 GB), which are named by HEALPix level-8 ranges,
  and source_id >> 43 is that pixel (checked on three sources). ARI answers a cone on
  gaia_source joined to the GSPC in seconds when the cone is small (2 deg radius, G < 14.5:
  8709 rows in 25 s) but not one the size of a TESS frame (8.5 deg, G < 10.5: nothing in
  170 s), and did not finish a join of gaia_source with an uploaded table in 120 s (two
  positions) or 300 s (1000 positions). Details and the plan: doc/gaia_synthetic_photometry_handoff.md.
- awk: a comparison in a print or printf argument list needs parentheses. mawk (the default
  awk of Debian and Ubuntu) takes any '>' there as output redirection, also the one of '>=',
  and stops with a syntax error (scan.c, case SC_GT); POSIX does not allow unparenthesized
  comparisons in a print expression list at all. gawk accepts them, so tau does not show it.
  Write printf "%d", (a >= 20), not printf "%d", a >= 20. The altitude mask of the bright-star
  check (BRIGHT_STAR_CHECK_IMAGE_MASK in transient_factory_test31.sh, a1a03975) was such a
  line: under mawk the mask would come out empty and src/vast.c would skip the check without
  a message. Fixed 2026-11-23; it could not be run under mawk here (tau has only gawk, and
  'docker run' fails on tau with a containerd shim error).
- Bright-star check of a1a03975 on the Gem-03-Q1b1x1 test field: the unmodified new images
  have 87 percent of the reference star count (the clear Aql-03-Q1b1x1 test pair, taken 28
  degrees above the horizon, has 49 and 51 percent); uniform extinction simulated by dimming all
  sources at constant sky noise gives 26 percent at 1 mag, 9.4 percent at 2 mag and 3 percent
  at 3 mag, so the 10 percent limit means about 2 mag of cloud. The camera settings come from
  the input path: a test directory needs Q1b1x1 or Q2b1x1 in its name or the check never runs.
- An image without stars never gets a star catalog. autodetect_aperture() finds no star to
  measure the seeing from, writes the aperture 0.0 to imageNNNNN.cat.aperture, warns that
  'the estimated aperture is unrealistically small' and returns before the main SExtractor
  run. count_bright_stars() in src/vast.c took the missing catalog for 'cannot tell'
  ('Bright-star check: unavailable for ...'), so two starless new images went on to the star
  matching, the pointing check with its blind plate solution and the passes with fainter
  stars. Fixed 2026-11-23: with no catalog it reads the aperture file - an aperture below one
  pixel means no stars (0), no aperture file means SExtractor failed (unknown); a catalog
  that exists and is empty is 0 too, one whose lines cannot be parsed stays unknown. A
  reference image without stars still gives 'unavailable': the check never rejects on a
  reference it cannot use.
- Tests added 2026-11-23, all runnable alone and called from test_vast.sh:
  util/examples/test_bright_star_check.sh - VaST on the crops of the closed-roof dataset as
  the factory runs its bright-star pass (17 runs in 9 s, everywhere), then two factory runs
  on the closed-roof frames with CHECK_FOR_CLOSED_ROOF=no (2 s; left out on GitHub Actions
  with BRIGHT_STAR_CHECK_TEST_SKIP_FACTORY_RUNS=yes). Star counts of that pass on the crops,
  SExtractor 2.19.5 on tau: the two Pup-02 references 500 and 497, Lac-01 743, And-05 277,
  Com-03 57, the partly dark Com-01 14, the closed-roof and the overcast Dra-07 frames 0.
  The two reference crops overlap only in part, so VaST ends such a four-image run with exit
  code 1 after the check - the test looks at the check lines and at 'Matching stars between
  images', not at the exit code of a run that passed.
  util/examples/test_apass_esa_tap.sh - the ESA client against canned replies (everywhere)
  and util/solve_plate_with_UCAC5 on wcs_fd_Per3_2011-10-31_001.fts (only with the local
  UCAC5 copy; 1000 positions, radius 23.4 arcsec, 50 s for five runs). The curl stand-in also
  answers the vizquery requests (lib/my_vizquery.sh calls curl from PATH): '#END#   ' alone
  is a complete reply without stars, which the solver does not retry. VIZIER_MIRROR_RECORD_ONLY=yes
  keeps lib/choose_vizier_mirror.sh from probing through the stand-in and from recording the
  result in lib/catalogs. The returned magnitudes encode the position number (V = base +
  N/1000, base 10 for ESA, 13 for VizieR), which shows which position and which service a
  magnitude in the output catalog came from. The VizieR reader gives a row to every matched
  star in a box around the position, so the two readers need not write identical catalogs
  on a crowded frame; the test asks the ESA path for the exact assignment and the VizieR
  path only for VizieR values. The solver leaves image_pid<PID>.cat.aperture and .sex_log
  files in the VaST directory (the test removes its own).
  util/examples/test_transient_altaz.sh now also runs the factory's own mask line with the
  awk of the system; it was not called from anywhere before.
  test_closed_roof_check.sh takes 5 s instead of 3.3 min: in its runs without a dark frame
  and with the check switched off the bright-star check now stops the starless images.
- ESA came back at 17:34 UTC on 2026-11-23 (the VOSI availability endpoint
  /tap-server/tap/availability says <available>true</available>; during the maintenance the
  sync endpoint served the HTML page with HTTP 200). lib/apass_esa_tap.sh live: right columns,
  right reply format, values identical to VizieR (IDIA) for the 3 of 3 stars both had among
  the first 20 TESS positions. But the upload join costs about 5 s + 0.12 s per position at
  35.4 arcsec (0.06 s at 10 arcsec), and ESA ends a sync query after about 60 s with HTTP 408
  (body: QUERY_STATUS ERROR 'Job timeout/aborted.'), so the 1000 positions the solver sends
  always fail and the solver goes on with VizieR. Exchanging POINT and CIRCLE is slower on
  ESA and does not help on GAVO. A field cone without upload is fast: APASS, 4 deg
  around the TESS field, 17331 rows in 5.0 s. 16 queries spaced 15-25 s apart got no 429.
- Gaia DR3 on ESA, live: an upload join with gaiadr3.gaia_source costs about 0.5 s per
  position (100 positions, 3 arcsec, G < 14.5: 52 s; with the synthetic photometry joined
  too: 408). Lookups by source_id are fast (98 uploaded ids in 10.6 s), and so is a field
  cone on gaia_source joined to the synthetic photometry (2 deg, G < 14.5: 8709 rows in 5.7 s,
  ARI 25 s).
- Who else serves the two catalogs over TAP (GAVO RegTAP search of table names and
  descriptions, http://reg.g-vo.org/tap, plus direct tap_schema queries): APASS DR9 at CDS
  TAPVizieR (II/336/apass9) and SkyMapper (https://api.skymapper.nci.org.au/public/tap,
  ext.apass_dr9, the very same rows and values as ESA, VizieR column names gmag/rmag/imag, no
  table upload, 4 deg cone in 19.5 s); APASS DR10 at GAVO (http://dc.g-vo.org/tap,
  apass.dr10: another release, other values, errors its own notes call overly pessimistic;
  uploads accepted but sync queries stop at 20 s and an async job stayed QUEUED for 7 min).
  Gaia synthetic photometry: ARI and AIP (the ESA table names; AIP did not answer that day)
  and CDS TAPVizieR I/360/syntphot (positions in the same table; down that day). ARI, AIP and
  IRSA hold only Gaia-APASS cross-match tables, not APASS magnitudes; NOIRLab Data Lab and
  MAST have neither catalog; JVO's Gaia TAP (jvo.nao.ac.jp/skynode/do/tap/gaia) lists no data
  tables; SSDC (gaiaportal.ssdc.asi.it) answers 403. ESA's own list of Gaia partner data
  centres is AIP, ARI, SSDC and JVO.
- GAVO UWS jobs: the job URL is in the Location header of the creation reply
  (http://dc.g-vo.org/__system__/tap/run/async/<id>, not /tap/async/<id>); PHASE=RUN in the
  creation form did not start the job, a separate POST PHASE=RUN to <job>/phase did. Delete
  jobs with POST ACTION=DELETE to the job URL.
- ADQL magnitude conditions must not be able to use a magnitude index: with `vmag BETWEEN a
  AND b` (or `vmag < b`) the database behind ESA's external.apassdr9 scanned by magnitude
  for one of four equal 4-degree tiles of the TESS field and hit the 60 s limit even for
  COUNT(*), which takes 1.4 s with `vmag + 0 BETWEEN a AND b`; one cone over the whole
  8.27-degree field went from HTTP 408 to 11.4 s (83,722 rows). SkyMapper's copy: 19.5 s ->
  1.9 s for a 4-degree cone. Gaia: write `phot_g_mean_mag + 0 < x`. The same rewrite speeds
  the per-position upload join up only a little (0.12 -> 0.08 s per position).
- Request shapes measured on ESA on 2026-11-23 (TESS field, 1000 positions): four parallel
  upload batches of 250 positions finished in 30.7 s with no 429; back-to-back requests and
  four parallel ones were never refused that day (on 11-09 they were). Gaia field cone
  (gaia_source joined to the synthetic photometry, 8.27 deg, G + 0 < 13.5): 150,562 rows in
  84 s with seven bands (59 MB), 34 s with one band and 1.0857*flux_error/flux computed in
  ADQL (25 MB), 31 s as four parallel tiles. A 0.25-degree field: APASS 350 rows in 0.85 s,
  Gaia (G < 20) 2454 rows in 9 s. ARI did not answer a 4-degree Gaia cone within 60 s.
- A field cone matched locally with the rule of the current APASS queries (brightest V with
  B, r', i' present, within the radius) gave exactly the rows of the ESA upload join, 319 of
  319 for the 1000 TESS positions: the matching can move into the solver without changing
  results.
- The solver's APASS Cousins I was 0.42 mag too faint: set_apass_photometry() and the
  Pan-STARRS1 reader computed Ic = Rc - (r - i) + 0.21, while Jester et al. (2005) give
  R - I = 1.00 (r - i) + 0.21, i.e. Ic = Rc - (r - i) - 0.21 (formula unchanged since the
  initial commit). Against Gaia synthetic photometry, 26,420 TESS-field stars: B, V, g', r',
  i' within 0.02 mag, Rc -0.044, Ic +0.367 (-0.053 with the paper's sign). Every APASS_I
  calibration (TICA TESS) was affected. Fixed on 2026-11-23 on the user's request. The
  three TESS sections of test_vast.sh calibrate with APASS_I, and their expectations were
  shifted by exactly -0.42 mag (a pure zero-point shift of the I-band zero_point
  calibration): TICATESSFINDNVUL240110a 9.[7-9] -> 9.[2-5], the reference image limiting
  magnitude of the calibration failure test 15.77 -> 15.35 and of the zero RA test
  16.46 -> 16.04, and the six candidate magnitudes of the zero RA test (taken from the
  values recorded in its comments). The last two sections are skipped on GitHub Actions,
  which is why a plain grep for APASS_I in the test did not show them: grep for
  "limiting mag" and for the candidate lines too. util/examples/test_apass_esa_tap.sh had
  copied the wrong formula into its own check of the solver output.
- Positional outlier cut tried on the TESS frame (offsets catalogue minus measured position,
  median and 1.4826*MAD per axis, elliptical 5-sigma cut): APASS sigma 2.4 arcsec, 43 of 323
  matches rejected, 39 of them photometric outliers; Gaia 23 of 974 rejected, 16 photometric
  outliers. Against UCAC5 positions the core is 0.2-0.3 arcsec (APASS) and 0.02-0.03 arcsec
  (Gaia - UCAC5 is reduced with Gaia DR1), too narrow for a sigma cut without exact epochs.
  Gaia matched 974 of the 1000 TESS reference stars, APASS 319; I-band zero-point scatter
  0.10 mag with Gaia, 0.27 mag with APASS.

## Photometric field catalogs: APASS and Gaia fetched per field, matched in the solver (2026-11-23)

- lib/photometric_field_catalog.sh fetches the catalog stars around the good reference stars
  (one cone, four in parallel for a field wider than VAST_FIELD_CATALOG_TILE_RADIUS_DEG=4 in
  radius; Gaia cones 60 arcsec wider for proper motions) and writes one normalized table;
  search_photometric_field_catalog() in src/solve_plate_with_UCAC5.c matches it. Providers:
  APASS esa, skymapper; Gaia esa, ari (VAST_FIELD_CATALOG_PROVIDERS overrides). Exit codes:
  0 table written (possibly empty), 1 bad arguments, 2 no provider delivered. A complete table
  with < 4 matches makes the solver skip the VizieR APASS list query (same catalog) and go to
  Pan-STARRS1. The list queries keep the 1000-star limit (user: drop it only where the search
  goes through a cone).
- Matching rule kept from the list queries on the user's request: the brightest catalog star
  within the search radius and magnitude range; if it lacks photometry (APASS: B V r' i';
  Gaia: no GSPC row, VARIABLE, |c_star| > 0.1) the reference star gets none. The fetcher lists
  Gaia stars without synthetic photometry (LEFT OUTER JOIN) exactly so that this works.
  APASS is searched around catalog_ra_original (UCAC5 at its epoch, as before), Gaia around
  catalog_ra (UCAC5 at the image epoch) after moving the Gaia rows to the image epoch.
- Positional cut for every source (field tables, VizieR APASS, Pan-STARRS1): offsets of the
  catalog position from corrected_ra_local/corrected_dec_local (the positions written to the
  .wcscat.ucac5), median and 1.4826*MAD per axis, sigma >= 1 arcsec, reject > 5 sigma, only
  with >= 20 matches. Constants at the top of the solver. reset_photometric_catalog_matches()
  now clears photometry too: before, a failed APASS attempt left its values behind for the
  stars Pan-STARRS1 did not match.
- Field-catalog cache: lib/catalogs/field_catalog_cache (git-ignored), reused when its cones
  cover the positions plus margin and its mag range covers the request; LRU pruning above
  VAST_FIELD_CATALOG_CACHE_MAX_MB (1000). Two traps found by the test: an awk "exit" in END
  replaces the status of an earlier "exit 1" (use a flag), and the cone radii are written with
  7 decimals, so the coverage check needs a 1e-6 deg tolerance or an identical request misses.
- util/examples/test_photometric_field_catalog.sh (replaces test_apass_esa_tap.sh; codes
  PHOTFIELDCAT*): a curl stand-in answers cone queries from sky stars made for the reference
  stars of wcs_fd_Per3_2011-10-31_001.fts (positions captured from the
  photometric_field_catalog_<PID>.positions file the solver writes). Gaia source_ids must be
  written as strings in awk (doubles lose them; the fetcher then de-duplicated 4611 stars into
  20). The first solver run on an image leaves a refined plate solution, so later runs match
  more stars (4611 vs 4896): the test does a warm-up run. Its Rc/Ic check restates Jester et
  al. (2005) as published (V-R, R-I), never the code's formula. Verified by planting bugs: old
  Ic sign, cut disabled, faintest instead of brightest, no PM propagation, "vmag BETWEEN",
  1e-9 cache tolerance - each one fails the test; about 1.5 min.
- Live TESS reference frame: APASS 4464 positions, 72,456 stars from ESA in 11 s, 2695
  matched, 249 cut, 2446 used (old: 319); Gaia 140,950 stars in 35 s, 3657 used; I zero points
  25.825 (APASS, sigma 0.27) vs 25.820 (Gaia, sigma 0.14).
- test_vast.sh sections calibrated against APASS, rerun by hand with the field-catalog code
  (live ESA): TESS Nova Vul 9.55 (pattern now 9.[4-6]); TESS calibration failure limit 15.39
  (now expected); TESS zero RA limit 16.04 and candidates 12.61 13.14 13.54 14.08 14.09 14.28
  13.40 (old values -0.42..-0.44, inside the patterns shifted for the Cousins I fix); RC600
  V/B/Rc fits and nova within 0.022 mag of the expectations (radius 2.3 arcsec: the cut never
  bites on such fields). The field-catalog path moves zero points by 0.00-0.02 mag only.
- Guards against transformation errors like the Cousins I sign (user's request, 2026-11-23):
  util/examples/check_photometric_catalog_colors.sh makes two checks on a .wcscat.ucac5:
  median (Rc-Ic)-(V-Rc) of the stars with 0.25 <= V-Rc < 0.60 within -0.15..+0.10 (real F-K
  stars about -0.01..-0.07; measured -0.024 APASS and -0.003 Gaia on TESS, -0.032 APASS on
  RC600; the old sign gives -0.44), and the median V-Rc, V-Ic, Rc-Ic of the stars with
  0.55 <= B-V < 0.75 AND B, V errors <= 0.05 (Sun 0.356, 0.701, 0.345, Ramirez et al. 2012;
  windows 0.27-0.52, 0.58-0.98, 0.25-0.52; old sign V-Ic 0.35, Rc-Ic -0.05 on TESS). Lesson:
  without the error limit the B-V check failed on the RC600 field (Nova Cas 2021, reddened):
  its faint stars have APASS B errors of 0.27 mag, the B-V bin fills with red stars (V-Ic
  1.03), and only 8 stars have good B and V - hence the B-free first check. test_vast.sh
  calls it through check_reference_image_catalog_colors() in the
  three TESS sections and the three RC600 sections (codes <PREFIX>_CATALOG_COLORS and
  _CATALOG_COLORS_NOT_CHECKED). util/examples/test_photometric_catalog_agreement.sh solves
  wcs_fd_Per3_2011-10-31_001.fts with APASS and with VAST_PHOTOMETRIC_CATALOG=gaia (live
  services, fresh cache) and compares the same stars: limits 0.10 (B V g r i), 0.15 (Rc Ic);
  NOT_PERFORMED_PHOTCATAGREE_nodata/noapass/nogaia when a catalog cannot be had. APASS and
  Gaia do not agree exactly and the offset depends on the field: Per3 V -0.034, Rc -0.063,
  Ic -0.067, r -0.027, i -0.038 (flat from V 10 to 13.5, so APASS zero points, not the bright
  end); TESS V -0.010, Ic -0.053 - tighter limits would be flaky. The old Ic sign gives +0.35.
  Gating in test_vast.sh: the agreement test runs everywhere, GitHub Actions included (the user:
  the 9.7 MB Per3 image and about 11 MB of Gaia plus 2 MB of APASS stars fetched live are fine
  for a GitHub runner; downloading a whole catalog, like the 42 GB Gaia synthetic photometry,
  would not be). On GitHub there is no local UCAC5 copy, so its plate solver runs match UCAC5
  remotely. The colour check runs inside the three TESS and three RC600 sections, with their
  gating (on GitHub only the TICA TESS find Nova Vul 2024 section). The offline field-catalog
  test needs no gate: without the local UCAC5 copy it skips its solver part before downloading
  the image. Ubuntu's default awk is mawk (whether the GitHub runner image also has gawk was not
  checked): the new awk code avoids comparisons and leading parentheses in print/printf
  argument lists (if/else instead), see the awk portability section.

## Archive frame-quality step: util/sun_moon, util/archive_frame_quality, unmw archive_frame_quality.sh (2026-11-23)
- Purpose (user request): judge the frames sort_workdir_images.sh keeps in
  <workdir>/good_wcs_fd_images/ and move the poor ones out (KEEP / REVIEW / REJECT, flat
  folders frame_quality/{review,rejected}/<reason>/ with good/ and bad/ for the user's pgfv
  loop; a frame put into good/ returns with the next --execute and is labelled). User
  decisions: reject Sun > -18 deg and Krisciunas & Schaefer (1991) moonlight > 0.5 mag; judge
  transparency against the field's own clear frames (fields never high in the sky keep their
  better frames); REVIEW a frame more than 1 mag below the camera's clear sky; own Sun/Moon
  code checked against astropy. The unmw script never deletes and never touches uncalibrated
  frames; coord_forced_photometry.py was deliberately left alone (moved-out frames are
  invisible to its backfills until returned).
- src/sun_moon.c (Meeus 1998 ch. 25/47/40/21/12/48 + K&S 1991 + Young 1994 airmass) agrees with
  astropy's built-in ephemeris to 0.012 deg (Sun), 0.003 deg (Moon, topocentric), 0.0001
  (illuminated fraction) over 2000-2026 at three sites: util/examples/test_sun_moon_ephemeris.sh.
  python3 -I hides the user site-packages (astropy on tau): run python from an empty
  directory instead when only the current directory must be kept out of sys.path.
- util/archive_frame_quality (run from the VaST directory): its own SExtractor pass (own
  parameter list in a mkdtemp directory), the frame's TAN-SIP solution (SIP inverted by
  iteration for Tycho-2 -> pixel), local Tycho-2 with proper motions, nearest detection within
  2 px. 4 s per frame on a typical TTU field, about 18 s of CPU in Milky Way fields (120k
  detections). Computed centre altitude vs N.I.N.A. CENTALT: 0.03-0.1 deg (CENTALT includes
  refraction).
- VaST's fitted SNR-model limiting magnitude (src/detection_limit.c) jumped by 1.2 mag between
  the two frames of one upload taken a minute apart (Aur-05, 2026-11-09 and -11); the median
  magnitude of the detections with SNR 4.5-5.5 agreed to 0.01 mag, so lim_mag is that and the
  fit is printed as lim_mag_fit only.
- The extinction coefficient of the unfiltered QHY600M (FILTER 'CV') is about 0.14 mag per
  airmass (fitted from the clear-sky upper envelope of the raw cell zero points against cell
  airmass, airmass 1.06-5.55): the V-band default 0.20 over-corrected the high-airmass cells by
  up to 0.5 mag and made clear low-airmass frames look 0.8 mag deficient against per-cell
  baselines. The unmw script fits k per camera on every run.
- The worst of 24 cells is too noisy against 90th-percentile baselines (0.27-0.34 mag on clear
  frames): the script judges the median cell (whole-frame transparency) and the third-worst
  cell (a patch of cloud). First results on 20 Aur-05/Vir-05 frames: 8 KEEP (clear, airmass
  1.0-1.7), the cloudy 2026-11-09 23:47 pair REJECT (median deficit 0.68-0.83), Moon, twilight
  and horizon-obstructed frames REJECT, 5 REVIEW (airmass 3.8 with 5.7 px seeing, a lost
  corner at airmass 4.4). All thresholds except the user's three are starting values.
- awk trap met three times in one script: the NR == FNR idiom treats every line of the second
  file as the first file's when the first file is EMPTY (no labels yet, no measurements yet,
  no baselines). Read the first file with getline in BEGIN instead.
- Example of a bright sky without Moon or twilight: Eri-10-Q1 2026-11-11 23:23, 16 deg up,
  169 ADU/s against 27-60 on the same night, limiting magnitude 1.3 mag brighter while the
  zero point and the found fraction were normal (light dome or city-lit haze).

## Aladin Lite and WISE report links ignored the position; CDS host names gone again (2026-11-25)
- Symptom (user report): the "Aladin Lite" link of every transient candidate opened Aladin Lite
  on a random object (Sgr B2, RMC 136, NGC 6397, NGC 5548 ... a different one on each load).
  The ?target=RA+DEC link made by util/transients/report_transient.sh was not at fault.
- Cause: during its cybersecurity incident CDS put up a temporary "fallback" Aladin Lite landing
  page on 2026-11-10 (Wayback: last old page 2026-10-25, first new one 2026-11-11). It reads
  only ra= and dec= (decimal degrees, 0 <= ra < 360, -90 <= dec <= 90), fov= (deg, 0 < fov <=
  180), hips=, catalogs= and theme=, never target=. Each of ra, dec and fov that is missing or
  out of range is replaced on its own by that of a random entry of its simbadTop100Targets
  list, so a lone bad ra (e.g. "360.000000") gives a random RA with the candidate's Dec. The
  pre-incident page (js/app.js of 2026-08-25) read target= first and ra/dec only without it;
  the copy CDS keeps at /AladinLite/old/ (like every app.js before 2024-03) reads only target=.
  The link is now ?ra=&dec=&fov=0.1&target=RA+DEC, which works with all three. fov=0.1 is a
  6 arcmin wide view (util/identify.sh zooms desktop Aladin to 5 arcmin); the old target-only
  links got a random 0.1-6 deg zoom.
- How it was checked: headless Chromium driven over the DevTools protocol from node (node 20
  needs --experimental-websocket for the global WebSocket). The page exposes window.initialView
  (what it hands to Aladin) and window.initialSimbadTarget (the random fallback); the
  .aladin-location box shows the view centre. All 26 positions of the 2026-11-08 report, 14 of
  the 2026-11-23 report (RA 0.75-359.76, Dec -37.8 to +88.3) and the edge cases ra=0,
  ra=359.999999, a 7-decimal RA, dec=+-90 and dec=-0 centred within 0.04 arcsec. An HTTP status
  check cannot see this failure (200 either way), and both selenium report tests skip AladinLite
  links. CDS's own Aladin Lite library (v3.9.3) still makes ?target= share links.
- WISE link, the same kind of failure: the old IRSA 'Hydra' link (#id=Hydra_wise_wise_1 ...
  UserTargetWorldPt=RA;DEC;EQ_J2000) now loads the Firefly WISE app on an empty "Search by
  Position" form and ignores every parameter. The app's URL API works: ?api=searchPos&ra=&dec=
  &imageset=allsky-4band&intersect=CENTER&imagesize=600s&dataproductlevel=3a&imageband=1,2,3,4
  &execute=true (Atlas level 3, 4 bands, 10 arcmin as before; checked at Dec +14.7 and -17.4;
  HTTP 200 without redirects, as the selenium link check needs). The result takes 60-90 s to
  render.
- Published reports keep the broken links: unmw copies each candidate's HTML byte for byte into
  *_filtered.html and its hrefs into *_filtered.json (external_links), and old pages are never
  rebuilt. One-off rewrite on the server (GNU sed; '&' in a replacement must be written '\&').
  Tested on copies of the 2026-11-08 and 2026-11-23 pages and the 2026-11-08 JSON: every link
  rewritten, nothing else changed, a second run changes nothing:
    sed -i -E \
     -e 's#https?://aladin\.(u-strasbg\.fr|cds\.unistra\.fr)/AladinLite/\?target=([0-9.]+)\+(-?[0-9.]+)"#https://aladin.cds.unistra.fr/AladinLite/?ra=\2\&dec=\3\&fov=0.1\&target=\2+\3"#g' \
     -e 's|https?://irsa\.ipac\.caltech\.edu/applications/wise/#id=Hydra_wise_wise_1[^"]*UserTargetWorldPt=([0-9.]+);(-?[0-9.]+);EQ_J2000[^"]*"|https://irsa.ipac.caltech.edu/applications/wise/?api=searchPos\&ra=\1\&dec=\2\&imageset=allsky-4band\&intersect=CENTER\&imagesize=600s\&dataproductlevel=3a\&imageband=1,2,3,4\&execute=true"|g' \
     FILES
- CDS host names: on 2026-11-24 aladin.u-strasbg.fr resolved again (same address and page as
  aladin.cds.unistra.fr); on 2026-11-25 (zone serials 2026112501 and 2026112502) aladin.,
  simbad. and vizier.cds.unistra.fr were NXDOMAIN, also at 8.8.8.8, and aladin.u-strasbg.fr had
  no A record, so every CDS link failed outright. Before that SIMBAD and VizieR answered 404
  "This page is currently unavailable" (the outage, not the link format); simbad.harvard.edu
  answers the same sim-coo query.
- TNS, in the same link block, works, but once answered "No results found" for the SN 2023ixf
  position that the same URL found later: a failed search and an empty one look the same.
