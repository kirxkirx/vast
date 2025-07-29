#include <string.h> // for memmem() and strncmp()
#include <libgen.h> // for basename()

#include <stdio.h>
#include <stdlib.h>
#include "fitsio.h"
#include "fitsfile_read_check.h"
#include "vast_types.h"
#include "ident.h"

#include <stdio.h>
#include "get_path_to_vast.h"
#include <unistd.h> // for chdir

#include "replace_file_with_symlink_if_filename_contains_white_spaces.h"

int main( int argc, char **argv ) {
 double double_garbage_JD;
 int int_garbage_timesys;
 double X_im_size;
 double Y_im_size;
 double aperture;

 char fitsfilename[FILENAME_LENGTH];

 char sextractor_catalog[FILENAME_LENGTH];

 char path_to_vast_string[VAST_PATH_MAX];
 get_path_to_vast( path_to_vast_string );
 if ( 0 != chdir( path_to_vast_string ) ) {
  fprintf( stderr, "ERROR in %s cannot chdir() to %s\n", argv[0], path_to_vast_string );
  return 1;
 }

 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s image.fit\n", argv[0] );
  return 1;
 }
 fprintf( stderr, "Choosing aperture...\n" );

 // strncpy(fitsfilename, argv[1], FILENAME_LENGTH - 1);
 safely_encode_user_input_string( fitsfilename, argv[1], FILENAME_LENGTH - 1 );
 fitsfilename[FILENAME_LENGTH - 1]= '\0';

 replace_file_with_symlink_if_filename_contains_white_spaces( fitsfilename );
 cutout_green_channel_out_of_RGB_DSLR_image( fitsfilename );

 if ( 0 != fitsfile_read_check( fitsfilename ) ) {
  fprintf( stderr, "ERROR reading FITS file %s\n", fitsfilename );
  return 1;
 }
#ifdef DEBUGMESSAGES
 fprintf( stderr, "gettime()\n" );
#endif
 int_garbage_timesys= 0;
 gettime( fitsfilename, &double_garbage_JD, &int_garbage_timesys, 0, &X_im_size, &Y_im_size, NULL, NULL, 0, 0, NULL );
#ifdef DEBUGMESSAGES
 fprintf( stderr, "autodetect_aperture()\n" );
#endif

 if ( 0 == strncmp( "sextract_single_image_noninteractive", basename( argv[0] ), strlen( "sextract_single_image_noninteractive" ) ) || 0 == strncmp( "fits2cat", basename( argv[0] ), strlen( "fits2cat" ) ) ) {
  // Perform the standard multi-run SExtractor processing and write the output source catalog
  aperture= autodetect_aperture( fitsfilename, sextractor_catalog, 0, 0, 0.0, X_im_size, Y_im_size, 2 );
  // special case when we are emulating fits2cat
  if ( 0 == strncmp( "fits2cat", basename( argv[0] ), strlen( "fits2cat" ) ) ) {
   fprintf( stdout, "%s\n", sextractor_catalog );
   return 0;
  }
 } else {
  // do not write the output source catalog, just print-out the aperture
  aperture= autodetect_aperture( fitsfilename, sextractor_catalog, 0, 2, 0.0, X_im_size, Y_im_size, 2 );
 }
 fprintf( stdout, "%.1lf\n", aperture );
 return 0;
}
