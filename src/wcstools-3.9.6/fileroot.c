/* File fileroot.c
 * August 17, 2018
 * By Jessica Mink, Harvard-Smithsonian Center for Astrophysics
 * Send bug reports to jmink@cfa.harvard.edu

   Copyright (C) 2000-2018
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

static int verbose = 0;         /* verbose/debugging flag */
static int replace = 0;         /* character replacement flag */
static int twoext = 0;		/* double extension flag */
static char c1, c2;
static void usage();

int
main (ac, av)
int ac;
char **av;
{
    char *fn;
    char *str;
    char *ext, *ext2;
    int i, lroot;

    /* crack arguments */
    for (av++; --ac > 0 && *(str = *av) == '-'; av++) {
        char c;
        while ((c = *++str))
        switch (c) {

        case 'v':       /* more verbosity */
            verbose++;
            break;

        case 'r':       /* replace next character with one after it */
	    if (ac < 3) 
		usage();
	    av++;
	    c1 = *av[0];
	    ac--;
	    av++;
	    c2 = *av[0];
	    ac--;
            replace++;
            break;

	case '2':	/* remove double extension */
	    twoext++;
	    break;

        default:
            usage();
            break;
        }
    }

    /* There are ac remaining file names starting at av[0] */
    if (ac == 0)
        usage ();

    while (ac-- > 0) {
	fn = *av++;
	if (verbose)
    	    printf ("%s -> ", fn);
	ext = strrchr (fn, ',');
	if (ext != NULL)
	    *ext = (char) 0;
	else {
	    ext = strrchr (fn, '.');
	    if (ext != NULL) {
		*ext = (char) 0;
		if (twoext) {
		    ext2 = strrchr (fn, '.');
		    if (ext2 != NULL) {
			*ext = '.';
			*ext2 = (char) 0;
			}
		    }
		}
	    }
	if (replace) {
	    lroot= strlen (fn);
	    for (i = 0; i < lroot; i++)
		if (fn[i] == c1) fn[i] = c2;
	    }
	printf ("%s\n", fn);
	}

    return (0);
}

static void
usage ()
{
    fprintf (stderr,"FILEROOT: Drop file name extension\n");
    fprintf (stderr,"Usage:  fileroot file1 file2 file3 ...\n");
    fprintf (stderr,"        fileroot -r c1 c2 file1 file2 file3 ...\n");
    fprintf (stderr,"        -r replaces c1 with c2 in file name\n");
    fprintf (stderr,"        -2 drops two extensions at once\n");
    exit (1);
}
/* May  3 2000	New program
 * Sep 12 2000	Truncate at comma as well as period
 *
 * Mar  1 2000	Add character replacement
 *
 * Jun 21 2006	Clean up code
 *
 * Jan 10 2007	Add second parentheses around character check
 *
 * Aug 17 2018	Add -2 to drop two-par extensions such as ".ms.fits"
 */
