#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
 unsigned int i= 0;
 if( argc < 2 ) {
  fprintf(stderr, "Usage: %s 359.989609+00.012589\n", argv[0]);
  return 1;
 }
 while( i < strlen(argv[1]) ) {
  if( argv[1][i] == '+' || argv[1][i] == '-' )
   fputc(' ', stdout);
  fputc(argv[1][i], stdout);
  i++;
 }
 fputc('\n', stdout);
 return 0;
}
