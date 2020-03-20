#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_statistics.h>

#include <sys/time.h>

#include "vast_limits.h"
#include "lightcurve_io.h"

int main( int argc, char **argv ) {
 DIR *dp;
 struct dirent *ep;

 FILE *lightcurvefile;
 double jd, old_jd, mag, merr, x, y, app;
 char string[FILENAME_LENGTH];

 int number_of_reference_images;
 double *mag_a= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( mag_a == NULL ) {
  fprintf( stderr, "ERROR: Cannot allocate memory for mag_a(find_flares.c)\n" );
  exit( 1 );
 };
 double *mag_a_err= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( mag_a_err == NULL ) {
  fprintf( stderr, "ERROR: Cannot allocate memory for mag_a_err(find_flares.c)\n" );
  exit( 1 );
 };
 double *w= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( w == NULL ) {
  fprintf( stderr, "ERROR: Cannot allocate memory for w(find_flares.c)\n" );
  exit( 1 );
 };
 double preflare_median_mag, flare_median_mag;
 double preflare_mag_sigma, flare_mag_sigma;
 int i;

 double x_on_reference_image, y_on_reference_image;

 if ( argc > 2 ) {
  fprintf( stderr, "Usage: %s [NUMBER_OF_REFERENCE_IMAGES]\n", argv[0] );
  exit( 0 );
 }

 if ( argc == 2 ) {
  number_of_reference_images= atoi( argv[1] );
 } else
  number_of_reference_images= HARD_MIN_NUMBER_OF_POINTS;

 dp= opendir( "./" );
 if ( dp != NULL ) {
  while ( ( ep= readdir( dp ) ) != NULL ) {
   if ( strlen( ep->d_name ) < 12 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {
    lightcurvefile= fopen( ep->d_name, "r" );
    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     exit( 1 );
    }
    // We accept two cases: the star is visible on two reference images and two second-epoch images
    // and the star is visible on one reference image and two second-epoch images

    // Count number of lines
    i= 0;
    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, NULL ) )
     i++;
    if ( jd == 0.0 )
     continue; // if this line could not be parsed, try the next one
    if ( i == 4 )
     number_of_reference_images= 2;
    if ( i == 3 )
     number_of_reference_images= 1;
    if ( i < HARD_MIN_NUMBER_OF_POINTS ) {
     fclose( lightcurvefile );
     continue;
    } // TEST
    fclose( lightcurvefile );
    lightcurvefile= fopen( ep->d_name, "r" );
    if ( lightcurvefile == NULL ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     exit( 1 );
    };

    /* Compute pre-flare mag & sigma */
    i= 0;
    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, NULL ) ) {
     if ( jd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     if ( i == 0 ) {
      x_on_reference_image= x;
      y_on_reference_image= y;
     }
     mag_a[i]= mag;
     mag_a_err[i]= merr;
     w[i]= 1.0 / ( merr * merr );
     i++;
     if ( i == number_of_reference_images ) {
      break;
     }
    }

    if ( i == 1 ) {
     preflare_median_mag= mag;
     preflare_mag_sigma= merr;
    } else {
     gsl_sort( mag_a, 1, i );
     preflare_median_mag= gsl_stats_wmean( w, 1, mag_a, 1, i );
     preflare_mag_sigma= MAX( gsl_stats_wsd_m( w, 1, mag_a, 1, i, preflare_median_mag ), sqrt( mag_a_err[0] * mag_a_err[0] + mag_a_err[1] * mag_a_err[1] ) );
    }
    /* Compute flare mag & sigma */
    i= 0;
    old_jd= 0.0; // so the compiler wouldn't complain about uninitialaized use
    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, NULL ) ) {
     if ( jd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     mag_a[i]= mag;
     mag_a_err[i]= merr;
     w[i]= 1.0 / ( merr * merr );
     i++;
     // Make sure there is no jump in JD between 2nd epoch images
     if ( i > 1 ) {
      if ( fabs( old_jd - jd ) > TRANSIENT_MIN_TIMESCALE_DAYS )
       continue;
     }
     old_jd= jd;
    }
    if ( i < HARD_MIN_NUMBER_OF_POINTS ) {
     fclose( lightcurvefile );
     continue;
    } // TEST
    gsl_sort( mag_a, 1, i );
    flare_median_mag= gsl_stats_wmean( w, 1, mag_a, 1, i );
    flare_mag_sigma= MAX( gsl_stats_wsd_m( w, 1, mag_a, 1, i, flare_median_mag ), sqrt( mag_a_err[0] * mag_a_err[0] + mag_a_err[1] * mag_a_err[1] ) );

    // Check the difference between the two second-epoch measurements
    if ( fabs( mag_a[0] - mag_a[1] ) > 0.4 ) {
     fclose( lightcurvefile );
     continue;
    } // something is wrong with this star
    
    
    // TEST if the flare is good
    if ( preflare_median_mag - preflare_mag_sigma - flare_median_mag + flare_mag_sigma > FLARE_MAG ) {
     // Make sure the flare is significant at 3 sigma level given the errorbars
     if ( preflare_median_mag - flare_median_mag > 3.0*sqrt( preflare_mag_sigma*preflare_mag_sigma + flare_mag_sigma*flare_mag_sigma ) ) {
      //fprintf(stderr,"%s preflare_median_mag=%lf preflare_mag_sigma=%lf i=%d ",ep->d_name,preflare_median_mag,preflare_mag_sigma,i);
      //fprintf(stderr," flare_median_mag=%lf flare_mag_sigma=%lf i=%d\n",flare_median_mag,flare_mag_sigma,i);
      fprintf( stdout, "%s  %8.3lf %8.3lf\n", ep->d_name, x_on_reference_image, y_on_reference_image );
     }
    }

    fclose( lightcurvefile );
   }
  }
  (void)closedir( dp );
 } else {
  perror( "Couldn't open the directory\n" );
 }

 free( mag_a );
 free( mag_a_err );
 free( w );

 fprintf( stderr, "Search for flares is completed. =)\n" );

 return 0;
}
