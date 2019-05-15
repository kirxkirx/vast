/// See http://adsabs.harvard.edu/abs/1995A%26A...300..707T

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <libgen.h>   // for basename()
#include <sys/time.h> // for gettimeofday()

#include <gsl/gsl_rng.h>
#include <gsl/gsl_randist.h>

#include <gsl/gsl_statistics.h>

#include "lightcurve_io.h"

//#define MEAN 11.0
//#define ERR 0.02
#define DEFAULT_VAR_AMP 0.5 // default half-amplitude
#define DEFAULT_N_OBS 100
#define DEFAULT_PERIOD 2 * M_PI

#define NUMBER_OF_STARS_TO_SIMULATE 2 // a pair - one variable and one non-variable
                                      // a larger number will result in one variable and many non-variable stars simulated at each realization

#define NUMBER_OF_REALIZATIONS 100

#define N_SPECTRAL_POINTS 10000

// 2 100 10000 - takes ~1 minute to simulate on my latop

unsigned long int random_seed() {
 unsigned int seed;
 struct timeval tv;

 // Opening /dev/random is very slow
 // Use simple time-based random seed instead
 gettimeofday( &tv, 0 );
 seed= tv.tv_sec + tv.tv_usec;

 return ( seed );
}

int main( int argc, char **argv ) {
 const gsl_rng_type *T;
 gsl_rng *r;

 double model_mag;
 int i; // counters

 // JD is the array with dates
 double *JD;
 double *out_mag;
 double *out_magerr;
 double *out_x;
 double *out_y;
 double *out_app;
 char fake_str[FILENAME_LENGTH + 32];

 double *simulated_mag= NULL;

 char outfilename[256];
 FILE *outfile;

 int number_of_measurements= DEFAULT_N_OBS; //default
 double var_half_amp= DEFAULT_VAR_AMP;
 double frequency= 1.0 / DEFAULT_PERIOD;
 double period_days;
 double phase= 0.0;
 //int introduce_outliers=0; // 0 = no, 1 = yes, 2 == sine wave plus power law PSD

 char var_half_amp_string[256];

 // We initialize these to NULL in order to silance the compiler warning '-Wmaybe-uninitialized'
 double *expected_power= NULL;
 double *amplitudes= NULL;
 double *frequencies= NULL;
 double *phases= NULL;

 double max_freq= 1000;
 double min_freq= 0.0001;
 double psd_slope= -1.0;
 double NORM= 0.001;
 int j;
 double log10_max_freq, log10_min_freq;

 double power;
 double model_mean, model_sd;

 int sine_wave_mode_instead_of_psd= 0; // 0 - simulate lightcurve with a given PSD slope
                                       // 1 - simulate sine wave

 int all_random= 0;
 int randomly_choose_sine_or_psd_variability_type= 0;

 if ( 0 == strcmp( "sine_wave_simulator", basename( argv[0] ) ) ) {
  sine_wave_mode_instead_of_psd= 1;
 }
 if ( 0 == strcmp( "sine_wave_and_psd_simulator", basename( argv[0] ) ) ) {
  sine_wave_mode_instead_of_psd= 2;
 }
 if ( 0 == strcmp( "sine_wave_or_psd_simulator", basename( argv[0] ) ) ) {
  //sine_wave_mode_instead_of_psd=2;
  randomly_choose_sine_or_psd_variability_type= 1;
 }

 // Print usage note
 if ( argc < 2 ) {
  fprintf( stderr, "This program will simulate pairs of ligtcurves, one non-variable and one varying with a given power-law PSD or a sine wave.\nUsage:\n %s outNNNNN.dat\n or\n %s outNNNNN.dat peak-to-peak_amplitude [period_in_days_for_periodic]\n", argv[0], argv[0] );
  return 1;
 }

 // Parse the command line arguments
 if ( argc >= 2 ) {
  number_of_measurements= count_points_in_lightcurve_file( argv[1] );
  if ( number_of_measurements < 2 ) {
   fprintf( stderr, "ERROR: something is wrong with the input lightcurve file %s - number_of_measurements = %d < 2 \n", argv[1], number_of_measurements );
   return 1;
  }
 }

 if ( argc >= 3 ) {
  var_half_amp= 0.5 * atof( argv[2] );
  fprintf( stderr, "Setting (peak-to-peak for the sine wave or aperiodic) variability amplitude %.3lf mag.\n", 2.0*var_half_amp );
  if ( argc >= 4 ) {
   period_days= atof( argv[3] );
   if( period_days<=0.0 ){
    fprintf(stderr,"ERROR: incorrect input period!\n");
    return 1;
   }
   frequency= 1.0 / period_days;
  }
 } else {
  fprintf( stderr, "Operating in the random mode!\nRandom amplitude, period and phase!\nOnly a small chance that the input star will be made variable at all!\n" );
  all_random= 1;
 }
 /*
 if( argc>=4 ){
  introduce_outliers=atoi(argv[3]);
 }
 if( argc>=5 ){
  psd_slope=-1.0*atof(argv[4]);
 }
*/


 /* create a generator chosen by the 
   environment variable GSL_RNG_TYPE */
 gsl_rng_env_setup();

 T= gsl_rng_default;
 r= gsl_rng_alloc( T );

 //gsl_rng_set(r, 2015); // set random seed
 gsl_rng_set( r, random_seed() );

 // Now after RNG is initialized we may randomly choose variability type, if needed
 if ( randomly_choose_sine_or_psd_variability_type == 1 ) {
  if ( 0.5 < gsl_rng_uniform( r ) ) {
   sine_wave_mode_instead_of_psd= 1;
  } else {
   sine_wave_mode_instead_of_psd= 0;
  }
 }


 ////////////////////// RANDOM VARIABILITY PARAMETERS SETUP //////////////////////
 if ( all_random == 1 ) {
  // Decide if we want this star to be variable at all
  // 1% probability for this star to be made variable
  if ( 0.01 < gsl_rng_uniform( r ) ) {
   fprintf( stderr, "We are not making this star variable!\n" );
   gsl_rng_free( r ); // de-allocation
   return 1; // exit code is important for the control script
  }
  // Uniform distribution from 0 to 1mag amplitude (peak-to-peak)
  var_half_amp= 0.5 * gsl_rng_uniform( r );
  if ( sine_wave_mode_instead_of_psd != 0 ) {
   // Uniform frequency distribution from 1/0.05 to 1/20 d
   frequency= gsl_ran_flat( r, 0.05, 20.0 );
   phase= gsl_ran_flat( r, 0.0, 2 * M_PI ); // randomize phase
   fprintf( stderr, "Injecting sine variability with the amplitude mag., frequency=%lf c/d, phase=%lf rad!\n", 2*var_half_amp, frequency, phase );
  }
 }
 sprintf( var_half_amp_string, "_amp%.3lfmag", var_half_amp ); // save amplitude for future reference
 /////////////////////////////////////////////////////////////////////////////////

 // We want it after 'all_random' check so we don't do all the malloc'ing 
 // if we don't want to insert simulated variability into the input lightcurve.
 JD= malloc( number_of_measurements * sizeof( double ) );
 if ( JD == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for JD(lighcurve_simulator.c)\n" );
  exit( 1 );
 };
 out_mag= malloc( number_of_measurements * sizeof( double ) );
 if ( out_mag == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for out_mag(lighcurve_simulator.c)\n" );
  exit( 1 );
 };
 out_magerr= malloc( number_of_measurements * sizeof( double ) );
 if ( out_magerr == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for out_magerr(lighcurve_simulator.c)\n" );
  exit( 1 );
 };
 out_x= malloc( number_of_measurements * sizeof( double ) );
 if ( out_x == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for out_x(lighcurve_simulator.c)\n" );
  exit( 1 );
 };
 out_y= malloc( number_of_measurements * sizeof( double ) );
 if ( out_y == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for out_y(lighcurve_simulator.c)\n" );
  exit( 1 );
 };
 out_app= malloc( number_of_measurements * sizeof( double ) );
 if ( out_app == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for out_app(lighcurve_simulator.c)\n" );
  exit( 1 );
 };

 if ( sine_wave_mode_instead_of_psd != 1 ) {
  simulated_mag= malloc( number_of_measurements * sizeof( double ) );
  if ( simulated_mag == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for simulated_mag(lighcurve_simulator.c)\n" );
   exit( 1 );
  };
  expected_power= malloc( N_SPECTRAL_POINTS * sizeof( double ) );
  if ( expected_power == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for expected_power(lighcurve_simulator.c)\n" );
   exit( 1 );
  };
  amplitudes= malloc( N_SPECTRAL_POINTS * sizeof( double ) );
  if ( amplitudes == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for amplitudes(lighcurve_simulator.c)\n" );
   exit( 1 );
  };
  frequencies= malloc( N_SPECTRAL_POINTS * sizeof( double ) );
  if ( frequencies == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for frequencies(lighcurve_simulator.c)\n" );
   exit( 1 );
  };
  phases= malloc( N_SPECTRAL_POINTS * sizeof( double ) );
 }

 // This stuff will be the same for all the realizations
 if ( sine_wave_mode_instead_of_psd != 1 ) {
  log10_max_freq= log10( max_freq );
  log10_min_freq= log10( min_freq );
  for ( j= 0; j < N_SPECTRAL_POINTS; j++ ) {
   // set log-spaced frequencies
   frequencies[j]= pow( 10, log10_min_freq + ( log10_max_freq - log10_min_freq ) / ( (double)N_SPECTRAL_POINTS ) * (double)j );
   // frequencies are now set once for all realizations
   expected_power[j]= NORM * pow( frequencies[j], psd_slope ); // compute expected power from the model power-law PSD
  }
 }

 if ( sine_wave_mode_instead_of_psd != 1 ) {

  // Set frequencies, phases and amplitudes
  for ( j= 0; j < N_SPECTRAL_POINTS; j++ ) {
   // set log-spaced frequencies
   power= 0.5 * expected_power[j] * gsl_ran_chisq( r, 2 ); // randomize power (amplitude)
   if ( power < 0.0 )
    power= 0.0; // just in case
   amplitudes[j]= sqrt( power );
   phases[j]= gsl_ran_flat( r, 0.0, 2 * M_PI ); // randomize phase
   // You may print out the simulated PSD here
   //fprintf(stderr,"%lf %lf %lf\n",frequencies[j],amplitudes[j],phases[j]);
  }
 } else {
  phase= gsl_ran_flat( r, 0.0, 2 * M_PI ); // randomize just phase
 }  // if( sine_wave_mode_instead_of_psd!=1 ){

 /*
  // Generate random sampling pattern
  for(i=0;i<number_of_measurements;i++){
   JD[i]= 2457000.00 + gsl_ran_flat( r, start_day, stop_day);
  }
*/
 // Read the input lightcurve
 strncpy( outfilename, argv[1], OUTFILENAME_LENGTH );
 outfilename[OUTFILENAME_LENGTH - 1]= '\0'; // paranoid
 outfile= fopen( outfilename, "r" );
 i= 0;
 while ( -1 < read_lightcurve_point( outfile, &JD[i], &out_mag[i], &out_magerr[i], &out_x[i], &out_y[i], &out_app[i], fake_str, NULL ) ) {
  if ( JD[i] == 0.0 )
   continue; // if this line could not be parsed, try the next one
  //fprintf(stderr,"DEBUG: %lf %lf %lf\n",JD[i],out_mag[i],out_magerr[i]);
  i++;
 }
 fclose( outfile );

 outfile= fopen( outfilename, "w" );
 if ( outfile == NULL ) {
  fprintf( stderr, "ERROR: Couldn't open file %s(lightcurve_simulator.c)\n", outfilename );
  exit( 1 );
 };
 strncpy( fake_str, "constant", FILENAME_LENGTH );

 if ( sine_wave_mode_instead_of_psd != 1 ) {
  strncat( fake_str, "+psd", FILENAME_LENGTH );
 }
 if ( sine_wave_mode_instead_of_psd != 0 ) {
  strncat( fake_str, "+sine", FILENAME_LENGTH );
 }
 strncpy( fake_str, var_half_amp_string, FILENAME_LENGTH );

 if ( sine_wave_mode_instead_of_psd != 1 ) {

  // For each date compute model mag
  for ( i= 0; i < number_of_measurements; i++ ) {
   simulated_mag[i]= 0.0;
   for ( j= 0; j < N_SPECTRAL_POINTS; j++ ) {
    simulated_mag[i]= simulated_mag[i] + amplitudes[j] * cos( 2 * M_PI * frequencies[j] * ( JD[i] - 2457000.00 ) - phases[j] );
   }
  }
  // Re-normalize lightcurve
  model_sd= gsl_stats_sd( simulated_mag, 1, number_of_measurements );
  for ( i= 0; i < number_of_measurements; i++ ) {
   // https://en.wikipedia.org/wiki/Root_mean_square
   // RMS = var_half_amp / sqrt(2)
   simulated_mag[i]= simulated_mag[i] * var_half_amp / model_sd / M_SQRT2;
  }
  model_mean= gsl_stats_mean( simulated_mag, 1, number_of_measurements );
  for ( i= 0; i < number_of_measurements; i++ ) {
   simulated_mag[i]= simulated_mag[i] - model_mean;
   // + MEAN;
  }

 } // if( sine_wave_mode_instead_of_psd!=1 )

 // For each date compute fake mag
 for ( i= 0; i < number_of_measurements; i++ ) {
  model_mag= out_mag[i]; //MEAN;
  if ( sine_wave_mode_instead_of_psd != 1 ) {
   model_mag= model_mag + simulated_mag[i];
  }
  if ( sine_wave_mode_instead_of_psd != 0 ) {
   model_mag= model_mag + var_half_amp * sin( 2 * M_PI * frequency * ( JD[i] - 2457000.00 ) + phase );
  }
  write_lightcurve_point( outfile, JD[i], model_mag, out_magerr[i], out_x[i], out_y[i], out_app[i], fake_str, NULL );
 }

 fclose( outfile );

 gsl_rng_free( r ); // de-allocation

 if ( sine_wave_mode_instead_of_psd != 1 ) {
  free( simulated_mag );
  free( phases );
  free( frequencies );
  free( amplitudes );
  free( expected_power );
 }

 free( JD );
 free( out_mag );
 free( out_magerr );
 free( out_x );
 free( out_y );
 free( out_app );

 return 0;
}
