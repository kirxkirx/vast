#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#include <unistd.h> // for unlink() ...

#include "../fitsio.h"
#include "../vast_limits.h"
#include "../safely_encode_user_input_string.h" // needed by fitsfile_read_check.h
#include "../fitsfile_read_check.h"

#include "../kourovka_sbg_date.h"
// function defined in gettime.c
//int Kourovka_SBG_date_hack( char *fitsfilename, char *DATEOBS, int *date_parsed, double *exposure );

int main( int argc, char **argv ) {
 int this_is_a_good_image_hdu= 0;
 int hdutype;
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
  fprintf( stderr, "ERROR opening FITS file %s for reding\n", fitsfilename );
  fits_report_error( stderr, status ); /* print out any error messages */
  return status;
 }
 fits_get_hdrspace( fptr, &No_of_wcs_keys, &wcs_keys_left, &status );
 wcs_key= malloc( No_of_wcs_keys * sizeof( char * ) );
 if ( NULL == wcs_key ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for wcs_key\n" );
  exit( EXIT_FAILURE );
 };
 // Initialize all elements to NULL
 memset( wcs_key, 0, sizeof( char * ) * No_of_wcs_keys );
 //
 wcs_key[0]= (char *)malloc( FLEN_CARD * sizeof( char ) );
 if ( NULL == wcs_key[0] ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for wcs_key[0](try_to_guess_image_fov)\n" );
  exit( EXIT_FAILURE );
 };
 memset( wcs_key[0], 0, FLEN_CARD * sizeof( char ) );
 //
 // Why on earth we start from 1???
 for ( i= 1; i < No_of_wcs_keys; i++ ) {
  wcs_key[i]= (char *)malloc( FLEN_CARD * sizeof( char ) ); // FLEN_CARD length of a FITS header card defined in fitsio.h
  if ( NULL == wcs_key[i] ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for wcs_key[i]\n" );
   exit( EXIT_FAILURE );
  };
  memset( wcs_key[i], 0, FLEN_CARD * sizeof( char ) );
  fits_read_record( fptr, i, wcs_key[i], &status );
 }
 fits_close_file( fptr, &status ); // close file

 // Read image //
 strncpy( fitsfilename, argv[2], 1024 );
 sprintf( outputfitsfilename, "wcs_%s", fitsfilename );
 fprintf( stderr, "Opening FITS image file %s for reading...  ", fitsfilename );
 fits_open_file( &inputfptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fprintf( stderr, "WARNING: cannot open file %s for reading (2)\n", fitsfilename );
  // This is a special test for the strange bug when the output file gets created while we are still solving the plate
  if ( 0 == fitsfile_read_check( outputfitsfilename ) ) {
   fprintf( stderr, "WARNING: the output file %s already exist! Will not insert any header. (1)\n", outputfitsfilename );
   return 0; // assume success - everything was done by someone else
  }
  fprintf( stderr, "ERROR: the output file %s was not created by anyone else\n", fitsfilename );
  return status;
 }
 fprintf( stderr, "done!\n" );
 // This is a special test for the strange bug when the output file gets created while we are still solving the plate
 if ( 0 == fitsfile_read_check_silent( outputfitsfilename ) ) {
  fprintf( stderr, "WARNING: the output file %s already exist! Will not insert any header. (2)\n", outputfitsfilename );
  return 0; // assume success - everything was done by someone else
 }
 //
 fprintf( stderr, "Creating new image file (%s)...  ", outputfitsfilename );
 fits_create_file( &outputfptr, outputfitsfilename, &status ); /* create new file */
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fprintf( stderr, "ERROR: problem creating new file!\n" );
  return status;
 }
 fprintf( stderr, "done!\n" );
 // fprintf(stderr, "Copying HDU...  ");
 fits_copy_file( inputfptr, outputfptr, 1, 1, 1, &status );
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

 // Normal close the input file
 fits_close_file( inputfptr, &status ); // close input file

 // Move to the first image HDU - we want all the following operations to be applied to it
 this_is_a_good_image_hdu= 0;
 status= 0;
 fits_movabs_hdu( outputfptr, 1, &hdutype, &status ); // move to the first HDU
 if ( status != 0 ) {
  fprintf( stderr, "ERROR: moving to the first HDU\n" );
  return 1;
 }
 if ( hdutype == IMAGE_HDU ) {
  // this looks promising
  fits_read_key( outputfptr, TLONG, "NAXIS1", &naxes[0], NULL, &status );
  if ( status == 0 ) {
   if ( naxes[0] > 1 ) {
    this_is_a_good_image_hdu= 1;
   }
  }
  status= 0; // reset status - no key - no problem
 }

 // if the first HDU is no good - try the next one
 if ( this_is_a_good_image_hdu == 0 ) {

  fits_movrel_hdu( outputfptr, 1, &hdutype, &status ); // move to the next HDU
  if ( status != 0 ) {
   fprintf( stderr, "ERROR: moving to the next HDU\n" );
   return 1;
  }

  if ( hdutype == IMAGE_HDU ) {
   // this looks promising
   fits_read_key( outputfptr, TLONG, "NAXIS1", &naxes[0], NULL, &status );
   if ( status == 0 ) {
    if ( naxes[0] > 1 ) {
     this_is_a_good_image_hdu= 1;
    }
   }
   status= 0; // reset status - no key - no problem
  }

 } // if( this_is_a_good_image_hdu == 0 ) {

 if ( this_is_a_good_image_hdu != 1 ) {
  fprintf( stderr, "ERROR: the none of the first two HDUs has  hdutype = IMAGE_HDU  with  NAXIS1 > 1\n" );
  return 1;
 }

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

 // list all possible PV keywords

 // PV1_
 fits_delete_key( outputfptr, "PV1_0", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_1", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_2", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_3", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_4", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_5", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_6", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_7", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_8", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_9", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_10", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_11", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_12", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_13", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_14", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_15", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_16", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_17", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_18", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_19", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_20", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_21", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_22", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_23", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_24", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_25", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_26", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_27", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_28", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_29", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_30", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_31", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_32", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_33", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_34", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_35", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_36", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_37", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_38", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV1_39", &status );
 status= 0;
 //
 // PV2_
 fits_delete_key( outputfptr, "PV2_0", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_1", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_2", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_3", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_4", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_5", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_6", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_7", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_8", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_9", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_10", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_11", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_12", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_13", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_14", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_15", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_16", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_17", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_18", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_19", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_20", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_21", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_22", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_23", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_24", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_25", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_26", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_27", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_28", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_29", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_30", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_31", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_32", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_33", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_34", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_35", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_36", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_37", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_38", &status );
 status= 0;
 fits_delete_key( outputfptr, "PV2_39", &status );
 status= 0;

 // somehow this doesn't seem to work
 for ( i= 0; i < 10000; i++ ) {
  fits_delete_key( outputfptr, "PV*_*", &status );
  status= 0;
 }

 status= 0;

 for ( i= 5; i < No_of_wcs_keys; i++ ) {
  fits_write_record( outputfptr, wcs_key[i], &status );
 }

 // fits_close_file(inputfptr, &status);  // close file // moved up
 fits_close_file( outputfptr, &status ); // close output file

 fits_report_error( stderr, status ); // print out any error messages

 fprintf( stderr, "All done!\n" );

 for ( i= 1; i < No_of_wcs_keys; i++ ) {
  free( wcs_key[i] );
 }
 //
 free( wcs_key[0] );
 //
 free( wcs_key );

 return 0;
}
