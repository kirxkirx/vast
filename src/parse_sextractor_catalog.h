// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_PARSE_SEXTRACTOR_CATALOG_H

#include <stdio.h>
#include <string.h>

static inline int parse_sextractor_catalog_string( char *input_sextractor_catalog_string,
                                                   int *star_number_in_sextractor_catalog,
                                                   double *flux_adu,
                                                   double *flux_adu_err,
                                                   double *mag,
                                                   double *sigma_mag,
                                                   double *position_x_pix,
                                                   double *position_y_pix,
                                                   double *a_a, // semi-major axis lengths
                                                   double *a_a_err,
                                                   double *a_b, // semi-minor axis lengths
                                                   double *a_b_err,
                                                   int *sextractor_flag,
                                                   int *external_flag,
                                                   double *psf_chi2,
                                                   float *float_parameters_array_output ) {

 char external_flag_string[256];
 double double_external_flag;
 int ii, jj; // for SExtractor catalog parsing

 float float_parameters_internalcopy[NUMBER_OF_FLOAT_PARAMETERS];

 ( *external_flag )= 0;
 external_flag_string[0]= '\0';

 //if( 14>sscanf(input_sextractor_catalog_string, "%d %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %d  %f %f  %[^\t\n]", star_number_in_sextractor_catalog, flux_adu, flux_adu_err, mag, sigma_mag, position_x_pix, position_y_pix, a_a, a_a_err, a_b, a_b_err, sextractor_flag, &float_parameters_internalcopy[0], &float_parameters_internalcopy[1],  external_flag_string) ){
 if ( 24 > sscanf( input_sextractor_catalog_string, "%d %lf %lf %lf %f %f %f %f %f %lf %f %f %f %f %f  %lf %lf %lf %lf %lf %lf %d  %f %f  %[^\t\n]",
                   //                                                     -0.2  -0.1  -0.0  +0.1  +0.2
                   star_number_in_sextractor_catalog,
                   flux_adu,
                   flux_adu_err,
                   mag,                                // reference aperture or PSF-fitting magnitude
                   &float_parameters_internalcopy[2],  // aper+0.0*aper -- reference aperture (yes, again if PSF-fitting mode is off)
                   &float_parameters_internalcopy[4],  // aper-0.2*aper
                   &float_parameters_internalcopy[6],  // aper-0.1*aper
                   &float_parameters_internalcopy[8],  // aper+0.1*aper
                   &float_parameters_internalcopy[10], // aper+0.2*aper
                   sigma_mag,                          // error of the reference aperture or PSF-fitting magnitude
                   &float_parameters_internalcopy[3],  // aper+0.0*aper err -- reference aperture error
                   &float_parameters_internalcopy[5],  // aper-0.2*aper err
                   &float_parameters_internalcopy[7],  // aper-0.1*aper err
                   &float_parameters_internalcopy[9],  // aper+0.1*aper err
                   &float_parameters_internalcopy[11], // aper+0.2*aper err
                   position_x_pix,
                   position_y_pix,
                   a_a,
                   a_a_err,
                   a_b,
                   a_b_err,
                   sextractor_flag,
                   &float_parameters_internalcopy[0], // FWHM
                   &float_parameters_internalcopy[1], // Mag-Auto
                   external_flag_string ) ) {
  //fprintf(stderr,"WARNING: problem occurred while parsing SExtractor catalog %s\nThe offending line is:\n%s\n",sextractor_catalog,input_sextractor_catalog_string);
  return 1;
 }

// filter-out some outlandish measurements here
// Specifically, if the measurement in one apeture is bad - assume all other apertures are unreliable too
#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
#ifdef VAST_USE_BUILTIN_FUNCTIONS
// Make a proper check the input values if isnormal() is defined
#if defined _ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L
 // We use __builtin_isnormal() as we know it is working if VAST_USE_BUILTIN_FUNCTIONS is defined
 // Othervise even with the '_ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L' check
 // isnormal() doesn't work on Ubuntu 14.04 trusty (vast.sai.msu.ru)
 // BEWARE 0.0 is also not considered normal by isnormal() !!!

 if ( 0 == __builtin_isnormal( ( *mag ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( float_parameters_internalcopy[2] ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( float_parameters_internalcopy[4] ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( float_parameters_internalcopy[6] ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( float_parameters_internalcopy[8] ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( float_parameters_internalcopy[10] ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( *sigma_mag ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( float_parameters_internalcopy[3] ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( float_parameters_internalcopy[5] ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( float_parameters_internalcopy[7] ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( float_parameters_internalcopy[9] ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( float_parameters_internalcopy[11] ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( *a_a ) ) ) {
  return 1;
 }
 if ( 0 == __builtin_isnormal( ( *a_b ) ) ) {
  return 1;
 }
 //if( 0==__builtin_isnormal( (float_parameters_internalcopy[0]) ) ){return 1;} // FWHM can be zero! %(

#endif
#endif

 // The magnitude check is done outside this function in order to keep track of the counters
#endif
 //

 if ( NULL != float_parameters_array_output ) {
  float_parameters_internalcopy[1]= float_parameters_internalcopy[2] - float_parameters_internalcopy[1]; // MAG_AUTO
  float_parameters_internalcopy[4]= float_parameters_internalcopy[2] - float_parameters_internalcopy[4];
  float_parameters_internalcopy[6]= float_parameters_internalcopy[2] - float_parameters_internalcopy[6];
  float_parameters_internalcopy[8]= float_parameters_internalcopy[2] - float_parameters_internalcopy[8];
  float_parameters_internalcopy[10]= float_parameters_internalcopy[2] - float_parameters_internalcopy[10];
  float_parameters_internalcopy[2]= (float)( *mag ) - float_parameters_internalcopy[2]; // now this should be the last one as the other parameters use the reference aperture mag stored in float_parameters_internalcopy[2]
  // New
  float_parameters_internalcopy[12]= (float)( ( *a_a ) / ( *a_b ) ); // inverse elongation
  //
  for ( ii= NUMBER_OF_FLOAT_PARAMETERS; ii--; ) {
   float_parameters_array_output[ii]= float_parameters_internalcopy[ii];
  }
 }

 // Now this is some crazy stuff:
 // The last columns of the SExtractor catalog file might be:
 // ... flags
 // ... flags external_flags
 // ... flags external_flags psf_fitting_chi2
 // ... flags psf_fitting_chi2
 // Below we try to handle each of the four possibilities
 //
 // if these are not just flags
 // (but make sure we perform the tese only on a line with a good measurement)
 if ( strlen( external_flag_string ) > 0 && ( *flux_adu ) > 0.0 && ( *mag ) != 99.0000 ) {
  // if these are not "Mag-Auto external_flags psf_fitting_chi2"
  if ( 2 != sscanf( external_flag_string, "%lf %lf", &double_external_flag, psf_chi2 ) ) {
   // Decide between "Mag-Auto external_flags" and "flags psf_fitting_chi2"
   for ( ii= 0, jj= 0; ii < (int)strlen( external_flag_string ); ii++ ) {
    if ( external_flag_string[ii] == '.' || external_flag_string[ii] == 'e' ) {
     jj= 1;
     break;
    } // assume that a decimal point indicates psf_chi2 rather than external_flag that is expe
   }
   if ( jj == 0 ) {
    // "Mag-Auto external_flags" case
    ( *psf_chi2 )= 1.0; // no PSF fitting results
    if ( 1 != sscanf( external_flag_string, "%lf", &double_external_flag ) ) {
     double_external_flag= 0.0; // no external flag image used
    }
   } else {
    // "Mag-Auto psf_fitting_chi2" case
    double_external_flag= 0.0; // no external flag image used
    if ( 1 != sscanf( external_flag_string, "%lf", psf_chi2 ) ) {
     ( *psf_chi2 )= 1.0; // no PSF fitting results
    }
   }
  } // if( 2!=sscanf(external_flag_string,"%lf %lf",&double_external_flag,&psf_chi2) ){
  ( *external_flag )= (int)double_external_flag;
 } else {
  ( *psf_chi2 )= 1.0;    // no PSF fitting results
  ( *external_flag )= 0; // no external flag image used
 }
 // End of crazy stuff!

 return 0;
}

// The macro below will tell the pre-processor that this header file is already included
#define VAST_PARSE_SEXTRACTOR_CATALOG_H
#endif
// VAST_PARSE_SEXTRACTOR_CATALOG_H
