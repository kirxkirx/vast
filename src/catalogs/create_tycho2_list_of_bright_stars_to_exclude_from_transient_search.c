#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "read_tycho2.h"

int main() {

 double image_boundaries_radec[4];
 long M;
 int N, N_match;
 struct Star *arrStar;
 struct CatStar *arrCatStar;
 N= count_lines_in_ASCII_file( "wcsmag.cat" );
 arrStar= malloc( N * sizeof( struct Star ) );
 if ( arrStar == NULL ) {
  fprintf( stderr, "ERROR: Couldnt allocate memory for arrStar\n" );
  exit( 1 );
 };
 read_sextractor_cat( "wcsmag.cat", arrStar, &N, image_boundaries_radec );
 arrCatStar= malloc( STARS_IN_TYC2 * sizeof( struct CatStar ) );
 if ( arrCatStar == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for arrCatStar\n" );
  exit( 1 );
 };
 read_tycho_cat( arrCatStar, &M, image_boundaries_radec );
 N_match= match_stars_with_catalog( arrStar, N, arrCatStar, M );
 free( arrCatStar );
 free( arrStar );
 fprintf( stderr, "Matched with Tycho-2 %d out of %d detected stars.\n", N_match, N );

 return 0;
}
