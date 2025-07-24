/*

 vast.c - photometric reduction of images with SExtractor.

 This file is part of VaST -
 a SExtractor front-end for search of variable objects in a series of FITS images.

 Copyleft 2005-2025  Kirill Sokolovsky <kirx@kirx.net>,
                     Alexandr Lebedev  <lebastr@gmail.com>,
                     Dmitry Nasonov,
                     Sergey Nazarov,
                     Vladimir Bazilevich,
                     Ferdinand

 This program is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.

 You should have received a copy of the GNU General Public License
 along with this program; if not, write to the Free Software
 Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.

*/

/****************** Include files ******************/

// Standard header files
#include <stdio.h>
#include <stdlib.h>

// #define _GNU_SOURCE
#include <string.h> // for memmem

#include <signal.h>
#include <math.h>
#include <time.h> /* to measure execution time */
#include <getopt.h>
#include <libgen.h>    /* for basename() */
#include <unistd.h>    /* for sleep() and getpid() */
#include <sys/types.h> /* for getpid() */
#include <sys/wait.h>  /* defines WEXITED */
#include <sys/resource.h>
#include <sys/stat.h> /* for stat(), also requires #include <sys/types.h> and #include <unistd.h> */
#include <dirent.h>   /* to work with directories */

#include <strings.h> // for strcasecmp()

// Include omp.h ONLY if VaST compiler flag is requesting it
// Include omp.h ONLY if the compiler supports OpenMP
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#include <omp.h> // for omp_get_num_threads() and omp_set_num_threads()
#endif
#endif

// GSL header files
#include <gsl/gsl_statistics.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_errno.h> // for GSL_SUCCESS, GSL_NAN

// CFITSIO
#include "fitsio.h" // we use a local copy of this file because we use a local copy of cfitsio

// VaST's own header files
#include "ident.h"
#include "vast_limits.h"
#include "vast_report_memory_error.h"
#include "detailed_error_messages.h"
#include "photocurve.h"
#include "get_number_of_cpu_cores.h"
#include "fit_plane_lin.h"
#include "fitsfile_read_check.h"
#include "wpolyfit.h"
#include "replace_file_with_symlink_if_filename_contains_white_spaces.h"
#include "lightcurve_io.h"
#include "variability_indexes.h"
#include "write_individual_image_log.h"
//
#include "filter_MagSize.h"
//
#include "parse_sextractor_catalog.h"
//
#include "count_lines_in_ASCII_file.h" // for count_lines_in_ASCII_file()
//
#include "is_point_close_or_off_the_frame_edge.h" // for is_point_close_or_off_the_frame_edge()
//
#include "detection_limit.h" // for get_detection_limit_sn()

/****************** Auxiliary functions ******************/

// #define debug_x 586.696
// #define debug_y 438.463

/* A reminder to myself:

SExtractor flags:
----------------

1     The object has neighbors, bright and close enough to
      significantly bias the photometry, or bad pixels
      (more than 10% of the integrated area affected).

2     The object was originally blended with another one.

4     At least one pixel of the object is saturated
      (or very close to).

8     The object is truncated (too close to an image boundary).

16    Object's aperture data are incomplete or corrupted.

32    Object's isophotal data are incomplete or corrupted.

64    A memory overflow occurred during deblending.

128   A memory overflow occurred during extraction.


An object close to an image border may have FLAGS = 16,
or perhaps FLAGS = 8+16+32 = 56.

*/

void version( char *version_string ) {
 strncpy( version_string, "VaST 1.0rc88", 32 );
 return;
}

void print_vast_version( void ) {
 char version_string[128];
 version( version_string );
 fprintf( stderr, "\n--==%s==--\n\n", version_string );
 return;
}

void report_and_handle_too_many_stars_error( void ) {
 // user message
 fprintf( stderr, "#######################\nVaST thinks there are too many stars on the images.\n\nIn most cases this is not the case and VaST/SExtractor detects noise fluctuations and counts them as stars.\nIf this is the case you may want to change the detection settings in default.sex\nTry to set a higher star detection limit (get less stars per frame) by changing DETECT_MINAREA and DETECT_THRESH/ANALYSIS_THRESH\n\nYou may look at how well stars are detected by running './sextract_single_image'. Most stars visible on the image should be marked\nwith green circles and the green circles should not appear around things that are not stars.\n\nIf you are sure that it's the actual number of stars on image that exceeds the VaST limit of %d,\nchange the string \"#define MAX_NUMBER_OF_STARS %d\" in src/vast_limits.h file and recompile VaST by running \"make\".\n#######################\n", MAX_NUMBER_OF_STARS, MAX_NUMBER_OF_STARS );
 // clean the MAX_NUMBER_OF_STARS lightcurve files
 fprintf( stderr, "Removing the %d outNNNNN.dat lightcurve files.\n", MAX_NUMBER_OF_STARS );
 if ( 0 != system( "util/clean_data.sh all >/dev/null" ) ) {
  fprintf( stderr, "There was an error while cleaning old files!\n" );
 } else {
  fprintf( stderr, "Done with cleaning!\n" );
 }

 return;
}

void print_TT_reminder( int show_timer_or_quit_instantly ) {

 int n;

 fprintf( stderr, "\n" );
 fprintf( stderr, "\n" );

 fprintf( stderr, "              #########   \x1B[34;47mATTENTION!\x1B[33;00m   #########              \n" );
 fprintf( stderr, "According to the IAU recommendation (Resolution B1 XXIII IAU GA,\n" );
 fprintf( stderr, "see http://www.iers.org/IERS/EN/Science/Recommendations/resolutionB1.html )  \n" );
 fprintf( stderr, "Julian Dates (JDs) computed by VaST will be expressed by default    \n" );
 fprintf( stderr, "in \x1B[34;47mTerrestrial Time (TT)\x1B[33;00m! " );
 fprintf( stderr, "Starting from January 1, 2017:\n  TT = UTC + 69.184 sec  \n" );
 fprintf( stderr, "If you want JDs to be expressed in UTC, use '-u' or '--UTC' key: './vast -u'\n" );
 fprintf( stderr, "You may find which time system was used in vast_summary.log\n\n" );
 fprintf( stderr, "Please \x1B[01;31mmake sure you know the difference between Terrestrial Time and UTC\033[00m,\n" );
 fprintf( stderr, "before deriving the time of minimum of an eclipsing binary or maximum of\n" );
 fprintf( stderr, "a pulsating star, sending a VaST lightcurve to your collaborators, AAVSO,\n" );
 fprintf( stderr, "B.R.N.O. database etc. Often people and databases expect JDs in UTC, not TT.\n" );
 fprintf( stderr, "More information may be found at https://en.wikipedia.org/wiki/Terrestrial_Time\n\n" );
 if ( show_timer_or_quit_instantly == 2 ) {
  return;
 }
 fprintf( stderr, "If you need accurate timing, don't forget to apply the Heliocentric Correction\n" );
 fprintf( stderr, "to the lightcurve. This can be done using 'util/hjd_input_in_TT' or 'util/hjd_input_in_UTC'.\n\n" );
 fprintf( stderr, "The more accurate barycentric time correction may be computed with VARTOOLS:\n" );
 fprintf( stderr, "http://www.astro.princeton.edu/~jhartman/vartools.html#converttime\n" );
 fprintf( stderr, "The SPICE library ( https://naif.jpl.nasa.gov/ ) support needs to be enabled\n" );
 fprintf( stderr, "when compiling VARTOOLS.\n\n" );
 fprintf( stderr, "Have fun! =)\n" );

 if ( show_timer_or_quit_instantly == 1 ) {
  return;
 }
 fprintf( stderr, "\n\n" );

 fprintf( stderr, "This warning message will disappear in...   " );
 /* sleep for 6 seconds to make sure user saw the message */
 for ( n= 5; n > 0; n-- ) {
  sleep( 1 );
  fprintf( stderr, "%d ", n );
 }
 sleep( 1 );
 fprintf( stderr, "NOW!\n" );

 return;
}

/* help_msg(const char* progname, int exit_code) - print help */
void help_msg( const char *progname, int exit_code ) {
 fprintf( stdout, "Usage: %s [options] image1.fit image2.fit ... imageN.fit\n\n", progname );
 printf( "Options:\n" );
 printf( "  -h or --help       print this message\n" );
 printf( "  -9 or --ds9        use DS9 instead of pgfv to view FITS files\n" );
 printf( "  -f or --nofind     run ./find_candidates manually\n" );
 printf( "  -d or --debug      run in debug (verbose) mode\n" );
 printf( "  -t 2 or --type 2   frame-to-frame magnitude calibration type: \n" );
 printf( "                     0 - linear magnitude calibration (vary zero-point and slope)\n" );
 printf( "                     1 - magnitude calibration with parabola (default)\n" );
 printf( "                     2 - zero-point only magnitude calibration (linear with the fixed slope)\n" );
 printf( "                     3 - \"photocurve\" magnitude calibration (for photographic plates)\n" );
 printf( "                     4 - robust linear magnitude calibration (vary zero-point and slope, automated outlier rejection, no weights)\n" );
 printf( "  -p or --poly       equivalent to '-t 0' [OPTION ONLY FOR BACKWARD COMPATIBILITY] DO NOT use polynomial magnitude calibration (useful for good quality CCD images)\n" );
 printf( "  -o or --photocurve equivalent to '-t 3' [OPTION ONLY FOR BACKWARD COMPATIBILITY] use formulas (1) and (3) from Bacher et al. (2005, MNRAS, 362, 542) for \n" );
 printf( "                     magnitude calibration. Useful for photographic data\n" );
 printf( "  -P or --PSF        PSF photometry mode with SExtractor and PSFEx\n" );
 printf( "  -r or --norotation assume the input images are not rotated by more than %.1lf deg. w.r.t. the first (reference) one\n", MAX_NOROTATION_ANGLE_RAD * 180.0 / M_PI );
 printf( "  -l or --nodiscardell     do NOT discard images with elliptical stars (bad tracking)\n" );
 printf( "  -e or --failsafe   FAILSAFE mode. Only stars detected on the reference frame will be processed\n" );
 printf( "  -u or --UTC        always assume UTC time system, do not perform conversion to TT\n" );
 printf( "  -k or --nojdkeyword  ignore \"JD\" keyword in FITS image header. Time of observation will be taken from the usual keywords instead\n" );
 printf( "  -K or --nodateobskeyword  ignore \"DATE-OBS\" keyword in FITS header. VaST will try to derive observing time from other keywords\n" );
 printf( "  -a 5.0 or --aperture 5.0  use fixed aperture (e.g. 5 pixels) in diameter\n" );
 printf( "  -b 200 or --matchstarnumber 200  use 200 (e.g. 200) reference stars for image matching\n" );
 printf( "  -y 3 or --sysrem 3 conduct a few (e.g. 3) iterations of SysRem\n" );
 printf( "  -x 3 or --maxsextractorflag 3 accept stars with flag <=3 (3 means 'accept blended stars')\n" );
 printf( "  -j or --position_dependent_correction    use position-dependent magnitude correction (recommended for wide-field images)\n" );
 printf( "  -J or --no_position_dependent_correction DO NOT use position-dependent magnitude correction (recommended for narrow-field images with not too many stars on them)\n" );
 printf( "  -g or --guess_saturation_limit try to guess image saturation limit based on the brightest pixels found in the image\n" );
 printf( "  -G or --no_guess_saturation_limit DO NOT try to guess image saturation limit based on the brightest pixels found in the image\n" );
 printf( "  -1 or --magsizefilter filter-out sources that appear too large or to small for their magnitude (compared to other sources on this image)\n" );
 printf( "  -2 or --nomagsizefilter DO NOT filter-out sources that appear too large or to small for their magnitude (compared to other sources on this image)\n" );
 printf( "  -3 or --selectbestaperture for each object select measurement aperture that minimized the lightcurve scatter\n" );
 printf( "  -4 or --noerrorsrescale disable photometric error rescaling\n" );
 printf( "  -5 10.0 or --starmatchraius 10.0 use a fixed-radius (in pixels) comparison circle for star matching\n" );
 printf( "  -6 or --notremovebadimages disable automated identification of bad images\n" );
 printf( "  -7 or --autoselectrefimage  automatically select the deepest image as the reference image\n" );
 printf( "  -8 or --excluderefimage  do not use the reference image for photometry\n" );
 printf( "        --movingobject  manually specify moving object position at each image (comet/asteroid/space junk photometry)\n" );
 printf( "\nExamples:\n" );
 printf( "  ./vast ../data/ccd_image-001.fit ../data/ccd_image-*.fit       # Typical CCD image reduction.\n" );
 printf( "  ./vast --UTC ../data/ccd_image-001.fit ../data/ccd_image-*.fit # CCD image reduction, UTC time will be used instead of TT.\n" );
 printf( "  ./vast -y 1 ../data/ccd_image-001.fit ../data/ccd_image-*.fit  # CCD image reduction with one SysRem iteration.\n" );
 printf( "  ./vast --movingobject -a33 --type 2 ../data/ccd_image-*.fit    # moving object, fixed 33pix-diameter aperture, magnitude zero-point offset calibration only (mag-mag relation slope fixed to 1.0)\n" );

 print_TT_reminder( 1 );

 exit( exit_code );
}

// a helper function for the magnitude limit calculator
void extract_mag_and_snr_from_structStar( const struct Star *stars, size_t n_stars, double *mag_array, double *snr_array ) {
 size_t i;
 for ( i= 0; i < n_stars; i++ ) {
  mag_array[i]= (double)stars[i].mag;
  snr_array[i]= stars[i].flux / stars[i].flux_err;
 }
 return;
}

// a comparison function to qsort the observations chached in memory
int compare_star_num( const void *a, const void *b ) {
 const struct Observation *obs_a= (const struct Observation *)a;
 const struct Observation *obs_b= (const struct Observation *)b;

 return ( obs_a->star_num - obs_b->star_num );
}

size_t binary_search_first( struct Observation *arr, size_t size, int target ) {
 size_t left= 0;
 size_t right= size;
 size_t mid;

 while ( left < right ) {
  mid= left + ( right - left ) / 2;
  if ( arr[mid].star_num < target ) {
   left= mid + 1;
  } else {
   right= mid;
  }
 }

 return left;
}

void write_obs_to_file( FILE *file_out, struct Observation *obs ) {
 char string_with_float_parameters_and_saved_FITS_keywords[2048 + FITS_KEYWORDS_IN_LC_LENGTH];
#ifdef WRITE_ADDITIONAL_APERTURES_TO_LIGHTCURVES
 snprintf( string_with_float_parameters_and_saved_FITS_keywords, sizeof( string_with_float_parameters_and_saved_FITS_keywords ),
           "  %+.4lf %.4lf  %+.4lf %.4lf  %+.4lf %.4lf  %+.4lf %.4lf  %+.4lf %.4lf  %s",
           obs->float_parameters[2],
           obs->float_parameters[3],
           obs->float_parameters[4],
           obs->float_parameters[5],
           obs->float_parameters[6],
           obs->float_parameters[7],
           obs->float_parameters[8],
           obs->float_parameters[9],
           obs->float_parameters[10],
           obs->float_parameters[11],
           obs->fits_header_keywords_to_be_recorded_in_lightcurve );
#else
 snprintf( string_with_float_parameters_and_saved_FITS_keywords, sizeof( string_with_float_parameters_and_saved_FITS_keywords ),
           "  %s", obs->fits_header_keywords_to_be_recorded_in_lightcurve );
#endif
 write_lightcurve_point( file_out, obs->JD, obs->mag, obs->mag_err, obs->X, obs->Y, obs->APER, obs->filename, string_with_float_parameters_and_saved_FITS_keywords );
 obs->is_used= 1;
 return;
}

int read_input_file_with_user_specified_moving_object_position( char **input_images, float *moving_object__user_array_x, float *moving_object__user_array_y, int Num ) {
 FILE *file_user_specified_moving_object_position;
 int i;

 char imagefilename_from_input_file[FILENAME_LENGTH];
 float moving_object_x_from_input_file;
 float moving_object_y_from_input_file;

 file_user_specified_moving_object_position= fopen( "vast_input_user_specified_moving_object_position.txt", "r" );
 if ( file_user_specified_moving_object_position == NULL ) {
  fprintf( stderr, "\n\nNo vast_input_user_specified_moving_object_position.txt - will ask for the moving target posiiton interactively\n\n" );
  return 1;
 }
 // Initialize, just in case
 for ( i= 0; i < Num; i++ ) {
  moving_object__user_array_x[i]= moving_object__user_array_y[i]= 0.0;
 }
 moving_object_x_from_input_file= moving_object_y_from_input_file= 0.0; // reset just in case
 while ( -1 < fscanf( file_user_specified_moving_object_position, "%s %f %f", imagefilename_from_input_file, &moving_object_x_from_input_file, &moving_object_y_from_input_file ) ) {
  // Coarse input check
  if ( moving_object_x_from_input_file < 0.0 || moving_object_x_from_input_file > MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK || moving_object_y_from_input_file < 0.0 || moving_object_y_from_input_file > MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
   fprintf( stderr, "WARNING from read_input_file_with_user_specified_moving_object_position(): a problem encountered while parsing vast_input_user_specified_moving_object_position.txt\n" );
   continue;
  }
  //
  for ( i= 0; i < Num; i++ ) {
   if ( 0 == strncmp( input_images[i], imagefilename_from_input_file, FILENAME_LENGTH ) ) {
    moving_object__user_array_x[i]= moving_object_x_from_input_file;
    moving_object__user_array_y[i]= moving_object_y_from_input_file;
    break;
   }
  }
  moving_object_x_from_input_file= moving_object_y_from_input_file= 0.0; // reset just in case
 }

 fclose( file_user_specified_moving_object_position );

 return 0;
}

void ask_user_to_click_on_moving_object( char **input_images, float *moving_object__user_array_x, float *moving_object__user_array_y, int Num ) {

 FILE *file_user_specified_moving_object_position;

 FILE *pipe_for_reading_coordinates_from_sextract_single_image;
 int i;
 char command_string[2 * FILENAME_LENGTH + VAST_PATH_MAX];

 fprintf( stderr, "\n\nPlease mark the moving object on each image.\n\n" );

 for ( i= 0; i < Num; i++ ) {
  fprintf( stderr, "Image: %s\nLeft-click on the moving target then right-click to go to the next image.\n", input_images[i] );
  sprintf( command_string, "./sextract_single_image %s 2>&1 | grep 'Star coordinates' | sed 's/\\x1B\\[[0-9;]\\{1,\\}[A-Za-z]//g' | tail -n1", input_images[i] );
  pipe_for_reading_coordinates_from_sextract_single_image= popen( command_string, "r" );
  if ( 2 != fscanf( pipe_for_reading_coordinates_from_sextract_single_image, "Star coordinates %f %f (pix)", &moving_object__user_array_x[i], &moving_object__user_array_y[i] ) ) {
   fprintf( stderr, "No moving object selected (or failed to parse './sextract_single_image' output)\n" );
   moving_object__user_array_x[i]= moving_object__user_array_y[i]= 0.0;
  }
  if ( moving_object__user_array_x[i] < 0.0 || moving_object__user_array_x[i] > MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
   moving_object__user_array_x[i]= 0.0;
   fprintf( stderr, "No moving object selected (or failed to parse './sextract_single_image' output) (case B)\n" );
  }
  if ( moving_object__user_array_y[i] < 0.0 || moving_object__user_array_y[i] > MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
   moving_object__user_array_y[i]= 0.0;
   fprintf( stderr, "No moving object selected (or failed to parse './sextract_single_image' output) (case C)\n" );
  }
  pclose( pipe_for_reading_coordinates_from_sextract_single_image );
  // fprintf(stderr,"ask_user_to_click_on_moving_object() %f %f\n", moving_object__user_array_x[i], moving_object__user_array_y[i]);
  //  Crash if the moving object is not visible on the reference image
  if ( i == 0 ) {
   if ( moving_object__user_array_x[0] == 0.0 || moving_object__user_array_y[0] == 0.0 ) {
    fprintf( stderr, "ERROR: the user-selected moving object MUST be visible on the reference image!\n" );
    exit( EXIT_FAILURE );
   }
  }
  //
 }

 // Write the log file
 file_user_specified_moving_object_position= fopen( "vast_user_specified_moving_object_position.log", "w" );
 if ( file_user_specified_moving_object_position == NULL ) {
  fprintf( stderr, "ERROR in ask_user_to_click_on_moving_object(): cannot open vast_user_specified_moving_object_position.log for writing!\n" );
  return;
 }
 // Cycle through images and the arrays with the pixel coordinates of the moving target
 for ( i= 0; i < Num; i++ ) {
  fprintf( file_user_specified_moving_object_position, "%s  %7.1f %7.1f\n", input_images[i], moving_object__user_array_x[i], moving_object__user_array_y[i] );
 }
 fclose( file_user_specified_moving_object_position );

 return;
}

int remove_directory( const char *path ) {
 int error= 0;

 // Safety checks for critical directories
 if ( path == NULL || path[0] == '\0' ) {
  fprintf( stderr, "ERROR: Invalid empty path provided\n" );
  return 1;
 }

 // Check for root directory
 if ( strcmp( path, "/" ) == 0 ) {
  fprintf( stderr, "ERROR: Refusing to remove root directory '/'\n" );
  return 1;
 }

 // Check for current or parent directory
 if ( strcmp( path, "." ) == 0 || strcmp( path, ".." ) == 0 ) {
  fprintf( stderr, "ERROR: Refusing to remove '%s' directory\n", path );
  return 1;
 }

 // Simple path checks (without realpath)
 // Check if path contains only / characters
 int slashes_only= 1;
 size_t i;
 for ( i= 0; path[i] != '\0'; i++ ) {
  if ( path[i] != '/' ) {
   slashes_only= 0;
   break;
  }
 }
 if ( slashes_only && i > 0 ) {
  fprintf( stderr, "ERROR: Refusing to remove path containing only slashes\n" );
  return 1;
 }

// Replace recursive approach with iterative one using a stack
#define MAX_DIR_DEPTH 3
 char **dir_stack= malloc( MAX_DIR_DEPTH * sizeof( char * ) );
 int stack_ptr= 0;

 if ( dir_stack == NULL ) {
  fprintf( stderr, "ERROR: Memory allocation failed for directory traversal stack\n" );
  return 1;
 }

 // Add initial path to stack
 dir_stack[stack_ptr]= strdup( path );
 if ( dir_stack[stack_ptr] == NULL ) {
  free( dir_stack );
  return 1;
 }
 stack_ptr++;

 while ( stack_ptr > 0 ) {
  // Pop directory from stack
  stack_ptr--;
  char *curr_path= dir_stack[stack_ptr];

  DIR *d= opendir( curr_path );
  if ( d ) {
   struct dirent *p;
   while ( ( p= readdir( d ) ) ) {
    // Skip "." and ".."
    if ( !strcmp( p->d_name, "." ) || !strcmp( p->d_name, ".." ) )
     continue;

    // Construct full path
    size_t curr_len= strlen( curr_path );
    size_t name_len= strlen( p->d_name );
    size_t path_len= curr_len + name_len + 2; // +2 for '/' and '\0'

    char *full_path= malloc( path_len );
    if ( full_path == NULL ) {
     fprintf( stderr, "ERROR: Memory allocation failed\n" );
     error= 1;
     break;
    }

    /* Handle trailing slash in curr_path */
    if ( curr_len > 0 && curr_path[curr_len - 1] == '/' ) {
     sprintf( full_path, "%s%s", curr_path, p->d_name );
    } else {
     sprintf( full_path, "%s/%s", curr_path, p->d_name );
    }

    struct stat statbuf;
    if ( !stat( full_path, &statbuf ) ) {
     if ( S_ISDIR( statbuf.st_mode ) ) {
      // If directory, add to stack if we haven't reached max depth
      if ( stack_ptr < MAX_DIR_DEPTH ) {
       dir_stack[stack_ptr++]= full_path; // Will process later
      } else {
       fprintf( stderr, "ERROR: Maximum directory depth exceeded\n" );
       free( full_path );
       error= 1;
       break;
      }
     } else {
      // If regular file, remove it
      if ( unlink( full_path ) != 0 ) {
       fprintf( stderr, "ERROR removing file: %s\n", full_path );
       error= 1;
      }
      free( full_path );
     }
    } else {
     // Handle broken symlink case
     if ( !lstat( full_path, &statbuf ) ) {
      unlink( full_path );
     } else {
      fprintf( stderr, "ERROR in remove_directory(): Could not stat: %s\n", full_path );
      error= 1;
     }
     free( full_path );
    }
   }
   closedir( d );

   // Now remove the directory itself
   if ( !error ) {
    if ( rmdir( curr_path ) != 0 ) {
     fprintf( stderr, "ERROR in remove_directory(): Failed to remove directory: %s\n", curr_path );
     error= 1;
    }
   }
  } else {
   fprintf( stderr, "INFO from remove_directory(): Could not open directory: %s\n", curr_path );
   error= 1;
  }

  free( curr_path );
 }

 // Free the stack
 free( dir_stack );

 return error;
}

int find_catalog_in_vast_images_catalogs_log( char *fitsfilename, char *catalogfilename ); // actually it is declared in src/autodetect_aperture.c

void make_sure_libbin_is_in_path(); // actually it is declared in src/autodetect_aperture.c

// This function will try to find the deepest image and set it as the reference one
// by altering the image order in input_images array
void choose_best_reference_image( char **input_images, int *vast_bad_image_flag, int Num ) {
 char sextractor_catalog[FILENAME_LENGTH];
 char copy_input_image_path[FILENAME_LENGTH];
 char sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT];

 int star_number_in_sextractor_catalog, sextractor_flag;
 double flux_adu, flux_adu_err, position_x_pix, position_y_pix, mag, sigma_mag;
 double a_a; // semi-major axis lengths
 double a_a_err;
 double a_b; // semi-minor axis lengths
 double a_b_err;
 float float_parameters[NUMBER_OF_FLOAT_PARAMETERS];

 int external_flag;
 double psf_chi2;

 int i, best_image;

 int previous_star_number_in_sextractor_catalog; // !! to check that the star count in the output catalog is always increasing

 double *number_of_good_detected_stars; // this is double for the simple reason that I want to use the conveinent double functions from GSL (already included for other purposes)
 double *copy_of_number_of_good_detected_stars;
 double median_number_of_good_detected_stars;

 int int_number_of_good_detected_stars;
 double *A_IMAGE;
 double *aperture;
 double best_aperture;

 FILE *file;

 fprintf( stderr, "Trying to automatically select the reference image!\n" );

 if ( Num <= 0 ) {
  fprintf( stderr, "ERROR: Num is too small for choosing best reference image\n" );
  exit( EXIT_FAILURE );
 }

 number_of_good_detected_stars= malloc( Num * sizeof( double ) );
 if ( NULL == number_of_good_detected_stars ) {
  fprintf( stderr, "ERROR in choose_best_reference_image() while allocating memory for number_of_good_detected_stars\n" );
  exit( EXIT_FAILURE );
 }

 aperture= malloc( Num * sizeof( double ) );
 if ( NULL == aperture ) {
  fprintf( stderr, "ERROR in choose_best_reference_image() while allocating memory for aperture\n" );
  exit( EXIT_FAILURE );
 }

 A_IMAGE= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
 if ( NULL == A_IMAGE ) {
  fprintf( stderr, "ERROR in choose_best_reference_image() while allocating memory for A_IMAGE\n" );
  exit( EXIT_FAILURE );
 }

 // Initialize values to make the compiler happy
 for ( i= 0; i < NUMBER_OF_FLOAT_PARAMETERS; i++ ) {
  float_parameters[i]= 0.0;
 }

 for ( i= 0; i < Num; i++ ) {
  // Get the star catalog name from the image name
  if ( 0 != find_catalog_in_vast_images_catalogs_log( input_images[i], sextractor_catalog ) ) {
   fprintf( stderr, "WARNING in choose_best_reference_image(): cannot read the catalog file associated with the image %s\n", input_images[i] );
   number_of_good_detected_stars[i]= 0.0;
   aperture[i]= 0.0;
   continue;
  }
  // count number of detected_stars
  file= fopen( sextractor_catalog, "r" );
  if ( file == NULL ) {
   fprintf( stderr, "WARNING in choose_best_reference_image(): cannot open file %s\n", sextractor_catalog );
   number_of_good_detected_stars[i]= 0.0;
   aperture[i]= 0.0;
   continue;
  }

  previous_star_number_in_sextractor_catalog= 0;
  number_of_good_detected_stars[i]= 0.0;
  aperture[i]= 0.0;
  int_number_of_good_detected_stars= 0;
  while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, file ) ) {
   sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT - 1]= '\0'; // just in case
   external_flag= 0;
   if ( 0 != parse_sextractor_catalog_string( sextractor_catalog_string, &star_number_in_sextractor_catalog, &flux_adu, &flux_adu_err, &mag, &sigma_mag, &position_x_pix, &position_y_pix, &a_a, &a_a_err, &a_b, &a_b_err, &sextractor_flag, &external_flag, &psf_chi2, float_parameters ) ) {
    continue;
   }
   // Read only stars detected at the first FITS image extension.
   // The start of the second image extension will be signified by a jump in star numbering
   if ( star_number_in_sextractor_catalog < previous_star_number_in_sextractor_catalog ) {
    break;
   } else {
    previous_star_number_in_sextractor_catalog= star_number_in_sextractor_catalog;
   }

   // Check if the catalog line is a really band one
   if ( flux_adu <= 0 ) {
    continue;
   }
   if ( flux_adu_err == 999999 ) {
    continue;
   }
   if ( mag == 99.0000 ) {
    continue;
   }
   if ( sigma_mag == 99.0000 ) {
    continue;
   }
   // If we have no error estimates in at least one aperture - assume things are bad with this object
   if ( float_parameters[3] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[5] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[7] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[9] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[11] == 99.0000 ) {
    continue;
   }
//
#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
   if ( mag < BRIGHTEST_STARS ) {
    continue;
   }
   if ( mag > FAINTEST_STARS_ANYMAG ) {
    continue;
   }
   if ( sigma_mag > MAX_MAG_ERROR ) {
    continue;
   }
#endif
   //
   if ( flux_adu < MIN_SNR * flux_adu_err ) {
    continue;
   }
   // Experimental: ount only high-SNR stars
   if ( flux_adu < 20.0 * flux_adu_err ) {
    continue;
   }
   //
   // https://en.wikipedia.org/wiki/Full_width_at_half_maximum
   // ok, I'm not sure if A is the sigma or sigma/2
   if ( SIGMA_TO_FWHM_CONVERSION_FACTOR * ( a_a + a_a_err ) < FWHM_MIN ) {
    continue;
   }
   if ( SIGMA_TO_FWHM_CONVERSION_FACTOR * ( a_b + a_b_err ) < FWHM_MIN ) {
    continue;
   }
   // !!! That doesn't seem to solve the problem
   // float_parameters[0] is the actual FWHM
   if ( float_parameters[0] < 0.0 ) {
    // Faint stars and especially hot pixels tend to have negative FWHM estimate
    continue;
   }
   if ( MAX( float_parameters[0], SIGMA_TO_FWHM_CONVERSION_FACTOR * a_a ) < FWHM_MIN ) {
    continue;
   }
   //
   if ( external_flag != 0 ) {
    continue;
   }
   //
   // just in case we mark objects with really bad SExtractor flags
   if ( sextractor_flag > 7 ) {
    continue;
   }
   A_IMAGE[int_number_of_good_detected_stars]= a_a;
   int_number_of_good_detected_stars++;
  } // while( NULL!=fgets(sextractor_catalog_string,MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT,file) ){

  fclose( file );
  number_of_good_detected_stars[i]= (double)int_number_of_good_detected_stars;
  if ( int_number_of_good_detected_stars < MIN_NUMBER_OF_STARS_ON_FRAME ) {
   // mark as bad image that has too few stars
   aperture[i]= 0.0;
   continue;
  }
  gsl_sort( A_IMAGE, 1, int_number_of_good_detected_stars );
  aperture[i]= CONST * gsl_stats_median_from_sorted_data( A_IMAGE, 1, int_number_of_good_detected_stars );
  fprintf( stderr, "Redetermining aperture for the image %s %.1lfpix\n", input_images[i], aperture[i] );
 }
 free( A_IMAGE );

 // Determine median number of stars on images
 best_image= 0;
 copy_of_number_of_good_detected_stars= malloc( Num * sizeof( double ) );
 if ( NULL == copy_of_number_of_good_detected_stars ) {
  fprintf( stderr, "ERROR allocating memory for copy_of_number_of_good_detected_stars in choose_best_reference_image()\n" );
  exit( EXIT_FAILURE );
 }
 for ( i= 0; i < Num; i++ ) {
  copy_of_number_of_good_detected_stars[i]= number_of_good_detected_stars[i];
 }
 gsl_sort( copy_of_number_of_good_detected_stars, 1, Num );
 median_number_of_good_detected_stars= gsl_stats_median_from_sorted_data( copy_of_number_of_good_detected_stars, 1, Num );
 free( copy_of_number_of_good_detected_stars );
 ///

 fprintf( stderr, "==> median number of good stars %.0lf, max. allowed number of good stars %.0lf = 2*median\n", median_number_of_good_detected_stars, 2.0 * median_number_of_good_detected_stars );

 // Avoid choosing an image with double-detections as the best one
 best_image= 0;
 // best_number_of_good_detected_stars= 0.0;
 best_aperture= 99.0;
 for ( i= 0; i < Num; i++ ) {
  fprintf( stderr, "%4.1lf %5.0lf %d  %s \n", aperture[i], number_of_good_detected_stars[i], vast_bad_image_flag[i], input_images[i] );
  // avoid images that have too many stars
  if ( number_of_good_detected_stars[i] < 2.0 * median_number_of_good_detected_stars ) {
   // avoid images that have too few stars
   if ( number_of_good_detected_stars[i] >= median_number_of_good_detected_stars && number_of_good_detected_stars[i] > 0.0 ) {
    // avoid images that don't have a good aperture estimate
    if ( aperture[i] > 0.0 ) {
     // Make sure the bad image flag is not set for this image
     if ( vast_bad_image_flag[i] == 0 ) {
      // The new way of selecting reference image as the one that has the best seeing
      if ( aperture[i] < best_aperture ) {
       best_image= i;
       best_aperture= aperture[i];
       fprintf( stderr, "new best!\n" );
      }
     }
    }
   }
  }
  // fprintf(stderr,"%lf %s \n",number_of_good_detected_stars[i],input_images[i]);
 }

 // fprintf(stderr,"%lf %s  -- NEW BEST\n",best_number_of_good_detected_stars,input_images[best_image]);

 fprintf( stderr, "\nAutomatically selected %s as the reference image.\n\n", input_images[best_image] );

 free( aperture );

 free( number_of_good_detected_stars );

 // Write-down the name of the new reference image
 file= fopen( "vast_automatically_selected_reference_image.log", "w" );
 if ( file == NULL ) {
  fprintf( stderr, "ERROR in choose_best_reference_image(): cannot open vast_automatically_selected_reference_image.log for writing!\n" );
  return;
 }
 fprintf( file, "%s\n", input_images[best_image] );
 fclose( file );

 // Replace the reference image
 if ( best_image != 0 ) {
  strncpy( copy_input_image_path, input_images[0], FILENAME_LENGTH );
  strncpy( input_images[0], input_images[best_image], FILENAME_LENGTH );
  strncpy( input_images[best_image], copy_input_image_path, FILENAME_LENGTH );
 }

 return;
}

void mark_images_with_elongated_stars_as_bad( char **input_images, int *vast_bad_image_flag, int Num ) {
 char sextractor_catalog[FILENAME_LENGTH];
 char sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT];

 int star_number_in_sextractor_catalog, sextractor_flag;
 double flux_adu, flux_adu_err, position_x_pix, position_y_pix, mag, sigma_mag;
 double a_a; // semi-major axis lengths
 double a_a_err;
 double a_b; // semi-minor axis lengths
 double a_b_err;
 float float_parameters[NUMBER_OF_FLOAT_PARAMETERS];

 int external_flag;
 double psf_chi2;

 int i;

 int previous_star_number_in_sextractor_catalog; // !! to check that the star count in the output catalog is always increasing

 // double *number_of_good_detected_stars; // this is double for the simple reason that I want to use the conveinent double functions from GSL (already included for other purposes)

 int number_of_good_detected_stars;

 //
 // int number_of_stars_current_image;
 double *a_minus_b;
 double *a_minus_b__image;
 double *a_minus_b__image__to_be_runied_by_sort;
 double median_a_minus_b;
 double sigma_from_MAD_a_minus_b;
 //

 double a_minus_b_cutoff_threshold= 0;

 FILE *file;

 fprintf( stderr, "Trying to automatically reject images with elongated stars!\n" );

 if ( Num <= 0 ) {
  fprintf( stderr, "ERROR: Num is too small\n" );
  exit( EXIT_FAILURE );
 }

 if ( Num <= 20 ) {
  fprintf( stderr, "WARNING: Num is too small for identifying images with elongated stars! Will do nothing.\n" );
  return;
 }

 a_minus_b__image= malloc( Num * sizeof( double ) );
 a_minus_b__image__to_be_runied_by_sort= malloc( Num * sizeof( double ) );
 if ( NULL == a_minus_b__image || NULL == a_minus_b__image__to_be_runied_by_sort ) {
  fprintf( stderr, "ERROR allocating memory in mark_images_with_elongated_stars_as_bad()\n" );
  exit( EXIT_FAILURE );
 }

 // Initialize the values to make the compier happy
 for ( i= 0; i < NUMBER_OF_FLOAT_PARAMETERS; i++ ) {
  float_parameters[i]= 0.0;
 }

#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i, a_minus_b, sextractor_catalog, file, previous_star_number_in_sextractor_catalog, number_of_good_detected_stars, sextractor_catalog_string, star_number_in_sextractor_catalog, flux_adu, flux_adu_err, mag, sigma_mag, position_x_pix, position_y_pix, a_a, a_a_err, a_b, a_b_err, sextractor_flag, external_flag, psf_chi2, float_parameters )
#endif
#endif
 for ( i= 0; i < Num; i++ ) {

  // Get the star catalog name from the image name
  if ( 0 != find_catalog_in_vast_images_catalogs_log( input_images[i], sextractor_catalog ) ) {
   fprintf( stderr, "WARNING in mark_images_with_elongated_stars_as_bad(): cannot read the catalog file associated with the image %s\n", input_images[i] );
   a_minus_b__image__to_be_runied_by_sort[i]= a_minus_b__image[i]= -0.1; // is it a good choice?
   continue;
  }
  // count number of detected_stars
  file= fopen( sextractor_catalog, "r" );
  if ( file == NULL ) {
   fprintf( stderr, "WARNING in mark_images_with_elongated_stars_as_bad(): cannot open file %s\n", sextractor_catalog );
   a_minus_b__image__to_be_runied_by_sort[i]= a_minus_b__image[i]= -0.01; // is it a good choice?
   continue;
  }

  a_minus_b= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) );
  if ( a_minus_b == NULL ) {
   fprintf( stderr, "MEMORY ERROR in mark_images_with_elongated_stars_as_bad()\n" );
   exit( EXIT_FAILURE );
  }
  previous_star_number_in_sextractor_catalog= 0;
  number_of_good_detected_stars= 0;
  while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, file ) ) {
   sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT - 1]= '\0'; // just in case
   external_flag= 0;
   if ( 0 != parse_sextractor_catalog_string( sextractor_catalog_string, &star_number_in_sextractor_catalog, &flux_adu, &flux_adu_err, &mag, &sigma_mag, &position_x_pix, &position_y_pix, &a_a, &a_a_err, &a_b, &a_b_err, &sextractor_flag, &external_flag, &psf_chi2, float_parameters ) ) {
    sextractor_catalog_string[0]= '\0'; // just in case
    continue;
   }
   // Read only stars detected at the first FITS image extension.
   // The start of the second image extension will be signified by a jump in star numbering
   if ( star_number_in_sextractor_catalog < previous_star_number_in_sextractor_catalog ) {
    fprintf( stderr, "WARNING in mark_images_with_elongated_stars_as_bad(): this seems to be a multi-extension FITS\n" );
    break;
   } else {
    previous_star_number_in_sextractor_catalog= star_number_in_sextractor_catalog;
   }
   sextractor_catalog_string[0]= '\0'; // just in case

   // Check if the catalog line is a really band one
   if ( flux_adu <= 0 ) {
    continue;
   }
   if ( flux_adu_err == 999999 ) {
    continue;
   }
   if ( mag == 99.0000 ) {
    continue;
   }
   if ( sigma_mag == 99.0000 ) {
    continue;
   }
   // If we have no error estimates in at least one aperture - assume things are bad with this object
   if ( float_parameters[3] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[5] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[7] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[9] == 99.0000 ) {
    continue;
   }
   if ( float_parameters[11] == 99.0000 ) {
    continue;
   }
//
#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
   if ( mag < BRIGHTEST_STARS ) {
    continue;
   }
   if ( mag > FAINTEST_STARS_ANYMAG ) {
    continue;
   }
   if ( sigma_mag > MAX_MAG_ERROR ) {
    continue;
   }
#endif
   //
   if ( flux_adu < MIN_SNR * flux_adu_err ) {
    continue;
   }
   //
   // https://en.wikipedia.org/wiki/Full_width_at_half_maximum
   // ok, I'm not sure if A is the sigma or sigma/2
   if ( SIGMA_TO_FWHM_CONVERSION_FACTOR * ( a_a + a_a_err ) < FWHM_MIN ) {
    continue;
   }
   if ( SIGMA_TO_FWHM_CONVERSION_FACTOR * ( a_b + a_b_err ) < FWHM_MIN ) {
    continue;
   }
   // float_parameters[0] is the actual FWHM
   // if ( float_parameters[0] < FWHM_MIN ) {
   if ( MAX( float_parameters[0], SIGMA_TO_FWHM_CONVERSION_FACTOR * a_a ) < FWHM_MIN ) {
    continue;
   }
   //
   if ( external_flag != 0 ) {
    continue;
   }
   //
   // just in case we mark objects with really bad SExtractor flags
   if ( sextractor_flag > 7 ) {
    continue;
   }
   a_minus_b[number_of_good_detected_stars]= a_a - a_b;
   number_of_good_detected_stars++;
  } // while( NULL!=fgets(sextractor_catalog_string,MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT,file) ){

  fclose( file );

  if ( number_of_good_detected_stars < MIN_NUMBER_OF_STARS_ON_FRAME ) {
   // mark as bad image that has too few stars
   a_minus_b__image__to_be_runied_by_sort[i]= a_minus_b__image[i]= -0.001; // is it a good choice?
   free( a_minus_b );
   continue;
  }
  gsl_sort( a_minus_b, 1, number_of_good_detected_stars );
  a_minus_b__image__to_be_runied_by_sort[i]= a_minus_b__image[i]= gsl_stats_median_from_sorted_data( a_minus_b, 1, number_of_good_detected_stars );
  fprintf( stderr, "median(A-B) for the image %s %.3lfpix\n", input_images[i], a_minus_b__image[i] );

  free( a_minus_b );

 } // for ( i= 0; i < Num; i++ ) { // cycle through the images

 // Determine median a_minus_b among all images
 gsl_sort( a_minus_b__image__to_be_runied_by_sort, 1, Num );
 median_a_minus_b= gsl_stats_median_from_sorted_data( a_minus_b__image__to_be_runied_by_sort, 1, Num );
 sigma_from_MAD_a_minus_b= esimate_sigma_from_MAD_of_sorted_data( a_minus_b__image__to_be_runied_by_sort, (long)Num );
 free( a_minus_b__image__to_be_runied_by_sort );
 // !!! We should consider the possibility that sigma_from_MAD_a_minus_b= 0.0
 // !!! and median_a_minus_b= -0.001

 //
 file= fopen( "vast_accepted_or_rejected_images_based_on_stars_elongation.log", "w" );
 if ( file == NULL ) {
  fprintf( stderr, "ERROR in mark_images_with_elongated_stars_as_bad(): cannot open vast_automatically_selected_reference_image.log for writing!\n" );
  free( a_minus_b__image );
  return;
 }

 // Determine the cut-off threshold
 a_minus_b_cutoff_threshold= 5.0 * MAX( sigma_from_MAD_a_minus_b, 0.05 );
 fprintf( file, "# (A-B) cut-off threshold: %.3lf pix\n", a_minus_b_cutoff_threshold );
 fprintf( stderr, "# (A-B) cut-off threshold: %.3lf pix\n", a_minus_b_cutoff_threshold );

 fprintf( file, "# 0 in the first column means 'below threshold - image accepted'\n" );
 fprintf( stderr, "# 0 in the first column means 'below threshold - image accepted'\n" );
 fprintf( file, "# 1 in the first column means 'above threshold - image rejected'\n" );
 fprintf( stderr, "# 1 in the first column means 'below threshold - image rejected'\n" );

 fprintf( file, "# median(A-B) among all images %.3lf +/-%.3lf pix\n", median_a_minus_b, sigma_from_MAD_a_minus_b );
 fprintf( stderr, "# median(A-B) among all images %.3lf +/-%.3lf pix\n", median_a_minus_b, sigma_from_MAD_a_minus_b );

 // Cycle through all images and mark good and bad ones
 for ( i= 0; i < Num; i++ ) {
  // the image is so bad we could not compute A-B
  // if ( a_minus_b__image[i] == -0.1 ) {
  if ( a_minus_b__image[i] < 0.0 ) {
   vast_bad_image_flag[i]= 1;
   fprintf( file, "%d  %.3lf  %s\n", vast_bad_image_flag[i], a_minus_b__image[i], input_images[i] );
   fprintf( stderr, "%d  %.3lf  %s\n", vast_bad_image_flag[i], a_minus_b__image[i], input_images[i] );
   continue;
  }
  // check if image A-B is too large
  if ( fabs( a_minus_b__image[i] - median_a_minus_b ) > a_minus_b_cutoff_threshold ) {
   vast_bad_image_flag[i]= 2;
   fprintf( file, "%d  %.3lf  %s\n", vast_bad_image_flag[i], a_minus_b__image[i], input_images[i] );
   fprintf( stderr, "%d  %.3lf  %s\n", vast_bad_image_flag[i], a_minus_b__image[i], input_images[i] );
   continue;
  }
  // this image is good
  vast_bad_image_flag[i]= 0;
  fprintf( file, "%d  %.3lf  %s\n", vast_bad_image_flag[i], a_minus_b__image[i], input_images[i] );
  fprintf( stderr, "%d  %.3lf  %s\n", vast_bad_image_flag[i], a_minus_b__image[i], input_images[i] );
 }

 free( a_minus_b__image );

 fclose( file );

 return;
}

//
// This function is useful for debugging. It will create a DS9 region file from an rray of structures (type struct Star)
// containing a list of stars.
//
void write_Star_struct_to_ds9_region_file( struct Star *star, int N_start, int N_stop, char *filename, double aperture ) {
 int i;
 FILE *f;
 f= fopen( filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR in write_Star_struct_to_ds9_region_file() while opening file %s for writing!\n", filename );
  return;
 }
 fprintf( f, "# Region file format: DS9 version 4.0\n" );
 fprintf( f, "# Filename:\n" );
 fprintf( f, "global color=green font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source\n" );
 fprintf( f, "image\n" );
 for ( i= N_start; i < N_stop; i++ ) {
  fprintf( f, "circle(%f,%f,%lf)\n", star[i].x_frame, star[i].y_frame, aperture * 0.5 ); /// 2.0);
 }
 fclose( f );
 return;
}

void write_single_Star_from_struct_to_ds9_region_file( struct Star *star, int N_start, int N_stop, char *filename, double aperture ) {
 int i;
 FILE *f;
 // try to open the file
 f= fopen( filename, "r" );
 if ( f == NULL ) {
  // write header
  f= fopen( filename, "w" );
  if ( NULL == f ) {
   fprintf( stderr, "ERROR in write_single_Star_from_struct_to_ds9_region_file() while opening file %s for writing\n", filename );
   return;
  }
  fprintf( f, "# Region file format: DS9 version 4.0\n" );
  fprintf( f, "# Filename:\n" );
  fprintf( f, "global color=green font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source\n" );
  fprintf( f, "image\n" );
 }
 fclose( f );
 f= fopen( filename, "a" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR in write_single_Star_from_struct_to_ds9_region_file() while opening file %s for addition\n", filename );
  return;
 }
 for ( i= N_start; i < N_stop; i++ ) {
  fprintf( f, "circle(%f,%f,%lf)\n", star[i].x_frame, star[i].y_frame, aperture * 0.5 ); /// 2.0);
 }
 fclose( f );
 return;
}

/*
 This function is useful for debugging.
 */
void write_Star_struct_to_ASCII_file( struct Star *star, int N_start, int N_stop, char *filename, double aperture ) {
 int i;
 FILE *f;
 f= fopen( filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR in write_Star_struct_to_ASCII_file() while opening file %s for writing\n", filename );
  return;
 }
 for ( i= N_start; i < N_stop; i++ ) {
  fprintf( f, "%f  %f   %lf\n", star[i].x, star[i].y, aperture * 0.5 ); /// 2.0);
 }
 fclose( f );
 return;
}

//
// Get the compiler version, just for the sake of bookkeeping...
//
void compiler_version( char *compiler_version_string ) {
 FILE *cc_version_file;
 cc_version_file= fopen( ".cc.version", "r" );
 if ( NULL == cc_version_file ) {
  strncpy( compiler_version_string, "unknown compiler\n", 18 );
  return;
 }
 if ( NULL == fgets( compiler_version_string, 256, cc_version_file ) ) {
  strncpy( compiler_version_string, "unknown compiler\n", 18 );
 }
 fclose( cc_version_file );
 return;
}

void compilation_date( char *compilation_date_string ) {
 FILE *cc_version_file;
 cc_version_file= fopen( ".cc.date", "r" );
 if ( NULL == cc_version_file ) {
  strncpy( compilation_date_string, "unknown date\n", 18 );
  return;
 }
 if ( NULL == fgets( compilation_date_string, 256, cc_version_file ) ) {
  strncpy( compilation_date_string, "unknown date\n", 18 );
 }
 fclose( cc_version_file );
 return;
}

void vast_build_number( char *vast_build_number_string ) {
 FILE *cc_version_file;
 cc_version_file= fopen( ".cc.build", "r" );
 if ( NULL == cc_version_file ) {
  strncpy( vast_build_number_string, "unknown\n", 18 );
  return;
 }
 if ( NULL == fgets( vast_build_number_string, 256, cc_version_file ) ) {
  strncpy( vast_build_number_string, "unknown\n", 18 );
 }
 fclose( cc_version_file );
 return;
}

void vast_is_openmp_enabled( char *vast_openmp_enabled_string ) {
 FILE *cc_version_file;
 cc_version_file= fopen( ".cc.openmp", "r" );
 if ( NULL == cc_version_file ) {
  strncpy( vast_openmp_enabled_string, "unknown\n", 18 );
  return;
 }
 if ( NULL == fgets( vast_openmp_enabled_string, 256, cc_version_file ) ) {
  strncpy( vast_openmp_enabled_string, "unknown\n", 18 );
 }
 fclose( cc_version_file );
 return;
}

/* is_file() - a small function which checks is an input string is a name of a readable file
int is_file( char *filename ) {
 FILE *f= NULL;
 f= fopen( filename, "r" );
 if ( f == NULL )
  return 0;
 else {
  fclose( f );
  return 1;
 }
}
*/

/*
   This function will write vast_images_catalogs.log file
*/
void write_images_catalogs_logfile( char **filelist, int n ) {
 FILE *f;
 int i;
 f= fopen( "vast_images_catalogs.log", "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR in write_images_catalogs_logfile() while opening file %s for writing\n", "vast_images_catalogs.log" );
  return;
 }
 for ( i= 0; i < n; i++ ) {
  fprintf( f, "image%05d.cat %s\n", i + 1, filelist[i] );
 }
 fclose( f );
 return;
}

/* Write data on magnitude calibration to the log file */
void write_magnitude_calibration_log( double *mag1, double *mag2, double *mag_err, int N, char *fitsimagename ) {
 char logfilename[FILENAME_LENGTH];
 FILE *logfile;
 int i;
 strncpy( logfilename, basename( fitsimagename ), FILENAME_LENGTH );
 logfilename[FILENAME_LENGTH - 1]= '\0';
 for ( i= (int)strlen( logfilename ) - 1; i--; ) {
  if ( logfilename[i] == '.' ) {
   logfilename[i]= '\0';
   break;
  }
 }
 strcat( logfilename, ".calib" );
 logfile= fopen( logfilename, "w" );
 if ( NULL == logfile ) {
  fprintf( stderr, "WARNING: can't open %s for writing!\n", logfilename );
  return;
 }
 for ( i= 0; i < N; i++ ) {
  fprintf( logfile, "%8.4lf %8.4lf %.4lf\n", mag1[i], mag2[i], mag_err[i] );
 }
 fclose( logfile );
 fprintf( stderr, "Using %d stars for magnitude calibration (before filtering).\n", N );
 return;
}

void write_magnitude_calibration_log2( double *mag1, double *mag2, double *mag_err, int N, char *fitsimagename ) {
 // Calculate the size of dest, minus the null terminator, to ensure
 // that it is large enough to hold the concatenated string
 size_t dest_size= FILENAME_LENGTH - 1;

 char logfilename[FILENAME_LENGTH];
 FILE *logfile;
 int i;
 strncpy( logfilename, basename( fitsimagename ), FILENAME_LENGTH );
 logfilename[FILENAME_LENGTH - 1]= '\0';
 for ( i= (int)strlen( logfilename ) - 1; i--; ) {
  if ( logfilename[i] == '.' ) {
   logfilename[i]= '\0';
   break;
  }
 }
 // strcat(logfilename, ".calib2");
 strncat( logfilename, ".calib2", dest_size - strlen( logfilename ) );

 logfile= fopen( logfilename, "w" );
 if ( NULL == logfile ) {
  fprintf( stderr, "WARNING: can't open %s for writing!\n", logfilename );
  return;
 }
 for ( i= 0; i < N; i++ ) {
  fprintf( logfile, "%8.4lf %8.4lf %.4lf\n", mag1[i], mag2[i], mag_err[i] );
 }
 fclose( logfile );
 fprintf( stderr, "After removing outliers in (X,Y,dm) plane, we are left with %d stars for magnitude calibration.\n", N );
 return;
}

void write_magnitude_calibration_log_plane( double *mag1, double *mag2, double *mag_err, int N, char *fitsimagename, double A, double B, double C ) {
 // Calculate the size of dest, minus the null terminator, to ensure
 // that it is large enough to hold the concatenated string
 size_t dest_size= FILENAME_LENGTH - 1;

 char logfilename[FILENAME_LENGTH];
 FILE *logfile;
 int i;
 if ( strlen( fitsimagename ) < 1 ) {
  fprintf( stderr, "WARNING from write_magnitude_calibration_log_plane(): cannot get FITS image filename!\n" );
  return;
 }
 strncpy( logfilename, basename( fitsimagename ), FILENAME_LENGTH );
 logfilename[FILENAME_LENGTH - 1]= '\0';
 for ( i= (int)strlen( logfilename ) - 1; i--; ) {
  if ( logfilename[i] == '.' ) {
   logfilename[i]= '\0';
   break;
  }
 }
 // strcat(logfilename, ".calib_plane");
 strncat( logfilename, ".calib_plane", dest_size - strlen( logfilename ) );

 logfile= fopen( logfilename, "w" );
 if ( NULL == logfile ) {
  fprintf( stderr, "WARNING: can't open %s for writing!\n", logfilename );
  return;
 }
 for ( i= 0; i < N; i++ ) {
  fprintf( logfile, "%8.4lf %8.4lf %.4lf\n", mag1[i], mag2[i], mag_err[i] );
 }
 fclose( logfile );
 // strcat(logfilename, ".calib_plane_param");
 strncat( logfilename, ".calib_plane_param", dest_size - strlen( logfilename ) );
 logfile= fopen( logfilename, "w" );
 if ( NULL == logfile ) {
  fprintf( stderr, "WARNING: can't open %s for writing!\n", logfilename );
  return;
 }
 fprintf( logfile, "%lf %lf %lf\n", A, B, C );
 fclose( logfile );
 return;
}

// Write parameters of magnitude calibration to another log file
void write_magnitude_calibration_param_log( double *poly_coeff, char *fitsimagename ) {
 // Calculate the size of dest, minus the null terminator, to ensure
 // that it is large enough to hold the concatenated string
 size_t dest_size= FILENAME_LENGTH - 1;

 char logfilename[FILENAME_LENGTH];
 FILE *logfile;
 int i;
 strncpy( logfilename, basename( fitsimagename ), FILENAME_LENGTH );
 logfilename[FILENAME_LENGTH - 1]= '\0';
 for ( i= (int)strlen( logfilename ) - 1; i--; ) {
  if ( logfilename[i] == '.' ) {
   logfilename[i]= '\0';
   break;
  }
 }
 // strncat(logfilename, ".calib_param", FILENAME_LENGTH - 32);
 strncat( logfilename, ".calib_param", dest_size - strlen( logfilename ) );
 logfilename[FILENAME_LENGTH - 1]= '\0';
 logfile= fopen( logfilename, "w" );
 if ( NULL == logfile ) {
  fprintf( stderr, "WARNING: can't open %s for writing!\n", logfilename );
  return;
 }
 fprintf( logfile, "%lf %lf %lf %lf %lf\n", poly_coeff[4], poly_coeff[3], poly_coeff[2], poly_coeff[1], poly_coeff[0] );
 fclose( logfile );
 return;
}

// New memory check - try to allocate lots of space
int check_if_we_can_allocate_lots_of_memory() {
 char *big_chunk_of_memory;
 big_chunk_of_memory= malloc( 134217728 * sizeof( char ) ); // try to allocate 128MB
 if ( NULL == big_chunk_of_memory ) {
  fprintf( stderr, "WARNING: the system is low on memory!\n" );
  return 1;
 }
 free( big_chunk_of_memory );
 return 0;
}

// Memory check
int check_and_print_memory_statistics() {

 FILE *meminfofile;
 char string1[256 + 256]; // should be big enough to accomodate string2
 char string2[256];
 double VmPeak= 0.0;
 char VmPeak_units[256];
 double VmSize= 0.0;
 char VmSize_units[256];
 double RAM_size= 0.0;
 char RAM_size_units[256];
 double mem= 0.0;
 pid_t pid;
 pid= getpid();

 // Check if process status information is available in /proc
 sprintf( string2, "/proc/%d/status", pid );
 if ( 0 == is_file( string2 ) ) {
  // This means we are probably on a BSD-like system

  // Trying to handle the BSD/Mac case in a rudimentary way
  //
  // Why don't I want to handle the low-memory-system case on Linux in a similar way?
  // For no good reason, really.
  //
  sprintf( string1, "sysctl -n hw.physmem > vast_memory_usage.log" );
  if ( 0 != system( string1 ) ) {
   sprintf( string1, "sysctl -n hw.memsize > vast_memory_usage.log" );
   if ( 0 != system( string1 ) ) {
    fprintf( stderr, "ERROR running  sysctl -n hw.memsize > vast_memory_usage.log\n" );
    return 0;
   }
  }
  meminfofile= fopen( "vast_memory_usage.log", "r" );
  if ( meminfofile == NULL ) {
   fprintf( stderr, "can't open vast_memory_usage.log, no memory statistics available\n" );
   return 0;
  }
  if ( 1 != fscanf( meminfofile, "%lf", &mem ) ) {
   fprintf( stderr, "ERROR parsing vast_memory_usage.log, no memory statistics available\n" );
   fclose( meminfofile );
   return 0;
  }
  fclose( meminfofile );
  if ( mem < 0.0 ) {
   fprintf( stderr, "ERROR parsing vast_memory_usage.log, no memory statistics available\n" );
   return 0;
  }
  // if we are on BSD or Mac and we are under 1GB of RAM - assume we are short on memory
  if ( mem < 1073741824.0 ) {
   fprintf( stderr, "WARNING: the system seems to have less than 1GB of RAM. Assuming we are short on memory.\n" );
   return 1;
  }
  // fprintf(stderr,"can't read %s   no memory statistics available\n",string2);
  return 0;
 } else {
  // Get ammount of used memory from /proc/PID/status
  sprintf( string1, "grep -B1 VmSize %s | grep -v Groups | sed 's/\\t/ /g' > vast_memory_usage.log", string2 );
  if ( 0 != system( string1 ) ) {
   fprintf( stderr, "ERROR running  %s\n", string1 );
   return 0;
  }

  // Check if memory information is available in /proc
  if ( 0 == is_file( "/proc/meminfo" ) ) {
   fprintf( stderr, "can't read /proc/meminfo   no memory statistics available\n" );
   return 0;
  }

  // Get RAM size
  sprintf( string1, "grep MemTotal /proc/meminfo | sed 's/\\t/ /g' >> vast_memory_usage.log" );
  if ( 0 != system( string1 ) ) {
   fprintf( stderr, "ERROR running  %s\n", string1 );
   return 0;
  }

  // Load memory information from the log file
  meminfofile= fopen( "vast_memory_usage.log", "r" );
  if ( meminfofile == NULL ) {
   fprintf( stderr, "can't open vast_memory_usage.log, no memory statistics available\n" );
   return 0;
  }
  if ( 3 != fscanf( meminfofile, "%s %lf %s ", string1, &mem, string2 ) ) {
   fprintf( stderr, "no memory statistics available\n" );
   return 0;
  }
  if ( 0 == strcasecmp( string1, "VmPeak:" ) ) {
   VmPeak= mem;
   strncpy( VmPeak_units, string2, 256 - 1 );
  }
  if ( 0 == strcasecmp( string1, "VmSize:" ) ) {
   VmSize= mem;
   strncpy( VmSize_units, string2, 256 - 1 );
  }
  if ( 0 == strcasecmp( string1, "MemTotal:" ) ) {
   RAM_size= mem;
   strncpy( RAM_size_units, string2, 256 - 1 );
  }
  if ( 3 == fscanf( meminfofile, "%s %lf %s ", string1, &mem, string2 ) ) {
   if ( 0 == strcasecmp( string1, "VmPeak:" ) ) {
    VmPeak= mem;
    strncpy( VmPeak_units, string2, 256 - 1 );
   }
   if ( 0 == strcasecmp( string1, "VmSize:" ) ) {
    VmSize= mem;
    strncpy( VmSize_units, string2, 256 - 1 );
   }
   if ( 0 == strcasecmp( string1, "MemTotal:" ) ) {
    RAM_size= mem;
    strncpy( RAM_size_units, string2, 256 - 1 );
   }
   if ( 3 == fscanf( meminfofile, "%s %lf %s ", string1, &mem, string2 ) ) {
    if ( 0 == strcasecmp( string1, "VmPeak:" ) ) {
     VmPeak= mem;
     strncpy( VmPeak_units, string2, 256 - 1 );
    }
    if ( 0 == strcasecmp( string1, "VmSize:" ) ) {
     VmSize= mem;
     strncpy( VmSize_units, string2, 256 - 1 );
    }
    if ( 0 == strcasecmp( string1, "MemTotal:" ) ) {
     RAM_size= mem;
     strncpy( RAM_size_units, string2, 256 - 1 );
    }
   }
  }
  fclose( meminfofile );

  // Write information about memory usage
  fprintf( stderr, "memory: " );
  if ( 0.0 != VmSize )
   fprintf( stderr, " %.0lf %s used", VmSize, VmSize_units );
  if ( 0.0 != VmPeak )
   fprintf( stderr, ", %.0lf %s peak", VmPeak, VmPeak_units );
  if ( 0.0 != RAM_size )
   fprintf( stderr, ", %.0lf %s available RAM", RAM_size, RAM_size_units );
  fprintf( stderr, "\n" );

  // If RAM and VmSize were correctly read and are in the same units...
  if ( 0 == strcasecmp( VmSize_units, RAM_size_units ) && 0 != VmSize && 0 != RAM_size ) {
   // Check that the data are reasonable
   if ( VmSize > 100 * RAM_size ) {
    fprintf( stderr, "\x1B[01;31mWARNING! There seems to be a problem parsing the memory usage statistic.\x1B[33;00m\n" );
   } else {
    // Check aren't we using too much memory?
    if ( VmSize > MAX_RAM_USAGE * RAM_size ) {
     fprintf( stderr, "\x1B[01;31mWARNING! VaST is using more than %d%% of RAM! Trying to free some memory...\x1B[33;00m\n", (int)( MAX_RAM_USAGE * 100 ) );
     return 1; // return value 1 means that we need to free some momory
    }
   }
  }

 } // else -- if( 0==is_file(string2) ){

 if ( 0 != check_if_we_can_allocate_lots_of_memory() ) {
  return 1;
 }

 return 0;
}

// progress(int done, int all) - print out progress status, how many images were sextracted
void progress( int done, int all ) {
 fprintf( stderr, "processed %d of %d images (%5.1lf%%)\n", done, all, (double)done / (double)all * 100.0 );
 return;
}

// save_command_line_to_log_file(int argc, char **argv) - save command line arguments to the log file vast_command_line.log
void save_command_line_to_log_file( int argc, char **argv ) {
 int i;
 FILE *cmdlogfile;
 cmdlogfile= fopen( "vast_command_line.log", "w" );
 if ( NULL == cmdlogfile ) {
  fprintf( stderr, "ERROR: cannot open vast_command_line.log for writing - something is very wrong.\n" );
  return;
 }
 // Print to the terminal in addition to the log file
 fprintf( stderr, "\n VaST was started with the following command line: \n" );
 for ( i= 0; i < argc; i++ ) {
  fprintf( cmdlogfile, "%s ", argv[i] ); // log file
  fprintf( stderr, "%s ", argv[i] );     // terminal
 }
 fclose( cmdlogfile );
 fprintf( stderr, "\n\n" );
}

// TODO: replace with memove
// a housekeeping function to exclude i'th element from three arrays
void exclude_from_3_double_arrays( double *array1, double *array2, double *array3, int i, int *N ) {
 int j;
 if ( i < 0 || i >= ( *N ) ) {
  fprintf( stderr, "ERROR in exclude_from_3_double_arrays(): i=%d\n", i );
  return;
 }
 for ( j= i; j < ( *N ) - 1; j++ ) {
  array1[j]= array1[j + 1];
  array2[j]= array2[j + 1];
  array3[j]= array3[j + 1];
 }
 ( *N )= ( *N ) - 1;
 return;
}
// a housekeeping function to exclude i'th element from six arrays
void exclude_from_6_double_arrays( double *array1, double *array2, double *array3, double *array4, double *array5, double *array6, int i, int *N ) {
 int j;
 if ( i < 0 || i >= ( *N ) ) {
  fprintf( stderr, "ERROR in exclude_from_6_double_arrays(): i=%d\n", i );
  return;
 }
 for ( j= i; j < ( *N ) - 1; j++ ) {
  array1[j]= array1[j + 1];
  array2[j]= array2[j + 1];
  array3[j]= array3[j + 1];
  array4[j]= array4[j + 1];
  array5[j]= array5[j + 1];
  array6[j]= array6[j + 1];
 }
 ( *N )= ( *N ) - 1;
 return;
}

// Auxialiary function for magnitude calibration
void drop_one_point_that_changes_fit_the_most( double *poly_x_external, double *poly_y_external, double *poly_err_external, int *N_good_stars_external, int photometric_calibration_type, int param_use_photocurve ) {
 int param_use_photocurve_local_copy;
 double poly_coeff_local_copy[10];
 double chi2;
 double chi2_best;
 int i;
 int i_drop;
 int i_drop_best= -1;
 int N_good_stars;
 int wpolyfit_exit_code;

 double *poly_x;
 double *poly_y;
 double *poly_err;

 // do nothing if we have too few points
 if ( ( *N_good_stars_external ) < 4 ) {
  fprintf( stderr, "Error: too few points for drop_one_point_that_changes_fit_the_most()\n" );
  return;
 }

 // for(i_drop=0;i_drop<(*N_good_stars_external);i_drop++){
 for ( i_drop= -1; i_drop < 10; i_drop++ ) {

  N_good_stars= ( *N_good_stars_external );
  if ( N_good_stars <= 0 ) {
   fprintf( stderr, "Error: no good stars for magnitude calibration\n" );
   // exit( EXIT_FAILURE ); // I don't want to crash here
  }
  poly_x= (double *)malloc( N_good_stars * sizeof( double ) );
  if ( poly_x == NULL ) {
   fprintf( stderr, "ERROR in drop_one_point_that_changes_fit_the_most(): can't allocate memory for magnitude calibration!\n" );
   vast_report_memory_error();
   return;
  }
  poly_y= (double *)malloc( N_good_stars * sizeof( double ) );
  if ( poly_y == NULL ) {
   fprintf( stderr, "ERROR in drop_one_point_that_changes_fit_the_most(): can't allocate memory for magnitude calibration!\n" );
   vast_report_memory_error();
   free( poly_x );
   return;
  }
  poly_err= (double *)malloc( N_good_stars * sizeof( double ) );
  if ( poly_err == NULL ) {
   fprintf( stderr, "ERROR in drop_one_point_that_changes_fit_the_most(): can't allocate memory for magnitude calibration!\n" );
   vast_report_memory_error();
   free( poly_x );
   free( poly_y );
   return;
  }

  // Initialize the array
  // to be replaced with memcpy
  for ( i= 0; i < ( *N_good_stars_external ); i++ ) {
   poly_x[i]= poly_x_external[i];
   poly_y[i]= poly_y_external[i];
   poly_err[i]= poly_err_external[i];
  }

  if ( i_drop >= 0 ) {
   exclude_from_3_double_arrays( poly_x, poly_y, poly_err, i_drop, &N_good_stars );
  }

  // Fit thr function and get chi2
  if ( param_use_photocurve != 0 ) {
   wpolyfit_exit_code= fit_photocurve( poly_x, poly_y, poly_err, N_good_stars, poly_coeff_local_copy, &param_use_photocurve_local_copy, &chi2 );
  } else {
   if ( photometric_calibration_type == 0 ) {
    wpolyfit_exit_code= wlinearfit( poly_x, poly_y, poly_err, N_good_stars, poly_coeff_local_copy, &chi2 );
   } else {
    wpolyfit_exit_code= wpolyfit( poly_x, poly_y, poly_err, N_good_stars, poly_coeff_local_copy, &chi2 );
   }
  } // if( param_use_photocurve!=0 ){

  free( poly_err );
  free( poly_y );
  free( poly_x );

  if ( i_drop == -1 ) {
   chi2_best= chi2;
   continue;
  }
  if ( wpolyfit_exit_code != 0 ) {
   continue;
  }
  if ( chi2 <= chi2_best ) {
   chi2_best= chi2;
   i_drop_best= i_drop;
   // fprintf(stderr,"DEBUG drop_one_point_that_changes_fit_the_most(): excluding the star %d  %lf %lf %lf chi2_best=%lf\n",i_drop_best,poly_x_external[i_drop],poly_y_external[i_drop],poly_err_external[i_drop],chi2_best);
  }

 } // for(i_drop=0;i_drop<(*N_good_stars_external);i_drop++){

 // Apply the result
 exclude_from_3_double_arrays( poly_x_external, poly_y_external, poly_err_external, i_drop_best, N_good_stars_external );

 return;
}

// This function writes a string to an image log file.
// vast_image_details.log will be created from image log files later...
void write_string_to_log_file( char *log_string, char *sextractor_catalog ) {
 FILE *vast_image_details;
 char vast_image_details_log_filename[256];
 int i;
 // Guess the log file name
 strncpy( vast_image_details_log_filename, sextractor_catalog, 256 - 1 );
 for ( i= (int)strlen( vast_image_details_log_filename ); i--; ) {
  if ( vast_image_details_log_filename[i] == '.' ) {
   vast_image_details_log_filename[i + 1]= 'l';
   vast_image_details_log_filename[i + 2]= 'o';
   vast_image_details_log_filename[i + 3]= 'g';
   break;
  }
 }
 // Write the string
 vast_image_details= fopen( vast_image_details_log_filename, "a" );
 if ( vast_image_details == NULL ) {
  fprintf( stderr, "ERROR appending line \"%s\" to log file \"%s\"\n", log_string, vast_image_details_log_filename );
  return;
 }
 fprintf( vast_image_details, "%s", log_string );
 fclose( vast_image_details );
 write_string_to_individual_image_log( sextractor_catalog, "write_string_to_log_file(): ", log_string, "" );
 return;
}

// The function is used to find a star specified with its pixel coordinates
// in a list of stars (with their X Y coordinates listed in two arrays).
//
// The function is used both for the exclusion test and for finding
// the manually selected comparison stars.
//
// Return values:
//                -1 - not found
//                 0, 1, 2... - index of the found star
int exclude_test( double X, double Y, double *exX, double *exY, int N, int verbose ) {
 int result= -1;
 int i;
 for ( i= 0; i < N; i++ ) {
  // for ( i= N; i--; ) {
  if ( fabs( exX[i] - X ) < 1.5 && fabs( exY[i] - Y ) < 1.5 ) {
   result= i;
   break;
  }
 }
 if ( result > -1 ) {
  if ( verbose != 0 ) {
   fprintf( stderr, "The star %.3lf %.3lf is listed in exclude.lst => excluded from magnitude calibration\n", X, Y );
  }
 }
 return result;
}

// Transients are objects which were not detected on the reference frame but have now suddenly appeared.
void test_transient( double *search_area_boundaries, struct Star star, double reference_image_JD, double X_im_size, double Y_im_size, double *X1, double *Y1, double *X2, double *Y2, int N_bad_regions, double aperture ) {
 FILE *transientfile;
 int n= star.n;
 double x= star.x;
 double y= star.y;
 double m= star.mag;
 double m_err= star.sigma_mag;

 // Test if the time difference between the reference and the current image is >TRANSIENT_MIN_TIMESCALE_DAYS
 if ( fabs( star.JD - reference_image_JD ) < TRANSIENT_MIN_TIMESCALE_DAYS ) {
  return;
 }
 // if( star.n==4511 )fprintf(stderr,"##### %lf %lf\n",star.JD,reference_image_JD);
 // if( star.n==21841 )fprintf(stderr,"##### %lf %lf\n",star.JD,reference_image_JD);

 if ( x > search_area_boundaries[0] && x < search_area_boundaries[1] ) {
  if ( y > search_area_boundaries[2] && y < search_area_boundaries[3] ) {
   // we check that the transient is brighter than the faint limit
   // don't care if it's fainter or brighter thant the bright search box limits
   // if ( m + 1.0 * m_err < search_area_boundaries[5] ) {
   if ( m + 0.0 * m_err < search_area_boundaries[5] ) {
    // The candidate is inside the search box - now make additional (slow) checks
    // if ( 1 == is_point_close_or_off_the_frame_edge( star.x_frame, star.y_frame, X_im_size, Y_im_size, 3 * FRAME_EDGE_INDENT_PIXELS ) ) {
    if ( 1 == is_point_close_or_off_the_frame_edge( star.x_frame, star.y_frame, X_im_size, Y_im_size, FRAME_EDGE_INDENT_PIXELS ) ) {
     return;
    }
    // if( star.n==21841 )fprintf(stderr,"##### star.n==21841  -- passed is_point_close_or_off_the_frame_edge()\n");
    //  double-check that it's not in a bad region
    if ( 0 != exclude_region( X1, Y1, X2, Y2, N_bad_regions, star.x_frame, star.y_frame, aperture ) ) {
     fprintf( stderr, "The transient candidate %9.3lf %9.3lf is rejected, see bad_region.lst\n", star.x_frame, star.y_frame );
     return;
    }
    // if( star.n==21841 )fprintf(stderr,"##### star.n==21841  -- passed exclude_region() new frame\n");
    //  Check that it's not in a bad region on the reference frame - there will be no reference object!
    //  increase the bad region, just in case
    if ( 0 != exclude_region( X1, Y1, X2, Y2, N_bad_regions, x, y, 1.5 * aperture ) ) {
     fprintf( stderr, "The transient candidate (new frame position %9.3lf %9.3lf ; ref frame position: %9.3lf %9.3lf) is rejected as at the reference frame it would land at a bad region listed in bad_region.lst\n", star.x_frame, star.y_frame, x, y );
     return;
    }
    // if( star.n==21841 )fprintf(stderr,"##### star.n==21841  -- passed exclude_region() ref frame\n");
    //  OK, we like this candidate
    // if( star.n==21841 )fprintf(stderr,"##### star.n==21841  -- we like it\n");
    transientfile= fopen( "candidates-transients.lst", "a" );
    if ( NULL == transientfile ) {
     fprintf( stderr, "ERROR writing to candidates-transients.lst\n" );
     return;
    }
    fprintf( transientfile, "out%05d.dat  %8.3lf %8.3lf\n", n, x, y );
    fclose( transientfile );
   }
  }
 }
 return;
}

int compare( const double *a, const double *b ) {
 if ( *a < *b )
  return -1;
 else if ( *a > *b )
  return 1;
 else
  return 0;
}

void set_transient_search_boundaries( double *search_area_boundaries, struct Star *star, int NUMBER, double X_im_size, double Y_im_size ) {

 double *detection_limit_from_snr__mag_array;
 double *detection_limit_from_snr__snr_array;
 int detection_limit_from_snr__success;

 double detection_limit_derived_from_snr= 99.9;
 double detection_limit_80percent_of_stars= 99.9;

 int i;
 double *filtered_mag_values;
 int filtered_count= 0;

 search_area_boundaries[0]= search_area_boundaries[1]= search_area_boundaries[2]= search_area_boundaries[3]= FRAME_EDGE_INDENT_PIXELS;
 search_area_boundaries[4]= search_area_boundaries[5]= (double)star[0].mag;

 filtered_mag_values= (double *)malloc( NUMBER * sizeof( double ) );
 if ( NULL == filtered_mag_values ) {
  fprintf( stderr, "ERROR allocating memory for filtered_mag_values in set_transient_search_boundaries()\n" );
  exit( EXIT_FAILURE );
 }

 for ( i= NUMBER; i--; ) {
  if ( star[i].sextractor_flag > 7 )
   continue;
  if ( star[i].vast_flag != 0 )
   continue;
  if ( star[i].mag != 0.0 ) { // just in case
   // Make sure a star defining the search area is not too close to image edge
   if ( 1 == is_point_close_or_off_the_frame_edge( (double)star[i].x, (double)star[i].y, X_im_size, Y_im_size, FRAME_EDGE_INDENT_PIXELS ) )
    continue;
   //
   if ( (double)star[i].x < search_area_boundaries[0] )
    search_area_boundaries[0]= (double)star[i].x;
   if ( (double)star[i].x > search_area_boundaries[1] )
    search_area_boundaries[1]= (double)star[i].x;
   if ( (double)star[i].y < search_area_boundaries[2] )
    search_area_boundaries[2]= (double)star[i].y;
   if ( (double)star[i].y > search_area_boundaries[3] )
    search_area_boundaries[3]= (double)star[i].y;
   if ( (double)star[i].mag < search_area_boundaries[4] )
    search_area_boundaries[4]= (double)star[i].mag;

   filtered_mag_values[filtered_count++]= (double)star[i].mag;
  }
 }

 if ( filtered_count <= 0 ) {
  fprintf( stderr, "ERROR determining the transient search bondaries - no stars pass the filtering!\n" );
  exit( EXIT_FAILURE );
 }

 // Here is a short discussion on how the normal people estimate limiting magnitude of an image
 // https://www.cadc-ccda.hia-iha.nrc-cnrc.gc.ca/en/megapipe/docs/photo.html
 //
 // I also like the approach of Sergey Karpov: https://ui.adsabs.harvard.edu/abs/2024arXiv241116470K/abstract
 // see src/detection_limit.c
 //

 // Mag limit from SNR-magnitude relation following Karpov'24
 //
 //
 detection_limit_from_snr__mag_array= malloc( NUMBER * sizeof( double ) );
 if ( NULL == detection_limit_from_snr__mag_array ) {
  fprintf( stderr, "ERROR: allocating memory for detection_limit_from_snr__mag_array\n" );
  exit( EXIT_FAILURE );
 }

 detection_limit_from_snr__snr_array= malloc( NUMBER * sizeof( double ) );
 if ( NULL == detection_limit_from_snr__snr_array ) {
  fprintf( stderr, "ERROR: allocating memory for detection_limit_from_snr__snr_array\n" );
  exit( EXIT_FAILURE );
 }

 extract_mag_and_snr_from_structStar( star, (size_t)NUMBER, detection_limit_from_snr__mag_array, detection_limit_from_snr__snr_array );
 detection_limit_derived_from_snr= get_detection_limit_sn( detection_limit_from_snr__mag_array, detection_limit_from_snr__snr_array, (size_t)NUMBER, MIN_SNR, &detection_limit_from_snr__success );
 // fprintf(stderr,"DEBUG: detection_limit_from_snr__success= %d  GSL_SUCCESS= %d\n", detection_limit_from_snr__success,GSL_SUCCESS);

 free( detection_limit_from_snr__mag_array );
 free( detection_limit_from_snr__snr_array );

 if ( GSL_SUCCESS != detection_limit_from_snr__success ) {
  fprintf( stderr, "WARNING: failed to determine magnitude limit from the magnitude-SNR relation! Falling back to the 80 percent brighter stars limit.\n" );
 } else {
  fprintf( stderr, "Detection limit from the magnitude-SNR relation= %.1lf  (%.1lf sigma detection)\n", detection_limit_derived_from_snr, MIN_SNR );
 }

 // Mag limit above which are 80% of the detected stars
 // Sort the filtered_mag_values array and get the value that is 20% from the largest value
 qsort( filtered_mag_values, filtered_count, sizeof( double ), (int ( * )( const void *, const void * ))compare );
 detection_limit_80percent_of_stars= filtered_mag_values[(int)( 0.80 * (double)filtered_count )]; // 20% from the end
 fprintf( stderr, "The simple faintest star detection limit= %.1lf\n", filtered_mag_values[filtered_count - 1] );
 fprintf( stderr, "80 percent brightest stars detection limit= %.1lf\n", detection_limit_80percent_of_stars );

 // Under normal circumstances detection_limit_80percent_of_stars << detection_limit_derived_from_snr
 search_area_boundaries[5]= MIN( detection_limit_derived_from_snr, detection_limit_80percent_of_stars );
 fprintf( stderr, "Selected detection limit= %.1lf\n", search_area_boundaries[5] );

 search_area_boundaries[5]= search_area_boundaries[5] - MAG_TRANSIENT_ABOVE_THE_REFERENCE_FRAME_LIMIT;
 fprintf( stderr, "Final detection limit= %.1lf (after subtracting MAG_TRANSIENT_ABOVE_THE_REFERENCE_FRAME_LIMIT=%.1lf)\n", search_area_boundaries[5], MAG_TRANSIENT_ABOVE_THE_REFERENCE_FRAME_LIMIT );

 fprintf( stderr, "\nParameter box for transient search: %7.1lf<X<%7.1lf %7.1lf<Y<%7.1lf %5.2lf<m<%5.2lf\n \n",
          search_area_boundaries[0],
          search_area_boundaries[1],
          search_area_boundaries[2],
          search_area_boundaries[3],
          search_area_boundaries[4],
          search_area_boundaries[5] );

 free( filtered_mag_values );

 return;
}

void record_specified_fits_keywords( char *input_image, char *output_str_with_fits_keywords_to_capture_from_input_images ) {
 //
 fitsfile *fptr;       // FITS file pointer, defined in fitsio.h
 char card[FLEN_CARD]; // Standard string lengths defined in fitsio.h
 int status= 0;        // CFITSIO status value MUST be initialized to zero!
 //
 unsigned int number_of_keywords, i, j, good_keyword_flag;
 FILE *filelist_of_keywords_to_record;
 char list_of_keywords_to_record[MAX_NUMBER_OF_FITS_KEYWORDS_TO_CAPTURE_IN_LC][81];
 if ( NULL == input_image ) {
  fprintf( stderr, "ERROR in record_specified_fits_keywords() the input image string is NULL\n" );
  exit( EXIT_FAILURE );
 }
 if ( NULL == output_str_with_fits_keywords_to_capture_from_input_images ) {
  // that's OK, just quietly return
  return;
 }
 output_str_with_fits_keywords_to_capture_from_input_images[0]= '\0'; // maybe no keywords will be recorded
 //
 // Open the ASCII file containing the list of FITS keywords we want to record
 //
 filelist_of_keywords_to_record= fopen( "vast_list_of_FITS_keywords_to_record_in_lightcurves.txt", "r" );
 if ( NULL == filelist_of_keywords_to_record ) {
  return;
 }
 i= 0;
 // The keyword names may be up to 8 characters long and can only contain uppercase letters A to Z, the digits 0 to 9, the hyphen, and the underscore character.
 // https://fits.gsfc.nasa.gov/fits_primer.html
 while ( NULL != fgets( list_of_keywords_to_record[i], 9, filelist_of_keywords_to_record ) ) {
  good_keyword_flag= 1;
  list_of_keywords_to_record[i][9]= '\0';
  for ( j= 0; j < strlen( list_of_keywords_to_record[i] ); j++ ) {
   if ( list_of_keywords_to_record[i][j] >= '0' && list_of_keywords_to_record[i][j] <= '9' )
    continue;
   if ( list_of_keywords_to_record[i][j] >= 'A' && list_of_keywords_to_record[i][j] <= 'Z' )
    continue;
   if ( list_of_keywords_to_record[i][j] == '-' )
    continue;
   if ( list_of_keywords_to_record[i][j] == '_' )
    continue;
   good_keyword_flag= 0;
   break;
  }
  if ( good_keyword_flag == 1 )
   i++;
 }
 fclose( filelist_of_keywords_to_record );
 number_of_keywords= i;
 // fprintf(stderr,"DEBUG: trying to read %d keywords from %s \n",number_of_keywords,input_image);
 //  Open FITS image
 //  It is supposed to be checked above that this is a readable FITS image, but just in case let's check again
 if ( 0 != fitsfile_read_check( input_image ) ) {
  fprintf( stderr, "ERROR in record_specified_fits_keywords(): The input does not appear to be a FITS image: %s\n", input_image );
  output_str_with_fits_keywords_to_capture_from_input_images[FITS_KEYWORDS_IN_LC_LENGTH - 1]= '\0';
  return;
 }
 fits_open_file( &fptr, input_image, READONLY, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status ); // print out any error messages
  fits_clear_errmsg();                 // clear the CFITSIO error message stack
  return;
 }
 //
 // Loop through the list of keywords we want to record
 for ( i= 0; i < number_of_keywords; i++ ) {
  // fprintf(stderr,"ttttttt%sttttttt\n",list_of_keywords_to_record[i]);
  fits_read_card( fptr, list_of_keywords_to_record[i], card, &status );
  if ( 0 != status ) {
   // fits_report_error(stderr, status);  // print out any error messages
   fits_clear_errmsg(); // clear the CFITSIO error message stack
   status= 0;
   continue;
  }
  // remove comments
  for ( j= 0; j < strlen( card ); j++ ) {
   if ( card[j] == '/' )
    card[j]= '\0';
  }
  // fprintf(stderr,"-------%s------\n",card);
  if ( FITS_KEYWORDS_IN_LC_LENGTH < strlen( output_str_with_fits_keywords_to_capture_from_input_images ) + FLEN_CARD ) {
   fprintf( stderr, "ERROR in record_specified_fits_keywords(): the output string is too long!\n" );
   break;
  }
  strncat( output_str_with_fits_keywords_to_capture_from_input_images, card, FLEN_CARD );
 }
 output_str_with_fits_keywords_to_capture_from_input_images[FITS_KEYWORDS_IN_LC_LENGTH - 1]= '\0'; // just in case
 //
 // fprintf(stderr,"###################%s###################\n",output_str_with_fits_keywords_to_capture_from_input_images);
 //
 fits_close_file( fptr, &status );
 if ( 0 != status ) {
  fits_report_error( stderr, status ); // print out any error messages
  fits_clear_errmsg();                 // clear the CFITSIO error message stack
  return;
 }
 //
 return;
}

/****************** The main function ******************/

int main( int argc, char **argv ) {

 FILE *file;

 int previous_star_number_in_sextractor_catalog; // needed to check that the star count in the output catalog is always increasing

 int star_number_in_sextractor_catalog, sextractor_flag;
 double flux_adu, flux_adu_err, position_x_pix, position_y_pix, mag, sigma_mag;

 struct PixCoordinateTransformation *struct_pixel_coordinate_transformation= NULL;

 int number_of_lines_reference_image_cat, number_of_lines_current_image_cat;

 struct Star *STAR1= NULL, *STAR2= NULL, *STAR3= NULL; // STAR1 - structure with all stars we can match
                                                       //         new stars are added to STAR1
                                                       // STAR2 - structure with stars on a current image
                                                       // STAR3 - structure with stars on the reference image used to match frames
                                                       //         to identify pixel coordinate transformation needed tom match individual stars.
                                                       //         No new stars are added to STAR3.
 char *file_or_dir_on_command_line, **input_images, **str_with_fits_keywords_to_capture_from_input_images;
 size_t start_index;
 FILE *file_out;
 int n, Num= 0, i, j; // Counters. Num is number of files to operate
 int NUMBER1, NUMBER2, NUMBER3;
 int Number_of_ecv_star;
 int *Pos1, *Pos2;

 double JD= 0;
 char tmpNAME[OUTFILENAME_LENGTH];             // Array to store generated lightcurve filenames
 struct Observation *ptr_struct_Obs= NULL;     // Structure to store all observations
 long TOTAL_OBS= 0;                            // Total number of measurements
 long obs_in_RAM= 0;                           // Number of observations which were not written to disk
 long Max_obs_in_RAM= MAX_MEASUREMENTS_IN_RAM; // maximum number of observations in RAM
 int N_good_stars= 0;
 //
 int N_bad_stars= 0;
 double *bad_stars_X;
 double *bad_stars_Y;
 //
 int N_manually_selected_comparison_stars= 0;
 double *manually_selected_comparison_stars_X;
 double *manually_selected_comparison_stars_Y;
 double *manually_selected_comparison_stars_catalog_mag;
 int manually_selected_comparison_stars_index;
 FILE *cmparisonstarsfile;
 FILE *calibtxtfile;
 double tmp_manually_selected_comparison_stars_X, tmp_manually_selected_comparison_stars_Y, tmp_manually_selected_comparison_stars_catalog_mag;
 //
 double X_im_size= 0.0;
 double Y_im_size= 0.0;
 double max_X_im_size= 0.0; // new (We may have input images of different size and we need the largest size for image identifictaion)
 double max_Y_im_size= 0.0; // new
 double aperture;
 double reference_image_aperture;

 // Variables to set special parameters
 int fitsfile_read_error= 0;          // returned by gettime
 int photometric_calibration_type= 1; // do not calibrate mags by polynom
 int param_P= 0;                      // PSF photometry mode (1 - do it; 2 - do usual aperture photometry)
 int param_w= 0;                      // wide comparison window
 double fixed_star_matching_radius_pix= 0.0;
 // int param_nocalib = 0;  // do not change magnitude scale
 int param_nofind= 0;                // do not run find_candidates
 int param_nofilter= 1;              // do not run filtering
 int param_nodiscardell= 0;          // do not discard images with elliptical stars
 int param_nodiscardlargesrc= 0;     // do not discard large sources
 int no_rotation= 0;                 // count as error rotation larger than 3 degrees
 int debug= 0;                       // be more verbose
 int period_search_switch= 0;        // do not use period search algorithms
 int use_ds9_instead_of_pgfv= 0;     // if 1 use ds9 instead of pgfv
 int param_failsafe= 0;              // if 1 consider only stars that were detected on the reference frame,
                                     // as in older versions of VaST
 int cache_counter= 0;               // is needed for the lightcurve cache in memory
 int number_of_sysrem_iterations= 0; // if !=0 - use util/sysrem number_of_sysrem_iterations times
 int n_start= 1;                     // sould be 0 if the increment mode is active

 int param_nojdkeyword= 0; // 1 - ignore "JD" keyword in FITS image header, useful if sme junk is written in this keyword instead of the middle exposure time

 int maxsextractorflag= MAX_SEXTRACTOR_FLAG; // Maximum star flag value set by sextractor acceptable for VaST

 int param_use_photocurve= 0; // Use "photocurve" for magnitude calibration. See src/photocurve.c for details

 int param_filterout_magsize_outliers= 1; // 0 - no, 1 - yes  -- filter out outliers on magnitude-size plot

 int param_rescale_photometric_errors= 0; // 1 - yes, 0 - no

 int param_select_best_aperture_for_each_source= 0; // 1 - yes, 0 - no

 int param_remove_bad_images= 1; // 1 - yes, 0 - no

 int param_automatically_select_reference_image= 0; // 1 - yes, 0 - no

 int param_exclude_reference_image= 0; // 1 - yes, 0 - no

 // poly_mag
 double *poly_x= NULL;
 double *poly_y= NULL;
 double *poly_err= NULL;
 double *poly_err_fake= NULL; // this is an array with fake error values that is used for unweighted fitting
 double poly_coeff[10];

 //	double faintest_stars = FAINTEST_STARS_ANYMAG; //FAINTEST_STARS;

 int wpolyfit_exit_code= 0;

 int min_number_of_stars_for_magnitude_calibration= MIN_NUMBER_STARS_POLY_MAG_CALIBR;

 // Linear magnitude correction as a function of X and Y
 int apply_position_dependent_correction= 0;       // 1 - apply, 2 - do not apply
 int param_apply_position_dependent_correction= 0; // determines if this parameter is specified on the command line
 double *lin_mag_cor_x= NULL;
 double *lin_mag_cor_y= NULL;
 double *lin_mag_cor_z= NULL;
 double lin_mag_A, lin_mag_B, lin_mag_C;

 int MATCH_SUCESS= 0;

 int previous_Number_of_main_star;

 // LOG-file
 FILE *vast_image_details; // May refer to both vast_image_details.log and vast_summary.log when needed

 char stderr_output[1024];
 char log_output[1024];

 int exclude_outlier_mags_counter;
 int the_baddest_outlier_number;
 double the_baddest_outlier;
 double abs_computed_predicted_mag_diff;
 double computed_mag;

 double fixed_aperture= 0.0; // If fixed_aperture!=0.0 - use fixed aperture for all images

 FILE *vast_list_of_all_stars_log;
 FILE *vast_list_of_all_stars_ds9;

 FILE *vast_source_detection_rejection_statistics_log;

 FILE *vast_exclude_reference_image_log;

 //// Hunt for transients ////
 double search_area_boundaries[6]; // Xmin, Xmax, Ymin, Ymax, MAGmin, MAGmax

 double a_a; // semi-major axis lengths
 double a_a_err;
 double a_b; // semi-minor axis lengths
 double a_b_err;

 float float_parameters[NUMBER_OF_FLOAT_PARAMETERS];
 int float_parameters_counter;

 //// Execution time measurements ////
 time_t start_time;
 time_t end_time;
 double elapsed_time;

 //// Time system ////
 int timesys= 0;               // 0 - unknown
                               // 1 - UTC
                               // 2 - TT
                               // 3 - TDB (with our current precision it is the same as TT)
 int convert_timesys_to_TT= 1; // Convert JD from UTC to TT?
                               // 0 - no
                               // 1 - yes

 char tymesys_str[32];

 int match_try= 0;                     // counter for multimple match trials
 int match_retry= 0;                   // variable set by Ident
 int default_Number_of_main_star= 100; // init so the compiler does not complain
 int default_Number_of_ecv_triangle;
 int param_set_manually_Number_of_main_star= 0;
 int success_match_on_increase= 0;
 int best_number_of_matched_stars= 0;
 int best_number_of_reference_stars= 0;

 //// Coordinate arrays ////
 int coordinate_array_index;
 int coordinate_array_counter;
 int *number_of_coordinate_measurements_for_star;
 int *star_numbers_for_coordinate_arrays;
 float **coordinate_array_x;
 float **coordinate_array_y;
 int i_update_coordinates_STAR3;

 int max_number; // Maximum star number, will be needed to make up numbers for new stars if we want to add them to the list

 char sextractor_catalog[FILENAME_LENGTH];

 pid_t pid;

#ifndef VAST_ENABLE_OPENMP
 int number_of_lightcurves_for_each_thread; // number of lightcurves to be written on disk by each parrallel thread
#endif

 int k; // a counter used to write down lightcurve files

 struct stat sb; // structure returned by stat() system call
 DIR *dp;
 struct dirent *ep;
 char dir_string[FILENAME_LENGTH];

 DIR *dp2;
 struct dirent *ep2;
 char dir_string2[2 * FILENAME_LENGTH];

 // The following variables are used to handle vast_list_of_input_images_with_time_corrections.txt
 FILE *vast_list_of_input_images_with_time_corrections;
 char str_image_filename_from_input_list_and_time_correction[2 * FILENAME_LENGTH];
 char image_filename_from_input_list[FILENAME_LENGTH];
 double image_date_correction_from_input_list;
 // ------------------------------------------

 int j_poly_err; // a counter for checking that no element in the poly_err[] array is equal to 0.0,
                 // so no data point is super-weighted

 char sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT];

 int guess_saturation_limit_operation_mode= 2; // by default try to be smart and guess
                                               // if we should guess the saturation limit
                                               // or use the one specified in default.sex
 int external_flag;
 double psf_chi2;

 int counter_rejected_bad_flux, counter_rejected_low_snr, counter_rejected_bad_region;
 int counter_rejected_frame_edge, counter_rejected_too_small, counter_rejected_too_large;
 int counter_rejected_external_flag, counter_rejected_bad_psf_fit, counter_rejected_seflags_gt7;
 int counter_rejected_MagSize, counter_rejected_seflags_gt_user_spec_threshold;

 long long int malloc_size= 0; // we want to have it a signed type (not size_t) so the negative value of malloc_size may indicate an error

 double fraction_of_good_measurements_for_this_source; // fraction of good measurements used to filter-out bad sources

 /// Comparison star filtering ////
 double sigma_from_MAD; // for compariosn stars filtering
 int number_of_bright_stars_to_drop_from_mag_calibr= 0;
 int comparison_star_counter;
 int comparison_star_counter2;
 double comparison_star_median_mag_diff;
 double *comparison_star_mag_diff;
 double *comparison_star_poly_x_good;
 double *comparison_star_poly_y_good;
 double *comparison_star_poly_err_good;
 double *poly_x_original_pointer;
 double *poly_y_original_pointer;
 double *poly_err_original_pointer;

 char system_command_select_comparison_stars[2 * FILENAME_LENGTH];

 FILE *manually_selected_aperture_txt_file;
 double manually_selected_aperture;

 int diffphot_flag= 0; // 0 -- the usual mode, 1 -- diffphot (manually selected comparison stars, zero-point offset only)

 //////////////////////////////////

 char filename_for_magnitude_calibration_log[2 * FILENAME_LENGTH]; // image00001__myimage.fits

 int vast_bad_image_flag[MAX_NUMBER_OF_OBSERVATIONS]; // 0 -- good image; >=1 -- bad image;

 int vast_bad_image_flag_counter= 0; // count bad images flagged during image analysis
                                     // note that there is another step when bad images are falgged - lightcurve analysis

 //        int number_of_elements_in_Pos1; // needed for adding stars not detected on the reference frame

 /// end of definitions
 lin_mag_A= lin_mag_B= lin_mag_C= 0.0; // just in case

 // Protection against strange free() crashes
 // setenv("MALLOC_CHECK_", "0", 1);

 char sextractor_catalog_filtering_results_string[2048];

 // char string_with_float_parameters_and_saved_FITS_keywords[2048 + FITS_KEYWORDS_IN_LC_LENGTH];

 // Moving object hack
 char moving_object= 0;
 float *moving_object__user_array_x;
 float *moving_object__user_array_y;
 char str_moving_object_lightcurve_file[OUTFILENAME_LENGTH];
 //

 // memset(sextractor_catalog, 0, FILENAME_LENGTH); // just to make vlagrind happy

 print_vast_version();

 // argv[] parsing begins
 if ( argc == 1 ) {
  // no command line arguments! Is this is a mistake or should we read the input list of images from a file
  vast_list_of_input_images_with_time_corrections= fopen( "vast_list_of_input_images_with_time_corrections.txt", "r" );
  // Check if we can open the file
  if ( NULL == vast_list_of_input_images_with_time_corrections ) {
   help_msg( argv[0], 0 );
  } else {
   fclose( vast_list_of_input_images_with_time_corrections );
  }
  //
 }

 // Options for getopt()
 char *cvalue= NULL;

 // const char *const shortopt= "vh9fdqmwpoPngGrlseucUijJkK12346785:a:b:x:y:t:";
 const char *const shortopt= "a:b:cdefgGhijJkKlmnopPqrst:uUvwx:y:z12345:6789";
 const struct option longopt[]= {
     { "guess_saturation_limit", 0, NULL, 'g' },
     { "no_guess_saturation_limit", 0, NULL, 'G' },
     { "version", 0, NULL, 'v' },
     { "PSF", 0, NULL, 'P' },
     { "help", 0, NULL, 'h' },
     { "ds9", 0, NULL, '9' },
     { "small", 0, NULL, 's' },
     { "type", 1, NULL, 't' },
     { "medium", 0, NULL, 'm' },
     { "wide", 0, NULL, 'w' },
     { "starmatchraius", 1, NULL, '5' },
     { "poly", 0, NULL, 'p' },
     { "nodiscardell", 0, NULL, 'l' },
     { "norotation", 0, NULL, 'r' },
     { "nofind", 0, NULL, 'f' },
     { "debug", 0, NULL, 'd' },
     { "position_dependent_correction", 0, NULL, 'j' },
     { "no_position_dependent_correction", 0, NULL, 'J' },
     { "aperture", 1, NULL, 'a' },
     { "matchstarnumber", 1, NULL, 'b' },
     { "sysrem", 1, NULL, 'y' },
     { "failsafe", 0, NULL, 'e' },
     { "UTC", 0, NULL, 'u' },
     { "utc", 0, NULL, 'c' },
     { "Utc", 0, NULL, 'U' },
     { "increment", 0, NULL, 'i' },
     { "nojdkeyword", 0, NULL, 'k' },
     { "nodateobskeyword", 0, NULL, 'K' },
     { "maxsextractorflag", 1, NULL, 'x' },
     { "photocurve", 0, NULL, 'o' },
     { "magsizefilter", 0, NULL, '1' },
     { "nomagsizefilter", 0, NULL, '2' },
     { "selectbestaperture", 0, NULL, '3' },
     { "noerrorsrescale", 0, NULL, '4' },
     { "notremovebadimages", 0, NULL, '6' },
     { "autoselectrefimage", 0, NULL, '7' },
     { "excluderefimage", 0, NULL, '8' },
     { "movingobject", 0, NULL, 'z' },
     { NULL, 0, NULL, 0 } }; // NULL string must be in the end
 int nextopt;
 fprintf( stderr, "Parsing command line arguments...\n" );
 while ( nextopt= getopt_long( argc, argv, shortopt, longopt, NULL ), nextopt != -1 ) {
  switch ( nextopt ) {
  case 'v':
   version( stderr_output );
   fprintf( stdout, "%s\n", stderr_output );
   return EXIT_FAILURE;
  case 'h':
   help_msg( argv[0], 0 );
   break;
  case 'f':
   param_nofind= 1;
   fprintf( stderr, "opt 'f': Run ./find_candidates manually!\n" );
   break;
  case 'd':
   debug= 1;
   // Relatively lightweight heap buffer overflow detection.
   // It is implemented by increasing the size of allocations and storing some padding and checking it in some places.
   // This heap checker should be thread-safe, and it is tightly coupled with malloc internals.
   // see https://stackoverflow.com/questions/18153746/what-is-the-difference-between-glibcs-malloc-check-m-check-action-and-mcheck
   setenv( "MALLOC_CHECK_", "1", 1 );
   break;
  case 'q':
   debug= 1;
   param_nofind= 1;
   break;
  case 't':
   cvalue= optarg;
   if ( 1 == is_file( cvalue ) ) {
    fprintf( stderr, "Option -%c requires an argument: the desired photometric calibration type!\n", optopt );
    return EXIT_FAILURE;
   }
   photometric_calibration_type= atoi( cvalue );
   if ( photometric_calibration_type < 0 || photometric_calibration_type > 4 ) {
    fprintf( stderr, "The argument is out of range: -%c %s \n", optopt, cvalue );
    return EXIT_FAILURE;
   }
   if ( photometric_calibration_type == 0 ) {
    fprintf( stderr, "opt 't 0': linear magnitude calibration (vary zero-point and slope)\n" );
   }
   if ( photometric_calibration_type == 1 ) {
    fprintf( stderr, "opt 't 1': magnitude calibration with parabola\n" );
   }
   if ( photometric_calibration_type == 2 ) {
    fprintf( stderr, "opt 't 2': zero-point only magnitude calibration (linear with the fixed slope)\n" );
    apply_position_dependent_correction= 0;
    param_use_photocurve= 0; // obviously incompatible with photocurve
   }
   if ( photometric_calibration_type == 3 ) {
    // equivalent to '-o'
    param_nodiscardell= 1; // incompatible with photocurve
    param_use_photocurve= 1;
    photometric_calibration_type= 1; // force parabolic magnitude fit (it should be reasonably good). It is needed to remove outliers.
    fprintf( stderr, "opt 't 3': \"photocurve\" will be used for magnitude calibration!\n" );
   }
   if ( photometric_calibration_type == 4 ) {
    fprintf( stderr, "opt 't 4': robust linear magnitude calibration (vary zero-point and slope)\n" );
   }

   break;
  case '9': // use ds9 FITS viewer
   use_ds9_instead_of_pgfv= 1;
   fprintf( stderr, "opt '9': DS9 FITS viewer will be used instead of pgfv\n" );
   break;
  case 'g': // Auto-detect saturation limit
   guess_saturation_limit_operation_mode= 1;
   fprintf( stderr, "opt 'g': Will try to guess saturation limit for each image\n" );
   break;
  case 'G': // Auto-detect saturation limit
   guess_saturation_limit_operation_mode= 0;
   fprintf( stderr, "opt 'G': Will NOT try to guess saturation limit for each image\n" );
   break;
  /// Should be replaces with the new option 'starmatchraius'
  case 's': // small comparison window - 1 pix.
   param_w= 3;
   struct_pixel_coordinate_transformation= New_PixCoordinateTransformation();
   fprintf( stderr, "opt 's': Using small match radius (comparison window)\n" );
   break;
  case '5':
   cvalue= optarg;
   if ( 1 == is_file( cvalue ) ) {
    fprintf( stderr, "Option -%c requires an argument: star matching radius in pixels\n", optopt );
    return EXIT_FAILURE;
   }
   param_w= 4;
   fixed_star_matching_radius_pix= atof( cvalue );
   if ( fixed_star_matching_radius_pix < 0.1 || fixed_star_matching_radius_pix > 100.0 ) {
    fprintf( stderr, "ERROR: fixed_star_matching_radius_pix is out of range!\n" );
    return EXIT_FAILURE;
   }
   fprintf( stderr, "opt '5': %lf pix is the new fixed star matching radius!\n", fixed_star_matching_radius_pix );
   break;
  ///
  case 'p':
   photometric_calibration_type= 0;
   fprintf( stderr, "opt 'p': Polynomial magnitude calibration will *NOT* be used!\n" );
   break;
  case 'o':
   param_nodiscardell= 1; // incompatible with photocurve
   param_use_photocurve= 1;
   photometric_calibration_type= 1; // force parabolic magnitude fit (it should be reasonably good). It is needed to remove outliers.
   fprintf( stderr, "opt 'o': \"photocurve\" will be used for magnitude calibration!\n" );
   break;
  case 'z':
   // switch on to the user-specified moving object mode
   moving_object= 1;
   fprintf( stderr, "opt 'z': Experimental moving object tracking mode!\n" );
   // set additional flags to make things compatible with this mode
   convert_timesys_to_TT= 0;
   fprintf( stderr, "opt 'u': Stick with UTC time system, no conversion to TT will be done!\n" );
   param_filterout_magsize_outliers= 0;
   fprintf( stderr, "opt '2': disabling filter out outliers on mag-size plot!\n" );
   param_automatically_select_reference_image= 0;
   fprintf( stderr, "opt ' ': diable automated reference-image selection!\n" );
   maxsextractorflag= 3;
   fprintf( stderr, "opt 'x': %d is the maximum acceptable SExtractor flag!\n", maxsextractorflag );
   break;
  case '1':
   param_filterout_magsize_outliers= 1;
   fprintf( stderr, "opt '1': filter out outliers on mag-size plot!\n" );
   break;
  case '2':
   param_filterout_magsize_outliers= 0;
   fprintf( stderr, "opt '2': disabling filter out outliers on mag-size plot!\n" );
   break;
  case '3':
   param_select_best_aperture_for_each_source= 1;
   fprintf( stderr, "opt '3': Will try to select best aperture for each source!\n" );
   break;
  case '4':
   param_rescale_photometric_errors= 0;
   fprintf( stderr, "opt '4': Will not re-scale photometric errors!\n" );
   break;
  case '6':
   param_remove_bad_images= 0;
   fprintf( stderr, "opt '6': Will not remove bad images!\n" );
   break;
  case '7':
   param_automatically_select_reference_image= 1;
   fprintf( stderr, "opt '7': Will try to automatically select the deepest reference image!\n" );
   break;
  case '8':
   param_exclude_reference_image= 1;
   fprintf( stderr, "opt '8': the reference image will not be used for photometry!\n" );
   break;
  case 'P':
   // param_nodiscardell= 1; // incompatible with PSF photometry and I'm not sure why - probably a bug
   param_P= 1;
   fprintf( stderr, "opt 'P': PSF photometry mode!\n" );
   // Check if the PSFEx executable (named "psfex") is present in $PATH
   if ( 0 != system( "lib/look_for_psfex.sh" ) ) {
    return EXIT_FAILURE;
   }
   // psfex.found will be created by lib/look_for_psfex.sh if PSFEx is found
   if ( 0 == is_file( "psfex.found" ) ) {
    return EXIT_FAILURE;
   }
   break;
  case 'r':
   no_rotation= 1;
   fprintf( stderr, "opt 'r': assuming no rotation larger than %.1lf degrees!\n", MAX_NOROTATION_ANGLE_RAD * 180.0 / M_PI );
   break;
  case 'l':
   // param_nofilter= 0;
   param_nodiscardell= 1;
   fprintf( stderr, "opt 'l': will NOT try to discard images with elliptical stars (bad tracking)!\n" );
   break;
  case 'j':
   apply_position_dependent_correction= 1;
   param_apply_position_dependent_correction= 1;
   fprintf( stderr, "opt 'j': USING image-position-dependent correction!\n" );
   break;
  case 'J':
   apply_position_dependent_correction= 0;
   param_apply_position_dependent_correction= 1;
   fprintf( stderr, "opt 'J': NOT USING image-position-dependent correction!\n" );
   break;
  case 'e':
   param_failsafe= 1;
   fprintf( stderr, "opt 'e': FAILSAFE mode. Only stars detected on the reference frame will be processed!\n" );
   break;
   // UTC the following options duplicate each other to allow for both --UTC and --utc
  case 'u':
   convert_timesys_to_TT= 0;
   timesys= 1;
   fprintf( stderr, "opt 'u': Stick with UTC time system, no conversion to TT will be done!\n" );
   break;
  case 'c':
   convert_timesys_to_TT= 0;
   timesys= 1;
   fprintf( stderr, "opt 'c': Stick with UTC time system, no conversion to TT will be done!\n" );
   break;
  case 'U':
   convert_timesys_to_TT= 0;
   timesys= 1;
   fprintf( stderr, "opt 'U': Stick with UTC time system, no conversion to TT will be done!\n" );
   break;
   // end of UTC
  case 'k':
   param_nojdkeyword= 1;
   fprintf( stderr, "opt 'k': \"JD\" keyword in FITS image header will be ignored!\n" );
   break;
  case 'K':
   if ( param_nojdkeyword == 1 ) {
    fprintf( stderr, "WARNING: VaST can't ignore both 'JD' and 'DATE-OBS' keywords!\nWill ignore 'DATE-OBS' keyword.\n" );
   }
   param_nojdkeyword= 2;
   fprintf( stderr, "opt 'K': \"DATE-OBS\" keyword in FITS image header will be ignored!\n" );
   break;
  case 'a':
   cvalue= optarg;
   if ( 1 == is_file( cvalue ) ) {
    fprintf( stderr, "Option -%c requires an argument: fixed aperture size in pix.!\n", optopt );
    return EXIT_FAILURE;
   }
   fixed_aperture= atof( cvalue );
   fprintf( stderr, "opt 'a': Using fixed aperture %.1lf pix. in diameter!\n", fixed_aperture );
   if ( fixed_aperture < 1.0 ) {
    fprintf( stderr, "ERROR: the specified fixed aperture dameter is out of the expected range!\n" );
    return EXIT_FAILURE;
   }
   break;
  case 'b':
   cvalue= optarg;
   if ( 1 == is_file( cvalue ) ) {
    fprintf( stderr, "Option -%c requires an argument: number of reference stars!\n", optopt );
    return EXIT_FAILURE;
   }
   param_set_manually_Number_of_main_star= 1;
   default_Number_of_main_star= atoi( cvalue );
   default_Number_of_ecv_triangle= MATCH_MAX_NUMBER_OF_TRIANGLES;
   fprintf( stderr, "opt 'b': Using %d reference stars for image matching!\n", default_Number_of_main_star );
   break;
  case 'y':
   cvalue= optarg;
   if ( 1 == is_file( cvalue ) ) {
    fprintf( stderr, "Option -%c requires an argument: number of SysRem iterations!\n", optopt );
    return EXIT_FAILURE;
   }
   if ( number_of_sysrem_iterations != 1 )
    number_of_sysrem_iterations= atoi( cvalue );
   fprintf( stderr, "opt 'y': %d SysRem iterations will be conducted!\n", number_of_sysrem_iterations );
   break;
  case 'x':
   cvalue= optarg;
   if ( 1 == is_file( cvalue ) ) {
    fprintf( stderr, "Option -%c requires an argument: Maximum acceptable SExtractor flag!\n", optopt );
    return EXIT_FAILURE;
   }
   maxsextractorflag= atoi( cvalue );
   if ( maxsextractorflag < 0 || maxsextractorflag > 255 ) {
    fprintf( stderr, "WARNING: maximum acceptable flag value %d is set incorrectly!\nResorting to the default value of %d.\n", maxsextractorflag, MAX_SEXTRACTOR_FLAG );
    maxsextractorflag= MAX_SEXTRACTOR_FLAG;
   }
   fprintf( stderr, "opt 'x': %d is the maximum acceptable SExtractor flag!\n", maxsextractorflag );
   if ( maxsextractorflag > 1 ) {
    if ( param_filterout_magsize_outliers == 1 ) {
     param_filterout_magsize_outliers= 0;
     fprintf( stderr, "WARNING: disabling the mag-size filter in order not to reject blended stars.\n" );
    }
   }
   break;
  case '?':
   if ( optopt == 'a' ) {
    fprintf( stderr, "Option -%c requires an argument: fixed aperture size in pix.!\n", optopt );
    return EXIT_FAILURE;
   }
   fprintf( stderr, "ERROR: unknown option!\n" );
   return EXIT_FAILURE;
   break;
  case -1:
   fprintf( stderr, "That's all\n" );
   break;
  }
 }

 // Check maxsextractorflag value
 if ( maxsextractorflag < 0 || maxsextractorflag > 255 ) {
  fprintf( stderr, "WARNING: maximum acceptable flag value %d is set incorrectly!\nPlease check MAX_SEXTRACTOR_FLAG in src/vast_limits.h\nResorting to the default value of %d.\n", maxsextractorflag, 0 );
  maxsextractorflag= 0;
 }

 // Report a potential problem mag-size filter if maxsextractorflag>1
 if ( maxsextractorflag > 1 ) {
  if ( param_filterout_magsize_outliers == 1 ) {
   // param_filterout_magsize_outliers=0
   fprintf( stderr, "WARNING: mag-size filter is enabled while VaST is asked to accept blended stars marked by SExtractor (flag>=%d)!\nThe mag-size filter WILL REJECT BLENDED STARS.\n", maxsextractorflag );
   fprintf( stderr, "This warning message will disappear in...   " );
   // sleep for 6 seconds to make sure user saw the message
   for ( n= 5; n > 0; n-- ) {
    sleep( 1 );
    fprintf( stderr, "%d ", n );
   }
   sleep( 1 );
   fprintf( stderr, "NOW!\n" );
  }
 }

 malloc_size= sizeof( char ) * FILENAME_LENGTH;
 if ( malloc_size <= 0 ) {
  fprintf( stderr, "ERROR001 - trying to allocate zero or negative number of bytes!\n" );
  return EXIT_FAILURE;
 }
 file_or_dir_on_command_line= malloc( (size_t)malloc_size );
 if ( file_or_dir_on_command_line == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory!\n file_or_dir_on_command_line = malloc(sizeof(char) * FILENAME_LENGTH); - failed!\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 input_images= NULL;
 Num= 0;

 // just in case - assume all images are good by default
 memset( vast_bad_image_flag, 0, sizeof( vast_bad_image_flag ) );

 // Clean symlinks to images and on-the-fly converted images from a previous run
 if ( argc > 1 ) {
  // This cannot be handled in util/clean_data.sh because we start it after creating the symlinks

  // symlinks
#ifdef DEBUGMESSAGES
  fprintf( stderr, "Starting remove_directory( \"symlinks_to_images\" )\n" );
#endif
  remove_directory( "symlinks_to_images" );
#ifdef DEBUGMESSAGES
  fprintf( stderr, "Done with remove_directory( \"symlinks_to_images\" )\n" );
#endif
  // converted images
#ifdef DEBUGMESSAGES
  fprintf( stderr, "Starting remove_directory( \"converted_images\" )\n" );
#endif
  remove_directory( "converted_images" );
#ifdef DEBUGMESSAGES
  fprintf( stderr, "Done with remove_directory( \"converted_images\" )\n" );
#endif
 }

 // Go through images and directories specified on the command line
 fprintf( stderr, "\nChecking the list of input images specified on the command line ...\n" );
 for ( n= optind; n < argc; ++n ) {
  if ( (int)strlen( argv[n] ) > FILENAME_LENGTH ) {
   fprintf( stderr, "ERROR: the input filename is too long (FILENAME_LENGTH = %d, while this one is %d) %s\n", FILENAME_LENGTH, (int)strlen( argv[n] ), argv[n] );
   return EXIT_FAILURE;
  }
  // strncpy( file_or_dir_on_command_line, argv[n], FILENAME_LENGTH );
  safely_encode_user_input_string( file_or_dir_on_command_line, argv[n], FILENAME_LENGTH );
  //
  file_or_dir_on_command_line[FILENAME_LENGTH - 1]= '\0'; // just in case
  // Try to stat() the input
  if ( 0 != stat( file_or_dir_on_command_line, &sb ) ) {
   fprintf( stderr, "Cannot stat() %s - No such file or directory. Skipping the input.\n", file_or_dir_on_command_line );
   continue;
  }
  // If this is some funny file
  if ( ( sb.st_mode & S_IFMT ) != S_IFDIR && ( sb.st_mode & S_IFMT ) != S_IFREG ) {
   fprintf( stderr, "The input is not a regular file, directory or symlink. Skipping the input %s\n", file_or_dir_on_command_line );
   continue;
  }
  // If this is dir
  if ( ( sb.st_mode & S_IFMT ) == S_IFDIR ) {
   fprintf( stderr, "Listing level 1 directory %s\n", file_or_dir_on_command_line );
   dp= opendir( file_or_dir_on_command_line );
   if ( dp == NULL )
    continue;
   while ( ( ep= readdir( dp ) ) != NULL ) {
    // Cycle through all entries
    if ( ep->d_name[0] == '.' )
     continue; // avoid hidden files and dirs
    if ( (int)strlen( ep->d_name ) < 3 )
     continue; // avoid short filenames
    if ( file_or_dir_on_command_line[(int)strlen( file_or_dir_on_command_line ) - 1] == '/' ) {
     sprintf( dir_string, "%s%s", file_or_dir_on_command_line, ep->d_name );
    } else {
     sprintf( dir_string, "%s/%s", file_or_dir_on_command_line, ep->d_name );
    }
    // Try to stat() the input
    if ( 0 != stat( dir_string, &sb ) ) {
     fprintf( stderr, "Cannot stat() %s - No such file or directory. Skipping the input.\n", dir_string );
     continue;
    }
    if ( ( sb.st_mode & S_IFMT ) != S_IFDIR && ( sb.st_mode & S_IFMT ) != S_IFREG ) {
     fprintf( stderr, "The input is not a regular file, directory or symlink. Skipping the input %s\n", dir_string );
     continue;
    }
    if ( ( sb.st_mode & S_IFMT ) == S_IFDIR ) {
     fprintf( stderr, "This is a directory: %s\n", dir_string );
     ///////////////////////////////////////////////////////////////////////////////////////////
     // TBA: list the second-level directory too
     fprintf( stderr, "Listing level 2 directory %s\n", dir_string );
     dp2= opendir( dir_string );
     if ( dp2 == NULL )
      continue;
     while ( ( ep2= readdir( dp2 ) ) != NULL ) {
      // Cycle through all entries
      if ( ep2->d_name[0] == '.' )
       continue; // avoid hidden files and dirs
      if ( (int)strlen( ep2->d_name ) < 3 )
       continue; // avoid short filenames
      if ( dir_string[(int)strlen( dir_string ) - 1] == '/' ) {
       sprintf( dir_string2, "%s%s", dir_string, ep2->d_name );
      } else {
       sprintf( dir_string2, "%s/%s", dir_string, ep2->d_name );
      }
      // Try to stat() the input
      if ( 0 != stat( dir_string2, &sb ) ) {
       fprintf( stderr, "Cannot stat() %s - No such file or directory. Skipping the input.\n", dir_string2 );
       continue;
      }
      if ( ( sb.st_mode & S_IFMT ) != S_IFDIR && ( sb.st_mode & S_IFMT ) != S_IFREG ) {
       fprintf( stderr, "The input is not a regular file, directory or symlink. Skipping the input %s\n", dir_string2 );
       continue;
      }
      if ( ( sb.st_mode & S_IFMT ) == S_IFDIR ) {
       fprintf( stderr, "This is a level 3 directory, its content will be ignored: %s\n", dir_string2 );
       ///////////////////////////////////////////////////////////////////////////////////////////
       // TBA: list the second-level directory too
       ///////////////////////////////////////////////////////////////////////////////////////////
       continue;
      } // if((sb.st_mode & S_IFMT) == S_IFDIR){
      if ( ( sb.st_mode & S_IFMT ) == S_IFREG ) {
       // Handle a regular file in a first-level directory
       if ( 0 != fitsfile_read_check( dir_string2 ) ) {
        fprintf( stderr, "The input does not appear to be a FITS image (1): %s\n", dir_string2 );
        continue;
       } else {
        // allocate memory for the list of input images
        input_images= (char **)realloc( input_images, sizeof( char * ) * ( Num + 1 ) );
        if ( input_images == NULL ) {
         fprintf( stderr, "ERROR: can't allocate memory!\n input_images = (char **)realloc(input_images, sizeof(char *) * n); - failed!\n" );
         return EXIT_FAILURE;
        }
        // handle file names with white spaces
        replace_file_with_symlink_if_filename_contains_white_spaces( dir_string2 );
        // handle RGB DSLR image
        cutout_green_channel_out_of_RGB_DSLR_image( dir_string2 );
        // allocate memory for each item in the image list
        malloc_size= sizeof( char ) * ( strlen( dir_string2 ) + 1 );
        // !!!
        if ( malloc_size > FILENAME_LENGTH ) {
         fprintf( stderr, "ERROR in main(): filename is too long %s\n", dir_string2 );
         return EXIT_FAILURE;
        }
        malloc_size= FILENAME_LENGTH;
        //
        if ( malloc_size <= 0 ) {
         fprintf( stderr, "ERROR002 - trying to allocate zero or negative number of bytes!\n" );
         return EXIT_FAILURE;
        }
        input_images[Num]= malloc( (size_t)malloc_size );
        if ( input_images[Num] == NULL ) {
         fprintf( stderr, "ERROR: can't allocate memory!\n input_images[Num] = malloc(sizeof(char) * (strlen(file_or_dir_on_command_line) + 1)); - failed!\n" );
         vast_report_memory_error();
         return EXIT_FAILURE;
        }
        // strcpy(input_images[Num], dir_string2);
        // strncpy(input_images[Num], dir_string2, malloc_size);
        safely_encode_user_input_string( input_images[Num], dir_string2, malloc_size );
        input_images[Num][malloc_size - 1]= '\0'; // just in case
        vast_bad_image_flag[Num]= 0;              // mark the image good by default
        // increase image counter
        Num++;
       }
      } // if((sb.st_mode & S_IFMT) == S_IFREG){
     }
     (void)closedir( dp2 );
     ///////////////////////////////////////////////////////////////////////////////////////////
     continue;
    } // if((sb.st_mode & S_IFMT) == S_IFDIR){
    if ( ( sb.st_mode & S_IFMT ) == S_IFREG ) {
     // Handle a regular file in a first-level directory
     if ( 0 != fitsfile_read_check( dir_string ) ) {
      fprintf( stderr, "The input does not appear to be a FITS image (2): %s\n", dir_string );
      continue;
     } else {

      // allocate memory for the list of input images
      input_images= (char **)realloc( input_images, sizeof( char * ) * ( Num + 1 ) );
      if ( input_images == NULL ) {
       fprintf( stderr, "ERROR: can't allocate memory!\n input_images = (char **)realloc(input_images, sizeof(char *) * n); - failed!\n" );
       return EXIT_FAILURE;
      }
      // handle file names with white spaces
      replace_file_with_symlink_if_filename_contains_white_spaces( dir_string );
      // handle RGB DSLR image
      cutout_green_channel_out_of_RGB_DSLR_image( dir_string );
      // allocate memory for each item in the image list
      malloc_size= sizeof( char ) * ( strlen( dir_string ) + 1 );
      // !!!
      if ( malloc_size > FILENAME_LENGTH ) {
       fprintf( stderr, "ERROR in main(): filename is too long %s\n", dir_string );
       return EXIT_FAILURE;
      }
      malloc_size= FILENAME_LENGTH;
      //
      if ( malloc_size <= 0 ) {
       fprintf( stderr, "ERROR002 - trying to allocate zero or negative number of bytes!\n" );
       return EXIT_FAILURE;
      }
      input_images[Num]= malloc( (size_t)malloc_size );
      if ( input_images[Num] == NULL ) {
       fprintf( stderr, "ERROR: can't allocate memory!\n input_images[Num] = malloc(sizeof(char) * (strlen(file_or_dir_on_command_line) + 1)); - failed!\n" );
       vast_report_memory_error();
       return EXIT_FAILURE;
      }
      // strcpy(input_images[Num], dir_string);
      // strncpy(input_images[Num], dir_string, malloc_size);
      safely_encode_user_input_string( input_images[Num], dir_string, malloc_size );
      input_images[Num][malloc_size - 1]= '\0'; // just in case
      vast_bad_image_flag[Num]= 0;              // mark the image good by default
      // increase image counter
      Num++;
     }
    } // if((sb.st_mode & S_IFMT) == S_IFREG){
   }
   (void)closedir( dp );
   continue;
  } // if((sb.st_mode & S_IFMT) == S_IFDIR){
  // If this is a regular file
  if ( ( sb.st_mode & S_IFMT ) == S_IFREG ) {
   // Handle a regular file specified on the command line
   if ( 0 != fitsfile_read_check( file_or_dir_on_command_line ) ) {
    fprintf( stderr, "The input does not appear to be a FITS image (3): %s\n", file_or_dir_on_command_line );
    continue;
   }
   input_images= (char **)realloc( input_images, sizeof( char * ) * ( Num + 1 ) );
   if ( input_images == NULL ) {
    fprintf( stderr, "ERROR: can't allocate memory!\n input_images = (char **)realloc(input_images, sizeof(char *) * n); - failed!\n" );
    return EXIT_FAILURE;
   }
   replace_file_with_symlink_if_filename_contains_white_spaces( file_or_dir_on_command_line );
   // handle RGB DSLR image
   cutout_green_channel_out_of_RGB_DSLR_image( file_or_dir_on_command_line );
   malloc_size= sizeof( char ) * ( strlen( file_or_dir_on_command_line ) + 1 );
   // !!!
   if ( malloc_size > FILENAME_LENGTH ) {
    fprintf( stderr, "ERROR in main(): filename(2) is too long %s\n", dir_string );
    return EXIT_FAILURE;
   }
   malloc_size= FILENAME_LENGTH;
   if ( malloc_size <= 0 ) {
    fprintf( stderr, "ERROR003 - trying to allocate zero or negative number of bytes!\n" );
    return EXIT_FAILURE;
   }
   input_images[Num]= malloc( (size_t)malloc_size );
   if ( input_images[Num] == NULL ) {
    fprintf( stderr, "ERROR: can't allocate memory!\n input_images[Num] = malloc(sizeof(char) * (strlen(file_or_dir_on_command_line) + 1)); - failed!\n" );
    vast_report_memory_error();
    return EXIT_FAILURE;
   }
   // strcpy(input_images[Num], file_or_dir_on_command_line);
   // strncpy(input_images[Num], file_or_dir_on_command_line, malloc_size);
   safely_encode_user_input_string( input_images[Num], file_or_dir_on_command_line, malloc_size );
   input_images[Num][malloc_size - 1]= '\0'; // just in case
   vast_bad_image_flag[Num]= 0;              // mark the image good by default
   // increase image counter
   Num++;
  } // if((sb.st_mode & S_IFMT) == S_IFREG){
 }
 // free(file_or_dir_on_command_line); should be here!
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: free(file_or_dir_on_command_line);\n" );
 free( file_or_dir_on_command_line );

 // Go through images specified in vast_list_of_input_images_with_time_corrections.txt
 fprintf( stderr, "\nLooking for the list of input images with time corrections in vast_list_of_input_images_with_time_corrections.txt ... " );
 vast_list_of_input_images_with_time_corrections= fopen( "vast_list_of_input_images_with_time_corrections.txt", "r" );
 // Check if we can open the file
 if ( NULL != vast_list_of_input_images_with_time_corrections ) {
  // If the file exists
  fprintf( stderr, "list found!\n" );
  // Possibe buffer overflow here beacuse of fscanf(..., "%s", ...), but I feel lucky
  // while ( 2 == fscanf( vast_list_of_input_images_with_time_corrections, "%s %lf", image_filename_from_input_list, &image_date_correction_from_input_list ) ) {
  while ( NULL != fgets( str_image_filename_from_input_list_and_time_correction, 2 * FILENAME_LENGTH, vast_list_of_input_images_with_time_corrections ) ) {
   if ( 2 != sscanf( str_image_filename_from_input_list_and_time_correction, "%s %lf", image_filename_from_input_list, &image_date_correction_from_input_list ) ) {
    // handle the case when no time correction is specified, just the image file
    if ( 1 != sscanf( str_image_filename_from_input_list_and_time_correction, "%s", image_filename_from_input_list ) ) {
     continue;
    }
    image_date_correction_from_input_list= 0.0;
   }
   // We will run a few simple checks on image_date_correction_from_input_list and forget image_date_correction_from_input_list for now, it will be looked for in gettime() later
   if ( fabs( image_date_correction_from_input_list ) > EXPECTED_MAX_JD )
    continue;
   // Try to stat image_filename_from_input_list
   if ( 0 != stat( image_filename_from_input_list, &sb ) ) {
    fprintf( stderr, "Cannot stat() %s - No such file or directory. Skipping the input.\n", image_filename_from_input_list );
    continue;
   }
   // If this is some funny file
   if ( ( sb.st_mode & S_IFMT ) != S_IFDIR && ( sb.st_mode & S_IFMT ) != S_IFREG ) {
    fprintf( stderr, "The input is not a regular file, directory or symlink. Skipping the input %s\n", image_filename_from_input_list );
    continue;
   }
   // If this is dir
   if ( ( sb.st_mode & S_IFMT ) == S_IFDIR ) {
    fprintf( stderr, "Sorry, you cannot specify a directory in vast_list_of_input_images_with_time_corrections.txt\nPlease specify only individual images in vast_list_of_input_images_with_time_corrections.txt\nSkipping the input %s\n", image_filename_from_input_list );
    continue;
   }
   if ( ( sb.st_mode & S_IFMT ) == S_IFREG ) {
    // Handle a regular file
    if ( 0 != fitsfile_read_check( image_filename_from_input_list ) ) {
     fprintf( stderr, "The input does not appear to be a FITS image (4): %s\n", image_filename_from_input_list );
     continue;
    }
    input_images= (char **)realloc( input_images, sizeof( char * ) * ( Num + 1 ) );
    if ( input_images == NULL ) {
     fprintf( stderr, "ERROR: can't allocate memory!\n input_images = (char **)realloc(input_images, sizeof(char *) * n); - failed!\n" );
     return EXIT_FAILURE;
    }
    malloc_size= sizeof( char ) * ( strlen( image_filename_from_input_list ) + 1 );
    if ( malloc_size > FILENAME_LENGTH ) {
     fprintf( stderr, "ERROR in main(): filename is too long %s\n", image_filename_from_input_list );
     return EXIT_FAILURE;
    }
    malloc_size= FILENAME_LENGTH;
    if ( malloc_size <= 0 ) {
     fprintf( stderr, "ERROR004 - trying to allocate zero or negative number of bytes!\n" );
     return EXIT_FAILURE;
    }
    input_images[Num]= malloc( (size_t)malloc_size );
    // input_images[Num] = malloc(sizeof(char) * (strlen(image_filename_from_input_list) + 1));
    if ( input_images[Num] == NULL ) {
     fprintf( stderr, "ERROR: can't allocate memory!\n input_images[Num] = malloc(sizeof(char) * (strlen(image_filename_from_input_list) + 1)); - failed!\n" );
     vast_report_memory_error();
     return EXIT_FAILURE;
    }
    // strcpy(input_images[Num], image_filename_from_input_list);
    // strncpy(input_images[Num], image_filename_from_input_list, malloc_size);
    safely_encode_user_input_string( input_images[Num], image_filename_from_input_list, malloc_size );
    input_images[Num][malloc_size - 1]= '\0'; // just in case
    vast_bad_image_flag[Num]= 0;              // mark the image good by default
    // increase image counter
    Num++;
   } // if((sb.st_mode & S_IFMT) == S_IFREG){
  }
  fclose( vast_list_of_input_images_with_time_corrections );
 } else {
  // If the file does not exist - never mind
  fprintf( stderr, "list not found.\nThis is OK if you specify the input images on the command line, not through this text file.\n" );
 }

 if ( Num == 1 ) {
  fprintf( stderr, "Only one image was supplied: %s", input_images[0] );
  fprintf( stderr, "Entering single image mode...\n\n" );
  if ( 0 == is_file( input_images[0] ) ) {
   fprintf( stderr, "ERROR: can't open file %s \nIt does not exist or is not readable! :(\n", input_images[0] );
   return 0;
  }
  sprintf( stderr_output, "./sextract_single_image %s\n", input_images[0] );
  fprintf( stderr, "%s", stderr_output );
  if ( 0 != system( stderr_output ) ) {
   fprintf( stderr, "ERROR running  %s\n", stderr_output );
  }
  return 0;
 }

 fprintf( stderr, "\nPreparing to process %d input FITS images...\n", Num );

 if ( Num < HARD_MIN_NUMBER_OF_POINTS && Num != 3 ) {
  fprintf( stderr, "ERROR: At least %d images are needed for correct processing (much more is much better)!\nYou have supplied only %d images. :(\n", HARD_MIN_NUMBER_OF_POINTS, Num );
  fprintf( stderr, "\nThis error message often appears if there is a TYPO IN THE COMMAND LINE argument(s) specifying path to the images.\nPlease double-check the command you type in the terminal.\n\n" );
  // moved up
  // free(file_or_dir_on_command_line);
  return EXIT_FAILURE; // disable the cheating mode
 }

 // Special settings that are forced for the 4-image transient detection mode
 if ( Num == 4 ) {
  fprintf( stderr, "\n\n######## Forcing special settings for the transient detection ########\n" );
  fprintf( stderr, "transient search mode: disabling the mag-size filter as it should be switched off when running a transient search!\n" );
  param_filterout_magsize_outliers= 0;
  fprintf( stderr, "transient search mode: disabling the bad image filter as it will not help during the transient search!\n" );
  param_remove_bad_images= 0;
  fprintf( stderr, "transient search mode: will not try to gues image saturation limit\n" );
  guess_saturation_limit_operation_mode= 0;
  fprintf( stderr, "transient search mode: no UTC-to-TT time system conversion will be performed!!!\n" );
  convert_timesys_to_TT= 0;
  fprintf( stderr, "transient search mode: setting the maximum acceptable SExtractor flag to 3\n" );
  maxsextractorflag= 99; // 3 + 4; // we want to accept all sorts of blended and saturated sources
  fprintf( stderr, "transient search mode: disabling rejectin of images with elliptical stars\n" );
  param_nodiscardell= 1;
  fprintf( stderr, "transient search mode: not discarding large sources\n" );
  param_nodiscardlargesrc= 1;
  fprintf( stderr, "################\n" );
 }

 /// Special mode for manual comparison star selection
 if ( 0 == strcmp( "diffphot", basename( argv[0] ) ) ) {
  diffphot_flag= 1;
  fprintf( stderr, "\n\n######## Applying a set of special settings for the simple differential photometry mode ########\n" );
  fprintf( stderr, "diffphot mode: magnitude calibration type is set to zeropoint offset only\n" );
  photometric_calibration_type= 2;
  fprintf( stderr, "diffphot mode: disabling photocurve support\n" );
  param_use_photocurve= 0;
  fprintf( stderr, "diffphot mode: disabling position-dependent corrections\n" );
  apply_position_dependent_correction= 0;
  fprintf( stderr, "diffphot mode: no UTC-to-TT time system conversion will be performed!!!\n" );
  convert_timesys_to_TT= 0;
  fprintf( stderr, "diffphot mode: disable photometric error rescaling!!!\n" );
  param_rescale_photometric_errors= 0;
  fprintf( stderr, "diffphot mode: will not try to guess image saturation limit\n" );
  guess_saturation_limit_operation_mode= 0;
  maxsextractorflag= 3;
  fprintf( stderr, "diffphot mode: setting the maximum acceptable SExtractor flag to 3\n" );
  param_filterout_magsize_outliers= 0;
  fprintf( stderr, "diffphot mode: disabling magnitude-size outlier filtering\n" );
  fprintf( stderr, "diffphot mode: disabling rejectin of images with elliptical stars\n" );
  param_nodiscardell= 1;
  fprintf( stderr, "diffphot mode: will not display sigma-mag plot after completing the VaST run\n(you may display it manualy by running './find_candidates')\n" );
  param_nofind= 1;
  fprintf( stderr, "diffphot mode: disable automated reference image selection\n" );
  param_automatically_select_reference_image= 0;
  fprintf( stderr, "################\n\n" );
 }

 /// Make photocurve and discard elliptical stars parameters incompatible
 /// (photoplates too often suffer frm bad guiding and low number of images)
 if ( param_nodiscardell == 0 && param_use_photocurve == 1 ) {
  fprintf( stderr, "\n\n######## WARNING ########\n" );
  fprintf( stderr, "Parameter --photocurve is incompatible with elliptical star rejection.\nDisabling eliptical star rejection." );
  param_nodiscardell= 1;
  fprintf( stderr, "################\n\n" );
 }

 // allocate memory for the list of FITS keyword strings
 malloc_size= sizeof( char * ) * ( Num + 1 );
 if ( malloc_size <= 0 ) {
  fprintf( stderr, "ERROR005 - trying to allocate zero or negative number of bytes!\n" );
  return EXIT_FAILURE;
 }
 str_with_fits_keywords_to_capture_from_input_images= (char **)malloc( (size_t)malloc_size );
 if ( str_with_fits_keywords_to_capture_from_input_images == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory!\n str_with_fits_keywords_to_capture_from_input_images = (char **)realloc(input_images, sizeof(char *) * (Num+1)); - failed!\n" );
  return EXIT_FAILURE;
 }
 for ( i= 0; i < Num; i++ ) {
  malloc_size= sizeof( char ) * FITS_KEYWORDS_IN_LC_LENGTH;
  if ( malloc_size <= 0 ) {
   fprintf( stderr, "ERROR006 - trying to allocate zero or negative number of bytes!\n" );
   return EXIT_FAILURE;
  }
  str_with_fits_keywords_to_capture_from_input_images[i]= malloc( (size_t)malloc_size );
  if ( str_with_fits_keywords_to_capture_from_input_images[i] == NULL ) {
   fprintf( stderr, "ERROR: can't allocate memory!\n str_with_fits_keywords_to_capture_from_input_images[i] = malloc(sizeof(char) * FITS_KEYWORDS_IN_LC_LENGTH); - failed!\n" );
   vast_report_memory_error();
   return EXIT_FAILURE;
  }
  // populate the list of keywords to store
  record_specified_fits_keywords( input_images[i], str_with_fits_keywords_to_capture_from_input_images[i] );
 }

 // Num==3, 4, or 5 - is likely the triplet mode for transient detection, we'll skip the usual stupid warnings
 if ( Num > HARD_MIN_NUMBER_OF_POINTS && Num < SOFT_MIN_NUMBER_OF_POINTS && Num != 3 && Num != 4 && Num != 5 && debug == 0 && convert_timesys_to_TT != 0 ) {
  fprintf( stderr, "WARNING: It is recommended to use VaST with more than %d images (much more is much better)!\nYou have supplied only %d images. :(\n", SOFT_MIN_NUMBER_OF_POINTS, Num );
  fprintf( stderr, "\n" );
  fprintf( stderr, "This warning message will disappear in...   " );
  // sleep for 6 seconds to make sure user saw the above message
  for ( n= 5; n > 0; n-- ) {
   sleep( 1 );
   fprintf( stderr, "%d ", n );
  }
  sleep( 1 );
  fprintf( stderr, "NOW!\n" );
 }

 if ( Num < SOFT_MIN_NUMBER_OF_POINTS ) {
  if ( param_rescale_photometric_errors != 0 ) {
   param_rescale_photometric_errors= 0;
   fprintf( stderr, "WARNING: disabling the photometric error rescaling for the small number of input images (%d<%d)!\nYou may run 'util/rescale_photometric_errors' manually after the processing has finished.\n", Num, SOFT_MIN_NUMBER_OF_POINTS );
  }
 }

 //// Print the TT warning only if UTC was not explicitly requested by user.
 if ( convert_timesys_to_TT != 0 && Num != 3 && Num != 4 && Num != 5 ) {
  print_TT_reminder( 0 );
 }

 // The end of the beginning

 // Update PATH variable to make sure the local copy of SExtractor is there
 make_sure_libbin_is_in_path();

 /// Check if the SExtractor executable (named "sex") is present in $PATH
 if ( 0 != system( "lib/look_for_sextractor.sh" ) ) {
  fprintf( stderr, "Error looking for SExtractor. Aborting further computations...\n" );
  return EXIT_FAILURE;
 }

 // Update TAI-UTC file if needed
 if ( 0 != system( "lib/update_tai-utc.sh" ) ) {
  fprintf( stderr, "WARNING: an error occured while trying to update lib/tai-utc.dat\nNo internet connection?\n" );
 }

 // Destroy files created by previous session
 fprintf( stderr, "Cleaning old outNNNNN.dat files.\n" );
 if ( 0 != system( "util/clean_data.sh all >/dev/null" ) ) {
  fprintf( stderr, "Error while cleaning old files. Aborting further computations...\n" );
  return EXIT_FAILURE;
 }
 fprintf( stderr, "Done with cleaning!\n" );

 // Save command line arguments to the log file vast_command_line.log
 save_command_line_to_log_file( argc, argv );

 /// Special mode for manual comparison star selection
 // if( 0 == strcmp("diffphot", basename(argv[0])) ) {
 if ( diffphot_flag == 1 ) {
  fprintf( stderr, "\n\n Select a comparison star with a click and change the measurement aperture by pressing '+'/'-' on the keyboard.\n\n" );
  if ( fixed_aperture != 0.0 ) {
   sprintf( system_command_select_comparison_stars, "lib/select_comparison_stars %s -a %lf", input_images[0], fixed_aperture );
  } else {
   sprintf( system_command_select_comparison_stars, "lib/select_comparison_stars %s", input_images[0] );
  } // else if( fixed_aperture != 0.0 ) {
  if ( 0 != system( system_command_select_comparison_stars ) ) {
   fprintf( stderr, "ERROR running  '%s'\n", system_command_select_comparison_stars );
   // Free memory for a clean exit
   for ( n= Num; n--; ) {
    free( input_images[n] );
   }
   free( input_images );
   //
   return EXIT_FAILURE;
  } else {

   // Check if at least one comparison star was provided
   cmparisonstarsfile= fopen( "manually_selected_comparison_stars.lst", "r" );
   if ( cmparisonstarsfile == NULL ) {
    fprintf( stderr, "No manually selected comparison stars file manually_selected_comparison_stars.lst\n" );
    // Free memory for a clean exit
    for ( n= Num; n--; ) {
     free( input_images[n] );
    }
    free( input_images );
    //
    return EXIT_FAILURE;
   } else {
    N_manually_selected_comparison_stars= 0;
    while ( -1 < fscanf( cmparisonstarsfile, "%lf %lf %lf", &tmp_manually_selected_comparison_stars_X, &tmp_manually_selected_comparison_stars_Y, &tmp_manually_selected_comparison_stars_catalog_mag ) ) {
     N_manually_selected_comparison_stars+= 1;
    }
    fclose( cmparisonstarsfile );
    if ( N_manually_selected_comparison_stars < 1 ) {
     fprintf( stderr, "ERROR too few (%d) comparison stars in manually_selected_comparison_stars.lst or there is aproblem reading the file\n", N_manually_selected_comparison_stars );
     // Free memory for a clean exit
     for ( n= Num; n--; ) {
      free( input_images[n] );
     }
     free( input_images );
     //
     return EXIT_FAILURE;
    }
    N_manually_selected_comparison_stars= 0; // reset the counter for future use
   }
   //

   // Check if the aperture size was manually set by the user
   manually_selected_aperture_txt_file= fopen( "manually_selected_aperture.txt", "r" );
   if ( NULL != manually_selected_aperture_txt_file ) {
    if ( 1 != fscanf( manually_selected_aperture_txt_file, "%lf", &manually_selected_aperture ) ) {
     fprintf( stderr, "ERROR parsing manually_selected_aperture.txt\n" );
    } else {
     if ( manually_selected_aperture < 1.0 ) {
      fprintf( stderr, "ERROR: the manually selected aperture diameter from manually_selected_aperture.txt is too small: %lf < 1.0\n", manually_selected_aperture );
     } else {
      fixed_aperture= manually_selected_aperture;
      fprintf( stderr, "Using %lf pix diameter aperture for the whole image series \n", fixed_aperture );
     } // else if( manually_selected_aperture< 1.0 ) {
    } // else if( 1 != fscanf(manually_selected_aperture_txt_file,"%lf",&manually_selected_aperture) ) {
    fclose( manually_selected_aperture_txt_file );
   } // if( NULL != manually_selected_aperture_txt_file ) {
   //

  } // else if( 0 != system(system_command_select_comparison_stars) ) {

 } // if ( 0 == strcmp( "diffphot", basename( argv[0] ) ) ) {

 ///// Start timer /////
 start_time= time( NULL );

 // Allocate memory for moving object coordinates
 // we only need it for user-specified moving object (moving_object==1)
 // but we want to avoid compiler warning about possible unitizlized memory use
 moving_object__user_array_x= malloc( Num * sizeof( float ) );
 moving_object__user_array_y= malloc( Num * sizeof( float ) );
 //
 memset( moving_object__user_array_x, 0, Num * sizeof( float ) );
 memset( moving_object__user_array_y, 0, Num * sizeof( float ) );
 //////////////////

 //////////////////////////////////////////////////////////////////////////////////////////////////////////////
 /////// Reading file which defines rectangular regions we want to completely exclude from the analysis ///////
 //////////////////////////////////////////////////////////////////////////////////////////////////////////////
 double *X1;
 double *Y1;
 double *X2;
 double *Y2;
 int max_N_bad_regions_for_malloc;
 max_N_bad_regions_for_malloc= count_lines_in_ASCII_file( "bad_region.lst" );
 X1= (double *)malloc( max_N_bad_regions_for_malloc * sizeof( double ) );
 Y1= (double *)malloc( max_N_bad_regions_for_malloc * sizeof( double ) );
 X2= (double *)malloc( max_N_bad_regions_for_malloc * sizeof( double ) );
 Y2= (double *)malloc( max_N_bad_regions_for_malloc * sizeof( double ) );
 if ( X1 == NULL || Y1 == NULL || X2 == NULL || Y2 == NULL ) {
  fprintf( stderr, "ERROR: cannot allocate memory for exclusion regions array X1, Y1, X2, Y2\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 int N_bad_regions= 0;
 read_bad_CCD_regions_lst( X1, Y1, X2, Y2, &N_bad_regions );

 //////////////////////////////////////////////////////////////////////////////////////////
 /////// Reading file with stars which should not be used for magnitude calibration ///////
 //////////////////////////////////////////////////////////////////////////////////////////
 // The stars are specified with their X Y positions on the reference frame
 // FILE *excludefile;
 // N_bad_stars= 1 + count_lines_in_ASCII_file("exclude.lst");
 N_bad_stars= count_lines_in_ASCII_file( "exclude.lst" );
 bad_stars_X= malloc( N_bad_stars * sizeof( double ) );
 if ( bad_stars_X == NULL ) {
  fprintf( stderr, "ERROR: cannot allocate memory for bad_stars_X\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 bad_stars_Y= malloc( N_bad_stars * sizeof( double ) );
 if ( bad_stars_Y == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory for bad_stars_Y\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 read_exclude_stars_on_ref_image_lst( bad_stars_X, bad_stars_Y, &N_bad_stars );

 ///// From now on, ignore SIGHUP! /////
 signal( SIGHUP, SIG_IGN );

 ///// Starting real work! /////

 // Set up coordinate system transofrmation structure
 if ( param_w == 0 || param_w == 4 ) {
  struct_pixel_coordinate_transformation= New_PixCoordinateTransformation();
  if ( param_w == 4 ) {
   struct_pixel_coordinate_transformation->sigma_popadaniya= fixed_star_matching_radius_pix;
   fprintf( stderr, "Setting the fixed star match radius of %.2lf pix\n", fixed_star_matching_radius_pix );
  }
 }

 if ( param_set_manually_Number_of_main_star == 0 ) {
  // Remamber default struct_pixel_coordinate_transformation parameters
  default_Number_of_ecv_triangle= struct_pixel_coordinate_transformation->Number_of_ecv_triangle;
  default_Number_of_main_star= struct_pixel_coordinate_transformation->Number_of_main_star;
 } else {
  // Or set parameters supplied by user
  struct_pixel_coordinate_transformation->Number_of_ecv_triangle= default_Number_of_ecv_triangle;
  struct_pixel_coordinate_transformation->Number_of_main_star= default_Number_of_main_star;
 }

 fprintf( stderr, "We have %d images to process.\n", Num );

 // Debug the input image list
 // for(i=0;i<Num;i++)
 // fprintf(stderr,"%s\n",input_images[i]);

 // Create vast_images_catalogs.log
 write_images_catalogs_logfile( input_images, Num );

 int n_fork;    //=get_number_of_cpu_cores(); // number of parallel threads
 int i_fork= 0; // counter for fork
 int j_fork;    // another counter for fork
 int fork_found_empty_slot;
 int pid_of_child_that_finished;
 int pid_status;
 int *child_pids;

 // Set the desired number of threads
 n_fork= get_number_of_cpu_cores();

#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
 // While we want to use all the available cores to run SExtractor via fork(),
 // tests show that limiting the number of OpenMP threads dramatically improves performance.
 omp_set_num_threads( MIN( n_fork, 48 ) );
#endif
#endif

 malloc_size= n_fork * sizeof( int );
 if ( malloc_size <= 0 ) {
  fprintf( stderr, "ERROR007 - trying to allocate zero or negative number of bytes!\n" );
  return EXIT_FAILURE;
 }
 child_pids= malloc( (size_t)malloc_size );
 if ( child_pids == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory!\n child_pids=malloc(n_fork*sizeof(int)); - failed!\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }

 fprintf( stderr, "Running SExtractor in %d parallel threads...\n", MIN( n_fork, Num ) );
 // Initialize child_pids
 for ( j_fork= 0; j_fork < n_fork; j_fork++ ) {
  child_pids[j_fork]= 0;
 }
 //
 for ( i= 0; i < Num; i++ ) {
  fitsfile_read_error= gettime( input_images[i], &JD, &timesys, convert_timesys_to_TT, &X_im_size, &Y_im_size, stderr_output, log_output, param_nojdkeyword, 0, NULL );
  if ( fitsfile_read_error != 0 && i == 0 ) {
   fprintf( stderr, "Error reading reference file: code %d\nI'll die :(\n", fitsfile_read_error );
   fits_report_error( stderr, fitsfile_read_error );
   exit( fitsfile_read_error );
  } else {
   //////////////////////////////////////////////////////////////
   i_fork++;
   pid= fork();
   if ( pid == 0 || pid == -1 ) {
    if ( pid == -1 ) {
     fprintf( stderr, "WARNING: cannot fork()! Continuing in the streamline mode...\n" );
    }
    autodetect_aperture( input_images[i], sextractor_catalog, 0, param_P, fixed_aperture, X_im_size, Y_im_size, guess_saturation_limit_operation_mode );
    if ( pid == 0 ) {
     ///// If this is a child /////
     // free-up memory
     if ( debug != 0 ) {
      fprintf( stderr, "DEBUG MSG %d: CHILD free();\n", getpid() );
     }
     free( child_pids );
     free( ptr_struct_Obs );
     free( STAR3 ); // I don't think these are allocated at this point. Are they?
     free( STAR1 ); // I don't think these are allocated at this point. Are they?
     free( bad_stars_X );
     free( bad_stars_Y );
     if ( debug != 0 ) {
      fprintf( stderr, "DEBUG MSG %d: for(n = 0; n < Num; n++)free(input_images[n]);\n", getpid() );
     }
     for ( n= Num; n--; ) {
      free( input_images[n] );
     }
     if ( debug != 0 ) {
      fprintf( stderr, "DEBUG MSG %d: free(input_images);\n", getpid() );
     }
     free( input_images );
     //
     for ( n= Num; n--; ) {
      free( str_with_fits_keywords_to_capture_from_input_images[n] );
     }
     free( str_with_fits_keywords_to_capture_from_input_images );
     if ( debug != 0 ) {
      fprintf( stderr, "DEBUG MSG %d: Delete_PixCoordinateTransformation(struct_pixel_coordinate_transformation);\n", getpid() );
     }
     Delete_PixCoordinateTransformation( struct_pixel_coordinate_transformation );
     if ( debug != 0 ) {
      fprintf( stderr, "DEBUG MSG %d: CHILD free() -- still alive\n", getpid() );
     }
     //
     exit( EXIT_SUCCESS ); // exit only if this is actually a child
    } // if ( pid == 0 ) {
    // the other possibility is that this is a parent that could not fork - no exit in this case
   } else {
    // child_pids[i_fork-1]=pid;
    for ( fork_found_empty_slot= 0, j_fork= 0; j_fork < n_fork; j_fork++ ) {
     if ( child_pids[j_fork] == 0 ) {
      child_pids[j_fork]= pid;
      fork_found_empty_slot= 1;
      break;
     }
    }
    if ( fork_found_empty_slot != 1 ) {
     fprintf( stderr, "FATAL ERROR 11\n" );
     return EXIT_FAILURE;
    }
    ///// #####################################
    if ( i_fork == MIN( n_fork, Num ) ) {
     // Wait for any child process to finish
     pid_of_child_that_finished= waitpid( -1, &pid_status, 0 );
     for ( j_fork= 0; j_fork < i_fork; j_fork++ ) {
      if ( pid_of_child_that_finished == child_pids[j_fork] ) {
       child_pids[j_fork]= 0;
       i_fork--;
       break;
      }
     }
     // i_fork--;
     /// Seems to work, but pid_status array gets corrupted
     // Check if any of the children is done
     // for(j_fork=0;j_fork<i_fork;j_fork++){
     // waitpid(child_pids[j_fork],&pid_status,WNOHANG);
     //}
    }
    ///// #####################################
   } // else // if( pid==0 || pid==-1 ){
   //////////////////////////////////////////////////////////////
  } // else // if (fitsfile_read_error != 0 && i==0 ) {
 } // for(i=0;i<Num;i++){

 fprintf( stderr, "Parent process says: we are done fork()ing.\n" );

 // Here is a wild assumption: if we have more than 100 images,
 // the remaining few will be processed while we are starting
 // to match star lists corresponding to the first few images.
 //
 // n_fork>16 condition is here because the above wild assumption will not
 // work on a highly multi-core system!
 if ( Num < 100 || param_automatically_select_reference_image == 1 || moving_object == 1 || n_fork > 16 || param_nodiscardell == 0 ) {
  for ( ; i_fork--; ) {
   fprintf( stderr, "Waiting for thread %d to finish...\n", i_fork + 1 );
   if ( i_fork < 0 )
    break;
   pid= child_pids[i_fork];
   waitpid( pid, &pid_status, 0 );
  }

  // It seems the above logic may leave off one still running thread???
  // We'll catch it with the while cycle below
  // https://stackoverflow.com/questions/19461744/how-to-make-parent-wait-for-all-child-processes-to-finish
  while ( ( pid_of_child_that_finished= wait( &pid_status ) ) > 0 )
   ; // this way, the parent waits for all the child processes

  // Sleep 1sec to make sure the image cataog files are actually populated.
  // It seems that sometimes the followin functions read the the image ctalogs before
  // they are actually written despite the above thread has already finished.
  // This is an extra precaution as the problem seems to be solved by the above wait loop.
  // sleep(1);

  fprintf( stderr, "\n\nDone with SExtractor!\n\n" );

  // Elongated image star mark and automatic reference image selection cannot work with
  // the fast processing hack: they need all the image catalogs to be present.

  // Mark images with elongated stars as bad
  if ( param_nodiscardell == 0 ) {
   mark_images_with_elongated_stars_as_bad( input_images, vast_bad_image_flag, Num );
  }

  // Choose the reference image if we were asked to (otherwise the first image will be used)
  if ( param_automatically_select_reference_image == 1 ) {
   choose_best_reference_image( input_images, vast_bad_image_flag, Num );
  }

  if ( moving_object == 1 ) {
   // Try to read the input file with moving object positions
   if ( 0 != read_input_file_with_user_specified_moving_object_position( input_images, moving_object__user_array_x, moving_object__user_array_y, Num ) ) {
    // if no input file - ask user to specify the moving object position interactively
    ask_user_to_click_on_moving_object( input_images, moving_object__user_array_x, moving_object__user_array_y, Num );
   }
  }

 } else {
  fprintf( stderr, "Fast processing hack: continue to star matching while SExtractor is still computing!\n" );
 }

 fprintf( stderr, "\n\nMatching stars between images!\n\n" );

 //  Allocate memory for arrays with coordinates.
 malloc_size= MAX_NUMBER_OF_STARS * sizeof( int );
 if ( malloc_size <= 0 ) {
  fprintf( stderr, "ERROR008 - trying to allocate zero or negative number of bytes!\n" );
  return EXIT_FAILURE;
 }
 number_of_coordinate_measurements_for_star= malloc( (size_t)malloc_size );
 if ( number_of_coordinate_measurements_for_star == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory for number_of_coordinate_measurements_for_star\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 malloc_size= MAX_NUMBER_OF_STARS * sizeof( int );
 if ( malloc_size <= 0 ) {
  fprintf( stderr, "ERROR009 - trying to allocate zero or negative number of bytes!\n" );
  return EXIT_FAILURE;
 }
 star_numbers_for_coordinate_arrays= malloc( (size_t)malloc_size );
 if ( star_numbers_for_coordinate_arrays == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory for star_numbers_for_coordinate_arrays\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 malloc_size= MAX_NUMBER_OF_STARS * sizeof( float * );
 if ( malloc_size <= 0 ) {
  fprintf( stderr, "ERROR010 - trying to allocate zero or negative number of bytes!\n" );
  return EXIT_FAILURE;
 }
 coordinate_array_x= malloc( (size_t)malloc_size );
 if ( coordinate_array_x == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory for coordinate_array_x\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 malloc_size= MAX_NUMBER_OF_STARS * sizeof( float * );
 if ( malloc_size <= 0 ) {
  fprintf( stderr, "ERROR011 - trying to allocate zero or negative number of bytes!\n" );
  return EXIT_FAILURE;
 }
 coordinate_array_y= malloc( (size_t)malloc_size );
 if ( coordinate_array_y == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory for coordinate_array_y\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 coordinate_array_counter= 0;
 // Inititalize the coordinate arrays just to make debugger happy
 for ( i= MAX_NUMBER_OF_STARS; i--; ) {
  coordinate_array_x[i]= NULL;
  coordinate_array_y[i]= NULL;
  star_numbers_for_coordinate_arrays[i]= 0;
  number_of_coordinate_measurements_for_star[i]= 0;
 }

 // I want this after fork()
 ////////////////////////////////////////////////////////////////////
 /////// Reading file with manually selected comparison stars ///////
 ////////////////////////////////////////////////////////////////////
 // The stars are specified with their X Y positions on the reference frame
 manually_selected_comparison_stars_X= malloc( sizeof( double ) );
 if ( manually_selected_comparison_stars_X == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory for manually_selected_comparison_stars_X\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 manually_selected_comparison_stars_Y= malloc( sizeof( double ) );
 if ( manually_selected_comparison_stars_Y == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory for manually_selected_comparison_stars_Y\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 manually_selected_comparison_stars_catalog_mag= malloc( sizeof( double ) );
 if ( manually_selected_comparison_stars_catalog_mag == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory for manually_selected_comparison_stars_catalog_mag\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 cmparisonstarsfile= fopen( "manually_selected_comparison_stars.lst", "r" );
 if ( cmparisonstarsfile == NULL ) {
  fprintf( stderr, "No manually selected comparison stars file manually_selected_comparison_stars.lst which is fine.\n" );
  // return EXIT_FAILURE;
  //  We should not quit if there is no manually_selected_comparison_stars.lst
 } else {
  while ( -1 < fscanf( cmparisonstarsfile, "%lf %lf %lf",
                       &manually_selected_comparison_stars_X[N_manually_selected_comparison_stars],
                       &manually_selected_comparison_stars_Y[N_manually_selected_comparison_stars],
                       &manually_selected_comparison_stars_catalog_mag[N_manually_selected_comparison_stars] ) ) {
   manually_selected_comparison_stars_X= realloc( manually_selected_comparison_stars_X, sizeof( double ) * ( N_manually_selected_comparison_stars + 2 ) );
   manually_selected_comparison_stars_Y= realloc( manually_selected_comparison_stars_Y, sizeof( double ) * ( N_manually_selected_comparison_stars + 2 ) );
   manually_selected_comparison_stars_catalog_mag= realloc( manually_selected_comparison_stars_catalog_mag, sizeof( double ) * ( N_manually_selected_comparison_stars + 2 ) );
   N_manually_selected_comparison_stars+= 1;
  }
  fclose( cmparisonstarsfile );
  fprintf( stderr, "Loaded %d manually selected compariosn stars from manually_selected_comparison_stars.lst file\n", N_manually_selected_comparison_stars );
  if ( N_manually_selected_comparison_stars < 1 ) {
   fprintf( stderr, "ERROR: too few comparison stars loaded\n" );
   // probably some manual memory free-up should be here
   return EXIT_FAILURE;
  }
  photometric_calibration_type= 2;
  fprintf( stderr, "Resetting the magnitude calibration mode to zero-point offset only!\n\n\n" );
 }
 ////////////////////////////////////////////////////////////////////

 // Process the reference image
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: (ref) gettime(input_images[0])\n" ); // Debug message!
 fitsfile_read_error= gettime( input_images[0], &JD, &timesys, convert_timesys_to_TT, &X_im_size, &Y_im_size, stderr_output, log_output, param_nojdkeyword, 1, NULL );
 if ( fitsfile_read_error != 0 ) {
  fprintf( stderr, "Error reading reference file: code %d\nI'll die :(\n", fitsfile_read_error );
  fits_report_error( stderr, fitsfile_read_error );
  exit( fitsfile_read_error );
 }
 // frame.X_centre = X_im_size / 2;
 // frame.Y_centre = Y_im_size / 2;
 max_X_im_size= X_im_size;
 max_Y_im_size= Y_im_size;

 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: (ref) autodetect_aperture(input_images[0])\n" );
 aperture= autodetect_aperture( input_images[0], sextractor_catalog, 0, param_P, fixed_aperture, X_im_size, Y_im_size, guess_saturation_limit_operation_mode );
 if ( aperture > 75 || aperture < 1.0 ) {
  // TBA: wait so the error message doesn't get swamped
  fprintf( stderr, "APERTURE = %.1lf is > 75.0 or < 1.0\nBad reference image...\n", aperture );
  write_string_to_individual_image_log( sextractor_catalog, "main(): ", "Bad reference image: the estimated aperture is out of range!", "" );
  return EXIT_FAILURE;
 }
 reference_image_aperture= aperture;
 if ( param_w == 0 ) {
  struct_pixel_coordinate_transformation->sigma_popadaniya= AUTO_SIGMA_POPADANIYA_COEF * aperture;
  fprintf( stderr, "Setting the star matching radius to %.2lf pix\n", struct_pixel_coordinate_transformation->sigma_popadaniya );
 }

 fprintf( stderr, "%s", stderr_output );
 // fprintf(stderr,"----------------%s----------------\n",sextractor_catalog);
 write_string_to_log_file( log_output, sextractor_catalog );

 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: (ref) Read_sex_cat(%s and other stuff)\n", sextractor_catalog );

 // NUMBER1 is the number of stars on the reference frame

 counter_rejected_bad_psf_fit= 0; // just in case
 // if( param_P==1 )filter_out_bad_psf_fits_from_catalog(sextractor_catalog,&counter_rejected_bad_psf_fit);

 // Count lines in the reference image catalog, so we know how much memory to allocate
 number_of_lines_reference_image_cat= count_lines_in_ASCII_file( sextractor_catalog );
 if ( 0 == number_of_lines_reference_image_cat ) {
  fprintf( stderr, "ERROR: %d lines in file %s\n", number_of_lines_reference_image_cat, sextractor_catalog );
  return EXIT_FAILURE;
 }
 //

 file= fopen( sextractor_catalog, "r" );
 if ( file == NULL ) {
  fprintf( stderr, "Can't open file %s\n", sextractor_catalog );
  return EXIT_FAILURE;
 } else {
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: Opened file %s\n", sextractor_catalog );
 }
 malloc_size= MAX_NUMBER_OF_STARS * sizeof( struct Star );
 if ( malloc_size <= 0 ) {
  fprintf( stderr, "ERROR012 - trying to allocate zero or negative number of bytes!\n" );
  return EXIT_FAILURE;
 }
 STAR1= malloc( (size_t)malloc_size );
 if ( STAR1 == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory!\n STAR1=malloc(MAX_NUMBER_OF_STARS*sizeof(struct Star)); - failed!\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 // malloc_size= MAX_NUMBER_OF_STARS * sizeof( struct Star );
 malloc_size= number_of_lines_reference_image_cat * sizeof( struct Star );
 if ( malloc_size <= 0 ) {
  fprintf( stderr, "ERROR013 - trying to allocate zero or negative number of bytes!\n" );
  return EXIT_FAILURE;
 }
 STAR3= malloc( (size_t)malloc_size );
 if ( STAR3 == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory!\n STAR3=malloc(MAX_NUMBER_OF_STARS*sizeof(struct Star)); - failed!\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 //---------------------------------------
 // Determine SExtractor catalog format //
 // if( NULL==fgets(sextractor_catalog_string,MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT,file) ){fprintf(stderr,"ERROR determining SExtractor catalog format!\n");}
 counter_rejected_bad_flux= counter_rejected_low_snr= counter_rejected_bad_region= counter_rejected_frame_edge= counter_rejected_too_small= counter_rejected_too_large= counter_rejected_external_flag= counter_rejected_seflags_gt7= counter_rejected_MagSize= counter_rejected_seflags_gt_user_spec_threshold= 0; // reset bad star counters
 //---------------------------------------
 previous_star_number_in_sextractor_catalog= 0;
 for ( NUMBER1= 0, NUMBER3= 0;; ) {
  if ( debug != 0 )
   fprintf( stderr, "Reading a catalog line NUMBER1=%d NUMBER3=%d \n", NUMBER1, NUMBER3 );
  if ( NULL == fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, file ) ) {
   break;
  }
  sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT - 1]= '\0'; // just in case
  external_flag= 0;
  // external_flag_string[0]='\0';
  if ( 0 != parse_sextractor_catalog_string( sextractor_catalog_string, &star_number_in_sextractor_catalog, &flux_adu, &flux_adu_err, &mag, &sigma_mag, &position_x_pix, &position_y_pix, &a_a, &a_a_err, &a_b, &a_b_err, &sextractor_flag, &external_flag, &psf_chi2, float_parameters ) ) {
   fprintf( stderr, "WARNING: problem occurred while parsing SExtractor catalog %s\nThe offending line is:\n%s\n", sextractor_catalog, sextractor_catalog_string );
   continue;
  }
  // Read only stars detected at the first FITS image extension.
  // The start of the second image extension will be signified by a jump in star numbering
  if ( star_number_in_sextractor_catalog < previous_star_number_in_sextractor_catalog ) {
   fprintf( stderr, "WARNING: the input SExtractor catalog is not sorted. Was this catalog created from a multi-extension FITS? In this case, only sources detected on the first image extension will be processed!\n" );
   break;
  } else {
   previous_star_number_in_sextractor_catalog= star_number_in_sextractor_catalog;
  }
  // Check if the catalog line is a really band one
  if ( flux_adu <= 0 ) {
   counter_rejected_bad_flux++;
   continue;
  }
  if ( flux_adu_err == 999999 ) {
   counter_rejected_bad_flux++;
   continue;
  }
  if ( mag == 99.0000 ) {
   counter_rejected_bad_flux++;
   continue;
  }
  if ( sigma_mag == 99.0000 ) {
   counter_rejected_bad_flux++;
   continue;
  }
  // If we have no error estimates in at least one aperture - assume things are bad with this object
  if ( float_parameters[3] == 99.0000 ) {
   counter_rejected_bad_flux++;
   continue;
  }
  if ( float_parameters[5] == 99.0000 ) {
   counter_rejected_bad_flux++;
   continue;
  }
  if ( float_parameters[7] == 99.0000 ) {
   counter_rejected_bad_flux++;
   continue;
  }
  if ( float_parameters[9] == 99.0000 ) {
   counter_rejected_bad_flux++;
   continue;
  }
  if ( float_parameters[11] == 99.0000 ) {
   counter_rejected_bad_flux++;
   continue;
  }
//
#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
  if ( mag < BRIGHTEST_STARS ) {
   counter_rejected_bad_flux++;
   continue;
  }
  if ( mag > FAINTEST_STARS_ANYMAG ) {
   counter_rejected_bad_flux++;
   continue;
  }
  if ( sigma_mag > MAX_MAG_ERROR ) {
   counter_rejected_low_snr++;
   continue;
  }
#endif
  //
  if ( flux_adu < MIN_SNR * flux_adu_err ) {
   counter_rejected_low_snr++;
   continue;
  }
  if ( 0 != exclude_region( X1, Y1, X2, Y2, N_bad_regions, position_x_pix, position_y_pix, aperture ) ) {
   if ( counter_rejected_bad_region < 10 ) {
    fprintf( stderr, "The reference image star %9.3lf %9.3lf is rejected, see bad_region.lst\n", position_x_pix, position_y_pix );
   }
   if ( counter_rejected_bad_region == 10 ) {
    fprintf( stderr, "Excluding more reference image stars falling at bad regions!.. (will not print them all)\n" );
   }
   counter_rejected_bad_region++;
   continue;
  }
  if ( 1 == is_point_close_or_off_the_frame_edge( position_x_pix, position_y_pix, X_im_size, Y_im_size, FRAME_EDGE_INDENT_PIXELS ) ) {
   counter_rejected_frame_edge++;
   continue;
  }
  //
  if ( CONST * ( a_a + a_a_err ) < MIN_SOURCE_SIZE_APERTURE_FRACTION * aperture ) {
   counter_rejected_too_small++;
   continue;
  }
  //
  if ( SIGMA_TO_FWHM_CONVERSION_FACTOR * ( a_a + a_a_err ) < FWHM_MIN ) {
   counter_rejected_too_small++;
   continue;
  }
  if ( SIGMA_TO_FWHM_CONVERSION_FACTOR * ( a_b + a_b_err ) < FWHM_MIN ) {
   counter_rejected_too_small++;
   continue;
  }
  // FWHM may be incoorectly set to 0.0 for a saaturated object
  if ( MAX( float_parameters[0], SIGMA_TO_FWHM_CONVERSION_FACTOR * a_a ) < FWHM_MIN ) {
   counter_rejected_too_small++;
   continue;
  }
  //
  if ( external_flag != 0 ) {
   counter_rejected_external_flag++;
   continue;
  }
  //
  if ( maxsextractorflag < sextractor_flag && sextractor_flag <= 7 ) {
   counter_rejected_seflags_gt_user_spec_threshold++;
   // We don't drop such objects here to keep 'em in STAR structure,
   // they will be rejected later when saving the observations.
  }
  // just in case we mark objects with really bad SExtractor flags
  // sextractor_flag != 20 -- accept a super-bright saturated object
  if ( sextractor_flag > 7 && sextractor_flag != 20 ) {
   counter_rejected_seflags_gt7++;
   continue;
  }
  //
  NUMBER1++;
  NUMBER3++;
  STAR1[NUMBER1 - 1].vast_flag= 0;
  //
  STAR1[NUMBER1 - 1].n_detected= 0; // init
  STAR1[NUMBER1 - 1].n_rejected= 0; // init
                                    //
  // It is OK for a very bright saturated object to be big
  // if ( a_a > 5*aperture && sextractor_flag < 4 ) {
  if ( a_a > aperture && sextractor_flag < 4 && 0 == param_nodiscardlargesrc ) {
   counter_rejected_too_large++;
   STAR1[NUMBER1 - 1].vast_flag= 1;
  }

  STAR1[NUMBER1 - 1].n= star_number_in_sextractor_catalog;
  STAR1[NUMBER1 - 1].x_frame= STAR1[NUMBER1 - 1].x= (float)position_x_pix;
  STAR1[NUMBER1 - 1].y_frame= STAR1[NUMBER1 - 1].y= (float)position_y_pix;
  // for moving object match
  STAR1[NUMBER1 - 1].moving_object= 0;
  if ( moving_object == 1 ) {
   if ( 0.0 < position_x_pix && position_x_pix < MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
    if ( 0.0 < position_y_pix && position_y_pix < MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
     if ( 0.0 < moving_object__user_array_x[0] && moving_object__user_array_x[0] < MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
      if ( 0.0 < moving_object__user_array_y[0] && moving_object__user_array_y[0] < MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
       if ( ( position_x_pix - moving_object__user_array_x[0] ) * ( position_x_pix - moving_object__user_array_x[0] ) + ( position_y_pix - moving_object__user_array_y[0] ) * ( position_y_pix - moving_object__user_array_y[0] ) < 1.0 ) {
        STAR1[NUMBER1 - 1].moving_object= 1;
        snprintf( str_moving_object_lightcurve_file, OUTFILENAME_LENGTH, "out%05d.dat", STAR1[NUMBER1 - 1].n );
        // fprintf(stderr,"DEBUG: here is the moving object on REF FRAME!!!\n");
       }
      }
     }
    }
   }
  }
  //
  STAR1[NUMBER1 - 1].flux= flux_adu;
  STAR1[NUMBER1 - 1].flux_err= flux_adu_err;
  STAR1[NUMBER1 - 1].mag= (float)mag;
  STAR1[NUMBER1 - 1].sigma_mag= (float)sigma_mag;
  STAR1[NUMBER1 - 1].JD= JD;
  STAR1[NUMBER1 - 1].detected_on_ref_frame= 1;               // Mark the star that it was detected on the reference frame and not added later
  STAR1[NUMBER1 - 1].sextractor_flag= (char)sextractor_flag; // SExtractor flag
  STAR1[NUMBER1 - 1].star_size= (float)a_a;
  //
  STAR1[NUMBER1 - 1].star_psf_chi2= (float)psf_chi2;
  //
  for ( float_parameters_counter= NUMBER_OF_FLOAT_PARAMETERS; float_parameters_counter--; ) {
   STAR1[NUMBER1 - 1].float_parameters[float_parameters_counter]= float_parameters[float_parameters_counter];
  }
  // If there are manually supplied calibration stars - write calib.txt
  if ( N_manually_selected_comparison_stars > 0 ) {
   manually_selected_comparison_stars_index= exclude_test( position_x_pix, position_y_pix, manually_selected_comparison_stars_X, manually_selected_comparison_stars_Y, N_manually_selected_comparison_stars, 0 );
   if ( manually_selected_comparison_stars_index != -1 ) {
    calibtxtfile= fopen( "calib.txt", "a" );
    if ( calibtxtfile == NULL ) {
     fprintf( stderr, "ERROR: cannot open file calib.txt for writing!\n" );
     return EXIT_FAILURE;
    }
    // -13.5161 14.4000 0.0032
    fprintf( calibtxtfile, "%lf %lf %lf\n", mag, manually_selected_comparison_stars_catalog_mag[manually_selected_comparison_stars_index], sigma_mag );
    fclose( calibtxtfile );
   }
  }
  // Use only good stars for coordinate transformation
  if ( STAR1[NUMBER1 - 1].sextractor_flag <= 7 && STAR1[NUMBER1 - 1].vast_flag == 0 ) {
   Star_Copy( STAR3 + NUMBER3 - 1, STAR1 + NUMBER1 - 1 );
  } else {
   NUMBER3--;
  }
 }
 fclose( file );
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: image00001.cat was closed...\n" );
 // end of Read_sex_cat2

 if ( param_P == 1 ) {
  fprintf( stderr, "Filtering-out stars with bad PSF fit... " );
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: filter_MagPSFchi2()\n" );
  if ( param_filterout_magsize_outliers == 1 ) {
   /// !!! Disable PSF fit quality filter - it never works well (see also below) !!!
   //   counter_rejected_bad_psf_fit= filter_on_float_parameters(STAR1, NUMBER1, sextractor_catalog, -2); // psfchi2
   counter_rejected_bad_psf_fit= 0;
  }
  fprintf( stderr, "done!\n" );
 } else {
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: NOT RUNNING filter_MagPSFchi2()\n" );
  counter_rejected_bad_psf_fit= 0; // no PSF-fitting (and filtering)
 }

 // Flag outliers in the magnitude-size plot
 if ( param_filterout_magsize_outliers == 1 ) {
  fprintf( stderr, "Filtering-out outliers in the mag-size plot... " );
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(-1)\n" );
  counter_rejected_MagSize= filter_on_float_parameters( STAR1, NUMBER1, sextractor_catalog, -1 ); // replacement of filter_MagSize()
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(0)\n" );
  counter_rejected_MagSize+= filter_on_float_parameters( STAR1, NUMBER1, sextractor_catalog, 0 );
  // OK, let's count these filters as size-filters too for now
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(1)\n" );
  counter_rejected_MagSize+= filter_on_float_parameters( STAR1, NUMBER1, sextractor_catalog, 1 );
  //
  //
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(4)\n" );
  counter_rejected_MagSize+= filter_on_float_parameters( STAR1, NUMBER1, sextractor_catalog, 4 );
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(6)\n" );
  counter_rejected_MagSize+= filter_on_float_parameters( STAR1, NUMBER1, sextractor_catalog, 6 );
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(8)\n" );
  counter_rejected_MagSize+= filter_on_float_parameters( STAR1, NUMBER1, sextractor_catalog, 8 );
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(10)\n" );
  counter_rejected_MagSize+= filter_on_float_parameters( STAR1, NUMBER1, sextractor_catalog, 10 );
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(12)\n" );
  counter_rejected_MagSize+= filter_on_float_parameters( STAR1, NUMBER1, sextractor_catalog, 12 );
  fprintf( stderr, "done!\n" );
 } else {
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: filter_on_float_parameters()\n" );
  counter_rejected_MagSize= 0; // no filtering on mag-size is done
 }

 // Print out input catalog filtering stats
 sprintf( sextractor_catalog_filtering_results_string, "SExtractor output filtering results:\n * passed selection: %d, (%d good for image matching)\n * rejected as having no flux measurement: %d\n * rejected as having SNR<%.1lf: %d\n * rejected inside rectangles defined in bad_region.lst: %d\n * rejected close to frame edge: %d\n * rejected as being too small (<%.1lf pix): %d\n * rejected as being too large (>%.1lf pix): %d\n * rejected as outliers in mag-size plot: %d\n * rejected as having SExtractor flags > %d and <= 7: %d\n * rejected as having hopelessly bad SExtractor flags (>7): %d\n * rejected due to an external image flag: %d\n * rejected as having bad PSF fit: %d\n---\n",
          NUMBER1,
          NUMBER3,
          counter_rejected_bad_flux,
          MIN_SNR,
          counter_rejected_low_snr,
          counter_rejected_bad_region,
          counter_rejected_frame_edge,
          MAX( FWHM_MIN, MIN_SOURCE_SIZE_APERTURE_FRACTION * aperture ),
          counter_rejected_too_small,
          aperture,
          counter_rejected_too_large,
          counter_rejected_MagSize,
          maxsextractorflag, counter_rejected_seflags_gt_user_spec_threshold,
          counter_rejected_seflags_gt7,
          counter_rejected_external_flag,
          counter_rejected_bad_psf_fit );
 write_string_to_individual_image_log( sextractor_catalog, "main(): ", sextractor_catalog_filtering_results_string, "" );
 fputs( sextractor_catalog_filtering_results_string, stderr );
 fprintf( stderr, "You may change some of the filtering parameters by editing src/vast_limits.h and re-running 'make'.\n" );
 // Check the stats and issue warnings if needed
 if ( (double)counter_rejected_too_small / (double)NUMBER1 > 0.3 && counter_rejected_too_small > 3 ) {
  fprintf( stderr, "\x1B[01;31m WARNING: \x1B[33;00m suspiciously many stars are rejected as being too small. Please check FWHM_MIN in src/vast_limits.h and re-run 'make' if you change it.\n" );
 }

 /* Check if enough stars were detected on the reference frame */
 if ( NUMBER1 < MIN_NUMBER_OF_STARS_ON_FRAME || NUMBER3 < MIN_NUMBER_OF_STARS_ON_FRAME ) {
  // Wait for the children to finish or the error message will be swamped in the normal output
  pid_t wpid;
  int waitstatus;
  while ( ( wpid= wait( &waitstatus ) ) > 0 )
   ; // this way, the father waits for all the child processes
  //
  fprintf( stderr, "ERROR! Too few stars detected on the reference frame: %d<%d\n", NUMBER1, MIN_NUMBER_OF_STARS_ON_FRAME );
  fprintf( stderr, "\nPlease check that the reference image file is readable and looks reasonably good.\n" );
  fprintf( stderr, "\nThe SExtractor catalog for the reference image may be found in image00001.cat \n" );
  if ( param_P == 1 )
   fprintf( stderr, "\nCheck that GAIN parameter in the default.sex file is set to a value >0.0 \n" );
  return EXIT_FAILURE;
 }

 /* Set distance to the closest star in the structure: will be useful for star matching later... */
 // set_distance_to_neighbor_in_struct_Star(STAR1, NUMBER1, aperture, X_im_size, Y_im_size);
 // set_distance_to_neighbor_in_struct_Star(STAR3, NUMBER3, aperture, X_im_size, Y_im_size);
 /* Set maximum star number */
 max_number= STAR1[0].n;
 // for(i=0;i<NUMBER1;i++){
 for ( i= NUMBER1; i--; ) {
  if ( max_number < STAR1[i].n )
   max_number= STAR1[i].n;
 }
 // make a gap in numbering so stars detected on the reference frame can be easily distinguished from those added later by their number
 //
 // a sily attempt to preserve star numbers over data reduction runs with different settings (-x0 vs. -x2)
 // I'm afraid that will not change much...
 if ( max_number < 50000 ) {
  if ( max_number < 30000 ) {
   if ( max_number < 20000 ) {
    max_number= 20000;
   } else {
    max_number= 30000;
   }
  } else {
   max_number= 50000;
  }
 } else {
  // fall back to the default behaviour
  max_number+= 10000;
 }
 // make a gap in numbering so stars detected on the reference frame can be easily distinguished from those added later by their number

 // Turn on the CCD position-dependent magnitude correction if needed

 if ( param_apply_position_dependent_correction == 0 ) {
  // If this was not specified in the command line, make our own choice
  if ( NUMBER1 > MIN_NUMBER_OF_STARS_FOR_CCD_POSITION_DEPENDENT_MAGNITUDE_CORRECTION )
   apply_position_dependent_correction= 1; // apply the correction
  else
   apply_position_dependent_correction= 0; // do not apply the correction
 }

 // Report if the CCD position-dependent magnitude correction will be used
 if ( apply_position_dependent_correction == 1 )
  fprintf( stderr, "\nPlease note: the CCD position-dependent magnitude correction will be applied.\n" );
 else
  fprintf( stderr, "\nPlease note: the CCD position-dependent magnitude correction will not be applied.\n" );

 /* Sort arrays for Ident */
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: NUMBER1=%d  NUMBER3=%d...\n", NUMBER1, NUMBER3 );
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: Sort arrays for Ident STAR1, NUMBER1...\n" );
 Sort_in_mag_of_stars( STAR1, NUMBER1 );
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: Sort arrays for Ident STAR3, NUMBER3...\n" );
 Sort_in_mag_of_stars( STAR3, NUMBER3 );
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: Done with sorting arrays...\n" );

 malloc_size= sizeof( int ) * NUMBER1;
 if ( malloc_size <= 0 ) {
  fprintf( stderr, "ERROR014 - trying to allocate zero or negative number of bytes!\n" );
  return EXIT_FAILURE;
 }
 Pos1= malloc( (size_t)malloc_size );
 if ( Pos1 == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory!\n Pos1 = malloc(sizeof(int) * NUMBER1); - failed!\n" );
  vast_report_memory_error();
  return EXIT_FAILURE;
 }
 // Be careful here! NUMBER1 may change later and we'll need to change Pos1 accordingly!

 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: set_transient_search_boundaries()\n" );
 set_transient_search_boundaries( search_area_boundaries, STAR3, NUMBER3, X_im_size, Y_im_size );

 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: I am NUMBER1: %d, I am JD: %lf, I am Mister X: %lf\n", NUMBER1, JD, X_im_size );
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: malloc(sizeof(int) * NUMBER1)\n" );

 /* Read catalog of the reference image */
 // Try to allocate a large chunk of memory
 malloc_size= sizeof( struct Observation ) * Max_obs_in_RAM;
 if ( malloc_size <= 0 ) {
  fprintf( stderr, "ERROR015 - trying to allocate zero or negative number of bytes!\n" );
  return EXIT_FAILURE;
 }
 ptr_struct_Obs= malloc( (size_t)malloc_size );
 /// Potential big source of problems: malloc() may succeed, but not enough memory may actually be available!
 // i is just a counter
 for ( i= 0; i < 4; i++ ) {
  // Check if the allocation failed
  if ( ptr_struct_Obs == NULL ) {
   fprintf( stderr, "WARNING: can't allocate memory for observations!\n ptr_struct_Obs = malloc(sizeof(struct Observation) * Max_obs_in_RAM);\nTrying to allocate less memory...\n" );
  } else {
   // If the allocation is a success, get out of this cycle
   break;
  }
  // If the allocation failed, try to pre-allocate less memory
  Max_obs_in_RAM= (long)( (double)Max_obs_in_RAM / 2.0 + 0.5 );
  malloc_size= sizeof( struct Observation ) * Max_obs_in_RAM;
  if ( malloc_size <= 0 ) {
   fprintf( stderr, "ERROR016 - trying to allocate zero or negative number of bytes!\n" );
   return EXIT_FAILURE;
  }
  ptr_struct_Obs= malloc( (size_t)malloc_size );
 }
 // If we still cannot allocate memory - exit with an error message
 if ( ptr_struct_Obs == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory for observations!\n ptr_struct_Obs = malloc(sizeof(struct Observation) * Max_obs_in_RAM);\n" );
  return EXIT_FAILURE;
 }
 if ( debug != 0 )
  fprintf( stderr, "\n\nDEBUG: allocated %.3lf Gb for %ld observations (%ld bytes each) in RAM\n\n", (double)sizeof( struct Observation ) * (double)Max_obs_in_RAM / (double)( 1024 * 1024 * 1024 ), Max_obs_in_RAM, sizeof( struct Observation ) );

 //
 if ( param_exclude_reference_image == 1 ) {
  // Create an empty file signalling that we are excluding the reference image photometry
  vast_exclude_reference_image_log= fopen( "vast_exclude_reference_image.log", "w" );
  if ( NULL != vast_exclude_reference_image_log ) {
   fclose( vast_exclude_reference_image_log );
  }
 }
 //

 for ( i= 0; i < NUMBER1; i++ ) {

  //  if( STAR1[i].n == 375 )
  //   fprintf(stderr, "\n\n\n DEBUGVENUS STAR1[i].n -- CHECK\n\n\n");

  if ( STAR1[i].n >= MAX_NUMBER_OF_STARS ) {
   report_and_handle_too_many_stars_error();
   //   fprintf( stderr, "########## Oops!!! Too many stars! ##########\nChange string \"#define MAX_NUMBER_OF_STARS %d\" in src/vast_limits.h file and recompile the program by running \"make\".\n\nOr you may choose a higher star detection limit (get less stars per frame) by changing DETECT_MINAREA and DETECT_THRESH/ANALYSIS_THRESH parameters in default.sex file\n",
   //            MAX_NUMBER_OF_STARS );
   return EXIT_FAILURE;
  }

  ///////////////////////////////////////////////////////////////////////////////
  // Do not add observations from the reference image if we want to exclude it //
  if ( param_exclude_reference_image == 1 ) {
   continue;
  }
  ///////////////////////////////////////////////////////////////////////////////

  //
  STAR1[i].n_detected= 1;
  // Check if the star is good enough to be written to the output
  if ( 1 == is_point_close_or_off_the_frame_edge( (double)STAR1[i].x_frame, (double)STAR1[i].y_frame, X_im_size, Y_im_size, FRAME_EDGE_INDENT_PIXELS ) ) {
   // This is supposed to be checked above!
   fprintf( stderr, "FRAME EDGE REJECTION ERROR!!!\n" );
   return EXIT_FAILURE;
  }
  //  if( STAR1[i].n == 375 )
  //   fprintf(stderr, "\n\n\n DEBUGVENUS STAR1[i].n -- CHECK2\n\n\n");
  if ( STAR1[i].sextractor_flag > maxsextractorflag ) {
   // We counted them above, here we just reject
   // counter_rejected_seflags_gt_user_spec_threshold++;
   STAR1[i].n_rejected= 1;
   continue;
  }
  //  if( STAR1[i].n == 375 )
  //   fprintf(stderr, "\n\n\n DEBUGVENUS STAR1[i].n -- CHECK3\n\n\n");
  if ( STAR1[i].vast_flag != 0 ) {
   // WTF?!?!?!?!?
   STAR1[i].n_rejected= 1;
   continue;
  }
  STAR1[i].n_rejected= 0;

  TOTAL_OBS++;
  obs_in_RAM++;

  // Save coordinates to the array. (the arrays are used to compute mean position of a star across all images)
  star_numbers_for_coordinate_arrays[coordinate_array_counter]= STAR1[i].n;
  number_of_coordinate_measurements_for_star[coordinate_array_counter]= 1; // first measurement
  coordinate_array_x[coordinate_array_counter]= malloc( sizeof( float ) );
  if ( coordinate_array_x[coordinate_array_counter] == NULL ) {
   fprintf( stderr, "ERROR: can't allocate memory for coordinate_array_x[coordinate_array_counter]\n" );
   vast_report_memory_error();
   return EXIT_FAILURE;
  }
  coordinate_array_x[coordinate_array_counter][0]= STAR1[i].x;
  coordinate_array_y[coordinate_array_counter]= malloc( sizeof( float ) );
  if ( coordinate_array_y[coordinate_array_counter] == NULL ) {
   fprintf( stderr, "ERROR: can't allocate memory for coordinate_array_y[coordinate_array_counter]\n" );
   vast_report_memory_error();
   return EXIT_FAILURE;
  }
  coordinate_array_y[coordinate_array_counter][0]= STAR1[i].y;
  coordinate_array_counter++;

  if ( obs_in_RAM > Max_obs_in_RAM ) {
   ptr_struct_Obs= realloc( ptr_struct_Obs, sizeof( struct Observation ) * obs_in_RAM );
   if ( ptr_struct_Obs == NULL ) {
    fprintf( stderr, "ERROR: cannot re-allocate memory for a new observation (from reference image)!\n ptr_struct_Obs = realloc(ptr_struct_Obs, sizeof(struct Observation) * obs_in_RAM); - failed!\n" );
    return EXIT_FAILURE;
   }
  }

  //
  //  if( STAR1[i].n == 375 )
  //   fprintf(stderr, "\n\n\n DEBUGVENUS STAR1[i].n -- YES\n\n\n");

  ptr_struct_Obs[obs_in_RAM - 1].star_num= STAR1[i].n;
  ptr_struct_Obs[obs_in_RAM - 1].JD= STAR1[i].JD;
  ptr_struct_Obs[obs_in_RAM - 1].mag= (double)STAR1[i].mag;
  ptr_struct_Obs[obs_in_RAM - 1].mag_err= (double)STAR1[i].sigma_mag;
  ptr_struct_Obs[obs_in_RAM - 1].X= (double)STAR1[i].x_frame;
  ptr_struct_Obs[obs_in_RAM - 1].Y= (double)STAR1[i].y_frame;
  ptr_struct_Obs[obs_in_RAM - 1].APER= (float)aperture;

  // strncpy( ptr_struct_Obs[obs_in_RAM - 1].filename, input_images[0], FILENAME_LENGTH );
  // ptr_struct_Obs[obs_in_RAM - 1].filename[FILENAME_LENGTH - 1]= '\0'; // just in case
  // strncpy( ptr_struct_Obs[obs_in_RAM - 1].fits_header_keywords_to_be_recorded_in_lightcurve, str_with_fits_keywords_to_capture_from_input_images[0], FITS_KEYWORDS_IN_LC_LENGTH );
  // ptr_struct_Obs[obs_in_RAM - 1].fits_header_keywords_to_be_recorded_in_lightcurve[FITS_KEYWORDS_IN_LC_LENGTH - 1]= '\0'; // just in case
  //  Just store pointers to the existing strings
  ptr_struct_Obs[obs_in_RAM - 1].filename= input_images[0];
  ptr_struct_Obs[obs_in_RAM - 1].fits_header_keywords_to_be_recorded_in_lightcurve= str_with_fits_keywords_to_capture_from_input_images[0];

  ptr_struct_Obs[obs_in_RAM - 1].is_used= 0;

  //
  for ( float_parameters_counter= NUMBER_OF_FLOAT_PARAMETERS; float_parameters_counter--; ) {
   ptr_struct_Obs[obs_in_RAM - 1].float_parameters[float_parameters_counter]= STAR1[i].float_parameters[float_parameters_counter];
  }
  //

  //} // if the star is good enough...
 }
 //
 // fprintf(stderr," * rejected as having SExtractor flags > %d and < 7: %d\n---\n",maxsextractorflag,counter_rejected_seflags_gt_user_spec_threshold);
 //
 fprintf( stderr, "    %4d stars detected\n", NUMBER1 );

 check_and_print_memory_statistics();
 progress( 1, Num );

 // log first observation
 // sprintf( log_output, "JD= %13.5lf  ap= %4.1lf  rotation= %7.3lf  *detected= %5d  *matched= %5d  status=OK     %s\n", JD, aperture, 0.0, NUMBER1, NUMBER1, input_images[0] );
 sprintf( log_output, "JD= %16.8lf  ap= %4.1lf  rotation= %7.3lf  *detected= %5d  *matched= %5d  status=OK     %s\n", JD, aperture, 0.0, NUMBER1, NUMBER1, input_images[0] );
 write_string_to_log_file( log_output, sextractor_catalog );

 ////// Process other images //////
 for ( n= n_start; n < Num; n++ ) {
  fprintf( stderr, "\n\n\n" );

  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: gettime() - " );
  fitsfile_read_error= gettime( input_images[n], &JD, &timesys, convert_timesys_to_TT, &X_im_size, &Y_im_size, stderr_output, log_output, param_nojdkeyword, 1, NULL ); // Вот этот код дублирован выше! Зачем?
  if ( fitsfile_read_error == 0 ) {
   if ( debug != 0 )
    fprintf( stderr, "OK\n" );
   if ( debug != 0 )
    fprintf( stderr, "DEBUG MSG: autodetect_aperture() - " );
   aperture= autodetect_aperture( input_images[n], sextractor_catalog, 0, param_P, fixed_aperture, X_im_size, Y_im_size, guess_saturation_limit_operation_mode );
   if ( debug != 0 )
    fprintf( stderr, "OK\n" );

   // Check if the image is marked as bad
   // if it is, set the aperture to an unrealistic value
   // this will allow the existing mechanism to handle and log the bad image properly
   if ( vast_bad_image_flag[n] != 0 ) {
    fprintf( stderr, "WARNING: image marked as bad with flag %d %s (indicating this by setting APERTURE=0.0)\n", vast_bad_image_flag[n], input_images[n] );
    aperture= 0.0;
    vast_bad_image_flag_counter++;
   }
   //

   // Write the logfile
   if ( aperture < 0.0 ) {
    fprintf( stderr, "WARNING: the derivedimae apture is unrealistically small %lf %s\n", aperture, input_images[n] );
    aperture= 0.0; // Do not corrupt the log file with bad apertures
   }
   if ( aperture > 99.9 ) {
    fprintf( stderr, "WARNING: the derivedimae apture is unrealistically large %lf %s\n", aperture, input_images[n] );
    aperture= 99.9; // Do not corrupt the log file with bad apertures
   }
   write_string_to_log_file( log_output, sextractor_catalog );
   // sprintf( log_output, "JD= %13.5lf  ap= %4.1lf  ", JD, aperture );
   sprintf( log_output, "JD= %16.8lf  ap= %4.1lf  ", JD, aperture );
   write_string_to_log_file( log_output, sextractor_catalog );

   // WARNING!!! Hardcoded aperture limits here!
   if ( aperture < BELIEVABLE_APERTURE_MAX_PIX && aperture > BELIEVABLE_APERTURE_MIN_PIX ) {
    // STAR2 gets allocated in this block...

    //
    // Make sure we record the largest image size
    //
    if ( max_X_im_size < X_im_size )
     max_X_im_size= X_im_size;
    if ( max_Y_im_size < Y_im_size )
     max_Y_im_size= Y_im_size;
    //
    if ( param_w == 0 ) {
     struct_pixel_coordinate_transformation->sigma_popadaniya= AUTO_SIGMA_POPADANIYA_COEF * MAX( aperture, reference_image_aperture );
     fprintf( stderr, "Setting the star matching radius to %.2lf pix\n", struct_pixel_coordinate_transformation->sigma_popadaniya );
    }
    if ( debug != 0 )
     fprintf( stderr, "DEBUG MSG: Read_sex_cat() - " );
    /* Read_sex_cat2 */
    number_of_lines_current_image_cat= count_lines_in_ASCII_file( sextractor_catalog );
    if ( number_of_lines_current_image_cat <= 0 ) {
     fprintf( stderr, "ERROR: %d lines in the file %s\n", number_of_lines_current_image_cat, sextractor_catalog );
     return EXIT_FAILURE;
    }
    // malloc_size= MAX_NUMBER_OF_STARS * sizeof( struct Star );
    malloc_size= number_of_lines_current_image_cat * sizeof( struct Star );
    if ( malloc_size <= 0 ) {
     fprintf( stderr, "ERROR017 - trying to allocate zero or negative number of bytes!\n" );
     return EXIT_FAILURE;
    }
    STAR2= malloc( (size_t)malloc_size );
    if ( STAR2 == NULL ) {
     fprintf( stderr, "ERROR: No memory (STAR2)\n" );
     vast_report_memory_error();
     return EXIT_FAILURE;
    }
    file= fopen( sextractor_catalog, "r" );
    if ( file == NULL ) {
     fprintf( stderr, "Can't open file %s\n", sextractor_catalog );
     return EXIT_FAILURE;
    }
    NUMBER2= 0;
    counter_rejected_bad_flux= counter_rejected_low_snr= counter_rejected_bad_region= counter_rejected_frame_edge= counter_rejected_too_small= counter_rejected_too_large= counter_rejected_external_flag= counter_rejected_seflags_gt7= counter_rejected_seflags_gt_user_spec_threshold= 0; // reset bad star counters
    previous_star_number_in_sextractor_catalog= 0;
    while ( NULL != fgets( sextractor_catalog_string, MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT, file ) ) {
     sextractor_catalog_string[MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT - 1]= '\0'; // just in case
     external_flag= 0;
     // external_flag_string[0]='\0';
     if ( 0 != parse_sextractor_catalog_string( sextractor_catalog_string, &star_number_in_sextractor_catalog, &flux_adu, &flux_adu_err, &mag, &sigma_mag, &position_x_pix, &position_y_pix, &a_a, &a_a_err, &a_b, &a_b_err, &sextractor_flag, &external_flag, &psf_chi2, float_parameters ) ) {
      fprintf( stderr, "WARNING: problem occurred while parsing SExtractor catalog %s\nThe offending line is:\n%s\n", sextractor_catalog, sextractor_catalog_string );
      continue;
     }
     // if( 12>sscanf(sextractor_catalog_string, "%d %lf %lf %lf %lf %lf %lf %lf %lf %lf %lf %d %[^\t\n]", &star_number_in_sextractor_catalog, &flux_adu, &flux_adu_err, &mag, &sigma_mag, &position_x_pix, &position_y_pix, &a_a, &a_a_err, &a_b, &a_b_err, &sextractor_flag, external_flag_string) ){
     //  fprintf(stderr,"WARNING: problem occurred while parsing SExtractor catalog %s\nThe offending line is:\n%s\n",sextractor_catalog,sextractor_catalog_string);
     //  continue;
     // }
     //  Read only stars detected at the first FITS image extension.
     //  The start of the second image extension will be signified by a jump in star numbering
     if ( star_number_in_sextractor_catalog < previous_star_number_in_sextractor_catalog ) {
      fprintf( stderr, "WARNING: the input SExtractor catalog is not sorted. Was this catalog created from a multi-extension FITS? In this case, only sources detected on the first image extension will be processed!\n" );
      break;
     } else {
      previous_star_number_in_sextractor_catalog= star_number_in_sextractor_catalog;
     }
     // Check if the catalog line is a really band one
     if ( flux_adu <= 0 ) {
      counter_rejected_bad_flux++;
      continue;
     }
     if ( flux_adu_err == 999999 ) {
      counter_rejected_bad_flux++;
      continue;
     }
     if ( mag == 99.0000 ) {
      counter_rejected_bad_flux++;
      continue;
     }
     if ( sigma_mag == 99.0000 ) {
      counter_rejected_bad_flux++;
      continue;
     }
     // If we have no error estimates in at least one aperture - assume things are bad with this object
     if ( float_parameters[3] == 99.0000 ) {
      counter_rejected_bad_flux++;
      continue;
     }
     if ( float_parameters[5] == 99.0000 ) {
      counter_rejected_bad_flux++;
      continue;
     }
     if ( float_parameters[7] == 99.0000 ) {
      counter_rejected_bad_flux++;
      continue;
     }
     if ( float_parameters[9] == 99.0000 ) {
      counter_rejected_bad_flux++;
      continue;
     }
     if ( float_parameters[11] == 99.0000 ) {
      counter_rejected_bad_flux++;
      continue;
     }
//
#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
     if ( mag < BRIGHTEST_STARS ) {
      counter_rejected_bad_flux++;
      continue;
     }
     if ( mag > FAINTEST_STARS_ANYMAG ) {
      counter_rejected_bad_flux++;
      continue;
     }
     if ( sigma_mag > MAX_MAG_ERROR ) {
      counter_rejected_low_snr++;
      continue;
     }
#endif
     //
     if ( flux_adu < MIN_SNR * flux_adu_err ) {
      counter_rejected_low_snr++;
      continue;
     }
     if ( 0 != exclude_region( X1, Y1, X2, Y2, N_bad_regions, position_x_pix, position_y_pix, aperture ) ) {
      if ( counter_rejected_bad_region < 10 ) {
       fprintf( stderr, "The star %9.3lf %9.3lf is rejected, see bad_region.lst\n", position_x_pix, position_y_pix );
      }
      if ( counter_rejected_bad_region == 10 ) {
       fprintf( stderr, "Excluding more stars falling at bad regions!.. (will not print them all)\n" );
      }
      counter_rejected_bad_region++;
      continue;
     }
     if ( 1 == is_point_close_or_off_the_frame_edge( position_x_pix, position_y_pix, X_im_size, Y_im_size, FRAME_EDGE_INDENT_PIXELS ) ) {
      counter_rejected_frame_edge++;
      continue;
     }
     //
     if ( CONST * ( a_a + a_a_err ) < MIN_SOURCE_SIZE_APERTURE_FRACTION * aperture ) {
      counter_rejected_too_small++;
      continue;
     }
     //
     if ( SIGMA_TO_FWHM_CONVERSION_FACTOR * ( a_a + a_a_err ) < FWHM_MIN ) {
      counter_rejected_too_small++;
      continue;
     }
     if ( SIGMA_TO_FWHM_CONVERSION_FACTOR * ( a_b + a_b_err ) < FWHM_MIN ) {
      counter_rejected_too_small++;
      continue;
     }
     // if ( float_parameters[0] < FWHM_MIN ) {
     if ( MAX( float_parameters[0], SIGMA_TO_FWHM_CONVERSION_FACTOR * a_a ) < FWHM_MIN ) {
      counter_rejected_too_small++;
      continue;
     }
     //
     if ( external_flag != 0 ) {
      counter_rejected_external_flag++;
      continue;
     }
     //
     if ( maxsextractorflag < sextractor_flag && sextractor_flag <= 7 ) {
      counter_rejected_seflags_gt_user_spec_threshold++;
      // We don't drop such objects here to keep 'em in STAR structure,
      // they will be rejected later when saving the observations.
     }
     // just in case we mark objects with really bad SExtractor flags
     // sextractor_flag != 20 -- accept a super-bright saturated object
     if ( sextractor_flag > 7 && sextractor_flag != 20 ) {
      counter_rejected_seflags_gt7++;
      continue;
     }
     //
     NUMBER2++;
     STAR2[NUMBER2 - 1].vast_flag= 0;
     // It is OK for a very bright saturated object to be big
     // if ( a_a > 5*aperture && sextractor_flag < 4 ) {
     if ( a_a > aperture && sextractor_flag < 4 && 0 == param_nodiscardlargesrc ) {
      counter_rejected_too_large++;
      STAR2[NUMBER2 - 1].vast_flag= 1;
     }

     STAR2[NUMBER2 - 1].n= star_number_in_sextractor_catalog;
     STAR2[NUMBER2 - 1].x= (float)position_x_pix;
     STAR2[NUMBER2 - 1].y= (float)position_y_pix;
     STAR2[NUMBER2 - 1].flux= flux_adu;
     STAR2[NUMBER2 - 1].flux_err= flux_adu_err;
     // Теперь считаем ошибки правильно, а не как трактор ;)
     STAR2[NUMBER2 - 1].mag= (float)mag;
     STAR2[NUMBER2 - 1].sigma_mag= (float)sigma_mag;
     STAR2[NUMBER2 - 1].JD= JD;
     STAR2[NUMBER2 - 1].x_frame= STAR2[NUMBER2 - 1].x;
     STAR2[NUMBER2 - 1].y_frame= STAR2[NUMBER2 - 1].y;
     // for moving object match
     STAR2[NUMBER2 - 1].moving_object= 0;
     if ( moving_object == 1 ) {
      if ( 0.0 < position_x_pix && position_x_pix < MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
       if ( 0.0 < position_y_pix && position_y_pix < MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
        if ( 0.0 < moving_object__user_array_x[n] && moving_object__user_array_x[n] < MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
         if ( 0.0 < moving_object__user_array_y[n] && moving_object__user_array_y[n] < MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
          if ( ( position_x_pix - moving_object__user_array_x[n] ) * ( position_x_pix - moving_object__user_array_x[n] ) + ( position_y_pix - moving_object__user_array_y[n] ) * ( position_y_pix - moving_object__user_array_y[n] ) < 1.0 ) {
           STAR2[NUMBER2 - 1].moving_object= 1;
           // fprintf(stderr,"\x1B[01;31mDEBUG: here is the moving object on %s !!!\x1B[33;00m\n", input_images[n]);
          }
         } // if( 0.0 < moving_object__user_array_y[n]  &&  moving_object__user_array_y[n] < MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
        } // if( 0.0 < moving_object__user_array_x[n]  &&  moving_object__user_array_x[n] < MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
       } // if( 0.0 < position_y_pix  &&  position_y_pix < MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
      } // if( 0.0 < position_x_pix  && position_x_pix < MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK ) {
     }
     //
     STAR2[NUMBER2 - 1].detected_on_ref_frame= 0;               // Mark the star that it is not on the reference frame
     STAR2[NUMBER2 - 1].sextractor_flag= (char)sextractor_flag; // SExtractor flag
     // STAR2[NUMBER2-1].distance_to_neighbor_squared=4*a_a*a_a; // EXPERIMENTAL !!!
     STAR2[NUMBER2 - 1].star_size= (float)a_a;
     //
     STAR2[NUMBER2 - 1].star_psf_chi2= (float)psf_chi2;
     //
     for ( float_parameters_counter= NUMBER_OF_FLOAT_PARAMETERS; float_parameters_counter--; ) {
      STAR2[NUMBER2 - 1].float_parameters[float_parameters_counter]= float_parameters[float_parameters_counter];
     }
     //

     /// !!! Debug !!!
     // float debug_x=586.696;
     // float debug_y=438.463;
     /// float debug_d=sqrt((STAR2[NUMBER2-1].x_frame-debug_x)*(STAR2[NUMBER2-1].x_frame-debug_x)+(STAR2[NUMBER2-1].y_frame-debug_y)*(STAR2[NUMBER2-1].y_frame-debug_y));
     /// if( debug_d<aperture ){
     // fprintf(stderr,"READING SEXTRACTOR CAT: %d  %.3f %.3f  (%f)  s=%d v=%6d\n",STAR2[NUMBER2-1].n,STAR2[NUMBER2-1].x_frame,STAR2[NUMBER2-1].y_frame,STAR2[NUMBER2-1].star_size,STAR2[NUMBER2-1].sextractor_flag,STAR2[NUMBER2-1].vast_flag);
     //}

     /// !!! Debug !!!
     float debug_x= 2535.0;
     float debug_y= 1901.5;
     float debug_d= sqrt( ( STAR2[NUMBER2 - 1].x_frame - debug_x ) * ( STAR2[NUMBER2 - 1].x_frame - debug_x ) + ( STAR2[NUMBER2 - 1].y_frame - debug_y ) * ( STAR2[NUMBER2 - 1].y_frame - debug_y ) );
     if ( debug_d < aperture ) {
      fprintf( stderr, "READING SEXTRACTOR CAT: %d  %.3f %.3f  (%f)  s=%d v=%6d\n", STAR2[NUMBER2 - 1].n, STAR2[NUMBER2 - 1].x_frame, STAR2[NUMBER2 - 1].y_frame, STAR2[NUMBER2 - 1].star_size, STAR2[NUMBER2 - 1].sextractor_flag, STAR2[NUMBER2 - 1].vast_flag );
     }

     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: Reading test.cat NUMBER2=%d OK\n", NUMBER2 );
    }
    fclose( file );
    if ( debug != 0 )
     fprintf( stderr, "DEBUG MSG: Finished reading cat file for %s\n", input_images[n] );
    /* end of Read_sex_cat2 */

    if ( param_P == 1 ) {
     fprintf( stderr, "Filtering-out stars with bad PSF fit... " );
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: filter_MagPSFchi2()\n" );
     if ( param_filterout_magsize_outliers == 1 )
      /// !!! Disable PSF fit quality filter - it never works well (see also above) !!!
      //      counter_rejected_bad_psf_fit= filter_on_float_parameters(STAR2, NUMBER2, sextractor_catalog, -2); // psfchi2
      counter_rejected_bad_psf_fit= 0;
     /*
if ( param_filterout_magsize_outliers != 1 ) {
if ( debug != 0 )
fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(2)\n" );
counter_rejected_bad_psf_fit+= filter_on_float_parameters( STAR2, NUMBER2, sextractor_catalog, 2 ); // magpsf-magaper
}
*/
     fprintf( stderr, "done!\n" );
    } else {
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: NOT RUNNING filter_MagPSFchi2()\n" );
     counter_rejected_bad_psf_fit= 0; // no PSF-fitting (and filtering)
    }

    // Flag outliers in the magnitude-size plot
    if ( param_filterout_magsize_outliers == 1 ) {
     fprintf( stderr, "Filtering-out outliers in the mag-size plot... " );
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(-1)\n" );
     counter_rejected_MagSize= filter_on_float_parameters( STAR2, NUMBER2, sextractor_catalog, -1 );
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(0)\n" );
     counter_rejected_MagSize+= filter_on_float_parameters( STAR2, NUMBER2, sextractor_catalog, 0 );
     // OK, let's count these filters as size-filters too for now
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(1)\n" );
     counter_rejected_MagSize+= filter_on_float_parameters( STAR2, NUMBER2, sextractor_catalog, 1 );
     //
     /*
     if ( param_P == 1 ) {
      if ( debug != 0 )
       fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(2)\n" );
      counter_rejected_bad_psf_fit+= filter_on_float_parameters( STAR2, NUMBER2, sextractor_catalog, 2 ); // magpsf-magaper
     }
     */
     //
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(4)\n" );
     counter_rejected_MagSize+= filter_on_float_parameters( STAR2, NUMBER2, sextractor_catalog, 4 );
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(6)\n" );
     counter_rejected_MagSize+= filter_on_float_parameters( STAR2, NUMBER2, sextractor_catalog, 6 );
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(8)\n" );
     counter_rejected_MagSize+= filter_on_float_parameters( STAR2, NUMBER2, sextractor_catalog, 8 );
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(10)\n" );
     counter_rejected_MagSize+= filter_on_float_parameters( STAR2, NUMBER2, sextractor_catalog, 10 );
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: filter_on_float_parameters(12)\n" );
     counter_rejected_MagSize+= filter_on_float_parameters( STAR2, NUMBER2, sextractor_catalog, 12 );
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: DONE WITH filter_on_float_parameters()\n" );
     fprintf( stderr, "done!\n" );
    } else {
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: filter_on_float_parameters()\n" );
     counter_rejected_MagSize= 0; // no mag-size filtering
    }

    // Print out input catalog filtering stats
    sprintf( sextractor_catalog_filtering_results_string, "SExtractor output filtering results:\n * passed selection: %d\n * rejected as having no flux measurement: %d\n * rejected as having SNR<%.1lf: %d\n * rejected inside rectangles defined in bad_region.lst: %d\n * rejected close to frame edge: %d\n * rejected as being too small (<%.1lf pix): %d\n * rejected as being too large (>%.1lf pix): %d\n * rejected as outliers in mag-size plot: %d\n * rejected as having SExtractor flags > %d and <= 7: %d\n * rejected as having hopelessly bad SExtractor flags (>7): %d\n * rejected due to an external image flag: %d\n * rejected as having bad PSF fit: %d\n---\n",
             NUMBER2,
             counter_rejected_bad_flux,
             MIN_SNR, counter_rejected_low_snr,
             counter_rejected_bad_region,
             counter_rejected_frame_edge,
             MAX( FWHM_MIN, MIN_SOURCE_SIZE_APERTURE_FRACTION * aperture ), counter_rejected_too_small,
             aperture, counter_rejected_too_large,
             counter_rejected_MagSize,
             maxsextractorflag, counter_rejected_seflags_gt_user_spec_threshold,
             counter_rejected_seflags_gt7,
             counter_rejected_external_flag,
             counter_rejected_bad_psf_fit );
    fputs( sextractor_catalog_filtering_results_string, stderr );
    write_string_to_individual_image_log( sextractor_catalog, "main(): ", sextractor_catalog_filtering_results_string, "" );

    fprintf( stderr, "You may change some of the filtering parameters by editing src/vast_limits.h and re-running 'make'.\n" );
    // Check the stats and issue warnings if needed
    if ( (double)counter_rejected_too_small / (double)NUMBER1 > 0.3 )
     fprintf( stderr, "\x1B[01;31m WARNING: \x1B[33;00m suspiciously many stars are rejected as being too small. Please check FWHM_MIN in src/vast_limits.h and re-run 'make' if you change it.\n" );

    if ( debug != 0 )
     fprintf( stderr, "DEBUG MSG: NUMBER2=%d OK\n", NUMBER2 );

    Pos2= NULL; // can't malloc here as there will be an error if NUMBER2<MIN_NUMBER_OF_STARS_ON_FRAME

    /* If we see enough stars... */
    if ( NUMBER2 > MIN_NUMBER_OF_STARS_ON_FRAME ) {
     //
     malloc_size= sizeof( int ) * NUMBER2;
     if ( malloc_size <= 0 ) {
      fprintf( stderr, "ERROR018 - trying to allocate zero or negative number of bytes!\n" );
      return EXIT_FAILURE;
     }
     Pos2= malloc( (size_t)malloc_size );
     if ( Pos2 == NULL ) {
      fprintf( stderr, "ERROR: can't allocate memory for Pos2\n" );
      vast_report_memory_error();
      return EXIT_FAILURE;
     }
     if ( debug != 0 ) {
      fprintf( stderr, "DEBUG MSG: Ident(struct_pixel_coordinate_transformation etc) - " );
     }

     // Experimental fix - resize Pos1 right here. Yes, that seems to work well!
     // BUT THE EXTENDED PART OF Pos1 is not populated yet!
     Pos1= realloc( Pos1, sizeof( int ) * ( MAX( NUMBER1, NUMBER2 ) + 1 ) );
     //

     // set_distance_to_neighbor_in_struct_Star(STAR2, NUMBER2, aperture, X_im_size, Y_im_size); // set distance to the closest neighbor for each star.

     Sort_in_mag_of_stars( STAR2, NUMBER2 );
     best_number_of_matched_stars= 0;
     best_number_of_matched_stars= 0;
     struct_pixel_coordinate_transformation->Number_of_ecv_triangle= default_Number_of_ecv_triangle;
     struct_pixel_coordinate_transformation->Number_of_main_star= default_Number_of_main_star;
     previous_Number_of_main_star= 0;
     // Special case: relax scale criterea for images with very few stars
     if ( NUMBER2 < 10 && NUMBER3 < 10 ) {
      struct_pixel_coordinate_transformation->sigma_podobia= 0.02; // cf. the default value in ident_lib.c
     }
     //
     for ( match_try= 0; match_try < MAX_MATCH_TRIALS; match_try++ ) {
      match_retry= 0;

      /* Identify stars */
      if ( param_set_manually_Number_of_main_star == 0 ) {
       Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)( 2 * MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ), max_X_im_size, max_Y_im_size );
      } else {
       Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)( MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ), max_X_im_size, max_Y_im_size );
       if ( match_retry == 1 )
        match_retry= 0;
      }

      /* Test if match attempt was a success */
      if ( match_retry == 0 )
       break;
      if ( Number_of_ecv_star > best_number_of_matched_stars ) {
       fprintf( stderr, "the best number of matched * so far: %d\n", Number_of_ecv_star );
       best_number_of_matched_stars= Number_of_ecv_star;
       best_number_of_reference_stars= struct_pixel_coordinate_transformation->Number_of_main_star;
      }
      if ( struct_pixel_coordinate_transformation->Number_of_main_star >= MIN( MATCH_MAX_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) || struct_pixel_coordinate_transformation->Number_of_ecv_triangle >= MATCH_MAX_NUMBER_OF_TRIANGLES ) {
       break;
      }
      /* Try to play with parameters */
      struct_pixel_coordinate_transformation->Number_of_main_star= struct_pixel_coordinate_transformation->Number_of_main_star * 2;
      struct_pixel_coordinate_transformation->Number_of_ecv_triangle= struct_pixel_coordinate_transformation->Number_of_ecv_triangle * 2;
      if ( struct_pixel_coordinate_transformation->Number_of_main_star == 2 * MIN( MATCH_MAX_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) )
       break; // So we do not repeat many times attempt with the maximum number of reference stars
      if ( struct_pixel_coordinate_transformation->Number_of_main_star > MIN( MATCH_MAX_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) || struct_pixel_coordinate_transformation->Number_of_ecv_triangle > MATCH_MAX_NUMBER_OF_TRIANGLES ) {
       struct_pixel_coordinate_transformation->Number_of_main_star= MIN( MATCH_MAX_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) );
       struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MAX_NUMBER_OF_TRIANGLES;
      }

      // this is new!
      fprintf( stderr, "[1] previous_Number_of_main_star = %d\n", previous_Number_of_main_star );
      if ( struct_pixel_coordinate_transformation->Number_of_main_star == previous_Number_of_main_star ) {
       fprintf( stderr, "[1] break!\n" );
       break;
      }
      previous_Number_of_main_star= struct_pixel_coordinate_transformation->Number_of_main_star;
     } // for ( match_try= 0; match_try < MAX_MATCH_TRIALS; match_try++ ) {

     /* Special test for the case if one image is much better focused than the other and
                                    all the reference stars got saturated on it... */
     if ( match_retry == 1 ) {
      fprintf( stderr, "Performing special test for the case of a sudden focus change (exclude brightest stars from the match)...\n" );
     }
     // current image
     if ( match_retry == 1 && NUMBER2 > 2 * struct_pixel_coordinate_transformation->Number_of_main_star ) {
      match_retry= 0;
      Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, struct_pixel_coordinate_transformation->Number_of_main_star, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)( 1.5 * MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ), max_X_im_size, max_Y_im_size );
     } else {
      if ( match_retry == 1 )
       fprintf( stderr, "Ups, not enough stars on the current image for the test! Whatever...\n" );
     }

     // reference image
     if ( match_retry == 1 && NUMBER3 > 2 * struct_pixel_coordinate_transformation->Number_of_main_star ) {
      match_retry= 0;
      Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, Pos1, Pos2, no_rotation, STAR3, NUMBER3, struct_pixel_coordinate_transformation->Number_of_main_star, &match_retry, (int)( 1.5 * MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ), max_X_im_size, max_Y_im_size );
     } else {
      if ( match_retry == 1 )
       fprintf( stderr, "Ups, not enough stars on the reference image for the test! Whatever...\n" );
     }
     if ( match_retry == 1 )
      fprintf( stderr, "Done with the test...\n" );

     /* If increasing number of reference stars did not help, try to decrease the number */
     if ( match_retry == 1 ) {
      // start with 1 so test match_try!=0 will work later
      for ( match_try= 1; match_try < MAX_MATCH_TRIALS + 1; match_try++ ) {

       /* Try to play with parameters */
       struct_pixel_coordinate_transformation->Number_of_main_star= struct_pixel_coordinate_transformation->Number_of_main_star / 2;
       struct_pixel_coordinate_transformation->Number_of_ecv_triangle= struct_pixel_coordinate_transformation->Number_of_ecv_triangle / 2;

       if ( struct_pixel_coordinate_transformation->Number_of_main_star < MATCH_MIN_NUMBER_OF_REFERENCE_STARS || struct_pixel_coordinate_transformation->Number_of_ecv_triangle < MATCH_MIN_NUMBER_OF_TRIANGLES ) {
        struct_pixel_coordinate_transformation->Number_of_main_star= MATCH_MIN_NUMBER_OF_REFERENCE_STARS;
        struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MIN_NUMBER_OF_TRIANGLES;
       }

       match_retry= 0;
       // Number_of_ecv_star = Ident(struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, frame, frame, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)(2*MIN_FRACTION_OF_MATCHED_STARS*MIN(NUMBER3,NUMBER2)), X_im_size, Y_im_size);
       Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)( 2 * MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ), max_X_im_size, max_Y_im_size );
       /* Test if match attemt was a success */
       if ( match_retry == 0 )
        break;
       if ( Number_of_ecv_star > best_number_of_matched_stars ) {
        fprintf( stderr, "the best number of matched * so far: %d\n", Number_of_ecv_star );
        best_number_of_matched_stars= Number_of_ecv_star;
        best_number_of_reference_stars= struct_pixel_coordinate_transformation->Number_of_main_star;
       }
       if ( struct_pixel_coordinate_transformation->Number_of_main_star <= MATCH_MIN_NUMBER_OF_REFERENCE_STARS || struct_pixel_coordinate_transformation->Number_of_ecv_triangle <= MATCH_MIN_NUMBER_OF_TRIANGLES )
        break;

       if ( struct_pixel_coordinate_transformation->Number_of_main_star <= MIN( MATCH_MIN_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) || struct_pixel_coordinate_transformation->Number_of_ecv_triangle <= MATCH_MIN_NUMBER_OF_TRIANGLES ) {
        break;
       }

       // this is new!
       fprintf( stderr, "[2] previous_Number_of_main_star = %d\n", previous_Number_of_main_star );
       if ( struct_pixel_coordinate_transformation->Number_of_main_star == previous_Number_of_main_star ) {
        fprintf( stderr, "[2] break!\n" );
        break;
       }
       previous_Number_of_main_star= struct_pixel_coordinate_transformation->Number_of_main_star;

      } // for ( match_try= 1; match_try < MAX_MATCH_TRIALS + 1; match_try++ ) {
     }

     /* If it still doesn't work - try to decrease an accpetable number of matched stars */
     if ( match_retry == 1 ) {
      if ( best_number_of_reference_stars > 0 ) {
       struct_pixel_coordinate_transformation->Number_of_main_star= best_number_of_reference_stars;
       // is this correct?
       struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MAX_NUMBER_OF_TRIANGLES; // best_number_of_reference_stars;
       fprintf( stderr, "Trying again the best match with %d reference stars\n", best_number_of_reference_stars );
       Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)( 1.5 * MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ), max_X_im_size, max_Y_im_size );
      } else {
       fprintf( stderr, "ERROR: we ended up with only %d reference stars\n", best_number_of_reference_stars );
       Number_of_ecv_star= 0;
       match_retry= 0;
      }
     }
     /*----------------------------------------------------------------------------------*/
     if ( match_retry == 1 ) {
      struct_pixel_coordinate_transformation->Number_of_ecv_triangle= default_Number_of_ecv_triangle;
      struct_pixel_coordinate_transformation->Number_of_main_star= default_Number_of_main_star;
      for ( match_try= 0; match_try < MAX_MATCH_TRIALS; match_try++ ) {
       match_retry= 0;
       Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)( 1.5 * MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER2, NUMBER3 ) ), max_X_im_size, max_Y_im_size );
       /* Test if match attemt was a success */
       if ( match_retry == 0 )
        break;
       if ( Number_of_ecv_star > best_number_of_matched_stars ) {
        fprintf( stderr, "the best number of matched * so far: %d\n", Number_of_ecv_star );
        best_number_of_matched_stars= Number_of_ecv_star;
        best_number_of_reference_stars= struct_pixel_coordinate_transformation->Number_of_main_star;
       }
       if ( struct_pixel_coordinate_transformation->Number_of_main_star >= MATCH_MAX_NUMBER_OF_REFERENCE_STARS || struct_pixel_coordinate_transformation->Number_of_ecv_triangle >= MATCH_MAX_NUMBER_OF_TRIANGLES )
        break;
       /* If not, try to play with parameters */
       struct_pixel_coordinate_transformation->Number_of_main_star= struct_pixel_coordinate_transformation->Number_of_main_star * 2;
       struct_pixel_coordinate_transformation->Number_of_ecv_triangle= struct_pixel_coordinate_transformation->Number_of_ecv_triangle * 2;
       if ( struct_pixel_coordinate_transformation->Number_of_main_star == 2 * MIN( MATCH_MAX_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) )
        break; // So we do not repeat many times attempt with the maximum number of reference stars
       if ( struct_pixel_coordinate_transformation->Number_of_main_star > MATCH_MAX_NUMBER_OF_REFERENCE_STARS || struct_pixel_coordinate_transformation->Number_of_ecv_triangle > MATCH_MAX_NUMBER_OF_TRIANGLES ) {
        struct_pixel_coordinate_transformation->Number_of_main_star= MATCH_MAX_NUMBER_OF_REFERENCE_STARS;
        struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MAX_NUMBER_OF_TRIANGLES;
       }

       if ( struct_pixel_coordinate_transformation->Number_of_main_star >= MIN( MATCH_MAX_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) || struct_pixel_coordinate_transformation->Number_of_ecv_triangle >= MATCH_MAX_NUMBER_OF_TRIANGLES ) {
        break;
       }

       // this is new!
       fprintf( stderr, "[3] previous_Number_of_main_star = %d\n", previous_Number_of_main_star );
       if ( struct_pixel_coordinate_transformation->Number_of_main_star == previous_Number_of_main_star ) {
        fprintf( stderr, "[3] break!\n" );
        break;
       }
       previous_Number_of_main_star= struct_pixel_coordinate_transformation->Number_of_main_star;

      } // for ( match_try= 0; match_try < MAX_MATCH_TRIALS; match_try++ ) {
     }

     /* If increasing number of reference stars did not help, try to decrease the number */
     if ( match_retry == 1 ) {
      // start with 1 so test match_try!=0 will work later
      for ( match_try= 1; match_try < MAX_MATCH_TRIALS + 1; match_try++ ) {
       match_retry= 0;
       Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)( 1.5 * MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ), max_X_im_size, max_Y_im_size );
       /* Test if match attemt was a success */
       if ( match_retry == 0 )
        break;
       if ( Number_of_ecv_star > best_number_of_matched_stars ) {
        fprintf( stderr, "the best number of matched * so far: %d\n", Number_of_ecv_star );
        best_number_of_matched_stars= Number_of_ecv_star;
        best_number_of_reference_stars= struct_pixel_coordinate_transformation->Number_of_main_star;
       }
       if ( struct_pixel_coordinate_transformation->Number_of_main_star <= MATCH_MIN_NUMBER_OF_REFERENCE_STARS || struct_pixel_coordinate_transformation->Number_of_ecv_triangle <= MATCH_MIN_NUMBER_OF_TRIANGLES )
        break;

       if ( struct_pixel_coordinate_transformation->Number_of_main_star <= MIN( MATCH_MIN_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) || struct_pixel_coordinate_transformation->Number_of_ecv_triangle <= MATCH_MIN_NUMBER_OF_TRIANGLES ) {
        break;
       }

       /* If not, try to play with parameters */
       struct_pixel_coordinate_transformation->Number_of_main_star= struct_pixel_coordinate_transformation->Number_of_main_star / 2;
       struct_pixel_coordinate_transformation->Number_of_ecv_triangle= struct_pixel_coordinate_transformation->Number_of_ecv_triangle / 2;
       if ( struct_pixel_coordinate_transformation->Number_of_main_star < MATCH_MIN_NUMBER_OF_REFERENCE_STARS || struct_pixel_coordinate_transformation->Number_of_ecv_triangle < MATCH_MIN_NUMBER_OF_TRIANGLES ) {
        struct_pixel_coordinate_transformation->Number_of_main_star= MATCH_MIN_NUMBER_OF_REFERENCE_STARS;
        struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MIN_NUMBER_OF_TRIANGLES;
       }
      }
     }

     /* If that did not help, try many different numbers of reference stars */
     if ( match_retry == 1 ) {
      // start with 1 so test match_try!=0 will work later
      // is the follwing line correct?
      struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MAX_NUMBER_OF_TRIANGLES;
      for ( struct_pixel_coordinate_transformation->Number_of_main_star= MATCH_MIN_NUMBER_OF_REFERENCE_STARS, struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MIN_NUMBER_OF_TRIANGLES; struct_pixel_coordinate_transformation->Number_of_main_star < MATCH_MAX_NUMBER_OF_REFERENCE_STARS; struct_pixel_coordinate_transformation->Number_of_main_star+= MATCH_REFERENCE_STARS_NUMBER_STEP ) {
       match_retry= 0;
       Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)( 1.5 * MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ), max_X_im_size, max_Y_im_size );
       /* Test if match attemt was a success */
       if ( match_retry == 0 )
        break;
       if ( Number_of_ecv_star > best_number_of_matched_stars ) {
        fprintf( stderr, "the best number of matched * so far: %d\n", Number_of_ecv_star );
        best_number_of_matched_stars= Number_of_ecv_star;
        best_number_of_reference_stars= struct_pixel_coordinate_transformation->Number_of_main_star;
       }
       if ( struct_pixel_coordinate_transformation->Number_of_main_star < MATCH_MIN_NUMBER_OF_REFERENCE_STARS || struct_pixel_coordinate_transformation->Number_of_ecv_triangle < MATCH_MIN_NUMBER_OF_TRIANGLES ) {
        struct_pixel_coordinate_transformation->Number_of_main_star= MATCH_MIN_NUMBER_OF_REFERENCE_STARS;
        struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MIN_NUMBER_OF_TRIANGLES;
       }

       if ( struct_pixel_coordinate_transformation->Number_of_main_star >= MIN( MATCH_MAX_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) || struct_pixel_coordinate_transformation->Number_of_ecv_triangle >= MATCH_MAX_NUMBER_OF_TRIANGLES ) {
        break;
       }
      }
     }

     /*----------------------------------------------------------------------------------*/
     if ( match_retry == 1 ) {
      struct_pixel_coordinate_transformation->Number_of_main_star= best_number_of_reference_stars;
      // is this correct??
      struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MAX_NUMBER_OF_TRIANGLES; // best_number_of_reference_stars;
      fprintf( stderr, "Trying again the best match with %d reference stars\n", best_number_of_reference_stars );
      Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)( 1.0 * MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ), max_X_im_size, max_Y_im_size );
     }
     /*----------------------------------------------------------------------------------*/

     /* Test if there is any hope to match this image */
     if ( match_retry == 1 ) {
      if ( Number_of_ecv_star < (int)( MIN_FRACTION_OF_MATCHED_STARS_STOP_ATTEMPTS * MIN( NUMBER3, NUMBER2 ) ) ) {
       fprintf( stderr, "ERROR! Too few stars matched (%d<%d) after a few iterations! Something may be wrong with this image, skipping it!\n", Number_of_ecv_star, (int)( MIN_FRACTION_OF_MATCHED_STARS_STOP_ATTEMPTS * MIN( NUMBER3, NUMBER2 ) ) );
       Number_of_ecv_star= 0;
       match_retry= 0;
      }
     }

     if ( match_retry == 1 ) {
      struct_pixel_coordinate_transformation->Number_of_ecv_triangle= default_Number_of_ecv_triangle;
      struct_pixel_coordinate_transformation->Number_of_main_star= default_Number_of_main_star;
      for ( match_try= 0; match_try < MAX_MATCH_TRIALS; match_try++ ) {
       match_retry= 0;
       Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)( MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER2, NUMBER3 ) ), max_X_im_size, max_Y_im_size );
       /* Test if match attemt was a success */
       if ( match_retry == 0 )
        break;
       if ( struct_pixel_coordinate_transformation->Number_of_main_star >= MATCH_MAX_NUMBER_OF_REFERENCE_STARS || struct_pixel_coordinate_transformation->Number_of_ecv_triangle >= MATCH_MAX_NUMBER_OF_TRIANGLES )
        break;

       if ( struct_pixel_coordinate_transformation->Number_of_main_star >= MIN( MATCH_MAX_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) || struct_pixel_coordinate_transformation->Number_of_ecv_triangle >= MATCH_MAX_NUMBER_OF_TRIANGLES ) {
        break;
       }
       if ( struct_pixel_coordinate_transformation->Number_of_main_star <= MIN( MATCH_MIN_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) || struct_pixel_coordinate_transformation->Number_of_ecv_triangle <= MATCH_MIN_NUMBER_OF_TRIANGLES ) {
        break;
       }

       /* If not, try to play with parameters */
       struct_pixel_coordinate_transformation->Number_of_main_star= struct_pixel_coordinate_transformation->Number_of_main_star * 2;
       struct_pixel_coordinate_transformation->Number_of_ecv_triangle= struct_pixel_coordinate_transformation->Number_of_ecv_triangle * 2;
       if ( struct_pixel_coordinate_transformation->Number_of_main_star > MATCH_MAX_NUMBER_OF_REFERENCE_STARS || struct_pixel_coordinate_transformation->Number_of_ecv_triangle > MATCH_MAX_NUMBER_OF_TRIANGLES ) {
        struct_pixel_coordinate_transformation->Number_of_main_star= MATCH_MAX_NUMBER_OF_REFERENCE_STARS;
        struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MAX_NUMBER_OF_TRIANGLES;
       }
      }
     }

     /* If increasing number of reference stars did not help, try to decrease the number */
     if ( match_retry == 1 ) {
      // start with 1 so test match_try!=0 will work later
      for ( match_try= 1; match_try < MAX_MATCH_TRIALS + 1; match_try++ ) {
       match_retry= 0;
       Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)( MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ), max_X_im_size, max_Y_im_size );
       /* Test if match attemt was a success */
       if ( match_retry == 0 )
        break;
       if ( struct_pixel_coordinate_transformation->Number_of_main_star <= MATCH_MIN_NUMBER_OF_REFERENCE_STARS || struct_pixel_coordinate_transformation->Number_of_ecv_triangle <= MATCH_MIN_NUMBER_OF_TRIANGLES )
        break;

       if ( struct_pixel_coordinate_transformation->Number_of_main_star >= MIN( MATCH_MAX_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) || struct_pixel_coordinate_transformation->Number_of_ecv_triangle >= MATCH_MAX_NUMBER_OF_TRIANGLES ) {
        break;
       }
       if ( struct_pixel_coordinate_transformation->Number_of_main_star <= MIN( MATCH_MIN_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) || struct_pixel_coordinate_transformation->Number_of_ecv_triangle <= MATCH_MIN_NUMBER_OF_TRIANGLES ) {
        break;
       }

       /* If not, try to play with parameters */
       struct_pixel_coordinate_transformation->Number_of_main_star= struct_pixel_coordinate_transformation->Number_of_main_star / 2;
       struct_pixel_coordinate_transformation->Number_of_ecv_triangle= struct_pixel_coordinate_transformation->Number_of_ecv_triangle / 2;
       if ( struct_pixel_coordinate_transformation->Number_of_main_star < MATCH_MIN_NUMBER_OF_REFERENCE_STARS || struct_pixel_coordinate_transformation->Number_of_ecv_triangle < MATCH_MIN_NUMBER_OF_TRIANGLES ) {
        struct_pixel_coordinate_transformation->Number_of_main_star= MATCH_MIN_NUMBER_OF_REFERENCE_STARS;
        struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MIN_NUMBER_OF_TRIANGLES;
       }
      }
     }

     /* If that did not help, try many different numbers of reference stars */
     if ( match_retry == 1 ) {
      // start with 1 so test match_try!=0 will work later
      // is the follwing line correct ?
      struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MAX_NUMBER_OF_TRIANGLES;
      for ( struct_pixel_coordinate_transformation->Number_of_main_star= MATCH_MIN_NUMBER_OF_REFERENCE_STARS, struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MIN_NUMBER_OF_TRIANGLES; struct_pixel_coordinate_transformation->Number_of_main_star < MATCH_MAX_NUMBER_OF_REFERENCE_STARS; struct_pixel_coordinate_transformation->Number_of_main_star+= MATCH_REFERENCE_STARS_NUMBER_STEP ) {
       match_retry= 0;
       Number_of_ecv_star= Ident( struct_pixel_coordinate_transformation, STAR1, NUMBER1, STAR2, NUMBER2, 0, Pos1, Pos2, no_rotation, STAR3, NUMBER3, 0, &match_retry, (int)( MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ), max_X_im_size, max_Y_im_size );
       /* Test if match attemt was a success */
       if ( match_retry == 0 )
        break;

       if ( struct_pixel_coordinate_transformation->Number_of_main_star >= MIN( MATCH_MAX_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) || struct_pixel_coordinate_transformation->Number_of_ecv_triangle >= MATCH_MAX_NUMBER_OF_TRIANGLES ) {
        break;
       }
       if ( struct_pixel_coordinate_transformation->Number_of_main_star <= MIN( MATCH_MIN_NUMBER_OF_REFERENCE_STARS, MIN( NUMBER2, NUMBER3 ) ) || struct_pixel_coordinate_transformation->Number_of_ecv_triangle <= MATCH_MIN_NUMBER_OF_TRIANGLES ) {
        break;
       }

       if ( struct_pixel_coordinate_transformation->Number_of_main_star < MATCH_MIN_NUMBER_OF_REFERENCE_STARS || struct_pixel_coordinate_transformation->Number_of_ecv_triangle < MATCH_MIN_NUMBER_OF_TRIANGLES ) {
        struct_pixel_coordinate_transformation->Number_of_main_star= MATCH_MIN_NUMBER_OF_REFERENCE_STARS;
        struct_pixel_coordinate_transformation->Number_of_ecv_triangle= MATCH_MIN_NUMBER_OF_TRIANGLES;
       }
      }
     }

     /*----------------------------------------------------------------------------------*/
     if ( debug != 0 )
      fprintf( stderr, "OK\n" );

     // Check if this is the reference image again? We don't want to measure it for the second time and write
     // duplicate points in all lightcurves!
     // Compare file names with the reference image! Old criteria - exectly 180 deg. rotation may not work now
     // since avaraged computed star coordinates are now used for image matching, not coordinates obtained
     // directly from the reference image!
     if ( 0 == strcmp( input_images[0], input_images[n] ) ) { //&& increment_mode!=1 ){
      if ( debug != 0 )
       fprintf( stderr, "It is the reference frame again! File name match!\n" );
      struct_pixel_coordinate_transformation->fi= M_PI;
     }
     if ( fabs( 180 * struct_pixel_coordinate_transformation->fi / M_PI - 180.0 ) < 0.0001 ) {
      struct_pixel_coordinate_transformation->fi= M_PI; // set 180 even if it is not (but file name matches)!
      fprintf( stderr, " rotation is exactly 180 degrees! Is this the reference image again? Dropping image!  %lf\n", 180 * struct_pixel_coordinate_transformation->fi / M_PI );
      Number_of_ecv_star= 0;
     }

     // Write DS9 region files for debug
     // write_Star_struct_to_ds9_region_file(STAR1, 0, NUMBER1, "STAR1_ds9.reg", aperture);
     // write_Star_struct_to_ds9_region_file(STAR2, 0, NUMBER2, "STAR2_ds9.reg", aperture);
     // write_Star_struct_to_ds9_region_file(STAR3, 0, NUMBER3, "STAR3_ds9.reg", aperture);
     // write_Star_struct_to_ds9_region_file(STAR2, Number_of_ecv_star, NUMBER2, "STAR_UNID_ds9.reg", aperture);
     // exit(0); // !!!
     // write_Star_struct_to_ASCII_file(STAR1, 0, NUMBER1, "image_referece.txt", aperture);
     // sprintf(log_output,"image_%03d.txt",n);
     // write_Star_struct_to_ASCII_file(STAR2, 0, NUMBER2, log_output, aperture);

     // Try to eliminate hot pixels from the star list
     // flag_false_star_detections_caused_by_hot_pixels( STAR1, Pos1, &NUMBER1, STAR2, Pos2, &NUMBER2, Number_of_ecv_star);
     // ...

     /* log */
     sprintf( log_output, "rotation= %7.3lf  ", 180 * struct_pixel_coordinate_transformation->fi / M_PI );
     write_string_to_log_file( log_output, sextractor_catalog );
     fprintf( stderr, "  rotation [degrees] = %7.3lf\n", 180 * struct_pixel_coordinate_transformation->fi / M_PI );
     if ( no_rotation == 1 && fabs( struct_pixel_coordinate_transformation->fi ) > MAX_NOROTATION_ANGLE_RAD && fabs( struct_pixel_coordinate_transformation->fi - M_PI ) > MAX_NOROTATION_ANGLE_RAD ) {
      fprintf( stderr, " rotation is large! Dropping image!  %lf\n", 180 * struct_pixel_coordinate_transformation->fi / M_PI );
      Number_of_ecv_star= 0;
     }

     fprintf( stderr, "    %5d stars detected, %5d stars matched\n", NUMBER2, Number_of_ecv_star );
    } else {
     /* Else write log and go to next image */
     Number_of_ecv_star= 0;
     fprintf( stderr, "  rotation [degrees] = %7.3lf\n", 0.000 );
     //
     sprintf( log_output, "rotation= %7.3lf  ", 0.000 );
     write_string_to_log_file( log_output, sextractor_catalog );
    }

    sprintf( log_output, "*detected= %5d  *matched= %5d  ", NUMBER2, Number_of_ecv_star );
    write_string_to_log_file( log_output, sextractor_catalog );

    /* If not enough stars were matched...*/
    if ( Number_of_ecv_star < (int)( MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ) ) { // We should compare with the number of stars on the reference frame, not with the total number of stars!

     fprintf( stderr, "ERROR! Too few stars matched (%d < %d) . Wrong match? Skipping file...\n", Number_of_ecv_star, (int)( MIN_FRACTION_OF_MATCHED_STARS * MIN( NUMBER3, NUMBER2 ) ) );
     write_string_to_individual_image_log( sextractor_catalog, "main(): ", "ERROR! Too few stars matched. Wrong match? Skipping file...", "" );
     Number_of_ecv_star= 0;
    }

    if ( Number_of_ecv_star == 0 ) {
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: Writing status=ERROR to log file - " );
     sprintf( log_output, "status=ERROR  %s\n", input_images[n] );
     write_string_to_log_file( log_output, sextractor_catalog );
     if ( debug != 0 )
      fprintf( stderr, "OK\n" );
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: Closing log file - " );
     if ( debug != 0 )
      fprintf( stderr, "OK\n" );
     if ( NUMBER2 > MIN_NUMBER_OF_STARS_ON_FRAME )
      free( Pos2 );
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: free(STAR2) - " );
     free( STAR2 );
     if ( debug != 0 )
      fprintf( stderr, "OK\n" );
     continue; // Go to next image
    }
    // MATCH_SUCESS++;

    /* Magnitude calibration. */
    // if (param_nocalib != 1) {

    if ( debug != 0 )
     fprintf( stderr, "DEBUG MSG: Mag. calibr start here.   Number_of_ecv_star=%d\n", Number_of_ecv_star ); // Debug message!

    // allocate memory for the arrays
    N_good_stars= 0;
    malloc_size= MIN( Number_of_ecv_star, NUMBER3 ) * sizeof( double );
    if ( malloc_size <= 0 ) {
     fprintf( stderr, "ERROR: trying allocate xero or negative bites amount\n malloc_size = MIN(Number_of_ecv_star, NUMBER3) * sizeof(double)\n" );
     return EXIT_FAILURE;
    }
    // poly_x = (double *)malloc(MIN( Number_of_ecv_star, NUMBER3) * sizeof(double));
    // poly_y = (double *)malloc(MIN( Number_of_ecv_star, NUMBER3) * sizeof(double));
    // poly_err = (double *)malloc(MIN( Number_of_ecv_star, NUMBER3) * sizeof(double));
    // poly_err_fake = (double *)malloc(MIN( Number_of_ecv_star, NUMBER3) * sizeof(double));
    poly_x= (double *)malloc( malloc_size );
    poly_y= (double *)malloc( malloc_size );
    poly_err= (double *)malloc( malloc_size );
    poly_err_fake= (double *)malloc( malloc_size );
    if ( poly_x == NULL || poly_y == NULL || poly_err == NULL || poly_err_fake == NULL ) {
     fprintf( stderr, "ERROR: can't allocate memory for magnitude calibration!\n" );
     vast_report_memory_error();
     return EXIT_FAILURE;
    }
    // We may use some pointer arithmetic to drop brightes stars from these arrays,
    // but we need to keep track of the original pointers to free the arrays properly
    poly_x_original_pointer= poly_x;
    poly_y_original_pointer= poly_y;
    poly_err_original_pointer= poly_err;

    if ( apply_position_dependent_correction == 1 ) {
     // lin_mag_cor_x = (double *)malloc(MIN( Number_of_ecv_star, NUMBER3) * sizeof(double));
     // lin_mag_cor_y = (double *)malloc(MIN( Number_of_ecv_star, NUMBER3) * sizeof(double));
     // lin_mag_cor_z = (double *)malloc(MIN( Number_of_ecv_star, NUMBER3) * sizeof(double));
     lin_mag_cor_x= (double *)malloc( malloc_size );
     lin_mag_cor_y= (double *)malloc( malloc_size );
     lin_mag_cor_z= (double *)malloc( malloc_size );
     if ( lin_mag_cor_x == NULL || lin_mag_cor_y == NULL || lin_mag_cor_z == NULL ) {
      fprintf( stderr, "ERROR: can't allocate memory for magnitude correction!\n" );
      vast_report_memory_error();
      return EXIT_FAILURE;
     }
    }

    // populate the arrays of comparison stars for magnitude calibration
    for ( i= 0; i < MIN( Number_of_ecv_star, NUMBER3 ); i++ ) {
     // STAR1[Pos1[i]].magmag==0.0 if the star was not detected on the reference frame
     if ( -1 == exclude_test( STAR1[Pos1[i]].x, STAR1[Pos1[i]].y, bad_stars_X, bad_stars_Y, N_bad_stars, 1 ) && fabs( STAR1[Pos1[i]].mag - STAR2[Pos2[i]].mag ) < MAX_INSTR_MAG_DIFF && STAR1[Pos1[i]].mag != 0.0
          //&& STAR1[Pos1[i]].sextractor_flag==0
          && STAR1[Pos1[i]].sextractor_flag <= 1 && STAR1[Pos1[i]].vast_flag == 0 && STAR1[Pos1[i]].moving_object == 0
          //&& STAR2[Pos2[i]].sextractor_flag==0
          && STAR2[Pos2[i]].sextractor_flag <= 1 && STAR2[Pos2[i]].vast_flag == 0 && STAR2[Pos2[i]].moving_object == 0 ) {

      if ( N_manually_selected_comparison_stars > 0 ) {
       // fprintf(stderr, "Performing magnitude calibration using manually selected comparison stars\n");
       //  Handle the special case of a set of manually selected comparison stars
       if ( exclude_test( STAR1[Pos1[i]].x, STAR1[Pos1[i]].y, manually_selected_comparison_stars_X, manually_selected_comparison_stars_Y, N_manually_selected_comparison_stars, 0 ) != -1 ) {
        poly_x[N_good_stars]= (double)STAR2[Pos2[i]].mag;
        poly_y[N_good_stars]= (double)STAR1[Pos1[i]].mag;
        poly_err[N_good_stars]= (double)STAR2[Pos2[i]].sigma_mag;
        poly_err_fake[N_good_stars]= 0.01; // fake error for unweighted fitting
        N_good_stars+= 1;
       }
      } else {
       // fprintf(stderr, "Performing magnitude calibration using automatically selected comparison stars\n");
       //  Handle the normal case of using all the good matched stars for magnitude calibration
       poly_x[N_good_stars]= (double)STAR2[Pos2[i]].mag;
       poly_y[N_good_stars]= (double)STAR1[Pos1[i]].mag;
       poly_err[N_good_stars]= (double)STAR2[Pos2[i]].sigma_mag;
       // no obvious gain if we take into acocunt the reference frame-derived errors (as we collect more images - we iprove reference magnitudes?)
       // poly_err[N_good_stars]= sqrt( (double)STAR2[Pos2[i]].sigma_mag*(double)STAR2[Pos2[i]].sigma_mag + (double)STAR1[Pos1[i]].sigma_mag*(double)STAR1[Pos1[i]].sigma_mag );
       poly_err_fake[N_good_stars]= 0.01; // fake error for unweighted fitting

       if ( apply_position_dependent_correction == 1 ) {
        lin_mag_cor_x[N_good_stars]= (double)STAR2[Pos2[i]].x_frame;
        lin_mag_cor_y[N_good_stars]= (double)STAR2[Pos2[i]].y_frame;
       }
       N_good_stars+= 1;
      } // else if ( N_manually_selected_comparison_stars>0 ) {
      //} else {
      // fprintf(stderr, "Excluding star %.3f %.3f from magnitude calibration - it's close to the pixel position specified in exclude.lst\n", STAR1[Pos1[i]].x, STAR1[Pos1[i]].y );
     } // if ( 0 == exclude_test( STAR1[Pos1[i]].x, STAR1[Pos1[i]].y, bad_stars_X, bad_stars_Y, N_bad_stars ) && fabs( STAR1[Pos1[i]].mag - STAR2[Pos2[i]].mag ) ...
    } // for ( i= 0; i < MIN( Number_of_ecv_star, NUMBER3 ); i++ ) {
    // Handle the case where the majority of stars have the 'blended' flag
    // Don't do that if the manually selected comparison stars were provided
    if ( N_good_stars < (double)( MIN( Number_of_ecv_star, NUMBER3 ) ) / 2.0 && N_manually_selected_comparison_stars == 0 ) {
     N_good_stars= 0;
     // repopulate the arrays
     for ( i= 0; i < MIN( Number_of_ecv_star, NUMBER3 ); i++ ) {
      // STAR1[Pos1[i]].magmag==0.0 if the star was not detected on the reference frame
      if ( -1 == exclude_test( STAR1[Pos1[i]].x, STAR1[Pos1[i]].y, bad_stars_X, bad_stars_Y, N_bad_stars, 1 ) && fabs( STAR1[Pos1[i]].mag - STAR2[Pos2[i]].mag ) < MAX_INSTR_MAG_DIFF && STAR1[Pos1[i]].mag != 0.0
           //&& STAR1[Pos1[i]].sextractor_flag==0
           && STAR1[Pos1[i]].sextractor_flag <= 3 && STAR1[Pos1[i]].vast_flag == 0 && STAR1[Pos1[i]].moving_object == 0
           //&& STAR2[Pos2[i]].sextractor_flag==0
           && STAR2[Pos2[i]].sextractor_flag <= 3 && STAR2[Pos2[i]].vast_flag == 0 && STAR2[Pos2[i]].moving_object == 0 ) {
       poly_x[N_good_stars]= (double)STAR2[Pos2[i]].mag;
       poly_y[N_good_stars]= (double)STAR1[Pos1[i]].mag;
       poly_err[N_good_stars]= (double)STAR2[Pos2[i]].sigma_mag;
       poly_err_fake[N_good_stars]= 0.01; // fake error for unweighted fitting

       if ( apply_position_dependent_correction == 1 ) {
        lin_mag_cor_x[N_good_stars]= (double)STAR2[Pos2[i]].x_frame;
        lin_mag_cor_y[N_good_stars]= (double)STAR2[Pos2[i]].y_frame;
       }

       N_good_stars+= 1;
      } // if( 0==exclude_test ...
     } // for (i = 0; i < MIN( Number_of_ecv_star, NUMBER3) ; i++) {
    } // if( N_good_stars<(double)(MIN( Number_of_ecv_star, NUMBER3))/2.0 ){

    if ( N_manually_selected_comparison_stars > 0 ) {
     fprintf( stderr, "Performing magnitude calibration using manually selected comparison stars\n" );
    } else {
     fprintf( stderr, "Performing magnitude calibration using automatically selected comparison stars\n" );
    }

    // make sure we don't have an estimated error == 0.0
    for ( i= 0; i < N_good_stars; i++ ) {
     // Make sure poly_err[i] is not 0
     if ( poly_err[i] == 0.0 ) {
      fprintf( stderr, "WARNING: zero error encountered while calibrating magnitudes!\n" );
      poly_err[i]= 0.1; // assume some large error
      //  Try to refine this wild guess by setting the error to the smallest significant value we have seen so far
      for ( j_poly_err= 0; j_poly_err < N_good_stars; j_poly_err++ ) {
       if ( poly_err[j_poly_err] < poly_err[i] && poly_err[j_poly_err] > 0.0 ) {
        poly_err[i]= poly_err[j_poly_err];
       }
      }
      fprintf( stderr, "Trying to handle it by setting the magnitude error to %.5lf\n", poly_err[i] );
     }
     // Forbid small errors
     // SURPRISINGLY, this significantly reduces the magnitude calibration accuracy!!!!!!
     // Don't use it!!!!
     // poly_err[i]=MAX( poly_err[i], MIN_MAG_ERR_FROM_SEXTRACTOR);
    }
    // -------------------------------------------------
    if ( debug != 0 ) {
     fprintf( stderr, "%d stars selected for mag. calibr. (N_good_stars)\n", N_good_stars );
    }
    if ( debug != 0 ) {
     fprintf( stderr, "DEBUG MSG: flush poly_coeff - " );
    }
    poly_coeff[0]= 0.0;
    poly_coeff[1]= 0.0;
    poly_coeff[2]= 0.0;
    poly_coeff[3]= 0.0;
    poly_coeff[4]= 0.0;
    //
    poly_coeff[5]= 0.0;
    poly_coeff[6]= 0.0;
    poly_coeff[7]= 0.0;
    poly_coeff[8]= 0.0;
    poly_coeff[9]= 0.0;
    //
    if ( debug != 0 ) {
     fprintf( stderr, "OK\n" );
    }
    //////
    // Decide how many stars we need for magnitude calibration
    min_number_of_stars_for_magnitude_calibration= MIN( (int)( (double)MIN( NUMBER2, NUMBER3 ) / 3.0 ), MIN_NUMBER_STARS_POLY_MAG_CALIBR );
    // Relax min_number_of_stars_for_magnitude_calibration if we do zero-point only calibration (NMW good reference vs bad new image)
    if ( photometric_calibration_type == 2 ) {
     min_number_of_stars_for_magnitude_calibration= MIN( min_number_of_stars_for_magnitude_calibration, MIN_NUMBER_STARS_ZEROPOINT_MAG_CALIB );
    }
    min_number_of_stars_for_magnitude_calibration= MAX( min_number_of_stars_for_magnitude_calibration, 1 ); // we need at least one comparison star, that's for sure

    fprintf( stderr, "Expecting to find at least %d * for magnitude calibration\n", min_number_of_stars_for_magnitude_calibration );
    fprintf( stderr, "We have N_good_stars = %d, N_manually_selected_comparison_stars = %d\n", N_good_stars, N_manually_selected_comparison_stars );
    //////

    // If we don't have enough stars to perform a reliable magnitude calibration
    if ( N_good_stars < min_number_of_stars_for_magnitude_calibration && N_manually_selected_comparison_stars == 0 ) {
     wpolyfit_exit_code= 1;
     write_string_to_individual_image_log( sextractor_catalog, "main(): ", "ERROR: to few stars to perform magnitude calibration ", "" );
    } else {

     // Write data to log
     sprintf( filename_for_magnitude_calibration_log, "image%05d__%s", n, basename( input_images[n] ) );
     // write_magnitude_calibration_log( poly_x, poly_y, poly_err, N_good_stars, input_images[n] );
     write_magnitude_calibration_log( poly_x, poly_y, poly_err, N_good_stars, filename_for_magnitude_calibration_log );

     if ( debug != 0 ) {
      fprintf( stderr, "DEBUG MSG: GSL: wpolyfit - " );
     }

     /// Here we try to weed-out potential variable stars from the magnitude calibration data

     if ( photometric_calibration_type == 2 ) {
      min_number_of_stars_for_magnitude_calibration= 1; // we can survive with only a single comparison star in this mode
      // Filter the comparison stars for the zero-point-only calibration
      if ( N_good_stars > 3 && N_manually_selected_comparison_stars > 0 ) {
       // remove the brightest star, it is typically bad
       // but not if it was explicitly specified by the user
       number_of_bright_stars_to_drop_from_mag_calibr= 1;
       fprintf( stderr, "Excluding %d brightest stars from magnitude calibration\n", number_of_bright_stars_to_drop_from_mag_calibr );
       // Pointer Arithmetic https://stackoverflow.com/questions/394767/pointer-arithmetic
       poly_x= poly_x + number_of_bright_stars_to_drop_from_mag_calibr;
       poly_y= poly_y + number_of_bright_stars_to_drop_from_mag_calibr;
       poly_err= poly_err + number_of_bright_stars_to_drop_from_mag_calibr;
       N_good_stars= N_good_stars - number_of_bright_stars_to_drop_from_mag_calibr;
       //
      }
      if ( N_good_stars > 3 && N_manually_selected_comparison_stars > 0 ) {
       // but not if they were explicitly specified by the user
       N_good_stars= MAX( (int)( 0.1 * N_good_stars ), 3 ); // keep only the few brightest stars
       fprintf( stderr, "Using only %d brightest stars from magnitude calibration\n", N_good_stars );
      }
      if ( N_good_stars > 3 ) {
       malloc_size= N_good_stars * sizeof( double );
       if ( malloc_size <= 0 ) {
        fprintf( stderr, "ERROR - trying to allocate zero or negative number of bytes!\n" );
        return EXIT_FAILURE;
       }
       comparison_star_mag_diff= malloc( malloc_size );
       if ( comparison_star_mag_diff == NULL ) {
        fprintf( stderr, "Memory allocation ERROR\n" );
        vast_report_memory_error();
        return EXIT_FAILURE;
       }
       for ( comparison_star_counter= 0; comparison_star_counter < N_good_stars; comparison_star_counter++ ) {
        comparison_star_mag_diff[comparison_star_counter]= poly_y[comparison_star_counter] - poly_x[comparison_star_counter];
       }
       gsl_sort( comparison_star_mag_diff, 1, N_good_stars );
       comparison_star_median_mag_diff= gsl_stats_median_from_sorted_data( comparison_star_mag_diff, 1, N_good_stars );
       sigma_from_MAD= esimate_sigma_from_MAD_of_sorted_data( comparison_star_mag_diff, (long)N_good_stars );
       fprintf( stderr, "Zero-point offset = %.4lf +/-%.4lf mag (sigma= %.4lf mag)\n", comparison_star_median_mag_diff, sigma_from_MAD / sqrt( (double)N_good_stars ), sigma_from_MAD );
       free( comparison_star_mag_diff );
       // Now filter-out the outliers
       comparison_star_poly_x_good= malloc( malloc_size );
       comparison_star_poly_y_good= malloc( malloc_size );
       comparison_star_poly_err_good= malloc( malloc_size );
       if ( comparison_star_poly_x_good == NULL || comparison_star_poly_y_good == NULL || comparison_star_poly_err_good == NULL ) {
        fprintf( stderr, "Memory allocation ERROR comparison_star_poly_x_good comparison_star_poly_y_good comparison_star_poly_err_good\n" );
        vast_report_memory_error();
        return EXIT_FAILURE;
       }
       comparison_star_counter2= 0;
       for ( comparison_star_counter= 0; comparison_star_counter < N_good_stars; comparison_star_counter++ ) {
        if ( fabs( ( poly_y[comparison_star_counter] - poly_x[comparison_star_counter] ) - comparison_star_median_mag_diff ) < 3.0 * sigma_from_MAD ) {
         // if( fabs((poly_y[comparison_star_counter] - poly_x[comparison_star_counter]) - comparison_star_median_mag_diff) < 6.0 * sigma_from_MAD ) {
         comparison_star_poly_x_good[comparison_star_counter2]= poly_x[comparison_star_counter];
         comparison_star_poly_y_good[comparison_star_counter2]= poly_y[comparison_star_counter];
         comparison_star_poly_err_good[comparison_star_counter2]= poly_err[comparison_star_counter];
         comparison_star_counter2++;
        } else {
         fprintf( stderr, "Rejecting a star from magnitude calibration (sigma-clipping magnitude difference): m1=%.3lf m2=%.3lf |(m1-m2)-mediandiff|=%.3lf  sigma(MAD)=%.3lf \n", poly_y[comparison_star_counter], poly_x[comparison_star_counter], fabs( ( poly_y[comparison_star_counter] - poly_x[comparison_star_counter] ) - comparison_star_median_mag_diff ), sigma_from_MAD );
        }
       }
       // Copy the good points back
       for ( comparison_star_counter= 0; comparison_star_counter < comparison_star_counter2; comparison_star_counter++ ) {
        poly_x[comparison_star_counter]= comparison_star_poly_x_good[comparison_star_counter];
        poly_y[comparison_star_counter]= comparison_star_poly_y_good[comparison_star_counter];
        poly_err[comparison_star_counter]= comparison_star_poly_err_good[comparison_star_counter];
       }
       N_good_stars= comparison_star_counter2;
       free( comparison_star_poly_err_good );
       free( comparison_star_poly_y_good );
       free( comparison_star_poly_x_good );
       //
      }

     } else {
      // Filter the comparison stars for the usual linear/quadratic/photocurve calibration

      // First pass - remove really bad outliers usin unweighted linear approximation
      fprintf( stderr, "Iteratively removing outliers from the linear mag-mag relation (unweighted fit)...\n" );
      // Use linear function as the first-order approximation
      // wpolyfit_exit_code=wlinearfit(poly_x, poly_y, poly_err_fake, N_good_stars, poly_coeff);
      wpolyfit_exit_code= robustlinefit( poly_x, poly_y, N_good_stars, poly_coeff );
      do {
       the_baddest_outlier= 0.0;
       the_baddest_outlier_number= -1;
       for ( exclude_outlier_mags_counter= N_good_stars; exclude_outlier_mags_counter--; ) {
        computed_mag= poly_coeff[1] * poly_x[exclude_outlier_mags_counter] + poly_coeff[0];
        // find the baddest outlier
        abs_computed_predicted_mag_diff= fabs( computed_mag - poly_y[exclude_outlier_mags_counter] );
        if ( abs_computed_predicted_mag_diff > 3 * MAX_DIFF_POLY_MAG_CALIBRATION && abs_computed_predicted_mag_diff > the_baddest_outlier ) {
         the_baddest_outlier= abs_computed_predicted_mag_diff;
         the_baddest_outlier_number= exclude_outlier_mags_counter;
        }
       }
       // And now remove the baddest outlier
       if ( the_baddest_outlier_number >= 0 ) {
        // Exclude bad point from calibration
        if ( apply_position_dependent_correction == 0 )
         exclude_from_3_double_arrays( poly_x, poly_y, poly_err, the_baddest_outlier_number, &N_good_stars );
        else
         exclude_from_6_double_arrays( poly_x, poly_y, poly_err, lin_mag_cor_x, lin_mag_cor_y, lin_mag_cor_z, the_baddest_outlier_number, &N_good_stars );
        // Recompute fit using unweighted linear fit
        // wpolyfit_exit_code=wlinearfit(poly_x, poly_y, poly_err_fake, N_good_stars, poly_coeff);
        wpolyfit_exit_code= robustlinefit( poly_x, poly_y, N_good_stars, poly_coeff );
       }
      } while ( the_baddest_outlier_number >= 0 );
     } // Iteratively removing outliers from the linear mag-mag relation (unweighted fit)

     /* Check that we haven't dropped too many stars so the parabolic fit still make sence */
     if ( N_good_stars < min_number_of_stars_for_magnitude_calibration ) {
      wpolyfit_exit_code= 1;
      fprintf( stderr, "ERROR01 - too few stars for magnitude calibration: %d\n", N_good_stars );
     }

     // Linear CCD position dependent corrections
     if ( apply_position_dependent_correction == 1 && wpolyfit_exit_code == 0 ) {
      // Populate the array
      for ( i= 0; i < N_good_stars; i++ ) {
       lin_mag_cor_z[i]= poly_coeff[1] * poly_x[i] + poly_coeff[0] - poly_y[i];
      }
      // Fit a plane in the (X, Y, delta_mag) space

      fit_plane_lin( lin_mag_cor_x, lin_mag_cor_y, lin_mag_cor_z, (unsigned int)N_good_stars, &lin_mag_A, &lin_mag_B, &lin_mag_C );
      // write_magnitude_calibration_log_plane( lin_mag_cor_x, lin_mag_cor_y, lin_mag_cor_z, N_good_stars, input_images[n], lin_mag_A, lin_mag_B, lin_mag_C );
      write_magnitude_calibration_log_plane( lin_mag_cor_x, lin_mag_cor_y, lin_mag_cor_z, N_good_stars, filename_for_magnitude_calibration_log, lin_mag_A, lin_mag_B, lin_mag_C );

      // Iteratively remove outliers
      do {
       the_baddest_outlier= 0.0;
       the_baddest_outlier_number= -1;
       for ( exclude_outlier_mags_counter= N_good_stars; exclude_outlier_mags_counter--; ) {
        computed_mag= poly_coeff[1] * poly_x[exclude_outlier_mags_counter] + poly_coeff[0];
        // find the baddest outlier
        abs_computed_predicted_mag_diff= fabs( computed_mag - poly_y[exclude_outlier_mags_counter] );
        if ( abs_computed_predicted_mag_diff > 3 * MAX_DIFF_POLY_MAG_CALIBRATION && abs_computed_predicted_mag_diff > the_baddest_outlier ) {
         the_baddest_outlier= abs_computed_predicted_mag_diff;
         the_baddest_outlier_number= exclude_outlier_mags_counter;
        }
       }
       // And now remove the baddest outlier
       if ( the_baddest_outlier_number >= 0 ) {
        // Exclude bad point from calibration
        exclude_from_6_double_arrays( poly_x, poly_y, poly_err, lin_mag_cor_x, lin_mag_cor_y, lin_mag_cor_z, the_baddest_outlier_number, &N_good_stars );
        // Recompute fit using unweighted linear fit
        // wpolyfit_exit_code=wlinearfit(poly_x, poly_y, poly_err_fake, N_good_stars, poly_coeff);
        wpolyfit_exit_code= robustlinefit( poly_x, poly_y, N_good_stars, poly_coeff );
        // Populate the array
        for ( i= 0; i < N_good_stars; i++ ) {
         lin_mag_cor_z[i]= poly_coeff[1] * poly_x[i] + poly_coeff[0] - poly_y[i];
        }
        // Fit a plane in the (X, Y, delta_mag) space
        fit_plane_lin( lin_mag_cor_x, lin_mag_cor_y, lin_mag_cor_z, (unsigned int)N_good_stars, &lin_mag_A, &lin_mag_B, &lin_mag_C );
       }
      } while ( the_baddest_outlier_number >= 0 );

      // Apply the linear CCD position dependent corrections
      for ( i= 0; i < N_good_stars; i++ ) {
       poly_y[i]= poly_y[i] + ( lin_mag_A * lin_mag_cor_x[i] + lin_mag_B * lin_mag_cor_y[i] + lin_mag_C );
      } // fprintf(stderr,"DEBUG: %lf\n",lin_mag_A*lin_mag_cor_x[i]+lin_mag_B*lin_mag_cor_y[i]+lin_mag_C);}
      // write_magnitude_calibration_log2( poly_x, poly_y, poly_err, N_good_stars, input_images[n] );
      write_magnitude_calibration_log2( poly_x, poly_y, poly_err, N_good_stars, filename_for_magnitude_calibration_log );
      fprintf( stderr, "Using the linear CCD position-dependent magnitude correction:\n delta_m = %7.5lf*X_pix %+7.5lf*Y_pix %+7.5lf\n", lin_mag_A, lin_mag_B, lin_mag_C );
      // write_magnitude_calibration_log_plane( lin_mag_cor_x, lin_mag_cor_y, lin_mag_cor_z, N_good_stars, input_images[n], lin_mag_A, lin_mag_B, lin_mag_C );
      write_magnitude_calibration_log_plane( lin_mag_cor_x, lin_mag_cor_y, lin_mag_cor_z, N_good_stars, filename_for_magnitude_calibration_log, lin_mag_A, lin_mag_B, lin_mag_C );

      // Check if the magnitude correction is not too large
      if ( fabs( lin_mag_C ) > MAX_LIN_CORR_MAG ) {
       fprintf( stderr, "ERROR in magnitude calibration: fabs(lin_mag_C) > MAX_LIN_CORR_MAG\n" );
       wpolyfit_exit_code= 1;
      }
      if ( fabs( lin_mag_A * X_im_size + lin_mag_C ) > MAX_LIN_CORR_MAG ) {
       fprintf( stderr, "ERROR in magnitude calibration: fabs(lin_mag_A * X_im_size + lin_mag_C) > MAX_LIN_CORR_MAG\n" );
       wpolyfit_exit_code= 1;
      }
      if ( fabs( lin_mag_B * Y_im_size + lin_mag_C ) > MAX_LIN_CORR_MAG ) {
       fprintf( stderr, "ERROR in magnitude calibration: fabs(lin_mag_B * Y_im_size + lin_mag_C) > MAX_LIN_CORR_MAG\n" );
       wpolyfit_exit_code= 1;
      }
      if ( fabs( lin_mag_A * X_im_size + lin_mag_B * Y_im_size + lin_mag_C ) > MAX_LIN_CORR_MAG ) {
       fprintf( stderr, "ERROR in magnitude calibration: fabs(lin_mag_A * X_im_size + lin_mag_B * Y_im_size + lin_mag_C) > MAX_LIN_CORR_MAG\n" );
       wpolyfit_exit_code= 1;
      }

      // Use linear function as an approximation
      if ( wpolyfit_exit_code == 0 ) {
       // wpolyfit_exit_code=wlinearfit(poly_x, poly_y, poly_err_fake, N_good_stars, poly_coeff);
       wpolyfit_exit_code= robustlinefit( poly_x, poly_y, N_good_stars, poly_coeff );
       do {
        the_baddest_outlier= 0.0;
        the_baddest_outlier_number= -1;
        for ( exclude_outlier_mags_counter= N_good_stars; exclude_outlier_mags_counter--; ) {
         computed_mag= poly_coeff[1] * poly_x[exclude_outlier_mags_counter] + poly_coeff[0];
         // find the baddest outlier
         abs_computed_predicted_mag_diff= fabs( computed_mag - poly_y[exclude_outlier_mags_counter] );
         if ( abs_computed_predicted_mag_diff > 3 * MAX_DIFF_POLY_MAG_CALIBRATION && abs_computed_predicted_mag_diff > the_baddest_outlier ) {
          the_baddest_outlier= abs_computed_predicted_mag_diff;
          the_baddest_outlier_number= exclude_outlier_mags_counter;
         }
        }
        // And now remove the baddest outlier
        if ( the_baddest_outlier_number >= 0 ) {
         // Exclude bad point from calibration
         // exclude_from_3_double_arrays(poly_x, poly_y, poly_err, the_baddest_outlier_number, &N_good_stars);
         exclude_from_6_double_arrays( poly_x, poly_y, poly_err, lin_mag_cor_x, lin_mag_cor_y, lin_mag_cor_z, the_baddest_outlier_number, &N_good_stars );
         // Recompute fit using unweighted linear fit
         // wpolyfit_exit_code=wlinearfit(poly_x, poly_y, poly_err_fake, N_good_stars, poly_coeff);
         wpolyfit_exit_code= robustlinefit( poly_x, poly_y, N_good_stars, poly_coeff );
        }
       } while ( the_baddest_outlier_number >= 0 );

       /* Check that we haven't dropped too many stars so the parabolic fit still make sence */
       if ( N_good_stars < min_number_of_stars_for_magnitude_calibration ) {
        wpolyfit_exit_code= 1;
        fprintf( stderr, "ERROR02 - too few stars for magnitude calibration: %d\n", N_good_stars );
       }
      } // if( wpolyfit_exit_code==0 ){
     } // if( apply_position_dependent_correction==1 && wpolyfit_exit_code==0 ){

     // Second pass - remove the remaining outlier using weighted approximation
     if ( wpolyfit_exit_code == 0 && photometric_calibration_type != 2 ) {
      // Use linear function as the very first approximation
      wpolyfit_exit_code= wlinearfit( poly_x, poly_y, poly_err, N_good_stars, poly_coeff, NULL );
      fprintf( stderr, "Iteratively removing outliers from the mag-mag relation (weighted linear/polynomial fit)...\n" );
      do {
       the_baddest_outlier= 0.0;
       the_baddest_outlier_number= -1;
       for ( exclude_outlier_mags_counter= N_good_stars; exclude_outlier_mags_counter--; ) {
        computed_mag= poly_coeff[2] * poly_x[exclude_outlier_mags_counter] * poly_x[exclude_outlier_mags_counter] + poly_coeff[1] * poly_x[exclude_outlier_mags_counter] + poly_coeff[0];
        // find the baddest outlier
        abs_computed_predicted_mag_diff= fabs( computed_mag - poly_y[exclude_outlier_mags_counter] );
        if ( abs_computed_predicted_mag_diff > MAX_DIFF_POLY_MAG_CALIBRATION && abs_computed_predicted_mag_diff > the_baddest_outlier ) {
         the_baddest_outlier= abs_computed_predicted_mag_diff;
         the_baddest_outlier_number= exclude_outlier_mags_counter;
        }
       }
       // And now remove the baddest outlier
       if ( the_baddest_outlier_number >= 0 ) {
        // Exclude bad point from calibration
        if ( apply_position_dependent_correction == 0 )
         exclude_from_3_double_arrays( poly_x, poly_y, poly_err, the_baddest_outlier_number, &N_good_stars );
        else
         exclude_from_6_double_arrays( poly_x, poly_y, poly_err, lin_mag_cor_x, lin_mag_cor_y, lin_mag_cor_z, the_baddest_outlier_number, &N_good_stars );
        // Recompute fit using linear or parabolic function depending on settings
        if ( photometric_calibration_type == 0 ) {
         wpolyfit_exit_code= wlinearfit( poly_x, poly_y, poly_err, N_good_stars, poly_coeff, NULL );
        } else {
         wpolyfit_exit_code= wpolyfit( poly_x, poly_y, poly_err, N_good_stars, poly_coeff, NULL );
        }
       } // if(the_baddest_outlier_number>=0){
      } while ( the_baddest_outlier_number >= 0 );
      ////////////////////////////////////////////
      //
      // FILE *magcalibdebugfile;
      // magcalibdebugfile=fopen("magcalibdebug.txt","w");
      // for(i=0;i<N_good_stars;i++){
      // fprintf(magcalibdebugfile,"%lf %lf %lf\n",poly_x[i],poly_y[i],poly_err[i]);
      //}
      // fclose(magcalibdebugfile);
      //
      ////////////////////////////////////////////

      // Drop one of the 10 brightest stars that changes fit the most,
      // this is to handle the case when one of the brightest stars is actually variable
      if ( N_good_stars >= 10 ) {
       drop_one_point_that_changes_fit_the_most( poly_x, poly_y, poly_err, &N_good_stars, photometric_calibration_type, param_use_photocurve );
      }

      /* Check that we haven't dropped too many stars so the parabolic fit still make sense */
      if ( N_good_stars < min_number_of_stars_for_magnitude_calibration ) {
       wpolyfit_exit_code= 1;
       fprintf( stderr, "ERROR03 - too few stars for magnitude calibration: %d\n", N_good_stars );
      } else {
       if ( debug != 0 ) {
        fprintf( stderr, "OK %d\n", wpolyfit_exit_code );
       }
      }

      //// Redo the final fit here, just in case
      //if ( photometric_calibration_type == 0 ) {
      // wpolyfit_exit_code= wlinearfit( poly_x, poly_y, poly_err, N_good_stars, poly_coeff, NULL );
      //} else {
      // wpolyfit_exit_code= wpolyfit( poly_x, poly_y, poly_err, N_good_stars, poly_coeff, NULL );
      //}
      // Redo the final fit here, just in case
      if ( photometric_calibration_type == 0 ) {
       fprintf( stderr, "Computing weighted linear magnitude calibration.\n" );
       wpolyfit_exit_code= wlinearfit( poly_x, poly_y, poly_err, N_good_stars, poly_coeff, NULL );
      } else if ( photometric_calibration_type == 4 ) {
       fprintf( stderr, "Computing robust linear magnitude calibration.\n" );
       wpolyfit_exit_code= robustlinefit( poly_x, poly_y, N_good_stars, poly_coeff );
       // !!! poly_coeff[4] is not supposed to be used as an actual polynomial coefficient - we use it as a flag instead
       poly_coeff[4]= 6.0; // Set fit function type for fit_mag_calib.c
      } else {
       fprintf( stderr, "Computing polynomial magnitude calibration.\n" );
       wpolyfit_exit_code= wpolyfit( poly_x, poly_y, poly_err, N_good_stars, poly_coeff, NULL );
      }
      /* Above we assume that parabola was a reasonable approximation.
                                                           Now we use photocurve for magnitude calibration if param_use_photocurve is set. */
      if ( param_use_photocurve != 0 && wpolyfit_exit_code == 0 ) {
       fprintf( stderr, "Computing 'photocurve' magnitude calibration.\n" );
       wpolyfit_exit_code= fit_photocurve( poly_x, poly_y, poly_err, N_good_stars, poly_coeff, &param_use_photocurve, NULL );
       poly_coeff[4]= (double)param_use_photocurve;
      }

      /* Write calibration parameters to log files */
      // write_magnitude_calibration_param_log( poly_coeff, input_images[n] );
      write_magnitude_calibration_param_log( poly_coeff, filename_for_magnitude_calibration_log );

     } // if( wpolyfit_exit_code==0 ){
     else {
      if ( photometric_calibration_type == 2 ) {
       fprintf( stderr, "Computing zero-point only magnitude calibration.\n" );
       // wpolyfit_exit_code= robustzeropointfit( poly_x, poly_y, MAX( (int)(0.1*N_good_stars), 3), poly_coeff );
       // wpolyfit_exit_code= robustzeropointfit( poly_x + 1, poly_y + 1, MAX( (int)(0.1*N_good_stars), 3), poly_coeff );
       //  filtering moved above
       wpolyfit_exit_code= robustzeropointfit( poly_x, poly_y, poly_err, N_good_stars, poly_coeff );
       // write_magnitude_calibration_param_log( poly_coeff, input_images[n] );
       write_magnitude_calibration_param_log( poly_coeff, filename_for_magnitude_calibration_log );
      }
     }
     fprintf( stderr, "Used %d stars for magnitude calibration (after filtering).\n", N_good_stars );
    } // if we have enought stars for mag calibration
    if ( debug != 0 )
     fprintf( stderr, "DEBUG MSG: free(poly_x) - " );
    // free( poly_x );
    free( poly_x_original_pointer );
    if ( debug != 0 )
     fprintf( stderr, "OK\n" );
    if ( debug != 0 )
     fprintf( stderr, "DEBUG MSG: free(poly_y) - " );
    // free( poly_y );
    free( poly_y_original_pointer );
    if ( debug != 0 )
     fprintf( stderr, "OK\n" );
    if ( debug != 0 )
     fprintf( stderr, "DEBUG MSG: free(poly_err) - " );
    // free( poly_err );
    free( poly_err_original_pointer );
    if ( debug != 0 )
     fprintf( stderr, "OK\n" );
    free( poly_err_fake );

    if ( apply_position_dependent_correction == 1 ) {
     free( lin_mag_cor_x );
     free( lin_mag_cor_y );
     free( lin_mag_cor_z );
    }

    if ( debug != 0 ) {
     fprintf( stderr, "DEBUG MSG: It was a lot of work, OK now\n" );
    }
    if ( wpolyfit_exit_code == 0 ) {
     /* Transform all magnitudes to the ref-frame system. */
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: Mag. transform - " );
     // for (i = 0; i < NUMBER2; i++) {
     for ( i= NUMBER2; i--; ) {
      if ( param_use_photocurve != 0 ) {
       // If we use the "photocurve" for magnitude calibration
       if ( apply_position_dependent_correction == 1 ) {
        // Aplly CCD position dependent correction
        STAR2[Pos2[i]].mag= (float)eval_photocurve( (double)STAR2[Pos2[i]].mag, poly_coeff, param_use_photocurve ) - ( lin_mag_A * STAR2[Pos2[i]].x_frame + lin_mag_B * STAR2[Pos2[i]].y_frame + lin_mag_C );
       } else {
        // Do not Aplly CCD position dependent correction
        STAR2[Pos2[i]].mag= (float)eval_photocurve( (double)STAR2[Pos2[i]].mag, poly_coeff, param_use_photocurve );
       }
      } else {
       // If we use a linear or parabolic calibration curve
       if ( apply_position_dependent_correction == 1 ) {
        // Aplly CCD position dependent correction
        //STAR2[Pos2[i]].mag= STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * (float)poly_coeff[4] + STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * (float)poly_coeff[3] + STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * (float)poly_coeff[2] + STAR2[Pos2[i]].mag * (float)poly_coeff[1] + (float)poly_coeff[0] - ( lin_mag_A * STAR2[Pos2[i]].x_frame + lin_mag_B * STAR2[Pos2[i]].y_frame + lin_mag_C );
        STAR2[Pos2[i]].mag= STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * (float)poly_coeff[2] + STAR2[Pos2[i]].mag * (float)poly_coeff[1] + (float)poly_coeff[0] - ( lin_mag_A * STAR2[Pos2[i]].x_frame + lin_mag_B * STAR2[Pos2[i]].y_frame + lin_mag_C );
       } else {
        // Do not Aplly CCD position dependent correction
        //STAR2[Pos2[i]].mag= STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * (float)poly_coeff[4] + STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * (float)poly_coeff[3] + STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * (float)poly_coeff[2] + STAR2[Pos2[i]].mag * (float)poly_coeff[1] + (float)poly_coeff[0];
        // 2nd order polynomial (parabola) is already a massive overkill in most situations - let's not support higher order polynomials
        STAR2[Pos2[i]].mag= STAR2[Pos2[i]].mag * STAR2[Pos2[i]].mag * (float)poly_coeff[2] + STAR2[Pos2[i]].mag * (float)poly_coeff[1] + (float)poly_coeff[0];
       }
      }
     }
     if ( debug != 0 )
      fprintf( stderr, "OK\n" );
    }
    //} // nocalib ??

    /* Write to log file if everything whent well or not */
    if ( wpolyfit_exit_code == 0 ) {
     sprintf( log_output, "status=OK     %s\n", input_images[n] );
     write_string_to_log_file( log_output, sextractor_catalog );
     MATCH_SUCESS++;
    } else {
     sprintf( log_output, "status=ERROR  %s\n", input_images[n] );
     write_string_to_log_file( log_output, sextractor_catalog );
     fprintf( stderr, "\x1B[01;31m ERROR!!! Magnitude calibration failure. Dropping image. \x1B[33;00m\n" ); // and print to the terminal that there was a problem
    }

    // ADD NEW STARS ONLY IF THE MAGNITUDE SCALE COULD BE SUCCESSFULY CALIBRATED
    //
    // If we can't calibrate magnitudes, something is not right with this image - better skip it altogether
    //

    //// **** Add new stars (which were not detected on the reference frame) to STAR1 - the structure with reference stars  ****
    if ( param_failsafe == 0 && Number_of_ecv_star > 0 && wpolyfit_exit_code == 0 ) {

     // We are now resizing Pos1 eralier, before attempting star matching
     // Pos1 = realloc(Pos1, sizeof(int) * ( MAX(NUMBER1,NUMBER2) + 1) );
     // fprintf(stderr,"MEGADEBUG: %d %d  %d \n",NUMBER1,NUMBER2, MAX(NUMBER1,NUMBER2) + 1);
     //

     // number_of_elements_in_Pos1=Number_of_ecv_star; // This is how Ident works
     //
     for ( i= Number_of_ecv_star; i < NUMBER2; i++ ) {
      // fprintf(stderr,"DEBUG: NUMBER1=%d i=%d Number_of_ecv_star=%d NUMBER2=%d\n",NUMBER1,i,Number_of_ecv_star,NUMBER2);
      //  If this is a good star
      //  Add it to STAR1
      if ( STAR1 == NULL ) {
       fprintf( stderr, "ERROR: can't allocate memory for a new star!\n STAR1 = realloc(STAR1, sizeof(struct Star) * (NUMBER1+1) ); - failed!\n" );
       return EXIT_FAILURE;
      }
      // Pos1 = realloc(Pos1, sizeof(int) * (NUMBER1+1) ); // that was working for us all the time
      // Pos1 = realloc(Pos1, sizeof(int) * ( MAX(i,NUMBER1) +1) ); // does not work
      if ( Pos1 == NULL ) {
       fprintf( stderr, "ERROR: can't allocate memory for a new star!\n Pos1 = realloc(Pos1, sizeof(int) * (NUMBER1+1) ); - failed!\n" );
       return EXIT_FAILURE;
      }
      //
      // Here is the key thing: Pos1 is filled-up only until Number_of_ecv_star before we enter this for cycle!
      //
      Pos1[i]= NUMBER1; // this was so wrong!!! Or was it?
      // Pos1[i] = number_of_elements_in_Pos1; // we'll need it just for processing this image, Pos1 will be reset for the next image
      // number_of_elements_in_Pos1++;
      //
      max_number++; // star name (ok, number)
      STAR2[Pos2[i]].n= max_number;
      Star_Copy( STAR1 + Pos1[i], STAR2 + Pos2[i] );
      STAR1[Pos1[i]].mag= 0.0;
      //
      STAR1[Pos1[i]].n_detected= 1;
      if ( STAR2[Pos2[i]].sextractor_flag <= maxsextractorflag && STAR2[Pos2[i]].vast_flag == 0 ) {
       STAR1[Pos1[i]].n_rejected= 0;
      } else {
       STAR1[Pos1[i]].n_rejected= 1;
      }
      //
      NUMBER1++;

      // !!! Debug !!!
      // if(n==8)write_single_Star_from_struct_to_ds9_region_file(STAR2, Pos2[i], Pos2[i]+1, "STAR_UNID_ds9.reg", aperture);
      // float debug_x=586.696;
      // float debug_y=438.463;
      // float debug_d=sqrt((STAR2[Pos2[i]].x_frame-debug_x)*(STAR2[Pos2[i]].x_frame-debug_x)+(STAR2[Pos2[i]].y_frame-debug_y)*(STAR2[Pos2[i]].y_frame-debug_y));
      // if( debug_d<aperture ){
      // fprintf(stderr,"ADDING NEW STARS: %d  %.3f %.3f  (%f)  s=%d v=%6d\n",STAR2[Pos2[i]].n,STAR2[Pos2[i]].x_frame,STAR2[Pos2[i]].y_frame,STAR2[Pos2[i]].star_size,STAR2[Pos2[i]].sextractor_flag,STAR2[Pos2[i]].vast_flag);
      //}

      if ( NUMBER1 >= MAX_NUMBER_OF_STARS - 1 ) {
       // fprintf( stderr, "ERROR while adding new stars: Too many stars!\nChange string \"#define MAX_NUMBER_OF_STARS %d\" in src/vast_limits.h file and recompile the program by running \"make\".\n", MAX_NUMBER_OF_STARS );
       fprintf( stderr, "ERROR while adding new stars!" );
       report_and_handle_too_many_stars_error();
       return EXIT_FAILURE;
      }
      //} // // If this is a good star
      // else
      // fprintf(stderr,"Bad star!\n");
     }

    } // if ( param_failsafe == 0 && Number_of_ecv_star > 0 && wpolyfit_exit_code == 0 ) {

    fprintf( stderr, "    %5d objects stored in memory (%5d max.)\n", NUMBER1, MAX_NUMBER_OF_STARS );

    if ( wpolyfit_exit_code == 0 ) {
     fprintf( stderr, "Magnitude calibration is performed successfully!\n" );

     /* Write observation to light curve cache. */
     if ( debug != 0 )
      fprintf( stderr, "DEBUG MSG: write cache - " );

     if ( param_failsafe == 0 ) {
      cache_counter= NUMBER2;
     } else {
      cache_counter= Number_of_ecv_star;
     }
     if ( debug != 0 )
      fprintf( stderr, "NUMBER2= %d  Number_of_ecv_star= %d ", NUMBER2, Number_of_ecv_star );

     // coordinate_array_counter=0; // WTF?!?!?!

     fprintf( stderr, "Saving observations to the cache... " );

     for ( i= 0; i < cache_counter; i++ ) {
      //
      // Update the detection counter
      if ( i < Number_of_ecv_star ) {
       STAR1[Pos1[i]].n_detected++;
      }
      //

      // !!! ONE LAST CHECK IF THIS IS A GOOD STAR !!!
      if ( 1 == is_point_close_or_off_the_frame_edge( (double)STAR2[Pos2[i]].x_frame, (double)STAR2[Pos2[i]].y_frame, X_im_size, Y_im_size, FRAME_EDGE_INDENT_PIXELS ) ) {
       // This is supposed to be checked above!
       fprintf( stderr, "FRAME EDGE REJECTION ERROR 2!!! Please report to kirx@kirx.net the following informaiton:\n" );
       fprintf( stderr, "X_im_size-STAR2[Pos2[i]].x_frame<FRAME_EDGE_INDENT_PIXELS\n%f-%f<%f\n", X_im_size, STAR2[Pos2[i]].x_frame, FRAME_EDGE_INDENT_PIXELS );
       fprintf( stderr, "Y_im_size-STAR2[Pos2[i]].y_frame<FRAME_EDGE_INDENT_PIXELS\n%f-%f<%f\n", Y_im_size, STAR2[Pos2[i]].y_frame, FRAME_EDGE_INDENT_PIXELS );
       return EXIT_FAILURE;
      }
      if ( STAR2[Pos2[i]].sextractor_flag > maxsextractorflag ) {
       // That should work only for i<Number_of_ecv_star ,so we check that
       // We count such cases above, here we just reject 'em
       if ( i < Number_of_ecv_star ) {
        STAR1[Pos1[i]].n_rejected++;
       }
       continue;
      }
      if ( STAR2[Pos2[i]].vast_flag != 0 ) {
       // WTF?!?!?!?!?!?!?!?! -- hmm, I see no problem here
       // That should work only for i<Number_of_ecv_star ,so we check that
       if ( i < Number_of_ecv_star ) {
        STAR1[Pos1[i]].n_rejected++;
       }
       continue;
      }
      //
      //

      TOTAL_OBS++;
      obs_in_RAM++;

      // Do this only for the new stars
      if ( i >= Number_of_ecv_star ) {
       // Save coordinates to the array. (the arrays are used to compute mean position of a star across all images)
       star_numbers_for_coordinate_arrays[coordinate_array_counter]= STAR1[Pos1[i]].n;
       number_of_coordinate_measurements_for_star[coordinate_array_counter]= 1; // first measurement
       coordinate_array_x[coordinate_array_counter]= malloc( sizeof( float ) );
       if ( coordinate_array_x[coordinate_array_counter] == NULL ) {
        fprintf( stderr, "ERROR: can't allocate memory for coordinate_array_x[coordinate_array_counter]\n" );
        vast_report_memory_error();
        return EXIT_FAILURE;
       }
       coordinate_array_x[coordinate_array_counter][0]= STAR2[Pos2[i]].x;
       coordinate_array_y[coordinate_array_counter]= malloc( sizeof( float ) );
       if ( coordinate_array_y[coordinate_array_counter] == NULL ) {
        fprintf( stderr, "ERROR: can't allocate memory for coordinate_array_y[coordinate_array_counter]\n" );
        vast_report_memory_error();
        return EXIT_FAILURE;
       }
       coordinate_array_y[coordinate_array_counter][0]= STAR2[Pos2[i]].y;
       coordinate_array_counter++;
       // fprintf(stderr,"\n\n\n\ncoordinate_array_counter=%d\n\n",coordinate_array_counter);
      }
      //

      // Coordinates averaging
      for ( coordinate_array_index= 0; coordinate_array_index < coordinate_array_counter; coordinate_array_index++ ) {
       // sadly, no measurable speed-up
       // attempt to speed-up
       if ( n >= MAX_N_IMAGES_USED_TO_DETERMINE_STAR_COORDINATES ) {
        if ( number_of_coordinate_measurements_for_star[coordinate_array_index] >= MAX_N_IMAGES_USED_TO_DETERMINE_STAR_COORDINATES ) {
         continue;
        }
       }
       //
       // SLOW: 5.12%
       // if ( STAR1[Pos1[i]].n == star_numbers_for_coordinate_arrays[coordinate_array_index] ) {
       // Using the IF_UNLIKELY macro to handle branch prediction
       IF_UNLIKELY( STAR1[Pos1[i]].n == star_numbers_for_coordinate_arrays[coordinate_array_index] ) {
        // maybe we don't want to do it if number_of_coordinate_measurements_for_star[coordinate_array_index] > something ?
        if ( number_of_coordinate_measurements_for_star[coordinate_array_index] < MAX_N_IMAGES_USED_TO_DETERMINE_STAR_COORDINATES ) {
         number_of_coordinate_measurements_for_star[coordinate_array_index]++;
         coordinate_array_x[coordinate_array_index]= realloc( coordinate_array_x[coordinate_array_index], number_of_coordinate_measurements_for_star[coordinate_array_index] * sizeof( float ) );
         coordinate_array_y[coordinate_array_index]= realloc( coordinate_array_y[coordinate_array_index], number_of_coordinate_measurements_for_star[coordinate_array_index] * sizeof( float ) );
         coordinate_array_x[coordinate_array_index][number_of_coordinate_measurements_for_star[coordinate_array_index] - 1]= STAR2[Pos2[i]].x;
         coordinate_array_y[coordinate_array_index][number_of_coordinate_measurements_for_star[coordinate_array_index] - 1]= STAR2[Pos2[i]].y;
         // update coordinates ONLY if we already have many measurements
         if ( number_of_coordinate_measurements_for_star[coordinate_array_index] > MIN_N_IMAGES_USED_TO_DETERMINE_STAR_COORDINATES ) {
          //

          //
          gsl_sort_float( coordinate_array_x[coordinate_array_index], 1, number_of_coordinate_measurements_for_star[coordinate_array_index] );
          gsl_sort_float( coordinate_array_y[coordinate_array_index], 1, number_of_coordinate_measurements_for_star[coordinate_array_index] );
          STAR1[Pos1[i]].x= gsl_stats_float_median_from_sorted_data( coordinate_array_x[coordinate_array_index], 1, number_of_coordinate_measurements_for_star[coordinate_array_index] );
          STAR1[Pos1[i]].y= gsl_stats_float_median_from_sorted_data( coordinate_array_y[coordinate_array_index], 1, number_of_coordinate_measurements_for_star[coordinate_array_index] );
          //
          // STAR1[Pos1[i]].x= clipped_mean_of_unsorted_data_float( coordinate_array_x[coordinate_array_index], number_of_coordinate_measurements_for_star[coordinate_array_index] );
          // STAR1[Pos1[i]].y= clipped_mean_of_unsorted_data_float( coordinate_array_y[coordinate_array_index], number_of_coordinate_measurements_for_star[coordinate_array_index] );
          //
         } // update coordinates ONLY if we already have many measurements
        } // if( number_of_coordinate_measurements_for_star[coordinate_array_index]<MAX_N_IMAGES_USED_TO_DETERMINE_STAR_COORDINATES ){
          /////////////////
          // coordinate_array_index=coordinate_array_counter; // break the loop
          //  cannot use the usual break here if OpenMP is active
          //                                            #ifndef VAST_ENABLE_OPENMP
        break; // there should be only one match STAR1[Pos1[i]].n==star_numbers_for_coordinate_arrays[coordinate_array_index] , right?
               //                                           #endif
        /////////////////
       } // if( STAR1[Pos1[i]].n==star_numbers_for_coordinate_arrays[coordinate_array_index] ){
      } // for(coordinate_array_index=0;coordinate_array_index<NUMBER1;coordinate_array_index++){
      // Update coordinates in STAR3 (reference structure for image metching)
      if ( n > MIN_N_IMAGES_USED_TO_DETERMINE_STAR_COORDINATES ) { // this step make sence only if coordinates in STAR1 have (or could have) been updated, and that if checks it!
       for ( i_update_coordinates_STAR3= 0; i_update_coordinates_STAR3 < NUMBER3; i_update_coordinates_STAR3++ ) {
        // for ( i_update_coordinates_STAR3= NUMBER3; i_update_coordinates_STAR3--; ) {
        //  SLOW: 4.13%
        // if ( STAR1[Pos1[i]].n == STAR3[i_update_coordinates_STAR3].n ) {
        // Using the IF_UNLIKELY macro to handle branch prediction
        IF_UNLIKELY( STAR1[Pos1[i]].n == STAR3[i_update_coordinates_STAR3].n ) {
         // never update for a moving object
         if ( STAR1[Pos1[i]].moving_object != 1 && STAR3[i_update_coordinates_STAR3].moving_object != 1 ) {
          STAR3[i_update_coordinates_STAR3].x= STAR1[Pos1[i]].x;
          STAR3[i_update_coordinates_STAR3].y= STAR1[Pos1[i]].y;
         }
         break; // there should be only one match, correct?!
        } // if( STAR1[Pos1[i]].n==STAR3[i_update_coordinates_STAR3].n ){
       } // for( i_update_coordinates_STAR3=0; i_update_coordinates_STAR3<NUMBER3; i_update_coordinates_STAR3++ ){
      } // if( n>MIN_N_IMAGES_USED_TO_DETERMINE_STAR_COORDINATES ){
      // Done with avaraging the coordinates
      ////////////////////////////////////////////////////////////////////

      if ( obs_in_RAM > Max_obs_in_RAM ) {
       ptr_struct_Obs= realloc( ptr_struct_Obs, sizeof( struct Observation ) * obs_in_RAM );
       if ( ptr_struct_Obs == NULL ) {
        fprintf( stderr, "ERROR: can't allocate memory for a new observation!\n ptr_struct_Obs = realloc(ptr_struct_Obs, sizeof(struct Observation) * obs_in_RAM); - failed!\n" );
        return EXIT_FAILURE;
       }
      }

      //      if( STAR1[Pos1[i]].n == 375 )
      //       fprintf(stderr, "\n\n\n DEBUGVENUS STAR1[i].n - YES\n\n\n");

      ptr_struct_Obs[obs_in_RAM - 1].star_num= STAR1[Pos1[i]].n;
      ptr_struct_Obs[obs_in_RAM - 1].JD= STAR2[Pos2[i]].JD;
      ptr_struct_Obs[obs_in_RAM - 1].mag= (double)STAR2[Pos2[i]].mag;
      ptr_struct_Obs[obs_in_RAM - 1].mag_err= (double)STAR2[Pos2[i]].sigma_mag;
      ptr_struct_Obs[obs_in_RAM - 1].X= (double)STAR2[Pos2[i]].x_frame;
      ptr_struct_Obs[obs_in_RAM - 1].Y= (double)STAR2[Pos2[i]].y_frame;
      ptr_struct_Obs[obs_in_RAM - 1].APER= (float)aperture;
      if ( strlen( input_images[n] ) > FILENAME_LENGTH ) {
       fprintf( stderr, "ERROR: strlen(input_images[n])>FILENAME_LENGTH \nFILENAME_LENGTH=%d\nFilename: %s\nPlease, increase FILENAME_LENGTH in src/vast_limits.h and recompile the program using make!\n", FILENAME_LENGTH, input_images[n] );
       return EXIT_FAILURE;
      }

      // strncpy( ptr_struct_Obs[obs_in_RAM - 1].filename, input_images[n], FILENAME_LENGTH );
      // ptr_struct_Obs[obs_in_RAM - 1].filename[FILENAME_LENGTH - 1]= '\0'; // just in case
      // strncpy( ptr_struct_Obs[obs_in_RAM - 1].fits_header_keywords_to_be_recorded_in_lightcurve, str_with_fits_keywords_to_capture_from_input_images[n], FITS_KEYWORDS_IN_LC_LENGTH );
      // ptr_struct_Obs[obs_in_RAM - 1].fits_header_keywords_to_be_recorded_in_lightcurve[FITS_KEYWORDS_IN_LC_LENGTH - 1]= '\0'; // just in case
      //  Just store pointers to the existing strings
      ptr_struct_Obs[obs_in_RAM - 1].filename= input_images[n];
      ptr_struct_Obs[obs_in_RAM - 1].fits_header_keywords_to_be_recorded_in_lightcurve= str_with_fits_keywords_to_capture_from_input_images[n];

      ptr_struct_Obs[obs_in_RAM - 1].is_used= 0;

      //
      for ( float_parameters_counter= NUMBER_OF_FLOAT_PARAMETERS; float_parameters_counter--; ) {
       ptr_struct_Obs[obs_in_RAM - 1].float_parameters[float_parameters_counter]= STAR2[Pos2[i]].float_parameters[float_parameters_counter];
      }
      //
     } // for (i = 0; i < cache_counter; i++) {
     fprintf( stderr, "OK\n" );
    } // if ( wpolyfit_exit_code == 0 ) {

    if ( debug != 0 )
     fprintf( stderr, "DEBUG MSG: 00001 " );
    // at this point it is assumed that images were successfully matched
    if ( match_try != 0 )
     success_match_on_increase++;
    // test should we use new number of reference stars as default?
    if ( param_set_manually_Number_of_main_star == 0 ) {
     if ( success_match_on_increase > MIN_SUCCESS_MATCH_ON_RETRY ) {
      success_match_on_increase= 0;
      default_Number_of_ecv_triangle= struct_pixel_coordinate_transformation->Number_of_ecv_triangle;
      default_Number_of_main_star= struct_pixel_coordinate_transformation->Number_of_main_star;
      fprintf( stderr, "WARNING: changing the number of reference stars for image matching to %d\n", default_Number_of_main_star );
     }
    }
    if ( debug != 0 )
     fprintf( stderr, "OK\n" );

    if ( debug != 0 )
     fprintf( stderr, "DEBUG MSG: 00002 " );
    // Do this only for the second image in the transientdetection mode !!
    if ( n == 2 && Num == 4 ) {
     // We do not care about transient candidates in failsafe mode OR if all stars on the frame were matched
     if ( param_failsafe == 0 && Number_of_ecv_star < NUMBER2 ) {
      // Make sure the potential transients are not suspiciously fast
      if ( fabs( STAR3[0].JD - STAR2[Pos2[Number_of_ecv_star]].JD ) > TRANSIENT_MIN_TIMESCALE_DAYS ) {
       // Search for transients among new stars
       for ( i= Number_of_ecv_star; i < NUMBER2; i++ ) {
        // !!!! vast_flag is size-related and should not be considered for the transient search
        // if( STAR2[Pos2[i]].vast_flag!=0 )continue;
        // fprintf(stderr,"*** DEBUG %d\n",STAR2[Pos2[i]].n);
        // test_transient( search_area_boundaries, STAR2[Pos2[i]], STAR3[0].JD, X_im_size, Y_im_size );
        test_transient( search_area_boundaries, STAR2[Pos2[i]], STAR3[0].JD, X_im_size, Y_im_size, X1, Y1, X2, Y2, N_bad_regions, aperture );
       }
      }
     }
    }
    //
    if ( debug != 0 )
     fprintf( stderr, "OK\n" );

    /* Write observations to disk to save RAM */
    if ( 0 != check_and_print_memory_statistics() && Max_obs_in_RAM > 1000 ) {
     Max_obs_in_RAM= Max_obs_in_RAM / 2;
    }
    if ( obs_in_RAM > Max_obs_in_RAM ) {
     fprintf( stderr, "Total number of measurements %ld (%ld measurements stored in RAM)\n", TOTAL_OBS, obs_in_RAM );
     fprintf( stderr, "sorting the measurements cached in memory,\n" );
     qsort( ptr_struct_Obs, obs_in_RAM, sizeof( struct Observation ), compare_star_num );
     fprintf( stderr, "writing lightcurve (outNNNNN.dat) files...\n" );
/* Write observation to disk */
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
// #pragma omp parallel for private( k, tmpNAME, file_out, j, string_with_float_parameters_and_saved_FITS_keywords )
#pragma omp parallel for private( start_index, k, tmpNAME, file_out, j )
#endif
     // The new OpenMP-based lightcurve writer
     for ( k= 0; k < NUMBER1; k++ ) {
      // process one star
      snprintf( tmpNAME, OUTFILENAME_LENGTH, "out%05d.dat", STAR1[k].n ); // Generate lightcurve filename
      file_out= fopen( tmpNAME, "a" );                                    //====================file_out===========================
      if ( file_out == NULL ) {
       continue;
      }

      start_index= binary_search_first( ptr_struct_Obs, obs_in_RAM, STAR1[k].n );

      for ( j= start_index; j < obs_in_RAM && ptr_struct_Obs[j].star_num == STAR1[k].n; j++ ) {
       if ( ptr_struct_Obs[j].is_used == 1 || ptr_struct_Obs[j].star_num == 0 ) {
        continue;
       }
       write_obs_to_file( file_out, &ptr_struct_Obs[j] );
      }
      fclose( file_out );
      // end of process one star
     } // for(k=0; k<NUMBER1; k++){
#else
     // The old fork-based lightcurve writer for the systems that do not support OpenMP
     i_fork= 0; // counter for fork
     number_of_lightcurves_for_each_thread= (int)( NUMBER1 / n_fork ) + 1;
     for ( i= 0; i < NUMBER1; i+= number_of_lightcurves_for_each_thread ) {
      i_fork++;
      pid= fork();
      if ( pid == 0 || pid == -1 ) {
       // if child or parent cannot fork
       if ( pid == -1 )
        fprintf( stderr, "WARNING: cannot fork()! Continuing in the streamline mode...\n" );

       for ( k= i; k < MIN( i + number_of_lightcurves_for_each_thread, NUMBER1 ); k++ ) {
        // process one star
        snprintf( tmpNAME, OUTFILENAME_LENGTH, "out%05d.dat", STAR1[k].n ); // Generate lightcurve filename
        file_out= fopen( tmpNAME, "a" );                                    //====================file_out===========================
        if ( file_out == NULL ) {
         fprintf( stderr, "ERROR: can't open file %s\n", tmpNAME );
         return EXIT_FAILURE;
        }

        start_index= binary_search_first( ptr_struct_Obs, obs_in_RAM, STAR1[k].n );

        for ( j= start_index; j < obs_in_RAM && ptr_struct_Obs[j].star_num == STAR1[k].n; j++ ) {
         if ( ptr_struct_Obs[j].is_used == 1 || ptr_struct_Obs[j].star_num == 0 ) {
          continue;
         }
         write_obs_to_file( file_out, &ptr_struct_Obs[j] );
        }

        fclose( file_out );
        // end of process one star
       }
       if ( pid == 0 ) {
        ///// If this is a child /////
        // free-up memory
        if ( debug != 0 ) {
         fprintf( stderr, "DEBUG MSG: CHILD free();\n" );
        }
        free( child_pids );
        free( ptr_struct_Obs );
        free( STAR3 );
        free( STAR1 );
        free( Pos1 );
        free( Pos2 );
        if ( debug != 0 ) {
         fprintf( stderr, "DEBUG MSG: freeing coordinate arrays\n" );
        }
        for ( coordinate_array_index= coordinate_array_counter; coordinate_array_index--; ) {
         free( coordinate_array_x[coordinate_array_index] );
         free( coordinate_array_y[coordinate_array_index] );
        }
        if ( debug != 0 ) {
         fprintf( stderr, "DEBUG MSG: free(coordinate_array_x);\n" );
        }
        free( coordinate_array_x );
        if ( debug != 0 ) {
         fprintf( stderr, "DEBUG MSG: free(coordinate_array_y);\n" );
        }
        free( coordinate_array_y );
        if ( debug != 0 ) {
         fprintf( stderr, "DEBUG MSG: free(star_numbers_for_coordinate_arrays);\n" );
        }
        free( star_numbers_for_coordinate_arrays );
        if ( debug != 0 ) {
         fprintf( stderr, "DEBUG MSG: free(number_of_coordinate_measurements_for_star);\n" );
        }
        free( number_of_coordinate_measurements_for_star );
        if ( debug != 0 ) {
         fprintf( stderr, "DEBUG MSG: for(n = 0; n < Num; n++)free(input_images[n]);\n" );
        }
        for ( n= Num; n--; ) {
         free( input_images[n] );
        }
        if ( debug != 0 ) {
         fprintf( stderr, "DEBUG MSG: free(input_images);\n" );
        }
        free( input_images );
        //
        for ( n= Num; n--; ) {
         free( str_with_fits_keywords_to_capture_from_input_images[n] );
        }
        free( str_with_fits_keywords_to_capture_from_input_images );
        if ( debug != 0 ) {
         fprintf( stderr, "DEBUG MSG: Delete_PixCoordinateTransformation(struct_pixel_coordinate_transformation);\n" );
        }
        Delete_PixCoordinateTransformation( struct_pixel_coordinate_transformation );

        if ( debug != 0 ) {
         fprintf( stderr, "DEBUG MSG: CHILD free() -- still alive\n" );
        }
        exit( EXIT_SUCCESS ); // exit only if this is actually a child
        // end of child
       }
       // the other possibility is that this is a parent that could not fork - no exit in this case
      } else {
       // if parent
       child_pids[i_fork - 1]= pid;
       if ( i_fork == MIN( n_fork, NUMBER1 ) ) {
        for ( ; i_fork--; ) {
         pid= child_pids[i_fork];
         waitpid( pid, &pid_status, 0 );
        }
        // i_fork=-1 after the for
        i_fork= 0;
       }
      }
     } // for(i = 0; i < NUMBER1; i++) {
#endif
     obs_in_RAM= 0;
     // !!! Experimental stuff !!!
     // Max_obs_in_RAM may have changed, so we need to re-allocate the memory
     free( ptr_struct_Obs );
     malloc_size= sizeof( struct Observation ) * Max_obs_in_RAM;
     if ( malloc_size <= 0 ) {
      fprintf( stderr, "ERROR019 - trying to allocate zero or negative number of bytes!\n" );
      return EXIT_FAILURE;
     }
     ptr_struct_Obs= malloc( (size_t)malloc_size );
     if ( ptr_struct_Obs == NULL ) {
      fprintf( stderr, "ERROR: couldn't allocate ptr_struct_Obs\n" );
      return EXIT_FAILURE;
     }
    } // if( obs_in_RAM>Max_obs_in_RAM ){

    /* Reset variables */
    wpolyfit_exit_code= 0;
    if ( debug != 0 )
     fprintf( stderr, "DEBUG MSG: free(Pos2); - " );
    free( Pos2 );
    if ( debug != 0 )
     fprintf( stderr, "OK\n" );
    if ( debug != 0 )
     fprintf( stderr, "DEBUG MSG: free(STAR2); - " );
    free( STAR2 );
    if ( debug != 0 )
     fprintf( stderr, "OK\n" );
   } else {
    // If we take this branch, we forget to free() the arrays above??
    // STAR2 is not allocated here, so no leak
    // what about Pos2?
    fprintf( stderr, "ERROR! APERTURE %.1lf is outside the expected range of %.1lf to  %.1lf\n", aperture, BELIEVABLE_APERTURE_MIN_PIX, BELIEVABLE_APERTURE_MAX_PIX );
    // Write error to the logfile
    sprintf( log_output, "rotation=   0.000  *detected= %5d  *matched= %5d  status=ERROR  %s\n", 0, 0, input_images[n] );
    write_string_to_log_file( log_output, sextractor_catalog );
   }
  } else {
   fprintf( stderr, "Error reading file %s\n", input_images[n] );
   // Write error to the logfile
   // sprintf( log_output, "exp_start= %02d.%02d.%4d %02d:%02d:%02d  exp= %4d  JD= %13.5lf  ap= %4.1lf  rotation= %7.3lf  *detected= %5d  *matched= %5d  status=ERROR  %s\n", 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0, 0, input_images[n] );
   sprintf( log_output, "exp_start= %02d.%02d.%4d %02d:%02d:%02d.000  exp= %4d.000  JD= %16.8lf  ap= %4.1lf  rotation= %7.3lf  *detected= %5d  *matched= %5d  status=ERROR  %s\n", 0, 0, 0, 0, 0, 0, 0, 0.0, 0.0, 0.0, 0, 0, input_images[n] );
   write_string_to_log_file( log_output, sextractor_catalog );

   fitsfile_read_error= 0;
  }

  progress( n + 1, Num );
 }

 fprintf( stderr, "Done with measurements! =)\n\n" );
 fprintf( stderr, "Total number of measurements %ld (%ld measurements stored in RAM)\n", TOTAL_OBS, obs_in_RAM );
 fprintf( stderr, "Freeing up some memory...  " );

 // we'll do it all the time to avoid uninitialized-use compiler warning
 // if( moving_object == 1 ) {
 free( moving_object__user_array_x );
 free( moving_object__user_array_y );
 //}
 //

 free( X1 );
 // fprintf( stderr, "1 " );
 free( Y1 );
 // fprintf( stderr, "2 " );
 free( X2 );
 // fprintf( stderr, "3 " );
 free( Y2 );
 // fprintf( stderr, "4 " );

 free( bad_stars_X );
 // fprintf( stderr, "5 " );
 free( bad_stars_Y );
 // fprintf( stderr, "6 " );

 free( manually_selected_comparison_stars_X );
 // fprintf( stderr, "7 " );
 free( manually_selected_comparison_stars_Y );
 // fprintf( stderr, "8 " );
 free( manually_selected_comparison_stars_catalog_mag );
 // fprintf( stderr, "9 " );

 //// Moved up here
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: free(Pos1);\n" );
 }
 free( Pos1 );
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: freeing coordinate arrays\n" );
 }
 // fprintf( stderr, "10 " );
 for ( coordinate_array_index= coordinate_array_counter; coordinate_array_index--; ) {
  free( coordinate_array_x[coordinate_array_index] );
  free( coordinate_array_y[coordinate_array_index] );
 }
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: free(coordinate_array_x);\n" );
 }
 // fprintf( stderr, "11 " );
 free( coordinate_array_x );
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: free(coordinate_array_y);\n" );
 }
 // fprintf( stderr, "12 " );
 free( coordinate_array_y );
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: free(star_numbers_for_coordinate_arrays);\n" );
 }
 // fprintf( stderr, "13 " );
 free( star_numbers_for_coordinate_arrays );
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: free(number_of_coordinate_measurements_for_star);\n" );
 }
 // fprintf( stderr, "14 " );
 free( number_of_coordinate_measurements_for_star );
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: for(n = 0; n < Num; n++)free(input_images[n]);\n" );
 }
 // fprintf( stderr, "15 " );
 /*
 // moved down so Observations can point to these arrays
 for ( n= Num; n--; ) {
  free( input_images[n] );
 }
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: free(input_images);\n" );
 }
 fprintf( stderr, "16 " );
 free( input_images );
 fprintf( stderr, "17 " );
 for ( n= Num; n--; ) {
  free( str_with_fits_keywords_to_capture_from_input_images[n] );
 }
 fprintf( stderr, "18 " );
 free( str_with_fits_keywords_to_capture_from_input_images );
 */
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: Delete_PixCoordinateTransformation(struct_pixel_coordinate_transformation);\n" );
 }
 // fprintf( stderr, "19 " );
 Delete_PixCoordinateTransformation( struct_pixel_coordinate_transformation );
 // fprintf( stderr, "20\n" );
 ////

 //
 fprintf( stderr, "Sorting the measurements cached in memory...\n" );
 qsort( ptr_struct_Obs, obs_in_RAM, sizeof( struct Observation ), compare_star_num );

 fprintf( stderr, "Writing lightcurve (outNNNNN.dat) files...\n" );

/* Write observation to disk */
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
// #pragma omp parallel for private( k, tmpNAME, file_out, j, string_with_float_parameters_and_saved_FITS_keywords )
#pragma omp parallel for private( start_index, k, tmpNAME, file_out, j )
#endif
 // The new OpenMP-based lightcurve writer
 for ( k= 0; k < NUMBER1; k++ ) {
  // process one star
  snprintf( tmpNAME, OUTFILENAME_LENGTH, "out%05d.dat", STAR1[k].n ); // Generate lightcurve filename
  file_out= fopen( tmpNAME, "a" );                                    //====================file_out===========================
  if ( file_out == NULL ) {
   continue;
  }

  start_index= binary_search_first( ptr_struct_Obs, obs_in_RAM, STAR1[k].n );

  for ( j= start_index; j < obs_in_RAM && ptr_struct_Obs[j].star_num == STAR1[k].n; j++ ) {
   if ( ptr_struct_Obs[j].is_used == 1 || ptr_struct_Obs[j].star_num == 0 ) {
    continue;
   }
   write_obs_to_file( file_out, &ptr_struct_Obs[j] );
  }
  fclose( file_out );
  // end of process one star
 } // for(k=0; k<NUMBER1; k++){
#else
 // The old fork-based lightcurve writer for the systems that do not support OpenMP
 i_fork= 0; // counter for fork
 number_of_lightcurves_for_each_thread= (int)( NUMBER1 / n_fork ) + 1;
 for ( i= 0; i < NUMBER1; i+= number_of_lightcurves_for_each_thread ) {
  i_fork++;
  pid= fork();
  if ( pid == 0 || pid == -1 ) {
   // if child or parent cannot fork()
   if ( pid == -1 )
    fprintf( stderr, "WARNING: cannot fork()! Continuing in the streamline mode...\n" );

   for ( k= i; k < MIN( i + number_of_lightcurves_for_each_thread, NUMBER1 ); k++ ) {
    // process one star
    snprintf( tmpNAME, OUTFILENAME_LENGTH, "out%05d.dat", STAR1[k].n ); // Generate lightcurve filename
    file_out= fopen( tmpNAME, "a" );                                    //====================file_out===========================
    if ( file_out == NULL ) {
     fprintf( stderr, "ERROR: can't open file %s for appending!\n", tmpNAME );
     return EXIT_FAILURE;
    }

    start_index= binary_search_first( ptr_struct_Obs, obs_in_RAM, STAR1[k].n );

    for ( j= start_index; j < obs_in_RAM && ptr_struct_Obs[j].star_num == STAR1[k].n; j++ ) {
     if ( ptr_struct_Obs[j].is_used == 1 || ptr_struct_Obs[j].star_num == 0 ) {
      continue;
     }
     write_obs_to_file( file_out, &ptr_struct_Obs[j] );
    }
    fclose( file_out );
    // end of process one star
   }
   if ( pid == 0 ) {
    ///// If this is a child /////
    // free-up memory
    if ( debug != 0 ) {
     fprintf( stderr, "DEBUG MSG: CHILD free();\n" );
    }
    free( child_pids );
    free( ptr_struct_Obs );
    free( STAR3 );
    free( STAR1 );
    // free( coordinate_array_x );
    // free( coordinate_array_y );
    // free( star_numbers_for_coordinate_arrays );
    // free( number_of_coordinate_measurements_for_star );
    // free( Pos1 );
    // free( Pos2 ) ;
    if ( debug != 0 ) {
     fprintf( stderr, "DEBUG MSG: CHILD free() -- still alive\n" );
    }
    //
    exit( EXIT_SUCCESS ); // exit only if this is actually a child
    // end of child
   }
   // the other possibility is that this is a parent that could not fork - no exit in this case
  } else {
   // if parent
   child_pids[i_fork - 1]= pid;
   if ( i_fork == MIN( n_fork, NUMBER1 ) ) {
    for ( ; i_fork--; ) {
     pid= child_pids[i_fork];
     waitpid( pid, &pid_status, 0 );
    }
    // i_fork=-1 after the for
    i_fork= 0;
   }
  }
 } // for(i = 0; i < NUMBER1; i++) {
#endif

 free( child_pids );

 // Now we can free the arrays (no longer needed for Observations to point to)
 for ( n= Num; n--; ) {
  free( input_images[n] );
 }
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: free(input_images);\n" );
 }
 // fprintf( stderr, "16 " );
 free( input_images );
 // fprintf( stderr, "17 " );
 for ( n= Num; n--; ) {
  free( str_with_fits_keywords_to_capture_from_input_images[n] );
 }
 // fprintf( stderr, "18 " );
 free( str_with_fits_keywords_to_capture_from_input_images );

 // Dump STAR1 structure to a log file
 vast_list_of_all_stars_log= fopen( "vast_list_of_all_stars.log", "w" );
 if ( NULL == vast_list_of_all_stars_log ) {
  fprintf( stderr, "WARNING! cannot create vast_list_of_all_stars.log\n" );
 } else {
  for ( i= 0; i < NUMBER1; i++ ) {
   fprintf( vast_list_of_all_stars_log, "%05d %8.3lf %8.3lf\n", STAR1[i].n, STAR1[i].x, STAR1[i].y );
  }
  fclose( vast_list_of_all_stars_log );
 }
 // Same as above, but in DS9 format
 vast_list_of_all_stars_ds9= fopen( "vast_list_of_all_stars.ds9.reg", "w" );
 if ( NULL == vast_list_of_all_stars_ds9 ) {
  fprintf( stderr, "WARNING! cannot create vast_list_of_all_stars.log\n" );
 } else {
  fprintf( vast_list_of_all_stars_ds9, "# Region file format: DS9 version 4.0\n# Filename: vast_list_of_all_stars.ds9.reg\nglobal color=green font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source\nimage\n" );
  for ( i= 0; i < NUMBER1; i++ ) {
   // fprintf( vast_list_of_all_stars_ds9, "circle(%8.3lf,%8.3lf,%8.3lf)\n# text(%8.3lf,%8.3lf) text={%05d}\n", STAR1[i].x, STAR1[i].y, STAR1[i].star_size, STAR1[i].x, STAR1[i].y, STAR1[i].n );
   fprintf( vast_list_of_all_stars_ds9, "circle(%8.3lf,%8.3lf,%8.3lf)\n# text(%8.3lf,%8.3lf) text={%05d}\n", STAR1[i].x, STAR1[i].y, CONST * STAR1[i].star_size / 2.0, STAR1[i].x, STAR1[i].y + 1.8 * CONST * STAR1[i].star_size / 2.0, STAR1[i].n );
  }
  fclose( vast_list_of_all_stars_ds9 );
 }

 // system("cat out00856.dat > YOHOHO.txt");

 // Write detection statistics for all stars in STAR1 structure
 vast_source_detection_rejection_statistics_log= fopen( "vast_source_detection_rejection_statistics.log", "w" );
 if ( NULL == vast_source_detection_rejection_statistics_log ) {
  fprintf( stderr, "WARNING! cannot create vast_source_detection_rejection_statistics.log\n" );
 } else {
  for ( i= 0; i < NUMBER1; i++ ) {
   // fprintf(vast_source_detection_rejection_statistics_log,"%05d %5d %5d  %.3lf\n",STAR1[i].n,STAR1[i].n_detected,STAR1[i].n_rejected,(double)(STAR1[i].n_detected-STAR1[i].n_rejected)/(double)STAR1[i].n_detected );
   //  The following MUST be consistent with the lightcurve file naming scheme used above
   snprintf( tmpNAME, OUTFILENAME_LENGTH, "out%05d.dat", STAR1[i].n ); // Generate lightcurve filename
   //
   fraction_of_good_measurements_for_this_source= (double)( STAR1[i].n_detected - STAR1[i].n_rejected ) / (double)STAR1[i].n_detected;
   // Write the log output anyway
   fprintf( vast_source_detection_rejection_statistics_log, "%s  %5d %5d  %.3lf\n", tmpNAME, STAR1[i].n_detected, STAR1[i].n_rejected, fraction_of_good_measurements_for_this_source );
   // If this source doesn't pass the quality cuts - REMOVE the lightcurve file
   if ( STAR1[i].n_detected < HARD_MIN_NUMBER_OF_POINTS ) {
    unlink( tmpNAME );
    continue;
   }
   // do not remove lightcurves in in diffphot mode
   if ( diffphot_flag != 1 && moving_object != 1 ) {
    // do not rely on a single rejection - accidents happen
    if ( fraction_of_good_measurements_for_this_source < MIN_FRACTION_OF_GOOD_MEASUREMENTS && STAR1[i].n_rejected > MIN_NUMBER_OF_REJECTIONS_FOR_MIN_FRACTION_OF_GOOD_MEASUREMENTS ) {
     unlink( tmpNAME );
     continue;
    }
   }
   //
  }
  fclose( vast_source_detection_rejection_statistics_log );
 }

 fprintf( stderr, "The lightcurve files have been written, freeing up more memory...\n" );
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: free(ptr_struct_Obs);\n" );
 free( ptr_struct_Obs );

 /*
 // moved up
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: Delete_PixCoordinateTransformation(struct_pixel_coordinate_transformation);\n" );
 Delete_PixCoordinateTransformation( struct_pixel_coordinate_transformation );
*/

 // if ( debug != 0 )
 //  fprintf( stderr, "DEBUG MSG: free(Pos1);\n" );
 // free( Pos1 );

 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: free(STAR1);\n" );
 free( STAR1 );
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: free(STAR3);\n" );
 free( STAR3 );
 /*
        // moved up
        if (debug != 0) fprintf(stderr, "DEBUG MSG: free(file_or_dir_on_command_line);\n");
        free(file_or_dir_on_command_line);
 // moved up
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: for(n = 0; n < Num; n++)free(input_images[n]);\n" );
 }
 for ( n= Num; n--; ) {
  free( input_images[n] );
 }
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: free(input_images);\n" );
 }
 free( input_images );
 //
 for ( n= Num; n--; ) {
  free( str_with_fits_keywords_to_capture_from_input_images[n] );
 }
 free( str_with_fits_keywords_to_capture_from_input_images );

 // moved up
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: freeing coordinate arrays\n" );
 }
 for ( coordinate_array_index= coordinate_array_counter; coordinate_array_index--; ) {
  free( coordinate_array_x[coordinate_array_index] );
  free( coordinate_array_y[coordinate_array_index] );
 }
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: free(coordinate_array_x);\n" );
 }
 free( coordinate_array_x );
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: free(coordinate_array_y);\n" );
 }
 free( coordinate_array_y );
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: free(star_numbers_for_coordinate_arrays);\n" );
 }
 free( star_numbers_for_coordinate_arrays );
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: free(number_of_coordinate_measurements_for_star);\n" );
 }
 free( number_of_coordinate_measurements_for_star );
*/

 // Save details about magnitude calibration
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: vast.c is starting lib/save_magnitude_calibration_details.sh\n" );
 }

 if ( 0 != system( "lib/save_magnitude_calibration_details.sh" ) ) {
  fprintf( stderr, "ERROR running  lib/save_magnitude_calibration_details.sh\n" );
 }

 // Create vast_image_details.log
 if ( 0 != system( "lib/create_vast_image_details_log.sh" ) ) {
  fprintf( stderr, "ERROR running  lib/create_vast_image_details_log.sh\n" );
  return EXIT_FAILURE;
 }

 // Sort all lightcurve files in JD
 if ( 0 != system( "lib/sort_all_lightcurve_files_in_jd" ) ) {
  fprintf( stderr, "ERROR running  lib/sort_all_lightcurve_files_in_jd\n" );
  return EXIT_FAILURE;
 }

 // Generate summary log
 if ( debug != 0 ) {
  fprintf( stderr, "DEBUG MSG: vast.c is starting echo and lib/vast_image_details_log_parser.sh > vast_summary.log && echo OK\n" );
 }
 fprintf( stderr, "\nWriting summary file: vast_summary.log ...  " );
 // system("lib/vast_image_details_log_parser.sh > vast_summary.log && echo OK ");
 if ( 0 == system( "lib/vast_image_details_log_parser.sh > vast_summary.log" ) ) {
  fprintf( stderr, "OK\n" );
 }

 /* We don't need it if vast_source_detection_rejection_statistics.log stuff works
 // Remove single-epoch detections to exclude them from bad image search speed-up the following steps
 if ( 0 != system( "lib/remove_lightcurves_with_small_number_of_points" ) ) {
  fprintf( stderr, "ERROR running  lib/remove_lightcurves_with_small_number_of_points\n" );
 }
 */

 // Filter-out bad images
 if ( param_remove_bad_images == 1 ) {
  if ( 0 != system( "lib/remove_bad_images" ) ) {
   fprintf( stderr, "ERROR running  lib/remove_bad_images\n" );
  }
  if ( 0 != system( "lib/remove_lightcurves_with_small_number_of_points" ) ) {
   fprintf( stderr, "ERROR running  lib/remove_lightcurves_with_small_number_of_points\n" );
  }
 }

 // Apply sigma filter if we want...
 if ( param_nofilter != 1 && Num > 2 * HARD_MIN_NUMBER_OF_POINTS ) {
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: vast.c is starting lib/new_lightcurve_sigma_filter\n" );
  if ( 0 != system( "lib/new_lightcurve_sigma_filter" ) ) {
   fprintf( stderr, "ERROR running  lib/new_lightcurve_sigma_filter\n" );
  }
  if ( 0 != system( "lib/remove_lightcurves_with_small_number_of_points" ) ) {
   fprintf( stderr, "ERROR running  lib/remove_lightcurves_with_small_number_of_points\n" );
  }
 }

 // Choose string to describe time system
 if ( timesys == 3 ) {
  sprintf( tymesys_str, "TDB" );
  fprintf( stderr, "\n\n   ##### The JD time system is set to TDB, not UTC!!! #####\n " );
  fprintf( stderr, "Within the time accuracy of VaST it is the same as TT.\n " );
  print_TT_reminder( 2 ); // print the TT reminder once more, just to be sure the user have noticed it
  fprintf( stderr, "   #######################################################\n\n " );
 } else if ( timesys == 2 ) {
  sprintf( tymesys_str, "TT" );
  fprintf( stderr, "\n\n   ##### The JD time system is set to TT, not UTC!!! #####\n " );
  print_TT_reminder( 2 ); // print the TT reminder once more, just to be sure the user have noticed it
  fprintf( stderr, "   #######################################################\n\n " );
 } else {
  if ( timesys == 1 ) {
   sprintf( tymesys_str, "UTC" );
  } else {
   sprintf( tymesys_str, "UNKNOWN" );
  }
 }

 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: tymesys_str= _%s_\n", tymesys_str );

 /* Write more comments to log file */
 vast_image_details= fopen( "vast_summary.log", "a" );
 if ( vast_image_details == NULL ) {
  fprintf( stderr, "ERROR: cannot open vast_summary.log for writing!\n" );
  return EXIT_FAILURE;
 }
 fprintf( vast_image_details, "JD time system (TT/UTC/UNKNOWN): %s\n", tymesys_str );
 fclose( vast_image_details );

 if ( param_select_best_aperture_for_each_source == 1 ) {
  fprintf( stderr, "Selecting the best aperture for each source\n" );
  if ( 0 != system( "lib/select_aperture_with_smallest_scatter_for_each_object" ) ) {
   fprintf( stderr, "ERROR running  lib/select_aperture_with_smallest_scatter_for_each_object\n" );
   return EXIT_FAILURE;
  }
 }

 if ( number_of_sysrem_iterations > 0 || param_rescale_photometric_errors == 1 ) {
  // if( Num!=4 ){
  //  Compute lightcurve statistics!
  if ( 0 != system( "util/nopgplot.sh -q" ) ) {
   fprintf( stderr, "ERROR running  util/nopgplot.sh -q\n" );
  }
  //}
 }

 if ( param_rescale_photometric_errors == 1 ) {
  if ( 0 != system( "util/rescale_photometric_errors" ) ) {
   fprintf( stderr, "ERROR running  util/rescale_photometric_errors\n" );
  } // will use the list of constant stars
  // Some measurements may be rejected here due to large errors
  // (especially relevant for photographic data)
  // So we remove lightcurves which have too small number of points after rejecting high-error measurements
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: vast.c is starting lib/remove_lightcurves_with_small_number_of_points\n" );
  if ( 0 != system( "lib/remove_lightcurves_with_small_number_of_points" ) ) {
   fprintf( stderr, "ERROR running  lib/remove_lightcurves_with_small_number_of_points\n" );
  }
 }

 // SysRem needs an input list of non-variable sources
 for ( n= 0; n < number_of_sysrem_iterations; n++ ) {
  fprintf( stderr, "Starting SysRem iteration %d...\n", number_of_sysrem_iterations );
  if ( 0 != system( "util/sysrem2" ) ) {
   fprintf( stderr, "ERROR running  util/sysrem2\n" );
   return EXIT_FAILURE; // if we were asked to run SysRem but failed - abort
  }
 }

 /* Prepare list of possible transients */
 if ( param_failsafe == 0 ) {
  if ( 0 != system( "lib/create_list_of_candidate_transients.sh" ) ) {
   fprintf( stderr, "ERROR running  lib/create_list_of_candidate_transients.sh\n" );
  }
  /*
          system("lib/transient_list");
          //system("lib/remove_blends_from_transient_candidates");
          //if( Num==3 || Num==4 )
          if( Num<10 ){
           // add flares to the list of transients
           system("lib/find_flares >> candidates-flares.lst ");
           system("while read A B ;do echo $A `grep -c \"\" $A` `tail -n1 $A |awk '{printf \"%s %8.3f %8.3f  \",$7,$4,$5}'` `head -n1 $A |awk '{printf \"%s %8.3f %8.3f  \",$7,$4,$5}'` ;done < candidates-flares.lst >> candidates-transients.lst");
          }
          // Write the log file info only if this is a transient detection run
          if( Num==3 || Num==4 ){
           system("echo -n \"Transient candidates found: \" >> vast_summary.log ; if [ -f candidates-transients.lst ];then grep -c \" \" candidates-transients.lst >> vast_summary.log ;else echo 0 >> vast_summary.log ;fi"); // Write to summary log
          }
          */
 }

 /* Stop timer */
 end_time= time( NULL );
 elapsed_time= difftime( end_time, start_time );
 /* Write more comments to log file to log file */
 vast_image_details= fopen( "vast_summary.log", "a" );
 if ( vast_image_details == NULL ) {
  fprintf( stderr, "ERROR: cannot open vast_summary.log for writing!\n" );
  return EXIT_FAILURE;
 }
 //                            01234567890123
 fprintf( vast_image_details, "Estimated ref. image limiting mag.: %6.2lf\n", search_area_boundaries[5] );
 if ( param_filterout_magsize_outliers == 1 ) {
  fprintf( vast_image_details, "Magnitude-Size filter: Enabled\n" );
 } else {
  fprintf( vast_image_details, "Magnitude-Size filter: Disabled\n" );
 }
 if ( param_select_best_aperture_for_each_source == 1 ) {
  fprintf( vast_image_details, "For each source choose aperture with the smallest scatter: YES\n" );
 } else {
  fprintf( vast_image_details, "For each source choose aperture with the smallest scatter: NO\n" );
 }
 if ( param_rescale_photometric_errors == 1 ) {
  fprintf( vast_image_details, "Photometric errors rescaling: YES\n" );
 } else {
  fprintf( vast_image_details, "Photometric errors rescaling: NO\n" );
 }
 // fprintf(vast_image_details, "Number of identified bad images: %d\n", count_lines_in_ASCII_file("vast_list_of_bad_images.log"));
 //  The number is a combination of image stats and lightcurve stats identified bad images
 fprintf( vast_image_details, "Number of identified bad images: %d\n", count_lines_in_ASCII_file( "vast_list_of_bad_images.log" ) + vast_bad_image_flag_counter );
 fprintf( vast_image_details, "Number of SysRem iterations: %d\n", number_of_sysrem_iterations );
 // and mention the user-specified moving object
 if ( moving_object == 1 ) {
  fprintf( vast_image_details, "User-specified moving object: %s\n", str_moving_object_lightcurve_file );
 } else {
  fprintf( vast_image_details, "User-specified moving object: %s\n", "none" );
 }
 fprintf( vast_image_details, "Computation time: %.0lf seconds\n", elapsed_time );
 fprintf( vast_image_details, "Number of parallel threads: %d\n", n_fork );
 fprintf( vast_image_details, "SExtractor parameter file: default.sex\n" ); // actually, for now this is always default.sex
 fclose( vast_image_details );

 //// Highlight SExtractor settings ////
 if ( 0 != system( "echo 'Some important SExtractor parameters:' >> vast_summary.log ; export LANG=C ; grep '^[^#]' default.sex | grep -e 'SATUR_LEVEL' -e 'DETECT_MINAREA' -e 'DETECT_THRESH' -e 'ANALYSIS_THRESH' -e 'GAIN' -e 'WEIGHT_TYPE' >> vast_summary.log" ) ) {
  fprintf( stderr, "ERROR_SYSTEM_SE_PARAM\n" );
 }

 //// Write more stats ////
 if ( Num > 3 ) {
  if ( debug != 0 )
   fprintf( stderr, "DEBUG MSG: vast.c is starting util/observations_per_star >> vast_summary.log\n" );
  if ( 0 != system( "util/observations_per_star >> vast_summary.log" ) ) {
   fprintf( stderr, "ERROR running util/observations_per_star\n" );
  } // will use util/nopgplot.sh to compute stats if it was not run before
 }
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: vast.c is starting util/vast-mc.sh >> vast_summary.log\n" );
 if ( 0 != system( "util/vast-mc.sh >> vast_summary.log" ) ) {
  fprintf( stderr, "ERROR running  util/vast-mc.sh\n" );
 }

 //// Write information about maximum memory usage (if /proc/PID/status is readable) ////
 if ( debug != 0 )
  fprintf( stderr, "DEBUG MSG: vast.c is getting memory usage stats from /proc\n" );
 sprintf( stderr_output, "/proc/%d/status", getpid() );
 if ( 1 == is_file( stderr_output ) ) {
  sprintf( stderr_output, "echo -n \"Memory usage \" >> vast_summary.log ; head -n1 vast_memory_usage.log >> vast_summary.log" );
  if ( 0 != system( stderr_output ) ) {
   fprintf( stderr, "ERROR running  %s\n", stderr_output );
  }
 }

 /* Write version information to the log file */
 version( stderr_output );
 vast_image_details= fopen( "vast_summary.log", "a" );
 if ( vast_image_details == NULL ) {
  fprintf( stderr, "ERROR: cannot open vast_summary.log for writing!\n" );
  return EXIT_FAILURE;
 }
 //
 fprintf( vast_image_details, "Software: %s ", stderr_output );
 compiler_version( stderr_output );
 fprintf( vast_image_details, "compiled with %s", stderr_output );
 compilation_date( stderr_output );
 fprintf( vast_image_details, "VaST compiled on  %s", stderr_output );
 vast_build_number( stderr_output );
 fprintf( vast_image_details, "VaST build number  %s", stderr_output );
 // This actually reflects the output of lib/set_openmp.sh
 // If the output was ignored - the following would not reflect how the code was actually compiled
 vast_is_openmp_enabled( stderr_output );
 fprintf( vast_image_details, "OpenMP enabled: %s", stderr_output );
 //
 fclose( vast_image_details );
 if ( 0 != system( "sex -v >> vast_summary.log" ) ) {
  fprintf( stderr, "ERROR_SYSTEM001\n" );
 }
 if ( param_P == 1 ) {
  if ( 0 != system( "`lib/look_for_psfex.sh | awk '{print $4}'` -v 2>/dev/null >> vast_summary.log" ) ) {
   fprintf( stderr, "ERROR_SYSTEM002\n" );
  }
 }
 if ( 0 != system( "/usr/bin/env bash --version | head -n 1 >> vast_summary.log" ) ) {
  fprintf( stderr, "ERROR_SYSTEM003\n" );
 }
 if ( 0 != system( "echo -n \"Processing completed on  \" >> vast_summary.log ; export LANG=C ; date >> vast_summary.log ; echo -n \"Host name: \" >> vast_summary.log ; hostname >> vast_summary.log" ) ) {
  fprintf( stderr, "ERROR_SYSTEM004\n" );
 } // write date to the log file

 if ( Num <= SOFT_MIN_NUMBER_OF_POINTS && Num != 4 ) {
  // if( 0 != strcmp("diffphot", basename(argv[0])) ) {
  if ( diffphot_flag != 1 ) {
   // suppress the message if we are in the manual differential photometry mode
   fprintf( stderr, "\n\n\n----***** VaST processing message *****----\n\
You asked VaST to process only %d images. Under most circumstances this \n\
is a BAD IDEA that will lead to inconclusive results.\n\
Unless you are sure about what you are doing, please consider\n\
one of the 'normal' ways to run VaST:\n\n\
 * 'Transient detection mode' - run VaST on four (4) images: two reference and two second-epoch.\n\
Then create an HTML search report by running util/transients/search_for_transients_single_field.sh\n\n\
 * 'Variable star search mode' - run VaST on a long (50-100-1000) series of images and inspect\n\
lightcurves that show a large scatter.\n\n\
 * 'Individual star photometry mode' - run VaST with './diffphot' command an manually specify\n\
the comparison stars and the variable star you want to measure.\n\n\n\n",
            Num );
  }
 }

 if ( MATCH_SUCESS == 0 && Num == 2 ) {
  fprintf( stderr, "\n\n\nVaST processing ERROR: cannot match the two images!\n\n\n" );
  return EXIT_FAILURE;
 }

 // Perform manitude calibration if the calibration file is supplied and non-empty
 if ( count_lines_in_ASCII_file( "calib.txt" ) > 0 && N_manually_selected_comparison_stars > 0 ) {
  if ( 0 != system( "util/calibrate_magnitude_scale `lib/fit_zeropoint`" ) ) {
   fprintf( stderr, "ERROR running the magnitude calibration!" );
  }
 }

 // Print warning messages if many images were not matched
 if ( MATCH_SUCESS + 1 < (int)( 0.75 * (double)Num + 0.5 ) ) {
  fprintf( stderr, "\n\n\n----***** VaST processing WARNING *****----\nYou asked VaST to process %d images, but only %d were actually matched to the reference one.\nPlease investigate this!\n\n\n", Num, MATCH_SUCESS );
  report_lightcurve_statistics_computation_problem();
 }

 if ( Num != 4 ) {
  // Compute lightcurve statistics!
  if ( 0 != system( "util/nopgplot.sh" ) ) {
   fprintf( stderr, "ERROR running util/nopgplot.sh\n" );
  }
  // Warn the user if the reference image does not look good
  if ( 0 != system( "lib/evaluate_vast_image_details_log.sh" ) ) {
   fprintf( stderr, "ERROR running lib/evaluate_vast_image_details_log.sh\n" );
  }
 }

 /// Special mode for manual comparison star selection
 // if( 0 == strcmp("diffphot", basename(argv[0])) ) {
 if ( diffphot_flag == 1 ) {
  // Display lightcurves of user-marked variables
  sprintf( stderr_output, "if [ -s vast_list_of_previously_known_variables.log ];then while read A ;do ./lc $A & done < vast_list_of_previously_known_variables.log ;fi" );
  if ( !system( stderr_output ) ) {
   // fprintf(stderr, "ERROR running the command:\n %s\n", stderr_output);
   fprintf( stderr, "\n\n \x1B[34;47mClick on a star which lightcurve you want to display.\x1B[33;00m \n\n" );
   sprintf( stderr_output, "./select_star_on_reference_image" );
   if ( !system( stderr_output ) ) {
    fprintf( stderr, "ERROR running the command:\n %s\n", stderr_output );
   }
  }
 }

 //
 if ( moving_object == 1 && param_nofind != 1 ) {
  fprintf( stderr, "\n\n\nDisplaying the moving object lightcurve %s\n\n\n", str_moving_object_lightcurve_file );
  sprintf( stderr_output, "./lc %s", str_moving_object_lightcurve_file );
  if ( !system( stderr_output ) ) {
   fprintf( stderr, " \n" ); // ./lc will exit with an error
   // fprintf(stderr, "ERROR running the command:\n %s\n", stderr_output);
  }
 }

 /* Search for variability candidates */
 if ( param_nofind == 0 ) {
  strcpy( stderr_output, "./find_candidates a " ); // no need to recompute lightcurve stats!
  if ( period_search_switch == 1 ) {
   strcat( stderr_output, "--tsearch " );
  }
  if ( use_ds9_instead_of_pgfv == 1 ) {
   strcat( stderr_output, "--ds9 " );
  }
  fprintf( stderr, "%s\n", stderr_output );
  if ( !system( stderr_output ) ) {
   return EXIT_FAILURE;
  }
 }

 // unsetenv("MALLOC_CHECK_");

 // fprintf(stderr, "Num=%d MATCH_SUCESS=%d\n", Num, MATCH_SUCESS);

 // Decide on the overall outcome of the processing (was it OK or not)
 if ( MATCH_SUCESS + 1 < (int)( 0.75 * (double)Num + 0.5 ) ) {
  fprintf( stderr, "Low percentage of matched images - we'll declare this an unsuccessful VaST run (exit code 1)\n" );
  return EXIT_FAILURE;
 }

 fprintf( stderr, "We consider this a successful VaST run (exit code 0)\n" );
 return 0;
}
