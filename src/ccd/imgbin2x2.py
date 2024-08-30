#!/usr/bin/env python3

import sys
from astropy.io import fits
import numpy as np

def bin_2x2(data):
    # Check if the dimensions of the image are even
    if data.shape[0] % 2 != 0 or data.shape[1] % 2 != 0:
        raise ValueError("Image dimensions must be even to bin 2x2.")

    # Reshape and then take the mean along the new axes to bin the data
    binned_data = data.reshape(data.shape[0]//2, 2, data.shape[1]//2, 2).mean(axis=3).mean(axis=1)
    # Alternatively, you may want to...
    # Reshape and take the sum along the new axes to bin the data
    #binned_data = data.reshape(data.shape[0]//2, 2, data.shape[1]//2, 2).sum(axis=3).sum(axis=1)

    return binned_data

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print("Usage: python script_name.py <input_fits_file>")
        sys.exit(1)

    fits_file = sys.argv[1]  # Take the FITS file name from the command line argument

    # Load the FITS file
    with fits.open(fits_file) as hdul:
        data = hdul[0].data  # Assuming the image data is in the first HDU
        dtype = data.dtype  # Store the original data type of the image

    # Bin the data
    binned_data = bin_2x2(data)

    # Cast the binned data back to the original data type
    binned_data = binned_data.astype(dtype)

    # Output file name
    output_file = 'binned_image.fits'

    # Save the binned image to a new FITS file
    hdu = fits.PrimaryHDU(binned_data)
    hdul = fits.HDUList([hdu])
    hdul.writeto(output_file, overwrite=True)

    # Print confirmation message
    print(f"Binned image is written to {output_file}")
