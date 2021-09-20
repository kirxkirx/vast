// This small program will read a lightcurve file from stdin or an ASCII file and will reformat it to look cute.

#include <stdio.h>

#include <gsl/gsl_sort.h>

#include "vast_limits.h"              // for MAX_NUMBER_OF_OBSERVATIONS
#include "vast_report_memory_error.h" // for vast_report_memory_error()
#include "lightcurve_io.h"            // for read_lightcurve_point()

int main(int argc, char **argv) {
 char string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 double x, y, app;
 FILE *inputfile;

 double *jd;
 double *mag;
 double *mag_err;

 int observation_counter, number_of_observations;
 size_t *observation_index; // for index sorting

 if( argc > 2 ) {
  fprintf(stderr, "This script will round--off all measurements to 0.001 mag and produce a lightcurve in format\nJD MAG MAG_ERR\n\n");
  fprintf(stderr, "Usage: %s outNNNNN.dat > fancy_lc.dat\n", argv[0]);
  return 1;
 }

 if( argc == 2 ) {
  inputfile= fopen(argv[1], "r");
  if( inputfile == NULL ) {
   fprintf(stderr, "ERROR: cannot open the lightcurve file %s\n", argv[1]);
   return 1;
  }
 } else {
  inputfile= stdin;
 }

 jd= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(double));
 if( NULL == jd ) {
  vast_report_memory_error();
  return 1;
 }
 mag= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(double));
 if( NULL == mag ) {
  vast_report_memory_error();
  return 1;
 }
 mag_err= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(double));
 if( NULL == mag_err ) {
  vast_report_memory_error();
  return 1;
 }
 observation_index= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(size_t));
 if( NULL == observation_index ) {
  vast_report_memory_error();
  return 1;
 }

 // Read the input lightcurve
 observation_counter= 0;
 while( -1 < read_lightcurve_point(inputfile, &jd[observation_counter], &mag[observation_counter], &mag_err[observation_counter], &x, &y, &app, string, NULL) ) {
  if( jd[observation_counter] == 0.0 )
   continue; // if this line could not be parsed, try the next one
  //fprintf(stdout,"%.5lf  %6.3lf %5.3lf\n",jd,mag,mag_err);
  observation_counter++;
 }
 number_of_observations= observation_counter;

 // Sort the lightcurve in jd
 gsl_sort_index(observation_index, jd, 1, number_of_observations); // The elements of p give the index of the array element which would have been stored in that position if the array had been sorted in place.
                                                                   // The array data is not changed.

 // Print results
 for( observation_counter= 0; observation_counter < number_of_observations; observation_counter++ ) {
  // never print zero errors!!!
  // 0.001 corresponds to %5.3lf printf format below
  if( mag_err[observation_index[observation_counter]] < 0.001 ) {
   mag_err[observation_index[observation_counter]]= 0.001;
  }
  //
  fprintf(stdout, "%.5lf  %6.3lf %5.3lf\n", jd[observation_index[observation_counter]], mag[observation_index[observation_counter]], mag_err[observation_index[observation_counter]]);
 }

 if( argc == 2 )
  fclose(inputfile);

 free(jd);
 free(mag);
 free(mag_err);
 free(observation_index);

 // Return non-zero exit status if there are too few observations in the input lightcurve
 // (may be useful for external scripts to test if a given file is a valid lightcurve)
 if( number_of_observations < HARD_MIN_NUMBER_OF_POINTS )
  return 1;

 return 0;
}
