#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h> // for unlink()
#include <gsl/gsl_sort.h>
#include <gsl/gsl_statistics.h>

#include "../fitsio.h"

#include "../vast_limits.h"

#define FALLBACK_CCD_TEMP_VALUE 100
#define MAX_CCD_TEMP_DIFF 2.5
#define MIN_FLAT_FIELD_COUNT 5000
#define MAX_FLAT_FIELD_COUNT 20000
#define MAX_BRIGHTNESS 50000

char *beztochki( char * );

void handle_error(const char *message, int status) {
    fprintf(stderr, "ERROR: %s\n", message);
    fits_report_error(stderr, status);
    exit(EXIT_FAILURE);
}

int main( int argc, char *argv[] ) {
 // Varaibles for FITS file reading
 fitsfile *fptr; // pointer to the FITS file; defined in fitsio.h
 long fpixel= 1;
 long naxes[2];
 long naxes_ref[2];

 int status= 0;
 int anynul= 0;
 unsigned short nullval= 0;
 unsigned short **image_array;
 unsigned short *combined_array;
 double y[MAX_NUMBER_OF_OBSERVATIONS];
 double *yy;
 double val;
 double ref_index= 1.0; // just to make the compiler happy
 double cur_index= 1.0; // just to make the compiler happy
 int i;
 int bitpix2;
 int file_counter;
 int good_file_counter;

 double set_temp_image, ccd_temp_image;

 // These variables are needed to keep FITS header keys
 char **key;
 int No_of_keys;
 int keys_left;
 int ii;
 long bzero= 0;
 char bzero_comment[FLEN_CARD];
 int bzero_key_found= 0;

 FILE *filedescriptor_for_opening_test;

 fprintf( stderr, "Median combiner v2.4\n\n" );
 fprintf( stderr, "Combining %d files\n", argc - 1 );
 if ( argc < 3 ) {
  fprintf( stderr, "Not enough arguments...\n  Usage: %s flat01.fit flat02.fit flat03.fit ...\n", argv[0] );
  exit( EXIT_FAILURE );
 }

 // Allocate combined array
 fits_open_file( &fptr, argv[1], 0, &status );
 fits_read_key( fptr, TLONG, "NAXIS1", &naxes_ref[0], NULL, &status );
 fits_read_key( fptr, TLONG, "NAXIS2", &naxes_ref[1], NULL, &status );
 // Note the set temperature of the camera
 fits_read_key( fptr, TDOUBLE, "SET-TEMP", &set_temp_image, NULL, &status );
 if ( status != 0 ) {
  set_temp_image= FALLBACK_CCD_TEMP_VALUE;
  status= 0;
 }
 // Note the CCD temperature of the camera
 fits_read_key( fptr, TDOUBLE, "CCD-TEMP", &ccd_temp_image, NULL, &status );
 if ( status != 0 ) {
  ccd_temp_image= FALLBACK_CCD_TEMP_VALUE;
  status= 0;
 }
 // Check for possible mismatch between CCD-TEMP and SET-TEMP
 if ( ccd_temp_image != FALLBACK_CCD_TEMP_VALUE && set_temp_image != FALLBACK_CCD_TEMP_VALUE ) {
  fprintf( stderr, "CCD-TEMP= %lf for %s\n", ccd_temp_image, argv[1] );
  fprintf( stderr, "SET-TEMP= %lf for %s\n", set_temp_image, argv[1] );
  if ( fabs( ccd_temp_image - set_temp_image ) > MAX_CCD_TEMP_DIFF ) {
   // found set temperature mismatch
   fprintf( stderr, "ERROR: mismatch between CCD-TEMP and SET-TEMP! Looks like the the camera didn't have time to cool down.\n" );
   fits_close_file( fptr, &status );
   exit( EXIT_FAILURE );
  }
 }
 //
 fits_get_hdrspace( fptr, &No_of_keys, &keys_left, &status );
 // !!!!!!!!!!! Not sure why, but this is clearly needed in order not to loose the last key !!!!!!!!!!!
 No_of_keys++;
 // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 key= malloc( No_of_keys * sizeof( char * ) );
 if ( key == NULL ) {
  handle_error("Couldn't allocate memory for FITS header", status);
 }
 for ( ii= 1; ii < No_of_keys; ii++ ) {
  key[ii]= malloc( FLEN_CARD * sizeof( char ) ); // FLEN_CARD length of a FITS header card defined in fitsio.h
  if ( key[ii] == NULL ) {
   handle_error("Couldn't allocate memory for key[ii]", status);
   for (int j = 1; j < ii; j++) {
       free(key[j]);
   }
   free(key);
  }
  fits_read_record( fptr, ii, key[ii], &status );
 }
 fits_read_key( fptr, TLONG, "BZERO", &bzero, bzero_comment, &status );
 if ( status != 0 ) {
  status= 0;
  bzero_key_found= 0;
 } else {
  bzero_key_found= 1;
 }
 fits_close_file( fptr, &status );
 fits_report_error( stderr, status ); // print out any error messages

 long img_size= naxes_ref[0] * naxes_ref[1];
 if ( img_size <= 0 ) {
  fprintf( stderr, "ERROR: The image size cannot be negative\n" );
  exit( EXIT_FAILURE );
 }
 combined_array= malloc( img_size * sizeof( short ) );
 if ( combined_array == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for combined_array\n" );
  exit( EXIT_FAILURE );
 }
 //
 
 image_array= NULL;

/*
 image_array= malloc( sizeof( unsigned short * ) ); // this will be realloc'ed before use anyhow
 if ( image_array == NULL ) {
  fprintf( stderr, "ERROR in mk: Couldn't allocate memory for image array (0)\n" );
  exit( EXIT_FAILURE );
 }
*/

 // Reading the input files
 for ( file_counter= 1; file_counter < argc; file_counter++ ) {
  fits_open_file( &fptr, argv[file_counter], 0, &status );
  fits_read_key( fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status );
  fits_read_key( fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status );
  if ( naxes_ref[0] != naxes[0] || naxes_ref[1] != naxes[1] ) {
   fprintf( stderr, "ERROR: image size mismatch %ldx%ld for %s vs. %ldx%ld for %s\n", naxes[0], naxes[1], argv[file_counter], naxes_ref[0], naxes_ref[1], argv[1] );
   exit( EXIT_FAILURE );
  }
  // Note the set temperature of the camera
  fits_read_key( fptr, TDOUBLE, "SET-TEMP", &set_temp_image, NULL, &status );
  if ( status != 0 ) {
   set_temp_image= FALLBACK_CCD_TEMP_VALUE;
   status= 0;
  }
  // Note the CCD temperature of the camera
  fits_read_key( fptr, TDOUBLE, "CCD-TEMP", &ccd_temp_image, NULL, &status );
  if ( status != 0 ) {
   ccd_temp_image= FALLBACK_CCD_TEMP_VALUE;
   status= 0;
  }
  // Check for possible mismatch between CCD-TEMP and SET-TEMP
  if ( ccd_temp_image != FALLBACK_CCD_TEMP_VALUE && set_temp_image != FALLBACK_CCD_TEMP_VALUE ) {
   fprintf( stderr, "CCD-TEMP= %lf for %s\n", ccd_temp_image, argv[file_counter] );
   fprintf( stderr, "SET-TEMP= %lf for %s\n", set_temp_image, argv[file_counter] );
   if ( fabs( ccd_temp_image - set_temp_image ) > MAX_CCD_TEMP_DIFF ) {
    // found set temperature mismatch
    fprintf( stderr, "ERROR: mismatch between CCD-TEMP and SET-TEMP! Looks like the the camera didn't have time to cool down.\n" );
    fits_close_file( fptr, &status );
    exit( EXIT_FAILURE );
   }
  }
  //
  // Allocate memory for the input images
  image_array= realloc( image_array, file_counter * sizeof( unsigned short * ) );
  image_array[file_counter - 1]= malloc( img_size * sizeof( unsigned short ) );
  if ( image_array[file_counter - 1] == NULL ) {
   fprintf( stderr, "ERROR in mk: Couldn't allocate memory for image array\n Current image: %s\n", argv[file_counter] );
   exit( EXIT_FAILURE );
  }

  // Reading FITS header keywords from the first image we'll need to remember
  fits_get_img_type( fptr, &bitpix2, &status );
  fprintf( stderr, "Reading %s %ld %ld  %d bitpix\n", argv[file_counter], naxes[0], naxes[1], bitpix2 );
  if ( bitpix2 != SHORT_IMG ) {
   fprintf( stderr, "ERROR: BITPIX = %d.  Only SHORT_IMG (BITPIX = %d) images are currently supported.\n", bitpix2, SHORT_IMG );
   exit( EXIT_FAILURE );
  }
  fits_read_img( fptr, TUSHORT, 1, naxes[0] * naxes[1], &nullval, image_array[file_counter - 1], &anynul, &status );
  fits_close_file( fptr, &status );
  fits_report_error( stderr, status ); // print out any error messages
  if ( status != 0 ) {
   exit( EXIT_FAILURE );
  }
 }

 yy= malloc( img_size * sizeof( double ) );
 if ( yy == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for yy array\n" );
  exit( EXIT_FAILURE );
 };

 good_file_counter= 0;
 for ( file_counter= 1; file_counter < argc; file_counter++ ) {
  for ( i= 0; i < img_size; i++ ) {
   yy[i]= image_array[file_counter - 1][i];
  }
  gsl_sort( yy, 1, img_size );
  cur_index= gsl_stats_median_from_sorted_data( yy, 1, img_size );
  fprintf( stderr, "cur_index=%lf\n", cur_index );

  // Reject obviously bad images from the flat-field stack
  // (but how do we know it's a flat stack?)
  // assume if the value is below 5000 counts it's a dark/bias staks and not flat
  if ( MIN_FLAT_FIELD_COUNT < cur_index && cur_index < MAX_FLAT_FIELD_COUNT ) {
   fprintf( stderr, "REJECT (too faint for a flat field)\n" );
   continue; // continue here so good_file_counter does not increase
  }
  if ( cur_index > MAX_BRIGHTNESS ) {
   fprintf( stderr, "REJECT (too bright)\n" );
   continue; // continue here so good_file_counter does not increase
  }

  if ( good_file_counter == 0 ) {
   ref_index= cur_index;
   fprintf( stderr, "ref_index=%lf\n", ref_index );
  }

  for ( ii= 0; ii < img_size; ii++ ) {
   image_array[good_file_counter][ii]= image_array[file_counter - 1][ii] * ref_index / cur_index;
  }
  good_file_counter++;
 }
 free( yy );

 if ( good_file_counter < 2 ) {
  fprintf( stderr, "ERROR: only %d images passed the mean count cuts!\n", good_file_counter );
  exit( EXIT_FAILURE );
 }

 //
 for ( i= 0; i < img_size; i++ ) {
  for ( file_counter= 0; file_counter < good_file_counter; file_counter++ ) {
   y[file_counter]= image_array[file_counter][i];
  }
  gsl_sort( y, 1, good_file_counter );
  val= gsl_stats_median_from_sorted_data( y, 1, good_file_counter );
  combined_array[i]= (unsigned short)( val + 0.5 );
 }

 // Write the output FITS file
 // (DELETE the file with this name if it already exists)
 filedescriptor_for_opening_test= fopen( "median.fit", "r" );
 if ( NULL != filedescriptor_for_opening_test ) {
  fprintf( stderr, "WARNING: removing the output file from the previous run: median.fit\n" );
  fclose( filedescriptor_for_opening_test );
  unlink( "median.fit" );
 }
 fits_create_file( &fptr, "median.fit", &status ); /* create new file */
 fits_create_img( fptr, USHORT_IMG, 2, naxes, &status );
 fits_write_img( fptr, TUSHORT, fpixel, img_size, combined_array, &status );
 free( combined_array );

 // Write the FITS header
 for ( ii= 1; ii < No_of_keys; ii++ ) {
  fits_write_record( fptr, key[ii], &status );
 }
 // Delete the following keywords to avoid duplication
 fits_delete_key( fptr, "SIMPLE", &status );
 fits_delete_key( fptr, "BITPIX", &status );
 fits_delete_key( fptr, "NAXIS", &status );
 fits_delete_key( fptr, "NAXIS1", &status );
 fits_delete_key( fptr, "NAXIS2", &status );
 fits_delete_key( fptr, "EXTEND", &status );
 fits_delete_key( fptr, "COMMENT", &status );
 fits_delete_key( fptr, "COMMENT", &status );
 fits_delete_key( fptr, "BZERO", &status );
 fits_delete_key( fptr, "BSCALE", &status );

 if ( bzero_key_found == 1 ) {
  fits_write_key( fptr, TLONG, "BZERO", &bzero, bzero_comment, &status );
 }

 fits_write_history( fptr, "Median frame stacking:", &status );
 for ( ii= 1; ii < argc; ii++ ) {
  fits_write_history( fptr, argv[ii], &status );
 }
 fits_report_error( stderr, status ); /* print out any error messages */
 fits_close_file( fptr, &status );

 for ( file_counter= 1; file_counter < argc; file_counter++ ) {
  free( image_array[file_counter - 1] );
 }
 free( image_array );

 fprintf( stderr, "Writing output to median.fit \n" );
 fits_report_error( stderr, status ); /* print out any error messages */

 for ( ii= 1; ii < No_of_keys; ii++ ) {
  free( key[ii] );
 }
 free( key );

 return status;
}
