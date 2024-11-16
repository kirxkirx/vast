from __future__ import print_function, division, absolute_import
# This code determines reverse coefficients from the forward ones
import numpy as np


# function to evaluate polynomials
def evalpoly(u, v, adist, bdist):
    """ Given coordinates arrays u, v,
        polynomial orders aorder and border,
        and distortion polynomial matrices,
        return a tuple of (uprime,vprime) containing the corrected positions."""

    # Calculate forward orders from size of distortion matrices
    aorder = np.shape(adist)[0] - 1
    border = np.shape(bdist)[0] - 1
    ushape = u.shape
    vshape = v.shape
    uu = u.flatten()
    vv = v.flatten()
    uprime = uu.astype('float64')
    vprime = vv.astype('float64')

    udict = {}
    vdict = {}
    udict[0] = 1.0
    vdict[0] = 1.0
    for i in range(1, max(aorder, border) + 1):
        udict[i] = uu * udict[i - 1]
        vdict[i] = vv * vdict[i - 1]
    for i in range(aorder + 1):
        for j in range(0, aorder + 1 - i):
            uprime += adist[i][j] * udict[i] * vdict[j]
    for i in range(border + 1):
        for j in range(0, border + 1 - i):
            vprime += bdist[i][j] * udict[i] * vdict[j]
    uprime = uprime.reshape(ushape)
    vprime = vprime.reshape(vshape)
    return uprime, vprime


def fitreverse(aporder, bporder, adist, bdist, u, v):
    """ Given the desired reverse polynomials orders,
        the forward coefficients, and coordinate arrays
        u and v for doing the calculations, this function
        computes reverse coefficients and returns the results
        in matrices apdist and bpdist """

    # Create reverse coefficient matrices
    apdist = np.zeros((aporder + 1, aporder + 1), 'float64')
    bpdist = np.zeros((bporder + 1, bporder + 1), 'float64')

    (uprime, vprime) = evalpoly(u, v, adist, bdist)
    updict = {}
    vpdict = {}
    uprime = uprime.flatten()
    vprime = vprime.flatten()
    updict[0] = 1.0 + 0.0 * uprime
    vpdict[0] = 1.0 + 0.0 * vprime
    for i in range(1, max(aporder, bporder) + 1):
        updict[i] = updict[i - 1] * uprime
        vpdict[i] = vpdict[i - 1] * vprime
    udiff = u.flatten() - uprime
    vdiff = v.flatten() - vprime

    mylist1 = []
    mylist2 = []
    for i in range(aporder + 1):
        for j in range(0, aporder - i + 1):
            mylist1.append(updict[i] * vpdict[j])
    for i in range(bporder + 1):
        for j in range(0, bporder - i + 1):
            mylist2.append(updict[i] * vpdict[j])

    a = np.array(mylist1).T
    b = udiff

    apcoeffs, r, rank, s = np.linalg.lstsq(a, b)

    a = np.array(mylist2).T
    b = vdiff

    bpcoeffs, r, rank, s = np.linalg.lstsq(a, b)

    # Load reverse distortion matrices
    extractcoeffs(apcoeffs, aporder, apdist)
    extractcoeffs(bpcoeffs, bporder, bpdist)

    return apdist, bpdist


def extractcoeffs(coeffs, order, dist):
    """ Given a compact vector of coefficients and the
        polynomial order, extract them into matrix dist """
    index = 0
    for i in range(order + 1):
        for j in range(0, order - i + 1):
            dist[i][j] = coeffs[index]
            index += 1
