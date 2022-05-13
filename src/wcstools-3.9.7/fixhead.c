/* File fixhead.c
 * October 14, 2021
 * By Jessica Mink, SAO Telescope Data Center
 * Send bug reports to jmink@cfa.harvard.edu

   Copyright (C) 2021
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
#include <fcntl.h>
#include <errno.h>
#include <unistd.h>
#include <math.h>
#include "libwcs/fitsfile.h"
#include "libwcs/wcslib.h"

#define MAXKWD 100
#define MAXFILES 2000
static int maxnfile = MAXFILES;

static void usage();
static void CopyValues();
extern char *GetFITShead();

static char *RevMsg = "FIXHEAD WCSTools 3.9.7, 26 April 2022, Jessica Mink (jmink@cfa.harvard.edu)";
static int verbose = 0;		/* verbose/debugging flag */
static int nblank = 10;		/* Number of blank lines to leave before END */
static int nfile = 0;
static int ndec0 = -9;
static int listpath = 0;
static int newimage0 = 0;
static int keyset = 0;
static int histset = 0;
static int version = 0;		/* If 1, print only program name and version */
static char *rootdir=NULL;	/* Root directory for input files */

int
main (ac, av)
int ac;
char **av;
{
    char *str;
    char **fp, **newfp;
    int ifile;
    int nbytes;
    char filepath[256];
    char *name;
    FILE *flist = NULL;
    FILE *fdk;
    char *listfile;
    char *ilistfile;
    int  i;
    void FixHeader();

    ilistfile = NULL;
    nfile = 0;
    fp = (char **)calloc (maxnfile, sizeof(char *));

    /* Check for help or version command first */
    str = *(av+1);
    if (!str || !strcmp (str, "help") || !strcmp (str, "-help"))
	usage();
    if (!strcmp (str, "version") || !strcmp (str, "-version")) {
	version = 1;
	usage();
	}

    /* crack arguments */
    for (av++; --ac > 0; av++) {
	if ((*(str = *av))=='-') {
	    char c;
	    while ((c = *++str))
	    switch (c) {

		case 'b': /* Number of blank header lines to keep */
		    if (ac < 2)
			usage();
		    nblank = atoi (*++av);
		    ac--;

		case 'd': /* Root directory for input */
		    if (ac < 2)
			usage();
		    rootdir = *++av;
		    ac--;
		    break;

		case 'h':	/* Group HISTORY keywords at end of header */
		    histset++;
		    break;
	
		case 'v': /* More verbosity */
		    verbose++;
		    break;
	
		default:
		    usage();
		    break;
		}
	    }

	/* File containing a list of image files */
	else if (*av[0] == '@') {
	    listfile = *av + 1;
	    if (isimlist (listfile)) {
		ilistfile = listfile;
		nfile = getfilelines (ilistfile);
		}
	    else {
		printf ("FIXHEAD: %s is not an image list file\n", listfile);
		}
	    }

	/* Image file */
	else if (isfits (*av) || isiraf (*av)) {
	    if (nfile >= maxnfile) {
		maxnfile = maxnfile * 2;
		nbytes = maxnfile * sizeof (char *);
		newfp = (char **) calloc (maxnfile, sizeof (char *));
		for (i = 0; i < nfile; i++)
		newfp[i] = fp[i];
		free (fp);
		fp = newfp;
		}
	    fp[nfile] = *av;
	    nfile++;
	    }

	}

    if (nfile < 1 ) {
	printf ("FIXHEAD: no files specified\n");
	usage ();
	}

    /* Open file containing a list of images, if there is one */
    if (ilistfile != NULL) {
	if ((flist = fopen (ilistfile, "r")) == NULL) {
	    printf ("FIXHEAD: Image list file %s cannot be read\n", ilistfile);
	    usage ();
	    }
	}

    /* Read through headers of images */
    for (ifile = 0; ifile < nfile; ifile++) {
	if (ilistfile != NULL) {
	    first_token (flist, 254, filepath);
	    FixHeader (filepath);
	    }
	else
	    FixHeader (fp[ifile]);

	if (verbose)
	    printf ("\n");
	}
    if (ilistfile != NULL)
	fclose (flist);

    return (0);
}

static void
usage ()
{
    printf ("%s\n",RevMsg);
    if (version)
	exit (-1);
    printf ("Clean up FITS or IRAF by removing excessive blank lines\n");
    printf ("Usage: fixhead [-v][-d dir][-b num] file1.fit ... filen.fits\n");
    printf("  or : fixhead [-v][-d dir][-b num] file1.fit @filelist\n");
    printf("  -b num: Remove all but num blank lines from end of header\n");
    printf("  -d: Root directory for input files (default is cwd)\n");
    printf("  -h: Move HISTORY lines to end of header\n");
    printf("  -k: Write FIXHEAD keyword giving the number of lines removed\n");
    printf("  -v: Verbose\n");
    exit (1);
}


void
FixHeader (filepath)

char	*filepath;	/* FITS or IRAF file to process */

{
    char *headin;	/* FITS image header to which to add */
    char *headout;	/* FITS image header to output */
    char *irafheader = NULL;	/* IRAF image header */
    char *image = NULL;	/* Input and output image buffer */
    double dval;
    int ival, nch, inum;
    int iraffile;
    int ndec, nbheadout, nbheadin, nbheader;
    char oldfilepath[128];
    char string[80];
    char *fext;
    char *fullpath;
    int lhist, lhead;
    char *ltime;
    int naxis, ipos, nbhead, nbr, nbw;
    int fdw;
    int lfp;
    int nblines, nlrem;
    char history[128];
    char echar;
    char *lblanks, *lend;
    int imageread = 0;
    char *fblanks;	/* Position of new END in output header */

    if (rootdir) {
	nch = strlen (rootdir) + strlen (filepath) + 2;
	fullpath = (char *) calloc (1, nch);
	strcat (fullpath, rootdir);
	strcat (fullpath, "/");
	strcat (fullpath, filepath);
	strcpy (filepath, fullpath);
	}
    else
	filepath = filepath;

/* Retrieve FITS header from FITS or IRAF .imh file */
    if ((headin = GetFITShead (filepath, verbose)) == NULL)
	return;

/* Open IRAF image if .imh extension is present */
    if (isiraf (filepath)) {
	iraffile = 1;
	if ((irafheader = irafrhead (filepath, &lhead)) != NULL) {
	    if ((headin = iraf2fits (filepath, irafheader, lhead, &nbhead)) == NULL) {
		printf ("Cannot translate IRAF header %s/n",filepath);
		free (irafheader);
		return;
		}
	    }
	else {
	    printf ("Cannot read IRAF file %s\n", filepath);
	    return;
	    }
	}

/* Open FITS file if .imh extension is not present */
    else {
	iraffile = 0;
	if ((headin = fitsrhead (filepath, &lhead, &nbhead)) != NULL) {
	    hgeti4 (headin,"NAXIS",&naxis);
	    if (naxis > 0) {
		if ((image = fitsrfull (filepath, nbhead, headin)) == NULL) {
		    if (verbose)
			printf ("No image with FITS header in %s\n", filepath);
		    imageread = 0;
		    }
		else
		    imageread = 1;
		}
	    else {
		if (verbose)
		    printf ("Writing new primary header only\n");
		}
	    }
	else {
	    printf ("Cannot read FITS file %s\n", filepath);
	    return;
	    }
	}

/* Allocate output FITS header and copy original header into it */
    nbheadin = nbhead;
    headout = (char *) calloc (nbheadout, 1);
    strncpy (headout, headin, nbheadin);
    headout[nbheadin+1] = (char) 0;
    nbheadout = nbheadin;

/* Find first and last blank line */
    lblanks = blsearch (headout, "END");
    lend = ksearch (headout, "END");
    nblines = (lend - lblanks) / 80;
    nlrem = nblines - nblank;
    hgeti4 (headout, "IMHVER", &iraffile );

    if (verbose) {
	printf ("%s\n",RevMsg);
	if (nlrem > 1)
	    printf ("Remove %d blank lines from header of ", nlrem);
	else if (nlrem > 0)
	    printf ("Remove %d blank line from header of ", nlrem);
	else
	    printf ("Removing no blank lines from header of ");
	if (iraffile)
	    printf ("IRAF image file %s\n", filepath);
	else
	    printf ("FITS image file %s\n", filepath);
	}

/* Return here if no changes are being made to the header */
    if (nlrem < 1)
	return;

/* If space for more than nblank blank lines, move END up to new end of header */
    fblanks = lblanks + (nblank * 80);
    if (fblanks < lend) {
	strcpy (fblanks, "END");
	strcpy (lend, "   ");
	}

/* If no space for nblank blank lines, exit */
    else
	return;

/* Remove directory path and extension from file name */
    strcpy (oldfilepath, filepath);
    fext = strrchr (oldfilepath, '.');
    if (fext)
	fext++;
    else {
	lfp = strlen (oldfilepath);
	fext = filepath + lfp;
	fext[0] = '.';
	fext++;
	}

/* Move original FITS or IRAF file to .fitx or .imx file */
    if (iraffile) {
	fext[0] = 'i';
	fext[1] = 'm';
	fext[2] = 'x';
	fext[3] = (char) 0;
	if (verbose)
	    printf ("Moving old IRAF image file to %s\n", oldfilepath);
	}
    else {
	fext[0] = 'f';
	fext[1] = 'i';
	fext[2] = 't';
	fext[3] = 'x';
	fext[4] = (char) 0;
	if (verbose)
	    printf ("Moving old FITS image file to %s\n", oldfilepath);
	}
    rename (filepath, oldfilepath);

/* Write fixed header to output file */
    if (iraffile) {
	if (irafwhead (filepath, lhead, irafheader, headout) > 0 && verbose)
	    printf ("%s rewritten successfully.\n", filepath);
	else if (verbose)
	    printf ("%s could not be written.\n", filepath);
	free (irafheader);
	}
    else if (naxis > 0 && imageread) {
	if (fitswimage (filepath, headout, image) > 0 && verbose)
	    printf ("%s: rewritten successfully.\n", filepath);
	else if (verbose)
	    printf ("%s could not be written.\n", filepath);
	free (image);
	}
    else {
	if ((fdw = fitswhead (filepath, headout)) > 0 ) {
	    if (verbose)
		printf ("%s: rewritten successfully.\n", filepath);
	    close (fdw);
	    }
	else if (verbose)
            printf ("%s could not be written.\n", filepath);
	}

    if (headin == headout) {
	free (headin);
	}
    else {
	free (headin);
	free (headout);
	}
    return;
}

/* Oct 14 2021	New program based on cphead
 */
