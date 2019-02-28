/* File filedir.c
 * September 22, 2015
 * By Jessica Mink, Harvard-Smithsonian Center for Astrophysics
 * Send bug reports to jmink@cfa.harvard.edu

   Copyright (C) 2010 - 2015
   Smithsonian Astrophysical Observatory, Cambridge, MA USA

   This program is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public License
   as published by the Free Software Foundation; either version 2
   of the License, or (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License
   along with this program; if not, write to the Free Software Foundation,
   Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>

static int verbose= 0; /* verbose/debugging flag */
static int replace= 0; /* character replacement flag */
static char c1, c2;
static void usage();
static char *RevMsg= "FILEDIR WCSTools 3.9.5, 30 March 2017, Jessica Mink (jmink@cfa.harvard.edu)";

int
    main( ac, av ) int ac;
char **av;
{
 char *fn;
 char *str;
 char *ext;
 int i, lroot, lfn;
 FILE *fd= NULL;
 char line[4096];
 int ReadStdin;

 /* crack arguments */
 for ( av++; --ac > 0 && *( str= *av ) == '-'; av++ ) {
  char c;
  while ( ( c= *++str ) )
   switch ( c ) {

   case 'v': /* more verbosity */
    verbose++;
    break;

   default:
    usage();
    break;
   }
 }

 /* There are ac remaining file names starting at av[0] */
 if ( ac == 0 )
  usage();
 ReadStdin= 0;

 while ( ac-- > 0 ) {
  if ( !ReadStdin ) {
   fn= *av++;
   if ( !strcmp( fn, "stdin" ) ) {
    ReadStdin= 1;
    fd= stdin;
   }
  }
  if ( ReadStdin ) {
   if ( fgets( line, 1023, fd ) == NULL )
    break;
   ac++;
   lfn= strlen( line );
   line[lfn - 1]= (char)0;
   fn= line;
  }
  lfn= strlen( fn );
  if ( verbose )
   printf( "%s ( %d) -> ", fn, lfn );
  ext= strrchr( fn, '/' );
  if ( ext != NULL ) {
   *ext= (char)0;
   if ( ext == ( fn + lfn - 1 ) ) {
    ext= strrchr( fn, '/' );
    if ( ext != NULL )
     *ext= (char)0;
    else {
     fn[0]= '.';
     fn[1]= '/';
     fn[2]= (char)0;
    }
   }
   printf( "%s\n", fn );
  } else
   printf( "./\n" );
 }

 return ( 0 );
}

static void
usage() {
 fprintf( stderr, "%s\n", RevMsg );
 fprintf( stderr, "FILEDIR: Return directory part of file pathname\n" );
 fprintf( stderr, "Usage:  filedir file1 file2 file3 ...\n" );
 exit( 1 );
}
/* Jun 30 2000	New program
 *
 * Oct 02 2012	If pathname ends in "/", drop last directory
 *
 * Sep 22 2015	Read filepath from STDIN if filepath is "stdin"
 */
