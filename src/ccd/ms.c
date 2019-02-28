#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <time.h>

#include "../fitsio.h"

int main( int argc, char *argv[] ) {
 /* Для чтения фитсов */
 fitsfile *fptr; /* pointer to the FITS file; defined in fitsio.h */
 long fpixel= 1;
 long naxes[2];
 long testX, testY;

 int status= 0;
 int anynul= 0;
 unsigned short nullval= 0;
 unsigned short *image_array;
 unsigned short *dark_array;
 unsigned short *result_image_array;

 /* ----- */
 int i;
 int bitpix2;
 /* -- Для хранения ключей из шапки -- */
 //char *key[10000];
 char **key;
 int No_of_keys;
 int keys_left;
 int ii;

 double tmp;

 if ( argc != 4 ) {
  fprintf( stderr, "Wrong arguments amount... :(\n  Usage: %s image.fit dark.fit result.fit\n", argv[0] );
  exit( 1 );
 }

 /* Читаем файл */
 fprintf( stderr, "Exploring image header: %s \n", argv[1] );
 fits_open_file( &fptr, argv[1], 0, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 if ( status != 0 )
  exit( status );
 fits_read_key( fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 if ( status != 0 )
  exit( status );
 fits_read_key( fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 if ( status != 0 )
  exit( status );
 // Читаем из шапки то что стоит запомнить
 fits_get_hdrspace( fptr, &No_of_keys, &keys_left, &status );
 fprintf( stderr, "Header: %d keys total, %d keys left\n", No_of_keys, keys_left );
 key= malloc( No_of_keys * sizeof( char * ) );
 if ( key == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for FITS header\n" );
  exit( 1 );
 }
 for ( ii= 1; ii < No_of_keys; ii++ ) {
  key[ii]= malloc( FLEN_CARD * sizeof( char ) ); // FLEN_CARD length of a FITS header card defined in fitsio.h
  if ( key[ii] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for FITS header\n" );
   exit( 1 );
  }
  fits_read_record( fptr, ii, key[ii], &status );
  fprintf( stderr, "Record %d: \"%s\" status=%d\n", ii, key[ii], status );
  fits_report_error( stderr, status ); /* print out any error messages */
  status= 0;                           // continue on any errors at this stage
 }
 fits_get_img_type( fptr, &bitpix2, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 if ( status != 0 )
  exit( status );

 /* Выделяем память */
 fprintf( stderr, "Allocating memory for image, dark and result arrays...\n" );
 long img_size= naxes[0] * naxes[1];
 if ( img_size <= 0 ) {
  fprintf( stderr, "ERROR: Trying allocate negative or zero bytes of memory\n" );
  fits_close_file( fptr, &status );
  exit( 1 );
 };
 image_array= malloc( img_size * sizeof( short ) );
 if ( image_array == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for image_array\n" );
  fits_close_file( fptr, &status );
  exit( 1 );
 };
 dark_array= malloc( img_size * sizeof( short ) );
 if ( dark_array == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for dark_array\n" );
  free( image_array );
  fits_close_file( fptr, &status );
  exit( 1 );
 };
 result_image_array= malloc( img_size * sizeof( short ) );
 if ( result_image_array == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for result_image_array\n" );
  free( image_array );
  free( dark_array );
  fits_close_file( fptr, &status );
  exit( 1 );
 };
 /* И читаем картинку */
 fits_read_img( fptr, TUSHORT, 1, img_size, &nullval, image_array, &anynul, &status );
 fprintf( stderr, "Reading image %s %ld %ld  %d bitpix\n", argv[1], naxes[0], naxes[1], bitpix2 );
 fits_close_file( fptr, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 status= 0;

 /* Читаем дарк */
 fits_open_file( &fptr, argv[2], 0, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 if ( status != 0 )
  exit( status );
 fits_read_key( fptr, TLONG, "NAXIS1", &testX, NULL, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 if ( status != 0 )
  exit( status );
 fits_read_key( fptr, TLONG, "NAXIS2", &testY, NULL, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 if ( status != 0 )
  exit( status );
 if ( testX != naxes[0] || testY != naxes[1] ) {
  fprintf( stderr, "Image frame and dark frame must have same dimensions!\n" );
  exit( 1 );
 }
 fits_get_img_type( fptr, &bitpix2, &status );
 fits_read_img( fptr, TUSHORT, 1, naxes[0] * naxes[1], &nullval, dark_array, &anynul, &status );
 fprintf( stderr, "Reading dark frame %s %ld %ld  %d bitpix\n", argv[2], testX, testY, bitpix2 );
 fits_close_file( fptr, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 status= 0;
 /* Вычитаем темновой кадр */
 for ( i= 0; i < naxes[0] * naxes[1]; i++ ) {
  /* Try to avoid messing up overscan region */
  if ( dark_array[i] < image_array[i] ) {
   tmp= (double)image_array[i] - (double)dark_array[i];
  } else {
   tmp= (double)dark_array[i] - (double)image_array[i];
  }
  // the output image will be of 'unsigned short' type, so force the pixel values to be in that range
  if ( tmp <= 0.0 )
   tmp= 1.0; // we want to avoid 0 pixels in order not to confuse the VaST flag image creator
  if ( tmp > 65534.0 )
   tmp= 65534.5;
  // Preserve saturated pixels
  if ( image_array[i] == 65535 )
   tmp= 65534.5;
  //
  result_image_array[i]= (unsigned short)( tmp + 0.5 );
  //if ( result_image_array[i]>65000 )
  // result_image_array[i]=65535;
 }
 free( image_array );
 free( dark_array );
 fits_create_file( &fptr, argv[3], &status ); /* create new file */
 fits_report_error( stderr, status );         /* print out any error messages */
 if ( status != 0 )
  exit( 1 );
 fits_create_img( fptr, USHORT_IMG, 2, naxes, &status );
 fits_write_img( fptr, TUSHORT, fpixel, naxes[0] * naxes[1], result_image_array, &status );
 /* -- Пишем шапку -- */
 for ( ii= 1; ii < No_of_keys; ii++ ) {
  fits_write_record( fptr, key[ii], &status );
 }
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
 fits_write_history( fptr, argv[1], &status );
 fits_write_history( fptr, argv[2], &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 fits_close_file( fptr, &status );
 free( result_image_array );
 fprintf( stderr, "Dark frame is subtracted, output is written to %s :)\n\n", argv[3] );
 fprintf( stdout, "Spent %f seconds \n", 1.0 * clock() / CLOCKS_PER_SEC );

 for ( ii= 1; ii < No_of_keys; ii++ ) {
  free( key[ii] );
 }
 free( key );

 return 0;
}
