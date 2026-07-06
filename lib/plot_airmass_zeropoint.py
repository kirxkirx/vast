#!/usr/bin/env python3
"""Diagnostic plot for the airmass-aware zero-point fit used by forced photometry.

Usage:
  plot_airmass_zeropoint.py fit_table airmass_param_file output.png title

Inputs:
  fit_table          per-star rows 'airmass resid used_flag' written by
                     util/pixel_flux_airmass_correction --fit-airmass-zeropoint --fit-table
                     (resid is the residual from the constant zero-point, mag)
  airmass_param_file one line: STATUS D0 B X_center k N span sigma X_min X_max
  output.png         output image path
  title              plot title (typically the image basename)

Dependencies: matplotlib only. If it is missing the script prints a one-line
note and exits nonzero; the caller must treat that as "no plot", not an error.
"""

import sys


def main():
    if len(sys.argv) != 5:
        sys.stderr.write(
            "Usage: plot_airmass_zeropoint.py fit_table airmass_param_file output.png title\n")
        return 1
    table_path, param_path, out_png, title = sys.argv[1:5]

    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as exc:
        sys.stderr.write(
            "plot_airmass_zeropoint.py: matplotlib unavailable (%s) - skipping the plot\n" % exc)
        return 1

    try:
        with open(param_path) as f:
            tokens = f.readline().split()
        status = tokens[0]
        d0, slope_b, x_center, k_fitted = [float(v) for v in tokens[1:5]]
        n_used = int(tokens[5])
        span, sigma_fit, x_min, x_max = [float(v) for v in tokens[6:10]]
    except (IOError, IndexError, ValueError) as exc:
        sys.stderr.write("plot_airmass_zeropoint.py: cannot parse %s (%s)\n" % (param_path, exc))
        return 1

    x_used, y_used, x_clip, y_clip = [], [], [], []
    try:
        with open(table_path) as f:
            for line in f:
                parts = line.split()
                if len(parts) < 3:
                    continue
                try:
                    x_val, y_val, used = float(parts[0]), float(parts[1]), int(parts[2])
                except ValueError:
                    continue
                if used == 1:
                    x_used.append(x_val)
                    y_used.append(y_val)
                else:
                    x_clip.append(x_val)
                    y_clip.append(y_val)
    except IOError as exc:
        sys.stderr.write("plot_airmass_zeropoint.py: cannot read %s (%s)\n" % (table_path, exc))
        return 1

    if not x_used and not x_clip:
        sys.stderr.write("plot_airmass_zeropoint.py: no stars in %s - skipping the plot\n" % table_path)
        return 1

    fig, ax = plt.subplots(figsize=(10.0, 6.5))
    if x_clip:
        ax.plot(x_clip, y_clip, "x", color="#bbbbbb", markersize=4, label="clipped")
    if x_used:
        ax.plot(x_used, y_used, "o", color="#4477cc", markersize=2.5,
                label="calibration stars (N=%d)" % n_used)
    ax.axhline(0.0, color="black", linestyle="--", linewidth=1,
               label="constant zero-point")
    if status == "OK":
        line_lo = x_min - 0.02 * max(span, 0.01)
        line_hi = x_max + 0.02 * max(span, 0.01)
        ax.plot([line_lo, line_hi],
                [d0 + slope_b * line_lo, d0 + slope_b * line_hi],
                color="#33aa33", linewidth=2,
                label="airmass zero-point: k=%+.3f mag/airmass" % k_fitted)
        title_color = "black"
        title_suffix = ""
    else:
        title_color = "#cc3333"
        title_suffix = "\n%s - airmass correction NOT applied" % status
    ax.set_xlabel("airmass at the star position")
    ax.set_ylabel("(catalog mag - instrumental mag) - constant zero-point  [mag]")
    # Center the window on the data (robust to a mismatched constant zero-point);
    # the y=0 dashed line of the constant zero-point may then fall off-window,
    # which is itself diagnostic.
    y_ref = sorted(y_used if y_used else y_clip)
    y_center = y_ref[len(y_ref) // 2]
    y_scale = max(0.5, min(2.0, 4.0 * sigma_fit if sigma_fit > 0 else 0.5))
    ax.set_ylim(y_center - y_scale, y_center + y_scale)
    ax.set_title(title + title_suffix, color=title_color, fontsize=11)
    ax.legend(loc="upper left", fontsize=9)
    annotation = "STATUS: %s\nk = %+.4f mag/airmass\nN = %d  span = %.2f airmasses\nscatter = %.3f mag" % (
        status, k_fitted, n_used, span, sigma_fit)
    ax.text(0.98, 0.02, annotation, transform=ax.transAxes, fontsize=9,
            verticalalignment="bottom", horizontalalignment="right",
            bbox=dict(boxstyle="round", facecolor="wheat", alpha=0.7))
    fig.tight_layout()
    try:
        fig.savefig(out_png, dpi=100)
    except IOError as exc:
        sys.stderr.write("plot_airmass_zeropoint.py: cannot write %s (%s)\n" % (out_png, exc))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
