/*
 * This VaST routine will compute Heliocentric correction.
 */

#include <stdlib.h>
#include <time.h>
#include <stdio.h>
#include <math.h>

#include <libgen.h> // for basename()

#include <string.h> // for strcmp()

#include "../vast_limits.h"
#include "../lightcurve_io.h"

double hjd_N(double ra_obj_d, double dec_obj_d, double jd_tt); // defined in hjd_N.c

double convert_jdUT_to_jdTT(double jdUT, int *timesys); // defined in src/gettime.c

int main(int argc, char **argv) {
 double hjd_var;
 double ra_d, dec_d;

 FILE *lightcurvefile;
 FILE *outlightcurvefile;
 double jd, mag, merr, x, y, app;
 char string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char outfilename[FILENAME_LENGTH];

 int lightcurve_format; // Flag marking format of the lightcurve (both input and output).

 int input_in_UTC_flag= 0; // if input_in_UTC_flag = 1 - assume the input JD is JD(UTC), otherwise - assume JD(TT)
 int timesys= 0;           // for convert_jdUT_to_jdTT()
 double jdTT;

 if( 0 == strcmp(basename(argv[0]), "hjd_input_in_UTC") ) {
  input_in_UTC_flag= 1;
  fprintf(stderr, "Input JD is assumed to be JD(UTC)\n");
 } else {
  input_in_UTC_flag= 0;
  fprintf(stderr, "Input JD is assumed to be JD(TT)\n");
 }

 if( argc < 3 ) {
  fprintf(stderr, "Usage: %s outNNNNN.dat RA_DEG DEC_deg # to process full VaST lightcurve file\nor\n%s JD RA_DEG DEC_deg   # to convert individual date\n\nfor example:\n%s out01234.dat 123.4567 +89.0123 \nor\n%s 2455123.456 123.4567 +89.0123\n", argv[0], argv[0], argv[0], argv[0]);
  return 1;
 }

 fprintf(stderr, "IMPORTANT NOTE:\n it is reasonable to use Heliocentric correction only if you aim at timing accuracy no beter than ~8 sec.\n If you need higher accuracy - use Barycentric correction (not yet implemented in VaST).\n");

 ra_d= atof(argv[2]);
 dec_d= atof(argv[3]);

 // Try to open the input lightcurve file //
 lightcurvefile= fopen(argv[1], "r");
 if( NULL != lightcurvefile ) {
  // If the loghtcurve file was sucesfully opened, apply the corrections to each observation in it

  if( NULL == fgets(string, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lightcurvefile) ) {
   fprintf(stderr, "ERROR: empty lightcurve file!\n");
   exit( EXIT_FAILURE );
  }
  // Identify lightcurve format //
  if( 2 == sscanf(string, "%lf %lf", &jd, &mag) ) {
   lightcurve_format= 2; // "JD mag" format
   // Check that JD is within the reasonable range
   if( jd < EXPECTED_MIN_JD || jd > EXPECTED_MAX_JD ) {
    fprintf(stderr, "ERROR: JD out of expected range (%.1lf, %.1lf)!\nYou may change EXPECTED_MIN_JD and EXPECTED_MAX_JD in src/vast_limits.h and recompile VaST if you are _really sure_ you know what you are doing...\n", EXPECTED_MIN_JD, EXPECTED_MAX_JD);
    return 1;
   }
   if( 3 == sscanf(string, "%lf %lf %lf", &jd, &mag, &merr) ) {
    lightcurve_format= 1; // "JD mag err" format
    if( 4 == sscanf(string, "%lf %lf %lf %lf", &jd, &mag, &merr, &x) )
     lightcurve_format= 0; // VaST lightcurve format
   }
  } else {
   fprintf(stderr, "ERROR: can't parse the lightcurve file!\n");
   exit( EXIT_FAILURE );
  }
  if( lightcurve_format == 0 )
   fprintf(stderr, "VaST lightcurve format detected!\n");
  if( lightcurve_format == 1 )
   fprintf(stderr, "\"JD mag err\" lightcurve format detected!\n");
  if( lightcurve_format == 2 )
   fprintf(stderr, "\"JD mag\" lightcurve format detected!\n");
  fseek(lightcurvefile, 0, SEEK_SET); // go back to the beginning of the lightcurve file

  sprintf(outfilename, "%s_hjdTT", basename(argv[1])); // invent the output file name
  fprintf(stderr, "Applying Heliocentric Correction... ");
  outlightcurvefile= fopen(outfilename, "w");

  if( lightcurve_format == 0 ) {
   //while(-1<fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&merr,&x,&y,&app,string)){
   while( -1 < read_lightcurve_point(lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, comments_string) ) {
    if( jd == 0.0 )
     continue; // if this line could not be parsed, try the next one
    if( input_in_UTC_flag == 1 ) {
     jdTT= convert_jdUT_to_jdTT(jd, &timesys);
     jd= jdTT;
    }
    hjd_var= hjd_N(ra_d, dec_d, jd);
    //fprintf(outlightcurvefile,"%.5lf %8.5lf %.5lf %8.3lf %8.3lf %4.1lf %s\n",hjd_var,mag,merr,x,y,app,string);
    write_lightcurve_point(outlightcurvefile, hjd_var, mag, merr, x, y, app, string, comments_string);
   }
  }

  if( lightcurve_format == 1 ) {
   while( -1 < fscanf(lightcurvefile, "%lf %lf %lf", &jd, &mag, &merr) ) {
    if( input_in_UTC_flag == 1 ) {
     jdTT= convert_jdUT_to_jdTT(jd, &timesys);
     jd= jdTT;
    }
    hjd_var= hjd_N(ra_d, dec_d, jd);
    fprintf(outlightcurvefile, "%.5lf %8.5lf %.5lf\n", hjd_var, mag, merr);
   }
  }

  if( lightcurve_format == 2 ) {
   while( -1 < fscanf(lightcurvefile, "%lf %lf", &jd, &mag) ) {
    if( input_in_UTC_flag == 1 ) {
     jdTT= convert_jdUT_to_jdTT(jd, &timesys);
     jd= jdTT;
    }
    hjd_var= hjd_N(ra_d, dec_d, jd);
    fprintf(outlightcurvefile, "%.5lf %8.5lf\n", hjd_var, mag);
   }
  }

  fclose(lightcurvefile);
  fclose(outlightcurvefile);
  fprintf(stderr, "done! =)\nCorrected lightcurve is written to %s\nEnjoy it! :)\n", outfilename);
 } else {
  // If not, then user probably wants us to convert just a single date
  jd= atof(argv[1]);
  if( input_in_UTC_flag == 1 ) {
   fprintf(stderr, "\nJD(UTC)= %.5lf\n", jd);
   jdTT= convert_jdUT_to_jdTT(jd, &timesys);
   jd= jdTT;
  }
  fprintf(stderr, "JD(TT)= %.5lf\n", jd);
  if( jd < EXPECTED_MIN_JD || jd > EXPECTED_MAX_JD ) {
   fprintf(stderr, "ERROR: JD out of expected range!\nPlease change the source code in src/hjd.c and recompile if you are sure you know what you are doing...\n");
   return 1;
  }
  hjd_var= hjd_N(ra_d, dec_d, jd);
  fprintf(stdout, "HJD(TT)= %.5lf\n", hjd_var);
 }

 return 0;
}
