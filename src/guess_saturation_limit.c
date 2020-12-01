#define _GNU_SOURCE // for memmem() defined in string.h
#include <string.h>
// these should go first, ohterwise GCC will complain about implicit declaration of memmem

#include <stdio.h>
#include <stdlib.h>
#include <libgen.h>    // for basename()
#include <sys/stat.h>  // for stat(), also requires #include <sys/types.h> and #include <unistd.h>
#include <sys/types.h> // for stat()
#include <unistd.h>    // for stat()

#include <gsl/gsl_sort.h>
#include <gsl/gsl_statistics.h>

#include "fitsio.h"

#include "vast_limits.h"

#include "variability_indexes.h" // for esimate_sigma_from_MAD_of_sorted_data_float()

#define COUNT_N_PIXELS_AROUND_BAD_ONE 2

// defined in autodetect_aperture.c
// therefore any program that uses guess_saturation_limit() should be linked against autodetect_aperture.o
int find_catalog_in_vast_images_catalogs_log(char *fitsfilename, char *catalogfilename);

// 1 - default gain value is found in default.sex
//     will alow the program to change it
// 0 - non-default gain value is found in default.sex
//     the program will use the value from default.sex
// 2 - GAIN_KEY is present in default.sex - do nothing
int check_gain_in_default_sex(double *out_gain_from_default_sex) {
 double gain_in_default_sex;
 int i, j;
 char str1[256];
 FILE *f;
 f= fopen("default.sex", "r");
 if( NULL == f ) {
  fprintf(stderr, "ERROR: Can't open default.sex\n");
  return 1;
 };
 // first check if GAIN_KEY is present
 while( NULL != fgets(str1, 256, f) ) {
  str1[255]= '\0'; // just in case
  if( str1[0] == '#' )
   continue;
  if( strlen(str1) < 9 )
   continue;
  for( i= 0; i < (int)strlen(str1) - 9; i++ ) {
   if( str1[i] == '#' )
    break; // go to next line
   if( str1[i] == 'G' && str1[i + 1] == 'A' && str1[i + 2] == 'I' && str1[i + 3] == 'N' && str1[i + 4] == '_' && str1[i + 5] == 'K' && str1[i + 6] == 'E' && str1[i + 7] == 'Y' ) {
    // GAIN_KEY is found
    return 2;
   }
  }
 }
 fseek(f, 0, SEEK_SET); // go back to the beginning of the file
 // then try to read the GAIN value
 while( NULL != fgets(str1, 256, f) ) {
  str1[255]= '\0'; // just in case
  if( str1[0] == '#' )
   continue;
  if( strlen(str1) < 6 )
   continue;
  for( i= 0; i < (int)strlen(str1) - 6; i++ ) {
   if( str1[i] == '#' )
    break; // go to next line
   if( str1[i] == 'G' && str1[i + 1] == 'A' && str1[i + 2] == 'I' && str1[i + 3] == 'N' && str1[i + 4] == ' ' ) {
    // this is our key
    // make sure there is no other stuff written after the gain value
    for( j= i + 5; j < (int)strlen(str1) - 6; j++ ) {
     if( str1[j] == '#' ) {
      str1[j]= '\0';
      break;
     }
     if( str1[j] != '0' && str1[j] != '1' && str1[j] != '2' && str1[j] != '3' && str1[j] != '4' && str1[j] != '5' && str1[j] != '6' && str1[j] != '7' && str1[j] != '8' && str1[j] != '9' && str1[j] != '.' && str1[j] != ' ' && str1[j] != '\t' ) {
      str1[j]= '\0';
      break;
     }
    }
    // read the gain value
    sscanf(str1, "GAIN %lf", &gain_in_default_sex);
    (*out_gain_from_default_sex)= gain_in_default_sex;
    fclose(f);
    if( gain_in_default_sex == 5.0 || gain_in_default_sex == 0.0 ) {
     return 1;
    } else {
     return 0;
    }
   }
  }
 }
 fclose(f);
 return 1;
}

// 0 - no
// 1 - yes
int check_if_gain_keyword_comment_looks_suspicious(char *gain_keyword_comment) {
 if( NULL != memmem(gain_keyword_comment, sizeof(gain_keyword_comment), "switch", 7) ) {
  if( NULL != memmem(gain_keyword_comment, sizeof(gain_keyword_comment), "position", 9) ) {
   return 1;
  }
 }
 return 0;
}

// Try to set the correct CCD gain from FITS image header
// operation_mode=0 // do nothing
// operation_mode=1 // force the use of gain guessed from images
// operation_mode=2 // try to be clever
//
// if raise_unset_gain_warning=1 - warn the user that gain value should be set manually
// if raise_unset_gain_warning=0 - silently ignore the problem
int guess_gain(char *fitsfilename, char *resulting_sextractor_cl_parameter_string, int operation_mode, int raise_unset_gain_warning) {

 char str[256]; // for TSTRING type keys from FITS header
 char comment_str[256];

 fitsfile *fptr; // FITS file pointer
 int status= 0;  // CFITSIO status value MUST be initialized to zero!
 int hdutype;

 double guessed_gain, gain_from_fits_header, double_trash;

 double exposure= 0.0;

 int check_gain_in_default_sex_result;

 int bitpix;

 // Check the input
 if( operation_mode < 0 || operation_mode > 2 ) {
  fprintf(stderr, "ERROR: unknown operation_mode=%d (should be 0, 1 or 2)\n", operation_mode);
  return 1;
 }

 // do nothing if we don't need to
 if( operation_mode == 0 ) {
  resulting_sextractor_cl_parameter_string[0]= '\0';
  return 0;
 }

 // Try to play smart here: if a non-default gain value is specified in default.sex - use this one, don't try to guess
 if( operation_mode == 2 ) {
  check_gain_in_default_sex_result= check_gain_in_default_sex(&guessed_gain);
  if( 1 != check_gain_in_default_sex_result ) {
   resulting_sextractor_cl_parameter_string[0]= '\0';
   if( 2 != check_gain_in_default_sex_result ) {
    fprintf(stderr, "The gain value (GAIN=%.3lf) from default.sex will be used for image %s\nThe above guess is based on the non-default gain value specified in default.sex by user\n", guessed_gain, fitsfilename);
   }
   return 0;
  }
 }

 if( 0 == fits_open_image(&fptr, fitsfilename, READONLY, &status) ) {
  if( fits_get_hdu_type(fptr, &hdutype, &status) || hdutype != IMAGE_HDU ) {
   fprintf(stderr, "ERROR: this program only works on images, not tables\n");
   return 1;
  }
  // Special case for HST images
  fits_read_key(fptr, TSTRING, "BUNIT", str, NULL, &status);
  if( status == 0 ) {
   gain_from_fits_header= -99.9;
   if( 0 == strncmp(str, "count   ", 8) )
    gain_from_fits_header= 1.0; // Swift/UVOT
   if( 0 == strncmp(str, "ELECTRONS", 9) )
    gain_from_fits_header= 1.0;                 // HST raw images
   if( 0 == strncmp(str, "ELECTRONS/S", 11) ) { // HST level 1 (drizzled/resampled images)
    fits_read_key(fptr, TDOUBLE, "EXPTIME", &exposure, NULL, &status);
    if( status == 0 ) {
     gain_from_fits_header= exposure; // Gain is equal to exposure time if this is a count rate image!
    }
   }
   // If we managed to recognize the BUNIT key...
   if( gain_from_fits_header != -99.9 ) {
    fits_close_file(fptr, &status); // close file
    guessed_gain= gain_from_fits_header;
    sprintf(resulting_sextractor_cl_parameter_string, " -GAIN %.3lf ", guessed_gain);
    fprintf(stderr, "The gain value (GAIN=%.3lf) is set based on the FITS header key BUNIT=%s of the image %s\n", guessed_gain, str, fitsfilename);
    return 0;
   }
  }
  status= 0; // reset status, it is OK not to find this keyword

  // Special case Siril imae stacking code producess some really strange normalization when writing 32bit floating-point images.
  // As the result, the default non-zero gain value completely messes up error estimation for the detected sources.
  // If this is a DSLR image (as indicated by the presence of ISOSPEED key) and it is 32bit floatng point - set gain to 0.
  status= 0;
  fits_read_key(fptr, TDOUBLE, "ISOSPEED", &double_trash, NULL, &status);
  if( status == 0 ) {
   fits_get_img_type(fptr, &bitpix, &status);
   if( status != 0 ) {
    fprintf(stderr, "ERROR: cannot get FITS image type!\n");
   } else {
    if( bitpix == -32 ) {
     fits_close_file(fptr, &status); // close file
     guessed_gain= 0.0;
     sprintf(resulting_sextractor_cl_parameter_string, "-GAIN %.3lf ", guessed_gain);
     fprintf(stderr, "The gain value is set to 0 for a BITPIX = -32 DSLR image %s\n", fitsfilename);
     return 0;
    }
   }
  }

  // Normal GAIN keyword
  status= 0;
  fits_read_key(fptr, TDOUBLE, "GAIN", &gain_from_fits_header, comment_str, &status);
  if( status == 0 ) {
   if( 0 == check_if_gain_keyword_comment_looks_suspicious(comment_str) ) {
    fits_close_file(fptr, &status); // close file
    guessed_gain= gain_from_fits_header;
    sprintf(resulting_sextractor_cl_parameter_string, "-GAIN %.3lf ", guessed_gain);
    fprintf(stderr, "The gain value (GAIN=%.3lf) is obtained from the FITS header of the image %s\n", guessed_gain, fitsfilename);
    return 0;
   }
  }
  // EGAIN keyword
  status= 0;
  fits_read_key(fptr, TDOUBLE, "EGAIN", &gain_from_fits_header, NULL, &status);
  if( status == 0 ) {
   fits_close_file(fptr, &status); // close file
   guessed_gain= gain_from_fits_header;
   sprintf(resulting_sextractor_cl_parameter_string, "-GAIN %.3lf ", guessed_gain);
   fprintf(stderr, "The gain value (EGAIN=%.3lf) is obtained from the FITS header of the image %s\n", guessed_gain, fitsfilename);
   return 0;
  }
  // CCDSENS keyword
  status= 0;
  fits_read_key(fptr, TDOUBLE, "CCDSENS", &gain_from_fits_header, NULL, &status);
  if( status == 0 ) {
   fits_close_file(fptr, &status); // close file
   guessed_gain= gain_from_fits_header;
   sprintf(resulting_sextractor_cl_parameter_string, "-GAIN %.3lf ", guessed_gain);
   fprintf(stderr, "The gain value (CCDSENS=%.3lf) is obtained from the FITS header of the image %s\n", guessed_gain, fitsfilename);
   return 0;
  }
  // CCDGAIN keyword
  status= 0;
  fits_read_key(fptr, TDOUBLE, "CCDGAIN", &gain_from_fits_header, NULL, &status);
  if( status == 0 ) {
   fits_close_file(fptr, &status); // close file
   guessed_gain= gain_from_fits_header;
   sprintf(resulting_sextractor_cl_parameter_string, "-GAIN %.3lf ", guessed_gain);
   fprintf(stderr, "The gain value (CCDGAIN=%.3lf) is obtained from the FITS header of the image %s\n", guessed_gain, fitsfilename);
   return 0;
  }
  // GAINCCD keyword
  status= 0;
  fits_read_key(fptr, TDOUBLE, "GAINCCD", &gain_from_fits_header, NULL, &status);
  if( status == 0 ) {
   fits_close_file(fptr, &status); // close file
   guessed_gain= gain_from_fits_header;
   sprintf(resulting_sextractor_cl_parameter_string, "-GAIN %.3lf ", guessed_gain);
   fprintf(stderr, "The gain value (GAINCCD=%.3lf) is obtained from the FITS header of the image %s\n", guessed_gain, fitsfilename);
   return 0;
  } else {
   status= 0;                      // reset status, it's OK not to find the GAIN keyword in the header
   fits_close_file(fptr, &status); // close file
   if( raise_unset_gain_warning == 1 )
    fprintf(stderr, "WARNING: no gain value could be found for the image %s\nPlease specify it using GAIN keyword in default.sex or image FITS header,\notherwise aperture photometry error estimates will be unreliable and\nPSF-fitting photometry with PSFEx will not be possible at all.\n", fitsfilename);
   resulting_sextractor_cl_parameter_string[0]= '\0';
   return 0;
  }
  fits_close_file(fptr, &status); // close file
 }

 if( status != 0 ) {
  fits_report_error(stderr, status); // print any error message
  fits_clear_errmsg();               // clear the CFITSIO error message stack
  return 1;
 }

 resulting_sextractor_cl_parameter_string[0]= '\0';

 return 1; // we are not supposed to get here under the normal circumstances
}

// This function will count the number of zeroes in an image and if there are many - will create a flag image
// for the SExtractor to flag-out stars near zero-leel pixels
//
// Note that is_flag_image_used HAS TO BE INITIALIZED to 2, 1 or 0
// 2 - guess by default, 1 - always use the flag image, 0 - never use the flag image
int check_if_we_need_flag_image(char *fitsfilename, char *resulting_sextractor_cl_parameter_string, int *is_flag_image_used, char *flag_image_filename, char *weight_image_filename) {

 fitsfile *fptr; // FITS file pointer
 int status= 0;  // CFITSIO status value MUST be initialized to zero!
 int hdutype, naxis, ii;
 //long naxes[2], totpix, fpixel[2];
 long naxes[3], totpix, fpixel[3]; // we need naxes[3], fpixel[3] to handle 3D cube slice case with dimentions X*Y*1
 double *pix;
 long number_of_zeroes= 0;
 long number_of_negatives= 0;
 long number_of_subthreshold_pix= 0;
 int flag_subthreshould_pixels_but_not_zeroes= 0;
 char *flag;
 char *weight;
 fitsfile *outfptr_flag;   // FITS file pointer
 fitsfile *outfptr_weight; // FITS file pointer
 char outfilename_flag[FILENAME_LENGTH];
 char outfilename_weight[FILENAME_LENGTH];
 struct stat sb; // structure returned by stat() system call

 int anynul= 0;
 double nullval= 0.0;

 long X, Y, X0, Y0;

 long j, k, l;

 int *number_of_zero_neighbors; // this array will store how many zero-value neighbors each image pixel has
 int number_of_zeroes_tmp;
 int number_of_zeroes2; // yeah, silly

 int hdunum, hducounter;

 double median;
 double sigma_estimated_from_MAD;
 double pixel_value_threshold= MIN_PIX_VALUE; // set to the default value so the compiler is happy

 totpix= 0;   // reset
 median= 0.0; // reset

 // If user requests not to use the flag image by setting is_flag_image_used=0
 if( (*is_flag_image_used) == 0 ) {
  // Nothing to do, we'll be fine even without a flag image
  (*is_flag_image_used)= 0;
  resulting_sextractor_cl_parameter_string[0]= '\0';
  flag_image_filename[0]= '\0';
  return 0;
 }

 // Calculate image median and sigma
 if( 0 == fits_open_image(&fptr, fitsfilename, READONLY, &status) ) {

  fits_get_img_dim(fptr, &naxis, &status);
  if( naxis > 3 ) {
   fprintf(stderr, "ERROR: NAXIS = %d.  Only 2-D images are supported.\n", naxis);
   return 1;
  }
  // with the above check naxes should not overflow
  // maxdim = 2 also protects
  fits_get_img_size(fptr, 2, naxes, &status);

  if( status || naxis != 2 ) {
   if( naxis == 3 ) {
    long naxes3;
    fits_read_key(fptr, TLONG, "NAXIS3", &naxes3, NULL, &status);
    if( naxes3 != 1 ) {
     fprintf(stderr, "ERROR: NAXIS = %d.  Only 2-D images are supported.\n", naxis);
     (*is_flag_image_used)= 0;                          // just in case
     resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
     flag_image_filename[0]= '\0';                      // just in case
     return 1;
    }
   } else {
    fprintf(stderr, "ERROR: NAXIS = %d.  Only 2-D images are supported.\n", naxis);
    (*is_flag_image_used)= 0;                          // just in case
    resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
    flag_image_filename[0]= '\0';                      // just in case
    return 1;
   }
  }
  if( naxes[0] < 1 || naxes[1] < 1 ) {
   fprintf(stderr, "ERROR in check_if_we_need_flag_image() the image dimensions are clearly wrong!\n");
   return 1;
  }
  totpix= naxes[0] * naxes[1];
  pix= (double *)malloc(totpix * sizeof(double)); // memory for the input image
  if( pix == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for pix(guess_saturation_limit.c)\n");
   (*is_flag_image_used)= 0;                          // just in case
   resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
   flag_image_filename[0]= '\0';                      // just in case
   return 1;
  }
  fits_read_img(fptr, TDOUBLE, 1, totpix, &nullval, pix, &anynul, &status);
  if( status != 0 ) {
   fprintf(stderr, "WARNING! Non-zero status after reading the image\n");
   fits_report_error(stderr, status); // print any error message
   fits_clear_errmsg();               // clear the CFITSIO error message stack
   status= 0;
  }
  fits_close_file(fptr, &status);
  gsl_sort(pix, 1, totpix);
  median= gsl_stats_median_from_sorted_data(pix, 1, totpix);
  sigma_estimated_from_MAD= esimate_sigma_from_MAD_of_sorted_data_and_ruin_input_array(pix, totpix);
  free(pix); // we'll mess-up the order of pix while calculating median
  pixel_value_threshold= median - 7.0 * sigma_estimated_from_MAD;
  //
  fprintf(stderr, "Image stats for %s  median=%lf sigma=%lf threshold=%lf\n", basename(fitsfilename), median, sigma_estimated_from_MAD, pixel_value_threshold);
 } else {
  fprintf(stderr, "ERROR in check_if_we_need_flag_image(): cannot open image to get stats!\n");
  status= 0; // just in case
  // Nothing to do, we'll be fine even without a flag image
  (*is_flag_image_used)= 0;
  resulting_sextractor_cl_parameter_string[0]= '\0';
  flag_image_filename[0]= '\0';
  return 0;
 } // if( 0==fits_open_image(&fptr, fitsfilename, READONLY, &status) ){

 //
 /*
 if ( median != 0.0 ) {
  pixel_value_threshold= MAX( 0.0, pixel_value_threshold );
 } else {
  pixel_value_threshold= MIN_PIX_VALUE;
 }
*/
 //

 // If user requests to use the flag image, we don't need to guess
 if( 0 == fits_open_image(&fptr, fitsfilename, READONLY, &status) ) {

  if( fits_get_hdu_type(fptr, &hdutype, &status) || hdutype != IMAGE_HDU ) {
   fprintf(stderr, "ERROR: this program only works on images, not tables\n");
   (*is_flag_image_used)= 0;                          // just in case
   resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
   flag_image_filename[0]= '\0';                      // just in case
   return 1;
  }

  fits_get_img_dim(fptr, &naxis, &status);
  if( naxis > 3 ) {
   fprintf(stderr, "ERROR: NAXIS = %d.  Only 2-D images are supported.\n", naxis);
   return 1;
  }
  // with the above check naxes should not overflow
  // maxdim = 2 also protects
  fits_get_img_size(fptr, 2, naxes, &status);

  if( status || naxis != 2 ) {
   if( naxis == 3 ) {
    long naxes3;
    fits_read_key(fptr, TLONG, "NAXIS3", &naxes3, NULL, &status);
    if( naxes3 != 1 ) {
     fprintf(stderr, "ERROR: NAXIS = %d.  Only 2-D images are supported.\n", naxis);
     (*is_flag_image_used)= 0;                          // just in case
     resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
     flag_image_filename[0]= '\0';                      // just in case
     return 1;
    }
   } else {
    fprintf(stderr, "ERROR: NAXIS = %d.  Only 2-D images are supported.\n", naxis);
    (*is_flag_image_used)= 0;                          // just in case
    resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
    flag_image_filename[0]= '\0';                      // just in case
    return 1;
   }
  }
  status= 0;                                        // if we are still here, one way or the other the status is OK
  pix= (double *)malloc(naxes[0] * sizeof(double)); /* memory for 1 row */

  if( pix == NULL ) {
   fprintf(stderr, "ERROR2: Couldn't allocate memory for pix(guess_saturation_limit.c)\n");
   (*is_flag_image_used)= 0;                          // just in case
   resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
   flag_image_filename[0]= '\0';                      // just in case
   return 1;
  }

  totpix= naxes[0] * naxes[1];
  fpixel[0]= 1; // read starting with first pixel in each row

  fpixel[2]= 1; // this is needed to handle the X*Y*1 case

  // process image one row at a time; increment row # in each loop
  for( fpixel[1]= 1; fpixel[1] <= naxes[1]; fpixel[1]++ ) {
   // this loop executes only once in the X*Y*1 case i.e. only the first row gets to be read
   //fprintf( stderr, "DEBUG: reading line fpixel[1]=%ld out of naxes[1]=%ld, meanwhile naxes[0]=%ld\n", fpixel[1], naxes[1], naxes[0]);
   // give starting pixel coordinate and number of pixels to read
   // int fits_read_pix(fitsfile *fptr, int  datatype, long *fpixel,
   //             long nelements, void *nulval, void *array,
   //             int *anynul, int *status)
   if( fits_read_pix(fptr, TDOUBLE, fpixel, naxes[0], 0, pix, 0, &status) ) {
    break; // jump out of loop on error
   }

   for( ii= 0; ii < naxes[0]; ii++ ) {
    if( pix[ii] == 0.0 ) {
     number_of_zeroes++;
     continue;
    }
    if( pix[ii] < MIN_PIX_VALUE ) {
     number_of_zeroes++;
     continue;
    }
    if( pix[ii] > MAX_PIX_VALUE ) {
     number_of_zeroes++;
     continue;
    }
    if( pix[ii] < 0.0 ) {
     number_of_negatives++;
    }
    if( pix[ii] < pixel_value_threshold ) {
     number_of_subthreshold_pix++;
    }
   }
  }

  free(pix);
  fits_close_file(fptr, &status);

 } // if ( !fits_open_image(&fptr, fitsfilename, READONLY, &status) ){

 if( status != 0 ) {
  fits_report_error(stderr, status);                 /* print any error message */
  fits_clear_errmsg();                               // clear the CFITSIO error message stack
  (*is_flag_image_used)= 0;                          // just in case
  resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
  flag_image_filename[0]= '\0';                      // just in case
  return 1;
 }

 if( 1 != (*is_flag_image_used) ) {

  // First check the sub-threshold pix count
  if( (double)number_of_subthreshold_pix / (double)totpix < FRACTION_OF_ZERO_PIXEL_TO_USE_FLAG_IMG ) {

   // If the image has only a few zero-value pixels
   // or if the image has many negative pixels (meaning that a zero-value is not an extreme)
   // - we do not need to create a flag image.
   fprintf(stderr, "number_of_zeroes = %ld (%.4lf%%)  number_of_negatives = %ld (%.4lf%%)\n", number_of_zeroes, (double)number_of_zeroes / (double)totpix * 100, number_of_negatives, (double)number_of_negatives / (double)totpix * 100);
   if( (double)number_of_zeroes / (double)totpix < FRACTION_OF_ZERO_PIXEL_TO_USE_FLAG_IMG || number_of_negatives > number_of_zeroes ) {
    // Nothing to do, we'll be fine even without a flag image
    (*is_flag_image_used)= 0;
    resulting_sextractor_cl_parameter_string[0]= '\0';
    flag_image_filename[0]= '\0';
    fprintf(stderr, "Flag and weight images will NOT be created for %s\n", fitsfilename);
    return 0;
   }
  } else {
   if( number_of_negatives > number_of_zeroes ) {
    flag_subthreshould_pixels_but_not_zeroes= 1; // KZ Her example
    fprintf(stderr, "flag_subthreshould_pixels_but_not_zeroes= 1\n");
   }
  } // else if ( (double)number_of_subthreshold_pix / (double)totpix < FRACTION_OF_ZERO_PIXEL_TO_USE_FLAG_IMG ) {
 }  // if( 1!=is_flag_image_used ){

 fprintf(stderr, "Flag and weight images will be created for %s\n", fitsfilename);

 ///// If we are still here, check how many zero-value neighbors each zero-value pixel has?
 ///// If there are only few for each pixel -- assume we don't need a flag image
 if( 0 == fits_open_image(&fptr, fitsfilename, READONLY, &status) ) {
  pix= (double *)malloc(totpix * sizeof(double)); // memory for the input image
  if( pix == NULL ) {
   fprintf(stderr, "ERROR3: Couldn't allocate memory for pix(guess_saturation_limit.c)\n");
   (*is_flag_image_used)= 0;                          // just in case
   resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
   flag_image_filename[0]= '\0';                      // just in case
   return 1;
  }

  fits_read_img(fptr, TDOUBLE, 1, totpix, &nullval, pix, &anynul, &status);
  if( status != 0 ) {
   fprintf(stderr, "WARNING! Non-zero status after reading the image\n");
   fits_report_error(stderr, status); // print any error message
   fits_clear_errmsg();               // clear the CFITSIO error message stack
   status= 0;
  }
  fits_close_file(fptr, &status);

  number_of_zero_neighbors= (int *)malloc(totpix * sizeof(int));
  if( number_of_zero_neighbors == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for number_of_zero_neighbours(guess_saturation_limit.c)\n");
   (*is_flag_image_used)= 0;                          // just in case
   resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
   flag_image_filename[0]= '\0';                      // just in case
   return 1;
  }

  //-------------------------------------
  // array index to X Y
  // Y=1+(int)((float)i/(float)naxes[0]);
  // X=i+1-(Y-1)*naxes[0];
  //-------------------------------------
  // X Y to array index
  // i=X-1+(Y-1)*naxes[0];
  //-------------------------------------
  // reset
  //for(ii = 0; ii < totpix; ii++)number_of_zero_neighbors[ii]=0;
  number_of_zeroes2= 0;
  for( ii= 0; ii < totpix; ii++ ) {
   // If the pixel does not need to be flagged - continue

   // First consider the special case of an HST image that is mostly zeroes
   if( median == 0.0 && sigma_estimated_from_MAD == 0.0 ) {
    // we want to flag only the exact 0.0 values leaving all positive and negative values unflaged
    if( pix[ii] != 0.0 ) {
     continue;
    }
   } else {
    // Consider all other images where sigma and pixel_value_threshold are meaningful
    if( flag_subthreshould_pixels_but_not_zeroes == 0 ) {
     if( pix[ii] != 0.0 && pix[ii] > pixel_value_threshold && pix[ii] > MIN_PIX_VALUE && pix[ii] < MAX_PIX_VALUE ) {
      continue;
     }
    } else {
     if( pix[ii] > pixel_value_threshold && pix[ii] > MIN_PIX_VALUE && pix[ii] < MAX_PIX_VALUE ) {
      continue;
     }
    } // if ( flag_subthreshould_pixels_but_not_zeroes == 0 ) {
   }  // if ( median == 0.0 && sigma_estimated_from_MAD == 0.0 ) {
   ///
   /// indent
   {
    number_of_zeroes_tmp= 0;
    // count its neighbors with zero values
    Y0= 1 + (long)((float)ii / (float)naxes[0]);
    X0= ii + 1 - (Y0 - 1) * naxes[0];
    for( j= -1 * COUNT_N_PIXELS_AROUND_BAD_ONE; j <= COUNT_N_PIXELS_AROUND_BAD_ONE; j++ ) {
     X= X0 + j;
     if( X < 1 )
      continue;
     if( X > naxes[0] )
      continue;
     for( k= -1 * COUNT_N_PIXELS_AROUND_BAD_ONE; k <= COUNT_N_PIXELS_AROUND_BAD_ONE; k++ ) {
      Y= Y0 + k;
      if( Y < 1 )
       continue;
      if( Y > naxes[1] )
       continue;
      l= X - 1 + (Y - 1) * naxes[0];
      if( pix[l] == 0.0 || pix[ii] < pixel_value_threshold || pix[l] < MIN_PIX_VALUE || pix[l] > MAX_PIX_VALUE ) {
       number_of_zeroes_tmp++;
      }
     }
    }
    //
    number_of_zero_neighbors[number_of_zeroes2]= number_of_zeroes_tmp;
    number_of_zeroes2++;
   }
   ///
  }
  free(pix);
  gsl_sort_int(number_of_zero_neighbors, 1, number_of_zeroes2);
  number_of_zeroes_tmp= gsl_stats_int_median_from_sorted_data(number_of_zero_neighbors, 1, number_of_zeroes2);

  free(number_of_zero_neighbors);

  if( 1 != (*is_flag_image_used) ) {
   // If there are many zero-value neighbors to each zero-value pixel - do not create flag image
   if( 0.5 > (double)number_of_zeroes_tmp / ((double)(2 * COUNT_N_PIXELS_AROUND_BAD_ONE + 1) * (double)(2 * COUNT_N_PIXELS_AROUND_BAD_ONE + 1)) ) {
    // Nothing to do, we'll be fine even without a flag image
    (*is_flag_image_used)= 0;
    resulting_sextractor_cl_parameter_string[0]= '\0';
    flag_image_filename[0]= '\0';
    fprintf(stderr, "(There are many zero-value neighbors to a typical zero-value pixel)\nNot creating the flag image after all -- 0.5 > %d/( 2*%d + 1 )^2 = %lf\n", number_of_zeroes_tmp, COUNT_N_PIXELS_AROUND_BAD_ONE, (double)number_of_zeroes_tmp / ((double)(2 * COUNT_N_PIXELS_AROUND_BAD_ONE + 1) * (double)(2 * COUNT_N_PIXELS_AROUND_BAD_ONE + 1)));
    return 0;
   } else {
    fprintf(stderr, "(There are not too many zero-value neighbors to a typical zero-value pixel)\nCreating the flag image -- 0.5 <= %d/( 2*%d + 1 )^2 = %lf\n", number_of_zeroes_tmp, COUNT_N_PIXELS_AROUND_BAD_ONE, (double)number_of_zeroes_tmp / ((double)(2 * COUNT_N_PIXELS_AROUND_BAD_ONE + 1) * (double)(2 * COUNT_N_PIXELS_AROUND_BAD_ONE + 1)));
   }
  } else {
   fprintf(stderr, " ( *is_flag_image_used ) = %d   -- not checking the number of zero neighbors\n", (*is_flag_image_used));
  } // if( 1!=is_flag_image_used ){
 }  // if ( 0 == fits_open_image( &fptr, fitsfilename, READONLY, &status ) ) {

 if( status != 0 ) {
  fprintf(stderr, "WARNING! Cannot open FITS image %s\n", fitsfilename);
  fits_report_error(stderr, status);                 // print any error message
  fits_clear_errmsg();                               // clear the CFITSIO error message stack
  (*is_flag_image_used)= 0;                          // just in case
  resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
  flag_image_filename[0]= '\0';                      // just in case
  return 1;
 }
 /////

 // else ...

 // re-open the image

 //if ( !fits_open_image(&fptr, fitsfilename, READONLY, &status) ){
 if( 0 == fits_open_image(&fptr, fitsfilename, READONLY, &status) ) {

  find_catalog_in_vast_images_catalogs_log(fitsfilename, outfilename_flag);
  outfilename_flag[strlen(outfilename_flag) - 4]= '\0';
  strcat(outfilename_flag, ".flag");
  //
  strcpy(outfilename_weight, outfilename_flag);
  outfilename_weight[strlen(outfilename_weight) - 5]= '\0';
  strcat(outfilename_weight, ".weight");
  //

  fprintf(stderr, "Creating a flag image %s for the input image %s\n", outfilename_flag, fitsfilename);
  fprintf(stderr, "Creating a weight image %s for the input image %s\n", outfilename_weight, fitsfilename);

  // Remove the old flag image with this name if exist
  // Try to stat() the flag file
  if( 0 == stat(outfilename_flag, &sb) ) {
   fprintf(stderr, "Hmm... Found an old flag file %s\n", outfilename_flag);
   // Make sure this is not a directory or some funny file
   if( (sb.st_mode & S_IFMT) != S_IFREG ) {
    fprintf(stderr, "%s is not a regular file or symlink!\nSomething is very-very wrong. Aborting computations.\n", outfilename_flag);
    exit(1);
   }
   // If this is just an old file - delete it.
   fprintf(stderr, "Removing the old flag file %s\n", outfilename_flag);
   unlink(outfilename_flag);
  }
  // Remove the old weight image with this name if exist
  // Try to stat() the flag file
  if( 0 == stat(outfilename_weight, &sb) ) {
   fprintf(stderr, "Hmm... Found an old weight file %s\n", outfilename_weight);
   // Make sure this is not a directory or some funny file
   if( (sb.st_mode & S_IFMT) != S_IFREG ) {
    fprintf(stderr, "%s is not a regular file or symlink!\nSomething is very-very wrong. Aborting computations.\n", outfilename_flag);
    exit(1);
   }
   // If this is just an old file - delete it.
   fprintf(stderr, "Removing the old weight file %s\n", outfilename_weight);
   unlink(outfilename_weight);
  }

  // create the new empty output file for the weight image
  if( 0 != fits_create_file(&outfptr_weight, outfilename_weight, &status) ) {
   fprintf(stderr, "ERROR creating the weight image file %s\n", outfilename_weight);
   exit(1);
  }
  // create the new empty output file if the above checks are OK
  if( 0 == fits_create_file(&outfptr_flag, outfilename_flag, &status) ) {
   fits_create_img(outfptr_flag, BYTE_IMG, 2, naxes, &status);
   fits_create_img(outfptr_weight, BYTE_IMG, 2, naxes, &status);

   pix= (double *)malloc(totpix * sizeof(double)); // memory for the input image
   if( pix == NULL ) {
    fprintf(stderr, "ERROR4: Couldn't allocate memory for pix(guess_saturation_limit.c)\n");
    (*is_flag_image_used)= 0;                          // just in case
    resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
    flag_image_filename[0]= '\0';                      // just in case
    return 1;
   }
   flag= (char *)malloc(totpix * sizeof(char)); // memory for the flag image
   if( flag == NULL ) {
    fprintf(stderr, "ERROR: Couldn't allocate memory for flag(guess_saturation_limit.c)\n");
    (*is_flag_image_used)= 0;                          // just in case
    resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
    flag_image_filename[0]= '\0';                      // just in case
    return 1;
   }
   //
   weight= (char *)malloc(totpix * sizeof(char)); // memory for the flag image
   if( weight == NULL ) {
    fprintf(stderr, "ERROR: Couldn't allocate memory for weight(guess_saturation_limit.c)\n");
    (*is_flag_image_used)= 0;                          // just in case
    resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
    flag_image_filename[0]= '\0';                      // just in case
    return 1;
   }

   fits_read_img(fptr, TDOUBLE, 1, totpix, &nullval, pix, &anynul, &status);
   if( status != 0 ) {
    fprintf(stderr, "WARNING! \n");
    fits_report_error(stderr, status); // print any error message
    fits_clear_errmsg();               // clear the CFITSIO error message stack
    return 1;                          // ???
   }

   //-------------------------------------
   // array index to X Y
   // Y=1+(int)((float)i/(float)naxes[0]);
   // X=i+1-(Y-1)*naxes[0];
   //-------------------------------------
   // X Y to array index
   // i=X-1+(Y-1)*naxes[0];
   //-------------------------------------
   // reset flag values
   for( ii= 0; ii < totpix; ii++ ) {
    flag[ii]= 0;
   }
   // and weight values
   for( ii= 0; ii < totpix; ii++ ) {
    weight[ii]= 1;
   }
   //
   for( ii= 0; ii < totpix; ii++ ) {
    // First consider the special case of an HST image that is mostly zeroes
    if( median == 0.0 && sigma_estimated_from_MAD == 0.0 ) {
     // we want to flag only the exact 0.0 values leaving all positive and negative values unflaged
     if( pix[ii] != 0.0 ) {
      continue;
     }
    } else {
     if( flag_subthreshould_pixels_but_not_zeroes == 0 ) {
      if( pix[ii] != 0.0 && pix[ii] > pixel_value_threshold && pix[ii] > MIN_PIX_VALUE && pix[ii] < MAX_PIX_VALUE ) {
       continue;
      }
     } else {
      if( pix[ii] > pixel_value_threshold && pix[ii] > MIN_PIX_VALUE && pix[ii] < MAX_PIX_VALUE ) {
       continue;
      }
     } // if ( flag_subthreshould_pixels_but_not_zeroes == 0 ) {
    }  // if ( median == 0.0 && sigma_estimated_from_MAD == 0.0 ) {
    ///
    //  Mark as suspicious also FLAG_N_PIXELS_AROUND_BAD_ONE pixels around the bad one
    Y0= 1 + (long)((float)ii / (float)naxes[0]);
    X0= ii + 1 - (Y0 - 1) * naxes[0];
    for( j= -1 * FLAG_N_PIXELS_AROUND_BAD_ONE; j <= FLAG_N_PIXELS_AROUND_BAD_ONE; j++ ) {
     X= X0 + j;
     if( X < 1 )
      continue;
     if( X > naxes[0] )
      continue;
     for( k= -1 * FLAG_N_PIXELS_AROUND_BAD_ONE; k <= FLAG_N_PIXELS_AROUND_BAD_ONE; k++ ) {
      Y= Y0 + k;
      if( Y < 1 )
       continue;
      if( Y > naxes[1] )
       continue;
      l= X - 1 + (Y - 1) * naxes[0];
      flag[l]= 1;
      //
      weight[l]= 0;
      //
     }
    }
    ///
   }
   free(pix);
   fits_write_img(outfptr_flag, TBYTE, 1, totpix, flag, &status);
   fits_write_img(outfptr_weight, TBYTE, 1, totpix, weight, &status);

   //// Handle the situation if we have multiple image HDUs and we want to flag all of them except the first one ////
   fits_get_num_hdus(fptr, &hdunum, &status);
   if( hdunum > 1 ) {
    fprintf(stderr, "WARNING: trying to handle a multiple-HDU image. Sources will be detected only on the first image HDU!\n");
    for( hducounter= 2; hducounter < hdunum; hducounter++ ) {
     // a new IMAGE extension is appended to end of the file following the other HDUs in the file
     fits_create_img(outfptr_flag, BYTE_IMG, 2, naxes, &status);
     fits_write_img(outfptr_flag, TBYTE, 1, totpix, flag, &status);
     //
     fits_create_img(outfptr_weight, BYTE_IMG, 2, naxes, &status);
     fits_write_img(outfptr_weight, TBYTE, 1, totpix, weight, &status);
    }
    status= 0;
   }
   //////////////////////////////////////////////////////////////////////////////////////////////////////////////////

   fits_close_file(outfptr_flag, &status);
   fits_close_file(outfptr_weight, &status);
   free(flag);
   free(weight);
  } // create the new empty output file
  fits_close_file(fptr, &status);
 }

 if( status != 0 ) {
  fits_report_error(stderr, status);                 // print any error message
  fits_clear_errmsg();                               // clear the CFITSIO error message stack
  (*is_flag_image_used)= 0;                          // just in case
  resulting_sextractor_cl_parameter_string[0]= '\0'; // just in case
  flag_image_filename[0]= '\0';                      // just in case
  return 1;
 }

 (*is_flag_image_used)= 1;
 sprintf(resulting_sextractor_cl_parameter_string, "-FLAG_IMAGE %s   -WEIGHT_IMAGE %s  -WEIGHT_TYPE MAP_WEIGHT  ", outfilename_flag, outfilename_weight);
 sprintf(flag_image_filename, "%s", outfilename_flag);
 sprintf(weight_image_filename, "%s", outfilename_weight);

 return 0;
}

// 1 - default saturation level value is found in default.sex
//     will alow the program to change it
// 0 - non-default saturation level value is found in default.sex
//     the program will use the value from default.sex
int check_saturation_limit_in_default_sex(double *out_saturation_level_from_default_sex) {
 double satur_level_in_default_sex;
 int i, j;
 char str1[256];
 FILE *f;
 f= fopen("default.sex", "r");
 if( NULL == f ) {
  fprintf(stderr, "EROR: Can't open file default.sex\n");
  return 1;
 };
 while( NULL != fgets(str1, 256, f) ) {
  str1[255]= '\0'; // just in case
  if( str1[0] == '#' )
   continue;
  if( strlen(str1) < 13 )
   continue;
  for( i= 0; i < (int)strlen(str1) - 13; i++ ) {
   if( str1[i] == '#' )
    break; // go to next line
   if( str1[i] == 'S' && str1[i + 1] == 'A' && str1[i + 2] == 'T' && str1[i + 3] == 'U' && str1[i + 4] == 'R' && str1[i + 5] == '_' && str1[i + 6] == 'L' && str1[i + 7] == 'E' && str1[i + 8] == 'V' && str1[i + 9] == 'E' && str1[i + 10] == 'L' ) {
    // this is our key
    // make sure there is no other stuff written after the key value
    for( j= i + 12; j < (int)strlen(str1) - 13; j++ ) {
     if( str1[j] == '#' ) {
      str1[j]= '\0';
      break;
     }
     if( str1[j] != '0' && str1[j] != '1' && str1[j] != '2' && str1[j] != '3' && str1[j] != '4' && str1[j] != '5' && str1[j] != '6' && str1[j] != '7' && str1[j] != '8' && str1[j] != '9' && str1[j] != '.' && str1[j] != ' ' && str1[j] != '\t' ) {
      str1[j]= '\0';
      break;
     }
    }
    sscanf(str1, "SATUR_LEVEL %lf", &satur_level_in_default_sex);
    (*out_saturation_level_from_default_sex)= satur_level_in_default_sex;
    fclose(f);
    if( satur_level_in_default_sex == 60000.0 ) {
     return 0;
    } else {
     return 1;
    }
   }
  }
 }
 fclose(f);
 return 1;
}

// operation_mode=0 // do nothing
// operation_mode=1 // force the use of satuation limit guessed from images
// operation_mode=2 // try to be clever
int guess_saturation_limit(char *fitsfilename, char *resulting_sextractor_cl_parameter_string, int operation_mode) {

 fitsfile *fptr; // FITS file pointer
 int status= 0;  // CFITSIO status value MUST be initialized to zero!
 int hdutype, naxis, ii;
 //long naxes[2], fpixel[2];
 long naxes[3], fpixel[3]; // we need naxes[3], fpixel[3] to handle 3D cube slice case with dimentions X*Y*1
 double *pix, minval= 1.E33, maxval= -1.E33;

 double guessed_saturation_limit= 0.0;

 double exposure= 0.0;

 double saturation_level_from_default_sex= 0.0;

 char str[256]; // for TSTRING type keys from FITS header

 // do nothing if we don't need to
 if( operation_mode == 0 ) {
  resulting_sextractor_cl_parameter_string[0]= '\0';
  return 0;
 }

 // Check the input
 if( operation_mode < 0 || operation_mode > 2 ) {
  fprintf(stderr, "ERROR: unknown operation_mode=%d (should be 0, 1 or 2)\n", operation_mode);
  return 1;
 }

 if( 0 == fits_open_image(&fptr, fitsfilename, READONLY, &status) ) {

  if( fits_get_hdu_type(fptr, &hdutype, &status) || hdutype != IMAGE_HDU ) {
   fprintf(stderr, "ERROR: this program only works on images, not tables\n");
   //
   fits_report_error(stderr, status); /* print any error message */
   fits_clear_errmsg();               // clear the CFITSIO error message stack
   status= 0;
   fits_close_file(fptr, &status);
   //
   return 1;
  }

  fits_get_img_dim(fptr, &naxis, &status);
  fits_get_img_size(fptr, 2, naxes, &status);

  if( status || naxis != 2 ) {
   if( naxis == 3 ) {
    long naxes3;
    fits_read_key(fptr, TLONG, "NAXIS3", &naxes3, NULL, &status);
    if( naxes3 != 1 ) {
     fprintf(stderr, "ERROR: NAXIS = %d.  Only 2-D images are supported.\n", naxis);
     //
     fits_report_error(stderr, status); /* print any error message */
     fits_clear_errmsg();               // clear the CFITSIO error message stack
     status= 0;
     fits_close_file(fptr, &status);
     //
     return 1;
    }
   } else {
    fprintf(stderr, "ERROR: NAXIS = %d.  Only 2-D images are supported.\n", naxis);
    //
    fits_report_error(stderr, status); /* print any error message */
    fits_clear_errmsg();               // clear the CFITSIO error message stack
    status= 0;
    fits_close_file(fptr, &status);
    //
    return 1;
   }
  }

  // Get exposure time
  fits_read_key(fptr, TDOUBLE, "EXPTIME", &exposure, NULL, &status);
  if( status == 202 ) {
   fits_clear_errmsg(); // clear the CFITSIO error message stack
   status= 0;
   fits_read_key(fptr, TDOUBLE, "EXPOSURE", &exposure, NULL, &status);
   if( status == 202 ) {
    exposure= 0.0;
    fits_clear_errmsg(); // clear the CFITSIO error message stack
    status= 0;
   }
  }

  // Try to play smart here: if the image is small, it is unlikely to have saturated stars on it
  // In that case, revert back to the default SATUR_LEVEL set by user in SExtractor configuration file default.sex
  if( operation_mode == 2 ) {
   if( 1 == check_saturation_limit_in_default_sex(&saturation_level_from_default_sex) ) {
    resulting_sextractor_cl_parameter_string[0]= '\0';
    fprintf(stderr, "The value of saturation limit (SATUR_LEVEL=%.1lf) from default.sex will be used for image %s\nThe above guess is based on the non-default saturation level specified in default.sex by user\n", saturation_level_from_default_sex, fitsfilename);
    //
    fits_report_error(stderr, status); /* print any error message */
    fits_clear_errmsg();               // clear the CFITSIO error message stack
    status= 0;
    fits_close_file(fptr, &status);
    //
    return 0;
   }
   if( naxes[0] < 3000 || naxes[1] < 3000 ) {
    resulting_sextractor_cl_parameter_string[0]= '\0';
    fprintf(stderr, "The value of saturation limit (SATUR_LEVEL=%.1lf) from default.sex will be used for image %s\nThe above guess is based on the small image size of %ldx%ld pix\n", saturation_level_from_default_sex, fitsfilename, naxes[0], naxes[1]);
    //
    fits_report_error(stderr, status); /* print any error message */
    fits_clear_errmsg();               // clear the CFITSIO error message stack
    status= 0;
    fits_close_file(fptr, &status);
    //
    return 0;
   }
   if( exposure > 0.0 && exposure < 15.0 ) {
    resulting_sextractor_cl_parameter_string[0]= '\0';
    fprintf(stderr, "The value of saturation limit (SATUR_LEVEL=%.1lf) from default.sex will be used for image %s\nThe above guess is based on the short exposure time of %.1lf sec\n", saturation_level_from_default_sex, fitsfilename, exposure);
    //
    fits_report_error(stderr, status); /* print any error message */
    fits_clear_errmsg();               // clear the CFITSIO error message stack
    status= 0;
    fits_close_file(fptr, &status);
    //
    return 0;
   }
  }
  //fprintf(stderr,"Guessing saturation limit for %s\n",fitsfilename);

  pix= (double *)malloc(naxes[0] * sizeof(double)); // memory for 1 row
  //pix= (double *)malloc( (naxes[0]+1) * sizeof( double ) ); // memory for 1 row

  if( pix == NULL ) {
   fprintf(stderr, "ERROR5: Couldn't allocate memory for pix(quess_saturation_limit.c)\n");
   //
   fits_report_error(stderr, status); /* print any error message */
   fits_clear_errmsg();               // clear the CFITSIO error message stack
   status= 0;
   fits_close_file(fptr, &status);
   //
   return 1;
  }

  fpixel[0]= 1; /* read starting with first pixel in each row */

  fpixel[2]= 1; // this is needed to handle the X*Y*1 case

  /* process image one row at a time; increment row # in each loop */
  for( fpixel[1]= 1; fpixel[1] <= naxes[1]; fpixel[1]++ ) {
   /* give starting pixel coordinate and number of pixels to read */
   if( fits_read_pix(fptr, TDOUBLE, fpixel, naxes[0], 0, pix, 0, &status) )
    break; /* jump out of loop on error */

   for( ii= 0; ii < naxes[0]; ii++ ) {
    //sum += pix[ii];                      /* accumlate sum */
    if( pix[ii] < minval )
     minval= pix[ii]; /* find min and  */
    if( pix[ii] > maxval )
     maxval= pix[ii]; /* max values    */
   }
  }

  // Special case of HST countrate images
  fits_read_key(fptr, TSTRING, "BUNIT", str, NULL, &status);
  if( status == 0 ) {
   if( 0 == strncmp(str, "ELECTRONS/S", 11) ) {   // HST level 1 (drizzled/resampled images)
    guessed_saturation_limit= 70000.0 / exposure; // The maximum full well depth of the pixels on the WFC3/UVIS chips is ~72500 e-
   }
  }
  status= 0; // we want to continue as usual if BUNIT keyword is not found

  free(pix);
  fits_close_file(fptr, &status);
 }

 if( status != 0 ) {
  fits_report_error(stderr, status); /* print any error message */
  fits_clear_errmsg();               // clear the CFITSIO error message stack
  return 1;
 }

 // if guessed_saturation_limit was not set above
 if( guessed_saturation_limit == 0.0 ) {
  guessed_saturation_limit= maxval - SATURATION_LIMIT_INDENT * maxval;
 } else {
  guessed_saturation_limit= MIN(maxval - SATURATION_LIMIT_INDENT * maxval, guessed_saturation_limit); // take minimmum of the values based on the assumed well depth and on the actually found brightest pixel
 }

 fprintf(stderr, "Guessing that the saturation limit for %s is %.2lf ADU\n", fitsfilename, guessed_saturation_limit);

 // Suggest saturation level based on image pixel values
 sprintf(resulting_sextractor_cl_parameter_string, "-SATUR_LEVEL %.2lf ", guessed_saturation_limit);

 return 0;
}
