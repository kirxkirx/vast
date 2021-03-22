#include <stdio.h>
#include <stdlib.h>

#define _GNU_SOURCE // for memmem()
#include <string.h>

#include <math.h>
#include <libgen.h> // for basename()

#include <sys/types.h> // for getpid()
#include <unistd.h>    // for getpid() too  and for unlink()

#include <time.h> // for nanosleep()

#include <sys/wait.h> // for waitpid

#include <getopt.h>

#include <gsl/gsl_statistics_float.h>
#include <gsl/gsl_sort_float.h>

#include "cpgplot.h"

#include "../setenv_local_pgplot.h"

#include "../fitsio.h"

#include "../vast_limits.h"
#include "../photocurve.h"
#include "../ident.h"
#include "../fitsfile_read_check.h"
#include "../replace_file_with_symlink_if_filename_contains_white_spaces.h"

#include "../parse_sextractor_catalog.h"

#include "../get_path_to_vast.h"

#include "../count_lines_in_ASCII_file.h"

#include "../lightcurve_io.h" // for read_lightcurve_point()

#include "../is_point_close_or_off_the_frame_edge.h" // for is_point_close_or_off_the_frame_edge()

int Kourovka_SBG_date_hack(char *fitsfilename, char *DATEOBS, int *date_parsed, double *exposure); // defined in gettime.c

void save_star_to_vast_list_of_previously_known_variables_and_exclude_lst(int sexNUMBER, float sexX, float sexY) {
 FILE *filepointer;
 fprintf(stderr, "Marking out%05d.dat as a variable star and excluding it from magnitude calibration\n", sexNUMBER);
 filepointer= fopen("vast_list_of_previously_known_variables.log", "a");
 fprintf(filepointer, "out%05d.dat\n", sexNUMBER);
 fclose(filepointer);
 filepointer= fopen("exclude.lst", "a");
 fprintf(filepointer, "%.3f %.3f\n", sexX, sexY);
 fclose(filepointer);
 return;
}

int get_string_with_fov_of_wcs_calibrated_image(char *fitsfilename, char *output_string, int finding_chart_mode, float finder_char_pix_around_the_target) {
 float image_scale, image_size;
 unsigned int string_char_counter;
 char path_to_vast_string[VAST_PATH_MAX];
 char systemcommand[2 * VAST_PATH_MAX];
 FILE *fp;
 get_path_to_vast(path_to_vast_string);
 path_to_vast_string[VAST_PATH_MAX - 1]= '\0'; // just in case
 //
 output_string[0]= '\0'; // reset output just in case
 //
 if( finding_chart_mode == 1 ) {
  // This is a zoom-in image
  sprintf(systemcommand, "%sutil/fov_of_wcs_calibrated_image.sh %s | grep 'Image scale:' | awk '{print $3}' | awk -F'\"' '{print $1}'", path_to_vast_string, fitsfilename);
  fprintf(stderr, "Trying to run\n %s\n", systemcommand);
  if( (fp= popen(systemcommand, "r")) == NULL ) {
   fprintf(stderr, "ERROR in get_string_with_fov_of_wcs_calibrated_image() while opening pipe!\n");
   return 1;
  }
  if( 1 == fscanf(fp, "%f", &image_scale) ) {
   if( image_scale > 0.0 ) {
    image_size= image_scale * 2.0 * finder_char_pix_around_the_target / 60.0;
    if( image_size > 0.0 ) {
     sprintf(output_string, "Image size: %.0f'x%.0f'", image_size, image_size);
    }
   }
  }
  pclose(fp);
 } else {
  // Full-frame image
  sprintf(systemcommand, "%sutil/fov_of_wcs_calibrated_image.sh %s", path_to_vast_string, fitsfilename);
  fprintf(stderr, "Trying to run\n %s\n", systemcommand);
  if( (fp= popen(systemcommand, "r")) == NULL ) {
   fprintf(stderr, "ERROR in get_string_with_fov_of_wcs_calibrated_image() while opening pipe!\n");
   return 1;
  }
  if( NULL != fgets(output_string, 1024, fp) ) {
   output_string[1024 - 1]= '\0'; // just in case
   // remove new line character from the end of the string
   for( string_char_counter= 0; string_char_counter < strlen(output_string); string_char_counter++ ) {
    if( output_string[string_char_counter] == '\n' ) {
     output_string[string_char_counter]= '\0';
    }
   }
  }
  pclose(fp);
 }
 /*
 // On success, these functions return the number of input items successfully matched and assigned
 if( 1!=fscanf(fp,"%s",output_string) ){
  fprintf(stderr,"ERROR in get_string_with_fov_of_wcs_calibrated_image() Cannot read the command output\n");
  output_string[0]='\0'; // reset output just in case
  return 1;
 }
 pclose(fp);
 if( pclose(fp) )  {
  fprintf(stderr,"ERROR in get_string_with_fov_of_wcs_calibrated_image() Command not found or exited with error status\n");
  output_string[0]='\0'; // reset output just in case
  return 1;
 }
 */
 return 0;
}

int xy2sky(char *fitsfilename, float X, float Y) {
 char path_to_vast_string[VAST_PATH_MAX];
 char systemcommand[2 * VAST_PATH_MAX];
 int systemcommand_return_value;
 get_path_to_vast(path_to_vast_string);
 path_to_vast_string[VAST_PATH_MAX - 1]= '\0'; // just in case
 //fprintf(stderr,"DEBUG xy2sky(): path_to_vast_string = %s\n",path_to_vast_string);
 sprintf(systemcommand, "%slib/bin/xy2sky %s %lf %lf >> /dev/stderr", path_to_vast_string, fitsfilename, X, Y);
 systemcommand[2 * VAST_PATH_MAX - 1]= '\0'; // just in case
 systemcommand_return_value= system(systemcommand);
 if( systemcommand_return_value == 0 ) {
  fprintf(stderr, "The pixel to celestal coordinates transforamtion is performed using 'xy2sky' from WCSTools.\n");
 }
 return systemcommand_return_value;
}

int sky2xy(char *fitsfilename, char *input_RA_string, char *input_DEC_string, float *outX, float *outY) {
 char path_to_vast_string[VAST_PATH_MAX];
 char systemcommand[2 * VAST_PATH_MAX];
 unsigned int i, n_semicol; // counter
 FILE *pipe_for_sky2xy;
 char command_output_string[VAST_PATH_MAX];

 // Check that the input coordinates are in the 01:02:03.45 +06:07:08.9 format
 n_semicol= 0;
 for( i= 0; i < strlen(input_RA_string); i++ ) {
  if( input_RA_string[i] == ':' ) {
   n_semicol++;
  }
 }
 for( i= 0; i < strlen(input_DEC_string); i++ ) {
  if( input_DEC_string[i] == ':' ) {
   n_semicol++;
  }
 }
 if( n_semicol != 4 ) {
  (*outX)= (float)atof(input_RA_string);
  (*outY)= (float)atof(input_DEC_string);
  return 1;
 }
 //

 get_path_to_vast(path_to_vast_string);
 path_to_vast_string[VAST_PATH_MAX - 1]= '\0'; // just in case
 sprintf(systemcommand, "%slib/bin/sky2xy %s %s %s", path_to_vast_string, fitsfilename, input_RA_string, input_DEC_string);
 systemcommand[2 * VAST_PATH_MAX - 1]= '\0'; // just in case

 pipe_for_sky2xy= popen(systemcommand, "r");
 if( NULL == pipe_for_sky2xy ) {
  (*outX)= (float)atof(input_RA_string);
  (*outY)= (float)atof(input_DEC_string);
  return 1;
 }
 if( NULL == fgets(command_output_string, VAST_PATH_MAX, pipe_for_sky2xy) ) {
  pclose(pipe_for_sky2xy);
  (*outX)= (float)atof(input_RA_string);
  (*outY)= (float)atof(input_DEC_string);
  return 1;
 }
 pclose(pipe_for_sky2xy);
 command_output_string[VAST_PATH_MAX - 1]= '\0'; // just in case
 if( NULL != strstr(command_output_string, "off") ) {
  fprintf(stderr, "#### The specified celestial position is outside the image! ####\n");
  (*outX)= 0.0;
  (*outY)= 0.0;
  return 1;
 }
 // expecting:
 // 18:19:53.683 -30:41:12.54 J2000 -> 1676.500 1266.500
 if( 2 != sscanf(command_output_string, "%*s %*s J2000 -> %f %f", outX, outY) ) {
  (*outX)= (float)atof(input_RA_string);
  (*outY)= (float)atof(input_DEC_string);
  return 1;
 }

 if( (*outX) <= 0.0 || (*outY) <= 0.0 ) {
  (*outX)= (float)atof(input_RA_string);
  (*outY)= (float)atof(input_DEC_string);
  return 1;
 }

 return 0;
}

void print_pgfv_help() {
 fprintf(stderr, "\n");
 fprintf(stderr, "  --*** HOW TO USE THE IMAGE VIEWER ***--\n\n");
 fprintf(stderr, "press 'I' to get this message.\n");
 fprintf(stderr, "press 'Z' and draw rectangle to zoom in.\n");
 fprintf(stderr, "press 'D' or click middle mouse button to return to the original zoom.\n");
 fprintf(stderr, "press 'H' for Histogram Equalization.\n");
 fprintf(stderr, "press 'B' to invert X axis.\n");
 fprintf(stderr, "press 'V' to invert Y axis.\n");
 fprintf(stderr, "move mouse and press 'F' to adjust image brightness/contrast. If an image apears too bright, move the pointer to the lower left and press 'F'. Repeat it many times to achive the desired result.\n");
 fprintf(stderr, "press 'M' to turn star markers on/off.\n");
 fprintf(stderr, "press 'X' or right click to exit!\nClick on image to get coordinates and value of the current pixel...\n");
 fprintf(stderr, "\n");
 return;
}

// Special function for handling online access to HLA images
int download_hla_image_if_this_is_it_and_modify_imagename(char *fits_image_name, float markX, float markY) {
 unsigned int i;
 char system_command[4096];
 char output_fits_image_name[FILENAME_LENGTH];
 // first check if this looks like an HLA image
 // hst_12911_47_wfc3_uvis_f775w
 if( 12 > strlen(fits_image_name) )
  return 1; // filename too short
 if( 60 < strlen(fits_image_name) )
  return 1; // filename too long
 if( fits_image_name[0] != 'h' )
  return 1;
 if( fits_image_name[1] != 's' )
  return 1;
 if( fits_image_name[2] != 't' )
  return 1;
 if( fits_image_name[3] != '_' )
  return 1;
 if( 0 != strcmp(fits_image_name, basename(fits_image_name)) )
  return 1; // file system path information - not our case
 for( i= 0; i < strlen(fits_image_name); i++ ) {
  if( fits_image_name[i] == '.' )
   return 1; // there is an extension - surely it's a filename, not our case
 }
 // ok, if we are still here, assume we have an HLA image
 // generate_an_output_filename
 sprintf(output_fits_image_name, "wcs_%s_%.6f_%.6f.fits", fits_image_name, markX, markY);
 // check if this file already exist
 if( 0 == fitsfile_read_check(output_fits_image_name) ) {
  strncpy(fits_image_name, output_fits_image_name, FILENAME_LENGTH - 1);
  fits_image_name[FILENAME_LENGTH - 1]= '\0'; //just in case
  return 0;
 }
 sprintf(system_command, "LANG=C wget -c -O %s 'http://hla.stsci.edu/cgi-bin/fitscut.cgi?red=%s&RA=%.6f&Dec=%.6f&Size=64&Format=fits&ApplyOmega=true'\n", output_fits_image_name, fits_image_name, markX, markY);
 fprintf(stderr, "Downloading a cutout from HLA image %s\n%s\n", fits_image_name, system_command);
 if( 0 == system(system_command) ) {
  fprintf(stderr, "Success! =)\n");
  strncpy(fits_image_name, output_fits_image_name, FILENAME_LENGTH - 1);
  fits_image_name[FILENAME_LENGTH - 1]= '\0'; // just in case
  return 0;
 } else {
  fprintf(stderr, "Failed to download the image! :(\n");
  return 1;
 }
 return 1;
}

/* Magnitude calibration for single image mode */
void magnitude_calibration_using_calib_txt(double *mag, int N) {
 int i;
 double a, b, c;
 double a_[4];
 int operation_mode;
 FILE *f;
 /* Check if calib.txt is readable */
 f= fopen("calib.txt", "r");
 if( f == NULL )
  return;
 fclose(f);
 if( 0 != system("lib/fit_mag_calib > calib.tmp") ) {
  fprintf(stderr, "ERROR running  lib/fit_mag_calib > calib.tmp\n");
  return;
 }
 f= fopen("calib.tmp", "r");
 if( 5 == fscanf(f, "%d %lf %lf %lf %lf", &operation_mode, &a_[0], &a_[1], &a_[2], &a_[3]) ) {
  // photocurve
  fprintf(stderr, "Calibrating the magnitude scale using the photocurve with parameters:\n%lf %lf %lf %lf\n", a_[0], a_[1], a_[2], a_[3]);
  for( i= 0; i < N; i++ )
   mag[i]= eval_photocurve(mag[i], a_, operation_mode);
 } else {
  // parabola or straight line
  fseek(f, 0, SEEK_SET); // go back to the beginning of the file
  if( 3 > fscanf(f, "%lf %lf %lf", &a, &b, &c) ) {
   fprintf(stderr, "ERROR parsing calib.tmp in magnitude_calibration_using_calib_txt()\n");
  }
  fprintf(stderr, "Calibrating the magnitude scale using the polynom with parameters:\n%lf %lf %lf\n", a, b, c);
  for( i= 0; i < N; i++ )
   mag[i]= a * mag[i] * mag[i] + b * mag[i] + c;
 }
 fclose(f);
 //system("rm -f calib.tmp");
 unlink("calib.tmp");
 return;
}

/* Extract reference image name from log file */
/*
void get_ref_image_name(char *str){
 FILE *outfile;
 char outfilename[2048];
 outfile=fopen("vast_summary.log","r");
 if( outfile==NULL ){
  fprintf(stderr,"ERROR: can't open the log file vast_summary.log\n");
  exit(1);
 }
 fclose(outfile);
 system("grep \"Ref.  image:\" vast_summary.log | awk '{print $6}' > tmp.tmp");
 strcpy(outfilename,"tmp.tmp");
 outfile=fopen(outfilename,"r");
 if( NULL==outfile ){
  fprintf(stderr,"ERROR: Can't open file %s\n",outfilename);
  exit(1);
 }
 fscanf(outfile,"%s",str);
 fclose(outfile);
 system("rm -f tmp.tmp");
 return;
}
*/

void get_ref_image_name(char *str) {
 FILE *outfile;
 char stringbuf[2048];
 char stringtrash1[2048];
 char stringtrash2[2048];
 char stringtrash3[2048];
 fprintf(stderr, "Getting the reference image name from vast_summary.log\n");
 outfile= fopen("vast_summary.log", "r");
 if( outfile == NULL ) {
  fprintf(stderr, "ERROR: cannot get the reference image name as there is no vast_summary.log\n");
  exit(1);
 }
 while( NULL != fgets(stringbuf, 2048, outfile) ) {
  stringbuf[2048 - 1]= '\0'; // just in case
  if( NULL == strstr(stringbuf, "Ref.  image:") ) {
   continue;
  }
  // Example string to parse
  // Ref.  image: 2453192.38876 05.07.2004 21:18:19   ../sample_data/f_72-001r.fit
  sscanf(stringbuf, "Ref.  image: %s %s %s   %s", stringtrash1, stringtrash2, stringtrash3, str);
  stringtrash1[2048 - 1]= '\0'; // just in case
  stringtrash2[2048 - 1]= '\0'; // just in case
  stringtrash3[2048 - 1]= '\0'; // just in case
  // The line below freaks out Address sanitizer
  //sscanf( stringbuf, "Ref.  image: %2048s %2048s %2048s   %s", stringtrash1, stringtrash2, stringtrash3, str );
 }
 fclose(outfile);
 fprintf(stderr, "The reference image is %s \n", str);

 if( 0 != fitsfile_read_check(str) ) {
  fprintf(stderr, "WARNING: cannot open the reference image file %s \nHas this file moved?\n", str);
 }

 return;
}

void fix_array_with_negative_values(long NUM_OF_PIXELS, float *im) {
 long i;
 float min, max;
 min= max= im[0];
 for( i= 0; i < NUM_OF_PIXELS; i++ ) {
  if( im[i] < min && im[i] > 0 )
   min= im[i];
  if( im[i] > max && im[i] > 0 )
   max= im[i];
 }
 if( min < 0.0 ) {
  for( i= 0; i < NUM_OF_PIXELS; i++ )
   im[i]= im[i] - min;
  for( i= 0; i < NUM_OF_PIXELS; i++ ) {
   if( im[i] > max )
    max= im[i];
  }
  min= 0.001;
 }

 if( max > 65535.0 ) {
  for( i= 0; i < NUM_OF_PIXELS; i++ )
   im[i]= im[i] * 65535.0 / max;
 }
 max= 65535.0;

 return;
}

void image_minmax2(long NUM_OF_PIXELS, float *im, float *max_i, float *min_i) {
 int i;
 int HIST[65536];
 int summa= 0;
 int limit;
 int hist_summa= 0;
 (*max_i)= (*min_i)= im[0];
 // set all histogram values to 0
 for( i= 0; i < 65536; i++ ) {
  HIST[i]= 0;
 }

 for( i= 0; i < NUM_OF_PIXELS; i++ ) {
  if( im[i] > 0 && im[i] < 65535 ) {
   HIST[(long)(im[i] + 0.5)]+= 1;
   if( im[i] > (*max_i) )
    (*max_i)= im[i];
   if( im[i] < (*min_i) )
    (*min_i)= im[i];
  }
 }

 for( i= 0; i < 65535; i++ ) {
  hist_summa+= HIST[i];
 }

 limit= (long)(((double)hist_summa - (double)hist_summa * PGFV_CUTS_PERCENT / 100.0) / 2.0);

 //////////////////////
 // Try the percantage cuts only if the image range is not much smaller than 0 to 65535
 if( (*max_i) < 10.0 ) {

  // set all histogram values to 0
  for( i= 0; i < 65536; i++ ) {
   HIST[i]= 0;
  }

  for( i= 0; i < NUM_OF_PIXELS; i++ ) {
   if( im[i] > 0 && im[i] < 65535 ) {
    HIST[(long)(65535 / 10.0 * im[i] + 0.5)]+= 1;
    if( im[i] > (*max_i) )
     (*max_i)= im[i];
    if( im[i] < (*min_i) )
     (*min_i)= im[i];
   }
  }

  // find histogram peak
  summa= 0;
  for( i= 0; i < 65535; i++ ) {
   if( summa < HIST[i] ) {
    (*min_i)= (float)i / 65535 * 10.0;
    summa= HIST[i];
   }
  }
  (*min_i)-= (*min_i) * 2 / 3;
  (*min_i)= MAX((*min_i), 0); // do not go for very negatve values - they are likely wrong
  summa= 0;
  for( i= 65535; i > 1; i-- ) {
   summa+= HIST[i];

   if( summa >= limit ) {
    (*max_i)= (float)i / 65535 * 10.0;
    break;
   }
  }

  //fprintf( stderr, "DEBUG: image_minmax2() %f %f\n", ( *min_i ), ( *max_i ) );
  return;
 }
 //////////////////////

 // find histogram peak
 summa= 0;
 for( i= 0; i < 65535; i++ ) {
  if( summa < HIST[i] ) {
   (*min_i)= (float)i;
   summa= HIST[i];
  }
 }

 (*min_i)-= (*min_i) * 2 / 3;

 (*min_i)= MAX((*min_i), 0); // do not go for very negatve values - they are likely wrong

 summa= 0;
 for( i= 65535; i > 1; i-- ) {
  summa+= HIST[i];

  if( summa >= limit ) {
   (*max_i)= (float)i;
   break;
  }
 }

 return;
}

void image_minmax3(long NUM_OF_PIXELS, float *im, float *max_i, float *min_i, float drawX1, float drawX2, float drawY1, float drawY2, long *naxes) {
 long i;
 int HIST[65536];
 int summa= 0;
 int hist_summa= 0;
 (*max_i)= (*min_i)= im[0];

 float X, Y;

 int test_i;

 int limit;

 // int number_of_pixels_in_zoomed_image;

 if( NUM_OF_PIXELS <= 0 ) {
  fprintf(stderr, "FATAL ERROR in image_minmax3(): NUM_OF_PIXELS<=0 \n");
  exit(1);
 }

 /*
 // Do not allow sub-pixel zoom
 number_of_pixels_in_zoomed_image=0;
 for ( i= 0; i < NUM_OF_PIXELS; i++ ) {
  if ( im[i] > 0 && 65535/10.0*im[i] < 65535 ) {
   // Cool it works!!! (Transformation from i to XY)
   Y= 1 + (int)( (float)i / (float)naxes[0] );
   X= i + 1 - ( Y - 1 ) * naxes[0];
   if ( X > MIN( drawX1, drawX2 ) && X < MAX( drawX1, drawX2 ) && Y > MIN( drawY1, drawY2 ) && Y < MAX( drawY1, drawY2 ) ) {
    number_of_pixels_in_zoomed_image++;
   }
  }
 }
 if ( number_of_pixels_in_zoomed_image<16 ) {
  return;
 }
 //////////////////
*/
 // set all histogram values to 0
 for( i= 0; i < 65536; i++ )
  HIST[i]= 0;

 for( i= 0; i < NUM_OF_PIXELS; i++ ) {
  if( im[i] > 0 && im[i] < 65535 ) {
   // Cool it works!!! (Transformation from i to XY)
   Y= 1 + (int)((float)i / (float)naxes[0]);
   X= i + 1 - (Y - 1) * naxes[0];
   if( X > MIN(drawX1, drawX2) && X < MAX(drawX1, drawX2) && Y > MIN(drawY1, drawY2) && Y < MAX(drawY1, drawY2) ) {
    HIST[(long)(im[i] + 0.5)]+= 1;
    if( im[i] > (*max_i) )
     (*max_i)= im[i];
    if( im[i] < (*min_i) )
     (*min_i)= im[i];
   }
  }
 }

 //////////////////////
 // Try the percantage cuts only if the image range is not much smaller than 0 to 65535
 if( (*max_i) < 10.0 ) {

  // set all histogram values to 0
  for( i= 0; i < 65536; i++ ) {
   HIST[i]= 0;
  }

  for( i= 0; i < NUM_OF_PIXELS; i++ ) {
   if( im[i] > 0 && 65535 / 10.0 * im[i] < 65535 ) {
    // Cool it works!!! (Transformation from i to XY)
    Y= 1 + (int)((float)i / (float)naxes[0]);
    X= i + 1 - (Y - 1) * naxes[0];
    if( X > MIN(drawX1, drawX2) && X < MAX(drawX1, drawX2) && Y > MIN(drawY1, drawY2) && Y < MAX(drawY1, drawY2) ) {
     HIST[(long)(65535 / 10.0 * im[i] + 0.5)]+= 1;
     if( im[i] > (*max_i) )
      (*max_i)= im[i];
     if( im[i] < (*min_i) )
      (*min_i)= im[i];
    }
   }
  }

  // find histogram peak
  summa= 0;
  for( i= 0; i < 65535; i++ ) {
   if( summa < HIST[i] ) {
    (*min_i)= MIN((*min_i), (float)i / 65535 * 10.0);
    summa= HIST[i];
   }
  }
  (*min_i)-= (*min_i) * 2 / 3;
  (*min_i)= MAX((*min_i), 0); // do not go for very negatve values - they are likely wrong

  summa= 0;
  //for ( i= 65535; i > 1; i-- ) {
  for( i= 65535; i--; ) {
   summa+= HIST[i];
  }
  limit= (long)(((double)summa - (double)summa * PGFV_CUTS_PERCENT / 100.0) / 2.0);

  summa= 0;
  //for ( i= 65535; i > 1; i-- ) {
  for( i= 65535; i--; ) {
   summa+= HIST[i];

   if( summa >= limit ) {
    (*max_i)= MIN((*max_i), (float)i / 65535 * 10.0);
    break;
   }
  }

  //fprintf( stderr, "DEBUG: image_minmax3() %f %f\n", ( *min_i ), ( *max_i ) );
  return;
 }
 //////////////////////

 for( i= 0; i < 65535; i++ )
  hist_summa+= HIST[i];

 summa= 0;
 for( i= 0, test_i= 0; i < 65535; i++ ) {
  summa+= HIST[i];
  if( summa >= (int)(PGFV_CUTS_PERCENT / 100.0 * (float)hist_summa) ) {
   //(*max_i)=(float)i;
   (*max_i)= (float)test_i;
   break;
  }
  if( HIST[i] != 0 )
   test_i= i;
 }

 summa= 0;
 for( i= 0; i < 65535; i++ ) {
  summa+= HIST[i];
  if( summa >= (int)(2.0 * (1.0 - PGFV_CUTS_PERCENT / 100.0) * (float)hist_summa) ) {
   (*min_i)= (float)i;
   break;
  }
 }

 (*max_i)= MIN((*max_i), 65535); // just in case...

 (*min_i)= MAX((*min_i), 0); // do not go for very negatve values - they are likely wrong

 (*max_i)= MAX((*max_i), (*min_i) + 1); // for the countrate images (like the HST ones)

 //fprintf(stderr,"DEBUG: %lf  %lf\n",(*min_i),(*max_i));

 return;
}

/* 
   Histogram equalization is a method in image processing of contrast adjustment using the image's histogram. 
   See http://en.wikipedia.org/wiki/Histogram_equalization for details.   
*/
void histeq(long NUM_OF_PIXELS, float *im, float *max_i, float *min_i) {
 long i;
 int HIST[65536];
 int NO_OF_PIX_BELOW_I[65536];
 (*max_i)= -9999.0;
 (*min_i)= 9999.0;
 for( i= 0; i < 65536; i++ ) {
  HIST[i]= 0;
  NO_OF_PIX_BELOW_I[i]= 0;
 }
 for( i= 0; i < NUM_OF_PIXELS; i++ ) {
  if( im[i] > (*max_i) )
   (*max_i)= im[i];
  if( im[i] < (*max_i) )
   (*min_i)= im[i];
 }
 for( i= 0; i < NUM_OF_PIXELS; i++ ) {
  HIST[MAX(0, (int)(im[i] + 0.5))]+= 1;
 }
 NO_OF_PIX_BELOW_I[0]= HIST[0];
 for( i= 1; i < 65536; i++ ) {
  NO_OF_PIX_BELOW_I[i]= NO_OF_PIX_BELOW_I[i - 1] + HIST[i];
 }
 for( i= 0; i < NUM_OF_PIXELS; i++ ) {
  im[i]= NO_OF_PIX_BELOW_I[MAX(0, (int)(im[i] + 0.5))] * (*max_i) / NUM_OF_PIXELS;
 }
 return;
}

int myimax(int A, int B) {
 if( A > B )
  return A;
 else
  return B;
}

/*
int myimin( int A, int B ) {
 if ( A < B )
  return A;
 else
  return B;
}
*/

int mymax(float A, float B) {
 if( A > B )
  return trunc(round(A));
 else
  return trunc(round(B));
}

int mymin(float A, float B) {
 if( A < B )
  return trunc(round(A));
 else
  return trunc(round(B));
}

int find_XY_position_of_a_star_on_image_from_vast_format_lightcurve(float *X_known_variable, float *Y_known_variable, char *lightcurvefilename, char *fits_image_name) {
 double jd, mag, merr, x, y, app;
 char string[FILENAME_LENGTH];
 FILE *lightcurvefile;
 lightcurvefile= fopen(lightcurvefilename, "r");
 if( lightcurvefile == NULL ) {
  fprintf(stderr, "No lightcurve file %s\n", lightcurvefilename);
  return 0; // not found
 }
 while( -1 < read_lightcurve_point(lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, NULL) ) {
  if( jd == 0.0 ) {
   continue; // if this line could not be parsed, try the next one
  }
  if( 0 == strncmp(string, fits_image_name, strlen(fits_image_name)) ) {
   fprintf(stderr, "%lf %lf\n", x, y);
   (*X_known_variable)= (float)x;
   (*Y_known_variable)= (float)y;
   fclose(lightcurvefile);
   return 1; // found
  }
 }
 fclose(lightcurvefile);
 fprintf(stderr, "not found\n");
 return 0; // not found, if we are still here
}

void load_markers_for_known_variables(float *markX_known_variable, float *markY_known_variable, int *mark_known_variable_counter, char *fits_image_name) {
 FILE *list_of_known_vars_file;
 char full_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char lightcurvefilename[OUTFILENAME_LENGTH];
 char string_with_star_id_and_info[2048];
 list_of_known_vars_file= fopen("vast_list_of_previously_known_variables.log", "r");
 if( list_of_known_vars_file == NULL ) {
  (*mark_known_variable_counter)= 0;
  return;
 }
 fprintf(stderr, "Loading known variables from vast_list_of_previously_known_variables.log\n");
 while( NULL != fgets(full_string, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, list_of_known_vars_file) ) {
  sscanf(full_string, "%s %[^\t\n]", lightcurvefilename, string_with_star_id_and_info);
  fprintf(stderr, "Loading known variable %s ... ", lightcurvefilename);
  if( 1 == find_XY_position_of_a_star_on_image_from_vast_format_lightcurve(&markX_known_variable[(*mark_known_variable_counter)], &markY_known_variable[(*mark_known_variable_counter)], lightcurvefilename, fits_image_name) ) {
   (*mark_known_variable_counter)++;
  }
 }
 fprintf(stderr, "Loaded %d known variables.\n", (*mark_known_variable_counter));
 return;
}

void load_markers_for_autocandidate_variables(float *markX_known_variable, float *markY_known_variable, int *mark_known_variable_counter, char *fits_image_name) {
 FILE *list_of_known_vars_file;
 char full_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char lightcurvefilename[OUTFILENAME_LENGTH];
 char string_with_star_id_and_info[2048];
 list_of_known_vars_file= fopen("vast_autocandidates.log", "r");
 if( list_of_known_vars_file == NULL ) {
  (*mark_known_variable_counter)= 0;
  return;
 }
 fprintf(stderr, "Loading autocandidate variables from vast_autocandidates.log\n");
 while( NULL != fgets(full_string, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, list_of_known_vars_file) ) {
  sscanf(full_string, "%s %[^\t\n]", lightcurvefilename, string_with_star_id_and_info);
  fprintf(stderr, "Loading candidate variable %s ... ", lightcurvefilename);
  if( 1 == find_XY_position_of_a_star_on_image_from_vast_format_lightcurve(&markX_known_variable[(*mark_known_variable_counter)], &markY_known_variable[(*mark_known_variable_counter)], lightcurvefilename, fits_image_name) ) {
   (*mark_known_variable_counter)++;
  }
 }
 fprintf(stderr, "Loaded %d candidate variables.\n", (*mark_known_variable_counter));
 return;
}

int main(int argc, char **argv) {

 /* For FITS file reading */
 fitsfile *fptr; /* pointer to the FITS file; defined in fitsio.h */
 //long  fpixel = 1, naxis = 2, nelements, exposure;
 long naxes[2];
 int status= 0;
 int bitpix;
 int anynul= 0;
 //int nullval=0;
 float nullval= 0.0;
 unsigned char nullval_uchar= 0;
 unsigned short nullval_ushort= 0;
 unsigned int nullval_uint= 0;
 double nullval_double= 0.0;
 unsigned char *image_array_uchar;
 unsigned short *image_array_ushort;
 unsigned int *image_array_uint;
 double *image_array_double;
 float *real_float_array;
 float *float_array;
 float *float_array2;
 //long x,y;
 int i;
 /* PGPLOT vars */
 //float current_color=0.0;
 float curX, curY, curX2, curY2;
 char curC= 'R';
 float tr[6];
 tr[0]= 0;
 tr[1]= 1;
 tr[2]= 0;
 tr[3]= 0;
 tr[4]= 0;
 tr[5]= 1;
 int drawX1, drawX2, drawY1, drawY2, drawX0, drawY0;
 float min_val;
 float max_val;

 int hist_trigger= 0;
 int mark_trigger= 0;

 float markX= 0.0;
 float markY= 0.0;
 //float finder_char_pix_around_the_target= 10.0; // default thumbnail image size for transient search
 float finder_char_pix_around_the_target= 20.0; // default thumbnail image size for transient search

 /* new fatures */
 //int buf,v_trigger=0,b_trigger=0;
 int buf;
 //int j;
 float axis_ratio;
 double razmer_x, razmer_y;

 char fits_image_name[FILENAME_LENGTH];
 int match_mode= 0;
 //char sex_command_string[2048];
 double APER= 0.0; // just reset it

 int bad_size;

 /* Sex Cat */
 FILE *catfile;
 //double MUSOR;
 //int intMUSOR;
 //int iMUSOR;
 float *sexX= NULL;
 float *sexY= NULL;
 double *sexFLUX= NULL;
 double *sexFLUX_ERR= NULL;
 double *sexMAG= NULL;
 double *sexMAG_ERR= NULL;
 int *sexNUMBER= NULL;
 int *sexFLAG= NULL;
 int *extFLAG= NULL;
 double *psfCHI2= NULL;

 double *sexA_IMAGE= NULL;
 double *sexERRA_IMAGE= NULL;
 double *sexB_IMAGE= NULL;
 double *sexERRB_IMAGE= NULL;

 int sex= 0;
 int marker_counter;

 float *sexX_viewed= NULL;
 float *sexY_viewed= NULL;
 int sex_viewed_counter;

 float *markX_known_variable= NULL;
 float *markY_known_variable= NULL;
 int mark_known_variable_counter;
 float *markX_autocandidate_variable= NULL;
 float *markY_autocandidate_variable= NULL;
 int mark_autocandidate_variable_counter;

 int use_north_east_marks= 1;
 int use_labels= 1;
 int use_datestringinsideimg= 0;
 int use_imagesizestringinsideimg= 0;

 /* Match File */
 FILE *matchfile;
 char RADEC[1024];
 int match_input= 0;
 //double HH,HM,HS,DD,DM,DS;
 //char syscommand[1024];

 /* Calib mode */
 FILE *calibfile;
 double tmp_APER= 0.0;
 char imagefilename[1024 + FILENAME_LENGTH];
 char system_command[1024 + FILENAME_LENGTH];
 int N;
 double catalog_mag;
 char filtered_string[1024 + FILENAME_LENGTH];
 int ii, jj, first_number_flag;

 /* For time information from the FITS header */
 double JD;
 double dimX;
 double dimY;
 char stderr_output[2 * 1024 + 2 * FILENAME_LENGTH];
 char log_output[1024 + FILENAME_LENGTH];

 int timesys= 0;
 int convert_timesys_to_TT= 0;

 int draw_star_markers= 1;
 int aperture_change= 0;

 double median_class_star;
 //double sigma_class_star;

 static float bw_l[]= {-0.5, 0.0, 0.5, 1.0, 1.5, 2.0};
 static float bw_r[]= {0.0, 0.0, 0.5, 1.0, 1.0, 1.0};
 static float bw_g[]= {0.0, 0.0, 0.5, 1.0, 1.0, 1.0};
 static float bw_b[]= {0.0, 0.0, 0.5, 1.0, 1.0, 1.0};

 char sextractor_catalog[FILENAME_LENGTH];

 int finding_chart_mode= 0; // =1 draw finding chart to an image file instead of interactive plotting

 int inverted_X_axis= 0;
 int inverted_Y_axis= 1; // start with inverted Y axis

 char sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT];
 int external_flag; // flag image info, if available
                    // double double_external_flag;
 double psf_chi2;
 // char external_flag_string[256];

 int use_xy2sky= 2; // 0 - no, 1 - yes, 2 - don't know
 int xy2sky_return_value;

 if( 0 == strcmp("make_finding_chart", basename(argv[0])) ) {
  fprintf(stderr, "Plotting finding chart...\n");
  finding_chart_mode= 1;
  //mark_trigger= 1;
 }

 if( 0 == strcmp("fits2png", basename(argv[0])) ) {
  fprintf(stderr, "Plotting finding chart with no labels...\n");
  finding_chart_mode= 1;
  use_north_east_marks= 0;
  use_labels= 0;
  //mark_trigger= 1;
 }

 /* Reading file which defines rectangular regions we want to exclude */
 float cpgline_tmp_x[2];
 float cpgline_tmp_y[2];
 double X1[500], Y1[500], X2[500], Y2[500];
 int N_bad_regions= 0;
 read_bad_lst(X1, Y1, X2, Y2, &N_bad_regions);

 int use_ds9= 0; // if 1 - use ds9 instead of pgplot to display an image
 pid_t pid= getpid();
 char ds9_region_filename[1024];

 ////////////
 FILE *manymarkersfile;
 int manymrkerscounter;
 float manymarkersX[1024];
 float manymarkersY[1024];
 char manymarkersstring[2048];
 ////////////

 char fov_string[1024];

 if( 0 != strcmp("select_star_on_reference_image", basename(argv[0])) ) {
  if( argc == 1 ) {
   fprintf(stderr, "Usage:\n%s FITSIMAGE.fit\nor\n%s FITSIMAGE.fit X Y\nor\n%s FITSIMAGE.fit RA DEC\n\n", argv[0], argv[0], argv[0]);
   // Do nothing else: if no arguments are provided - display the reference image
   //get_ref_image_name(fits_image_name);
   //return 1;
  }
 } else {
  // This is star selection on reference image mode
  match_mode= 1;
  get_ref_image_name(fits_image_name);
 }

 double fixed_aperture= 0.0;

 // for nanosleep()
 struct timespec requested_time;
 struct timespec remaining;
 requested_time.tv_sec= 0;
 requested_time.tv_nsec= 100000000;

 //
 int is_this_an_hla_image= 0; // 0 - no;  1 - yes; needed only to make proper labels

 //
 int is_this_north_up_east_left_image= 0; // For N/E labels on the finding chart

 // Dummy vars
 // int star_number_in_sextractor_catalog;
 // double flux_adu;
 // double flux_adu_err;
 // double mag;
 // double sigma_mag;
 double position_x_pix;
 double position_y_pix;
 // double a_a;
 // double a_a_err;
 // double a_b;
 // double a_b_err;
 // int sextractor_flag;

 /* Options for getopt() */
 char *cvalue= NULL;

 const char *const shortopt= "a:w:9sdnl";
 const struct option longopt[]= {
     {"apeture", 1, NULL, 'a'}, {"width", 1, NULL, 'w'}, {"ds9", 0, NULL, '9'}, {"imgsizestringinsideimg", 0, NULL, 's'}, {"datestringinsideimg", 0, NULL, 'd'}, {"nonortheastmarks", 0, NULL, 'n'}, {"nolabels", 0, NULL, 'l'}, {NULL, 0, NULL, 0}}; //NULL string must be in the end
 int nextopt;
 while( nextopt= getopt_long(argc, argv, shortopt, longopt, NULL), nextopt != -1 ) {
  switch( nextopt ) {
  case 'a':
   cvalue= optarg;
   fixed_aperture= atof(cvalue);
   fprintf(stdout, "opt 'a': Using fixed aperture %.1lf pix. in diameter!\n", fixed_aperture);
   if( fixed_aperture < 1.0 ) {
    fprintf(stderr, "ERROR: the specified fixed aperture dameter is out of the expected range!\n");
    return 1;
   }
   break;
  case 'w':
   cvalue= optarg;
   finder_char_pix_around_the_target= (float)atof(cvalue);
   fprintf(stdout, "opt 'w': Plotting %.1lf pix. around the target!\n", finder_char_pix_around_the_target);
   if( finder_char_pix_around_the_target < 1.0 ) {
    fprintf(stderr, "ERROR: the specified finder chart widt is out of the expected range!\n");
    return 1;
   }
   break;
  case '9':
   use_ds9= 1;
   fprintf(stdout, "opt '9': Using ds9 to display images!\n");
   break;
  case 's':
   use_imagesizestringinsideimg= 1;
   fprintf(stdout, "opt 's': image size will be displayed inside the image!\n");
   break;
  case 'd':
   use_datestringinsideimg= 1;
   fprintf(stdout, "opt 'd': observing date will be displayed inside the image!\n");
   break;
  case 'n':
   use_north_east_marks= 0;
   fprintf(stdout, "opt 'n': No North-East marks will be ploted!\n");
   break;
  case 'l':
   use_labels= 0;
   fprintf(stdout, "opt 'l': No axes labels will be ploted!\n");
   break;
  case '?':
   if( optopt == 'a' ) {
    fprintf(stderr, "Option -%c requires an argument: fixed aperture size in pix.!\n", optopt);
    exit(1);
   }
   if( optopt == 'w' ) {
    fprintf(stderr, "Option -%c requires an argument: finder chart size in pix.!\n", optopt);
    exit(1);
   }
   break;
  case -1:
   fprintf(stderr, "That's all\n");
   break;
  }
 }
 optind--; //!!!

 //
 if( use_labels == 1 && use_datestringinsideimg == 1 ) {
  fprintf(stderr, "We don't want the observing time string to be dispalyed two times - disabling the in-the-image display!\n");
  use_datestringinsideimg= 0;
 }
 //

 if( argc - optind == 5 ) {
  APER= atof(argv[optind + 4]);
 }

 if( match_mode != 1 && argc != 1 ) {
  strcpy(fits_image_name, argv[optind + 1]);
 } else {
  /* Get reference file name from log */
  get_ref_image_name(fits_image_name);
 }

 replace_file_with_symlink_if_filename_contains_white_spaces(fits_image_name);

 if( argc - optind >= 4 ) {
  // Now we need to figure out if the input values are pixel or celestial coordinates
  // Don't do this check if this is fits2png
  if( finding_chart_mode != 1 && use_labels != 0 ) {
   sky2xy(fits_image_name, argv[optind + 2], argv[optind + 3], &markX, &markY);
  } else {
   markX= (float)atof(argv[optind + 2]);
   markY= (float)atof(argv[optind + 3]);
  }
  if( markX > 0.0 && markY > 0.0 ) {
   mark_trigger= 1;
   fprintf(stderr, "Putting mark on pixel position %lf %lf\n", markX, markY);
  } else {
   fprintf(stderr, "The pixel position %lf %lf is outside the image!\n", markX, markY);
  }
 }

 // Read manymarkers file if there is one
 manymrkerscounter= 0;
 manymarkersfile= fopen("vast_manymarkersfile.log", "r");
 if( manymarkersfile != NULL ) {
  while( -1 < fscanf(manymarkersfile, "%f %f %[^\t\n]", &manymarkersX[manymrkerscounter], &manymarkersY[manymrkerscounter], manymarkersstring) )
   manymrkerscounter++;
  fprintf(stderr, "vast_manymarkersfile.log - %d markers\n", manymrkerscounter);
 }

 if( 0 == strcasecmp(fits_image_name, "calib") ) {
  // Magnitude calibration mode
  match_mode= 2;
 }

 if( match_mode == 2 ) {
  // Remove old calib.txt
  matchfile= fopen("calib.txt", "r");
  if( NULL != matchfile ) {
   fclose(matchfile);
   //system("rm -f calib.txt");
   unlink("calib.txt");
  }

  // Allocate memory for the arrays
  sexX= (float *)malloc(MAX_NUMBER_OF_STARS * sizeof(float));
  if( sexX == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexX\n");
   exit(1);
  };
  sexY= (float *)malloc(MAX_NUMBER_OF_STARS * sizeof(float));
  if( sexY == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexY\n");
   exit(1);
  };
  sexMAG= (double *)malloc(MAX_NUMBER_OF_STARS * sizeof(double));
  if( sexMAG == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexMAG\n");
   exit(1);
  };
  sexMAG_ERR= (double *)malloc(MAX_NUMBER_OF_STARS * sizeof(double));
  if( sexMAG_ERR == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexMAG_ERR\n");
   exit(1);
  };
  sexNUMBER= (int *)malloc(MAX_NUMBER_OF_STARS * sizeof(int));
  if( sexNUMBER == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexNUMBER\n");
   exit(1);
  };
  marker_counter= 0;

  /* Get reference file name from log */
  get_ref_image_name(fits_image_name);

  /* Read data.m_sigma but select only stars detected on the reference frame */
  matchfile= fopen("data.m_sigma", "r");
  while( -1 < fscanf(matchfile, "%lf %lf %f %f %s", &sexMAG[sex], &sexMAG_ERR[sex], &sexX[sex], &sexY[sex], RADEC) ) {
   calibfile= fopen(RADEC, "r");
   if( calibfile != NULL ) {
    //fscanf(calibfile,"%lf %lf %lf %lf %lf %lf %s",&MUSOR,&MUSOR,&MUSOR,&MUSOR,&MUSOR,&tmp_APER,imagefilename);
    if( 2 > fscanf(calibfile, "%*f %*f %*f %*f %*f %lf %s", &tmp_APER, imagefilename) ) {
     fprintf(stderr, "ERROR parsing %s\n", RADEC);
    }
    fclose(calibfile);
    if( 0 == strcmp(imagefilename, fits_image_name) ) {
     // Get number of observations for correct error estimation
     N= count_lines_in_ASCII_file(RADEC);
     /*
     sprintf( system_command, "grep -c \" \" %s > grep.tmp", RADEC );
     if ( 0 != system( system_command ) ) {
      fprintf( stderr, "ERROR running  %s\n", system_command );
     }
     calibfile= fopen( "grep.tmp", "r" );
     if ( 1 > fscanf( calibfile, "%d", &N ) ) {
      fprintf( stderr, "ERROR parsing grep.tmp\n" );
     }
     fclose( calibfile );
     //system("rm -f grep.tmp");
     unlink( "grep.tmp" );
     */
     sexMAG_ERR[sex]= sexMAG_ERR[sex] / sqrt(N - 1);
     // done with errors
     // Note the star name
     sscanf(RADEC, "out%d.dat", &sexNUMBER[sex]);
     // remember aperture size, increase counter */
     APER= tmp_APER;
     sex++;
    }
   }
  }
  fclose(matchfile);
  sex--; /* We can't be sure that the last star is visible on the reference frame so we just drop it */
 }

 /* 
 if( 0==strcasecmp(fits_image_name,"match") ){
  match_mode=1;
  system("rm -f match.txt");
  get_ref_image_name(fits_image_name);
 }
*/

 if( 0 == strcasecmp(fits_image_name, "match") ) {
  fprintf(stderr, "The manual star-matching mode is no longer supported, sorry!\n");
  return 1;
 }

 if( 0 == strcmp("sextract_single_image", basename(argv[0])) ) {
  match_mode= 3;
 }

 if( 0 == strcmp("select_comparison_stars", basename(argv[0])) ) {
  match_mode= 4;

  // Remove old calib.txt
  matchfile= fopen("calib.txt", "r");
  if( NULL != matchfile ) {
   fclose(matchfile);
   unlink("calib.txt");
  }
  // Remove old manually_selected_comparison_stars.lst
  matchfile= fopen("manually_selected_comparison_stars.lst", "r");
  if( NULL != matchfile ) {
   fclose(matchfile);
   unlink("manually_selected_comparison_stars.lst");
  }

 } // if ( 0 == strcmp( "select_comparison_stars", basename( argv[0] ) ) ) {

 //fprintf(stderr,"DEBUG-5\n");

 // WTF is this????
 if( 0 == strcasecmp(fits_image_name, "detect") ) {
  if( argc - optind < 3 ) {
   fprintf(stderr, "Usage: ./pgfv detect image.fit\n");
   exit(1);
  }
  strcpy(fits_image_name, argv[optind + 2]);
  match_mode= 3;
 }
 if( match_mode == 3 ) {
  fprintf(stderr, "Entering single image reduction mode.\nProcessing image %s\n", fits_image_name);
  fprintf(stderr, "Use '+' or '-' to increase or decrease aperture size.\n");
  fprintf(stderr, "\E[34;47mTo calibrate magnitude scale press '2'\E[33;00m\n");

  /* Remove old calib.txt in case we'll want a magnitude calibration */
  //system("rm -f calib.txt");
  calibfile= fopen("calib.txt", "r");
  if( NULL != calibfile ) {
   fclose(calibfile);
   unlink("calib.txt");
  }
 }

 //fprintf(stderr,"DEBUG-4\n");

 /// handling HLA images
 if( mark_trigger == 1 ) {
  if( 0 == download_hla_image_if_this_is_it_and_modify_imagename(fits_image_name, markX, markY) ) {
   // This has to change if the cutout is not 64pix
   markX= 32.0;
   markY= 32.0;
   APER= 0.0;
   //
   is_this_an_hla_image= 1;
  }
 }

 /* Get time and frame size information from the FITS header */
 if( 0 != fitsfile_read_check(fits_image_name) ) {
  fprintf(stderr, "\nERROR: the input file %s does not appear to be a readable FITS image!\n", fits_image_name);
  return 1;
 }
 int param_nojdkeyword= 0; // Temporary fix!!! pgfv cannot accept the --nojdkeyword parameter yet, only the main program vast understands it
 gettime(fits_image_name, &JD, &timesys, convert_timesys_to_TT, &dimX, &dimY, stderr_output, log_output, param_nojdkeyword, 0);
 if( strlen(stderr_output) < 10 ) {
  fprintf(stderr, "Warning after running gettime(): stderr_output is suspiciously short:\n");
  fprintf(stderr, "#%s#\n", stderr_output);
 }
 stderr_output[strlen(stderr_output) - 1]= '\0'; /* Remove \n at the end of line */
 // Special case of HLA images with no proper date
 if( is_this_an_hla_image == 1 ) {
  stderr_output[0]= '\0';
 }
 //
 if( finding_chart_mode == 1 ) {
  is_this_north_up_east_left_image= check_if_this_fits_image_is_north_up_east_left(fits_image_name);
 }

 //fprintf(stderr,"DEBUG-3\n");

 if( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
  // Allocate memory for the array of known variables markers
  markX_known_variable= (float *)malloc(MAX_NUMBER_OF_STARS * sizeof(float));
  if( markX_known_variable == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for markX_known_variable\n");
   exit(1);
  };
  markY_known_variable= (float *)malloc(MAX_NUMBER_OF_STARS * sizeof(float));
  if( markY_known_variable == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for markY_known_variable\n");
   exit(1);
  };
  mark_known_variable_counter= 0; // initialize
  load_markers_for_known_variables(markX_known_variable, markY_known_variable, &mark_known_variable_counter, fits_image_name);
  //
  if( mark_known_variable_counter == 0 ) {
   // Free memory for the array of known variables markers, as non known variables were loaded
   free(markX_known_variable);
   free(markY_known_variable);
  }
  fprintf(stderr, "Loaded %d known variables.\n", mark_known_variable_counter);

  // Allocate memory for the array of autocandidate variables markers
  markX_autocandidate_variable= (float *)malloc(MAX_NUMBER_OF_STARS * sizeof(float));
  if( markX_autocandidate_variable == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for markX_autocandidate_variable\n");
   exit(1);
  };
  markY_autocandidate_variable= (float *)malloc(MAX_NUMBER_OF_STARS * sizeof(float));
  if( markY_autocandidate_variable == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for markY_autocandidate_variable\n");
   exit(1);
  };
  mark_autocandidate_variable_counter= 0; // initialize
  // TBA: load autocandidate variables
  load_markers_for_autocandidate_variables(markX_autocandidate_variable, markY_autocandidate_variable, &mark_autocandidate_variable_counter, fits_image_name);
  //
  if( mark_autocandidate_variable_counter == 0 ) {
   // Free memory for the array of autocandidate variables markers, as non autocandidate variables were loaded
   free(markX_autocandidate_variable);
   free(markY_autocandidate_variable);
  }
  fprintf(stderr, "Loaded %d candidate variables.\n", mark_autocandidate_variable_counter);
 }

 //fprintf(stderr,"DEBUG-3a\n");

 if( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
  //fprintf(stderr,"DEBUG-2\n");
  /* Check if the SExtractor executable (named "sex") is present in $PATH */
  /* Update PATH variable to make sure the local copy of SExtractor is there */
  char pathstring[8192];
  strncpy(pathstring, getenv("PATH"), 8192 - 1 - 8);
  pathstring[8192 - 1 - 8]= '\0';
  strncat(pathstring, ":lib/bin", 9);
  pathstring[8192 - 1]= '\0';
  setenv("PATH", pathstring, 1);
  if( 0 != system("lib/look_for_sextractor.sh") ) {
   fprintf(stderr, "ERROR running  lib/look_for_sextractor.sh\n");
  }
  //fprintf(stderr," *** Running SExtractor on %s ***\n",fits_image_name);
  // Star match mode (create WCS) or Single image reduction mode
  //APER=autodetect_aperture(fits_image_name, sextractor_catalog, 0, 0, fixed_aperture, 1, dimX, dimY);
  APER= autodetect_aperture(fits_image_name, sextractor_catalog, 0, 0, fixed_aperture, dimX, dimY, 2);
  if( fixed_aperture != 0.0 ) {
   APER= fixed_aperture;
  }

  //fprintf(stderr,"DEBUG-1\n");

  sexX_viewed= (float *)malloc(MAX_NUMBER_OF_STARS * sizeof(float));
  if( sexX_viewed == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexX_viewed\n");
   exit(1);
  };
  sexY_viewed= (float *)malloc(MAX_NUMBER_OF_STARS * sizeof(float));
  if( sexY_viewed == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexY_viewed\n");
   exit(1);
  };
  sex_viewed_counter= 0; // initialize

  sexX= (float *)malloc(MAX_NUMBER_OF_STARS * sizeof(float));
  if( sexX == NULL ) {
   fprintf(stderr, "ERROR0: Couldn't allocate memory for sexX\n");
   exit(1);
  };
  sexY= (float *)malloc(MAX_NUMBER_OF_STARS * sizeof(float));
  if( sexY == NULL ) {
   fprintf(stderr, "ERROR0: Couldn't allocate memory for sexY\n");
   exit(1);
  };
  sexFLUX= (double *)malloc(MAX_NUMBER_OF_STARS * sizeof(double));
  if( sexFLUX == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexFLUX\n");
   exit(1);
  };
  sexFLUX_ERR= (double *)malloc(MAX_NUMBER_OF_STARS * sizeof(double));
  if( sexFLUX_ERR == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexFLUX_ERR\n");
   exit(1);
  };
  sexMAG= (double *)malloc(MAX_NUMBER_OF_STARS * sizeof(double));
  if( sexMAG == NULL ) {
   fprintf(stderr, "ERROR0: Couldn't allocate memory for sexMAG\n");
   exit(1);
  };
  sexMAG_ERR= (double *)malloc(MAX_NUMBER_OF_STARS * sizeof(double));
  if( sexMAG_ERR == NULL ) {
   fprintf(stderr, "ERROR0: Couldn't allocate memory for sexFLUX\n");
   exit(1);
  };
  sexNUMBER= (int *)malloc(MAX_NUMBER_OF_STARS * sizeof(int));
  if( sexNUMBER == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexNUMBER\n");
   exit(1);
  };
  sexFLAG= (int *)malloc(MAX_NUMBER_OF_STARS * sizeof(int));
  if( sexFLAG == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexFLAG\n");
   exit(1);
  };
  extFLAG= (int *)malloc(MAX_NUMBER_OF_STARS * sizeof(int));
  if( extFLAG == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for extFLAG\n");
   exit(1);
  };
  psfCHI2= (double *)malloc(MAX_NUMBER_OF_STARS * sizeof(double));
  if( psfCHI2 == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for psfCHI2\n");
   exit(1);
  };

  sexA_IMAGE= (double *)malloc(MAX_NUMBER_OF_STARS * sizeof(double));
  if( sexA_IMAGE == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexA_image\n");
   exit(1);
  };
  sexERRA_IMAGE= (double *)malloc(MAX_NUMBER_OF_STARS * sizeof(double));
  if( sexERRA_IMAGE == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexERRA_IMAGE\n");
   exit(1);
  };
  sexB_IMAGE= (double *)malloc(MAX_NUMBER_OF_STARS * sizeof(double));
  if( sexB_IMAGE == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexB_IMAGE\n");
   exit(1);
  };
  sexERRB_IMAGE= (double *)malloc(MAX_NUMBER_OF_STARS * sizeof(double));
  if( sexERRB_IMAGE == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for sexERRB_IMAGE\n");
   exit(1);
  };

  //
  memset(sexX_viewed, 0, MAX_NUMBER_OF_STARS * sizeof(float));
  memset(sexY_viewed, 0, MAX_NUMBER_OF_STARS * sizeof(float));
  memset(sexX, 0, MAX_NUMBER_OF_STARS * sizeof(float));
  memset(sexY, 0, MAX_NUMBER_OF_STARS * sizeof(float));
  memset(sexFLUX, 0, MAX_NUMBER_OF_STARS * sizeof(double));
  memset(sexFLUX_ERR, 0, MAX_NUMBER_OF_STARS * sizeof(double));
  memset(sexMAG, 0, MAX_NUMBER_OF_STARS * sizeof(double));
  memset(sexMAG_ERR, 0, MAX_NUMBER_OF_STARS * sizeof(double));
  memset(sexNUMBER, 0, MAX_NUMBER_OF_STARS * sizeof(int));
  memset(sexFLAG, 0, MAX_NUMBER_OF_STARS * sizeof(int));
  memset(extFLAG, 0, MAX_NUMBER_OF_STARS * sizeof(int));
  memset(psfCHI2, 0, MAX_NUMBER_OF_STARS * sizeof(double));
  memset(sexA_IMAGE, 0, MAX_NUMBER_OF_STARS * sizeof(double));
  memset(sexERRA_IMAGE, 0, MAX_NUMBER_OF_STARS * sizeof(double));
  memset(sexERRA_IMAGE, 0, MAX_NUMBER_OF_STARS * sizeof(double));
  memset(sexB_IMAGE, 0, MAX_NUMBER_OF_STARS * sizeof(double));
  memset(sexERRB_IMAGE, 0, MAX_NUMBER_OF_STARS * sizeof(double));
  //

  catfile= fopen(sextractor_catalog, "r");
  if( NULL == catfile ) {
   fprintf(stderr, "ERROR! Cannot open sextractor catalog file %s for reading!\n", sextractor_catalog);
   exit(1);
  }
  //while( -1<fscanf(catfile, "%d %lf %lf %lf %lf %f %f %lf %lf %lf %lf %d\n", &sexNUMBER[sex], &sexFLUX[sex], &sexFLUX_ERR[sex], &sexMAG[sex], &sexMAG_ERR[sex], &sexX[sex], &sexY[sex], &sexA_IMAGE[sex], &sexERRA_IMAGE[sex], &sexB_IMAGE[sex], &sexERRB_IMAGE[sex], &sexFLAG[sex]) ){
  //fprintf(stderr,"DEBUG01\n");
  while( NULL != fgets(sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, catfile) ) {
   //fprintf(stderr,"DEBUG02 sex=%d\n",sex);
   sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT - 1]= '\0'; // just in case
   external_flag= 0;
   //external_flag_string[0]='\0';
   if( 0 != parse_sextractor_catalog_string(sextractor_catalog_string, &sexNUMBER[sex], &sexFLUX[sex], &sexFLUX_ERR[sex], &sexMAG[sex], &sexMAG_ERR[sex], &position_x_pix, &position_y_pix, &sexA_IMAGE[sex], &sexERRA_IMAGE[sex], &sexB_IMAGE[sex], &sexERRB_IMAGE[sex], &sexFLAG[sex], &external_flag, &psf_chi2, NULL) ) {
    fprintf(stderr, "WARNING: problem occurred while parsing SExtractor catalog %s\nThe offending line is:\n%s\n", sextractor_catalog, sextractor_catalog_string);
    continue;
   }
   // Do not display saturated stars in the magnitude calibration mode
   if( match_mode == 0 ) {
    if( sexFLAG[sex] >= 4 ) {
     continue;
    }
   }
   //
   sexX[sex]= position_x_pix;
   sexY[sex]= position_y_pix;
   //if( 12>sscanf(sextractor_catalog_string, "%d %lf %lf %lf %lf %f %f %lf %lf %lf %lf %d %[^\t\n]\n", &sexNUMBER[sex], &sexFLUX[sex], &sexFLUX_ERR[sex], &sexMAG[sex], &sexMAG_ERR[sex], &sexX[sex], &sexY[sex], &sexA_IMAGE[sex], &sexERRA_IMAGE[sex], &sexB_IMAGE[sex], &sexERRB_IMAGE[sex], &sexFLAG[sex], external_flag_string) ){
   // fprintf(stderr,"WARNING: problem occurred while parsing SExtractor catalog %s\nThe offending line is:\n%s\n",sextractor_catalog,sextractor_catalog_string);
   // continue;
   //}
   /*
   // Now this is some crazy stuff:
   // The last columns of the SExtractor catalog file might be:
   // ... flags
   // ... flags external_flags
   // ... flags external_flags psf_fitting_chi2
   // ... flags psf_fitting_chi2
   // Below we try to handle each of the four possibilities
   //
   // if these are not just flags
   // (but make sure we perform the tese only on a line wit ha good measurement)
   if( strlen(external_flag_string)>0 && sexFLUX[sex]>0.0 && sexMAG[sex]!=99.0000 ){
    // if these are not flags external_flags psf_fitting_chi2
    if( 2!=sscanf(external_flag_string,"%lf %lf",&double_external_flag,&psf_chi2) ){
     // Decide between "flags external_flags" and "flags psf_fitting_chi2"
     for(ii=0,jj=0;ii<(int)strlen(external_flag_string);ii++){
      if( external_flag_string[ii]=='.' || external_flag_string[ii]=='e' ){jj=1;break;} // assume that a decimal point indicates psf_chi2 rather than external_flag that is expected be 0 or 1 only
     }
     if( jj==0 ){
      // "flags external_flags" case
      psf_chi2=1.0; // no PSF fitting results
      if( 1!=sscanf(external_flag_string,"%lf",&double_external_flag) ){
       double_external_flag=0.0; // no external flag image used
      }
     }
     else{
      // "flags psf_fitting_chi2" case
      double_external_flag=0.0; // no external flag image used
      if( 1!=sscanf(external_flag_string,"%lf",&psf_chi2) ){
       psf_chi2=1.0; // no PSF fitting results
      }
     }
    } // if( 2!=sscanf(external_flag_string,"%lf %lf",&double_external_flag,&psf_chi2) ){
    external_flag=(int)double_external_flag;
   }
   else{
    psf_chi2=1.0; // no PSF fitting results
    external_flag=0; // no external flag image used
   }
   */

   //if( strlen(external_flag_string)>0 ){
   // if( 1!=sscanf(external_flag_string,"%d",&external_flag) ){
   //  external_flag=0; // no external flag image used
   // }
   //}
   //else
   // external_flag=0; // no external flag image used
   extFLAG[sex]= external_flag;
   psfCHI2[sex]= psf_chi2;
   //fprintf(stderr,"\n#%s#\n%d %lf %lf %lf %lf %f %f %lf %lf %lf %lf %d\n",sextractor_catalog_string,  sexNUMBER[sex], sexFLUX[sex], sexFLUX_ERR[sex], sexMAG[sex], sexMAG_ERR[sex], sexX[sex], sexY[sex], sexA_IMAGE[sex], sexERRA_IMAGE[sex], sexB_IMAGE[sex], sexERRB_IMAGE[sex], sexFLAG[sex]);
   sex++;
  }
  fclose(catfile);

  // if we use ds9 to display an image
  if( use_ds9 == 1 ) {
   // prepare the ds9 region file
   sprintf(ds9_region_filename, "ds9_%d_tmp.reg", pid);
   catfile= fopen(ds9_region_filename, "w");
   fprintf(catfile, "# Region file format: DS9 version 4.0\n# Filename: %s\nglobal color=green font=\"sans 8 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source\nimage\n", fits_image_name);
   for( ; sex--; )
    fprintf(catfile, "circle(%.3lf,%.3lf,%.1lf)\n# text(%.3lf,%.3lf) text={%d}\n", sexX[sex], sexY[sex], APER / 2.0, sexX[sex], sexY[sex] - APER, sexNUMBER[sex]);
   fclose(catfile);

   // execute the system command to run ds9
   fprintf(stderr, "Starting DS9 FITS image viewer...\n");
   sprintf(stderr_output, "ds9 %s -region %s -xpa no ; rm -f %s\n", fits_image_name, ds9_region_filename, ds9_region_filename);
   fprintf(stderr, "%s", stderr_output);
   if( 0 != system(stderr_output) ) {
    fprintf(stderr, "ERROR runnning  %s\n", stderr_output);
   }

   // free the arrays
   free(sexX);
   free(sexY);
   free(sexFLUX);
   free(sexFLUX_ERR);
   free(sexMAG);
   free(sexMAG_ERR);
   free(sexNUMBER);
   free(sexFLAG);
   free(sexA_IMAGE);
   free(sexERRA_IMAGE);
   free(sexB_IMAGE);
   free(sexERRB_IMAGE);
   // exit
   return 0;
  }
 }

 //fprintf(stderr,"DEBUG-3b\n");

 // Check if we are asked to start ds9 instead of the normal PGPLOT interface
 if( use_ds9 == 1 ) {
  // execute the system command to run ds9
  fprintf(stderr, "Starting DS9 FITS image viewer...\n");
  sprintf(stderr_output, "ds9 %s \n", fits_image_name);
  fprintf(stderr, "%s", stderr_output);
  if( 0 != system(stderr_output) ) {
   fprintf(stderr, "ERROR running  %s\n", stderr_output);
  }
  return 0;
 }

 //fprintf(stderr,"DEBUG-3c\n");

 if( 0 != fitsfile_read_check(fits_image_name) ) {
  return 1;
 }
 //fprintf(stderr,"DEBUG-3d\n");
 //fits_open_file(&fptr, fits_image_name, 0 , &status);
 fits_open_image(&fptr, fits_image_name, 0, &status);
 if( status != 0 ) {
  fprintf(stderr, "ERROR opening %s\n", fits_image_name);
  return 1;
 }
 fits_get_img_type(fptr, &bitpix, &status);
 fits_read_key(fptr, TLONG, "NAXIS1", &naxes[0], NULL, &status);
 fits_read_key(fptr, TLONG, "NAXIS2", &naxes[1], NULL, &status);
 fprintf(stderr, "Image: %ldx%ld pixels, BITPIX data type code: %d\n", naxes[0], naxes[1], bitpix);
 if( naxes[0] * naxes[1] <= 0 ) {
  fprintf(stderr, "ERROR: Trying allocate zero or negative sized array\n");
  exit(1);
 };
 float_array= malloc(naxes[0] * naxes[1] * sizeof(float));
 if( float_array == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for float_array\n");
  exit(1);
 };
 real_float_array= malloc(naxes[0] * naxes[1] * sizeof(float));
 if( real_float_array == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for real_float_array\n");
  exit(1);
 };

 // 8 bit image
 if( bitpix == 8 ) {
  image_array_uchar= (unsigned char *)malloc(naxes[0] * naxes[1] * sizeof(unsigned char));
  if( image_array_uchar == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for image_array_uchar\n");
   exit(1);
  };
  fits_read_img(fptr, TBYTE, 1, naxes[0] * naxes[1], &nullval_uchar, image_array_uchar, &anynul, &status);
  for( i= 0; i < naxes[0] * naxes[1]; i++ )
   float_array[i]= (float)image_array_uchar[i];
 }
 // 16 bit image
 if( bitpix == 16 ) {
  image_array_ushort= (unsigned short *)malloc(naxes[0] * naxes[1] * sizeof(short));
  if( image_array_ushort == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for image_array_ushort\n");
   exit(1);
  };
  //fprintf(stderr,"Trying to read the image as TUSHORT\n");
  fits_read_img(fptr, TUSHORT, 1, naxes[0] * naxes[1], &nullval_ushort, image_array_ushort, &anynul, &status);
  //fits_read_img(fptr, TSHORT, 1, naxes[0]*naxes[1],&nullval,image_array_ushort, &anynul, &status);
  if( status == 412 ) {
   // is this actually a signed-integer image?
   //fprintf(stderr,"Trying to read the image as TSHORT\n");
   status= 0;
   //fits_read_img(fptr, TSHORT, 1, naxes[0]*naxes[1],&nullval,image_array_ushort, &anynul, &status);
   fits_read_img(fptr, TUSHORT, 1, naxes[0] * naxes[1], &nullval_ushort, image_array_ushort, &anynul, &status);
   // ??
  }
  if( status == 412 ) {
   // is this actually a float-image with a wrong header?
   fits_report_error(stderr, status); /* print out any error messages */
   fprintf(stderr, "Image read problem! Is it actually a Kourovka SBG cameraimage? Let's try...\n");
   if( 0 == Kourovka_SBG_date_hack(fits_image_name, stderr_output, &N, &median_class_star) ) {
    fprintf(stderr, "Yes, it is! Will have to re-open the image...\n");
    status= 0;
    bitpix= 16;
    fits_close_file(fptr, &status);
    //fits_open_file(&fptr, fits_image_name, 0 , &status);
    fits_open_image(&fptr, fits_image_name, 0, &status);
    fits_get_img_type(fptr, &bitpix, &status);
   } else {
    fprintf(stderr, "Image read problem! Is it actually a float-type image? Let's try...\n");
    status= 0;
    bitpix= -32;
   }
  }
  if( status == 0 && bitpix != -32 ) {
   for( i= 0; i < naxes[0] * naxes[1]; i++ )
    float_array[i]= (float)image_array_ushort[i];
  }
  free(image_array_ushort);
 }
 // 32 bit image
 if( bitpix == 32 ) {
  image_array_uint= (unsigned int *)malloc(naxes[0] * naxes[1] * sizeof(int));
  if( image_array_uint == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for image_array_uint\n");
   exit(1);
  };
  fits_read_img(fptr, TUINT, 1, naxes[0] * naxes[1], &nullval_uint, image_array_uint, &anynul, &status);
  if( status == 412 ) {
   // Ignore the data type overflow error
   status= 0;
  }
  fits_report_error(stderr, status); // print out any error messages
  for( i= 0; i < naxes[0] * naxes[1]; i++ )
   float_array[i]= (float)image_array_uint[i];
  free(image_array_uint);
 }
 // double image
 if( bitpix == -64 ) {
  image_array_double= (double *)malloc(naxes[0] * naxes[1] * sizeof(double));
  if( image_array_double == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for image_array_double\n");
   exit(1);
  };
  fits_read_img(fptr, TDOUBLE, 1, naxes[0] * naxes[1], &nullval_double, image_array_double, &anynul, &status);
  for( i= 0; i < naxes[0] * naxes[1]; i++ )
   float_array[i]= (float)image_array_double[i];
  free(image_array_double);
 }
 // float image
 if( bitpix == -32 ) {
  fits_read_img(fptr, TFLOAT, 1, naxes[0] * naxes[1], &nullval, float_array, &anynul, &status);
 }
 fits_close_file(fptr, &status);
 fits_report_error(stderr, status); /* print out any error messages */
 if( status != 0 ) {
  exit(status);
 }
 //fprintf(stderr,"OK\n");

 //fprintf(stderr,"DEBUG-3e\n");

 // Don't do this check if this is fits2png
 if( finding_chart_mode != 1 && use_labels != 0 ) {
  // Decide if we want to use xy2sky()
  xy2sky_return_value= xy2sky(fits_image_name, (float)naxes[0] / 2.0, (float)naxes[1] / 2.0);
  if( xy2sky_return_value == 0 ) {
   fprintf(stderr, "The image center coordinates are printed above.\n");
   use_xy2sky= 1;
  } else {
   use_xy2sky= 0;
  }
  //
 } else {
  use_xy2sky= 0;
 }

 axis_ratio= (float)naxes[0] / (float)naxes[1];
 //fprintf(stderr,"DEBUG-3f axis_ratio=%f\n",axis_ratio);

 // filter out bad pixels from float_array
 for( i= 0; i < naxes[0] * naxes[1]; i++ ) {
  if( float_array[i] < MIN_PIX_VALUE || float_array[i] > MAX_PIX_VALUE )
   float_array[i]= 0.0;
 }

 // real_float_array - array with real pixel values (well, not real but converted to float)
 // float_array - array used for computations with values ranging from 0 to 65535
 for( i= 0; i < naxes[0] * naxes[1]; i++ ) {
  real_float_array[i]= float_array[i];
 }
 fix_array_with_negative_values(naxes[0] * naxes[1], float_array);
 image_minmax2(naxes[0] * naxes[1], float_array, &max_val, &min_val);

 /* GUI */
 //fprintf(stderr,"Opening display ... ");

 //fprintf(stderr,"DEBUG-3g\n");

 //setenv("PGPLOT_DIR","lib/pgplot/",1);
 setenv_localpgplot(argv[0]);
 if( finding_chart_mode == 1 ) {

  //
  inverted_Y_axis= 0; // do not invert Y axis for finding charts!
  //

  if( cpgbeg(0, "/PNG", 1, 1) != 1 ) {
   // fallback to PS
   if( cpgbeg(0, "/PS", 1, 1) != 1 ) {
    return EXIT_FAILURE;
   }
  }
 } else {
  if( cpgbeg(0, "/XW", 1, 1) != 1 ) {
   return EXIT_FAILURE;
  }
 }
 cpgask(0); // turn OFF this silly " Type <RETURN> for next page:" request

 //cpgpap( 0.0, 1.0); /* Make square plot */

 //if( finding_chart_mode==0 ){
 cpgscr(0, 0.10, 0.31, 0.32); /* set default vast window background */
 cpgpage();
 //}
 // (finding_chart_mode == 1 && use_north_east_marks == 0 && use_labels == 0)
 // should correspond to fits2png settings
 if( finding_chart_mode == 0 || (finding_chart_mode == 1 && use_north_east_marks == 0 && use_labels == 0) ) {
  //fprintf(stderr,"DEBUG-3h\n");
  cpgpap(0.0, 1.0 / axis_ratio);
  //cpgpap( 0.0, (float)naxes[1] / (float)( naxes[0] ) );
  cpgsvp(0.05, 0.95, 0.035, 0.035 + 0.9);
 } else {
  //fprintf(stderr,"DEBUG-3hh\n");
  cpgpap(0.0, 1.0); /* Make square plot */
                    /*
  if( use_labels == 1 ) {
   fprintf(stderr,"DEBUG-3hhh\n");
   // leave some space for labels
   cpgsvp( 0.05, 0.95, 0.05, 0.95 );
  } else {
   fprintf(stderr,"DEBUG-3hhhh\n");
   // Use the full plot area leaving no space for labels
   cpgsvp( 0.0, 1.0, 0.0, 1.0 );
  }
*/
 }

 if( use_labels == 1 ) {
  //fprintf(stderr,"DEBUG-3hhh\n");
  // leave some space for labels
  cpgsvp(0.05, 0.95, 0.05, 0.95);
 } else {
  //fprintf(stderr,"DEBUG-3hhhh\n");
  // Use the full plot area leaving no space for labels
  cpgsvp(0.0, 1.0, 0.0, 1.0);
 }

 // set default plotting limits
 drawX1= 1;
 drawY1= 1;
 drawX2= (int)naxes[0];
 drawY2= (int)naxes[1];

 // Check marker position
 if( markX < 0.0 || markX > (float)naxes[0] || markY < 0.0 || markY > (float)naxes[1] ) {
  fprintf(stderr, "WARNING: marker position %lf %lf is outside the image border\n", markX, markY);
  markX= 0.0;
  markY= 0.0;
 }

 // start with a zoom if a marker position is specified
 if( markX != 0.0 && markY != 0.0 && finding_chart_mode == 0 ) {
  drawX1= markX - MIN(100.0, markX);
  drawY1= markY - MIN(100.0, markY);
  drawX2= drawX1 + MIN(200.0, (float)naxes[0]);
  drawY2= drawY1 + MIN(200.0, (float)naxes[1]);
  //fprintf(stderr,"DEBUG01: drawX1=%d drawX2=%d drawY1=%d drawY2=%d  markX=%f markY=%f \n",drawX1,drawX2,drawY1,drawY2,markX,markY);
  ///////
  drawX0= (int)((drawX1 + drawX2) / 2 + 0.5);
  drawY0= (int)((drawY1 + drawY2) / 2 + 0.5);
  razmer_y= myimax(drawX2 - drawX1, drawY2 - drawY1);
  //
  razmer_y= MAX(razmer_y, 3); // do not allow zoom smaller than 3 pix
  //
  razmer_x= axis_ratio * razmer_y;
  drawX1= drawX0 - (int)(razmer_x / 2 + 0.5);
  drawY1= drawY0 - (int)(razmer_y / 2 + 0.5);
  drawX2= drawX1 + (int)razmer_x;
  drawY2= drawY1 + (int)razmer_y;
  //fprintf(stderr,"DEBUG02: drawX1=%d drawX2=%d drawY1=%d drawY2=%d\n",drawX1,drawX2,drawY1,drawY2);
  if( drawX2 > naxes[0] ) {
   drawX1-= drawX2 - naxes[0];
   drawX2= naxes[0];
  }
  if( drawY2 > naxes[1] ) {
   drawY1-= drawY2 - naxes[1];
   drawY2= naxes[1];
  }
  if( drawX1 < 1 ) {
   drawX2+= 1 - drawX1;
   drawX1= 1;
  }
  if( drawY1 < 1 ) {
   drawY2+= 1 - drawY1;
   drawY1= 1;
  }
  if( drawX2 > naxes[0] )
   drawX2= naxes[0];
  if( drawY2 > naxes[1] )
   drawY2= naxes[1];
  //fprintf(stderr,"DEBUG03: drawX1=%d drawX2=%d drawY1=%d drawY2=%d\n",drawX1,drawX2,drawY1,drawY2);
  ///////
  fprintf(stderr, "\n Press 'D' or 'Z''Z' to view the full image.\n\n");
 }

 if( finding_chart_mode == 0 ) {
  // Print user instructions here!!!
  print_pgfv_help();
  if( match_mode == 2 ) {
   fprintf(stderr, "Click on a comparison star and enter its magnitude in the terminal window.\nRight-click after entering all the comparison stars.\n");
  }
 } // if ( finding_chart_mode == 0 ) {

 if( finding_chart_mode == 1 ) {
  curX= markX;
  curY= markY;
 } else {
  curX= curY= 0;
 }
 curX2= curY2= 0;
 curC= 'R';
 do {

  // Check if the click is inside the plot
  // (we'll just redraw the plot if it is)
  if( curC == 'A' || curC == 'a' ) {
   if( curX < drawX1 || curX > drawX2 || curY < drawY1 || curY > drawY2 ) {
    curC= 'R';
   }
  }

  /// Below is the old check...

  // If we cick inside the image
  if( curX > 0 && curX < naxes[0] && curY > 0 && curY < naxes[1] ) {

   /* '+' increse aperture */
   if( curC == '+' || curC == '=' ) {
    APER= APER + 1.0;
    APER= (double)((int)(APER + 0.5)); // round-off the aperture
    aperture_change= 1;
   }

   /* '-' decrese aperture */
   if( curC == '-' || curC == '_' ) {
    APER= APER - 1.0;
    APER= (double)((int)(APER + 0.5)); // round-off the aperture
    aperture_change= 1;
   }

   /* If aperture was changed - repeat measurements with new aperture */
   if( match_mode == 3 || match_mode == 4 ) {
    if( aperture_change == 1 ) {
     autodetect_aperture(fits_image_name, sextractor_catalog, 1, 0, APER, dimX, dimY, 2);
     sex= 0;
     catfile= fopen(sextractor_catalog, "r");
     if( NULL == catfile ) {
      fprintf(stderr, "ERROR! Cannot open sextractor catalog file %s for reading!\n", sextractor_catalog);
      exit(1);
     }
     while( NULL != fgets(sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, catfile) ) {
      sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT - 1]= '\0'; // just in case
      external_flag= 0;
      if( 0 != parse_sextractor_catalog_string(sextractor_catalog_string, &sexNUMBER[sex], &sexFLUX[sex], &sexFLUX_ERR[sex], &sexMAG[sex], &sexMAG_ERR[sex], &position_x_pix, &position_y_pix, &sexA_IMAGE[sex], &sexERRA_IMAGE[sex], &sexB_IMAGE[sex], &sexERRB_IMAGE[sex], &sexFLAG[sex], &external_flag, &psf_chi2, NULL) ) {
       fprintf(stderr, "WARNING: problem occurred while parsing SExtractor catalog %s\nThe offending line is:\n%s\n", sextractor_catalog, sextractor_catalog_string);
       continue;
      }
      sexX[sex]= position_x_pix;
      sexY[sex]= position_y_pix;
      extFLAG[sex]= external_flag;
      psfCHI2[sex]= psf_chi2;
      sex++;
     }
     fclose(catfile);
     fprintf(stderr, "New aperture %.1lf\n", APER);
     aperture_change= 0;
     curC= 'R'; // Redraw screen
    }           // if ( aperture_change == 1 ) {
   }            // if( match_mode == 3 || match_mode == 4 ) {
   /* Switch to magnitude calibration mode */
   if( curC == '2' && match_mode == 3 ) {
    fprintf(stderr, "Entering megnitude calibration mode!\n");
    fprintf(stderr, "\E[01;31mPlease click on comparison stars and enter their magnitudes...\E[33;00m\n");
    fprintf(stderr, "\E[01;31mPress '3' when done!\E[33;00m\n");
    //system("rm -f calib.txt");
    unlink("calib.txt");
    match_mode= 2;
   }

   /* Switch to single image inspection mode */
   if( curC == '3' && match_mode == 2 ) {
    magnitude_calibration_using_calib_txt(sexMAG, sex);
    fprintf(stderr, "Entering single image inspection mode!\n");
    match_mode= 3;
   }

   /* I - print info (help) */
   if( curC == 'I' || curC == 'i' ) {
    print_pgfv_help();
   }

   /* M - star markers on/off */
   if( curC == 'M' || curC == 'm' ) {
    if( draw_star_markers == 1 )
     draw_star_markers= 0;
    else
     draw_star_markers= 1;
    curC= 'R';
   }

   /* Process left mouse button click */
   if( curC == 'A' ) {
    //fprintf(stderr,"Pixel: %7.1f %7.1f %9.3f\n",curX+0.5,curY+0.5,real_float_array[(int)(curX-0.5)+(int)(curY-0.5)*naxes[0]]);
    fprintf(stderr, "\nPixel: %7.1f %7.1f %9.3f\n", curX, curY, real_float_array[(int)(curX - 0.5) + (int)(curY - 0.5) * naxes[0]]);
    ///
    if( use_xy2sky > 0 ) {
     xy2sky_return_value= xy2sky(fits_image_name, curX, curY);
    }
    //

    /* Magnitude calibration mode or Single image mode */
    //if( match_mode==2 || match_mode==3 ){
    if( match_mode == 1 || match_mode == 2 || match_mode == 3 || match_mode == 4 ) {
     for( marker_counter= 0; marker_counter < sex; marker_counter++ ) {
      if( (curX - sexX[marker_counter]) * (curX - sexX[marker_counter]) + (curY - sexY[marker_counter]) * (curY - sexY[marker_counter]) < (float)(APER * APER / 4.0) ) {
       // mark the star
       cpgsci(2);
       cpgcirc(sexX[marker_counter], sexY[marker_counter], (float)APER / 2.0);
       cpgsci(1);
       //

       /* Magnitude calibration mode */
       if( match_mode == 2 || match_mode == 4 ) {
        // mark the star
        //cpgsci( 2 );
        //cpgcirc( sexX[marker_counter], sexY[marker_counter], (float)APER / 2.0 );
        //cpgsci( 1 );
        //
        fprintf(stderr, "Star %d. Instrumental magnitude: %.4lf %.4lf\n(In order to cancel the input - type '99' instead of an actual magnitude.)\n Please, enter its catalog magnitude or 'v' to mark it as the target variable:\nComp. star mag: ", sexNUMBER[marker_counter], sexMAG[marker_counter], sexMAG_ERR[marker_counter]);
        if( NULL == fgets(RADEC, 1024, stdin) ) {
         fprintf(stderr, "Incorrect input!\n");
        }
        RADEC[1024 - 1]= '\0';
        ; // just in case
        if( match_mode == 4 ) {
         // Check if we should mark this as a known variable star
         if( NULL != strstr(RADEC, "v") || NULL != strstr(RADEC, "V") ) {
          save_star_to_vast_list_of_previously_known_variables_and_exclude_lst(sexNUMBER[marker_counter], sexX[marker_counter], sexY[marker_counter]);
          break;
         }
        }
        // Try to filter the input string
        for( first_number_flag= 0, jj= 0, ii= 0; ii < MIN(1024, (int)strlen(RADEC)); ii++ ) {
         //fprintf(stderr,"%d %c\n",ii,RADEC[ii]);
         if( RADEC[ii] == '0' ) {
          filtered_string[jj]= '0';
          jj++;
          continue;
         }
         if( RADEC[ii] == '1' ) {
          filtered_string[jj]= '1';
          jj++;
          first_number_flag= 1;
          continue;
         } // assume if we found '1' this is the magnitude
         if( RADEC[ii] == '2' ) {
          filtered_string[jj]= '2';
          jj++;
          continue;
         }
         if( RADEC[ii] == '3' ) {
          filtered_string[jj]= '3';
          jj++;
          continue;
         }
         if( RADEC[ii] == '4' ) {
          filtered_string[jj]= '4';
          jj++;
          continue;
         }
         if( RADEC[ii] == '5' ) {
          filtered_string[jj]= '5';
          jj++;
          continue;
         }
         if( RADEC[ii] == '6' ) {
          filtered_string[jj]= '6';
          jj++;
          continue;
         }
         if( RADEC[ii] == '7' ) {
          filtered_string[jj]= '7';
          jj++;
          continue;
         }
         if( RADEC[ii] == '8' ) {
          filtered_string[jj]= '8';
          jj++;
          continue;
         }
         if( RADEC[ii] == '9' ) {
          filtered_string[jj]= '9';
          jj++;
          continue;
         }
         if( RADEC[ii] == '.' ) {
          filtered_string[jj]= '.';
          jj++;
          first_number_flag= 1;
          continue;
         } // assume if we found '.' this is the magnitude
         if( RADEC[ii] == '+' ) {
          filtered_string[jj]= '+';
          jj++;
          continue;
         }
         if( RADEC[ii] == '-' ) {
          filtered_string[jj]= '-';
          jj++;
          continue;
         }
         if( RADEC[ii] == ' ' && first_number_flag == 1 ) {
          break;
         } // ignore anything that goes after the first magnitude
        }
        filtered_string[jj]= '\0'; // set the end of line character
        if( strlen(filtered_string) < 2 ) {
         fprintf(stderr, "Magnitude string too short. Ignoring input.\nPlease try again with this or another star.\n");
         break;
        }
        catalog_mag= atof(filtered_string);
        if( catalog_mag < -1.5 || catalog_mag > 30.0 ) {
         fprintf(stderr, "Magnitude %lf is out of range. Ignoring input.\nPlease try again with this or another star.\n", catalog_mag);
         break;
        }
        if( match_mode == 4 ) {
         fprintf(stderr, "Adding the star at %.4f %.4f with magnitude %.4lf to manually_selected_comparison_stars.lst\nPick an additional comparison star or right-click to quit.\n", sexX[marker_counter], sexY[marker_counter], catalog_mag);
         matchfile= fopen("manually_selected_comparison_stars.lst", "a");
         if( matchfile == NULL ) {
          fprintf(stderr, "ERROR: failed to poed manually_selected_comparison_stars.lst for writing!\nSomething is really messed-up, so I'll die. :(\n");
          exit(1);
         }
         fprintf(matchfile, "%.4f %.4f %.4lf\n", sexX[marker_counter], sexY[marker_counter], catalog_mag);
         fclose(matchfile);
        } else {
         fprintf(stderr, "Writing a new string to calib.txt:\n%.4lf %.4lf %.4lf\n\n", sexMAG[marker_counter], catalog_mag, sexMAG_ERR[marker_counter]);
         matchfile= fopen("calib.txt", "a");
         fprintf(matchfile, "%.4lf %.4lf %.4lf\n", sexMAG[marker_counter], catalog_mag, sexMAG_ERR[marker_counter]);
         fclose(matchfile);
        }
        match_input++;
        break;
       }

       /* Single image mode */
       if( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
        fprintf(stderr, "Star %6d\n", sexNUMBER[marker_counter]);

        //if ( sexX[marker_counter] > FRAME_EDGE_INDENT_PIXELS && sexY[marker_counter] > FRAME_EDGE_INDENT_PIXELS && fabs( sexX[marker_counter] - (float)naxes[0] ) > FRAME_EDGE_INDENT_PIXELS && fabs( sexY[marker_counter] - (float)naxes[1] ) > FRAME_EDGE_INDENT_PIXELS ) {
        if( 0 == is_point_close_or_off_the_frame_edge((double)sexX[marker_counter], (double)sexY[marker_counter], (double)naxes[0], (double)naxes[1], FRAME_EDGE_INDENT_PIXELS) ) {
         fprintf(stderr, "Star coordinates \E[01;32m%6.1lf %6.1lf\E[33;00m (pix)\n", sexX[marker_counter], sexY[marker_counter]);
        } else {
         fprintf(stderr, "Star coordinates \E[01;31m%6.1lf %6.1lf\E[33;00m (pix)\n", sexX[marker_counter], sexY[marker_counter]);
        }

        if( 0 == exclude_region(X1, Y1, X2, Y2, N_bad_regions, (double)sexX[marker_counter], (double)sexY[marker_counter], APER) ) {
         fprintf(stderr, "The star is not situated in a bad CCD region according to bad_region.lst\n");
        } else {
         fprintf(stderr, "The star is situated in a \E[01;31mbad CCD region\E[33;00m according to bad_region.lst\n");
        }

        if( use_xy2sky > 0 ) {
         xy2sky_return_value= xy2sky(fits_image_name, sexX[marker_counter], sexY[marker_counter]);
        }

        if( sexFLUX[marker_counter] > MIN_SNR * sexFLUX_ERR[marker_counter] ) {
         fprintf(stderr, "SNR \E[01;32m%.1lf\E[33;00m\n", sexFLUX[marker_counter] / sexFLUX_ERR[marker_counter]);
        } else {
         fprintf(stderr, "SNR \E[01;31m%.1lf\E[33;00m\n", sexFLUX[marker_counter] / sexFLUX_ERR[marker_counter]);
        }

        if( sexMAG[marker_counter] != 99.0000 ) {
         fprintf(stderr, "Magnitude \E[01;34m%7.4lf  %6.4lf\E[33;00m\n", sexMAG[marker_counter], sexMAG_ERR[marker_counter]);
        } else {
         fprintf(stderr, "Magnitude \E[01;31m%7.4lf  %6.4lf\E[33;00m\n", sexMAG[marker_counter], sexMAG_ERR[marker_counter]);
        }

        if( sexFLAG[marker_counter] < 2 ) {
         fprintf(stderr, "SExtractor flag \E[01;32m%d\E[33;00m\n", sexFLAG[marker_counter]);
        } else {
         fprintf(stderr, "SExtractor flag \E[01;31m%d\E[33;00m\n", sexFLAG[marker_counter]);
        }

        if( extFLAG[marker_counter] == 0 ) {
         fprintf(stderr, "External flag \E[01;32m%d\E[33;00m\n", extFLAG[marker_counter]);
        } else {
         fprintf(stderr, "External flag \E[01;31m%d\E[33;00m\n", extFLAG[marker_counter]);
        }

        // Print anyway
        fprintf(stderr, "Reduced chi2 from PSF-fitting: \E[01;32m%lg\E[33;00m (Objects with large values will be mising from the list of detections! If no PSF fitting was performed, this value is set to 1.0)\n", psfCHI2[marker_counter]);

        bad_size= 0;
        if( CONST * (sexA_IMAGE[marker_counter] + sexERRA_IMAGE[marker_counter]) < MIN_SOURCE_SIZE_APERTURE_FRACTION * APER ) {
         bad_size= 1;
        }
        if( sexA_IMAGE[marker_counter] > APER && sexFLAG[marker_counter] < 4 ) {
         bad_size= 1;
        }
        if( sexA_IMAGE[marker_counter] + sexERRA_IMAGE[marker_counter] < FWHM_MIN ) {
         bad_size= 1;
        }
        if( sexB_IMAGE[marker_counter] + sexERRB_IMAGE[marker_counter] < FWHM_MIN ) {
         bad_size= 1;
        }
        if( bad_size == 0 ) {
         fprintf(stderr, "A= \E[01;32m%lf +/- %lf\E[33;00m  B= \E[01;32m%lf +/- %lf\E[33;00m\nFWHM(A)= \E[01;32m%lf +/- %lf\E[33;00m  FWHM(B)= \E[01;32m%lf +/- %lf\E[33;00m\n", sexA_IMAGE[marker_counter], sexERRA_IMAGE[marker_counter], sexB_IMAGE[marker_counter], sexERRB_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sexA_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sexERRA_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sexB_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sexERRB_IMAGE[marker_counter]);
        } else {
         fprintf(stderr, "A= \E[01;31m%lf +/- %lf\E[33;00m  B= \E[01;31m%lf +/- %lf\E[33;00m\nFWHM(A)= \E[01;31m%lf +/- %lf\E[33;00m  FWHM(B)= \E[01;31m%lf +/- %lf\E[33;00m\n", sexA_IMAGE[marker_counter], sexERRA_IMAGE[marker_counter], sexB_IMAGE[marker_counter], sexERRB_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sexA_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sexERRA_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sexB_IMAGE[marker_counter], SIGMA_TO_FWHM_CONVERSION_FACTOR * sexERRB_IMAGE[marker_counter]);
        }
        // It's nice to ptint the aperture size here for comparison
        fprintf(stderr, "Aperture diameter = %.1lf pixels\n", APER);

        fprintf(stderr, "%s\n", stderr_output);
        fprintf(stderr, "\n");
       }

       // Star selection from reference image mode
       if( match_mode == 1 ) {
        // Mark star as viewed
        cpgsci(2);
        cpgcirc(sexX[marker_counter], sexY[marker_counter], (float)APER / 2.0);
        cpgsci(1);
        // Save the mark information so it isn't lost when we change zoom
        sexX_viewed[sex_viewed_counter]= sexX[marker_counter];
        sexY_viewed[sex_viewed_counter]= sexY[marker_counter];
        sex_viewed_counter++;
        // Generate the command
        sprintf(system_command, "./lc out%05d.dat", sexNUMBER[marker_counter]);
        // fork before system() so the parent process is not blocked
        if( 0 == fork() ) {
         nanosleep(&requested_time, &remaining);
         if( 0 != system(system_command) ) {
          fprintf(stderr, "ERROR running  %s\n", system_command);
         }
         exit(0);
        } else {
         waitpid(-1, &status, WNOHANG);
        }
       }
      }
     }
    }
   } // if( curC=='A' ){

   if( finding_chart_mode == 1 ) {
    curC= 'Z';
   }

   /* Zoom in or out */
   if( curC == 'z' || curC == 'Z' ) {
    if( finding_chart_mode == 1 ) {
     drawX1= markX - finder_char_pix_around_the_target;
     drawX2= markX + finder_char_pix_around_the_target;
     drawY1= markY - finder_char_pix_around_the_target;
     drawY2= markY + finder_char_pix_around_the_target;
     curC= 'R';
    } else {
     cpgsci(5);
     cpgband(2, 0, curX, curY, &curX2, &curY2, &curC);
     cpgsci(1);
    }
    if( curC == 'Z' || curC == 'z' )
     curC= 'D';
    else {
     if( finding_chart_mode == 0 ) {
      drawX1= mymin(curX, curX2);
      drawX2= mymax(curX, curX2);
      drawY1= mymin(curY, curY2);
      drawY2= mymax(curY, curY2);
     }
     drawX0= (int)((drawX1 + drawX2) / 2 + 0.5);
     drawY0= (int)((drawY1 + drawY2) / 2 + 0.5);
     razmer_y= myimax(drawX2 - drawX1, drawY2 - drawY1);
     razmer_y= MAX(razmer_y, 3); // do not allow zoom smaller than 3 pix
     razmer_y= MIN(razmer_y, naxes[1]);
     // if razmer_y is so big that the whole image is to be displayed again...
     if( razmer_y == naxes[1] ) {
      razmer_y= (double)MIN(drawX2 - drawX1, naxes[0]) / (double)naxes[0] * razmer_y;
     }
     // finding_chart_mode=1 use_north_east_marks= 0; use_labels= 0;
     // corresponds to fits2png settings where we presumably whant the whole image
     //if ( finding_chart_mode == 1 && ( use_north_east_marks!= 0 && use_labels!= 0 ) ) {
     if( finding_chart_mode == 1 && (use_north_east_marks != 0 && use_labels != 0) ) {
      // we want a square finding chart !
      razmer_x= razmer_y;
      fprintf(stderr, "Making a square plot\n");
     } else {
      razmer_x= axis_ratio * razmer_y;
      fprintf(stderr, "Making a plot with the axes ratio of %lf\n", axis_ratio);
     }
     drawX1= drawX0 - (int)(razmer_x / 2 + 0.5);
     drawY1= drawY0 - (int)(razmer_y / 2 + 0.5);
     drawX2= drawX1 + (int)razmer_x;
     drawY2= drawY1 + (int)razmer_y;
     if( drawX2 > naxes[0] ) {
      drawX1-= drawX2 - naxes[0];
      drawX2= naxes[0];
     }
     if( drawY2 > naxes[1] ) {
      drawY1-= drawY2 - naxes[1];
      drawY2= naxes[1];
     }
     if( drawX1 < 1 ) {
      drawX2+= 1 - drawX1;
      drawX1= 1;
     }
     if( drawY1 < 1 ) {
      drawY2+= 1 - drawY1;
      drawY1= 1;
     }
     if( drawX2 > naxes[0] )
      drawX2= naxes[0];
     if( drawY2 > naxes[1] )
      drawY2= naxes[1];
     //
     //
     curC= 'R';
    }
   }
  } // If we cick inside the image

  // No matter if the click was inside or outside the image area
  if( curC == 'H' || curC == 'h' ) {
   if( hist_trigger == 0 ) {
    hist_trigger= 1;
    float_array2= malloc(naxes[0] * naxes[1] * sizeof(float));
    if( float_array2 == NULL ) {
     fprintf(stderr, "ERROR: Couldn't allocate memory for float_array2\n");
     exit(1);
    };
    for( i= 0; i < naxes[0] * naxes[1]; i++ ) {
     float_array2[i]= float_array[i];
    }
    //fprintf(stderr,"histeq... ");
    histeq(naxes[0] * naxes[1], float_array, &max_val, &min_val);
    image_minmax3(naxes[0] * naxes[1], float_array, &max_val, &min_val, drawX1, drawX2, drawY1, drawY2, naxes); // TEST
    //fprintf(stderr,"OK\n ");
   } else {
    hist_trigger= 0;
    for( i= 0; i < naxes[0] * naxes[1]; i++ ) {
     float_array[i]= float_array2[i];
    }
    free(float_array2);
    //image_minmax2( (int)(naxes[0]*naxes[1]), float_array, &max_val, &min_val);
    image_minmax3(naxes[0] * naxes[1], float_array, &max_val, &min_val, drawX1, drawX2, drawY1, drawY2, naxes);
   }
   curC= 'R';
  }
  if( curC == 'D' || curC == 'd' ) {
   drawX1= 1;
   drawY1= 1;
   drawX2= (int)naxes[0];
   drawY2= (int)naxes[1];
   curC= 'R';
  }
  if( curC == 'V' || curC == 'v' ) {
   if( inverted_Y_axis == 0 ) {
    inverted_Y_axis= 1;
   } else {
    inverted_Y_axis= 0;
   }
   curC= 'R';
  }
  if( curC == 'B' || curC == 'b' ) {
   if( inverted_X_axis == 0 ) {
    inverted_X_axis= 1;
   } else {
    inverted_X_axis= 0;
   }
   curC= 'R';
  }
  /* F - Fiddle the color table contrast and brightness */
  if( curC == 'F' || curC == 'f' ) {
   fprintf(stderr, "brightness=%lf  contrast=%lf\n", (curX - drawX1) / (drawX2 - drawX1), 5.0 * curY / abs(drawY2 - drawY1));
   cpgctab(bw_l, bw_r, bw_g, bw_b, 83, 5.0 * curY / abs(drawY2 - drawY1), (curX - drawX1) / (drawX2 - drawX1));
   curC= 'R';
  }

  /* R - Redraw screen */
  if( curC == 'R' || curC == 'r' ) {

   //fprintf(stderr,"Redrawing image: inverted_X_axis=%d inverted_Y_axis=%d  drawX1=%d drawX2=%d drawY1=%d drawY2=%d\n",inverted_X_axis,inverted_Y_axis,drawX1,drawX2,drawY1,drawY2);

   if( inverted_Y_axis == 1 ) {
    buf= drawY1;
    drawY1= drawY2;
    drawY2= buf;
   }
   if( inverted_X_axis == 1 ) {
    buf= drawX1;
    drawX1= drawX2;
    drawX2= buf;
   }

   if( finding_chart_mode == 0 ) {
    cpgbbuf();
    cpgscr(0, 0.10, 0.31, 0.32); /* set default vast window background */
    cpgeras();
   }
   cpgswin((float)drawX1, (float)drawX2, (float)drawY1, (float)drawY2);
   if( use_labels == 1 ) {
    cpgbox("BCN1", 0.0, 0, "BCN1", 0.0, 0);
   }

   if( drawY1 > drawY2 ) {
    buf= drawY1;
    drawY1= drawY2;
    drawY2= buf;
   }
   if( drawX1 > drawX2 ) {
    buf= drawX1;
    drawX1= drawX2;
    drawX2= buf;
   }

   // Determine cuts
   image_minmax3(naxes[0] * naxes[1], float_array, &max_val, &min_val, drawX1, drawX2, drawY1, drawY2, naxes);

   /* Draw image */
   if( finding_chart_mode == 0 ) {
    cpgscr(0, 0.0, 0.0, 0.0); /* set black background */
    cpgimag(float_array, (int)naxes[0], (int)naxes[1], drawX1, drawX2, drawY1, drawY2, min_val, max_val, tr);
   } else {
    //fprintf(stderr,"curC=%c\n",curC);
    cpgscr(1, 0.0, 0.0, 0.0);
    cpgscr(0, 1.0, 1.0, 1.0);
    cpggray(float_array, (int)naxes[0], (int)naxes[1], drawX1, drawX2, drawY1, drawY2, min_val, max_val, tr);
    cpgscr(0, 0.0, 0.0, 0.0);
    cpgscr(1, 1.0, 1.0, 1.0);
    //    cpgclos();
    //    return 0;
   }
   /* Make labels with general information: time, filename... */
   if( use_labels == 1 ) {
    if( finding_chart_mode == 0 ) {
     cpgscr(1, 0.62, 0.81, 0.38); /* set color of lables */
     cpgsch(0.9);                 /* Set small font size */
     cpgmtxt("T", 0.5, 0.5, 0.5, fits_image_name);
     cpgmtxt("T", 1.5, 0.5, 0.5, stderr_output);
     cpgsch(1.0);              /* Set normal font size */
     cpgscr(1, 1.0, 1.0, 1.0); /* */
    } else {
     cpgmtxt("T", 1.0, 0.5, 0.5, stderr_output);
    }
   }
   /* Done with labels */

   /* Put a mark */
   if( mark_trigger == 1 && use_labels == 1 ) {
    cpgsci(2);
    cpgpt1(markX, markY, 2);
    cpgsci(1);
    ///// New code to enable aperture to be ploted on the finding chart
    if( APER > 0.0 ) {
     cpgsci(2);
     cpgsfs(2);
     cpgcirc(markX, markY, (float)APER / 2.0);
     cpgsci(1);
    }
    /////
   } // if ( mark_trigger == 1 ) {

   if( use_labels == 1 ) {
    // Always put mark in te center of the finding chart
    if( finding_chart_mode == 1 ) {
     markX= ((float)naxes[0] / 2.0);
     markY= ((float)naxes[1] / 2.0);
     cpgsci(2);
     cpgsch(3.0);
     cpgslw(2); // increase line width
     cpgpt1(markX, markY, 2);
     cpgslw(1); // set default line width
     cpgsch(1.0);
     cpgsci(1);
    }
   }

   // Markers from manymarkers file
   for( marker_counter= 0; marker_counter < manymrkerscounter; marker_counter++ ) {
    cpgsci(5);
    cpgpt1(manymarkersX[marker_counter], manymarkersY[marker_counter], 2);
    cpgsci(1);
   }

   if( finding_chart_mode == 1 ) {

    if( use_north_east_marks == 1 ) {
     // Make N/E labels
     if( is_this_north_up_east_left_image == 1 ) {
      cpgsci(2);
      cpgsch(2.0); /* Set small font size */
      cpgslw(4);   // increase line width
      cpgmtxt("T", -1.0, 0.5, 0.5, "N");
      cpgmtxt("LV", -0.5, 0.5, 0.5, "E");
      //
      if( 1 == use_datestringinsideimg ) {
       cpgsch(1.0);
       cpgmtxt("B", -1.0, 0.5, 0.5, stderr_output);
       cpgsch(2.0);
      }
      //
      if( 1 == use_imagesizestringinsideimg ) {
       if( 0 == get_string_with_fov_of_wcs_calibrated_image(fits_image_name, fov_string, finding_chart_mode, finder_char_pix_around_the_target) ) {
        fprintf(stderr, "The image is %s\n", fov_string);
        if( 1 == use_datestringinsideimg ) {
         cpgsch(1.0);
         cpgmtxt("B", -2.2, 0.05, 0.0, fov_string);
         cpgsch(2.0);
        } else {
         // Use large letters
         cpgmtxt("B", -1.0, 0.05, 0.0, fov_string);
        }
       } // if ( 0 == get_string_with_fov_of_wcs_calibrated_image( fits_image_name, fov_string ) ) {
      }  //  if ( 1 == use_imagesizestringinsideimg ) {
      //
      cpgslw(1);   // set default line width
      cpgsch(1.0); /* Set default font size */
      cpgsci(1);
     }
    }

    // exit now
    cpgclos();
    fprintf(stderr, "Writing the output image file pgplot.png (or .ps)\n");
    free(float_array);
    free(real_float_array);
    return 0;
   }

   //fprintf(stderr,"DEBUG000\n");

   /* If not in simple display mode - draw star markers */
   if( match_mode > 0 && draw_star_markers == 1 ) {
    cpgsci(3);
    cpgsfs(2);
    // Draw objects
    for( marker_counter= 0; marker_counter < sex; marker_counter++ ) {
     cpgcirc(sexX[marker_counter], sexY[marker_counter], (float)APER / 2.0);
    }
    if( match_mode == 1 ) {
     cpgsci(2);
     for( marker_counter= 0; marker_counter < sex_viewed_counter; marker_counter++ ) {
      cpgcirc(sexX_viewed[marker_counter], sexY_viewed[marker_counter], (float)APER / 2.0);
     }
     cpgsci(1);
    }
    if( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
     // mark previously known variables from vast_list_of_previously_known_variables.log
     // cpgsci( 5 ); // good for autocandidates
     cpgsci(6);
     cpgslw(4); // increase line width
     for( marker_counter= 0; marker_counter < mark_known_variable_counter; marker_counter++ ) {
      cpgcirc(markX_known_variable[marker_counter], markY_known_variable[marker_counter], (float)APER / 1.5);
     }
     cpgslw(1); // set default line width
     cpgsci(1);
    }
    if( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
     // mark previously known variables from vast_autocandidates.log
     cpgsci(5); // good for autocandidates
     cpgslw(4); // increase line width
     for( marker_counter= 0; marker_counter < mark_autocandidate_variable_counter; marker_counter++ ) {
      cpgcirc(markX_autocandidate_variable[marker_counter], markY_autocandidate_variable[marker_counter], (float)APER / 1.2);
     }
     cpgslw(1); // set default line width
     cpgsci(1);
    }
    /* And draw bad regions */
    if( 0 != N_bad_regions ) {
     cpgsci(2);
     for( marker_counter= 0; marker_counter < N_bad_regions; marker_counter++ ) {
      cpgline_tmp_x[0]= (float)X1[marker_counter];
      cpgline_tmp_y[0]= (float)Y1[marker_counter];
      cpgline_tmp_x[1]= (float)X1[marker_counter];
      cpgline_tmp_y[1]= (float)Y2[marker_counter];
      cpgline(2, cpgline_tmp_x, cpgline_tmp_y);

      cpgline_tmp_x[0]= (float)X1[marker_counter];
      cpgline_tmp_y[0]= (float)Y2[marker_counter];
      cpgline_tmp_x[1]= (float)X2[marker_counter];
      cpgline_tmp_y[1]= (float)Y2[marker_counter];
      cpgline(2, cpgline_tmp_x, cpgline_tmp_y);

      cpgline_tmp_x[0]= (float)X2[marker_counter];
      cpgline_tmp_y[0]= (float)Y2[marker_counter];
      cpgline_tmp_x[1]= (float)X2[marker_counter];
      cpgline_tmp_y[1]= (float)Y1[marker_counter];
      cpgline(2, cpgline_tmp_x, cpgline_tmp_y);

      cpgline_tmp_x[0]= (float)X2[marker_counter];
      cpgline_tmp_y[0]= (float)Y1[marker_counter];
      cpgline_tmp_x[1]= (float)X1[marker_counter];
      cpgline_tmp_y[1]= (float)Y1[marker_counter];
      cpgline(2, cpgline_tmp_x, cpgline_tmp_y);
     }
    }
    cpgsci(1);
   }
   /* Else - draw single star marker */
   //if( match_mode==0 && APER>0 ){
   if( APER > 0.0 ) {
    cpgsci(2);
    cpgsfs(2);
    cpgcirc(markX, markY, (float)APER / 2.0);
    cpgsci(1);
   }

   //fprintf(stderr,"finding_chart_mode=%d\n",finding_chart_mode);
   if( finding_chart_mode == 0 )
    cpgebuf();
   else {
    fprintf(stderr, "Writing the output image file pgplot.png (or.ps)\n");
    cpgclos();
    return 0;
   }
  }

  cpgcurs(&curX, &curY, &curC);
 } while( curC != 'X' && curC != 'x' );

 if( match_mode > 0 ) {
  free(sexX);
  free(sexY);
  free(sexMAG);
  free(sexMAG_ERR);
  free(sexNUMBER);
 }

 if( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
  free(sexX_viewed);
  free(sexY_viewed);
 }

 if( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
  free(sexFLUX);
  free(sexFLUX_ERR);
  //free( sexNUMBER );
  free(sexFLAG);
  free(extFLAG);
  free(psfCHI2);
  free(sexA_IMAGE);
  free(sexERRA_IMAGE);
  free(sexB_IMAGE);
  free(sexERRB_IMAGE);
 }

 if( match_mode == 1 || match_mode == 3 || match_mode == 4 ) {
  if( mark_known_variable_counter > 0 ) {
   // Free memory for the array of known variables markers
   free(markX_known_variable);
   free(markY_known_variable);
  }
  if( mark_autocandidate_variable_counter > 0 ) {
   // Free memory for the array of autocandidate variables markers
   free(markX_autocandidate_variable);
   free(markY_autocandidate_variable);
  }
 }

 /* Write magnitude calibration file */
 /* Magnitude calibration mode */
 if( match_mode == 2 && match_input != 0 ) {
  fprintf(stderr, "%d stars were written to calib.txt \n", match_input);
 }

 if( hist_trigger == 1 ) {
  free(float_array2);
 }

 free(float_array);
 free(real_float_array);

 cpgclos();

 fprintf(stderr, "%s fits viewer exit code 0 (all fine)\n", argv[0]);

 return 0;
}
