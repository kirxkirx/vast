#include <stdio.h>
#include <stdlib.h>

#include <string.h> // for strncmp()

#include <libgen.h> // for basename()

#include <unistd.h>    // for getpid() and unlink()
#include <sys/types.h> // for getpid()

#include <ctype.h> // for isdigit()

#include <time.h>

#include "fitsio.h"

#include "ident.h"

#include "vast_limits.h"

// If the input string is not an image file - assume this is a time string that needs to be converted to other date formats.
// This is accomplished using a very inefficient way of creating a fake FITS image - all for the sake of consistency 
// with the existing FITS header reading and JD-conversion code.
int fake_image_hack( char *input_string ) {

 int keytype;
 fitsfile *fptr;
 int status= 0;
 long fpixel= 1;
 long naxes[2];

 unsigned short combined_array[]= {0, 0, 0, 0};

 char card[FLEN_CARD], newcard[FLEN_CARD], fitsfilename[FILENAME_LENGTH];

 int input_calendar_date_or_jd=0; // 0 - calendar, 1 - JD
 unsigned int number_of_characters_inputs_str;
 unsigned int i,j; // counter
 double jd_from_string;

 FILE *f;

 f= fopen( input_string, "r" );
 if ( NULL != f ) {
  // This is a file, nothing to do
  fclose( f );
  return 0;
 }
 
 // Check input string
 number_of_characters_inputs_str=strlen(input_string);
 // check if the number of characters is reasonable
 if( number_of_characters_inputs_str<7 ){
  fprintf(stderr,"ERROR in fake_image_hack(): the number of characters in the input string #%s# is %d, less than expected\n",input_string,number_of_characters_inputs_str);
  return 0;
 }
 if( number_of_characters_inputs_str>26 ){
  fprintf(stderr,"ERROR in fake_image_hack(): the number of characters in the input string #%s# is %d, more than expected\n",input_string,number_of_characters_inputs_str);
  return 0;
 }

 // Determine if the input is the calendar date or JD
 input_calendar_date_or_jd= 0; // assume calendar date by default
 // Check that we have exactly one '.'
 for ( j= 0, i= 0; i < number_of_characters_inputs_str; i++ ) {
  //
  if ( 0 != isdigit( input_string[i] ) ) {
   continue;
  }
  if ( input_string[i] == '.' ) {
   j++;
   continue;
  }
  // If we are here, that means there was an ilegal character in the input
  j=99;
  break;
 } // for ( j= 0, i= 0; i < strlen( argv[1] ); i++ ) { 
 if( j==1 ){
  // OK, there is only one '.' in the string, that looks promising
  jd_from_string=atof(input_string);
  if ( jd_from_string>EXPECTED_MIN_MJD && jd_from_string<EXPECTED_MAX_JD ){
   input_calendar_date_or_jd= 1; // this looks like a JD
  }
 }
 //

 sprintf( fitsfilename, "fake_image_hack_%d.fits", getpid() );

 fits_create_file( &fptr, fitsfilename, &status ); /* create new file */
 naxes[0]= naxes[1]= 2;
 fits_create_img( fptr, USHORT_IMG, 2, naxes, &status );
 fits_write_img( fptr, TUSHORT, fpixel, naxes[0] * naxes[1], combined_array, &status );

 if ( input_calendar_date_or_jd== 1 ){
  // Writing this into JD keyword
  sprintf( newcard,"JD = %.5lf / JD (UTC)",jd_from_string);
  // reformat the keyword string to conform to FITS rules
  fits_parse_template( newcard, card, &keytype, &status );
  // overwrite the keyword with the new value
  fits_update_card( fptr, "JD", card, &status );
 }
 else{ 
  // The defaultassumption is to write DATE-OBS
  strcpy( newcard, "DATE-OBS" );                                  // keyword name
  strcat( newcard, " = " );                                       // '=' value delimiter
  strcat( newcard, input_string );                                // new value
  strcat( newcard, " / " );                                       // comment delimiter
  strcat( newcard, "Exposure start time (UTC) derived by VaST" ); // append the comment
  // reformat the keyword string to conform to FITS rules
  fits_parse_template( newcard, card, &keytype, &status );
  // overwrite the keyword with the new value
  fits_update_card( fptr, "DATE-OBS", card, &status );
 }
 
 strcpy( newcard, "EXPTIME" );            // keyword name
 strcat( newcard, " = " );                // '=' value delimiter
 strcat( newcard, "0" );                  // new value
 strcat( newcard, " / " );                // comment delimiter
 strcat( newcard, "fake exposure time" ); // append the comment
 // reformat the keyword string to conform to FITS rules
 fits_parse_template( newcard, card, &keytype, &status );
 // overwrite the keyword with the new value
 fits_update_card( fptr, "EXPTIME", card, &status );

 fits_close_file( fptr, &status ); // close file
 fits_report_error( stderr, status );

 strncpy( input_string, fitsfilename, FILENAME_LENGTH );

 return 1; // yes, we created the fake image
}

int main( int argc, char **argv ) {

 double JD, dimX, dimY;
 int timesys= 0;
 int convert_timesys_to_TT= 0;
 char *stderr_output;
 char *log_output;
 int param_nojdkeyword= 0;
 int param_verbose= 1;

 double MJD, UnixTime, Julian_year;

 time_t UnixTime_time_t;
 struct tm *structureTIME;

 char input_fits_image[FILENAME_LENGTH];

 int fake_image_hack_return;

 if ( 0 == strncmp( "fix_image_date", basename( argv[0] ), 14 ) ) {
  param_verbose= 2;
  fprintf( stderr, "\n\n\n################## Will try to fix DATE-OBS and EXPTIME keywords in the FITS header ##################\n\n" );
 }

 if ( argc == 1 ) {
  fprintf( stderr, "This program will get observation time from an image header.\n" );
  if ( param_verbose == 2 ) {
   fprintf( stderr, "It will then try to write the derived infromation into DATE-OBS and EXPTIME keywords.\n" );
  }
  fprintf( stderr, "\nUsage:\n %s image.fits\n", argv[0] );
  if ( param_verbose != 2 ) {
   fprintf( stderr, "or\n %s '2014-09-09T05:29:55'\nor\n %s '2456909.72911'\n", argv[0], argv[0] );
  }
  return 1;
 }

 strncpy( input_fits_image, argv[1], FILENAME_LENGTH );
 input_fits_image[FILENAME_LENGTH - 1]= '\0'; // just in case

 fake_image_hack_return= fake_image_hack( input_fits_image );

 if ( fake_image_hack_return == 1 ) {
  param_verbose= 0;
 }

 stderr_output= malloc( 1024 * sizeof( char ) );
 if ( stderr_output == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for stderr_output(get_image_date.c)\n" );
  exit( 1 );
 };
 log_output= malloc( 1024 * sizeof( char ) );
 if ( log_output == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for log_output(get_image_date.c)\n" );
  exit( 1 );
 };

 // Get the date
 if ( 0 != gettime( input_fits_image, &JD, &timesys, convert_timesys_to_TT, &dimX, &dimY, stderr_output, log_output, param_nojdkeyword, param_verbose ) ) {
  fprintf( stderr, "ERROR getting observing time from the input image %s\n", argv[1] );
  free( stderr_output );
  free( log_output );
  return 1;
 }

 if ( fake_image_hack_return == 1 ) {
  unlink( input_fits_image );
 }

 // Convert the date to other formats
 MJD= JD - 2400000.5;
 UnixTime= ( JD - 2440587.5 ) * 86400.0;
 Julian_year= 2000.0 + ( JD - 2451545.0 ) / 365.25;
 if ( UnixTime<0.0 ){
  UnixTime_time_t= (time_t)(UnixTime - 0.5);
 } else{
  // UnixTime is double, so we add 0.5 for the propoer type conversion
  UnixTime_time_t= (time_t)(UnixTime + 0.5);
 }
 structureTIME= gmtime( &UnixTime_time_t );

 // Print output
 fprintf( stdout, "%s\n", stderr_output );
 fprintf( stdout, "\n --== Observation date in various formats ==--\n" );
 fprintf( stdout, "         JD %14.6lf\n", JD );
 fprintf( stdout, "        MJD %14.6lf\n", MJD );
 fprintf( stdout, "  Unix Time %.0lf\n", UnixTime );
 fprintf( stdout, "Julian year %14.9lf\n", Julian_year );
// The roblem is that the sub-second accuracy is lost in this output
 fprintf( stdout, " MPC format %04d %02d %8.5lf\n", structureTIME->tm_year - 100 + 2000, structureTIME->tm_mon + 1, (double)structureTIME->tm_mday + (double)structureTIME->tm_hour / 24.0 + (double)structureTIME->tm_min / ( 24.0 * 60 ) + (double)structureTIME->tm_sec / ( 24.0 * 60 * 60 ) );
// fprintf( stdout, " MPC format %04d %02d %8.6lf\n", structureTIME->tm_year - 100 + 2000, structureTIME->tm_mon + 1, (double)structureTIME->tm_mday + (double)structureTIME->tm_hour / 24.0 + (double)structureTIME->tm_min / ( 24.0 * 60 ) + (double)structureTIME->tm_sec / ( 24.0 * 60 * 60 ) );
 //
 //fprintf( stderr, "DEBUG UnixTime_time_t=%ld UnixTime(double)=%lf\n",UnixTime_time_t,UnixTime);

 // Clean up
 free( log_output );
 free( stderr_output );

// Check if the output was actually reasonable
#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
 if ( JD < EXPECTED_MIN_JD )
  return 1;
 if ( JD > EXPECTED_MAX_JD )
  return 1;
 if ( MJD < EXPECTED_MIN_MJD )
  return 1;
 if ( MJD > EXPECTED_MAX_MJD )
  return 1;
#endif

 return 0;
}
