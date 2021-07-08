#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h> // for isalpha()

int main(int argc, char **argv) {
 unsigned int i, j;
 double hh, mm, ss;
 if( argc < 3 ) {
  fprintf(stderr, "Usage:\n %s RA DEC\n\nExample:\n %s 18:34:51.12 +34:00:20.3\n\nTo get single-line output:\n %s 18:34:51.12 +34:00:20.3 | sed 'N;s/\\n/ /' \n\n", argv[0], argv[0], argv[0]);
  return 1;
 }
 // Check that we have exactly two ':'
 for( j= 0, i= 0; i < strlen(argv[1]); i++ ) {
  if( argv[1][i] == ',' ) {
   argv[1][i]=' ';
   continue;
  }
  if( 0 != isdigit(argv[1][i]) ) {
   continue;
  }
  if( argv[1][i] == '.' ) {
   continue;
  }
  if( argv[1][i] == ':' ) {
   j++;
   continue;
  }
  if( 0 != isalpha(argv[1][i]) ) {
   fprintf(stderr, "ERROR parsing RA string %s \n", argv[1]);
   return 1;
  } // redundant
  fprintf(stderr, "ERROR: illegal character #%c# in RA string %s \n", argv[1][i], argv[1]);
  return 1;
 }
 if( j != 2 ) {
  fprintf(stderr, "ERROR parsing RA string %s \n", argv[1]);
  return 1;
 }
 //
 if( 3 != sscanf(argv[1], "%lf:%lf:%lf", &hh, &mm, &ss) ) {
  fprintf(stderr, "ERROR parsing the input position %s\n", argv[1]);
 }
 hh+= mm / 60 + ss / 3600;
 hh*= 15;
 if( hh < 0 || hh > 360 ) {
  fprintf(stderr, "ERROR converting coordinates: %s understood as %lf\n", argv[1], hh);
  return 1;
 }
 fprintf(stdout, "%12.7lf\n", hh);

 // Check that we have exactly two ':'
 for( j= 0, i= 0; i < strlen(argv[2]); i++ ) {
  if( 0 != isdigit(argv[2][i]) ) {
   continue;
  }
  if( argv[2][i] == '-' ) {
   continue;
  }
  if( argv[2][i] == '+' ) {
   continue;
  }
  if( argv[2][i] == '.' ) {
   continue;
  }
  if( argv[2][i] == ':' ) {
   j++;
   continue;
  }
  if( 0 != isalpha(argv[2][i]) ) {
   fprintf(stderr, "ERROR parsing Dec string %s \n", argv[2]);
   return 1;
  } // redundant
  fprintf(stderr, "ERROR: illegal character #%c# in Dec string %s \n", argv[2][i], argv[2]);
  return 1;
 }
 if( j != 2 ) {
  fprintf(stderr, "ERROR parsing Dec string %s \n", argv[2]);
  return 1;
 }
 //
 if( 3 != sscanf(argv[2], "%lf:%lf:%lf", &hh, &mm, &ss) ) {
  fprintf(stderr, "ERROR parsing the input position %s\n", argv[2]);
 }
 if( hh >= 0 && argv[2][0] != '-' )
  hh+= mm / 60 + ss / 3600;
 if( hh <= 0 && argv[2][0] == '-' )
  hh-= mm / 60 + ss / 3600;
 if( hh < -90 || hh > 90 ) {
  fprintf(stderr, "ERROR converting coordinates: %s understood as %lf\n", argv[2], hh);
  return 1;
 }
 fprintf(stdout, "%+12.7lf\n", hh);

 return 0;
}
