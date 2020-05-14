#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#include <unistd.h> // for unlink() ...

#include "../fitsio.h"

#include "../vast_limits.h"

// function defined in gettime.c
int Kourovka_SBG_date_hack( char *fitsfilename, char *DATEOBS, int *date_parsed, double *exposure );

int main( int argc, char **argv ) {
 int status= 0;  //, anynul=0,nullval=0; //for cfitsio routines
 fitsfile *fptr; /* pointer to the FITS file; defined in fitsio.h */
 char fitsfilename[FILENAME_LENGTH];
 char outputfitsfilename[2 * FILENAME_LENGTH];

 // for header file
 int i;              // stupid counter
 int No_of_wcs_keys; // number of keys in header
 int wcs_keys_left;
 char **wcs_key;

 //
 fitsfile *inputfptr;  /* pointer to the FITS file; defined in fitsio.h */
 fitsfile *outputfptr; /* pointer to the FITS file; defined in fitsio.h */

 //////////////////////////////
 // Kourovka_SBG_date_hack() //
 char DATEOBS[512];
 int date_parsed;
 double exposure;
 short *image_array;
 long naxes[2];
 int anynul= 0;
 //int nullval=0;
 short nullval;
 long fpixel= 1;
 //////////////////////////////

 if ( argc != 3 ) {
  fprintf( stderr, "Usage: %s wcs_header.fits image.fit\n", argv[0] );
  return 1;
 }

 /* Extract data from WCS fits header file */
 strncpy( fitsfilename, argv[1], FILENAME_LENGTH );
 fitsfilename[FILENAME_LENGTH - 1]= '\0';
 fits_open_file( &fptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fprintf( stderr, "ERROR opening FITS file %s for reding\n", fitsfilename);
  fits_report_error( stderr, status ); /* print out any error messages */
  return status;
 }
 fits_get_hdrspace( fptr, &No_of_wcs_keys, &wcs_keys_left, &status );
 wcs_key= malloc( No_of_wcs_keys * sizeof( char * ) );
 if ( wcs_key == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for wcs_key\n" );
  exit( 1 );
 };
 // Why on earth we start from 1???
 for ( i= 1; i < No_of_wcs_keys; i++ ) {
  wcs_key[i]= (char *)malloc( FLEN_CARD * sizeof( char ) ); // FLEN_CARD length of a FITS header card defined in fitsio.h
  if ( wcs_key[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for wcs_key[i]\n" );
   exit( 1 );
  };
  fits_read_record( fptr, i, wcs_key[i], &status );
 }
 fits_close_file( fptr, &status ); // close file

 /* Read image */
 strncpy( fitsfilename, argv[2], 1024 );
 fprintf( stderr, "Opening FITS image file (%s)...  ", fitsfilename );
 fits_open_file( &inputfptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fprintf( stderr, "ERROR: cannot open file %s for reading (2)\n", fitsfilename );
  return status;
 }
 fprintf( stderr, "done!\n" );
 sprintf( outputfitsfilename, "wcs_%s", fitsfilename );
 fprintf( stderr, "Creating new image file (%s)...  ", outputfitsfilename );
 fits_create_file( &outputfptr, outputfitsfilename, &status ); /* create new file */
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fprintf( stderr, "ERROR: problem creating new file!\n" );
  return status;
 }
 fprintf( stderr, "done!\n" );
 fprintf( stderr, "Copying HDU...  " );
 fits_copy_hdu( inputfptr, outputfptr, 0, &status );
 //
 if ( status == 207 ) {
  fprintf( stderr, "Oh, is this a Kourovka SBG image?!\n Will try to handle it...\n" );
  status= 0;
  if ( 0 == Kourovka_SBG_date_hack( fitsfilename, DATEOBS, &date_parsed, &exposure ) ) {
   // Remove leftovers from the failed run
   fits_close_file( inputfptr, &status );  // close file
   fits_close_file( outputfptr, &status ); // close file
   if ( 0 != unlink( outputfitsfilename ) ) {
    fprintf( stderr, "ERROR! Cannot delete incomplete output file %s\n", outputfitsfilename ); // remove incomplete output file
    return 1;
   }
   // Re-open files another way
   fits_open_file( &inputfptr, fitsfilename, READONLY, &status );
   fits_read_key( inputfptr, TLONG, "NAXIS1", &naxes[0], NULL, &status );
   fits_report_error( stderr, status );
   if ( status != 0 )
    return status;
   fits_read_key( inputfptr, TLONG, "NAXIS2", &naxes[1], NULL, &status );
   fits_report_error( stderr, status );
   if ( status != 0 )
    return status;
   image_array= malloc( naxes[0] * naxes[1] * sizeof( short ) );
   if ( image_array == NULL ) {
    fprintf( stderr, "ERROR allocating memory for the image_array!\n" );
    return 1;
   }
   fits_read_img( inputfptr, TSHORT, 1, naxes[0] * naxes[1], &nullval, image_array, &anynul, &status );
   fits_report_error( stderr, status );
   if ( status != 0 ) {
    return status;
   }
   fits_create_file( &outputfptr, outputfitsfilename, &status );
   fits_report_error( stderr, status );
   if ( status != 0 ) {
    return status;
   }
   fits_create_img( outputfptr, SHORT_IMG, 2, naxes, &status );
   fits_report_error( stderr, status );
   if ( status != 0 ) {
    return status;
   }
   fits_update_key( outputfptr, TSTRING, "DATE-OBS", DATEOBS, "UTC observation start date", &status );
   fits_report_error( stderr, status );
   if ( status != 0 ) {
    return status;
   }
   fits_update_key( outputfptr, TDOUBLE, "EXPOSURE", &exposure, "Exposure time in seconds", &status );
   fits_report_error( stderr, status );
   if ( status != 0 ) {
    return status;
   }
   fits_write_img( outputfptr, TSHORT, fpixel, naxes[0] * naxes[1], image_array, &status );
   fits_report_error( stderr, status );
   if ( status != 0 ) {
    return status;
   }
  } else {
   fprintf( stderr, "Nope, this does not appear to be a Kourovka SBG image...\n" );
   status= 1;
  }
 } // if(status==207){
 //
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fprintf( stderr, "ERROR: problem copying HDU!\n" );
  fits_close_file( inputfptr, &status );  // close file
  fits_close_file( outputfptr, &status ); // close file
  if ( 0 != unlink( outputfitsfilename ) ) {
   fprintf( stderr, "ERROR: cannot delete incomplete output file %s\n", outputfitsfilename ); // remove incomplete output file
  }
  return status;
 }
 fprintf( stderr, "done!\n" );

 // Remove all keys which we absolutely don't want to see duplicated
 status= 0;
 fits_delete_key( outputfptr, "CTYPE1", &status );
 status= 0;
 fits_delete_key( outputfptr, "CTYPE2", &status );
 status= 0;
 fits_delete_key( outputfptr, "EQUINOX", &status );
 status= 0;
 fits_delete_key( outputfptr, "LONPOLE", &status );
 status= 0;
 fits_delete_key( outputfptr, "LATPOLE", &status );
 status= 0;
 fits_delete_key( outputfptr, "CRVAL1", &status );
 status= 0;
 fits_delete_key( outputfptr, "CRVAL2", &status );
 status= 0;
 fits_delete_key( outputfptr, "CRPIX1", &status );
 status= 0;
 fits_delete_key( outputfptr, "CRPIX2", &status );
 status= 0;
 fits_delete_key( outputfptr, "CUNIT1", &status );
 status= 0;
 fits_delete_key( outputfptr, "CUNIT2", &status );
 status= 0;
 fits_delete_key( outputfptr, "CD1_1", &status );
 status= 0;
 fits_delete_key( outputfptr, "CD1_2", &status );
 status= 0;
 fits_delete_key( outputfptr, "CD2_1", &status );
 status= 0;
 fits_delete_key( outputfptr, "CD2_2", &status );
 status= 0;
 fits_delete_key( outputfptr, "IMAGEW", &status );
 status= 0;
 fits_delete_key( outputfptr, "IMAGEH", &status );
 status= 0;
 fits_delete_key( outputfptr, "A_ORDER", &status );
 status= 0;
 fits_delete_key( outputfptr, "A_0_2", &status );
 status= 0;
 fits_delete_key( outputfptr, "A_1_1", &status );
 status= 0;
 fits_delete_key( outputfptr, "A_2_0", &status );
 status= 0;
 fits_delete_key( outputfptr, "B_ORDER", &status );
 status= 0;
 fits_delete_key( outputfptr, "B_0_2", &status );
 status= 0;
 fits_delete_key( outputfptr, "B_1_1", &status );
 status= 0;
 fits_delete_key( outputfptr, "B_2_0", &status );
 status= 0;
 fits_delete_key( outputfptr, "AP_ORDER", &status );
 status= 0;
 fits_delete_key( outputfptr, "AP_0_1", &status );
 status= 0;
 fits_delete_key( outputfptr, "AP_0_2", &status );
 status= 0;
 fits_delete_key( outputfptr, "AP_1_0", &status );
 status= 0;
 fits_delete_key( outputfptr, "AP_1_1", &status );
 status= 0;
 fits_delete_key( outputfptr, "AP_2_0", &status );
 status= 0;
 fits_delete_key( outputfptr, "BP_ORDER", &status );
 status= 0;
 fits_delete_key( outputfptr, "BP_0_1", &status );
 status= 0;
 fits_delete_key( outputfptr, "BP_0_2", &status );
 status= 0;
 fits_delete_key( outputfptr, "BP_1_0", &status );
 status= 0;
 fits_delete_key( outputfptr, "BP_1_1", &status );
 status= 0;
 fits_delete_key( outputfptr, "BP_2_0", &status );
 status= 0;
 fits_delete_key( outputfptr, "CDELT1", &status );
 status= 0;
 fits_delete_key( outputfptr, "CDELT2", &status );
 status= 0;
 fits_delete_key( outputfptr, "CROTA1", &status );
 status= 0;
 fits_delete_key( outputfptr, "CROTA2", &status );
 status= 0;

 for ( i= 0; i < 10000; i++ ) {
  fits_delete_key( outputfptr, "TR?_*", &status );
  status= 0;
 }

/* Why do we want to delete HISTORY??
 for ( i= 0; i < 10000; i++ ) {
  fits_delete_key( outputfptr, "HISTORY", &status );
  status= 0;
 }
*/

 status= 0;

 for ( i= 5; i < No_of_wcs_keys; i++ ) {
  fits_write_record( outputfptr, wcs_key[i], &status );
 }

 fits_close_file( inputfptr, &status );  // close file
 fits_close_file( outputfptr, &status ); // close file

 fits_report_error( stderr, status ); /* print out any error messages */

 fprintf( stderr, "All done!\n" );

 for ( i= 1; i < No_of_wcs_keys; i++ ) {
  free( wcs_key[i] );
 }
 free( wcs_key );

 return 0;
}
