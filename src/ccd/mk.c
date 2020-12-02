#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h> // for unlink()
#include <gsl/gsl_sort.h>
#include <gsl/gsl_statistics.h>

#include "../fitsio.h"

#include "../vast_limits.h"

char *beztochki(char *);

int main(int argc, char *argv[]) {
 // Varaibles for FITS file reading
 fitsfile *fptr; // pointer to the FITS file; defined in fitsio.h
 long fpixel= 1;
 long naxes[2];
 long naxes_ref[2];

 int status= 0;
 int anynul= 0;
 unsigned short nullval= 0;
 //unsigned short *image_array[MAX_NUMBER_OF_OBSERVATIONS];
 unsigned short **image_array;
 unsigned short *combined_array;
 double y[MAX_NUMBER_OF_OBSERVATIONS];
 double *yy;
 double val;
 double ref_index, cur_index;
 int i;
 int bitpix2;
 int file_counter;
 int good_file_counter;
 // These variables are needed to keep FITS header keys
 char **key;
 int No_of_keys;
 int keys_left;
 int ii;
 long bzero= 0;
 char bzero_comment[80];
 int bzero_key_found= 0;

 FILE *filedescriptor_for_opening_test;

 fprintf(stderr, "Median combiner v2.1\n\n");
 fprintf(stderr, "Combining %d files\n", argc - 1);
 if( argc < 3 ) {
  fprintf(stderr, "Not enough arguments...\n  Usage: %s flat01.fit flat02.fit flat03.fit ...\n", argv[0]);
  exit(1);
 }

 // Allocate combined array
 fits_open_file(&fptr, argv[1], 0, &status);
 fits_read_key(fptr, TLONG, "NAXIS1", &naxes_ref[0], NULL, &status);
 fits_read_key(fptr, TLONG, "NAXIS2", &naxes_ref[1], NULL, &status);
 fits_get_hdrspace(fptr, &No_of_keys, &keys_left, &status);
 key= malloc(No_of_keys * sizeof(char *));
 if( key == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for FITS header\n");
  exit(1);
 }
 for( ii= 1; ii < No_of_keys; ii++ ) {
  key[ii]= malloc(FLEN_CARD * sizeof(char)); // FLEN_CARD length of a FITS header card defined in fitsio.h
  if( key[ii] == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for key[ii]\n");
   exit(1);
  }
  //fprintf( stderr, "DEBUG: ii=%d No_of_keys=%d FLEN_CARD=%d\n", ii, No_of_keys, FLEN_CARD );
  fits_read_record(fptr, ii, key[ii], &status);
 }
 fits_read_key(fptr, TLONG, "BZERO", &bzero, bzero_comment, &status);
 if( status != 0 ) {
  status= 0;
  bzero_key_found= 0;
 } else {
  bzero_key_found= 1;
 }
 fits_close_file(fptr, &status);
 fits_report_error(stderr, status); // print out any error messages

 long img_size= naxes_ref[0] * naxes_ref[1];
 if( img_size <= 0 ) {
  fprintf(stderr, "ERROR: The image size cannot be negative\n");
  exit(1);
 }
 combined_array= malloc(img_size * sizeof(short));
 if( combined_array == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for combined_array\n");
  exit(1);
 }
 //

 image_array= malloc( sizeof(unsigned short) );

 // Reading the input files
 for( file_counter= 1; file_counter < argc; file_counter++ ) {
  fits_open_file(&fptr, argv[file_counter], 0, &status);
  fits_read_key(fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status);
  fits_read_key(fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status);
  if( naxes_ref[0] != naxes[0] || naxes_ref[1] != naxes[1] ) {
   fprintf(stderr, "ERROR: image size mismatch %ldx%ld for %s vs. %ldx%ld for %s\n", naxes[0], naxes[1], argv[file_counter], naxes_ref[0], naxes_ref[1], argv[1]);
   exit(1);
  }
  // Allocate memory for the input images
  image_array= realloc(image_array, file_counter * sizeof(unsigned short *));
  image_array[file_counter-1]= malloc(img_size * sizeof(unsigned short));
  if( image_array[file_counter-1] == NULL ) {
   fprintf(stderr, "Error: Couldn't allocate memory for image array\n Current image: %s\n", argv[file_counter]);
   exit(1);
  }

  // Reading FITS header keywords from the first image we'll need to remember

  fits_get_img_type(fptr, &bitpix2, &status);
  fprintf(stderr, "Reading %s %ld %ld  %d bitpix\n", argv[file_counter], naxes[0], naxes[1], bitpix2);
  if( bitpix2 != SHORT_IMG ) {
   fprintf(stderr, "ERROR: BITPIX = %d.  Only SHORT_IMG (BITPIX = %d) images are currently supported.\n", bitpix2, SHORT_IMG);
   exit(1);
  }
  fits_read_img(fptr, TUSHORT, 1, naxes[0] * naxes[1], &nullval, image_array[file_counter-1], &anynul, &status);
  fits_close_file(fptr, &status);
  fits_report_error(stderr, status); // print out any error messages
  if( status != 0 ) {
   exit(1);
  }
  //fprintf(stderr,"DEBUUG: file_counter=%d\n",file_counter);
 }

 yy= malloc(img_size * sizeof(double));
 if( yy == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for yy array\n");
  exit(1);
 };
 /*
 // Scale everyting to the first image
 for ( i= 0; i < img_size; i++ ) {
  yy[i]= (double)image_array[1][i];
  //  fprintf(stderr,"%lf %d\n",yy[i],i);
 }
*/

/*
 // Scale everyting to the LAST image
 for( i= 0; i < img_size; i++ ) {
  yy[i]= (double)image_array[file_counter - 1][i];
  //  fprintf(stderr,"%lf %d\n",yy[i],i);
 }
 gsl_sort(yy, 1, img_size);
 ref_index= gsl_stats_median_from_sorted_data(yy, 1, img_size);
 fprintf(stderr, "ref_index=%lf\n", ref_index);
*/
 good_file_counter= 0;
 for( file_counter= 1; file_counter < argc; file_counter++ ) {
  for( i= 0; i < img_size; i++ ) {
   yy[i]= image_array[file_counter-1][i];
  }
  gsl_sort(yy, 1, img_size);
  cur_index= gsl_stats_median_from_sorted_data(yy, 1, img_size);
  fprintf(stderr, "cur_index=%lf\n", cur_index);

  // Reject obviously bad images from the flat-field stack

  if( 20000 > cur_index || cur_index > 50000 ) {
   fprintf(stderr, "REJECT\n", cur_index);
   continue; // continue here so good_file_counter does not increase
  }

  if( good_file_counter == 0 ) {
   ref_index=cur_index;
   fprintf(stderr, "ref_index=%lf\n", ref_index);
  }

  for( ii= 0; ii < img_size; ii++ ) {
   //image_array[file_counter][ii]= image_array[file_counter][ii] * ref_index / cur_index;
   image_array[good_file_counter][ii]= image_array[file_counter-1][ii] * ref_index / cur_index;
  }
  good_file_counter++;
 }
 free(yy);

 //
 for( i= 0; i < img_size; i++ ) {
  //for( file_counter= 1; file_counter < argc; file_counter++ ) {
  for( file_counter= 0; file_counter < good_file_counter; file_counter++ ) {
   y[file_counter]= image_array[file_counter][i];
   //fprintf(stderr,"%d %lf\n", file_counter, y[file_counter]);
  }
  //gsl_sort(y, 1, argc - 1);
  gsl_sort(y, 1, good_file_counter);
  //val= gsl_stats_median_from_sorted_data(y, 1, argc - 1);
  val= gsl_stats_median_from_sorted_data(y, 1, good_file_counter);
  //  fprintf(stderr,"median %lf\n",val);
  combined_array[i]= (unsigned short)(val + 0.5);
  //fprintf(stderr, "median = %lf _ %d\n ", val, combined_array[i]);
  //exit( 1 );
 }

 // Write the output FITS file
 // (DELETE the file with this name if it already exists)
 filedescriptor_for_opening_test= fopen("median.fit", "r");
 if( NULL != filedescriptor_for_opening_test ) {
  fprintf(stderr, "WARNING: removing the output file from the previous run: median.fit\n");
  fclose(filedescriptor_for_opening_test);
  unlink("median.fit");
 }
 fits_create_file(&fptr, "median.fit", &status); /* create new file */
 fits_create_img(fptr, USHORT_IMG, 2, naxes, &status);
 fits_write_img(fptr, TUSHORT, fpixel, img_size, combined_array, &status);
 free(combined_array);

 // Write the FITS header
 for( ii= 1; ii < No_of_keys; ii++ ) {
  fits_write_record(fptr, key[ii], &status);
 }
 // Delete the following keywords to avoid duplication
 fits_delete_key(fptr, "SIMPLE", &status);
 fits_delete_key(fptr, "BITPIX", &status);
 fits_delete_key(fptr, "NAXIS", &status);
 fits_delete_key(fptr, "NAXIS1", &status);
 fits_delete_key(fptr, "NAXIS2", &status);
 fits_delete_key(fptr, "EXTEND", &status);
 fits_delete_key(fptr, "COMMENT", &status);
 fits_delete_key(fptr, "COMMENT", &status);
 fits_delete_key(fptr, "BZERO", &status);
 fits_delete_key(fptr, "BSCALE", &status);

 if( bzero_key_found == 1 ) {
  fits_write_key(fptr, TLONG, "BZERO", &bzero, bzero_comment, &status);
 }

 for( file_counter= 1; file_counter < argc; file_counter++ ) {
  fits_write_history(fptr, argv[file_counter], &status);
 }
 fits_report_error(stderr, status); /* print out any error messages */
 fits_close_file(fptr, &status);
 for( file_counter= 1; file_counter < argc; file_counter++ ) {
  free(image_array[file_counter-1]);
 }
 free(image_array);
 fprintf(stderr, "Writing output to median.fit \n");
 fits_report_error(stderr, status); /* print out any error messages */

 for( ii= 1; ii < No_of_keys; ii++ ) {
  free(key[ii]);
 }
 free(key);

 return status;
}
