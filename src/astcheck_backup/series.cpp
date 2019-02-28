/* series.cpp: tested some Poisson series computations

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

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#define PI 3.141592653589793238462643383279502884197169399375105

double *load_cartesian_coords( const char *filename, int *n_found,
                  double *jd0, double *step)
{
   FILE *ifile = fopen( filename, "rb");
   double *rval = NULL, *tptr;
   char buff[100];
   const int max_coords = 10000;

   if( ifile)
      {
      *n_found = 0;
      rval = tptr = (double *)malloc( 3 * sizeof( double) * max_coords);
      while( fgets( buff, sizeof( buff), ifile) && *n_found < max_coords)
         if( strlen( buff) > 55 && !memicmp( buff + 50, " (CT)", 5))
            {
            if( *n_found == 0)      /* first line: get starting JD */
               *jd0 = atof( buff);
            if( *n_found == 1)      /* second line: get step size */
               *step = atof( buff) - *jd0;
            fgets( buff, sizeof( buff), ifile);
            sscanf( buff, "%lf %lf %lf", tptr, tptr + 1, tptr + 2);
            (*n_found)++;
            tptr += 3;
            }
      fclose( ifile);
      }
   return( rval);
}

double evaluate_series( const double jd0, const double step, const int n_points,
         const double *coords, const double freq, double *amplitudes)
{
   int i;
   double rval = 0.;

   for( i = 0; i < 6; i++)
      amplitudes[i] = 0.;
   for( i = 0; i < n_points; i++)
      {
      const double J2000 = 2451545.;
      const double arg = 2. * PI * (jd0 + (double)i * step - J2000) / freq;
      const double cos_arg = cos( arg), sin_arg = sin( arg);

      amplitudes[0] += cos_arg * coords[0];
      amplitudes[1] += sin_arg * coords[0];
      amplitudes[2] += cos_arg * coords[1];
      amplitudes[3] += sin_arg * coords[1];
      amplitudes[4] += cos_arg * coords[2];
      amplitudes[5] += sin_arg * coords[2];
      coords += 3;
      }
   for( i = 0; i < 6; i++)
      {
      amplitudes[i] /= (double)n_points;
      rval += amplitudes[i] * amplitudes[i];
      }
   return( sqrt( rval));
}

int main( const int argc, const char **argv)
{
   double jd0, step;
   int n_points;
   double *coords = load_cartesian_coords( argv[1], &n_points, &jd0, &step);

   if( !coords)
      printf( "%s not opened\n", argv[1]);
   else
      {
      double amplitudes[6];
      double freq = atof( argv[2]), freq_step = atof( argv[3]);
      int n_steps = atoi( argv[4]);

      while( n_steps--)
         {
         double rval = evaluate_series( jd0, step, n_points, coords,
                              freq, amplitudes);

         printf( "%lf: rval = %lf\n", freq, rval);
         freq += freq_step;
         }
      }
   return( 0);
}
