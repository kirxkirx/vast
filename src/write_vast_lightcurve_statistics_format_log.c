#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "vast_limits.h"
#include "index_vs_mag.h"

// This function will create a file vast_lightcurve_statistics_format.log describing
// the format of vast_lightcurve_statistics.log and related files
void write_vast_lightcurve_statistics_format_log() {
 int i; // counter
 char short_index_name[256];
 FILE *vast_lightcurve_statistics_format_logfile;
 vast_lightcurve_statistics_format_logfile= fopen("vast_lightcurve_statistics_format.log", "w");
 if( vast_lightcurve_statistics_format_logfile == NULL ) {
  fprintf(stderr, "ERROR writing vast_lightcurve_statistics_format.log\n");
  return;
 }
 fprintf(vast_lightcurve_statistics_format_logfile, "The format of vast_lightcurve_statistics.log and related files is the following:\n");
 fprintf(vast_lightcurve_statistics_format_logfile, " Column %2d: Median magnitude\n", 1 + 0);
 get_index_name(0, short_index_name);
 fprintf(vast_lightcurve_statistics_format_logfile, " Column %2d: %s\n", 1 + 1, short_index_name);
 fprintf(vast_lightcurve_statistics_format_logfile, " Column %2d: X position of the star on the reference image [pix]\n", 1 + 2);
 fprintf(vast_lightcurve_statistics_format_logfile, " Column %2d: Y position of the star on the reference image [pix]\n", 1 + 3);
 fprintf(vast_lightcurve_statistics_format_logfile, " Column %2d: lightcurve file name\n", 1 + 4);
 for( i= 1; i < MAX_NUMBER_OF_INDEXES_TO_STORE; i++ ) {
  get_index_name(i, short_index_name);
  fprintf(vast_lightcurve_statistics_format_logfile, " Column %2d: %s\n", 5 + i, short_index_name);
 }
 fclose(vast_lightcurve_statistics_format_logfile);
 return;
}
