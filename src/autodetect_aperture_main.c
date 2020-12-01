#include <string.h> // for memmem() and strncmp()
#include <libgen.h> // for basename()

#include <stdio.h>
#include <stdlib.h>
#include "fitsio.h"
#include "fitsfile_read_check.h"
#include "ident.h"

#include <stdio.h>
#include "get_path_to_vast.h"
#include <unistd.h> // for chdir

int main(int argc, char **argv) {
 double double_garbage_JD;
 int int_garbage_timesys;
 char char_garbage[4096];
 double X_im_size;
 double Y_im_size;
 double aperture;

 char path_to_vast_string[VAST_PATH_MAX];
 get_path_to_vast(path_to_vast_string);
 if( 0 != chdir(path_to_vast_string) ) {
  fprintf(stderr, "ERROR in %s cannot chdir() to %s\n", argv[0], path_to_vast_string);
  return 1;
 }

 fprintf(stderr, "Choosing aperture...\n");
 if( argc < 2 ) {
  fprintf(stderr, "Usage: %s image.fit\n", argv[0]);
  return 1;
 }
 if( 0 != fitsfile_read_check(argv[1]) ) {
  fprintf(stderr, "ERROR reading FITS file %s\n", argv[1]);
  return 1;
 }
#ifdef DEBUGMESSAGES
 fprintf(stderr, "gettime()\n");
#endif
 int_garbage_timesys= 0;
 gettime(argv[1], &double_garbage_JD, &int_garbage_timesys, 0, &X_im_size, &Y_im_size, char_garbage, char_garbage, 0, 0);
#ifdef DEBUGMESSAGES
 fprintf(stderr, "autodetect_aperture()\n");
#endif
 if( 0 == strncmp("sextract_single_image_noninteractive", basename(argv[0]), strlen("sextract_single_image_noninteractive")) ) {
  // Perform the standard multi-run SExtractor processing and write the output source catalog
  aperture= autodetect_aperture(argv[1], char_garbage, 0, 0, 0.0, X_im_size, Y_im_size, 2);
 } else {
  // do not write the output source catalog, just print-out the aperture
  aperture= autodetect_aperture(argv[1], char_garbage, 0, 2, 0.0, X_im_size, Y_im_size, 2);
 }
 fprintf(stdout, "%.1lf\n", aperture);
 return 0;
}
