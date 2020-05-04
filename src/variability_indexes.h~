// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_STETSON_VARIABILITY_INDEXES_INCLUDE_FILE

// This tells the compiler if we should not compute some variability indexes to speed-up computations
#define SKIP_EXPERIMENTAL_VARIABILITY_INDEXES

// If we want to skip some variability indexes, here is the exact list of indexes to skip
// These are the ones that are not displayed by './find_candidates' minus CHI2
#ifdef SKIP_EXPERIMENTAL_VARIABILITY_INDEXES
// The commented-out indexes will not be disabled by enabling SKIP_EXPERIMENTAL_VARIABILITY_INDEXES
#define DISABLE_INDEX_WELCH_STETSON
#define DISABLE_INDEX_WELCH_STETSON_SIGN_ONLY
#define DISABLE_INDEX_STETSON_JKL
// #define DISABLE_INDEX_STETSON_JKL_TIME_WEIGHTING
#define DISABLE_INDEX_STETSON_JKL_MAG_CLIP_PAIRS
// #define DISABLE_INDEX_MAD
// #define DISABLE_INDEX_IQR
#define DISABLE_INDEX_LAG1_AUTOCORRELATION
#define DISABLE_INDEX_SKEWNESS
#define DISABLE_INDEX_KURTOSIS
// #define DISABLE_INDEX_ROMS
#define DISABLE_INDEX_N3
#define DISABLE_INDEX_EXCURSIONS
// #define DISABLE_INDEX_VONNEUMANN_RATIO
#define DISABLE_INDEX_EXCESS_ABBE_E_A
// #define DISABLE_INDEX_SB
#define DISABLE_INDEX_NXS
// #define DISABLE_INDEX_REDUCED_CHI2
#define DISABLE_INDEX_PEAK_TO_PEAK_AGN_V
// #define DISABLE_INDEX_WEIGHTED_SIGMA // also disables DISABLE_INDEX_SKEWNESS and DISABLE_INDEX_KURTOSIS see src/create_data.c
#define DISABLE_INDEX_A
#endif

// The following is for internal use only, do not change the default value!
#define DEFAULT_MAX_PAIR_DIFF_SIGMA 999.0 // Do not form pairs from points that differ by more than DEFAULT_MAX_PAIR_DIFF_SIGMA*error mags

void compute_variability_indexes_that_need_time_sorting( double *input_JD, double *input_m, double *input_merr, int input_Nobs, int input_Nmax, double *output_index_I, double *output_index_J, double *output_index_K, double *output_index_L, double *output_index_J_clip, double *output_index_L_clip, double *output_index_J_time, double *output_index_L_time, double *output_index_I_sign_only, double *N3, double *excursions, double *eta, double *E_A, double *SB );

void stetson_JKL_from_sorted_lightcurve( size_t *input_array_index_p, double *input_JD, double *input_m, double *input_merr, int input_Nobs, int input_Nmax, double input_max_pair_diff_sigma, int input_use_time_based_weighting, double *output_J, double *output_K, double *output_L );

double classic_welch_stetson_I_from_sorted_lightcurve( size_t *input_array_index_p, double *input_JD, double *input_m, double *input_merr, int input_Nobs );

double sign_only_welch_stetson_I_from_sorted_lightcurve( size_t *input_array_index_p, double *input_JD, double *input_m, double *input_merr, int input_Nobs );

double compute_IQR_of_unsorted_data( double *unsorted_data, int n );

/*
float clipped_mean_of_unsorted_data_float( float *unsorted_data, long n ); 
double clipped_mean_of_unsorted_data( double *unsorted_data, long n );
*/

double esimate_sigma_from_MAD_of_unsorted_data( double *unsorted_data, long n );

double esimate_sigma_from_MAD_of_sorted_data( double *sorted_data, long n );

float esimate_sigma_from_MAD_of_sorted_data_float( float *sorted_data, long n );

double esimate_sigma_from_MAD_of_sorted_data_and_destroy_input_array( double *sorted_data, long n );

double N3_consecutive_samesign_deviations_in_sorted_lightcurve( size_t *input_array_index_p, double *input_m, int input_Nobs );

double lag1_autocorrelation_of_unsorted_lightcurve( double *JD, double *m, int N );

double detect_excursions_in_sorted_lightcurve( size_t *p, double *JD, double *m, double *merr, int N_points_in_lightcurve );

double vonNeumann_ratio_eta_from_sorted_lightcurve( size_t *p, double *m, int N_points_in_lightcurve );

double excess_Abbe_value_from_sorted_lightcurve( size_t *p, double *JD, double *m, int N_points_in_lightcurve );

double SB_variability_detection_statistic_of_sorted_lightcurve( size_t *p, double *m, double *merr, int N );

double Normalized_excess_variance( double *m, double *merr, int N );

double compute_RoMS( double *m, double *merr, int N );

double compute_reduced_chi2( double *m, double *merr, int N );

double compute_chi2( double *m, double *merr, int N );

double compute_peak_to_peak_AGN_v( double *m, double *merr, int N );

double c4( int n );

double unbiased_estimation_of_standard_deviation_assuming_Gaussian_dist( double *sample, int n );

double compute_median_of_usorted_array_without_changing_it( double *data, int n );

// Comparison function for qsort, which is actually slower in practice than gsl_sort (heapsort)
// https://stackoverflow.com/questions/20584499/why-qsort-from-stdlib-doesnt-work-with-double-values-c
static inline int compare_double( const void * a, const void * b) {
  if (*(double*)a > *(double*)b)
    return 1;
 if (*(double*)a < *(double*)b)
    return -1;
 else
    return 0; 
}


// The macro below will tell the pre-processor that this header file is already included
#define VAST_STETSON_VARIABILITY_INDEXES_INCLUDE_FILE

#endif
// VAST_STETSON_VARIABILITY_INDEXES_INCLUDE_FILE
