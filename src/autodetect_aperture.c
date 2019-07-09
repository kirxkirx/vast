/*

  This function will conduct SExtractor photometry for a given image.

*/

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include <gsl/gsl_statistics.h>
#include <gsl/gsl_sort.h>

//#include <sys/types.h> // for getpid(i)
#include <sys/stat.h> // for st_mtime (modification time)
#include <unistd.h>    // also for getpid() and unlink() ...

#include "vast_limits.h"
#include "ident.h"
#include "guess_saturation_limit.h"
#include "write_individual_image_log.h"

int find_catalog_in_vast_images_catalogs_log( char *fitsfilename, char *catalogfilename ) {
 char fitsfilename_to_test[FILENAME_LENGTH];
 FILE *f;
 f= fopen( "vast_images_catalogs.log", "r" );
 if ( f == NULL ) {
  strcpy( catalogfilename, "image00000.cat" );
  return 1; // not only this image has not been processed, even "vast_images_catalogs.log" is not created yet!
 }
 int found= 0;
 while ( -1 < fscanf( f, "%s %s", catalogfilename, fitsfilename_to_test ) )
  if ( 0 == strcmp( fitsfilename_to_test, fitsfilename ) ) {
   found= 1;
   break;
  }
 fclose( f );
 if ( found == 0 ) {
  strcpy( catalogfilename, "image00000.cat" );
  return 1; // it is possible that image00000.cat is referring to another image, so we'll recompute...
 }
 /* Check if the catalog already exist */
 f= fopen( catalogfilename, "r" );
 if ( f == NULL )
  return 1;
 else{
  fclose(f);
  /* Check if default.sex was modified after catalog's creation*/
  struct stat defSex;
  struct stat cat;
  stat("default.sex", &defSex);
  stat(catalogfilename, &cat);
  if(defSex.st_mtime > cat.st_mtime){
   fprintf(stderr, "Image will be processed again since default.sex was modified\n");
   return 1;
  };
 }
 return 0;
}

double autodetect_aperture( char *fitsfilename, char *output_sextractor_catalog, int force_recompute, int do_PSF_fitting, double fixed_aperture, double X_im_size, double Y_im_size, int guess_saturation_limit_operation_mode ) {

 FILE *psfex_compatible_sextractor_parameters_file;
 char error_message_string[2048 + 1024 + 4 * FILENAME_LENGTH]; // should be big enough to encomapss command[]

 char command[1024 + 4 * FILENAME_LENGTH];
 double *A;
 int i= 0;
 double median_A;
 double APERTURE;
 int sextractor_flag;

 char aperture_filename[FILENAME_LENGTH]; // this file simply stores the aperture size
 FILE *aperture_file;

 //int number_of_cpu_cores=N_FORK; // default

 int N_bad_regions= 0;
 double *X1;
 double *Y1;
 double *X2;
 double *Y2;

// int pid= getpid();
 char sextractor_catalog_filename[FILENAME_LENGTH];
 char psf_filename[FILENAME_LENGTH];
 
 char sextractor_messages_filename[FILENAME_LENGTH];

 int good_stars_in_the_catalog= 0;
 int all_stars_in_the_catalog= 0;

 double star_x, star_y;

 char saturation_limitsextractor_cl_parameter_string[FILENAME_LENGTH];
 char gain_sextractor_cl_parameter_string[FILENAME_LENGTH];
 char flag_image_sextractor_cl_parameter_string[FILENAME_LENGTH];
 char flag_image_filename[FILENAME_LENGTH];
 char weight_image_filename[FILENAME_LENGTH];
 int is_flag_image_used= 2; // 2 - guess by default, 1 - always use the flag image, 0 - never use the flag image
                            // The decision will also be stored in this variable: 1 - use the flag image, 0 - don't use it
 int external_flag;
 char external_flag_string[256];

 char sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT];

 int raise_unset_gain_warning= 0;

 double ap[8]; // an array that holds multiple apertures

 /* Check if the file has already been processed */
 if ( 0 == find_catalog_in_vast_images_catalogs_log( fitsfilename, output_sextractor_catalog ) ) {
  sprintf( aperture_filename, "%s.aperture", output_sextractor_catalog );
  aperture_file= fopen( aperture_filename, "r" );
  if ( NULL == aperture_file ) {
   fprintf( stderr, "ERROR: cannot open %s\n", aperture_filename );
   return 99.0;
  }
  if ( 1 != fscanf( aperture_file, "%lf\n", &APERTURE ) ) {
   force_recompute= 1;
  }
  if ( APERTURE < 1.0 ) {
   force_recompute= 1;
  }
  fclose( aperture_file );
  if ( 0 == force_recompute ) {
   fprintf( stderr, "Using the catalog %s SExtracted earlier from the image %s\n", output_sextractor_catalog, fitsfilename );
   return APERTURE;
  }
 }
 sprintf( aperture_filename, "%s.aperture", output_sextractor_catalog );

 ////// Here is some memory-hungry stuff //////
 write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): SExtractor catalog name ", output_sextractor_catalog, "" );
 write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): original FITS image filename ", fitsfilename, "" );

 // Check if we need a flag image
 check_if_we_need_flag_image( fitsfilename, flag_image_sextractor_cl_parameter_string, &is_flag_image_used, flag_image_filename, weight_image_filename );

 // Guess saturation limit for the given image
 if ( 0 != guess_saturation_limit( fitsfilename, saturation_limitsextractor_cl_parameter_string, guess_saturation_limit_operation_mode ) ) {
  sprintf( error_message_string, "An ERROR ocurred while trying to guess image saturation limit for %s\n", fitsfilename );
  fputs( error_message_string, stderr );
  write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", error_message_string, "" );
  return 99.0;
 }

 // Guess gain for the given image
 if ( do_PSF_fitting == 1 )
  raise_unset_gain_warning= 1; // always warn about unset gain when doing PSF-fitting photometry
 if ( 0 != guess_gain( fitsfilename, gain_sextractor_cl_parameter_string, 2, raise_unset_gain_warning ) ) {
  sprintf( error_message_string, "An ERROR ocurred while trying to guess CCD gain for %s\n", fitsfilename );
  fputs( error_message_string, stderr );
  write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", error_message_string, "" );
  return 99.0;
 }
 ////// End of the memory-hungry stuff //////

 X1= malloc( MAX_NUMBER_OF_BAD_REGIONS_ON_CCD * sizeof( double ) );
 if ( X1 == NULL ) {
  fprintf( stderr, "ERROR: in autodetect_aperture() can't allocate memory for X1\n" );
  exit( 1 );
 }
 Y1= malloc( MAX_NUMBER_OF_BAD_REGIONS_ON_CCD * sizeof( double ) );
 if ( Y1 == NULL ) {
  fprintf( stderr, "ERROR: in autodetect_aperture() can't allocate memory for Y1\n" );
  exit( 1 );
 }
 X2= malloc( MAX_NUMBER_OF_BAD_REGIONS_ON_CCD * sizeof( double ) );
 if ( X2 == NULL ) {
  fprintf( stderr, "ERROR: in autodetect_aperture() can't allocate memory for X2\n" );
  exit( 1 );
 }
 Y2= malloc( MAX_NUMBER_OF_BAD_REGIONS_ON_CCD * sizeof( double ) );
 if ( Y2 == NULL ) {
  fprintf( stderr, "ERROR: in autodetect_aperture() can't allocate memory for Y2\n" );
  exit( 1 );
 }

 read_bad_lst( X1, Y1, X2, Y2, &N_bad_regions );

 A= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( A == NULL ) {
  fprintf( stderr, "ERROR: out of memory in function autodetect_aperture() A !!!\n" );
  exit( 1 );
 }

 fprintf( stderr, "Running SExtractor on %s\n", fitsfilename );

 sprintf( sextractor_messages_filename, "%s.sex_log", output_sextractor_catalog );

 /* Set fixed aperture size if we whant to use it */
 if ( fixed_aperture != 0.0 ) {
  APERTURE= fixed_aperture;
  write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", "setting the user-specified fixed aperture", "" );
 } else {
  write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", "Calculating the aperture size", "" );
  /* Calculate best aperture size from seeing */
  //sprintf( sextractor_catalog_filename, "autodetect_aper_%d.cat", pid );
  sprintf( sextractor_catalog_filename, "autodetect_aper_%s", output_sextractor_catalog );
  // and yes, we are re-using the .sex_log files
  if ( is_flag_image_used == 1 ) {
   sprintf( command, "sex -c default.sex %s%s%s -PARAMETERS_NAME autodetect_aper_flag.param -CATALOG_NAME %s  %s 2>&1 > %s", gain_sextractor_cl_parameter_string, saturation_limitsextractor_cl_parameter_string, flag_image_sextractor_cl_parameter_string, sextractor_catalog_filename, fitsfilename, sextractor_messages_filename );
  } else {
   sprintf( command, "sex -c default.sex %s%s -PARAMETERS_NAME autodetect_aper.param -CATALOG_NAME %s  %s 2>&1 > %s", gain_sextractor_cl_parameter_string, saturation_limitsextractor_cl_parameter_string, sextractor_catalog_filename, fitsfilename, sextractor_messages_filename );
  }
  //fprintf(stderr, "%s\n", command);
  fputs( command, stderr );
  fputs( "\n", stderr );
  write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): command for the preliminary SExtractor run:\n", command, "" );
  if ( 0 != system( command ) ) {
   //fprintf(stderr,"An ERROR occured while executing the following command:\n%s\n",command);
   sprintf( error_message_string, "An ERROR occured while executing the following command:\n%s\n", command );
   fputs( error_message_string, stderr );
   write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", error_message_string, "" );
   return 99.0;
  }
  FILE *catalog;
  catalog= fopen( sextractor_catalog_filename, "r" );
  if ( catalog == NULL ) {
   sprintf( error_message_string, "ERROR: cannot open SExtractor output catalog file %s\n", sextractor_catalog_filename );
   fputs( error_message_string, stderr );
   write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", error_message_string, "" );
   return 99.0;
  }
  while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, catalog ) ) {
   external_flag_string[0]= '\0'; // reset, just in case
   if ( 4 > sscanf( sextractor_catalog_string, "%lf %d %lf %lf %[^\t\n]", &A[i], &sextractor_flag, &star_x, &star_y, external_flag_string ) )
    continue;
   if ( strlen( external_flag_string ) > 0 ) {
    if ( 1 != sscanf( external_flag_string, "%d", &external_flag ) ) {
     external_flag= 0; // no external flag image used
    }
   } else
    external_flag= 0; // no external flag image used
   all_stars_in_the_catalog++;
   if ( external_flag == 0 && sextractor_flag == 0 && A[i] > FWHM_MIN && 0 == exclude_region( X1, Y1, X2, Y2, N_bad_regions, star_x, star_y, 5.0 ) && star_x > FRAME_EDGE_INDENT_PIXELS && star_y > FRAME_EDGE_INDENT_PIXELS && fabs( star_x - X_im_size ) > FRAME_EDGE_INDENT_PIXELS && fabs( star_y - Y_im_size ) > FRAME_EDGE_INDENT_PIXELS ) {
    i++;
    good_stars_in_the_catalog++;
   }
   if ( i >= MAX_NUMBER_OF_STARS ) {
    fprintf( stderr, "Oops!!! Too many stars!\nChange string \"#define MAX_NUMBER_OF_STARS %d\" in src/vast_limits.h file and recompile the program by running \"make\".\n", MAX_NUMBER_OF_STARS );
    exit( 1 );
   }
  }
  // If most of the stars are flagged out - use flagged stars to choose aperture size
  if ( good_stars_in_the_catalog < 0.5 * all_stars_in_the_catalog ) {
   write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", "too many stars are flagged, so we'll accept flagged stars for seeing determination", "" );
   fseek( catalog, 0, SEEK_SET ); // go back to the beginning of the lightcurve file
   i= 0;                          // reset the counter that we use later
   good_stars_in_the_catalog= 0;
   while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, catalog ) ) {
    external_flag_string[0]= '\0'; // reset, just in case
    if ( 4 > sscanf( sextractor_catalog_string, "%lf %d %lf %lf %[^\t\n]", &A[i], &sextractor_flag, &star_x, &star_y, external_flag_string ) )
     continue;
    if ( strlen( external_flag_string ) > 0 ) {
     if ( 1 != sscanf( external_flag_string, "%d", &external_flag ) ) {
      external_flag= 0; // no external flag image used
     }
    } else {
     external_flag= 0; // no external flag image used
    }

    all_stars_in_the_catalog++;
    if ( external_flag == 0 && A[i] > FWHM_MIN && 0 == exclude_region( X1, Y1, X2, Y2, N_bad_regions, star_x, star_y, 5.0 ) && star_x > FRAME_EDGE_INDENT_PIXELS && star_y > FRAME_EDGE_INDENT_PIXELS && fabs( star_x - X_im_size ) > FRAME_EDGE_INDENT_PIXELS && fabs( star_y - Y_im_size ) > FRAME_EDGE_INDENT_PIXELS ) {
     i++;
     good_stars_in_the_catalog++;
    }
    if ( i >= MAX_NUMBER_OF_STARS ) {
     fprintf( stderr, "Oops!!! Too many stars!\nChange string \"#define MAX_NUMBER_OF_STARS %d\" in src/vast_limits.h file and recompile the program by running \"make\".\n", MAX_NUMBER_OF_STARS );
     exit( 1 );
    }
   }
  } // if( good_stars_in_the_catalog<0.5*all_stars_in_the_catalog ){
  // close the catalog file
  fclose( catalog );

  // remove the SExtractor catalog from the 1st pass with wich we measured sizes of stars, we don't need it anymore
  if ( 0 != unlink( sextractor_catalog_filename ) ){
   fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", sextractor_catalog_filename );
  }

  gsl_sort( A, 1, i );
  median_A= gsl_stats_median_from_sorted_data( A, 1, i );
  APERTURE= median_A * CONST;
 } //if( fixed_aperture!=0.0 )

 // Save aperture information
 aperture_file= fopen( aperture_filename, "w" );
 if ( aperture_file == NULL ) {
  fprintf( stderr, "ERROR: cannot open for writing %s\n", aperture_filename );
  return 99.0;
 }
 fprintf( aperture_file, "%.1lf", APERTURE );
 fclose( aperture_file );

 // Check if the aperture is suspiciously small
 if ( APERTURE < 1.0 ) {
  fprintf( stderr, "\nWARNING: the estimated aperture is unrealistically small: %.1lf<1.0 pix (determined from %d stars).\nThis may happen if all stars are flagged as bad ones by SExtractor.\nCheck SExtractor settings in default.sex, especially that SATUR_LEVEL is not too low.\n\n", APERTURE, i );
  return APERTURE;
 }

 // Set aperture sizes: larger and smaller than the reference aperture
 ap[0]= APERTURE + AP01 * APERTURE;
 ap[1]= APERTURE + AP02 * APERTURE;
 ap[2]= APERTURE + AP03 * APERTURE;
 ap[3]= APERTURE + AP04 * APERTURE;
 // SExtractor catalog will have the following sequence of magnitude measurements
 // best-mag = PSF or reference aperture
 // reference-aperture
 // ap[0]
 // ap[1]
 // ap[2]
 // ap[3]
 

 if ( do_PSF_fitting == 0 ) {
  if ( is_flag_image_used == 1 ) {
   sprintf( command, "sex %s%s%s -PARAMETERS_NAME default_flag.param -PHOT_APERTURES %.1lf,%.1lf,%.1lf,%.1lf,%.1lf,%.1lf -VERBOSE_TYPE NORMAL -CATALOG_NAME %s %s 2>&1 > %s", gain_sextractor_cl_parameter_string, saturation_limitsextractor_cl_parameter_string, flag_image_sextractor_cl_parameter_string, APERTURE, APERTURE, ap[0], ap[1], ap[2], ap[3], output_sextractor_catalog, fitsfilename, sextractor_messages_filename );
  } else {
   sprintf( command, "sex %s%s -PARAMETERS_NAME default.param -PHOT_APERTURES %.1lf,%.1lf,%.1lf,%.1lf,%.1lf,%.1lf -VERBOSE_TYPE NORMAL -CATALOG_NAME %s %s 2>&1 > %s", gain_sextractor_cl_parameter_string, saturation_limitsextractor_cl_parameter_string, APERTURE, APERTURE, ap[0], ap[1], ap[2], ap[3], output_sextractor_catalog, fitsfilename, sextractor_messages_filename );
  }
  fprintf( stderr, "%s\n", command );
  write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): runnning SExtractor in the aperture photometry mode, the processing command is\n", command, "" );
  if ( 0 != system( command ) ) {
   fprintf( stderr, "ERROR: the command returned a non-zero exit code!\n" );
  }
 }
 if ( do_PSF_fitting == 1 ) {

  char psfex_param_filename[512];
  char psfex_XML_check_filename[512];
  char psfex_log_entry_filename[512];

  sprintf( psfex_param_filename, "%s.psfex_param", output_sextractor_catalog );
  sprintf( psfex_XML_check_filename, "%s.psfex_check.xml", output_sextractor_catalog );
  sprintf( psfex_log_entry_filename, "%s.psfex_log", output_sextractor_catalog );
  write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", "writing PSFEx-compatible SExtractor parameters file ", psfex_param_filename );
  psfex_compatible_sextractor_parameters_file= fopen( psfex_param_filename, "w" );
  if ( NULL == psfex_compatible_sextractor_parameters_file ) {
   fprintf( stderr, "ERROR writing %s\n", psfex_param_filename );
   exit( 1 );
  }
  fprintf( psfex_compatible_sextractor_parameters_file, "VIGNET(%.0lf,%.0lf)\nXWIN_IMAGE\nYWIN_IMAGE\nFLUX_RADIUS\nFLUX_MAX\nFLUX_APER(1)\nELONGATION\nFLAGS\nSNR_WIN\n", 2.0 * APERTURE + 0.5, 2.0 * APERTURE + 0.5 );
  fclose( psfex_compatible_sextractor_parameters_file );

  sprintf( sextractor_catalog_filename, "%s.psfex_input_cat", output_sextractor_catalog );
  sprintf( psf_filename, "%s.psf", output_sextractor_catalog );
  sprintf( command, "sex -c bright_star_blend_check_3.0.sex %s%s -PARAMETERS_NAME %s -CATALOG_TYPE FITS_LDAC -CATALOG_NAME %s -PHOT_APERTURES %.1lf,%.1lf,%.1lf,%.1lf,%.1lf %s", gain_sextractor_cl_parameter_string, saturation_limitsextractor_cl_parameter_string, psfex_param_filename, sextractor_catalog_filename, APERTURE, ap[0], ap[1], ap[2], ap[3], fitsfilename );
  fprintf( stderr, "%s\n", command );
  write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", "creating PSFEx-compatible SExtractor catalog with the command\n", command );
  if ( 0 != system( command ) ) {
   fprintf( stderr, "ERROR: the command returned a non-zero exit code!\n" );
  }

  sprintf( command, "psfex -c default.psfex -NTHREADS 1 -SAMPLE_FWHMRANGE %.2lf,%.2lf -XML_NAME %s %s 2>&1 > %s", 0.3 * APERTURE / 2.2528, 1.3 * APERTURE / 2.2528, psfex_XML_check_filename, sextractor_catalog_filename, psfex_log_entry_filename );
  fprintf( stderr, "%s\n", command );
  write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", "extracting PSF with PSFEx using the command\n", command );
  if ( 0 != system( command ) ) {
   fprintf( stderr, "ERROR: the command returned a non-zero exit code!\n" );
  }

  if ( is_flag_image_used == 1 ) {
   sprintf( command, "sex -c default.sex %s%s%s -PARAMETERS_NAME psfex_sextractor_2nd_pass_flag.param -PSF_NMAX 1 -PSF_NAME %s -PHOT_APERTURES %.1lf,%.1lf,%.1lf,%.1lf,%.1lf -VERBOSE_TYPE NORMAL -CATALOG_NAME %s %s 2>&1 > %s", gain_sextractor_cl_parameter_string, saturation_limitsextractor_cl_parameter_string, flag_image_sextractor_cl_parameter_string, psf_filename, APERTURE, ap[0], ap[1], ap[2], ap[3], output_sextractor_catalog, fitsfilename, sextractor_messages_filename );
  } else {
   sprintf( command, "sex -c default.sex %s%s -PARAMETERS_NAME psfex_sextractor_2nd_pass.param -PSF_NMAX 1 -PSF_NAME %s -PHOT_APERTURES %.1lf,%.1lf,%.1lf,%.1lf,%.1lf -VERBOSE_TYPE NORMAL -CATALOG_NAME %s %s 2>&1 > %s", gain_sextractor_cl_parameter_string, saturation_limitsextractor_cl_parameter_string, psf_filename, APERTURE, ap[0], ap[1], ap[2], ap[3], output_sextractor_catalog, fitsfilename, sextractor_messages_filename );
  }
  fprintf( stderr, "%s\n", command );
  write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", "running SExtractor in the PSF-photometry mode with the command\n", command );
  if ( 0 != system( command ) ) {
   fprintf( stderr, "ERROR: the command returned a non-zero exit code!\n" );
  }

  // !!! EXTRA APERTURE PHOTOMETRY RUN !!!
  // The thing is that SExtractor will not PSF-fit saturated stars,
  // but we need to have a catalog containing all the stars (including the brightest ones)
  // in order to be able to perform blind astrometric solution with the Astrometry.net code
  if ( is_flag_image_used == 1 ) {
   sprintf( command, "sex %s%s%s -PARAMETERS_NAME default_flag.param -PHOT_APERTURES %.1lf,%.1lf,%.1lf,%.1lf,%.1lf,%.1lf -CATALOG_NAME %s.apphot %s", gain_sextractor_cl_parameter_string, saturation_limitsextractor_cl_parameter_string, flag_image_sextractor_cl_parameter_string, APERTURE, APERTURE, ap[0], ap[1], ap[2], ap[3], output_sextractor_catalog, fitsfilename );
  } else {
   sprintf( command, "sex %s%s -PARAMETERS_NAME default.param -PHOT_APERTURES %.1lf,%.1lf,%.1lf,%.1lf,%.1lf,%.1lf -CATALOG_NAME %s.apphot %s", gain_sextractor_cl_parameter_string, saturation_limitsextractor_cl_parameter_string, APERTURE, APERTURE, ap[0], ap[1], ap[2], ap[3], output_sextractor_catalog, fitsfilename );
  }
  fprintf( stderr, "%s\n", command );
  write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", "running SExtractor in the aperture photometry mode with the command\n", command );
  if ( 0 != system( command ) ) {
   fprintf( stderr, "ERROR: the command returned a non-zero exit code!\n" );
  }
  // !!! EXTRA APERTURE PHOTOMETRY RUN !!!
 }

 free( A );

 free( X1 );
 free( Y1 );
 free( X2 );
 free( Y2 );

 // Remove flag file to save disk space (if it was used)
 if ( is_flag_image_used == 1 ) {
  write_string_to_individual_image_log( output_sextractor_catalog, "autodetect_aperture(): ", "removing flag image ", flag_image_filename );
#ifdef REMOVE_FLAG_IMAGES_TO_SAVE_SPACE
  if ( 0 != unlink( flag_image_filename ) )
   fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", flag_image_filename );
  if ( 0 != unlink( weight_image_filename ) )
   fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", weight_image_filename );
#endif
#ifdef REMOVE_SEX_LOG_FILES
  if ( 0 != unlink( sextractor_messages_filename ) )
   fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", sextractor_messages_filename );
#endif
 }

 return APERTURE;
}
