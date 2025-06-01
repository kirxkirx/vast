#include "filter_MagSize.h"

#define STOP_IF_FEWER_THAN_THIS_NUMBER_OF_STARS_PER_BIN 10
#define MIN_NUMBER_OF_STARS_IN_BIN 40
#define MAX_NUMBER_OF_STARS_IN_BIN 300
#define BIN_HALFWIDTH_STEP_MAG 0.05
#define MIN_BIN_HALFWIDTH_MAG 0.05

#define NUMBER_OF_REFERENCE_POINTS 500 // There will be no more than NUMBER_OF_REFERENCE_POINTS points along the magnitude axis

#define DO_NOT_APPLY_SIZE_FILTERS_TO_BRIGHTEST_STARS_MAG 0.1                   // do not apply A_IMAGE and FWHM_IMAGE filters to stars                  \
                                                                               // that are less than DO_NOT_APPLY_SIZE_FILTERS_TO_BRIGHTEST_STARS_MAG   \
                                                                               // mags from the bright limit. (Useful for photographic data with having \
                                                                               // a steep mag-size dependence)
#define DO_NOT_APPLY_SIZE_FILTERS_TO_N_BRIGHTEST_STARRS_OR_REFERENCE_POINTS 10 // do not apply A_IMAGE and FWHM_IMAGE filters to stars \
                                                                               // that are brighter than the N reference point

// This function will filter the input SExtractor catalog (already stored in the structure STAR)
// containing NUMBER objects using the SExtractor output parameter (specified by 'parameter_number')
// vs. magnitude plot.
//
// Note that we are not computing the expected parameter values for each star.
// Instead, we compute them for a set of reference points and then
// for each star just use the values corresponding to the nearest reference point.
//
// The overall procedure is the following:
// 1. Set ~NUMBER_OF_REFERENCE_POINTS reference points across the full magnitude range of the catalog.
// 2. For each reference point compute the median value of the parameter using stars that are close in magnitude to the reference point.
// 3. For each star subtract the median parameter value associated with the nearest reference point.
// 4. For each reference point compute the MAD scaled to sigma of the median-subtracted value of the parameter using stars that are close in magnitude to that reference point.
//
// Silly enough, this function takes input data from different fields of the STAR structure
// depending on the input value 'parameter_number':
//
//  -2 -- mag - PSF chi^2 filter
//  -1 -- mag - A_IMAGE filter
// >=0 -- mag - parameter[] filter
//
// (the idea is, of course, to have the unified filtering procedure for all the filtering parameters)
//
// sextractor_catalog - is the catalog filename to generate names of the corresponding log files.
//

int filter_on_float_parameters( struct Star *STAR, int NUMBER, char *sextractor_catalog, int parameter_number ) {
 int i, j, k; // counters

 //
 float *reference_point_mag;
 float *reference_point_float_parameter;
 float *reference_point_float_parameter_sigma;
 //
 float reference_point_mag_brightest, reference_point_mag_faintest, reference_point_mag_step;
 int number_of_reference_points;
 float distance_to_the_nearest_reference_point;
 int index_of_the_nearest_reference_point;

 float *median_subtracted_float_parameter_for_each_star;
 float reference_point_halfbinwidth[NUMBER_OF_REFERENCE_POINTS];

 float *mag_diff;
 float *mag_diff_float_parameter;
 float float_mag_diff;
 float mag_bin_halfwidth;

 float float_parameter_value_for_STAR;

 float median_float_parameter;
 float float_parameter_sigma;

 float float_parameter_min= -1.0e16; // some very small number by default
 float float_parameter_max= 1.0e16;  // some very large number by default

 int flagged_stars_counter= 0;

 int iteration;

 float threshold_sigma;

 short vast_flag_to_set= 9999; // default crazy value

 int min_number_of_points_in_mag_bin;

#ifndef DISABLE_MAGSIZE_FILTER_LOGS
 char thresholdcurvefilename[512];
 char passedfilename[512];
 char rejectedfilename[512];

 FILE *debugfile_thresholdcurve;
 FILE *debugfile_passed;
 FILE *debugfile_rejected;
#endif

 // Set the cut-off threshold depending on the number of sources detected on the image
 /// https://en.wikipedia.org/wiki/68%E2%80%9395%E2%80%9399.7_rule
 // threshold_sigma=sqrt(2)*erfinv(1-2*0.0003/NUMBER);
 // threshold_sigma=sqrt(2)*erfinv(1-2*0.0002/NUMBER);
 threshold_sigma= sqrt( 2 ) * erfinv( 1 - 2 * 0.0001 / NUMBER );
 // sqrt(2)*erfinv(1-2*0.0003/100)=4.5264
 // sqrt(2)*erfinv(1-2*0.0003/1000)=4.9912
 // sqrt(2)*erfinv(1-2*0.0003/10000)=5.4188
 /*
 threshold_sigma= 4.0;
 if ( NUMBER > 100 )
  threshold_sigma= 4.5;
 if ( NUMBER > 1000 )
  threshold_sigma= 5.0;
 if ( NUMBER > 10000 )
  threshold_sigma= 5.5;
*/

 if ( parameter_number < -2 ) {
  fprintf( stderr, "ERROR in filter_on_float_parameters(): parameter_number is out of range!\n" );
  return 0;
 }

 min_number_of_points_in_mag_bin= MIN( MIN_NUMBER_OF_STARS_IN_BIN, (int)( (float)NUMBER / 3.0 ) + 0.5 );
 if ( min_number_of_points_in_mag_bin < STOP_IF_FEWER_THAN_THIS_NUMBER_OF_STARS_PER_BIN ) {
  fprintf( stderr, "ERROR in filter_on_float_parameters(): too few stars per magnitude bin to perform filtering!\n" );
  return 0;
 }

 if ( parameter_number == -2 ) {
  vast_flag_to_set= 2; // PSF-fit chi^2
  float_parameter_min= 0.0;
  float_parameter_max= 1.0e16; // some very large number by default
 }
 if ( parameter_number == -1 ) {
  vast_flag_to_set= 4; // A_IMAGE
  float_parameter_min= 0.0;
  float_parameter_max= 1.0e16; // some very large number by default
  if ( parameter_number == -1 )
   threshold_sigma= 2.0 * threshold_sigma; // want to relax the threshold -- red stars appear bigger on refractor images
                                           // also see MAG_AUTO below
                                           // This is based on the test:
                                           // ./vast --failsafe -u --selectbestaperture /mnt/usb/TCPJ00114297+6611190/Stas/2020-08-07_NCas/fd_2020-08-07_NCas_30sec_H_-15C_0*
 }
 if ( parameter_number == 0 ) {
  vast_flag_to_set= 8; // FWHM_IMAGE
  float_parameter_min= FWHM_MIN;
  float_parameter_max= 1.0e16; // some very large number by default
  if ( parameter_number == 0 )
   threshold_sigma= 0.9 * threshold_sigma; // especially useful parameter for rejecting blends, so
                                           // I want to lower the threshould for this one
 }
 if ( parameter_number >= 1 ) {
  vast_flag_to_set= 16; // MAG_AUTO
  float_parameter_min= -1.0 * MAX_MAG_ERROR;
  float_parameter_max= 1.0e16; // some very large number by default -- canot have small number here -- pho photographic data the difference may be pretty huge
  // don't want to set a hard limit here as for the fainter objects MAG_AUTO is not well defined
  if ( parameter_number == 1 )
   threshold_sigma= 2.0 * threshold_sigma; // want to relax the threshould -- red stars appear bigger on refractor images
 }
 if ( parameter_number >= 2 ) {
  vast_flag_to_set= 32;         // PSF-APER MAG diff
  float_parameter_min= -1.0e16; // some very small number by default
  float_parameter_max= 1.0e16;  // some very large number by default
 }
 if ( parameter_number >= 4 ) {
  vast_flag_to_set= 64;         // MAG diff
  float_parameter_min= -1.0e16; // think of the overexposed core
  // 2.5*log10( (1.0+(AP01))*(1.0+(AP01)) ); // 2.5*log10( (1.0+(AP01))*(1.0+(AP01)) ) - magnitude difference for a uniform extended source
  float_parameter_max= -0.01;
 }
 if ( parameter_number >= 6 ) {
  vast_flag_to_set= 128; // MAG diff
  float_parameter_min= 0.01;
  float_parameter_max= 2.5 * log10( ( 1.0 + ( AP02 ) ) * ( 1.0 + ( AP02 ) ) ); //
 }
 if ( parameter_number >= 8 ) {
  vast_flag_to_set= 256; // MAG diff
  float_parameter_min= 0.01;
  float_parameter_max= 2.5 * log10( ( 1.0 + ( AP03 ) ) * ( 1.0 + ( AP03 ) ) ); // may be large for photographic plates
 }
 if ( parameter_number >= 10 ) {
  vast_flag_to_set= 512; // MAG diff
  float_parameter_min= 0.01;
  float_parameter_max= 2.5 * log10( ( 1.0 + ( AP04 ) ) * ( 1.0 + ( AP04 ) ) ); // may be large for photographic plates
 }
 if ( parameter_number >= 12 ) {
  vast_flag_to_set= 1024; // A_IMAGE/B_IMAGE
  float_parameter_min= 1.0;
  float_parameter_max= 1.0e16; // some very large number
  if ( parameter_number == 12 )
   threshold_sigma= 2.0 * threshold_sigma; // increase threshould!
                                           // The sigma we have is not the real sigma, but 1.4826*MAD
                                           // and that makes a HUGE difference for the A_IMAGE/B_IMAGE ratio
 }
 if ( parameter_number > 12 ) {
  vast_flag_to_set= 2048;       //
  float_parameter_min= -1.0e16; // some very small number by default
  float_parameter_max= 1.0e16;  // some very large number by default
 }

 //
 reference_point_mag= malloc( NUMBER_OF_REFERENCE_POINTS * sizeof( float ) );
 reference_point_float_parameter= malloc( NUMBER_OF_REFERENCE_POINTS * sizeof( float ) );
 reference_point_float_parameter_sigma= malloc( NUMBER_OF_REFERENCE_POINTS * sizeof( float ) );
 //

 // Set the reference points
 if ( NUMBER < NUMBER_OF_REFERENCE_POINTS ) {
  // Just set the reference points where the stars are
  number_of_reference_points= NUMBER;
  for ( i= 0; i < number_of_reference_points; i++ ) {
   reference_point_mag[i]= STAR[i].mag;
  }
  // now we need to sort reference_point_mag[] so reference_point_mag[0] is always the brightest star
  gsl_sort_float( reference_point_mag, 1, number_of_reference_points );
 } else {
  // Uniformly distribute the reference points across the whole magnitude range
  reference_point_mag_brightest= reference_point_mag_faintest= STAR[0].mag; // yes, we have to be pretty sure STAR[0].mag is not 99.99 or something
  for ( i= 0; i < NUMBER; i++ ) {
   if ( STAR[i].mag < reference_point_mag_brightest )
    reference_point_mag_brightest= STAR[i].mag;
   if ( STAR[i].mag > reference_point_mag_faintest )
    reference_point_mag_faintest= STAR[i].mag;
  }
  number_of_reference_points= NUMBER_OF_REFERENCE_POINTS;
  reference_point_mag_step= ( reference_point_mag_faintest - reference_point_mag_brightest ) / (double)number_of_reference_points;
  // fprintf(stderr,"DEBUG: setting %d reference points between %lf and %lf step %lf mag\n",number_of_reference_points,reference_point_mag_brightest,reference_point_mag_faintest,reference_point_mag_step);
  reference_point_mag[0]= reference_point_mag_brightest;
  for ( i= 1; i < number_of_reference_points; i++ ) {
   reference_point_mag[i]= reference_point_mag[i - 1] + reference_point_mag_step;
  } // for(i=0;i<number_of_reference_points;i++){
 } // if( NUMBER<NUMBER_OF_REFERENCE_POINTS ){

#ifndef DISABLE_MAGSIZE_FILTER_LOGS
 // Set the log file names
 if ( parameter_number == -2 ) {
  sprintf( thresholdcurvefilename, "%s.magpsfchi2filter_thresholdcurve", sextractor_catalog );
  sprintf( passedfilename, "%s.magpsfchi2filter_passed", sextractor_catalog );
  sprintf( rejectedfilename, "%s.magpsfchi2filter_rejected", sextractor_catalog );
 }
 if ( parameter_number == -1 ) {
  sprintf( thresholdcurvefilename, "%s.magsizefilter_thresholdcurve", sextractor_catalog );
  sprintf( passedfilename, "%s.magsizefilter_passed", sextractor_catalog );
  sprintf( rejectedfilename, "%s.magsizefilter_rejected", sextractor_catalog );
 }
 if ( parameter_number >= 0 ) {
  sprintf( thresholdcurvefilename, "%s.magparameter%02dfilter_thresholdcurve", sextractor_catalog, parameter_number );
  sprintf( passedfilename, "%s.magparameter%02dfilter_passed", sextractor_catalog, parameter_number );
  sprintf( rejectedfilename, "%s.magparameter%02dfilter_rejected", sextractor_catalog, parameter_number );
 }

 // open the log file which will store the cut-off curve
 debugfile_thresholdcurve= fopen( thresholdcurvefilename, "w" );
#endif
 //

 fprintf( stderr, "Applying mag-size filter to %s filtering on parameter %d (see src/filter_MagSize.c)\n", sextractor_catalog, parameter_number );

 // Make two iterations so the stars that are just on the edge of being rejected go over that edge
 for ( iteration= 0; iteration < 2; iteration++ ) {

  // Set reference_point_float_parameter for each reference_point

#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel private( i, mag_diff, mag_diff_float_parameter, k, j, float_mag_diff, median_float_parameter, mag_bin_halfwidth, float_parameter_sigma, float_parameter_value_for_STAR )
#endif
#endif
  {
   mag_diff= malloc( NUMBER * sizeof( float ) );
   mag_diff_float_parameter= malloc( NUMBER * sizeof( float ) );
/*
  #ifdef VAST_ENABLE_OPENMP
   #ifdef _OPENMP
    #pragma omp parallel for private(i,mag_diff,mag_diff_float_parameter,k,j,float_mag_diff,median_float_parameter,mag_bin_halfwidth,float_parameter_sigma,float_parameter_value_for_STAR)
   #endif
  #endif
  */
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp for
#endif
#endif
   for ( i= 0; i < number_of_reference_points; i++ ) {
    // mag_diff=malloc(NUMBER*sizeof(float));
    // mag_diff_float_parameter=malloc(NUMBER*sizeof(float));

    // Tune bin half-width
    mag_bin_halfwidth= MIN_BIN_HALFWIDTH_MAG;
    k= 0; // seed value to start the iterations
    while ( k < min_number_of_points_in_mag_bin ) {
     mag_bin_halfwidth= mag_bin_halfwidth + BIN_HALFWIDTH_STEP_MAG;
     k= 0; // reset
     // Check every star to find the nearby ones (in magnitude)
     for ( j= 0; j < NUMBER; j++ ) {
      // The stept that is most likely to end up in 'continue' goes first
      // check if the srar STAR[j] is within the bin
      float_mag_diff= fabsf( reference_point_mag[i] - STAR[j].mag );
      if ( float_mag_diff > mag_bin_halfwidth )
       continue;
      //
      if ( STAR[j].vast_flag >= vast_flag_to_set )
       continue; // trying to keep the filters reasonably independent
      if ( STAR[j].sextractor_flag > 7 )
       continue; // discard stars with scary SExtractor flags
      // That's for the batter compatibility with the old filter that had reference points always have the same magnitude as stars
      // (and we rejected the star istself from the median parameter value calculation)
      if ( number_of_reference_points == NUMBER ) {
       // if( i==j ){
       //  can't do this anymore as we have to sort reference_point_mag[]
       //  so instead of the array index - compare the magnitudes
       if ( float_mag_diff == 0.0 ) {
        continue; // discard the same star
       }
      }
      //
      mag_diff[k]= float_mag_diff;
      ///
      float_parameter_value_for_STAR= 0.0; // reset just in case
      //
      if ( parameter_number == -2 ) {
       float_parameter_value_for_STAR= STAR[j].star_psf_chi2;
      }
      if ( parameter_number == -1 ) {
       float_parameter_value_for_STAR= STAR[j].star_size;
      }
      if ( parameter_number >= 0 ) {
       float_parameter_value_for_STAR= STAR[j].float_parameters[parameter_number];
      }
      mag_diff_float_parameter[k]= float_parameter_value_for_STAR;
      k++;
     } // for(j=0;j<NUMBER;j++){
     if ( mag_bin_halfwidth > 20.0 ) {
      fprintf( stderr, "\n\n\nERROR in filter_on_float_parameters(%d): encountered a suspiciously large bin width > 20 mag\n", parameter_number );
      fprintf( stderr, "Center of the failed bin: %f mag  k=%d\n", reference_point_mag[i], k );
      fprintf( stderr, "min_number_of_points_in_mag_bin=%d\n", min_number_of_points_in_mag_bin );
      fprintf( stderr, "MIN_NUMBER_OF_STARS_IN_BIN=%d (double)NUMBER=%lf (double)NUMBER/3.0=%lf\n\n\n", MIN_NUMBER_OF_STARS_IN_BIN, (double)NUMBER, (double)NUMBER / 3.0 );
      // this is not suppose to happen, but sometimes it does
      // exit(1);
      break; // we cannot just return from inside omp parallel
     }
    } // while( k<20 ){
    reference_point_halfbinwidth[i]= mag_bin_halfwidth;

    gsl_sort2_float( mag_diff, 1, mag_diff_float_parameter, 1, k );
    // free(mag_diff);
    k= MIN( k, MAX_NUMBER_OF_STARS_IN_BIN );
    gsl_sort_float( mag_diff_float_parameter, 1, k );
    median_float_parameter= gsl_stats_float_median_from_sorted_data( mag_diff_float_parameter, 1, k );
    reference_point_float_parameter[i]= median_float_parameter;
    ///
    // free(mag_diff_float_parameter);
   }

   free( mag_diff );
   free( mag_diff_float_parameter );
  } // #pragma omp parallel

  // Check if a binning error was encountered
  for ( i= 0; i < number_of_reference_points; i++ ) {
   if ( reference_point_halfbinwidth[i] > 20.0 ) {
    fprintf( stderr, "Binning error in filter_on_float_parameters(%d)\n\n", parameter_number );
    return 0;
   }
  }

  // For each star compute the median-subtracted float_parameter and store this value in median_subtracted_float_parameter_for_each_star[i]
  median_subtracted_float_parameter_for_each_star= malloc( NUMBER * sizeof( float ) );
  if ( NULL == median_subtracted_float_parameter_for_each_star ) {
   fprintf( stderr, "ERROR: cannot allocate median_subtracted_float_parameter_for_each_star\n" );
   exit( EXIT_FAILURE );
  }
// for each star
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i, distance_to_the_nearest_reference_point, j, float_mag_diff, index_of_the_nearest_reference_point )
#endif
#endif
  for ( i= 0; i < NUMBER; i++ ) {
   distance_to_the_nearest_reference_point= 10.0;
   index_of_the_nearest_reference_point= number_of_reference_points; // reset
   for ( j= 0; j < number_of_reference_points; j++ ) {
    float_mag_diff= fabsf( reference_point_mag[j] - STAR[i].mag );
    if ( float_mag_diff < distance_to_the_nearest_reference_point ) {
     distance_to_the_nearest_reference_point= float_mag_diff;
     index_of_the_nearest_reference_point= j;
    }
   }
   if ( index_of_the_nearest_reference_point == number_of_reference_points ) {
    fprintf( stderr, "ERROR in filter_on_float_parameters() cannot find the nearest reference point!\n" );
    exit( EXIT_FAILURE );
   }
   float_parameter_value_for_STAR= 0.0; // reset to make the compiler happy
   if ( parameter_number == -2 ) {
    float_parameter_value_for_STAR= STAR[i].star_psf_chi2;
   }
   if ( parameter_number == -1 ) {
    float_parameter_value_for_STAR= STAR[i].star_size;
   }
   if ( parameter_number >= 0 ) {
    float_parameter_value_for_STAR= STAR[i].float_parameters[parameter_number];
   }
   median_subtracted_float_parameter_for_each_star[i]= float_parameter_value_for_STAR - reference_point_float_parameter[index_of_the_nearest_reference_point];
  }
// For each reference point set float_parameter_sigma using median_subtracted_float_parameter_for_each_star
// Set reference_point_float_parameter for each reference_point
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i, mag_diff, mag_diff_float_parameter, k, j, float_mag_diff, median_float_parameter, float_parameter_sigma )
#endif
#endif
  for ( i= 0; i < number_of_reference_points; i++ ) {
   mag_diff= malloc( NUMBER * sizeof( float ) );
   mag_diff_float_parameter= malloc( NUMBER * sizeof( float ) );

   // Tune bin half-width
   mag_bin_halfwidth= reference_point_halfbinwidth[i]; // mag_bin_halfwidth+BIN_HALFWIDTH_STEP_MAG;
   k= 0;                                               // reset
   // Check every star to find the nearby ones (in magnitude)
   for ( j= 0; j < NUMBER; j++ ) {
    // again, this one is most likely to end up in 'continue', so this test goes first
    float_mag_diff= fabsf( reference_point_mag[i] - STAR[j].mag );
    if ( float_mag_diff > mag_bin_halfwidth )
     continue;
    //
    if ( STAR[j].vast_flag >= vast_flag_to_set )
     continue; // trying to keep the filters reasonably independent
    if ( STAR[j].sextractor_flag > 7 )
     continue; // discard stars with scary SExtractor flags
    // That's for the batter compatibility with the old filter
    if ( number_of_reference_points == NUMBER ) {
     if ( i == j ) {
      continue; // discard the same star
     }
    }
    //
    mag_diff[k]= float_mag_diff;
    mag_diff_float_parameter[k]= median_subtracted_float_parameter_for_each_star[j];
    k++;
   } // for(j=0;j<NUMBER;j++){

   gsl_sort2_float( mag_diff, 1, mag_diff_float_parameter, 1, k );
   free( mag_diff );
   k= MIN( k, MAX_NUMBER_OF_STARS_IN_BIN );
   gsl_sort_float( mag_diff_float_parameter, 1, k );
   // set a lower limit on float_parameter_sigma ??
   float_parameter_sigma= esimate_sigma_from_MAD_of_sorted_data_float( mag_diff_float_parameter, k );

   reference_point_float_parameter_sigma[i]= float_parameter_sigma;
   ///
   free( mag_diff_float_parameter );
   //
  }
  // done with median_subtracted_float_parameter_for_each_star
  free( median_subtracted_float_parameter_for_each_star );

  // Smooth the threshold curve
  for ( i= 2; i < number_of_reference_points - 2; i++ ) {
   reference_point_mag[i]= ( reference_point_mag[i - 2] + reference_point_mag[i - 1] + reference_point_mag[i] + reference_point_mag[i + 1] + reference_point_mag[i + 2] ) / 5.0;
   reference_point_float_parameter_sigma[i]= ( reference_point_float_parameter_sigma[i - 2] + reference_point_float_parameter_sigma[i - 1] + reference_point_float_parameter_sigma[i] + reference_point_float_parameter_sigma[i + 1] + reference_point_float_parameter_sigma[i + 2] ) / 5.0;
  }

#ifndef DISABLE_MAGSIZE_FILTER_LOGS
  if ( iteration == 1 ) {
   for ( i= 0; i < number_of_reference_points; i++ ) {
    fprintf( debugfile_thresholdcurve, "%f %g %g\n", reference_point_mag[i], reference_point_float_parameter[i], reference_point_float_parameter_sigma[i] );
   }
  }
#endif

// for each star
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i, distance_to_the_nearest_reference_point, j, float_mag_diff, index_of_the_nearest_reference_point, float_parameter_value_for_STAR ) reduction( + : flagged_stars_counter )
#endif
#endif
  for ( i= 0; i < NUMBER; i++ ) {
   // The brightes stars should not be droped in some tests!
   // If this is A_IMAGE or FWHM_IMAGE vs. mag test
   // if( parameter_number==-1 || parameter_number==0 ){
   // TEST WITH THE PSF THING
   if ( parameter_number == -2 || parameter_number == -1 || parameter_number == 0 ) {
    if ( fabsf( reference_point_mag[0] - STAR[i].mag ) < DO_NOT_APPLY_SIZE_FILTERS_TO_BRIGHTEST_STARS_MAG )
     continue;
    if ( STAR[i].mag < reference_point_mag[DO_NOT_APPLY_SIZE_FILTERS_TO_N_BRIGHTEST_STARRS_OR_REFERENCE_POINTS] )
     continue;
   }
   // Reset the best distance
   distance_to_the_nearest_reference_point= 10.0;
   index_of_the_nearest_reference_point= number_of_reference_points;
   for ( j= 0; j < number_of_reference_points; j++ ) {
    float_mag_diff= fabsf( reference_point_mag[j] - STAR[i].mag );
    if ( float_mag_diff < distance_to_the_nearest_reference_point ) {
     distance_to_the_nearest_reference_point= float_mag_diff;
     index_of_the_nearest_reference_point= j;
    }
   }
   if ( number_of_reference_points == index_of_the_nearest_reference_point ) {
    fprintf( stderr, "ERROR in filter_on_float_parameters() cannot find the nearest reference point!\n" );
    exit( EXIT_FAILURE );
   }
   float_parameter_value_for_STAR= 0.0; // reset just in case
   // Check if the star is too large/small for its magnitude
   if ( parameter_number == -2 ) {
    float_parameter_value_for_STAR= STAR[i].star_psf_chi2;
   }
   if ( parameter_number == -1 ) {
    float_parameter_value_for_STAR= STAR[i].star_size;
   }
   if ( parameter_number >= 0 ) {
    float_parameter_value_for_STAR= STAR[i].float_parameters[parameter_number];
   }
   if ( fabsf( reference_point_float_parameter[index_of_the_nearest_reference_point] - float_parameter_value_for_STAR ) > threshold_sigma * reference_point_float_parameter_sigma[index_of_the_nearest_reference_point] ) {
    if ( STAR[i].vast_flag == 0 ) {
     flagged_stars_counter++;
    } // update counter only if the star was not flagged earlier
    if ( STAR[i].vast_flag < vast_flag_to_set ) {
     STAR[i].vast_flag+= vast_flag_to_set;
    } // otherwise assume it is set already at the previous iteration
    continue;
   }
   // Check hard limits only for the stars that are not in the main cloud
   if ( fabs( reference_point_float_parameter[index_of_the_nearest_reference_point] - float_parameter_value_for_STAR ) > 3.0 * reference_point_float_parameter_sigma[index_of_the_nearest_reference_point] ) {
    // Check the hard limits
    if ( float_parameter_value_for_STAR < float_parameter_min ) {
     if ( STAR[i].vast_flag == 0 )
      flagged_stars_counter++; // update counter only if the star was not flagged earlier
     if ( STAR[i].vast_flag < vast_flag_to_set )
      STAR[i].vast_flag+= vast_flag_to_set; // otherwise assume it is set already at the previous iteration
    }
    if ( float_parameter_value_for_STAR > float_parameter_max ) {
     if ( STAR[i].vast_flag == 0 )
      flagged_stars_counter++; // update counter only if the star was not flagged earlier
     if ( STAR[i].vast_flag < vast_flag_to_set )
      STAR[i].vast_flag+= vast_flag_to_set; // otherwise assume it is set already at the previous iteration
    }
   }
   //
  }

 } // for(iteration=0;iteration<2;iteration++{
#ifndef DISABLE_MAGSIZE_FILTER_LOGS
 fclose( debugfile_thresholdcurve );
#endif

 //
 free( reference_point_mag );
 free( reference_point_float_parameter );
 free( reference_point_float_parameter_sigma );
 //

#ifndef DISABLE_MAGSIZE_FILTER_LOGS
 // Write the log files
 debugfile_passed= fopen( passedfilename, "w" );
 if ( debugfile_passed == NULL ) {
  fprintf( stderr, "ERROR in filter_Magfloat_parameter(): cannot open %s for writing!\n", passedfilename );
  return flagged_stars_counter;
 }
 debugfile_rejected= fopen( rejectedfilename, "w" );
 if ( debugfile_rejected == NULL ) {
  fprintf( stderr, "ERROR in filter_Magfloat_parameter(): cannot open %s for writing!\n", rejectedfilename );
  return flagged_stars_counter;
 }
 for ( i= 0; i < NUMBER; i++ ) {
  float_parameter_value_for_STAR= 0.0; // reset just in case
  if ( parameter_number == -2 ) {
   float_parameter_value_for_STAR= STAR[i].star_psf_chi2;
  }
  if ( parameter_number == -1 ) {
   float_parameter_value_for_STAR= STAR[i].star_size;
  }
  if ( parameter_number >= 0 ) {
   float_parameter_value_for_STAR= STAR[i].float_parameters[parameter_number];
  }
  // THIS HAS TO MATCH THE FLAG VALUE SET ABOVE!!!!
  // (otherwise the output in the debug files will be messed-up)
  if ( STAR[i].vast_flag >= vast_flag_to_set ) {
   // fprintf(debugfile_rejected,"%lf %lg  %d\n",STAR[i].mag,STAR[i].float_parameters[parameter_number],STAR[i].n);
   fprintf( debugfile_rejected, "%f %g  %d\n", STAR[i].mag, float_parameter_value_for_STAR, STAR[i].n );
  } else {
   fprintf( debugfile_passed, "%f %g  %d\n", STAR[i].mag, float_parameter_value_for_STAR, STAR[i].n );
  }
 }
 fclose( debugfile_passed );
 fclose( debugfile_rejected );
//
#endif

 return flagged_stars_counter;
}
