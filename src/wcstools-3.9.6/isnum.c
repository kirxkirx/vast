/* File isnum.c
 * August 23, 2016
 * By Jessica Mink, Harvard-Smithsonian Center for Astrophysics
 * Send bug reports to jmink@cfa.harvard.edu

   Copyright (C) 2001-2016
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
 *
 * Return 1 if argument is an integer, 2 if it is floating point, else 0
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "libwcs/fitshead.h"

static char *RevMsg = "ISNUM WCSTools 3.9.6, 31 August 2020, Jessica Mink (jmink@cfa.harvard.edu)";

int
main (ac, av)
int ac;
char **av;
{
    char *str;
    int arg;

    /* Check for version or help command first */
    str = *(av+1);
    if (!str || !strcmp (str, "help") || !strcmp (str, "-help")) {
	fprintf (stderr,"%s\n",RevMsg);
	fprintf (stderr,"Usage: isnum [-n] <string>\n");
	fprintf (stderr,"       -n Do not return linefeed (for scripting)\n");
	fprintf (stderr,"       Return 1 if argument is an integer,\n");
	fprintf (stderr,"       Return 2 if it is floating point\n");
	fprintf (stderr,"       Return 3 if it is a time with colons\n");
	fprintf (stderr,"       Return 4 if it is a date with dashes\n");
	fprintf (stderr,"       Return 0 otherwise\n");
	exit (1);
	}
    else if (!strcmp (str, "version") || !strcmp (str, "-version")) {
	fprintf (stderr,"%s\n",RevMsg);
	exit (1);
	}

    /* If -n, do not print linefeed after number (for scripting) */
    if ( !strcmp (str, "-n") ) {
	arg = 1;
	str = *(av+2);
	}

    /* Check to see if this is a number */
    if (arg) {
	printf ("%d", isnum (str));
	}
    else {
	printf ("%d\n", isnum (str));
	}

    exit (0);
}
/* Nov  7 2001	New program
 *
 * Apr 11 2005	Print version
 *
 * Apr  3 2006	Declare main to be int
 *
 * Jan 10 2007	Drop unused variable fn
 *
 * Nov  6 2015	Add return definition for 3 and 4
 *
 * Dec  9 2015	Add -n option to output number without linefeed
 *
 * Aug 23 2016	Document -n option
 */
