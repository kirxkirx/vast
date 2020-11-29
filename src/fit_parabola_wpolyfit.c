#include <stdio.h>
#include <stdlib.h>

#include "vast_limits.h"

#include "wpolyfit.h"

//int wpolyfit(double *datax, double *datay, double *dataerr, int n, double *poly_coeff);

int main() {
 double *datax;
 double *datay;
 double *dataerr;
 int n= 0;
 double poly_coeff[8];

 datax= malloc(MAX_NUMBER_OF_STARS * sizeof(double));
 if( datax == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for datax(fit_parabola_wpolyfit.c)\n");
  exit(1);
 };
 datay= malloc(MAX_NUMBER_OF_STARS * sizeof(double));
 if( datay == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for datax(fit_parabola_wpolyfit.c)\n");
  exit(1);
 };
 dataerr= malloc(MAX_NUMBER_OF_STARS * sizeof(double));
 if( dataerr == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for datax(fit_parabola_wpolyfit.c)\n");
  exit(1);
 };

 while( -1 < fscanf(stdin, "%lf %lf %lf", &datax[n], &datay[n], &dataerr[n]) )
  n++;

 wpolyfit(datax, datay, dataerr, n, poly_coeff, NULL);

 fprintf(stdout, "%lf %lf %lf\n", poly_coeff[2], poly_coeff[1], poly_coeff[0]);

 return 0;
}
