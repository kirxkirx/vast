#!/usr/bin/env python3
#
# plot_astrometric_residuals_xy.py -- informative diagnostic of the astrometric
# residual vector field across an image.
#
# This is the preferred (richer) replacement for the PGPLOT C tool
# lib/plot_astrometric_residuals_xy, which only plots the (x_pix, y_pix)
# distribution of catalog-matched stars. Here we additionally draw:
#   - the residual VECTOR FIELD (each matched star's measured-minus-catalog
#     offset, exaggerated) coloured by the offset from the catalog position, and
#   - an offset-from-catalog map,
# so a glance tells you whether the WCS is good (small, random residuals) or
# bad (large, spatially-structured residuals -- e.g. a distortion the solution
# failed to model, which throws off the RA/Dec of every detected source and
# makes real stars look like unidentified transients).
#
# Note: throughout this tool "offset" / "residual" means the angular distance
# between a star's measured (WCS) position and its catalog position, in
# arcseconds -- NOT a stellar brightness magnitude.
#
# Input/Output mirror the C tool exactly, so the calling pipeline can use
# either interchangeably:
#   Input : <image>.fits           (residuals read from <image>.fits.wcscat.astrometric_residuals)
#        or <image>.fits.wcscat.astrometric_residuals
#   Output: <image>_astrometric_residuals.png   in the current directory.
#
# The residuals file is written by util/solve_plate_with_UCAC5
# (write_astrometric_residuals_vector_field). Whitespace-separated columns are:
#   1 RA(deg) 2 Dec(deg) 3 dRA(deg) 4 dDec(deg) 5 |resid|(arcsec)
#   6 dRA*cos(Dec)(arcsec) 7 dDec(arcsec) 8 x_pix 9 y_pix
#
# Dependencies: numpy + matplotlib only. If they are missing the script exits
# non-zero with a one-line message so the caller can fall back to the C tool.
# No astropy needed -- image dimensions are read from the FITS header by a
# minimal parser, falling back to the data extent if that fails.

import os
import sys

# Column indices (0-based) in the .wcscat.astrometric_residuals file.
COL_OFFSET = 4      # |resid| = offset from catalog position, arcsec
COL_DX = 5          # dRA*cos(Dec) in arcsec (East-West residual)
COL_DY = 6          # dDec in arcsec (North-South residual)
COL_X = 7           # x_pix
COL_Y = 8           # y_pix
MIN_COLUMNS = 9


def strip_fits_ext(name):
    low = name.lower()
    for ext in (".fits", ".fts", ".fit"):
        if low.endswith(ext):
            return name[: len(name) - len(ext)]
    return name


def derive_paths(arg):
    """Return (residuals_path, fits_path) from either kind of input path."""
    suffix = ".wcscat.astrometric_residuals"
    if arg.endswith(suffix):
        residuals_path = arg
        fits_path = arg[: -len(suffix)]
    else:
        fits_path = arg
        residuals_path = arg + ".wcscat.astrometric_residuals"
    return residuals_path, fits_path


def read_fits_dimensions(fits_path):
    """Read NAXIS1/NAXIS2 from a FITS primary header without astropy.

    Returns (nx, ny) or (None, None) on any failure (caller falls back to the
    data extent). Only the uncompressed primary header is parsed, which is what
    the wcs_-prefixed images written by the pipeline carry.
    """
    try:
        nx = ny = None
        with open(fits_path, "rb") as f:
            while True:
                block = f.read(2880)
                if len(block) < 2880:
                    break
                done = False
                for off in range(0, 2880, 80):
                    card = block[off:off + 80].decode("ascii", "replace")
                    key = card[:8].strip()
                    if key == "END":
                        done = True
                        break
                    if key in ("NAXIS1", "NAXIS2") and card[8:10] == "= ":
                        try:
                            val = int(card[10:].split("/")[0].strip())
                        except ValueError:
                            continue
                        if key == "NAXIS1":
                            nx = val
                        else:
                            ny = val
                if done or (nx is not None and ny is not None):
                    break
        if nx and ny and nx > 0 and ny > 0:
            return nx, ny
    except (IOError, OSError):
        pass
    return None, None


def read_residuals(residuals_path):
    """Return numpy arrays x, y, dx, dy, offset. Raises IOError if unreadable."""
    import numpy as np

    xs, ys, dxs, dys, offsets = [], [], [], [], []
    with open(residuals_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            parts = line.split()
            if len(parts) < MIN_COLUMNS:
                continue
            try:
                xs.append(float(parts[COL_X]))
                ys.append(float(parts[COL_Y]))
                dxs.append(float(parts[COL_DX]))
                dys.append(float(parts[COL_DY]))
                offsets.append(float(parts[COL_OFFSET]))
            except ValueError:
                continue
    return (np.asarray(xs), np.asarray(ys), np.asarray(dxs),
            np.asarray(dys), np.asarray(offsets))


def mad_sigma(values):
    """Robust sigma estimate: 1.4826 * MAD. Returns 0.0 for empty input."""
    import numpy as np
    if values.size == 0:
        return 0.0
    med = np.median(values)
    return float(1.4826 * np.median(np.abs(values - med)))


def main():
    if len(sys.argv) != 2:
        sys.stderr.write(
            "Usage: %s <fits-file | .wcscat.astrometric_residuals>\n" % sys.argv[0])
        return 1

    # Import the heavy dependencies inside a guard so a missing package is a
    # clean, quiet fallback signal rather than a traceback.
    try:
        import numpy as np
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as exc:
        sys.stderr.write(
            "plot_astrometric_residuals_xy.py: numpy/matplotlib unavailable "
            "(%s) -- falling back to the C plotter\n" % exc)
        return 2

    residuals_path, fits_path = derive_paths(sys.argv[1])

    if not os.path.isfile(residuals_path):
        sys.stderr.write(
            "plot_astrometric_residuals_xy.py: residuals file not found: %s "
            "-- nothing to plot\n" % residuals_path)
        return 1

    try:
        x, y, dx, dy, offset = read_residuals(residuals_path)
    except (IOError, OSError) as exc:
        sys.stderr.write(
            "plot_astrometric_residuals_xy.py: cannot read %s (%s)\n"
            % (residuals_path, exc))
        return 1

    n_points = x.size

    nx, ny = read_fits_dimensions(fits_path)
    if nx is None:
        if n_points > 0:
            nx = float(np.max(x)) + 1.0
            ny = float(np.max(y)) + 1.0
        else:
            nx = ny = 1.0

    base = strip_fits_ext(os.path.basename(fits_path)).replace("/", "_")
    png_path = base + "_astrometric_residuals.png"

    # Summary statistics that make the WCS quality self-evident.
    if n_points > 0:
        med_resid = float(np.median(offset))
        max_resid = float(np.max(offset))
        sigma = np.hypot(mad_sigma(dx), mad_sigma(dy))
    else:
        med_resid = max_resid = sigma = 0.0

    if n_points == 0:
        verdict = "NO MATCHED STARS -- plate solution failed for this image"
    elif med_resid < 1.5:
        verdict = "residuals small and random -> good astrometric solution"
    elif med_resid < 5.0:
        verdict = "residuals elevated -> marginal solution"
    else:
        verdict = ("residuals LARGE/structured -> bad WCS; source RA/Dec are "
                   "unreliable (real stars may appear as unidentified transients)")

    # Colour scale capped at the 98th percentile so a few large outliers do
    # not wash out the structure of the bulk of the field.
    if n_points > 0:
        vmax = float(np.percentile(offset, 98))
        if vmax <= 0:
            vmax = max(max_resid, 1e-6)
    else:
        vmax = 1.0

    fig, axes = plt.subplots(1, 2, figsize=(15, 6))

    # ---- Panel A: binned residual vector field ------------------------------
    # Average the per-star residuals into a coarse grid so the vector field is
    # readable (hundreds of overlapping arrows are not). A smooth, organised
    # pattern that grows toward one corner is the signature of an unmodelled
    # distortion; small, random arrows mean a clean solution.
    axA = axes[0]
    if n_points > 0:
        ncx, ncy = 26, 17
        ex = np.linspace(0, nx, ncx + 1)
        ey = np.linspace(0, ny, ncy + 1)
        ix = np.clip(np.digitize(x, ex) - 1, 0, ncx - 1)
        iy = np.clip(np.digitize(y, ey) - 1, 0, ncy - 1)
        gx, gy, gdx, gdy, goffset = [], [], [], [], []
        for cy in range(ncy):
            for cx in range(ncx):
                sel = (ix == cx) & (iy == cy)
                if not np.any(sel):
                    continue
                gx.append(0.5 * (ex[cx] + ex[cx + 1]))
                gy.append(0.5 * (ey[cy] + ey[cy + 1]))
                gdx.append(float(np.mean(dx[sel])))
                gdy.append(float(np.mean(dy[sel])))
                goffset.append(float(np.mean(offset[sel])))
        gx = np.asarray(gx); gy = np.asarray(gy)
        gdx = np.asarray(gdx); gdy = np.asarray(gdy); goffset = np.asarray(goffset)
        # Scale so a typical (cell-mean) arrow spans roughly one grid cell.
        ref = float(np.median(np.hypot(gdx, gdy))) if gx.size else med_resid
        if ref <= 0:
            ref = max(med_resid, 1e-6)
        target_pix = 0.9 * (nx / ncx)
        scale = (ref / target_pix) if target_pix > 0 else 1.0
        q = axA.quiver(gx, gy, gdx, gdy, goffset, angles="xy", scale_units="xy",
                       scale=scale, cmap="inferno", width=0.004,
                       clim=(0, vmax))
        cb = fig.colorbar(q, ax=axA)
        cb.set_label("mean offset from catalog (arcsec)")
        key_len = max(round(ref, 1), 0.1)
        axA.quiverkey(q, 0.82, 1.02, key_len, '%g"' % key_len,
                      labelpos="E", coordinates="axes")
    else:
        axA.text(0.5, 0.5, "no matched stars", ha="center", va="center",
                 transform=axA.transAxes, color="red", fontsize=14)
    axA.set_xlim(0, nx)
    axA.set_ylim(0, ny)
    axA.set_aspect("equal")
    axA.set_xlabel("X (pixels)")
    axA.set_ylabel("Y (pixels)")
    axA.set_title("Astrometric residual vector field (grid-averaged)\n"
                  "arrow = measured position minus catalog position")

    # ---- Panel B: per-star offset-from-catalog map --------------------------
    axB = axes[1]
    if n_points > 0:
        sc = axB.scatter(x, y, c=offset, s=14, cmap="inferno",
                         vmin=0, vmax=vmax, edgecolors="none")
        cb2 = fig.colorbar(sc, ax=axB)
        cb2.set_label("offset from catalog position (arcsec)")
    else:
        axB.text(0.5, 0.5, "no matched stars", ha="center", va="center",
                 transform=axB.transAxes, color="red", fontsize=14)
    axB.set_xlim(0, nx)
    axB.set_ylim(0, ny)
    axB.set_aspect("equal")
    axB.set_xlabel("X (pixels)")
    axB.set_ylabel("Y (pixels)")
    axB.set_title("Catalog-matched stars coloured by offset from catalog position")

    fig.suptitle(
        "%s\n%d matched stars   median=%.2f\"   max=%.1f\"   sigma(MAD)=%.2f\"   "
        "image %gx%g\n%s"
        % (base, n_points, med_resid, max_resid, sigma, nx, ny, verdict),
        fontsize=11)
    fig.tight_layout(rect=(0, 0, 1, 0.93))

    try:
        fig.savefig(png_path, dpi=80)
    except (IOError, OSError) as exc:
        sys.stderr.write(
            "plot_astrometric_residuals_xy.py: failed to write %s (%s)\n"
            % (png_path, exc))
        plt.close(fig)
        return 1
    plt.close(fig)

    # Only claim success if a non-empty file actually landed on disk.
    if os.path.isfile(png_path) and os.path.getsize(png_path) > 0:
        sys.stderr.write(
            "plot_astrometric_residuals_xy.py: wrote %s (%d matched stars from %s, "
            "image %gx%g, median residual %.2f arcsec)\n"
            % (png_path, n_points, residuals_path, nx, ny, med_resid))
        return 0
    sys.stderr.write(
        "plot_astrometric_residuals_xy.py: no output file produced at %s\n"
        % png_path)
    return 1


if __name__ == "__main__":
    sys.exit(main())
