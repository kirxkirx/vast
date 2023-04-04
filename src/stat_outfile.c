#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <gsl/gsl_statistics_double.h>
#include <gsl/gsl_errno.h>

#include "vast_limits.h"
#include "lightcurve_io.h"

int main( int argc, char **argv ) {
 FILE *f;
 double jd;
 double MUSOR;
 char strMUSOR[FILENAME_LENGTH];
 double *sigma; //[MAX_NUMBER_OF_STARS];
 double *m;     // [MAX_NUMBER_OF_STARS];
 double m_mean;
 double sigma_mean;
 double sigma_series;
 int i= 0;
 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s outNUMBER.dat\n", argv[0] );
  exit( 1 );
 }

 // allocte memory
 m= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( m == NULL ) {
  fprintf( stderr, "ERROR cannot allocate memory for m\n" );
  return 1;
 }
 sigma= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( sigma == NULL ) {
  fprintf( stderr, "ERROR cannot allocate memory for sigma\n" );
  return 1;
 }

 f= fopen( argv[1], "r" );
 if ( f == NULL ) {
  fprintf( stderr, "ERROR opening lightcurve file %s\n", argv[1] );
  return 1;
 }
 // while( -1<fscanf(f,"%lf %lf %lf %lf %lf %lf %s",&MUSOR,&m[i],&sigma[i],&MUSOR,&MUSOR,&MUSOR,strMUSOR) ){
 while ( -1 < read_lightcurve_point( f, &jd, &m[i], &sigma[i], &MUSOR, &MUSOR, &MUSOR, strMUSOR, NULL ) ) {
  if ( jd == 0.0 )
   continue; // if this line could not be parsed, try the next one
  i++;
 }
 fclose( f );
 m_mean= gsl_stats_mean( m, 1, i );
 sigma_series= gsl_stats_sd_m( m, 1, i, m_mean );
 sigma_mean= gsl_stats_mean( sigma, 1, i );

 free( sigma );
 free( m );

 fprintf( stdout, "%s contains %d observations\nm= %.4lf  sigma_series= %.4lf  mean_sigma=%.4lf \n", argv[1], i, m_mean, sigma_series, sigma_mean );

 return 0;
}
