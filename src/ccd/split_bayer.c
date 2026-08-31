// split_bayer -- split a raw Bayer-mosaic FITS image (one-shot-color camera,
// e.g. ZWO Seestar S50) into three half-resolution per-channel FITS images
// suitable for aperture photometry.
//
// Each 2x2 Bayer cell of the input produces exactly ONE output pixel per
// channel ("superpixel" scheme): the R and B output pixels are the raw values
// of the corresponding cell pixels and the G output pixel is the average of
// the two green cell pixels. No interpolation is performed, so the
// per-channel photometry is free of demosaicing artifacts. The three output
// images share the same pixel grid, but the effective light centroids of the
// R, G and B channels are shifted by up to half a superpixel relative to each
// other - plate-solve each channel image independently before doing
// astrometry-based photometry.
//
// The Bayer pattern string (RGGB/BGGR/GRBG/GBRG) is taken from the BAYERPAT
// header keyword unless overridden on the command line. The pattern is
// interpreted in the FITS pixel storage order: pattern[0] pattern[1] are the
// first two pixels of the first stored image row. Some capture software
// records BAYERPAT in display orientation (top row first) while FITS stores
// the bottom row first; if the two conventions disagree, the R and B output
// channels are swapped while G is unaffected. The calibration diagnostics in
// util/seestar_photometry.sh detect such a swap from stellar colors.
//
// If any input pixel contributing to an output pixel is at or above
// SATURATION_PROPAGATION_INPUT_ADU, the output pixel is set to
// SATURATED_OUTPUT_ADU so that SExtractor can flag the star as saturated
// (this matters for the averaged G channel where one saturated pixel would
// otherwise be hidden by the average).

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../fitsio.h"

#define SATURATION_PROPAGATION_INPUT_ADU 65500.0
#define SATURATED_OUTPUT_ADU 65535.0

// Header keywords copied verbatim from the input image to each channel image.
// WCS and Bayer keywords are deliberately NOT copied: the WCS of the
// full-resolution mosaic does not apply to the binned channel images.
static const char *keywords_to_copy[]= { "EXPTIME", "EXPOSURE", "DATE-OBS", "DATE-EXP", "TIME-OBS", "JD", "GAIN", "EGAIN", "CCD-TEMP", "FOCALLEN", "APERTURE", "INSTRUME", "TELESCOP", "OBSERVER", "OBJECT", "SITELONG", "SITELAT", "FILTER", "IMAGETYP", "BIAS", "RA", "DEC", NULL };

static int write_channel_image( fitsfile *in_fptr, char *output_filename, double *data, long out_w, long out_h, char channel_letter, char *pattern, char *input_basename ) {
 fitsfile *out_fptr;
 int status= 0;
 int keyindex;
 long naxes[2];
 long fpixel[2];
 double pixsz;
 double electrons_per_adu;
 char card[FLEN_CARD];
 char history_string[512];
 char channel_string[2];
 char create_name[8192 + 2];

 naxes[0]= out_w;
 naxes[1]= out_h;
 fpixel[0]= fpixel[1]= 1;

 // The leading '!' tells CFITSIO to overwrite an existing file
 sprintf( create_name, "!%s", output_filename );
 if ( fits_create_file( &out_fptr, create_name, &status ) ) {
  fits_report_error( stderr, status );
  return 1;
 }
 if ( fits_create_img( out_fptr, FLOAT_IMG, 2, naxes, &status ) ) {
  fits_report_error( stderr, status );
  return 1;
 }

 // Copy selected header keywords from the input image
 for ( keyindex= 0; keywords_to_copy[keyindex] != NULL; keyindex++ ) {
  // EGAIN (e-/ADU) is handled separately for the averaged G channel below
  if ( channel_letter == 'G' && 0 == strcmp( keywords_to_copy[keyindex], "EGAIN" ) ) {
   continue;
  }
  status= 0;
  if ( 0 == fits_read_card( in_fptr, (char *)keywords_to_copy[keyindex], card, &status ) ) {
   fits_write_record( out_fptr, card, &status );
  }
 }
 status= 0;

 // The G output pixel is the AVERAGE of two raw pixels, so the number of
 // collected electrons per output ADU is twice that of a single raw pixel
 if ( channel_letter == 'G' ) {
  if ( 0 == fits_read_key( in_fptr, TDOUBLE, "EGAIN", &electrons_per_adu, NULL, &status ) ) {
   electrons_per_adu= 2.0 * electrons_per_adu;
   fits_update_key( out_fptr, TDOUBLE, "EGAIN", &electrons_per_adu, "e-/ADU doubled: G superpixel is a two-pixel average", &status );
  }
  status= 0;
 }

 // The superpixels are twice the physical size of the input pixels
 if ( 0 == fits_read_key( in_fptr, TDOUBLE, "XPIXSZ", &pixsz, NULL, &status ) ) {
  pixsz= 2.0 * pixsz;
  fits_update_key( out_fptr, TDOUBLE, "XPIXSZ", &pixsz, "pixel size in microns (2x2 Bayer superpixel)", &status );
 }
 status= 0;
 if ( 0 == fits_read_key( in_fptr, TDOUBLE, "YPIXSZ", &pixsz, NULL, &status ) ) {
  pixsz= 2.0 * pixsz;
  fits_update_key( out_fptr, TDOUBLE, "YPIXSZ", &pixsz, "pixel size in microns (2x2 Bayer superpixel)", &status );
 }
 status= 0;

 channel_string[0]= channel_letter;
 channel_string[1]= '\0';
 fits_update_key( out_fptr, TSTRING, "BAYERCHN", channel_string, "Bayer channel extracted by split_bayer", &status );
 sprintf( history_string, "split_bayer: channel %c extracted with pattern %s from %.180s", channel_letter, pattern, input_basename );
 fits_write_history( out_fptr, history_string, &status );

 if ( fits_write_pix( out_fptr, TDOUBLE, fpixel, out_w * out_h, data, &status ) ) {
  fits_report_error( stderr, status );
  return 1;
 }
 if ( fits_close_file( out_fptr, &status ) ) {
  fits_report_error( stderr, status );
  return 1;
 }

 return 0;
}

int main( int argc, char **argv ) {
 fitsfile *in_fptr;
 int status= 0;
 int bitpix;
 int naxis;
 long naxes[2];
 long fpixel[2];
 long input_width;
 long input_height;
 long out_w;
 long out_h;
 long cx;
 long cy;
 long out_index;
 int cell_i;
 int cell_j;
 int pattern_index;
 int saturated_r;
 int saturated_g;
 int saturated_b;
 double cell_value;
 double value_r;
 double value_b;
 double sum_g;
 double *input_data;
 double *output_r;
 double *output_g;
 double *output_b;
 char pattern[FLEN_VALUE];
 char *input_basename;
 char *extension_pointer;
 char output_dir[4096];
 char base_no_extension[4096];
 char output_filename_r[8192];
 char output_filename_g[8192];
 char output_filename_b[8192];
 size_t string_index;
 size_t output_dir_length;

 if ( argc < 3 || argc > 4 ) {
  fprintf( stderr, "Split a Bayer-mosaic FITS image into half-resolution R, G, B superpixel images.\n" );
  fprintf( stderr, "Usage: %s bayer_mosaic.fits output_directory [BAYER_PATTERN]\n", argv[0] );
  fprintf( stderr, "BAYER_PATTERN is one of RGGB, BGGR, GRBG, GBRG; if not given, the BAYERPAT header keyword is used.\n" );
  fprintf( stderr, "The three output image paths are printed to stdout, one per line, in R G B order.\n" );
  return 1;
 }

 // CFITSIO itself cannot handle file names longer than FLEN_FILENAME (1025)
 if ( strlen( argv[2] ) > 1000 ) {
  fprintf( stderr, "ERROR: the output directory path is too long\n" );
  return 1;
 }
 strcpy( output_dir, argv[2] );
 // Drop a trailing slash if present
 output_dir_length= strlen( output_dir );
 if ( output_dir_length > 1 && output_dir[output_dir_length - 1] == '/' ) {
  output_dir[output_dir_length - 1]= '\0';
 }

 // fits_open_image() moves to the first image HDU, so fpack-compressed
 // (.fz) inputs are handled transparently
 if ( fits_open_image( &in_fptr, argv[1], READONLY, &status ) ) {
  fits_report_error( stderr, status );
  return 1;
 }
 if ( fits_get_img_param( in_fptr, 2, &bitpix, &naxis, naxes, &status ) ) {
  fits_report_error( stderr, status );
  return 1;
 }
 if ( naxis != 2 ) {
  fprintf( stderr, "ERROR: only 2D images are supported, this one has NAXIS=%d\n", naxis );
  return 1;
 }
 input_width= naxes[0];
 input_height= naxes[1];
 if ( input_width < 2 || input_height < 2 ) {
  fprintf( stderr, "ERROR: the input image is too small (%ldx%ld)\n", input_width, input_height );
  return 1;
 }
 if ( input_width % 2 != 0 || input_height % 2 != 0 ) {
  fprintf( stderr, "WARNING: odd image dimensions %ldx%ld - the last column/row will be ignored\n", input_width, input_height );
 }

 // Get the Bayer pattern from the command line or the header
 if ( argc == 4 ) {
  if ( strlen( argv[3] ) != 4 ) {
   fprintf( stderr, "ERROR: the Bayer pattern must be a four-character string like RGGB, got '%s'\n", argv[3] );
   return 1;
  }
  strcpy( pattern, argv[3] );
 } else {
  if ( 0 != fits_read_key( in_fptr, TSTRING, "BAYERPAT", pattern, NULL, &status ) ) {
   fprintf( stderr, "ERROR: no BAYERPAT keyword in the header of %s and no Bayer pattern given on the command line\n", argv[1] );
   return 1;
  }
 }
 // Uppercase and trim trailing spaces
 for ( string_index= 0; string_index < strlen( pattern ); string_index++ ) {
  if ( pattern[string_index] >= 'a' && pattern[string_index] <= 'z' ) {
   pattern[string_index]= pattern[string_index] - 'a' + 'A';
  }
  if ( pattern[string_index] == ' ' ) {
   pattern[string_index]= '\0';
   break;
  }
 }
 if ( 0 != strcmp( pattern, "RGGB" ) && 0 != strcmp( pattern, "BGGR" ) && 0 != strcmp( pattern, "GRBG" ) && 0 != strcmp( pattern, "GBRG" ) ) {
  fprintf( stderr, "ERROR: '%s' is not a valid Bayer pattern (expected one of RGGB, BGGR, GRBG, GBRG)\n", pattern );
  return 1;
 }
 fprintf( stderr, "Splitting %s with Bayer pattern %s\n", argv[1], pattern );

 // Read the input image
 input_data= (double *)malloc( input_width * input_height * sizeof( double ) );
 if ( input_data == NULL ) {
  fprintf( stderr, "ERROR: memory allocation failure (input image)\n" );
  return 1;
 }
 fpixel[0]= fpixel[1]= 1;
 if ( fits_read_pix( in_fptr, TDOUBLE, fpixel, input_width * input_height, NULL, input_data, NULL, &status ) ) {
  fits_report_error( stderr, status );
  return 1;
 }

 out_w= input_width / 2;
 out_h= input_height / 2;
 output_r= (double *)malloc( out_w * out_h * sizeof( double ) );
 output_g= (double *)malloc( out_w * out_h * sizeof( double ) );
 output_b= (double *)malloc( out_w * out_h * sizeof( double ) );
 if ( output_r == NULL || output_g == NULL || output_b == NULL ) {
  fprintf( stderr, "ERROR: memory allocation failure (output images)\n" );
  return 1;
 }

 // Split the Bayer mosaic into superpixels
 for ( cy= 0; cy < out_h; cy++ ) {
  for ( cx= 0; cx < out_w; cx++ ) {
   value_r= 0.0;
   value_b= 0.0;
   sum_g= 0.0;
   saturated_r= saturated_g= saturated_b= 0;
   for ( cell_j= 0; cell_j < 2; cell_j++ ) {
    for ( cell_i= 0; cell_i < 2; cell_i++ ) {
     pattern_index= 2 * cell_j + cell_i;
     cell_value= input_data[( 2 * cy + cell_j ) * input_width + 2 * cx + cell_i];
     if ( pattern[pattern_index] == 'R' ) {
      value_r= cell_value;
      if ( cell_value >= SATURATION_PROPAGATION_INPUT_ADU ) {
       saturated_r= 1;
      }
     } else if ( pattern[pattern_index] == 'B' ) {
      value_b= cell_value;
      if ( cell_value >= SATURATION_PROPAGATION_INPUT_ADU ) {
       saturated_b= 1;
      }
     } else {
      sum_g+= cell_value;
      if ( cell_value >= SATURATION_PROPAGATION_INPUT_ADU ) {
       saturated_g= 1;
      }
     }
    }
   }
   out_index= cy * out_w + cx;
   output_r[out_index]= saturated_r ? SATURATED_OUTPUT_ADU : value_r;
   output_g[out_index]= saturated_g ? SATURATED_OUTPUT_ADU : sum_g / 2.0;
   output_b[out_index]= saturated_b ? SATURATED_OUTPUT_ADU : value_b;
  }
 }

 // Construct the output file names from the input basename
 input_basename= strrchr( argv[1], '/' );
 if ( input_basename == NULL ) {
  input_basename= argv[1];
 } else {
  input_basename= input_basename + 1;
 }
 // CFITSIO itself cannot handle file names longer than FLEN_FILENAME (1025)
 if ( strlen( input_basename ) > 1000 ) {
  fprintf( stderr, "ERROR: the input file name is too long\n" );
  return 1;
 }
 strcpy( base_no_extension, input_basename );
 // Drop any CFITSIO extended-syntax specifier like [1] before deriving
 // the output names from the input file name
 extension_pointer= strchr( base_no_extension, '[' );
 if ( extension_pointer != NULL ) {
  *extension_pointer= '\0';
 }
 // Strip a .fz compression suffix and then the FITS extension
 extension_pointer= strrchr( base_no_extension, '.' );
 if ( extension_pointer != NULL && 0 == strcmp( extension_pointer, ".fz" ) ) {
  *extension_pointer= '\0';
 }
 extension_pointer= strrchr( base_no_extension, '.' );
 if ( extension_pointer != NULL ) {
  if ( 0 == strcmp( extension_pointer, ".fit" ) || 0 == strcmp( extension_pointer, ".fits" ) || 0 == strcmp( extension_pointer, ".fts" ) || 0 == strcmp( extension_pointer, ".FIT" ) || 0 == strcmp( extension_pointer, ".FITS" ) || 0 == strcmp( extension_pointer, ".FTS" ) ) {
   *extension_pointer= '\0';
  }
 }
 sprintf( output_filename_r, "%s/%s_R.fit", output_dir, base_no_extension );
 sprintf( output_filename_g, "%s/%s_G.fit", output_dir, base_no_extension );
 sprintf( output_filename_b, "%s/%s_B.fit", output_dir, base_no_extension );

 if ( 0 != write_channel_image( in_fptr, output_filename_r, output_r, out_w, out_h, 'R', pattern, input_basename ) ) {
  return 1;
 }
 if ( 0 != write_channel_image( in_fptr, output_filename_g, output_g, out_w, out_h, 'G', pattern, input_basename ) ) {
  return 1;
 }
 if ( 0 != write_channel_image( in_fptr, output_filename_b, output_b, out_w, out_h, 'B', pattern, input_basename ) ) {
  return 1;
 }

 fits_close_file( in_fptr, &status );

 free( input_data );
 free( output_r );
 free( output_g );
 free( output_b );

 fprintf( stderr, "The %ldx%ld input image is split into three %ldx%ld channel images\n", input_width, input_height, out_w, out_h );

 // Machine-readable output for calling scripts: the three paths in R G B order
 fprintf( stdout, "%s\n%s\n%s\n", output_filename_r, output_filename_g, output_filename_b );

 return 0;
}
