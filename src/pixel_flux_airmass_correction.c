// pixel_flux_airmass_correction.c
//
// Correct image pixel counts for DIFFERENTIAL atmospheric extinction across a wide field of view.
//
// Physics: along a line of sight with airmass X starlight is attenuated following the
// Bouguer (Beer-Lambert) law  F_obs = F_0 * exp(-tau_0 * X) = F_0 * 10^(-0.4*k*X)
// where tau_0 is the zenith optical depth and k = 2.5*log10(e)*tau_0 = 1.0857*tau_0 is the
// extinction coefficient in magnitudes per unit airmass. The optical depth is linear in
// airmass (airmass is by definition the slant-path column density normalized to the zenith
// one), so the transmitted flux is exponential in airmass. To renormalize a pixel observed
// at airmass X(x,y) to the airmass of the frame center X_c, its counts are multiplied by
//   10^( 0.4 * k * (X(x,y) - X_c) )
// The frame center itself is unchanged: the absolute extinction at the center stays absorbed
// by the usual per-image photometric zero-point calibration.
//
// The airmass map is computed from the image WCS (TAN approximation; SIP distortion terms are
// ignored as their effect on this smooth correction is negligible), the observing site
// coordinates (FITS header keywords or command-line override) and the mid-exposure time
// (gettime(), same header interpretation as the rest of VaST). Airmass model: Young (1994,
// Applied Optics 33, 1108), a function of the true (unrefracted) zenith distance - appropriate
// here since the WCS is fit to catalog star positions and thus gives true directions.
//
// The correction is recorded in the FITS header HISTORY; an input image already carrying this
// HISTORY record is refused (unless --force) to prevent accidental double correction.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>
#include <libgen.h> // for basename()
#include <getopt.h>
#include <unistd.h> // for unlink()

#include "fitsio.h"
#include "vast_limits.h"
#include "vast_types.h"
#include "ident.h" // for gettime()

// The marker text must fit in the free-text part of a single HISTORY card (72 characters)
// so that the double-correction check can find it with a simple substring search
#define AIRMASS_CORRECTION_HISTORY_MARKER "Airmass flux correction applied by VaST pixel_flux_airmass_correction"

// Pin saturated pixels to the top of the range only if the input image actually reaches
// high counts (protects synthetic low-count test images from being treated as saturated)
#define AIRMASS_CORRECTION_SATURATION_PINNING_MIN_MAXVAL 32767.0

#define AC_DEG2RAD 0.017453292519943295

struct TANWCS {
 double crval1;
 double crval2;
 double crpix1;
 double crpix2;
 double cd11;
 double cd12;
 double cd21;
 double cd22;
};

// Greenwich Mean Sidereal Time in degrees for a given JD(UT)
static double gmst_deg( double jd_ut ) {
 double t;
 double gmst;
 t= ( jd_ut - 2451545.0 ) / 36525.0;
 gmst= 280.46061837 + 360.98564736629 * ( jd_ut - 2451545.0 ) + 0.000387933 * t * t - t * t * t / 38710000.0;
 gmst= fmod( gmst, 360.0 );
 if ( gmst < 0.0 ) {
  gmst+= 360.0;
 }
 return gmst;
}

// Parse an angle that may be decimal degrees ("33.748239", "-101.958391")
// or sexagesimal ("43 38 58", "-101:57:30.1", "+41 25 34.5").
// A trailing N/E (positive) or S/W (negative) letter is accepted.
// Returns 0 on success.
static int parse_angle_string( const char *instr, double *result_deg ) {
 char buf[128];
 double d, m, s;
 double sign;
 int n;
 size_t i, len, j;
 char suffix;

 if ( instr == NULL || result_deg == NULL ) {
  return 1;
 }
 len= strlen( instr );
 if ( len < 1 || len > 127 ) {
  return 1;
 }
 strncpy( buf, instr, sizeof( buf ) );
 buf[sizeof( buf ) - 1]= '\0';

 // replace ':' and ',' separators with spaces
 for ( i= 0; i < strlen( buf ); i++ ) {
  if ( buf[i] == ':' || buf[i] == ',' ) {
   buf[i]= ' ';
  }
 }

 // detect and remove a trailing hemisphere letter
 sign= 1.0;
 suffix= ' ';
 for ( j= strlen( buf ); j > 0; j-- ) {
  if ( buf[j - 1] == ' ' ) {
   continue;
  }
  if ( 0 != isalpha( (int)buf[j - 1] ) ) {
   suffix= (char)toupper( (int)buf[j - 1] );
   buf[j - 1]= ' ';
  }
  break;
 }
 if ( suffix == 'S' || suffix == 'W' ) {
  sign= -1.0;
 } else {
  if ( suffix != ' ' && suffix != 'N' && suffix != 'E' ) {
   return 1; // unexpected letter in the angle string
  }
 }

 // detect a leading minus sign (applies to the whole sexagesimal value)
 for ( i= 0; i < strlen( buf ); i++ ) {
  if ( buf[i] == ' ' ) {
   continue;
  }
  if ( buf[i] == '-' ) {
   sign= -1.0 * sign;
   buf[i]= ' ';
  }
  if ( buf[i] == '+' ) {
   buf[i]= ' ';
  }
  break;
 }

 d= m= s= 0.0;
 n= sscanf( buf, "%lf %lf %lf", &d, &m, &s );
 if ( n < 1 ) {
  return 1;
 }
 if ( d < 0.0 ) {
  return 1; // the sign was supposed to be stripped above
 }
 if ( n > 1 && ( m < 0.0 || m >= 60.0 ) ) {
  return 1;
 }
 if ( n > 2 && ( s < 0.0 || s >= 60.0 ) ) {
  return 1;
 }
 ( *result_deg )= sign * ( d + m / 60.0 + s / 3600.0 );
 return 0;
}

// Read a TAN WCS from a FITS header. Returns 0 on success.
static int read_tan_wcs( fitsfile *fptr, struct TANWCS *wcs ) {
 int status;
 int status_cd;
 char ctype1[FLEN_VALUE];
 char ctype2[FLEN_VALUE];
 double cdelt1, cdelt2, crota2;

 status= 0;
 fits_read_key( fptr, TSTRING, "CTYPE1", ctype1, NULL, &status );
 fits_read_key( fptr, TSTRING, "CTYPE2", ctype2, NULL, &status );
 if ( status != 0 ) {
  return 1; // no WCS
 }
 if ( 0 != strncmp( ctype1, "RA---TAN", 8 ) || 0 != strncmp( ctype2, "DEC--TAN", 8 ) ) {
  fprintf( stderr, "ERROR: unsupported WCS projection CTYPE1='%s' CTYPE2='%s' (expecting RA---TAN/DEC--TAN)\n", ctype1, ctype2 );
  return 1;
 }
 fits_read_key( fptr, TDOUBLE, "CRVAL1", &wcs->crval1, NULL, &status );
 fits_read_key( fptr, TDOUBLE, "CRVAL2", &wcs->crval2, NULL, &status );
 fits_read_key( fptr, TDOUBLE, "CRPIX1", &wcs->crpix1, NULL, &status );
 fits_read_key( fptr, TDOUBLE, "CRPIX2", &wcs->crpix2, NULL, &status );
 if ( status != 0 ) {
  fprintf( stderr, "ERROR: incomplete WCS (missing CRVAL/CRPIX keywords)\n" );
  return 1;
 }

 // prefer the CD matrix, fall back to CDELT + CROTA2
 status_cd= 0;
 fits_read_key( fptr, TDOUBLE, "CD1_1", &wcs->cd11, NULL, &status_cd );
 fits_read_key( fptr, TDOUBLE, "CD1_2", &wcs->cd12, NULL, &status_cd );
 fits_read_key( fptr, TDOUBLE, "CD2_1", &wcs->cd21, NULL, &status_cd );
 fits_read_key( fptr, TDOUBLE, "CD2_2", &wcs->cd22, NULL, &status_cd );
 if ( status_cd != 0 ) {
  status_cd= 0;
  fits_read_key( fptr, TDOUBLE, "CDELT1", &cdelt1, NULL, &status_cd );
  fits_read_key( fptr, TDOUBLE, "CDELT2", &cdelt2, NULL, &status_cd );
  if ( status_cd != 0 ) {
   fprintf( stderr, "ERROR: incomplete WCS (no CD matrix and no CDELT keywords)\n" );
   return 1;
  }
  crota2= 0.0;
  status_cd= 0;
  fits_read_key( fptr, TDOUBLE, "CROTA2", &crota2, NULL, &status_cd );
  wcs->cd11= cdelt1 * cos( crota2 * AC_DEG2RAD );
  wcs->cd12= -1.0 * cdelt2 * sin( crota2 * AC_DEG2RAD );
  wcs->cd21= cdelt1 * sin( crota2 * AC_DEG2RAD );
  wcs->cd22= cdelt2 * cos( crota2 * AC_DEG2RAD );
 }
 return 0;
}

// Inverse gnomonic (TAN) projection: pixel to celestial coordinates (degrees)
static void pixel_to_radec( struct TANWCS *wcs, double x, double y, double *ra_deg, double *dec_deg ) {
 double u, v, xi, eta, ra0_rad, dec0_rad, denom, ra;
 u= x - wcs->crpix1;
 v= y - wcs->crpix2;
 xi= ( wcs->cd11 * u + wcs->cd12 * v ) * AC_DEG2RAD;
 eta= ( wcs->cd21 * u + wcs->cd22 * v ) * AC_DEG2RAD;
 ra0_rad= wcs->crval1 * AC_DEG2RAD;
 dec0_rad= wcs->crval2 * AC_DEG2RAD;
 denom= cos( dec0_rad ) - eta * sin( dec0_rad );
 ra= ra0_rad + atan2( xi, denom );
 ( *dec_deg )= atan2( eta * cos( dec0_rad ) + sin( dec0_rad ), sqrt( xi * xi + denom * denom ) ) / AC_DEG2RAD;
 ra= fmod( ra / AC_DEG2RAD, 360.0 );
 if ( ra < 0.0 ) {
  ra+= 360.0;
 }
 ( *ra_deg )= ra;
 return;
}

// Altitude and azimuth (degrees; azimuth from North through East) of a J2000 position.
// Precession/nutation/aberration are deliberately ignored: the correction is differential
// across the frame and normalized at the frame center, so their contribution cancels.
static void radec_to_alt_az( double ra_deg, double dec_deg, double lat_deg, double lst_deg, double *alt_deg, double *az_deg ) {
 double ha_rad, lat_rad, dec_rad, sinalt, az_rad;
 ha_rad= ( lst_deg - ra_deg ) * AC_DEG2RAD;
 lat_rad= lat_deg * AC_DEG2RAD;
 dec_rad= dec_deg * AC_DEG2RAD;
 sinalt= sin( lat_rad ) * sin( dec_rad ) + cos( lat_rad ) * cos( dec_rad ) * cos( ha_rad );
 if ( sinalt > 1.0 ) {
  sinalt= 1.0;
 }
 if ( sinalt < -1.0 ) {
  sinalt= -1.0;
 }
 ( *alt_deg )= asin( sinalt ) / AC_DEG2RAD;
 az_rad= atan2( -1.0 * sin( ha_rad ) * cos( dec_rad ), sin( dec_rad ) - sinalt * sin( lat_rad ) );
 ( *az_deg )= fmod( az_rad / AC_DEG2RAD, 360.0 );
 if ( ( *az_deg ) < 0.0 ) {
  ( *az_deg )+= 360.0;
 }
 return;
}

// Airmass as a function of the true (unrefracted) altitude, Young (1994, ApOpt 33, 1108)
static double airmass_young1994( double alt_deg ) {
 double cz, cz2, cz3;
 if ( alt_deg <= 0.0 ) {
  return 40.0; // below the horizon; larger than the formula value at the horizon (~32)
 }
 cz= cos( ( 90.0 - alt_deg ) * AC_DEG2RAD );
 cz2= cz * cz;
 cz3= cz2 * cz;
 return ( 1.002432 * cz2 + 0.148386 * cz + 0.0096467 ) / ( cz3 + 0.149864 * cz2 + 0.0102963 * cz + 0.000303978 );
}

// Try to find the observing site coordinates in the FITS header.
// Returns 0 on success and reports which keyword pair was used.
static int find_site_in_header( fitsfile *fptr, double *lat_deg, double *long_deg, char *used_keywords, size_t used_keywords_size ) {
 static const char *lat_keys[5]= { "SITELAT", "LAT-OBS", "OBSLAT", "LATITUDE", "OBSGEO-B" };
 static const char *long_keys[5]= { "SITELONG", "LONG-OBS", "OBSLONG", "LONGITUD", "OBSGEO-L" };
 int ipair;
 int status;
 char latstr[FLEN_VALUE];
 char longstr[FLEN_VALUE];
 double lat, lon;

 for ( ipair= 0; ipair < 5; ipair++ ) {
  status= 0;
  fits_read_key( fptr, TSTRING, (char *)lat_keys[ipair], latstr, NULL, &status );
  fits_read_key( fptr, TSTRING, (char *)long_keys[ipair], longstr, NULL, &status );
  if ( status != 0 ) {
   continue;
  }
  if ( 0 != parse_angle_string( latstr, &lat ) ) {
   continue;
  }
  if ( 0 != parse_angle_string( longstr, &lon ) ) {
   continue;
  }
  if ( fabs( lat ) > 90.0 || fabs( lon ) > 360.0 ) {
   continue;
  }
  ( *lat_deg )= lat;
  ( *long_deg )= lon;
  if ( used_keywords != NULL ) {
   snprintf( used_keywords, used_keywords_size, "%s/%s FITS header keywords", lat_keys[ipair], long_keys[ipair] );
  }
  return 0;
 }
 return 1;
}

// Check the in-memory copy of the header for the airmass-correction HISTORY record
static int header_has_history_marker( char **header_keys, int num_keys ) {
 int i;
 for ( i= 0; i < num_keys; i++ ) {
  if ( header_keys[i] == NULL ) {
   continue;
  }
  if ( 0 != strncmp( header_keys[i], "HISTORY ", 8 ) ) {
   continue;
  }
  if ( NULL != strstr( header_keys[i], AIRMASS_CORRECTION_HISTORY_MARKER ) ) {
   return 1;
  }
 }
 return 0;
}

// Check if a header record is a structural keyword that should not be copied to the output
static int is_structural_keyword( const char *record ) {
 if ( strncmp( record, "SIMPLE  ", 8 ) == 0 )
  return 1;
 if ( strncmp( record, "BITPIX  ", 8 ) == 0 )
  return 1;
 if ( strncmp( record, "NAXIS   ", 8 ) == 0 )
  return 1;
 if ( strncmp( record, "NAXIS1  ", 8 ) == 0 )
  return 1;
 if ( strncmp( record, "NAXIS2  ", 8 ) == 0 )
  return 1;
 if ( strncmp( record, "EXTEND  ", 8 ) == 0 )
  return 1;
 if ( strncmp( record, "BZERO   ", 8 ) == 0 )
  return 1;
 if ( strncmp( record, "BSCALE  ", 8 ) == 0 )
  return 1;
 if ( strncmp( record, "END", 3 ) == 0 && ( record[3] == ' ' || record[3] == '\0' ) )
  return 1;
 return 0;
}

// Write the output image preserving the input BITPIX, copying the saved header records
// (minus the structural keywords) and appending the correction HISTORY.
static int write_output_image( const char *filename, float *data, long *naxes, int bitpix,
                               char **header_keys, int num_keys,
                               double applied_k, double center_airmass,
                               double site_lat_deg, double site_long_deg ) {
 fitsfile *fptr;
 int status;
 long npixels;
 long i;
 int ii;
 char history[FLEN_CARD];
 float val;
 short *short_data;
 int *int_data;
 double *double_data;
 unsigned char *byte_data;
 double bzero_val;
 double bscale_val;

 status= 0;
 npixels= naxes[0] * naxes[1];

 // remove a leftover output file if present
 unlink( filename );

 fits_create_file( &fptr, filename, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  return 1;
 }
 fits_create_img( fptr, bitpix, 2, naxes, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  fits_close_file( fptr, &status );
  return 1;
 }

 switch ( bitpix ) {
 case BYTE_IMG:
  byte_data= malloc( npixels * sizeof( unsigned char ) );
  if ( byte_data == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for the output conversion\n" );
   fits_close_file( fptr, &status );
   return 1;
  }
  for ( i= 0; i < npixels; i++ ) {
   val= data[i];
   if ( val < 0.0f ) {
    val= 0.0f;
   }
   if ( val > 255.0f ) {
    val= 255.0f;
   }
   byte_data[i]= (unsigned char)( val + 0.5f );
  }
  fits_write_img( fptr, TBYTE, 1, npixels, byte_data, &status );
  free( byte_data );
  break;
 case SHORT_IMG:
  // unsigned 16-bit convention: BZERO=32768, manual conversion
  bzero_val= 32768.0;
  bscale_val= 1.0;
  short_data= malloc( npixels * sizeof( short ) );
  if ( short_data == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for the output conversion\n" );
   fits_close_file( fptr, &status );
   return 1;
  }
  fits_update_key( fptr, TDOUBLE, "BZERO", &bzero_val, "offset for unsigned 16-bit", &status );
  fits_update_key( fptr, TDOUBLE, "BSCALE", &bscale_val, "scale factor", &status );
  for ( i= 0; i < npixels; i++ ) {
   val= data[i];
   if ( val < 0.0f ) {
    val= 0.0f;
   }
   if ( val > 65535.0f ) {
    val= 65535.0f;
   }
   // floor(val+0.5) rounding so that physical 0 maps to stored -32768 exactly
   short_data[i]= (short)floor( (double)val + 0.5 - 32768.0 );
  }
  fits_set_bscale( fptr, 1.0, 0.0, &status );
  fits_write_img( fptr, TSHORT, 1, npixels, short_data, &status );
  fits_set_bscale( fptr, 1.0, 32768.0, &status );
  free( short_data );
  break;
 case LONG_IMG:
  int_data= malloc( npixels * sizeof( int ) );
  if ( int_data == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for the output conversion\n" );
   fits_close_file( fptr, &status );
   return 1;
  }
  for ( i= 0; i < npixels; i++ ) {
   int_data[i]= (int)floor( (double)data[i] + 0.5 );
  }
  fits_write_img( fptr, TINT, 1, npixels, int_data, &status );
  free( int_data );
  break;
 case DOUBLE_IMG:
  double_data= malloc( npixels * sizeof( double ) );
  if ( double_data == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for the output conversion\n" );
   fits_close_file( fptr, &status );
   return 1;
  }
  for ( i= 0; i < npixels; i++ ) {
   double_data[i]= (double)data[i];
  }
  fits_write_img( fptr, TDOUBLE, 1, npixels, double_data, &status );
  free( double_data );
  break;
 case FLOAT_IMG:
 default:
  fits_write_img( fptr, TFLOAT, 1, npixels, data, &status );
  break;
 }
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  fits_close_file( fptr, &status );
  return 1;
 }

 for ( ii= 1; ii < num_keys; ii++ ) {
  if ( header_keys[ii] == NULL ) {
   continue;
  }
  if ( !is_structural_keyword( header_keys[ii] ) ) {
   fits_write_record( fptr, header_keys[ii], &status );
   status= 0; // continue on errors
  }
 }

 fits_write_history( fptr, AIRMASS_CORRECTION_HISTORY_MARKER, &status );
 snprintf( history, FLEN_CARD, "airmass_correction: k= %.3lf mag/airmass, frame center airmass= %.3lf", applied_k, center_airmass );
 fits_write_history( fptr, history, &status );
 snprintf( history, FLEN_CARD, "airmass_correction: site lat= %+.6lf deg, lon= %+.6lf deg (east-positive)", site_lat_deg, site_long_deg );
 fits_write_history( fptr, history, &status );

 fits_close_file( fptr, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  return 1;
 }
 return 0;
}

// ---- airmass-aware zero-point fit (--fit-airmass-zeropoint mode) ----

struct CatalogStarForJoin {
 long long mag_key; // MAG_APER rounded to 4 decimal places, times 10000
 double x;
 double y;
 int duplicate;
};

static int compare_catalog_star_keys( const void *a, const void *b ) {
 const struct CatalogStarForJoin *sa= (const struct CatalogStarForJoin *)a;
 const struct CatalogStarForJoin *sb= (const struct CatalogStarForJoin *)b;
 if ( sa->mag_key < sb->mag_key )
  return -1;
 if ( sa->mag_key > sb->mag_key )
  return 1;
 return 0;
}

// Read the additive constant p0 from a calib.txt_param-style file
// (format: fit_function p3 p2 p1 p0; forced_photometry applies p2*x^2 + p1*x + p0).
// Returns 0 on success, 1 on read error, 2 if the calibration is not a pure
// zero-point (the airmass term is defined only against a zero-point calibration).
static int read_calib_param_p0( const char *path, double *p0 ) {
 FILE *f;
 double fit_fn, p3, p2, p1;
 f= fopen( path, "r" );
 if ( f == NULL ) {
  return 1;
 }
 if ( 5 != fscanf( f, "%lf %lf %lf %lf %lf", &fit_fn, &p3, &p2, &p1, p0 ) ) {
  fclose( f );
  return 1;
 }
 fclose( f );
 if ( fabs( p1 - 1.0 ) > 0.001 || fabs( p2 ) > 1e-9 || fabs( p3 ) > 1e-9 ) {
  return 2;
 }
 return 0;
}

// Fit (catalog_mag - instrumental_mag) = A + B*X over the calibration stars of one image
// and print the one-line airmass zero-point result to stdout:
//   STATUS D0 B X_center k N_used airmass_span sigma_fit X_min X_max
// where D0 = A - p0 and k = -B. STATUS is OK or a REJECT_* reason; on reject the
// caller applies no correction (term 0). Diagnostics go to stderr.
// Returns 0 whenever the result line was printed, 1 on operational failure.
static int fit_airmass_zeropoint( const char *calib_txt_path, const char *catalog_path,
                                  const char *calib_param_path, const char *fit_table_path,
                                  struct TANWCS *wcs, double site_lat_deg, double lst_deg,
                                  double center_airmass ) {
 FILE *f;
 FILE *ftab;
 char line[1024];
 struct CatalogStarForJoin *cat_stars;
 struct CatalogStarForJoin search_key;
 struct CatalogStarForJoin *found_star;
 long n_cat_alloc, n_cat, i;
 long n_calib_alloc, n_join;
 double *star_airmass;
 double *star_resid;
 int *star_used;
 double parse_x, parse_y, parse_mag;
 double instr_mag, cat_mag, err_mag;
 double star_ra, star_dec, star_alt, star_az;
 double p0;
 int p0_status;
 int pass;
 long n_used;
 double sx, sy, sxx, sxy, det;
 double fit_A, fit_B, sigma_fit, sigma_B;
 double resid_from_fit;
 double xmin, xmax, span;
 double k_fitted, d0;
 char status_string[64];

 cat_stars= NULL;
 star_airmass= NULL;
 star_resid= NULL;
 star_used= NULL;
 fit_A= fit_B= sigma_fit= sigma_B= 0.0;
 xmin= xmax= span= 0.0;
 k_fitted= d0= 0.0;
 n_used= 0;
 strncpy( status_string, "OK", sizeof( status_string ) );

 // the constant zero-point that the forced photometry tool will apply
 p0= 0.0;
 p0_status= read_calib_param_p0( calib_param_path, &p0 );
 if ( p0_status == 1 ) {
  fprintf( stderr, "ERROR: cannot read the zero-point calibration file %s\n", calib_param_path );
  return 1;
 }
 if ( p0_status == 2 ) {
  fprintf( stderr, "WARNING: %s is not a pure zero-point calibration - airmass term disabled\n", calib_param_path );
  fprintf( stdout, "REJECT_NONLINEAR_CALIB 0 0 %.4lf 0 0 0 0 0 0\n", center_airmass );
  return 0;
 }

 // read the SExtractor catalog of this image (10 columns: NUMBER RA Dec X Y FLUX FLUXERR MAG MAGERR FLAGS)
 f= fopen( catalog_path, "r" );
 if ( f == NULL ) {
  fprintf( stderr, "WARNING: cannot open the star catalog %s - airmass term disabled\n", catalog_path );
  fprintf( stdout, "REJECT_NO_POSITIONS 0 0 %.4lf 0 0 0 0 0 0\n", center_airmass );
  return 0;
 }
 n_cat_alloc= 0;
 while ( NULL != fgets( line, sizeof( line ), f ) ) {
  n_cat_alloc++;
 }
 rewind( f );
 if ( n_cat_alloc < 1 ) {
  fclose( f );
  fprintf( stderr, "WARNING: the star catalog %s is empty - airmass term disabled\n", catalog_path );
  fprintf( stdout, "REJECT_NO_POSITIONS 0 0 %.4lf 0 0 0 0 0 0\n", center_airmass );
  return 0;
 }
 cat_stars= malloc( n_cat_alloc * sizeof( struct CatalogStarForJoin ) );
 if ( cat_stars == NULL ) {
  fclose( f );
  fprintf( stderr, "ERROR: out of memory reading %s\n", catalog_path );
  return 1;
 }
 n_cat= 0;
 while ( NULL != fgets( line, sizeof( line ), f ) ) {
  if ( 3 != sscanf( line, "%*d %*f %*f %lf %lf %*f %*f %lf", &parse_x, &parse_y, &parse_mag ) ) {
   continue;
  }
  cat_stars[n_cat].mag_key= (long long)floor( parse_mag * 10000.0 + 0.5 );
  cat_stars[n_cat].x= parse_x;
  cat_stars[n_cat].y= parse_y;
  cat_stars[n_cat].duplicate= 0;
  n_cat++;
 }
 fclose( f );
 qsort( cat_stars, n_cat, sizeof( struct CatalogStarForJoin ), compare_catalog_star_keys );
 for ( i= 1; i < n_cat; i++ ) {
  if ( cat_stars[i].mag_key == cat_stars[i - 1].mag_key ) {
   cat_stars[i].duplicate= 1;
   cat_stars[i - 1].duplicate= 1;
  }
 }

 // read calib.txt (instrumental_mag catalog_mag err) and join by the 4-decimal instrumental mag
 f= fopen( calib_txt_path, "r" );
 if ( f == NULL ) {
  free( cat_stars );
  fprintf( stderr, "ERROR: cannot open %s\n", calib_txt_path );
  return 1;
 }
 n_calib_alloc= 0;
 while ( NULL != fgets( line, sizeof( line ), f ) ) {
  n_calib_alloc++;
 }
 rewind( f );
 star_airmass= malloc( ( n_calib_alloc + 1 ) * sizeof( double ) );
 star_resid= malloc( ( n_calib_alloc + 1 ) * sizeof( double ) );
 star_used= malloc( ( n_calib_alloc + 1 ) * sizeof( int ) );
 if ( star_airmass == NULL || star_resid == NULL || star_used == NULL ) {
  fclose( f );
  free( cat_stars );
  fprintf( stderr, "ERROR: out of memory reading %s\n", calib_txt_path );
  return 1;
 }
 n_join= 0;
 while ( NULL != fgets( line, sizeof( line ), f ) ) {
  if ( 3 != sscanf( line, "%lf %lf %lf", &instr_mag, &cat_mag, &err_mag ) ) {
   continue;
  }
  search_key.mag_key= (long long)floor( instr_mag * 10000.0 + 0.5 );
  found_star= bsearch( &search_key, cat_stars, n_cat, sizeof( struct CatalogStarForJoin ), compare_catalog_star_keys );
  if ( found_star == NULL ) {
   continue;
  }
  if ( found_star->duplicate == 1 ) {
   continue; // ambiguous join key - identical instrumental mags of different stars
  }
  pixel_to_radec( wcs, found_star->x, found_star->y, &star_ra, &star_dec );
  radec_to_alt_az( star_ra, star_dec, site_lat_deg, lst_deg, &star_alt, &star_az );
  star_airmass[n_join]= airmass_young1994( star_alt );
  star_resid[n_join]= cat_mag - instr_mag;
  star_used[n_join]= 1;
  n_join++;
 }
 fclose( f );
 free( cat_stars );

 if ( n_join < AIRMASS_ZP_MIN_STARS ) {
  fprintf( stderr, "Airmass zero-point fit: only %ld calibration stars joined to catalog positions\n", n_join );
  fprintf( stdout, "REJECT_NO_POSITIONS 0 0 %.4lf 0 %ld 0 0 0 0\n", center_airmass, n_join );
  free( star_airmass );
  free( star_resid );
  free( star_used );
  return 0;
 }

 // least-squares fit resid = A + B*X with one 3-sigma clipping pass
 for ( pass= 1; pass <= 2; pass++ ) {
  sx= sy= sxx= sxy= 0.0;
  n_used= 0;
  for ( i= 0; i < n_join; i++ ) {
   if ( star_used[i] == 0 ) {
    continue;
   }
   sx+= star_airmass[i];
   sy+= star_resid[i];
   sxx+= star_airmass[i] * star_airmass[i];
   sxy+= star_airmass[i] * star_resid[i];
   n_used++;
  }
  det= (double)n_used * sxx - sx * sx;
  if ( n_used < 3 || fabs( det ) < 1e-9 ) {
   fprintf( stderr, "Airmass zero-point fit: degenerate fit (all stars at the same airmass?)\n" );
   fprintf( stdout, "REJECT_NARROW_SPAN 0 0 %.4lf 0 %ld 0 0 0 0\n", center_airmass, n_used );
   free( star_airmass );
   free( star_resid );
   free( star_used );
   return 0;
  }
  fit_B= ( (double)n_used * sxy - sx * sy ) / det;
  fit_A= ( sy * sxx - sx * sxy ) / det;
  sigma_fit= 0.0;
  for ( i= 0; i < n_join; i++ ) {
   if ( star_used[i] == 0 ) {
    continue;
   }
   resid_from_fit= star_resid[i] - ( fit_A + fit_B * star_airmass[i] );
   sigma_fit+= resid_from_fit * resid_from_fit;
  }
  sigma_fit= sqrt( sigma_fit / (double)( n_used - 2 ) );
  sigma_B= sigma_fit * sqrt( (double)n_used / det );
  if ( pass == 1 ) {
   for ( i= 0; i < n_join; i++ ) {
    resid_from_fit= fabs( star_resid[i] - ( fit_A + fit_B * star_airmass[i] ) );
    if ( resid_from_fit > 3.0 * sigma_fit ) {
     star_used[i]= 0;
    } else {
     star_used[i]= 1;
    }
   }
  }
 }

 // airmass range actually covered by the stars used in the fit
 xmin= 1e9;
 xmax= -1e9;
 for ( i= 0; i < n_join; i++ ) {
  if ( star_used[i] == 0 ) {
   continue;
  }
  if ( star_airmass[i] < xmin ) {
   xmin= star_airmass[i];
  }
  if ( star_airmass[i] > xmax ) {
   xmax= star_airmass[i];
  }
 }
 span= xmax - xmin;
 k_fitted= -1.0 * fit_B;
 d0= fit_A - p0;

 // gates: the narrow-field / poor-fit provision
 if ( n_used < AIRMASS_ZP_MIN_STARS ) {
  strncpy( status_string, "REJECT_FEW_STARS", sizeof( status_string ) );
 } else {
  if ( span < AIRMASS_ZP_MIN_AIRMASS_SPAN ) {
   strncpy( status_string, "REJECT_NARROW_SPAN", sizeof( status_string ) );
  } else {
   if ( sigma_B > AIRMASS_ZP_MAX_K_ERR ) {
    strncpy( status_string, "REJECT_NOISY_FIT", sizeof( status_string ) );
   } else {
    if ( k_fitted < AIRMASS_ZP_MIN_K || k_fitted > AIRMASS_ZP_MAX_K ) {
     strncpy( status_string, "REJECT_K_RANGE", sizeof( status_string ) );
    }
   }
  }
 }
 status_string[sizeof( status_string ) - 1]= '\0';

 // per-star table for the diagnostic plotter (residual from the constant zero-point actually applied)
 if ( fit_table_path != NULL && fit_table_path[0] != '\0' ) {
  ftab= fopen( fit_table_path, "w" );
  if ( ftab != NULL ) {
   for ( i= 0; i < n_join; i++ ) {
    fprintf( ftab, "%.4lf %+.4lf %d\n", star_airmass[i], star_resid[i] - p0, star_used[i] );
   }
   fclose( ftab );
  } else {
   fprintf( stderr, "WARNING: cannot write the fit table %s\n", fit_table_path );
  }
 }

 fprintf( stderr, "Airmass zero-point fit: %s  k= %+.4lf +/- %.4lf mag/airmass  N= %ld  airmass span %.4lf-%.4lf  scatter %.4lf mag\n",
          status_string, k_fitted, sigma_B, n_used, xmin, xmax, sigma_fit );
 fprintf( stdout, "%s %+.6lf %+.6lf %.4lf %+.4lf %ld %.4lf %.4lf %.4lf %.4lf\n",
          status_string, d0, fit_B, center_airmass, k_fitted, n_used, span, sigma_fit, xmin, xmax );

 free( star_airmass );
 free( star_resid );
 free( star_used );
 return 0;
}

static void print_usage( char *progname ) {
 fprintf( stderr, "Correct image pixel counts for differential atmospheric extinction (airmass\n" );
 fprintf( stderr, "varying across a wide field of view). Each pixel is multiplied by\n" );
 fprintf( stderr, "10^(0.4*k*(X(x,y)-X_center)) following the Bouguer extinction law, so the\n" );
 fprintf( stderr, "frame center is unchanged while the rest of the frame is renormalized to the\n" );
 fprintf( stderr, "frame-center airmass. The output image preserves the input BITPIX.\n\n" );
 fprintf( stderr, "Usage: %s [options] input.fits [output.fits]\n\n", progname );
 fprintf( stderr, "If output.fits is not specified, ac_<input file name> is written to the current directory.\n\n" );
 fprintf( stderr, "Options:\n" );
 fprintf( stderr, " -k, --extinction <k>  extinction coefficient in mag/airmass (default %.2lf)\n", DEFAULT_EXTINCTION_MAG_PER_AIRMASS );
 fprintf( stderr, " --sitelat <angle>     observing site latitude, decimal degrees or 'dd mm ss'\n" );
 fprintf( stderr, " --sitelong <angle>    observing site longitude, east-positive, decimal degrees or 'dd mm ss'\n" );
 fprintf( stderr, "                       (the two options override the FITS header keywords and must be used together)\n" );
 fprintf( stderr, " --jd <JD>             override the mid-exposure time (UTC Julian date)\n" );
 fprintf( stderr, " --grid <pix>          airmass evaluation grid step in pixels (default %d)\n", AIRMASS_CORRECTION_GRID_STEP_PIX );
 fprintf( stderr, " --map <map.fits>      also write the applied correction (delta-mag) map as a float FITS image\n" );
 fprintf( stderr, " --print-info          print the time/site/airmass information and exit (no output image)\n" );
 fprintf( stderr, " --predict-list <f>    print 'x y delta_mag airmass alt_deg' for pixel positions listed in a file and exit\n" );
 fprintf( stderr, " --force               process the image even if it carries the airmass-correction HISTORY record\n" );
 fprintf( stderr, " -h, --help            print this message\n\n" );
 fprintf( stderr, "Airmass-aware zero-point fit mode (for forced photometry):\n" );
 fprintf( stderr, " %s --fit-airmass-zeropoint [options] calib.txt catalog.wcscat image.fits\n", progname );
 fprintf( stderr, "  Fits (catalog_mag - instrumental_mag) = A + B*airmass over the calibration stars\n" );
 fprintf( stderr, "  and prints one line: STATUS D0 B X_center k N span sigma X_min X_max\n" );
 fprintf( stderr, "  (term to add to a constant-zero-point calibrated magnitude: D0 + B*X_target;\n" );
 fprintf( stderr, "  on any REJECT_* status apply no term). Extra options for this mode:\n" );
 fprintf( stderr, " --calib-param <file>  the constant zero-point file the term is defined against (default calib.txt_param)\n" );
 fprintf( stderr, " --fit-table <file>    also write per-star rows 'airmass resid used_flag' for the diagnostic plotter\n\n" );
 fprintf( stderr, "Examples:\n" );
 fprintf( stderr, " %s wcs_fd_Sco-03_image.fits\n", progname );
 fprintf( stderr, " %s -k 0.30 --sitelat '43 38 58' --sitelong '41 25 34' wcs_solved_image.fits ac_image.fits\n", progname );
 fprintf( stderr, "\nThe input image must carry its own TAN WCS (plate-solve it with util/wcs_image_calibration.sh first).\n" );
 return;
}

int main( int argc, char **argv ) {
 // command line parameters
 double param_k;
 double param_sitelat;
 double param_sitelong;
 int param_have_cli_site;
 int param_have_cli_sitelat;
 int param_have_cli_sitelong;
 double param_jd;
 int param_have_cli_jd;
 long param_grid;
 char param_map_filename[FILENAME_LENGTH];
 int param_have_map;
 int param_print_info;
 char param_predict_list[FILENAME_LENGTH];
 int param_have_predict_list;
 int param_force;
 int param_fit_airmass_zp;
 char param_calib_param_path[FILENAME_LENGTH];
 char param_fit_table_path[FILENAME_LENGTH];
 char fit_calib_txt_path[FILENAME_LENGTH];
 char fit_catalog_path[FILENAME_LENGTH];
 FILE *info_stream;

 char input_filename[FILENAME_LENGTH];
 char output_filename[FILENAME_LENGTH];
 char input_filename_copy_for_basename[FILENAME_LENGTH];

 // FITS I/O
 fitsfile *fptr;
 int status;
 int naxis;
 long naxes[2];
 int bitpix;
 float *data;
 char **header_keys;
 int num_keys;
 int keys_left;
 int anynul;

 // site/time
 double site_lat_deg, site_long_deg;
 char site_source[128];
 double JD;
 int timesys;
 double dimX, dimY;
 char gettime_stderr_output[1024];
 char gettime_log_output[1024];
 char jd_source[64];

 // WCS and geometry
 struct TANWCS wcs;
 double center_x, center_y;
 double center_ra, center_dec, center_alt, center_az, center_airmass;
 double lst;
 double header_centalt, header_airmass;
 int have_header_centalt, have_header_airmass;

 // airmass/correction grids
 long nx_nodes, ny_nodes, n_steps_x, n_steps_y;
 double *node_x;
 double *node_y;
 double *factor_grid;
 double *delta_grid;
 long inode, jnode;
 double node_ra, node_dec, node_alt, node_az, node_airmass, node_delta;
 double airmass_min, airmass_max, delta_min, delta_max;
 long n_capped_nodes;

 // pixel loop
 long i, j, ix, iy;
 double x, y, wx, wy, cell_width, cell_height, interp_factor;
 float input_pixel_value, output_pixel_value;
 double max_input_pixel_value;
 double saturation_level;
 int do_saturation_pinning;
 long n_pinned_pixels, n_clamped_pixels;
 long pixel_index;

 // predict-list mode
 FILE *predict_file;
 char predict_line[512];
 double predict_x, predict_y, predict_alt, predict_az, predict_airmass, predict_delta;

 // map output
 float *map_data;

 // misc
 int opt;
 int option_index;
 int ii;

 static struct option long_options[]= {
     { "extinction", required_argument, NULL, 'k' },
     { "sitelat", required_argument, NULL, 2 },
     { "sitelong", required_argument, NULL, 3 },
     { "jd", required_argument, NULL, 4 },
     { "grid", required_argument, NULL, 6 },
     { "map", required_argument, NULL, 7 },
     { "predict-list", required_argument, NULL, 8 },
     { "print-info", no_argument, NULL, 9 },
     { "force", no_argument, NULL, 10 },
     { "fit-airmass-zeropoint", no_argument, NULL, 11 },
     { "calib-param", required_argument, NULL, 12 },
     { "fit-table", required_argument, NULL, 13 },
     { "help", no_argument, NULL, 'h' },
     { NULL, 0, NULL, 0 } };

 // defaults
 param_k= DEFAULT_EXTINCTION_MAG_PER_AIRMASS;
 param_sitelat= 0.0;
 param_sitelong= 0.0;
 param_have_cli_site= 0;
 param_have_cli_sitelat= 0;
 param_have_cli_sitelong= 0;
 param_jd= 0.0;
 param_have_cli_jd= 0;
 param_grid= AIRMASS_CORRECTION_GRID_STEP_PIX;
 memset( param_map_filename, 0, FILENAME_LENGTH );
 param_have_map= 0;
 param_print_info= 0;
 memset( param_predict_list, 0, FILENAME_LENGTH );
 param_have_predict_list= 0;
 param_force= 0;
 param_fit_airmass_zp= 0;
 memset( param_calib_param_path, 0, FILENAME_LENGTH );
 strncpy( param_calib_param_path, "calib.txt_param", FILENAME_LENGTH - 1 );
 memset( param_fit_table_path, 0, FILENAME_LENGTH );
 memset( fit_calib_txt_path, 0, FILENAME_LENGTH );
 memset( fit_catalog_path, 0, FILENAME_LENGTH );
 info_stream= stdout;
 status= 0;
 data= NULL;
 header_keys= NULL;
 num_keys= 0;
 have_header_centalt= 0;
 have_header_airmass= 0;
 header_centalt= 0.0;
 header_airmass= 0.0;
 site_lat_deg= site_long_deg= 0.0;
 memset( site_source, 0, sizeof( site_source ) );
 memset( jd_source, 0, sizeof( jd_source ) );

 while ( ( opt= getopt_long( argc, argv, "k:h", long_options, &option_index ) ) != -1 ) {
  switch ( opt ) {
  case 'k':
   param_k= atof( optarg );
   if ( param_k < -1.0 || param_k > 3.0 ) {
    fprintf( stderr, "ERROR: the extinction coefficient %lf mag/airmass looks unrealistic\n", param_k );
    return 1;
   }
   break;
  case 2:
   if ( 0 != parse_angle_string( optarg, &param_sitelat ) || fabs( param_sitelat ) > 90.0 ) {
    fprintf( stderr, "ERROR: cannot interpret the latitude string '%s'\n", optarg );
    return 1;
   }
   param_have_cli_sitelat= 1;
   break;
  case 3:
   if ( 0 != parse_angle_string( optarg, &param_sitelong ) || fabs( param_sitelong ) > 360.0 ) {
    fprintf( stderr, "ERROR: cannot interpret the longitude string '%s'\n", optarg );
    return 1;
   }
   param_have_cli_sitelong= 1;
   break;
  case 4:
   param_jd= atof( optarg );
   if ( param_jd < 2000000.0 || param_jd > 3000000.0 ) {
    fprintf( stderr, "ERROR: the JD %lf is out of the expected range\n", param_jd );
    return 1;
   }
   param_have_cli_jd= 1;
   break;
  case 6:
   param_grid= atol( optarg );
   if ( param_grid < 1 || param_grid > 1024 ) {
    fprintf( stderr, "ERROR: the grid step should be between 1 and 1024 pixels\n" );
    return 1;
   }
   break;
  case 7:
   strncpy( param_map_filename, optarg, FILENAME_LENGTH - 1 );
   param_have_map= 1;
   break;
  case 8:
   strncpy( param_predict_list, optarg, FILENAME_LENGTH - 1 );
   param_have_predict_list= 1;
   break;
  case 9:
   param_print_info= 1;
   break;
  case 10:
   param_force= 1;
   break;
  case 11:
   param_fit_airmass_zp= 1;
   break;
  case 12:
   memset( param_calib_param_path, 0, FILENAME_LENGTH );
   strncpy( param_calib_param_path, optarg, FILENAME_LENGTH - 1 );
   break;
  case 13:
   strncpy( param_fit_table_path, optarg, FILENAME_LENGTH - 1 );
   break;
  case 'h':
  default:
   print_usage( argv[0] );
   return 1;
  }
 }

 if ( param_fit_airmass_zp == 1 ) {
  info_stream= stderr; // in fit mode stdout carries only the one-line result
 }

 if ( param_have_cli_sitelat != param_have_cli_sitelong ) {
  fprintf( stderr, "ERROR: --sitelat and --sitelong should always be used together\n" );
  return 1;
 }
 param_have_cli_site= param_have_cli_sitelat;

 if ( param_fit_airmass_zp == 1 ) {
  // fit mode positional arguments: calib.txt catalog.wcscat image.fits
  if ( optind + 2 >= argc ) {
   print_usage( argv[0] );
   return 1;
  }
  strncpy( fit_calib_txt_path, argv[optind], FILENAME_LENGTH - 1 );
  strncpy( fit_catalog_path, argv[optind + 1], FILENAME_LENGTH - 1 );
  memset( input_filename, 0, FILENAME_LENGTH );
  strncpy( input_filename, argv[optind + 2], FILENAME_LENGTH - 1 );
  memset( output_filename, 0, FILENAME_LENGTH );
 } else {
  if ( optind >= argc ) {
   print_usage( argv[0] );
   return 1;
  }
  memset( input_filename, 0, FILENAME_LENGTH );
  strncpy( input_filename, argv[optind], FILENAME_LENGTH - 1 );
  memset( output_filename, 0, FILENAME_LENGTH );
  if ( optind + 1 < argc ) {
   strncpy( output_filename, argv[optind + 1], FILENAME_LENGTH - 1 );
  } else {
   strncpy( input_filename_copy_for_basename, input_filename, FILENAME_LENGTH );
   input_filename_copy_for_basename[FILENAME_LENGTH - 1]= '\0';
   snprintf( output_filename, FILENAME_LENGTH, "ac_%s", basename( input_filename_copy_for_basename ) );
  }
  if ( 0 == strcmp( input_filename, output_filename ) ) {
   fprintf( stderr, "ERROR: the input and output image names are the same - in-place correction is not supported\n" );
   return 1;
  }
 }

 fprintf( stderr, "%s processing %s\n", argv[0], input_filename );

 // open the input image and read everything we need from it
 fits_open_file( &fptr, input_filename, READONLY, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  return 1;
 }
 fits_get_img_dim( fptr, &naxis, &status );
 if ( status != 0 || naxis != 2 ) {
  fprintf( stderr, "ERROR: the input image should be a 2D FITS image (NAXIS=%d)\n", naxis );
  fits_close_file( fptr, &status );
  return 1;
 }
 fits_read_key( fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status );
 fits_read_key( fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status );
 fits_get_img_type( fptr, &bitpix, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( naxes[0] < 2 || naxes[1] < 2 ) {
  fprintf( stderr, "ERROR: the input image is too small\n" );
  fits_close_file( fptr, &status );
  return 1;
 }

 // save all header records (for the double-correction check and for the output header);
 // not needed in the fit mode which never writes an image
 if ( param_fit_airmass_zp == 0 ) {
  fits_get_hdrspace( fptr, &num_keys, &keys_left, &status );
  num_keys++; // extra for safety
  header_keys= malloc( num_keys * sizeof( char * ) );
  if ( header_keys == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for the header records\n" );
   fits_close_file( fptr, &status );
   return 1;
  }
  for ( ii= 0; ii < num_keys; ii++ ) {
   header_keys[ii]= malloc( FLEN_CARD * sizeof( char ) );
   if ( header_keys[ii] == NULL ) {
    fprintf( stderr, "ERROR: Couldn't allocate memory for a header record\n" );
    fits_close_file( fptr, &status );
    return 1;
   }
   memset( header_keys[ii], 0, FLEN_CARD );
   if ( ii > 0 ) {
    fits_read_record( fptr, ii, header_keys[ii], &status );
    status= 0; // continue on errors
   }
  }

  // refuse to correct an already-corrected image
  if ( header_has_history_marker( header_keys, num_keys ) ) {
   if ( param_print_info == 1 || param_have_predict_list == 1 ) {
    fprintf( stderr, "WARNING: this image already carries the airmass-correction HISTORY record\n" );
   } else {
    if ( param_force == 0 ) {
     fprintf( stderr, "ERROR: the input image %s appears to be already corrected for airmass:\n the FITS header HISTORY contains the record\n '%s'\nUse --force to process it anyway.\n", input_filename, AIRMASS_CORRECTION_HISTORY_MARKER );
     fits_close_file( fptr, &status );
     return 1;
    }
    fprintf( stderr, "WARNING: the image carries the airmass-correction HISTORY record, processing anyway as requested (--force)\n" );
   }
  }
 }

 // optional cross-check values written by some acquisition software
 status= 0;
 fits_read_key( fptr, TDOUBLE, "CENTALT", &header_centalt, NULL, &status );
 if ( status == 0 ) {
  have_header_centalt= 1;
 }
 status= 0;
 fits_read_key( fptr, TDOUBLE, "AIRMASS", &header_airmass, NULL, &status );
 if ( status == 0 ) {
  have_header_airmass= 1;
 }
 status= 0;

 // observing site
 if ( param_have_cli_site == 1 ) {
  site_lat_deg= param_sitelat;
  site_long_deg= param_sitelong;
  snprintf( site_source, sizeof( site_source ), "command line" );
 } else {
  if ( 0 != find_site_in_header( fptr, &site_lat_deg, &site_long_deg, site_source, sizeof( site_source ) ) ) {
   site_source[0]= '\0';
  }
 }

 // WCS is always taken from the input image itself: the altitude/airmass of every
 // grid node is computed through this image's own CD matrix, so any orientation
 // (rotation/flip) of the frame is handled correctly.
 if ( 0 != read_tan_wcs( fptr, &wcs ) ) {
  fprintf( stderr, "ERROR: cannot read a TAN WCS from %s\nThe correction requires the image to carry its own WCS - plate-solve it first\n(e.g. util/wcs_image_calibration.sh %s)\n", input_filename, input_filename );
  fits_close_file( fptr, &status );
  return 1;
 }

 // read the pixel data if we are going to write a corrected image
 if ( param_print_info == 0 && param_have_predict_list == 0 && param_fit_airmass_zp == 0 ) {
  data= malloc( naxes[0] * naxes[1] * sizeof( float ) );
  if ( data == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for the image data\n" );
   fits_close_file( fptr, &status );
   return 1;
  }
  anynul= 0;
  fits_read_img( fptr, TFLOAT, 1, naxes[0] * naxes[1], NULL, data, &anynul, &status );
  if ( status != 0 ) {
   fits_report_error( stderr, status );
   fits_close_file( fptr, &status );
   return 1;
  }
 }
 fits_close_file( fptr, &status );
 status= 0;

 if ( site_source[0] == '\0' && param_have_cli_site == 0 ) {
  fprintf( stderr, "ERROR: cannot find the observing site coordinates in the FITS header\n(tried SITELAT/SITELONG, LAT-OBS/LONG-OBS, OBSLAT/OBSLONG, LATITUDE/LONGITUD, OBSGEO-B/OBSGEO-L)\nPlease specify the site with --sitelat and --sitelong\n" );
  return 1;
 }

 // observation time (mid-exposure, UTC)
 if ( param_have_cli_jd == 1 ) {
  JD= param_jd;
  snprintf( jd_source, sizeof( jd_source ), "command line" );
 } else {
  memset( gettime_stderr_output, 0, sizeof( gettime_stderr_output ) );
  memset( gettime_log_output, 0, sizeof( gettime_log_output ) );
  if ( 0 != gettime( input_filename, &JD, &timesys, 0, &dimX, &dimY, gettime_stderr_output, gettime_log_output, 0, 0, NULL ) ) {
   fprintf( stderr, "ERROR getting the observing time from %s\nPlease specify the mid-exposure time with --jd\n", input_filename );
   return 1;
  }
  snprintf( jd_source, sizeof( jd_source ), "FITS header" );
 }

 // geometry at the frame center
 lst= gmst_deg( JD ) + site_long_deg;
 center_x= ( (double)naxes[0] + 1.0 ) / 2.0;
 center_y= ( (double)naxes[1] + 1.0 ) / 2.0;
 pixel_to_radec( &wcs, center_x, center_y, &center_ra, &center_dec );
 radec_to_alt_az( center_ra, center_dec, site_lat_deg, lst, &center_alt, &center_az );
 center_airmass= airmass_young1994( center_alt );

 fprintf( info_stream, "Observation time (mid-exposure, UTC): JD %.5lf (%s)\n", JD, jd_source );
 fprintf( info_stream, "Observing site: lat= %+.6lf deg  lon= %+.6lf deg east-positive (%s)\n", site_lat_deg, site_long_deg, site_source );
 fprintf( info_stream, "Frame center (pixel %.1lf %.1lf): RA= %.5lf deg  Dec= %+.5lf deg\n", center_x, center_y, center_ra, center_dec );
 fprintf( info_stream, "Frame center: alt= %+.3lf deg  az= %.3lf deg  airmass= %.4lf\n", center_alt, center_az, center_airmass );
 if ( have_header_centalt == 1 ) {
  fprintf( info_stream, "Header cross-check: CENTALT= %.3lf deg (difference %+.3lf deg)\n", header_centalt, center_alt - header_centalt );
  if ( fabs( center_alt - header_centalt ) > 1.0 ) {
   fprintf( stderr, "WARNING: the computed frame center altitude differs from the header CENTALT by more than 1 degree!\nPlease check the site coordinates and the WCS.\n" );
  }
 }
 if ( have_header_airmass == 1 ) {
  fprintf( info_stream, "Header cross-check: AIRMASS= %.4lf (we compute %.4lf)\n", header_airmass, center_airmass );
  if ( header_airmass > 0.0 && fabs( center_airmass - header_airmass ) / header_airmass > 0.05 ) {
   fprintf( stderr, "WARNING: the computed frame center airmass differs from the header AIRMASS by more than 5 percent!\nPlease check the site coordinates and the WCS.\n" );
  }
 }
 if ( center_alt <= 0.0 ) {
  fprintf( stderr, "ERROR: the computed frame center is below the horizon!\nThe site coordinates (or the observing time, or the WCS) must be wrong.\n" );
  return 1;
 }

 // airmass-aware zero-point fit mode: fit, print the one-line result, exit
 if ( param_fit_airmass_zp == 1 ) {
  return fit_airmass_zeropoint( fit_calib_txt_path, fit_catalog_path,
                                param_calib_param_path, param_fit_table_path,
                                &wcs, site_lat_deg, lst, center_airmass );
 }

 // predict-list mode: exact per-position computation, then exit
 if ( param_have_predict_list == 1 ) {
  predict_file= fopen( param_predict_list, "r" );
  if ( predict_file == NULL ) {
   fprintf( stderr, "ERROR: cannot open the pixel position list file %s\n", param_predict_list );
   return 1;
  }
  fprintf( stdout, "# X_pix Y_pix delta_mag airmass alt_deg\n" );
  while ( NULL != fgets( predict_line, sizeof( predict_line ), predict_file ) ) {
   predict_line[sizeof( predict_line ) - 1]= '\0';
   if ( predict_line[0] == '#' ) {
    continue;
   }
   if ( 2 != sscanf( predict_line, "%lf %lf", &predict_x, &predict_y ) ) {
    continue;
   }
   pixel_to_radec( &wcs, predict_x, predict_y, &node_ra, &node_dec );
   radec_to_alt_az( node_ra, node_dec, site_lat_deg, lst, &predict_alt, &predict_az );
   predict_airmass= airmass_young1994( predict_alt );
   predict_delta= param_k * ( predict_airmass - center_airmass );
   if ( predict_delta > AIRMASS_CORRECTION_MAX_DELTA_MAG ) {
    predict_delta= AIRMASS_CORRECTION_MAX_DELTA_MAG;
   }
   if ( predict_delta < -1.0 * AIRMASS_CORRECTION_MAX_DELTA_MAG ) {
    predict_delta= -1.0 * AIRMASS_CORRECTION_MAX_DELTA_MAG;
   }
   fprintf( stdout, "%9.3lf %9.3lf %+8.4lf %8.4lf %+8.3lf\n", predict_x, predict_y, predict_delta, predict_airmass, predict_alt );
  }
  fclose( predict_file );
  return 0;
 }

 // set up the airmass evaluation grid
 n_steps_x= ( naxes[0] - 1 ) / param_grid;
 nx_nodes= n_steps_x + 1;
 if ( 1 + n_steps_x * param_grid < naxes[0] ) {
  nx_nodes++;
 }
 n_steps_y= ( naxes[1] - 1 ) / param_grid;
 ny_nodes= n_steps_y + 1;
 if ( 1 + n_steps_y * param_grid < naxes[1] ) {
  ny_nodes++;
 }
 node_x= malloc( nx_nodes * sizeof( double ) );
 node_y= malloc( ny_nodes * sizeof( double ) );
 factor_grid= malloc( nx_nodes * ny_nodes * sizeof( double ) );
 delta_grid= malloc( nx_nodes * ny_nodes * sizeof( double ) );
 if ( node_x == NULL || node_y == NULL || factor_grid == NULL || delta_grid == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for the airmass grid\n" );
  return 1;
 }
 for ( inode= 0; inode < nx_nodes; inode++ ) {
  node_x[inode]= 1.0 + (double)( inode * param_grid );
  if ( node_x[inode] > (double)naxes[0] ) {
   node_x[inode]= (double)naxes[0];
  }
 }
 node_x[nx_nodes - 1]= (double)naxes[0];
 for ( jnode= 0; jnode < ny_nodes; jnode++ ) {
  node_y[jnode]= 1.0 + (double)( jnode * param_grid );
  if ( node_y[jnode] > (double)naxes[1] ) {
   node_y[jnode]= (double)naxes[1];
  }
 }
 node_y[ny_nodes - 1]= (double)naxes[1];

 airmass_min= airmass_max= center_airmass;
 delta_min= delta_max= 0.0;
 n_capped_nodes= 0;
 for ( jnode= 0; jnode < ny_nodes; jnode++ ) {
  for ( inode= 0; inode < nx_nodes; inode++ ) {
   pixel_to_radec( &wcs, node_x[inode], node_y[jnode], &node_ra, &node_dec );
   radec_to_alt_az( node_ra, node_dec, site_lat_deg, lst, &node_alt, &node_az );
   node_airmass= airmass_young1994( node_alt );
   if ( node_airmass < airmass_min ) {
    airmass_min= node_airmass;
   }
   if ( node_airmass > airmass_max ) {
    airmass_max= node_airmass;
   }
   node_delta= param_k * ( node_airmass - center_airmass );
   if ( node_delta > AIRMASS_CORRECTION_MAX_DELTA_MAG ) {
    node_delta= AIRMASS_CORRECTION_MAX_DELTA_MAG;
    n_capped_nodes++;
   }
   if ( node_delta < -1.0 * AIRMASS_CORRECTION_MAX_DELTA_MAG ) {
    node_delta= -1.0 * AIRMASS_CORRECTION_MAX_DELTA_MAG;
    n_capped_nodes++;
   }
   if ( node_delta < delta_min ) {
    delta_min= node_delta;
   }
   if ( node_delta > delta_max ) {
    delta_max= node_delta;
   }
   delta_grid[jnode * nx_nodes + inode]= node_delta;
   factor_grid[jnode * nx_nodes + inode]= pow( 10.0, 0.4 * node_delta );
  }
 }

 fprintf( stdout, "Airmass across the frame: min= %.4lf  max= %.4lf\n", airmass_min, airmass_max );
 fprintf( stdout, "Extinction coefficient k= %.3lf mag/airmass\n", param_k );
 fprintf( stdout, "Flux correction: %+.4lf mag (factor %.4lf) to %+.4lf mag (factor %.4lf)\n", delta_min, pow( 10.0, 0.4 * delta_min ), delta_max, pow( 10.0, 0.4 * delta_max ) );
 if ( n_capped_nodes > 0 ) {
  fprintf( stderr, "WARNING: the correction was capped at %.1lf mag for %ld of %ld grid nodes (field edge too close to the horizon?)\n", AIRMASS_CORRECTION_MAX_DELTA_MAG, n_capped_nodes, nx_nodes * ny_nodes );
 }

 if ( param_print_info == 1 ) {
  return 0;
 }

 // optional delta-mag map output
 if ( param_have_map == 1 ) {
  map_data= malloc( naxes[0] * naxes[1] * sizeof( float ) );
  if ( map_data == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for the correction map\n" );
   return 1;
  }
  for ( j= 0; j < naxes[1]; j++ ) {
   y= (double)( j + 1 );
   iy= j / param_grid;
   if ( iy > ny_nodes - 2 ) {
    iy= ny_nodes - 2;
   }
   cell_height= node_y[iy + 1] - node_y[iy];
   wy= ( y - node_y[iy] ) / cell_height;
   for ( i= 0; i < naxes[0]; i++ ) {
    x= (double)( i + 1 );
    ix= i / param_grid;
    if ( ix > nx_nodes - 2 ) {
     ix= nx_nodes - 2;
    }
    cell_width= node_x[ix + 1] - node_x[ix];
    wx= ( x - node_x[ix] ) / cell_width;
    map_data[j * naxes[0] + i]= (float)( ( 1.0 - wx ) * ( 1.0 - wy ) * delta_grid[iy * nx_nodes + ix] + wx * ( 1.0 - wy ) * delta_grid[iy * nx_nodes + ix + 1] + ( 1.0 - wx ) * wy * delta_grid[( iy + 1 ) * nx_nodes + ix] + wx * wy * delta_grid[( iy + 1 ) * nx_nodes + ix + 1] );
   }
  }
  if ( 0 != write_output_image( param_map_filename, map_data, naxes, FLOAT_IMG, header_keys, num_keys, param_k, center_airmass, site_lat_deg, site_long_deg ) ) {
   fprintf( stderr, "ERROR writing the correction map %s\n", param_map_filename );
   free( map_data );
   return 1;
  }
  fprintf( stdout, "Correction (delta-mag) map written to %s\n", param_map_filename );
  free( map_data );
 }

 // decide on the saturated-pixels handling
 max_input_pixel_value= 0.0;
 for ( i= 0; i < naxes[0] * naxes[1]; i++ ) {
  if ( (double)data[i] > max_input_pixel_value ) {
   max_input_pixel_value= (double)data[i];
  }
 }
 saturation_level= max_input_pixel_value - SATURATION_LIMIT_INDENT * max_input_pixel_value;
 do_saturation_pinning= 0;
 if ( bitpix == SHORT_IMG && param_k != 0.0 && max_input_pixel_value > AIRMASS_CORRECTION_SATURATION_PINNING_MIN_MAXVAL ) {
  do_saturation_pinning= 1;
  fprintf( stdout, "Saturation preservation: input pixels above %.1lf (input max %.1lf) will be set to 65535\n", saturation_level, max_input_pixel_value );
 }

 // apply the correction
 n_pinned_pixels= 0;
 n_clamped_pixels= 0;
 for ( j= 0; j < naxes[1]; j++ ) {
  y= (double)( j + 1 );
  iy= j / param_grid;
  if ( iy > ny_nodes - 2 ) {
   iy= ny_nodes - 2;
  }
  cell_height= node_y[iy + 1] - node_y[iy];
  wy= ( y - node_y[iy] ) / cell_height;
  for ( i= 0; i < naxes[0]; i++ ) {
   pixel_index= j * naxes[0] + i;
   input_pixel_value= data[pixel_index];
   if ( input_pixel_value == 0.0f ) {
    continue; // preserve exact zeros (blank image margins)
   }
   if ( do_saturation_pinning == 1 && (double)input_pixel_value >= saturation_level ) {
    data[pixel_index]= 65535.0f;
    n_pinned_pixels++;
    continue;
   }
   x= (double)( i + 1 );
   ix= i / param_grid;
   if ( ix > nx_nodes - 2 ) {
    ix= nx_nodes - 2;
   }
   cell_width= node_x[ix + 1] - node_x[ix];
   wx= ( x - node_x[ix] ) / cell_width;
   interp_factor= ( 1.0 - wx ) * ( 1.0 - wy ) * factor_grid[iy * nx_nodes + ix] + wx * ( 1.0 - wy ) * factor_grid[iy * nx_nodes + ix + 1] + ( 1.0 - wx ) * wy * factor_grid[( iy + 1 ) * nx_nodes + ix] + wx * wy * factor_grid[( iy + 1 ) * nx_nodes + ix + 1];
   output_pixel_value= (float)( (double)input_pixel_value * interp_factor );
   if ( bitpix == SHORT_IMG ) {
    if ( do_saturation_pinning == 1 ) {
     // keep scaled values below the 65535 level reserved for the originally saturated pixels
     if ( output_pixel_value > 65534.0f ) {
      output_pixel_value= 65534.0f;
      n_clamped_pixels++;
     }
    } else {
     if ( output_pixel_value > 65535.0f ) {
      output_pixel_value= 65535.0f;
      n_clamped_pixels++;
     }
    }
    if ( output_pixel_value < 1.0f ) {
     output_pixel_value= 1.0f;
    }
   }
   data[pixel_index]= output_pixel_value;
  }
 }
 if ( do_saturation_pinning == 1 ) {
  fprintf( stdout, "Saturation preservation: %ld pixels pinned to 65535, %ld scaled pixels clamped at 65534\n", n_pinned_pixels, n_clamped_pixels );
 }

 if ( 0 != write_output_image( output_filename, data, naxes, bitpix, header_keys, num_keys, param_k, center_airmass, site_lat_deg, site_long_deg ) ) {
  fprintf( stderr, "ERROR writing the output image %s\n", output_filename );
  return 1;
 }
 fprintf( stdout, "Airmass-corrected image written to %s (BITPIX %d preserved)\n", output_filename, bitpix );

 free( data );
 for ( ii= 0; ii < num_keys; ii++ ) {
  free( header_keys[ii] );
 }
 free( header_keys );
 free( node_x );
 free( node_y );
 free( factor_grid );
 free( delta_grid );

 return 0;
}
