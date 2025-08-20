// #define _GNU_SOURCE // for memmem() in Kourovka_SBG_date_hack()

#define WARN_IF_TAImUTC_DAT_IS_OLDER_THAN_DAYS 10.0 * 365.242

#include <stdio.h>
#include <time.h>
#include <string.h>
#include <strings.h> // for strcasecmp()
#include <stdlib.h>
#include <math.h>

#include "fitsio.h"
#include "vast_limits.h"

#include "kourovka_sbg_date.h"

// helper function removing multiple white spaces from a string
void remove_multiple_spaces( char *str ) {
 int i, j;
 int space_flag= 0;

 if ( str == NULL )
  return;

 for ( i= 0, j= 0; str[i] != '\0'; i++ ) {
  if ( str[i] == ' ' ) {
   if ( space_flag == 0 ) {
    str[j++]= ' ';
    space_flag= 1;
   }
  } else {
   str[j++]= str[i];
   space_flag= 0;
  }
 }
 str[j]= '\0';

 return;
}

void generate_finder_chart_timestring( char *finder_chart_timestring_output,
                                       const struct tm *structureTIME,
                                       double double_fractional_seconds_only,
                                       const char *tymesys_str_in,
                                       double exposure ) {
 if ( finder_chart_timestring_output == NULL ) {
  return;
 }

 char coma_or_whitespace_character_after_timesys= ',';
 if ( strcmp( tymesys_str_in, " " ) == 0 ) {
  coma_or_whitespace_character_after_timesys= ' ';
 }

 if ( exposure > 0.0 ) {
  sprintf( finder_chart_timestring_output,
           "%4d-%02d-%02d %02d:%02d:%02.0lf %s%c %.0lf sec",
           structureTIME->tm_year - 100 + 2000,
           structureTIME->tm_mon + 1,
           structureTIME->tm_mday,
           structureTIME->tm_hour,
           structureTIME->tm_min,
           (double)structureTIME->tm_sec + double_fractional_seconds_only,
           tymesys_str_in,
           coma_or_whitespace_character_after_timesys,
           exposure );
 } else {
  sprintf( finder_chart_timestring_output,
           "%4d-%02d-%02d %02d:%02d:%02.0lf %s",
           structureTIME->tm_year - 100 + 2000,
           structureTIME->tm_mon + 1,
           structureTIME->tm_mday,
           structureTIME->tm_hour,
           structureTIME->tm_min,
           (double)structureTIME->tm_sec + double_fractional_seconds_only,
           tymesys_str_in );
 }
}

void write_DATEOBS_and_EXPTIME_to_FITS_header( char *fitsfilename, char *formed_str_DATEOBS, char *formed_str_EXPTIME ) {
 fitsfile *fptr; /* FITS file pointer, defined in fitsio.h */
 char card[FLEN_CARD], newcard[FLEN_CARD];
 char oldvalue[FLEN_VALUE], comment[FLEN_COMMENT];
 int status= 0; /*  CFITSIO status value MUST be initialized to zero!  */
 int iomode, keytype;

 iomode= READWRITE;

 if ( !fits_open_file( &fptr, fitsfilename, iomode, &status ) ) {
  //////////////////// DATE-OBS ////////////////////
  if ( fits_read_card( fptr, "DATE-OBS", card, &status ) ) {
   fprintf( stderr, "Keyword %s does not exist in the header\n", "DATE-OBS" );
   card[0]= '\0';
   comment[0]= '\0';
   status= 0; /* reset status after error */
  } else {
   // Save the old value
   fprintf( stderr, "%s\n", card );
   fprintf( stderr, "Saving this to OLD-OBS as a backup\n" );
   if ( *card )
    fits_parse_value( card, oldvalue, comment, &status );
   // construct template for new keyword
   strcpy( newcard, "OLD-OBS" ); // keyword name
   strcat( newcard, " = " );     // '=' value delimiter
   strcat( newcard, oldvalue );  // new value
   if ( *comment ) {
    strcat( newcard, " / " );   // comment delimiter
    strcat( newcard, comment ); // append the comment
   }
   // reformat the keyword string to conform to FITS rules
   fits_parse_template( newcard, card, &keytype, &status );
   // overwrite the keyword with the new value
   fits_update_card( fptr, "OLD-OBS", card, &status );
  }
  // Write the new value of DATE-OBS
  // construct template for new keyword
  strcpy( newcard, "DATE-OBS" );                                  // keyword name
  strcat( newcard, " = " );                                       // '=' value delimiter
  strcat( newcard, formed_str_DATEOBS );                          // new value
  strcat( newcard, " / " );                                       // comment delimiter
  strcat( newcard, "Exposure start time (UTC) derived by VaST" ); // append the comment
  // reformat the keyword string to conform to FITS rules
  fits_parse_template( newcard, card, &keytype, &status );
  // overwrite the keyword with the new value
  fits_update_card( fptr, "DATE-OBS", card, &status );

  //////////////////// EXPTIME ////////////////////
  if ( fits_read_card( fptr, "EXPTIME", card, &status ) ) {
   fprintf( stderr, "Keyword %s does not exist in the header\n", "EXPTIME" );
   card[0]= '\0';
   comment[0]= '\0';
   status= 0; /* reset status after error */
  } else {
   // Save the old value
   fprintf( stderr, "%s\n", card );
   fprintf( stderr, "Saving this to OLDTIME as a backup\n" );
   if ( *card )
    fits_parse_value( card, oldvalue, comment, &status );
   // construct template for new keyword
   strcpy( newcard, "OLDTIME" ); // keyword name
   strcat( newcard, " = " );     // '=' value delimiter
   strcat( newcard, oldvalue );  // new value
   if ( *comment ) {
    strcat( newcard, " / " );   // comment delimiter
    strcat( newcard, comment ); // append the comment
   }
   // reformat the keyword string to conform to FITS rules
   fits_parse_template( newcard, card, &keytype, &status );
   // overwrite the keyword with the new value
   fits_update_card( fptr, "OLDTIME", card, &status );
  }
  // Write the new value of EXPTIME
  // construct template for new keyword
  strcpy( newcard, "EXPTIME" );                             // keyword name
  strcat( newcard, " = " );                                 // '=' value delimiter
  strcat( newcard, formed_str_EXPTIME );                    // new value
  strcat( newcard, " / " );                                 // comment delimiter
  strcat( newcard, "Exposure time (sec) derived by VaST" ); // append the comment
  // reformat the keyword string to conform to FITS rules
  fits_parse_template( newcard, card, &keytype, &status );
  // overwrite the keyword with the new value
  fits_update_card( fptr, "EXPTIME", card, &status );

  fits_close_file( fptr, &status );
 } // open_file

 // if error occured, print out error message
 if ( status ) {
  fits_report_error( stderr, status );
 }

 return;
}

void form_DATEOBS_EXPTIME_log_output_from_JD( double JD, double exposure_sec, char *formed_str_DATEOBS, char *formed_str_EXPTIME, char *log_output, char *finder_chart_timestring_output, int stderr_silent ) {
 double double_fractional_seconds_only;

 double exposure_start_time_JD;

 time_t exposure_start_time_unixsec;
 struct tm *struct_tm_pointer;

 int year, month, day, hour, minute;
 double second;

 char output_str_DATEOBS[FLEN_CARD];
 char output_str_EXPTIME[FLEN_CARD];

 exposure_start_time_JD= JD - exposure_sec / ( 2.0 * 86400.0 );

 exposure_start_time_unixsec= (time_t)( ( exposure_start_time_JD - 2440587.5 ) * 86400.0 );
 double_fractional_seconds_only= ( exposure_start_time_JD - 2440587.5 ) * 86400.0 - (double)exposure_start_time_unixsec;

 // Special 1969-12-31T23:59:59.0
 if ( 0 == exposure_start_time_unixsec ) {
  if ( double_fractional_seconds_only < 0.0 ) {
   exposure_start_time_unixsec= exposure_start_time_unixsec - 1;
   double_fractional_seconds_only= 1.0 + double_fractional_seconds_only;
  }
 }

 // fprintf(stderr,"DEBUUUGGGG:  double_fractional_seconds_only= %.3lf\n", double_fractional_seconds_only);

 // exposure_start_time_unixsec= middle_of_exposure_unixsec - (time_t)( exposure_sec / 2.0 + 0.5 );

#if defined( _POSIX_C_SOURCE ) || defined( _BSD_SOURCE ) || defined( _SVID_SOURCE )
 struct_tm_pointer= malloc( sizeof( struct tm ) );
 gmtime_r( &exposure_start_time_unixsec, struct_tm_pointer );
#else
 struct_tm_pointer= gmtime( &exposure_start_time_unixsec );
#endif

 // Produce finder_chart_timestring_output
 if ( NULL != finder_chart_timestring_output ) {
  generate_finder_chart_timestring( finder_chart_timestring_output,
                                    struct_tm_pointer,
                                    double_fractional_seconds_only,
                                    " ",
                                    exposure_sec );
 }
 //

 year= struct_tm_pointer->tm_year + 1900;
 month= struct_tm_pointer->tm_mon + 1;
 day= struct_tm_pointer->tm_mday;
 hour= struct_tm_pointer->tm_hour;
 minute= struct_tm_pointer->tm_min;
 second= (double)( struct_tm_pointer->tm_sec ) + double_fractional_seconds_only;

#if defined( _POSIX_C_SOURCE ) || defined( _BSD_SOURCE ) || defined( _SVID_SOURCE )
 free( struct_tm_pointer );
#endif

 // Note that we are now printing out fractions of the second
 sprintf( output_str_DATEOBS, "%04d-%02d-%02dT%02d:%02d:%06.3lf", year, month, day, hour, minute, second );
 sprintf( output_str_EXPTIME, "%.3lf", exposure_sec );

 if ( 1 != stderr_silent ) {
  // Print out stderr message only if this is a normal call
  fprintf( stderr, "\nObserving time converted to the \"standard\" FITS header format:\nDATE-OBS= %s\nEXPTIME = %s\n\n", output_str_DATEOBS, output_str_EXPTIME );
 }

 if ( NULL != formed_str_DATEOBS ) {
  strncpy( formed_str_DATEOBS, output_str_DATEOBS, FLEN_CARD - 1 );
 }
 if ( NULL != formed_str_EXPTIME ) {
  strncpy( formed_str_EXPTIME, output_str_EXPTIME, FLEN_CARD - 1 );
 }
 if ( NULL != log_output ) {
  // sprintf( log_output, "exp_start= %02d.%02d.%4d %02d:%02d:%02.0lf  exp= %4.0lf  ", day, month, year, hour, minute, second, exposure_sec );
  sprintf( log_output, "exp_start= %02d.%02d.%4d %02d:%02d:%06.3lf  exp= %8.3lf  ", day, month, year, hour, minute, second, exposure_sec );
 }
 ///////////////

 return;
}

double get_TTminusUTC_in_days( double jdUT, int *output_timesys ) {
 FILE *tai_utc_dat;
 double TTminusUTC_days;
 double *jd_leap_second;
 jd_leap_second= malloc( MAX_NUMBER_OF_LEAP_SECONDS * sizeof( double ) );
 if ( jd_leap_second == NULL ) {
  fprintf( stderr, "ERROR: in convert_jdUT_to_jdTT() can't allocate memory for jd_leap_second\n" );
  exit( EXIT_FAILURE );
 }
 double *TAI_minus_UTC;
 TAI_minus_UTC= malloc( MAX_NUMBER_OF_LEAP_SECONDS * sizeof( double ) );
 if ( TAI_minus_UTC == NULL ) {
  fprintf( stderr, "ERROR: in convert_jdUT_to_jdTT() can't allocate memory for TAI_minus_UTC\n" );
  exit( EXIT_FAILURE );
 }
 double tai_utc;
 char str1[256], str2[256];
 int i;
 int n_leap_sec= 0;

 double MJD= jdUT - 2400000.5; // for leap second calculation before 1972 JAN  1
 double *MJD0;
 MJD0= malloc( MAX_NUMBER_OF_LEAP_SECONDS * sizeof( double ) );
 if ( MJD0 == NULL ) {
  fprintf( stderr, "ERROR: in convert_jdUT_to_jdTT() can't allocate memory for MJD0\n" );
  exit( EXIT_FAILURE );
 }
 double *leap_second_rate;
 leap_second_rate= malloc( MAX_NUMBER_OF_LEAP_SECONDS * sizeof( double ) );
 if ( leap_second_rate == NULL ) {
  fprintf( stderr, "ERROR: in convert_jdUT_to_jdTT() can't allocate memory for leap_second_rate\n" );
  exit( EXIT_FAILURE );
 }

 /*

   Read the file with leap seconds lib/tai-utc.dat
   up-to-date version of this file is available at
   https://maia.usno.navy.mil/ser7/tai-utc.dat

   "Clearly, the JD where the discontinuity in UTC occurs is in UTC.
   (If it were in TAI instead, the JD epoch would not correspond to midnight exactly.)"
   according to https://accserv.lepp.cornell.edu/svn/packages/plplot/lib/qsastime/README.tai-utc

 */

 tai_utc_dat= fopen( "lib/tai-utc.dat", "r" );
 if ( NULL == tai_utc_dat ) {
  fprintf( stderr, "ERROR: can't open file lib/tai-utc.dat\n" );
  exit( EXIT_FAILURE );
 }
 while ( NULL != fgets( str1, 256, tai_utc_dat ) ) {
  for ( i= 17; i < 26; i++ )
   str2[i - 17]= str1[i];
  str2[i - 17]= '\0';
  jd_leap_second[n_leap_sec]= atof( str2 );
  for ( i= 37; i < 48; i++ )
   str2[i - 37]= str1[i];
  str2[i - 37]= '\0';
  TAI_minus_UTC[n_leap_sec]= atof( str2 );
  for ( i= 60; i < 66; i++ )
   str2[i - 60]= str1[i];
  str2[i - 60]= '\0';
  MJD0[n_leap_sec]= atof( str2 );
  for ( i= 70; i < 79; i++ )
   str2[i - 70]= str1[i];
  str2[i - 70]= '\0';
  leap_second_rate[n_leap_sec]= atof( str2 );
  n_leap_sec++;
 }
 fclose( tai_utc_dat );

 if ( jdUT < jd_leap_second[0] )
  fprintf( stderr, "WARNING: TT is not defined before %.5lf\n", jd_leap_second[0] );

 tai_utc= TAI_minus_UTC[0];
 for ( i= 1; i < n_leap_sec; i++ ) {
  if ( jdUT >= jd_leap_second[i] ) {
   tai_utc= TAI_minus_UTC[i] + ( MJD - MJD0[i] ) * leap_second_rate[i]; // tai_utc=TAI_minus_UTC[i];
  }
 }

 // Check that the input lib/tai-utc.dat file is not too old
 if ( jdUT - jd_leap_second[n_leap_sec - 1] > WARN_IF_TAImUTC_DAT_IS_OLDER_THAN_DAYS ) {
  fprintf( stderr, "\nWARNING: the last record in lib/tai-utc.dat is more than %.0lf days old (JD%.1lf)!\n Please make sure the tai-utc.dat file is up to date by checking its latest version at http://maia.usno.navy.mil/ser7/tai-utc.dat\n\n", WARN_IF_TAImUTC_DAT_IS_OLDER_THAN_DAYS, jd_leap_second[n_leap_sec - 1] );
 }

 // Apply the leap seconds correction
 // TT = TAI + 32.184
 // TAI = UTC + leap_seconds
 TTminusUTC_days= ( 32.184 + tai_utc ) / 86400;

 /// Set marker that time system was changed
 ( *output_timesys )= 2; // TT

 free( jd_leap_second );
 free( TAI_minus_UTC );
 free( MJD0 );
 free( leap_second_rate );

 return TTminusUTC_days;
}

double convert_jdUT_to_jdTT( double jdUT, int *output_timesys ) {
 return jdUT + get_TTminusUTC_in_days( jdUT, output_timesys );
}

double convert_jdTT_to_jdUT( double jdTT, int *output_timesys ) {
 double jdUT;
 double TTminusUTC_days;
 int placeholder_int_timesys;

 TTminusUTC_days= 69.184 / 86400; // initial guess

 jdUT= jdTT - TTminusUTC_days; // get approximate jdUT using guessed TTminusUTC_days

 TTminusUTC_days= get_TTminusUTC_in_days( jdUT, &placeholder_int_timesys );
 jdUT= jdTT - TTminusUTC_days; // get a better value of TTminusUTC_days
 // the above will not work well around the time leap second occurs
 // try to improve things with another iteration
 TTminusUTC_days= get_TTminusUTC_in_days( jdUT, &placeholder_int_timesys );
 jdUT= jdTT - TTminusUTC_days; // get a better value of TTminusUTC_days

 ( *output_timesys )= 1; // force-set time system to UT
 return jdUT;
}

/*
We can't accept all these date writing options. but we'll try to handle some
1999-09-01 58
1999-09-1  58
1999-9-01  57
1999-9-1   57

99-09-01   36
99-09-1    36
99-9-01    35
99-9-1     35


1-9-1999   24
1-09-1999  25
01-9-1999  35
01-09-1999 36

1-9-99     24
1-09-99    25
01-9-99    35
01-09-99   36
*/

// This function will handle '25/12/2011' style DATE-OBS
void fix_DATEOBS_STRING( char *DATEOBS ) {
 unsigned int i, j, date_part; // counters
 char substring_day[32];
 char substring_month[32];
 char substring_year[32];
 int day, month, year;

 // do nothing if this is a NULL string
 if ( NULL == DATEOBS ) {
  fprintf( stderr, "ERROR in fix_DATEOBS_STRING(): NULL input string!\n" );
  return;
 }

 // check if this is an empty string (and assume that the date will be provided as 'JD' keyword)
 if ( 0 == strlen( DATEOBS ) ) {
  return;
 }

 // check if this is a normal '2004-07-05' style DATE-OBS
 for ( i= 0; i < strlen( DATEOBS ); i++ ) {
  // if yes - do nothing
  if ( DATEOBS[i] == '-' ) {
   return;
  }
 }

 // reset strings, just in case
 memset( substring_day, 0, 32 );
 memset( substring_month, 0, 32 );
 memset( substring_year, 0, 32 );

 // Parse '25/12/2011' style DATE-OBS
 for ( i= 0, j= 0, date_part= 1; i < strlen( DATEOBS ); i++ ) {
  if ( DATEOBS[i] == '/' ) {
   if ( date_part == 1 )
    substring_day[j]= '\0';
   if ( date_part == 2 )
    substring_month[j]= '\0';
   if ( date_part == 3 )
    substring_year[j]= '\0';
   date_part++;
   j= 0;
   continue;
  }
  if ( date_part == 1 ) {
   substring_day[j]= DATEOBS[i];
   j++;
  }
  if ( date_part == 2 ) {
   substring_month[j]= DATEOBS[i];
   j++;
  }
  if ( date_part == 3 ) {
   substring_year[j]= DATEOBS[i];
   j++;
  }
 }
 substring_year[4]= '\0';

 if ( date_part == 1 ) {
  fprintf( stderr, "ERROR: cannot parse DATE-OBS keyword!\n" );
  exit( EXIT_FAILURE );
 }

 // Print result
 // fprintf(stderr,"_%s_ _%s_ _%s_   _%s_\n",substring_day,substring_month,substring_year,DATEOBS);
 day= atoi( substring_day );
 month= atoi( substring_month );
 year= atoi( substring_year );
 // try fix a two-digit year
 if ( year < 100 ) {
  fprintf( stderr, "fix_DATEOBS_STRING() WARNING -- two-digit year in the input DATEOBS string: %d -> ", year );
  if ( year < 50 ) {
   year= year + 2000;
  } else {
   year= year + 1900;
  }
  fprintf( stderr, "%d\n", year );
 }
 //
 // sprintf(DATEOBS,"%d-%02d-%02d",year,month,day);

 fprintf( stderr, "WARNING -- fixing the input DATEOBS string: %s -> ", DATEOBS );

 sprintf( DATEOBS, "%d-%02d-%02d", year, month, day );

 fprintf( stderr, "%s\n", DATEOBS );

 return;
}

// This function will handle '09-10-2017' and '09.10.2017' style DATE-OBS
void fix_DATEOBS_STRING__DD_MM_YYYY_format( char *DATEOBS ) {
 // should the counters be 'size_t'?
 unsigned int i, j, date_part; // counters
 char substring_day[32];
 char substring_month[32];
 char substring_year[32];
 int day, month, year;

 int ndash, ndot;
 char dash_or_dot_character;

 // the following is to handle 04.02.2012 02:48:30
 //                            01234567890123456789
 int ncolon;
 char timestring[32];

 // check if the input is a NULL pointer (not sure why, but what if)
 if ( NULL == DATEOBS ) {
  return;
 }

 // check if this is an empty string (and assume that the date will be provided as 'JD' keyword)
 if ( 0 == strlen( DATEOBS ) ) {
  return;
 }
 // if( strlen(DATEOBS) < 8 ) {
 //  we want to aslo handle a two-digit year 21-09-99
 if ( strlen( DATEOBS ) < 6 ) {
  // the string is too short for the following trick to work
  return;
 }

 // count how many times dash and dots are found in the string
 // we don't want to start with zero
 ndash= ndot= ncolon= 0;
 for ( i= 1; i < strlen( DATEOBS ); i++ ) {
  if ( DATEOBS[i] == '-' ) {
   ndash++;
   continue;
  }
  if ( DATEOBS[i] == '.' ) {
   ndot++;
   continue;
  }
  if ( DATEOBS[i] == ':' ) {
   ncolon++;
   continue;
  }
 }
 //
 if ( ndash >= 2 ) {
  dash_or_dot_character= '-';
 } else {
  if ( ndot >= 2 ) {
   dash_or_dot_character= '.';
  } else {
   // nothing to fix here
   return;
  }
 }

 //                            0123456789
 // check if this is a normal '2004-07-05' style DATE-OBS
 if ( DATEOBS[4] == dash_or_dot_character ) {
  // special cases 1-09-99 and 01-9-1999
  if ( DATEOBS[1] != dash_or_dot_character && DATEOBS[2] != dash_or_dot_character ) {
   return;
  }
 }

 // reset strings, just in case
 memset( substring_day, 0, 32 );
 memset( substring_month, 0, 32 );
 memset( substring_year, 0, 32 );

 memset( timestring, 0, 32 );

 // the following is to handle 04.02.2012 02:48:30
 //                            01234567890123456789
 if ( strlen( DATEOBS ) > 10 && ncolon >= 1 ) {
 }

 // Parse '09-10-2017' or '09.10.2017' style DATE-OBS
 j= 0;
 date_part= 1;
 for ( i= 0; i < strlen( DATEOBS ); i++ ) {
  if ( DATEOBS[i] == dash_or_dot_character ) {
   if ( date_part == 1 )
    substring_day[j]= '\0';
   if ( date_part == 2 )
    substring_month[j]= '\0';
   if ( date_part == 3 )
    substring_year[j]= '\0';
   date_part++;
   j= 0;
   continue;
  }
  // check if this is start of the time part of 04.02.2012 02:48:30
  //                                            01234567890123456789
  // if ( i > 6 && DATEOBS[i] == ' ' && date_part == 3 ) {
  // the white space is actually replaced earlier by '-'
  if ( i > 6 && date_part == 3 ) {
   if ( DATEOBS[i] == '-' || DATEOBS[i] == ' ' || DATEOBS[i] == 'T' ) {
    substring_year[j]= '\0';
    date_part++;
    j= 0;
    continue;
   }
  }
  //
  if ( date_part == 1 ) {
   substring_day[j]= DATEOBS[i];
   j++;
  }
  if ( date_part == 2 ) {
   substring_month[j]= DATEOBS[i];
   j++;
  }
  if ( date_part == 3 ) {
   substring_year[j]= DATEOBS[i];
   j++;
  }
  if ( date_part == 4 ) {
   timestring[j]= DATEOBS[i];
   j++;
  }
 }
 substring_year[4]= '\0';
 substring_month[2]= '\0';
 substring_day[2]= '\0';

 if ( date_part == 1 ) {
  fprintf( stderr, "ERROR: cannot parse DATE-OBS keyword!\n" );
  exit( EXIT_FAILURE );
 }

 // Print result
 // consistency check
 if ( 0 == strlen( substring_day ) ) {
  fprintf( stderr, "ERROR: cannot parse DATE-OBS keyword! Empty string substring_day\n" );
  exit( EXIT_FAILURE );
 }
 if ( 0 == strlen( substring_month ) ) {
  fprintf( stderr, "ERROR: cannot parse DATE-OBS keyword! Empty string substring_month\n" );
  exit( EXIT_FAILURE );
 }
 if ( 0 == strlen( substring_year ) ) {
  fprintf( stderr, "ERROR: cannot parse DATE-OBS keyword! Empty string substring_year\n" );
  exit( EXIT_FAILURE );
 }
 //
 day= atoi( substring_day );
 month= atoi( substring_month );
 year= atoi( substring_year );
 //
 if ( day < 1 || day > 31 ) {
  fprintf( stderr, "ERROR: cannot parse DATE-OBS keyword! Wrong day\n" );
  exit( EXIT_FAILURE );
 }
 if ( month < 1 || month > 12 ) {
  fprintf( stderr, "ERROR: cannot parse DATE-OBS keyword! Wrong month\n" );
  exit( EXIT_FAILURE );
 }
 if ( year < 0 || year > 3000 ) {
  fprintf( stderr, "ERROR: cannot parse DATE-OBS keyword! Wrong year\n" );
  exit( EXIT_FAILURE );
 }
 // try fix a two-digit year
 if ( year < 100 ) {
  fprintf( stderr, "fix_DATEOBS_STRING__DD_MM_YYYY_format() WARNING -- two-digit year in the input DATEOBS string: %d -> ", year );
  if ( year < 50 ) {
   year= year + 2000;
  } else {
   year= year + 1900;
  }
 }
 //

 fprintf( stderr, "WARNING -- fixing the input DATEOBS string: %s -> ", DATEOBS );

 sprintf( DATEOBS, "%d-%02d-%02d", year, month, day );

 if ( strlen( timestring ) > 0 ) {
  strncat( DATEOBS, "T", 2 );
  strncat( DATEOBS, timestring, 32 - 12 );
 }

 fprintf( stderr, "%s\n", DATEOBS );

 return;
}

// Determine if this is the image resampled to the defaut orientation (North up, East left)
// 1 - yes
// 0 - no
int check_if_this_fits_image_is_north_up_east_left( char *fitsfilename ) {
 fitsfile *fptr; /* pointer to the FITS file; defined in fitsio.h */
 int status= 0;  // for cfitsio routines
 double CD1_1, CD1_2, CD2_1, CD2_2;

 fits_open_image( &fptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status ); /* print out any error messages */
  fits_clear_errmsg();                 // clear the CFITSIO error message stack
  return 0;                            // assume - no
 }

 fits_read_key( fptr, TDOUBLE, "CD1_1", &CD1_1, NULL, &status );
 if ( status == 202 ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();              // clear the CFITSIO error message stack
  fits_close_file( fptr, &status ); // close file
  status= 0;                        // just in case
  return 0;                         // assume - no
 }
 fits_read_key( fptr, TDOUBLE, "CD1_2", &CD1_2, NULL, &status );
 if ( status == 202 ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();              // clear the CFITSIO error message stack
  fits_close_file( fptr, &status ); // close file
  status= 0;                        // just in case
  return 0;                         // assume - no
 }
 fits_read_key( fptr, TDOUBLE, "CD2_1", &CD2_1, NULL, &status );
 if ( status == 202 ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();              // clear the CFITSIO error message stack
  fits_close_file( fptr, &status ); // close file
  status= 0;                        // just in case
  return 0;                         // assume - no
 }
 fits_read_key( fptr, TDOUBLE, "CD2_2", &CD2_2, NULL, &status );
 if ( status == 202 ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();              // clear the CFITSIO error message stack
  fits_close_file( fptr, &status ); // close file
  status= 0;                        // just in case
  return 0;                         // assume - no
 }

 // close the FITS file
 fits_report_error( stderr, status );
 fits_clear_errmsg();              // clear the CFITSIO error message stack
 fits_close_file( fptr, &status ); // close file
 status= 0;                        // just in case

 // main test
 // WCS axes are paralloell to the image axes
 // if( CD1_2 == 0.0 && CD2_1 == 0.0 ) {
 // OK, let's allow for slight rotation
 // if ( fabs( CD1_2 ) / fabs( CD1_1 ) < 0.1 && fabs( CD2_1 ) / fabs( CD2_2 ) < 0.1 ) {
 if ( fabs( CD1_2 ) / fabs( CD1_1 ) < 0.12 && fabs( CD2_1 ) / fabs( CD2_2 ) < 0.12 ) {
  // east left, north up
  if ( CD1_1 < 0.0 && CD2_2 > 0.0 ) {
   return 1; // yes!!!!
  }
 } // if( CD1_2==0.0 && CD2_1==0.0 ){

 // by default
 return 0; // assume - no
}

void sanitize_positive_float_string( char *str ) {
 int len= strlen( str );
 int write_index= 0;
 int decimal_point_found= 0; // Using int instead of bool
 int read_index= 0;

 for ( read_index= 0; read_index < len; read_index++ ) {
  if ( str[read_index] >= '0' && str[read_index] <= '9' ) {
   // Keep digits
   str[write_index++]= str[read_index];
  } else if ( str[read_index] == '.' && !decimal_point_found ) {
   // Keep the first decimal point encountered
   str[write_index++]= str[read_index];
   decimal_point_found= 1; // Set flag to 1 instead of true
  }
  // Ignore all other characters
 }

 // Null-terminate the sanitized string
 str[write_index]= '\0';
}

void parse_seconds_and_fraction( const char *Tm_s, char *Tm_s_full_seconds_only, char *Tm_s_fractional_seconds_only ) {
 char *decimal_point= strchr( Tm_s, '.' );

 if ( decimal_point == NULL ) {
  // No decimal point found, treat as integer
  strcpy( Tm_s_full_seconds_only, Tm_s );
  strcpy( Tm_s_fractional_seconds_only, "0.0" );
 } else {
  // Copy full seconds
  size_t full_seconds_length= decimal_point - Tm_s;
  strncpy( Tm_s_full_seconds_only, Tm_s, full_seconds_length );
  Tm_s_full_seconds_only[full_seconds_length]= '\0';

  // Copy fractional seconds
  strcpy( Tm_s_fractional_seconds_only, "0" );
  strcat( Tm_s_fractional_seconds_only, decimal_point );

  // If there's nothing after the decimal point, add a "0"
  if ( strlen( Tm_s_fractional_seconds_only ) == 2 ) {
   strcat( Tm_s_fractional_seconds_only, "0" );
  }
 }
}

int gettime( char *fitsfilename, double *JD, int *timesys, int convert_timesys_to_TT, double *dimX, double *dimY, char *stderr_output, char *log_output, int param_nojdkeyword, int param_verbose, char *finder_chart_timestring_output ) {

 unsigned int counter_i;

 // Variables for time
 int status= 0; // for cfitsio routines
 int j;
 int j_end_of_year;
 int j_end_of_month;
 int jj;
 time_t unix_time;
 struct tm structureTIME;
 char Tm_s_full_seconds_only[FLEN_CARD];       // For sub-second timing - this string will store full number of seconds
 char Tm_s_fractional_seconds_only[FLEN_CARD]; // For sub-second timing - this string will store fractions of a second
 double double_fractional_seconds_only= 0.0;   // Tm_s_fractional_seconds_only converted to double
 char Tm_h[10], Tm_m[10], Tm_s[FLEN_CARD];     // We want a lot of memeory for Tm_s for cases like '2020-11-21T18:10:43.4516245'
 char Da_y[10], Da_m[10], Da_d[FLEN_CARD];     // We want more memeory for Da_d for cases like '2020-11-21.1234567

 char DATEOBS[FLEN_CARD], TIMEOBS[FLEN_CARD], TIMESYS[FLEN_CARD];
 char DATEOBS_COMMENT[2048];  // make it long, just in case
 char EXPOSURE_COMMENT[2048]; // make it long, just in case
 char tymesys_str_in[32];
 char tymesys_str_out[32];
 // char coma_or_whitespace_character_after_timesys;
 double inJD= 0.0;
 double endJD= 0.0;    // for paring the Siril-style EXPSTART/EXPEND keywords
 double tjd_zero= 0.0; // for parsing TESS TICA FFIs
 double midtjd= 0.0;   // for parsing TESS TICA FFIs

 // fitsio
 fitsfile *fptr;       /* pointer to the FITS file; defined in fitsio.h */
 double exposure= 0.0; // if exposure != 0.0 -- assuming we have correctly read it
 // End of time variables
 long naxes[2];

 // LOG-files
 // FILE *vast_image_details;

 int date_parsed= 0;         // 0 - date is not parsed, 1 - date is parsed successfully
 int expstart_mjd_parsed= 0; // 0 - date is not parsed, 1 - date is parsed successfully

 // EROS images have DATE-OBS set to the middle of exposure, not the exposure start!
 int is_this_an_EROS_image= 0; // 0 - no, 1 - yes

 // The following variables are used to handle vast_list_of_input_images_with_time_corrections.txt
 FILE *vast_list_of_input_images_with_time_corrections;
 char image_filename_from_input_list[FILENAME_LENGTH];
 double image_date_correction_from_input_list;
 double apply_JD_correction_in_days= 0.0;
 double overridingJD_from_input_image_list= 0.0;
 // ------------------------------------------

 // Stuff to suppoert TESS images
 int get_header_info_from_first_image_hdu_instead_of_just_first_hdu= 0;
 double TESS_style_deadtime_correction= 1.0;
 // ------------------------------------------

 char telescop[FLEN_CARD];

 char DATEOBS_KEY_NAME[32];
 char TIMEOBS_KEY_NAME[32];

 char formed_str_DATEOBS[FLEN_CARD];
 char formed_str_EXPTIME[FLEN_CARD];
 memset( formed_str_DATEOBS, 0, FLEN_CARD );
 memset( formed_str_EXPTIME, 0, FLEN_CARD );
 //

 memset( telescop, 0, FLEN_CARD );

 memset( DATEOBS_KEY_NAME, 0, 32 );
 memset( TIMEOBS_KEY_NAME, 0, 32 );

 memset( DATEOBS, 0, FLEN_CARD );
 memset( TIMEOBS, 0, FLEN_CARD );
 memset( TIMESYS, 0, FLEN_CARD );
 memset( DATEOBS_COMMENT, 0, 2048 );
 memset( EXPOSURE_COMMENT, 0, 2048 );

 if ( param_verbose >= 1 ) {
  fprintf( stderr, "Processing  %s\n", fitsfilename );
 }

 // See if the input image is listed in the time corrections file vast_list_of_input_images_with_time_corrections.txt
 vast_list_of_input_images_with_time_corrections= fopen( "vast_list_of_input_images_with_time_corrections.txt", "r" );
 // Check if we can open the file
 if ( NULL != vast_list_of_input_images_with_time_corrections ) {
  // Possibe buffer overflow here beacuse of fscanf(..., "%s", ...), but I feel lucky
  while ( 2 == fscanf( vast_list_of_input_images_with_time_corrections, "%s %lf", image_filename_from_input_list, &image_date_correction_from_input_list ) ) {
   // Check if the listed one is the same image we process now
   if ( 0 == strncmp( image_filename_from_input_list, fitsfilename, FILENAME_LENGTH ) ) {
    if ( fabs( image_date_correction_from_input_list ) < EXPECTED_MIN_JD ) {
     // Assume this is the time correction in seconds we need to apply to this image
     apply_JD_correction_in_days= image_date_correction_from_input_list / 86400.0;
     if ( param_verbose >= 1 )
      fprintf( stderr, "JD correction of %.8lf days (%.3lf seconds) will be applied!\n", apply_JD_correction_in_days, image_date_correction_from_input_list );
    } else {
     // Assume this is the full JD in days
     if ( fabs( image_date_correction_from_input_list ) < EXPECTED_MAX_JD ) {
      overridingJD_from_input_image_list= image_date_correction_from_input_list;
      if ( param_verbose >= 1 )
       fprintf( stderr, "WARNING: overriding the time deterrmined from FITS header with JD%.8lf as specified in vast_list_of_input_images_with_time_corrections.txt !\n", overridingJD_from_input_image_list );
     }
    }
    break; // don't process the remaining images, we have the right one
   } // if same image
  } // while()
  fclose( vast_list_of_input_images_with_time_corrections );
 }

 //

 /* Extract data from fits header */
 // fits_open_file(&fptr, fitsfilename, READONLY, &status);
 fits_open_image( &fptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status ); /* print out any error messages */
  fits_clear_errmsg();                 // clear the CFITSIO error message stack
  return status;
 }

 // Get image dimentions
 fits_read_key( fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();              // clear the CFITSIO error message stack
  fits_close_file( fptr, &status ); // close file
  fprintf( stderr, "ERROR: gettime() - can't get image dimensions from NAXIS1 keyword!\n" );
  return status;
 }
 fits_read_key( fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();              // clear the CFITSIO error message stack
  fits_close_file( fptr, &status ); // close file
  fprintf( stderr, "ERROR: gettime() - can't get image dimensions from NAXIS2 keyword!\n" );
  return status;
 }

 if ( param_verbose >= 1 ) {
  fprintf( stderr, "%ldx%ld FITS image %s\n", naxes[0], naxes[1], fitsfilename );
 }

 // Get the telescope name - we may recognize some and modify the behaviour
 fits_read_key( fptr, TSTRING, "TELESCOP", telescop, NULL, &status );
 if ( status != 0 ) {
  telescop[0]= '\0';
 }
 status= 0;

 //
 if ( 4 <= strlen( telescop ) ) {
  if ( 0 == strncmp( telescop, "TESS", 4 ) ) {
   // for TESS some important information is in the second HDU
   get_header_info_from_first_image_hdu_instead_of_just_first_hdu= 1;
  }
 }

 if ( get_header_info_from_first_image_hdu_instead_of_just_first_hdu != 1 ) {
  // Close the FITS file and re-open it with fits_open_file() instead of fits_open_image()
  // as the observing date information may be in a different HDU than the image!
  fits_close_file( fptr, &status ); // close file
  if ( 0 != status ) {
   fits_report_error( stderr, status ); // print out any error messages
   fits_clear_errmsg();                 // clear the CFITSIO error message stack
   return status;
  }
  fits_open_file( &fptr, fitsfilename, READONLY, &status );
  if ( 0 != status ) {
   fits_report_error( stderr, status ); // print out any error messages
   fits_clear_errmsg();                 // clear the CFITSIO error message stack
   return status;
  }
 }

 // Moved here as we may need the exposure time to set time using UT-END
 // if exposure!=0.0 we assume it was set earlier by Kourovka_SBG_date_hack()
 if ( exposure == 0.0 ) {
  // give TEXPTIME (Telemetry Exposure Time) higher priority than EXPTIME
  fits_read_key( fptr, TDOUBLE, "TEXPTIME", &exposure, EXPOSURE_COMMENT, &status );
  if ( status == 202 ) {
   status= 0;
   fits_read_key( fptr, TDOUBLE, "EXPTIME", &exposure, EXPOSURE_COMMENT, &status );
  } else {
   fprintf( stderr, "Using exposure from TEXPTIME\n" );
  }
  if ( status == 202 ) {
   status= 0;
   if ( param_verbose >= 1 )
    fprintf( stderr, "Looking for exposure in EXPOSURE (after checking EXPTIME)\n" );
   fits_read_key( fptr, TDOUBLE, "EXPOSURE", &exposure, EXPOSURE_COMMENT, &status );
   if ( status == 202 ) {
    status= 0;
    if ( param_verbose >= 1 )
     fprintf( stderr, "Looking for exposure in TM-EXPOS \n" );
    fits_read_key( fptr, TDOUBLE, "TM-EXPOS", &exposure, EXPOSURE_COMMENT, &status );
    if ( status == 202 ) {
     if ( param_verbose >= 1 )
      fprintf( stderr, "I can't find a keyword with exposure time! ;(     assuming EXPTIME=0\n" );
     exposure= 0.0;
     status= 0;
    }
   }
  }
  fits_report_error( stderr, status ); /* print out any error messages */
  fits_clear_errmsg();                 // clear the CFITSIO error message stack
  // Try to parse the exposure keyword comment and handle the situation when the exposure is not expressed in seconds
  //
  EXPOSURE_COMMENT[2048 - 1]= '\0'; // just in case
  if ( strlen( EXPOSURE_COMMENT ) > 8 ) {
   // Trying to simplify
   if ( strcasecmp( EXPOSURE_COMMENT, "seconds" ) != 0 ) {
    if ( strcasecmp( EXPOSURE_COMMENT, "minutes" ) == 0 ) {
     exposure= exposure * 60.0;
    } else if ( strcasecmp( EXPOSURE_COMMENT, "hours" ) == 0 ) {
     exposure= exposure * 3600.0;
    } else if ( strstr( EXPOSURE_COMMENT, "[d] time on source" ) != NULL ) {
     exposure= exposure * 86400.0;
    }
   } // if ( strcasecmp(EXPOSURE_COMMENT, "seconds") != 0 ) {
  } // if ( strlen( EXPOSURE_COMMENT ) > 8 ) {
  //
  // Search for the deadtime correction keyword like in TESS
  fits_read_key( fptr, TDOUBLE, "DEADC", &TESS_style_deadtime_correction, NULL, &status );
  if ( status == 0 ) {
   if ( param_verbose >= 1 ) {
    fprintf( stderr, "WARNING: applying dead time correction %lf from 'DEADC' to exposure %.3lf\n", TESS_style_deadtime_correction, exposure );
   }
   exposure= exposure / TESS_style_deadtime_correction;
  }
  status= 0; // we are fine even if there is no DEADC key
  //
 } // if( exposure!=0.0 ){

 if ( exposure < SHORTEST_EXPOSURE_SEC || exposure > LONGEST_EXPOSURE_SEC ) {
  if ( param_verbose >= 1 )
   fprintf( stderr, "WARNING: exposure time %lf is out of range (%.0lf,%.0lf)\nAssuming ZERO exposure time!\n", exposure, SHORTEST_EXPOSURE_SEC, LONGEST_EXPOSURE_SEC );
  exposure= 0.0;
 }

 // Special case: we want to always use SHUTOPEN instead of DATE-OBS for ZTF images, even if DATE-OBS is present
 fits_read_key( fptr, TSTRING, "SHUTOPEN", DATEOBS, DATEOBS_COMMENT, &status );
 if ( status == 0 ) {
  // This is what exactly ???
  if ( param_nojdkeyword == 1 ) {
   fprintf( stderr, "WARNING: cannot ignore both 'JD' and 'DATE-OBS' keywords! Will allow use of 'JD' keyword. \n" );
  }
  // ???
  fprintf( stderr, "WARNING: ignoring 'DATE-OBS' keyword as 'SHUTOPEN' is present.\n" );
  param_nojdkeyword= 2;
 }
 fits_clear_errmsg(); // clear the CFITSIO error message stack
 status= 0;

 // Check if these are EROS observations were DATE-OBS corresponds to the middle of exposure
 // so we need to set exposure=0.0 in order not to introduce the middle of exposure correction twice.
 is_this_an_EROS_image= 0;
 // all EROS images have DATE-OBS
 //
 // check if we are allowed to use JD keyword
 if ( param_nojdkeyword == 2 ) {
  status= 202;
 } else {
  fits_read_key( fptr, TSTRING, "DATE-OBS", DATEOBS, DATEOBS_COMMENT, &status );
 }
 if ( status == 0 ) {
  // Check if this is an EROS image, there are two types
  // The first type of images
  fits_read_key( fptr, TSTRING, "TU-START", DATEOBS, DATEOBS_COMMENT, &status );
  if ( status == 0 ) {
   fits_read_key( fptr, TSTRING, "TU-END", DATEOBS, DATEOBS_COMMENT, &status );
   if ( status == 0 ) {
    is_this_an_EROS_image= 1;
   } // TU-END
  } // TU-START
  if ( is_this_an_EROS_image == 0 ) {
   // The second type of images
   fits_clear_errmsg(); // clear the CFITSIO error message stack
   status= 0;
   fits_read_key( fptr, TSTRING, "TM-EXPOS", DATEOBS, DATEOBS_COMMENT, &status );
   if ( status == 0 ) {
    fits_read_key( fptr, TSTRING, "FILTREF", DATEOBS, DATEOBS_COMMENT, &status );
    if ( status == 0 ) {
     is_this_an_EROS_image= 1;
    } // FILTREF
   } // TM-EXPOS
  } // if( is_this_an_EROS_image==0 ){
 } // DATE-OBS
 // conclusion
 if ( is_this_an_EROS_image == 1 ) {
  if ( param_verbose >= 1 )
   fprintf( stderr, "WARNING: assuming DATE-OBS corresponds to the middle of exposure!\nSetting exposure time to zero in order not to introduce the middle-of-exposure correction twice.\n" );
  exposure= 0.0;
 }
 // cleanup
 // memset( DATEOBS, 0, 32 );
 memset( DATEOBS, 0, FLEN_CARD );
 memset( DATEOBS_COMMENT, 0, 2048 );
 fits_clear_errmsg(); // clear the CFITSIO error message stack
 status= 0;
 // end of cleanup

 DATEOBS_COMMENT[0]= '\0'; // just in case
 // check if we are allowed to use JD keyword
 if ( param_nojdkeyword == 2 ) {
  status= 202;
 } else {
  fits_read_key( fptr, TSTRING, "DATE-OBS", DATEOBS, DATEOBS_COMMENT, &status );
 }
 if ( status == 0 ) {
  date_parsed= 1;
  strncpy( DATEOBS_KEY_NAME, "DATE-OBS", 9 );
 }
 DATEOBS_COMMENT[FLEN_CARD - 1]= '\0'; // just in case

 // Handle the case that DATE-OBS is present, but EMPTY
 if ( 0 == strlen( DATEOBS ) && status == 0 ) {
  fprintf( stderr, "WARNING from gettime(): DATE-OBS keyword is present in the header but is empty!\n" );
  status= 202; // act if the keyword is not present at all
 }

 if ( status == 202 ) {
  // if DATE-OBS does not exist, try DATE-BEG
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  status= 0;
  fits_read_key( fptr, TSTRING, "DATE-BEG", DATEOBS, DATEOBS_COMMENT, &status );
  if ( status == 0 ) {
   date_parsed= 1;
   strncpy( DATEOBS_KEY_NAME, "DATE-BEG", 9 );
  }
  DATEOBS_COMMENT[FLEN_CARD - 1]= '\0'; // just in case
 }

 if ( status == 202 ) {
  // if DATE-OBS and DATE-BEG do not exist, try DATE-EXP
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  status= 0;
  fits_read_key( fptr, TSTRING, "DATE-EXP", DATEOBS, DATEOBS_COMMENT, &status );
  if ( status == 0 ) {
   date_parsed= 1;
   strncpy( DATEOBS_KEY_NAME, "DATE-EXP", 9 );
  }
  DATEOBS_COMMENT[FLEN_CARD - 1]= '\0'; // just in case
 }

 // SHUTOPEN is in ZTF images
 if ( status == 202 ) {
  // if DATE-OBS, DATE-BEG, DATE-EXP do not exist, try SHUTOPEN
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  status= 0;
  fits_read_key( fptr, TSTRING, "SHUTOPEN", DATEOBS, DATEOBS_COMMENT, &status );
  if ( status == 0 ) {
   date_parsed= 1;
   strncpy( DATEOBS_KEY_NAME, "SHUTOPEN", 9 );
  }
  DATEOBS_COMMENT[FLEN_CARD - 1]= '\0'; // just in case
 }

 // DATE_OBS is in example image from Felice Cusano
 if ( status == 202 ) {
  // if DATE-OBS, DATE-BEG, DATE-EXP, SHUTOPEN do not exist, try DATE_OBS (with underscore sign)
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  status= 0;
  fits_read_key( fptr, TSTRING, "DATE_OBS", DATEOBS, DATEOBS_COMMENT, &status );
  if ( status == 0 ) {
   date_parsed= 1;
   strncpy( DATEOBS_KEY_NAME, "DATE_OBS", 9 );
  }
  DATEOBS_COMMENT[FLEN_CARD - 1]= '\0'; // just in case
 }

 // If both EXPSTART and EXPEND keywords are present - we want to use them instead of DATE-OBS and EXPTIME
 int status_before_EXPSTART_EXPEND_test= status;
 fits_read_key( fptr, TDOUBLE, "EXPSTART", &inJD, NULL, &status );
 if ( status == 0 ) {
  fits_read_key( fptr, TDOUBLE, "EXPEND", &inJD, NULL, &status );
  if ( status == 0 ) {
   fprintf( stderr, "Both EXPSTART and EXPEND keywords are present - will use them instead of DATE-OBS\n" );
   DATEOBS[0]= '\0';
   date_parsed= 0; // we will get the date later
   // status= 202; // seems unnecessary
  }
 }
 status= status_before_EXPSTART_EXPEND_test;

 // if DATE-OBS, DATE-BEG, DATE-EXP and SHUTOPEN do not exist at all, try DATE
 if ( status == 202 ) {
  date_parsed= 0;
  if ( param_verbose >= 1 ) {
   fprintf( stderr, "WARNING: DATE-OBS keyword not found, trying DATE...\n" );
  }
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  status= 0;
  // Trying to get the observing date from DATE is realy the last resort
  // fits_read_key(fptr, TSTRING, "DATE", DATEOBS, DATEOBS_COMMENT, &status);
  fits_read_key( fptr, TSTRING, "DATE", DATEOBS, NULL, &status ); // do not modify DATEOBS_COMMENT
  if ( status == 0 ) {
   date_parsed= 1; // We may be fine (but see the warning below)
   // This is a trick: if there are other date-related keywords in the header - DO NOT take the observing date from DATE keyword
   fits_read_key( fptr, TDOUBLE, "JD", &inJD, NULL, &status );
   if ( status == 0 ) {
    // strncpy(DATEOBS,"",2);
    DATEOBS[0]= '\0';
    date_parsed= 0; // we will get the date later
   }
   status= 0;
   fits_read_key( fptr, TDOUBLE, "JDMID", &inJD, NULL, &status );
   if ( status == 0 ) {
    // strncpy(DATEOBS,"",2);
    DATEOBS[0]= '\0';
    date_parsed= 0; // we will get the date later
   }
   status= 0;
   fits_read_key( fptr, TDOUBLE, "MIDTJD", &inJD, NULL, &status );
   if ( status == 0 ) {
    // strncpy(DATEOBS,"",2);
    DATEOBS[0]= '\0';
    date_parsed= 0; // we will get the date later
    // fprintf(stderr, "DEBUG MIDTJD\n");
   }
   status= 0;
   fits_read_key( fptr, TDOUBLE, "MJD-OBS", &inJD, NULL, &status );
   if ( status == 0 ) {
    // strncpy(DATEOBS,"",2);
    DATEOBS[0]= '\0';
    date_parsed= 0; // we will get the date later
   }
   // Do not look at EXPSTART if the image is from Aristarchos telescope!
   if ( 0 != strncmp( telescop, "Aristarchos", 11 ) ) {
    fits_clear_errmsg(); // clear the CFITSIO error message stack
    status= 0;
    fits_read_key( fptr, TDOUBLE, "EXPSTART", &inJD, NULL, &status );
    if ( status == 0 ) {
     // We will parse the EXPSTART date later,
     // here we just need to mark that we are not using DATE keyword to get the observing date/time
     DATEOBS[0]= '\0';
     date_parsed= 0; // we will get the date later
    }
   }
   fits_clear_errmsg(); // clear the CFITSIO error message stack
   status= 0;
   //
   if ( param_verbose >= 1 && date_parsed == 1 ) {
    fprintf( stderr, "\n***** WARNING! WARNING! WARNING! *****\n VaST is getting observing date from DATE keyword.\n This is usually the WRONG thing to do since this keyword typically contains the FITS file creation date rather than observing date.\n Ignore this warning only if you are absolutely sure that your images have observation start date written in DATE keyword.\n\n" );
    strcpy( DATEOBS_KEY_NAME, "DATE" );
   }
  }
 }
 if ( strlen( DATEOBS ) < 11 && strlen( DATEOBS ) > 1 && date_parsed == 1 ) {
  fix_DATEOBS_STRING( DATEOBS );                    // handle '25/12/2011' style DATE-OBS
  fix_DATEOBS_STRING__DD_MM_YYYY_format( DATEOBS ); // handle '09-10-2017' style DATE-OBS
  fits_read_key( fptr, TSTRING, "TIME-OBS", TIMEOBS, NULL, &status );
  if ( 0 == strcmp( TIMEOBS, "" ) ) {
   fits_clear_errmsg(); // clear the CFITSIO error message stack
   status= 0;           // guess need to set it here or the folowing  FITSIO request will not pass
   if ( param_verbose >= 1 )
    fprintf( stderr, "Looking for time of observation in START keyword (its format is assumed to be similar to TIME-OBS keyword)\n" );
   fits_read_key( fptr, TSTRING, "START   ", TIMEOBS, NULL, &status );
   status= 0; // need to set it here or the folowing  FITSIO request will not pass
   // if (0 == strcmp(TIMEOBS, "")) {
   if ( 0 == strlen( TIMEOBS ) ) {
    if ( param_verbose >= 1 )
     fprintf( stderr, "Looking for time of observation in UT-START keyword (its format is assumed to be similar to TIME-OBS keyword)\n" );
    status= 0;
    fits_read_key( fptr, TSTRING, "UT-START", TIMEOBS, NULL, &status );
    // Special trick for Aristarchos that somethimes doesn't have UT-START, but does have UT-END
    // fprintf(stderr,"\n\n\n\n\nDEBUGISHE TIMEOBS=#%s#\n\n\n\n\n",TIMEOBS);
    if ( 0 == strncmp( TIMEOBS, "NIL", 3 ) ) {
     fprintf( stderr, "Oh, this looks like the Aristarchos telescope header with invalid UT-START!\nWill try to see if there is UT-END?\n" );
     status= 0;
     fits_read_key( fptr, TSTRING, "UT-END", TIMEOBS, NULL, &status );
     if ( status == 0 ) {
      fprintf( stderr, "Yes, found UT-END\n" );
      if ( 0 != strncmp( TIMEOBS, "NIL", 3 ) ) {
       strcpy( TIMEOBS_KEY_NAME, "UT-END" );
       exposure= ( -1.0 ) * exposure;
       fprintf( stderr, "Yes, the UT-END value is not obviously empty!\nSetting the negative exposure time = %lf sec\n", exposure );
      } else {
       fprintf( stderr, "Oh, it's empty: UT-END=%s\n", TIMEOBS );
       TIMEOBS[0]= '\0';
      }
     }
    }
    //
    // if (0 == strcmp(TIMEOBS, "")){
    if ( 0 == strlen( TIMEOBS ) ) {
     fprintf( stderr, "WARNING! Cannot get proper observing time from FITS header! Assuming it will be provided as JD keyword...\n" );
     date_parsed= 0; // Mark that we were unable to parse the date yet
    } else {
     if ( 0 != strncmp( TIMEOBS_KEY_NAME, "UT-END", 6 ) ) {
      strcpy( TIMEOBS_KEY_NAME, "UT-START" );
     }
    }
   } else {
    strcpy( TIMEOBS_KEY_NAME, "START" );
   }
  } else {
   strcpy( TIMEOBS_KEY_NAME, "TIME-OBS" );
  }
  status= 0;
 } // if( strlen(DATEOBS)<11 && strlen(DATEOBS)>1 && date_parsed==1 ){

 /////// Look for EXPSTART keyword containing MJD (a convention used for HST images in the HLA) ///////
 /////// The other possibility we test for here is EXPSTART/EXPEND keywords containing JD (a convention used by Siril) ///////
 status= 0;
 if ( date_parsed == 0 ) {
  fprintf( stderr, "Trying to get observing start MJD from EXPSTART keyword...\n" );
  fits_read_key( fptr, TDOUBLE, "EXPSTART", &inJD, NULL, &status );
  if ( status != 202 ) {
   fprintf( stderr, "Getting the observing time of the exposure start from EXPSTART keyword: %.8lf\n", inJD );
   if ( EXPECTED_MIN_MJD < inJD && inJD < EXPECTED_MAX_MJD ) {
    fprintf( stderr, "Based on the numerical value, we think EXPSTART contains MJD\nUsing EXPSTART+EXPTIME/2 as the middle of exposure\n" );
    inJD= inJD + 2400000.5;
    fprintf( stderr, "Got observation time parameters: JD_start= %.8lf  exptime= %.3lf sec\n", inJD, exposure );
    inJD= inJD + exposure / 86400.0 / 2.0;
    ( *timesys )= 0; // UNKNOWN
    // date_parsed=1;
    expstart_mjd_parsed= 1;
   } else {
    // check if the value looks like a JD
    if ( EXPECTED_MIN_JD < inJD && inJD < EXPECTED_MAX_JD ) {
     fits_read_key( fptr, TDOUBLE, "EXPEND", &endJD, NULL, &status );
     if ( status != 202 ) {
      if ( EXPECTED_MIN_JD < endJD && endJD < EXPECTED_MAX_JD ) {
       fprintf( stderr, "Setting the middle of exposure time based on EXPSTART and EXPEND keywords.\n" );
       fprintf( stderr, "Got observation time parameters: JD_start= %.8lf  JD_end= %.8lf  exptime= %.3lf sec\n", inJD, endJD, exposure );
       inJD= ( inJD + endJD ) / 2.0;
       ( *timesys )= 1; // UT
       expstart_mjd_parsed= 1;
      } else {
       fprintf( stderr, "JD derived from EXPEND keyword %.8lf is out of the expected range (%.8lf,%.8lf)!\n", endJD, EXPECTED_MIN_JD, EXPECTED_MAX_JD );
       fprintf( stderr, "Got observation time parameters: JD_start= %.8lf  exptime= %.3lf sec\n", inJD, exposure );
       inJD= inJD + exposure / 86400.0 / 2.0;
       ( *timesys )= 0; // UNKNOWN
       expstart_mjd_parsed= 1;
      } // else if ( EXPECTED_MIN_JD < inJD && inJD < EXPECTED_MAX_JD ) {
     } else {
      // no EXPEND keyword
      fprintf( stderr, "No EXPEND keyword\n" );
      fprintf( stderr, "Got observation time parameters: JD_start= %.8lf  exptime= %.3lf sec\n", inJD, exposure );
      inJD= inJD + exposure / 86400.0 / 2.0;
      ( *timesys )= 0; // UNKNOWN
      expstart_mjd_parsed= 1;
     } // else if ( status != 202 ) {
     status= 0;
    } else {
     fprintf( stderr, "WARNING: the value %lf infered from EXPSTART keyword is outside the expected MJD range (%.0lf,%.0lf).\n", inJD, EXPECTED_MIN_MJD, EXPECTED_MAX_MJD );
    } // else if ( EXPECTED_MIN_JD < inJD && inJD < EXPECTED_MAX_JD ) {
   } // else if ( EXPECTED_MIN_MJD < inJD && inJD < EXPECTED_MAX_MJD ) {
  } // if ( status != 202 ) {
 } // if ( date_parsed == 0 ) {

 // Check if this is a TICA TESS FFI https://archive.stsci.edu/hlsp/tica#section-c34b9669-b0be-40b2-853e-a59997d1b7c5
 status= 0;
 if ( date_parsed == 0 && expstart_mjd_parsed == 0 ) {
  fprintf( stderr, "Trying to see if this is a TICA TESS FFI by looking for TJD_ZERO keyword...\n" );
  fits_read_key( fptr, TDOUBLE, "TJD_ZERO", &tjd_zero, NULL, &status );
  if ( status != 202 ) {
   fprintf( stderr, "Found TJD_ZERO keyword: %.8lf\nNow looking for MIDTJD keyword...\n", tjd_zero );
   fits_read_key( fptr, TDOUBLE, "MIDTJD", &midtjd, NULL, &status );
   if ( status != 202 ) {
    fprintf( stderr, "Found MIDTJD keyword: %.8lf\n", midtjd );
    inJD= tjd_zero + midtjd;
    if ( EXPECTED_MIN_JD < inJD && inJD < EXPECTED_MAX_JD ) {
     //
     fprintf( stderr, "Getting the observing time (middle of exposure) from TJD_ZERO + MIDTJD: %.8lf\n", inJD );
     ( *timesys )= 3; // TDB
     // The time system is TDB, but at the position of the TESS spacecraft (and therefore differs from geocentric TDB by a small light travel time).
     // https://tess.mit.edu/public/tesstransients/pages/readme.html
     expstart_mjd_parsed= 1;
     //
     if ( param_nojdkeyword == 1 ) {
      fprintf( stderr, "WARNING: overriding '--nojdkeyword' parameter for TICA TESS images! \n" );
      param_nojdkeyword= 0;
     }
     //
    } else {
     fprintf( stderr, "WARNING: the value %.8lf infered from TJD_ZERO + MIDTJD is outside the expected JD range (%.0lf,%.0lf).\n\n", inJD, EXPECTED_MIN_JD, EXPECTED_MAX_JD );
     inJD= 0.0;
    }
   } else {
    fprintf( stderr, "Found no MIDTJD keyword!\n" );
   } // MIDTJD
  } // TJD_ZERO
 } // if ( date_parsed == 0 && expstart_mjd_parsed == 0 ) {

 /////// Look for JD keyword (a convention used for Moscow photographic plate scans) ///////
 status= 0;
 // param_nojdkeyword==1 tells us that JD keyword should be ignored
 // date_parsed==0 means DATE-OBS was not found and parsed
 if ( param_nojdkeyword == 0 && date_parsed == 0 && expstart_mjd_parsed == 0 ) {
#ifdef DEBUGMESSAGES
  fprintf( stderr, "entering   if ( param_nojdkeyword == 0 && date_parsed == 0 && expstart_mjd_parsed == 0 )\n" );
#endif

  exposure= 0.0; // Assume JD keyword corresponds to the middle of exposure!!!
  fprintf( stderr, "Trying to get observing date from JD keyword...\n" );
  fits_read_key( fptr, TDOUBLE, "JD", &inJD, NULL, &status );
  // fprintf(stderr,"DEBUG: status = %d\n",status);
  if ( status == 0 ) {
#ifdef DEBUGMESSAGES
   fprintf( stderr, "entering   if ( status == 0 )\n" );
#endif
   // fprintf( stderr, "Getting JD of the middle of exposure from JD keyword: %.5lf\n", inJD );
   fprintf( stderr, "Getting JD of the middle of exposure from JD keyword: %.8lf\n", inJD );
   ( *timesys )= 1; // UT -- the convention for digitized Moscow collection plates
   // Check that JD is within the reasonable range
   if ( inJD < EXPECTED_MIN_JD || inJD > EXPECTED_MAX_JD ) {
    fprintf( stderr, "ERROR: JD %lf is out of expected range (%.1lf, %.1lf)!\nYou may change EXPECTED_MIN_JD and EXPECTED_MAX_JD in src/vast_limits.h and recompile VaST if you are _really sure_ you know what you are doing...\n", inJD, EXPECTED_MIN_JD, EXPECTED_MAX_JD );
    exit( EXIT_FAILURE ); // should this be return ?! we probably don't want a catastrophic crash based on one image with funny JD in the header
   }
  } else {
#ifdef DEBUGMESSAGES
   fprintf( stderr, "entering  else corresponding to if ( status == 0 )\n" );
#endif
   status= 0; // reset
   fprintf( stderr, "Trying to get observing date from JDMID keyword...\n" );
   fits_read_key( fptr, TDOUBLE, "JDMID", &inJD, NULL, &status );
   if ( status == 0 ) {
#ifdef DEBUGMESSAGES
    fprintf( stderr, "entering  if ( status == 0 )\n" );
#endif
    fprintf( stderr, "Getting JD of the middle of exposure from JDMID keyword: %.8lf\n", inJD );
    ( *timesys )= 1; // UT
    // Check that JD is within the reasonable range
    if ( inJD < EXPECTED_MIN_JD || inJD > EXPECTED_MAX_JD ) {
     fprintf( stderr, "ERROR: JD %lf is out of expected range (%.1lf, %.1lf)!\nYou may change EXPECTED_MIN_JD and EXPECTED_MAX_JD in src/vast_limits.h and recompile VaST if you are _really sure_ you know what you are doing...\n", inJD, EXPECTED_MIN_JD, EXPECTED_MAX_JD );
     exit( EXIT_FAILURE );
    }
   } else {
    // MJD-OBS
    status= 0; // reset
    fprintf( stderr, "Trying to get observing date from MJD-OBS keyword...\n" );
    fits_read_key( fptr, TDOUBLE, "MJD-OBS", &inJD, NULL, &status );
    if ( status == 0 ) {
     fprintf( stderr, "Getting MJD of the middle of exposure from MJD-OBS keyword: %.8lf\n", inJD );
     // Check that MJD is within the reasonable range
     if ( inJD < EXPECTED_MIN_MJD || inJD > EXPECTED_MAX_MJD ) {
      fprintf( stderr, "ERROR: MJD %lf is out of expected range (%.1lf, %.1lf)!\nYou may change EXPECTED_MIN_MJD and EXPECTED_MAX_MJD in src/vast_limits.h and recompile VaST if you are _really sure_ you know what you are doing...\n", inJD, EXPECTED_MIN_MJD, EXPECTED_MAX_MJD );
      exit( EXIT_FAILURE );
     }
     inJD= inJD + 2400000.5; // convert MJD to JD
     ( *timesys )= 0;        // UNKNOWN
     // Check that JD is within the reasonable range
     if ( inJD < EXPECTED_MIN_JD || inJD > EXPECTED_MAX_JD ) {
      fprintf( stderr, "ERROR: JD %lf is out of expected range (%.1lf, %.1lf)!\nYou may change EXPECTED_MIN_JD and EXPECTED_MAX_JD in src/vast_limits.h and recompile VaST if you are _really sure_ you know what you are doing...\n", inJD, EXPECTED_MIN_JD, EXPECTED_MAX_JD );
      exit( EXIT_FAILURE );
     }
    } // if( status == 0 ) { for MJD-OBS
   } // else for JDMID keyword
  } // else for JD keyword
  if ( status != 0 ) {
#ifdef DEBUGMESSAGES
   fprintf( stderr, "entering  if ( status != 0 )\n" );
#endif
   // Testing if this is the mad header from Kourovka SBG?
   status= 0;
   fprintf( stderr, "Testing if this is an image from Kourovka SBG camera...\n" );
   status= Kourovka_SBG_date_hack( fitsfilename, DATEOBS, &date_parsed, &exposure );
   if ( status != 0 ) {
#ifdef DEBUGMESSAGES
    fprintf( stderr, "entering  if ( status != 0 )\n" );
#endif
    date_parsed= 0; // if Kourovka_SBG_date_hack() failed...
    // fprintf(stderr, "No, it's not.\nWARNING: cannot determine date/time associated with this image!\n");
    fprintf( stderr, "No, it's not a Kourovka SBG camera image.\n \x1B[01;31m WARNING: cannot determine date/time associated with this image! \x1B[33;00m \n" );
    // Special case - no date information in the image file
    inJD= 0.0;
    status= 0;
   } else {
#ifdef DEBUGMESSAGES
    fprintf( stderr, "entering  else corresponding to if ( status != 0 )\n" );
#endif
    fprintf( stderr, "Yes this is an image from Kourovka SBG camera! start=%s exp=%.1lf parsing_flag=%d\n", DATEOBS, exposure, date_parsed );
   }
  }
 } else {
#ifdef DEBUGMESSAGES
  fprintf( stderr, "entering  else corresponding to if ( param_nojdkeyword == 0 && date_parsed == 0 && expstart_mjd_parsed == 0 ) {\n" );
#endif
  status= 202; // proceed parsing the DATE string
  if ( param_nojdkeyword == 1 && date_parsed == 0 ) {
#ifdef DEBUGMESSAGES
   fprintf( stderr, "entering  if ( param_nojdkeyword == 1 && date_parsed == 0 )\n" );
#endif
   // Special case - no date information in the image file (and we are not allowed to use JD keyword, no matter if it's there or not)
   inJD= 0.0;
   status= 0;
  }
 }

#ifdef DEBUGMESSAGES
 fprintf( stderr, "debug checkpoint 01\n" );
#endif

 ( *dimX )= naxes[0];
 ( *dimY )= naxes[1];

 // Initiallize just in case
 memset( Tm_h, 0, 10 );
 memset( Tm_m, 0, 10 );
 memset( Tm_s, 0, FLEN_CARD );
 memset( Da_y, 0, 10 );
 memset( Da_m, 0, 10 );
 memset( Da_d, 0, FLEN_CARD );
 //
 memset( Tm_s_full_seconds_only, 0, FLEN_CARD );
 memset( Tm_s_fractional_seconds_only, 0, FLEN_CARD );
 //

 // status==202 here means the JD keyword is not found
 // date_parsed==0 means DATE-OBS was not found and parsed
 if ( status == 202 && date_parsed != 0 && expstart_mjd_parsed == 0 ) {
#ifdef DEBUGMESSAGES
  fprintf( stderr, "entering  if ( status == 202 && date_parsed != 0 && expstart_mjd_parsed == 0 )\n" );
#endif
  // if (status == 202) {
  /* If no JD keyword was found... */

  /*
               Try to guess time system (UTC or TT).
               Look for TIMESYS keyword, if it is not found
               - try to parse DATE-OBS comment.
             */
  status= 0;
  fits_read_key( fptr, TSTRING, "TIMESYS", TIMESYS, NULL, &status );
  if ( status != 202 ) {
#ifdef DEBUGMESSAGES
   fprintf( stderr, "entering  if ( status != 202 )\n" );
#endif
   // TIMESYS keyword found
   if ( param_verbose >= 1 ) {
    fprintf( stderr, "TIMESYS keyword found: %s\n", TIMESYS );
   }
   if ( TIMESYS[0] == 'T' && TIMESYS[1] == 'D' && TIMESYS[2] == 'B' ) {
    ( *timesys )= 3; // TDB
   } else if ( TIMESYS[0] == 'T' && TIMESYS[1] == 'T' ) {
    ( *timesys )= 2; // TT
   } else if ( TIMESYS[0] == 'U' && TIMESYS[1] == 'T' ) {
    ( *timesys )= 1; // UT
   } else {
    ( *timesys )= 0; // UNKNOWN
   }
   // Another common option is
   // TIMESYS = 'TDB     '           / time system is Barycentric Dynamical Time (TDB)
   // but we don't support it yet. When we do - check times derived from TESS image headers
   // as currently we take the UTC ones from DATE-OBS + EXPOSURE + DEADC
  } // else {
  status= 0;
  // Try to parse DATEOBS_COMMENT even if TIMESYS was set
  // TESS SPOC images are the example where TIMESYS is TDB... but not for the DATE-OBS field
  // #ifdef DEBUGMESSAGES
  //    fprintf( stderr, "entering  else corresponding to if ( status != 202 )\n" );
  // #endif
  //  Here we assume that TT system can be only set from TIMESYS keyword.
  //  If it's not there - the only timing options are UTC or UNKNOWN

  //// TIMESYS keyword not found, try to parse DATE-OBS comment string
  // if ( param_verbose >= 1 ) {
  //  fprintf( stderr, "TIMESYS keyword is not in the FITS header.\n" );
  // }
  //  Make sure the string is not empty
  if ( strlen( DATEOBS_COMMENT ) > 1 ) {
   if ( param_verbose >= 1 )
    fprintf( stderr, "Trying to guess the time system by parsing the comment string '%s'\n", DATEOBS_COMMENT );
   // don't start from 0 - if there is no comment, the string will contain 0 characters before \0 !
   for ( j= 1; j < (int)strlen( DATEOBS_COMMENT ) - 1; j++ ) {
    if ( DATEOBS_COMMENT[j] == 'U' && DATEOBS_COMMENT[j + 1] == 'T' ) {
     ( *timesys )= 1; // UT
     if ( param_verbose >= 1 )
      fprintf( stderr, "Time system set from the comment to DATE-OBS keyword: '%s'\n", DATEOBS_COMMENT );
     break;
    }
   }
  } else {
   if ( param_verbose >= 1 )
    fprintf( stderr, "No suitable comment string found\n" );
  } // if( strlen(DATEOBS_COMMENT)>1 ){

  // make sure we have one of the expected timesys values
  if ( ( *timesys ) != 1 && ( *timesys ) != 2 && ( *timesys ) != 3 ) {
   ( *timesys )= 0; // UNKNOWN
   if ( param_verbose >= 1 )
    fprintf( stderr, "Time system is set to UNKNOWN\n" );
  }
  //}

  // Choose string to describe time system
  if ( ( *timesys ) == 3 ) {
   sprintf( tymesys_str_in, "TDB" );
  } else if ( ( *timesys ) == 2 ) {
   sprintf( tymesys_str_in, "TT" );
  } else if ( ( *timesys ) == 1 ) {
   sprintf( tymesys_str_in, "UTC" );
  } else {
   sprintf( tymesys_str_in, " " );
  }

  if ( param_verbose >= 1 ) {
   fprintf( stderr, "The input time system is identified as: %s (blank if unknown)\n", tymesys_str_in );
  }
  if ( param_verbose >= 1 ) {
   fprintf( stderr, "Setting observation date using %s keyword: %s\n", DATEOBS_KEY_NAME, DATEOBS );
  }
  //
  if ( 0 == strlen( DATEOBS ) ) {
   fprintf( stderr, "ERROR in gettime(): the %s FITS header key that is supposed to report the observation date is missing or empty!\n", DATEOBS_KEY_NAME );
   fits_close_file( fptr, &status ); // close file
   return 1;
  }
  if ( strlen( DATEOBS ) < 8 ) {
   fprintf( stderr, "ERROR in gettime(): strlen(%s) < 8\n", DATEOBS );
   fits_close_file( fptr, &status ); // close file
   return 1;
  }
  // fprintf( stderr, " %d #%s#\n", strlen(DATEOBS), DATEOBS);
  //

  // for( j= 0; j < 32; j++ ) {
  for ( j= 0; j < 5; j++ ) {
   // if( DATEOBS[j] == 45 ) {
   if ( DATEOBS[j] == '-' ) {
    Da_y[j]= '\0';
    break;
   }
   Da_y[j]= DATEOBS[j];
  }
  j_end_of_year= j + 1;
  for ( j+= 1; j < 8; j++ ) {
   // fprintf(stderr,"DEBUGISHE %d %c  j_end_of_year=%d\n", j, DATEOBS[j], j_end_of_year);
   //  if( DATEOBS[j] == 45 ) {
   if ( DATEOBS[j] == '-' ) {
    // if ( j - 5 < 0 ) {
    if ( j - j_end_of_year < 0 ) {
     fprintf( stderr, "ERROR100 in gettime()\n" );
     fits_close_file( fptr, &status ); // close file
     return 1;
    }
    // Da_m[j - 5]= '\0';
    Da_m[j - j_end_of_year]= '\0';
    break;
   }
   // if ( j - 5 < 0 ) {
   if ( j - j_end_of_year < 0 ) {
    fprintf( stderr, "ERROR101 in gettime()\n" );
    fits_close_file( fptr, &status ); // close file
    return 1;
   }
   // Da_m[j - 5]= DATEOBS[j];
   Da_m[j - j_end_of_year]= DATEOBS[j];
  }
  j_end_of_month= j + 1;
  for ( j+= 1; j < 32; j++ ) {
   if ( DATEOBS[j] == '\0' || DATEOBS[j] == 'T' ) {
    // if ( j - 7 < 0 ) {
    if ( j - j_end_of_month < 0 ) {
     fprintf( stderr, "ERROR102 in gettime()\n" );
     fits_close_file( fptr, &status ); // close file
     return 1;
    }
    // Da_d[j - 7]= '\0';
    Da_d[j - j_end_of_month]= '\0';
    break;
   }
   // if ( j - 8 < 0 ) {
   //  !!! why 8 ???
   if ( j - j_end_of_month < 0 ) {
    fprintf( stderr, "ERROR103 in gettime()\n" );
    fits_close_file( fptr, &status ); // close file
    return 1;
   }
   // Da_d[j - 8]= DATEOBS[j];
   //  !!! why 8 ???
   Da_d[j - j_end_of_month]= DATEOBS[j];
  }
  // Если время прописано в DATE-OBS после T
  if ( DATEOBS[j] == 'T' ) {
   if ( param_verbose >= 1 )
    fprintf( stderr, "Setting observation time using %s keyword: %s\n", DATEOBS_KEY_NAME, DATEOBS );
   jj= 0;
   for ( j+= 1; j < 32; j++ ) {
    // if ( DATEOBS[j] == '\0' ) {
    //  explicitly handle 2023-05-17T23:22:38.894T00:00:24.955
    if ( DATEOBS[j] == '\0' || DATEOBS[j] == 'T' ) {
     TIMEOBS[jj]= '\0';
     break;
    }
    TIMEOBS[jj]= DATEOBS[j];
    jj++;
   }
  } else {
   if ( 0 == strlen( TIMEOBS_KEY_NAME ) ) {
    fprintf( stderr, "ERROR in gettime(): cannot find a FITS header key reporting the observation start time!\n" );
    fits_close_file( fptr, &status ); // close file
    return 1;
   }
   if ( param_verbose >= 1 ) {
    fprintf( stderr, "Setting observation time using %s keyword: %s\n", TIMEOBS_KEY_NAME, TIMEOBS );
   }
  }

  ///////////////////////////////////
  // for ( j= 0; j < 32; j++ ) {
  for ( j= 0; j < 3; j++ ) {
   if ( TIMEOBS[j] == ':' ) {
    Tm_h[j]= '\0';
    break;
   }
   Tm_h[j]= TIMEOBS[j];
  }
  // for ( j+= 1; j < 32; j++ ) {
  for ( j+= 1; j < 3 + 3; j++ ) {
   if ( TIMEOBS[j] == ':' || TIMEOBS[j] == '\0' ) {
    Tm_m[j - 3]= '\0';
    break;
   }
   Tm_m[j - 3]= TIMEOBS[j];
  }
  if ( j + 1 < (int)strlen( TIMEOBS ) ) {
   for ( j+= 1; j < 32; j++ ) {
    if ( TIMEOBS[j] == '\0' ) {
     Tm_s[j - 6]= '\0';
     break;
    }
    Tm_s[j - 6]= TIMEOBS[j];
   }
   Tm_s[6]= '\0';
   //
   sanitize_positive_float_string( Tm_s );
   //
  } else {
   // no seconds
   Tm_s[0]= '0';
   Tm_s[1]= '0';
   Tm_s[2]= '\0';
  }
  //
  Tm_m[2]= '\0';
  Tm_h[2]= '\0';
  Da_d[2]= '\0';
  Da_m[2]= '\0';
  Da_y[4]= '\0';
  if ( strlen( Tm_s ) < 1 || strlen( Tm_m ) < 1 || strlen( Tm_h ) < 1 || strlen( Da_d ) < 1 || strlen( Da_m ) < 1 || strlen( Da_y ) < 2 ) {
   fprintf( stderr, "ERROR000 in gettime(): string length check failed on broken-down time components\n" );
   fits_close_file( fptr, &status ); // close file
   return 1;
  }
  //
  parse_seconds_and_fraction( Tm_s, Tm_s_full_seconds_only, Tm_s_fractional_seconds_only );
  double_fractional_seconds_only= atof( Tm_s_fractional_seconds_only );
  // fprintf(stderr, "Tm_s=#%s# Tm_s_full_seconds_only=#%s# Tm_s_fractional_seconds_only=#%s# double_fractional_seconds_only=%lf\n",Tm_s,Tm_s_full_seconds_only,Tm_s_fractional_seconds_only,double_fractional_seconds_only);
  //  someday I'll need to get rid of this gross simplification
  // structureTIME.tm_sec= (int)( atof( Tm_s ) + 0.5 );
  //  what better place than here, what better time than now?
  structureTIME.tm_sec= atoi( Tm_s_full_seconds_only );
  if ( structureTIME.tm_sec < 0 || structureTIME.tm_sec > 60 ) {
   fprintf( stderr, "ERROR001 in gettime(): the derived time is seconds is out of the expected [0:60] range\n" );
   fits_close_file( fptr, &status );
   return 1;
  }
  structureTIME.tm_min= atoi( Tm_m );
  if ( structureTIME.tm_min < 0 || structureTIME.tm_min > 60 ) {
   fprintf( stderr, "ERROR002 in gettime(): the minute is not between 0 and 60\n" );
   fits_close_file( fptr, &status );
   return 1;
  }
  structureTIME.tm_hour= atoi( Tm_h );
  if ( structureTIME.tm_hour < 0 || structureTIME.tm_hour > 24 ) {
   fprintf( stderr, "ERROR003 in gettime(): the hour is not between 0 and 24\n" );
   fits_close_file( fptr, &status );
   return 1;
  }
  structureTIME.tm_mday= atoi( Da_d );
  if ( structureTIME.tm_mday < 0 || structureTIME.tm_mday > 31 ) {
   fprintf( stderr, "ERROR004 in gettime(): the day of the month is not between 0 and 31\n" );
   fits_close_file( fptr, &status );
   return 1;
  }
  structureTIME.tm_mon= atoi( Da_m ) - 1;
  if ( structureTIME.tm_mon < 0 || structureTIME.tm_mon > 12 ) {
   fprintf( stderr, "ERROR005 in gettime(): the month is not between 0 and 12\n" );
   fits_close_file( fptr, &status );
   return 1;
  }
  structureTIME.tm_year= atoi( Da_y ) - 1900;
  unix_time= timegm( &structureTIME );
  ///////////////////////////////////
  // A silly atempt to accomodate exposures crossing the midnight
  // that have time set through UT-END while date is correponding
  // to exposure start on the previous day.
  if ( exposure < 0.0 ) {
   struct tm structureTIME2;
   structureTIME2.tm_sec= 0;
   structureTIME2.tm_min= 0;
   structureTIME2.tm_hour= 0;
   structureTIME2.tm_mday= structureTIME.tm_mday;
   structureTIME2.tm_mon= structureTIME.tm_mon;
   structureTIME2.tm_year= structureTIME.tm_year;
   if ( (double)unix_time - (double)timegm( &structureTIME2 ) < ( -1.0 ) * exposure ) {
    fprintf( stderr, "WARNING!!! The exposure is crossing midnight while it's time is set through UT-END!\n" );
    unix_time+= 86400;
   }
  }
  ///////////////////////////////////
  /*
  // Need to rewrite this for sub-second accuracy in reference time and exposure

  // Oh, this is a funny one: cf. date -d '1969-12-31T23:59:59' +%s  and  date -d '1970-01-01T00:00:00' +%s
  if ( (double)unix_time + exposure / 2.0 < 0.0 ) {
   unix_time= (time_t)( (double)unix_time + exposure / 2.0 - 0.5 );
  } else {
   unix_time= (time_t)( (double)unix_time + exposure / 2.0 + 0.5 );
  }

  ( *JD )= (double)unix_time / 3600.0 / 24.0 + 2440587.5 + apply_JD_correction_in_days; // note that the time correction is not reflected in the broken down time!
  */

  ( *JD )= exposure / ( 2.0 * 86400.0 ) + (double)unix_time / 86400.0 + double_fractional_seconds_only / 86400.0 + 2440587.5 + apply_JD_correction_in_days; // note that the time correction is not reflected in the broken down time!

  if ( overridingJD_from_input_image_list != 0.0 ) {
   // Override the computed JD!
   ( *JD )= overridingJD_from_input_image_list;
   if ( ( *timesys ) == 1 && convert_timesys_to_TT == 1 ) {
    if ( param_verbose >= 1 ) {
     fprintf( stderr, "Note that JD(UTC) to JD(TT) conversion will still be applied to the overriding JD.\n" );
    }
   }
  }

  // Convert JD(UTC) to JD(TT) if needed
  if ( ( *timesys ) == 1 && convert_timesys_to_TT == 1 ) {
   ( *JD )= convert_jdUT_to_jdTT( ( *JD ), timesys );
  }

  // Choose string to describe new time system
  if ( ( *timesys ) == 3 ) {
   sprintf( tymesys_str_out, "(TDB)" );
  } else if ( ( *timesys ) == 2 ) {
   sprintf( tymesys_str_out, "(TT)" );
  } else if ( ( *timesys ) == 1 ) {
   sprintf( tymesys_str_out, "(UTC)" );
  } else {
   sprintf( tymesys_str_out, " " );
  }

  if ( NULL != log_output ) {
   // If we use the JD->logstring converison function here, the start date might be TT (if it was converted)
   // What we actually want is to keep this date UTC (or whatever timesystem of the original FITS header was).
   // sprintf( log_output, "exp_start= %02d.%02d.%4d %02d:%02d:%02d  exp= %4.0lf  ", structureTIME.tm_mday, structureTIME.tm_mon + 1, structureTIME.tm_year - 100 + 2000, structureTIME.tm_hour, structureTIME.tm_min, structureTIME.tm_sec, exposure );
   sprintf( log_output, "exp_start= %02d.%02d.%4d %02d:%02d:%06.3lf  exp= %8.3lf  ", structureTIME.tm_mday, structureTIME.tm_mon + 1, structureTIME.tm_year - 100 + 2000, structureTIME.tm_hour, structureTIME.tm_min, (double)( structureTIME.tm_sec ) + double_fractional_seconds_only, exposure );
  }

  // Produce finder_chart_timestring_output
  if ( NULL != finder_chart_timestring_output ) {
   generate_finder_chart_timestring( finder_chart_timestring_output,
                                     &structureTIME,
                                     double_fractional_seconds_only,
                                     tymesys_str_in,
                                     exposure );
  }

  /*
    // Produce finder_chart_timestring_output
    if ( NULL != finder_chart_timestring_output ) {

     // make sure a lonely coma is not hanging in the middle of the string if tymesys_str_in is a white space
     coma_or_whitespace_character_after_timesys= ',';
     if ( 0 == strcmp( tymesys_str_in, " " ) ) {
      coma_or_whitespace_character_after_timesys= ' ';
     }
     if ( exposure > 0.0 ) {
      // Write exposure time if it's non-zero
      // sprintf( finder_chart_timestring_output, "%4d-%02d-%02d %02d:%02d:%02d %s, %.0lf sec",
      sprintf( finder_chart_timestring_output, "%4d-%02d-%02d %02d:%02d:%02d %s%c %.0lf sec",
               structureTIME.tm_year - 100 + 2000,
               structureTIME.tm_mon + 1,
               structureTIME.tm_mday,
               structureTIME.tm_hour,
               structureTIME.tm_min,
               structureTIME.tm_sec,
               tymesys_str_in,
               coma_or_whitespace_character_after_timesys,
               exposure );
     } else {
      // Do not write exposure time if it's zero
      sprintf( finder_chart_timestring_output, "%4d-%02d-%02d %02d:%02d:%02d %s",
               structureTIME.tm_year - 100 + 2000,
               structureTIME.tm_mon + 1,
               structureTIME.tm_mday,
               structureTIME.tm_hour,
               structureTIME.tm_min,
               structureTIME.tm_sec,
               tymesys_str_in );
     }
    }
  */

  if ( NULL != stderr_output ) {
   if ( exposure != 0 ) {
    if ( 0 == double_fractional_seconds_only ) {
     sprintf( stderr_output, "Exposure %3.0lf sec, %02d.%02d.%4d %02d:%02d:%02d %s = JD%s %.5lf mid. exp.\n", exposure, structureTIME.tm_mday, structureTIME.tm_mon + 1, structureTIME.tm_year - 100 + 2000, structureTIME.tm_hour, structureTIME.tm_min, structureTIME.tm_sec, tymesys_str_in, tymesys_str_out, ( *JD ) );
    } else {
     sprintf( stderr_output, "Exposure %3.0lf sec, %02d.%02d.%4d %02d:%02d:%06.3lf %s = JD%s %.8lf mid. exp.\n", exposure, structureTIME.tm_mday, structureTIME.tm_mon + 1, structureTIME.tm_year - 100 + 2000, structureTIME.tm_hour, structureTIME.tm_min, (double)structureTIME.tm_sec + double_fractional_seconds_only, tymesys_str_in, tymesys_str_out, ( *JD ) );
    }
   }
   if ( exposure == 0 ) {
    if ( 0 == double_fractional_seconds_only ) {
     sprintf( stderr_output, "Exposure %3.0lf sec, %02d.%02d.%4d %02d:%02d:%02d %s = JD%s %.5lf\n", exposure, structureTIME.tm_mday, structureTIME.tm_mon + 1, structureTIME.tm_year - 100 + 2000, structureTIME.tm_hour, structureTIME.tm_min, structureTIME.tm_sec, tymesys_str_in, tymesys_str_out, ( *JD ) );
    } else {
     sprintf( stderr_output, "Exposure %3.0lf sec, %02d.%02d.%4d %02d:%02d:%06.3lf %s = JD%s %.8lf\n", exposure, structureTIME.tm_mday, structureTIME.tm_mon + 1, structureTIME.tm_year - 100 + 2000, structureTIME.tm_hour, structureTIME.tm_min, (double)structureTIME.tm_sec + double_fractional_seconds_only, tymesys_str_in, tymesys_str_out, ( *JD ) );
    }
   }
   // make a better-looking stderr_output
   remove_multiple_spaces( stderr_output );
  } // if ( NULL != stderr_output ) {
 } else {
  // This else is for:
  // status==202 here means the JD keyword is not found
  // date_parsed==0 means DATE-OBS was not found and parsed
  // if ( status == 202 && date_parsed != 0 && expstart_mjd_parsed == 0 ) {

#ifdef DEBUGMESSAGES
  fprintf( stderr, "entering  else corresponding to if ( status == 202 && date_parsed != 0 && expstart_mjd_parsed == 0 )\n" );
#endif
  // Setting pre-calculated JD(UT) mid. exp. from the JD keyword
  //( *timesys )= 1;
  // sprintf( tymesys_str_out, "(UT)" );
  // Choose string to describe new time system
  if ( ( *timesys ) == 3 ) {
   sprintf( tymesys_str_out, "(TDB)" );
  } else if ( ( *timesys ) == 2 ) {
   sprintf( tymesys_str_out, "(TT)" );
  } else if ( ( *timesys ) == 1 ) {
   sprintf( tymesys_str_out, "(UTC)" );
  } else {
   sprintf( tymesys_str_out, " " );
  }
  //
  ( *JD )= inJD + apply_JD_correction_in_days;
  if ( overridingJD_from_input_image_list != 0.0 ) {
#ifdef DEBUGMESSAGES
   fprintf( stderr, "entering  if ( overridingJD_from_input_image_list != 0.0 ) \n" );
#endif
   // Override the computed JD!
   ( *JD )= overridingJD_from_input_image_list;
   ( *timesys )= 0; // UNKNOWN
  }
#ifdef DEBUGMESSAGES
  fprintf( stderr, "debug checkpoint a01\n" );
#endif
  // exposure = 0.0;
  if ( NULL != stderr_output ) {
#ifdef DEBUGMESSAGES
   fprintf( stderr, "entering  if ( NULL != stderr_output )\n" );
#endif
   // fprintf( stderr, "JD (mid. exp.) %.5lf\n", ( *JD ) );
   fprintf( stderr, "JD (mid. exp.) %.8lf\n", ( *JD ) );
   // unix_time= (time_t)( ( ( *JD ) - 2440587.5 ) * 3600.0 * 24.0 + 0.5 );
   // form_DATEOBS_and_EXPTIME_from_UNIXSEC( unix_time, 0.0, formed_str_DATEOBS, formed_str_EXPTIME );
   // fprintf(stderr, "DEBUG01 form_DATEOBS_EXPTIME_log_output_from_JD()\n");
   form_DATEOBS_EXPTIME_log_output_from_JD( ( *JD ), 0.0, formed_str_DATEOBS, formed_str_EXPTIME, log_output, finder_chart_timestring_output, 0 );
   for ( counter_i= 0; counter_i < strlen( formed_str_DATEOBS ); counter_i++ ) {
    if ( formed_str_DATEOBS[counter_i] == 'T' ) {
     formed_str_DATEOBS[counter_i]= ' ';
     break;
    }
   } // for( counter_i=0; counter_i<strlen(formed_str_DATEOBS); counter_i++ ){
   // sprintf( stderr_output, "JD (mid. exp.) %.5lf = %s %s\n", ( *JD ), formed_str_DATEOBS, tymesys_str_out );
   sprintf( stderr_output, "JD (mid. exp.) %.8lf = %s %s\n", ( *JD ), formed_str_DATEOBS, tymesys_str_out );
  }
#ifdef DEBUGMESSAGES
  fprintf( stderr, "debug checkpoint a03\n" );
#endif
  if ( NULL != log_output ) {
#ifdef DEBUGMESSAGES
   fprintf( stderr, "entering if ( NULL != log_output )\n" );
#endif
   // So why don't we form calendar date of exposure start
   if ( 0 != ( *JD ) ) {
    // time_t unix_time_exposure_start_for_logs= unix_time - (time_t)( exposure / 2.0 );
    // struct tm *structureTIME_for_logs= gmtime( &unix_time_exposure_start_for_logs );
    // sprintf( log_output, "exp_start= %02d.%02d.%4d %02d:%02d:%02d  exp= %4.0lf  ", structureTIME_for_logs->tm_mday, structureTIME_for_logs->tm_mon + 1, structureTIME_for_logs->tm_year - 100 + 2000, structureTIME_for_logs->tm_hour, structureTIME_for_logs->tm_min, structureTIME_for_logs->tm_sec, exposure );
    // fprintf(stderr, "DEBUG02 form_DATEOBS_EXPTIME_log_output_from_JD()\n");
    form_DATEOBS_EXPTIME_log_output_from_JD( ( *JD ), exposure, NULL, NULL, log_output, finder_chart_timestring_output, 0 );
   } else {
    // somehting is messed up here - fallback to zeroes in the log file
    // sprintf( log_output, "exp_start= %02d.%02d.%4d %02d:%02d:%02d  exp= %4.0lf  ", 0, 0, 0, 0, 0, 0, exposure );
    sprintf( log_output, "exp_start= %02d.%02d.%4d %02d:%02d:%06.3lf  exp= %4.0lf  ", 0, 0, 0, 0, 0, 0.0, exposure );
   }
  }
  //
 }
 fits_close_file( fptr, &status ); // close file
 status= 0;
// fits_report_error( stderr, status ); // print out any error messages
#ifdef DEBUGMESSAGES
 fprintf( stderr, "finished   fits_close_file()\n" );
#endif

 // Do this only if the time system is UNKNOWN or UT!
 if ( ( *timesys ) == 0 || ( *timesys ) == 1 ) {
#ifdef DEBUGMESSAGES
  fprintf( stderr, "entering   if ( ( *timesys ) == 0 || ( *timesys ) == 1 )\n" );
#endif
  if ( param_verbose >= 1 ) {
#ifdef DEBUGMESSAGES
   fprintf( stderr, "entering   if ( param_verbose >= 1 )\n" );
#endif
   // Compute unix_time so we can convert the JD back to the broken-down time
   //(*JD) = (double)unix_time/3600.0/24.0+2440587.5+apply_JD_correction_in_days;
   // unix_time= (time_t)( ( ( *JD ) - 2440587.5 ) * 3600.0 * 24.0 + 0.5 );
   exposure= fabs( exposure );
   // form_DATEOBS_and_EXPTIME_from_UNIXSEC( unix_time, exposure, formed_str_DATEOBS, formed_str_EXPTIME );
   // fprintf(stderr, "DEBUG03 form_DATEOBS_EXPTIME_log_output_from_JD()\n");
   form_DATEOBS_EXPTIME_log_output_from_JD( ( *JD ), exposure, formed_str_DATEOBS, formed_str_EXPTIME, NULL, NULL, 0 );
   // #ifdef DEBUGMESSAGES
   //    fprintf( stderr, "\n\n\n\nunix_time=%ld\nexposure=%lf\nformed_str_DATEOBS=%s\nformed_str_EXPTIME=%s\n\n\n", unix_time, exposure, formed_str_DATEOBS, formed_str_EXPTIME );
   // #endif
   //
   if ( param_verbose == 2 ) {
#ifdef DEBUGMESSAGES
    fprintf( stderr, "entering   if ( param_verbose == 2 ) )\n" );
#endif
    // Update the FITS header
    write_DATEOBS_and_EXPTIME_to_FITS_header( fitsfilename, formed_str_DATEOBS, formed_str_EXPTIME );
   }
   //
  }
 }
#ifdef DEBUGMESSAGES
 fprintf( stderr, "gettime() ends\n" );
#endif
 return 0;
}
