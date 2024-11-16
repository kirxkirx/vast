#!/usr/bin/env python

from __future__ import print_function, absolute_import, division
from copy import copy
import astropy.io.fits as fits
from pvsiputils import (sym_tpvexprs,
                         get_sip_keywords,
                         real_sipexprs,
                         add_pv_keywords,
                         remove_sip_keywords)

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


def sip_to_pv(header, tpv_format=True, preserve=False):
    """ Function which wraps the sip_to_pv conversion

    Parameters:
    -----------
    header (fits.Header) : header of file with SIP convention keywords
    tpv_format (boolean) : modify CTYPE1 and CTYPE2 to TPV convention RA---TPV, DEC--TPV
    preserve (boolean) : preserve the SIP keywords in the header (default is to delete)

    Returns:
    --------
    None (header is modified in-place)
    """
    pvrange, tpvx, tpvy = sym_tpvexprs()
    cd, ac, bc = get_sip_keywords(header)
    sipx, sipy = real_sipexprs(cd, ac, bc)
    add_pv_keywords(header, sipx, sipy, pvrange, tpvx, tpvy,
                    int(header['B_ORDER']))
    if not preserve:
        remove_sip_keywords(header)


if __name__ == '__main__':
    import argparse

    parser = argparse.ArgumentParser(description="""
        Convert FITS files with SIP distortion to TPV representation
        """)
    parser.add_argument('infile', help='path to input file with SIP distortion')
    parser.add_argument('outfile', help='path to output file')
    parser.add_argument('--extension', help='extension of file with SIP header (default 0)',
                        default=0)
    parser.add_argument('--overwrite',
                        help='Overwrite output file if it exists',
                        action='store_true')
    parser.add_argument('--write_tan',
                        help='Write -TAN in CTYPE keywords, not -TPV',
                        action='store_true')
    parser.add_argument('--write_tan_sip',
                        help='Write -TAN-SIP in CTYPE keywords, not -TPV',
                        action='store_true')
    parser.add_argument('--preserve_sip',
                        help='Retain SIP keywords in header',
                        action='store_true')

    args = parser.parse_args()
    infile = args.infile
    outfile = args.outfile
    extension = args.extension
    overwrite = args.overwrite
    write_tan = args.write_tan
    write_tan_sip = args.write_tan_sip
    preserve_sip = args.preserve_sip

    hdu = fits.open(infile)
    header = copy(hdu[extension].header)
    sip_to_pv(header, tpv_format=not write_tan, preserve=preserve_sip)
    if write_tan_sip:
        header['CTYPE1'] = 'RA---TAN-SIP'
        header['CTYPE2'] = 'DEC--TAN-SIP'
    hdu[extension].header = header
    hdu.writeto(outfile, overwrite=overwrite)
