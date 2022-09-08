/*

   Exclude bad regions on image (described in bad_region.lst) from consideration.

 */

#define EXCLUDE_N_PIXELS_AROUND_BAD_POINT 1.0

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <ctype.h> // for isalpha()

#include "vast_limits.h" // for MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE

#include "count_lines_in_ASCII_file.h" // for count_lines_in_ASCII_file()

int read_bad_lst(double *X1, double *Y1, double *X2, double *Y2, int *N) {

 char str[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 int str_len; // string length
 int max_index_for_comments_check;
 int i; // counter
 int max_N_bad_regions_for_malloc;

 double tmp_double;
 FILE *badfile;

 (*N)= 0;

 // we assume this is how many elements were allocated for X1, Y1, X2, Y2 arrays outside of this function
 max_N_bad_regions_for_malloc= 1 + count_lines_in_ASCII_file("bad_region.lst");

 badfile= fopen("bad_region.lst", "r");
 if( badfile == NULL ) {
  fprintf(stderr, "WARNING: Cannot open bad_region.lst \n");
  return 0; // it should not be a fatal error!
 }

 //fprintf( stderr, "Reading bad_region.lst \n" );
 //while ( -1 < fscanf( badfile, "%lf %lf %lf %lf", &X1[( *N )], &Y1[( *N )], &X2[( *N )], &Y2[( *N )] ) ) {
 while( NULL != fgets(str, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, badfile) ) {

  str[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE - 1]= '\0'; // just in case

  //fprintf( stderr, "%s", str );

  // exclude comments (based on lightcurve_io.h)
  // Get string length
  str_len= strlen(str);
  if( str_len < 3 ) {
   continue;
  } // assume that a string shorter than 3 bytes will contain no useful information
  max_index_for_comments_check= MIN(str_len, 10);
  // Check if there are comments in the first 10 bytes of this string
  // If there are, assume this string contains no useful data
  for( i= 0; i < max_index_for_comments_check; i++ ) {
   // in most cases we expect the first symbol of the string to be a comment mark
   if( str[i] == '#' ) {
    str[i]= '\0';
    break;
   }
   if( str[i] == '%' ) {
    str[i]= '\0';
    break;
   }
   if( str[i] == '/' ) {
    str[i]= '\0';
    break;
   }
   if( 0 != isalpha(str[i]) ) {
    str[i]= '\0';
    break;
   }
  }
  // re-check string length after removing comments
  // Get string length
  str_len= strlen(str);
  if( str_len < 3 ) {
   continue;
  } // assume that a string shorter than 3 bytes will contain no useful information

  // Now let's parse the string

  // first - try the usual format lower-left corner upper-right corner
  if( 4 != sscanf(str, "%lf %lf %lf %lf", &X1[(*N)], &Y1[(*N)], &X2[(*N)], &Y2[(*N)]) ) {
   // if that didn't work, try the new format - bad point X and Y
   if( 2 == sscanf(str, "%lf %lf", &X1[(*N)], &Y1[(*N)]) ) {
    // exclude a EXCLUDE_N_PIXELS_AROUND_BAD_POINT-pix region around the specified point
    X2[(*N)]= X1[(*N)] + EXCLUDE_N_PIXELS_AROUND_BAD_POINT;
    Y2[(*N)]= Y1[(*N)] + EXCLUDE_N_PIXELS_AROUND_BAD_POINT;
    X1[(*N)]= X1[(*N)] - EXCLUDE_N_PIXELS_AROUND_BAD_POINT;
    Y1[(*N)]= Y1[(*N)] - EXCLUDE_N_PIXELS_AROUND_BAD_POINT;
    //fprintf( stderr, "Parsed as a bad spot, excluding rectangle: %.1lf %.1lf %.1lf %.1lf\n", X1[( *N )], Y1[( *N )], X2[( *N )], Y2[( *N )]);
   } else {
    // if this didn't work - something is wrong with that particular string
    //fprintf( stderr, "Cannot parse this string\n" );
    continue;
   }
  } else {
   //fprintf( stderr, "Parsed as two corners of a rectangle: %.1lf %.1lf %.1lf %.1lf\n", X1[( *N )], Y1[( *N )], X2[( *N )], Y2[( *N )]);
  }

  // Make sure the corners are in the correct order
  if( X1[(*N)] > X2[(*N)] ) {
   tmp_double= X2[(*N)];
   X2[(*N)]= X1[(*N)];
   X1[(*N)]= tmp_double;
  }
  if( Y1[(*N)] > Y2[(*N)] ) {
   tmp_double= Y2[(*N)];
   Y2[(*N)]= Y1[(*N)];
   Y1[(*N)]= tmp_double;
  }
  //

  // Don't print example region from bad_region.lst - 0 0 0 0
  if( X1[(*N)] != 0.0 || Y1[(*N)] != 0.0 || X2[(*N)] != 0.0 || Y2[(*N)] != 0.0 ) {
   fprintf(stderr, "Excluding image region: %7.1lf %7.1lf %7.1lf %7.1lf  (defined in bad_region.lst)\n", X1[(*N)], Y1[(*N)], X2[(*N)], Y2[(*N)]);
  }
  (*N)+= 1;

  // Check that we are not out of memory yet
  if( (*N) >= max_N_bad_regions_for_malloc ) {
   fprintf(stderr, "ERROR: we reached max_N_bad_regions_for_malloc=%d\n", max_N_bad_regions_for_malloc);
   break;
  }
 }
 fclose(badfile);
 //fprintf( stderr, "Done reading bad_region.lst \n" );
 return 0;
}

int exclude_region(double *X1, double *Y1, double *X2, double *Y2, int N, double X, double Y, double aperture) {
 int i;
 for( i= 0; i < N; i++ ) {
  if( X + aperture / 2.0 >= X1[i] && Y + aperture / 2.0 >= Y1[i] && X - aperture / 2.0 <= X2[i] && Y - aperture / 2.0 <= Y2[i] ) {
   fprintf(stderr, "The star %9.3lf %9.3lf is rejected, see bad_region.lst\n", X, Y);
   return 1;
  }
 }
 return 0;
}
