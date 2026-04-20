#!/usr/bin/env python3
"""
Forced aperture photometry at one or more pixel positions on a FITS image.

Usage (single position):
    forced_photometry.py image.fits center_x center_y aperture_diameter
Usage (list mode):
    forced_photometry.py image.fits --list listfile aperture_diameter

List file: one position per line "center_x center_y [label]".
Lines starting with '#' or '%' and blank lines are skipped.
If label is missing, the 1-based line index is used.

center_x, center_y are 1-based pixel coordinates (from sky2xy).
Reads calib.txt_param, bad_region.lst, and default.sex from current directory.
Output (single, stdout): cal_mag mag_err status
Output (list,   stdout): label center_x center_y cal_mag mag_err status

Uses photutils for aperture photometry (independent cross-check of C version).
"""

# Background estimation method:
# Set to True to use SExtractor-style mode estimation
# (mode = 2.5*median - 1.5*mean, with iterative kappa-sigma clipping).
# Set to False to use simple sigma-clipped median with MAD-based sigma.
USE_SEXTRACTOR_BACKGROUND = True

import sys
import os
import math
import numpy as np
from astropy.io import fits
from photutils.aperture import CircularAperture, CircularAnnulus
from photutils.aperture import aperture_photometry
from photutils.background import SExtractorBackground
from astropy.stats import SigmaClip


def read_satur_level_from_default_sex():
    """Parse SATUR_LEVEL from default.sex, return float or 55000.0 default."""
    satur_level = 55000.0
    if not os.path.isfile("default.sex"):
        print("WARNING: cannot open default.sex, using SATUR_LEVEL=%.1f" % satur_level,
              file=sys.stderr)
        return satur_level
    with open("default.sex", "r") as f:
        for line in f:
            line = line.strip()
            if line.startswith("#") or len(line) == 0:
                continue
            parts = line.split()
            if len(parts) >= 2 and parts[0] == "SATUR_LEVEL":
                try:
                    return float(parts[1])
                except ValueError:
                    pass
    print("WARNING: SATUR_LEVEL not found in default.sex, using %.1f" % satur_level,
          file=sys.stderr)
    return satur_level


def read_calib_param():
    """Read calib.txt_param. Returns (p2, p1, p0) or None on failure.
    Format: fit_function p3 p2 p1 p0
    Calibration: cal_mag = p2*x^2 + p1*x + p0
    """
    if not os.path.isfile("calib.txt_param"):
        print("ERROR: cannot open calib.txt_param", file=sys.stderr)
        return None
    with open("calib.txt_param", "r") as f:
        line = f.readline().strip()
    parts = line.split()
    if len(parts) < 5:
        print("ERROR: cannot parse calib.txt_param", file=sys.stderr)
        return None
    try:
        fit_fn = float(parts[0])
        # p3 is parsed but unused (only quadratic p2,p1,p0 are applied)
        _p3 = float(parts[1])
        p2 = float(parts[2])
        p1 = float(parts[3])
        p0 = float(parts[4])
    except ValueError:
        print("ERROR: cannot parse calib.txt_param values", file=sys.stderr)
        return None
    print("Calibration (fit_function=%.0f): cal_mag = %.6f * x^2 + %.6f * x + %.6f" %
          (fit_fn, p2, p1, p0), file=sys.stderr)
    return (p2, p1, p0)


def read_bad_regions():
    """Read bad_region.lst. Returns list of (x1, y1, x2, y2) rectangles."""
    regions = []
    if not os.path.isfile("bad_region.lst"):
        return regions
    with open("bad_region.lst", "r") as f:
        for line in f:
            line = line.strip()
            if len(line) < 3:
                continue
            # Check for comments in first 10 characters
            skip = False
            for i in range(min(len(line), 10)):
                if line[i] in ('#', '%', '/'):
                    skip = True
                    break
                if line[i].isalpha():
                    skip = True
                    break
            if skip:
                continue
            parts = line.split()
            if len(parts) >= 4:
                try:
                    x1, y1, x2, y2 = float(parts[0]), float(parts[1]), \
                                     float(parts[2]), float(parts[3])
                    if x1 > x2:
                        x1, x2 = x2, x1
                    if y1 > y2:
                        y1, y2 = y2, y1
                    regions.append((x1, y1, x2, y2))
                except ValueError:
                    continue
            elif len(parts) >= 2:
                try:
                    x, y = float(parts[0]), float(parts[1])
                    regions.append((x - 1.0, y - 1.0, x + 1.0, y + 1.0))
                except ValueError:
                    continue
    return regions


def check_exclude_region(cx, cy, aperture_diameter, bad_regions):
    """Check if aperture bounding box overlaps any bad region.
    Same logic as exclude_region() in src/exclude_region.c.
    Returns True if excluded."""
    half_ap = aperture_diameter / 2.0
    for (x1, y1, x2, y2) in bad_regions:
        if (cx + half_ap >= x1 and cy + half_ap >= y1 and
                cx - half_ap <= x2 and cy - half_ap <= y2):
            return True
    return False


def photometry_at_position(data, satur_level, bad_regions, calib,
                           center_x, center_y, aperture_diameter):
    """Per-position forced photometry.  Returns (cal_mag, mag_err, status).

    data: 2D numpy array (float64), 0-based indexing, shape (naxis2, naxis1)
    satur_level: float
    bad_regions: list of (x1, y1, x2, y2) 1-based rectangles
    calib: (p2, p1, p0) polynomial
    center_x, center_y: 1-based pixel coords
    aperture_diameter: pixels
    """
    aperture_radius = aperture_diameter / 2.0
    annulus_inner = 4.0 * aperture_radius
    annulus_outer = 10.0 * aperture_radius

    p2, p1, p0 = calib
    naxis2, naxis1 = data.shape

    print("Forced photometry: center=(%.2f, %.2f) aperture=%.1f" %
          (center_x, center_y, aperture_diameter), file=sys.stderr)
    print("Annulus: inner=%.2f outer=%.2f" % (annulus_inner, annulus_outer),
          file=sys.stderr)

    # Edge check (1-based coordinates)
    if (center_x - annulus_outer < 1.0 or center_x + annulus_outer > float(naxis1) or
            center_y - annulus_outer < 1.0 or center_y + annulus_outer > float(naxis2)):
        print("ERROR: aperture/annulus extends beyond image edge", file=sys.stderr)
        return (99.0, 99.0, "edge")

    # Bad region check (1-based)
    if check_exclude_region(center_x, center_y, aperture_diameter, bad_regions):
        print("ERROR: position falls in a bad CCD region (bad_region.lst)",
              file=sys.stderr)
        return (99.0, 99.0, "bad_region")

    # photutils uses 0-based coordinates
    x_py = center_x - 1.0
    y_py = center_y - 1.0

    aperture = CircularAperture((x_py, y_py), r=aperture_radius)
    ap_mask = aperture.to_mask(method='exact')
    ap_weights = ap_mask.data
    cutout = ap_mask.cutout(data, fill_value=0.0)
    if cutout is None:
        print("ERROR: aperture cutout is None (off image?)", file=sys.stderr)
        return (99.0, 99.0, "edge")
    min_y = min(ap_weights.shape[0], cutout.shape[0])
    min_x = min(ap_weights.shape[1], cutout.shape[1])

    for iy in range(min_y):
        for ix in range(min_x):
            if ap_weights[iy, ix] <= 0.0:
                continue
            val = cutout[iy, ix]
            if np.isnan(val) or np.isinf(val):
                print("ERROR: NaN/Inf pixel within aperture", file=sys.stderr)
                return (99.0, 99.0, "nan_pixel")
            if val >= satur_level:
                print("ERROR: saturated pixel value=%.1f >= %.1f" %
                      (val, satur_level), file=sys.stderr)
                return (99.0, 99.0, "saturated")

    # Background annulus
    annulus_aperture = CircularAnnulus((x_py, y_py), r_in=annulus_inner, r_out=annulus_outer)
    ann_mask = annulus_aperture.to_mask(method='center')
    ann_weights = ann_mask.data
    ann_cutout = ann_mask.cutout(data, fill_value=0.0)
    if ann_cutout is None:
        print("ERROR: annulus cutout is None (off image?)", file=sys.stderr)
        return (99.0, 99.0, "edge")

    ann_min_y = min(ann_weights.shape[0], ann_cutout.shape[0])
    ann_min_x = min(ann_weights.shape[1], ann_cutout.shape[1])

    annulus_vals = []
    for iy in range(ann_min_y):
        for ix in range(ann_min_x):
            if ann_weights[iy, ix] <= 0.0:
                continue
            val = ann_cutout[iy, ix]
            if np.isnan(val) or np.isinf(val):
                continue
            annulus_vals.append(val)

    annulus_vals = np.array(annulus_vals)
    n_annulus = len(annulus_vals)

    if n_annulus < 5:
        print("ERROR: too few annulus pixels (%d) for background estimation" % n_annulus,
              file=sys.stderr)
        return (99.0, 99.0, "edge")

    print("Background annulus: %d pixels" % n_annulus, file=sys.stderr)

    if USE_SEXTRACTOR_BACKGROUND:
        sigma_clip = SigmaClip(sigma=3.0, maxiters=50, cenfunc='median', stdfunc='std')
        bkg_estimator = SExtractorBackground(sigma_clip=sigma_clip)
        bg_per_pixel = bkg_estimator.calc_background(annulus_vals)

        clipped = sigma_clip(annulus_vals)
        clipped_vals = clipped.compressed()
        n_clipped = len(clipped_vals)
        if n_clipped < int(0.3 * n_annulus):
            print("WARNING: sigma clipping too aggressive (%d/%d survived), using all pixels"
                  % (n_clipped, n_annulus), file=sys.stderr)
            clipped_vals = annulus_vals
            n_clipped = n_annulus
        sigma_bg = np.std(clipped_vals)

        clip_median = np.median(clipped_vals)
        clip_mean = np.mean(clipped_vals)
        bg_mode = 2.5 * clip_median - 1.5 * clip_mean
        print("SExtractor background: mode=%.2f median=%.2f mean=%.2f sigma=%.2f -> bg=%.2f (%d pixels)"
              % (bg_mode, clip_median, clip_mean, sigma_bg, bg_per_pixel, n_clipped),
              file=sys.stderr)
    else:
        bg_median = np.median(annulus_vals)
        bg_mad = np.median(np.abs(annulus_vals - bg_median))
        sigma_mad = 1.4826 * bg_mad
        print("Background before clipping: median=%.2f MAD=%.2f sigma_MAD=%.2f" %
              (bg_median, bg_mad, sigma_mad), file=sys.stderr)

        mask = np.abs(annulus_vals - bg_median) <= 3.0 * sigma_mad
        clipped_vals = annulus_vals[mask]
        n_clipped = len(clipped_vals)

        if n_clipped < int(0.3 * n_annulus):
            print("WARNING: sigma clipping too aggressive (%d/%d survived), using all pixels"
                  % (n_clipped, n_annulus), file=sys.stderr)
            clipped_vals = annulus_vals
            n_clipped = n_annulus

        bg_per_pixel = np.median(clipped_vals)
        sigma_bg = 1.4826 * np.median(np.abs(clipped_vals - bg_per_pixel))

    print("Background after clipping: median=%.2f sigma=%.2f (%d pixels)" %
          (bg_per_pixel, sigma_bg, n_clipped), file=sys.stderr)

    # Aperture flux
    phot_table = aperture_photometry(data, aperture, method='exact')
    sum_aperture = float(phot_table['aperture_sum'][0])
    n_eff = float(np.sum(ap_weights[:min_y, :min_x]))

    print("Aperture sum=%.2f N_eff=%.4f" % (sum_aperture, n_eff), file=sys.stderr)

    net_flux = sum_aperture - bg_per_pixel * n_eff
    noise = sigma_bg * math.sqrt(n_eff)

    snr = net_flux / noise if noise > 0.0 else 0.0
    print("Net flux=%.2f noise=%.2f SNR=%.2f" % (net_flux, noise, snr), file=sys.stderr)

    if net_flux > 3.0 * noise:
        inst_mag = -2.5 * math.log10(net_flux)
        mag_err = 1.0857 * noise / net_flux
        status_str = "detection"
    else:
        inst_mag = -2.5 * math.log10(3.0 * noise) if noise > 0.0 else 99.0
        mag_err = 99.0
        status_str = "upperlimit"

    print("Instrumental magnitude: %.4f" % inst_mag, file=sys.stderr)

    cal_mag = p2 * inst_mag * inst_mag + p1 * inst_mag + p0
    print("Calibrated magnitude: %.4f" % cal_mag, file=sys.stderr)

    return (cal_mag, mag_err, status_str)


def iter_list_file(list_filename):
    """Yield (line_idx, center_x, center_y, label) for each valid input row.

    Skips blank/comment lines and lines that fail to parse.  Labels default
    to the 1-based line index when not provided."""
    with open(list_filename, "r") as f:
        line_idx = 0
        for raw in f:
            line_idx += 1
            line = raw.strip()
            if len(line) == 0:
                continue
            if line[0] in ('#', '%'):
                continue
            parts = line.split()
            if len(parts) < 2:
                print("WARNING: list line %d: could not parse center_x center_y: %s"
                      % (line_idx, raw.rstrip()), file=sys.stderr)
                continue
            try:
                cx = float(parts[0])
                cy = float(parts[1])
            except ValueError:
                print("WARNING: list line %d: could not parse center_x center_y: %s"
                      % (line_idx, raw.rstrip()), file=sys.stderr)
                continue
            label = parts[2] if len(parts) >= 3 else str(line_idx)
            yield (line_idx, cx, cy, label)


def main():
    if len(sys.argv) != 5:
        print("Usage:", file=sys.stderr)
        print("  %s image.fits center_x center_y aperture_diameter" % sys.argv[0],
              file=sys.stderr)
        print("  %s image.fits --list listfile aperture_diameter" % sys.argv[0],
              file=sys.stderr)
        sys.exit(1)

    fitsfilename = sys.argv[1]
    list_mode = (sys.argv[2] == "--list")

    if list_mode:
        list_filename = sys.argv[3]
        try:
            aperture_diameter = float(sys.argv[4])
        except ValueError:
            print("ERROR: aperture_diameter must be a number", file=sys.stderr)
            sys.exit(1)
    else:
        try:
            center_x = float(sys.argv[2])
            center_y = float(sys.argv[3])
            aperture_diameter = float(sys.argv[4])
        except ValueError:
            print("ERROR: could not parse numeric arguments", file=sys.stderr)
            sys.exit(1)

    if aperture_diameter <= 0.0:
        print("ERROR: aperture_diameter must be positive", file=sys.stderr)
        sys.exit(1)

    if list_mode:
        print("Forced photometry (list mode): image=%s list=%s aperture=%.1f" %
              (fitsfilename, list_filename, aperture_diameter), file=sys.stderr)
    else:
        print("Forced photometry: image=%s center=(%.2f, %.2f) aperture=%.1f" %
              (fitsfilename, center_x, center_y, aperture_diameter), file=sys.stderr)

    # Load image once
    with fits.open(fitsfilename) as hdul:
        data = hdul[0].data
    if data is None or data.ndim != 2:
        print("ERROR: expected a 2D FITS image", file=sys.stderr)
        sys.exit(1)
    data = data.astype(np.float64)
    naxis2, naxis1 = data.shape
    print("Image size: %d x %d" % (naxis1, naxis2), file=sys.stderr)

    # Load bad regions, saturation, calibration once
    bad_regions = read_bad_regions()
    satur_level = read_satur_level_from_default_sex()
    print("Saturation level: %.1f" % satur_level, file=sys.stderr)
    calib = read_calib_param()

    def emit_calib_fail_single():
        print("99.0000 99.0000 calib_fail")

    def emit_calib_fail_list():
        for _idx, cx, cy, label in iter_list_file(list_filename):
            print("%s %.4f %.4f 99.0000 99.0000 calib_fail" % (label, cx, cy))

    if calib is None:
        print("ERROR: magnitude calibration failed", file=sys.stderr)
        if list_mode:
            emit_calib_fail_list()
        else:
            emit_calib_fail_single()
        sys.exit(0)

    if list_mode:
        for _idx, cx, cy, label in iter_list_file(list_filename):
            cal_mag, mag_err, status = photometry_at_position(
                data, satur_level, bad_regions, calib, cx, cy, aperture_diameter)
            print("%s %.4f %.4f %.4f %.4f %s" %
                  (label, cx, cy, cal_mag, mag_err, status))
    else:
        cal_mag, mag_err, status = photometry_at_position(
            data, satur_level, bad_regions, calib,
            center_x, center_y, aperture_diameter)
        print("%.4f %.4f %s" % (cal_mag, mag_err, status))


if __name__ == "__main__":
    main()
