/* miscell.cpp: misc. astronomy-related functions

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
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>
#include "watdefs.h"
#include "afuncs.h"
#include "date.h"

const static double pi = 3.141592653589793238462643383279;

/* It's embarrassingly common to find out that,  after roundoff errors,
   you're attempting to take the arccosine or arcsine of +/- 1.0000001,
   resulting in a math exception.  Use of acose( ) and asine( ) lets you
   slip around such difficulties. */

double DLL_FUNC acose( const double arg)
{
   if( arg >= 1.)
      return( 0.);
   if( arg <= -1.)
      return( pi);
   return( acos( arg));
}

double DLL_FUNC asine( const double arg)
{
   if( arg >= 1.)
      return( pi / 2);
   if( arg <= -1.)
      return( -pi / 2.);
   return( asin( arg));
}

void DLL_FUNC set_identity_matrix( double DLLPTR *matrix)
{
   int i;

   for( i = 0; i < 9; i++)
      matrix[i] = ((i & 3) ? 0. : 1.);
}

          /* Inverting an orthonormal matrix happens to be an unusually   */
          /* simple job:  swap rows and columns,  and you're in business. */
          /* This really ought to be just called 'transpose_matrix'.      */

#define SWAP( A, B, TEMP)  { TEMP = A;  A = B;  B = TEMP; }

void DLL_FUNC invert_orthonormal_matrix( double DLLPTR *matrix)
{
   double temp;

   SWAP( matrix[1], matrix[3], temp);
   SWAP( matrix[2], matrix[6], temp);
   SWAP( matrix[5], matrix[7], temp);
}

/* Variable star designations follow a rather ugly scheme,  for historical
reasons.  The first 334 are labelled in the following order:

 R  S  T  U  V  W  X  Y  Z RR RS RT RU RV RW RX RY RZ SS ST SU SV SW SX
SY SZ TT TU TV TW TX TY TZ UU UV UW UX UY UZ VV VW VX VY VZ WW WX WY WZ
XX XY XZ YY YZ ZZ AA AB AC AD AE AF AG AH AI AK AL AM AN AO AP AQ AR AS
AT AU AV AW AX AY AZ BB BC BD BE BF BG BH BI BK BL BM BN BO BP BQ BR BS
BT BU BV BW BX BY BZ CC CD CE CF CG CH CI CK CL CM CN CO CP CQ CR CS CT
CU CV CW CX CY CZ DD DE DF DG DH DI DK DL DM DN DO DP DQ DR DS DT DU DV
DW DX DY DZ EE EF EG EH EI EK EL EM EN EO EP EQ ER ES ET EU EV EW EX EY
EZ FF FG FH FI FK FL FM FN FO FP FQ FR FS FT FU FV FW FX FY FZ GG GH GI
GK GL GM GN GO GP GQ GR GS GT GU GV GW GX GY GZ HH HI HK HL HM HN HO HP
HQ HR HS HT HU HV HW HX HY HZ II IK IL IM IN IO IP IQ IR IS IT IU IV IW
IX IY IZ KK KL KM KN KO KP KQ KR KS KT KU KV KW KX KY KZ LL LM LN LO LP
LQ LR LS LT LU LV LW LX LY LZ MM MN MO MP MQ MR MS MT MU MV MW MX MY MZ
NN NO NP NQ NR NS NT NU NV NW NX NY NZ OO OP OQ OR OS OT OU OV OW OX OY
OZ PP PQ PR PS PT PU PV PW PX PY PZ QQ QR QS QT QU QV QW QX QY QZ

   The first one found in a constellation is 'R (constellation name)';
followed by 'S', 'T',  ... 'Z'.  That allows up to nine variables per
constellation;  the tenth gets labelled 'RR',  followed by 'RS', 'RT',
'RU',... 'RZ';  then 'SS', 'ST', 'SU'... 'SZ', 'TT'... 'TZ',  and so on,
up to 'ZZ'.  This allows a further 9+8+7+6+5+4+3+2+1=45 stars to be
labelled. The letters are always 'R' through 'Z',  and the second letter
is never alphabetically before the first.

   Following this,  we cycle the first letter back to 'A'.  This
gives 'AA', 'AB', 'AC', ... 'AZ';  'BB', 'BC', 'BD', ... 'BZ';  and,
eventually,  'QQ', 'QR', ... 'QZ'.  For some reason,  'J' is always
skipped.

   Following this lunacy for 334 variable stars,  they are simply labelled
"V335",  "V336",  etc.

*/

void DLL_FUNC make_var_desig( char DLLPTR *buff, int var_no)
{
   int i, curr_no = 10;

   if( var_no < 10)
      {
      *buff++ = (char)('R' + var_no - 1);
      *buff = '\0';
      }
   else if( var_no > 334)
      {
      *buff++ = 'V';
      for( i = 1000; i; i /= 10)
         if( var_no >= i)
            *buff++ = (char)( (var_no / i) % 10 + '0');
      *buff = '\0';
      }
   else     /* two-letter abbr */
      {
      buff[2] = '\0';
      for( i = 'R'; i <= 'Z' && curr_no + ('Z' - i) < var_no; i++)
         curr_no += 'Z' - i + 1;
               /* gotta get weird to allow for fact that J isn't used */
      if( i > 'Z')                    /* in variable star designators */
         for( i = 'A'; i < 'Q' && curr_no + ('Y' - i) < var_no; i++)
            curr_no += 'Z' - i;
      buff[0] = (char)i;
      buff[1] = (char)(i + var_no - curr_no);
               /* more weirdness due to missing J:  bump up letters J-Q */
      if( buff[0] < 'R' && buff[0] >= 'J')
         buff[0]++;
      if( buff[0] < 'R' && buff[1] >= 'J')
         buff[1]++;
      }
}

void DLL_FUNC rotate_vector( double DLLPTR *v, const double angle,
                                          const int axis)
{
   const double sin_ang = sin( angle), cos_ang = cos( angle);
   const int a = (axis + 1) % 3, b = (axis + 2) % 3;
   const double temp = v[a] * cos_ang - v[b] * sin_ang;

   v[b] = v[b] * cos_ang + v[a] * sin_ang;
   v[a] = temp;
}

void DLL_FUNC pre_spin_matrix( double *v1, double *v2, const double angle)
{
   const double sin_ang = sin( angle);
   const double cos_ang = cos( angle);
   int i;

   for( i = 3; i; i--)
      {
      const double tval = *v1 * cos_ang - *v2 * sin_ang;

      *v2 = *v2 * cos_ang + *v1 * sin_ang;
      *v1 = tval;
      v1 += 3;
      v2 += 3;
      }
}

void DLL_FUNC spin_matrix( double *v1, double *v2, const double angle)
{
   const double sin_ang = sin( angle);
   const double cos_ang = cos( angle);
   int i;

   for( i = 3; i; i--)
      {
      const double tval = *v1 * cos_ang - *v2 * sin_ang;

      *v2 = *v2 * cos_ang + *v1 * sin_ang;
      *v1++ = tval;
      v2++;
      }
}

/* See above for a discussion of the variable star designation scheme. */

int DLL_FUNC decipher_var_desig( const char DLLPTR *desig)
{
   int len, first,  second, rval = -2;

   first = toupper( desig[0]);
   second = toupper( desig[1]);
   for( len = 0; desig[len] && desig[len] != ' '; len++)
      ;
   switch( len)
      {
      case 1:
         if( first >= 'R' && first <= 'Z')
            rval = first - 'R';
         if( desig[0] >= 'A' && desig[0] <= 'Q')
            rval = 9200 + desig[0] - 'A';
         if( (desig[0] >= 'a' && desig[0] <= 'q') || desig[0] == 'u')
            rval = 9100 + desig[0] - 'a';
         break;
      case 2:
         if( second >= first && second <= 'Z')
            {
            if( first >= 'R')  /* RR...ZZ */
               {
               first -= 'R';
               second -= 'R';
               rval = first * 8 - first * (first - 1) / 2 + 9 + second;
               }
            else if( first != 'J' && second != 'J' && first >= 'A')
               {                  /* AA...QQ */
               first -= 'A';
               if( first > 8) first--;
               second -= 'A';
               if( second > 8) second--;
               rval = first * 24 - first * (first - 1) / 2 + 9 + 45 + second;
               }
            }
         break;
      default:
         if( first == 'V')
            rval = atoi( desig + 1) - 1;
         break;
      }
   rval++;
   return( rval);
}

/* The following is analogous to the C ctime( ) function,  except that it
   handles dates previous to 1970 (at least back to -5.5 million years
   and forward to 5.5 million years) and allows for other calendars
   (Gregorian, Julian,  Hebrew,  etc.;  see 'date.cpp' for details).
   Also,  greater control over the output format is provided. */

void DLL_FUNC full_ctime( char *buff, double jd, const int format)
{
   const int precision = (format >> 4) & 0xf, calendar = format & 0xf;
   const int output_format = (format & FULL_CTIME_FORMAT_MASK);
   char *ibuff = buff;   /* keep track of the start of the output */
   int day, month;
   long units, i;
   const int leading_zeroes = (format & FULL_CTIME_LEADING_ZEROES);
   long year, int_jd, day_of_week;
   double add_on = .05 / 86400.;

   for( i = precision; i; i--)
      add_on /= 10.;
   jd += add_on;

   if( output_format == FULL_CTIME_FORMAT_YEAR)
      {
      sprintf( buff, "%17.12lf", (jd - 2451545.0) / 365.25 + 2000.);
      buff[precision + 5] = '\0';
      if( !precision)
         buff[4] = '\0';
      if( leading_zeroes)
         while( *buff == ' ')
            *buff++ = '0';
      return;
      }
   if( output_format == FULL_CTIME_FORMAT_JD
                     || output_format == FULL_CTIME_FORMAT_MJD)
      {
      char format_str[10];

      sprintf( format_str, "JD %%.%df", precision);
      if( output_format == FULL_CTIME_FORMAT_MJD)
         {
         *buff++ = 'M';
         jd -= 2400000.5;
         }
      sprintf( buff, format_str, jd);
      if( leading_zeroes)
         while( *buff == ' ')
            *buff++ = '0';
      return;
      }

   jd += .5;
   int_jd = (long)floor( jd);
   day_of_week = (int_jd + 1) % 7;
   if( day_of_week < 0)    /* keep 0 <= day_of_week < 7: */
      day_of_week += 7;
   if( format & FULL_CTIME_DAY_OF_WEEK_FIRST)
      buff += sprintf( buff, "%s ",
                     set_day_of_week_name( day_of_week, NULL));

   day_to_dmy( int_jd, &day, &month, &year, calendar);

   if( !(format & FULL_CTIME_TIME_ONLY))     /* we want the date: */
      {
      char month_str[25];
      char year_str[10];
      char day_str[15];

      if( format & FULL_CTIME_MONTHS_AS_DIGITS)
         sprintf( month_str, (leading_zeroes ? "%02d" : "%2d"), month);
      else
         {
         strcpy( month_str, set_month_name( month, NULL));
         strcat( month_str, "   ");    /* ensure three-digit abbr for */
         month_str[3] = '\0';          /* all months */
         }

      if( format & FULL_CTIME_TWO_DIGIT_YEAR)
         sprintf( year_str, "%02ld", abs( year % 100));
      else
         sprintf( year_str, (leading_zeroes ? "%04ld" : "%4ld"), year);

      if( format & FULL_CTIME_YEAR_FIRST)
         if( !(format & FULL_CTIME_NO_YEAR))
            buff += sprintf( buff, "%s ", year_str);

      sprintf( day_str, (leading_zeroes ? "%02d" : "%2d"), day);
      if( output_format == FULL_CTIME_FORMAT_DAY && precision)
         {
         long nanodays = (long)( (jd - (double)int_jd) * 1.e+9 + .5);

         if( nanodays < 0L)
            nanodays = 0L;
         if( nanodays > 1000000000L - 1L)
            nanodays = 1000000000L - 1L;
         sprintf( day_str + 2, ".%09ld", nanodays);
         day_str[3 + precision] = '\0';
         }

      if( format & FULL_CTIME_MONTH_DAY)
         buff += sprintf( buff, "%s %s", month_str, day_str);
      else
         buff += sprintf( buff, "%s %s", day_str, month_str);

      if( !(format & FULL_CTIME_YEAR_FIRST))       /* year comes at end */
         if( !(format & FULL_CTIME_NO_YEAR))
            buff += sprintf( buff, " %s", year_str);
      if( output_format != FULL_CTIME_FORMAT_DAY)
         *buff++ = ' ';
      }

   jd -= (double)int_jd;      /* just include remains of the day */
   if( output_format == FULL_CTIME_FORMAT_SECONDS)
      units = 86400;
   else if( output_format == FULL_CTIME_FORMAT_HH_MM)
      units = 1440;
   else                  /* output_format == FULL_CTIME_FORMAT_HH */
      units = 24;
   jd *= (double)units;
   i = (long)jd;
   if( i == units)   /* keep things from rounding up incorrectly */
      i--;
   switch( output_format)
      {
      case FULL_CTIME_FORMAT_SECONDS:
         sprintf( buff, "%2ld:%02ld:%02ld", i / 3600L, (i / 60) % 60L,
                           i % 60L);
         break;
      case FULL_CTIME_FORMAT_HH_MM:
         sprintf( buff, "%2ld:%02ld", i / 60L, i % 60L);
         break;
      case FULL_CTIME_FORMAT_HH:
         sprintf( buff, "%2ld", i);
         break;
      }
   if( output_format != FULL_CTIME_FORMAT_DAY)
      {
      if( leading_zeroes && *buff == ' ')
         *buff = '0';
      if( precision && precision < 10)
         {
         char tbuff[20];

         i = (int)( (jd - (double)i) * 1000000000.);
         if( i > 999999999)
            i = 999999999;
         sprintf( tbuff, ".%09ld", i);
         tbuff[precision + 1] = '\0';
         strcat( buff, tbuff);
         }
      }
   if( format & FULL_CTIME_DAY_OF_WEEK_LAST)
      sprintf( buff + strlen( buff), " %s",
                     set_day_of_week_name( day_of_week, NULL));
   if( format & FULL_CTIME_NO_SPACES)
      for( i = 0; ibuff[i]; i++)
         if( ibuff[i] == ' ')
            {
            memmove( ibuff + i, ibuff + i + 1, strlen( ibuff + i));
            i--;
            }
}

void DLL_FUNC polar3_to_cartesian( double *vect, const double lon, const double lat)
{
   double clat = cos( lat);

   *vect++ = cos( lon) * clat;
   *vect++ = sin( lon) * clat;
   *vect   = sin( lat);
}

double DLL_FUNC vector3_length( const double *vect)
{
   return( sqrt( vect[0] * vect[0] + vect[1] * vect[1] + vect[2] * vect[2]));
}

double DLL_FUNC green_sidereal_time( double jd)
{
   double t_cen, rval, base_t;

   jd -= 2451545.0;      /* set relative to 2000.0 */
   t_cen = jd / 36525.;    /* convert to julian centuries */
   base_t = floor( jd);
   jd -= base_t;
   rval = 280.46061837 + 360.98564736629 * jd + .98564736629 * base_t +
           t_cen * t_cen * (3.87933e-4 - t_cen / 38710000.);

         /* See p 84,  in Meeus:  the following should get apparent */
         /* Greenwich sidereal time: */
   return( rval * pi / 180.);
}

