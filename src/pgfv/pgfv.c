#include <stdio.h>
#include <stdlib.h>

#define _GNU_SOURCE // for memmem()
#include <string.h>

#include <math.h>
#include <libgen.h> // for basename()

#include <sys/types.h> // for getpid()
#include <unistd.h>    // for getpid() too  and for unlink()

#include <time.h> // for nanosleep()

#include <sys/wait.h> // for waitpid

#include <getopt.h>

#include <gsl/gsl_statistics_float.h>
#include <gsl/gsl_sort_float.h>

#include "cpgplot.h"

#include "../setenv_local_pgplot.h"

#include "../fitsio.h"

#include "../vast_limits.h"
#include "../photocurve.h"
#include "../ident.h"
#include "../safely_encode_user_input_string.h" // for safely_encode_user_input_string() and also needed by fitsfile_read_check.h
#include "../fitsfile_read_check.h"
#include "../replace_file_with_symlink_if_filename_contains_white_spaces.h"

#include "../parse_sextractor_catalog.h"

#include "../get_path_to_vast.h"

#include "../count_lines_in_ASCII_file.h"

#include "../lightcurve_io.h" // for read_lightcurve_point()

#include "../is_point_close_or_off_the_frame_edge.h" // for is_point_close_or_off_the_frame_edge()

int Kourovka_SBG_date_hack( char *fitsfilename, char *DATEOBS, int *date_parsed, double *exposure ); // defined in gettime.c

void save_star_to_vast_list_of_previously_known_variables_and_exclude_lst( int sextractor_catalog__star_number, float sextractor_catalog__X, float sextractor_catalog__Y ) {
 FILE *filepointer;
 fprintf( stderr, "Marking out%05d.dat as a variable star and excluding it from magnitude calibration\n", sextractor_catalog__star_number );
 filepointer= fopen( "vast_list_of_previously_known_variables.log", "a" );
 fprintf( filepointer, "out%05d.dat\n", sextractor_catalog__star_number );
 fclose( filepointer );
 filepointer= fopen( "exclude.lst", "a" );
 fprintf( filepointer, "%.3f %.3f\n", sextractor_catalog__X, sextractor_catalog__Y );
 fclose( filepointer );
 return;
}

int get_string_with_fov_of_wcs_calibrated_image( char *fitsfilename, char *output_string, float *output_float_fov_arcmin, int finder_chart_mode, float finder_char_pix_around_the_target ) {
 float image_scale, image_size;
 unsigned int string_char_counter;
 char path_to_vast_string[VAST_PATH_MAX];
 char systemcommand[2 * VAST_PATH_MAX];
 FILE *fp;
 get_path_to_vast( path_to_vast_string );
 path_to_vast_string[VAST_PATH_MAX - 1]= '\0'; // just in case
 //
 output_string[0]= '\0';            // reset output just in case
 ( *output_float_fov_arcmin )= 0.0; // reset output just in case
 //
 if ( finder_chart_mode == 1 ) {
  // This is a zoom-in image
  sprintf( systemcommand, "%sutil/fov_of_wcs_calibrated_image.sh %s | grep 'Image scale:' | awk '{print $3}' | awk -F'\"' '{print $1}'", path_to_vast_string, fitsfilename );
  fprintf( stderr, "Trying to run\n %s\n", systemcommand );
  if ( ( fp= popen( systemcommand, "r" ) ) == NULL ) {
   fprintf( stderr, "ERROR in get_string_with_fov_of_wcs_calibrated_image() while opening pipe!\n" );
   return 1;
  }
  if ( 1 == fscanf( fp, "%f", &image_scale ) ) {
   if ( image_scale > 0.0 ) {
    image_size= image_scale * 2.0 * finder_char_pix_around_the_target / 60.0;
    if ( image_size > 0.0 ) {
     ( *output_float_fov_arcmin )= image_size;
     // print small FoV in arcmin, and large in degrees
     if ( image_size < 120.0 ) {
      sprintf( output_string, "Field of view: %.0f'x%.0f'", image_size, image_size );
     } else {
      sprintf( output_string, "Field of view: %.1f^x%.1f^", image_size / 60.0, image_size / 60.0 );
     }
    }
   }
  }
  pclose( fp );
 } else {
  // Full-frame image
  sprintf( systemcommand, "%sutil/fov_of_wcs_calibrated_image.sh %s", path_to_vast_string, fitsfilename );
  fprintf( stderr, "Trying to run\n %s\n", systemcommand );
  if ( ( fp= popen( systemcommand, "r" ) ) == NULL ) {
   fprintf( stderr, "ERROR in get_string_with_fov_of_wcs_calibrated_image() while opening pipe!\n" );
   return 1;
  }
  if ( NULL != fgets( output_string, 1024, fp ) ) {
   output_string[1024 - 1]= '\0'; // just in case
   // remove new line character from the end of the string
   for ( string_char_counter= 0; string_char_counter < strlen( output_string ); string_char_counter++ ) {
    if ( output_string[string_char_counter] == '\n' ) {
     output_string[string_char_counter]= '\0';
    }
   }
  }
  pclose( fp );
 }
 /*
 // On success, these functions return the number of input items successfully matched and assigned
 if( 1!=fscanf(fp,"%s",output_string) ){
  fprintf(stderr,"ERROR in get_string_with_fov_of_wcs_calibrated_image() Cannot read the command output\n");
  output_string[0]='\0'; // reset output just in case
  return 1;
 }
 pclose(fp);
 if( pclose(fp) )  {
  fprintf(stderr,"ERROR in get_string_with_fov_of_wcs_calibrated_image() Command not found or exited with error status\n");
  output_string[0]='\0'; // reset output just in case
  return 1;
 }
 */
 return 0;
}

int xy2sky( char *fitsfilename, float X, float Y ) {
 char path_to_vast_string[VAST_PATH_MAX];
 char systemcommand[2 * VAST_PATH_MAX];
 int systemcommand_return_value;
 get_path_to_vast( path_to_vast_string );
 path_to_vast_string[VAST_PATH_MAX - 1]= '\0'; // just in case
 // fprintf(stderr,"DEBUG xy2sky(): path_to_vast_string = %s\n",path_to_vast_string);
 sprintf( systemcommand, "%slib/bin/xy2sky %s %lf %lf >> /dev/stderr", path_to_vast_string, fitsfilename, X, Y );
 systemcommand[2 * VAST_PATH_MAX - 1]= '\0'; // just in case
 systemcommand_return_value= system( systemcommand );
 if ( systemcommand_return_value == 0 ) {
  fprintf( stderr, "The pixel to celestal coordinates transforamtion is performed using 'xy2sky' from WCSTools.\n" );
 }
 return systemcommand_return_value;
}

int sky2xy( char *fitsfilename, char *input_RA_string, char *input_DEC_string, float *outX, float *outY ) {
 char path_to_vast_string[VAST_PATH_MAX];
 char systemcommand[2 * VAST_PATH_MAX];
 unsigned int i, n_semicol; // counter
 FILE *pipe_for_sky2xy;
 char command_output_string[VAST_PATH_MAX];

 char encoded_fitsfilename[FILENAME_LENGTH];
 char encoded_input_RA_string[FILENAME_LENGTH];
 char encoded_input_DEC_string[FILENAME_LENGTH];

 // Check all input strings
 safely_encode_user_input_string( encoded_fitsfilename, fitsfilename, FILENAME_LENGTH );
 encoded_fitsfilename[FILENAME_LENGTH - 1]= '\0';
 safely_encode_user_input_string( encoded_input_RA_string, input_RA_string, FILENAME_LENGTH );
 encoded_input_RA_string[FILENAME_LENGTH - 1]= '\0';
 safely_encode_user_input_string( encoded_input_DEC_string, input_DEC_string, FILENAME_LENGTH );
 encoded_input_DEC_string[FILENAME_LENGTH - 1]= '\0';

 // Check that the input coordinates are in the 01:02:03.45 +06:07:08.9 format
 n_semicol= 0;
 for ( i= 0; i < strlen( encoded_input_RA_string ); i++ ) {
  if ( encoded_input_RA_string[i] == ':' ) {
   n_semicol++;
  }
 }
 for ( i= 0; i < strlen( encoded_input_DEC_string ); i++ ) {
  if ( encoded_input_DEC_string[i] == ':' ) {
   n_semicol++;
  }
 }
 if ( n_semicol != 4 ) {
  ( *outX )= (float)atof( encoded_input_RA_string );
  ( *outY )= (float)atof( encoded_input_DEC_string );
  return 1;
 }
 //

 get_path_to_vast( path_to_vast_string );
 path_to_vast_string[VAST_PATH_MAX - 1]= '\0'; // just in case
 sprintf( systemcommand, "%slib/bin/sky2xy %s %s %s", path_to_vast_string, encoded_fitsfilename, encoded_input_RA_string, encoded_input_DEC_string );
 systemcommand[2 * VAST_PATH_MAX - 1]= '\0'; // just in case

 fprintf( stderr, "%s\n", systemcommand );

 pipe_for_sky2xy= popen( systemcommand, "r" );
 if ( NULL == pipe_for_sky2xy ) {
  ( *outX )= (float)atof( encoded_input_RA_string );
  ( *outY )= (float)atof( encoded_input_DEC_string );
  return 1;
 }
 if ( NULL == fgets( command_output_string, VAST_PATH_MAX, pipe_for_sky2xy ) ) {
  pclose( pipe_for_sky2xy );
  ( *outX )= (float)atof( encoded_input_RA_string );
  ( *outY )= (float)atof( encoded_input_DEC_string );
  return 1;
 }
 pclose( pipe_for_sky2xy );
 command_output_string[VAST_PATH_MAX - 1]= '\0'; // just in case
 if ( NULL != strstr( command_output_string, "off" ) ) {
  fprintf( stderr, "#### The specified celestial position is outside the image! ####\n" );
  ( *outX )= 0.0;
  ( *outY )= 0.0;
  return 1;
 }
 // expecting:
 // 18:19:53.683 -30:41:12.54 J2000 -> 1676.500 1266.500
 if ( 2 != sscanf( command_output_string, "%*s %*s J2000 -> %f %f", outX, outY ) ) {
  ( *outX )= (float)atof( encoded_input_RA_string );
  ( *outY )= (float)atof( encoded_input_DEC_string );
  return 1;
 }

 if ( ( *outX ) <= 0.0 || ( *outY ) <= 0.0 ) {
  ( *outX )= (float)atof( encoded_input_RA_string );
  ( *outY )= (float)atof( encoded_input_DEC_string );
  return 1;
 }

 return 0;
}

void write_list_of_all_stars_with_calibrated_magnitudes_to_file( float *sextractor_catalog__X, float *sextractor_catalog__Y, double *sextractor_catalog__MAG, double *sextractor_catalog__MAG_ERR, int *sextractor_catalog__star_number, int *sextractor_catalog__se_FLAG, int *sextractor_catalog__ext_FLAG, int sextractor_catalog__counter, char *sextractor_catalog_filename ) {
 FILE *outputfile;
 char outputfilename[FILENAME_LENGTH + 12];
 int i; // counter
 sprintf( outputfilename, "%s.calibrated", sextractor_catalog_filename );
 outputfile= fopen( outputfilename, "w" );
 if ( NULL == outputfile ) {
  fprintf( stderr, "ERROR writing %s\n", outputfilename );
  return;
 }
 for ( i= 0; i < sextractor_catalog__counter; i++ ) {
  // OK not all, we want to filter-out the obviously bad ones
  if ( 0 != isnan( sextractor_catalog__MAG[i] ) ) {
   continue;
  }
  if ( 0 != isinf( sextractor_catalog__MAG[i] ) ) {
   continue;
  }
  if ( 0 != isnan( sextractor_catalog__X[i] ) ) {
   continue;
  }
  if ( 0 != isnan( sextractor_catalog__Y[i] ) ) {
   continue;
  }
  if ( 0 != isinf( sextractor_catalog__X[i] ) ) {
   continue;
  }
  if ( 0 != isinf( sextractor_catalog__Y[i] ) ) {
   continue;
  }
#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
#ifdef VAST_USE_BUILTIN_FUNCTIONS
// Make a proper check of the input values if isnormal() is defined
#if defined _ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L
  // We use __builtin_isnormal() as we know it is working if VAST_USE_BUILTIN_FUNCTIONS is defined
  // Othervise even with the '_ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L' check
  // isnormal() doesn't work on Ubuntu 14.04 trusty (vast.sai.msu.ru)
  // BEWARE 0.0 is also not considered normal by isnormal() !!!
  if ( 0 == __builtin_isnormal( sextractor_catalog__MAG[i] ) ) {
   continue;
  }
  if ( 0 == __builtin_isnormal( sextractor_catalog__MAG_ERR[i] ) ) {
   continue;
  }
  if ( 0 == __builtin_isnormal( sextractor_catalog__X[i] ) ) {
   continue;
  }
  if ( 0 == __builtin_isnormal( sextractor_catalog__Y[i] ) ) {
   continue;
  }
#endif
#endif
  // Check the input mag
  if ( sextractor_catalog__MAG[i] < BRIGHTEST_STARS ) {
   continue;
  }
  // A similar check for the expected faintest stars
  if ( sextractor_catalog__MAG[i] > FAINTEST_STARS_ANYMAG ) {
   continue;
  }

  // Check if the measurement errors are not too big
  if ( sextractor_catalog__MAG_ERR[i] > MAX_MAG_ERROR ) {
   continue;
  }

#endif

  if ( sextractor_catalog__se_FLAG[i] > 3 ) {
   continue;
  }
  if ( sextractor_catalog__ext_FLAG[i] > 0 ) {
   continue;
  }

  //
  fprintf( outputfile, "%8.4lf %.4lf  %10.5f %10.5f  %6d  %3d %1d\n", sextractor_catalog__MAG[i], sextractor_catalog__MAG_ERR[i], sextractor_catalog__X[i], sextractor_catalog__Y[i], sextractor_catalog__star_number[i], sextractor_catalog__se_FLAG[i], sextractor_catalog__ext_FLAG[i] );
 }
 fclose( outputfile );
 fprintf( stderr, "The list of stars with calibrated magnitudes is written to \E[01;31m %s \E[33;00m\n", outputfilename );
 return;
}

void print_pgfv_help() {
 fprintf( stderr, "\n" );
 fprintf( stderr, "  --*** HOW TO USE THE IMAGE VIEWER ***--\n\n" );
 fprintf( stderr, "press 'I' to get this message.\n" );
 fprintf( stderr, "press 'Z' and draw rectangle to zoom in.\n" );
 fprintf( stderr, "press 'D' or click middle mouse button to return to the original zoom.\n" );
 fprintf( stderr, "press 'H' for Histogram Equalization.\n" );
 fprintf( stderr, "press 'B' to invert X axis.\n" );
 fprintf( stderr, "press 'V' to invert Y axis.\n" );
 fprintf( stderr, "move mouse and press 'F' to adjust image brightness/contrast. If an image apears too bright, move the pointer to the lower left and press 'F'. Repeat it many times to achive the desired result.\n" );
 fprintf( stderr, "press 'M' to turn star markers on/off.\n" );
 fprintf( stderr, "press 'X' or right click to exit!\nclick on image to get coordinates and value of the current pixel.\n" );
 fprintf( stderr, "\n" );
 fprintf( stderr, "press '2' to perform manual single-image magnitude calibration.\n" );
 fprintf( stderr, "press '4' to perform automated single-image magnitude calibration.\n" );
 fprintf( stderr, "\n" );
 return;
}

// Special function for handling online access to HLA images
int download_hla_image_if_this_is_it_and_modify_imagename( char *fits_image_name, float markX, float markY ) {
 unsigned int i;
 char system_command[4096];
 char output_fits_image_name[FILENAME_LENGTH];
 // first check if this looks like an HLA image
 // hst_12911_47_wfc3_uvis_f775w
 if ( 12 > strlen( fits_image_name ) )
  return 1; // filename too short
 if ( 60 < strlen( fits_image_name ) )
  return 1; // filename too long
 if ( fits_image_name[0] != 'h' )
  return 1;
 if ( fits_image_name[1] != 's' )
  return 1;
 if ( fits_image_name[2] != 't' )
  return 1;
 if ( fits_image_name[3] != '_' )
  return 1;
 if ( 0 != strcmp( fits_image_name, basename( fits_image_name ) ) )
  return 1; // file system path information - not our case
 for ( i= 0; i < strlen( fits_image_name ); i++ ) {
  if ( fits_image_name[i] == '.' )
   return 1; // there is an extension - surely it's a filename, not our case
 }
 // ok, if we are still here, assume we have an HLA image
 // generate_an_output_filename
 sprintf( output_fits_image_name, "wcs_%s_%.6f_%.6f.fits", fits_image_name, markX, markY );
 // check if this file already exist
 if ( 0 == fitsfile_read_check( output_fits_image_name ) ) {
  strncpy( fits_image_name, output_fits_image_name, FILENAME_LENGTH - 1 );
  fits_image_name[FILENAME_LENGTH - 1]= '\0'; // just in case
  return 0;
 }
 sprintf( system_command, "LANG=C wget -c -O %s 'http://hla.stsci.edu/cgi-bin/fitscut.cgi?red=%s&RA=%.6f&Dec=%.6f&Size=64&Format=fits&ApplyOmega=true'\n", output_fits_image_name, fits_image_name, markX, markY );
 fprintf( stderr, "Downloading a cutout from HLA image %s\n%s\n", fits_image_name, system_command );
 if ( 0 == system( system_command ) ) {
  fprintf( stderr, "Success! =)\n" );
  strncpy( fits_image_name, output_fits_image_name, FILENAME_LENGTH - 1 );
  fits_image_name[FILENAME_LENGTH - 1]= '\0'; // just in case
  return 0;
 } else {
  fprintf( stderr, "Failed to download the image! :(\n" );
  return 1;
 }
 return 1;
}

/* Magnitude calibration for single image mode */
void magnitude_calibration_using_calib_txt( double *mag, int N ) {
 int i;
 double a, b, c;
 double a_[4];
 int operation_mode;
 FILE *f;
 /* Check if calib.txt is readable */
 f= fopen( "calib.txt", "r" );
 if ( f == NULL )
  return;
 fclose( f );
 if ( 0 != system( "lib/fit_mag_calib > calib.tmp" ) ) {
  fprintf( stderr, "ERROR running  lib/fit_mag_calib > calib.tmp\n" );
  return;
 }
 f= fopen( "calib.tmp", "r" );
 if ( 5 == fscanf( f, "%d %lf %lf %lf %lf", &operation_mode, &a_[0], &a_[1], &a_[2], &a_[3] ) ) {
  // photocurve
  fprintf( stderr, "Calibrating the magnitude scale using the photocurve with parameters:\n%lf %lf %lf %lf\n", a_[0], a_[1], a_[2], a_[3] );
  for ( i= 0; i < N; i++ )
   mag[i]= eval_photocurve( mag[i], a_, operation_mode );
 } else {
  // parabola or straight line
  fseek( f, 0, SEEK_SET ); // go back to the beginning of the file
  if ( 3 > fscanf( f, "%lf %lf %lf", &a, &b, &c ) ) {
   fprintf( stderr, "ERROR parsing calib.tmp in magnitude_calibration_using_calib_txt()\n" );
  }
  fprintf( stderr, "Calibrating the magnitude scale using the polynom with parameters:\n%lf %lf %lf\n", a, b, c );
  for ( i= 0; i < N; i++ )
   mag[i]= a * mag[i] * mag[i] + b * mag[i] + c;
 }
 fclose( f );
 // system("rm -f calib.tmp");
 unlink( "calib.tmp" );
 return;
}

int get_ref_image_name( char *str ) {
 FILE *outfile;
 char stringbuf[2048];
 char stringtrash1[2048];
 char stringtrash2[2048];
 char stringtrash3[2048];
 char filenamestring[FILENAME_LENGTH];

 fprintf( stderr, "Getting the reference image name from vast_summary.log\n" );
 outfile= fopen( "vast_summary.log", "r" );
 if ( outfile == NULL ) {
  fprintf( stderr, "ERROR: cannot get the reference image name as there is no vast_summary.log\n" );
  exit( EXIT_FAILURE );
 }
 while ( NULL != fgets( stringbuf, 2048, outfile ) ) {
  stringbuf[2048 - 1]= '\0'; // just in case
  if ( NULL == strstr( stringbuf, "Ref.  image:" ) ) {
   continue;
  }
  // Example string to parse
  // Ref.  image: 2453192.38876 05.07.2004 21:18:19   ../sample_data/f_72-001r.fit
  // sscanf(stringbuf, "Ref.  image: %s %s %s   %s", stringtrash1, stringtrash2, stringtrash3, str);
  sscanf( stringbuf, "Ref.  image: %s %s %s   %s", stringtrash1, stringtrash2, stringtrash3, filenamestring );
  stringtrash1[2048 - 1]= '\0'; // just in case
  stringtrash2[2048 - 1]= '\0'; // just in case
  stringtrash3[2048 - 1]= '\0'; // just in case
  // The line below freaks out Address sanitizer
  // sscanf( stringbuf, "Ref.  image: %2048s %2048s %2048s   %s", stringtrash1, stringtrash2, stringtrash3, str );
 }
 fclose( outfile );
 fprintf( stderr, "The reference image is %s \n", str );

 if ( 0 != safely_encode_user_input_string( str, filenamestring, FILENAME_LENGTH ) ) {
  fprintf( stderr, "ERROR: the reference image filename contains unexpected characters %s\n", filenamestring );
  return 1;
 }

 if ( 0 != fitsfile_read_check( str ) ) {
  fprintf( stderr, "ERROR: cannot open the reference image file %s \nHas this file moved?\n", str );
  return 1;
 }

 return 0;
}

void fix_array_with_negative_values( long NUM_OF_PIXELS, float *im ) {
 long i;
 float min, max;
 min= max= im[0];
 for ( i= 0; i < NUM_OF_PIXELS; i++ ) {
  if ( im[i] < min && im[i] > 0 )
   min= im[i];
  if ( im[i] > max && im[i] > 0 )
   max= im[i];
 }
 if ( min < 0.0 ) {
  for ( i= 0; i < NUM_OF_PIXELS; i++ )
   im[i]= im[i] - min;
  for ( i= 0; i < NUM_OF_PIXELS; i++ ) {
   if ( im[i] > max )
    max= im[i];
  }
  min= 0.001;
 }

 if ( max > 65535.0 ) {
  for ( i= 0; i < NUM_OF_PIXELS; i++ )
   im[i]= im[i] * 65535.0 / max;
 }
 max= 65535.0;

 return;
}

void image_minmax2( long NUM_OF_PIXELS, float *im, float *max_i, float *min_i ) {
 int i;
 int HIST[65536];
 int summa= 0;
 int limit;
 int hist_summa= 0;
 ( *max_i )= ( *min_i )= im[0];
 // set all histogram values to 0
 for ( i= 0; i < 65536; i++ ) {
  HIST[i]= 0;
 }

 for ( i= 0; i < NUM_OF_PIXELS; i++ ) {
  if ( im[i] > 0 && im[i] < 65535 ) {
   HIST[(long)( im[i] + 0.5 )]+= 1;
   if ( im[i] > ( *max_i ) )
    ( *max_i )= im[i];
   if ( im[i] < ( *min_i ) )
    ( *min_i )= im[i];
  }
 }

 for ( i= 0; i < 65535; i++ ) {
  hist_summa+= HIST[i];
 }

 limit= (long)( ( (double)hist_summa - (double)hist_summa * PGFV_CUTS_PERCENT / 100.0 ) / 2.0 );

 //////////////////////
 // Try the percantage cuts only if the image range is not much smaller than 0 to 65535
 if ( ( *max_i ) < 10.0 ) {

  // set all histogram values to 0
  for ( i= 0; i < 65536; i++ ) {
   HIST[i]= 0;
  }

  for ( i= 0; i < NUM_OF_PIXELS; i++ ) {
   if ( im[i] > 0 && im[i] < 65535 ) {
    HIST[(long)( 65535 / 10.0 * im[i] + 0.5 )]+= 1;
    if ( im[i] > ( *max_i ) )
     ( *max_i )= im[i];
    if ( im[i] < ( *min_i ) )
     ( *min_i )= im[i];
   }
  }

  // find histogram peak
  summa= 0;
  for ( i= 0; i < 65535; i++ ) {
   if ( summa < HIST[i] ) {
    ( *min_i )= (float)i / 65535 * 10.0;
    summa= HIST[i];
   }
  }
  ( *min_i )-= ( *min_i ) * 2 / 3;
  ( *min_i )= MAX( ( *min_i ), 0 ); // do not go for very negatve values - they are likely wrong
  summa= 0;
  for ( i= 65535; i > 1; i-- ) {
   summa+= HIST[i];

   if ( summa >= limit ) {
    ( *max_i )= (float)i / 65535 * 10.0;
    break;
   }
  }

  // fprintf( stderr, "DEBUG: image_minmax2() %f %f\n", ( *min_i ), ( *max_i ) );
  return;
 }
 //////////////////////

 // find histogram peak
 summa= 0;
 for ( i= 0; i < 65535; i++ ) {
  if ( summa < HIST[i] ) {
   ( *min_i )= (float)i;
   summa= HIST[i];
  }
 }

 ( *min_i )-= ( *min_i ) * 2 / 3;

 ( *min_i )= MAX( ( *min_i ), 0 ); // do not go for very negatve values - they are likely wrong

 summa= 0;
 for ( i= 65535; i > 1; i-- ) {
  summa+= HIST[i];

  if ( summa >= limit ) {
   ( *max_i )= (float)i;
   break;
  }
 }

 return;
}

void image_minmax3( long NUM_OF_PIXELS, float *im, float *max_i, float *min_i, float drawX1, float drawX2, float drawY1, float drawY2, long *naxes ) {
 long i;
 int HIST[65536];
 int summa= 0;
 int hist_summa= 0;
 ( *max_i )= ( *min_i )= im[0];

 float X, Y;

 int test_i;

 int limit;

 // int number_of_pixels_in_zoomed_image;

 if ( NUM_OF_PIXELS <= 0 ) {
  fprintf( stderr, "FATAL ERROR in image_minmax3(): NUM_OF_PIXELS<=0 \n" );
  exit( EXIT_FAILURE );
 }

 /*
 // Do not allow sub-pixel zoom
 number_of_pixels_in_zoomed_image=0;
 for ( i= 0; i < NUM_OF_PIXELS; i++ ) {
  if ( im[i] > 0 && 65535/10.0*im[i] < 65535 ) {
   // Cool it works!!! (Transformation from i to XY)
   Y= 1 + (int)( (float)i / (float)naxes[0] );
   X= i + 1 - ( Y - 1 ) * naxes[0];
   if ( X > MIN( drawX1, drawX2 ) && X < MAX( drawX1, drawX2 ) && Y > MIN( drawY1, drawY2 ) && Y < MAX( drawY1, drawY2 ) ) {
    number_of_pixels_in_zoomed_image++;
   }
  }
 }
 if ( number_of_pixels_in_zoomed_image<16 ) {
  return;
 }
 //////////////////
*/
 // set all histogram values to 0
 for ( i= 0; i < 65536; i++ )
  HIST[i]= 0;

 for ( i= 0; i < NUM_OF_PIXELS; i++ ) {
  if ( im[i] > 0 && im[i] < 65535 ) {
   // Cool it works!!! (Transformation from i to XY)
   Y= 1 + (int)( (float)i / (float)naxes[0] );
   X= i + 1 - ( Y - 1 ) * naxes[0];
   if ( X > MIN( drawX1, drawX2 ) && X < MAX( drawX1, drawX2 ) && Y > MIN( drawY1, drawY2 ) && Y < MAX( drawY1, drawY2 ) ) {
    HIST[(long)( im[i] + 0.5 )]+= 1;
    if ( im[i] > ( *max_i ) )
     ( *max_i )= im[i];
    if ( im[i] < ( *min_i ) )
     ( *min_i )= im[i];
   }
  }
 }

 //////////////////////
 // Try the percantage cuts only if the image range is not much smaller than 0 to 65535
 if ( ( *max_i ) < 10.0 ) {

  // set all histogram values to 0
  for ( i= 0; i < 65536; i++ ) {
   HIST[i]= 0;
  }

  for ( i= 0; i < NUM_OF_PIXELS; i++ ) {
   if ( im[i] > 0 && 65535 / 10.0 * im[i] < 65535 ) {
    // Cool it works!!! (Transformation from i to XY)
    Y= 1 + (int)( (float)i / (float)naxes[0] );
    X= i + 1 - ( Y - 1 ) * naxes[0];
    if ( X > MIN( drawX1, drawX2 ) && X < MAX( drawX1, drawX2 ) && Y > MIN( drawY1, drawY2 ) && Y < MAX( drawY1, drawY2 ) ) {
     HIST[(long)( 65535 / 10.0 * im[i] + 0.5 )]+= 1;
     if ( im[i] > ( *max_i ) )
      ( *max_i )= im[i];
     if ( im[i] < ( *min_i ) )
      ( *min_i )= im[i];
    }
   }
  }

  // find histogram peak
  summa= 0;
  for ( i= 0; i < 65535; i++ ) {
   if ( summa < HIST[i] ) {
    ( *min_i )= MIN( ( *min_i ), (float)i / 65535 * 10.0 );
    summa= HIST[i];
   }
  }
  ( *min_i )-= ( *min_i ) * 2 / 3;
  ( *min_i )= MAX( ( *min_i ), 0 ); // do not go for very negatve values - they are likely wrong

  summa= 0;
  // for ( i= 65535; i > 1; i-- ) {
  for ( i= 65535; i--; ) {
   summa+= HIST[i];
  }
  limit= (long)( ( (double)summa - (double)summa * PGFV_CUTS_PERCENT / 100.0 ) / 2.0 );

  summa= 0;
  // for ( i= 65535; i > 1; i-- ) {
  for ( i= 65535; i--; ) {
   summa+= HIST[i];

   if ( summa >= limit ) {
    ( *max_i )= MIN( ( *max_i ), (float)i / 65535 * 10.0 );
    break;
   }
  }

  // fprintf( stderr, "DEBUG: image_minmax3() %f %f\n", ( *min_i ), ( *max_i ) );
  return;
 }
 //////////////////////

 for ( i= 0; i < 65535; i++ )
  hist_summa+= HIST[i];

 summa= 0;
 for ( i= 0, test_i= 0; i < 65535; i++ ) {
  summa+= HIST[i];
  if ( summa >= (int)( PGFV_CUTS_PERCENT / 100.0 * (float)hist_summa ) ) {
   //(*max_i)=(float)i;
   ( *max_i )= (float)test_i;
   break;
  }
  if ( HIST[i] != 0 )
   test_i= i;
 }

 summa= 0;
 for ( i= 0; i < 65535; i++ ) {
  summa+= HIST[i];
  if ( summa >= (int)( 2.0 * ( 1.0 - PGFV_CUTS_PERCENT / 100.0 ) * (float)hist_summa ) ) {
   ( *min_i )= (float)i;
   break;
  }
 }

 ( *max_i )= MIN( ( *max_i ), 65535 ); // just in case...

 ( *min_i )= MAX( ( *min_i ), 0 ); // do not go for very negatve values - they are likely wrong

 ( *max_i )= MAX( ( *max_i ), ( *min_i ) + 1 ); // for the countrate images (like the HST ones)

 // fprintf(stderr,"DEBUG: %lf  %lf\n",(*min_i),(*max_i));

 return;
}

/*
   Histogram equalization is a method in image processing of contrast adjustment using the image's histogram.
   See http://en.wikipedia.org/wiki/Histogram_equalization for details.
*/
void histeq( long NUM_OF_PIXELS, float *im, float *max_i, float *min_i ) {
 long i;
 int HIST[65536];
 int NO_OF_PIX_BELOW_I[65536];
 ( *max_i )= -9999.0;
 ( *min_i )= 9999.0;
 for ( i= 0; i < 65536; i++ ) {
  HIST[i]= 0;
  NO_OF_PIX_BELOW_I[i]= 0;
 }
 for ( i= 0; i < NUM_OF_PIXELS; i++ ) {
  if ( im[i] > ( *max_i ) )
   ( *max_i )= im[i];
  if ( im[i] < ( *max_i ) )
   ( *min_i )= im[i];
 }
 for ( i= 0; i < NUM_OF_PIXELS; i++ ) {
  HIST[MAX( 0, (int)( im[i] + 0.5 ) )]+= 1;
 }
 NO_OF_PIX_BELOW_I[0]= HIST[0];
 for ( i= 1; i < 65536; i++ ) {
  NO_OF_PIX_BELOW_I[i]= NO_OF_PIX_BELOW_I[i - 1] + HIST[i];
 }
 for ( i= 0; i < NUM_OF_PIXELS; i++ ) {
  im[i]= NO_OF_PIX_BELOW_I[MAX( 0, (int)( im[i] + 0.5 ) )] * ( *max_i ) / NUM_OF_PIXELS;
 }
 return;
}

int myimax( int A, int B ) {
 if ( A > B )
  return A;
 else
  return B;
}

/*
int myimin( int A, int B ) {
 if ( A < B )
  return A;
 else
  return B;
}
*/

int mymax( float A, float B ) {
 if ( A > B )
  return trunc( round( A ) );
 else
  return trunc( round( B ) );
}

int mymin( float A, float B ) {
 if ( A < B )
  return trunc( round( A ) );
 else
  return trunc( round( B ) );
}

int return_one_if_the_input_image_is_among_the_recently_processed_onses_listed_in_vast_image_details_log( char *fits_image_name ) {
 FILE *file_vast_image_details_log;
 char image_filename_from_the_file[FILENAME_LENGTH];
 file_vast_image_details_log= fopen( "vast_image_details.log", "r" );
 if ( NULL == file_vast_image_details_log ) {
  // no vast_image_details.log, so the input image is surely not there
  return 0;
 }
 //                                            1   2   3   4   5   6   7   8   9   10  11  12  13  14  15  16  17
 while ( -1 < fscanf( file_vast_image_details_log, "%*s %*s %*s %*s %*s %*s %*s %*s %*s %*s %*s %*s %*s %*s %*s %*s %s", image_filename_from_the_file ) ) {
  // fprintf(stderr,"DEBUG: %s\n",image_filename_from_the_file);
  if ( 0 == strncmp( image_filename_from_the_file, fits_image_name, MIN( strlen( fits_image_name ), strlen( image_filename_from_the_file ) ) ) ) {
   // fprintf(stderr,"DEBUG: %s       ---- YESS\n",image_filename_from_the_file);
   fclose( file_vast_image_details_log );
   return 1;
  }
 }
 fclose( file_vast_image_details_log );
 return 0;
}

int find_XY_position_of_a_star_on_image_from_vast_format_lightcurve( float *X_known_variable, float *Y_known_variable, char *lightcurvefilename, char *fits_image_name ) {
 double jd, mag, merr, x, y, app;
 char string[FILENAME_LENGTH];
 FILE *lightcurvefile;
 lightcurvefile= fopen( lightcurvefilename, "r" );
 if ( lightcurvefile == NULL ) {
  fprintf( stderr, "No lightcurve file %s\n", lightcurvefilename );
  return 0; // not found
 }
 while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, NULL ) ) {
  if ( jd == 0.0 ) {
   continue; // if this line could not be parsed, try the next one
  }
  if ( 0 == strncmp( string, fits_image_name, strlen( fits_image_name ) ) ) {
   fprintf( stderr, "%lf %lf\n", x, y );
   ( *X_known_variable )= (float)x;
   ( *Y_known_variable )= (float)y;
   fclose( lightcurvefile );
   return 1; // found
  }
 }
 fclose( lightcurvefile );
 fprintf( stderr, "not found on this image\n" );
 return 0; // not found, if we are still here
}

void load_markers_for_known_variables( float *markX_known_variable, float *markY_known_variable, int *mark_known_variable_counter, char *fits_image_name ) {
 FILE *list_of_known_vars_file;
 char full_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char lightcurvefilename[OUTFILENAME_LENGTH];
 char string_with_star_id_and_info[2048];
 list_of_known_vars_file= fopen( "vast_list_of_previously_known_variables.log", "r" );
 if ( list_of_known_vars_file == NULL ) {
  ( *mark_known_variable_counter )= 0;
  return;
 }
 fprintf( stderr, "Loading known variables from vast_list_of_previously_known_variables.log\n" );
 while ( NULL != fgets( full_string, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, list_of_known_vars_file ) ) {
  sscanf( full_string, "%s %[^\t\n]", lightcurvefilename, string_with_star_id_and_info );
  fprintf( stderr, "Loading known variable %s ... ", lightcurvefilename );
  if ( 1 == find_XY_position_of_a_star_on_image_from_vast_format_lightcurve( &markX_known_variable[( *mark_known_variable_counter )], &markY_known_variable[( *mark_known_variable_counter )], lightcurvefilename, fits_image_name ) ) {
   ( *mark_known_variable_counter )++;
  }
 }
 fprintf( stderr, "Loaded %d known variables.\n", ( *mark_known_variable_counter ) );
 return;
}

void load_markers_for_autocandidate_variables( float *markX_known_variable, float *markY_known_variable, int *mark_known_variable_counter, char *fits_image_name ) {
 FILE *list_of_known_vars_file;
 char full_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char lightcurvefilename[OUTFILENAME_LENGTH];
 char string_with_star_id_and_info[2048];
 list_of_known_vars_file= fopen( "vast_autocandidates.log", "r" );
 if ( list_of_known_vars_file == NULL ) {
  ( *mark_known_variable_counter )= 0;
  return;
 }
 fprintf( stderr, "Loading autocandidate variables from vast_autocandidates.log\n" );
 while ( NULL != fgets( full_string, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, list_of_known_vars_file ) ) {
  sscanf( full_string, "%s %[^\t\n]", lightcurvefilename, string_with_star_id_and_info );
  fprintf( stderr, "Loading candidate variable %s ... ", lightcurvefilename );
  if ( 1 == find_XY_position_of_a_star_on_image_from_vast_format_lightcurve( &markX_known_variable[( *mark_known_variable_counter )], &markY_known_variable[( *mark_known_variable_counter )], lightcurvefilename, fits_image_name ) ) {
   ( *mark_known_variable_counter )++;
  }
 }
 fprintf( stderr, "Loaded %d candidate variables.\n", ( *mark_known_variable_counter ) );
 return;
}

int main( int argc, char **argv ) {

 /* For FITS file reading */
 fitsfile *fptr; /* pointer to the FITS file; defined in fitsio.h */
 // long  fpixel = 1, naxis = 2, nelements, exposure;
 long naxes[2];
 int status= 0;
 int bitpix;
 int anynul= 0;
 // int nullval=0;
 float nullval= 0.0;
 unsigned char nullval_uchar= 0;
 unsigned short nullval_ushort= 0;
 unsigned int nullval_uint= 0;
 double nullval_double= 0.0;
 unsigned char *image_array_uchar;
 unsigned short *image_array_ushort;
 unsigned int *image_array_uint;
 double *image_array_double;
 float *real_float_array;
 float *float_array;
 float *float_array2;
 // long x,y;
 int i;
 /* PGPLOT vars */
 // float current_color=0.0;
 float curX, curY, curX2, curY2;
 char curC= 'R';
 float tr[6];
 tr[0]= 0;
 tr[1]= 1;
 tr[2]= 0;
 tr[3]= 0;
 tr[4]= 0;
 tr[5]= 1;
 int drawX1, drawX2, drawY1, drawY2, drawX0, drawY0;
 float min_val;
 float max_val;

 int hist_trigger= 0;
 int mark_trigger= 0;

 float markX= 0.0;
 float markY= 0.0;
 // float finder_char_pix_around_the_target= 10.0; // default thumbnail image size for transient search
 float finder_char_pix_around_the_target= 20.0; // default thumbnail image size for transient search

 /* new fatures */
 // int buf,v_trigger=0,b_trigger=0;
 int buf;
 // int j;
 float axis_ratio;
 double razmer_x, razmer_y;

 char fits_image_name[FILENAME_LENGTH];
 char fits_image_name_string_for_display[FILENAME_LENGTH];
 int match_mode= 0;
 // char sex_command_string[2048];
 double APER= 0.0; // just reset it

 int bad_size;

 /* Sex Cat */
 FILE *catfile;
 // double MUSOR;
 // int intMUSOR;
 // int iMUSOR;
 float *sextractor_catalog__X= NULL;
 float *sextractor_catalog__Y= NULL;
 double *sextractor_catalog__FLUX= NULL;
 double *sextractor_catalog__FLUX_ERR= NULL;
 double *sextractor_catalog__MAG= NULL;
 double *sextractor_catalog__MAG_ERR= NULL;
 int *sextractor_catalog__star_number= NULL;
 int *sextractor_catalog__se_FLAG= NULL;
 int *sextractor_catalog__ext_FLAG= NULL;
 double *sextractor_catalog__psfCHI2= NULL;

 double *sextractor_catalog__A_IMAGE= NULL;
 double *sextractor_catalog__ERRA_IMAGE= NULL;
 double *sextractor_catalog__B_IMAGE= NULL;
 double *sextractor_catalog__ERRB_IMAGE= NULL;

 int sextractor_catalog__counter= 0;
 int marker_counter;

 float *sextractor_catalog__X_viewed= NULL;
 float *sextractor_catalog__Y_viewed= NULL;
 int sextractor_catalog__viewed_counter;

 float *markX_known_variable= NULL;
 float *markY_known_variable= NULL;
 int mark_known_variable_counter;
 float *markX_autocandidate_variable= NULL;
 float *markY_autocandidate_variable= NULL;
 int mark_autocandidate_variable_counter;

 int use_north_east_marks= 1;
 int use_labels= 1;
 int use_datestringinsideimg= 0;
 int use_imagesizestringinsideimg= 0;
 int fits2png_fullframe= 0;
 int use_target_mark= 0;
 float lineX[2];
 float lineY[2];
 float marker_scaling;
 char namelabel[256];
 namelabel[0]= '\0';

 /* Match File */
 FILE *matchfile;
 char RADEC[1024];
 int match_input= 0;
 // double HH,HM,HS,DD,DM,DS;
 // char syscommand[1024];

 /* Calib mode */
 FILE *calibfile;
 double tmp_APER= 0.0;
 char imagefilename[1024 + FILENAME_LENGTH];
 char system_command[1024 + FILENAME_LENGTH];
 int N;
 double catalog_mag;
 char filtered_string[1024 + FILENAME_LENGTH];
 int ii, jj, first_number_flag;

 char filter_name_for_automatic_magnitude_calibration[512];
 char filter_name_for_automatic_magnitude_calibration_local[512];

 /* For time information from the FITS header */
 double JD;
 double dimX;
 double dimY;
 char stderr_output[2 * 1024 + 2 * FILENAME_LENGTH];
 char log_output[1024 + FILENAME_LENGTH];
 char finder_chart_timestring_output[2 * 1024 + 2 * FILENAME_LENGTH];
 char finder_chart_string_to_print[2 * 1024 + 2 * FILENAME_LENGTH + 8];

 int timesys= 0;
 int convert_timesys_to_TT= 0;

 int draw_star_markers= 1;
 int aperture_change= 0;

 double median_class_star;
 // double sigma_class_star;

 static float bw_l[]= { -0.5, 0.0, 0.5, 1.0, 1.5, 2.0 };
 static float bw_r[]= { 0.0, 0.0, 0.5, 1.0, 1.0, 1.0 };
 static float bw_g[]= { 0.0, 0.0, 0.5, 1.0, 1.0, 1.0 };
 static float bw_b[]= { 0.0, 0.0, 0.5, 1.0, 1.0, 1.0 };

 char sextractor_catalog_filename[FILENAME_LENGTH];

 int finder_chart_mode= 0; // =1 draw finding chart to an image file instead of interactive plotting

 int inverted_X_axis= 0;
 int inverted_Y_axis= 1; // start with inverted Y axis

 char sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT];
 int external_flag; // flag image info, if available
                    // double double_external_flag;
 double psf_chi2;
 // char external_flag_string[256];

 int use_xy2sky= 2; // 0 - no, 1 - yes, 2 - don't know
 int xy2sky_return_value;

 if ( 0 == strcmp( "make_finder_chart", basename( argv[0] ) ) ) {
  fprintf( stderr, "Plotting finder chart...\n" );
  finder_chart_mode= 1;
  // mark_trigger= 1;
 }

 if ( 0 == strcmp( "make_finding_chart", basename( argv[0] ) ) ) {
  fprintf( stderr, "Plotting finding chart...\n" );
  finder_chart_mode= 1;
  // mark_trigger= 1;
 }

 if ( 0 == strcmp( "fits2png", basename( argv[0] ) ) ) {
  fprintf( stderr, "Plotting finding chart with no labels...\n" );
  finder_chart_mode= 1;
  use_north_east_marks= 0;
  use_labels= 0;
  fits2png_fullframe= 1;
 }

 /* Reading file which defines rectangular regions we want to exclude */
 float cpgline_tmp_x[2];
 float cpgline_tmp_y[2];
 double X1[500], Y1[500], X2[500], Y2[500];
 int N_bad_regions= 0;
 read_bad_CCD_regions_lst( X1, Y1, X2, Y2, &N_bad_regions );

 int use_ds9= 0; // if 1 - use ds9 instead of pgplot to display an image
 pid_t pid= getpid();
 char ds9_region_filename[1024];

 ////////////
 FILE *manymarkersfile;
 int manymrkerscounter;
 float manymarkersX[1024];
 float manymarkersY[1024];
 char manymarkersstring[2048];
 ////////////

 char fov_string[1024];
 float fov_float= 0.0;

 int image_specified_on_command_line__0_is_yes= 0; // 0 - yes, 1 - no, we'll get the image name from log file

 double fixed_aperture= 0.0;

 // for nanosleep()
 struct timespec requested_time;
 struct timespec remaining;
 requested_time.tv_sec= 0;
 requested_time.tv_nsec= 100000000;

 //
 int is_this_an_hla_image= 0; // 0 - no;  1 - yes; needed only to make proper labels

 //
 int is_this_north_up_east_left_image= 0; // For N/E labels on the finding chart

 int magnitude_calibration_already_performed_flag= 0; // do not perform the magnitude calibration twice if set to 1

 // Dummy vars
 // int star_number_in_sextractor_catalog;
 // double flux_adu;
 // double flux_adu_err;
 // double mag;
 // double sigma_mag;
 double position_x_pix;
 double position_y_pix;
 // double a_a;
 // double a_a_err;
 // double a_b;
 // double a_b_err;
 // int sextractor_flag;

 // Options for getopt()
 char *cvalue= NULL;

 const char *const shortopt= "a:w:9sdnlftb:";
 const struct option longopt[]= {
     { "apeture", 1, NULL, 'a' }, { "width", 1, NULL, 'w' }, { "ds9", 0, NULL, '9' }, { "imgsizestringinsideimg", 0, NULL, 's' }, { "datestringinsideimg", 0, NULL, 'd' }, { "nonortheastmarks", 0, NULL, 'n' }, { "nolabels", 0, NULL, 'l' }, { "targetmark", 0, NULL, 't' }, { "namelabel", 1, NULL, 'b' }, { NULL, 0, NULL, 0 } }; // NULL string must be in the end
 int nextopt;
 while ( nextopt= getopt_long( argc, argv, shortopt, longopt, NULL ), nextopt != -1 ) {
  switch ( nextopt ) {
  case 'a':
   cvalue= optarg;
   fixed_aperture= atof( cvalue );
   fprintf( stdout, "opt 'a': Using fixed aperture %.1lf pix. in diameter!\n", fixed_aperture );
   if ( fixed_aperture < 1.0 ) {
    fprintf( stderr, "ERROR: the specified fixed aperture dameter is out of the expected range!\n" );
    return 1;
   }
   break;
  case 'w':
   cvalue= optarg;
   finder_char_pix_around_the_target= (float)atof( cvalue );
   fprintf( stdout, "opt 'w': Plotting %.1lf pix. around the target!\n", finder_char_pix_around_the_target );
   if ( finder_char_pix_around_the_target < 1.0 ) {
    fprintf( stderr, "ERROR: the specified finder chart widt is out of the expected range!\n" );
    return 1;
   }
   break;
  case '9':
   use_ds9= 1;
   fprintf( stdout, "opt '9': Using ds9 to display images!\n" );
   break;
  case 's':
   use_imagesizestringinsideimg= 1;
   fprintf( stdout, "opt 's': image size will be displayed inside the image!\n" );
   break;
  case 'd':
   use_datestringinsideimg= 1;
   fprintf( stdout, "opt 'd': observing date will be displayed inside the image!\n" );
   break;
  case 'n':
   use_north_east_marks= 0;
   fprintf( stdout, "opt 'n': No North-East marks will be ploted!\n" );
   break;
  case 'l':
   use_labels= 0;
   fprintf( stdout, "opt 'l': No axes labels will be ploted!\n" );
   break;
  case 't':
   use_target_mark= 1;
   fprintf( stdout, "opt 't': Put target mark for the finder chart!\n" );
   break;
  case 'b':
   cvalue= optarg;
   strncpy( namelabel, cvalue, 256 );
   namelabel[256 - 1]= '\0';
   fprintf( stdout, "opt 'b': Adding label %s to the finding chart!\n", namelabel );
   break;
  case '?':
   if ( optopt == 'a' ) {
    fprintf( stderr, "Option -%c requires an argument: fixed aperture size in pix.!\n", optopt );
    exit( EXIT_FAILURE );
   }
   if ( optopt == 'w' ) {
    fprintf( stderr, "Option -%c requires an argument: finder chart size in pix.!\n", optopt );
    exit( EXIT_FAILURE );
   }
   if ( optopt == 'b' ) {
    fprintf( stderr, "Option -%c requires an argument: string with the target name!\n", optopt );
    exit( EXIT_FAILURE );
   }
   break;
  case -1:
   fprintf( stderr, "That's all\n" );
   break;
  }
 }
 optind--; //!!!

 //
 if ( use_labels == 1 && use_datestringinsideimg == 1 ) {
  fprintf( stderr, "We don't want the observing time string to be dispalyed two times - disabling the in-the-image display!\n" );
  use_datestringinsideimg= 0;
 }
 //

 if ( argc > 1 ) {

  // check for the depricated special case
  if ( 0 == strcasecmp( argv[optind + 1], "match" ) ) {
   fprintf( stderr, "The manual star-matching mode is no longer supported, sorry!\n" );
   return 1;
  }

  if ( 0 == strcasecmp( argv[optind + 1], "calib" ) ) {
   // special case to handle: './pgfv calib'
   // Magnitude calibration mode
   match_mode= 2;
   // that will be handled later
  } else {
   // the normal way

   if ( 0 == fitsfile_read_check_silent( argv[optind + 1] ) ) {
    // An image is specified on the command line
    image_specified_on_command_line__0_is_yes= 0;
   } else {
    // no image is specified on the comamnd line - try to get it from vast_summary.log
    //    if( 0 != get_ref_image_name(fits_image_name) ) {
    //     fprintf(stderr, "Usage:\n%s FITSIMAGE.fit\nor\n%s FITSIMAGE.fit X Y\nor\n%s FITSIMAGE.fit RA DEC\n\n", argv[0], argv[0], argv[0]);
    //     exit( EXIT_FAILURE );
    //    }
    image_specified_on_command_line__0_is_yes= 1;
   }
  }
 } else {
  image_specified_on_command_line__0_is_yes= 1; // no image on the command line as there is nothing there at all
 }                                              // else if( argc > 1 ) {

 /*
  if( 0 != strcmp("select_star_on_reference_image", basename(argv[0])) ) {
   if( argc == 1 ) {
    fprintf(stderr, "Usage:\n%s FITSIMAGE.fit\nor\n%s FITSIMAGE.fit X Y\nor\n%s FITSIMAGE.fit RA DEC\n\n", argv[0], argv[0], argv[0]);
   }
   // the normal way
  } else {
   // This is star selection on reference image mode
   match_mode= 1;
   // handle the special case where the image is specified on the command line when running select_star_on_reference_image
   if( 0 == fitsfile_read_check_silent(argv[optind + 1]) ) {
    image_specified_on_command_line__0_is_yes= 0;
    fprintf(stderr,"\n\nWARNING: an image is specified on the command line whne rinning %s!\nWill display the reference image instead.\n\n", basename(argv[0]) );
   } else {
    // the normal way when no image is specified on the command line when using select_star_on_reference_image
    image_specified_on_command_line__0_is_yes= 1;
   }
   if( 0 != get_ref_image_name(fits_image_name) ) {
    fprintf(stderr, "ERROR getting the reference image name from the log file\n");
    exit( EXIT_FAILURE );
   }
  }

  //if( match_mode != 1 && argc != 1 ) {
  // Somehow we handle match_mode==1 case separately above
  if( match_mode != 1 ) {
   //strcpy(fits_image_name, argv[optind + 1]);
   safely_encode_user_input_string(fits_image_name, argv[optind + 1], FILENAME_LENGTH);
  } else {
   fprintf(stderr, "DEBUUUUUUUGAAAAA");
   // handle the special case where the image is specified on the command line when running select_star_on_reference_image/other
   if( 0 == fitsfile_read_check_silent(argv[optind + 1]) ) {
    image_specified_on_command_line__0_is_yes= 0;
    fprintf(stderr,"\n\nWARNING: an image is specified on the command line while running %s!\nWill display the reference image instead.\n\n", basename(argv[0]) );
   } else {
    // the normal way when no image is specified on the command line when using select_star_on_reference_image/other
    image_specified_on_command_line__0_is_yes= 1;
   }
   // Get reference file name from log
   //get_ref_image_name(fits_image_name);
   if( 0 != get_ref_image_name(fits_image_name) ) {
    fprintf(stderr, "ERROR getting the reference image name from the log file\n");
    exit( EXIT_FAILURE );
   }
  }
 */

 if ( image_specified_on_command_line__0_is_yes != 0 && image_specified_on_command_line__0_is_yes != 1 ) {
  fprintf( stderr, "ERROR in %s: image_specified_on_command_line__0_is_yes = %d \n", argv[0], image_specified_on_command_line__0_is_yes );
  exit( EXIT_FAILURE );
 }

 // if( argc - optind == 5 ) {
 //  APER= atof(argv[optind + 4]);
 // }
 /*
  if( argc - optind + image_specified_on_command_line__0_is_yes == 5 ) {
   APER= atof(argv[optind - image_specified_on_command_line__0_is_yes + 4]);
   fprintf(stderr, "Aperture size specified on the command line: %.1lf (%s)\n", APER, argv[optind - image_specified_on_command_line__0_is_yes + 4] );
  }
 */

 // moved up
 // if( 0 == strcasecmp(fits_image_name, "calib") ) {
 //  // Magnitude calibration mode
 //  match_mode= 2;
 // }

 // if( 0 == strcasecmp(fits_image_name, "match") ) {
 //  fprintf(stderr, "The manual star-matching mode is no longer supported, sorry!\n");
 //  return 1;
 // }

 // moved here from above
 if ( 0 == strcmp( "select_star_on_reference_image", basename( argv[0] ) ) && match_mode == 0 ) {
  match_mode= 1;
 }

 if ( 0 == strcmp( "sextract_single_image", basename( argv[0] ) ) && match_mode == 0 ) {
  match_mode= 3;
 }

 if ( 0 == strcmp( "select_comparison_stars", basename( argv[0] ) ) && match_mode == 0 ) {
  match_mode= 4;

  // Remove old calib.txt
  matchfile= fopen( "calib.txt", "r" );
  if ( NULL != matchfile ) {
   fclose( matchfile );
   unlink( "calib.txt" );
  }
  // Remove old manually_selected_comparison_stars.lst
  matchfile= fopen( "manually_selected_comparison_stars.lst", "r" );
  if ( NULL != matchfile ) {
   fclose( matchfile );
   unlink( "manually_selected_comparison_stars.lst" );
  }
  // Remove old manually_selected_aperture.txt
  matchfile= fopen( "manually_selected_aperture.txt", "r" );
  if ( NULL != matchfile ) {
   fclose( matchfile );
   unlink( "manually_selected_aperture.txt" );
  }

 } // if ( 0 == strcmp( "select_comparison_stars", basename( argv[0] ) ) ) {

 // A reminder to myself:
 // match_mode == 0   - the normal image display
 // match_mode == 3   - sextract single image - not necessary the reference one

 if ( image_specified_on_command_line__0_is_yes == 1 ) {
  // no image specified on the comamnd line
  if ( match_mode == 0 ) {
   fprintf( stderr, "Usage:\n%s FITSIMAGE.fit\nor\n%s FITSIMAGE.fit X Y\nor\n%s FITSIMAGE.fit RA DEC\n\n", argv[0], argv[0], argv[0] );
   return 1;
  }
  // the image is not specified on the command line or this is some funny data reduction mode
  // -- get the image name from vast_summary.log
  if ( 0 != get_ref_image_name( fits_image_name ) ) {
   fprintf( stderr, "ERROR(1) getting the reference image name from the log file\n" );
   return 1;
  }
 } else {
  // an image is specified on the command line
  if ( match_mode == 0 || match_mode == 3 ) {
   safely_encode_user_input_string( fits_image_name, argv[optind + 1], FILENAME_LENGTH );
  } else {
   fprintf( stderr, "\n\nWARNING: an image is specified on the command line while running %s!\nWill display the reference image instead.\n\n", basename( argv[0] ) );
   // -- get the image name from vast_summary.log
   if ( 0 != get_ref_image_name( fits_image_name ) ) {
    fprintf( stderr, "ERROR(2) getting the reference image name from the log file\n" );
    return 1;
   }
  }
 }

 //////////////////////////////////////////////////////////////////////////////
 // by this time we should have the desired image name in fits_image_name
 // derived from the command line or the vast_summary.log file

 // Reformat file name for display
 strncpy( fits_image_name_string_for_display, fits_image_name, FILENAME_LENGTH ); // display the original file name, not symlink
 if ( strlen( fits_image_name_string_for_display ) > 70 ) {
  strncpy( fits_image_name_string_for_display, basename( fits_image_name ), FILENAME_LENGTH ); // display just the file name if the full path is too long and will not fit the screen anyhow
 }
 //

 replace_file_with_symlink_if_filename_contains_white_spaces( fits_image_name );
 cutout_green_channel_out_of_RGB_DSLR_image( fits_image_name );

 // fprintf(stderr,"\n\n\nDEBUUUUUUUG argc=%d  optind=%d  image_specified_on_command_line__0_is_yes=%d argv[optind - image_specified_on_command_line__0_is_yes + 2]=%s \n\n\n", argc, optind, image_specified_on_command_line__0_is_yes, argv[optind - image_specified_on_command_line__0_is_yes + 2]);

 // if( argc - optind >= 4 ) {
 //  // Now we need to figure out if the input values are pixel or celestial coordinates
 //  // Don't do this check if this is fits2png
 //  if( finder_chart_mode != 1 && use_labels != 0 ) {
 //   sky2xy(fits_image_name, argv[optind + 2], argv[optind + 3], &markX, &markY);
 //  } else {
 //   markX= (float)atof(argv[optind + 2]);
 //   markY= (float)atof(argv[optind + 3]);
 //  }
 //  if( markX > 0.0 && markY > 0.0 ) {
 //   mark_trigger= 1;
 //   fprintf(stderr, "Putting mark on pixel position %lf %lf\n", markX, markY);
 //  } else {
 //   fprintf(stderr, "The pixel position %lf %lf is outside the image!\n", markX, markY);
 //  }
 // }
 if ( argc - optind + image_specified_on_command_line__0_is_yes >= 4 ) {
  //

  // that will only work with pgfv - in star display modes APER
  // will be reset to the aperture size
  if ( argc - optind + image_specified_on_command_line__0_is_yes >= 5 ) {
   APER= atof( argv[optind - image_specified_on_command_line__0_is_yes + 4] );
   fprintf( stderr, "Aperture size specified on the command line: %.1lf (%s)\n", APER, argv[optind - image_specified_on_command_line__0_is_yes + 4] );
  }

  // Now we need to figure out if the input values are pixel or celestial coordinates
  // Don't do this check if this is fits2png
  if ( finder_chart_mode != 1 && use_labels != 0 ) {
   sky2xy( fits_image_name, argv[optind - image_specified_on_command_line__0_is_yes + 2], argv[optind - image_specified_on_command_line__0_is_yes + 3], &markX, &markY );
  } else {
   markX= (float)atof( argv[optind - image_specified_on_command_line__0_is_yes + 2] );
   markY= (float)atof( argv[optind - image_specified_on_command_line__0_is_yes + 3] );
  }
  if ( markX > 0.0 && markY > 0.0 ) {
   mark_trigger= 1;
   fprintf( stderr, "Putting mark on pixel position %lf %lf\n", markX, markY );
  } else {
   fprintf( stderr, "The pixel position %lf %lf is outside the image!\n", markX, markY );
  }
 }

 // Read manymarkers file if there is one
 manymrkerscounter= 0;
 manymarkersfile= fopen( "vast_manymarkersfile.log", "r" );
 if ( manymarkersfile != NULL ) {
  while ( -1 < fscanf( manymarkersfile, "%f %f %[^\t\n]", &manymarkersX[manymrkerscounter], &manymarkersY[manymrkerscounter], manymarkersstring ) )
   manymrkerscounter++;
  fprintf( stderr, "vast_manymarkersfile.log - %d markers\n", manymrkerscounter );
 }

 // fprintf(stderr,"DEBUG-5\n");

 if ( match_mode == 2 ) {
  // Magnitude calibration mode

  // Remove old calib.txt
  matchfile= fopen( "calib.txt", "r" );
  if ( NULL != matchfile ) {
   fclose( matchfile );
   // system("rm -f calib.txt");
   unlink( "calib.txt" );
  }

  // Allocate memory for the arrays
  sextractor_catalog__X= (float *)malloc( MAX_NUMBER_OF_STARS * sizeof( float ) );
  if ( sextractor_catalog__X == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__X\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__Y= (float *)malloc( MAX_NUMBER_OF_STARS * sizeof( float ) );
  if ( sextractor_catalog__Y == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__Y\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__MAG= (double *)malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( sextractor_catalog__MAG == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__MAG\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__MAG_ERR= (double *)malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( sextractor_catalog__MAG_ERR == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__MAG_ERR\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__star_number= (int *)malloc( MAX_NUMBER_OF_STARS * sizeof( int ) );
  if ( sextractor_catalog__star_number == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__star_number\n" );
   exit( EXIT_FAILURE );
  };
  marker_counter= 0;

  // Get reference file name from log
  // get_ref_image_name(fits_image_name);
  if ( 0 != get_ref_image_name( fits_image_name ) ) {
   fprintf( stderr, "ERROR getting the reference image name from the log file\n" );
   exit( EXIT_FAILURE );
  }

  // Read data.m_sigma but select only stars detected on the reference frame
  matchfile= fopen( "data.m_sigma", "r" );
  while ( -1 < fscanf( matchfile, "%lf %lf %f %f %s", &sextractor_catalog__MAG[sextractor_catalog__counter], &sextractor_catalog__MAG_ERR[sextractor_catalog__counter], &sextractor_catalog__X[sextractor_catalog__counter], &sextractor_catalog__Y[sextractor_catalog__counter], RADEC ) ) {
   calibfile= fopen( RADEC, "r" );
   if ( calibfile != NULL ) {
    // fscanf(calibfile,"%lf %lf %lf %lf %lf %lf %s",&MUSOR,&MUSOR,&MUSOR,&MUSOR,&MUSOR,&tmp_APER,imagefilename);
    if ( 2 > fscanf( calibfile, "%*f %*f %*f %*f %*f %lf %s", &tmp_APER, imagefilename ) ) {
     fprintf( stderr, "ERROR parsing %s\n", RADEC );
    }
    fclose( calibfile );
    if ( 0 == strcmp( imagefilename, fits_image_name ) ) {
     // Get number of observations for correct error estimation
     N= count_lines_in_ASCII_file( RADEC );
     sextractor_catalog__MAG_ERR[sextractor_catalog__counter]= sextractor_catalog__MAG_ERR[sextractor_catalog__counter] / sqrt( N - 1 );
     // done with errors
     // Note the star name
     sscanf( RADEC, "out%d.dat", &sextractor_catalog__star_number[sextractor_catalog__counter] );
     // remember aperture size, increase counter */
     APER= tmp_APER;
     sextractor_catalog__counter++;
    }
   }
  }
  fclose( matchfile );
  sextractor_catalog__counter--; // We can't be sure that the last star is visible on the reference frame so we just drop it
 }

 /*
  // WTF is this????
  if( 0 == strcasecmp(fits_image_name, "detect") ) {
   if( argc - optind < 3 ) {
    fprintf(stderr, "Usage: ./pgfv detect image.fit\n");
    exit( EXIT_FAILURE );
   }
   //strcpy(fits_image_name, argv[optind + 2]);
   //safely_encode_user_input_string(fits_image_name, argv[optind + 2], FILENAME_LENGTH);
   safely_encode_user_input_string(fits_image_name, argv[optind + 2], FILENAME_LENGTH);
   match_mode= 3;
  }
 */
 if ( match_mode == 3 ) {
  fprintf( stderr, "Entering single image reduction mode.\nProcessing image %s\n", fits_image_name );
  // We want to have this check early in order not to distract user with the following messages if the file is unreadable
  if ( 0 != fitsfile_read_check( fits_image_name ) ) {
   fprintf( stderr, "\nERROR: the input file %s does not appear to be a readable FITS image!\n", fits_image_name );
   return 1;
  }
  fprintf( stderr, "Use '+' or '-' to increase or decrease aperture size.\n" );
  fprintf( stderr, "\E[34;47mTo calibrate magnitude scale press '2'\E[33;00m (manual calibration) or \E[34;47m'4'\E[33;00m (automatic calibration)\n" );

  // Remove old calib.txt in case we'll want a magnitude calibration
  // system("rm -f calib.txt");
  calibfile= fopen( "calib.txt", "r" );
  if ( NULL != calibfile ) {
   fclose( calibfile );
   unlink( "calib.txt" );
  }
 }

 // fprintf(stderr,"DEBUG-4\n");

 /// handling HLA images
 if ( mark_trigger == 1 ) {
  if ( 0 == download_hla_image_if_this_is_it_and_modify_imagename( fits_image_name, markX, markY ) ) {
   // This has to change if the cutout is not 64pix
   markX= 32.0;
   markY= 32.0;
   APER= 0.0;
   //
   is_this_an_hla_image= 1;
  }
 }

 // Get time and frame size information from the FITS header
 if ( 0 != fitsfile_read_check( fits_image_name ) ) {
  fprintf( stderr, "\nERROR: the input file %s does not appear to be a readable FITS image!\n", fits_image_name );
  return 1;
 }
 int param_nojdkeyword= 0; // Temporary fix!!! pgfv cannot accept the --nojdkeyword parameter yet, only the main program vast understands it
 gettime( fits_image_name, &JD, &timesys, convert_timesys_to_TT, &dimX, &dimY, stderr_output, log_output, param_nojdkeyword, 0, finder_chart_timestring_output );
 if ( strlen( stderr_output ) < 10 ) {
  fprintf( stderr, "Warning after running gettime(): stderr_output is suspiciously short:\n" );
  fprintf( stderr, "#%s#\n", stderr_output );
 }
 stderr_output[strlen( stderr_output ) - 1]= '\0'; /* Remove \n at the end of line */
 // Special case of HLA images with no proper date
 if ( is_this_an_hla_image == 1 ) {
  stderr_output[0]= '\0';
 }
 //
 if ( finder_chart_mode == 1 ) {
  is_this_north_up_east_left_image= check_if_this_fits_image_is_north_up_east_left( fits_image_name );
 }

 // fprintf(stderr,"DEBUG-3\n");

 if ( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
  // load markers only if the image was recently processed
  if ( 1 == return_one_if_the_input_image_is_among_the_recently_processed_onses_listed_in_vast_image_details_log( fits_image_name ) ) {
   // Allocate memory for the array of known variables markers
   markX_known_variable= (float *)malloc( MAX_NUMBER_OF_STARS * sizeof( float ) );
   if ( markX_known_variable == NULL ) {
    fprintf( stderr, "ERROR: Couldn't allocate memory for markX_known_variable\n" );
    exit( EXIT_FAILURE );
   };
   markY_known_variable= (float *)malloc( MAX_NUMBER_OF_STARS * sizeof( float ) );
   if ( markY_known_variable == NULL ) {
    fprintf( stderr, "ERROR: Couldn't allocate memory for markY_known_variable\n" );
    exit( EXIT_FAILURE );
   };
   mark_known_variable_counter= 0; // initialize
   // load known variables
   load_markers_for_known_variables( markX_known_variable, markY_known_variable, &mark_known_variable_counter, fits_image_name );
   //
   if ( mark_known_variable_counter == 0 ) {
    // Free memory for the array of known variables markers, as non known variables were loaded
    free( markX_known_variable );
    free( markY_known_variable );
   }
   fprintf( stderr, "Loaded %d known variables.\n", mark_known_variable_counter );

   // Allocate memory for the array of autocandidate variables markers
   markX_autocandidate_variable= (float *)malloc( MAX_NUMBER_OF_STARS * sizeof( float ) );
   if ( markX_autocandidate_variable == NULL ) {
    fprintf( stderr, "ERROR: Couldn't allocate memory for markX_autocandidate_variable\n" );
    exit( EXIT_FAILURE );
   };
   markY_autocandidate_variable= (float *)malloc( MAX_NUMBER_OF_STARS * sizeof( float ) );
   if ( markY_autocandidate_variable == NULL ) {
    fprintf( stderr, "ERROR: Couldn't allocate memory for markY_autocandidate_variable\n" );
    exit( EXIT_FAILURE );
   };
   mark_autocandidate_variable_counter= 0; // initialize
   // load autocandidate variables
   load_markers_for_autocandidate_variables( markX_autocandidate_variable, markY_autocandidate_variable, &mark_autocandidate_variable_counter, fits_image_name );
   //
   if ( mark_autocandidate_variable_counter == 0 ) {
    // Free memory for the array of autocandidate variables markers, as non autocandidate variables were loaded
    free( markX_autocandidate_variable );
    free( markY_autocandidate_variable );
   }
   fprintf( stderr, "Loaded %d candidate variables.\n", mark_autocandidate_variable_counter );
  }
 }

 // fprintf(stderr,"DEBUG-3a\n");

 if ( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
  // Check if the SExtractor executable (named "sex") is present in $PATH
  // Update PATH variable to make sure the local copy of SExtractor is there
  char pathstring[8192];
  strncpy( pathstring, getenv( "PATH" ), 8192 - 1 - 8 );
  pathstring[8192 - 1 - 8]= '\0';
  strncat( pathstring, ":lib/bin", 9 );
  pathstring[8192 - 1]= '\0';
  setenv( "PATH", pathstring, 1 );
  if ( 0 != system( "lib/look_for_sextractor.sh" ) ) {
   fprintf( stderr, "ERROR running  lib/look_for_sextractor.sh\n" );
  }
  // fprintf(stderr," *** Running SExtractor on %s ***\n",fits_image_name);
  //  Star match mode (create WCS) or Single image reduction mode
  fprintf( stderr, "%s is starting autodetect_aperture(%s, %s, 0, 0, %.2lf, %lf, %lf, 2);\n", argv[0], fits_image_name, sextractor_catalog_filename, fixed_aperture, dimX, dimY );
  APER= autodetect_aperture( fits_image_name, sextractor_catalog_filename, 0, 0, fixed_aperture, dimX, dimY, 2 );
  if ( fixed_aperture != 0.0 ) {
   APER= fixed_aperture;
  }

  // fprintf(stderr,"DEBUG-1\n");

  sextractor_catalog__X_viewed= (float *)malloc( MAX_NUMBER_OF_STARS * sizeof( float ) );
  if ( sextractor_catalog__X_viewed == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__X_viewed\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__Y_viewed= (float *)malloc( MAX_NUMBER_OF_STARS * sizeof( float ) );
  if ( sextractor_catalog__Y_viewed == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__Y_viewed\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__viewed_counter= 0; // initialize

  sextractor_catalog__X= (float *)malloc( MAX_NUMBER_OF_STARS * sizeof( float ) );
  if ( sextractor_catalog__X == NULL ) {
   fprintf( stderr, "ERROR0: Couldn't allocate memory for sextractor_catalog__X\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__Y= (float *)malloc( MAX_NUMBER_OF_STARS * sizeof( float ) );
  if ( sextractor_catalog__Y == NULL ) {
   fprintf( stderr, "ERROR0: Couldn't allocate memory for sextractor_catalog__Y\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__FLUX= (double *)malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( sextractor_catalog__FLUX == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__FLUX\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__FLUX_ERR= (double *)malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( sextractor_catalog__FLUX_ERR == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__FLUX_ERR\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__MAG= (double *)malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( sextractor_catalog__MAG == NULL ) {
   fprintf( stderr, "ERROR0: Couldn't allocate memory for sextractor_catalog__MAG\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__MAG_ERR= (double *)malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( sextractor_catalog__MAG_ERR == NULL ) {
   fprintf( stderr, "ERROR0: Couldn't allocate memory for sextractor_catalog__FLUX\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__star_number= (int *)malloc( MAX_NUMBER_OF_STARS * sizeof( int ) );
  if ( sextractor_catalog__star_number == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__star_number\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__se_FLAG= (int *)malloc( MAX_NUMBER_OF_STARS * sizeof( int ) );
  if ( sextractor_catalog__se_FLAG == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__se_FLAG\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__ext_FLAG= (int *)malloc( MAX_NUMBER_OF_STARS * sizeof( int ) );
  if ( sextractor_catalog__ext_FLAG == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__ext_FLAG\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__psfCHI2= (double *)malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( sextractor_catalog__psfCHI2 == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__psfCHI2\n" );
   exit( EXIT_FAILURE );
  };

  sextractor_catalog__A_IMAGE= (double *)malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( sextractor_catalog__A_IMAGE == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sexA_image\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__ERRA_IMAGE= (double *)malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( sextractor_catalog__ERRA_IMAGE == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__ERRA_IMAGE\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__B_IMAGE= (double *)malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( sextractor_catalog__B_IMAGE == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__B_IMAGE\n" );
   exit( EXIT_FAILURE );
  };
  sextractor_catalog__ERRB_IMAGE= (double *)malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( sextractor_catalog__ERRB_IMAGE == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for sextractor_catalog__ERRB_IMAGE\n" );
   exit( EXIT_FAILURE );
  };

  //
  memset( sextractor_catalog__X_viewed, 0, MAX_NUMBER_OF_STARS * sizeof( float ) );
  memset( sextractor_catalog__Y_viewed, 0, MAX_NUMBER_OF_STARS * sizeof( float ) );
  memset( sextractor_catalog__X, 0, MAX_NUMBER_OF_STARS * sizeof( float ) );
  memset( sextractor_catalog__Y, 0, MAX_NUMBER_OF_STARS * sizeof( float ) );
  memset( sextractor_catalog__FLUX, 0, MAX_NUMBER_OF_STARS * sizeof( double ) );
  memset( sextractor_catalog__FLUX_ERR, 0, MAX_NUMBER_OF_STARS * sizeof( double ) );
  memset( sextractor_catalog__MAG, 0, MAX_NUMBER_OF_STARS * sizeof( double ) );
  memset( sextractor_catalog__MAG_ERR, 0, MAX_NUMBER_OF_STARS * sizeof( double ) );
  memset( sextractor_catalog__star_number, 0, MAX_NUMBER_OF_STARS * sizeof( int ) );
  memset( sextractor_catalog__se_FLAG, 0, MAX_NUMBER_OF_STARS * sizeof( int ) );
  memset( sextractor_catalog__ext_FLAG, 0, MAX_NUMBER_OF_STARS * sizeof( int ) );
  memset( sextractor_catalog__psfCHI2, 0, MAX_NUMBER_OF_STARS * sizeof( double ) );
  memset( sextractor_catalog__A_IMAGE, 0, MAX_NUMBER_OF_STARS * sizeof( double ) );
  memset( sextractor_catalog__ERRA_IMAGE, 0, MAX_NUMBER_OF_STARS * sizeof( double ) );
  memset( sextractor_catalog__ERRA_IMAGE, 0, MAX_NUMBER_OF_STARS * sizeof( double ) );
  memset( sextractor_catalog__B_IMAGE, 0, MAX_NUMBER_OF_STARS * sizeof( double ) );
  memset( sextractor_catalog__ERRB_IMAGE, 0, MAX_NUMBER_OF_STARS * sizeof( double ) );
  //

  catfile= fopen( sextractor_catalog_filename, "r" );
  if ( NULL == catfile ) {
   fprintf( stderr, "ERROR! Cannot open sextractor catalog file %s for reading!\n", sextractor_catalog_filename );
   exit( EXIT_FAILURE );
  }
  // while( -1<fscanf(catfile, "%d %lf %lf %lf %lf %f %f %lf %lf %lf %lf %d\n", &sextractor_catalog__star_number[sextractor_catalog__counter], &sextractor_catalog__FLUX[sextractor_catalog__counter], &sextractor_catalog__FLUX_ERR[sextractor_catalog__counter], &sextractor_catalog__MAG[sextractor_catalog__counter], &sextractor_catalog__MAG_ERR[sextractor_catalog__counter], &sextractor_catalog__X[sextractor_catalog__counter], &sextractor_catalog__Y[sextractor_catalog__counter], &sextractor_catalog__A_IMAGE[sextractor_catalog__counter], &sextractor_catalog__ERRA_IMAGE[sextractor_catalog__counter], &sextractor_catalog__B_IMAGE[sextractor_catalog__counter], &sextractor_catalog__ERRB_IMAGE[sextractor_catalog__counter], &sextractor_catalog__se_FLAG[sextractor_catalog__counter]) ){
  // fprintf(stderr,"DEBUG01\n");
  while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, catfile ) ) {
   // fprintf(stderr,"DEBUG02 sextractor_catalog__counter=%d\n",sextractor_catalog__counter);
   sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT - 1]= '\0'; // just in case
   external_flag= 0;
   // external_flag_string[0]='\0';
   if ( 0 != parse_sextractor_catalog_string( sextractor_catalog_string, &sextractor_catalog__star_number[sextractor_catalog__counter], &sextractor_catalog__FLUX[sextractor_catalog__counter], &sextractor_catalog__FLUX_ERR[sextractor_catalog__counter], &sextractor_catalog__MAG[sextractor_catalog__counter], &sextractor_catalog__MAG_ERR[sextractor_catalog__counter], &position_x_pix, &position_y_pix, &sextractor_catalog__A_IMAGE[sextractor_catalog__counter], &sextractor_catalog__ERRA_IMAGE[sextractor_catalog__counter], &sextractor_catalog__B_IMAGE[sextractor_catalog__counter], &sextractor_catalog__ERRB_IMAGE[sextractor_catalog__counter], &sextractor_catalog__se_FLAG[sextractor_catalog__counter], &external_flag, &psf_chi2, NULL ) ) {
    fprintf( stderr, "WARNING: problem occurred while parsing SExtractor catalog %s  (1)\nThe offending line is:\n%s\n", sextractor_catalog_filename, sextractor_catalog_string );
    continue;
   }
   ////////////////////
   // Read only stars detected at the first FITS image extension.
   // The start of the second image extension will be signified by a jump in star numbering
   if ( sextractor_catalog__counter > 0 ) {
    if ( sextractor_catalog__star_number[sextractor_catalog__counter] < sextractor_catalog__star_number[sextractor_catalog__counter - 1] ) {
     fprintf( stderr, "WARNING: it seems SExtractor catalog contains detection at multiple FITS extensions. Only the first extension detections are displayed!\n" );
     break;
    }
   }
   ////////////////////
   // Do not display saturated stars in the magnitude calibration mode
   if ( match_mode == 0 ) {
    if ( sextractor_catalog__se_FLAG[sextractor_catalog__counter] >= 4 ) {
     continue;
    }
   }
   //
   sextractor_catalog__X[sextractor_catalog__counter]= position_x_pix;
   sextractor_catalog__Y[sextractor_catalog__counter]= position_y_pix;
   sextractor_catalog__ext_FLAG[sextractor_catalog__counter]= external_flag;
   sextractor_catalog__psfCHI2[sextractor_catalog__counter]= psf_chi2;
   sextractor_catalog__counter++;
  }
  fclose( catfile );

  // if we use ds9 to display an image
  if ( use_ds9 == 1 ) {
   // prepare the ds9 region file
   sprintf( ds9_region_filename, "ds9_%d_tmp.reg", pid );
   catfile= fopen( ds9_region_filename, "w" );
   fprintf( catfile, "# Region file format: DS9 version 4.0\n# Filename: %s\nglobal color=green font=\"sans 8 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source\nimage\n", fits_image_name );
   for ( ; sextractor_catalog__counter--; )
    fprintf( catfile, "circle(%.3lf,%.3lf,%.1lf)\n# text(%.3lf,%.3lf) text={%d}\n", sextractor_catalog__X[sextractor_catalog__counter], sextractor_catalog__Y[sextractor_catalog__counter], APER / 2.0, sextractor_catalog__X[sextractor_catalog__counter], sextractor_catalog__Y[sextractor_catalog__counter] - APER, sextractor_catalog__star_number[sextractor_catalog__counter] );
   fclose( catfile );

   // execute the system command to run ds9
   fprintf( stderr, "Starting DS9 FITS image viewer...\n" );
   sprintf( stderr_output, "ds9 %s -region %s -xpa no ; rm -f %s\n", fits_image_name, ds9_region_filename, ds9_region_filename );
   fprintf( stderr, "%s", stderr_output );
   if ( 0 != system( stderr_output ) ) {
    fprintf( stderr, "ERROR runnning  %s\n", stderr_output );
   }

   // free the arrays
   free( sextractor_catalog__X );
   free( sextractor_catalog__Y );
   free( sextractor_catalog__FLUX );
   free( sextractor_catalog__FLUX_ERR );
   free( sextractor_catalog__MAG );
   free( sextractor_catalog__MAG_ERR );
   free( sextractor_catalog__star_number );
   free( sextractor_catalog__se_FLAG );
   free( sextractor_catalog__A_IMAGE );
   free( sextractor_catalog__ERRA_IMAGE );
   free( sextractor_catalog__B_IMAGE );
   free( sextractor_catalog__ERRB_IMAGE );
   // exit
   return 0;
  }
 }

 // fprintf(stderr,"DEBUG-3b\n");

 // Check if we are asked to start ds9 instead of the normal PGPLOT interface
 if ( use_ds9 == 1 ) {
  // execute the system command to run ds9
  fprintf( stderr, "Starting DS9 FITS image viewer...\n" );
  sprintf( stderr_output, "ds9 %s \n", fits_image_name );
  fprintf( stderr, "%s", stderr_output );
  if ( 0 != system( stderr_output ) ) {
   fprintf( stderr, "ERROR running  %s\n", stderr_output );
  }
  return 0;
 }

 // fprintf(stderr,"DEBUG-3c\n");

 if ( 0 != fitsfile_read_check( fits_image_name ) ) {
  return 1;
 }
 // fprintf(stderr,"DEBUG-3d\n");
 // fits_open_file(&fptr, fits_image_name, 0 , &status);
 fits_open_image( &fptr, fits_image_name, 0, &status );
 if ( status != 0 ) {
  fprintf( stderr, "ERROR opening %s\n", fits_image_name );
  return 1;
 }
 fits_get_img_type( fptr, &bitpix, &status );
 fits_read_key( fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status );
 fits_read_key( fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status );
 fprintf( stderr, "Image %s: %ldx%ld pixels, BITPIX data type code: %d\n", fits_image_name, naxes[0], naxes[1], bitpix );
 if ( naxes[0] * naxes[1] <= 0 ) {
  fprintf( stderr, "ERROR: Trying allocate zero or negative sized array\n" );
  exit( EXIT_FAILURE );
 };
 float_array= malloc( naxes[0] * naxes[1] * sizeof( float ) );
 if ( float_array == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for float_array\n" );
  exit( EXIT_FAILURE );
 };
 real_float_array= malloc( naxes[0] * naxes[1] * sizeof( float ) );
 if ( real_float_array == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for real_float_array\n" );
  exit( EXIT_FAILURE );
 };

 // 8 bit image
 if ( bitpix == 8 ) {
  image_array_uchar= (unsigned char *)malloc( naxes[0] * naxes[1] * sizeof( unsigned char ) );
  if ( image_array_uchar == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for image_array_uchar\n" );
   exit( EXIT_FAILURE );
  };
  fits_read_img( fptr, TBYTE, 1, naxes[0] * naxes[1], &nullval_uchar, image_array_uchar, &anynul, &status );
  for ( i= 0; i < naxes[0] * naxes[1]; i++ ) {
   float_array[i]= (float)image_array_uchar[i];
  }
  free( image_array_uchar );
 }
 // 16 bit image
 if ( bitpix == 16 ) {
  image_array_ushort= (unsigned short *)malloc( naxes[0] * naxes[1] * sizeof( short ) );
  if ( image_array_ushort == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for image_array_ushort\n" );
   exit( EXIT_FAILURE );
  };
  // fprintf(stderr,"Trying to read the image as TUSHORT\n");
  fits_read_img( fptr, TUSHORT, 1, naxes[0] * naxes[1], &nullval_ushort, image_array_ushort, &anynul, &status );
  // fits_read_img(fptr, TSHORT, 1, naxes[0]*naxes[1],&nullval,image_array_ushort, &anynul, &status);
  if ( status == 412 ) {
   // is this actually a signed-integer image?
   // fprintf(stderr,"Trying to read the image as TSHORT\n");
   status= 0;
   // fits_read_img(fptr, TSHORT, 1, naxes[0]*naxes[1],&nullval,image_array_ushort, &anynul, &status);
   fits_read_img( fptr, TUSHORT, 1, naxes[0] * naxes[1], &nullval_ushort, image_array_ushort, &anynul, &status );
   // ??
  }
  if ( status == 412 ) {
   // is this actually a float-image with a wrong header?
   fits_report_error( stderr, status ); /* print out any error messages */
   fprintf( stderr, "Image read problem! Is it actually a Kourovka SBG cameraimage? Let's try...\n" );
   if ( 0 == Kourovka_SBG_date_hack( fits_image_name, stderr_output, &N, &median_class_star ) ) {
    fprintf( stderr, "Yes, it is! Will have to re-open the image...\n" );
    status= 0;
    bitpix= 16;
    fits_close_file( fptr, &status );
    // fits_open_file(&fptr, fits_image_name, 0 , &status);
    fits_open_image( &fptr, fits_image_name, 0, &status );
    fits_get_img_type( fptr, &bitpix, &status );
   } else {
    fprintf( stderr, "Image read problem! Is it actually a float-type image? Let's try...\n" );
    status= 0;
    bitpix= -32;
   }
  }
  if ( status == 0 && bitpix != -32 ) {
   for ( i= 0; i < naxes[0] * naxes[1]; i++ )
    float_array[i]= (float)image_array_ushort[i];
  }
  free( image_array_ushort );
 }
 // 32 bit image
 if ( bitpix == 32 ) {
  image_array_uint= (unsigned int *)malloc( naxes[0] * naxes[1] * sizeof( int ) );
  if ( image_array_uint == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for image_array_uint\n" );
   exit( EXIT_FAILURE );
  };
  fits_read_img( fptr, TUINT, 1, naxes[0] * naxes[1], &nullval_uint, image_array_uint, &anynul, &status );
  if ( status == 412 ) {
   // Ignore the data type overflow error
   status= 0;
  }
  fits_report_error( stderr, status ); // print out any error messages
  for ( i= 0; i < naxes[0] * naxes[1]; i++ )
   float_array[i]= (float)image_array_uint[i];
  free( image_array_uint );
 }
 // double image
 if ( bitpix == -64 ) {
  image_array_double= (double *)malloc( naxes[0] * naxes[1] * sizeof( double ) );
  if ( image_array_double == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for image_array_double\n" );
   exit( EXIT_FAILURE );
  };
  fits_read_img( fptr, TDOUBLE, 1, naxes[0] * naxes[1], &nullval_double, image_array_double, &anynul, &status );
  for ( i= 0; i < naxes[0] * naxes[1]; i++ )
   float_array[i]= (float)image_array_double[i];
  free( image_array_double );
 }
 // float image
 if ( bitpix == -32 ) {
  fits_read_img( fptr, TFLOAT, 1, naxes[0] * naxes[1], &nullval, float_array, &anynul, &status );
 }
 fits_close_file( fptr, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 if ( status != 0 ) {
  exit( status );
 }
 // fprintf(stderr,"OK\n");

 // fprintf(stderr,"DEBUG-3e\n");

 // Don't do this check if this is fits2png
 if ( finder_chart_mode != 1 && use_labels != 0 ) {
  // Decide if we want to use xy2sky()
  xy2sky_return_value= xy2sky( fits_image_name, (float)naxes[0] / 2.0, (float)naxes[1] / 2.0 );
  if ( xy2sky_return_value == 0 ) {
   fprintf( stderr, "The image center coordinates are printed above.\n" );
   use_xy2sky= 1;
  } else {
   use_xy2sky= 0;
  }
  //
 } else {
  use_xy2sky= 0;
 }

 axis_ratio= (float)naxes[0] / (float)naxes[1];
 // fprintf(stderr,"DEBUG-3f axis_ratio=%f\n",axis_ratio);

 // filter out bad pixels from float_array
 for ( i= 0; i < naxes[0] * naxes[1]; i++ ) {
  if ( float_array[i] < MIN_PIX_VALUE || float_array[i] > MAX_PIX_VALUE )
   float_array[i]= 0.0;
 }

 // real_float_array - array with real pixel values (well, not real but converted to float)
 // float_array - array used for computations with values ranging from 0 to 65535
 for ( i= 0; i < naxes[0] * naxes[1]; i++ ) {
  real_float_array[i]= float_array[i];
 }
 fix_array_with_negative_values( naxes[0] * naxes[1], float_array );
 image_minmax2( naxes[0] * naxes[1], float_array, &max_val, &min_val );

 /* GUI */
 // fprintf(stderr,"Opening display ... ");

 // fprintf(stderr,"DEBUG-3g\n");

 // setenv("PGPLOT_DIR","lib/pgplot/",1);
 setenv_localpgplot( argv[0] );
 if ( finder_chart_mode == 1 ) {

  //
  inverted_Y_axis= 0; // do not invert Y axis for finding charts!
  //

  if ( cpgbeg( 0, "/PNG", 1, 1 ) != 1 ) {
   // fallback to PS
   if ( cpgbeg( 0, "/PS", 1, 1 ) != 1 ) {
    return EXIT_FAILURE;
   }
  }
 } else {
  if ( cpgbeg( 0, "/XW", 1, 1 ) != 1 ) {
   return EXIT_FAILURE;
  }
 }
 cpgask( 0 ); // turn OFF this silly " Type <RETURN> for next page:" request

 // cpgpap( 0.0, 1.0); /* Make square plot */

 // if( finder_chart_mode==0 ){
 cpgscr( 0, 0.10, 0.31, 0.32 ); /* set default vast window background */
 cpgpage();
 //}
 // (finder_chart_mode == 1 && use_north_east_marks == 0 && use_labels == 0)
 // should correspond to fits2png settings
 // if( finder_chart_mode == 0 || (finder_chart_mode == 1 && use_north_east_marks == 0 && use_labels == 0) ) {
 if ( finder_chart_mode == 0 || fits2png_fullframe == 1 ) {
  // fprintf(stderr,"DEBUG-3h\n");
  cpgpap( 0.0, 1.0 / axis_ratio );
  // cpgpap( 0.0, (float)naxes[1] / (float)( naxes[0] ) );
  cpgsvp( 0.05, 0.95, 0.035, 0.035 + 0.9 );
 } else {
  // fprintf(stderr,"DEBUG-3hh\n");
  cpgpap( 0.0, 1.0 ); /* Make square plot */
                      /*
    if( use_labels == 1 ) {
     fprintf(stderr,"DEBUG-3hhh\n");
     // leave some space for labels
     cpgsvp( 0.05, 0.95, 0.05, 0.95 );
    } else {
     fprintf(stderr,"DEBUG-3hhhh\n");
     // Use the full plot area leaving no space for labels
     cpgsvp( 0.0, 1.0, 0.0, 1.0 );
    }
  */
 }

 if ( use_labels == 1 ) {
  // fprintf(stderr,"DEBUG-3hhh\n");
  //  leave some space for labels
  cpgsvp( 0.05, 0.95, 0.05, 0.95 );
 } else {
  // fprintf(stderr,"DEBUG-3hhhh\n");
  //  Use the full plot area leaving no space for labels
  cpgsvp( 0.0, 1.0, 0.0, 1.0 );
 }

 // set default plotting limits
 drawX1= 1;
 drawY1= 1;
 drawX2= (int)naxes[0];
 drawY2= (int)naxes[1];

 // Check marker position
 if ( markX < 0.0 || markX > (float)naxes[0] || markY < 0.0 || markY > (float)naxes[1] ) {
  fprintf( stderr, "WARNING: marker position %lf %lf is outside the image border\n", markX, markY );
  markX= 0.0;
  markY= 0.0;
 }

 // start with a zoom if a marker position is specified
 if ( markX != 0.0 && markY != 0.0 && finder_chart_mode == 0 ) {
  drawX1= markX - MIN( 100.0, markX );
  drawY1= markY - MIN( 100.0, markY );
  drawX2= drawX1 + MIN( 200.0, (float)naxes[0] );
  drawY2= drawY1 + MIN( 200.0, (float)naxes[1] );
  // fprintf(stderr,"DEBUG01: drawX1=%d drawX2=%d drawY1=%d drawY2=%d  markX=%f markY=%f \n",drawX1,drawX2,drawY1,drawY2,markX,markY);
  ///////
  drawX0= (int)( ( drawX1 + drawX2 ) / 2 + 0.5 );
  drawY0= (int)( ( drawY1 + drawY2 ) / 2 + 0.5 );
  razmer_y= myimax( drawX2 - drawX1, drawY2 - drawY1 );
  //
  razmer_y= MAX( razmer_y, 3 ); // do not allow zoom smaller than 3 pix
  //
  razmer_x= axis_ratio * razmer_y;
  drawX1= drawX0 - (int)( razmer_x / 2 + 0.5 );
  drawY1= drawY0 - (int)( razmer_y / 2 + 0.5 );
  drawX2= drawX1 + (int)razmer_x;
  drawY2= drawY1 + (int)razmer_y;
  // fprintf(stderr,"DEBUG02: drawX1=%d drawX2=%d drawY1=%d drawY2=%d\n",drawX1,drawX2,drawY1,drawY2);
  if ( drawX2 > naxes[0] ) {
   drawX1-= drawX2 - naxes[0];
   drawX2= naxes[0];
  }
  if ( drawY2 > naxes[1] ) {
   drawY1-= drawY2 - naxes[1];
   drawY2= naxes[1];
  }
  if ( drawX1 < 1 ) {
   drawX2+= 1 - drawX1;
   drawX1= 1;
  }
  if ( drawY1 < 1 ) {
   drawY2+= 1 - drawY1;
   drawY1= 1;
  }
  if ( drawX2 > naxes[0] )
   drawX2= naxes[0];
  if ( drawY2 > naxes[1] )
   drawY2= naxes[1];
  // fprintf(stderr,"DEBUG03: drawX1=%d drawX2=%d drawY1=%d drawY2=%d\n",drawX1,drawX2,drawY1,drawY2);
  ///////
  fprintf( stderr, "\n Press 'D' or 'Z''Z' to view the full image.\n\n" );
 }

 if ( finder_chart_mode == 0 ) {
  // Print user instructions here!!!
  print_pgfv_help();
  if ( match_mode == 2 ) {
   fprintf( stderr, "Click on a comparison star and enter its magnitude in the terminal window.\nRight-click after entering all the comparison stars.\n" );
  }
  if ( match_mode == 4 ) {
   fprintf( stderr, "\E[01;35mSelect one or multiple comparison stars\E[33;00m with know magnitudes.\nClick on the star then enter its magnitude in the terminal.\nYou may mark the variable star by clicking on it and typing 'v' instead of the magnitude.\nUse +/- keys on the keyboard to increase/decrease the aperture size\n\n" );
  }
 } // if ( finder_chart_mode == 0 ) {

 if ( finder_chart_mode == 1 ) {
  curX= markX;
  curY= markY;
 } else {
  curX= curY= 0;
 }
 curX2= curY2= 0;
 curC= 'R';
 do {

  // Check if the click is inside the plot
  // (we'll just redraw the plot if it is)
  if ( curC == 'A' || curC == 'a' ) {
   if ( curX < drawX1 || curX > drawX2 || curY < drawY1 || curY > drawY2 ) {
    curC= 'R';
   }
  }

  /// Below is the old check...

  // If we cick inside the image
  if ( curX > 0 && curX < naxes[0] && curY > 0 && curY < naxes[1] ) {

   /* '+' increse aperture */
   if ( curC == '+' || curC == '=' ) {
    APER= APER + 1.0;
    APER= (double)( (int)( APER + 0.5 ) ); // round-off the aperture
    aperture_change= 1;
   }

   /* '-' decrese aperture */
   if ( curC == '-' || curC == '_' ) {
    APER= APER - 1.0;
    APER= (double)( (int)( APER + 0.5 ) ); // round-off the aperture
    aperture_change= 1;
   }

   /* If aperture was changed - repeat measurements with new aperture */
   if ( match_mode == 3 || match_mode == 4 ) {
    if ( aperture_change == 1 ) {
     fprintf( stderr, "%s is re-starting autodetect_aperture(%s, %s, 1, 0, %.2lf, %lf, %lf, 2);\n", argv[0], fits_image_name, sextractor_catalog_filename, fixed_aperture, dimX, dimY );
     autodetect_aperture( fits_image_name, sextractor_catalog_filename, 1, 0, APER, dimX, dimY, 2 );
     sextractor_catalog__counter= 0;
     catfile= fopen( sextractor_catalog_filename, "r" );
     if ( NULL == catfile ) {
      fprintf( stderr, "ERROR! Cannot open sextractor catalog file %s for reading!\n", sextractor_catalog_filename );
      exit( EXIT_FAILURE );
     }
     while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, catfile ) ) {
      sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT - 1]= '\0'; // just in case
      external_flag= 0;
      if ( 0 != parse_sextractor_catalog_string( sextractor_catalog_string, &sextractor_catalog__star_number[sextractor_catalog__counter], &sextractor_catalog__FLUX[sextractor_catalog__counter], &sextractor_catalog__FLUX_ERR[sextractor_catalog__counter], &sextractor_catalog__MAG[sextractor_catalog__counter], &sextractor_catalog__MAG_ERR[sextractor_catalog__counter], &position_x_pix, &position_y_pix, &sextractor_catalog__A_IMAGE[sextractor_catalog__counter], &sextractor_catalog__ERRA_IMAGE[sextractor_catalog__counter], &sextractor_catalog__B_IMAGE[sextractor_catalog__counter], &sextractor_catalog__ERRB_IMAGE[sextractor_catalog__counter], &sextractor_catalog__se_FLAG[sextractor_catalog__counter], &external_flag, &psf_chi2, NULL ) ) {
       fprintf( stderr, "WARNING: problem occurred while parsing SExtractor catalog %s  (2)\nThe offending line is:\n%s\n", sextractor_catalog_filename, sextractor_catalog_string );
       continue;
      }
      ////////////////////
      // Read only stars detected at the first FITS image extension.
      // The start of the second image extension will be signified by a jump in star numbering
      if ( sextractor_catalog__counter > 0 ) {
       if ( sextractor_catalog__star_number[sextractor_catalog__counter] < sextractor_catalog__star_number[sextractor_catalog__counter - 1] ) {
        fprintf( stderr, "WARNING: it seems SExtractor catalog contains detection at multiple FITS extensions. Only the first extension detections are displayed!\n" );
        break;
       }
      }
      ////////////////////
      sextractor_catalog__X[sextractor_catalog__counter]= position_x_pix;
      sextractor_catalog__Y[sextractor_catalog__counter]= position_y_pix;
      sextractor_catalog__ext_FLAG[sextractor_catalog__counter]= external_flag;
      sextractor_catalog__psfCHI2[sextractor_catalog__counter]= psf_chi2;
      sextractor_catalog__counter++;
     }
     fclose( catfile );
     fprintf( stderr, "New aperture %.1lf\n", APER );
     // Save the manually selected aperture for possible future use
     if ( match_mode == 4 ) {
      fprintf( stderr, "Writing the aperture diameter of %.1lf pix to manually_selected_aperture.txt\n", APER );
      matchfile= fopen( "manually_selected_aperture.txt", "w" );
      if ( matchfile == NULL ) {
       fprintf( stderr, "ERROR: failed to open manually_selected_aperture.txt for writing!\nSomething is really messed-up, so I'll die. :(\n" );
       exit( EXIT_FAILURE );
      }
      fprintf( matchfile, "%.1lf\n", APER );
      fclose( matchfile );
     }
     //
     aperture_change= 0;
     curC= 'R'; // Redraw screen
    }           // if ( aperture_change == 1 ) {
   }            // if( match_mode == 3 || match_mode == 4 ) {
   // Switch to magnitude calibration mode
   if ( curC == '2' && match_mode == 3 && magnitude_calibration_already_performed_flag == 0 ) {
    fprintf( stderr, "Entering megnitude calibration mode!\n" );
    fprintf( stderr, "\E[01;31mPlease click on comparison stars and enter their magnitudes...\E[33;00m\n" );
    fprintf( stderr, "\E[01;31mPress '3' when done!\E[33;00m\n" );
    // system("rm -f calib.txt");
    unlink( "calib.txt" );
    match_mode= 2;
   }

   // Switch to AUTOMATIC magnitude calibration mode
   if ( curC == '4' && match_mode == 3 && magnitude_calibration_already_performed_flag == 0 ) {
    fprintf( stderr, "Entering AUTOMATIC megnitude calibration mode!\n" );
    fprintf( stderr, "\E[01;31mPlease enter the filter name (one of BVRIgri):\E[33;00m\n" );
    // The %511s format specifier reads at most 511 characters from stdin into the filter_name_for_automatic_magnitude_calibration_local string, leaving space for a null terminator at the end of the string.
    // Let's limit ourselves to 2 characters
    while ( -1 < fscanf( stdin, "%2s", filter_name_for_automatic_magnitude_calibration_local ) ) {
     filter_name_for_automatic_magnitude_calibration_local[512 - 1]= '\0';
     safely_encode_user_input_string( filter_name_for_automatic_magnitude_calibration, filter_name_for_automatic_magnitude_calibration_local, 512 - 1 );
     // we don't expect the filter name to be long
     if ( strlen( filter_name_for_automatic_magnitude_calibration ) > 2 ) {
      continue;
     }
     // check if we recognize the name
     if ( strncmp( filter_name_for_automatic_magnitude_calibration, "B", 1 ) || strncmp( filter_name_for_automatic_magnitude_calibration, "V", 1 ) || strncmp( filter_name_for_automatic_magnitude_calibration, "r", 1 ) || strncmp( filter_name_for_automatic_magnitude_calibration, "i", 1 ) || strncmp( filter_name_for_automatic_magnitude_calibration, "R", 1 ) || strncmp( filter_name_for_automatic_magnitude_calibration, "Rc", 2 ) || strncmp( filter_name_for_automatic_magnitude_calibration, "I", 1 ) || strncmp( filter_name_for_automatic_magnitude_calibration, "Ic", 2 ) || strncmp( filter_name_for_automatic_magnitude_calibration, "g", 1 ) ) {
      fprintf( stderr, "Trying to perform automatic magnitude calibration for %s filter\n", filter_name_for_automatic_magnitude_calibration );
      break;
     }
     fprintf( stderr, "Unrecognized filter name %s\nPlease enter one of BVriRI: ", filter_name_for_automatic_magnitude_calibration );
    }
    sprintf( system_command, "util/calibrate_single_image.sh %s %s", fits_image_name, filter_name_for_automatic_magnitude_calibration );
    if ( 0 != system( system_command ) ) {
     fprintf( stderr, "ERROR running %s\nYou may try to calibrate the magnitude scale manually by pressing '2' on the keyboard\n", system_command );
    } else {
     // everything worked - go to magnitude calibration
     curC= '3';
     match_mode= 2;
    }
   }

   // Switch to single image inspection mode
   if ( curC == '3' && match_mode == 2 ) {
    if ( magnitude_calibration_already_performed_flag != 0 ) {
     fprintf( stderr, "WARNING: magnitude calibration already performed - will not do it twice!\n" );
    } else {
     magnitude_calibration_using_calib_txt( sextractor_catalog__MAG, sextractor_catalog__counter );
     write_list_of_all_stars_with_calibrated_magnitudes_to_file( sextractor_catalog__X, sextractor_catalog__Y, sextractor_catalog__MAG, sextractor_catalog__MAG_ERR, sextractor_catalog__star_number, sextractor_catalog__se_FLAG, sextractor_catalog__ext_FLAG, sextractor_catalog__counter, sextractor_catalog_filename );
     magnitude_calibration_already_performed_flag= 1;
    }
    fprintf( stderr, "Entering back the single image inspection mode!\n" );
    match_mode= 3;
   }

   /* I - print info (help) */
   if ( curC == 'I' || curC == 'i' ) {
    print_pgfv_help();
   }

   /* M - star markers on/off */
   if ( curC == 'M' || curC == 'm' ) {
    if ( draw_star_markers == 1 )
     draw_star_markers= 0;
    else
     draw_star_markers= 1;
    curC= 'R';
   }

   /* Process left mouse button click */
   if ( curC == 'A' ) {
    fprintf( stderr, "\nPixel: %7.1f %7.1f %9.3f\n", curX, curY, real_float_array[(int)( curX - 0.5 ) + (int)( curY - 0.5 ) * naxes[0]] );
    ///
    if ( use_xy2sky > 0 ) {
     xy2sky_return_value= xy2sky( fits_image_name, curX, curY );
    }
    //

    /* Magnitude calibration mode or Single image mode */
    if ( match_mode == 1 || match_mode == 2 || match_mode == 3 || match_mode == 4 ) {
     for ( marker_counter= 0; marker_counter < sextractor_catalog__counter; marker_counter++ ) {
      if ( ( curX - sextractor_catalog__X[marker_counter] ) * ( curX - sextractor_catalog__X[marker_counter] ) + ( curY - sextractor_catalog__Y[marker_counter] ) * ( curY - sextractor_catalog__Y[marker_counter] ) < (float)( APER * APER / 4.0 ) ) {
       // mark the star
       cpgsci( 2 );
       cpgcirc( sextractor_catalog__X[marker_counter], sextractor_catalog__Y[marker_counter], (float)APER / 2.0 );
       cpgsci( 1 );
       //

       /* Magnitude calibration mode */
       if ( match_mode == 2 || match_mode == 4 ) {
        // mark the star
        // cpgsci( 2 );
        // cpgcirc( sextractor_catalog__X[marker_counter], sextractor_catalog__Y[marker_counter], (float)APER / 2.0 );
        // cpgsci( 1 );
        //
        fprintf( stderr, "Star %d. Instrumental magnitude: %.4lf %.4lf\n(In order to cancel the input - type '99' instead of an actual magnitude.)\n Please, enter its catalog magnitude or 'v' to mark it as the target variable:\nComp. star mag: ", sextractor_catalog__star_number[marker_counter], sextractor_catalog__MAG[marker_counter], sextractor_catalog__MAG_ERR[marker_counter] );
        if ( NULL == fgets( RADEC, 1024, stdin ) ) {
         fprintf( stderr, "Incorrect input!\n" );
        }
        RADEC[1024 - 1]= '\0';
        ; // just in case
        if ( match_mode == 4 ) {
         // Check if we should mark this as a known variable star
         if ( NULL != strstr( RADEC, "v" ) || NULL != strstr( RADEC, "V" ) ) {
          save_star_to_vast_list_of_previously_known_variables_and_exclude_lst( sextractor_catalog__star_number[marker_counter], sextractor_catalog__X[marker_counter], sextractor_catalog__Y[marker_counter] );
          break;
         }
        }
        // Try to filter the input string
        for ( first_number_flag= 0, jj= 0, ii= 0; ii < MIN( 1024, (int)strlen( RADEC ) ); ii++ ) {
         // fprintf(stderr,"%d %c\n",ii,RADEC[ii]);
         if ( RADEC[ii] == '0' ) {
          filtered_string[jj]= '0';
          jj++;
          continue;
         }
         if ( RADEC[ii] == '1' ) {
          filtered_string[jj]= '1';
          jj++;
          first_number_flag= 1;
          continue;
         } // assume if we found '1' this is the magnitude
         if ( RADEC[ii] == '2' ) {
          filtered_string[jj]= '2';
          jj++;
          continue;
         }
         if ( RADEC[ii] == '3' ) {
          filtered_string[jj]= '3';
          jj++;
          continue;
         }
         if ( RADEC[ii] == '4' ) {
          filtered_string[jj]= '4';
          jj++;
          continue;
         }
         if ( RADEC[ii] == '5' ) {
          filtered_string[jj]= '5';
          jj++;
          continue;
         }
         if ( RADEC[ii] == '6' ) {
          filtered_string[jj]= '6';
          jj++;
          continue;
         }
         if ( RADEC[ii] == '7' ) {
          filtered_string[jj]= '7';
          jj++;
          continue;
         }
         if ( RADEC[ii] == '8' ) {
          filtered_string[jj]= '8';
          jj++;
          continue;
         }
         if ( RADEC[ii] == '9' ) {
          filtered_string[jj]= '9';
          jj++;
          continue;
         }
         if ( RADEC[ii] == '.' ) {
          filtered_string[jj]= '.';
          jj++;
          first_number_flag= 1;
          continue;
         } // assume if we found '.' this is the magnitude
         if ( RADEC[ii] == '+' ) {
          filtered_string[jj]= '+';
          jj++;
          continue;
         }
         if ( RADEC[ii] == '-' ) {
          filtered_string[jj]= '-';
          jj++;
          continue;
         }
         if ( RADEC[ii] == ' ' && first_number_flag == 1 ) {
          break;
         } // ignore anything that goes after the first magnitude
        }
        filtered_string[jj]= '\0'; // set the end of line character
        if ( strlen( filtered_string ) < 2 ) {
         fprintf( stderr, "Magnitude string too short. Ignoring input.\nPlease try again with this or another star.\n" );
         break;
        }
        catalog_mag= atof( filtered_string );
        if ( catalog_mag < -1.5 || catalog_mag > 30.0 ) {
         fprintf( stderr, "Magnitude %lf is out of range. Ignoring input.\nPlease try again with this or another star.\n", catalog_mag );
         break;
        }
        if ( match_mode == 4 ) {
         fprintf( stderr, "Adding the star at %.4f %.4f with magnitude %.4lf to manually_selected_comparison_stars.lst\nPick an additional comparison star or right-click to quit.\n", sextractor_catalog__X[marker_counter], sextractor_catalog__Y[marker_counter], catalog_mag );
         matchfile= fopen( "manually_selected_comparison_stars.lst", "a" );
         if ( matchfile == NULL ) {
          fprintf( stderr, "ERROR: failed to open manually_selected_comparison_stars.lst for writing!\nSomething is really messed-up, so I'll die. :(\n" );
          exit( EXIT_FAILURE );
         }
         fprintf( matchfile, "%.4f %.4f %.4lf\n", sextractor_catalog__X[marker_counter], sextractor_catalog__Y[marker_counter], catalog_mag );
         fclose( matchfile );
        } else {
         fprintf( stderr, "Writing a new string to calib.txt:\n%.4lf %.4lf %.4lf\n\n", sextractor_catalog__MAG[marker_counter], catalog_mag, sextractor_catalog__MAG_ERR[marker_counter] );
         matchfile= fopen( "calib.txt", "a" );
         fprintf( matchfile, "%.4lf %.4lf %.4lf\n", sextractor_catalog__MAG[marker_counter], catalog_mag, sextractor_catalog__MAG_ERR[marker_counter] );
         fclose( matchfile );
        }
        match_input++;
        break;
       }

       /* Single image mode */
       if ( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
        fprintf( stderr, "Star %6d\n", sextractor_catalog__star_number[marker_counter] );

        if ( 0 == is_point_close_or_off_the_frame_edge( (double)sextractor_catalog__X[marker_counter], (double)sextractor_catalog__Y[marker_counter], (double)naxes[0], (double)naxes[1], FRAME_EDGE_INDENT_PIXELS ) ) {
         fprintf( stderr, "Star coordinates \E[01;32m%6.1lf %6.1lf\E[33;00m (pix)\n", sextractor_catalog__X[marker_counter], sextractor_catalog__Y[marker_counter] );
        } else {
         fprintf( stderr, "Star coordinates \E[01;31m%6.1lf %6.1lf\E[33;00m (pix)\n", sextractor_catalog__X[marker_counter], sextractor_catalog__Y[marker_counter] );
        }

        if ( 0 == exclude_region( X1, Y1, X2, Y2, N_bad_regions, (double)sextractor_catalog__X[marker_counter], (double)sextractor_catalog__Y[marker_counter], APER ) ) {
         fprintf( stderr, "The star is not situated in a bad CCD region according to bad_region.lst\n" );
        } else {
         fprintf( stderr, "The star is situated in a \E[01;31mbad CCD region\E[33;00m according to bad_region.lst\n" );
        }

        if ( use_xy2sky > 0 ) {
         xy2sky_return_value= xy2sky( fits_image_name, sextractor_catalog__X[marker_counter], sextractor_catalog__Y[marker_counter] );
        }

        if ( sextractor_catalog__FLUX[marker_counter] > MIN_SNR * sextractor_catalog__FLUX_ERR[marker_counter] ) {
         fprintf( stderr, "SNR \E[01;32m%.1lf\E[33;00m\n", sextractor_catalog__FLUX[marker_counter] / sextractor_catalog__FLUX_ERR[marker_counter] );
        } else {
         fprintf( stderr, "SNR \E[01;31m%.1lf\E[33;00m\n", sextractor_catalog__FLUX[marker_counter] / sextractor_catalog__FLUX_ERR[marker_counter] );
        }

        if ( sextractor_catalog__MAG[marker_counter] != 99.0000 ) {
         fprintf( stderr, "Magnitude \E[01;34m%7.4lf  %6.4lf\E[33;00m\n", sextractor_catalog__MAG[marker_counter], sextractor_catalog__MAG_ERR[marker_counter] );
        } else {
         fprintf( stderr, "Magnitude \E[01;31m%7.4lf  %6.4lf\E[33;00m\n", sextractor_catalog__MAG[marker_counter], sextractor_catalog__MAG_ERR[marker_counter] );
        }

        if ( sextractor_catalog__se_FLAG[marker_counter] < 2 ) {
         fprintf( stderr, "SExtractor flag \E[01;32m%d\E[33;00m\n", sextractor_catalog__se_FLAG[marker_counter] );
        } else {
         fprintf( stderr, "SExtractor flag \E[01;31m%d\E[33;00m\n", sextractor_catalog__se_FLAG[marker_counter] );
        }

        if ( sextractor_catalog__ext_FLAG[marker_counter] == 0 ) {
         fprintf( stderr, "External flag \E[01;32m%d\E[33;00m\n", sextractor_catalog__ext_FLAG[marker_counter] );
        } else {
         fprintf( stderr, "External flag \E[01;31m%d\E[33;00m\n", sextractor_catalog__ext_FLAG[marker_counter] );
        }

        // Print anyway
        fprintf( stderr, "Reduced chi2 from PSF-fitting: \E[01;32m%lg\E[33;00m (Objects with large values will be mising from the list of detections! If no PSF fitting was performed, this value is set to 1.0)\n", sextractor_catalog__psfCHI2[marker_counter] );

        bad_size= 0;
        if ( CONST * ( sextractor_catalog__A_IMAGE[marker_counter] + sextractor_catalog__ERRA_IMAGE[marker_counter] ) < MIN_SOURCE_SIZE_APERTURE_FRACTION * APER ) {
         bad_size= 1;
        }
        // That has to match two filtering lines in vast.c
        //if ( sextractor_catalog__A_IMAGE[marker_counter] > APER && sextractor_catalog__se_FLAG[marker_counter] < 4 ) {
        // Allow for large unsaturrated stars: example - VX Sgr with low detection limit, test NMWNSGR20N40410
        if ( sextractor_catalog__A_IMAGE[marker_counter] > 2*APER && sextractor_catalog__se_FLAG[marker_counter] < 4 ) {
         bad_size= 1;
        }
        if ( sextractor_catalog__A_IMAGE[marker_counter] + sextractor_catalog__ERRA_IMAGE[marker_counter] < FWHM_MIN ) {
         bad_size= 1;
        }
        if ( sextractor_catalog__B_IMAGE[marker_counter] + sextractor_catalog__ERRB_IMAGE[marker_counter] < FWHM_MIN ) {
         bad_size= 1;
        }
        
        if ( bad_size == 0 ) {
         fprintf( stderr, "A= \E[01;32m%lf +/- %lf\E[33;00m  B= \E[01;32m%lf +/- %lf\E[33;00m\nFWHM(A)= \E[01;32m%lf +/- %lf\E[33;00m  FWHM(B)= \E[01;32m%lf +/- %lf\E[33;00m\n", sextractor_catalog__A_IMAGE[marker_counter], sextractor_catalog__ERRA_IMAGE[marker_counter], sextractor_catalog__B_IMAGE[marker_counter], sextractor_catalog__ERRB_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sextractor_catalog__A_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sextractor_catalog__ERRA_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sextractor_catalog__B_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sextractor_catalog__ERRB_IMAGE[marker_counter] );
        } else {
         fprintf( stderr, "A= \E[01;31m%lf +/- %lf\E[33;00m  B= \E[01;31m%lf +/- %lf\E[33;00m\nFWHM(A)= \E[01;31m%lf +/- %lf\E[33;00m  FWHM(B)= \E[01;31m%lf +/- %lf\E[33;00m\n", sextractor_catalog__A_IMAGE[marker_counter], sextractor_catalog__ERRA_IMAGE[marker_counter], sextractor_catalog__B_IMAGE[marker_counter], sextractor_catalog__ERRB_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sextractor_catalog__A_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sextractor_catalog__ERRA_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sextractor_catalog__B_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sextractor_catalog__ERRB_IMAGE[marker_counter] );
        }
        // It's nice to ptint the aperture size here for comparison
        fprintf( stderr, "Aperture diameter = %.1lf pixels\n", APER );

        fprintf( stderr, "%s\n", stderr_output );
        fprintf( stderr, "\n" );
       }

       // Star selection from reference image mode
       if ( match_mode == 1 ) {
        // Mark star as viewed
        cpgsci( 2 );
        cpgcirc( sextractor_catalog__X[marker_counter], sextractor_catalog__Y[marker_counter], (float)APER / 2.0 );
        cpgsci( 1 );
        // Save the mark information so it isn't lost when we change zoom
        sextractor_catalog__X_viewed[sextractor_catalog__viewed_counter]= sextractor_catalog__X[marker_counter];
        sextractor_catalog__Y_viewed[sextractor_catalog__viewed_counter]= sextractor_catalog__Y[marker_counter];
        sextractor_catalog__viewed_counter++;
        // Generate the log view command
        fprintf( stderr, "This star in VaST log files:\n" );
        sprintf( system_command, "grep 'out%05d.dat' vast*.log", sextractor_catalog__star_number[marker_counter] );
        if ( 0 != system( system_command ) ) {
         fprintf( stderr, "ERROR running  %s\n", system_command );
        }
        fprintf( stdout, " \n" );
        // Generate the lightcurve viewer command
        sprintf( system_command, "./lc out%05d.dat", sextractor_catalog__star_number[marker_counter] );
        // fork before system() so the parent process is not blocked
        if ( 0 == fork() ) {
         nanosleep( &requested_time, &remaining );
         if ( 0 != system( system_command ) ) {
          fprintf( stderr, "ERROR running  %s\n", system_command );
         }
         exit( 0 );
        } else {
         waitpid( -1, &status, WNOHANG );
        }
       }
      }
     }
    }
   } // if( curC=='A' ){

   if ( finder_chart_mode == 1 ) {
    curC= 'Z';
   }

   /* Zoom in or out */
   if ( curC == 'z' || curC == 'Z' ) {
    if ( finder_chart_mode == 1 ) {
     drawX1= markX - finder_char_pix_around_the_target;
     drawX2= markX + finder_char_pix_around_the_target;
     drawY1= markY - finder_char_pix_around_the_target;
     drawY2= markY + finder_char_pix_around_the_target;
     curC= 'R';
    } else {
     cpgsci( 5 );
     cpgband( 2, 0, curX, curY, &curX2, &curY2, &curC );
     cpgsci( 1 );
    }
    if ( curC == 'Z' || curC == 'z' )
     curC= 'D';
    else {
     if ( finder_chart_mode == 0 ) {
      drawX1= mymin( curX, curX2 );
      drawX2= mymax( curX, curX2 );
      drawY1= mymin( curY, curY2 );
      drawY2= mymax( curY, curY2 );
     }
     drawX0= (int)( ( drawX1 + drawX2 ) / 2 + 0.5 );
     drawY0= (int)( ( drawY1 + drawY2 ) / 2 + 0.5 );
     razmer_y= myimax( drawX2 - drawX1, drawY2 - drawY1 );
     razmer_y= MAX( razmer_y, 3 ); // do not allow zoom smaller than 3 pix
     razmer_y= MIN( razmer_y, naxes[1] );
     // if razmer_y is so big that the whole image is to be displayed again...
     if ( razmer_y == naxes[1] ) {
      razmer_y= (double)MIN( drawX2 - drawX1, naxes[0] ) / (double)naxes[0] * razmer_y;
     }
     // finder_chart_mode=1 use_north_east_marks= 0; use_labels= 0;
     // corresponds to fits2png settings where we presumably whant the whole image
     // if ( finder_chart_mode == 1 && ( use_north_east_marks!= 0 && use_labels!= 0 ) ) {
     // if( finder_chart_mode == 1 && (use_north_east_marks != 0 && use_labels != 0) ) {
     // if( finder_chart_mode == 1 && (use_north_east_marks != 0 || use_labels != 0) ) {
     if ( finder_chart_mode == 1 && fits2png_fullframe == 0 ) {
      // we want a square finding chart !
      razmer_x= razmer_y;
      fprintf( stderr, "Making a square plot\n" );
     } else {
      razmer_x= axis_ratio * razmer_y;
      fprintf( stderr, "Making a plot with the axes ratio of %lf\n", axis_ratio );
     }
     drawX1= drawX0 - (int)( razmer_x / 2 + 0.5 );
     drawY1= drawY0 - (int)( razmer_y / 2 + 0.5 );
     drawX2= drawX1 + (int)razmer_x;
     drawY2= drawY1 + (int)razmer_y;
     if ( drawX2 > naxes[0] ) {
      drawX1-= drawX2 - naxes[0];
      drawX2= naxes[0];
     }
     if ( drawY2 > naxes[1] ) {
      drawY1-= drawY2 - naxes[1];
      drawY2= naxes[1];
     }
     if ( drawX1 < 1 ) {
      drawX2+= 1 - drawX1;
      drawX1= 1;
     }
     if ( drawY1 < 1 ) {
      drawY2+= 1 - drawY1;
      drawY1= 1;
     }
     if ( drawX2 > naxes[0] )
      drawX2= naxes[0];
     if ( drawY2 > naxes[1] )
      drawY2= naxes[1];
     //
     //
     curC= 'R';
    }
   }
  } // If we cick inside the image

  // No matter if the click was inside or outside the image area
  if ( curC == 'H' || curC == 'h' ) {
   if ( hist_trigger == 0 ) {
    hist_trigger= 1;
    float_array2= malloc( naxes[0] * naxes[1] * sizeof( float ) );
    if ( float_array2 == NULL ) {
     fprintf( stderr, "ERROR: Couldn't allocate memory for float_array2\n" );
     exit( EXIT_FAILURE );
    };
    for ( i= 0; i < naxes[0] * naxes[1]; i++ ) {
     float_array2[i]= float_array[i];
    }
    // fprintf(stderr,"histeq... ");
    histeq( naxes[0] * naxes[1], float_array, &max_val, &min_val );
    image_minmax3( naxes[0] * naxes[1], float_array, &max_val, &min_val, drawX1, drawX2, drawY1, drawY2, naxes ); // TEST
    // fprintf(stderr,"OK\n ");
   } else {
    hist_trigger= 0;
    for ( i= 0; i < naxes[0] * naxes[1]; i++ ) {
     float_array[i]= float_array2[i];
    }
    free( float_array2 );
    // image_minmax2( (int)(naxes[0]*naxes[1]), float_array, &max_val, &min_val);
    image_minmax3( naxes[0] * naxes[1], float_array, &max_val, &min_val, drawX1, drawX2, drawY1, drawY2, naxes );
   }
   curC= 'R';
  }
  if ( curC == 'D' || curC == 'd' ) {
   drawX1= 1;
   drawY1= 1;
   drawX2= (int)naxes[0];
   drawY2= (int)naxes[1];
   curC= 'R';
  }
  if ( curC == 'V' || curC == 'v' ) {
   if ( inverted_Y_axis == 0 ) {
    inverted_Y_axis= 1;
   } else {
    inverted_Y_axis= 0;
   }
   curC= 'R';
  }
  if ( curC == 'B' || curC == 'b' ) {
   if ( inverted_X_axis == 0 ) {
    inverted_X_axis= 1;
   } else {
    inverted_X_axis= 0;
   }
   curC= 'R';
  }
  /* F - Fiddle the color table contrast and brightness */
  if ( curC == 'F' || curC == 'f' ) {
   fprintf( stderr, "brightness=%lf  contrast=%lf\n", ( curX - drawX1 ) / ( drawX2 - drawX1 ), 5.0 * curY / abs( drawY2 - drawY1 ) );
   cpgctab( bw_l, bw_r, bw_g, bw_b, 83, 5.0 * curY / abs( drawY2 - drawY1 ), ( curX - drawX1 ) / ( drawX2 - drawX1 ) );
   curC= 'R';
  }

  /* R - Redraw screen */
  if ( curC == 'R' || curC == 'r' ) {

   // fprintf(stderr,"Redrawing image: inverted_X_axis=%d inverted_Y_axis=%d  drawX1=%d drawX2=%d drawY1=%d drawY2=%d\n",inverted_X_axis,inverted_Y_axis,drawX1,drawX2,drawY1,drawY2);

   if ( inverted_Y_axis == 1 ) {
    buf= drawY1;
    drawY1= drawY2;
    drawY2= buf;
   }
   if ( inverted_X_axis == 1 ) {
    buf= drawX1;
    drawX1= drawX2;
    drawX2= buf;
   }

   if ( finder_chart_mode == 0 ) {
    cpgbbuf();
    cpgscr( 0, 0.10, 0.31, 0.32 ); /* set default vast window background */
    cpgeras();
   }
   cpgswin( (float)drawX1, (float)drawX2, (float)drawY1, (float)drawY2 );
   if ( use_labels == 1 ) {
    cpgbox( "BCN1", 0.0, 0, "BCN1", 0.0, 0 );
   }

   if ( drawY1 > drawY2 ) {
    buf= drawY1;
    drawY1= drawY2;
    drawY2= buf;
   }
   if ( drawX1 > drawX2 ) {
    buf= drawX1;
    drawX1= drawX2;
    drawX2= buf;
   }

   // Determine cuts
   image_minmax3( naxes[0] * naxes[1], float_array, &max_val, &min_val, drawX1, drawX2, drawY1, drawY2, naxes );

   /* Draw image */
   if ( finder_chart_mode == 0 ) {
    cpgscr( 0, 0.0, 0.0, 0.0 ); /* set black background */
    cpgimag( float_array, (int)naxes[0], (int)naxes[1], drawX1, drawX2, drawY1, drawY2, min_val, max_val, tr );
   } else {
    // fprintf(stderr,"curC=%c\n",curC);
    cpgscr( 1, 0.0, 0.0, 0.0 );
    cpgscr( 0, 1.0, 1.0, 1.0 );
    cpggray( float_array, (int)naxes[0], (int)naxes[1], drawX1, drawX2, drawY1, drawY2, min_val, max_val, tr );
    cpgscr( 0, 0.0, 0.0, 0.0 );
    cpgscr( 1, 1.0, 1.0, 1.0 );
    //    cpgclos();
    //    return 0;
   }
   /* Make labels with general information: time, filename... */
   if ( use_labels == 1 ) {
    if ( finder_chart_mode == 0 ) {
     cpgscr( 1, 0.62, 0.81, 0.38 ); /* set color of lables */
     cpgsch( 0.9 );                 /* Set small font size */
     // cpgmtxt("T", 0.5, 0.5, 0.5, fits_image_name);
     cpgmtxt( "T", 0.5, 0.5, 0.5, fits_image_name_string_for_display );
     cpgmtxt( "T", 1.5, 0.5, 0.5, stderr_output );
     cpgsch( 1.0 );              /* Set normal font size */
     cpgscr( 1, 1.0, 1.0, 1.0 ); /* */
    } else {
     cpgmtxt( "T", 1.0, 0.5, 0.5, stderr_output );
    }
   }
   /* Done with labels */

   /* Put a mark */
   if ( mark_trigger == 1 && use_labels == 1 ) {
    cpgsci( 2 );
    fprintf( stderr, "Putting marker 001: %f %f\n", markX, markY );
    cpgpt1( markX, markY, 2 );
    cpgsci( 1 );
    ///// New code to enable aperture to be ploted on the finding chart
    if ( APER > 0.0 ) {
     cpgsci( 2 );
     cpgsfs( 2 );
     cpgcirc( markX, markY, (float)APER / 2.0 );
     cpgsci( 1 );
    }
    /////
   } // if ( mark_trigger == 1 ) {

   if ( use_labels == 1 ) {
    // Always put mark in te center of the finding chart
    if ( finder_chart_mode == 1 ) {
     markX= ( (float)naxes[0] / 2.0 );
     markY= ( (float)naxes[1] / 2.0 );
     cpgsci( 2 );
     cpgsch( 3.0 );
     cpgslw( 2 ); // increase line width
     fprintf( stderr, "Putting marker 002: %f %f\n", markX, markY );
     cpgpt1( markX, markY, 2 );
     cpgslw( 1 ); // set default line width
     cpgsch( 1.0 );
     cpgsci( 1 );
    }
   }

   // Markers from manymarkers file
   for ( marker_counter= 0; marker_counter < manymrkerscounter; marker_counter++ ) {
    cpgsci( 5 );
    fprintf( stderr, "Putting marker 003: %f %f\n", manymarkersX[marker_counter], manymarkersY[marker_counter] );
    cpgpt1( manymarkersX[marker_counter], manymarkersY[marker_counter], 2 );
    cpgsci( 1 );
   }

   if ( finder_chart_mode == 1 ) {

    if ( use_north_east_marks == 1 ) {
     // Make N/E labels
     if ( is_this_north_up_east_left_image == 1 ) {
      // cpgsci(2);
      cpgscr( 15, 1.0, 0.973, 0.580 );
      cpgsci( 15 );
      //
      cpgsch( 2.0 ); /* Set small font size */
      cpgslw( 4 );   // increase line width
      // cpgslw(10);   // increase line width
      cpgmtxt( "T", -1.0, 0.5, 0.5, "\\fR N" );
      cpgmtxt( "LV", -0.5, 0.5, 0.5, "\\fR E" );
      //
      if ( 1 == use_datestringinsideimg ) {
       // cpgsch(1.0);
       // cpgmtxt("B", -1.0, 0.5, 0.5, stderr_output);
       sprintf( finder_chart_string_to_print, "\\fR %s", finder_chart_timestring_output );
       cpgmtxt( "B", -1.0, 0.05, 0.0, finder_chart_string_to_print );
       // cpgsch(2.0);
      }
      //
      if ( 1 == use_imagesizestringinsideimg ) {
       if ( 0 == get_string_with_fov_of_wcs_calibrated_image( fits_image_name, fov_string, &fov_float, finder_chart_mode, finder_char_pix_around_the_target ) ) {
        fprintf( stderr, "The image has %s\n", fov_string );
        if ( 1 == use_datestringinsideimg ) {
         // cpgsch(1.0);
         // cpgmtxt("B", -2.2, 0.05, 0.0, fov_string);
         if ( strlen( namelabel ) > 0 ) {
          sprintf( finder_chart_string_to_print, "\\fR %s", namelabel );
          cpgmtxt( "B", -3.4, 0.05, 0.0, finder_chart_string_to_print );
         }
         sprintf( finder_chart_string_to_print, "\\fR %s", fov_string );
         cpgmtxt( "B", -2.2, 0.05, 0.0, finder_chart_string_to_print );
         // cpgsch(2.0);
        } else {
         if ( strlen( namelabel ) > 0 ) {
          sprintf( finder_chart_string_to_print, "\\fR %s", namelabel );
          cpgmtxt( "B", -2.2, 0.05, 0.0, finder_chart_string_to_print );
         }
         // Use large letters
         cpgmtxt( "B", -1.0, 0.05, 0.0, fov_string );
        }
       } // if ( 0 == get_string_with_fov_of_wcs_calibrated_image( fits_image_name, fov_string ) ) {
      }  //  if ( 1 == use_imagesizestringinsideimg ) {
      //
      if ( use_target_mark == 1 ) {
       // cpgsci(2);   // red
       cpgslw( 4 ); // increase line width
       if ( finder_char_pix_around_the_target > 256 ) {
        marker_scaling= (float)finder_char_pix_around_the_target / 512.0;
       } else {
        marker_scaling= 1.0;
       }
       // up
       lineX[0]= markX;
       lineY[0]= markY + 9.0 * marker_scaling;
       lineX[1]= markX;
       lineY[1]= markY + 9.0 * marker_scaling + 15.0 * marker_scaling;
       cpgline( 2, lineX, lineY );
       // right
       lineX[0]= markX + 9.0 * marker_scaling;
       lineY[0]= markY;
       lineX[1]= markX + 9.0 * marker_scaling + 15.0 * marker_scaling;
       lineY[1]= markY;
       cpgline( 2, lineX, lineY );
       //
      }
      //
      cpgslw( 1 );   // set default line width
      cpgsch( 1.0 ); /* Set default font size */
      cpgsci( 1 );
     }
    }

    // exit now
    cpgclos();
    fprintf( stderr, "Writing the output image file pgplot.png (or .ps)\n" );
    free( float_array );
    free( real_float_array );
    return 0;
   }

   // fprintf(stderr,"DEBUG000\n");

   /* If not in simple display mode - draw star markers */
   if ( match_mode > 0 && draw_star_markers == 1 ) {
    cpgsci( 3 );
    cpgsfs( 2 );
    // Draw objects
    for ( marker_counter= 0; marker_counter < sextractor_catalog__counter; marker_counter++ ) {
     cpgcirc( sextractor_catalog__X[marker_counter], sextractor_catalog__Y[marker_counter], (float)APER / 2.0 );
    }
    if ( match_mode == 1 ) {
     cpgsci( 2 );
     for ( marker_counter= 0; marker_counter < sextractor_catalog__viewed_counter; marker_counter++ ) {
      cpgcirc( sextractor_catalog__X_viewed[marker_counter], sextractor_catalog__Y_viewed[marker_counter], (float)APER / 2.0 );
     }
     cpgsci( 1 );
    }
    if ( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
     // mark previously known variables from vast_list_of_previously_known_variables.log
     // cpgsci( 5 ); // good for autocandidates
     cpgsci( 6 );
     cpgslw( 4 ); // increase line width
     for ( marker_counter= 0; marker_counter < mark_known_variable_counter; marker_counter++ ) {
      cpgcirc( markX_known_variable[marker_counter], markY_known_variable[marker_counter], (float)APER / 1.5 );
     }
     cpgslw( 1 ); // set default line width
     cpgsci( 1 );
    }
    if ( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
     // mark previously known variables from vast_autocandidates.log
     cpgsci( 5 ); // good for autocandidates
     cpgslw( 4 ); // increase line width
     for ( marker_counter= 0; marker_counter < mark_autocandidate_variable_counter; marker_counter++ ) {
      cpgcirc( markX_autocandidate_variable[marker_counter], markY_autocandidate_variable[marker_counter], (float)APER / 1.2 );
     }
     cpgslw( 1 ); // set default line width
     cpgsci( 1 );
    }
    /* And draw bad regions */
    if ( 0 != N_bad_regions ) {
     cpgsci( 2 );
     for ( marker_counter= 0; marker_counter < N_bad_regions; marker_counter++ ) {
      cpgline_tmp_x[0]= (float)X1[marker_counter];
      cpgline_tmp_y[0]= (float)Y1[marker_counter];
      cpgline_tmp_x[1]= (float)X1[marker_counter];
      cpgline_tmp_y[1]= (float)Y2[marker_counter];
      cpgline( 2, cpgline_tmp_x, cpgline_tmp_y );

      cpgline_tmp_x[0]= (float)X1[marker_counter];
      cpgline_tmp_y[0]= (float)Y2[marker_counter];
      cpgline_tmp_x[1]= (float)X2[marker_counter];
      cpgline_tmp_y[1]= (float)Y2[marker_counter];
      cpgline( 2, cpgline_tmp_x, cpgline_tmp_y );

      cpgline_tmp_x[0]= (float)X2[marker_counter];
      cpgline_tmp_y[0]= (float)Y2[marker_counter];
      cpgline_tmp_x[1]= (float)X2[marker_counter];
      cpgline_tmp_y[1]= (float)Y1[marker_counter];
      cpgline( 2, cpgline_tmp_x, cpgline_tmp_y );

      cpgline_tmp_x[0]= (float)X2[marker_counter];
      cpgline_tmp_y[0]= (float)Y1[marker_counter];
      cpgline_tmp_x[1]= (float)X1[marker_counter];
      cpgline_tmp_y[1]= (float)Y1[marker_counter];
      cpgline( 2, cpgline_tmp_x, cpgline_tmp_y );
     }
    }
    cpgsci( 1 );
   }
   /* Else - draw single star marker */
   // if( match_mode==0 && APER>0 ){
   if ( APER > 0.0 ) {
    cpgsci( 2 );
    cpgsfs( 2 );
    cpgcirc( markX, markY, (float)APER / 2.0 );
    cpgsci( 1 );
   }

   // fprintf(stderr,"finder_chart_mode=%d\n",finder_chart_mode);
   if ( finder_chart_mode == 0 )
    cpgebuf();
   else {
    fprintf( stderr, "Writing the output image file pgplot.png (or.ps)\n" );
    cpgclos();
    return 0;
   }
  }

  cpgcurs( &curX, &curY, &curC );
 } while ( curC != 'X' && curC != 'x' );

 if ( match_mode > 0 ) {
  free( sextractor_catalog__X );
  free( sextractor_catalog__Y );
  free( sextractor_catalog__MAG );
  free( sextractor_catalog__MAG_ERR );
  free( sextractor_catalog__star_number );
 }

 if ( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
  free( sextractor_catalog__X_viewed );
  free( sextractor_catalog__Y_viewed );
 }

 if ( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
  free( sextractor_catalog__FLUX );
  free( sextractor_catalog__FLUX_ERR );
  free( sextractor_catalog__se_FLAG );
  free( sextractor_catalog__ext_FLAG );
  free( sextractor_catalog__psfCHI2 );
  free( sextractor_catalog__A_IMAGE );
  free( sextractor_catalog__ERRA_IMAGE );
  free( sextractor_catalog__B_IMAGE );
  free( sextractor_catalog__ERRB_IMAGE );
 }

 if ( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
  if ( mark_known_variable_counter > 0 ) {
   // Free memory for the array of known variables markers
   free( markX_known_variable );
   free( markY_known_variable );
  }
  if ( mark_autocandidate_variable_counter > 0 ) {
   // Free memory for the array of autocandidate variables markers
   free( markX_autocandidate_variable );
   free( markY_autocandidate_variable );
  }
 }

 /* Write magnitude calibration file */
 /* Magnitude calibration mode */
 if ( match_mode == 2 && match_input != 0 ) {
  fprintf( stderr, "%d stars were written to calib.txt \n", match_input );
 }

 if ( hist_trigger == 1 ) {
  free( float_array2 );
 }

 free( float_array );
 free( real_float_array );

 cpgclos();

 fprintf( stderr, "%s fits viewer exit code 0 (all fine)\n", argv[0] );

 return 0;
}
