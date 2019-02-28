/* big_vsop.cpp: functions for analytic (VSOP87) planetary ephems

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
#ifdef _MSC_VER            /* Microsoft Visual C/C++ lacks a 'stdint.h'; */
#include "stdintvc.h"      /* 'stdintvc.h' is a replacement version      */
#else
#include <stdint.h>
#endif
#include "watdefs.h"
#include "lunar.h"

#define PI 3.141592653589793238462643383279502884197169399375105

int DLL_FUNC calc_big_vsop_loc( FILE *ifile, const int planet,
                      double *ovals, double t, const double prec0)
{
   static int16_t cache[19];
   static int curr_planet = 99;
   int close_it = 0, value;

   ovals[0] = ovals[1] = ovals[2] = 0.;
   if( !planet)
      return( 0);       /* the sun */
   if( !ifile)
      {
      ifile = fopen( "big_vsop.bin", "rb");
      close_it = 1;
      }
   if( !ifile)
      return( -1);                              /* ...then give up. */
   if( curr_planet != planet)
      {                             /* reload the cache */
      fseek( ifile, (size_t)(planet - 1) * 6L * 3L * sizeof( int16_t), SEEK_SET);
      fread( cache, 3 * 6 + 1, sizeof( int16_t), ifile);
      curr_planet = planet;
      }

   t /= 10.;         /* convert to julian millenia */
   for( value = 0; value < 3; value++)
      {
      double sum, rval = 0., power = 1., prec = prec0;
      int16_t *loc = cache + value * 6;
      int i, j;

      fseek( ifile, 290L + (size_t)loc[0] * 24L, SEEK_SET);
      if( prec < 0.)
         prec = -prec;

      for( i = 6; i; i--, loc++)
         {
         double idata[3];

         sum = 0.;
         for( j = loc[1] - loc[0]; j; j--)
            {
            fread( idata, 3, sizeof( double), ifile);
            if( idata[0] > prec || idata[0] < -prec)
               {
               double argument = idata[1] + idata[2] * t;

               sum += idata[0] * cos( argument);
               }
            }
         rval += sum * power;
         power *= t;
         if( t)
            prec /= t;
         }
      ovals[value] = rval;
      }

   if( close_it)
      fclose( ifile);

   ovals[0] = fmod( ovals[0], 2. * PI);
   if( ovals[0] < 0.)
      ovals[0] += 2. * PI;
   return( 0);
}
