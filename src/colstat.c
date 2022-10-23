#include <stdio.h>
#include <gsl/gsl_statistics.h>
#include <gsl/gsl_sort.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include <ctype.h> // for isalpha()

#include "variability_indexes.h" // for esimate_sigma_from_MAD_of_sorted_data() etc.


int main() {
 double *x= NULL;
 double MIN, MAX;
 double MEAN;
 double MEDIAN;
 double SD;
 double MEAN_ERR;
 double MAD;
 double IQR;
 double datasumm;
 int N= 0, Ns= 0, N2s= 0, N3s= 0;
 int i= 0, j= 0;

 char str[2048];
 int str_len, str_is_good;

 fprintf(stderr, "Enter a column of numbers:\n");

 x= malloc(sizeof(double));

 datasumm= 0.0;
 while( NULL != fgets(str, 2048, stdin) ) {
  // Make sure the input string is good
  str_is_good= 1;
  str[2048 - 1]= '\0'; // just in case
  str_len= strlen(str);
  // Check that the string is not suspiciously short
  if( str_len < 1 )
   continue;
  // Check that the string is not suspiciously long
  if( str_len > 100 )
   continue;
  // Check that the string doesn't contain any silly stuff
  for( j= 0; j < str_len; j++ ) {
   if( str[j] == '#' ) {
    str_is_good= 0;
    break;
   }
   if( str[j] == '%' ) {
    str_is_good= 0;
    break;
   }
   if( str[j] == '/' ) {
    str_is_good= 0;
    break;
   }
   if( 1 == isalpha(str[j]) ) {
    str_is_good= 0;
    break;
   }
  }
  if( str_is_good != 1 )
   continue; // bad string
  x[i]= atof(str);
  datasumm= datasumm + x[i];
  i+= 1;
  x= realloc(x, (i + 1) * sizeof(double));
 }

 fprintf(stderr, "-----------------------------------------------------\n");
 fprintf(stdout, "N= %d\n", i);

 gsl_sort(x, 1, i);
 MIN= x[0];
 MAX= x[i - 1];
 MEDIAN= gsl_stats_median_from_sorted_data(x, 1, i);
 MEAN= gsl_stats_mean(x, 1, i);
 SD= gsl_stats_sd_m(x, 1, i, MEAN);
 MEAN_ERR= SD / sqrt( (double)i);
 MAD= compute_MAD_of_sorted_data(x, i); //esimate_sigma_from_MAD_of_sorted_data(x, i);
 IQR= compute_IQR_of_unsorted_data(x, i);

 fprintf(stdout, "     MIN= %.6lf\n", MIN);
 fprintf(stdout, "     MAX= %.6lf\n", MAX);
 fprintf(stdout, " MAX-MIN=  %.6lf\n", MAX - MIN);
 fprintf(stdout, "  MEDIAN= %.6lf\n", MEDIAN);
 fprintf(stdout, "    MEAN= %.6lf\n", MEAN);
 fprintf(stdout, "MEAN_ERR=  %.6lf\n", MEAN_ERR);
 fprintf(stdout, "      SD=  %.6lf\n", SD);
 fprintf(stdout, "     MAD=  %.6lf\n", MAD);
 // 1.48260221850560 = 1/norminv(3/4)
 fprintf(stdout, "MAD*1.48=  %.6lf\n", 1.48260221850560 * MAD);
 fprintf(stdout, "     IQR=  %.6lf\n", IQR);
 // Scale IQR to sigma
 // ${\rm IQR} = 2 \Phi^{-1}(0.75)
 // 2*norminv(0.75) = 1.34897950039216
 //IQR=IQR/( 2.0*gsl_cdf_ugaussian_Pinv(0.75) );
 //IQR=IQR/1.34897950039216;
 fprintf(stdout, "IQR/1.34=  %lf\n", IQR / 1.34897950039216);
 fprintf(stdout, "    SUMM=  %lf\n", datasumm);

 N= Ns= N2s= N3s= 0;
 for( j= 0; j < i; j++ ) {
  if( fabs(MEAN - x[j]) > 3 * SD ) {
   N3s+= 1;
  } else {
   if( fabs(MEAN - x[j]) > 2 * SD && fabs(MEAN - x[j]) < 3 * SD ) {
    N2s+= 1;
   } else {
    if( fabs(MEAN - x[j]) > SD && fabs(MEAN - x[j]) < 2 * SD ) {
     Ns+= 1;
    } else {
     N+= 1;
    }
   }
  }
 }
 fprintf(stderr, "%5d<sigma,      %5d>sigma,      %5d>2*sigma,      %5d>3*sigma       out of %5d points\n", N, Ns, N2s, N3s, N + Ns + N2s + N3s);

 N= Ns= N2s= N3s= 0;
 for( j= 0; j < i; j++ ) {
  if( fabs(MEDIAN - x[j]) > 3 * 1.48260221850560 * MAD ) {
   N3s+= 1;
  } else {
   if( fabs(MEDIAN - x[j]) > 2 * 1.48260221850560 * MAD && fabs(MEDIAN - x[j]) < 3 * 1.48260221850560 * MAD ) {
    N2s+= 1;
   } else {
    if( fabs(MEDIAN - x[j]) > 1.48260221850560 * MAD && fabs(MEDIAN - x[j]) < 2 * 1.48260221850560 * MAD ) {
     Ns+= 1;
    } else {
     N+= 1;
    }
   }
  }
 }
 fprintf(stderr, "%5d<sigma(MAD), %5d>sigma(MAD), %5d>2*sigma(MAD), %5d>3*sigma(MAD)  out of %5d points\n", N, Ns, N2s, N3s, N + Ns + N2s + N3s);

 free(x);

 return 0;
}
