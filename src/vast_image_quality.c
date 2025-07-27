/* -------------  C standard library ------------- */
#include <stdio.h>      /* FILE, fopen, fclose, fgets, fprintf, stderr        */
#include <stdlib.h>     /* malloc, free, exit, EXIT_FAILURE                   */
#include <string.h>     /* strncpy                                            */
#include <math.h>       /* fabs                                               */

/* -------------  GNU Scientific Library (GSL) ------------- */
#include <gsl/gsl_sort.h>             /* gsl_sort()                           */
#include <gsl/gsl_statistics.h>       /* gsl_stats_median_from_sorted_data()  */


#include "vast_limits.h"
#include "vast_utils.h"
#include "vast_image_quality.h"
#include "variability_indexes.h" // for esimate_sigma_from_MAD_of_sorted_data()
#include "parse_sextractor_catalog.h" // for parse_sextractor_catalog_string()


// This function will try to find the deepest image and set it as the reference one
// by altering the image order in input_images array
void choose_best_reference_image( char **input_images, int *vast_bad_image_flag, int Num ) {
 char sextractor_catalog[FILENAME_LENGTH];
 char copy_input_image_path[FILENAME_LENGTH];
 char sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT];

 int star_number_in_sextractor_catalog, sextractor_flag;
 double flux_adu, flux_adu_err, position_x_pix, position_y_pix, mag, sigma_mag;
 double a_a; // semi-major axis lengths
 double a_a_err;
 double a_b; // semi-minor axis lengths
 double a_b_err;
 float float_parameters[NUMBER_OF_FLOAT_PARAMETERS];

 int external_flag;
 double psf_chi2;

 int i, best_image;

 int previous_star_number_in_sextractor_catalog; // !! to check that the star count in the output catalog is always increasing

 double *number_of_good_detected_stars; // this is double for the simple reason that I want to use the conveinent double functions from GSL (already included for other purposes)
 double *copy_of_number_of_good_detected_stars;
 double median_number_of_good_detected_stars;

 int int_number_of_good_detected_stars;
 double *A_IMAGE;
 double *aperture;
 double best_aperture;

 FILE *file;

 fprintf( stderr, "Trying to automatically select the reference image!\n" );

 if ( Num <= 0 ) {
  fprintf( stderr, "ERROR: Num is too small for choosing best reference image\n" );
  exit( EXIT_FAILURE );
 }

 number_of_good_detected_stars= malloc( Num * sizeof( double ) );
 if ( NULL == number_of_good_detected_stars ) {
  fprintf( stderr, "ERROR in choose_best_reference_image() while allocating memory for number_of_good_detected_stars\n" );
  exit( EXIT_FAILURE );
 }

 aperture= malloc( Num * sizeof( double ) );
 if ( NULL == aperture ) {
  fprintf( stderr, "ERROR in choose_best_reference_image() while allocating memory for aperture\n" );
  exit( EXIT_FAILURE );
 }

 A_IMAGE= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( NULL == A_IMAGE ) {
  fprintf( stderr, "ERROR in choose_best_reference_image() while allocating memory for A_IMAGE\n" );
  exit( EXIT_FAILURE );
 }

 // Initialize values to make the compiler happy
 for ( i= 0; i < NUMBER_OF_FLOAT_PARAMETERS; i++ ) {
  float_parameters[i]= 0.0;
 }

 for ( i= 0; i < Num; i++ ) {
  // Get the star catalog name from the image name
  if ( 0 != find_catalog_in_vast_images_catalogs_log( input_images[i], sextractor_catalog ) ) {
   fprintf( stderr, "WARNING in choose_best_reference_image(): cannot read the catalog file associated with the image %s\n", input_images[i] );
   number_of_good_detected_stars[i]= 0.0;
   aperture[i]= 0.0;
   continue;
  }
  // count number of detected_stars
  file= fopen( sextractor_catalog, "r" );
  if ( file == NULL ) {
   fprintf( stderr, "WARNING in choose_best_reference_image(): cannot open file %s\n", sextractor_catalog );
   number_of_good_detected_stars[i]= 0.0;
   aperture[i]= 0.0;
   continue;
  }

  previous_star_number_in_sextractor_catalog= 0;
  number_of_good_detected_stars[i]= 0.0;
  aperture[i]= 0.0;
  int_number_of_good_detected_stars= 0;
  while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, file ) ) {
   sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT - 1]= '\0'; // just in case
   external_flag= 0;
   if ( 0 != parse_sextractor_catalog_string( sextractor_catalog_string, &star_number_in_sextractor_catalog, &flux_adu, &flux_adu_err, &mag, &sigma_mag, &position_x_pix, &position_y_pix, &a_a, &a_a_err, &a_b, &a_b_err, &sextractor_flag, &external_flag, &psf_chi2, float_parameters ) ) {
    continue;
   }
   // Read only stars detected at the first FITS image extension.
   // The start of the second image extension will be signified by a jump in star numbering
   if ( star_number_in_sextractor_catalog < previous_star_number_in_sextractor_catalog ) {
    break;
   } else {
    previous_star_number_in_sextractor_catalog= star_number_in_sextractor_catalog;
   }

   // Check if the catalog line is a really band one
   if ( flux_adu <= 0 ) {
    continue;
   }
   if ( flux_adu_err == 999999 ) {
    continue;
   }
   if ( mag == 99.0000 ) {
    continue;
   }
   if ( sigma_mag == 99.0000 ) {
    continue;
   }
   // If we have no error estimates in at least one aperture - assume things are bad with this object
   if ( float_parameters[3] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[5] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[7] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[9] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[11] == 99.0000 ) {
    continue;
   }
//
#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
   if ( mag < BRIGHTEST_STARS ) {
    continue;
   }
   if ( mag > FAINTEST_STARS_ANYMAG ) {
    continue;
   }
   if ( sigma_mag > MAX_MAG_ERROR ) {
    continue;
   }
#endif
   //
   if ( flux_adu < MIN_SNR * flux_adu_err ) {
    continue;
   }
   // Experimental: ount only high-SNR stars
   if ( flux_adu < 20.0 * flux_adu_err ) {
    continue;
   }
   //
   // https://en.wikipedia.org/wiki/Full_width_at_half_maximum
   // ok, I'm not sure if A is the sigma or sigma/2
   if ( SIGMA_TO_FWHM_CONVERSION_FACTOR * ( a_a + a_a_err ) < FWHM_MIN ) {
    continue;
   }
   if ( SIGMA_TO_FWHM_CONVERSION_FACTOR * ( a_b + a_b_err ) < FWHM_MIN ) {
    continue;
   }
   // !!! That doesn't seem to solve the problem
   // float_parameters[0] is the actual FWHM
   if ( float_parameters[0] < 0.0 ) {
    // Faint stars and especially hot pixels tend to have negative FWHM estimate
    continue;
   }
   if ( MAX( float_parameters[0], SIGMA_TO_FWHM_CONVERSION_FACTOR * a_a ) < FWHM_MIN ) {
    continue;
   }
   //
   if ( external_flag != 0 ) {
    continue;
   }
   //
   // just in case we mark objects with really bad SExtractor flags
   if ( sextractor_flag > 7 ) {
    continue;
   }
   A_IMAGE[int_number_of_good_detected_stars]= a_a;
   int_number_of_good_detected_stars++;
  } // while( NULL!=fgets(sextractor_catalog_string,MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT,file) ){

  fclose( file );
  number_of_good_detected_stars[i]= (double)int_number_of_good_detected_stars;
  if ( int_number_of_good_detected_stars < MIN_NUMBER_OF_STARS_ON_FRAME ) {
   // mark as bad image that has too few stars
   aperture[i]= 0.0;
   continue;
  }
  gsl_sort( A_IMAGE, 1, int_number_of_good_detected_stars );
  aperture[i]= CONST * gsl_stats_median_from_sorted_data( A_IMAGE, 1, int_number_of_good_detected_stars );
  fprintf( stderr, "Redetermining aperture for the image %s %.1lfpix\n", input_images[i], aperture[i] );
 }
 free( A_IMAGE );

 // Determine median number of stars on images
 best_image= 0;
 copy_of_number_of_good_detected_stars= malloc( Num * sizeof( double ) );
 if ( NULL == copy_of_number_of_good_detected_stars ) {
  fprintf( stderr, "ERROR allocating memory for copy_of_number_of_good_detected_stars in choose_best_reference_image()\n" );
  exit( EXIT_FAILURE );
 }
 for ( i= 0; i < Num; i++ ) {
  copy_of_number_of_good_detected_stars[i]= number_of_good_detected_stars[i];
 }
 gsl_sort( copy_of_number_of_good_detected_stars, 1, Num );
 median_number_of_good_detected_stars= gsl_stats_median_from_sorted_data( copy_of_number_of_good_detected_stars, 1, Num );
 free( copy_of_number_of_good_detected_stars );
 ///

 fprintf( stderr, "==> median number of good stars %.0lf, max. allowed number of good stars %.0lf = 2*median\n", median_number_of_good_detected_stars, 2.0 * median_number_of_good_detected_stars );

 // Avoid choosing an image with double-detections as the best one
 best_image= 0;
 // best_number_of_good_detected_stars= 0.0;
 best_aperture= 99.0;
 for ( i= 0; i < Num; i++ ) {
  fprintf( stderr, "%4.1lf %5.0lf %d  %s \n", aperture[i], number_of_good_detected_stars[i], vast_bad_image_flag[i], input_images[i] );
  // avoid images that have too many stars
  if ( number_of_good_detected_stars[i] < 2.0 * median_number_of_good_detected_stars ) {
   // avoid images that have too few stars
   if ( number_of_good_detected_stars[i] >= median_number_of_good_detected_stars && number_of_good_detected_stars[i] > 0.0 ) {
    // avoid images that don't have a good aperture estimate
    if ( aperture[i] > 0.0 ) {
     // Make sure the bad image flag is not set for this image
     if ( vast_bad_image_flag[i] == 0 ) {
      // The new way of selecting reference image as the one that has the best seeing
      if ( aperture[i] < best_aperture ) {
       best_image= i;
       best_aperture= aperture[i];
       fprintf( stderr, "new best!\n" );
      }
     }
    }
   }
  }
  // fprintf(stderr,"%lf %s \n",number_of_good_detected_stars[i],input_images[i]);
 }

 // fprintf(stderr,"%lf %s  -- NEW BEST\n",best_number_of_good_detected_stars,input_images[best_image]);

 fprintf( stderr, "\nAutomatically selected %s as the reference image.\n\n", input_images[best_image] );

 free( aperture );

 free( number_of_good_detected_stars );

 // Write-down the name of the new reference image
 file= fopen( "vast_automatically_selected_reference_image.log", "w" );
 if ( file == NULL ) {
  fprintf( stderr, "ERROR in choose_best_reference_image(): cannot open vast_automatically_selected_reference_image.log for writing!\n" );
  return;
 }
 fprintf( file, "%s\n", input_images[best_image] );
 fclose( file );

 // Replace the reference image
 if ( best_image != 0 ) {
  strncpy( copy_input_image_path, input_images[0], FILENAME_LENGTH );
  strncpy( input_images[0], input_images[best_image], FILENAME_LENGTH );
  strncpy( input_images[best_image], copy_input_image_path, FILENAME_LENGTH );
 }

 return;
}

void mark_images_with_elongated_stars_as_bad( char **input_images, int *vast_bad_image_flag, int Num ) {
 char sextractor_catalog[FILENAME_LENGTH];
 char sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT];

 int star_number_in_sextractor_catalog, sextractor_flag;
 double flux_adu, flux_adu_err, position_x_pix, position_y_pix, mag, sigma_mag;
 double a_a; // semi-major axis lengths
 double a_a_err;
 double a_b; // semi-minor axis lengths
 double a_b_err;
 float float_parameters[NUMBER_OF_FLOAT_PARAMETERS];

 int external_flag;
 double psf_chi2;

 int i;

 int previous_star_number_in_sextractor_catalog; // !! to check that the star count in the output catalog is always increasing

 // double *number_of_good_detected_stars; // this is double for the simple reason that I want to use the conveinent double functions from GSL (already included for other purposes)

 int number_of_good_detected_stars;

 //
 // int number_of_stars_current_image;
 double *a_minus_b;
 double *a_minus_b__image;
 double *a_minus_b__image__to_be_runied_by_sort;
 double median_a_minus_b;
 double sigma_from_MAD_a_minus_b;
 //

 double a_minus_b_cutoff_threshold= 0;

 FILE *file;

 fprintf( stderr, "Trying to automatically reject images with elongated stars!\n" );

 if ( Num <= 0 ) {
  fprintf( stderr, "ERROR: Num is too small\n" );
  exit( EXIT_FAILURE );
 }

 if ( Num <= 20 ) {
  fprintf( stderr, "WARNING: Num is too small for identifying images with elongated stars! Will do nothing.\n" );
  return;
 }

 a_minus_b__image= malloc( Num * sizeof( double ) );
 a_minus_b__image__to_be_runied_by_sort= malloc( Num * sizeof( double ) );
 if ( NULL == a_minus_b__image || NULL == a_minus_b__image__to_be_runied_by_sort ) {
  fprintf( stderr, "ERROR allocating memory in mark_images_with_elongated_stars_as_bad()\n" );
  exit( EXIT_FAILURE );
 }

 // Initialize the values to make the compier happy
 for ( i= 0; i < NUMBER_OF_FLOAT_PARAMETERS; i++ ) {
  float_parameters[i]= 0.0;
 }

#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i, a_minus_b, sextractor_catalog, file, previous_star_number_in_sextractor_catalog, number_of_good_detected_stars, sextractor_catalog_string, star_number_in_sextractor_catalog, flux_adu, flux_adu_err, mag, sigma_mag, position_x_pix, position_y_pix, a_a, a_a_err, a_b, a_b_err, sextractor_flag, external_flag, psf_chi2, float_parameters )
#endif
#endif
 for ( i= 0; i < Num; i++ ) {

  // Get the star catalog name from the image name
  if ( 0 != find_catalog_in_vast_images_catalogs_log( input_images[i], sextractor_catalog ) ) {
   fprintf( stderr, "WARNING in mark_images_with_elongated_stars_as_bad(): cannot read the catalog file associated with the image %s\n", input_images[i] );
   a_minus_b__image__to_be_runied_by_sort[i]= a_minus_b__image[i]= -0.1; // is it a good choice?
   continue;
  }
  // count number of detected_stars
  file= fopen( sextractor_catalog, "r" );
  if ( file == NULL ) {
   fprintf( stderr, "WARNING in mark_images_with_elongated_stars_as_bad(): cannot open file %s\n", sextractor_catalog );
   a_minus_b__image__to_be_runied_by_sort[i]= a_minus_b__image[i]= -0.01; // is it a good choice?
   continue;
  }

  a_minus_b= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( a_minus_b == NULL ) {
   fprintf( stderr, "MEMORY ERROR in mark_images_with_elongated_stars_as_bad()\n" );
   exit( EXIT_FAILURE );
  }
  previous_star_number_in_sextractor_catalog= 0;
  number_of_good_detected_stars= 0;
  while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, file ) ) {
   sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT - 1]= '\0'; // just in case
   external_flag= 0;
   if ( 0 != parse_sextractor_catalog_string( sextractor_catalog_string, &star_number_in_sextractor_catalog, &flux_adu, &flux_adu_err, &mag, &sigma_mag, &position_x_pix, &position_y_pix, &a_a, &a_a_err, &a_b, &a_b_err, &sextractor_flag, &external_flag, &psf_chi2, float_parameters ) ) {
    sextractor_catalog_string[0]= '\0'; // just in case
    continue;
   }
   // Read only stars detected at the first FITS image extension.
   // The start of the second image extension will be signified by a jump in star numbering
   if ( star_number_in_sextractor_catalog < previous_star_number_in_sextractor_catalog ) {
    fprintf( stderr, "WARNING in mark_images_with_elongated_stars_as_bad(): this seems to be a multi-extension FITS\n" );
    break;
   } else {
    previous_star_number_in_sextractor_catalog= star_number_in_sextractor_catalog;
   }
   sextractor_catalog_string[0]= '\0'; // just in case

   // Check if the catalog line is a really band one
   if ( flux_adu <= 0 ) {
    continue;
   }
   if ( flux_adu_err == 999999 ) {
    continue;
   }
   if ( mag == 99.0000 ) {
    continue;
   }
   if ( sigma_mag == 99.0000 ) {
    continue;
   }
   // If we have no error estimates in at least one aperture - assume things are bad with this object
   if ( float_parameters[3] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[5] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[7] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[9] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[11] == 99.0000 ) {
    continue;
   }
//
#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
   if ( mag < BRIGHTEST_STARS ) {
    continue;
   }
   if ( mag > FAINTEST_STARS_ANYMAG ) {
    continue;
   }
   if ( sigma_mag > MAX_MAG_ERROR ) {
    continue;
   }
#endif
   //
   if ( flux_adu < MIN_SNR * flux_adu_err ) {
    continue;
   }
   //
   // https://en.wikipedia.org/wiki/Full_width_at_half_maximum
   // ok, I'm not sure if A is the sigma or sigma/2
   if ( SIGMA_TO_FWHM_CONVERSION_FACTOR * ( a_a + a_a_err ) < FWHM_MIN ) {
    continue;
   }
   if ( SIGMA_TO_FWHM_CONVERSION_FACTOR * ( a_b + a_b_err ) < FWHM_MIN ) {
    continue;
   }
   // float_parameters[0] is the actual FWHM
   // if ( float_parameters[0] < FWHM_MIN ) {
   if ( MAX( float_parameters[0], SIGMA_TO_FWHM_CONVERSION_FACTOR * a_a ) < FWHM_MIN ) {
    continue;
   }
   //
   if ( external_flag != 0 ) {
    continue;
   }
   //
   // just in case we mark objects with really bad SExtractor flags
   if ( sextractor_flag > 7 ) {
    continue;
   }
   a_minus_b[number_of_good_detected_stars]= a_a - a_b;
   number_of_good_detected_stars++;
  } // while( NULL!=fgets(sextractor_catalog_string,MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT,file) ){

  fclose( file );

  if ( number_of_good_detected_stars < MIN_NUMBER_OF_STARS_ON_FRAME ) {
   // mark as bad image that has too few stars
   a_minus_b__image__to_be_runied_by_sort[i]= a_minus_b__image[i]= -0.001; // is it a good choice?
   free( a_minus_b );
   continue;
  }
  gsl_sort( a_minus_b, 1, number_of_good_detected_stars );
  a_minus_b__image__to_be_runied_by_sort[i]= a_minus_b__image[i]= gsl_stats_median_from_sorted_data( a_minus_b, 1, number_of_good_detected_stars );
  fprintf( stderr, "median(A-B) for the image %s %.3lfpix\n", input_images[i], a_minus_b__image[i] );

  free( a_minus_b );

 } // for ( i= 0; i < Num; i++ ) { // cycle through the images

 // Determine median a_minus_b among all images
 gsl_sort( a_minus_b__image__to_be_runied_by_sort, 1, Num );
 median_a_minus_b= gsl_stats_median_from_sorted_data( a_minus_b__image__to_be_runied_by_sort, 1, Num );
 sigma_from_MAD_a_minus_b= esimate_sigma_from_MAD_of_sorted_data( a_minus_b__image__to_be_runied_by_sort, (long)Num );
 free( a_minus_b__image__to_be_runied_by_sort );
 // !!! We should consider the possibility that sigma_from_MAD_a_minus_b= 0.0
 // !!! and median_a_minus_b= -0.001

 //
 file= fopen( "vast_accepted_or_rejected_images_based_on_stars_elongation.log", "w" );
 if ( file == NULL ) {
  fprintf( stderr, "ERROR in mark_images_with_elongated_stars_as_bad(): cannot open vast_automatically_selected_reference_image.log for writing!\n" );
  free( a_minus_b__image );
  return;
 }

 // Determine the cut-off threshold
 a_minus_b_cutoff_threshold= 5.0 * MAX( sigma_from_MAD_a_minus_b, 0.05 );
 fprintf( file, "# (A-B) cut-off threshold: %.3lf pix\n", a_minus_b_cutoff_threshold );
 fprintf( stderr, "# (A-B) cut-off threshold: %.3lf pix\n", a_minus_b_cutoff_threshold );

 fprintf( file, "# 0 in the first column means 'below threshold - image accepted'\n" );
 fprintf( stderr, "# 0 in the first column means 'below threshold - image accepted'\n" );
 fprintf( file, "# 1 in the first column means 'above threshold - image rejected'\n" );
 fprintf( stderr, "# 1 in the first column means 'below threshold - image rejected'\n" );

 fprintf( file, "# median(A-B) among all images %.3lf +/-%.3lf pix\n", median_a_minus_b, sigma_from_MAD_a_minus_b );
 fprintf( stderr, "# median(A-B) among all images %.3lf +/-%.3lf pix\n", median_a_minus_b, sigma_from_MAD_a_minus_b );

 // Cycle through all images and mark good and bad ones
 for ( i= 0; i < Num; i++ ) {
  // the image is so bad we could not compute A-B
  // if ( a_minus_b__image[i] == -0.1 ) {
  if ( a_minus_b__image[i] < 0.0 ) {
   vast_bad_image_flag[i]= 1;
   fprintf( file, "%d  %.3lf  %s\n", vast_bad_image_flag[i], a_minus_b__image[i], input_images[i] );
   fprintf( stderr, "%d  %.3lf  %s\n", vast_bad_image_flag[i], a_minus_b__image[i], input_images[i] );
   continue;
  }
  // check if image A-B is too large
  if ( fabs( a_minus_b__image[i] - median_a_minus_b ) > a_minus_b_cutoff_threshold ) {
   vast_bad_image_flag[i]= 2;
   fprintf( file, "%d  %.3lf  %s\n", vast_bad_image_flag[i], a_minus_b__image[i], input_images[i] );
   fprintf( stderr, "%d  %.3lf  %s\n", vast_bad_image_flag[i], a_minus_b__image[i], input_images[i] );
   continue;
  }
  // this image is good
  vast_bad_image_flag[i]= 0;
  fprintf( file, "%d  %.3lf  %s\n", vast_bad_image_flag[i], a_minus_b__image[i], input_images[i] );
  fprintf( stderr, "%d  %.3lf  %s\n", vast_bad_image_flag[i], a_minus_b__image[i], input_images[i] );
 }

 free( a_minus_b__image );

 fclose( file );

 return;
}
