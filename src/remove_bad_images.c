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

void update_number_of_bad_images_in_log_file(int images_Nbad) {
 FILE *logfilein;
 FILE *logfileout;
 int old_number_of_bad_images= 0;
 char str[2048];
 logfilein= fopen("vast_summary.log", "r");
 if( logfilein != NULL ) {
  logfileout= fopen("vast_summary.log.tmp", "w");
  if( logfileout == NULL ) {
   fclose(logfilein);
   return;
  }
  while( NULL != fgets(str, 2048, logfilein) ) {
   if( str[0] == 'N' && str[1] == 'u' && str[2] == 'm' && str[10] == 'i' && str[11] == 'd' && str[21] == 'b' && str[22] == 'a' && str[23] == 'd' && str[25] == 'i' ) {
    //          012345678901234567890123456789
    sscanf(str, "Number of identified bad images: %d", &old_number_of_bad_images);
    sprintf(str, "Number of identified bad images: %d\n", old_number_of_bad_images + images_Nbad);
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

void get_image_filename_from_vast_image_details_log_using_JD(double JD) {
 FILE *vast_image_details_file;
 char str[MAX_LOG_STR_LENGTH];
 char filename[FILENAME_LENGTH];
 double logJD;
 int image_found_in_logfile= 0;

 FILE *vast_list_of_bad_images_file;

// Check if JD is reasoable
#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
 // Allow for both MJD and JD
 if( JD < EXPECTED_MIN_MJD || JD > EXPECTED_MAX_JD )
  return;
#endif

 vast_image_details_file= fopen("vast_image_details.log", "r");
 if( vast_image_details_file == NULL ) {
  return;
 }
 while( NULL != fgets(str, MAX_LOG_STR_LENGTH, vast_image_details_file) ) {
  str[MAX_LOG_STR_LENGTH - 1]= '\0'; // just in case
  if( strlen(str) < 100 )
   continue; // this line is probably corrupted
  // exp_start= 11.05.2015 19:39:26  exp=    5  JD= 2457154.31907  ap= 12.5  rotation=   0.000  *detected=  1763  *matched=  1763  status=OK     ../MASTER_test/wcs_fd_MASTER-KISL-WFC-1_EAST_W_-30_LIGHT_5_878280.fit
  if( 2 != sscanf(str, "exp_start= %*s %*s  exp=   %*s  JD= %lf  ap= %*s  rotation=   %*s  *detected=  %*s  *matched=  %*s  %*s  %s", &logJD, filename) )
   continue;
  if( fabs(JD - logJD) < 0.00001 ) {
   fprintf(stderr, "%.5lf %s\n", JD, filename);
   image_found_in_logfile= 1;
   break;
  }
 }
 fclose(vast_image_details_file);

 // Write JD and image filename (or only JD) to the log file
 vast_list_of_bad_images_file= fopen("vast_list_of_bad_images.log", "a");
 if( vast_list_of_bad_images_file != NULL ) {
  if( image_found_in_logfile == 1 ) {
   fprintf(vast_list_of_bad_images_file, "%.5lf %s\n", JD, filename);
  } else {
   fprintf(vast_list_of_bad_images_file, "%.5lf \n", JD);
  }
  fclose(vast_list_of_bad_images_file);
 }

 return;
}

int main(int argc, char **argv) {
 // File name handling
 DIR *dp;
 struct dirent *ep;

 char **filenamelist;
 long filename_counter;
 long filename_n;
 long filenamelen;

 FILE *lightcurvefile;
 FILE *outlightcurvefile;
 double jd, mag, merr, x, y, app;
 char string[FILENAME_LENGTH];
 char comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 double *jd_a;
 double *mag_a;
 double median_mag;
 double mag_sigma;
 int i, j;

 double max_fraction_of_outliers;

 char lightcurve_tmp_filename[FILENAME_LENGTH];

 double *image_jd;     // JD is uses here as an image ID
 int *image_Noutliers; // number of outlier measurements obtained from this iamge
 int *image_Nall;      // total number of measurements obtained form this image
                       // ( = number of measured sources except the real bad ones for which no lightcurve was constructed)

 int image_counter;
 int image_Number; // number of images

 double *images_bad= NULL;
 int images_Nbad;
 int is_this_image_good;

 // char imagfilename[FILENAME_LENGTH];

 if( argc >= 2 && 0 == strcmp("-h", argv[1]) ) {
  fprintf(stderr, "Clean measurements associated with bad images from all lightcurves (out*dat files).\n");
  fprintf(stderr, "Usage:\n %s [FRACTION_OF_BAD_DETECTIONS]\nExample:\n %s 0.1 # will remove measurements form all images having at least 10 per cent of outliers.\n", argv[0], argv[0]);
  exit(0);
 }

 if( argc == 2 ) {
  max_fraction_of_outliers= atof(argv[1]);
 } else
  max_fraction_of_outliers= REMOVE_BAD_IMAGES__DEFAULT_MAX_FRACTION_OF_OUTLIERS; /* Use default value from vast_limits.h */

 jd_a= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(double));
 if( jd_a == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for jd_a(remove_bad_images.c)\n");
  exit(1);
 };
 mag_a= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(double));
 if( mag_a == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for mag_a(remove_bad_images.c)\n");
  exit(1);
 };

 image_jd= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(double));
 if( image_jd == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for image_jd(remove_bad_images.c)\n");
  exit(1);
 };
 image_Noutliers= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(int));
 if( image_Noutliers == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for image_Noutliers(remove_bad_images.c)\n");
  exit(1);
 };
 image_Nall= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(int));
 if( image_Nall == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for image_Nall(remove_bad_images.c)\n");
  exit(1);
 };

 image_Number= 0;

 dp= opendir("./");
 if( dp != NULL ) {
  fprintf(stderr, "Searching for bad images that have a large fraction (>%.2lf) of outliers...\n", max_fraction_of_outliers);
  //fprintf(stderr,"Removing measurements with large errors (>%.1lf sigma) from lightcurves... ",max_fraction_of_outliers);
  //while( ep = readdir(dp) ){
  while( (ep= readdir(dp)) != NULL ) {
   if( strlen(ep->d_name) < 8 )
    continue; // make sure the filename is not too short for the following tests
   if( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen(ep->d_name) - 1] == 't' && ep->d_name[strlen(ep->d_name) - 2] == 'a' && ep->d_name[strlen(ep->d_name) - 3] == 'd' ) {
    lightcurvefile= fopen(ep->d_name, "r");
    if( NULL == lightcurvefile ) {
     fprintf(stderr, "ERROR: Can't open file %s\n", ep->d_name);
     exit(1);
    }
    /* Compute median mag & sigma */
    i= 0;
    //while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, comments_string ) ) {
    while( -1 < read_lightcurve_point(lightcurvefile, &jd, &mag, &merr, NULL, &y, &app, string, comments_string) ) {
     if( jd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     jd_a[i]= jd;
     mag_a[i]= mag;
     i++;
    }
    fclose(lightcurvefile);
    if( i < SOFT_MIN_NUMBER_OF_POINTS ) {
     continue;
    }
    gsl_sort2(mag_a, 1, jd_a, 1, i);
    median_mag= gsl_stats_median_from_sorted_data(mag_a, 1, i);
    //mag_sigma=gsl_stats_sd(mag_a,1,i);
    //mag_sigma= esimate_sigma_from_MAD_of_unsorted_data( mag_a, i );
    mag_sigma= esimate_sigma_from_MAD_of_sorted_data(mag_a, i);
    //
    // Count outliers
    for( j= 0; j < i; j++ ) {
     for( image_counter= 0; image_counter < image_Number; image_counter++ ) {
      if( jd_a[j] == image_jd[image_counter] )
       break;
     }
     // after this image_counter should point to the corect slot
     if( image_counter == image_Number ) {
      image_jd[image_counter]= jd_a[j];  // initialize
      image_Nall[image_counter]= 0;      // initialize
      image_Noutliers[image_counter]= 0; // initialize
      image_Number++;
     }
     image_Nall[image_counter]++;
     if( fabs(mag_a[j] - median_mag) > REMOVE_BAD_IMAGES__OUTLIER_THRESHOLD * mag_sigma ) {
      image_Noutliers[image_counter]++;
      //fprintf(stderr,"Outlier found: %s %lf\n",ep->d_name,image_jd[image_counter]);
     } // if( fabs(mag_a[j]-median_mag)>5.0*mag_sigma ){
    }
   }
  }
  (void)closedir(dp);
 } else {
  perror("Couldn't open the directory\n");
 }

 free(jd_a);
 free(mag_a);

 for( images_Nbad= 0, image_counter= 0; image_counter < image_Number; image_counter++ ) {
  // Identify bad images considering fraction and the total number of outlier measurements
  //fprintf(stderr,"%d %d %d\n",image_counter,image_Nall[image_counter],image_Noutliers[image_counter]); // !!
  if( (double)image_Noutliers[image_counter] / (double)image_Nall[image_counter] > max_fraction_of_outliers && image_Noutliers[image_counter] > REMOVE_BAD_IMAGES__MAX_ALLOWED_NUMBER_OF_OUTLIERS ) {
   images_Nbad++;
   images_bad= realloc(images_bad, images_Nbad * sizeof(double));
   if( images_bad == NULL ) {
    fprintf(stderr, "ERROR: Couldn't allocate memory for images_bad(remove_bad_images.c)\n");
    exit(1);
   };
   images_bad[images_Nbad - 1]= image_jd[image_counter];
   fprintf(stderr, "Identified bad image %03d  JD%lf   Nall = %05d  Noutliers = %05d  fraction=%lf\n", image_counter, image_jd[image_counter], image_Nall[image_counter], image_Noutliers[image_counter], (double)image_Noutliers[image_counter] / (double)image_Nall[image_counter]);
   //get_image_filename_from_vast_image_details_log_using_JD( image_jd[image_counter], imagfilename);
  }
  //else{
  // fprintf(stderr,"Good image %03d  JD%lf   Nall = %05d  Noutliers = %05d  fraction=%lf\n",image_counter,image_jd[image_counter],image_Nall[image_counter],image_Noutliers[image_counter], (double)image_Noutliers[image_counter]/(double)image_Nall[image_counter]  );
  //}
 }
 fprintf(stderr, "Identified %d bad images!\n", images_Nbad);

 free(image_jd);
 free(image_Noutliers);
 free(image_Nall);

 // Sort images_bad in JD to get a nice log output
 gsl_sort(images_bad, 1, images_Nbad);
 for( image_counter= 0; image_counter < images_Nbad; image_counter++ ) {
  get_image_filename_from_vast_image_details_log_using_JD(images_bad[image_counter]);
 }

 filenamelist= (char **)malloc(MAX_NUMBER_OF_STARS * sizeof(char *));

 if( images_Nbad > 0 ) {
  fprintf(stderr, "Removing bad-image measurements from all lightcurves... ");
  //sprintf( lightcurve_tmp_filename, "lightcurve.tmp" );
  // Create a list of files
  filename_counter= 0;
  dp= opendir("./");
  if( dp != NULL ) {
   //while( ep = readdir(dp) ){
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
   return -1;
  }
  // Process each file in the list
  filename_n= filename_counter;
  /*
// On the test data I have this is not faster!
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP           
#pragma omp parallel for private( filename_counter, lightcurvefile, outlightcurvefile, lightcurve_tmp_filename, jd, mag, merr, x, y, app, string, comments_string, is_this_image_good, image_counter )
#endif
#endif
*/
  for( filename_counter= 0; filename_counter < filename_n; filename_counter++ ) {
   //for ( ; filename_counter--; ) {
   /// Re-open the lightcurve file and choose only good points
   //lightcurvefile= fopen( ep->d_name, "r" );
   lightcurvefile= fopen(filenamelist[filename_counter], "r");
   if( NULL == lightcurvefile ) {
    fprintf(stderr, "ERROR: Can't open file %s\n", filenamelist[filename_counter]);
    exit(1);
   }
   sprintf(lightcurve_tmp_filename, "lightcurve.tmp%05ld", filename_counter);
   outlightcurvefile= fopen(lightcurve_tmp_filename, "w");
   if( NULL == outlightcurvefile ) {
    fprintf(stderr, "\nAn ERROR has occured while processing file %s  median_mag=%lf mag_sigma=%lf\n", filenamelist[filename_counter], median_mag, mag_sigma);
    fprintf(stderr, "ERROR: Can't open file %s\n", lightcurve_tmp_filename);
    exit(1);
   }
   //fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&merr,&x,&y,&app,string); // Never drop the first point!
   // The while cycle is needed to handle the situation that the first lines are comments
   //jd= 0.0;
   //while( jd==0.0 ){
   // read_lightcurve_point(lightcurvefile,&jd,&mag,&merr,&x,&y,&app,string); // Never drop the first point!
   //}
   //fprintf(outlightcurvefile,"%.5lf %8.5lf %.5lf %8.3lf %8.3lf %4.1lf %s\n",jd,mag,merr,x,y,app,string);
   //write_lightcurve_point( outlightcurvefile, jd, mag, merr, x, y, app, string);
   //while(-1<fscanf(lightcurvefile,"%lf %lf %lf %lf %lf %lf %s",&jd,&mag,&merr,&x,&y,&app,string)){
   while( -1 < read_lightcurve_point(lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, comments_string) ) {
    if( jd == 0.0 )
     continue; // if this line could not be parsed, try the next one
    is_this_image_good= 1;
    for( image_counter= 0; image_counter < images_Nbad; image_counter++ ) {
     if( jd == images_bad[image_counter] ) {
      is_this_image_good= 0;
      break; // we expect only one image with matching JD
     }
    }
    if( is_this_image_good == 1 ) {
     //fprintf(outlightcurvefile,"%.5lf %8.5lf %.5lf %8.3lf %8.3lf %4.1lf %s\n",jd,mag,merr,x,y,app,string);
     write_lightcurve_point(outlightcurvefile, jd, mag, merr, x, y, app, string, comments_string);
    }
   }
   fclose(outlightcurvefile);
   fclose(lightcurvefile);
   unlink(filenamelist[filename_counter]);                          // delete old lightcurve file
   rename(lightcurve_tmp_filename, filenamelist[filename_counter]); /// move lightcurve.tmp to lightcurve file
   free(filenamelist[filename_counter]);
  }
  update_number_of_bad_images_in_log_file(images_Nbad); // Update vast_summary.log
 }                                                      // if( images_Nbad>0 ){

 free(filenamelist);

 free(images_bad);

 fprintf(stderr, "done!  =)\n");

 return 0;
}
