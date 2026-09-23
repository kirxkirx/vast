# Forced-photometry reference-image filter: design + implementation plan

## 1. Motivation

Today's transient-candidate funnel rejects candidates that are already in Gaia
DR2/APASS (`util/transients/report_transient.sh:594-671`). The Gaia filter is
slow (1-3 s per candidate, network-bound) and occasionally flaky.

Orthogonal failure mode: on the reference image, SExtractor sometimes misses
an otherwise-visible source (blending with a neighbor, aggressive `ANALYSIS_THRESH`,
bad pixels next to the PSF, etc.). VaST then reports the object as a new source
on the new frames -- a false-positive "transient".

Proposed mitigation: for each candidate, measure aperture photometry at its
RA/Dec on BOTH reference images *forcibly* (bypassing SExtractor detection and
VaST star-matching), using the `util/forced_photometry` C tool we already have.
If the forced reference-image photometry returns a detection and the candidate's
new-epoch mean magnitude is **not** at least `FLARE_MAG = 0.9` mag brighter than
the forced reference magnitude, reject the candidate. This turns an implicit
SExtractor failure into an explicit, algorithmic check.

## 2. Goals

1. Add a configurable pre-Gaia filter: forced photometry at candidate RA/Dec on
   both reference images, using the new-vs-reference brightening criterion from
   `src/find_flares.c` (`FLARE_MAG = 0.9` mag; errors ignored in this iteration).
2. Do the work **per-candidate** inside `report_transient.sh` (simple, parallel-safe,
   cost comparable to the Gaia query it might save).
3. Keep the existing pipeline bit-identical when the feature is disabled.
4. Surface the measurements in the HTML report without breaking downstream
   parsers: `parse_aavso.py`, `/tmp/unmw/filter_report.py`.

## 3. Non-goals

- No sigma/error-based brightening test this iteration -- pure
  `forced_ref_mag - new_mean_mag > FLARE_MAG`.
- No per-field tuning of `FLARE_MAG`; reuse the existing constant.
- **Absolutely no propagation of forced-photometry values into the lightcurve
  `out*.dat` files.** The forced measurements are a filtering-only side-channel;
  they must not appear in any column of the lightcurves, must not be re-read
  by VaST as part of the lightcurve, and must not affect `NEW_MEAN_MAG` (which
  is always derived from the existing lightcurve points, not from forced
  photometry on the new images -- we do not perform forced photometry on new
  images in this feature).
- No optimisation of VaST's internal star-matching. This filter compensates for
  matching failures, it does not fix them.
- No change to the Gaia/APASS filter logic; it continues to run for surviving
  candidates.
- **`calib.png` in `transient_report/` must remain the lightcurve-calibration
  plot (as it is today). The per-reference-image calibration introduced here
  must not overwrite or replace that archived plot.**

## 4. Feature flag

**Name**: `FORCED_PHOTOMETRY_ON_REFERENCE_IMAGES_FILTER`

**Values**: `yes` / `no` (case-sensitive; matches existing flag style such as
`REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES`).

**Default**: `no`. Existing runs, CI, and the tests in `util/examples/test_vast.sh`
keep their current behaviour. Users opt in via the per-camera-setting block in
`transient_factory_test31.sh`, or via environment variable.

**Scope when disabled**: no per-reference-image calibration, no forced-photometry
calls, no HTML additions, no per-candidate decisions. `transient_factory_test31.sh`
and `report_transient.sh` must take a short-circuit path whose net effect is
identical to the current code.

**Scope when enabled**: gates (a) the reference-image calibration step inside
the SExtractor-config loop, (b) the per-candidate filter block in
`report_transient.sh`. No test-path special-casing.

## 5. Design

### 5.1 C tool extension (`src/forced_photometry.c`)

Add a `--calib <path>` option so a caller can point the tool at a specific
calibration-parameter file instead of the current-directory `calib.txt_param`.
This avoids any rename/swap of `calib.txt_param` across parallel
`report_transient.sh` threads.

New CLI forms:

```
util/forced_photometry image.fits center_x center_y aperture_diameter [--calib PATH]
util/forced_photometry image.fits --list listfile aperture_diameter [--calib PATH]
```

`--calib PATH` must appear at the end (positional keep). If omitted, the tool
reads `calib.txt_param` from CWD (current behaviour, backward-compatible).

Implementation:
- Parse `argv`. Accept 5 or 7 args. When `argc == 7`, last two must be `--calib`
  and a path.
- Replace the `read_calib_param()` call to take an optional filename.
- Keep all other behaviour untouched (single-mode and list-mode outputs, stderr
  diagnostics). Update usage string.

Tests: the existing `util/examples/test_forced_photometry_list.sh` already
exercises list + single modes; add one assertion that `--calib` works.

### 5.2 Per-reference-image calibration (`transient_factory_test31.sh`)

Runs inside the existing SExtractor-config loop, **strictly after** the block
at lines 2666-2672 that copies `calib.png` into `transient_report/`. That
archive step is the point at which the lightcurve-calibration plot is safely
preserved under its unique `calib_<field>_<config>.png` name. Any work below
that point may freely clobber CWD's `calib.txt`, `calib.txt_param`, and
`calib.png` without affecting the archived lightcurve plot.

Ordering-protection requirements (violating these must be a review-blocker):

1. The per-ref calibration block must be inserted **after** line 2672 (the
   `fi` that closes the `calib.png` archive). No reordering of lines 2666-2672.
2. Before invoking `util/calibrate_single_image.sh` on the first ref image,
   assert via `[ -f transient_report/calib_${FIELD}_$(basename "$SEXTRACTOR_CONFIG_FILE").png ]`
   that the lightcurve plot has been archived. If missing (because `calib.png`
   wasn't generated in this iteration -- e.g. calibration upstream failed), we
   abstain from running per-ref calibration for this field/config pair. The
   report keeps whatever it had; no forced-photometry filter runs either.
3. No code elsewhere is changed to write `calib.png` or `calib.txt*`.
   `util/calibrate_single_image.sh` and `lib/fit_zeropoint` are the only
   writers of these files and they run after the archive, never before it.

The feature flag `FORCED_PHOTOMETRY_ON_REFERENCE_IMAGES_FILTER=yes` gates the
entire block -- when `no`, none of this runs and the pipeline's CWD files
remain exactly as they are today.

For each of `REFERENCE_EPOCH__FIRST_IMAGE` and `REFERENCE_EPOCH__SECOND_IMAGE`:

1. Resolve `WCS_REF=wcs_$(basename "$REF")` (normalise `wcs_wcs_`/`.fz`).
2. Derive the calibration band from `$PHOTOMETRIC_CALIBRATION` (`TYCHO2_V` -> `V`;
   `APASS_B` -> `B`; and so on for `_R`, `_I`, `_r`, `_i`, `_g`). Reuse the
   existing mapping -- copy-paste from the magnitude-calibration block rather
   than re-implementing.
3. Run `util/calibrate_single_image.sh "$WCS_REF" "$BAND"`. This overwrites
   `calib.txt` and (via `lib/fit_zeropoint` being called by the surrounding
   glue) the CWD `calib.png`. The archived lightcurve plot in
   `transient_report/` is unaffected, as required by the ordering rule above.
   The script will call `util/solve_plate_with_UCAC5` if
   `wcs_${base}.cat.ucac5` is not already present, reusing the existing cache.
4. Run `lib/fit_zeropoint`. This overwrites `calib.txt_param` (and `calib.png`).
5. `mv calib.txt_param calib.txt_param_ref_<basename>` -- saves the per-ref
   result. The lightcurve's `calib.txt_param` is no longer needed by the
   report (the lightcurves are already in calibrated form in the `out*.dat`
   files).
6. Record the per-ref aperture: read `${WCS_REF}.cat.aperture` (first value is
   the auto-detected aperture diameter in pixels used by VaST for that image).
   Store in a simple per-ref file `calib.txt_param_ref_<basename>.aperture`.

Failure handling:
- If `util/solve_plate_with_UCAC5` fails for a ref: emit a warning, write the
  marker file `calib.txt_param_ref_<basename>.FAIL`, don't write calib params.
  `report_transient.sh` will interpret the marker as "this ref is unusable" and
  skip it (treat like `calib_fail`).
- `.cat.aperture` missing: likewise mark `.FAIL`.

After both refs are processed:
- If at least one ref is usable, the filter runs in `report_transient.sh`.
- If both are `.FAIL`, the filter abstains for every candidate in this field.

Cleanup at end-of-field: no explicit cleanup needed; the next field's config
loop regenerates files.

### 5.3 Per-candidate filter (`report_transient.sh`)

Inserted in the flow between the online-id output (line 744) and the
`Check this position in TNS.` line (line 757), inside the existing
`<pre class='folding-pre'>` block so output is plain text lines.

```
if [ "$FORCED_PHOTOMETRY_ON_REFERENCE_IMAGES_FILTER" = "yes" ] && \
   [ "$NUBER_OF_LIGHTCURVE_POINTS" -eq 2 -o "$NUBER_OF_LIGHTCURVE_POINTS" -eq 3 ]; then
  # For each ref image:
  #   resolve paths, aperture, calib file
  #   sky2xy RA_MEAN_HMS DEC_MEAN_HMS -> px py
  #   util/forced_photometry WCS_REF PX PY APER --calib calib.txt_param_ref_<basename>
  #   parse: CAL_MAG ERR STATUS
  #   echo one line: "Forced photometry on <WCS_REF> at <RA> <DEC>:  <MAG> +/- <ERR>  <STATUS>"
  #
  # Combine ref1/ref2 into a single reference magnitude:
  #   both detection -> weighted average (w_i = 1 / err_i^2) => FORCED_REF_MAG
  #   exactly one detection -> use that magnitude
  #   neither detection -> no decision, do not reject
  #
  # Compute NEW_MEAN_MAG: weighted average of the 2 lightcurve-point mags
  # already present in $LIGHTCURVEFILE (columns: JD mag err x y aper image ...).
  #
  # Reject if FORCED_REF_MAG - NEW_MEAN_MAG <= FLARE_MAG (0.9).
  # On reject: clean_tmp_files; exit 1 (same as Gaia reject).
fi
```

Parsing rules, mirroring user-confirmed behaviour:

| forced-photometry status          | interpretation                               | behaviour                 |
|-----------------------------------|----------------------------------------------|---------------------------|
| `detection`                       | measurement usable                           | include in combined mag   |
| `upperlimit`                      | source undetected on ref                     | abstain (keep candidate)  |
| `edge` / `bad_region` / `nan_pixel` / `saturated` / `calib_fail` | cannot measure | abstain (keep)            |
| shell error / empty stdout        | internal problem                             | abstain (keep) + stderr   |

Per-ref `.FAIL` marker (from 5.2) is treated as `calib_fail` without invoking
the C tool.

### 5.4 Combining the two reference measurements

Weighted average when both are `detection`, with `w_i = 1 / err_i^2`:
`FORCED_REF_MAG = (m1*w1 + m2*w2) / (w1 + w2)`.

If either `err` is zero/missing, fall back to the arithmetic mean of whichever
magnitudes are detections.

If exactly one ref is `detection`, use it as-is; no averaging.

This policy was chosen by the user: one ref detection already proves "source
was there", but two complementary detections should combine rather than pick
one arbitrarily.

### 5.5 Combining the two new-epoch points

`NEW_MEAN_MAG` = weighted mean of the two lightcurve mags using `1/err^2`.
Fall back to arithmetic mean if errors are missing. These values are read from
the candidate's `out*.dat` lightcurve file (columns 2 and 3).

### 5.6 Filter decision

```
if FORCED_REF_MAG exists and (FORCED_REF_MAG - NEW_MEAN_MAG) <= FLARE_MAG (0.9):
    clean_tmp_files; exit 1   # candidate rejected, same semantics as Gaia
```

If `FORCED_REF_MAG` is undefined (both refs abstained), no decision is made.

### 5.7 HTML output

Two or three lines of plain text inside the existing `<pre class='folding-pre'>`
block -- no new HTML tags, no new attributes, no AAVSO-format lines, no lines
starting with `Type:`:

1. One line per usable reference image with its own forced-photometry result.
2. A summary line showing the weighted-average forced-reference magnitude
   (derived from 5.4) -- printed whenever the combined value was computable
   (i.e. at least one ref produced `detection`). If only one ref detection is
   available, the summary line simply repeats that magnitude (weighted average
   of one point = itself) so the reader sees a single, unambiguous "what the
   filter compared against" number.

Example (both refs usable, both detection):
```
Forced photometry on wcs_<ref1_basename> at 19:32:43.67 -22:39:30.7:  13.85 +/- 0.04  detection
Forced photometry on wcs_<ref2_basename> at 19:32:43.67 -22:39:30.7:  13.82 +/- 0.04  detection
Forced photometry reference-image weighted average:  13.83 +/- 0.03
```

Example (one `detection`, one `upperlimit`):
```
Forced photometry on wcs_<ref1_basename> at 19:32:43.67 -22:39:30.7:  13.85 +/- 0.04  detection
Forced photometry on wcs_<ref2_basename> at 19:32:43.67 -22:39:30.7:  99.0000 99.0000  upperlimit
Forced photometry reference-image weighted average:  13.85 +/- 0.04
```

Example (both `upperlimit` / abstain): only the two per-ref lines are printed;
no summary line, because nothing was averaged and no decision was made.

For non-detection / abstention cases the status is printed as-is (`upperlimit`,
`edge`, `bad_region`, `nan_pixel`, `saturated`, `calib_fail`) with
`99.0000 99.0000` magnitudes the C tool already produces.

Rejection path: the per-ref lines and the summary line are printed first, THEN
`exit 1` so the tmp output file is discarded by `make_report_in_HTML.sh`. User
sees nothing for rejected candidates -- same as Gaia rejections.

Parser compatibility verified:
- `parse_aavso.py` regex `r'^([^#<\s].+?,24\d{5}\.\d+,\d+\.\d+,.*,NMW.+)$'` and
  `Type:` / VSX lookbacks are unaffected (our lines have no `,24XXXXXX.XX,`
  pattern and do not start with `Type:`).
- `/tmp/unmw/filter_report.py` uses BeautifulSoup + `<a name>` anchors and
  reads the entire candidate block verbatim -- new lines are inside an
  existing `<pre>` and do not create new anchors.

## 6. Files changed

1. `src/forced_photometry.c` -- add `--calib <path>` parsing + pass through to
   `read_calib_param()`.
2. `util/transients/transient_factory_test31.sh` -- add per-ref calibration
   block inside the SExtractor-config loop, gated by the flag. Also default
   the flag at the top of the script.
3. `util/transients/report_transient.sh` -- add filter block between online-id
   output and TNS link.
4. `.claude/forced_photometry_reference_filter_design.md` -- this document.
5. `util/examples/test_forced_photometry_list.sh` -- minor: add a `--calib`
   smoke assertion.
6. `util/examples/test_forced_photometry_reference_filter.sh` -- **new** small
   standalone test (see section 8).

## 7. Implementation plan

Step-by-step, each step independently testable.

**Step 1**: `src/forced_photometry.c` `--calib <path>` support.
- Parse `argc == 5` (legacy), `argc == 7` with `argv[5]=="--calib"`.
- Refactor `read_calib_param()` to take a filename argument (default
  `"calib.txt_param"`).
- `make`, syntax-check, and extend `util/examples/test_forced_photometry_list.sh`
  with a quick assertion: pass `--calib <non-default-path>` and confirm the
  output magnitudes are consistent.

**Step 2**: `transient_factory_test31.sh` -- feature flag default + ref calibration.
- Add `: "${FORCED_PHOTOMETRY_ON_REFERENCE_IMAGES_FILTER:=no}"` near the top,
  next to similar defaults.
- After line 2672 (after `calib.png` is archived to
  `transient_report/calib_${FIELD}_$(basename "$SEXTRACTOR_CONFIG_FILE").png`),
  wrap in `if [ "$FORCED_PHOTOMETRY_ON_REFERENCE_IMAGES_FILTER" = yes ]`:
  - **Ordering assertion**: check that the archived plot exists
    (`[ -f transient_report/calib_${FIELD}_<config>.png ]`). If not, log a
    warning, abstain from per-ref calibration for this field/config, and
    continue. This guarantees the `calib.png` on disk belongs to the lightcurve
    calibration at the moment it is archived and is never replaced by per-ref
    content in the archive.
  - For each of `REFERENCE_EPOCH__{FIRST,SECOND}_IMAGE`: map `PHOTOMETRIC_CALIBRATION`
    to band, call `util/calibrate_single_image.sh`, `lib/fit_zeropoint`,
    rename `calib.txt_param` -> `calib.txt_param_ref_<basename>`. On any error,
    `touch calib.txt_param_ref_<basename>.FAIL` instead.
  - Read `${WCS_REF}.cat.aperture` and stash the first float in an env-style
    file `calib.txt_param_ref_<basename>.aperture`.
- **Do not** add any code that re-archives `calib.png` to `transient_report/`
  after this block; the lightcurve plot archived above is the final copy.
- Export the two `REFERENCE_EPOCH__{FIRST,SECOND}_IMAGE` variables so
  `report_transient.sh` children can resolve the per-ref filenames.
- Verify: parse-check + run one existing NMW test with the flag unset (default)
  to confirm no behavioural change.

**Step 3**: `report_transient.sh` -- filter block.
- Add helper function near top that parses `out*.dat` to compute the weighted
  new-epoch mean magnitude (used for `NEW_MEAN_MAG`).
- Inside the per-candidate flow, inserted just after the online-id `fi` at line
  744, guarded by the flag:
  - Skip unless `NUBER_OF_LIGHTCURVE_POINTS` is 2 or 3 (same gate as Gaia).
  - For each ref image (`REFERENCE_EPOCH__FIRST_IMAGE`, `_SECOND_IMAGE`, read
    from the exported environment):
    - If the per-ref `.FAIL` marker exists -> print a `calib_fail` per-ref
      line, continue.
    - Resolve aperture from `calib.txt_param_ref_<basename>.aperture`.
    - `lib/bin/sky2xy $WCS_REF $RA_MEAN_HMS $DEC_MEAN_HMS`, parse `$5 $6`.
    - `util/forced_photometry $WCS_REF $PX $PY $APER --calib calib.txt_param_ref_<basename>`.
    - Echo the per-ref one-liner.
  - Combine per policy (5.4, 5.5, 5.6):
    - Compute `FORCED_REF_MAG` and its error from the per-ref detections using
      inverse-variance weighted average (arithmetic mean fallback if errors
      are missing).
    - If `FORCED_REF_MAG` was computable, echo the summary line
      `Forced photometry reference-image weighted average:  <mag> +/- <err>`.
    - If `FORCED_REF_MAG` exists and `FORCED_REF_MAG - NEW_MEAN_MAG <= 0.9`,
      reject -> `clean_tmp_files; exit 1`.
- Absolutely do not write the forced measurements into `$LIGHTCURVEFILE` or any
  `out*.dat`; they live only in stdout/HTML.

**Step 4**: Small-scale test (section 8).

**Step 5**: Shellcheck, `bash -n`, spot-run the small test with and without the
flag; stage the changed files.

## 8. Small-scale test

**Goal**: validate end-to-end behaviour with minimum runtime, using
pre-existing test data. Not aimed at exhaustive coverage.

**Choice of base test**: `NMW find Nova Sgr 2020 N4 test` (line 13741 in
`util/examples/test_vast.sh`). Reasons:
- Real nova (`Nova Sgr 2020 N4`) provides a candidate that must **survive** the
  filter; both ref frames should give `upperlimit` or very faint detections at
  the nova's pre-discovery position, so the filter keeps the candidate.
- Test data already exists on CI; the existing test-block completes in ~2-3 min.
- The block already runs `transient_factory_test31.sh` end-to-end, so adding a
  sibling block that toggles the flag is minimally invasive.

**New test script**: `util/examples/test_forced_photometry_reference_filter.sh`
Standalone runner (mirrors the pattern of
`util/examples/test_forced_photometry_list.sh`):

1. Check the Nova Sgr test data directory exists (same check as the existing
   test block).
2. `util/clean_data.sh`.
3. Run the pipeline with the feature flag on:
   `FORCED_PHOTOMETRY_ON_REFERENCE_IMAGES_FILTER=yes \
       REFERENCE_IMAGES=../NMW_Sgr1_NovaSgr20N4_test/reference_images/ \
       util/transients/transient_factory_test31.sh \
       ../NMW_Sgr1_NovaSgr20N4_test/second_epoch_images`.
4. Assertions:
   - Exit code 0.
   - `transient_factory_test31.txt` contains a "Preparing per-reference-image
     forced-photometry calibration" marker line we add for observability.
   - `calib.txt_param_ref_wcs_*.fits` files exist (both refs calibrated).
   - Each such file has 5 whitespace-separated floats on a single line
     (`fit_zeropoint` output format).
   - `transient_report/index.html` contains `Forced photometry on wcs_` for at
     least one candidate surviving to the HTML stage (or at least one
     `.tmp2__report_transient_output__GOOD__` file contains it, if we check at
     an intermediate point).
   - `transient_report/index.html` contains the summary line
     `Forced photometry reference-image weighted average:` for at least one
     surviving candidate (empirical: if any candidate had at least one
     ref-image `detection`).
   - `transient_report/calib_<FIELD>_<CONFIG>.png` exists and is the
     lightcurve-calibration plot; its size/timestamp was set before per-ref
     calibration ran (i.e. the lightcurve plot is not silently replaced by a
     per-ref one). The CWD `calib.png` may belong to the last ref processed --
     that is acceptable because only the archived copy is linked from the HTML.
   - No `out*.dat` lightcurve file was modified by the forced-photometry
     code path: compare mtimes of `out*.dat` before-and-after the per-candidate
     loop, or spot-check a known candidate's lightcurve content to confirm it
     still has exactly `NUBER_OF_LIGHTCURVE_POINTS` lines with the original
     instrumental + calibrated values.
   - The known Nova Sgr 2020 N4 is still reported (same assertion as existing
     test block).
   - `parse_aavso.py`-style regex scan over `transient_report/index.html` still
     parses successfully (optional sanity check if we want to be thorough).
5. Clean up temp files.

**Integration into `util/examples/test_vast.sh`**: **not yet**. The standalone
test runs independently for now. Once stable, we can add it to test_vast.sh
following the same pattern we used for `test_forced_photometry_list.sh`.

**Smoke: flag disabled**: the existing Nova Sgr test block already validates
this case -- no changes required.

## 9. Risks and open questions

- **Calibration-plot ordering**: the lightcurve `calib.png` must be archived in
  `transient_report/` BEFORE any per-reference-image calibration runs. Two
  defences: (a) the per-ref block is inserted after line 2672 where the
  archive occurs; (b) the per-ref block asserts the archived PNG exists and
  abstains otherwise. A breakage here would silently replace the lightcurve
  plot with a per-ref one in the HTML report -- detectable in the small-scale
  test via mtime / content check.
- **Lightcurve-file integrity**: the filter is a side-channel that must never
  mutate `out*.dat` files. Enforced by design (no file writes by the filter);
  the small-scale test cross-checks `out*.dat` contents are unchanged.
- **`.cat.aperture` file availability**: relies on SExtractor having been run
  on the reference image via the plate-solving step. Normally this already
  runs; if not, the `.FAIL` marker keeps the filter safe. Need to double-check
  the file is persisted (not temp-cleaned between config iterations).
- **`util/calibrate_single_image.sh` side-effects on CWD**: it writes `calib.txt`
  and `calib.png`. Calling it twice (once per ref) within the same config
  iteration means the second call's `calib.png` is a plot of the second ref,
  overwriting the first's. Since we only use `calib.txt_param` and do not
  re-archive `calib.png` after ref calibration, this is acceptable, but we
  should not call `calib.png` -> `transient_report/` logic again.
- **Parallelism**: `report_transient.sh` runs with up to 5 threads. Each
  thread invokes `util/forced_photometry` on the same ref image. Linux
  file-cache makes second+ reads fast, and `--calib <path>` avoids shared-file
  writes. No locking needed.
- **Non-deterministic ordering of forced-phot calls**: two parallel threads may
  compute for different candidates. Since each has its own RA/Dec and no shared
  state, results are deterministic per-candidate.
- **Feature flag honouring by all call sites**: must ensure the flag gate is
  checked identically in `transient_factory_test31.sh` (gate the calibration)
  and `report_transient.sh` (gate the per-candidate filter). Mismatch would
  produce spurious errors (e.g. calib files missing at filter time). The test
  in section 8 exercises both.

## 10. Not in scope / out-of-band follow-ups

- Integrating the new test into `util/examples/test_vast.sh`.
- Switching the default to `yes` once the feature has been battle-tested.
- Exposing `FLARE_MAG` as a tunable instead of using the C constant directly.
- Using errors in the brightening criterion (deferred by user).
- Propagating forced-photometry values into `out*.dat` lightcurves.
