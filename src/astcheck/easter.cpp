/* easter.cpp: functions for computing date of Easter, plus test code

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

/* See Meeus,  _Astronomical Algorithms_,  p 67.  He in turn states that
   "the following method has been given by Spencer Jones in his book
   _General Astronomy_ (p 73-74 of the 1922 edition).  It has been
   published again in the _Journal of the British Astronomical Association_,
   vol 88, page 91 (December 1977),  where it is said that it was devised
   in 1876 and appeared in Butcher's _Astronomical Calendar._

      Unlike the formula given by Gauss,  this method has no exception and
   is valid for all years in the Gregorian calendar,  hence from 1583 on."

   I modified the method to include negative years by taking advantage
of the fact that,  in the Gregorian calendar,  Easter recurs on a 5.7
million year cycle. Add 5.7 million to the year,  and all numbers are
positive (as long as year > -5700000,  of course!  I suppose one could
add,  say,  570 million instead,  extending the range to cover roughly
the Paleozoic era to a time 1.5 billion years hence...)

*/

void easter_date( const long year, int *month, int *day)
{
   const long year2 = year + 5700000L;
   const long a = year2 % 19L, b = year2 / 100L, c = year2 % 100L;
   const long d = b / 4L, e = b % 4L, f = (b + 8L) / 25L;
   const long g = (b - f + 1L) / 3L, h = (19L * a + b - d - g + 15L) % 30L;
   const long i = c / 4L, k = c % 4L, l = (32L + e + e + i + i - h - k) % 7L;
   const long m = (a + 11L * h + 22L * l) / 451L, tval = h + l - 7L * m + 114L;

   *month = (int)( tval / 31L);
   *day = (int)( tval % 31L) + 1;
}

#ifdef TEST_CODE

#include <stdio.h>
#include <stdlib.h>

int main( int argc, char **argv)
{
   int month, day;
   long year;

   if( argc == 2)
      {
      int i;
      const int n_across = 5, n_down = 15;

      for( i = 0; i < n_across * n_down; i++)
         {
         year = atol( argv[1]) + (i % n_across) * n_down + i / n_across;
         easter_date( year, &month, &day);
         printf( "%ld %s %2d%s", year, (month == 3 ? "Mar" : "Apr"), day,
                  ((i + 1) % n_across) ? "    " : "\n");
         }
      }
   else if( argc == 3)
      {
      int n_found = 0;

      for( year = 0; year < 10000; year++)
         {
         easter_date( year, &month, &day);
         if( month == atoi( argv[1]) && day == atoi( argv[2]))
            {
            printf( "%5ld", year);
            if( n_found++ % 15 == 14)
               printf( "\n");
            }
         }
      printf( "\n%d found over 10000 years\n", n_found);
      }
   else
      {
      long march[32], april[32];

      for( day = 0; day < 32; day++)
         april[day] = march[day] = 0;
      for( year = 0; year < 5700000; year++)
         {
         easter_date( year, &month, &day);
         if( month == 3)
            march[day]++;
         else
            april[day]++;
         }
      for( day = 0; day < 32; day++)
         if( march[day])
            printf( "Mar %2d: %6.3lf\n", day, (double)march[day] / 57000.);
      for( day = 0; day < 32; day++)
         if( april[day])
            printf( "Apr %2d: %6.3lf\n", day, (double)april[day] / 57000.);

      printf( "Run 'easter' with a year on the command line to get the date\n");
      printf( "of Easter for that year.  For example,  'easter 2008' will\n");
      printf( "get the output 'March 23'.  Alternatively,  give a month and\n");
      printf( "day on the command line to get the years between 0 and 10000\n");
      printf( "when Easter will fall on that day.  For example,  'easter 3 23'\n");
      printf( "will produce a list of all years when Easter is on 23 March.\n");
      printf( "\nNote that Easter cannot occur before 22 March or after 25 April.\n");
      }
   return( 0);
}
#endif
