#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_statistics_double.h>

#include <sys/time.h>

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

 double *mag_a= NULL;
 mag_a= malloc( sizeof( double ) );
 if ( mag_a == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for mag_a(remove_points_with_large_errors.c)\n" );
  exit( 1 );
 };
 double median_mag;
 double mag_sigma;
 int i;

 double sigma_filter;

 char lightcurve_tmp_filename[FILENAME_LENGTH];

 if ( argc >= 2 && 0 == strcmp( "-h", argv[1] ) ) {
  fprintf( stderr, "Clean out*dat files from measurements with large errors (sigma clip on estimated error).\n" );
  fprintf( stderr, "Usage:\n" );
  fprintf( stderr, "%s [SIGMA]\n", argv[0] );
  exit( 0 );
 }

 if ( argc == 2 ) {
  sigma_filter= atof( argv[1] );
 } else
  sigma_filter= LIGHT_CURVE_ERROR_FILTER_SIGMA; /* Use default value from vast_limits.h */

 dp= opendir( "./" );
 if ( dp != NULL ) {
  fprintf( stderr, "Removing measurements with large errors (>%.1lf sigma) from lightcurves... ", sigma_filter );
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
    /* Compute median mag & sigma */
    i= 0;
    //while(-1<fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&merr,&x,&y,&app,string)){
    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, comments_string ) ) {
     if ( jd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     mag_a[i]= merr;
     i++;
     mag_a= realloc( mag_a, ( i + 1 ) * sizeof( double ) );
     if ( mag_a == NULL ) {
      fprintf( stderr, "ERROR: Couldn't reallocate memory for mag_array(rescale_photometric_errors.c)\n" );
      exit( 1 );
     };
    }
    fclose( lightcurvefile );
    gsl_sort( mag_a, 1, i );
    median_mag= gsl_stats_median_from_sorted_data( mag_a, 1, i );
    mag_sigma= gsl_stats_sd( mag_a, 1, i );
    // We need to make sure mag_sigma is not too small
    mag_sigma= MAX( mag_sigma, median_mag / 2.0 );
    //fprintf(stderr, "Processing file %s  median_mag=%lf mag_sigma=%lf\n",ep->d_name,median_mag,mag_sigma);
    sprintf( lightcurve_tmp_filename, "lightcurve.tmp" );
    /* Re-open the lightcurve file and choose only good points */
    lightcurvefile= fopen( ep->d_name, "r" );
    outlightcurvefile= fopen( lightcurve_tmp_filename, "w" );
    if ( NULL == outlightcurvefile ) {
     fprintf( stderr, "\nAn ERROR has occured while processing file %s  median_mag=%lf mag_sigma=%lf\n", ep->d_name, median_mag, mag_sigma );
     fprintf( stderr, "ERROR: Can't open file %s\n", lightcurve_tmp_filename );
     exit( 1 );
    }
    //fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&merr,&x,&y,&app,string); /* Never drop the first point! */
    // The while cycle is needed to handle the situation that the first lines are comments
    jd= 0.0;
    while ( jd == 0.0 ) {
     read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, comments_string ); // Never drop the first point!
    }
    //fprintf(outlightcurvefile,"%.5lf %8.5lf %.5lf %8.3lf %8.3lf %4.1lf %s\n",jd,mag,merr,x,y,app,string);
    write_lightcurve_point( outlightcurvefile, jd, mag, merr, x, y, app, string, comments_string );
    //while(-1<fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&merr,&x,&y,&app,string)){
    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, comments_string ) ) {
     if ( jd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     if ( fabs( merr - median_mag ) < sigma_filter * mag_sigma ) {
      //fprintf(outlightcurvefile,"%.5lf %8.5lf %.5lf %8.3lf %8.3lf %4.1lf %s\n",jd,mag,merr,x,y,app,string);
      write_lightcurve_point( outlightcurvefile, jd, mag, merr, x, y, app, string, comments_string );
     }
    }
    fclose( outlightcurvefile );
    fclose( lightcurvefile );
    unlink( ep->d_name );                          /* delete old lightcurve file */
    rename( lightcurve_tmp_filename, ep->d_name ); /* move lightcurve.tmp to lightcurve file */
   }
  }
  (void)closedir( dp );
 } else {
  perror( "Couldn't open the directory\n" );
 }

 free( mag_a );

 fprintf( stderr, "done!  =)\n" );

 return 0;
}
