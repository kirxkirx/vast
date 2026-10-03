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
// Environment: FORCED_PHOTOMETRY_EDGE_MARGIN_PIX (optional) = minimum distance
// in pixels from any frame edge for a position to be measured; closer
// positions get the 'edge' status (default 0: only the annulus must fit).
// FORCED_PHOTOMETRY_FRAME_CHECKS=yes turns on the frame-level sanity checks
// (see the comment above wcs_is_tan_only_wide_field): a would-be detection
// or upper limit may then be reported as 'bad_wcs' or 'no_nearby_stars',
// keeping the measured values. They are off by default because every caller
// must know the two statuses: the source monitoring callers turn them on.
// They read FORCED_PHOTOMETRY_WCS_IMAGE (the image whose WCS gave the pixel
// positions, default: the measured image) and FORCED_PHOTOMETRY_STAR_CATALOG
// (the detection catalog, default: <WCS image>.wcscat or
// wcs_<basename>.wcscat in the current directory).
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

// Minimum distance (pixels) from any frame edge for a position to be
// measured, on top of the annulus-must-fit rule. Set in main() from the
// FORCED_PHOTOMETRY_EDGE_MARGIN_PIX environment variable; the source
// monitoring callers use 100 so that sources near the frame boundary (worst
// distortion and vignetting) get the 'edge' status instead of a measurement.
static double forced_photometry_edge_margin_pix= 0.0;

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
 double edge_margin;
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
 // The position must be at least edge_margin pixels away from every frame
 // edge: the annulus must fit, and the caller may demand more through
 // FORCED_PHOTOMETRY_EDGE_MARGIN_PIX (see forced_photometry_edge_margin_pix)
 edge_margin= annulus_outer;
 if ( forced_photometry_edge_margin_pix > edge_margin ) {
  edge_margin= forced_photometry_edge_margin_pix;
 }

 *cal_mag_out= 99.0;
 *mag_err_out= 99.0;

 fprintf( stderr, "Forced photometry: center=(%.2f, %.2f) aperture=%.1f\n",
          center_x, center_y, aperture_diameter );
 fprintf( stderr, "Annulus: inner=%.2f outer=%.2f edge margin=%.2f\n", annulus_inner, annulus_outer, edge_margin );

 // ------------------------------------------------------------------
 // Edge check: the position must be edge_margin pixels away from the
 // frame edges (at least the annulus must fit within the image)
 // ------------------------------------------------------------------
 if ( center_x - edge_margin < 1.0 || center_x + edge_margin > (double)naxis1 ||
      center_y - edge_margin < 1.0 || center_y + edge_margin > (double)naxis2 ) {
  // The per-position skip conditions in this function (edge, bad region,
  // NaN, saturation, too few annulus pixels) are expected data conditions,
  // not failures: they are reported with the status token the callers act
  // upon, and the stderr notes must not say 'ERROR' - the word would
  // propagate into processing logs that are scanned for real errors.
  fprintf( stderr, "NOTE: the position is closer than %.1f pix to the image edge (aperture/annulus or the configured margin) - skipping the measurement\n", edge_margin );
  strncpy( status_str_out, "edge", 31 );
  status_str_out[31]= '\0';
  return;
 }

 // ------------------------------------------------------------------
 // Bad region check
 // ------------------------------------------------------------------
 if ( 0 != exclude_region( bad_X1, bad_Y1, bad_X2, bad_Y2, n_bad_regions,
                            center_x, center_y, aperture_diameter ) ) {
  fprintf( stderr, "NOTE: position falls in a bad CCD region (bad_region.lst) - skipping the measurement\n" );
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
    fprintf( stderr, "NOTE: NaN/Inf pixel at (%d, %d) within aperture - skipping the measurement\n", ix, iy );
    strncpy( status_str_out, "nan_pixel", 31 );
    status_str_out[31]= '\0';
    return;
   }
   if ( pix_val >= satur_level ) {
    fprintf( stderr, "NOTE: saturated pixel at (%d, %d) value=%.1f >= %.1f - skipping the measurement\n",
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
  fprintf( stderr, "NOTE: too few annulus pixels (%d) for background estimation - skipping the measurement\n", n_annulus );
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
  // NOTE: mag_err is the true formal photon-noise error and is deliberately NOT floored here.
  // For a bright, high-SNR star it can be ~0. Beware that a zero (or near-zero) error can trip up
  // VaST tools that later read this lightcurve: read_lightcurve_point_raw() in src/lightcurve_io.h
  // drops points whose error is exactly 0.0 (isnormal() treats 0.0 as non-normal), and a zero
  // error also breaks inverse-variance weighting (zero error -> infinite weight). Any minimum-error
  // floor is intentionally left to the downstream consumer that needs it (e.g. the web
  // forced-photometry CGI applies a small floor to lightcurve.dat before plotting).
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
// Frame-level sanity checks.
//
// Only with FORCED_PHOTOMETRY_FRAME_CHECKS=yes in the environment: every
// caller must know the two statuses below. The reference-image filter of
// util/transients/report_transient.sh, for one, must not lose its
// reference measurements this way, and util/seestar_photometry.sh tells a
// failed measurement by its 99.0000 magnitude. The source monitoring
// callers (the transient factory's monitoring block and the unmw forced
// photometry) turn the checks on. util/forced_photometry.py does not
// implement them.
//
// They are applied to every position whose measurement came out as a
// 'detection' or an 'upperlimit' - the only statuses the callers publish;
// all other statuses (edge, bad_region, saturated, ...) are left alone. A
// failed check replaces the status, while the measured magnitude and error
// stay in the output (unlike the other refusals, which print 99.0000), so a
// caller that keeps a record of the measurement can still see what was
// measured there.
//
// 1. 'bad_wcs': the plate solution used to place the aperture is a rigid
//    TAN projection without a distortion polynomial (no SIP, no PV terms)
//    on a field wider than FORCED_PHOTOMETRY_TAN_ONLY_WIDE_FIELD_DEG. This
//    is what solve-field leaves behind when its SIP tweak silently fails
//    (see the TAN-only guard in util/identify.sh): accurate near the
//    matched quad, tens of arcseconds off at the far corners, so the
//    aperture may land on blank sky and give a bogus upper limit. The
//    solution checked is the one in the image named by
//    FORCED_PHOTOMETRY_WCS_IMAGE (the caller sets it to the image it ran
//    sky2xy on), otherwise the header of the measured image.
//
// 2. 'no_nearby_stars': the image's own detection catalog (see
//    find_star_catalog()) holds fewer than
//    FORCED_PHOTOMETRY_STAR_COVERAGE_MIN_STARS stars within
//    FORCED_PHOTOMETRY_STAR_COVERAGE_RADIUS_ARCSEC of the position: no
//    stars are seen around it - a thick cloud over the position,
//    typically - and a magnitude or an upper limit measured there means
//    nothing. An empty circle means something only when the catalog is
//    deep enough to fill it, so the test judges only positions where at
//    least FORCED_PHOTOMETRY_STAR_COVERAGE_MIN_EXPECTED stars are expected
//    at the mean star density of the frame (counting only the part of the
//    circle that lies inside the frame); it is skipped altogether, with a
//    note, when no catalog is found, the pixel scale is unknown or the
//    frame is too small for its density to mean anything. The
//    test is deliberately local: whole-frame transparency is the business
//    of the calling pipeline. The thresholds and the data they come from
//    are described where they are defined, in src/vast_limits.h.
//
// Neither check prints the word ERROR: pipeline logs are scanned for it,
// and a refused position is a data condition, not a failure.
// ------------------------------------------------------------------

// 1 if the header of fitsfilename holds a TAN projection without distortion
// terms (no SIP polynomial, no PV terms) on a field wider than
// FORCED_PHOTOMETRY_TAN_ONLY_WIDE_FIELD_DEG along its longer side, 0
// otherwise - including a header without a celestial WCS and one whose
// pixel scale cannot be read. pixel_scale_arcsec_out gets the pixel scale
// from the CD matrix (or CDELT) whenever it can be read, -1.0 otherwise.
static int wcs_is_tan_only_wide_field( const char *fitsfilename, double *pixel_scale_arcsec_out ) {
 fitsfile *fptr;
 int status;
 int key_status;
 char ctype1[FLEN_VALUE];
 char card[FLEN_CARD];
 long a_order;
 long naxes_wcs[2];
 double cd11, cd12, cd21, cd22, cdelt1, cdelt2;
 double pixel_scale_arcsec, fov_major_deg;
 int has_tan, has_sip, has_pv;
 int nkeys, i;

 *pixel_scale_arcsec_out= -1.0;
 status= 0;
 if ( 0 != fits_open_image( &fptr, fitsfilename, READONLY, &status ) ) {
  return 0;
 }
 naxes_wcs[0]= 0;
 naxes_wcs[1]= 0;
 fits_get_img_size( fptr, 2, naxes_wcs, &status );
 if ( status != 0 ) {
  status= 0;
  fits_close_file( fptr, &status );
  return 0;
 }
 ctype1[0]= '\0';
 key_status= 0;
 fits_read_key( fptr, TSTRING, "CTYPE1", ctype1, NULL, &key_status );
 if ( key_status != 0 ) {
  // no celestial WCS at all - nothing to judge
  status= 0;
  fits_close_file( fptr, &status );
  return 0;
 }
 has_tan= ( 0 == strncmp( ctype1, "RA---TAN", 8 ) ) ? 1 : 0;
 has_sip= ( NULL != strstr( ctype1, "SIP" ) ) ? 1 : 0;
 key_status= 0;
 fits_read_key( fptr, TLONG, "A_ORDER", &a_order, NULL, &key_status );
 if ( key_status == 0 ) {
  has_sip= 1;
 }
 // PV distortion terms (TAN+PV as written by SCAMP): PV1_n / PV2_n, n >= 1
 has_pv= 0;
 nkeys= 0;
 fits_get_hdrspace( fptr, &nkeys, NULL, &status );
 for ( i= 1; i <= nkeys && status == 0; i++ ) {
  if ( 0 != fits_read_record( fptr, i, card, &status ) ) {
   break;
  }
  if ( 0 == strncmp( card, "PV1_", 4 ) || 0 == strncmp( card, "PV2_", 4 ) ) {
   if ( atoi( card + 4 ) >= 1 ) {
    has_pv= 1;
   }
  }
 }
 // pixel scale from the CD matrix, or from CDELT
 pixel_scale_arcsec= -1.0;
 key_status= 0;
 fits_read_key( fptr, TDOUBLE, "CD1_1", &cd11, NULL, &key_status );
 fits_read_key( fptr, TDOUBLE, "CD1_2", &cd12, NULL, &key_status );
 fits_read_key( fptr, TDOUBLE, "CD2_1", &cd21, NULL, &key_status );
 fits_read_key( fptr, TDOUBLE, "CD2_2", &cd22, NULL, &key_status );
 if ( key_status == 0 ) {
  pixel_scale_arcsec= 3600.0 * sqrt( fabs( cd11 * cd22 - cd12 * cd21 ) );
 } else {
  key_status= 0;
  fits_read_key( fptr, TDOUBLE, "CDELT1", &cdelt1, NULL, &key_status );
  fits_read_key( fptr, TDOUBLE, "CDELT2", &cdelt2, NULL, &key_status );
  if ( key_status == 0 ) {
   pixel_scale_arcsec= 3600.0 * sqrt( fabs( cdelt1 * cdelt2 ) );
  }
 }
 status= 0;
 fits_close_file( fptr, &status );
 if ( pixel_scale_arcsec <= 0.0 ) {
  return 0;
 }
 *pixel_scale_arcsec_out= pixel_scale_arcsec;
 fov_major_deg= (double)( naxes_wcs[0] > naxes_wcs[1] ? naxes_wcs[0] : naxes_wcs[1] ) * pixel_scale_arcsec / 3600.0;
 if ( has_tan == 1 && has_sip == 0 && has_pv == 0 && fov_major_deg > FORCED_PHOTOMETRY_TAN_ONLY_WIDE_FIELD_DEG ) {
  fprintf( stderr, "NOTE: the plate solution in %s (%s, a %.1f deg field) has no distortion terms - it is unreliable away from the matched quad, so no measurement on this image will be reported as a detection or an upper limit (status bad_wcs)\n", fitsfilename, ctype1, fov_major_deg );
  return 1;
 }
 return 0;
}

static int file_is_readable( const char *path ) {
 FILE *f;
 f= fopen( path, "r" );
 if ( f == NULL ) {
  return 0;
 }
 fclose( f );
 return 1;
}

// The detection catalog for the local star coverage test: the file named
// by FORCED_PHOTOMETRY_STAR_CATALOG; else <wcs_image>.wcscat; else the
// catalog of the plate-solved copy wcs_<basename> in the current directory,
// the name util/forced_photometry.sh and the transient pipeline give it (a
// trailing .fz is dropped, as they do). The 10-column VaST .wcscat layout
// (lib/correct_sextractor_wcs_catalog_using_xy2sky.sh) has the pixel
// position in columns 4 and 5. Returns 0 and fills catalog_path_out when a
// readable catalog was found, 1 otherwise.
static int find_star_catalog( const char *wcs_image, char *catalog_path_out, size_t out_size ) {
 const char *env_catalog;
 const char *base;
 char basename_buf[FILENAME_LENGTH];
 size_t len;

 env_catalog= getenv( "FORCED_PHOTOMETRY_STAR_CATALOG" );
 if ( env_catalog != NULL && env_catalog[0] != '\0' ) {
  snprintf( catalog_path_out, out_size, "%s", env_catalog );
  return file_is_readable( catalog_path_out ) ? 0 : 1;
 }
 snprintf( catalog_path_out, out_size, "%s.wcscat", wcs_image );
 if ( file_is_readable( catalog_path_out ) ) {
  return 0;
 }
 base= strrchr( wcs_image, '/' );
 base= ( base != NULL ) ? base + 1 : wcs_image;
 strncpy( basename_buf, base, sizeof( basename_buf ) - 1 );
 basename_buf[sizeof( basename_buf ) - 1]= '\0';
 len= strlen( basename_buf );
 if ( len > 3 && 0 == strcmp( basename_buf + len - 3, ".fz" ) ) {
  basename_buf[len - 3]= '\0';
 }
 if ( 0 == strncmp( basename_buf, "wcs_", 4 ) ) {
  snprintf( catalog_path_out, out_size, "%s.wcscat", basename_buf );
 } else {
  snprintf( catalog_path_out, out_size, "wcs_%s.wcscat", basename_buf );
 }
 if ( file_is_readable( catalog_path_out ) ) {
  return 0;
 }
 catalog_path_out[0]= '\0';
 return 1;
}

// Pixel positions (columns 4 and 5) of the stars in a .wcscat catalog.
// Positions that are not finite numbers of a sane size are skipped (the
// comparisons below are false for NaN): they would index the cell array of
// the density cells out of bounds.
// Returns 0 on success with malloc'ed arrays the caller frees.
static int load_star_catalog_xy( char *catalog_path, double **x_out, double **y_out, int *n_out ) {
 FILE *f;
 char line[4096];
 double x, y;
 double *xs, *ys;
 int n, nmax;

 nmax= count_lines_in_ASCII_file( catalog_path ) + 1;
 xs= (double *)malloc( (size_t)nmax * sizeof( double ) );
 ys= (double *)malloc( (size_t)nmax * sizeof( double ) );
 if ( xs == NULL || ys == NULL ) {
  free( xs );
  free( ys );
  return 1;
 }
 f= fopen( catalog_path, "r" );
 if ( f == NULL ) {
  free( xs );
  free( ys );
  return 1;
 }
 n= 0;
 while ( n < nmax && fgets( line, sizeof( line ), f ) != NULL ) {
  if ( line[0] == '#' ) {
   continue;
  }
  if ( 2 != sscanf( line, "%*s %*s %*s %lf %lf", &x, &y ) ) {
   continue;
  }
  if ( !( x > -1.0e7 && x < 1.0e7 && y > -1.0e7 && y < 1.0e7 ) ) {
   continue;
  }
  xs[n]= x;
  ys[n]= y;
  n++;
 }
 fclose( f );
 *x_out= xs;
 *y_out= ys;
 *n_out= n;
 return 0;
}

// The mean number of catalog stars in square cells of side 2*radius_pix,
// over the cells that fit entirely inside the frame: the frame's typical
// star density on the scale of the test. The mean rather than the median:
// clouds that empty more than half of the frame drive the median to zero
// and would turn the test off on the very frames it is for, while the mean
// drops only in proportion to the clouded area. -1.0 when fewer than 4
// cells fit (the frame is too small for its density to mean anything).
static double mean_stars_per_cell( const double *xs, const double *ys, int n, long naxis1, long naxis2, double radius_pix ) {
 double cell;
 int ncx, ncy, i, n_in_cells;

 cell= 2.0 * radius_pix;
 if ( cell <= 0.0 ) {
  return -1.0;
 }
 ncx= (int)( (double)naxis1 / cell );
 ncy= (int)( (double)naxis2 / cell );
 if ( ncx < 1 || ncy < 1 || ncx * ncy < 4 ) {
  return -1.0;
 }
 n_in_cells= 0;
 for ( i= 0; i < n; i++ ) {
  // only the stars inside the cell grid (false for NaN, too)
  if ( xs[i] >= 0.0 && xs[i] < (double)ncx * cell && ys[i] >= 0.0 && ys[i] < (double)ncy * cell ) {
   n_in_cells++;
  }
 }
 return (double)n_in_cells / (double)( ncx * ncy );
}

// Fraction of the circle of radius_pix around (center_x, center_y) that
// lies inside the frame (1-based pixel coordinates, pixel edges at 0.5 and
// naxis+0.5), estimated on a 41x41 grid of sample points.
static double circle_fraction_inside_frame( double center_x, double center_y, double radius_pix, long naxis1, long naxis2 ) {
 int i, j;
 int n_in_circle, n_in_frame;
 double dx, dy, px, py;

 n_in_circle= 0;
 n_in_frame= 0;
 for ( i= -20; i <= 20; i++ ) {
  for ( j= -20; j <= 20; j++ ) {
   dx= (double)i / 20.0;
   dy= (double)j / 20.0;
   if ( dx * dx + dy * dy > 1.0 ) {
    continue;
   }
   n_in_circle++;
   px= center_x + dx * radius_pix;
   py= center_y + dy * radius_pix;
   if ( px >= 0.5 && px <= (double)naxis1 + 0.5 && py >= 0.5 && py <= (double)naxis2 + 0.5 ) {
    n_in_frame++;
   }
  }
 }
 if ( n_in_circle == 0 ) {
  return 0.0;
 }
 return (double)n_in_frame / (double)n_in_circle;
}

static int count_stars_within_radius( const double *xs, const double *ys, int n, double center_x, double center_y, double radius_pix ) {
 int i, count;
 double dx, dy, r2;

 r2= radius_pix * radius_pix;
 count= 0;
 for ( i= 0; i < n; i++ ) {
  dx= xs[i] - center_x;
  dy= ys[i] - center_y;
  if ( dx * dx + dy * dy <= r2 ) {
   count++;
  }
 }
 return count;
}

// The status that replaces a 'detection' or 'upperlimit' result of the
// position (see the block comment above), or NULL when the result stands.
// mean_per_cell <= 0 means the local star coverage test is not active.
static const char *frame_level_status( const char *measured_status, int wcs_unreliable,
                                       const double *xs, const double *ys, int n_stars,
                                       long naxis1, long naxis2, double radius_pix, double mean_per_cell,
                                       double center_x, double center_y, double cal_mag, double mag_err ) {
 double expected;
 int n_local;

 if ( 0 != strcmp( measured_status, "detection" ) && 0 != strcmp( measured_status, "upperlimit" ) ) {
  return NULL;
 }
 if ( wcs_unreliable == 1 ) {
  return "bad_wcs";
 }
 if ( mean_per_cell <= 0.0 ) {
  return NULL;
 }
 // Expected count in the part of the circle inside the frame: a density
 // cell is a square of side 2r, the circle covers pi/4 of it
 expected= mean_per_cell * M_PI / 4.0 * circle_fraction_inside_frame( center_x, center_y, radius_pix, naxis1, naxis2 );
 if ( expected < FORCED_PHOTOMETRY_STAR_COVERAGE_MIN_EXPECTED ) {
  fprintf( stderr, "NOTE: local star coverage test not applied at (%.2f, %.2f): only %.1f catalog stars expected within %.0f pix at the frame's mean star density, the test needs %.0f\n", center_x, center_y, expected, radius_pix, FORCED_PHOTOMETRY_STAR_COVERAGE_MIN_EXPECTED );
  return NULL;
 }
 n_local= count_stars_within_radius( xs, ys, n_stars, center_x, center_y, radius_pix );
 if ( n_local < FORCED_PHOTOMETRY_STAR_COVERAGE_MIN_STARS ) {
  fprintf( stderr, "NOTE: only %d catalog stars within %.0f pix of (%.2f, %.2f), where %.1f are expected at the frame's mean star density - no stars are seen around the position (a cloud?); the measured %s (%.4f %.4f) is reported with the status no_nearby_stars\n", n_local, radius_pix, center_x, center_y, expected, measured_status, cal_mag, mag_err );
  return "no_nearby_stars";
 }
 fprintf( stderr, "Local star coverage at (%.2f, %.2f): %d catalog stars within %.0f pix, %.1f expected at the frame's mean star density\n", center_x, center_y, n_local, radius_pix, expected );
 return NULL;
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

 // Optional edge margin from the environment
 char *edge_margin_env;

 // Frame-level sanity checks (see the comment above wcs_is_tan_only_wide_field)
 char *frame_checks_env;
 const char *wcs_image;
 int wcs_unreliable;
 double pixel_scale_arcsec;
 char coverage_catalog_path[FILENAME_LENGTH + 16];
 double *coverage_star_x, *coverage_star_y;
 int coverage_n_stars;
 double coverage_radius_pix, coverage_mean_per_cell;
 const char *replacement_status;

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
  fprintf( stderr, "  environment FORCED_PHOTOMETRY_EDGE_MARGIN_PIX=N: report positions closer than N pix to a frame edge as 'edge'\n" );
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

 // Optional minimum distance from the frame edges (pixels); a negative or
 // unparsable value means the default (only the annulus must fit)
 edge_margin_env= getenv( "FORCED_PHOTOMETRY_EDGE_MARGIN_PIX" );
 if ( edge_margin_env != NULL && edge_margin_env[0] != '\0' ) {
  forced_photometry_edge_margin_pix= atof( edge_margin_env );
  if ( forced_photometry_edge_margin_pix < 0.0 ) {
   forced_photometry_edge_margin_pix= 0.0;
  }
  fprintf( stderr, "Edge margin: %.1f pix (FORCED_PHOTOMETRY_EDGE_MARGIN_PIX)\n", forced_photometry_edge_margin_pix );
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
 // Frame-level sanity checks (see the comment above wcs_is_tan_only_wide_field),
 // only when the caller asks for them. With wcs_unreliable 0 and
 // coverage_mean_per_cell -1 frame_level_status() changes nothing.
 // ------------------------------------------------------------------
 wcs_unreliable= 0;
 wcs_image= fitsfilename;
 pixel_scale_arcsec= -1.0;
 coverage_star_x= NULL;
 coverage_star_y= NULL;
 coverage_n_stars= 0;
 coverage_radius_pix= 0.0;
 coverage_mean_per_cell= -1.0;
 coverage_catalog_path[0]= '\0';
 frame_checks_env= getenv( "FORCED_PHOTOMETRY_FRAME_CHECKS" );
 if ( frame_checks_env != NULL && 0 == strcmp( frame_checks_env, "yes" ) ) {
  // The plate solution to judge is the one the caller placed the apertures
  // with: FORCED_PHOTOMETRY_WCS_IMAGE when set, the measured image otherwise
  wcs_image= getenv( "FORCED_PHOTOMETRY_WCS_IMAGE" );
  if ( wcs_image == NULL || wcs_image[0] == '\0' ) {
   wcs_image= fitsfilename;
  }
  wcs_unreliable= wcs_is_tan_only_wide_field( wcs_image, &pixel_scale_arcsec );
  if ( wcs_unreliable == 0 ) {
   if ( pixel_scale_arcsec <= 0.0 ) {
    fprintf( stderr, "NOTE: local star coverage test skipped - no pixel scale in the plate solution of %s\n", wcs_image );
   } else if ( 0 != find_star_catalog( wcs_image, coverage_catalog_path, sizeof( coverage_catalog_path ) ) ) {
    fprintf( stderr, "NOTE: local star coverage test skipped - no detection catalog (.wcscat) found for %s\n", wcs_image );
   } else if ( 0 != load_star_catalog_xy( coverage_catalog_path, &coverage_star_x, &coverage_star_y, &coverage_n_stars ) ) {
    fprintf( stderr, "NOTE: local star coverage test skipped - cannot read %s\n", coverage_catalog_path );
   } else {
    coverage_radius_pix= FORCED_PHOTOMETRY_STAR_COVERAGE_RADIUS_ARCSEC / pixel_scale_arcsec;
    coverage_mean_per_cell= mean_stars_per_cell( coverage_star_x, coverage_star_y, coverage_n_stars, naxes[0], naxes[1], coverage_radius_pix );
    if ( coverage_mean_per_cell <= 0.0 ) {
     fprintf( stderr, "NOTE: local star coverage test skipped - the frame is too small, or too sparse in %s, to tell its typical star density on the %.0f pix scale of the test\n", coverage_catalog_path, 2.0 * coverage_radius_pix );
     coverage_mean_per_cell= -1.0;
    } else {
     fprintf( stderr, "Local star coverage test: %d stars in %s, test radius %.0f pix (%.2f deg), %.1f stars per circle at the frame's mean density\n", coverage_n_stars, coverage_catalog_path, coverage_radius_pix, FORCED_PHOTOMETRY_STAR_COVERAGE_RADIUS_ARCSEC / 3600.0, coverage_mean_per_cell * M_PI / 4.0 );
    }
   }
  }
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
  replacement_status= frame_level_status( status_str, wcs_unreliable, coverage_star_x, coverage_star_y, coverage_n_stars, naxes[0], naxes[1], coverage_radius_pix, coverage_mean_per_cell, center_x, center_y, cal_mag, mag_err );
  if ( replacement_status != NULL ) {
   strncpy( status_str, replacement_status, 31 );
   status_str[31]= '\0';
  }
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
   free( coverage_star_x );
   free( coverage_star_y );
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
   replacement_status= frame_level_status( status_str, wcs_unreliable, coverage_star_x, coverage_star_y, coverage_n_stars, naxes[0], naxes[1], coverage_radius_pix, coverage_mean_per_cell, center_x, center_y, cal_mag, mag_err );
   if ( replacement_status != NULL ) {
    strncpy( status_str, replacement_status, 31 );
    status_str[31]= '\0';
   }
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
 free( coverage_star_x );
 free( coverage_star_y );

 return 0;
}
