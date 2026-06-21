#include <stdio.h>
#include <stdlib.h>
#include <string.h> // for strlen() and strcmp()
#include <math.h>

#include <libgen.h> // for basename()

#include <ctype.h> // for isalpha()

// Validate a decimal degrees string for RA: digits, '.', and optional leading '+'
// Returns 0 on success, 1 on error
static int validate_ra_string( const char *s ) {
 unsigned int i, j;
 for ( j= 0, i= 0; i < strlen( s ); i++ ) {
  // We want to allow a + sign for the decimal degrees in RA, like +91.5
  if ( s[i] == '+' ) {
   continue;
  }
  //
  if ( 0 != isdigit( s[i] ) ) {
   continue;
  }
  if ( s[i] == '.' ) {
   j++;
   continue;
  }
  if ( s[i] == ':' ) {
   fprintf( stderr, "ERROR: the input RA is expected to be RA in degrees, instead: %s\n", s );
   return 1;
  }
  fprintf( stderr, "ERROR: illegal character #%c# in RA string %s \n", s[i], s );
  return 1;
 }
 if ( j != 1 ) {
  fprintf( stderr, "ERROR parsing RA string %s \n", s );
  return 1;
 }
 return 0;
}

// Validate a decimal degrees string for Dec: digits, '.', optional leading '+' or '-'
// Returns 0 on success, 1 on error
static int validate_dec_string( const char *s ) {
 unsigned int i, j;
 for ( j= 0, i= 0; i < strlen( s ); i++ ) {
  if ( 0 != isdigit( s[i] ) ) {
   continue;
  }
  if ( s[i] == '-' ) {
   continue;
  }
  if ( s[i] == '+' ) {
   continue;
  }
  if ( s[i] == '.' ) {
   j++;
   continue;
  }
  if ( s[i] == ':' ) {
   fprintf( stderr, "ERROR: the input Dec is expected to be Dec in degrees, instead: %s\n", s );
   return 1;
  }
  fprintf( stderr, "ERROR: illegal character #%c# in Dec string %s \n", s[i], s );
  return 1;
 }
 if ( j != 1 ) {
  fprintf( stderr, "ERROR parsing Dec string %s \n", s );
  return 1;
 }
 return 0;
}

// Convert RA (deg) and Dec (deg) strings to HMS/DMS and print to stdout.
// is_uas_mode: 1 for sub-mas precision, 0 for standard precision.
// Returns 0 on success, 1 on error.
static int convert_and_print( const char *ra_str, const char *dec_str, int is_uas_mode ) {
 double in, ss;
 int hh, mm;
 // Roll a seconds value over to the next minute when it would be *displayed*
 // as "60". The threshold is half a unit in the last printed decimal, so it
 // must track the print precision: the old fixed 0.01 was too coarse for the
 // one-decimal Dec output (it left ":60.0" in the string) and too fine for the
 // high-precision *_uas output (it would prematurely round real sub-arcsecond
 // values up to the next minute).
 double ra_seconds_round_threshold= is_uas_mode ? 0.5e-6 : 0.005;  // %09.6lf : %05.2lf
 double dec_seconds_round_threshold= is_uas_mode ? 0.5e-5 : 0.05;  // %08.5lf : %04.1lf

 if ( validate_ra_string( ra_str ) != 0 ) {
  return 1;
 }
 if ( validate_dec_string( dec_str ) != 0 ) {
  return 1;
 }

 in= atof( ra_str );
 if ( in < 0.0 || in > 360.0 ) {
  fprintf( stderr, "ERROR: the input RA (%s interpreted as %lf) is our of range!\n", ra_str, in );
  return 1;
 }
 in= in / 15;
 hh= (int)in;
 mm= (int)( ( in - hh ) * 60 );
 ss= ( ( in - hh ) * 60 - mm ) * 60;
 if ( ss >= 60.0 - ra_seconds_round_threshold ) {
  mm+= 1;
  ss= 0.0;
 }
 if ( mm == 60 ) {
  hh+= 1;
  mm= 0.0;
 }
 if ( is_uas_mode ) {
  // print results with sub-mas precision
  fprintf( stdout, "%02d:%02d:%09.6lf ", hh, mm, ss );
 } else {
  // print results with the standard precision
  fprintf( stdout, "%02d:%02d:%05.2lf ", hh, mm, ss );
 }
 in= atof( dec_str );
 if ( in < -90.0 || in > 90.0 ) {
  fprintf( stderr, "ERROR: the input Dec (%s interpreted as %lf) is our of range!\n", dec_str, in );
  return 1;
 }
 // Print the sign first, then decompose the ABSOLUTE value into DMS. Negating
 // the individual components instead (the old approach) turned a seconds field
 // that rounds to zero into negative zero, which printf renders as "-0.0" --
 // producing a malformed Dec string like "-16:30:-0.0" (e.g. for Dec -16.5).
 if ( in < 0.0 ) {
  fprintf( stdout, "-" );
 } else {
  fprintf( stdout, "+" );
 }
 in= fabs( in );
 hh= (int)in;
 mm= (int)( ( in - hh ) * 60 );
 ss= ( ( in - hh ) * 60 - mm ) * 60;
 if ( ss >= 60.0 - dec_seconds_round_threshold ) {
  mm+= 1;
  ss= 0.0;
 }
 if ( mm == 60 ) {
  hh+= 1;
  mm= 0;
 }
 if ( is_uas_mode ) {
  // print results with sub-mas precision
  fprintf( stdout, "%02d:%02d:%08.5lf\n", hh, mm, ss );
 } else {
  // print results with the standard precision
  fprintf( stdout, "%02d:%02d:%04.1lf\n", hh, mm, ss );
 }

 return 0;
}

int main( int argc, char **argv ) {
 int is_uas_mode;
 char ra_buf[256];
 char dec_buf[256];
 unsigned int i;

 is_uas_mode= ( 0 == strcmp( "deg2hms_uas", basename( argv[0] ) ) );

 // Batch mode: read RA DEC pairs from stdin when invoked with "-" argument
 if ( argc == 2 && 0 == strcmp( "-", argv[1] ) ) {
  while ( 2 == scanf( "%255s %255s", ra_buf, dec_buf ) ) {
   if ( convert_and_print( ra_buf, dec_buf, is_uas_mode ) != 0 ) {
    fprintf( stderr, "WARNING: skipping invalid input line: %s %s\n", ra_buf, dec_buf );
   }
  }
  return 0;
 }

 if ( argc < 3 ) {
  for ( i= 0; i < (unsigned int)argc; i++ )
   fprintf( stderr, "%s", argv[i] );
  fprintf( stderr, "\nUsage: %s RA DEC\n       %s -  (read from stdin)\n", argv[0], argv[0] );
  return 1;
 }

 return convert_and_print( argv[1], argv[2], is_uas_mode );
}
