/* File getpix.c
 * March 17, 2021
 * By Jessica Mink, Harvard-Smithsonian Center for Astrophysics)
 * Send bug reports to jmink@cfa.harvard.edu

   Copyright (C) 1996-2021
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
#include "libwcs/wcs.h"
#include "libwcs/fitsfile.h"
#include "libwcs/wcscat.h"

#define MAXFILES 2000
static int maxnfile = MAXFILES;
#define MAXNPIX	100;
static int maxnpix = MAXNPIX;

static void usage();
static int PrintPix();
static void procpix();

static char *RevMsg = "GETPIX WCSTools 3.9.7, 26 April 2022, Jessica Mink (jmink@cfa.harvard.edu)";

static int verbose = 0;		/* verbose/debugging flag */
static int version = 0;		/* If 1, print only program name and version */
static int nline = 10;		/* Number of pixels displayed per line */
static int ndec = -1;		/* Format in which to print pixels */
static int pixlabel = 0;	/* If 1, label pixels in output */
static int gtcheck = 0;		/* If 1, list pixels greater than gtval */
static int ltcheck = 0;		/* If 1, list pixels less than ltval */
static int nopunct=0;		/* If 1, print output with no punctuation */
static int printrange = 0;	/* If 1, print range of values, not values */
static int printmean = 0;	/* If 1, print mean of values, not values */
static int printname = 0;	/* If 1, print file name */
static int bycol = 0;		/* If 1, display column as line */
static double gtval = 0.0;
static double ltval = 0.0;
static double ra0 = -99.0;	/* Initial center RA in degrees */
static double dec0 = -99.0;	/* Initial center Dec in degrees */
static double rad0 = 0.0;	/* Search box radius */
static double dra0 = 0.0;	/* Search box width */
static double ddec0 = 0.0;	/* Search box height */
static double eqcoor = 2000.0;  /* Equinox of search center */
static int syscoor = 0;         /* Input search coordinate system */
static int identifier = 0;	/* If 1, identifier precedes x y in file */
static int printtab = 0;	/* If 1, separate number with tabs */
static int procinit = 1;	/* If 1, start mean and limits */
static char *extensions;	/* Extension number(s) or name to read */
static char *extension;		/* Extension number or name to read */
static char pformat[8];		/* If not null, format for pixels without leading % */

int
main (ac, av)

int ac;
char **av;
{
    char *str, *str1;
    char listfile[256];
    char **fn;
    char filename[256];
    int ifile, nbytes;
    FILE *flist;
    char *xrange;       /* Horizontal(x) range string */
    char *yrange;       /* Vertical(y) range string */
    char *rstr;
    char *dstr = NULL;
    char *cstr;
    int systemp;
    int i, j;
    int nch;
    int npix = 0;
    int nfile;
    int ixnum, iynum;
    int ixrange, iyrange;
    char linebuff[1024];
    char listname[256];
    char *fext, *fcomma;
    char *namext;
    char *extroot = NULL;
    char *extroot0;
    char *lastroot = NULL;
    char *line;
    char xstr[16], ystr[16], temp[64];
    int ix, iy;
    int *xpix, *ypix;
    int iline, nlines;
    FILE *fd;
    int *xp1, *yp1;
    double x, y;
    int nfext = 0;
    int nrmax=10;
    struct Range *erange = NULL;

    nfile = 0;
    fn = (char **)calloc (maxnfile, sizeof(char *));
    xpix = (int *)calloc (maxnpix, sizeof (int));
    ypix = (int *)calloc (maxnpix, sizeof (int));
    pformat[0] = (char) 0;

    /* Check for help or version command first */
    str = *(av+1);
    if (!str || !strcmp (str, "help") || !strcmp (str, "-help"))
	usage();
    if (!strcmp (str, "version") || !strcmp (str, "-version")) {
	version = 1;
	usage();
	}

    xrange = NULL;
    yrange = NULL;

    /* crack arguments */
    for (av++; --ac > 0; av++) {
	str = *av;
	ixnum = isnum (str);
	ixrange = isrange (str);
	if (ac > 0) {
	    str1 = *(av+1);
	    iynum = isnum (str1);
	    iyrange = isrange (str1);
	    }
	else {
	    str1 = NULL;
	    iynum = 0;
	    iyrange = 0;
	    }

	/* Command */
	if (str[0] == '-') {
	    char c;
	    while ((c = *++str))
	    switch (c) {

		case 'v':	/* more verbosity */
		    verbose++;
		    break;

		case 'd':	/* Display this number of decimal places */
		    if (ac < 2)
			usage();
		    ndec = atoi (*++av);
		    ac--;
		    break;

		case 'e':	/* Print range of values */
		    printrange=1;
		    break;

		case 'g':	/* Keep pixels greater than this */
		    if (ac < 2)
			usage();
		    gtval = atof (*++av);
		    gtcheck++;
		    ac--;
		    break;

		case 'h':	/* Print file name above pixel values */
		    printname++;
		    break;

		case 'i':	/* Identifier precedes x y in file */
		    identifier++;
		    break;

		case 'l':	/* Keep pixels less than this */
		    if (ac < 2)
			usage();
		    ltval = atof (*++av);
		    ltcheck++;
		    ac--;
		    break;

		case 'm':	/* Print mean, sigma of values */
		    printmean = 1;
		    break;

		case 'n':	/* Number of pixels per line */
		    if (ac < 2)
			usage();
		    nline = atoi (*++av);
		    ac--;
		    break;

		case 'o':	/* Output pixel format without leading % */
		    if (ac < 2)
			usage();
		    strncpy (pformat, *++av, 8);
		    ac--;
		    break;

		case 'p':	/* label pixels */
		    pixlabel++;
		    break;

		case 'r':	/* Box radius in arcseconds */
		    if (ac < 2)
    			usage ();
		    av++;
		    if ((dstr = strchr (*av, ',')) != NULL) {
			*dstr = (char) 0;
			dstr++;
			}
		    if (strchr (*av,':'))
			rad0 = 3600.0 * str2dec (*av);
		    else
			rad0 = atof (*av);
		    if (dstr != NULL) {
			dra0 = rad0;
			rad0 = 0.0;
			if (strchr (dstr, ':'))
			    ddec0 = 3600.0 * str2dec (dstr);
			else
			    ddec0 = atof (dstr);
			if (ddec0 <= 0.0)
			    ddec0 = dra0;
			/* rad0 = sqrt (dra0*dra0 + ddec0*ddec0); */
			}
    		    ac--;
    		    break;

		case 's':	/* Print x y value without punctuation */
		    nopunct++;
		    break;

		case 't':	/* Separate pixels with tabs */
		    printtab++;
		    break;

		case 'y':	/* Display by column instead of line */
		    bycol++;
		    break;
	
		case 'x': /* FITS extension to read */
		    if (ac < 2)
			usage();
		    if (isnum (*(av+1)) || isrange (*(av+1))) {
			extroot = NULL;
			extensions = *++av;
			ac--;
			}
		    else {
			extroot = *++av;
			lastroot = extroot + strlen (extroot);
			extensions = extroot;
			while (extensions < lastroot) {
			    if (isrange (extensions))
				break;
			    else
				extensions++;
			    }
			if (extensions == lastroot) {
			    extensions = calloc (16, 1);
			    if (strlen (extroot) > 0)
				strcpy (extensions, "1-1000");
			    else
				strcpy (extensions, "0-1000");
			    }
			else {
			    extroot0 = extroot;
			    extroot = calloc (16, 1);
			    strncpy (extroot, extroot0, extensions-extroot0);
			    }
			ac--;
			}
		    if (isrange (extensions)) {
			erange = RangeInit (extensions, nrmax);
			nfext = rgetn (erange);
			if (verbose)
			    fprintf (stderr, "Searching extensions %s\n", extensions);
			}
		    else {
			extension = extensions;
			if (extension)
			    nfext = 1;
			else
			    nfext = 0;
			if (verbose)
			    fprintf (stderr, "Searching extension %s\n", extension);
			}
		    break;

		default:
		    usage();
		    break;
		}
	    }

	/* Set search RA, Dec, and equinox if colon in argument */
	else if (ixnum == 3 && iynum == 3) {
	    if (ac < 2) {
		usage ();
		}
	    else {
		strcpy (rstr, str);
		ac--;
		av++;
		strcpy (dstr, str1);
		ra0 = str2ra (rstr);
		dec0 = str2dec (dstr);
		ac--;
		if (ac < 1) {
		    syscoor = WCS_J2000;
		    eqcoor = 2000.0;
		    }
		else if ((syscoor = wcscsys (*(av+1))) >= 0)
		    eqcoor = wcsceq (*++av);
		else {
		    syscoor = WCS_J2000;
		    eqcoor = 2000.0;
		    }
		}
	    }

	/* Search coordinates in degrees if coordinate system specified */
	else if (ixnum == 2 && iynum == 2) {
	    rstr = str;
	    dstr = str1;
	    ac--;
	    av++;
	    av++;
	    if (ac > 0 && (systemp = wcscsys (*av)) > 0) {
		ra0 = atof (rstr);
		dec0 = atof (dstr);
		cstr = *av++;
		syscoor = systemp;
		eqcoor = wcsceq (cstr);
		}

	/* Fractional coordinate pair if no coordinate system */
	    else {
		if (npix+1 > maxnpix) {
		    maxnpix = 2 * maxnpix;
		    xp1 = calloc (maxnpix, sizeof (int));
		    yp1 = calloc (maxnpix, sizeof (int));
		    for (i = 0; i < maxnpix; i++) {
			xp1[i] = xpix[i];
			yp1[i] = ypix[i];
			}
		    free (xpix);
		    free (ypix);
		    xpix = xp1;
		    ypix = yp1;
		    }
		x = atof (rstr);
		if (x > 0.0)
		    ix = (int) (x + 0.5);
		else if (x < 0.0)
		    ix = (int) (x - 0.5);
		else
		    ix = 0;
		y = atof (dstr);
		if (y > 0.0)
		    iy = (int) (y + 0.5);
		else if (y < 0.0)
		    iy = (int) (y - 0.5);
		else
		    iy = 0;
	        xpix[npix] = ix;
	        ypix[npix] = iy;
	        npix++;
		}
	    }

	/* Ranges of x and y pixels to print (only one pair allowed) */
        else if (ixrange && iynum || ixnum && iyrange || ixrange && iyrange) {
	    xrange = str;
	    yrange = str1;
	    ac--;
	    av++;
	    }

	/* Two zeroes indicates that the entire image should be printed */
        else if (!strcmp (str, "0") && !strcmp (str, "0")) {
	    xrange = str;
	    yrange = str1;
	    ac--;
	    av++;
	    }

	/* Coordinate pairs for pixels to print */
        else if (ixnum == 1 && iynum == 1) {
	    if (npix+1 > maxnpix) {
		maxnpix = 2 * maxnpix;
		xp1 = calloc (maxnpix, sizeof (int));
		yp1 = calloc (maxnpix, sizeof (int));
		for (i = 0; i < maxnpix; i++) {
		    xp1[i] = xpix[i];
		    yp1[i] = ypix[i];
		    }
		free (xpix);
		free (ypix);
		xpix = xp1;
		ypix = yp1;
		}
	    ix = atoi (str);
	    iy = atoi (str1);
	    if (ix == 0 || iy == 0) {
		xrange = str1;
		yrange = str;
		}
	    else {
	        xpix[npix] = ix;
	        ypix[npix] = iy;
	        npix++;
		}
	    av++;
	    ac--;
	    }

	/* File containing a list of files or image coordinates */
	else if (str[0] == '@') {
	    strcpy (listname, str+1);
	    if (isimlist (listname)) {
		strcpy (listfile, listname);
		listname[0] = (char) 0;
		}
	    else {
		nlines = getfilelines (listname);
		fd = fopen (listname, "r");
		if (fd == NULL) {
		    fprintf (stderr, "GETPIX: Cannot read file %s\n", listname);
		    nlines = 0;
		    }
		for (iline = 0; iline < nlines; iline++) {
		    if (!fgets (linebuff, 1023, fd))
			break;
		    line = linebuff;
		    if (line[0] == '#')
			continue;
		    if (identifier)
			sscanf (line,"%s %s %s", temp, xstr, ystr);
		    else
			sscanf (line,"%s %s", xstr, ystr);
		    if (npix+1 > maxnpix) {
			maxnpix = 2 * maxnpix;
			xp1 = calloc (maxnpix, sizeof (int));
			yp1 = calloc (maxnpix, sizeof (int));
			for (i = 0; i < maxnpix; i++) {
			    xp1[i] = xpix[i];
			    yp1[i] = ypix[i];
			    }
			free (xpix);
			free (ypix);
			xpix = xp1;
			ypix = yp1;
			}
		    xpix[npix] = atoi (xstr);
		    ypix[npix] = atoi (ystr);
		    npix++;
		    }
		}
	    ac--;
	    }

	/* Image file name */
	else if (isfits (str) || isiraf (str)) {
	    if (nfile >= maxnfile) {
		maxnfile = maxnfile * 2;
		nbytes = maxnfile * sizeof (char *);
		fn = (char **) realloc ((void *)fn, nbytes);
		}
	    fn[nfile] = str;
	    nfile++;
	    }
	}

    if ((xrange && yrange) || npix > 0) {

	/* Process files already read from the command line */
	if (nfile) {
	    for (ifile = 0; ifile < nfile; ifile++) {
		strcpy (filename, fn[ifile]);
		if (nfext > 1) {
		    rstart (erange);
		    extension = calloc (1, 8);
		    for (i = 0; i < nfext; i++) {
			j = rgeti4 (erange);
			sprintf (extension, "%d", j);
			nch = strlen (filename) + 2 + strlen (extension);
			if (extroot)
			    nch = nch + strlen (extroot);
			namext = (char *) calloc (1, nch);
			strcpy (namext, filename);
			strcat (namext, ",");
			if (extroot)
			    strcat (namext,extroot);
			strcat (namext, extension);
			if (PrintPix (namext, xrange, yrange, npix, xpix, ypix)) {
			    if (namext != NULL) {
				free (namext);
				namext = NULL;
				}
			    break;
			    }
			if (namext != NULL) {
			    free (namext);
			    namext = NULL;
			    }
			}
		    if (extension != NULL) {
			free (extension);
			extension = NULL;
			}
		/* if (erange != NULL)
		    free (erange); */
		    }
		else
		    PrintPix (filename, xrange, yrange, npix, xpix, ypix);
		}
	    }

	/* Process files from listfile one at a time */
	else if (isimlist (listfile)) {
	    nfile = getfilelines (listfile);
	    if ((flist = fopen (listfile, "r")) == NULL) {
		fprintf (stderr,"GETPIX: Image list file %s cannot be read\n",
			 listfile);
		usage ();
		}
	    for (ifile = 0; ifile < nfile; ifile++) {
		first_token (flist, 254, filename);
		if (nfext > 1) {
		    rstart (erange);
		    extension = calloc (1, 8);
		    for (i = 0; i < nfext; i++) {
			j = rgeti4 (erange);
			sprintf (extension, "%d", j);
			nch = strlen (filename) + 2 + strlen (extension);
			if (extroot)
			    nch = nch + strlen (extroot);
			namext = (char *) calloc (1, nch);
			strcpy (namext, filename);
			strcat (namext, ",");
			if (extroot)
			    strcat (namext,extroot);
			strcat (namext, extension);
			if (PrintPix (namext, xrange, yrange, npix, xpix, ypix)) {
			    if (namext != NULL) {
				free (namext);
				namext = NULL;
				}
			    break;
			    }
			if (namext != NULL) {
			    free (namext);
			    namext = NULL;
			    }
			}
		    if (extension != NULL) {
			free (extension);
			extension = NULL;
			}
		    }
		else
		    PrintPix (filename, xrange, yrange, npix, xpix, ypix);
		}
	    fclose (flist);
	    }
	}

    free (xpix);
    free (ypix);
    free (fn);
    return (0);
}

static void
usage ()
{
    fprintf (stderr,"%s\n",RevMsg);
    if (version)
	exit (-1);
    fprintf (stderr,"Print FITS or IRAF pixel values\n");
    fprintf(stderr,"Usage: getpix [-vp][-n num][-g val][-l val] file.fits x_range y_range\n");
    fprintf(stderr,"  or   getpix [-vp][-n num][-g val][-l val] file.fits x1 y1 x2 y2 ... xn yn\n");
    fprintf(stderr,"  or   getpix [-vp][-n num][-g val][-l val] file.fits @file\n");
    fprintf(stderr,"  file: File with x y coordinates as first two tokens on lines\n");
    fprintf(stderr,"  -d: Number of decimal places in displayed pixel values\n");
    fprintf(stderr,"  -e: Print range of pixel values in specified image region\n");
    fprintf(stderr,"  -f name: Write specified region to a FITS file\n");
    fprintf(stderr,"  -g num: keep pixels with values greater than this\n");
    fprintf(stderr,"  -h: print file name on line above pixel values\n");
    fprintf(stderr,"  -i: Ignore first token per line of coordinate file\n");
    fprintf(stderr,"  -l num: keep pixels with values less than this\n");
    fprintf(stderr,"  -m: Print mean of pixel values in specified image region\n");
    fprintf(stderr,"  -n num: number of pixel values printed per line\n");
    fprintf(stderr,"  -o format: Output format in C style without leading %%\n");
    fprintf(stderr,"  -p: label pixels\n");
    fprintf(stderr,"  -r num: radius (<0=box) to extract in degrees/arcsec\n");
    fprintf(stderr,"  -s: print x y value with no punctuation\n");
    fprintf(stderr,"  -t: separate columns in table with tabs not spaces \n");
    fprintf(stderr,"  -v: verbose\n");
    fprintf(stderr,"  -x [range]: Read header for these extensions (no arg=all)\n");
    fprintf(stderr,"  -y: display by column instead of by row\n");
    exit (1);
}


static int
PrintPix (name, xrange, yrange, npix, xpix, ypix)

char *name;
char *xrange;		/* Horizontal(x) range string */
char *yrange;		/* Vertical(y) range string */
int npix;		/* Number of coordinate pairs */
int *xpix, *ypix;	/* Vectors of x,y coordinate pairs */

{
    char *header;	/* FITS image header */
    char pform[8];	/* Pixel display format */
    char testval[32];	/* Test value string for column header formatting */
    int lhead;		/* Maximum number of bytes in FITS header */
    int nbhead;		/* Actual number of bytes in FITS header */
    char *irafheader;	/* IRAF image header */
    char *image;	/* FITS or IRAF image */
    double bzero;	/* Zero point for pixel scaling */
    double bscale;	/* Scale factor for pixel scaling */
    int iraffile;
    int lf;
    int intout = 0;	/* Display output pixel values as integer if =1 */
    double dpix, dsum, dmean, dmin, dmax, dnpix;
    char *c;
    int *yi, *xi;
    int bitpix, xdim, ydim, i, nx, ny, ix, iy, x, y, x1, y1, pixperline, ndig;
    int ipix = 0;
    char pixname[255];
    char cform[8], rform[8];
    struct Range *crange;    /* Column (nominally x) range structure */
    struct Range *rrange;    /* Row (nominally y) range structure */

    /* Open IRAF image if .imh extension is present */
    if (isiraf (name)) {
	iraffile = 1;
	if ((irafheader = irafrhead (name, &lhead)) != NULL) {
	    header = iraf2fits (name, irafheader, lhead, &nbhead);
	    free (irafheader);
	    if (header == NULL) {
		fprintf (stderr, "Cannot translate IRAF header %s/n",name);
		return (1);
		}
	    if ((image = irafrimage (header)) == NULL) {
		hgetm (header,"PIXFIL", 255, pixname);
		fprintf (stderr, "Cannot read IRAF pixel file %s\n", pixname);
		free (irafheader);
		free (header);
		return (1);
		}
	    }
	else {
	    fprintf (stderr, "Cannot read IRAF file %s\n", name);
	    return (1);
	    }
	}

    /* Open FITS file if .imh extension is not present */
    else {
	iraffile = 0;
	if ((header = fitsrhead (name, &lhead, &nbhead)) != NULL) {
	    if ((image = fitsrimage (name, nbhead, header)) == NULL) {
		fprintf (stderr, "Cannot read FITS image %s\n", name);
		free (header);
		return (1);
		}
	    }
	else {
	    fprintf (stderr, "Cannot read FITS file %s\n", name);
	    return (1);
	    }
	}
    if (printname) {
	if (ltcheck & gtcheck)
	    fprintf (stderr, "%s: %f < pixel values < %f\n", name, gtval, ltval);
	else if (ltcheck)
	    fprintf (stderr, "%s: pixel values < %f\n", name, ltval);
	else if (gtcheck)
	    fprintf (stderr, "%s: pixel values > %f\n", name, gtval);
	else
	    fprintf (stderr,"%s:\n", name);
	}

    /* Get size of image and scaling factors */
    bitpix = 32;
    hgeti4 (header,"BITPIX",&bitpix);
    xdim = 1;
    hgeti4 (header,"NAXIS1",&xdim);
    ydim = 1;
    hgeti4 (header,"NAXIS2",&ydim);
    bzero = 0.0;
    hgetr8 (header,"BZERO",&bzero);
    bscale = 1.0;
    hgetr8 (header,"BSCALE",&bscale);

    if (verbose) {
	fprintf (stderr,"%s\n",RevMsg);
	if (npix > 0)
	    fprintf (stderr,"Print pixels of ");
	else if (!strcmp (xrange, "0") && !strcmp (yrange, "0"))
	    fprintf (stderr,"Print x  1-%d columns, y 1-%d rows of ", xdim, ydim);
	else if (!strcmp (xrange, "0"))
	    fprintf (stderr,"Print x 1-%d columns, y %s rows of ", xdim, yrange);
	else if (bycol && !strcmp (yrange, "0"))
	    fprintf (stderr,"Print y 1-%d columns, x %s rows of ", ydim, xrange);
	else if (!strcmp (yrange, "0"))
	    fprintf (stderr,"Print x %s columns, y 1-%d rows of ", xrange, ydim);
	else if (bycol)
	    fprintf (stderr,"Print y %s columns , x %s rows of ", yrange, xrange);
	else
	    fprintf (stderr,"Print x %s rows, y %s columns of ", xrange, yrange);
	if (iraffile)
	    fprintf (stderr,"IRAF image file %s\n", name);
	else
	    fprintf (stderr,"FITS image file %s\n", name);
	if (ltcheck & gtcheck)
	    fprintf (stderr, "%f < pixel values < %f\n", gtval, ltval);
	else if (ltcheck)
	    fprintf (stderr, "pixel values < %f\n", ltval);
	else if (gtcheck)
	    fprintf (stderr, "pixel values > %f\n", gtval);
	}
    if (verbose && !pixlabel)
	pixperline = 1;
    else
	pixperline = 0;

/* Set up pixel access and display */

    /* Set initial values */
    dsum = 0.0;
    dnpix = 0.0;
    dmin = 0.0;
    dmax = 0.0;
    procinit = 1;

    /* Set format if not already set */
    for (i = 0; i < 8; i++)
	pform[i] = (char) 0;
    if (pformat[0] != (char) 0) {
	sprintf (pform, "%%%s", pformat);
	lf = strlen (pformat);
	if (pformat[lf-1] == 'd')
	    intout = 1;
	}
    else if (ndec == 0) {
	sprintf (pform, "%%d");
	intout = 1;
	}
    else if (ndec > 0)  {
	sprintf (pform, "%%.%df", ndec);
	intout = 0;
	}
    else if (bitpix > 0) {
	strcpy (pform, "%%d");
	intout = 1;
	}
    else {
	strcpy (pform, "%%.2f");
	intout = 0;
	}

/* Print values at specified coordinates in an image  */
    if (npix > 0) {

	/* Loop through rows starting with the last one */
	for (i = 0; i < npix; i++) {
	    dpix = getpix1(image,bitpix,xdim,ydim,bzero,bscale,xpix[i],ypix[i]);
	    if (gtcheck || ltcheck) {
		if ((gtcheck && dpix > gtval) ||
		    (ltcheck && dpix < ltval)) {
		    procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
		    if (intout) {
			if (dpix > 0)
		 	    ipix = (int) (dpix + 0.5);
			else if (dpix < 0)
			     ipix = (int) (dpix - 0.5);
			else
			    ipix = 0;
			}
		    if (nopunct)
			printf ("%d %d \n", xpix[i], ypix[i]);
		    else
			printf ("[%d,%d] = \n", xpix[i], ypix[i]);
		    if (intout)
			printf (pform, ipix);
		    else
			printf (pform, dpix);
		    printf ("\n");
		    }
		continue;
		}

	    else
		procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
	    if (printrange || printmean)
		continue;
	    if (intout) {
		if (dpix > 0)
	 	    ipix = (int) (dpix + 0.5);
		else if (dpix < 0)
		     ipix = (int) (dpix - 0.5);
		else
		    ipix = 0;
		}
	    if (pixperline) {
		printf ("%s[%d,%d] = ",name,xpix[i],ypix[i]);
		if (intout)
		    printf (pform, ipix);
		else
		    printf (pform, dpix);
		printf ("\n");
		}
	    else {
		if (intout)
		    printf (pform, ipix);
		else
		    printf (pform, dpix);
		if ((i+1) % nline == 0)
		    printf ("\n");
		else if (printtab)
		    printf ("\t");
		else
		    printf (" ");
		}
	    }
	if (!pixperline && !ltcheck && !gtcheck)
	    printf ("\n");
	}

/* Print entire image */
    else if (!strcmp (xrange, "0") && !strcmp (yrange, "0")) {
	if (printmean || printrange) {
	    nx = xdim;
	    ny = ydim;
	    for (y = 0; y < ny; y++) {
		for (x = 0; x < nx; x++) {
        	    dpix = getpix (image,bitpix,xdim,ydim,bzero,bscale,x,y);
		    if (!gtcheck && !ltcheck)
			procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
		    else if (gtcheck && ltcheck) {
			if (dpix > gtval && dpix < ltval)
			    procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
			}
		    else if ((gtcheck && dpix > gtval) ||
			(ltcheck && dpix < ltval))
			procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
		    }
		}
	    }
	else if (gtcheck || ltcheck) {
	    nx = xdim;
	    ny = ydim;
	    for (y = 0; y < ny; y++) {
		y1 = y + 1;
		for (x = 0; x < nx; x++) {
		    x1 = x + 1;
        	    dpix = getpix (image,bitpix,xdim,ydim,bzero,bscale,x,y);
		    if (gtcheck && ltcheck) {
			if (dpix > gtval && dpix < ltval) {
			    if (nopunct)
				printf ("%d %d %f\n", x1, y1, dpix);
			    else
				printf ("[%d,%d] = %f\n", x1, y1, dpix);
			    }
			}
		    else if ((gtcheck && dpix > gtval) ||
			(ltcheck && dpix < ltval)) {
			if (nopunct)
			    printf ("%d %d %f\n", x1, y1, dpix);
			else
			    printf ("[%d,%d] = %f\n", x1, y1, dpix);
			}
		    }
		}
	    }
	else
	    printf ("GETPIX will not print this %d x %d image; use ranges\n",
		xdim, ydim);
	}

/* Print entire columns */
    else if (!strcmp (yrange, "0")) {

	/* Make list of x coordinates */
	crange = RangeInit (xrange, xdim);
	nx = rgetn (crange);
	xi = (int *) calloc (nx, sizeof (int));
	for (i = 0; i < nx; i++) {
	    xi[i] = rgeti4 (crange);
	    }

	ny = ydim;
	for (y = 0; y < ny; y++) {
	    y1 = y + 1;
	    for (ix = 0; ix < nx; ix++) {
		x = xi[ix];
		x1 = x + 1;
        	dpix = getpix (image,bitpix,xdim,ydim,bzero,bscale,x,y);
		if (gtcheck || ltcheck) {
		    if ((gtcheck && dpix > gtval) ||
			(ltcheck && dpix < ltval)) {
			procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
			if (nopunct)
			    printf ("%d %d %f\n", x1, y1, dpix);
			else
			    printf ("[%d,%d] = %f\n", x1, y1, dpix);
			}
		    continue;
		    }
		else
		    procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
	        if (intout) {
		    if (dpix > 0)
	 		ipix = (int) (dpix + 0.5);
		    else if (dpix < 0)
		 	ipix = (int) (dpix - 0.5);
		    else
			ipix = 0;
		    }
		if (pixperline) {
		    printf ("%s[%d,%d] = ",name,x,y);
		    if (intout)
			printf (pform, ipix);
		    else
			printf (pform, dpix);
		    printf ("\n");
		    }
		else {
		    if (intout)
			printf (pform, ipix);
		    else
			printf (pform, dpix);
		    if ((y1) % nline == 0)
			printf ("\n");
		    else if (printtab)
			printf ("\t");
		    else
			printf (" ");
		    }
		}
	    if (y % nline != 0 && !gtcheck && !ltcheck)
		printf ("\n");
	    if (nx > 1 && !gtcheck && !ltcheck)
		printf ("\n");
	    }
	free (crange);
	}

/* Print entire rows */
    else if (!strcmp (xrange, "0")) {

	/* Make list of y coordinates */
	rrange = RangeInit (yrange, ydim);
	ny = rgetn (rrange);
	yi = (int *) calloc (ny, sizeof (int));
	for (i = 0; i < ny; i++) {
	    yi[i] = rgeti4 (rrange);
	    }

	nx = xdim;
	for (x = 0; x < nx; x++) {
	    for (iy = 0; iy < ny; iy++) {
	        y = yi[iy];
        	dpix = getpix (image,bitpix,xdim,ydim,bzero,bscale,x,y);
		if (gtcheck || ltcheck) {
		    if ((gtcheck && dpix > gtval) ||
			(ltcheck && dpix < ltval)) {
			procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
			if (nopunct)
			    printf ("%d %d %f\n", x+1, y+1, dpix);
			else
			    printf ("[%d,%d] = %f\n", x+1, y+1, dpix);
			}
		    continue;
		    }
		else
		    procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
	        if (intout) {
		    if (dpix > 0)
	 		ipix = (int) (dpix + 0.5);
		    else if (dpix < 0)
		 	ipix = (int) (dpix - 0.5);
		    else
			ipix = 0;
		    }
		if (pixperline) {
		    printf ("%s[%d,%d] = ",name,x,y);
		    if (intout)
			printf (pform, ipix);
		    else
			printf (pform, dpix);
		    printf ("\n");
		    }
		else {
		    if (intout)
			printf (pform, ipix);
		    else
			printf (pform, dpix);
		    if ((x+1) % nline == 0)
			printf ("\n");
		    else if (printtab)
			printf ("\t");
		    else
			printf (" ");
		    }
		}
	    if (x % nline != 0 && !gtcheck && !ltcheck)
		printf ("\n");
	    if (ny > 1 && !gtcheck && !ltcheck)
		printf ("\n");
	    }
	free (rrange);
	}

/* Print a region of a two-dimensional image sideways */
    else if (bycol) {

	/* Make list of x coordinates */
	rrange = RangeInit (xrange, xdim);
	nx = rgetn (rrange);
	xi = (int *) calloc (nx, sizeof (int));
	for (i = 0; i < nx; i++) {
	    xi[i] = rgeti4 (rrange);
	    }

	/* Make list of x coordinates */
	crange = RangeInit (yrange, xdim);
	ny = rgetn (crange);
	yi = (int *) calloc (ny, sizeof (int));
	for (i = 0; i < ny; i++) {
	    yi[i] = rgeti4 (crange);
	    }

	/* Set pixel label formats */
	if (pixlabel) {

	/* Format for row pixel labels */
	    x = xi[nx-1];
	    sprintf (testval, "%d", x);
	    ndig = strlen (testval);
	    if (printtab) {
		sprintf (rform, "%%%dd:\t", ndig);
		}
	    else{
		sprintf (rform, "%%%dd: ", ndig);
		}

	/* Format for column pixel labels */
	    sprintf (testval, pform, 1.12345678);
	    ndig = strlen (testval);
	    y = yi[ny-1];
	    sprintf (testval, "%d", y);
	    ndig = ndig + strlen (testval);
	    if (printtab) {
		sprintf (cform, "%%%dd\t", ndig);
		}
	    else{
		sprintf (cform, "%%%dd ", ndig);
		}

	/* Label column pixels */
	    printf ("Coord");
	    for (iy = 0; iy < ny; iy++) {
		y = yi[iy];
		printf (cform, y);
		}
	    printf ("\n");
	    }

	/* Loop through rows */
	for (ix = 0; ix < nx; ix++) {
	    x1 = xi[ix];
	    x = x1 - 1;
	    if (pixlabel) {
		printf (rform, x1);
		}

	    /* Loop through columns */
	    for (iy = 0; iy < ny; iy++) {
		y1 = yi[iy];
		y = y1 - 1;
        	dpix = getpix (image,bitpix,xdim,ydim,bzero,bscale,x,y);
		if (gtcheck || ltcheck) {
		    if ((gtcheck && dpix > gtval) ||
			(ltcheck && dpix < ltval)) {
			procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
			if (nopunct) {
			    printf ("%d %d %f\n", x1, y1, dpix);
			    }
			else {
			    printf ("[%d,%d] = %f\n", x1, y1, dpix);
			    }
			}
		    continue;
		    }
		else {
		    procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
		    }
		if (printrange || printmean) {
		    continue;
		    }
		if (intout) {
		    if (dpix > 0)
	 		ipix = (int) (dpix + 0.5);
		    else if (dpix < 0)
		 	ipix = (int) (dpix - 0.5);
		    else
			ipix = 0;
		    }
		if (pixperline) {
		    printf ("%s[%d,%d] = ", name, x1, y1);
		    if (intout)
			printf (pform, ipix);
		    else
			printf (pform, dpix);
		    printf ("\n");
		    }
		else {
		    if (intout)
			printf (pform, ipix);
		    else
			printf (pform, dpix);
		    if ((iy+1) % nline == 0)
			printf ("\n");
		    else if (printtab)
			printf ("\t");
		    else
			printf (" ");
		    }
		}
	    if (!pixperline && !ltcheck && !gtcheck) {
		if (!printrange && !printmean && iy % nline != 0)
		    printf ("\n");
		}
	    }
	free (rrange);
	free (crange);
	}

/* Print a region of a two-dimensional image */
    else {

	/* Make list of x coordinates */
	crange = RangeInit (xrange, xdim);
	nx = rgetn (crange);
	xi = (int *) calloc (nx, sizeof (int));
	for (i = 0; i < nx; i++) {
	    xi[i] = rgeti4 (crange);
	    }

	/* Make list of y coordinates */
	rrange = RangeInit (yrange, ydim);
	ny = rgetn (rrange);
	yi = (int *) calloc (ny, sizeof (int));
	for (i = 0; i < ny; i++) {
	    yi[i] = rgeti4 (rrange);
	    }

	/* Set pixel label formats */
	if (pixlabel) {

	/* Format for row pixel labels */
	    x = xi[nx-1];
	    sprintf (testval, "%d", x);
	    ndig = strlen (testval);
	    sprintf (rform, "%%%dd:", ndig);
	    if (printtab) {
		sprintf (rform, "%%%dd:\t", ndig);
		}
	    else{
		sprintf (rform, "%%%dd: ", ndig);
		}

	/* Format for column pixel labels */
	    sprintf (testval, pform, 1.12345678);
	    ndig = strlen (testval);
	    y = yi[ny-1];
	    sprintf (testval, "%d", y);
	    ndig = ndig + strlen (testval);
	    if (printtab) {
		sprintf (cform, "%%%dd\t", ndig);
		}
	    else{
		sprintf (cform, "%%%dd ", ndig);
		}

	/* Label column pixels */
	    printf ("Coord");
	    for (ix = 0; ix < nx; ix++) {
		x = xi[ix];
		printf (cform, x);
		}
	    printf ("\n");
	    }

	if (pixperline)
	    iy = -1;
	else
	    iy = ny;

	/* Loop through rows starting with the last one */
	for (i = 0; i < ny; i++) {
	    if (pixperline)
		iy++;
	    else
		iy--;
	    y1 = yi[iy];
	    y = y1 - 1;
	    if (pixlabel) {
		printf (rform, y1);
		}

	    /* Loop through columns */
	    for (ix = 0; ix < nx; ix++) {
		x1 = xi[ix];
		x = x1 - 1;
        	dpix = getpix (image,bitpix,xdim,ydim,bzero,bscale,x,y);
		if (gtcheck || ltcheck) {
		    if ((gtcheck && dpix > gtval) ||
			(ltcheck && dpix < ltval)) {
			procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
			if (nopunct)
			    printf ("%d %d %f\n", x1, y1, dpix);
			else
			    printf ("[%d,%d] = %f\n", x1, y1, dpix);
			}
		    continue;
		    }
		else {
		    procpix (&dsum, &dnpix, &dmin, &dmax, dpix);
		    }
		if (printrange || printmean)
		    continue;
	        if (intout) {
		    if (dpix > 0)
	 		ipix = (int) (dpix + 0.5);
		    else if (dpix < 0)
		 	ipix = (int) (dpix - 0.5);
		    else
			ipix = 0;
		    }
		if (pixperline) {
		    printf ("%s[%d,%d] = ", name, x1, y1);
		    if (intout)
			printf (pform, ipix);
		    else
			printf (pform, dpix);
		    printf ("\n");
		    }
		else {
		    if (intout)
			printf (pform, ipix);
		    else
			printf (pform, dpix);
		    if ((ix+1) % nline == 0)
			printf ("\n");
		    else if (printtab)
			printf ("\t");
		    else
			printf (" ");
		    }
		}
	    if (!pixperline && !ltcheck && !gtcheck) {
		if (!printrange && !printmean && ix % nline != 0)
		    printf ("\n");
		}
	    }
	free (rrange);
	free (crange);
	}

    if (printmean) {
	dmean = dsum / dnpix;
	if (verbose)
	    printf ("Mean= %.4f ", dmean);
	else
	    printf ("%.4f", dmean);
	}
    if (printrange) {
	if (printmean)
	    printf (" ");
	if (verbose)
	    printf ("Range = %.4f - %.4f ", dmin, dmax);
	else
	    printf ("%.4f %.4f", dmin, dmax);
	}
    if (printmean || printrange) {
	if (verbose)
	    printf ("for %d pixels\n", (int) dnpix);
	else
	    printf ("\n");
	}

    free (header);
    free (image);
    return (0);
}


static void
procpix (dsum, dnpix, dmin, dmax, dpix)

double	*dsum;	/* Sum of pixel values */
double	*dnpix;	/* Number of pixels so far */
double	*dmin;	/* Minimum pixel value */
double	*dmax;	/* Maximum pixel value */
double	dpix;	/* Current pixel value */
{
	if (procinit) {
	    *dsum = dpix;
	    *dnpix = 1.0;
	    *dmin = dpix;
	    *dmax = dpix;
	    }
	else {
	    *dsum = *dsum + dpix;
	    *dnpix = *dnpix + 1.0;
	    if (dpix < *dmin)
		*dmin = dpix;
	    else if (dpix > *dmax)
		*dmax = dpix;
	    }
	procinit = 0;
}
/* Dec  6 1996	New program
 *
 * Feb 21 1997  Check pointers against NULL explicitly for Linux
 * Dec 15 1997	Add capability of reading and writing IRAF 2.11 images
 *
 * May 27 1998	Include fitsio.h instead of fitshead.h
 * Jul 24 1998	Make irafheader char instead of int
 * Aug  6 1998	Change fitsio.h to fitsfile.h
 * Oct 14 1998	Use isiraf() to determine file type
 * Nov 30 1998	Add version and help commands for consistency
 *
 * Feb 12 1999	Initialize dxisn to 1 so it works for 1-D images
 * Apr 29 1999	Add BZERO and BSCALE
 * Jun 29 1999	Fix typo in BSCALE setting
 * Jul  2 1999	Use ranges instead of individual pixels
 * Oct 15 1999	Fix format statement
 * Oct 22 1999	Drop unused variables after lint
 * Dec  9 1999	Add -g -l limits
 * Dec 13 1999	Fix bug so that -g and -l limits can be ANDed
 *
 * Mar 23 2000	Use hgetm() to get the IRAF pixel file name, not hgets()
 *
 * Jan 30 2001	Fix format specification in help message
 *
 * Jun  3 2002	Add -s option to print x y value with no punctuation
 * Oct 30 2002	Add code to count lines when printing a region
 *
 * Feb 20 2003	Add option to enter multiple pixel (x,y) as well as ranges
 * Mar 26 2003	Fix pixel counter bug in individual pixel printing
 * Sep 17 2003	Fix bug which broke use of 0 as substitute for 1-naxisn range
 *
 * Apr 26 2004	Fix handling of 0 0 for entire image
 * Aug 30 2004	Fix declarations
 * Sep 21 2004	Fix bug which used x instead of ix for number of elements printed
 *
 * Jul 29 2005	Add mean and range computation
 *
 * Jun 21 2006	Clean up code
 *
 * Jan 10 2007	Declare RevMsg static, not const
 * Dec 20 2007	Add option to read x y coordinates from a file
 * Dec 21 2007	Fix bug reallocating coordinate list when current size exceeded
 *
 * Aug 14 2009	If coordinates are floating point round to appropriate pixel
 *
 * Sep 21 2010	Add option -t to separate numbers by tabs
 * Sep 21 2010	Fix bug in computing means and limits
 *
 * Feb 22 2012	Print descriptors for mean and limits only in verbose mode
 * Feb 22 2012	Fix bug to avoid printing all pixels if printing mean and/or limits
 *
 * Jan 10 2014	Get same pixels from multiple files
 * Jan 10 2014	Add command line option @listfile as list of files
 *
 * Jun  9 2016	Fix isnum() tests for added coloned times and dashed dates
 *
 * May 12 2020	Reverse column and row assignment in range interpretation (Steve Willner)
 * May 12 2020	Change range of values to -e and add -d for decimal places
 * May 12 2020	Add -y to print columns as rows
 * May 14 2020	Clean up distinctions between image x and y and output columns and rows
 * May 14 2020	Add -o [format] to allow any legal C format for pixel display
 * 
 * Feb 10 2021	Add -x to read specified extension(s) from every input file
 * Mar 17 2021	Fix bug when reading filename(s) from command line
 */
