#include <stdio.h>
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#include "vast_limits.h"
#include "lightcurve_io.h"

int main() {
 char outfilename[OUTFILENAME_LENGTH];
 double x_ref_frame, y_ref_frame;
 FILE *transient_list_input;
 FILE *transient_list_output;
 FILE *lightcurvefile;

 double transient_best_mag= 99.0;
 double transient_best_x, transient_best_y;
 char transient_best_image[FILENAME_LENGTH];
 int i;
 double jd, mag, merr, x, y, app;
 char string[FILENAME_LENGTH];
 char ref_frame[FILENAME_LENGTH];

 /* Get file name of reference image from log */
 transient_list_input= fopen("vast_summary.log", "r");
 if( transient_list_input == NULL ) {
  fprintf(stderr, "ERROR: Can't open vast_summary.log for reading!\n");
  return 1;
 }
 if( 3 > fscanf(transient_list_input, "%s %s %s", string, string, string) ) {
  fprintf(stderr, "ERROR01 in transient_list.c while parsing vast_summary.log\n");
 }
 if( 5 > fscanf(transient_list_input, "%s %s %s %s %s", string, string, string, string, string) ) {
  fprintf(stderr, "ERROR02 in transient_list.c while parsing vast_summary.log\n");
 }
 if( 6 > fscanf(transient_list_input, "%s %s %s %s %s   %s", string, string, string, string, string, ref_frame) ) {
  fprintf(stderr, "ERROR03 in transient_list.c while parsing vast_summary.log\n");
  return 1;
 }
 fclose(transient_list_input);

 /* Deal with the list of transients */

 // DEBUG
 //system("cat candidates-transients.lst");

 /* Open candidates-transients.lst which was prepared by vast */
 transient_list_input= fopen("candidates-transients.lst", "r");
 if( transient_list_input == NULL ) {
  fprintf(stderr, "WARNING: Can't open candidates-transients.lst for reading! -- No candidates found?\n");
  return 1;
 }
 /* Open temporary output file candidates-transients.tmp */
 transient_list_output= fopen("candidates-transients.tmp", "w");
 if( transient_list_output == NULL ) {
  fprintf(stderr, "ERROR: Can't open candidates-transients.tmp for writing!\n");
  fclose(transient_list_input);
  return 1;
 }

 while( -1 < fscanf(transient_list_input, "%s %lf %lf", outfilename, &x_ref_frame, &y_ref_frame) ) {
  lightcurvefile= fopen(outfilename, "r");
  if( lightcurvefile != NULL ) {
   i= 0;
   //while(-1<fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&merr,&x,&y,&app,string) ){
   while( -1 < read_lightcurve_point(lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, NULL) ) {
    if( mag < transient_best_mag ) {
     transient_best_x= x;
     transient_best_y= y;
     strcpy(transient_best_image, string);
    }
    i++;
   }
   fclose(lightcurvefile);
   fprintf(transient_list_output, "%s %4d  %s %8.3lf %8.3lf  %s %8.3lf %8.3lf\n", outfilename, i, transient_best_image, transient_best_x, transient_best_y, ref_frame, x_ref_frame, y_ref_frame);
  } // if( outfile!=NULL )
 }

 fclose(transient_list_input);
 fclose(transient_list_output);

 unlink("candidates-transients.lst");
 rename("candidates-transients.tmp", "candidates-transients.lst");

 return 0;
}
