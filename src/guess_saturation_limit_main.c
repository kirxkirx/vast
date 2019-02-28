/*

 This program will print additional SExtractor command line arguments setting gain and flag images.

*/

#include <stdio.h>
#include <string.h> // for strncpy()

#include "vast_limits.h"
#include "guess_saturation_limit.h"
#include "ident.h"
//#include "write_individual_image_log.h"

int main( int argc, char **argv ) {

 char fitsfilename[FILENAME_LENGTH];

 char gain_sextractor_cl_parameter_string[FILENAME_LENGTH];
 char flag_image_sextractor_cl_parameter_string[FILENAME_LENGTH];
 char flag_image_filename[FILENAME_LENGTH];
 char weight_image_filename[FILENAME_LENGTH];

 int is_flag_image_used;

 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s image.fits\n", argv[0] );
  return 1;
 }
 strncpy( fitsfilename, argv[1], FILENAME_LENGTH - 1 );
 fitsfilename[FILENAME_LENGTH - 1]= '\0';

 // Reset
 gain_sextractor_cl_parameter_string[0]= flag_image_sextractor_cl_parameter_string[0]= flag_image_filename[0]= '\0';

 // Check if we need a flag image
 check_if_we_need_flag_image( fitsfilename, flag_image_sextractor_cl_parameter_string, &is_flag_image_used, flag_image_filename, weight_image_filename );

 // Guess gain for the given image
 guess_gain( fitsfilename, gain_sextractor_cl_parameter_string, 2, 1 );

 fprintf( stdout, "%s%s\n", flag_image_sextractor_cl_parameter_string, gain_sextractor_cl_parameter_string );

 return 0;
}
