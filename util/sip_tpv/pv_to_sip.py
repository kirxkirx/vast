#!/usr/bin/env python

from __future__ import print_function, absolute_import, division
from copy import copy
import astropy.io.fits as fits
from pvsiputils import (get_pv_keywords,
                         sym_sipexprs,
                         real_tpvexprs,
                         add_sip_keywords,
                         remove_pv_keywords)

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

version = 1.1


def pv_to_sip(header, preserve=False, add_reverse=True,
              aporder=None, bporder=None):
    """ Function which wraps the sip_to_pv conversion

    Parameters:
    -----------
    header (fits.Header) : header of file with TPV convention keywords
    preserve (boolean) : preserve the PV keywords in the header (default False)
    add_reverse (boolean) : compute and add reverse SIP keywords (default True)
    aporder (int) : order for reverse polynomial for axis 1 (default 4)
    bporder (int) : order for reverse polynomials for axis 2 (default 4)

    Returns:
    --------
    None (header is modified in-place)
    """
    cd, pv1, pv2 = get_pv_keywords(header)
    sipu, sipv = sym_sipexprs()
    tpvu, tpvv = real_tpvexprs(cd, pv1, pv2)
    add_sip_keywords(header, tpvu, tpvv, sipu, sipv, add_reverse,
                     aporder, bporder)
    if not preserve:
        remove_pv_keywords(header)


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description="""
        Convert FITS files with SIP distortion to TPV representation
        """)
    parser.add_argument('infile', help='path to input file with SIP distortion')
    parser.add_argument('outfile', help='path to output file')
    parser.add_argument('--extension', help='extension of file with PV header (default 0)',
                        default=0)
    parser.add_argument('--overwrite',
                        help='Overwrite output file if it exists',
                        action='store_true')
    parser.add_argument('--preserve_tpv',
                        help='Retain PV keywords in header',
                        action='store_true')
    parser.add_argument('--add_reverse',
                        help='Write the reverse SIP coefficients',
                        action='store_true')
    parser.add_argument('--aporder',
                        help='Order for reverse polynomial, axis 1 (defaults to A_ORDER)',
                        default=None)
    parser.add_argument('--bporder',
                        help='Order for reverse polynomial, axis 1 (defaults to B_ORDER)',
                        default=None)

    args = parser.parse_args()
    infile = args.infile
    outfile = args.outfile
    extension = args.extension
    overwrite = args.overwrite
    preserve_tpv = args.preserve_tpv
    add_reverse = args.add_reverse
    aporder = args.aporder
    bporder = args.bporder
    if aporder is not None:
        aporder = int(aporder)
    if bporder is not None:
        bporder = int(bporder)

    hdu = fits.open(infile)
    header = copy(hdu[extension].header)
    pv_to_sip(header, preserve=preserve_tpv, add_reverse=add_reverse,
              aporder=aporder, bporder=bporder)
    hdu[extension].header = header
    hdu.writeto(outfile, overwrite=overwrite)
