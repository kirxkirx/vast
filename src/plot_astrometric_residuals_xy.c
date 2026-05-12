// plot_astrometric_residuals_xy -- PGPLOT diagnostic for catalog-matched
// star distribution across an image.
//
// Input:  a FITS file (e.g., wcs_<image>.fts) or its accompanying
//         .cat.astrometric_residuals file.
// Output: <basename>_astrometric_residuals.png in the current directory.
//
// The .cat.astrometric_residuals file is produced by solve_plate_with_UCAC5
// (write_astrometric_residuals_vector_field). Columns 8 and 9 are x_pix,
// y_pix of each catalog-matched star. This tool plots those coordinates
// with the plot's aspect ratio matched to the source image's NAXIS1:NAXIS2,
// so the distribution is visually faithful to the chip layout.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "fitsio.h"
#include "cpgplot.h"

#include "setenv_local_pgplot.h"

#define MAX_POINTS 1000000
#define PATH_MAX_LEN 4096

// Strip a trailing .fts / .fits / .fit extension (case-insensitive) and
// return the index where the extension started; returns the original length
// if no recognized extension is present.
static size_t length_without_fits_ext( const char *path ) {
 size_t len;
 size_t i;
 const char *suffix;
 size_t suffix_len;
 const char *known_suffixes[] = { ".fits", ".fts", ".fit", NULL };
 len= strlen( path );
 for ( i= 0; known_suffixes[i] != NULL; i++ ) {
  suffix= known_suffixes[i];
  suffix_len= strlen( suffix );
  if ( len >= suffix_len ) {
   size_t j;
   int matches= 1;
   for ( j= 0; j < suffix_len; j++ ) {
    char a;
    char b;
    a= path[len - suffix_len + j];
    b= suffix[j];
    if ( a >= 'A' && a <= 'Z' )
     a= (char)( a - 'A' + 'a' );
    if ( a != b ) {
     matches= 0;
     break;
    }
   }
   if ( matches )
    return len - suffix_len;
  }
 }
 return len;
}

// Strip the trailing ".cat.astrometric_residuals" if present; returns the
// original length otherwise.
static size_t length_without_residuals_ext( const char *path ) {
 const char *suffix = ".cat.astrometric_residuals";
 size_t len;
 size_t suffix_len;
 len= strlen( path );
 suffix_len= strlen( suffix );
 if ( len >= suffix_len && strcmp( path + len - suffix_len, suffix ) == 0 )
  return len - suffix_len;
 return len;
}

// Read NAXIS1 / NAXIS2 from the FITS file at fits_path. Returns 0 on
// success, non-zero on failure. Uses fits_open_image so compressed files
// (.fz) are handled transparently.
static int read_fits_dimensions( const char *fits_path, long *nx, long *ny ) {
 fitsfile *fptr= NULL;
 int status= 0;
 int naxis= 0;
 long naxes[9];
 fits_open_image( &fptr, (char *)fits_path, READONLY, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  return 1;
 }
 fits_get_img_dim( fptr, &naxis, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  fits_close_file( fptr, &status );
  return 2;
 }
 if ( naxis < 2 ) {
  fprintf( stderr, "plot_astrometric_residuals_xy: %s has NAXIS=%d, expected >=2\n",
           fits_path, naxis );
  fits_close_file( fptr, &status );
  return 3;
 }
 fits_get_img_size( fptr, 2, naxes, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  fits_close_file( fptr, &status );
  return 4;
 }
 fits_close_file( fptr, &status );
 *nx= naxes[0];
 *ny= naxes[1];
 return 0;
}

// Read column 8 (x_pix) and column 9 (y_pix) from each line. Returns the
// number of points successfully read or -1 on file-open failure.
static int read_xy_from_residuals_file( const char *path, float *x, float *y, int max_points ) {
 FILE *f;
 char line[1024];
 int n;
 double c[9];
 f= fopen( path, "r" );
 if ( f == NULL ) {
  return -1;
 }
 n= 0;
 while ( n < max_points && fgets( line, (int)sizeof( line ), f ) != NULL ) {
  int parsed;
  parsed= sscanf( line, "%lf %lf %lf %lf %lf %lf %lf %lf %lf",
                  &c[0], &c[1], &c[2], &c[3], &c[4], &c[5], &c[6], &c[7], &c[8] );
  if ( parsed == 9 ) {
   x[n]= (float)c[7];
   y[n]= (float)c[8];
   n++;
  }
 }
 fclose( f );
 return n;
}

int main( int argc, char **argv ) {
 char fits_path[PATH_MAX_LEN];
 char residuals_path[PATH_MAX_LEN];
 char png_path[PATH_MAX_LEN];
 char png_device_spec[PATH_MAX_LEN];
 char title[PATH_MAX_LEN];
 char fits_basename[PATH_MAX_LEN];
 long nx;
 long ny;
 int have_fits;
 size_t input_len;
 const char *input;
 float *x;
 float *y;
 int n_points;
 int dim_status;
 size_t base_len;
 const char *bn;
 size_t i;
 double aspect_ratio;

 if ( argc != 2 ) {
  fprintf( stderr, "Usage: %s <fits-file | .cat.astrometric_residuals>\n", argv[0] );
  fprintf( stderr, "Plots the (x_pix, y_pix) distribution of catalog-matched\n" );
  fprintf( stderr, "stars from the .cat.astrometric_residuals file accompanying\n" );
  fprintf( stderr, "the given FITS image.\n" );
  return 1;
 }
 input= argv[1];
 input_len= strlen( input );
 if ( input_len >= PATH_MAX_LEN - 32 ) {
  fprintf( stderr, "%s: input path too long\n", argv[0] );
  return 1;
 }

 // Determine which side of the (FITS, residuals) pair we were given.
 if ( input_len >= strlen( ".cat.astrometric_residuals" ) &&
      strcmp( input + input_len - strlen( ".cat.astrometric_residuals" ),
              ".cat.astrometric_residuals" ) == 0 ) {
  // Input is the residuals file; derive the FITS path by stripping the
  // ".cat.astrometric_residuals" suffix.
  size_t fits_len;
  fits_len= length_without_residuals_ext( input );
  memcpy( fits_path, input, fits_len );
  fits_path[fits_len]= '\0';
  strncpy( residuals_path, input, PATH_MAX_LEN - 1 );
  residuals_path[PATH_MAX_LEN - 1]= '\0';
 } else {
  // Input is the FITS file; the residuals file sits beside it with the
  // ".cat.astrometric_residuals" suffix.
  strncpy( fits_path, input, PATH_MAX_LEN - 1 );
  fits_path[PATH_MAX_LEN - 1]= '\0';
  snprintf( residuals_path, PATH_MAX_LEN, "%s.cat.astrometric_residuals", fits_path );
 }

 // Try to read NAXIS1 / NAXIS2. If the FITS file is not available, we will
 // fall back to bounds from the residuals data later.
 have_fits= ( 0 == read_fits_dimensions( fits_path, &nx, &ny ) );
 if ( !have_fits ) {
  fprintf( stderr,
           "plot_astrometric_residuals_xy: could not read dimensions from %s, "
           "falling back to data extent\n",
           fits_path );
 }

 // Allocate point buffers and read the residuals file.
 x= (float *)malloc( (size_t)MAX_POINTS * sizeof( float ) );
 y= (float *)malloc( (size_t)MAX_POINTS * sizeof( float ) );
 if ( x == NULL || y == NULL ) {
  fprintf( stderr, "plot_astrometric_residuals_xy: malloc failed\n" );
  free( x );
  free( y );
  return 2;
 }
 n_points= read_xy_from_residuals_file( residuals_path, x, y, MAX_POINTS );
 if ( n_points < 0 ) {
  // Friendly to the calling pipeline: not finding the residuals file is not
  // a hard error since the plate solve may have failed for other reasons.
  fprintf( stderr,
           "plot_astrometric_residuals_xy: cannot open %s -- skipping plot\n",
           residuals_path );
  free( x );
  free( y );
  return 0;
 }

 // If we have no FITS dimensions, derive a bounding box from the data.
 if ( !have_fits ) {
  if ( n_points <= 0 ) {
   fprintf( stderr,
            "plot_astrometric_residuals_xy: %s is empty and no FITS dimensions; "
            "nothing to plot\n",
            residuals_path );
   free( x );
   free( y );
   return 0;
  } else {
   float xmin;
   float xmax;
   float ymin;
   float ymax;
   int j;
   xmin= xmax= x[0];
   ymin= ymax= y[0];
   for ( j= 1; j < n_points; j++ ) {
    if ( x[j] < xmin )
     xmin= x[j];
    if ( x[j] > xmax )
     xmax= x[j];
    if ( y[j] < ymin )
     ymin= y[j];
    if ( y[j] > ymax )
     ymax= y[j];
   }
   nx= (long)( xmax - xmin + 1.0f );
   ny= (long)( ymax - ymin + 1.0f );
   if ( nx < 1 )
    nx= 1;
   if ( ny < 1 )
    ny= 1;
  }
 }

 // Build the output PNG filename. Strip a trailing .fts/.fits/.fit from
 // the FITS basename so the result reads cleanly.
 bn= strrchr( fits_path, '/' );
 if ( bn == NULL )
  bn= fits_path;
 else
  bn= bn + 1;
 strncpy( fits_basename, bn, PATH_MAX_LEN - 1 );
 fits_basename[PATH_MAX_LEN - 1]= '\0';
 base_len= length_without_fits_ext( fits_basename );
 fits_basename[base_len]= '\0';
 // Replace characters PGPLOT's /PNG device interprets specially in the
 // filename portion -- the device spec ends at '/', so any '/' or '+' in
 // the cwd-relative output name would confuse it. Our convention is to
 // write to cwd so the name should be safe, but be defensive.
 for ( i= 0; i < base_len; i++ ) {
  if ( fits_basename[i] == '/' )
   fits_basename[i]= '_';
 }
 snprintf( png_path, PATH_MAX_LEN, "%s_astrometric_residuals.png", fits_basename );

 // PGPLOT device specification: <filename>/PNG.
 snprintf( png_device_spec, PATH_MAX_LEN, "%s/PNG", png_path );

 // Title shows the FITS basename and the matched-star count.
 snprintf( title, PATH_MAX_LEN, "%s  [%d matched]", fits_basename, n_points );

 // Aspect ratio for cpgpap: PGPLOT interprets the second argument as
 // height/width. We want a plot whose drawing area is proportional to the
 // image (NAXIS2 / NAXIS1).
 aspect_ratio= (double)ny / (double)nx;
 if ( aspect_ratio <= 0.0 )
  aspect_ratio= 1.0;

 setenv_localpgplot( argv[0] );
 if ( 1 == cpgbeg( 0, png_device_spec, 1, 1 ) ) {
  // White background, black foreground -- match fit_mag_calib's convention
  // so the resulting PNG is readable on the white-background HTML log.
  cpgscr( 0, 1.0f, 1.0f, 1.0f );
  cpgscr( 1, 0.0f, 0.0f, 0.0f );
  // Default page width with the requested aspect ratio.
  cpgpap( 8.0, (float)aspect_ratio );
  cpgsvp( 0.10f, 0.95f, 0.10f, 0.92f );
  cpgswin( 0.0f, (float)nx, 0.0f, (float)ny );
  cpgscf( 1 );
  cpgbox( "BCNST", 0.0, 0, "BCNST", 0.0, 0 );
  cpglab( "X (pixels)", "Y (pixels)", title );
  if ( n_points > 0 ) {
   // Filled circle marker in red (color index 2), slightly smaller than
   // default so dense fields remain readable.
   cpgsch( 0.6f );
   cpgsci( 2 );
   cpgpt( n_points, x, y, 17 );
  }
  cpgend();
  fprintf( stderr,
           "plot_astrometric_residuals_xy: wrote %s (%d matched stars from %s, image %ldx%ld)\n",
           png_path, n_points, residuals_path, nx, ny );
 } else {
  fprintf( stderr,
           "plot_astrometric_residuals_xy: PGPLOT /PNG device not available -- "
           "no plot produced\n" );
 }

 free( x );
 free( y );
 return 0;
}
