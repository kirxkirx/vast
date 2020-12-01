#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_statistics_double.h>

#include <sys/time.h>

#include "vast_limits.h"
#include "lightcurve_io.h"
#include "variability_indexes.h"

void make_sure_photometric_errors_rescaling_is_in_log_file() {
 FILE *logfilein;
 FILE *logfileout;
 //int number_of_iterations=0;
 char str[2048];
 logfilein= fopen("vast_summary.log", "r");
 if( logfilein != NULL ) {
  logfileout= fopen("vast_summary.log.tmp", "w");
  if( logfileout == NULL ) {
   fclose(logfilein);
   fprintf(stderr, "ERROR: Couldn't open file vast_summary.log.tmp\n");
   return;
  }
  while( NULL != fgets(str, 2048, logfilein) ) {
   if( str[0] == 'F' && str[1] == 'o' && str[2] == 'r' && str[4] == 'e' && str[5] == 'a' && str[6] == 'c' && str[7] == 'h' && str[23] == 'a' && str[24] == 'p' && str[25] == 'e' && str[26] == 'r' ) {
    //           0123456789012345678901234567890
    sprintf(str, "For each source choose aperture with the smallest scatter: YES\n");
   }
   fputs(str, logfileout);
  }
  fclose(logfileout);
  fclose(logfilein);
  //system("mv vast_summary.log.tmp vast_summary.log");
  unlink("vast_summary.log");
  rename("vast_summary.log.tmp", "vast_summary.log");
 }
 return;
}

int main(int argc, char **argv) {

 FILE *lightcurvefile;
 FILE *outlightcurvefile;
 double jd, mag, magerr, x, y, app;
 char string[FILENAME_LENGTH];
 char comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 int i;

 int apcounter, bestap;
 double MAD, best_MAD;

 double dm;

 int counter_ap[6];

 double aperture_coefficient_to_print;

 char lightcurve_tmp_filename[FILENAME_LENGTH];

 char comments_string_without_multiple_apertures[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 double **mag_a;
 double **magerr_a;

 // File name handling
 DIR *dp;
 struct dirent *ep;

 char **filenamelist;
 long filename_counter;
 long filenamelen;

 int sscanf_return_value;

 // This is to silance Valgrind warning that we may use this thig uninitialized
 memset(comments_string_without_multiple_apertures, 0, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE);

 mag_a= (double **)malloc(6 * sizeof(double *));
 if( mag_a == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory mag_a(select_aperture_with_smallest_scatter_for_each_object.c)\n");
  exit(1);
 };
 magerr_a= (double **)malloc(6 * sizeof(double *));
 if( magerr_a == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory magerr_a(select_aperture_with_smallest_scatter_for_each_object.c)\n");
  exit(1);
 };
 for( i= 0; i < 6; i++ ) {
  mag_a[i]= (double *)malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(double));
  if( mag_a[i] == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory mag_a[i](select_aperture_with_smallest_scatter_for_each_object.c)\n");
   exit(1);
  };
  magerr_a[i]= (double *)malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(double));
  if( magerr_a[i] == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory magerr_a[i](select_aperture_with_smallest_scatter_for_each_object.c)\n");
   exit(1);
  };
  counter_ap[i]= 0;
 }

 if( argc > 1 ) {
  fprintf(stderr, "Reprocess out*dat files setting the magnitude measured with the best aperture as the reference one (2nd column in the lightcurve file).\n");
  fprintf(stderr, "Usage:\n");
  fprintf(stderr, "%s \n", argv[0]);
  exit(0);
 }

 // Create a list of files
 filenamelist= (char **)malloc(MAX_NUMBER_OF_STARS * sizeof(char *));
 filename_counter= 0;
 dp= opendir("./");
 if( dp != NULL ) {
  while( (ep= readdir(dp)) != NULL ) {
   filenamelen= strlen(ep->d_name);
   if( filenamelen < 8 )
    continue; // make sure the filename is not too short for the following tests
   if( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[filenamelen - 1] == 't' && ep->d_name[filenamelen - 2] == 'a' && ep->d_name[filenamelen - 3] == 'd' ) {
    filenamelist[filename_counter]= malloc((filenamelen + 1) * sizeof(char));
    strncpy(filenamelist[filename_counter], ep->d_name, (filenamelen + 1));
    filename_counter++;
   }
  }
  (void)closedir(dp);
 } else {
  perror("Couldn't open the directory");
  free(filenamelist);
  return 2;
 }

 // Process each file in the list
 for( ; filename_counter--; ) {

  lightcurvefile= fopen(filenamelist[filename_counter], "r");
  if( NULL == lightcurvefile ) {
   fprintf(stderr, "ERROR: Can't open file %s\n", filenamelist[filename_counter]);
   exit(1);
  }
  /* Compute median mag & sigma */
  i= 0;
  while( -1 < read_lightcurve_point(lightcurvefile, &jd, &mag, &magerr, &x, &y, &app, string, comments_string) ) {
   if( jd == 0.0 )
    continue; // if this line could not be parsed, try the next one
   mag_a[0][i]= mag;
   magerr_a[0][i]= magerr;
   if( comments_string == NULL ) {
    continue;
   }
   sscanf_return_value= sscanf(comments_string, "%lf %lf  %lf %lf %lf %lf %lf %lf %lf %lf %[^\t\n]", &mag_a[1][i], &magerr_a[1][i], &mag_a[2][i], &magerr_a[2][i], &mag_a[3][i], &magerr_a[3][i], &mag_a[4][i], &magerr_a[4][i], &mag_a[5][i], &magerr_a[5][i], comments_string_without_multiple_apertures);
   //fprintf(stderr, "sscanf_return_value=%d\n", sscanf_return_value);
   if( 10 > sscanf_return_value ) {
    //fprintf( stderr, "ERROR parsing the comments string: %s\n", comments_string );
    //fprintf( stderr, "##%s##\n", comments_string );
    //fprintf( stderr, "#%s#\n", comments_string_without_multiple_apertures );
    //fprintf( stderr, "#%lf %lf#\n", mag_a[5][i], magerr_a[5][i] );
    continue;
   }

#ifdef VAST_USE_BUILTIN_FUNCTIONS
// Make a proper check the input values if isnormal() is defined
#if defined _ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L
   // We use __builtin_isnormal() as we know it is working if VAST_USE_BUILTIN_FUNCTIONS is defined
   // Othervise even with the '_ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L' check
   // isnormal() doesn't work on Ubuntu 14.04 trusty (vast.sai.msu.ru)
   // BEWARE 0.0 is also not considered normal by isnormal() !!!
   if( 0 == __builtin_isnormal((mag_a[5][i])) && mag_a[5][i] != 0.0 ) {
    fprintf(stderr, "The coefficient value is out of range!\n");
    continue;
   }
   if( 0 == __builtin_isnormal((mag_a[4][i])) && mag_a[4][i] != 0.0 ) {
    fprintf(stderr, "The coefficient value is out of range!\n");
    continue;
   }
   if( 0 == __builtin_isnormal((mag_a[3][i])) && mag_a[3][i] != 0.0 ) {
    fprintf(stderr, "The coefficient value is out of range!\n");
    continue;
   }
   if( 0 == __builtin_isnormal((mag_a[2][i])) && mag_a[2][i] != 0.0 ) {
    fprintf(stderr, "The coefficient value is out of range!\n");
    continue;
   }
   if( 0 == __builtin_isnormal((mag_a[1][i])) && mag_a[1][i] != 0.0 ) {
    fprintf(stderr, "The coefficient value is out of range!\n");
    continue;
   }
#endif
#else
   // a simplified check using isnan
   if( 0 != isnan((mag_a[5][i])) ) {
    fprintf(stderr, "The coefficient value is out of range!\n");
    continue;
   }
   if( 0 != isnan((mag_a[4][i])) ) {
    fprintf(stderr, "The coefficient value is out of range!\n");
    continue;
   }
   if( 0 != isnan((mag_a[3][i])) ) {
    fprintf(stderr, "The coefficient value is out of range!\n");
    continue;
   }
   if( 0 != isnan((mag_a[2][i])) ) {
    fprintf(stderr, "The coefficient value is out of range!\n");
    continue;
   }
   if( 0 != isnan((mag_a[1][i])) ) {
    fprintf(stderr, "The coefficient value is out of range!\n");
    continue;
   }
#endif

   mag_a[1][i]+= mag_a[0][i];
   mag_a[2][i]+= mag_a[0][i];
   mag_a[3][i]+= mag_a[0][i];
   mag_a[4][i]+= mag_a[0][i];
   mag_a[5][i]+= mag_a[0][i];
   i++;
  }
  fclose(lightcurvefile);
  bestap= 0;
  best_MAD= 99999999;
  for( apcounter= 0; apcounter < 6; apcounter++ ) {
   MAD= esimate_sigma_from_MAD_of_unsorted_data(mag_a[apcounter], i);
   if( MAD < best_MAD ) {
    best_MAD= MAD;
    bestap= apcounter;
   }
  }

  counter_ap[bestap]++;

  if( bestap == 0 ) {
   // Do nothing - the current aperture is fine
   free(filenamelist[filename_counter]);
   continue;
  }

  // Compute the aperture correction (we'll need it to make sure the avarage magnitude will not change)
  dm= compute_median_of_usorted_array_without_changing_it(mag_a[0], i) - compute_median_of_usorted_array_without_changing_it(mag_a[bestap], i);
  sprintf(lightcurve_tmp_filename, "lightcurve.tmp");
  // Re-open the lightcurve file and apply the correction
  lightcurvefile= fopen(filenamelist[filename_counter], "r");
  outlightcurvefile= fopen(lightcurve_tmp_filename, "w");
  if( NULL == outlightcurvefile ) {
   fprintf(stderr, "\nAn ERROR has occured while processing file %s \n", filenamelist[filename_counter]);
   fprintf(stderr, "ERROR: Can't open file %s\n", lightcurve_tmp_filename);
   exit(1);
  }
  i= 0;
  while( -1 < read_lightcurve_point(lightcurvefile, &jd, &mag, &magerr, &x, &y, &app, string, comments_string) ) {
   if( jd == 0.0 )
    continue; // if this line could not be parsed, try the next one
   if( 10 <= sscanf(comments_string, "%lf %lf  %lf %lf %lf %lf %lf %lf %lf %lf %[^\t\n]", &mag_a[1][i], &magerr_a[1][i], &mag_a[2][i], &magerr_a[2][i], &mag_a[3][i], &magerr_a[3][i], &mag_a[4][i], &magerr_a[4][i], &mag_a[5][i], &magerr_a[5][i], comments_string_without_multiple_apertures) ) {
    mag= mag + mag_a[bestap][i] + dm;
    magerr= magerr_a[bestap][i];
    if( bestap == 2 ) {
     app+= AP01 * app;
    }
    if( bestap == 3 ) {
     app+= AP02 * app;
    }
    if( bestap == 4 ) {
     app+= AP03 * app;
    }
    if( bestap == 5 ) {
     app+= AP04 * app;
    }
    //write_lightcurve_point( outlightcurvefile, jd, mag, magerr, x, y, app, string, comments_string);
    write_lightcurve_point(outlightcurvefile, jd, mag, magerr, x, y, app, string, comments_string_without_multiple_apertures);
    i++;
    continue;
   }
   fprintf(stderr, "ERROR parsing the comments string %s in %s\n", comments_string, filenamelist[filename_counter]);
  }
  fclose(outlightcurvefile);
  fclose(lightcurvefile);
  unlink(filenamelist[filename_counter]);                          // delete old lightcurve file
  rename(lightcurve_tmp_filename, filenamelist[filename_counter]); // move lightcurve.tmp to lightcurve file
  free(filenamelist[filename_counter]);
 }

 free(filenamelist);

 for( i= 0; i < 6; i++ ) {
  free(mag_a[i]);
  free(magerr_a[i]);
 }
 free(mag_a);
 free(magerr_a);

 for( i= 0; i < 6; i++ ) {
  aperture_coefficient_to_print= 0.0;
  if( i == 1 )
   aperture_coefficient_to_print= 0.0;
  if( i == 2 )
   aperture_coefficient_to_print= AP01;
  if( i == 3 )
   aperture_coefficient_to_print= AP02;
  if( i == 4 )
   aperture_coefficient_to_print= AP03;
  if( i == 5 )
   aperture_coefficient_to_print= AP04;
  //fprintf( stderr, "Aperture with index %d (%lf*REFERENCE_APERTURE_DIAMETER) seems best for %d stars\n", i, aperture_coefficient_to_print, counter_ap[i] );
  fprintf(stderr, "Aperture with index %d (REFERENCE_APERTURE_DIAMETER + (%.2lf)*REFERENCE_APERTURE_DIAMETER) seems best for %d stars\n", i, aperture_coefficient_to_print, counter_ap[i]);
 }

 fprintf(stderr, "\ndone!  =)\n");

 return 0;
}
