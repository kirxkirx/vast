#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// stat()
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include "vast_limits.h"

void replace_file_with_symlink_if_filename_contains_white_spaces( char *filename ) {
 unsigned int i, need_to_replace_with_symlink;
 char symlink[FILENAME_LENGTH];
 char command_string[2 * FILENAME_LENGTH];
 struct stat sb; // structure returned by stat() system call
 for ( need_to_replace_with_symlink= 0, i= 0; i < strlen( filename ); i++ ) {
  if ( filename[i] == ' ' ) {
   need_to_replace_with_symlink= 1;
   break;
  }
 }
 if ( need_to_replace_with_symlink == 0 )
  return;
 // create symlink name
 for ( i= 1; i < 65535; i++ ) {
  sprintf( symlink, "symlinks_to_images/symlink_to_image_%05d.fits", i );
  if ( 0 != stat( symlink, &sb ) )
   break; // continue is such a symlink already exists
 }
 if ( i >= 65535 ) {
  fprintf( stderr, "ERROR: symlinks_to_images counter is out of range!\n" );
  return;
 }
 //if( 0!=fitsfile_read_check(filename) ){
 // fprintf(stderr,"The input does not appear to be a FITS image: %s\n",filename);return;
 //}
 fprintf( stderr, "WARNING: image path \"%s\" contains white spaces - SExtractor will not be able to handle that!\nTrying to circumvent this problem by creating symbolic link %s\n", filename, symlink );

 sprintf( command_string, "if [ ! -d symlinks_to_images ];then mkdir symlinks_to_images ;fi ; TRUEPATH=`readlink -f '%s'` ; ln -s \"$TRUEPATH\" %s", filename, symlink );
 if ( 0 != system( command_string ) ) {
  fprintf( stderr, "WARNING: there seems to be a problem creating symbolic links to the input images! replace_file_with_symlink_if_filename_contains_white_spaces()\n" );
 }

 strncpy( filename, symlink, FILENAME_LENGTH - 1 );
 filename[FILENAME_LENGTH - 1]= '\0'; // just in case

 return;
}
