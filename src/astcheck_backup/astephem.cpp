/* astephem.cpp: example program for computing asteroid ephems

Copyright (C) 2010, Project Pluto

This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
02110-1301, USA.    */

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "watdefs.h"
#include "date.h"
#include "comets.h"
#include "afuncs.h"

/* ASTEPHEM.CPP

   This is basically a way of showing how the asteroid/comet computations
are done in ASTFUNCS.CPP.  Date functions from DAT.CPP and the Earth's
J2000.0 position from EART2000.CPP are also used.

*/

#define ASTORB_RECORD_LEN 268

#define PI 3.14159265358979323
#define LOG_10 2.302585

int get_earth_loc( const double t_millenia, double *results);

long extract_astorb_dat( ELEMENTS *elem, const char *buff);

static inline double law_of_cosines( const double a, const double b, const double c)
{
   return( .5 * (a * a + b * b - c * c) / (a * b));
}

static double calc_obs_magnitude( ELEMENTS *elem, const double obj_sun,
                      const double obj_earth, const double earth_sun)
{
   double magnitude;

   if( !elem->is_asteroid)
      magnitude = elem->slope_param * log( obj_sun);
   else
      {
      const double cos_phase_ang =
                  law_of_cosines( obj_sun, obj_earth, earth_sun);
      const double half_phase_ang = acose( cos_phase_ang) / 2.;
      const double log_tan_half_phase = log( tan( half_phase_ang));
      const double phi1 = exp( -3.33 * exp( log_tan_half_phase * 0.63));
      const double phi2 = exp( -1.87 * exp( log_tan_half_phase * 1.22));

      magnitude = 5. * log( obj_sun)
                           -2.5 * log( (1. - elem->slope_param) * phi1
                                            + elem->slope_param * phi2);
      }
   magnitude += 5. * log( obj_earth);
   magnitude /= LOG_10;      /* cvt from natural logs to common (base 10) */
   magnitude += elem->abs_mag;
   return( magnitude);
}

int main( int argc, char **argv)
{
   double t, dt, dist, x, y, z, ra, dec;
   double earth_loc[6];
   double asteroid_loc[4];
   int day, month = 0, i, j, n_intervals, asteroid_no;
   long year, ra_sec_tenths;
   ELEMENTS class_elem;
   FILE *ifile = fopen( "astorb.dat", "rb");
   char tbuff[300];
   char month_str[30];
   const double sin_obliq_2000 = .397777156;
   const double cos_obliq_2000 = .917482062;

   if( !ifile)
      {
      printf( "Couldn't find 'astorb.dat'\n");
      exit( -1);
      }

   while( !month)
      {
      printf( "Enter the starting day,  month,  and year (example: 21 Apr 1992): ");
      scanf( "%d %s %ld", &day, month_str, &year);
      for( i = 0; i < 12; i++)
         if( !strcmp( month_str, set_month_name( i + 1, NULL)))
            month = i + 1;
      if( !month)
         printf( "Not a valid month.  Try again.\n");
      }

   t = (double)dmy_to_day( day, month, year, 0) + .5;
   printf( "Enter the step size,  in days (or decimal fractions of a day): ");
   scanf( "%lf", &dt);
   printf( "Enter the number of the asteroid: ");
   scanf( "%d", &asteroid_no);

   fseek( ifile, (asteroid_no - 1) * ASTORB_RECORD_LEN, SEEK_SET);
   fgets( tbuff, sizeof( tbuff), ifile);
   fclose( ifile);

   if( !extract_astorb_dat( &class_elem, tbuff))
      {
      printf( "Didn't get asteroid data\n");
      exit( -1);
      }

   printf( "Enter the number of positions desired: ");
   scanf( "%d", &n_intervals);
   dist = 0.;

                           /* Step through the ephemeris:  */
   for( i = 0; i < n_intervals; i++, t += dt)
      {
      double mag, r1, r2, r3, elong;

                     /* The following function is in EART2000.CPP. */
      get_earth_loc( (t - 2451545.0) / 365250., earth_loc);
      r3 = -100.;    /* ensure at least one pass */

                     /* To deal with light-time lag,  an iterative process */
                     /* is necessary.  In truth,  I suspect this could be  */
                     /* replaced with a "for( i = 0; i < 2; i++)" loop (in */
                     /* other words,  do it twice.)                        */
      while( fabs( dist - r3) > .01)
         {
         r3 = dist;
         comet_posn( &class_elem, t - dist / AU_PER_DAY, asteroid_loc);
         dist = 0.;
         for( j = 0; j < 3; j++)
            {
            asteroid_loc[j] -= earth_loc[j];
            dist += asteroid_loc[j] * asteroid_loc[j];
            }
         dist = sqrt( dist);
         }
                           /* Convert the JD value to calendar format: */
      day_to_dmy( (long)(t + .5 + .00001), &day, &month, &year, 0);

                    /* The following method of getting a magnitude is  */
                    /* discussed in Meeus' _Astronomical Algorithms_*, */
                    /* pages 216 and 217.                              */
      r1 = dist;                                 /* home-target dist */
      r2 = earth_loc[5];                         /* home-sun dist */
      r3 = asteroid_loc[3];                      /* target-sun dist */
      mag = calc_obs_magnitude( &class_elem, r3, r1, r2);

                    /* Get the elongation from the Sun,  using the law */
                    /* of cosines.                                     */
      elong = acose( law_of_cosines( r1, r2, r3));

                     /* (x, y, z) = geocentric position of the asteroid, */
                     /* in Cartesian J2000 coords.                       */
      x = asteroid_loc[0];
      y = asteroid_loc[1] * cos_obliq_2000 - asteroid_loc[2] * sin_obliq_2000;
      z = asteroid_loc[1] * sin_obliq_2000 + asteroid_loc[2] * cos_obliq_2000;
                     /* Now convert that to RA/dec... */
      ra = atan2( y, x) * 180. / PI;
      if( ra < 0.) ra += 360.;
      dec = asin( z / dist) * 180. / PI;
      ra_sec_tenths = (long)(ra * 36000. / 15.);
                     /* ...and show me the data:  */
      sprintf( tbuff, "%2d %s %4ld:  %2ldh%02ldm%02ld.%lds   %3d %5.2lf'  %6.3lf  %6.3lf  %4.1lf %4.1lf\n",
              day, set_month_name( month, NULL), year,
              ra_sec_tenths / 36000L, (ra_sec_tenths / 600L) % 60L,
              (ra_sec_tenths / 10L) % 60L, ra_sec_tenths % 10L,
              (int)dec, 60. * (fabs( dec) - floor( fabs( dec))), dist,
              asteroid_loc[3], mag, elong * 180. / PI);
      if( i % 24 == 0)
         printf( "                  RA             dec     dist    radius  mag\n");
      printf( "%s", tbuff);
      }
   return( 0);
}
