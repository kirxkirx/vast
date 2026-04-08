# Forced Photometry Tool - Design Document

## Overview

A new VaST feature to perform aperture photometry at a user-specified sky
position (RA, Dec) on a single FITS image, reporting a calibrated magnitude
or a 3-sigma upper limit. Two independent implementations (C and Python)
will be cross-validated against each other and against SExtractor measurements.

## Files

| File | Role |
|------|------|
| `util/forced_photometry.sh` | Shell wrapper: orchestrates pipeline, runs both implementations |
| `src/forced_photometry.c` | C implementation of the aperture measurement |
| `util/forced_photometry` | Compiled C binary (build target) |
| `util/forced_photometry.py` | Python/photutils implementation of the aperture measurement |

## Command-Line Interface

```
util/forced_photometry.sh image.fits HH:MM:SS.ss +DD:MM:SS.s FILTER
```

- `image.fits` -- input FITS image (2D)
- `HH:MM:SS.ss +DD:MM:SS.s` -- target equatorial coordinates (J2000)
- `FILTER` -- photometric filter name (B, V, R, Rc, I, Ic, r, i, g); always required

No aperture diameter argument -- the aperture is always determined
automatically by SExtractor (median A_IMAGE * 6, same as standard VaST
photometry).

## Pipeline Flow (Shell Script)

```
1. Validate inputs:
   a. Check that required VaST tools exist:
      - lib/bin/sky2xy
      - lib/fit_zeropoint
      - util/calibrate_single_image.sh
      - util/get_image_date
      - sextract_single_image_noninteractive (in lib/ or PATH)
   b. Image file exists and is non-empty
   c. Filter name is one of: B, V, R, Rc, I, Ic, r, i, g
2. sextract_single_image_noninteractive image.fits
   -> SExtractor catalog + aperture diameter printed to stdout
3. util/calibrate_single_image.sh image.fits FILTER
   -> plate-solves via solve_plate_with_UCAC5 (if needed)
   -> writes calib.txt (instrumental_mag catalog_mag error)
4. lib/fit_zeropoint
   -> reads calib.txt from current directory (no arguments needed)
   -> writes calib.txt_param:  3.0 0.0 0.0 1.0 <zeropoint>
   -> prints "0.000000 1.000000 <zeropoint>" to stdout
   -> calibration formula: calibrated_mag = inst_mag + zeropoint
5. lib/bin/sky2xy image.fits HH:MM:SS.ss +DD:MM:SS.s
   -> pixel coordinates X, Y
6. util/get_image_date image.fits
   -> extract JD
7. Run C implementation:
   util/forced_photometry image.fits X Y aperture_diameter
   (reads calib.txt_param and bad_region.lst from current directory)
8. Run Python implementation:
   util/forced_photometry.py image.fits X Y aperture_diameter
   (reads calib.txt_param and bad_region.lst from current directory)
9. Print both results for comparison
```

If any step (1-6) fails, the script aborts with an error message.

Steps 2-3 rely on existing VaST infrastructure which internally reuses
cached results (e.g., existing UCAC5 catalog files) when available.

## Output Format

Diagnostic information goes to **stderr**. The measurement goes to
**stdout** as a single line:

```
image.fits  JD  calibrated_mag  mag_err  inst_mag  status
```

Fields:
- `image.fits` -- input image filename (for future multi-image concatenation)
- `JD` -- Julian Date of the observation mid-point
- `calibrated_mag` -- calibrated magnitude (or 3-sigma upper limit)
- `mag_err` -- magnitude error; `99.0` for upper limits and failures
- `inst_mag` -- instrumental magnitude (before calibration); `99.0` for failures
- `status` -- one of:
  - `detection` -- source detected above 3-sigma
  - `upperlimit` -- flux below 3-sigma; calibrated_mag is the 3-sigma limit
  - `saturated` -- saturated pixel(s) within the source aperture
  - `bad_region` -- aperture overlaps with a bad CCD region (bad_region.lst)
  - `edge` -- aperture or background annulus extends beyond image boundary
  - `nan_pixel` -- NaN or Inf pixel(s) within the source aperture
  - `calib_fail` -- magnitude calibration file not found or unreadable

For failure statuses (saturated, bad_region, edge, nan_pixel), magnitude
fields are set to `99.0`.

The shell script prints both C and Python results, clearly labeled:

```
# C implementation:
image.fits  2460234.56789  17.432  0.087  -7.568  detection
# Python implementation:
image.fits  2460234.56789  17.435  0.088  -7.565  detection
```

## Aperture Photometry Algorithm

Both C and Python implementations follow the same algorithm. The C version
implements it from scratch using CFITSIO; the Python version uses photutils
(providing an independent cross-check).

### Coordinate Conversion

The target RA, Dec is converted to pixel coordinates X, Y using WCSTools
`sky2xy` via the image's existing WCS header. No centroiding is performed;
the aperture is placed at the exact computed position.

### Aperture Geometry

- **Source aperture**: circular, diameter = SExtractor auto-detected aperture
  (median A_IMAGE * CONST, where CONST=6, same as standard VaST photometry)
- **Background annulus**: circular annulus with:
  - inner radius = 4.0 * aperture_radius
  - outer radius = 10.0 * aperture_radius

Example: for a 10-pixel diameter aperture (radius=5), the annulus spans
r=20 to r=50 pixels. The large gap between source aperture and background
annulus avoids contamination from source wings, which was found to cause a
systematic ~0.04 mag offset with closer annuli (1.5r-2.5r). The wide
annulus provides enough pixels for a well-measured background, reducing
RMS scatter to ~0.025 mag vs SExtractor (tested on 881 stars).

### Pixel Weighting

**Source aperture**: exact geometric overlap area between the circular
aperture and each square pixel. This uses the Buie/DAOPHOT algorithm
(Intarea/Oneside/Arc/Chord decomposition) which analytically computes the
intersection area of a circle and a rectangle. Reference implementation:
`/mnt/usb2/PoD/photometryondemand/pixwt_circleaperture.py`.

- C implementation: port the Buie algorithm to C (scalar version)
- Python implementation: use photutils `CircularAperture` with `method='exact'`
  (which computes the same geometric intersection internally)

With the `PixwtFast` optimization: pixels whose centers are closer than
`r - 0.75` to the aperture center get weight 1.0; pixels farther than
`r + 0.75` get weight 0.0; only boundary pixels need the full Intarea
computation.

**Background annulus**: center-in/center-out. A pixel is included if its
center falls within the annulus (distance from aperture center >= inner
radius AND < outer radius). No fractional weighting for the annulus.

### Pre-measurement Checks (in order)

1. **Edge check**: the entire outer annulus must fit within the image
   boundaries. If `center - annulus_outer < 1.0` or
   `center + annulus_outer > image_size` in either axis, report `edge`
   failure.

2. **Bad region check**: read `bad_region.lst` (format: either
   `X1 Y1 X2 Y2` rectangle corners, or `X Y` bad point with 1-pixel
   buffer). Use the existing `exclude_region()` logic: if the aperture's
   bounding box overlaps any bad region rectangle, report `bad_region`
   failure. Bad regions overlapping only the annulus (not the aperture) do
   NOT cause failure -- sigma-clipping handles them.

3. **Saturation check**: read `SATUR_LEVEL` from `default.sex` (currently
   55000.0 ADU). If any pixel within the source aperture (weight > 0)
   has a value >= SATUR_LEVEL, report `saturated` failure.

4. **NaN/Inf check**: if any pixel within the source aperture (weight > 0)
   is NaN or Inf, report `nan_pixel` failure. NaN/Inf pixels in the
   background annulus are silently excluded before computing statistics.

### Background Estimation

1. Collect all pixel values whose centers fall within the background annulus.
   Exclude any NaN/Inf values.

2. Compute median and MAD (Median Absolute Deviation) of annulus pixel
   values. Scale MAD to sigma equivalent: `sigma_MAD = 1.4826 * MAD`.

3. **One iteration of sigma clipping**: reject pixels deviating by more than
   `3 * sigma_MAD` from the median.

4. **Safety check**: if fewer than 30% of the original annulus pixels survive
   clipping, fall back to using all (non-NaN) annulus pixels. An
   overestimated sigma is preferable to an underestimated one.

5. Compute final values from surviving pixels:
   - `bg_per_pixel` = median of clipped pixels
   - `sigma_bg` = 1.4826 * MAD of clipped pixels

### Flux Measurement

```
sum_aperture = SUM(pixel_value[i] * weight[i])    for all pixels near aperture
N_eff        = SUM(weight[i])                      effective pixel count
net_flux     = sum_aperture - bg_per_pixel * N_eff
noise        = sigma_bg * sqrt(N_eff)
```

Where `weight[i]` is the exact geometric overlap fraction (0.0 to 1.0) from
the Buie algorithm.

### Detection vs. Upper Limit

```
if net_flux > 3 * noise:
    status       = "detection"
    inst_mag     = -2.5 * log10(net_flux)
    mag_err      = 1.0857 * noise / net_flux
    cal_mag      = inst_mag + zeropoint
else:
    status       = "upperlimit"
    limit_flux   = 3 * sigma_bg * sqrt(N_eff)
    inst_mag_lim = -2.5 * log10(limit_flux)
    cal_mag      = inst_mag_lim + zeropoint
    mag_err      = 99.0
```

The 3-sigma upper limit represents: "a source brighter than this calibrated
magnitude would have been detected at 3-sigma confidence."

### Magnitude Calibration

Calibration uses the same infrastructure as VaST single-image mode:

1. `calibrate_single_image.sh` matches SExtractor detections to the UCAC5
   catalog and writes calibration pairs to `calib.txt`.
2. `lib/fit_zeropoint` (symlink to `fit_mag_calib`) computes a weighted
   mean zero-point offset: `C = SUM(w_i * (catalog_mag_i - inst_mag_i)) / SUM(w_i)`
   and writes `calib.txt_param`.
3. The forced photometry tool reads `calib.txt_param` (5 values:
   `fit_function p3 p2 p1 p0`) and applies:
   `calibrated_mag = p2*inst_mag^2 + p1*inst_mag + p0`
   For fit_zeropoint (fit_function=3): p2=0, p1=1, p0=zeropoint, so
   `calibrated_mag = inst_mag + zeropoint`.

No calibration error propagation is performed. The reported `mag_err`
reflects background noise only, which dominates for faint sources (the
primary use case).

### Error Estimation

For detected sources:
```
mag_err = 1.0857 * noise / net_flux
```

This accounts for background noise only (not Poisson noise from the source
or read noise). This is adequate for faint sources near the detection limit,
which is the primary use case for forced photometry. For brighter sources,
the error is underestimated -- but those sources would typically be detected
by SExtractor and measured through the standard pipeline.

## Known Limitations

1. **Background estimation method**: SExtractor uses mesh-based local
   background estimation; forced photometry uses annulus-based sigma-clipped
   median. For isolated sources on relatively flat backgrounds, the
   difference is negligible. For crowded fields or fields with strong
   gradients, there may be a systematic offset in the instrumental magnitude,
   which propagates through the calibration. Initial validation will use
   simple non-crowded fields where the methods should agree.

2. **No source masking in annulus**: contaminating sources in the background
   annulus are handled only by sigma clipping, not by explicit masking.
   This is sufficient for sparse fields but may bias the background estimate
   in very crowded regions.

3. **No centroiding**: the aperture is placed at the exact WCS-derived
   position. If the WCS has systematic errors, the aperture may be slightly
   offset from the true source position. For well-plate-solved images, this
   should be sub-pixel.

4. **Single calibration type**: currently uses fit_zeropoint only (constant
   offset, slope=1). This is the simplest and most robust calibration but
   does not account for color terms or non-linearity.

5. **Background-only error**: the magnitude error does not include Poisson
   noise from the source itself, so it underestimates the true error for
   bright sources.

6. **No flag image support**: external flag/mask images are not used.
   Bad pixel detection relies on `bad_region.lst`, saturation check, and
   NaN/Inf check.

## C Implementation Notes

- Source file: `src/forced_photometry.c`
- Dependencies: CFITSIO (FITS I/O), math library
- Does NOT depend on: GSL, PGPLOT, WCS library
- Reads: image pixels via `fits_read_img()`, `calib.txt_param`,
  `bad_region.lst`, `SATUR_LEVEL` from `default.sex`
- Implements: Buie circle-rectangle overlap algorithm (ported from
  pixwt_circleaperture.py), sigma-clipped MAD median, `exclude_region()`
  logic (reimplemented or linked from `src/exclude_region.c`)
- FITS pixel convention: 1-based (matching sky2xy output). Array index
  `(iy-1)*naxes[0] + (ix-1)` for pixel (ix, iy).
- All variables declared at function top (C89 compatibility per CLAUDE.md)
- Use `//` for code comments

## Python Implementation Notes

- File: `util/forced_photometry.py`
- Dependencies: astropy (FITS I/O), photutils (aperture photometry), numpy
- Uses `photutils.aperture.CircularAperture` with `method='exact'` for the
  source aperture flux
- Background estimation: use photutils `CircularAnnulus` and
  `ApertureStats` (or equivalent photutils/astropy utilities) for
  sigma-clipped median and MAD in the annulus
- Reads `calib.txt_param` with same parsing as C
- Reads `bad_region.lst` with same logic as C
- Reads `SATUR_LEVEL` from `default.sex`
- FITS pixel convention: 0-based internally (astropy/numpy convention), but
  input X,Y from command line are 1-based (sky2xy output) and converted

## Validation Strategy

1. **C vs. Python**: run both on the same image/position and compare results.
   Agreement within ~0.001 mag confirms correct implementation of the
   aperture measurement algorithm.

2. **Forced photometry vs. SExtractor**: for sources detected by SExtractor,
   compare forced photometry at the SExtractor-detected position to the
   SExtractor catalog magnitude. Agreement within ~0.01-0.05 mag confirms
   that the background estimation difference is small and the calibration
   is applied correctly. This comparison is done externally (not built into
   the forced photometry tool).

3. **Upper limit validation**: for positions far from any source, verify
   that the reported upper limit is consistent with the image depth
   (e.g., compare to the faintest SExtractor detections).
