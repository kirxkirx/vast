// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_FITSFILE_READ_CHECK_INCLUDE_FILE

#include "fitsio.h" // we use a local copy of this file because we use a local copy of cfitsio

#include <stdio.h>

#define _GNU_SOURCE // doesn't seem to work!
#include <string.h> // for memmem()

void *memmem( const void *haystack, size_t haystacklen, const void *needle, size_t needlelen );

static void check_if_the_input_is_MaxIM_compressed_FITS( char *fitsfilename ) {
 FILE *f;
 char *buffer; // buffer for a part of the header
 char *pointer_to_the_key_start;
 int i;
 f= fopen( fitsfilename, "r" );
 if ( f == NULL ) {
  return;
 }
 buffer= malloc( 65536 * sizeof( char ) );
 if ( buffer == NULL ) {
  fprintf( stderr, "ERROR in check_if_the_input_is_MaxIM_compressed_FITS(): cannot allocate buffer memory\n" );
  return;
 }
 memset( buffer, 0, 65535 ); // wipe the memory just in case there was something there
 for ( i= 0; i < 65535; i++ ) {
  buffer[i]= getc( f );
  if ( buffer[i] == EOF ) {
   break;
  }
 }
 fclose( f );
 // Check for signs of the compressed FITS image
 pointer_to_the_key_start= (char *)memmem( buffer, 65535 - 80, "SIMPLE", 6 );
 if ( pointer_to_the_key_start != NULL ) {
  pointer_to_the_key_start= (char *)memmem( buffer, 65535 - 80, "BITPIX", 6 );
  if ( pointer_to_the_key_start != NULL ) {
   pointer_to_the_key_start= (char *)memmem( buffer, 65535 - 80, "NAXIS", 5 );
   if ( pointer_to_the_key_start != NULL ) {
    fprintf( stderr, "\n#########################################################\nThe file %s \nactually looks like a FITS image compressed by MaxIM DL.\nPlease open the image in MaxIM DL software and save it as\nUncompressed FITS. I'm not aware of any other (legal) way\nto uncompress such images.\n#########################################################\n", fitsfilename );
   }
  }
 }
 free( buffer );
 return;
}

// This function will check if the input is a readable FITS image
static inline int fitsfile_read_check( char *fitsfilename ) {
 int status= 0;  //for cfitsio routines
 fitsfile *fptr; // pointer to the FITS file; defined in fitsio.h
 int hdutype, naxis;
 long naxes3;
 long naxes4;
 // check if this is a readable FITS image
 fits_open_image( &fptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  check_if_the_input_is_MaxIM_compressed_FITS( fitsfilename );
  return status;
 }
 if ( fits_get_hdu_type( fptr, &hdutype, &status ) || hdutype != IMAGE_HDU ) {
  fprintf( stderr, "%s is not a FITS image! Is it a FITS table?\n", fitsfilename );
  fits_close_file( fptr, &status );
  return 1;
 }
 fits_get_img_dim( fptr, &naxis, &status );
 if ( status || naxis != 2 ) {
  if ( naxis == 3 ) {
   fits_read_key( fptr, TLONG, "NAXIS3", &naxes3, NULL, &status );
   if ( naxes3 == 1 ) {
    fprintf( stderr, "%s image has NAXIS = %d, but NAXIS3 = %ld -- maybe there is some hope to handle this image...\n", fitsfilename, naxis, naxes3 );
    fits_close_file( fptr, &status );
    return 0;
   }
  }
  if ( naxis == 4 ) {
   fits_read_key( fptr, TLONG, "NAXIS3", &naxes3, NULL, &status );
   if ( naxes3 == 1 ) {
    fits_read_key( fptr, TLONG, "NAXIS4", &naxes4, NULL, &status );
    if ( naxes4 == 1 ) {
     fprintf( stderr, "%s image has NAXIS = %d, but NAXIS3 = %ld and NAXIS4 = %ld -- maybe there is some hope to handle this image...\n", fitsfilename, naxis, naxes3, naxes4 );
     fits_close_file( fptr, &status );
     return 0;
    }
   }
  }
  fprintf( stderr, "%s image has NAXIS = %d.  Only 2-D images are supported.\n", fitsfilename, naxis );
  fits_close_file( fptr, &status );
  return 1;
 }
 fits_close_file( fptr, &status );
 return 0;
}

// The macro below will tell the pre-processor that this header file is already included
#define VAST_FITSFILE_READ_CHECK_INCLUDE_FILE
#endif
// VAST_FITSFILE_READ_CHECK_INCLUDE_FILE
