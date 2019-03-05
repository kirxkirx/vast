#! /usr/bin/env python

from __future__ import division

import sys
import argparse
import logging
import warnings
import numpy as np
from scipy.optimize import minimize
from astropy.io import fits
from astropy.wcs import WCS, Wcsprm as WCSParam
from astropy.wcs.wcs import FITSFixedWarning


def setup_logger(verbose=0):
    logger = logging.getLogger(__name__)
    formatter = logging.Formatter("%(message)s")
    handler = logging.StreamHandler()
    handler.setFormatter(formatter)
    handler.setLevel('DEBUG')
    logger.addHandler(handler)
    logger.setLevel(['WARNING', 'INFO', 'DEBUG'][verbose])


def error(x, tra, tdec, pixels, wcs, order, radial):
    pv = x.reshape(2, -1)
    ra, dec = wcs2pv(pv, pixels, wcs, order=order, radial=radial)
    dra = tra - ra
    ddec = tdec - dec
    return np.sum(dra*dra + ddec*ddec)


def wcs2pv(pv, pixels, wcs, order=3, radial=False):
    """Convert x-y pixel arrays using the base WCS and pv distortion
    coefficients"""

    cd = wcs.cd
    dpx = pixels[0,...] - wcs.crpix[0]
    dpy = pixels[1,...] - wcs.crpix[1]
    x = cd[0,0] * dpx + cd[0,1] * dpy
    y = cd[1,0] * dpx + cd[1,1] * dpy

    r = np.sqrt(x*x + y*y) if radial else 0
    # To do: transform this to a matrix multiplication, or a smart loop
    pvx = pv[0,...]
    xy = [x, y]
    coords = [x, y]
    for i in range(2):
        ppv = pv[i,...]
        xi = xy[i]
        eta = xy[1-i]
        corr = xi + ppv[2] * eta + ppv[3] * r
        if order > 1:
            xi2 = xi*xi
            eta2 = eta*eta
            corr += ppv[4] * xi2 + ppv[5] * xi * eta + ppv[6] * eta2
        if order > 2:
            xi3 = xi2*xi
            eta3 = eta2*eta
            r3 = r*r*r
            corr += ppv[7] * xi3 + ppv[8] * xi2 * eta
            corr += ppv[9] * xi * eta2 + ppv[10] * eta3
            corr += ppv[11] * r3
        if order > 3:
            xi4 = xi3*xi
            eta4 = eta3*eta
            corr += ppv[12] * xi4 + ppv[13] * xi3 * eta
            corr += ppv[14] * xi2 * eta2 + ppv[15] * xi * eta3
            corr += ppv[16] * eta4
        if order > 4:
            xi5 = xi4*xi
            eta5 = eta4*eta
            r5 = r3*r*r
            corr += ppv[17] * xi5 + ppv[18] * xi4 * eta
            corr += ppv[19] * xi3 * eta2 + ppv[20] * xi2 * eta3
            corr += ppv[21] * xi * eta4 + ppv[22] * eta5
            corr += ppv[23] * r5
        if order > 5:
            xi6 = xi5*xi
            eta6 = eta5*eta
            corr += ppv[24] * xi6 + ppv[18] * xi5 * eta
            corr += ppv[26] * xi4 * eta2 + ppv[20] * xi3 * eta3
            corr += ppv[28] * xi2 * eta4 + ppv[22] * xi * eta5
            corr += ppv[30] * eta6
        if order > 6:
            xi7 = xi6*xi
            eta7 = eta6*eta
            r7 = r5*r*r
            corr += ppv[31] * xi7 + ppv[32] * xi6 * eta
            corr += ppv[33] * xi5 * eta2 + ppv[34] * xi4 * eta3
            corr += ppv[35] * xi3 * eta4 + ppv[36] * xi2 * eta5
            corr += ppv[37] * xi * eta2 + ppv[38] * eta7
            corr += ppv[39] * r7
        coords[i] = corr


    x, y = coords

    r = np.sqrt(x*x + y*y)
    phi = np.arctan2(x, -y)
    theta = np.arctan(180/np.pi / r)

    raref = wcs.crval[0]
    decref = wcs.crval[1]

    arg = np.sin(theta) * np.sin(decref) - np.cos(theta) * np.cos(phi) * np.cos(decref)
    dec = np.arcsin(arg)
    arg = np.cos(theta) * np.sin(phi) / np.cos(dec)
    ra = np.arcsin(arg)
    ra += raref

    return ra, dec


def addpv(header, order=5, radial=False, ndata=64):
    logger = logging.getLogger(__name__)

    if isinstance(ndata, (tuple, list)):
        ndata = dict(x=ndata[0], y=ndata[1])
    elif not isinstance(ndata, dict):
        ndata = dict(x=ndata, y=ndata)

    header = header.copy()
    crpix = dict(x=header['crpix1'], y=header['crpix2'])
    shape = dict(x=header['naxis1'], y=header['naxis2'])
    crval = dict(x=header['crval1'], y=header['crval2'])

    with warnings.catch_warnings():
        warnings.filterwarnings(
            'ignore', category=FITSFixedWarning, message="Removed redundant "
            "SCAMP distortion parameters because SIP parameters "
            "are also present")
        wcs = WCS(header)

    start, step = {}, {}
    if shape['x'] >= ndata['x']:
        step['x'] = shape['x'] // ndata['x']
        start['x'] = (shape['x'] % ndata['x']) // 2
    else:
        step['x'] = 1
        start['x'] = 0
    if shape['y'] >= ndata['y']:
        step['y'] = shape['y'] // ndata['y']
        start['y'] = (shape['y'] % ndata['y']) // 2
    else:
        step['y'] = 1
        start['y'] = 0

    xpix, ypix = np.mgrid[start['x']:shape['x']:step['x'],
                          start['y']:shape['y']:step['y']]


    px = xpix.ravel()
    py = ypix.ravel()
    ra, dec = wcs.all_pix2world(px, py, 1)

    mask = slice(55, 60)
    ra, dec = wcs.wcs_pix2world(px, py, 1)

    cd = wcs.pixel_scale_matrix
    dpx = px - crpix['x']
    dpy = py - crpix['y']
    x = cd[0,0] * dpx + cd[0,1] * dpy
    y = cd[1,0] * dpx + cd[1,1] * dpy

    r = np.sqrt(x*x + y*y)
    phi = np.arctan2(x, -y)
    theta = np.arctan(180/np.pi / r)

    raref = np.radians(crval['x'])
    decref = np.radians(crval['y'])

    arg = np.sin(theta) * np.sin(decref) - np.cos(theta) * np.cos(phi) * np.cos(decref)
    dec = np.arcsin(arg)
    arg = np.cos(theta) * np.sin(phi) / np.cos(dec)
    ra = np.arcsin(arg)
    ra += raref

    dec = np.degrees(dec)
    ra = np.degrees(ra)

    # Set up the args for minimization
    tra, tdec = wcs.all_pix2world(px, py, 1)
    tra, tdec = np.radians(tra), np.radians(tdec)
    p = np.zeros(2*40)
    p[1] = 1
    p[41] = 1
    pv = p.reshape(2, -1)
    pixels = np.asarray([px, py])
    wcspv = WCSParam()
    wcspv.cd = wcs.wcs.cd.copy()
    wcspv.crpix = wcs.wcs.crpix.copy()
    wcspv.crval = np.radians(wcs.wcs.crval)

    ra, dec = wcs2pv(pv, pixels, wcspv)
    args = tra, tdec, pixels, wcspv, order, radial

    before = error(p, *args)

    results = minimize(error, p, args)

    pv = results['x'].reshape(2, -1)
    after = error(results['x'], *args)

    pv[np.abs(pv) < np.finfo(pv.dtype).tiny] = 0.0

    logger.debug("New PV keywords:")
    for i in range(pv.shape[-1]):
        if pv[0,i] != 0.0:
            key = "PV1_{i:d}".format(i=i)
            header[key] = pv[0,i]
            logger.debug("%s = %f", key, pv[0, i])
        if pv[1,i] != 0.0:
            key = "PV2_{i:d}".format(i=i)
            header[key] = pv[1,i]
            logger.debug("%s = %f", key, pv[0, i])

    fraction = before / after
    logger.info("Difference improvement = %.5e / %.5e = %.2f%%",
                before, after, 100*fraction)

    return header



def parse_args():
    def nargs_range(nmin, nmax):
        class NargsRange(argparse.Action):
            def __call__(self, parser, args, values, option_string=None):
                if not nmin <= len(values) <= nmax:
                    msg = '"{f}" requires between {nmin} and {nmax} arguments'.format(
                        f=self.dest, nmin=nmin, nmax=nmax)
                    raise argparse.ArgumentTypeError(msg)
                setattr(args, self.dest, values)
        return NargsRange


    parser = argparse.ArgumentParser()
    parser.add_argument('files', nargs='+',
                        help="Input FITS files")
    parser.add_argument('-o', '--order', type=int,
                        help="PV order")
    parser.add_argument('-r', '--radial', action='store_true',
                        help="Use the radial term")
    parser.add_argument('-n', '--ndata', type=int, default=[64, 64],
                        action=nargs_range(1, 2), nargs='+',
                        help="Use n x n pixels to solve")
    parser.add_argument('--ext', action='append',
                        help="Extension to correct; "
                        "option can be used multiple times. "
                        "Default is the primary hdu.")
    parser.add_argument('-v', '--verbose', action='count', default=0,
                        help="Verbose level")
    args = parser.parse_args()

    if len(args.ndata) == 1:
        args.ndata = [args.ndata[0], args.ndata[0]]
    if not args.ext:
        args.ext = [0]

    return args


def main(files, order=None, radial=False, ndata=64, extensions=None):
    logger = logging.getLogger(__name__)
    if extensions is None:
        extensions = [0]
    for filename in args.files:
        with fits.open(filename, mode='update') as hdulist:
            for ext in extensions:
                try:
                    ext = int(ext)
                except ValueError:
                    pass
                hdu = hdulist[ext]
                if order is None:
                    order = hdu.header.get('A_ORDER')
                    logger.info("Order determined from SIP x-order: %d", order)
                if order is None:
                    logger.warning("No order given, and no SIP order found. "
                                   "%s[%d] is ignored", filename, ext)

                hdu.header = addpv(hdu.header, order=order, radial=radial,
                                   ndata=ndata)

                # For some reason, astropy.io.fits doesn't update a
                # CompImageHDU; recreate it instead
                hdulist[ext] = type(hdu)(data=hdu.data, header=hdu.header)


if __name__ == '__main__':
    args = parse_args()
    setup_logger(args.verbose)
    main(args.files, order=args.order, radial=args.radial, ndata=args.ndata,
         extensions=args.ext)
