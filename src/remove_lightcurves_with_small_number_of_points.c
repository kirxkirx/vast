#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "vast_limits.h"
#include "lightcurve_io.h"

int main( int argc, char **argv ) {

 FILE *lightcurvefile;
 // double jd, mag, merr, x, y, app;
 double jd, mag, merr, y, app;
 char string[FILENAME_LENGTH];
 int i;

 int min_number_of_points;

 DIR *dp;
 struct dirent *ep;

 char **filenamelist;
 long filename_counter;
 long filenamelen;

 if ( argc >= 2 && 0 == strcmp( "-h", argv[1] ) ) {
  fprintf( stderr, "Delete out*dat files with too small number of observations.\n" );
  fprintf( stderr, "Usage:\n" );
  fprintf( stderr, "%s [MIN_NUMBER_OF_POINTS]\n", argv[0] );
  exit( 0 );
 }

 if ( argc == 2 ) {
  min_number_of_points= atoi( argv[1] );
 } else
  min_number_of_points= HARD_MIN_NUMBER_OF_POINTS; /* Use default value from vast_limits.h */

 // Create a list of files
 filenamelist= (char **)malloc( MAX_NUMBER_OF_STARS * sizeof( char * ) );
 filename_counter= 0;
 dp= opendir( "./" );
 if ( dp != NULL ) {
  fprintf( stderr, "Removing lightcurves with less than %d points... ", min_number_of_points );
  while ( ( ep= readdir( dp ) ) != NULL ) {
   filenamelen= strlen( ep->d_name );
   if ( filenamelen < 8 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[filenamelen - 1] == 't' && ep->d_name[filenamelen - 2] == 'a' && ep->d_name[filenamelen - 3] == 'd' ) {
    filenamelist[filename_counter]= malloc( ( filenamelen + 1 ) * sizeof( char ) );
    strncpy( filenamelist[filename_counter], ep->d_name, ( filenamelen + 1 ) );
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
   exit( 1 );
  }

  // Count observations
  i= 0;
  // while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, NULL ) ) {
  while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, NULL, &y, &app, string, NULL ) ) {
   if ( jd == 0.0 )
    continue; // if this line could not be parsed, try the next one
   i++;
  }
  fclose( lightcurvefile );

  if ( i < min_number_of_points ) {
   unlink( filenamelist[filename_counter] ); // delete lightcurve file
  }

  free( filenamelist[filename_counter] );
 }

 free( filenamelist );

 fprintf( stderr, "done!  =)\n" );

 return 0;
}
