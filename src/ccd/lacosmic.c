/*
 * L.A.Cosmic - Laplacian Cosmic Ray Identification
 *
 * Implementation based on:
 * van Dokkum, P. G. 2001, PASP, 113, 1420
 * "Cosmic-Ray Rejection by Laplacian Edge Detection"
 *
 * This program identifies and removes cosmic rays from astronomical
 * images using Laplacian edge detection.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <unistd.h>
#include <getopt.h>
#include <libgen.h>
#include <errno.h>

#include <gsl/gsl_sort_float.h>

/* OpenMP support - only enabled if VAST_ENABLE_OPENMP is defined and compiler supports it */
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#include <omp.h>
#endif
#endif

#include "../fitsio.h"

/* Default parameters - conservative settings to preserve faint stars */
#define DEFAULT_GAIN 1.0f
#define DEFAULT_READNOISE 10.0f
#define DEFAULT_CONTRAST 15.0f
#define DEFAULT_CR_THRESHOLD 5.0f
#define DEFAULT_NEIGHBOR_THRESHOLD 2.0f
#define DEFAULT_MAXITER 2

/* Function prototypes */
static void print_usage( const char *prog_name );
static int read_fits_image( const char *filename, float **data, long *naxes,
                            char ***header_keys, int *num_keys, int *bitpix );
static int write_fits_image( const char *filename, float *data, long *naxes,
                             char **header_keys, int num_keys, int bitpix,
                             float gain, float readnoise, float contrast,
                             float cr_threshold, float neighbor_threshold,
                             int total_cr );
static int write_fits_mask( const char *filename, unsigned char *mask, long *naxes );
static void check_and_remove_file( const char *filename );

/* Core algorithm functions */
static long mirror_index( long i, long max );
static void block_replicate_2x( const float *input, float *output, long width, long height );
static void block_reduce_2x( const float *input, float *output, long width, long height );
static void laplacian_filter( const float *input, float *output, long width, long height );
static void median_filter( const float *input, float *output, long width, long height,
                           int filter_size, float *work_buffer );
static void compute_noise_model( const float *median5_image, float *noise,
                                 long width, long height, float gain, float readnoise );
static void binary_dilate_3x3( const unsigned char *input, unsigned char *output,
                               long width, long height );
static void clean_masked_pixels( float *image, const unsigned char *mask,
                                 long width, long height, float *work_buffer );
static int lacosmic_process( float *image, unsigned char *crmask, long width, long height,
                             float gain, float readnoise, float contrast,
                             float cr_threshold, float neighbor_threshold, int maxiter );

/* Command-line options */
static struct option long_options[]= {
    { "gain", required_argument, 0, 'g' },
    { "readnoise", required_argument, 0, 'r' },
    { "contrast", required_argument, 0, 'c' },
    { "sigma", required_argument, 0, 's' },
    { "neighbor", required_argument, 0, 'n' },
    { "maxiter", required_argument, 0, 'i' },
    { "mask", required_argument, 0, 'm' },
    { "help", no_argument, 0, 'h' },
    { 0, 0, 0, 0 } };

static void print_usage( const char *prog_name ) {
 fprintf( stderr, "\nL.A.Cosmic - Laplacian Cosmic Ray Identification\n" );
 fprintf( stderr, "Based on van Dokkum (2001, PASP 113, 1420)\n\n" );
 fprintf( stderr, "Usage: %s [OPTIONS] input.fits [output.fits]\n\n", prog_name );
 fprintf( stderr, "Options:\n" );
 fprintf( stderr, "  -g, --gain FLOAT      Effective gain in e-/ADU (default: %.1f)\n", DEFAULT_GAIN );
 fprintf( stderr, "  -r, --readnoise FLOAT Read noise in electrons (default: %.1f)\n", DEFAULT_READNOISE );
 fprintf( stderr, "  -c, --contrast FLOAT  Contrast threshold f_lim (default: %.1f)\n", DEFAULT_CONTRAST );
 fprintf( stderr, "                        Higher values preserve faint stars better\n" );
 fprintf( stderr, "  -s, --sigma FLOAT     CR detection threshold (default: %.1f)\n", DEFAULT_CR_THRESHOLD );
 fprintf( stderr, "  -n, --neighbor FLOAT  Neighbor detection threshold (default: %.1f)\n", DEFAULT_NEIGHBOR_THRESHOLD );
 fprintf( stderr, "  -i, --maxiter INT     Maximum iterations (default: %d)\n", DEFAULT_MAXITER );
 fprintf( stderr, "  -m, --mask FILE       Output cosmic ray mask to FILE\n" );
 fprintf( stderr, "  -h, --help            Show this help message\n\n" );
 fprintf( stderr, "If output.fits is not specified, 'lacosmic_cleaned.fits' is used.\n\n" );
}

static void check_and_remove_file( const char *filename ) {
 if ( unlink( filename ) == 0 ) {
  fprintf( stderr, "WARNING: existing file %s was deleted\n", filename );
 } else if ( errno != ENOENT ) {
  fprintf( stderr, "ERROR: could not delete existing file %s\n", filename );
 }
}

/* Mirror boundary index handling */
static long mirror_index( long i, long max ) {
 if ( i < 0 )
  return -i - 1;
 if ( i >= max )
  return 2 * max - i - 1;
 return i;
}

/* Block replicate: upsample image by factor 2 */
static void block_replicate_2x( const float *input, float *output, long width, long height ) {
 long x, y;
 long new_width= 2 * width;
 float val;

 for ( y= 0; y < height; y++ ) {
  for ( x= 0; x < width; x++ ) {
   val= input[y * width + x];
   output[( 2 * y ) * new_width + ( 2 * x )]= val;
   output[( 2 * y ) * new_width + ( 2 * x + 1 )]= val;
   output[( 2 * y + 1 ) * new_width + ( 2 * x )]= val;
   output[( 2 * y + 1 ) * new_width + ( 2 * x + 1 )]= val;
  }
 }
}

/* Block reduce: downsample image by factor 2 (average 2x2 blocks) */
static void block_reduce_2x( const float *input, float *output, long width, long height ) {
 long x, y;
 long in_width= 2 * width;
 float sum;

 for ( y= 0; y < height; y++ ) {
  for ( x= 0; x < width; x++ ) {
   sum= input[( 2 * y ) * in_width + ( 2 * x )];
   sum+= input[( 2 * y ) * in_width + ( 2 * x + 1 )];
   sum+= input[( 2 * y + 1 ) * in_width + ( 2 * x )];
   sum+= input[( 2 * y + 1 ) * in_width + ( 2 * x + 1 )];
   output[y * width + x]= sum / 4.0f;
  }
 }
}

/* Laplacian filter with mirrored boundaries and negative clipping */
static void laplacian_filter( const float *input, float *output, long width, long height ) {
 long x, y;
 long x0, x1, y0, y1;
 float val;

 for ( y= 0; y < height; y++ ) {
  for ( x= 0; x < width; x++ ) {
   y0= mirror_index( y - 1, height );
   y1= mirror_index( y + 1, height );
   x0= mirror_index( x - 1, width );
   x1= mirror_index( x + 1, width );

   /* Laplacian kernel: [[0,-1,0],[-1,4,-1],[0,-1,0]] / 4 */
   val= 4.0f * input[y * width + x] - input[y0 * width + x] - input[y1 * width + x] - input[y * width + x0] - input[y * width + x1];
   val/= 4.0f;

   /* Clip negative values (L^{2+}) */
   output[y * width + x]= ( val > 0.0f ) ? val : 0.0f;
  }
 }
}

/* Quickselect partition: rearrange so elements < pivot are left, > pivot are right */
static int quickselect_partition( float *arr, int left, int right, int pivot_idx ) {
 float pivot_val= arr[pivot_idx];
 float tmp;
 int store_idx, i;

 /* Move pivot to end */
 tmp= arr[pivot_idx];
 arr[pivot_idx]= arr[right];
 arr[right]= tmp;

 store_idx= left;
 for ( i= left; i < right; i++ ) {
  if ( arr[i] < pivot_val ) {
   tmp= arr[store_idx];
   arr[store_idx]= arr[i];
   arr[i]= tmp;
   store_idx++;
  }
 }

 /* Move pivot to its final place */
 tmp= arr[store_idx];
 arr[store_idx]= arr[right];
 arr[right]= tmp;

 return store_idx;
}

/* Quickselect: find k-th smallest element in O(n) average time */
static float quickselect( float *arr, int left, int right, int k ) {
 int pivot_idx, pivot_new_idx;

 while ( left < right ) {
  /* Choose middle element as pivot for better average performance */
  pivot_idx= left + ( right - left ) / 2;
  pivot_new_idx= quickselect_partition( arr, left, right, pivot_idx );

  if ( k == pivot_new_idx ) {
   return arr[k];
  } else if ( k < pivot_new_idx ) {
   right= pivot_new_idx - 1;
  } else {
   left= pivot_new_idx + 1;
  }
 }
 return arr[left];
}

/* Find median of n floats using quickselect - O(n) average time */
static float median_of_n( float *arr, int n ) {
 if ( n % 2 == 1 ) {
  return quickselect( arr, 0, n - 1, n / 2 );
 } else {
  /* For even n, find both middle elements */
  float lower= quickselect( arr, 0, n - 1, n / 2 - 1 );
  float upper= quickselect( arr, 0, n - 1, n / 2 );
  return 0.5f * ( lower + upper );
 }
}

/* Generic NxN median filter with mirrored boundaries */
static void median_filter( const float *input, float *output, long width, long height,
                           int filter_size, float *work_buffer ) {
 int half= filter_size / 2;
 long x, y;
 int i, j, idx;
 long xi, yi;
 int window_size= filter_size * filter_size;
 int is_interior;

#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel private( x, i, j, idx, xi, yi, is_interior )
 {
  /* Each thread gets its own work buffer */
  float *thread_work_buffer= malloc( window_size * sizeof( float ) );
  if ( thread_work_buffer != NULL ) {
#pragma omp for
   for ( y= 0; y < height; y++ ) {
    for ( x= 0; x < width; x++ ) {
     idx= 0;
     /* Check if this pixel is in the interior (no boundary issues) */
     is_interior= ( y >= half && y < height - half && x >= half && x < width - half );
     if ( is_interior ) {
      /* Fast path: no boundary checks needed */
      for ( j= -half; j <= half; j++ ) {
       for ( i= -half; i <= half; i++ ) {
        thread_work_buffer[idx++]= input[( y + j ) * width + ( x + i )];
       }
      }
     } else {
      /* Slow path: need mirror boundary handling */
      for ( j= -half; j <= half; j++ ) {
       for ( i= -half; i <= half; i++ ) {
        yi= mirror_index( y + j, height );
        xi= mirror_index( x + i, width );
        thread_work_buffer[idx++]= input[yi * width + xi];
       }
      }
     }
     output[y * width + x]= median_of_n( thread_work_buffer, window_size );
    }
   }
   free( thread_work_buffer );
  }
 }
#else
 /* Non-OpenMP fallback */
 for ( y= 0; y < height; y++ ) {
  for ( x= 0; x < width; x++ ) {
   idx= 0;
   is_interior= ( y >= half && y < height - half && x >= half && x < width - half );
   if ( is_interior ) {
    for ( j= -half; j <= half; j++ ) {
     for ( i= -half; i <= half; i++ ) {
      work_buffer[idx++]= input[( y + j ) * width + ( x + i )];
     }
    }
   } else {
    for ( j= -half; j <= half; j++ ) {
     for ( i= -half; i <= half; i++ ) {
      yi= mirror_index( y + j, height );
      xi= mirror_index( x + i, width );
      work_buffer[idx++]= input[yi * width + xi];
     }
    }
   }
   output[y * width + x]= median_of_n( work_buffer, window_size );
  }
 }
#endif
#else
 /* Non-OpenMP fallback */
 for ( y= 0; y < height; y++ ) {
  for ( x= 0; x < width; x++ ) {
   idx= 0;
   is_interior= ( y >= half && y < height - half && x >= half && x < width - half );
   if ( is_interior ) {
    for ( j= -half; j <= half; j++ ) {
     for ( i= -half; i <= half; i++ ) {
      work_buffer[idx++]= input[( y + j ) * width + ( x + i )];
     }
    }
   } else {
    for ( j= -half; j <= half; j++ ) {
     for ( i= -half; i <= half; i++ ) {
      yi= mirror_index( y + j, height );
      xi= mirror_index( x + i, width );
      work_buffer[idx++]= input[yi * width + xi];
     }
    }
   }
   output[y * width + x]= median_of_n( work_buffer, window_size );
  }
 }
#endif
}

/* Compute noise model: N = sqrt(gain * median5(I) + readnoise^2) / gain */
static void compute_noise_model( const float *median5_image, float *noise,
                                 long width, long height, float gain, float readnoise ) {
 long i;
 long npix= width * height;
 float med_val, variance;
 float readnoise_sq= readnoise * readnoise;

 for ( i= 0; i < npix; i++ ) {
  med_val= median5_image[i];
  if ( med_val < 1.0e-5f )
   med_val= 1.0e-5f;
  variance= gain * med_val + readnoise_sq;
  noise[i]= sqrtf( variance ) / gain;
 }
}

/* Binary dilation with 3x3 structuring element */
static void binary_dilate_3x3( const unsigned char *input, unsigned char *output,
                               long width, long height ) {
 long x, y;
 int i, j;
 long xi, yi;
 unsigned char val;

 for ( y= 0; y < height; y++ ) {
  for ( x= 0; x < width; x++ ) {
   val= 0;
   for ( j= -1; j <= 1 && !val; j++ ) {
    for ( i= -1; i <= 1 && !val; i++ ) {
     yi= y + j;
     xi= x + i;
     if ( yi >= 0 && yi < height && xi >= 0 && xi < width ) {
      if ( input[yi * width + xi] ) {
       val= 1;
      }
     }
    }
   }
   output[y * width + x]= val;
  }
 }
}

/* Replace masked pixels with local median of unmasked neighbors */
static void clean_masked_pixels( float *image, const unsigned char *mask,
                                 long width, long height, float *work_buffer ) {
 long x, y;
 int half, size;
 int i, j, idx;
 long xi, yi;
 float median_val;
 long npix= width * height;
 long p;

 for ( p= 0; p < npix; p++ ) {
  if ( !mask[p] )
   continue;

  y= p / width;
  x= p % width;

  /* Start with 5x5 window, expand if needed */
  for ( size= 5; size <= 21; size+= 2 ) {
   half= size / 2;
   idx= 0;

   for ( j= -half; j <= half; j++ ) {
    for ( i= -half; i <= half; i++ ) {
     yi= y + j;
     xi= x + i;
     if ( yi >= 0 && yi < height && xi >= 0 && xi < width ) {
      if ( !mask[yi * width + xi] ) {
       work_buffer[idx++]= image[yi * width + xi];
      }
     }
    }
   }

   if ( idx > 0 ) {
    median_val= median_of_n( work_buffer, idx );
    image[p]= median_val;
    break;
   }
  }
 }
}

/* Main L.A.Cosmic processing function */
static int lacosmic_process( float *image, unsigned char *crmask, long width, long height,
                             float gain, float readnoise, float contrast,
                             float cr_threshold, float neighbor_threshold, int maxiter ) {
 long npix= width * height;
 long npix_2x= 4 * npix;
 long i;
 int iter;
 int total_cr= 0;
 int new_cr;

 /* Allocate working arrays */
 float *upsampled= malloc( npix_2x * sizeof( float ) );
 float *laplacian= malloc( npix * sizeof( float ) );
 float *med5_img= malloc( npix * sizeof( float ) );
 float *noise= malloc( npix * sizeof( float ) );
 float *snr= malloc( npix * sizeof( float ) );
 float *snr_medsub= malloc( npix * sizeof( float ) );
 float *med3_img= malloc( npix * sizeof( float ) );
 float *med7_img= malloc( npix * sizeof( float ) );
 float *fine_struct= malloc( npix * sizeof( float ) );
 unsigned char *iter_mask= malloc( npix * sizeof( unsigned char ) );
 unsigned char *dilated= malloc( npix * sizeof( unsigned char ) );
 float *work_buffer= malloc( 441 * sizeof( float ) ); /* For up to 21x21 window in cleaning */

 /* Check allocations */
 if ( !upsampled || !laplacian || !med5_img || !noise || !snr ||
      !snr_medsub || !med3_img || !med7_img || !fine_struct ||
      !iter_mask || !dilated || !work_buffer ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for working arrays in lacosmic_process()\n" );
  free( upsampled );
  free( laplacian );
  free( med5_img );
  free( noise );
  free( snr );
  free( snr_medsub );
  free( med3_img );
  free( med7_img );
  free( fine_struct );
  free( iter_mask );
  free( dilated );
  free( work_buffer );
  return -1;
 }

 /* Initialize cosmic ray mask */
 memset( crmask, 0, npix * sizeof( unsigned char ) );

 for ( iter= 0; iter < maxiter; iter++ ) {
  /* Step 1: Block replicate 2x */
  block_replicate_2x( image, upsampled, width, height );

  /* Step 2: Laplacian convolution (on 2x image) + clip negatives */
  laplacian_filter( upsampled, upsampled, 2 * width, 2 * height );

  /* Step 3: Block reduce back to original size */
  block_reduce_2x( upsampled, laplacian, width, height );

  /* Step 4: Compute noise model N = sqrt(g*med5(I) + rn^2) / g */
  median_filter( image, med5_img, width, height, 5, work_buffer );
  compute_noise_model( med5_img, noise, width, height, gain, readnoise );

  /* Step 5: SNR image S = L+ / (2 * N) */
  for ( i= 0; i < npix; i++ ) {
   snr[i]= laplacian[i] / ( 2.0f * noise[i] );
  }

  /* Step 6: Remove extended structure S' = S - med5(S) */
  median_filter( snr, snr_medsub, width, height, 5, work_buffer );
  for ( i= 0; i < npix; i++ ) {
   snr_medsub[i]= snr[i] - snr_medsub[i];
  }

  /* Step 7: Fine structure F = (med3(I) - med7(med3(I))) / N */
  median_filter( image, med3_img, width, height, 3, work_buffer );
  median_filter( med3_img, med7_img, width, height, 7, work_buffer );
  for ( i= 0; i < npix; i++ ) {
   float f= ( med3_img[i] - med7_img[i] ) / noise[i];
   fine_struct[i]= ( f > 0.01f ) ? f : 0.01f;
  }

  /* Step 8: Detection masks */
  /* cr_mask1: S' > cr_threshold */
  /* cr_mask2: S'/F > contrast */
  for ( i= 0; i < npix; i++ ) {
   int cond1= ( snr_medsub[i] > cr_threshold );
   int cond2= ( ( snr_medsub[i] / fine_struct[i] ) > contrast );
   iter_mask[i]= ( cond1 && cond2 ) ? 1 : 0;
  }

  /* Step 9: Grow mask and apply neighbor threshold */
  /* First dilation */
  binary_dilate_3x3( iter_mask, dilated, width, height );
  for ( i= 0; i < npix; i++ ) {
   iter_mask[i]= ( snr_medsub[i] > cr_threshold ) && dilated[i];
  }
  /* Second dilation with lower threshold */
  binary_dilate_3x3( iter_mask, dilated, width, height );
  for ( i= 0; i < npix; i++ ) {
   iter_mask[i]= ( snr_medsub[i] > neighbor_threshold ) && dilated[i];
  }

  /* Step 10: Count new cosmic rays */
  new_cr= 0;
  for ( i= 0; i < npix; i++ ) {
   if ( iter_mask[i] && !crmask[i] ) {
    new_cr++;
    crmask[i]= 1;
   }
  }
  total_cr+= new_cr;

  fprintf( stderr, "Iteration %d: Found %d new cosmic rays (total: %d)\n",
           iter + 1, new_cr, total_cr );

  if ( new_cr == 0 )
   break;

  /* Step 11: Clean masked pixels */
  clean_masked_pixels( image, crmask, width, height, work_buffer );
 }

 /* Free working arrays */
 free( upsampled );
 free( laplacian );
 free( med5_img );
 free( noise );
 free( snr );
 free( snr_medsub );
 free( med3_img );
 free( med7_img );
 free( fine_struct );
 free( iter_mask );
 free( dilated );
 free( work_buffer );

 return total_cr;
}

/* Read FITS image into float array */
static int read_fits_image( const char *filename, float **data, long *naxes,
                            char ***header_keys, int *num_keys, int *out_bitpix ) {
 fitsfile *fptr;
 int status= 0;
 int naxis;
 int bitpix;
 long npixels;
 int anynul= 0;
 int ii, j;
 int keys_left;

 fits_open_file( &fptr, filename, READONLY, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  return status;
 }

 /* Get image dimensions */
 fits_get_img_dim( fptr, &naxis, &status );
 if ( status != 0 || naxis != 2 ) {
  fprintf( stderr, "ERROR: Image must be 2D (NAXIS=%d)\n", naxis );
  fits_close_file( fptr, &status );
  return -1;
 }

 fits_read_key( fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status );
 fits_read_key( fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  fits_close_file( fptr, &status );
  return status;
 }

 fits_get_img_type( fptr, &bitpix, &status );
 *out_bitpix= bitpix;
 fprintf( stderr, "Reading %s: %ld x %ld pixels, BITPIX=%d\n",
          filename, naxes[0], naxes[1], bitpix );

 npixels= naxes[0] * naxes[1];
 if ( npixels <= 0 ) {
  fprintf( stderr, "ERROR: Invalid image dimensions\n" );
  fits_close_file( fptr, &status );
  return -1;
 }

 /* Allocate memory for image data */
 *data= malloc( npixels * sizeof( float ) );
 if ( *data == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for image data\n" );
  fits_close_file( fptr, &status );
  return -1;
 }

 /* Read image data as float */
 fits_read_img( fptr, TFLOAT, 1, npixels, NULL, *data, &anynul, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  free( *data );
  fits_close_file( fptr, &status );
  return status;
 }

 /* Read header keywords */
 fits_get_hdrspace( fptr, num_keys, &keys_left, &status );
 ( *num_keys )++; /* Extra for safety */

 *header_keys= malloc( *num_keys * sizeof( char * ) );
 if ( *header_keys == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for header keys\n" );
  free( *data );
  fits_close_file( fptr, &status );
  return -1;
 }

 for ( ii= 0; ii < *num_keys; ii++ ) {
  ( *header_keys )[ii]= malloc( FLEN_CARD * sizeof( char ) );
  if ( ( *header_keys )[ii] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for header key %d\n", ii );
   /* Free previously allocated */
   for ( j= 0; j < ii; j++ )
    free( ( *header_keys )[j] );
   free( *header_keys );
   free( *data );
   fits_close_file( fptr, &status );
   return -1;
  }
  fits_read_record( fptr, ii, ( *header_keys )[ii], &status );
  status= 0; /* Continue on errors */
 }

 fits_close_file( fptr, &status );
 return 0;
}

/* Check if a header record is a structural keyword that should be skipped */
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

/* Write FITS image from float array, preserving original BITPIX format */
static int write_fits_image( const char *filename, float *data, long *naxes,
                             char **header_keys, int num_keys, int bitpix,
                             float gain, float readnoise, float contrast,
                             float cr_threshold, float neighbor_threshold,
                             int total_cr ) {
 fitsfile *fptr;
 int status= 0;
 long npixels= naxes[0] * naxes[1];
 long i;
 int ii;
 char history[FLEN_CARD];
 int output_bitpix;

 /* For integer output, we need to clip values and convert */
 unsigned short *ushort_data= NULL;
 unsigned char *byte_data= NULL;
 int *int_data= NULL;
 double *double_data= NULL;

 check_and_remove_file( filename );

 fits_create_file( &fptr, filename, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  return status;
 }

 /* Determine output image type based on input BITPIX */
 switch ( bitpix ) {
 case BYTE_IMG: /* 8 */
  output_bitpix= BYTE_IMG;
  break;
 case SHORT_IMG: /* 16 */
  output_bitpix= SHORT_IMG;
  break;
 case LONG_IMG: /* 32 */
  output_bitpix= LONG_IMG;
  break;
 case FLOAT_IMG: /* -32 */
  output_bitpix= FLOAT_IMG;
  break;
 case DOUBLE_IMG: /* -64 */
  output_bitpix= DOUBLE_IMG;
  break;
 default:
  /* Default to same as input, or float if unknown */
  output_bitpix= bitpix;
  break;
 }

 fits_create_img( fptr, output_bitpix, 2, naxes, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  fits_close_file( fptr, &status );
  return status;
 }

 /* Write data with appropriate type conversion */
 switch ( output_bitpix ) {
 case BYTE_IMG:
  byte_data= malloc( npixels * sizeof( unsigned char ) );
  if ( byte_data == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for output conversion\n" );
   fits_close_file( fptr, &status );
   return -1;
  }
  for ( i= 0; i < npixels; i++ ) {
   float val= data[i];
   if ( val < 0.0f )
    val= 0.0f;
   if ( val > 255.0f )
    val= 255.0f;
   byte_data[i]= (unsigned char)( val + 0.5f );
  }
  fits_write_img( fptr, TBYTE, 1, npixels, byte_data, &status );
  free( byte_data );
  break;

 case SHORT_IMG:
  /* For 16-bit unsigned output, we need to set BZERO=32768 and convert manually */
  {
   short *short_data;
   double bzero_val= 32768.0;
   double bscale_val= 1.0;

   short_data= malloc( npixels * sizeof( short ) );
   if ( short_data == NULL ) {
    fprintf( stderr, "ERROR: Couldn't allocate memory for output conversion\n" );
    fits_close_file( fptr, &status );
    return -1;
   }

   /* Set BZERO and BSCALE for unsigned 16-bit representation */
   fits_update_key( fptr, TDOUBLE, "BZERO", &bzero_val, "offset for unsigned 16-bit", &status );
   fits_update_key( fptr, TDOUBLE, "BSCALE", &bscale_val, "scale factor", &status );

   /* Convert float to signed short: stored = physical - BZERO */
   for ( i= 0; i < npixels; i++ ) {
    float val= data[i];
    /* Clip to valid unsigned 16-bit range */
    if ( val < 1.0f )
     val= 1.0f; /* Avoid 0 to not confuse VaST flag image */
    if ( val > 65534.0f )
     val= 65534.0f;
    /* Convert physical value to stored value */
    short_data[i]= (short)( val - 32768.0f + 0.5f );
   }

   /* Tell CFITSIO not to apply scaling when writing (we already did it) */
   fits_set_bscale( fptr, 1.0, 0.0, &status );
   fits_write_img( fptr, TSHORT, 1, npixels, short_data, &status );
   /* Restore proper BZERO for reading */
   fits_set_bscale( fptr, 1.0, 32768.0, &status );

   free( short_data );
  }
  break;

 case LONG_IMG:
  int_data= malloc( npixels * sizeof( int ) );
  if ( int_data == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for output conversion\n" );
   fits_close_file( fptr, &status );
   return -1;
  }
  for ( i= 0; i < npixels; i++ ) {
   int_data[i]= (int)( data[i] + 0.5f );
  }
  fits_write_img( fptr, TINT, 1, npixels, int_data, &status );
  free( int_data );
  break;

 case DOUBLE_IMG:
  double_data= malloc( npixels * sizeof( double ) );
  if ( double_data == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for output conversion\n" );
   fits_close_file( fptr, &status );
   return -1;
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
  return status;
 }

 /* Write original header keywords, skipping structural ones */
 for ( ii= 1; ii < num_keys; ii++ ) {
  if ( !is_structural_keyword( header_keys[ii] ) ) {
   fits_write_record( fptr, header_keys[ii], &status );
   status= 0; /* Continue on errors */
  }
 }

 /* Add processing history */
 fits_write_history( fptr, "L.A.Cosmic cosmic ray rejection (van Dokkum 2001)", &status );
 snprintf( history, FLEN_CARD, "Parameters: gain=%.2f readnoise=%.2f contrast=%.2f",
           gain, readnoise, contrast );
 fits_write_history( fptr, history, &status );
 snprintf( history, FLEN_CARD, "Parameters: cr_threshold=%.2f neighbor_threshold=%.2f",
           cr_threshold, neighbor_threshold );
 fits_write_history( fptr, history, &status );
 snprintf( history, FLEN_CARD, "Total cosmic ray pixels removed: %d", total_cr );
 fits_write_history( fptr, history, &status );

 fits_close_file( fptr, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  return status;
 }

 return 0;
}

/* Write cosmic ray mask as FITS image */
static int write_fits_mask( const char *filename, unsigned char *mask, long *naxes ) {
 fitsfile *fptr;
 int status= 0;
 long npixels= naxes[0] * naxes[1];

 check_and_remove_file( filename );

 fits_create_file( &fptr, filename, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  return status;
 }

 fits_create_img( fptr, BYTE_IMG, 2, naxes, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  fits_close_file( fptr, &status );
  return status;
 }

 fits_write_img( fptr, TBYTE, 1, npixels, mask, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  fits_close_file( fptr, &status );
  return status;
 }

 fits_write_history( fptr, "L.A.Cosmic cosmic ray mask", &status );
 fits_write_history( fptr, "1 = cosmic ray pixel, 0 = good pixel", &status );

 fits_close_file( fptr, &status );
 if ( status != 0 ) {
  fits_report_error( stderr, status );
  return status;
 }

 return 0;
}

int main( int argc, char *argv[] ) {
 int opt;
 int option_index= 0;

 /* Parameters with defaults */
 float gain= DEFAULT_GAIN;
 float readnoise= DEFAULT_READNOISE;
 float contrast= DEFAULT_CONTRAST;
 float cr_threshold= DEFAULT_CR_THRESHOLD;
 float neighbor_threshold= DEFAULT_NEIGHBOR_THRESHOLD;
 int maxiter= DEFAULT_MAXITER;
 char *mask_file= NULL;

 /* File names */
 const char *input_file;
 const char *output_file= "lacosmic_cleaned.fits";

 /* Image data */
 float *image_data= NULL;
 unsigned char *crmask= NULL;
 long naxes[2];
 char **header_keys= NULL;
 int num_keys= 0;
 int bitpix= FLOAT_IMG; /* Will be set by read_fits_image */

 int total_cr;
 int result;
 int ii;

 /* Parse command-line options */
 while ( ( opt= getopt_long( argc, argv, "g:r:c:s:n:i:m:h", long_options, &option_index ) ) != -1 ) {
  switch ( opt ) {
  case 'g':
   gain= (float)atof( optarg );
   if ( gain <= 0 ) {
    fprintf( stderr, "ERROR: gain must be positive\n" );
    return EXIT_FAILURE;
   }
   break;
  case 'r':
   readnoise= (float)atof( optarg );
   if ( readnoise < 0 ) {
    fprintf( stderr, "ERROR: readnoise must be non-negative\n" );
    return EXIT_FAILURE;
   }
   break;
  case 'c':
   contrast= (float)atof( optarg );
   if ( contrast <= 0 ) {
    fprintf( stderr, "ERROR: contrast must be positive\n" );
    return EXIT_FAILURE;
   }
   break;
  case 's':
   cr_threshold= (float)atof( optarg );
   if ( cr_threshold <= 0 ) {
    fprintf( stderr, "ERROR: sigma threshold must be positive\n" );
    return EXIT_FAILURE;
   }
   break;
  case 'n':
   neighbor_threshold= (float)atof( optarg );
   if ( neighbor_threshold < 0 ) {
    fprintf( stderr, "ERROR: neighbor threshold must be non-negative\n" );
    return EXIT_FAILURE;
   }
   break;
  case 'i':
   maxiter= atoi( optarg );
   if ( maxiter <= 0 ) {
    fprintf( stderr, "ERROR: maxiter must be positive\n" );
    return EXIT_FAILURE;
   }
   break;
  case 'm':
   mask_file= optarg;
   break;
  case 'h':
   print_usage( argv[0] );
   return EXIT_SUCCESS;
  default:
   print_usage( argv[0] );
   return EXIT_FAILURE;
  }
 }

 /* Check for required arguments */
 if ( optind >= argc ) {
  fprintf( stderr, "ERROR: No input file specified\n" );
  print_usage( argv[0] );
  return EXIT_FAILURE;
 }

 input_file= argv[optind];
 if ( optind + 1 < argc ) {
  output_file= argv[optind + 1];
 }

 fprintf( stderr, "\nL.A.Cosmic - Laplacian Cosmic Ray Identification\n" );
 fprintf( stderr, "================================================\n" );
 fprintf( stderr, "Input:  %s\n", input_file );
 fprintf( stderr, "Output: %s\n", output_file );
 if ( mask_file ) {
  fprintf( stderr, "Mask:   %s\n", mask_file );
 }
 fprintf( stderr, "\nParameters:\n" );
 fprintf( stderr, "  gain         = %.2f e-/ADU\n", gain );
 fprintf( stderr, "  readnoise    = %.2f e-\n", readnoise );
 fprintf( stderr, "  contrast     = %.2f\n", contrast );
 fprintf( stderr, "  cr_threshold = %.2f sigma\n", cr_threshold );
 fprintf( stderr, "  neighbor_threshold = %.2f sigma\n", neighbor_threshold );
 fprintf( stderr, "  maxiter      = %d\n\n", maxiter );

 /* Read input image */
 result= read_fits_image( input_file, &image_data, naxes, &header_keys, &num_keys, &bitpix );
 if ( result != 0 ) {
  fprintf( stderr, "ERROR: Failed to read input image %s\n", input_file );
  return EXIT_FAILURE;
 }

 /* Allocate cosmic ray mask */
 crmask= malloc( naxes[0] * naxes[1] * sizeof( unsigned char ) );
 if ( crmask == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for cosmic ray mask\n" );
  free( image_data );
  for ( ii= 0; ii < num_keys; ii++ )
   free( header_keys[ii] );
  free( header_keys );
  return EXIT_FAILURE;
 }

 /* Run L.A.Cosmic algorithm */
 fprintf( stderr, "Processing...\n" );
 total_cr= lacosmic_process( image_data, crmask, naxes[0], naxes[1],
                             gain, readnoise, contrast,
                             cr_threshold, neighbor_threshold, maxiter );

 if ( total_cr < 0 ) {
  fprintf( stderr, "ERROR: L.A.Cosmic processing failed\n" );
  free( image_data );
  free( crmask );
  for ( ii= 0; ii < num_keys; ii++ )
   free( header_keys[ii] );
  free( header_keys );
  return EXIT_FAILURE;
 }

 fprintf( stderr, "\nTotal cosmic ray pixels identified: %d\n", total_cr );

 /* Write output image */
 result= write_fits_image( output_file, image_data, naxes, header_keys, num_keys, bitpix,
                           gain, readnoise, contrast, cr_threshold, neighbor_threshold,
                           total_cr );
 if ( result != 0 ) {
  fprintf( stderr, "ERROR: Failed to write output image %s\n", output_file );
  free( image_data );
  free( crmask );
  for ( ii= 0; ii < num_keys; ii++ )
   free( header_keys[ii] );
  free( header_keys );
  return EXIT_FAILURE;
 }
 fprintf( stderr, "Output written to: %s\n", output_file );

 /* Write mask if requested */
 if ( mask_file ) {
  result= write_fits_mask( mask_file, crmask, naxes );
  if ( result != 0 ) {
   fprintf( stderr, "ERROR: Failed to write mask image %s\n", mask_file );
  } else {
   fprintf( stderr, "Mask written to: %s\n", mask_file );
  }
 }

 /* Clean up */
 free( image_data );
 free( crmask );
 for ( ii= 0; ii < num_keys; ii++ ) {
  free( header_keys[ii] );
 }
 free( header_keys );

 fprintf( stderr, "\nDone.\n" );
 return EXIT_SUCCESS;
}
