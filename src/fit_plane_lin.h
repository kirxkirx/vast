// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_FIT_PLANE_LIN_INCLUDE_FILE

// Auxiliary function to compute a sum of 'n' 'a's
double a( double *a, unsigned int n );

// Auxiliary function to compute a sum of 'n' 'a'-squared
double aa( double *a, unsigned int n );

// Auxiliary function to compute a sum of 'n' 'a' times 'b' pairs
double ab( double *a, double *b, unsigned int n );
//
// This function performs the plane fitting.
// the plane is defined simply as as z=A*x+B*y+C
//
// based on this example from the GSL manual:
// http://www.gnu.org/software/gsl/manual/html_node/Linear-Algebra-Examples.html
//
void fit_plane_lin( double *x, double *y, double *z, unsigned int N, double *A, double *B, double *C );

// The macro below will tell the pre-processor that this header file is already included
#define VAST_FIT_PLANE_LIN_INCLUDE_FILE
#endif
// VAST_FIT_PLANE_LIN_INCLUDE_FILE
