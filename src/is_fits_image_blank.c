/*
 * This file contains a function to check if a FITS image is blank.
 * A blank image is one where all pixels have constant values,
 * which typically indicates a camera error.
 */

#include <stdio.h>
#include <stdlib.h>

#include "fitsio.h"
#include "vast_limits.h"

// Check if a FITS image is blank (all pixels have constant values)
// Returns:
//   0 - image is NOT blank (has variation/noise/stars)
//   1 - image IS blank (all pixels are constant)
//  -1 - error reading the image
int is_fits_image_blank( char *fitsfilename ) {
 fitsfile *fptr;
 int status= 0;
 int naxis;
 long naxes[2];
 long totpix;
 double *pix;
 int anynul= 0;
 double nullval= 0.0;
 long ii;

 double min_val, max_val;

 // Open the FITS image
 if ( 0 != fits_open_image( &fptr, fitsfilename, READONLY, &status ) ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  return -1;
 }

 // Get image dimensions
 fits_get_img_dim( fptr, &naxis, &status );
 if ( status != 0 || naxis < 2 ) {
  fprintf( stderr, "ERROR in is_fits_image_blank(): cannot get image dimensions for %s\n", fitsfilename );
  fits_close_file( fptr, &status );
  return -1;
 }

 fits_get_img_size( fptr, 2, naxes, &status );
 if ( status != 0 ) {
  fprintf( stderr, "ERROR in is_fits_image_blank(): cannot get image size for %s\n", fitsfilename );
  fits_close_file( fptr, &status );
  return -1;
 }

 if ( naxes[0] < 1 || naxes[1] < 1 ) {
  fprintf( stderr, "ERROR in is_fits_image_blank(): invalid image dimensions for %s\n", fitsfilename );
  fits_close_file( fptr, &status );
  return -1;
 }

 totpix= naxes[0] * naxes[1];

 // Allocate memory for the image
 pix= (double *)malloc( totpix * sizeof( double ) );
 if ( pix == NULL ) {
  fprintf( stderr, "ERROR in is_fits_image_blank(): cannot allocate memory for %s\n", fitsfilename );
  fits_close_file( fptr, &status );
  return -1;
 }

 // Read the image
 fits_read_img( fptr, TDOUBLE, 1, totpix, &nullval, pix, &anynul, &status );
 if ( status != 0 ) {
  fprintf( stderr, "ERROR in is_fits_image_blank(): cannot read image data from %s\n", fitsfilename );
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  free( pix );
  fits_close_file( fptr, &status );
  return -1;
 }

 fits_close_file( fptr, &status );

 // Find min and max values
 min_val= pix[0];
 max_val= pix[0];

 for ( ii= 1; ii < totpix; ii++ ) {
  if ( pix[ii] < min_val ) {
   min_val= pix[ii];
  }
  if ( pix[ii] > max_val ) {
   max_val= pix[ii];
  }
 }

 free( pix );

 // If min equals max, all pixels have the same value - the image is blank
 if ( max_val == min_val ) {
  fprintf( stderr, "Image %s is BLANK: all %ld pixels have the same value %.2f\n", fitsfilename, totpix, min_val );
  return 1;
 }

 // Image has variation - it's not blank
 return 0;
}
