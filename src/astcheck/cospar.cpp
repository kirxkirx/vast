/* cospar.cpp: functions for planet/satellite orientations

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
#include <string.h>
#include <stdlib.h>
#include <math.h>
#include "watdefs.h"
#include "afuncs.h"
#include "lunar.h"

#define PI 3.1415926535897932384626433

/* Mostly complete code to compute COSPAR planetary,  satellite,  and
asteroid orientations using data extracted from 'cospar.txt'.  Thus far,
it can take the Guide-style object number and a JD and compute the pole
position and rotation angle Omega,  including the periodic and linear
and quadratic terms.  It still needs some of the logic from the original
'cospar.cpp' to convert this to a matrix and to handle odd cases such as
the Earth, which has a rotation matrix based on a separate precession
formula, and to set an identity matrix for unknown objects and such.
'cospar.txt' may be extended to include asteroids... someday. */

#define MAX_N_ANGULAR_COEFFS 20
               /* Uranus goes up to 16;  above leaves room for expansion */

int is_retrograde;

static int get_cospar_data_from_text_file( const int object_number,
         const int system_number, const double jde,
         double *pole_ra, double *pole_dec, double *omega)
{
   double angular_coeffs[MAX_N_ANGULAR_COEFFS];
   const double J2000 = 2451545.0;        /* JD 2451545.0 = 1.5 Jan 2000 */
   const double d = (jde - J2000);
   const double t_cen = d / 36525.;
   FILE *ifile = fopen( "cospar.txt", "rb");
   char buff[300];
   char planet = 0;
   int i, curr_obj_from_file = -2, err = 0, done = 0;
   const double pi = 3.141592653589793238462643383279502884197169399375;
   const char *omega_string = "W=";

   if( !ifile)
      return( -1);
               /* Look for different rotation data for Systems II & III: */
   if( object_number == 5 || object_number == 6)
      {
      if( system_number == 2)
         omega_string = "W2=";
      else if( system_number == 3)
         omega_string = "W3=";
      }
   is_retrograde = 0;
   while( !done && !err && fgets( buff, sizeof( buff), ifile))
      if( *buff != '#' && *buff >= ' ')      /* skip comments, empty lines */
         {
         if( !memcmp( buff, "Planet: ", 8))
            {
            planet = buff[8];
            if( curr_obj_from_file == object_number)
               done = 1;
            curr_obj_from_file = -1;
            for( i = 0; i < MAX_N_ANGULAR_COEFFS; i++)
               angular_coeffs[i] = 0.;
            }
         else if( !memcmp( buff, "Obj: ", 5))
            {
            if( curr_obj_from_file == object_number)
               done = 1;
            curr_obj_from_file = atoi( buff + 5);
            }
         else if( planet && curr_obj_from_file == -1)
            {
            double linear, constant_term;
            int idx;
            char d_or_T;

            for( i = 0; buff[i]; i++)
               if( buff[i] == planet && sscanf( buff + i + 1,
                             "%d=%lf%lf%c", &idx, &constant_term, &linear,
                              &d_or_T) == 4)
                  {
                  angular_coeffs[idx] = constant_term + linear *
                           (d_or_T == 'd' ? d : t_cen);
                  angular_coeffs[idx] *= pi / 180.;
                  }
            }
         else if( curr_obj_from_file == object_number)
            {
            double *oval = NULL;

            if( strstr( buff, "a0="))
               oval = pole_ra;
            else if( strstr( buff, "d0="))
               oval = pole_dec;
            else if( strstr( buff, omega_string))
               oval = omega;
            if( oval)
               {
               for( i = 0; buff[i] != '='; i++)
                  ;
               i++;
               *oval = atof( buff + i);
               if( buff[i] == '-')     /* skip leading neg sign */
                  i++;
               while( buff[i])
                  if( buff[i] != '+' && buff[i] != '-')
                     i++;        /* just skip on over... */
                  else
                     {
                     double coeff;
                     int number_length;

                     sscanf( buff + i, "%lf%n", &coeff, &number_length);
                     i += number_length;
                     if( buff[i] == 'd')
                        {
                        if( buff[i + 1] == '2')
                           coeff *= d;
                        else if( coeff < 0. && oval == omega)
                           is_retrograde = 1;
                        coeff *= d;
                        }
                     else if( buff[i] == 'T')
                        {
                        if( buff[i + 1] == '2')
                           coeff *= t_cen;
                        else if( coeff < 0. && oval == omega)
                           is_retrograde = 1;
                        coeff *= t_cen;
                        }
                     else
                        {
                        int idx, multiplier = 1;
                        double angle;

                        if( buff[i + 5] == planet)
                           idx = atoi( buff + i + 6);
                        else
                           {
                           multiplier = atoi( buff + i + 5);
                           idx = atoi( buff + i + 7);
                           if( buff[i + 6] != planet)
                              err = -4;
                           }
                        angle = (double)multiplier * angular_coeffs[idx];
                        if( !multiplier)
                           err = -5;
                        else if( !angle)
                           err = -3;
                        else if( buff[i + 1] == 's')     /* sine term */
                           coeff *= sin( angle);
                        else if( buff[i + 1] == 'c')     /* cosine term */
                           coeff *= cos( angle);
                        else
                           err = -2;
                        }
                     *oval += coeff;
                     }
               }
            }
         }
   fclose( ifile);
   if( !err)
      if( !done)        /* never did find the object: */
         err = -1;
#if 0
      else if( is_retrograde)
         {
         *pole_ra += 180.;
         *pole_dec = -*pole_dec;
         *omega = -*omega;
         }
      else
         *omega += 180.;
#endif
#ifdef TEST_MAIN
   if( err && err != -1)
      printf( "ERROR %d: %s\n", err, buff);
#endif
   return( err);
}

#ifdef TEST_MAIN
int DLL_FUNC calc_planet_orientation2( int planet_no, int system_no, double jd,
                                                         double *matrix)
#else
int DLL_FUNC calc_planet_orientation( int planet_no, int system_no, double jd,
                                                         double *matrix)
#endif
{
   static int prev_planet_no = -1, prev_system_no = -1, prev_rval = 0;
   static double prev_jd = -1.;
   static double prev_matrix[9];
   int i, rval;
   double pole_ra, pole_dec, omega;

   if( planet_no == prev_planet_no && system_no == prev_system_no
                           && jd == prev_jd)
      {
      memcpy( matrix, prev_matrix, 9 * sizeof( double));
      return( prev_rval);
      }

   prev_planet_no = planet_no;
   prev_system_no = system_no;
   prev_jd = jd;

   if( planet_no == 3)        /* handle earth with "normal" precession: */
      {
      const double J2000 = 2451545.;   /* 1.5 Jan 2000 = JD 2451545 */
      const double t_cen = (jd - J2000) / 36525.;
      int i;

      setup_precession( matrix, 2000., 2000. + t_cen * 100.);
      for( i = 3; i < 6; i++)
         matrix[i] = -matrix[i];
      spin_matrix( matrix, matrix + 3, green_sidereal_time( jd));
      memcpy( prev_matrix, matrix, 9 * sizeof( double));
      prev_rval = 0;
      return( 0);
      }

         /* For everybody else,  we use TD.  Only the earth uses UT. */
         /* (This correction added 5 Nov 98,  after G Seronik pointed */
         /* out an error in the Saturn central meridian.)             */

   jd += td_minus_ut( jd) / 86400.;   /* correct from UT to TD */
   rval = get_cospar_data_from_text_file( planet_no, system_no, jd,
                  &pole_ra, &pole_dec, &omega);
   if( rval)      /* failed;  set reasonable defaults */
      pole_ra = pole_dec = omega = 0.;
   pole_ra *= PI / 180.;
   pole_dec *= PI / 180.;
   polar3_to_cartesian( matrix, pole_ra - PI / 2., 0.);
   polar3_to_cartesian( matrix + 3, pole_ra - PI, PI / 2. - pole_dec);
   polar3_to_cartesian( matrix + 6, pole_ra, pole_dec);

   spin_matrix( matrix, matrix + 3, omega * PI / 180. + PI);
   if( is_retrograde)
      for( i = 3; i < 6; i++)
         matrix[i] *= -1.;
   memcpy( prev_matrix, matrix, 9 * sizeof( double));
   prev_rval = rval;
   return( rval);
}


#ifdef TEST_MAIN
void main( int argc, char **argv)
{
   double pole_ra, pole_dec, omega;
   const int planet_number = atoi( argv[1]);
   const double jde = atof( argv[2]);
   const int system_number = (argc > 3 ? atoi( argv[3]) : 0);
   int i, j;

   for( i = (planet_number == -1 ? 0 : planet_number);
        i < (planet_number == -1 ? 100 : planet_number + 1); i++)
      {
      int err = get_cospar_data_from_text_file( i, system_number, jde,
                      &pole_ra, &pole_dec, &omega);

      printf( "Planet %d\n", i);
      if( !err)
         {
         double old_mat[9], new_mat[9], delta = 0.;

         printf( "   pole RA: %lf\n", pole_ra);
         printf( "   pole dec %lf\n", pole_dec);
         printf( "   Omega    %lf (%lf)\n", omega, fmod( omega, 360.));
         if( !calc_planet_orientation2( i, system_number, jde, new_mat))
            if( !calc_planet_orientation( i, system_number, jde, old_mat))
               {
               for( j = 0; j < 9; j += 3)
                  printf( "%10.6lf %10.6lf %10.6lf    %10.6lf %10.6lf %10.6lf\n",
                           new_mat[j], new_mat[j + 1], new_mat[j + 2],
                           old_mat[j], old_mat[j + 1], old_mat[j + 2]);
               for( j = 0; j < 9; j++)
                  delta += (new_mat[j] - old_mat[j]) * (new_mat[j] - old_mat[j]);
               printf( "Diff: %lf\n", sqrt( delta));
               }
         }
      else
         printf( "   Error %d\n", err);
      }
}
#endif
