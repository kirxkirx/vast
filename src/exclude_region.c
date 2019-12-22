/*

   Exclude bad regions on image (described in bad_region.lst) from consideration.

 */

#include <stdio.h>
#include <stdlib.h>

int read_bad_lst( double *X1, double *Y1, double *X2, double *Y2, int *N ) {
 double tmp_double;
 FILE *badfile;
 ( *N )= 0;
 badfile= fopen( "bad_region.lst", "r" );
 if ( badfile == NULL ) {
  fprintf( stderr, "WARNING: Cannot open bad_region.lst \n" );
  return 0; // it should not be a fatal error!
 }
 while ( -1 < fscanf( badfile, "%lf %lf %lf %lf", &X1[( *N )], &Y1[( *N )], &X2[( *N )], &Y2[( *N )] ) ) {
  if ( X1[( *N )] > X2[( *N )] ) {
   tmp_double= X2[( *N )];
   X2[( *N )]= X1[( *N )];
   X1[( *N )]= tmp_double;
  }
  if ( Y1[( *N )] > Y2[( *N )] ) {
   tmp_double= Y2[( *N )];
   Y2[( *N )]= Y1[( *N )];
   Y1[( *N )]= tmp_double;
  }
  /* Don't print example region from bad_region.lst - 0 0 0 0 */
  if ( X1[( *N )] != 0.0 || Y1[( *N )] != 0.0 || X2[( *N )] != 0.0 || Y2[( *N )] != 0.0 )
   fprintf( stderr, "excluding region: %lf %lf %lf %lf\n", X1[( *N )], Y1[( *N )], X2[( *N )], Y2[( *N )] );
  ( *N )+= 1;
 }
 fclose( badfile );
 return 0;
}

int exclude_region( double *X1, double *Y1, double *X2, double *Y2, int N, double X, double Y, double aperture ) {
 int i;
 for ( i= 0; i < N; i++ ) {
  if ( X + aperture / 2.0 >= X1[i] && Y + aperture / 2.0 >= Y1[i] && X - aperture / 2.0 <= X2[i] && Y - aperture / 2.0 <= Y2[i] ) {
   fprintf( stderr, "The star %lf %lf is rejected, see bad_region.lst\n", X, Y );
   return 1;
  }
 }
 return 0;
}
