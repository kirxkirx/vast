#include <stdio.h>
#include <string.h>
#include <ctype.h> // for tolower() in card_contains_substring_ci()
#include "../fitsio.h"
#include "../vast_limits.h"

// Case-insensitive substring test, portable (avoids strcasestr / _GNU_SOURCE).
static int card_contains_substring_ci( const char *card, const char *needle_lowercase ) {
 char lowercard[FLEN_CARD];
 int i;
 for ( i= 0; card[i] != '\0' && i < FLEN_CARD - 1; i++ ) {
  lowercard[i]= (char)tolower( (unsigned char)card[i] );
 }
 lowercard[i]= '\0';
 if ( strstr( lowercard, needle_lowercase ) != NULL ) {
  return 1;
 }
 return 0;
}

// Delete EVERY card with this keyword name, not just the first one.
//
// A FITS header may legitimately carry the same WCS keyword more than once:
// inserting a new solution into a header that already had one leaves two
// cards, and the Sco6 NMW reference image in the SIP_refit_policy_test
// dataset is a real specimen with two WCSAXES cards. cfitsio's
// fits_delete_key() removes only the first match, so a single pass used to
// leave the duplicate behind - which made stripping non-idempotent and, worse,
// could leave a partial WCS in an image that is supposed to look unsolved.
// util/identify.sh decides whether an image is already solved by looking for
// exactly these keywords, so a survivor can defeat the forced re-solve that
// util/solve_plate_with_best_sip_order.sh depends on.
//
// The loop is bounded: a header cannot hold more cards than this, and the
// bound also guarantees we cannot spin forever if a delete silently fails.
#define STRIP_WCS_MAX_DUPLICATE_CARDS 1000
static void delete_all_cards_with_this_keyword( fitsfile *fptr, const char *keyname, int *status ) {
 char card[FLEN_CARD];
 int iteration;

 for ( iteration= 0; iteration < STRIP_WCS_MAX_DUPLICATE_CARDS; iteration++ ) {
  *status= 0;
  if ( fits_read_card( fptr, (char *)keyname, card, status ) == KEY_NO_EXIST ) {
   *status= 0;
   return;
  }
  *status= 0;
  fits_delete_key( fptr, (char *)keyname, status );
  if ( *status ) {
   fits_report_error( stderr, *status );
   *status= 0;
   return; // do not spin on a card we cannot remove
  }
 }
 return;
}

// Delete HISTORY/COMMENT cards that mark the image as solved by Astrometry.net
// (or the AIJ "Astronomy.net" variant). util/identify.sh decides whether to
// blindly trust an existing WCS by grep-ing the header for these markers, so
// leaving them in place after stripping the WCS would make a freshly-stripped
// image still look "already solved" and skip the re-solve. Removing them lets a
// WCS-stripped image be treated as unsolved and re-solved with the desired
// settings (e.g. a different SIP polynomial order).
void delete_astrometrynet_provenance_keywords( fitsfile *fptr, int *status ) {
 char card[FLEN_CARD];
 int nkeys;
 int keynum;

 nkeys= 0;
 fits_get_hdrspace( fptr, &nkeys, NULL, status );
 if ( *status ) {
  fits_report_error( stderr, *status );
  *status= 0;
  return;
 }

 keynum= 1;
 while ( keynum <= nkeys ) {
  if ( fits_read_record( fptr, keynum, card, status ) ) {
   fits_report_error( stderr, *status );
   *status= 0;
   keynum++;
   continue;
  }
  // Only commentary cards carry the Astrometry.net provenance text.
  if ( ( strncmp( card, "HISTORY", 7 ) == 0 || strncmp( card, "COMMENT", 7 ) == 0 ) &&
       ( card_contains_substring_ci( card, "astrometry.net" ) == 1 || card_contains_substring_ci( card, "astronomy.net" ) == 1 ) ) {
   fits_delete_record( fptr, keynum, status );
   if ( *status ) {
    fits_report_error( stderr, *status );
    *status= 0;
    keynum++; // avoid an infinite loop if a record cannot be deleted
   } else {
    nkeys--; // a record was removed; re-check the same position
   }
  } else {
   keynum++;
  }
 }
}

// Function to delete TR WCS keywords inserted by PinPoint
void delete_tr_keywords( fitsfile *fptr, int *status ) {
 char tr_keyword[FLEN_KEYWORD];
 int i, j; // counters
 char suffix;

 // Loop over axes 1 and 2
 for ( i= 1; i <= 2; i++ ) {
  // Loop over possible keyword indices
  for ( j= 0; j <= 14; j++ ) { // Assuming the range of j is 0-14 as per your data
   // Construct the keyword for the current TR coefficient.
   snprintf( tr_keyword, sizeof( tr_keyword ), "TR%d_%d", i, j );
   delete_all_cards_with_this_keyword( fptr, tr_keyword, status );

   // Also check for alternate WCS versions with A-Z suffixes
   for ( suffix= 'A'; suffix <= 'Z'; suffix++ ) {
    snprintf( tr_keyword, sizeof( tr_keyword ), "TR%d_%d%c", i, j, suffix );
    delete_all_cards_with_this_keyword( fptr, tr_keyword, status );
   }
  }
 }
}

// Function to delete TPV WCS keywords
void delete_tpv_keywords( fitsfile *fptr, int *status ) {
 char tpv_keyword[FLEN_KEYWORD];
 int i, j; // counters
 char suffix;

 for ( i= 1; i <= 2; i++ ) {   // Loop over axes 1 and 2
  for ( j= 0; j <= 39; j++ ) { // Loop over possible keyword indices
   // Construct the keyword for the current TPV coefficient.
   snprintf( tpv_keyword, sizeof( tpv_keyword ), "PV%d_%d", i, j );
   delete_all_cards_with_this_keyword( fptr, tpv_keyword, status );

   // Also check for alternate WCS versions with A-Z suffixes
   for ( suffix= 'A'; suffix <= 'Z'; suffix++ ) {
    snprintf( tpv_keyword, sizeof( tpv_keyword ), "PV%d_%d%c", i, j, suffix );
    delete_all_cards_with_this_keyword( fptr, tpv_keyword, status );
   }
  }
 }
}

// Function to delete a range of polynomial coefficient keywords
void delete_poly_coeff( const char *key_base, int max_order, fitsfile *fptr, int *status ) {
 char coeff_keyword[FLEN_KEYWORD];
 int i, j; // counters
 char suffix;

 for ( i= 0; i <= max_order; i++ ) {
  for ( j= 0; j <= max_order; j++ ) {
   // Construct the keyword for the current coefficient.
   snprintf( coeff_keyword, sizeof( coeff_keyword ), "%s_%d_%d", key_base, i, j );
   delete_all_cards_with_this_keyword( fptr, coeff_keyword, status );

   // Also check for alternate WCS versions with A-Z suffixes
   for ( suffix= 'A'; suffix <= 'Z'; suffix++ ) {
    snprintf( coeff_keyword, sizeof( coeff_keyword ), "%s_%d_%d%c", key_base, i, j, suffix );
    delete_all_cards_with_this_keyword( fptr, coeff_keyword, status );
   }
  }
 }
}

void strip_wcs_sip_keywords( fitsfile *fptr, int *status ) {
 const int assumed_max_order= 10; // Assumed max order for SIP polynomials

 long order= 0;

 char key_base[3]= { '\0' };

 char alt_keyword[FLEN_KEYWORD]; // for alternate WCS keywords

 char suffix;

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
  // delete key using its original name (primary WCS)
  delete_all_cards_with_this_keyword( fptr, *keyword, status );

  // Delete alternate WCS keywords with A-Z suffixes
  for ( suffix= 'A'; suffix <= 'Z'; suffix++ ) {
   if ( strlen( *keyword ) < 8 ) {
    snprintf( alt_keyword, sizeof( alt_keyword ), "%s%c", *keyword, suffix );
    delete_all_cards_with_this_keyword( fptr, alt_keyword, status );
   }
  }

  // HST-specific OPUS WCS keywords (keep existing functionality)
  if ( strlen( *keyword ) < 8 ) {
   snprintf( alt_keyword, sizeof( alt_keyword ), "%sO", *keyword );
   delete_all_cards_with_this_keyword( fptr, alt_keyword, status );
  }

  // TESS-specific physical WCS keywords (keep existing functionality)
  if ( strlen( *keyword ) < 8 ) {
   snprintf( alt_keyword, sizeof( alt_keyword ), "%sP", *keyword );
   delete_all_cards_with_this_keyword( fptr, alt_keyword, status );
  }
 }

 // Deleting SIP-specific 'ORDER' keywords and coefficients
 for ( order_keyword= sip_order_keywords; *order_keyword != NULL; order_keyword++ ) {
  // Check for ORDER keyword and determine the order (primary WCS)
  if ( fits_read_key( fptr, TLONG, *order_keyword, &order, NULL, status ) != KEY_NO_EXIST ) {
   // Delete the ORDER keyword (every copy of it)
   *status= 0;
   delete_all_cards_with_this_keyword( fptr, *order_keyword, status );
  } else {
   *status= 0;
   order= assumed_max_order; // Assume maximum order if ORDER keyword is missing
  }

  // Check for alternate WCS ORDER keywords with A-Z suffixes
  for ( suffix= 'A'; suffix <= 'Z'; suffix++ ) {
   if ( strlen( *order_keyword ) < 8 ) {
    snprintf( alt_keyword, sizeof( alt_keyword ), "%s%c", *order_keyword, suffix );
    if ( fits_read_key( fptr, TLONG, alt_keyword, &order, NULL, status ) != KEY_NO_EXIST ) {
     *status= 0;
     delete_all_cards_with_this_keyword( fptr, alt_keyword, status );
    } else {
     *status= 0;
    }
   }
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
  delete_astrometrynet_provenance_keywords( fptr, &status );

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

 printf( "WCS keywords and Astrometry.net provenance markers have been successfully stripped from all HDUs in the file.\n" );
 return EXIT_SUCCESS;
}
