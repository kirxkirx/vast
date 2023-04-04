#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include <gsl/gsl_statistics.h>

#include <gsl/gsl_sort.h>

#include "lightcurve_io.h"

int main( int argc, char **argv ) {

 // unsigned int i,j,bin_counter,points_in_bin_counter,points_in_next_bin; // counters
 unsigned int i, bin_counter, points_in_bin_counter, number_of_measurements; // counters

 // JD is the array with dates
 double *out_JD;
 double *out_mag;
 double *out_magerr;
 double *out_x;
 double *out_y;
 double *out_app;

 double *bin_JD;
 double *bin_mag;
 double *bin_magerr;
 double *bin_weight;
 double *bin_x;
 double *bin_y;
 double *bin_app;

 double *in_JD;
 double *in_mag;
 double *in_magerr;
 double *in_x;
 double *in_y;
 double *in_app;

 char fake_str[FILENAME_LENGTH + 32];

 char outfilename[256];
 FILE *outfile;

 size_t *observation_index; // for index sorting

 double jd_bin_start= 0;
 double jd_bin_width;

 int shoud_we_compute_stats_for_bin;

 // Print usage note
 if ( argc < 3 ) {
  fprintf( stderr, "This program will bin the input ligtcurve in time.\nUsage:\n %s outNNNNN.dat bin_width_in_seconds\n", argv[0] );
  return 1;
 }

 // Parse the command line arguments
 if ( argc >= 3 ) {
  number_of_measurements= (unsigned int)count_points_in_lightcurve_file( argv[1] );
  if ( number_of_measurements < 2 ) {
   fprintf( stderr, "ERROR: something is wrong with the input lightcurve file %s - number_of_measurements = %d < 2 \n", argv[1], number_of_measurements );
   return 1;
  }
 }

 jd_bin_width= atof( argv[2] );
 if ( jd_bin_width <= 0.0 || jd_bin_width > 86400 * 100 ) {
  fprintf( stderr, "ERROR: the interpreted bin width in seconds (%lf) is out of the epected range!\n", jd_bin_width );
  return 1;
 } else {
  fprintf( stderr, "The lightcurve will be binned in %.0lf sec chunks\n", jd_bin_width );
 }
 jd_bin_width= jd_bin_width / 86400.0; // convert jd_bin_width from seconds to days

 out_JD= malloc( number_of_measurements * sizeof( double ) );
 if ( out_JD == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for out_JD()\n" );
  exit( 1 );
 }
 out_mag= malloc( number_of_measurements * sizeof( double ) );
 if ( out_mag == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for out_mag()\n" );
  exit( 1 );
 }
 out_magerr= malloc( number_of_measurements * sizeof( double ) );
 if ( out_magerr == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for out_magerr()\n" );
  exit( 1 );
 }
 out_x= malloc( number_of_measurements * sizeof( double ) );
 if ( out_x == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for out_x()\n" );
  exit( 1 );
 }
 out_y= malloc( number_of_measurements * sizeof( double ) );
 if ( out_y == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for out_y()\n" );
  exit( 1 );
 }
 out_app= malloc( number_of_measurements * sizeof( double ) );
 if ( out_app == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for out_app()\n" );
  exit( 1 );
 }

 bin_JD= malloc( number_of_measurements * sizeof( double ) );
 if ( bin_JD == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for bin_JD()\n" );
  exit( 1 );
 }
 bin_mag= malloc( number_of_measurements * sizeof( double ) );
 if ( bin_mag == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for bin_mag()\n" );
  exit( 1 );
 }
 bin_magerr= malloc( number_of_measurements * sizeof( double ) );
 if ( bin_magerr == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for bin_magerr()\n" );
  exit( 1 );
 }
 bin_weight= malloc( number_of_measurements * sizeof( double ) );
 if ( bin_weight == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for bin_weight()\n" );
  exit( 1 );
 }
 bin_x= malloc( number_of_measurements * sizeof( double ) );
 if ( bin_x == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for bin_x()\n" );
  exit( 1 );
 }
 bin_y= malloc( number_of_measurements * sizeof( double ) );
 if ( bin_y == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for bin_y()\n" );
  exit( 1 );
 }
 bin_app= malloc( number_of_measurements * sizeof( double ) );
 if ( bin_app == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for bin_app()\n" );
  exit( 1 );
 }

 in_JD= malloc( number_of_measurements * sizeof( double ) );
 if ( in_JD == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for in_JD()\n" );
  exit( 1 );
 }
 in_mag= malloc( number_of_measurements * sizeof( double ) );
 if ( in_mag == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for in_mag()\n" );
  exit( 1 );
 }
 in_magerr= malloc( number_of_measurements * sizeof( double ) );
 if ( in_magerr == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for in_magerr()\n" );
  exit( 1 );
 }
 in_x= malloc( number_of_measurements * sizeof( double ) );
 if ( in_x == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for in_x()\n" );
  exit( 1 );
 }
 in_y= malloc( number_of_measurements * sizeof( double ) );
 if ( in_y == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for in_y()\n" );
  exit( 1 );
 }
 in_app= malloc( number_of_measurements * sizeof( double ) );
 if ( in_app == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for in_app()\n" );
  exit( 1 );
 }

 observation_index= malloc( number_of_measurements * sizeof( size_t ) );
 if ( observation_index == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for observation_index()\n" );
  exit( 1 );
 }

 // Read the input lightcurve
 strncpy( outfilename, argv[1], OUTFILENAME_LENGTH );
 outfilename[OUTFILENAME_LENGTH - 1]= '\0'; // paranoid
 outfile= fopen( outfilename, "r" );
 i= 0;
 while ( -1 < read_lightcurve_point( outfile, &in_JD[i], &in_mag[i], &in_magerr[i], &in_x[i], &in_y[i], &in_app[i], fake_str, NULL ) ) {
  if ( in_JD[i] == 0.0 ) {
   continue; // if this line could not be parsed, try the next one
  }
  i++;
 }
 fclose( outfile );

 number_of_measurements= i;

 // Sort the lightcurve in JD
 gsl_sort_index( observation_index, in_JD, 1, number_of_measurements ); // The elements of p give the index of the array element which would have been stored in that position if the array had been sorted in place.
                                                                        // The array data is not changed.

 // Bin the lightcurve
 jd_bin_start= in_JD[observation_index[0]];
 bin_counter= 0;
 points_in_bin_counter= 0;
 shoud_we_compute_stats_for_bin= 0;
 for ( i= 0; i < number_of_measurements + 1; i++ ) {

  shoud_we_compute_stats_for_bin= 0;

  if ( i == number_of_measurements ) {
   // that's the last measurement
   shoud_we_compute_stats_for_bin= 1;
  } else {
   if ( in_JD[observation_index[i]] > jd_bin_start + jd_bin_width ) {
    // time to start the new bin
    shoud_we_compute_stats_for_bin= 1;
   }
   // fprintf(stderr, "DEBUUUG: %lf %lf %lf\n", in_JD[observation_index[i]], in_mag[observation_index[i]], in_magerr[observation_index[i]]);
  }

  // should we start a new bin or the point is within the old one
  if ( shoud_we_compute_stats_for_bin == 1 ) {
   //
   // fprintf(stderr, "DEBUUUG: NEW BIN %05d  points_in_bin_counter %05d  jd_bin_start=%lf jd_bin_width=%lf\n", bin_counter, points_in_bin_counter, jd_bin_start, jd_bin_width);
   // compute stats for the bin
   if ( points_in_bin_counter == 1 ) {
    // single point in the bin
    out_JD[bin_counter]= bin_JD[0];
    out_mag[bin_counter]= bin_mag[0];
    out_magerr[bin_counter]= bin_magerr[0];
    out_x[bin_counter]= bin_x[0];
    out_y[bin_counter]= bin_y[0];
    out_app[bin_counter]= bin_app[0];
   } else {
    // multiple points in the bin
    out_JD[bin_counter]= gsl_stats_wmean( bin_weight, 1, bin_JD, 1, points_in_bin_counter );
    out_mag[bin_counter]= gsl_stats_wmean( bin_weight, 1, bin_mag, 1, points_in_bin_counter );
    // out_magerr[bin_counter]= MAX( gsl_stats_wsd_m(bin_weight, 1, bin_mag, 1, points_in_bin_counter, out_mag[bin_counter])/sqrt( (double)points_in_bin_counter ), gsl_stats_mean(bin_magerr, 1, points_in_bin_counter)/sqrt( (double)points_in_bin_counter ) );
    //  this way the errors are incorrect, ut consistent bwtween one-point and multi-point bins
    out_magerr[bin_counter]= gsl_stats_mean( bin_magerr, 1, points_in_bin_counter ) / sqrt( (double)points_in_bin_counter );
    if ( 0 != isnan( out_magerr[bin_counter] ) ) {
     out_magerr[bin_counter]= DEFAULT_PHOTOMETRY_ERROR_MAG;
    }
    out_x[bin_counter]= gsl_stats_wmean( bin_weight, 1, bin_x, 1, points_in_bin_counter );
    out_y[bin_counter]= gsl_stats_wmean( bin_weight, 1, bin_y, 1, points_in_bin_counter );
    out_app[bin_counter]= gsl_stats_wmean( bin_weight, 1, bin_app, 1, points_in_bin_counter );
   }
   //
   // new bin
   bin_counter++;
   if ( i < number_of_measurements ) {
    points_in_bin_counter= 0;
    jd_bin_start= in_JD[observation_index[i]];
   } else {
    break;
   }
  }

  // fprintf(stderr, "DEBUUUG: %lf %lf %lf adding this point to bin %3d\n", in_JD[observation_index[i]], in_mag[observation_index[i]], in_magerr[observation_index[i]], bin_counter);

  // add point to the bin
  bin_JD[points_in_bin_counter]= in_JD[observation_index[i]];
  bin_mag[points_in_bin_counter]= in_mag[observation_index[i]];
  bin_magerr[points_in_bin_counter]= in_magerr[observation_index[i]];
  bin_weight[points_in_bin_counter]= 1.0 / ( bin_magerr[points_in_bin_counter] * bin_magerr[points_in_bin_counter] );
  bin_x[points_in_bin_counter]= in_x[observation_index[i]];
  bin_y[points_in_bin_counter]= in_y[observation_index[i]];
  bin_app[points_in_bin_counter]= in_app[observation_index[i]];
  points_in_bin_counter++;

 } // for(i=0; i<number_of_measurements; i++) {

 sprintf( fake_str, "binned_%.0lf_s", jd_bin_width * 86400.0 );

 // fprintf(stderr, "DEBUUUG: ----------------------------- \n");

 // Write-out the results
 for ( i= 0; i < bin_counter; i++ ) {
  write_lightcurve_point( stdout, out_JD[i], out_mag[i], out_magerr[i], out_x[i], out_y[i], out_app[i], fake_str, NULL );
 }

 // write_lightcurve_point(outfile, JD[i], model_mag, out_magerr[i], out_x[i], out_y[i], out_app[i], fake_str, NULL);

 free( observation_index );

 free( in_app );
 free( in_y );
 free( in_x );
 free( in_magerr );
 free( in_mag );
 free( in_JD );

 free( bin_app );
 free( bin_y );
 free( bin_x );
 free( bin_weight );
 free( bin_magerr );
 free( bin_mag );
 free( bin_JD );

 free( out_app );
 free( out_y );
 free( out_x );
 free( out_magerr );
 free( out_mag );
 free( out_JD );

 return 0;
}
