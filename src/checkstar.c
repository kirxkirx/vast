/*

  For each star, this routine will find a check star with the most similar lightcurve
  and investigate the remaining residuals.

*/

#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>

#include <gsl/gsl_statistics_float.h>
#include <gsl/gsl_sort_float.h>
#include <gsl/gsl_errno.h>

#include "vast_limits.h"
#include "lightcurve_io.h"

void write_fake_log_file( double *jd, size_t *Nobs ) {
 // int i;
 size_t i;
 FILE *logfile;
 fprintf( stderr, "Writing fake vast_image_details.log ... " );
 logfile= fopen( "vast_image_details.log", "w" );
 if ( logfile == NULL ) {
  fprintf( stderr, "ERROR: Cam't open vast_image_details.log\n" );
  exit( EXIT_FAILURE );
 };
 for ( i= 0; i < ( *Nobs ); i++ )
  fprintf( logfile, "JD= %.5lf\n", jd[i] );
 fclose( logfile );
 fprintf( stderr, "done\n" );
 return;
}

void get_dates_from_lightcurve_files( double *jd, size_t *Nobs ) {
 DIR *dp;
 struct dirent *ep;
 FILE *lightcurvefile;
 double _jd, mag, merr, x, y, app;
 char string[FILENAME_LENGTH];
 char comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 // int i;
 size_t i;
 int date_found;

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
     exit( EXIT_FAILURE );
    }
    while ( -1 < read_lightcurve_point( lightcurvefile, &_jd, &mag, &merr, &x, &y, &app, string, comments_string ) ) {
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

void get_dates( double *jd, size_t *Nobs ) {
 FILE *vastlogfile;
 char str[MAX_LOG_STR_LENGTH];
 char jd_str[MAX_LOG_STR_LENGTH];
 // unsigned int i, j, k;
 size_t i, j, k;
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
  fprintf( stderr, "Total number of observations (from log file) %ld\n", ( *Nobs ) );
  return;
 }
 fprintf( stderr, "Total number of observations %ld\n", ( *Nobs ) );
 return;
}

int main() {
 FILE *lightcurvefile;

 FILE *datafile;
 char data_m_sigma_line[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 size_t Nobs, Nstars, i, j, k;

 char **star_numbers;
 double *jd;

 float **mag_err;
 float **r;

 float *data;
 float mean, median;
 char lightcurvefilename[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char star_number_string[FILENAME_LENGTH];

 double djd;
 double dmag, dmerr, x, y, app;
 char string[FILENAME_LENGTH];
 char comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 float sum_sq_res, best_sum_sq_res;
 int best_k;

 float *mag_diff;
 float *diff_err;
 float Chi2;

 int n_good_1, n_good_2, n_good_common;

 float *median_arr;

 // Count stars we want to process
 Nstars= 0;
 datafile= fopen( "data.m_sigma", "r" );
 if ( NULL == datafile ) {
  fprintf( stderr, "ERROR! Can't open file data.m_sigma\n" );
  return 1;
 }
 while ( NULL != fgets( data_m_sigma_line, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, datafile ) )
  Nstars++;
 fclose( datafile );
 fprintf( stderr, "Number of stars in data.m_sigma %ld\n", Nstars );

 if ( Nstars <= 0 ) {
  fprintf( stderr, "ERROR: Trying allocate zero or negative bytes amount\n" );
  exit( EXIT_FAILURE );
 };
 star_numbers= malloc( Nstars * sizeof( char * ) );
 if ( star_numbers == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for star_numbers\n" );
  exit( EXIT_FAILURE );
 };
 for ( i= Nstars; i--; ) {
  star_numbers[i]= malloc( OUTFILENAME_LENGTH * sizeof( char ) );
  if ( star_numbers[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for star_numbers[i]\n" );
   exit( EXIT_FAILURE );
  };
 }

 // Read the log file
 jd= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( jd == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for jd\n" );
  exit( EXIT_FAILURE );
 };
 get_dates( jd, &Nobs );

 // Allocate memory
 mag_err= malloc( Nstars * sizeof( float * ) );
 if ( mag_err == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for mag_err\n" );
  exit( EXIT_FAILURE );
 }
 r= malloc( Nstars * sizeof( float * ) );
 if ( r == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for r\n" );
  exit( EXIT_FAILURE );
 }

 median_arr= malloc( Nstars * sizeof( float ) );
 if ( median_arr == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for median_arr\n" );
  exit( EXIT_FAILURE );
 };

 data= malloc( Nstars * Nobs * sizeof( float ) );
 if ( data == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for data\n" );
  exit( EXIT_FAILURE );
 }

 mag_diff= malloc( Nobs * sizeof( float ) );
 if ( mag_diff == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for mag_diff\n" );
  exit( EXIT_FAILURE );
 };
 diff_err= malloc( Nobs * sizeof( float ) );
 if ( diff_err == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for diff_err\n" );
  exit( EXIT_FAILURE );
 };

 // for(i=0;i<Nstars;i++){
 for ( i= Nstars; i--; ) {
  mag_err[i]= malloc( Nobs * sizeof( float ) );
  if ( mag_err[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for mag_err[i]\n" );
   exit( EXIT_FAILURE );
  };
  r[i]= malloc( Nobs * sizeof( float ) ); // is it correct ?????
  if ( r[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for r[i]\n" );
   exit( EXIT_FAILURE );
  }
 }

 // for(i=0;i<Nstars;i++)
 for ( i= Nstars; i--; )
  // for(j=0;j<Nobs;j++)
  for ( j= Nobs; j--; ) {
   r[i][j]= 0.0;
   mag_err[i][j]= 0.0;
  }

 // Read the data
 i= j= 0;
 datafile= fopen( "data.m_sigma", "r" );
 if ( NULL == datafile ) {
  fprintf( stderr, "ERROR! Can't open file data.m_sigma\n" );
  exit( EXIT_FAILURE );
 }
 while ( -1 < fscanf( datafile, "%f %f %f %f %s", &mean, &mean, &mean, &mean, lightcurvefilename ) ) {
  // Get star number from the lightcurve file name
  for ( k= 3; k < strlen( lightcurvefilename ); k++ ) {
   star_number_string[k - 3]= lightcurvefilename[k];
   if ( lightcurvefilename[k] == '.' ) {
    star_number_string[k - 3]= '\0';
    break;
   }
  }
  strcpy( star_numbers[i], star_number_string );
  lightcurvefile= fopen( lightcurvefilename, "r" );
  if ( NULL == lightcurvefile ) {
   fprintf( stderr, "ERROR: Can't read file %s\n", lightcurvefilename );
   exit( EXIT_FAILURE );
  }
  while ( -1 < read_lightcurve_point( lightcurvefile, &djd, &dmag, &dmerr, &x, &y, &app, string, comments_string ) ) {
   if ( djd == 0.0 )
    continue; // if this line could not be parsed, try the next one
   // Find which j is corresponding to the current JD
   for ( k= 0; k < Nobs; k++ ) {
    if ( fabs( jd[k] - djd ) <= 0.00001 ) { // 0.8 sec
     j= k;
     r[i][j]= dmag;
     mag_err[i][j]= dmerr;
     break;
    }
   }
  }
  fclose( lightcurvefile );
  i++;
 }
 fclose( datafile );

 // Do the actual work
 fprintf( stderr, "Computing average magnitudes... " );

 // For each star compute median magnitude and subtract it from all measurements
 // for(i=0;i<Nstars;i++){
 for ( i= Nstars; i--; ) {
  k= 0;
  // for(j=0;j<Nobs;j++){
  for ( j= Nobs; j--; ) {
   if ( r[i][j] != 0.0 ) {
    data[k]= r[i][j];
    k++;
   }
  }
  gsl_sort_float( data, 1, k );
  median= gsl_stats_float_median_from_sorted_data( data, 1, k );
  median_arr[i]= median;
  // for(j=0;j<Nobs;j++){
  for ( j= Nobs; j--; ) {
   if ( r[i][j] != 0.0 ) {
    r[i][j]= r[i][j] - median;
   }
  }
 }
 fprintf( stderr, "done\nFinding the most similar check star for each one...\n" );

 datafile= fopen( "vast_autocandidates.log", "w" );
 if ( NULL == datafile ) {
  fprintf( stderr, "ERROR! Can't open file vast_autocandidates.log\n" );
  return 1;
 }

 // For each star
 for ( i= Nstars; i--; ) {
  best_sum_sq_res= 99999999999999999.9;
  best_k= -1;
  for ( n_good_1= 0, j= Nobs; j--; )
   if ( r[i][j] != 0.0 )
    n_good_1++;
  for ( k= Nstars; k--; ) {
   if ( i == k )
    continue;
   for ( n_good_2= 0, j= Nobs; j--; )
    if ( r[k][j] != 0.0 )
     n_good_2++;
   if ( abs( n_good_1 - n_good_2 ) > 10 )
    continue;
   if ( fabsf( median_arr[i] - median_arr[k] ) > 1.0 )
    continue;
   for ( n_good_common= 0, j= Nobs; j--; )
    if ( r[i][j] != 0.0 && r[k][j] != 0.0 )
     n_good_common++;
   if ( (float)n_good_common < 0.9 * (float)n_good_1 )
    continue;
   // fprintf(stderr,"median_arr[i]=%f median_arr[k]=%f  n_good_1=%d n_good_2=%d\n",median_arr[i],median_arr[k],n_good_1,n_good_2);
   sum_sq_res= 0.0;
   for ( j= Nobs; j--; ) {
    if ( r[i][j] != 0.0 && r[k][j] != 0.0 ) {
     sum_sq_res+= ( r[i][j] - r[k][j] ) * ( r[i][j] - r[k][j] );
    }
   }
   if ( sum_sq_res < best_sum_sq_res ) {
    best_sum_sq_res= sum_sq_res;
    best_k= k;
   }
  }
  // fprintf(stderr,"out%s.dat out%s.dat\n", star_numbers[i],star_numbers[best_k]);

  for ( Chi2= 0.0, k= 0, j= Nobs; j--; ) {
   //
   if ( best_k < 0 ) {
    fprintf( stderr, "ERROR in src/checkstar.c  best_k<0\n" );
    exit( EXIT_FAILURE );
   }
   //
   if ( r[i][j] != 0.0 && r[best_k][j] != 0.0 ) {
    mag_diff[k]= r[i][j] - r[best_k][j];
    diff_err[k]= sqrtf( mag_err[i][j] * mag_err[i][j] + mag_err[best_k][j] * mag_err[best_k][j] );
    Chi2+= mag_diff[k] * mag_diff[k] / ( diff_err[k] * diff_err[k] );
    k++;
   }
  }
  Chi2= Chi2 / (float)( k - 1 );

  // fprintf(stderr,"out%s.dat out%s.dat %lg\n", star_numbers[i],star_numbers[best_k],Chi2);

  fprintf( stdout, "%.4lf %lg\n", median_arr[i], Chi2 );

  if ( Chi2 > 5.0 )
   fprintf( datafile, "out%s.dat\n", star_numbers[i] );
 }
 fclose( datafile );

 free( median_arr );

 free( diff_err );
 free( mag_diff );

 for ( i= Nstars; i--; ) {
  free( star_numbers[i] );
  free( mag_err[i] );
  free( r[i] );
 }
 free( star_numbers );
 free( mag_err );
 free( r );

 free( jd );

 return 0;
}
