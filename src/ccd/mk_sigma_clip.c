#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include <unistd.h> // for unlink()
#include <gsl/gsl_sort.h>
#include <gsl/gsl_statistics.h>

#include "../fitsio.h"

#include "../vast_limits.h"

//#define MIN_COUNT 15 //Это типа минимальный отсчёт, который мы считаем реальным.

char *beztochki( char * );

int main( int argc, char *argv[] ) {
 /* Для чтения фитсов */
 fitsfile *fptr; /* pointer to the FITS file; defined in fitsio.h */
 long fpixel= 1;
 long naxes[2];
 long img_size;

 int status= 0;
 int anynul= 0;
 unsigned short nullval= 0;
 unsigned short *image_array[MAX_NUMBER_OF_OBSERVATIONS];
 unsigned short *combined_array= NULL;
 double y[MAX_NUMBER_OF_OBSERVATIONS];
 double *yy;
 double val;
 double ref_index, cur_index;
 /* ----- */
 int i;
 int bitpix2;
 int counter; //Считаем файлы
 int uje= 0;
 /* -- Для хранения ключей из шапки -- */
 char *key[10000];
 int No_of_keys;
 int keys_left;
 int ii;
 long bzero= 0;

 char bzero_comment[80];

 double sigma; // for the sigma filter
 int nonzero_counts;

 FILE *file_read_test;

 fprintf( stderr, "Median combiner v1.2\n I'll not spoil any files...\n" );
 fprintf( stderr, "Combining %d files\n", argc - 1 );
 if ( argc < 3 ) {
  fprintf( stderr, "Not enough arguments...\n  Usage: ./mk flat01.fit flat02.fit flat03.fit ...\n" );
  exit( 1 );
 }

 /* Читаем файлы */
 for ( counter= 1; counter < argc; counter++ ) {
  fits_open_file( &fptr, argv[counter], 0, &status );
  fits_read_key( fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status );
  fits_read_key( fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status );
  /* Выделяем память под картинки */
  img_size= naxes[0] * naxes[1];
  if ( img_size <= 0 ) {
   fprintf( stderr, "ERROR: Trying allocate zero or negative bytes amount\n" );
   exit( 1 );
  };
  image_array[counter]= malloc( img_size * sizeof( short ) );
  if ( image_array == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for image_array\n" );
   exit( 1 );
  };
  if ( uje == 0 ) {
   combined_array= malloc( img_size * sizeof( short ) );
   if ( combined_array == NULL ) {
    fprintf( stderr, "ERROR: Couldn't allocate memory for combined_array\n" );
    exit( 1 );
   };
   uje= 1;
  }
  /* ---- */
  //Читаем из шапки то что стоит запомнить
  fits_get_hdrspace( fptr, &No_of_keys, &keys_left, &status );
  for ( ii= 1; ii < No_of_keys; ii++ ) {
   key[ii]= malloc( FLEN_CARD * sizeof( char ) ); // FLEN_CARD length of a FITS header card defined in fitsio.h
   if ( key[ii] == NULL ) {
    fprintf( stderr, "ERROR: Couldn't allocate memory for key[ii]\n" );
    exit( 1 );
   };
   fits_read_record( fptr, ii, key[ii], &status );
  }
  fits_read_key( fptr, TLONG, "BZERO", &bzero, bzero_comment, &status );
  //status=0;
  fits_get_img_type( fptr, &bitpix2, &status );
  fits_read_img( fptr, TUSHORT, 1, img_size, &nullval, image_array[counter], &anynul, &status );
  fprintf( stderr, "Reading %s %ld %ld  %d bitpix\n", argv[counter], naxes[0], naxes[1], bitpix2 );
  fits_close_file( fptr, &status );
  fits_report_error( stderr, status ); /* print out any error messages */
 }

 yy= malloc( img_size * sizeof( double ) );
 if ( yy == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for yy\n" );
  exit( 1 );
 };
 //Приводим всё к первому кадру
 for ( i= 0; i < img_size; i++ ) {
  yy[i]= (double)image_array[1][i];
  //  fprintf(stderr,"%lf %d\n",yy[i],i);
 }
 gsl_sort( yy, 1, img_size );
 ref_index= gsl_stats_median_from_sorted_data( yy, 1, img_size );
 fprintf( stderr, "ref_index=%lf\n", ref_index );
 for ( counter= 2; counter < argc; counter++ ) {
  for ( i= 0; i < img_size; i++ ) {
   yy[i]= image_array[counter][i];
  }
  gsl_sort( yy, 1, img_size );
  cur_index= gsl_stats_median_from_sorted_data( yy, 1, img_size );
  fprintf( stderr, "cur_index=%lf\n", cur_index );

  for ( ii= 0; ii < img_size; ii++ ) {
   image_array[counter][ii]= image_array[counter][ii] * ref_index / cur_index;
  }
  //  fprintf(stderr,"Привели картинку\n",cur_index);
 }

 //
 for ( i= 0; i < img_size; i++ ) {
  for ( counter= 1, nonzero_counts= 0; counter < argc; counter++ ) {
   if ( 0 != image_array[counter][i] ) {
    y[nonzero_counts]= image_array[counter][i];
    nonzero_counts++;
   }
   //   fprintf(stderr,"%lf\n",y[counter-1]);
  }
  gsl_sort( y, 1, argc - 1 );
  // !!! Sigma filter !!!
  //   ! Kills stars  !
  val= gsl_stats_median_from_sorted_data( y, 1, (int)( 0.5 * nonzero_counts ) );
  sigma= gsl_stats_sd( y, 1, (int)( 0.5 * nonzero_counts ) );
  //fprintf(stderr,"val=%lf sigma=%lf\n",val,sigma);
  for ( counter= 0; counter < nonzero_counts; counter++ ) {
   if ( y[counter] >= val + 1.0 * sigma )
    break;
  }
  val= gsl_stats_median_from_sorted_data( y, 1, counter );
  //  fprintf(stderr,"median %lf\n",val);
  combined_array[i]= (unsigned short)( val + 0.5 );
 }

 //пишем в файл
 //system("rm -f median.fit");
 file_read_test= fopen( "median.fit", "r" );
 if ( NULL != file_read_test ) {
  fclose( file_read_test );
  unlink( "median.fit" );
 }
 fits_create_file( &fptr, "median.fit", &status ); /* create new file */
 fits_create_img( fptr, USHORT_IMG, 2, naxes, &status );
 fits_write_img( fptr, TUSHORT, fpixel, img_size, combined_array, &status );

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

 fits_write_key( fptr, TLONG, "BZERO", &bzero, bzero_comment, &status );

 for ( counter= 1; counter < argc; counter++ ) {
  fits_write_history( fptr, argv[counter], &status );
 }
 fits_report_error( stderr, status ); /* print out any error messages */
 fits_close_file( fptr, &status );
 for ( counter= 1; counter < argc; counter++ ) {
  free( image_array[counter] );
 }
 fprintf( stderr, "Writing output to median.fit \n" );
 fits_report_error( stderr, status ); /* print out any error messages */
 return status;
}
