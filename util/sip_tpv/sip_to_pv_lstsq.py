#!/usr/bin/env python
#
# Convert SIP distortion (TAN-SIP) FITS WCS to the TPV convention that Swarp
# and Scamp understand, using only numpy + astropy (no sympy).
#
# This is a drop-in, dependency-light alternative to util/sip_tpv/sip_to_pv.py.
# The upstream sip_tpv package derives the SIP->TPV relations symbolically with
# sympy.  On machines where sympy is not installed the symbolic converter fails
# to import, and if that failure is ignored Swarp silently resamples the image
# using only the linear CD matrix -- discarding the polynomial distortion.  For
# wide-field, strongly-distorted detectors (e.g. TESS FFIs, whose astrometric
# solution needs 6th-order SIP) that produces position errors of tens of pixels
# (hundreds of arcsec), which is exactly the kind of large finder-chart offset
# this script exists to avoid.
#
# Instead of a symbolic derivation we fit the TPV polynomial numerically:
# TPV and SIP are two ways of writing the same distorted mapping, so we sample
# the SIP model on a pixel grid and solve for the PV coefficients by linear
# least squares.  The TPV term ordering is the standard Scamp/wcslib one, and
# matches util/sip_tpv/pvsiputils.py::compute_tpv() (radial terms PV*_3, _11,
# _23, _39 are left out, as SIP has no radial term).
#
# Usage:
#   sip_to_pv_lstsq.py infile.fits outfile.fits [--extension N] [--overwrite]
#
from __future__ import print_function, absolute_import, division
import sys
import numpy as np
import astropy.io.fits as fits
from astropy import wcs as astropy_wcs

# (p, q) powers of (x, y) for each PV index 0..38, radial terms (3,11,23,39)
# excluded.  This is exactly the monomial layout of pvsiputils.compute_tpv()
# for axis 1.  For axis 2 the roles of x and y are swapped (see below).
PV_TERMS = {
    0: (0, 0),
    1: (1, 0), 2: (0, 1),
    4: (2, 0), 5: (1, 1), 6: (0, 2),
    7: (3, 0), 8: (2, 1), 9: (1, 2), 10: (0, 3),
    12: (4, 0), 13: (3, 1), 14: (2, 2), 15: (1, 3), 16: (0, 4),
    17: (5, 0), 18: (4, 1), 19: (3, 2), 20: (2, 3), 21: (1, 4), 22: (0, 5),
    24: (6, 0), 25: (5, 1), 26: (4, 2), 27: (3, 3), 28: (2, 4), 29: (1, 5),
    30: (0, 6),
    31: (7, 0), 32: (6, 1), 33: (5, 2), 34: (4, 3), 35: (3, 4), 36: (2, 5),
    37: (1, 6), 38: (0, 7),
}


def _sip_forward_offsets(header):
    """Return the CD matrix and, on a pixel grid covering the image, the
    linear intermediate coords (x, y) and the full-SIP intermediate coords
    (xt, yt), all in degrees."""
    w = astropy_wcs.WCS(header)
    naxis1 = int(header['NAXIS1'])
    naxis2 = int(header['NAXIS2'])
    crpix1 = float(header['CRPIX1'])
    crpix2 = float(header['CRPIX2'])
    cd = w.wcs.cd if w.wcs.has_cd() else w.wcs.get_pc() * w.wcs.cdelt

    # Sample generously so the fit is well conditioned up to 7th order.
    n = 40
    gx = np.linspace(1, naxis1, n)
    gy = np.linspace(1, naxis2, n)
    gx, gy = np.meshgrid(gx, gy)
    u = gx.ravel() - crpix1  # pixel offset from reference (SIP u,v)
    v = gy.ravel() - crpix2

    # Full SIP forward distortion: (U, V) = (u + A(u,v), v + B(u,v))
    if w.sip is not None:
        fu = w.sip.foc2pix  # not used; evaluate via polynomials below
    du = _eval_sip(w.sip.a, u, v) if (w.sip is not None) else 0.0
    dv = _eval_sip(w.sip.b, u, v) if (w.sip is not None) else 0.0
    U = u + du
    V = v + dv

    # Intermediate world coords (degrees): apply CD.
    x = cd[0, 0] * u + cd[0, 1] * v      # linear-only -> TPV input
    y = cd[1, 0] * u + cd[1, 1] * v
    xt = cd[0, 0] * U + cd[0, 1] * V     # full SIP    -> TPV target
    yt = cd[1, 0] * U + cd[1, 1] * V
    return cd, x, y, xt, yt


def _eval_sip(coeff, u, v):
    """Evaluate a SIP coefficient matrix (astropy sip.a / sip.b) at (u, v)."""
    order = coeff.shape[0] - 1
    out = np.zeros_like(u, dtype=float)
    for i in range(order + 1):
        for j in range(order + 1 - i):
            c = coeff[i, j]
            if c != 0.0:
                out += c * u ** i * v ** j
    return out


def _fit_axis(x, y, target, swap):
    """Least-squares fit of TPV coefficients so poly(x,y) == target.
    swap=False for axis 1 (monomials x**p * y**q), swap=True for axis 2
    (x and y exchanged, per the TPV convention)."""
    idx = sorted(PV_TERMS)
    cols = []
    for k in idx:
        p, q = PV_TERMS[k]
        if not swap:
            cols.append(x ** p * y ** q)
        else:
            cols.append(y ** p * x ** q)
    A = np.vstack(cols).T
    coeff, _, _, _ = np.linalg.lstsq(A, target, rcond=None)
    resid = A.dot(coeff) - target
    return dict(zip(idx, coeff)), np.max(np.abs(resid))


def sip_to_pv(header):
    """Convert SIP keywords in *header* to TPV in place."""
    cd, x, y, xt, yt = _sip_forward_offsets(header)
    pv1, r1 = _fit_axis(x, y, xt, swap=False)
    pv2, r2 = _fit_axis(x, y, yt, swap=True)

    # The fit residual is in degrees of intermediate coordinate; convert to a
    # rough pixel figure using the CD scale so we can sanity-check it.
    scale = np.sqrt(abs(cd[0, 0] * cd[1, 1] - cd[0, 1] * cd[1, 0]))
    resid_pix = max(r1, r2) / scale
    if resid_pix > 0.05:
        sys.stderr.write(
            "WARNING sip_to_pv_lstsq: TPV fit residual %.3g pix exceeds 0.05 "
            "pix -- distortion may be poorly represented\n" % resid_pix)

    _remove_sip_keywords(header)
    header['CTYPE1'] = 'RA---TPV'
    header['CTYPE2'] = 'DEC--TPV'
    for k, val in sorted(pv1.items()):
        header['PV1_%d' % k] = float(val)
    for k, val in sorted(pv2.items()):
        header['PV2_%d' % k] = float(val)
    return resid_pix


def _remove_sip_keywords(header):
    order = int(header.get('A_ORDER', 0))
    aporder = int(header.get('AP_ORDER', 0))
    for i in range(order + 1):
        for j in range(order + 1):
            for base in ('A_%d_%d', 'B_%d_%d'):
                header.remove(base % (i, j), ignore_missing=True)
    for i in range(aporder + 1):
        for j in range(aporder + 1):
            for base in ('AP_%d_%d', 'BP_%d_%d'):
                header.remove(base % (i, j), ignore_missing=True)
    for kw in ('A_ORDER', 'B_ORDER', 'AP_ORDER', 'BP_ORDER',
               'A_DMAX', 'B_DMAX'):
        header.remove(kw, ignore_missing=True)


def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="Convert FITS SIP distortion to TPV (numpy least squares, "
                    "no sympy).")
    parser.add_argument('infile', help='input FITS file with SIP distortion')
    parser.add_argument('outfile', help='output FITS file (TPV)')
    parser.add_argument('--extension', type=int, default=0,
                        help='HDU with the SIP header (default 0)')
    parser.add_argument('--overwrite', action='store_true')
    args = parser.parse_args()

    hdu = fits.open(args.infile)
    header = hdu[args.extension].header
    if 'A_ORDER' not in header and 'B_ORDER' not in header:
        sys.stderr.write("sip_to_pv_lstsq: no SIP keywords in %s -- nothing to "
                         "do\n" % args.infile)
        sys.exit(2)
    resid = sip_to_pv(header)
    hdu[args.extension].header = header
    hdu.writeto(args.outfile, overwrite=args.overwrite)
    print("sip_to_pv_lstsq: wrote %s (max fit residual %.3g pix)"
          % (args.outfile, resid))


if __name__ == '__main__':
    main()
