// This routine will resacle photometric errors in all lightcurves following
// http://adsabs.harvard.edu/abs/2009MNRAS.397.1228W
// and
// http://adsabs.harvard.edu/abs/2017MNRAS.468.2189Z
//
// sigma_new_i = sqrt( (gamm*sigma_i)^2 + epsilon^2 )

#include <math.h>

#include <stdio.h>
#include <stdlib.h> // for system() and exit()
#include <unistd.h> // for unlink()

#include <libgen.h> // for basename()
#include <string.h> // for strncmp()

#include <sys/types.h>
#include <dirent.h>

#include <gsl/gsl_statistics.h>
#include <gsl/gsl_fit.h>
//#include <gsl/gsl_sort.h>

#include "limits.h"
#include "lightcurve_io.h"

#include "wpolyfit.h"

void make_sure_photometric_errors_rescaling_is_in_log_file() {
 FILE *logfilein;
 FILE *logfileout;
 //int number_of_iterations=0;
 char str[2048];
 logfilein= fopen( "vast_summary.log", "r" );
 if ( logfilein != NULL ) {
  logfileout= fopen( "vast_summary.log.tmp", "w" );
  if ( logfileout == NULL ) {
   fclose( logfilein );
   fprintf( stderr, "ERROR: Couldn't open vast_summary.log.tmp" );
   return;
  }
  while ( NULL != fgets( str, 2048, logfilein ) ) {
   if ( str[0] == 'P' && str[1] == 'h' && str[2] == 'o' && str[12] == 'e' && str[13] == 'r' && str[14] == 'r' && str[15] == 'o' ) {
    //           0123456789012345678901234567890
    sprintf( str, "Photometric errors rescaling: YES\n" );
   }
   fputs( str, logfileout );
  }
  fclose( logfileout );
  fclose( logfilein );
  //system("mv vast_summary.log.tmp vast_summary.log");
  if ( 0 != unlink( "vast_summary.log" ) ) {
   fprintf( stderr, "ERROR in make_sure_photometric_errors_rescaling_is_in_log_file(): unlink(\"vast_summary.log\") FAILED\n" );
  }
  if ( 0 != rename( "vast_summary.log.tmp", "vast_summary.log" ) ) {
   fprintf( stderr, "ERROR in make_sure_photometric_errors_rescaling_is_in_log_file(): rename(\"vast_summary.log.tmp\",\"vast_summary.log\") FAILED\n" );
  }
 }
 return;
}

int main( int argc, char **argv ) {

 FILE *outlightcurvefile;

 FILE *vast_rescale_photometric_errors_log;
 FILE *vast_list_of_likely_constant_stars;
 FILE *input_lightcurve_file;
 char input_lightcurve_filename[OUTFILENAME_LENGTH];

 // for lightcurve_io
 double jd, mag, magerr, x, y, app;
 char string[FILENAME_LENGTH];
 char comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 // for gsl_fit
 //double cov00, cov01, cov11, sumsq;
 double cov11, sumsq; // sufficient for the linear fit without the constant term.

 double gamma, gamma_squared, epsilon, epsilon_squared;

 double *mean_estimated_sigma;
 double *actual_sigma;
 double *w;

 int i, star_counter, just_estimate_noise_level_and_exit;

 double *mag_array;
 double *magerr_array;

 // File name handling
 DIR *dp;
 struct dirent *ep;
 
 char **filenamelist;
 long filename_counter;
 long filenamelen;

 mean_estimated_sigma= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( mean_estimated_sigma == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for mean_estimated_sigma\n" );
  exit( 1 );
 };
 actual_sigma= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( actual_sigma == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for actual_sigma\n" );
  exit( 1 );
 };
 w= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( w == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for w array\n" );
  exit( 1 );
 };

 mag_array= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( mag_array == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for mag_array(rescale_photometric_errors.c)\n" );
  exit( 1 );
 };
 magerr_array= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( magerr_array == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for magerr_array(rescale_photometric_errors.c)\n" );
  exit( 1 );
 };

 star_counter= 0;

 if ( 0 == strncmp( "estimate_systematic_noise_level", basename( argv[0] ), strlen( "estimate_systematic_noise_level" ) ) ) {
  just_estimate_noise_level_and_exit= 1;
 } else {
  just_estimate_noise_level_and_exit= 0;
 }

 if ( argc > 1 ) {
  fprintf( stderr, "Usage: %s\n", argv[0] );
  return 1;
 }

 // Read the list of constants stars
 vast_list_of_likely_constant_stars= fopen( "vast_list_of_likely_constant_stars.log", "r" );
 if ( NULL == vast_list_of_likely_constant_stars ) {
  if ( 0 != system( "lib/index_vs_mag" ) ) {
   fprintf( stderr, "ERROR running lib/index_vs_mag\n" );
   return 1;
  }
  if ( NULL == vast_list_of_likely_constant_stars ) {
   fprintf( stderr, "ERROR: cannot open the input list of constant stars in vast_list_of_likely_constant_stars.log\n" );
   return 1;
  }
 }
 while ( -1 < fscanf( vast_list_of_likely_constant_stars, "%s", input_lightcurve_filename ) ) {
  input_lightcurve_file= fopen( input_lightcurve_filename, "r" );
  if ( input_lightcurve_file == NULL ) {
   fprintf( stderr, "WARNING: cannot open lightcurve file %s listed in vast_list_of_likely_constant_stars.log\n", input_lightcurve_filename );
   continue;
  }
  // Read the lightcure
  i= 0;
  while ( -1 < read_lightcurve_point( input_lightcurve_file, &jd, &mag, &magerr, &x, &y, &app, string, comments_string ) ) {
   if ( jd == 0.0 )
    continue; // if this line could not be parsed, try the next one
   mag_array[i]= mag;
   magerr_array[i]= magerr;
   i++;
  }
  fclose( input_lightcurve_file );
  if ( i < HARD_MIN_NUMBER_OF_POINTS )
   continue;
  //
  mean_estimated_sigma[star_counter]= gsl_stats_mean( magerr_array, 1, i );
  if ( mean_estimated_sigma[star_counter] <= 0.0 )
   continue;
  actual_sigma[star_counter]= gsl_stats_sd( mag_array, 1, i );
  if ( actual_sigma[star_counter] <= 0.0 )
   continue;
  //
  mean_estimated_sigma[star_counter]= mean_estimated_sigma[star_counter] * mean_estimated_sigma[star_counter];
  actual_sigma[star_counter]= actual_sigma[star_counter] * actual_sigma[star_counter];
  w[star_counter]= 1.0 / ( mean_estimated_sigma[star_counter] ); // already squared
  //
  star_counter++;
 }

 fclose( vast_list_of_likely_constant_stars );

 free( magerr_array );
 free( mag_array );

 fprintf( stderr, "Computing photometric errors rescaling factors using %d constant stars.\n", star_counter );
 if ( star_counter < MIN_NUMBER_OF_STARS_ON_FRAME ) {
  fprintf( stderr, "ERROR: only %d stars are available for magnitude error rescaling -- that's too few!\n", star_counter );
  return 1;
 }

 for ( i= star_counter; i--; ) {
  if ( mean_estimated_sigma[0] != mean_estimated_sigma[i] )
   break; // we should be fine
  if ( i == 0 ) {
   // If we got here - something is not right
   fprintf( stderr, "ERROR: all estimated photometric errors are set to the same value of %lf\nI cannot rescale such artificial errorbars!\n", sqrt( mean_estimated_sigma[0] ) );
   return 1;
  }
 }

 // Write the log file
 vast_rescale_photometric_errors_log= fopen( "vast_rescale_photometric_errors.log", "w" );
 if ( NULL != vast_rescale_photometric_errors_log ) {
  fprintf( stderr, "Writing squared photometric errors to vast_rescale_photometric_errors.log\n" );
  for ( i= 0; i < star_counter; i++ ) {
   fprintf( vast_rescale_photometric_errors_log, "%lf  %lf\n", mean_estimated_sigma[i], actual_sigma[i] );
  }
  fclose( vast_rescale_photometric_errors_log );
 } else {
  fprintf( stderr, "ERROR opening vast_rescale_photometric_errors.log for writing!\n" );
 }

 ////gsl_fit_linear( mean_estimated_sigma, 1, actual_sigma, 1, star_counter, &epsilon_squared, &gamma_squared, &cov00, &cov01, &cov11, &sumsq);
 //gsl_fit_wlinear( mean_estimated_sigma, 1, w, 1, actual_sigma, 1, star_counter, &epsilon_squared, &gamma_squared, &cov00, &cov01, &cov11, &sumsq);

 double poly_coeff[10];
 robustlinefit( mean_estimated_sigma, actual_sigma, star_counter, poly_coeff );
 epsilon_squared= poly_coeff[0];
 gamma_squared= poly_coeff[1];

 fprintf( stderr, "Best fit: %lf*x%+lf\n", gamma_squared, epsilon_squared );

 epsilon= sqrt( epsilon_squared );
 gamma= sqrt( gamma_squared );

 if ( just_estimate_noise_level_and_exit == 1 ) {
  if ( 0 != isnan( epsilon ) )
   epsilon= 0.0;
  if ( epsilon < 0.0 )
   epsilon= 0.0;
  fprintf( stdout, "%.4lf\n", epsilon );
  free( w );
  free( actual_sigma );
  free( mean_estimated_sigma );
  return 0;
 }

 if ( gamma >= 1.0 || epsilon_squared >= 0.0 ) {
  // The fit is not good
  if ( gamma < 1.0 ) {
   fprintf( stderr, "The linear fit suggest gamma=%lf<1.0, but we don't want to lower the estimated errors, so we are forcing gamma=1.0\n", gamma );
   gamma_squared= gamma= 1.0;
   epsilon_squared= gsl_stats_mean( actual_sigma, 1, star_counter ) - gsl_stats_mean( mean_estimated_sigma, 1, star_counter );
   fprintf( stderr, " mean(actual_sigma) - mean(mean_estimated_sigma) = %lf\n", epsilon_squared );
   if ( epsilon_squared < 0.0 ) {
    epsilon_squared= epsilon= 0.0;
   } else {
    epsilon= sqrt( epsilon_squared );
   }
  }
  if ( epsilon_squared < 0.0 ) {
   fprintf( stderr, "The linear fit suggest epsilon^2=%lf<1.0, so we are forcing epsilon=0.0\n", epsilon_squared );
   epsilon_squared= epsilon= 0.0;
   fprintf( stderr, "Performing the linear fit without the constant term (epsilon=0.0).\n" );
   //gsl_fit_mul( mean_estimated_sigma, 1, actual_sigma, 1, star_counter, &gamma_squared, &cov11, &sumsq);
   gsl_fit_wmul( mean_estimated_sigma, 1, w, 1, actual_sigma, 1, star_counter, &gamma_squared, &cov11, &sumsq );
   gamma= sqrt( gamma_squared );
  }

 } // if( gamma>=1.0 || epsilon_squared>=0.0 ){

 fprintf( stderr, "Final best fit: %lf*x%+lf\n", gamma_squared, epsilon_squared );

 // Write the log file
 vast_rescale_photometric_errors_log= fopen( "vast_rescale_photometric_errors.log", "w" );
 if ( NULL != vast_rescale_photometric_errors_log ) {
  fprintf( stderr, "Writing squared photometric errors to vast_rescale_photometric_errors.log\n" );
  for ( i= 0; i < star_counter; i++ ) {
   fprintf( vast_rescale_photometric_errors_log, "%lf  %lf\n", mean_estimated_sigma[i], actual_sigma[i] );
  }
  fclose( vast_rescale_photometric_errors_log );
 } else {
  fprintf( stderr, "ERROR opening vast_rescale_photometric_errors.log for writing!\n" );
 }

 free( w );
 free( actual_sigma );
 free( mean_estimated_sigma );

 vast_rescale_photometric_errors_log= fopen( "vast_rescale_photometric_errors_linear_fit_coefs.log", "w" );
 if ( NULL != vast_rescale_photometric_errors_log ) {
  fprintf( stderr, "Saving the linear fit coefficients to vast_rescale_photometric_errors_linear_fit_coefs.log\n" );
  fprintf( vast_rescale_photometric_errors_log, "%lf * x + %lf\n", gamma_squared, epsilon_squared );
  fclose( vast_rescale_photometric_errors_log );
 } else {
  fprintf( stderr, "ERROR opening vast_rescale_photometric_errors_linear_fit_coefs.log for writing!\n" );
 }

 fprintf( stderr, "The derived error scaling parameters: gamma= %lf epsilon= %lf\nAll photometric errors will be scaled as sigma_new = sqrt( (%lf*sigma)^2 + %lf^2 )\n", gamma, epsilon, gamma, epsilon );

 if ( gamma == 1.0 && epsilon == 0.0 ) {
  fprintf( stderr, "No need to rescale errors!\n" );
  return 0;
 }

 if ( 0 != isnan( gamma ) || 0 != isnan( epsilon ) ) {
  fprintf( stderr, "Failed to rescale errors -- encountered 'nan' valuess of fit coefficients!\n" );
  return 1;
 }

 if ( gamma < 1.0 ) {
  fprintf( stderr, "The derived gamma=%lf<1.0 rescale errors!\nI'm not rescaling the errors.\n", gamma );
  return 1;
 }

 // Apply the corrections
 fprintf( stderr, "Applying corrections to error estimates in all lightcurves.\n" );
 // Create a list of files
 filenamelist= (char **)malloc( MAX_NUMBER_OF_STARS * sizeof( char * ) );
 filename_counter= 0;
 dp= opendir( "./" );
 if ( dp != NULL ) {
  while ( ( ep= readdir( dp ) ) != NULL ) {
   filenamelen= strlen( ep->d_name );
   if ( filenamelen < 8 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[filenamelen - 1] == 't' && ep->d_name[filenamelen - 2] == 'a' && ep->d_name[filenamelen - 3] == 'd' ) {
    filenamelist[filename_counter]= malloc( (filenamelen+1) * sizeof( char ) );
    strncpy( filenamelist[filename_counter], ep->d_name, (filenamelen+1) );
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
  input_lightcurve_file= fopen( filenamelist[filename_counter], "r" );
  if ( NULL == input_lightcurve_file ) {
   fprintf( stderr, "ERROR: Can't open file %s\n", filenamelist[filename_counter] );
   exit( 1 );
  }
  outlightcurvefile= fopen( "lightcurve.tmp", "w" );
  if ( NULL == outlightcurvefile ) {
   fprintf( stderr, "\nAn ERROR has occured while processing file %s \n", filenamelist[filename_counter] );
   fprintf( stderr, "ERROR: Can't open file %s for writing\n", "lightcurve.tmp" );
   exit( 1 );
  }
  while ( -1 < read_lightcurve_point( input_lightcurve_file, &jd, &mag, &magerr, &x, &y, &app, string, comments_string ) ) {
   if ( jd == 0.0 )
    continue; // if this line could not be parsed, try the next one
   /////
   magerr= sqrt( gamma_squared * magerr * magerr + epsilon_squared );
   ////
   if ( magerr > MAX_MAG_ERROR )
    continue; // discard observations with large errorbars
   ////
   write_lightcurve_point( outlightcurvefile, jd, mag, magerr, x, y, app, string, comments_string );
  }
  fclose( outlightcurvefile );
  fclose( input_lightcurve_file );
  unlink( filenamelist[filename_counter] );                   // delete old lightcurve file
  rename( "lightcurve.tmp", filenamelist[filename_counter] ); // move lightcurve.tmp to lightcurve file
  free( filenamelist[filename_counter] );
 }

 make_sure_photometric_errors_rescaling_is_in_log_file();

 free( filenamelist );

 return 0;
}
