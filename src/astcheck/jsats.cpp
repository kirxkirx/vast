/* jsats.cpp: functions for Galilean satellite posns

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
#include <string.h>
#include "watdefs.h"
#include "lunar.h"

#define PI 3.141592653589793
#define CVT (PI / 180.)
#define PER (13.469942 * PI / 180.)
#define J1900 ( 2451545. - 36525.)
#define J2000   2451545.

/* 28 Sep 2002:  Kazumi Akiyama pointed out two slightly wrong
   coefficients (marked 'KA fix' below).  These change the position
   of Europa by as much as 300 km (worst case),  of Callisto by
   as much as 3 km.
 */

/* Formulae taken from Jean Meeus' _Astronomical Algorithms_.  WARNING:
   the coordinates returned in the 'jsats' array are ecliptic Cartesian
   coordinates of _date_,  not J2000 or B1950!  Units are Jovian radii.  */

int DLL_FUNC calc_jsat_loc( const double jd, double DLLPTR *jsats,
                         const int sats_wanted, const long precision)
{
   const double t = jd - 2443000.5;          /* 1976 aug 10, 0:00 UT */
   double temp1, temp2, gam, libration;
   double lon[5], lat[5], rad[5], l[5], pi[5], ome[5];
   double loc[18];
   double g, g_prime, precess_time, precession, incl, dt, asc_node;
   double psi, incl_orbit;
   int i;

   l[1] = 106.07947 + 203.488955432 * t;
   l[2] = 175.72938 + 101.374724550 * t;
   l[3] = 120.55434 +  50.317609110 * t;
   l[4] = 84.44868 +   21.571071314 * t;

   pi[1] =  58.3329 + 0.16103936 * t;
   pi[2] = 132.8959 + 0.04647985 * t;
   pi[3] = 187.2887 + 0.00712740 * t;
   pi[4] = 335.3418 + 0.00183998 * t;

   ome[1] = 311.0793 - 0.13279430 * t;
   ome[2] = 100.5099 - 0.03263047 * t;
   ome[3] = 119.1688 - 0.00717704 * t;
   ome[4] = 322.5729 - 0.00175934 * t;

   temp1 = (163.679 + 0.0010512 * t) * (PI / 180.);
   temp2 = (34.486 - 0.0161731 * t) * (PI / 180.);
   gam = 0.33033 * sin( temp1) + 0.03439 * sin( temp2);
   libration = (191.8132 + 0.17390023 * t) * (PI / 180.);
   psi = (316.5182 - 2.08e-6 * t) * (PI / 180.);

   g = (30.23756 + 0.0830925701 * t + gam) * (PI / 180.);
   g_prime = (31.97853 + 0.0334597339 * t) * (PI / 180.);
   for( i = 1; i < 5; i++)
      {
      l[i] *= PI / 180.;
      pi[i] *= PI / 180.;
      ome[i] *= PI / 180.;
      lon[i] = lat[i] = rad[i] = 0.;
      }

   if( sats_wanted & 1)       /* Io */
      {
      lon[1] = 47259. * sin( 2. * (l[1] - l[2])) -
                3480. * sin( pi[3] - pi[4]) -
                1756. * sin( pi[1] + pi[3] - 2. * PER - 2 * g) +
                1080. * sin( l[2] - 2. * l[3] + pi[3]) +
                 757. * sin( libration) +
                 663. * sin( l[2] - 2. * l[3] + pi[4]) +
                 453. * sin( l[1] - pi[3]) +
                 453. * sin( l[2] - l[3] - l[3] + pi[2]);
      lat[1] = 6502. * sin( l[1] - ome[1]) +
               1835. * sin( l[1] - ome[2]);
      rad[1] = -41339. * cos( 2. * (l[1] - l[2]));
      }

   if( sats_wanted & 2)       /* europa */
      {
      lon[2] = 106476. * sin( 2. * (l[2] - l[3]))
                +4253. * sin( l[1] - l[2] - l[2] + pi[3])
                +3579. * sin( l[2] - pi[3])
                +2383. * sin( l[1] - 2. * l[2] + pi[4])
                +1977. * sin( l[2] - pi[4])
                -1843. * sin( libration)
                +1299. * sin( pi[3] - pi[4])    /* KA fix */
                -1142. * sin( l[2] - l[3])
                +1078. * sin( l[2] - pi[2])
                -1058. * sin( g)
                 +870. * sin( l[2] - l[3] - l[3] + pi[2])
                 -775. * sin( 2. * ( psi - PER))
                 +524. * sin( 2. * (l[1] - l[2]));
      lat[2] = 81275. * sin( l[2] - ome[2])
               +4512. * sin( l[2] - ome[3])
               -3286. * sin( l[2] - psi)
               +1164. * sin( l[2] - ome[4]);
      rad[2] = 93847. * cos( l[1] - l[2])
               -3114. * cos( l[2] - pi[3])
               -1738. * cos( l[2] - pi[4])
                -941. * cos( l[2] - pi[2]);
      }

   if( sats_wanted & 4)       /* ganymede */
      {
      lon[3] = 16477. * sin( l[3] - pi[3])
               +9062. * sin( l[3] - pi[4])
               -6907. * sin( l[2] - l[3])
               +3786. * sin( pi[3] - pi[4])
               +1844. * sin( 2. * (l[3] - l[4]))
               -1340. * sin( g)
                +703. * sin( l[2] - l[3] - l[3] + pi[3])
                -670. * sin( 2. * ( psi - PER))
                -540. * sin( l[3] - l[4])
                +481. * sin( pi[1] + pi[3] - 2. * PER - 2. * g);
      lat[3] = 32364. * sin( l[3] - ome[3])
              -16911. * sin( l[3] - psi)
               +6849. * sin( l[3] - ome[4])
               -2806. * sin( l[3] - ome[2]);
      rad[3] = -14377. * cos( l[3] - pi[3])
                -7904. * cos( l[3] - pi[4])
                +6342. * cos( l[2] - l[3])
                -1758. * cos( 2. * (l[3] - l[4]));
      }

   if( sats_wanted & 8)       /* callisto */
      {
      lon[4] = 84109. * sin( l[4] - pi[4]) +
                3429. * sin( pi[4] - pi[3]) -
                3305. * sin( 2. * (psi - PER)) -
                3211. * sin( g) -
                1860. * sin( l[4] - pi[3]) +
                1182. * sin( psi - ome[4]) +
                 622. * sin( l[4] + pi[4] - 2. * g - 2. * PER) +
                 385. * sin( 2. * (l[4] - pi[4])) -
                 284. * sin( 5. * g_prime - 2. * g + 52.225 * CVT) -
                 233. * sin( 2. * (psi - pi[4])) -
                 223. * sin( l[3] - l[4]);         /* KA fix */
      lat[4] = -76579. * sin( l[4] - psi) +
                44148. * sin( l[4] - ome[4]) -
                 5106. * sin( l[4] - ome[3]) +
                  773. * sin( l[4] + psi - 2. * PER - 2. * g);
      rad[4] = -73391. * cos( l[4] - pi[4])
                +1620. * cos( l[4] - pi[3])
                 +974. * cos( l[3] - l[4]);
      }

               /* calc precession since B1950 epoch */
   precess_time = (jd - 2433282.423) / 36525.;
   precession = (1.3966626 + .0003088 * precess_time) * precess_time;
   precession *= (PI / 180.);
   dt = (jd - J2000) / 36525.;
   asc_node = 100.464441 + dt * (1.020955 + dt * .00040117);
   asc_node *= PI / 180.;
   incl_orbit = 1.303270 + dt * (-.0054966 + dt * 4.65e-6);
   incl_orbit *= PI / 180.;
   for( i = 1; i < 5; i++)
      if( sats_wanted & (1 << (i - 1)))
         {
         static double r0[4] = { 5.90730, 9.39912, 14.99240, 26.36990 };

         lon[i] = l[i] + lon[i] * PI / 180. * 1.e-5 + precession;
         lat[i] = atan( lat[i] * 1.e-7);
         rad[i] = r0[i - 1] * (1. + rad[i] * 1.e-7);
         }
   psi += precession;
   incl = 3.120262 + .0006 * (jd - J1900) / 36525.;
   incl *= PI / 180.;
   for( i = 0; i < 18; i++)
      loc[i] = 0.;
   for( i = 1; i < 6; i++)
      if( sats_wanted & (1 << (i - 1)))
         {
         double co, si, x, y, z, a, b, c;
         double FAR *tptr;

         tptr = (double FAR *)loc + i * 3 - 3;
                                    /* calc coords by Jupiter's equator */
         if( i != 5)
            {
            tptr[0] = rad[i] * cos( lon[i] - psi) * cos( lat[i]);
            tptr[1] = rad[i] * sin( lon[i] - psi) * cos( lat[i]);
            tptr[2] = rad[i] * sin( lat[i]);
            }
         else
            tptr[2] = 1.;     /* fictitious fifth satellite */

         co = cos( incl);
         si = sin( incl);
         x = tptr[0];               /* rotate to plane of Jup's orbit */
         y = tptr[1] * co - tptr[2] * si;
         z = tptr[1] * si + tptr[2] * co;

         co = cos( psi - asc_node);     /* rotate to Jup's ascending node */
         si = sin( psi - asc_node);
         a = x * co - y * si;
         b = x * si + y * co;
         c = z;

         co = cos( incl_orbit);     /* rotate to the ecliptic */
         si = sin( incl_orbit);
         x = a;
         y = b * co - c * si;
         z = b * si + c * co;

         co = cos( asc_node);    /* rotate to vernal equinox */
         si = sin( asc_node);
         a = x * co - y * si;
         b = x * si + y * co;
         c = z;                  /* at this point we have jovicentric */
                                 /* coords and could (should) stop */
         tptr[0] = a;
         tptr[1] = b;
         tptr[2] = c;
         }
   FMEMCPY( jsats, loc, 15 * sizeof( double));
   if( sats_wanted & 16)      /* imaginary sat wanted */
      FMEMCPY( jsats + 15, loc + 15, 3 * sizeof( double));
   return( sats_wanted);
}
