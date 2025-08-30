#!/usr/bin/env python3
"""
Remove a bright star from a FITS image by replacing it with background noise.

This script replaces a 21x21 pixel region centered on a star with Gaussian noise
that matches the statistical properties of the local background.
"""

import numpy as np
from astropy.io import fits
import argparse
import sys
from scipy import stats

def remove_star(fits_file, x_center, y_center, output_file=None):
    """
    Remove a star from a FITS image by replacing it with background noise.
    
    Parameters:
    -----------
    fits_file : str
        Path to input FITS file
    x_center : float
        X coordinate of star center (FITS convention: 1-indexed)
    y_center : float  
        Y coordinate of star center (FITS convention: 1-indexed)
    output_file : str, optional
        Output filename. If None, appends '_star_removed' to input filename
    """
    
    # Read FITS file
    try:
        with fits.open(fits_file) as hdul:
            original_data = hdul[0].data
            original_dtype = original_data.dtype
            data = original_data.astype(float)
            header = hdul[0].header
    except Exception as e:
        print(f"Error reading FITS file: {e}")
        return False
    
    # Convert from FITS convention (1-indexed) to Python convention (0-indexed)
    # Round to nearest pixel
    x_center_py = int(round(x_center - 1))
    y_center_py = int(round(y_center - 1))
    
    # Define the 21x21 removal box
    box_size = 21
    half_box = box_size // 2  # = 10
    
    # Get image dimensions
    if len(data.shape) == 2:
        y_max, x_max = data.shape
    else:
        print("Error: Image must be 2D")
        return False
    
    # Check if star position allows for 21x21 box
    if (x_center_py - half_box < 0 or x_center_py + half_box >= x_max or 
        y_center_py - half_box < 0 or y_center_py + half_box >= y_max):
        print(f"Error: Star position ({x_center}, {y_center}) too close to image edge")
        print(f"Need at least {half_box} pixels margin from edges")
        print(f"Image dimensions: {x_max} x {y_max}")
        return False
    
    # Define background estimation region as an annulus around the star
    # Inner radius should be larger than the removal box to avoid the star
    inner_radius = 15  # pixels
    outer_radius = 50  # pixels
    
    # Create coordinate grids relative to star center
    y_coords, x_coords = np.ogrid[:y_max, :x_max]
    distances = np.sqrt((x_coords - x_center_py)**2 + (y_coords - y_center_py)**2)
    
    # Create background mask (annulus region)
    background_mask = (distances >= inner_radius) & (distances <= outer_radius)
    background_pixels = data[background_mask]
    
    if len(background_pixels) < 100:
        print("Warning: Very few background pixels available for statistics")
        print(f"Consider using a larger outer_radius (current: {outer_radius})")
    
    # Use sigma clipping to get robust statistics resistant to other stars
    # This removes outliers beyond 3-sigma iteratively
    try:
        clipped_data, lower, upper = stats.sigmaclip(background_pixels, low=3, high=3)
        
        if len(clipped_data) < 50:
            print("Warning: Very few pixels remain after sigma clipping")
            # Fall back to simple percentile-based robust estimates
            bg_median = np.median(background_pixels)
            # Use MAD (Median Absolute Deviation) scaled to approximate std
            mad = np.median(np.abs(background_pixels - bg_median))
            bg_std = mad * 1.4826  # Scale factor to approximate Gaussian std
        else:
            # Use sigma-clipped statistics
            bg_median = np.median(clipped_data)
            bg_std = np.std(clipped_data)
            
    except Exception as e:
        print(f"Error computing background statistics: {e}")
        return False
    
    # Generate Gaussian noise with same statistics as background
    np.random.seed(42)  # For reproducible results
    noise = np.random.normal(bg_median, bg_std, (box_size, box_size))
    
    # Replace the star region with noise
    y_start = y_center_py - half_box
    y_end = y_center_py + half_box + 1
    x_start = x_center_py - half_box  
    x_end = x_center_py + half_box + 1
    
    original_median = np.median(data[y_start:y_end, x_start:x_end])
    data[y_start:y_end, x_start:x_end] = noise
    
    # Convert back to original data type
    if np.issubdtype(original_dtype, np.integer):
        # For integer types, clip to valid range and round
        if original_dtype == np.uint16:
            data = np.clip(data, 0, 65535)
        elif original_dtype == np.int16:
            data = np.clip(data, -32768, 32767)
        elif original_dtype == np.uint8:
            data = np.clip(data, 0, 255)
        elif original_dtype == np.int8:
            data = np.clip(data, -128, 127)
        elif original_dtype == np.uint32:
            data = np.clip(data, 0, 4294967295)
        elif original_dtype == np.int32:
            data = np.clip(data, -2147483648, 2147483647)
        
        # Round to nearest integer
        data = np.round(data)
    
    # Convert to original data type
    data = data.astype(original_dtype)
    
    # Prepare output filename
    if output_file is None:
        if fits_file.endswith('.fits'):
            output_file = fits_file[:-5] + '_star_removed.fits'
        else:
            output_file = fits_file + '_star_removed.fits'
    
    # Save the modified image
    try:
        fits.writeto(output_file, data, header, overwrite=True)
    except Exception as e:
        print(f"Error writing output file: {e}")
        return False
    
    # Print summary
    print(f"Successfully removed star at position ({x_center}, {y_center})")
    if x_center != x_center_py + 1 or y_center != y_center_py + 1:
        print(f"  Rounded to pixel ({x_center_py + 1}, {y_center_py + 1}) for processing")
    print(f"Original data type: {original_dtype}")
    print(f"Background median: {bg_median:.3f}")
    print(f"Background std dev: {bg_std:.3f}")
    print(f"Original star region median: {original_median:.3f}")
    print(f"Used {len(background_pixels)} background pixels")
    print(f"After sigma clipping: {len(clipped_data) if 'clipped_data' in locals() else 'N/A'} pixels")
    print(f"Output saved to: {output_file}")
    
    return True

def main():
    """Main function to handle command line arguments."""
    parser = argparse.ArgumentParser(
        description="Remove a bright star from a FITS image",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python remove_star.py image.fits 513 257
  python remove_star.py image.fits 513.7 257.2 -o cleaned_image.fits
  
Note: Coordinates use FITS convention (1-indexed)
      X is the column index, Y is the row index
      Fractional pixel coordinates are accepted and rounded to nearest pixel
        """)
    
    parser.add_argument("fits_file", help="Input FITS file path")
    parser.add_argument("x_center", type=float, help="X coordinate of star center (FITS convention: 1-indexed, accepts fractional pixels)")
    parser.add_argument("y_center", type=float, help="Y coordinate of star center (FITS convention: 1-indexed, accepts fractional pixels)")
    parser.add_argument("-o", "--output", help="Output FITS file name")
    
    args = parser.parse_args()
    
    # Validate inputs
    if args.x_center < 1.0 or args.y_center < 1.0:
        print("Error: Coordinates must be >= 1.0 (FITS convention)")
        sys.exit(1)
    
    # Remove the star
    success = remove_star(args.fits_file, args.x_center, args.y_center, args.output)
    
    if not success:
        sys.exit(1)

if __name__ == "__main__":
    main()
