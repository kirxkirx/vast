/* File crlf.c
 * June 20, 2006
 * By Jessica Mink, Harvard-Smithsonian Center for Astrophysics
 * Send bug reports to jmink@cfa.harvard.edu

   Copyright (C) 2006 
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
static void usage();
static void HTMLFix();
int StripHTMLTags();
static char *RevMsg = "HTMLSP WCSTools 3.9.7, 26 April 2022, Jessica Mink (jmink@cfa.harvard.edu)";

int
main (ac, av)
int ac;
char **av;
{
    char *fn;
    char *str;

    /* crack arguments */
    for (av++; --ac > 0 && *(str = *av) == '-'; av++) {
        char c;
        while ((c = *++str))
        switch (c) {

        case 'v':       /* more verbosity */
            verbose++;
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
    	    printf ("%s:\n", fn);
	HTMLFix (fn);
	if (verbose)
	    printf ("\n");
	}

    return (0);
}

static void
usage ()
{
    fprintf (stderr,"HTMLSP: Remove HTML tags from input file\n");
    fprintf(stderr,"Usage:  htmlsp [-v] file1 file2 ... filen\n");
    fprintf(stderr,"  -v: verbose\n");
    exit (1);
}

static int flag;	/* 0: searching for < or &,
			   1: searching for >,
			   2: searching for ; after &,
			   3: searching for </script>,</style>, --> */
static int k=0;
static char tempbuf[1024] = "";

static void
HTMLFix (name)

char *name;

{
    char buffer[1000];
    int fd;
    int nbr, nnbr, i;

    flag = 0;

    fd = open (name, O_RDONLY);
    nbr = 1000;
    while (nbr > 0) {
	nbr = read (fd, buffer, 1000);
	if (nbr > 0) {
	    nnbr = StripHTMLTags (buffer, nbr);
	    (void) write (1, buffer, nnbr);
	    }
	}
   return;
}


int
StripHTMLTags (instring, size)

char *instring;
int size;

{
int i=0, j=0;
char searchbuf[1024] =  "";

while (i < size) {

    if (flag == 0) {
	if (instring[i] == '<') {
	    flag = 1;
	    tempbuf[0] = '\0';
	    k=0;	/* track for <script>,<style>, <!-- --> etc */
	    }
	else if (instring[i] == '&') {
	    flag = 2;
	    }
	else {
	    instring[j] = instring[i];
	    j++;
	    }
	}

    else if (flag == 1) {
	tempbuf[k] = instring[i];
	k++;
	tempbuf[k] = '\0';

	if ((0 == strcmp(tempbuf,"script"))) {
	    flag = 3;
	    strcpy (searchbuf,"</script>");
	    tempbuf[0] = '\0';
	    k = 0;
	    }
	else if ((0 == strcmp(tempbuf,"style"))) {
	    flag = 3;
	    strcpy (searchbuf,"</style>");
	    tempbuf[0] = '\0';
	    k = 0;
	    }
	else if ((0 == strcmp(tempbuf,"!--"))) {
	    flag = 3;
	    strcpy (searchbuf,"-->");
	    tempbuf[0] = '\0';
	    k = 0;
	    }

	if (instring[i] == '>') {
	    if ((0 == strcmp (tempbuf, "/tr"))) {
		fprintf (stderr, "encountered end of table line\n");
		instring[j] = (char) 10;
		}
	    else if ((0 == strcmp (tempbuf, "br"))) {
		instring[j] = (char) 10;
		}
	    else if ((0 == strcmp (tempbuf, "p"))) {
		instring[j] = (char) 10;
		}
	    else {
		instring[j] = ' ';
		}
	    j++;
	    flag = 0;
	    }

	}

    else if (flag == 2) {
	if(instring[i] == ';') {
	    instring[j] = ' ';
	    j++;
	    flag = 0;
	    }
	}

    else if(flag == 3) {
	tempbuf[k] = instring[i];
	k++;
	tempbuf[k] = '\0';

	if (0 == strcmp(&tempbuf[0] + k - strlen(searchbuf),searchbuf)) {
	    flag = 0;
	    searchbuf[0] = '\0';
	    tempbuf[0] = '\0';
	    k = 0;
	    }
	}

    i++;
    }

instring[j] = '\0';

return j;
}

/* Nov  5 2018	New program based on CRLF
 */
