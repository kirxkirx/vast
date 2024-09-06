#!/usr/bin/env python3

import argparse
from astropy.time import Time

# Setup command line argument parser
parser = argparse.ArgumentParser(description="Convert calendar date to Julian Date.")
parser.add_argument('date_string', type=str, help='Date string in the format "YYYY-MM-DDTHH:MM:SS.sss"')

# Parse the arguments
args = parser.parse_args()

# Calendar date to Julian Date
t = Time(args.date_string, format='isot', scale='utc')
print(f'{t.jd:.8f}')  # Julian Date with 8 decimal places
