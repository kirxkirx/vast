// Forced aperture photometry at a specified pixel position on a FITS image.
//
// Usage: forced_photometry image.fits center_x center_y aperture_diameter
//
// Reads calib.txt_param, bad_region.lst, and default.sex from current directory.
// Output (stdout): cal_mag mag_err status
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

// Read calibration parameters from calib.txt_param.
// Format: fit_function p3 p2 p1 p0
// Returns 0 on success, 1 on failure.
static int read_calib_param( double *p3, double *p2, double *p1, double *p0 ) {
 FILE *f;
 double fit_fn;

 f= fopen( "calib.txt_param", "r" );
 if ( f == NULL ) {
  fprintf( stderr, "ERROR: cannot open calib.txt_param\n" );
  return 1;
 }
 if ( 5 != fscanf( f, "%lf %lf %lf %lf %lf", &fit_fn, p3, p2, p1, p0 ) ) {
  fprintf( stderr, "ERROR: cannot parse calib.txt_param\n" );
  fclose( f );
  return 1;
 }
 fclose( f );
 fprintf( stderr, "Calibration (fit_function=%.0f): cal_mag = %.6f * x^2 + %.6f * x + %.6f\n",
          fit_fn, *p2, *p1, *p0 );
 return 0;
}

// ------------------------------------------------------------------
// main
// ------------------------------------------------------------------

int main( int argc, char **argv ) {

 // Command-line arguments
 char fitsfilename[FILENAME_LENGTH];
 double center_x, center_y, aperture_diameter;
 double aperture_radius, annulus_inner, annulus_outer;

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

 // Pixel loop variables
 int ix, iy;
 int ix_min, ix_max, iy_min, iy_max;
 double weight, pix_val;
 long pix_idx;
 double dist2;

 // Background estimation
 double *annulus_vals;
 double *annulus_copy;
 double *abs_dev;
 int n_annulus, n_annulus_alloc;
 int n_clipped;
 double bg_median, bg_mad, sigma_mad;
 double bg_per_pixel, sigma_bg;
 int i;
#ifdef USE_SEXTRACTOR_BACKGROUND
 // SExtractor-style background estimation variables
 double clip_median, clip_mean, clip_sigma, bg_mode;
 int n_prev, iter;
 double sum_val, sum_val2;
#endif

 // Aperture flux
 double sum_aperture, n_eff;
 double net_flux, noise;
 double inst_mag, cal_mag, mag_err;
 char status_str[32];

 // Calibration
 double calib_p3, calib_p2, calib_p1, calib_p0;

 // ------------------------------------------------------------------
 // Parse arguments
 // ------------------------------------------------------------------
 if ( argc != 5 ) {
  fprintf( stderr, "Usage: %s image.fits center_x center_y aperture_diameter\n", argv[0] );
  fprintf( stderr, "  center_x, center_y: 1-based pixel coordinates (from sky2xy)\n" );
  fprintf( stderr, "  aperture_diameter: in pixels\n" );
  return 1;
 }

 strncpy( fitsfilename, argv[1], FILENAME_LENGTH - 1 );
 fitsfilename[FILENAME_LENGTH - 1]= '\0';
 center_x= atof( argv[2] );
 center_y= atof( argv[3] );
 aperture_diameter= atof( argv[4] );

 if ( aperture_diameter <= 0.0 ) {
  fprintf( stderr, "ERROR: aperture_diameter must be positive\n" );
  return 1;
 }

 aperture_radius= aperture_diameter / 2.0;
 annulus_inner= 4.0 * aperture_radius;
 annulus_outer= 10.0 * aperture_radius;

 fprintf( stderr, "Forced photometry: image=%s center=(%.2f, %.2f) aperture=%.1f\n",
          fitsfilename, center_x, center_y, aperture_diameter );
 fprintf( stderr, "Annulus: inner=%.2f outer=%.2f\n", annulus_inner, annulus_outer );

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
 // Edge check: entire annulus must fit within image
 // ------------------------------------------------------------------
 if ( center_x - annulus_outer < 1.0 || center_x + annulus_outer > (double)naxes[0] ||
      center_y - annulus_outer < 1.0 || center_y + annulus_outer > (double)naxes[1] ) {
  fprintf( stderr, "ERROR: aperture/annulus extends beyond image edge\n" );
  fprintf( stdout, "99.0000 99.0000 edge\n" );
  free( pix );
  return 0;
 }

 // ------------------------------------------------------------------
 // Bad region check
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

 if ( 0 != exclude_region( bad_X1, bad_Y1, bad_X2, bad_Y2, n_bad_regions,
                            center_x, center_y, aperture_diameter ) ) {
  fprintf( stderr, "ERROR: position falls in a bad CCD region (bad_region.lst)\n" );
  fprintf( stdout, "99.0000 99.0000 bad_region\n" );
  free( pix );
  free( bad_X1 );
  free( bad_Y1 );
  free( bad_X2 );
  free( bad_Y2 );
  return 0;
 }
 free( bad_X1 );
 free( bad_Y1 );
 free( bad_X2 );
 free( bad_Y2 );

 // ------------------------------------------------------------------
 // Read saturation level from default.sex
 // ------------------------------------------------------------------
 satur_level= read_satur_level_from_default_sex();
 fprintf( stderr, "Saturation level: %.1f\n", satur_level );

 // ------------------------------------------------------------------
 // Saturation and NaN/Inf check over aperture pixels
 // ------------------------------------------------------------------
 ix_min= (int)floor( center_x - aperture_radius - 1.0 );
 ix_max= (int)ceil( center_x + aperture_radius + 1.0 );
 iy_min= (int)floor( center_y - aperture_radius - 1.0 );
 iy_max= (int)ceil( center_y + aperture_radius + 1.0 );
 if ( ix_min < 1 ) ix_min= 1;
 if ( iy_min < 1 ) iy_min= 1;
 if ( ix_max > naxes[0] ) ix_max= (int)naxes[0];
 if ( iy_max > naxes[1] ) iy_max= (int)naxes[1];

 for ( iy= iy_min; iy <= iy_max; iy++ ) {
  for ( ix= ix_min; ix <= ix_max; ix++ ) {
   weight= pixwt_scalar( center_x, center_y, aperture_radius, (double)ix, (double)iy );
   if ( weight <= 0.0 ) {
    continue;
   }
   pix_idx= ( (long)iy - 1 ) * naxes[0] + ( (long)ix - 1 );
   pix_val= pix[pix_idx];
   if ( isnan( pix_val ) || isinf( pix_val ) ) {
    fprintf( stderr, "ERROR: NaN/Inf pixel at (%d, %d) within aperture\n", ix, iy );
    fprintf( stdout, "99.0000 99.0000 nan_pixel\n" );
    free( pix );
    return 0;
   }
   if ( pix_val >= satur_level ) {
    fprintf( stderr, "ERROR: saturated pixel at (%d, %d) value=%.1f >= %.1f\n",
             ix, iy, pix_val, satur_level );
    fprintf( stdout, "99.0000 99.0000 saturated\n" );
    free( pix );
    return 0;
   }
  }
 }

 // ------------------------------------------------------------------
 // Background estimation from annulus
 // ------------------------------------------------------------------
 // Allocate generously for annulus pixel collection
 n_annulus_alloc= (int)( 4.0 * annulus_outer * annulus_outer ) + 100;
 annulus_vals= (double *)malloc( n_annulus_alloc * sizeof( double ) );
 annulus_copy= (double *)malloc( n_annulus_alloc * sizeof( double ) );
 abs_dev= (double *)malloc( n_annulus_alloc * sizeof( double ) );
 if ( annulus_vals == NULL || annulus_copy == NULL || abs_dev == NULL ) {
  fprintf( stderr, "ERROR: cannot allocate memory for annulus arrays\n" );
  free( pix );
  free( annulus_vals );
  free( annulus_copy );
  free( abs_dev );
  return 1;
 }

 // Collect annulus pixels (center-in/center-out)
 ix_min= (int)floor( center_x - annulus_outer - 1.0 );
 ix_max= (int)ceil( center_x + annulus_outer + 1.0 );
 iy_min= (int)floor( center_y - annulus_outer - 1.0 );
 iy_max= (int)ceil( center_y + annulus_outer + 1.0 );
 if ( ix_min < 1 ) ix_min= 1;
 if ( iy_min < 1 ) iy_min= 1;
 if ( ix_max > naxes[0] ) ix_max= (int)naxes[0];
 if ( iy_max > naxes[1] ) iy_max= (int)naxes[1];

 n_annulus= 0;
 for ( iy= iy_min; iy <= iy_max; iy++ ) {
  for ( ix= ix_min; ix <= ix_max; ix++ ) {
   dist2= ( (double)ix - center_x ) * ( (double)ix - center_x )
         + ( (double)iy - center_y ) * ( (double)iy - center_y );
   if ( dist2 < annulus_inner * annulus_inner || dist2 >= annulus_outer * annulus_outer ) {
    continue;
   }
   pix_idx= ( (long)iy - 1 ) * naxes[0] + ( (long)ix - 1 );
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
  fprintf( stdout, "99.0000 99.0000 edge\n" );
  free( pix );
  free( annulus_vals );
  free( annulus_copy );
  free( abs_dev );
  return 0;
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

 // Start with all annulus pixels in the working copy
 memcpy( annulus_copy, annulus_vals, n_annulus * sizeof( double ) );
 n_clipped= n_annulus;

 // Iterative kappa-sigma clipping until convergence
 for ( iter= 0; iter < 50; iter++ ) {
  n_prev= n_clipped;

  // Compute median of current set (quickselect destroys array, use abs_dev as scratch)
  memcpy( abs_dev, annulus_copy, n_clipped * sizeof( double ) );
  clip_median= quickselect_median_double( abs_dev, n_clipped );

  // Compute mean and standard deviation of current set
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

  // Clip at median +/- 3*sigma
  n_clipped= 0;
  for ( i= 0; i < n_prev; i++ ) {
   if ( fabs( annulus_copy[i] - clip_median ) <= 3.0 * clip_sigma ) {
    annulus_copy[n_clipped]= annulus_copy[i];
    n_clipped++;
   }
  }

  // Safety: do not clip below 30% of original pixels
  if ( n_clipped < (int)( 0.3 * (double)n_annulus ) ) {
   fprintf( stderr, "WARNING: sigma clipping too aggressive at iter %d (%d/%d survived), stopping\n",
            iter, n_clipped, n_annulus );
   // Restore previous iteration's data
   memcpy( annulus_copy, annulus_vals, n_annulus * sizeof( double ) );
   n_clipped= n_annulus;
   break;
  }

  // Check convergence: number of pixels unchanged
  if ( n_clipped == n_prev ) {
   break;
  }
 }
 fprintf( stderr, "Iterative clipping converged after %d iterations, %d/%d pixels remain\n",
          iter, n_clipped, n_annulus );

 // Compute final statistics of clipped set
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

 // Mode estimation: mode = 2.5 * median - 1.5 * mean
 bg_mode= 2.5 * clip_median - 1.5 * clip_mean;

 // Fall back to median if mode and median disagree by more than 0.3 * sigma
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

 // Compute median of annulus pixels (quickselect destroys array, use copy)
 memcpy( annulus_copy, annulus_vals, n_annulus * sizeof( double ) );
 bg_median= quickselect_median_double( annulus_copy, n_annulus );

 // Compute MAD
 for ( i= 0; i < n_annulus; i++ ) {
  abs_dev[i]= fabs( annulus_vals[i] - bg_median );
 }
 bg_mad= quickselect_median_double( abs_dev, n_annulus );
 sigma_mad= 1.4826 * bg_mad;
 fprintf( stderr, "Background before clipping: median=%.2f MAD=%.2f sigma_MAD=%.2f\n",
          bg_median, bg_mad, sigma_mad );

 // One iteration of sigma clipping (3 * sigma_MAD)
 n_clipped= 0;
 for ( i= 0; i < n_annulus; i++ ) {
  if ( fabs( annulus_vals[i] - bg_median ) <= 3.0 * sigma_mad ) {
   annulus_copy[n_clipped]= annulus_vals[i];
   n_clipped++;
  }
 }

 // Safety: if too few pixels survive, revert to all
 if ( n_clipped < (int)( 0.3 * (double)n_annulus ) ) {
  fprintf( stderr, "WARNING: sigma clipping too aggressive (%d/%d survived), using all pixels\n",
           n_clipped, n_annulus );
  memcpy( annulus_copy, annulus_vals, n_annulus * sizeof( double ) );
  n_clipped= n_annulus;
 }

 // Final background from clipped pixels
 // Make another copy because quickselect destroys array
 memcpy( abs_dev, annulus_copy, n_clipped * sizeof( double ) );
 bg_per_pixel= quickselect_median_double( abs_dev, n_clipped );

 // Final sigma from clipped pixels
 for ( i= 0; i < n_clipped; i++ ) {
  abs_dev[i]= fabs( annulus_copy[i] - bg_per_pixel );
 }
 sigma_bg= 1.4826 * quickselect_median_double( abs_dev, n_clipped );

 fprintf( stderr, "Background after clipping: median=%.2f sigma=%.2f (%d pixels)\n",
          bg_per_pixel, sigma_bg, n_clipped );
#endif

 free( annulus_vals );
 free( annulus_copy );
 free( abs_dev );

 // ------------------------------------------------------------------
 // Aperture flux measurement with exact pixel weights
 // ------------------------------------------------------------------
 ix_min= (int)floor( center_x - aperture_radius - 1.0 );
 ix_max= (int)ceil( center_x + aperture_radius + 1.0 );
 iy_min= (int)floor( center_y - aperture_radius - 1.0 );
 iy_max= (int)ceil( center_y + aperture_radius + 1.0 );
 if ( ix_min < 1 ) ix_min= 1;
 if ( iy_min < 1 ) iy_min= 1;
 if ( ix_max > naxes[0] ) ix_max= (int)naxes[0];
 if ( iy_max > naxes[1] ) iy_max= (int)naxes[1];

 sum_aperture= 0.0;
 n_eff= 0.0;
 for ( iy= iy_min; iy <= iy_max; iy++ ) {
  for ( ix= ix_min; ix <= ix_max; ix++ ) {
   weight= pixwt_scalar( center_x, center_y, aperture_radius, (double)ix, (double)iy );
   if ( weight <= 0.0 ) {
    continue;
   }
   pix_idx= ( (long)iy - 1 ) * naxes[0] + ( (long)ix - 1 );
   sum_aperture+= pix[pix_idx] * weight;
   n_eff+= weight;
  }
 }

 free( pix );

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
  strncpy( status_str, "detection", sizeof( status_str ) - 1 );
 } else {
  // 3-sigma upper limit
  if ( noise > 0.0 ) {
   inst_mag= -2.5 * log10( 3.0 * noise );
  } else {
   inst_mag= 99.0;
  }
  mag_err= 99.0;
  strncpy( status_str, "upperlimit", sizeof( status_str ) - 1 );
 }
 status_str[sizeof( status_str ) - 1]= '\0';

 fprintf( stderr, "Instrumental magnitude: %.4f\n", inst_mag );

 // ------------------------------------------------------------------
 // Magnitude calibration
 // ------------------------------------------------------------------
 if ( 0 != read_calib_param( &calib_p3, &calib_p2, &calib_p1, &calib_p0 ) ) {
  fprintf( stderr, "ERROR: magnitude calibration failed\n" );
  fprintf( stdout, "99.0000 99.0000 calib_fail\n" );
  return 0;
 }

 cal_mag= calib_p2 * inst_mag * inst_mag + calib_p1 * inst_mag + calib_p0;
 fprintf( stderr, "Calibrated magnitude: %.4f\n", cal_mag );

 // ------------------------------------------------------------------
 // Output result
 // ------------------------------------------------------------------
 fprintf( stdout, "%.4f %.4f %s\n", cal_mag, mag_err, status_str );

 return 0;
}
