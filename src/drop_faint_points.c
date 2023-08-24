#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#include <dirent.h>
#include <sys/types.h>
#include <unistd.h>

#include "vast_limits.h"
#include "lightcurve_io.h"

int main( int argc, char **argv ) {

 FILE *infile;
 FILE *outfile;
 double JD, M, MERR, X, Y, APP;
 char str[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char str2[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char infilename[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char outfilename[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 double faintest;
 int n_drop;
 int total_number_of_points_to_drop;
 int already_dropped;

 // File name handling
 DIR *dp;
 struct dirent *ep;

 char **filenamelist;
 long filename_counter;
 long filenamelen;

 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s N_POINTS\n", argv[0] );
  return 1;
 }
 // strcpy(infilename,argv[2]);
 strcpy( outfilename, "lightcurve.tmp" );

 // Initialize the values to make the comppiler happy
 JD= M= MERR= X= Y= APP= 0.0;

 total_number_of_points_to_drop= atoi( argv[1] );

 filenamelist= (char **)malloc( MAX_NUMBER_OF_STARS * sizeof( char * ) );
 if( NULL == filenamelist ) {
  fprintf( stderr, "ERROR allocating memory for filenamelist\n");
  exit( EXIT_FAILURE );
 }
 filename_counter= 0;
 dp= opendir( "./" );
 if ( dp != NULL ) {
  fprintf( stderr, "Dropping %d faintest points from lightcurves... \n", total_number_of_points_to_drop );
  // while( ep = readdir(dp) ){
  while ( ( ep= readdir( dp ) ) != NULL ) {
   filenamelen= strlen( ep->d_name );
   if ( filenamelen < 8 ) {
    continue; // make sure the filename is not too short for the following tests
   }
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[filenamelen - 1] == 't' && ep->d_name[filenamelen - 2] == 'a' && ep->d_name[filenamelen - 3] == 'd' ) {
    filenamelist[filename_counter]= malloc( ( filenamelen + 1 ) * sizeof( char ) );
    if( NULL == filenamelist[filename_counter] ) {
     fprintf( stderr, "ERROR allocating memory for filenamelist[%ld]\n", filename_counter);
     exit( EXIT_FAILURE );
    }
    strncpy( filenamelist[filename_counter], ep->d_name, ( filenamelen + 1 ) );
    filename_counter++;
   }
  }
  (void)closedir( dp );
 } else {
  perror( "Couldn't open the directory" );
  free( filenamelist );
  return 2;
 }

 // Process each file in the list
 for ( ; filename_counter--; ) {
  n_drop= total_number_of_points_to_drop;
  // Open the file just to check if it's readable
  infile= fopen( filenamelist[filename_counter], "r" );
  if ( NULL == infile ) {
   fprintf( stderr, "ERROR: Can't open file %s\n", filenamelist[filename_counter] );
   // exit(1);
   continue; // if the input file is not readable - continue to the next file
  }
  fclose( infile );

  strcpy( infilename, filenamelist[filename_counter] );
  do {
   already_dropped= 0;
   // Find faintest point
   faintest= -999.0;
   infile= fopen( infilename, "r" );
   if ( NULL == infile ) {
    fprintf( stderr, "ERROR: Can't open file %s\n", filenamelist[filename_counter] );
    exit( EXIT_FAILURE );
   }
   while ( -1 < read_lightcurve_point( infile, &JD, &M, &MERR, &X, &Y, &APP, str, str2 ) ) {
    if ( JD == 0.0 )
     continue; // if this line could not be parsed, try the next one
    if ( M > faintest )
     faintest= M;
   }
   fclose( infile );
   // Remove faintest point
   infile= fopen( infilename, "r" );
   outfile= fopen( outfilename, "w" );
   while ( -1 < read_lightcurve_point( infile, &JD, &M, &MERR, &X, &Y, &APP, str, str2 ) ) {
    if ( JD == 0.0 )
     continue; // if this line could not be parsed, try the next one
    if ( M < faintest || already_dropped == 1 ) {
     write_lightcurve_point( outfile, JD, M, MERR, X, Y, APP, str, str2 );
    } else {
     already_dropped= 1; // make sure that if there are many points with exactly the same manitude we'll drop only the first one we find.
    }
   }
   fclose( infile );
   fclose( outfile );
   unlink( infilename );
   rename( outfilename, infilename );
   n_drop--;
  } while ( n_drop > 0 );
  free( filenamelist[filename_counter] );
 }

 free( filenamelist );

 return 0;
}
