#include <stdio.h>
#include <string.h>
#include <strings.h> // for strcasecmp()
#include <stdlib.h>
#include <math.h>
#include <time.h>
#include <unistd.h>
#include <getopt.h>
#include <libgen.h> // for basename()

#include "../fitsio.h"

#define FALLBACK_CCD_TEMP_VALUE 100
#define MAX_SET_TEMP_DIFF 0.5
#define MAX_CCD_TEMP_DIFF 3.0 // let's be generous

void check_and_remove_file( const char *filename ) {
 // Check if file exists by trying to access it
 if ( access( filename, F_OK ) == 0 ) {
  // File exists, try to remove it
  if ( unlink( filename ) == 0 ) {
   fprintf( stderr, "WARNING: existing file %s was deleted\n", filename );
   return; // Success
  } else {
   fprintf( stderr, "ERROR: could not delete existing file %s\n", filename );
   return; // Deletion failed
  }
 }
 return; // File didn't exist, no action needed
}

// This function will try to guess if the opened file is a dark frame or bias frame based on its header
int is_bias_frame( fitsfile *fptr ) {
 char imagetyp[FLEN_VALUE];
 int status= 0;
 double exposure= 0.0;

 // First, try to read IMAGETYP
 fits_read_key( fptr, TSTRING, "IMAGETYP", imagetyp, NULL, &status );
 if ( status == 0 ) {
  // Trim leading and trailing whitespace
  char *start= imagetyp;
  char *end= imagetyp + strlen( imagetyp ) - 1;

  while ( *start == ' ' || *start == '\t' )
   start++;
  while ( end > start && ( *end == ' ' || *end == '\t' ) )
   end--;

  *( end + 1 )= '\0';

  // Case-insensitive comparison
  if ( strcasecmp( start, "Bias Frame" ) == 0 ) {
   return 1;
  }
 }

 // Reset status
 status= 0;

 // If IMAGETYP is not found or not "Bias Frame", check exposure time
 fits_read_key( fptr, TDOUBLE, "EXPTIME", &exposure, NULL, &status );
 if ( status == KEY_NO_EXIST ) {
  status= 0;
  fits_read_key( fptr, TDOUBLE, "EXPOSURE", &exposure, NULL, &status );
 }

 if ( status == 0 && exposure == 0.0 ) {
  return 1; // This is a bias frame (exposure time is 0)
 }

 status= 0; // Reset status if EXPOSURE key was not found
 return 0;  // Not a bias frame
}

// This function will check if a record indicates the image has already been calibrated
int check_history_keywords( char *record ) {
 if ( strstr( record, "HISTORY Dark frame subtraction:" ) != NULL ||
      strstr( record, "HISTORY Flat fielding:" ) != NULL ) {
  return 1; // Match found
 }
 return 0; // No match found
}

void print_usage( char *program_name ) {
 fprintf( stderr, "Usage: %s [-h] [-f] image.fit dark.fit result.fit\n", program_name );
 fprintf( stderr, "Options:\n" );
 fprintf( stderr, "  -h  Print this help message\n" );
 fprintf( stderr, "  -f  Force processing (disable history keyword check)\n" );
}

int main( int argc, char *argv[] ) {
 int opt;
 int force_processing= 0;

 char *input_file= argv[optind];
 char *dark_file= argv[optind + 1];
 char *output_file= argv[optind + 2];

 fitsfile *fptr; // pointer to the FITS file; defined in fitsio.h
 long fpixel= 1;
 long naxes[2];
 long testX, testY;
 long img_size;

 int status= 0;
 int anynul= 0;
 unsigned short nullval= 0;
 unsigned short *image_array;
 unsigned short *dark_array;
 unsigned short *result_image_array;

 int i;
 int bitpix2;
 char **key;
 int No_of_keys;
 int keys_left;
 int ii, j; // counters

 double tmp;

 double set_temp_image, set_temp_dark;
 double ccd_temp_image, ccd_temp_dark;

 double image_mean, dark_mean;

 int is_bias= 0; // 1 - if it's a bias rather than dark frame (needed just to name it properly)

 while ( ( opt= getopt( argc, argv, "hf" ) ) != -1 ) {
  switch ( opt ) {
  case 'h':
   print_usage( argv[0] );
   exit( EXIT_SUCCESS );
  case 'f':
   force_processing= 1;
   break;
  default:
   fprintf( stderr, "Unknown option: %c\n", opt );
   print_usage( argv[0] );
   exit( EXIT_FAILURE );
  }
 }

 if ( argc - optind != 3 ) {
  fprintf( stderr, "Wrong arguments amount... :(\n" );
  print_usage( argv[0] );
  exit( EXIT_FAILURE );
 }

 fprintf( stderr, "Exploring image header: %s \n", input_file );
 fits_open_file( &fptr, input_file, 0, &status );
 fits_report_error( stderr, status ); // print out any error messages
 if ( status != 0 ) {
  exit( status );
 }
 fits_read_key( fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status );
 fits_report_error( stderr, status ); // print out any error messages
 if ( status != 0 ) {
  exit( status );
 }
 fits_read_key( fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status );
 fits_report_error( stderr, status ); // print out any error messages
 if ( status != 0 ) {
  exit( status );
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
  fprintf( stderr, "CCD-TEMP= %lf for %s\n", ccd_temp_image, input_file );
  fprintf( stderr, "SET-TEMP= %lf for %s\n", set_temp_image, input_file );
  if ( fabs( ccd_temp_image - set_temp_image ) > MAX_CCD_TEMP_DIFF ) {
   // found set temperature mismatch
   // basename() may mess the input string - use it just befor exit
   fprintf( stderr, "ERROR: mismatch between CCD-TEMP= %.1lf and SET-TEMP= %.1lf in %s! Looks like the the camera didn't have time to cool down.\n", ccd_temp_image, set_temp_image, basename( input_file ) );
   fits_close_file( fptr, &status );
   exit( EXIT_FAILURE );
  }
 }
 //
 //
 fits_get_hdrspace( fptr, &No_of_keys, &keys_left, &status );
 fprintf( stderr, "Header: %d keys total, %d keys left\n", No_of_keys, keys_left );
 // !!!!!!!!!!! Not sure why, but this is clearly needed in order not to loose the last key !!!!!!!!!!!
 No_of_keys++;
 // !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
 key= malloc( No_of_keys * sizeof( char * ) );
 if ( key == NULL ) {
  fprintf( stderr, "ERROR in %s: Couldn't allocate memory for FITS header\n", argv[0] );
  exit( EXIT_FAILURE );
 }
 for ( ii= 0; ii < No_of_keys; ii++ ) {
  key[ii]= malloc( FLEN_CARD * sizeof( char ) ); // FLEN_CARD length of a FITS header card defined in fitsio.h
  if ( key[ii] == NULL ) {
   fprintf( stderr, "ERROR in %s: Couldn't allocate memory for FITS header\n", argv[0] );
   exit( EXIT_FAILURE );
  }
  fits_read_record( fptr, ii, key[ii], &status );
  fprintf( stderr, "Record %d: \"%s\" status=%d\n", ii, key[ii], status );
  fits_report_error( stderr, status ); // print out any error messages

  // Check if the FITS header record indicates the image has already been calibrated
  if ( !force_processing && check_history_keywords( key[ii] ) ) {
   fprintf( stderr, "Prohibited HISTORY keyword found in header, exiting...\n" );
   fprintf( stderr, "Use -f option to force processing if you want to proceed anyway.\n" );
   fits_close_file( fptr, &status ); // Close the FITS file
   // Free allocated memory
   for ( j= 0; j <= ii; j++ ) {
    free( key[j] );
   }
   free( key );
   exit( EXIT_FAILURE ); // Exit the program
  }

  status= 0; // continue on any errors at this stage
 }

 fits_get_img_type( fptr, &bitpix2, &status );
 fits_report_error( stderr, status ); // print out any error messages
 if ( status != 0 ) {
  exit( status );
 }

 fprintf( stderr, "Allocating memory for image, dark and result arrays...\n" );
 img_size= naxes[0] * naxes[1];
 if ( img_size <= 0 ) {
  fprintf( stderr, "ERROR in %s: Trying allocate negative or zero bytes of memory\n", argv[0] );
  fits_close_file( fptr, &status );
  exit( EXIT_FAILURE );
 };
 image_array= malloc( img_size * sizeof( short ) );
 if ( image_array == NULL ) {
  fprintf( stderr, "ERROR in %s: Can't allocate memory for image_array\n", argv[0] );
  fits_close_file( fptr, &status );
  exit( EXIT_FAILURE );
 };
 dark_array= malloc( img_size * sizeof( short ) );
 if ( dark_array == NULL ) {
  fprintf( stderr, "ERROR in %s: Can't allocate memory for dark_array\n", argv[0] );
  free( image_array );
  fits_close_file( fptr, &status );
  exit( EXIT_FAILURE );
 };
 result_image_array= malloc( img_size * sizeof( short ) );
 if ( result_image_array == NULL ) {
  fprintf( stderr, "ERROR in %s: Can't allocate memory for result_image_array()\n", argv[0] );
  free( image_array );
  free( dark_array );
  fits_close_file( fptr, &status );
  exit( EXIT_FAILURE );
 };

 fits_read_img( fptr, TUSHORT, 1, img_size, &nullval, image_array, &anynul, &status );
 fprintf( stderr, "Reading image %s %ld %ld  %d bitpix\n", input_file, naxes[0], naxes[1], bitpix2 );
 fits_close_file( fptr, &status );
 fits_report_error( stderr, status ); // print out any error messages
 status= 0;

 fits_open_file( &fptr, dark_file, 0, &status );
 fits_report_error( stderr, status ); // print out any error messages
 if ( status != 0 ) {
  fprintf( stderr, "ERROR: opening dark frame %s\n", basename( dark_file ) );
  free( image_array );
  free( dark_array );
  free( result_image_array );
  fits_close_file( fptr, &status );
  exit( status );
 }
 fits_read_key( fptr, TLONG, "NAXIS1", &testX, NULL, &status );
 fits_report_error( stderr, status ); // print out any error messages
 if ( status != 0 ) {
  fprintf( stderr, "ERROR: getting NAXIS1 from dark frame %s\n", basename( dark_file ) );
  free( image_array );
  free( dark_array );
  free( result_image_array );
  fits_close_file( fptr, &status );
  exit( status );
 }
 fits_read_key( fptr, TLONG, "NAXIS2", &testY, NULL, &status );
 fits_report_error( stderr, status ); // print out any error messages
 if ( status != 0 ) {
  fprintf( stderr, "ERROR: getting NAXIS2 from dark frame %s\n", basename( dark_file ) );
  free( image_array );
  free( dark_array );
  free( result_image_array );
  fits_close_file( fptr, &status );
  exit( status );
 }
 if ( testX != naxes[0] || testY != naxes[1] ) {
  // basename() may mess the input string - use it just befor exit
  fprintf( stderr, "ERROR: Image frame (%s) and dark frame (%s) must have the same dimensions!\n", basename( input_file ), basename( dark_file ) );
  free( image_array );
  free( dark_array );
  free( result_image_array );
  fits_close_file( fptr, &status );
  exit( EXIT_FAILURE );
 }
 // Note the set temperature of the camera
 fits_read_key( fptr, TDOUBLE, "SET-TEMP", &set_temp_dark, NULL, &status );
 if ( status != 0 ) {
  set_temp_dark= FALLBACK_CCD_TEMP_VALUE;
  status= 0;
 }
 // Check the temperature match between the light and dark frames
 if ( set_temp_image != FALLBACK_CCD_TEMP_VALUE && set_temp_dark != FALLBACK_CCD_TEMP_VALUE ) {
  fprintf( stderr, "SET-TEMP= %lf for %s\n", set_temp_image, input_file );
  fprintf( stderr, "SET-TEMP= %lf for %s\n", set_temp_dark, dark_file );
  if ( fabs( set_temp_image - set_temp_dark ) > MAX_SET_TEMP_DIFF ) {
   // found set temperature mismatch
   // basename() may mess the input string - use it just befor exit
   fprintf( stderr, "ERROR: SET-TEMP temperature mismatch between the light (%s) and dark (%s) images!\n", basename( input_file ), basename( dark_file ) );
   free( image_array );
   free( dark_array );
   free( result_image_array );
   fits_close_file( fptr, &status );
   exit( EXIT_FAILURE );
  }
 }
 //
 // Note the ccd temperature of the camera
 fits_read_key( fptr, TDOUBLE, "CCD-TEMP", &ccd_temp_dark, NULL, &status );
 if ( status != 0 ) {
  ccd_temp_dark= FALLBACK_CCD_TEMP_VALUE;
  status= 0;
 }
 // Check the temperature match between the light and dark frames
 if ( ccd_temp_image != FALLBACK_CCD_TEMP_VALUE && ccd_temp_dark != FALLBACK_CCD_TEMP_VALUE ) {
  fprintf( stderr, "CCD-TEMP= %lf for %s\n", ccd_temp_image, input_file );
  fprintf( stderr, "CCD-TEMP= %lf for %s\n", ccd_temp_dark, dark_file );
  if ( fabs( ccd_temp_image - ccd_temp_dark ) > MAX_CCD_TEMP_DIFF ) {
   // found set temperature mismatch
   // basename() may mess the input string - use it just befor exit
   fprintf( stderr, "ERROR: CCD-TEMP temperature mismatch between the light (%.1lf; %s) and dark (%.1lf; %s) images!\n", ccd_temp_image, basename( input_file ), ccd_temp_dark, basename( dark_file ) );
   free( image_array );
   free( dark_array );
   free( result_image_array );
   fits_close_file( fptr, &status );
   exit( EXIT_FAILURE );
  }
 }
 //
 is_bias= is_bias_frame( fptr );
 //
 fits_get_img_type( fptr, &bitpix2, &status );
 fits_read_img( fptr, TUSHORT, 1, img_size, &nullval, dark_array, &anynul, &status );
 fprintf( stderr, "Reading dark frame %s %ld %ld  %d bitpix\n", dark_file, testX, testY, bitpix2 );
 fits_close_file( fptr, &status );
 fits_report_error( stderr, status ); // print out any error messages
 status= 0;

 // Calculate means while we have both arrays in memory
 image_mean= 0.0;
 dark_mean= 0.0;
 for ( i= 0; i < img_size; i++ ) {
  image_mean+= (double)image_array[i];
  dark_mean+= (double)dark_array[i];
 }
 image_mean/= (double)img_size;
 dark_mean/= (double)img_size;

 // Check if dark frame mean is greater than image mean
 if ( dark_mean >= image_mean ) {
  // basename may mess the input string - use it just befor exit
  fprintf( stderr, "ERROR: The mean value of the dark frame %s (%.2f) is greater than or equal to image mean (%.2f) for %s\n", basename( dark_file ), dark_mean, image_mean, basename( input_file ) );
  free( image_array );
  free( dark_array );
  free( result_image_array );
  for ( ii= 0; ii < No_of_keys; ii++ ) {
   free( key[ii] );
  }
  free( key );
  exit( EXIT_FAILURE );
 }

 // Perform dark subtraction
 for ( i= 0; i < img_size; i++ ) {
  // Try to avoid messing up overscan region
  // but is it actually safe for the rest of the image?
  if ( dark_array[i] < image_array[i] ) {
   tmp= (double)image_array[i] - (double)dark_array[i];
  } else {
   tmp= (double)dark_array[i] - (double)image_array[i];
  }
  // the output image will be of 'unsigned short' type, so force the pixel values to be in that range
  if ( tmp <= 0.0 ) {
   tmp= 1.0; // we want to avoid 0 pixels in order not to confuse the VaST flag image creator
  }
  if ( tmp > 65534.0 ) {
   tmp= 65534.5;
  }
  // Preserve saturated pixels
  if ( image_array[i] == 65535 ) {
   tmp= 65534.5;
  }
  //
  result_image_array[i]= (unsigned short)( tmp + 0.5 );
  // if ( result_image_array[i]>65000 )
  //  result_image_array[i]=65535;
 }
 free( image_array );
 free( dark_array );

 check_and_remove_file( output_file );
 fits_create_file( &fptr, output_file, &status ); // create new file
 fits_report_error( stderr, status );             // print out any error messages
 if ( status != 0 ) {
  // free-up memory before exiting
  free( result_image_array );
  for ( ii= 0; ii < No_of_keys; ii++ ) {
   free( key[ii] );
  }
  free( key );
  //
  return 1;
 }
 fits_create_img( fptr, USHORT_IMG, 2, naxes, &status );
 fits_report_error( stderr, status ); // print out any error messages
 if ( status != 0 ) {
  // free-up memory before exiting
  free( result_image_array );
  for ( ii= 0; ii < No_of_keys; ii++ ) {
   free( key[ii] );
  }
  free( key );
  //
  return 1;
 }
 fits_write_img( fptr, TUSHORT, fpixel, img_size, result_image_array, &status );
 fits_report_error( stderr, status ); // print out any error messages
 if ( status != 0 ) {
  // free-up memory before exiting
  free( result_image_array );
  for ( ii= 0; ii < No_of_keys; ii++ ) {
   free( key[ii] );
  }
  free( key );
  //
  return 1;
 }
 // Write the FITS header
 for ( ii= 1; ii < No_of_keys; ii++ ) {
  // for ( ii= 0; ii < No_of_keys; ii++ ) {
  fits_write_record( fptr, key[ii], &status );
 }

 // Remove duplicate keys
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
 // fits_write_history( fptr, "Dark frame subtraction:", &status );
 if ( 1 == is_bias ) {
  fits_write_history( fptr, "Bias frame subtraction:", &status );
 } else {
  fits_write_history( fptr, "Dark frame subtraction:", &status );
 }
 fits_report_error( stderr, status ); // print out any error messages
 status= 0;
 fits_write_history( fptr, input_file, &status );
 fits_report_error( stderr, status ); // print out any error messages
 status= 0;
 fits_write_history( fptr, dark_file, &status );
 fits_report_error( stderr, status ); // print out any error messages
 status= 0;                           // just in case
 fits_close_file( fptr, &status );
 fits_report_error( stderr, status ); // print out any error messages
 if ( status != 0 ) {
  // free-up memory before exiting
  free( result_image_array );
  for ( ii= 0; ii < No_of_keys; ii++ ) {
   free( key[ii] );
  }
  free( key );
  //
  return 1;
 }

 // fprintf( stderr, "Dark frame is subtracted, output is written to %s :)\n\n", output_file );
 if ( is_bias ) {
  fprintf( stderr, "Bias frame is subtracted, output is written to %s :)\n\n", output_file );
 } else {
  fprintf( stderr, "Dark frame is subtracted, output is written to %s :)\n\n", output_file );
 }
 fprintf( stdout, "Spent %f seconds \n", 1.0 * clock() / CLOCKS_PER_SEC );

 free( result_image_array );

 for ( ii= 0; ii < No_of_keys; ii++ ) {
  free( key[ii] );
 }
 free( key );

 fits_report_error( stderr, status ); // print out any error messages
 if ( status != 0 ) {
  fprintf( stderr, "ERROR modifying the file %s\n", output_file );
  return 1;
 }

 return 0;
}
