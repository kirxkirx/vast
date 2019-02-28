#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_statistics_double.h>

#include <sys/time.h>

#include "vast_limits.h"
#include "lightcurve_io.h"
#include "variability_indexes.h"

void make_sure_photometric_errors_rescaling_is_in_log_file() {
 FILE *logfilein;
 FILE *logfileout;
 //int number_of_iterations=0;
 char str[2048];
 logfilein= fopen( "vast_summary.log", "r" );
 if ( logfilein != NULL ) {
  logfileout= fopen( "vast_summary.log.tmp", "w" );
  if ( logfileout == NULL ) {
   fclose( logfilein );
   fprintf( stderr, "ERROR: Couldn't open file vast_summary.log.tmp\n" );
   return;
  }
  while ( NULL != fgets( str, 2048, logfilein ) ) {
   if ( str[0] == 'F' && str[1] == 'o' && str[2] == 'r' && str[4] == 'e' && str[5] == 'a' && str[6] == 'c' && str[7] == 'h' && str[23] == 'a' && str[24] == 'p' && str[25] == 'e' && str[26] == 'r' ) {
    //           0123456789012345678901234567890
    sprintf( str, "For each source choose aperture with the smallest scatter: YES\n" );
   }
   fputs( str, logfileout );
  }
  fclose( logfileout );
  fclose( logfilein );
  //system("mv vast_summary.log.tmp vast_summary.log");
  unlink( "vast_summary.log" );
  rename( "vast_summary.log.tmp", "vast_summary.log" );
 }
 return;
}

int main( int argc, char **argv ) {
 DIR *dp;
 struct dirent *ep;

 FILE *lightcurvefile;
 FILE *outlightcurvefile;
 double jd, mag, magerr, x, y, app;
 char string[FILENAME_LENGTH];
 char comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 // double median_mag;
 // double mag_sigma;
 int i;

 int apcounter, bestap;
 double MAD, best_MAD;

 double dm;

 int counter_ap[6];

 double aperture_coefficient_to_print;

 char lightcurve_tmp_filename[FILENAME_LENGTH];

 char comments_string_without_multiple_apertures[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 double **mag_a;
 double **magerr_a;

 mag_a= (double **)malloc( 6 * sizeof( double * ) );
 if ( mag_a == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory mag_a(select_aperture_with_smallest_scatter_for_each_object.c)\n" );
  exit( 1 );
 };
 magerr_a= (double **)malloc( 6 * sizeof( double * ) );
 if ( magerr_a == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory magerr_a(select_aperture_with_smallest_scatter_for_each_object.c)\n" );
  exit( 1 );
 };
 for ( i= 0; i < 6; i++ ) {
  mag_a[i]= (double *)malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
  if ( mag_a[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory mag_a[i](select_aperture_with_smallest_scatter_for_each_object.c)\n" );
   exit( 1 );
  };
  magerr_a[i]= (double *)malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
  if ( magerr_a[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory magerr_a[i](select_aperture_with_smallest_scatter_for_each_object.c)\n" );
   exit( 1 );
  };
  counter_ap[i]= 0;
 }

 if ( argc > 1 ) {
  fprintf( stderr, "Reprocess out*dat files setting the magnitude measured with the best aperture as the reference one (2nd column in the lightcurve file).\n" );
  fprintf( stderr, "Usage:\n" );
  fprintf( stderr, "%s \n", argv[0] );
  exit( 0 );
 }

 dp= opendir( "./" );
 if ( dp != NULL ) {
  //fprintf(stderr,"Removing measurements with large errors (>%.1lf sigma) from lightcurves... ",sigma_filter);
  //while( ep = readdir(dp) ){
  while ( ( ep= readdir( dp ) ) != NULL ) {
   if ( strlen( ep->d_name ) < 8 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {
    lightcurvefile= fopen( ep->d_name, "r" );
    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     exit( 1 );
    }
    /* Compute median mag & sigma */
    i= 0;
    //while(-1<fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&magerr,&x,&y,&app,string)){
    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &magerr, &x, &y, &app, string, comments_string ) ) {
     if ( jd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     mag_a[0][i]= mag;
     magerr_a[0][i]= magerr;
     if ( comments_string == NULL ) {
      continue;
     }
     if ( 10 > sscanf( comments_string, "%lf %lf  %lf %lf %lf %lf %lf %lf %lf %lf %[^\t\n]", &mag_a[1][i], &magerr_a[1][i], &mag_a[2][i], &magerr_a[2][i], &mag_a[3][i], &magerr_a[3][i], &mag_a[4][i], &magerr_a[4][i], &mag_a[5][i], &magerr_a[5][i], comments_string_without_multiple_apertures ) ) {
      fprintf( stderr, "ERROR parsing the comments string: %s\n", comments_string );
      continue;
     }
     mag_a[1][i]+= mag_a[0][i];
     mag_a[2][i]+= mag_a[0][i];
     mag_a[3][i]+= mag_a[0][i];
     mag_a[4][i]+= mag_a[0][i];
     mag_a[5][i]+= mag_a[0][i];
     i++;
    }
    fclose( lightcurvefile );
    bestap= 0;
    best_MAD= 99999999;
    for ( apcounter= 0; apcounter < 6; apcounter++ ) {
     MAD= esimate_sigma_from_MAD_of_unsorted_data( mag_a[apcounter], i );
     if ( MAD < best_MAD ) {
      best_MAD= MAD;
      bestap= apcounter;
     }
    }

    counter_ap[bestap]++;

    // too much prinitng
    //fprintf(stderr,"%s  bestap = %d\n",ep->d_name,bestap);

    if ( bestap == 0 ) {
     // Do nothing - the current aperture is fine
     continue;
    }

    // Compute the aperture correction (we'll need it to make sure the avarage magnitude will not change)
    dm= compute_median_of_usorted_array_without_changing_it( mag_a[0], i ) - compute_median_of_usorted_array_without_changing_it( mag_a[bestap], i );

    sprintf( lightcurve_tmp_filename, "lightcurve.tmp" );
    // Re-open the lightcurve file and apply the correction
    lightcurvefile= fopen( ep->d_name, "r" );
    outlightcurvefile= fopen( lightcurve_tmp_filename, "w" );
    if ( NULL == outlightcurvefile ) {
     fprintf( stderr, "\nAn ERROR has occured while processing file %s \n", ep->d_name );
     fprintf( stderr, "ERROR: Can't open file %s\n", lightcurve_tmp_filename );
     exit( 1 );
    }
    // The while cycle is needed to handle the situation that the first lines are comments
    //jd=0.0;
    //while( jd==0.0 ){
    // read_lightcurve_point(lightcurvefile,&jd,&mag,&magerr,&x,&y,&app,string,comments_string); // Never drop the first point!
    //}
    //fprintf(outlightcurvefile,"%.5lf %8.5lf %.5lf %8.3lf %8.3lf %4.1lf %s\n",jd,mag,magerr,x,y,app,string);
    //write_lightcurve_point( outlightcurvefile, jd, mag, magerr, x, y, app, string,comments_string);
    //while(-1<fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&magerr,&x,&y,&app,string)){
    i= 0;
    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &magerr, &x, &y, &app, string, comments_string ) ) {
     if ( jd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     if ( 10 <= sscanf( comments_string, "%lf %lf  %lf %lf %lf %lf %lf %lf %lf %lf %[^\t\n]", &mag_a[1][i], &magerr_a[1][i], &mag_a[2][i], &magerr_a[2][i], &mag_a[3][i], &magerr_a[3][i], &mag_a[4][i], &magerr_a[4][i], &mag_a[5][i], &magerr_a[5][i], comments_string_without_multiple_apertures ) ) {
      mag= mag + mag_a[bestap][i] + dm;
      magerr= magerr_a[bestap][i];
      if ( bestap == 2 ) {
       app+= AP01 * app;
      }
      if ( bestap == 3 ) {
       app+= AP02 * app;
      }
      if ( bestap == 4 ) {
       app+= AP03 * app;
      }
      if ( bestap == 5 ) {
       app+= AP04 * app;
      }
      //write_lightcurve_point( outlightcurvefile, jd, mag, magerr, x, y, app, string, comments_string);
      write_lightcurve_point( outlightcurvefile, jd, mag, magerr, x, y, app, string, comments_string_without_multiple_apertures );
      i++;
      continue;
     }
     fprintf( stderr, "ERROR parsing the comments string %s in %s\n", comments_string, ep->d_name );
    }
    fclose( outlightcurvefile );
    fclose( lightcurvefile );
    unlink( ep->d_name );                          // delete old lightcurve file
    rename( lightcurve_tmp_filename, ep->d_name ); // move lightcurve.tmp to lightcurve file
   }
  }
  (void)closedir( dp );
 } else {
  perror( "Couldn't open the directory\n" );
 }

 for ( i= 0; i < 6; i++ ) {
  free( mag_a[i] );
  free( magerr_a[i] );
 }
 free( mag_a );
 free( magerr_a );

 for ( i= 0; i < 6; i++ ) {
  aperture_coefficient_to_print= 1.0;
  if ( i == 1 )
   aperture_coefficient_to_print= 1.0;
  if ( i == 2 )
   aperture_coefficient_to_print= AP01;
  if ( i == 3 )
   aperture_coefficient_to_print= AP02;
  if ( i == 4 )
   aperture_coefficient_to_print= AP03;
  if ( i == 5 )
   aperture_coefficient_to_print= AP04;
  fprintf( stderr, "Aperture with index %d (%lf*REFERENCE_APERTURE_DIAMETER) seems best for %d stars\n", i, aperture_coefficient_to_print, counter_ap[i] );
 }

 fprintf( stderr, "\ndone!  =)\n" );

 return 0;
}
