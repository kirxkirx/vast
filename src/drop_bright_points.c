#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include <dirent.h>
#include <sys/types.h>
#include <unistd.h>

#include "vast_limits.h"
#include "lightcurve_io.h"

int main( int argc, char **argv ) {
 DIR *dp;
 struct dirent *ep;

 FILE *infile;
 FILE *outfile;
 double JD, M, MERR, X, Y, APP;
 char str[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char str2[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char infilename[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char outfilename[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 double brightest;
 int n_drop;
 int total_number_of_points_to_drop;
 int already_dropped;

 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s N_POINTS\n", argv[0] );
  return 1;
 }
 //strcpy(infilename,argv[2]);
 strcpy( outfilename, "lightcurve.tmp" );

 total_number_of_points_to_drop= atoi( argv[1] );

 dp= opendir( "./" );
 if ( dp != NULL ) {
  fprintf( stderr, "Dropping %d brightest points from lightcurves... \n", total_number_of_points_to_drop );
  //while( ep = readdir(dp) ){
  while ( ( ep= readdir( dp ) ) != NULL ) {
   if ( strlen( ep->d_name ) < 8 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {

    n_drop= total_number_of_points_to_drop;

    // Open the file just to check if it's readable
    infile= fopen( ep->d_name, "r" );
    if ( NULL == infile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     //exit(1);
     continue; // if the input file is not readable - continue to the next file
    }
    fclose( infile );

    strcpy( infilename, ep->d_name );
    do {
     already_dropped= 0;
     /* Find brightest point */
     brightest= 999.0;
     infile= fopen( infilename, "r" );
     if ( NULL == infile ) {
      fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
      exit( 1 );
     }
     //while(-1<fscanf(infile,"%lf %lf %lf %lf %lf %lf %s",&JD,&M,&MERR,&X,&Y,&APP,str)){
     while ( -1 < read_lightcurve_point( infile, &JD, &M, &MERR, &X, &Y, &APP, str, str2 ) ) {
      if ( JD == 0.0 )
       continue; // if this line could not be parsed, try the next one
      if ( M < brightest )
       brightest= M;
     }
     fclose( infile );
     /* Remove brightest point */
     //fprintf(stderr,"DEBUG: infilename=%s outfilename=%s \n",infilename,outfilename);
     infile= fopen( infilename, "r" );
     outfile= fopen( outfilename, "w" );
     //while(-1<fscanf(infile,"%lf %lf %lf %lf %lf %lf %s",&JD,&M,&MERR,&X,&Y,&APP,str)){
     while ( -1 < read_lightcurve_point( infile, &JD, &M, &MERR, &X, &Y, &APP, str, str2 ) ) {
      if ( JD == 0.0 )
       continue; // if this line could not be parsed, try the next one
      //if(M>brightest)fprintf(outfile, "%lf %.4lf %.4lf %.3lf %.3lf %.1lf %s\n",JD,M,MERR,X,Y,APP,str);
      if ( M > brightest || already_dropped == 1 ) {
       write_lightcurve_point( outfile, JD, M, MERR, X, Y, APP, str, str2 );
      } else {
       already_dropped= 1; // make sure that if there are many points with exactly the same manitude we'll drop only the first one we find.
      }
     }
     fclose( infile );
     fclose( outfile );
     //if(n_drop>1){
     //system("mv lightcurve.tmp lightcurve.tmp.tmp");
     unlink( infilename );
     rename( outfilename, infilename );
     //strcpy(infilename,"lightcurve.tmp.tmp");
     //}
     n_drop--;
    } while ( n_drop > 0 );
    //system("rm -f lightcurve.tmp.tmp");
    //unlink("lightcurve.tmp.tmp");
    //unlink(ep->d_name);
    //rename(infilename,ep->d_name);
   }
  }
  (void)closedir( dp );
 } else
  perror( "Couldn't open the directory\n" );

 return 0;
}
