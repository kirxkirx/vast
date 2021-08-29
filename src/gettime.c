#define _GNU_SOURCE // for memmem() in Kourovka_SBG_date_hack()

#define WARN_IF_TAImUTC_DAT_IS_OLDER_THAN_DAYS 5.0 * 365.242

#include <stdio.h>
#include <time.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#include "fitsio.h"
#include "vast_limits.h"

void write_DATEOBS_and_EXPTIME_to_FITS_header(char *fitsfilename, char *formed_str_DATEOBS, char *formed_str_EXPTIME) {
 fitsfile *fptr; /* FITS file pointer, defined in fitsio.h */
 char card[FLEN_CARD], newcard[FLEN_CARD];
 char oldvalue[FLEN_VALUE], comment[FLEN_COMMENT];
 int status= 0; /*  CFITSIO status value MUST be initialized to zero!  */
 int iomode, keytype;

 iomode= READWRITE;

 if( !fits_open_file(&fptr, fitsfilename, iomode, &status) ) {
  //////////////////// DATE-OBS ////////////////////
  if( fits_read_card(fptr, "DATE-OBS", card, &status) ) {
   fprintf(stderr, "Keyword %s does not exist in the header\n", "DATE-OBS");
   card[0]= '\0';
   comment[0]= '\0';
   status= 0; /* reset status after error */
  } else {
   // Save the old value
   fprintf(stderr, "%s\n", card);
   fprintf(stderr, "Saving this to OLD-OBS as a backup\n");
   if( *card )
    fits_parse_value(card, oldvalue, comment, &status);
   // construct template for new keyword
   strcpy(newcard, "OLD-OBS"); // keyword name
   strcat(newcard, " = ");     // '=' value delimiter
   strcat(newcard, oldvalue);  // new value
   if( *comment ) {
    strcat(newcard, " / ");   // comment delimiter
    strcat(newcard, comment); // append the comment
   }
   // reformat the keyword string to conform to FITS rules
   fits_parse_template(newcard, card, &keytype, &status);
   // overwrite the keyword with the new value
   fits_update_card(fptr, "OLD-OBS", card, &status);
  }
  // Write the new value of DATE-OBS
  // construct template for new keyword
  strcpy(newcard, "DATE-OBS");                                  // keyword name
  strcat(newcard, " = ");                                       // '=' value delimiter
  strcat(newcard, formed_str_DATEOBS);                          // new value
  strcat(newcard, " / ");                                       // comment delimiter
  strcat(newcard, "Exposure start time (UTC) derived by VaST"); // append the comment
  // reformat the keyword string to conform to FITS rules
  fits_parse_template(newcard, card, &keytype, &status);
  // overwrite the keyword with the new value
  fits_update_card(fptr, "DATE-OBS", card, &status);

  //////////////////// EXPTIME ////////////////////
  if( fits_read_card(fptr, "EXPTIME", card, &status) ) {
   fprintf(stderr, "Keyword %s does not exist in the header\n", "EXPTIME");
   card[0]= '\0';
   comment[0]= '\0';
   status= 0; /* reset status after error */
  } else {
   // Save the old value
   fprintf(stderr, "%s\n", card);
   fprintf(stderr, "Saving this to OLDTIME as a backup\n");
   if( *card )
    fits_parse_value(card, oldvalue, comment, &status);
   // construct template for new keyword
   strcpy(newcard, "OLDTIME"); // keyword name
   strcat(newcard, " = ");     // '=' value delimiter
   strcat(newcard, oldvalue);  // new value
   if( *comment ) {
    strcat(newcard, " / ");   // comment delimiter
    strcat(newcard, comment); // append the comment
   }
   // reformat the keyword string to conform to FITS rules
   fits_parse_template(newcard, card, &keytype, &status);
   // overwrite the keyword with the new value
   fits_update_card(fptr, "OLDTIME", card, &status);
  }
  // Write the new value of EXPTIME
  // construct template for new keyword
  strcpy(newcard, "EXPTIME");                             // keyword name
  strcat(newcard, " = ");                                 // '=' value delimiter
  strcat(newcard, formed_str_EXPTIME);                    // new value
  strcat(newcard, " / ");                                 // comment delimiter
  strcat(newcard, "Exposure time (sec) derived by VaST"); // append the comment
  // reformat the keyword string to conform to FITS rules
  fits_parse_template(newcard, card, &keytype, &status);
  // overwrite the keyword with the new value
  fits_update_card(fptr, "EXPTIME", card, &status);

  fits_close_file(fptr, &status);
 } // open_file

 // if error occured, print out error message
 if( status ) {
  fits_report_error(stderr, status);
 }

 return;
}

void form_DATEOBS_and_EXPTIME_from_UNIXSEC(time_t middle_of_exposure_unixsec, double exposure_sec, char *formed_str_DATEOBS, char *formed_str_EXPTIME) {
 time_t exposure_start_time_unixsec;
 struct tm *struct_tm_pointer;

 int year, month, day, hour, minute;
 double second;

 char output_str_DATEOBS[FLEN_CARD];
 char output_str_EXPTIME[FLEN_CARD];

 exposure_start_time_unixsec= middle_of_exposure_unixsec - (time_t)(exposure_sec / 2.0 + 0.5);

#if defined(_POSIX_C_SOURCE) || defined(_BSD_SOURCE) || defined(_SVID_SOURCE)
 struct_tm_pointer= malloc(sizeof(struct tm));
 gmtime_r(&exposure_start_time_unixsec, struct_tm_pointer);
#else
 struct_tm_pointer= gmtime(&exposure_start_time_unixsec);
#endif

 year= struct_tm_pointer->tm_year + 1900;
 month= struct_tm_pointer->tm_mon + 1;
 day= struct_tm_pointer->tm_mday;
 hour= struct_tm_pointer->tm_hour;
 minute= struct_tm_pointer->tm_min;
 second= (double)(struct_tm_pointer->tm_sec);

#if defined(_POSIX_C_SOURCE) || defined(_BSD_SOURCE) || defined(_SVID_SOURCE)
 free(struct_tm_pointer);
#endif

 // Note that we are not printing out fractions of the second!
 sprintf(output_str_DATEOBS, "%04d-%02d-%02dT%02d:%02d:%02.0lf", year, month, day, hour, minute, second);
 sprintf(output_str_EXPTIME, "%.0lf", exposure_sec);

 fprintf(stderr, "\nObserving time converted to the \"standard\" FITS header format:\nDATE-OBS= %s\nEXPTIME = %s\n\n", output_str_DATEOBS, output_str_EXPTIME);

 strncpy(formed_str_DATEOBS, output_str_DATEOBS, 80);
 strncpy(formed_str_EXPTIME, output_str_EXPTIME, 80);
 ///////////////

 return;
}

int Kourovka_SBG_date_hack(char *fitsfilename, char *DATEOBS, int *date_parsed, double *exposure) {
 // Kourovka-SBG camera images have a very unusual header.
 // This function is supposed to handle it.

 FILE *f;      // FITS file
 char *buffer; // buffer for a part of the header
 char *pointer_to_the_key_start;
 // char *pointer_to_the_key_end;
 int i; // counter
 char output_string[512];
 int day, month, year;
 int hour, minute;
 double second;
 double exp;
 char tmp[512];

 // allocate buffer
 buffer= malloc(65536 * sizeof(char));
 if( buffer == NULL ) {
  fprintf(stderr, "ERROR in Kourovka_SBG_date_hack(): cannot allocate buffer memory\n");
  return 1;
 }
 // read first part of the file to the buffer
 f= fopen(fitsfilename, "r");
 if( f == NULL ) {
  fprintf(stderr, "ERROR in Kourovka_SBG_date_hack(): cannot open file %s\n", fitsfilename);
  free(buffer);
  return 1;
 }
 for( i= 0; i < 65535; i++ ) {
  buffer[i]= getc(f);
  if( buffer[i] == EOF ) {
   break;
  }
 }
 fclose(f);
 // search for the substrings
 // date
 pointer_to_the_key_start= (char *)memmem(buffer, 65535 - 80, "Date      ", 10);
 if( pointer_to_the_key_start == NULL ) {
  fprintf(stderr, "ERROR in Kourovka_SBG_date_hack(): cannot find date\n");
  free(buffer);
  return 1;
 }
 (*(pointer_to_the_key_start + 79 * sizeof(char)))= '\0';
 sscanf(pointer_to_the_key_start, "Date                %d.%d.%d", &day, &month, &year);
 fprintf(stderr, "%s\n", pointer_to_the_key_start);
 // exposure
 //pointer_to_the_key_start=(char *)memmem( buffer, 65535-80, "ExpTime, . = ", 13);
 pointer_to_the_key_start= (char *)memmem(buffer, 65535 - 80, "ExpTime", 7);
 if( pointer_to_the_key_start == NULL ) {
  fprintf(stderr, "ERROR in Kourovka_SBG_date_hack(): cannot find exposure time\n");
  free(buffer);
  return 1;
 }
 (*(pointer_to_the_key_start + 79 * sizeof(char)))= '\0';
 sscanf(pointer_to_the_key_start, "ExpTime,%s = %lf", tmp, &exp);
 fprintf(stderr, "%s\n", pointer_to_the_key_start);
 // time
 pointer_to_the_key_start= (char *)memmem(buffer, 65535 - 80, "UTC1, h:m:s =", 13);
 if( pointer_to_the_key_start == NULL ) {
  fprintf(stderr, "ERROR in Kourovka_SBG_date_hack(): cannot find date\n");
  free(buffer);
  return 1;
 }
 (*(pointer_to_the_key_start + 79 * sizeof(char)))= '\0';
 sscanf(pointer_to_the_key_start, "UTC1, h:m:s =      %d:%d:%lf", &hour, &minute, &second);
 fprintf(stderr, "%s\n", pointer_to_the_key_start);

 sprintf(output_string, "%04d-%02d-%02dT%02d:%02d:%07.4lf", year, month, day, hour, minute, second);
 fprintf(stderr, "%s\nexposure = %.2lf\n", output_string, exp);
 free(buffer);

 if( day < 0 || day > 31 ) {
  fprintf(stderr, "ERROR in Kourovka_SBG_date_hack()\n");
  return 1;
 }
 if( month < 1 || month > 12 ) {
  fprintf(stderr, "ERROR in Kourovka_SBG_date_hack()\n");
  return 1;
 }
 if( year < 1950 || year > 2200 ) {
  fprintf(stderr, "ERROR in Kourovka_SBG_date_hack()\n");
  return 1;
 }
 if( hour < 0 || hour > 24 ) {
  fprintf(stderr, "ERROR in Kourovka_SBG_date_hack()\n");
  return 1;
 }
 if( minute < 0 || minute > 60 ) {
  fprintf(stderr, "ERROR in Kourovka_SBG_date_hack()\n");
  return 1;
 }
 if( second < 0.0 || second > 60.0 ) {
  fprintf(stderr, "ERROR in Kourovka_SBG_date_hack()\n");
  return 1;
 }

 if( exp < SHORTEST_EXPOSURE_SEC || exp > LONGEST_EXPOSURE_SEC ) {
  fprintf(stderr, "WARNING from Kourovka_SBG_date_hack(): cannot get exposure time from the image header!\nAssuming zero exposure time!\n");
  exp= 0.0;
 }

 strcpy(DATEOBS, output_string);
 (*date_parsed)= 1;
 (*exposure)= exp;

 return 0;
}

double convert_jdUT_to_jdTT(double jdUT, int *timesys) {
 FILE *tai_utc_dat;
 double jdTT;
 double *jd_leap_second;
 jd_leap_second= malloc(MAX_NUMBER_OF_LEAP_SECONDS * sizeof(double));
 if( jd_leap_second == NULL ) {
  fprintf(stderr, "ERROR: in convert_jdUT_to_jdTT() can't allocate memory for jd_leap_second\n");
  exit(1);
 }
 double *TAI_minus_UTC;
 TAI_minus_UTC= malloc(MAX_NUMBER_OF_LEAP_SECONDS * sizeof(double));
 if( TAI_minus_UTC == NULL ) {
  fprintf(stderr, "ERROR: in convert_jdUT_to_jdTT() can't allocate memory for TAI_minus_UTC\n");
  exit(1);
 }
 double tai_utc;
 char str1[256], str2[256];
 int i;
 int n_leap_sec= 0;

 double MJD= jdUT - 2400000.5; // for leap second calculation before 1972 JAN  1
 double *MJD0;
 MJD0= malloc(MAX_NUMBER_OF_LEAP_SECONDS * sizeof(double));
 if( MJD0 == NULL ) {
  fprintf(stderr, "ERROR: in convert_jdUT_to_jdTT() can't allocate memory for MJD0\n");
  exit(1);
 }
 double *leap_second_rate;
 leap_second_rate= malloc(MAX_NUMBER_OF_LEAP_SECONDS * sizeof(double));
 if( leap_second_rate == NULL ) {
  fprintf(stderr, "ERROR: in convert_jdUT_to_jdTT() can't allocate memory for leap_second_rate\n");
  exit(1);
 }

 /* 
   Read the file with leap seconds lib/tai-utc.dat
   up-to-date version of this file is available at 
   http://maia.usno.navy.mil/ser7/tai-utc.dat
 */
 tai_utc_dat= fopen("lib/tai-utc.dat", "r");
 if( NULL == tai_utc_dat ) {
  fprintf(stderr, "ERROR: can't open file lib/tai-utc.dat\n");
  exit(1);
 }
 while( NULL != fgets(str1, 256, tai_utc_dat) ) {
  for( i= 17; i < 26; i++ )
   str2[i - 17]= str1[i];
  str2[i - 17]= '\0';
  jd_leap_second[n_leap_sec]= atof(str2);
  for( i= 37; i < 48; i++ )
   str2[i - 37]= str1[i];
  str2[i - 37]= '\0';
  TAI_minus_UTC[n_leap_sec]= atof(str2);
  for( i= 60; i < 66; i++ )
   str2[i - 60]= str1[i];
  str2[i - 60]= '\0';
  MJD0[n_leap_sec]= atof(str2);
  for( i= 70; i < 79; i++ )
   str2[i - 70]= str1[i];
  str2[i - 70]= '\0';
  leap_second_rate[n_leap_sec]= atof(str2);
  n_leap_sec++;
 }
 fclose(tai_utc_dat);

 if( jdUT < jd_leap_second[0] )
  fprintf(stderr, "WARNING: TT is not defined before %.5lf\n", jd_leap_second[0]);

 tai_utc= TAI_minus_UTC[0];
 for( i= 1; i < n_leap_sec; i++ ) {
  if( jdUT >= jd_leap_second[i] ) {
   tai_utc= TAI_minus_UTC[i] + (MJD - MJD0[i]) * leap_second_rate[i]; //tai_utc=TAI_minus_UTC[i];
   //fprintf(stderr,"DEBUG: %02d TT-UTC=%.3lf \n",i,(32.184+tai_utc) );
  }
 }

 // Check that the input lib/tai-utc.dat file is not too old
 if( jdUT - jd_leap_second[n_leap_sec - 1] > WARN_IF_TAImUTC_DAT_IS_OLDER_THAN_DAYS ) {
  fprintf(stderr, "\nWARNING: the last record in lib/tai-utc.dat is more than %.0lf days old (JD%.1lf)!\n Please make sure the tai-utc.dat file is up to date by checking its latest version at http://maia.usno.navy.mil/ser7/tai-utc.dat\n\n", WARN_IF_TAImUTC_DAT_IS_OLDER_THAN_DAYS, jd_leap_second[n_leap_sec - 1]);
 }

 // Apply the leap seconds correction
 jdTT= jdUT + (32.184 + tai_utc) / 86400; // TT = TAI + 32.184
                                          // TAI = UTC + leap_seconds

 //fprintf(stderr,"DEBUG: TT-UTC=%.3lf \n",(32.184+tai_utc) );

 /* Set marker that time system was changed */
 (*timesys)= 2; // TT

 free(jd_leap_second);
 free(TAI_minus_UTC);
 free(MJD0);
 free(leap_second_rate);

 return jdTT;
}

/* We can't accept all these date writing options. but we'll try to handle some
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
void fix_DATEOBS_STRING(char *DATEOBS) {
 int i, j, date_part; // counters
 char substring_day[32];
 char substring_month[32];
 char substring_year[32];
 int day, month, year;

 // check if this is an empty string (and assume that the date will be provided as 'JD' keyword)
 if( 0 == strlen(DATEOBS) )
  return;

 // check if this is a normal '2004-07-05' style DATE-OBS
 for( i= 0; i < (int)strlen(DATEOBS); i++ )
  // if yes - do nothing
  if( DATEOBS[i] == '-' )
   return;

 // Parse '25/12/2011' style DATE-OBS
 for( i= 0, j= 0, date_part= 1; i < (int)strlen(DATEOBS); i++ ) {
  if( DATEOBS[i] == '/' ) {
   if( date_part == 1 )
    substring_day[j]= '\0';
   if( date_part == 2 )
    substring_month[j]= '\0';
   if( date_part == 3 )
    substring_year[j]= '\0';
   date_part++;
   j= 0;
   continue;
  }
  if( date_part == 1 ) {
   substring_day[j]= DATEOBS[i];
   j++;
  }
  if( date_part == 2 ) {
   substring_month[j]= DATEOBS[i];
   j++;
  }
  if( date_part == 3 ) {
   substring_year[j]= DATEOBS[i];
   j++;
  }
 }
 substring_year[4]= '\0';

 if( date_part == 1 ) {
  fprintf(stderr, "ERROR: cannot parse DATE-OBS keyword!\n");
  exit(1);
 }

 // Print result
 //fprintf(stderr,"_%s_ _%s_ _%s_   _%s_\n",substring_day,substring_month,substring_year,DATEOBS);
 day= atoi(substring_day);
 month= atoi(substring_month);
 year= atoi(substring_year);
 // try fix a two-digit year
 if( year<100 ) {
  fprintf(stderr, "WARNING -- two-digit year in the input DATEOBS string: %d -> ", year);
  if( year<50 ) {
   year= year + 2000;
  } else {
   year= year + 1900;
  }
  fprintf(stderr, "%d\n", year);
 }
 //
 // sprintf(DATEOBS,"%d-%02d-%02d",year,month,day);

 fprintf(stderr, "WARNING -- fixing the input DATEOBS string: %s -> ", DATEOBS);

 sprintf(DATEOBS, "%d-%02d-%02d", year, month, day);

 fprintf(stderr, "%s\n", DATEOBS);

 return;
}

// This function will handle '09-10-2017' style DATE-OBS
void fix_DATEOBS_STRING__DD_MM_YYYY_format(char *DATEOBS) {
 int i, j, date_part; // counters
 char substring_day[32];
 char substring_month[32];
 char substring_year[32];
 int day, month, year;

 //fprintf(stderr,"\n0123456789\n%s \n", DATEOBS);

 // check if this is an empty string (and assume that the date will be provided as 'JD' keyword)
 if( 0 == strlen(DATEOBS) ) {
  return;
 }
 //if( strlen(DATEOBS) < 8 ) {
 // we want to aslo handle a two-digit year 21-09-99
 if( strlen(DATEOBS) < 6 ) {
  // the string is too short for the following trick to work
  return;
 }


 //                            0123456789
 // check if this is a normal '2004-07-05' style DATE-OBS
 if( DATEOBS[4] == '-' ) {
  // special cases 1-09-99 and 01-9-1999
  if( DATEOBS[1] != '-' && DATEOBS[2] != '-' ) {
   return;
  }
 }

 for( i= 0; i < (int)strlen(DATEOBS); i++ )

  // Parse '09-10-2017' style DATE-OBS
  j= 0;
 date_part= 1;
 for( i= 0; i < (int)strlen(DATEOBS); i++ ) {
  if( DATEOBS[i] == '-' ) {
   if( date_part == 1 )
    substring_day[j]= '\0';
   if( date_part == 2 )
    substring_month[j]= '\0';
   if( date_part == 3 )
    substring_year[j]= '\0';
   date_part++;
   j= 0;
   continue;
  }
  if( date_part == 1 ) {
   substring_day[j]= DATEOBS[i];
   j++;
  }
  if( date_part == 2 ) {
   substring_month[j]= DATEOBS[i];
   j++;
  }
  if( date_part == 3 ) {
   substring_year[j]= DATEOBS[i];
   j++;
  }
 }
 substring_year[4]= '\0';

 if( date_part == 1 ) {
  fprintf(stderr, "ERROR: cannot parse DATE-OBS keyword!\n");
  exit(1);
 }

 // Print result
 //fprintf(stderr,"_%s_ _%s_ _%s_   _%s_\n",substring_day,substring_month,substring_year,DATEOBS);
 day= atoi(substring_day);
 month= atoi(substring_month);
 year= atoi(substring_year);
 // try fix a two-digit year
 if( year<100 ) {
  fprintf(stderr, "WARNING -- two-digit year in the input DATEOBS string: %d -> ", year);
  if( year<50 ) {
   year= year + 2000;
  } else {
   year= year + 1900;
  }
  fprintf(stderr, "%d\n", year);
 }
 //

 fprintf(stderr, "WARNING -- fixing the input DATEOBS string: %s -> ", DATEOBS);

 sprintf(DATEOBS, "%d-%02d-%02d", year, month, day);

 fprintf(stderr, "%s\n", DATEOBS);

 return;
}

// Determine if this is the image resampled to the defaut orientation (North up, East left)
// 1 - yes
// 0 - no
int check_if_this_fits_image_is_north_up_east_left(char *fitsfilename) {
 fitsfile *fptr; /* pointer to the FITS file; defined in fitsio.h */
 int status= 0;  //for cfitsio routines
 double CD1_1, CD1_2, CD2_1, CD2_2;

 fits_open_image(&fptr, fitsfilename, READONLY, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status); /* print out any error messages */
  fits_clear_errmsg();               // clear the CFITSIO error message stack
  return 0;                          // assume - no
 }

 fits_read_key(fptr, TDOUBLE, "CD1_1", &CD1_1, NULL, &status);
 if( status == 202 ) {
  fits_report_error(stderr, status);
  fits_clear_errmsg();            // clear the CFITSIO error message stack
  fits_close_file(fptr, &status); // close file
  status= 0;                      // just in case
  return 0;                       // assume - no
 }
 fits_read_key(fptr, TDOUBLE, "CD1_2", &CD1_2, NULL, &status);
 if( status == 202 ) {
  fits_report_error(stderr, status);
  fits_clear_errmsg();            // clear the CFITSIO error message stack
  fits_close_file(fptr, &status); // close file
  status= 0;                      // just in case
  return 0;                       // assume - no
 }
 fits_read_key(fptr, TDOUBLE, "CD2_1", &CD2_1, NULL, &status);
 if( status == 202 ) {
  fits_report_error(stderr, status);
  fits_clear_errmsg();            // clear the CFITSIO error message stack
  fits_close_file(fptr, &status); // close file
  status= 0;                      // just in case
  return 0;                       // assume - no
 }
 fits_read_key(fptr, TDOUBLE, "CD2_2", &CD2_2, NULL, &status);
 if( status == 202 ) {
  fits_report_error(stderr, status);
  fits_clear_errmsg();            // clear the CFITSIO error message stack
  fits_close_file(fptr, &status); // close file
  status= 0;                      // just in case
  return 0;                       // assume - no
 }

 // close the FITS file
 fits_report_error(stderr, status);
 fits_clear_errmsg();            // clear the CFITSIO error message stack
 fits_close_file(fptr, &status); // close file
 status= 0;                      // just in case

 // main test
 // WCS axes are paralloell to the image axes
 //if( CD1_2 == 0.0 && CD2_1 == 0.0 ) {
 // OK, let's allow for slight rotation
 if( fabs(CD1_2)/fabs(CD1_1)<0.1 && fabs(CD2_1)/fabs(CD2_2)<0.1 ) {
  // east left, north up
  if( CD1_1 < 0.0 && CD2_2 > 0.0 ) {
   return 1; // yes!!!!
  }
 } // if( CD1_2==0.0 && CD2_1==0.0 ){

 // by default
 return 0; // assume - no
}

int gettime(char *fitsfilename, double *JD, int *timesys, int convert_timesys_to_TT, double *dimX, double *dimY, char *stderr_output, char *log_output, int param_nojdkeyword, int param_verbose, char *finder_chart_timestring_output) {

 unsigned int counter_i;

 /* Variables for time */
 int status= 0; //for cfitsio routines
 int j;
 int jj;
 time_t unix_time;
 struct tm structureTIME;
 char Tm_h[10], Tm_m[10], Tm_s[FLEN_CARD]; // We want a lot of memeory for Tm_s for cases like '2020-11-21T18:10:43.4516245'
 char Da_y[10], Da_m[10], Da_d[10];

 char DATEOBS[32], TIMEOBS[32], TIMESYS[32];
 char DATEOBS_COMMENT[2048];  // make it long, just in case
 char EXPOSURE_COMMENT[2048]; // make it long, just in case
 char tymesys_str_in[32];
 char tymesys_str_out[32];
 double inJD= 0.0;
 double endJD= 0.0; // for paring the Siril-style EXPSTART/EXPEND keywords

 /* fitsio */
 fitsfile *fptr; /* pointer to the FITS file; defined in fitsio.h */
 //long  fpixel = 1, naxis = 2, nelements;//, exposure;
 double exposure= 0.0; // if exposure != 0.0 -- assuming we have correctly read it
 /*End of time variables */
 long naxes[2];

 // LOG-files
 //FILE *vast_image_details;

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

 char telescop[FLEN_CARD];

 char DATEOBS_KEY_NAME[32];
 char TIMEOBS_KEY_NAME[32];


 char formed_str_DATEOBS[FLEN_CARD];
 char formed_str_EXPTIME[FLEN_CARD];
 memset( formed_str_DATEOBS, 0, FLEN_CARD );
 memset( formed_str_EXPTIME, 0, FLEN_CARD );
 //

 memset( telescop, 0, FLEN_CARD );

 //DATEOBS_KEY_NAME[0]='\0';
 //TIMEOBS_KEY_NAME[0]='\0';
 memset(DATEOBS_KEY_NAME, 0, 32);
 memset(TIMEOBS_KEY_NAME, 0, 32);

 //char DATEOBS[32], TIMEOBS[32], TIMESYS[32];
 //char DATEOBS_COMMENT[2048]; // make it long, just in case
 memset(DATEOBS, 0, 32);
 memset(TIMEOBS, 0, 32);
 memset(TIMESYS, 0, 32);
 memset(DATEOBS_COMMENT, 0, 2048);
 memset(EXPOSURE_COMMENT, 0, 2048);

 if( param_verbose >= 1 )
  fprintf(stderr, "Processing  %s\n", fitsfilename);

 // See if the input image is listed in the time corrections file vast_list_of_input_images_with_time_corrections.txt
 vast_list_of_input_images_with_time_corrections= fopen("vast_list_of_input_images_with_time_corrections.txt", "r");
 // Check if we can open the file
 if( NULL != vast_list_of_input_images_with_time_corrections ) {
  // Possibe buffer overflow here beacuse of fscanf(..., "%s", ...), but I feel lucky
  while( 2 == fscanf(vast_list_of_input_images_with_time_corrections, "%s %lf", image_filename_from_input_list, &image_date_correction_from_input_list) ) {
   // Check if the listed one is the same image we process now
   if( 0 == strncmp(image_filename_from_input_list, fitsfilename, FILENAME_LENGTH) ) {
    if( fabs(image_date_correction_from_input_list) < EXPECTED_MIN_JD ) {
     // Assume this is the time correction in seconds we need to apply to this image
     apply_JD_correction_in_days= image_date_correction_from_input_list / 86400.0;
     if( param_verbose >= 1 )
      fprintf(stderr, "JD correction of %.6lf days (%.2lf seconds) will be applied!\n", apply_JD_correction_in_days, image_date_correction_from_input_list);
    } else {
     // Assume this is the full JD in days
     if( fabs(image_date_correction_from_input_list) < EXPECTED_MAX_JD ) {
      overridingJD_from_input_image_list= image_date_correction_from_input_list;
      if( param_verbose >= 1 )
       fprintf(stderr, "WARNING: overriding the time deterrmined from FITS header with JD%.5lf as specified in vast_list_of_input_images_with_time_corrections.txt !\n", overridingJD_from_input_image_list);
     }
    }
    break; // don't process the remaining images, we have the right one
   }       // if same image
  }        // while()
  fclose(vast_list_of_input_images_with_time_corrections);
 }

 //

 /* Extract data from fits header */
 //fits_open_file(&fptr, fitsfilename, READONLY, &status);
 fits_open_image(&fptr, fitsfilename, READONLY, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status); /* print out any error messages */
  fits_clear_errmsg();               // clear the CFITSIO error message stack
  return status;
 }

 // Get image dimentions
 fits_read_key(fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status);
  fits_clear_errmsg();            // clear the CFITSIO error message stack
  fits_close_file(fptr, &status); // close file
  fprintf(stderr, "ERROR: gettime() - can't get image dimensions from NAXIS1 keyword!\n");
  return status;
 }
 fits_read_key(fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status);
  fits_clear_errmsg();            // clear the CFITSIO error message stack
  fits_close_file(fptr, &status); // close file
  fprintf(stderr, "ERROR: gettime() - can't get image dimensions from NAXIS2 keyword!\n");
  return status;
 }

 // Get the telescope name - we may recognize some and modify the behaviour
 fits_read_key(fptr, TSTRING, "TELESCOP", telescop, NULL, &status);
 if( status != 0 ) {
  telescop[0]= '\0';
 }
 status= 0;

 // Close the FITS file and re-open it with fits_open_file() instead of fits_open_image()
 // as the observing date information may be in a different HDU than the image!
 fits_close_file(fptr, &status); // close file
 if( 0 != status ) {
  fits_report_error(stderr, status); // print out any error messages
  fits_clear_errmsg();               // clear the CFITSIO error message stack
  return status;
 }
 fits_open_file(&fptr, fitsfilename, READONLY, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status); // print out any error messages
  fits_clear_errmsg();               // clear the CFITSIO error message stack
  return status;
 }

 // Moved here as we may need the exposure time to set time using UT-END
 // if exposure!=0.0 we assume it was set earlier by Kourovka_SBG_date_hack()
 if( exposure == 0.0 ) {
  fits_read_key(fptr, TDOUBLE, "EXPTIME", &exposure, EXPOSURE_COMMENT, &status);
  if( status == 202 ) {
   status= 0;
   if( param_verbose >= 1 )
    fprintf(stderr, "Looking for exposure in EXPOSURE \n");
   fits_read_key(fptr, TDOUBLE, "EXPOSURE", &exposure, EXPOSURE_COMMENT, &status);
   if( status == 202 ) {
    status= 0;
    if( param_verbose >= 1 )
     fprintf(stderr, "Looking for exposure in TM-EXPOS \n");
    fits_read_key(fptr, TDOUBLE, "TM-EXPOS", &exposure, EXPOSURE_COMMENT, &status);
    if( status == 202 ) {
     if( param_verbose >= 1 )
      fprintf(stderr, "I can't find a keyword with exposure time! ;(     assuming EXPTIME=0\n");
     exposure= 0.0;
     status= 0;
    }
   }
  }
  fits_report_error(stderr, status); /* print out any error messages */
  fits_clear_errmsg();               // clear the CFITSIO error message stack
  // Try to parse the exposure keyword comment and handle the situation when the exposure is not expressed in seconds
  //
  EXPOSURE_COMMENT[2048 - 1]= '\0'; // just in case
  if( strlen(EXPOSURE_COMMENT) > 8 ) {
   if( NULL == strstr(EXPOSURE_COMMENT, "Seconds") && NULL == strstr(EXPOSURE_COMMENT, "seconds") ) {
    // here we should use case rather than multiple ifs?
    if( NULL != strstr(EXPOSURE_COMMENT, "Minutes") ) {
     exposure= 60.0 * exposure;
    }
    if( NULL != strstr(EXPOSURE_COMMENT, "minutes") ) {
     exposure= 60.0 * exposure;
    }
    if( NULL != strstr(EXPOSURE_COMMENT, "Hours") ) {
     exposure= 3600.0 * exposure;
    }
    if( NULL != strstr(EXPOSURE_COMMENT, "hours") ) {
     exposure= 3600.0 * exposure;
    }
   }
  }
  //
 } // if( exposure!=0.0 ){

 if( exposure < SHORTEST_EXPOSURE_SEC || exposure > LONGEST_EXPOSURE_SEC ) {
  if( param_verbose >= 1 )
   fprintf(stderr, "WARNING: exposure time %lf is out of range (%.0lf,%.0lf)\nAssuming ZERO exposure time!\n", exposure, SHORTEST_EXPOSURE_SEC, LONGEST_EXPOSURE_SEC);
  exposure= 0.0;
 }

 // Special case: we want to always use SHUTOPEN instead of DATE-OBS for ZTF images, even if DATE-OBS is present
 fits_read_key(fptr, TSTRING, "SHUTOPEN", DATEOBS, DATEOBS_COMMENT, &status);
 if( status == 0 ) {
  if( param_nojdkeyword == 1 ) {
   fprintf(stderr, "WARNING: cannot ignore both 'JD' and 'DATE-OBS' keywords! Will allow use of 'JD' keyword. \n");
  }
  fprintf(stderr, "WARNING: ignoring 'DATE-OBS' keyword as 'SHUTOPEN' is present.\n");
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
 if( param_nojdkeyword==2 ) {
  status=202;
 } else {
  fits_read_key(fptr, TSTRING, "DATE-OBS", DATEOBS, DATEOBS_COMMENT, &status);
 }
 if( status == 0 ) {
  // The first type of images
  fits_read_key(fptr, TSTRING, "TU-START", DATEOBS, DATEOBS_COMMENT, &status);
  if( status == 0 ) {
   fits_read_key(fptr, TSTRING, "TU-END", DATEOBS, DATEOBS_COMMENT, &status);
   if( status == 0 ) {
    is_this_an_EROS_image= 1;
   } //TU-END
  }  // TU-START
  if( is_this_an_EROS_image == 0 ) {
   // The second type of images
   fits_clear_errmsg(); // clear the CFITSIO error message stack
   status= 0;
   fits_read_key(fptr, TSTRING, "TM-EXPOS", DATEOBS, DATEOBS_COMMENT, &status);
   if( status == 0 ) {
    fits_read_key(fptr, TSTRING, "FILTREF", DATEOBS, DATEOBS_COMMENT, &status);
    if( status == 0 ) {
     is_this_an_EROS_image= 1;
    } // FILTREF
   }  // TM-EXPOS
  }   // if( is_this_an_EROS_image==0 ){
 }    // DATE-OBS
 // conclusion
 if( is_this_an_EROS_image == 1 ) {
  if( param_verbose >= 1 )
   fprintf(stderr, "WARNING: assuming DATE-OBS corresponds to the middle of exposure!\nSetting exposure time to zero in order not to introduce the middle-of-exposure correction twice.\n");
  exposure= 0.0;
 }
 // cleanup
 memset(DATEOBS, 0, 32);
 memset(DATEOBS_COMMENT, 0, 2048);
 fits_clear_errmsg(); // clear the CFITSIO error message stack
 status= 0;
 // end of cleanup

 DATEOBS_COMMENT[0]= '\0'; // just in case
 // check if we are allowed to use JD keyword
 if( param_nojdkeyword==2 ) {
  status=202;
 } else {
  fits_read_key(fptr, TSTRING, "DATE-OBS", DATEOBS, DATEOBS_COMMENT, &status);
 }
 if( status == 0 ) {
  date_parsed= 1;
  strncpy(DATEOBS_KEY_NAME, "DATE-OBS", 9);
 }
 DATEOBS_COMMENT[FLEN_CARD-1]= '\0'; // just in case

 // Handle the case that DATE-OBS is present, but EMPTY
 if( 0 == strlen(DATEOBS) && status == 0 ) {
  fprintf(stderr, "WARNING from gettime(): DATE-OBS keyword is present in the header but is empty!\n");
  status= 202; // act if the keyword is not present at all
 }

 if( status == 202 ) {
  // if DATE-OBS does not exist, try DATE-BEG
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  status= 0;
  fits_read_key(fptr, TSTRING, "DATE-BEG", DATEOBS, DATEOBS_COMMENT, &status);
  if( status == 0 ) {
   date_parsed= 1;
   strncpy(DATEOBS_KEY_NAME, "DATE-BEG", 9);
  }
  DATEOBS_COMMENT[FLEN_CARD-1]= '\0'; // just in case
 }

 if( status == 202 ) {
  // if DATE-OBS and DATE-BEG do not exist, try DATE-EXP
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  status= 0;
  fits_read_key(fptr, TSTRING, "DATE-EXP", DATEOBS, DATEOBS_COMMENT, &status);
  if( status == 0 ) {
   date_parsed= 1;
   strncpy(DATEOBS_KEY_NAME, "DATE-EXP", 9);
  }
  DATEOBS_COMMENT[FLEN_CARD-1]= '\0'; // just in case
 }

 // SHUTOPEN is in ZTF images
 if( status == 202 ) {
  // if DATE-OBS, DATE-BEG, DATE-EXP do not exist, try SHUTOPEN
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  status= 0;
  fits_read_key(fptr, TSTRING, "SHUTOPEN", DATEOBS, DATEOBS_COMMENT, &status);
  if( status == 0 ) {
   date_parsed= 1;
   strncpy(DATEOBS_KEY_NAME, "SHUTOPEN", 9);
  }
  DATEOBS_COMMENT[FLEN_CARD-1]= '\0'; // just in case
 }

 // If both EXPSTART and EXPEND keywords are present - we want to use them instead of DATE-OBS and EXPTIME
 int status_before_EXPSTART_EXPEND_test= status;
 fits_read_key(fptr, TDOUBLE, "EXPSTART", &inJD, NULL, &status);
 if( status == 0 ) {
  fits_read_key(fptr, TDOUBLE, "EXPEND", &inJD, NULL, &status);
  if( status == 0 ) {
   fprintf(stderr, "Both EXPSTART and EXPEND keywords are present - will use them instead of DATE-OBS\n");
   DATEOBS[0]= '\0';
   date_parsed= 0; // we will get the date later
   //status= 202; // seems unnecessary
  }
 }
 status= status_before_EXPSTART_EXPEND_test;

 // if DATE-OBS, DATE-BEG, DATE-EXP and SHUTOPEN do not exist at all, try DATE
 if( status == 202 ) {
  date_parsed= 0;
  if( param_verbose >= 1 ) {
   fprintf(stderr, "WARNING: DATE-OBS keyword not found, trying DATE...\n");
  }
  fits_clear_errmsg(); // clear the CFITSIO error message stack
  status= 0;
  // Trying to get the observing date from DATE is realy the last resort
  //fits_read_key(fptr, TSTRING, "DATE", DATEOBS, DATEOBS_COMMENT, &status);
  fits_read_key(fptr, TSTRING, "DATE", DATEOBS, NULL, &status); // do not modify DATEOBS_COMMENT
  if( status == 0 ) {
   date_parsed= 1; // We may be fine (but see the warning below)
   // This is a trick: if there are other date-related keywords in the header - DO NOT take the observing date from DATE keyword
   fits_read_key(fptr, TDOUBLE, "JD", &inJD, NULL, &status);
   if( status == 0 ) {
    //strncpy(DATEOBS,"",2);
    DATEOBS[0]= '\0';
    date_parsed= 0; // we will get the date later
   }
   fits_read_key(fptr, TDOUBLE, "JDMID", &inJD, NULL, &status);
   if( status == 0 ) {
    //strncpy(DATEOBS,"",2);
    DATEOBS[0]= '\0';
    date_parsed= 0; // we will get the date later
   }
   fits_read_key(fptr, TDOUBLE, "MJD-OBS", &inJD, NULL, &status);
   if( status == 0 ) {
    //strncpy(DATEOBS,"",2);
    DATEOBS[0]= '\0';
    date_parsed= 0; // we will get the date later
   }
   // Do not look at EXPSTART if the image is from Aristarchos telescope!
   if( 0 != strncmp(telescop, "Aristarchos", 11) ) {
    fits_clear_errmsg(); // clear the CFITSIO error message stack
    status= 0;
    fits_read_key(fptr, TDOUBLE, "EXPSTART", &inJD, NULL, &status);
    if( status == 0 ) {
     // We will parse the EXPSTART date later,
     // here we just need to mark that we are not using DATE keyword to get the observing date/time
     DATEOBS[0]= '\0';
     date_parsed= 0; // we will get the date later
    }
   }
   fits_clear_errmsg(); // clear the CFITSIO error message stack
   status= 0;
   //
   if( param_verbose >= 1 && date_parsed == 1 ) {
    fprintf(stderr, "\n***** WARNING! WARNING! WARNING! *****\n VaST is getting observing date from DATE keyword.\n This is usually the WRONG thing to do since this keyword typically contains the FITS file creation date rather than observing date.\n Ignore this warning only if you are absolutely sure that your images have observation start date written in DATE keyword.\n\n");
    strcpy(DATEOBS_KEY_NAME, "DATE");
   }
  }
 }
 if( strlen(DATEOBS) < 11 && strlen(DATEOBS) > 1 && date_parsed == 1 ) {
  fix_DATEOBS_STRING(DATEOBS);                    // handle '25/12/2011' style DATE-OBS
  fix_DATEOBS_STRING__DD_MM_YYYY_format(DATEOBS); // handle '09-10-2017' style DATE-OBS
  fits_read_key(fptr, TSTRING, "TIME-OBS", TIMEOBS, NULL, &status);
  if( 0 == strcmp(TIMEOBS, "") ) {
   fits_clear_errmsg(); // clear the CFITSIO error message stack
   status= 0;           // guess need to set it here or the folowing  FITSIO request will not pass
   if( param_verbose >= 1 )
    fprintf(stderr, "Looking for time of observation in START keyword (its format is assumed to be similar to TIME-OBS keyword)\n");
   fits_read_key(fptr, TSTRING, "START   ", TIMEOBS, NULL, &status);
   status= 0; // need to set it here or the folowing  FITSIO request will not pass
   //if (0 == strcmp(TIMEOBS, "")) {
   if( 0 == strlen(TIMEOBS) ) {
    if( param_verbose >= 1 )
     fprintf(stderr, "Looking for time of observation in UT-START keyword (its format is assumed to be similar to TIME-OBS keyword)\n");
    status= 0;
    fits_read_key(fptr, TSTRING, "UT-START", TIMEOBS, NULL, &status);
    // Special trick for Aristarchos that somethimes doesn't have UT-START, but does have UT-END
    //fprintf(stderr,"\n\n\n\n\nDEBUGISHE TIMEOBS=#%s#\n\n\n\n\n",TIMEOBS);
    if( 0 == strncmp(TIMEOBS, "NIL", 3) ) {
     fprintf(stderr, "Oh, this looks like the Aristarchos telescope header with invalid UT-START!\nWill try to see if there is UT-END?\n");
     status= 0;
     fits_read_key(fptr, TSTRING, "UT-END", TIMEOBS, NULL, &status);
     if( status == 0 ) {
      fprintf(stderr, "Yes, found UT-END\n");
      if( 0 != strncmp(TIMEOBS, "NIL", 3) ) {
       strcpy(TIMEOBS_KEY_NAME, "UT-END");
       exposure= (-1.0) * exposure;
       fprintf(stderr, "Yes, the UT-END value is not obviously empty!\nSetting the negative exposure time = %lf sec\n", exposure);
      } else {
       fprintf(stderr, "Oh, it's empty: UT-END=%s\n", TIMEOBS);
       TIMEOBS[0]= '\0';
      }
     }
    }
    //
    //if (0 == strcmp(TIMEOBS, "")){
    if( 0 == strlen(TIMEOBS) ) {
     fprintf(stderr, "WARNING! Cannot get proper observing time from FITS header! Assuming it will be provided as JD keyword...\n");
     date_parsed= 0; // Mark that we were unable to parse the date yet
    } else {
     if( 0 != strncmp(TIMEOBS_KEY_NAME, "UT-END", 6) ) {
      strcpy(TIMEOBS_KEY_NAME, "UT-START");
     }
    }
   } else {
    strcpy(TIMEOBS_KEY_NAME, "START");
   }
  } else {
   strcpy(TIMEOBS_KEY_NAME, "TIME-OBS");
  }
  status= 0;
 } // if( strlen(DATEOBS)<11 && strlen(DATEOBS)>1 && date_parsed==1 ){

 // EXPOSURE STUFF WAS HERE

 /*
        if( param_get_start_time_instead_of_midexp==1 ){
         if(param_verbose==1)fprintf(stderr,"WARNING: setting exposure time to 0 as the exposure start time is requested instead of middle of exposure time!\n");
         exposure=0.0;
        }
        */

 /////// Look for EXPSTART keyword containing MJD (a convention used for HST images in the HLA) ///////
 /////// The other possibility we test for here is EXPSTART/EXPEND keywords containing JD (a convention used by Siril) ///////
 status= 0;
 if( date_parsed == 0 ) {
  fprintf(stderr, "Trying to get observing start MJD from EXPSTART keyword...\n");
  fits_read_key(fptr, TDOUBLE, "EXPSTART", &inJD, NULL, &status);
  if( status != 202 ) {
   fprintf(stderr, "Getting the observing time of the exposure start from EXPSTART keyword: %.5lf\n", inJD);
   if( EXPECTED_MIN_MJD < inJD && inJD < EXPECTED_MAX_MJD ) {
    fprintf(stderr, "Based on the numerical value, we think EXPSTART contains MJD\nUsing EXPSTART+EXPTIME/2 as the middle of exposure\n");
    inJD= inJD + 2400000.5;
    fprintf(stderr, "Got observation time parameters: JD_start= %.5lf  exptime= %.1lf sec\n", inJD, exposure);
    inJD= inJD + exposure / 86400.0 / 2.0;
    //date_parsed=1;
    expstart_mjd_parsed= 1;
   } else {
    // check if the value looks like a JD
    if( EXPECTED_MIN_JD < inJD && inJD < EXPECTED_MAX_JD ) {
     fits_read_key(fptr, TDOUBLE, "EXPEND", &endJD, NULL, &status);
     if( status != 202 ) {
      if( EXPECTED_MIN_JD < endJD && endJD < EXPECTED_MAX_JD ) {
       fprintf(stderr, "Setting the middle of exposure time based on EXPSTART and EXPEND keywords.\n");
       fprintf(stderr, "Got observation time parameters: JD_start= %.5lf  JD_end= %.5lf  exptime= %.1lf sec\n", inJD, endJD, exposure);
       inJD= (inJD + endJD) / 2.0;
       expstart_mjd_parsed= 1;
      } else {
       fprintf(stderr, "JD derived from EXPEND keyword %.5lf is out of the expected range (%.5lf,%.5lf)!\n", endJD, EXPECTED_MIN_JD, EXPECTED_MAX_JD);
       fprintf(stderr, "Got observation time parameters: JD_start= %.5lf  exptime= %.1lf sec\n", inJD, exposure);
       inJD= inJD + exposure / 86400.0 / 2.0;
       expstart_mjd_parsed= 1;
      } // else if ( EXPECTED_MIN_JD < inJD && inJD < EXPECTED_MAX_JD ) {
     } else {
      // no EXPEND keyword
      fprintf(stderr, "No EXPEND keyword\n");
      fprintf(stderr, "Got observation time parameters: JD_start= %.5lf  exptime= %.1lf sec\n", inJD, exposure);
      inJD= inJD + exposure / 86400.0 / 2.0;
      expstart_mjd_parsed= 1;
     } // else if ( status != 202 ) {
     status= 0;
    } else {
     fprintf(stderr, "WARNING: the value %lf infered from EXPSTART keyword is outside the expected MJD range (%.0lf,%.0lf).\n", inJD, EXPECTED_MIN_MJD, EXPECTED_MAX_MJD);
    } // else if ( EXPECTED_MIN_JD < inJD && inJD < EXPECTED_MAX_JD ) {
   }  // else if ( EXPECTED_MIN_MJD < inJD && inJD < EXPECTED_MAX_MJD ) {
  }   // if ( status != 202 ) {
 }    // if ( date_parsed == 0 ) {

 /////// Look for JD keyword (a convention used for Moscow photographic plate scans) ///////
 status= 0;
 // param_nojdkeyword==1 tells us that JD keyword should be ignored
 // date_parsed==0 means DATE-OBS was not found and parsed
 if( param_nojdkeyword == 0 && date_parsed == 0 && expstart_mjd_parsed == 0 ) {
#ifdef DEBUGMESSAGES
  fprintf(stderr, "entering   if ( param_nojdkeyword == 0 && date_parsed == 0 && expstart_mjd_parsed == 0 )\n");
#endif

  exposure= 0.0; // Assume JD keyword corresponds to the middle of exposure!!!
  fprintf(stderr, "Trying to get observing date from JD keyword...\n");
  fits_read_key(fptr, TDOUBLE, "JD", &inJD, NULL, &status);
  //fprintf(stderr,"DEBUG: status = %d\n",status);
  if( status == 0 ) {
#ifdef DEBUGMESSAGES
   fprintf(stderr, "entering   if ( status == 0 )\n");
#endif
   fprintf(stderr, "Getting JD of the middle of exposure from JD keyword: %.5lf\n", inJD);
   // Check that JD is within the reasonable range
   if( inJD < EXPECTED_MIN_JD || inJD > EXPECTED_MAX_JD ) {
    fprintf(stderr, "ERROR: JD %lf is out of expected range (%.1lf, %.1lf)!\nYou may change EXPECTED_MIN_JD and EXPECTED_MAX_JD in src/vast_limits.h and recompile VaST if you are _really sure_ you know what you are doing...\n", inJD, EXPECTED_MIN_JD, EXPECTED_MAX_JD);
    exit(1);
   }
  } else {
#ifdef DEBUGMESSAGES
   fprintf(stderr, "entering  else corresponding to if ( status == 0 )\n");
#endif
   status= 0; // reset
   fprintf(stderr, "Trying to get observing date from JDMID keyword...\n");
   fits_read_key(fptr, TDOUBLE, "JDMID", &inJD, NULL, &status);
   if( status == 0 ) {
#ifdef DEBUGMESSAGES
    fprintf(stderr, "entering  if ( status == 0 )\n");
#endif
    fprintf(stderr, "Getting JD of the middle of exposure from JDMID keyword: %.5lf\n", inJD);
    // Check that JD is within the reasonable range
    if( inJD < EXPECTED_MIN_JD || inJD > EXPECTED_MAX_JD ) {
     fprintf(stderr, "ERROR: JD %lf is out of expected range (%.1lf, %.1lf)!\nYou may change EXPECTED_MIN_JD and EXPECTED_MAX_JD in src/vast_limits.h and recompile VaST if you are _really sure_ you know what you are doing...\n", inJD, EXPECTED_MIN_JD, EXPECTED_MAX_JD);
     exit(1);
    }
   } else {
    // MJD-OBS
    status= 0; // reset
    fprintf(stderr, "Trying to get observing date from MJD-OBS keyword...\n");
    fits_read_key(fptr, TDOUBLE, "MJD-OBS", &inJD, NULL, &status);
    if( status == 0 ) {
     fprintf(stderr, "Getting MJD of the middle of exposure from MJD-OBS keyword: %.5lf\n", inJD);
     // Check that MJD is within the reasonable range
     if( inJD < EXPECTED_MIN_MJD || inJD > EXPECTED_MAX_MJD ) {
      fprintf(stderr, "ERROR: MJD %lf is out of expected range (%.1lf, %.1lf)!\nYou may change EXPECTED_MIN_MJD and EXPECTED_MAX_MJD in src/vast_limits.h and recompile VaST if you are _really sure_ you know what you are doing...\n", inJD, EXPECTED_MIN_MJD, EXPECTED_MAX_MJD);
      exit(1);
     }
     inJD= inJD + 2400000.5; // convert MJD to JD
     // Check that JD is within the reasonable range
     if( inJD < EXPECTED_MIN_JD || inJD > EXPECTED_MAX_JD ) {
      fprintf(stderr, "ERROR: JD %lf is out of expected range (%.1lf, %.1lf)!\nYou may change EXPECTED_MIN_JD and EXPECTED_MAX_JD in src/vast_limits.h and recompile VaST if you are _really sure_ you know what you are doing...\n", inJD, EXPECTED_MIN_JD, EXPECTED_MAX_JD);
      exit(1);
     }
    } // if( status == 0 ) { for MJD-OBS
   } // else for JDMID keyword
  } // else for JD keyword
  if( status != 0 ) {
#ifdef DEBUGMESSAGES
   fprintf(stderr, "entering  if ( status != 0 )\n");
#endif
   // Testing if this is the mad header from Kourovka SBG?
   status= 0;
   fprintf(stderr, "Testing if this is an image from Kourovka SBG camera...\n");
   status= Kourovka_SBG_date_hack(fitsfilename, DATEOBS, &date_parsed, &exposure);
   if( status != 0 ) {
#ifdef DEBUGMESSAGES
    fprintf(stderr, "entering  if ( status != 0 )\n");
#endif
    date_parsed= 0; // if Kourovka_SBG_date_hack() failed...
    //fprintf(stderr, "No, it's not.\nWARNING: cannot determine date/time associated with this image!\n");
    fprintf(stderr, "No, it's not a Kourovka SBG camera image.\n \E[01;31m WARNING: cannot determine date/time associated with this image! \E[33;00m \n");
    // Special case - no date information in the image file
    inJD= 0.0;
    status= 0;
   } else {
#ifdef DEBUGMESSAGES
    fprintf(stderr, "entering  else corresponding to if ( status != 0 )\n");
#endif
    fprintf(stderr, "Yes this is an image from Kourovka SBG camera! start=%s exp=%.1lf parsing_flag=%d\n", DATEOBS, exposure, date_parsed);
   }
  }
 } else {
#ifdef DEBUGMESSAGES
  fprintf(stderr, "entering  else corresponding to if ( param_nojdkeyword == 0 && date_parsed == 0 && expstart_mjd_parsed == 0 ) {\n");
#endif
  status= 202; // proceed parsing the DATE string
  if( param_nojdkeyword == 1 && date_parsed == 0 ) {
#ifdef DEBUGMESSAGES
   fprintf(stderr, "entering  if ( param_nojdkeyword == 1 && date_parsed == 0 )\n");
#endif
   // Special case - no date information in the image file (and we are not allowed to use JD keyword, no matter if it's there or not)
   inJD= 0.0;
   status= 0;
  }
 }

#ifdef DEBUGMESSAGES
 fprintf(stderr, "debug checkpoint 01\n");
#endif

 (*dimX)= naxes[0];
 (*dimY)= naxes[1];

 // Initiallize just in case
 memset( Tm_h, 0, 10 );
 memset( Tm_m, 0, 10 );
 memset( Tm_s, 0, FLEN_CARD );
 memset( Da_y, 0, 10 );
 memset( Da_m, 0, 10 );
 memset( Da_d, 0, 10 );
 //

 // status==202 here means the JD keyword is not found
 // date_parsed==0 means DATE-OBS was not found and parsed
 if( status == 202 && date_parsed != 0 && expstart_mjd_parsed == 0 ) {
#ifdef DEBUGMESSAGES
  fprintf(stderr, "entering  if ( status == 202 && date_parsed != 0 && expstart_mjd_parsed == 0 )\n");
#endif
  //if (status == 202) {
  /* If no JD keyword was found... */

  /* 
	       Try to guess time system (UTC or TT).
	       Look for TIMESYS keyword, if it is not found 
	       - try to parse DATE-OBS comment.
	     */
  status= 0;
  fits_read_key(fptr, TSTRING, "TIMESYS", TIMESYS, NULL, &status);
  if( status != 202 ) {
#ifdef DEBUGMESSAGES
   fprintf(stderr, "entering  if ( status != 202 )\n");
#endif
   // TIMESYS keyword found
   if( param_verbose >= 1 )
    fprintf(stderr, "TIMESYS keyword found: %s\n", TIMESYS);
   if( TIMESYS[0] == 'T' && TIMESYS[1] == 'T' )
    (*timesys)= 2; // TT
   else if( TIMESYS[0] == 'U' && TIMESYS[1] == 'T' )
    (*timesys)= 1; // UT
   else
    (*timesys)= 0; // UNKNOWN
  } else {
#ifdef DEBUGMESSAGES
   fprintf(stderr, "entering  else corresponding to if ( status != 202 )\n");
#endif
   // Here we assume that TT system can be only set from TIMESYS keyword.
   // If it's not there - the only temaing options are UTC or UNKNOWN

   // TIMESYS keyword not found, try to parse DATE-OBS comment string
   if( param_verbose >= 1 ) {
    fprintf(stderr, "TIMESYS keyword is not in the FITS header.\n");
   }
   // Make sure the string is not empty
   if( strlen(DATEOBS_COMMENT) > 1 ) {
    if( param_verbose >= 1 )
     fprintf(stderr, "Trying to guess the time system by parsing the comment string '%s'\n", DATEOBS_COMMENT);
    // don't start from 0 - if there is no comment, the string will contain 0 characters before \0 !
    for( j= 1; j < (int)strlen(DATEOBS_COMMENT) - 1; j++ ) {
     if( DATEOBS_COMMENT[j] == 'U' && DATEOBS_COMMENT[j + 1] == 'T' ) {
      (*timesys)= 1; // UT
      if( param_verbose >= 1 )
       fprintf(stderr, "Time system set from the comment to DATE-OBS keyword: '%s'\n", DATEOBS_COMMENT);
      break;
     }
    }
   } else {
    if( param_verbose >= 1 )
     fprintf(stderr, "No suitable comment string found\n");
   } // if( strlen(DATEOBS_COMMENT)>1 ){

   if( (*timesys) != 1 ) {
    (*timesys)= 0; // UNKNOWN
    if( param_verbose >= 1 )
     fprintf(stderr, "Time system is set to UNKNOWN\n");
   }
  }

  /* Choose string to describe time system */
  if( (*timesys) == 2 ) {
   sprintf(tymesys_str_in, "TT");
  } else if( (*timesys) == 1 ) {
   sprintf(tymesys_str_in, "UT");
  } else {
   sprintf(tymesys_str_in, " ");
  }

  if( param_verbose >= 1 ) {
   fprintf(stderr, "The input time system is identified as: %s (blank if unknown)\n", tymesys_str_in);
  }
  if( param_verbose >= 1 ) {
   fprintf(stderr, "Setting observation date using %s keyword: %s\n", DATEOBS_KEY_NAME, DATEOBS);
  }
  //
  if( 0 == strlen(DATEOBS) ) {
   fprintf(stderr, "ERROR in gettime(): the %s FITS header key that is supposed to report the observation date is missing or empty!\n", DATEOBS_KEY_NAME);
   fits_close_file(fptr, &status); // close file
   return 1;
  }
  if( strlen(DATEOBS) < 8 ) {
   fprintf( stderr, "ERROR in gettime(): strlen(%s) < 8\n", DATEOBS);
   fits_close_file(fptr, &status); // close file
   return 1;
  }
  //fprintf( stderr, " %d #%s#\n", strlen(DATEOBS), DATEOBS);
  //
  
  for( j= 0; j < 32; j++ ) {
   if( DATEOBS[j] == 45 ) {
    Da_y[j]= '\0';
    break;
   }
   Da_y[j]= DATEOBS[j];
  }
  for( j+= 1; j < 32; j++ ) {
   if( DATEOBS[j] == 45 ) {
    if( j - 5 < 0 ) {
     fprintf( stderr, "ERROR100 in gettime()\n");
     fits_close_file(fptr, &status); // close file
     return 1;
    }
    Da_m[j - 5]= '\0';
    break;
   }
   if( j - 5 < 0 ) {
    fprintf( stderr, "ERROR101 in gettime()\n");
    fits_close_file(fptr, &status); // close file
    return 1;
   }
   Da_m[j - 5]= DATEOBS[j];
  }
  for( j+= 1; j < 32; j++ ) {
   if( DATEOBS[j] == '\0' || DATEOBS[j] == 'T' ) {
    if( j - 7 < 0 ) {
     fprintf( stderr, "ERROR102 in gettime()\n");
     fits_close_file(fptr, &status); // close file
     return 1;
    }
    Da_d[j - 7]= '\0';
    break;
   }
   if( j - 8 < 0 ) {
    fprintf( stderr, "ERROR103 in gettime()\n");
    fits_close_file(fptr, &status); // close file
    return 1;
   }
   Da_d[j - 8]= DATEOBS[j];
  }
  //Если время прописано в DATE-OBS после T
  if( DATEOBS[j] == 'T' ) {
   if( param_verbose >= 1 )
    fprintf(stderr, "Setting observation time using %s keyword: %s\n", DATEOBS_KEY_NAME, DATEOBS);
   jj= 0;
   for( j+= 1; j < 32; j++ ) {
    if( DATEOBS[j] == '\0' ) {
     TIMEOBS[jj]= '\0';
     break;
    }
    TIMEOBS[jj]= DATEOBS[j];
    jj++;
   }
  } else {
   if( 0 == strlen(TIMEOBS_KEY_NAME) ) {
    fprintf(stderr, "ERROR in gettime(): cannot find a FITS header key reporting the observation start time!\n");
    fits_close_file(fptr, &status); // close file
    return 1;
   }
   if( param_verbose >= 1 ) {
    fprintf(stderr, "Setting observation time using %s keyword: %s\n", TIMEOBS_KEY_NAME, TIMEOBS);
   }
  }

  ///////////////////////////////////
  for ( j= 0; j < 32; j++ ) {
   if ( TIMEOBS[j] == ':' ) {
    Tm_h[j]= '\0';

    break;
   }
   Tm_h[j]= TIMEOBS[j];
  }
  for ( j+= 1; j < 32; j++ ) {
   if ( TIMEOBS[j] == ':' || TIMEOBS[j] == '\0' ) {
    Tm_m[j - 3]= '\0';
    break;
   }
   Tm_m[j - 3]= TIMEOBS[j];
  }
  if ( j+1<(int)strlen( TIMEOBS ) ) { 
   for ( j+= 1; j < 32; j++ ) {
    if ( TIMEOBS[j] == '\0' ) {
     Tm_s[j - 6]= '\0';
     break;
    }
    Tm_s[j - 6]= TIMEOBS[j];
   }
   Tm_s[6]= '\0';
  } else {
   Tm_s[0]='0';
   Tm_s[1]='0';
   Tm_s[2]='\0';
  }
  //
  Tm_m[2]= '\0';
  Tm_m[2]= '\0';
  Da_d[2]= '\0';
  Da_m[2]= '\0';
  Da_y[4]= '\0';
  if ( strlen( Tm_s ) < 1 || strlen( Tm_m ) < 1 || strlen( Tm_h ) < 1 || strlen( Da_d ) < 1 || strlen( Da_m ) < 1 || strlen( Da_y ) < 2 ) {
   fprintf( stderr, "ERROR000 in gettime(): string length check failed on broken-down time components\n" );
   fits_close_file( fptr, &status ); // close file
   return 1;
  }
  // someday I'll need to get rid of this gross simplification
  structureTIME.tm_sec= (int)( atof( Tm_s ) + 0.5 );
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
  structureTIME.tm_mday= atoi(Da_d);
  if( structureTIME.tm_mday < 0 || structureTIME.tm_mday > 31 ) {
   fprintf(stderr, "ERROR004 in gettime(): the month day is not between 0 and 31\n");
   fits_close_file(fptr, &status);
   return 1;
  }
  structureTIME.tm_mon= atoi(Da_m) - 1;
  if( structureTIME.tm_mon < 0 || structureTIME.tm_mon > 12 ) {
   fprintf(stderr, "ERROR005 in gettime(): the month is not between 0 and 12\n");
   fits_close_file(fptr, &status);
   return 1;
  }
  structureTIME.tm_year= atoi(Da_y) - 1900;
  unix_time= timegm(&structureTIME);
  ///////////////////////////////////
  // A silly atempt to accomodate exposures crossing the midnight
  // that have time set through UT-END while date is correponding
  // to exposure start on the previous day.
  if( exposure < 0.0 ) {
   struct tm structureTIME2;
   structureTIME2.tm_sec= 0;
   structureTIME2.tm_min= 0;
   structureTIME2.tm_hour= 0;
   structureTIME2.tm_mday= structureTIME.tm_mday;
   structureTIME2.tm_mon= structureTIME.tm_mon;
   structureTIME2.tm_year= structureTIME.tm_year;
   if( (double)unix_time - (double)timegm(&structureTIME2) < (-1.0) * exposure ) {
    fprintf(stderr, "WARNING!!! The exposure is crossing midnight while it's time is set through UT-END!\n");
    unix_time+= 86400;
   }
  }
  ///////////////////////////////////
  // Oh, this is a funny one: cf. date -d '1969-12-31T23:59:59' +%s  and  date -d '1970-01-01T00:00:00' +%s
  if( (double)unix_time + exposure / 2.0 < 0.0 ) {
   unix_time= (time_t)((double)unix_time + exposure / 2.0 - 0.5);
  } else {
   unix_time= (time_t)((double)unix_time + exposure / 2.0 + 0.5);
  }

  (*JD)= (double)unix_time / 3600.0 / 24.0 + 2440587.5 + apply_JD_correction_in_days; // note that the time correction is not reflected in the broken down time!
  if( overridingJD_from_input_image_list != 0.0 ) {
   // Override the computed JD!
   (*JD)= overridingJD_from_input_image_list;
   if( (*timesys) == 1 && convert_timesys_to_TT == 1 ) {
    if( param_verbose >= 1 ) {
     fprintf(stderr, "Note that JD(UT) to JD(TT) conversion will still be applied to the overriding JD.\n");
    }
   }
  }

  /* Convert JD(UT) to JD(TT) if needed */
  if( (*timesys) == 1 && convert_timesys_to_TT == 1 ) {
   (*JD)= convert_jdUT_to_jdTT((*JD), timesys);
  }

  /* Choose string to describe new time system */
  if( (*timesys) == 2 ) {
   sprintf(tymesys_str_out, "(TT)");
  } else if( (*timesys) == 1 ) {
   sprintf(tymesys_str_out, "(UT)");
  } else {
   sprintf(tymesys_str_out, " ");
  }

  if( NULL != log_output ) {
   sprintf(log_output, "exp_start= %02d.%02d.%4d %02d:%02d:%02d  exp= %4.0lf  ", structureTIME.tm_mday, structureTIME.tm_mon + 1, structureTIME.tm_year - 100 + 2000, structureTIME.tm_hour, structureTIME.tm_min, structureTIME.tm_sec, exposure);
  }

  if( NULL != finder_chart_timestring_output ) {
   if( exposure>0.0 ) {
    sprintf(finder_chart_timestring_output, "%4d-%02d-%02d %02d:%02d:%02d %s, %.0lf sec", 
    structureTIME.tm_year - 100 + 2000, 
    structureTIME.tm_mon + 1, 
    structureTIME.tm_mday, 
    structureTIME.tm_hour, 
    structureTIME.tm_min, 
    structureTIME.tm_sec, 
    tymesys_str_in,
    exposure);
   } else {
    sprintf(finder_chart_timestring_output, "%4d-%02d-%02d %02d:%02d:%02d %s", 
    structureTIME.tm_year - 100 + 2000, 
    structureTIME.tm_mon + 1, 
    structureTIME.tm_mday, 
    structureTIME.tm_hour, 
    structureTIME.tm_min, 
    structureTIME.tm_sec, 
    tymesys_str_in);
   }
  }

  if( NULL != stderr_output ) {
   if( exposure != 0 )
    sprintf(stderr_output, "Exposure %3.0lf sec, %02d.%02d.%4d %02d:%02d:%02d %s = JD%s %.5lf mid. exp.\n", exposure, structureTIME.tm_mday, structureTIME.tm_mon + 1, structureTIME.tm_year - 100 + 2000, structureTIME.tm_hour, structureTIME.tm_min, structureTIME.tm_sec, tymesys_str_in, tymesys_str_out, (*JD));
   if( exposure == 0 )
    sprintf(stderr_output, "Exposure %3.0lf sec, %02d.%02d.%4d %02d:%02d:%02d %s = JD%s %.5lf\n", exposure, structureTIME.tm_mday, structureTIME.tm_mon + 1, structureTIME.tm_year - 100 + 2000, structureTIME.tm_hour, structureTIME.tm_min, structureTIME.tm_sec, tymesys_str_in, tymesys_str_out, (*JD));
  }
 } else {
#ifdef DEBUGMESSAGES
  fprintf(stderr, "entering  else corresponding to if ( status == 202 && date_parsed != 0 && expstart_mjd_parsed == 0 )\n");
#endif
  /* Setting pre-calculated JD(UT) mid. exp. from the JD keyword */
  (*timesys)= 1;
  sprintf(tymesys_str_out, "(UT)");
  (*JD)= inJD + apply_JD_correction_in_days;
  if( overridingJD_from_input_image_list != 0.0 ) {
#ifdef DEBUGMESSAGES
   fprintf(stderr, "entering  if ( overridingJD_from_input_image_list != 0.0 ) \n");
#endif
   // Override the computed JD!
   (*JD)= overridingJD_from_input_image_list;
  }
#ifdef DEBUGMESSAGES
  fprintf(stderr, "debug checkpoint a01\n");
#endif
  //exposure = 0.0;
  if( NULL != stderr_output ) {
#ifdef DEBUGMESSAGES
   fprintf(stderr, "entering  if ( NULL != stderr_output )\n");
#endif
   fprintf(stderr, "JD (mid. exp.) %.5lf\n", (*JD));
   unix_time= (time_t)(((*JD) - 2440587.5) * 3600.0 * 24.0 + 0.5);
   form_DATEOBS_and_EXPTIME_from_UNIXSEC(unix_time, 0.0, formed_str_DATEOBS, formed_str_EXPTIME);
   for( counter_i= 0; counter_i < strlen(formed_str_DATEOBS); counter_i++ ) {
    if( formed_str_DATEOBS[counter_i] == 'T' ) {
     formed_str_DATEOBS[counter_i]= ' ';
     break;
    }
   } // for( counter_i=0; counter_i<strlen(formed_str_DATEOBS); counter_i++ ){
   sprintf(stderr_output, "JD (mid. exp.) %.5lf = %s %s\n", (*JD), formed_str_DATEOBS, tymesys_str_out);
  }
#ifdef DEBUGMESSAGES
  fprintf(stderr, "debug checkpoint a03\n");
#endif
  if( NULL != log_output ) {
#ifdef DEBUGMESSAGES
   fprintf(stderr, "entering if ( NULL != log_output )\n");
#endif
   sprintf(log_output, "exp_start= %02d.%02d.%4d %02d:%02d:%02d  exp= %4.0lf  ", 0, 0, 0, 0, 0, 0, exposure);
  }
  //
 }
 fits_close_file(fptr, &status); // close file
 status= 0;
//fits_report_error( stderr, status ); // print out any error messages
#ifdef DEBUGMESSAGES
 fprintf(stderr, "finished   fits_close_file()\n");
#endif

 // Do this only if the time system is UNKNOWN or UT!
 if( (*timesys) == 0 || (*timesys) == 1 ) {
#ifdef DEBUGMESSAGES
  fprintf(stderr, "entering   if ( ( *timesys ) == 0 || ( *timesys ) == 1 )\n");
#endif
  if( param_verbose >= 1 ) {
#ifdef DEBUGMESSAGES
   fprintf(stderr, "entering   if ( param_verbose >= 1 )\n");
#endif
   // Compute unix_time so we can convert the JD back to the broken-down time
   //(*JD) = (double)unix_time/3600.0/24.0+2440587.5+apply_JD_correction_in_days;
   unix_time= (time_t)(((*JD) - 2440587.5) * 3600.0 * 24.0 + 0.5);
   exposure= fabs(exposure);
   form_DATEOBS_and_EXPTIME_from_UNIXSEC(unix_time, exposure, formed_str_DATEOBS, formed_str_EXPTIME);
#ifdef DEBUGMESSAGES
   fprintf(stderr, "\n\n\n\nunix_time=%ld\nexposure=%lf\nformed_str_DATEOBS=%s\nformed_str_EXPTIME=%s\n\n\n", unix_time, exposure, formed_str_DATEOBS, formed_str_EXPTIME);
#endif
   //
   if( param_verbose == 2 ) {
#ifdef DEBUGMESSAGES
    fprintf(stderr, "entering   if ( param_verbose == 2 ) )\n");
#endif
    // Update the FITS header
    write_DATEOBS_and_EXPTIME_to_FITS_header(fitsfilename, formed_str_DATEOBS, formed_str_EXPTIME);
   }
   //
  }
 }
#ifdef DEBUGMESSAGES
 fprintf(stderr, "gettime() ends\n");
#endif
 return 0;
}
