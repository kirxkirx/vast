/*

  This program reads an ASCII SExtractor catalog created by VaST and converts it
  to a binary table readable for Astrometry.net software after doing some basic filtering.

 */

#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h> // for unlink()
#include <math.h>

#include "fitsio.h"

#include "vast_limits.h"

#include "parse_sextractor_catalog.h"

#include "is_point_close_or_off_the_frame_edge.h" // for is_point_close_or_off_the_frame_edge()

int main( int argc, char **argv ) {

 int i, j, n, n_good, n_high_snr; // counters
 float *X;
 float *Y;
 float *FLUX;

 float Xtmp, Ytmp, FLUXtmp;

 int star_number_in_sextractor_catalog, flags;
 double flux, flux_err, mag, mag_err, x, y, a, a_err, b, b_err;

 int previous_star_number_in_sextractor_catalog; // !! to check that the star count in the output catalog is always increasing

 char ascii_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT];
 char ascii_catalog_filename[512];
 char fits_catalog_filename[512];
 // char tmpstring[ascii_catalog_string];

 // char external_flag_string[256];

 int external_flag;
 double psf_chi2;

 FILE *ascii_catalog;
 fitsfile *fptr;
 int status= 0;

 if ( argc < 5 ) {
  fprintf( stderr, "Usage: %s image00000.cat out12345.xyls X_image_size_pix Y_image_size_pix\n", argv[0] );
  return 1;
 }
 strcpy( ascii_catalog_filename, argv[1] );
 strcpy( fits_catalog_filename, argv[2] );
 float X_im_size= (float)atof( argv[3] );
 float Y_im_size= (float)atof( argv[4] );

 // Read ASCII catalog
 ascii_catalog= fopen( ascii_catalog_filename, "r" );
 if ( NULL == ascii_catalog ) {
  fprintf( stderr, "[%s] ERROR: cannot open %s\n", argv[0], ascii_catalog_filename );
  return 1;
 }
 for ( n= 0; NULL != fgets( ascii_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, ascii_catalog ); n++ )
  ;
 X= malloc( n * sizeof( float ) );
 Y= malloc( n * sizeof( float ) );
 FLUX= malloc( n * sizeof( float ) );
 fseek( ascii_catalog, 0, SEEK_SET ); // go back to the beginning of the file
 previous_star_number_in_sextractor_catalog= 0;
 for ( i= 0, n_good= 0, n_high_snr= 0; i < n; i++ ) {
  if ( NULL == fgets( ascii_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, ascii_catalog ) ) {
   break;
  }

  if ( 0 != parse_sextractor_catalog_string( ascii_catalog_string, &star_number_in_sextractor_catalog, &flux, &flux_err, &mag, &mag_err, &x, &y, &a, &a_err, &b, &b_err, &flags, &external_flag, &psf_chi2, NULL ) ) {
   fprintf( stderr, "WARNING: problem occurred while parsing SExtractor catalog %s\nThe offending line is:\n%s\n", ascii_catalog_filename, ascii_catalog_string );
   continue;
  }

  // Read only stars detected at the first FITS image extension.
  // The start of the second image extension will be signified by a jump in star numbering
  if ( star_number_in_sextractor_catalog < previous_star_number_in_sextractor_catalog ) {
   fprintf( stderr, "WARNING: it seems SExtractor catalog contains detection at multiple FITS extensions. Only the first extension detections are processed!\n" );
   break;
  } else {
   previous_star_number_in_sextractor_catalog= star_number_in_sextractor_catalog;
  }

  // legacy code
  if ( flux == 0 )
   continue;
  if ( flux_err == 999999 )
   continue;
  if ( mag == 99.0000 )
   continue;
  if ( mag_err == 99.0000 )
   continue;
  if ( a + a_err < FWHM_MIN )
   continue;
  if ( b + b_err < FWHM_MIN )
   continue;

  //
  if ( 1 == is_point_close_or_off_the_frame_edge( x, y, X_im_size, Y_im_size, FRAME_EDGE_INDENT_PIXELS ) ) {
   continue;
  }
  if ( flux / flux_err < MIN_SNR ) {
   continue;
  }
  // else this is a reasonably good star
  X[n_good]= x;
  Y[n_good]= y;
  FLUX[n_good]= flux;
  n_good++;
  if ( flux / flux_err > 50.0 ) {
   // if( flux / flux_err > 20.0 ){
   n_high_snr++;
  }
 }
 if ( n_high_snr < 100 ) {
  // if there are too few high-snr stars - lower the SNR limit
  fseek( ascii_catalog, 0, SEEK_SET ); // go back to the beginning of the file
  previous_star_number_in_sextractor_catalog= 0;
  for ( i= 0, n_good= 0, n_high_snr= 0; i < n; i++ ) {
   if ( NULL == fgets( ascii_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, ascii_catalog ) ) {
    break;
   }

   if ( 0 != parse_sextractor_catalog_string( ascii_catalog_string, &star_number_in_sextractor_catalog, &flux, &flux_err, &mag, &mag_err, &x, &y, &a, &a_err, &b, &b_err, &flags, &external_flag, &psf_chi2, NULL ) ) {
    fprintf( stderr, "WARNING: problem occurred while parsing SExtractor catalog %s\nThe offending line is:\n%s\n", ascii_catalog_filename, ascii_catalog_string );
    continue;
   }

   // Read only stars detected at the first FITS image extension.
   // The start of the second image extension will be signified by a jump in star numbering
   if ( star_number_in_sextractor_catalog < previous_star_number_in_sextractor_catalog ) {
    fprintf( stderr, "WARNING: it seems SExtractor catalog contains detection at multiple FITS extensions. Only the first extension detections are processed!\n" );
    break;
   } else {
    previous_star_number_in_sextractor_catalog= star_number_in_sextractor_catalog;
   }

   // legacy code
   if ( flux == 0 )
    continue;
   if ( flux_err == 999999 )
    continue;
   if ( mag == 99.0000 )
    continue;
   if ( mag_err == 99.0000 )
    continue;
   if ( a + a_err < FWHM_MIN )
    continue;
   if ( b + b_err < FWHM_MIN )
    continue;

   //
   if ( 1 == is_point_close_or_off_the_frame_edge( x, y, X_im_size, Y_im_size, FRAME_EDGE_INDENT_PIXELS ) ) {
    continue;
   }
   if ( flux / flux_err < MIN_SNR ) {
    continue;
   }
   // else this is a reasonably good star
   X[n_good]= x;
   Y[n_good]= y;
   FLUX[n_good]= flux;
   n_good++;
   if ( flux / flux_err > 20.0 ) {
    n_high_snr++;
   }
  }
 } // if too few high-SNR stars
 fclose( ascii_catalog );

 fprintf( stderr, "%s found %d high-SNR stars for plate solving\n", argv[0], n_high_snr );

 // Check if we have enough high-SNR stars to attempt plate solving
 // if ( n_high_snr < 10 ) {
 if ( n_high_snr < 4 ) {
  fprintf( stderr, "ERROR in %s : too few high-SNR stars detected on the image (%d<10).\nIs this a bad image?\n", argv[0], n_high_snr );
  free( X );
  free( Y );
  free( FLUX );
  return 1;
 }

 // Sort good stars in flux
 for ( i= 0; i < n_good - 1; i++ )
  for ( j= i + 1; j < n_good - 1; j++ ) {
   if ( FLUX[j] > FLUX[i] ) {
    Xtmp= X[i];
    Ytmp= Y[i];
    FLUXtmp= FLUX[i];

    X[i]= X[j];
    Y[i]= Y[j];
    FLUX[i]= FLUX[j];

    X[j]= Xtmp;
    Y[j]= Ytmp;
    FLUX[j]= FLUXtmp;
   }
  }

 // Use only N brightest stars!
 if ( n_good > 10000 )
  n_good= 10000;

 if ( n_good > n_high_snr )
  n_good= n_high_snr;

 // Create FITS table
 char *ttype[3]= { "X_IMAGE", "Y_IMAGE", "FLUX_APER" };
 char *tform[3]= { "1E", "1E", "1E" };
 char *tunit[3]= { "pixel", "pixel", "count" };
 unlink( fits_catalog_filename );                           // make sure there is no such file
 fits_create_file( &fptr, fits_catalog_filename, &status ); /* create new file */
 fits_create_tbl( fptr, BINARY_TBL, (long)n_good, 3, ttype, tform, tunit, "OBJECTS", &status );
 fits_write_col( fptr, TFLOAT, 1, 1, 1, (long)n_good, X, &status );
 fits_write_col( fptr, TFLOAT, 2, 1, 1, (long)n_good, Y, &status );
 fits_write_col( fptr, TFLOAT, 3, 1, 1, (long)n_good, FLUX, &status );
 fits_close_file( fptr, &status ); // close file
 fits_report_error( stderr, status );

 free( X );
 free( Y );
 free( FLUX );

 return 0;
}
