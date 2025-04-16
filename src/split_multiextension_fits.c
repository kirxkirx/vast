// Split multi-extension FITS into single-extension FITS files

#include <string.h>
#include <stdlib.h>
#include <libgen.h>
#include <math.h>

#include "fitsio.h"

// VaST's own header files
#include "vast_limits.h" // defines FILENAME_LENGTH

// Function prototype for gettime from gettime.c
int gettime( char *fitsfilename, double *JD, int *timesys, int convert_timesys_to_TT,
             double *dimX, double *dimY, char *stderr_output, char *log_output,
             int param_nojdkeyword, int param_verbose, char *finder_chart_timestring_output );

int main( int argc, char *argv[] ) {

 int success_counter;

 int number_of_hdus, current_hdu, i;
 int current_hdu_type;

 fitsfile *fptrout;
 char strbuf[FILENAME_LENGTH];
 char outfilename[2 * FILENAME_LENGTH];
 char date_obs[FLEN_CARD]= "";
 char dateobs_comment[FLEN_COMMENT]= "Observation start time (UTC) copied from primary HDU";

 // For reading FITS files
 fitsfile *fptr; // pointer to the FITS file; defined in fitsio.h

 // For gettime check
 double JD= 0.0;
 int timesys= 0;
 double dimX= 0.0, dimY= 0.0;
 char stderr_output[1024]= "";
 int gettime_status= 0;
 int primary_has_dateobs= 0;

 int status= 0;

 // Check command line arguments
 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s multiextension_image.fits\n", argv[0] );
  return 1;
 }

 // Reading the input FITS file
 fits_open_file( &fptr, argv[1], 0, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 if ( status != 0 )
  exit( status );

 // Check if DATE-OBS exists in the primary HDU
 fits_read_key( fptr, TSTRING, "DATE-OBS", date_obs, NULL, &status );
 if ( status == 0 ) {
  primary_has_dateobs= 1;
  fprintf( stderr, "Found DATE-OBS in primary HDU: %s\n", date_obs );
 } else {
  status= 0; // Reset status
  fprintf( stderr, "Warning: DATE-OBS not found in primary HDU.\n" );
 }

 fits_get_num_hdus( fptr, &number_of_hdus, &status );
 fits_report_error( stderr, status ); /* print out any error messages */
 if ( status != 0 )
  exit( status );
 fprintf( stderr, "Found %d HDUs\n", number_of_hdus );

 // HDU#1 is the primary HDU! So we'll start from HDU#2
 for ( success_counter= 0, current_hdu= 2; current_hdu < number_of_hdus + 1; current_hdu++ ) {
  fits_movabs_hdu( fptr, current_hdu, &current_hdu_type, &status );
  strcpy( strbuf, basename( argv[1] ) );
  for ( i= strlen( strbuf ) - 1; i > 0; i-- ) {
   if ( strbuf[i] == '.' ) {
    strbuf[i]= '\0';
    break;
   }
  }
  sprintf( outfilename, "%s_%02d.fit", strbuf, current_hdu - 1 ); // Names will match HDU numbers in fv
  fprintf( stderr, "Writing %s ...", outfilename );
  fits_create_file( &fptrout, outfilename, &status );
  fits_report_error( stderr, status ); // print out any error messages
  if ( status != 0 )
   exit( EXIT_FAILURE );
  fits_copy_hdu( fptr, fptrout, 0, &status );

  // Check if we can extract time information with gettime
  fits_close_file( fptrout, &status ); // Close file so gettime can open it
  gettime_status= gettime( outfilename, &JD, &timesys, 0, &dimX, &dimY, stderr_output,
                           NULL, 0, 0, NULL );

  // Consider gettime unsuccessful if JD is 0 or very small (ancient date)
  if ( gettime_status != 0 || JD < 2400000.0 ) {
   fprintf( stderr, "\nWarning: Could not extract valid time information from %s\n", outfilename );

   // If primary HDU has DATE-OBS, copy it to the output file
   if ( primary_has_dateobs ) {
    // Reopen the output file to add DATE-OBS
    fits_open_file( &fptrout, outfilename, READWRITE, &status );

    // Write the DATE-OBS keyword directly
    fits_write_key_str( fptrout, "DATE-OBS", date_obs, dateobs_comment, &status );

    fits_close_file( fptrout, &status );

    fprintf( stderr, "Copied DATE-OBS='%s' from primary HDU to %s\n", date_obs, outfilename );
   } else {
    fprintf( stderr, "Warning: No DATE-OBS information available to add to %s\n", outfilename );
   }
  } else {
   fprintf( stderr, " (Time information present: %s)", stderr_output );
  }

  success_counter++;
  fprintf( stderr, "done\n" );
 }

 fits_close_file( fptr, &status ); // close the input file

 fprintf( stderr, "Done splitting %s into %d single-extension FITS images!\n", argv[1], success_counter );

 return 0;
}
