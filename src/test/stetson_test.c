#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// GSL include files
#include <gsl/gsl_statistics_double.h>

#include "../vast_limits.h"
#include "../variability_indexes.h"
#include "../lightcurve_io.h"

int main(int argc, char **argv) {

 double *JD;
 double *m;
 double *merr;
 double *w;

 int Nobs;
 int Nmax;

 double I, J, K, L, I_sign_only;        // Stetson's variability indexes
 double J_clip, L_clip, J_time, L_time; // Modified Stetson's variability indexes
 double N3;                             // number of significant same-sign deviations
 double excursions;
 double eta, E_A, SB;
 double NXS;
 double chi2;
 double reduced_chi2;
 double peak_to_peak_AGN_v;
 double m_mean;

 double jd, mag, mag_err, x, y, app;
 char string[FILENAME_LENGTH];

 int j; // counter

 FILE *lc_file_descriptor;

 if( argc < 2 ) {
  fprintf(stderr, "Usage: %s test_lightcurve.dat\n", argv[0]);
  return 1;
 }

 lc_file_descriptor= fopen(argv[1], "r");
 if( lc_file_descriptor == NULL ) {
  fprintf(stderr, "ERROR: cannot open lightcurve file %s\n", argv[1]);
  return 1;
 }
 Nobs= 0;
 JD= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(double));
 m= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(double));
 merr= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(double));
 w= malloc(MAX_NUMBER_OF_OBSERVATIONS * sizeof(double));
 
 if ( NULL == JD || NULL == m || NULL == merr || NULL == w ) {
  fprintf(stderr, "ERROR: allocating memory\n");
  return 1;
 }
 
 while( -1 < read_lightcurve_point(lc_file_descriptor, &jd, &mag, &mag_err, &x, &y, &app, string, NULL) ) {
  if( jd == 0.0 )
   continue; // if this line could not be parsed, try the next one
  JD[Nobs]= jd;
  m[Nobs]= mag;
  merr[Nobs]= mag_err;
  Nobs++;
 }
 fclose(lc_file_descriptor);
 Nmax= Nobs; // !!!

 // compute weights
 for( j= 0; j < Nobs; j++ ) {
  w[j]= 1.0 / merr[j];
 }
 m_mean= gsl_stats_wmean(w, 1, m, 1, Nobs); // weighted mean mag.
 //

 NXS= Normalized_excess_variance(m, merr, Nobs);
 chi2= compute_chi2(m, merr, Nobs);
 reduced_chi2= compute_reduced_chi2(m, merr, Nobs);
 peak_to_peak_AGN_v= compute_peak_to_peak_AGN_v(m, merr, Nobs);

 compute_variability_indexes_that_need_time_sorting(JD, m, merr, Nobs, Nmax, &I, &J, &K, &L, &J_clip, &L_clip, &J_time, &L_time, &I_sign_only, &N3, &excursions, &eta, &E_A, &SB);

 fprintf(stderr, "N = %d\nI = %lf\nJ = %lf %lf %lf\nK = %lf\nL = %lf %lf %lf\nI_sign_only = %lf\nN3 = %lf\nexcursions = %lf\neta = %lf\nE_A = %lf\nSB = %lf\nNXS = %lg\n", Nobs, I, J, J_clip, J_time, K, L, L_clip, L_time, I_sign_only, N3, excursions, eta, E_A, SB, NXS);

 fprintf(stderr, "chi2 = %lf\nreduced_chi2 = %lf\npeak_to_peak_AGN_v = %lf\n", chi2, reduced_chi2, peak_to_peak_AGN_v);

 fprintf(stderr, "m_mean_funny_weights = %lf\n", m_mean);

 free(JD);
 free(m);
 free(merr);
 free(w);

 return 0;
}
