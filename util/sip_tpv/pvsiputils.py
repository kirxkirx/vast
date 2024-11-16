from __future__ import print_function, absolute_import, division

# Licensed under a 3-clause BSD style license - see LICENSE.txt
"""
Convert SIP convention distortion keywords to the TPV convention.

This module includes the equations for converting from the SIP distortion representation
 to the PV or TPV representations, following the SPIE proceedings paper at
     http://proceedings.spiedigitallibrary.org/proceeding.aspx?articleid=1363103
     and http://web.ipac.caltech.edu/staff/shupe/reprints/SIP_to_PV_SPIE2012.pdf .
The work described in that paper is extended to 7th order.

Copyright (c) 2012-2017, California Institute of Technology

If you make use of this work, please cite:
"More flexibility in representing geometric distortion in astronomical images,"
  Shupe, David L.; Laher, Russ R.; Storrie-Lombardi, Lisa; Surace, Jason; Grillmair, Carl;
  Levitan, David; Sesar, Branimir, 2012, in Software and Cyberinfrastructure for
  Astronomy II. Proceedings of the SPIE, Volume 8451, article id. 84511M.

Thanks to Octavi Fors for contributing code modifications for better modularization,
   and for extensive testing.

Funding is acknowledged from NASA to the NASA Herschel Science Center and the
   Spitzer Science Center.

Contact: David Shupe, Caltech/IPAC.

"""

from sympy import symbols, Matrix, poly
import numpy as np
from reverse import fitreverse


def sym_tpvexprs():
    """ calculate the Sympy expression for TPV distortion

    Parameters:
    -----------
    None

    Returns:
    --------
    pvrange (list) : indices to the PV keywords
    tpvx (Sympy expr) : equation for x-distortion in TPV convention
    tpvy (Sympy expr) : equation for y-distortion in TPV convention
    """
    pvrange = list(range(0, 39))
    pvrange.remove(3)
    pvrange.remove(11)
    pvrange.remove(23)
    pv1 = symbols('pv1_0:39')
    pv2 = symbols('pv2_0:39')
    x, y = symbols("x y")
    tpvx, tpvy = compute_tpv(pv1, pv2, x, y)
    tpvx.expand()
    tpvy.expand()
    return pvrange, tpvx, tpvy


def compute_tpv(pv1, pv2, x, y):
    """ Compute the distortion equations for the TPV convention

    Parameters:
    -----------
    pv1 (array-like): PV coefficients for axis 1
    pv2 (array-like): PV coefficients for axis 2
    x,y (number or symbol): coordinates in plane-of-projection

    Returns:
    --------
    tpvx(Sympy expr or number) : equation for x-distortion in TPV convention
    tpvy (Sympy expr or number) : equation for y-distortion in TPV convention
    """
    # Copy the equations from the PV-to-SIP paper and convert to code,
    #  leaving out radial terms PV[1,3], PV[1,11], PV[1,23], PV[1,39]
    tpvx = pv1[0] + pv1[1]*x + pv1[2]*y + pv1[4]*x**2 + pv1[5]*x*y + pv1[6]*y**2 + \
        pv1[7]*x**3 + pv1[8]*x**2*y + pv1[9]*x*y**2 + pv1[10]*y**3 +  \
        pv1[12]*x**4 + pv1[13]*x**3*y + pv1[14]*x**2*y**2 + pv1[15]*x*y**3 + pv1[16]*y**4 + \
        pv1[17]*x**5 + pv1[18]*x**4*y + pv1[19]*x**3*y**2 + pv1[20]*x**2*y**3 + pv1[21]*x*y**4 + \
        pv1[22]*y**5 + \
        pv1[24]*x**6 + pv1[25]*x**5*y + pv1[26]*x**4*y**2 + pv1[27]*x**3*y**3 + \
        pv1[28]*x**2*y**4 + pv1[29]*x*y**5 + pv1[30]*y**6 + \
        pv1[31]*x**7 + pv1[32]*x**6*y + pv1[33]*x**5*y**2 + pv1[34]*x**4*y**3 + \
        pv1[35]*x**3*y**4 + pv1[36]*x**2*y**5 + pv1[37]*x*y**6 + pv1[38]*y**7

    tpvy = pv2[0] + pv2[1]*y + pv2[2]*x + pv2[4]*y**2 + pv2[5]*y*x + pv2[6]*x**2 + \
        pv2[7]*y**3 + pv2[8]*y**2*x + pv2[9]*y*x**2 + pv2[10]*x**3 + \
        pv2[12]*y**4 + pv2[13]*y**3*x + pv2[14]*y**2*x**2 + pv2[15]*y*x**3 + pv2[16]*x**4 + \
        pv2[17]*y**5 + pv2[18]*y**4*x + pv2[19]*y**3*x**2 + pv2[20]*y**2*x**3 + pv2[21]*y*x**4 + \
        pv2[22]*x**5 + \
        pv2[24]*y**6 + pv2[25]*y**5*x + pv2[26]*y**4*x**2 + pv2[27]*y**3*x**3 + \
        pv2[28]*y**2*x**4 + pv2[29]*y*x**5 + pv2[30]*x**6 + \
        pv2[31]*y**7 + pv2[32]*y**6*x + pv2[33]*y**5*x**2 + pv2[34]*y**4*x**3 + \
        pv2[35]*y**3*x**4 + pv2[36]*y**2*x**5 + pv2[37]*y*x**6 + pv2[38]*x**7

    return tpvx, tpvy


def sym_sipexprs():
    """ calculate the Sympy expression for SIP distortion

    Parameters:
    -----------
    None

    Returns:
    --------
    sipu (Sympy expr) : equation for u-distortion in SIP convention
    sipv (Sympy expr) : equation for v-distortion in SIP convention
    """
    u, v = symbols('u v')

    sipu = 0
    sipv = 0
    for m in range(8):
        for n in range(0, 8-m):
            ac = symbols('a_%d_%d' % (m, n))
            bc = symbols('b_%d_%d' % (m, n))
            sipu += ac*u**m*v**n
            sipv += bc*u**m*v**n
    sipu.expand()
    sipv.expand()
    return sipu, sipv


def calcpv(pvrange, pvinx1, pvinx2, sipx, sipy, tpvx, tpvy):
    """Calculate the PV coefficient expression as a function of CD matrix
    parameters and SIP coefficients

    Parameters:
    -----------
    pvrange (list) : indices to the PV keywords
    pvinx1 (int): first index, 1 or 2
    pvinx2 (int): second index
    tpvx (Sympy expr) : equation for x-distortion in TPV convention
    tpvy (Sympy expr) : equation for y-distortion in TPV convention
    sipx (Sympy expr) : equation for x-distortion in SIP convention
    sipy (Sympy expr) : equation for y-distortion in SIP convention

    Returns:
    --------
    Expression of CD matrix elements and SIP polynomial coefficients
    """
    x, y = symbols("x y")
    if pvinx1 == 1:
        expr1 = tpvx
        expr2 = sipx
    elif pvinx1 == 2:
        expr1 = tpvy
        expr2 = sipy
    else:
        raise ValueError('incorrect first index to PV keywords')
    if pvinx2 not in pvrange:
        raise ValueError('incorrect second index to PV keywords')
    pvar = symbols('pv%d_%d' % (pvinx1, pvinx2))
    xord = yord = 0
    if expr1.coeff(pvar).has(x):
        xord = poly(expr1.coeff(pvar)).degree(x)
    if expr1.coeff(pvar).has(y):
        yord = poly(expr1.coeff(pvar)).degree(y)

    return expr2.coeff(x, xord).coeff(y, yord)


def calcsip(axis, m, n, sipu, sipv, tpvu, tpvv):
    """Calculate the SIP coefficient expression as a function of CD matrix
    parameters and PV coefficients

    Parameters:
    -----------
    axis (1 or 2): axis to compute
    m (int) : order of SIP coefficient in u
    n (int) : order of SIP coefficient in v
    sipu (Sympy expr) : symbolic equation for u-distortion in SIP convention
    sipv (Sympy expr) : symbolic equation for v-distortion in SIP convention
    tpvu (Sympy expr) : equation for u-distortion w/TPV coeffiecients
    tpvv (Sympy expr) : equation for v-distortion w/TPV coefficients

    Returns:
    --------
    Expression of CD matrix elements and TPV polynomial coefficients
    """
    u, v = symbols("u v")
    if axis == 1:
        expr2 = tpvu
    elif axis == 2:
        expr2 = tpvv
    rval = expr2.coeff(u, m).coeff(v, n)
    if (axis == 1) and (m == 1) and (n == 0):
        rval = rval - 1.0
    elif (axis == 2) and (m == 0) and (n == 1):
        rval = rval - 1.0
    return rval


def get_sip_keywords(header):
    """Return the CD matrix and SIP coefficients from a Header object

    Parameters:
    -----------
    header (fits.Header) : header object from a FITS file

    Returns:
    --------
    cd (numpy.matrix) : the CD matrix from the FITS header
    ac (numpy.matrix) : the A-coefficients from the FITS header
    bc (numpy.matrix) : the B-coefficients from the FITS header
    """
    cd = np.matrix([[header.get('CD1_1', 0.0), header.get('CD1_2', 0.0)],
                    [header.get('CD2_1', 0.0), header.get('CD2_2', 0.0)]], dtype=np.float64)
    a_order = int(header.get('A_ORDER', 0))
    b_order = int(header.get('B_ORDER', 0))
    ac = np.matrix(np.zeros((a_order+1, a_order+1), dtype=np.float64))
    bc = np.matrix(np.zeros((b_order+1, b_order+1), dtype=np.float64))
    for m in range(a_order+1):
        for n in range(0, a_order+1-m):
            ac[m, n] = header.get('A_%d_%d' % (m, n), 0.0)
    for m in range(b_order+1):
        for n in range(0, b_order+1-m):
            bc[m, n] = header.get('B_%d_%d' % (m, n), 0.0)
    return cd, ac, bc


def get_pv_keywords(header):
    """Return the CD matrix and PV coefficients from a Header object

    Parameters:
    -----------
    header (fits.Header) : header object from a FITS file

    Returns:
    --------
    cd (numpy.matrix) : the CD matrix from the FITS header
    pv1 (numpy.array) : the PV1-coefficients from the FITS header
    pv2 (numpy.array) : the PV2-coefficients from the FITS header
    """
    cd = np.matrix([[header.get('CD1_1', 0.0), header.get('CD1_2', 0.0)],
                    [header.get('CD2_1', 0.0), header.get('CD2_2', 0.0)]], dtype=np.float64)
    pv1 = np.zeros((40,), dtype=np.float64)
    pv2 = np.zeros((40,), dtype=np.float64)
    for k in range(40):
            pv1[k] = header.get('PV1_%d' % k, 0.0)
            pv2[k] = header.get('PV2_%d' % k, 0.0)
    return cd, pv1, pv2


def real_sipexprs(cd, ac, bc):
    """ Calculate the Sympy expression for SIP distortion

    Parameters:
    -----------
    cd (numpy.matrix) : the CD matrix from the FITS header
    ac (numpy.matrix) : the A-coefficients from the FITS header
    bc (numpy.matrix) : the B-coefficients from the FITS header

    Returns:
    --------
    sipx (Sympy expr) : equation for x-distortion in SIP convention
    sipy (Sympy expr) : equation for y-distortion in SIP convention
    """
    x, y = symbols("x y")
    cdinverse = cd**-1
    uprime, vprime = cdinverse*Matrix([x, y])
    usum = uprime
    vsum = vprime
    aorder = ac.shape[0] - 1
    border = bc.shape[0] - 1
    for m in range(aorder+1):
        for n in range(0, aorder+1-m):
            usum += ac[m, n]*uprime**m*vprime**n
    for m in range(border+1):
        for n in range(0, border+1-m):
            vsum += bc[m, n]*uprime**m*vprime**n
    sipx, sipy = cd*Matrix([usum, vsum])
    sipx = sipx.expand()
    sipy = sipy.expand()
    return sipx, sipy


def real_tpvexprs(cd, pv1, pv2):
    """ Calculate the Sympy expression for TPV distortion

    Parameters:
    -----------
    cd (numpy.matrix) : the CD matrix from the FITS header
    pv1 (numpy.array) : the axis-1 coefficients from the FITS header
    pv2 (numpy.array) : the axis-2 coefficients from the FITS header

    Returns:
    --------
    tpvu (Sympy expr) : equation for u-distortion in TPV convention
    tpvv (Sympy expr) : equation for v-distortion in TPV convention
    """
    u, v = symbols("u v")
    x, y = cd*Matrix([u, v])

    tpv1, tpv2 = compute_tpv(pv1, pv2, x, y)
    cdinverse = cd**-1
    tpvu, tpvv = cdinverse*Matrix([tpv1, tpv2])
    tpvu = tpvu.expand()
    tpvv = tpvv.expand()
    return tpvu, tpvv


def add_pv_keywords(header, sipx, sipy, pvrange, tpvx, tpvy, tpv=True):
    """Calculate the PV keywords and add to the header

    Parameters:
    -----------
    header (pyfits.Header) : header object from a FITS file
    sipx, sipv : SIP coefficients in terms of x, y
    pvrange : list of allowd PV coefficient positions
    tpvx, tpvy : Sympy expressions for TPV distortion
    tpv (boolean, default True) : Change CTYPE1/2 to TPV convention

    Returns:
    --------
    None (header is modified in place)
    """
    for p in pvrange:
        val = float(calcpv(pvrange, 1, p, sipx, sipy, tpvx, tpvy).evalf())
        if val != 0.0:
            header['PV1_%d' % p] = val
    for p in pvrange:
        val = float(calcpv(pvrange, 2, p, sipx, sipy, tpvx, tpvy).evalf())
        if val != 0.0:
            header['PV2_%d' % p] = val
    if tpv:
        header['CTYPE1'] = 'RA---TPV'
        header['CTYPE2'] = 'DEC--TPV'
    else:
        header['CTYPE1'] = header['CTYPE1'][:8]
        header['CTYPE2'] = header['CTYPE2'][:8]
    return


def add_sip_keywords(header, tpvu, tpvv, sipu, sipv, add_reverse=True,
                     aporder=None, bporder=None):
    """Calculate the PV keywords and add to the header

    Parameters:
    -----------
    header (pyfits.Header) : header object from a FITS file
    tpvu, tpvv : TPV coefficients in terms of u, v
    sipu, sipv : Sympy expressions for SIP distortion
    add_reverse (bool) : Add reverse SIP coefficients (default True)
    aporder (int or None) : order of reverse poly, axis 1, or a_order if None
    bporder (int or None) : order of reverse poly, axis 2, or b_order if None

    Returns:
    --------
    None (header is modified in place)
    """
    a_order = 0
    b_order = 0
    u, v = symbols('u v')
    for m in range(8):
        for n in range(8):
            val = float(calcsip(1, m, n, sipu, sipv, tpvu, tpvv).evalf())
            if val != 0.0:
                header['A_%d_%d' % (m, n)] = val
                a_order = max(a_order, max(m, n))
            val = float(calcsip(2, m, n, sipu, sipv, tpvu, tpvv).evalf())
            if val != 0.0:
                header['B_%d_%d' % (m, n)] = val
                b_order = max(a_order, max(m, n))
    header['CTYPE1'] = 'RA---TAN-SIP'
    header['CTYPE2'] = 'DEC--TAN-SIP'
    header['A_ORDER'] = int(a_order)
    header['B_ORDER'] = int(b_order)
    if aporder is None:
        aporder = a_order
    if bporder is None:
        bporder = b_order
    if add_reverse:
        add_reverse_coefficients(header, aporder, bporder)
    return


def removekwd(header, kwd):
    """ Helper function for removing keywords from FITS headers after first
        testing that they exist in the header

    Parameters:
    -----------
    header (pyfits.Header) : header object from a FITS file
    kwd (string) : name of the keyword to be removed

    Returns:
    --------
    None (header is modified in place)
    """
    if kwd in header.keys():
        header.remove(kwd)
    return


def remove_sip_keywords(header):
    """ Remove keywords from the SIP convention from the header.

    Parameters:
    -----------
    header (pyfits.Header) : header object from a FITS file

    Returns:
    --------
    None (header is modified in place)
    """
    aorder = int(header.get('A_ORDER', 0))
    border = int(header.get('B_ORDER', 0))
    aporder = int(header.get('AP_ORDER', 0))
    bporder = int(header.get('BP_ORDER', 0))
    for m in range(aorder+1):
        for n in range(0, aorder+1-m):
            removekwd(header, 'A_%d_%d' % (m, n))
    for m in range(border+1):
        for n in range(0, border+1-m):
            removekwd(header, 'B_%d_%d' % (m, n))
    for m in range(aporder+1):
        for n in range(0, aporder+1-m):
            removekwd(header, 'AP_%d_%d' % (m, n))
    for m in range(bporder+1):
        for n in range(0, bporder+1-m):
            removekwd(header, 'BP_%d_%d' % (m, n))
    removekwd(header, 'A_ORDER')
    removekwd(header, 'B_ORDER')
    removekwd(header, 'AP_ORDER')
    removekwd(header, 'BP_ORDER')
    removekwd(header, 'A_DMAX')
    removekwd(header, 'B_DMAX')
    return


def remove_pv_keywords(header):
    """ Remove keywords from the PV convention from the header.

    Parameters:
    -----------
    header (pyfits.Header) : header object from a FITS file

    Returns:
    --------
    None (header is modified in place)
    """
    for i in range(40):
        removekwd(header, 'PV1_%d' % i)
        removekwd(header, 'PV2_%d' % i)
    return


def add_reverse_coefficients(header, aporder, bporder):
    """ Add reverse AP, BP SIP coefficients to header

    Parameters:
    -----------
    header (fits.header) : header with forward SIP coefficients
    aporder (int) : order of axis 1 polynomial
    bporder (int) : order of axis 2 polynomial

    Returns:
    --------
    None (header is modified in-place)
    """
    crpix1 = header['CRPIX1']
    crpix2 = header['CRPIX2']
    naxis1 = header['NAXIS1']
    naxis2 = header['NAXIS2']
    r = np.arange(0, naxis1, 4, dtype=np.float64) - crpix1
    q = np.arange(0, naxis2, 4, dtype=np.float64) - crpix2
    u, v = np.meshgrid(r, q)
    cd, ac, bc = get_sip_keywords(header)
    adist = np.array(ac)
    bdist = np.array(bc)
    apdist, bpdist = fitreverse(aporder, bporder, adist, bdist, u, v)
    for i in range(aporder+1):
        for j in range(0, aporder - i + 1):
                header['AP_%d_%d' % (i, j)] = apdist[i, j]
    for i in range(bporder+1):
        for j in range(0, bporder - i + 1):
                header['BP_%d_%d' % (i, j)] = bpdist[i, j]
    header['AP_ORDER'] = aporder
    header['BP_ORDER'] = bporder
    return
