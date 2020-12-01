#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include <gsl/gsl_linalg.h>

#include "vast_limits.h"

// Auxiliary function to compute a sum of 'n' 'a's
static inline double a(double *a, unsigned int n) {
 double sum= 0.0;
 int i;
 //for(i=0;i<n;i++)
 for( i= n; i--; )
  sum+= a[i];
 return sum;
}

// Auxiliary function to compute a sum of 'n' 'a'-squared
static inline double aa(double *a, unsigned int n) {
 double sum= 0.0;
 int i;
 //for(i=0;i<n;i++)
 for( i= n; i--; )
  sum+= a[i] * a[i];
 return sum;
}

// Auxiliary function to compute a sum of 'n' 'a' times 'b' pairs
static inline double ab(double *a, double *b, unsigned int n) {
 double sum= 0.0;
 int i;
 //for(i=0;i<n;i++)
 for( i= n; i--; )
  sum+= a[i] * b[i];
 return sum;
}

//
// This function performs the plane fitting.
// the plane is defined simply as as z=A*x+B*y+C
//
// based on this example from the GSL manual:
// http://www.gnu.org/software/gsl/manual/html_node/Linear-Algebra-Examples.html
//
void fit_plane_lin(double *x, double *y, double *z, unsigned int N, double *A, double *B, double *C) {
 double da[9];
 double db[3];

 da[0]= aa(x, N);
 da[1]= ab(y, x, N);
 da[2]= a(x, N);
 da[3]= da[1];
 da[4]= aa(y, N);
 da[5]= a(y, N);
 da[6]= da[2];
 da[7]= da[5];
 da[8]= (double)N;

 db[0]= ab(z, x, N);
 db[1]= ab(z, y, N);
 db[2]= a(z, N);

 gsl_matrix_view m= gsl_matrix_view_array(da, 3, 3);
 gsl_vector_view b= gsl_vector_view_array(db, 3);

 gsl_vector *vector_x= gsl_vector_alloc(3);

 int s;

 gsl_permutation *p= gsl_permutation_alloc(3);

 gsl_linalg_LU_decomp(&m.matrix, p, &s);

 gsl_linalg_LU_solve(&m.matrix, p, &b.vector, vector_x);

 // get values of the ouput parameters
 (*A)= gsl_vector_get(vector_x, 0);
 (*B)= gsl_vector_get(vector_x, 1);
 (*C)= gsl_vector_get(vector_x, 2);

 // just a fun way to print a vector
 //printf ("x = \n");
 //gsl_vector_fprintf(stdout, vector_x, "%g");

 gsl_permutation_free(p);
 gsl_vector_free(vector_x);

 return;
}

/*
 The following servese as an example of how to use the fitting function.


int main(){
 double A,B,C;

 double *x;
 double *y;
 double *z;
 
 x=malloc(MAX_NUMBER_OF_STARS*sizeof(double));
 y=malloc(MAX_NUMBER_OF_STARS*sizeof(double));
 z=malloc(MAX_NUMBER_OF_STARS*sizeof(double));
 
 unsigned int i=0;
 while(-1<fscanf(stdin,"%lf %lf %lf",&x[i],&y[i],&z[i])){
  i++;
 };

 //fit_plane( x, y, z, i, &A, &B, &C, &D); 
 fit_plane_lin( x, y, z, i, &A, &B, &C); 

 //fprintf(stdout,"(%f)*x+(%f)*y+(%f)\n",-1*A/C,-1*B/C,-1*D/C);
 fprintf(stdout,"(%lf)*x+(%lf)*y+(%lf)\n",A,B,C);
 
 free(x);
 free(y);
 free(z); 
 
 return 0;
}
*/
