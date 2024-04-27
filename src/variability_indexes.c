/*

  The code below computes the variability indexes
  suggested by Stetson, Peter B. in 1996PASP..108..851S
  see http://adsabs.harvard.edu/abs/1996PASP..108..851S

  ...and many other variability indexes!

  See http://adsabs.harvard.edu/abs/2017MNRAS.464..274S
  for a detailed discussion of the implemented indexes.

*/

#include <stdlib.h>
#include <stdio.h>
#include <math.h>

#include <gsl/gsl_statistics_double.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_errno.h>
#include <gsl/gsl_randist.h>
#include <gsl/gsl_cdf.h>
#include <gsl/gsl_sf_gamma.h> // for gsl_sf_gamma() and GSL_SF_GAMMA_XMAX

#include <gsl/gsl_statistics_float.h>
#include <gsl/gsl_sort_float.h>

#include "vast_limits.h"

#include "variability_indexes.h"

double sgn( double a ) {
 if ( a < 0.0 )
  return -1.0;
 return 1.0;
}

// input_max_pair_diff_sigma - do not form pairs if magnitude difference is more than input_max_pair_diff_sigma*error
void stetson_JKL_from_sorted_lightcurve( size_t *input_array_index_p, double *input_JD, double *input_m, double *input_merr, int input_Nobs, int input_Nmax, double input_max_pair_diff_sigma, int input_use_time_based_weighting, double *output_J, double *output_K, double *output_L ) {

#ifdef DISABLE_INDEX_STETSON_JKL
 if ( DEFAULT_MAX_PAIR_DIFF_SIGMA == input_max_pair_diff_sigma && 0 == input_use_time_based_weighting ) {
  ( *output_J )= 0.0;
  ( *output_K )= 0.0;
  ( *output_L )= 0.0;
  return;
 }
#endif

#ifdef DISABLE_INDEX_STETSON_JKL_TIME_WEIGHTING
 if ( 1 == input_use_time_based_weighting ) {
  ( *output_J )= 0.0;
  ( *output_K )= 0.0;
  ( *output_L )= 0.0;
  return;
 }
#endif

#ifdef DISABLE_INDEX_STETSON_JKL_MAG_CLIP_PAIRS
 if ( DEFAULT_MAX_PAIR_DIFF_SIGMA != input_max_pair_diff_sigma ) {
  ( *output_J )= 0.0;
  ( *output_K )= 0.0;
  ( *output_L )= 0.0;
  return;
 }
#endif

 if ( input_Nobs < 2 ) {
  fprintf( stderr, "ERROR in stetson_JKL_from_sorted_lightcurve(): %d -- too few data points to compute the index!\n", input_Nobs );
  ( *output_J )= 0.0;
  ( *output_K )= 0.0;
  ( *output_L )= 0.0;
  return;
 }

 int i, j, k, n;

 double J, J_forward, J_backward;
 double K;
 double L;

 double mean_magnitude, old_mean_magnitude;

 double a, b;

 double *P= malloc( 4 * input_Nobs * sizeof( double ) );
 if ( P == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for array P\n" );
  exit( EXIT_FAILURE );
 };
 double di, dj;

 double sum, sum_w;

 double sqrt_n_nm1;

 double ws_binning_days= WS_BINNING_DAYS; // Maximum time difference between points to form a pair
                                          // Will be set to a total lightcurve duration if time-based weighting is requested
                                          // by setting input_use_time_based_weighting=1
 double dt;                               //  the median of all pair time spans t_i+1 - t_i
 dt= 1.0;                                 // we initialize it to 1 to silance the compiler warning -Wmaybe-uninitialized

#ifdef DEBUGFILES
 FILE *debugfile_sortedLC;
 FILE *debugfile_stetsonJpair1;
 FILE *debugfile_stetsonJpair2;
 FILE *debugfile_stetsonJisolated;
#endif

 double *w;

 // Why 4?
 w= malloc( 4 * input_Nobs * sizeof( double ) );
 if ( w == NULL ) {
  fprintf( stderr, "ERROR in variability_indexes.c - cannot allocate memory\n" );
  exit( EXIT_FAILURE );
 }

 // Check if we should use time-based weighting
 if ( input_use_time_based_weighting == 1 ) {
  ws_binning_days= input_JD[input_array_index_p[input_Nobs - 1]] - input_JD[input_array_index_p[0]];
  // We'll re-use w array
  // for(i=0;i<input_Nobs-1;i++){
  for ( i= 0; i < input_Nobs - 2; i++ ) {
   w[i]= input_JD[input_array_index_p[i + 1]] - input_JD[input_array_index_p[i]];
  }
  gsl_sort( w, 1, i );
  dt= gsl_stats_median_from_sorted_data( w, 1, i );
 }

 ////////////////////////////////////////////////////////////////////////////////////////////////////
 ////  Determine robust mean and weights through an iterative procedure following Stetson (1996) ////
 ////////////////////////////////////////////////////////////////////////////////////////////////////
 // Initial guess
 for ( i= 0; i < input_Nobs; i++ ) {
  w[i]= 1.0 / ( input_merr[i] * input_merr[i] );
 }
 old_mean_magnitude= mean_magnitude= gsl_stats_wmean( w, 1, input_m, 1, input_Nobs );
 // re-weighting
 a= b= 2.0;
 // 1000 here is the maximum number of iterations, just to make sure the process will not go on forever
 for ( j= 0; j < 1000; j++ ) {
  for ( i= 0; i < input_Nobs; i++ ) {
   w[i]= w[i] / ( 1.0 + pow( fabs( ( input_m[i] - mean_magnitude ) / input_merr[i] ) / a, b ) );
  }
  mean_magnitude= gsl_stats_wmean( w, 1, input_m, 1, input_Nobs );
  if ( fabs( old_mean_magnitude - mean_magnitude ) < 0.00001 )
   break; // erarly stop condition
  old_mean_magnitude= mean_magnitude;
 }
 // fprintf(stderr,"DEBUG stetson_JKL_from_sorted_lightcurve() mean_magnitude=%lf\n",mean_magnitude);
 ////////////////////////////////////////////////////////////////////////////////////////////////////

 sqrt_n_nm1= sqrt( (double)input_Nobs / (double)( input_Nobs - 1 ) );

#ifdef DEBUGFILES
 // Write debug files only if the function is started with the default parameters
 // (only the first time it is run)
 if ( DEFAULT_MAX_PAIR_DIFF_SIGMA == input_max_pair_diff_sigma && 0 == input_use_time_based_weighting ) {
  fprintf( stdout, "mean_magnitude(J)= %lf\n", mean_magnitude );
  debugfile_sortedLC= fopen( "debugfile_sortedLC.dat", "w" );
  debugfile_stetsonJpair1= fopen( "debugfile_stetsonJpair1.dat", "w" );
  debugfile_stetsonJpair2= fopen( "debugfile_stetsonJpair2.dat", "w" );
  debugfile_stetsonJisolated= fopen( "debugfile_stetsonJisolated.dat", "w" );
 }

 // Save sorted lightcurve for debug
 for ( i= 0; i < input_Nobs; i++ ) {
  // Write debug files only if the function is started with the default parameters
  // (only the first time it is run)
  if ( DEFAULT_MAX_PAIR_DIFF_SIGMA == input_max_pair_diff_sigma && 0 == input_use_time_based_weighting ) {
   fprintf( debugfile_sortedLC, "%.6lf %.6lf %.6lf\n", input_JD[input_array_index_p[i]], input_m[input_array_index_p[i]], input_merr[input_array_index_p[i]] );
  }
 }
#endif

 // From now on w[] is re-used for the weights of pairs P[], not points m[]

 // ----****  Forward  ****----
 for ( k= 0, i= 0; i < input_Nobs; i++ ) {
// fprintf(stderr,"DEBUG stetson_JKL_from_sorted_lightcurve() 19\n");
#ifdef DEBUGFILES
  // Write debug files only if the function is started with the default parameters
  // (only the first time it is run)
  if ( DEFAULT_MAX_PAIR_DIFF_SIGMA == input_max_pair_diff_sigma && 0 == input_use_time_based_weighting ) {
   fprintf( stderr, "J_forward %d\n", i );
  }
#endif

  /*
  if( i<input_Nobs-3 ){
   if( input_JD[input_array_index_p[i+2]]-input_JD[input_array_index_p[i]]<ws_binning_days ){
    // 3-point case
    di=sqrt_n_nm1*(input_m[input_array_index_p[i]]-mean_magnitude)/input_merr[input_array_index_p[i]];
    dj=sqrt_n_nm1*(input_m[input_array_index_p[i+1]]-mean_magnitude)/input_merr[input_array_index_p[i+1]];
    dk=sqrt_n_nm1*(input_m[input_array_index_p[i+2]]-mean_magnitude)/input_merr[input_array_index_p[i+2]];
    P[k]=di*dj;w[k]=2.0/3.0;k++;
    P[k]=dj*dk;w[k]=2.0/3.0;k++;
    P[k]=di*dk;w[k]=2.0/3.0;k++;
    i++;i++;//
    continue;
   }
  }
*/
  if ( i < input_Nobs - 1 ) {
   if ( input_JD[input_array_index_p[i + 1]] - input_JD[input_array_index_p[i]] < ws_binning_days && fabs( input_m[input_array_index_p[i]] - input_m[input_array_index_p[i + 1]] ) < input_max_pair_diff_sigma * sqrt( input_merr[input_array_index_p[i]] * input_merr[input_array_index_p[i]] + input_merr[input_array_index_p[i + 1]] * input_merr[input_array_index_p[i + 1]] ) ) {
    // 2-point case
    di= sqrt_n_nm1 * ( input_m[input_array_index_p[i]] - mean_magnitude ) / input_merr[input_array_index_p[i]];
    dj= sqrt_n_nm1 * ( input_m[input_array_index_p[i + 1]] - mean_magnitude ) / input_merr[input_array_index_p[i + 1]];
    P[k]= di * dj;
    // Check if we should use time-based weighting
    if ( input_use_time_based_weighting == 1 ) {
     // Set weight of the pair based on time difference
     w[k]= exp( -1.0 * ( input_JD[input_array_index_p[i + 1]] - input_JD[input_array_index_p[i]] ) / dt );
     // fprintf(stderr,"stetson_JKL_from_sorted_lightcurve() dt= %lf  w[k]=%lf\n",dt,w[k]);
    } else {
     // Just set the weight to 1
     w[k]= 1.0;
     if ( input_use_time_based_weighting == 1 )
      fprintf( stderr, "stetson_JKL_from_sorted_lightcurve() dt= %lf  w[k]=%lf\n", dt, w[k] );
    }
    k++;

#ifdef DEBUGFILES
    // Write debug files only if the function is started with the default parameters
    // (only the first time it is run)
    if ( DEFAULT_MAX_PAIR_DIFF_SIGMA == input_max_pair_diff_sigma && 0 == input_use_time_based_weighting ) {
     fprintf( debugfile_stetsonJpair1, "%.6lf %.6lf %.6lf\n", input_JD[input_array_index_p[i]], input_m[input_array_index_p[i]], input_merr[input_array_index_p[i]] );
     fprintf( debugfile_stetsonJpair2, "%.6lf %.6lf %.6lf\n", input_JD[input_array_index_p[i + 1]], input_m[input_array_index_p[i + 1]], input_merr[input_array_index_p[i + 1]] );
    }
#endif

    i++; //
    continue;
   }
  }
  // 1-point case
  di= sqrt_n_nm1 * ( input_m[input_array_index_p[i]] - mean_magnitude ) / input_merr[input_array_index_p[i]];
  P[k]= di * di - 1.0;
  w[k]= 1.0;
  k++; // should we assign the same weight to singleton observations???

#ifdef DEBUGFILES
  // Write debug files only if the function is started with the default parameters
  // (only the first time it is run)
  if ( DEFAULT_MAX_PAIR_DIFF_SIGMA == input_max_pair_diff_sigma && 0 == input_use_time_based_weighting ) {
   fprintf( debugfile_stetsonJisolated, "%.6lf %.6lf %.6lf\n", input_JD[input_array_index_p[i]], input_m[input_array_index_p[i]], input_merr[input_array_index_p[i]] );
  }
#endif
 }

 n= k;
 sum_w= sum= 0.0;
 for ( k= 0; k < n; k++ ) {
  sum+= w[k] * sgn( P[k] ) * sqrt( fabs( P[k] ) );
  sum_w+= w[k];
 }

 J_forward= sum / sum_w;

// Write debug information if needed
#ifdef DEBUGFILES
 // Write debug files only if the function is started with the default parameters
 // (only the first time it is run) for the classic J index
 if ( DEFAULT_MAX_PAIR_DIFF_SIGMA == input_max_pair_diff_sigma && 0 == input_use_time_based_weighting ) {
  fclose( debugfile_sortedLC );
  fclose( debugfile_stetsonJpair1 );
  fclose( debugfile_stetsonJpair2 );
  fclose( debugfile_stetsonJisolated );

  fprintf( stderr, "DEBUG: writing back files!\n" );
  debugfile_stetsonJpair1= fopen( "debugfile_back_stetsonJpair1.dat", "w" );
  debugfile_stetsonJpair2= fopen( "debugfile_back_stetsonJpair2.dat", "w" );
  debugfile_stetsonJisolated= fopen( "debugfile_back_stetsonJisolated.dat", "w" );
 }
#endif

 // ----****  Backward ****----
 for ( k= 0, i= input_Nobs - 1; i > -1; i-- ) {

// fprintf(stderr,"DEBUG stetson_JKL_from_sorted_lightcurve() 22 k=%d\n",k);
#ifdef DEBUGFILES
  // Write debug files only if the function is started with the default parameters
  // (only the first time it is run)
  if ( DEFAULT_MAX_PAIR_DIFF_SIGMA == input_max_pair_diff_sigma && 0 == input_use_time_based_weighting ) {
   fprintf( stderr, "J_back %d\n", i );
  }
#endif

  /*
  if( i>1 ){
   if( input_JD[input_array_index_p[i]]-input_JD[input_array_index_p[i-2]]<ws_binning_days ){
    // 3-point case
    di=sqrt_n_nm1*(input_m[input_array_index_p[i]]-mean_magnitude)/input_merr[input_array_index_p[i]];
    dj=sqrt_n_nm1*(input_m[input_array_index_p[i-1]]-mean_magnitude)/input_merr[input_array_index_p[i-1]];
    dk=sqrt_n_nm1*(input_m[input_array_index_p[i-2]]-mean_magnitude)/input_merr[input_array_index_p[i-2]];
    P[k]=di*dj;w[k]=2.0/3.0;k++;
    P[k]=dj*dk;w[k]=2.0/3.0;k++;
    P[k]=di*dk;w[k]=2.0/3.0;k++;
    i--;i--;//
    continue;
   }
  }
*/
  // fprintf(stderr,"DEBUG stetson_JKL_from_sorted_lightcurve() 23 %d\n",k);
  if ( i > 0 ) {
   if ( input_JD[input_array_index_p[i]] - input_JD[input_array_index_p[i - 1]] < ws_binning_days && fabs( input_m[input_array_index_p[i]] - input_m[input_array_index_p[i - 1]] ) < input_max_pair_diff_sigma * sqrt( input_merr[input_array_index_p[i]] * input_merr[input_array_index_p[i]] + input_merr[input_array_index_p[i - 1]] * input_merr[input_array_index_p[i - 1]] ) ) {
    // 2-point case
    di= sqrt_n_nm1 * ( input_m[input_array_index_p[i]] - mean_magnitude ) / input_merr[input_array_index_p[i]];
    dj= sqrt_n_nm1 * ( input_m[input_array_index_p[i - 1]] - mean_magnitude ) / input_merr[input_array_index_p[i - 1]];
    P[k]= di * dj;
    // Check if we should use time-based weighting
    if ( input_use_time_based_weighting == 1 ) {
     // Set weight of the pair based on time difference
     w[k]= exp( -1.0 * ( input_JD[input_array_index_p[i]] - input_JD[input_array_index_p[i - 1]] ) / dt );
    } else {
     // Just set the weight to 1
     w[k]= 1.0;
    }
    k++;

#ifdef DEBUGFILES
    // Write debug files only if the function is started with the default parameters
    // (only the first time it is run)
    if ( DEFAULT_MAX_PAIR_DIFF_SIGMA == input_max_pair_diff_sigma && 0 == input_use_time_based_weighting ) {
     fprintf( debugfile_stetsonJpair2, "%.6lf %.6lf %.6lf\n", input_JD[input_array_index_p[i]], input_m[input_array_index_p[i]], input_merr[input_array_index_p[i]] );
     fprintf( debugfile_stetsonJpair1, "%.6lf %.6lf %.6lf\n", input_JD[input_array_index_p[i - 1]], input_m[input_array_index_p[i - 1]], input_merr[input_array_index_p[i - 1]] );
    }
#endif

    i--; //
    continue;
   }
  }
  // 1-point case
  di= sqrt_n_nm1 * ( input_m[input_array_index_p[i]] - mean_magnitude ) / input_merr[input_array_index_p[i]];
  P[k]= di * di - 1.0;
  w[k]= 1.0;
  k++; // should we assign the same weight to singleton observations???

#ifdef DEBUGFILES
  // Write debug files only if the function is started with the default parameters
  // (only the first time it is run)
  if ( DEFAULT_MAX_PAIR_DIFF_SIGMA == input_max_pair_diff_sigma && 0 == input_use_time_based_weighting ) {
   fprintf( debugfile_stetsonJisolated, "%.6lf %.6lf %.6lf\n", input_JD[input_array_index_p[i]], input_m[input_array_index_p[i]], input_merr[input_array_index_p[i]] );
  }
#endif
 }

 n= k;
 sum_w= sum= 0.0;
 for ( k= 0; k < n; k++ ) {
  sum+= w[k] * sgn( P[k] ) * sqrt( fabs( P[k] ) );
  sum_w+= w[k];
 }

 J_backward= sum / sum_w;

 J= ( J_backward + J_forward ) / 2.0;

#ifdef DEBUGFILES
 // Write debug files only if the function is started with the default parameters
 // (only the first time it is run)
 if ( DEFAULT_MAX_PAIR_DIFF_SIGMA == input_max_pair_diff_sigma && 0 == input_use_time_based_weighting ) {
  fprintf( stderr, "DEBUG: mean_magnitude=%lf\n", mean_magnitude );
  fprintf( stderr, "J_forward=%f J_backward=%f J=%f\n", J_forward, J_backward, J );
  fclose( debugfile_stetsonJpair1 );
  fclose( debugfile_stetsonJpair2 );
  fclose( debugfile_stetsonJisolated );
 }
#endif

 // K is a robust measure of the kurtosis of the magnitude histogram:
 sum_w= sum= 0.0;
 for ( i= 0; i < input_Nobs; i++ ) {
  // are you sure we should not recompute sqrt_n_nm1 somwere here?
  di= sqrt_n_nm1 * ( input_m[input_array_index_p[i]] - mean_magnitude ) / input_merr[input_array_index_p[i]];
  sum+= fabs( di );
  sum_w+= di * di;
 }
 K= 1.0 / (double)input_Nobs * sum / sqrt( 1.0 / (double)input_Nobs * sum_w );
 // for a Gaussian noise K->0.798

 // Compute the last index, L which is the combination of J and K
 L= ( J * K / 0.798 ) * (double)input_Nobs / (double)input_Nmax;

 // Write-out the results
 ( *output_J )= J;
 ( *output_K )= K;
 ( *output_L )= L;

 // free-up the memory
 free( w );
 free( P );

 return;
}

double sign_only_welch_stetson_I_from_sorted_lightcurve( size_t *input_array_index_p, double *input_JD, double *input_m, double *input_merr, int input_Nobs ) {

#ifdef DISABLE_INDEX_WELCH_STETSON_SIGN_ONLY
 return 0.0;
#endif

 double I, I_forward; //,I_backward;
 int i, n;

 double mean_magnitude, sum;

 double *w;

 w= malloc( input_Nobs * sizeof( double ) );
 if ( w == NULL ) {
  fprintf( stderr, "ERROR in variability_indexes.c - cannot allocate memory\n" );
  exit( EXIT_FAILURE );
 }

 // Set weights
 for ( i= 0; i < input_Nobs; i++ ) {
  w[i]= 1.0 / ( input_merr[i] * input_merr[i] );
 }
 mean_magnitude= gsl_stats_wmean( w, 1, input_m, 1, input_Nobs );

 // for(i=0;i<input_Nobs-1;i++)fprintf(stderr,"%lf %lf %lf\n",input_JD[input_array_index_p[i]],input_m[input_array_index_p[i]],input_merr[input_array_index_p[i]]);
 // fprintf(stderr,"#######################################################################\n");
 //  Forward
 sum= 0.0;
 for ( n= 0, i= 0; i < input_Nobs - 1; i++ ) {
  // do not form a pair if two points are too far apart
  if ( input_JD[input_array_index_p[i + 1]] - input_JD[input_array_index_p[i]] > WS_BINNING_DAYS )
   continue;
  // form a pair
  sum+= sgn( ( input_m[input_array_index_p[i]] - mean_magnitude ) / input_merr[input_array_index_p[i]] * ( input_m[input_array_index_p[i + 1]] - mean_magnitude ) / input_merr[input_array_index_p[i + 1]] );
  n++;
  // fprintf(stderr,"%lf %lf %lf\n%lf %lf %lf\n",input_JD[input_array_index_p[i]],input_m[input_array_index_p[i]],input_merr[input_array_index_p[i]],input_JD[input_array_index_p[i+1]],input_m[input_array_index_p[i+1]],input_merr[input_array_index_p[i+1]]);

  // i++;//
 }
 I_forward= sum * sqrt( 1.0 / ( (double)n * ( (double)n - 1.0 ) ) );

 if ( 0 == isnan( I_forward ) ) {
  I= I_forward;
 } else {
  I= 0.0;
 }

 free( w );

 return I;
}

double classic_welch_stetson_I_from_sorted_lightcurve( size_t *input_array_index_p, double *input_JD, double *input_m, double *input_merr, int input_Nobs ) {

#ifdef DISABLE_INDEX_WELCH_STETSON
 return 0.0;
#endif

 double I, I_forward, I_backward;
 int i, n;

 double mean_magnitude, sum; //,sum_w;

#ifdef DEBUGFILES
 FILE *debugfile_stetsonIpair1;
 FILE *debugfile_stetsonIpair2;
#endif

 double *w;
 w= malloc( input_Nobs * sizeof( double ) );
 if ( w == NULL ) {
  fprintf( stderr, "ERROR in variability_indexes.c - cannot allocate memory\n" );
  exit( EXIT_FAILURE );
 }

 // Set weights
 for ( i= 0; i < input_Nobs; i++ ) {
  w[i]= 1.0 / ( input_merr[i] * input_merr[i] );
 }
 mean_magnitude= gsl_stats_wmean( w, 1, input_m, 1, input_Nobs );
 // mean_magnitude=gsl_stats_mean(input_m, 1, input_Nobs);

 // fprintf(stderr,"classic_welch_stetson_I_from_sorted_lightcurve() mean_magnitude=%lf\n",mean_magnitude);

 /*
 sum_w=sum=0.0;
 for(n=0,i=0;i<input_Nobs-1;i++){
  // do not form a pair if two points are too far apart
  if( input_JD[input_array_index_p[i+1]]-input_JD[input_array_index_p[i]]>WS_BINNING_DAYS )continue;
  // form a pair
  w[i]=1.0; // /(input_merr[input_array_index_p[i]]*input_merr[input_array_index_p[i]]);
  w[i+1]=1.0; // /(input_merr[input_array_index_p[i+1]]*input_merr[input_array_index_p[i+1]]);
  sum+=w[i]*input_m[input_array_index_p[i]];
  sum+=w[i+1]*input_m[input_array_index_p[i+1]];
  sum_w+=w[i];
  sum_w+=w[i+1];
  n++;
  n++;
  //fprintf(stderr,"%lf %lf %lf\n%lf %lf %lf\n",input_JD[input_array_index_p[i]],input_m[input_array_index_p[i]],input_merr[input_array_index_p[i]],input_JD[input_array_index_p[i+1]],input_m[input_array_index_p[i+1]],input_merr[input_array_index_p[i+1]]);
  //i++;//
 }
 mean_magnitude=sum/sum_w;
*/

#ifdef DEBUGFILES
 fprintf( stdout, "mean_magnitude(I)= %lf\n", mean_magnitude );
 debugfile_stetsonIpair1= fopen( "debugfile_stetsonIpair1.dat", "w" );
 debugfile_stetsonIpair2= fopen( "debugfile_stetsonIpair2.dat", "w" );
#endif

 // for(i=0;i<input_Nobs-1;i++)fprintf(stderr,"%lf %lf %lf\n",input_JD[input_array_index_p[i]],input_m[input_array_index_p[i]],input_merr[input_array_index_p[i]]);
 // fprintf(stderr,"#######################################################################\n");
 //  Forward
 sum= 0.0;
 for ( n= 0, i= 0; i < input_Nobs - 1; i++ ) {
  // do not form a pair if two points are too far apart
  if ( input_JD[input_array_index_p[i + 1]] - input_JD[input_array_index_p[i]] > WS_BINNING_DAYS )
   continue;
  // form a pair
  sum+= ( input_m[input_array_index_p[i]] - mean_magnitude ) / input_merr[input_array_index_p[i]] * ( input_m[input_array_index_p[i + 1]] - mean_magnitude ) / input_merr[input_array_index_p[i + 1]];
  n++;

#ifdef DEBUGFILES
  fprintf( debugfile_stetsonIpair1, "%.6lf %.6lf %.6lf\n", input_JD[input_array_index_p[i]], input_m[input_array_index_p[i]], input_merr[input_array_index_p[i]] );
  fprintf( debugfile_stetsonIpair2, "%.6lf %.6lf %.6lf\n", input_JD[input_array_index_p[i + 1]], input_m[input_array_index_p[i + 1]], input_merr[input_array_index_p[i + 1]] );
#endif

  i++; //
 }
 I_forward= sum * sqrt( 1.0 / ( (double)n * ( (double)n - 1.0 ) ) );

 // Backward is the same as forward if we allow each point to be binned bothe with both its right and left neighbours

#ifdef DEBUGFILES
 fclose( debugfile_stetsonIpair1 );
 fclose( debugfile_stetsonIpair2 );
 fprintf( stderr, "DEBUG: writing back files!\n" );
 fprintf( stderr, "DEBUG: mean_magnitude=%lf\n", mean_magnitude );
 debugfile_stetsonIpair1= fopen( "debugfile_back_stetsonIpair1.dat", "w" );
 debugfile_stetsonIpair2= fopen( "debugfile_back_stetsonIpair2.dat", "w" );
#endif

 // Backward
 sum= 0.0;
 for ( n= 0, i= input_Nobs - 2; i > -1; i-- ) {
  // do not form a pair if two points are too far apart
  if ( input_JD[input_array_index_p[i + 1]] - input_JD[input_array_index_p[i]] > WS_BINNING_DAYS )
   continue;
  // form a pair
  sum+= ( input_m[input_array_index_p[i]] - mean_magnitude ) / input_merr[input_array_index_p[i]] * ( input_m[input_array_index_p[i + 1]] - mean_magnitude ) / input_merr[input_array_index_p[i + 1]];
  n++;

#ifdef DEBUGFILES
  fprintf( debugfile_stetsonIpair1, "%.6lf %.6lf %.6lf\n", input_JD[input_array_index_p[i]], input_m[input_array_index_p[i]], input_merr[input_array_index_p[i]] );
  fprintf( debugfile_stetsonIpair2, "%.6lf %.6lf %.6lf\n", input_JD[input_array_index_p[i + 1]], input_m[input_array_index_p[i + 1]], input_merr[input_array_index_p[i + 1]] );
#endif

  i--; //
 }
 I_backward= sum * sqrt( 1.0 / ( (double)n * ( (double)n - 1.0 ) ) );

 if ( 0 == isnan( I_forward ) && 0 == isnan( I_backward ) ) {
  I= ( I_forward + I_backward ) / 2.0;
 } else {
  I= 0.0;
 }
 /// Print only forward !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!1
 // I=I_forward;

#ifdef DEBUGFILES
 fprintf( stderr, "I_forward=%f I_backward=%f I=%f\n", I_forward, I_backward, I );
 fclose( debugfile_stetsonIpair1 );
 fclose( debugfile_stetsonIpair2 );
 fprintf( stderr, "#######################################################################\n" );
#endif

 // fprintf(stderr,"%lf %lf %lf\n",I_forward,I_backward,I);

 // I=I; /// ??????????????

 free( w );

 // exit( EXIT_FAILURE );

 return I;
}

// This function computes interquartile range
// (a range containing the innr 50% of values)
// for an unsorted dataset
/*
double compute_IQR_of_unsorted_data(double *unsorted_data, int n) {
#ifdef DISABLE_INDEX_IQR
 return 0.0;
#endif

 double Q1, Q2, Q3;
 double IQR; // the result
 double *x;  // copy of the input dataset that will be sorted
 double *x2;
 double *x3;
 int i, j, k; // counters

 // allocate memory
 x= malloc(n * sizeof(double));
 if( x == NULL ) {
  fprintf(stderr, "ERROR allocating memory for x in compute_IQR_of_unsorted_data()\n");
  exit( EXIT_FAILURE );
 }
 x2= malloc(n * sizeof(double));
 if( x2 == NULL ) {
  fprintf(stderr, "ERROR allocating memory for x2 in compute_IQR_of_unsorted_data()\n");
  exit( EXIT_FAILURE );
 }
 x3= malloc(n * sizeof(double));
 if( x3 == NULL ) {
  fprintf(stderr, "ERROR allocating memory for x3 in compute_IQR_of_unsorted_data()\n");
  exit( EXIT_FAILURE );
 }

 // make a copy of the input dataset
 for( i= 0; i < n; i++ ) {
  x[i]= unsorted_data[i];
 }
 // sort the copy
 gsl_sort(x, 1, n);

 // compute median
 Q2= gsl_stats_median_from_sorted_data(x, 1, n);

 // make copies of the lower (x2) and upper (x3) 50% of the data
 for( j= k= i= 0; i < n; i++ ) {
  if( x[i] <= Q2 ) {
   x2[j]= x[i];
   j++;
  } else {
   x3[k]= x[i];
   k++;
  }
 }
 // x2 and x3 are sorted because they are created from a sorted array (x)
 Q1= gsl_stats_median_from_sorted_data(x2, 1, j);
 Q3= gsl_stats_median_from_sorted_data(x3, 1, k);

 IQR= Q3 - Q1;

 // free-up memory
 free(x3);
 free(x2);
 free(x);

// // Scale IQR top sigma
// // ${\rm IQR} = 2 \Phi^{-1}(0.75)
// // 2*norminv(0.75) = 1.34897950039216
// //IQR=IQR/( 2.0*gsl_cdf_ugaussian_Pinv(0.75) );
// IQR= IQR / 1.34897950039216;

 // return result
 return IQR;
}
*/
double compute_IQR_of_sorted_data( double *sorted_data, int n ) {
 double Q1, Q2, Q3;
 double IQR;  // the result
 int i, j, k; // counters

 // compute median
 Q2= gsl_stats_median_from_sorted_data( sorted_data, 1, n );

 // make copies of the lower (x2) and upper (x3) 50% of the data
 for ( j= k= i= 0; i < n; i++ ) {
  if ( sorted_data[i] <= Q2 ) {
   j++;
  } else {
   k++;
  }
 }
 Q1= gsl_stats_median_from_sorted_data( sorted_data, 1, j );
 Q3= gsl_stats_median_from_sorted_data( &sorted_data[j], 1, k );

 IQR= Q3 - Q1;

 // return result
 return IQR;
}
double compute_IQR_of_unsorted_data( double *unsorted_data, int n ) {
#ifdef DISABLE_INDEX_IQR
 return 0.0;
#endif

 double IQR; // the result
 double *x;  // copy of the input dataset that will be sorted
 int i;      // counter

 // allocate memory
 x= malloc( n * sizeof( double ) );
 if ( x == NULL ) {
  fprintf( stderr, "ERROR allocating memory for x in compute_IQR_of_unsorted_data()\n" );
  exit( EXIT_FAILURE );
 }
 // make a copy of the input dataset
 for ( i= 0; i < n; i++ ) {
  x[i]= unsorted_data[i];
 }
 // sort the copy
 gsl_sort( x, 1, n );

 IQR= compute_IQR_of_sorted_data( x, n );

 free( x );

 // return result
 return IQR;
}
double estimate_sigma_from_IQR_of_unsorted_data( double *unsorted_data, int n ) {
 double IQR, sigma;
 IQR= compute_IQR_of_unsorted_data( unsorted_data, n );
 // Scale IQR top sigma
 // ${\rm IQR} = 2 \Phi^{-1}(0.75)
 // 2*norminv(0.75) = 1.34897950039216
 // IQR=IQR/( 2.0*gsl_cdf_ugaussian_Pinv(0.75) );
 sigma= IQR / 1.34897950039216;
 return sigma;
}
double estimate_sigma_from_IQR_of_sorted_data( double *sorted_data, int n ) {
 double IQR, sigma;
 IQR= compute_IQR_of_sorted_data( sorted_data, n );
 // Scale IQR top sigma
 // ${\rm IQR} = 2 \Phi^{-1}(0.75)
 // 2*norminv(0.75) = 1.34897950039216
 // IQR=IQR/( 2.0*gsl_cdf_ugaussian_Pinv(0.75) );
 sigma= IQR / 1.34897950039216;
 return sigma;
}

/*
float clipped_mean_of_unsorted_data_float( float *unsorted_data, long n ) {
 long i;
 double *x;
 float float_result;
 x=malloc(n*sizeof(double));
 for( i=0; i<n; i++ ) {
  x[i]=(double)unsorted_data[i];
 }
 float_result= (float)clipped_mean_of_unsorted_data( x, n );
 free(x);
 return float_result;
}

// This function will compute the clipped mean the input dataset,
// the input dataset will be copied and the copy will be sorted to compute median, MAD and reject outliers.
// The input dataset will not be changed.
double clipped_mean_of_unsorted_data( double *unsorted_data, long n ) {
 double median;
 double mean;
 int n_good_for_mean;
 double MAD_scaled_to_sigma; // the result
 double *x;                  // copy of the input dataset that will be sorted
 int i;                      // counter

 // allocate memory
 x= malloc( n * sizeof( double ) );
 if ( x == NULL ) {
  fprintf( stderr, "ERROR allocating memory for x in esimate_sigma_from_MAD_of_unsorted_data()\n" );
  exit( EXIT_FAILURE );
 }

 // make a copy of the input dataset
 for ( i= 0; i < n; i++ ) {
  x[i]= unsorted_data[i];
 }
 // sort the copy
 gsl_sort( x, 1, n );

 // compute MAD scaled to sigma
 MAD_scaled_to_sigma= esimate_sigma_from_MAD_of_sorted_data( x, n );
 median= gsl_stats_median_from_sorted_data( x, 1, n );

 n_good_for_mean=0;
 mean=0.0;
 for( i=0; i<n; i++ ) {
  if ( fabs( x[i]-median )<3*MAD_scaled_to_sigma ){
   mean+=x[i];
   n_good_for_mean++;
  }
 }
 mean= mean/(double)n_good_for_mean;

 // free-up memory
 free( x );

 // return result
 return MAD_scaled_to_sigma;
}
*/

// This function will compute the Median Absolute Deviation of the input dataset,
// the input dataset will be copied and the copy will be sorted to compute MAD.
// The input dataset will not be changed.
double esimate_sigma_from_MAD_of_unsorted_data( double *unsorted_data, long n ) {
 double MAD_scaled_to_sigma; // the result
 double *x;                  // copy of the input dataset that will be sorted
 int i;                      // counter

 // allocate memory
 x= malloc( n * sizeof( double ) );
 if ( x == NULL ) {
  fprintf( stderr, "ERROR allocating memory for x in esimate_sigma_from_MAD_of_unsorted_data()\n" );
  exit( EXIT_FAILURE );
 }

 // make a copy of the input dataset
 for ( i= 0; i < n; i++ ) {
  x[i]= unsorted_data[i];
 }
 // sort the copy
 gsl_sort( x, 1, n );
 // that is slower than gsl_sort()
 // vast_qsort_double(x, n);

 // compute MAD scaled to sigma
 MAD_scaled_to_sigma= esimate_sigma_from_MAD_of_sorted_data( x, n );

 // free-up memory
 free( x );

 // return result
 return MAD_scaled_to_sigma;
}

// This function will compute the Median Absolute Deviation of the input
// dataset ASSUMING IT IS SORTED and will scale it to sigma.
// The input dataset will not be changed. For a detailed discussion of MAD
// see http://en.wikipedia.org/wiki/Robust_measures_of_scale
// and http://en.wikipedia.org/wiki/Median_absolute_deviation#relation_to_standard_deviation
double compute_MAD_of_sorted_data( double *sorted_data, long n ) {
 double median_data, MAD; //, sigma;
 double *AD;
 int i;

 AD= malloc( n * sizeof( double ) );
 if ( AD == NULL ) {
  fprintf( stderr, "ERROR allocating memory for AD in compute_MAD_of_sorted_data()\n" );
  exit( EXIT_FAILURE );
 }

 // The input dataset has to be sorted so we can compute its median
 median_data= gsl_stats_median_from_sorted_data( sorted_data, 1, n );

 for ( i= 0; i < n; i++ ) {
  AD[i]= fabs( sorted_data[i] - median_data );
  // fprintf(stderr,"sorted_data[i]=%lf, median_data=%lf   AD=%lf\n",sorted_data[i],median_data,AD[i]);
 }
 gsl_sort( AD, 1, n );
 MAD= gsl_stats_median_from_sorted_data( AD, 1, n );

 free( AD );

 return MAD;

 // // 1.48260221850560 = 1/norminv(3/4)
 // sigma= 1.48260221850560 * MAD;
 // return sigma;
}

double esimate_sigma_from_MAD_of_sorted_data( double *sorted_data, long n ) {
 double sigma, MAD;
 MAD= compute_MAD_of_sorted_data( sorted_data, n );
 // 1.48260221850560 = 1/norminv(3/4)
 sigma= 1.48260221850560 * MAD;
 return sigma;
}

// float version of the above functions
float compute_MAD_of_sorted_data_float( float *sorted_data, long n ) {
 float median_data, MAD; //, sigma;
 float *AD;
 int i;

 AD= malloc( n * sizeof( float ) );
 if ( AD == NULL ) {
  fprintf( stderr, "ERROR allocating memory for AD in esimate_sigma_from_MAD_of_sorted_data_float()\n" );
  exit( EXIT_FAILURE );
 }

 // The input dataset has to be sorted so we can compute its median
 median_data= gsl_stats_float_median_from_sorted_data( sorted_data, 1, n );

 for ( i= 0; i < n; i++ ) {
  AD[i]= fabs( sorted_data[i] - median_data );
  // fprintf(stderr,"sorted_data[i]=%lf, median_data=%lf   AD=%lf\n",sorted_data[i],median_data,AD[i]);
 }
 gsl_sort_float( AD, 1, n );
 MAD= gsl_stats_float_median_from_sorted_data( AD, 1, n );

 free( AD );

 return MAD;
 // // 1.48260221850560 = 1/norminv(3/4)
 // sigma= 1.48260221850560 * MAD;
 // return sigma;
}
float esimate_sigma_from_MAD_of_sorted_data_float( float *sorted_data, long n ) {
 float MAD, sigma;
 MAD= compute_MAD_of_sorted_data_float( sorted_data, n );
 // 1.48260221850560 = 1/norminv(3/4)
 sigma= 1.48260221850560 * MAD;
 return sigma;
}

// as the above, but messes-up the input array in order to save memory
double compute_MAD_of_sorted_data_and_ruin_input_array( double *sorted_data, long n ) {
 double median_data, MAD; //, sigma;
 int i;

 // The input dataset has to be sorted so we can compute its median
 median_data= gsl_stats_median_from_sorted_data( sorted_data, 1, n );

 for ( i= 0; i < n; i++ ) {
  sorted_data[i]= fabs( sorted_data[i] - median_data );
 }
 gsl_sort( sorted_data, 1, n );
 MAD= gsl_stats_median_from_sorted_data( sorted_data, 1, n );

 return MAD;

 // // 1.48260221850560 = 1/norminv(3/4)
 // sigma= 1.48260221850560 * MAD;
 // return sigma;
}
double esimate_sigma_from_MAD_of_sorted_data_and_ruin_input_array( double *sorted_data, long n ) {
 double MAD, sigma;
 MAD= compute_MAD_of_sorted_data_and_ruin_input_array( sorted_data, n );
 // 1.48260221850560 = 1/norminv(3/4)
 sigma= 1.48260221850560 * MAD;
 return sigma;
}

// https://en.wikipedia.org/wiki/Unbiased_estimation_of_standard_deviation
double c4( int n ) {
 double c4_result;
 double double_n;

 if ( n < 2 ) {
  // I'll silance this warning, but really something is not OK if it appears
  // fprintf(stderr,"WARINING computing c4(%d): the function argument should be > 2\n",n);
  return 1.0;
 }

 double_n= (double)n;

 if ( double_n / 2.0 > GSL_SF_GAMMA_XMAX )
  return 1.0;
 c4_result= sqrt( 2.0 / ( double_n - 1.0 ) ) * gsl_sf_gamma( double_n / 2.0 ) / gsl_sf_gamma( ( double_n - 1.0 ) / 2.0 );

 return c4_result;
}

// https://en.wikipedia.org/wiki/Unbiased_estimation_of_standard_deviation
double unbiased_estimation_of_standard_deviation_assuming_Gaussian_dist( double *sample, int n ) {
 double sample_sigma;

 // Basic check of the input
 if ( n < 2 )
  return 0.0;
 if ( NULL == sample ) {
  fprintf( stderr, "ERROR in esimate_population_sigma_correcting_the_sample_sigma_assuming_Gaussian_dist() NULL==sample\n" );
  return 0.0;
 }

 sample_sigma= gsl_stats_sd( sample, 1, n );

 // Function: double gsl_sf_gamma (double x)
 // These routines compute the Gamma function \Gamma(x), subject to x not being a negative integer or zero.
 // The function is computed using the real Lanczos method. The maximum value of x such that \Gamma(x) is not
 // considered an overflow is given by the macro GSL_SF_GAMMA_XMAX and is 171.0.
 if ( (double)n / 2.0 > GSL_SF_GAMMA_XMAX )
  return sample_sigma; // do not apply the correction if it can't be computed: it's small anyhow

 return gsl_stats_sd( sample, 1, n ) / c4( n );
}

double N3_consecutive_samesign_deviations_in_sorted_lightcurve( size_t *input_array_index_p, double *input_m, int input_Nobs ) {
#ifdef DISABLE_INDEX_N3
 return 0.0;
#endif

 int i;     // a counter
 int N3= 0; // the result

 double *data; // array to compute median

 double median;              // median magnitude of the lightcurve
 double mad_scaled_to_sigma; // MAD scaled to sigma

 data= malloc( input_Nobs * sizeof( double ) );
 if ( data == NULL ) {
  fprintf( stderr, "ERROR allocating memory for data array in variability_indexes.c\n" );
  exit( EXIT_FAILURE );
 }

 for ( i= 0; i < input_Nobs; i++ ) {
  data[i]= input_m[i];
 }
 gsl_sort( data, 1, i );
 median= gsl_stats_median_from_sorted_data( data, 1, i );
 mad_scaled_to_sigma= esimate_sigma_from_MAD_of_sorted_data( data, i );
 free( data );

 // count triplets
 for ( i= 2; i < input_Nobs; i++ ) {
  if ( input_m[input_array_index_p[i]] - median > N3_SIGMA * mad_scaled_to_sigma && input_m[input_array_index_p[i - 1]] - median > N3_SIGMA * mad_scaled_to_sigma && input_m[input_array_index_p[i - 2]] - median > N3_SIGMA * mad_scaled_to_sigma )
   N3++;
  if ( median - input_m[input_array_index_p[i]] > N3_SIGMA * mad_scaled_to_sigma && median - input_m[input_array_index_p[i - 1]] > N3_SIGMA * mad_scaled_to_sigma && median - input_m[input_array_index_p[i - 2]] > N3_SIGMA * mad_scaled_to_sigma )
   N3++;
 }

#ifdef DEBUGFILES
 fprintf( stderr, "DEBUG N3: median=%lf mad_scaled_to_sigma=%lf N3=%d\n", median, mad_scaled_to_sigma, N3 );
#endif

 return (double)N3 / (double)( input_Nobs - 2 );
 // return (double)N3;
}

double lag1_autocorrelation_of_unsorted_lightcurve( double *JD, double *m, int N ) {
#ifdef DISABLE_INDEX_LAG1_AUTOCORRELATION
 return 0.0;
#endif

 int i;
 double result;
 double *data_x;
 double *data_y;

 data_x= malloc( N * sizeof( double ) );
 if ( data_x == NULL ) {
  fprintf( stderr, "MEMORY ERROR!\n" );
  exit( EXIT_FAILURE );
 }
 data_y= malloc( N * sizeof( double ) );
 if ( data_y == NULL ) {
  fprintf( stderr, "MEMORY ERROR!\n" );
  exit( EXIT_FAILURE );
 }

 for ( i= 0; i < N; i++ ) {
  data_x[i]= JD[i];
  data_y[i]= m[i];
 }

 gsl_sort2( data_x, 1, data_y, 1, N );
 result= gsl_stats_lag1_autocorrelation( m, 1, i );

 free( data_y );
 free( data_x );

 return result;
}

double detect_excursions_in_sorted_lightcurve( size_t *p, double *JD, double *m, double *merr, int N_points_in_lightcurve ) {
#ifdef DISABLE_INDEX_EXCURSIONS
 return 0.0;
#endif

 double result= 0.0;
 int i, j, n_scan, n_scan_alloc; // counters
 double **scan_mag;
 double **scan_err;
 double **scan_w;
 double *test_results_for_pairs_of_scans;
 int scan_pair;

 double *data;

 int *points_in_scans;

 int scan_stop= 0;

 // Stuff for mean comparison
 double mean1, sigma1, mean2, sigma2;

 points_in_scans= malloc( N_points_in_lightcurve * sizeof( int ) );
 if ( points_in_scans == NULL ) {
  fprintf( stderr, "MEMORY ERROR!\n" );
  exit( EXIT_FAILURE );
 }

 data= malloc( N_points_in_lightcurve * sizeof( double ) );
 if ( data == NULL ) {
  fprintf( stderr, "MEMORY ERROR!\n" );
  exit( EXIT_FAILURE );
 }

 n_scan_alloc= N_points_in_lightcurve; // We assume that there will be no more scans than points in a lightcurve

 scan_mag= malloc( n_scan_alloc * sizeof( double * ) );
 if ( scan_mag == NULL ) {
  fprintf( stderr, "MEMORY ERROR!\n" );
  exit( EXIT_FAILURE );
 }

 scan_err= malloc( n_scan_alloc * sizeof( double * ) );
 if ( scan_err == NULL ) {
  fprintf( stderr, "MEMORY ERROR!\n" );
  exit( EXIT_FAILURE );
 }

 scan_w= malloc( n_scan_alloc * sizeof( double * ) );
 if ( scan_w == NULL ) {
  fprintf( stderr, "MEMORY ERROR!\n" );
  exit( EXIT_FAILURE );
 }

 for ( i= 0; i < n_scan_alloc; i++ ) {
  scan_mag[i]= malloc( N_points_in_lightcurve * sizeof( double ) );
  if ( scan_mag[i] == NULL ) {
   fprintf( stderr, "MEMORY ERROR!\n" );
   exit( EXIT_FAILURE );
  }
  scan_err[i]= malloc( N_points_in_lightcurve * sizeof( double ) );
  if ( scan_err[i] == NULL ) {
   fprintf( stderr, "MEMORY ERROR!\n" );
   exit( EXIT_FAILURE );
  }
  scan_w[i]= malloc( N_points_in_lightcurve * sizeof( double ) );
  if ( scan_w[i] == NULL ) {
   fprintf( stderr, "MEMORY ERROR!\n" );
   exit( EXIT_FAILURE );
  }
 }

 // Form scans
 for ( n_scan= 0, i= 0; i < N_points_in_lightcurve; i++ ) {
  scan_stop= 0;
#ifdef DEBUGFILES
  fprintf( stderr, "__ Scan %3d, point %3d out of %d __\n", n_scan, i, N_points_in_lightcurve );
  fprintf( stderr, "########### Scan %3d ###########\n#### Point %3d %lf %lf ####\n", n_scan, i, m[p[i]], merr[p[i]] );
#endif
  for ( j= i; j < N_points_in_lightcurve + 1; j++ ) {
   // fprintf(stderr,"considering j=%d\n",j);
   //  Check if this should be the end of the scan?
   if ( j == N_points_in_lightcurve ) {
    scan_stop= 1;
   } else {
    // Check this only if this is not the last point in the lightcurve!!!
    if ( JD[p[j]] - JD[p[i]] > EXCURSIONS_GAP_BETWEEN_SCANS_DAYS ) {
     scan_stop= 1;
    }
   }
   if ( scan_stop == 1 ) {
    // fprintf(stderr,"stop\n");
    points_in_scans[n_scan]= j - i; // save number of points in this scan for future use
#ifdef DEBUGFILES
    fprintf( stderr, "-------- %3d points in this scan --------\n", points_in_scans[n_scan] );
#endif
    n_scan++; // increase the scan counter by one
    i= j - 1; // jump to the next point
    break;
   }
   // fprintf(stderr,"continue\n");
   //  Save the point to a scan
   scan_mag[n_scan][j - i]= m[p[j]];
   scan_err[n_scan][j - i]= merr[p[j]];
#ifdef DEBUGFILES
   fprintf( stderr, "%lf %lf  %d %d\n", scan_mag[n_scan][j - i], scan_err[n_scan][j - i], j - i, j );
#endif
  }
 }

 // For each pair of scans, conduct the test
 test_results_for_pairs_of_scans= malloc( n_scan * n_scan * sizeof( double ) );
 if ( test_results_for_pairs_of_scans == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for test_results_for_pairs_of_scans\n" );
  exit( EXIT_FAILURE );
 };
 scan_pair= 0;
 for ( i= 0; i < n_scan; i++ ) {
  // First scan
  if ( points_in_scans[i] < 2 ) {
   mean1= scan_mag[i][0];
   sigma1= scan_err[i][0];
  } else {
   gsl_sort( scan_mag[i], 1, points_in_scans[i] );
   mean1= gsl_stats_median_from_sorted_data( scan_mag[i], 1, points_in_scans[i] );
   // our best estimate of sigma will be either MAD scaled to sigma (if we have many points) or max estimated error (fallback if we have only a couple of points)
   sigma1= MAX( esimate_sigma_from_MAD_of_sorted_data( scan_mag[i], points_in_scans[i] ), gsl_stats_max( scan_err[i], 1, points_in_scans[i] ) );
  }

#ifdef DEBUGFILES
  fprintf( stderr, "SCAN %3d:  mean1= %lf sigma1= %lf \n", i, mean1, sigma1 );
#endif

  for ( j= i + 1; j < n_scan; j++ ) {
   // Second scan
   if ( points_in_scans[j] ) {
    mean2= scan_mag[j][0];
    sigma2= scan_err[j][0];
   } else {
    gsl_sort( scan_mag[j], 1, points_in_scans[j] );
    mean2= gsl_stats_median_from_sorted_data( scan_mag[j], 1, points_in_scans[j] );
    sigma2= MAX( esimate_sigma_from_MAD_of_sorted_data( scan_mag[j], points_in_scans[j] ), gsl_stats_max( scan_err[j], 1, points_in_scans[j] ) );
   }

   test_results_for_pairs_of_scans[scan_pair]= fabs( mean1 - mean2 ) / sqrt( sigma1 * sigma1 + sigma2 * sigma2 );

   scan_pair++;
  }
 }

 // Find the best
 result= gsl_stats_mean( test_results_for_pairs_of_scans, 1, scan_pair );

#ifdef DEBUGFILES
 fprintf( stderr, "Excursions: %lf\n", result );
#endif

 free( test_results_for_pairs_of_scans );

 for ( i= 0; i < n_scan_alloc; i++ ) {
  free( scan_w[i] );
  free( scan_err[i] );
  free( scan_mag[i] );
 }
 free( scan_w );
 free( scan_err );
 free( scan_mag );

 free( data );

 free( points_in_scans );

 return result;
}

// p is the array index
double vonNeumann_ratio_eta_from_sorted_lightcurve( size_t *p, double *m, int N_points_in_lightcurve ) {
#ifdef DISABLE_INDEX_VONNEUMANN_RATIO
 return 0.0;
#endif
 double eta;
 double delta_squared, variance;
 int i; // just a counter

 if ( N_points_in_lightcurve < 2 ) {
  fprintf( stderr, "ERROR in vonNeumann_ratio_eta_from_sorted_lightcurve(): N_points_in_lightcurve=%d<2\n", N_points_in_lightcurve );
  return -100500.0;
 }

 variance= gsl_stats_variance( m, 1, N_points_in_lightcurve );

 // fprintf(stderr,"vonNeumann_ratio: sqrt(variance)=%lf\n", sqrt(variance) );

 for ( delta_squared= 0.0, i= 0; i < N_points_in_lightcurve - 1; i++ ) {
  delta_squared+= ( m[p[i + 1]] - m[p[i]] ) * ( m[p[i + 1]] - m[p[i]] );
 }
 delta_squared= delta_squared / (double)( N_points_in_lightcurve - 1 );

 eta= delta_squared / variance;

 return eta;
}

double excess_Abbe_value_from_sorted_lightcurve( size_t *p, double *JD, double *m, int N_points_in_lightcurve ) {
#ifdef DISABLE_INDEX_EXCESS_ABBE_E_A
 return 0.0;
#endif
 double E_A;   // the excess Abbe value
 double A;     // the Abbe value (eta/2) for the whole lightcurve
 double Asub;  // the Abbe value (eta/2) for a section of the lightcurve
 double DT;    //  the overall duration of time series
 double DTsub; // determines the minimum timescale of variability that may be detected
 // double DTsub_div_2; // =DTsub/2.0

 int i, j; // counters

 int number_of_subsamples;
 int Nsub;               // nuber of points in a section of the lightcurve
 double *JD_for_Asub;    // array to store dates of the lightcurve subsection
 double *m_for_Asub;     // array to store the lightcurve subsection
 size_t *index_for_Asub; // index to sort the lightcurve subsection

 if ( N_points_in_lightcurve < 2 ) {
  fprintf( stderr, "ERROR in excess_Abbe_value_from_sorted_lightcurve(): N_points_in_lightcurve=%d<2\n", N_points_in_lightcurve );
  return -100500.0;
 }

 JD_for_Asub= malloc( N_points_in_lightcurve * sizeof( double ) );
 if ( JD_for_Asub == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for JD_for_Asub\n" );
  exit( EXIT_FAILURE );
 };
 m_for_Asub= malloc( N_points_in_lightcurve * sizeof( double ) );
 if ( m_for_Asub == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for m_for_Asub\n" );
  exit( EXIT_FAILURE );
 };
 index_for_Asub= malloc( N_points_in_lightcurve * sizeof( size_t ) );
 if ( index_for_Asub == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for index_for_Asub\n" );
  exit( EXIT_FAILURE );
 };
 // fake the index! We rely on the input lightcurve to be sorted
 for ( i= 0; i < N_points_in_lightcurve; i++ )
  index_for_Asub[i]= i;

 A= vonNeumann_ratio_eta_from_sorted_lightcurve( p, m, N_points_in_lightcurve ) / 2.0;

 DT= JD[p[N_points_in_lightcurve - 1]] - JD[p[0]];
 DTsub= 10.0 * DT / (double)N_points_in_lightcurve;
 if ( DTsub > DT / 3.0 )
  DTsub= DT / 3.0;
#ifdef DEBUGFILES
 fprintf( stderr, "#### DTsub=%lf DT=%lf\n", DTsub, DT );
#endif
 // DTsub_div_2=DTsub/2.0;

 // for each point
 for ( E_A= 0.0, number_of_subsamples= 0, i= 0; i < N_points_in_lightcurve; i++ ) {
  // select points within +/-DTsub/2.0 of it

  // Calculate Asub for independent time intervals
  // maybe this is not exactly as suggested in the paper?
  // but it makes more sence to average independent values, right?!
  for ( Nsub= 0, j= i; j < N_points_in_lightcurve; j++ ) {
   if ( JD[p[j]] - JD[p[i]] <= DTsub ) {
    m_for_Asub[Nsub]= m[p[j]];
    Nsub++;
   } else {
    i= j - 1;
    break;
   }
  }

  // The alternative way, to have Asub calculated for each point (the Asub values will not be independent of each other)
  /*
  for(Nsub=0,j=0;j<N_points_in_lightcurve;j++){
   // A simple optimizaton considering the lightcurve is index-sorted
   //if( JD[p[i]]-JD[p[j]]>DTsub_div_2 )continue;
   //if( JD[p[j]]-JD[p[i]]>DTsub_div_2 )break;
   //
   if( fabs(JD[p[i]]-JD[p[j]])<=DTsub_div_2 ){
    m_for_Asub[Nsub]=m[p[j]];
    Nsub++;
   } // if( fabs(JD[p[i]]-JD[p[j]])<=DTsub ){
  } // for(j=0,j<N_points_in_lightcurve;j++){
  */
  // Make sure we don't have too small number of points in the lightcurve subsection
  if ( Nsub < 5 )
   continue;
  Asub= vonNeumann_ratio_eta_from_sorted_lightcurve( index_for_Asub, m_for_Asub, Nsub ) / 2.0;
  E_A+= Asub;
#ifdef DEBUGFILES
  fprintf( stderr, "E_A=%lf  Asub=%lf\n", E_A, Asub );
#endif
  number_of_subsamples++;
  // fprintf(stderr,"Asub = %lf  number_of_subsamples = %d  DTsub_div_2=%lf  Afull=%lf\n",Asub,number_of_subsamples,DTsub_div_2,A);
 } // for(E_A=0.0,i=0;i<N_points_in_lightcurve;i++){
 if ( number_of_subsamples > 0 ) {
  E_A= E_A / (double)number_of_subsamples - A;
 } else {
  E_A= 0.0;
 }

 free( index_for_Asub );
 free( m_for_Asub );
 free( JD_for_Asub );

 return E_A;
}

double SB_variability_detection_statistic_of_sorted_lightcurve( size_t *p, double *m, double *merr, int N ) {
#ifdef DISABLE_INDEX_SB
 return 0.0;
#endif

 double SB;
 int i, j; // counter
 int M;    // is the number of groups of time-consecutive residuals of the same sign from a constant-brightness lightcurve model
 double group_sum;
 double mean_mag;

 mean_mag= gsl_stats_mean( m, 1, N );

 for ( SB= 0.0, M= 0, i= 0; i < N; i++ ) {
  group_sum= 0.0;
  for ( j= i; j < N; j++ ) {
   // for(j=i+1;j<N;j++){
#ifdef DEBUGFILES
   fprintf( stderr, "m[p[i]]=%lf  m[p[j]]=%lf  mean_mag=%lf\n", m[p[i]], m[p[j]], mean_mag );
#endif
   if ( sgn( m[p[i]] - mean_mag ) != sgn( m[p[j]] - mean_mag ) || j == N - 1 ) {
    // end of a group
    M++;
    i= j;
// i=j-1; // ???? check that ????
#ifdef DEBUGFILES
    fprintf( stderr, "break\n" );
#endif
    break;
   }
   group_sum+= fabs( m[p[j]] - mean_mag ) / merr[p[j]];
  }
  SB+= group_sum * group_sum;
#ifdef DEBUGFILES
  fprintf( stderr, "### %d %d  SB=%lf\n", M, i, SB );
#endif
 }

 SB= SB / (double)( N * M );

 return SB;
}

double Normalized_excess_variance( double *m, double *merr, int N ) {
#ifdef DISABLE_INDEX_NXS
 return 0.0;
#endif

 int i;              // counter
 double result= 0.0; // result will be stored in this variable
 double mean= 0.0;   // weighted(?) mean magnitude

 // compute mean magnitude
 mean= gsl_stats_mean( m, 1, N );

 // compute the NXS
 for ( i= 0; i < N; i++ ) {
  result+= ( m[i] - mean ) * ( m[i] - mean ) - merr[i] * merr[i];
 }
 result= result / ( (double)N * mean * mean );

 // just in case...
 if ( 0 == vast_isnormal( result ) )
  result= 0.0;

 // PREVENT negative values of NXS
 if ( result < 0.0 )
  result= 0.0;

 return result;
}

double compute_RoMS( double *unsorted_m, double *unsorted_merr, int N ) {
#ifdef DISABLE_INDEX_ROMS
 return 0.0;
#endif

 double out_RoMS; // result will be stored here
 int i;           // counter

 /// And all this is needed to compute median_m
 double median_m; // median mag.

 double *x; // a copy of the input array that will be sorted to compute median

 // allocate memory
 x= malloc( N * sizeof( double ) );
 if ( x == NULL ) {
  fprintf( stderr, "ERROR allocating memory for x in compute_RoMS()\n" );
  exit( EXIT_FAILURE );
 }

 // make a copy of the input dataset
 for ( i= 0; i < N; i++ ) {
  x[i]= unsorted_m[i];
 }
 // sort the copy
 gsl_sort( x, 1, i );
 median_m= gsl_stats_median_from_sorted_data( x, 1, i );
 free( x ); // free-up the memory
 // OK, now we have median_m

 // compute RoMS
 for ( out_RoMS= 0.0, i= 0; i < N; i++ ) {
  // We do this calculation on the unsorted array so we don't need to sort also unsorted_merr together with unsorted_m
  out_RoMS+= fabs( ( unsorted_m[i] - median_m ) / unsorted_merr[i] );
 }
 out_RoMS= out_RoMS / (double)( N - 1 );
 return out_RoMS;
}

double compute_reduced_chi2( double *m, double *merr, int N ) {
 return compute_chi2( m, merr, N ) / (double)( N - 1 );
}

double compute_chi2( double *m, double *merr, int N ) {
 double chi2;   // result will be stored here
 double m_mean; // man magnitude
 int i;         // counter
 m_mean= gsl_stats_mean( m, 1, N );
 for ( chi2= 0.0, i= 0; i < N; i++ ) {
  chi2+= ( m[i] - m_mean ) * ( m[i] - m_mean ) / ( merr[i] * merr[i] );
 }
 return chi2;
}

double compute_peak_to_peak_AGN_v( double *m, double *merr, int N ) {
#ifdef DISABLE_INDEX_PEAK_TO_PEAK_AGN_V
 return 0.0;
#endif
 int i;                                      // counter
 double peak_to_peak_AGN_v;                  // result will be stored here
 double m_minus_sigma_max, m_plus_sigma_min; // extreme mag. values
 m_minus_sigma_max= m[0] - merr[0];
 m_plus_sigma_min= m[0] + merr[0];
 for ( i= 1; i < N; i++ ) {
  if ( m[i] - merr[i] > m_minus_sigma_max )
   m_minus_sigma_max= m[i] - merr[i];
  if ( m[i] + merr[i] < m_plus_sigma_min )
   m_plus_sigma_min= m[i] + merr[i];
 }
 peak_to_peak_AGN_v= ( m_minus_sigma_max - m_plus_sigma_min ) / ( m_minus_sigma_max + m_plus_sigma_min );
 peak_to_peak_AGN_v= peak_to_peak_AGN_v * sgn( m_minus_sigma_max + m_plus_sigma_min ); // make sure the value is positive for both real and negative "instrumental" magnitudes
 return peak_to_peak_AGN_v;
}

// An umbrella-function for the many variability indexes.
// The idea is that we have to index-sort the lightcurve in JD only once and then use
// the index-sorted lightcurve for all the indexes to speed-up computations.
void compute_variability_indexes_that_need_time_sorting( double *input_JD, double *input_m, double *input_merr, int input_Nobs, int input_Nmax, double *output_index_I, double *output_index_J, double *output_index_K, double *output_index_L, double *output_index_J_clip, double *output_index_L_clip, double *output_index_J_time, double *output_index_L_time, double *output_index_I_sign_only, double *N3, double *excursions, double *eta, double *E_A, double *SB ) {
 size_t *p; // for index sorting

 p= malloc( input_Nobs * sizeof( size_t ) ); // allocate memory for the index array
 if ( p == NULL ) {
  fprintf( stderr, "ERROR in variability_indexes.c - cannot allocate memory for p\n" );
  exit( EXIT_FAILURE );
 }

 // Sort the lightcurve in time
 gsl_sort_index( p, input_JD, 1, input_Nobs ); // The elements of p give the index of the array element which would have been stored in that position if the array had been sorted in place. The array data is not changed.

 // Compute the indexes that depand on time-sorting of the lightcurve
 stetson_JKL_from_sorted_lightcurve( p, input_JD, input_m, input_merr, input_Nobs, input_Nmax, DEFAULT_MAX_PAIR_DIFF_SIGMA, 0, output_index_J, output_index_K, output_index_L );
 stetson_JKL_from_sorted_lightcurve( p, input_JD, input_m, input_merr, input_Nobs, input_Nmax, MAX_PAIR_DIFF_SIGMA_FOR_JKL_MAG_CLIP, 0, output_index_J_clip, output_index_K, output_index_L_clip );
 stetson_JKL_from_sorted_lightcurve( p, input_JD, input_m, input_merr, input_Nobs, input_Nmax, DEFAULT_MAX_PAIR_DIFF_SIGMA, 1, output_index_J_time, output_index_K, output_index_L_time );
 ( *output_index_I )= classic_welch_stetson_I_from_sorted_lightcurve( p, input_JD, input_m, input_merr, input_Nobs );
 ( *output_index_I_sign_only )= sign_only_welch_stetson_I_from_sorted_lightcurve( p, input_JD, input_m, input_merr, input_Nobs );
 ( *N3 )= N3_consecutive_samesign_deviations_in_sorted_lightcurve( p, input_m, input_Nobs );
 ( *excursions )= detect_excursions_in_sorted_lightcurve( p, input_JD, input_m, input_merr, input_Nobs );
 ( *eta )= 1.0 / vonNeumann_ratio_eta_from_sorted_lightcurve( p, input_m, input_Nobs );
 ( *E_A )= excess_Abbe_value_from_sorted_lightcurve( p, input_JD, input_m, input_Nobs );
 ( *SB )= SB_variability_detection_statistic_of_sorted_lightcurve( p, input_m, input_merr, input_Nobs );

 free( p ); // free memory for the index array

 return;
}

double compute_median_of_usorted_array_without_changing_it( double *data, int n ) {
 int i;
 double *local_copy_data;
 double median;

 if ( n < 2 ) {
  fprintf( stderr, "ERROR in compute_median_of_usorted_array_without_changing_it(): cannot compute median for only %d points!\n", n );
  return 0.0;
 }

 local_copy_data= malloc( n * sizeof( double ) );
 if ( local_copy_data == NULL ) {
  fprintf( stderr, "ERROR in variability_indexes.c - cannot allocate memory for local_copy_data\n" );
  exit( EXIT_FAILURE );
 }

 for ( i= n; i--; ) {
  local_copy_data[i]= data[i];
 }

 gsl_sort( local_copy_data, 1, n );
 median= gsl_stats_median_from_sorted_data( local_copy_data, 1, n );

 free( local_copy_data );

 return median;
}
