#include <stdio.h>
#include <stdlib.h>
#include "fitsio.h"

int main( int argc, char *argv[] ) {
 fitsfile *fptr;
 int status, naxis;
 long naxes[2], totpix, fpixel[2];
 unsigned short *image;
 long i, x, y;
 char *filename;
 int threshold;
 long x_ll, x_ur;

 status= 0;
 threshold= 62000;

 if ( argc != 2 ) {
  fprintf( stderr, "Usage: %s <fits_file>\n", argv[0] );
  fprintf( stderr, "Finds pixels > %d and creates bad region rectangles\n", threshold );
  fprintf( stderr, "for masking readout trails in shutterless observations.\n" );
  return 1;
 }

 filename= argv[1];

 /* Open the FITS file */
 if ( fits_open_file( &fptr, filename, READONLY, &status ) ) {
  fits_report_error( stderr, status );
  return 1;
 }

 /* Get image dimensions */
 if ( fits_get_img_dim( fptr, &naxis, &status ) ) {
  fits_report_error( stderr, status );
  fits_close_file( fptr, &status );
  return 1;
 }

 if ( naxis != 2 ) {
  fprintf( stderr, "Error: Only 2D images are supported\n" );
  fits_close_file( fptr, &status );
  return 1;
 }

 if ( fits_get_img_size( fptr, 2, naxes, &status ) ) {
  fits_report_error( stderr, status );
  fits_close_file( fptr, &status );
  return 1;
 }

 totpix= naxes[0] * naxes[1];

 /* Allocate memory for image */
 image= (unsigned short *)malloc( totpix * sizeof( unsigned short ) );
 if ( image == NULL ) {
  fprintf( stderr, "Error: Cannot allocate memory for image (%ld pixels)\n", totpix );
  fits_close_file( fptr, &status );
  return 1;
 }

 /* Read the image */
 fpixel[0]= 1;
 fpixel[1]= 1;
 if ( fits_read_pix( fptr, TUSHORT, fpixel, totpix, NULL, image, NULL, &status ) ) {
  fits_report_error( stderr, status );
  free( image );
  fits_close_file( fptr, &status );
  return 1;
 }

 /* Close the FITS file */
 fits_close_file( fptr, &status );

 /* Print header comment */
 fprintf( stderr, "# Processing %s (%ld x %ld pixels)\n", filename, naxes[0], naxes[1] );
 fprintf( stderr, "# Looking for pixels > %d to mask readout trails\n", threshold );

 /* Process the image to find saturated pixels */
 for ( i= 0; i < totpix; i++ ) {
  if ( image[i] > threshold ) {
   /* Convert linear index to x,y coordinates (1-based FITS convention) */
   x= ( i % naxes[0] ) + 1;
   y= ( i / naxes[0] ) + 1;

   /* Create a rectangle covering 3 pixels wide around the column */
   /* This matches the pattern seen in the example bad_region.lst */
   x_ll= x - 1;
   x_ur= x + 1;

   /* Ensure we don't go outside image bounds */
   if ( x_ll < 1 )
    x_ll= 1;
   if ( x_ur > naxes[0] )
    x_ur= naxes[0];

   /* Print rectangle in bad_region.lst format: X_ll Y_ll X_ur Y_ur */
   /* Mask from current Y coordinate to top of image */
   printf( "%4ld %4ld %4ld %4ld\n", x_ll, y, x_ur, naxes[1] );
  }
 }

 free( image );
 return 0;
}
