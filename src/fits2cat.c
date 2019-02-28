#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "ident.h"

#include "vast_limits.h"

int main( int argc, char **argv ) {
 char sextractor_catalog[FILENAME_LENGTH];
 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s image00001.fit\n", argv[0] );
  return 1;
 }
 double JD, X_im_size, Y_im_size;
 int timesys= 0; // 0 - unknown
 char tmpstring[1024];

 /* Update PATH variable to make sure the local copy of SExtractor is there */
 char pathstring[8192];
 strncpy( pathstring, getenv( "PATH" ), 8192 );
 pathstring[8191]= '\0';
 strcat( pathstring, ":lib/bin" );
 setenv( "PATH", pathstring, 1 );

 gettime( argv[1], &JD, &timesys, 0, &X_im_size, &Y_im_size, tmpstring, tmpstring, 0, 0 );
 autodetect_aperture( argv[1], sextractor_catalog, 0, 0, 0, X_im_size, Y_im_size, 2 );
 fprintf( stdout, "%s\n", sextractor_catalog );
 return 1;
}
