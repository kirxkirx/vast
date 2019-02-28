/* classel.cpp: converts state vects to classical elements

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
#include "comets.h"

#define PI 3.141592653589793238462643383279502884197
#define SQRT_2 1.41421356

/* 2009 Nov 24:  noticed a loss of precision problem in computing arg_per.
   This was done by computing the cosine of that value,  then taking the
   arc-cosine.  But if that value is close to +/-1,  precision is lost
   (you can actually end up with a domain error if the roundoff goes
   against you).  I added code so that,  if |cos_arg_per| > .7,  we
   compute the _sine_ of the argument of periapsis and use that instead.

   While doing this,  I also noticed that several variables could be made
   of type const.   */

/* calc_classical_elements( ) will take a given state vector r at a time t,
   for an object orbiting a mass gm;  and will compute the orbital elements
   and store them in the elem structure.  Normally,  ref=1.  You can set
   it to 0 if you don't care about the angular elements (inclination,
   longitude of ascending node,  argument of perihelion).         */

int DLL_FUNC calc_classical_elements( ELEMENTS *elem, const double *r,
                             const double t, const int ref, const double gm)
{
   const double *v = r + 3;
   const double r_dot_v = r[0] * v[0] + r[1] * v[1] + r[2] * v[2];
   const double dist = sqrt( r[0] * r[0] + r[1] * r[1] + r[2] * r[2]);
   const double v2 = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
   const double inv_major_axis = 2. / dist - v2 / gm;
   double h0, n0;
   double h[3], e[3], ecc2;
   double ecc, perihelion_speed, gm_over_h0;
   int i;

   h[0] = r[1] * v[2] - r[2] * v[1];
   h[1] = r[2] * v[0] - r[0] * v[2];
   h[2] = r[0] * v[1] - r[1] * v[0];
   n0 = h[0] * h[0] + h[1] * h[1];
   h0 = n0 + h[2] * h[2];
   n0 = sqrt( n0);
   h0 = sqrt( h0);

                        /* See Danby,  p 204-206,  for much of this: */
   if( ref & 1)
      {
      elem->asc_node = atan2( h[0], -h[1]);
      elem->incl = asine( n0 / h0);
      if( h[2] < 0.)                   /* retrograde orbit */
         elem->incl = PI - elem->incl;
      }
   e[0] = (v[1] * h[2] - v[2] * h[1]) / gm - r[0] / dist;
   e[1] = (v[2] * h[0] - v[0] * h[2]) / gm - r[1] / dist;
   e[2] = (v[0] * h[1] - v[1] * h[0]) / gm - r[2] / dist;
   ecc2 = 0.;
   for( i = 0; i < 3; i++)
      ecc2 += e[i] * e[i];
   elem->minor_to_major = sqrt( fabs( 1. - ecc2));
   ecc = elem->ecc = sqrt( ecc2);
   for( i = 0; i < 3; i++)
      e[i] /= ecc;
   gm_over_h0 = gm / h0;
   perihelion_speed = gm_over_h0 + sqrt( gm_over_h0 * gm_over_h0
               - inv_major_axis * gm);
   elem->q = h0 / perihelion_speed;
   if( inv_major_axis)
      {
      elem->major_axis = 1. / inv_major_axis;
      elem->t0 = elem->major_axis * sqrt( fabs( elem->major_axis) / gm);
      }
   if( ref & 1)
      {
      const double cos_arg_per = (h[0] * e[1] - h[1] * e[0]) / n0;

      if( cos_arg_per < .7 && cos_arg_per > -.7)
         elem->arg_per = acos( cos_arg_per);
      else
         {
         const double sin_arg_per =
               (e[0] * h[0] * h[2] + e[1] * h[1] * h[2] - e[2] * n0 * n0)
                                            / (n0 * h0);

         elem->arg_per = fabs( asin( sin_arg_per));
         if( cos_arg_per < 0.)
            elem->arg_per = PI - elem->arg_per;
         }
      if( e[2] < 0.)
         elem->arg_per = PI + PI - elem->arg_per;
      }

   if( inv_major_axis > 0.)         /* elliptical case */
      {
      const double e_cos_E = 1. - dist * inv_major_axis;
      const double e_sin_E = r_dot_v / sqrt( gm * elem->major_axis);
      const double ecc_anom = atan2( e_sin_E, e_cos_E);

      elem->mean_anomaly = ecc_anom - ecc * sin( ecc_anom);
/*    elem->t0 = elem->major_axis * sqrt( elem->major_axis / gm);   */
      elem->perih_time = t - elem->mean_anomaly * elem->t0;
      }
   else if( inv_major_axis < 0.)         /* hyperbolic case */
      {
      const double z = (1. - dist * inv_major_axis) / ecc;
      double f = log( z + sqrt( z * z - 1.));

      if( r_dot_v < 0.)
         f = -f;
      elem->mean_anomaly = ecc * sinh( f) - f;
      elem->perih_time = t - elem->mean_anomaly * fabs( elem->t0);
      h0 = -h0;
      }
   else              /* parabolic case */
      {
      double tau;

      tau = sqrt( dist / elem->q - 1.);
      if( r_dot_v < 0.)
         tau = -tau;
      elem->w0 = (3. / SQRT_2) / (elem->q * sqrt( elem->q / gm));
/*    elem->perih_time = t - tau * (tau * tau / 3. + 1) *                   */
/*                                      elem->q * sqrt( 2. * elem->q / gm); */
      elem->perih_time = t - tau * (tau * tau / 3. + 1) * 3. / elem->w0;
      }

/* In the past,  these were scaled;  but now,  I'd prefer to have them */
/* as unit-length vectors.  This matches assumptions in ASTFUNCS.CPP.  */
#if 0
   elem->perih_vec[0] = e[0] * elem->major_axis;
   elem->perih_vec[1] = e[1] * elem->major_axis;
   elem->perih_vec[2] = e[2] * elem->major_axis;
   scale = elem->major_axis / h0;
   elem->sideways[0] = (e[2] * h[1] - e[1] * h[2]) * scale;
   elem->sideways[1] = (e[0] * h[2] - e[2] * h[0]) * scale;
   elem->sideways[2] = (e[1] * h[0] - e[0] * h[1]) * scale;
#endif
   for( i = 0; i < 3; i++)
      elem->perih_vec[i] = e[i];
   elem->sideways[0] = (e[2] * h[1] - e[1] * h[2]) / h0;
   elem->sideways[1] = (e[0] * h[2] - e[2] * h[0]) / h0;
   elem->sideways[2] = (e[1] * h[0] - e[0] * h[1]) / h0;
   elem->angular_momentum = h0;
   return( 0);
}
