#include <stdio.h>
#include <stdlib.h> // for atof()

#include "read_tycho2.h"

int main(int argc, char **argv) {

 double faint_mag_limit_for_the_list;

 if ( argc<2 ){
  fprintf( stderr, "Usage: %s mag_limit\n", argv[0]);
  return 1;
 }
 
 faint_mag_limit_for_the_list=atof(argv[1]);
 
 if ( faint_mag_limit_for_the_list < 2.0 ){
  fprintf( stderr, "ERROR: the limiting magnitude is too bright!\n");
  return 1;
 }
 if ( faint_mag_limit_for_the_list > 14.0 ){
  fprintf( stderr, "ERROR: the limiting magnitude is too faint!\n");
  return 1;
 }


 create_tycho2_list_of_bright_stars_to_exclude_from_transient_search( faint_mag_limit_for_the_list );


 return 0;
}
