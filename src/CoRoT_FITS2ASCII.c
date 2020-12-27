#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <libgen.h>

#include "fitsio.h"

void get_name_from_string(char *name, char *string) {
 int i, j;
 if( strlen(string) > 13 ) {
  name[0]= 'o';
  name[1]= 'u';
  name[2]= 't';
  for( i= 13, j= 3;; i++, j++ ) {
   if( string[i] == '_' ) {
    name[j]= '\0';
    break;
   }
   name[j]= string[i];
  }
 } else
  strcpy(name, string);
 strcat(name, ".dat");
}

int main(int argc, char **argv) {
 fitsfile *fptr;
 int status, colnum_TIME, colnum_MAG, colnum_MAG_ERR, colnum_STATUS, i;
 int colnum_TIME_type, colnum_MAG_type, colnum_MAG_ERR_type, colnum_STATUS_type;
 // Yes, num_rows should be long while num_cols should be int
 long num_rows;
 int num_cols;
 double *mag;
 double *mag_err;
 double *JD;
 int *status_flag;
 FILE *outfile;
 char name[512];

 double ALPHA, DELTA;
 char string[1024];
 char string2[2048]; // should be enough to put in SPECTYPE and LUMCLASS
 char SPECTYPE[512];
 char LUMCLASS[512];
 double MAGNIT_B= 0;
 double MAGNIT_V= 0;
 double MAGNIT_R= 0;
 double MAGNIT_I= 0;

 fprintf(stderr, "\nCoRoT_FITS2ASCII - a tool to convert CoRoT FITS lightcurves to VaST ASCII format.\n");

 if( argc != 2 ) {
  fprintf(stderr, "\nUsage: %s XXXX.fit\n\n", argv[0]);
  fprintf(stderr, "The lightcurve in the VaST format will be written to outXXXX.dat\n");
  fprintf(stderr, "Enjoy! =)\n");
  exit(1);
 }
 status= 0;

 /* Extract data from fits header */
 fits_open_file(&fptr, argv[1], READONLY, &status);
 fits_report_error(stderr, status); /* print out any error messages */
 if( status != 0 )
  exit(status);
 fits_read_key(fptr, TDOUBLE, "ALPHA", &ALPHA, NULL, &status);
 if( status != 0 ) {
  fprintf(stderr, "WARNING: cannot read FITS key: ALPHA\n");
  ALPHA= 0.0;
  status= 0;
 }
 fits_read_key(fptr, TDOUBLE, "DELTA", &DELTA, NULL, &status);
 if( status != 0 ) {
  fprintf(stderr, "WARNING: cannot read FITS key: DELTA\n");
  DELTA= 0.0;
  status= 0;
 }
 fits_read_key(fptr, TDOUBLE, "MAGNIT_B", &MAGNIT_B, NULL, &status);
 if( status != 0 ) {
  fprintf(stderr, "WARNING: cannot read FITS key: MAGNIT_B\n");
  MAGNIT_B= 0.0;
  status= 0;
 }
 fits_read_key(fptr, TDOUBLE, "MAGNIT_V", &MAGNIT_V, NULL, &status);
 if( status != 0 ) {
  fprintf(stderr, "WARNING: cannot read FITS key: MAGNIT_V\n");
  MAGNIT_V= 0.0;
  status= 0;
 }
 fits_read_key(fptr, TDOUBLE, "MAGNIT_R", &MAGNIT_R, NULL, &status);
 if( status != 0 ) {
  fprintf(stderr, "WARNING: cannot read FITS key: MAGNIT_R\n");
  MAGNIT_R= 0.0;
  status= 0;
 }
 fits_read_key(fptr, TDOUBLE, "MAGNIT_I", &MAGNIT_I, NULL, &status);
 if( status != 0 ) {
  fprintf(stderr, "WARNING: cannot read FITS key: MAGNIT_I\n");
  MAGNIT_I= 0.0;
  status= 0;
 }
 fits_read_key(fptr, TSTRING, "SPECTYPE", SPECTYPE, NULL, &status);
 if( status != 0 ) {
  fprintf(stderr, "WARNING: cannot read FITS key: SPECTYPE\n");
  strcpy(SPECTYPE, "");
  status= 0;
 }
 fits_read_key(fptr, TSTRING, "LUMCLASS", LUMCLASS, NULL, &status);
 if( status != 0 ) {
  fprintf(stderr, "WARNING: cannot read FITS key: LUMCLASS\n");
  strcpy(LUMCLASS, "");
  status= 0;
 }
 fits_close_file(fptr, &status); // close file

 sprintf(string, " ");
 string[0]= '\0';

 if( 0 == isnan(MAGNIT_B) ) {
  sprintf(string2, "MAGB%06.3lf_", MAGNIT_B);
  strcat(string, string2);
 }
 if( 0 == isnan(MAGNIT_V) ) {
  sprintf(string2, "MAGV%06.3lf_", MAGNIT_V);
  strcat(string, string2);
 }
 if( 0 == isnan(MAGNIT_R) ) {
  sprintf(string2, "MAGR%06.3lf_", MAGNIT_R);
  strcat(string, string2);
 }
 if( 0 == isnan(MAGNIT_I) ) {
  sprintf(string2, "MAGI%06.3lf_", MAGNIT_I);
  strcat(string, string2);
 }
 sprintf(string2, "%s_%s___%s", SPECTYPE, LUMCLASS, argv[1]);
 strcat(string, string2);

 fprintf(stderr, "%lf %lf #%s#\n", ALPHA, DELTA, string);

 fprintf(stderr, "Opening FITS table %s\n", argv[1]);
 fits_open_table(&fptr, argv[1], READONLY, &status);
 fits_report_error(stderr, status);
 if( status != 0 )
  exit(status);
 fits_get_num_rows(fptr, &num_rows, &status);
 fits_get_num_cols(fptr, &num_cols, &status);
 fits_report_error(stderr, status);
 if( status != 0 )
  exit(status);
 fprintf(stderr, "rows: %ld  col:%d\n", num_rows, num_cols);
 fits_get_colnum(fptr, CASEINSEN, "DATEHEL", &colnum_TIME, &status);
 fits_get_coltype(fptr, colnum_TIME, &colnum_TIME_type, NULL, NULL, &status);
 fits_get_colnum(fptr, CASEINSEN, "WHITEFLUX", &colnum_MAG, &status);
 fits_get_coltype(fptr, colnum_MAG, &colnum_MAG_type, NULL, NULL, &status);
 fits_get_colnum(fptr, CASEINSEN, "WHITEFLUXDEV", &colnum_MAG_ERR, &status);
 fits_get_coltype(fptr, colnum_MAG_ERR, &colnum_MAG_ERR_type, NULL, NULL, &status);
 fits_get_colnum(fptr, CASEINSEN, "STATUS", &colnum_STATUS, &status);
 fits_get_coltype(fptr, colnum_STATUS, &colnum_STATUS_type, NULL, NULL, &status);
 fprintf(stderr, " %d (%d) %d (%d)\n", colnum_TIME, colnum_TIME_type, colnum_MAG, colnum_MAG_type);
 fits_report_error(stderr, status);
 if( num_rows <= 0 || num_cols <= 0 ) {
  fprintf(stderr, "ERROR: Wrong table size: %d x %ld\n", num_cols, num_rows);
  exit(1);
 };
 mag= malloc(num_rows * sizeof(double));
 if( mag == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for mag(CoRoT_FITS2ASCII.c)\n");
  exit(1);
 };
 mag_err= malloc(num_rows * sizeof(double));
 if( mag_err == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for mag_err(CoRoT_FITS2ASCII.c)\n");
  exit(1);
 }
 JD= malloc(num_rows * sizeof(double));
 if( JD == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for JD(CoRoT_FITS2ASCII.c)\n");
  exit(1);
 }
 status_flag= malloc(num_rows * sizeof(int));
 if( status_flag == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for status_flag(CoRoT_FITS2ASCII.c)\n");
  exit(1);
 }

 fits_read_col(fptr, TDOUBLE, colnum_TIME, 1, 1, num_rows, NULL, JD, NULL, &status);
 fits_read_col(fptr, TDOUBLE, colnum_MAG, 1, 1, num_rows, NULL, mag, NULL, &status);
 fits_read_col(fptr, TDOUBLE, colnum_MAG_ERR, 1, 1, num_rows, NULL, mag_err, NULL, &status);
 fits_read_col(fptr, TINT, colnum_STATUS, 1, 1, num_rows, NULL, status_flag, NULL, &status);

 fits_report_error(stderr, status);
 fits_close_file(fptr, &status);
 get_name_from_string(name, basename(argv[1]));
 fprintf(stderr, "Writing file %s\n", name);
 outfile= fopen(name, "w");
 if( outfile == NULL ) {
  fprintf(stderr, "ERROR: Can't open file %s\n", name);
  exit(1);
 };
 for( i= 0; i < num_rows; i++ ) {
  JD[i]+= 2451545.00000;
  mag_err[i]= (-2.5 * log10(mag[i]) + 2.5 * log10(mag_err[i] + mag[i]) - 2.5 * log10(mag[i] - mag_err[i]) + 2.5 * log10(mag[i])) / 2.0;
  mag[i]= -2.5 * log10(mag[i]);
  if( status_flag[i] == 0 && 0 == isnan(JD[i]) && 0 == isnan(mag[i]) && 0 == isnan(mag_err[i]) )
   fprintf(outfile, "%lf %lf %lf  %10.6lf %9.6lf %6.3lf %02d_%s\n", JD[i], mag[i], mag_err[i], ALPHA, DELTA, MAGNIT_R, status_flag[i], string);
 }
 fclose(outfile);
 return 0;
}
