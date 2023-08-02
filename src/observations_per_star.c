#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_statistics.h>

#include "vast_limits.h"

int main() {
 DIR *dp;
 struct dirent *ep;

 FILE *data_m_sigma;
 double mmag, mmerr, mx, my;
 char outfilename[FILENAME_LENGTH];

 // initialize to 0.0 to make the compiler happy
 double mmean= 0.0;
 double mmedian= 0.0;
 double mmax= 0.0;
 double mmin= 0.0;

 int mnumber_of_stars= 0;

 FILE *lightcurvefile;

 double *a;
 a= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( a == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for array a(observations_per_star.c)\n" );
  exit( EXIT_FAILURE );
 };
 double mean;
 double median;
 double max;
 double min;

 int number_of_stars= 0;

 char str[2048];

 

 dp= opendir( "./" );
 if ( dp != NULL ) {
  fprintf( stderr, "Computing lightcurve statistics... " );

  while ( ( ep= readdir( dp ) ) != NULL ) {
   if ( strlen( ep->d_name ) < 12 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {
    lightcurvefile= fopen( ep->d_name, "r" );
    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     exit( EXIT_FAILURE );
    }
    a[number_of_stars]= 0.0;
    while ( NULL != fgets( str, 2048, lightcurvefile ) ) {
     a[number_of_stars]+= 1.0;
    }
    fclose( lightcurvefile );
    number_of_stars++;
   }
  }
  (void)closedir( dp );
 } else {
  perror( "Couldn't open the directory\n" );
 }
 
 if ( number_of_stars != 0 ) {

  mean= gsl_stats_mean( a, 1, number_of_stars );
  gsl_sort( a, 1, number_of_stars );
  median= gsl_stats_median_from_sorted_data( a, 1, number_of_stars );
  gsl_stats_minmax( &min, &max, a, 1, number_of_stars );

  data_m_sigma= fopen( "data.m_sigma", "r" );
  if ( data_m_sigma == NULL ) {
   // this will create data.m_sigma file among other things
   if ( 0 != system( "util/nopgplot.sh -q" ) ) {
    fprintf( stderr, "ERROR running  util/nopgplot.sh -q\n" );
   }
  } else {
   fclose( data_m_sigma );
  }

  mnumber_of_stars= 0;
  data_m_sigma= fopen( "data.m_sigma", "r" );
  if ( NULL != data_m_sigma ) {
   while ( -1 < fscanf( data_m_sigma, "%lf %lf %lf %lf %s", &mmag, &mmerr, &mx, &my, outfilename ) ) {
    lightcurvefile= fopen( outfilename, "r" );
    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", outfilename );
     exit( EXIT_FAILURE );
    }
    a[mnumber_of_stars]= 0.0;
    while ( NULL != fgets( str, 2048, lightcurvefile ) )
     a[mnumber_of_stars]+= 1.0;
    fclose( lightcurvefile );
    mnumber_of_stars++;
   }
   fclose( data_m_sigma );

   mmean= gsl_stats_mean( a, 1, mnumber_of_stars );
   gsl_sort( a, 1, mnumber_of_stars );
   mmedian= gsl_stats_median_from_sorted_data( a, 1, mnumber_of_stars );
   gsl_stats_minmax( &mmin, &mmax, a, 1, mnumber_of_stars );
  }

 } else {
  fprintf( stderr, "ERROR: no lightcurve files were produced.\n" );
  mnumber_of_stars= 0;
  mean= median= min= max= mmean= mmedian= mmin= mmax= 0.0;
 }

 free( a );

 fprintf( stdout, "Total objects detected (at least %d times):  %d\n", HARD_MIN_NUMBER_OF_POINTS, number_of_stars );
 fprintf( stdout, "Objects passed selection criteria:  %d\n", mnumber_of_stars );
 fprintf( stdout, "Measurements per detected object (mean, median, min, max): %6.1lf %6.1lf %4.0lf %4.0lf\n", mean, median, min, max );
 fprintf( stdout, "Measurements per selected object (mean, median, min, max): %6.1lf %6.1lf %4.0lf %4.0lf\n", mmean, mmedian, mmin, mmax );

 return 0;
}
