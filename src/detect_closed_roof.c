// detect_closed_roof - find images taken with the observatory roof (dome) closed.
//
// When the roof closes without the camera control software knowing about it,
// the camera keeps taking pictures of the inside of the closed roof. Such
// images contain no stars and (almost) no light: apart from a little stray
// light, the image background stays at the dark-frame level.
//
// The tool counts star-like peaks and measures the background level relative
// to a dark frame (if one is given), and prints one of these verdicts:
//   OK          - the image shows stars;
//   CLOSED_ROOF - no stars, and the background is at the dark level:
//                 the image was taken with the roof (dome) closed;
//   NO_STARS    - no stars, but the background is well above the dark level
//                 (thick clouds, fog, dew, light inside the dome), or the
//                 dark level is unknown (no dark frame) so the two cases
//                 cannot be told apart;
//   PARTLY_DARK - stars are visible, but a part of the field of view gets
//                 no sky light (the roof is partly closed or moving, or
//                 something blocks the view). Reported only when a dark
//                 frame is given.
//
// Usage: detect_closed_roof [-n MAX_STARS] [-r MAX_SKY_ADU_PER_SEC] [-b MAX_SKY_ADU] [-s MAX_NOISE_ADU] [-v] image.fits [dark.fits]
//
// Exit codes: 0 - OK; 1 - CLOSED_ROOF, NO_STARS or PARTLY_DARK; 2 - error.
//
// Star-like peaks are counted on (image - dark), or on the image alone if no
// dark frame is given. The background and its scatter are estimated with the
// median and the median absolute deviation in tiles of about 128x128 pixels,
// which keeps the detection threshold right in the presence of background
// gradients. A pixel counts as a star if it is a local maximum more than
// 5 sigma above the local background and at least 6 of its 8 neighbours are
// more than 2 sigma above the background. The neighbour condition rejects hot
// pixels and most cosmic-ray hits.
//
// The thresholds were checked on a year of NMW-TexasTech images (QHY600M,
// 135 mm f/2.2 lens, 20 s exposures, 61 Mpix): closed-roof frames show 0-1
// peaks and sit -1 to +18 ADU above the dark frame, while every frame that
// sees the sky shows thousands of peaks and the faintest sky seen was
// +268 ADU above the dark.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <time.h>
#include <unistd.h> // for getopt()

#include "fitsio.h"
#include "vast_limits.h"
#include "fitsfile_read_check.h"

#define DCR_DEFAULT_MAX_STARS 20
#define DCR_DEFAULT_MAX_SKY_ADU_PER_SEC 5.0
// The background limit if the exposure time is unknown (5 ADU/s for a 20 s exposure)
#define DCR_DEFAULT_MAX_SKY_ADU_UNKNOWN_EXPTIME 100.0
// Target tile size (pixels) for the local background estimate. Actual tiles are 128-255 pixels.
#define DCR_TILE_SIZE 128
// The field of view is divided in up to DCR_N_REGIONS x DCR_N_REGIONS regions to find partly dark images
#define DCR_N_REGIONS 4
#define DCR_DETECTION_SIGMA 5.0
#define DCR_NEIGHBOUR_SIGMA 2.0
#define DCR_MIN_BRIGHT_NEIGHBOURS 6
// Pixels this close to the image edge are ignored
#define DCR_MAX_BORDER_PIX 10
#define DCR_MIN_IMAGE_SIZE_PIX 16
// A tile needs at least this fraction of valid (finite) pixels
#define DCR_MIN_VALID_PIXEL_FRACTION 0.5
#define DCR_MAD_TO_SIGMA 1.4826
// EXPTIME values above this (seconds) are treated as unknown
#define DCR_MAX_SANE_EXPTIME_SEC 1.0e6
// The dark frame does not match the image if the image background is below the dark level by more
// than DCR_MISMATCH_NOISE_UNITS times the noise and more than this fraction of the background limit
#define DCR_MISMATCH_NOISE_UNITS 3.0
#define DCR_MISMATCH_FRACTION_OF_SKY_LIMIT 0.5
// In a dark-subtracted image (folded at zero by util/ccd/ms) a tile with median < 2 sigma_MAD is treated as folded noise
#define DCR_FOLDED_NOISE_MEDIAN_TO_SIGMA 2.0

#define DCR_EXIT_OK 0
#define DCR_EXIT_PROBLEM 1
#define DCR_EXIT_ERROR 2

#define DCR_ZERO_LEVEL_NONE 0
#define DCR_ZERO_LEVEL_DARK 1
#define DCR_ZERO_LEVEL_HEADER 2
// The dark frame cannot be the zero level: the image background is far below the dark level
#define DCR_ZERO_LEVEL_MISMATCH 3

static void print_usage( char *progname ) {
 fprintf( stderr, "Detect images with no stars taken with the observatory roof (dome) closed.\n\n" );
 fprintf( stderr, "Usage: %s [-n MAX_STARS] [-r MAX_SKY_ADU_PER_SEC] [-b MAX_SKY_ADU] [-s MAX_NOISE_ADU] [-v] image.fits [dark.fits]\n\n", progname );
 fprintf( stderr, "  -n MAX_STARS            an image with fewer star-like peaks has no stars (default %d)\n", DCR_DEFAULT_MAX_STARS );
 fprintf( stderr, "  -r MAX_SKY_ADU_PER_SEC  a starless image counts as taken with the roof closed if its\n" );
 fprintf( stderr, "                          background is less than this many ADU per second of exposure\n" );
 fprintf( stderr, "                          above the dark level (default %.1f; %.0f ADU if the exposure\n", DCR_DEFAULT_MAX_SKY_ADU_PER_SEC, DCR_DEFAULT_MAX_SKY_ADU_UNKNOWN_EXPTIME );
 fprintf( stderr, "                          time is not in the FITS header)\n" );
 fprintf( stderr, "  -b MAX_SKY_ADU          the same limit in ADU, regardless of the exposure time\n" );
 fprintf( stderr, "  -s MAX_NOISE_ADU        a starless image at the dark level counts as taken with the roof closed\n" );
 fprintf( stderr, "                          only if its noise is below this (about 2x the read noise in ADU is a\n" );
 fprintf( stderr, "                          good value); a noisier one means that the dark does not match the image\n" );
 fprintf( stderr, "                          (default 0 = no limit)\n" );
 fprintf( stderr, "  -v                      print diagnostics on stderr\n\n" );
 fprintf( stderr, "The dark frame should match the image (same camera, size, exposure time and temperature).\n" );
 fprintf( stderr, "Without it the background level cannot be compared with the dark level, unless the image\n" );
 fprintf( stderr, "header says it was dark-subtracted already (HISTORY Dark frame subtraction, written by util/ccd/ms).\n\n" );
 fprintf( stderr, "Prints one line: VERDICT key=value ... where VERDICT is OK, CLOSED_ROOF, NO_STARS or PARTLY_DARK.\n" );
 fprintf( stderr, "Exit codes: 0 = OK, 1 = CLOSED_ROOF, NO_STARS or PARTLY_DARK, 2 = error\n" );
 return;
}

// Return the k-th smallest value (k is 0-based) of a[0..n-1], partially reordering a[].
// This is quickselect with a median-of-three pivot and a three-way partition:
// integer camera data have long runs of equal values that make a plain
// two-way partition very slow.
static float select_kth_smallest( float *a, long n, long k ) {
 long lo, hi, lt, gt, i, mid;
 float pivot, tmp, x, y, z;

 lo= 0;
 hi= n - 1;
 while ( lo < hi ) {
  mid= lo + ( hi - lo ) / 2;
  x= a[lo];
  y= a[mid];
  z= a[hi];
  // median of three
  if ( x < y ) {
   if ( y < z ) {
    pivot= y;
   } else if ( x < z ) {
    pivot= z;
   } else {
    pivot= x;
   }
  } else {
   if ( x < z ) {
    pivot= x;
   } else if ( y < z ) {
    pivot= z;
   } else {
    pivot= y;
   }
  }
  // three-way partition: a[lo..lt-1] < pivot, a[lt..gt] == pivot, a[gt+1..hi] > pivot
  lt= lo;
  gt= hi;
  i= lo;
  while ( i <= gt ) {
   if ( a[i] < pivot ) {
    tmp= a[lt];
    a[lt]= a[i];
    a[i]= tmp;
    lt++;
    i++;
   } else if ( a[i] > pivot ) {
    tmp= a[gt];
    a[gt]= a[i];
    a[i]= tmp;
    gt--;
   } else {
    i++;
   }
  }
  if ( k < lt ) {
   hi= lt - 1;
  } else if ( k > gt ) {
   lo= gt + 1;
  } else {
   return pivot;
  }
 }
 return a[k];
}

// The file name without the directory part. Unlike basename(), this never modifies its
// argument or returns a pointer to a static buffer (shared between calls on macOS and old FreeBSD).
static char *file_name_without_path( char *path ) {
 char *last_slash;
 last_slash= strrchr( path, '/' );
 if ( last_slash == NULL ) {
  return path;
 }
 return last_slash + 1;
}

// Median of a[0..n-1] (the upper median for even n), partially reordering a[]
static float median_of_float_array( float *a, long n ) {
 return select_kth_smallest( a, n, n / 2 );
}

// Parse a non-negative number from a command line option. Returns 0 on success.
static int parse_nonnegative_number( char *string, double *value ) {
 char *endptr;
 double x;
 if ( string == NULL || string[0] == '\0' ) {
  return 1;
 }
 x= strtod( string, &endptr );
 if ( endptr == string || *endptr != '\0' ) {
  return 1;
 }
 if ( !( x >= 0.0 ) || x > 1.0e30 ) {
  return 1;
 }
 ( *value )= x;
 return 0;
}

// Open a FITS image and get its size. Only the first plane of a data cube is used.
// Returns 0 on success.
static int open_fits_image_and_get_size( char *filename, fitsfile **fptr, long *nx, long *ny, int *bitpix ) {
 int status= 0;
 int hdutype;
 int naxis;
 long naxes[3];

 if ( 0 != fits_open_image( fptr, filename, READONLY, &status ) ) {
  fprintf( stderr, "ERROR: cannot open the FITS image %s\n", filename );
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  return 1;
 }
 if ( 0 != fits_get_hdu_type( *fptr, &hdutype, &status ) || hdutype != IMAGE_HDU ) {
  fprintf( stderr, "ERROR: %s is not an image\n", filename );
  status= 0;
  fits_close_file( *fptr, &status );
  return 1;
 }
 fits_get_img_dim( *fptr, &naxis, &status );
 if ( status != 0 || naxis < 2 || naxis > 3 ) {
  fprintf( stderr, "ERROR: %s has NAXIS=%d - only 2D images (or the first plane of a 3D cube) are supported\n", filename, naxis );
  status= 0;
  fits_close_file( *fptr, &status );
  return 1;
 }
 naxes[0]= naxes[1]= naxes[2]= 1;
 fits_get_img_size( *fptr, 3, naxes, &status );
 fits_get_img_type( *fptr, bitpix, &status );
 if ( status != 0 ) {
  fprintf( stderr, "ERROR: cannot get the image size of %s\n", filename );
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  status= 0;
  fits_close_file( *fptr, &status );
  return 1;
 }
 ( *nx )= naxes[0];
 ( *ny )= naxes[1];
 return 0;
}

// Exposure time from the EXPTIME (or, if absent, EXPOSURE) keyword; -1.0 if unknown
static double read_exposure_time( fitsfile *fptr ) {
 int status= 0;
 double exptime;

 exptime= -1.0;
 if ( 0 != fits_read_key( fptr, TDOUBLE, "EXPTIME", &exptime, NULL, &status ) ) {
  status= 0;
  exptime= -1.0;
  if ( 0 != fits_read_key( fptr, TDOUBLE, "EXPOSURE", &exptime, NULL, &status ) ) {
   exptime= -1.0;
  }
 }
 fits_clear_errmsg();
 // this also rejects NaN and Inf
 if ( !( exptime > 0.0 ) || exptime > DCR_MAX_SANE_EXPTIME_SEC ) {
  exptime= -1.0;
 }
 return exptime;
}

// Returns 1 if the header has the HISTORY record written by util/ccd/ms
// when it subtracts a dark (or bias) frame, 0 otherwise
static int image_is_dark_subtracted( fitsfile *fptr ) {
 int status= 0;
 int nkeys, ii;
 char card[FLEN_CARD];

 if ( 0 != fits_get_hdrspace( fptr, &nkeys, NULL, &status ) ) {
  fits_clear_errmsg();
  return 0;
 }
 for ( ii= 1; ii <= nkeys; ii++ ) {
  if ( 0 != fits_read_record( fptr, ii, card, &status ) ) {
   fits_clear_errmsg();
   return 0;
  }
  if ( 0 != strncmp( card, "HISTORY", 7 ) ) {
   continue;
  }
  if ( NULL != strstr( card, "Dark frame subtraction:" ) || NULL != strstr( card, "Bias frame subtraction:" ) ) {
   return 1;
  }
 }
 return 0;
}

// Read nrows image rows starting from the 0-based row first_row into buf (as float)
static int read_image_rows( fitsfile *fptr, long nx, long first_row, long nrows, float *buf ) {
 int status= 0;
 long fpixel[3];

 fpixel[0]= 1;
 fpixel[1]= first_row + 1;
 fpixel[2]= 1; // the first plane of a cube
 if ( 0 != fits_read_pix( fptr, TFLOAT, fpixel, nx * nrows, NULL, buf, NULL, &status ) ) {
  fits_report_error( stderr, status );
  fits_clear_errmsg();
  return 1;
 }
 return 0;
}

int main( int argc, char **argv ) {
 char imagefilename[FILENAME_LENGTH];
 char darkfilename[FILENAME_LENGTH];
 char *image_basename;
 char *dark_basename;
 char exptime_string[64];
 char above_dark_string[64];
 char dark_regions_string[64];
 char *verdict;
 fitsfile *imagefptr;
 fitsfile *darkfptr;
 int status;
 int opt;
 int verbose;
 int dark_given;
 int zero_level;
 int bitpix, dark_bitpix;
 long nx, ny, dark_nx, dark_ny;
 long border;
 long ntx, nty, tile_index, i, j, x, y, row, k;
 long nreg_x, nreg_y, nreg, reg, reg_x, reg_y;
 long *tile_x_edge;
 long *tile_y_edge;
 long *tile_of_x;
 long max_tile_w, max_tile_h, work_size;
 long n_valid, n_valid_tiles, n_valid_regions, n_dark_regions;
 long buf_first_row, buf_nrows;
 long star_count;
 long *region_star_count;
 long *region_n_tiles;
 long region_star_limit;
 float *tile_median;
 float *tile_center;
 float *tile_sigma;
 char *tile_is_valid;
 float *region_background;
 float *image_buf;
 float *dark_buf;
 float *work;
 float *row_above;
 float *row_this;
 float *row_below;
 float value, neighbour, threshold_high, threshold_low, sigma_floor;
 float global_background, global_noise;
 double max_stars_double;
 double max_sky_adu_per_sec;
 double max_sky_adu_absolute;
 double max_sky_adu;
 double max_noise_adu;
 double exptime, dark_exptime;
 double bscale;
 double folded_noise_rms, clip_level, sum_of_squares;
 double mismatch_limit;
 float tile_mad;
 long n_clipped;
 long n_tiles_with_stats, n_tiles_equal_to_dark;
 int max_stars;
 int is_local_maximum;
 int n_bright_neighbours;
 int dx, dy;
 int exit_code;
 clock_t start_clock;

 start_clock= clock();
 status= 0;
 verbose= 0;
 max_stars= DCR_DEFAULT_MAX_STARS;
 max_sky_adu_per_sec= DCR_DEFAULT_MAX_SKY_ADU_PER_SEC;
 max_sky_adu_absolute= -1.0;
 max_noise_adu= 0.0;
 imagefptr= NULL;
 darkfptr= NULL;
 dark_given= 0;
 zero_level= DCR_ZERO_LEVEL_NONE;
 dark_exptime= -1.0;
 dark_bitpix= 0;
 dark_nx= dark_ny= 0;
 darkfilename[0]= '\0';
 dark_basename= NULL;

 while ( ( opt= getopt( argc, argv, "n:r:b:s:vh" ) ) != -1 ) {
  switch ( opt ) {
  case 'n':
   if ( 0 != parse_nonnegative_number( optarg, &max_stars_double ) || max_stars_double < 1.0 || max_stars_double > 1.0e9 ) {
    fprintf( stderr, "ERROR: bad value of -n: %s (expecting a positive integer)\n", optarg );
    return DCR_EXIT_ERROR;
   }
   max_stars= (int)max_stars_double;
   break;
  case 'r':
   if ( 0 != parse_nonnegative_number( optarg, &max_sky_adu_per_sec ) ) {
    fprintf( stderr, "ERROR: bad value of -r: %s (expecting a non-negative number)\n", optarg );
    return DCR_EXIT_ERROR;
   }
   break;
  case 'b':
   if ( 0 != parse_nonnegative_number( optarg, &max_sky_adu_absolute ) ) {
    fprintf( stderr, "ERROR: bad value of -b: %s (expecting a non-negative number)\n", optarg );
    return DCR_EXIT_ERROR;
   }
   break;
  case 's':
   if ( 0 != parse_nonnegative_number( optarg, &max_noise_adu ) ) {
    fprintf( stderr, "ERROR: bad value of -s: %s (expecting a non-negative number)\n", optarg );
    return DCR_EXIT_ERROR;
   }
   break;
  case 'v':
   verbose= 1;
   break;
  case 'h':
   print_usage( argv[0] );
   return DCR_EXIT_ERROR;
  default:
   print_usage( argv[0] );
   return DCR_EXIT_ERROR;
  }
 }
 if ( argc - optind < 1 || argc - optind > 2 ) {
  print_usage( argv[0] );
  return DCR_EXIT_ERROR;
 }

 if ( 0 != safely_encode_user_input_string( imagefilename, argv[optind], FILENAME_LENGTH ) ) {
  fprintf( stderr, "ERROR: bad image file name\n" );
  return DCR_EXIT_ERROR;
 }
 imagefilename[FILENAME_LENGTH - 1]= '\0';
 if ( 0 != fitsfile_read_check_silent( imagefilename ) ) {
  fprintf( stderr, "ERROR: %s is not a readable FITS image\n", imagefilename );
  return DCR_EXIT_ERROR;
 }
 if ( argc - optind == 2 ) {
  if ( 0 != safely_encode_user_input_string( darkfilename, argv[optind + 1], FILENAME_LENGTH ) ) {
   fprintf( stderr, "ERROR: bad dark frame file name\n" );
   return DCR_EXIT_ERROR;
  }
  darkfilename[FILENAME_LENGTH - 1]= '\0';
  if ( 0 != fitsfile_read_check_silent( darkfilename ) ) {
   fprintf( stderr, "ERROR: %s is not a readable FITS image\n", darkfilename );
   return DCR_EXIT_ERROR;
  }
  if ( 0 == strcmp( imagefilename, darkfilename ) ) {
   fprintf( stderr, "ERROR: the same file %s is given as the image and as the dark frame\n", imagefilename );
   return DCR_EXIT_ERROR;
  }
  dark_given= 1;
 }

 image_basename= file_name_without_path( imagefilename );

 if ( 0 != open_fits_image_and_get_size( imagefilename, &imagefptr, &nx, &ny, &bitpix ) ) {
  return DCR_EXIT_ERROR;
 }
 if ( nx < DCR_MIN_IMAGE_SIZE_PIX || ny < DCR_MIN_IMAGE_SIZE_PIX ) {
  fprintf( stderr, "ERROR: the image %s is too small (%ldx%ld pixels)\n", imagefilename, nx, ny );
  fits_close_file( imagefptr, &status );
  return DCR_EXIT_ERROR;
 }
 exptime= read_exposure_time( imagefptr );
 bscale= 1.0;
 if ( 0 != fits_read_key( imagefptr, TDOUBLE, "BSCALE", &bscale, NULL, &status ) ) {
  status= 0;
  bscale= 1.0;
  fits_clear_errmsg();
 }
 if ( bscale == 0.0 ) {
  bscale= 1.0;
 }

 if ( 1 == image_is_dark_subtracted( imagefptr ) ) {
  zero_level= DCR_ZERO_LEVEL_HEADER;
  if ( dark_given == 1 ) {
   fprintf( stderr, "The image %s has been dark-subtracted already (HISTORY Dark frame subtraction), so the dark frame %s is not used\n", imagefilename, darkfilename );
   dark_given= 0;
  }
 }

 if ( dark_given == 1 ) {
  dark_basename= file_name_without_path( darkfilename );
  if ( 0 != open_fits_image_and_get_size( darkfilename, &darkfptr, &dark_nx, &dark_ny, &dark_bitpix ) ) {
   fits_close_file( imagefptr, &status );
   return DCR_EXIT_ERROR;
  }
  if ( dark_nx != nx || dark_ny != ny ) {
   fprintf( stderr, "ERROR: the dark frame %s is %ldx%ld pixels while the image %s is %ldx%ld pixels\n", darkfilename, dark_nx, dark_ny, imagefilename, nx, ny );
   fits_close_file( darkfptr, &status );
   status= 0;
   fits_close_file( imagefptr, &status );
   return DCR_EXIT_ERROR;
  }
  dark_exptime= read_exposure_time( darkfptr );
  if ( exptime > 0.0 && dark_exptime > 0.0 && fabs( exptime - dark_exptime ) > 0.01 * exptime ) {
   fprintf( stderr, "WARNING: the exposure time of the dark frame %s (%.3lf s) differs from that of the image %s (%.3lf s)\n", darkfilename, dark_exptime, imagefilename, exptime );
  }
  zero_level= DCR_ZERO_LEVEL_DARK;
 }

 // The background limit in ADU
 if ( max_sky_adu_absolute >= 0.0 ) {
  max_sky_adu= max_sky_adu_absolute;
 } else if ( exptime > 0.0 ) {
  max_sky_adu= max_sky_adu_per_sec * exptime;
 } else {
  max_sky_adu= DCR_DEFAULT_MAX_SKY_ADU_UNKNOWN_EXPTIME;
 }

 // Integer-valued data are quantized: a zero MAD means the noise is below the quantization step
 sigma_floor= (float)fabs( bscale );
 if ( bitpix < 0 ) {
  sigma_floor= 1.0;
 }

 // Ignore a thin border, but keep at least 1 pixel so every examined pixel has 8 neighbours
 border= DCR_MAX_BORDER_PIX;
 if ( border > nx / 10 ) {
  border= nx / 10;
 }
 if ( border > ny / 10 ) {
  border= ny / 10;
 }
 if ( border < 1 ) {
  border= 1;
 }

 // Tiles of 128-255 pixels covering [border, n - border)
 ntx= ( nx - 2 * border ) / DCR_TILE_SIZE;
 if ( ntx < 1 ) {
  ntx= 1;
 }
 nty= ( ny - 2 * border ) / DCR_TILE_SIZE;
 if ( nty < 1 ) {
  nty= 1;
 }
 nreg_x= DCR_N_REGIONS;
 if ( nreg_x > ntx ) {
  nreg_x= ntx;
 }
 nreg_y= DCR_N_REGIONS;
 if ( nreg_y > nty ) {
  nreg_y= nty;
 }
 nreg= nreg_x * nreg_y;
 region_star_limit= max_stars / 4;
 if ( region_star_limit < 1 ) {
  region_star_limit= 1;
 }

 tile_x_edge= (long *)malloc( ( ntx + 1 ) * sizeof( long ) );
 tile_y_edge= (long *)malloc( ( nty + 1 ) * sizeof( long ) );
 tile_of_x= (long *)malloc( nx * sizeof( long ) );
 tile_median= (float *)malloc( ntx * nty * sizeof( float ) );
 tile_center= (float *)malloc( ntx * nty * sizeof( float ) );
 tile_sigma= (float *)malloc( ntx * nty * sizeof( float ) );
 tile_is_valid= (char *)malloc( ntx * nty * sizeof( char ) );
 region_star_count= (long *)malloc( nreg * sizeof( long ) );
 region_n_tiles= (long *)malloc( nreg * sizeof( long ) );
 region_background= (float *)malloc( nreg * sizeof( float ) );
 if ( tile_x_edge == NULL || tile_y_edge == NULL || tile_of_x == NULL || tile_median == NULL || tile_center == NULL || tile_sigma == NULL || tile_is_valid == NULL || region_star_count == NULL || region_n_tiles == NULL || region_background == NULL ) {
  fprintf( stderr, "ERROR: cannot allocate memory\n" );
  return DCR_EXIT_ERROR;
 }
 for ( i= 0; i <= ntx; i++ ) {
  tile_x_edge[i]= border + i * ( nx - 2 * border ) / ntx;
 }
 for ( j= 0; j <= nty; j++ ) {
  tile_y_edge[j]= border + j * ( ny - 2 * border ) / nty;
 }
 max_tile_w= 0;
 for ( i= 0; i < ntx; i++ ) {
  if ( tile_x_edge[i + 1] - tile_x_edge[i] > max_tile_w ) {
   max_tile_w= tile_x_edge[i + 1] - tile_x_edge[i];
  }
  for ( x= tile_x_edge[i]; x < tile_x_edge[i + 1]; x++ ) {
   tile_of_x[x]= i;
  }
 }
 max_tile_h= 0;
 for ( j= 0; j < nty; j++ ) {
  if ( tile_y_edge[j + 1] - tile_y_edge[j] > max_tile_h ) {
   max_tile_h= tile_y_edge[j + 1] - tile_y_edge[j];
  }
 }
 for ( reg= 0; reg < nreg; reg++ ) {
  region_star_count[reg]= 0;
  region_n_tiles[reg]= 0;
 }

 // Image rows of one row of tiles plus one row above and one below (for the 3x3 neighbourhood)
 image_buf= (float *)malloc( ( max_tile_h + 2 ) * nx * sizeof( float ) );
 dark_buf= NULL;
 if ( dark_given == 1 ) {
  dark_buf= (float *)malloc( ( max_tile_h + 2 ) * nx * sizeof( float ) );
 }
 // The work buffer holds the pixels of one tile, and later the medians of all tiles
 work_size= max_tile_w * max_tile_h;
 if ( work_size < ntx * nty ) {
  work_size= ntx * nty;
 }
 work= (float *)malloc( work_size * sizeof( float ) );
 if ( image_buf == NULL || work == NULL || ( dark_given == 1 && dark_buf == NULL ) ) {
  fprintf( stderr, "ERROR: cannot allocate memory for the image buffers\n" );
  return DCR_EXIT_ERROR;
 }

 star_count= 0;
 n_valid_tiles= 0;
 n_tiles_with_stats= 0;
 n_tiles_equal_to_dark= 0;
 for ( j= 0; j < nty; j++ ) {
  // Read this row of tiles with one extra row on each side (border >= 1 keeps them inside the image)
  buf_first_row= tile_y_edge[j] - 1;
  buf_nrows= tile_y_edge[j + 1] - tile_y_edge[j] + 2;
  if ( 0 != read_image_rows( imagefptr, nx, buf_first_row, buf_nrows, image_buf ) ) {
   fprintf( stderr, "ERROR: cannot read the image %s\n", imagefilename );
   return DCR_EXIT_ERROR;
  }
  if ( dark_given == 1 ) {
   if ( 0 != read_image_rows( darkfptr, nx, buf_first_row, buf_nrows, dark_buf ) ) {
    fprintf( stderr, "ERROR: cannot read the dark frame %s\n", darkfilename );
    return DCR_EXIT_ERROR;
   }
   for ( k= 0; k < buf_nrows * nx; k++ ) {
    image_buf[k]-= dark_buf[k];
   }
  }

  // Background (median) and its scatter (MAD) in each tile of this row
  for ( i= 0; i < ntx; i++ ) {
   tile_index= j * ntx + i;
   n_valid= 0;
   for ( y= tile_y_edge[j]; y < tile_y_edge[j + 1]; y++ ) {
    row= y - buf_first_row;
    for ( x= tile_x_edge[i]; x < tile_x_edge[i + 1]; x++ ) {
     value= image_buf[row * nx + x];
     // skip NaN and Inf
     if ( value != value || value > 1.0e30 || value < -1.0e30 ) {
      continue;
     }
     work[n_valid]= value;
     n_valid++;
    }
   }
   tile_is_valid[tile_index]= 0;
   tile_median[tile_index]= 0.0;
   tile_center[tile_index]= 0.0;
   tile_sigma[tile_index]= sigma_floor;
   if ( (double)n_valid < DCR_MIN_VALID_PIXEL_FRACTION * (double)( ( tile_x_edge[i + 1] - tile_x_edge[i] ) * ( tile_y_edge[j + 1] - tile_y_edge[j] ) ) || n_valid < 3 ) {
    continue;
   }
   tile_median[tile_index]= median_of_float_array( work, n_valid );
   tile_center[tile_index]= tile_median[tile_index];
   folded_noise_rms= 0.0;
   if ( zero_level == DCR_ZERO_LEVEL_HEADER ) {
    // RMS around zero of the (folded) values, clipped to exclude stars and hot pixels
    clip_level= 5.0 * ( (double)tile_median[tile_index] > (double)sigma_floor ? (double)tile_median[tile_index] : (double)sigma_floor );
    sum_of_squares= 0.0;
    n_clipped= 0;
    for ( k= 0; k < n_valid; k++ ) {
     if ( (double)work[k] < clip_level ) {
      sum_of_squares+= (double)work[k] * (double)work[k];
      n_clipped++;
     }
    }
    if ( n_clipped > 0 ) {
     folded_noise_rms= sqrt( sum_of_squares / (double)n_clipped );
    }
   }
   for ( k= 0; k < n_valid; k++ ) {
    work[k]= (float)fabs( work[k] - tile_median[tile_index] );
   }
   tile_mad= median_of_float_array( work, n_valid );
   tile_sigma[tile_index]= (float)( DCR_MAD_TO_SIGMA * tile_mad );
   n_tiles_with_stats++;
   if ( zero_level == DCR_ZERO_LEVEL_DARK && tile_mad == 0.0 && tile_median[tile_index] == 0.0 ) {
    n_tiles_equal_to_dark++;
   }
   // util/ccd/ms writes |image - dark|, so where the background of a dark-subtracted image is
   // close to zero the noise is folded over at zero: the median and MAD then underestimate
   // the noise (and are coarsely quantized for small integer values), and folded noise peaks
   // would pass for stars. The true zero level is known in this case, so measure the noise
   // as the RMS around zero. (For folded pure noise median/sigma_MAD = 1.14; the ratio is 2
   // when the background is 2 sigma above zero and folding no longer matters.)
   if ( zero_level == DCR_ZERO_LEVEL_HEADER && tile_median[tile_index] < (float)DCR_FOLDED_NOISE_MEDIAN_TO_SIGMA * tile_sigma[tile_index] && folded_noise_rms > 0.0 ) {
    tile_center[tile_index]= 0.0;
    tile_sigma[tile_index]= (float)folded_noise_rms;
   }
   if ( bitpix > 0 ) {
    // integer data: the noise cannot be resolved below the quantization step
    if ( tile_sigma[tile_index] < sigma_floor ) {
     tile_sigma[tile_index]= sigma_floor;
    }
   } else if ( !( tile_sigma[tile_index] > 0.0 ) ) {
    // floating-point data with more than half of the pixels equal: a filled or masked area, not sky
    tile_sigma[tile_index]= sigma_floor;
    continue;
   }
   tile_is_valid[tile_index]= 1;
   n_valid_tiles++;
  }

  // Count star-like peaks in this row of tiles
  for ( y= tile_y_edge[j]; y < tile_y_edge[j + 1]; y++ ) {
   row= y - buf_first_row;
   row_above= image_buf + ( row - 1 ) * nx;
   row_this= image_buf + row * nx;
   row_below= image_buf + ( row + 1 ) * nx;
   for ( x= border; x < nx - border; x++ ) {
    tile_index= j * ntx + tile_of_x[x];
    if ( tile_is_valid[tile_index] == 0 ) {
     continue;
    }
    value= row_this[x];
    threshold_high= tile_center[tile_index] + (float)DCR_DETECTION_SIGMA * tile_sigma[tile_index];
    // this comparison is false for NaN
    if ( !( value > threshold_high ) ) {
     continue;
    }
    threshold_low= tile_center[tile_index] + (float)DCR_NEIGHBOUR_SIGMA * tile_sigma[tile_index];
    is_local_maximum= 1;
    n_bright_neighbours= 0;
    for ( dy= -1; dy <= 1; dy++ ) {
     for ( dx= -1; dx <= 1; dx++ ) {
      if ( dx == 0 && dy == 0 ) {
       continue;
      }
      if ( dy == -1 ) {
       neighbour= row_above[x + dx];
      } else if ( dy == 0 ) {
       neighbour= row_this[x + dx];
      } else {
       neighbour= row_below[x + dx];
      }
      if ( neighbour > value ) {
       is_local_maximum= 0;
      }
      // of several equal pixels at the top of a peak count only the first one in the raster order
      if ( neighbour == value && ( dy < 0 || ( dy == 0 && dx < 0 ) ) ) {
       is_local_maximum= 0;
      }
      if ( neighbour > threshold_low ) {
       n_bright_neighbours++;
      }
     }
    }
    if ( is_local_maximum == 1 && n_bright_neighbours >= DCR_MIN_BRIGHT_NEIGHBOURS ) {
     star_count++;
     reg_x= ( x - border ) * nreg_x / ( nx - 2 * border );
     reg_y= ( y - border ) * nreg_y / ( ny - 2 * border );
     if ( reg_x > nreg_x - 1 ) {
      reg_x= nreg_x - 1;
     }
     if ( reg_y > nreg_y - 1 ) {
      reg_y= nreg_y - 1;
     }
     region_star_count[reg_y * nreg_x + reg_x]++;
    }
   }
  }
 }
 fits_close_file( imagefptr, &status );
 status= 0;
 if ( dark_given == 1 ) {
  fits_close_file( darkfptr, &status );
  status= 0;
 }

 if ( n_valid_tiles == 0 ) {
  fprintf( stderr, "ERROR: no valid pixels in %s\n", imagefilename );
  return DCR_EXIT_ERROR;
 }
 // Every real exposure has read noise, so image - dark cannot be exactly zero almost everywhere
 if ( zero_level == DCR_ZERO_LEVEL_DARK && 2 * n_tiles_equal_to_dark > n_tiles_with_stats ) {
  fprintf( stderr, "ERROR: the image %s is identical to the dark frame %s\n", imagefilename, darkfilename );
  return DCR_EXIT_ERROR;
 }

 // Global background and noise: the median over the tiles
 n_valid= 0;
 for ( tile_index= 0; tile_index < ntx * nty; tile_index++ ) {
  if ( tile_is_valid[tile_index] == 1 ) {
   work[n_valid]= tile_median[tile_index];
   n_valid++;
  }
 }
 global_background= median_of_float_array( work, n_valid );
 n_valid= 0;
 for ( tile_index= 0; tile_index < ntx * nty; tile_index++ ) {
  if ( tile_is_valid[tile_index] == 1 ) {
   work[n_valid]= tile_sigma[tile_index];
   n_valid++;
  }
 }
 global_noise= median_of_float_array( work, n_valid );

 // Is the dark frame a usable zero level? Sky light only adds to the dark level, and images
 // taken with the roof closed sit within a few ADU of a matching dark and show only the read
 // noise. (1) An image background far below the dark level means that the dark frame does not
 // match the image (other gain, offset or readout mode, or another camera). (2) A background at
 // the dark level with much more noise than a frame without sky light can have points to the
 // same problem: a dark whose level happens to cancel the sky light of an overcast frame
 // (checked only for starless images: partly lit images mix dark and lit regions).
 // In both cases the dark frame cannot tell a closed roof from bright clouds.
 if ( zero_level == DCR_ZERO_LEVEL_DARK ) {
  mismatch_limit= DCR_MISMATCH_FRACTION_OF_SKY_LIMIT * max_sky_adu;
  if ( DCR_MISMATCH_NOISE_UNITS * (double)global_noise > mismatch_limit ) {
   mismatch_limit= DCR_MISMATCH_NOISE_UNITS * (double)global_noise;
  }
  if ( (double)global_background < -mismatch_limit ) {
   fprintf( stderr, "WARNING: the image background is %.1f ADU below the level of the dark frame %s - the dark frame does not match the image, so the background level cannot be checked\n", -(double)global_background, darkfilename );
   zero_level= DCR_ZERO_LEVEL_MISMATCH;
  } else if ( max_noise_adu > 0.0 && star_count < max_stars && (double)global_background < max_sky_adu && (double)global_noise >= max_noise_adu ) {
   fprintf( stderr, "WARNING: the image background is at the level of the dark frame %s, but the noise (%.1f ADU) is too high for an image without sky light (limit %.1lf ADU) - the dark frame does not match the image\n", darkfilename, (double)global_noise, max_noise_adu );
   zero_level= DCR_ZERO_LEVEL_MISMATCH;
  }
 }

 // Background of each region: the median over the tiles whose centres are in that region
 n_valid_regions= 0;
 n_dark_regions= 0;
 for ( reg= 0; reg < nreg; reg++ ) {
  n_valid= 0;
  for ( j= 0; j < nty; j++ ) {
   reg_y= ( ( tile_y_edge[j] + tile_y_edge[j + 1] ) / 2 - border ) * nreg_y / ( ny - 2 * border );
   if ( reg_y > nreg_y - 1 ) {
    reg_y= nreg_y - 1;
   }
   if ( reg_y != reg / nreg_x ) {
    continue;
   }
   for ( i= 0; i < ntx; i++ ) {
    reg_x= ( ( tile_x_edge[i] + tile_x_edge[i + 1] ) / 2 - border ) * nreg_x / ( nx - 2 * border );
    if ( reg_x > nreg_x - 1 ) {
     reg_x= nreg_x - 1;
    }
    if ( reg_x != reg % nreg_x ) {
     continue;
    }
    tile_index= j * ntx + i;
    if ( tile_is_valid[tile_index] == 1 ) {
     work[n_valid]= tile_median[tile_index];
     n_valid++;
    }
   }
  }
  region_n_tiles[reg]= n_valid;
  region_background[reg]= 0.0;
  if ( n_valid == 0 ) {
   continue;
  }
  region_background[reg]= median_of_float_array( work, n_valid );
  n_valid_regions++;
  if ( region_star_count[reg] < region_star_limit && (double)region_background[reg] < max_sky_adu ) {
   n_dark_regions++;
  }
 }

 // The verdict
 if ( star_count < max_stars ) {
  if ( ( zero_level == DCR_ZERO_LEVEL_DARK || zero_level == DCR_ZERO_LEVEL_HEADER ) && (double)global_background < max_sky_adu ) {
   verdict= "CLOSED_ROOF";
  } else {
   verdict= "NO_STARS";
  }
 } else if ( zero_level == DCR_ZERO_LEVEL_DARK && n_dark_regions > 0 ) {
  verdict= "PARTLY_DARK";
 } else {
  verdict= "OK";
 }
 if ( 0 == strcmp( verdict, "OK" ) ) {
  exit_code= DCR_EXIT_OK;
 } else {
  exit_code= DCR_EXIT_PROBLEM;
 }

 if ( exptime > 0.0 ) {
  snprintf( exptime_string, sizeof( exptime_string ), "%.3lf", exptime );
 } else {
  strcpy( exptime_string, "unknown" );
 }
 if ( zero_level != DCR_ZERO_LEVEL_NONE ) {
  snprintf( above_dark_string, sizeof( above_dark_string ), "%.1lf", (double)global_background );
 } else {
  strcpy( above_dark_string, "unknown" );
 }
 if ( zero_level == DCR_ZERO_LEVEL_DARK || zero_level == DCR_ZERO_LEVEL_HEADER ) {
  snprintf( dark_regions_string, sizeof( dark_regions_string ), "%ld/%ld", n_dark_regions, n_valid_regions );
 } else {
  strcpy( dark_regions_string, "unknown" );
 }

 if ( verbose == 1 ) {
  fprintf( stderr, "Image: %s (%ldx%ld pixels, BITPIX=%d, exposure %s s)\n", imagefilename, nx, ny, bitpix, exptime_string );
  if ( zero_level == DCR_ZERO_LEVEL_DARK ) {
   fprintf( stderr, "Dark frame: %s (exposure %.3lf s)\n", darkfilename, dark_exptime );
  } else if ( zero_level == DCR_ZERO_LEVEL_MISMATCH ) {
   fprintf( stderr, "Dark frame: %s (exposure %.3lf s) does not match the image\n", darkfilename, dark_exptime );
  } else if ( zero_level == DCR_ZERO_LEVEL_HEADER ) {
   fprintf( stderr, "Dark frame: none needed, the image has been dark-subtracted already\n" );
  } else {
   fprintf( stderr, "Dark frame: none, the dark level is unknown\n" );
  }
  fprintf( stderr, "Tiles: %ldx%ld (%ld valid), border %ld pixels, regions %ldx%ld\n", ntx, nty, n_valid_tiles, border, nreg_x, nreg_y );
  if ( zero_level != DCR_ZERO_LEVEL_NONE ) {
   fprintf( stderr, "Background above the dark level: %.1f ADU (limit %.1lf ADU)\n", global_background, max_sky_adu );
  } else {
   fprintf( stderr, "Background: %.1f ADU (the dark level is unknown)\n", global_background );
  }
  fprintf( stderr, "Noise: %.1f ADU\n", global_noise );
  fprintf( stderr, "Star-like peaks: %ld (an image with fewer than %d has no stars)\n", star_count, max_stars );
  fprintf( stderr, "Regions (stars, background%s):\n", ( zero_level != DCR_ZERO_LEVEL_NONE ) ? " above the dark level" : "" );
  for ( reg_y= nreg_y - 1; reg_y >= 0; reg_y-- ) {
   for ( reg_x= 0; reg_x < nreg_x; reg_x++ ) {
    reg= reg_y * nreg_x + reg_x;
    if ( region_n_tiles[reg] > 0 ) {
     fprintf( stderr, "  %7ld %8.1f", region_star_count[reg], region_background[reg] );
    } else {
     fprintf( stderr, "  %7ld %8s", region_star_count[reg], "-" );
    }
   }
   fprintf( stderr, "\n" );
  }
  fprintf( stderr, "Processing time: %.2lf s\n", (double)( clock() - start_clock ) / (double)CLOCKS_PER_SEC );
 }

 fprintf( stdout, "%s stars=%ld max_stars=%d above_dark=%s max_above_dark=%.1lf zero_level=%s noise=%.1f dark_regions=%s exptime=%s image=%s",
          verdict, star_count, max_stars, above_dark_string, max_sky_adu,
          ( zero_level == DCR_ZERO_LEVEL_DARK ) ? "dark" : ( ( zero_level == DCR_ZERO_LEVEL_HEADER ) ? "header" : ( ( zero_level == DCR_ZERO_LEVEL_MISMATCH ) ? "mismatch" : "none" ) ),
          global_noise, dark_regions_string, exptime_string, image_basename );
 if ( dark_given == 1 && dark_basename != NULL ) {
  fprintf( stdout, " dark=%s", dark_basename );
 }
 fprintf( stdout, "\n" );

 free( tile_x_edge );
 free( tile_y_edge );
 free( tile_of_x );
 free( tile_median );
 free( tile_center );
 free( tile_sigma );
 free( tile_is_valid );
 free( region_star_count );
 free( region_n_tiles );
 free( region_background );
 free( image_buf );
 if ( dark_buf != NULL ) {
  free( dark_buf );
 }
 free( work );

 return exit_code;
}
