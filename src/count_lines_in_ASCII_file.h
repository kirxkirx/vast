// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_COUNT_LINES_IN_ASCII_FILE_INCLUDE_FILE

#include <stdio.h>
#include <string.h>

// We may have troubles including this file if it's not in the same directory
#ifndef VAST_LIMITS_INCLUDE_FILE
#include "vast_limits.h" // defines MAX_LOG_STR_LENGTH FILENAME_LENGTH 
#endif

static int count_lines_in_ASCII_file(char *asciifilename) {
 FILE *file;
 int linecounter= 0;
 char buf[MAX_LOG_STR_LENGTH];
 if( strlen(asciifilename) < 2 ) {
  return 0;
 }
 if( strlen(asciifilename) > FILENAME_LENGTH ) {
  return 0;
 }
 file= fopen(asciifilename, "r");
 if( NULL == file ) {
  return 0;
 }
 while( NULL != fgets(buf, MAX_LOG_STR_LENGTH, file) ) {
  linecounter++;
 }
 fclose(file);
 return linecounter;
}

// The macro below will tell the pre-processor that limits.h is already included
#define VAST_COUNT_LINES_IN_ASCII_FILE_INCLUDE_FILE

#endif
// VAST_COUNT_LINES_IN_ASCII_FILE_INCLUDE_FILE
