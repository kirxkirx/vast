#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h> // for unlink()

#include <gsl/gsl_statistics_double.h>
#include <gsl/gsl_errno.h>
#include <gsl/gsl_sort.h>

#include "vast_limits.h"
//#include "vast_math.h"

//int main(int argc, char **argv){
int main() {
 FILE *dmsf;
 FILE *f;
 double m, sigma, X, Y, sum, mmax, mean;
 double *data;
 double *x;
 double *y;
 double *y_limit;

 char inputfilename[FILENAME_LENGTH];

 mmax= 0.0;

 /* Check if sysrem_input_star_list.lst was already created. If not - use data.m_sigma instead */
 strcpy( inputfilename, "sysrem_input_star_list.lst" );
 dmsf= fopen( inputfilename, "r" );
 if ( dmsf == NULL ) {
  strcpy( inputfilename, "data.m_sigma" );
 } else {
  fclose( dmsf );
 }

 /* Check if data.m_sigma is there? If not - try to cteate it using util/nopgplot.sh */
 dmsf= fopen( inputfilename, "r" );
 if ( dmsf == NULL ) {
  if ( 0 != system( "util/nopgplot.sh" ) ) {
   fprintf( stderr, "ERROR running util/nopgplot.sh\n" );
  }
 } else {
  fclose( dmsf );
 }

 y_limit= malloc( sizeof( double ) * MAX_NUMBER_OF_STARS );
 if ( y_limit == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for y_limit\n" );
  exit( 1 );
 };
 x= malloc( sizeof( double ) * MAX_NUMBER_OF_STARS );
 if ( x == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for x(select_sysrem_input_star_list.c)\n" );
  exit( 1 );
 };
 y= malloc( sizeof( double ) * MAX_NUMBER_OF_STARS );
 if ( y == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for y(select_sysrem_input_star_list.c)\n" );
  exit( 1 );
 };
 data= malloc( sizeof( double ) * MAX_NUMBER_OF_STARS );
 if ( data == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for data(select_sysrem_input_star_list.c)\n" );
  exit( 1 );
 };
 char str[256];
 sum= -1;
 int n= 0;
 int i= 0;
 dmsf= fopen( inputfilename, "r" );
 if ( dmsf == NULL ) {
  fprintf( stderr, "ERROR: Can't open file %s !\n", inputfilename );
  exit( 1 );
 }
 while ( -1 < fscanf( dmsf, "%lf %lf %lf %lf %s", &m, &sigma, &X, &Y, str ) ) {
  if ( sum == -1 ) {
   sum= m;
   n= 0;
   mmax= m;
  }
  if ( m <= mmax + M_SIGMA_BIN_SIZE_M ) {
   data[n]= sigma;
   n++;
  } else {
   x[i]= mmax + M_SIGMA_BIN_SIZE_M / 2;
   //sort_data_double(data, 0, n);
   gsl_sort( data, 1, n );
   if ( n > 3 * M_SIGMA_BIN_DROP )
    n-= M_SIGMA_BIN_DROP;
   if ( n == 0 && i != 0 ) {
    y[i]= y[i - 1];
    y_limit[i]= y_limit[i - 1];
   } else {
    mean= gsl_stats_mean( data, 1, n );
    y[i]= mean;
    y_limit[i]= gsl_stats_sd_m( data, 1, n, mean );
   }
   if ( 0 != isnan( y_limit[i] ) ) {
    //y_limit[i]=3*y[i];
    y_limit[i]= 2 * y[i];
   }
   //   fprintf(stderr,"%lf %lf %lf\n",x[i], y[i], y_limit[i]);
   i++;
   n= 0;
   mmax= m;
  }
 }
 fclose( dmsf );
 //
 free( data );
 //
 dmsf= fopen( inputfilename, "r" );
 if ( dmsf == NULL ) {
  fprintf( stderr, "ERROR: Couldn't open file %s(select_sysrem_input_star_list.c)\n", inputfilename );
  exit( 1 );
 };
 f= fopen( "sysrem_input_star_list.tmp", "w" );
 if ( f == NULL ) {
  fprintf( stderr, "ERROR: Couldn't open file sysrem_input_star_list.tmp(select_sysrem_input_star_list.c)\n" );
  exit( 1 );
 };
 while ( -1 < fscanf( dmsf, "%lf %lf %lf %lf %s", &m, &sigma, &X, &Y, str ) ) {
  //if( m>sum+M_SIGMA_BIN_MAG_OTSTUP ){
  for ( n= 0; n < i; n++ ) {
   if ( fabs( m - x[n] ) <= M_SIGMA_BIN_SIZE_M / 2 + M_SIGMA_BIN_SIZE_M / 10 ) {
    if ( sigma < y[n] + 10 * M_SIGMA_BIN_MAG_SIGMA_DETECT * y_limit[n] ) {
     //if( sigma<y[n]+10*M_SIGMA_BIN_MAG_SIGMA_DETECT*y_limit[n] ){
     fprintf( f, "%10.6lf %.6lf %9.3lf %9.3lf %s\n", m, sigma, X, Y, str );
     //fprintf(f,"%lf %lf %lf %lf %s\n",m,sigma,X,Y,str);
     break;
    } else {
     //      fprintf(stderr,"%lf %lf %lf %lf %s    %lf %lf %lf\n",m,sigma,X,Y,str,y[n]+10*M_SIGMA_BIN_MAG_SIGMA_DETECT*y_limit[n],y[n],y_limit[n]);
     fprintf( stderr, "Excluding star %s\n", str );
    }
   }
  }
  //}
 }
 fclose( dmsf );
 fclose( f );
 //
 free( y_limit );
 free( y );
 free( x );
 //

 //system("mv sysrem_input_star_list.tmp sysrem_input_star_list.lst");
 unlink( "sysrem_input_star_list.lst" );
 rename( "sysrem_input_star_list.tmp", "sysrem_input_star_list.lst" );
 return 0;
}
