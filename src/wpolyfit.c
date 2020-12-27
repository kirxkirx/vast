#include <stdlib.h>
#include <stdio.h>
#include <gsl/gsl_fit.h> // for the fallback option gsl_fit_linear()
#include <gsl/gsl_multifit.h>
#include <gsl/gsl_errno.h> // for gsl_strerror(s)
//
#include <gsl/gsl_statistics.h>
#include <gsl/gsl_sort.h>

int wpolyfit(double *datax, double *datay, double *dataerr, int n, double *poly_coeff, double *chi2_not_reduced) {

 gsl_set_error_handler_off();

 int i;
 double xi, yi, ei, chisq;
 gsl_matrix *X, *cov;
 gsl_vector *y, *w, *c;

 X= gsl_matrix_alloc(n, 3);
 y= gsl_vector_alloc(n);
 w= gsl_vector_alloc(n);

 c= gsl_vector_alloc(3);
 cov= gsl_matrix_alloc(3, 3);

 for( i= 0; i < n; i++ ) {
  xi= datax[i];
  yi= datay[i];
  ei= dataerr[i];

  gsl_matrix_set(X, i, 0, 1.0);
  gsl_matrix_set(X, i, 1, xi);
  gsl_matrix_set(X, i, 2, xi * xi);

  gsl_vector_set(y, i, yi);
  gsl_vector_set(w, i, 1.0 / (ei * ei));
 }

 gsl_multifit_linear_workspace *work= gsl_multifit_linear_alloc(n, 3);
 if( 0 != gsl_multifit_wlinear(X, w, y, c, cov, &chisq, work) )
  return 1;
 gsl_multifit_linear_free(work);

#define C(i) (gsl_vector_get(c, (i)))
#define COV(i, j) (gsl_matrix_get(cov, (i), (j)))

 poly_coeff[0]= C(0);
 poly_coeff[1]= C(1);
 poly_coeff[2]= C(2);
 poly_coeff[5]= COV(0, 0);
 poly_coeff[6]= COV(1, 1);
 poly_coeff[7]= COV(2, 2);

 if( NULL != chi2_not_reduced ) {
  (*chi2_not_reduced)= chisq;
 }

 /* Free GSL stuff */
 gsl_matrix_free(X);
 gsl_vector_free(y);
 gsl_vector_free(w);
 gsl_vector_free(c);
 gsl_matrix_free(cov);

 return 0;
}

int wlinearfit(double *datax, double *datay, double *dataerr, int n, double *poly_coeff, double *chi2_not_reduced) {

 gsl_set_error_handler_off();

 int i;
 double xi, yi, ei, chisq;
 gsl_matrix *X, *cov;
 gsl_vector *y, *w, *c;

 X= gsl_matrix_alloc(n, 2);
 y= gsl_vector_alloc(n);
 w= gsl_vector_alloc(n);

 c= gsl_vector_alloc(2);
 cov= gsl_matrix_alloc(2, 2);

 for( i= 0; i < n; i++ ) {
  xi= datax[i];
  yi= datay[i];
  ei= dataerr[i];

  gsl_matrix_set(X, i, 0, 1.0);
  gsl_matrix_set(X, i, 1, xi);
  //gsl_matrix_set(X, i, 2, xi*xi);

  gsl_vector_set(y, i, yi);
  gsl_vector_set(w, i, 1.0 / (ei * ei));
  // TESTING THE MORE REOBUST WEIGHTING SCHEME
  //gsl_vector_set(w, i, 1.0 / ei );
 }

 gsl_multifit_linear_workspace *work= gsl_multifit_linear_alloc(n, 2);
 if( 0 != gsl_multifit_wlinear(X, w, y, c, cov, &chisq, work) )
  return 1;
 gsl_multifit_linear_free(work);

#define C(i) (gsl_vector_get(c, (i)))
#define COV(i, j) (gsl_matrix_get(cov, (i), (j)))

 poly_coeff[0]= C(0);
 poly_coeff[1]= C(1);
 poly_coeff[2]= 0.0; //C(2);
 poly_coeff[5]= COV(0, 0);
 poly_coeff[6]= COV(1, 1);
 poly_coeff[7]= 0.0; //COV(2, 2);

 if( NULL != chi2_not_reduced ) {
  (*chi2_not_reduced)= chisq;
 }

 /* Free GSL stuff */
 gsl_matrix_free(X);
 gsl_vector_free(y);
 gsl_vector_free(w);
 gsl_vector_free(c);
 gsl_matrix_free(cov);

 return 0;
}

// Below is the stuff for robust line fitting

int dofit(const gsl_multifit_robust_type *T,
          const gsl_matrix *X, const gsl_vector *y,
          gsl_vector *c, gsl_matrix *cov) {
 int s;

 gsl_set_error_handler_off(); // so the program doesn't crash if the the robust fit fails

 gsl_multifit_robust_workspace *work= gsl_multifit_robust_alloc(T, X->size1, X->size2);

 s= gsl_multifit_robust(X, y, c, cov, work);
 gsl_multifit_robust_free(work);

 if( s != 0 ) {
  fprintf(stderr, "WARNING: %s\n", gsl_strerror(s));
 }

 return s;
}

int robustlinefit(double *datax, double *datay, int n, double *poly_coeff) {
 int i;             // counter
 const size_t p= 2; /* linear fit */
 gsl_matrix *X, *cov;
 gsl_vector *x, *y, *c;
 double xi;

 X= gsl_matrix_alloc(n, p);
 x= gsl_vector_alloc(n);
 y= gsl_vector_alloc(n);

 c= gsl_vector_alloc(p);
 cov= gsl_matrix_alloc(p, p);

 for( i= 0; i < n; i++ ) {
  gsl_vector_set(x, i, datax[i]);
  gsl_vector_set(y, i, datay[i]);
 }

 /* construct design matrix X for linear fit */
 for( i= 0; i < n; ++i ) {
  xi= gsl_vector_get(x, i);
  gsl_matrix_set(X, i, 0, 1.0);
  gsl_matrix_set(X, i, 1, xi);
 }

 /* perform robust fit */
 if( 0 == dofit(gsl_multifit_robust_bisquare, X, y, c, cov) ) {
  // defined above
  // #define C(i) (gsl_vector_get(c,(i)))
  // #define COV(i,j) (gsl_matrix_get(cov,(i),(j)))

  poly_coeff[0]= C(0);
  poly_coeff[1]= C(1);
  poly_coeff[2]= 0.0; //C(2);
  poly_coeff[5]= COV(0, 0);
  poly_coeff[6]= COV(1, 1);
  poly_coeff[7]= 0.0; //COV(2, 2);
 } else {
  // If the robust fit fails -- fall back to the simple unweighted fit
  fprintf(stderr, "WARNING: robust line fitting failed in robustlinefit() -- falling back to the simple unweighted linear fit!\n");
  gsl_fit_linear(datax, 1, datay, 1, n, &poly_coeff[0], &poly_coeff[1], &poly_coeff[5], &poly_coeff[2], &poly_coeff[6], &poly_coeff[7]);
  poly_coeff[2]= 0.0;
  poly_coeff[7]= 0.0;
 }

 /* Free GSL stuff */
 gsl_matrix_free(X);
 gsl_vector_free(x);
 gsl_vector_free(y);
 gsl_vector_free(c);
 gsl_matrix_free(cov);

 return 0;
}

int robustzeropointfit(double *datax, double *datay, double *dataerr, int n, double *poly_coeff) {
 int i;
 double median_mag_diff;
 double *mag_diff;
 double *w;
 mag_diff= malloc(n * sizeof(double));
 if( mag_diff == NULL ) {
  fprintf(stderr, "Memory allocation ERROR in robustzeropointfit()\n");
  return 1;
 }
 w= malloc(n * sizeof(double));
 if( w == NULL ) {
  fprintf(stderr, "Memory allocation ERROR in robustzeropointfit()\n");
  return 1;
 }
 for( i= 0; i < n; i++ ) {
  mag_diff[i]= datay[i] - datax[i];
  w[i]= 1.0 / (dataerr[i] * dataerr[i]);
 }
 //gsl_sort( mag_diff, 1, n );
 //median_mag_diff= gsl_stats_median_from_sorted_data( mag_diff, 1, n );
 //median_mag_diff= gsl_stats_mean( mag_diff, 1, n );
 median_mag_diff= gsl_stats_wmean(w, 1, mag_diff, 1, n);
 free(w);
 free(mag_diff);
 poly_coeff[7]= poly_coeff[6]= poly_coeff[5]= poly_coeff[4]= poly_coeff[3]= poly_coeff[2]= poly_coeff[1]= poly_coeff[0]= 0.0;
 poly_coeff[1]= 1.0;
 poly_coeff[0]= median_mag_diff;
 fprintf(stderr, "Final zero-point offset %.4lf mag\n", median_mag_diff);
 return 0;
}
