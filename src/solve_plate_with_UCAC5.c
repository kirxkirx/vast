#ifdef VAST_USE_SINCOS
#define _GNU_SOURCE // for sincos()
#endif

#define MAX_STARS_IN_VIZQUERY 1000
#define MAX_STARS_IN_LOCAL_CAT_QUERY MAX_STARS_IN_VIZQUERY

#define MAX_DEVIATION_AT_FIRST_STEP 6.0 / 3600.0 // 5.0/3600.0 //1.8/3600.0
#define REFERENCE_LOCAL_SOLUTION_RADIUS_DEG 1.0

#define MIN_APASS_MAG 1.0
#define MAX_APASS_MAG 18.0
#define MIN_APASS_MAG_ERR 0.0
#define MAX_APASS_MAG_ERR 1.0

#define DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN 40.0

#define VIZIER_SITE "$(\"$VAST_PATH\"lib/choose_vizier_mirror.sh)"

// When VizieR is in a bad mood, 300 sec is not nearly enough
#define VIZIER_TIMEOUT_SEC 900

#include <stdio.h>
#include <stdlib.h>
#include <getopt.h>

#include <string.h>

#include <libgen.h>    // for basename()
#include <sys/types.h> // for getpid()
#include <unistd.h>    // also for getpid(), unlink(), sleep() ...
#include <math.h>

#include <time.h> // for seeding the random number generator with srand(time(NULL))

#include <sys/wait.h> // for waitpid() in execute_curl_direct()
#include <ctype.h>    // for isspace() in parse_shell_args()

#include <gsl/gsl_statistics.h>
#include <gsl/gsl_sort.h>

#include "get_path_to_vast.h"

#include "fit_plane_lin.h"
#include "fitsio.h"
#include "fitsfile_read_check.h"
#include "vast_limits.h"
#include "vast_types.h"
#include "ident.h"

#include "wpolyfit.h"

#include "variability_indexes.h" // for esimate_sigma_from_MAD_of_unsorted_data() and c4()

#include "is_point_close_or_off_the_frame_edge.h" // for is_point_close_or_off_the_frame_edge()

#include "replace_file_with_symlink_if_filename_contains_white_spaces.h"

#include "count_lines_in_ASCII_file.h" // for count_lines_in_ASCII_file()

#include "vast_is_file.h"

// 8192 is out of nowhere
#define BASE_COMMAND_LENGTH 1024 + 3 * VAST_PATH_MAX + 2 * FILENAME_LENGTH + 8192

struct str_catalog_search_parameters {
 double search_radius_deg;
 double search_radius_second_step_deg;
 double brightest_mag;
 double faintest_mag;
};

struct detected_star {
 int n_current_frame; // star number in the input SExtractor catalog
 double x_pix;        // star position
 double y_pix;
 double ra_deg_measured;
 double dec_deg_measured;
 double flux;
 double flux_err;
 double mag;
 double mag_err;
 int flag;
 /////////////////////////
 double ra_deg_measured_orig;
 double dec_deg_measured_orig;
 /////////////////////////
 int matched_with_astrometric_catalog;
 int matched_with_photometric_catalog;
 double match_distance_astrometric_catalog_arcsec;
 //  char ucac4id[32];
 double d_ra;
 double d_dec;
 double computed_d_ra;
 double computed_d_dec;
 double corrected_ra_planefit;
 double corrected_dec_planefit;
 double corrected_mag_ra;
 double corrected_mag_dec;
 double local_correction_ra;
 double local_correction_dec;
 double corrected_ra_local;
 double corrected_dec_local;
 double catalog_ra;           // catalog position computed for the observation epoch (taking proper motion into account)
 double catalog_dec;          // catalog position computed for the observation epoch (taking proper motion into account)
 double catalog_ra_original;  // originl position from the catalog for the catalog epoch
 double catalog_dec_original; // originl position from the catalog for the catalog epoch
 double catalog_mag;
 double catalog_mag_err;
 int good_star;
 /////////////////////////
 double APASS_B;
 double APASS_B_err;
 double APASS_V;
 double APASS_V_err;
 double APASS_r;
 double APASS_r_err;
 double APASS_i;
 double APASS_i_err;
 double APASS_g;
 double APASS_g_err;
 /////////////////////////
 double Rc_computed_from_APASS_ri;
 double Rc_computed_from_APASS_ri_err;
 //
 double Ic_computed_from_APASS_ri;
 double Ic_computed_from_APASS_ri_err;
 /////////////////////////
 double estimated_local_correction_accuracy;
 //
 double observing_epoch_jd;
};

static inline double compute_distance_on_sphere( double RA1_deg, double DEC1_deg, double RA2_deg, double DEC2_deg ) {
 double distance;
 double deg2rad_conversion= M_PI / 180.0;
 double RA1_rad= RA1_deg * deg2rad_conversion;
 double DEC1_rad= DEC1_deg * deg2rad_conversion;
 double RA2_rad= RA2_deg * deg2rad_conversion;
 double DEC2_rad= DEC2_deg * deg2rad_conversion;

 double cos_DEC1_rad;
 double sin_DEC1_rad;
 double cos_DEC2_rad;
 double sin_DEC2_rad;

#ifdef VAST_USE_SINCOS
 sincos( DEC1_rad, &sin_DEC1_rad, &cos_DEC1_rad );
 sincos( DEC2_rad, &sin_DEC2_rad, &cos_DEC2_rad );
#else
 cos_DEC1_rad= cos( DEC1_rad );
 sin_DEC1_rad= sin( DEC1_rad );
 cos_DEC2_rad= cos( DEC2_rad );
 sin_DEC2_rad= sin( DEC2_rad );
#endif

 // distance=acos(cos(DEC1_rad)*cos(DEC2_rad)*cos(MAX(RA1_rad,RA2_rad)-MIN(RA1_rad,RA2_rad))+sin(DEC1_rad)*sin(DEC2_rad))/deg2rad_conversion;
 distance= acos( cos_DEC1_rad * cos_DEC2_rad * cos( MAX( RA1_rad, RA2_rad ) - MIN( RA1_rad, RA2_rad ) ) + sin_DEC1_rad * sin_DEC2_rad ) / deg2rad_conversion;

 return distance;
}

void debug_dump_star_struct( struct detected_star *stars, int N ) {
 int i;
 FILE *f;
 f= fopen( "debug_dump_star_struct.txt", "w" );
 for ( i= 0; i < N; i++ ) {
  fprintf( f, "%lf %lf %lf %lf %lf %lf\n",
           stars[i].ra_deg_measured,
           stars[i].dec_deg_measured,
           stars[i].match_distance_astrometric_catalog_arcsec,
           stars[i].catalog_ra,
           stars[i].catalog_dec,
           stars[i].catalog_mag );
 }
 fclose( f );
 return;
}

void wcs_basename( const char *filename, char *new_filename ) {
 // Duplicate the filename, as basename might modify the original string
 char filename_copy[FILENAME_LENGTH];
 char basename_str[FILENAME_LENGTH];
 char *fz_extension_position;
 size_t basename_len;

 strncpy( filename_copy, filename, FILENAME_LENGTH - 1 );
 filename_copy[FILENAME_LENGTH - 1]= '\0'; // just in case
 strncpy( basename_str, basename( filename_copy ), FILENAME_LENGTH - 1 );
 basename_str[FILENAME_LENGTH - 1]= '\0'; // just in case

 // Strip .fz extension if present
 basename_len= strlen( basename_str );
 if ( basename_len > 3 ) {
  fz_extension_position= basename_str + basename_len - 3;
  if ( strcmp( fz_extension_position, ".fz" ) == 0 ) {
   *fz_extension_position= '\0';
  }
 }

 // Check if the basename already starts with "wcs_"
 if ( strncmp( basename_str, "wcs_", 4 ) == 0 ) {
  // No need to add the prefix, copy the basename without .fz
  strncpy( new_filename, basename_str, FILENAME_LENGTH - 1 );
  new_filename[FILENAME_LENGTH - 1]= '\0';
  return;
 }

 // Copy the "wcs_" prefix and the basename to the new string
 strcpy( new_filename, "wcs_" );
 strcat( new_filename, basename_str );

 return;
}

void remove_outliers_from_a_pair_of_arrays( double *a, double *b, int *N_good ) {
 int i, j;
 double median1, MAD1, M1;
 double median2, MAD2, M2;
 double *copy_a;
 int copy_N_good= ( *N_good );
 if ( copy_N_good < 3 )
  return; // return right away if the input arrays are too small
 copy_a= malloc( copy_N_good * sizeof( double ) );
 if ( copy_a == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for copy_a\n" );
  exit( EXIT_FAILURE );
 };
 //
 for ( i= 0; i < copy_N_good; i++ )
  copy_a[i]= 0; //
 //
 // Compute median
 gsl_sort( a, 1, copy_N_good );
 median1= gsl_stats_median_from_sorted_data( a, 1, copy_N_good );
 MAD1= gsl_stats_absdev_m( a, 1, copy_N_good, median1 );
 gsl_sort( b, 1, copy_N_good );
 median2= gsl_stats_median_from_sorted_data( b, 1, copy_N_good );
 MAD2= gsl_stats_absdev_m( b, 1, copy_N_good, median2 );
 for ( i= 0, j= 0; i < copy_N_good; i++ ) {
  // taken from http://www.itl.nist.gov/div898/handbook/eda/section3/eda35h.htm
  M1= 0.6745 * ( a[i] - median1 ) / MAD1;
  M2= 0.6745 * ( b[i] - median2 ) / MAD2;
  // fprintf(stderr,"%lf %lf  %lf %lf  %lf %lf\n",a[i]*3600,b[i]*3600,median1*3600,median2*3600,M1,M2);
  if ( fabs( M1 ) < 3.5 && fabs( M2 ) < 3.5 ) {
   copy_a[j]= a[i];
   j++;
  }
 }
 // for(i=0;i<j;i++)
 for ( i= 0; i < MIN( j, copy_N_good ); i++ ) {
  // fprintf(stderr,"%lg %d\n",copy_a[j],j);
  a[i]= copy_a[j];
 }
 //(*N_good)=j;
 ( *N_good )= MIN( j, copy_N_good );
 free( copy_a );
 return;
}

void set_catalog_search_parameters( double approximate_field_of_view_arcmin, struct str_catalog_search_parameters *catalog_search_parameters ) {
 catalog_search_parameters->search_radius_deg= MAX_DEVIATION_AT_FIRST_STEP * 0.5 * approximate_field_of_view_arcmin / 60.0;
 catalog_search_parameters->brightest_mag= 1.0;
 // catalog_search_parameters->faintest_mag= 9.0;
 //  We need fainter stars for UCAC5!
 catalog_search_parameters->faintest_mag= 13.5;
 // if ( approximate_field_of_view_arcmin < 500.0 ) {
 if ( approximate_field_of_view_arcmin < 600.0 ) {
  catalog_search_parameters->search_radius_deg= MAX_DEVIATION_AT_FIRST_STEP * 0.5 * approximate_field_of_view_arcmin / 60.0;
  catalog_search_parameters->brightest_mag= 2.0;
  catalog_search_parameters->faintest_mag= 13.5;
 }
 // NMW scale
 // change as the input approximate_field_of_view_arcmin is now the actual major side of the frame rather than a crude estiamte
 // if ( approximate_field_of_view_arcmin < 400.0 ) {
 if ( approximate_field_of_view_arcmin < 500.0 ) {
  catalog_search_parameters->search_radius_deg= MAX_DEVIATION_AT_FIRST_STEP * 0.5 * approximate_field_of_view_arcmin / 60.0;
  // catalog_search_parameters->brightest_mag= 5.0;
  catalog_search_parameters->brightest_mag= 2.0;
  catalog_search_parameters->faintest_mag= 13.5;
 }
 if ( approximate_field_of_view_arcmin < 240.0 ) {
  catalog_search_parameters->search_radius_deg= MAX_DEVIATION_AT_FIRST_STEP * 0.5 * approximate_field_of_view_arcmin / 60.0;
  catalog_search_parameters->brightest_mag= 6.0;
  catalog_search_parameters->faintest_mag= 14.0;
 }
 if ( approximate_field_of_view_arcmin < 120.0 ) {
  catalog_search_parameters->search_radius_deg= MAX_DEVIATION_AT_FIRST_STEP * approximate_field_of_view_arcmin / 60.0;
  catalog_search_parameters->brightest_mag= 7.0; // 9.0;
  catalog_search_parameters->faintest_mag= 16.5;
 }
 if ( approximate_field_of_view_arcmin < 60.0 ) {
  catalog_search_parameters->search_radius_deg= MAX_DEVIATION_AT_FIRST_STEP; // * approximate_field_of_view_arcmin / 60.0;
  catalog_search_parameters->brightest_mag= 10.0;                            // let's keep it low becasue of the photographic plates
  catalog_search_parameters->faintest_mag= 17.0;
 }
 if ( approximate_field_of_view_arcmin < 30.0 ) {
  catalog_search_parameters->search_radius_deg= MAX( 2.0 / 3600.0, MAX_DEVIATION_AT_FIRST_STEP * approximate_field_of_view_arcmin / 60.0 );
  catalog_search_parameters->brightest_mag= 9.0;
  catalog_search_parameters->faintest_mag= 20.0;
 }
 if ( approximate_field_of_view_arcmin < 15.0 ) {
  catalog_search_parameters->search_radius_deg= MAX( 1.5 / 3600.0, MAX_DEVIATION_AT_FIRST_STEP * approximate_field_of_view_arcmin / 60.0 );
  catalog_search_parameters->brightest_mag= 12.0;
  catalog_search_parameters->faintest_mag= 20.0;
 }
 // HST
 if ( approximate_field_of_view_arcmin < 5.0 ) {
  catalog_search_parameters->search_radius_deg= 1.5 / 3600.0;
  catalog_search_parameters->brightest_mag= 12.0;
  catalog_search_parameters->faintest_mag= 22.0;
 }
 catalog_search_parameters->search_radius_second_step_deg= 0.8 * catalog_search_parameters->search_radius_deg;

 fprintf( stderr, "UCAC5 catalog search parameters:\n \
                   catalog_search_parameters->search_radius_deg= %lf (%.1lf arcsec)\n \
                   catalog_search_parameters->brightest_mag= %.2lf\n \
                   catalog_search_parameters->faintest_mag= %.2lf\n \
                   catalog_search_parameters->search_radius_second_step_deg %lf (%.1lf arcsec)\n",
          catalog_search_parameters->search_radius_deg, catalog_search_parameters->search_radius_deg * 3600,
          catalog_search_parameters->brightest_mag,
          catalog_search_parameters->faintest_mag,
          catalog_search_parameters->search_radius_second_step_deg, catalog_search_parameters->search_radius_second_step_deg * 3600 );

 return;
}

int blind_plate_solve_with_astrometry_net( char *fits_image_filename, double approximate_field_of_view_arcmin ) {
 char cmdstr[2 * FILENAME_LENGTH + VAST_PATH_MAX];
 char path_to_vast_string[VAST_PATH_MAX];
 get_path_to_vast( path_to_vast_string );
 sprintf( cmdstr, "%sutil/wcs_image_calibration.sh %s %.1lf", path_to_vast_string, fits_image_filename, approximate_field_of_view_arcmin );
 fprintf( stderr, "Trying to blindly solve the plate...\n%s\n", cmdstr );
 if ( 0 != system( cmdstr ) ) {
  fprintf( stderr, "ERROR solving the plate!\n" );
  return 1;
 }
 return 0;
}

void guess_wcs_catalog_filename( char *wcs_catalog_filename, char *fits_image_filename ) {
 char test_string[FILENAME_LENGTH];
 char *fz_extension_position;
 size_t test_string_len;

 strcpy( test_string, basename( fits_image_filename ) );

 // Strip .fz extension if present (to match shell script behavior)
 test_string_len= strlen( test_string );
 if ( test_string_len > 3 ) {
  fz_extension_position= test_string + test_string_len - 3;
  if ( strcmp( fz_extension_position, ".fz" ) == 0 ) {
   *fz_extension_position= '\0';
  }
 }

 if ( test_string[0] == 'w' && test_string[1] == 'c' && test_string[2] == 's' && test_string[3] == '_' ) {
  wcs_catalog_filename[0]= '\0';
 } else {
  strncpy( wcs_catalog_filename, "wcs_", FILENAME_LENGTH );
  wcs_catalog_filename[FILENAME_LENGTH - 1]= '\0';
 }
 strncat( wcs_catalog_filename, test_string, FILENAME_LENGTH - strlen( wcs_catalog_filename ) );
 wcs_catalog_filename[FILENAME_LENGTH - 1]= '\0';
 strncat( wcs_catalog_filename, ".cat", FILENAME_LENGTH - strlen( wcs_catalog_filename ) );
 wcs_catalog_filename[FILENAME_LENGTH - 1]= '\0';
 // fprintf(stderr,"test_string=#%s#\n",test_string);
 // fprintf(stderr,"fits_image_filename=#%s#\n",fits_image_filename);
 // fprintf(stderr,"wcs_catalog_filename=#%s#\n",wcs_catalog_filename);
 return;
}

/*
void guess_wcs_catalog_filename_old_does_not_hanlde_fz( char *wcs_catalog_filename, char *fits_image_filename ) {
 char test_string[FILENAME_LENGTH];
 strcpy( test_string, basename( fits_image_filename ) );
 if ( test_string[0] == 'w' && test_string[1] == 'c' && test_string[2] == 's' && test_string[3] == '_' ) {
  wcs_catalog_filename[0]= '\0';
 } else {
  strncpy( wcs_catalog_filename, "wcs_", FILENAME_LENGTH );
  wcs_catalog_filename[FILENAME_LENGTH - 1]= '\0';
 }
 strncat( wcs_catalog_filename, test_string, FILENAME_LENGTH - strlen( wcs_catalog_filename ) );
 wcs_catalog_filename[FILENAME_LENGTH - 1]= '\0';
 strncat( wcs_catalog_filename, ".cat", FILENAME_LENGTH - strlen( wcs_catalog_filename ) );
 wcs_catalog_filename[FILENAME_LENGTH - 1]= '\0';
 // fprintf(stderr,"test_string=#%s#\n",test_string);
 // fprintf(stderr,"fits_image_filename=#%s#\n",fits_image_filename);
 // fprintf(stderr,"wcs_catalog_filename=#%s#\n",wcs_catalog_filename);
 return;
}
*/

int check_if_the_output_catalog_already_exist( char *fits_image_filename ) {
 FILE *f;
 int i;
 char wcs_catalog_filename[FILENAME_LENGTH + 32];
 char string[1024];
 guess_wcs_catalog_filename( wcs_catalog_filename, fits_image_filename );
 strncat( wcs_catalog_filename, ".ucac5", FILENAME_LENGTH );
 wcs_catalog_filename[FILENAME_LENGTH - 1]= '\0'; // just in case
 f= fopen( wcs_catalog_filename, "r" );
 if ( f == NULL ) {
  return 0; // OK, the catalog is not there
 }
 // Check that the catalog is not empty
 i= 0;
 while ( NULL != fgets( string, 1024, f ) ) {
  i++;
  if ( i > MIN_NUMBER_OF_STARS_FOR_UCAC5_MATCH )
   break;
 }
 fclose( f );
 if ( i > MIN_NUMBER_OF_STARS_FOR_UCAC5_MATCH ) {
  fprintf( stderr, "The output catalog %s already exist.\n", wcs_catalog_filename );
  return 1;
 }
 // hmm, the catalog is there but there are too few lines in it
 return 0;
}

void write_wcs_catalog( char *fits_image_filename, struct detected_star *stars, int number_of_stars_in_wcs_catalog ) {
 FILE *f;
 int i;
 char wcs_catalog_filename[FILENAME_LENGTH];
 guess_wcs_catalog_filename( wcs_catalog_filename, fits_image_filename );
 strcat( wcs_catalog_filename, ".ucac5" );
 if ( number_of_stars_in_wcs_catalog < 1 ) {
  fprintf( stderr, "ERROR: in write_wcs_catalog()  number_of_stars_in_wcs_catalog=%d\n", number_of_stars_in_wcs_catalog );
  return;
 }
 f= fopen( wcs_catalog_filename, "w" );
 if ( f == NULL ) {
  fprintf( stderr, "ERROR opening %s for writing!\n", wcs_catalog_filename );
  return;
 }
 for ( i= 0; i < number_of_stars_in_wcs_catalog; i++ ) {
  fprintf( f, "%6d %11.7lf %+10.7lf %9.4lf %9.4lf  %9.1lf %9.1lf %+7.4lf %6.4lf %3d    %6.3lf %5.3lf  %6.3lf %5.3lf  %6.3lf %5.3lf  %6.3lf %5.3lf  %6.3lf %5.3lf  %6.3lf %5.3lf %6.3lf %5.3lf  %6.3lf %5.3lf\n",
           stars[i].n_current_frame,
           stars[i].corrected_ra_local,
           stars[i].corrected_dec_local,
           stars[i].x_pix,
           stars[i].y_pix,
           stars[i].flux,
           stars[i].flux_err,
           stars[i].mag,
           stars[i].mag_err,
           stars[i].flag,
           stars[i].catalog_mag,
           stars[i].catalog_mag_err,
           stars[i].APASS_B,
           stars[i].APASS_B_err,
           stars[i].APASS_V,
           stars[i].APASS_V_err,
           stars[i].APASS_r,
           stars[i].APASS_r_err,
           stars[i].APASS_i,
           stars[i].APASS_i_err,
           stars[i].Rc_computed_from_APASS_ri,
           stars[i].Rc_computed_from_APASS_ri_err,
           stars[i].Ic_computed_from_APASS_ri,
           stars[i].Ic_computed_from_APASS_ri_err,
           stars[i].APASS_g,
           stars[i].APASS_g_err );
 }
 fclose( f );
 fprintf( stderr, "The image catalog is written to %s\n", wcs_catalog_filename );
 return;
}

void write_matched_stars_to_ds9_region( char *fits_image_filename, struct detected_star *stars, int number_of_stars_in_wcs_catalog ) {
 FILE *f;
 int i;
 char wcs_catalog_filename[FILENAME_LENGTH];
 guess_wcs_catalog_filename( wcs_catalog_filename, fits_image_filename );
 strcat( wcs_catalog_filename, ".ds9.reg" );
 f= fopen( wcs_catalog_filename, "w" );
 if ( f == NULL ) {
  fprintf( stderr, "ERROR opening %s for writing!\n", wcs_catalog_filename );
  return;
 }
 fprintf( f, "# Region file format: DS9 version 4.0\n" );
 fprintf( f, "# Filename:\n" );
 fprintf( f, "global color=green font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source\n" );
 fprintf( f, "image\n" );
 for ( i= 0; i < number_of_stars_in_wcs_catalog; i++ )
  if ( stars[i].matched_with_astrometric_catalog == 1 )
   fprintf( f, "# text(%lf,%lf) text={%5.2lf}\ncircle(%lf,%lf,4.0)\n", stars[i].x_pix, stars[i].y_pix, ( stars[i].catalog_dec - stars[i].corrected_dec_local ) * 3600, stars[i].x_pix, stars[i].y_pix );
 fclose( f );
 fprintf( stderr, "The DS9 region file with the matched stars is written to %s\nYou may view it with the command:\n ds9 %s -region %s\n", wcs_catalog_filename, fits_image_filename, wcs_catalog_filename );
 return;
}

void write_astrometric_residuals_vector_field( char *fits_image_filename, struct detected_star *stars, int number_of_stars_in_wcs_catalog ) {
 FILE *f;
 int i;
 char wcs_catalog_filename[FILENAME_LENGTH];
 guess_wcs_catalog_filename( wcs_catalog_filename, fits_image_filename );
 strcat( wcs_catalog_filename, ".astrometric_residuals" );
 if ( number_of_stars_in_wcs_catalog < 1 ) {
  fprintf( stderr, "ERROR: in write_wcs_catalog()  number_of_stars_in_wcs_catalog=%d\n", number_of_stars_in_wcs_catalog );
  return;
 }
 f= fopen( wcs_catalog_filename, "w" );
 if ( f == NULL ) {
  fprintf( stderr, "ERROR opening %s for writing!\n", wcs_catalog_filename );
  return;
 }
 for ( i= 0; i < number_of_stars_in_wcs_catalog; i++ ) {
  if ( stars[i].matched_with_astrometric_catalog == 1 ) {
   fprintf( f, "%11.7lf %+10.7lf %+10.7lf %+10.7lf  %11.7lf  %+10.7f %+10.7lf  %9.4lf %9.4lf \n",
            stars[i].corrected_ra_local,
            stars[i].corrected_dec_local,
            stars[i].corrected_ra_local - stars[i].catalog_ra,
            stars[i].corrected_dec_local - stars[i].catalog_dec,
            3600 * sqrt( ( stars[i].corrected_ra_local - stars[i].catalog_ra ) * cos( stars[i].catalog_dec * M_PI / 180.0 ) * ( stars[i].corrected_ra_local - stars[i].catalog_ra ) * cos( stars[i].catalog_dec * M_PI / 180.0 ) + ( stars[i].corrected_dec_local - stars[i].catalog_dec ) * ( stars[i].corrected_dec_local - stars[i].catalog_dec ) ),
            3600 * ( stars[i].corrected_ra_local - stars[i].catalog_ra ) * cos( stars[i].catalog_dec * M_PI / 180.0 ),
            3600 * ( stars[i].corrected_dec_local - stars[i].catalog_dec ),
            stars[i].x_pix,
            stars[i].y_pix );
  }
 }
 fclose( f );
 fprintf( stderr, "The astrometric residuals vector field is written to %s\n", wcs_catalog_filename );
 return;
}

int read_wcs_catalog( char *fits_image_filename, struct detected_star *stars, int *number_of_stars_in_wcs_catalog ) {
 FILE *f;
 int i;
 char wcs_catalog_filename[FILENAME_LENGTH];
 double JD;
 int timesys;
 // char char_garbage[4096];
 double X_im_size;
 double Y_im_size;
 int good_stars_counter= 0;

 int nodrop_counter;
 int drop_zero_flux_counter;
 int drop_no_flux_err_counter;
 int drop_mag_99_counter;
 int drop_mag_err_99_counter;
 int drop_low_SNR_counter;
 int blend_counter;

 char sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT]; // this is for debug only!!!

 int max_acceptable_SE_flag= 1;

 timesys= 0; // for gettime()
 // gettime( fits_image_filename, &double_garbage, &timesys, 0, &X_im_size, &Y_im_size, char_garbage, char_garbage, 0, 0); // This is just an overkill way to get X_im_size Y_im_size
 gettime( fits_image_filename, &JD, &timesys, 0, &X_im_size, &Y_im_size, NULL, NULL, 0, 0, NULL ); // This is to get observing time for proper motion correction and X_im_size Y_im_size

 guess_wcs_catalog_filename( wcs_catalog_filename, fits_image_filename );
 fprintf( stderr, "WCS catalog name: %s \n", wcs_catalog_filename );
 f= fopen( wcs_catalog_filename, "r" );
 if ( f == NULL ) {
  return 1;
 }
 // count the proportion of blended sources
 i= 0;
 nodrop_counter= drop_zero_flux_counter= drop_no_flux_err_counter= drop_mag_99_counter= drop_mag_err_99_counter= drop_low_SNR_counter= blend_counter= 0;
 while ( -1 < fscanf( f, "%d %lf %lf %lf %lf  %lf %lf %lf %lf %d", &stars[i].n_current_frame, &stars[i].ra_deg_measured, &stars[i].dec_deg_measured, &stars[i].x_pix, &stars[i].y_pix, &stars[i].flux, &stars[i].flux_err, &stars[i].mag, &stars[i].mag_err, &stars[i].flag ) ) {
  ///
  if ( stars[i].flux == 0 ) {
   drop_zero_flux_counter++;
   continue;
  }
  if ( stars[i].flux_err == 999999 ) {
   drop_no_flux_err_counter++;
   continue;
  }
  if ( stars[i].mag == 99.0000 ) {
   drop_mag_99_counter++;
   continue;
  }
  if ( stars[i].mag_err == 99.0000 ) {
   drop_mag_err_99_counter++;
   continue;
  }
  if ( stars[i].flux < MIN_SNR * stars[i].flux_err ) {
   drop_low_SNR_counter++;
   continue;
  }
  ///
  // if( stars[i].flag==0 )
  if ( stars[i].flag <= max_acceptable_SE_flag ) {
   stars[i].good_star= 1;
  } else {
   stars[i].good_star= 0;
   blend_counter++;
  }
 }
 if ( (double)blend_counter / (double)i > 0.33333 ) {
  fprintf( stderr, "The fraction of blended stars is high!\n" );
  // max_acceptable_SE_flag= 3;
  // fprintf( stderr, "The fraction of blended stars is high - will accept them for catalog matching!\nThe maximum acceptable Source Extractor flag is %d\n", max_acceptable_SE_flag);
 }
 fseek( f, 0, SEEK_SET ); // go back to the beginning of the log file
 // do the actual thing
 i= 0;
 nodrop_counter= drop_zero_flux_counter= drop_no_flux_err_counter= drop_mag_99_counter= drop_mag_err_99_counter= drop_low_SNR_counter= blend_counter= 0;
 while ( -1 < fscanf( f, "%d %lf %lf %lf %lf  %lf %lf %lf %lf %d", &stars[i].n_current_frame, &stars[i].ra_deg_measured, &stars[i].dec_deg_measured, &stars[i].x_pix, &stars[i].y_pix, &stars[i].flux, &stars[i].flux_err, &stars[i].mag, &stars[i].mag_err, &stars[i].flag ) ) {
  ///
  if ( stars[i].flux == 0 ) {
   drop_zero_flux_counter++;
   continue;
  }
  if ( stars[i].flux_err == 999999 ) {
   drop_no_flux_err_counter++;
   continue;
  }
  if ( stars[i].mag == 99.0000 ) {
   drop_mag_99_counter++;
   continue;
  }
  if ( stars[i].mag_err == 99.0000 ) {
   drop_mag_err_99_counter++;
   continue;
  }
  if ( stars[i].flux < MIN_SNR * stars[i].flux_err ) {
   drop_low_SNR_counter++;
   continue;
  }
  ///
  // if( stars[i].flag==0 )
  if ( stars[i].flag <= max_acceptable_SE_flag ) {
   stars[i].good_star= 1;
  } else {
   stars[i].good_star= 0;
   blend_counter++;
  }
  //
  stars[i].ra_deg_measured_orig= stars[i].ra_deg_measured;
  stars[i].dec_deg_measured_orig= stars[i].dec_deg_measured;
  // set default values of the derived parameters
  stars[i].matched_with_astrometric_catalog= 0; // no catalog match at first
  stars[i].matched_with_photometric_catalog= 0; // no catalog match at first
  // stars[i].distance_from_image_edge= MIN( stars[i].x_pix, stars[i].y_pix );
  // stars[i].distance_from_image_edge= MIN( stars[i].distance_from_image_edge, X_im_size - stars[i].x_pix );
  // stars[i].distance_from_image_edge= MIN( stars[i].distance_from_image_edge, Y_im_size - stars[i].y_pix );
  // if ( stars[i].distance_from_image_edge < FRAME_EDGE_INDENT_PIXELS )
  if ( 1 == is_point_close_or_off_the_frame_edge( stars[i].x_pix, stars[i].y_pix, X_im_size, Y_im_size, FRAME_EDGE_INDENT_PIXELS ) ) {
   stars[i].good_star= 0;
  }
  if ( stars[i].good_star == 1 ) {
   good_stars_counter++;
  }
  //
  nodrop_counter++;
  //
  stars[i].estimated_local_correction_accuracy= 0.0; // initialize
  //
  // Initialize all the remaining stuff
  // stars[i].ucac4id[0]='\0';
  stars[i].d_ra= stars[i].d_dec= stars[i].computed_d_ra= stars[i].computed_d_dec= stars[i].corrected_ra_planefit= 0.0;
  stars[i].corrected_mag_ra= stars[i].catalog_mag_err= stars[i].local_correction_ra= stars[i].local_correction_dec= 0.0;
  stars[i].corrected_ra_local= stars[i].corrected_dec_local= stars[i].catalog_ra= stars[i].catalog_dec= 0.0;
  stars[i].catalog_ra_original= stars[i].catalog_dec_original= 0.0;
  stars[i].catalog_mag= stars[i].catalog_mag_err= stars[i].APASS_B= stars[i].APASS_B_err= stars[i].APASS_V= stars[i].APASS_V_err= 0.0;
  stars[i].APASS_r= stars[i].APASS_r_err= stars[i].APASS_i= stars[i].APASS_i_err= stars[i].Rc_computed_from_APASS_ri= stars[i].Rc_computed_from_APASS_ri_err= stars[i].Ic_computed_from_APASS_ri= stars[i].Ic_computed_from_APASS_ri_err= 0.0;
  stars[i].APASS_g= stars[i].APASS_g_err= 0.0;
  //
  stars[i].observing_epoch_jd= JD;
  //
  i++;
  if ( i >= MAX_NUMBER_OF_STARS ) {
   fprintf( stderr, "ERROR: too many stars in the SExtractor catalog file %s\n", wcs_catalog_filename );
   fclose( f );
   return 1;
  }
 }
 //
 fprintf( stderr, "SExtractor catalog parsing summary: zero_flux=%d, no_flux_err=%d, no_mag=%d, no_mag_err=%d, low_SNR=%d, blended=%d, passed=%d\n", drop_zero_flux_counter, drop_no_flux_err_counter, drop_mag_99_counter, drop_mag_err_99_counter, drop_low_SNR_counter, blend_counter, nodrop_counter );
 //
 ( *number_of_stars_in_wcs_catalog )= i;
 fclose( f );
 if ( i < MIN_NUMBER_OF_STARS_ON_FRAME ) {
  fprintf( stderr, "ERROR: too few stars (%d<%d) in the SExtractor catalog file %s\n", i, MIN_NUMBER_OF_STARS_ON_FRAME, wcs_catalog_filename );
  // Print the catalog for debug purposes
  fprintf( stderr, "Here are the first few lines of the catalog - check for obvious formatting problems:\n" );
  i= 0;
  f= fopen( wcs_catalog_filename, "r" );
  if ( f == NULL ) {
   fprintf( stderr, "ERROR: re-opening the catalog!\n" );
  } else {
   while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, f ) ) {
    sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT - 1]= '\0'; // just in case
    fprintf( stderr, "%s\n", sextractor_catalog_string );
    // display only the first few lines
    i++;
    if ( i > 5 ) {
     break;
    }
   }
   fclose( f );
  }
  //
  return 1;
 }
 fprintf( stderr, "Got %d stars (including %d good ones) from the SExtractor catalog %s \n", i, good_stars_counter, wcs_catalog_filename );
 return 0;
}

int read_UCAC5_from_vizquery( struct detected_star *stars, int N, char *vizquery_output_filename, struct str_catalog_search_parameters *catalog_search_parameters ) {
 FILE *f;
 char string[1024];
 int i;
 double measured_ra, measured_dec, distance, catalog_ra, catalog_dec, catalog_mag; //,catalog_mag_err;
 double catalog_ra_original, catalog_dec_original;
 double cos_delta;
 int N_stars_matched_with_astrometric_catalog= 0;

 double epoch, pmRA, e_pmRA, pmDE, e_pmDE;

 double observing_epoch_jy, dt;

 f= fopen( vizquery_output_filename, "r" );
 while ( NULL != fgets( string, 1024, f ) ) {
  if ( string[0] == '#' )
   continue;
  if ( string[0] == '\n' )
   continue;
  if ( string[0] == '-' )
   continue;
  if ( string[0] == '_' )
   continue;
  if ( string[0] == ' ' )
   continue;
  if ( string[0] != ' ' && string[0] != '0' && string[0] != '1' && string[0] != '2' && string[0] != '3' && string[0] != '4' && string[0] != '5' && string[0] != '6' && string[0] != '7' && string[0] != '8' && string[0] != '9' )
   continue;

  // This returns only stars with measured PM
  // if( 8>sscanf(string,"%lf %lf %lf  %lf %lf %lf  %lf %lf %lf %lf %lf",&measured_ra,&measured_dec,&distance, &catalog_ra,&catalog_dec,&catalog_mag,&epoch, &pmRA,&e_pmRA,&pmDE,&e_pmDE) )continue;
  epoch= pmRA= e_pmRA= pmDE= e_pmDE= 0.0;
  if ( 8 > sscanf( string, "%lf %lf %lf  %lf %lf %lf  %lf %lf %lf %lf %lf", &measured_ra, &measured_dec, &distance, &catalog_ra, &catalog_dec, &catalog_mag, &epoch, &pmRA, &e_pmRA, &pmDE, &e_pmDE ) ) {
   if ( 6 > sscanf( string, "%lf %lf %lf  %lf %lf %lf  %lf %lf %lf %lf %lf", &measured_ra, &measured_dec, &distance, &catalog_ra, &catalog_dec, &catalog_mag, &epoch, &pmRA, &e_pmRA, &pmDE, &e_pmDE ) ) {
    continue;
   }
   epoch= pmRA= e_pmRA= pmDE= e_pmDE= 0.0;
  }

  cos_delta= cos( catalog_dec * M_PI / 180.0 );

  ///////////////// Account for proper motion /////////////////
  catalog_ra_original= catalog_ra;
  catalog_dec_original= catalog_dec;
  //  assuming the epoch is a Julian Year https://en.wikipedia.org/wiki/Epoch_(astronomy)#Julian_years_and_J2000
  //  assuming observing_epoch_jd is the same for all stars!
  observing_epoch_jy= 2000.0 + ( stars[0].observing_epoch_jd - 2451545.0 ) / 365.25;
  dt= observing_epoch_jy - epoch;
  // https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=I/340
  // pmRA is UCAC/Gaia proper motion in RA*cosDE
  catalog_ra= catalog_ra + pmRA / ( 3600000 * cos_delta ) * dt;
  catalog_dec= catalog_dec + pmDE / 3600000 * dt;
  /////////////////////////////////////////////////////////////

  // Now find which input star that was
  for ( i= 0; i < N; i++ ) {
   if ( stars[i].matched_with_astrometric_catalog == 1 ) {
    continue;
   }
   if ( fabs( stars[i].dec_deg_measured - measured_dec ) < catalog_search_parameters->search_radius_deg ) {
    if ( fabs( stars[i].ra_deg_measured - measured_ra ) * cos_delta < catalog_search_parameters->search_radius_deg ) {
     if ( distance > catalog_search_parameters->search_radius_deg * 3600 ) {
      continue;
     }

     // if we are here - this is a match
     stars[i].matched_with_astrometric_catalog= 1;
     stars[i].d_ra= catalog_ra - measured_ra;
     stars[i].d_dec= catalog_dec - measured_dec;
     stars[i].catalog_ra= catalog_ra;
     stars[i].catalog_dec= catalog_dec;
     stars[i].catalog_mag= catalog_mag;
     // stars[i].catalog_mag_err=catalog_mag_err;
     stars[i].catalog_mag_err= 0.0;
     stars[i].catalog_ra_original= catalog_ra_original;
     stars[i].catalog_dec_original= catalog_dec_original;
     // strncpy(stars[i].ucac4id,ucac4id,32);stars[i].ucac4id[32-1]='\0';
     //
     stars[i].match_distance_astrometric_catalog_arcsec= distance;

     // reset photometric info
     stars[i].APASS_B= 0.0;
     stars[i].APASS_B_err= 0.0;
     stars[i].APASS_V= 0.0;
     stars[i].APASS_V_err= 0.0;
     stars[i].APASS_r= 0.0;
     stars[i].APASS_r_err= 0.0;
     stars[i].APASS_i= 0.0;
     stars[i].APASS_i_err= 0.0;
     stars[i].Rc_computed_from_APASS_ri= 0.0;
     stars[i].Rc_computed_from_APASS_ri_err= 0.0;
     stars[i].Rc_computed_from_APASS_ri_err= 0.0;
     stars[i].Ic_computed_from_APASS_ri= 0.0;
     stars[i].Ic_computed_from_APASS_ri_err= 0.0;
     stars[i].APASS_g= 0.0;
     stars[i].APASS_g_err= 0.0;
     //     }

     N_stars_matched_with_astrometric_catalog++;
     // fprintf(stderr,"DEBUG MATCHED: stars[i].x_pix= %8.3lf\n",stars[i].x_pix);
     break; // like if we assume there will be only one match within distance - why not?
    }
   }
  } // for(i=0;i<N;i++)
 }
 fclose( f );
 fprintf( stderr, "Matched %d stars with UCAC5 using vizquery.\n", N_stars_matched_with_astrometric_catalog );
 if ( N_stars_matched_with_astrometric_catalog < 5 ) {
  fprintf( stderr, "ERROR: too few stars matched!\n" );
  return 1;
 }
 return 0;
}

int read_PANSTARRS1_from_vizquery( struct detected_star *stars, int N, char *vizquery_output_filename, struct str_catalog_search_parameters *catalog_search_parameters ) {
 FILE *f;
 char string[1024];
 int i;
 double measured_ra, measured_dec, distance, catalog_ra, catalog_dec;
 double cos_delta;
 int N_stars_matched_with_photometric_catalog= 0;

 double PS1_g;
 double PS1_g_err;
 double PS1_r;
 double PS1_r_err;
 double PS1_i;
 double PS1_i_err;
 double PS1_gr;
 double PS1_gr_err;
 double B0, B1, E;

 double APASS_B;
 double APASS_B_err;
 double APASS_V;
 double APASS_V_err;
 double APASS_r;
 double APASS_r_err;
 double APASS_i;
 double APASS_i_err;
 double APASS_g;
 double APASS_g_err;

 f= fopen( vizquery_output_filename, "r" );
 while ( NULL != fgets( string, 1024, f ) ) {
  if ( string[0] == '#' )
   continue;
  if ( string[0] == '\n' )
   continue;
  if ( string[0] == '-' )
   continue;
  if ( string[0] == '_' )
   continue;
  if ( string[0] == ' ' )
   continue;
  if ( string[0] != ' ' && string[0] != '0' && string[0] != '1' && string[0] != '2' && string[0] != '3' && string[0] != '4' && string[0] != '5' && string[0] != '6' && string[0] != '7' && string[0] != '8' && string[0] != '9' )
   continue;

  PS1_g= PS1_g_err= PS1_r= PS1_r_err= PS1_i= PS1_i_err= 0.0;                                   // reset, just in case
  APASS_B= APASS_B_err= APASS_V= APASS_V_err= APASS_r= APASS_r_err= APASS_i= APASS_i_err= 0.0; // reset, just in case
  //                                         g  eg   r  er   i  ei
  if ( 11 > sscanf( string, "%lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf ", &measured_ra, &measured_dec, &distance, &catalog_ra, &catalog_dec, &PS1_g, &PS1_g_err, &PS1_r, &PS1_r_err, &PS1_i, &PS1_i_err ) )
   continue;
  // fprintf(stderr,"\n\n DEBUG \n#%s#%lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf\n",
  // string,
  // measured_ra,measured_dec,distance,catalog_ra,catalog_dec,   APASS_B, APASS_B_err, APASS_V, APASS_V_err, APASS_r, APASS_r_err, APASS_i, APASS_i_err
  //);

  // crude range check
  if ( 0.0 >= PS1_g )
   continue;
  if ( 0.0 >= PS1_g_err )
   continue;
  if ( 0.0 >= PS1_r )
   continue;
  if ( 0.0 >= PS1_r_err )
   continue;
  if ( 0.0 >= PS1_i )
   continue;
  if ( 0.0 >= PS1_i_err )
   continue;
  //
  // Convert PS1 to APASS following http://adsabs.harvard.edu/abs/2012ApJ...750...99T
  // y = A0 + A1 x + A2 x2 = B0 + B1 x
  PS1_gr= PS1_g - PS1_r;
  PS1_gr_err= sqrt( PS1_g_err * PS1_g_err + PS1_r_err * PS1_r_err );
  B0= 0.213;
  B1= 0.587;
  E= 0.034;
  APASS_B= PS1_g + B0 + B1 * PS1_gr;
  APASS_B_err= sqrt( PS1_g_err * PS1_g_err + B1 * PS1_gr_err * B1 * PS1_gr_err + E * E );
  B0= 0.006;
  B1= 0.474;
  E= 0.012;
  APASS_V= PS1_r + B0 + B1 * PS1_gr;
  APASS_V_err= sqrt( PS1_r_err * PS1_r_err + B1 * PS1_gr_err * B1 * PS1_gr_err + E * E );
  B0= -0.001;
  B1= 0.011;
  E= 0.004;
  APASS_r= PS1_r + B0 + B1 * PS1_gr;
  APASS_r_err= sqrt( PS1_r_err * PS1_r_err + B1 * PS1_gr_err * B1 * PS1_gr_err + E * E );
  B0= -0.004;
  B1= 0.020;
  E= 0.005;
  APASS_i= PS1_i + B0 + B1 * PS1_gr;
  APASS_i_err= sqrt( PS1_i_err * PS1_i_err + B1 * PS1_gr_err * B1 * PS1_gr_err + E * E );
  //
  APASS_g= PS1_g;
  APASS_g_err= PS1_g_err;
  //

  cos_delta= cos( measured_dec * M_PI / 180.0 );
  for ( i= 0; i < N; i++ ) {
   // Consider only stars matched earlier with the astrometric catalog
   if ( stars[i].matched_with_astrometric_catalog != 1 )
    continue;
   // Don not consider stars that were matched earlier
   if ( stars[i].matched_with_photometric_catalog == 1 )
    continue;
   if ( fabs( stars[i].dec_deg_measured - measured_dec ) < catalog_search_parameters->search_radius_deg )
    if ( fabs( stars[i].ra_deg_measured - measured_ra ) * cos_delta < catalog_search_parameters->search_radius_deg ) {
     if ( distance > catalog_search_parameters->search_radius_deg * 3600 )
      continue;
     stars[i].matched_with_photometric_catalog= 1;

     // if the star is matched with APASS
     if ( 0.0 != APASS_B && 0.0 != APASS_V && 0.0 != APASS_r && 0.0 != APASS_i ) {
      // If there is no error estimate, assume some typical value
      if ( 0.0 == APASS_B_err )
       APASS_B_err= 0.05;
      if ( 0.0 == APASS_V_err )
       APASS_V_err= 0.05;
      if ( 0.0 == APASS_r_err )
       APASS_r_err= 0.05;
      if ( 0.0 == APASS_i_err )
       APASS_i_err= 0.05;
      //
      stars[i].APASS_B= APASS_B;
      stars[i].APASS_B_err= APASS_B_err;
      stars[i].APASS_V= APASS_V;
      stars[i].APASS_V_err= APASS_V_err;
      stars[i].APASS_r= APASS_r;
      stars[i].APASS_r_err= APASS_r_err;
      stars[i].APASS_i= APASS_i;
      stars[i].APASS_i_err= APASS_i_err;
      stars[i].APASS_g= APASS_g;
      stars[i].APASS_g_err= APASS_g_err;

      // Jester et al. (2005) https://ui.adsabs.harvard.edu/abs/2005AJ....130..873J
      // All stars with Rc-Ic < 1.15
      // V-R    =    1.09*(r-i) + 0.22        0.03
      stars[i].Rc_computed_from_APASS_ri= APASS_V - 1.09 * ( APASS_r - APASS_i ) - 0.22;
      stars[i].Rc_computed_from_APASS_ri_err= sqrt( 1.09 * 1.09 * ( APASS_r_err * APASS_r_err + APASS_i_err * APASS_i_err ) + 0.03 * 0.03 );
      // Forgot the V error
      stars[i].Rc_computed_from_APASS_ri_err= sqrt( stars[i].Rc_computed_from_APASS_ri_err * stars[i].Rc_computed_from_APASS_ri_err + APASS_V_err * APASS_V_err );
      //////////////////////////////////////////////////
      stars[i].Ic_computed_from_APASS_ri= stars[i].Rc_computed_from_APASS_ri - 1.00 * ( APASS_r - APASS_i ) + 0.21;
      stars[i].Ic_computed_from_APASS_ri_err= stars[i].Rc_computed_from_APASS_ri_err;
      //////////////////////////////////////////////////
     } else {
      stars[i].APASS_B= 0.0;
      stars[i].APASS_B_err= 0.0;
      stars[i].APASS_V= 0.0;
      stars[i].APASS_V_err= 0.0;
      stars[i].APASS_r= 0.0;
      stars[i].APASS_r_err= 0.0;
      stars[i].APASS_i= 0.0;
      stars[i].APASS_i_err= 0.0;
      stars[i].Rc_computed_from_APASS_ri= 0.0;
      stars[i].Rc_computed_from_APASS_ri_err= 0.0;
      stars[i].Ic_computed_from_APASS_ri= 0.0;
      stars[i].Ic_computed_from_APASS_ri_err= 0.0;
      stars[i].APASS_g= 0.0;
      stars[i].APASS_g_err= 0.0;
     }

     N_stars_matched_with_photometric_catalog++;
     // fprintf(stderr,"DEBUG MATCHED: stars[i].x_pix= %8.3lf\n",stars[i].x_pix);
    }
   // if( fabs(stars[i].dec_deg_measured-measured_dec)<MAX_DEVIATION_AT_FIRST_STEP )
  } // for(i=0;i<N;i++)
 }
 fclose( f );
 fprintf( stderr, "Matched %d stars with Pan-STARRS1.\n", N_stars_matched_with_photometric_catalog );
 if ( N_stars_matched_with_photometric_catalog < 5 ) {
  fprintf( stderr, "ERROR: too few stars matched!\n" );
  return 1;
 }
 return 0;
}

int read_APASS_from_vizquery( struct detected_star *stars, int N, char *vizquery_output_filename, struct str_catalog_search_parameters *catalog_search_parameters ) {
 FILE *f;
 char string[1024];
 int i;
 double measured_ra, measured_dec, distance, catalog_ra, catalog_dec;
 double cos_delta;
 int N_stars_matched_with_photometric_catalog= 0;

 int N_catalog_lines_parsed= 0;
 int N_rejected_on_distance= 0;

 double APASS_B;
 double APASS_B_err;
 double APASS_V;
 double APASS_V_err;
 double APASS_r;
 double APASS_r_err;
 double APASS_i;
 double APASS_i_err;
 double APASS_g;
 double APASS_g_err;

 int found_end_marker= 0; // Variable to track if "#END#   " is present
                          // The presence of this marker will signify the VizieR output was not cut-off by a network error

 int found_vizier_error_marker= 0; // Set to 1 if VizieR internal error is found

 f= fopen( vizquery_output_filename, "r" );
 if ( NULL == f ) {
  return 1;
 }
 while ( NULL != fgets( string, 1024, f ) ) {

  // quickly check the first character of the input string
  if ( string[0] == '\n' )
   continue;
  if ( string[0] == '-' )
   continue;
  if ( string[0] == '_' )
   continue;
  if ( string[0] == ' ' )
   continue;

  // Check for "#END#   " at the start of the line
  if ( strncmp( string, "#END#   ", 8 ) == 0 ) {
   found_end_marker= 1;
   break; // we are already at the end of input
  }

  // Check for "#INFO QUERY_STATUS=ERROR" - a sign of VizieR internal error
  if ( strncmp( string, "#INFO QUERY_STATUS=ERROR", 24 ) == 0 ) {
   found_vizier_error_marker= 1;
   fprintf( stderr, "WARNING: found an error message in VizieR response!\n" );
   break; // VizieR problem
  }

  // sadly, the following can only be checked after searching for "#END#   "
  if ( string[0] == '#' )
   continue;
  if ( string[0] != ' ' && string[0] != '0' && string[0] != '1' && string[0] != '2' && string[0] != '3' && string[0] != '4' && string[0] != '5' && string[0] != '6' && string[0] != '7' && string[0] != '8' && string[0] != '9' )
   continue;

  // check if the string looks sufficiently long to contain useful data
  string[1024 - 1]= '\0'; // just in case
  if ( strlen( string ) < 123 ) {
   continue;
  }

  APASS_B= APASS_B_err= APASS_V= APASS_V_err= APASS_r= APASS_r_err= APASS_i= APASS_i_err= APASS_g= APASS_g_err= 0.0; // reset, just in case
  //                                            B  eB   V  eV   r  er   i  ei   g  eg
  if ( 15 > sscanf( string, "%lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf", &measured_ra, &measured_dec, &distance, &catalog_ra, &catalog_dec, &APASS_B, &APASS_B_err, &APASS_V, &APASS_V_err, &APASS_r, &APASS_r_err, &APASS_i, &APASS_i_err, &APASS_g, &APASS_g_err ) ) {
   continue;
  }
  N_catalog_lines_parsed++;

  cos_delta= cos( measured_dec * M_PI / 180.0 );
  for ( i= 0; i < N; i++ ) {
   // Consider only stars matched earlier with the astrometric catalog
   if ( stars[i].matched_with_astrometric_catalog != 1 )
    continue;
   // Don not consider stars that were matched earlier
   if ( stars[i].matched_with_photometric_catalog == 1 )
    continue;
   if ( fabs( stars[i].dec_deg_measured - measured_dec ) < catalog_search_parameters->search_radius_deg )
    if ( fabs( stars[i].ra_deg_measured - measured_ra ) * cos_delta < catalog_search_parameters->search_radius_deg ) {
     if ( distance > catalog_search_parameters->search_radius_deg * 3600 ) {
      N_rejected_on_distance++;
      continue;
     }
     stars[i].matched_with_photometric_catalog= 1;

     // if the star is matched with APASS
     if ( 0.0 != APASS_B && 0.0 != APASS_V && 0.0 != APASS_r && 0.0 != APASS_i ) {
      // If there is no error estimate, assume some typical value
      if ( 0.0 == APASS_B_err )
       APASS_B_err= 0.02;
      if ( 0.0 == APASS_V_err )
       APASS_V_err= 0.02;
      if ( 0.0 == APASS_r_err )
       APASS_r_err= 0.02;
      if ( 0.0 == APASS_i_err )
       APASS_i_err= 0.02;
      if ( 0.0 == APASS_g_err )
       APASS_g_err= 0.02;
      //
      stars[i].APASS_B= APASS_B;
      stars[i].APASS_B_err= APASS_B_err;
      stars[i].APASS_V= APASS_V;
      stars[i].APASS_V_err= APASS_V_err;
      stars[i].APASS_r= APASS_r;
      stars[i].APASS_r_err= APASS_r_err;
      stars[i].APASS_i= APASS_i;
      stars[i].APASS_i_err= APASS_i_err;
      stars[i].APASS_g= APASS_g;
      stars[i].APASS_g_err= APASS_g_err;

      // Jester et al. (2005)
      // All stars with Rc-Ic < 1.15
      // V-R    =    1.09*(r-i) + 0.22        0.03
      stars[i].Rc_computed_from_APASS_ri= APASS_V - 1.09 * ( APASS_r - APASS_i ) - 0.22;
      stars[i].Rc_computed_from_APASS_ri_err= sqrt( 1.09 * 1.09 * ( APASS_r_err * APASS_r_err + APASS_i_err * APASS_i_err ) + 0.03 * 0.03 );
      // Forgot the V error
      stars[i].Rc_computed_from_APASS_ri_err= sqrt( stars[i].Rc_computed_from_APASS_ri_err * stars[i].Rc_computed_from_APASS_ri_err + APASS_V_err * APASS_V_err );
      //////////////////////////////////////////////////
      stars[i].Ic_computed_from_APASS_ri= stars[i].Rc_computed_from_APASS_ri - 1.00 * ( APASS_r - APASS_i ) + 0.21;
      stars[i].Ic_computed_from_APASS_ri_err= stars[i].Rc_computed_from_APASS_ri_err; // above we assumed 1.09 ~ 1.00 to simplify error propagation, but what's the uncertainty of the relation?
      //////////////////////////////////////////////////
     } else {
      stars[i].APASS_B= 0.0;
      stars[i].APASS_B_err= 0.0;
      stars[i].APASS_V= 0.0;
      stars[i].APASS_V_err= 0.0;
      stars[i].APASS_r= 0.0;
      stars[i].APASS_r_err= 0.0;
      stars[i].APASS_i= 0.0;
      stars[i].APASS_i_err= 0.0;
      stars[i].Rc_computed_from_APASS_ri= 0.0;
      stars[i].Rc_computed_from_APASS_ri_err= 0.0;
      stars[i].Ic_computed_from_APASS_ri= 0.0;
      stars[i].Ic_computed_from_APASS_ri_err= 0.0;
      stars[i].APASS_g= 0.0;
      stars[i].APASS_g_err= 0.0;
     }

     N_stars_matched_with_photometric_catalog++;
     // fprintf(stderr,"DEBUG MATCHED: stars[i].x_pix= %8.3lf\n",stars[i].x_pix);
    }
   // if( fabs(stars[i].dec_deg_measured-measured_dec)<MAX_DEVIATION_AT_FIRST_STEP )
  } // for(i=0;i<N;i++)
 }
 fclose( f );
 if ( 0 != found_end_marker ) {
  fprintf( stderr, "#END# marker found - VizieR output is complete!\n" );
 } else {
  // We do not wait for the #END# marker if there was a VizieR error
  // If there is a VizieR error, do not confuse user with the 'no END maker' message
  if ( 0 == found_vizier_error_marker ) {
   fprintf( stderr, "#END# marker NOT found - VizieR output is truncated by network timeout!\n" );
  }
 }
 fprintf( stderr, "Parsed %d APASS catalog lines.\n", N_catalog_lines_parsed );
 fprintf( stderr, "%d stars rejected on distance.\n", N_rejected_on_distance );
 fprintf( stderr, "Matched %d stars with APASS.\n", N_stars_matched_with_photometric_catalog );
 // if( N_stars_matched_with_photometric_catalog < 5 ) {
 if ( N_stars_matched_with_photometric_catalog < 4 ) {
  // remove matched with photometric catalog marker from all stars
  for ( i= 0; i < N; i++ ) {
   stars[i].matched_with_photometric_catalog= 0;
  }
  // this way after APASS search failure and success of another phtoometric catalog search we hopefully wouldn't end up with a mixture of two photometric catalogs in the output
  //
  // Check for an internal VizieR error that will be maked by non-zero value of found_vizier_error_marker
  if ( 0 != found_vizier_error_marker ) {
   fprintf( stderr, "ERROR: VizieR internal error marker found!\n" );
   return 2; // return code 2 means 'do not retry'
  }
  // Check if VizieR interaction was a success or was there a network error (if we didn't get the #END# marker)
  if ( 0 != found_end_marker ) {
   fprintf( stderr, "ERROR: Too few stars matched and #END# marker found!\n" );
   return 2; // return code 2 means 'do not retry'
  } else {
   fprintf( stderr, "ERROR: Too few stars matched!\n" );
   return 1; // return code 1 means 'may retry'
  }
 }
 return 0; // return code 0 means everything is fine - match success
}

int search_UCAC5_localcopy( struct detected_star *stars, int N, struct str_catalog_search_parameters *catalog_search_parameters ) {

 double faintest_mag, brightest_mag;

 double observing_epoch_jy, dt;

 double measured_ra, measured_dec, catalog_ra, catalog_dec, catalog_mag;
 double distance;
 double catalog_ra_original, catalog_dec_original;
 double cos_delta;
 int N_stars_matched_with_astrometric_catalog= 0;

 int search_stars_counter;

 double epoch, pmRA, pmDE;
 // double e_pmRA, e_pmDE;

 double search_ra_min_deg, search_ra_max_deg; //, search_ra_maxmin_deg, search_ra_mean_deg;
 double search_dec_min_deg, search_dec_max_deg, search_dec_maxmin_deg, search_dec_mean_deg;
 int detected_star_counter;

 // based on https://stackoverflow.com/questions/17598572/read-and-write-to-binary-files-in-c
 // and http://cdsarc.u-strasbg.fr/ftp/I/340/readmeU5.txt
 unsigned int zone_counter;
 char zonefilename[24]; // should match the length of sprintf string below

 // double gaia_ra_deg, garia_dec_deg;
 double ucac_ra_deg, ucac_dec_deg;
 double ucac_mag;
 double ucac_epoch;

 double ucac_pm_ra_masy;  //, ucac_pm_ra_err_masy;
 double ucac_pm_dec_masy; //, ucac_pm_dec_err_masy;

 int64_t srcid;                                                                    // long
 int32_t ira, idc, rag, dcg;                                                       // int
 int16_t epi, pmir, pmid, pmer, pmed, phgm, im1, rmag, jmag, hmag, kmag, erg, edg; // short
 int8_t flg, nu1;                                                                  // char

 // unsigned char buffer[52];
 FILE *ptr;

 // Check if a local copy of UCAC5 is found
 sprintf( zonefilename, "lib/catalogs/ucac5/z%03d", 1 );
 ptr= fopen( zonefilename, "rb" ); // r for read, b for binary
 if ( NULL == ptr ) {
  fprintf( stderr, "No local copy of UCAC5 is found\n" );
  return 1;
 } else {
  fprintf( stderr, "Found a local copy of UCAC5\n" );
 }
 fclose( ptr );

 // set zone search parameters
 search_ra_min_deg= 360.0;
 search_ra_max_deg= 0.0;
 search_dec_min_deg= 90.0;
 search_dec_max_deg= -90.0;
 for ( detected_star_counter= 0; detected_star_counter < N; detected_star_counter++ ) {
  if ( stars[detected_star_counter].ra_deg_measured < search_ra_min_deg )
   search_ra_min_deg= stars[detected_star_counter].ra_deg_measured;
  if ( stars[detected_star_counter].ra_deg_measured > search_ra_max_deg )
   search_ra_max_deg= stars[detected_star_counter].ra_deg_measured;
  if ( stars[detected_star_counter].dec_deg_measured < search_dec_min_deg )
   search_dec_min_deg= stars[detected_star_counter].dec_deg_measured;
  if ( stars[detected_star_counter].dec_deg_measured > search_dec_max_deg )
   search_dec_max_deg= stars[detected_star_counter].dec_deg_measured;
 }
 // search_ra_maxmin_deg=search_ra_max_deg-search_ra_min_deg;
 // search_ra_mean_deg=(search_ra_max_deg+search_ra_min_deg)/2.0;
 search_dec_maxmin_deg= search_dec_max_deg - search_dec_min_deg;
 search_dec_mean_deg= ( search_dec_max_deg + search_dec_min_deg ) / 2.0;
 //
 faintest_mag= catalog_search_parameters->faintest_mag;
 brightest_mag= catalog_search_parameters->brightest_mag;

 fprintf( stderr, "Reading UCAC5 zone files...\n" );

 // Read each zone file
 for ( zone_counter= 1; zone_counter < 900 + 1; zone_counter++ ) {
  // for( zone_counter=1; zone_counter<2; zone_counter++ ) {

  sprintf( zonefilename, "lib/catalogs/ucac5/z%03d", zone_counter );

  // fprintf(stderr,"%s\n",zonefilename);

  ptr= fopen( zonefilename, "rb" ); // r for read, b for binary
  if ( NULL == ptr ) {
   fprintf( stderr, "ERROR opening zone file %s\n", zonefilename );
   // assume this is just one missing file, but do we want crash on it?
   continue;
  }

  // fprintf(stderr,"DEBUG: reading %s\n",zonefilename);

  // Read all stars in the zone file
  while ( 1 == 1 ) {
   if ( 0 == fread( &srcid, sizeof( srcid ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &rag, sizeof( rag ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &dcg, sizeof( dcg ), 1, ptr ) ) {
    break;
   }
   //
   // gaia_ra_deg=(double)rag/3600000.0;
   // garia_dec_deg=(double)dcg/3600000.0;
   //
   if ( 0 == fread( &erg, sizeof( erg ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &edg, sizeof( edg ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &flg, sizeof( flg ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &nu1, sizeof( nu1 ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &epi, sizeof( epi ), 1, ptr ) ) {
    break;
   }
   //
   ucac_epoch= (double)epi / 1000.0 + 1997.0;
   epoch= ucac_epoch;
   //
   if ( 0 == fread( &ira, sizeof( ira ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &idc, sizeof( idc ), 1, ptr ) ) {
    break;
   }
   //
   ucac_ra_deg= (double)ira / 3600000.0;
   ucac_dec_deg= (double)idc / 3600000.0;
   //
   if ( fabs( search_dec_mean_deg - ucac_dec_deg ) > search_dec_maxmin_deg / 2.0 + 0.2 ) {
    break;
   }
   //
   if ( 0 == fread( &pmir, sizeof( pmir ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &pmid, sizeof( pmid ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &pmer, sizeof( pmer ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &pmed, sizeof( pmed ), 1, ptr ) ) {
    break;
   }
   //
   ucac_pm_ra_masy= 0.1 * (double)pmir;
   // ucac_pm_ra_err_masy=0.1*(double)pmer;
   ucac_pm_dec_masy= 0.1 * (double)pmid;
   // ucac_pm_dec_err_masy=0.1*(double)pmed;

   //
   if ( 0 == fread( &phgm, sizeof( phgm ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &im1, sizeof( im1 ), 1, ptr ) ) {
    break;
   }
   //
   ucac_mag= (double)im1 / 1000.0;
   //
   if ( 0 == fread( &rmag, sizeof( rmag ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &jmag, sizeof( jmag ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &hmag, sizeof( hmag ), 1, ptr ) ) {
    break;
   }
   if ( 0 == fread( &kmag, sizeof( kmag ), 1, ptr ) ) {
    break;
   }

   // Check the search parameters
   if ( ucac_mag > faintest_mag ) {
    continue;
   } // continue to the next star
   if ( ucac_mag < brightest_mag ) {
    continue;
   } // continue to the next star
   //
   if ( ucac_ra_deg < search_ra_min_deg ) {
    continue;
   }
   if ( ucac_ra_deg > search_ra_max_deg ) {
    continue;
   }
   if ( ucac_dec_deg < search_dec_min_deg ) {
    continue;
   }
   if ( ucac_dec_deg > search_dec_max_deg ) {
    continue;
   }
   //
   // Go through all the detected stars and search for a match
   search_stars_counter= 0;
   for ( detected_star_counter= 0; detected_star_counter < N; detected_star_counter++ ) {
    //
    if ( stars[detected_star_counter].good_star != 1 ) {
     continue;
    }
    if ( search_stars_counter == MAX_STARS_IN_LOCAL_CAT_QUERY ) {
     break;
    }
    search_stars_counter++;
    //
    measured_ra= stars[detected_star_counter].ra_deg_measured;
    measured_dec= stars[detected_star_counter].dec_deg_measured;
    distance= compute_distance_on_sphere( ucac_ra_deg, ucac_dec_deg, measured_ra, measured_dec );
    if ( distance < catalog_search_parameters->search_radius_deg ) {
     if ( ( ucac_mag < stars[detected_star_counter].catalog_mag && stars[detected_star_counter].matched_with_astrometric_catalog == 1 ) || stars[detected_star_counter].matched_with_astrometric_catalog == 0 ) {
      //
      // fprintf(stderr,"DEBUG: we've got a match!\n");
      //
      if ( stars[detected_star_counter].matched_with_astrometric_catalog == 0 ) {
       N_stars_matched_with_astrometric_catalog++;
      }
      //
      catalog_ra= ucac_ra_deg;
      catalog_dec= ucac_dec_deg;
      pmRA= ucac_pm_ra_masy;
      pmDE= ucac_pm_dec_masy;
      catalog_mag= ucac_mag;
      ///////////////// Account for proper motion /////////////////
      cos_delta= cos( catalog_dec * M_PI / 180.0 );
      catalog_ra_original= catalog_ra;
      catalog_dec_original= catalog_dec;
      observing_epoch_jy= 2000.0 + ( stars[0].observing_epoch_jd - 2451545.0 ) / 365.25;
      dt= observing_epoch_jy - epoch;
      catalog_ra= catalog_ra + pmRA / ( 3600000 * cos_delta ) * dt;
      // catalog_ra= catalog_ra + pmRA / 3600000 * cos_delta * dt;
      catalog_dec= catalog_dec + pmDE / 3600000 * dt;
      //
      stars[detected_star_counter].matched_with_astrometric_catalog= 1;
      stars[detected_star_counter].d_ra= catalog_ra - measured_ra;
      stars[detected_star_counter].d_dec= catalog_dec - measured_dec;
      stars[detected_star_counter].catalog_ra= catalog_ra;
      stars[detected_star_counter].catalog_dec= catalog_dec;
      stars[detected_star_counter].catalog_mag= catalog_mag;
      stars[detected_star_counter].catalog_mag_err= 0.0;
      stars[detected_star_counter].catalog_ra_original= catalog_ra_original;
      stars[detected_star_counter].catalog_dec_original= catalog_dec_original;
      //
      stars[detected_star_counter].match_distance_astrometric_catalog_arcsec= distance;
      // reset photometric info
      stars[detected_star_counter].APASS_B= 0.0;
      stars[detected_star_counter].APASS_B_err= 0.0;
      stars[detected_star_counter].APASS_V= 0.0;
      stars[detected_star_counter].APASS_V_err= 0.0;
      stars[detected_star_counter].APASS_r= 0.0;
      stars[detected_star_counter].APASS_r_err= 0.0;
      stars[detected_star_counter].APASS_i= 0.0;
      stars[detected_star_counter].APASS_i_err= 0.0;
      stars[detected_star_counter].Rc_computed_from_APASS_ri= 0.0;
      stars[detected_star_counter].Rc_computed_from_APASS_ri_err= 0.0;
      stars[detected_star_counter].Rc_computed_from_APASS_ri_err= 0.0;
      stars[detected_star_counter].Ic_computed_from_APASS_ri= 0.0;
      stars[detected_star_counter].Ic_computed_from_APASS_ri_err= 0.0;
      //
      break; // assume we have only one match
      //
     }
    }
   }
   //

   // fprintf(stderr, "%li  %.7lf %.7lf  %.3lf %.3lf  %.1lf %.1lf %.1lf %.1lf\n", srcid, ucac_ra_deg, ucac_dec_deg, ucac_epoch, ucac_mag,  ucac_pm_ra_masy, ucac_pm_ra_err_masy, ucac_pm_dec_masy, ucac_pm_dec_err_masy );
  } // while( 1 == 1 ) { // Read all stars in the zone file

  fclose( ptr );
 } // for( zone_counter==0; zone_counter<900; zone_counter++ ) { // Read each zone file

 fprintf( stderr, "Done reading UCAC5 zone files...\n" );

 fprintf( stderr, "Matched %d stars with the local copy of UCAC5.\n", N_stars_matched_with_astrometric_catalog );
 if ( N_stars_matched_with_astrometric_catalog < 5 ) {
  fprintf( stderr, "ERROR: too few stars matched!\n" );
  return 1;
 }

 return 0;
}

/**
 * Checks and sanitizes the VAST_CURL_PROXY environment variable.
 * Returns sanitized proxy string if valid, or NULL if invalid or not set.
 * The caller must free the returned string.
 */
char *get_sanitized_curl_proxy() {
 size_t i;

 const char *proxy_env= getenv( "VAST_CURL_PROXY" );

 // If not set, return NULL
 if ( proxy_env == NULL || strlen( proxy_env ) == 0 ) {
  return NULL;
 }

 // Check for reasonable length (arbitrary limit of 512 chars)
 size_t len= strlen( proxy_env );
 if ( len > 512 ) {
  fprintf( stderr, "WARNING: VAST_CURL_PROXY environment variable is too long (max 512 chars)\n" );
  return NULL;
 }

 // Copy the string so we can safely work with it
 char *proxy_str= strdup( proxy_env );
 if ( proxy_str == NULL ) {
  fprintf( stderr, "ERROR: Memory allocation failed for proxy string\n" );
  return NULL;
 }

 // STRICT VALIDATION: Check for shell command separators and dangerous characters
 const char *dangerous_chars[]= {
     ";", "&&", "||", "|", ">", "<", "`", "$", "(", ")", "{", "}",
     "\\", "\n", "\r", "\t", "\"", "'", "*", "?", "[", "]", "~", "#" };

 for ( i= 0; i < sizeof( dangerous_chars ) / sizeof( dangerous_chars[0] ); i++ ) {
  if ( strstr( proxy_str, dangerous_chars[i] ) != NULL ) {
   fprintf( stderr, "WARNING: VAST_CURL_PROXY contains forbidden character sequence: %s\n", dangerous_chars[i] );
   free( proxy_str );
   return NULL;
  }
 }

 // Validate that all space-separated tokens are allowed curl proxy options
 const char *allowed_options[]= {
     "--proxy", "--proxy-user", "--proxy-pass", "--proxy-insecure",
     "--proxy-header", "--proxy-basic", "--proxy-digest", "--proxy-negotiate",
     "--proxy-ntlm", "--proxy-anyauth", "--proxy-cacert", "--proxy-capath",
     "--proxy-cert", "--proxy-cert-type", "--proxy-ciphers", "--proxy-crlfile",
     "--proxy-key", "--proxy-key-type", "--proxy-pinnedpubkey",
     "--proxy-service-name", "--proxy-ssl-allow-beast", "--proxy-tls13-ciphers",
     "--proxy-tlsuser", "--proxy-tlspassword", "--proxy-tlsauthtype",
     "-L", "--location", NULL };

 // Parse and validate each token
 char *proxy_copy= strdup( proxy_str );
 if ( proxy_copy == NULL ) {
  fprintf( stderr, "ERROR: Memory allocation failed\n" );
  free( proxy_str );
  return NULL;
 }

 char *token= strtok( proxy_copy, " " );
 int has_valid_proxy_option= 0;

 while ( token != NULL ) {
  // Check if this token is a curl option (starts with -)
  if ( token[0] == '-' ) {
   int is_allowed= 0;
   for ( i= 0; allowed_options[i] != NULL; i++ ) {
    if ( strcmp( token, allowed_options[i] ) == 0 ) {
     is_allowed= 1;
     if ( strstr( token, "proxy" ) != NULL ) {
      has_valid_proxy_option= 1;
     }
     break;
    }
   }

   if ( !is_allowed ) {
    fprintf( stderr, "WARNING: VAST_CURL_PROXY contains disallowed option: %s\n", token );
    free( proxy_copy );
    free( proxy_str );
    return NULL;
   }
  } else {
   // This is a value/argument, not an option - validate it's reasonable
   if ( strlen( token ) > 255 ) {
    fprintf( stderr, "WARNING: VAST_CURL_PROXY contains overly long argument: %s\n", token );
    free( proxy_copy );
    free( proxy_str );
    return NULL;
   }
  }

  token= strtok( NULL, " " );
 }

 free( proxy_copy );

 if ( !has_valid_proxy_option ) {
  fprintf( stderr, "WARNING: VAST_CURL_PROXY must contain at least one proxy-related option\n" );
  free( proxy_str );
  return NULL;
 }

 // Additional validation: if it contains --proxy, validate the URL format
 char *proxy_option= strstr( proxy_str, "--proxy " );
 if ( proxy_option != NULL ) {
  char *url_start= proxy_option + 8; // Skip "--proxy "
  char *url_end= strchr( url_start, ' ' );

  // Extract just the URL part
  char url_buf[256];
  size_t url_len;
  if ( url_end != NULL ) {
   url_len= url_end - url_start;
  } else {
   url_len= strlen( url_start );
  }

  if ( url_len >= sizeof( url_buf ) ) {
   fprintf( stderr, "WARNING: Proxy URL too long\n" );
   free( proxy_str );
   return NULL;
  }

  strncpy( url_buf, url_start, url_len );
  url_buf[url_len]= '\0';

  // Validate URL format
  if ( !( strncmp( url_buf, "http://", 7 ) == 0 ||
          strncmp( url_buf, "https://", 8 ) == 0 ||
          strncmp( url_buf, "socks4://", 9 ) == 0 ||
          strncmp( url_buf, "socks5://", 9 ) == 0 ) ) {
   fprintf( stderr, "WARNING: Invalid proxy URL format. Must start with http://, https://, socks4://, or socks5://\n" );
   free( proxy_str );
   return NULL;
  }
 }

 // Additional validation: if it contains --proxy-user, validate the format
 char *user_option= strstr( proxy_str, "--proxy-user " );
 if ( user_option != NULL ) {
  char *user_start= user_option + 13; // Skip "--proxy-user "
  char *user_end= strchr( user_start, ' ' );

  // Extract just the user:pass part
  char user_buf[256];
  size_t user_len;
  if ( user_end != NULL ) {
   user_len= user_end - user_start;
  } else {
   user_len= strlen( user_start );
  }

  if ( user_len >= sizeof( user_buf ) || user_len < 3 ) {
   fprintf( stderr, "WARNING: Invalid proxy user credentials format\n" );
   free( proxy_str );
   return NULL;
  }

  strncpy( user_buf, user_start, user_len );
  user_buf[user_len]= '\0';

  // Must contain a colon for user:pass format
  if ( strchr( user_buf, ':' ) == NULL ) {
   fprintf( stderr, "WARNING: Proxy user credentials must be in user:password format\n" );
   free( proxy_str );
   return NULL;
  }
 }

 // Final safety check: ensure only alphanumeric, dash, dot, colon, slash, and space characters
 for ( i= 0; i < strlen( proxy_str ); i++ ) {
  char c= proxy_str[i];
  if ( !( isalnum( c ) || c == '-' || c == '.' || c == ':' || c == '/' || c == ' ' || c == '_' ) ) {
   fprintf( stderr, "WARNING: VAST_CURL_PROXY contains invalid character: %c\n", c );
   free( proxy_str );
   return NULL;
  }
 }

 fprintf( stderr, "solve_plate_with_UCAC5 is using curl proxy settings from VAST_CURL_PROXY\n" );
 return proxy_str;
}

/**
 * Parses a shell-style argument string into tokens, handling single and double quotes.
 * Adds parsed tokens to the provided argv array, updating argc and reallocating if needed.
 *
 * input_str: The string to parse (can be NULL or empty)
 * argv: Pointer to the argument array (will be reallocated if needed)
 * argc: Pointer to current argument count (will be updated)
 * capacity: Pointer to current array capacity (will be updated if reallocated)
 *
 * Returns 0 on success, -1 on memory allocation failure.
 */
static int parse_shell_args( const char *input_str, char ***argv, int *argc, int *capacity ) {
 if ( input_str == NULL || strlen( input_str ) == 0 ) {
  return 0; // Nothing to parse
 }

 char *str_copy= strdup( input_str );
 if ( str_copy == NULL ) {
  return -1;
 }

 char *p= str_copy;
 char quote_char;
 char token_buf[1024];
 int token_len;

 while ( *p != '\0' ) {
  // Skip leading whitespace
  while ( *p != '\0' && isspace( (unsigned char)*p ) ) {
   p++;
  }
  if ( *p == '\0' ) {
   break;
  }

  token_len= 0;
  token_buf[0]= '\0';

  // Parse one token (may consist of multiple quoted/unquoted segments)
  while ( *p != '\0' && !isspace( (unsigned char)*p ) ) {
   if ( *p == '\'' || *p == '"' ) {
    // Quoted segment
    quote_char= *p;
    p++; // Skip opening quote
    while ( *p != '\0' && *p != quote_char ) {
     if ( token_len < (int)sizeof( token_buf ) - 1 ) {
      token_buf[token_len++]= *p;
     }
     p++;
    }
    if ( *p == quote_char ) {
     p++; // Skip closing quote
    }
   } else {
    // Unquoted segment
    if ( token_len < (int)sizeof( token_buf ) - 1 ) {
     token_buf[token_len++]= *p;
    }
    p++;
   }
  }
  token_buf[token_len]= '\0';

  // Add token to argv if non-empty
  if ( token_len > 0 ) {
   // Check if we need to grow the array
   if ( *argc >= *capacity - 1 ) { // -1 to leave room for NULL terminator
    int new_capacity= *capacity * 2;
    char **new_argv= realloc( *argv, new_capacity * sizeof( char * ) );
    if ( new_argv == NULL ) {
     free( str_copy );
     return -1;
    }
    *argv= new_argv;
    *capacity= new_capacity;
   }

   ( *argv )[*argc]= strdup( token_buf );
   if ( ( *argv )[*argc] == NULL ) {
    free( str_copy );
    return -1;
   }
   ( *argc )++;
  }
 }

 free( str_copy );
 return 0;
}

/**
 * Frees an argv-style array of strings.
 */
static void free_argv( char **argv, int argc ) {
 int i;
 if ( argv == NULL ) {
  return;
 }
 for ( i= 0; i < argc; i++ ) {
  free( argv[i] );
 }
 free( argv );
}

/**
 * Executes curl directly without shell interpretation using fork() + execvp().
 * This avoids command injection vulnerabilities by passing arguments as an array.
 *
 * base_command: The curl arguments (without "curl" prefix)
 * proxy_settings: Optional proxy settings string (can be NULL)
 * print_command: If non-zero, print the command to stderr (with obscured credentials)
 *
 * Returns the exit status of curl, or -1 on error.
 */
static int execute_curl_direct( const char *base_command, const char *proxy_settings, int print_command ) {
 char **argv= NULL;
 int argc= 0;
 int capacity= 64;
 int status;
 pid_t pid;
 int i;

 // Allocate initial argv array
 argv= malloc( capacity * sizeof( char * ) );
 if ( argv == NULL ) {
  fprintf( stderr, "ERROR: Memory allocation failed for argv\n" );
  return -1;
 }

 // First argument is the program name
 argv[argc]= strdup( "curl" );
 if ( argv[argc] == NULL ) {
  free( argv );
  fprintf( stderr, "ERROR: Memory allocation failed for curl argument\n" );
  return -1;
 }
 argc++;

 // Parse proxy settings if provided
 if ( proxy_settings != NULL && strlen( proxy_settings ) > 0 ) {
  if ( parse_shell_args( proxy_settings, &argv, &argc, &capacity ) != 0 ) {
   free_argv( argv, argc );
   fprintf( stderr, "ERROR: Failed to parse proxy settings\n" );
   return -1;
  }
 }

 // Parse base command
 if ( parse_shell_args( base_command, &argv, &argc, &capacity ) != 0 ) {
  free_argv( argv, argc );
  fprintf( stderr, "ERROR: Failed to parse base command\n" );
  return -1;
 }

 // NULL-terminate the array
 argv[argc]= NULL;

 // Print command if requested (for debugging)
 if ( print_command ) {
  fprintf( stderr, "Executing:" );
  for ( i= 0; i < argc; i++ ) {
   // Obscure proxy credentials in output
   if ( i > 0 && strcmp( argv[i - 1], "--proxy-user" ) == 0 ) {
    fprintf( stderr, " user:password" );
   } else {
    fprintf( stderr, " %s", argv[i] );
   }
  }
  fprintf( stderr, "\n" );
 }

 // Fork and execute
 pid= fork();
 if ( pid == -1 ) {
  fprintf( stderr, "ERROR: fork() failed\n" );
  free_argv( argv, argc );
  return -1;
 }

 if ( pid == 0 ) {
  // Child process: execute curl
  execvp( "curl", argv );
  // If execvp returns, it failed
  _exit( 127 );
 }

 // Parent process: wait for child
 if ( waitpid( pid, &status, 0 ) == -1 ) {
  fprintf( stderr, "ERROR: waitpid() failed\n" );
  free_argv( argv, argc );
  return -1;
 }

 free_argv( argv, argc );

 if ( WIFEXITED( status ) ) {
  return WEXITSTATUS( status );
 } else {
  return -1; // Child terminated abnormally
 }
}

/**
 * Safely constructs a curl command with proxy settings if available.
 * Returns a dynamically allocated string that must be freed by the caller.
 * NOTE: This function is kept for backward compatibility and logging purposes.
 */
char *construct_safe_curl_command( const char *base_command, const char *proxy_settings ) {
 // Allocate memory for the full command
 // Size estimation: base command + proxy settings (if any) + null terminator
 size_t command_size= strlen( base_command ) + ( proxy_settings ? strlen( proxy_settings ) + 1 : 0 ) + 7; // "curl" + space + space + null terminator
 char *safe_command= malloc( command_size );

 if ( safe_command == NULL ) {
  fprintf( stderr, "ERROR: Memory allocation failed for curl command\n" );
  return NULL;
 }

 // Initialize the allocated memory to null characters
 memset( safe_command, '\0', command_size );

 // Construct command with proxy settings if available
 if ( proxy_settings != NULL ) {
  snprintf( safe_command, command_size, "curl %s %s", proxy_settings, base_command );
 } else {
  snprintf( safe_command, command_size, "curl %s", base_command );
 }
 safe_command[command_size - 1]= '\0'; // just in case snprintf() messed up the last byte

 return safe_command;
}

/**
 * Obscures proxy login credentials in a string.
 * Searches for a pattern "--proxy-user xxxx:yyyy " where xxxx:yyyy is the credential part,
 * and replaces it with "user:password" padded with spaces to the original length.
 *
 * str: The input string to process (will be modified in-place)
 *
 * Returns 1 if replacement was made, 0 if pattern not found
 */
int obscure_proxy_credentials( char *str ) {
 if ( str == NULL ) {
  return 0;
 }

 const char *prefix= "--proxy-user ";
 size_t prefix_len= strlen( prefix );

 /* Find prefix in string */
 char *start= strstr( str, prefix );
 if ( start == NULL ) {
  return 0;
 }

 /* Skip to the beginning of credentials */
 start+= prefix_len;

 /* Find the end of credentials (space or end of string) */
 char *end= start;
 while ( *end != '\0' && *end != ' ' ) {
  end++;
 }

 /* Get original credential length */
 size_t cred_len= end - start;
 if ( cred_len == 0 ) {
  return 0; /* No credentials found after prefix */
 }

 /* Create replacement with "user:password" */
 const char *replacement= "user:password";
 size_t replace_len= strlen( replacement );

 /* Replace credentials with replacement */
 size_t i;
 for ( i= 0; i < replace_len && i < cred_len; i++ ) {
  start[i]= replacement[i];
 }

 /* Pad the remaining space with spaces */
 for ( ; i < cred_len; i++ ) {
  start[i]= ' ';
 }

 return 1;
}

/**
 * Modified search_UCAC5_at_scan function that uses safer command construction.
 */
int search_UCAC5_at_scan( struct detected_star *stars, int N, struct str_catalog_search_parameters *catalog_search_parameters ) {
 double epoch, pmRA, e_pmRA, pmDE, e_pmDE, dt, observing_epoch_jy, catalog_ra_original, catalog_dec_original;
 int N_stars_matched_with_astrometric_catalog= 0;
 double measured_ra, measured_dec, distance, catalog_ra, catalog_dec, catalog_mag;
 double cos_delta;
 char string[1024];
 // char base_command[1024 + 3 * VAST_PATH_MAX + 2 * FILENAME_LENGTH];
 char base_command[BASE_COMMAND_LENGTH];
 FILE *vizquery_input;
 FILE *f;
 int i;
 int pid= getpid();
 char vizquery_input_filename[FILENAME_LENGTH];
 char vizquery_output_filename[FILENAME_LENGTH];
 int vizquery_run_success;
 int search_stars_counter;
 int zero_radec_counter;

 char path_to_vast_string[VAST_PATH_MAX];
 get_path_to_vast( path_to_vast_string );

 // try disabling scan UCAC5 access - this should trigger VizieR UCAC5 access
 // return 1;

#ifdef DEBUGFILES
 FILE *scan_ucac5_debug_ds9_region;
 scan_ucac5_debug_ds9_region= fopen( "scan_ucac5_input_debug_ds9.reg", "w" );
 fprintf( scan_ucac5_debug_ds9_region, "# Region file format: DS9 version 4.0\n" );
 fprintf( scan_ucac5_debug_ds9_region, "# Filename:\n" );
 fprintf( scan_ucac5_debug_ds9_region, "global color=green font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source\n" );
 fprintf( scan_ucac5_debug_ds9_region, "fk5\n" );
#endif

 // Initialize the allocated memory to null characters
 memset( vizquery_input_filename, '\0', FILENAME_LENGTH );
 memset( vizquery_output_filename, '\0', FILENAME_LENGTH );
 snprintf( vizquery_input_filename, FILENAME_LENGTH - 1, "scan_ucac5_%d.input", pid );
 snprintf( vizquery_output_filename, FILENAME_LENGTH - 1, "scan_ucac5_%d.output", pid );
 vizquery_input= fopen( vizquery_input_filename, "w" );
 if ( NULL == vizquery_input ) {
  fprintf( stderr, "ERROR in search_UCAC5_at_scan(): cannot open file %s for writing!\n", vizquery_input_filename );
  return 1;
 }
 search_stars_counter= 0;
 zero_radec_counter= 0;
 for ( i= 0; i < N; i++ ) {
  if ( stars[i].good_star == 1 ) {
   // check for a specific problem
   if ( stars[i].ra_deg_measured == 0.0 && stars[i].dec_deg_measured == 0.0 ) {
    zero_radec_counter++;
    if ( zero_radec_counter > 10 ) {
     fprintf( stderr, "ERROR in search_UCAC5_at_scan(): too many input positions are '0.000000 0.000000'\nWe cannot go to VizieR with that!\n" );
     exit( EXIT_FAILURE ); // terminate everything
    }
   }
   //
   fprintf( vizquery_input, "%lf %lf\n", stars[i].ra_deg_measured, stars[i].dec_deg_measured );
#ifdef DEBUGFILES
   fprintf( scan_ucac5_debug_ds9_region, "circle(%f,%f,%lf)\n", stars[i].ra_deg_measured, stars[i].dec_deg_measured, 5.0 * 21 / 3600 );
#endif
   search_stars_counter++;
   if ( search_stars_counter == MAX_STARS_IN_VIZQUERY ) {
    break;
   }
  }
 }
 fclose( vizquery_input );

#ifdef DEBUGFILES
 fclose( scan_ucac5_debug_ds9_region );
#endif

 if ( search_stars_counter < MIN_NUMBER_OF_STARS_ON_FRAME ) {
  fprintf( stderr, "ERROR in search_UCAC5_at_scan(): only %d stars are in the vizquery input list - that's too few!\n", search_stars_counter );
  return 1;
 }

 // Print search stat
 fprintf( stderr, "Searchig scan/vast for %d good reference stars...\n", search_stars_counter );

 // Get proxy settings if available
 char *proxy_settings= get_sanitized_curl_proxy();

 // Astrometric catalog search
 fprintf( stderr, "Searchig UCAC5...\n" );
 // Randomly choose between the three servers
 // Seed the random number generator
 srand( time( NULL ) );
 // Generate a random number (0, 1, or 2)
 int randChoice= rand() % 3;

 // Construct base command
 // Initialize the allocated memory to null characters
 memset( base_command, '\0', BASE_COMMAND_LENGTH );
 if ( randChoice == 0 ) {
  snprintf( base_command, BASE_COMMAND_LENGTH, "--silent --show-error --insecure --connect-timeout 10 --retry 1 --max-time 600 -F file=@%s -F submit=\"Upload Image\" -F brightmag=%lf -F faintmag=%lf -F searcharcsec=%lf --output %s 'http://scan.sai.msu.ru/cgi-bin/ucac5/search_ucac5.py'",
            vizquery_input_filename, catalog_search_parameters->brightest_mag,
            catalog_search_parameters->faintest_mag,
            catalog_search_parameters->search_radius_deg * 3600,
            vizquery_output_filename );
 } else if ( randChoice == 1 ) {
  snprintf( base_command, BASE_COMMAND_LENGTH, "--silent --show-error --insecure --connect-timeout 10 --retry 1 --max-time 600 -F file=@%s -F submit=\"Upload Image\" -F brightmag=%lf -F faintmag=%lf -F searcharcsec=%lf --output %s 'http://vast.sai.msu.ru/cgi-bin/ucac5/search_ucac5.py'",
            vizquery_input_filename, catalog_search_parameters->brightest_mag,
            catalog_search_parameters->faintest_mag,
            catalog_search_parameters->search_radius_deg * 3600,
            vizquery_output_filename );
 } else {
  snprintf( base_command, BASE_COMMAND_LENGTH, "--silent --show-error --insecure --connect-timeout 10 --retry 1 --max-time 600 -F file=@%s -F submit=\"Upload Image\" -F brightmag=%lf -F faintmag=%lf -F searcharcsec=%lf --output %s 'http://tau.kirx.net/cgi-bin/ucac5/search_ucac5.py'",
            vizquery_input_filename, catalog_search_parameters->brightest_mag,
            catalog_search_parameters->faintest_mag,
            catalog_search_parameters->search_radius_deg * 3600,
            vizquery_output_filename );
 }
 base_command[BASE_COMMAND_LENGTH - 1]= '\0'; // just in case snprintf() messed up the last byte

 // Execute curl directly without shell interpretation (avoids command injection)
 fprintf( stderr, "Running curl...\n" );
 vizquery_run_success= execute_curl_direct( base_command, proxy_settings, 1 );

 if ( vizquery_run_success != 0 || count_lines_in_ASCII_file( vizquery_output_filename ) < 5 ) {
  fprintf( stderr, "First attempt failed, trying alternative command\n" );

  // Note the reverse order with respect to randChoice
  if ( randChoice == 0 ) {
   // This block will execute if the first executed command was the first option and it failed
   sprintf( base_command, "--silent --show-error --insecure --connect-timeout 10 --retry 2 --max-time 600 -F file=@%s -F submit=\"Upload Image\" -F brightmag=%lf -F faintmag=%lf -F searcharcsec=%lf --output %s 'http://vast.sai.msu.ru/cgi-bin/ucac5/search_ucac5.py'",
            vizquery_input_filename, catalog_search_parameters->brightest_mag,
            catalog_search_parameters->faintest_mag,
            catalog_search_parameters->search_radius_deg * 3600,
            vizquery_output_filename );
  } else if ( randChoice == 1 ) {
   // This block will execute if the first executed command was the second option and it failed
   sprintf( base_command, "--silent --show-error --insecure --connect-timeout 10 --retry 2 --max-time 600 -F file=@%s -F submit=\"Upload Image\" -F brightmag=%lf -F faintmag=%lf -F searcharcsec=%lf --output %s 'http://tau.kirx.net/cgi-bin/ucac5/search_ucac5.py'",
            vizquery_input_filename, catalog_search_parameters->brightest_mag,
            catalog_search_parameters->faintest_mag,
            catalog_search_parameters->search_radius_deg * 3600,
            vizquery_output_filename );
  } else {
   // This block will execute if the first executed command was the third option and it failed
   sprintf( base_command, "--silent --show-error --insecure --connect-timeout 10 --retry 2 --max-time 600 -F file=@%s -F submit=\"Upload Image\" -F brightmag=%lf -F faintmag=%lf -F searcharcsec=%lf --output %s 'http://scan.sai.msu.ru/cgi-bin/ucac5/search_ucac5.py'",
            vizquery_input_filename, catalog_search_parameters->brightest_mag,
            catalog_search_parameters->faintest_mag,
            catalog_search_parameters->search_radius_deg * 3600,
            vizquery_output_filename );
  }

  // Execute curl directly without shell interpretation (avoids command injection)
  fprintf( stderr, "Running curl...\n" );
  vizquery_run_success= execute_curl_direct( base_command, proxy_settings, 1 );

  if ( vizquery_run_success != 0 || count_lines_in_ASCII_file( vizquery_output_filename ) < 5 ) {
   fprintf( stderr, "ERROR: Both attempts failed\n" );
   // Free proxy settings if allocated
   if ( proxy_settings != NULL ) {
    free( proxy_settings );
   }
   return 1;
  }
 }

 // Free proxy settings if allocated
 if ( proxy_settings != NULL ) {
  free( proxy_settings );
 }

#ifdef DEBUGFILES
 scan_ucac5_debug_ds9_region= fopen( "scan_ucac5_output_debug_ds9.reg", "w" );
 fprintf( scan_ucac5_debug_ds9_region, "# Region file format: DS9 version 4.0\n" );
 fprintf( scan_ucac5_debug_ds9_region, "# Filename:\n" );
 fprintf( scan_ucac5_debug_ds9_region, "global color=red font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source\n" );
 fprintf( scan_ucac5_debug_ds9_region, "fk5\n" );
#endif

 f= fopen( vizquery_output_filename, "r" );
 while ( NULL != fgets( string, 1024, f ) ) {
  if ( string[0] == '#' )
   continue;

  if ( string[0] == '\n' )
   continue;

  epoch= pmRA= e_pmRA= pmDE= e_pmDE= 0.0;
  int sscanf_return_code= sscanf( string, "%lf %lf %lf %lf %lf %lf %lf %lf %lf", &measured_ra, &measured_dec, &distance, &catalog_ra, &catalog_dec, &catalog_mag, &epoch, &pmRA, &pmDE );
  if ( 6 > sscanf_return_code ) {
   continue;
  }
  if ( 9 > sscanf_return_code ) {
   epoch= pmRA= e_pmRA= pmDE= e_pmDE= 0.0;
  }

  cos_delta= cos( catalog_dec * M_PI / 180.0 );

  ///////////////// Account for proper motion /////////////////
  catalog_ra_original= catalog_ra;
  catalog_dec_original= catalog_dec;
  // assuming the epoch is a Julian Year https://en.wikipedia.org/wiki/Epoch_(astronomy)#Julian_years_and_J2000
  // assuming observing_epoch_jd is the same for all stars!
  observing_epoch_jy= 2000.0 + ( stars[0].observing_epoch_jd - 2451545.0 ) / 365.25;
  dt= observing_epoch_jy - epoch;
  // https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=I/340
  // pmRA is UCAC/Gaia proper motion in RA*cosDE
  catalog_ra= catalog_ra + pmRA / ( 3600000 * cos_delta ) * dt;
  catalog_dec= catalog_dec + pmDE / 3600000 * dt;
  /////////////////////////////////////////////////////////////

  // Now find which input star that was
  for ( i= 0; i < N; i++ ) {
   if ( stars[i].matched_with_astrometric_catalog == 1 ) {
    continue;
   }
   if ( fabs( stars[i].dec_deg_measured - measured_dec ) < catalog_search_parameters->search_radius_deg ) {
    if ( fabs( stars[i].ra_deg_measured - measured_ra ) * cos_delta < catalog_search_parameters->search_radius_deg ) {
     if ( distance > catalog_search_parameters->search_radius_deg * 3600 ) {
      continue;
     }

#ifdef DEBUGFILES
     fprintf( scan_ucac5_debug_ds9_region, "circle(%f,%f,%lf)\n", measured_ra, measured_dec, 10.0 * 21 / 3600 );
#endif

     // if we are here - this is a match
     stars[i].matched_with_astrometric_catalog= 1;
     stars[i].d_ra= catalog_ra - measured_ra;
     stars[i].d_dec= catalog_dec - measured_dec;
     stars[i].catalog_ra= catalog_ra;
     stars[i].catalog_dec= catalog_dec;
     stars[i].catalog_mag= catalog_mag;
     stars[i].catalog_mag_err= 0.0;
     stars[i].catalog_ra_original= catalog_ra_original;
     stars[i].catalog_dec_original= catalog_dec_original;

     //
     stars[i].match_distance_astrometric_catalog_arcsec= distance / 3600;

     // reset photometric info
     stars[i].APASS_B= 0.0;
     stars[i].APASS_B_err= 0.0;
     stars[i].APASS_V= 0.0;
     stars[i].APASS_V_err= 0.0;
     stars[i].APASS_r= 0.0;
     stars[i].APASS_r_err= 0.0;
     stars[i].APASS_i= 0.0;
     stars[i].APASS_i_err= 0.0;
     stars[i].Rc_computed_from_APASS_ri= 0.0;
     stars[i].Rc_computed_from_APASS_ri_err= 0.0;
     stars[i].Rc_computed_from_APASS_ri_err= 0.0;
     stars[i].Ic_computed_from_APASS_ri= 0.0;
     stars[i].Ic_computed_from_APASS_ri_err= 0.0;
     stars[i].APASS_g= 0.0;
     stars[i].APASS_g_err= 0.0;

     N_stars_matched_with_astrometric_catalog++;
     break; // like if we assume there will be only one match within distance - why not?
    }
   }
  } // for(i=0;i<N;i++)
 }
 fclose( f );
 fprintf( stderr, "Matched %d stars with UCAC5 at scan.\n", N_stars_matched_with_astrometric_catalog );
 if ( N_stars_matched_with_astrometric_catalog < 5 ) {
  fprintf( stderr, "WARNING: too few stars matched!\n" );
  return 1;
 }

#ifdef DEBUGFILES
 fclose( scan_ucac5_debug_ds9_region );
#endif

 // delete temporary files only on success
 if ( 0 != unlink( vizquery_input_filename ) )
  fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", vizquery_input_filename );
 if ( 0 != unlink( vizquery_output_filename ) )
  fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", vizquery_output_filename );

 return 0;
}

int search_UCAC5_at_scan__old_scan_and_vast_only( struct detected_star *stars, int N, struct str_catalog_search_parameters *catalog_search_parameters ) {
 double epoch, pmRA, e_pmRA, pmDE, e_pmDE, dt, observing_epoch_jy, catalog_ra_original, catalog_dec_original;
 int N_stars_matched_with_astrometric_catalog= 0;
 double measured_ra, measured_dec, distance, catalog_ra, catalog_dec, catalog_mag;
 double cos_delta;
 char string[1024];
 // char base_command[1024 + 3 * VAST_PATH_MAX + 2 * FILENAME_LENGTH];
 char base_command[BASE_COMMAND_LENGTH];
 FILE *vizquery_input;
 FILE *f;
 int i;
 int pid= getpid();
 char vizquery_input_filename[FILENAME_LENGTH];
 char vizquery_output_filename[FILENAME_LENGTH];
 int vizquery_run_success;
 int search_stars_counter;
 int zero_radec_counter;

 char path_to_vast_string[VAST_PATH_MAX];
 get_path_to_vast( path_to_vast_string );

 // try disabling scan UCAC5 access - this should trigger VizieR UCAC5 access
 // return 1;

#ifdef DEBUGFILES
 FILE *scan_ucac5_debug_ds9_region;
 scan_ucac5_debug_ds9_region= fopen( "scan_ucac5_input_debug_ds9.reg", "w" );
 fprintf( scan_ucac5_debug_ds9_region, "# Region file format: DS9 version 4.0\n" );
 fprintf( scan_ucac5_debug_ds9_region, "# Filename:\n" );
 fprintf( scan_ucac5_debug_ds9_region, "global color=green font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source\n" );
 fprintf( scan_ucac5_debug_ds9_region, "fk5\n" );
#endif

 // Initialize the allocated memory to null characters
 memset( vizquery_input_filename, '\0', FILENAME_LENGTH );
 memset( vizquery_output_filename, '\0', FILENAME_LENGTH );
 snprintf( vizquery_input_filename, FILENAME_LENGTH - 1, "scan_ucac5_%d.input", pid );
 snprintf( vizquery_output_filename, FILENAME_LENGTH - 1, "scan_ucac5_%d.output", pid );
 vizquery_input= fopen( vizquery_input_filename, "w" );
 if ( NULL == vizquery_input ) {
  fprintf( stderr, "ERROR in search_UCAC5_at_scan(): cannot open file %s for writing!\n", vizquery_input_filename );
  return 1;
 }
 search_stars_counter= 0;
 zero_radec_counter= 0;
 for ( i= 0; i < N; i++ ) {
  if ( stars[i].good_star == 1 ) {
   // check for a specific problem
   if ( stars[i].ra_deg_measured == 0.0 && stars[i].dec_deg_measured == 0.0 ) {
    zero_radec_counter++;
    if ( zero_radec_counter > 10 ) {
     fprintf( stderr, "ERROR in search_UCAC5_at_scan(): too many input positions are '0.000000 0.000000'\nWe cannot go to VizieR with that!\n" );
     exit( EXIT_FAILURE ); // terminate everything
    }
   }
   //
   fprintf( vizquery_input, "%lf %lf\n", stars[i].ra_deg_measured, stars[i].dec_deg_measured );
#ifdef DEBUGFILES
   fprintf( scan_ucac5_debug_ds9_region, "circle(%f,%f,%lf)\n", stars[i].ra_deg_measured, stars[i].dec_deg_measured, 5.0 * 21 / 3600 );
#endif
   search_stars_counter++;
   if ( search_stars_counter == MAX_STARS_IN_VIZQUERY ) {
    break;
   }
  }
 }
 fclose( vizquery_input );

#ifdef DEBUGFILES
 fclose( scan_ucac5_debug_ds9_region );
#endif

 if ( search_stars_counter < MIN_NUMBER_OF_STARS_ON_FRAME ) {
  fprintf( stderr, "ERROR in search_UCAC5_at_scan(): only %d stars are in the vizquery input list - that's too few!\n", search_stars_counter );
  return 1;
 }

 // Print search stat
 fprintf( stderr, "Searchig scan/vast for %d good reference stars...\n", search_stars_counter );

 // Get proxy settings if available
 char *proxy_settings= get_sanitized_curl_proxy();

 // Astrometric catalog search
 fprintf( stderr, "Searchig UCAC5...\n" );
 // Randomly choose between the two servers
 // Seed the random number generator
 srand( time( NULL ) );
 // Generate a random number (0 or 1)
 int randChoice= rand() % 2;

 // Construct base command
 // Initialize the allocated memory to null characters
 memset( base_command, '\0', BASE_COMMAND_LENGTH );
 if ( randChoice == 0 ) {
  snprintf( base_command, BASE_COMMAND_LENGTH, "--silent --show-error --insecure --connect-timeout 10 --retry 1 --max-time 600 -F file=@%s -F submit=\"Upload Image\" -F brightmag=%lf -F faintmag=%lf -F searcharcsec=%lf --output %s 'http://scan.sai.msu.ru/cgi-bin/ucac5/search_ucac5.py'",
            vizquery_input_filename, catalog_search_parameters->brightest_mag,
            catalog_search_parameters->faintest_mag,
            catalog_search_parameters->search_radius_deg * 3600,
            vizquery_output_filename );
 } else {
  snprintf( base_command, BASE_COMMAND_LENGTH, "--silent --show-error --insecure --connect-timeout 10 --retry 1 --max-time 600 -F file=@%s -F submit=\"Upload Image\" -F brightmag=%lf -F faintmag=%lf -F searcharcsec=%lf --output %s 'http://vast.sai.msu.ru/cgi-bin/ucac5/search_ucac5.py'",
            vizquery_input_filename, catalog_search_parameters->brightest_mag,
            catalog_search_parameters->faintest_mag,
            catalog_search_parameters->search_radius_deg * 3600,
            vizquery_output_filename );
 }
 base_command[BASE_COMMAND_LENGTH - 1]= '\0'; // just in case snprintf() messed up the last byte

 // Execute curl directly without shell interpretation (avoids command injection)
 fprintf( stderr, "Running curl...\n" );
 vizquery_run_success= execute_curl_direct( base_command, proxy_settings, 1 );

 if ( vizquery_run_success != 0 || count_lines_in_ASCII_file( vizquery_output_filename ) < 5 ) {
  fprintf( stderr, "First attempt failed, trying alternative command\n" );

  // Note the reverse order with respect to randChoice
  if ( randChoice == 0 ) {
   // This block will execute if the first executed command was the first option and it failed
   sprintf( base_command, "--silent --show-error --insecure --connect-timeout 10 --retry 2 --max-time 600 -F file=@%s -F submit=\"Upload Image\" -F brightmag=%lf -F faintmag=%lf -F searcharcsec=%lf --output %s 'http://vast.sai.msu.ru/cgi-bin/ucac5/search_ucac5.py'",
            vizquery_input_filename, catalog_search_parameters->brightest_mag,
            catalog_search_parameters->faintest_mag,
            catalog_search_parameters->search_radius_deg * 3600,
            vizquery_output_filename );
  } else {
   // This block will execute if the first executed command was the second option and it failed
   sprintf( base_command, "--silent --show-error --insecure --connect-timeout 10 --retry 2 --max-time 600 -F file=@%s -F submit=\"Upload Image\" -F brightmag=%lf -F faintmag=%lf -F searcharcsec=%lf --output %s 'http://scan.sai.msu.ru/cgi-bin/ucac5/search_ucac5.py'",
            vizquery_input_filename, catalog_search_parameters->brightest_mag,
            catalog_search_parameters->faintest_mag,
            catalog_search_parameters->search_radius_deg * 3600,
            vizquery_output_filename );
  }

  // Execute curl directly without shell interpretation (avoids command injection)
  fprintf( stderr, "Running curl...\n" );
  vizquery_run_success= execute_curl_direct( base_command, proxy_settings, 1 );

  if ( vizquery_run_success != 0 || count_lines_in_ASCII_file( vizquery_output_filename ) < 5 ) {
   fprintf( stderr, "ERROR: Both attempts failed\n" );
   // Free proxy settings if allocated
   if ( proxy_settings != NULL ) {
    free( proxy_settings );
   }
   return 1;
  }
 }

 // Free proxy settings if allocated
 if ( proxy_settings != NULL ) {
  free( proxy_settings );
 }

#ifdef DEBUGFILES
 scan_ucac5_debug_ds9_region= fopen( "scan_ucac5_output_debug_ds9.reg", "w" );
 fprintf( scan_ucac5_debug_ds9_region, "# Region file format: DS9 version 4.0\n" );
 fprintf( scan_ucac5_debug_ds9_region, "# Filename:\n" );
 fprintf( scan_ucac5_debug_ds9_region, "global color=red font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source\n" );
 fprintf( scan_ucac5_debug_ds9_region, "fk5\n" );
#endif

 f= fopen( vizquery_output_filename, "r" );
 while ( NULL != fgets( string, 1024, f ) ) {
  if ( string[0] == '#' )
   continue;

  if ( string[0] == '\n' )
   continue;

  epoch= pmRA= e_pmRA= pmDE= e_pmDE= 0.0;
  int sscanf_return_code= sscanf( string, "%lf %lf %lf %lf %lf %lf %lf %lf %lf", &measured_ra, &measured_dec, &distance, &catalog_ra, &catalog_dec, &catalog_mag, &epoch, &pmRA, &pmDE );
  if ( 6 > sscanf_return_code ) {
   continue;
  }
  if ( 9 > sscanf_return_code ) {
   epoch= pmRA= e_pmRA= pmDE= e_pmDE= 0.0;
  }

  cos_delta= cos( catalog_dec * M_PI / 180.0 );

  ///////////////// Account for proper motion /////////////////
  catalog_ra_original= catalog_ra;
  catalog_dec_original= catalog_dec;
  // assuming the epoch is a Julian Year https://en.wikipedia.org/wiki/Epoch_(astronomy)#Julian_years_and_J2000
  // assuming observing_epoch_jd is the same for all stars!
  observing_epoch_jy= 2000.0 + ( stars[0].observing_epoch_jd - 2451545.0 ) / 365.25;
  dt= observing_epoch_jy - epoch;
  // https://vizier.cds.unistra.fr/viz-bin/VizieR?-source=I/340
  // pmRA is UCAC/Gaia proper motion in RA*cosDE
  catalog_ra= catalog_ra + pmRA / ( 3600000 * cos_delta ) * dt;
  catalog_dec= catalog_dec + pmDE / 3600000 * dt;
  /////////////////////////////////////////////////////////////

  // Now find which input star that was
  for ( i= 0; i < N; i++ ) {
   if ( stars[i].matched_with_astrometric_catalog == 1 ) {
    continue;
   }
   if ( fabs( stars[i].dec_deg_measured - measured_dec ) < catalog_search_parameters->search_radius_deg ) {
    if ( fabs( stars[i].ra_deg_measured - measured_ra ) * cos_delta < catalog_search_parameters->search_radius_deg ) {
     if ( distance > catalog_search_parameters->search_radius_deg * 3600 ) {
      continue;
     }

#ifdef DEBUGFILES
     fprintf( scan_ucac5_debug_ds9_region, "circle(%f,%f,%lf)\n", measured_ra, measured_dec, 10.0 * 21 / 3600 );
#endif

     // if we are here - this is a match
     stars[i].matched_with_astrometric_catalog= 1;
     stars[i].d_ra= catalog_ra - measured_ra;
     stars[i].d_dec= catalog_dec - measured_dec;
     stars[i].catalog_ra= catalog_ra;
     stars[i].catalog_dec= catalog_dec;
     stars[i].catalog_mag= catalog_mag;
     stars[i].catalog_mag_err= 0.0;
     stars[i].catalog_ra_original= catalog_ra_original;
     stars[i].catalog_dec_original= catalog_dec_original;

     //
     stars[i].match_distance_astrometric_catalog_arcsec= distance / 3600;

     // reset photometric info
     stars[i].APASS_B= 0.0;
     stars[i].APASS_B_err= 0.0;
     stars[i].APASS_V= 0.0;
     stars[i].APASS_V_err= 0.0;
     stars[i].APASS_r= 0.0;
     stars[i].APASS_r_err= 0.0;
     stars[i].APASS_i= 0.0;
     stars[i].APASS_i_err= 0.0;
     stars[i].Rc_computed_from_APASS_ri= 0.0;
     stars[i].Rc_computed_from_APASS_ri_err= 0.0;
     stars[i].Rc_computed_from_APASS_ri_err= 0.0;
     stars[i].Ic_computed_from_APASS_ri= 0.0;
     stars[i].Ic_computed_from_APASS_ri_err= 0.0;
     stars[i].APASS_g= 0.0;
     stars[i].APASS_g_err= 0.0;

     N_stars_matched_with_astrometric_catalog++;
     break; // like if we assume there will be only one match within distance - why not?
    }
   }
  } // for(i=0;i<N;i++)
 }
 fclose( f );
 fprintf( stderr, "Matched %d stars with UCAC5 at scan.\n", N_stars_matched_with_astrometric_catalog );
 if ( N_stars_matched_with_astrometric_catalog < 5 ) {
  fprintf( stderr, "WARNING: too few stars matched!\n" );
  return 1;
 }

#ifdef DEBUGFILES
 fclose( scan_ucac5_debug_ds9_region );
#endif

 // delete temporary files only on success
 if ( 0 != unlink( vizquery_input_filename ) )
  fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", vizquery_input_filename );
 if ( 0 != unlink( vizquery_output_filename ) )
  fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", vizquery_output_filename );

 return 0;
}

int search_UCAC5_with_vizquery( struct detected_star *stars, int N, struct str_catalog_search_parameters *catalog_search_parameters ) {
 char command[BASE_COMMAND_LENGTH];
 FILE *vizquery_input;
 int i;
 int pid= getpid();
 char vizquery_input_filename[FILENAME_LENGTH];
 char vizquery_output_filename[FILENAME_LENGTH];
 int vizquery_run_success;
 int search_stars_counter;
 int zero_radec_counter;

 char path_to_vast_string[VAST_PATH_MAX];
 get_path_to_vast( path_to_vast_string );

 // Try the local copy of UCAC5
 if ( 0 == search_UCAC5_localcopy( stars, N, catalog_search_parameters ) ) {
  fprintf( stderr, "The local UCAC5 search seems to be a success\n" );
  return 0;
 } else {
  fprintf( stderr, "The local UCAC5 search failed. Trying remote search at scan\n" );
 }

 // Try the copy of UCAC5 at scan
 if ( 0 == search_UCAC5_at_scan( stars, N, catalog_search_parameters ) ) {
  fprintf( stderr, "The scan UCAC5 search seems to be a success\n" );
  return 0;
 } else {
  fprintf( stderr, "The scan UCAC5 search failed. Trying remote search with vizquery\n" );
  // exit( EXIT_FAILURE );
 }

 // Initialize the allocated memory to null characters
 memset( vizquery_input_filename, '\0', FILENAME_LENGTH );
 memset( vizquery_output_filename, '\0', FILENAME_LENGTH );
 snprintf( vizquery_input_filename, FILENAME_LENGTH - 1, "vizquery_%d.input", pid );
 snprintf( vizquery_output_filename, FILENAME_LENGTH - 1, "vizquery_%d.output", pid );
 vizquery_input= fopen( vizquery_input_filename, "w" );
 search_stars_counter= 0;
 zero_radec_counter= 0;
 for ( i= 0; i < N; i++ ) {
  if ( stars[i].good_star == 1 ) {
   // check for a specific problem
   if ( stars[i].ra_deg_measured == 0.0 && stars[i].dec_deg_measured == 0.0 ) {
    zero_radec_counter++;
    if ( zero_radec_counter > 10 ) {
     fprintf( stderr, "ERROR in search_UCAC5_with_vizquery(): too many input positions are '0.000000 0.000000'\nWe cannot go to VizieR with that!\n" );
     exit( EXIT_FAILURE ); // terminate everything
    }
   }
   //
   fprintf( vizquery_input, "%lf %lf\n", stars[i].ra_deg_measured, stars[i].dec_deg_measured );
   search_stars_counter++;
   if ( search_stars_counter == MAX_STARS_IN_VIZQUERY ) {
    break;
   }
  }
 }
 fclose( vizquery_input );

 if ( search_stars_counter < MIN_NUMBER_OF_STARS_ON_FRAME ) {
  fprintf( stderr, "ERROR in search_UCAC5_with_vizquery(): only %d stars are in the vizquery input list - that's too few!\n", search_stars_counter );
  return 1;
 }

 // Print search stat
 fprintf( stderr, "Searchig VizieR for %d good reference stars...\n", search_stars_counter );

 // Astrometric catalog search
 fprintf( stderr, "Searchig UCAC5...\n" );
 // yes, sorting in magnitude works
 // sprintf( command, "export PATH=\"$PATH:%slib/bin\"; $(%slib/find_timeout_command.sh) %.0lf %slib/vizquery -site=%s -mime=text -source=UCAC5 -out.max=1 -out.add=_1 -out.add=_r -out.form=mini -out=RAJ2000,DEJ2000,f.mag,EPucac,pmRA,e_pmRA,pmDE,e_pmDE f.mag=%.1lf..%.1lf -sort=f.mag -c.rs=%.1lf -list=%s > %s", path_to_vast_string, path_to_vast_string, (double)VIZIER_TIMEOUT_SEC, path_to_vast_string, VIZIER_SITE, catalog_search_parameters->brightest_mag, catalog_search_parameters->faintest_mag, catalog_search_parameters->search_radius_deg * 3600, vizquery_input_filename, vizquery_output_filename );
 sprintf( command, "export BEST_VIZIER_MIRROR=%s; echo $BEST_VIZIER_MIRROR; export PATH=\"$PATH:%slib/bin\"; $(%slib/find_timeout_command.sh) %.0lf %slib/vizquery -site=$BEST_VIZIER_MIRROR -mime=text -source=UCAC5 -out.max=1 -out.add=_1 -out.add=_r -out.form=mini -out=RAJ2000,DEJ2000,f.mag,EPucac,pmRA,e_pmRA,pmDE,e_pmDE f.mag=%.1lf..%.1lf -sort=f.mag -c.rs=%.1lf -list=%s > %s", VIZIER_SITE, path_to_vast_string, path_to_vast_string, (double)VIZIER_TIMEOUT_SEC, path_to_vast_string, catalog_search_parameters->brightest_mag, catalog_search_parameters->faintest_mag, catalog_search_parameters->search_radius_deg * 3600, vizquery_input_filename, vizquery_output_filename );

 fprintf( stderr, "%s\n", command );
 vizquery_run_success= system( command );
 if ( vizquery_run_success == 124 ) {
  fprintf( stderr, "ERROR: the script lib/vizquery has timed out :(\n" );
 }
 if ( vizquery_run_success != 0 ) {
  fprintf( stderr, "WARNING: some problem running lib/vizquery script. Is this an internet connection problem? Retrying...\n" );
  sleep( 10 );
  fprintf( stderr, "%s\n", command );
  vizquery_run_success= system( command );
  if ( vizquery_run_success == 124 ) {
   fprintf( stderr, "ERROR: the script lib/vizquery has timed out :(\n" );
  }
  if ( vizquery_run_success != 0 ) {
   fprintf( stderr, "WARNING: some problem running lib/vizquery script. Is this an internet connection problem? Retrying...\n" );
   sleep( 10 );
   fprintf( stderr, "%s\n", command );
   vizquery_run_success= system( command );
   if ( vizquery_run_success == 124 ) {
    fprintf( stderr, "ERROR: the script lib/vizquery has timed out :(\n" );
    exit( EXIT_FAILURE );
   }
   if ( vizquery_run_success != 0 ) {
    fprintf( stderr, "ERROR: problem running lib/vizquery script :(\n" );
    exit( EXIT_FAILURE );
   }
  }
 }

 if ( 0 != read_UCAC5_from_vizquery( stars, N, vizquery_output_filename, catalog_search_parameters ) ) {
  fprintf( stderr, "Problem getting UCAC5 data from VizieR. :(\n" );
  return 1;
 }

 // delete temporary files only on success
 // if ( vizquery_run_success == 0 ) {
 if ( 0 != unlink( vizquery_input_filename ) )
  fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", vizquery_input_filename );
 if ( 0 != unlink( vizquery_output_filename ) )
  fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", vizquery_output_filename );
 //}

 return 0;
}

int search_PANSTARRS1_with_vizquery( struct detected_star *stars, int N, struct str_catalog_search_parameters *catalog_search_parameters ) {
 char command[BASE_COMMAND_LENGTH];
 FILE *vizquery_input;
 int i;
 int pid= getpid();
 char vizquery_input_filename[FILENAME_LENGTH];
 char vizquery_output_filename[FILENAME_LENGTH];
 int vizquery_run_success;
 int search_stars_counter;

 char path_to_vast_string[VAST_PATH_MAX];
 get_path_to_vast( path_to_vast_string );

 // Initialize the allocated memory to null characters
 memset( vizquery_input_filename, '\0', FILENAME_LENGTH );
 memset( vizquery_output_filename, '\0', FILENAME_LENGTH );
 snprintf( vizquery_input_filename, FILENAME_LENGTH - 1, "vizquery_%d.input", pid );
 snprintf( vizquery_output_filename, FILENAME_LENGTH - 1, "vizquery_%d.output", pid );
 vizquery_input= fopen( vizquery_input_filename, "w" );
 search_stars_counter= 0;
 for ( i= 0; i < N; i++ ) {
  if ( stars[i].good_star == 1 && stars[i].matched_with_astrometric_catalog == 1 ) {
   // fprintf(vizquery_input,"%lf %lf\n",stars[i].ra_deg_measured,stars[i].dec_deg_measured);
   // fprintf(vizquery_input,"%lf %lf\n",stars[i].catalog_ra,stars[i].catalog_dec);
   //  The reference catalog epoch is expected to be closer to PANSTARRS1 epoch than some of the images we are going to process
   fprintf( vizquery_input, "%lf %lf\n", stars[i].catalog_ra_original, stars[i].catalog_dec_original );
   search_stars_counter++;
   // fprintf(stderr,"DEBUG  %lf %lf\n",stars[i].ra_deg_measured,stars[i].dec_deg_measured);
   if ( search_stars_counter == MAX_STARS_IN_VIZQUERY ) {
    break;
   }
  }
 }
 fclose( vizquery_input );

 if ( search_stars_counter < MIN_NUMBER_OF_STARS_ON_FRAME ) {
  fprintf( stderr, "ERROR in search_PANSTARRS1_with_vizquery(): only %d stars are in the vizquery input list - that's too few!\n", search_stars_counter );
  return 1;
 }

 // Print search stat
 fprintf( stderr, "Searchig VizieR for %d good reference stars...\n", search_stars_counter );

 // Photometric catalog search
 fprintf( stderr, "Searchig PANSTARRS1...\n" );
 // sprintf( command, "export PATH=\"$PATH:%slib/bin\"; $(%slib/find_timeout_command.sh) %.0lf %slib/vizquery -site=%s -mime=text -source=PS1 -out.max=1 -out.add=_1 -out.add=_r -out.form=mini -out=RAJ2000,DEJ2000,gmag,e_gmag,rmag,e_rmag,imag,e_imag rmag=%.1lf..%.1lf -sort=rmag -c.rs=%.1lf -list=%s > %s", path_to_vast_string, path_to_vast_string, (double)VIZIER_TIMEOUT_SEC, path_to_vast_string, VIZIER_SITE, catalog_search_parameters->brightest_mag, catalog_search_parameters->faintest_mag, catalog_search_parameters->search_radius_deg * 3600, vizquery_input_filename, vizquery_output_filename );
 sprintf( command, "export BEST_VIZIER_MIRROR=%s; echo $BEST_VIZIER_MIRROR; export PATH=\"$PATH:%slib/bin\"; $(%slib/find_timeout_command.sh) %.0lf %slib/vizquery -site=$BEST_VIZIER_MIRROR -mime=text -source=PS1 -out.max=1 -out.add=_1 -out.add=_r -out.form=mini -out=RAJ2000,DEJ2000,gmag,e_gmag,rmag,e_rmag,imag,e_imag rmag=%.1lf..%.1lf -sort=rmag -c.rs=%.1lf -list=%s > %s", VIZIER_SITE, path_to_vast_string, path_to_vast_string, (double)VIZIER_TIMEOUT_SEC, path_to_vast_string, catalog_search_parameters->brightest_mag, catalog_search_parameters->faintest_mag, catalog_search_parameters->search_radius_deg * 3600, vizquery_input_filename, vizquery_output_filename );

 fprintf( stderr, "%s\n", command );
 vizquery_run_success= system( command );
 if ( vizquery_run_success != 0 ) {
  fprintf( stderr, "WARNING: some problem running lib/vizquery script. Is this an internet connection problem? Retrying...\n" );
  sleep( 10 );
  fprintf( stderr, "%s\n", command );
  vizquery_run_success= system( command );
  if ( vizquery_run_success != 0 ) {
   fprintf( stderr, "WARNING: some problem running lib/vizquery script. Is this an internet connection problem? Retrying...\n" );
   sleep( 10 );
   fprintf( stderr, "%s\n", command );
   vizquery_run_success= system( command );
   if ( vizquery_run_success != 0 ) {
    fprintf( stderr, "ERROR: problem running lib/vizquery script :(\n" );
    exit( EXIT_FAILURE );
   }
  }
 }

 vizquery_run_success= read_PANSTARRS1_from_vizquery( stars, N, vizquery_output_filename, catalog_search_parameters );

 // delete temporary files only on success
 // if ( vizquery_run_success == 0 ) {
 if ( 0 != unlink( vizquery_input_filename ) )
  fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", vizquery_input_filename );
 if ( 0 != unlink( vizquery_output_filename ) )
  fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", vizquery_output_filename );
 //}

 return vizquery_run_success;
}

int search_APASS_with_vizquery( struct detected_star *stars, int N, struct str_catalog_search_parameters *catalog_search_parameters ) {

 int backoff_retry_count= 0;
 int backoff_wait_time_sec= 1;

 char command[BASE_COMMAND_LENGTH];
 FILE *vizquery_input;
 int i;
 int pid= getpid();
 char vizquery_input_filename[FILENAME_LENGTH];
 char vizquery_output_filename[FILENAME_LENGTH];
 int vizquery_run_success;
 int search_stars_counter;

 char path_to_vast_string[VAST_PATH_MAX];
 get_path_to_vast( path_to_vast_string );

 // Initialize the allocated memory to null characters
 memset( vizquery_input_filename, '\0', FILENAME_LENGTH );
 memset( vizquery_output_filename, '\0', FILENAME_LENGTH );
 snprintf( vizquery_input_filename, FILENAME_LENGTH - 1, "vizquery_%d.input", pid );
 snprintf( vizquery_output_filename, FILENAME_LENGTH - 1, "vizquery_%d.output", pid );
 vizquery_input= fopen( vizquery_input_filename, "w" );
 if ( vizquery_input == NULL ) {
  fprintf( stderr, "ERROR in search_APASS_with_vizquery(): Cannot open file %s for writing.\n", vizquery_input_filename );
  return 1;
 }
 search_stars_counter= 0;
 for ( i= 0; i < N; i++ ) {
  if ( stars[i].good_star == 1 && stars[i].matched_with_astrometric_catalog == 1 ) {
   //  The reference catalog epoch is expected to be closer to APASS epoch than some of the images we are going to process
   fprintf( vizquery_input, "%lf %lf\n", stars[i].catalog_ra_original, stars[i].catalog_dec_original );
   search_stars_counter++;
   // if ( search_stars_counter == MAX_STARS_IN_VIZQUERY ) {
   if ( search_stars_counter == MAX_STARS_IN_LOCAL_CAT_QUERY ) {
    break;
   }
  }
 }
 fclose( vizquery_input );

 if ( search_stars_counter < MIN_NUMBER_OF_STARS_ON_FRAME ) {
  fprintf( stderr, "ERROR in search_APASS_with_vizquery(): only %d stars are in the vizquery input list - that's too few!\n", search_stars_counter );
  return 1;
 }

 // Print search stat
 fprintf( stderr, "Searchig VizieR for %d good reference stars...\n", search_stars_counter );

 // Photometric catalog search
 fprintf( stderr, "Searchig APASS...\n" );
 sprintf( command,
          "export PATH=\"$PATH:%slib/bin\"; $(%slib/find_timeout_command.sh) %.0lf %slib/vizquery -site=$(%slib/choose_vizier_mirror.sh APASS) -mime=text -source=II/336/apass9 -out.max=1 -out.add=_1 -out.add=_r -out.form=mini -out=RAJ2000,DEJ2000,Bmag,e_Bmag,Vmag,e_Vmag,r\\'mag,e_r\\'mag,i\\'mag,e_i\\'mag,g\\'mag,e_g\\'mag Vmag=%.1lf..%.1lf -sort=Vmag -c.rs=%.1lf -list=%s > %s",
          path_to_vast_string,
          path_to_vast_string,
          (double)VIZIER_TIMEOUT_SEC,
          path_to_vast_string,
          path_to_vast_string,
          catalog_search_parameters->brightest_mag,
          catalog_search_parameters->faintest_mag,
          catalog_search_parameters->search_radius_deg * 3600,
          vizquery_input_filename, vizquery_output_filename );

 fprintf( stderr, "%s\n", command );
 vizquery_run_success= system( command );
 // Actually vizquery may return 0 on failure, it's the timeout that may return non-zero (while we may still have planty of good data lines)
 if ( vizquery_run_success != 0 ) {
  fprintf( stderr, "WARNING: it looks like there was a timeout while running lib/vizquery script.\n" );
 }

 vizquery_run_success= read_APASS_from_vizquery( stars, N, vizquery_output_filename, catalog_search_parameters );
 // If the output of vizquery looks bad or empty or whatever - this is when we retry
 // read_APASS_from_vizquery returns 2 if the VizieR interaction was a success, but there are just too few stars
 // while ( 0 != vizquery_run_success && 2 != vizquery_run_success && backoff_retry_count < 5 ) {
 while ( 0 != vizquery_run_success && 2 != vizquery_run_success && backoff_retry_count < 3 ) {
  backoff_retry_count= backoff_retry_count + 1;
  backoff_wait_time_sec= backoff_wait_time_sec * 2;
  fprintf( stderr, "WARNING: some problem reading the vizquery output. Is this an internet connection problem? Retrying in %d sec...\n", backoff_wait_time_sec );
  sleep( backoff_retry_count );
  fprintf( stderr, "%s\n", command );
  vizquery_run_success= system( command );
  if ( vizquery_run_success != 0 ) {
   fprintf( stderr, "WARNING: it looks like there was a timeout while running lib/vizquery script. (retry %d)\n", backoff_retry_count );
  }
  vizquery_run_success= read_APASS_from_vizquery( stars, N, vizquery_output_filename, catalog_search_parameters );
  if ( vizquery_run_success != 0 ) {
   fprintf( stderr, "WARNING: failed to get APASS data with lib/vizquery script :(\n" );
   // return 1; // we don't want to quit, the function will later return vizquery_run_success
  }
 }

 // delete temporary files only on success
 // if ( vizquery_run_success == 0 ) {
 if ( 0 != unlink( vizquery_input_filename ) )
  fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", vizquery_input_filename );
 if ( 0 != unlink( vizquery_output_filename ) )
  fprintf( stderr, "WARNING! Cannot delete temporary file %s\n", vizquery_output_filename );
 //}

 return vizquery_run_success;
}

// static inline int compare_star_on_mag_solve(const void *a1, const void *a2) {
static int compare_star_on_mag_solve( const void *a1, const void *a2 ) {
 struct detected_star *s1, *s2;
 s1= (struct detected_star *)a1;
 s2= (struct detected_star *)a2;
 //
 //     The comparison function must return an integer less than, equal to, or
 //     greater than zero if the first argument is	considered to be respectively
 //     less than,	equal to, or greater than the second.
 if ( s1->mag < s2->mag ) {
  return -1;
 }
 return 1;
 /* THIS WAS SO WRONG -- 0
 if( s1->mag < s2->mag )
  return 0;
 else
  return 1;
*/
}

int correct_measured_positions( struct detected_star *stars, int N, double search_radius, int process_only_stars_matched_with_catalog, struct str_catalog_search_parameters *catalog_search_parameters ) {

 double estimated_output_accuracy_of_the_plate_solution_arcsec;

 int i, j, N_good;

 double A1, B1, C1, A2, B2, C2;

 double *x;
 double *y;
 double *z1;
 double *z2;

 double distance;

 struct detected_star *only_good_starsmatched_with_catalog;
 int N_only_good; // counter for the structures array above

 // debug_dump_star_struct( stars, N ); exit(1); // !!!!!!!!!!!!!!!!!!!!!!!!!!

 x= malloc( N * sizeof( double ) );
 if ( x == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for x(solve_plate_with_UCAC5.c)\n" );
  exit( EXIT_FAILURE );
 };
 y= malloc( N * sizeof( double ) );
 if ( y == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for y(solve_plate_with_UCAC5.c)\n" );
  exit( EXIT_FAILURE );
 };
 z1= malloc( N * sizeof( double ) );
 if ( z1 == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for z1(solve_plate_with_UCAC5.c)\n" );
  exit( EXIT_FAILURE );
 };
 z2= malloc( N * sizeof( double ) );
 if ( z2 == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for z2(solve_plate_with_UCAC5.c)\n" );
  exit( EXIT_FAILURE );
 };

 // *** Find global linear solution  ***
 for ( i= 0, N_good= 0; i < N; i++ ) {
  if ( stars[i].good_star != 1 )
   continue;
  // if( stars[i].good_star==1 && stars[i].matched_with_catalog==1 ){
  if ( stars[i].matched_with_astrometric_catalog == 1 ) {
   x[N_good]= stars[i].x_pix;
   y[N_good]= stars[i].y_pix;
   z1[N_good]= stars[i].d_ra;
   z2[N_good]= stars[i].d_dec;
   N_good++;
  }
 }

 // for(i=0;i<N_good;i++)
 //  fprintf(stderr,"%lf %lf %lf OGAOGA\n",x[i],y[i],z2[i]);

 fit_plane_lin( x, y, z1, (unsigned int)N_good, &A1, &B1, &C1 );
 fit_plane_lin( x, y, z2, (unsigned int)N_good, &A2, &B2, &C2 );

// apply the linear correction
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i )
#endif
#endif
 for ( i= 0; i < N; i++ ) {
  stars[i].computed_d_ra= A1 * stars[i].x_pix + B1 * stars[i].y_pix + C1;
  stars[i].computed_d_dec= A2 * stars[i].x_pix + B2 * stars[i].y_pix + C2;
  stars[i].corrected_ra_planefit= stars[i].ra_deg_measured + stars[i].computed_d_ra;
  stars[i].corrected_dec_planefit= stars[i].dec_deg_measured + stars[i].computed_d_dec;
  // clean-up outliers after the linear fit
  if ( stars[i].matched_with_astrometric_catalog == 1 ) {
   if ( compute_distance_on_sphere( stars[i].catalog_ra, stars[i].catalog_dec, stars[i].corrected_ra_planefit, stars[i].corrected_dec_planefit ) > catalog_search_parameters->search_radius_second_step_deg ) {
    stars[i].matched_with_astrometric_catalog= 0;
   }
  }
 }

 // *** Find astrometric correction as a function of magnitude  ***
 double poly_coeff[10];

 for ( N_good= 0, i= 0; i < N; i++ ) {
  if ( stars[i].good_star == 1 && stars[i].matched_with_astrometric_catalog == 1 ) {
   x[N_good]= stars[i].mag;
   y[N_good]= 0.1; // fake error, same for all stars since we want an unweighted fit
   z1[N_good]= stars[i].catalog_ra - stars[i].corrected_ra_planefit;
   z2[N_good]= stars[i].catalog_dec - stars[i].corrected_dec_planefit;
   N_good++;
  }
 }

 wlinearfit( x, z1, y, N_good, poly_coeff, NULL );
 C1= poly_coeff[0];
 A1= poly_coeff[1];
 wlinearfit( x, z2, y, N_good, poly_coeff, NULL );
 C2= poly_coeff[0];
 A2= poly_coeff[1];
//
// A1=A2=C1=C2=0.0;
// apply the correction
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i )
#endif
#endif
 for ( i= 0; i < N; i++ ) {
  // for(i=N;i--;){
  stars[i].corrected_mag_ra= stars[i].corrected_ra_planefit + ( A1 * stars[i].mag + C1 );
  stars[i].corrected_mag_dec= stars[i].corrected_dec_planefit + ( A2 * stars[i].mag + C2 );
 }

 // *** Find local corrections  ***
 double local_correction_ra;
 double local_correction_dec;
 // double target_mag;
 double target_ra;
 double target_dec;
 double target_x_pix;
 double target_y_pix;
 double current_accuracy, current_accuracy_ra, current_accuracy_dec;
 double best_accuracy;
 double current_search_radius;
 double best_search_radius= REFERENCE_LOCAL_SOLUTION_RADIUS_DEG;
 double best_local_correction_ra;
 double best_local_correction_dec;
 double cos_delta;

 // Create a copy of the star catalog containing only the good ones matched with catalog
 only_good_starsmatched_with_catalog= malloc( N * sizeof( struct detected_star ) );
 if ( only_good_starsmatched_with_catalog == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for x(solve_plate_with_UCAC5.c)\n" );
  exit( EXIT_FAILURE );
 };

 N_only_good= 0;
 for ( i= N; i--; ) {
  if ( stars[i].matched_with_astrometric_catalog != 1 )
   continue;
  if ( stars[i].good_star != 1 )
   continue;
  only_good_starsmatched_with_catalog[N_only_good]= stars[i];
  N_only_good++;
 }

 for ( j= 0; j < N; j++ ) {

  if ( process_only_stars_matched_with_catalog == 1 && stars[j].matched_with_astrometric_catalog != 1 )
   continue;
  // set target star
  // target_mag=stars[j].mag;
  target_x_pix= stars[j].x_pix;
  target_y_pix= stars[j].y_pix;
  target_ra= stars[j].ra_deg_measured;
  target_dec= stars[j].dec_deg_measured;
  cos_delta= cos( stars[j].dec_deg_measured * M_PI / 180.0 );

  // try various corrections
  best_accuracy= 9980.0;    // 99.9*99.9;
  best_search_radius= 99.9; // just so we can distinguish if the value comes from a previous star or not
  N_good= 0;                // just in case
  // for(current_search_radius=search_radius;current_search_radius>0.05*search_radius;current_search_radius=current_search_radius-0.1*current_search_radius){
  for ( current_search_radius= search_radius; current_search_radius > 0.01 * search_radius; current_search_radius= current_search_radius - 0.1 * current_search_radius ) {
   // determine the best search radius for local correction
   // for(i=0,N_good=0;i<N;i++){
   N_good= 0;
   for ( i= N_only_good; i--; ) {
    // if( stars[i].matched_with_catalog!=1 )continue;
    // if( stars[i].good_star!=1 )continue;
    //  It turns out we should not make the serach box smaller than 500 pix, test on ../M31_ISON_test/M31-1-001-001_dupe-1.fts
    if ( fabs( target_x_pix - only_good_starsmatched_with_catalog[i].x_pix ) > 500 )
     continue; // a miserable attempt to optimize
    if ( fabs( target_y_pix - only_good_starsmatched_with_catalog[i].y_pix ) > 500 )
     continue; // a miserable attempt to optimize
    if ( fabs( target_dec - only_good_starsmatched_with_catalog[i].dec_deg_measured ) > current_search_radius )
     continue; // a miserable attempt to optimize
    //
    // if( target_mag<stars[i].mag-1.5 )continue;
    ///
    distance= compute_distance_on_sphere( only_good_starsmatched_with_catalog[i].ra_deg_measured, only_good_starsmatched_with_catalog[i].dec_deg_measured, target_ra, target_dec );
    if ( distance < current_search_radius ) {
     if ( distance == 0.0 )
      continue; //
     z1[N_good]= only_good_starsmatched_with_catalog[i].catalog_ra - only_good_starsmatched_with_catalog[i].corrected_mag_ra;
     z2[N_good]= only_good_starsmatched_with_catalog[i].catalog_dec - only_good_starsmatched_with_catalog[i].corrected_mag_dec;
     N_good++;
     if ( N_good > 501 )
      break; // too many stars
     //}
    }
   }
   if ( N_good > 500 )
    continue; // too many stars
   ///
   /// EXPERIMENTAL attempt to avoid the situation that the initial value for the search radius is too small
   // if this is the first iteration
   if ( current_search_radius == search_radius && best_search_radius == 99.9 ) {
    if ( N_good < 10 )
     current_search_radius= 3.0 * current_search_radius;
   }
   ///
   // if( N_good<5 )break; // too few stars
   // remove_outliers_from_a_pair_of_arrays( z1, z2, &N_good);
   ///
   if ( N_good < 5 )
    break; // too few stars
   // if( N_good<10 )break; // too few stars
   current_accuracy_ra= gsl_stats_variance( z1, 1, N_good );
   // current_accuracy_ra=gsl_stats_sd(z1,1,N_good);
   // current_accuracy_ra=esimate_sigma_from_MAD_of_unsorted_data( z1, N_good);
   current_accuracy_dec= gsl_stats_variance( z2, 1, N_good );
   // current_accuracy_dec=gsl_stats_sd(z2,1,N_good);
   // current_accuracy_dec=esimate_sigma_from_MAD_of_unsorted_data( z2, N_good);
   // current_accuracy=sqrt(current_accuracy_ra*cos_delta*current_accuracy_ra*cos_delta+current_accuracy_dec*current_accuracy_dec);
   // current_accuracy=current_accuracy_ra*cos_delta*current_accuracy_ra*cos_delta+current_accuracy_dec*current_accuracy_dec;
   current_accuracy= current_accuracy_ra * cos_delta * cos_delta + current_accuracy_dec; // for gsl_stats_variance()
   if ( current_accuracy < best_accuracy ) {
    best_accuracy= current_accuracy;
    best_search_radius= current_search_radius;
   }
  }

  // fprintf(stderr,"############### DEBUG ###############\n");
  // fprintf(stderr,"%lf %lf\n",target_ra, target_dec);

  // determine the local correction using the best search radius
  N_good= 0;
  for ( i= N_only_good; i--; ) {
   // for(i=0,N_good=0;i<N;i++){
   //  if( stars[i].matched_with_catalog!=1 )continue;
   //  if( stars[i].good_star!=1 )continue;
   if ( fabs( target_x_pix - only_good_starsmatched_with_catalog[i].x_pix ) > 500 )
    continue; // a miserable attempt to optimize
   if ( fabs( target_y_pix - only_good_starsmatched_with_catalog[i].y_pix ) > 500 )
    continue; // a miserable attempt to optimize
   if ( fabs( target_dec - only_good_starsmatched_with_catalog[i].dec_deg_measured ) > best_search_radius )
    continue; // a miserable attempt to optimize
   //
   // if( target_mag<stars[i].mag-1.5 )continue;
   //
   distance= compute_distance_on_sphere( only_good_starsmatched_with_catalog[i].ra_deg_measured, only_good_starsmatched_with_catalog[i].dec_deg_measured, target_ra, target_dec );
   if ( distance < best_search_radius ) {
    if ( distance == 0.0 )
     continue; //
    z1[N_good]= only_good_starsmatched_with_catalog[i].catalog_ra - only_good_starsmatched_with_catalog[i].corrected_mag_ra;
    z2[N_good]= only_good_starsmatched_with_catalog[i].catalog_dec - only_good_starsmatched_with_catalog[i].corrected_mag_dec;
    N_good++;
    // fprintf(stderr,"%lf %lf\n",only_good_starsmatched_with_catalog[i].ra_deg_measured,only_good_starsmatched_with_catalog[i].dec_deg_measured);
   }
  }
  // exit(1);

  /// Somehow this seems very dangerous
  // remove_outliers_from_a_pair_of_arrays( z1, z2, &N_good);
  ///

  if ( N_good >= 3 ) {

   best_local_correction_ra= gsl_stats_mean( z1, 1, N_good );
   best_local_correction_dec= gsl_stats_mean( z2, 1, N_good );

   /*
   gsl_sort(z1,1,N_good);
   gsl_sort(z2,1,N_good);
   best_local_correction_ra=gsl_stats_median_from_sorted_data(z1,1,N_good);
   best_local_correction_dec=gsl_stats_median_from_sorted_data(z2,1,N_good);
*/
  } else {
   // fprintf(stderr,"DEBUG: best_accuracy=%lf best_search_radius=%lf (arcmin)\n",best_accuracy,best_search_radius*60);
   best_local_correction_ra= 0.0;
   best_local_correction_dec= 0.0;
   best_accuracy= 9998.0;
  }

  // fprintf(stderr,"DEBUG: best_accuracy=%lf best_search_radius=%lf stars[j].matched_with_catalog=%d best_local_correction_ra=%lf best_local_correction_dec=%lf\n",best_accuracy*3600,best_search_radius,stars[j].matched_with_catalog,best_local_correction_ra*3600,best_local_correction_dec*3600);

  local_correction_ra= best_local_correction_ra;
  local_correction_dec= best_local_correction_dec;

  // save the determined value of the local correction for this star
  stars[j].local_correction_ra= local_correction_ra;
  stars[j].local_correction_dec= local_correction_dec;
  //  If no correction was applied
  if ( best_accuracy > 9000 ) {
   stars[j].estimated_local_correction_accuracy= 0.0;
   // Emergency! No correction computed!
  } else {
   stars[j].estimated_local_correction_accuracy= sqrt( best_accuracy ) / c4( N_good );
  }

 } // for(j=0;j<N;j++){
 //}
 free( only_good_starsmatched_with_catalog );

// Taken out of the above for cycle so we can parallelize these actions
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( j )
#endif
#endif
 for ( j= 0; j < N; j++ ) {
  // Apply previously determined local corrections to each star
  stars[j].corrected_ra_local= stars[j].corrected_mag_ra + stars[j].local_correction_ra;
  stars[j].corrected_dec_local= stars[j].corrected_mag_dec + stars[j].local_correction_dec;
  // Clean-up outliers
  if ( stars[j].matched_with_astrometric_catalog == 1 ) {
   distance= compute_distance_on_sphere( stars[j].corrected_ra_local, stars[j].corrected_dec_local, stars[j].catalog_ra, stars[j].catalog_dec );
   if ( distance > catalog_search_parameters->search_radius_second_step_deg )
    stars[j].matched_with_astrometric_catalog= 0;
  }
  //
 }

 // Estimate accuracy
 for ( i= 0, j= 0; j < N; j++ ) {
  if ( stars[j].estimated_local_correction_accuracy != 0.0 ) {
   z1[i]= stars[j].estimated_local_correction_accuracy;
   i++;
  }
 }
 gsl_sort( z1, 1, i );
 estimated_output_accuracy_of_the_plate_solution_arcsec= 3600 * gsl_stats_median_from_sorted_data( z1, 1, i );
 fprintf( stderr, "Estimated accuracy of the plate solution: %.2lf\" \n", estimated_output_accuracy_of_the_plate_solution_arcsec );

 free( x );
 free( y );
 free( z1 );
 free( z2 );

 // Check if the estimated accuracy is unreallistically large
 if ( estimated_output_accuracy_of_the_plate_solution_arcsec > 60.0 ) {
  fprintf( stderr, "ERROR: the estimated accuracy of the plate solution seems unrealistically large!\nSomething is very wrong!\nDoes the image have *many* hot pixels that are incorrectly identified as stats?\n" );
  return 1;
 }
 // Check if the estimated accuracy is unreallistically small
 if ( estimated_output_accuracy_of_the_plate_solution_arcsec <= 0.0 ) {
  fprintf( stderr, "ERROR: the estimated accuracy of the plate solution seems unrealistically small!\nSomething is very wrong!\n" );
  return 1;
 }

 return 0;
}

int main( int argc, char **argv ) {

 /////////////////////////////////////
 // Options for getopt()
 char *cvalue= NULL;
 const char *const shortopt= "ni:f:";
 const struct option longopt[]= {
     { "no_photometric_catalog", 0, NULL, 'n' }, { "iterations", 1, NULL, 'i' }, { "fov", 1, NULL, 'f' }, { NULL, 0, NULL, 0 } }; // NULL string must be in the end
 int nextopt;
 /////////////////////////////////////

 int use_photometric_catalog= 1;
 int requested_number_of_iterations= MAX_NUMBER_OF_ITERATIONS_FOR_UCAC5_MATCH;

 int number_of_stars_in_wcs_catalog;
 struct detected_star *stars;
 char fits_image_filename[FILENAME_LENGTH];
 char wcs_basename_fits_image_filename[FILENAME_LENGTH];
 int i;

 double approximate_field_of_view_arcmin= DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN;

 int stars_matched_at_previous_iteration, stars_matched_at_this_iteration;

 struct str_catalog_search_parameters catalog_search_parameters;

 int solution_iteration;

 FILE *pipe_for_try_to_guess_image_fov;
 char command_string[2 * FILENAME_LENGTH + VAST_PATH_MAX];

 char path_to_vast_string[VAST_PATH_MAX];
 get_path_to_vast( path_to_vast_string );

 number_of_stars_in_wcs_catalog= 0; // =0 just in case

 if ( argc < 2 ) {
  fprintf( stderr, "Usage: %s myfitsimage.fits [--fov APPROXIMATE_FIELD_OF_VIEW_ARCMIN] [--iterations NUMBER_OF_ITERATIONS] [--no_photometric_catalog]\n\nExamples: %s myfitsimage.fits\n          %s myfitsimage.fits -f 40\n", argv[0], argv[0], argv[0] );
  return 1;
 }

 // Parse command line arguments
 fprintf( stderr, "Parsing command line arguments...\n" );
 while ( nextopt= getopt_long( argc, argv, shortopt, longopt, NULL ), nextopt != -1 ) {
  switch ( nextopt ) {
  case 'n':
   fprintf( stdout, "Option '-n' not using photometric catalogs, just stick with astrometry\n" );
   use_photometric_catalog= 0;
   break;
  case 'i':
   cvalue= optarg;
   if ( 1 == is_file( cvalue ) ) {
    fprintf( stderr, "Option '-i' requires an argument: maximum number of iterations\n" );
    exit( EXIT_FAILURE );
   }
   requested_number_of_iterations= atoi( cvalue );
   if ( requested_number_of_iterations < 1 || requested_number_of_iterations > 10 ) {
    fprintf( stderr, "WARNING: maximum number of iterations %d is set incorrectly!\nResorting to the default value of %d\n", requested_number_of_iterations, MAX_NUMBER_OF_ITERATIONS_FOR_UCAC5_MATCH );
    requested_number_of_iterations= MAX_NUMBER_OF_ITERATIONS_FOR_UCAC5_MATCH;
   }
   fprintf( stdout, "opt '-i': %d is the maximum number of iterations\n", requested_number_of_iterations );
   break;
  case 'f':
   cvalue= optarg;
   if ( 1 == is_file( cvalue ) ) {
    fprintf( stderr, "Option '-%c' requires an argument: field of view in arcminutes\n", optopt );
    exit( EXIT_FAILURE );
   }
   approximate_field_of_view_arcmin= atof( cvalue );
   if ( approximate_field_of_view_arcmin < 2.0 || approximate_field_of_view_arcmin > 600.0 ) {
    fprintf( stderr, "WARNING: the field of view %lf seems to be set incorrectly!\nResorting to the default value of %lf\n", approximate_field_of_view_arcmin, DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN );
    approximate_field_of_view_arcmin= DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN;
   }
   fprintf( stdout, "opt '-%c': %lf is the field of view in arcminutes\n", optopt, approximate_field_of_view_arcmin );
   break;
  case '?':
   fprintf( stderr, "ERROR: unknown option!\n" );
   exit( EXIT_FAILURE );
   break;
  case -1:
   fprintf( stderr, "Done parsing the options\n" );
   break;
  }
 }

 // strncpy(fits_image_filename, argv[optind], FILENAME_LENGTH);
 if ( 0 != any_unusual_characters_in_string( argv[optind] ) ) {
  fprintf( stderr, "ERROR preparing to encode the input file name\n" );
  exit( EXIT_FAILURE );
 }
 if ( 0 != safely_encode_user_input_string( fits_image_filename, argv[optind], FILENAME_LENGTH ) ) {
  fprintf( stderr, "ERROR trying to encode the input file name\n" );
  exit( EXIT_FAILURE );
 }
 fits_image_filename[FILENAME_LENGTH - 1]= '\0';

 //
 replace_file_with_symlink_if_filename_contains_white_spaces( fits_image_filename );
 cutout_green_channel_out_of_RGB_DSLR_image( fits_image_filename );
 //

 // Check if the input file has already been processed
 if ( 1 == check_if_the_output_catalog_already_exist( fits_image_filename ) ) {
  return 0;
 }

 // Test if whatever is provided as argv[1] is actually a readable FITS file
 if ( 0 != fitsfile_read_check( fits_image_filename ) ) {
  fprintf( stderr, "ERROR reading FITS file %s\n", fits_image_filename );
  return 1;
 }

 if ( approximate_field_of_view_arcmin == DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN ) {
  if ( NULL != strstr( fits_image_filename, "wcs_" ) ) {
   // If the input is already a VaST plate-solved image, we want the exact field of view, not a guess
   sprintf( command_string, "%sutil/fov_of_wcs_calibrated_image.sh %s | grep 'Image size:' | awk -F\"[ 'x]\" '{if ($3 > $4) print $3; else print $4}'", path_to_vast_string, fits_image_filename );
   pipe_for_try_to_guess_image_fov= popen( command_string, "r" );
   if ( NULL == pipe_for_try_to_guess_image_fov ) {
    fprintf( stderr, "WARNING: failed to run command: %s\n", command_string );
    approximate_field_of_view_arcmin= DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN;
   } else {
    if ( 1 == fscanf( pipe_for_try_to_guess_image_fov, "%lf", &approximate_field_of_view_arcmin ) ) {
     pclose( pipe_for_try_to_guess_image_fov );
    } else {
     pclose( pipe_for_try_to_guess_image_fov ); // ???
     fprintf( stderr, "WARNING: error parsing the output of the command: %s\n", command_string );
     approximate_field_of_view_arcmin= DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN;
    }
   }
  }
 } // if ( approximate_field_of_view_arcmin == DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN ) {

 if ( approximate_field_of_view_arcmin == DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN ) {
  // If the input image is not plate-solved or something whent wrong while extracting its Fov - we try to guess
  sprintf( command_string, "%slib/try_to_guess_image_fov %s", path_to_vast_string, fits_image_filename );
  pipe_for_try_to_guess_image_fov= popen( command_string, "r" );
  if ( NULL == pipe_for_try_to_guess_image_fov ) {
   fprintf( stderr, "WARNING: failed to run command: %s\n", command_string );
   approximate_field_of_view_arcmin= DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN;
  } else {
   if ( 1 == fscanf( pipe_for_try_to_guess_image_fov, "%lf", &approximate_field_of_view_arcmin ) ) {
    pclose( pipe_for_try_to_guess_image_fov );
   } else {
    pclose( pipe_for_try_to_guess_image_fov ); // ???
    fprintf( stderr, "WARNING: error parsing the output of the command: %s\n", command_string );
    approximate_field_of_view_arcmin= DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN;
   }
  }
 } // if ( approximate_field_of_view_arcmin == DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN ) {

 // **** Blind plate solution with Astrometry.net ****
 if ( 0 != blind_plate_solve_with_astrometry_net( fits_image_filename, approximate_field_of_view_arcmin ) ) {
  fprintf( stderr, "ERROR: cannot perform blind plate solution.\n" );
  return 1;
 }

 stars= malloc( MAX_NUMBER_OF_STARS * sizeof( struct detected_star ) );
 if ( stars == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for stars(solve_plate_with_UCAC5.c)\n" );
  exit( EXIT_FAILURE );
 };

 // **** Read the star catalog ****
 fprintf( stderr, "%s is preparing to read a catalog corresponding to the image %s\n", argv[0], fits_image_filename );
 if ( 0 != read_wcs_catalog( fits_image_filename, stars, &number_of_stars_in_wcs_catalog ) ) {
  fprintf( stderr, "ERROR: reading SExtractor catalog file...\n" );
  free( stars );
  return 1;
 }
 if ( number_of_stars_in_wcs_catalog < MIN_NUMBER_OF_STARS_ON_FRAME ) {
  fprintf( stderr, "ERROR: number_of_stars_in_wcs_catalog=%d", number_of_stars_in_wcs_catalog );
  free( stars );
  return 1;
 } else {
  fprintf( stderr, "%s got %d stars from the SExtractor catalog\n", argv[0], number_of_stars_in_wcs_catalog );
 }
 qsort( stars, number_of_stars_in_wcs_catalog, sizeof( struct detected_star ), compare_star_on_mag_solve );

 // TEST //
 // for(i=0;i<number_of_stars_in_wcs_catalog;i++){
 // if( i==1000 )break;
 // fprintf(stderr, "%04d  %8.4lf %d\n", i, stars[i].mag, stars[i].flag );
 //}
 //////////

 // Make sure all stars have a flag that they are not matched with a catalog yet
 // for(i=0;i<number_of_stars_in_wcs_catalog;i++)stars[i].matched_with_catalog=0;

 // Update cataog search parameters base on FoV of the solved image
 wcs_basename( fits_image_filename, wcs_basename_fits_image_filename );
 sprintf( command_string, "%sutil/fov_of_wcs_calibrated_image.sh %s | grep 'Image size:' | awk -F\"[ 'x]\" '{if ($3 > $4) print $3; else print $4}'", path_to_vast_string, wcs_basename_fits_image_filename );
 // sprintf( command_string, "%sutil/fov_of_wcs_calibrated_image.sh %s | grep 'Image size:' | awk -F\"[ 'x]\" '{if ($3 > $4) print $3; else print $4}'", path_to_vast_string, wcs_basename( fits_image_filename ) );
 pipe_for_try_to_guess_image_fov= popen( command_string, "r" );
 if ( NULL == pipe_for_try_to_guess_image_fov ) {
  fprintf( stderr, "WARNING: failed to run command: %s\n", command_string );
  // approximate_field_of_view_arcmin= DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN;
 } else {
  if ( 1 == fscanf( pipe_for_try_to_guess_image_fov, "%lf", &approximate_field_of_view_arcmin ) ) {
   pclose( pipe_for_try_to_guess_image_fov );
  } else {
   pclose( pipe_for_try_to_guess_image_fov ); // ???
   fprintf( stderr, "WARNING: error parsing the output of the command: %s\n", command_string );
   approximate_field_of_view_arcmin= DEFAULT_APPROXIMATE_FIELD_OF_VIEW_ARCMIN;
  }
  fprintf( stderr, "Updated FoV from the plate-solved image: %.1lf'\n", approximate_field_of_view_arcmin );
 }

 fprintf( stderr, "Seting catalog search parameters based on the expected field of view %.1lf arcmin\n", approximate_field_of_view_arcmin );
 set_catalog_search_parameters( approximate_field_of_view_arcmin, &catalog_search_parameters );

 // **** Querry UCAC5 ****
 fprintf( stderr, "\nITERATION 01 -- talking to VizieR, this might be slow!\n" );
 // if( 0!=search_UCAC4_with_vizquery( stars, number_of_stars_in_wcs_catalog, &catalog_search_parameters) ){fprintf(stderr,"ERROR running vizquery\n");return 1;}
 if ( 0 != search_UCAC5_with_vizquery( stars, number_of_stars_in_wcs_catalog, &catalog_search_parameters ) ) {
  fprintf( stderr, "ERROR running vizquery\n" );
  free( stars );
  return 1;
 }

 // Check if there is any hope
 // compute the number of matched stars
 for ( stars_matched_at_this_iteration= 0, i= 0; i < number_of_stars_in_wcs_catalog; i++ ) {
  if ( stars[i].matched_with_astrometric_catalog == 1 )
   stars_matched_at_this_iteration++;
 }
 //////// EVIL HARDCODED NUMBER
 if ( stars_matched_at_this_iteration < 50 ) {
  fprintf( stderr, "\nRetrying with a larger catalog search radius.\n" );
  catalog_search_parameters.search_radius_deg= 2.0 * catalog_search_parameters.search_radius_deg;
  catalog_search_parameters.search_radius_second_step_deg= 2.0 * catalog_search_parameters.search_radius_second_step_deg;
  // We need to reset matched_with_astrometric_catalog flags before re-running the search!
  for ( i= 0; i < number_of_stars_in_wcs_catalog; i++ ) {
   stars[i].matched_with_astrometric_catalog= 0;
  }
  //
  // if( 0!=search_UCAC4_with_vizquery( stars, number_of_stars_in_wcs_catalog, &catalog_search_parameters) ){fprintf(stderr,"ERROR running vizquery\n");return 1;}
  if ( 0 != search_UCAC5_with_vizquery( stars, number_of_stars_in_wcs_catalog, &catalog_search_parameters ) ) {
   fprintf( stderr, "ERROR running vizquery\n" );
   free( stars );
   return 1;
  }
  // if we are still here - re-compute the number of stars matched at this iteration
  for ( stars_matched_at_this_iteration= 0, i= 0; i < number_of_stars_in_wcs_catalog; i++ ) {
   if ( stars[i].matched_with_astrometric_catalog == 1 )
    stars_matched_at_this_iteration++;
  }
 } // if( stars_matched_at_this_iteration < 50 ) {

 // Correct the measured positions
 fprintf( stderr, "Correcting the measured astrometric positions...\n" );
 if ( 0 != correct_measured_positions( stars, number_of_stars_in_wcs_catalog, REFERENCE_LOCAL_SOLUTION_RADIUS_DEG, 1, &catalog_search_parameters ) ) {
  fprintf( stderr, "\nERROR running correct_measured_positions()\n\n" );
  free( stars );
  return 1;
 }

 fprintf( stderr, "Removing outliers...\n" );
 // Remove outliers (likley wrong identifications)
 for ( i= 0; i < number_of_stars_in_wcs_catalog; i++ )
  if ( stars[i].matched_with_astrometric_catalog == 1 )
   if ( compute_distance_on_sphere( stars[i].catalog_ra, stars[i].catalog_dec, stars[i].corrected_ra_local, stars[i].corrected_dec_local ) > catalog_search_parameters.search_radius_second_step_deg )
    stars[i].matched_with_astrometric_catalog= 0;

 // re-compute correct the measured positions
 fprintf( stderr, "Correcting the measured astrometric positions...\n" );
 if ( 0 != correct_measured_positions( stars, number_of_stars_in_wcs_catalog, REFERENCE_LOCAL_SOLUTION_RADIUS_DEG, 0, &catalog_search_parameters ) ) {
  fprintf( stderr, "\nERROR running correct_measured_positions()\n\n" );
  free( stars );
  return 1;
 }

 // compute the number of matched stars
 for ( stars_matched_at_this_iteration= 0, i= 0; i < number_of_stars_in_wcs_catalog; i++ ) {
  if ( stars[i].matched_with_astrometric_catalog == 1 )
   stars_matched_at_this_iteration++;
 }
 stars_matched_at_previous_iteration= stars_matched_at_this_iteration;

 // Apply the local corrections and iterate to find a better plate solution
 // for ( solution_iteration= 2; solution_iteration <= MAX_NUMBER_OF_ITERATIONS_FOR_UCAC5_MATCH; solution_iteration++ ) {
 for ( solution_iteration= 2; solution_iteration <= requested_number_of_iterations; solution_iteration++ ) {

  fprintf( stderr, "\nITERATION %02d -- talking to VizieR, this might be slow!\n", solution_iteration );
  for ( i= 0; i < number_of_stars_in_wcs_catalog; i++ ) {
   stars[i].ra_deg_measured= stars[i].corrected_ra_local;
   stars[i].dec_deg_measured= stars[i].corrected_dec_local;
   // Make sure all stars have a flag that they are not matched with a catalog yet
   stars[i].matched_with_astrometric_catalog= 0;
   //
   stars[i].matched_with_photometric_catalog= 0;
  }
  // search_UCAC4_with_vizquery( stars, number_of_stars_in_wcs_catalog);
  // if( 0!=search_UCAC4_with_vizquery( stars, number_of_stars_in_wcs_catalog, &catalog_search_parameters) ){fprintf(stderr,"ERROR running vizquery\n");return 1;}
  if ( 0 != search_UCAC5_with_vizquery( stars, number_of_stars_in_wcs_catalog, &catalog_search_parameters ) ) {
   fprintf( stderr, "ERROR running vizquery\n" );
   free( stars );
   return 1;
  }
  if ( 0 != correct_measured_positions( stars, number_of_stars_in_wcs_catalog, REFERENCE_LOCAL_SOLUTION_RADIUS_DEG, 1, &catalog_search_parameters ) ) {
   fprintf( stderr, "\nERROR running correct_measured_positions()\n\n" );
   free( stars );
   return 1;
  }

  // remove outliers
  for ( i= 0; i < number_of_stars_in_wcs_catalog; i++ )
   if ( stars[i].matched_with_astrometric_catalog == 1 )
    if ( compute_distance_on_sphere( stars[i].catalog_ra, stars[i].catalog_dec, stars[i].corrected_ra_local, stars[i].corrected_dec_local ) > catalog_search_parameters.search_radius_second_step_deg )
     stars[i].matched_with_astrometric_catalog= 0;
  // re-compute the corrections, now applying them to all stars
  if ( 0 != correct_measured_positions( stars, number_of_stars_in_wcs_catalog, REFERENCE_LOCAL_SOLUTION_RADIUS_DEG, 0, &catalog_search_parameters ) ) {
   fprintf( stderr, "\nERROR running correct_measured_positions()\n\n" );
   free( stars );
   return 1;
  }

  // compute the number of matched stars
  stars_matched_at_previous_iteration= stars_matched_at_this_iteration;
  for ( stars_matched_at_this_iteration= 0, i= 0; i < number_of_stars_in_wcs_catalog; i++ ) {
   if ( stars[i].matched_with_astrometric_catalog == 1 )
    stars_matched_at_this_iteration++;
  }

  // Report the current status
  fprintf( stderr, "Excluding outliers - %d stars left (next iteration limit %d)\n", stars_matched_at_this_iteration, stars_matched_at_previous_iteration + (int)( 0.1 * stars_matched_at_previous_iteration ) );

  // check if there was a noticable improvement in the solution
  if ( stars_matched_at_this_iteration < stars_matched_at_previous_iteration + (int)( 0.1 * (double)stars_matched_at_previous_iteration + 0.5 ) || stars_matched_at_this_iteration == 0 ) {
   fprintf( stderr, "Stop iterations.\n" );
   if ( stars_matched_at_this_iteration < MIN_NUMBER_OF_STARS_FOR_UCAC5_MATCH ) {
    fprintf( stderr, "\n\n The number of stars matched with the catalog is suspiciously low!\n Something is not right here... :(\n\n" );
   } else {
    fprintf( stderr, "\n\n The field is successfully solved and matched with the astrometric catalog! :)\n\n" );
   }
   break;
  }

 } // for(solution_iteration=2;solution_iteration<=MAX_NUMBER_OF_ITERATIONS_FOR_UCAC5_MATCH;solution_iteration++){

#ifdef DEBUGFILES
 // Inspect the output
 // Note that the content of solve_plate_debug.txt corresponds to the LAST iteration
 FILE *solve_plate_debug;
 solve_plate_debug= fopen( "solve_plate_debug.txt", "w" );
 for ( i= 0; i < number_of_stars_in_wcs_catalog; i++ ) {
  if ( stars[i].matched_with_astrometric_catalog == 1 )
   fprintf( solve_plate_debug, "%10lf %10lf  %+10lf %+10lf  %+10lf %+10lf  %+10lf %+10lf %+10lf %+10lf  %+10lf %+10lf   %+10lf %+10lf %+10lf %+10lf  %+10lf  %+10lf %+10lf\n", // 1 2
            stars[i].x_pix, stars[i].y_pix,                                                                                                                                    // 3 4
            stars[i].d_ra * 3600, stars[i].d_dec * 3600,                                                                                                                       // 5 6
            stars[i].local_correction_ra * 3600, stars[i].local_correction_dec * 3600,                                                                                         // 7 8
            ( stars[i].catalog_ra - stars[i].corrected_ra_local ) * 3600, ( stars[i].catalog_dec - stars[i].corrected_dec_local ) * 3600,                                      // 9 10
            ( stars[i].catalog_ra - stars[i].ra_deg_measured_orig ) * 3600, ( stars[i].catalog_dec - stars[i].dec_deg_measured_orig ) * 3600,                                  // 11 12
            ( stars[i].catalog_ra - stars[i].corrected_ra_planefit ) * 3600, ( stars[i].catalog_dec - stars[i].corrected_dec_planefit ) * 3600,                                // 13 14
            stars[i].catalog_ra, stars[i].catalog_dec,                                                                                                                         // 15 16
            stars[i].computed_d_ra * 3600, stars[i].computed_d_dec * 3600,                                                                                                     // 17
            stars[i].mag,
            ( stars[i].catalog_ra - stars[i].corrected_mag_ra ) * 3600, ( stars[i].catalog_dec - stars[i].corrected_mag_dec ) * 3600 );
 }
 fclose( solve_plate_debug );
#endif

 if ( use_photometric_catalog == 1 ) {
  // Photometric calibration
  if ( 0 != search_APASS_with_vizquery( stars, number_of_stars_in_wcs_catalog, &catalog_search_parameters ) ) {
   fprintf( stderr, "ERROR running search_APASS_with_vizquery()\n" );
   fprintf( stderr, "Maybe this sky area is not covered by APASS yet?\nMaybe the image is too deep and narrow-field that there are not unaturated APASS stars in it?\n\nTrying the Pan-STARRS1 catalog as the fallback option...\n\nWARNING: using Pan-STARRS1 instead of APASS for magnitude calibration!!!!\n\n" );
   // We need to reset matched_with_astrometric_catalog flags before re-running the search!
   for ( i= 0; i < number_of_stars_in_wcs_catalog; i++ ) {
    stars[i].matched_with_photometric_catalog= 0;
   }
   if ( 0 != search_PANSTARRS1_with_vizquery( stars, number_of_stars_in_wcs_catalog, &catalog_search_parameters ) ) {
    fprintf( stderr, "ERROR running search_PANSTARRS1_with_vizquery()\n" );
    // Fail if no photometric catalogs could be reached
    // free( stars );
    // return 1;
    // Real use case: VizieR down so photoemtric catalogs cannot be reached.
    // That's bad but what's even worse is that we also can't determine coordinates.
    // Let's print a big error and continue.
    fprintf( stderr, "\n\n !!!! Photometric calibration ERROR !!!!\nCannot reach photometric catalogs! Only astrometry will be calibrated.\nYou may measure coordinates of stars, but automated magnitude scale calibration will not work!\n\n" );
   }
  }
 } // if ( use_photometric_catalog == 1 ) {

 // Write output
 write_wcs_catalog( fits_image_filename, stars, number_of_stars_in_wcs_catalog );
 write_matched_stars_to_ds9_region( fits_image_filename, stars, number_of_stars_in_wcs_catalog );
 write_astrometric_residuals_vector_field( fits_image_filename, stars, number_of_stars_in_wcs_catalog );

 free( stars );
 return 0;
}
