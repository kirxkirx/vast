#include <string.h>
#include <stdlib.h>
#include <libgen.h>

#include <stdio.h>

#include "vast_limits.h"

void setenv_localpgplot( char *path_to_the_executable ) {
 char *path_to_vast; //=dirname(path_to_the_executable);
 char *path_to_pgplot;
 char *last_dir_name;
 // path_to_pgplot=malloc( (2*strlen(path_to_vast)+32)*sizeof(char)); // just a wild guess how big the thing should be
 // last_dir_name=malloc( (2*strlen(path_to_vast)+32)*sizeof(char)); // just a wild guess how big the thing should be
 path_to_vast= malloc( FILENAME_LENGTH * sizeof( char ) );
 if(path_to_vast == NULL){
    fprintf(stderr, "ERROR: Couldn't allocate memory for path_to_vast(setenv_local_pgplot.c)\n");
    exit(1);
 }
 path_to_pgplot= malloc( FILENAME_LENGTH * sizeof( char ) ); // just a wild guess how big the thing should be
 if(path_to_pgplot == NULL){
    fprintf(stderr, "ERROR: Couldn't allocate memory for path_to_pgplot(setenv_local_pgplot.c)\n");
    exit(1);
 }
 last_dir_name= malloc( FILENAME_LENGTH * sizeof( char ) );  // just a wild guess how big the thing should be
 if(last_dir_name == NULL){
    fprintf(stderr, "ERROR: Couldn't allocate memory for last_dir_name(setenv_local_pgplot.c)\n");
    exit(1);
 }
 strncpy( path_to_vast, dirname( path_to_the_executable ), FILENAME_LENGTH );
 path_to_vast[FILENAME_LENGTH - 1]= '\0'; // just in case
 strncpy( last_dir_name, basename( path_to_vast ), FILENAME_LENGTH );
 last_dir_name[FILENAME_LENGTH - 1]= '\0'; // just in case
 if ( 0 == strcmp( last_dir_name, "lib" ) ) {
  strncpy( last_dir_name, dirname( path_to_vast ), FILENAME_LENGTH );
  last_dir_name[FILENAME_LENGTH - 1]= '\0'; // just in case
  strcpy( path_to_vast, last_dir_name );
 }
 if ( 0 == strcmp( last_dir_name, "util" ) ) {
  strncpy( last_dir_name, dirname( path_to_vast ), FILENAME_LENGTH );
  last_dir_name[FILENAME_LENGTH - 1]= '\0'; // just in case
  strncpy( path_to_vast, last_dir_name, FILENAME_LENGTH );
  path_to_vast[FILENAME_LENGTH - 1]= '\0'; // just in case
 }

 strcpy( path_to_pgplot, path_to_vast );
 strcat( path_to_pgplot, "/lib/pgplot/" );
 //fprintf(stderr,"###############%s########%s######\n",path_to_pgplot,last_dir_name);
 setenv( "PGPLOT_DIR", path_to_pgplot, 1 );
 free( path_to_vast );
 free( path_to_pgplot );
 free( last_dir_name );
 return;
}
