#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <gsl/gsl_statistics_double.h>
#include <gsl/gsl_statistics_float.h>
#include <gsl/gsl_fit.h>
#include <gsl/gsl_sort_double.h>
#include <gsl/gsl_sort_float.h>
#include <libgen.h> // for basename()
#include <getopt.h>
#include <sys/types.h> // also wait3()
#include <sys/stat.h>
#include <unistd.h> /// sleep() and something else...

#include <time.h>

// all these are for wait3()
#include <sys/wait.h>
#include <sys/time.h>
#include <sys/resource.h>

#include "cpgplot.h"

#include "setenv_local_pgplot.h"
#include "vast_limits.h"
#include "variability_indexes.h"
#include "lightcurve_io.h"

#include "get_path_to_vast.h"

#include "wpolyfit.h" // for robustlinefit()

#include "fitsfile_read_check.h" // for fitsfile_read_check()

void print_help() {
 fprintf( stderr, "\n" );
 fprintf( stderr, "  --*** HOW TO USE THE LIGHTCURVE PLOTTER ***--\n" );
 fprintf( stderr, "\n" );
 fprintf( stderr, "  'H' - display this help message\n" );
 fprintf( stderr, "  right mouse click - exit\n" );
 fprintf( stderr, "  left mouse click - display image corresponding to the data point closest to the cursor (only works if the lightcurve is in VaST format)\n" );
 fprintf( stderr, "  'Z' + draw a rectangle to zoom in\n" );
 fprintf( stderr, "  'D' or 'Z'+'Z' - default zoom\n" );
 fprintf( stderr, "  'E' - display error bars (on/off)\n" );
 fprintf( stderr, "  'S' - save lightcurve to .ps file\n" );
 fprintf( stderr, "  'N' - save lightcurve to .png file (if compiled with libpng support)\n" );
 fprintf( stderr, "  'T' - terminate a single point\n" );
 fprintf( stderr, "  'C' + draw a rectangle - remove many point\n" );
 fprintf( stderr, "  '1' - display linear trend fit to the lightcurve (on/off)\n" );
 fprintf( stderr, "  '0' - fix linear trend inclination to 0 (on/off). Useful for correcting jumps in a lightcurve.\n" );
 fprintf( stderr, "  'B' - set a break point for a trend\n" );
 fprintf( stderr, "  '-' - subtract trend from the lightcurve\n" );
 fprintf( stderr, "  'W' - write edited lightcurve to a data file (will be in the same format as input file)\n" );
 fprintf( stderr, "  'K' - time of minimum determination using KvW method. You'll need to specify the eclipse duration with two clicks.\n" );
 fprintf( stderr, "  \033[0;36m'U'\033[00m - Try to \033[0;36midentify the star\033[00m with USNO-B1.0 and search GCVS, Simbad, VSX\n" );
 fprintf( stderr, "  'F' - fast identification that outputs just the variable star name with no further details.\n" );
 fprintf( stderr, "  \033[0;36m'L'\033[00m - Start web-based \033[0;36mperiod search tool\033[00m\n" );
 fprintf( stderr, "  'Q' - Start online lighcurve classifier (http://scan.sai.msu.ru/wwwupsilon/)\n" );
 fprintf( stderr, "\n" );
 return;
}

void replace_last_dot_with_null(char *original_filename) {
    int i;

    if (original_filename == NULL) {
        return;
    }

    int len = strlen(original_filename);
    // Traverse from the end of the string
    for (i = len - 1; i >= 0; i--) {
        if (original_filename[i] == '.') {
            original_filename[i] = '\0';  // Replace the last '.' with '\0'
            break;  // Exit after the first (last from end) dot is replaced
        }
    }
}

int convert_ztf_snad_format(char *lightcurvefilename, char *path_to_vast_string) {
    FILE *lightcurvefile, *convertedfile;
    char line[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
    char original_filename[FILENAME_LENGTH];
    char converted_filename[FILENAME_LENGTH];
    char converted_directory[VAST_PATH_MAX];
    double mjd, mag, mag_err;
    char filter[10];
    int zg_count = 0, zr_count = 0, zi_count = 0;

    lightcurvefile = fopen(lightcurvefilename, "r");
    if (NULL == lightcurvefile) {
        fprintf(stderr, "ERROR: cannot open file %s\n", lightcurvefilename);
        return 1;
    }

    // Check if the file starts with the ZTF SNAD format header
    if (fgets(line, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lightcurvefile) != NULL) {
        if (strncmp(line, "oid,filter,mjd,mag,magerr,clrcoeff", 34) != 0) {
            fclose(lightcurvefile);
            return 0; // Not a ZTF SNAD format file, do nothing
        }
    } else {
        fclose(lightcurvefile);
        return 1; // Error reading the file
    }
    
    // Create the converted_lightcurves directory if it doesn't exist
    snprintf(converted_directory, VAST_PATH_MAX, "%sconverted_lightcurves", path_to_vast_string);
    mkdir(converted_directory, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);
 
    strncpy(original_filename, basename(lightcurvefilename), FILENAME_LENGTH);
    replace_last_dot_with_null(original_filename);  

    // Generate the converted filename
    snprintf(converted_filename, FILENAME_LENGTH, "%s/%s_converted.dat", converted_directory, original_filename);

    fprintf(stderr, "ZTF SNAD data format detected! Converting %s to %s \n", basename(lightcurvefilename), converted_filename);

    convertedfile = fopen(converted_filename, "w");
    if (NULL == convertedfile) {
        fprintf(stderr, "ERROR: cannot create converted file %s\n", converted_filename);
        fclose(lightcurvefile);
        return 1;
    }

    // Process the lightcurve data
    while (fgets(line, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lightcurvefile) != NULL) {
        if (sscanf(line, "%*[^,],%[^,],%lf,%lf,%lf", filter, &mjd, &mag, &mag_err) == 4) {
            if (strcmp(filter, "zg") == 0) {
                zg_count++;
            } else if (strcmp(filter, "zr") == 0) {
                zr_count++;
            } else if (strcmp(filter, "zi") == 0) {
                zi_count++;
            }
        }
    }

    // Determine the filter with the most measurements
    char selected_filter[10];
    if (zg_count >= zr_count && zg_count >= zi_count) {
        strcpy(selected_filter, "zg");
    } else if (zr_count >= zg_count && zr_count >= zi_count) {
        strcpy(selected_filter, "zr");
    } else {
        strcpy(selected_filter, "zi");
    }
    fprintf(stderr, "Displaying %s filter data!\n", selected_filter);

    // Reset file pointer to the beginning of the file
    fseek(lightcurvefile, 0, SEEK_SET);
    
    // Skip the header line
    fgets(line, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lightcurvefile);

    // Write selected filter data to the converted file
    while (fgets(line, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lightcurvefile) != NULL) {
        if (sscanf(line, "%*[^,],%[^,],%lf,%lf,%lf", filter, &mjd, &mag, &mag_err) == 4) {
            if (strcmp(filter, selected_filter) == 0) {
                fprintf(convertedfile, "%.6lf %.5f %.5f\n", mjd + 2400000.5, mag, mag_err);
            }
        }
    }

    fclose(lightcurvefile);
    fclose(convertedfile);

    strcpy(lightcurvefilename, converted_filename);
    return 0;
}

int convert_aavso_format(char *lightcurvefilename, char *path_to_vast_string) {
    FILE *lightcurvefile, *convertedfile;
    char line[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
    char original_filename[FILENAME_LENGTH];
    char converted_filename[FILENAME_LENGTH];
    char converted_directory[VAST_PATH_MAX];
    double jd, mag, mag_err;

    lightcurvefile = fopen(lightcurvefilename, "r");
    if (NULL == lightcurvefile) {
        fprintf(stderr, "ERROR: cannot open file %s\n", lightcurvefilename);
        return 1;
    }

    // Check if the file starts with #TYPE=EXTENDED
    if (fgets(line, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lightcurvefile) != NULL) {
        if (strncmp(line, "#TYPE=EXTENDED", 14) != 0) {
            fclose(lightcurvefile);
            return 0; // Not an AAVSO format file, do nothing
        }
    } else {
        fclose(lightcurvefile);
        return 1; // Error reading the file
    }
    

    // Create the converted_lightcurves directory if it doesn't exist
    snprintf(converted_directory, VAST_PATH_MAX, "%sconverted_lightcurves", path_to_vast_string);
    mkdir(converted_directory, S_IRWXU | S_IRWXG | S_IROTH | S_IXOTH);
 
    strncpy(original_filename, basename(lightcurvefilename), FILENAME_LENGTH);
    replace_last_dot_with_null(original_filename);  

    // Generate the converted filename
    //snprintf(converted_filename, FILENAME_LENGTH, "%s/%s_converted.dat", converted_directory, basename(lightcurvefilename));
    snprintf(converted_filename, FILENAME_LENGTH, "%s/%s_converted.dat", converted_directory, original_filename);

    fprintf(stderr, "AAVSO data format detected! Converting %s to %s \n", basename(lightcurvefilename), converted_filename );

    convertedfile = fopen(converted_filename, "w");
    if (NULL == convertedfile) {
        fprintf(stderr, "ERROR: cannot create converted file %s\n", converted_filename);
        fclose(lightcurvefile);
        return 1;
    }

    // Skip the header lines until the data starts
    while (fgets(line, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lightcurvefile) != NULL) {
        if (strncmp(line, "#", 1) != 0) {
            break;
        }
    }

    // Process the lightcurve data
    do {
        if (sscanf(line, "%*[^,],%lf,%lf,%lf", &jd, &mag, &mag_err) == 3) {
            fprintf(convertedfile, "%.6lf %.5f %.5f\n", jd, mag, mag_err);
        }
    } while (fgets(line, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lightcurvefile) != NULL);

    fclose(lightcurvefile);
    fclose(convertedfile);

    strcpy(lightcurvefilename, converted_filename);
    return 0;
}

void minumum_kwee_van_woerden( float *fit_jd, float *fit_mag, int fit_n, double double_JD2float_JD ) {
 FILE *tmp_lc_file;
 int i;

 if ( fit_n == 0 ) {
  return;
 }

 tmp_lc_file= fopen( "lightcurve_for_kwee_van_woerden.tmp", "w" );
 if ( tmp_lc_file == NULL ) {
  fprintf( stderr, "ERROR: cannot open the temporary lightcurve file for writing! Aborting minimum determination routine...\n" );
  return;
 }
 for ( i= 0; i < fit_n; i++ ) {
  fprintf( tmp_lc_file, "%lf %f\n", (double)fit_jd[i] + double_JD2float_JD, fit_mag[i] );
 }
 fclose( tmp_lc_file );
 if ( 0 != system( "lib/kwee-van-woerden < lightcurve_for_kwee_van_woerden.tmp" ) ) {
  fprintf( stderr, "ERROR running  lib/kwee-van-woerden < lightcurve_for_kwee_van_woerden.tmp\n" );
 }
 if ( 0 != system( "rm -f lightcurve_for_kwee_van_woerden.tmp" ) ) {
  fprintf( stderr, "ERROR running  rm -f lightcurve_for_kwee_van_woerden.tmp\n" );
 }
 return;
}

void remove_linear_trend( float *fit_jd, float *mag, int N, double A, double B, double mean_jd, double mean_mag, float jd_min, float jd_max, double mag_zeropoint_for_log, double *JD_double_array_for_log ) {

 FILE *vast_lc_remove_linear_trend_logfile;

 int i;
 float *plot_jd;
 float *plot_y;
 float E1, E2;

 float E3, E4;
 float *corrected_mag;

 if ( N == 0 ) {
  return;
 }

 if ( N <= 0 ) {
  fprintf( stderr, "ERROR: Trying allocate zero or negative number of bytes(lc.c)\n" );
  exit( EXIT_FAILURE );
 }
 plot_jd= malloc( N * sizeof( float ) );
 if ( plot_jd == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for plot_jd(lc.c)\n" );
  exit( EXIT_FAILURE );
 }
 plot_y= malloc( N * sizeof( float ) );
 if ( plot_y == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for plot_y(lc.c)\n" );
  exit( EXIT_FAILURE );
 }
 corrected_mag= malloc( N * sizeof( float ) );
 if ( corrected_mag == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for plot_y(lc.c)\n" );
  exit( EXIT_FAILURE );
 }

 vast_lc_remove_linear_trend_logfile= fopen( "vast_lc_remove_linear_trend.log", "a" );
 if ( vast_lc_remove_linear_trend_logfile == NULL ) {
  fprintf( stderr, "ERROR: Cannot open file vast_lc_remove_linear_trend.log\n" );
  exit( EXIT_FAILURE );
 }

 for ( i= 0; i < N; i++ ) {
  if ( fit_jd[i] >= jd_min && fit_jd[i] <= jd_max ) {
   plot_jd[i]= fit_jd[i] - (float)( mean_jd );
   plot_y[i]= (float)(A)*plot_jd[i] + (float)( B );
   plot_jd[i]= plot_jd[i] + (float)mean_jd;
   if ( mag[i] > 100.0 ) {
    corrected_mag[i]= mag[i] - plot_y[i];                 // assume it's not magnitude but something linear
    corrected_mag[i]= corrected_mag[i] - (float)mean_mag; // assume it's not magnitude but something linear
   } else {
    // subtract magnitudes
    E1= powf( 10.0f, -0.4f * plot_y[i] );
    E2= powf( 10.0f, -0.4f * mag[i] );
    // corrected_mag[i]= 2.5f * log10f(E1 / E2);
    E3= powf( 10.0f, -0.4f * (float)mean_mag );
    E4= powf( 10.0f, -0.4f * ( 2.5f * log10f( E1 / E2 ) ) );
    corrected_mag[i]= 2.5f * log10f( E3 / E4 );
   }
   //
   E1= powf( 10.0f, -0.4f * plot_y[i] );
   E3= powf( 10.0f, -0.4f * (float)mean_mag );
   //
   fprintf( vast_lc_remove_linear_trend_logfile, "%.5lf  %9.5f  %9.5f  %9.5f \n", JD_double_array_for_log[i], corrected_mag[i], plot_y[i] + (float)mean_mag + (float)mag_zeropoint_for_log, mag[i] );
   mag[i]= corrected_mag[i];
  } // if( fit_jd[i]>jd_min && fit_jd[i]<jd_max )
 }

 fclose( vast_lc_remove_linear_trend_logfile );
 fprintf( stderr, "The detrending log is added to \x1B[34;47m vast_lc_remove_linear_trend.log \x1B[33;00m\n\n" );

 free( corrected_mag );
 free( plot_y );
 free( plot_jd );

 return;
}

void plot_linear_trend( float *fit_jd, int N, double A, double B, double mean_jd, double mean_mag ) {
 int i;
 float *plot_jd;
 float *plot_y;

 if ( N == 0 ) {
  return;
 }

 if ( N <= 0 ) {
  fprintf( stderr, "ERROR2: Trying allocate zero or negative number of bytes(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 plot_jd= malloc( N * sizeof( float ) );
 if ( plot_jd == NULL ) {
  fprintf( stderr, "ERROR2: Couldn't allocate memory for plot_y(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 plot_y= malloc( N * sizeof( float ) );
 if ( plot_y == NULL ) {
  fprintf( stderr, "ERROR2: Couldn't allocate memory for plot_y(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 for ( i= 0; i < N; i++ ) {
  plot_jd[i]= fit_jd[i] - (float)( mean_jd );
  plot_y[i]= (float)(A)*plot_jd[i] + (float)( B );
  plot_jd[i]= plot_jd[i] + (float)mean_jd;
  plot_y[i]= plot_y[i] + (float)mean_mag;
 }
 cpgsci( 3 );
 cpgline( N, plot_jd, plot_y );
 free( plot_y );
 free( plot_jd );
 return;
}

void fit_linear_trend( float *input_JD, float *input_mag, float *mag_err, int N, double *A, double *B, double *mean_jd, double *mean_mag ) {
 // double cov00,cov01; // needed if we want to use gsl_fit_wlinear() instead of gsl_fit_wmul()
 double cov11, chisq;
 double *fit_jd;
 double *fit_mag;
 double *fit_w;
 double *difference;
 int i;

 if ( N == 0 ) {
  return;
 }

 if ( N <= 0 ) {
  fprintf( stderr, "ERROR3: Trying allocate zero or negative number of bytes(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 fit_jd= malloc( N * sizeof( double ) );
 if ( fit_jd == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for fit_jd(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 fit_mag= malloc( N * sizeof( double ) );
 if ( fit_mag == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for fit_mag(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 fit_w= malloc( N * sizeof( double ) );
 if ( fit_w == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for fit_w(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 difference= malloc( N * sizeof( double ) );
 if ( difference == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for difference(lc.c)\n" );
  exit( EXIT_FAILURE );
 };

 for ( i= 0; i < N; i++ ) {
  fit_jd[i]= (double)input_JD[i];
  fit_mag[i]= (double)input_mag[i];
  fit_w[i]= 1.0 / (double)( mag_err[i] * mag_err[i] );
 }
 ( *mean_jd )= gsl_stats_mean( fit_jd, 1, N );
 ( *mean_mag )= gsl_stats_mean( fit_mag, 1, N );
 for ( i= 0; i < N; i++ ) {
  fit_jd[i]= fit_jd[i] - ( *mean_jd );
  fit_mag[i]= fit_mag[i] - ( *mean_mag );
 }
 // gsl_fit_wlinear(fit_jd,1,fit_w,1,fit_mag,1,N,B,A,&cov00,&cov01,&cov11,&chisq);
 gsl_fit_wmul( fit_jd, 1, fit_w, 1, fit_mag, 1, N, A, &cov11, &chisq );
 ( *B )= 0.0;

 // Suppress output if it's flat
 if ( ( *A ) < 1e-6 || 1e-6 < ( *A ) ) {
  fprintf( stderr, "Weighted linear trend fit:   %lf mag/day, corresponding to t_2mag= %lf, t_3mag= %lf\n", ( *A ), 2.0 / ( *A ), 3.0 / ( *A ) );
 }

 double poly_coeff[8];

 robustlinefit( fit_jd, fit_mag, N, poly_coeff );

 ( *B )= poly_coeff[0];
 ( *A )= poly_coeff[1];

 // Suppress output if it's flat
 if ( ( *A ) < 1e-6 || 1e-6 < ( *A ) ) {
  fprintf( stderr, "Robust linear trend fit:   %lf mag/day, corresponding to t_2mag= %lf, t_3mag= %lf\n", ( *A ), 2.0 / ( *A ), 3.0 / ( *A ) );
 }

 free( difference );
 free( fit_w );
 free( fit_mag );
 free( fit_jd );
 return;
}

void fit_median_for_jumps( float *input_JD, float *input_mag, float *mag_err, int N, double *A, double *B, double *mean_jd, double *mean_mag ) {
 double *fit_jd;
 double *fit_mag;
 double *fit_w;
 double *difference;
 int i;

 if ( N == 0 ) {
  return;
 }

 if ( N <= 0 ) {
  fprintf( stderr, "ERROR4: Trying allocate zero or negative number of bytes(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 fit_jd= malloc( N * sizeof( double ) );
 if ( fit_jd == NULL ) {
  fprintf( stderr, "ERROR2: Couldn't allocate memory for difference(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 fit_mag= malloc( N * sizeof( double ) );
 if ( fit_mag == NULL ) {
  fprintf( stderr, "ERROR2: Couldn't allocate memory for difference(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 fit_w= malloc( N * sizeof( double ) );
 if ( fit_w == NULL ) {
  fprintf( stderr, "ERROR2: Couldn't allocate memory for difference(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 difference= malloc( N * sizeof( double ) );
 if ( difference == NULL ) {
  fprintf( stderr, "ERROR2: Couldn't allocate memory for difference(lc.c)\n" );
  exit( EXIT_FAILURE );
 };

 for ( i= 0; i < N; i++ ) {
  fit_jd[i]= (double)input_JD[i];
  fit_mag[i]= (double)input_mag[i];
  fit_w[i]= 1.0 / (double)( mag_err[i] * mag_err[i] );
 }
 ( *mean_jd )= gsl_stats_mean( fit_jd, 1, N );
 gsl_sort( fit_mag, 1, N );
 ( *mean_mag )= gsl_stats_median_from_sorted_data( fit_mag, 1, N );
 ( *A )= 0.0;
 ( *B )= 0.0;

 fprintf( stderr, "median magnitude:   %lf\n", ( *mean_mag ) );

 free( difference );
 free( fit_w );
 free( fit_mag );
 free( fit_jd );
 return;
}

int get_star_number_from_name( char *output_str, char *input_str ) {
 char str1[FILENAME_LENGTH];
 char str[FILENAME_LENGTH];
 unsigned int i;
 int output_star_number;
 // strncpy(str1, input_str, FILENAME_LENGTH - 1);
 safely_encode_user_input_string( str1, input_str, FILENAME_LENGTH - 1 );
 str1[FILENAME_LENGTH - 1]= '\0';
 // strncpy(str, basename(str1), FILENAME_LENGTH - 1);
 safely_encode_user_input_string( str, basename( str1 ), FILENAME_LENGTH - 1 );
 str[FILENAME_LENGTH - 1]= '\0';
 // fprintf(stderr,"DEBUG: AAAAA\n");
 //  if file name is too short
 // if( strlen(str)<8 ){
 // if( strlen(str) < 2 ) {
 //  strncpy(output_str, " ", 2);
 //  return 0;
 // }
 if ( strlen( str ) < 3 ) {
  safely_encode_user_input_string( output_str, str, OUTFILENAME_LENGTH - 1 );
  output_str[OUTFILENAME_LENGTH - 1]= '\0';
  return 0;
 }

 // cut-out the extension
 for ( i= strlen( str ); i--; ) {
  if ( str[i] == '.' ) {
   str[i]= '\0';
   break;
  }
 }

 if ( strlen( str ) < 3 ) {
  safely_encode_user_input_string( output_str, str, OUTFILENAME_LENGTH - 1 );
  output_str[OUTFILENAME_LENGTH - 1]= '\0';
  return 0;
 }

 // remove 'out' if it is part of the name
 if ( str[0] == 'o' && str[1] == 'u' && str[2] == 't' ) {
  // Special case if the name starts with 'out_'
  if ( str[3] == '_' ) {
   // note that we also want to copy the terminating \0
   for ( i= 0; i < strlen( str ) - 3; i++ ) {
    str1[i]= str[i + 4];
   }
  } else {
   // note that we also want to copy the terminating \0
   for ( i= 0; i < strlen( str ) - 2; i++ ) {
    str1[i]= str[i + 3];
   }
  } // if( str[3]=='_'){
  // fprintf(stderr,"DEBUUUUUUU: str=#%s# strlen(str)=%d str1=#%s#\n\n\n",str,strlen(str),str1);
 } else {
  // strncpy(output_str, str, OUTFILENAME_LENGTH - 1);
  safely_encode_user_input_string( output_str, str, OUTFILENAME_LENGTH - 1 );
  output_str[OUTFILENAME_LENGTH - 1]= '\0';
  return 1;
 } // if( str[0]=='o' && str[1]=='u' && str[2]=='t' ){
 // strncpy(output_str, str1, OUTFILENAME_LENGTH - 1);
 safely_encode_user_input_string( output_str, str1, OUTFILENAME_LENGTH - 1 );
 output_str[OUTFILENAME_LENGTH - 1]= '\0';
 output_star_number= atoi( str1 );
 // fprintf(stderr,"\n\n\nDEBUG #%s# %d\n\n\n",str1,output_star_number);
 return output_star_number;
}

int find_closest( float x, float y, float *X, float *Y, int N, float new_X1, float new_X2, float new_Y1, float new_Y2 ) {
 float y_to_x_scaling_factor= fabsf( new_X2 - new_X1 ) / fabsf( new_Y2 - new_Y1 );
 int i;
 float best_dist;
 int best_dist_num= 0;
 best_dist= ( x - X[0] ) * ( x - X[0] ) + ( y - Y[0] ) * ( y - Y[0] ) * y_to_x_scaling_factor * y_to_x_scaling_factor; //!!
 for ( i= 1; i < N; i++ ) {
  if ( ( x - X[i] ) * ( x - X[i] ) + ( y - Y[i] ) * ( y - Y[i] ) * y_to_x_scaling_factor * y_to_x_scaling_factor < best_dist ) {
   best_dist= ( x - X[i] ) * ( x - X[i] ) + ( y - Y[i] ) * ( y - Y[i] ) * y_to_x_scaling_factor * y_to_x_scaling_factor;
   best_dist_num= i;
  }
 }
 return best_dist_num;
}

int is_comment( char *str ) {
 int i;
 int is_empty= 1;
 int n= strlen( str );

 if ( n < 1 )
  return 1;

 // Guess what: if it's the VaST lightcurve formatted file - there will be alphanumeric symbols in the column with file names
 // So check only the first 10 bytes of each string (a string containing an actual lightcurve point should not be that short)
 for ( i= 0; i < MIN( n - 1, 10 ); i++ ) {
  if ( str[i] != ' ' && str[i] != '0' && str[i] != '1' && str[i] != '2' && str[i] != '3' && str[i] != '4' && str[i] != '5' && str[i] != '6' && str[i] != '7' && str[i] != '8' && str[i] != '9' && str[i] != '.' && str[i] != '\r' && str[i] != '\n' && str[i] != '\t' && str[i] != '+' && str[i] != '-' )
   return 1;
  if ( str[i] == '\t' )
   str[i]= ' ';
  if ( str[i] == '\r' )
   str[i]= ' ';
  if ( str[i] != ' ' )
   is_empty= 0;
 }

 if ( is_empty == 1 )
  return 1;

 return 0;
}

int main( int argc, char **argv ) {
 // for rename ()
 char newpath[FILENAME_LENGTH];
 char oldpath[FILENAME_LENGTH];
 //
 char path_to_vast_string[VAST_PATH_MAX];
 char strmusor[VAST_PATH_MAX + 2 * FILENAME_LENGTH];
 int is_lightcurvefilename_modified= 0; // flag for apeending _edit to the edited lightcurve file names
 char lightcurvefilename[FILENAME_LENGTH];
 char tmp_lightcurvefilename[2 * FILENAME_LENGTH];
 FILE *lightcurvefile;
 double *JD= NULL;
 float *mag= NULL;
 float *mag_err= NULL;
 float *float_JD= NULL;
 float *X= NULL;
 float *Y= NULL;
 float *APER= NULL;
 char **filename;
 char unsanitized_filename[FILENAME_LENGTH];
 int Nobs= 0;
 int i, j;
 float minJD, maxJD, minmag, maxmag;
 // PGPLOT vars //
 float curX, curY;
 float curX2, curY2;
 char curC;
 //
 float markX= 0.0;
 float markY= 0.0;
 //
 char PGPLOT_CONTROL[1024];    // no idea what should be the correct size for this
 int change_limits_trigger= 0; // 0 - first time draw
                               // 1 - zoom in
                               // 2 - redraw plot with default limits
 float new_X1, new_X2, old_X1, old_X2;
 float new_Y1, new_Y2, old_Y1, old_Y2;
 char pokaz_start[VAST_PATH_MAX + 2 * FILENAME_LENGTH];
 int xw_ps= 0;                           // default plotting device - /xw
 int exit_after_plot= 0;                 // if =1 - plot once and exit
 int draw_errorbars= 0;                  // draw errorbars? 0 = no
 int was_lightcurve_changed= 0;          // =1 - it was
 int write_edited_lightcurve_to_file= 0; // 1 - do it now, 'W' or 'P' was pressed!
 int start_pokaz_script= 0;              // 1 - start script, 'P' was pressed!
 int plot_linear_trend_switch= 0;
 double A, B, mean_jd, mean_mag; // for trend fitting
 float breaks[512];              // breaks - trends on different sides of a break may be different
 int n_breaks= 0;                // number of breaks
 float tmp_x[2];                 // to draw vertical lines for breaks
 float tmp_y[2];                 // to draw vertical lines for breaks
 float *fit_jd= NULL;            // for trend fitting
 float *fit_mag= NULL;           // for trend fitting
 float *fit_mag_err= NULL;       // for trend fitting
 int fit_n= 0;                   // for trend fitting
 int jump_instead_of_break= 0;   // = 1 - fix A=0.0 in all linear trenf fits and use median magnitude instead of mean magnitude
 int plot_minimum_fitting_boundaries= 0;
 /* ----------- */
 int closest_num;
 int removed_points_counter_total= 0;
 int removed_points_counter_this_run= 0;
 int lightcurve_format;
 /* Statistic */
 double JD_first, JD_last;
 float m_mean, sigma, mean_sigma, error_mean;
 char header_str[1024];
 char header_str2[1024];
 double double_JD2float_JD= 0.0;
 char JD_label_str[1024];
 char mag_label_str[1024];
 char star_name[OUTFILENAME_LENGTH];

 double dmag, dmerr, dap, dx, dy;

 new_X1= 0.0;
 //
 new_X2= 0.0;
 new_Y1= 0.0;
 new_Y2= 0.0;
 //

 double UnixTime;
 time_t UnixTime_time_t;
 struct tm *structureTIME;

 int debug_mode= 0; // 1 - print debug messages

 int status= 0; // for wait3()

 int number_of_lines_in_lc_file_for_malloc;

 int pgplot_status;

 // char bin_dir_name[512]="./";
 int use_ds9_instead_of_pgfv= 0;
 /* Options for getopt() */
 int n;
 // char *cvalue = NULL;
 const char *const shortopt= "9dsneb:";
 const struct option longopt[]= {
     { "ds9", 0, NULL, '9' }, { "debug", 0, NULL, 'd' }, { "save", 0, NULL, 's' }, { "png", 0, NULL, 'n' }, { "errorbars", 0, NULL, 'e' }, { "bindir", 1, NULL, 'b' }, { NULL, 0, NULL, 0 } }; // NULL string must be in the end
 int nextopt;
 // struct stat buf;
 while ( nextopt= getopt_long( argc, argv, shortopt, longopt, NULL ), nextopt != -1 ) {
  switch ( nextopt ) {
  case '9':
   use_ds9_instead_of_pgfv= 1;
   fprintf( stderr, "option -9: DS9 will be used as a FITS image viewer\n" );
   break;
  case 'd':
   debug_mode= 1;
   fprintf( stderr, "option -d: Debug mode activated.\n" );
   break;
  case 's':
   xw_ps= 1;
   exit_after_plot= 1;
   fprintf( stderr, "option -s: lightcurve will be plotted to a .ps file\n" );
   break;
  case 'n':
   xw_ps= 2;
   exit_after_plot= 1;
   fprintf( stderr, "option -n: lightcurve will be plotted to a .png file\n" );
   break;
  case 'e':
   draw_errorbars= 1;
   fprintf( stderr, "option -e: plot errorbars\n" );
   break;
  case -1:
   fprintf( stderr, "That's all with options\n" );
   break;
  }
 }

 if ( debug_mode == 1 )
  fprintf( stderr, "Done parsing command line arguments.\n" );

 if ( argc == 1 ) {
  fprintf( stderr, "Usage:\n ./lc FILENAME\nor\n" );
  fprintf( stderr, "./lc FILENAME -9    # to use ds9 FITS viewer instead of pgfv\n" );
  fprintf( stderr, "./lc FILENAME -s    # plot lightcurve to a .ps file\n" );
  fprintf( stderr, "./lc FILENAME -n    # plot lightcurve to a .png file\n" );
  fprintf( stderr, "./lc FILENAME -e    # plot errorbars\n" );
  exit( EXIT_FAILURE );
 }
 for ( n= optind; n < argc; ++n ) {
  // strcpy(lightcurvefilename, argv[n]);
  safely_encode_user_input_string( lightcurvefilename, argv[n], FILENAME_LENGTH - 1 );
 }

 get_path_to_vast( path_to_vast_string );

 if (convert_aavso_format(lightcurvefilename, path_to_vast_string) != 0) {
    exit(EXIT_FAILURE);
 }

 if (convert_ztf_snad_format(lightcurvefilename, path_to_vast_string) != 0) {
    exit(EXIT_FAILURE);
 }

 fprintf( stderr, "Opening \x1B[34;47m %s \x1B[33;00m ...  ", lightcurvefilename );
 lightcurvefile= fopen( lightcurvefilename, "r" );
 if ( NULL == lightcurvefile ) {
  sprintf( tmp_lightcurvefilename, "out%s.dat", lightcurvefilename );
  strncpy( lightcurvefilename, tmp_lightcurvefilename, FILENAME_LENGTH - 1 );
  lightcurvefilename[FILENAME_LENGTH - 1]= '\0'; // just in case
  fprintf( stderr, "ERROR: cannot open file!\n Trying %s ... ", lightcurvefilename );
  lightcurvefile= fopen( lightcurvefilename, "r" );
  if ( NULL == lightcurvefile ) {
   fprintf( stderr, "ERROR: cannot open file!\n" );
   exit( EXIT_FAILURE );
  }
 }
 if ( NULL == fgets( strmusor, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lightcurvefile ) ) {
  fprintf( stderr, "ERROR: empty lightcurve file!\n" );
  exit( EXIT_FAILURE );
 }

 if ( 1 == is_comment( strmusor ) ) {
  while ( NULL != fgets( strmusor, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lightcurvefile ) ) {
   if ( 4 == sscanf( strmusor, "%lf %f %f %f", &JD_first, &m_mean, &sigma, &mean_sigma ) )
    break; // VaST lightcurve format
   if ( 0 == is_comment( strmusor ) )
    break;
  }
 }

 // Identify lightcurve format
 if ( 2 == sscanf( strmusor, "%lf %f", &JD_first, &m_mean ) ) {
  lightcurve_format= 2; // "JD mag" format
  if ( 3 == sscanf( strmusor, "%lf %f %f", &JD_first, &m_mean, &sigma ) ) {
   lightcurve_format= 1; // "JD mag err" format
   if ( 4 == sscanf( strmusor, "%lf %f %f %f", &JD_first, &m_mean, &sigma, &mean_sigma ) )
    lightcurve_format= 0; // VaST lightcurve format
  }
 } else {
  fprintf( stderr, "ERROR: cannot parse the lightcurve file!\n" );
  exit( EXIT_FAILURE );
 }
 if ( lightcurve_format == 0 )
  fprintf( stderr, "VaST lightcurve format detected!\n" );
 if ( lightcurve_format == 1 )
  fprintf( stderr, "\"JD mag err\" lightcurve format detected!\n" );
 if ( lightcurve_format == 2 )
  fprintf( stderr, "\"JD mag\" lightcurve format detected!\n" );

 /* Compute number of lines and allocate memory */
 fseek( lightcurvefile, 0, SEEK_SET ); // go back to the beginning of the lightcurve file
 // No idea why it should start with 1
 // for(i=0;;i++){
 for ( i= 1;; i++ ) {
  if ( NULL == fgets( strmusor, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lightcurvefile ) ) {
   break;
  }
 }
 // fprintf(stderr,"%d lines in the lightcurve file %s\n",i,lightcurvefilename);
 // if( lightcurve_format==0 )filename=(char **)malloc((i+1)*sizeof(char **));//malloc((i+1)*sizeof(char **));
 number_of_lines_in_lc_file_for_malloc= i;
 fprintf( stderr, "%d lines in the lightcurve file %s\n", number_of_lines_in_lc_file_for_malloc - 1, lightcurvefilename );
 fseek( lightcurvefile, 0, SEEK_SET ); // go back to the beginning of the lightcurve file

 // We will need these anyway
 JD= malloc( number_of_lines_in_lc_file_for_malloc * sizeof( double ) );
 if ( JD == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for JD(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 mag= malloc( number_of_lines_in_lc_file_for_malloc * sizeof( float ) );
 if ( mag == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for mag(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 mag_err= malloc( number_of_lines_in_lc_file_for_malloc * sizeof( float ) );
 if ( mag_err == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for mag_err(lc.c)\n" );
  exit( EXIT_FAILURE );
 };

 X= malloc( number_of_lines_in_lc_file_for_malloc * sizeof( float ) );
 if ( X == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for X(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 Y= malloc( number_of_lines_in_lc_file_for_malloc * sizeof( float ) );
 if ( Y == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for Y(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 APER= malloc( number_of_lines_in_lc_file_for_malloc * sizeof( float ) );
 if ( APER == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for APER(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 filename= (char **)malloc( number_of_lines_in_lc_file_for_malloc * sizeof( char * ) );
 if ( filename == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for filename(lc.c)\n" );
  exit( EXIT_FAILURE );
 };
 for ( i= 0; i < number_of_lines_in_lc_file_for_malloc; i++ ) {
  filename[i]= (char *)malloc( FILENAME_LENGTH * sizeof( char ) );
  if ( filename[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for filename[i](lc.c)\n" );
   exit( EXIT_FAILURE );
  };
 }

 // fprintf(stderr,"reading \x1B[34;47m %s \x1B[33;00m ... ",lightcurvefilename);

 Nobs= 0; // reset it here just in case
 dmag= dmerr= dx= dy= dap= 0.0;
 JD[Nobs]= 0.0; // initialize
 mag[Nobs]= mag_err[Nobs]= X[Nobs]= Y[Nobs]= APER[Nobs]= 0.0;
 // while( -1 < read_lightcurve_point(lightcurvefile, &JD[Nobs], &dmag, &dmerr, &dx, &dy, &dap, filename[Nobs], NULL) ) {
 while ( -1 < read_lightcurve_point( lightcurvefile, &JD[Nobs], &dmag, &dmerr, &dx, &dy, &dap, unsanitized_filename, NULL ) ) {
  if ( JD[Nobs] != 0.0 ) {
   mag[Nobs]= (float)dmag;
   mag_err[Nobs]= (float)dmerr;
   X[Nobs]= (float)dx;
   Y[Nobs]= (float)dy;
   APER[Nobs]= (float)dap;
   safely_encode_user_input_string( filename[Nobs], unsanitized_filename, FILENAME_LENGTH );
   Nobs++;
   JD[Nobs]= 0.0; // initialize the next one
   mag[Nobs]= mag_err[Nobs]= X[Nobs]= Y[Nobs]= APER[Nobs]= 0.0;
  }
 }

 // Nobs--;
 fclose( lightcurvefile );
 // fprintf(stderr,"OK\n");

 print_help();

 /// moved up as needed for lightcurve conversion
 //
 ///

 // Searching min max for double (for stats only) //
 JD_first= JD_last= JD[0];
 for ( i= 0; i < Nobs; i++ ) {
  if ( JD[i] > JD_last )
   JD_last= JD[i];
  if ( JD[i] < JD_first )
   JD_first= JD[i];
 }

 if ( Nobs <= 0 ) {
  fprintf( stderr, "ERROR: Attempting to allocate a zero or negative amount of memory (Nobs<= 0, lc.c)\n" );
  exit( EXIT_FAILURE );
 };

 // Determine plot limits
 minmag= maxmag= mag[0];
 minJD= maxJD= (float)JD[0];
 for ( i= 1; i < Nobs; i++ ) {
  minmag= MIN( minmag, mag[i] );
  maxmag= MAX( maxmag, mag[i] );
  minJD= MIN( minJD, (float)JD[i] );
 }
 // If possible, do not plot full JD, try something shorter...

 double_JD2float_JD= (double)( (int)minJD );

 float_JD= malloc( Nobs * sizeof( float ) );
 if ( float_JD == NULL ) {
  fprintf( stderr, "ERROR: can't allocate memory for float_JD: %d*sizeof(float)\n", Nobs );
  return 1;
 }

 minJD= maxJD= (float)( JD[0] - double_JD2float_JD );
 for ( i= 0; i < Nobs; i++ ) {
  float_JD[i]= (float)( JD[i] - double_JD2float_JD );
  minJD= MIN( minJD, float_JD[i] );
  maxJD= MAX( maxJD, float_JD[i] );
 }

 /* Choose appropriate axes labels */
 if ( minmag < 0.0 )
  sprintf( mag_label_str, "Instrumental Magnitude" );
 else
  sprintf( mag_label_str, "Magnitude" );

 if ( double_JD2float_JD != 0.0 )
  sprintf( JD_label_str, "JD - %.1lf", double_JD2float_JD );
 else
  sprintf( JD_label_str, "JD" );

 /* Start GUI */
 curC= ' ';                     // just some value which doesn't mean anything
 curX= curY= curX2= curY2= 0.0; // same here
 // setenv("PGPLOT_DIR","lib/pgplot/",1);
 setenv_localpgplot( argv[0] );
 do {
  // Check what plotting device should be used
  if ( xw_ps == 1 )
   strcpy( PGPLOT_CONTROL, "/CPS" );
  if ( xw_ps == 2 )
   strcpy( PGPLOT_CONTROL, "/PNG" );
  if ( xw_ps == 0 || xw_ps == -1 )
   strcpy( PGPLOT_CONTROL, "/XW" );

  if ( change_limits_trigger == 0 || xw_ps != 0 ) {
   pgplot_status= cpgopen( PGPLOT_CONTROL );
   if ( pgplot_status <= 0 ) {
    fprintf( stderr, "ERROR opening PGPLOT device %s\n", PGPLOT_CONTROL );
    if ( 0 == strcmp( PGPLOT_CONTROL, "/PNG" ) ) {
     // fall back to PS plotting
     fprintf( stderr, "Falling back to PGPLOT device /CPS\n" );
     strcpy( PGPLOT_CONTROL, "/CPS" );
     xw_ps= 1;
     curC= 's';
     // cpgclos(); // seems to be not needed if the device was not open
     fprintf( stderr, "Retrying to open PGPLOT device %s\n", PGPLOT_CONTROL );
     pgplot_status= cpgopen( PGPLOT_CONTROL );
    }
    // If the fallback option didn't work
    if ( pgplot_status <= 0 ) {
     fprintf( stderr, "Emergency exit.\n" );
     exit( EXIT_FAILURE );
    }
   }
   if ( 0 == strcmp( PGPLOT_CONTROL, "/XW" ) ) {
    xw_ps= 0;
    if ( change_limits_trigger == 0 )
     change_limits_trigger= 2;
   }
   if ( xw_ps == 0 ) {
    cpgscr( 0, 0.10, 0.31, 0.32 ); // set default vast window background
    cpgpage();
   }
   if ( xw_ps == 2 ) {
    cpgscr( 0, 1.0, 1.0, 1.0 ); // set white background
    cpgscr( 1, 0.0, 0.0, 0.0 ); // and black foreground
    cpgpage();
   }
  }

  if ( xw_ps == 0 ) {
   //
   cpgscr( 1, 1.0, 1.0, 1.0 ); // set color of axes lables - white
   //
   cpgscr( 0, 0.10, 0.31, 0.32 ); // set default vast window background
   cpgeras();
   cpgask( 0 ); // turn OFF this silly " Type <RETURN> for next page:" request
  }

  cpgsvp( 0.08, 0.95, 0.1, 0.9 );
  if ( change_limits_trigger == 2 || change_limits_trigger == 0 ) {
   old_X1= minJD - ( maxJD - minJD ) / 10;
   old_X2= maxJD + ( maxJD - minJD ) / 10;
   new_X1= old_X1;
   new_X2= old_X2;

   old_Y1= maxmag + ( maxmag - minmag ) / 10;
   old_Y2= minmag - ( maxmag - minmag ) / 10;
   new_Y1= old_Y1;
   new_Y2= old_Y2;
  }
  //   fprintf(stderr,"##### DEBUG01 #####\n");

  // Zero timerange warning
  if ( new_X1 == new_X2 ) {
   fprintf( stderr, "\nWARNING: cannot determine the lightcurve time span!\nSomething is very wrong with the observing date/time information in this data set.\n\n" );
  }

  cpgswin( new_X1, new_X2, new_Y1, new_Y2 );
  if ( xw_ps == 0 ) {
   cpgscr( 0, 0.08, 0.08, 0.09 ); // set background
  }
  cpgsci( 0 );
  cpgrect( new_X1, new_X2, new_Y1, new_Y2 );
  cpgsci( 1 );
  cpgscf( 1 );
  cpgbox( "BCNST1", 0.0, 0, "BCNST1", 0.0, 0 );

  //   fprintf(stderr,"DEBUG: new_X1=%.5f new_X2=%.5f\n",new_X1,new_X2);

  /* Generate some lightcurve stats */
  m_mean= gsl_stats_float_mean( mag, 1, Nobs ); /* Mean magnitude */
  // if we have information about measurement errors...
  if ( lightcurve_format != 2 )
   mean_sigma= gsl_stats_float_mean( mag_err, 1, Nobs ); /* expected statistical error */
  else
   mean_sigma= -99.9;
  sigma= gsl_stats_float_sd( mag, 1, Nobs ); /* the standard deviation of the distribution */
  error_mean= sigma / sqrtf( (float)Nobs );  /* the standard deviation of the mean */

  //   fprintf(stderr,"##### DEBUG02 #####\n");

  cpgscf( 1 );
  cpgsch( 1.0 ); /* make lables with normal characters */
  if ( xw_ps == 0 )
   cpgscr( 1, 0.62, 0.81, 0.38 ); /* set color of lables */
  get_star_number_from_name( star_name, lightcurvefilename );

  //// What we don't know is how long is the target name
  sprintf( header_str, "Object %s, %d observations over %.1lf years starting on JD %.4lf", star_name, Nobs, ( JD_last - JD_first ) / 365.25, JD_first );
  if ( strlen( header_str ) > 78 ) {
   sprintf( header_str, "Object %s, %d observations over %.1lf years", star_name, Nobs, ( JD_last - JD_first ) / 365.25 );
  }
  if ( JD_last - JD_first < 2 * 365.0 ) {
   sprintf( header_str, "Object %s, %d observations over %.2lf days starting on JD %.4lf", star_name, Nobs, JD_last - JD_first, JD_first );
   if ( strlen( header_str ) > 78 ) {
    sprintf( header_str, "Object %s, %d observations over %.2lf days", star_name, Nobs, JD_last - JD_first );
   }
  }
  if ( JD_last - JD_first < 1.0 ) {
   sprintf( header_str, "Object %s, %d observations over %.2lf hours starting on JD %.4lf", star_name, Nobs, ( JD_last - JD_first ) * 24, JD_first );
   if ( strlen( header_str ) > 78 ) {
    sprintf( header_str, "Object %s, %d observations over %.2lf hours", star_name, Nobs, ( JD_last - JD_first ) * 24 );
   }
  }
  if ( JD_last - JD_first < 2.0 / 24.0 ) {
   sprintf( header_str, "Object %s, %d observations over %.0lf minutes starting on JD %.4lf", star_name, Nobs, ( JD_last - JD_first ) * 24 * 60, JD_first );
   if ( strlen( header_str ) > 78 ) {
    sprintf( header_str, "Object %s, %d observations over %.0lf minutes", star_name, Nobs, ( JD_last - JD_first ) * 24 * 60 );
   }
  }
  /*
    if( JD_last-JD_first < 1.0 ) {
     if( JD_last-JD_first < 2.0/24.0 ) {
      sprintf(header_str, "Object %s, %d observations over %.0lf minutes starting on JD %.4lf", star_name, Nobs, (JD_last-JD_first)*24*60, JD_first);
      if( strlen(header_str) > 78 ) {
       sprintf(header_str, "Object %s, %d observations over %.0lf minutes", star_name, Nobs, (JD_last-JD_first)*24*60);
      }
     } else {
      sprintf(header_str, "Object %s, %d observations over %.2lf hours starting on JD %.4lf", star_name, Nobs, (JD_last-JD_first)*24, JD_first);
      if( strlen(header_str) > 78 ) {
       sprintf(header_str, "Object %s, %d observations over %.2lf hours", star_name, Nobs, (JD_last-JD_first)*24);
      }
     }
    } else {
     sprintf(header_str, "Object %s, %d observations over %.2lf days starting on JD %.4lf", star_name, Nobs, JD_last-JD_first, JD_first);
     if( strlen(header_str) > 78 ) {
      sprintf(header_str, "Object %s, %d observations over %.2lf days", star_name, Nobs, JD_last-JD_first);
     }
    }
   */
  ////

  if ( strlen( header_str ) > 78 ) {
   cpgsch( 0.9 ); // make lables with small characters
  }

  // fprintf(stderr,"#%s#\n#%s#\n",header_str,lightcurvefilename);

  // Print second title line only if we are drawing in an X window, not a file
  if ( xw_ps == 0 ) {
   cpgmtxt( "T", 2.0, 0.0, 0.0, header_str );

   sprintf( header_str, "<m>=%.3f +/-%.3f,  sigma= %.3f", m_mean, error_mean, sigma );
   if ( sigma < 0.002 ) {
    sprintf( header_str, "<m>=%.4f +/-%.4f,  sigma= %.4f", m_mean, error_mean, sigma );
   }
   if ( lightcurve_format != 2 ) {
    sprintf( header_str2, ", expected sigma = %.3f", mean_sigma );
    if ( mean_sigma < 0.002 ) {
     sprintf( header_str2, ", expected sigma = %.4f", mean_sigma );
    }
    strcat( header_str, header_str2 );
   }
   cpgmtxt( "T", 1.0, 0.0, 0.0, header_str );
  } else {
   // print only one-line title and only if no zoom was used!
   if ( change_limits_trigger == 2 || change_limits_trigger == 0 )
    cpgmtxt( "T", 1.0, 0.0, 0.0, header_str );
  }

  //   fprintf(stderr,"##### DEBUG03 #####\n");

  /* Make axes lables */
  cpgsch( 1.2 ); /* make axes lables with larger characters */
  cpgmtxt( "L", 2.5, 0.5, 0.5, mag_label_str );
  cpgmtxt( "B", 2.5, 0.5, 0.5, JD_label_str );
  if ( xw_ps == 0 )
   cpgscr( 1, 1.0, 1.0, 1.0 ); // set color back to normal
  cpgsch( 1.0 );               // set character size back to normal

  if ( lightcurve_format != 2 && draw_errorbars == 1 ) {
   // plot errors
   cpgerrb( 6, Nobs, float_JD, mag, mag_err, 1.0 );
  }
  cpgpt( Nobs, float_JD, mag, 17 ); // plot data

  // Mark the previously viewed lightcurve point
  if ( markX != 0.0 && markY != 0.0 ) {
   cpgsci( 2 );
   cpgpt1( markX, markY, 4 );
   cpgsci( 5 );
  }

  //   fprintf(stderr,"##### DEBUG04 #####\n");

  // plot break lines
  if ( n_breaks != 0 ) {
   gsl_sort_float( breaks, 1, n_breaks );
  }
  cpgsci( 4 );
  for ( i= 0; i < n_breaks; i++ ) {
   tmp_x[1]= tmp_x[0]= breaks[i];
   tmp_y[0]= new_Y1;
   tmp_y[1]= new_Y2;
   if ( plot_linear_trend_switch == 1 )
    cpgline( 2, tmp_x, tmp_y );
   if ( plot_minimum_fitting_boundaries == 1 ) {
    cpgsci( 9 );
    cpgline( 2, tmp_x, tmp_y );
   } // plot minimum fitting boundaries
  }

  //   fprintf(stderr,"##### DEBUG05 #####\n");

  if ( plot_linear_trend_switch == 1 ) { // fit and plot linear trends and breaks if there are any, some more details my be found below near remove_linear_trend
   if ( fit_n == 0 ) {
    // allocate memory
    // fprintf(stderr,"DEBUUUUGGGG\n\n\n");
    fit_jd= malloc( Nobs * sizeof( float ) );
    if ( fit_jd == NULL ) {
     fprintf( stderr, "ERROR3: Couldn't allocate memory for fit_jd(lc.c)\n" );
     exit( EXIT_FAILURE );
    };
    fit_mag= malloc( Nobs * sizeof( float ) );
    if ( fit_mag == NULL ) {
     fprintf( stderr, "ERROR3: Couldn't allocate memory for fit_mag(lc.c)\n" );
     exit( EXIT_FAILURE );
    };
    fit_mag_err= malloc( Nobs * sizeof( float ) );
    if ( fit_mag_err == NULL ) {
     fprintf( stderr, "ERROR3: Couldn't allocate memory for fit_mag_err(lc.c)\n" );
     exit( EXIT_FAILURE );
    };
    fit_n= Nobs;
   }

   if ( n_breaks == 0 ) {
    if ( jump_instead_of_break == 0 )
     fit_linear_trend( float_JD, mag, mag_err, Nobs, &A, &B, &mean_jd, &mean_mag );
    else
     fit_median_for_jumps( float_JD, mag, mag_err, Nobs, &A, &B, &mean_jd, &mean_mag );
    plot_linear_trend( float_JD, Nobs, A, B, mean_jd, mean_mag );
   }

   if ( n_breaks == 1 ) {
    //
    fit_n= 0;
    for ( i= 0; i < Nobs; i++ ) {
     if ( float_JD[i] <= breaks[0] ) {
      fit_jd[fit_n]= float_JD[i];
      fit_mag[fit_n]= mag[i];
      fit_mag_err[fit_n]= mag_err[i];
      fit_n++;
     }
    }
    if ( jump_instead_of_break == 0 )
     fit_linear_trend( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    else
     fit_median_for_jumps( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    plot_linear_trend( fit_jd, fit_n, A, B, mean_jd, mean_mag );
    //
    //
    fit_n= 0;
    for ( i= 0; i < Nobs; i++ ) {
     if ( float_JD[i] > breaks[0] ) {
      fit_jd[fit_n]= float_JD[i];
      fit_mag[fit_n]= mag[i];
      fit_mag_err[fit_n]= mag_err[i];
      fit_n++;
     }
    }
    if ( jump_instead_of_break == 0 )
     fit_linear_trend( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    else
     fit_median_for_jumps( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    plot_linear_trend( fit_jd, fit_n, A, B, mean_jd, mean_mag );
    //
   }

   if ( n_breaks > 1 ) {
    //
    fit_n= 0;
    for ( i= 0; i < Nobs; i++ ) {
     if ( float_JD[i] <= breaks[0] ) {
      //
      // fprintf(stderr, "fit_n=%d i=%d breaks[0]=%f\n", fit_n, i, breaks[0]);
      //
      fit_jd[fit_n]= float_JD[i];
      fit_mag[fit_n]= mag[i];
      fit_mag_err[fit_n]= mag_err[i];
      fit_n++;
     }
    }
    if ( jump_instead_of_break == 0 )
     fit_linear_trend( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    else
     fit_median_for_jumps( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    plot_linear_trend( fit_jd, fit_n, A, B, mean_jd, mean_mag );
    //
    //
    for ( j= 1; j < n_breaks; j++ ) {
     fit_n= 0;
     for ( i= 0; i < Nobs; i++ ) {
      if ( float_JD[i] > breaks[j - 1] && float_JD[i] < breaks[j] ) {
       fit_jd[fit_n]= float_JD[i];
       fit_mag[fit_n]= mag[i];
       fit_mag_err[fit_n]= mag_err[i];
       fit_n++;
      }
     }
     if ( jump_instead_of_break == 0 )
      fit_linear_trend( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
     else
      fit_median_for_jumps( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
     plot_linear_trend( fit_jd, fit_n, A, B, mean_jd, mean_mag );
    }
    //
    //
    fit_n= 0;
    for ( i= 0; i < Nobs; i++ ) {
     if ( float_JD[i] > breaks[n_breaks - 1] ) {
      fit_jd[fit_n]= float_JD[i];
      fit_mag[fit_n]= mag[i];
      fit_mag_err[fit_n]= mag_err[i];
      fit_n++;
     }
    }
    if ( jump_instead_of_break == 0 )
     fit_linear_trend( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    else
     fit_median_for_jumps( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    plot_linear_trend( fit_jd, fit_n, A, B, mean_jd, mean_mag );
    //
   }

   free( fit_jd );
   free( fit_mag );
   free( fit_mag_err );

   fit_jd= NULL;
   fit_mag= NULL;
   fit_mag_err= NULL;

   fit_n= 0; // or we'll not reallocate the memory for fit_jd and stuff when we'll get back here
  }          // if( plot_linear_trend_switch==1 ){

  //   fprintf(stderr,"##### DEBUG06 #####\n");

  cpgsci( 5 );
  if ( xw_ps == 0 )
   cpgcurs( &curX, &curY, &curC );

  // Check if the click is outside the plot
  // (we'll just redraw the plot if it is)
  // fprintf(stderr,"######################################\n######################################\n");
  if ( curC == 'A' || curC == 'a' ) {
   if ( curX < new_X1 || curX > new_X2 || curY > new_Y1 || curY < new_Y2 ) {
    // fprintf(stderr,"%f %f \n",curX,curY);
    curC= 'R';
   }
  }

  /* Zoom */
  if ( curC == 'Z' || curC == 'z' ) {
   cpgband( 2, 0, curX, curY, &curX2, &curY2, &curC );
   if ( new_X1 != 0.0 ) {
    old_X1= new_X1;
    old_X2= new_X2;
   }
   new_X1= curX;
   new_Y1= curY;

   // fprintf(stderr,"DEBUG: curX=%.5f curY=%.5f curX2=%.5f curY2=%.5f\n",curX,curY,curX2,curY2);

   if ( curC == 'Z' || curC == 'z' )
    curC= 'D';
   else
    curC= 'R';

   change_limits_trigger= 1;
   if ( curX2 > new_X1 )
    new_X2= curX2;
   else {
    new_X2= new_X1;
    new_X1= curX2;
   }
   if ( curY2 < new_Y1 )
    new_Y2= curY2;
   else {
    new_Y2= new_Y1;
    new_Y1= curY2;
   }

   if ( fabs( new_X2 - new_X1 ) < 0.05 ) { // do not zoom too much
    old_X1= ( new_X1 + new_X2 ) / 2.0 - 0.025;
    old_X2= ( new_X1 + new_X2 ) / 2.0 + 0.025;
    new_X1= old_X1;
    new_X2= old_X2;
   }
   if ( fabs( new_Y2 - new_Y1 ) < 0.005 ) { // do not zoom too much
    old_Y1= ( new_Y1 + new_Y2 ) / 2.0 + 0.0025;
    old_Y2= ( new_Y1 + new_Y2 ) / 2.0 - 0.0025;
    new_Y1= old_Y1;
    new_Y2= old_Y2;
   }

  } /* End of Zoom */
  if ( curC == 'x' )
   curC= 'X'; // in case small 'x' was pressed - that still means exit!

  // Mark that user wants to fit and plot linear trend
  if ( curC == '1' ) {
   if ( plot_linear_trend_switch == 0 )
    plot_linear_trend_switch= 1;
   else
    plot_linear_trend_switch= 0;
  }

  // subtract one or many linear trends (many trends may be defined in regions separated by breaks)
  if ( curC == '-' ) {
   //
   if ( 0 == unlink( "vast_lc_remove_linear_trend.log" ) ) {
    fprintf( stderr, "Rewriting the trend-subtraction log file \x1B[34;47m vast_lc_remove_linear_trend.log \x1B[33;00m\n\n" );
   }
   //

   if ( fit_n == 0 ) {
    // allocate memory
    fit_jd= malloc( Nobs * sizeof( float ) );
    if ( fit_jd == NULL ) {
     fprintf( stderr, "ERROR4: Couldn't allocate memory for fit_jd(lc.c)\n" );
     exit( EXIT_FAILURE );
    };
    fit_mag= malloc( Nobs * sizeof( float ) );
    if ( fit_mag == NULL ) {
     fprintf( stderr, "ERROR4: Couldn't allocate memory for fit_mag(lc.c)\n" );
     exit( EXIT_FAILURE );
    };
    fit_mag_err= malloc( Nobs * sizeof( float ) );
    if ( fit_mag_err == NULL ) {
     fprintf( stderr, "ERROR3: Couldn't allocate memory for fit_mag_err(lc.c)\n" );
     exit( EXIT_FAILURE );
    };
    fit_n= Nobs;
   }

   // if there are no breaks, just one trend
   if ( n_breaks == 0 ) {
    if ( jump_instead_of_break == 0 ) {
     fit_linear_trend( float_JD, mag, mag_err, Nobs, &A, &B, &mean_jd, &mean_mag );
    } else {
     fit_median_for_jumps( float_JD, mag, mag_err, Nobs, &A, &B, &mean_jd, &mean_mag );
    }
    remove_linear_trend( float_JD, mag, Nobs, A, B, mean_jd, mean_mag - m_mean, minJD, maxJD, m_mean, JD );
   }

   // if there is only one break
   if ( n_breaks == 1 ) {
    //
    fit_n= 0;
    for ( i= 0; i < Nobs; i++ ) {
     if ( float_JD[i] <= breaks[0] ) {
      fit_jd[fit_n]= float_JD[i];
      fit_mag[fit_n]= mag[i];
      fit_mag_err[fit_n]= mag_err[i];
      fit_n++;
     }
    }
    if ( jump_instead_of_break == 0 ) {
     fit_linear_trend( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    } else {
     fit_median_for_jumps( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    }
    remove_linear_trend( float_JD, mag, Nobs, A, B, mean_jd, mean_mag - m_mean, minJD, breaks[0], m_mean, JD );
    //
    //
    fit_n= 0;
    for ( i= 0; i < Nobs; i++ ) {
     if ( float_JD[i] > breaks[0] ) {
      fit_jd[fit_n]= float_JD[i];
      fit_mag[fit_n]= mag[i];
      fit_mag_err[fit_n]= mag_err[i];
      fit_n++;
     }
    }
    if ( jump_instead_of_break == 0 ) {
     fit_linear_trend( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    } else {
     fit_median_for_jumps( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    }
    remove_linear_trend( float_JD, mag, Nobs, A, B, mean_jd, mean_mag - m_mean, breaks[0], maxJD, m_mean, JD );
    //
   }

   // if there are many breaks
   if ( n_breaks > 1 ) {
    //
    fit_n= 0;
    for ( i= 0; i < Nobs; i++ ) {
     if ( float_JD[i] <= breaks[0] ) {
      fit_jd[fit_n]= float_JD[i];
      fit_mag[fit_n]= mag[i];
      fit_mag_err[fit_n]= mag_err[i];
      fit_n++;
     }
    }
    if ( jump_instead_of_break == 0 ) {
     fit_linear_trend( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    } else {
     fit_median_for_jumps( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    }
    remove_linear_trend( float_JD, mag, Nobs, A, B, mean_jd, mean_mag - m_mean, minJD, breaks[0], m_mean, JD );
    //
    //
    for ( j= 1; j < n_breaks; j++ ) {
     fit_n= 0;
     for ( i= 0; i < Nobs; i++ ) {
      if ( float_JD[i] > breaks[j - 1] && float_JD[i] < breaks[j] ) {
       fit_jd[fit_n]= float_JD[i];
       fit_mag[fit_n]= mag[i];
       fit_mag_err[fit_n]= mag_err[i];
       fit_n++;
      }
     }
     if ( jump_instead_of_break == 0 ) {
      fit_linear_trend( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
     } else {
      fit_median_for_jumps( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
     }
     remove_linear_trend( float_JD, mag, Nobs, A, B, mean_jd, mean_mag - m_mean, breaks[j - 1], breaks[j], m_mean, JD );
    }
    //
    //
    fit_n= 0;
    for ( i= 0; i < Nobs; i++ ) {
     if ( float_JD[i] > breaks[n_breaks - 1] ) {
      fit_jd[fit_n]= float_JD[i];
      fit_mag[fit_n]= mag[i];
      fit_mag_err[fit_n]= mag_err[i];
      fit_n++;
     }
    }
    if ( jump_instead_of_break == 0 ) {
     fit_linear_trend( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    } else {
     fit_median_for_jumps( fit_jd, fit_mag, fit_mag_err, fit_n, &A, &B, &mean_jd, &mean_mag );
    }
    remove_linear_trend( float_JD, mag, Nobs, A, B, mean_jd, mean_mag - m_mean, breaks[n_breaks - 1], maxJD, m_mean, JD );
   }

   fprintf( stderr, "Completed writing the trend-subtraction log file \x1B[34;47m vast_lc_remove_linear_trend.log \x1B[33;00m\n\n" );

   was_lightcurve_changed= 1; // note, that lightcurve was changed

   free( fit_jd );
   free( fit_mag );
   free( fit_mag_err );
   fit_jd= NULL;
   fit_mag= NULL;
   fit_mag_err= NULL;

   n_breaks= 0; // reset the breaks counter
   fit_n= 0;    // reset this one too, just in case
  }

  // terminate single data point
  if ( curC == 'T' || curC == 't' ) {
   closest_num= find_closest( curX, curY, float_JD, mag, Nobs, new_X1, new_X2, new_Y1, new_Y2 );
   was_lightcurve_changed= 1; // note, that lightcurve was changed
   Nobs--;
   for ( i= closest_num; i < Nobs; i++ ) {
    JD[i]= JD[i + 1];
    float_JD[i]= float_JD[i + 1];
    mag[i]= mag[i + 1];
    if ( lightcurve_format != 2 )
     mag_err[i]= mag_err[i + 1];
    if ( lightcurve_format == 0 ) {
     X[i]= X[i + 1];
     Y[i]= Y[i + 1];
     APER[i]= APER[i + 1];
     strcpy( filename[i], filename[i + 1] );
    }
   }
  }

  // terminate all data point in selected region
  if ( curC == 'C' || curC == 'c' ) {
   cpgsci( 2 );
   cpgband( 2, 0, curX, curY, &curX2, &curY2, &curC );
   // last chance to cancel!
   if ( curC != 'X' && curC != 'x' ) {
    removed_points_counter_this_run= 0;
    for ( closest_num= 0; closest_num < Nobs; closest_num++ ) {
     // fprintf(stderr,"%f %f  %f %f\n",MIN(curX,curX2),MAX(curX,curX2),MIN(curY,curY2),MAX(curY,curY2));
     if ( float_JD[closest_num] > MIN( curX, curX2 ) && float_JD[closest_num] < MAX( curX, curX2 ) && mag[closest_num] > MIN( curY, curY2 ) && mag[closest_num] < MAX( curY, curY2 ) ) {
      // fprintf(stderr,"Nobs= %d\n",Nobs); // DEBUG!!
      fprintf( stderr, "Removing data point %5d %.5lf %8.4f\n", closest_num, JD[closest_num], mag[closest_num] );
      // kill it
      Nobs--;
      for ( i= closest_num; i < Nobs; i++ ) {
       // fprintf(stderr,"DEBUG: closest_num=%d    i=%d     Nobs=%d\n",closest_num,i,Nobs);
       // fprintf(stderr,"lightcurve_format=%d JD[%d+1]= %lf\n",lightcurve_format,i,JD[i+1]); // DEBUG!!
       // fprintf(stderr,"                    float_JD[%d+1]= %lf\n",i,float_JD[i+1]); // DEBUG!!
       // fprintf(stderr,"                    mag[%d+1]= %lf\n",i,mag[i+1]); // DEBUG!!
       JD[i]= JD[i + 1];
       float_JD[i]= float_JD[i + 1];
       mag[i]= mag[i + 1];
       if ( lightcurve_format != 2 )
        mag_err[i]= mag_err[i + 1];
       if ( lightcurve_format == 0 ) {
        X[i]= X[i + 1];
        Y[i]= Y[i + 1];
        APER[i]= APER[i + 1];
        strcpy( filename[i], filename[i + 1] );
       } // if( lightcurve_format==0 )
       // the following works, I don't know why...
       if ( closest_num != -1 )
        closest_num--; /// ! TEST !
      }                // for(i=closest_num;i<Nobs;i++)
      was_lightcurve_changed= 1;
      removed_points_counter_total++;
      removed_points_counter_this_run++;
     } // if inside the rectangle
    }  // for(closest_num=0;i<Nobs;i++)
    fprintf( stderr, "Removed %5d data points (%5d removed data points in total)\n", removed_points_counter_this_run, removed_points_counter_total );
   } // if( curC!='X' && curC!='x' )
   curC= ' ';
  } // if( curC=='C' || curC=='c' )

  // do not allow to write edited lightcurve if no changes were made!
  if ( was_lightcurve_changed == 0 ) {
   if ( curC == 'W' || curC == 'w' ) {
    curC= ' ';
    fprintf( stderr, "No changes were applied to the lightcurve! I don't want to save it! %%)\n" );
   }
  }
  // write edited lightcurve to file
  if ( curC == 'W' || curC == 'w' ) {
   write_edited_lightcurve_to_file= 1;
  }

  // start WinEfk wrapper
  if ( curC == 'P' || curC == 'p' ) {
   if ( was_lightcurve_changed != 0 ) {
    write_edited_lightcurve_to_file= 1; // write the lightcurve to a new file if it was changed
    was_lightcurve_changed= 0;
   }
   start_pokaz_script= 1; // and start the script
  }
  // start web-based period search tool wrapper
  if ( curC == 'L' || curC == 'l' ) {
   if ( was_lightcurve_changed != 0 ) {
    write_edited_lightcurve_to_file= 1; // write the lightcurve to a new file if it was changed
    was_lightcurve_changed= 0;
   }
   start_pokaz_script= 2; // and start the script
  }
  // start the experimental web-based lightcurve classifier
  if ( curC == 'Q' || curC == 'q' ) {
   if ( was_lightcurve_changed != 0 ) {
    write_edited_lightcurve_to_file= 1; // write the lightcurve to a new file if it was changed
    was_lightcurve_changed= 0;
   }
   start_pokaz_script= 3; // and start the script
  }

  if ( write_edited_lightcurve_to_file == 1 ) {
   was_lightcurve_changed= 0;
   write_edited_lightcurve_to_file= 0; // don't do it again unless 'W' or 'P' will be pressed again
   // fprintf(stderr,"\n\n\nDEBUUUUGGG #%s#\n&(lightcurvefilename[strlen(lightcurvefilename) - 4]=#%s#\n&(lightcurvefilename[strlen(lightcurvefilename) - 3])=#%s#\n",lightcurvefilename,&(lightcurvefilename[strlen(lightcurvefilename) - 4]),&(lightcurvefilename[strlen(lightcurvefilename) - 3]));
   //  make sure the lightcurve file name is long enough
   if ( strlen( lightcurvefilename ) > 5 ) {
    // we don't do the fancy renaming if the input lightcurve file name is too short
    if ( NULL != strstr( lightcurvefilename, ".dat" ) ) {
     lightcurvefilename[strlen( lightcurvefilename ) - 4]= '\0'; // remove ".dat"
     strcat( lightcurvefilename, "_edit.dat" );
     is_lightcurvefilename_modified= 1;
    }
    if ( NULL != strstr( lightcurvefilename, ".txt" ) ) {
     lightcurvefilename[strlen( lightcurvefilename ) - 4]= '\0'; // remove ".txt"
     strcat( lightcurvefilename, "_edit.txt" );
     is_lightcurvefilename_modified= 1;
    }
    if ( NULL != strstr( lightcurvefilename, ".csv" ) ) {
     lightcurvefilename[strlen( lightcurvefilename ) - 4]= '\0'; // remove ".csv"
     strcat( lightcurvefilename, "_edit.csv" );
     is_lightcurvefilename_modified= 1;
    }
    if ( NULL != strstr( lightcurvefilename, ".lc" ) ) {
     lightcurvefilename[strlen( lightcurvefilename ) - 3]= '\0'; // remove ".lc"
     strcat( lightcurvefilename, "_edit.lc" );
     is_lightcurvefilename_modified= 1;
    }
   }
   if ( is_lightcurvefilename_modified == 0 ) {
    // we did not recognize the file name extension, so we'll make it ugly
    strcat( lightcurvefilename, "_edit.dat" );
   }
   is_lightcurvefilename_modified= 0; // reset flag
   lightcurvefile= fopen( lightcurvefilename, "w" );
   for ( i= 0; i < Nobs; i++ ) {
    fprintf( lightcurvefile, "%.5lf %9.5f", JD[i], mag[i] );
    if ( lightcurve_format != 2 )
     fprintf( lightcurvefile, " %.5f", mag_err[i] );
    if ( lightcurve_format == 0 )
     fprintf( lightcurvefile, " %8.3lf %8.3lf %4.1lf %s", X[i], Y[i], APER[i], filename[i] );
    fprintf( lightcurvefile, "\n" );
   }
   fclose( lightcurvefile );
   fprintf( stderr, "Edited lightcurve is written to %s\n", lightcurvefilename );
  }
  if ( start_pokaz_script == 1 ) {
   // TODO: make sure lightcurvefilename exist
   //
   start_pokaz_script= 0; // don't do it again unless 'P' will be pressed again
   // path_to_vast_string always ends with '/'
   sprintf( pokaz_start, "%spokaz_winefk.sh %s ", path_to_vast_string, lightcurvefilename );
   // fork before system() so the parent process is not blocked
   if ( 0 == fork() ) {
    if ( 0 != system( pokaz_start ) ) {
     fprintf( stderr, "ERROR in %s", pokaz_start );
    }
    exit( EXIT_SUCCESS );
   } else {
    sleep( 1 );
    waitpid( -1, &status, WNOHANG );
   }
   change_limits_trigger= 1;
  }
  if ( start_pokaz_script == 2 ) {
   // TODO: make sure lightcurvefilename exist
   //
   start_pokaz_script= 0; // don't do it again unless 'L' will be pressed again
   // path_to_vast_string always ends with '/'
   sprintf( pokaz_start, "%spokaz_laflerkinman.sh %s ", path_to_vast_string, lightcurvefilename );
   // fork before system() so the parent process is not blocked
   if ( 0 == fork() ) {
    if ( 0 != system( pokaz_start ) ) {
     fprintf( stderr, "ERROR in %s \nGoing back to the lightcurve viewer.\n", pokaz_start );
    }
    exit( EXIT_SUCCESS );
   } else {
    sleep( 1 );
    waitpid( -1, &status, WNOHANG );
   }
   change_limits_trigger= 1;
  }
  if ( start_pokaz_script == 3 ) {
   start_pokaz_script= 0; // don't do it again unless 'C' will be pressed again
   // path_to_vast_string always ends with '/'
   sprintf( pokaz_start, "%slib/test/experimental_web_classifier.sh %s ", path_to_vast_string, lightcurvefilename );
   // fork before system() so the parent process is not blocked
   if ( 0 == fork() ) {
    if ( 0 != system( pokaz_start ) ) {
     fprintf( stderr, "ERROR in %s", pokaz_start );
    }
    exit( EXIT_SUCCESS );
   } else {
    sleep( 1 );
    waitpid( -1, &status, WNOHANG );
   }
   change_limits_trigger= 1;
  }

  if ( curC == 'H' || curC == 'h' || curC == 'I' || curC == 'i' )
   print_help(); // print help message

  /*
      Test if we want to set jump_instead_of_break ?
      That will fix A=0.0 in all linear trend fits.
  */
  if ( curC == '0' ) {
   if ( jump_instead_of_break == 1 )
    jump_instead_of_break= 0;
   else
    jump_instead_of_break= 1;
  }

  /*
      Set break: a discontinuity on a lightcurve. If linear trend fitting will be used,
      lightcurve on different sides of the brek will be fitted separately.
   */
  if ( curC == 'B' || curC == 'b' ) {
   cpgsci( 6 );
   cpgband( 6, 0, curX, curY, &curX2, &curY2, &curC );
   breaks[n_breaks]= curX2;
   n_breaks++;
   curC= ' ';
   plot_linear_trend_switch= 1;
  }

  /*
      Minimum time determination
   */
  if ( curC == 'K' || curC == 'k' || curC == 'M' || curC == 'm' ) {
   // Determine fit bounadireas
   //    n_breaks=0; // just to make sure there will be no interference with jump and brake handling routines
   cpgsci( 9 );
   cpgband( 6, 0, curX, curY, &curX2, &curY2, &curC );
   breaks[0]= curX2;

   // draw first line
   tmp_x[1]= tmp_x[0]= breaks[0];
   tmp_y[0]= new_Y1;
   tmp_y[1]= new_Y2;
   cpgline( 2, tmp_x, tmp_y );

   cpgband( 6, 0, curX, curY, &curX2, &curY2, &curC );
   breaks[1]= curX2;
   curC= 'K'; //

   // draw second line
   tmp_x[1]= tmp_x[0]= breaks[1];
   tmp_y[0]= new_Y1;
   tmp_y[1]= new_Y2;
   cpgline( 2, tmp_x, tmp_y );

   // Make sure that  breaks[1]>breaks[0]
   if ( breaks[1] < breaks[0] ) {
    tmp_x[1]= breaks[1];
    breaks[1]= breaks[0];
    breaks[0]= tmp_x[1];
   }

   // Copy the minimum lightcurve to fit_jd/fit_mag array;
   fit_jd= malloc( Nobs * sizeof( float ) );
   if ( fit_jd == NULL ) {
    fprintf( stderr, "ERROR5: Couldn't allocate memory for fit_jd(lc.c)\n" );
    exit( EXIT_FAILURE );
   };
   fit_mag= malloc( Nobs * sizeof( float ) );
   if ( fit_mag == NULL ) {
    fprintf( stderr, "ERROR5: Couldn't allocate memory for fit_mag(lc.c)\n" );
    exit( EXIT_FAILURE );
   };

   fit_n= 0;
   for ( i= 0; i < Nobs; i++ ) {
    if ( float_JD[i] > breaks[0] && float_JD[i] < breaks[1] ) {
     fit_jd[fit_n]= float_JD[i];
     fit_mag[fit_n]= mag[i];
     fit_n++;
    }
   }
   fprintf( stderr, "Starting the minimum determination routine...\n" );
   fprintf( stderr, "Minimum search boundaries:  %f  %f\n", breaks[0], breaks[1] ); // Print the minimum search boundaries
   fprintf( stderr, "Minimum duration (from the above boundaries): %f\n", breaks[1] - breaks[0] );
   minumum_kwee_van_woerden( fit_jd, fit_mag, fit_n, double_JD2float_JD ); // do actual fitting and print results to a terminal
   // clean-up
   free( fit_mag );
   free( fit_jd );
   fit_mag= NULL;
   fit_jd= NULL;
   fit_n= 0;

   n_breaks= 2; // to draw fitting boundaries again after the screen was wiped
   plot_minimum_fitting_boundaries= 1;
  }

  // Note that we want to draw errorbars
  if ( curC == 'E' || curC == 'e' ) {
   if ( draw_errorbars == 0 )
    draw_errorbars= 1;
   else
    draw_errorbars= 0;
  }

  if ( curC == 'S' || curC == 's' )
   xw_ps= 1; // save picture to .ps file

  if ( curC == 'N' || curC == 'n' )
   xw_ps= 2; // save picture to .png file

  if ( curC == 'U' || curC == 'u' ) { // start util/identify.sh
   // path_to_vast_string always ends with '/'
   //sprintf( strmusor, "%sutil/identify.sh %s", path_to_vast_string, lightcurvefilename );
   sprintf( strmusor, "%sutil/identify_noninteractive.sh %s", path_to_vast_string, lightcurvefilename );
   fprintf( stderr, "%s\n", strmusor );
   // fork before system() so the parent process is not blocked
   if ( 0 == fork() ) {
    if ( 0 != system( strmusor ) ) {
     fprintf( stderr, "ERROR in %s", strmusor );
    }
    exit( EXIT_SUCCESS );
   } else {
    waitpid( -1, &status, WNOHANG );
   }
  }

  if ( curC == 'F' || curC == 'f' ) { // start identify_justname.sh
   // path_to_vast_string always ends with '/'
   sprintf( strmusor, "%sutil/identify_justname.sh %s", path_to_vast_string, lightcurvefilename );
   fprintf( stderr, "%s\n", strmusor );
   // fork before system() so the parent process is not blocked
   if ( 0 == fork() ) {
    if ( 0 != system( strmusor ) ) {
     fprintf( stderr, "ERROR in %s\n", strmusor );
    } else {
     fprintf( stderr, "\nCOMPLETED %s\n", strmusor );
    }
    exit( EXIT_SUCCESS );
   } else {
    waitpid( -1, &status, WNOHANG );
   }
  }

  // Set default zoom
  if ( curC == 'D' || curC == 'd' ) {
   change_limits_trigger= 2;
  }

  /*
      Left click - if the lightcuve is in VaST format - open image corresponding to the closest data point.
   */
  if ( curC == 'A' || curC == 'a' ) {
   change_limits_trigger= 1;
   closest_num= find_closest( curX, curY, float_JD, mag, Nobs, new_X1, new_X2, new_Y1, new_Y2 );
   // set marker
   markX= float_JD[closest_num];
   markY= mag[closest_num];
   //    cpgsci(2);cpgpt1( markX, markY, 4);cpgsci(5);
   // print out the point info
   // fprintf( stderr, "%13.5lf  %.5lf %.5lf\n", JD[closest_num], mag[closest_num], mag_err[closest_num] );
   // Print the selected data point
   fprintf( stderr, "%13.5lf  %.5lf %.5lf  ", JD[closest_num], mag[closest_num], mag_err[closest_num] );
   //
   // Convert JD to calendar time
   UnixTime= ( JD[closest_num] - 2440587.5 ) * 86400.0;
   if ( UnixTime < 0.0 ) {
    UnixTime_time_t= (time_t)( UnixTime - 0.5 );
   } else {
    // UnixTime is double, so we add 0.5 for the proper type conversion
    UnixTime_time_t= (time_t)( UnixTime + 0.5 );
   }
   // Use thread-safe gmtime_r() instead of gmtime() if possible
   // will need to free( structureTIME ) below
#if defined( _POSIX_C_SOURCE ) || defined( _BSD_SOURCE ) || defined( _SVID_SOURCE )
   structureTIME= malloc( sizeof( struct tm ) );
   gmtime_r( &UnixTime_time_t, structureTIME );
#else
   structureTIME= gmtime( &UnixTime_time_t );
#endif
   // Warning! I'm loosing the last digit while convering!
   // fprintf( stderr, "%04d-%02d-%08.5lf\n", structureTIME->tm_year - 100 + 2000, structureTIME->tm_mon + 1, (double)structureTIME->tm_mday + (double)structureTIME->tm_hour / 24.0 + (double)structureTIME->tm_min / ( 24.0 * 60 ) + (double)structureTIME->tm_sec / ( 24.0 * 60 * 60 ) );
   fprintf( stderr, "%04d-%02d-%07.4lf\n", structureTIME->tm_year - 100 + 2000, structureTIME->tm_mon + 1, (double)structureTIME->tm_mday + (double)structureTIME->tm_hour / 24.0 + (double)structureTIME->tm_min / ( 24.0 * 60 ) + (double)structureTIME->tm_sec / ( 24.0 * 60 * 60 ) );
#if defined( _POSIX_C_SOURCE ) || defined( _BSD_SOURCE ) || defined( _SVID_SOURCE )
   free( structureTIME );
#endif
   //
   // start a FITS viewer
   if ( lightcurve_format == 0 ) {
    if ( NULL != filename[closest_num] ) {
     if ( 0 != fitsfile_read_check( filename[closest_num] ) ) {
      fprintf( stderr, "Cannot open FITS image %s\n", filename[closest_num] );
     } else {
      if ( use_ds9_instead_of_pgfv == 1 ) {
       // path_to_vast_string always ends with '/'
       sprintf( strmusor, "%sutil/draw_stars_with_ds9.sh %s %.6f %.6f %.1f %s >/dev/null", path_to_vast_string, filename[closest_num], X[closest_num], Y[closest_num], APER[closest_num], lightcurvefilename );
      } else {
       // %.6f for the case when the input coordinates are RA/Dec, not pixel coordinates
       // path_to_vast_string always ends with '/'
       sprintf( strmusor, "%spgfv -- %s %.6f %.6f %.1f", path_to_vast_string, filename[closest_num], X[closest_num], Y[closest_num], APER[closest_num] );
      }
      fprintf( stderr, " Starting FITS image viewer:\n%s\n", strmusor );
      // fork before system() so the parent process is not blocked
      if ( 0 == fork() ) {
       if ( 0 != system( strmusor ) ) {
        fprintf( stderr, "ERROR in %s", strmusor );
       }
       exit( EXIT_SUCCESS );
      } else {
       waitpid( -1, &status, WNOHANG );
      }
     } // if( 0 != fitsfile_read_check( filename[closest_num] ) ){
    }
    // else {
    // fprintf(stderr, "Oops! There is no information about the FITS image filename!\n");
    //}
   }
   // else {
   // fprintf(stderr, "Oops! The lightcurve is not in VaST format! No information about image corresponding to this data point is available!\n");
   //}
  }

  // If we were plotting to a file instead of X window...
  if ( 0 == strcmp( PGPLOT_CONTROL, "/CPS" ) || 0 == strcmp( PGPLOT_CONTROL, "/PNG" ) ) {
   cpgclos();

   //
   // fprintf(stderr,"\n\n\nDEBUG #%s# %d\n\n\n",lightcurvefilename,get_star_number_from_name(star_name,lightcurvefilename));

   if ( 0 != get_star_number_from_name( star_name, lightcurvefilename ) ) {
    if ( xw_ps == 1 ) {
     strncpy( oldpath, "pgplot.ps", 10 );
     sprintf( newpath, "%s.ps", star_name );
    }
    if ( xw_ps == 2 ) {
     strncpy( oldpath, "pgplot.png", 11 );
     sprintf( newpath, "%s.png", star_name );
    }
    rename( oldpath, newpath );
   } else {
    strncpy( star_name, "pgplot", 7 );
   }

   if ( xw_ps == 1 ) {
    fprintf( stderr, "Lightcurve plot should be saved to \x1B[34;47m %s.ps \x1B[33;00m \n", star_name );
   }
   if ( xw_ps == 2 ) {
    fprintf( stderr, "Lightcurve plot should be saved to \x1B[34;47m %s.png \x1B[33;00m \n", star_name );
   }

   xw_ps= -1;
   curC= ' ';

   if ( exit_after_plot == 1 ) {
    break;
   }
  }

 } while ( curC != 'X' && curC != 'x' );

 // Free memory
 free( float_JD );
 free( JD );
 free( mag );
 free( mag_err );

 for ( i= 0; i < number_of_lines_in_lc_file_for_malloc; i++ )
  free( filename[i] );
 free( filename );
 free( X );
 free( Y );
 free( APER );

 // we laready did cpgclos() above if we were plotting to a file
 if ( 0 != strcmp( PGPLOT_CONTROL, "/CPS" ) && 0 != strcmp( PGPLOT_CONTROL, "/PNG" ) ) {
  cpgclos();
 }

 return 0;
}
