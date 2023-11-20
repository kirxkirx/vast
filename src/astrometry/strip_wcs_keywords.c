#include <stdio.h>
#include <string.h>
#include "../fitsio.h"
#include "../vast_limits.h"

// Function to delete TPV WCS keywords
void delete_tpv_keywords(fitsfile *fptr, int *status) {
    char tpv_keyword[FLEN_KEYWORD];
    for (int i = 1; i <= 2; i++) { // Loop over axes 1 and 2
        for (int j = 0; j <= 39; j++) { // Loop over possible keyword indices
            // Construct the keyword for the current TPV coefficient.
            snprintf(tpv_keyword, sizeof(tpv_keyword), "PV%d_%d", i, j);
            // Check if the keyword exists before attempting to delete
            char card[FLEN_CARD];
            if (fits_read_card(fptr, tpv_keyword, card, status) == KEY_NO_EXIST) {
                *status = 0; // Reset status if the keyword is not found
            } else {
                fits_delete_key(fptr, tpv_keyword, status);
                if (*status) {
                    fits_report_error(stderr, *status); // Report the error if one occurred
                    *status = 0; // Reset status after reporting
                }
            }
        }
    }
}

// Function to delete a range of polynomial coefficient keywords
void delete_poly_coeff(const char *key_base, int max_order, fitsfile *fptr, int *status) {
    char coeff_keyword[FLEN_KEYWORD];
    for (int i = 0; i <= max_order; i++) {
        for (int j = 0; j <= max_order; j++) {
            // Construct the keyword for the current coefficient.
            snprintf(coeff_keyword, sizeof(coeff_keyword), "%s_%d_%d", key_base, i, j);
            // Check if the keyword exists before attempting to delete
            char card[FLEN_CARD];
            if (fits_read_card(fptr, coeff_keyword, card, status) == KEY_NO_EXIST) {
                *status = 0; // Reset status if the keyword is not found
            } else {
                fits_delete_key(fptr, coeff_keyword, status);
                if (*status) {
                    fits_report_error(stderr, *status); // Report the error if one occurred
                    *status = 0; // Reset status after reporting
                }
            }
        }
    }
}

void strip_wcs_sip_keywords(fitsfile *fptr, int *status) {
    const int assumed_max_order = 10; // Assumed max order for SIP polynomials

    // List of standard WCS keywords to be deleted
    const char *wcs_keywords[] = {
        // List of standard WCS keywords
        "WCSAXES", "CRPIX1", "CRPIX2", "CRVAL1", "CRVAL2",
        "CTYPE1", "CTYPE2", "CUNIT1", "CUNIT2", "CDELT1",
        "CDELT2", "CROTA1", "CROTA2", "EQUINOX", "RADECSYS",
        "LONPOLE", "LATPOLE", "RESTFRQ", "RESTWAV",
        "CD1_1", "CD1_2", "CD2_1", "CD2_2",
        "PC1_1", "PC1_2", "PC2_1", "PC2_2",
        "RADESYS", "WCSVERS", "WCSNAME", 
        NULL
    };

    for (const char **keyword = wcs_keywords; *keyword != NULL; keyword++) {
        char card[FLEN_CARD];
        if (fits_read_card(fptr, *keyword, card, status) != KEY_NO_EXIST) {
            fits_delete_key(fptr, *keyword, status);
            if (*status) {
                fits_report_error(stderr, *status);
                *status = 0;
            }
        } else {
            *status = 0;
        }
    }
    
    // SIP-specific 'ORDER' keywords
    const char *sip_order_keywords[] = {"A_ORDER", "B_ORDER", "AP_ORDER", "BP_ORDER", "A_DMAX", "B_DMAX", NULL};

    // Deleting SIP-specific 'ORDER' keywords and coefficients
    for (const char **order_keyword = sip_order_keywords; *order_keyword != NULL; order_keyword++) {
        long order = 0;
        // Check for ORDER keyword and determine the order
        if (fits_read_key(fptr, TLONG, *order_keyword, &order, NULL, status) != KEY_NO_EXIST) {
            // Delete the ORDER keyword
            fits_delete_key(fptr, *order_keyword, status);
            if (*status) {
                fits_report_error(stderr, *status);
                *status = 0;
            }
        } else {
            *status = 0;
            order = assumed_max_order; // Assume maximum order if ORDER keyword is missing
        }

        // Determine the base keyword for coefficients (e.g., "A", "B", "AP", "BP")
        char key_base[3] = {'\0'};
        if (strncmp(*order_keyword, "AP_", 3) == 0 || strncmp(*order_keyword, "BP_", 3) == 0) {
            strncpy(key_base, *order_keyword, 2); // "AP" or "BP"
        } else {
            strncpy(key_base, *order_keyword, 1); // "A" or "B"
        }

        // Delete all coefficients for this base keyword and order
        delete_poly_coeff(key_base, order, fptr, status);
    }
}


int main(int argc, char **argv) {
    fitsfile *fptr;   // FITS file pointer
    int status = 0;   // CFITSIO status
    char filename[FILENAME_LENGTH]; // FITS file name

    if (argc != 2) {
        fprintf(stderr, "Usage: %s <fitsfile_to_strip_wcs_keywords_from.fits>\n", argv[0]);
        return EXIT_FAILURE;
    }

    strncpy(filename, argv[1], FILENAME_LENGTH - 1);
    filename[FILENAME_LENGTH - 1] = '\0'; // Ensure null termination

    // Open the FITS file for editing (read-write mode)
    fits_open_file(&fptr, filename, READWRITE, &status);
    if (status) {
        fits_report_error(stderr, status); // Report any error on opening
        return status;
    }

    // Call the function to strip WCS and SIP keywords
    strip_wcs_sip_keywords(fptr, &status);
    if (status) {
        fits_report_error(stderr, status); // Report any error on processing
        // Close file if there was an error
        fits_close_file(fptr, &status);
        return status;
    }
    
    // Call the function to strip TPV keywords
    delete_tpv_keywords(fptr, &status);
    if (status) {
        fits_report_error(stderr, status); // Report any error on processing
        // Close file if there was an error
        fits_close_file(fptr, &status);
        return status;
    }

    // Write any changes to the file and close it
    fits_close_file(fptr, &status);
    if (status) {
        fits_report_error(stderr, status); // Report any error on closing
        return status;
    }

    printf("WCS keywords have been successfully stripped from the file.\n");
    return EXIT_SUCCESS;
}