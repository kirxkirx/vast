#include <stdio.h>
#include <stdlib.h>
#include <string.h>    // for strncmp()
#include <libgen.h>    // for basename()
#include <unistd.h>    // for getpid() and unlink()
#include <sys/types.h> // for getpid()
#include <ctype.h>     // for isdigit()
#include <time.h>

#include "fitsio.h"
#include "vast_limits.h"
#include "vast_types.h"
#include "ident.h"

void fix_DATEOBS_STRING( char *DATEOBS );                                                                                                                                                                      // defined in gettime.c
void fix_DATEOBS_STRING__DD_MM_YYYY_format( char *DATEOBS );                                                                                                                                                   // defined in gettime.c
void form_DATEOBS_EXPTIME_log_output_from_JD( double JD, double exposure_sec, char *formed_str_DATEOBS, char *formed_str_EXPTIME, char *log_output, char *finder_chart_timestring_output, int stderr_silent ); // defined in gettime.c

void remove_multiple_white_spaces_from_string( char *string ) {
 unsigned int i, j;
 // fprintf(stderr,"DEBUG(1) #%s#\n", string);
 for ( i= 1; i < strlen( string ); i++ ) {
  if ( string[i - 1] == ' ' && string[i] == ' ' ) {
   for ( j= i; j < strlen( string ) - 1; j++ ) {
    string[j]= string[j + 1];
   }
   string[j]= '\0';
   // fprintf(stderr,"DEBUG(2) #%s#\n", string);
   i--;
  }
 }
 // fprintf(stderr,"DEBUG(3) #%s#\n", string);
 return;
}

void remove_leading_white_spaces_before_first_digit_from_string( char *string ) {
 unsigned int i, j;
 // fprintf(stderr,"DEBUG(11) #%s#\n", string);
 for ( i= 0; i < strlen( string ); i++ ) {
  if ( 0 != isdigit( string[i] ) ) {
   break;
  } else {
   // if ( string[i] == ' ' ){
   for ( j= i; j < strlen( string ) - 1; j++ ) {
    string[j]= string[j + 1];
   }
   string[j]= '\0';
   // fprintf(stderr,"DEBUG(12) #%s#\n", string);
   i--;
  }
 }
 // fprintf(stderr,"DEBUG(13) #%s#\n", string);
 return;
}

// If the input string is not an image file - assume this is a time string that needs to be converted to other date formats.
// This is accomplished using a very inefficient way of creating a fake FITS image - all for the sake of consistency
// with the existing FITS header reading and JD-conversion code.
int fake_image_hack( char *input_string ) {

 int keytype;
 fitsfile *fptr;
 int status= 0;
 long fpixel= 1;
 long naxes[2];

 unsigned short combined_array[]= { 0, 0, 0, 0 };

 // I want to add some buffer to newcard[]
 char card[FLEN_CARD], newcard[FLEN_CARD + 2048], fitsfilename[FILENAME_LENGTH];

 char processed_input_string[FLEN_CARD];

 int input_calendar_date_or_jd= 0; // 0 - calendar, 1 - JD
 unsigned int number_of_characters_inputs_str;
 unsigned int i, j; // counter
 double jd_from_string;

 double year, month, day, iday, hour, ihour, min, imin, sec; // for handling the YYYY-MM-DD.DDDD format

 FILE *f;

 f= fopen( input_string, "r" );
 if ( NULL != f ) {
  // This is a file, nothing to do
  fclose( f );
  return 0;
 }

 // Check input string
 number_of_characters_inputs_str= strlen( input_string );
 // check if the number of characters is reasonable
 if ( number_of_characters_inputs_str < 5 ) {
  fprintf( stderr, "ERROR in fake_image_hack(): the number of characters in the input string #%s# is %d, less than expected\n", input_string, number_of_characters_inputs_str );
  return 0;
 }
 // if( number_of_characters_inputs_str>26 ){
 if ( number_of_characters_inputs_str > 40 ) {
  fprintf( stderr, "ERROR in fake_image_hack(): the number of characters in the input string #%s# is %d, more than expected\n", input_string, number_of_characters_inputs_str );
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
  // allow for exponential notation
  if ( input_string[i] == 'e' || input_string[i] == 'E' || input_string[i] == '+' ) {
   continue;
  }
  // count decimal points
  if ( input_string[i] == '.' ) {
   j++;
   continue;
  }
  // If we are here, that means there was an illegal character in the input
  j= 99;
  break;
 } // for ( j= 0, i= 0; i < strlen( argv[1] ); i++ ) {
 if ( j == 0 || j == 1 ) {
  // fprintf( stderr, "DEBUG02\n");
  //  OK, there is zero or only one '.' in the string, that looks promising
  jd_from_string= atof( input_string );
  if ( jd_from_string > EXPECTED_MIN_MJD && jd_from_string < EXPECTED_MAX_JD ) {
   input_calendar_date_or_jd= 1; // this looks like a JD
   // now figure out if this is JD or MJD
   if ( jd_from_string < EXPECTED_MAX_MJD ) {
    fprintf( stderr, "Assuming the input is MJD\n" );
    jd_from_string= jd_from_string + 2400000.5;
   } else { // if ( jd_from_string<EXPECTED_MAX_MJD ) {
    fprintf( stderr, "Assuming the input is JD\n" );
   } // else if ( jd_from_string<EXPECTED_MAX_MJD ) {
  } // if ( jd_from_string>EXPECTED_MIN_MJD && jd_from_string<EXPECTED_MAX_JD ) {
 } // if( j==1 ){ // OK, there is only one '.' in the string, that looks promising
 //
 // fprintf( stderr, "DEBUG03\n");
 // handle the white space between the input date and time instead of T
 int is_T_found= 0;
 if ( input_calendar_date_or_jd == 0 ) {
  // fprintf( stderr, "DEBUG04\n");
  strncpy( processed_input_string, input_string, FLEN_CARD );
  processed_input_string[FLEN_CARD - 1]= '\0'; // just in case
  for ( i= 0; i < strlen( processed_input_string ); i++ ) {
   if ( processed_input_string[i] == 'T' ) {
    is_T_found= 1;
    // fprintf( stderr, "DEBUG05\n");
    break;
   }
  }
  // fprintf( stderr, "DEBUG06\n");
  if ( is_T_found == 0 ) {
   // fprintf( stderr, "DEBUG07 #%s#\n", processed_input_string);
   remove_multiple_white_spaces_from_string( processed_input_string );
   // fprintf( stderr, "DEBUG08 #%s#\n", processed_input_string);
   remove_leading_white_spaces_before_first_digit_from_string( processed_input_string );
   // fprintf( stderr, "DEBUG09 #%s#\n", processed_input_string);
   //  make sure the last character of the string is not white space
   if ( processed_input_string[strlen( processed_input_string ) - 1] == ' ' ) {
    processed_input_string[strlen( processed_input_string ) - 1]= '\0';
   }
   // run this early to handle 04.02.2012 02:48:30 - style dates
   fix_DATEOBS_STRING__DD_MM_YYYY_format( processed_input_string );
   //
   // fprintf( stderr, "DEBUG10 #%s#\n", processed_input_string);
   if ( 3 == sscanf( processed_input_string, "%lf %lf %lf", &year, &month, &day ) ) {
    // fprintf( stderr, "DEBUG11 #%s#\n", processed_input_string);
    for ( j= 0, i= 0; i < strlen( processed_input_string ); i++ ) {
     if ( processed_input_string[i] == '-' ) {
      // fprintf( stderr, "DEBUG12a #%s#\n", processed_input_string);
      break;
     }
     if ( processed_input_string[i] == ' ' ) {
      processed_input_string[i]= '-';
      j++;
      if ( j == 2 ) {
       // fprintf( stderr, "DEBUG12 #%s#\n", processed_input_string);
       break;
      }
     }
    }
   }
   // fprintf( stderr, "DEBUG13 #%s#\n", processed_input_string);
   //  We don't want the last character to be T
   for ( i= 1; i < strlen( processed_input_string ) - 1; i++ ) {
    if ( 0 != isdigit( processed_input_string[i - 1] ) && processed_input_string[i] == ' ' ) {
     processed_input_string[i]= 'T';
     // fprintf( stderr, "DEBUG14 #%s#\n", processed_input_string);
     break;
    }
   }
   // fprintf( stderr, "DEBUG15 #%s#\n", processed_input_string);
   //  handle the case where only the date and no time is given (assume 00:00:00 UT),
   //  or a fraction of the day is specified
   is_T_found= 0;
   for ( i= 0; i < strlen( processed_input_string ); i++ ) {
    if ( processed_input_string[i] == 'T' ) {
     is_T_found= 1;
     // fprintf( stderr, "DEBUG16 #%s#\n", processed_input_string);
     break;
    }
   }
   // fprintf( stderr, "DEBUG17 #%s#\n", processed_input_string);
   if ( is_T_found == 0 ) {
    // fprintf( stderr, "DEBUG18 #%s#\n", processed_input_string);
    //  T was not found, so there was no white space in the input string
    //  handle the insane DD/MM/YYYY format (no fraction of the day)
    fix_DATEOBS_STRING( processed_input_string );
    fix_DATEOBS_STRING__DD_MM_YYYY_format( processed_input_string ); // handle '09-10-2017' style DATE-OBS
    // fprintf( stderr, "DEBUG19 #%s#\n", processed_input_string);
    //  handle YYYY-MM-DD.DDDD
    sscanf( processed_input_string, "%lf%*1[ -]%lf%*1[ -]%lf", &year, &month, &day );
    // fprintf(stderr, "DEBUG20a: %.0lf %.0lf %lf\n", year, month, day);
    // fprintf( stderr, "DEBUG20 #%s#\n", processed_input_string);
    iday= (double)(int)day;
    hour= ( day - iday ) * 24;
    ihour= (double)(int)( hour );
    min= ( hour - ihour ) * 60;
    imin= (double)(int)( min );
    sec= ( min - imin ) * 60;
    sprintf( processed_input_string, "%4.0lf-%02.0lf-%02.0lfT%02.0lf:%02.0lf:%06.3lf", year, month, iday, ihour, imin, sec );
    // fprintf( stderr, "DEBUG21 #%s#\n", processed_input_string);
    //  exit( EXIT_FAILURE );
   } // if ( is_T_found == 0 ) {
   //
   // fprintf( stderr, "DEBUG22 #%s#\n", processed_input_string);
  } // if ( is_T_found == 0 ) { // yes the higher level
  // fprintf( stderr, "DEBUG23 #%s#\n", processed_input_string);
 } // if ( input_calendar_date_or_jd == 0 ){
 // fprintf( stderr, "DEBUG24 #%s#\n", processed_input_string);
 //

 sprintf( fitsfilename, "fake_image_hack_%d.fits", getpid() );

 // fprintf( stderr, "DEBUG24a #%s#\n", processed_input_string);

 fits_create_file( &fptr, fitsfilename, &status ); /* create new file */
 naxes[0]= naxes[1]= 2;
 // fprintf( stderr, "DEBUG24b #%s#\n", processed_input_string);
 fits_create_img( fptr, USHORT_IMG, 2, naxes, &status );
 // fprintf( stderr, "DEBUG24c #%s#\n", processed_input_string);
 fits_write_img( fptr, TUSHORT, fpixel, naxes[0] * naxes[1], combined_array, &status );
 // fprintf( stderr, "DEBUG24d #%s#\n", processed_input_string);

 if ( input_calendar_date_or_jd == 1 ) {
  // Writing this into JD keyword
  // sprintf( newcard, "JD = %.5lf / JD (UTC)", jd_from_string );
  sprintf( newcard, "JD = %.8lf / JD (UTC)", jd_from_string );
  // reformat the keyword string to conform to FITS rules
  fits_parse_template( newcard, card, &keytype, &status );
  // overwrite the keyword with the new value
  fits_update_card( fptr, "JD", card, &status );
 } else {
  // The default assumption is to write DATE-OBS
  strcpy( newcard, "DATE-OBS" ); // keyword name
  // fprintf( stderr, "DEBUG24e #%s#\n", processed_input_string);
  strcat( newcard, "= " ); // '=' value delimiter
  // truncate the input string so it's not too long
  processed_input_string[FLEN_CARD - 13]= '\0';
  // fprintf( stderr, "DEBUG24f #%s#\n", processed_input_string);
  strcat( newcard, processed_input_string ); // new value
  // fprintf( stderr, "DEBUG24g #%s#\n", processed_input_string);
  strcat( newcard, " / " ); // comment delimiter
  if ( strlen( newcard ) < FLEN_CARD - 42 ) {
   // long comment
   strcat( newcard, "Exposure start time (UTC) derived by VaST" ); // append the comment
  } else {
   // short comment
   strcat( newcard, "UTC" ); // append the comment
  }
  // anyhow, truncate the newcard[] string
  newcard[FLEN_CARD - 1]= '\0';
  // fprintf( stderr, "DEBUG24h #%s#\n", processed_input_string);
  //  reformat the keyword string to conform to FITS rules
  fits_parse_template( newcard, card, &keytype, &status );
  // fprintf( stderr, "DEBUG24i #%s#\n", processed_input_string);
  //  overwrite the keyword with the new value
  fits_update_card( fptr, "DATE-OBS", card, &status );
  // fprintf( stderr, "DEBUG24j #%s#\n", processed_input_string);
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

 // fprintf( stderr, "DEBUG24k #%s#\n", processed_input_string);

 fits_close_file( fptr, &status ); // close file
 fits_report_error( stderr, status );

 // fprintf( stderr, "DEBUG24l #%s#\n", processed_input_string);

 // why??
 strncpy( input_string, fitsfilename, FILENAME_LENGTH );

 // fprintf( stderr, "DEBUG25\n");

 return 1; // yes, we created the fake image
}

int main( int argc, char **argv ) {

 double JD, dimX, dimY;
 int timesys= 0; // Normal value
 int convert_timesys_to_TT= 0;
 char *stderr_output;
 char *log_output;
 int param_nojdkeyword= 0;
 int param_verbose= 1;
 int argument_counter;

 double MJD, UnixTime, Julian_year;

 double double_fractional_seconds_only;

 time_t UnixTime_time_t__rounded;
 struct tm *structureTIME__rounded;

 time_t UnixTime_time_t__truncated;
 struct tm *structureTIME__truncated;

 char formed_str_DATEOBS[FLEN_CARD];

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
 if ( argc > 2 ) {
  // combine multiple arguments in one string
  for ( argument_counter= 2; argument_counter < argc; argument_counter++ ) {
   if ( strlen( input_fits_image ) + strlen( argv[argument_counter] ) > FILENAME_LENGTH - 1 ) {
    fprintf( stderr, "The argument list is too long!\n" );
    return 1;
   }
   strncat( input_fits_image, " ", 2 );
   strncat( input_fits_image, argv[argument_counter], 80 );
  }
 }
 input_fits_image[FILENAME_LENGTH - 1]= '\0'; // just in case

 fake_image_hack_return= fake_image_hack( input_fits_image );

 if ( fake_image_hack_return == 1 ) {
  param_verbose= 0;
 }

 stderr_output= malloc( 1024 * sizeof( char ) );
 if ( stderr_output == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for stderr_output(get_image_date.c)\n" );
  exit( EXIT_FAILURE );
 };
 log_output= malloc( 1024 * sizeof( char ) );
 if ( log_output == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for log_output(get_image_date.c)\n" );
  exit( EXIT_FAILURE );
 };

 // fprintf( stderr, "DEBUG26\n");

 // Get the date
 if ( 0 != gettime( input_fits_image, &JD, &timesys, convert_timesys_to_TT, &dimX, &dimY, stderr_output, log_output, param_nojdkeyword, param_verbose, NULL ) ) {
  fprintf( stderr, "ERROR getting observing time from the input %s\n", argv[1] );
  free( stderr_output );
  free( log_output );
  return 1;
 }

 // fprintf( stderr, "DEBUG27\n");

 if ( fake_image_hack_return == 1 ) {
  unlink( input_fits_image );
 }

 // Convert the date to other formats

 // We want to for DATEOBS string using this function rather than manually, so it can be tested
 form_DATEOBS_EXPTIME_log_output_from_JD( JD, 0.0, formed_str_DATEOBS, NULL, NULL, NULL, 1 );

 MJD= JD - 2400000.5;

 // https://en.wikipedia.org/wiki/Julian_year_(astronomy)
 Julian_year= 2000.0 + ( JD - 2451545.0 ) / 365.25;

 UnixTime= ( JD - 2440587.5 ) * 86400.0;

 double_fractional_seconds_only= UnixTime - (double)( (time_t)UnixTime );
 UnixTime_time_t__truncated= (time_t)( UnixTime );

 // Special 1969-12-31T23:59:59.0
 if ( 0 == UnixTime_time_t__truncated ) {
  if ( double_fractional_seconds_only < 0.0 ) {
   UnixTime_time_t__truncated= UnixTime_time_t__truncated - 1;
   double_fractional_seconds_only= 1.0 + double_fractional_seconds_only;
  }
 }

 // fprintf(stderr,"DEBUGISHE double_fractional_seconds_only=%lf UnixTime=%lf UnixTime_time_t__truncated=%ld\n",double_fractional_seconds_only,UnixTime,UnixTime_time_t__truncated);

 // round it up
 if ( UnixTime < 0.0 ) {
  UnixTime_time_t__rounded= (time_t)( UnixTime - 0.5 );
 } else {
  // UnixTime is double, so we add 0.5 for the proper type conversion
  UnixTime_time_t__rounded= (time_t)( UnixTime + 0.5 );
 }

 // Use thread-safe gmtime_r() instead of gmtime() if possible
 // will need to free( structureTIME__rounded ) and free( structureTIME__truncated ) below
#if defined( _POSIX_C_SOURCE ) || defined( _BSD_SOURCE ) || defined( _SVID_SOURCE )
 structureTIME__rounded= malloc( sizeof( struct tm ) );
 gmtime_r( &UnixTime_time_t__rounded, structureTIME__rounded );
 structureTIME__truncated= malloc( sizeof( struct tm ) );
 gmtime_r( &UnixTime_time_t__truncated, structureTIME__truncated );
#else
 structureTIME__rounded= gmtime( &UnixTime_time_t__rounded );
 structureTIME__truncated= gmtime( &UnixTime_time_t__truncated );
#endif

 // fprintf( stderr, "DEBUG28\n");

 // Print output
 fprintf( stdout, "%s\n", stderr_output );
 fprintf( stdout, "\n --== Observation date in various formats ==--\n" );
 // fprintf( stdout, "         JD %14.6lf\n", JD );
 fprintf( stdout, "         JD %16.8lf\n", JD );
 fprintf( stdout, "        _JD %13.5lf        (rounded to 1 sec)\n", JD );
 // fprintf( stdout, "        MJD %14.6lf\n", MJD );
 fprintf( stdout, "        MJD %16.8lf\n", MJD );
 fprintf( stdout, "       _MJD %13.5lf        (rounded to 1 sec)\n", MJD );
 fprintf( stdout, "  Unix Time %.0lf            (seconds)\n", UnixTime );
 // fprintf( stdout, "Julian year %14.9lf\n", Julian_year );
 fprintf( stdout, "Julian year %16.11lf\n", Julian_year );
 // Day fraction output with full accuracy
 fprintf( stdout, "Dayfraction %04d %02d %8.8lf\n", structureTIME__truncated->tm_year - 100 + 2000, structureTIME__truncated->tm_mon + 1, (double)structureTIME__truncated->tm_mday + (double)structureTIME__truncated->tm_hour / 24.0 + (double)structureTIME__truncated->tm_min / ( 24.0 * 60 ) + ( (double)structureTIME__truncated->tm_sec + double_fractional_seconds_only ) / ( 24.0 * 60 * 60 ) );
 // The problem is that the sub-second accuracy is lost in this output
 fprintf( stdout, " MPC format %04d %02d %8.5lf\n", structureTIME__truncated->tm_year - 100 + 2000, structureTIME__truncated->tm_mon + 1, (double)structureTIME__truncated->tm_mday + (double)structureTIME__truncated->tm_hour / 24.0 + (double)structureTIME__truncated->tm_min / ( 24.0 * 60 ) + ( (double)structureTIME__truncated->tm_sec + double_fractional_seconds_only ) / ( 24.0 * 60 * 60 ) );
 // fprintf( stdout, " MPC format %04d %02d %8.5lf\n", structureTIME__rounded->tm_year - 100 + 2000, structureTIME__rounded->tm_mon + 1, (double)structureTIME__rounded->tm_mday + (double)structureTIME__rounded->tm_hour / 24.0 + (double)structureTIME__rounded->tm_min / ( 24.0 * 60 ) + (double)structureTIME__rounded->tm_sec / ( 24.0 * 60 * 60 ) );
 //  fprintf( stdout, " MPC format %04d %02d %8.6lf\n", structureTIME__rounded->tm_year - 100 + 2000, structureTIME__rounded->tm_mon + 1, (double)structureTIME__rounded->tm_mday + (double)structureTIME__rounded->tm_hour / 24.0 + (double)structureTIME__rounded->tm_min / ( 24.0 * 60 ) + (double)structureTIME__rounded->tm_sec / ( 24.0 * 60 * 60 ) );
 //  The problem is that the sub-second accuracy is lost in this output
 fprintf( stdout, " ATel style %04d-%02d-%08.5lf\n", structureTIME__truncated->tm_year - 100 + 2000, structureTIME__truncated->tm_mon + 1, (double)structureTIME__truncated->tm_mday + (double)structureTIME__truncated->tm_hour / 24.0 + (double)structureTIME__truncated->tm_min / ( 24.0 * 60 ) + ( (double)structureTIME__truncated->tm_sec + double_fractional_seconds_only ) / ( 24.0 * 60 * 60 ) );
 // fprintf( stdout, " ATel style %04d-%02d-%08.5lf\n", structureTIME__rounded->tm_year - 100 + 2000, structureTIME__rounded->tm_mon + 1, (double)structureTIME__rounded->tm_mday + (double)structureTIME__rounded->tm_hour / 24.0 + (double)structureTIME__rounded->tm_min / ( 24.0 * 60 ) + (double)structureTIME__rounded->tm_sec / ( 24.0 * 60 * 60 ) );
 fprintf( stdout, " (mid. exp) %04d-%02d-%02d %02d:%02d:%06.3lf\n", structureTIME__truncated->tm_year - 100 + 2000, structureTIME__truncated->tm_mon + 1, structureTIME__truncated->tm_mday, structureTIME__truncated->tm_hour, structureTIME__truncated->tm_min, (double)( structureTIME__truncated->tm_sec ) + double_fractional_seconds_only );
 fprintf( stdout, " (mid. exp) %s\n", formed_str_DATEOBS );
 // The problem is that the sub-second accuracy is lost in this output
 fprintf( stdout, " (mid. exp) %04d-%02d-%02d %02d:%02d:%02d  (rounded to 1 sec)\n", structureTIME__rounded->tm_year - 100 + 2000, structureTIME__rounded->tm_mon + 1, structureTIME__rounded->tm_mday, structureTIME__rounded->tm_hour, structureTIME__rounded->tm_min, structureTIME__rounded->tm_sec );
 // The problem is that the sub-second accuracy is lost in this output
 fprintf( stdout, " DD.MM.YYYY %02d.%02d.%04d %02d:%02d:%02d  (rounded to 1 sec)\n", structureTIME__rounded->tm_mday, structureTIME__rounded->tm_mon + 1, structureTIME__rounded->tm_year - 100 + 2000, structureTIME__rounded->tm_hour, structureTIME__rounded->tm_min, structureTIME__rounded->tm_sec );
 // The problem is that the sub-second accuracy is lost in this output
 fprintf( stdout, " MM/DD/YYYY %02d/%02d/%04d %02d:%02d:%02d  (rounded to 1 sec)\n", structureTIME__rounded->tm_mon + 1, structureTIME__rounded->tm_mday, structureTIME__rounded->tm_year - 100 + 2000, structureTIME__rounded->tm_hour, structureTIME__rounded->tm_min, structureTIME__rounded->tm_sec );
 //

 // Clean up
 free( log_output );
 free( stderr_output );

#if defined( _POSIX_C_SOURCE ) || defined( _BSD_SOURCE ) || defined( _SVID_SOURCE )
 free( structureTIME__rounded );
 free( structureTIME__truncated );
#endif

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
