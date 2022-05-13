/* File isdate.c
 * July 23, 2020
 * By Jessica Mink, Harvard-Smithsonian Center for Astrophysics
 * Send bug reports to jmink@cfa.harvard.edu

   Copyright (C) 2020
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

static char *RevMsg = "ISDATE WCSTools 3.9.7, 26 April 2022, Jessica Mink (jmink@cfa.harvard.edu)";

int
main (ac, av)
int ac;
char **av;
{
    char *str;
    int arg;
    int idate;
    int lstr, istr;

    /* Check for version or help command first */
    arg = 0;
    str = *(av+1);
    if (!str || !strcmp (str, "help") || !strcmp (str, "-help")) {
	fprintf (stderr,"%s\n",RevMsg);
	fprintf (stderr,"Usage: isdate [-n] <string>\n");
	fprintf (stderr,"       -n Do not return linefeed (for scripting)\n");
	fprintf (stderr,"       Return 1 if argument is date as yyyy-mm-dd\n");
	fprintf (stderr,"       Return 2 if argument is date as yyyy.mmdd\n");
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
    idate = 0;
    lstr = strlen (str);
    istr = isnum (str);
    if (istr > 1) {
	if (lstr == 10 && str[4] == '-' && str[7] == '-') {
	    idate = 1;
	    }
	else if (lstr == 9 && str[4] == '.') {
	    idate = 2;
	    }
	else if (lstr == 7) {
	    if (str[4] = '-') {
		idate = 1;
		}
	    else if (str[4] == '.') {
		idate = 2;
		}
	    }
	}
    else if (istr == 1 && lstr == 4) {
	idate = 1;
	}
    if (arg) {
	printf ("%d", idate);
	}
    else {
	printf ("%d\n", idate);
	}

    exit (0);
}
/* Jul 23 2020	New program based on ISNUM
 */
