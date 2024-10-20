// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_KOUROVKA_SBG_DATE_INCLUDE_FILE

#define _GNU_SOURCE // for memmem() in Kourovka_SBG_date_hack()

#include <stdio.h>   // For FILE, fopen, fclose, getc, fprintf, sscanf, sprintf
#include <stdlib.h>  // For malloc, free
#include <string.h>  // For strcpy, memmem

#include "vast_limits.h"


int Kourovka_SBG_date_hack( char *fitsfilename, char *DATEOBS, int *date_parsed, double *exposure );

// The macro below will tell the pre-processor that limits.h is already included
#define VAST_KOUROVKA_SBG_DATE_INCLUDE_FILE

#endif
// VAST_COUNT_LINES_IN_ASCII_FILE_INCLUDE_FILE
