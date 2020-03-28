#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "vast_limits.h"

//#define MAX_NUMBER_OF_INDEXES_TO_STORE 26

// After incorporating PCA admixture coefficients using merge_admixture_coefficients_into_vast_lightcurve_statistics_log.sh
#define MAX_NUMBER_OF_INDEXES_TO_STORE 31

//#define MAX_STRING_LENGTH_IN_LIGHTCURVESTATS_FILE 4096

#define INVALID_INDEX_VALUE 100500

/// Bin size defined in number of points AND in magnitude range
//#define N_STARS_IN_INDEX_BIN 20 // used for filtering only
//#define N_STARS_IN_INDEX_BIN 60
//#define MIN_N_STARS_IN_INDEX_BIN 10
//#define MIN_N_STARS_IN_INDEX_BIN 20
//#define MIN_N_STARS_IN_INDEX_BIN 500
//#define MAG_BIN_HALF_WIDTH 0.25
//#define MAG_BIN_HALF_WIDTH 0.5

static inline void get_index_name( int input_index_number, char *output_short_index_name ) {
 if ( input_index_number == 0 ) {
  strcpy( output_short_index_name, "idx00_STD " );
  return;
 }
 if ( input_index_number == 6 - 5 ) {
  #ifdef DISABLE_INDEX_WEIGHTED_SIGMA
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx01_wSTD" );
  #endif
  return;
 }
 if ( input_index_number == 7 - 5 ) {
  #ifdef DISABLE_INDEX_SKEWNESS
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx02_skew" );
  #endif
  return;
 }
 if ( input_index_number == 8 - 5 ) {
  #ifdef DISABLE_INDEX_KURTOSIS
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx03_kurt" );
  #endif
  return;
 }
 if ( input_index_number == 9 - 5 ) {
  #ifdef DISABLE_INDEX_WELCH_STETSON
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx04_I   " );
  #endif
  return;
 }
 if ( input_index_number == 10 - 5 ) {
  #ifdef DISABLE_INDEX_STETSON_JKL
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx05_J   " );
  #endif
  return;
 }
 if ( input_index_number == 11 - 5 ) {
  #ifdef DISABLE_INDEX_STETSON_JKL
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx06_K   " );
  #endif
  return;
 }
 if ( input_index_number == 12 - 5 ) {
  #ifdef DISABLE_INDEX_STETSON_JKL
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx07_L   " );
  #endif
  return;
 }
 if ( input_index_number == 13 - 5 ) {
  strcpy( output_short_index_name, "idx08_Npts" );
  return;
 }
 if ( input_index_number == 14 - 5 ) {
  #ifdef DISABLE_INDEX_MAD
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx09_MAD " );
  #endif
  return;
 }
 if ( input_index_number == 15 - 5 ) {
  #ifdef DISABLE_INDEX_LAG1_AUTOCORRELATION
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx10_lag1" );
  #endif
  return;
 }
 if ( input_index_number == 16 - 5 ) {
  #ifdef DISABLE_INDEX_ROMS
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx11_RoMS" );
  #endif
  return;
 }
 if ( input_index_number == 17 - 5 ) {
  #ifdef DISABLE_INDEX_REDUCED_CHI2
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx12_rCh2" );
  #endif
  return;
 }
 if ( input_index_number == 18 - 5 ) {
  #ifdef DISABLE_INDEX_WELCH_STETSON_SIGN_ONLY
  strcpy( output_short_index_name, "__________" );
  #else  
  strcpy( output_short_index_name, "idx13_Isgn" );
  #endif
  return;
 }
 if ( input_index_number == 19 - 5 ) {
  #ifdef DISABLE_INDEX_PEAK_TO_PEAK_AGN_V
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx14_Vp2p" );
  #endif
  return;
 }
 if ( input_index_number == 20 - 5 ) {
  #ifdef DISABLE_INDEX_STETSON_JKL_MAG_CLIP_PAIRS
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx15_Jclp" );
  #endif
  return;
 }
 if ( input_index_number == 21 - 5 ) {
  #ifdef DISABLE_INDEX_STETSON_JKL_MAG_CLIP_PAIRS
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx16_Lclp" );
  #endif
  return;
 }
 if ( input_index_number == 22 - 5 ) {
  #ifdef DISABLE_INDEX_STETSON_JKL_TIME_WEIGHTING
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx17_Jtim" );
  #endif
  return;
 }
 if ( input_index_number == 23 - 5 ) {
  #ifdef DISABLE_INDEX_STETSON_JKL_TIME_WEIGHTING
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx18_Ltim" );
  #endif
  return;
 }
 if ( input_index_number == 24 - 5 ) {
  #ifdef DISABLE_INDEX_N3
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx19_N3  " );
  #endif
  return;
 }
 if ( input_index_number == 25 - 5 ) {
  #ifdef DISABLE_INDEX_EXCURSIONS
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx20_excr" );
  #endif
  return;
 }
 if ( input_index_number == 26 - 5 ) {
  #ifdef DISABLE_INDEX_VONNEUMANN_RATIO
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx21_eta " );
  #endif
  return;
 }
 if ( input_index_number == 27 - 5 ) {
  #ifdef DISABLE_INDEX_EXCESS_ABBE_E_A
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx22_E_A " );
  #endif
  return;
 }
 if ( input_index_number == 28 - 5 ) {
  #ifdef DISABLE_INDEX_SB
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx23_S_B " );
  #endif
  return;
 }
 if ( input_index_number == 29 - 5 ) {
  #ifdef DISABLE_INDEX_NXS
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx24_NXS " );
  #endif
  return;
 }
 if ( input_index_number == 30 - 5 ) {
  #ifdef DISABLE_INDEX_IQR
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx25_IQR " );
  #endif
  return;
 }
 // the A01--A05 indexes are reserved for the PCA analysis
 // that was implemented outside of VaST, see
 // https://ui.adsabs.harvard.edu/abs/2018MNRAS.477.2664M
 if ( input_index_number == 31 - 5 ) {
  #ifdef DISABLE_INDEX_A
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx26_A01 " );
  #endif
  return;
 }
 if ( input_index_number == 32 - 5 ) {
  #ifdef DISABLE_INDEX_A
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx27_A02 " );
  #endif
  return;
 }
 if ( input_index_number == 33 - 5 ) {
  #ifdef DISABLE_INDEX_A
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx28_A03 " );
  #endif
  return;
 }
 if ( input_index_number == 34 - 5 ) {
  #ifdef DISABLE_INDEX_A
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx29_A04 " );
  #endif
  return;
 }
 if ( input_index_number == 35 - 5 ) {
  #ifdef DISABLE_INDEX_A
  strcpy( output_short_index_name, "__________" );
  #else
  strcpy( output_short_index_name, "idx30_A05 " );
  #endif
  return;
 }

 strcpy( output_short_index_name, "UNK." );
 return;
}

// This function is described in src/write_vast_lightcurve_statistics_format_log.c
void write_vast_lightcurve_statistics_format_log();

static inline double get_index_by_column_number( char *substring_to_parse, int index_number_in_substring ) {
 double index_value;
 int index_counter, i, j; // counters
 int string_length;
 char substring_to_covert[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG];
 int are_we_reading= 0; // 0 - we are not currently reading an index value
                        // 1 - we are currently reading an index value

 i= j= index_counter= 0;                                                            // just in case
 substring_to_parse[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG - 1]= '\0'; // just in case

 string_length= strlen( substring_to_parse );

 if ( 10 > string_length ) {
  fprintf( stderr, "ERROR: the substring_to_parse is suspiciously short %s\n", substring_to_parse );
  exit( 1 );
 }

 // Is there a mixup between 24 and 29???
 if ( index_number_in_substring >= MAX_NUMBER_OF_INDEXES_TO_STORE ) {
  fprintf( stderr, "ERROR in get_index_by_column_number() %d >= %d\n", index_number_in_substring, MAX_NUMBER_OF_INDEXES_TO_STORE );
  exit( 1 );
 }

 index_value= INVALID_INDEX_VALUE; // reset the variable, just in case

 for ( are_we_reading= 0, index_counter= 0, j= 0, i= 0; i < MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG; i++ ) {
  // skip leading white spaces if any
  if ( are_we_reading == 0 && substring_to_parse[i] == ' ' )
   continue;
  // stop if see a white space again after reading a value
  if ( are_we_reading == 1 ) {
   if ( substring_to_parse[i] == ' ' || i == string_length ) {
    index_counter++;
    // if this is our index
    if ( index_counter == index_number_in_substring ) {
     substring_to_covert[j]= '\0';
     // convert the temporary string to double
     index_value= atof( substring_to_covert );
     //if( index_number_in_substring==24 )fprintf(stderr,"CONVERTING _%s_  %d %d %lf  %lg \n",substring_to_covert, index_counter, index_number_in_substring,index_value,index_value);
     break;
    }
    j= 0;
    are_we_reading= 0;
    continue;
   }
  }
  // copy the non-space characters to a temporary string
  substring_to_covert[j]= substring_to_parse[i];
  are_we_reading= 1;
  j++;
 }

 // If the index index is too large
 if ( index_counter < index_number_in_substring )
  index_value= INVALID_INDEX_VALUE;
 //

 //fprintf(stderr,"returning the index %lf\n",index_value);

 // return the result
 return index_value;
}
