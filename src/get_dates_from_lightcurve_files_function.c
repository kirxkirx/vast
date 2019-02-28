/*
#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>


#include "vast_limits.h"
#include "lightcurve_io.h"
*/

#include "get_dates_from_lightcurve_files_function.h"

void write_fake_log_file( double *jd, int *Nobs ) {
 int i;
 FILE *logfile;
 fprintf( stderr, "Writing fake vast_image_details.log ... " );
 logfile= fopen( "vast_image_details.log", "w" );
 if ( logfile == NULL ) {
  fprintf( stderr, "ERROR: Couldn't create file vast_image_details.log\n" );
  exit( 1 );
 };
 for ( i= 0; i < ( *Nobs ); i++ )
  fprintf( logfile, "JD= %.5lf\n", jd[i] );
 fclose( logfile );
 fprintf( stderr, "done\n" );
 return;
}

void get_dates_from_lightcurve_files( double *jd, int *Nobs ) {
 DIR *dp;
 struct dirent *ep;
 FILE *lightcurvefile;
 double _jd, mag, merr, x, y, app;
 char string[FILENAME_LENGTH];
 int i, date_found;

 ( *Nobs )= 0;

 dp= opendir( "./" );
 if ( dp != NULL ) {
  fprintf( stderr, "Extracting list of Julian Days from lightcurves... " );
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
    //while(-1<fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&_jd,&mag,&merr,&x,&y,&app,string)){
    while ( -1 < read_lightcurve_point( lightcurvefile, &_jd, &mag, &merr, &x, &y, &app, string, NULL ) ) {
     if ( _jd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     date_found= 0;
     for ( i= 0; i < ( *Nobs ); i++ ) {
      if ( _jd == jd[i] ) {
       date_found= 1;
       break;
      }
     }
     if ( date_found == 0 ) {
      jd[( *Nobs )]= _jd;
      ( *Nobs )+= 1;
     }
    }
    fclose( lightcurvefile );
   }
  }
  (void)closedir( dp );
  fprintf( stderr, "done\n" );
 } else
  perror( "Couldn't open the directory\n" );

 /* Write a fake log file so we don't need to read all the lightcurves next time */
 write_fake_log_file( jd, Nobs );

 return;
}

void get_dates( double *jd, int *Nobs ) {
 FILE *vastlogfile;
 char str[MAX_LOG_STR_LENGTH];
 char jd_str[MAX_LOG_STR_LENGTH];
 unsigned int i, j, k;
 ( *Nobs )= 0;
 vastlogfile= fopen( "vast_image_details.log", "r" );
 if ( NULL == vastlogfile ) {
  fprintf( stderr, "WARNING: Can't open vast_image_details.log\n" );
  get_dates_from_lightcurve_files( jd, Nobs );
 } else {
  while ( NULL != fgets( str, MAX_LOG_STR_LENGTH, vastlogfile ) ) {
   for ( i= 0; i < strlen( str ) - 3; i++ )
    if ( str[i] == 'J' && str[i + 1] == 'D' && str[i + 2] == '=' ) {
     for ( j= i + 4, k= 0; str[j] != ' '; j++, k++ ) {
      jd_str[k]= str[j];
     }
     jd[( *Nobs )]= atof( jd_str );
     break;
    }
   ( *Nobs )+= 1;
  }
  fclose( vastlogfile );
  fprintf( stderr, "Total number of observations (from log file) %d\n", ( *Nobs ) );
  return;
 }
 fprintf( stderr, "Total number of observations %d\n", ( *Nobs ) );
 return;
}
