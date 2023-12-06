#include <stdio.h>
#include <string.h>
#include "../fitsio.h"
#include "../vast_limits.h"

// Function to delete TR WCS keywords inserted by PinPoint
void delete_tr_keywords( fitsfile *fptr, int *status ) {
 char card[FLEN_CARD];
 char tr_keyword[FLEN_KEYWORD];
 int i, j; // counters

 // Loop over axes 1 and 2
 for ( i= 1; i <= 2; i++ ) {
  // Loop over possible keyword indices
  for ( j= 0; j <= 14; j++ ) { // Assuming the range of j is 0-14 as per your data
   // Construct the keyword for the current TR coefficient.
   snprintf( tr_keyword, sizeof( tr_keyword ), "TR%d_%d", i, j );
   // Check if the keyword exists before attempting to delete
   if ( fits_read_card( fptr, tr_keyword, card, status ) == KEY_NO_EXIST ) {
    *status= 0; // Reset status if the keyword is not found
   } else {
    fits_delete_key( fptr, tr_keyword, status );
    if ( *status ) {
     fits_report_error( stderr, *status ); // Report the error if one occurred
     *status= 0;                           // Reset status after reporting
    }
   }
  }
 }
}

// Function to delete TPV WCS keywords
void delete_tpv_keywords( fitsfile *fptr, int *status ) {
 char card[FLEN_CARD];
 char tpv_keyword[FLEN_KEYWORD];
 int i, j;                     // counters
 for ( i= 1; i <= 2; i++ ) {   // Loop over axes 1 and 2
  for ( j= 0; j <= 39; j++ ) { // Loop over possible keyword indices
   // Construct the keyword for the current TPV coefficient.
   snprintf( tpv_keyword, sizeof( tpv_keyword ), "PV%d_%d", i, j );
   // Check if the keyword exists before attempting to delete
   if ( fits_read_card( fptr, tpv_keyword, card, status ) == KEY_NO_EXIST ) {
    *status= 0; // Reset status if the keyword is not found
   } else {
    fits_delete_key( fptr, tpv_keyword, status );
    if ( *status ) {
     fits_report_error( stderr, *status ); // Report the error if one occurred
     *status= 0;                           // Reset status after reporting
    }
   }
  }
 }
}

// Function to delete a range of polynomial coefficient keywords
void delete_poly_coeff( const char *key_base, int max_order, fitsfile *fptr, int *status ) {
 char card[FLEN_CARD];
 char coeff_keyword[FLEN_KEYWORD];
 int i, j; // counters
 for ( i= 0; i <= max_order; i++ ) {
  for ( j= 0; j <= max_order; j++ ) {
   // Construct the keyword for the current coefficient.
   snprintf( coeff_keyword, sizeof( coeff_keyword ), "%s_%d_%d", key_base, i, j );
   // Check if the keyword exists before attempting to delete
   if ( fits_read_card( fptr, coeff_keyword, card, status ) == KEY_NO_EXIST ) {
    *status= 0; // Reset status if the keyword is not found
   } else {
    fits_delete_key( fptr, coeff_keyword, status );
    if ( *status ) {
     fits_report_error( stderr, *status ); // Report the error if one occurred
     *status= 0;                           // Reset status after reporting
    }
   }
  }
 }
}

void strip_wcs_sip_keywords( fitsfile *fptr, int *status ) {
 const int assumed_max_order= 10; // Assumed max order for SIP polynomials

 char card[FLEN_CARD];

 long order= 0;

 char key_base[3]= { '\0' };

 char opus_keyword[FLEN_KEYWORD]; // for HST-sppecific OPUS keys

 // SIP-specific 'ORDER' keywords
 const char *sip_order_keywords[]= { "A_ORDER", "B_ORDER", "AP_ORDER", "BP_ORDER", "A_DMAX", "B_DMAX", NULL };

 // List of standard WCS keywords to be deleted
 const char *wcs_keywords[]= {
     // List of standard WCS keywords
     "WCSAXES", "CRPIX1", "CRPIX2", "CRVAL1", "CRVAL2",
     "CTYPE1", "CTYPE2", "CUNIT1", "CUNIT2", "CDELT1",
     "CDELT2", "CROTA1", "CROTA2", "EQUINOX", "RADECSYS",
     "LONPOLE", "LATPOLE", "RESTFRQ", "RESTWAV",
     "CD1_1", "CD1_2", "CD2_1", "CD2_2",
     "PC1_1", "PC1_2", "PC2_1", "PC2_2",
     "RADESYS", "WCSVERS", "WCSNAME", "PLTSOLVD", "EPOCH", "PA",
     NULL };

 const char **keyword;

 const char **order_keyword;

 for ( keyword= wcs_keywords; *keyword != NULL; keyword++ ) {
  // delete key using its original name
  if ( fits_read_card( fptr, *keyword, card, status ) != KEY_NO_EXIST ) {
   fits_delete_key( fptr, *keyword, status );
   if ( *status ) {
    fits_report_error( stderr, *status );
    *status= 0;
   }
  } else {
   *status= 0;
  }
  // below we delete keys with some modifications to the original name
  // HST-specific OPUS WCS keywords
  if ( strlen( *keyword ) < 8 ) {
   snprintf( opus_keyword, sizeof( opus_keyword ), "%sO", *keyword );
   if ( fits_read_card( fptr, opus_keyword, card, status ) != KEY_NO_EXIST ) {
    fits_delete_key( fptr, opus_keyword, status );
    if ( *status ) {
     fits_report_error( stderr, *status );
     *status= 0;
    }
   } else {
    *status= 0;
   }
  }
  //
  // TESS-specific physical WCS keywords
  if ( strlen( *keyword ) < 8 ) {
   snprintf( opus_keyword, sizeof( opus_keyword ), "%sP", *keyword );
   if ( fits_read_card( fptr, opus_keyword, card, status ) != KEY_NO_EXIST ) {
    fits_delete_key( fptr, opus_keyword, status );
    if ( *status ) {
     fits_report_error( stderr, *status );
     *status= 0;
    }
   } else {
    *status= 0;
   }
  }
  //
 }

 // Deleting SIP-specific 'ORDER' keywords and coefficients
 for ( order_keyword= sip_order_keywords; *order_keyword != NULL; order_keyword++ ) {
  // Check for ORDER keyword and determine the order
  if ( fits_read_key( fptr, TLONG, *order_keyword, &order, NULL, status ) != KEY_NO_EXIST ) {
   // Delete the ORDER keyword
   fits_delete_key( fptr, *order_keyword, status );
   if ( *status ) {
    fits_report_error( stderr, *status );
    *status= 0;
   }
  } else {
   *status= 0;
   order= assumed_max_order; // Assume maximum order if ORDER keyword is missing
  }

  // Determine the base keyword for coefficients (e.g., "A", "B", "AP", "BP")
  if ( strncmp( *order_keyword, "AP_", 3 ) == 0 || strncmp( *order_keyword, "BP_", 3 ) == 0 ) {
   strncpy( key_base, *order_keyword, 2 ); // "AP" or "BP"
  } else {
   strncpy( key_base, *order_keyword, 1 ); // "A" or "B"
  }

  // Delete all coefficients for this base keyword and order
  delete_poly_coeff( key_base, order, fptr, status );
 }
}

int main( int argc, char **argv ) {
 fitsfile *fptr;                 // FITS file pointer
 int status= 0;                  // CFITSIO status
 char filename[FILENAME_LENGTH]; // FITS file name
 int num_hdus, hdu_type, current_hdu;

 if ( argc != 2 ) {
  fprintf( stderr, "Usage: %s <fitsfile_to_strip_wcs_keywords_from.fits>\n", argv[0] );
  return EXIT_FAILURE;
 }

 strncpy( filename, argv[1], FILENAME_LENGTH - 1 );
 filename[FILENAME_LENGTH - 1]= '\0'; // Ensure null termination

 // Open the FITS file for editing (read-write mode)
 fits_open_file( &fptr, filename, READWRITE, &status );
 if ( status ) {
  fits_report_error( stderr, status ); // Report any error on opening
  return status;
 }

 // Get the number of HDUs in the file
 fits_get_num_hdus( fptr, &num_hdus, &status );

 // Iterate over all HDUs
 for ( current_hdu= 1; current_hdu <= num_hdus; current_hdu++ ) {
  // Move to the current HDU
  fits_movabs_hdu( fptr, current_hdu, &hdu_type, &status );
  if ( status ) {
   fits_report_error( stderr, status ); // Report any error on moving to HDU
   continue;                            // Skip to next HDU on error
  }

  // Call the functions to strip WCS and SIP keywords for the current HDU
  strip_wcs_sip_keywords( fptr, &status );
  delete_tpv_keywords( fptr, &status );
  delete_tr_keywords( fptr, &status );

  if ( status ) {
   fits_report_error( stderr, status ); // Report any error on processing
   status= 0;                           // Reset status for the next HDU
  }
 }

 // Write any changes to the file and close it
 fits_close_file( fptr, &status );
 if ( status ) {
  fits_report_error( stderr, status ); // Report any error on closing
  return status;
 }

 printf( "WCS keywords have been successfully stripped from all HDUs in the file.\n" );
 return EXIT_SUCCESS;
}
