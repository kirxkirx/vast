#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <getopt.h>
#include <sys/stat.h> /* for stat(), also requires #include <sys/types.h> and #include <unistd.h> */
#include <sys/types.h>
#include <unistd.h>

#include <sys/wait.h>
#include <sys/time.h>
#include <sys/resource.h>

#include <time.h> // for nanosleep()

#include "cpgplot.h"
#include "setenv_local_pgplot.h"
#include "vast_limits.h"
#include "detailed_error_messages.h"
#include "index_vs_mag.h" // for get_index_by_column_number()

#include "fitsfile_read_check.h"

/*

From http://www.cse.iitb.ac.in/~cs101/2003.2/resources/notesPgplot/chapter5.html

Table 5.1. Default Color Representation

Color
Index    Color                  (H, L, S)        (R, G, B)

 0   Black (background)       0, 0.00, 0.00   0.00, 0.00, 0.00
 1   White (default)          0, 1.00, 0.00   1.00, 1.00, 1.00
 2   Red                    120, 0.50, 1.00   1.00, 0.00, 0.00
 3   Green                  240, 0.50, 1.00   0.00, 1.00, 0.00
 4   Blue                     0, 0.50, 1.00   0.00, 0.00, 1.00
 5   Cyan (Green + Blue)    300, 0.50, 1.00   0.00, 1.00, 1.00
 6   Magenta (Red + Blue)    60, 0.50, 1.00   1.00, 0.00, 1.00
 7   Yellow  (Red + Green)  180, 0.50, 1.00   1.00, 1.00, 0.00
 8   Red + Yellow (Orange)  150, 0.50, 1.00   1.00, 0.50, 0.00
 9   Green + Yellow         210, 0.50, 1.00   0.50, 1.00, 0.00
10   Green + Cyan           270, 0.50, 1.00   0.00, 1.00, 0.50
11   Blue + Cyan            330, 0.50, 1.00   0.00, 0.50, 1.00
12   Blue + Magenta          30, 0.50, 1.00   0.50, 0.00, 1.00
13   Red + Magenta           90, 0.50, 1.00   1.00, 0.00, 0.50
14   Dark Gray                0, 0.33, 0.00   0.33, 0.33, 0.33
15   Light Gray   	      0, 0.66, 0.00   0.66, 0.66, 0.66
16--255	Undefined                    	                      

*/

float myfmin(float x, float y) {
 if( x > y )
  return y;
 else
  return x;
}

float myfmax(float x, float y) {
 if( x > y )
  return x;
 else
  return y;
}

//void call_scripts(int period_search_switch) {
void call_scripts() {
 char cmd[512];
 strcpy(cmd, "util/nopgplot.sh");
// if( period_search_switch == 1 )
//  strcat(cmd, " -t"); // DEPRICATED!!!
 if( 0 != system(cmd) ) {
  fprintf(stderr, "ERROR running %s\n", cmd);
 }
 fprintf(stderr, "NOTE: to create the lightcurve statistics file 'vast_lightcurve_statistics.log' non-interactively you may run 'util/nopgplot.sh'\n\n");
 return;
}

int find_closest(float *x, float *y, float *X, float *Y, int N, float new_X1, float new_X2, float new_Y1, float new_Y2) {
 float y_to_x_scaling_factor= fabsf(new_X2 - new_X1) / fabsf(new_Y2 - new_Y1);
 int i;
 float best_dist;
 float best_x, best_y;
 best_x= X[0];
 best_y= Y[0];
 int best_dist_num= 0;
 best_dist= ((*x) - X[0]) * ((*x) - X[0]) + ((*y) - Y[0]) * ((*y) - Y[0]) * y_to_x_scaling_factor * y_to_x_scaling_factor; //!!
 for( i= 1; i < N; i++ ) {
  if( ((*x) - X[i]) * ((*x) - X[i]) + ((*y) - Y[i]) * ((*y) - Y[i]) * y_to_x_scaling_factor * y_to_x_scaling_factor < best_dist ) {
   best_dist= ((*x) - X[i]) * ((*x) - X[i]) + ((*y) - Y[i]) * ((*y) - Y[i]) * y_to_x_scaling_factor * y_to_x_scaling_factor;
   best_x= X[i];
   best_y= Y[i];
   best_dist_num= i;
  }
 }
 (*x)= best_x;
 (*y)= best_y;
 return best_dist_num;
}

void save_viewed_star_number(char *viewed_star_outfilename) {
 FILE *f;
 f= fopen("vast_viewed_lightcurves.log", "a");
 if( f == NULL ) {
  fprintf(stderr, "WARNING: cannot append to vast_viewed_lightcurves.log\n");
  return;
 }
 fprintf(f, "%s\n", viewed_star_outfilename);
 fclose(f);
 return;
}

void load_viewed_star_numbers(char *mark_as_viewed, int Max_number_of_lines, char **outfilename) {
 FILE *f;
 int i;
 f= fopen("vast_viewed_lightcurves.log", "r");
 char star[OUTFILENAME_LENGTH];
 if( f == NULL )
  return;
 while( 0 < fscanf(f, "%s", star) ) {
  for( i= 0; i < Max_number_of_lines; i++ ) {
   if( mark_as_viewed[i] == 1 )
    continue;
   if( 0 == strncmp(star, outfilename[i], OUTFILENAME_LENGTH) ) {
    mark_as_viewed[i]= 1;
    break;
   }
  }
 }
 fclose(f);
 return;
}

void remove_vast_viewed_lightcurves_log() {
 struct stat sb; // structure returned by stat() system call
 // Check if the file exist
 if( 0 != stat("vast_viewed_lightcurves.log", &sb) ) {
  // vast_viewed_lightcurves.log does not exist, that's fine - nothing to delete
  return;
 }
 // Check if it's a regular file
 //if( (sb.st_mode & S_IFMT) != S_IFREG){fprintf(stderr,"WARNING from remove_vast_viewed_lightcurves_log(): vast_viewed_lightcurves.log is not a regular file! This is not suppose to happen...\n");return;}
 // The above doesn't work, see
 // https://stackoverflow.com/questions/28547271/s-ifmt-and-s-ifreg-undefined-with-std-c11-or-std-gnu11
 // instead of (sb.st_mode & S_IFMT) == S_IFREG, just write S_ISREG(sb.st_mode)
 if( !S_ISREG(sb.st_mode) ) {
  fprintf(stderr, "WARNING from remove_vast_viewed_lightcurves_log(): vast_viewed_lightcurves.log is not a regular file! This is not suppose to happen...\n");
  return;
 }
 // Remove it
 fprintf(stderr, "Removing the list of earlier-viewed lightcurves 'vast_viewed_lightcurves.log'\n");
 unlink("vast_viewed_lightcurves.log");
 return;
}

void load_candidate_star_numbers(char *mark_as_candidate, int Max_number_of_lines, char **outfilename, char *input_filename) {
 FILE *f;
 int i;
 // int candidate_found;
 char full_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 char string_with_star_id_and_info[2048];
 char star[OUTFILENAME_LENGTH];
 // some basic checks of the input
 if( input_filename == NULL ) {
  fprintf(stderr, "ERROR in load_candidate_star_numbers(): input_filename==NULL\n");
  exit(1);
 }
 if( 1 > strlen(input_filename) ) {
  fprintf(stderr, "ERROR in load_candidate_star_numbers(): 1<strlen(input_filename)\n");
  exit(1);
 }
 f= fopen(input_filename, "r");
 if( f == NULL )
  return; // it is fine, just exit quietly
 fprintf(stderr, "Loading star list from %s\n", input_filename);
 string_with_star_id_and_info[0]= '\0';
 while( NULL != fgets(full_string, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, f) ) {
  sscanf(full_string, "%s %[^\t\n]", star, string_with_star_id_and_info);
  //fprintf(stderr,"Loading %s (%s) - ",star,string_with_star_id_and_info);
  //candidate_found=0;
  for( i= 0; i < Max_number_of_lines; i++ ) {
   if( mark_as_candidate[i] == 1 )
    continue;
   if( 0 == strncmp(star, outfilename[i], OUTFILENAME_LENGTH) ) {
    mark_as_candidate[i]= 1;
    break;
   }
  }
  //if( candidate_found==1 ){
  // fprintf(stderr,"FOUND\n");
  //}
  //else{
  // fprintf(stderr,"NOT FOUND\n");
  //}
  string_with_star_id_and_info[0]= '\0';
 }
 fclose(f);
 return;
}

void check_if_star_is_in_candidates_list(char *outfilename) {
 FILE *f;
 char star[OUTFILENAME_LENGTH];
 char string_with_star_id_and_info[2048];
 f= fopen("vast_autocandidates.log", "r");
 if( f == NULL )
  return;
 while( 0 < fscanf(f, "%s %[^\t\n]", star, string_with_star_id_and_info) ) {
  if( 0 == strncmp(star, outfilename, OUTFILENAME_LENGTH) ) {
   fprintf(stderr, "Star found in vast_autocandidates.log\n %s %s\n", star, string_with_star_id_and_info);
   break;
  }
 }
 fclose(f);
 return;
}

int main(int argc, char **argv) {
 char COMMAND_STR[512];
 FILE *lightcurve_statistics_file;
 float *mag= NULL;
 char **outfilename= NULL;
 char tmpfilename[OUTFILENAME_LENGTH];
 int Nstar= 0;
 int i;
 //
 float *modified_sigma= NULL;
 char *mark_as_viewed= NULL;
 char *mark_as_candidate= NULL;
 char *mark_as_known_variable= NULL; // new
 char *mark_as_last_viewed= NULL;
 float *plot_x;
 float *plot_y;

 float maxM, minM;

 /* PGPLOT vars */
 float curX= 0.0;
 float curY= 0.0;
 char curC= 'R';
 /* for zoom */
 float draw_X_min, draw_X_max, draw_X_min_current, draw_X_max_current;
 float draw_Y_min, draw_Y_max, draw_Y_min_current, draw_Y_max_current;
 float curX2= 0.0;
 float curY2= 0.0;
 float *mag_viewed= NULL;
 float *sigma_viewed= NULL;

 int status= 0; // for wait()

 /* header string */
 char header_str[512];

 /* Variables needed to draw the curve deviding stars with high (spspected 
    variability candidates) and low sigma. */
 float *high_sigma_curve_mag;
 float *high_sigma_curve_limit; // actual cut-off level at a given magnitude
 int sigma_curve_N_points= 0;
 FILE *vast_sigma_selection_curve_file;

 /* Mark the last inspected star */
 float markX= 0.0;
 float markY= 0.0;

 /* Closest star */
 int closest_star_number;
 float closest_star_x;
 float closest_star_y;

 /* Protection against strange free() crushes */
 //setenv("MALLOC_CHECK_", "0", 1);

 int use_old_files= 0;
 //int t_option_set= 0;
 int use_ds9_instead_of_pgfv= 0;

 int display_mode= 1; // 1 - mag-sigma plot
                      // 2 - mag-weighted_sigma plot
                      // TBA

 char instrumental_magnitude_or_magnitude_string[256];

 char buf[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG];

 ///// New index infrastructure /////
 int j;                // counter
 double dvarindex_tmp; // temporary storage for double-type var. index
 double tmpmag, tmpsigma, tmpdouble;
 float **fvarindex; //[MAX_NUMBER_OF_INDEXES_TO_STORE]; // array of index arrays
 float fvarindex_max[MAX_NUMBER_OF_INDEXES_TO_STORE];
 float fvarindex_min[MAX_NUMBER_OF_INDEXES_TO_STORE];
 char string_to_parse[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG];
 char substring_to_parse[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG];

 // for nanosleep()
 struct timespec requested_time;
 struct timespec remaining;
 requested_time.tv_sec= 0;
 requested_time.tv_nsec= 100000000;

 /* Options for getopt() */
 //extern int opterr; // if you use this, you should just include <unistd.h>, not declare opterr manually
 opterr= 0; // There's variable opterr in getopt.h which will avoid printing the the error to stderr if you set it to 0.
 int n;
 const char *const shortopt= "t9";
 const struct option longopt[]= {{"ds9", 0, NULL, '9'}, {"tsearch", 0, NULL, 't'}, {NULL, 0, NULL, 0}}; //NULL string must be in the end
 int nextopt;
 while( nextopt= getopt_long(argc, argv, shortopt, longopt, NULL), nextopt != -1 ) {
  switch( nextopt ) {
  case '9':
   use_ds9_instead_of_pgfv= 1;
   break;
//  case 't':
//   t_option_set= 1;
//   break;
//   // do we need break here???
  case '?':
   use_old_files= 1;
   //     fprintf(stderr,"Using the old vast_lightcurve_statistics.log and other log files.\n");
   break;
   // do we need break here???
  case -1:
   fprintf(stderr, "That's all with options\n");
   break;
  }
 }

 if( use_old_files == 0 ) {
  // allow for the OLD syntax
  /* if there are some more option - use old files */
  for( n= optind; n < argc; n++ ) {
   use_old_files= 1;
  }
 } else {
  // Try to see if we can actually at least open the main log file
  lightcurve_statistics_file= fopen("vast_lightcurve_statistics.log", "r");
  if( lightcurve_statistics_file == NULL ) {
   fprintf(stderr, "ERROR: Can't open file \"vast_lightcurve_statistics.log\"!\n");
   use_old_files= 0;
  }
  fclose(lightcurve_statistics_file);
 }

 if( use_old_files == 0 ) {
  fprintf(stderr, "Computing lightcurves statistics, this may take some time...\nThe results will be written to vast_lightcurve_statistics.log\n");
  call_scripts();
 } else {
  fprintf(stderr, "Using the old vast_lightcurve_statistics.log and other log files.\n");
 }

// moved to the inside of if() above
// // else - call external scripts to produce data files 
// if( t_option_set == 0 && use_old_files == 0 ) {
//  call_scripts(0); // Do not use period search 
// }
// if( t_option_set == 1 && use_old_files == 0 ) {
//  call_scripts(1); // Use period search 
// }

 // read vast_lightcurve_statistics.log file
 lightcurve_statistics_file= fopen("vast_lightcurve_statistics.log", "r");
 if( lightcurve_statistics_file == NULL ) {
  fprintf(stderr, "ERROR: Can't open file \"vast_lightcurve_statistics.log\"!\n");
  report_lightcurve_statistics_computation_problem();
  exit(1);
 }
 // count lines in file
 Nstar= 0;
 while( NULL != fgets(buf, MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG, lightcurve_statistics_file) )
  Nstar++;
 fseek(lightcurve_statistics_file, 0, SEEK_SET); // go back to the beginning of the file
 if( Nstar <= 0 ) {
  fprintf(stderr, "ERROR: Trying allocate zero or negative bytes amount\n");
 };
 // allocate memory for index array
 mag= malloc(Nstar * sizeof(float));
 if( mag == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for mag\n");
  exit(1);
 };
 mark_as_candidate= malloc(Nstar * sizeof(char));
 if( mark_as_candidate == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for mark_as_candidate\n");
  exit(1);
 };
 mark_as_known_variable= malloc(Nstar * sizeof(char));
 if( mark_as_known_variable == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for mark_as_known_variable\n");
  exit(1);
 };
 mark_as_viewed= malloc(Nstar * sizeof(char));
 if( mark_as_viewed == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for mark_as_viewed\n");
  exit(1);
 };
 mark_as_last_viewed= malloc(Nstar * sizeof(char));
 if( mark_as_last_viewed == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for mark_as_last_viewed\n");
  exit(1);
 };
 fvarindex= malloc(MAX_NUMBER_OF_INDEXES_TO_STORE * sizeof(float *));
 if( fvarindex == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for fvarindex\n");
  exit(1);
 };
 // Note here i cycles through indexes
 for( i= 0; i < MAX_NUMBER_OF_INDEXES_TO_STORE; i++ ) {
  fvarindex[i]= malloc(Nstar * sizeof(float));
  if( NULL == fvarindex[i] ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for fvarindex[i]\n");
   exit(1);
  }
  // just to make valgrind happy
  //memset(fvarindex[i], '\0', Nstar*sizeof(float) );
 }
 outfilename= malloc(Nstar * sizeof(char *));
 if( outfilename == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for outfilename\n");
  exit(1);
 };
 // Note here i cycles through stars
 for( i= 0; i < Nstar; i++ ) {
  // initialize
  mark_as_candidate[i]= 0;
  mark_as_known_variable[i]= 0;
  mark_as_viewed[i]= 0;
  mark_as_last_viewed[i]= 0;
  //
  outfilename[i]= malloc(OUTFILENAME_LENGTH * sizeof(char));
  if( outfilename[i] == NULL ) {
   fprintf(stderr, "ERROR: Couldn't allocate memory for outfilename[i]\n");
   exit(1);
  };
 }
 i= 0;
 while( NULL != fgets(string_to_parse, MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG, lightcurve_statistics_file) ) {
  string_to_parse[MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG - 1]= '\0'; // just in case
  if( 100 > strlen(string_to_parse) ) {
   fprintf(stderr, "ERROR parsing vast_lightcurve_statistics.log string: %s\n", string_to_parse);
   continue;
  }
  // reset the string to make valgrind happy
  memset(substring_to_parse, 0, MAX_STRING_LENGTH_IN_VAST_LIGHTCURVE_STATISTICS_LOG);
  //
  //if( 6 > sscanf(string_to_parse, "%lf %lf %lf %lf %s %[^\t\n]", &tmpmag, &tmpsigma, &tmpdouble, &tmpdouble, outfilename[i], substring_to_parse) ) {
  if( 6 > sscanf(string_to_parse, "%lf %lf %lf %lf %s %[^\t\n]", &tmpmag, &tmpsigma, &tmpdouble, &tmpdouble, tmpfilename, substring_to_parse) ) {
   fprintf(stderr, "ERROR parsing vast_lightcurve_statistics.log string: %s\n", string_to_parse);
   continue;
  }
  //
  tmpfilename[OUTFILENAME_LENGTH-1]= '\0';
  if( 0 != safely_encode_user_input_string(outfilename[i], tmpfilename, OUTFILENAME_LENGTH) ) {
   fprintf(stderr, "ERROR encoding filename %s\n", tmpfilename);
   continue;
  }
  //
  mag[i]= (float)tmpmag;
  fvarindex[0][i]= (float)tmpsigma;
  for( j= 1; j < MAX_NUMBER_OF_INDEXES_TO_STORE; j++ ) {
   //dvarindex_tmp=0.0; // just to make valgrind happy
   dvarindex_tmp= get_index_by_column_number(substring_to_parse, j);
#ifndef VAST_USE_BUILTIN_FUNCTIONS
   if( 0 == isnormal(dvarindex_tmp) )
    dvarindex_tmp= 0.0; // SET INDEX to 0.0 if it's undefined!!! Setting it to a funny extreme value will ruin the plots!
#endif
#ifdef VAST_USE_BUILTIN_FUNCTIONS
   // for whatever reason isnormal() does not link properly on FreeBSD here, using __builtin_isnormal() instead which links fine
   if( 0 == __builtin_isnormal(dvarindex_tmp) )
    dvarindex_tmp= 0.0; // SET INDEX to 0.0 if it's undefined!!! Setting it to a funny extreme value will run the plots!
#endif
   // Note the reverse ij order compared to the index[][] array in index_vs_mag.c
   fvarindex[j][i]= (float)dvarindex_tmp;
  }
  //fprintf(stderr,"TEST: %lf\n", get_index_by_column_number( substring_to_parse, 2) );
  i++;
 }
 fclose(lightcurve_statistics_file);

 //fprintf(stderr,"AGA %d\n",Nstar);

 mag_viewed= malloc(3 * Nstar * sizeof(float));
 if( mag_viewed == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for mag_viewed\n");
  exit(1);
 };
 sigma_viewed= malloc(3 * Nstar * sizeof(float));
 if( sigma_viewed == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for sigma_viewed\n");
  exit(1);
 };

 /*  Load the curve indicating stars with high (suspected 
     variability candidates) and low sigma from vast_sigma_selection_curve.log . */
 sigma_curve_N_points= 0;
 high_sigma_curve_mag= malloc(sizeof(float) * MAX_NUMBER_OF_STARS);
 if( high_sigma_curve_mag == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for high_sigma_curve_mag\n");
  exit(1);
 };
 high_sigma_curve_limit= malloc(sizeof(float) * MAX_NUMBER_OF_STARS);
 if( high_sigma_curve_limit == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for high_sigma_curve_limit\n");
  exit(1);
 };
 vast_sigma_selection_curve_file= fopen("vast_sigma_selection_curve.log", "r");
 if( vast_sigma_selection_curve_file != NULL ) {
  while( -1 < fscanf(vast_sigma_selection_curve_file, "%f %f", &high_sigma_curve_mag[sigma_curve_N_points], &high_sigma_curve_limit[sigma_curve_N_points]) ) {
   sigma_curve_N_points++;
  }
  fclose(vast_sigma_selection_curve_file);
 }

 ////////////////  Load markers  ////////////////
 // Previously viewed stars
 if( use_old_files == 1 ) {
  load_viewed_star_numbers(mark_as_viewed, Nstar, outfilename);
 } else {
  remove_vast_viewed_lightcurves_log(); // Remove the list of previously viewed stars (if there is one)
 }
 // Candidate variables
 load_candidate_star_numbers(mark_as_candidate, Nstar, outfilename, "vast_autocandidates.log");
 // Known variables
 load_candidate_star_numbers(mark_as_known_variable, Nstar, outfilename, "vast_list_of_previously_known_variables.log");
 ////////////////////////////////////////////////

 // find limits //
 maxM= minM= mag[0];
 for( j= 0; j < MAX_NUMBER_OF_INDEXES_TO_STORE; j++ ) {
  fvarindex_max[j]= fvarindex_min[j]= fvarindex[j][0];
 }

 // start with [1] since we use [0] as the default value
 for( i= 1; i < Nstar; i++ ) {

  if( mag[i] > maxM )
   maxM= mag[i];
  if( mag[i] < minM )
   minM= mag[i];

  for( j= 0; j < MAX_NUMBER_OF_INDEXES_TO_STORE; j++ ) {
   if( fvarindex[j][i] < fvarindex_min[j] )
    fvarindex_min[j]= fvarindex[j][i];
   if( fvarindex[j][i] > fvarindex_max[j] )
    fvarindex_max[j]= fvarindex[j][i];
  }
 }

 if( minM > 0.0 && maxM > 0.0 )
  strncpy(instrumental_magnitude_or_magnitude_string, "Magnitude", 256);
 else
  strncpy(instrumental_magnitude_or_magnitude_string, "Instrumental magnitude", 256);
 instrumental_magnitude_or_magnitude_string[255]= '\0'; // just in case

 // This should be sufficeint to setup a mag-sigma plot
 draw_X_min= minM - (maxM - minM) / 10;
 draw_X_max= maxM + (maxM - minM) / 10;
 draw_X_min_current= draw_X_min;
 draw_X_max_current= draw_X_max;

 draw_Y_min= fvarindex_min[0] - (fvarindex_max[0] - fvarindex_min[0]) / 10;
 draw_Y_max= fvarindex_max[0] + (fvarindex_max[0] - fvarindex_min[0]) / 10;
 draw_Y_min_current= draw_Y_min;
 draw_Y_max_current= draw_Y_max;

 plot_x= mag;
 plot_y= fvarindex[0];
 ///////////////////////////////////////////////////////

 /* draw picture */
 setenv_localpgplot(argv[0]);
 //fprintf(stderr,"\nStarting PGPlot ");
 if( 1 != cpgbeg(0, "/XW", 1, 1) ) {
  fprintf(stderr, "ERROR starting PGPlot!\n");
  return EXIT_FAILURE;
 }
 cpgask(0); // turn OFF this silly " Type <RETURN> for next page:" request
 //fprintf(stderr,"- OK\n");
 fprintf(stderr, "\n  --*** HOW TO USE THE VARIABILITY INDEX PLOTTER ***--\n");
 fprintf(stderr, "\nClick on any star to see its lightcurve.\n");
 fprintf(stderr, "Press \033[0;36m'M'\033[00m and \033[0;36m'N'\033[00m to switch between the various variability indices.\nPress 'Z' and draw rectangle to zoom in.\nPress 'D', 'Z''Z' or click middle mouse button to return to the original zoom.\nPress 'X' two times or double right click to exit.\nHave fun! :)\n\n");

 do {

  cpgscr(0, 0.10, 0.31, 0.32); /* set default vast window background */
  cpgeras();
  cpgsvp(0.08, 0.95, 0.1, 0.92);
  cpgswin(draw_X_min_current, draw_X_max_current, draw_Y_min_current, draw_Y_max_current);
  cpgsci(0);
  cpgscr(0, 0.08, 0.08, 0.09); /* set background */
  if( draw_X_min_current != draw_X_max_current && draw_Y_min_current != draw_Y_max_current )
   cpgrect(draw_X_min_current, draw_X_max_current, draw_Y_min_current, draw_Y_max_current); /* draw background for plot */
  else
   cpgrect(draw_X_min, draw_X_max, draw_Y_min, draw_Y_max); /* draw background for plot */
  cpgsci(1);
  cpgbox("BCNST1", 0.0, 0, "BCNST1", 0.0, 0);

  // If we have magnitude as one axis
  // Comment this out for now because ALL plots have magnitude as X axis
  //if( display_mode==1 || display_mode==2 || display_mode==3 || display_mode==4 || display_mode==5 ){
  cpgsch(0.85); /* make this labels with smaller characters */
  cpgmtxt("B", 2.5, 0.0, 0.0, "(bright stars)");
  cpgmtxt("B", 2.5, 1.0, 1.0, "(faint stars)");
  //}

  cpgscf(1);
  cpgsch(1.1);                 /* make labels with larger characters */
  cpgscr(1, 0.62, 0.81, 0.38); /* set color of lables */
  sprintf(header_str, "Stars measured: %d", Nstar);
  if( display_mode == 1 )
   cpglab(instrumental_magnitude_or_magnitude_string, "Standard deviation", header_str);
  if( display_mode == 2 )
   cpglab(instrumental_magnitude_or_magnitude_string, "Weighted standard deviation", header_str);
  if( display_mode == 3 )
   cpglab(instrumental_magnitude_or_magnitude_string, "1.4826 * MAD", header_str);
  if( display_mode == 4 )
   cpglab(instrumental_magnitude_or_magnitude_string, "IQR / 1.3489", header_str);
  if( display_mode == 5 )
   cpglab(instrumental_magnitude_or_magnitude_string, "RoMS", header_str);
  if( display_mode == 6 )
   cpglab(instrumental_magnitude_or_magnitude_string, "Stetson's J index", header_str);
  if( display_mode == 7 )
   cpglab(instrumental_magnitude_or_magnitude_string, "Stetson's L index", header_str);
  if( display_mode == 8 )
   cpglab(instrumental_magnitude_or_magnitude_string, "S_B", header_str);
  if( display_mode == 9 )
   cpglab(instrumental_magnitude_or_magnitude_string, "1/\\gy", header_str);

  cpgscr(1, 1.0, 1.0, 1.0);
  cpgsch(1.0);
  cpgsci(1);
  cpgpt(Nstar, plot_x, plot_y, 18);

  // Mark candidate variable stars
  for( i= 0; i < Nstar; i++ ) {
   cpgsci(5); // Cyan
   if( mark_as_candidate[i] == 1 ) {
    cpgpt1(plot_x[i], plot_y[i], 18);
   }
  }

  // Mark known variable stars
  for( i= 0; i < Nstar; i++ ) {
   //cpgsci( 3 ); // green which is low contrast
   cpgsci(8); // orange
   if( mark_as_known_variable[i] == 1 ) {
    cpgpt1(plot_x[i], plot_y[i], 23);
   }
  }

  // Mark previously viewed stars
  for( i= 0; i < Nstar; i++ ) {
   cpgsci(3); // Green
   if( mark_as_viewed[i] == 1 ) {
    cpgpt1(plot_x[i], plot_y[i], 18);
   }
  }

  if( display_mode == 1 ) {
   // Draw the curve dividing stars with high (suspected variability candidates) and low sigma.
   if( sigma_curve_N_points > 0 ) {
    cpgsci(6); // Magenta (Red + Blue)
    cpgsls(4); // dotted line
    cpgline(sigma_curve_N_points, high_sigma_curve_mag, high_sigma_curve_limit);
    cpgsci(5); // set color index back to draw thouse nice blue rectangles %)
    cpgsls(1); // full line
   }
  }

  // Mark the previous viewed star
  for( i= 0; i < Nstar; i++ ) {
   if( mark_as_last_viewed[i] == 1 ) {
    markX= plot_x[i];
    markY= plot_y[i];
    cpgsci(2);
    cpgpt1(markX, markY, 4);
    cpgsci(5);
   }
  }

  cpgcurs(&curX, &curY, &curC);
  if( curC == 'X' || curC == 'x' ) {
   fprintf(stderr, "\nAre you sure you want to exit?\nIf yes, please click the right mouse button again (or press 'X')!\nOtherwise, press any key.\n");
   cpgcurs(&curX, &curY, &curC);
   if( curC == 'X' || curC == 'x' )
    break;
  }

  // Check if the click is outside the plot
  // (we'll just redraw the plot if it is)
  if( curC == 'A' || curC == 'a' ) {
   if( curX < draw_X_min_current || curX > draw_X_max_current || curY < draw_Y_min_current || curY > draw_Y_max_current ) {
    curC= 'R';
   }
  }

  if( curC == 'A' || curC == 'a' ) {
   // find closest star to the cursor position
   closest_star_x= curX;
   closest_star_y= curY;
   closest_star_number= find_closest(&closest_star_x, &closest_star_y, plot_x, plot_y, Nstar, draw_X_min_current, draw_X_max_current, draw_Y_min_current, draw_Y_max_current);
   // remember click position
   markX= closest_star_x;
   markY= closest_star_y;
   save_viewed_star_number(outfilename[closest_star_number]);
   for( i= 0; i < Nstar; i++ )
    mark_as_last_viewed[i]= 0;
   mark_as_last_viewed[closest_star_number]= 1;
   mark_as_viewed[closest_star_number]= 1;
   check_if_star_is_in_candidates_list(outfilename[closest_star_number]);
   if( use_ds9_instead_of_pgfv == 1 ) {
    sprintf(COMMAND_STR, "./lc --ds9 %s\n", outfilename[closest_star_number]);
   } else {
    sprintf(COMMAND_STR, "./lc %s\n", outfilename[closest_star_number]);
   }
   fprintf(stderr, "%s", COMMAND_STR);
   // fork before system() so the parent process is not blocked
   if( 0 == fork() ) {
    nanosleep(&requested_time, &remaining);
    if( 0 != system(COMMAND_STR) ) {
     fprintf(stderr, "ERROR running %s\n", COMMAND_STR);
    }
    exit(0);
   } else {
    waitpid(-1, &status, WNOHANG);
   }
  }

  // Change display mode
  if( curC == 'N' || curC == 'n' ) {
   display_mode--;
   display_mode--;
   if( display_mode < 0 )
    display_mode= 8;
   curC= 'M';
  }

  // Change display mode
  if( curC == 'M' || curC == 'm' ) {
   display_mode++;
   if( display_mode > 9 )
    display_mode= 1;

   if( display_mode == 1 ) {
    // This should be sufficeint to setup a mag-sigma plot
    draw_X_min= minM - (maxM - minM) / 10;
    draw_X_max= maxM + (maxM - minM) / 10;
    draw_X_min_current= draw_X_min;
    draw_X_max_current= draw_X_max;

    //draw_Y_min=minSIGMA-(maxSIGMA-minSIGMA)/10;
    //draw_Y_max=maxSIGMA+(maxSIGMA-minSIGMA)/10;
    draw_Y_min= fvarindex_min[0] - (fvarindex_max[0] - fvarindex_min[0]) / 10;
    draw_Y_max= fvarindex_max[0] + (fvarindex_max[0] - fvarindex_min[0]) / 10;
    draw_Y_min_current= draw_Y_min;
    draw_Y_max_current= draw_Y_max;

    fprintf(stderr, "\n   PLOT DESCRIPTION:\n%s vs. Standard deviation computed over clipped lightcurves.\nThis is the plot displayed by previous versions of VaST.\n\n", instrumental_magnitude_or_magnitude_string);

    //plot_x=mag;plot_y=sigma; // display_mode==1
    plot_x= mag;
    plot_y= fvarindex[0]; // display_mode==1
    ///////////////////////////////////////////////////////
   }
   if( display_mode == 2 ) {
    // This should be sufficeint to setup a mag-modified_sigma plot
    draw_X_min= minM - (maxM - minM) / 10;
    draw_X_max= maxM + (maxM - minM) / 10;
    draw_X_min_current= draw_X_min;
    draw_X_max_current= draw_X_max;

    draw_Y_min= fvarindex_min[1] - (fvarindex_max[1] - fvarindex_min[1]) / 10;
    draw_Y_max= fvarindex_max[1] + (fvarindex_max[1] - fvarindex_min[1]) / 10;
    draw_Y_min_current= draw_Y_min;
    draw_Y_max_current= draw_Y_max;

    fprintf(stderr, "\n   PLOT DESCRIPTION:\n%s vs. Weighted standard deviation computed over non-clipped lightcurves.\n\n", instrumental_magnitude_or_magnitude_string);

    plot_x= mag;
    plot_y= fvarindex[1];
    ///////////////////////////////////////////////////////
   }
   if( display_mode == 3 ) {
    // mag-MAD plot
    draw_X_min= minM - (maxM - minM) / 10;
    draw_X_max= maxM + (maxM - minM) / 10;
    draw_X_min_current= draw_X_min;
    draw_X_max_current= draw_X_max;

    draw_Y_min= fvarindex_min[14 - 5] - (fvarindex_max[14 - 5] - fvarindex_min[14 - 5]) / 10;
    draw_Y_max= fvarindex_max[14 - 5] + (fvarindex_max[14 - 5] - fvarindex_min[14 - 5]) / 10;
    draw_Y_min_current= draw_Y_min;
    draw_Y_max_current= draw_Y_max;

    fprintf(stderr, "\n   PLOT DESCRIPTION:\n%s vs. Median absolute deviation (MAD) computed over non-clipped lightcurves.\nMAD is scaled by 1.4826 so it can be easily compared to Standard deviation.\nSee https://en.wikipedia.org/wiki/Median_absolute_deviation\n\n", instrumental_magnitude_or_magnitude_string);

    plot_x= mag;
    plot_y= fvarindex[14 - 5];
    ///////////////////////////////////////////////////////
   }
   if( display_mode == 4 ) {
    // mag-IQR plot
    draw_X_min= minM - (maxM - minM) / 10;
    draw_X_max= maxM + (maxM - minM) / 10;
    draw_X_min_current= draw_X_min;
    draw_X_max_current= draw_X_max;

    draw_Y_min= fvarindex_min[30 - 5] - (fvarindex_max[30 - 5] - fvarindex_min[30 - 5]) / 10;
    draw_Y_max= fvarindex_max[30 - 5] + (fvarindex_max[30 - 5] - fvarindex_min[30 - 5]) / 10;

    draw_Y_min_current= draw_Y_min;
    draw_Y_max_current= draw_Y_max;

    fprintf(stderr, "\n   PLOT DESCRIPTION:\n%s vs. Interquartile range (IQR) computed over non-clipped lightcurves.\nThe IQR is devided by 1.349 so it can be easily compared to Standard deviation.\nSee https://en.wikipedia.org/wiki/Interquartile_range\n\n", instrumental_magnitude_or_magnitude_string);

    plot_x= mag;
    plot_y= fvarindex[30 - 5];
    ///////////////////////////////////////////////////////
   }
   if( display_mode == 5 ) {
    // mag-RoMS plot
    draw_X_min= minM - (maxM - minM) / 10;
    draw_X_max= maxM + (maxM - minM) / 10;
    draw_X_min_current= draw_X_min;
    draw_X_max_current= draw_X_max;

    draw_Y_min= fvarindex_min[16 - 5] - (fvarindex_max[16 - 5] - fvarindex_min[16 - 5]) / 10;
    draw_Y_max= fvarindex_max[16 - 5] + (fvarindex_max[16 - 5] - fvarindex_min[16 - 5]) / 10;
    draw_Y_min_current= draw_Y_min;
    draw_Y_max_current= draw_Y_max;

    fprintf(stderr, "\n   PLOT DESCRIPTION:\n%s vs. Robust median statistic (RoMS) computed over non-clipped lightcurves.\nSee http://adsabs.harvard.edu/abs/2007AJ....134.2067R\n\n", instrumental_magnitude_or_magnitude_string);

    plot_x= mag;
    plot_y= fvarindex[16 - 5];
    ///////////////////////////////////////////////////////
   }
   if( display_mode == 6 ) {
    // mag-J_time plot
    draw_X_min= minM - (maxM - minM) / 10;
    draw_X_max= maxM + (maxM - minM) / 10;
    draw_X_min_current= draw_X_min;
    draw_X_max_current= draw_X_max;

    draw_Y_min= fvarindex_min[22 - 5] - (fvarindex_max[22 - 5] - fvarindex_min[22 - 5]) / 10;
    draw_Y_max= fvarindex_max[22 - 5] + (fvarindex_max[22 - 5] - fvarindex_min[22 - 5]) / 10;
    draw_Y_min_current= draw_Y_min;
    draw_Y_max_current= draw_Y_max;

    fprintf(stderr, "\n   PLOT DESCRIPTION:\n%s vs. Stetson's J variability index computed over non-clipped lightcurves.\nSee http://adsabs.harvard.edu/abs/1996PASP..108..851S\nTime-based weighting scheme is applied as suggested by http://adsabs.harvard.edu/abs/2012AJ....143..140F\n\n", instrumental_magnitude_or_magnitude_string);

    plot_x= mag;
    plot_y= fvarindex[22 - 5];
    ///////////////////////////////////////////////////////
   }
   if( display_mode == 7 ) {
    // mag-L_time plot
    draw_X_min= minM - (maxM - minM) / 10;
    draw_X_max= maxM + (maxM - minM) / 10;
    draw_X_min_current= draw_X_min;
    draw_X_max_current= draw_X_max;

    draw_Y_min= fvarindex_min[23 - 5] - (fvarindex_max[23 - 5] - fvarindex_min[23 - 5]) / 10;
    draw_Y_max= fvarindex_max[23 - 5] + (fvarindex_max[23 - 5] - fvarindex_min[23 - 5]) / 10;
    draw_Y_min_current= draw_Y_min;
    draw_Y_max_current= draw_Y_max;

    fprintf(stderr, "\n   PLOT DESCRIPTION:\n%s vs. Stetson's L variability index computed over non-clipped lightcurves.\nSee http://adsabs.harvard.edu/abs/1996PASP..108..851S\nTime-based weighting scheme is applied as suggested by http://adsabs.harvard.edu/abs/2012AJ....143..140F\n\n", instrumental_magnitude_or_magnitude_string);

    plot_x= mag;
    plot_y= fvarindex[23 - 5];
    ///////////////////////////////////////////////////////
   }
   if( display_mode == 8 ) {
    // mag-SB plot
    draw_X_min= minM - (maxM - minM) / 10;
    draw_X_max= maxM + (maxM - minM) / 10;
    draw_X_min_current= draw_X_min;
    draw_X_max_current= draw_X_max;

    draw_Y_min= fvarindex_min[28 - 5] - (fvarindex_max[28 - 5] - fvarindex_min[28 - 5]) / 10;
    draw_Y_max= fvarindex_max[28 - 5] + (fvarindex_max[28 - 5] - fvarindex_min[28 - 5]) / 10;

    draw_Y_min_current= draw_Y_min;
    draw_Y_max_current= draw_Y_max;

    fprintf(stderr, "\n   PLOT DESCRIPTION:\n%s vs. S_B variability detection statistic computed over non-clipped lightcurves.\nSee http://adsabs.harvard.edu/abs/2013A&A...556A..20F\n\n", instrumental_magnitude_or_magnitude_string);

    plot_x= mag;
    plot_y= fvarindex[28 - 5];
    ///////////////////////////////////////////////////////
   }
   if( display_mode == 9 ) {
    // mag-1/eta plot
    draw_X_min= minM - (maxM - minM) / 10;
    draw_X_max= maxM + (maxM - minM) / 10;
    draw_X_min_current= draw_X_min;
    draw_X_max_current= draw_X_max;

    draw_Y_min= fvarindex_min[26 - 5] - (fvarindex_max[26 - 5] - fvarindex_min[26 - 5]) / 10;
    draw_Y_max= fvarindex_max[26 - 5] + (fvarindex_max[26 - 5] - fvarindex_min[26 - 5]) / 10;

    draw_Y_min_current= draw_Y_min;
    draw_Y_max_current= draw_Y_max;

    fprintf(stderr, "\n   PLOT DESCRIPTION:\n%s vs. 1/eta variability detection statistic computed over non-clipped lightcurves.\nSee https://projecteuclid.org/euclid.aoms/1177731677\n\n", instrumental_magnitude_or_magnitude_string);

    plot_x= mag;
    plot_y= fvarindex[26 - 5];
    ///////////////////////////////////////////////////////
   }

   curC= 'D';
  } // if( curC=='M' || curC=='m' ){

  if( curC == 'z' || curC == 'Z' ) {
   cpgband(2, 0, curX, curY, &curX2, &curY2, &curC);
   draw_X_min_current= myfmin(curX, curX2);
   draw_X_max_current= myfmax(curX, curX2);
   draw_Y_min_current= myfmin(curY, curY2);
   draw_Y_max_current= myfmax(curY, curY2);

   if( curC == 'Z' || curC == 'z' )
    curC= 'D';
   else
    curC= 'R';
  }
  if( curC == 'D' || curC == 'd' ) {
   draw_X_min_current= draw_X_min;
   draw_X_max_current= draw_X_max;
   draw_Y_min_current= draw_Y_min;
   draw_Y_max_current= draw_Y_max;
  }

 } while( curC != 'X' && curC != 'x' );

 for( i= 0; i < MAX_NUMBER_OF_INDEXES_TO_STORE; i++ ) {
  free(fvarindex[i]);
 }
 free(fvarindex);

 for( i= 0; i < Nstar; i++ ) {
  free(outfilename[i]);
 }
 free(outfilename);

 free(mag_viewed);
 free(sigma_viewed);

 free(modified_sigma);
 free(mark_as_viewed);
 free(mark_as_last_viewed);
 free(mark_as_candidate);
 free(mark_as_known_variable);
 free(mag); // was missing

 free(high_sigma_curve_mag);
 free(high_sigma_curve_limit);

 cpgclos();

 return 0;
}
