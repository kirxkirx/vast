#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// #define VSX_SEARCH_RADIUS_DEG 35.0 / 3600.0
#define VSX_SEARCH_RADIUS_DEG 25.0 / 3600.0

#define ASASSN_SEARCH_RADIUS_DEG 20.0 / 3600.0

/* Auxiliary definitions */
#define MAX( a, b ) ( ( ( a ) > ( b ) ) ? ( a ) : ( b ) )
#define MIN( a, b ) ( ( ( a ) < ( b ) ) ? ( a ) : ( b ) )

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

int search_vsx( double target_RA_deg, double target_Dec_deg, double search_radius_deg, int be_silent_if_not_found, int html_output ) {
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

 // download_vsx();
 vsx_dat= fopen( "lib/catalogs/vsx.dat", "r" );
 if ( NULL == vsx_dat ) {
  fprintf( stderr, "ERROR: Cannot open vsx.dat\n" );
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
  if ( 1 == html_output ) {
   fprintf( stdout, "<b>%2.0lf\"  %s</b>\nType: %s\n#   Max.           Min./Amp.       JD0           Period\n%s", best_distance_deg * 3600.0, best_name, best_type, best_descr );
  } else {
   fprintf( stdout, "%2.0lf\"  %s\nType: %s\n#   Max.           Min./Amp.       JD0           Period\n%s", best_distance_deg * 3600.0, best_name, best_type, best_descr );
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

int search_asassnv( double target_RA_deg, double target_Dec_deg, double search_radius_deg, int be_silent_if_not_found, int html_output ) {
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

 int is_found= 0;

 // old format (the new format is described below and should be detected automatically)
 int asassn_name_token= 1;
 int type_token= 9;
 int meanmag_token= 6;
 int amplitude_token= 7;
 int period_token= 8;

 asassnv_csv= fopen( "lib/catalogs/asassnv.csv", "r" );
 if ( NULL == asassnv_csv ) {
  fprintf( stderr, "ERROR: Cannot open asassnv.csv\n" );
  exit( EXIT_FAILURE );
 }
 while ( NULL != fgets( string, 4096 - 1, asassnv_csv ) ) {
  if ( strlen( string ) < 180 ) {
   // That happens all too often!
   //   fprintf(stderr,"WARNING from search_asassnv() a string in lib/catalogs/asassnv.csv is too short:\n%s\n",string);
   continue;
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
   continue;
  }
  //

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

int main( int argc, char **argv ) {

 int html_output= 0; // 0 - no, 1 - yes

 int is_found;
 double target_RA_deg;
 double target_Dec_deg;

 if ( argc < 3 ) {
  fprintf( stderr, "Usage: %s 12.345 67.890\nor\n%s 12.345 67.890 H  # for HTML output", argv[0], argv[0] );
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

 // This script should take care of updating the catalogs
 if ( 0 != system( "lib/update_offline_catalogs.sh all" ) ) {
  fprintf( stderr, "WARNING: an error occured while updating the catalogs with lib/update_offline_catalogs.sh\n" );
 }

 is_found= 0; // init

 // The use of the reduced search radius is a silly attempt to handle the situation where
 // multiple known variables are within the search radius and ideally we want the nearest one to the search position.

 // First try small search radius
 is_found= search_vsx( target_RA_deg, target_Dec_deg, VSX_SEARCH_RADIUS_DEG / 3.0, 1, html_output );
 if ( is_found != 1 ) {
  is_found= search_asassnv( target_RA_deg, target_Dec_deg, ASASSN_SEARCH_RADIUS_DEG / 3.0, 1, html_output );
 }
 // If nothing found - try a larger search radius
 if ( is_found != 1 ) {
  is_found= search_vsx( target_RA_deg, target_Dec_deg, VSX_SEARCH_RADIUS_DEG, 0, html_output );
 }
 if ( is_found != 1 ) {
  is_found= search_asassnv( target_RA_deg, target_Dec_deg, ASASSN_SEARCH_RADIUS_DEG, 0, html_output );
 }
 if ( is_found != 1 ) {
  is_found= search_myMDV( target_RA_deg, target_Dec_deg, VSX_SEARCH_RADIUS_DEG, 0, html_output );
 }

 // Return 0 if the source is found
 if ( is_found == 1 ) {
  return 0;
 }

 return 1;
}
