#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <libgen.h>

#include "fitsio.h"

void get_name_from_string(char *name, char *string) {
 unsigned int i; //,j;
 if( strlen(string) > 13 ) {
  for( i= strlen(string); i > 0; i-- )
   if( string[i] == '.' ) {
    string[i]= '\0';
    break;
   } // remove file extenstion
  sprintf(name, "out%s", string);
 } else
  strcpy(name, string);
 strcat(name, ".dat"); // add new file extension
}

int main(int argc, char **argv) {
 fitsfile *fptr;
 int status, colnum_TIME, colnum_MAG, colnum_MAG_ERR, colnum_STATUS, i;
 int colnum_TIME_type, colnum_MAG_type, colnum_MAG_ERR_type, colnum_STATUS_type;
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
 char string2[1024];
 // char SPECTYPE[512];
 // char LUMCLASS[512];
 // double MAGNIT_B=0;
 double MAGNIT_V= 0;
 // double MAGNIT_R=0;
 // double MAGNIT_I=0;

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
 fits_read_key(fptr, TDOUBLE, "RA_OBJ", &ALPHA, NULL, &status);
 fits_read_key(fptr, TDOUBLE, "DEC_OBJ", &DELTA, NULL, &status);
 // fits_read_key(fptr, TDOUBLE, "MAGNIT_B", &MAGNIT_B, NULL, &status);
 fits_read_key(fptr, TDOUBLE, "WASP_MAG", &MAGNIT_V, NULL, &status);
 // fits_read_key(fptr, TDOUBLE, "MAGNIT_R", &MAGNIT_R, NULL, &status);
 // fits_read_key(fptr, TDOUBLE, "MAGNIT_I", &MAGNIT_I, NULL, &status);
 // fits_read_key(fptr, TSTRING, "SPECTYPE", SPECTYPE, NULL, &status);
 // fits_read_key(fptr, TSTRING, "LUMCLASS", LUMCLASS, NULL, &status);
 fits_close_file(fptr, &status); // close file

 sprintf(string, " ");
 string[0]= '\0';
 //sprintf(string,"MAGB%6.3lf_MAGV%6.3lf_MAGR%6.3lf_MAGI%6.3lf_%s_%s___%s",MAGNIT_B,MAGNIT_V,MAGNIT_R,MAGNIT_I,SPECTYPE,LUMCLASS,argv[1]);
 /* if( 0==isnan(MAGNIT_B) ){
  sprintf(string2,"MAGB%6.3lf_",MAGNIT_B);
  strcat(string,string2);
 }*/
 if( 0 == isnan(MAGNIT_V) ) {
  sprintf(string2, "MAGV%6.3lf_", MAGNIT_V);
  strcat(string, string2);
 }
 /* if( 0==isnan(MAGNIT_R) ){
  sprintf(string2,"MAGR%6.3lf_",MAGNIT_R);
  strcat(string,string2);
 }
 if( 0==isnan(MAGNIT_I) ){
  sprintf(string2,"MAGI%6.3lf_",MAGNIT_I);
  strcat(string,string2);
 }
 sprintf(string2,"%s_%s___%s",SPECTYPE,LUMCLASS,argv[1]);*/
 sprintf(string2, "%s", argv[1]);
 strcat(string, string2);

 for( i= 0; i < (int)strlen(string); i++ )
  if( string[i] == ' ' )
   string[i]= '_'; // remove any possible white spaces from string

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
 fits_get_colnum(fptr, CASEINSEN, "TMID", &colnum_TIME, &status);
 fits_get_coltype(fptr, colnum_TIME, &colnum_TIME_type, NULL, NULL, &status);
 fits_get_colnum(fptr, CASEINSEN, "TAMFLUX2", &colnum_MAG, &status);
 // fits_get_colnum(fptr, CASEINSEN, "GREENFLUX", &colnum_MAG, &status);
 fits_get_coltype(fptr, colnum_MAG, &colnum_MAG_type, NULL, NULL, &status);
 fits_get_colnum(fptr, CASEINSEN, "TAMFLUX2_ERR", &colnum_MAG_ERR, &status);
 // fits_get_colnum(fptr, CASEINSEN, "GREENFLUXDEV", &colnum_MAG_ERR, &status);
 fits_get_coltype(fptr, colnum_MAG_ERR, &colnum_MAG_ERR_type, NULL, NULL, &status);
 fits_get_colnum(fptr, CASEINSEN, "FLAG", &colnum_STATUS, &status);
 fits_get_coltype(fptr, colnum_STATUS, &colnum_STATUS_type, NULL, NULL, &status);
 fprintf(stderr, " %d (%d) %d (%d)\n", colnum_TIME, colnum_TIME_type, colnum_MAG, colnum_MAG_type);
 fits_report_error(stderr, status);
 if( num_rows <= 0 ) {
  fprintf(stderr, "ERROR: Trying allocate zero or negative bytes amount(num_cols <= 0)\n");
 };
 mag= malloc(num_rows * sizeof(double));
 if( mag == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for mag\n");
  exit(1);
 };
 mag_err= malloc(num_rows * sizeof(double));
 if( mag_err == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for mag_err\n");
  exit(1);
 };
 JD= malloc(num_rows * sizeof(double));
 if( JD == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for JD\n");
  exit(1);
 };
 status_flag= malloc(num_rows * sizeof(int));
 if( status_flag == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for status_flag\n");
  exit(1);
 };
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
  fprintf(stderr, "ERROR: Couldn't open file %s\n", name);
  exit(1);
 };
 for( i= 0; i < num_rows; i++ ) {
  JD[i]= JD[i] / 86400 + 2453005.5; // Butters et al. 2010A&A...520L..10B
  //mag[i]=mag[i]*1000; // shift zero-point to avoid problems with other VaST subroutines which do not like faint stars
  mag_err[i]= (-2.5 * log10(mag[i]) + 2.5 * log10(mag_err[i] + mag[i]) - 2.5 * log10(mag[i] - mag_err[i]) + 2.5 * log10(mag[i])) / 2.0;
  //mag[i]=-2.5*log10(mag[i]);
  mag[i]= 15.0 - 2.5 * log10(mag[i]); // according to Butters et al. 2010, A&A, 520, L10
  //if( status_flag[i]==0 && 0==isnan(JD[i]) && 0==isnan(mag[i]) && 0==isnan(mag_err[i]) )
  if( 0 == isnan(JD[i]) && 0 == isnan(mag[i]) && 0 == isnan(mag_err[i]) )
   fprintf(outfile, "%lf %lf %lf  %10.6lf %9.6lf %6.3lf %02d_%s\n", JD[i], mag[i], mag_err[i], ALPHA, DELTA, MAGNIT_V, status_flag[i], string);
  //fprintf(outfile,"%lf %lf %lf  512.0  512.0 5.0 %s\n", JD[i], mag[i], mag_err[i],argv[1]);
 }
 fclose(outfile);
 return 0;
}
