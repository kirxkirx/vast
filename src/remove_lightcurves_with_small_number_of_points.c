#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "vast_limits.h"
#include "lightcurve_io.h"

int main( int argc, char **argv ) {
 DIR *dp;
 struct dirent *ep;

 FILE *lightcurvefile;
 double jd, mag, merr, x, y, app;
 char string[FILENAME_LENGTH];
 int i;

 int min_number_of_points;

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

 dp= opendir( "./" );
 if ( dp != NULL ) {
  fprintf( stderr, "Removing lightcurves with less than %d points... ", min_number_of_points );
  //while( ep = readdir(dp) ){
  while ( ( ep= readdir( dp ) ) != NULL ) {
   if ( strlen( ep->d_name ) < 8 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {

    lightcurvefile= fopen( ep->d_name, "r" );

    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     exit( 1 );
    }

    /* Count observations */
    i= 0;
    //while(-1<fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&merr,&x,&y,&app,string)){
    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, NULL ) ) {
     if ( jd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     i++;
    }
    fclose( lightcurvefile );

    if ( i < min_number_of_points )
     unlink( ep->d_name ); /* delete lightcurve file */
   }
  }
  (void)closedir( dp );
 } else {
  perror( "Couldn't open the directory\n" );
 }

 fprintf( stderr, "done!  =)\n" );

 return 0;
}
