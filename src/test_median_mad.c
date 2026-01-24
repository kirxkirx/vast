// Test program for median and MAD computation functions from variability_indexes.c
// This program reads values from stdin and computes statistics using the functions
// that are being tested, outputting results for comparison with util/colstat

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>

#include <gsl/gsl_statistics.h>
#include <gsl/gsl_sort.h>

#include "variability_indexes.h"

int isOnlyWhitespace_test( const char *str ) {
 while ( *str ) {
  if ( !isspace( (unsigned char)*str ) ) {
   return 0;
  }
  str++;
 }
 return 1;
}

int main() {
 double *x= NULL;
 double *x_copy= NULL;
 double *temp_pointer_for_realloc= NULL;
 int i= 0, j= 0;

 char str[2048];
 int str_len, str_is_good;

 // Results from different methods
 double median_gsl;           // GSL median from sorted data (reference)
 double median_quickselect;   // Our quickselect-based median
 double mad_gsl_sorted;       // MAD computed from sorted data using gsl_sort internally
 double mad_quickselect;      // MAD computed using quickselect
 double sigma_from_mad_gsl;   // sigma from MAD (sorted)
 double sigma_from_mad_qs;    // sigma from MAD (quickselect)

 fprintf( stderr, "Test program for median and MAD computation\n" );
 fprintf( stderr, "Enter a column of numbers:\n" );

 x= malloc( sizeof( double ) );

 if ( NULL == x ) {
  fprintf( stderr, "MEMORY ERROR\n" );
  return 1;
 }

 while ( NULL != fgets( str, 2048, stdin ) ) {
  str_is_good= 1;
  str[2048 - 1]= '\0';
  str_len= strlen( str );
  if ( str_len < 1 )
   continue;
  if ( str_len > 100 )
   continue;
  for ( j= 0; j < str_len; j++ ) {
   if ( str[j] == '#' ) {
    str_is_good= 0;
    break;
   }
   if ( str[j] == '%' ) {
    str_is_good= 0;
    break;
   }
   if ( str[j] == '/' ) {
    str_is_good= 0;
    break;
   }
   if ( 1 == isalpha( str[j] ) ) {
    str_is_good= 0;
    break;
   }
  }

  if ( 1 == isOnlyWhitespace_test( str ) ) {
   str_is_good= 0;
  }

  if ( str_is_good != 1 ) {
   continue;
  }
  x[i]= atof( str );
  i+= 1;
  temp_pointer_for_realloc= realloc( x, ( i + 1 ) * sizeof( double ) );
  if ( temp_pointer_for_realloc == NULL ) {
   fprintf( stderr, "MEMORY ERROR\n" );
   free( x );
   return 1;
  }
  x= temp_pointer_for_realloc;
 }

 fprintf( stderr, "-----------------------------------------------------\n" );
 fprintf( stdout, "N= %d\n", i );

 if ( i < 2 ) {
  fprintf( stderr, "Need at least 2 data points\n" );
  free( x );
  return 1;
 }

 // Make a copy of the unsorted data for quickselect-based functions
 x_copy= malloc( i * sizeof( double ) );
 if ( NULL == x_copy ) {
  fprintf( stderr, "MEMORY ERROR\n" );
  free( x );
  return 1;
 }
 memcpy( x_copy, x, i * sizeof( double ) );

 // Test 1: Compute median using quickselect (on unsorted data)
 median_quickselect= compute_median_of_usorted_array_without_changing_it( x, i );
 fprintf( stdout, "MEDIAN_QUICKSELECT= %.10lf\n", median_quickselect );

 // Test 2: Compute sigma from MAD using quickselect (on unsorted data)
 sigma_from_mad_qs= esimate_sigma_from_MAD_of_unsorted_data( x_copy, i );
 fprintf( stdout, "SIGMA_MAD_QUICKSELECT= %.10lf\n", sigma_from_mad_qs );
 // MAD = sigma / 1.48260221850560
 mad_quickselect= sigma_from_mad_qs / 1.48260221850560;
 fprintf( stdout, "MAD_QUICKSELECT= %.10lf\n", mad_quickselect );

 // Now sort the original data for GSL-based reference computation
 gsl_sort( x, 1, i );

 // Test 3: GSL median from sorted data (reference)
 median_gsl= gsl_stats_median_from_sorted_data( x, 1, i );
 fprintf( stdout, "MEDIAN_GSL= %.10lf\n", median_gsl );

 // Test 4: MAD from sorted data (uses gsl_sort internally)
 mad_gsl_sorted= compute_MAD_of_sorted_data( x, i );
 fprintf( stdout, "MAD_GSL_SORTED= %.10lf\n", mad_gsl_sorted );
 sigma_from_mad_gsl= 1.48260221850560 * mad_gsl_sorted;
 fprintf( stdout, "SIGMA_MAD_GSL_SORTED= %.10lf\n", sigma_from_mad_gsl );

 // Summary comparison
 fprintf( stderr, "-----------------------------------------------------\n" );
 fprintf( stderr, "COMPARISON:\n" );
 fprintf( stderr, "  Median (GSL reference):    %.10lf\n", median_gsl );
 fprintf( stderr, "  Median (quickselect):      %.10lf\n", median_quickselect );
 fprintf( stderr, "  Median difference:         %.10e\n", fabs( median_gsl - median_quickselect ) );
 fprintf( stderr, "\n" );
 fprintf( stderr, "  MAD (GSL sorted):          %.10lf\n", mad_gsl_sorted );
 fprintf( stderr, "  MAD (quickselect):         %.10lf\n", mad_quickselect );
 fprintf( stderr, "  MAD difference:            %.10e\n", fabs( mad_gsl_sorted - mad_quickselect ) );

 // Check if values match
 if ( fabs( median_gsl - median_quickselect ) > 1e-10 ) {
  fprintf( stderr, "\nWARNING: Median values do not match!\n" );
 }
 if ( fabs( mad_gsl_sorted - mad_quickselect ) > 1e-10 ) {
  fprintf( stderr, "\nWARNING: MAD values do not match!\n" );
 }

 free( x );
 free( x_copy );

 return 0;
}
