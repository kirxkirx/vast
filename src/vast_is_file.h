#ifndef VAST_IS_FILE_H
#define VAST_IS_FILE_H

#include <stdio.h> // defines FILE, fopen(), fclose()

// is_file() - a small function which checks is an input string is a name of a readable file
static inline int is_file(char *filename) {
 FILE *f= NULL;
 f= fopen(filename, "r");
 if( f == NULL )
  return 0;
 else {
  fclose(f);
  return 1;
 }
}
#endif
// VAST_IS_FILE_H
