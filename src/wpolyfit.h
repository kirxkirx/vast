// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_WPOLYFIT_INCLUDE_FILE

int wpolyfit( double *datax, double *datay, double *dataerr, int n, double *poly_coeff, double *chi2_not_reduced );

int wlinearfit( double *datax, double *datay, double *dataerr, int n, double *poly_coeff, double *chi2_not_reduced );

int robustlinefit( double *datax, double *datay, int n, double *poly_coeff );

// The macro below will tell the pre-processor that this header file is already included
#define VAST_WPOLYFIT_INCLUDE_FILE

#endif
// VAST_WPOLYFIT_INCLUDE_FILE
