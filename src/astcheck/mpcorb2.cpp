/* mpcorb2.cpp: functions to get basic data on 'mpcorb.dat' files
(Not really very relevant to anything,  as it's turned out!)

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

/* data[0] = header length,  in bytes;
   data[1] = number of numbered asteroids / start of multi-opps;
   data[2] = start of single-opp objects;
   data[3] = total number of objects */

#define MPCORB_RECLEN 203

int get_mpcorb_info( FILE *ifile, long *data)
{
   char buff[210];
   int lines_read = 0, i;

   fseek( ifile, 0L, SEEK_SET);
   data[0] = 0;         /* assume no header */
   data[1] = data[2] = data[3] = 0;
   while( lines_read < 50 && fgets( buff, sizeof( buff), ifile))
      {
      lines_read++;
      if( *buff == '-')    /* we've read the entire header */
         {
         lines_read = 1000;
         data[0] = ftell( ifile);
         }
      }
   fseek( ifile, 0L, SEEK_END);
   data[3] = (ftell( ifile) - data[0]) / MPCORB_RECLEN;
   for( i = 1; i <= 3; i++)
      {
      long step, loc1;

      for( step = 0x800000; step; step >>= 1)
         {
         loc1 = data[i] + step;
         if( !fseek( ifile, data[0] + loc1 * MPCORB_RECLEN, SEEK_SET))
            if( fread( buff, 10, 1, ifile))
               {
               if( buff[0] == 10 && loc1 > data[2])
                  data[2] = loc1;
               else if( buff[0] != 10 && buff[1] != 10 && loc1 > data[1])
                  data[1] = loc1;
               }
         }
      }
   data[1]++;
   return( 0);
}

int main( const int argc, const char **argv)
{
   FILE *ifile = fopen( "mpcorb.dat", "rb");
   long data[4];
   char tbuff[80];

   if( ifile)
      {
      get_mpcorb_info( ifile, data);
      printf( "%ld %ld %ld %ld\n", data[0], data[1], data[2], data[3]);
      }
   else
      printf( "mpcorb.dat not opened\n");
   if( argc > 1)
      {
      long rec_num = atol( argv[1]);
      long offset = data[0] + rec_num * MPCORB_RECLEN;

      if( rec_num >= data[2])
         offset += 2;
      else if( rec_num >= data[1])
         offset++;
      fseek( ifile, offset, SEEK_SET);
      fread( tbuff, 80, 1, ifile);
      tbuff[79] = '\0';
      printf( "%s", tbuff);
      }
   return( 0);
}
