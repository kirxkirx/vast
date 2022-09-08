// This file contains VaST setings that are not expected to change during runtime

// Please note that the correct name of this file is "vast_limits.h", "limits.h" is a symlink kept for compatibility.
// The problem with the old name is that it was the same as one of the standard C include files.

// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_LIMITS_INCLUDE_FILE

//////// Settings that control VaST start here ////////

#define N_FORK 0         // Number of SExtractor threads running in parallel \
                         // 0 - the number of threads is determined at runtime
#define DEFAULT_N_FORK 5 // number of threads to be used if it cannot be properly determined at runtime

/* Memory settings */
#define MAX_NUMBER_OF_STARS 300000
#define MAX_NUMBER_OF_OBSERVATIONS 120000 // per star

//////////////////////////////////////////////////////////
// The following paprameter is now set AUTOMATICALLY by the script lib/set_MAX_MEASUREMENTS_IN_RAM_in_vast_limits.sh that is started by make
#include "vast_max_measurements_in_ram.h"
//#define MAX_MEASUREMENTS_IN_RAM 96000  // set automatically at compile time based on PHYSMEM_BYTES=8229117952 by lib/set_MAX_MEASUREMENTS_IN_RAM_in_vast_limits.sh
//////////////////////////////////////////////////////////

// Max. number of measurements to be stored in memory
#define FILENAME_LENGTH 1024   // Max. image filename length
#define OUTFILENAME_LENGTH 128 // Max. lightcurve (out*.dat) filename length
#define VAST_PATH_MAX 4096     // Max path length to the vast executable

#define MAX_NUMBER_OF_FITS_KEYWORDS_TO_CAPTURE_IN_LC 10                              // Max number of keywords to capture with each lightcurve point
#define FITS_KEYWORDS_IN_LC_LENGTH 81 * MAX_NUMBER_OF_FITS_KEYWORDS_TO_CAPTURE_IN_LC // Max length of FITS keywords string to be recorded with each lightcurve point
// Warning! Max comment string length is hardcoded in src/lightcurve_io.h

//#define MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE 512+FILENAME_LENGTH // assuming each string in any lightcurve file is not longer than this
#define MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE 512 + FILENAME_LENGTH + FITS_KEYWORDS_IN_LC_LENGTH // assuming each string in any lightcurve file is not longer than this
#define MAX_STRING_LENGTH_IN_SEXTARCTOR_CAT 512                                                 // Maximum string length in image00001.cat
#define MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG 512                                 // Maximum string length in vast_lightcurve_statistics.log

#define MAX_RAM_USAGE 0.7 /* Try not to store in RAM more than MAX_RAM_USAGE*RAM_size */
#define MAX_NUMBER_OF_LEAP_SECONDS 100 /* Maximum number of lines in lib/tai-utc.dat file */

/* Star detection */
#define FRAME_EDGE_INDENT_PIXELS 10.0  // Don't take into account stars closer than FRAME_EDGE_INDENT_PIXELS pixels to a frame edge.
#define MIN_NUMBER_OF_STARS_ON_FRAME 2 // Frames with less than MIN_NUMBER_OF_STARS_ON_FRAME stars detected will not be used
#define AUTO_SIGMA_POPADANIYA_COEF 0.6 // Important for star matchning! Stars are matched if their coordinates on two images coincide within AUTO_SIGMA_POPADANIYA_COEF*aperture if -s -m or -w switch is not set.
#define HARD_MIN_NUMBER_OF_POINTS 2    // Potential transients with less than HARD_MIN_NUMBER_OF_POINTS will be discarded! \
                                       // Parameter used in  src/remove_lightcurves_with_small_number_of_points.c
#define SOFT_MIN_NUMBER_OF_POINTS 40   // Recommend a user to use at least SOFT_MIN_NUMBER_OF_POINTS images in the series
#define MIN_FRACTION_OF_GOOD_MEASUREMENTS 0.9 // at least MIN_FRACTION_OF_GOOD_MEASUREMENTS of detections of this particular source \
                                              // should pass the quality cuts, otherwise it will be rejected                        \
                                              // MIN_FRACTION_OF_GOOD_MEASUREMENTS should always be between 0.0 and 1.0
#define MIN_NUMBER_OF_REJECTIONS_FOR_MIN_FRACTION_OF_GOOD_MEASUREMENTS 2 // apply the above only if at least that number of rejections happened

///////////////////// !!! /////////////////////
// If defined create_data WILL NOT COMPUTE VARIABILITY INDEXES for the lightcurves having
// less than MIN(SOFT_MIN_NUMBER_OF_POINTS,(int)(MIN_FRACTION_OF_IMAGES_THE_STAR_SHOULD_APPEAR_IN*number_of_measured_images_from_vast_summary_log))
// points! You may miss some transient objects that appear only temporary if this option is enabled,
// but dropping lightcurves with small number of points dramatically reduces the number of false candidate variables.
#define DROP_LIGHTCURVES_WITH_SMALL_NUMBER_OF_POINTS_FROM_ALL_PLOTS
#define MIN_FRACTION_OF_IMAGES_THE_STAR_SHOULD_APPEAR_IN 0.5
// Please note that these parameters apply at the lightcurve analysis stage.
// More strict ruled may be applied at the lightcurve creation stage above (MIN_FRACTION_OF_GOOD_MEASUREMENTS)
///////////////////////////////////////////////
#define STRICT_CHECK_OF_JD_AND_MAG_RANGE
// check that JD and magnitudes of all points in the lightcurves are within the expected range
// comment-out the above line to disable the strict check
// The two parameters above are needed for experimenting with unusual data (like non-optical)
// Under the normal circumstancese these parameters should be enabled.
///////////////////// !!! /////////////////////

//#define FAINTEST_STARS 50.0      // Instrumental (with respect to the background) magnitude of faintest stars.
//#define FAINTEST_STARS_PHOTO -1.0 // Same as FAINTEST_STARS but for photographic plate reduction mode.
// Parameter used in src/data_parser.c
#define BRIGHTEST_STARS -30.0         /* Instrumental (with respect to the background) magnitude of brightest stars. \
                                         Parameter used in src/data_parser.c */
#define FAINTEST_STARS_ANYMAG 30.0    // Discard observations with (instrumental or whatever) magnitudes > FAINTEST_STARS
#define MIN_SNR 3.0                   // Discard objects detected with signal-to-noise ratio < MIN_SNR
#define MAX_MAG_ERROR 1.086 / MIN_SNR // Discard observations with the estimated error >MAX_MAG_ERROR. Note: the meaning of this parameter has changed in vast-1.0rc80 \
                                      // see http://wise2.ipac.caltech.edu/docs/release/allsky/expsup/sec6_3a.html                                                     \
                                      // and http://www.eso.org/~ohainaut/ccd/sn.html

#define DEFAULT_PHOTOMETRY_ERROR_MAG 0.02 // Assume this error when no error estimate is given

//#define MIN_MAG_ERR_FROM_SEXTRACTOR 0.005 // Assume that SExtractor-derived photometric errors < MIN_MAG_ERR_FROM_SEXTRACTOR are not realistic.
//                                          // (Used for instrumental magnitude calibration.)

// ATTENTION!
// If the stars are really small use FWHM_MIN=0.0
// to loose the restrictions on the star image shape!
// The value of FWHM_MIN for small stars are now used by default.
// If star images on your CCD frames have normal size (span many pixels), 
// it is recommended to use FWHM_MIN 0.85 (or some similar value).
//
//
#define FWHM_MIN 0.1 // safe default value -- only stars with FWHM > FWHM_MIN (pix) will be processed
//                                            // 0.5 is too high - fails the photographic plate test
#define MIN_SOURCE_SIZE_APERTURE_FRACTION 0.25 // reject sources for which the comusted aperture size would be less than
                                               // MIN_SOURCE_SIZE_APERTURE_FRACTION*image_aperture_size
                                               // (this should reject very small objects = cosmic rays)

#define SATURATION_LIMIT_INDENT 0.1 // guessed_saturation_limit=maxval-SATURATION_LIMIT_INDENT*maxval;

// #define FRACTION_OF_ZERO_PIXEL_TO_USE_FLAG_IMG 0.01
#define FRACTION_OF_ZERO_PIXEL_TO_USE_FLAG_IMG 0.002 // if the image has more than FRACTION_OF_ZERO_PIXEL_TO_USE_FLAG_IMG*total_number_of_pixels \
                                                     // pixels with zero values - use the flag image to flag-out these bad regions               \
                                                     // and avoid numerous supurious detections arond their edges
#define N_POINTS_PSF_FIT_QUALITY_FILTER 7

/////////////// LOG FILES THAT MAY OR MAY NOT BE NEEDED ///////////////
#define REMOVE_FLAG_IMAGES_TO_SAVE_SPACE
#define REMOVE_SEX_LOG_FILES
#define DISABLE_INDIVIDUAL_IMAGE_LOG
#define DISABLE_MAGSIZE_FILTER_LOGS
///////////////////////////////////////////////////////////////////////

#define MAX_IMAGE_SIDE_PIX_FOR_SANITY_CHECK 1000000

// Only image pixels with values between MIN_PIX_VALUE and MAX_PIX_VALUE are considered good ones
#define MIN_PIX_VALUE -100000
#define MAX_PIX_VALUE 100000

#define FLAG_N_PIXELS_AROUND_BAD_ONE 4 // that many pixels will be flagged around each bad pixel (if flag image is to be used)

#define MAX_SEXTRACTOR_FLAG 1 // Maximum star flag value set by sextractor acceptable for VaST        \
                              // You may override this at runtime with '-x N' parameter, for example: \
                              // ./vast -x3 ../sample_data/*fit                                       \
                              // Will accept all stars having flag less or equal to 3

// A reminder:
// 1     The object has neighbors, bright and close enough to
//       significantly bias the photometry, or bad pixels
//       (more than 10% of the integrated area affected).
//
// 2     The object was originally blended with another one.
//
// 4     At least one pixel of the object is saturated
//       (or very close to).
//
// And trust me, you don't want to consider objects with flags more than 4.
//

#define NUMBER_OF_FLOAT_PARAMETERS 13 // Number of aditional filtering parameters to keep for each star

#define WRITE_ADDITIONAL_APERTURES_TO_LIGHTCURVES // if enable mag(ref)-mag(aper) differences will be written to the lightcurve files \
                                                  // Set aperture sizes: larger and smaller than the reference aperture               \
                                                  // ap[0]=APERTURE+AP01*APERTURE;                                                    \
                                                  // ap[1]=APERTURE+AP02*APERTURE;                                                    \
                                                  // ap[2]=APERTURE+AP03*APERTURE;                                                    \
                                                  // ap[3]=APERTURE+AP04*APERTURE;

#define AP01 -0.1
#define AP02 0.1
#define AP03 0.2
#define AP04 0.3

// If the measured aperture is not between BELIEVABLE_APERTURE_MIN_PIX and BELIEVABLE_APERTURE_MAX_PIX -
// assume the measurement is bad
#define BELIEVABLE_APERTURE_MAX_PIX 95.0
#define BELIEVABLE_APERTURE_MIN_PIX  1.0

// Star matching
#define MAX_FRACTION_OF_AMBIGUOUS_MATCHES 0.05           //  Maximum fraction of stars that match one star on the reference image
#define MIN_NUMBER_OF_AMBIGUOUS_MATCHES_TO_TAKE_ACTION 5 // discard the above if there are less than the specified number of stars affected by the problem

#define MAX_MATCH_TRIALS 5                              /* discard image if it was still not matched after MAX_MATCH_TRIALS attempts */
#define MIN_FRACTION_OF_MATCHED_STARS 0.41              /* discard image if <MIN_FRACTION_OF_MATCHED_STARS*number_stars_on_reference_image were matched */
                                                        /* (should always be <0.5 !!!) discard image if <MIN_FRACTION_OF_MATCHED_STARS*number_stars_on_reference_image were matched */
#define MIN_FRACTION_OF_MATCHED_STARS_STOP_ATTEMPTS 0.1 /* Do not attempt to match images if less than MIN_FRACTION_OF_MATCHED_STARS_STOP_ATTEMPTS were matched after a few iterations */
                                                        /* because something is evidently wrong with that image. */
#define MATCH_MIN_NUMBER_OF_REFERENCE_STARS 100
#define MATCH_MIN_NUMBER_OF_TRIANGLES 20 * MATCH_MIN_NUMBER_OF_REFERENCE_STARS
#define MATCH_REFERENCE_STARS_NUMBER_STEP 500                                                 // Search for an optimal number of reference stars between MATCH_MIN_NUMBER_OF_REFERENCE_STARS and \
                                                                                              // MATCH_MAX_NUMBER_OF_REFERENCE_STARS with step MATCH_REFERENCE_STARS_NUMBER_STEP
#define MATCH_MAX_NUMBER_OF_REFERENCE_STARS 3000                                              // Give up trying to match frame if it was not matched with MATCH_MAX_NUMBER_OF_REFERENCE_STARS stars
#define TRIANGLES_PER_STAR 11                                                                 // 11 triangles paer star in the current algorithm, see Separate_to_triangles() in src/ident_lib.c
#define MATCH_MAX_NUMBER_OF_TRIANGLES TRIANGLES_PER_STAR *MATCH_MAX_NUMBER_OF_REFERENCE_STARS //
#define MATCH_MAX_NUMBER_OF_STARS_FOR_SMALL_TRIANGLES 700                                     // The starfield is divided in triangles using two statagies:                                                \
                                                                                              // one produces largi triangles from stars of close brightness while                                         \
                                                                                              // the second produces small triangles from closely separated stars.                                         \
                                                                                              // The search for closest neighbour becomes very computationally expansive as the number of stars increases. \
                                                                                              // So, separation for small triangles will not be performed if the number of reference stars is > MATCH_MAX_NUMBER_OF_STARS_FOR_SMALL_TRIANGLES
#define MIN_SUCCESS_MATCH_ON_RETRY 5                                                          // if more than MIN_SUCCESS_MATCH_ON_RETRY images were successfully matched after increasing the number of reference stars \
                                                                                              // - change the number of reference stars
#define MIN_N_IMAGES_USED_TO_DETERMINE_STAR_COORDINATES 15                                    // Use median position of a star after MIN_N_IMAGES_USED_TO_DETERMINE_STAR_COORDINATES \
                                                                                              // measurements of its position were collected (star's position on the reference frame is used before).
#define MAX_N_IMAGES_USED_TO_DETERMINE_STAR_COORDINATES 200                                   // Only the first MAX_N_IMAGES_USED_TO_DETERMINE_STAR_COORDINATES                                 \
                                                                                              // will be used to determine average star positions in the reference image coordinate system      \
                                                                                              // (needed for star matching). This is done to save memory, because otherwise all the coordinates \
                                                                                              // needs to be kept in memory all the time...
#define POSITION_ACCURACY_AS_A_FRACTION_OF_APERTURE 0.1                                       // Assume the position of a star may be measured with accuracy of POSITION_ACCURACY_AS_A_FRACTION_OF_APERTURE
#define MAX_SCALE_FACTOR 0.05                                                                 // Assume that images have the same scale to the accuracy of MAX_SCALE_FACTOR - important for star matching.
#define ONE_PLUS_MAX_SCALE_FACTOR_SIX (1.0 + MAX_SCALE_FACTOR) * (1.0 + MAX_SCALE_FACTOR) * (1.0 + MAX_SCALE_FACTOR) * (1.0 + MAX_SCALE_FACTOR) * (1.0 + MAX_SCALE_FACTOR) * (1.0 + MAX_SCALE_FACTOR)

// Magnitude calibration
#define MAX_MAG_FOR_med_CALIBRATION -3.0 // Do not use too faint stars for magnitude calibration.
#define CONST 6                          // measurement APERTURE=median_A*CONST where median_A - typical major axis of star images on the current frame (pix.)
//#define CONST 10
#define MAX_DIFF_POLY_MAG_CALIBRATION 0.3                                         // Stars that deviate more than MAX_DIFF_POLY_MAG_CALIBRATION from the fit will \
                                                                                  // be discarded from the magnitude calibration procedure.
#define MIN_NUMBER_STARS_POLY_MAG_CALIBR 40                                       // Magnitude calibration with parabola will not be performed \
                                                                                  // if there are less than MIN_NUMBER_STARS_POLY_MAG_CALIBR stars.
#define MAX_INSTR_MAG_DIFF 99.0                                                   // Do not use stars with instrumental mag difference >MAX_INSTR_MAG_DIFF for magnitude calibration \
                                                                                  // (turn out to be not really useful parameter)
#define MIN_NUMBER_OF_STARS_FOR_CCD_POSITION_DEPENDENT_MAGNITUDE_CORRECTION 10000 // If the reference image has >MIN_NUMBER_OF_STARS_FOR_CCD_POSITION_DEPENDENT_MAGNITUDE_CORRECTION \
                                                                                  // on it, a linear CCD-position-dependent magnitude correctin will be computed.                    \
                                                                                  // You can be override this with command line options -J or -j
//#define MAX_LIN_CORR_MAG 0.5                // Maximum CCD-position-dependent magnitude correctin/
#define MAX_LIN_CORR_MAG 1.0 // If the estimated correction is larger at frame's corners, the magnitude calibration will be failed

#define MAX_STRING_LENGTH_AUTOCANDIDATESDETAILS 512

///////////////////////////////////////////////////////////
// You may enable/disable individual variability indices 
// by editing src/variability_indexes.h
///////////////////////////////////////////////////////////

/// *** Automated selection of candidate variables *** ///
// Stars are listed as candidate variables if they have variability index values greater than the threshold values specified below
#define CANDIDATE_VAR_SELECTION_WITH_IQR
#define IQR_THRESHOLD 5.0

#define CANDIDATE_VAR_SELECTION_WITH_IQR_AND_MAD
//#define IQR_AND_MAD__IQR_THRESHOLD 3.6
#define IQR_AND_MAD__IQR_THRESHOLD 3.4
#define IQR_AND_MAD__MAD_THRESHOLD 4.1

#define CANDIDATE_VAR_SELECTION_WITH_ETA_AND_IQR_AND_MAD
#define ETA_AND_IQR_AND_MAD__ETA_THRESHOLD 5.0
#define ETA_AND_IQR_AND_MAD__IQR_THRESHOLD 3.0
#define ETA_AND_IQR_AND_MAD__MAD_THRESHOLD 3.0

#define CANDIDATE_VAR_SELECTION_WITH_ETA_AND_CLIPPED_SIGMA
#define ETA_AND_CLIPPED_SIGMA__ETA_THRESHOLD 7.0
#define ETA_AND_CLIPPED_SIGMA__CLIPPED_SIGMA_THRESHOLD 3.5

#define CANDIDATE_VAR_SELECTION_WITH_CLIPPED_SIGMA
#define CLIPPED_SIGMA_THRESHOLD 30.0

#define REQUIRED_MIN_CHI2RED_FOR_ALL_CANDIDATE_VAR 1.5 // reject candidates with reduced chi2 value less than REQUIRED_MIN_CHI2RED_FOR_ALL_CANDIDATE_VAR

#define DROP_FRACTION_OF_BRIGHTEST_VARIABLE_STARS 0.005 // exclude the brightest 0.5% of stars from the list
#define DROP_MAX_NUMBER_OF_BRIGHTEST_VARIABLE_STARS 5   // do not drop more than the specified number of bright stars
#define DROP_FRACTION_OF_FAINTEST_VARIABLE_STARS 0.25   // exclude the faintest 30% of stars from the list

/// *** Automated selection of candidate CONSTANT stars *** ///
// Stars are assumed to be constant if they have variability index values less than the threshold values specified below
#define CONSTANT_STARS__MAD_THRESHOLD 3.0
#define CONSTANT_STARS__IQR_THRESHOLD 3.0
#define CONSTANT_STARS__ETA_THRESHOLD 3.0
#define CONSTANT_STARS__WEIGHTED_SIGMA_THRESHOLD 3.0
#define CONSTANT_STARS__CLIPPED_SIGMA_THRESHOLD 3.0
#define CONSTANT_STARS__RoMS_THRESHOLD 3.0
// Not cutting on reducied chi2 as the photometric errors in the input lightcurve may be *heavily* underestimated
#define DROP_FRACTION_OF_BRIGHTEST_CONST_STARS 0.01 // exclude the brightest 1% of stars from the list
#define DROP_MAX_NUMBER_OF_BRIGHTEST_CONST_STARS 10
#define DROP_FRACTION_OF_FAINTEST_CONST_STARS 0.1   // exclude the faintest 10% of stars from the list
//////////////////////////////////////////////////////////

// Transient search
#define TRANSIENT_MIN_TIMESCALE_DAYS 1.0                  // expect transients apearing on timescale > TRANSIENT_MIN_TIMESCALE_DAYS
#define MAG_TRANSIENT_ABOVE_THE_REFERENCE_FRAME_LIMIT 1.3 //0.8 //1.3 // Transient candidates should be at least MAG_TRANSIENT_ABOVE_THE_REFERENCE_FRAME_LIMIT mag \
                                                          // above the detection limit on the reference frame.
#define FLARE_MAG 0.9                                     // Objects which are found to be FLARE_MAG magnitudes brighter on the current image than on the reference image \
                                                          // will be also listed as transient candidates
#define MIN_DISTANCE_BETWEEN_STARS_IN_APERTURE_DIAMS 0.8  //0.7

/* src/fit_mag_calib.c */
#define MAX_NUMBER_OF_STARS_MAG_CALIBR MAX_NUMBER_OF_STARS

/* src/m_sigma_bin.c */
#define M_SIGMA_BIN_SIZE_M 0.35
#define M_SIGMA_BIN_DROP 1
#define M_SIGMA_BIN_MAG_OTSTUP 0.1
#define M_SIGMA_BIN_MAG_SIGMA_DETECT 0.7 /* Increase this parameter \
                                            if you want more conservative candidate selection */

// src/variability_indexes.c
#define WS_BINNING_DAYS 1.0                      // Max time difference in days between data points that can form a pair for Stetson's indexes. \
                                                 // Stetson's indexes  are sensitive to variability on timescales >> WS_BINNING_DAYS
#define MAX_PAIR_DIFF_SIGMA_FOR_JKL_MAG_CLIP 5.0 // Do not form pairs from points that differ by more than DEFAULT_MAX_PAIR_DIFF_SIGMA*error mags

#define N3_SIGMA 3.0 // deviation of N3_SIGMA of three consequetive lightcurve points from the mean is considered significant

// Parameters for detecting Excursions
#define EXCURSIONS_GAP_BETWEEN_SCANS_DAYS 5.0 // Form scans from points that are not more than EXCURSIONS_GAP_BETWEEN_SCANS_DAYS apart to detect excursions \
                                              // 'Excursions' are the significant changes of brightness from scan to scan.

/* src/find_candidates.c */
#define DEFAULT_FRAME_SIZE_X 30000
#define DEFAULT_FRAME_SIZE_Y 30000

/* periodFilter/periodS2.c */
#define ANOVA_MIN_PERIOD 0.05 // days
#define ANOVA_MAX_PERIOD 30.0 // days

/* BLS/bls.c */
#define BLS_SIGMA 0.05 // assume all points have the same sigma
#define BLS_CUT 7.3    // consider as real \
                       // periods with snr>BLS_CUT
#define BLS_MIN_FREQ 0.2
#define BLS_MAX_FREQ 3.0
#define BLS_FREQ_STEP 0.00002
#define BLS_DI_MAX 24 // max. eclipse duration
#define BLS_DI_MIN 8  // min. eclipse duration

/* src/vast_math.c (stat) */
//#define STAT_NDROP 0 // for the simulation!!!!
// This now affects only the legacy sigma plot (2nd column in data.m_sigma and vast_lightcurve_statistics.log )
#define STAT_NDROP 5 // Drop STAT_NDROP brightest and STAT_NDROP faintest \
                     // points before calculating sigma
// Apply lightcurve filtering before computing variability indexes only to the lightcurve
// having at least STAT_MIN_NUMBER_OF_POINTS_FOR_NDROP points
#define STAT_MIN_NUMBER_OF_POINTS_FOR_NDROP SOFT_MIN_NUMBER_OF_POINTS

// src/pgfv/pgfv.c
#define PGFV_CUTS_PERCENT 99.5 //99.75 //95.0 //99.5  // this determines how bright is the displayed image

// src/match_eater.c SOME CRAZY OLD OBSOLETE STUFF
//#define MIN_MATCH_DISTANCE_PIX 600
//#define MAX_MATCH_DISTANCE_PIX 10*MIN_MATCH_DISTANCE_PIX

// src/fix_photo_log.c and many others
#define MAX_LOG_STR_LENGTH 1024 + FILENAME_LENGTH

// src/sysrem.c and src/sysrem2.c
#define NUMBER_OF_Ai_Ci_ITERATIONS 1000
#define Ai_Ci_DIFFERENCE_TO_STOP_ITERATIONS 0.00001
#define SYSREM_MAX_CORRECTION_MAG 0.5
#define SYSREM_MIN_NUMBER_OF_STARS 100
#define SYSREM_N_STARS_IN_PROCESSING_BLOCK 6000
#define SYSREM_MAX_NUMBER_OF_PROCESSING_BLOCKS 99

// src/new_lightcurve_sigma_filter.c
#define LIGHT_CURVE_FILTER_SIGMA 7.0

// src/remove_points_with_large_errors.c
//#define LIGHT_CURVE_ERROR_FILTER_SIGMA 5.0

// src/remove_bad_images.c
#define REMOVE_BAD_IMAGES__OUTLIER_THRESHOLD 3.0                 // Considers outliers measurements that are REMOVE_BAD_IMAGES__OUTLIER_THRESHOLD sigma \
                                                                 // above or below the median brightness.
#define REMOVE_BAD_IMAGES__DEFAULT_MAX_FRACTION_OF_OUTLIERS 0.11 // Drop images that have a large fraction of outlier measurements
#define REMOVE_BAD_IMAGES__MAX_ALLOWED_NUMBER_OF_OUTLIERS 20     // Drop bad images only if there are at least the specified number of outlier objects \
                                                                 // (regardless of what fraction of the total number of objects these outliers constitute)

/* src/hjd.c */
#define EXPECTED_MIN_JD 2400000.0
#define EXPECTED_MAX_JD 2500000.0
// EXPECTED_MIN_JD and EXPECTED_MAX_JD are useful for checking if an input number actually looks like a correct JD
// same for EXPECTED_MIN_MJD and EXPECTED_MAX_MJD
//#define EXPECTED_MIN_MJD 15020.0 // CE  1900 January  1 00:00:00.0 UT
#define EXPECTED_MIN_MJD 0.0      // no, can't use #define EXPECTED_MIN_MJD 15020.0 since in practice users love to truncate JD in really unpredictable ways
#define EXPECTED_MAX_MJD 124593.0 // CE  2200 January  1 00:00:00.0 UT

#define SHORTEST_EXPOSURE_SEC 0.0    // the shortest exposure time in seconds considered as valid by VaST
#define LONGEST_EXPOSURE_SEC 86400.0 // the longest exposure time in seconds considered as valid by VaST

#define MIN_NUMBER_OF_STARS_FOR_UCAC5_MATCH 20      // Warn the user that match with external catalog probably dind't go well
#define MAX_NUMBER_OF_ITERATIONS_FOR_UCAC5_MATCH 10 // perform that many iterations of local correction+catalog matching

//////// Settings that control VaST end here ////////

/* Auxiliary definitions */
#define MAX(a, b) (((a) > (b)) ? (a) : (b))
#define MIN(a, b) (((a) < (b)) ? (a) : (b))

// 2*sqrt(2*log(2)) see https://en.wikipedia.org/wiki/Full_width_at_half_maximum
#define SIGMA_TO_FWHM_CONVERSION_FACTOR 2.35482004503095

//////////////////////////////////////////////////
// Enable debug file output and many debug messages on the terminal.
// Should not be set for production!
//#define DEBUGFILES
//#define DEBUGMESSAGES

#include "stdio.h" // defines FILE, fopen(), fclose()

// is_file() - a small function which checks is an input string is a name of a readable file
static inline int is_file(char *filename) {
 FILE *f= NULL;
 f= fopen(filename, "r");
 if( f == NULL )
  return 0;
 else {
  fclose(f);
  return 1;
 }
}

// The macro below will tell the pre-processor that limits.h is already included
#define VAST_LIMITS_INCLUDE_FILE

#endif
// VAST_LIMITS_INCLUDE_FILE
