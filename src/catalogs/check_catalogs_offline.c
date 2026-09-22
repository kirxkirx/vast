#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "../vast_limits.h" // for TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD

// #define VSX_SEARCH_RADIUS_DEG 35.0 / 3600.0
#define VSX_SEARCH_RADIUS_DEG 25.0 / 3600.0

#define ASASSN_SEARCH_RADIUS_DEG 20.0 / 3600.0

// Sentinel value indicating that the measured magnitude of the transient
// was not supplied on the command line (so no magnitude comparison is done
// and the output is identical to the one produced by the older versions).
#define MEASURED_MAG_NOT_PROVIDED -100.0

// The vsx.dat record tail (descr) is parsed only up to this many characters:
// this covers the max/min magnitude fields but cuts before the epoch column,
// so a JD can never be mistaken for a magnitude.
#define VSX_DESCR_MAG_REGION_LENGTH 44
// Tokens starting before this offset within descr belong to the max
// magnitude field, tokens starting at or after it belong to the min
// magnitude (or amplitude) field.
#define VSX_DESCR_MAXFIELD_BOUNDARY 18

/* Auxiliary definitions (vast_limits.h provides functionally identical ones) */
#ifndef MAX
#define MAX( a, b ) ( ( ( a ) > ( b ) ) ? ( a ) : ( b ) )
#endif
#ifndef MIN
#define MIN( a, b ) ( ( ( a ) < ( b ) ) ? ( a ) : ( b ) )
#endif

// Set by any of the three catalog searches that could not read its catalog file.
//
// Without it "we searched everything and this is not a known variable" and "we
// could not actually search" are the same exit status, 1, and a caller has no
// way to tell them apart. That conflation is what turns a catalog outage into a
// confident wrong answer: util/search_databases_with_vizquery.sh falls through
// to an online query with a 3" radius in place of the local 25" one and then
// prints "This object is not listed in the common varaible star catalogs" as a
// definitive verdict, and util/transients/report_transient.sh records the same
// 1 in VARIABLE_STAR_ID. main() turns this flag into exit status 3 so the
// difference is visible. See the comment on the return statements in main().
static int a_catalog_was_unusable= 0;

// Check if a whitespace-delimited token from a catalog record is a magnitude
// value. One leading limit flag '<' or '>' and one trailing ':' (uncertainty
// flag) are allowed and ignored. Values outside the plausible magnitude range
// are rejected (this also protects against misinterpreting a JD or a period
// as a magnitude). Returns 1 on success.
int parse_mag_token( const char *token, double *value ) {
 char *endptr;
 const char *startptr;
 double v;
 if ( NULL == token ) {
  return 0;
 }
 startptr= token;
 if ( startptr[0] == '<' || startptr[0] == '>' ) {
  startptr++;
 }
 if ( startptr[0] == '\0' ) {
  return 0;
 }
 v= strtod( startptr, &endptr );
 if ( endptr == startptr ) {
  return 0;
 }
 if ( *endptr == ':' ) {
  endptr++;
 }
 while ( *endptr == ' ' || *endptr == '\t' || *endptr == '\n' || *endptr == '\r' ) {
  endptr++;
 }
 if ( *endptr != '\0' ) {
  return 0;
 }
 if ( v < -5.0 || v > 30.0 ) {
  return 0;
 }
 ( *value )= v;
 return 1;
}

// Extract the expected maximum brightness (the brightest magnitude the object
// is expected to reach according to its catalog record) from the magnitude
// section of a vsx.dat record.
// The input is the tail of a vsx.dat line starting at file byte 92 (as stored
// in descr by search_vsx), so offset 0 of the input corresponds to byte 92 of
// the catalog record. Empirically verified layout of the current CDS B/vsx
// vsx.dat file (the byte positions in the CDS ReadMe are off by a few columns,
// so the fields are located here by tokens + position windows rather than by
// exact column numbers):
//   offsets  4-9  magnitude at maximum (or the mean magnitude), may be
//                 preceded by a '>' or '<' limit flag and followed by a ':'
//   offset  13+   passband of the max magnitude
//   offsets 21-22 'Y' flag indicating that the min field holds a full
//                 peak-to-peak amplitude rather than the minimum magnitude
//                 (in that case the max field holds the MEAN magnitude,
//                 see https://www.aavso.org/magnitude-range-amplitude )
//   offsets 26-31 magnitude at minimum (or the amplitude)
//   offset  45+   epoch (JD) followed by the period - must not be mistaken
//                 for magnitudes, hence the region and value range cuts
// Returns 1 and sets (*expected_brightest_mag) on success, 0 otherwise.
int get_expected_brightest_mag_from_vsx_descr( const char *descr, double *expected_brightest_mag ) {
 char region[VSX_DESCR_MAG_REGION_LENGTH + 1];
 char token[VSX_DESCR_MAG_REGION_LENGTH + 1];
 int i, j, token_start;
 int have_max, have_min, min_is_amplitude;
 double max_mag, min_mag, token_value;

 have_max= 0;
 have_min= 0;
 min_is_amplitude= 0;
 max_mag= 0.0;
 min_mag= 0.0;

 if ( NULL == descr ) {
  return 0;
 }

 // Copy the magnitude region of the record, cutting before the epoch column
 for ( i= 0; i < VSX_DESCR_MAG_REGION_LENGTH && descr[i] != '\0' && descr[i] != '\n' && descr[i] != '\r'; i++ ) {
  region[i]= descr[i];
 }
 region[i]= '\0';

 // Scan whitespace-separated tokens keeping track of their position in the record
 i= 0;
 while ( region[i] != '\0' ) {
  if ( region[i] == ' ' || region[i] == '\t' ) {
   i++;
   continue;
  }
  token_start= i;
  for ( j= 0; region[i] != '\0' && region[i] != ' ' && region[i] != '\t'; i++, j++ ) {
   token[j]= region[i];
  }
  token[j]= '\0';
  // The 'Y' amplitude flag is a standalone 'Y' in the min part of the record
  // that comes before the min value. A 'Y' right after the max value is the
  // near-IR Y passband of the max magnitude, and a 'Y' after the min value
  // would be the passband of the min magnitude - both are ignored.
  if ( 0 == have_min && token_start >= VSX_DESCR_MAXFIELD_BOUNDARY && 0 == strcmp( token, "Y" ) ) {
   min_is_amplitude= 1;
   continue;
  }
  if ( 0 == parse_mag_token( token, &token_value ) ) {
   continue;
  }
  if ( token_start < VSX_DESCR_MAXFIELD_BOUNDARY ) {
   if ( 0 == have_max ) {
    max_mag= token_value;
    have_max= 1;
   }
  } else {
   if ( 0 == have_min ) {
    min_mag= token_value;
    have_min= 1;
   }
  }
 }

 if ( 0 == have_max ) {
  // Only the minimum magnitude (or nothing at all) is given in the record,
  // so we have no expectation of how bright the object may get.
  return 0;
 }

 if ( 1 == min_is_amplitude && 1 == have_min ) {
  // The max field holds the mean magnitude and the min field holds the full
  // peak-to-peak amplitude. Depending on the star type the mean may sit
  // anywhere between the extremes (for dwarf-nova-like objects it is close
  // to the quiescent state), so conservatively assume the star may get as
  // bright as the mean minus the full amplitude.
  ( *expected_brightest_mag )= max_mag - min_mag;
 } else {
  ( *expected_brightest_mag )= max_mag;
 }

 return 1;
}

// Extract the passband in which the maximum (or mean) magnitude of a vsx.dat
// record is measured. The input is the same descr string that
// get_expected_brightest_mag_from_vsx_descr() parses (see the record layout
// description above): the passband is the first token within the max
// magnitude field that follows the successfully parsed max magnitude value
// and is not a detached ':' uncertainty flag. The output buffer must be at
// least VSX_DESCR_MAG_REGION_LENGTH+1 bytes long.
// Returns 1 and sets passband on success, 0 otherwise.
static int get_max_mag_passband_from_vsx_descr( const char *descr, char *passband ) {
 char region[VSX_DESCR_MAG_REGION_LENGTH + 1];
 char token[VSX_DESCR_MAG_REGION_LENGTH + 1];
 int i, j, token_start;
 int have_max;
 double token_value;

 have_max= 0;

 if ( NULL == descr || NULL == passband ) {
  return 0;
 }

 // Copy the magnitude region of the record, cutting before the epoch column
 for ( i= 0; i < VSX_DESCR_MAG_REGION_LENGTH && descr[i] != '\0' && descr[i] != '\n' && descr[i] != '\r'; i++ ) {
  region[i]= descr[i];
 }
 region[i]= '\0';

 // Scan whitespace-separated tokens keeping track of their position in the record
 i= 0;
 while ( region[i] != '\0' ) {
  if ( region[i] == ' ' || region[i] == '\t' ) {
   i++;
   continue;
  }
  token_start= i;
  for ( j= 0; region[i] != '\0' && region[i] != ' ' && region[i] != '\t'; i++, j++ ) {
   token[j]= region[i];
  }
  token[j]= '\0';
  if ( token_start >= VSX_DESCR_MAXFIELD_BOUNDARY ) {
   // We are past the max magnitude field, so no passband was given for the max
   break;
  }
  if ( 1 == parse_mag_token( token, &token_value ) ) {
   have_max= 1;
   continue;
  }
  if ( 0 == have_max ) {
   // Something unparseable before the max value, like a detached '<' or '>' limit flag
   continue;
  }
  if ( 0 == strcmp( token, ":" ) ) {
   // A detached uncertainty flag between the max value and its passband
   continue;
  }
  strncpy( passband, token, VSX_DESCR_MAG_REGION_LENGTH );
  passband[VSX_DESCR_MAG_REGION_LENGTH]= '\0';
  return 1;
 }

 return 0;
}

// Return 1 if the variability type string denotes a Mira variable: exactly 'M'
// or the uncertain-classification variant 'M:'. Combined and other M-starting
// types ('MISC', 'EA/M', 'M9') do not match. Miras get a relaxed brightening
// warning threshold (TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD_MIRA):
// their catalog maxima are often photographic, they are very red, and their
// maxima vary from cycle to cycle.
static int is_mira_variability_type( const char *type_string ) {
 if ( type_string == NULL ) {
  return 0;
 }
 if ( type_string[0] != 'M' ) {
  return 0;
 }
 if ( type_string[1] == '\0' ) {
  return 1;
 }
 if ( type_string[1] == ':' && type_string[2] == '\0' ) {
  return 1;
 }
 return 0;
}

// Return 1 if the variability type string denotes a semiregular variable:
// 'SR' or one of its subtypes 'SRA', 'SRB', 'SRC', 'SRD', 'SRS', optionally
// followed by the uncertain-classification flag ':'. Combined types
// ('SR/M', 'SRB+EA') do not match, same strictness as
// is_mira_variability_type().
static int is_semiregular_variability_type( const char *type_string ) {
 int i;
 if ( type_string == NULL ) {
  return 0;
 }
 if ( type_string[0] != 'S' || type_string[1] != 'R' ) {
  return 0;
 }
 i= 2;
 if ( type_string[i] == 'A' || type_string[i] == 'B' || type_string[i] == 'C' || type_string[i] == 'D' || type_string[i] == 'S' ) {
  i++;
 }
 if ( type_string[i] == ':' ) {
  i++;
 }
 if ( type_string[i] == '\0' ) {
  return 1;
 }
 return 0;
}

// Return 1 if the variability type string denotes a slow irregular variable:
// 'L' or one of its subtypes 'LB', 'LC', optionally followed by the
// uncertain-classification flag ':'. Combined and other L-starting types
// ('L/SR', 'LB+E', 'LBV', 'LPB', 'LPV') do not match, same strictness as
// is_mira_variability_type().
static int is_slow_irregular_variability_type( const char *type_string ) {
 int i;
 if ( type_string == NULL ) {
  return 0;
 }
 if ( type_string[0] != 'L' ) {
  return 0;
 }
 i= 1;
 if ( type_string[i] == 'B' || type_string[i] == 'C' ) {
  i++;
 }
 if ( type_string[i] == ':' ) {
  i++;
 }
 if ( type_string[i] == '\0' ) {
  return 1;
 }
 return 0;
}

// Select the threshold for the 'measured mag is brighter than the record
// maximum' ATTENTION warning for a VSX record. Mira variables always get the
// relaxed TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD_MIRA threshold.
// Semiregular and slow irregular variables get the same relaxed threshold
// when the record maximum is measured in the photographic 'pg', Johnson 'B'
// or Sloan 'g' band ('g' is case-sensitive so Gaia 'G' does not match):
// like Miras these are red stars, so their V/CV-band maximum may be
// magnitudes brighter than the blue-band catalog maximum.
static double vsx_record_brightening_warn_threshold( const char *type_string, const char *descr ) {
 char max_mag_passband[VSX_DESCR_MAG_REGION_LENGTH + 1];
 if ( 1 == is_mira_variability_type( type_string ) ) {
  return TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD_MIRA;
 }
 if ( 1 == is_semiregular_variability_type( type_string ) || 1 == is_slow_irregular_variability_type( type_string ) ) {
  if ( 1 == get_max_mag_passband_from_vsx_descr( descr, max_mag_passband ) ) {
   if ( 0 == strcmp( max_mag_passband, "pg" ) || 0 == strcmp( max_mag_passband, "B" ) || 0 == strcmp( max_mag_passband, "g" ) ) {
    return TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD_MIRA;
   }
  }
 }
 return TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD;
}

int search_myMDV( double target_RA_deg, double target_Dec_deg, double search_radius_deg, int be_silent_if_not_found, int html_output ) {
 FILE *mymdvfile;
 char name[32];
 double RA_deg, Dec_deg, RA1_rad, RA2_rad, DEC1_rad, DEC2_rad;
 char type[32];
 char string[256];
 int i;

 double RA_hour, RA_min, RA_sec, Dec_degrees, Dec_min, Dec_sec;
 double distance_deg;

 double best_distance_deg= 90.0;
 char best_name[32];
 char best_type[32];

 int is_found= 0;

 // Initialize memory
 memset( name, '\0', 32 );
 memset( type, '\0', 32 );
 memset( string, '\0', 256 );
 memset( best_name, '\0', 32 );
 memset( best_type, '\0', 32 );

 // mymdvfile= fopen( "lib/catalogs/myMDV.dat", "r" );
 //  I put it in lib as the catalog is so small it is easier to just bundle it with the source code
 mymdvfile= fopen( "lib/myMDV.dat", "r" );
 if ( NULL == mymdvfile ) {
  fprintf( stderr, "ERROR: Cannot open myMDV.dat\n" );
  a_catalog_was_unusable= 1;
  return -1;
 }
 while ( NULL != fgets( string, 256, mymdvfile ) ) {
  sscanf( string, "%d %lf %lf %lf %lf %lf %lf %s", &i, &RA_hour, &RA_min, &RA_sec, &Dec_degrees, &Dec_min, &Dec_sec, type );

  // Convert RA and Dec to degrees
  RA_deg= ( RA_hour * 15.0 ) + ( RA_min / 4.0 ) + ( RA_sec / 240.0 );
  Dec_deg= fabs( Dec_degrees ) + ( Dec_min / 60.0 ) + ( Dec_sec / 3600.0 );
  if ( Dec_degrees < 0 )
   Dec_deg*= -1;

  if ( fabs( target_Dec_deg - Dec_deg ) > search_radius_deg )
   continue;

  RA1_rad= RA_deg * M_PI / 180.0;
  RA2_rad= target_RA_deg * M_PI / 180.0;
  DEC1_rad= Dec_deg * M_PI / 180.0;
  DEC2_rad= target_Dec_deg * M_PI / 180.0;

  distance_deg= acos( cos( DEC1_rad ) * cos( DEC2_rad ) * cos( MAX( RA1_rad, RA2_rad ) - MIN( RA1_rad, RA2_rad ) ) + sin( DEC1_rad ) * sin( DEC2_rad ) ) * 180.0 / M_PI;

  if ( distance_deg < search_radius_deg ) {
   if ( is_found == 0 ) {
    if ( 1 == html_output ) {
     fprintf( stdout, "<b>The object was <font color=\"red\">found</font> in <font color=\"DarkCyan\">MDV</font></b>\n" );
    } else {
     fprintf( stdout, "The object was found in MDV\n" );
    }
   }
   is_found= 1;
   if ( distance_deg < best_distance_deg ) {
    best_distance_deg= distance_deg;
    sprintf( best_name, "MDV %d", i ); // Star's name is its ID in this case
    strncpy( best_type, type, 32 );
    best_type[31 - 1]= '\0';
   }
  }
 }
 if ( 1 == is_found ) {
  if ( 1 == html_output ) {
   fprintf( stdout, "<b>%2.0lf\"  %s</b>\nType: %s\n", best_distance_deg * 3600.0, best_name, best_type );
  } else {
   fprintf( stdout, "%2.0lf\"  %s\nType: %s\n", best_distance_deg * 3600.0, best_name, best_type );
  }
 } else if ( be_silent_if_not_found ) {
  fprintf( stdout, "The object was not found in MDV\n" );
 }

 fclose( mymdvfile );

 return is_found;
}

int search_vsx( double target_RA_deg, double target_Dec_deg, double search_radius_deg, int be_silent_if_not_found, int html_output, double measured_mag_of_transient ) {
 FILE *vsx_dat;
 char name[32];
 char RA_char[32];
 char Dec_char[32];
 double RA_deg, Dec_deg, RA1_rad, RA2_rad, DEC1_rad, DEC2_rad;
 char type[32];
 char descr[128];
 char string[256];
 int i, j;

 double distance_deg;

 double best_distance_deg= 90.0;
 char best_name[32];
 char best_type[32];
 char best_descr[128];

 // The nearest brightness-COMPATIBLE match is tracked separately: a record
 // whose catalog maximum can account for the measured magnitude (same
 // per-type threshold as the brightening ATTENTION check below). It rescues
 // the identification when the nearest match is a faint variable that cannot
 // possibly be the measured object (common in crowded galactic-plane fields).
 double compat_best_distance_deg= 90.0;
 char compat_best_name[32];
 char compat_best_type[32];
 char compat_best_descr[128];
 double row_expected_brightest_mag;
 double row_warn_threshold_mag;
 int have_compatible_match= 0;
 int nearest_triggers_attention= 0;
 int headline_is_takeover= 0;
 int print_far_compatible_note= 0;

 double expected_brightest_mag;
 double brightening_warn_threshold_mag;

 int is_found= 0;

 // Initialize memory, otherwise valgrind complains about uninitialized 'type'
 memset( name, '\0', 32 );
 memset( RA_char, '\0', 32 );
 memset( Dec_char, '\0', 32 );
 memset( type, '\0', 32 );
 memset( descr, '\0', 128 );
 memset( string, '\0', 256 );
 memset( best_name, '\0', 32 );
 memset( best_type, '\0', 32 );
 memset( best_descr, '\0', 128 );
 memset( compat_best_name, '\0', 32 );
 memset( compat_best_type, '\0', 32 );
 memset( compat_best_descr, '\0', 128 );

 // download_vsx();
 vsx_dat= fopen( "lib/catalogs/vsx.dat", "r" );
 if ( NULL == vsx_dat ) {
  fprintf( stderr, "ERROR: Cannot open vsx.dat\n" );
  a_catalog_was_unusable= 1;
  return -1;
 }
 while ( NULL != fgets( string, 256, vsx_dat ) ) {

  for ( j= 0, i= 51; i < 60; i++, j++ )
   Dec_char[j]= string[i];
  Dec_char[j]= '\0';

  Dec_deg= atof( Dec_char );
  if ( fabs( target_Dec_deg - Dec_deg ) > search_radius_deg )
   continue;

  for ( j= 0, i= 8; i < 38; i++, j++ )
   name[j]= string[i];
  name[j]= '\0';

  for ( j= 0, i= 41; i < 50; i++, j++ )
   RA_char[j]= string[i];
  RA_char[j]= '\0';
  for ( j= 0, i= 61; i < 70; i++, j++ )
   type[j]= string[i];
  for ( j= 0; j < 32; j++ )
   if ( type[j] == ' ' ) {
    type[j]= '\0';
    break;
   }
  //  for ( j= 0; j < 92 - 61; j++ )
  //   if ( type[j] == ' ' )
  //    type[j]= '\0';
  for ( j= 0, i= 91; i < (int)strlen( string ); i++, j++ )
   descr[j]= string[i];
  descr[j]= '\0';

  RA_deg= atof( RA_char );

  RA1_rad= RA_deg * M_PI / 180.0;
  RA2_rad= target_RA_deg * M_PI / 180.0;
  DEC1_rad= Dec_deg * M_PI / 180.0;
  DEC2_rad= target_Dec_deg * M_PI / 180.0;

  // yes, it mathces the definition in src/put_two_sources_in_one_field.c
  distance_deg= acos( cos( DEC1_rad ) * cos( DEC2_rad ) * cos( MAX( RA1_rad, RA2_rad ) - MIN( RA1_rad, RA2_rad ) ) + sin( DEC1_rad ) * sin( DEC2_rad ) ) * 180.0 / M_PI;

  if ( distance_deg < search_radius_deg ) {
   if ( 0 == is_found ) {
    // say it only once even if we'll have a better match later
    if ( 1 == html_output ) {
     fprintf( stdout, "<b>The object was <font color=\"red\">found</font> in <font color=\"blue\">VSX</font></b>\n" );
    } else {
     fprintf( stdout, "The object was found in VSX\n" );
    }
   }
   is_found= 1;
   // fprintf(stdout,"%2.0lf\"  %s\nType: %s\n#   Max.           Min./Amp.       JD0           Period\n%s",distance_deg*3600.0,name,type,descr);
   if ( distance_deg < best_distance_deg ) {
    best_distance_deg= distance_deg;
    strncpy( best_name, name, 32 );
    best_name[31 - 1]= '\0';
    strncpy( best_type, type, 32 );
    best_type[31 - 1]= '\0';
    strncpy( best_descr, descr, 128 );
    best_descr[128 - 1]= '\0';
   }
   // Track the nearest match whose record maximum can account for the
   // measured magnitude (records with no parseable maximum carry no
   // brightness information and never qualify)
   if ( measured_mag_of_transient > MEASURED_MAG_NOT_PROVIDED + 1.0 ) {
    if ( 1 == get_expected_brightest_mag_from_vsx_descr( descr, &row_expected_brightest_mag ) ) {
     row_warn_threshold_mag= vsx_record_brightening_warn_threshold( type, descr );
     if ( row_expected_brightest_mag - measured_mag_of_transient <= row_warn_threshold_mag ) {
      if ( distance_deg < compat_best_distance_deg ) {
       compat_best_distance_deg= distance_deg;
       strncpy( compat_best_name, name, 32 );
       compat_best_name[31 - 1]= '\0';
       strncpy( compat_best_type, type, 32 );
       compat_best_type[31 - 1]= '\0';
       strncpy( compat_best_descr, descr, 128 );
       compat_best_descr[128 - 1]= '\0';
       have_compatible_match= 1;
      }
     }
    }
   }
  }
 }
 if ( is_found == 0 ) {
  if ( be_silent_if_not_found == 0 ) {
   if ( 1 == html_output ) {
    fprintf( stdout, "The object was <font color=\"green\">not found</font> in <font color=\"blue\">VSX</font>\n" );
   } else {
    fprintf( stdout, "The object was not found in VSX\n" );
   }
  }
 } else {
  // Decide which matched record to present as the identification (headline).
  // Default: the nearest match. When the measured magnitude is known and the
  // nearest record's maximum CANNOT account for it, a brightness-compatible
  // match slightly farther away is the more likely counterpart:
  //  - within VSX_COMPATIBLE_MATCH_TAKEOVER_RADIUS_ARCSEC it takes over as
  //    the headline (so the downstream AAVSO/VSNET report lines carry its
  //    name) and a NOTE mentions the skipped nearer faint record;
  //  - farther out it is only mentioned in a NOTE replacing the ATTENTION.
  // Compare the measured brightness of the transient with the brightest state
  // expected from the catalog record (if the measured magnitude was supplied).
  // A transient that is much brighter than the cataloged maximum deserves
  // attention even though it matches a known variable star position.
  // The wording of the ATTENTION and NOTE lines must not contain the phrases
  // 'The object was', 'found in' or 'not found' that are relied upon by the
  // downstream parsers (unmw filter_report.py, transient_factory_test31.sh,
  // the artificial star test); the 'mag brighter than the' substring is the
  // stable marker the downstream tools may key on.
  nearest_triggers_attention= 0;
  headline_is_takeover= 0;
  print_far_compatible_note= 0;
  if ( measured_mag_of_transient > MEASURED_MAG_NOT_PROVIDED + 1.0 ) {
   if ( 1 == get_expected_brightest_mag_from_vsx_descr( best_descr, &expected_brightest_mag ) ) {
    // Miras (always), semiregulars and slow irregulars (when the catalog
    // maximum is pg, B or g) get a relaxed threshold: blue-band catalog
    // maxima + the color of these red stars + cycle-to-cycle maximum
    // variations easily exceed 3 mag
    brightening_warn_threshold_mag= vsx_record_brightening_warn_threshold( best_type, best_descr );
    if ( expected_brightest_mag - measured_mag_of_transient > brightening_warn_threshold_mag ) {
     nearest_triggers_attention= 1;
    }
   }
  }
  if ( 1 == nearest_triggers_attention && 1 == have_compatible_match ) {
   if ( compat_best_distance_deg * 3600.0 <= VSX_COMPATIBLE_MATCH_TAKEOVER_RADIUS_ARCSEC ) {
    headline_is_takeover= 1;
   } else {
    print_far_compatible_note= 1;
   }
  }
  if ( 1 == headline_is_takeover ) {
   // The brightness-compatible match is the identification; the nearer faint
   // record only gets a NOTE. Trim the fixed-width field padding of the
   // skipped name so the NOTE reads cleanly.
   for ( i= (int)strlen( best_name ) - 1; i >= 0 && ' ' == best_name[i]; i-- ) {
    best_name[i]= '\0';
   }
   for ( j= 0; ' ' == best_name[j]; j++ ) {
    ;
   }
   if ( 1 == html_output ) {
    fprintf( stdout, "<b>%2.0lf\"  %s</b>\nType: %s\n#   Max.           Min./Amp.       JD0           Period\n%s", compat_best_distance_deg * 3600.0, compat_best_name, compat_best_type, compat_best_descr );
   } else {
    fprintf( stdout, "%2.0lf\"  %s\nType: %s\n#   Max.           Min./Amp.       JD0           Period\n%s", compat_best_distance_deg * 3600.0, compat_best_name, compat_best_type, compat_best_descr );
   }
   if ( strlen( compat_best_descr ) == 0 || compat_best_descr[strlen( compat_best_descr ) - 1] != '\n' ) {
    fprintf( stdout, "\n" );
   }
   fprintf( stdout, "NOTE: the nearer VSX entry %s at %.0f\" (record maximum %.2f) is too faint to account for the measured mag %.2f - the brighter variable above is the more likely counterpart.\n", &best_name[j], best_distance_deg * 3600.0, expected_brightest_mag, measured_mag_of_transient );
  } else {
   if ( 1 == html_output ) {
    fprintf( stdout, "<b>%2.0lf\"  %s</b>\nType: %s\n#   Max.           Min./Amp.       JD0           Period\n%s", best_distance_deg * 3600.0, best_name, best_type, best_descr );
   } else {
    fprintf( stdout, "%2.0lf\"  %s\nType: %s\n#   Max.           Min./Amp.       JD0           Period\n%s", best_distance_deg * 3600.0, best_name, best_type, best_descr );
   }
   if ( 1 == nearest_triggers_attention ) {
    // Make sure the ATTENTION/NOTE line starts on a new line even if the record was missing the trailing newline
    if ( strlen( best_descr ) == 0 || best_descr[strlen( best_descr ) - 1] != '\n' ) {
     fprintf( stdout, "\n" );
    }
    if ( 1 == print_far_compatible_note ) {
     for ( i= (int)strlen( compat_best_name ) - 1; i >= 0 && ' ' == compat_best_name[i]; i-- ) {
      compat_best_name[i]= '\0';
     }
     for ( j= 0; ' ' == compat_best_name[j]; j++ ) {
      ;
     }
     fprintf( stdout, "NOTE: the measured mag %.2f is inconsistent with the record above (maximum %.2f), and the brighter VSX variable %s at %.0f\" may be the actual counterpart.\n", measured_mag_of_transient, expected_brightest_mag, &compat_best_name[j], compat_best_distance_deg * 3600.0 );
    } else {
     if ( 1 == html_output ) {
      fprintf( stdout, "<b><font color=\"red\">ATTENTION: measured mag %.2f is %.1f mag brighter than the VSX record maximum brightness %.2f - possible unusual activity of a known variable!</font></b> (Alternatively, this may be a new object that coincides with the known variable's position just by chance.)\n", measured_mag_of_transient, expected_brightest_mag - measured_mag_of_transient, expected_brightest_mag );
     } else {
      fprintf( stdout, "ATTENTION: measured mag %.2f is %.1f mag brighter than the VSX record maximum brightness %.2f - possible unusual activity of a known variable! (Alternatively, this may be a new object that coincides with the known variable's position just by chance.)\n", measured_mag_of_transient, expected_brightest_mag - measured_mag_of_transient, expected_brightest_mag );
     }
    }
   }
  }
 }

 fclose( vsx_dat );

 return is_found;
}

const char *getfield_from_csv_string( char *line, int num ) {
 static const char whitespace[32]= "                               "; // 31 white space
 const char *tok;
 for ( tok= strtok( line, "," );
       tok && *tok;
       tok= strtok( NULL, ",\n" ) ) {
  if ( !--num )
   return tok;
 }
 // The idea is to return an empty line that is longer than anything we would like to compare it to
 return whitespace; // Return pointer to 31 white space on failure
}

int search_asassnv( double target_RA_deg, double target_Dec_deg, double search_radius_deg, int be_silent_if_not_found, int html_output, double measured_mag_of_transient ) {
 FILE *asassnv_csv;
 char name[32];
 double RA_deg, Dec_deg, RA1_rad, RA2_rad, DEC1_rad, DEC2_rad;
 char type[32];
 char MeanMag[32];
 char Amplitude[32];
 char Period[32];
 char string[4096];
 char string_noemptycells[4096];
 char string_to_be_ruined_by_strtok[4096];
 int i, j;

 double distance_deg;

 double asassn_mean_mag, asassn_amplitude, expected_brightest_mag;
 double brightening_warn_threshold_mag;

 int is_found= 0;

 // old format (the new format is described below and should be detected automatically)
 int asassn_name_token= 1;
 int type_token= 9;
 int meanmag_token= 6;
 int amplitude_token= 7;
 int period_token= 8;

 // main() calls this function up to twice per run; warn only once.
 static int asassnv_missing_warning_printed= 0;
 static int asassnv_malformed_record_warning_printed= 0;

 // Number of commas on the header line, learned from the file itself, and the
 // count for the record currently being parsed. -1 means "no header seen yet".
 int expected_number_of_commas= -1;
 int number_of_commas_in_this_line= 0;
 int comma_index;

 asassnv_csv= fopen( "lib/catalogs/asassnv.csv", "r" );
 if ( NULL == asassnv_csv ) {
  // The ASAS-SN Variables catalog is an optional download: lib/update_offline_catalogs.sh
  // declares it optional ("the search can proceed without it") and will legitimately leave
  // it absent when no mirror serves a complete copy. Its absence must NOT abort the VSX and
  // MDV searches that main() runs after this one - they have their own catalogs and those
  // are present. Degrade exactly the way search_vsx() and search_myMDV() do when their
  // catalog cannot be opened.
  //
  // This used to be exit( EXIT_FAILURE ), which was unreachable while download_asassnv() was
  // called on the line above the fopen(). Once that call was commented out the exit became
  // live, and when the ASAS-SN mirror started serving a truncated catalog in Sep 2026 that
  // the size checks correctly refused, every search whose VSX match falls outside the 6"
  // pre-pass died here - losing the full-radius VSX pass and the MDV search entirely.
  if ( 0 == asassnv_missing_warning_printed ) {
   fprintf( stderr, "WARNING: cannot open lib/catalogs/asassnv.csv - skipping the ASAS-SN part of the search\n" );
   asassnv_missing_warning_printed= 1;
  }
  a_catalog_was_unusable= 1;
  return -1;
 }
 while ( NULL != fgets( string, 4096 - 1, asassnv_csv ) ) {
  if ( strlen( string ) < 180 ) {
   // That happens all too often!
   //   fprintf(stderr,"WARNING from search_asassnv() a string in lib/catalogs/asassnv.csv is too short:\n%s\n",string);
   continue;
  }
  // Count the fields before anything else touches the line: a record with the
  // wrong number of them must not be parsed at all. See the guard below.
  number_of_commas_in_this_line= 0;
  for ( comma_index= 0; string[comma_index] != '\0'; comma_index++ ) {
   if ( string[comma_index] == ',' ) {
    number_of_commas_in_this_line++;
   }
  }
  // fix the FIRST PART of string for strtok() as it cannot handle empty cells ",,"
  // Assume Name RA and Dec will all fit within the first 100 characters
  // for( i= 0, j= 0; i < 4096 - 1; i++, j++ ) {
  for ( i= 0, j= 0; i < 100; i++, j++ ) {
   if ( j == 4096 - 1 ) {
    string_noemptycells[j]= '\0';
    break;
   }
   string_noemptycells[j]= string[i];
   // if( i < 4096 - 1 ) {
   if ( i < 4096 - 2 ) {
    if ( string[i] == ',' ) {
     if ( string[i + 1] == ',' ) {
      j++;
      string_noemptycells[j]= ' '; // add empty cell
     }
    }
   }
  }
  //
  string_noemptycells[j]= '\0'; // !!

  // We should do this before each invocation of getfield_from_csv_string() !!!
  strncpy( string_to_be_ruined_by_strtok, string_noemptycells, 4096 - 1 );
  string_to_be_ruined_by_strtok[4096 - 1]= '\0'; // just in case
  // Skip the header line -- old file format
  if ( 0 == strncmp( "ASAS-SN Name", getfield_from_csv_string( string_to_be_ruined_by_strtok, asassn_name_token ), strlen( "ASAS-SN Name" ) ) ) {
   expected_number_of_commas= number_of_commas_in_this_line;
   continue;
  }
  //
  // We should do this before each invocation of getfield_from_csv_string() !!!
  strncpy( string_to_be_ruined_by_strtok, string_noemptycells, 4096 - 1 );
  string_to_be_ruined_by_strtok[4096 - 1]= '\0'; // just in case
  // Skip the header line -- and detect new file format
  if ( 0 == strncmp( "source_id", getfield_from_csv_string( string_to_be_ruined_by_strtok, asassn_name_token ), strlen( "source_id" ) ) ) {
   // new file format
   asassn_name_token= 2;
   type_token= 11;
   meanmag_token= 8;
   amplitude_token= 9;
   period_token= 10;
   //   url_token= 0;
   //
   expected_number_of_commas= number_of_commas_in_this_line;
   continue;
  }
  //

  // A data record must carry the same number of comma-separated fields as the
  // header line that opens the file. Anything else is a damaged record, and
  // parsing it does not merely lose that star - it INVENTS one.
  //
  // getfield_from_csv_string() splits with strtok(), and strtok() collapses a
  // leading delimiter, while the ",," padding loop above only pads an empty cell
  // that sits BETWEEN two commas. A record that begins with a comma therefore has
  // every field shifted by one and still parses "successfully". The ASAS-SN copy
  // published in Feb 2026 contains exactly such a record - the tail half of a row
  // whose first 38 fields are gone, 316 characters long and so comfortably past
  // the 180-character filter above - and VaST read it as a variable star named
  // "0.034" of type "-1.649" at RA 0.021 Dec 6.79, reporting a false match to
  // anything searched near that position.
  //
  // The expected count is learned from the file's own header rather than
  // hard-coded to 79, so this works for the old and the new format alike and
  // cannot go stale if a future release adds a column.
  if ( expected_number_of_commas >= 0 && number_of_commas_in_this_line != expected_number_of_commas ) {
   if ( 0 == asassnv_malformed_record_warning_printed ) {
    fprintf( stderr, "WARNING: lib/catalogs/asassnv.csv contains at least one malformed record (%d comma-separated fields where the header has %d) - such records are skipped\n", number_of_commas_in_this_line + 1, expected_number_of_commas + 1 );
    asassnv_malformed_record_warning_printed= 1;
   }
   continue;
  }

  //// Dec
  // We should do this before each invocation of getfield_from_csv_string() !!!
  strncpy( string_to_be_ruined_by_strtok, string_noemptycells, 4096 - 1 );
  string_to_be_ruined_by_strtok[4096 - 1]= '\0'; // just in case
  Dec_deg= atof( getfield_from_csv_string( string_to_be_ruined_by_strtok, 5 ) );
  // atof() may return 0.0 if the input is just white spaces
  if ( Dec_deg < -90.0 || Dec_deg > +90.0 || Dec_deg == 0.0 ) {
   continue;
  }
  if ( fabs( target_Dec_deg - Dec_deg ) > search_radius_deg ) {
   continue;
  }

  //// RA
  // We should do this before each invocation of getfield_from_csv_string() !!!
  strncpy( string_to_be_ruined_by_strtok, string_noemptycells, 4096 - 1 );
  string_to_be_ruined_by_strtok[4096 - 1]= '\0'; // just in case
  RA_deg= atof( getfield_from_csv_string( string_to_be_ruined_by_strtok, 4 ) );
  // atof() may return 0.0 if the input is just white spaces
  if ( RA_deg < 0.0 || RA_deg > 360.0 || RA_deg == 0.0 ) {
   continue;
  }

  RA1_rad= RA_deg * M_PI / 180.0;
  RA2_rad= target_RA_deg * M_PI / 180.0;
  DEC1_rad= Dec_deg * M_PI / 180.0;
  DEC2_rad= target_Dec_deg * M_PI / 180.0;

  // yes, it mathces the definition in src/put_two_sources_in_one_field.c
  distance_deg= acos( cos( DEC1_rad ) * cos( DEC2_rad ) * cos( MAX( RA1_rad, RA2_rad ) - MIN( RA1_rad, RA2_rad ) ) + sin( DEC1_rad ) * sin( DEC2_rad ) ) * 180.0 / M_PI;

  if ( distance_deg < search_radius_deg ) {

   ////// Do the nasty conversions only if this is our star //////

   // fix the FULL string for strtok() as it cannot handle empty cells ",,"
   for ( i= 0, j= 0; i < 4096 - 1; i++, j++ ) {
    if ( j == 4096 - 1 ) {
     string_noemptycells[j]= '\0';
     break;
    }
    string_noemptycells[j]= string[i];
    // if( i < 4096 - 1 ) {
    if ( i < 4096 - 2 ) {
     if ( string[i] == ',' ) {
      if ( string[i + 1] == ',' ) {
       j++;
       string_noemptycells[j]= ' '; // add empty cell
      }
     }
    }
   }
   //
   string_noemptycells[j]= '\0'; // !!
   //

   //// Name
   // We should do this before each invocation of getfield_from_csv_string() !!!
   strncpy( string_to_be_ruined_by_strtok, string_noemptycells, 4096 - 1 );
   string_to_be_ruined_by_strtok[4096 - 1]= '\0'; // just in case
   strncpy( name, getfield_from_csv_string( string_to_be_ruined_by_strtok, asassn_name_token ), 32 );
   name[32 - 1]= '\0'; // just in case

   //// Type
   // We should do this before each invocation of getfield_from_csv_string() !!!
   strncpy( string_to_be_ruined_by_strtok, string_noemptycells, 4096 - 1 );
   string_to_be_ruined_by_strtok[4096 - 1]= '\0'; // just in case
   strncpy( type, getfield_from_csv_string( string_to_be_ruined_by_strtok, type_token ), 32 );
   type[32 - 1]= '\0'; // just in case

   //// MeanMag
   // We should do this before each invocation of getfield_from_csv_string() !!!
   strncpy( string_to_be_ruined_by_strtok, string_noemptycells, 4096 - 1 );
   string_to_be_ruined_by_strtok[4096 - 1]= '\0'; // just in case
   strncpy( MeanMag, getfield_from_csv_string( string_to_be_ruined_by_strtok, meanmag_token ), 32 );
   MeanMag[32 - 1]= '\0'; // just in case

   //// Amplitude
   // We should do this before each invocation of getfield_from_csv_string() !!!
   strncpy( string_to_be_ruined_by_strtok, string_noemptycells, 4096 - 1 );
   string_to_be_ruined_by_strtok[4096 - 1]= '\0'; // just in case
   strncpy( Amplitude, getfield_from_csv_string( string_to_be_ruined_by_strtok, amplitude_token ), 32 );
   Amplitude[32 - 1]= '\0'; // just in case

   //// Period
   // We should do this before each invocation of getfield_from_csv_string() !!!
   strncpy( string_to_be_ruined_by_strtok, string_noemptycells, 4096 - 1 );
   string_to_be_ruined_by_strtok[4096 - 1]= '\0'; // just in case
   strncpy( Period, getfield_from_csv_string( string_to_be_ruined_by_strtok, period_token ), 32 );
   Period[32 - 1]= '\0'; // just in case

   // no URL in new format
   //   //// Url
   //   // We should do this before each invocation of getfield_from_csv_string() !!!
   //   strncpy(string_to_be_ruined_by_strtok, string_noemptycells, 4096 - 1);
   //   string_to_be_ruined_by_strtok[4096 - 1]= '\0'; // just in case
   //   strncpy(Url, getfield_from_csv_string(string_to_be_ruined_by_strtok, url_token), 32);
   //   Url[32 - 1]= '\0'; // just in case
   ///////////////////////////////////////////////////////////////

   // if( is_found == 0 )
   if ( 1 == html_output ) {
    fprintf( stdout, "<b>The object was <font color=\"red\">found</font> in <font color=\"green\">ASASSN-V</font></b>\n" );
    fprintf( stdout, "<b>%2.0lf\"  %s</b>\nType: %s\nMeanMag %s m  Amp. %s m  Period %s d\n", distance_deg * 3600.0, name, type, MeanMag, Amplitude, Period );
   } else {
    fprintf( stdout, "The object was found in ASASSN-V\n" );
    fprintf( stdout, "%2.0lf\"  %s\nType: %s\nMeanMag %s m  Amp. %s m  Period %s d\n", distance_deg * 3600.0, name, type, MeanMag, Amplitude, Period );
   }
   // Compare the measured brightness of the transient with the brightest state
   // expected from the catalog record (if the measured magnitude was supplied).
   // The ASAS-SN catalog provides the mean magnitude and the full amplitude,
   // so conservatively assume the star may get as bright as the mean minus the
   // full amplitude. See the matching code in search_vsx() for the wording
   // constraints imposed by the downstream parsers.
   if ( measured_mag_of_transient > MEASURED_MAG_NOT_PROVIDED + 1.0 ) {
    if ( 1 == parse_mag_token( MeanMag, &asassn_mean_mag ) ) {
     expected_brightest_mag= asassn_mean_mag;
     if ( 1 == parse_mag_token( Amplitude, &asassn_amplitude ) ) {
      expected_brightest_mag= asassn_mean_mag - asassn_amplitude;
     }
     // Miras get a relaxed threshold as in search_vsx(); the semiregular
     // and slow-irregular blue-band relaxation of search_vsx() does not
     // apply here as the ASAS-SN mean magnitudes are V band
     brightening_warn_threshold_mag= is_mira_variability_type( type ) ? TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD_MIRA : TRANSIENT_BRIGHTER_THAN_CATALOG_MAG_THRESHOLD;
     if ( expected_brightest_mag - measured_mag_of_transient > brightening_warn_threshold_mag ) {
      if ( 1 == html_output ) {
       fprintf( stdout, "<b><font color=\"red\">ATTENTION: measured mag %.2f is %.1f mag brighter than the ASASSN-V record maximum brightness %.2f - possible unusual activity of a known variable!</font></b> (Alternatively, this may be a new object that coincides with the known variable's position just by chance.)\n", measured_mag_of_transient, expected_brightest_mag - measured_mag_of_transient, expected_brightest_mag );
      } else {
       fprintf( stdout, "ATTENTION: measured mag %.2f is %.1f mag brighter than the ASASSN-V record maximum brightness %.2f - possible unusual activity of a known variable! (Alternatively, this may be a new object that coincides with the known variable's position just by chance.)\n", measured_mag_of_transient, expected_brightest_mag - measured_mag_of_transient, expected_brightest_mag );
      }
     }
    }
   }
   is_found= 1;
   break; // find one and be happy
  }
 }
 if ( is_found == 0 && be_silent_if_not_found == 0 ) {
  if ( 1 == html_output ) {
   fprintf( stdout, "The object was <font color=\"green\">not found</font> in <font color=\"DarkSeaGreen\">ASASSN-V</font>\n" );
  } else {
   fprintf( stdout, "The object was not found in ASASSN-V\n" );
  }
 }

 fclose( asassnv_csv );

 return is_found;
}

// Is this catalog file present and not empty?
// Used only to decide whether the update script has to be run at all.
static int catalog_file_is_present_and_nonempty( const char *catalog_filename ) {
 FILE *catalog_file;
 long catalog_file_size;
 catalog_file= fopen( catalog_filename, "r" );
 if ( catalog_file == NULL ) {
  return 0;
 }
 if ( 0 != fseek( catalog_file, 0, SEEK_END ) ) {
  fclose( catalog_file );
  return 0;
 }
 catalog_file_size= ftell( catalog_file );
 fclose( catalog_file );
 if ( catalog_file_size > 0 ) {
  return 1;
 }
 return 0;
}

int main( int argc, char **argv ) {

 int html_output= 0; // 0 - no, 1 - yes

 int is_found;
 double target_RA_deg;
 double target_Dec_deg;
 double measured_mag;
 double measured_mag_input;
 char *endptr_argv4;

 measured_mag= MEASURED_MAG_NOT_PROVIDED;

 if ( argc < 3 ) {
  fprintf( stderr, "Usage: %s 12.345 67.890\nor\n%s 12.345 67.890 H  # for HTML output\nor\n%s 12.345 67.890 H 12.3  # HTML output + comparison of the measured transient mag 12.3 with the catalog record", argv[0], argv[0], argv[0] );
  return 1;
 }

 if ( strchr( argv[1], ':' ) != NULL || strchr( argv[2], ':' ) != NULL ) {
  fprintf( stderr, "ERROR: The input RA contains a colon ':'.\nOnly decimal degrees are supported by this binary! Sorry!\n" );
  return 2;
 }

 target_RA_deg= atof( argv[1] );
 if ( target_RA_deg < 0.0 || target_RA_deg > 360.0 ) {
  fprintf( stderr, "ERROR: the input RA (%s interpreted as %lf) is our of range!\n", argv[1], target_RA_deg );
  return 2;
 }
 target_Dec_deg= atof( argv[2] );
 if ( target_Dec_deg < -90.0 || target_Dec_deg > 90.0 ) {
  fprintf( stderr, "ERROR: the input Dec (%s interpreted as %lf) is our of range!\n", argv[2], target_Dec_deg );
  return 2;
 }

 if ( argc >= 4 ) {
  if ( argv[3][0] == 'H' ) {
   html_output= 1;
  }
 }

 // The optional 5th command line argument is the measured magnitude of the
 // transient. When it is provided (by util/transients/report_transient.sh),
 // a match with a known variable star will be checked for a large brightness
 // difference between the measurement and the catalog record expectation.
 if ( argc >= 5 ) {
  measured_mag_input= strtod( argv[4], &endptr_argv4 );
  while ( *endptr_argv4 == ' ' || *endptr_argv4 == '\t' ) {
   endptr_argv4++;
  }
  if ( endptr_argv4 == argv[4] || *endptr_argv4 != '\0' || measured_mag_input < -2.0 || measured_mag_input > 30.0 ) {
   fprintf( stderr, "WARNING: ignoring the measured transient magnitude '%s' that does not look like a valid magnitude value\n", argv[4] );
  } else {
   measured_mag= measured_mag_input;
  }
 }

 // This script should take care of updating the catalogs.
 // Note: The relative path "lib/update_offline_catalogs.sh" requires this program to be
 // executed from the VaST root directory. Calling scripts (e.g., util/search_databases_with_vizquery.sh)
 // must ensure they cd to VAST_PATH before invoking this binary.
 //
 // Run it only when one of the two catalogs this program reads is actually
 // missing. This used to be unconditional, and since the program is executed
 // once per transient candidate, that meant forking a shell script for every
 // candidate of every field for the whole night. When the catalogs are in
 // place the script does nothing and returns in about 0.06 s, so the waste was
 // invisible - until a mirror started serving a truncated ASAS-SN catalog that
 // the size checks correctly refused. The catalog then never appeared, every
 // candidate re-downloaded and re-rejected it at about 2 s a time, and the
 // 2026-09-14 CI run spent three hours in one test before the 300-minute
 // GitHub Actions limit killed it.
 // Refreshing catalogs that are present but stale is not this program's job:
 // the transient factory and the other entry points run the update script at
 // startup for exactly that purpose.
 if ( 0 == catalog_file_is_present_and_nonempty( "lib/catalogs/vsx.dat" ) ||
      0 == catalog_file_is_present_and_nonempty( "lib/catalogs/asassnv.csv" ) ) {
  if ( 0 != system( "lib/update_offline_catalogs.sh all" ) ) {
   fprintf( stderr, "WARNING: an error occured while updating the catalogs with lib/update_offline_catalogs.sh\n" );
  }
 }

 is_found= 0; // init

 // The use of the reduced search radius is a silly attempt to handle the situation where
 // multiple known variables are within the search radius and ideally we want the nearest one to the search position.

 if ( measured_mag > MEASURED_MAG_NOT_PROVIDED + 1.0 ) {
  // With a measured magnitude available, search_vsx() itself prefers the
  // nearest brightness-compatible match over the full search radius, so the
  // small-radius pre-pass must not run: it would lock in a faint nearest
  // match and hide a compatible brighter variable sitting at 7-15" (common
  // in crowded galactic-plane fields).
  is_found= search_vsx( target_RA_deg, target_Dec_deg, VSX_SEARCH_RADIUS_DEG, 0, html_output, measured_mag );
  if ( is_found != 1 ) {
   is_found= search_asassnv( target_RA_deg, target_Dec_deg, ASASSN_SEARCH_RADIUS_DEG / 5.0, 1, html_output, measured_mag );
  }
  if ( is_found != 1 ) {
   is_found= search_asassnv( target_RA_deg, target_Dec_deg, ASASSN_SEARCH_RADIUS_DEG, 0, html_output, measured_mag );
  }
 } else {
  // First try small search radius
  // was 3.0 an caused problems with the STANDALONEDBSCRIPT_MULTCLOSEVAR test, 5 is not cutting it
  // is_found= search_vsx( target_RA_deg, target_Dec_deg, VSX_SEARCH_RADIUS_DEG / 5.0, 1, html_output, measured_mag );
  is_found= search_vsx( target_RA_deg, target_Dec_deg, 6.0 / 3600, 1, html_output, measured_mag );
  if ( is_found != 1 ) {
   is_found= search_asassnv( target_RA_deg, target_Dec_deg, ASASSN_SEARCH_RADIUS_DEG / 5.0, 1, html_output, measured_mag );
  }
  // If nothing found - try a larger search radius
  if ( is_found != 1 ) {
   is_found= search_vsx( target_RA_deg, target_Dec_deg, VSX_SEARCH_RADIUS_DEG, 0, html_output, measured_mag );
  }
  if ( is_found != 1 ) {
   is_found= search_asassnv( target_RA_deg, target_Dec_deg, ASASSN_SEARCH_RADIUS_DEG, 0, html_output, measured_mag );
  }
 }
 if ( is_found != 1 ) {
  is_found= search_myMDV( target_RA_deg, target_Dec_deg, VSX_SEARCH_RADIUS_DEG, 0, html_output );
 }

 // Return 0 if the source is found
 if ( is_found == 1 ) {
  return 0;
 }

 // 3 means "not found, but at least one catalog could not be read, so this is
 // NOT a confident non-detection". It has to be 3 rather than 2: 2 is already
 // returned above for a colon in the input and for an out-of-range RA/Dec, so
 // reusing it would make every caller that passes sexagesimal coordinates look
 // like a catalog outage. Callers that only test for 0 are unaffected, and the
 // one caller that tests for non-zero - report_transient.sh, which stores this
 // in VARIABLE_STAR_ID and proceeds to the online search when it is not 0 -
 // does the right thing with 3 already.
 if ( 0 != a_catalog_was_unusable ) {
  return 3;
 }

 return 1;
}
