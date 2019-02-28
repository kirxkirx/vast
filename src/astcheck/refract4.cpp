/* refract4.cpp: functions for very precise refraction computations

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
#include "watdefs.h"
#include "afuncs.h"


/*
         All references are to the _Explanatory Supplement to the
         Astronomical Almanac_,  pages 141-143

   The following code basically follows the algorithm set forth in
the above reference.  I did modify it a little by not exactly using
Simpson's rule for integration in its "usual" form.  Instead,  the
code uses Simpson's rule over a given interval,  and compares the
result to that which you would get from the trapezoidal rule
(integral evaluated using just the endpoints.)  If the difference is
greater than a certain tolerance,  the region is split in half and
the total_refraction() function recurses.

   The benefit of this is that the region is recursively subdivided,
with most of the evaluation being done in the places where the
function is changing most rapidly.  I'm sure it's not an original
idea,  but it does seem to improve performance a bit.

   Another benefit comes into play when the iterative procedure at
(3.281-5) is done,  to determine the value of 'r' corresponding to
a given value of 'z'.  With this "subdivision" technique,  we're
looking at an intermediate value of z (between the two endpoints),
and an excellent starting point is the intermediate value of r.
This better initial value in the iteration saves us a few steps.
*/

#define PI 3.1415926535897932384626433
            /* Constants from p 142, (3.281-3): */
#define R   8314.36
#define Md    28.966
#define Mw    18.016
#define delta 18.36
#define re 6378120.
                /* ht = height of troposphere,  in meters */
#define ht 11000.
                /* hs = height of stratosphere,  in meters */
#define hs 80000.
#define alpha .0065
#define rt (re + ht)
#define rs (re + hs)

#define REFRACT struct refract
#define LOCALS  struct locals

REFRACT
   {
   double temp_0, n0_r0_sin_z0;
   double r0, c2, gamma, c6, c7, c8, c9, nt;
   };

LOCALS
   {
   double z, r, n, dn_dr, integrand;
   };

static void compute_refractive_index( const REFRACT *ref, LOCALS *loc,
                      const int is_troposphere)
{
   if( is_troposphere)
      {                                   /* (3.281-6) */
      const double temp_fraction = 1. - alpha * (loc->r - ref->r0) / ref->temp_0;
      const double gamma_term = pow( temp_fraction, ref->gamma - 2.);
      const double delta_term = pow( temp_fraction, delta - 2.);

      loc->n = 1. + temp_fraction * (ref->c6 * gamma_term - ref->c7 * delta_term);
      loc->dn_dr = -ref->c8 * gamma_term + ref->c9 * delta_term;
      }
   else                                   /* (3.281-7) */
      {
      const double temp_t = ref->temp_0 - alpha * (rt - ref->r0);
      const double exp_term =
                (ref->nt - 1.) * exp( -ref->c2 * (loc->r - rt) / temp_t);

      loc->n = 1. + exp_term;
      loc->dn_dr = -(ref->c2 / temp_t) * exp_term;
      }
}

static void compute_integrand( LOCALS *loc)
{
   const double r_dn_dr = loc->r * loc->dn_dr;

   loc->integrand = r_dn_dr / (loc->n + r_dn_dr);   /* (3.281-8) */
}

static double total_refraction( const REFRACT *ref,
        const LOCALS *l1, const LOCALS *l2, const int is_troposphere)
{
   LOCALS mid;
   double change;
   const double iteration_limit = 1.;     /* get 'r' within a meter */
   const double integration_tolerance = .0001;

   mid.z = (l1->z + l2->z) * .5;
   mid.r = (l1->r + l2->r) * .5;
   do
      {
      compute_refractive_index( ref, &mid, is_troposphere);
      change = -(mid.n * mid.r - ref->n0_r0_sin_z0 / sin( mid.z));
      change /= mid.n + mid.r * mid.dn_dr;           /* (3.281-5) */
      mid.r += change;
      }
      while( fabs( change) > iteration_limit);

   compute_integrand( &mid);
            /* Compute difference between a Simpson's rule integration */
            /* and a trapezoidal one... */
   change = 2. * mid.integrand - (l1->integrand + l2->integrand);
            /* ...and if it's too great,  recurse with each half: */
   if( fabs( change) > integration_tolerance)
      return( total_refraction( ref, l1, &mid, is_troposphere)
            + total_refraction( ref, &mid, l2, is_troposphere));
   else
      {                    /* Simpson's rule is good enough: */
      const double h = (l2->z - l1->z) / 6.;

      return( h * (4. * mid.integrand + l1->integrand + l2->integrand));
      }
}

double DLL_FUNC integrated_refraction( const double latitude,
                  const double observed_alt, const double wavelength_microns,
                  const double height_in_meters, const double rel_humid_pct,
                  const double temp_kelvins, const double pressure_mb)
{
   const double g_bar = 9.784 * (1. - .0026 * cos( 2. * latitude)
                        - 2.8e-7 * height_in_meters);      /* (3.281-4) */
   const double Pw0 = rel_humid_pct * pow( temp_kelvins / 247.1, delta) / 100.;
   const double l2 = wavelength_microns * wavelength_microns;
   const double A = (273.15e-6 / 1013.25)
                        * (287.607 + 1.6288 / l2 + .0136 / (l2 * l2));
   REFRACT ref;
   double c5, rval;
   LOCALS l0, lt, ls;

   ref.r0 = re + height_in_meters;
   ref.c2 = g_bar * Md / R;
   ref.gamma = ref.c2 / alpha;    /* = C3 */
   c5 = Pw0 * (1. - Mw / Md) * ref.gamma / (delta - ref.gamma);
   ref.c6 = A * (pressure_mb + c5) / temp_kelvins;
   ref.c7 = (A * c5 + 11.2684e-6 * Pw0) / temp_kelvins;
   ref.c8 = alpha * (ref.gamma - 1.) * ref.c6 / temp_kelvins;
   ref.c9 = alpha * (delta - 1.) * ref.c7 / temp_kelvins;
   ref.temp_0 = temp_kelvins;

   l0.r = ref.r0;
   compute_refractive_index( &ref, &l0, 1);
   l0.z = PI / 2. - observed_alt;
   compute_integrand( &l0);

   lt.r = rt;
   compute_refractive_index( &ref, &lt, 1);
   lt.z = asin( l0.n * ref.r0 * sin( l0.z) / (lt.n * rt));     /* (3.281-9) */
   compute_integrand( &lt);

   ref.nt = lt.n;
   ref.n0_r0_sin_z0 = l0.n * l0.r * sin( l0.z);
   rval = total_refraction( &ref, &l0, &lt, 1);

         /* Now for the stratospheric portion... we need to recompute */
         /* dn/dr at the tropopause, because there's a discontinuity  */
         /* in the derivative as r crosses that point;  which also    */
         /* means we gotta recompute the integrand at r = rt.  So:    */
   compute_refractive_index( &ref, &lt, 0);
   compute_integrand( &lt);

   ls.r = rs;
   compute_refractive_index( &ref, &ls, 0);
   ls.z = asin( ls.n * ref.r0 * sin( l0.z) / (ls.n * rs));
   compute_integrand( &ls);

   return( rval + total_refraction( &ref, &lt, &ls, 0));
}

double DLL_FUNC reverse_integrated_refraction( const double latitude,
                  const double refracted_alt, const double wavelength_microns,
                  const double height_in_meters, const double rel_humid_pct,
                  const double temp_kelvins, const double pressure_mb)
{
            /* start out with an initial "primitive" guess: */
   double rval = reverse_refraction( refracted_alt)
                     * (pressure_mb / 1010.) * (283. / temp_kelvins);

   double change;
   const double tolerance = .1 * PI / (180. * 3600.);     /* .1 arcsec */

   do
      {
      double new_val = integrated_refraction( latitude, refracted_alt + rval,
                           wavelength_microns, height_in_meters,
                           rel_humid_pct, temp_kelvins, pressure_mb);

      change = rval - new_val;
      rval = new_val;
      }
   while( change > tolerance || change < -tolerance);

   return( rval);
}

#ifdef TEST_MAIN
#include <stdio.h>
#include <stdlib.h>

int main( const int argc, const char **argv)
{
   int i, diff_mode = 0;
   double pressure_mb = 1013.,  temp_kelvin = 293., relative_humidity = .2;
   double wavelength_microns = .574, height_in_meters = 100.;

   for( i = 2; i < argc; i++)
      switch( argv[i][0])
         {
         case 'p':
            pressure_mb = atof( argv[i] + 1);
            break;
         case 't':
            temp_kelvin = atof( argv[i] + 1) + 273.;
            break;
         case 'h':
            relative_humidity = atof( argv[i] + 1);
            break;
         case 'l':                  /* allow entry in nm */
            wavelength_microns = atof( argv[i] + 1) / 1000.;
            break;
         case 'a':
            height_in_meters = atof( argv[i] + 1);
            break;
         case 'd':
            diff_mode = 1;
            break;
         default:
            printf( "? Didn't understand argument '%s'\n", argv[i]);
            break;
         }
   for( i = -1; i < 90; i++)
      {
      const double rad_to_arcmin = 180. * 60. / PI;
      double observed_alt = (i == -1 ? atof( argv[1]) : (double)i) * PI / 180.;
      const double primitive_mul = (pressure_mb / 1010.) * (283. / temp_kelvin);
      double primitive = primitive_mul * refraction( observed_alt);
      double saasta = saasta_refraction( observed_alt, pressure_mb, temp_kelvin,
                          relative_humidity);
      double integrated =
            integrated_refraction( PI / 4., observed_alt, wavelength_microns,
                   height_in_meters, 100. * relative_humidity, temp_kelvin,
                   pressure_mb);

      if( i == -1 && observed_alt)
         {
         printf( "Primitive refraction:  %9.5lf\n",
                                    primitive * rad_to_arcmin) ;
         primitive = reverse_refraction( observed_alt - primitive);
         printf( "Primitive refraction reversed: %9.5lf\n",
                      primitive * primitive_mul * rad_to_arcmin);
         printf( "Saasta refraction:     %9.5lf\n", saasta * rad_to_arcmin);
         saasta = reverse_saasta_refraction( observed_alt - saasta,
                          pressure_mb, temp_kelvin,
                          relative_humidity);
         printf( "Saasta refraction (reversed):     %9.5lf\n",
                          saasta * rad_to_arcmin);
         printf( "Integrated refraction: %9.5lf\n",
                          integrated * rad_to_arcmin);
         integrated = reverse_integrated_refraction( PI / 4.,
                           observed_alt - integrated, wavelength_microns,
                           height_in_meters, 100. * relative_humidity,
                           temp_kelvin, pressure_mb);
         printf( "Reverse integrated:    %9.5lf\n",
                          integrated * rad_to_arcmin);
         }
      else if( i > -1 && argv[1][0] == 't')
         {
         if( diff_mode)
            {
            primitive -= integrated;
            saasta -= integrated;
            }
         printf( "%2d: %9.5lf %9.5lf %9.5lf\n", i,
                       primitive * rad_to_arcmin,
                       saasta * rad_to_arcmin,
                       integrated * rad_to_arcmin);
         }
      }
}
#endif
