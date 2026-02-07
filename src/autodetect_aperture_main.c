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

// Write the catalog-to-image mapping to vast_images_catalogs.log
// This function creates the file if it doesn't exist, or appends if the entry is not already present.
// Note: vast.c has its own write_images_catalogs_logfile() that overwrites the entire file
// with sequential naming (image00001.cat, etc.). This function is for standalone use of
// autodetect_aperture_main where PID-based naming is used.
static void update_vast_images_catalogs_log( const char *catalogfilename, const char *fitsfilename ) {
 FILE *f;
 char existing_catalog[FILENAME_LENGTH];
 char existing_fits[FILENAME_LENGTH];
 // First check if this entry already exists in the log
 f= fopen( "vast_images_catalogs.log", "r" );
 if ( f != NULL ) {
  while ( 2 == fscanf( f, "%s %s", existing_catalog, existing_fits ) ) {
   if ( 0 == strcmp( existing_fits, fitsfilename ) && 0 == strcmp( existing_catalog, catalogfilename ) ) {
    // Entry already exists, no need to write again
    fclose( f );
    return;
   }
  }
  fclose( f );
 }
 // Create or append the new entry
 f= fopen( "vast_images_catalogs.log", "a" );
 if ( f == NULL ) {
  fprintf( stderr, "WARNING: cannot open vast_images_catalogs.log for writing\n" );
  return;
 }
 fprintf( f, "%s %s\n", catalogfilename, fitsfilename );
 fclose( f );
}

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
  aperture= autodetect_aperture( fitsfilename, sextractor_catalog, 0, 0, 0.0, X_im_size, Y_im_size, 2, 2 );
  // Write the catalog-to-image correspondence to the log file
  update_vast_images_catalogs_log( sextractor_catalog, fitsfilename );
  // special case when we are emulating fits2cat
  if ( 0 == strncmp( "fits2cat", basename( argv[0] ), strlen( "fits2cat" ) ) ) {
   fprintf( stdout, "%s\n", sextractor_catalog );
   return 0;
  }
 } else {
  // do not write the output source catalog, just print-out the aperture
  aperture= autodetect_aperture( fitsfilename, sextractor_catalog, 0, 2, 0.0, X_im_size, Y_im_size, 2, 2 );
 }
 fprintf( stdout, "%.1lf\n", aperture );
 return 0;
}
