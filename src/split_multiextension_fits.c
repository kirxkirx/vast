// Split multi-extension FITS into single-extension FITS files

#include <string.h>
#include <stdlib.h>
#include <libgen.h>
#include <math.h>

#include "fitsio.h"

// VaST's own header files
#include "vast_limits.h" // defines FILENAME_LENGTH

int main( int argc, char *argv[] ) {

 int success_counter;

 int number_of_hdus, current_hdu, i;
 int current_hdu_type;

 fitsfile *fptrout;
 char strbuf[FILENAME_LENGTH];
 char outfilename[2 * FILENAME_LENGTH];
 // For reading FITS files
 fitsfile *fptr; // pointer to the FITS file; defined in fitsio.h
 //long  fpixel = 1, naxis = 2, nelements, exposure;
 //long naxes[2];
 //long testX,testY;

 int status= 0; //, hduT, bitpix, anynul=0,nullval=0, x;
 //unsigned int *image_array;

 // Check command line arguments
 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s multiextension_image.fits\n", argv[0] );
  return 1;
 }

 // Rading the input FITS file
 fits_open_file( &fptr, argv[1], 0, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 if ( status != 0 )
  exit( status );

 fits_get_num_hdus( fptr, &number_of_hdus, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 if ( status != 0 )
  exit( status );
 fprintf( stderr, "Found %d HDUs\n", number_of_hdus );

 // HDU#1 is the primary HDU! So we'll start from HDU#2
 for ( success_counter= 0, current_hdu= 2; current_hdu < number_of_hdus + 1; current_hdu++ ) {
  fits_movabs_hdu( fptr, current_hdu, &current_hdu_type, &status );
  strcpy( strbuf, basename( argv[1] ) );
  for ( i= strlen( strbuf ) - 1; i > 0; i-- ) {
   if ( strbuf[i] == '.' ) {
    strbuf[i]= '\0';
    break;
   }
  }
  sprintf( outfilename, "%s_%02d.fit", strbuf, current_hdu - 1 ); // Names will match HDU numbers in fv
  fprintf( stderr, "Writing %s ...", outfilename );
  fits_create_file( &fptrout, outfilename, &status );
  fits_report_error( stderr, status ); // print out any error messages
  if ( status != 0 )
   exit( 1 );
  fits_copy_hdu( fptr, fptrout, 0, &status );
  fits_close_file( fptrout, &status );
  success_counter++;
  fprintf( stderr, "done\n" );
 }

 fits_close_file( fptr, &status ); // close the input file

 fprintf( stderr, "Done splitting %s into %d single-extension FITS images!\n", argv[1], success_counter );

 return 0;
}
