// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_FILENAME_MANIPULATION_INCLUDE_FILE

#include <string.h>   // For strlen, strcat, strstr
#include <stdio.h>    // For NULL definition

void replace_last_slash_with_null( char *original_filename ) {
 int i;
 int len;

 if ( original_filename == NULL ) {
  return;
 }

 len= strlen( original_filename );
 // Traverse from the end of the string
 for ( i= len - 1; i >= 0; i-- ) {
  if ( original_filename[i] == '/' ) {
   original_filename[i]= '\0'; // Replace the last '.' with '\0'
   break;                      // Exit after the first (last from end) dot is replaced
  }
 }
}


void replace_last_dot_with_null( char *original_filename ) {
 int i;
 int len;

 if ( original_filename == NULL ) {
  return;
 }

 len= strlen( original_filename );
 // Traverse from the end of the string
 for ( i= len - 1; i >= 0; i-- ) {
  if ( original_filename[i] == '.' ) {
   original_filename[i]= '\0'; // Replace the last '.' with '\0'
   break;                      // Exit after the first (last from end) dot is replaced
  }
 }
}

void append_edit_suffix_to_lightcurve_filename( char *lightcurvefilename ) {
 int is_lightcurvefilename_modified= 0;

 if ( strlen( lightcurvefilename ) > 5 ) {
  // we don't do the fancy renaming if the input lightcurve file name is too short
  if ( NULL != strstr( lightcurvefilename, ".dat" ) ) {
   lightcurvefilename[strlen( lightcurvefilename ) - 4]= '\0'; // remove ".dat"
   strcat( lightcurvefilename, "_edit.dat" );
   is_lightcurvefilename_modified= 1;
  } else if ( NULL != strstr( lightcurvefilename, ".txt" ) ) {
   lightcurvefilename[strlen( lightcurvefilename ) - 4]= '\0'; // remove ".txt"
   strcat( lightcurvefilename, "_edit.txt" );
   is_lightcurvefilename_modified= 1;
  } else if ( NULL != strstr( lightcurvefilename, ".csv" ) ) {
   lightcurvefilename[strlen( lightcurvefilename ) - 4]= '\0'; // remove ".csv"
   strcat( lightcurvefilename, "_edit.csv" );
   is_lightcurvefilename_modified= 1;
  } else if ( NULL != strstr( lightcurvefilename, ".lc" ) ) {
   lightcurvefilename[strlen( lightcurvefilename ) - 3]= '\0'; // remove ".lc"
   strcat( lightcurvefilename, "_edit.lc" );
   is_lightcurvefilename_modified= 1;
  }
 }

 if ( is_lightcurvefilename_modified == 0 ) {
  // we did not recognize the file name extension, so we'll make it ugly
  replace_last_dot_with_null( lightcurvefilename );
  strcat( lightcurvefilename, "_edit.dat" );
 }

 return;
}

// The macro below will tell the pre-processor that limits.h is already included
#define VAST_FILENAME_MANIPULATION_INCLUDE_FILE

#endif
// VAST_FILENAME_MANIPULATION_INCLUDE_FILE
