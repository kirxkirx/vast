#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <limits.h> // realpath() needs it

// stat()
#include <sys/types.h>
#include <sys/stat.h>
#include <unistd.h>

#include "vast_limits.h"



void replace_file_with_symlink_if_filename_contains_white_spaces( char *filename ) {
 unsigned int i, need_to_replace_with_symlink;
 char symlinkname[FILENAME_LENGTH];
 //char command_string[2 * FILENAME_LENGTH];
 //
 char * resolvedpath;
 //
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
 for ( i= 1; i < MAX_NUMBER_OF_OBSERVATIONS; i++ ) {
  sprintf( symlinkname, "symlinks_to_images/symlink_to_image_%05d.fits", i );
  if ( 0 != stat( symlinkname, &sb ) )
   break; // continue if such a symlink already exists, break if this name is still empty
 }
 if ( i >= MAX_NUMBER_OF_OBSERVATIONS ) {
  fprintf( stderr, "ERROR: symlinks_to_images counter is out of range!\n" );
  return;
 }
 //if( 0!=fitsfile_read_check(filename) ){
 // fprintf(stderr,"The input does not appear to be a FITS image: %s\n",filename);return;
 //}
 fprintf( stderr, "WARNING: image path \"%s\" contains white spaces - SExtractor will not be able to handle that!\nTrying to circumvent this problem by creating symbolic link %s\n", filename, symlinkname );

 if( 0 == mkdir( "symlinks_to_images", 0766 ) ) {
  fprintf( stderr, "Creating directory 'symlinks_to_images/'\n");
 }

/*
 // A super silly way to create symlinks_to_images folder if it does not exist yet
 sprintf( command_string, "if [ ! -d symlinks_to_images ];then mkdir symlinks_to_images ;fi" );
 if ( 0 != system( command_string ) ) {
  fprintf( stderr, "WARNING: there seems to be a problem creating symbolic links to the input images! replace_file_with_symlink_if_filename_contains_white_spaces()\n" );
 }
*/

 // Create symlink
 resolvedpath= realpath( filename, 0 );
 if ( 0!=symlink( resolvedpath, symlinkname ) ){
  fprintf( stderr, "ERRROR in replace_file_with_symlink_if_filename_contains_white_spaces() -- cannot creat symlink to image containing a white space!\n");
  free( resolvedpath );
  return;
 }
 free( resolvedpath );

/*
 // The old and silly implementation of the above using a shell command
 // (that relies on 'readlink -f' not available on OS X)
 sprintf( command_string, "if [ ! -d symlinks_to_images ];then mkdir symlinks_to_images ;fi ; TRUEPATH=`readlink -f '%s'` ; ln -s \"$TRUEPATH\" %s", filename, symlink );
 if ( 0 != system( command_string ) ) {
  fprintf( stderr, "WARNING: there seems to be a problem creating symbolic links to the input images! replace_file_with_symlink_if_filename_contains_white_spaces()\n" );
 }
*/

 strncpy( filename, symlinkname, FILENAME_LENGTH - 1 );
 filename[FILENAME_LENGTH - 1]= '\0'; // just in case

 return;
}
