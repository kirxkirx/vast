#include <stdio.h>
#include <gsl/gsl_vector.h>
#include <gsl/gsl_multifit_nlin.h>
#include <gsl/gsl_roots.h>
#include <gsl/gsl_errno.h> // for GSL_SUCCESS, GSL_NAN
#include <math.h>
#include <stdlib.h>

/*

   This code implements the technique of magnitude limit determination
   based on fitting a model to the SNR-magnitude plot as suggested by Sergey Karpov
   https://ui.adsabs.harvard.edu/abs/2024arXiv241116470K/abstract

*/

// Structure to hold data for fitting
struct fit_data {
 size_t n;
 double *mag;
 double *sn;
 double *params; // Fitted parameters
};

// Structure for root finding
struct root_params {
 double *fitted_params;
 double target_sn;
};

// S/N model function
static double sn_model( double mag, double *params ) {
 return 1.0 / sqrt( params[0] * pow( 10, 0.8 * mag ) + params[1] * pow( 10, 0.4 * mag ) );
}

// Function to compute residuals for GSL fitting
static int residuals_f( const gsl_vector *x, void *params, gsl_vector *f ) {
 struct fit_data *data= (struct fit_data *)params;
 double p0= gsl_vector_get( x, 0 );
 double p1= gsl_vector_get( x, 1 );
 size_t i;

 for ( i= 0; i < data->n; i++ ) {
  double model_sn= sn_model( data->mag[i], ( double[] ){ p0, p1 } );
  // Minimize residuals in logarithms for better stability
  gsl_vector_set( f, i, log10( data->sn[i] ) - log10( model_sn ) );
 }

 return GSL_SUCCESS;
}

// Function for root finding
static double root_f( double x, void *params ) {
 struct root_params *rp= (struct root_params *)params;
 double model_val= sn_model( x, rp->fitted_params );
 return log10( model_val ) - log10( rp->target_sn );
}

// Make S/N model function
static void make_sn_model( double *mag, double *sn, size_t n, double *params ) {
 const size_t p= 2; // Number of parameters
 struct fit_data data= { n, mag, sn, params };
 size_t i;

 // Setup GSL fitting
 gsl_multifit_function_fdf f;
 f.f= &residuals_f;
 f.df= NULL; // We don't provide analytical derivatives
 f.fdf= NULL;
 f.n= n;
 f.p= p;
 f.params= &data;

 // Initial parameter estimates
 gsl_vector *x= gsl_vector_alloc( p );
 // Compute initial parameters similar to Python version
 double max_sn= 0;
 size_t max_sn_idx= 0;
 for ( i= 0; i < n; i++ ) {
  if ( sn[i] > max_sn ) {
   max_sn= sn[i];
   max_sn_idx= i;
  }
 }

 // Set initial parameters
 double init_p0= 0; // Will store median value
 double init_p1= pow( 10, -0.4 * mag[max_sn_idx] ) / ( max_sn * max_sn );

 gsl_vector_set( x, 0, init_p0 );
 gsl_vector_set( x, 1, init_p1 );

 // Setup solver
 const gsl_multifit_fdfsolver_type *T= gsl_multifit_fdfsolver_lmsder;
 gsl_multifit_fdfsolver *solver= gsl_multifit_fdfsolver_alloc( T, n, p );
 gsl_multifit_fdfsolver_set( solver, &f, x );

 // Iterate to solve
 int status;
 size_t iter= 0;
 do {
  iter++;
  status= gsl_multifit_fdfsolver_iterate( solver );
  if ( status )
   break;
  status= gsl_multifit_test_delta( solver->dx, solver->x, 1e-4, 1e-4 );
 } while ( status == GSL_CONTINUE && iter < 500 );

 // Store results
 params[0]= gsl_vector_get( solver->x, 0 );
 params[1]= gsl_vector_get( solver->x, 1 );

 // Print model parameters
 // fprintf(stderr,"make_sn_model(): Fitted model parameters: p[0]=%e, p[1]=%e\n", params[0], params[1]);
 // fprintf(stderr,"make_sn_model(): Gnuplot command:\n");
 // fprintf(stderr,"make_sn_model(): set logscale y ; plot 'image00001.cat' u 4:($2)/($3), 1.0 / sqrt(%e * 10**(0.8 * x) + %e * 10**(0.4 * x))\n", params[0], params[1]);

 // Cleanup
 gsl_multifit_fdfsolver_free( solver );
 gsl_vector_free( x );
}

// Helper function to find suitable bracket for root finding
static int find_bracket( gsl_function *F, double x_start, double *x_lo, double *x_hi ) {
 double f_lo, f_hi;
 double x_curr= x_start;
 double x_step= 0.5; // Initial step size
 int max_tries= 50;  // Maximum number of attempts
 int i;

 // fprintf(stderr,"Starting bracket search from x=%.3f\n", x_start);

 f_lo= GSL_FN_EVAL( F, x_curr );
 // fprintf(stderr,"Initial f(%.3f)=%.3f\n", x_curr, f_lo);

 // Try to find bracket by expanding search range
 for ( i= 0; i < max_tries; i++ ) {
  x_curr+= x_step;
  f_hi= GSL_FN_EVAL( F, x_curr );
  // fprintf(stderr,"Try positive: x=%.3f, f(x)=%.3f\n", x_curr, f_hi);

  // Check if we found a bracket
  if ( f_lo * f_hi < 0 ) {
   *x_lo= x_curr - x_step;
   *x_hi= x_curr;
   // fprintf(stderr,"Found bracket in positive direction: [%.3f, %.3f]\n", *x_lo, *x_hi);
   return GSL_SUCCESS;
  }

  // If we haven't found a bracket, increase step size
  x_step*= 1.6;
  f_lo= f_hi;
 }

 // Also try in negative direction from start point
 x_curr= x_start;
 x_step= -0.5;
 f_lo= GSL_FN_EVAL( F, x_curr );

 for ( i= 0; i < max_tries; i++ ) {
  x_curr+= x_step;
  // Totally go into negative magnitudes! The instrumenta lmagnitudes are negative.
  // if (x_curr < 0) break;  // Don't go into negative magnitudes

  f_hi= GSL_FN_EVAL( F, x_curr );
  // fprintf(stderr,"Try negative: x=%.3f, f(x)=%.3f\n", x_curr, f_hi);

  if ( f_lo * f_hi < 0 ) {
   *x_lo= x_curr;
   *x_hi= x_curr - x_step;
   // fprintf(stderr,"Found bracket in negative direction: [%.3f, %.3f]\n", *x_lo, *x_hi);
   return GSL_SUCCESS;
  }

  x_step*= 1.6;
  f_lo= f_hi;
 }

 return GSL_FAILURE;
}

double get_detection_limit_sn( double *mag, double *mag_sn, size_t n, double target_sn,
                               int *success ) {
 size_t i;
 // Fit the model first
 double params[2];
 make_sn_model( mag, mag_sn, n, params );

 // Setup root finding
 struct root_params rp= { params, target_sn };
 gsl_function F;
 F.function= &root_f;
 F.params= &rp;

 // Find maximum magnitude as starting point
 double max_mag= mag[0];
 for ( i= 1; i < n; i++ ) {
  if ( mag[i] > max_mag )
   max_mag= mag[i];
 }

 // Find bracket for root
 double x_lo, x_hi;
 int bracket_status= find_bracket( &F, max_mag, &x_lo, &x_hi );
 if ( bracket_status != GSL_SUCCESS ) {
  if ( success != NULL ) {
   *success= 0;
  }
  return GSL_NAN;
 }

 // Initialize root finder
 const gsl_root_fsolver_type *T= gsl_root_fsolver_brent;
 gsl_root_fsolver *solver= gsl_root_fsolver_alloc( T );

 // Setup solver with found bracket
 gsl_root_fsolver_set( solver, &F, x_lo, x_hi );

 // Iterate to find root
 int status;
 size_t iter= 0;
 double root= GSL_NAN;

 do {
  iter++;
  status= gsl_root_fsolver_iterate( solver );
  if ( status )
   break;

  root= gsl_root_fsolver_root( solver );
  x_lo= gsl_root_fsolver_x_lower( solver );
  x_hi= gsl_root_fsolver_x_upper( solver );

  status= gsl_root_test_interval( x_lo, x_hi, 0, 1e-6 );
 } while ( status == GSL_CONTINUE && iter < 100 );

 // Cleanup
 gsl_root_fsolver_free( solver );

 // Check if success pointer is NULL before dereferencing
 if ( success != NULL ) {
  *success= status; // should be GSL_SUCCESS if we are good

  if ( status == GSL_SUCCESS ) {
   fprintf( stderr, "get_detection_limit_sn(): Detection limit: %.2f\n", root );
  } else {
   fprintf( stderr, "get_detection_limit_sn(): Failed to find detection limit\n" );
  }
 }

 return root;
}

/*
double get_detection_limit_sn( double *mag, double *mag_sn, size_t n, double target_sn,
                               int *success ) {
 size_t i;
 // Fit the model first
 double params[2];
 make_sn_model( mag, mag_sn, n, params );

 // Setup root finding
 struct root_params rp= { params, target_sn };
 gsl_function F;
 F.function= &root_f;
 F.params= &rp;

 // Find maximum magnitude as starting point
 double max_mag= mag[0];
 for ( i= 1; i < n; i++ ) {
  if ( mag[i] > max_mag )
   max_mag= mag[i];
 }

 // Find bracket for root
 double x_lo, x_hi;
 int bracket_status= find_bracket( &F, max_mag, &x_lo, &x_hi );
 if ( bracket_status != GSL_SUCCESS ) {
  *success= 0;
  return GSL_NAN;
 }

 // Initialize root finder
 const gsl_root_fsolver_type *T= gsl_root_fsolver_brent;
 gsl_root_fsolver *solver= gsl_root_fsolver_alloc( T );

 // Setup solver with found bracket
 gsl_root_fsolver_set( solver, &F, x_lo, x_hi );

 // Iterate to find root
 int status;
 size_t iter= 0;
 double root= GSL_NAN;

 do {
  iter++;
  status= gsl_root_fsolver_iterate( solver );
  if ( status )
   break;

  root= gsl_root_fsolver_root( solver );
  x_lo= gsl_root_fsolver_x_lower( solver );
  x_hi= gsl_root_fsolver_x_upper( solver );

  status= gsl_root_test_interval( x_lo, x_hi, 0, 1e-6 );
 } while ( status == GSL_CONTINUE && iter < 100 );

 // Cleanup
 gsl_root_fsolver_free( solver );

 *success= status; // should be GSL_SUCCESS if we are good

 if ( success ) {
  fprintf( stderr, "get_detection_limit_sn(): Detection limit: %.2f\n", root );
 } else {
  fprintf( stderr, "get_detection_limit_sn(): Failed to find detection limit\n" );
 }

 return root;
}
*/
/*
// The main() function for standalone test of this code
int main(){
 double mag[50000];
 double mag_sn[50000];

 int success;
 double detection_limit;

 int n=0;
 while( -1<fscanf(stdin,"%lf %lf",&mag[n],&mag_sn[n]) ){
  n++;
 }

 detection_limit = get_detection_limit_sn(mag, mag_sn, n, 5.0, &success);

 if (success) {
     fprintf(stderr,"Detection limit: %.2f\n", detection_limit);
 } else {
     fprintf(stderr,"Failed to find detection limit\n");
 }
 return 0;
}
*/
