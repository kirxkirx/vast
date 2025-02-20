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
 double input_target_x_pix;
 double input_target_y_pix;
 char sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT];

 if ( argc < 3 ) {
  fprintf( stderr, "Usage: %s input_target_x_pix input_target_y_pix\n", argv[0] );
 }

 input_target_x_pix= atof( argv[1] );
 input_target_y_pix= atof( argv[2] );
 NUMBER= malloc( MAX_NUMBER_OF_STARS * sizeof( int ) );
 if ( NUMBER == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for NUMBER(find_star_in_wcs_catalog.c)\n" );
  exit( EXIT_FAILURE );
 };
 ALPHA_SKY= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( ALPHA_SKY == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for ALPHA_SKY(find_star_in_wcs_catalog.c)\n" );
  exit( EXIT_FAILURE );
 };
 DELTA_SKY= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( DELTA_SKY == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for DELTA_SKY(find_star_in_wcs_catalog.c)\n" );
  exit( EXIT_FAILURE );
 };
 X_IMAGE= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( X_IMAGE == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for X_IMAGE(find_star_in_wcs_catalog.c)\n" );
  exit( EXIT_FAILURE );
 };
 Y_IMAGE= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( Y_IMAGE == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for Y_IMAGE(find_star_in_wcs_catalog.c)\n" );
  exit( EXIT_FAILURE );
 };

 // this might be more stable against corrupted input
 i= 0;
 // while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, stdin ) ) {
 //  if ( 5 != sscanf( sextractor_catalog_string, "%d %lf %lf %lf %lf ", &NUMBER[i], &ALPHA_SKY[i], &DELTA_SKY[i], &X_IMAGE[i], &Y_IMAGE[i] ) ) {
 //   continue;
 //  }
 //  i++;
 // }
 //
 while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, stdin ) ) {
  if ( 5 != sscanf( sextractor_catalog_string, "%d %lf %lf %lf %lf",
                    &NUMBER[i], &ALPHA_SKY[i], &DELTA_SKY[i], &X_IMAGE[i], &Y_IMAGE[i] ) ) {
   continue;
  }

  // Check NUMBER[i]
  if ( NUMBER[i] < 0 ) {
   continue;
  }

  // ALPHA_SKY[i] should be between -360 and 720
  if ( ALPHA_SKY[i] < -360.0 || ALPHA_SKY[i] > 720.0 ) {
   continue;
  }

  // Adjust ALPHA_SKY[i] if needed
  if ( ALPHA_SKY[i] < 0.0 ) {
   ALPHA_SKY[i]+= 360.0;
  } else if ( ALPHA_SKY[i] >= 360.0 ) {
   ALPHA_SKY[i]-= 360.0;
  }

  // DELTA_SKY[i] should be between -90 and 90
  if ( DELTA_SKY[i] < -90.0 || DELTA_SKY[i] > 90.0 ) {
   continue;
  }

  // X_IMAGE[i] and Y_IMAGE[i] should be between -MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK and MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK
  if ( X_IMAGE[i] < -1.0 * MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK || X_IMAGE[i] > MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ||
       Y_IMAGE[i] < -1.0 * MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK || Y_IMAGE[i] > MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
   continue;
  }

  i++;
 }
 //
 for ( j= 0; j < i; j++ ) {
  distance= sqrt( ( input_target_x_pix - X_IMAGE[j] ) * ( input_target_x_pix - X_IMAGE[j] ) + ( input_target_y_pix - Y_IMAGE[j] ) * ( input_target_y_pix - Y_IMAGE[j] ) );
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
  fprintf( stderr, "ERROR: cannot find a star near the specified position x=%lf y=%lf\n", input_target_x_pix, input_target_y_pix );
  return 1;
 }

 return 0;
}
