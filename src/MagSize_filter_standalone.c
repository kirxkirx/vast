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
#include "ident.h"                                                   // for struct Star
#include "filter_MagSize.h"                                          // for filter_MagSize()
#include "get_image_filename_from_vast_image_details_log_using_JD.h" // for get_image_filename_from_vast_image_details_log_using_JD()
                                                                     // and update_number_of_bad_images_in_log_file()

struct a_thing_to_flag {
 double jd;
 char oufilename[OUTFILENAME_LENGTH];
};

int star_number_from_outfilename( char *outfilename ) {
 unsigned int i;
 int starnumber= 0;
 char tmpstr[OUTFILENAME_LENGTH];

 for ( i= 4; i < strlen( outfilename ); i++ ) {
  tmpstr[i - 4]= outfilename[i];
 }
 tmpstr[i - 4]= '\0';
 for ( i= 0; i < strlen( tmpstr ); i++ ) {
  if ( tmpstr[i] == '_' ) {
   tmpstr[i]= '\0';
   break;
  }
 }
 starnumber= atoi( tmpstr );
 // fprintf(stderr,"%s %s %d\n",outfilename,tmpstr,starnumber);
 return starnumber;
}

int main( int argc, char **argv ) {
 DIR *dp;
 struct dirent *ep;

 FILE *lightcurvefile;
 FILE *outlightcurvefile;
 double jd, mag, merr, x, y, app;
 char string[FILENAME_LENGTH];

 double *jd_a;
 double *mag_a;
 // double median_mag;
 // double mag_sigma;
 int i;

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

 struct Star **star;
 int *NUMBER1;
 char **starfilenames;
 int starfilecounter;

 struct a_thing_to_flag *observations_to_flag;

 int star_num;

 char fakesextractorcatname[512];

 if ( argc >= 2 && 0 == strcmp( "-h", argv[1] ) ) {
  fprintf( stderr, "Clean measurements associated with bad images from all lightcurves (out*dat files).\n" );
  fprintf( stderr, "Usage:\n %s [FRACTION_OF_BAD_DETECTIONS]\nExample:\n %s 0.1 # will remove measurements form all images having at least 10 per cent of outliers.\n", argv[0], argv[0] );
  exit( 0 );
 }

 if ( argc == 2 ) {
  max_fraction_of_outliers= atof( argv[1] );
 } else {
  max_fraction_of_outliers= REMOVE_BAD_IMAGES__DEFAULT_MAX_FRACTION_OF_OUTLIERS; // Use default value from vast_limits.h
 }

 jd_a= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( jd_a == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for jd_a(MagSize_filter_standalone.c)\n" );
  exit( 1 );
 };
 mag_a= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( mag_a == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for mag_a(MagSize_filter_standalone.c)\n" );
  exit( 1 );
 };

 image_jd= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( double ) );
 if ( image_jd == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for image_a(MagSize_filter_standalone.c)\n" );
  exit( 1 );
 };
 image_Noutliers= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( int ) );
 if ( image_Noutliers == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for image_Noutliers(MagSize_filter_standalone.c)\n" );
  exit( 1 );
 };
 image_Nall= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( int ) );
 if ( image_Nall == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for image_Nall(MagSize_filter_standalone.c)\n" );
  exit( 1 );
 };

 star= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( struct Star * ) );
 if ( star == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for star(MagSize_filter_standalone.c)\n" );
  exit( 1 );
 };
 NUMBER1= malloc( MAX_NUMBER_OF_OBSERVATIONS * sizeof( int ) );
 if ( NUMBER1 == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for NUMBER1(MagSize_filter_standalone.c)\n" );
  exit( 1 );
 };
 starfilenames= malloc( MAX_NUMBER_OF_STARS * sizeof( char * ) );
 if ( starfilenames == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for starfilenames(MagSize_filter_standalone.c)\n" );
  exit( 1 );
 };
 starfilecounter= 0;

 observations_to_flag= malloc( 10 * MAX_NUMBER_OF_STARS * sizeof( struct a_thing_to_flag ) );
 if ( observations_to_flag == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for observations_to_flag(MagSize_filter_standalone.c)\n" );
  exit( 1 );
 };

 image_Number= 0;

 dp= opendir( "./" );
 if ( dp != NULL ) {
  while ( ( ep= readdir( dp ) ) != NULL ) {
   if ( strlen( ep->d_name ) < 8 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {
    lightcurvefile= fopen( ep->d_name, "r" );
    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     exit( 1 );
    }
    // Compute median mag & sigma
    star_num= star_number_from_outfilename( ep->d_name );

    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, NULL ) ) {
     if ( jd == 0.0 )
      continue; // if this line could not be parsed, try the next one
     for ( image_counter= 0; image_counter < image_Number; image_counter++ ) {
      if ( jd == image_jd[image_counter] )
       break;
     }
     // after this image_counter should point to the corect slot
     if ( image_counter == image_Number ) {
      image_jd[image_counter]= jd; // initialize
      star[image_counter]= malloc( MAX_NUMBER_OF_STARS * sizeof( struct Star ) );
      NUMBER1[image_counter]= 0;

      image_Number++;
     }

     star[image_counter][NUMBER1[image_counter]].mag= (float)mag;
     star[image_counter][NUMBER1[image_counter]].star_size= (float)app; /// WE SAVE STAR SIZE AS A FAKE APERTURE SIZE
     star[image_counter][NUMBER1[image_counter]].vast_flag= 0;
     star[image_counter][NUMBER1[image_counter]].n= star_num;

     NUMBER1[image_counter]++;
    }
    fclose( lightcurvefile );
   }
  }
  (void)closedir( dp );
 } else
  perror( "Couldn't open the directory\n" );

 free( jd_a );
 free( mag_a );

 for ( image_counter= 0; image_counter < image_Number; image_counter++ ) {
  fprintf( stderr, "%lf %d  NUMBER1[image_counter]=%d\n", image_jd[image_counter], image_counter, NUMBER1[image_counter] );
 }

 /*
 #ifdef VAST_ENABLE_OPENMP
  #ifdef _OPENMP
   #pragma omp parallel for private(image_counter)
  #endif
 #endif
*/
 for ( image_counter= 0; image_counter < image_Number; image_counter++ ) {
  // filter_MagSize(star[image_counter], NUMBER1[image_counter]);
  sprintf( fakesextractorcatname, "image%05d.cat", image_counter );
  filter_on_float_parameters( star[image_counter], NUMBER1[image_counter], fakesextractorcatname, -1 );
 }

 sprintf( lightcurve_tmp_filename, "lightcurve.tmp" );
 dp= opendir( "./" );
 if ( dp != NULL ) {
  while ( ( ep= readdir( dp ) ) != NULL ) {
   if ( strlen( ep->d_name ) < 8 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {
    lightcurvefile= fopen( ep->d_name, "r" );
    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     exit( 1 );
    }
    outlightcurvefile= fopen( lightcurve_tmp_filename, "w" );
    if ( NULL == outlightcurvefile ) {
     fprintf( stderr, "\nAn ERROR has occured while processing file %s\n", ep->d_name );
     fprintf( stderr, "ERROR: Can't open file %s\n", lightcurve_tmp_filename );
     exit( 1 );
    }
    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, NULL ) ) {
     if ( jd == 0.0 )
      continue; // if this line could not be parsed, try the next one

     for ( image_counter= 0; image_counter < image_Number; image_counter++ ) {
      if ( jd == image_jd[image_counter] ) {
       star_num= star_number_from_outfilename( ep->d_name );
       for ( i= 0; i < NUMBER1[image_counter]; i++ ) {
        if ( star_num == star[image_counter][i].n ) {
         if ( star[image_counter][i].vast_flag == 0 ) {
          write_lightcurve_point( outlightcurvefile, jd, mag, merr, x, y, app, string, NULL );
         }
         // else{
         //  fprintf(stderr,"Rejecting an outlier!\n");
         // }
         break;
        } // if( star_num==star[image_counter][i].n ){
       }  // for(i=0;i<NUMBER1[image_counter];i++){
      }   // if( jd==image_jd[image_counter] ){
     }    // for(image_counter=0;image_counter<image_Number;image_counter++){
    }
    fclose( outlightcurvefile );
    fclose( lightcurvefile );
    unlink( ep->d_name );                          // delete old lightcurve file
    rename( lightcurve_tmp_filename, ep->d_name ); /// move lightcurve.tmp to lightcurve file
   }
  }
  (void)closedir( dp );
 } else
  perror( "Couldn't open the directory\n" );

 fprintf( stderr, "\nDone :)\n" );

 // Cleanup
 free( observations_to_flag );
 for ( i= 0; i < starfilecounter; i++ ) {
  free( starfilenames[i] );
 }
 free( starfilenames );
 free( NUMBER1 );
 for ( image_counter= 0; image_counter < image_Number; image_counter++ ) {
  free( star[image_counter] );
 }
 free( star );

 free( image_jd );

 return 0; /// STOP HERE FOR NOW

 for ( images_Nbad= 0, image_counter= 0; image_counter < image_Number; image_counter++ ) {
  // Identify bad images considering fraction and the total number of outlier measurements
  // fprintf(stderr,"%d %d %d\n",image_counter,image_Nall[image_counter],image_Noutliers[image_counter]); // !!
  if ( (double)image_Noutliers[image_counter] / (double)image_Nall[image_counter] > max_fraction_of_outliers && image_Noutliers[image_counter] > REMOVE_BAD_IMAGES__MAX_ALLOWED_NUMBER_OF_OUTLIERS ) {
   images_Nbad++;
   images_bad= realloc( images_bad, images_Nbad * sizeof( double ) );
   if ( images_bad == NULL ) {
    fprintf( stderr, "ERROR: Couldn't allocate memory for images_bad(MagSize_filter_standalone.c)\n" );
    exit( 1 );
   };
   images_bad[images_Nbad - 1]= image_jd[image_counter];
   // fprintf(stderr,"Bad image %03d  JD%lf   Nall = %05d  Noutliers = %05d  fraction=%lf\n",image_counter,image_jd[image_counter],image_Nall[image_counter],image_Noutliers[image_counter], (double)image_Noutliers[image_counter]/(double)image_Nall[image_counter]  );
   // get_image_filename_from_vast_image_details_log_using_JD( image_jd[image_counter], imagfilename);
  }
 }
 fprintf( stderr, "Identified %d bad images!\n", images_Nbad );

 free( image_Noutliers );
 free( image_Nall );

 // Sort images_bad in JD to get a nice log output
 gsl_sort( images_bad, 1, images_Nbad );
 for ( image_counter= 0; image_counter < images_Nbad; image_counter++ ) {
  get_image_filename_from_vast_image_details_log_using_JD( images_bad[image_counter] );
 }

 if ( images_Nbad > 0 ) {
  fprintf( stderr, "Removing them from all lightcurves... " );
  sprintf( lightcurve_tmp_filename, "lightcurve.tmp" );
  dp= opendir( "./" );
  if ( dp != NULL ) {
   // while( ep = readdir(dp) ){
   while ( ( ep= readdir( dp ) ) != NULL ) {
    if ( strlen( ep->d_name ) < 8 )
     continue; // make sure the filename is not too short for the following tests
    if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {
     /// Re-open the lightcurve file and choose only good points
     lightcurvefile= fopen( ep->d_name, "r" );
     if ( NULL == lightcurvefile ) {
      fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
      exit( 1 );
     }
     outlightcurvefile= fopen( lightcurve_tmp_filename, "w" );
     if ( NULL == outlightcurvefile ) {
      fprintf( stderr, "\nAn ERROR has occured while processing file %s\n", ep->d_name );
      fprintf( stderr, "ERROR: Can't open file %s\n", lightcurve_tmp_filename );
      exit( 1 );
     }
     // The while cycle is needed to handle the situation that the first lines are comments
     jd= 0.0;

     while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, NULL ) ) {
      if ( jd == 0.0 )
       continue; // if this line could not be parsed, try the next one
      is_this_image_good= 1;
      for ( image_counter= 0; image_counter < images_Nbad; image_counter++ ) {
       if ( jd == images_bad[image_counter] ) {
        is_this_image_good= 0;
        break; // we expect only one image with matching JD
       }
      }
      if ( is_this_image_good == 1 ) {
       // fprintf(outlightcurvefile,"%.5lf %8.5lf %.5lf %8.3lf %8.3lf %4.1lf %s\n",jd,mag,merr,x,y,app,string);
       write_lightcurve_point( outlightcurvefile, jd, mag, merr, x, y, app, string, NULL );
      }
     }
     fclose( outlightcurvefile );
     fclose( lightcurvefile );
     unlink( ep->d_name );                          // delete old lightcurve file
     rename( lightcurve_tmp_filename, ep->d_name ); /// move lightcurve.tmp to lightcurve file
    }
   }
   update_number_of_bad_images_in_log_file( images_Nbad ); // Update vast_summary.log
   (void)closedir( dp );
  } else
   perror( "Couldn't open the directory\n" );
 } // if( images_Nbad>0 ){

 free( images_bad );

 fprintf( stderr, "done!  =)\n" );

 return 0;
}
