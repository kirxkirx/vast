// Standard C include files
#include <stdio.h>
#include <math.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

// GSL include files
#include <gsl/gsl_statistics_double.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_errno.h>

// VaST's own include files
#include "vast_limits.h"
#include "variability_indexes.h"
#include "get_number_of_measured_images_from_vast_summary_log.h"
#include "detailed_error_messages.h"
#include "lightcurve_io.h"
//
#include "index_vs_mag.h"

void sort_log_file_in_mag() {
 unsigned int i, n;
 char **file_content;

 double *mag;

 FILE *f;

 size_t *p; // for index sorting

 unsigned int number_of_lines_in_file, longest_line_length, current_line_length;

 //char buf[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char buf[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG];

 // Count lines in file
 number_of_lines_in_file= longest_line_length= 0;
 f= fopen( "vast_lightcurve_statistics.log", "r" );
 if ( f == NULL ) {
  fprintf( stderr, "ERROR in create_data.c : cannot open vast_lightcurve_statistics.log for reading!\n" );
  report_lightcurve_statistics_computation_problem();
  exit( 1 );
 }
 //while(NULL!=fgets(buf,MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE,f)){
 while ( NULL != fgets( buf, MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG, f ) ) {
  //buf[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE-1]='\0'; // just in case
  buf[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG - 1]= '\0'; // just in case
  current_line_length= strlen( buf );
  if ( longest_line_length < current_line_length )
   longest_line_length= current_line_length;
  number_of_lines_in_file++;
 }
 fclose( f ); // close file for now, we'll re-open it later
 if ( longest_line_length < 10 ) {
  fprintf( stderr, "ERROR: the longest line length in vast_lightcurve_statistics.log is suspiciously short, only %d bytes! Something is very wrong.\n", longest_line_length );
  exit( 1 );
 }
 longest_line_length++; // to account for the final '\n' at the end of the line that is not visible to strlen()
 if ( number_of_lines_in_file < MIN_NUMBER_OF_STARS_ON_FRAME ) {
  fprintf( stderr, "ERROR: the number of lines in vast_lightcurve_statistics.log is suspiciously short, only %d! Something is very wrong.\n", number_of_lines_in_file );
  exit( 1 );
 }
 number_of_lines_in_file++; // Oh, this is the non-obvious one! It is needed for the last fgets() that will return NULL
 ///
 /// Well, if you count longest_line_length and number_of_lines_in_file they should be 1 less than the values at this point! Not sure why...
 fprintf( stderr, "vast_lightcurve_statistics.log: %d objects, the longest string is %d bytes.\nAllocating memory for resorting the file.\n", number_of_lines_in_file-1, longest_line_length-1 );

 mag= (double *)malloc( number_of_lines_in_file * sizeof( double ) );
 if ( NULL == mag ) {
  fprintf( stderr, "memory error\n" );
  exit( 1 );
 }

 file_content= (char **)malloc( number_of_lines_in_file * sizeof( char * ) );
 if ( NULL == file_content ) {
  fprintf( stderr, "memory error\n" );
  exit( 1 );
 }

 for ( i= 0; i < number_of_lines_in_file; i++ )
  file_content[i]= (char *)malloc( longest_line_length * sizeof( char ) );

 f= fopen( "vast_lightcurve_statistics.log", "r" );
 if ( f == NULL ) {
  fprintf( stderr, "ERROR in create_data.c : cannot open vast_lightcurve_statistics.log for reading!\n" );
  report_lightcurve_statistics_computation_problem();
  free( mag );
  for ( i= 0; i < number_of_lines_in_file; i++ )
   free( file_content[i] );
  free( file_content );
  exit( 1 );
 }
 i= 0;
 while ( NULL != fgets( file_content[i], longest_line_length, f ) ) {
  //fprintf(stderr,"--- %d ---\n",i);
  file_content[i][longest_line_length - 1]= '\0'; // just in case
  sscanf( file_content[i], "%lf %s", &mag[i], buf );
  //fprintf(stderr,"%d   %lf\n#%s#\n",i,mag[i],file_content[i]);
  i++;
 }
 fclose( f );
 n= i;

 p= malloc( n * sizeof( size_t ) );
 if ( p == NULL ) {
  fprintf( stderr, "ERROR in create_data.c - cannot allocate memory\n" );
  exit( 1 );
 }
 // don't forget to initialize the index array "p"!
 /// WHY initialize the index array "p"????
 ///for(i=0;i<n-1;i++)p[i]=(size_t)i;

 gsl_sort_index( p, mag, 1, n ); // The elements of p give the index of the array element which would have been stored in that position if the array had been sorted in place.
                                 // The array data is not changed.

 f= fopen( "vast_lightcurve_statistics.log", "w" );
 for ( i= 0; i < n; i++ ) {
  fprintf( f, "%s", file_content[p[i]] );
 }
 fclose( f );

 free( p );
 for ( i= 0; i < number_of_lines_in_file; i++ )
  free( file_content[i] );
 free( file_content );
 free( mag );
 return;
}

int main() {
 FILE *legacy_data_file;
 FILE *extended_data_file;

 DIR *dp;
 struct dirent *ep;

 FILE *lightcurvefile;
 double jd, mag, magerr, x, y, app;
 char string[FILENAME_LENGTH];

 //fprintf(stderr,"DEBUG01\n");

 int number_of_measured_images_from_vast_summary_log= get_number_of_measured_images_from_vast_summary_log();
 //
 //fprintf(stderr,"DEBUG: number_of_measured_images_from_vast_summary_log=%d \n",number_of_measured_images_from_vast_summary_log);
 //return 1;
 /*
 // the commented-out string was active in v77
 //int n_points_to_drop=MIN((int)(0.1*number_of_measured_images_from_vast_summary_log),STAT_NDROP);
 int n_points_to_drop=MIN((int)(0.05*number_of_measured_images_from_vast_summary_log),STAT_NDROP);
 fprintf(stderr,"n_points_to_drop=%d number_of_measured_images_from_vast_summary_log=%d STAT_NDROP=%d\n",n_points_to_drop,number_of_measured_images_from_vast_summary_log,STAT_NDROP);
 // Handle the special situation if there is no vast_summary.log file
 if( number_of_measured_images_from_vast_summary_log==MAX_NUMBER_OF_OBSERVATIONS )n_points_to_drop=0;
 fprintf(stderr,"n_points_to_drop=%d number_of_measured_images_from_vast_summary_log=%d STAT_NDROP=%d\n",n_points_to_drop,number_of_measured_images_from_vast_summary_log,STAT_NDROP);
 */
 int n_points_to_drop;

 // n_points_to_drop was determined based on number_of_measured_images_from_vast_summary_log
 // but we want n_points_to_drop to depend on the number of points in a given lightcurve

 //fprintf(stderr,"DEBUG02\n");

 double x_ref, y_ref;
 double m_median, sigma_series;
 int i, j; // just counters
 double *m;
 double *merr;
 double *w;
 //double a,b,d;

 double m_mean, weighted_sigma, MAD_scaled_to_sigma, lag1_autocorrelation, IQR;

 double skewness, kurtosis;

 double I, J, K, L;                     // Stetson's variability indexes
 double J_clip, L_clip, J_time, L_time; // Modified Stetson's variability indexes

 double I_sign_only;

 double *jday;

 int points_in_lightcurve;

 double RoMS;

 double reduced_chi2;

 double peak_to_peak_AGN_v;

 double N3;

 double excursions;

 double eta, E_A, SB;

 double NXS;

 int star_counter_for_display= 0;

 //unsigned int p; // for index sorting

 //fprintf(stderr,"DEBUG03\n");

 //a=b=2;

 // A minute of paranoia
 if ( number_of_measured_images_from_vast_summary_log <= 0 ) {
  fprintf( stderr, "FATAL ERROR in src/create_data.c - number_of_measured_images_from_vast_summary_log = %d <= 0\n", number_of_measured_images_from_vast_summary_log );
  return 1;
 }
 //

 legacy_data_file= fopen( "data", "w" );
 if ( NULL == legacy_data_file ) {
  fprintf( stderr, "ERROR in create_data.c - cannot open file data for writing!\n" );
  return 1;
 }
 extended_data_file= fopen( "vast_lightcurve_statistics.log", "w" );
 if ( NULL == extended_data_file ) {
  fprintf( stderr, "ERROR in create_data.c - cannot open file vast_lightcurve_statistics.log for writing!\n" );
  return 1;
 }

 //fprintf(stderr,"DEBUG04\n");

 m= malloc( number_of_measured_images_from_vast_summary_log * sizeof( double ) );
 if ( m == NULL ) {
  fprintf( stderr, "ERROR in create_data.c - cannot allocate memory\n" );
  return 1;
 }
 merr= malloc( number_of_measured_images_from_vast_summary_log * sizeof( double ) );
 if ( merr == NULL ) {
  fprintf( stderr, "ERROR in create_data.c - cannot allocate memory\n" );
  return 1;
 }
 w= malloc( number_of_measured_images_from_vast_summary_log * sizeof( double ) );
 if ( w == NULL ) {
  fprintf( stderr, "ERROR in create_data.c - cannot allocate memory\n" );
  return 1;
 }
 jday= malloc( number_of_measured_images_from_vast_summary_log * sizeof( double ) );
 if ( jday == NULL ) {
  fprintf( stderr, "ERROR in create_data.c - cannot allocate memory\n" );
  return 1;
 }
 //p=malloc(number_of_measured_images_from_vast_summary_log*sizeof(unsigned int));
 //if( p==NULL ){fprintf(stderr,"ERROR in create_data.c - cannot allocate memory\n");return 1;}

 //fprintf(stderr,"DEBUG05\n");

#ifdef DROP_LIGHTCURVS_WITH_SMALL_NUMBER_OF_POINS_FROM_ALL_PLOTS
 fprintf( stderr, " Will not compute variability indexes for objects having <%d points in lightcurve\nYou may disable this by commenting out the line '#define DROP_LIGHTCURVS_WITH_SMALL_NUMBER_OF_POINS_FROM_ALL_PLOTS' in src/vast_limits.h an re-compiling VaST with 'make'\n\nComputing, please wait a bit\n", MIN( SOFT_MIN_NUMBER_OF_POINTS, (int)( 0.5 * number_of_measured_images_from_vast_summary_log ) ) );
#endif

 dp= opendir( "./" );
 if ( dp != NULL ) {
  //fprintf(stderr,"Working...\nPlease, PLEASE, be patient!!!\n");
  //while( ep=readdir(dp) ){
  while ( ( ep= readdir( dp ) ) != NULL ) {
   //fprintf(stderr,"DEBUG: %s\n",ep->d_name); // !!!
   if ( strlen( ep->d_name ) < 8 )
    continue; // make sure the filename is not too short for the following tests
   //if( strlen(ep->d_name)<10 )continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {
    //fprintf(stderr,"DEBUG01\n"); // !!!
    //continue; // !!!!!!!!!!!!!!!!!!!!!!!!!!!!
    //puts(ep->d_name);
    lightcurvefile= fopen( ep->d_name, "r" );
    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     exit( 1 );
    }
    //fprintf(stderr,"DEBUG02\n"); // !!!
    //puts(ep->d_name);
    i= 0;

    //fprintf(stderr,"DEBUG06 - rading %s\n",ep->d_name);
    //while(-1<fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&magerr,&x,&y,&app,string)){
    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &magerr, &x, &y, &app, string, NULL ) ) {
     //continue; // !!!
     //puts(string);
     if ( jd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     if ( i == 0 ) {
      x_ref= x;
      y_ref= y;
     }
     if ( 1 == isnormal( mag ) && 1 == isnormal( magerr ) ) {
      if ( mag != 0.0 && magerr != 0.0 ) {
       m[i]= mag;
       merr[i]= magerr;
       jday[i]= jd;
       i++;
       if ( i >= MAX_NUMBER_OF_OBSERVATIONS ) {
        fprintf( stderr, "ERROR (src/create_data.c): i>=MAX_NUMBER_OF_OBSERVATIONS=%d\n", MAX_NUMBER_OF_OBSERVATIONS );
        fclose( lightcurvefile );
        return 1;
       }
      }
     }
    }
    fclose( lightcurvefile );
//fprintf(stderr,"DEBUG03\n"); // !!!
//puts(ep->d_name);
//continue; // !!!

// defined in src/vast_limits.h
#ifdef DROP_LIGHTCURVS_WITH_SMALL_NUMBER_OF_POINS_FROM_ALL_PLOTS
    // Skip the star if it has insufficient number of measurements
    //if( i<MIN(SOFT_MIN_NUMBER_OF_POINTS,(int)(0.5*(double)number_of_measured_images_from_vast_summary_log+0.5)) || i<2*HARD_MIN_NUMBER_OF_POINTS ){
    if ( i < MIN( SOFT_MIN_NUMBER_OF_POINTS, (int)( 0.5 * (double)number_of_measured_images_from_vast_summary_log + 0.5 ) ) || i < HARD_MIN_NUMBER_OF_POINTS ) {
#ifdef DEBUGFILES
     fprintf( stderr, "\rWill not compute variability indexes for %s as the lightcurve has only %5d points. ", ep->d_name, i );
#endif
     continue;
    }
    //fprintf(stderr,"i=%d MIN()=%d SOFT_MIN_NUMBER_OF_POINTS=%d number_of_measured_images_from_vast_summary_log=%d\n",i,MIN(SOFT_MIN_NUMBER_OF_POINTS,(int)(0.5*number_of_measured_images_from_vast_summary_log)),SOFT_MIN_NUMBER_OF_POINTS,number_of_measured_images_from_vast_summary_log);
#endif

    //fprintf(stderr,"DEBUG03.5\n"); // !!!
    //puts(ep->d_name);
    //continue; // !!!

    // Compute variability indexes: Stetson's indexes and the others that need time sorting of the input lightcurve
    compute_variability_indexes_that_need_time_sorting( jday, m, merr, i, number_of_measured_images_from_vast_summary_log, &I, &J, &K, &L, &J_clip, &L_clip, &J_time, &L_time, &I_sign_only, &N3, &excursions, &eta, &E_A, &SB );

    points_in_lightcurve= i;

    //fprintf(stderr,"DEBUG04\n"); // !!!
    //puts(ep->d_name);
    //continue; // !!!

    //////////////////////// Indexes that do not depend on sorting ////////////////////////
    // compute weights
    //for(j=0;j<i;j++){w[j]=1.0;} // NO WEIGHTS
    //for(j=0;j<i;j++){w[j]=1.0/merr[j];}  // NOTE THE UNUSUAL WEIGHTS!!!
    for ( j= 0; j < i; j++ ) {
     w[j]= 1.0 / ( merr[j] * merr[j] );
    } // THE USUAL WEIGHTS

    weighted_sigma= skewness= kurtosis= 0.0; // set default values

#ifndef DISABLE_INDEX_WEIGHTED_SIGMA
    m_mean= gsl_stats_wmean( w, 1, m, 1, i );                 // weighted mean mag.
    weighted_sigma= gsl_stats_wsd_m( w, 1, m, 1, i, m_mean ); // weighted SD
#ifndef DISABLE_INDEX_SKEWNESS
    skewness= gsl_stats_wskew_m_sd( w, 1, m, 1, i, m_mean, weighted_sigma ); // weighted skewness
#endif
#ifndef DISABLE_INDEX_KURTOSIS
    kurtosis= gsl_stats_wkurtosis_m_sd( w, 1, m, 1, i, m_mean, weighted_sigma ); // weighted kurtosis
#endif
#endif

    // Robust Median Statistic, RoMS
    RoMS= compute_RoMS( m, merr, i );

    //fprintf(stderr,"DEBUG05\n"); // !!!
    // reduced chi2
    reduced_chi2= 0.0; // This is in case chi2 computation is disabled at compile time.
// If needed, we disable chi2 computation here rather than in src/variability_indexes.c
// since compute_reduced_chi2() may be used as an auxiliary function
// elsewhere in the code.
#ifndef DISABLE_INDEX_REDUCED_CHI2
    reduced_chi2= compute_reduced_chi2( m, merr, i );
#endif

    // Peak-to-peak AGN-style variability index
    peak_to_peak_AGN_v= compute_peak_to_peak_AGN_v( m, merr, i );

    /// This thing has to be sorted in time!!!!
    lag1_autocorrelation= lag1_autocorrelation_of_unsorted_lightcurve( jday, m, i );

    //fprintf(stderr,"DEBUG05\n"); // !!!

    MAD_scaled_to_sigma= 0.0; // This is in case MAD computation is disabled at compile time.
// If needed, we disable MAD computation here rather than in src/variability_indexes.c
// since esimate_sigma_from_MAD_of_unsorted_data() may be used as an auxiliary function
// elsewhere in the code.
#ifndef DISABLE_INDEX_MAD
        // Estimate sigma from MAD, the input array doesn't need to be sorted in magnitude
    MAD_scaled_to_sigma= esimate_sigma_from_MAD_of_unsorted_data( m, i );
#endif

    // Compute normalized excess variance (NXS)
    NXS= Normalized_excess_variance( m, merr, i );

    // Compute IQR
    IQR= compute_IQR_of_unsorted_data( m, i );

    //////////////////////// end of indexes that do not depend on sorting ////////////////////////

    //fprintf(stderr,"DEBUG06\n"); // !!!

    ////////////////////////////// Computations below are needed for backward compatibility with the old way VaST was operating

    //-----------------------------------------------------------------------------------
    // Warning! After that point jday[i]-m[i]-merr[i] match is destroyed!
    // We keep only m[i]-merr[i] match by using gsl_sort2() instead of gsl_sort()
    gsl_sort2( m, 1, merr, 1, i );
    // let's compute median from the original (unfiltered lightcurve)
    //m_median=gsl_stats_median_from_sorted_data(m,1,i);

    // LIGHTCURVE FILTERING BELOW!!!!!
    /// Drop points
    //if( i>STAT_MIN_NUMBER_OF_POINTS_FOR_NDROP && i>2*n_points_to_drop ){
    if ( i >= STAT_MIN_NUMBER_OF_POINTS_FOR_NDROP ) {
     //
     n_points_to_drop= MIN( (int)( 0.05 * i ), STAT_NDROP );
     //
     i-= n_points_to_drop;
     for ( j= 0; j < i; j++ ) {
      m[j]= m[j + n_points_to_drop];
      merr[j]= merr[j + n_points_to_drop];
     }
     i-= n_points_to_drop;
    }

    //// Computations for the classical mag-sigma plot ////
    // note that the median and sigma here are calculated over the filtered lightcurve
    m_median= gsl_stats_median_from_sorted_data( m, 1, i );
    sigma_series= gsl_stats_sd( m, 1, i );

    //fprintf(stderr,"DEBUG07\n"); // !!!

    ///// Filter-out bad stars - if even the simple statistics canot be computed - we don't want this star to be written in the stat. files
    // This is the replacement of the old external filter
    if ( 0 == isnormal( m_median ) )
     continue;
    // Changec check here
    if ( m_median < BRIGHTEST_STARS )
     continue;
    if ( m_median > FAINTEST_STARS_ANYMAG )
     continue;
    // And this seems to be very dangerous
    //if( sigma_series>MAX_MAG_ERROR )continue;
    // No upper limit on the mag scatter - some objects may be vary by *a lot*!
    //
    if ( sigma_series == 0.0 || 0 == isnormal( sigma_series ) )
     continue;

    ///// Done with computations, now write-out the results

    // Write the results in the legacy file data.m_sigma
    fprintf( legacy_data_file, "%10.6lf %8.6lf %9.3lf %9.3lf %s\n", m_median, sigma_series, x_ref, y_ref, ep->d_name );

    // Write the results in the new extended file vast_lightcurve_statistics.log
    ///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////   1           2      3    4         5         6              7        8     9  10 11 12   13                   14                   15                 16       17         18          19                20          21     22     23    24    25    26       27 28  29
    //fprintf(extended_data_file,"%10.6lf %8.6lf %9.3lf %9.3lf %s  %6.6lf  %+12.6lf %+12.6lf  %+12.6lf %+12.6lf %+12.6lf %+12.6lf %5d %12.6lf %+12.6lf  %12.6lf %12.6lf %+12.6lf %12.6lf  %+12.6lf %+12.6lf %+12.6lf %+12.6lf  %+12.6lf  %+12.6lf  %+12.6lf %+12.6lf %+12.6lf  %+lg  %+12.6lf\n",m_median,sigma_series,x_ref,y_ref,ep->d_name, weighted_sigma,skewness,kurtosis,I, J, K, L, points_in_lightcurve,MAD_scaled_to_sigma,lag1_autocorrelation,RoMS,reduced_chi2,I_sign_only,peak_to_peak_AGN_v,J_clip,L_clip,J_time,L_time,N3,excursions,eta,E_A,SB,NXS,IQR);
    ///////////////////////////  Medag   STD     X       Y     lc  wSTD    skew     kurt      I        J        K        L       Npts  MAD     lag1     RoMS    rCh2    Isgn     Vp2p     Jclp     Lclp     Jtim     Ltim      N3        excr      eta     E_A      S_B       NXS   IQR
    fprintf( extended_data_file, "%10.6lf %8.6lf %11.7lf %11.7lf %s  %6.6lf  %+12.6lf %+12.6lf  %+12.6lf %+12.6lf %+12.6lf %+12.6lf %5d %12.6lf %+12.6lf  %12.6lf %12.6lf %+12.6lf %12.6lf  %+12.6lf %+12.6lf %+12.6lf %+12.6lf  %+12.6lf  %+12.6lf  %12.6lf %+12.6lf %+12.6lf  %12lg  %12.6lf\n", m_median, sigma_series, x_ref, y_ref, ep->d_name, weighted_sigma, skewness, kurtosis, I, J, K, L, points_in_lightcurve, MAD_scaled_to_sigma, lag1_autocorrelation, RoMS, reduced_chi2, I_sign_only, peak_to_peak_AGN_v, J_clip, L_clip, J_time, L_time, N3, excursions, eta, E_A, SB, NXS, IQR );

    //fprintf(stderr,"DEBUG08\n"); // !!!

    star_counter_for_display++;
    if ( star_counter_for_display % 100 == 0 )
     fprintf( stderr, "." );

    //fprintf(stderr,"DEBUG09\n"); // !!!
   }
  }
  (void)closedir( dp );
  // And write the file describing the crazy format of vast_lightcurve_statistics.log
  write_vast_lightcurve_statistics_format_log();
 } else {
  perror( "Couldn't open the directory" );
 }

 fprintf( stderr, "\n" ); // final end of line

 free( m );
 free( merr );
 free( w );
 free( jday );

 fclose( extended_data_file );
 fclose( legacy_data_file );

 sort_log_file_in_mag();

 return 0;
}
