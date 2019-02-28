/* This script will format a lightcurve to simple "JD mag" format */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int is_comment( char *str ) {
 int i;
 int is_empty= 1;
 int n= strlen( str );

 if ( n < 1 )
  return 1;

 for ( i= 0; i < n - 1; i++ ) {
  if ( str[i] != ' ' && str[i] != '0' && str[i] != '1' && str[i] != '2' && str[i] != '3' && str[i] != '4' && str[i] != '5' && str[i] != '6' && str[i] != '7' && str[i] != '8' && str[i] != '9' && str[i] != '.' && str[i] != '\r' && str[i] != '\n' && str[i] != '\t' && str[i] != '+' && str[i] != '-' )
   return 1;
  if ( str[i] == '\t' )
   str[i]= ' ';
  if ( str[i] == '\r' )
   str[i]= ' ';
  if ( str[i] != ' ' )
   is_empty= 0;
 }

 if ( is_empty == 1 )
  return 1;

 return 0;
}

int main( int argc, char *argv[] ) {
 FILE *inputfile;
 double JD, MAG, MAGERR, X, Y, AP;
 char STR[1024];
 int lightcurve_format;

 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s outXXXX.dat\n", argv[0] );
  return 1;
 }

 inputfile= fopen( argv[1], "r" );
 if ( inputfile == NULL ) {
  fprintf( stderr, "ERROR: can't open lightcurvefile %s\n", argv[1] );
  fprintf( stderr, "Usage: %s outXXXX.dat\n", argv[0] );
  return 1;
 }

 /* Read first line to identify the lightcurve format */
 if ( NULL == fgets( STR, 1000, inputfile ) ) {
  fprintf( stderr, "ERROR: empty lightcurve file!\n" );
  return 1;
 }

 if ( 1 == is_comment( STR ) ) {
  while ( NULL != fgets( STR, 1000, inputfile ) ) {
   if ( 4 == sscanf( STR, "%lf %lf %lf %lf", &JD, &MAG, &MAGERR, &X ) )
    break; // VaST lightcurve format
   if ( 0 == is_comment( STR ) )
    break;
  }
 }

 if ( 2 == sscanf( STR, "%lf %lf", &JD, &MAG ) ) {
  lightcurve_format= 2; // "JD mag" format
  if ( 3 == sscanf( STR, "%lf %lf %lf", &JD, &MAG, &MAGERR ) ) {
   lightcurve_format= 1; // "JD mag err" format
   if ( 4 == sscanf( STR, "%lf %lf %lf %lf", &JD, &MAG, &MAGERR, &X ) )
    lightcurve_format= 0; // VaST lightcurve format
  }
 } else {
  fprintf( stderr, "ERROR: can't parse the lightcurve file!\n" );
  return 1;
 }
 fseek( inputfile, 0, SEEK_SET ); // go back to the beginning of the lightcurve file
 if ( lightcurve_format == 0 ) {
  fprintf( stderr, "VaST lightcurve format detected!\n" );
  while ( NULL != fgets( STR, 1000, inputfile ) ) {
   sscanf( STR, "%lf %lf %lf %lf %lf %lf %s", &JD, &MAG, &MAGERR, &X, &Y, &AP, STR );
   //if( JD>2450000.0 )JD-=2450000.0; // to comfort the new version of WinEfk
   fprintf( stdout, "%lf %.6lf %.6lf\r\n", JD, MAG, MAGERR );
  }
 }
 if ( lightcurve_format == 1 ) {
  fprintf( stderr, "\"JD mag err\" lightcurve format detected!\n" );
  while ( NULL != fgets( STR, 1000, inputfile ) ) {
   if ( 1 == is_comment( STR ) )
    continue;
   sscanf( STR, "%lf %lf %lf", &JD, &MAG, &MAGERR );
   //if( JD>2450000.0 )JD-=2450000.0; // to comfort the new version of WinEfk
   fprintf( stdout, "%lf %.6lf %.6lf\r\n", JD, MAG, MAGERR );
  }
 }
 if ( lightcurve_format == 2 ) {
  fprintf( stderr, "\"JD mag\" lightcurve format detected!\n" );
  while ( NULL != fgets( STR, 1000, inputfile ) ) {
   if ( 1 == is_comment( STR ) )
    continue;
   sscanf( STR, "%lf %lf", &JD, &MAG );
   //if( JD>2450000.0 )JD-=2450000.0; // to comfort the new version of WinEfk
   fprintf( stdout, "%lf %.6lf\r\n", JD, MAG );
  }
 }

 fclose( inputfile );

 return 0;
}
