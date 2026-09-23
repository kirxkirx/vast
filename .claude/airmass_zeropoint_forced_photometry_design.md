# Airmass-aware zero-point for forced photometry: design + implementation plan

## 1. Motivation

Wide NMW frames carry a differential-extinction gradient: a star at the
high-airmass edge of a frame is reported systematically fainter than a star of
the same true brightness near the frame center, because the photometric
zero-point is a single constant fitted over the whole frame. Measured on real
data (single-image Tycho-2 calibrations, 2026-07-06 experiments in
/home/kirx/vast_test/airmass_correction_experiment/):

- TTU Sco-03 frames: 0.15-0.31 mag/airmass depending on the night, up to
  0.8 mag corner-to-corner at frame center airmass 2.9;
- STL Oph frame at airmass 3.1-10.4: 1.4 mag corner-to-corner, following a
  clean Bouguer line;
- the coefficient k varies by a factor 2-3 between nights (weather), so no
  constant default can substitute for a per-image fit.

Forced photometry (the reference-image candidate filter in
`transient_factory_test31.sh`/`report_transient.sh`, and the unmw
`coord_forced_photometry.py` / `archive_phot_worker.py` services) measures a
single target position per image and calibrates it with that constant
zero-point, so its result is biased by k*(X_target - X_calib_effective).

Key simplification proven empirically (Nova V6593 Sgr end-to-end test: the
reported magnitude moved by exactly the pixel-level correction at its
position): the whole measurement chain is linear, so for a point measurement
the pixel-level correction is exactly equivalent to a magnitude-level term.
No image pixels need to be touched. The correction becomes an upgrade of the
zero-point model from a constant to a linear function of airmass.

Measured costs of the building blocks: the airmass fit over the calibration
stars takes 0.3-0.5 s per image; evaluating the airmass at one target position
takes ~6 ms (`--predict-list` reads only the FITS header). For comparison,
the per-image plate solve + SExtractor + catalog match that forced photometry
already performs costs 30-120 s.

## 2. Goals

1. Correct forced-photometry magnitudes for the differential-extinction
   gradient, using a per-image k fitted from that image's own calibration
   stars.
2. Apply the correction in BOTH consumers with one implementation:
   `util/forced_photometry.sh` (serves unmw coord + archive photometry) and
   the reference-image filter (`transient_factory_test31.sh` +
   `report_transient.sh`).
3. Narrow-field / poor-fit provision: NO correction when the image does not
   support a good fit - not enough stars, not enough airmass range across the
   frame, noisy or implausible slope. In every such case the behaviour must be
   bit-identical to the current constant-zero-point pipeline.
4. Zero changes in the unmw repository. `archive_phot_prune.sh` and
   `archive_phot_status.py` are queue management and are not touched by design.
5. Feature-flagged, default off; flag off = bit-identical to today.

## 3. Non-goals

- No pixel-level correction and no storing of corrected images (equivalence
  argument in section 1; pixel-level remains available in
  `util/pixel_flux_airmass_correction` for whole-frame use cases).
- No correction of the main transient-search photometry (the `./vast` run and
  its lightcurves) - forced photometry only.
- No color term / second-order extinction; single achromatic k per image.
- No k database or per-night averaging in this iteration: each image is fitted
  independently at measurement time (the archive worker thereby automatically
  uses each historical night's own k).
- No change to the `calib.txt_param` file format or to
  `util/forced_photometry` (the C measuring tool): the airmass term lives in a
  separate companion file and is applied by the calling shell scripts.

## 4. Feature flag

**Name**: `FORCED_PHOTOMETRY_AIRMASS_ZEROPOINT`
**Values**: `yes` / `no`. **Default**: `no`.

Gates (a) the fit step and (b) the application step in both consumers. When
`no`, neither runs; when `yes` but the per-image fit is rejected by the gates
of section 5.3, the application step adds exactly 0 - both paths reduce to the
current behaviour.

## 5. Design

### 5.1 Model and sign conventions

For each calibration star i of one image: instrumental magnitude m_i
(`MAG_APER`), catalog magnitude V_i (Tycho-2 V or APASS band - whatever the
existing calibration produced), airmass X_i evaluated at the star's pixel
position through the image's own WCS + site + mid-exposure time (the exact
machinery of `util/pixel_flux_airmass_correction`; per-star evaluation, no
grid).

Fit by least squares with one 3-sigma clipping pass:

```
V_i - m_i = A + B * X_i
```

B < 0 corresponds to extinction (stars at higher airmass measure fainter);
the effective extinction coefficient is k = -B.

The constant zero-point that `lib/fit_zeropoint` fitted and that
`util/forced_photometry` will apply is p0 (from `calib.txt_param`). The
airmass-aware final magnitude of a target at position (x_t, y_t) with airmass
X_t is:

```
m_final = m_constZP_calibrated + D0 + B * X_t      where D0 = A - p0
```

i.e. the calling script takes the magnitude printed by the (unchanged) C
measuring tool and adds the differential term `D0 + B*X_t`. Defining the term
relative to p0 (read from the very `calib.txt_param`/`--calib` file the C tool
uses) makes the correction exact by construction, immune to any difference
between the median zero-point and the fit intercept.

Extrapolation guard: if X_t falls outside the [X_min, X_max] span of the
clipped calibration stars, clamp X_t to the nearest boundary before evaluating
the term (the linear model is not trusted beyond the fitted range; the
clamping is conservative and is noted in the diagnostic output).

### 5.2 The fitting mode: `util/pixel_flux_airmass_correction --fit-airmass-zeropoint`

New mode of the existing C tool (all the WCS/site/time/airmass machinery and
the site overrides are already there; adding the fit keeps one source of truth
for the math and puts the thresholds in `src/vast_limits.h` per project
convention):

```
util/pixel_flux_airmass_correction --fit-airmass-zeropoint \
    calib.txt <sextractor_catalog> <image.fits> [--calib-param calib.txt_param] \
    [--sitelat ... --sitelong ...]
```

- `calib.txt`: the existing 3-column file `instr_mag catalog_mag err` produced
  by `lib/catalogs/read_tycho2` (TYCHO2 path) or by
  `util/calibrate_single_image.sh` (APASS/UCAC5 path,
  `calibrate_single_image.sh:185-197`). In both flavours column 1 is the
  catalog's `MAG_APER` value printed to 4 decimals.
- `<sextractor_catalog>`: the image's own `wcs_<name>.fits.wcscat` (10 columns:
  `NUMBER RA Dec X Y FLUX FLUXERR MAG_APER MAGERR FLAGS`). Stars are joined to
  `calib.txt` rows on the 4-decimal-normalized MAG_APER value; ambiguous
  duplicate keys are dropped (validated approach; typical loss 1-3 percent).
- `--calib-param`: the file whose p0 the applied term must offset against
  (default `calib.txt_param` in CWD). Only field p0 is read; the file is not
  modified.
- `--fit-table <path>` (optional): also write the per-star fit table, one row
  per joined calibration star: `X_i resid_i used_flag` where
  `resid_i = (V_i - m_i) - p0` (the residual from the constant zero-point
  actually applied) and `used_flag` is 1 for stars that survived the clipping,
  0 for clipped ones. This file feeds the diagnostic plotter (section 5.9)
  and is also convenient for offline analysis.
- Output: ONE line on stdout (the "airmass zero-point file" content):

```
STATUS D0 B X_center k N_used airmass_span sigma_fit X_min X_max
```

(X_min/X_max are the airmass range of the stars used in the fit; appliers clamp
the target airmass into this range before evaluating the term.)

`STATUS` is `OK` or one of the reject reasons of section 5.3; on reject the
diagnostics fields are still filled where computable and the appliers use
term = 0. Exit code 0 whenever the line was produced (a reject is a normal,
non-error outcome); nonzero only on operational failure (missing files etc.),
which appliers also treat as "no correction".

### 5.3 Gates: the narrow-field / poor-fit provision

All constants in `src/vast_limits.h`. The fit is REJECTED (STATUS set
accordingly, no correction applied) unless every gate passes, evaluated on the
post-clipping star set:

| gate | constant (proposed value) | reject STATUS | rationale |
|---|---|---|---|
| enough stars | `AIRMASS_ZP_MIN_STARS 100` | `REJECT_FEW_STARS` | median/clip robustness; narrow-field cameras calibrate on 10-100 stars and are excluded outright |
| enough airmass range | `AIRMASS_ZP_MIN_AIRMASS_SPAN 0.1` | `REJECT_NARROW_SPAN` | below 0.1 airmass across the stars the correction is both unfittable and pointless (<=0.03 mag even at k=0.3); a 20-arcmin field has span ~0.003, a wide field at zenith also fails - the gate is self-regulating in both regimes |
| slope is measured, not guessed | `AIRMASS_ZP_MAX_K_ERR 0.05` (1-sigma of B) | `REJECT_NOISY_FIT` | the unified "good fit" criterion: sigma_B <= 0.05 mag/airmass requires the right combination of N, span and scatter, whatever the field |
| slope is plausible | `AIRMASS_ZP_MIN_K -0.05`, `AIRMASS_ZP_MAX_K 0.6` | `REJECT_K_RANGE` | k slightly negative is noise around zero and passes (the applied term is then tiny and harmless); k < -0.05 or k > 0.6 indicates a sky-pattern-dominated or broken fit (Sgr1-type differentially reddened fields, wrong site, bad WCS) |
| join succeeded | (no constant) | `REJECT_NO_POSITIONS` | missing/short catalog, join produced < AIRMASS_ZP_MIN_STARS pairs |

Notes:
- The gates make the narrow-field provision automatic: any camera whose field
  is too small to sample an airmass gradient can never pass
  `AIRMASS_ZP_MIN_AIRMASS_SPAN`, regardless of star counts.
- The known residual risk (documented, accepted): on strongly differentially
  reddened fields (galactic plane/bulge) the fitted B mixes extinction with a
  sky-fixed color-term pattern. The k-range gate bounds the damage; the term
  applied is the frame's empirical airmass trend, which is no worse than what
  a pixel-level correction with the same fitted k would do.
- No bright-star/all-star consistency gate in v1 (saturation makes the bright
  subset unusable on Stas/STL); both fits MAY be printed to stderr as
  diagnostics.

### 5.4 Site-coordinate policy

The airmass evaluation must never trust `SITELAT`/`SITELONG` on NMW Stas or
STL frames (the acquisition machines have been seen writing them swapped; the
user warns Stas is affected too, we were merely lucky with test data).

- `transient_factory_test31.sh`: the per-camera settings block exports
  `AIRMASS_ZP_SITELAT` / `AIRMASS_ZP_SITELONG` ('43 38 58' / '41 25 34' for
  Stas and STL-11000M; unset for TTU whose decimal header values are validated
  against the header's own CENTALT/AIRMASS by the tool's built-in cross-check).
- `util/forced_photometry.sh` (unmw context, no camera setting available):
  a small INSTRUME-based table - `SBIG ST-8300`/`STL-11000` implies the NMW
  site and forces the override; anything else uses the header. Both variables
  are env-overridable so unmw could force them per camera later without a VaST
  change.
- If no site can be resolved at all, the fit mode rejects
  (`REJECT_NO_POSITIONS` family; term 0) rather than guessing.

### 5.5 `util/forced_photometry.sh` integration

Insertion points (current flow: `calibrate_single_image.sh` at line ~208,
`fit_zeropoint` at ~222, `sky2xy` at ~246/285, C tool at ~328/331):

1. After `calib.txt_param` is confirmed non-empty and when
   `FORCED_PHOTOMETRY_AIRMASS_ZEROPOINT=yes`: resolve the catalog
   (`${WCS_IMAGE_NAME}.wcscat`), apply the site policy of 5.4, run the fit
   mode, save its stdout line as `calib.txt_param_airmass` in CWD. Any failure
   -> write a `REJECT_FIT_FAILED ...` line instead; never abort the
   measurement.
2. Single-target mode: after the C tool returns `MAG ERR STATUS`, if the
   airmass file says OK, evaluate X_t at (PIXEL_X, PIXEL_Y) with ONE
   `--predict-list` call on the same image (same site overrides), clamp to the
   fitted span, and replace MAG with `MAG + D0 + B*X_t` (awk, 4-decimal
   output). ERR and STATUS unchanged.
3. List mode: batch-evaluate all positions with a single `--predict-list`
   call, then adjust each output line's MAG. One fit + one predict per image
   regardless of the number of targets.
4. Output compatibility (hard constraint): stdout keeps the exact token
   structure that `nmw_forced_phot_lib.run_forced_photometry_c()` parses
   (`toks = c_line.split()` and the jd/mag/err/status/aperture/x/y fields) -
   only the numeric value of the magnitude token changes. The applied
   term/status is reported on STDERR only, e.g.
   `airmass zero-point: OK k=0.186 term(X=3.42)=-0.061 mag` or
   `airmass zero-point: REJECT_NARROW_SPAN (span=0.02) - constant zero-point used`.

### 5.6 `transient_factory_test31.sh` integration (reference-image filter)

Inside the existing per-reference-image calibration block
(lines ~3030-3110), immediately after `mv calib.txt_param
"$FORCED_PHOT_CALIB_OUT"` succeeds and the `.aperture` file is written:

- when the flag is `yes`, run the fit mode with `calib.txt` (still in CWD from
  `calibrate_single_image_with_tycho2.sh`, which also leaves `wcsmag.cat` -
  but pass the durable `${FORCED_PHOT_WCS_REF}.wcscat` as the catalog, not the
  transient `wcsmag.cat`), `--calib-param "$FORCED_PHOT_CALIB_OUT"`, and the
  per-camera site override variables; save the line as
  `${FORCED_PHOT_CALIB_OUT}.airmass`.
- on any failure write a `REJECT_FIT_FAILED` line; the `.FAIL` marker
  semantics of the existing design are untouched (a ref with `.FAIL` never
  reaches the airmass step).

The per-ref loop is sequential, so the CWD `calib.txt` race concerns of the
parallel candidate stage do not apply here.

### 5.7 `report_transient.sh` application (per candidate)

In the existing filter block (design doc
`.claude/forced_photometry_reference_filter_design.md` section 5.3), after
each per-ref `util/forced_photometry ... --calib calib.txt_param_ref_<img>`
call returns a `detection`:

- if `calib.txt_param_ref_<img>.airmass` exists and starts with `OK`,
  evaluate X_t at the (PX, PY) already obtained from `sky2xy` via one
  `--predict-list` call on the ref image (site overrides from the exported
  per-camera variables), clamp, and adjust the magnitude before it enters the
  per-ref HTML line and the weighted combination of section 5.4 of the filter
  design.
- the per-ref HTML line format is preserved; the adjusted magnitude simply
  replaces the raw one. Optionally append the plain-text word
  `airmass-corrected` at the END of the line - permitted by the parser rules
  in `.claude/notes.md` (no `The object was` / `found in` / `not found`
  substrings; appended at the end of the block lines).
- threads: `report_transient.sh` runs up to 5 in parallel; the `.airmass`
  files are written once by the factory before candidates are processed and
  are read-only here; `--predict-list` is read-only. No locking needed.

### 5.8 unmw

No changes. `coord_forced_photometry.py` and `archive_phot_worker.py` inherit
the correction through `util/forced_photometry.sh` (they exec it via
`nmw_forced_phot_lib.run_forced_photometry_c`). They enable it the same way
they get the rest of their environment: `FORCED_PHOTOMETRY_AIRMASS_ZEROPOINT=yes`
exported from `local_config.sh`, which the engine already sources before each
run. `archive_phot_prune.sh` / `archive_phot_status.py`: nothing (no
measurement code).

Note for the archive worker: because the fit runs per image at measurement
time, historical frames automatically get their own night's k - including
frames whose k a stored database would not know. Cost is +0.3-0.5 s on top of
the 30-120 s the worker already spends per image; throughput impact under
2 percent.

### 5.9 Diagnostic plots (gated on matplotlib availability)

A per-image PNG showing the airmass-dependent zero-point fit, placed in the
processing log right next to the corresponding measured-vs-catalog magnitude
calibration plot, so the operator sees both diagnostics for each reference
image in one place.

**Plotter**: new `lib/plot_airmass_zeropoint.py`, following the conventions of
`lib/plot_astrometric_residuals_xy.py`:
- stdlib + matplotlib only; the import block is
  `import matplotlib; matplotlib.use("Agg")` inside try/except ImportError -
  on missing matplotlib it prints a one-line note and exits nonzero, and the
  caller treats that as "no plot", never as an error
  (mirrors `lib/plot_astrometric_residuals_xy.py:152-157`);
- inputs: the fit table (`--fit-table` output of section 5.2), the one-line
  airmass zero-point file, an output PNG path, and a title string (the image
  basename);
- content: x = airmass at the star position, y = residual from the constant
  zero-point (mag); used stars as filled points, clipped stars as light
  crosses; the fitted line `D0 + B*X` and the y=0 line of the constant
  zero-point; an annotation box with STATUS, k = -B +/- sigma_B, N, airmass
  span, sigma_fit. When the fit is REJECTED the plot is still produced (that
  is when the operator most needs to see the data) with the reject reason in
  the title and a note that the correction was NOT applied.

**Factory placement** (`transient_factory_test31.sh` per-ref block): after the
`.airmass` file is written, when a python interpreter is found (same
`command -v python3 || command -v python` selection as
`make_astrometric_residuals_plot`, factory lines ~1058-1069):
- run the plotter to `transient_report/calib_ref_<wcs_ref_basename>_airmass.png`
  (name parallel to the existing per-ref calibration plot
  `calib_ref_<wcs_ref_basename>.png`);
- on success (non-empty PNG - the unambiguous success signal, stale file
  removed beforehand) append to `transient_factory_test31.txt`, immediately
  after the existing per-ref calibration plot line:
  `<br><b>Airmass zero-point diagnostic for <wcs_ref>:</b><br><img src="calib_ref_<...>_airmass.png"><br>`
  which surfaces it in the HTML report exactly alongside the
  measured-vs-catalog plot;
- on any failure (no python, no matplotlib, plotter error): one note line in
  the log, no HTML line, processing continues - the plot is strictly optional
  and never affects measurements.

**`util/forced_photometry.sh`** (unmw/standalone context): the PNG is written
to CWD next to `calib.png` only when the additional flag
`FORCED_PHOTOMETRY_AIRMASS_ZEROPOINT_PLOT=yes` is set (default `no`). The
matplotlib import alone costs 0.3-1 s, which is unwanted overhead for the
archive worker looping over hundreds of images, and the disposable working
copies have no HTML surface to show the plot anyway; unmw can opt in later
without any VaST change by exporting the flag from `local_config.sh`.

## 6. Files changed

1. `src/pixel_flux_airmass_correction.c` - `--fit-airmass-zeropoint` mode
   (join, LSQ + 3-sigma clip, gates, one-line output), `--calib-param` and
   `--fit-table` options. Roughly +280 lines, C89 style.
2. `src/vast_limits.h` - the five `AIRMASS_ZP_*` constants of section 5.3.
2a. `lib/plot_airmass_zeropoint.py` - new diagnostic plotter (section 5.9),
   matplotlib-gated, Agg backend, stdlib+matplotlib only.
3. `util/forced_photometry.sh` - flag default, fit step, site table,
   magnitude adjustment in single and list modes, stderr diagnostics.
4. `util/transients/transient_factory_test31.sh` - flag default, per-ref
   `.airmass` files, per-camera `AIRMASS_ZP_SITELAT/LONG` exports.
5. `util/transients/report_transient.sh` - per-ref application before the
   weighted combination.
6. `util/examples/test_pixel_flux_airmass_correction.sh` - fit-mode checks
   (see section 8).
7. `.claude/airmass_zeropoint_forced_photometry_design.md` - this document.

## 7. Implementation plan

**Step 1**: C tool: `--fit-airmass-zeropoint` + `--calib-param` + constants in
`vast_limits.h`. Syntax-check, `make`.
Validate against the known ground truth: running the fit mode on the saved
single-image experiment inputs (`results/single_image/<tag>_calib.txt` +
`<tag>_wcsmag.cat` + the wcs image) must reproduce the awk analyzer's slopes
(sco03_e2a: k=0.31, stl_oph_ref1: k=0.21, sgr1_e2_001: k~0 ->
`REJECT_K_RANGE` passes as k>-0.05... expected `OK` with tiny k) to ~0.005.

**Step 2**: `util/forced_photometry.sh` integration. Verify with the flag off:
byte-identical output on a test image. With the flag on: run on one solved TTU
Sco-03 frame at two artificial list positions near the frame top and bottom;
the magnitude difference between the corrected outputs must change by
B*(X_bottom - X_top) relative to the uncorrected run.

**Step 3**: factory + `report_transient.sh` integration; flag-off no-op
verified by re-running one standard NMW test unchanged.

**Step 4**: `lib/plot_airmass_zeropoint.py` + `--fit-table` plumbing + the
factory PNG/log-line placement. Verified on one Sco-03 reference image:
PNG appears in `transient_report/`, the log gains the `<img>` line right
after the per-ref calibration plot line, and with matplotlib artificially
hidden (`PYTHONPATH` pointing at an empty dir plus `-S`-style import
breakage, or simply asserting behaviour on a machine without matplotlib)
everything else is unaffected.

**Step 5**: tests of section 8; shellcheck; stage files.

## 8. Tests

Extend `util/examples/test_pixel_flux_airmass_correction.sh`:
- fit mode on the Sgr1 dataset's solved reference image (data already
  downloaded by the test): expect `OK`, k in a sane window, N > threshold;
- synthetic gate checks, no downloads needed: (a) truncate calib.txt to 50
  lines -> `REJECT_FEW_STARS`; (b) feed a catalog whose star positions are
  confined to a 100x100 px box (awk-filtered copy) -> `REJECT_NARROW_SPAN`;
  (c) corrupt calib.txt magnitudes with a huge fake slope -> `REJECT_K_RANGE`;
- flag-off equivalence: `util/forced_photometry.sh` output identical with the
  feature flag unset vs `no`.

New small standalone test `util/examples/test_forced_photometry_airmass.sh`
(optional, follows `test_forced_photometry_list.sh` pattern): one solved NMW
image, one target measured with flag off and on, assert the difference equals
the predicted term to 0.001 mag and that the unmw-parsed token structure is
unchanged (token count per line).

Plot checks (environment-tolerant, like the PSFEX_NOT_INSTALLED pattern in
`test_vast.sh`): if `python3 -c "import matplotlib"` succeeds on the test
machine, assert the fit-mode + plotter pair produces a non-empty PNG for the
Sgr1 reference image and that a REJECTED synthetic case (the narrow-span
input) also produces its PNG with the reject reason; if matplotlib is absent,
assert the plotter exits nonzero with its one-line note and that the calling
script continues without error.

## 9. Risks and open questions

- **Differentially reddened fields**: fitted B mixes extinction with the
  sky color-term pattern (Sgr1 study). Bounded by the k-range gate; the
  correction then reflects the frame's empirical trend - never worse than the
  equivalent pixel-level correction, but not pure extinction either. A future
  color-map or b_gal term is out of scope.
- **Aperture mismatch**: calib.txt mags come from the plate-solve SExtractor
  run (`.wcscat`), while `util/forced_photometry` measures with the `.aperture`
  diameter. The constant part of any aperture systematic is absorbed by p0 as
  today; the airmass term only assumes the GRADIENT is aperture-independent
  (extinction is), so no new systematic is introduced.
- **`.wcscat` availability**: guaranteed on the factory path (plate-solve pass
  produces it; `calibrate_single_image_with_tycho2.sh` regenerates it if
  missing). On the unmw path `calibrate_single_image.sh` also leaves it. If
  absent, the fit rejects and the term is 0.
- **Site policy hardcodes the NMW site** in `forced_photometry.sh`'s INSTRUME
  table. Accepted for v1 (env-overridable); the real fix is upstream in the
  acquisition configs.
- **Extrapolation at frame corners**: clamped to the fitted span; the known
  non-Bouguer upturn at X > ~4 in extreme frames is therefore neither
  corrected nor made worse.
- **Double application**: impossible by construction - the term is applied at
  exactly one point per consumer (the magnitude token rewrite), and nothing is
  ever written back to images or calib.txt_param.

## 10. Cost accounting

Per image, flag on, fit accepted: +0.3-0.5 s (fit) + 6 ms per target
(predict; one batched call in list mode). Per image, fit rejected: the same
fit cost, term 0. Against the existing 30-120 s per-image plate-solve +
SExtractor + catalog match of every forced-photometry path, the overhead is
1-2 percent. No new I/O of image-sized data; no storage.

Diagnostic plots: +0.3-1 s per plotted image (dominated by the matplotlib
import) and a 50-200 KB PNG per reference image in `transient_report/`.
In the factory this is two plots per field; in `forced_photometry.sh` plots
are off unless `FORCED_PHOTOMETRY_AIRMASS_ZEROPOINT_PLOT=yes`, so the archive
worker's throughput is unaffected by default.
