// This files provides a common interfice for lightcurve input and output to be used by
// all the VaST routines. The goal is to be able to easily track the exact format in
// which the lightcurves are stored.

// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_LIGHTCURVE_IO_INCLUDE_FILE

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
//#include <stddef.h> // for size_t, but stddef.h is included in string.h
#include <ctype.h> // for isalpha()
#include <math.h>  // for isnormal()

#include "vast_limits.h"

static inline int write_lightcurve_point(FILE *lc_file_descriptor, double jd, double mag, double mag_err, double x, double y, double app, char *string, char *comments_string) {
 //
 if( NULL == lc_file_descriptor ) {
  return 1;
 }
 // Never print zero errors!
 double nonzero_mag_err;
 // 0.0001 has to match the printf format %.4lf below
 if( mag_err < 0.0001 ) {
  nonzero_mag_err= 0.0001;
 } else {
  nonzero_mag_err=mag_err;  
 }
 //
 if( NULL == comments_string ) {
  //fprintf(lc_file_descriptor, "%.5lf %8.4lf %.4lf  %10.5lf %10.5lf %4.1lf %s\n", jd, mag, nonzero_mag_err, x, y, app, string);
  fprintf(lc_file_descriptor, "%.8lf %8.4lf %.4lf  %10.5lf %10.5lf %4.1lf %s\n", jd, mag, nonzero_mag_err, x, y, app, string);
 } else {
  //fprintf(lc_file_descriptor, "%.5lf %8.4lf %.4lf  %10.5lf %10.5lf %4.1lf %s  %s\n", jd, mag, nonzero_mag_err, x, y, app, string, comments_string);
  fprintf(lc_file_descriptor, "%.8lf %8.4lf %.4lf  %10.5lf %10.5lf %4.1lf %s  %s\n", jd, mag, nonzero_mag_err, x, y, app, string, comments_string);
 }
 return 0;
}

/*
  read_lightcurve_point() will read one line from a lightcurve file figuring out on its own the lightcurve file format
  
  RETURN VALUES:
  -1 - end of file
   0 - OK, successfully parsed the line
   1 - cannot parse the line, it probably contains comments, jd will also be set to 0.0!
*/

static inline int read_lightcurve_point(FILE *lc_file_descriptor, double *jd, double *mag, double *mag_err, double *x, double *y, double *app, char *string, char *comments_string) {
 char str[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 //int str_len; // string length
 size_t str_len; // string length
 size_t max_index_for_comments_check;
 size_t i; // counter

 char string_for_additional_columns_in_lc_file[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 string_for_additional_columns_in_lc_file[0]= '\0';                                        // just in case
 string_for_additional_columns_in_lc_file[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE - 1]= '\0'; // just in case

 if( NULL == fgets(str, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lc_file_descriptor) ) {
  return -1;
 }
 str[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE - 1]= '\0'; // just in case
 
 // everything else can burn, but *jd cannot be pointing to NULL
 if ( NULL == jd ) {
  fprintf( stderr, "ERROR in read_lightcurve_point() the output jd is a NULL pointer!\n");
  return 1;
 }
 
 // Actually we kid of want mag also
 if ( NULL == mag ) {
  fprintf( stderr, "ERROR in read_lightcurve_point() the output mag is a NULL pointer!\n");
  return 1;
 }
 (*mag) = 99.999; // initialize mag to an obviously wrong value

 // and mag_err
 if ( NULL == mag_err ) {
  fprintf( stderr, "ERROR in read_lightcurve_point() the output mag_err is a NULL pointer!\n");
  return 1;
 }
 (*mag_err)= DEFAULT_PHOTOMETRY_ERROR_MAG; // initialize mag_err

 // A naive attempt to optimize: if the first symbol is a number, assume this is a valid measurement, not a comment
 if( 0 == isdigit(str[0]) ) {
  // Get string length
  str_len= strlen(str);
  if( str_len < 5 ) {
   (*jd)= 0.0;
   return 1;
  } // assume that a string shorter than 5 bytes will contain no useful lightcurve information
  max_index_for_comments_check= MIN(str_len, 10);
  // Check if there are comments in the first 10 bytes of this string
  // If there are, assume this string contains no useful data
  for( i= 0; i < max_index_for_comments_check; i++ ) {
   // in most cases we expect the first symbol of the string to be a comment mark
   if( str[i] == '#' ) {
    (*jd)= 0.0;
    return 1;
   }
   if( str[i] == '%' ) {
    (*jd)= 0.0;
    return 1;
   }
   if( str[i] == '/' ) {
    (*jd)= 0.0;
    return 1;
   }
   if( 0 != isalpha(str[i]) ) {
    (*jd)= 0.0;
    return 1;
   }
  }
 }

 //fprintf(stderr,"DEBUG: %s\n",str);

 // experimental thing, does not work???
 //if( 7>sscanf( str, "%lf %lf %lf  %lf %lf %lf %s %[^\t\n]", jd, mag, mag_err, x, y, app, string, string_for_additional_columns_in_lc_file) ){
 // Consistency check
 if( MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE < 512 ) {
  fprintf(stderr, "ERROR: MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE defined in src/vast_limits.h should be >512\n");
  exit( EXIT_FAILURE );
 }

 // Special case -- yes, we can actually speed up reading by not parsing x, y, app and the comments
 if( x == NULL ) {
  if( 3 != sscanf(str, "%lf %lf %lf\n", jd, mag, mag_err) ) {
   (*mag_err)= DEFAULT_PHOTOMETRY_ERROR_MAG; // if no error estimate is provided, assume a "typical" CCD photometry error
   if( 2 != sscanf(str, "%lf %lf\n", jd, mag) ) {
    (*jd)= 0.0;
    return 1;
   } // if ( 2 != sscanf( str, "%lf %lf\n", jd, mag ) ) {
  }  // if ( 3 != sscanf( str, "%lf %lf %lf\n", jd, mag, mag_err ) ) {
 } else {

  // Warning! Max comment string length is hardcoded here!
  if( 8 != sscanf(str, "%lf %lf %lf  %lf %lf %lf %s %512[^\t\n]", jd, mag, mag_err, x, y, app, string, string_for_additional_columns_in_lc_file) ) {
   string_for_additional_columns_in_lc_file[0]= '\0';
   string[0]= '\0';                                     // just in case
   str[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE - 1]= '\0'; // just in case
   if( 7 != sscanf(str, "%lf %lf %lf  %lf %lf %lf %s", jd, mag, mag_err, x, y, app, string) ) {
    string[0]= '\0';
    (*app)= 1.0;
    (*x)= (*y)= 0.0;
    if( 3 != sscanf(str, "%lf %lf %lf\n", jd, mag, mag_err) ) {
     (*mag_err)= DEFAULT_PHOTOMETRY_ERROR_MAG;
     if( 2 != sscanf(str, "%lf %lf\n", jd, mag) ) {
      (*jd)= 0.0;
      return 1;
     }                                                                                      // if ( 2 != sscanf( str, "%lf %lf\n", jd, mag ) ) {
    }                                                                                       // if ( 3 != sscanf( str, "%lf %lf %lf\n", jd, mag, mag_err ) ) {
   }                                                                                        // if ( 7 != sscanf( str, "%lf %lf %lf  %lf %lf %lf %s", jd, mag, mag_err, x, y, app, string ) ) {
  }                                                                                         // if ( 8 != sscanf( str, "%lf %lf %lf  %lf %lf %lf %s %512[^\t\n]", jd, mag, mag_err, x, y, app, string, string_for_additio
  string_for_additional_columns_in_lc_file[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE - 1]= '\0'; // just in case
  // !!
  if( NULL != comments_string ) {
   strncpy(comments_string, string_for_additional_columns_in_lc_file, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE);
   comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE - 1]= '\0'; // just in case
  }

  // isnan() and isinf() are normally defined
  if( 0 != isnan((*jd)) ) {
   (*jd)= 0.0;
   return 1;
  }
  if( 0 != isnan((*mag)) ) {
   (*jd)= 0.0;
   return 1;
  }
  if( 0 != isnan((*mag_err)) ) {
   (*jd)= 0.0;
   return 1;
  }
  if( 0 != isinf((*jd)) ) {
   (*jd)= 0.0;
   return 1;
  }
  if( 0 != isinf((*mag)) ) {
   (*jd)= 0.0;
   return 1;
  }
  if( 0 != isinf((*mag_err)) ) {
   (*jd)= 0.0;
   return 1;
  }
  if( 0 != isnan((*x)) ) {
   (*jd)= 0.0;
   return 1;
  }
  if( 0 != isnan((*y)) ) {
   (*jd)= 0.0;
   return 1;
  }
  if( 0 != isinf((*x)) ) {
   (*jd)= 0.0;
   return 1;
  }
  if( 0 != isinf((*y)) ) {
   (*jd)= 0.0;
   return 1;
  }

#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
#ifdef VAST_USE_BUILTIN_FUNCTIONS
// Make a proper check of the input values if isnormal() is defined
#if defined _ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L
  // We use __builtin_isnormal() as we know it is working if VAST_USE_BUILTIN_FUNCTIONS is defined
  // Othervise even with the '_ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L' check
  // isnormal() doesn't work on Ubuntu 14.04 trusty (vast.sai.msu.ru)
  // BEWARE 0.0 is also not considered normal by isnormal() !!!
  if( 0 == __builtin_isnormal((*jd)) ) {
   (*jd)= 0.0;
   return 1;
  }
  if( 0 == __builtin_isnormal((*mag)) ) {
   (*jd)= 0.0;
   return 1;
  }
  if( 0 == __builtin_isnormal((*mag_err)) ) {
   (*jd)= 0.0;
   return 1;
  }
  if( 0 == __builtin_isnormal((*app)) ) {
   (*jd)= 0.0;
   return 1;
  }
#endif
#endif

  // Check the input date, note that wedon't know if it's JD or MJD
  if( (*jd) < EXPECTED_MIN_MJD ) {
   (*jd)= 0.0;
   return 1;
  }
  if( (*jd) > EXPECTED_MAX_JD ) {
   (*jd)= 0.0;
   return 1;
  }

  // Check the input mag
  if( (*mag) < BRIGHTEST_STARS ) {
   (*jd)= 0.0;
   return 1;
  }
  // A similar check for the expected faintest stars
  if( (*mag) > FAINTEST_STARS_ANYMAG ) {
   (*jd)= 0.0;
   return 1;
  }

  // Check if the measurement errors are not too big
  if( (*mag_err) > MAX_MAG_ERROR ) {
   (*jd)= 0.0;
   return 1;
  }

#endif

 } // end else special case

 if( (*mag_err) <= 0.0 ) {
  // never allow zero errors as they will lead to negative weights downstream
  (*mag_err)= DEFAULT_PHOTOMETRY_ERROR_MAG;
 }

 return 0;
}

static inline int count_points_in_lightcurve_file(char *lightcurvefilename) {
 int n;
 FILE *lightcurvefile;
 double jd, mag, merr, y, app;
 char string[FILENAME_LENGTH];

 lightcurvefile= fopen(lightcurvefilename, "r");
 if( NULL == lightcurvefile ) {
  fprintf(stderr, "ERROR: cannot open lightcurve file %s \n", lightcurvefilename);
  return -1;
 }

 n= 0;
 while( -1 < read_lightcurve_point(lightcurvefile, &jd, &mag, &merr, NULL, &y, &app, string, NULL) ) {
  if( jd == 0.0 )
   continue; // if this line could not be parsed, try the next one
  n++;
 }

 fclose(lightcurvefile);

 return n;
}

// The macro below will tell the pre-processor that this header file is already included
#define VAST_LIGHTCURVE_IO_INCLUDE_FILE
#endif
// VAST_LIGHTCURVE_IO_INCLUDE_FILE
