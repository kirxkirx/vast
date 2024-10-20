#include "kourovka_sbg_date.h"

int Kourovka_SBG_date_hack( char *fitsfilename, char *DATEOBS, int *date_parsed, double *exposure ) {
 // Kourovka-SBG camera images have a very unusual header.
 // This function is supposed to handle it.

 FILE *f;      // FITS file
 char *buffer; // buffer for a part of the header
 char *pointer_to_the_key_start;
 int i; // counter
 char output_string[512];
 int day, month, year;
 int hour, minute;
 double second;
 double exp;
 char tmp[512];

 // allocate buffer
 buffer= malloc( 65536 * sizeof( char ) );
 if ( buffer == NULL ) {
  fprintf( stderr, "ERROR in Kourovka_SBG_date_hack(): cannot allocate buffer memory\n" );
  return 1;
 }
 // read first part of the file to the buffer
 f= fopen( fitsfilename, "r" );
 if ( f == NULL ) {
  fprintf( stderr, "ERROR in Kourovka_SBG_date_hack(): cannot open file %s\n", fitsfilename );
  free( buffer );
  return 1;
 }
 for ( i= 0; i < 65535; i++ ) {
  buffer[i]= getc( f );
  if ( buffer[i] == EOF ) {
   break;
  }
 }
 fclose( f );
 // search for the substrings
 // date
 pointer_to_the_key_start= (char *)memmem( buffer, 65535 - 80, "Date      ", 10 );
 if ( pointer_to_the_key_start == NULL ) {
  fprintf( stderr, "ERROR in Kourovka_SBG_date_hack(): cannot find date\n" );
  free( buffer );
  return 1;
 }
 ( *( pointer_to_the_key_start + 79 * sizeof( char ) ) )= '\0';
 sscanf( pointer_to_the_key_start, "Date                %d.%d.%d", &day, &month, &year );
 fprintf( stderr, "%s\n", pointer_to_the_key_start );
 // exposure
 pointer_to_the_key_start= (char *)memmem( buffer, 65535 - 80, "ExpTime", 7 );
 if ( pointer_to_the_key_start == NULL ) {
  fprintf( stderr, "ERROR in Kourovka_SBG_date_hack(): cannot find exposure time\n" );
  free( buffer );
  return 1;
 }
 ( *( pointer_to_the_key_start + 79 * sizeof( char ) ) )= '\0';
 sscanf( pointer_to_the_key_start, "ExpTime,%s = %lf", tmp, &exp );
 fprintf( stderr, "%s\n", pointer_to_the_key_start );
 // time
 pointer_to_the_key_start= (char *)memmem( buffer, 65535 - 80, "UTC1, h:m:s =", 13 );
 if ( pointer_to_the_key_start == NULL ) {
  fprintf( stderr, "ERROR in Kourovka_SBG_date_hack(): cannot find date\n" );
  free( buffer );
  return 1;
 }
 ( *( pointer_to_the_key_start + 79 * sizeof( char ) ) )= '\0';
 sscanf( pointer_to_the_key_start, "UTC1, h:m:s =      %d:%d:%lf", &hour, &minute, &second );
 fprintf( stderr, "%s\n", pointer_to_the_key_start );

 sprintf( output_string, "%04d-%02d-%02dT%02d:%02d:%07.4lf", year, month, day, hour, minute, second );
 fprintf( stderr, "%s\nexposure = %.2lf\n", output_string, exp );
 free( buffer );

 if ( day < 0 || day > 31 ) {
  fprintf( stderr, "ERROR in Kourovka_SBG_date_hack()\n" );
  return 1;
 }
 if ( month < 1 || month > 12 ) {
  fprintf( stderr, "ERROR in Kourovka_SBG_date_hack()\n" );
  return 1;
 }
 if ( year < 1950 || year > 2200 ) {
  fprintf( stderr, "ERROR in Kourovka_SBG_date_hack()\n" );
  return 1;
 }
 if ( hour < 0 || hour > 24 ) {
  fprintf( stderr, "ERROR in Kourovka_SBG_date_hack()\n" );
  return 1;
 }
 if ( minute < 0 || minute > 60 ) {
  fprintf( stderr, "ERROR in Kourovka_SBG_date_hack()\n" );
  return 1;
 }
 if ( second < 0.0 || second > 60.0 ) {
  fprintf( stderr, "ERROR in Kourovka_SBG_date_hack()\n" );
  return 1;
 }

 if ( exp < SHORTEST_EXPOSURE_SEC || exp > LONGEST_EXPOSURE_SEC ) {
  fprintf( stderr, "WARNING from Kourovka_SBG_date_hack(): cannot get exposure time from the image header!\nAssuming zero exposure time!\n" );
  exp= 0.0;
 }

 strcpy( DATEOBS, output_string );
 ( *date_parsed )= 1;
 ( *exposure )= exp;

 return 0;
}
