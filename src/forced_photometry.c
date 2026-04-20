// Forced aperture photometry at one or more pixel positions on a FITS image.
//
// Usage (single position):
//   forced_photometry image.fits center_x center_y aperture_diameter
// Usage (list mode):
//   forced_photometry image.fits --list listfile aperture_diameter
//
// List file: one position per line "center_x center_y [label]".
// Lines starting with '#' or '%' and blank lines are skipped.
// If label is missing, the 1-based line index is used.
//
// Reads calib.txt_param, bad_region.lst, and default.sex from current directory.
// Output (single, stdout): cal_mag mag_err status
// Output (list,   stdout): label center_x center_y cal_mag mag_err status
//
// Ported Buie/DAOPHOT circle-rectangle overlap algorithm from
// pixwt_circleaperture.py (D. Jones, based on IDL Astronomy Users Library).

// Background estimation method:
// Define USE_SEXTRACTOR_BACKGROUND to use SExtractor-style mode estimation
// (mode = 2.5*median - 1.5*mean, with iterative kappa-sigma clipping).
// Undefine to use simple sigma-clipped median with MAD-based sigma.
#define USE_SEXTRACTOR_BACKGROUND

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "fitsio.h"

#include "vast_limits.h"
#include "count_lines_in_ASCII_file.h"
#include "quickselect.h"

// From exclude_region.c (linked as exclude_region.o)
int read_bad_CCD_regions_lst( double *X1, double *Y1, double *X2, double *Y2, int *N );
int exclude_region( double *X1, double *Y1, double *X2, double *Y2, int N, double X, double Y, double aperture );

// ------------------------------------------------------------------
// Buie/DAOPHOT exact circle-rectangle overlap (scalar C port)
// ------------------------------------------------------------------

// Area of a circular wedge defined by two radial lines from origin
// through (x, y0) and (x, y1) on a circle of radius r centered at origin.
static double arc_scalar( double x, double y0, double y1, double r ) {
 // Must use atan(y/x), NOT atan2(y,x), to match the original algorithm.
 // Division by zero is prevented by the x==0 check in oneside_scalar.
 return 0.5 * r * r * ( atan( y1 / x ) - atan( y0 / x ) );
}

// Area of a triangle with vertices at origin, (x, y0), and (x, y1).
static double chord_scalar( double x, double y0, double y1 ) {
 return 0.5 * x * ( y1 - y0 );
}

// Area of intersection between a triangle (origin, (x,y0), (x,y1))
// and a circle of radius r centered at origin.
static double oneside_scalar( double x, double y0, double y1, double r ) {
 double yh;

 if ( x == 0.0 ) {
  return 0.0;
 }
 if ( fabs( x ) >= r ) {
  return arc_scalar( x, y0, y1, r );
 }

 yh= sqrt( r * r - x * x );

 if ( y0 <= -yh ) {
  if ( y1 <= -yh ) {
   return arc_scalar( x, y0, y1, r );
  } else if ( y1 <= yh ) {
   return arc_scalar( x, y0, -yh, r ) + chord_scalar( x, -yh, y1 );
  } else {
   return arc_scalar( x, y0, -yh, r ) + chord_scalar( x, -yh, yh ) + arc_scalar( x, yh, y1, r );
  }
 } else if ( y0 < yh ) {
  if ( y1 <= -yh ) {
   return chord_scalar( x, y0, -yh ) + arc_scalar( x, -yh, y1, r );
  } else if ( y1 <= yh ) {
   return chord_scalar( x, y0, y1 );
  } else {
   return chord_scalar( x, y0, yh ) + arc_scalar( x, yh, y1, r );
  }
 } else {
  if ( y1 <= -yh ) {
   return arc_scalar( x, y0, yh, r ) + chord_scalar( x, yh, -yh ) + arc_scalar( x, -yh, y1, r );
  } else if ( y1 <= yh ) {
   return arc_scalar( x, y0, yh, r ) + chord_scalar( x, yh, y1 );
  } else {
   return arc_scalar( x, y0, y1, r );
  }
 }
}

// Compute area of overlap between a circle (xc, yc, r) and a rectangle
// with corners (x0, y0) and (x1, y1).
static double intarea_scalar( double xc, double yc, double r,
                              double x0, double x1, double y0, double y1 ) {
 // Shift so the circle is at the origin
 x0= x0 - xc;
 y0= y0 - yc;
 x1= x1 - xc;
 y1= y1 - yc;

 return oneside_scalar( x1, y0, y1, r )
      + oneside_scalar( y1, -x1, -x0, r )
      + oneside_scalar( -x0, -y1, -y0, r )
      + oneside_scalar( -y0, x0, x1, r );
}

// Compute the fraction of a unit pixel at (px, py) that is interior
// to a circle centered at (xc, yc) with radius r.
// Uses PixwtFast optimization: skip full computation for pixels
// clearly inside or outside the aperture.
static double pixwt_scalar( double xc, double yc, double r, double px, double py ) {
 double dx, dy, r2;
 double rintlim, rintlim2, rextlim2;

 dx= px - xc;
 dy= py - yc;
 r2= dx * dx + dy * dy;

 // External radius of the oversampled annulus (> r + sqrt(2)/2)
 rextlim2= ( r + 0.75 ) * ( r + 0.75 );
 if ( r2 > rextlim2 ) {
  return 0.0;
 }

 // Internal radius of the oversampled annulus (< r - sqrt(2)/2)
 rintlim= r - 0.75;
 if ( rintlim > 0.0 ) {
  rintlim2= rintlim * rintlim;
 } else {
  rintlim2= 0.0;
 }
 if ( r2 < rintlim2 ) {
  return 1.0;
 }

 // Boundary pixel: compute exact overlap
 return intarea_scalar( xc, yc, r, px - 0.5, px + 0.5, py - 0.5, py + 0.5 );
}

// ------------------------------------------------------------------
// Utility functions
// ------------------------------------------------------------------

// Parse SATUR_LEVEL from default.sex, return the value or 55000.0 as default.
static double read_satur_level_from_default_sex( void ) {
 FILE *f;
 char buf[256];
 double satur_level;
 char keyword[64];

 satur_level= 55000.0;
 f= fopen( "default.sex", "r" );
 if ( f == NULL ) {
  fprintf( stderr, "WARNING: cannot open default.sex, using SATUR_LEVEL=%.1f\n", satur_level );
  return satur_level;
 }
 while ( fgets( buf, sizeof( buf ), f ) != NULL ) {
  if ( buf[0] == '#' ) {
   continue;
  }
  if ( 2 == sscanf( buf, "%63s %lf", keyword, &satur_level ) ) {
   if ( 0 == strcmp( keyword, "SATUR_LEVEL" ) ) {
    fclose( f );
    return satur_level;
   }
  }
 }
 fclose( f );
 satur_level= 55000.0;
 fprintf( stderr, "WARNING: SATUR_LEVEL not found in default.sex, using %.1f\n", satur_level );
 return satur_level;
}

// Read calibration parameters from a calib.txt_param-style file.
// If calib_path is NULL, defaults to "calib.txt_param" in the current directory.
// Format: fit_function p3 p2 p1 p0
// Returns 0 on success, 1 on failure.
static int read_calib_param( const char *calib_path,
                             double *p3, double *p2, double *p1, double *p0 ) {
 FILE *f;
 double fit_fn;
 const char *path;

 path= ( calib_path != NULL ) ? calib_path : "calib.txt_param";

 f= fopen( path, "r" );
 if ( f == NULL ) {
  fprintf( stderr, "ERROR: cannot open %s\n", path );
  return 1;
 }
 if ( 5 != fscanf( f, "%lf %lf %lf %lf %lf", &fit_fn, p3, p2, p1, p0 ) ) {
  fprintf( stderr, "ERROR: cannot parse %s\n", path );
  fclose( f );
  return 1;
 }
 fclose( f );
 fprintf( stderr, "Calibration (from %s, fit_function=%.0f): cal_mag = %.6f * x^2 + %.6f * x + %.6f\n",
          path, fit_fn, *p2, *p1, *p0 );
 return 0;
}

// ------------------------------------------------------------------
// Per-position forced photometry.
//
// Uses pre-loaded pixel data, bad-region arrays, saturation level, and
// calibration polynomial; writes the magnitude, magnitude error, and status
// string via the out parameters.  status_str_out must have >= 32 bytes.
// Scratch buffers (annulus_vals, annulus_copy, abs_dev) must be sized for
// the given aperture (n_annulus_alloc >= 4 * annulus_outer^2 + 100).
// ------------------------------------------------------------------
static void photometry_at_position( const double *pix, long naxis1, long naxis2,
                                    double satur_level,
                                    double *bad_X1, double *bad_Y1,
                                    double *bad_X2, double *bad_Y2,
                                    int n_bad_regions,
                                    double calib_p2, double calib_p1, double calib_p0,
                                    double center_x, double center_y,
                                    double aperture_diameter,
                                    double *annulus_vals, double *annulus_copy, double *abs_dev,
                                    int n_annulus_alloc,
                                    double *cal_mag_out, double *mag_err_out,
                                    char *status_str_out ) {

 double aperture_radius, annulus_inner, annulus_outer;
 int ix, iy;
 int ix_min, ix_max, iy_min, iy_max;
 double weight, pix_val;
 long pix_idx;
 double dist2;
 int n_annulus, n_clipped;
 int i;
 double bg_per_pixel, sigma_bg;
#ifdef USE_SEXTRACTOR_BACKGROUND
 double clip_median, clip_mean, clip_sigma, bg_mode;
 int n_prev, iter;
 double sum_val, sum_val2;
#else
 double bg_median, bg_mad, sigma_mad;
#endif
 double sum_aperture, n_eff;
 double net_flux, noise;
 double inst_mag, cal_mag, mag_err;

 aperture_radius= aperture_diameter / 2.0;
 annulus_inner= 4.0 * aperture_radius;
 annulus_outer= 10.0 * aperture_radius;

 *cal_mag_out= 99.0;
 *mag_err_out= 99.0;

 fprintf( stderr, "Forced photometry: center=(%.2f, %.2f) aperture=%.1f\n",
          center_x, center_y, aperture_diameter );
 fprintf( stderr, "Annulus: inner=%.2f outer=%.2f\n", annulus_inner, annulus_outer );

 // ------------------------------------------------------------------
 // Edge check: entire annulus must fit within image
 // ------------------------------------------------------------------
 if ( center_x - annulus_outer < 1.0 || center_x + annulus_outer > (double)naxis1 ||
      center_y - annulus_outer < 1.0 || center_y + annulus_outer > (double)naxis2 ) {
  fprintf( stderr, "ERROR: aperture/annulus extends beyond image edge\n" );
  strncpy( status_str_out, "edge", 31 );
  status_str_out[31]= '\0';
  return;
 }

 // ------------------------------------------------------------------
 // Bad region check
 // ------------------------------------------------------------------
 if ( 0 != exclude_region( bad_X1, bad_Y1, bad_X2, bad_Y2, n_bad_regions,
                            center_x, center_y, aperture_diameter ) ) {
  fprintf( stderr, "ERROR: position falls in a bad CCD region (bad_region.lst)\n" );
  strncpy( status_str_out, "bad_region", 31 );
  status_str_out[31]= '\0';
  return;
 }

 // ------------------------------------------------------------------
 // Saturation and NaN/Inf check over aperture pixels
 // ------------------------------------------------------------------
 ix_min= (int)floor( center_x - aperture_radius - 1.0 );
 ix_max= (int)ceil( center_x + aperture_radius + 1.0 );
 iy_min= (int)floor( center_y - aperture_radius - 1.0 );
 iy_max= (int)ceil( center_y + aperture_radius + 1.0 );
 if ( ix_min < 1 ) ix_min= 1;
 if ( iy_min < 1 ) iy_min= 1;
 if ( ix_max > naxis1 ) ix_max= (int)naxis1;
 if ( iy_max > naxis2 ) iy_max= (int)naxis2;

 for ( iy= iy_min; iy <= iy_max; iy++ ) {
  for ( ix= ix_min; ix <= ix_max; ix++ ) {
   weight= pixwt_scalar( center_x, center_y, aperture_radius, (double)ix, (double)iy );
   if ( weight <= 0.0 ) {
    continue;
   }
   pix_idx= ( (long)iy - 1 ) * naxis1 + ( (long)ix - 1 );
   pix_val= pix[pix_idx];
   if ( isnan( pix_val ) || isinf( pix_val ) ) {
    fprintf( stderr, "ERROR: NaN/Inf pixel at (%d, %d) within aperture\n", ix, iy );
    strncpy( status_str_out, "nan_pixel", 31 );
    status_str_out[31]= '\0';
    return;
   }
   if ( pix_val >= satur_level ) {
    fprintf( stderr, "ERROR: saturated pixel at (%d, %d) value=%.1f >= %.1f\n",
             ix, iy, pix_val, satur_level );
    strncpy( status_str_out, "saturated", 31 );
    status_str_out[31]= '\0';
    return;
   }
  }
 }

 // ------------------------------------------------------------------
 // Background estimation from annulus
 // ------------------------------------------------------------------
 ix_min= (int)floor( center_x - annulus_outer - 1.0 );
 ix_max= (int)ceil( center_x + annulus_outer + 1.0 );
 iy_min= (int)floor( center_y - annulus_outer - 1.0 );
 iy_max= (int)ceil( center_y + annulus_outer + 1.0 );
 if ( ix_min < 1 ) ix_min= 1;
 if ( iy_min < 1 ) iy_min= 1;
 if ( ix_max > naxis1 ) ix_max= (int)naxis1;
 if ( iy_max > naxis2 ) iy_max= (int)naxis2;

 n_annulus= 0;
 for ( iy= iy_min; iy <= iy_max; iy++ ) {
  for ( ix= ix_min; ix <= ix_max; ix++ ) {
   dist2= ( (double)ix - center_x ) * ( (double)ix - center_x )
         + ( (double)iy - center_y ) * ( (double)iy - center_y );
   if ( dist2 < annulus_inner * annulus_inner || dist2 >= annulus_outer * annulus_outer ) {
    continue;
   }
   pix_idx= ( (long)iy - 1 ) * naxis1 + ( (long)ix - 1 );
   pix_val= pix[pix_idx];
   // Skip NaN/Inf in annulus silently
   if ( isnan( pix_val ) || isinf( pix_val ) ) {
    continue;
   }
   if ( n_annulus >= n_annulus_alloc ) {
    fprintf( stderr, "WARNING: annulus pixel buffer full at %d pixels\n", n_annulus );
    break;
   }
   annulus_vals[n_annulus]= pix_val;
   n_annulus++;
  }
 }

 if ( n_annulus < 5 ) {
  fprintf( stderr, "ERROR: too few annulus pixels (%d) for background estimation\n", n_annulus );
  strncpy( status_str_out, "edge", 31 );
  status_str_out[31]= '\0';
  return;
 }
 fprintf( stderr, "Background annulus: %d pixels\n", n_annulus );

#ifdef USE_SEXTRACTOR_BACKGROUND
 // ------------------------------------------------------------------
 // SExtractor-style background estimation:
 // 1. Iterative 3-sigma clipping around median until convergence
 // 2. Mode = 2.5 * Median - 1.5 * Mean
 // 3. Fall back to median if |mode - median| / sigma > 0.3
 // Reference: https://sextractor.readthedocs.io/en/latest/Background.html
 // ------------------------------------------------------------------

 memcpy( annulus_copy, annulus_vals, n_annulus * sizeof( double ) );
 n_clipped= n_annulus;
 iter= 0;

 for ( iter= 0; iter < 50; iter++ ) {
  n_prev= n_clipped;

  memcpy( abs_dev, annulus_copy, n_clipped * sizeof( double ) );
  clip_median= quickselect_median_double( abs_dev, n_clipped );

  sum_val= 0.0;
  sum_val2= 0.0;
  for ( i= 0; i < n_clipped; i++ ) {
   sum_val+= annulus_copy[i];
   sum_val2+= annulus_copy[i] * annulus_copy[i];
  }
  clip_mean= sum_val / (double)n_clipped;
  clip_sigma= sqrt( sum_val2 / (double)n_clipped - clip_mean * clip_mean );

  if ( clip_sigma <= 0.0 ) {
   break;
  }

  n_clipped= 0;
  for ( i= 0; i < n_prev; i++ ) {
   if ( fabs( annulus_copy[i] - clip_median ) <= 3.0 * clip_sigma ) {
    annulus_copy[n_clipped]= annulus_copy[i];
    n_clipped++;
   }
  }

  if ( n_clipped < (int)( 0.3 * (double)n_annulus ) ) {
   fprintf( stderr, "WARNING: sigma clipping too aggressive at iter %d (%d/%d survived), stopping\n",
            iter, n_clipped, n_annulus );
   memcpy( annulus_copy, annulus_vals, n_annulus * sizeof( double ) );
   n_clipped= n_annulus;
   break;
  }

  if ( n_clipped == n_prev ) {
   break;
  }
 }
 fprintf( stderr, "Iterative clipping converged after %d iterations, %d/%d pixels remain\n",
          iter, n_clipped, n_annulus );

 memcpy( abs_dev, annulus_copy, n_clipped * sizeof( double ) );
 clip_median= quickselect_median_double( abs_dev, n_clipped );
 sum_val= 0.0;
 sum_val2= 0.0;
 for ( i= 0; i < n_clipped; i++ ) {
  sum_val+= annulus_copy[i];
  sum_val2+= annulus_copy[i] * annulus_copy[i];
 }
 clip_mean= sum_val / (double)n_clipped;
 clip_sigma= sqrt( sum_val2 / (double)n_clipped - clip_mean * clip_mean );

 bg_mode= 2.5 * clip_median - 1.5 * clip_mean;

 if ( clip_sigma > 0.0 && fabs( bg_mode - clip_median ) / clip_sigma > 0.3 ) {
  fprintf( stderr, "SExtractor bg: mode=%.2f disagrees with median=%.2f (>0.3*sigma=%.2f), using median\n",
           bg_mode, clip_median, clip_sigma );
  bg_per_pixel= clip_median;
 } else {
  bg_per_pixel= bg_mode;
 }
 sigma_bg= clip_sigma;

 fprintf( stderr, "SExtractor background: mode=%.2f median=%.2f mean=%.2f sigma=%.2f -> bg=%.2f (%d pixels)\n",
          bg_mode, clip_median, clip_mean, clip_sigma, bg_per_pixel, n_clipped );

#else
 // ------------------------------------------------------------------
 // Simple sigma-clipped median with MAD-based sigma
 // ------------------------------------------------------------------

 memcpy( annulus_copy, annulus_vals, n_annulus * sizeof( double ) );
 bg_median= quickselect_median_double( annulus_copy, n_annulus );

 for ( i= 0; i < n_annulus; i++ ) {
  abs_dev[i]= fabs( annulus_vals[i] - bg_median );
 }
 bg_mad= quickselect_median_double( abs_dev, n_annulus );
 sigma_mad= 1.4826 * bg_mad;
 fprintf( stderr, "Background before clipping: median=%.2f MAD=%.2f sigma_MAD=%.2f\n",
          bg_median, bg_mad, sigma_mad );

 n_clipped= 0;
 for ( i= 0; i < n_annulus; i++ ) {
  if ( fabs( annulus_vals[i] - bg_median ) <= 3.0 * sigma_mad ) {
   annulus_copy[n_clipped]= annulus_vals[i];
   n_clipped++;
  }
 }

 if ( n_clipped < (int)( 0.3 * (double)n_annulus ) ) {
  fprintf( stderr, "WARNING: sigma clipping too aggressive (%d/%d survived), using all pixels\n",
           n_clipped, n_annulus );
  memcpy( annulus_copy, annulus_vals, n_annulus * sizeof( double ) );
  n_clipped= n_annulus;
 }

 memcpy( abs_dev, annulus_copy, n_clipped * sizeof( double ) );
 bg_per_pixel= quickselect_median_double( abs_dev, n_clipped );

 for ( i= 0; i < n_clipped; i++ ) {
  abs_dev[i]= fabs( annulus_copy[i] - bg_per_pixel );
 }
 sigma_bg= 1.4826 * quickselect_median_double( abs_dev, n_clipped );

 fprintf( stderr, "Background after clipping: median=%.2f sigma=%.2f (%d pixels)\n",
          bg_per_pixel, sigma_bg, n_clipped );
#endif

 // ------------------------------------------------------------------
 // Aperture flux measurement with exact pixel weights
 // ------------------------------------------------------------------
 ix_min= (int)floor( center_x - aperture_radius - 1.0 );
 ix_max= (int)ceil( center_x + aperture_radius + 1.0 );
 iy_min= (int)floor( center_y - aperture_radius - 1.0 );
 iy_max= (int)ceil( center_y + aperture_radius + 1.0 );
 if ( ix_min < 1 ) ix_min= 1;
 if ( iy_min < 1 ) iy_min= 1;
 if ( ix_max > naxis1 ) ix_max= (int)naxis1;
 if ( iy_max > naxis2 ) iy_max= (int)naxis2;

 sum_aperture= 0.0;
 n_eff= 0.0;
 for ( iy= iy_min; iy <= iy_max; iy++ ) {
  for ( ix= ix_min; ix <= ix_max; ix++ ) {
   weight= pixwt_scalar( center_x, center_y, aperture_radius, (double)ix, (double)iy );
   if ( weight <= 0.0 ) {
    continue;
   }
   pix_idx= ( (long)iy - 1 ) * naxis1 + ( (long)ix - 1 );
   sum_aperture+= pix[pix_idx] * weight;
   n_eff+= weight;
  }
 }

 fprintf( stderr, "Aperture sum=%.2f N_eff=%.4f\n", sum_aperture, n_eff );

 // ------------------------------------------------------------------
 // Net flux and detection decision
 // ------------------------------------------------------------------
 net_flux= sum_aperture - bg_per_pixel * n_eff;
 noise= sigma_bg * sqrt( n_eff );

 fprintf( stderr, "Net flux=%.2f noise=%.2f SNR=%.2f\n",
          net_flux, noise, ( noise > 0.0 ) ? net_flux / noise : 0.0 );

 if ( net_flux > 3.0 * noise ) {
  inst_mag= -2.5 * log10( net_flux );
  mag_err= 1.0857 * noise / net_flux;
  strncpy( status_str_out, "detection", 31 );
 } else {
  // 3-sigma upper limit
  if ( noise > 0.0 ) {
   inst_mag= -2.5 * log10( 3.0 * noise );
  } else {
   inst_mag= 99.0;
  }
  mag_err= 99.0;
  strncpy( status_str_out, "upperlimit", 31 );
 }
 status_str_out[31]= '\0';

 fprintf( stderr, "Instrumental magnitude: %.4f\n", inst_mag );

 cal_mag= calib_p2 * inst_mag * inst_mag + calib_p1 * inst_mag + calib_p0;
 fprintf( stderr, "Calibrated magnitude: %.4f\n", cal_mag );

 *cal_mag_out= cal_mag;
 *mag_err_out= mag_err;
}

// ------------------------------------------------------------------
// main
// ------------------------------------------------------------------

int main( int argc, char **argv ) {

 // Command-line arguments
 char fitsfilename[FILENAME_LENGTH];
 int list_mode;
 const char *list_filename;
 double center_x, center_y, aperture_diameter;
 double aperture_radius, annulus_outer;

 // FITS image
 fitsfile *fptr;
 int fits_status;
 int naxis;
 long naxes[2];
 long totpix;
 double *pix;
 double nullval;
 int anynul;

 // Bad region arrays
 double *bad_X1, *bad_Y1, *bad_X2, *bad_Y2;
 int n_bad_regions;
 int max_bad_regions;

 // Saturation
 double satur_level;

 // Calibration
 double calib_p3, calib_p2, calib_p1, calib_p0;

 // Annulus scratch buffers
 double *annulus_vals, *annulus_copy, *abs_dev;
 int n_annulus_alloc;

 // Per-position result
 double cal_mag, mag_err;
 char status_str[32];

 // List-mode parsing
 FILE *listf;
 char line_buf[4096];
 char label[64];
 int line_idx;
 int nfields;
 char *p;

 // Optional calibration-file path (NULL = default "calib.txt_param")
 const char *calib_filename;

 // ------------------------------------------------------------------
 // Parse arguments
 // ------------------------------------------------------------------
 if ( argc != 5 && argc != 7 ) {
  fprintf( stderr, "Usage:\n" );
  fprintf( stderr, "  %s image.fits center_x center_y aperture_diameter [--calib PATH]\n", argv[0] );
  fprintf( stderr, "  %s image.fits --list listfile aperture_diameter [--calib PATH]\n", argv[0] );
  fprintf( stderr, "  center_x, center_y: 1-based pixel coordinates (from sky2xy)\n" );
  fprintf( stderr, "  aperture_diameter: in pixels\n" );
  fprintf( stderr, "  listfile: one line per position \"center_x center_y [label]\"\n" );
  fprintf( stderr, "  --calib PATH: read calibration parameters from PATH instead of calib.txt_param\n" );
  return 1;
 }

 calib_filename= NULL;
 if ( argc == 7 ) {
  if ( 0 != strcmp( argv[5], "--calib" ) ) {
   fprintf( stderr, "ERROR: extra trailing argument must be '--calib PATH' (got '%s %s')\n", argv[5], argv[6] );
   return 1;
  }
  calib_filename= argv[6];
 }

 strncpy( fitsfilename, argv[1], FILENAME_LENGTH - 1 );
 fitsfilename[FILENAME_LENGTH - 1]= '\0';

 list_mode= 0;
 list_filename= NULL;
 center_x= 0.0;
 center_y= 0.0;
 if ( 0 == strcmp( argv[2], "--list" ) ) {
  list_mode= 1;
  list_filename= argv[3];
  aperture_diameter= atof( argv[4] );
 } else {
  center_x= atof( argv[2] );
  center_y= atof( argv[3] );
  aperture_diameter= atof( argv[4] );
 }

 if ( aperture_diameter <= 0.0 ) {
  fprintf( stderr, "ERROR: aperture_diameter must be positive\n" );
  return 1;
 }

 aperture_radius= aperture_diameter / 2.0;
 annulus_outer= 10.0 * aperture_radius;

 if ( list_mode == 0 ) {
  fprintf( stderr, "Forced photometry: image=%s center=(%.2f, %.2f) aperture=%.1f\n",
           fitsfilename, center_x, center_y, aperture_diameter );
 } else {
  fprintf( stderr, "Forced photometry (list mode): image=%s list=%s aperture=%.1f\n",
           fitsfilename, list_filename, aperture_diameter );
 }

 // ------------------------------------------------------------------
 // Open FITS image and read all pixels
 // ------------------------------------------------------------------
 fits_status= 0;
 fits_open_image( &fptr, fitsfilename, READONLY, &fits_status );
 if ( fits_status != 0 ) {
  fprintf( stderr, "ERROR: cannot open FITS image %s\n", fitsfilename );
  fits_report_error( stderr, fits_status );
  return 1;
 }

 fits_get_img_dim( fptr, &naxis, &fits_status );
 if ( fits_status != 0 || naxis != 2 ) {
  fprintf( stderr, "ERROR: expected a 2D FITS image, got naxis=%d\n", naxis );
  fits_close_file( fptr, &fits_status );
  return 1;
 }

 fits_get_img_size( fptr, 2, naxes, &fits_status );
 if ( fits_status != 0 ) {
  fprintf( stderr, "ERROR: cannot get image size\n" );
  fits_close_file( fptr, &fits_status );
  return 1;
 }
 fprintf( stderr, "Image size: %ld x %ld\n", naxes[0], naxes[1] );

 totpix= naxes[0] * naxes[1];
 pix= (double *)malloc( totpix * sizeof( double ) );
 if ( pix == NULL ) {
  fprintf( stderr, "ERROR: cannot allocate memory for %ld pixels\n", totpix );
  fits_close_file( fptr, &fits_status );
  return 1;
 }

 nullval= 0.0;
 anynul= 0;
 fits_read_img( fptr, TDOUBLE, 1, totpix, &nullval, pix, &anynul, &fits_status );
 if ( fits_status != 0 ) {
  fprintf( stderr, "ERROR: cannot read image pixels\n" );
  fits_report_error( stderr, fits_status );
  free( pix );
  fits_close_file( fptr, &fits_status );
  return 1;
 }
 fits_close_file( fptr, &fits_status );

 // ------------------------------------------------------------------
 // Read bad regions (kept for all positions)
 // ------------------------------------------------------------------
 max_bad_regions= 1 + count_lines_in_ASCII_file( "bad_region.lst" );
 bad_X1= (double *)malloc( max_bad_regions * sizeof( double ) );
 bad_Y1= (double *)malloc( max_bad_regions * sizeof( double ) );
 bad_X2= (double *)malloc( max_bad_regions * sizeof( double ) );
 bad_Y2= (double *)malloc( max_bad_regions * sizeof( double ) );
 if ( bad_X1 == NULL || bad_Y1 == NULL || bad_X2 == NULL || bad_Y2 == NULL ) {
  fprintf( stderr, "ERROR: cannot allocate memory for bad region arrays\n" );
  free( pix );
  free( bad_X1 );
  free( bad_Y1 );
  free( bad_X2 );
  free( bad_Y2 );
  return 1;
 }
 n_bad_regions= 0;
 read_bad_CCD_regions_lst( bad_X1, bad_Y1, bad_X2, bad_Y2, &n_bad_regions );

 // ------------------------------------------------------------------
 // Read saturation level from default.sex
 // ------------------------------------------------------------------
 satur_level= read_satur_level_from_default_sex();
 fprintf( stderr, "Saturation level: %.1f\n", satur_level );

 // ------------------------------------------------------------------
 // Read magnitude calibration up front (shared across all positions)
 // ------------------------------------------------------------------
 if ( 0 != read_calib_param( calib_filename, &calib_p3, &calib_p2, &calib_p1, &calib_p0 ) ) {
  fprintf( stderr, "ERROR: magnitude calibration failed\n" );
  if ( list_mode == 0 ) {
   fprintf( stdout, "99.0000 99.0000 calib_fail\n" );
  } else {
   // For list mode, emit a calib_fail row per listed position so the caller
   // still gets a row-per-position output aligned with the input list.
   listf= fopen( list_filename, "r" );
   if ( listf != NULL ) {
    line_idx= 0;
    while ( fgets( line_buf, sizeof( line_buf ), listf ) != NULL ) {
     line_idx++;
     p= line_buf;
     while ( *p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' ) {
      p++;
     }
     if ( *p == '\0' || *p == '#' || *p == '%' ) {
      continue;
     }
     nfields= sscanf( p, "%lf %lf %63s", &center_x, &center_y, label );
     if ( nfields < 2 ) {
      continue;
     }
     if ( nfields < 3 ) {
      snprintf( label, sizeof( label ), "%d", line_idx );
     }
     fprintf( stdout, "%s %.4f %.4f 99.0000 99.0000 calib_fail\n",
              label, center_x, center_y );
    }
    fclose( listf );
   }
  }
  free( pix );
  free( bad_X1 );
  free( bad_Y1 );
  free( bad_X2 );
  free( bad_Y2 );
  return 0;
 }
 (void)calib_p3;

 // ------------------------------------------------------------------
 // Allocate annulus scratch buffers (same aperture for every position)
 // ------------------------------------------------------------------
 n_annulus_alloc= (int)( 4.0 * annulus_outer * annulus_outer ) + 100;
 annulus_vals= (double *)malloc( n_annulus_alloc * sizeof( double ) );
 annulus_copy= (double *)malloc( n_annulus_alloc * sizeof( double ) );
 abs_dev= (double *)malloc( n_annulus_alloc * sizeof( double ) );
 if ( annulus_vals == NULL || annulus_copy == NULL || abs_dev == NULL ) {
  fprintf( stderr, "ERROR: cannot allocate annulus scratch buffers\n" );
  free( pix );
  free( bad_X1 );
  free( bad_Y1 );
  free( bad_X2 );
  free( bad_Y2 );
  free( annulus_vals );
  free( annulus_copy );
  free( abs_dev );
  return 1;
 }

 // ------------------------------------------------------------------
 // Dispatch: single position vs list
 // ------------------------------------------------------------------
 if ( list_mode == 0 ) {
  photometry_at_position( pix, naxes[0], naxes[1],
                          satur_level,
                          bad_X1, bad_Y1, bad_X2, bad_Y2, n_bad_regions,
                          calib_p2, calib_p1, calib_p0,
                          center_x, center_y,
                          aperture_diameter,
                          annulus_vals, annulus_copy, abs_dev, n_annulus_alloc,
                          &cal_mag, &mag_err, status_str );
  fprintf( stdout, "%.4f %.4f %s\n", cal_mag, mag_err, status_str );
 } else {
  listf= fopen( list_filename, "r" );
  if ( listf == NULL ) {
   fprintf( stderr, "ERROR: cannot open list file %s\n", list_filename );
   free( pix );
   free( bad_X1 );
   free( bad_Y1 );
   free( bad_X2 );
   free( bad_Y2 );
   free( annulus_vals );
   free( annulus_copy );
   free( abs_dev );
   return 1;
  }
  line_idx= 0;
  while ( fgets( line_buf, sizeof( line_buf ), listf ) != NULL ) {
   line_idx++;
   p= line_buf;
   while ( *p == ' ' || *p == '\t' || *p == '\n' || *p == '\r' ) {
    p++;
   }
   if ( *p == '\0' || *p == '#' || *p == '%' ) {
    continue;
   }
   nfields= sscanf( p, "%lf %lf %63s", &center_x, &center_y, label );
   if ( nfields < 2 ) {
    fprintf( stderr, "WARNING: list line %d: could not parse center_x center_y: %s",
             line_idx, line_buf );
    continue;
   }
   if ( nfields < 3 ) {
    snprintf( label, sizeof( label ), "%d", line_idx );
   }
   photometry_at_position( pix, naxes[0], naxes[1],
                           satur_level,
                           bad_X1, bad_Y1, bad_X2, bad_Y2, n_bad_regions,
                           calib_p2, calib_p1, calib_p0,
                           center_x, center_y,
                           aperture_diameter,
                           annulus_vals, annulus_copy, abs_dev, n_annulus_alloc,
                           &cal_mag, &mag_err, status_str );
   fprintf( stdout, "%s %.4f %.4f %.4f %.4f %s\n",
            label, center_x, center_y, cal_mag, mag_err, status_str );
  }
  fclose( listf );
 }

 free( pix );
 free( bad_X1 );
 free( bad_Y1 );
 free( bad_X2 );
 free( bad_Y2 );
 free( annulus_vals );
 free( annulus_copy );
 free( abs_dev );

 return 0;
}
