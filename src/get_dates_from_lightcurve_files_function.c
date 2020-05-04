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
  while ( ( ep= readdir( dp ) ) != NULL ) {
   if ( strlen( ep->d_name ) < 8 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {
    lightcurvefile= fopen( ep->d_name, "r" );
    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     exit( 1 );
    }
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
 } else {
  perror( "Couldn't open the directory\n" );
 }

 // Write a fake log file so we don't need to read all the lightcurves next time
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
  memset( str, 0, MAX_LOG_STR_LENGTH );
  while ( NULL != fgets( str, MAX_LOG_STR_LENGTH, vastlogfile ) ) {
   str[MAX_LOG_STR_LENGTH-1]='\0'; // just in case
   //fprintf( stderr, "#%s#\n", str);
   if( strlen( str ) < 4 ){
    continue;
   }
   memset( jd_str, 0, MAX_LOG_STR_LENGTH );
   for ( i= 0; i < strlen( str ) - 3; i++ ) {
    if ( str[i] == 'J' && str[i + 1] == 'D' && str[i + 2] == '=' ) {
     for ( j= i + 4, k= 0; str[j] != ' ' && str[j] != '\n' ; j++, k++ ) {
      jd_str[k]= str[j];
     }
     jd[( *Nobs )]= atof( jd_str );
     // Check that we have parsed the log file correclty
     if ( 0 != isnan( jd[( *Nobs )] ) ) {
      fprintf( stderr, "ERROR in get_dates(): failed to convert string #%s# to double\n", jd_str );
      exit( 1 );
     }
     if ( 0 != isinf( jd[( *Nobs )] ) ) {
      fprintf( stderr, "ERROR in get_dates(): failed to convert string #%s# to double (1)\n", jd_str );
      exit( 1 );
     }
#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
#ifdef VAST_USE_BUILTIN_FUNCTIONS
// Make a proper check of the input values if isnormal() is defined
#if defined _ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L
     // We use __builtin_isnormal() as we know it is working if VAST_USE_BUILTIN_FUNCTIONS is defined
     // Othervise even with the '_ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L' check
     // isnormal() doesn't work on Ubuntu 14.04 trusty (vast.sai.msu.ru)
     // BEWARE 0.0 is also not considered normal by isnormal() !!!
     if ( 0 == __builtin_isnormal( jd[( *Nobs )] ) ) {
      fprintf( stderr, "ERROR in get_dates(): failed to convert string #%s# to double (2)\n", jd_str );
      exit( 1 );
     }
#endif
#endif

     // Check the input date, note that wedon't know if it's JD or MJD
     if ( jd[( *Nobs )] < EXPECTED_MIN_MJD ) {
      fprintf( stderr, "ERROR in get_dates(): JD%.5lf<%.5lf #%s#\n", jd[( *Nobs )], EXPECTED_MIN_MJD, jd_str );
      exit( 1 );
     }
     if ( jd[( *Nobs )] > EXPECTED_MAX_JD ) {
      fprintf( stderr, "ERROR in get_dates(): JD%.5lf>%.5lf #%s#\n", jd[( *Nobs )], EXPECTED_MAX_JD, jd_str );
      exit( 1 );
     }
#endif
     // everything is fine, go parse the next line in the log file
     ( *Nobs )+= 1;
     break;
    }
   }
  }
  fclose( vastlogfile );
  fprintf( stderr, "Total number of observations (from log file) %d\n", ( *Nobs ) );
  return;
 }
 fprintf( stderr, "Total number of observations %d\n", ( *Nobs ) );
 return;
}
