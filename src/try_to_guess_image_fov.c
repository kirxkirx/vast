#define _GNU_SOURCE /* for memmem(). See feature_test_macros(7) */
#include <string.h>
// these should go first, ohterwise GCC will complain about implicit declaration of memmem

// Standard header files
#include <stdio.h>
#include <stdlib.h>
#include <libgen.h> /* for basename() */
#include <math.h>
// CFITSIO
#include "fitsio.h" // we use a local copy of this file because we use a local copy of cfitsio
// VaST's own header files
#include "vast_limits.h"
#include "fitsfile_read_check.h"

#define MAX_FOV_ARCMIN 7200 // 120 deg.
#define MIN_FOV_ARCMIN 5

#define FOV_DEBUG_MESSAGES

int is_it_a_photopate_scan_from_SAI_collection_with_the_basic_header( char *fitsfilename, double *estimated_fov_arcmin ) {
 double JD;
 char telescop[1024];
 char telescop_comment[1024];
 int status;
 fitsfile *fptr;
 
 status = 0;
 
 fits_open_file( &fptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  return status;
 }
 fits_read_key( fptr, TDOUBLE, "JD", &JD, NULL, &status );
 if ( 0 != status ) {
  status= 0;
  fits_read_key( fptr, TDOUBLE, "JDMID", &JD, NULL, &status );
  if ( 0 != status ) {
   fits_close_file( fptr, &status );
   return 1;
  }
 }
 // Check that JD is in a reasonable range for a SAI photoplate 1850 - 2000
 if ( JD < 2396759.0 || JD > 2451545.0 ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 // Check that there are no other commonly found keywords, otherwise this is probably not a SAI scan
 fits_read_key( fptr, TSTRING, "TELESCOP", telescop, telescop_comment, &status );
 if ( 0 == status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 status= 0;
 fits_read_key( fptr, TSTRING, "DATE-OBS", telescop, telescop_comment, &status );
 if ( 0 == status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 status= 0;
 fits_read_key( fptr, TSTRING, "TIME-OBS", telescop, telescop_comment, &status );
 if ( 0 == status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 status= 0;
 fits_read_key( fptr, TSTRING, "START", telescop, telescop_comment, &status );
 if ( 0 == status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 status= 0;
 fits_read_key( fptr, TSTRING, "UT-START", telescop, telescop_comment, &status );
 if ( 0 == status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 status= 0;

 ( *estimated_fov_arcmin )= 40;

 fits_close_file( fptr, &status );
 return 0;
}

int try_to_recognize_Zeiss2_with_FLIcam( char *fitsfilename, double *estimated_fov_arcmin ) {
 double xpixsz;
 double ypixsz;
 int xbinning;
 int ybinning;
 long naxes[2];
 char swowner[1024];
 char swowner_comment[1024];
 int status;
 fitsfile *fptr;
 int naxis;

 status = 0;
 
 fits_open_file( &fptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  return status;
 }

 fits_read_key( fptr, TSTRING, "SWOWNER", swowner, swowner_comment, &status );
 if ( 0 != status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( 0 != strncasecmp( swowner, "Microsoft", 1024 - 1 ) && 0 != strncasecmp( swowner, "alex", 1024 - 1 ) ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 fits_read_key( fptr, TDOUBLE, "XPIXSZ", &xpixsz, NULL, &status );
 if ( 0 != status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( xpixsz != 18.0 ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 fits_read_key( fptr, TDOUBLE, "YPIXSZ", &ypixsz, NULL, &status );
 if ( 0 != status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( ypixsz != 18.0 ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 fits_read_key( fptr, TINT, "XBINNING", &xbinning, NULL, &status );
 if ( 0 != status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( xbinning != 2 ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 fits_read_key( fptr, TINT, "YBINNING", &ybinning, NULL, &status );
 if ( 0 != status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( ybinning != 2 ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 fits_get_img_dim( fptr, &naxis, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  fits_close_file( fptr, &status );
  return status;
 }
 
 fits_get_img_size( fptr, 2, naxes, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  fits_close_file( fptr, &status );
  return status;
 }
 
 if ( naxes[0] != 1024 ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 if ( naxes[1] != 1024 ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 ( *estimated_fov_arcmin )= 6.9;

 fits_close_file( fptr, &status );
 return 0;
}

int try_to_recognize_TESS_FFI( char *fitsfilename, double *estimated_fov_arcmin ) {
 char telescop[1024];
 char telescop_comment[1024];
 long naxes[2];
 int hdutype;
 int status;
 fitsfile *fptr;
 int naxis;
 
 status = 0;
 
 fits_open_file( &fptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  return status;
 }

 fits_read_key( fptr, TSTRING, "TELESCOP", telescop, telescop_comment, &status );
 if ( 0 != status ) {
  status= 0;
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( 0 != strncasecmp( telescop, "TESS", 4 ) ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 fits_read_key( fptr, TSTRING, "INSTRUME", telescop, telescop_comment, &status );
 if ( 0 != status ) {
  status= 0;
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( 0 != strncasecmp( telescop, "TESS Photometer", 15 ) ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 fits_movabs_hdu( fptr, 2, &hdutype, &status );
 if ( 0 != status ) {
  status= 0;
  fits_close_file( fptr, &status );
  return 1;
 }

 fits_get_img_dim( fptr, &naxis, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  fits_close_file( fptr, &status );
  return status;
 }
 
 fits_get_img_size( fptr, 2, naxes, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  fits_close_file( fptr, &status );
  return status;
 }
 
 if ( naxes[0] != 2136 ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 if ( naxes[1] != 2078 ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 ( *estimated_fov_arcmin )= 710;

 fits_close_file( fptr, &status );
 return 0;
}

int try_to_recognize_MSUcampusObs06m_with_APOGEEcam( char *fitsfilename, double *estimated_fov_arcmin ) {
 double xpixsz;
 double ypixsz;
 int xbinning;
 int ybinning;
 long naxes[2];
 char sitelat[1024];
 char sitelat_comment[1024];
 char sitelong[1024];
 char sitelong_comment[1024];
 int status;
 fitsfile *fptr;
 int naxis;

 status = 0;
 
 fits_open_file( &fptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  return status;
 }

 fits_read_key( fptr, TSTRING, "SITELAT", sitelat, sitelat_comment, &status );
 if ( 0 != status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( 0 != strncasecmp( sitelat, "42 42 23", 1024 - 1 ) ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 fits_read_key( fptr, TSTRING, "SITELONG", sitelong, sitelong_comment, &status );
 if ( 0 != status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( 0 != strncasecmp( sitelong, "-25 37 56", 1024 - 1 ) ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 fits_read_key( fptr, TDOUBLE, "XPIXSZ", &xpixsz, NULL, &status );
 if ( 0 != status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( xpixsz != 13.0 ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 fits_read_key( fptr, TDOUBLE, "YPIXSZ", &ypixsz, NULL, &status );
 if ( 0 != status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( ypixsz != 13.0 ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 fits_read_key( fptr, TINT, "XBINNING", &xbinning, NULL, &status );
 if ( 0 != status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( xbinning != 1 ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 fits_read_key( fptr, TINT, "YBINNING", &ybinning, NULL, &status );
 if ( 0 != status ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( ybinning != 1 ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 fits_get_img_dim( fptr, &naxis, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  fits_close_file( fptr, &status );
  return status;
 }
 
 fits_get_img_size( fptr, 2, naxes, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  fits_close_file( fptr, &status );
  return status;
 }
 
 if ( naxes[0] != 1024 ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 if ( naxes[1] != 1024 ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 ( *estimated_fov_arcmin )= 9.3;

 fits_close_file( fptr, &status );
 return 0;
}

int try_to_recognize_telescop_keyword( char *fitsfilename, double *estimated_fov_arcmin ) {
 char telescop[FLEN_VALUE];
 char telescop_comment[FLEN_COMMENT];
 char roi[FLEN_VALUE];
 char roi_comment[FLEN_COMMENT];
 char instrume[FLEN_VALUE];
 char instrume_comment[FLEN_COMMENT];
 char *pointer_to_the_key_start;
 int status;
 fitsfile *fptr;
 int env_var_good;
 
 status = 0;
 env_var_good = 0;
 
 if ( NULL != getenv( "TELESCOP" ) ) {
  strncpy( telescop, getenv( "TELESCOP" ), FLEN_VALUE );
  telescop[FLEN_VALUE - 1]= '\0';
  if ( strlen( telescop ) > 1 ) {
   env_var_good= 1;
  }
 }
 
 if ( env_var_good == 0 ) {
  fits_open_file( &fptr, fitsfilename, READONLY, &status );
  if ( 0 != status ) {
   fits_report_error( stderr, status );
   fits_clear_errmsg();
   return status;
  }
  fits_read_key( fptr, TSTRING, "TELESCOP", telescop, telescop_comment, &status );
  if ( 0 != status ) {
   fits_close_file( fptr, &status );
   return 1;
  }
  fits_close_file( fptr, &status );
 }
 
 if ( 0 == strncasecmp( telescop, "Lens  2.8/170", FLEN_VALUE - 1 ) ) {
  ( *estimated_fov_arcmin )= 180.0;
  return 0;
 }
 
 pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "Lens", 4 );
 if ( pointer_to_the_key_start != NULL ) {
  ( *estimated_fov_arcmin )= 180.0;
  return 0;
 }
 
 pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "LENS", 4 );
 if ( pointer_to_the_key_start != NULL ) {
  ( *estimated_fov_arcmin )= 180.0;
  return 0;
 }
 
 pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "HST", 3 );
 if ( pointer_to_the_key_start != NULL ) {
  ( *estimated_fov_arcmin )= 2.0;
  return 0;
 }

 if ( strlen( telescop ) >= 12 ) {
  pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "0.45-m f/2.8", 12 );
  if ( pointer_to_the_key_start != NULL ) {
   ( *estimated_fov_arcmin )= 90.0;
   return 0;
  }
 }

 if ( strlen( telescop ) >= 10 ) {
  pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "Aristarchos", 10 );
  if ( pointer_to_the_key_start != NULL ) {
   ( *estimated_fov_arcmin )= 5.0;
   return 0;
  }
 }

 if ( strlen( telescop ) >= 9 ) {
  pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "SOAR 4.1m", 9 );
  if ( pointer_to_the_key_start != NULL ) {
   ( *estimated_fov_arcmin )= 3.2;
   fits_open_file( &fptr, fitsfilename, READONLY, &status );
   if ( 0 == status ) {
    fits_read_key( fptr, TSTRING, "ROI", roi, roi_comment, &status );
    if ( 0 == status ) {
     if ( strlen( roi ) >= 11 ) {
      pointer_to_the_key_start= (char *)memmem( roi, strlen( roi ), "Imaging 2x2", 11 );
      if ( pointer_to_the_key_start != NULL ) {
       ( *estimated_fov_arcmin )= 5.0;
      }
     }
    }
    status= 0;
    fits_close_file( fptr, &status );
   }
   status= 0;

   fprintf( stderr, "\n\n\nWARNING! WARNING! WARNING!\nThis is a SOAR 4.1m image.\nRemember to trim the black areas around the actual image or it will not be plate-solved!\nYou may trim it by running something like\n  util/fitscopy %s[700:1370] test.fit  # 'Spectroscopic 2x2' ROI\nor\n  util/fitscopy %s[290:1300,290:1300] test.fit  # 'Imaging 2x2' ROI\n\n\n", fitsfilename, fitsfilename );
   return 0;
  }
 }

 if ( strlen( telescop ) >= 28 ) {
  pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "CMO SAI MSU ASA RC600 PHOTON", 28 );
  if ( pointer_to_the_key_start != NULL ) {
   ( *estimated_fov_arcmin )= 20.0;
   return 0;
  }
 }

 if ( strlen( telescop ) >= 6 ) {
  pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "Sintez", 6 );
  if ( pointer_to_the_key_start != NULL ) {
   ( *estimated_fov_arcmin )= 26.0;
   return 0;
  }
 }

 if ( strlen( telescop ) >= 10 ) {
  pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "NMW_camera", 10 );
  if ( pointer_to_the_key_start != NULL ) {
   ( *estimated_fov_arcmin )= 350.0;
   return 0;
  }
 }
 if ( strlen( telescop ) >= 4 ) {
  pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "STAS", 4 );
  if ( pointer_to_the_key_start != NULL ) {
   ( *estimated_fov_arcmin )= 350.0;
   return 0;
  }
 }
 
 if ( strlen( telescop ) >= 10 ) {
  pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "STL-11000M", 10 );
  if ( pointer_to_the_key_start != NULL ) {
   ( *estimated_fov_arcmin )= 600.0;
   return 0;
  }
 }
 
 if ( strlen( telescop ) >= 7 ) {
  pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "NMW-STL", 7 );
  if ( pointer_to_the_key_start != NULL ) {
   ( *estimated_fov_arcmin )= 600.0;
   return 0;
  }
 }

 if ( strlen( telescop ) >= 12 ) {
  pointer_to_the_key_start= (char *)memmem( telescop, strlen( telescop ), "F=135mm, 2.0", 12 );
  if ( pointer_to_the_key_start != NULL ) {
   ( *estimated_fov_arcmin )= 350.0;
   fits_open_file( &fptr, fitsfilename, READONLY, &status );
   if ( 0 == status ) {
    fits_read_key( fptr, TSTRING, "INSTRUME", instrume, instrume_comment, &status );
    if ( 0 == status ) {
     if ( strlen( instrume ) >= 13 ) {
      pointer_to_the_key_start= (char *)memmem( instrume, strlen( instrume ), "SBIG STL-11000", 13 );
      if ( pointer_to_the_key_start != NULL ) {
       ( *estimated_fov_arcmin )= 600.0;
       return 0;
      }
     }
    }
    fits_close_file( fptr, &status );
   }
   status= 0;
   return 0;
  }
 }

 return 1;
}

int look_for_focallen_keyword( char *fitsfilename, double *estimated_fov_arcmin ) {
 int status;
 double internal_estimated_fov_arcmin;
 fitsfile *fptr;
 double focallen;
 double ypixsz;
 double minor_axis_of_CCD_chip_mm;
 long naxes[2];
 int naxis;

 status = 0;
 
 fits_open_file( &fptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  return status;
 }
 
 fits_read_key( fptr, TDOUBLE, "FOCALLEN", &focallen, NULL, &status );
 if ( 0 != status ) {
  status= 0;
  fits_clear_errmsg();
  fits_read_key( fptr, TDOUBLE, "FOC_LEN", &focallen, NULL, &status );
  if ( 0 != status ) {
   fits_clear_errmsg();
   fits_close_file( fptr, &status );
   return status;
  }
 }

 fits_get_img_dim( fptr, &naxis, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  fits_close_file( fptr, &status );
  return status;
 }
 
 fits_get_img_size( fptr, 2, naxes, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  fits_close_file( fptr, &status );
  return status;
 }

 if ( focallen < 20 || focallen > 20000 ) {
  fits_close_file( fptr, &status );
  return 1;
 }

 fits_read_key( fptr, TDOUBLE, "YPIXSZ", &ypixsz, NULL, &status );
 if ( 0 != status ) {
  status= 0;
  fits_clear_errmsg();
  minor_axis_of_CCD_chip_mm= 14.0;
#ifdef FOV_DEBUG_MESSAGES
  fprintf( stderr, "Using the default guess for the CCD chip size.\n" );
#endif
 } else {
  if ( ypixsz > 1.0 && ypixsz < 100.0 ) {
   minor_axis_of_CCD_chip_mm= (double)naxes[1] * ypixsz / 1000.0;
#ifdef FOV_DEBUG_MESSAGES
   fprintf( stderr, "The minor axis of the CCD chip should be %.1lf mm based on the derived pixel size of %.1lf um\n", minor_axis_of_CCD_chip_mm, ypixsz );
#endif
  } else {
   minor_axis_of_CCD_chip_mm= 14.0;
#ifdef FOV_DEBUG_MESSAGES
   fprintf( stderr, "Using the default guess for the CCD chip size.\n" );
#endif
  }
 }

 internal_estimated_fov_arcmin= atan2( minor_axis_of_CCD_chip_mm, focallen ) * 60.0 * 180.0 / M_PI;
#ifdef FOV_DEBUG_MESSAGES
 fprintf( stderr, "Internal estimated FoV %.1lf'\n", internal_estimated_fov_arcmin );
#endif

 if ( internal_estimated_fov_arcmin > MIN_FOV_ARCMIN && internal_estimated_fov_arcmin < MAX_FOV_ARCMIN ) {
  ( *estimated_fov_arcmin )= internal_estimated_fov_arcmin;
  fits_close_file( fptr, &status );
  return 0;
 } else {
  fits_close_file( fptr, &status );
  return 1;
 }
}

int look_for_existing_wcs_header( char *fitsfilename, double *estimated_fov_arcmin ) {
 int status;
 fitsfile *fptr;
 long naxes[2];
 int i;
 int No_of_wcs_keys;
 int wcs_keys_left;
 char **wcs_key;
 double scale_arcsec_pix;
 double CDELT1;
 double xrefval, yrefval, xrefpix, yrefpix, xinc, yinc, rot;
 char coordtype[512];
 double internal_estimated_fov_arcmin;
 int j;
 int naxis;

 status = 0;
 scale_arcsec_pix = 0.0;
 
 fits_open_file( &fptr, fitsfilename, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  return status;
 }
 
 fits_get_img_dim( fptr, &naxis, &status );
 if ( 0 != status ) {
  fits_clear_errmsg();
  fits_close_file( fptr, &status );
  return status;
 }
 
 if ( naxis < 2 ) {
  fits_close_file( fptr, &status );
  return 1;
 }
 
 fits_get_img_size( fptr, 2, naxes, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  fits_close_file( fptr, &status );
  return status;
 }
 
 CDELT1= 0.0;
 fits_read_key( fptr, TDOUBLE, "CDELT1", &CDELT1, NULL, &status );
 if ( 0 != status ) {
  status= 0;
  fits_clear_errmsg();
  CDELT1= 0.0;
 }
 
 xinc= 0.0;
 fits_read_img_coord( fptr, &xrefval, &yrefval, &xrefpix, &yrefpix, &xinc, &yinc, &rot, coordtype, &status );
 if ( status == APPROX_WCS_KEY ) {
  status= 0;
  fits_clear_errmsg();
 }
 if ( status != 0 ) {
  xinc= 0.0;
  status= 0;
  fits_clear_errmsg();
 }

 fits_get_hdrspace( fptr, &No_of_wcs_keys, &wcs_keys_left, &status );
 if ( No_of_wcs_keys < 5 ) {
  fprintf( stderr, "ERROR: No_of_wcs_keys < 5 \n" );
  exit( EXIT_FAILURE );
 }
 wcs_key= malloc( No_of_wcs_keys * sizeof( char * ) );
 if ( wcs_key == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for wcs_key(try_to_guess_image_fov)\n" );
  exit( EXIT_FAILURE );
 }
 
 wcs_key[0]= (char *)malloc( FLEN_CARD * sizeof( char ) );
 if ( wcs_key[0] == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for wcs_key[0](try_to_guess_image_fov)\n" );
  exit( EXIT_FAILURE );
 }
 memset( wcs_key[0], 0, FLEN_CARD * sizeof( char ) );
 
 for ( i= 1; i < No_of_wcs_keys; i++ ) {
  wcs_key[i]= (char *)malloc( FLEN_CARD * sizeof( char ) );
  if ( wcs_key[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for wcs_key[i](try_to_guess_image_fov)\n" );
   exit( EXIT_FAILURE );
  }
  memset( wcs_key[i], 0, FLEN_CARD * sizeof( char ) );
  fits_read_record( fptr, i, wcs_key[i], &status );
 }
 fits_close_file( fptr, &status );

 for ( i= 1; i < No_of_wcs_keys; i++ ) {
  if ( strlen( wcs_key[i] ) < 7 ) {
   continue;
  }
  if ( wcs_key[i][0] == 'C' && wcs_key[i][1] == 'O' && wcs_key[i][2] == 'M' && wcs_key[i][3] == 'M' && wcs_key[i][4] == 'E' && wcs_key[i][5] == 'N' && wcs_key[i][6] == 'T' ) {
   if ( strlen( wcs_key[i] ) < 23 )
    continue;
   if ( wcs_key[i][7] == ' ' && wcs_key[i][8] == 's' && wcs_key[i][9] == 'c' && wcs_key[i][10] == 'a' && wcs_key[i][11] == 'l' && wcs_key[i][12] == 'e' && wcs_key[i][13] == ':' )
    if ( 1 == sscanf( wcs_key[i], "COMMENT scale: %lf arcsec/pix", &scale_arcsec_pix ) ) {
     ( *estimated_fov_arcmin )= scale_arcsec_pix * MIN( naxes[0], naxes[1] ) / 60.0;
     ( *estimated_fov_arcmin )= ( *estimated_fov_arcmin ) - 0.1 * ( *estimated_fov_arcmin );
     for ( j= 1; j < No_of_wcs_keys; j++ ) {
      free( wcs_key[j] );
     }
     free( wcs_key[0] );
     free( wcs_key );
     return 0;
    }
  }
 }

 for ( j= 1; j < No_of_wcs_keys; j++ ) {
  free( wcs_key[j] );
 }
 free( wcs_key[0] );
 free( wcs_key );

 if ( xinc != 0.0 && xinc != 1.0 ) {
  internal_estimated_fov_arcmin= fabs( 60.0 * xinc * (double)naxes[0] );
  internal_estimated_fov_arcmin= internal_estimated_fov_arcmin - 0.1 * internal_estimated_fov_arcmin;
  if ( MIN_FOV_ARCMIN < internal_estimated_fov_arcmin && internal_estimated_fov_arcmin < MAX_FOV_ARCMIN ) {
   ( *estimated_fov_arcmin )= internal_estimated_fov_arcmin;
   return 0;
  }
 }

 if ( CDELT1 != 0.0 ) {
  internal_estimated_fov_arcmin= fabs( 60.0 * CDELT1 * (double)naxes[0] );
  internal_estimated_fov_arcmin= internal_estimated_fov_arcmin - 0.1 * internal_estimated_fov_arcmin;
  if ( MIN_FOV_ARCMIN < internal_estimated_fov_arcmin && internal_estimated_fov_arcmin < MAX_FOV_ARCMIN ) {
   ( *estimated_fov_arcmin )= internal_estimated_fov_arcmin;
   return 0;
  }
 }

 return 1;
}

int main( int argc, char **argv ) {
 FILE *image_details_logfile;
 char fitsfile_name[FILENAME_LENGTH];
 double estimated_fov_arcmin;
 char exp_start_date[MAX_LOG_STR_LENGTH];
 char exp_start_time[MAX_LOG_STR_LENGTH];
 char status[MAX_LOG_STR_LENGTH];
 char full_path_to_fits_image[MAX_LOG_STR_LENGTH];
 double exp, jd, ap, rotation;
 int detected, matched;
 char name_of_wcs_solved_reference_image[MAX_LOG_STR_LENGTH];
 char name_of_fits_image[FILENAME_LENGTH];
 
 estimated_fov_arcmin = 40.0;

 if ( argc != 2 ) {
  fprintf( stderr, "This program will make a naive attempt to guess image field of view in arcminutes based on various circumstantial evidence.\n Usage: %s my_image.fits\n", argv[0] );
  return 1;
 }

 strncpy( fitsfile_name, argv[1], FILENAME_LENGTH );
 fitsfile_name[FILENAME_LENGTH - 1]= '\0';
 if ( 0 != fitsfile_read_check( fitsfile_name ) ) {
  fprintf( stderr, "ERROR: %s is not a readbale FITS image!\n", fitsfile_name );
  return 1;
 }

 if ( 0 == look_for_existing_wcs_header( fitsfile_name, &estimated_fov_arcmin ) ) {
  fprintf( stdout, "%4.0lf\n", estimated_fov_arcmin );
#ifdef FOV_DEBUG_MESSAGES
  fprintf( stderr, "The guess is based on the existing WCS header.\n" );
#endif
  return 0;
 }

 if ( 0 == try_to_recognize_telescop_keyword( fitsfile_name, &estimated_fov_arcmin ) ) {
  fprintf( stdout, "%4.0lf\n", estimated_fov_arcmin );
#ifdef FOV_DEBUG_MESSAGES
  fprintf( stderr, "The guess is based on the recognized TELESCOP keyword.\n" );
#endif
  return 0;
 }

 if ( 0 == look_for_focallen_keyword( fitsfile_name, &estimated_fov_arcmin ) ) {
  fprintf( stdout, "%4.0lf\n", estimated_fov_arcmin );
#ifdef FOV_DEBUG_MESSAGES
  fprintf( stderr, "The guess is based on the FOCALLEN keyword.\n" );
#endif
  return 0;
 }

 if ( 0 == try_to_recognize_Zeiss2_with_FLIcam( fitsfile_name, &estimated_fov_arcmin ) ) {
  fprintf( stdout, "%4.0lf\n", estimated_fov_arcmin );
#ifdef FOV_DEBUG_MESSAGES
  fprintf( stderr, "That's Zeiss2 with FLI camera.\n" );
#endif
  return 0;
 }

 if ( 0 == try_to_recognize_TESS_FFI( fitsfile_name, &estimated_fov_arcmin ) ) {
  fprintf( stdout, "%4.0lf\n", estimated_fov_arcmin );
#ifdef FOV_DEBUG_MESSAGES
  fprintf( stderr, "That's a TESS FFI.\n" );
#endif
  return 0;
 }

 if ( 0 == try_to_recognize_MSUcampusObs06m_with_APOGEEcam( fitsfile_name, &estimated_fov_arcmin ) ) {
  fprintf( stdout, "%4.0lf\n", estimated_fov_arcmin );
#ifdef FOV_DEBUG_MESSAGES
  fprintf( stderr, "That's MSU Campus Observatory with the APOGEE camera.\n" );
#endif
  return 0;
 }

 if ( 0 == is_it_a_photopate_scan_from_SAI_collection_with_the_basic_header( fitsfile_name, &estimated_fov_arcmin ) ) {
  fprintf( stdout, "%4.0lf\n", estimated_fov_arcmin );
#ifdef FOV_DEBUG_MESSAGES
  fprintf( stderr, "That's a digitized plate from the SAI collaction.\n" );
#endif
  return 0;
 }

 image_details_logfile= fopen( "vast_image_details.log", "r" );
 if ( NULL != image_details_logfile ) {
  if ( 10 == fscanf( image_details_logfile, "exp_start= %s %s  exp= %lf  JD= %lf  ap= %lf  rotation= %lf  *detected= %d  *matched= %d  status=%s  %s", exp_start_date, exp_start_time, &exp, &jd, &ap, &rotation, &detected, &matched, status, full_path_to_fits_image ) ) {
   if ( 0 != strncmp( fitsfile_name, full_path_to_fits_image, FILENAME_LENGTH ) ) {
    strncpy( name_of_fits_image, basename( full_path_to_fits_image ), FILENAME_LENGTH );
    fitsfile_name[FILENAME_LENGTH - 1]= '\0';
    if ( strlen( name_of_fits_image ) < 5 ) {
     fprintf( stderr, "ERROR: too short image name: %s\n", name_of_fits_image );
     return 1;
    }
    if ( name_of_fits_image[0] == 'w' && name_of_fits_image[1] == 'c' && name_of_fits_image[2] == 's' && name_of_fits_image[3] == '_' )
     sprintf( name_of_wcs_solved_reference_image, "%s", name_of_fits_image );
    else
     sprintf( name_of_wcs_solved_reference_image, "wcs_%s", name_of_fits_image );
    name_of_wcs_solved_reference_image[FILENAME_LENGTH - 1]= '\0';
    if ( 0 == fitsfile_read_check( name_of_wcs_solved_reference_image ) ) {
     fseek( image_details_logfile, 0, SEEK_SET );
     while ( 0 < fscanf( image_details_logfile, "exp_start= %s %s  exp= %lf  JD= %lf  ap= %lf  rotation= %lf  *detected= %d  *matched= %d  status=%s  %s\n", exp_start_date, exp_start_time, &exp, &jd, &ap, &rotation, &detected, &matched, status, full_path_to_fits_image ) ) {
      if ( 0 == strncmp( fitsfile_name, full_path_to_fits_image, FILENAME_LENGTH ) ) {
       if ( 0 == look_for_existing_wcs_header( name_of_wcs_solved_reference_image, &estimated_fov_arcmin ) ) {
        fprintf( stdout, "%4.0lf\n", estimated_fov_arcmin );
        fclose( image_details_logfile );
#ifdef FOV_DEBUG_MESSAGES
        fprintf( stderr, "The guess is based on the previously solved image %s\n", name_of_wcs_solved_reference_image );
#endif
        return 0;
       }
       break;
      }
     }
    } else {
     fprintf( stderr, "This was an attempt to see if there is a plate-solved reference image from the same image series. Never mind.\n" );
    }
   }
  }
  fclose( image_details_logfile );
 }

 fprintf( stdout, "%4.0lf\n", estimated_fov_arcmin );
#ifdef FOV_DEBUG_MESSAGES
 fprintf( stderr, "That's the default guess value.\n" );
#endif

 return 1;
}
