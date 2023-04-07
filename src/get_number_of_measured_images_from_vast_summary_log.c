#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sys/types.h>
#include <dirent.h>
#include <unistd.h>

#include "vast_limits.h"
#include "lightcurve_io.h"

// if there is no vast_summary.log file - read all lightcurves to determine the maximum number of observations
int get_number_of_measured_images_from_lightcurves() {
 DIR *dp;
 struct dirent *ep;
 FILE *lightcurvefile;
 int lightcurvefilenamelength;
 // double jd,mag,merr,x,y,app;
 // char string[FILENAME_LENGTH];
 char string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 int i, max_i;

 max_i= 0;

 fprintf( stderr, "WARNING: in get_number_of_measured_images_from_lightcurves(): determining the maximum number of observations from the lightcurves!\n" );

 dp= opendir( "./" );
 if ( dp != NULL ) {
  // while( ep = readdir(dp) ){
  while ( ( ep= readdir( dp ) ) != NULL ) {
   // A naive attempt to optimize - check the first character in the file name
   if ( ep->d_name[0] != 'o' )
    continue;
   lightcurvefilenamelength= strlen( ep->d_name );
   // if( strlen(ep->d_name)<8 )continue; // make sure the filename is not too short for the following tests
   if ( lightcurvefilenamelength < 8 )
    continue; // make sure the filename is not too short for the following tests
   // check the last character in the file name
   if ( ep->d_name[lightcurvefilenamelength - 1] != 't' )
    continue;
   // check the full filename
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[lightcurvefilenamelength - 1] == 't' && ep->d_name[lightcurvefilenamelength - 2] == 'a' && ep->d_name[lightcurvefilenamelength - 3] == 'd' ) {
    lightcurvefile= fopen( ep->d_name, "r" );
    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     exit( EXIT_FAILURE );
    }
    // Count observations
    i= 0;
    // We don't care about this number being precise, so assume there are no comments or bad lines
    while ( NULL != fgets( string, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lightcurvefile ) ) {
     ////while(-1<fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&merr,&x,&y,&app,string))i++;
     // while(-1<read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string)){
     //  if( jd==0.0 )continue; // if this line could not be parsed, try the next one
     i++;
    }
    fclose( lightcurvefile );
    if ( i > max_i )
     max_i= i;
   }
  }
  (void)closedir( dp );
 } else
  perror( "Couldn't open the directory\n" );

 fprintf( stderr, "The maximum number of measurements found among all the lightcurves is %d\n", max_i );

 return max_i;
}

// if there is vast_summary.log - get numer of observations from it
int get_number_of_measured_images_from_vast_summary_log() {
 char str[1024];
 int n= 0;
 FILE *vast_summary_log;
 vast_summary_log= fopen( "vast_summary.log", "r" );
 if ( vast_summary_log != NULL ) {
  if ( 3 == fscanf( vast_summary_log, "%s %s %d", str, str, &n ) ) {
   if ( 5 > fscanf( vast_summary_log, "%s %s %s %s %d", str, str, str, str, &n ) ) {
    fprintf( stderr, "ERROR in get_number_of_measured_images_from_vast_summary_log while parsing vast_summary.log\n" );
   }
  }
  fclose( vast_summary_log );
 }
 if ( n <= 0 || n > MAX_NUMBER_OF_OBSERVATIONS ) {
  fprintf( stderr, "WARNING: in get_number_of_measured_images_from_vast_summary_log(): can't open or parse vast_summary.log\n" );
  n= get_number_of_measured_images_from_lightcurves();
  if ( n == 0 ) {
   fprintf( stderr, "WARNING: cannot determine number of observations from the lightcurves.\nThis is a bad sign...\n" );
   n= MAX_NUMBER_OF_OBSERVATIONS;
  }
  // return n;
 }
 return n;
}
