/*

   Local zero-point correction

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
#include "safely_encode_user_input_string.h" // for safely_encode_user_input_string()

#define CORRECTION_RADIUS_DEG_OR_PIX 20.0 / 3600.0

void write_fake_log_file( double *jd, size_t *Nobs ) {
 size_t i;
 FILE *logfile;
 fprintf( stderr, "Writing fake vast_image_details.log ... " );
 logfile= fopen( "vast_image_details.log", "w" );
 if ( logfile == NULL ) {
  fprintf( stderr, "ERROR: Couldn't open vast_image_details.log(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };
 for ( i= 0; i < ( *Nobs ); i++ ) {
  // fprintf( logfile, "JD= %.5lf\n", jd[i] );
  fprintf( logfile, "JD= %.8lf\n", jd[i] );
 }
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
     for ( i= 0; i < (size_t)( *Nobs ); i++ ) {
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

// This function will try to guess if the input coordinates are in degrees (0) or pixels (1)
int guess_degrees_or_pixels( float **y, int N1, int N2 ) {
 int i, j;
 float min_y, max_y;

 // this is just to make the compilrer happy
 min_y= max_y= y[0][0];

 // Set initial values
 for ( i= 0; i < N1; i++ ) {
  for ( j= 0; j < N2; j++ ) {
   if ( y[i][j] != 0.0 ) {
    min_y= max_y= y[i][j];
    break;
   }
  }
 }
 // Find min and max values
 for ( i= 0; i < N1; i++ ) {
  for ( j= 0; j < N2; j++ ) {
   if ( y[i][j] != 0.0 ) {
    if ( y[i][j] < min_y )
     min_y= y[i][j];
    if ( y[i][j] > max_y )
     max_y= y[i][j];
   }
  }
 }

 if ( max_y < 90.0 ) {
  return 0; // degrees
 } else {
  return 1; // pixels
 }
}

double compute_distance_on_sphere( double RA1, double DEC1, double target_ra, double target_dec ) {
 double distance;
 double RA1_rad= RA1 * M_PI / 180.0;
 double DEC1_rad= DEC1 * M_PI / 180.0;
 double target_ra_rad= target_ra * M_PI / 180.0;
 double target_dec_rad= target_dec * M_PI / 180.0;

 distance= 180.0 / M_PI * acos( cos( DEC1_rad ) * cos( target_dec_rad ) * cos( MAX( RA1_rad, target_ra_rad ) - MIN( RA1_rad, target_ra_rad ) ) + sin( DEC1_rad ) * sin( target_dec_rad ) );
 // fprintf(stderr,"###### %lf %lf  %lf %lf  %lf\n",RA1,DEC1,target_ra,target_dec,distance);
 return distance;
}

// int main(int argc, char **argv){
int main() {
 FILE *lightcurvefile;
 FILE *outlightcurvefile;

 float **mag_err; // mag. errors
 float **r;       // mag. residuals
 float **x;       // X image positions
 float **y;       // Y image positions
 float **corr;    // Y image positions

 float *c;
 float *a;

 float *old_c;
 float *old_a;

 double *jd;

 // int i, j; //,iter;
 // long k, l;

 size_t i, j, k, l;

 double djd;
 double dmag, dmerr, X, Y, app;
 float distance;
 char string[FILENAME_LENGTH];
 char comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 char star_number_string[FILENAME_LENGTH];

 // int Nobs;
 // int Nstars;
 size_t Nobs;
 size_t Nstars;

 float *data;
 float *w;
 // float mean,median,sigma,sum1,sum2;
 float mean, median;

 char system_command_str[1024];

 FILE *datafile;
 char lightcurvefilename[OUTFILENAME_LENGTH];
 char lightcurvefilename_local[OUTFILENAME_LENGTH];

 // int stop_iterations=0;

 int *bad_stars;
 char **star_numbers;

 // float tmpfloat; // for faster computation

 int degrees_or_pixels;

 /* Protection against strange free() crashes */
 // setenv("MALLOC_CHECK_", "0", 1);

 /* If there is no input star list - make it */
 // system("lib/select_sysrem_input_star_list");

 /* Count stars we want to process */
 Nstars= 0;
 datafile= fopen( "data.m_sigma", "r" );
 if ( NULL == datafile ) {
  fprintf( stderr, "ERROR! Can't open file data.m_sigma(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 }
 while ( -1 < fscanf( datafile, "%f %f %f %f %s", &mean, &mean, &mean, &mean, lightcurvefilename_local ) ) {
  safely_encode_user_input_string( lightcurvefilename, lightcurvefilename_local, OUTFILENAME_LENGTH - 1 );
  Nstars++;
 }
 fclose( datafile );
 fprintf( stderr, "Number of stars in sysrem_input_star_list.lst %ld\n", Nstars );
 if ( Nstars < 100 ) {
  fprintf( stderr, "Too few stars!\n" );
  exit( EXIT_FAILURE );
 }

 bad_stars= malloc( Nstars * sizeof( int ) );
 if ( bad_stars == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for bad_stars(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };
 star_numbers= malloc( Nstars * sizeof( char * ) );
 if ( star_numbers == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for star_numbers(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };
 // for(i=0;i<Nstars;i++){
 for ( i= Nstars; i--; ) {
  star_numbers[i]= malloc( OUTFILENAME_LENGTH * sizeof( char ) );
  if ( star_numbers[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for star_numbers[i](local_zeropoint_correction.c)\n" );
   exit( EXIT_FAILURE );
  };
  bad_stars[i]= 0;
 }

 /* Read the log file */
 jd= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( jd == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for jd(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };
 get_dates( jd, &Nobs );

 /* Allocate memory */
 mag_err= malloc( Nstars * sizeof( float * ) );
 if ( mag_err == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for mag_err(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };
 r= malloc( Nstars * sizeof( float * ) );
 if ( r == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for r(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };
 x= malloc( Nstars * sizeof( float * ) );
 if ( x == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for x(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };
 y= malloc( Nstars * sizeof( float * ) );
 if ( y == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for y(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };
 corr= malloc( Nstars * sizeof( float * ) );
 if ( corr == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for corr(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };

 data= malloc( Nstars * Nobs * sizeof( float ) );
 if ( data == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for data(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };
 w= malloc( Nstars * Nobs * sizeof( float ) );
 if ( w == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for w(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };

 // for(i=0;i<Nstars;i++){
 for ( i= Nstars; i--; ) {
  corr[i]= malloc( Nobs * sizeof( float ) );
  if ( corr[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for corr[i](local_zeropoint_correction.c)\n" );
   exit( EXIT_FAILURE );
  };
  x[i]= malloc( Nobs * sizeof( float ) );
  if ( x[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for x[i](local_zeropoint_correction.c)\n" );
   exit( EXIT_FAILURE );
  };
  y[i]= malloc( Nobs * sizeof( float ) );
  if ( y[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for y[i](local_zeropoint_correction.c)\n" );
   exit( EXIT_FAILURE );
  };
  mag_err[i]= malloc( Nobs * sizeof( float ) );
  if ( mag_err[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for mag_err[i](local_zeropoint_correction.c)\n" );
   exit( EXIT_FAILURE );
  };
  r[i]= malloc( Nobs * sizeof( float ) );
  if ( r[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for r[i](local_zeropoint_correction.c)\n" );
   exit( EXIT_FAILURE );
  };
 }

 // Initialize the arrays
 // for(i=0;i<Nstars;i++)
 for ( i= Nstars; i--; ) {
  // for(j=0;j<Nobs;j++)
  for ( j= Nobs; j--; ) {
   r[i][j]= 0.0;
   x[i][j]= 0.0;
   y[i][j]= 0.0;
   mag_err[i][j]= 0.0;
   corr[i][j]= 0.0;
  } // for(j=Nobs;j--;){
 }  // for(i=Nstars;i--;){

 c= malloc( Nstars * sizeof( float ) );
 if ( c == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for bad_stars(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };
 a= malloc( Nobs * sizeof( float ) );
 if ( a == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for a(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };

 old_c= malloc( Nstars * sizeof( float ) );
 if ( old_c == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for old_c(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };
 old_a= malloc( Nobs * sizeof( float ) );
 if ( old_a == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for old_a(local_zeropoint_correction.c)\n" );
  exit( EXIT_FAILURE );
 };

 // for(i=0;i<Nstars;i++){
 for ( i= Nstars; i--; ) {
  c[i]= 0.1;
  old_c[i]= 0.1;
 }

 // for(i=0;i<Nobs;i++){
 for ( i= Nobs; i--; ) {
  a[i]= 1.0;
  old_a[i]= 1.0;
 }

 // Read the data
 i= j= 0;
 datafile= fopen( "data.m_sigma", "r" );
 if ( NULL == datafile ) {
  fprintf( stderr, "ERROR! Can't open file data.m_sigma\n" );
  exit( EXIT_FAILURE );
 }
 while ( -1 < fscanf( datafile, "%f %f %f %f %s", &mean, &mean, &mean, &mean, lightcurvefilename_local ) ) {
  safely_encode_user_input_string( lightcurvefilename, lightcurvefilename_local, OUTFILENAME_LENGTH - 1 );
  // escape special characters in the green_channel_only_image_name (as it was derived from "user input" fscanf() )
  // if( 0 != any_unusual_characters_in_string(lightcurvefilename) ) {
  //  fprintf(stderr, "WARNING: any_unusual_characters_in_string(%s) returned 1\n", lightcurvefilename);
  //  continue;
  //}
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
  // while(-1<fscanf(lightcurvefile,"%lf %f %f %f %f %f %s",&djd,&dmag,&dmerr,&X,&Y,&app,string)){
  while ( -1 < read_lightcurve_point( lightcurvefile, &djd, &dmag, &dmerr, &X, &Y, &app, string, comments_string ) ) {
   if ( djd == 0.0 )
    continue; // if this line could not be parsed, try the next one
   // Find which j is corresponding to the current JD
   for ( k= 0; k < Nobs; k++ ) {
    if ( fabs( jd[k] - djd ) <= 0.00001 ) { // 0.8 sec
                                            // if( fabs(jd[k]-djd)<=0.0001 ){ // 8 sec
     j= k;
     r[i][j]= dmag;
     mag_err[i][j]= dmerr;
     x[i][j]= X;
     y[i][j]= Y;
     break;
    }
   }
  }
  fclose( lightcurvefile );
  i++;
 }
 fclose( datafile );

 degrees_or_pixels= guess_degrees_or_pixels( y, Nstars, Nobs );
 fprintf( stderr, "ASSUMING INPIT POSITIONS ARE %d (0 - degrees, 1 - pixels)\n", degrees_or_pixels );

 /* Do the actual work */
 fprintf( stderr, "Computing average magnitudes... " );

 /* For each star compute median magnitude and subtract it from all measurements */
 for ( i= 0; i < Nstars; i++ ) {
  // for(i=Nstars;i--;){
  k= 0;
  // for(j=0;j<Nobs;j++){
  for ( j= Nobs; j--; ) {
   if ( r[i][j] != 0.0 ) {
    data[k]= r[i][j];
    w[k]= 1.0 / ( mag_err[i][j] * mag_err[i][j] );
    k++;
   }
  }
  gsl_sort_float( data, 1, k );
  median= gsl_stats_float_median_from_sorted_data( data, 1, k );
  // for(j=0;j<Nobs;j++){
  for ( j= Nobs; j--; ) {
   if ( r[i][j] != 0.0 ) {
    r[i][j]= r[i][j] - median;
   }
  }
 }
 fprintf( stderr, "done\n" );

 fprintf( stderr, "Computing local corrections...\n" );
 // For each image
 for ( j= Nobs; j--; ) {
  // For each star
  for ( i= Nstars; i--; ) {
   // If there is a data point
   if ( r[i][j] != 0.0 ) {
    // Find nearest stars on that image
    k= 0;
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( l, distance )
#endif
#endif
    for ( l= 0; l < Nstars; l++ ) {
     if ( r[l][j] != 0.0 && i != l ) {
      if ( fabsf( y[l][j] - y[i][j] ) > CORRECTION_RADIUS_DEG_OR_PIX )
       continue;
      if ( degrees_or_pixels == 0 ) {
       distance= compute_distance_on_sphere( x[l][j], y[l][j], x[i][j], y[i][j] );
      } else {
       // pixels
       distance= sqrt( ( x[l][j] - x[i][j] ) * ( x[l][j] - x[i][j] ) + ( y[l][j] - y[i][j] ) * ( y[l][j] - y[i][j] ) );
      }
      // fprintf(stderr,"distance=%f\n",distance);
      if ( distance < CORRECTION_RADIUS_DEG_OR_PIX ) {
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp critical
#endif
#endif
       {
        data[k]= r[l][j];
        w[k]= 1.0 / ( mag_err[i][j] * mag_err[i][j] );
        k++;
       }
      }
     } // if( r[l][j]!=0.0 && i!=l ){
    }  // for(k=0;k<Nstars;k++){
    // Now determine the mean local correction
    gsl_sort_float( data, 1, k );
    corr[i][j]= gsl_stats_float_median_from_sorted_data( data, 1, k );
// fprintf(stderr,"corr[%d][%d]=%f\n",i,j,corr[i][j]);
#ifdef DEBUGFILES
    fprintf( stderr, "%7.3f %7.3f %6.4f\n", x[i][j], y[i][j], corr[i][j] );
#endif
   } // if( r[i][j]!=0.0 ){
  }  // for(i=Nstars;i--;){
  fprintf( stderr, "***********************************************\n" );
 } // for(j=Nobs;j--;){

 // Apply corrections to lightcurves *
 fprintf( stderr, "Applying corrections... \n" );
 for ( i= 0; i < Nstars; i++ ) {
  sprintf( lightcurvefilename, "out%s.dat", star_numbers[i] );
  if ( bad_stars[i] == 0 ) {
   lightcurvefile= fopen( lightcurvefilename, "r" );
   if ( NULL == lightcurvefile ) {
    fprintf( stderr, "ERROR: Can't read file %s\n", lightcurvefilename );
    exit( EXIT_FAILURE );
   }
   outlightcurvefile= fopen( "TMP.dat", "w" );
   if ( outlightcurvefile == NULL ) {
    fprintf( stderr, "ERROR: Couldn't open outlightcurvefile for writing(local_zeropoint_correction.c)\n" );
    exit( EXIT_FAILURE );
   };
   // while(-1<fscanf(lightcurvefile,"%lf %f %f %f %f %f %s",&djd,&dmag,&dmerr,&X,&Y,&app,string)){
   while ( -1 < read_lightcurve_point( lightcurvefile, &djd, &dmag, &dmerr, &X, &Y, &app, string, comments_string ) ) {
    if ( djd == 0.0 )
     continue; // if this line could not be parsed, try the next one
    // Find which j is corresponding to the current JD
    for ( k= 0; k < Nobs; k++ ) {
     if ( fabs( jd[k] - djd ) <= 0.00001 ) { // 0.8 sec
      // j=k;
      write_lightcurve_point( outlightcurvefile, djd, (double)( dmag - corr[i][k] ), (double)dmerr, (double)X, (double)Y, (double)app, string, comments_string );
      break;
     }
    }
   }
   fclose( outlightcurvefile );
   fclose( lightcurvefile );
   unlink( lightcurvefilename );
   rename( "TMP.dat", lightcurvefilename );
  } else {
   fprintf( stderr, "Skip correction for %s", lightcurvefilename );
   if ( bad_stars[i] == 2 ) {
    fprintf( stderr, " removing it from sysrem_input_star_list.lst\n" );
    sprintf( system_command_str, "grep -v %s sysrem_input_star_list.lst > TMP.dat && mv -f TMP.dat sysrem_input_star_list.lst", lightcurvefilename );
    if ( 0 != system( system_command_str ) ) {
     fprintf( stderr, "ERROR running  %s\n", system_command_str );
    }
   } else {
    fprintf( stderr, "\n" );
   }
  }
 }
 fprintf( stderr, "done\n" );

 free( bad_stars );
 for ( i= 0; i < Nstars; i++ ) {
  free( star_numbers[i] );
  free( x[i] );
  free( y[i] );
  free( mag_err[i] );
  free( r[i] );
 }
 free( star_numbers );
 free( old_c );
 free( old_a );

 /* Free memory */
 free( corr );
 free( x );
 free( y );
 free( mag_err );
 free( r );
 free( a );
 free( c );
 free( jd );
 free( data );
 free( w );

 // unsetenv("MALLOC_CHECK_");

 fprintf( stderr, "All done!  =)\n" );

 return 0;
}
