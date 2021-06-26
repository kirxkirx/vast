#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
#include <gsl/gsl_fit.h>
#include <gsl/gsl_multifit.h>
#include <gsl/gsl_errno.h>

#include <libgen.h> // for basename()

#include "cpgplot.h"

#include "setenv_local_pgplot.h"

#include "vast_limits.h"

#include "photocurve.h"

#include "wpolyfit.h"

void choose_fittting_function(double *insmag, double *catmag, int n_stars, int *fit_function) {

 double poly_coeff[8]= {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
 double *w;
 int i; // just a counter

 double sumsqres_photocurve, sumsqres_parabola;

 // set default
 (*fit_function)= 2;

 // Consider two special cases:
 // if n_stars<5 set fit_function=3 (line with fixed a)
 if( n_stars < 5 ) {
  (*fit_function)= 3;
  return;
 }
 // if n_stars<MIN_NUMBER_STARS_POLY_MAG_CALIBR set fit_function=1 (line)
 if( n_stars < MIN_NUMBER_STARS_POLY_MAG_CALIBR ) {
  (*fit_function)= 1;
  return;
 }

 // Prepare fake weights
 w= malloc(n_stars * sizeof(double));
 if( w == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for w(fit_mag_calib.c)\n");
  exit(1);
 };
 for( i= 0; i < n_stars; i++ )
  w[i]= 1.0;

 // Now try to fit various functions and see which one works best:
 // try photocurve
 fit_photocurve(insmag, catmag, w, n_stars, poly_coeff, fit_function, &sumsqres_photocurve);
 // try linear function
 wpolyfit(insmag, catmag, w, n_stars, poly_coeff, &sumsqres_parabola);
 // this is now returned by fit_photocurve()
 // for(sumsqres_parabola=0.0,i=0;i<n_stars;i++)sumsqres_parabola+=(catmag[i] - (A*insmag[i]*insmag[i]+B*insmag[i]+C) )*(catmag[i] - (A*insmag[i]*insmag[i]+B*insmag[i]+C) );
 if( sumsqres_parabola < sumsqres_photocurve )
  (*fit_function)= 2;

 free(w);

 fprintf(stderr, "sumsqres_photocurve=%lf sumsqres_parabola=%lf\n", sumsqres_photocurve, sumsqres_parabola);

 return;
}

int main(int argc, char **argv) {
 char calibfilename[FILENAME_LENGTH];
 FILE *calibfile;
 double *insmag;
 float *finsmag;
 double *insmagerr;
 float *finsmagerr;
 double *catmag;
 float *fcatmag;
 double *w;
 double cov00, cov01, cov11, sumsqres;
 int n_stars= 0;
 int j, k;

 double poly_coeff[8]= {0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0};
 double A= 0.0;
 double B= 0.0;
 double C= 0.0;

 double sum1, sum2;

 float mincatmag, maxcatmag, mininstmag, maxinstmag;

 float *computed_x;
 float *computed_y;

 /* PGPLOT vars */
 float curX, curY;
 float curX2, curY2;
 char curC;
 char PGPLOT_CONTROL[100];
 int change_limits_trigger= 0;
 float new_X1, new_X2, old_X1, old_X2;
 float new_Y1, new_Y2, old_Y1, old_Y2;
 char header_str[512];
 char header_str2[512];
 /* ----------- */

 /* switch */
 int weights_on= 1;
 int fit_function= 6; // 1 - line (a*x+b), 
                      // 2 - parabola(c*x^2+a*x+b), 
                      // 3 - line with a=1 (1*x+b), 
                      // 4 - "photocurve", 
                      // 5 - "inverse photocurve" (will be set automatically if fits better than "photocurve"),
                      // 6 - robust linear fit (default) (a*x+b)

 /* remove points */
 int remove_best_j;
 float best_dist= 99999;
 float y_to_x_scaling_factor; // to compensate for the difference in scale between the two axes

 // operating mode
 int operation_mode= 0; // 0 - interactive, default
                        // 1 - non-interactive, linear
                        // 2 - non-interactive, photocurve
                        // 3 - non-interactive, zero-point only
                        // 4 - non-interactive, robust linear
 /* */

 /* Allocate memory */
 insmag= malloc(MAX_NUMBER_OF_STARS_MAG_CALIBR * sizeof(double));
 if( insmag == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for insmag(fit_mag_calib.c)\n");
  exit(1);
 };
 finsmag= malloc(MAX_NUMBER_OF_STARS_MAG_CALIBR * sizeof(float));
 if( finsmag == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for finsmag(fit_mag_calib.c)\n");
  exit(1);
 };
 insmagerr= malloc(MAX_NUMBER_OF_STARS_MAG_CALIBR * sizeof(double));
 if( insmagerr == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for insmagerr(fit_mag_calib.c)\n");
  exit(1);
 };
 finsmagerr= malloc(MAX_NUMBER_OF_STARS_MAG_CALIBR * sizeof(float));
 if( finsmagerr == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for finsmagerr(fit_mag_calib.c)\n");
  exit(1);
 };
 catmag= malloc(MAX_NUMBER_OF_STARS_MAG_CALIBR * sizeof(double));
 if( catmag == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for catmag(fit_mag_calib.c)\n");
  exit(1);
 };
 fcatmag= malloc(MAX_NUMBER_OF_STARS_MAG_CALIBR * sizeof(float));
 if( fcatmag == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for fcatmag(fit_mag_calib.c)\n");
  exit(1);
 };
 w= malloc(MAX_NUMBER_OF_STARS_MAG_CALIBR * sizeof(double));
 if( w == NULL ) {
  fprintf(stderr, "ERROR2: Couldn't allocate memory for w(fit_mag_calib.c)\n");
  exit(1);
 };
 computed_x= malloc(MAX_NUMBER_OF_STARS_MAG_CALIBR * sizeof(float));
 if( computed_x == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for computed_x(fit_mag_calib.c)\n");
  exit(1);
 };
 computed_y= malloc(MAX_NUMBER_OF_STARS_MAG_CALIBR * sizeof(float));
 if( computed_y == NULL ) {
  fprintf(stderr, "ERROR: Couldn't allocate memory for computed_y(fit_mag_calib.c)\n");
  exit(1);
 };

 if( argc == 1 ) {
  strncpy(calibfilename, "calib.txt", FILENAME_LENGTH - 1);
 } else {
  strncpy(calibfilename, argv[1], FILENAME_LENGTH - 1);
 }
 calibfilename[FILENAME_LENGTH - 1]= '\0'; // just in case

 // Special case - read only the parameter file
 if( 0 == strncmp(calibfilename, "-q", FILENAME_LENGTH) ) {
  strcpy(calibfilename, "calib.txt_param");
  calibfile= fopen(calibfilename, "r");
  if( NULL == calibfile ) {
   fprintf(stderr, "ERROR: Cannot open file %s\n", calibfilename);
   return 1;
  }
  if( 5 > fscanf(calibfile, "%lf %lf %lf %lf %lf", &poly_coeff[4], &poly_coeff[3], &poly_coeff[2], &poly_coeff[1], &poly_coeff[0]) ) {
   fprintf(stderr, "ERROR parsing %s\n", calibfilename);
   return 1;
  }
  fit_function= (int)poly_coeff[4];
  A= poly_coeff[2];
  B= poly_coeff[1];
  C= poly_coeff[0];
  if( fit_function != 4 && fit_function != 5 ) {
   fprintf(stdout, "%lf %lf %lf\n", A, B, C);
  } else {
   fprintf(stdout, "%d %lf %lf %lf %lf\n", fit_function, poly_coeff[0], poly_coeff[1], poly_coeff[2], poly_coeff[3]);
  }
  return 0; // exit OK
 }

 /* Read data file */
 calibfile= fopen(calibfilename, "r");
 if( NULL == calibfile ) {
  fprintf(stderr, "ERROR: Cannot open file %s\n", calibfilename);
  free(insmag);
  free(finsmag);
  free(insmagerr);
  free(finsmagerr);
  free(catmag);
  free(fcatmag);
  free(w);
  free(computed_x);
  free(computed_y);
  return 1;
 }
 while( -1 < fscanf(calibfile, "%lf %lf %lf", &insmag[n_stars], &catmag[n_stars], &insmagerr[n_stars]) ) {
  finsmag[n_stars]= (float)insmag[n_stars];
  fcatmag[n_stars]= (float)catmag[n_stars];
  // Make sure insmagerr[n_stars] is not 0
  if( insmagerr[n_stars] == 0.0 ) {
   insmagerr[n_stars]= 0.03; // assume some thypical CCD photometry error
   //  Try to refine this wild guess by setting the error to the smallest significant value we have seen so far
   for( j= 0; j < n_stars; j++ ) {
    if( insmagerr[j] < insmagerr[n_stars] && insmagerr[j] > 0.0 ) {
     insmagerr[n_stars]= insmagerr[j];
    }
   }
  }
  // -------------------------------------
  finsmagerr[n_stars]= (float)insmagerr[n_stars];
  w[n_stars]= 1.0 / (insmagerr[n_stars] * insmagerr[n_stars]);
  n_stars++;
 }
 fclose(calibfile);
 
 if( n_stars==0 ) {
  fprintf(stderr, "ERROR: the input calibration file %s is empty - there are no calibration stars!\n", calibfilename );
  free(insmag);
  free(finsmag);
  free(insmagerr);
  free(finsmagerr);
  free(catmag);
  free(fcatmag);
  free(w);
  free(computed_x);
  free(computed_y);
  return 1;
 }

 // Set limits for plotting 
 mininstmag= maxinstmag= finsmag[0];
 mincatmag= maxcatmag= fcatmag[0];
 for( j= 0; j < n_stars; j++ ) {
  mininstmag= MIN(mininstmag, finsmag[j]);
  maxinstmag= MAX(maxinstmag, finsmag[j]);
  mincatmag= MIN(mincatmag, fcatmag[j]);
  maxcatmag= MAX(maxcatmag, fcatmag[j]);
 }
 // fprintf(stderr,"mininstmag=%lf maxinstmag=%lf mincatmag=%lf maxcatmag=%lf",mininstmag,maxinstmag,mincatmag,maxcatmag);

 // Special one-star mode 
 if( n_stars == 1 ) {
  fprintf(stdout, "%lf %lf %lf\n", 0.0, 1.0, (catmag[0]) - (insmag[0]));
  //
  free(computed_x);
  free(computed_y);
  free(catmag);
  free(fcatmag);
  free(w);
  free(insmagerr);
  free(finsmag);
  free(insmag);
  free(finsmagerr);
  //
  return 0;
 }

 // set operating mode if non-interactive options are requested
 if( 0 == strcmp("fit_linear", basename(argv[0])) ) {
  operation_mode= 1;
  fit_function= 1;
  gsl_fit_wlinear(insmag, 1, w, 1, catmag, 1, n_stars, &C, &B, &cov00, &cov01, &cov11, &sumsqres);
  poly_coeff[7]= poly_coeff[6]= poly_coeff[5]= poly_coeff[4]= poly_coeff[3]= poly_coeff[2]= poly_coeff[1]= poly_coeff[0]= 0.0;
  A= 0.0;
  poly_coeff[0]= C;
  poly_coeff[1]= B;
 }
 if( 0 == strcmp("fit_robust_linear", basename(argv[0])) ) {
  operation_mode= 4;
  fit_function= 6;
  poly_coeff[7]= poly_coeff[6]= poly_coeff[5]= poly_coeff[4]= poly_coeff[3]= poly_coeff[2]= poly_coeff[1]= poly_coeff[0]= 0.0;
  robustlinefit(insmag, catmag, n_stars, poly_coeff);
  A= 0.0;
  B= poly_coeff[1];
  C= poly_coeff[0];
 }
 if( 0 == strcmp("fit_zeropoint", basename(argv[0])) ) {
  operation_mode= 1;
  fit_function= 3;
  A= 0.0;
  B= 1.0;
  sum1= sum2= 0.0;
  for( j= 0; j < n_stars; j++ ) {
   sum1+= w[j] * (catmag[j] - insmag[j]);
   sum2+= w[j];
  }
  C= sum1 / sum2;
  poly_coeff[7]= poly_coeff[6]= poly_coeff[5]= poly_coeff[4]= poly_coeff[3]= poly_coeff[2]= poly_coeff[1]= poly_coeff[0]= 0.0;
  poly_coeff[0]= C;
  poly_coeff[1]= B;
 }
 if( 0 == strcmp("fit_photocurve", basename(argv[0])) ) {
  operation_mode= 2;
  fit_function= 4;
  poly_coeff[7]= poly_coeff[6]= poly_coeff[5]= poly_coeff[4]= poly_coeff[3]= poly_coeff[2]= poly_coeff[1]= poly_coeff[0]= 0.0;
  fit_photocurve(insmag, catmag, insmagerr, n_stars, poly_coeff, &fit_function, NULL);
 }

 // Go interactive
 if( operation_mode == 0 ) {

  // Choose fitting function -- this never worked aprticularly well
  //choose_fittting_function(insmag, catmag, n_stars, &fit_function);

  /* GUI */
  setenv_localpgplot(argv[0]);
  strcpy(PGPLOT_CONTROL, "/XW");
  if( cpgbeg(0, PGPLOT_CONTROL, 1, 1) != 1 )
   return EXIT_FAILURE;

  do {

   cpgscr(0, 0.10, 0.31, 0.32); /* set default vast window background */

   if( change_limits_trigger == 0 ) {
    cpgpage();
   }

   cpgeras();
   cpgsvp(0.08, 0.95, 0.1, 0.9);
   if( change_limits_trigger == 2 || change_limits_trigger == 0 ) {
    old_Y1= mincatmag - (maxcatmag - mincatmag) / 10;
    old_Y2= maxcatmag + (maxcatmag - mincatmag) / 10;
    new_Y1= old_Y1;
    new_Y2= old_Y2;

    old_X1= mininstmag - (maxinstmag - mininstmag) / 10;
    old_X2= maxinstmag + (maxinstmag - mininstmag) / 10;
    new_X1= old_X1;
    new_X2= old_X2;
   }

   cpgswin(new_X1, new_X2, new_Y1, new_Y2);
   cpgscr(0, 0.08, 0.08, 0.09); /* set background */
   cpgsci(0);
   cpgrect(new_X1, new_X2, new_Y1, new_Y2);
   cpgsci(1);
   cpgscf(1);
   cpgbox("BCNST1", 0.0, 0, "BCNST1", 0.0, 0);

   /* Processing */
   A= B= C= 0.0;
   //cov22=cov11=cov00=0.0;
   cov11= cov00= 0.0;

   if( argc == 3 ) {
    /* Just read A, B and C from input file */
    strncpy(calibfilename, argv[2], FILENAME_LENGTH - 1);
    calibfilename[FILENAME_LENGTH - 1]= '\0'; // just in case
    fprintf(stderr, "Reading fitting coefficients from file %s\n", calibfilename);
    calibfile= fopen(calibfilename, "r");
    if( NULL == calibfile ) {
     fprintf(stderr, "ERROR: Cannot open file %s\n", calibfilename);
     exit(1);
    }
    if( 5 > fscanf(calibfile, "%lf %lf %lf %lf %lf", &poly_coeff[4], &poly_coeff[3], &poly_coeff[2], &poly_coeff[1], &poly_coeff[0]) ) {
     fprintf(stderr, "ERROR parsing %s\n", calibfilename);
     exit(1);
    }
    if( poly_coeff[4] == 4.0 || poly_coeff[4] == 5.0 ) {
     fit_function= (int)poly_coeff[4];
    } else {
     A= poly_coeff[2];
     B= poly_coeff[1];
     C= poly_coeff[0];
     if( A == 0.0 )
      fit_function= 1;
     else
      fit_function= 2;
     fprintf(stderr, "%lf %lf %lf   %d\n", A, B, C, fit_function);
    }
    fclose(calibfile);
   } else {
    /* Compute A, B and C using current fitting function */
    if( fit_function == 1 ) {
     gsl_fit_wlinear(insmag, 1, w, 1, catmag, 1, n_stars, &C, &B, &cov00, &cov01, &cov11, &sumsqres);
     poly_coeff[7]= poly_coeff[6]= poly_coeff[5]= poly_coeff[4]= poly_coeff[3]= poly_coeff[2]= poly_coeff[1]= poly_coeff[0]= 0.0;
     poly_coeff[0]= C;
     poly_coeff[1]= B;
    }
    if( fit_function == 2 ) {
     poly_coeff[7]= poly_coeff[6]= poly_coeff[5]= poly_coeff[4]= poly_coeff[3]= poly_coeff[2]= poly_coeff[1]= poly_coeff[0]= 0.0;
     wpolyfit(insmag, catmag, insmagerr, n_stars, poly_coeff, &sumsqres);
     A= poly_coeff[2];
     B= poly_coeff[1];
     C= poly_coeff[0];
     cov00= poly_coeff[5];
     cov11= poly_coeff[6];
    }
    //
    if( fit_function == 3 ) {
     B= 1.0;
     sum1= sum2= 0.0;
     for( j= 0; j < n_stars; j++ ) {
      sum1+= w[j] * (catmag[j] - insmag[j]);
      sum2+= w[j];
     }
     C= sum1 / sum2;
     poly_coeff[7]= poly_coeff[6]= poly_coeff[5]= poly_coeff[4]= poly_coeff[3]= poly_coeff[2]= poly_coeff[1]= poly_coeff[0]= 0.0;
     poly_coeff[0]= C;
     poly_coeff[1]= B;
    }
    if( fit_function == 4 || fit_function == 5 ) {
     poly_coeff[7]= poly_coeff[6]= poly_coeff[5]= poly_coeff[4]= poly_coeff[3]= poly_coeff[2]= poly_coeff[1]= poly_coeff[0]= 0.0;
     fit_photocurve(insmag, catmag, insmagerr, n_stars, poly_coeff, &fit_function, NULL);
    }
    if( fit_function == 6 ) {
     poly_coeff[7]= poly_coeff[6]= poly_coeff[5]= poly_coeff[4]= poly_coeff[3]= poly_coeff[2]= poly_coeff[1]= poly_coeff[0]= 0.0;
     robustlinefit(insmag, catmag, n_stars, poly_coeff);
     A= 0.0;
     B= poly_coeff[1];
     C= poly_coeff[0];
    }
   }
   //

   /* Print plot header */
   cpgscf(1);
   cpgsch(1.0); /* make lables with normal characters */
   sprintf(header_str, "fitting function: y=");
   if( A != 0.0 ) {
    sprintf(header_str2, "%lf\\(0729)x\\u2\\d", A);
    strcat(header_str, header_str2);
    sprintf(header_str2, "%+lf\\(0729)x", B);
    strcat(header_str, header_str2);
   } else {
    sprintf(header_str2, "%lf\\(0729)x", B);
    strcat(header_str, header_str2);
   }
   sprintf(header_str2, "%+lf", C);
   strcat(header_str, header_str2);

   if( fit_function == 4 ) {
    sprintf(header_str, "fitting function: y=%.5lf*log\\d10\\u(10\\u%.5lf*(x-(%.5lf))\\d+1)+(%.5lf)", poly_coeff[0], poly_coeff[1], poly_coeff[2], poly_coeff[3]);
   }
   if( fit_function == 5 ) {
    sprintf(header_str, "fitting function: x=%.5lf*log\\d10\\u(10\\u%.5lf*(y-(%.5lf))\\d+1)+(%.5lf)", poly_coeff[0], poly_coeff[1], poly_coeff[2], poly_coeff[3]);
   }

   /* If we don't read parameters from input file... */
   if( argc != 3 && fit_function != 4 && fit_function != 5 ) {
    sprintf(header_str2, "  press 'P' to change fitting function");
    strcat(header_str, header_str2);
   }

   // robust linear fit uuses no weights
   if( fit_function != 6 ) {
    cpgmtxt("T", 2.0, 0.0, 0.0, header_str);
    sprintf(header_str, "use weights: ");
    if( weights_on == 1 ) {
     strcat(header_str, "yes");
    } else {
     strcat(header_str, " no");
    }
    // If we don't read parameters from input file... 
    if( argc != 3 ) {
     strcat(header_str, "  press 'W' to change it");
    }
   } else {
    cpgmtxt("T", 2.0, 0.0, 0.0, header_str);
    sprintf(header_str, "robust linear fit does not use weights");
   }
   
   cpgmtxt("T", 1.0, 0.0, 0.0, header_str);
   cpglab("Instrumental magnitude", "Catalog magnitude", "");
   cpgscr(1, 1.0, 1.0, 1.0);
   cpgsch(1.0);

   /* Compute best fit function */
   if( fit_function != 4 && fit_function != 5 ) {
    /* line or parabola */
    computed_x[0]= mininstmag;
    computed_y[0]= A * computed_x[0] * computed_x[0] + B * computed_x[0] + C;
    for( j= 1; j < MAX_NUMBER_OF_STARS_MAG_CALIBR; j++ ) {
     computed_x[j]= computed_x[j - 1] + (maxinstmag - mininstmag) / MAX_NUMBER_OF_STARS_MAG_CALIBR;
     computed_y[j]= A * computed_x[j] * computed_x[j] + B * computed_x[j] + C;
    }
   } else {
    /* photocurve or inverse photocurve */
    computed_x[0]= mininstmag;
    computed_y[0]= (float)eval_photocurve((double)computed_x[0], poly_coeff, fit_function);
    for( j= 1; j < MAX_NUMBER_OF_STARS_MAG_CALIBR; j++ ) {
     computed_x[j]= computed_x[j - 1] + (maxinstmag - mininstmag) / MAX_NUMBER_OF_STARS_MAG_CALIBR;
     computed_y[j]= (float)eval_photocurve((double)computed_x[j], poly_coeff, fit_function);
    }
   }

   /* Draw data points */
   cpgsci(2); // red
   for( j= 0; j < n_stars; j++ ) {
    cpgerr1(6, finsmag[j], fcatmag[j], finsmagerr[j], 1.0);
   }
   cpgpt(n_stars, finsmag, fcatmag, 17);

   /* Draw best fit curve */
   cpgsci(3); // green
   cpgline(MAX_NUMBER_OF_STARS_MAG_CALIBR, computed_x, computed_y);

   cpgsci(5);
   cpgcurs(&curX, &curY, &curC);
   /* Zoom */
   if( curC == 'Z' || curC == 'z' ) {
    cpgband(2, 0, curX, curY, &curX2, &curY2, &curC);
    if( new_X1 != 0.0 ) {
     old_X1= new_X1;
     old_X2= new_X2;
    }
    new_X1= curX;
    new_Y1= curY;

    if( curC == 'Z' || curC == 'z' )
     curC= 'D';

    if( curX2 > new_X1 )
     new_X2= curX2;
    else {
     new_X2= new_X1;
     new_X1= curX2;
    }
    if( curY2 > new_Y1 )
     new_Y2= curY2;
    else {
     new_Y2= new_Y1;
     new_Y1= curY2;
    }

   } /* End of Zoom */

   change_limits_trigger= 1;

   if( curC == 'D' || curC == 'd' ) {
    change_limits_trigger= 2;
   }

   /* Use/don't use weights */
   if( curC == 'W' || curC == 'w' ) {
    if( weights_on == 1 ) {
     weights_on= 0;
     for( j= 0; j < n_stars; j++ ) {
      w[j]= 1.0;
      insmagerr[j]= 0.01;
     }
    } else {
     weights_on= 1;
     for( j= 0; j < n_stars; j++ ) {
      insmagerr[j]= (double)finsmagerr[j];
      w[j]= 1.0 / (insmagerr[j] * insmagerr[j]);
     }
    }
   }

   /* Change fitting function */
   if( curC == 'P' || curC == 'p' ) {
    fit_function++;
    if( fit_function == 4 || fit_function == 5 ) {
     fit_function++;
    }
    if( fit_function > 6 ) {
     fit_function= 1;
    }
//    if( fit_function > 4 )
//     fit_function= 1;
   }

   y_to_x_scaling_factor= fabsf(new_X2 - new_X1) / fabsf(new_Y2 - new_Y1);

   /* Remove point */
   if( curC == 'R' || curC == 'r' ) {
    /* find closest point */
    best_dist= 999.9 * 999.9;
    remove_best_j= n_stars; // by default - don't remove anything
    for( j= 0; j < n_stars; j++ ) {
     if( (finsmag[j] - curX) * (finsmag[j] - curX) + (fcatmag[j] - curY) * (fcatmag[j] - curY) * y_to_x_scaling_factor * y_to_x_scaling_factor < best_dist ) {
      best_dist= (finsmag[j] - curX) * (finsmag[j] - curX) + (fcatmag[j] - curY) * (fcatmag[j] - curY) * y_to_x_scaling_factor * y_to_x_scaling_factor;
      remove_best_j= j;
     }
    }
    /* remove it */
    for( j= remove_best_j; j < n_stars; j++ ) {
     insmag[j]= insmag[j + 1];
     finsmag[j]= finsmag[j + 1];
     catmag[j]= catmag[j + 1];
     fcatmag[j]= fcatmag[j + 1];
     insmagerr[j]= insmagerr[j + 1];
     finsmagerr[j]= finsmagerr[j + 1];
     w[j]= w[j + 1];
    }
    n_stars--; // ?
   }

   /* Remove all data points within a user-specified rectangular region */
   if( curC == 'C' || curC == 'c' ) {
    cpgsci(2);
    cpgband(2, 0, curX, curY, &curX2, &curY2, &curC);
    // last chance to cancel!
    if( curC != 'X' && curC != 'x' ) {
     for( j= 0; j < n_stars; j++ ) {
      if( finsmag[j] > MIN(curX, curX2) && finsmag[j] < MAX(curX, curX2) && fcatmag[j] > MIN(curY, curY2) && fcatmag[j] < MAX(curY, curY2) ) {
       /* remove it */
       for( k= j; k < n_stars; k++ ) {
        insmag[k]= insmag[k + 1];
        finsmag[k]= finsmag[k + 1];
        catmag[k]= catmag[k + 1];
        fcatmag[k]= fcatmag[k + 1];
        insmagerr[k]= insmagerr[k + 1];
        finsmagerr[k]= finsmagerr[k + 1];
        w[k]= w[k + 1];
       }
       n_stars--; // ?
       j--;
      }
     }
    }
    curC= ' ';
   }

  } while( curC != 'X' && curC != 'x' );

 } // if( operation_mode==0 ){

 //
 free(computed_x);
 free(computed_y);
 free(catmag);
 free(fcatmag);
 free(w);
 free(insmagerr);
 free(finsmag);
 free(insmag);
 free(finsmagerr);
 //

 if( fit_function != 4 && fit_function != 5 ) {
  fprintf(stdout, "%lf %lf %lf\n", A, B, C);
  // Check for an obviously bad fit
  if( A == 0.0 && B == 0.0 && C == 0.0 ) {
   fprintf(stderr, "ERROR in %s -- A == 0.0 && B == 0.0 && C == 0.0\n", argv[0]);
   return 1;
  }
  //
 } else {
  fprintf(stdout, "%d %lf %lf %lf %lf\n", fit_function, poly_coeff[0], poly_coeff[1], poly_coeff[2], poly_coeff[3]);
 }

 calibfile= fopen("calib.txt_param", "w");
 if( NULL == calibfile ) {
  fprintf(stderr, "ERROR opening the output file calib.txt_param for writing!\n");
  return 1;
 }
 fprintf(calibfile, "%lf %lf %lf %lf %lf\n", (double)fit_function, poly_coeff[3], poly_coeff[2], poly_coeff[1], poly_coeff[0]);
 fclose(calibfile);
 fprintf(stderr, "The calibration function type and coefficients are written to calib.txt_param\n");
 return 0;
}
