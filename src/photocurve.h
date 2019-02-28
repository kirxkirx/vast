// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_PHOTOCURVE_INCLUDE_FILE

int fit_photocurve( double *datax, double *datay, double *dataerr, int n, double *a, int *function_type, double *chi2_not_reduced );

double eval_photocurve( double mag, double *a, int function_type );

// The macro below will tell the pre-processor that this header file is already included
#define VAST_PHOTOCURVE_INCLUDE_FILE

#endif
// VAST_PHOTOCURVE_INCLUDE_FILE
