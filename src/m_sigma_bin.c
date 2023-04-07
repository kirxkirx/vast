/*
   This program should identify stars with large sigma.
 */

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_spline.h>
#include <gsl/gsl_statistics.h>
#include <gsl/gsl_errno.h>

#include "vast_limits.h"

#include "variability_indexes.h"

#include "detailed_error_messages.h"

int main() {
 FILE *sigma_selection_curve_log;
 FILE *dmsf;
 double m, sigma, X, Y, mmax, mean;
 double *data_sigma;
 double *x_sigma;
 double *y;
 double *y_limit_sigma;
 y_limit_sigma= malloc( sizeof( double ) * MAX_NUMBER_OF_STARS );
 if ( y_limit_sigma == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for y_limit_sigma(m_sigma_bin.c)\n" );
  exit( EXIT_FAILURE );
 };
 x_sigma= malloc( sizeof( double ) * MAX_NUMBER_OF_STARS );
 if ( x_sigma == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for x_sigma(m_sigma_bin.c)\n" );
  exit( EXIT_FAILURE );
 };
 y= malloc( sizeof( double ) * MAX_NUMBER_OF_STARS );
 if ( y == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for y(m_sigma_bin.c)\n" );
  exit( EXIT_FAILURE );
 };
 data_sigma= malloc( sizeof( double ) * MAX_NUMBER_OF_STARS );
 if ( data_sigma == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for data_sigma(m_sigma_bin.c)\n" );
  exit( EXIT_FAILURE );
 };
 char str[256];
 int n= 0;
 int i= 0;
 int n_drop_high_sigma_stars;

 double *m_arr;

 int interpolation_status_gsl= 0;

 m_arr= malloc( sizeof( double ) * MAX_NUMBER_OF_STARS );
 if ( m_arr == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for m_arr(m_sigma_bin.c)\n" );
  exit( EXIT_FAILURE );
 };

 dmsf= fopen( "data.m_sigma", "r" );
 if ( dmsf == NULL ) {
  fprintf( stderr, "ERROR: Can't open file data.m_sigma !\n" );
  report_lightcurve_statistics_computation_problem();
  exit( EXIT_FAILURE );
 }

 i= 0;
 n= 0;
 mmax= 0.0;
 while ( -1 < fscanf( dmsf, "%lf %lf %lf %lf %s", &m, &sigma, &X, &Y, str ) ) {

  if ( mmax == 0.0 )
   mmax= m;

  if ( m <= mmax + M_SIGMA_BIN_SIZE_M || n < 12 ) {
   m_arr[n]= m;
   data_sigma[n]= sigma;
   n++;
  } else {
   gsl_sort2( data_sigma, 1, m_arr, 1, n );
   n_drop_high_sigma_stars= MAX( (int)( 0.07 * n ), M_SIGMA_BIN_DROP );
   if ( n > 2 * n_drop_high_sigma_stars + 2 )
    n-= 2 * n_drop_high_sigma_stars;
   else if ( n > n_drop_high_sigma_stars + 2 )
    n-= n_drop_high_sigma_stars;
   mean= gsl_stats_median_from_sorted_data( data_sigma, 1, n ); // gsl_stats_mean(data,1,n ); // would a median be more appropriate here?
   x_sigma[i]= gsl_stats_mean( m_arr, 1, n );
   y[i]= mean;
   y_limit_sigma[i]= gsl_stats_sd( data_sigma, 1, n );
   if ( 0 != isnan( y_limit_sigma[i] ) ) {
    y_limit_sigma[i]= 0;
   }
   y_limit_sigma[i]= y[i] + M_SIGMA_BIN_MAG_SIGMA_DETECT * y_limit_sigma[i]; // now this is the detection limit

   i++;
   n= 0;
   mmax= m;
  }
 }
 fclose( dmsf );

 free( m_arr );

 if ( i < 5 ) {
  fprintf( stderr, "ERROR: not enough bins (only %d) to construct the selection curve!\n", i );
  exit( EXIT_FAILURE );
 }

 gsl_set_error_handler_off(); // The function call to gsl_set_error_handler_off stops the default error handler from aborting the program.

 // Interpolate
 gsl_interp_accel *acc_sigma= gsl_interp_accel_alloc();
 gsl_spline *spline_sigma= gsl_spline_alloc( gsl_interp_akima, i );
 interpolation_status_gsl= gsl_spline_init( spline_sigma, x_sigma, y_limit_sigma, i );

 if ( interpolation_status_gsl != 0 ) {
  fprintf( stderr, "Interpolation error!\n" );
  exit( EXIT_FAILURE );
 }

 // Compute interpolating function and write it to file
 sigma_selection_curve_log= fopen( "vast_sigma_selection_curve.log", "w" );
 if ( sigma_selection_curve_log == NULL ) {
  fprintf( stderr, "ERROR: Can't open file vast_sigma_selection_curve.log for writing!\n" );
  exit( EXIT_FAILURE );
 }
 double xi, yi;
 for ( xi= x_sigma[0]; xi < x_sigma[i - 1]; xi+= 0.01 ) {
  yi= gsl_spline_eval( spline_sigma, xi, acc_sigma );
  fprintf( sigma_selection_curve_log, "%lf %lf\n", xi, yi );
 }
 fclose( sigma_selection_curve_log );

 // ---------------------------------------------------------------------------------------------

 // Write stars which pass the selection criteria to data.m_sigma file
 dmsf= fopen( "data.m_sigma", "r" );
 if ( dmsf == NULL ) {
  fprintf( stderr, "ERROR: Can't open file data.m_sigma for reading\n" );
  report_lightcurve_statistics_computation_problem();
  exit( EXIT_FAILURE );
 }
 while ( -1 < fscanf( dmsf, "%lf %lf %lf %lf %s", &m, &sigma, &X, &Y, str ) ) { // fprintf(stderr,"%lf %lf\n",m,sigma);
  // This should avoid "interpolation error" crash.
  if ( m < x_sigma[0] )
   m= x_sigma[0];
  if ( m > x_sigma[i - 1] )
   m= x_sigma[i - 1];
  // Compare the measured value with a limit
  if ( sigma >= gsl_spline_eval( spline_sigma, m, acc_sigma ) )
   fprintf( stdout, "%10.6lf %.6lf %9.3lf %9.3lf %s\n", m, sigma, X, Y, str );
  // New output to the files
  // if( sigma>gsl_spline_eval(spline_sigma, m, acc_sigma) && modified_sigma_series>gsl_spline_eval(spline_modified_sigma, m, acc_modified_sigma) && I>gsl_spline_eval(spline_I, m, acc_I) && L>gsl_spline_eval(spline_L, m, acc_L) )
  // fprintf(candidates_list,"%s\n",str);
 }
 // fclose(candidates_list);
 fclose( dmsf );

 //
 gsl_interp_accel_free( acc_sigma );
 gsl_spline_free( spline_sigma );
 //

 free( y_limit_sigma );
 free( x_sigma );
 free( y );
 free( data_sigma );

 return 0;
}
