/*

  This file contains functions to fit the following curve to the data:

  m_phot=a0*log10( pow(10,a1*m_ccd-a2) + 1 ) + a3

  this is formula (1) from  Bacher et al. (2005)
  http://adsabs.harvard.edu/abs/2005MNRAS.362..542B
  in the source code it it referred to as "photocurve".
  If photocurve provides bad fit, formula (3) from Bacher et al. (2005)
  will be fit instead (it is referred to ins the code as "inverse photocurve").

*/

#define MAX_NUMBER_OF_INITIAL_PARAMETER_GUESSES 1e3

#define LM_MAX_NUMBER_OF_ITERATIONS 200
#define LM_ACCURACY 1e-5

#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <gsl/gsl_roots.h>

#include <gsl/gsl_rng.h>
#include <gsl/gsl_randist.h>

#include <gsl/gsl_statistics.h>
#include <gsl/gsl_errno.h>
#include <gsl/gsl_vector.h>
#include <gsl/gsl_blas.h>
#include <gsl/gsl_multifit_nlin.h>

#include <gsl/gsl_version.h> // to set GSL_MAJOR_VERSION

#include "vast_limits.h"
#include "photocurve.h"

struct data {
 int n;
 double *x;
 double *y;
 double *err;
};

int photocurve_f( const gsl_vector *parameters_vector, void *data, gsl_vector *f ) {
 double a0= gsl_vector_get( parameters_vector, 0 );
 double a1= gsl_vector_get( parameters_vector, 1 );
 double a2= gsl_vector_get( parameters_vector, 2 );
 double a3= gsl_vector_get( parameters_vector, 3 );
 int i;
 double fi;
 for ( i= 0; i < ( (struct data *)data )->n; i++ ) {
  fi= a0 * log10( pow( 10, a1 * ( ( (struct data *)data )->x[i] - a2 ) ) + 1 ) + a3;
  gsl_vector_set( f, i, ( fi - ( (struct data *)data )->y[i] ) / ( (struct data *)data )->err[i] );
 }
 return GSL_SUCCESS;
}

int photocurve_df( const gsl_vector *parameters_vector, void *data, gsl_matrix *J ) {
 double a0= gsl_vector_get( parameters_vector, 0 );
 double a1= gsl_vector_get( parameters_vector, 1 );
 double a2= gsl_vector_get( parameters_vector, 2 );
 int i;
 double *x= (double *)( (struct data *)data )->x;
 // double *y = (double *)((struct data *)data)->y;
 double *err= (double *)( (struct data *)data )->err;
 for ( i= 0; i < ( (struct data *)data )->n; i++ ) {
  gsl_matrix_set( J, i, 0, log( pow( 10.0, a1 * ( x[i] - a2 ) ) + 1.0 ) / log( 10.0 ) / err[i] );
  gsl_matrix_set( J, i, 1, a0 * pow( 10.0, a1 * ( x[i] - a2 ) ) * ( x[i] - a2 ) / ( pow( 10.0, a1 * ( x[i] - a2 ) ) + 1.0 ) / err[i] );
  gsl_matrix_set( J, i, 2, -1.0 * a0 * pow( 10.0, a1 * ( x[i] - a2 ) ) * a1 / ( pow( 10.0, a1 * ( x[i] - a2 ) ) + 1.0 ) / err[i] );
  gsl_matrix_set( J, i, 3, 1.0 / err[i] );
 }
 return GSL_SUCCESS;
}

int photocurve_fdf( const gsl_vector *parameters_vector, void *data, gsl_vector *f, gsl_matrix *J ) {
 photocurve_f( parameters_vector, data, f );
 photocurve_df( parameters_vector, data, J );
 return GSL_SUCCESS;
}

int photocurve_inverse_f( const gsl_vector *parameters_vector, void *data, gsl_vector *f ) {
 double a0= gsl_vector_get( parameters_vector, 0 );
 double a1= gsl_vector_get( parameters_vector, 1 );
 double a2= gsl_vector_get( parameters_vector, 2 );
 double a3= gsl_vector_get( parameters_vector, 3 );
 int i;
 double fi;
 for ( i= 0; i < ( (struct data *)data )->n; i++ ) {
  fi= 1.0 / a1 * log10( pow( 10.0, ( ( (struct data *)data )->x[i] - a3 ) / a0 ) - 1.0 ) + a2;
  gsl_vector_set( f, i, ( fi - ( (struct data *)data )->y[i] ) / ( (struct data *)data )->err[i] );
 }
 return GSL_SUCCESS;
}

int photocurve_inverse_df( const gsl_vector *parameters_vector, void *data, gsl_matrix *J ) {
 double a0= gsl_vector_get( parameters_vector, 0 );
 double a1= gsl_vector_get( parameters_vector, 1 );
 double a3= gsl_vector_get( parameters_vector, 3 );
 int i;
 double *x= (double *)( (struct data *)data )->x;
 // double *y = (double *)((struct data *)data)->y;
 double *err= (double *)( (struct data *)data )->err;
 for ( i= 0; i < ( (struct data *)data )->n; i++ ) {
  gsl_matrix_set( J, i, 0, -0.10e1 / a1 * pow( 0.10e2, ( x[i] - a3 ) / a0 ) * ( x[i] - a3 ) * pow( a0, -0.2e1 ) / ( pow( 0.10e2, ( x[i] - a3 ) / a0 ) - 0.1e1 ) / err[i] );
  gsl_matrix_set( J, i, 1, -0.10e1 * pow( a1, -0.2e1 ) * log( pow( 0.10e2, ( x[i] - a3 ) / a0 ) - 0.1e1 ) / log( 0.10e2 ) / err[i] );
  gsl_matrix_set( J, i, 2, 0.1e1 / err[i] );
  gsl_matrix_set( J, i, 3, -0.10e1 / a1 * pow( 0.10e2, ( x[i] - a3 ) / a0 ) / a0 / ( pow( 0.10e2, ( x[i] - a3 ) / a0 ) - 0.1e1 ) / err[i] );
 }
 return GSL_SUCCESS;
}

int photocurve_inverse_fdf( const gsl_vector *parameters_vector, void *data, gsl_vector *f, gsl_matrix *J ) {
 photocurve_inverse_f( parameters_vector, data, f );
 photocurve_inverse_df( parameters_vector, data, J );
 return GSL_SUCCESS;
}

void print_state( size_t iter, gsl_multifit_fdfsolver *s ) {
 fprintf( stderr, "iter: %3u x = % 15.8f % 15.8f % 15.8f % 15.8f "
                  "|f(x)| = %g\n",
          (unsigned int)iter,
          gsl_vector_get( s->x, 0 ),
          gsl_vector_get( s->x, 1 ),
          gsl_vector_get( s->x, 2 ),
          gsl_vector_get( s->x, 3 ),
          gsl_blas_dnrm2( s->f ) );
}

int fit_photocurve( double *datax, double *datay, double *dataerr, int n, double *a, int *function_type, double *chi2_not_reduced ) {

 // function_type = 4 is normal photocurve,
 // function_type = 5 is inverse photocurve!

 struct data Data;
 const gsl_multifit_fdfsolver_type *T;
 gsl_multifit_fdfsolver *s;
 int status= 0;
 unsigned int iter= 0;
 const size_t N= (size_t)n;
 const size_t p= 4;
 double dof= n - p;
 double chi_normal_function;
 double chi_inverse_function;
 gsl_matrix *covar;
 gsl_multifit_function_fdf f;
 gsl_vector_view parameters_vector;
 const gsl_rng_type *TT;
 gsl_rng *r;
 int number_of_initial_parameter_guesses= 0;
#if GSL_MAJOR_VERSION >= 2
 gsl_matrix *J;
#endif

 Data.n= n;
 Data.x= datax;
 Data.y= datay;
 Data.err= dataerr;

 covar= gsl_matrix_alloc( p, p );

 /* Set initial guess for the fit */
 a[0]= 0.3;
 a[1]= 1.0;
 a[2]= gsl_stats_min( datax, 1, n );
 a[3]= gsl_stats_min( datay, 1, n );

 parameters_vector= gsl_vector_view_array( a, p );

 f.f= &photocurve_f;
 f.df= &photocurve_df;
 f.fdf= &photocurve_fdf;
 f.n= N;
 f.p= p;
 f.params= &Data;

 T= gsl_multifit_fdfsolver_lmsder;
 s= gsl_multifit_fdfsolver_alloc( T, N, p );
 gsl_multifit_fdfsolver_set( s, &f, &parameters_vector.vector );

 // compute normal
 do {
  iter++;
  status= gsl_multifit_fdfsolver_iterate( s );
  if ( status )
   break;
  status= gsl_multifit_test_delta( s->dx, s->x, LM_ACCURACY, LM_ACCURACY );
 } while ( status == GSL_CONTINUE && iter < LM_MAX_NUMBER_OF_ITERATIONS );
 chi_normal_function= pow( gsl_blas_dnrm2( s->f ), 2.0 ) / dof; // gsl_blas_dnrm2(s->f);

 // compute inverse

 a[0]= 0.3;
 a[1]= 1.0;
 a[2]= gsl_stats_min( datax, 1, n );
 a[3]= gsl_stats_min( datay, 1, n );
 parameters_vector= gsl_vector_view_array( a, p );

 f.f= &photocurve_inverse_f;
 f.df= &photocurve_inverse_df;
 f.fdf= &photocurve_inverse_fdf;
 f.n= N;
 f.p= p;
 f.params= &Data;

 // Monte Carlo
 gsl_rng_env_setup();
 TT= gsl_rng_default;
 r= gsl_rng_alloc( TT );
 // -----------

 do {
  gsl_multifit_fdfsolver_set( s, &f, &parameters_vector.vector );
  iter= 0;
  do {
   iter++;
   status= gsl_multifit_fdfsolver_iterate( s );
   if ( status )
    break;
   status= gsl_multifit_test_delta( s->dx, s->x, LM_ACCURACY, LM_ACCURACY );
  } while ( status == GSL_CONTINUE && iter < LM_MAX_NUMBER_OF_ITERATIONS );
  chi_inverse_function= pow( gsl_blas_dnrm2( s->f ), 2.0 ) / dof;
  // Inverse photocurve fit may not converge. If this is the case,
  // we try to vary the initial values of a[2] and a[3] until the
  // converging fit will be found.
  if ( 1 == isnan( chi_inverse_function ) ) {
   a[0]= 0.3;
   a[1]= 1.0;
   // a[2]=gsl_ran_gaussian(r, 1.0)+gsl_stats_min(datax,1,n);
   a[2]= gsl_ran_gaussian( r, 1.0 ) + gsl_stats_min( datay, 1, n );
   // a[3]=gsl_ran_gaussian(r, 1.0)+gsl_stats_min(datay,1,n);
   a[3]= gsl_ran_gaussian( r, 1.0 ) + gsl_stats_min( datax, 1, n );
   parameters_vector= gsl_vector_view_array( a, p );
   number_of_initial_parameter_guesses++;
   if ( number_of_initial_parameter_guesses == MAX_NUMBER_OF_INITIAL_PARAMETER_GUESSES )
    fprintf( stderr, "STOP!\n" );
  }
 } while ( 1 == isnan( chi_inverse_function ) && number_of_initial_parameter_guesses < MAX_NUMBER_OF_INITIAL_PARAMETER_GUESSES );

 // Monte Carlo
 gsl_rng_free( r );
 // -----------

 // So, which function is better: photocurve or inverse photocurve?
 // compute best
 ( *function_type )= 5;
 iter= 0;
 if ( chi_inverse_function > chi_normal_function || 1 == isnan( chi_inverse_function ) ) {

  a[0]= 0.3;
  a[1]= 1.0;
  a[2]= gsl_stats_min( datax, 1, n );
  a[3]= gsl_stats_min( datay, 1, n );
  parameters_vector= gsl_vector_view_array( a, p );

  f.f= &photocurve_f;
  f.df= &photocurve_df;
  f.fdf= &photocurve_fdf;
  f.n= N;
  f.p= p;
  f.params= &Data;

  gsl_multifit_fdfsolver_set( s, &f, &parameters_vector.vector );
  do {
   iter++;
   status= gsl_multifit_fdfsolver_iterate( s );
   if ( status )
    break;
   status= gsl_multifit_test_delta( s->dx, s->x, LM_ACCURACY, LM_ACCURACY );
  } while ( status == GSL_CONTINUE && iter < LM_MAX_NUMBER_OF_ITERATIONS );
  ( *function_type )= 4; // say that we want the normal function
 }

///////////////////////////////////////////////
// Here is the API difference between GSL v1 and v2
#if GSL_MAJOR_VERSION >= 2
 // Sure the dimentions should be f.n f.p ???
 // gsl_matrix *J = gsl_matrix_alloc(f.n, f.p);
 J= gsl_matrix_alloc( s->fdf->n, s->fdf->p );
 gsl_multifit_fdfsolver_jac( s, J );
 gsl_multifit_covar( J, 0.0, covar );
 // free previousely allocated memory
 gsl_matrix_free( J );
#else
 gsl_multifit_covar( s->J, 0.0, covar );
#endif
 ///////////////////////////////////////////////

 /* Set the best-fit values */
 a[0]= gsl_vector_get( s->x, 0 );
 a[1]= gsl_vector_get( s->x, 1 );
 a[2]= gsl_vector_get( s->x, 2 );
 a[3]= gsl_vector_get( s->x, 3 );

 // Report the residual chi^2 if we need to
 if ( NULL != chi2_not_reduced ) {
  ( *chi2_not_reduced )= pow( gsl_blas_dnrm2( s->f ), 2.0 );
 }

 gsl_multifit_fdfsolver_free( s );
 gsl_matrix_free( covar );

 return 0; // it would be nice to return an actual error code if something goes wrong
}

double eval_photocurve( double mag, double *a, int function_type ) {
 double mag_out;
 if ( function_type == 4 )
  mag_out= a[0] * log10( pow( 10, a[1] * ( mag - a[2] ) ) + 1.0 ) + a[3];
 else
  mag_out= 1.0 / a[1] * log10( pow( 10, ( mag - a[3] ) / a[0] ) - 1.0 ) + a[2];
 return (double)mag_out;
}
