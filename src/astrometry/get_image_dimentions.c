#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#include "../fitsio.h"

int main( int argc, char **argv ) {
 int status;
 int naxis;
 fitsfile *fptr;
 long naxes[2];
 char fitsfilename[1024];

 status = 0;

 if ( argc != 2 ) {
  fprintf( stderr, "Usage: %s image.fit\n", argv[0] );
  return 1;
 }

 strncpy( fitsfilename, argv[1], 1024 );
 fitsfilename[1024 - 1] = '\0'; /* ensure null termination */

 /* Extract data from fits header */
 fits_open_image( &fptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  return status;
 }

 /* Get number of dimensions */
 fits_get_img_dim( fptr, &naxis, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_close_file( fptr, &status );
  fprintf( stderr, "ERROR: can't get number of image dimensions!\n" );
  return status;
 }

 if ( naxis != 2 ) {
  fits_close_file( fptr, &status );
  fprintf( stderr, "ERROR: expected 2D image, got %d dimensions!\n", naxis );
  return 1;
 }

 /* Get image dimensions - this works correctly for both compressed and uncompressed images */
 fits_get_img_size( fptr, 2, naxes, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_close_file( fptr, &status );
  fprintf( stderr, "ERROR: can't get image dimensions!\n" );
  return status;
 }

 fits_close_file( fptr, &status );

 fprintf( stdout, " --width %ld --height %ld ", naxes[0], naxes[1] );

 return 0;
}
