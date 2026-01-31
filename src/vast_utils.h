#ifndef VAST_UTILS_H
#define VAST_UTILS_H

#include <stddef.h>     // for size_t
#include "vast_types.h" // for struct Star, struct Observation

/* These functions are completely self-contained */
void version(char *version_string);
void print_vast_version(void);
void compiler_version(char *compiler_version_string);
void compilation_date(char *compilation_date_string);
void vast_build_number(char *vast_build_number_string);
void vast_is_openmp_enabled(char *vast_openmp_enabled_string);
void progress(int done, int all);
int vast_remove_directory(const char *path);
int check_if_we_can_allocate_lots_of_memory(void);
int check_and_print_memory_statistics(void);
void print_TT_reminder( int show_timer_or_quit_instantly );

/* Simple helper functions */
int exclude_test(double X, double Y, double *exX, double *exY, int N, int verbose);
void exclude_from_3_double_arrays(double *array1, double *array2, double *array3, int i, int *N);
void exclude_from_6_double_arrays(double *array1, double *array2, double *array3, 
                                  double *array4, double *array5, double *array6, int i, int *N);

void make_sure_libbin_is_in_path();
int find_catalog_in_vast_images_catalogs_log( char *fitsfilename, char *catalogfilename );

/* Functions moved from vast.c */
void extract_mag_and_snr_from_structStar( const struct Star *stars, size_t n_stars, double *mag_array, double *snr_array );
int compare_star_num( const void *a, const void *b );
size_t binary_search_first( struct Observation *arr, size_t size, int target );
void write_images_catalogs_logfile( char **filelist, int n );
void write_magnitude_calibration_log( double *mag1, double *mag2, double *mag_err, int N, char *fitsimagename );
void write_magnitude_calibration_log2( double *mag1, double *mag2, double *mag_err, int N, char *fitsimagename );
void write_magnitude_calibration_log_plane( double *mag1, double *mag2, double *mag_err, int N, char *fitsimagename, double A, double B, double C );
void write_magnitude_calibration_param_log( double *poly_coeff, char *fitsimagename );
void save_command_line_to_log_file( int argc, char **argv );
int compare( const double *a, const double *b );

#endif
// VAST_UTILS_H
