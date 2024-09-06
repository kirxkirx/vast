#!/usr/bin/env python3

import argparse
from astropy.time import Time

# Setup command line argument parser
parser = argparse.ArgumentParser(description="Convert Julian Date to calendar date.")
parser.add_argument('jd', type=float, help='Julian Date to be converted')

# Parse the arguments
args = parser.parse_args()

# Julian Date to calendar date
t = Time(args.jd, format='jd', scale='utc')
print(t.iso)  # ISO 8601 format (with sub-second precision)
