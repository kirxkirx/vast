#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
//#include <time.h> // time profiling

#include <gsl/gsl_statistics.h>
#include <gsl/gsl_sort.h>

#include "../fitsio.h"
#include "../vast_limits.h" // for MAX( A, B)

#define MIN_REAL_COUNT 5 // The minimum count assumed to be real. The default is 5

/*
unsigned short detect_overscan(float *image_array, long *naxes) {
 int i, j;
 int binsize= 15;
 double arr[1024];
 double median1= 65535;
 double median2= 0;
 double median;
 double sigma; // to detect if there are any overscan at all
 double sigma1= 0.0;
 unsigned short min_real_count_estimate;
 for( i= naxes[0] * naxes[1] / 2 + 0; i < naxes[0] * naxes[1] / 2 + naxes[0] - 2 * binsize; i++ ) {
  for( j= i; j < i + binsize; j++ ) {
   arr[j - i]= (double)image_array[j];
  }
  gsl_sort(arr, 1, binsize);
  median= gsl_stats_median_from_sorted_data(arr, 1, binsize);
  if( median < median1 )
   median1= median;
  sigma= gsl_stats_sd(arr, 1, binsize);
  if( sigma > sigma1 )
   sigma1= sigma;
  for( j= i + binsize; j < i + 2 * binsize; j++ )
   arr[j - i - binsize]= (double)image_array[j];
  gsl_sort(arr, 1, binsize);
  median= gsl_stats_median_from_sorted_data(arr, 1, binsize);
  if( median > median2 )
   median2= median;
 }
 fprintf(stderr, "median1=%lf median2=%lf fabs(median2-median1)=%lf>%lf=5*sigma1\n", median1, median2, fabs(median2 - median1), 5 * sigma1);
 min_real_count_estimate= (unsigned short)median1 + 10 * sqrt(median1);
 if( min_real_count_estimate < MIN_REAL_COUNT ) {
  min_real_count_estimate= MIN_REAL_COUNT;
  return min_real_count_estimate;
 }

 // sigma1 turns out to be a bad estimate of the background noise because of outliers
 if( fabs(median2 - median1) < 10 * sqrt(median1) ) {
  fprintf(stderr, "No overscan found!\n");

  min_real_count_estimate= MIN_REAL_COUNT; /// ZATYCHKA!!!!!!!!!!!!!!!!11
  return min_real_count_estimate;
 }
 fprintf(stderr, "Overscan detected!\n");
 return min_real_count_estimate;
}
*/

unsigned short detect_overscan2(float *image_array, long *naxes) {
 // Two main ideas of this alghorithm:
 //    * 1. Signal from overscan is lower than signal from image background
 //    * 2. Overscan zone located on the edge of the image
 //

 int i; // counter

 int posY= (int)(naxes[1] / 2 + 0.5);
 double *img_profile;

 if( naxes[0] <= 0 ) {
  fprintf(stderr, "ERROR in detect_overscan2(): invalid value of naxes[0]=%ld\n", naxes[0]);
  exit(1);
 }
 img_profile= malloc(naxes[0] * sizeof(double));
 if( NULL == img_profile ) {
  fprintf(stderr, "ERROR in detect_overscan2() while allocating memory for img_profile\n");
  exit(1);
 }

 // slicing row from the middle of the image
 for( i= posY * naxes[0]; i < posY * naxes[0] + naxes[0]; i++ ) {
  img_profile[i - posY * naxes[0]]= (double)image_array[i];
 }

 int binsize= 64;

 double left[binsize];
 double right[binsize];
 int right_ind= naxes[0] - 1; // index for right part
 for( i= 0; i < binsize; i++ ) {
  left[i]= img_profile[i];
  right[i]= img_profile[right_ind - i];
 }
 fprintf(stdout, "\n");

 free(img_profile);

 // sorting both parts of the image
 gsl_sort(left, 1, binsize);
 gsl_sort(right, 1, binsize);

 // calculating medians
 double left_median= gsl_stats_median_from_sorted_data(left, 1, binsize);
 double right_median= gsl_stats_median_from_sorted_data(right, 1, binsize);

 // do not test if the values seem high
 if( left_median > 5000 && right_median > 5000 ){
  fprintf(stdout, "No overscan detected - all values seem high!\n");
  return MIN_REAL_COUNT;
 }

 // getting median value of overscan
 double median= (left_median < right_median) ? left_median : right_median;
 if( fabs(left_median - right_median) < 10 * sqrt(median) ) {
  fprintf(stdout, "No overscan detected!\n");
  return MIN_REAL_COUNT;
 }
 //fprintf(stderr,"DEBUG: median=%lf left_median=%lf right_median=%lf",median,left_median,right_median);
 //unsigned short min_real_count_estimate= (unsigned short)( median + 10 * sqrt( median ) );
 median= (left_median > right_median) ? left_median : right_median;
 unsigned short min_real_count_estimate= (unsigned short)(median - 10 * sqrt(median));
 fprintf(stdout, "Overscan detected!\n");
 return MAX(min_real_count_estimate, MIN_REAL_COUNT);
}

int main(int argc, char *argv[]) {
 unsigned short min;
 /* Для чтения фитсов */
 fitsfile *fptr; /* pointer to the FITS file; defined in fitsio.h */
 long fpixel= 1;
 long naxes[2];
 long testX, testY;

 int status= 0;
 int anynul= 0;
 unsigned short nullval_ushort= 0;
 float nullval_float= 0.0;
 unsigned short *image_array;
 unsigned short *flat_array;
 float *float_flat_array;
 unsigned short *result_image_array;

 /* ----- */
 long i;
 int bitpix2;
 double tmp, norm;
 /* -- Для хранения ключей из шапки -- */
 //char *key[10000];
 char **key;
 int No_of_keys;
 int keys_left;
 long ii;

 double bzero= 32768.0;

 if( argc != 4 ) {
  fprintf(stderr, "Wrong number of arguments... :(\n  Usage: %s image.fit flat.fit result.fit\n", argv[0]);
  return 1;
 }
 fprintf(stderr, "MegaDivider v6\n");

 /* Читаем файл */
 fits_open_file(&fptr, argv[1], 0, &status);
 fits_report_error(stderr, status); /* print out any error messages */
 if( status != 0 )
  exit(status);
 fits_read_key(fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status);
 fits_report_error(stderr, status); /* print out any error messages */
 if( status != 0 )
  exit(status);
 fits_read_key(fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status);
 fits_report_error(stderr, status); /* print out any error messages */
 if( status != 0 )
  exit(status);
 //Читаем из шапки то что стоит запомнить
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
  };
  fits_read_record(fptr, ii, key[ii], &status);
 }
 fits_get_img_type(fptr, &bitpix2, &status);

 /* Выделяем память */
 int img_size= naxes[0] * naxes[1];
 if( img_size <= 0 ) {
  fprintf(stderr, "ERROR: negative or zero image size\n");
  exit(1);
 };
 image_array= malloc(img_size * sizeof(short));

 flat_array= malloc(img_size * sizeof(short));
 float_flat_array= malloc(img_size * sizeof(float));
 result_image_array= malloc(img_size * sizeof(short));
 /* И читаем картинку */
 fits_read_img(fptr, TUSHORT, 1, img_size, &nullval_ushort, image_array, &anynul, &status);
 fprintf(stderr, "Reading image %s %ld %ld  %d bitpix\n", argv[1], naxes[0], naxes[1], bitpix2);
 fits_close_file(fptr, &status);
 fits_report_error(stderr, status); /* print out any error messages */
 status= 0;

 /* Читаем дарк */
 fits_open_file(&fptr, argv[2], 0, &status);
 fits_report_error(stderr, status); /* print out any error messages */
 if( status != 0 )
  exit(status);
 fits_read_key(fptr, TLONG, "NAXIS1", &testX, NULL, &status);
 fits_report_error(stderr, status); /* print out any error messages */
 if( status != 0 )
  exit(status);
 fits_read_key(fptr, TLONG, "NAXIS2", &testY, NULL, &status);
 fits_report_error(stderr, status); /* print out any error messages */
 if( status != 0 )
  exit(status);
 if( testX != naxes[0] || testY != naxes[1] ) {
  fprintf(stderr, "Flat field and image must be the same size!\n");
  exit(1);
 }
 fits_get_img_type(fptr, &bitpix2, &status);
 fprintf(stderr, "Reading flat %s %ld %ld  %d bitpix\n", argv[2], testX, testY, bitpix2);
 // The following will handle only FLOAT and SHORT data types for the flat field file
 if( bitpix2 == FLOAT_IMG ) {
  fits_read_img(fptr, TFLOAT, 1, img_size, &nullval_float, float_flat_array, &anynul, &status);
 } else {
  fits_read_img(fptr, TUSHORT, 1, img_size, &nullval_ushort, flat_array, &anynul, &status);
  for( i= 0; i < naxes[0] * naxes[1]; i++ ) {
   float_flat_array[i]= (float)flat_array[i];
  }
 }
 fits_close_file(fptr, &status);
 fits_report_error(stderr, status); /* print out any error messages */
 status= 0;

 /* Считаем нормировочный коэффициент */
 norm= 0.0;
 for( i= 0; i < img_size; i++ )
  norm+= float_flat_array[i];

 norm= norm / img_size;
 fprintf(stderr, "Avarage count on flat field image: %lf\n", norm);

 // !!!
 //double time_start = clock() * 1.0f / CLOCKS_PER_SEC;
 //min=detect_overscan(float_flat_array, naxes);
 min= detect_overscan2(float_flat_array, naxes);
 //double spent_time = clock() * 1.0f / CLOCKS_PER_SEC - time_start;
 //min=0;
 fprintf(stderr, "Minimal real count (from overscan): %d\n", min);

 /* Делим на плоское поле */
 for( i= 0; i < naxes[0] * naxes[1]; i++ ) {
  //if( image_array[i] > min && float_flat_array[i] > min ){
  if( float_flat_array[i] > min ) {
   tmp= (double)(image_array[i]) / ((double)(float_flat_array[i]) + 0.0000001) * norm;
  } else {
   tmp= 0.0;
  }
  // never happens...
  //fprintf(stderr,"tmp=%lf\n",tmp);
  if( tmp > 65534.0 ) {
   //fprintf(stderr,"Numeric overflow at a saturated pixel! %lf\n",tmp);
   tmp= 65534.5; // so we get 65535 after rounding-up
  }
  result_image_array[i]= (unsigned short)(tmp + 0.5);
 }
 free(image_array);
 free(flat_array);
 free(float_flat_array);
 fits_create_file(&fptr, argv[3], &status); /* create new file */
 fits_report_error(stderr, status);         /* print out any error messages */
 if( status != 0 ) {
  fprintf(stderr, "Cannot create FITS file %s\n", argv[3]);
  exit(1);
 }
 fits_create_img(fptr, USHORT_IMG, 2, naxes, &status);
 fits_report_error(stderr, status); /* print out any error messages */
 if( status != 0 ) {
  fprintf(stderr, "Cannot create image\n");
  exit(1);
 }
 fits_write_img(fptr, TUSHORT, fpixel, naxes[0] * naxes[1], result_image_array, &status);
 fits_report_error(stderr, status); /* print out any error messages */
 if( status != 0 ) {
  fprintf(stderr, "Cannot write image\n");
  exit(1);
 }
 // Write header keys
 for( ii= 1; ii < No_of_keys; ii++ ) {
  fits_write_record(fptr, key[ii], &status);
 }
 fits_delete_key(fptr, "SIMPLE", &status);
 fits_delete_key(fptr, "BITPIX", &status);
 fits_delete_key(fptr, "NAXIS", &status);
 fits_delete_key(fptr, "NAXIS1", &status);
 fits_delete_key(fptr, "NAXIS2", &status);
 fits_delete_key(fptr, "EXTEND", &status);
 fits_delete_key(fptr, "COMMENT", &status);
 fits_delete_key(fptr, "COMMENT", &status);
 fits_delete_key(fptr, "BZERO", &status);
 // fits_write_key(fptr,TDOUBLE,"BZERO",&bzero," ",&status);
 fits_delete_key(fptr, "BSCALE", &status);
 fits_write_history(fptr, argv[1], &status);
 fits_write_history(fptr, argv[2], &status);
 fits_report_error(stderr, status); // print out any error messages
 status= 0;                         // just in case
 fits_close_file(fptr, &status);
 free(result_image_array);

 fits_open_file(&fptr, argv[3], READWRITE, &status);
 fits_update_key(fptr, TDOUBLE, "BZERO", &bzero, " ", &status);
 fits_close_file(fptr, &status);

 fprintf(stderr, "Output is written to %s :)\n\n", argv[3]);

 // fprintf(stdout,  "Overscan detection: %f seconds\n Total: %f seconds\n", spent_time, 1.0 * clock() / CLOCKS_PER_SEC);

 for( ii= 1; ii < No_of_keys; ii++ ) {
  free(key[ii]);
 }
 free(key);

 fits_report_error(stderr, status); // print out any error messages
 if( status != 0 ) {
  fprintf(stderr, "ERROR modyfying the file %s\n", argv[3]);
  return 1;
 }

 return 0;
}
