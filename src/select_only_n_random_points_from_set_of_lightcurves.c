/*

  Select n random points from lightcurves
  
*/

#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <sys/time.h> // for gettimeofday()

#include <gsl/gsl_statistics.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_errno.h>
#include <gsl/gsl_rng.h>
#include <gsl/gsl_randist.h>

#include "vast_limits.h"
#include "lightcurve_io.h"

#include "get_dates_from_lightcurve_files_function.h"

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

 double *input_jd;
 double *selected_jd;
 int N, Nobs;

 int i; // counter

 // File name handling
 DIR *dp;
 struct dirent *ep;
 
 char **filenamelist;
 long filename_counter;
 long filenamelen;

 FILE *lightcurvefile;
 FILE *outlightcurvefile;
 double jd, mag, merr, x, y, app;
 char string[FILENAME_LENGTH];

 char lightcurve_tmp_filename[FILENAME_LENGTH];

 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s N\n where N is the number of points to keep.\n", argv[0] );
  return 1;
 }
 N= atoi( argv[1] );

 /* Read the log file */
 input_jd= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( input_jd == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for input_jd(select_only_n_random_points_from_set_of_light_curves.c)\n" );
  exit( 1 );
 };
 get_dates( input_jd, &Nobs );
 selected_jd= malloc( N * sizeof( double ) );
 if ( selected_jd == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for selected_jd(select_only_n_random_points_from_set_of_light_curves.c)\n" );
  exit( 1 );
 };

 fprintf( stderr, "Keeping only %d randomly selected dates out of %d...\n", N, Nobs );

 if ( N > Nobs ) {
  fprintf( stderr, "Oups, the number of output points should be less or equal to the numer of observations!\n" );
  return 1;
 }
 if ( N < 2 ) {
  fprintf( stderr, "Oups, the number of output points cannot be less than 2.\n" );
  return 1;
 }

 // create a generator chosen by the
 // environment variable GSL_RNG_TYPE
 gsl_rng_env_setup();

 T= gsl_rng_default;
 r= gsl_rng_alloc( T );

 gsl_rng_set( r, random_seed() ); // set random seed

 // This function fills the array dest[k] with k objects taken randomly from the n elements of the array src[0..n-1].
 // The objects are each of size size. The output of the random number generator r is used to make the selection.
 // The algorithm ensures all possible samples are equally likely, assuming a perfect source of randomness.
 // The objects are sampled without replacement, thus each object can only appear once in dest[k].
 // It is required that k be less than or equal to n. The objects in dest will be in the same relative order as those in src.
 // You will need to call gsl_ran_shuffle(r, dest, n, size) if you want to randomize the order.
 gsl_ran_choose( r, selected_jd, N, input_jd, Nobs, sizeof( double ) );

 /*
 for(i=0;i<Nobs;i++){
  fprintf(stderr,"%lf all\n",jd[i]);
 }
*/
 for ( i= 0; i < N; i++ ) {
  fprintf( stderr, "JD%lf is selected for output\n", selected_jd[i] );
 }

 // Create a list of files
 filenamelist= (char **)malloc( MAX_NUMBER_OF_STARS * sizeof( char * ) );
 filename_counter= 0;
 dp= opendir( "./" );
 if ( dp != NULL ) {
  while ( ( ep= readdir( dp ) ) != NULL ) {
   /// For each file
   filenamelen= strlen( ep->d_name );
   if ( filenamelen < 8 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[filenamelen - 1] == 't' && ep->d_name[filenamelen - 2] == 'a' && ep->d_name[filenamelen - 3] == 'd' ) {
    filenamelist[filename_counter]= malloc( (filenamelen+1) * sizeof( char ) );
    strncpy( filenamelist[filename_counter], ep->d_name, (filenamelen+1) );
    filename_counter++;
   }
  }
  (void)closedir( dp );
 } else {
  perror( "Couldn't open the directory" );
  free( filenamelist );
  return 2;
 }


 // Process each file in the list
 for ( ; filename_counter--; ) {

  lightcurvefile= fopen( filenamelist[filename_counter], "r" );
  if ( NULL == lightcurvefile ) {
   fprintf( stderr, "ERROR: Can't open file %s\n", filenamelist[filename_counter] );
   return 1;
  }
  outlightcurvefile= fopen( lightcurve_tmp_filename, "w" );
  if ( NULL == outlightcurvefile ) {
   fprintf( stderr, "ERROR: Can't open file %s\n", lightcurve_tmp_filename );
   return 1;
  }
  while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, NULL ) ) {
   if ( jd == 0.0 )
    continue; // if this line could not be parsed, try the next one
   for ( i= 0; i < N; i++ ) {
    if ( jd == selected_jd[i] ) {
     write_lightcurve_point( outlightcurvefile, jd, mag, merr, x, y, app, string, NULL );
     break;
    }
   } // for(i=0;i<N;i++){
  }
  fclose( outlightcurvefile );
  fclose( lightcurvefile );
  unlink( filenamelist[filename_counter] );                          /* delete old lightcurve file */
  rename( lightcurve_tmp_filename, filenamelist[filename_counter] ); /* move lightcurve.tmp to lightcurve file */
  free( filenamelist[filename_counter] );
 } // if this is out*.dat file
 //////
 
 free( filenamelist );

 free( selected_jd );
 free( input_jd );

 return 0;
}
