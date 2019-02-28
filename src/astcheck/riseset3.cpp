/* riseset3.cpp: demos some basic astronomical functions

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

#include <time.h>
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "watdefs.h"
#include "lunar.h"
#include "date.h"
#include "afuncs.h"

char *load_file_into_memory( const char *filename, size_t *filesize);
double look_for_rise_set( const int planet_no,
                  const double jd0, const double jd1,
                  const double observer_lat, const double observer_lon,
                  const char *vsop_data, int *is_setting);

const static double pi  = 3.1415926535897932384626433;
const static double J2000 = 2451545.0;

char *load_file_into_memory( const char *filename, size_t *filesize)
{
   size_t size;
   FILE *ifile = fopen( filename, "rb");
   char *rval = NULL;

   if( ifile)
      {
      fseek( ifile, 0L, SEEK_END);
      size = (size_t)ftell( ifile);
      fseek( ifile, 0L, SEEK_SET);
      rval = (char *)malloc( size + 1);
      if(rval == NULL){
            fprintf(stderr, "ERROR: couldn't allocate memory\n rval = (char *)malloc( size + 1)\n");
            exit(1);
    };
      if( rval)
         fread( rval, size, 1, ifile);
      fclose( ifile);
      if( filesize)
         *filesize = size;
      }
   return( rval);
}

#define PLANET_DATA struct planet_data

PLANET_DATA
   {
   double ecliptic_loc[3], equatorial_loc[3], altaz_loc[3];
   double r, ecliptic_lon, ecliptic_lat, jd;
   double hour_angle;
   };

int fill_planet_data( PLANET_DATA *pdata, const int planet_no, const double jd,
                  const double observer_lat, const double observer_lon,
                  const char *vsop_data)
{
   double loc_sidereal_time = green_sidereal_time( jd) + observer_lon;
   double t_centuries = (jd - J2000) / 36525.;
   double obliquity = mean_obliquity( t_centuries);
   double loc[3];

   pdata->jd = jd;
   if( planet_no == 10)         /* get lunar data,  not VSOP */
      {
      double fund[N_FUND];

      lunar_fundamentals( vsop_data, t_centuries, fund);
      lunar_lon_and_dist( vsop_data, fund, &pdata->ecliptic_lon, &pdata->r, 0L);
      pdata->ecliptic_lon *= pi / 180.;
      pdata->ecliptic_lat = lunar_lat( vsop_data, fund, 0L) * pi / 180.;
      }
   else
      {
                  /* What we _really_ want is the location of the sun as */
                  /* seen from the earth.  VSOP gives us the opposite,   */
                  /* i.e.,  where the _earth_ is as seen from the _sun_. */
                  /* To evade this,  we add PI to the longitude and      */
                  /* negate the latitude.                                */
      pdata->ecliptic_lon =
               calc_vsop_loc( vsop_data, planet_no, 0, t_centuries, 0.) + pi;
      pdata->ecliptic_lat =
                  -calc_vsop_loc( vsop_data, planet_no, 1, t_centuries, 0.);
      pdata->r   = calc_vsop_loc( vsop_data, planet_no, 2, t_centuries, 0.);
      }


   polar3_to_cartesian( loc, pdata->ecliptic_lon, pdata->ecliptic_lat);
   memcpy( pdata->ecliptic_loc, loc, 3 * sizeof( double));

                  /* At this point,  loc is a unit vector in ecliptic */
                  /* coords of date.  Rotate it by 'obliquity' to get */
                  /* a vector in equatorial coords of date: */

   rotate_vector( loc, obliquity, 0);
   memcpy( pdata->equatorial_loc, loc, 3 * sizeof( double));

               /* The following two rotations take us from a vector in */
               /* equatorial coords of date to an alt/az vector: */
   rotate_vector( loc, -loc_sidereal_time, 2);
/* printf( "LST: %lf\n", fmod( loc_sidereal_time * 180. / pi, 360.)); */
   pdata->hour_angle = atan2( loc[1], loc[0]);
   rotate_vector( loc, observer_lat - pi / 2., 1);
   memcpy( pdata->altaz_loc, loc, 3 * sizeof( double));
   return( 0);
}

/* This computes the times at which the sun or moon will rise and set,
during a given day starting on 'jd'.  It does this by computing the
position of the object during each of the 24 hours of that day...
especially the altitude of that object.  What we really want to know
is the object altitude relative to the 'rise/set altitude' (the altitude
at which the top of the object becomes visible,  after correcting for
refraction and,  in the case of the Moon,  topocentric parallax.)
For the sun,  this altitude is -.8333 degrees (its apparent radius
is about .25 degrees,  and refraction 'lifts it up' by .58333 degrees.)
For the moon,  this altitude is +.125 degrees.

   Anyway,  if we find that the object was below this altitude at one
hour,  and above it on the next hour,  then it must have risen in the
interval;  if it was above that altitude,  then below,  it must have
set.  We do an iterative search to find the instant during that
hour that it rose or set.  This starts with a guessed rise/set time
of the particular hour in question.  At each step,  we look at the
altitude of that object at that time,  and use it to adjust the rise/set
time based on the assumption that the motion was linear during the hour
(which isn't a wonderful assumption,  but still usually converges in
a few iterations.)

   The rise time is stored in rise_set[0].
   The set time is stored in rise_set[1].
*/

double look_for_rise_set( const int planet_no,
                  const double jd0, const double jd1,
                  const double observer_lat, const double observer_lon,
                  const char *vsop_data, int *is_setting)
{
   double alt0, alt1;
   double riseset_alt = -.83333 * pi / 180.;
   double rval = 0.;
   PLANET_DATA pdata;

   if( planet_no == 10)
      riseset_alt = .125 * pi / 180.;
   fill_planet_data( &pdata, planet_no, jd0,
                          observer_lat, observer_lon, vsop_data);
   alt0 = asin( pdata.altaz_loc[2]) - riseset_alt;
   fill_planet_data( &pdata, planet_no, jd1,
                          observer_lat, observer_lon, vsop_data);
   alt1 = asin( pdata.altaz_loc[2]) - riseset_alt;

   if( alt0 > 0. && alt1 <= 0.)        /* object is setting */
      *is_setting = 1;
   else if( alt0 <= 0. && alt1 > 0.)        /* object is rising */
      *is_setting = 0;
   else                                /* it's neither rising nor setting */
      *is_setting = -1;
   if( *is_setting != -1)
      {
      double fraction = 0., alt = alt0, delta = 1.;
      int iterations = 10;

      while( fabs( delta) > .0001 && iterations--)
         {
         PLANET_DATA pdata;

         delta = -alt / (alt1 - alt0);
         fraction += delta;
         rval = jd0 + (jd1 - jd0) * fraction;
         fill_planet_data( &pdata, planet_no, jd0 + (jd1 - jd0) * fraction,
                          observer_lat, observer_lon, vsop_data);
         alt = asin( pdata.altaz_loc[2]) - riseset_alt;
         }
      }
   return( rval);
}

#ifdef TEST_MAIN

static void get_rise_set_times( double *rise_set, const int planet_no,
                  double jd,
                  const double observer_lat, const double observer_lon,
                  const char *vsop_data)
{
   int i;

                                    /* Mark both the rise and set times     */
                                    /* as -1,  to indicate that they've     */
                                    /* not been found.  Of course,  it may  */
                                    /* turn out that one,  or both,  do     */
                                    /* not occur during the given 24 hours. */
   rise_set[0] = rise_set[1] = -1;
                                    /* Compute the altitude for each hour:  */
   for( i = 0; i < 24; i++)
      {
      int idx;
      double jd_riseset;

      jd_riseset = look_for_rise_set( planet_no, jd, jd + 1. / 24.,
                  observer_lat, observer_lon, vsop_data, &idx);

      if( idx != -1)
         rise_set[idx] = jd_riseset;
      jd += 1. / 24.;
      }
}

   /* The 'quadrant' function helps in figuring out dates of lunar phases
and solstices/equinoxes.  If the solar longitude is in one quadrant at
the start of a day,  but in a different quadrant at the end of a day,
then we know that there must have been a solstice or equinox during that
day.  Also,  if (lunar longitude - solar longitude) changes quadrants
from the start of a day to the end of a day,  we know there must have
been a lunar phase change during that day.

   In this code,  I don't bother finding the exact instant of these
events.  The code just checks for a quadrant change and reports the
corresponding event. */

static int quadrant( double angle)
{
   angle = fmod( angle, 2. * pi);
   if( angle < 0.)
      angle += 2. * pi;
   return( (int)( angle * 2. / pi));
}

int main( int argc, char **argv)
{
   char *vsop_data = load_file_into_memory( "vsop.bin", NULL);
   int i, year = atoi( argv[1]);
   int month_start = 1, month_end = 12, month;
   const double observer_lon = -69.90 * pi / 180.;
   const double observer_lat = 44.01 * pi / 180.;

   if( !vsop_data)
      {
      printf( "VSOP.BIN wasn't loaded.\n");
      return( -1);
      }

   if( argc > 2)        /* month specified,  rather than "entire year" */
      month_start = month_end = atoi( argv[2]);

   printf( "       Sun          Moon\n");
   printf( "Day  Rise Set     Rise Set\n");
   for( month = month_start; month <= month_end; month++)
      {
      long jd_start, jd_end;
      const int time_zone = -5;

      jd_start = dmy_to_day( 1, month, year, 0);
      if( month == 12)
         jd_end = dmy_to_day( 1, 1, year + 1, 0);
      else
         jd_end = dmy_to_day( 1, month + 1, year, 0);


      for( i = 0; i < (int)( jd_end - jd_start); i++)
         {
         double rise_set[4];
         double lunar_lon[2], solar_lon[2];
         double jd = (double)( jd_start + i) - .5 - (double)time_zone / 24.;
         char buff[80];
         int j, quad0, quad1;

         memset( buff, 0, 40);
         get_rise_set_times( rise_set, 3,  jd, observer_lat, observer_lon,
                                                                vsop_data);
         get_rise_set_times( rise_set + 2, 10, jd, observer_lat, observer_lon,
                                                                vsop_data);
         if( (jd_start + i) % 7 == 6)        /* Sunday */
            strcpy( buff, "Su");
         else
            sprintf( buff, "%2d", i + 1);
         for( j = 0; j < 4; j++)
            {
            static const int offsets[5] = { 4, 10, 17, 23, 29 };

            if( rise_set[j] < 0.)
               strcpy( buff + offsets[j], "--:--");
            else
               {
               int minutes;
               double fraction;

               fraction = rise_set[j] + .5 + (double)time_zone / 24.;
               minutes = (int)( (fraction - floor( fraction)) * 1440.0);

               sprintf( buff + offsets[j], "%02d:%02d",
                                            minutes / 60, minutes % 60);
               }
            }

         for( j = 0; j < 2; j++)
            {
            PLANET_DATA pdata;

            fill_planet_data( &pdata, 3, jd + (double)j,
                         observer_lat, observer_lon, vsop_data);
            solar_lon[j] = pdata.ecliptic_lon;
            fill_planet_data( &pdata, 10, jd + (double)j,
                         observer_lat, observer_lon, vsop_data);
            lunar_lon[j] = pdata.ecliptic_lon;
            }

         quad1 = quadrant( lunar_lon[1] - solar_lon[1]);
         quad0 = quadrant( lunar_lon[0] - solar_lon[0]);
         if( quad1 != quad0)
            memcpy( buff + 29, "1Q FM 3Q NM" + quad0 * 3, 2);

         quad1 = quadrant( solar_lon[1]);
         quad0 = quadrant( solar_lon[0]);
         if( quad1 != quad0)
            {
            static const char *strings[4] =
                            { "Summ Sol", "Autu Eq", "Wint Sol", "Vern Eq" };

            strcpy( buff + 29, strings[quad0]);
            }

         for( j = 0; j < 39; j++)
            if( !buff[j])
               buff[j] = ' ';
         printf( "%s\n", buff);
         }
      }
   free( vsop_data);
   return( 0);
}
#endif
