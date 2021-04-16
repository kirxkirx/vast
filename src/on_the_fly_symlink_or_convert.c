#include <stdio.h>
#include <string.h> // for memmem() and strncmp()

#include "vast_limits.h"
#include "get_path_to_vast.h"
#include <unistd.h> // for chdir

#include "replace_file_with_symlink_if_filename_contains_white_spaces.h"

int main(int argc, char **argv) {
 char fitsfilename[FILENAME_LENGTH];

 char path_to_vast_string[VAST_PATH_MAX];
 get_path_to_vast(path_to_vast_string);
 if( 0 != chdir(path_to_vast_string) ) {
  fprintf(stderr, "ERROR in %s cannot chdir() to %s\n", argv[0], path_to_vast_string);
  return 1;
 }

 if( argc < 2 ) {
  fprintf(stderr, "Usage: %s image.fit\n", argv[0]);
  return 1;
 }

 strncpy(fitsfilename, argv[1], FILENAME_LENGTH - 1);
 fitsfilename[FILENAME_LENGTH - 1]= '\0';

 replace_file_with_symlink_if_filename_contains_white_spaces(fitsfilename);
 cutout_green_channel_out_of_RGB_DSLR_image(fitsfilename);
 
 fprintf(stdout, "%s\n", fitsfilename);

 return 0;
}
