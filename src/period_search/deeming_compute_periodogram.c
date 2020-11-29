#ifdef VAST_USE_SINCOS
#define _GNU_SOURCE // for sincos()
#endif

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include <libgen.h> // for basename()

#include <string.h>
#include <sys/types.h>
#include <unistd.h>
#include <sys/wait.h>

#include <gsl/gsl_sort.h> // for gsl_sort2()
#include <gsl/gsl_rng.h>
#include <gsl/gsl_randist.h>

#include <sys/time.h> // for gettimeofday()

// Location of the include files changes if this is a web_lk source, not VaST
#ifdef VAST_WEB_LK
#include "vast_limits.h"
#include "lightcurve_io.h"
#else
#include "../vast_limits.h"
#include "../lightcurve_io.h"
#endif

#define TWOPI 2.0 * M_PI

void get_min_max(double *x, int N, double *min, double *max) {
 int i;
 (*min)= (*max)= x[0];
 for( i= 1; i < N; i++ ) {
  if( x[i] < (*min) )
   (*min)= x[i];
  if( x[i] > (*max) )
   (*max)= x[i];
 }
 return;
}

unsigned long int random_seed() {
 unsigned int seed;
 struct timeval tv;
 FILE *devrandom;

 if( (devrandom= fopen("/dev/random", "r")) == NULL ) {
  gettimeofday(&tv, 0);
  seed= tv.tv_sec + tv.tv_usec;
  fprintf(stderr, "Got seed %u from gettimeofday()\n", seed);
 } else {
  if( 0 != fread(&seed, sizeof(seed), 1, devrandom) )
   fprintf(stderr, "Got seed %u from /dev/random\n", seed);
  else {
   fprintf(stderr, "ERROR setting the random seed!\n");
   exit(1);
  }
  fclose(devrandom);
 }

 return (seed);
}

void compute_DFT(double *jd, double *m, unsigned int N_obs, double f, double *DFT, double T_DFT) {
 unsigned int i;
 double ReF, ImF, C, S, angle, dN_obs;

 ReF= ImF= 0.0;
 //for(i=0;i<N_obs;i++){
 for( i= N_obs; i--; ) {
  angle= TWOPI * f * (jd[i] - jd[0]);
// not sure if we should bother subtracting jd[0], but I'm afraid of large numbers
#ifdef VAST_USE_SINCOS
  sincos(angle, &S, &C);
#else
  C= cos(angle);
  S= sin(angle);
#endif
  ReF+= m[i] * C;
  ImF+= m[i] * S;
 }

 dN_obs= (double)N_obs;
 // New normalization consistent with 2014MNRAS.445..437M
 // The multiplicative factor is a normalization, such that the integral
 // from f_i to f_f is equal to the variance contributed to the light curve
 // in this frequency range.
 (*DFT)= 2.0 * T_DFT / (dN_obs * dN_obs) * (ReF * ReF + ImF * ImF);

 return;
}

void normalize_spectral_window_file(unsigned long int N_freq) {

 // Normilize window function

 FILE *periodogramfile;

 double *freq= malloc(N_freq * sizeof(double));
 double *theta= malloc(N_freq * sizeof(double));
 double *window= malloc(N_freq * sizeof(double));

 double max_F, max_W, max_F_to_max_W;

 unsigned long int i;

 periodogramfile= fopen("deeming.periodogram", "r");
 i= 0;
 while( -1 < fscanf(periodogramfile, "%lf %lf %lf", &freq[i], &theta[i], &window[i]) )
  i++;
 fclose(periodogramfile);
 max_F= theta[0];
 max_W= window[0];
 for( i= 0; i < N_freq; i++ ) {
  if( max_F < theta[i] )
   max_F= theta[i];
  if( max_W < window[i] )
   max_W= window[i];
 }
 max_F_to_max_W= max_F / max_W;
 periodogramfile= fopen("deeming.periodogram", "w");
 for( i= 0; i < N_freq; i++ ) {
  window[i]= window[i] * max_F_to_max_W;
  fprintf(periodogramfile, "%5.10lf %5.10lf %5.10lf\n", freq[i], theta[i], window[i]);
 }
 fclose(periodogramfile);

 free(freq);
 free(theta);
 free(window);

 return;
}

struct Obs {
 float phase;
 unsigned int n;
};

static int compare_phases(const void *obs11, const void *obs22) {
 struct Obs *obs1= (struct Obs *)obs11;
 struct Obs *obs2= (struct Obs *)obs22;
 if( obs1->phase < obs2->phase )
  return -1;
 return 1;
}

double compute_LK_reciprocal_theta(double *jd, double *m, unsigned int N_obs, double f, double M) {
 unsigned int i;
 struct Obs *obs= malloc(N_obs * sizeof(struct Obs));
 double sum1, sum2;
 double jdi_over_period;

 for( sum2= 0.0, i= 0; i < N_obs; i++ ) {
  jdi_over_period= (jd[i] - jd[0]) * f;
  obs[i].phase= (float)(jdi_over_period - (double)(int)(jdi_over_period));
  if( obs[i].phase < 0.0 )
   obs[i].phase+= 1.0;
  obs[i].n= i;                    // index
  sum2+= (m[i] - M) * (m[i] - M); // yeah, I know it is silly to repeat this calculation every time the funtion is called
 }

 qsort(obs, N_obs, sizeof(struct Obs), compare_phases);

 for( sum1= 0.0, i= 1; i < N_obs; i++ ) {
  sum1+= (m[obs[i].n] - m[obs[i - 1].n]) * (m[obs[i].n] - m[obs[i - 1].n]);
 }
 // Consider also the N+1 case!!!
 sum1+= (m[obs[0].n] - m[obs[N_obs - 1].n]) * (m[obs[0].n] - m[obs[N_obs - 1].n]);

 free(obs);

 return sum2 / sum1; // 1.0/theta;
}

int main(int argc, char **argv) {

 if( argc < 4 ) {
  fprintf(stderr, "Usage:\n Search for the best period\n  %s lightcurve.dat Pmax Pmin Step\n or search for the best period AND estimeate it's significance through lightcurve shuffling\n  %s lightcurve.dat Pmax Pmin Step Niterations\n", argv[0], argv[0]);
  return 1;
 }

 FILE *lcfile= NULL;
 FILE *LK_periodogramfile= NULL;
 FILE *DFT_periodogramfile= NULL;

 double pmax= atof(argv[2]);
 double pmin= atof(argv[3]);
 double step= atof(argv[4]);
 double tmp_period_shuffle;

 // Range check
 if( pmax <= 0.0 ) {
  fprintf(stderr, "ERROR: pmax should be > 0\n");
  return 1;
 }
 if( pmin <= 0.0 ) {
  fprintf(stderr, "ERROR: pmin should be > 0\n");
  return 1;
 }
 if( pmin == pmax ) {
  fprintf(stderr, "ERROR: pmax should be > pmin\n");
  return 1;
 }
 if( pmin > pmax ) {
  //fprintf(stderr,"WARNING: pmax should be > pmin, assuming the input order is mixed-up\n");
  tmp_period_shuffle= pmax;
  pmax= pmin;
  pmin= tmp_period_shuffle;
 }
 if( step <= 0.0 ) {
  fprintf(stderr, "ERROR: the phase step should be > 0\n");
  return 1;
 }
 if( step > 0.5 ) {
  fprintf(stderr, "ERROR: the phase step should be < 0.5\n");
  return 1;
 }

 int shuffle_iteration;
 int shuffle_iterations= 0;
 if( argc == 6 ) {
  shuffle_iterations= atoi(argv[5]);
  // Check range!
  if( shuffle_iterations < 0 ) {
   fprintf(stderr, "ERROR: the number of shuffle iteration cannot be <0\n");
   return 1;
  }
  if( shuffle_iterations > 1000000 ) {
   fprintf(stderr, "ERROR: the number of shuffle iteration cannot be >1000000\n");
   return 1;
  }
 }
 if( shuffle_iterations > 0 )
  fprintf(stderr, "Lightcurve shuffle iterations: %d\n", shuffle_iterations);

 double fmin; //=1.0/pmax;
 double fmax; //=1.0/pmin;
 double df;

 // the number of frequencies will be determined later based on the JD range of observations
 unsigned long int N_freq;
 double *freq= NULL;
 double *power= NULL;
 double *spectral_window= NULL;
 double *theta= NULL;

 unsigned int N_obs;
 double *jd= NULL;
 double *m= NULL;
 double *m_fake= NULL;

 double merr, x, y, app;       // not actually used, needed for compatibility with read_lightcurve_point()
 char string[FILENAME_LENGTH]; // used for comaptibility with read_lightcurve_point() and re-used later

 double LK_periodogram_max, LK_periodogram_max_freq;
 double DFT_periodogram_max, DFT_periodogram_max_freq;
 double noshuffle_DFT_periodogram_max, noshuffle_DFT_periodogram_max_freq;
 double noshuffle_LK_periodogram_max, noshuffle_LK_periodogram_max_freq;
 double DFT_p= 0.0;                // propability of false peak estimated from shuffling
 double LK_p= 0.0;                 // same as above but for the LK peak
 int DFT_shuffled_peak_counter= 0; // peaks higher then the one found in the original non-shuffled lightcurve
 int LK_shuffled_peak_counter= 0;  // peaks higher then the one found in the original non-shuffled lightcurve

 double jdmin, jdmax, T;

 unsigned int i;

 double M;

 double T_DFT; // f_Nyq = N/2T_DFT is the Nyquist frequency as defined in 2014MNRAS.445..437M

 char temporary_string_for_line_counter[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 // RNG initialization
 const gsl_rng_type *RNG_TYPE;
 gsl_rng *r= NULL;
 // if we'll be shuffling the lightcurve
 if( shuffle_iterations > 0 ) {
  // create a generator chosen by the
  //  environment variable GSL_RNG_TYPE
  gsl_rng_env_setup();
  RNG_TYPE= gsl_rng_default;
  r= gsl_rng_alloc(RNG_TYPE);
  gsl_rng_set(r, random_seed()); // set random seed
 }
 // done RNG initialization

 // Select operation mode
 // Use all methods by default
 int compute_Deeming= 1; // 1 - yes, 0 - no
 int compute_LK= 1;      // 1 - yes, 0 - no
 if( 0 == strcmp("deeming_compute_periodogram", basename(argv[0])) ) {
  // Only Deeming
  compute_Deeming= 1; // 1 - yes, 0 - no
  compute_LK= 0;      // 1 - yes, 0 - no
 }
 if( 0 == strcmp("lk_compute_periodogram", basename(argv[0])) ) {
  // Only Deeming
  compute_Deeming= 0; // 1 - yes, 0 - no
  compute_LK= 1;      // 1 - yes, 0 - no
 }
 //

 // Read the input lightcurve file
 lcfile= fopen(argv[1], "r");
 if( lcfile == NULL ) {
  fprintf(stderr, "ERROR opening the lightcurve file %s\n", argv[1]);
  return 1;
 }

 // Get the number of lines in the input file
 N_obs= 0;
 for( N_obs= 1;; N_obs++ ) {
  // the file cannot be of infinite length, right?!
  if( NULL == fgets(temporary_string_for_line_counter, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lcfile) ) {
   break;
  }
  if( N_obs == MAX_NUMBER_OF_OBSERVATIONS ) {
   fprintf(stderr, "ERROR: too many lines in the input file >%d\n", MAX_NUMBER_OF_OBSERVATIONS);
   return 1;
  } // just in case it is infinite length
 }
 fseek(lcfile, 0, SEEK_SET); // go back to the beginning of the lightcurve file
 jd= malloc(N_obs * sizeof(double));
 if( jd == NULL ) {
  fprintf(stderr, "ERROR: allocating memory for the jd array!\n");
  fclose(lcfile);
  return 1;
 }
 m= malloc(N_obs * sizeof(double));
 if( m == NULL ) {
  fprintf(stderr, "ERROR: allocating memory for the m array!\n");
  fclose(lcfile);
  return 1;
 }
 if( compute_Deeming == 1 ) {
  // if this is one iteration and the Deeming method is to be used - we'll also need the spectral window
  if( compute_Deeming == 1 && shuffle_iterations == 0 ) {
   m_fake= malloc(N_obs * sizeof(double));
   if( m_fake == NULL ) {
    fprintf(stderr, "ERROR: allocating memory for the m_fake array!\n");
    fclose(lcfile);
    return 1;
   }
   // Initialize the fake array for computing the window function
   //for(i=0;i<N_obs;i++){
   for( i= N_obs; i--; ) {
    m_fake[i]= 1.0;
   }
   // And if it'll turn out that we have a bit less observations than N_obs - not a big problem
  }
 }

 N_obs= 0; // re-compute N_obs as not all lines in the input file might actually contain observations
 while( -1 < read_lightcurve_point(lcfile, &jd[N_obs], &m[N_obs], &merr, &x, &y, &app, string, NULL) ) {
  if( jd[N_obs] == 0.0 )
   continue;
  N_obs++;
 }
 fclose(lcfile);

 if( N_obs < 5 ) {
  fprintf(stderr, "ERROR: to few observations in the input lightcurve: %d<5 \n", N_obs);
  return 1;
 }

 // Sort the lightcurve for compatibility with the web-based version
 // http://scan.sai.msu.ru/lk/
 // that does sorting
 gsl_sort2(jd, 1, m, 1, N_obs);
 // also for the stuff below we need the sorted lightcurve
 // f_Nyq = N/2T_DFT is the Nyquist frequency as defined in 2014MNRAS.445..437M
 T_DFT= (double)N_obs * (jd[N_obs - 1] - jd[0]) / (double)(N_obs - 1);
 // we compute T_DFT once here and then pass to compute_DFT()
 // so we don't need to recompute it every time

 get_min_max(jd, N_obs, &jdmin, &jdmax);
 T= jdmax - jdmin;

 fmin= 1.0 / pmax;
 fmax= 1.0 / pmin;

 // WARNING! Here we assume that the input period range is OK
 // Get number of frequencies in the spectrum
 df= step / T;
 N_freq= (unsigned long int)((fmax - fmin) / df + 0.5);
 //fprintf(stderr,"df=%lg N_freq=%ld\n",df,N_freq);
 //exit(1);
 /*
 // Well this doesn't work
 df=step/(pmax-pmin);
 N_freq=(int)((fmax-fmin)/df+0.5);
 */

 // compute mean magnitude (M) here
 for( M= 0.0, i= 0; i < N_obs; i++ ) {
  M+= m[i];
 }
 M= M / (double)N_obs;
 // subtract mean magnitude
 for( i= 0; i < N_obs; i++ ) {
  m[i]-= M;
 }

 freq= malloc(N_freq * sizeof(double));
 if( compute_Deeming == 1 )
  power= malloc(N_freq * sizeof(double));
 if( compute_Deeming == 1 && shuffle_iterations == 0 )
  spectral_window= malloc(N_freq * sizeof(double));
 if( compute_LK == 1 )
  theta= malloc(N_freq * sizeof(double));

 // +1 as we always want at least one iteration - the run at the original non-shuffled lightcurve
 for( shuffle_iteration= 0; shuffle_iteration < shuffle_iterations + 1; shuffle_iteration++ ) {

  // If this is not the first iteration - shuffle the lightcurve
  if( shuffle_iteration != 0 ) {
   gsl_ran_shuffle(r, m, N_obs, sizeof(double));
  }

  /*
  freq=malloc(N_freq*sizeof(double));
  if( compute_Deeming==1 )power=malloc(N_freq*sizeof(double));
  if( compute_Deeming==1 && shuffle_iterations==0 )spectral_window=malloc(N_freq*sizeof(double));
  if( compute_LK==1 )theta=malloc(N_freq*sizeof(double));
*/

// Main loop in frequency
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private(i)
#endif
#endif
  for( i= 0; i < N_freq; i++ ) {
   freq[i]= fmin + i * df;
   if( compute_Deeming == 1 )
    compute_DFT(jd, m, N_obs, freq[i], &power[i], T_DFT);
   if( compute_Deeming == 1 && shuffle_iterations == 0 )
    compute_DFT(jd, m_fake, N_obs, freq[i], &spectral_window[i], T_DFT);
   if( compute_LK == 1 )
    theta[i]= compute_LK_reciprocal_theta(jd, m, N_obs, freq[i], 0.0); // mean mag is always 0.0 as we subtracted it from the LC
   //                                          (double *jd, double *m, unsigned int N_obs, double f, double M)
  }

  DFT_periodogram_max= 0.0;
  LK_periodogram_max= 0.0;
  // This part is not parrallell for simplicity
  //for(i=0;i<N_freq;i++){
  for( i= N_freq; i--; ) {
   if( compute_Deeming == 1 ) {
    if( power[i] >= DFT_periodogram_max ) {
     DFT_periodogram_max= power[i];
     DFT_periodogram_max_freq= freq[i];
    }
   }
   if( compute_LK == 1 ) {
    if( theta[i] >= LK_periodogram_max ) {
     LK_periodogram_max= theta[i];
     LK_periodogram_max_freq= freq[i];
    }
   }
  }

  if( shuffle_iteration == 0 ) {
   // If this is the first (or the only shuffle iteration)
   if( compute_Deeming == 1 ) {
    noshuffle_DFT_periodogram_max_freq= DFT_periodogram_max_freq;
    noshuffle_DFT_periodogram_max= DFT_periodogram_max;
   }
   if( compute_LK == 1 ) {
    noshuffle_LK_periodogram_max_freq= LK_periodogram_max_freq;
    noshuffle_LK_periodogram_max= LK_periodogram_max;
   }
  } else {
   // If this is not the first iteration
   if( compute_Deeming == 1 ) {
    if( DFT_periodogram_max >= noshuffle_DFT_periodogram_max ) {
     DFT_shuffled_peak_counter++;
    }
   }
   if( compute_LK == 1 ) {
    if( LK_periodogram_max >= noshuffle_LK_periodogram_max ) {
     LK_shuffled_peak_counter++;
    }
   }
  }

  if( shuffle_iteration > 0 ) {
   if( compute_Deeming == 1 ) {
    DFT_p= (double)DFT_shuffled_peak_counter / (double)shuffle_iteration;
    fprintf(stderr, "DFT: %.6lf +/- %.6lf  %5d out of %5d peaks are above the original highest peak of %.6lf (current peak: %.6lf ); %5d iterations\n", DFT_p, sqrt((double)DFT_shuffled_peak_counter) / (double)shuffle_iteration, DFT_shuffled_peak_counter, shuffle_iteration, noshuffle_DFT_periodogram_max, DFT_periodogram_max, shuffle_iterations);
   }
   if( compute_LK == 1 ) {
    LK_p= (double)LK_shuffled_peak_counter / (double)shuffle_iteration;
    fprintf(stderr, " LK: %.6lf +/- %.6lf  %5d out of %5d peaks are above the original highest peak of %.6lf (current peak: %.6lf ); %5d iterations\n", LK_p, sqrt((double)LK_shuffled_peak_counter) / (double)shuffle_iteration, LK_shuffled_peak_counter, shuffle_iteration, noshuffle_LK_periodogram_max, LK_periodogram_max, shuffle_iterations);
   }
  }

 } // for(shuffle_iteration=0;shuffle_iteration<shuffle_iterations;shuffle_iteration++){

 // if we've ben shuffling the lightcurve
 if( shuffle_iterations > 0 ) {
  gsl_rng_free(r); // RNG de-allocation
 }

 free(jd);
 free(m);

 // Print out the results
 if( compute_Deeming == 1 ) {
  fprintf(stdout, "%.10lf %lf", noshuffle_DFT_periodogram_max_freq, noshuffle_DFT_periodogram_max);
  if( shuffle_iterations > 0 )
   fprintf(stdout, "  %lf +/- %lf", DFT_p, sqrt((double)DFT_shuffled_peak_counter) / (double)shuffle_iterations);
  fprintf(stdout, " DFT\n");
 }
 if( compute_LK == 1 ) {
  fprintf(stdout, "%.10lf %lf", noshuffle_LK_periodogram_max_freq, noshuffle_LK_periodogram_max);
  if( shuffle_iterations > 0 )
   fprintf(stdout, "  %lf +/- %lf", LK_p, sqrt((double)LK_shuffled_peak_counter) / (double)shuffle_iterations);
  fprintf(stdout, " LK\n");
 }

 if( shuffle_iterations == 0 ) {
  // Write the output files
  if( compute_LK == 1 ) {
   LK_periodogramfile= fopen("lk.periodogram", "w");
   if( NULL == LK_periodogramfile ) {
    fprintf(stderr, "ERROR writing lk.periodogram\n");
    return 1;
   }
  }
  if( compute_Deeming == 1 ) {
   DFT_periodogramfile= fopen("deeming.periodogram", "w");
   if( NULL == DFT_periodogramfile ) {
    fprintf(stderr, "ERROR  writing deeming.periodogram\n");
    return 1;
   }
  }
  for( i= 0; i < N_freq; i++ ) {
   if( compute_LK == 1 )
    fprintf(LK_periodogramfile, "%5.10lf %5.10lf\n", freq[i], theta[i]);
   if( compute_Deeming == 1 )
    fprintf(DFT_periodogramfile, "%5.10lf %5.10lf %5.10lf\n", freq[i], power[i], spectral_window[i]);
  }
  if( compute_LK == 1 )
   fclose(LK_periodogramfile);
  if( compute_Deeming == 1 ) {
   fclose(DFT_periodogramfile);
   // We don't care if we didn't compute spectral window
   normalize_spectral_window_file(N_freq);
  }
 }

 free(freq);
 if( compute_LK == 1 )
  free(theta);
 if( compute_Deeming == 1 )
  free(power);
 if( compute_Deeming == 1 && shuffle_iterations == 0 ) {
  free(m_fake);
  free(spectral_window);
 }

 return 0;
}
