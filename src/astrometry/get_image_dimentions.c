#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#include "../fitsio.h"

int main(int argc, char **argv) {
 int status= 0;  //for cfitsio routines
 fitsfile *fptr; /* pointer to the FITS file; defined in fitsio.h */
 //long  fpixel = 1, naxis = 2;
 long naxes[2];
 char fitsfilename[1024];

 if( argc != 2 ) {
  fprintf(stderr, "Usage: %s image.fit\n", argv[0]);
  return 1;
 }

 strncpy(fitsfilename, argv[1], 1024);

 /* Extract data from fits header */
 //fits_open_file(&fptr, fitsfilename, READONLY, &status);
 fits_open_image(&fptr, fitsfilename, READONLY, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status); /* print out any error messages */
  return status;
 }
 fits_read_key(fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status);
  fits_close_file(fptr, &status); // close file
  fprintf(stderr, "ERROR: can't get image dimensions from NAXIS1 keyword!\n");
  return status;
 }
 fits_read_key(fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status);
 if( 0 != status ) {
  fits_report_error(stderr, status);
  fits_close_file(fptr, &status); // close file
  fprintf(stderr, "ERROR: can't get image dimensions from NAXIS2 keyword!\n");
  return status;
 }
 fits_close_file(fptr, &status); // close file
 fprintf(stdout, " --width %ld --height %ld ", naxes[0], naxes[1]);
 return 0;
}
