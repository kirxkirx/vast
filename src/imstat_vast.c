#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include <libgen.h> // for basename()

#include <gsl/gsl_sort.h>
#include <gsl/gsl_statistics.h>

#include "fitsio.h"

#include "vast_limits.h"

#include "variability_indexes.h" // for esimate_sigma_from_MAD_of_sorted_data_float()

#include "fitsfile_read_check.h"

#include "replace_file_with_symlink_if_filename_contains_white_spaces.h"

int compute_image_stratistics(char *fitsfilename, int no_sorting_fast_computation, double *min, double *max, double *range, double *median, double *mean, double *mean_err, double *std, double *mad, double *mad_scaled_to_sigma, double *iqr, double *iqr_scaled_to_sigma) {

 fitsfile *fptr; // FITS file pointer
 int status= 0;  // CFITSIO status value MUST be initialized to zero!
 int naxis;
 long naxes[3], totpix; // we may need naxes[3] to handle 3D cube slice case with dimentions X*Y*1
 double *pix;

 int anynul= 0;
 double nullval= 0.0;


 totpix= 0;   // reset
 (*min)=(*max)=(*range)=(*median)=(*mean)=(*mean_err)=(*std)=(*mad)=(*mad_scaled_to_sigma)=(*iqr)=(*iqr_scaled_to_sigma)= 0.0;    // reset

 if( 0 != fits_open_image(&fptr, fitsfilename, READONLY, &status) ) { 
  fits_report_error(stderr, status); // print any error message         
  fits_clear_errmsg();               // clear the CFITSIO error message stack
  status= 0;
  fprintf(stderr, "ERROR in compute_images_stratistics() while trying to fits_open_image()\n");
  return 1;
 }

 fits_get_img_dim(fptr, &naxis, &status);                    
 if( naxis > 3 ) {
  fprintf(stderr, "ERROR in compute_images_stratistics(): NAXIS = %d.  Only 2-D images are supported.\n", naxis);
  fits_close_file(fptr, &status);
  return 1;
 }

 // maxdim = 2 is for the X*Y*1 case
 fits_get_img_size(fptr, 2, naxes, &status);

 if( status || naxis != 2 ) {
  fprintf(stderr, "ERROR in compute_images_stratistics() while trying to fits_get_img_size()\n");
  fits_report_error(stderr, status); // print any error message         
  fits_clear_errmsg();               // clear the CFITSIO error message stack
  fits_close_file(fptr, &status);
  status= 0;
  return 1;
 }
 
 if( naxes[0] < 1 || naxes[1] < 1 ) {
  fprintf(stderr, "ERROR in compute_images_stratistics() the image dimensions are clearly wrong!\n");
  fits_report_error(stderr, status); // print any error message         
  fits_clear_errmsg();               // clear the CFITSIO error message stack
  fits_close_file(fptr, &status);
  status= 0;
  return 1;
 }
 
 totpix= naxes[0] * naxes[1];
 pix= (double *)malloc(totpix * sizeof(double)); // memory for the input image
 if( pix == NULL ) {
  fprintf(stderr, "ERROR in compute_images_stratistics() cannot allocate memory\n");
  fits_close_file(fptr, &status);
  status= 0;
  return 1;
 } 

 fits_read_img(fptr, TDOUBLE, 1, totpix, &nullval, pix, &anynul, &status);
 if( status != 0 ) {
  fprintf(stderr, "WARNING from  compute_images_stratistics() non-zero status after reading the image\n");
  fits_report_error(stderr, status); // print any error message
  fits_clear_errmsg();               // clear the CFITSIO error message stack
  status= 0;
  return 1;
 }
 fits_close_file(fptr, &status);


 (*mean)= gsl_stats_mean(pix, 1, totpix);
 (*std)= gsl_stats_sd_m(pix, 1, totpix, (*mean));
 (*mean_err)= (*mean) / sqrt( (double)totpix);

 if( no_sorting_fast_computation != 1 ) {
  gsl_sort(pix, 1, totpix);
  (*min)= pix[0];
  (*max)= pix[totpix-1];
  (*range)= (*max) - (*min);
  (*median)= gsl_stats_median_from_sorted_data(pix, 1, totpix);
  (*iqr)= compute_IQR_of_sorted_data(pix, totpix);
  // 2*norminv(0.75) = 1.34897950039216
  (*iqr_scaled_to_sigma)= (*iqr) / 1.34897950039216;
  (*mad)= compute_MAD_of_sorted_data(pix, totpix);
  // 1.48260221850560 = 1/norminv(3/4)
  (*mad_scaled_to_sigma)= 1.48260221850560 * (*mad);
 }

 free(pix); // we messed up the order of pix while calculating median anyhow
 
 return 0;
}


int main(int argc, char **argv) {

 char fitsfilename[FILENAME_LENGTH];
 double min,max,range,median,mean,mean_err,std,mad,mad_scaled_to_sigma,iqr,iqr_scaled_to_sigma;

 if( argc < 2 ) {
  fprintf(stderr, "Usage: %s image.fits\n", argv[0]);
  return 1;
 } else {
  fprintf(stderr, "Running: %s %s\n", argv[0], argv[1]);
 }
 strncpy(fitsfilename, argv[1], FILENAME_LENGTH - 1);
 fitsfilename[FILENAME_LENGTH - 1]= '\0';

 fprintf(stderr, "Computing image statistics for the file %s\n", fitsfilename);

 replace_file_with_symlink_if_filename_contains_white_spaces(fitsfilename);

 if( 0 != fitsfile_read_check( fitsfilename ) ) {
  fprintf(stderr, "ERROR in %s: the input file did not pass fitsfile_read_check()\n", argv[0]);
  return 1;
 }
 
 cutout_green_channel_out_of_RGB_DSLR_image(fitsfilename);


 if( 0 == strncmp("imstat_vast_fast", basename(argv[0]), MIN( strlen("imstat_vast_fast"), strlen(basename(argv[0])) ) ) ) {
  // fast computation avoiding sorting
  if( 0 != compute_image_stratistics(fitsfilename, 1, &min, &max, &range, &median, &mean, &mean_err, &std, &mad, &mad_scaled_to_sigma, &iqr, &iqr_scaled_to_sigma) ) {
   fprintf(stderr, "ERROR in %s while running compute_image_stratistics()\n", argv[0]);
   return 1;
  }
 } else {
  if( 0 != compute_image_stratistics(fitsfilename, 0, &min, &max, &range, &median, &mean, &mean_err, &std, &mad, &mad_scaled_to_sigma, &iqr, &iqr_scaled_to_sigma) ) {
   fprintf(stderr, "ERROR in %s while running compute_image_stratistics()\n", argv[0]);
   return 1;
  }
  fprintf(stdout, "     MIN= %10.4lf\n", min);
  fprintf(stdout, "     MAX= %10.4lf\n", max);
  fprintf(stdout, " MAX-MIN= %10.4lf\n", range);
  fprintf(stdout, "  MEDIAN= %10.4lf\n", median);
  fprintf(stdout, "     MAD= %10.4lf\n", mad);
  // 1.48260221850560 = 1/norminv(3/4)
  fprintf(stdout, "MADx1.48= %10.4lf\n", mad_scaled_to_sigma);
  fprintf(stdout, "     IQR= %10.4lf\n", iqr);
  // Scale IQR to sigma
  // ${\rm IQR} = 2 \Phi^{-1}(0.75)
  // 2*norminv(0.75) = 1.34897950039216
  fprintf(stdout, "IQR/1.34= %10.4lf\n", iqr_scaled_to_sigma);
 }

 fprintf(stdout, "    MEAN= %10.4lf\n", mean);
 fprintf(stdout, "MEAN_ERR= %10.4lf\n", mean_err);
 fprintf(stdout, "      SD= %10.4lf\n", std);

 return 0;
}
