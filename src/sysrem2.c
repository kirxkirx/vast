/*

  This is a loose implementation of the SysRem algorithm
  proposed by Tamuz, O.; Mazeh, T.; Zucker, S. 2005 MNRAS, 356, 1466
  http://adsabs.harvard.edu/abs/2005MNRAS.356.1466T
  see also Roberts et al. 2013, MNRAS, 435, 3639
  http://adsabs.harvard.edu/abs/2013MNRAS.435.3639R

*/

#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>

// Include omp.h ONLY if VaST compiler flag is requesting it
// Include omp.h ONLY if the compiler supports OpenMP
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#include <omp.h> // for omp_get_num_threads() and omp_set_num_threads()
#endif
#endif

#include <gsl/gsl_statistics.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_errno.h>

#include "vast_limits.h"
#include "lightcurve_io.h"
#include "variability_indexes.h" // for esimate_sigma_from_MAD_of_unsorted_data()

#include "get_dates_from_lightcurve_files_function.h"

#include "get_number_of_cpu_cores.h" // for get_number_of_cpu_cores()

int split_sysrem_input_star_list_lst( char **split_sysrem_input_star_list_lst_filenames, int *N_sysrem_input_star_list_lst ) {

 FILE *input_sysrem_input_star_list_lst;
 FILE **outputfile;
 int Nstars, Noutput_files, oputput_file_counter;
 char full_string[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG];

 outputfile= malloc( SYSREM_MAX_NUMBER_OF_PROCESSING_BLOCKS * sizeof( FILE * ) );

 Nstars= 0;
 input_sysrem_input_star_list_lst= fopen( "sysrem_input_star_list.lst", "r" );
 if ( NULL == input_sysrem_input_star_list_lst ) {
  fprintf( stderr, "ERROR! Can't open file sysrem_input_star_list.lst\n" );
  exit( 1 );
 }
 while ( NULL != fgets( full_string, MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG, input_sysrem_input_star_list_lst ) ) {
  Nstars++;
 }
 fclose( input_sysrem_input_star_list_lst );
 fprintf( stderr, "Number of stars in sysrem_input_star_list.lst %d\n", Nstars );
 if ( Nstars < SYSREM_MIN_NUMBER_OF_STARS ) {
  fprintf( stderr, "Too few stars!\n" );
  exit( 1 );
 }

 // This is the trivial case of one processing block
 if ( Nstars < 2 * SYSREM_N_STARS_IN_PROCESSING_BLOCK ) {
  strncpy( split_sysrem_input_star_list_lst_filenames[0], "sysrem_input_star_list.lst", 27 );
  ( *N_sysrem_input_star_list_lst )= 1;
  free( outputfile );
  return 0;
 }

 // Split the input sysrem_input_star_list.lst into Noutput_files
 Noutput_files= (int)( (double)Nstars / (double)SYSREM_N_STARS_IN_PROCESSING_BLOCK );
 Noutput_files= MIN( Noutput_files, SYSREM_MAX_NUMBER_OF_PROCESSING_BLOCKS );
 fprintf( stderr, "Will split sysrem_input_star_list.lst into %d processing blocks\n", Noutput_files );

 // open the output files
 for ( oputput_file_counter= 0; oputput_file_counter < Noutput_files; oputput_file_counter++ ) {
  sprintf( split_sysrem_input_star_list_lst_filenames[oputput_file_counter], "sysrem_input_star_list.lst_%02d", oputput_file_counter );
  outputfile[oputput_file_counter]= fopen( split_sysrem_input_star_list_lst_filenames[oputput_file_counter], "w" );
  if ( NULL == outputfile[oputput_file_counter] ) {
   fprintf( stderr, "ERROR opening file %s for writing\n", split_sysrem_input_star_list_lst_filenames[oputput_file_counter] );
   exit( 1 );
  }
  fprintf( stderr, "Opening file %s for writing\n", split_sysrem_input_star_list_lst_filenames[oputput_file_counter] );
 }

 // Re-open the input file and write its content in the output files
 input_sysrem_input_star_list_lst= fopen( "sysrem_input_star_list.lst", "r" );
 if ( NULL == input_sysrem_input_star_list_lst ) {
  fprintf( stderr, "ERROR! Can't open file sysrem_input_star_list.lst (2)\n" );
  exit( 1 );
 }
 oputput_file_counter= 0;
 while ( NULL != fgets( full_string, MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG, input_sysrem_input_star_list_lst ) ) {
  fputs( full_string, outputfile[oputput_file_counter] );
  oputput_file_counter++;
  if ( oputput_file_counter == Noutput_files ) {
   oputput_file_counter= 0;
  }
 }
 fclose( input_sysrem_input_star_list_lst );
 fprintf( stderr, "Number of stars in sysrem_input_star_list.lst %d\n", Nstars );
 if ( Nstars < SYSREM_MIN_NUMBER_OF_STARS ) {
  fprintf( stderr, "Too few stars!\n" );
  exit( 1 );
 }

 // close the output files
 for ( oputput_file_counter= 0; oputput_file_counter < Noutput_files; oputput_file_counter++ ) {
  fclose( outputfile[oputput_file_counter] );
 }
 free( outputfile );

 ( *N_sysrem_input_star_list_lst )= Noutput_files;

 // exit( 1 ); // !!!!!!!!!!!!

 return 0;
}

void change_number_of_sysrem_iterations_in_log_file() {
 FILE *logfilein;
 FILE *logfileout;
 int number_of_iterations= 0;
 char str[2048];
 logfilein= fopen( "vast_summary.log", "r" );
 if ( logfilein != NULL ) {
  logfileout= fopen( "vast_summary.log.tmp", "w" );
  if ( logfileout == NULL ) {
   fclose( logfilein );
   return;
  }
  while ( NULL != fgets( str, 2048, logfilein ) ) {
   if ( str[0] == 'N' && str[1] == 'u' && str[2] == 'm' && str[10] == 'S' && str[13] == 'R' ) {
    sscanf( str, "Number of SysRem iterations: %d", &number_of_iterations );
    sprintf( str, "Number of SysRem iterations: %d\n", number_of_iterations + 1 );
   }
   fputs( str, logfileout );
  }
  fclose( logfileout );
  fclose( logfilein );
  // rename vast_summary.log.tmp vast_summary.log
  unlink( "vast_summary.log" );
  rename( "vast_summary.log.tmp", "vast_summary.log" );
 }
 return;
}

int main() {
 FILE *lightcurvefile;
 FILE *outlightcurvefile;

 float **mag_err;
 float **r;

 float *c;
 float *a;

 float *old_c;
 float *old_a;

 double *jd;

 int i, j, iter;

 long k;

 double corrected_magnitude, correction_mag;

 double djd;
 // float dmag, dmerr;
 double ddmag, ddmerr, x, y, app;
 char string[FILENAME_LENGTH];
 char comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 char star_number_string[FILENAME_LENGTH];

 char *split_sysrem_input_star_list_lst_filenames[SYSREM_MAX_NUMBER_OF_PROCESSING_BLOCKS];
 int N_sysrem_input_star_list_lst, sysrem_input_star_list_lst_counter;

 int Nobs;
 int Nstars;

 // float *data;
 double *double_data;
 float mean, median, sigma, sum1, sum2;

 FILE *datafile;
 char lightcurvefilename[OUTFILENAME_LENGTH];
 char outlightcurvefilename[OUTFILENAME_LENGTH];

 int stop_iterations= 0;

 // int bad_stars_counter;
 int *bad_stars;
 char **star_numbers;

 float tmpfloat; // for faster computation

 int number_of_cpu_cores_to_report;

 // This will make sysrem_input_star_list.lst
 if ( 0 != system( "lib/index_vs_mag" ) ) {
  fprintf( stderr, "ERROR in sysrem2.c while running lib/index_vs_mag\n" );
  exit( 1 );
 }

 for ( sysrem_input_star_list_lst_counter= 0; sysrem_input_star_list_lst_counter < SYSREM_MAX_NUMBER_OF_PROCESSING_BLOCKS; sysrem_input_star_list_lst_counter++ ) {
  split_sysrem_input_star_list_lst_filenames[sysrem_input_star_list_lst_counter]= malloc( FILENAME_LENGTH * sizeof( char ) );
  memset( split_sysrem_input_star_list_lst_filenames[sysrem_input_star_list_lst_counter], 0, FILENAME_LENGTH ); // just in case
 }
 split_sysrem_input_star_list_lst( split_sysrem_input_star_list_lst_filenames, &N_sysrem_input_star_list_lst );

 ///////////////////////
 for ( sysrem_input_star_list_lst_counter= 0; sysrem_input_star_list_lst_counter < N_sysrem_input_star_list_lst; sysrem_input_star_list_lst_counter++ ) {

  // Count stars we want to process
  Nstars= 0;
  // datafile= fopen( "sysrem_input_star_list.lst", "r" );
  datafile= fopen( split_sysrem_input_star_list_lst_filenames[sysrem_input_star_list_lst_counter], "r" );
  if ( NULL == datafile ) {
   fprintf( stderr, "ERROR! Can't open file %s\n", split_sysrem_input_star_list_lst_filenames[sysrem_input_star_list_lst_counter] );
   exit( 1 );
  }

  while ( -1 < fscanf( datafile, "%f %f %f %f %s", &mean, &mean, &mean, &mean, lightcurvefilename ) ) {
   Nstars++;
  }
  fclose( datafile );
  fprintf( stderr, "Number of stars in sysrem_input_star_list.lst %d\n", Nstars );
  if ( Nstars < SYSREM_MIN_NUMBER_OF_STARS ) {
   fprintf( stderr, "Too few stars!\n" );
   exit( 1 );
  }

  bad_stars= malloc( Nstars * sizeof( int ) );
  if ( bad_stars == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for bad_stars\n" );
   exit( 1 );
  };
  star_numbers= malloc( Nstars * sizeof( char * ) );
  if ( star_numbers == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for star_numbers\n" );
   exit( 1 );
  };
  // for(i=0;i<Nstars;i++){
  for ( i= Nstars; i--; ) {
   star_numbers[i]= malloc( OUTFILENAME_LENGTH * sizeof( char ) );
   if ( star_numbers[i] == NULL ) {
    fprintf( stderr, "ERROR: Couldn't allocate memory for star_numbers[i]\n" );
    exit( 1 );
   };
   bad_stars[i]= 0;
  }

  // Read the log file
  jd= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
  if ( jd == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for jd\n" );
   exit( 1 );
  }
  Nobs= 0; // initialize it here, just in case
  get_dates( jd, &Nobs );
  if ( Nobs <= 0 ) {
   fprintf( stderr, "ERROR: Trying allocate zero or negative memory amount(Nobs <= 0)\n" );
   exit( 1 );
  };

  // Allocate memory
  mag_err= malloc( Nstars * sizeof( float * ) );
  if ( mag_err == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for mag_err\n" );
   exit( 1 );
  }
  r= malloc( Nstars * sizeof( float * ) );
  if ( r == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for r\n" );
   exit( 1 );
  }

  /*
 data= malloc( Nstars * Nobs * sizeof( float ) ); // ??
 if ( data == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for data\n" );
  exit( 1 );
 }
*/

  // Moved below
  /*
 //double_data_Nstars= malloc( Nstars * Nobs * sizeof( double ) );
 double_data= malloc( MAX( Nstars, Nobs ) * sizeof( double ) );
 if ( double_data == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for double_data_Nstars\n" );
  exit( 1 );
 }
*/

  // for(i=0;i<Nstars;i++){
  for ( i= Nstars; i--; ) {
   mag_err[i]= malloc( Nobs * sizeof( float ) ); // !!
   r[i]= malloc( Nobs * sizeof( float ) );       // is it correct ????? // !!
   if ( r[i] == NULL || mag_err[i] == NULL ) {
    fprintf( stderr, "ERROR: Couldn't allocate memory(i=%d)\n", i );
    exit( 1 );
   }
  }

  // for(i=0;i<Nstars;i++)
  for ( i= Nstars; i--; ) {
   // for(j=0;j<Nobs;j++)
   for ( j= Nobs; j--; ) {
    r[i][j]= 0.0;
   }
  }

  c= malloc( Nstars * sizeof( float ) );
  if ( c == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for c array\n" );
   exit( 1 );
  }
  a= malloc( Nobs * sizeof( float ) );
  if ( a == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for a array\n" );
   exit( 1 );
  }

  old_c= malloc( Nstars * sizeof( float ) );
  if ( old_c == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for old_c\n" );
   exit( 1 );
  }
  old_a= malloc( Nobs * sizeof( float ) );
  if ( old_a == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for ald_a\n" );
   exit( 1 );
  }

  // for(i=0;i<Nstars;i++){
  for ( i= Nstars; i--; ) {
   c[i]= 0.1;
   old_c[i]= 0.1;
  }

  // for(i=0;i<Nobs;i++){
  for ( i= Nobs; i--; ) {
   a[i]= 1.0;
   old_a[i]= 1.0;
  }

  // Read the data
  i= j= 0;
  // datafile= fopen( "sysrem_input_star_list.lst", "r" );
  datafile= fopen( split_sysrem_input_star_list_lst_filenames[sysrem_input_star_list_lst_counter], "r" );
  if ( NULL == datafile ) {
   fprintf( stderr, "ERROR! Can't open file %s\n", split_sysrem_input_star_list_lst_filenames[sysrem_input_star_list_lst_counter] );
   exit( 1 );
  }
  while ( -1 < fscanf( datafile, "%f %f %f %f %s", &mean, &mean, &mean, &mean, lightcurvefilename ) ) {
   memset( star_number_string, 0, FILENAME_LENGTH ); // just in case
   // Get star number from the lightcurve file name
   for ( k= 3; k < (long)strlen( lightcurvefilename ); k++ ) {
    star_number_string[k - 3]= lightcurvefilename[k];
    if ( lightcurvefilename[k] == '.' ) {
     star_number_string[k - 3]= '\0';
     break;
    }
   }
   strncpy( star_numbers[i], star_number_string, OUTFILENAME_LENGTH );
   star_numbers[i][OUTFILENAME_LENGTH - 1]= '\0';
   lightcurvefile= fopen( lightcurvefilename, "r" );
   if ( NULL == lightcurvefile ) {
    fprintf( stderr, "ERROR: Can't read file %s\n", lightcurvefilename );
    exit( 1 );
   }
   memset( string, 0, FILENAME_LENGTH );
   memset( comments_string, 0, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE );
   // while ( -1 < read_lightcurve_point( lightcurvefile, &djd, &ddmag, &ddmerr, &x, &y, &app, string, comments_string ) ) {
   while ( -1 < read_lightcurve_point( lightcurvefile, &djd, &ddmag, &ddmerr, NULL, &y, &app, string, comments_string ) ) {
    if ( djd == 0.0 )
     continue; // if this line could not be parsed, try the next one
    // dmag= (float)ddmag;
    // dmerr= (float)ddmerr;
    //  Find which j is corresponding to the current JD
    for ( k= 0; k < Nobs; k++ ) {
     if ( fabs( jd[k] - djd ) <= 0.00001 ) { // 0.8 sec
                                             // if( fabs(jd[k]-djd)<=0.0001 ){ // 8 sec
      j= k;
      r[i][j]= (float)ddmag;
      mag_err[i][j]= (float)ddmerr;
      break;
     }
    }
   }
   fclose( lightcurvefile );
   i++;
  }
  fclose( datafile );

  ////////////////////////
  // get_number_of_cpu_cores() will set OMP_NUM_THREADS variable
  // in a hope to avoid out-of-memory situation when using OpenMP down below
  number_of_cpu_cores_to_report= get_number_of_cpu_cores();
  // and report the number of CPU cores to the user (just for information)
  fprintf( stderr, "Number of CPU cores: %d\n", number_of_cpu_cores_to_report );

#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
  // tests show that limiting the number of OpenMP threads dramatically improves performance.
  omp_set_num_threads( MIN( number_of_cpu_cores_to_report, 48 ) );
#endif
#endif
  fprintf( stderr, "Number of threads: %d\n", MIN( number_of_cpu_cores_to_report, 48 ) );

  // Do the actual work
  fprintf( stderr, "Computing average magnitudes... " );

  // For each star compute median magnitude and subtract it from all measurements
  // for(i=0;i<Nstars;i++){
  double_data= malloc( Nobs * sizeof( double ) );
  if ( double_data == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for double_data_Nstars\n" );
   exit( 1 );
  }
  for ( i= Nstars; i--; ) {
   k= 0;
   /*
  // No obvious speed-up with OpenMP here
  // data[] array is very big, so we cannot have a private copy of it for each thread!
  #ifdef VAST_ENABLE_OPENMP
   #ifdef _OPENMP
    #pragma omp parallel for private(j) reduction(+: k)
   #endif
  #endif
  */
   // for ( j= 0; j < Nobs; j++ ) {
   for ( j= Nobs; j--; ) {
    if ( r[i][j] != 0.0 ) {
     // data[k]= r[i][j];
     double_data[k]= (double)r[i][j];
     k++;
    }
   }
   //  gsl_sort_float( data, 1, k );
   //  median= gsl_stats_float_median_from_sorted_data( data, 1, k );
   gsl_sort( double_data, 1, k );
   median= gsl_stats_median_from_sorted_data( double_data, 1, k );
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( j )
#endif
#endif
   for ( j= 0; j < Nobs; j++ ) {
    // for(j=Nobs;j--;){
    if ( r[i][j] != 0.0 ) {
     r[i][j]= r[i][j] - median;
    }
   }
   // fprintf(stderr,"DEBUG06\n");
  }
  // fprintf(stderr,"DEBUG07\n");
  free( double_data );

  fprintf( stderr, "done\nStarting iterations...\n" );

  // Iterative search for best c[i] and a[j]
  for ( iter= 0; iter < NUMBER_OF_Ai_Ci_ITERATIONS; iter++ ) {
   fprintf( stderr, "\riteration %4d", iter + 1 );
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i, j, sum1, sum2, tmpfloat )
#endif
#endif
   for ( i= 0; i < Nstars; i++ ) {
    // for(i=Nstars;i--;){
    sum1= sum2= 0.0;
    for ( j= 0; j < Nobs; j++ ) {
     // for(j=Nobs;j--;){
     if ( r[i][j] != 0.0 ) {
      tmpfloat= 1.0f / ( mag_err[i][j] * mag_err[i][j] );
      sum1+= r[i][j] * a[j] * tmpfloat;
      sum2+= a[j] * a[j] * tmpfloat;
     }
    }
    if ( sum1 != 0.0 && sum2 != 0.0 ) {
     old_c[i]= c[i];
     c[i]= sum1 / sum2;
    }
   }

#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i, j, sum1, sum2, tmpfloat )
#endif
#endif
   for ( j= 0; j < Nobs; j++ ) {
    // for(j=Nobs;j--;){
    sum1= sum2= 0.0;
    // for(i=0;i<Nstars;i++){
    for ( i= Nstars; i--; ) {
     if ( r[i][j] != 0.0 ) {
      tmpfloat= 1.0f / ( mag_err[i][j] * mag_err[i][j] );
      sum1+= r[i][j] * c[i] * tmpfloat;
      sum2+= c[i] * c[i] * tmpfloat;
     }
    }
    if ( sum1 != 0.0 && sum2 != 0.0 ) {
     old_a[j]= a[j];
     a[j]= sum1 / sum2;
    }
   }

   //   // More debug
   //   fprintf(stderr, "\nSysRem \"airmass\" coefficients for each image (not the actual airmass, of course):\n");
   //   for( i= Nobs; i--; ) {
   //    fprintf(stderr, "a[%d]=%lf\n", i, a[i]);
   //   }

   // Should we stop now?
   // Yes, if both a and c change by less than Ai_Ci_DIFFERENCE_TO_STOP_ITERATIONS compared to the previous step
   // (for all indexes = stars/images)
   stop_iterations= 1;
   // for(i=0;i<Nstars;i++){
   for ( i= Nstars; i--; ) {
    if ( fabsf( c[i] - old_c[i] ) > Ai_Ci_DIFFERENCE_TO_STOP_ITERATIONS ) {
     stop_iterations= 0;
     break;
    }
   }
   if ( stop_iterations == 1 ) {
    // for(j=0;j<Nobs;j++){
    for ( j= Nobs; j--; ) {
     if ( fabsf( a[j] - old_a[j] ) > Ai_Ci_DIFFERENCE_TO_STOP_ITERATIONS ) {
      stop_iterations= 0;
      break;
     }
    }
   }
   if ( stop_iterations == 1 ) {
    break; // Stop iteretions if they make no difference
   }

  } // Iterative search for best c[i] and a[j]

  fprintf( stderr, "\nRemoving outliers... " );

  double_data= malloc( Nstars * sizeof( double ) );
  if ( double_data == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for double_data\n" );
   exit( 1 );
  }

  // A filtering attempt: if a single star dominates the solution, it should have c~1 while
  // all other stars should have c~0
  k= 0;
  for ( i= Nstars; i--; ) {
   if ( c[i] != 0.0f ) {
    double_data[k]= (double)c[i];
    k++;
   }
  }
  gsl_sort( double_data, 1, k );
  median= (float)gsl_stats_median_from_sorted_data( double_data, 1, k );
  sigma= (float)esimate_sigma_from_MAD_of_sorted_data_and_ruin_input_array( double_data, k );
  free( double_data );
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i )
#endif
#endif
  for ( i= 0; i < Nstars; i++ ) {
   // for ( i= Nstars; i--; ) {
   if ( c[i] != 0.0f ) {
    if ( fabsf( c[i] - median ) > 10.0 * sigma ) {
     //    fprintf( stderr, "EXCLUDING out%s.dat %d  fabsf(c[i]-median)=%f  >10.0*sigma=%f c[i]=%f median=%f\n", star_numbers[i], i, fabsf( c[i] - median ), 10.0 * sigma, c[i], median );
     bad_stars[i]= 1;
    }
   }
  }

  fprintf( stderr, "done\n" );

  /* 2nd pass */

  /////////////////////////////////////////////////////////
  // We marked the bad stars in the first pass
  // Now reset the coefficiants in order to start iterative search
  // in the second pass from scratch
  for ( i= Nstars; i--; ) {
   c[i]= 0.1;
   old_c[i]= 0.1;
  }

  for ( i= Nobs; i--; ) {
   a[i]= 1.0;
   old_a[i]= 1.0;
  }
  /////////////////////////////////////////////////////////

  for ( iter= 0; iter < NUMBER_OF_Ai_Ci_ITERATIONS; iter++ ) {
   fprintf( stderr, "\riteration %4d", iter + 1 );
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i, j, sum1, sum2, tmpfloat )
#endif
#endif
   for ( i= 0; i < Nstars; i++ ) {
    // for(i=Nstars;i--;){
    sum1= sum2= 0.0;
    if ( bad_stars[i] == 0 ) {
     // for(j=0;j<Nobs;j++){
     for ( j= Nobs; j--; ) {
      if ( r[i][j] != 0.0 ) {
       tmpfloat= 1.0f / ( mag_err[i][j] * mag_err[i][j] );
       sum1+= r[i][j] * a[j] * tmpfloat;
       sum2+= a[j] * a[j] * tmpfloat;
      }
     }
    }
    if ( sum1 != 0.0 && sum2 != 0.0 ) {
     old_c[i]= c[i];
     c[i]= sum1 / sum2;
    }
   }

#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i, j, sum1, sum2, tmpfloat )
#endif
#endif
   for ( j= 0; j < Nobs; j++ ) {
    // for(j=Nobs;j--;){
    sum1= sum2= 0.0;
    // !!!!! experimental !!!!! - try to use only a few brightest stars to compute a[j]
    // We assume the array is sorted in magnitude
    for ( i= 0; i < MIN( Nstars, 1000 ); i++ ) {
     // for ( i= Nstars; i--; ) {
     if ( bad_stars[i] == 0 ) {
      if ( r[i][j] != 0.0 ) {
       tmpfloat= 1.0f / ( mag_err[i][j] * mag_err[i][j] );
       sum1+= r[i][j] * c[i] * tmpfloat;
       sum2+= c[i] * c[i] * tmpfloat;
      }
     }
    }
    if ( sum1 != 0.0 && sum2 != 0.0 ) {
     old_a[j]= a[j];
     a[j]= sum1 / sum2;
    }
   }

   //   // More debug
   //   fprintf(stderr, "\nSysRem \"airmass\" coefficients for each image (not the actual airmass, of course):\n");
   //   for( i= Nobs; i--; ) {
   //    fprintf(stderr, "a[%d]=%lf\n", i, a[i]);
   //   }

   // Should we stop now?
   stop_iterations= 1;
   // for(i=0;i<Nstars;i++){
   for ( i= Nstars; i--; ) {
    if ( fabsf( c[i] - old_c[i] ) > Ai_Ci_DIFFERENCE_TO_STOP_ITERATIONS ) {
     stop_iterations= 0;
     break;
    }
   }
   if ( stop_iterations == 1 ) {
    // for(j=0;j<Nobs;j++){
    for ( j= Nobs; j--; ) {
     if ( fabsf( a[j] - old_a[j] ) > Ai_Ci_DIFFERENCE_TO_STOP_ITERATIONS ) {
      stop_iterations= 0;
      break;
     }
    }
   }

   if ( stop_iterations == 1 ) {
    break; // Stop iteretions if they make no difference
   }

  } // Iterative search for best c[i] and a[j]

  fprintf( stderr, "\nRemoving outliers... " );

  double_data= malloc( Nstars * sizeof( double ) );
  if ( double_data == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for double_data_Nstars\n" );
   exit( 1 );
  }

  // Not sure how effective that is, considering that c[i] filtering with the same parameters is also done above...
  // A filtering attempt: if a single star dominates the solution, it should have c~1 while
  // all other stars should have c~0
  k= 0;
  for ( i= Nstars; i--; ) {
   if ( c[i] != 0.0f ) {
    double_data[k]= (double)c[i];
    k++;
   }
  }
  gsl_sort( double_data, 1, k );
  median= (float)gsl_stats_median_from_sorted_data( double_data, 1, k );
  sigma= (float)esimate_sigma_from_MAD_of_sorted_data_and_ruin_input_array( double_data, k );
  free( double_data );
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i )
#endif
#endif
  for ( i= 0; i < Nstars; i++ ) {
   // for ( i= Nstars; i--; ) {
   if ( c[i] != 0.0f ) {
    if ( fabsf( c[i] - median ) > 10.0 * sigma ) {
     //    fprintf( stderr, "EXCLUDING out%s.dat %d  fabsf(c[i]-median)=%f  >10.0*sigma=%f c[i]=%f median=%f\n", star_numbers[i], i, fabsf( c[i] - median ), 10.0 * sigma, c[i], median );
     bad_stars[i]= 1;
    }
   }
  }

  fprintf( stderr, "done\n" );

  // Apply corrections to lightcurves
  fprintf( stderr, "Applying corrections... \n" );
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
// #pragma omp parallel for private( i, lightcurvefilename, lightcurvefile, djd, ddmag, ddmerr, x, y, app, string, comments_string, dmag, dmerr, j, k, outlightcurvefilename, outlightcurvefile, corrected_magnitude, correction_mag )
#pragma omp parallel for private( i, lightcurvefilename, lightcurvefile, djd, ddmag, ddmerr, x, y, app, string, comments_string, j, k, outlightcurvefilename, outlightcurvefile, corrected_magnitude, correction_mag )
#endif
#endif
  for ( i= 0; i < Nstars; i++ ) {
   if ( bad_stars[i] == 0 ) {
    sprintf( lightcurvefilename, "out%s.dat", star_numbers[i] );
    sprintf( outlightcurvefilename, "out%s.tmp", star_numbers[i] );
    lightcurvefile= fopen( lightcurvefilename, "r" );
    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't read file %s\n", lightcurvefilename );
     exit( 1 );
    }
    outlightcurvefile= fopen( outlightcurvefilename, "w" );
    while ( -1 < read_lightcurve_point( lightcurvefile, &djd, &ddmag, &ddmerr, &x, &y, &app, string, comments_string ) ) {
     if ( djd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     // dmag= (float)ddmag;
     // dmerr= (float)ddmerr;
     //  Find which j is corresponding to the current JD
     for ( k= 0; k < Nobs; k++ ) {
      if ( fabs( jd[k] - djd ) <= 0.00001 ) { // 0.8 sec
       j= k;
       //
       // if ( fabs(c[i] * a[j]) >2.0 ) {
       // fprintf( stderr, "DEBUG: %s  c[i] * a[j]=%lf  c[i]=%lf a[j]=%lf\n", outlightcurvefilename, c[i] * a[j], c[i], a[j] );
       //}
       // reject large corrections
       corrected_magnitude= ddmag;
       correction_mag= (double)( c[i] * a[j] );
       if ( fabs( correction_mag ) < SYSREM_MAX_CORRECTION_MAG ) {
        corrected_magnitude= ddmag - correction_mag;
       } else {
        fprintf( stderr, "SysRem WARNING: skipping a large correction of %lf mag for star %s on JD%lf  c[i]=%f a[j]=%f\n", correction_mag, outlightcurvefilename, djd, c[i], a[j] );
       }
       write_lightcurve_point( outlightcurvefile, djd, corrected_magnitude, (double)ddmerr, (double)x, (double)y, (double)app, string, comments_string );
       break;
      }
     }
    }
    fclose( outlightcurvefile );
    fclose( lightcurvefile );
    unlink( lightcurvefilename );
    rename( outlightcurvefilename, lightcurvefilename );
   }
  }
  fprintf( stderr, "done\n" );

  /*
 // This should not be parallel as it relies on system() commands
 bad_stars_counter=0;
 for ( i= Nstars; i--; ) {
  if ( bad_stars[i] != 0 ) {
   bad_stars_counter++;
   sprintf( lightcurvefilename, "out%s.dat", star_numbers[i] );
   fprintf( stderr, "Skip correction for %s", lightcurvefilename );
   fprintf( stderr, "\n" );
  }
 }
 fprintf( stderr, "Skipped corrections for %d out of %d stars\n", bad_stars_counter, Nstars );
*/

  //  // Print out some stats
  //  //
  //  fprintf(stderr, "\nFinal SysRem \"airmass\" coefficients for each image (not the actual airmass, of course):\n");
  //  for( i= Nobs; i--; ) {
  //   fprintf(stderr, "a[%d]=%lf\n", i, a[i]);
  //  }
  //
  /*
 // We need a ton of memory to compute it!
 k= 0;
 for ( i= 0; i < Nstars; i++ ) {
  if ( bad_stars[i] == 0 ) {
   for ( j= 0; j < Nobs; j++ ) {
    if ( r[i][j] != 0.0 ) {
     data[k]= fabsf( a[j] * c[i] );
     k++;
    }
   }
  }
 }
 mean= gsl_stats_float_mean( data, 1, k );
 sigma= gsl_stats_float_sd_m( data, 1, k, mean );
 gsl_sort_float( data, 1, k );
 median= gsl_stats_float_median_from_sorted_data( data, 1, k );
 fprintf( stderr, "Mean correction %.6f +/-%.6f  (median=%lf)\n", mean, sigma, median );
 */

  // Free memory
  free( bad_stars );
  // for ( i= 0; i < Nstars; i++ ) {
  for ( i= Nstars; i--; ) {
   free( star_numbers[i] );
   free( mag_err[i] );
   free( r[i] );
  }
  free( star_numbers );
  free( old_c );
  free( old_a );

  free( mag_err );
  free( r );
  free( a );
  free( c );
  free( jd );
  // free( data );

  fprintf( stderr, "Removing %s\n", split_sysrem_input_star_list_lst_filenames[sysrem_input_star_list_lst_counter] );
  unlink( split_sysrem_input_star_list_lst_filenames[sysrem_input_star_list_lst_counter] );

 } // for( sysrem_input_star_list_lst_counter=0; sysrem_input_star_list_lst_counter<N_sysrem_input_star_list_lst;

 for ( sysrem_input_star_list_lst_counter= 0; sysrem_input_star_list_lst_counter < SYSREM_MAX_NUMBER_OF_PROCESSING_BLOCKS; sysrem_input_star_list_lst_counter++ ) {
  free( split_sysrem_input_star_list_lst_filenames[sysrem_input_star_list_lst_counter] );
 }

 change_number_of_sysrem_iterations_in_log_file();

 if ( 0 != system( "lib/create_data" ) ) {
  fprintf( stderr, "ERROR running lib/create_data\n" );
  return 1;
 }

 fprintf( stderr, "All done!  =)\n" );

 return 0;
}
