// based on https://stackoverflow.com/questions/4025370/can-an-executable-discover-its-own-path-linux
#include <sys/types.h>
#include <unistd.h>
#include <sys/stat.h>

/*
#ifdef __gnu_linux__
 #include <linux/limits.h>
#else
 #include <sys/syslimits.h>
#endif
*/
#include <stdio.h>

#include <string.h> // for strlen()
#include <libgen.h> // for dirname()

#include <stdlib.h> // for exit()

#include "vast_limits.h" // for VAST_PATH_MAX

void removeSubstring( char *s, const char *toremove ) {
 //while( s=strstr(s,toremove) ){
 while ( ( s= strstr( s, toremove ) ) != NULL ) {
  memmove( s, s + strlen( toremove ), 1 + strlen( s + strlen( toremove ) ) );
 }
}

void get_path_to_vast( char *path_to_vast ) {
 char path[VAST_PATH_MAX];
 char dest[VAST_PATH_MAX];
 char vast_path[VAST_PATH_MAX];
 memset( dest, 0, sizeof( dest ) ); // readlink does not null terminate!
 //struct stat info;
 if ( path_to_vast == NULL ) {
  fprintf( stderr, "ERROR in get_path_to_vast(): the input string is NULL !!!\n" );
  exit( 1 );
 }
 pid_t pid= getpid();
 sprintf( path, "/proc/%d/exe", pid );
 if ( readlink( path, dest, VAST_PATH_MAX ) == -1 ) {
  // Just assume this is the current directory
  strncpy( path_to_vast, "./", VAST_PATH_MAX );
 } else {
  removeSubstring( dest, "util/" );
  removeSubstring( dest, "lib/" );
  strncpy( vast_path, dirname( dest ), VAST_PATH_MAX );
  strncat( vast_path, "/", 2 );
  strncpy( path_to_vast, vast_path, VAST_PATH_MAX );
  setenv( "VAST_PATH", vast_path, 1 ); // is used by some scripts
 }
 return;
}
