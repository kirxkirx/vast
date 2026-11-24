// util/archive_frame_quality - measure the quality of one calibrated, plate-solved frame for the
// archive frame-quality step that runs after unmw's sort_workdir_images.sh: the observing
// conditions (the altitude of the Sun, the moonlight at the field, the airmass), the
// transparency (the zero point against the local Tycho-2 catalog in a grid of cells across the
// frame, each corrected for its own airmass), the fraction of the Tycho-2 stars found in each
// cell, the sky level, the star size and elongation, and the limiting magnitude.
//
// Run it from the VaST directory: it runs lib/bin/sex with a SExtractor configuration file
// from that directory and reads lib/catalogs/tycho2/tyc2.dat.00 ... tyc2.dat.19.
//
// Usage: util/archive_frame_quality FRAME.fits [options], see print_usage() below.
// It prints one line of key=value pairs (NA for a value that could not be measured), which the
// frame-quality script stores, one line per frame. Exit code 0 when the line is printed
// (its status= key says whether the measurement is complete), 1 on an error.
//
// The site: the SITELAT/SITELONG/SITEELEV (or LAT-OBS/LONG-OBS, ...) header keywords, or
// --site; the geometry (src/sun_moon.c) gives the altitude of the Sun, the moonlight
// brightening of the sky at the frame centre (Krisciunas & Schaefer 1991, PASP 103, 1033) and
// the altitude and airmass of the centre of every cell. The header CENTALT and AIRMASS are
// printed next to the computed values: a disagreement means a wrong site, sign or clock.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <ctype.h>
#include <unistd.h>

#include "fitsio.h"
#include "vast_limits.h"
#include "ident.h" // for gettime()
#include "sun_moon.h"
#include "detection_limit.h"

#define AFQ_DEG2RAD 0.017453292519943295
#define AFQ_MAX_SIP_ORDER 9
#define AFQ_MAX_GRID 20
// a Tycho-2 star matches the nearest detection within this many pixels
#define AFQ_MATCH_RADIUS_PIX 2.0
// hash cell size (pixels) for the detection lookup
#define AFQ_HASH_CELL_PIX 8
// stars for the zero point: SNR and peak limits (the peak above the background, in ADU,
// keeps the zero point clear of non-linearity and saturation)
#define AFQ_ZP_MIN_SNR 20.0
#define AFQ_DEFAULT_MAX_PEAK_ADU 40000.0
#define AFQ_DEFAULT_V_BRIGHT 7.0
#define AFQ_DEFAULT_V_FAINT 11.5
// Tycho-2 is nearly complete to V = 11: the fraction of stars found is counted to that limit
#define AFQ_COUNT_V_FAINT 11.0
// minimal numbers of stars for a cell value
#define AFQ_MIN_STARS_PER_CELL 5
// every AFQ_SKY_STEP-th pixel of every AFQ_SKY_STEP-th row is used for the sky statistics
#define AFQ_SKY_STEP 8
// detections with SNR 4.5-5.5 needed for the limiting magnitude
#define AFQ_MIN_SNR5_DETECTIONS 20

struct afq_wcs {
 double crval1;
 double crval2;
 double crpix1;
 double crpix2;
 double cd11;
 double cd12;
 double cd21;
 double cd22;
 double icd11;
 double icd12;
 double icd21;
 double icd22;
 int a_order;
 int b_order;
 double a[AFQ_MAX_SIP_ORDER + 1][AFQ_MAX_SIP_ORDER + 1];
 double b[AFQ_MAX_SIP_ORDER + 1][AFQ_MAX_SIP_ORDER + 1];
};

struct afq_detection {
 double x;
 double y;
 double flux;
 double flux_err;
 double peak;
 double background;
 double fwhm;
 double a;
 double b;
 int flags;
};

struct afq_cell {
 int n_zp;
 int n_expected;
 int n_found;
 double *zp_values;
 int zp_allocated;
 double *sky_values;
 int n_sky;
 int sky_allocated;
 double zp;
 double sky;
 double airmass;
 double alt;
};

static void print_usage( char *progname ) {
 fprintf( stderr, "Usage: %s FRAME.fits [options]\n", progname );
 fprintf( stderr, "Options:\n" );
 fprintf( stderr, "  --sex-config FILE   SExtractor configuration (default default.sex.telephoto_lens_vSTL)\n" );
 fprintf( stderr, "  --site LAT,LON,H    observing site: latitude, east longitude (degrees), height (m);\n" );
 fprintf( stderr, "                      the default is to read it from the FITS header\n" );
 fprintf( stderr, "  --extinction K      extinction coefficient, mag per airmass (default %.2f)\n", SUN_MOON_DEFAULT_EXTINCTION_MAG );
 fprintf( stderr, "  --dark-sky V        dark zenith sky brightness for the moonlight model, V mag/arcsec^2 (default %.1f)\n", SUN_MOON_DEFAULT_DARK_SKY_V_MAG_ARCSEC2 );
 fprintf( stderr, "  --grid NXxNY        cells across the frame (default: 6 along the longer side, square cells)\n" );
 fprintf( stderr, "  --max-peak ADU      peak above the background of a zero-point star (default %.0f)\n", AFQ_DEFAULT_MAX_PEAK_ADU );
 fprintf( stderr, "  --v-range MIN,MAX   Tycho-2 V range of the zero-point stars (default %.1f,%.1f)\n", AFQ_DEFAULT_V_BRIGHT, AFQ_DEFAULT_V_FAINT );
 fprintf( stderr, "Run it from the VaST directory.\n" );
 return;
}

static int compare_doubles( const void *a, const void *b ) {
 double da;
 double db;
 da= *(const double *)a;
 db= *(const double *)b;
 if ( da < db ) {
  return -1;
 }
 if ( da > db ) {
  return 1;
 }
 return 0;
}

// Median of n values; the array is sorted in place. 0 for n < 1.
static double median_in_place( double *values, int n ) {
 if ( n < 1 ) {
  return 0.0;
 }
 qsort( values, (size_t)n, sizeof( double ), compare_doubles );
 if ( n % 2 == 1 ) {
  return values[n / 2];
 }
 return ( values[n / 2 - 1] + values[n / 2] ) / 2.0;
}

// 1.4826 * the median absolute deviation from the median (the array is reordered)
static double sigma_mad_in_place( double *values, int n, double median ) {
 int i;
 if ( n < 2 ) {
  return 0.0;
 }
 for ( i= 0; i < n; i++ ) {
  values[i]= fabs( values[i] - median );
 }
 return 1.4826 * median_in_place( values, n );
}

// Append a value to a growing array; 0 on success
static int append_value( double **array, int *n, int *allocated, double value ) {
 double *new_array;
 int new_allocated;
 if ( ( *n ) >= ( *allocated ) ) {
  new_allocated= ( *allocated ) < 64 ? 64 : 2 * ( *allocated );
  new_array= (double *)realloc( ( *array ), (size_t)new_allocated * sizeof( double ) );
  if ( new_array == NULL ) {
   return 1;
  }
  ( *array )= new_array;
  ( *allocated )= new_allocated;
 }
 ( *array )[( *n )]= value;
 ( *n )++;
 return 0;
}

// Parse an angle in decimal degrees ("33.748239") or sexagesimal ("43 38 58", "-101:57:30.1");
// a trailing N/E (positive) or S/W (negative) is accepted. 0 on success.
static int parse_angle_string( const char *instr, double *result_deg ) {
 char buf[128];
 double d;
 double m;
 double s;
 double sign;
 int n;
 size_t i;
 size_t j;
 char suffix;
 if ( instr == NULL || strlen( instr ) < 1 || strlen( instr ) > 127 ) {
  return 1;
 }
 strncpy( buf, instr, sizeof( buf ) );
 buf[sizeof( buf ) - 1]= '\0';
 for ( i= 0; i < strlen( buf ); i++ ) {
  if ( buf[i] == ':' || buf[i] == ',' ) {
   buf[i]= ' ';
  }
 }
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
 } else if ( suffix != ' ' && suffix != 'N' && suffix != 'E' ) {
  return 1;
 }
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
 d= 0.0;
 m= 0.0;
 s= 0.0;
 n= sscanf( buf, "%lf %lf %lf", &d, &m, &s );
 if ( n < 1 || d < 0.0 ) {
  return 1;
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

// The observing site from the FITS header; 0 on success
static int read_site_from_header( fitsfile *fptr, struct sun_moon_site *site ) {
 static const char *lat_keys[5]= { "SITELAT", "LAT-OBS", "OBSLAT", "LATITUDE", "OBSGEO-B" };
 static const char *long_keys[5]= { "SITELONG", "LONG-OBS", "OBSLONG", "LONGITUD", "OBSGEO-L" };
 static const char *height_keys[4]= { "SITEELEV", "ALT-OBS", "OBSALT", "OBSGEO-H" };
 int ipair;
 int status;
 char latstr[FLEN_VALUE];
 char longstr[FLEN_VALUE];
 double lat;
 double lon;
 double height;
 for ( ipair= 0; ipair < 5; ipair++ ) {
  status= 0;
  fits_read_key( fptr, TSTRING, (char *)lat_keys[ipair], latstr, NULL, &status );
  fits_read_key( fptr, TSTRING, (char *)long_keys[ipair], longstr, NULL, &status );
  if ( status != 0 ) {
   continue;
  }
  if ( 0 != parse_angle_string( latstr, &lat ) || 0 != parse_angle_string( longstr, &lon ) ) {
   continue;
  }
  if ( fabs( lat ) > 90.0 || fabs( lon ) > 360.0 ) {
   continue;
  }
  site->latitude_deg= lat;
  site->longitude_deg= lon;
  site->height_m= 0.0;
  for ( ipair= 0; ipair < 4; ipair++ ) {
   status= 0;
   fits_read_key( fptr, TDOUBLE, (char *)height_keys[ipair], &height, NULL, &status );
   if ( status == 0 && height > -500.0 && height < 10000.0 ) {
    site->height_m= height;
    break;
   }
  }
  return 0;
 }
 return 1;
}

// The TAN or TAN-SIP plate solution; 0 on success
static int read_wcs( fitsfile *fptr, struct afq_wcs *wcs ) {
 int status;
 int status_cd;
 int p;
 int q;
 char ctype1[FLEN_VALUE];
 char ctype2[FLEN_VALUE];
 char key[FLEN_KEYWORD];
 double cdelt1;
 double cdelt2;
 double crota2;
 double det;
 status= 0;
 fits_read_key( fptr, TSTRING, "CTYPE1", ctype1, NULL, &status );
 fits_read_key( fptr, TSTRING, "CTYPE2", ctype2, NULL, &status );
 if ( status != 0 ) {
  fprintf( stderr, "ERROR: no CTYPE1/CTYPE2 keywords - the frame is not plate-solved\n" );
  return 1;
 }
 if ( 0 != strncmp( ctype1, "RA---TAN", 8 ) || 0 != strncmp( ctype2, "DEC--TAN", 8 ) ) {
  fprintf( stderr, "ERROR: unsupported projection CTYPE1='%s' CTYPE2='%s' (expecting RA---TAN or RA---TAN-SIP)\n", ctype1, ctype2 );
  return 1;
 }
 fits_read_key( fptr, TDOUBLE, "CRVAL1", &wcs->crval1, NULL, &status );
 fits_read_key( fptr, TDOUBLE, "CRVAL2", &wcs->crval2, NULL, &status );
 fits_read_key( fptr, TDOUBLE, "CRPIX1", &wcs->crpix1, NULL, &status );
 fits_read_key( fptr, TDOUBLE, "CRPIX2", &wcs->crpix2, NULL, &status );
 if ( status != 0 ) {
  fprintf( stderr, "ERROR: incomplete WCS (CRVAL/CRPIX keywords missing)\n" );
  return 1;
 }
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
  wcs->cd11= cdelt1 * cos( crota2 * AFQ_DEG2RAD );
  wcs->cd12= -1.0 * cdelt2 * sin( crota2 * AFQ_DEG2RAD );
  wcs->cd21= cdelt1 * sin( crota2 * AFQ_DEG2RAD );
  wcs->cd22= cdelt2 * cos( crota2 * AFQ_DEG2RAD );
 }
 det= wcs->cd11 * wcs->cd22 - wcs->cd12 * wcs->cd21;
 if ( det == 0.0 ) {
  fprintf( stderr, "ERROR: singular CD matrix\n" );
  return 1;
 }
 wcs->icd11= wcs->cd22 / det;
 wcs->icd12= -1.0 * wcs->cd12 / det;
 wcs->icd21= -1.0 * wcs->cd21 / det;
 wcs->icd22= wcs->cd11 / det;
 // SIP distortion coefficients, if any
 memset( wcs->a, 0, sizeof( wcs->a ) );
 memset( wcs->b, 0, sizeof( wcs->b ) );
 wcs->a_order= 0;
 wcs->b_order= 0;
 if ( NULL != strstr( ctype1, "-SIP" ) ) {
  status= 0;
  fits_read_key( fptr, TINT, "A_ORDER", &wcs->a_order, NULL, &status );
  fits_read_key( fptr, TINT, "B_ORDER", &wcs->b_order, NULL, &status );
  if ( status != 0 || wcs->a_order < 0 || wcs->b_order < 0 || wcs->a_order > AFQ_MAX_SIP_ORDER || wcs->b_order > AFQ_MAX_SIP_ORDER ) {
   fprintf( stderr, "ERROR: cannot read the SIP polynomial orders A_ORDER/B_ORDER\n" );
   return 1;
  }
  for ( p= 0; p <= wcs->a_order; p++ ) {
   for ( q= 0; p + q <= wcs->a_order; q++ ) {
    snprintf( key, sizeof( key ), "A_%d_%d", p, q );
    status= 0;
    fits_read_key( fptr, TDOUBLE, key, &wcs->a[p][q], NULL, &status );
    if ( status != 0 ) {
     wcs->a[p][q]= 0.0;
    }
   }
  }
  for ( p= 0; p <= wcs->b_order; p++ ) {
   for ( q= 0; p + q <= wcs->b_order; q++ ) {
    snprintf( key, sizeof( key ), "B_%d_%d", p, q );
    status= 0;
    fits_read_key( fptr, TDOUBLE, key, &wcs->b[p][q], NULL, &status );
    if ( status != 0 ) {
     wcs->b[p][q]= 0.0;
    }
   }
  }
 }
 return 0;
}

// The SIP distortion f(u,v) and g(u,v) for the pixel offsets u, v from CRPIX
static void sip_distortion( const struct afq_wcs *wcs, double u, double v, double *f, double *g ) {
 int p;
 int q;
 double up;
 double vq;
 ( *f )= 0.0;
 ( *g )= 0.0;
 up= 1.0;
 for ( p= 0; p <= AFQ_MAX_SIP_ORDER; p++ ) {
  vq= 1.0;
  for ( q= 0; p + q <= AFQ_MAX_SIP_ORDER; q++ ) {
   if ( p + q <= wcs->a_order ) {
    ( *f )+= wcs->a[p][q] * up * vq;
   }
   if ( p + q <= wcs->b_order ) {
    ( *g )+= wcs->b[p][q] * up * vq;
   }
   vq*= v;
  }
  up*= u;
 }
 return;
}

// Pixel (FITS convention, the first pixel is 1) to RA, Dec (degrees)
static void pixel_to_radec( const struct afq_wcs *wcs, double x, double y, double *ra_deg, double *dec_deg ) {
 double u;
 double v;
 double f;
 double g;
 double xi;
 double eta;
 double ra0;
 double dec0;
 double denominator;
 double ra;
 u= x - wcs->crpix1;
 v= y - wcs->crpix2;
 sip_distortion( wcs, u, v, &f, &g );
 u+= f;
 v+= g;
 xi= ( wcs->cd11 * u + wcs->cd12 * v ) * AFQ_DEG2RAD;
 eta= ( wcs->cd21 * u + wcs->cd22 * v ) * AFQ_DEG2RAD;
 ra0= wcs->crval1 * AFQ_DEG2RAD;
 dec0= wcs->crval2 * AFQ_DEG2RAD;
 denominator= cos( dec0 ) - eta * sin( dec0 );
 ra= ra0 + atan2( xi, denominator );
 ( *dec_deg )= atan2( eta * cos( dec0 ) + sin( dec0 ), sqrt( xi * xi + denominator * denominator ) ) / AFQ_DEG2RAD;
 ra= fmod( ra / AFQ_DEG2RAD, 360.0 );
 if ( ra < 0.0 ) {
  ra+= 360.0;
 }
 ( *ra_deg )= ra;
 return;
}

// RA, Dec to pixel; the SIP distortion is inverted by iteration. 0 on success, 1 for a
// position more than 80 deg from the tangent point.
static int radec_to_pixel( const struct afq_wcs *wcs, double ra_deg, double dec_deg, double *x, double *y ) {
 double ra;
 double dec;
 double ra0;
 double dec0;
 double cos_c;
 double xi;
 double eta;
 double up;
 double vp;
 double u;
 double v;
 double f;
 double g;
 int iteration;
 ra= ra_deg * AFQ_DEG2RAD;
 dec= dec_deg * AFQ_DEG2RAD;
 ra0= wcs->crval1 * AFQ_DEG2RAD;
 dec0= wcs->crval2 * AFQ_DEG2RAD;
 cos_c= sin( dec0 ) * sin( dec ) + cos( dec0 ) * cos( dec ) * cos( ra - ra0 );
 if ( cos_c < 0.17 ) {
  return 1;
 }
 xi= cos( dec ) * sin( ra - ra0 ) / cos_c / AFQ_DEG2RAD;
 eta= ( cos( dec0 ) * sin( dec ) - sin( dec0 ) * cos( dec ) * cos( ra - ra0 ) ) / cos_c / AFQ_DEG2RAD;
 // the distorted offsets u + f(u,v), v + g(u,v)
 up= wcs->icd11 * xi + wcs->icd12 * eta;
 vp= wcs->icd21 * xi + wcs->icd22 * eta;
 u= up;
 v= vp;
 for ( iteration= 0; iteration < 20; iteration++ ) {
  sip_distortion( wcs, u, v, &f, &g );
  u= up - f;
  v= vp - g;
 }
 ( *x )= u + wcs->crpix1;
 ( *y )= v + wcs->crpix2;
 return 0;
}

// Index of the cell holding pixel x, y, or -1 outside the frame
static int cell_index( double x, double y, double naxis1, double naxis2, int nx, int ny ) {
 int ix;
 int iy;
 if ( x < 0.5 || y < 0.5 || x > naxis1 + 0.5 || y > naxis2 + 0.5 ) {
  return -1;
 }
 ix= (int)( ( x - 0.5 ) / naxis1 * nx );
 iy= (int)( ( y - 0.5 ) / naxis2 * ny );
 if ( ix >= nx ) {
  ix= nx - 1;
 }
 if ( iy >= ny ) {
  iy= ny - 1;
 }
 return iy * nx + ix;
}

// Split a Tycho-2 line (fields separated by '|') into at most max_fields field pointers;
// the line is modified. Returns the number of fields.
static int split_tycho2_line( char *line, char **fields, int max_fields ) {
 int n;
 char *c;
 n= 0;
 fields[n++]= line;
 for ( c= line; *c != '\0' && n < max_fields; c++ ) {
  if ( *c == '|' ) {
   *c= '\0';
   fields[n++]= c + 1;
  }
 }
 return n;
}

static int field_is_blank( const char *s ) {
 while ( *s != '\0' ) {
  if ( *s != ' ' && *s != '\n' && *s != '\r' ) {
   return 0;
  }
  s++;
 }
 return 1;
}

// Write the line of results. The values of failed measurements are NA.
static void print_na_or_value( const char *key, int have_value, double value, const char *format ) {
 fprintf( stdout, " %s=", key );
 if ( have_value != 0 ) {
  fprintf( stdout, format, value );
 } else {
  fprintf( stdout, "NA" );
 }
 return;
}

int main( int argc, char **argv ) {
 char *frame_name;
 char *sex_config;
 char frame_basename[FILENAME_LENGTH];
 char camera[FLEN_VALUE];
 char object[FLEN_VALUE];
 char tmp_dir_template[FILENAME_LENGTH];
 char *tmp_dir;
 char param_file[FILENAME_LENGTH];
 char catalog_file[FILENAME_LENGTH];
 char command[4 * FILENAME_LENGTH];
 char line[1024];
 char tycho_line[1024];
 char tycho_file_name[FILENAME_LENGTH];
 char *tycho_fields[32];
 char gettime_stderr_output[1024];
 char gettime_log_output[1024];
 const char *slash;
 fitsfile *fptr;
 int status;
 int i;
 int j;
 int n_fields;
 int nx;
 int ny;
 int n_cells;
 int have_cli_site;
 int have_header_centalt;
 int have_header_airmass;
 int timesys;
 int hash_nx;
 int hash_ny;
 int hx;
 int hy;
 int ihx;
 int ihy;
 int k;
 int best;
 int cell;
 int tycho_file_counter;
 int n_detections;
 int detections_allocated;
 int n_zp_all;
 int zp_all_allocated;
 int n_lim;
 int lim_allocated;
 int n_good_shape;
 int shape_allocated;
 int n_snr5;
 int n_tycho_expected;
 int n_tycho_found;
 int n_cells_with_zp;
 int n_cells_with_count;
 int lim_success;
 int n_lim_snr5;
 int n_sky_all;
 int sky_all_allocated;
 int *hash_head;
 int *hash_next;
 long naxes[2];
 long fpixel[2];
 long row;
 long col;
 double naxis1;
 double naxis2;
 double exptime;
 double jd;
 double dim_x;
 double dim_y;
 double extinction;
 double dark_sky_v;
 double max_peak;
 double v_bright;
 double v_faint;
 double header_centalt;
 double header_airmass;
 double center_ra;
 double center_dec;
 double corner_ra;
 double corner_dec;
 double radius_deg;
 double ra;
 double dec;
 double pm_ra;
 double pm_dec;
 double bt;
 double vt;
 double v_mag;
 double years_since_2000;
 double x;
 double y;
 double dx;
 double dy;
 double d2;
 double best_d2;
 double zp_frame;
 double zp_sigma;
 double fwhm_median;
 double elongation_median;
 double lim_mag;
 double lim_snr5;
 double sky_median;
 double sky_sigma;
 double zp_corr_median;
 double zp_corr_min;
 double zp_corr_max;
 double found_fraction_min;
 double found_fraction_median;
 double value;
 double cell_center_ra;
 double cell_center_dec;
 double *zp_all;
 double *lim_mag_values;
 double *lim_snr_values;
 double *fwhm_values;
 double *elongation_values;
 double *sky_all;
 double *row_buffer;
 double *cell_values;
 struct afq_detection *detections;
 struct afq_detection *new_detections;
 struct afq_cell cells[AFQ_MAX_GRID * AFQ_MAX_GRID];
 struct afq_wcs wcs;
 struct sun_moon_site site;
 struct sun_moon_geometry geometry;
 struct sun_moon_geometry cell_geometry;
 FILE *f;

 if ( argc < 2 || 0 == strcmp( argv[1], "-h" ) || 0 == strcmp( argv[1], "--help" ) ) {
  print_usage( argv[0] );
  return 1;
 }

 // Defaults
 frame_name= argv[1];
 sex_config= "default.sex.telephoto_lens_vSTL";
 have_cli_site= 0;
 site.latitude_deg= 0.0;
 site.longitude_deg= 0.0;
 site.height_m= 0.0;
 extinction= SUN_MOON_DEFAULT_EXTINCTION_MAG;
 dark_sky_v= SUN_MOON_DEFAULT_DARK_SKY_V_MAG_ARCSEC2;
 max_peak= AFQ_DEFAULT_MAX_PEAK_ADU;
 v_bright= AFQ_DEFAULT_V_BRIGHT;
 v_faint= AFQ_DEFAULT_V_FAINT;
 nx= 0;
 ny= 0;
 for ( i= 2; i < argc; i++ ) {
  if ( 0 == strcmp( argv[i], "--sex-config" ) && i + 1 < argc ) {
   sex_config= argv[++i];
  } else if ( 0 == strcmp( argv[i], "--site" ) && i + 1 < argc ) {
   if ( 3 != sscanf( argv[++i], "%lf,%lf,%lf", &site.latitude_deg, &site.longitude_deg, &site.height_m ) || fabs( site.latitude_deg ) > 90.0 || fabs( site.longitude_deg ) > 360.0 ) {
    fprintf( stderr, "ERROR: --site wants LATITUDE,EAST_LONGITUDE,HEIGHT_M, got '%s'\n", argv[i] );
    return 1;
   }
   have_cli_site= 1;
  } else if ( 0 == strcmp( argv[i], "--extinction" ) && i + 1 < argc ) {
   extinction= atof( argv[++i] );
  } else if ( 0 == strcmp( argv[i], "--dark-sky" ) && i + 1 < argc ) {
   dark_sky_v= atof( argv[++i] );
  } else if ( 0 == strcmp( argv[i], "--max-peak" ) && i + 1 < argc ) {
   max_peak= atof( argv[++i] );
  } else if ( 0 == strcmp( argv[i], "--grid" ) && i + 1 < argc ) {
   if ( 2 != sscanf( argv[++i], "%dx%d", &nx, &ny ) || nx < 1 || ny < 1 || nx > AFQ_MAX_GRID || ny > AFQ_MAX_GRID ) {
    fprintf( stderr, "ERROR: --grid wants NXxNY with 1 to %d cells along each side, got '%s'\n", AFQ_MAX_GRID, argv[i] );
    return 1;
   }
  } else if ( 0 == strcmp( argv[i], "--v-range" ) && i + 1 < argc ) {
   if ( 2 != sscanf( argv[++i], "%lf,%lf", &v_bright, &v_faint ) || v_bright >= v_faint ) {
    fprintf( stderr, "ERROR: --v-range wants MIN,MAX, got '%s'\n", argv[i] );
    return 1;
   }
  } else {
   fprintf( stderr, "ERROR: unknown or incomplete option '%s'\n", argv[i] );
   print_usage( argv[0] );
   return 1;
  }
 }
 if ( extinction < 0.0 || extinction > 2.0 || dark_sky_v < 15.0 || dark_sky_v > 25.0 || max_peak <= 0.0 ) {
  fprintf( stderr, "ERROR: implausible --extinction, --dark-sky or --max-peak value\n" );
  return 1;
 }
 if ( NULL != strchr( frame_name, '\'' ) || NULL != strchr( sex_config, '\'' ) ) {
  fprintf( stderr, "ERROR: file names with a single quote are not supported\n" );
  return 1;
 }
 if ( 0 != access( frame_name, R_OK ) ) {
  fprintf( stderr, "ERROR: cannot read %s\n", frame_name );
  return 1;
 }
 if ( 0 != access( sex_config, R_OK ) || 0 != access( "lib/bin/sex", X_OK ) ) {
  fprintf( stderr, "ERROR: cannot find the SExtractor configuration %s or lib/bin/sex - run this from the VaST directory\n", sex_config );
  return 1;
 }
 slash= strrchr( frame_name, '/' );
 strncpy( frame_basename, slash == NULL ? frame_name : slash + 1, sizeof( frame_basename ) - 1 );
 frame_basename[sizeof( frame_basename ) - 1]= '\0';

 // The header: size, exposure, camera, field, site, WCS, the telescope's own altitude/airmass
 status= 0;
 fits_open_image( &fptr, frame_name, READONLY, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  return 1;
 }
 fits_get_img_size( fptr, 2, naxes, &status );
 if ( status != 0 || naxes[0] < 100 || naxes[1] < 100 ) {
  fprintf( stderr, "ERROR: cannot get a plausible image size from %s\n", frame_name );
  fits_close_file( fptr, &status );
  return 1;
 }
 naxis1= (double)naxes[0];
 naxis2= (double)naxes[1];
 status= 0;
 fits_read_key( fptr, TDOUBLE, "EXPTIME", &exptime, NULL, &status );
 if ( status != 0 ) {
  status= 0;
  fits_read_key( fptr, TDOUBLE, "EXPOSURE", &exptime, NULL, &status );
 }
 if ( status != 0 || exptime <= 0.0 ) {
  fprintf( stderr, "ERROR: no positive EXPTIME or EXPOSURE in %s\n", frame_name );
  fits_close_file( fptr, &status );
  return 1;
 }
 status= 0;
 fits_read_key( fptr, TSTRING, "TELESCOP", camera, NULL, &status );
 if ( status != 0 ) {
  status= 0;
  fits_read_key( fptr, TSTRING, "INSTRUME", camera, NULL, &status );
  if ( status != 0 ) {
   strncpy( camera, "unknown", sizeof( camera ) );
  }
 }
 status= 0;
 fits_read_key( fptr, TSTRING, "OBJECT", object, NULL, &status );
 if ( status != 0 ) {
  strncpy( object, "unknown", sizeof( object ) );
 }
 // no spaces in the values of the key=value line
 for ( i= 0; camera[i] != '\0'; i++ ) {
  if ( camera[i] == ' ' || camera[i] == '=' ) {
   camera[i]= '_';
  }
 }
 for ( i= 0; object[i] != '\0'; i++ ) {
  if ( object[i] == ' ' || object[i] == '=' ) {
   object[i]= '_';
  }
 }
 status= 0;
 have_header_centalt= 1;
 fits_read_key( fptr, TDOUBLE, "CENTALT", &header_centalt, NULL, &status );
 if ( status != 0 ) {
  have_header_centalt= 0;
 }
 status= 0;
 have_header_airmass= 1;
 fits_read_key( fptr, TDOUBLE, "AIRMASS", &header_airmass, NULL, &status );
 if ( status != 0 ) {
  have_header_airmass= 0;
 }
 if ( have_cli_site == 0 && 0 != read_site_from_header( fptr, &site ) ) {
  fprintf( stderr, "ERROR: no observing site in the header of %s - give it with --site LAT,LON,HEIGHT\n", frame_name );
  status= 0;
  fits_close_file( fptr, &status );
  return 1;
 }
 if ( 0 != read_wcs( fptr, &wcs ) ) {
  status= 0;
  fits_close_file( fptr, &status );
  return 1;
 }

 // The grid of cells: about square cells, 6 along the longer side unless given
 if ( nx == 0 ) {
  if ( naxis1 >= naxis2 ) {
   nx= 6;
   ny= (int)floor( 6.0 * naxis2 / naxis1 + 0.5 );
  } else {
   ny= 6;
   nx= (int)floor( 6.0 * naxis1 / naxis2 + 0.5 );
  }
  if ( nx < 1 ) {
   nx= 1;
  }
  if ( ny < 1 ) {
   ny= 1;
  }
 }
 n_cells= nx * ny;
 for ( i= 0; i < n_cells; i++ ) {
  memset( &cells[i], 0, sizeof( struct afq_cell ) );
 }

 // The sky: every AFQ_SKY_STEP-th pixel of every AFQ_SKY_STEP-th row
 row_buffer= (double *)malloc( (size_t)naxes[0] * sizeof( double ) );
 if ( row_buffer == NULL ) {
  fprintf( stderr, "ERROR: out of memory\n" );
  fits_close_file( fptr, &status );
  return 1;
 }
 sky_all= NULL;
 n_sky_all= 0;
 sky_all_allocated= 0;
 for ( row= 1; row <= naxes[1]; row+= AFQ_SKY_STEP ) {
  fpixel[0]= 1;
  fpixel[1]= row;
  status= 0;
  fits_read_pix( fptr, TDOUBLE, fpixel, naxes[0], NULL, row_buffer, NULL, &status );
  if ( status != 0 ) {
   fits_report_error( stderr, status );
   free( row_buffer );
   fits_close_file( fptr, &status );
   return 1;
  }
  for ( col= 1; col <= naxes[0]; col+= AFQ_SKY_STEP ) {
   value= row_buffer[col - 1];
   cell= cell_index( (double)col, (double)row, naxis1, naxis2, nx, ny );
   if ( cell >= 0 ) {
    if ( 0 != append_value( &cells[cell].sky_values, &cells[cell].n_sky, &cells[cell].sky_allocated, value ) || 0 != append_value( &sky_all, &n_sky_all, &sky_all_allocated, value ) ) {
     fprintf( stderr, "ERROR: out of memory\n" );
     return 1;
    }
   }
  }
 }
 free( row_buffer );
 status= 0;
 fits_close_file( fptr, &status );

 // The observing time: mid-exposure, UTC, as everywhere in VaST
 memset( gettime_stderr_output, 0, sizeof( gettime_stderr_output ) );
 memset( gettime_log_output, 0, sizeof( gettime_log_output ) );
 if ( 0 != gettime( frame_name, &jd, &timesys, 0, &dim_x, &dim_y, gettime_stderr_output, gettime_log_output, 0, 0, NULL ) ) {
  fprintf( stderr, "ERROR: cannot get the observing time of %s\n", frame_name );
  return 1;
 }

 // SExtractor with a parameter list of its own, in a temporary directory
 if ( NULL != getenv( "TMPDIR" ) && strlen( getenv( "TMPDIR" ) ) < FILENAME_LENGTH - 32 ) {
  snprintf( tmp_dir_template, sizeof( tmp_dir_template ), "%s/vast_afq_XXXXXX", getenv( "TMPDIR" ) );
 } else {
  snprintf( tmp_dir_template, sizeof( tmp_dir_template ), "/tmp/vast_afq_XXXXXX" );
 }
 tmp_dir= mkdtemp( tmp_dir_template );
 if ( tmp_dir == NULL ) {
  fprintf( stderr, "ERROR: cannot create a temporary directory\n" );
  return 1;
 }
 snprintf( param_file, sizeof( param_file ), "%s/afq.param", tmp_dir );
 snprintf( catalog_file, sizeof( catalog_file ), "%s/afq.cat", tmp_dir );
 f= fopen( param_file, "w" );
 if ( f == NULL ) {
  fprintf( stderr, "ERROR: cannot write %s\n", param_file );
  rmdir( tmp_dir );
  return 1;
 }
 fprintf( f, "X_IMAGE\nY_IMAGE\nFLUX_AUTO\nFLUXERR_AUTO\nFLUX_MAX\nBACKGROUND\nFWHM_IMAGE\nA_IMAGE\nB_IMAGE\nFLAGS\n" );
 fclose( f );
 snprintf( command, sizeof( command ), "lib/bin/sex '%s' -c '%s' -PARAMETERS_NAME '%s' -CATALOG_NAME '%s' -CATALOG_TYPE ASCII -VERBOSE_TYPE QUIET -CHECKIMAGE_TYPE NONE > /dev/null 2>&1", frame_name, sex_config, param_file, catalog_file );
 if ( 0 != system( command ) ) {
  fprintf( stderr, "ERROR running SExtractor: %s\n", command );
  unlink( param_file );
  unlink( catalog_file );
  rmdir( tmp_dir );
  return 1;
 }
 detections= NULL;
 n_detections= 0;
 detections_allocated= 0;
 f= fopen( catalog_file, "r" );
 if ( f == NULL ) {
  fprintf( stderr, "ERROR: SExtractor wrote no catalog %s\n", catalog_file );
  unlink( param_file );
  rmdir( tmp_dir );
  return 1;
 }
 while ( NULL != fgets( line, sizeof( line ), f ) ) {
  if ( line[0] == '#' ) {
   continue;
  }
  if ( n_detections >= detections_allocated ) {
   detections_allocated= detections_allocated < 1024 ? 1024 : 2 * detections_allocated;
   new_detections= (struct afq_detection *)realloc( detections, (size_t)detections_allocated * sizeof( struct afq_detection ) );
   if ( new_detections == NULL ) {
    fprintf( stderr, "ERROR: out of memory\n" );
    fclose( f );
    return 1;
   }
   detections= new_detections;
  }
  if ( 10 != sscanf( line, "%lf %lf %lf %lf %lf %lf %lf %lf %lf %d", &detections[n_detections].x, &detections[n_detections].y, &detections[n_detections].flux, &detections[n_detections].flux_err, &detections[n_detections].peak, &detections[n_detections].background, &detections[n_detections].fwhm, &detections[n_detections].a, &detections[n_detections].b, &detections[n_detections].flags ) ) {
   continue;
  }
  n_detections++;
 }
 fclose( f );
 unlink( param_file );
 unlink( catalog_file );
 rmdir( tmp_dir );

 // A hash of the detections by position for the matching
 hash_nx= (int)( naxis1 / AFQ_HASH_CELL_PIX ) + 2;
 hash_ny= (int)( naxis2 / AFQ_HASH_CELL_PIX ) + 2;
 hash_head= (int *)malloc( (size_t)hash_nx * (size_t)hash_ny * sizeof( int ) );
 hash_next= (int *)malloc( ( n_detections > 0 ? (size_t)n_detections : 1 ) * sizeof( int ) );
 if ( hash_head == NULL || hash_next == NULL ) {
  fprintf( stderr, "ERROR: out of memory\n" );
  return 1;
 }
 for ( i= 0; i < hash_nx * hash_ny; i++ ) {
  hash_head[i]= -1;
 }
 n_snr5= 0;
 for ( i= 0; i < n_detections; i++ ) {
  hx= (int)( detections[i].x / AFQ_HASH_CELL_PIX );
  hy= (int)( detections[i].y / AFQ_HASH_CELL_PIX );
  if ( hx < 0 || hy < 0 || hx >= hash_nx || hy >= hash_ny ) {
   hash_next[i]= -1;
   continue;
  }
  hash_next[i]= hash_head[hy * hash_nx + hx];
  hash_head[hy * hash_nx + hx]= i;
  if ( detections[i].flux_err > 0.0 && detections[i].flux / detections[i].flux_err >= 5.0 && detections[i].flags < 8 ) {
   n_snr5++;
  }
 }

 // The field: its centre and the radius that holds the whole frame
 pixel_to_radec( &wcs, ( naxis1 + 1.0 ) / 2.0, ( naxis2 + 1.0 ) / 2.0, &center_ra, &center_dec );
 radius_deg= 0.0;
 for ( i= 0; i < 4; i++ ) {
  pixel_to_radec( &wcs, ( i % 2 == 0 ) ? 0.5 : naxis1 + 0.5, ( i < 2 ) ? 0.5 : naxis2 + 0.5, &corner_ra, &corner_dec );
  value= acos( sin( center_dec * AFQ_DEG2RAD ) * sin( corner_dec * AFQ_DEG2RAD ) + cos( center_dec * AFQ_DEG2RAD ) * cos( corner_dec * AFQ_DEG2RAD ) * cos( ( corner_ra - center_ra ) * AFQ_DEG2RAD ) ) / AFQ_DEG2RAD;
  if ( value > radius_deg ) {
   radius_deg= value;
  }
 }
 radius_deg+= 0.1;

 // Tycho-2 stars in the frame, matched to the detections; their zero points go to the cells
 years_since_2000= ( jd - 2451545.0 ) / 365.25;
 zp_all= NULL;
 n_zp_all= 0;
 zp_all_allocated= 0;
 fwhm_values= NULL;
 elongation_values= NULL;
 n_good_shape= 0;
 shape_allocated= 0;
 n_tycho_expected= 0;
 n_tycho_found= 0;
 for ( tycho_file_counter= 0; tycho_file_counter < 20; tycho_file_counter++ ) {
  snprintf( tycho_file_name, sizeof( tycho_file_name ), "lib/catalogs/tycho2/tyc2.dat.%02d", tycho_file_counter );
  f= fopen( tycho_file_name, "r" );
  if ( f == NULL ) {
   fprintf( stderr, "ERROR: cannot open %s - the local Tycho-2 catalog is needed (run this from the VaST directory)\n", tycho_file_name );
   return 1;
  }
  while ( NULL != fgets( tycho_line, sizeof( tycho_line ), f ) ) {
   n_fields= split_tycho2_line( tycho_line, tycho_fields, 32 );
   if ( n_fields < 26 ) {
    continue;
   }
   vt= atof( tycho_fields[19] );
   if ( field_is_blank( tycho_fields[19] ) || vt <= 0.0 ) {
    continue;
   }
   bt= atof( tycho_fields[17] );
   // V from BT and VT (ESA 1997); VT alone when BT is missing
   if ( field_is_blank( tycho_fields[17] ) || bt <= 0.0 ) {
    v_mag= vt;
   } else {
    v_mag= vt - 0.090 * ( bt - vt );
   }
   if ( v_mag < v_bright && v_mag < 6.0 ) {
    continue;
   }
   if ( v_mag > v_faint && v_mag > AFQ_COUNT_V_FAINT ) {
    continue;
   }
   if ( field_is_blank( tycho_fields[2] ) ) {
    // no mean position: the observed position at about 1991.5, no proper motion
    ra= atof( tycho_fields[24] );
    dec= atof( tycho_fields[25] );
   } else {
    ra= atof( tycho_fields[2] );
    dec= atof( tycho_fields[3] );
    pm_ra= atof( tycho_fields[4] );
    pm_dec= atof( tycho_fields[5] );
    dec+= pm_dec / 3600000.0 * years_since_2000;
    if ( fabs( dec ) < 89.9 ) {
     ra+= pm_ra / 3600000.0 * years_since_2000 / cos( dec * AFQ_DEG2RAD );
    }
   }
   // a quick cut on declination before the exact distance
   if ( fabs( dec - center_dec ) > radius_deg ) {
    continue;
   }
   value= sin( center_dec * AFQ_DEG2RAD ) * sin( dec * AFQ_DEG2RAD ) + cos( center_dec * AFQ_DEG2RAD ) * cos( dec * AFQ_DEG2RAD ) * cos( ( ra - center_ra ) * AFQ_DEG2RAD );
   if ( value < cos( radius_deg * AFQ_DEG2RAD ) ) {
    continue;
   }
   if ( 0 != radec_to_pixel( &wcs, ra, dec, &x, &y ) ) {
    continue;
   }
   // stay 10 pixels clear of the frame edges
   if ( x < 10.5 || y < 10.5 || x > naxis1 - 9.5 || y > naxis2 - 9.5 ) {
    continue;
   }
   cell= cell_index( x, y, naxis1, naxis2, nx, ny );
   if ( cell < 0 ) {
    continue;
   }
   // the nearest detection within AFQ_MATCH_RADIUS_PIX
   best= -1;
   best_d2= AFQ_MATCH_RADIUS_PIX * AFQ_MATCH_RADIUS_PIX;
   hx= (int)( x / AFQ_HASH_CELL_PIX );
   hy= (int)( y / AFQ_HASH_CELL_PIX );
   for ( ihy= hy - 1; ihy <= hy + 1; ihy++ ) {
    for ( ihx= hx - 1; ihx <= hx + 1; ihx++ ) {
     if ( ihx < 0 || ihy < 0 || ihx >= hash_nx || ihy >= hash_ny ) {
      continue;
     }
     for ( k= hash_head[ihy * hash_nx + ihx]; k >= 0; k= hash_next[k] ) {
      dx= detections[k].x - x;
      dy= detections[k].y - y;
      d2= dx * dx + dy * dy;
      if ( d2 <= best_d2 ) {
       best_d2= d2;
       best= k;
      }
     }
    }
   }
   // the fraction of the Tycho-2 stars found, counted where Tycho-2 is nearly complete
   if ( v_mag >= 6.0 && v_mag <= AFQ_COUNT_V_FAINT ) {
    cells[cell].n_expected++;
    n_tycho_expected++;
    if ( best >= 0 ) {
     cells[cell].n_found++;
     n_tycho_found++;
    }
   }
   if ( best < 0 || v_mag < v_bright || v_mag > v_faint ) {
    continue;
   }
   // a zero-point star: unsaturated, not truncated or corrupted, bright enough
   if ( detections[best].flags >= 4 || detections[best].flux <= 0.0 || detections[best].flux_err <= 0.0 ) {
    continue;
   }
   if ( detections[best].flux / detections[best].flux_err < AFQ_ZP_MIN_SNR || detections[best].peak > max_peak ) {
    continue;
   }
   value= v_mag + 2.5 * log10( detections[best].flux / exptime );
   if ( 0 != append_value( &cells[cell].zp_values, &cells[cell].n_zp, &cells[cell].zp_allocated, value ) || 0 != append_value( &zp_all, &n_zp_all, &zp_all_allocated, value ) ) {
    fprintf( stderr, "ERROR: out of memory\n" );
    return 1;
   }
   if ( detections[best].flags == 0 && detections[best].b > 0.0 && detections[best].fwhm > 0.0 ) {
    j= shape_allocated;
    if ( 0 != append_value( &fwhm_values, &n_good_shape, &shape_allocated, detections[best].fwhm ) ) {
     fprintf( stderr, "ERROR: out of memory\n" );
     return 1;
    }
    // the elongation array grows in step with the FWHM array
    if ( shape_allocated != j ) {
     elongation_values= (double *)realloc( elongation_values, (size_t)shape_allocated * sizeof( double ) );
     if ( elongation_values == NULL ) {
      fprintf( stderr, "ERROR: out of memory\n" );
      return 1;
     }
    }
    elongation_values[n_good_shape - 1]= detections[best].a / detections[best].b;
   }
  }
  fclose( f );
 }
 free( hash_head );
 free( hash_next );

 // The frame zero point and its scatter
 zp_frame= 0.0;
 zp_sigma= 0.0;
 if ( n_zp_all >= AFQ_MIN_STARS_PER_CELL ) {
  zp_frame= median_in_place( zp_all, n_zp_all );
  zp_sigma= sigma_mad_in_place( zp_all, n_zp_all, zp_frame );
 }

 // The geometry at the frame centre, and per cell
 sun_moon_compute( jd, &site, 1, center_ra, center_dec, extinction, dark_sky_v, &geometry );
 cell_values= (double *)malloc( (size_t)n_cells * sizeof( double ) );
 if ( cell_values == NULL ) {
  fprintf( stderr, "ERROR: out of memory\n" );
  return 1;
 }
 n_cells_with_zp= 0;
 n_cells_with_count= 0;
 for ( i= 0; i < n_cells; i++ ) {
  // the centre of the cell; i % nx is its column, i / nx (integer division) its row
  pixel_to_radec( &wcs, ( (double)( i % nx ) + 0.5 ) * naxis1 / nx + 0.5, ( floor( (double)i / (double)nx ) + 0.5 ) * naxis2 / ny + 0.5, &cell_center_ra, &cell_center_dec );
  sun_moon_compute( jd, &site, 1, cell_center_ra, cell_center_dec, extinction, dark_sky_v, &cell_geometry );
  cells[i].alt= cell_geometry.target_alt_deg;
  cells[i].airmass= cell_geometry.target_airmass;
  if ( cells[i].n_zp >= AFQ_MIN_STARS_PER_CELL ) {
   cells[i].zp= median_in_place( cells[i].zp_values, cells[i].n_zp );
   cell_values[n_cells_with_zp]= cells[i].zp + extinction * cells[i].airmass;
   n_cells_with_zp++;
  }
  if ( cells[i].n_sky > 0 ) {
   cells[i].sky= median_in_place( cells[i].sky_values, cells[i].n_sky );
  }
  if ( cells[i].n_expected >= AFQ_MIN_STARS_PER_CELL ) {
   n_cells_with_count++;
  }
 }
 // the extinction-corrected zero points: median, worst and best cell
 zp_corr_median= 0.0;
 zp_corr_min= 0.0;
 zp_corr_max= 0.0;
 if ( n_cells_with_zp > 0 ) {
  zp_corr_median= median_in_place( cell_values, n_cells_with_zp );
  zp_corr_min= cell_values[0];
  zp_corr_max= cell_values[n_cells_with_zp - 1];
 }
 // the fraction of the Tycho-2 stars found: median and worst cell
 found_fraction_min= 0.0;
 found_fraction_median= 0.0;
 j= 0;
 for ( i= 0; i < n_cells; i++ ) {
  if ( cells[i].n_expected >= AFQ_MIN_STARS_PER_CELL ) {
   cell_values[j++]= (double)cells[i].n_found / (double)cells[i].n_expected;
  }
 }
 if ( j > 0 ) {
  found_fraction_median= median_in_place( cell_values, j );
  found_fraction_min= cell_values[0];
 }

 // The sky
 sky_median= 0.0;
 sky_sigma= 0.0;
 if ( n_sky_all > 0 ) {
  sky_median= median_in_place( sky_all, n_sky_all );
  sky_sigma= sigma_mad_in_place( sky_all, n_sky_all, sky_median );
 }

 // Star size and shape
 fwhm_median= 0.0;
 elongation_median= 0.0;
 if ( n_good_shape > 0 ) {
  fwhm_median= median_in_place( fwhm_values, n_good_shape );
  elongation_median= median_in_place( elongation_values, n_good_shape );
 }

 // The limiting magnitude: the median magnitude of the detections with a signal-to-noise
 // ratio of 4.5 to 5.5. The fitted SNR-magnitude model VaST uses for the transient search
 // (src/detection_limit.c) is printed too (lim_mag_fit), but on the archive frames it jumped by
 // more than a magnitude between two frames of one upload taken a minute apart (2026-11-23).
 lim_snr5= 0.0;
 n_lim_snr5= 0;
 if ( n_zp_all >= AFQ_MIN_STARS_PER_CELL ) {
  lim_mag_values= (double *)malloc( ( n_detections > 0 ? (size_t)n_detections : 1 ) * sizeof( double ) );
  if ( lim_mag_values == NULL ) {
   fprintf( stderr, "ERROR: out of memory\n" );
   return 1;
  }
  for ( i= 0; i < n_detections; i++ ) {
   if ( detections[i].flags >= 8 || detections[i].flux <= 0.0 || detections[i].flux_err <= 0.0 ) {
    continue;
   }
   value= detections[i].flux / detections[i].flux_err;
   if ( value >= 4.5 && value <= 5.5 ) {
    lim_mag_values[n_lim_snr5]= zp_frame - 2.5 * log10( detections[i].flux / exptime );
    n_lim_snr5++;
   }
  }
  if ( n_lim_snr5 >= AFQ_MIN_SNR5_DETECTIONS ) {
   lim_snr5= median_in_place( lim_mag_values, n_lim_snr5 );
  }
  free( lim_mag_values );
 }
 lim_mag= 0.0;
 lim_success= 0;
 if ( n_zp_all >= AFQ_MIN_STARS_PER_CELL && n_detections > 100 ) {
  lim_mag_values= (double *)malloc( (size_t)n_detections * sizeof( double ) );
  lim_snr_values= (double *)malloc( (size_t)n_detections * sizeof( double ) );
  if ( lim_mag_values == NULL || lim_snr_values == NULL ) {
   fprintf( stderr, "ERROR: out of memory\n" );
   return 1;
  }
  n_lim= 0;
  lim_allocated= n_detections;
  for ( i= 0; i < n_detections && n_lim < lim_allocated; i++ ) {
   if ( detections[i].flags >= 8 || detections[i].flux <= 0.0 || detections[i].flux_err <= 0.0 ) {
    continue;
   }
   lim_mag_values[n_lim]= zp_frame - 2.5 * log10( detections[i].flux / exptime );
   lim_snr_values[n_lim]= detections[i].flux / detections[i].flux_err;
   n_lim++;
  }
  if ( n_lim > 100 ) {
   lim_mag= get_detection_limit_sn( lim_mag_values, lim_snr_values, (size_t)n_lim, MIN_SNR_TRANSIENT_DETECTION, &lim_success );
   if ( lim_success != 1 || lim_mag != lim_mag || lim_mag < 0.0 || lim_mag > 30.0 ) {
    lim_success= 0;
   }
  }
  free( lim_mag_values );
  free( lim_snr_values );
 }

 // The line of results
 fprintf( stdout, "frame=%s", frame_basename );
 if ( n_zp_all < AFQ_MIN_STARS_PER_CELL ) {
  fprintf( stdout, " status=NO_ZEROPOINT_STARS" );
 } else {
  fprintf( stdout, " status=OK" );
 }
 fprintf( stdout, " camera=%s object=%s jd=%.6f exptime=%.3f naxis1=%ld naxis2=%ld", camera, object, jd, exptime, naxes[0], naxes[1] );
 fprintf( stdout, " site_lat=%.6f site_lon=%.6f site_height=%.1f site_source=%s", site.latitude_deg, site.longitude_deg, site.height_m, have_cli_site != 0 ? "option" : "header" );
 fprintf( stdout, " center_ra=%.5f center_dec=%.5f center_alt=%.3f center_airmass=%.4f", center_ra, center_dec, geometry.target_alt_deg, geometry.target_airmass );
 print_na_or_value( "header_centalt", have_header_centalt, header_centalt, "%.3f" );
 print_na_or_value( "header_airmass", have_header_airmass, header_airmass, "%.4f" );
 fprintf( stdout, " sun_alt=%.3f moon_alt=%.3f moon_illumination=%.4f moon_separation=%.3f moon_sky_brightening=%.4f extinction=%.3f dark_sky=%.2f", geometry.sun_alt_deg, geometry.moon_alt_deg, geometry.moon_illuminated_fraction, geometry.moon_target_separation_deg, geometry.moon_sky_brightening_mag, extinction, dark_sky_v );
 fprintf( stdout, " n_detections=%d n_snr5=%d n_tycho_expected=%d n_tycho_found=%d n_zp_stars=%d", n_detections, n_snr5, n_tycho_expected, n_tycho_found, n_zp_all );
 print_na_or_value( "zp", n_zp_all >= AFQ_MIN_STARS_PER_CELL, zp_frame, "%.4f" );
 print_na_or_value( "zp_sigma", n_zp_all >= AFQ_MIN_STARS_PER_CELL, zp_sigma, "%.4f" );
 print_na_or_value( "zp_corr", n_cells_with_zp > 0, zp_corr_median, "%.4f" );
 print_na_or_value( "zp_corr_worst_cell", n_cells_with_zp > 0, zp_corr_min, "%.4f" );
 print_na_or_value( "zp_corr_best_cell", n_cells_with_zp > 0, zp_corr_max, "%.4f" );
 fprintf( stdout, " cells=%dx%d cells_with_zp=%d", nx, ny, n_cells_with_zp );
 print_na_or_value( "found_fraction", n_cells_with_count > 0, found_fraction_median, "%.3f" );
 print_na_or_value( "found_fraction_worst_cell", n_cells_with_count > 0, found_fraction_min, "%.3f" );
 fprintf( stdout, " sky=%.2f sky_rate=%.4f sky_sigma=%.2f", sky_median, sky_median / exptime, sky_sigma );
 print_na_or_value( "fwhm", n_good_shape > 0, fwhm_median, "%.3f" );
 print_na_or_value( "elongation", n_good_shape > 0, elongation_median, "%.3f" );
 print_na_or_value( "lim_mag", n_lim_snr5 >= AFQ_MIN_SNR5_DETECTIONS, lim_snr5, "%.3f" );
 print_na_or_value( "lim_mag_fit", lim_success == 1, lim_mag, "%.3f" );
 // per cell, row by row from the lower left corner (FITS pixel 1,1)
 fprintf( stdout, " cell_zp_corr=" );
 for ( i= 0; i < n_cells; i++ ) {
  if ( cells[i].n_zp >= AFQ_MIN_STARS_PER_CELL ) {
   fprintf( stdout, "%s%.3f", i == 0 ? "" : ",", cells[i].zp + extinction * cells[i].airmass );
  } else {
   fprintf( stdout, "%sNA", i == 0 ? "" : "," );
  }
 }
 fprintf( stdout, " cell_airmass=" );
 for ( i= 0; i < n_cells; i++ ) {
  fprintf( stdout, "%s%.3f", i == 0 ? "" : ",", cells[i].airmass );
 }
 fprintf( stdout, " cell_found=" );
 for ( i= 0; i < n_cells; i++ ) {
  fprintf( stdout, "%s%d/%d", i == 0 ? "" : ",", cells[i].n_found, cells[i].n_expected );
 }
 fprintf( stdout, " cell_sky=" );
 for ( i= 0; i < n_cells; i++ ) {
  fprintf( stdout, "%s%.1f", i == 0 ? "" : ",", cells[i].sky );
 }
 fprintf( stdout, "\n" );

 for ( i= 0; i < n_cells; i++ ) {
  free( cells[i].zp_values );
  free( cells[i].sky_values );
 }
 free( cell_values );
 free( zp_all );
 free( sky_all );
 free( fwhm_values );
 free( elongation_values );
 free( detections );
 return 0;
}
