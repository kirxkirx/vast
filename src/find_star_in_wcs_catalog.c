#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>

#include "vast_limits.h"

int main( int argc, char **argv ) {
 int i= 0;
 int j;
 int *NUMBER;
 double *ALPHA_SKY, *DELTA_SKY, *X_IMAGE, *Y_IMAGE;
 double distance;
 double best_distance= 10; // 10 pix
 int best_i= -1;
 double target_RA_deg;
 double target_Dec_deg;
 // char GARBAGE[4096];
 char sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT];

 if ( argc < 3 ) {
  fprintf( stderr, "Usage: %s target_RA_deg target_Dec_deg\n", argv[0] );
 }

 target_RA_deg= atof( argv[1] );
 target_Dec_deg= atof( argv[2] );
 NUMBER= malloc( MAX_NUMBER_OF_STARS * sizeof( int ) );
 if ( NUMBER == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for NUMBER(find_star_in_wcs_catalog.c)\n" );
  exit( 1 );
 };
 ALPHA_SKY= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( ALPHA_SKY == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for ALPHA_SKY(find_star_in_wcs_catalog.c)\n" );
  exit( 1 );
 };
 DELTA_SKY= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( DELTA_SKY == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for DELTA_SKY(find_star_in_wcs_catalog.c)\n" );
  exit( 1 );
 };
 X_IMAGE= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( X_IMAGE == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for X_IMAGE(find_star_in_wcs_catalog.c)\n" );
  exit( 1 );
 };
 Y_IMAGE= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( Y_IMAGE == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for Y_IMAGE(find_star_in_wcs_catalog.c)\n" );
  exit( 1 );
 };

 /*
 while ( -1 < fscanf( stdin, "%d %lf %lf %lf %lf  %[^\t\n]", &NUMBER[i], &ALPHA_SKY[i], &DELTA_SKY[i], &X_IMAGE[i], &Y_IMAGE[i], GARBAGE ) ) {
  i++;
 }
 for ( j= 0; j < i; j++ ) {
  distance= sqrt( ( target_RA_deg - X_IMAGE[j] ) * ( target_RA_deg - X_IMAGE[j] ) + ( target_Dec_deg - Y_IMAGE[j] ) * ( target_Dec_deg - Y_IMAGE[j] ) );
  if ( distance < best_distance ) {
   best_distance= distance;
   best_i= j;
  }
 }
*/
 // this might be more stable against corrupted input
 i= 0;
 while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, stdin ) ) {
  if ( 5 != sscanf( sextractor_catalog_string, "%d %lf %lf %lf %lf ", &NUMBER[i], &ALPHA_SKY[i], &DELTA_SKY[i], &X_IMAGE[i], &Y_IMAGE[i] ) ) {
   continue;
  }
  i++;
 }
 for ( j= 0; j < i; j++ ) {
  distance= sqrt( ( target_RA_deg - X_IMAGE[j] ) * ( target_RA_deg - X_IMAGE[j] ) + ( target_Dec_deg - Y_IMAGE[j] ) * ( target_Dec_deg - Y_IMAGE[j] ) );
  if ( distance < best_distance ) {
   best_distance= distance;
   best_i= j;
  }
 }

 if ( best_i != -1 ) {
  fprintf( stdout, "%lf  %lf\n", ALPHA_SKY[best_i], DELTA_SKY[best_i] );
 }

 free( Y_IMAGE );
 free( X_IMAGE );
 free( DELTA_SKY );
 free( ALPHA_SKY );
 free( NUMBER );

 // Report error if we didn't find the star
 if ( best_i == -1 ) {
  fprintf( stderr, "ERROR: cannot find a star near the specified position x=%lf y=%lf\n", target_RA_deg, target_Dec_deg );
  return 1;
 }

 return 0;
}
