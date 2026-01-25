#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>

#include <sys/time.h>

#include <gsl/gsl_sort.h>
#include <gsl/gsl_statistics_double.h>

#include "vast_limits.h"
#include "lightcurve_io.h"
#include "quickselect.h" // for quickselect_median_double()

int main( int argc, char **argv ) {

 FILE *lightcurvefile;
 FILE *outlightcurvefile;
 double jd, mag, merr, x, y, app;
 char string[FILENAME_LENGTH];
 char comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 double *mag_a= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( mag_a == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for mag_a(new_lightcurve_sigma_filter.c)\n" );
  exit( EXIT_FAILURE );
 };
 double median_mag;
 double mag_sigma;
 int i;

 double sigma_filter;

 char lightcurve_tmp_filename[FILENAME_LENGTH];

 int sigma_clip_iteration;
 int clipped_points;

 // File name handling
 DIR *dp;
 struct dirent *ep;

 char **filenamelist;
 long filename_counter;
 long filenamelen;

 if ( argc < 2 ) {
  fprintf( stderr, "Clean out*dat files from outliers (sigma clip).\n" );
  fprintf( stderr, "Usage:\n" );
  fprintf( stderr, "%s [SIGMA]\n", argv[0] );
  fprintf( stderr, "%s [SIGMA] file\n", argv[0] );
  exit( EXIT_SUCCESS );
 }

 if ( argc >= 2 ) {
  sigma_filter= atof( argv[1] );
 } else {
  sigma_filter= LIGHT_CURVE_FILTER_SIGMA; // Use default value from vast_limits.h
 }

 filenamelist= (char **)malloc( MAX_NUMBER_OF_STARS * sizeof( char * ) );
 if ( NULL == filenamelist ) {
  fprintf( stderr, "ERROR allocating memory for filenamelist\n" );
  exit( EXIT_FAILURE );
 }
 filename_counter= 0;
 if ( argc == 3 ) {
  // single-file mode
  filenamelen= strlen( argv[2] );
  filenamelist[filename_counter]= malloc( ( filenamelen + 1 ) * sizeof( char ) );
  if ( NULL == filenamelist[filename_counter] ) {
   fprintf( stderr, "ERROR allocating memory for filenamelist[%ld]\n", filename_counter );
   exit( EXIT_FAILURE );
  }
  strncpy( filenamelist[filename_counter], argv[2], ( filenamelen + 1 ) );
  filename_counter++;
 } else {
  // all files mode
  // Populate filenamelist[]
  dp= opendir( "./" );
  if ( dp != NULL ) {
   fprintf( stderr, "Removing (%.1lf sigma) outliers from lightcurves... ", sigma_filter );

   while ( ( ep= readdir( dp ) ) != NULL ) {
    /// For each file
    filenamelen= strlen( ep->d_name );
    if ( filenamelen < 8 ) {
     continue; // make sure the filename is not too short for the following tests
    }
    if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[filenamelen - 1] == 't' && ep->d_name[filenamelen - 2] == 'a' && ep->d_name[filenamelen - 3] == 'd' ) {
     filenamelist[filename_counter]= malloc( ( filenamelen + 1 ) * sizeof( char ) );
     if ( NULL == filenamelist[filename_counter] ) {
      fprintf( stderr, "ERROR allocating memory for filenamelist[%ld]\n", filename_counter );
      exit( EXIT_FAILURE );
     }
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
  //
 }

 // Process each file in the list
 for ( ; filename_counter--; ) {

  for ( sigma_clip_iteration= 0; sigma_clip_iteration < 10; sigma_clip_iteration++ ) {
   clipped_points= 0;

   lightcurvefile= fopen( filenamelist[filename_counter], "r" );
   if ( NULL == lightcurvefile ) {
    fprintf( stderr, "ERROR: Can't open file %s\n", filenamelist[filename_counter] );
    exit( EXIT_FAILURE );
   }

   // Compute median mag & sigma
   i= 0;
   // while(-1<fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&merr,&x,&y,&app,string)){
   while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, comments_string ) ) {
    if ( jd == 0.0 )
     continue; // if this line could not be parsed, try the next one
    mag_a[i]= mag;
    i++;
   }
   fclose( lightcurvefile );
   // Use quickselect for O(n) median computation instead of O(n log n) sort
   median_mag= quickselect_median_double( mag_a, i );
   // Should we try sigma estimated from MAD instead of this????
   mag_sigma= gsl_stats_sd_m( mag_a, 1, i, median_mag );
   sprintf( lightcurve_tmp_filename, "lightcurve.tmp" );
   /* Re-open the lightcurve file and choose only good points */
   lightcurvefile= fopen( filenamelist[filename_counter], "r" );
   if ( NULL == lightcurvefile ) {
    fprintf( stderr, "ERROR: Can't open file %s\n", filenamelist[filename_counter] );
    exit( EXIT_FAILURE );
   }
   outlightcurvefile= fopen( lightcurve_tmp_filename, "w" );
   if ( NULL == outlightcurvefile ) {
    fprintf( stderr, "\nAn ERROR has occurred while processing file %s  median_mag=%lf mag_sigma=%lf\n", filenamelist[filename_counter], median_mag, mag_sigma );
    fprintf( stderr, "ERROR: Can't open file %s\n", lightcurve_tmp_filename );
    exit( EXIT_FAILURE );
   }
   while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, comments_string ) ) {
    if ( jd == 0.0 )
     continue; // if this line could not be parsed, try the next one
    if ( fabs( mag - median_mag ) < sigma_filter * mag_sigma ) {
     write_lightcurve_point( outlightcurvefile, jd, mag, merr, x, y, app, string, comments_string );
    } else {
     clipped_points++;
    }
   }
   fclose( outlightcurvefile );
   fclose( lightcurvefile );
   unlink( filenamelist[filename_counter] );                          /* delete old lightcurve file */
   rename( lightcurve_tmp_filename, filenamelist[filename_counter] ); /* move lightcurve.tmp to lightcurve file */
   if ( clipped_points == 0 )
    break; // stop if we have no more points to clip
  } // iteration

  free( filenamelist[filename_counter] );

 } // if this is out*.dat file

 free( filenamelist );

 free( mag_a );

 fprintf( stderr, "done!  =)\n" );

 return 0;
}
