#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_statistics.h>

#include "vast_limits.h"   // for MIN()
#include "lightcurve_io.h" // for read_lightcurve_point()

/*
   Based on: http://adsabs.harvard.edu/abs/1956BAN....12..327K
*/

int main() {
 double T0= 0.0;
 double sigma_T0= 0.0;
 double T2= 0.0;
 double T3= 0.0;
 double A, B, C;
 int jdT1= 0;
 int n_delta_m= 0;
 double *delta_m= NULL;
 double sT1, sT2, sT3;
 double a, b;
 double best_d;
 int best_d_j;
 int n;
 double *interp_m= NULL;
 double *interp_jd= NULL;
 double dt;
 double T1= 0.0;
 double mT1= 0.0;
 int i, j;
 // double tmp_m, tmp_jd;
 double *jd= NULL;
 double *m= NULL;
 int n_points_lightcurve= 1;

 double mean_jd= 0; // Mean jd to be subtracted from the intput data before fitting to avoid problems

 double Z; // Z is the maximum number of independent magnitude pairs.
           // In the case of linear interpolation 0.25*N is recomended!

 double merr_not_used;

 /* Read data */
 do {
  jd= realloc( jd, n_points_lightcurve * sizeof( double ) );
  if ( jd == NULL ) {
   fprintf( stderr, "ERROR: Couldn't (re)allocate memory for jd(kwee-van-woerden.c)\n" );
   exit( 1 );
  };
  m= realloc( m, n_points_lightcurve * sizeof( double ) );
  if ( m == NULL ) {
   fprintf( stderr, "ERROR: Couldn't (re)allocate memory for m(kwee-van-woerden.c)\n" );
   exit( 1 );
  };
  n_points_lightcurve++;
 } while ( -1 < read_lightcurve_point( stdin, &jd[n_points_lightcurve - 2], &m[n_points_lightcurve - 2], &merr_not_used, NULL, NULL, NULL, NULL, NULL ) );
 // while( -1 < fscanf(stdin, "%lf %lf", &jd[n_points_lightcurve - 2], &m[n_points_lightcurve - 2]) );
 n_points_lightcurve--;
 n_points_lightcurve--;
 fprintf( stderr, "n_points=%d\n", n_points_lightcurve );

 if ( n_points_lightcurve < 6 ) {
  fprintf( stderr, "ERROR in kwee-van-woerden.c  -- too few points for lightcurve minimum search\n" );
  exit( 1 );
 }

 Z= 0.25 * (double)n_points_lightcurve;
 fprintf( stderr, "Expecting number of independent pairs Z=%d\n", (int)( Z + 0.0 ) );

 /* Sort data */
 /*
 size_t *order= malloc(sizeof(size_t) * n_points_lightcurve);
 gsl_sort_index(order, jd, 1, n_points_lightcurve);

 for( i= 0; i < n_points_lightcurve; i++ ) {
  mean_jd+= jd[i];
  int id= order[i];
  tmp_jd= jd[i];
  tmp_m= m[i];
  jd[i]= jd[id];
  m[i]= m[id];
  jd[id]= tmp_jd;
  m[id]= tmp_m;
 };
 free(order);
 */
 gsl_sort2( jd, 1, m, 1, n_points_lightcurve );
 // mean_jd= mean_jd / n_points_lightcurve;
 mean_jd= gsl_stats_mean( jd, 1, n_points_lightcurve );
 fprintf( stderr, "Mean JD = %lf\n", mean_jd );
 // mean_jd=mean_jd-10.0;
 for ( i= 0; i < n_points_lightcurve; i++ ) {
  jd[i]= jd[i] - mean_jd;
 }

 /* for(i=0;i<n_points_lightcurve;i++){
  fprintf(stderr,"%lf %lf\n",jd[i],m[i]);
 }*/

 /* dt is the typical distance between data points */
 dt= ( jd[n_points_lightcurve - 1] - jd[0] ) / n_points_lightcurve;
 fprintf( stderr, "dt = %lf\n", dt );

 /* Form 2n+1 magnitudes spaced by equal time intervals dt */
 interp_m= malloc( ( 2 * n_points_lightcurve + 1 ) * sizeof( double ) );
 if ( interp_m == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for interp_m(kwee-van-woerden.c)\n" );
  return 1;
 };
 interp_jd= malloc( ( 2 * n_points_lightcurve + 1 ) * sizeof( double ) );
 if ( interp_jd == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for interp_jd(kwee-van-woerden.c)\n" );
  return 1;
 };
 interp_m[0]= m[0];
 interp_jd[0]= jd[0];
 n= 0;
 while ( interp_jd[n] < jd[n_points_lightcurve - 1] ) {
  interp_jd[n + 1]= interp_jd[n] + dt;
  best_d= 99999.0;
  best_d_j= n_points_lightcurve; // reset
  for ( j= 0; j < n_points_lightcurve; j++ ) {
   if ( interp_jd[n + 1] - jd[j] < best_d && interp_jd[n + 1] - jd[j] > 0.0 ) {
    best_d= interp_jd[n + 1] - jd[j];
    best_d_j= j;
   }
  }
  if ( best_d_j < n_points_lightcurve ) {
   a= ( m[best_d_j] - m[best_d_j + 1] ) / ( jd[best_d_j] - jd[best_d_j + 1] );
   b= ( jd[best_d_j] * m[best_d_j + 1] - jd[best_d_j + 1] * m[best_d_j] ) / ( jd[best_d_j] - jd[best_d_j + 1] );
   interp_m[n + 1]= a * interp_jd[n + 1] + b;
   n++;
  } else {
   fprintf( stderr, "ERROR in kwee-van-woerden.c best_d_j>=n_points_lightcurve\n" );
   return 1;
  }
 }

 fprintf( stderr, "Interpolated lightcurve (%d points):\n", n );
 for ( i= 0; i < n; i++ ) {
  fprintf( stderr, "%+8.6lf %lf  %3d\n", interp_jd[i], interp_m[i], i );
 }

 /* Find T1 (estimated minima time) */
 mT1= -99.0;
 // for ( i= 0; i < n; i++ ) {
 //  1 to n - 1 as we have i + 1 and i - 1 array indexes
 for ( i= 1; i < n - 1; i++ ) {
  if ( interp_m[i] > mT1 ) {
   jdT1= i;
   mT1= interp_m[i];
   T1= interp_jd[i];
   T2= interp_jd[i + 1];
   T3= interp_jd[i - 1];
  }
 }
 fprintf( stderr, "First guess (the faintest point in the interpolated lightcurve):  T1 = %lf is the point with index i=%d\n", T1, jdT1 );

 // is this correct?
 /*
  if ( n - jdT1 > jdT1 ) {
   n_delta_m= jdT1 - 1;
  } else {
   n_delta_m= n - jdT1 - 1;
  }
 */
 n_delta_m= MIN( jdT1, n - jdT1 );
 // delta_m= malloc( (2 * n_points_lightcurve + 1) * sizeof( double ) );
 delta_m= malloc( n_delta_m * sizeof( double ) );
 if ( delta_m == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for delta_m(kwee-van-woerden.c)\n" );
  return 1;
 }

 // n_delta_m--;
 fprintf( stderr, "using %d pairs\n", n_delta_m );
 // NO, this will ruin sT3 calculation
 // n_delta_m++; // because it is used as the index offset: for i=0  0.0= delta_m[i]= interp_m[jdT1 - i] - interp_m[jdT1 + i]

 if ( n_delta_m < 1 ) {
  fprintf( stderr, "ERROR: too few pairs for minimum determination!\n" );
  free( m );
  free( jd );
  free( interp_m );
  free( interp_jd );
  free( delta_m );
  return 1;
 }

 /* sT1 */
 // for i=0 we'll have the faintest point subtracted from itself
 for ( i= 0; i < n_delta_m; i++ ) {
  delta_m[i]= interp_m[jdT1 - i] - interp_m[jdT1 + i];
 }
 sT1= 0;
 for ( i= 0; i < n_delta_m; i++ ) {
  sT1+= delta_m[i] * delta_m[i];
 }
 sT1= sT1 / ( n_delta_m - 1 );
 fprintf( stderr, "sT1 = %lg\n", sT1 );

 /* sT2 */
 jdT1+= 1;
 for ( i= 0; i < n_delta_m; i++ ) {
  delta_m[i]= interp_m[jdT1 - i] - interp_m[jdT1 + i];
 }
 sT2= 0;
 for ( i= 0; i < n_delta_m; i++ ) {
  sT2+= delta_m[i] * delta_m[i];
 }
 sT2= sT2 / ( n_delta_m - 1 );
 fprintf( stderr, "sT2 = %lg\n", sT2 );

 /* sT3 */
 jdT1-= 2;
 for ( i= 0; i < n_delta_m; i++ ) {
  delta_m[i]= interp_m[jdT1 - i] - interp_m[jdT1 + i];
 }
 sT3= 0;
 for ( i= 0; i < n_delta_m; i++ ) {
  sT3+= delta_m[i] * delta_m[i];
 }
 sT3= sT3 / ( n_delta_m - 1 );
 fprintf( stderr, "sT3 = %lg\n", sT3 );

 B= -1 * ( -T2 * T2 * sT1 + T2 * T2 * sT3 + sT2 * T1 * T1 - sT2 * T3 * T3 + T3 * T3 * sT1 - sT3 * T1 * T1 ) / ( T3 * T1 * T1 - T2 * T1 * T1 + T2 * T3 * T3 - T1 * T3 * T3 + T1 * T2 * T2 - T3 * T2 * T2 );
 C= ( -1 * sT3 * T2 * T1 * T1 + T2 * T2 * T1 * sT3 + T3 * T3 * T2 * sT1 - T3 * T3 * T1 * sT2 - T2 * T2 * T3 * sT1 + sT2 * T3 * T1 * T1 ) / ( T3 * T1 * T1 - T2 * T1 * T1 + T2 * T3 * T3 - T1 * T3 * T3 + T1 * T2 * T2 - T3 * T2 * T2 );
 A= ( T3 * sT1 - T1 * sT3 - T2 * sT1 - T3 * sT2 + T2 * sT3 + T1 * sT2 ) / ( T3 * T1 * T1 - T2 * T1 * T1 + T2 * T3 * T3 - T1 * T3 * T3 + T1 * T2 * T2 - T3 * T2 * T2 );

 fprintf( stderr, "DEBUG: A=%lf B=%lf C=%lf\n", A, B, C );

 T0= ( -0.5 ) * B / A;

 sigma_T0= ( 4 * A * C - B * B ) / ( 4 * A * A * (double)( (int)( Z + 0.0 ) - 1 ) );
 sigma_T0= sqrt( sigma_T0 );
 fprintf( stderr, "T0 = %lf\nsigma_T0 = %lf\n", T0, sigma_T0 );
 fprintf( stderr, "#################################\n" );
 fprintf( stdout, "%lf   %lf\n", T0 + mean_jd, sigma_T0 );

 free( jd );
 free( m );
 free( delta_m );
 free( interp_jd );
 free( interp_m );
 return 0;
}
