// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_SAFELY_ENCODE_USER_INPUT_INCLUDE_FILE

//#include "vast_limits.h" // defines FILENAME_LENGTH

//#include "fitsio.h" // we use a local copy of this file because we use a local copy of cfitsio

#include <stdio.h>
#include <ctype.h> // for isalnum()

//#define _GNU_SOURCE // doesn't seem to work!
//#include <string.h> // for memmem() and strlen()
#include <stddef.h> // for size_t, stddef.h is normally included in string.h

static inline int any_unusual_characters_in_string(char *fitsfilename) {
 size_t i;
 size_t string_size=strlen(fitsfilename);
 for(i=0; i<string_size; i++){
  // allow the following characters in filename
  // ':' is needed because we also use the same function to check input coordinates string
  // '[', ',', ']' are needed to use CFITSIO image cutout interface
  // allow '#' as there are real-life FITS files that has this symbol in their name
  if( 0==isalnum(fitsfilename[i]) && fitsfilename[i]!=' ' && fitsfilename[i]!='\\' && fitsfilename[i]!='/' && fitsfilename[i]!='.' && fitsfilename[i]!='_' && fitsfilename[i]!='-' && fitsfilename[i]!='+' && fitsfilename[i]!='~' && fitsfilename[i]!=',' && fitsfilename[i]!=';' && fitsfilename[i]!=':' && fitsfilename[i]!='[' && fitsfilename[i]!=',' && fitsfilename[i]!=']' && fitsfilename[i]!='#' ) {
   fprintf(stderr,"ERROR in any_unusual_characters_in_string(): I'm unhappy with the character '%c' in the input string '%s'\n", fitsfilename[i], fitsfilename);
   return 1;
  }
 }
 return 0;
}

static inline int safely_encode_user_input_string(char *output_filename, char *input_filename, size_t max_string_size) {
 size_t i;
 size_t string_size;
 if( input_filename==NULL ) {
  fprintf(stderr,"ERROR in safely_encode_user_input_string(): the input in a NULL pointer\n");
  return 1;
 }
 if( output_filename==NULL ) {
  fprintf(stderr,"ERROR in safely_encode_user_input_string(): the output in a NULL pointer\n");
  return 1;
 }
 if( 0 != any_unusual_characters_in_string(input_filename) ) {
  output_filename[0]= '\0';
  fprintf(stderr, "ERROR in safely_encode_user_input_string(): unusual character in input string\n");
  return 1;
 }
 string_size=strlen(input_filename);
 for(i=0; i<string_size; i++) {
  if( i==max_string_size ) {
   output_filename[0]= '\0';
   fprintf(stderr, "ERROR in safely_encode_user_input_string(): max string size reached\n");
   return 1;
  }
  output_filename[i]= input_filename[i];
 }
 output_filename[i]= '\0';
 return 0;
}


// The macro below will tell the pre-processor that this header file is already included
#define VAST_SAFELY_ENCODE_USER_INPUT_INCLUDE_FILE
#endif
// VAST_SAFELY_ENCODE_USER_INPUT_INCLUDE_FILE
