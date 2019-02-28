#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>

#include "vast_limits.h"

#include "lightcurve_io.h"

int main( int argc, char **argv ) {
 DIR *dp;
 struct dirent *ep;

 FILE *lightcurvefile;
 FILE *outlightcurvefile;
 double jd, mag, merr, x, y, app;
 char string[FILENAME_LENGTH];
 char comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 if ( argc >= 2 && 0 == strcmp( "-h", argv[1] ) ) {
  fprintf( stderr, "Clean out*dat files from \"nan\" values.\n" );
  fprintf( stderr, "Usage:\n" );
  fprintf( stderr, "%s\n", argv[0] );
  exit( 0 );
 }

 dp= opendir( "./" );
 if ( dp != NULL ) {
  fprintf( stderr, "Wiping out bad (nan) measurements... " );
  while ( ( ep= readdir( dp ) ) != NULL ) {
   if ( strlen( ep->d_name ) < 8 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {
    lightcurvefile= fopen( ep->d_name, "r" );
    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     exit( 1 );
    }
    outlightcurvefile= fopen( "lightcurve.tmp", "w" );
    if ( NULL == outlightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file lightcurve.tmp\n" );
     exit( 1 );
    }
    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, comments_string ) ) {
     if ( jd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     if ( 0 == isnan( jd ) && 0 == isnan( mag ) && 0 == isnan( merr ) && 0 == isnan( x ) && 0 == isnan( y ) && 0 == isnan( app ) ) {
      //fprintf(outlightcurvefile,"%.5lf %8.5lf %.5lf %8.3lf %8.3lf %4.1lf %s\n",jd,mag,merr,x,y,app,string);
      write_lightcurve_point( outlightcurvefile, jd, mag, merr, x, y, app, string, comments_string );
     }
    }
    fclose( outlightcurvefile );
    fclose( lightcurvefile );
    unlink( ep->d_name );                   /* delete old lightcurve file */
    rename( "lightcurve.tmp", ep->d_name ); /* move lightcurve.tmp to lightcurve file */
   }
  }
  (void)closedir( dp );
 } else {
  perror( "Couldn't open the directory\n" );
 }

 fprintf( stderr, "done!  =)\n" );

 return 0;
}
