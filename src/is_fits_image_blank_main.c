/*
 * Command line tool to check if a FITS image is blank.
 *
 * Usage: is_fits_image_blank image.fits
 *
 * Exit codes:
 *   0 - image is NOT blank (normal image with variation)
 *   1 - image IS blank (all pixels have the same value)
 *   2 - error (cannot read the image or invalid arguments)
 */

#include <stdio.h>
#include <string.h>

#include "vast_limits.h"
#include "is_fits_image_blank.h"
#include "fitsfile_read_check.h"

int main( int argc, char **argv ) {
 char fitsfilename[FILENAME_LENGTH];
 int result;

 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s image.fits\n", argv[0] );
  fprintf( stderr, "Exit codes: 0 = not blank, 1 = blank, 2 = error\n" );
  return 2;
 }

 // Safely copy the filename
 safely_encode_user_input_string( fitsfilename, argv[1], FILENAME_LENGTH );
 fitsfilename[FILENAME_LENGTH - 1] = '\0';

 // Check if the file is a valid FITS image
 if ( 0 != fitsfile_read_check( fitsfilename ) ) {
  fprintf( stderr, "ERROR: %s is not a valid FITS image\n", fitsfilename );
  return 2;
 }

 // Check if the image is blank
 result = is_fits_image_blank( fitsfilename );

 if ( result == -1 ) {
  // Error reading the image
  fprintf( stderr, "ERROR: cannot check if %s is blank\n", fitsfilename );
  return 2;
 }

 if ( result == 1 ) {
  // Image is blank
  fprintf( stdout, "BLANK\n" );
  return 1;
 }

 // Image is not blank
 fprintf( stdout, "OK\n" );
 return 0;
}
