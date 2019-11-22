#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_spline.h>
#include <gsl/gsl_statistics.h>
#include <gsl/gsl_errno.h>

#include "vast_limits.h"
#include "variability_indexes.h"     // for MAD computation
#include "detailed_error_messages.h" // for report_lightcurve_statistics_computation_problem()
#include "index_vs_mag.h"

int main() {

 double tmp_d_value_to_print;
 int output_file_counter;
 FILE *output_filedescriptor;

 double **index;          // the actual values of all indexes for all stars
 double **index_expected; // the expected (for non-variables) values of all indexes for all stars
 double **index_spread;   // the RMS (?) scatter of the the expected (for non-variables) values of all indexes for all stars
 double **index_filtered;
 double **index_spread_filtered;
 char **lightcurvefilename;
 double *data_for_stat;
 int *index_for_stat;
 double *array_of_magnitudes;
 char string_to_parse[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG];
 char substring_to_parse[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG];

 double tmpmag, tmpsigma, tmpdouble;

 int n_stars_in_lightcurve_statistics_file; // number of stars in the input statistics file

 int i, j, k, l; // counters

 int start_index, stop_index;
 int varindex_counter;

 FILE *lightcurve_statistics_file;

 FILE *lightcurve_statistics_expected_file;
 FILE *lightcurve_statistics_spread_file;
 FILE *lightcurve_statistics_expected_plus_spread_file;
 FILE *lightcurve_statistics_expected_minus_spread_file;

 FILE *lightcurve_statistics_normalized_file;

 // To compute the measures of variability selection efficiency C P F
 FILE *list_of_known_vars_file;
 char **known_variable_lightcurvefilename;
 int n_known_variables;
 double threshold; // select as variable stars the ones that stand out by more than threshold*sigma in some index
 int number_of_selected_objects[MAX_NUMBER_OF_INDEXES_TO_STORE];
 int number_of_selected_variables[MAX_NUMBER_OF_INDEXES_TO_STORE];
 double C; // Number of selected variables/Total number of confirmed variables
 double P; // Number of selected variables/Total number of selected objects
 double F; // 2 * (C * P)/(C + P)
 char short_index_name[256];
 // to compute maximum efficiency
 FILE *vast_detection_efficiency_log;
 // Naturally, there will be different values of Fmax, C_at_Fmax, and P_at_Fmax for each index
 double Fmax[MAX_NUMBER_OF_INDEXES_TO_STORE];
 double C_at_Fmax[MAX_NUMBER_OF_INDEXES_TO_STORE];
 double P_at_Fmax[MAX_NUMBER_OF_INDEXES_TO_STORE];
 double threshold_at_Fmax[MAX_NUMBER_OF_INDEXES_TO_STORE];
 double threshold_at_Cmax[MAX_NUMBER_OF_INDEXES_TO_STORE];
 double P_at_Cmax[MAX_NUMBER_OF_INDEXES_TO_STORE];
 double Cmax[MAX_NUMBER_OF_INDEXES_TO_STORE];
 double fraction_of_obj_rejected_at_Cmax[MAX_NUMBER_OF_INDEXES_TO_STORE];
 double fraction_of_obj_rejected_at_Fmax[MAX_NUMBER_OF_INDEXES_TO_STORE];
 FILE *lightcurve_statistics_expected_plus_spread_file_Cmax;
 char comments_string_autocandidates[2048];
 //
 char full_string_autocandidates[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG];
 //
 FILE *autocandidatesfile;
 int is_this_star_variable; // 0 - no, 1 - yes
 FILE *sysrem_input_star_list_file;
 //
 FILE *autocandidatesdetailsfile;
 char autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS];
 //
 FILE *vast_list_of_likely_constant_stars;
 int is_this_star_constant; // 0 - no, 1 - yes

 //
 double distance_to_nearest_reference_point, best_distance_to_nearest_reference_point;
 int best_reference_point_index;
 //

 // Initialize Fmax, j just because I use this counter with MAX_NUMBER_OF_INDEXES_TO_STORE later
 for ( j= 0; j < MAX_NUMBER_OF_INDEXES_TO_STORE; j++ ) {
  Fmax[j]= 0.0;
  // And initialize all the other stuff
  C_at_Fmax[j]= P_at_Fmax[j]= P_at_Cmax[j]= Cmax[j]= fraction_of_obj_rejected_at_Cmax[j]= fraction_of_obj_rejected_at_Fmax[j]= 0.0;
  threshold_at_Fmax[j]= 1.0; // threshold will override this below
  threshold_at_Cmax[j]= 1.0;
  //
 }

 // Read the indexes
 lightcurve_statistics_file= fopen( "vast_lightcurve_statistics.log", "r" );
 if ( lightcurve_statistics_file == NULL ) {
  fprintf( stderr, "ERROR: Can't open file vast_lightcurve_statistics.log !\n" );
  report_lightcurve_statistics_computation_problem();
  return 1;
 }
 // count lines in the file
 n_stars_in_lightcurve_statistics_file= 0;
 while ( NULL != fgets( string_to_parse, MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG, lightcurve_statistics_file ) )
  n_stars_in_lightcurve_statistics_file++;
 fseek( lightcurve_statistics_file, 0, SEEK_SET ); // go back to the beginning of the file
 if ( n_stars_in_lightcurve_statistics_file <= 0 ) {
  fprintf( stderr, "ERROR: Too small stars amount(index_vs_mag.c)\n" );
  return 1;
 };
 // allocate memory
 index= malloc( n_stars_in_lightcurve_statistics_file * sizeof( double * ) );
 if ( index == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for index(index_vs_mag.c)\n" );
  return 1;
 }
 index_expected= malloc( n_stars_in_lightcurve_statistics_file * sizeof( double * ) );
 if ( index_expected == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for index_expected(index_vs_mag.c)\n" );
  return 1;
 }
 index_filtered= malloc( n_stars_in_lightcurve_statistics_file * sizeof( double * ) );
 if ( index_filtered == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for index_filtered(index_vs_mag.c)\n" );
  return 1;
 }
 index_spread= malloc( n_stars_in_lightcurve_statistics_file * sizeof( double * ) );
 if ( index_spread == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for index_spread(index_vs_mag.c)\n" );
  return 1;
 }
 index_spread_filtered= malloc( n_stars_in_lightcurve_statistics_file * sizeof( double * ) );
 if ( index_spread_filtered == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for index_spread_filtered(index_vs_mag.c)\n" );
  return 1;
 }
 lightcurvefilename= malloc( n_stars_in_lightcurve_statistics_file * sizeof( char * ) );
 if ( lightcurvefilename == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for lightcurvefilename(index_vs_mag.c)\n" );
  return 1;
 }
 known_variable_lightcurvefilename= malloc( n_stars_in_lightcurve_statistics_file * sizeof( char * ) );
 if ( known_variable_lightcurvefilename == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for known_variable_lightcurvefilename(index_vs_mag.c)\n" );
  return 1;
 }

 array_of_magnitudes= malloc( n_stars_in_lightcurve_statistics_file * sizeof( double ) );
 if ( array_of_magnitudes == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for array_of_magnitudes(index_vs_mag.c)\n" );
  return 1;
 }
 index_for_stat= malloc( n_stars_in_lightcurve_statistics_file * sizeof( int ) );
 if ( index_for_stat == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for index_for_stat(index_vs_mag.c)\n" );
  return 1;
 }
 for ( i= 0; i < n_stars_in_lightcurve_statistics_file; i++ ) {
  index[i]= malloc( MAX_NUMBER_OF_INDEXES_TO_STORE * sizeof( double ) );
  if ( index[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for index[i](index_vs_mag.c)\n" );
   return 1;
  }
  index_expected[i]= malloc( MAX_NUMBER_OF_INDEXES_TO_STORE * sizeof( double ) );
  if ( index_expected[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for index_expected[i](index_vs_mag.c)\n" );
   return 1;
  }

  index_filtered[i]= malloc( MAX_NUMBER_OF_INDEXES_TO_STORE * sizeof( double ) );
  if ( index_filtered[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for index_filtered[i](index_vs_mag.c)\n" );
   return 1;
  }
  index_spread_filtered[i]= malloc( MAX_NUMBER_OF_INDEXES_TO_STORE * sizeof( double ) );
  if ( index_spread_filtered[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for index_spread_filtered[i](index_vs_mag.c)\n" );
   return 1;
  }
  index_spread[i]= malloc( MAX_NUMBER_OF_INDEXES_TO_STORE * sizeof( double ) );
  if ( index_spread[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for index_spread[i](index_vs_mag.c)\n" );
   return 1;
  }
  lightcurvefilename[i]= malloc( OUTFILENAME_LENGTH * sizeof( char ) );
  if ( lightcurvefilename[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for lightcurvefilename[i](index_vs_mag.c)\n" );
   return 1;
  }
  known_variable_lightcurvefilename[i]= malloc( OUTFILENAME_LENGTH * sizeof( char ) );
  if ( known_variable_lightcurvefilename[i] == NULL ) {
   fprintf( stderr, "Memory allocation ERROR: known_variable_lightcurvefilename[%d]\n", i );
   return 1;
  }
 }
 i= 0;
 while ( NULL != fgets( string_to_parse, MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG, lightcurve_statistics_file ) ) {
  string_to_parse[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG - 1]= '\0'; // just in case
  if ( 100 > strlen( string_to_parse ) ) {
   fprintf( stderr, "ERROR parsing vast_lightcurve_statistics.log string: %s\n", string_to_parse );
   continue;
  }
  // reset the string to make valgrind happy
  memset( substring_to_parse, 0, MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG );
  //
  if ( 6 > sscanf( string_to_parse, "%lf %lf %lf %lf %s %[^\t\n]", &tmpmag, &tmpsigma, &tmpdouble, &tmpdouble, lightcurvefilename[i], substring_to_parse ) ) {
   fprintf( stderr, "ERROR parsing vast_lightcurve_statistics.log string: %s\n", string_to_parse );
   continue;
  }
  array_of_magnitudes[i]= tmpmag;
  index[i][0]= tmpsigma;
  //
  index_filtered[i][0]= index_spread_filtered[i][0]= 0.0; // init
  //
  for ( j= 1; j < MAX_NUMBER_OF_INDEXES_TO_STORE; j++ ) {
   index[i][j]= get_index_by_column_number( substring_to_parse, j );
   // ?????????????????
   if ( 0 == isnormal( index[i][j] ) )
    index[i][j]= INVALID_INDEX_VALUE;
   //
   index_filtered[i][j]= 0.0;        // We need to initialize this one for the median-subtraction procedure that follows
   index_spread_filtered[i][j]= 0.0; // We need to initialize this
   //
  }
  i++;
 }
 fclose( lightcurve_statistics_file );

 // Compute the expected index values and their scatter for each star
 // WE RELY ON THE INPUT ARRAY TO BE SORTED IN MAGNITUDE

 fprintf( stderr, "Computing the expected values of variability indexes and their scatter as a function of magnitude\n" );

#define NUMBER_OF_REFERENCE_POINTS 1000 // There will be no more than NUMBER_OF_REFERENCE_POINTS points along the magnitude axis
                                        // #define MIN_NUMBER_OF_STARS_IN_BIN 40
#define MIN_NUMBER_OF_STARS_IN_BIN 100
 // #define MAX_NUMBER_OF_STARS_IN_BIN 300
#define BIN_HALFWIDTH_STEP_MAG 0.02
#define MIN_BIN_HALFWIDTH_MAG 0.25
 double reference_point_mag_brightest, reference_point_mag_faintest, reference_point_mag_step;
 double *reference_point_mag;
 int number_of_reference_points;
 double mag_bin_halfwidth;
 int min_number_of_points_in_mag_bin;
 double *data_for_stat_median_subtracted;
 int iteration;

 // Crazy attempt to handle the "too few stars" situation
 min_number_of_points_in_mag_bin= MIN( MIN_NUMBER_OF_STARS_IN_BIN, (int)( (float)n_stars_in_lightcurve_statistics_file / 10.0 ) + 0.5 );
 min_number_of_points_in_mag_bin= MAX( min_number_of_points_in_mag_bin, 20 );
 // make sure min_number_of_points_in_mag_bin is not smaller than the total number of stars (or the code will enter an infinite loop)
 min_number_of_points_in_mag_bin= MIN( min_number_of_points_in_mag_bin, n_stars_in_lightcurve_statistics_file );

 number_of_reference_points= MIN( n_stars_in_lightcurve_statistics_file, NUMBER_OF_REFERENCE_POINTS );

 reference_point_mag= malloc( number_of_reference_points * sizeof( double ) );
 if ( reference_point_mag == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for reference_point_mag(index_vs_mag.c)\n" );
  return 1;
 }
 // Uniformly distribute the reference points across the whole magnitude range
 reference_point_mag_brightest= array_of_magnitudes[0];
 reference_point_mag_faintest= array_of_magnitudes[n_stars_in_lightcurve_statistics_file - 1];
 reference_point_mag_step= ( reference_point_mag_faintest - reference_point_mag_brightest ) / (double)number_of_reference_points;
 reference_point_mag[0]= reference_point_mag_brightest;
 for ( i= 1; i < number_of_reference_points; i++ ) {
  reference_point_mag[i]= reference_point_mag[i - 1] + reference_point_mag_step;
 } // for(i=0;i<number_of_reference_points;i++){

 for ( iteration= 0; iteration < 4; iteration++ ) {

#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel private( i, j, start_index, stop_index, varindex_counter, k, data_for_stat, mag_bin_halfwidth, data_for_stat_median_subtracted )
#endif
#endif
  {
   // We allocate it here and de-allcoate at the end of the cycle to make OpenMP parallelization work
   data_for_stat= malloc( n_stars_in_lightcurve_statistics_file * sizeof( double ) );
   if ( data_for_stat == NULL ) {
    fprintf( stderr, "Memory allocation ERROR: data_for_stat\n" );
    exit( 1 );
   }
   // !!!
   data_for_stat_median_subtracted= malloc( n_stars_in_lightcurve_statistics_file * sizeof( double ) );
   if ( data_for_stat_median_subtracted == NULL ) {
    fprintf( stderr, "Memory allocation ERROR: data_for_stat_median_subtracted\n" );
    exit( 1 );
   }

#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp for
#endif
#endif
   //for(i=0;i<n_stars_in_lightcurve_statistics_file;i++){
   for ( i= 0; i < number_of_reference_points; i++ ) {

    //if( i % 100 == 0 )fprintf(stderr,"\rComputing variability indexes for star %5d out of %5d    ",i,n_stars_in_lightcurve_statistics_file);
    if ( i % 100 == 0 ) {
     fprintf( stderr, "." );
    }

    // Determine the range of indexes for the bin around the current star
    start_index= stop_index= 0;
    // Tune bin half-width
    mag_bin_halfwidth= MIN_BIN_HALFWIDTH_MAG;
    while ( stop_index - start_index < min_number_of_points_in_mag_bin ) {
     mag_bin_halfwidth= mag_bin_halfwidth + BIN_HALFWIDTH_STEP_MAG;
     for ( j= 0; j < n_stars_in_lightcurve_statistics_file; j++ ) {
      if ( reference_point_mag[i] - array_of_magnitudes[j] <= mag_bin_halfwidth )
       break;
     }
     start_index= j;
     for ( j= 0; j < n_stars_in_lightcurve_statistics_file; j++ ) {
      if ( array_of_magnitudes[j] - reference_point_mag[i] >= mag_bin_halfwidth )
       break;
     }
     stop_index= j;
    }
    //fprintf(stderr,"\nDEBUG: i=%d start_index=%d stop_index=%d  n_stars_in_lightcurve_statistics_file=%d\n",i,start_index,stop_index,n_stars_in_lightcurve_statistics_file);
    //} // for(j=0;j<n_stars_in_lightcurve_statistics_file;j++){
    // done binning, now collect the index values within the bin

    // For each index
    for ( varindex_counter= 0; varindex_counter < MAX_NUMBER_OF_INDEXES_TO_STORE; varindex_counter++ ) {
     // initialize index values to make valgrind happy
     // collect index values within the bin into an array
     for ( k= 0, j= start_index; j < stop_index; j++ ) {
      //if( i==j )continue; // don't count yourself!
      data_for_stat[k]= index[j][varindex_counter];
      if ( INVALID_INDEX_VALUE == data_for_stat[k] )
       continue;
      if ( 0 == isnormal( data_for_stat[k] ) )
       continue; // redundant, done this check before when assigning the INVALID_INDEX_VALUE value
      if ( 0.0 == data_for_stat[k] )
       continue; // THIS IS NEW, forbid 0 index falues
      if ( index_spread_filtered[j][varindex_counter] != 0.0 ) {
       if ( fabs( index[j][varindex_counter] - index_filtered[j][varindex_counter] ) > 5.0 * index_spread_filtered[j][varindex_counter] )
        continue;
      }
      data_for_stat_median_subtracted[k]= index[j][varindex_counter] - index_filtered[j][varindex_counter];
      k++;
     }
     // estimate the expected index value and expected variance
     if ( k > 5 ) {
      //     if( iteration<3 ){
      gsl_sort( data_for_stat, 1, k );
      // yes, qsort is noticably slower!!
      //qsort( data_for_stat, k, sizeof( double ), compare_double );
      index_expected[i][varindex_counter]= gsl_stats_median_from_sorted_data( data_for_stat, 1, k );
      gsl_sort( data_for_stat_median_subtracted, 1, k );
      //qsort( data_for_stat_median_subtracted, k, sizeof( double ), compare_double );
      index_spread[i][varindex_counter]= esimate_sigma_from_MAD_of_sorted_data( data_for_stat_median_subtracted, k );
      //     }
      //     else{
      //      index_expected[i][varindex_counter]=gsl_stats_mean( data_for_stat, 1, k);
      //      index_spread[i][varindex_counter]=gsl_stats_sd( data_for_stat_median_subtracted, 1, k);
      //     }
      // If k>1 but there is no expected value or variance
      if ( 0 == isnormal( index_expected[i][varindex_counter] ) )
       index_expected[i][varindex_counter]= 0.0;
      if ( 0 == isnormal( index_spread[i][varindex_counter] ) )
       index_spread[i][varindex_counter]= 0.0;
     } else {
      // If we don't have enough points to estimate the index
      index_expected[i][varindex_counter]= 0.0;
      index_spread[i][varindex_counter]= 0.0;
     }
     //
     //if( varindex_counter==25 ){
     // fprintf(stderr,"k=%d mag_bin_halfwidth=%lf index_expected[i][varindex_counter]=%lf  index_spread[i][varindex_counter]=%lf\n",k,mag_bin_halfwidth,index_expected[i][varindex_counter],index_spread[i][varindex_counter]);
     //}
     //
    }
   }

   free( data_for_stat );                   /// !!!
   free( data_for_stat_median_subtracted ); /// !!!
  }                                         // #pragma omp parallel

  fprintf( stderr, "\n" ); // to terminate the \r output

  // Propagate
  // double distance_to_nearest_reference_point,best_distance_to_nearest_reference_point;
  // int best_reference_point_index;
  for ( i= 0; i < n_stars_in_lightcurve_statistics_file; i++ ) {
   best_distance_to_nearest_reference_point= 99.9;
   best_reference_point_index= number_of_reference_points; // reset
   for ( j= 0; j < number_of_reference_points; j++ ) {
    //for(j=number_of_reference_points;j--;){
    // most stars are closer to the fiant end
    distance_to_nearest_reference_point= fabs( array_of_magnitudes[i] - reference_point_mag[j] );
    if ( distance_to_nearest_reference_point < best_distance_to_nearest_reference_point ) {
     best_distance_to_nearest_reference_point= distance_to_nearest_reference_point;
     best_reference_point_index= j;
    }
    //else{
    // // The reference points are sorted in mag, so if we getting further from the nearsest one - we've already passed the best one
    // break;
    //}
   }
   if ( best_reference_point_index == number_of_reference_points ) {
    fprintf( stderr, "ERROR in index_vs_mag.c  cannot find the  best_reference_point\n" );
    return 1;
   }
   for ( varindex_counter= 0; varindex_counter < MAX_NUMBER_OF_INDEXES_TO_STORE; varindex_counter++ ) {
    index_filtered[i][varindex_counter]= index_expected[best_reference_point_index][varindex_counter];
    index_spread_filtered[i][varindex_counter]= index_spread[best_reference_point_index][varindex_counter];
    //
    //if( varindex_counter==25 ){
    // fprintf(stderr,"index_expected[best_reference_point_index][varindex_counter]=index_expected[%d][%d]=%lf\n",best_reference_point_index,varindex_counter,index_expected[best_reference_point_index][varindex_counter]);
    //}
    //
   }
  }

 } // for(iteration=0;iteration<2;iteration++){

 free( reference_point_mag );

 /* // WORKS BUT IT IS TOO SLOW!!!
 
 #ifdef VAST_ENABLE_OPENMP
  #ifdef _OPENMP
   #pragma omp parallel private(i,j,start_index,stop_index,varindex_counter,k,data_for_stat)
  #endif
 #endif
 {
  // We allocate it here and de-allcoate at the end of the cycle to make OpenMP parallelization work
  data_for_stat=malloc(n_stars_in_lightcurve_statistics_file*sizeof(double));
  if( data_for_stat==NULL ){fprintf(stderr,"Memory allocation ERROR: data_for_stat\n");exit(1);}
  // !!!
 
  #ifdef VAST_ENABLE_OPENMP
   #ifdef _OPENMP
    #pragma omp for
   #endif
  #endif
  for(i=0;i<n_stars_in_lightcurve_statistics_file;i++){

   //if( i % 100 == 0 )fprintf(stderr,"\rComputing variability indexes for star %5d out of %5d    ",i,n_stars_in_lightcurve_statistics_file);
   if( i % 100 == 0 )fprintf(stderr,".");
   // Determine the range of indexes for the bin around the current star
   start_index=stop_index=0;
   for(j=0;j<n_stars_in_lightcurve_statistics_file;j++){
    if( j<i ){
     if( array_of_magnitudes[i]-array_of_magnitudes[j]>MAG_BIN_HALF_WIDTH ){
      start_index=j;
     }
    }
    else{
     if( array_of_magnitudes[j]-array_of_magnitudes[i]<MAG_BIN_HALF_WIDTH ){
      stop_index=j;
     }
     else{
      // Make sure we have enough stars within the bin, take a wider bin if necessary
      if( stop_index-start_index<MIN_N_STARS_IN_INDEX_BIN )stop_index=j;
     }
    } // if( j<i ){
   } // for(j=0;j<n_stars_in_lightcurve_statistics_file;j++){
   // done binning, now collect the index values within the bin
   
   // For each index
   for(varindex_counter=0;varindex_counter<MAX_NUMBER_OF_INDEXES_TO_STORE;varindex_counter++){
    // initialize index values to make valgrind happy
    //index_expected[i][varindex_counter]=0.0;
    //index_spread[i][varindex_counter]=0.0;
    //
    // collect index values within the bin into an array
    for(k=0,j=start_index;j<stop_index;j++){
     if( i==j )continue; // don't count yourself!
     data_for_stat[k]=index[j][varindex_counter];
     if( INVALID_INDEX_VALUE==data_for_stat[k] )continue;
     if( 0==isnormal(data_for_stat[k]) )continue; // redundant, done this check before when assigning the INVALID_INDEX_VALUE value
     if( 0.0==data_for_stat[k] )continue; // THIS IS NEW, forbid 0 index falues
     k++;
    }
    // estimate the expected index value and expected variance
    if( k>1 ){
     gsl_sort( data_for_stat, 1, k);
     index_expected[i][varindex_counter]=gsl_stats_median_from_sorted_data( data_for_stat, 1, k);
     index_spread[i][varindex_counter]=esimate_sigma_from_MAD_of_sorted_data( data_for_stat, k);
     // If k>1 but there is no expected value or variance
     if( 0==isnormal(index_expected[i][varindex_counter]) )index_expected[i][varindex_counter]=0.0;
     if( 0==isnormal(index_spread[i][varindex_counter]) )index_spread[i][varindex_counter]=0.0;
    }
    else{
     // If we don't have enough points to estimate the index
     index_expected[i][varindex_counter]=0.0;
     index_spread[i][varindex_counter]=0.0;
    }
   }
  }
 
  free(data_for_stat); /// !!!
 } // #pragma omp parallel 

 fprintf(stderr,"\n"); // to terminate the \r output

 // Yes, filtering works but please revise it!!!!!
 fprintf(stderr,"Filtering the magnitude-index curves\n");
 // Filter the expected index values and spread
 #ifdef VAST_ENABLE_OPENMP
  #ifdef _OPENMP
   #pragma omp parallel private(i,k,bright_star_half_mag_away,star_half_mag_away,j,l,data_for_stat,data_for_stat_spread)
  #endif
 #endif
 {
  // We allocate it here and de-allcoate at the end of the cycle to make OpenMP parallelization work
  data_for_stat=malloc(n_stars_in_lightcurve_statistics_file*sizeof(double));
  if( data_for_stat==NULL ){fprintf(stderr,"Memory allocation ERROR: data_for_stat\n");exit(1);}
  data_for_stat_spread=malloc(n_stars_in_lightcurve_statistics_file*sizeof(double)); 
  if( data_for_stat_spread==NULL ){fprintf(stderr,"Memory allocation ERROR: data_for_stat_spread\n");exit(1);}
  // !!!

  #ifdef VAST_ENABLE_OPENMP
   #ifdef _OPENMP
    #pragma omp for
   #endif
  #endif
  for(i=0;i<n_stars_in_lightcurve_statistics_file;i++){
   
   // print a point to entertain the user
   if( i % 100 == 0 )fprintf(stderr,".");
   
   // set bright_star_half_mag_away and star_half_mag_away
   bright_star_half_mag_away=star_half_mag_away=0;
   for(k=0;k<i;k++){
    if( array_of_magnitudes[i]-array_of_magnitudes[k]<MAG_BIN_HALF_WIDTH ){
     bright_star_half_mag_away=i-k;
     break;
    }
   }
   for(k=i;k<n_stars_in_lightcurve_statistics_file;k++){
    if( array_of_magnitudes[k]-array_of_magnitudes[i]>MAG_BIN_HALF_WIDTH ){
     star_half_mag_away=k-i;
     break;
    }
   }
   //
   for(j=0;j<MAX_NUMBER_OF_INDEXES_TO_STORE;j++){
   //for(j=0;j<2;j++){
    l=0;
    for(k=MAX(0,i-MAX(N_STARS_IN_INDEX_BIN,bright_star_half_mag_away));k<MIN(n_stars_in_lightcurve_statistics_file,i+MAX(N_STARS_IN_INDEX_BIN,star_half_mag_away));k++){
     if( 0==isnormal(index_expected[k][j]) )continue;
     if( 0==isnormal(index_spread[k][j]) )continue;
     if( 0.0==index_spread[k][j] )continue;
     data_for_stat[l]=index_expected[k][j];
     data_for_stat_spread[l]=index_spread[k][j];
     l++;
    }
    if( l>1 ){
     //gsl_sort( data_for_stat, 1, l);
     //index_filtered[i][j]=gsl_stats_median_from_sorted_data( data_for_stat, 1, l);
     index_filtered[i][j]=gsl_stats_mean( data_for_stat, 1, l);
     index_spread_filtered[i][j]=gsl_stats_mean( data_for_stat_spread, 1, l);
     //gsl_sort( data_for_stat_spread, 1, l);
     //index_spread_filtered[i][j]=gsl_stats_median_from_sorted_data( data_for_stat_spread, 1, l);
    } // if( l>1 ){
    else{
     index_filtered[i][j]=index_spread_filtered[i][j]=0.0;
    }
   }
  }

  free(data_for_stat_spread); // !!!
  free(data_for_stat); // !!! 
 } // #pragma omp parallel

 fprintf(stderr,"\n");

*/

 //////////////////// Create a list of candidate variables ////////////////////
 autocandidatesdetailsfile= fopen( "vast_autocandidates_details.log", "w" );
 if ( NULL == autocandidatesdetailsfile ) {
  fprintf( stderr, "ERROR: opening file vast_autocandidates_details.log for writing!\n" );
  return 1;
 }
 fprintf( stderr, "Wriring the list of candidate variables to vast_autocandidates.log " );
 autocandidatesfile= fopen( "vast_autocandidates.log", "w" );
 if ( NULL != autocandidatesfile ) {
  sysrem_input_star_list_file= fopen( "sysrem_input_star_list.lst", "w" );
  if ( NULL != sysrem_input_star_list_file ) {
   vast_list_of_likely_constant_stars= fopen( "vast_list_of_likely_constant_stars.log", "w" );
   if ( NULL != vast_list_of_likely_constant_stars ) {
    // Loop through all the stars
    for ( i= 0; i < n_stars_in_lightcurve_statistics_file; i++ ) {
     is_this_star_constant= 0; // reset the flag just in case here, to avoid any possible confusion
     is_this_star_variable= 0; // reset the variability flag
     //
     strncpy( autocandidatesdetails_string, lightcurvefilename[i], MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS );
     autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 1]= '\0'; // just in case
//
// Check if this star is variables
//
// STD  -- the least sensitive (with the default threshould) test goes first
#ifdef CANDIDATE_VAR_SELECTION_WITH_CLIPPED_SIGMA
     if ( 0.0 != index_spread_filtered[i][0] ) {
      if ( CLIPPED_SIGMA_THRESHOLD < ( index[i][0] - index_filtered[i][0] ) / index_spread_filtered[i][0] ) {
       is_this_star_variable= 1;
       strncat( autocandidatesdetails_string, " CLIPPED_SIGMA ", MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 32 );
       autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 1]= '\0'; // just in case
      }
     }
#endif
// IQR
#ifdef CANDIDATE_VAR_SELECTION_WITH_IQR
#ifdef DISABLE_INDEX_IQR
     fprintf( stderr, "ERROR: DISABLE_INDEX_IQR and CANDIDATE_VAR_SELECTION_WITH_IQR cannot be set at the same time!\n" );
#else
     if ( 0.0 != index_spread_filtered[i][25] ) {
      if ( IQR_THRESHOLD < ( index[i][25] - index_filtered[i][25] ) / index_spread_filtered[i][25] ) {
       is_this_star_variable= 1;
       strncat( autocandidatesdetails_string, " IQR ", MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 32 );
       autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 1]= '\0'; // just in case
      }
     }
#endif
#endif
     //////////////////////////////////////////////////////////////////////
     // We want to puse here to create the SysRem input list before running the more sensitive variability tests.
     // Before doing this we will apply the non-variability criterea (they will be applied again below, after all variability tests).
     //////////////////////////////////////////////////////////////////////
     // Remove variability label if reducedChi2 is low.
     // (the photometric errors are likely underestimated, but not overestimated).
     if ( is_this_star_variable == 1 ) {
#ifdef DISABLE_INDEX_REDUCED_CHI2
      fprintf( stderr, "ERROR: DISABLE_INDEX_REDUCED_CHI2 should not be set while automated candidate variables selectio nis enabled!\n" );
#endif
      //
      if ( index[i][12] != INVALID_INDEX_VALUE ) {
       if ( REQUIRED_MIN_CHI2RED_FOR_ALL_CANDIDATE_VAR > index[i][12] ) {
        is_this_star_variable= 0;
        strncat( autocandidatesdetails_string, " -MIN_CHI2RED_SYSREM ", MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 32 );
        autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 1]= '\0'; // just in case
       }
      }
     }
     //////////////////////////////////////////////////////////////////////
     // Remove variability flag from the few brightes and faintest stars
     // here we rely on the fact that the input list is sorted in mag
     // Exclude faint stars from the list
     if ( i < MIN( (int)( DROP_FRACTION_OF_BRIGHTEST_VARIABLE_STARS * (double)n_stars_in_lightcurve_statistics_file + 0.5 ), DROP_MAX_NUMBER_OF_BRIGHTEST_VARIABLE_STARS ) ) {
      is_this_star_variable= 0;
      strncat( autocandidatesdetails_string, " -FRACTION_OF_BRIGHTEST_VARIABLE_STARS_SYSREM ", MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 32 );
      autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 1]= '\0'; // just in case
     }
     // Exclude faint stars from the list
     if ( i > n_stars_in_lightcurve_statistics_file - (int)( DROP_FRACTION_OF_FAINTEST_VARIABLE_STARS * (double)n_stars_in_lightcurve_statistics_file + 0.5 ) ) {
      is_this_star_variable= 0;
      strncat( autocandidatesdetails_string, " -FRACTION_OF_FAINTEST_VARIABLE_STARS_SYSREM ", MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 32 );
      autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 1]= '\0'; // just in case
     }
     //////////////////////////////////////////////////////////////////////
     // Write the star to SysRem input star list
     if ( is_this_star_variable == 0 ) {
      fprintf( sysrem_input_star_list_file, "%+10.6lf %+12.6lf 0 0 %s\n", array_of_magnitudes[i], index[i][0], lightcurvefilename[i] );
     }
//////////////////////////////////////////////////////////////////////
// Continue with more sensitive (with default threshoulds) variability-detection tests
//
// IQR + MAD
#ifdef CANDIDATE_VAR_SELECTION_WITH_IQR_AND_MAD
#ifdef DISABLE_INDEX_IQR
     fprintf( stderr, "ERROR: DISABLE_INDEX_IQR and CANDIDATE_VAR_SELECTION_WITH_IQR_AND_MAD cannot be set at the same time!\n" );
#endif
#ifdef DISABLE_INDEX_MAD
     fprintf( stderr, "ERROR: DISABLE_INDEX_MAD and CANDIDATE_VAR_SELECTION_WITH_IQR_AND_MAD cannot be set at the same time!\n" );
#else
     if ( 0.0 != index_spread_filtered[i][25] && 0.0 != index_spread_filtered[i][9] ) {
      if ( IQR_AND_MAD__IQR_THRESHOLD < ( index[i][25] - index_filtered[i][25] ) / index_spread_filtered[i][25] && IQR_AND_MAD__MAD_THRESHOLD < ( index[i][9] - index_filtered[i][9] ) / index_spread_filtered[i][9] ) {
       is_this_star_variable= 1;
       strncat( autocandidatesdetails_string, " IQR+MAD ", MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 32 );
       autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 1]= '\0'; // just in case
      }
     }
#endif
#endif
// 1/eta + IQR + MAD
#ifdef CANDIDATE_VAR_SELECTION_WITH_ETA_AND_IQR_AND_MAD
#ifdef DISABLE_INDEX_MAD
     fprintf( stderr, "ERROR: DISABLE_INDEX_MAD and CANDIDATE_VAR_SELECTION_WITH_ETA_AND_IQR_AND_MAD cannot be set at the same time!\n" );
#endif
#ifdef DISABLE_INDEX_IQR
     fprintf( stderr, "ERROR: DISABLE_INDEX_IQR and CANDIDATE_VAR_SELECTION_WITH_ETA_AND_IQR_AND_MAD cannot be set at the same time!\n" );
#endif
#ifdef DISABLE_INDEX_VONNEUMANN_RATIO
     fprintf( stderr, "ERROR: DISABLE_INDEX_VONNEUMANN_RATIO and CANDIDATE_VAR_SELECTION_WITH_ETA_AND_IQR_AND_MAD cannot be set at the same time!\n" );
#else
     if ( 0.0 != index_spread_filtered[i][21] && 0.0 != index_spread_filtered[i][25] && 0.0 != index_spread_filtered[i][9] ) {
      if ( ETA_AND_IQR_AND_MAD__ETA_THRESHOLD < ( index[i][21] - index_filtered[i][21] ) / index_spread_filtered[i][21] && ETA_AND_IQR_AND_MAD__IQR_THRESHOLD < ( index[i][25] - index_filtered[i][25] ) / index_spread_filtered[i][25] && ETA_AND_IQR_AND_MAD__MAD_THRESHOLD < ( index[i][9] - index_filtered[i][9] ) / index_spread_filtered[i][9] ) {
       is_this_star_variable= 1;
       strncat( autocandidatesdetails_string, " eta+IQR+MAD ", MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 32 );
       autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 1]= '\0'; // just in case
      }
     }
#endif
#endif
// 1/eta + STD
#ifdef CANDIDATE_VAR_SELECTION_WITH_ETA_AND_CLIPPED_SIGMA
#ifdef DISABLE_INDEX_WEIGHTED_SIGMA
     fprintf( stderr, "ERROR: DISABLE_INDEX_WEIGHTED_SIGMA and CANDIDATE_VAR_SELECTION_WITH_ETA_AND_CLIPPED_SIGMA cannot be set at the same time!\n" );
#endif
#ifdef DISABLE_INDEX_VONNEUMANN_RATIO
     fprintf( stderr, "ERROR: DISABLE_INDEX_VONNEUMANN_RATIO and CANDIDATE_VAR_SELECTION_WITH_ETA_AND_CLIPPED_SIGMA cannot be set at the same time!\n" );
#else
     if ( 0.0 != index_spread_filtered[i][21] && 0.0 != index_spread_filtered[i][0] ) {
      if ( ETA_AND_CLIPPED_SIGMA__ETA_THRESHOLD < ( index[i][21] - index_filtered[i][21] ) / index_spread_filtered[i][21] && ETA_AND_CLIPPED_SIGMA__CLIPPED_SIGMA_THRESHOLD < ( index[i][0] - index_filtered[i][0] ) / index_spread_filtered[i][0] ) {
       is_this_star_variable= 1;
       strncat( autocandidatesdetails_string, " eta+CLIPPED_SIGMA ", MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 32 );
       autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 1]= '\0'; // just in case
      }
     }
#endif
#endif
     //////////////////////////////////////////////////////////////////////
     // Remove variability label if reducedChi2 is low.
     // (the photometric errors are likely underestimated, but not overestimated).
     if ( is_this_star_variable == 1 ) {
#ifdef DISABLE_INDEX_REDUCED_CHI2
      fprintf( stderr, "ERROR: DISABLE_INDEX_REDUCED_CHI2 should not be set while automated candidate variables selectio nis enabled!\n" );
#endif
      //
      if ( index[i][12] != INVALID_INDEX_VALUE ) {
       if ( REQUIRED_MIN_CHI2RED_FOR_ALL_CANDIDATE_VAR > index[i][12] ) {
        is_this_star_variable= 0;
        strncat( autocandidatesdetails_string, " -MIN_CHI2RED ", MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 32 );
        autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 1]= '\0'; // just in case
       }
      }
     }
     //////////////////////////////////////////////////////////////////////
     // Remove variability flag from the few brightes and faintest stars
     // here we rely on the fact that the input list is sorted in mag
     // Exclude faint stars from the list
     if ( i < MIN( (int)( DROP_FRACTION_OF_BRIGHTEST_VARIABLE_STARS * (double)n_stars_in_lightcurve_statistics_file + 0.5 ), DROP_MAX_NUMBER_OF_BRIGHTEST_VARIABLE_STARS ) ) {
      is_this_star_variable= 0;
      strncat( autocandidatesdetails_string, " -FRACTION_OF_BRIGHTEST_VARIABLE_STARS ", MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 32 );
      autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 1]= '\0'; // just in case
     }
     // Exclude faint stars from the list
     if ( i > n_stars_in_lightcurve_statistics_file - (int)( DROP_FRACTION_OF_FAINTEST_VARIABLE_STARS * (double)n_stars_in_lightcurve_statistics_file + 0.5 ) ) {
      is_this_star_variable= 0;
      strncat( autocandidatesdetails_string, " -FRACTION_OF_FAINTEST_VARIABLE_STARS ", MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 32 );
      autocandidatesdetails_string[MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS - 1]= '\0'; // just in case
     }
     //////////////////////////////////////////////////////////////////////
     //
     fprintf( autocandidatesdetailsfile, "%s\n", autocandidatesdetails_string );
     //////////////////////////////////////////////////////////////////////
     // If this is a vairbale star
     if ( is_this_star_variable == 1 ) {
      fprintf( autocandidatesfile, "%s\n", lightcurvefilename[i] );
      fprintf( stderr, "." );
     }
     // If this doesn't seem to be variables - write to sysrem input list
     if ( is_this_star_variable == 0 ) {
      // For the vast_list_of_likely_constant_stars.log we want even more strict criterea
      ////////// Criterea for listing a star as a likely constant one //////
      is_this_star_constant= 0; // reset the flag
// MAD
#ifndef DISABLE_INDEX_MAD
          //if( fabs(index[i][9]-index_filtered[i][9])/index_spread_filtered[i][9]<CONSTANT_STARS__MAD_THRESHOLD ){
      if ( ( index[i][9] - index_filtered[i][9] ) / index_spread_filtered[i][9] < CONSTANT_STARS__MAD_THRESHOLD ) {
       if ( is_this_star_constant == 1 )
        is_this_star_constant= 1;
      } else {
       continue;
      }
#endif
// IQR
#ifndef DISABLE_INDEX_IQR
      //if( fabs(index[i][25]-index_filtered[i][25])/index_spread_filtered[i][25]<CONSTANT_STARS__IQR_THRESHOLD ){
      if ( ( index[i][25] - index_filtered[i][25] ) / index_spread_filtered[i][25] < CONSTANT_STARS__IQR_THRESHOLD ) {
       is_this_star_constant= 1;
      } else {
       continue;
      }
#endif
// 1/eta
#ifndef DISABLE_INDEX_VONNEUMANN_RATIO
      //if( fabs(index[i][21]-index_filtered[i][21])/index_spread_filtered[i][21]<CONSTANT_STARS__ETA_THRESHOLD ){
      if ( ( index[i][21] - index_filtered[i][21] ) / index_spread_filtered[i][21] < CONSTANT_STARS__ETA_THRESHOLD ) {
       if ( is_this_star_constant == 1 )
        is_this_star_constant= 1;
      } else {
       continue;
      }
#endif
// weighted sigma
#ifndef DISABLE_INDEX_WEIGHTED_SIGMA
      //if( fabs(index[i][1]-index_filtered[i][1])/index_spread_filtered[i][1]<CONSTANT_STARS__WEIGHTED_SIGMA_THRESHOLD ){
      if ( ( index[i][1] - index_filtered[i][1] ) / index_spread_filtered[i][1] < CONSTANT_STARS__WEIGHTED_SIGMA_THRESHOLD ) {
       if ( is_this_star_constant == 1 )
        is_this_star_constant= 1;
      } else {
       continue;
      }
#endif
      // clipped sigma
      //if( fabs(index[i][0]-index_filtered[i][0])/index_spread_filtered[i][0]<CONSTANT_STARS__CLIPPED_SIGMA_THRESHOLD ){
      if ( ( index[i][0] - index_filtered[i][0] ) / index_spread_filtered[i][0] < CONSTANT_STARS__CLIPPED_SIGMA_THRESHOLD ) {
       if ( is_this_star_constant == 1 )
        is_this_star_constant= 1;
      } else {
       continue;
      }
// RoMS -- we also don't want lightcurve with incorrectly estimated errors (compared to other stars of the same brightenss)
#ifndef DISABLE_INDEX_ROMS
      if ( fabs( index[i][11] - index_filtered[i][11] ) / index_spread_filtered[i][11] < CONSTANT_STARS__RoMS_THRESHOLD ) {
       if ( is_this_star_constant == 1 )
        is_this_star_constant= 1;
      } else {
       continue;
      }
#endif
      // here we rely on the fact that the input list is sorted in mag
      // Exclude faint stars from the list
      if ( i < (int)( DROP_FRACTION_OF_BRIGHTEST_CONST_STARS * (double)n_stars_in_lightcurve_statistics_file + 0.5 ) ) {
       is_this_star_constant= 0;
      }
      // Exclude faint stars from the list
      if ( i > n_stars_in_lightcurve_statistics_file - (int)( DROP_FRACTION_OF_FAINTEST_CONST_STARS * (double)n_stars_in_lightcurve_statistics_file + 0.5 ) ) {
       is_this_star_constant= 0;
      }
      //////////////////////////////////////////////////////////////////////
      if ( is_this_star_constant == 1 ) {
       fprintf( vast_list_of_likely_constant_stars, "%s\n", lightcurvefilename[i] );
       // OK this is a silly way to write this with all the continue and if( is_this_star_constant==1 ) checks, but should work
      }
     } // if( is_this_star_variable==0 ){
    }  // // Loop through all the stars
    fclose( vast_list_of_likely_constant_stars );
   } // if( NULL != vast_list_of_likely_constant_stars ){
   else {
    fprintf( stderr, "ERROR: cannot open file vast_list_of_likely_constant_stars.log for writing\n" );
   }
   fclose( sysrem_input_star_list_file );
  } else {
   fprintf( stderr, "ERROR: cannot open file sysrem_input_star_list.lst for writing\n" );
  }
  fclose( autocandidatesfile );
  fprintf( stderr, "\n" );
 } else {
  fprintf( stderr, "ERROR: cannot open file vast_autocandidates.log for writing\n" );
 }
 fclose( autocandidatesdetailsfile );
 //////////////////////////////////////////////////////////////////////////////

 // If there is a file vast_list_of_previously_known_variables.log with a list of conwn vars
 //list_of_known_vars_file=fopen("vast_autocandidates.log","r");
 list_of_known_vars_file= fopen( "vast_list_of_previously_known_variables.log", "r" );
 if ( NULL != list_of_known_vars_file ) {
  n_known_variables= 0;
  full_string_autocandidates[0]= '\0';
  while ( NULL != fgets( full_string_autocandidates, MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG, list_of_known_vars_file ) ) {
   sscanf( full_string_autocandidates, "%s %[^\t\n]", known_variable_lightcurvefilename[n_known_variables], comments_string_autocandidates );
   // Count this star only if it's actually among the detected ones
   for ( i= 0; i < n_stars_in_lightcurve_statistics_file; i++ ) {
    if ( 0 == strncmp( lightcurvefilename[i], known_variable_lightcurvefilename[n_known_variables], OUTFILENAME_LENGTH ) ) {
     fprintf( stderr, "Known variable %s \n", known_variable_lightcurvefilename[n_known_variables] );
     n_known_variables++;
     break;
    }
   }
   full_string_autocandidates[0]= '\0';
  }
  fprintf( stderr, "Marking %d known variable stars in the field.\n", n_known_variables );

  l= 0; // use this counter as a flag for Cmax
  // M31 - fixed 3 sigma threshould
  //for ( threshold= 3.0; threshold < 3.1; threshold+= 0.1 ) {
   // Normal threshould fine-tuning
   for( threshold=0.0; threshold<50.0; threshold+=0.1 ){

   fprintf( stderr, "Selecting candidates with threshold=%lf sigma in each index\r", threshold );

   // reset the counters for all indexes
   for ( j= 0; j < MAX_NUMBER_OF_INDEXES_TO_STORE; j++ ) {
    number_of_selected_objects[j]= number_of_selected_variables[j]= 0;
   }
   // For each star
   for ( i= 0; i < n_stars_in_lightcurve_statistics_file; i++ ) {
    // compare its indexes with a threshold
    for ( j= 0; j < MAX_NUMBER_OF_INDEXES_TO_STORE; j++ ) {
     if ( index[i][j] > index_filtered[i][j] + threshold * index_spread_filtered[i][j] ) {
      number_of_selected_objects[j]++; // count this one as selected object
      // check if this is one of the known variables
      for ( k= 0; k < n_known_variables; k++ ) {
       if ( 0 == strncmp( known_variable_lightcurvefilename[k], lightcurvefilename[i], OUTFILENAME_LENGTH ) ) {
        number_of_selected_variables[j]++;
        break; // there should be only one match anyway
       }       // if( 0==strncmp(known_variable_lightcurvefilename[k],lightcurvefilename[i],OUTFILENAME_LENGTH) ){
      }        // for( k=0;k<n_known_variables;k++){
     }         // if( fabs(index[i][j])>index_filtered[i][j]+threshold*index_spread_filtered[i][j] ){
    }          // for(j=0;j<MAX_NUMBER_OF_INDEXES_TO_STORE;j++){
   }           // for(i=0;i<n_stars_in_lightcurve_statistics_file;i++){

   // Print the resulting statistic for each index
   for ( j= 0; j < MAX_NUMBER_OF_INDEXES_TO_STORE; j++ ) {
    C= (double)number_of_selected_variables[j] / (double)n_known_variables;
    P= (double)number_of_selected_variables[j] / (double)number_of_selected_objects[j];
    F= 2.0 * ( C * P ) / ( C + P );
    //double beta=50.0;
    //F = (1.0+beta*beta) * (C * P)/(C + beta*beta*P);
    // This is just to make the output look better
    if ( 0 != isnan( C ) )
     C= 0.0;
    if ( 0 != isnan( P ) )
     P= 0.0;
    if ( 0 != isnan( F ) )
     F= 0.0;
    //
    get_index_name( j, short_index_name );
    fprintf( stdout, "%6.3lf  %s   %lf %lf %lf   %5d  %5d  %5d\n", threshold, short_index_name, C, P, F, number_of_selected_variables[j], number_of_selected_objects[j], n_known_variables );
    //
    if ( F > Fmax[j] ) {
     Fmax[j]= F;
     C_at_Fmax[j]= C;
     P_at_Fmax[j]= P;
     threshold_at_Fmax[j]= threshold;
     fraction_of_obj_rejected_at_Fmax[j]= 1.0 - (double)number_of_selected_objects[j] / (double)n_stars_in_lightcurve_statistics_file;
    }
    // If this is the first iteration (the one with the lowest threshold)
    // set the maximum completeness values Cmax[j]
    if ( l == 0 ) {
     Cmax[j]= C;
    }
    // In case at first iteration C was zero
    if ( C > Cmax[j] )
     Cmax[j]= C;
    // Check if what is the purity if we are still at the maximum completeness level
    if ( C == Cmax[j] ) {
     P_at_Cmax[j]= P;
     threshold_at_Cmax[j]= threshold;
     fraction_of_obj_rejected_at_Cmax[j]= 1.0 - (double)number_of_selected_objects[j] / (double)n_stars_in_lightcurve_statistics_file;
    }
   }

   l++; // so we don't change Cmax[j] after the first iteration

  }                        // for( threshold=0.1; threshold<5.0; threshold+=1.0 ){
  fprintf( stderr, "\n" ); // to terminate the \r output

  fclose( list_of_known_vars_file ); // close the file with known variables

  // Write detection efficeincy summary
  vast_detection_efficiency_log= fopen( "vast_detection_efficiency.log", "w" );
  if ( NULL == vast_detection_efficiency_log ) {
   fprintf( stderr, "ERROR: opening file vast_detection_efficiency.log for writing!\n" );
   exit( 1 );
  }
  fprintf( vast_detection_efficiency_log, "#   Index    threshold_at_Fmax threshold_at_Cmax C_at_Fmax P_at_Fmax  Fmax     Cmax   P_at_Cmax fraction_of_obj_rejected_at_Cmax fraction_of_obj_rejected_at_Fmax #\n" );
  for ( j= 0; j < MAX_NUMBER_OF_INDEXES_TO_STORE; j++ ) {
   get_index_name( j, short_index_name );
   fprintf( vast_detection_efficiency_log, "  %s    %7.4lf          %7.4lf          %.5lf   %.5lf  %.5lf  %.5lf  %.5lf              %.5lf                       %.5lf\n", short_index_name, threshold_at_Fmax[j], threshold_at_Cmax[j], C_at_Fmax[j], P_at_Fmax[j], Fmax[j], Cmax[j], P_at_Cmax[j], fraction_of_obj_rejected_at_Cmax[j], fraction_of_obj_rejected_at_Fmax[j] );
  }
  fclose( vast_detection_efficiency_log );

 } // if( NULL!=list_of_known_vars_file ){
 else {
  // No list of known variables
  // We are supposed to write one, not create detection efficiency stats!
  for ( j= 0; j < MAX_NUMBER_OF_INDEXES_TO_STORE; j++ ) {
   threshold_at_Fmax[j]= 1.0; // is that enough??? what about the other uninitialized stuff??
   //
  }
  //threshold_at_Fmax[9]=IQR_AND_MAD__MAD_THRESHOLD;
  //for HCV debugging
  threshold_at_Fmax[9]= 5.0;
  //
  threshold_at_Fmax[25]= IQR_AND_MAD__IQR_THRESHOLD;
 }

 // Print results
 lightcurve_statistics_expected_file= fopen( "vast_lightcurve_statistics_expected.log", "w" );
 lightcurve_statistics_spread_file= fopen( "vast_lightcurve_statistics_spread.log", "w" );
 lightcurve_statistics_expected_plus_spread_file= fopen( "vast_lightcurve_statistics_expected_plus_spread.log", "w" );
 lightcurve_statistics_expected_plus_spread_file_Cmax= fopen( "vast_lightcurve_statistics_expected_plus_spread_Cmax.log", "w" );
 lightcurve_statistics_expected_minus_spread_file= fopen( "vast_lightcurve_statistics_expected_minus_spread.log", "w" );
 lightcurve_statistics_normalized_file= fopen( "vast_lightcurve_statistics_normalized.log", "w" );
 for ( i= 0; i < n_stars_in_lightcurve_statistics_file; i++ ) {
  fprintf( lightcurve_statistics_expected_file, "%lf %lf 0 0 0 ", array_of_magnitudes[i], index_filtered[i][0] );
  fprintf( lightcurve_statistics_spread_file, "%lf %lf 0 0 0 ", array_of_magnitudes[i], index_spread_filtered[i][0] );
  // Why don't have the same thing within the for loop and start from j=zero ??????????????
  // Ah yes, that is because we have to put 0's in colums that are not indexes...
  //fprintf(lightcurve_statistics_expected_plus_spread_file,"%lf %lf 0 0 0 ",array_of_magnitudes[i],index_filtered[i][0]+index_spread_filtered[i][0]);
  //fprintf(lightcurve_statistics_expected_minus_spread_file,"%lf %lf 0 0 0 ",array_of_magnitudes[i],index_filtered[i][0]-index_spread_filtered[i][0]);
  fprintf( lightcurve_statistics_expected_plus_spread_file, "%lf %lf 0 0 0 ", array_of_magnitudes[i], index_filtered[i][0] + threshold_at_Fmax[0] * index_spread_filtered[i][0] );
  fprintf( lightcurve_statistics_expected_plus_spread_file_Cmax, "%lf %lf 0 0 0 ", array_of_magnitudes[i], index_filtered[i][0] + threshold_at_Cmax[0] * index_spread_filtered[i][0] );
  fprintf( lightcurve_statistics_expected_minus_spread_file, "%lf %lf 0 0 0 ", array_of_magnitudes[i], index_filtered[i][0] - threshold_at_Fmax[0] * index_spread_filtered[i][0] );
  fprintf( lightcurve_statistics_normalized_file, "%+10.6lf %+12.6lf 0 0 %s ", array_of_magnitudes[i], ( index[i][0] - index_filtered[i][0] ) / index_spread_filtered[i][0], lightcurvefilename[i] );
  for ( j= 1; j < MAX_NUMBER_OF_INDEXES_TO_STORE; j++ ) {
   for ( output_file_counter= 0; output_file_counter < 6; output_file_counter++ ) {
    tmp_d_value_to_print= 0.0; // initialize to make valgrind happy
    if ( output_file_counter == 0 ) {
     output_filedescriptor= lightcurve_statistics_expected_file;
     tmp_d_value_to_print= index_filtered[i][j];
    }
    if ( output_file_counter == 1 ) {
     output_filedescriptor= lightcurve_statistics_spread_file;
     tmp_d_value_to_print= index_spread_filtered[i][j];
    }
    if ( output_file_counter == 2 ) {
     output_filedescriptor= lightcurve_statistics_expected_plus_spread_file;
     tmp_d_value_to_print= index_filtered[i][j] + threshold_at_Fmax[j] * index_spread_filtered[i][j];
    }
    if ( output_file_counter == 3 ) {
     output_filedescriptor= lightcurve_statistics_expected_plus_spread_file_Cmax;
     tmp_d_value_to_print= index_filtered[i][j] + threshold_at_Cmax[j] * index_spread_filtered[i][j];
    }
    if ( output_file_counter == 4 ) {
     output_filedescriptor= lightcurve_statistics_expected_minus_spread_file;
     tmp_d_value_to_print= index_filtered[i][j] - threshold_at_Fmax[j] * index_spread_filtered[i][j];
    }
    if ( output_file_counter == 5 ) {
     output_filedescriptor= lightcurve_statistics_normalized_file;
     // We want to avoid inf vlaues in the output file
     if ( 0.0 != index_spread_filtered[i][j] ) {
      tmp_d_value_to_print= ( index[i][j] - index_filtered[i][j] ) / index_spread_filtered[i][j];
     } else {
      tmp_d_value_to_print= 0.0;
     }
    }

    // Print the result to the file
    if ( tmp_d_value_to_print >= 100000.0 || tmp_d_value_to_print <= 0.0001 ) {
     fprintf( output_filedescriptor, "%+12.6lg ", tmp_d_value_to_print );
    } else {
     fprintf( output_filedescriptor, "%+12.6lf ", tmp_d_value_to_print );
    }
   }
   /*
   fprintf(lightcurve_statistics_expected_file,"%lf ",index_filtered[i][j]);
   fprintf(lightcurve_statistics_spread_file,"%lf ",index_spread_filtered[i][j]);
   //fprintf(lightcurve_statistics_expected_plus_spread_file,"%lf ",index_filtered[i][j]+index_spread_filtered[i][j]);
   fprintf(lightcurve_statistics_expected_plus_spread_file,"%lf ",index_filtered[i][j]+threshold_at_Fmax[j]*index_spread_filtered[i][j]);
   fprintf(lightcurve_statistics_expected_plus_spread_file_Cmax,"%lf ",index_filtered[i][j]+threshold_at_Cmax[j]*index_spread_filtered[i][j]);
   //fprintf(lightcurve_statistics_expected_minus_spread_file,"%lf ",index_filtered[i][j]-index_spread_filtered[i][j]);
   fprintf(lightcurve_statistics_expected_minus_spread_file,"%lf ",index_filtered[i][j]-threshold_at_Fmax[j]*index_spread_filtered[i][j]);
   //// Special trouble to make the output look good
   tmp_d_value_to_print=(index[i][j]-index_filtered[i][j])/index_spread_filtered[i][j];
   if( tmp_d_value_to_print>=100000.0 || tmp_d_value_to_print<=0.000001 )
    fprintf(lightcurve_statistics_normalized_file,"%+12.6lg ",tmp_d_value_to_print);
   else
    fprintf(lightcurve_statistics_normalized_file,"%+12.6lf ",tmp_d_value_to_print);
   ////
   */
  }
  fprintf( lightcurve_statistics_expected_file, "\n" );
  fprintf( lightcurve_statistics_spread_file, "\n" );
  fprintf( lightcurve_statistics_expected_plus_spread_file, "\n" );
  fprintf( lightcurve_statistics_expected_plus_spread_file_Cmax, "\n" );
  fprintf( lightcurve_statistics_expected_minus_spread_file, "\n" );
  fprintf( lightcurve_statistics_normalized_file, "\n" );
 }
 fclose( lightcurve_statistics_normalized_file );
 fclose( lightcurve_statistics_expected_minus_spread_file );
 fclose( lightcurve_statistics_expected_plus_spread_file );
 fclose( lightcurve_statistics_expected_plus_spread_file_Cmax );
 fclose( lightcurve_statistics_spread_file );
 fclose( lightcurve_statistics_expected_file );

 // Clean up
 for ( i= 0; i < n_stars_in_lightcurve_statistics_file; i++ ) {
  free( index[i] );
  free( index_expected[i] );
  free( index_filtered[i] );
  free( index_spread_filtered[i] );
  free( index_spread[i] );
  free( lightcurvefilename[i] );
  free( known_variable_lightcurvefilename[i] );
 }
 free( index );
 free( index_expected );
 free( index_filtered );
 free( index_spread_filtered );
 free( index_spread );
 free( index_for_stat );
 free( array_of_magnitudes );
 free( lightcurvefilename );
 free( known_variable_lightcurvefilename );

 return 0;
}
