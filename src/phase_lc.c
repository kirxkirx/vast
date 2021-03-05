// This program will print a good-looking phase ligthcurve repeating measurements at phases > 1 if needed for representation

#include <stdio.h>
#include <stdlib.h>   
#include <string.h>
#include <math.h>

#include "vast_limits.h" // for MAX_NUMBER_OF_OBSERVATIONS
#include "lightcurve_io.h" // for read_lightcurve_point()

void make_fake_phases(double *jd, double *phase, double *m, unsigned int N_obs, unsigned int *N_obs_fake, int phaserangetype ){

 unsigned int i;
 
 if( phaserangetype==3 ){
  (*N_obs_fake)=N_obs;
  return;
 }
 
 if( phaserangetype==2 ){
  (*N_obs_fake)=N_obs;
  for(i=0;i<N_obs;i++){
   if( phase[i]>=0.0 ){
    phase[(*N_obs_fake)]=phase[i]+1.0;
    m[(*N_obs_fake)]=m[i];
    jd[(*N_obs_fake)]=jd[i];
    (*N_obs_fake)++;
   }
  }
  return;
 }
 
 (*N_obs_fake)=N_obs;
 for(i=0;i<N_obs;i++){
  if( phase[i]>0.5 ){
   phase[(*N_obs_fake)]=phase[i]-1.0;
   m[(*N_obs_fake)]=m[i];
   jd[(*N_obs_fake)]=jd[i];
   (*N_obs_fake)++;
  }
 }

 return;
}

void compute_phases(double *jd, double *phase, unsigned int N_obs, double f, double jd0){
 unsigned int i;
 double jdi_over_period;
 
 for(i=0;i<N_obs;i++){
  jdi_over_period=(jd[i]-jd0)*f;
  phase[i]= jdi_over_period-(double)(int)(jdi_over_period);
  if( phase[i]<0.0 ){
   phase[i]+=1.0;
  }
 }
 
 return;
}

int main( int argc, char **argv){
 
 FILE *lightcurvefile;

 unsigned int N_obs,N_obs_fake;
 double *jd;
 double *phase;
 double *m;
 
 unsigned int i;

 double JD0;
 double period;
 double frequency;

 int phaserangetype=1;
 
 // these variables are not used and needed only to correctly interact with read_lightcurve_point()
 double dmerr,dx,dy,dap;
 char filename[FILENAME_LENGTH];
 //
 
 if( argc<4 ){
  fprintf(stderr,"Usage: %s lightcurve.dat JD0 period\n or\n%s lightcurve.dat JD0 period phase_range_type\nThe phase range type:\n 1 -- 0.5 to 1 (default)\n 2 -- 0.0 to 2.0\n 3 -- 0.0 to 1.0\nExample: %s out01234.dat 2459165.002 486.61 2\n", argv[0], argv[0], argv[0]);
  return 1;
 }
 
 if( argc>=5 ){
  phaserangetype=atoi(argv[4]);
  if( phaserangetype<1 || phaserangetype>3 ){
   fprintf(stderr,"WARNING: the phase type is out of range!\n");
   phaserangetype=1; // check range
  }
 }
 
 JD0=atof(argv[2]);
 
#ifdef STRICT_CHECK_OF_JD_AND_MAG_RANGE
 if( JD0 < EXPECTED_MIN_MJD ) {
  fprintf(stderr, "ERROR: JD0 is too small!\n");
  return 1;
 }
 if( JD0 > EXPECTED_MAX_JD ) {
  fprintf(stderr, "ERROR: JD0 is too large!\n");
  return 1;
 }
#endif
 
 period=atof(argv[3]);
 if( period<=0.0 ) {
  fprintf(stderr,"ERROR: the period cannot be negative or zero!\n");
  return 1;
 }
 frequency=1.0/period;

 jd= malloc(MAX_NUMBER_OF_OBSERVATIONS*sizeof(double));
 phase= malloc(2*MAX_NUMBER_OF_OBSERVATIONS*sizeof(double));
 m= malloc(2*MAX_NUMBER_OF_OBSERVATIONS*sizeof(double)); 


 // read the lightcurve from file
 lightcurvefile=fopen(argv[1],"r");
 if( NULL==lightcurvefile ){
  fprintf(stderr, "ERROR in %s cannot open the input lightcurve file %s\n", argv[0], argv[1]);
  free(jd);
  free(phase);
  free(m);
  return 1;
 }
 N_obs=0;
 while( -1 < read_lightcurve_point(lightcurvefile, &jd[N_obs], &m[N_obs], &dmerr, &dx, &dy, &dap, filename, NULL) ) {
  if( jd[N_obs] == 0.0 ){
   continue;
  }
  N_obs++;
 }
 fclose(lightcurvefile);

 compute_phases( jd, phase, N_obs, frequency, JD0);
 make_fake_phases( jd, phase, m, N_obs, &N_obs_fake, phaserangetype);

 for(i=0;i<N_obs_fake;i++){
  fprintf(stdout,"%+10.7lf %8.4lf %.5lf\n", phase[i], m[i], jd[i]);
 }

 free(jd);
 free(phase);
 free(m);

 return 0;
}

