#!/usr/bin/env python3

import os
import numpy as np
import matplotlib.pyplot as plt
from astropy.io import fits
from astropy.table import Table
import argparse
from astropy.wcs import WCS
from astropy.stats import sigma_clipped_stats, mad_std
import glob
from scipy.ndimage import gaussian_filter
import shutil  # Added for directory removal

def fwhm_to_sigma(fwhm):
    """
    Convert FWHM to sigma for a Gaussian distribution.
    FWHM = 2.355 * sigma
    """
    return fwhm / 2.355

def flux_to_amplitude(flux, sigma):
    """
    Convert desired total flux to peak amplitude for a 2D Gaussian.
    flux = 2 pi * sigma^2 * amplitude
    """
    return flux / (2 * np.pi * sigma * sigma)

def make_gaussian_source(shape, x_mean, y_mean, flux, fwhm=2.355, dtype=np.float64):
    """
    Create a 2D Gaussian source with specified flux and FWHM.
    
    Parameters
    ----------
    shape : tuple
        Shape of the output image (ny, nx)
    x_mean, y_mean : float
        Mean/center position of the Gaussian
    flux : float
        Total integrated flux of the Gaussian
    fwhm : float
        Full Width at Half Maximum of the Gaussian
    dtype : numpy.dtype
        Data type of the output array
    
    Returns
    -------
    numpy.ndarray
        2D array containing the Gaussian source
    """
    y, x = np.indices(shape)
    
    # Convert FWHM to sigma
    sigma = fwhm_to_sigma(fwhm)
    
    # Calculate amplitude from desired flux
    amplitude = flux_to_amplitude(flux, sigma)
    
    # Create normalized Gaussian (as float64 for precision)
    gaussian = np.exp(
        -(((x - x_mean) / sigma) ** 2 + 
          ((y - y_mean) / sigma) ** 2) / 2
    )
    
    # Scale by amplitude and convert to desired dtype
    return (amplitude * gaussian).astype(dtype)
            
def find_fits_files(directory):
    """
    Find FITS files in the given directory with common extensions.
    """
    extensions = ['*.fits', '*.fts', '*.fit']
    fits_files = []
    for ext in extensions:
        fits_files.extend(glob.glob(os.path.join(directory, ext)))
    
    if len(fits_files) < 2:
        raise ValueError(f"Error: Found fewer than 2 FITS files in {directory}. At least 2 FITS files are required.")
    
    # Sort and take first two files
    fits_files.sort()
    return fits_files[0], fits_files[1]
    
def determine_border_size(image_data):
    """
    Determines the size of the overscan regions around the image using median absolute deviation.
    """
    median = np.median(image_data)
    mad = mad_std(image_data)
    threshold = median - 5 * mad
    
    rows, cols = image_data.shape
    borders = {'top': 0, 'bottom': 0, 'left': 0, 'right': 0}
    
    # Determine top border
    for i in range(rows):
        if np.all(image_data[i, :] < threshold):
            borders['top'] += 1
        else:
            break

    # Determine bottom border
    for i in range(rows-1, -1, -1):
        if np.all(image_data[i, :] < threshold):
            borders['bottom'] += 1
        else:
            break

    # Determine left border
    for j in range(cols):
        if np.all(image_data[:, j] < threshold):
            borders['left'] += 1
        else:
            break

    # Determine right border
    for j in range(cols-1, -1, -1):
        if np.all(image_data[:, j] < threshold):
            borders['right'] += 1
        else:
            break

    # If no overscan regions found, use 100 pixels from edges
    if all(v == 0 for v in borders.values()):
        print("No overscan regions detected. Using 100 pixels from edges.")
        borders = {'top': 100, 'bottom': 100, 'left': 100, 'right': 100}
    
    print(f"Detected border sizes (pixels): {borders}")
    return borders

def generate_random_positions(borders, image_shape, num_stars, random_seed=None):
    """
    Generates random (x, y) positions within the valid region of the image,
    keeping minimum distance from borders and overscan regions.
    """
    if random_seed is not None:
        np.random.seed(random_seed)

    rows, cols = image_shape
    
    # Use maximum of overscan region or 100 pixels for safety margin
    margin = {
        'left': max(borders['left'] + 10, 100),
        'right': max(borders['right'] + 10, 100),
        'top': max(borders['top'] + 10, 100),
        'bottom': max(borders['bottom'] + 10, 100)
    }

    # Define valid ranges
    x_min = margin['left']
    x_max = cols - margin['right']
    y_min = margin['top']
    y_max = rows - margin['bottom']

    # Check if the valid area is sufficient
    if x_min >= x_max or y_min >= y_max:
        raise ValueError("Insufficient valid area to place artificial stars after excluding margins.")

    # Generate random positions
    x_positions = np.random.randint(x_min, x_max, size=num_stars)
    y_positions = np.random.randint(y_min, y_max, size=num_stars)

    return x_positions.tolist(), y_positions.tolist()

def insert_artificial_star(source_file_path, modified_file_path, x_list, y_list, flux_list, fwhm):
    """
    Inserts artificial stars into a FITS image and saves the modified data to a new FITS file.
    """
    with fits.open(source_file_path) as hdul:
        header = hdul[0].header.copy()
        star_field = hdul[0].data.copy()
        
        # Get original data type
        original_dtype = star_field.dtype
        
        # Convert to float64 for calculations if integer
        if np.issubdtype(original_dtype, np.integer):
            star_field = star_field.astype(np.float64)

    image_shape = star_field.shape
    artificial_star_image = np.zeros_like(star_field, dtype=np.float64)

    for x, y, flux in zip(x_list, y_list, flux_list):
        # Create Gaussian source (in float64 for precision)
        star_image = make_gaussian_source(
            image_shape,
            x_mean=x,
            y_mean=y,
            flux=flux,
            fwhm=fwhm,
            dtype=np.float64
        )
        artificial_star_image += star_image

    # Add artificial stars to the image
    modified_star_field = star_field + artificial_star_image

    # Convert back to original dtype if necessary
    if np.issubdtype(original_dtype, np.integer):
        # Clip values to valid range for the original dtype
        info = np.iinfo(original_dtype)
        modified_star_field = np.clip(modified_star_field, info.min, info.max)
        modified_star_field = np.round(modified_star_field).astype(original_dtype)
    
    # Create HDU with the modified data
    hdu = fits.PrimaryHDU(data=modified_star_field, header=header)

    # Ensure the output directory exists
    output_dir = os.path.dirname(modified_file_path)
    if output_dir and not os.path.exists(output_dir):
        os.makedirs(output_dir)

    # Write the file
    hdu.writeto(modified_file_path, overwrite=True)
    print(f"Modified FITS file saved to {modified_file_path}")
        
def convert_coordinates(x_pixels, y_pixels, wcs_from, wcs_to):
    """
    Convert pixel coordinates between two images using WCS information.
    """
    # Convert pixels to sky coordinates using first WCS
    sky_coords = wcs_from.pixel_to_world(x_pixels, y_pixels)
    
    # Convert sky coordinates to pixels using second WCS
    x_new, y_new = wcs_to.world_to_pixel(sky_coords)
    
    return x_new.tolist(), y_new.tolist()

def main():
    """
    Main function to insert artificial stars into FITS images using WCS alignment.
    """
    parser = argparse.ArgumentParser(description="Insert artificial stars into FITS images.")
    parser.add_argument('input_dir', type=str, help="Directory containing input FITS files.")
    parser.add_argument('flux', type=float, help="Total integrated flux of the artificial stars")
    parser.add_argument('num_stars', type=int, help="Number of artificial stars to insert.")
    parser.add_argument('--fwhm', type=float, default=2.355, 
                       help="Full Width at Half Maximum of the artificial stars in pixels (default: 2.355)")

    args = parser.parse_args()

    # Normalize input directory path by removing trailing slashes
    input_dir = args.input_dir.rstrip(os.sep)
    
    # Find input FITS files
    source_file_path1, source_file_path2 = find_fits_files(input_dir)
    
    # Create output directory name
    output_dir = f"{input_dir}__artificialstars"
    
    # Remove existing output directory if it exists
    if os.path.exists(output_dir):
        print(f"Removing existing output directory: {output_dir}")
        shutil.rmtree(output_dir)
    
    # Create fresh output directory
    os.makedirs(output_dir)
    
    # Create output paths
    modified_file_path1 = os.path.join(output_dir, os.path.basename(source_file_path1))
    modified_file_path2 = os.path.join(output_dir, os.path.basename(source_file_path2))

    # Read FITS files and check WCS information
    with fits.open(source_file_path1) as hdul1, fits.open(source_file_path2) as hdul2:
        # Check WCS information
        try:
            wcs1 = WCS(hdul1[0].header)
            wcs2 = WCS(hdul2[0].header)
            if not (wcs1.has_celestial and wcs2.has_celestial):
                raise ValueError("WCS celestial coordinates not found")
        except Exception as e:
            raise ValueError(f"Error processing WCS information: {str(e)}")
        
        image_data1 = hdul1[0].data.copy()
        image_data2 = hdul2[0].data.copy()

    # Determine border sizes
    borders1 = determine_border_size(image_data1)

    # Generate random positions for the first image
    x_rand1, y_rand1 = generate_random_positions(
        borders1,
        image_data1.shape,
        args.num_stars
    )

    # Convert coordinates from first image to second image using WCS
    x_rand2, y_rand2 = convert_coordinates(x_rand1, y_rand1, wcs1, wcs2)

    # Insert artificial stars
    insert_artificial_star(source_file_path1, modified_file_path1, x_rand1, y_rand1, 
                         [args.flux]*args.num_stars, args.fwhm)
    insert_artificial_star(source_file_path2, modified_file_path2, x_rand2, y_rand2, 
                         [args.flux]*args.num_stars, args.fwhm)

    # Save coordinates from first image to text file
    coord_file = os.path.join(output_dir, 'coordinates.txt')
    with open(coord_file, 'w') as f:
        for x, y in zip(x_rand1, y_rand1):
            f.write(f"{x+1:10.3f} {y+1:10.3f}\n")

    print(f"Coordinates of inserted stars (from first image) saved to '{coord_file}'")

if __name__ == "__main__":
    main()
