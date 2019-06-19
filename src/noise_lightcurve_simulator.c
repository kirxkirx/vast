// This program should simulate lightcurves of non-variable stars with noise

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

#define DEFAULT_MEAN_MAG 18.0

#define DEFAULT_NUMBER_OF_LIGHTCURVES_TO_SIMULATE 100
//#define DEFAULT_NUMBER_OF_LIGHTCURVES_TO_SIMULATE 1000
//#define DEFAULT_NUMBER_OF_LIGHTCURVES_TO_SIMULATE 10000

//#define DEFAULT_NUMBER_OF_POINTS_IN_LIGHTCURVE 824
//#define DEFAULT_NUMBER_OF_POINTS_IN_LIGHTCURVE 195
#define DEFAULT_NUMBER_OF_POINTS_IN_LIGHTCURVE 200

#define DEFAULT_JD_START 2457000.00
#define DEFAULT_JD_END DEFAULT_JD_START+10.0*365.0
//#define QASI_REGULAR_SAMPLING
//#define UNIFORM_ERRORS
#define OUTLIERS

#define ERROR_AMPLITUDE 0.1
#define OUTLIERS_MAX_AMP 100*ERROR_AMPLITUDE
#define OUTLIER_PROBABILITY 0.01


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

 int number_of_measurements=DEFAULT_NUMBER_OF_POINTS_IN_LIGHTCURVE;
 int lightcurve_counter,i; // counters

 // JD is the array with dates
 double *JD;
 double *out_mag;
 double *out_magerr;
 
 char simulated_lightcurve_filename[256];
 
 FILE *simulated_lightcurve_file;
 
 if ( argc>1 ){
  number_of_measurements=atof(argv[1]);
  if ( number_of_measurements<1 ){
   fprintf(stderr,"ERROR: incorrect input number of measurements %d\n",number_of_measurements);
   return 1;
  }
 }

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

 /* create a generator chosen by the 
   environment variable GSL_RNG_TYPE */
 gsl_rng_env_setup();

 T= gsl_rng_default;
 r= gsl_rng_alloc( T );

 //gsl_rng_set(r, 2015); // set random seed
 gsl_rng_set( r, random_seed() );


 for(lightcurve_counter=0;lightcurve_counter<DEFAULT_NUMBER_OF_LIGHTCURVES_TO_SIMULATE;lightcurve_counter++){
  sprintf( simulated_lightcurve_filename, "out%05d.dat",lightcurve_counter+1);
  simulated_lightcurve_file=fopen( simulated_lightcurve_filename, "w");
  // Lightcurve simulation 
  for( i= 0; i<number_of_measurements; i++ ){
   #ifdef QASI_REGULAR_SAMPLING
   // Quasi-regular sampling Elias style
   // gsl_rng_uniform( r ); has range 0.0 to 1.0
   timestep= (DEFAULT_JD_END-DEFAULT_JD_START)/number_of_measurements+gsl_rng_uniform( r );
   if( i==0 ){ 
    JD[i]= DEFAULT_JD_START+timestep;
   } else{
    JD[i]= JD[i-1]+timestep;
   }
   #else
   // Random sampling
   JD[i]=DEFAULT_JD_END+(DEFAULT_JD_END-DEFAULT_JD_START)*gsl_rng_uniform( r );
   #endif
   #ifdef UNIFORM_ERRORS
   out_mag[i]=DEFAULT_MEAN_MAG + ERROR_AMPLITUDE*gsl_rng_uniform( r );
   #else
   out_mag[i]=DEFAULT_MEAN_MAG + gsl_ran_gaussian( r, ERROR_AMPLITUDE);
   #endif
   #ifdef OUTLIERS
   // insert outliers only in some lightcurves
   if( OUTLIER_PROBABILITY>gsl_rng_uniform( r ) ){
    // insert an outlier
    out_mag[i]=out_mag[i]+OUTLIERS_MAX_AMP*gsl_rng_uniform( r );
   }
   #endif
   out_magerr[i]=ERROR_AMPLITUDE;
   write_lightcurve_point( simulated_lightcurve_file, JD[i], out_mag[i], out_magerr[i], 100.0, 100.0, 1.0, "test", NULL );
  }
  //
  fclose(simulated_lightcurve_file);   
 }

 gsl_rng_free( r );

 free( JD );
 free( out_mag );
 free( out_magerr );

 return 0;
}
