#include <stdio.h>
#include <stdlib.h>
#include <string.h> // for strlen() and strcmp()
#include <math.h>

#include <libgen.h> // for basename()

#include <ctype.h> // for isalpha()

int main( int argc, char **argv ) {
 double in, ss;
 int hh, mm;
 unsigned int i, j;

 if ( argc < 3 ) {
  for ( i= 0; i < (unsigned int)argc; i++ )
   fprintf( stderr, "%s", argv[i] );
  fprintf( stderr, "\nUsage: %s RA DEC\n", argv[0] );
  return 1;
 }

 // Check that we have exactly one '.'
 for ( j= 0, i= 0; i < strlen( argv[1] ); i++ ) {
  // We want to allow a + sign for the decimal degrees in RA, like +91.5
  if ( argv[1][i] == '+' ) {
   continue;
  }
  //
  if ( 0 != isdigit( argv[1][i] ) ) {
   continue;
  }
  if ( argv[1][i] == '.' ) {
   j++;
   continue;
  }
  if ( argv[1][i] == ':' ) {
   fprintf( stderr, "ERROR: the input RA is expected to be RA in degrees, instead: %s\n", argv[1] );
   return 1;
  }
  fprintf( stderr, "ERROR: illegal character #%c# in RA string %s \n", argv[1][i], argv[1] );
  return 1;
 }
 if ( j != 1 ) {
  fprintf( stderr, "ERROR parsing RA string %s \n", argv[1] );
  return 1;
 }

 // Check that we have exactly one '.'
 for ( j= 0, i= 0; i < strlen( argv[2] ); i++ ) {
  if ( 0 != isdigit( argv[2][i] ) ) {
   continue;
  }
  if ( argv[2][i] == '-' ) {
   continue;
  }
  if ( argv[2][i] == '+' ) {
   continue;
  }
  if ( argv[2][i] == '.' ) {
   j++;
   continue;
  }
  if ( argv[1][i] == ':' ) {
   fprintf( stderr, "ERROR: the input Dec is expected to be Dec in degrees, instead: %s\n", argv[2] );
   return 1;
  }
  fprintf( stderr, "ERROR: illegal character #%c# in Dec string %s \n", argv[2][i], argv[2] );
  return 1;
 }
 if ( j != 1 ) {
  fprintf( stderr, "ERROR parsing Dec string %s \n", argv[2] );
  return 1;
 }

 in= atof( argv[1] );
 if ( in < 0.0 || in > 360.0 ) {
  fprintf( stderr, "ERROR: the input RA (%s interpreted as %lf) is our of range!\n", argv[1], in );
  return 1;
 }
 in= in / 15;
 hh= (int)in;
 mm= (int)( ( in - hh ) * 60 );
 ss= ( ( in - hh ) * 60 - mm ) * 60;
 if ( fabs( ss - 60.0 ) < 0.01 ) {
  mm+= 1;
  ss= 0.0;
 }
 if ( mm == 60 ) {
  hh+= 1;
  mm= 0.0;
 }
 if ( 0 == strcmp( "deg2hms_uas", basename( argv[0] ) ) ) {
  // print results with sub-mas precision
  fprintf( stdout, "%02d:%02d:%09.6lf ", hh, mm, ss );
 } else {
  // print results with the standard precision
  fprintf( stdout, "%02d:%02d:%05.2lf ", hh, mm, ss );
 }
 in= atof( argv[2] );
 if ( in < -90.0 || in > 90.0 ) {
  fprintf( stderr, "ERROR: the input Dec (%s interpreted as %lf) is our of range!\n", argv[2], in );
  return 1;
 }
 hh= (int)in;
 mm= (int)( ( in - hh ) * 60 );
 ss= ( ( in - hh ) * 60 - mm ) * 60;
 // fprintf(stderr," ###%s### ___%c___\n",argv[2],argv[2][0]);
 if ( in < 0.0 ) {
  hh*= -1;
  fprintf( stdout, "-" );
  mm*= -1;
  ss*= -1;
 } else
  fprintf( stdout, "+" );
 if ( fabs( ss - 60.0 ) < 0.01 ) {
  mm+= 1;
  ss= 0.0;
 }
 if ( mm == 60 ) {
  hh+= 1;
  mm= 0.0;
 }
 if ( 0 == strcmp( "deg2hms_uas", basename( argv[0] ) ) ) {
  // print results with sub-mas precision
  fprintf( stdout, "%02d:%02d:%08.5lf\n", hh, mm, ss );
 } else {
  // print results with the standard precision
  fprintf( stdout, "%02d:%02d:%04.1lf\n", hh, mm, ss );
 }

 return 0;
}
