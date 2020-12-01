#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <math.h>

#include <gsl/gsl_statistics.h>

#include "../../vast_limits.h"

double time_interval(char *lcfilename) {
 FILE *lcfile;
 double jdmin= 0, jdmax= 0, jd;
 char string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 int n= 0;
 lcfile= fopen(lcfilename, "r");
 while( NULL != fgets(string, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, lcfile) ) {
  sscanf(string, "%lf ", &jd);
  if( jdmin == 0 )
   jdmin= jd;
  if( jdmax == 0 )
   jdmax= jd;
  if( jd > jdmax )
   jdmax= jd;
  if( jd < jdmin )
   jdmin= jd;
  n++;
 }
 fclose(lcfile);
 if( n < BLS_DI_MAX ) {
  fprintf(stderr, "ERROR! Not enough points for BLS test!\n");
  exit(1);
 }
 return jdmax - jdmin;
}

void fold(double T0, double Period, int n, double *jd, double *m, double *x) {
 double phase[MAX_NUMBER_OF_OBSERVATIONS];
 int i, j, min_n;
 double buf_x, buf_phase;
 double for_phase;
 // double sum;
 for( i= 0; i < n; i++ ) {
  for_phase= (jd[i] - T0) / Period;
  phase[i]= for_phase - (int)(for_phase);
  x[i]= m[i];
 }
 for( i= 0; i < n; i++ ) {
  min_n= i;
  for( j= i; j < n; j++ ) {
   if( phase[min_n] > phase[j] ) {
    min_n= j;
   }
  }
  buf_phase= phase[i];
  buf_x= x[i];
  phase[i]= phase[min_n];
  x[i]= x[min_n];
  phase[min_n]= buf_phase;
  x[min_n]= buf_x;
 }
 return;
}

int main(int argc, char **argv) {
 FILE *lightcurvefile;
 char str_buf[MAX_NUMBER_OF_OBSERVATIONS];
 double jd[MAX_NUMBER_OF_OBSERVATIONS];
 double m[MAX_NUMBER_OF_OBSERVATIONS];
 double x[MAX_NUMBER_OF_OBSERVATIONS];
 double w;
 double summa_sigm= 0;
 double r[MAX_NUMBER_OF_OBSERVATIONS];
 double s[MAX_NUMBER_OF_OBSERVATIONS];
 double Period= 0.5;
 double T0= 0.0;
 double SRmax= 0.0;
 double SRcurrent;
 double frequency;
 int i, n, di, dimax, i1, i2, i1i2_counter, k;

 double *sr_f= NULL;
 double sr_best= 0.0;
 int sr_f_counter= 0;
 double sr_mean, sr_sd, snr;
 /* Start test */
 if( argc < 2 ) {
  fprintf(stderr, "Usage: ./bls lightcurve.dat\n");
  return 1;
 }
 /* Read data */
 n= 0;
 lightcurvefile= fopen(argv[1], "r");
 while( NULL != fgets(str_buf, MAX_NUMBER_OF_OBSERVATIONS, lightcurvefile) ) {
  sscanf(str_buf, "%lf %lf", &jd[n], &m[n]);
  n++;
 }
 fclose(lightcurvefile);
 /* Compute weights */
 summa_sigm= 0;
 for( i= 0; i < n; i++ )
  summa_sigm+= 1 / (BLS_SIGMA * BLS_SIGMA);
 w= BLS_SIGMA * BLS_SIGMA;
 w= 1 / w;
 w= w / summa_sigm;
 /* Normalize data */
 summa_sigm= 0;
 for( i= 0; i < n; i++ )
  summa_sigm+= w * m[i];
 for( i= 0; i < n; i++ )
  m[i]= m[i] - summa_sigm;
 /* Try different periods */
 frequency= 2 / time_interval(argv[1]);
 if( frequency < BLS_MIN_FREQ )
  frequency= BLS_MIN_FREQ;
 dimax= BLS_DI_MAX; //max eclipse duration
 while( frequency < BLS_MAX_FREQ ) {
  i1i2_counter= 0;
  /* Fold with a given period */
  Period= 1.0 / frequency;
  fold(T0, Period, n, jd, m, x);
  /* Try different eclipse width */
  for( di= BLS_DI_MIN; di < dimax; di++ ) {
   /* Try different eclipse starting points */
   for( i= 0; i < n - di; i++ ) {
    i1= i;
    i2= i1 + di;
    r[i1i2_counter]= w * di;
    summa_sigm= 0;
    for( k= i1; k <= i2; k++ ) {
     summa_sigm+= x[k];
    }
    s[i1i2_counter]= w * summa_sigm;
    i1i2_counter++;
   }
  }
  SRmax= 0.0;
  for( i= 0; i < i1i2_counter; i++ ) {
   SRcurrent= r[i] * (1 - r[i]);
   //   SRcurrent=sqrt(s[i]*s[i]/SRcurrent);
   SRcurrent= s[i] * s[i] / SRcurrent; //no sqrt
   if( SRmax < SRcurrent )
    SRmax= SRcurrent;
  }

  sr_f_counter++;
  sr_f= realloc(sr_f, sr_f_counter * sizeof(double));
  sr_f[sr_f_counter - 1]= sqrt(SRmax);
  if( sr_best < sr_f[sr_f_counter - 1] )
   sr_best= sr_f[sr_f_counter - 1];
  //  fprintf(stdout,"%lf %lf\n",frequency,sqrt(SRmax)); //sqrt!
  frequency+= BLS_FREQ_STEP;
 }
 //sr_mean=mean_double(sr_f,0,sr_f_counter);
 sr_mean= gsl_stats_mean(sr_f, 1, sr_f_counter);
 //sr_sd=sd_double(sr_f,sr_mean,sr_f_counter);
 sr_sd= gsl_stats_sd_m(sr_f, 1, sr_f_counter, sr_mean);
 snr= (sr_best - sr_mean) / sr_sd;
 fprintf(stdout, "%lf\n", snr);
 /*
 fprintf(stdout,"SDE=%.2lf (%.2lf required) ",snr,BLS_CUT);
 if( snr>BLS_CUT )
  return 0;
 else
  return 1;
 */
}
