// This program will print a good-looking phase ligthcurve repeating measurements at phases > 1 if needed for representation

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <libgen.h> // for basename()

#include <gsl/gsl_statistics.h>
#include <gsl/gsl_sort.h>

#include "vast_limits.h"   // for MAX_NUMBER_OF_OBSERVATIONS
#include "lightcurve_io.h" // for read_lightcurve_point()

void make_fake_phases( double *jd, double *phase, double *m, unsigned int N_obs, unsigned int *N_obs_fake, int phaserangetype ) {

 unsigned int i;

 if ( phaserangetype == 3 ) {
  ( *N_obs_fake )= N_obs;
  return;
 }

 if ( phaserangetype == 2 ) {
  ( *N_obs_fake )= N_obs;
  for ( i= 0; i < N_obs; i++ ) {
   if ( phase[i] >= 0.0 ) {
    phase[( *N_obs_fake )]= phase[i] + 1.0;
    m[( *N_obs_fake )]= m[i];
    jd[( *N_obs_fake )]= jd[i];
    ( *N_obs_fake )++;
   }
  }
  return;
 }

 ( *N_obs_fake )= N_obs;
 for ( i= 0; i < N_obs; i++ ) {
  if ( phase[i] > 0.5 ) {
   phase[( *N_obs_fake )]= phase[i] - 1.0;
   m[( *N_obs_fake )]= m[i];
   jd[( *N_obs_fake )]= jd[i];
   ( *N_obs_fake )++;
  }
 }

 return;
}

void compute_phases( double *jd, double *phase, unsigned int N_obs, double f, double jd0 ) {
 unsigned int i;
 double jdi_over_period;

 for ( i= 0; i < N_obs; i++ ) {
  jdi_over_period= ( jd[i] - jd0 ) * f;
  phase[i]= jdi_over_period - (double)(int)( jdi_over_period );
  if ( phase[i] < 0.0 ) {
   phase[i]+= 1.0;
  }
 }

 return;
}

void bin_lightcurve_in_phase( double *jd, double *phase, double *m, unsigned int *N_obs, unsigned int N_bins ) {
 double *mag_in_bin;
 double *internal_array_phase;
 double *internal_array_binnedmag;
 double *internal_array_binnedmag_sd;
 unsigned int i, j; // counters
 double binwidth= 1.0 / (double)N_bins;
 unsigned int points_in_bin;

 // first handle some special cases
 if ( N_bins > ( *N_obs ) ) {
  fprintf( stderr, "ERROR in bin_lightcurve_in_phase() N_bins>N_obs\n" );
  return;
 }
 if ( N_bins == ( *N_obs ) ) {
  fprintf( stderr, "WARNING from bin_lightcurve_in_phase() N_bins=N_obs, so no binning will be done\n" );
  return;
 }

/*
 internal_array_phase= malloc( N_bins * sizeof( double ) );
 internal_array_binnedmag= malloc( N_bins * sizeof( double ) );
 internal_array_binnedmag_sd= malloc( N_bins * sizeof( double ) );
 
 mag_in_bin= malloc( ( *N_obs ) * sizeof( double ) );

 if ( NULL == internal_array_phase || NULL == internal_array_binnedmag || NULL == internal_array_binnedmag_sd || NULL == mag_in_bin ) {
  fprintf( stderr, "ERROR allocating memory in bin_lightcurve_in_phase()\n" );
  return;
 }
*/

 internal_array_phase= malloc( N_bins * sizeof( double ) );
 if ( NULL == internal_array_phase ) {
  fprintf( stderr, "ERROR allocating memory for internal_array_phase in bin_lightcurve_in_phase()\n" );
  return;
 }

 internal_array_binnedmag= malloc( N_bins * sizeof( double ) );
 if ( NULL == internal_array_binnedmag ) {
  fprintf( stderr, "ERROR allocating memory for internal_array_binnedmag in bin_lightcurve_in_phase()\n" );
  free(internal_array_phase);
  return;
 }

 internal_array_binnedmag_sd= malloc( N_bins * sizeof( double ) );
 if ( NULL == internal_array_binnedmag_sd ) {
  fprintf( stderr, "ERROR allocating memory for internal_array_binnedmag_sd in bin_lightcurve_in_phase()\n" );
  free(internal_array_phase);
  free(internal_array_binnedmag);
  return;
 }

 mag_in_bin= malloc( ( *N_obs ) * sizeof( double ) );
 if ( NULL == mag_in_bin ) {
  fprintf( stderr, "ERROR allocating memory for mag_in_bin in bin_lightcurve_in_phase()\n" );
  free(internal_array_phase);
  free(internal_array_binnedmag);
  free(internal_array_binnedmag_sd);
  return;
 }
 

 for ( j= 0; j < N_bins; j++ ) {
  points_in_bin= 0;
  internal_array_binnedmag[j]= 0.0;
  for ( i= 0; i < ( *N_obs ); i++ ) {
   // if( phase[i]<0.0 )phase[i]+=1.0; // !!!
   //  first/last bin
   if ( j == 0 ) {
    if ( phase[i] <= 0.5 * binwidth || phase[i] > 1.0 - 0.5 * binwidth ) {
     // internal_array_binnedmag[j]+=m[i];
     mag_in_bin[points_in_bin]= m[i];
     points_in_bin++;
    }
    continue;
   } // if first bin
   // case of j=0 is handled above
   if ( phase[i] > 0.5 * binwidth + binwidth * (double)( j - 1 ) && phase[i] <= 0.5 * binwidth + binwidth * (double)j ) {
    // internal_array_binnedmag[j]+=m[i];
    mag_in_bin[points_in_bin]= m[i];
    points_in_bin++;
   }
  } // for each data point
  internal_array_phase[j]= 0.0 + binwidth * (double)j;
  // internal_array_binnedmag[j]= internal_array_binnedmag[j]/(double)points_in_bin;
  internal_array_binnedmag[j]= gsl_stats_mean( mag_in_bin, 1, points_in_bin );
  // gsl_sort(mag_in_bin, 1, points_in_bin);
  // internal_array_binnedmag[j]= gsl_stats_median_from_sorted_data(mag_in_bin, 1, points_in_bin);
  // internal_array_binnedmag_sd[j]= gsl_stats_sd(mag_in_bin, 1, points_in_bin);
  internal_array_binnedmag_sd[j]= gsl_stats_sd( mag_in_bin, 1, points_in_bin ) / sqrt( points_in_bin );
 } // for each bin

 // Replace the input arrays with the binned data
 for ( j= 0; j < N_bins; j++ ) {
  jd[j]= internal_array_binnedmag_sd[j];
  phase[j]= internal_array_phase[j];
  m[j]= internal_array_binnedmag[j];
 }
 ( *N_obs )= N_bins;

 free( mag_in_bin );

 free( internal_array_binnedmag_sd );
 free( internal_array_binnedmag );
 free( internal_array_phase );

 return;
}

int main( int argc, char **argv ) {

 FILE *lightcurvefile;

 unsigned int N_obs, N_obs_fake;
 unsigned int N_bins= 30;
 double *jd;
 double *phase;
 double *m;

 unsigned int i;

 double JD0;
 double period;
 double frequency;

 int phaserangetype= 1;

 // these variables are not used and needed only to correctly interact with read_lightcurve_point()
 double dmerr, dx, dy, dap;
 char filename[FILENAME_LENGTH];
 //

 if ( argc < 4 ) {
  fprintf( stderr, "Usage: %s lightcurve.dat JD0 period\n or\n%s lightcurve.dat JD0 period phase_range_type\nThe phase range type:\n 1 -- -0.5 to 1 (default)\n 2 --  0.0 to 2.0\n 3 --  0.0 to 1.0\nExample: %s out01234.dat 2459165.002 486.61 2\n\nYou may also construct a binned lightcurve with:\nutil/phase_and_bin_lc lightcurve.dat JD0 period phase_range_type number_of_bins\nExample (bin the lightcurve in 10 phase bins): util/phase_and_bin_lc out01234.dat 2459165.002 486.61 2 10\n", argv[0], argv[0], argv[0] );
  return 1;
 }

 // The last argument is either the phase type or the number of bins
 if ( argc == 5 ) {
  N_bins= (unsigned int)atoi( argv[4] );
  if ( N_bins < 5 ) {
   // this is not the number of bins, this is the phase range type
   phaserangetype= atoi( argv[4] );
   if ( phaserangetype < 1 || phaserangetype > 3 ) {
    fprintf( stderr, "WARNING: the phase type is out of range! Falling back to the default.\n" );
    phaserangetype= 1; // check range
   }
  }
 }

 if ( argc > 5 ) {
  // this is not the number of bins, this is the phase range type
  phaserangetype= atoi( argv[4] );
  if ( phaserangetype < 1 || phaserangetype > 3 ) {
   fprintf( stderr, "WARNING: the phase type is out of range! Falling back to the default.\n" );
   phaserangetype= 1; // check range
  }
  N_bins= (unsigned int)atoi( argv[5] );
  if ( N_bins < 5 ) {
   fprintf( stderr, "WARNING: the number of bins is out of range! Falling back to the default.\n" );
   N_bins= 30;
  }
 }

 JD0= atof( argv[2] );

#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
 if ( JD0 < EXPECTED_MIN_MJD ) {
  fprintf( stderr, "ERROR: JD0 is too small!\n" );
  return 1;
 }
 if ( JD0 > EXPECTED_MAX_JD ) {
  fprintf( stderr, "ERROR: JD0 is too large!\n" );
  return 1;
 }
#endif

 period= atof( argv[3] );
 if ( period <= 0.0 ) {
  fprintf( stderr, "ERROR: the period cannot be negative or zero!\n" );
  return 1;
 }
 frequency= 1.0 / period;

 jd= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 phase= malloc( 2 * MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 m= malloc( 2 * MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 
 if ( NULL == jd || NULL == phase || NULL == m ) {
  fprintf(stderr, "ERROR allocating memory in %s\n", argv[0]);
  return 1;
 }
 memset( jd, 0, MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) ); // just in case
 memset( phase, 0, 2 * MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 memset( m, 0, 2 * MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );

 // read the lightcurve from file
 lightcurvefile= fopen( argv[1], "r" );
 if ( NULL == lightcurvefile ) {
  fprintf( stderr, "ERROR in %s cannot open the input lightcurve file %s\n", argv[0], argv[1] );
  free( jd );
  free( phase );
  free( m );
  return 1;
 }
 N_obs= 0;
 while ( -1 < read_lightcurve_point( lightcurvefile, &jd[N_obs], &m[N_obs], &dmerr, &dx, &dy, &dap, filename, NULL ) ) {
  if ( jd[N_obs] == 0.0 ) {
   continue;
  }
  N_obs++;
 }
 fclose( lightcurvefile );

 compute_phases( jd, phase, N_obs, frequency, JD0 );
 //
 if ( 0 == strcmp( "phase_and_bin_lc", basename( argv[0] ) ) ) {
  // make sure we don't have more bins than obs
  N_bins= MIN( N_bins, N_obs );
  bin_lightcurve_in_phase( jd, phase, m, &N_obs, N_bins );
 }
 //
 make_fake_phases( jd, phase, m, N_obs, &N_obs_fake, phaserangetype );

 for ( i= 0; i < N_obs_fake; i++ ) {
  fprintf( stdout, "%+10.7lf %8.4lf %.5lf\n", phase[i], m[i], jd[i] );
 }

 free( jd );
 free( phase );
 free( m );

 return 0;
}
