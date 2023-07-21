/*

   The following code is based on:

   NOVAS-C Version 3.0
   Solar System function; version 3.

   Naval Observatory Vector Astrometry Software
   C Version

   U. S. Naval Observatory
   Astronomical Applications Dept.
   3450 Massachusetts Ave., NW
   Washington, DC  20392-5420
*/

#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#include "novas.h"
#include "eph_manager.h" /* remove this line for use with solsys version 2 */

// The following function is declared in solsys3.c
void sun_eph(double jd, double *ra, double *dec, double *dis);

double hjd_N(double ra_obj_d, double dec_obj_d, double jd_tt) {
 double ra_obj_rad= ra_obj_d / RAD2DEG;
 double ra_obj_h= ra_obj_d / 15;
 double dec_obj_rad= dec_obj_d / RAD2DEG;
 double ra_sun_h;
 double ra_sun_d;
 double ra_sun_rad;
 double dec_sun_d;
 double dec_sun_rad;
 double dist_sun;
 double jd_correction;
 double hjd_tt;

 /* Compute apparent position of a star */
 short int error= 0;
 cat_entry star;
 ////make_cat_entry("STAR","HIP",0,ra_obj_h,dec_obj_d,0,0,0,0, &star);
 //make_cat_entry("STAR","FK6",0,ra_obj_h,dec_obj_d,0,0,0,0, &star);
 double pm_ra_mas_per_year= 0.0;
 double pm_dec_mas_per_year= 0.0;
 double parallax_mas= 0.0;
 double rv_kms= 0.0;
 //
 char word_star[SIZE_OF_OBJ_NAME];
 char word_catalog[SIZE_OF_CAT_NAME];
 strncpy(word_star,"STAR",SIZE_OF_OBJ_NAME);
 word_star[SIZE_OF_OBJ_NAME-1]='\0';
 strncpy(word_catalog,"FK6",SIZE_OF_CAT_NAME);
 word_catalog[SIZE_OF_CAT_NAME-1]='\0';
 //
 //make_cat_entry("STAR", "FK6", 0, ra_obj_h, dec_obj_d, pm_ra_mas_per_year, pm_dec_mas_per_year, parallax_mas, rv_kms, &star);
 make_cat_entry(word_star, word_catalog, 0, ra_obj_h, dec_obj_d, pm_ra_mas_per_year, pm_dec_mas_per_year, parallax_mas, rv_kms, &star);
 error= app_star(jd_tt, &star, 1, &ra_obj_h, &dec_obj_d);
 if( error != 0 )
  fprintf(stderr, "ERROR: %d\n", error);
 // OK ra_obj_d is not used anymore, but ra_obj_rad and dec_obj_rad are used!
 ra_obj_d= ra_obj_h * 15;
 ra_obj_rad= ra_obj_d / RAD2DEG;
 dec_obj_rad= dec_obj_d / RAD2DEG;

 // Compute apparent position of the Sun //
 sun_eph(jd_tt, &ra_sun_h, &dec_sun_d, &dist_sun);
 ra_sun_d= ra_sun_h * 360 / 24;
 ra_sun_rad= ra_sun_d / RAD2DEG;
 dec_sun_rad= dec_sun_d / RAD2DEG;

 //fprintf(stderr,"Geocentric distance of the Sun: %.10lf AU\n",dist_sun);

 // Compute and apply Heliocentric correction //
 jd_correction= -1 * dist_sun / C_AUDAY * (sin(dec_obj_rad) * sin(dec_sun_rad) + cos(dec_obj_rad) * cos(dec_sun_rad) * cos(ra_obj_rad - ra_sun_rad));
 hjd_tt= jd_tt + jd_correction;

 return hjd_tt;
}
