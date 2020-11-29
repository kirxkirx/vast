// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_WRITE_INDIVIDUAL_IMAGE_LOG

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h> // for isalpha()
#include <math.h>  // for isnormal()

#include "vast_limits.h"

static inline int write_string_to_individual_image_log(char *sextractor_catalog_filename, char *prefix_string, char *string_to_write_in_image_logfile, char *postfix_string) {
#ifdef DISABLE_INDIVIDUAL_IMAGE_LOG
 return 0;
#endif
 FILE *individual_image_logfile;
 char individual_image_logfilename[512];
 if( strlen(sextractor_catalog_filename) > 500 ) {
  fprintf(stderr, "ERROR: sextractor catalog filename is too long: %s\nSomething is very-very wrong...\n", sextractor_catalog_filename);
  return 1;
 }
 sprintf(individual_image_logfilename, "%s.info", sextractor_catalog_filename);
 individual_image_logfile= fopen(individual_image_logfilename, "a");
 if( NULL == individual_image_logfile ) {
  fprintf(stderr, "ERROR writing to the image log file %s\n", individual_image_logfilename);
  return 1;
 }
 //fprintf(stderr,"\n\n\n DEBUG: WRITING TO %s STRING %s \n\n\n",individual_image_logfilename,string_to_write_in_image_logfile);
 fputs(prefix_string, individual_image_logfile);
 fputs(string_to_write_in_image_logfile, individual_image_logfile);
 fputs(postfix_string, individual_image_logfile);
 fputc('\n', individual_image_logfile);
 fclose(individual_image_logfile);
 return 0;
}

// The macro below will tell the pre-processor that this header file is already included
#define VAST_WRITE_INDIVIDUAL_IMAGE_LOG
#endif
// VAST_WRITE_INDIVIDUAL_IMAGE_LOG
