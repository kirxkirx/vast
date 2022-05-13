/*** File libwcs/range.c
 *** July 6, 2021
 *** By Jessica Mink, jmink@cfa.harvard.edu
 *** Harvard-Smithsonian Center for Astrophysics
 *** Copyright (C) 1998-2021
 *** Smithsonian Astrophysical Observatory, Cambridge, MA, USA

    This library is free software; you can redistribute it and/or
    modify it under the terms of the GNU Lesser General Public
    License as published by the Free Software Foundation; either
    version 2 of the License, or (at your option) any later version.

    This library is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
    Lesser General Public License for more details.
    
    You should have received a copy of the GNU Lesser General Public
    License along with this library; if not, write to the Free Software
    Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

    Correspondence concerning WCSTools should be addressed as follows:
           Internet email: jmink@cfa.harvard.edu
           Postal address: Jessica Mink
                           Smithsonian Astrophysical Observatory
                           60 Garden St.
                           Cambridge, MA 02138 USA
 */

/* struct Range *RangeInit (string, ndef)
 *	Return structure containing ranges of numbers
 * int isrange (string)
 *	Return 1 if string is a range, else 0
 * int rstart (range)
 *	Restart at beginning of range
 * int rgetn (range)
 *	Return number of values from range structure
 * int rgeti4 (range)
 *	Return next number from range structure as 4-byte integer
 * int rgetr8 (range)
 *	Return next number from range structure as 8-byte floating point number
 * int ageti4 (string, keyword, ival)
 *	Read int value from a file where keyword=value, anywhere on a line
 * int agetr8 (string, keyword, dval)
 *	Read double value from a file where keyword=value, anywhere on a line
 * int agets (string, keyword, lval, fillblank, value)
 *	Read value from a file where keyword=value, anywhere on a line
 * void polfit (x, y, x0, npts, nterms, a, stdev)
 *	Polynomial least squares fitting program
 * double polcomp (xi, x0, norder, a)
 *	Polynomial evaluation Y = A(1) + A(2)*X + A(3)*X^2 + A(3)*X^3 + ...
 */

#include <unistd.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include "wcs.h"
#include "fitsfile.h"
#include "wcscat.h"

/* RANGEINIT -- Initialize range structure from string */

struct Range *
RangeInit (string, ndef)

char	*string;	/* String containing numbers separated by , and - */
int	ndef;		/* Maximum allowable range value */

{
    struct Range *range;
    int ip, irange;
    char *slast;
    double first, last, step;

    if (!isrange (string) && !isnum (string))
	return (NULL);
    ip = 0;
    range = (struct Range *)calloc (1, sizeof (struct Range));
    range->irange = -1;
    range->nvalues = 0;
    range->nranges = 0;
    range->valmax = -1000000000000.0;
    range->valmin = 1000000000000.0;

    for (irange = 0; irange < MAXRANGE; irange++) {

	/* Default to entire list */
	first = 1.0;
	last = ndef;
	step = 1.0;

	/* Skip delimiters to start of range */
	while (string[ip] == ' ' || string[ip] == '	' ||
	       string[ip] == ',')
	    ip++;

	/* Get first limit
	 * Must be a number, '-', 'x', or EOS.  If not return ERR */
	if (string[ip] == (char)0) {	/* end of list */
	    if (irange == 0) {

		/* Null string defaults */
		range->ranges[0] = first;
		if (first < 1)
		    range->ranges[1] = first;
		else
		    range->ranges[1] = last;
		range->ranges[2] = step;
		range->nvalues = range->nvalues + 1 +
			  ((range->ranges[1]-range->ranges[0])/step);
		range->nranges++;
		return (range);
		}
	    else
		return (range);
	    }
	else if (string[ip] > (char)47 && string[ip] < 58) {
	    first = strtod (string+ip, &slast);
	    ip = slast - string;
	    }
	else if (strchr ("-:x", string[ip]) == NULL) {
	    free (range);
	    return (NULL);
	    }

	/* Skip delimiters */
	while (string[ip] == ' ' || string[ip] == '	' ||
	       string[ip] == ',')
	    ip++;

	/* Get last limit
	* Must be '-', or 'x' otherwise last = first */
	if (string[ip] == '-' || string[ip] == ':') {
	    ip++;
	    while (string[ip] == ' ' || string[ip] == '	' ||
	   	   string[ip] == ',')
		ip++;
	    if (string[ip] == (char)0)
		last = first + ndef;
	    else if (string[ip] > (char)47 && string[ip] < 58) {
		last = strtod (string+ip, &slast);
		ip = slast - string;
		}
	    else if (string[ip] != 'x')
		last = first + ndef;
	    }
	else if (string[ip] != 'x')
	    last = first;

	/* Skip delimiters */
	while (string[ip] == ' ' || string[ip] == '	' ||
	       string[ip] == ',')
	    ip++;

	/* Get step
	 * Must be 'x' or assume default step. */
	if (string[ip] == 'x') {
	    ip++;
	    while (string[ip] == ' ' || string[ip] == '	' ||
	   	   string[ip] == ',')
		ip++;
	    if (string[ip] == (char)0)
		step = 1.0;
	    else if (string[ip] > (char)47 && string[ip] < 58) {
		step = strtod (string+ip, &slast);
		ip = slast - string;
		}
	    else if (string[ip] != '-' && string[ip] != ':')
		step = 1.0;
            }

	/* Output the range triple */
	range->ranges[irange*3] = first;
	range->ranges[irange*3 + 1] = last;
	range->ranges[irange*3 + 2] = step;
	range->nvalues = range->nvalues + ((last-first+(0.1*step)) / step + 1);
	range->nranges++;
	if (step > 0.0) {
	    if (first < range->valmin)
		range->valmin = first;
	    if (last > range->valmax)
		range->valmax = last;
	    }
	else {
	    if (first > range->valmax)
		range->valmax = first;
	    if (last < range->valmin)
		range->valmin = last;
	    }
	}

    return (range);
}


/* ISRANGE -- Return 1 if string is a range, else 0 */

int
isrange (string)

char *string;		/* String which might be a range of numbers */

{
    int i, lstr;

    /* If string is NULL or empty, return 0 */
    if (string == NULL || strlen (string) == 0)
	return (0);

    /* If range separators present, check to make sure string is range */
    else if (strchr (string+1, '-') || strchr (string+1, ',')) {
	lstr = strlen (string);
	for (i = 0; i < lstr; i++) {
	    if (strchr ("0123456789-,.x", (int)string[i]) == NULL)
		return (0);
	    }
	return (1);
	}
    else
	return (0);
}


/* RSTART -- Restart at beginning of range */

void
rstart (range)

struct Range *range;	/* Range structure */

{
    range->irange = -1;
    return;
}


/* RGETN -- Return number of values from range structure */

int
rgetn (range)

struct Range *range;	/* Range structure */

{
    return (range->nvalues);
}


/*  RGETR8 -- Return next number from range structure as 8-byte f.p. number */

double
rgetr8 (range)

struct Range *range;	/* Range structure */

{
    int i;

    if (range == NULL)
	return (0.0);
    else if (range->irange < 0) {
	range->irange = 0;
	range->first = range->ranges[0];
	range->last = range->ranges[1];
	range->step = range->ranges[2];
	range->value = range->first;
	}
    else {
	range->value = range->value + range->step;
	if (range->value > (range->last + (range->step * 0.5))) {
	    range->irange++;
	    if (range->irange < range->nranges) {
		i = range->irange * 3;
		range->first = range->ranges[i];
		range->last = range->ranges[i+1];
		range->step = range->ranges[i+2];
		range->value = range->first;
		}
	    else
		range->value = 0.0;
	    }
	}
    return (range->value);
}


/*  RGETI4 -- Return next number from range structure as 4-byte integer */

int
rgeti4 (range)

struct Range *range;	/* Range structure */

{
    double value;

    value = rgetr8 (range);
    return ((int) (value + 0.000000001));
}


/* AGETI4 -- Get integer value from ASCII string where keyword=value anywhere */

int
ageti4 (string, keyword, ival)

char	*string;	/* character string containing <keyword>= <value> */
char	*keyword;	/* character string containing the name of the keyword
			   the value of which is returned.  hget searches for a
                 	   line beginning with this string.  if "[n]" or ",n" is
			   present, the n'th token in the value is returned. */
int	*ival;		/* Integer value, returned */
{
    char value[32];

    if (agets (string, keyword, 31, 0, value)) {
	*ival = atoi (value);
	return (1);
	}
    else
	return (0);
}


/* AGETR8 -- Get double value from ASCII string where keyword=value anywhere */
int
agetr8 (string, keyword, dval)

char	*string;	/* character string containing <keyword>= <value> */
char	*keyword;	/* character string containing the name of the keyword
			   the value of which is returned.  hget searches for a
                 	   line beginning with this string.  if "[n]" or ",n" is
			   present, the n'th token in the value is returned. */
double	*dval;		/* Double value, returned */
{
    char value[32];

    if (agets (string, keyword, 31, 0, value)) {
	*dval = atof (value);
	return (1);
	}
    else
	return (0);
}


/* AGETS -- Get keyword value from ASCII string with keyword=value anywhere */

int
agets (string, keyword0, lval, fillblank, value)

char *string;	/* character string containing <keyword>= <value> info */
char *keyword0;	/* character string containing the name of the keyword
		   the value of which is returned.  hget searches for a
		   line beginning with this string.  if "[n]" or ",n" is
		   present, the n'th token in the value is returned. */
int lval;	/* Size of value in characters
		   If negative, value ends at end of line */
int fillblank;	/* If 0, leave blanks, strip trailing blanks
		   if non-zero, replace blanks with underscores */
char *value;	/* String (returned) */
{
    char keyword[81];
    char *pval, *str, *pkey, *pv;
    char cquot, squot[2], dquot[2], lbracket[2], rbracket[2], comma[2];
    char *lastval, *rval, *brack1, *brack2, *lastring, *iquot, *ival;
    int ipar, i, lkey, fkey;

    squot[0] = (char) 39;
    squot[1] = (char) 0;
    dquot[0] = (char) 34;
    dquot[1] = (char) 0;
    lbracket[0] = (char) 91;
    lbracket[1] = (char) 0;
    comma[0] = (char) 44;
    comma[1] = (char) 0;
    cquot = ' ';
    rbracket[0] = (char) 93;
    rbracket[1] = (char) 0;
    lastring = string + strlen (string);

    /* Find length of variable name */
    strncpy (keyword,keyword0, sizeof(keyword)-1);
    brack1 = strsrch (keyword,lbracket);
    if (brack1 == keyword) {
	brack1 = NULL;
	}
    brack2 = NULL;
    if (brack1 == NULL)
	brack1 = strsrch (keyword,comma);
    if (brack1 != NULL) {
	*brack1 = '\0';
	brack1++;
	}
    lkey = strlen (keyword);

    /* First check for the existence of the keyword in the string */
    pval = NULL;
    str = string;
    while (pval == NULL) {
	pkey = strcsrch (str, keyword);

    /* If keyword has not been found, return 0 */
	if (pkey == NULL) {
	    return (0);
	    }

    /* If it has been found, check for = or : and preceding characters */

    /* Must be at start of file or after control character or space */
	if (pkey != string && *(pkey-1) > 32) {
	    str = pkey;
	    pval = NULL;
	    }

	/* Must have "=" or ":" as next nonspace and nonbracket character */
	    else {
	    pv = pkey + lkey;
	    while (*pv == ' ' || *pv == ']' || *pv == 'o') {
		pv++;
		}
	    if (*pv != '=' && *pv != ':' && *pv != 10 && *pv != 'f') {
		str = pkey;
		pval = NULL;
		}

	/* If found, bump pointer past keyword, operator, and spaces */
	    else {
		pval = pv + 1;
		while (*pval == '=' || *pval == ' ') {
		    pval++;
		    }
		break;
		}
	    }
	str = str + lkey;
	if (str > lastring) {
	    break;
	    }
	}

    if (pval == NULL) {
	return (0);
	}

    /* Drop leading spaces */
    while (*pval == ' ') pval++;

    /* Pad quoted material with _; drop leading and trailing quotes */
    iquot = NULL;
    if (*pval == squot[0]) {
	pval++;
	iquot = strsrch (pval, squot);
	}
    if (*pval == dquot[0]) {
	pval++;
	iquot = strsrch (pval, dquot);
	}
    if (iquot != NULL) {
	cquot = *iquot;
	*iquot = (char) 0;
	if (fillblank) {
	    for (ival = pval; ival < iquot; ival++) {
		if (*ival == ' ') {
		    *ival = '_';
		    }
		}
	    }
	}

    /* If keyword has brackets, figure out which token to extract */
    if (brack1 != NULL) {
        brack2 = strsrch (brack1,rbracket);
        if (brack2 != NULL) {
            *brack2 = '\0';
	    }
        ipar = atoi (brack1);
	}
    else {
	ipar = 1;
	}

    /* Move to appropriate token */
    for (i = 1; i < ipar; i++) {
	while (*pval != ' ' && *pval != '/' && pval < lastring) {
	    pval++;
	    }

	/* Drop leading spaces  or / */
	while (*pval == ' ' || *pval == '/') {
	    pval++;
	    }
	}

    /* Transfer token value to returned string */
    rval = value;
    if (lval < 0) {
	lastval = value - lval - 1;
	while (*pval != '\n' && pval < lastring && rval < lastval) {
	    if (lval > 0 && *pval == ' ') {
		break;
		}
	    *rval++ = *pval++;
	    }
	}
    else {
	lastval = value + lval - 1;
	while (*pval != '\n' && *pval != '/' &&
	    pval < lastring && rval < lastval) {
	    if (lval > 0 && *pval == ' ') {
		break;
		}
	    *rval++ = *pval++;
	    }
	}
    if (rval < lastval) {
	*rval = (char) 0;
	}
    else {
	*lastval = 0;
	}

    /* Drop trailing spaces/underscores/commas */
    if (!fillblank) {
	lval = strlen (value);
	for (ival = value+lval-1; ival > value; ival--) {
	    if (*ival == '_') {
		*ival = (char) 0;
		}
	    else if (*ival == ',') {
		*ival = (char) 0;
		}
	    else if (*ival == ' ') {
		*ival = (char) 0;
		}
	    else {
		break;
		}
	    }
	}
    if (iquot != NULL) {
	*iquot = cquot;
	}
    if (brack1 != NULL) {
	*brack1 = lbracket[0];
	}
    if (brack2 != NULL) {
	*brack2 = rbracket[0];
	}

    return (1);
}

char sptbv[468]={"O5O8B0B0B0B1B1B1B2B2B2B3B3B3B4B5B5B6B6B6B7B7B8B8B8B9B9B9B9A0A0A0A0A0A0A0A0A0A2A2A2A2A2A2A2A2A5A5A5A5A6A7A7A7A7A7A7A7A7A7A7F0F0F0F0F0F0F0F2F2F2F2F2F2F2F5F5F5F5F5F5F5F5F5F8F8F8F8F8F8G0G5G5G2G2G2G3G3G4G4G5G5G5G6G6G6G6G6K6K6K6K6K7K7K7K7K7K7K7K7K7K7K7K7K7K7K8K8K8K8K8K8K8K8K8K8K8K8K8K8K8K8K8K8K8K5K5K5K5K5K6K6K6K6K6K6K6K7K7K7K7K7K7K7K8K8K8K8K9K9K9M0M0M0M0M0M0M1M1M1M1M1M2M2M2M2M3M3M4M4M5M5M5M2M2M2M3M3M4M4M5M5M5M6M6M6M6M6M6M6M6M6M7M7M7M7M7M7M7M7M7M7M7M7M7M7M8M8M8M8M8M8M8"};

void
bv2sp (bv, b, v, isp)

double	*bv;	/* B-V Magnitude */
double	b;	/* B Magnitude used if bv is NULL */
double	v;	/* V Magnitude used if bv is NULL */
char	*isp;	/* Spectral type */
{
    double bmv;	/* B - V magnitude */
    int im;

    if (bv == NULL)
	bmv = b - v;
    else
	bmv = *bv;

    if (bmv < -0.32) {
	isp[0] = '_';
	isp[1] = '_';
	}
    else if (bmv > 2.00) {
	isp[0] = '_';
	isp[1] = '_';
	}
    else if (bmv < 0) {
	im = 2 * (32 + (int)(bmv * 100.0 - 0.5));
	isp[0] = sptbv[im];
	isp[1] = sptbv[im+1];
	}
    else {
	im = 2 * (32 + (int)(bmv * 100.0 + 0.5));
	isp[0] = sptbv[im];
	isp[1] = sptbv[im+1];
	}
    return;
}

char sptbr1[96]={"O5O8O9O9B0B0B0B0B0B1B1B1B2B2B2B2B2B3B3B3B3B3B3B5B5B5B5B6B6B6B7B7B7B7B8B8B8B8B8B9B9B9B9B9A0A0A0"};

char sptbr2[904]={"A0A0A0A0A0A0A0A0A2A2A2A2A2A2A2A2A2A2A2A2A2A2A2A5A5A5A5A5A5A5A5A5A5A5A7A7A7A7A7A7A7A7A7A7A7A7A7A7A7A7F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F0F2F2F2F2F2F2F2F2F2F2F2F5F5F5F5F5F5F5F5F5F5F5F5F5F5F8F8F8F8F8F8F8F8F8F8F8F8F8F8G0G0G0G0G0G0G0G0G2G2G2G2G2G5G5G5G5G5G5G5G5G8G8G8G8G8G8G8G8G8G8G8G8G8G8K0K0K0K0K0K0K0K0K0K0K0K0K0K0K0K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K2K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K5K7K7K7K7K7K7K7K7K7K7K7K7K7K7K7K7K7K7K7K7K7K7K7K7K7M0M0M0M0M0M0M0M0M0M0M0M0M0M0M0M0M0M0M0M0M0M0M0M0M1M1M1M1M1M1M1M1M1M1M1M1M1M1M1M2M2M2M2M2M2M2M2M2M2M2M2M2M2M2M3M3M3M3M3M3M3M3M3M3M3M4M4M4M4M4M4M4M4M4M4M4M4M4M4M5M5M5M5M5M5M5M5M5M5M5M5M5M5M5M5M5M5M5M5M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M6M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M7M8M8M8M8M8M8M8M8M8M8M8M8M8M8M8M8M8M8M8M8M8M8M8M8"};

void
br2sp (br, b, r, isp)

double	*br;	/* B-R Magnitude */
double	b;	/* B Magnitude used if br is NULL */
double	r;	/* R Magnitude used if br is NULL */
char	*isp;	/* Spectral type */
{
    double bmr;	/* B - R magnitude */
    int im;

    if (br == NULL)
	bmr = b - r;
    else
	bmr = *br;

    if (b == 0.0 && r > 2.0) {
	isp[0] = '_';
	isp[1] = '_';
	}
    else if (bmr < -0.47) {
	isp[0] = '_';
	isp[1] = '_';
	}
    else if (bmr > 4.50) {
	isp[0] = '_';
	isp[1] = '_';
	}
    else if (bmr < 0) {
	im = 2 * (47 + (int)(bmr * 100.0 - 0.5));
	isp[0] = sptbr1[im];
	isp[1] = sptbr1[im+1];
	}
    else {
	im = 2 * ((int)(bmr * 100.0 + 0.49));
	isp[0] = sptbr2[im];
	isp[1] = sptbr2[im+1];
	}
    return;
}


void
CatTabHead (refcat,sysout,nnfld,mprop,nmag,ranges,keyword,gcset,tabout,
	    classd,printxy,gobj1,fd)

int	refcat;		/* Catalog being searched */
int	sysout;		/* Output coordinate system */
int	nnfld;		/* Number of characters in ID column */
int	mprop;		/* 1 if proper motion in catalog */
int	nmag;		/* Number of magnitudes */
char	*ranges;	/* Catalog numbers to print */
char	*keyword;	/* Column to add to tab table output */
int	gcset;		/* 1 if there are any values in gc[] */
int	tabout;		/* 1 if output is tab-delimited */
int	classd; 	/* GSC object class to accept (-1=all) */
int	printxy;	/* 1 if X and Y included in output */
char	**gobj1;	/* Pointer to array of object names; NULL if none */
FILE	*fd;		/* Output file descriptor; none if NULL */

{
    int typecol;
    char headline[160];

    /* Set flag for plate, class, type, or 3rd magnitude column */
    if (refcat == BINCAT || refcat == SAO  || refcat == PPM ||
	refcat == ACT  || refcat == TYCHO2 || refcat == BSC)
	typecol = 1;
    else if ((refcat == GSC || refcat == GSCACT) && classd < -1)
	typecol = 3;
    else if (refcat == TMPSC)
	typecol = 4;
    else if (refcat == GSC || refcat == GSCACT ||
	refcat == UJC || refcat == IRAS ||
	refcat == USAC || refcat == USA1   || refcat == USA2 ||
	refcat == UAC  || refcat == UA1    || refcat == UA2 ||
	refcat == BSC  || (refcat == TABCAT&&gcset))
	typecol = 2;
    else
	typecol = 0;


    /* Print column headings */
    if (refcat == ACT)
	strcpy (headline, "act_id       ");
    else if (refcat == BSC)
	strcpy (headline, "bsc_id       ");
    else if (refcat == GSC || refcat == GSCACT)
	strcpy (headline, "gsc_id       ");
    else if (refcat == USAC)
	strcpy (headline,"usac_id       ");
    else if (refcat == USA1)
	strcpy (headline,"usa1_id       ");
    else if (refcat == USA2)
	strcpy (headline,"usa2_id       ");
    else if (refcat == UAC)
	strcpy (headline,"usnoa_id      ");
    else if (refcat == UA1)
	strcpy (headline,"usnoa1_id     ");
    else if (refcat == UA2)
	strcpy (headline,"usnoa2_id     ");
    else if (refcat == UJC)
	strcpy (headline,"usnoj_id      ");
    else if (refcat == TMPSC)
	strcpy (headline,"2mass_id      ");
    else if (refcat == TMXSC)
	strcpy (headline,"2mx_id        ");
    else if (refcat == SAO)
	strcpy (headline,"sao_id        ");
    else if (refcat == PPM)
	strcpy (headline,"ppm_id        ");
    else if (refcat == IRAS)
	strcpy (headline,"iras_id       ");
    else if (refcat == TYCHO)
	strcpy (headline,"tycho_id      ");
    else if (refcat == TYCHO2)
	strcpy (headline,"tycho2_id     ");
    else if (refcat == HIP)
	strcpy (headline,"hip_id        ");
    else
	strcpy (headline,"id            ");
    headline[nnfld] = (char) 0;

    if (sysout == WCS_GALACTIC)
	strcat (headline,"	long_gal   	lat_gal  ");
    else if (sysout == WCS_ECLIPTIC)
	strcat (headline,"	long_ecl   	lat_ecl  ");
    else if (sysout == WCS_B1950)
	strcat (headline,"	ra1950      	dec1950  ");
    else
	strcat (headline,"	ra      	dec      ");
    if (refcat == USAC || refcat == USA1 || refcat == USA2 ||
	refcat == UAC  || refcat == UA1  || refcat == UA2)
	strcat (headline,"	magb	magr	plate");
    if (refcat == TMPSC)
	strcat (headline,"	magj	magh	magk");
    else if (refcat==TYCHO || refcat==TYCHO2 || refcat==HIP || refcat==ACT)
	strcat (headline,"	magb	magv");
    else if (refcat == GSC || refcat == GSCACT)
	strcat (headline,"	mag	class	band	N");
    else if (refcat == UJC)
	strcat (headline,"	mag	plate");
    else
	strcat (headline,"	mag");
    if (typecol == 1)
	strcat (headline,"	type");
    if (mprop)
	strcat (headline,"	Ura    	Udec  ");
    if (ranges == NULL)
	strcat (headline,"	arcsec");
    if (refcat == TABCAT && keyword != NULL) {
	strcat (headline,"	");
	strcat (headline, keyword);
	}
    if (gobj1 != NULL)
	strcat (headline,"	object");
    if (printxy)
	strcat (headline, "	x      	y      ");
    if (tabout) {
	printf ("%s\n", headline);
	if (fd != NULL)
	    fprintf (fd, "%s\n", headline);
	}

    strcpy (headline, "---------------------");
    headline[nnfld] = (char) 0;
    strcat (headline,"	------------	------------");
    if (nmag == 2)
	strcat (headline,"	-----	-----");
    else
	strcat (headline,"	-----");
    if (refcat == GSC || refcat == GSCACT)
	strcat (headline,"	-----	----	-");
    else if (typecol == 1)
	strcat (headline,"	----");
    else if (typecol == 2)
	strcat (headline,"	-----");
    else if (typecol == 4)
	strcat (headline,"	-----");
    if (mprop)
	strcat (headline,"	-------	------");
    if (ranges == NULL)
	strcat (headline, "	------");
    if (refcat == TABCAT && keyword != NULL)
	strcat (headline,"	------");
    if (printxy)
	strcat (headline, "	-------	-------");
    if (tabout) {
	printf ("%s\n", headline);
	if (fd != NULL)
	    fprintf (fd, "%s\n", headline);
	}
}


/* TMCID -- Return 1 if string is 2MASS ID, else 0 */

int
tmcid (string, ra, dec)

char	*string;	/* Character string to check */
double	*ra;		/* Right ascension (returned) */
double	*dec;		/* Declination (returned) */
{
    char *sdec;
    char csign;
    int idec, idm, ids, ira, irm, irs;

    /* Check first character */
    if (string[0] != 'J' && string[0] != 'j')
	return (0);

    /* Find declination sign */
    sdec = strsrch (string, "-");
    if (sdec == NULL)
	sdec = strsrch (string,"+");
    if (sdec == NULL)
	return (0);

    /* Parse right ascension */
    csign = *sdec;
    *sdec = (char) 0;
    ira = atoi (string+1);
    irs = ira % 10000;
    ira = ira / 10000;
    irm = ira % 100;
    ira = ira / 100;
    *ra = (double) ira + ((double) irm) / 60.0 + ((double) irs) / 360000.0;
    *ra = *ra * 15.0;

    /* Parse declination */
    idec = atoi (sdec+1);
    ids = idec % 1000;
    idec = idec / 1000;
    idm = idec % 100;
    idec = idec / 100;
    *dec = (double) idec + ((double) idm) / 60.0 + ((double) ids) / 36000.0;
    return (1);
}

int
vothead (refcat, refcatname, mprop, typecol, ns, cra, cdec, drad)

int	refcat;		/* Catalog code */
char	*refcatname;	/* Name of catalog */
int	mprop;		/* Proper motion flag */
int	typecol;	/* Flag for spectral type */
int	ns;		/* Number of sources found in catalog */
double	cra;		/* Search center right ascension */
double	cdec;		/* Search center declination */
double	drad;		/* Radius to search in degrees */

{
    char *catalog = CatName (refcat, refcatname);
    int nf = 0;

    printf ("<!DOCTYPE VOTABLE SYSTEM \"http://us-vo.org/xml/VOTable.dtd\">\n");
    printf ("<VOTABLE version=\"v1.1\" xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n");
    printf ("xsi:noNamespaceSchemaLocation=\"http://www.ivoa.net/xml/VOTable/VOTable/v1.1\">\n");
    printf (" <DESCRIPTION>SAO/TDC %s Cone Search Response</DESCRIPTION>\n", catalog);
    printf ("  <DEFINITIONS>\n");
    printf ("   <COOSYS  ID=\"J2000\" equinox=\"2000.0\" epoch=\"2000.0\" system=\"ICRS\" >\n");
    printf ("  </COOSYS>\n");
    printf ("  </DEFINITIONS>\n");
    printf ("  <RESOURCE>\n");
    printf ("   <TABLE name=\"results\">\n");
    printf ("    <DESCRIPTION>\n");
    printf ("     %d objects within %.6f degrees of ra=%010.6f dec=%09.6f\n",
	    ns, drad, cra, cdec);
    printf ("    </DESCRIPTION>\n");
    printf ("<FIELD ucd=\"ID_MAIN\" datatype=\"char\" name=\"Catalog Name\">\n");
    if (refcat == USAC || refcat == USA1 || refcat == USA2 ||
	refcat == UAC  || refcat == UA1  || refcat == UA2 || refcat == UB1)
	printf ("  <DESCRIPTION>USNO Object Identifier</DESCRIPTION>\n");
    else if (refcat == TYCHO2)
	printf ("  <DESCRIPTION>Tycho-2 Object Identifier</DESCRIPTION>\n");
    else if (refcat == GSC2)
	printf ("  <DESCRIPTION>GSC II Object Identifier</DESCRIPTION>\n");
    else if (refcat == TMPSC)
	printf ("  <DESCRIPTION>2MASS Point Source Identifier</DESCRIPTION>\n");
    else if (refcat == GSC || refcat == GSCACT)
	printf ("  <DESCRIPTION>GSC Object Identifier</DESCRIPTION>\n");
    else if (refcat == SAO)
	printf ("  <DESCRIPTION>SAO Catalog Number</DESCRIPTION>\n");
    else if (refcat == PPM)
	printf ("  <DESCRIPTION>PPM Catalog Number</DESCRIPTION>\n");
    else
	printf ("  <DESCRIPTION>Object Identifier</DESCRIPTION>\n");
    printf ("</FIELD>\n");

    printf ("<FIELD ucd=\"POS_EQ_RA_MAIN\" datatype=\"float\" name=\"RA\" unit=\"degrees\" ref=\"J2000\">\n");
    printf ("  <DESCRIPTION>Right Ascension of Object (J2000)</DESCRIPTION>\n");
    printf ("</FIELD>\n");

    printf ("<FIELD ucd=\"POS_EQ_DEC_MAIN\" datatype=\"float\" name=\"DEC\" unit=\"degrees\" ref=\"J2000\">\n");
    printf ("   <DESCRIPTION>Declination of Object (J2000)</DESCRIPTION>\n");
    printf ("</FIELD>\n");

    if (refcat == USAC || refcat == USA1 || refcat == USA2 ||
	refcat == UAC  || refcat == UA1  || refcat == UA2) {
	printf ("<FIELD ucd=\"PHOT_PHG_B\" datatype=\"float\" name=\"B Magnitude\" unit=\"mag\">\n");
	printf ("  <DESCRIPTION>Photographic B Magnitude of Object</DESCRIPTION>\n");
	printf ("</FIELD>\n");
	printf ("<FIELD ucd=\"PHOT_PHG_R\" datatype=\"float\" name=\"R Magnitude\" unit=\"mag\">\n");
	printf ("  <DESCRIPTION>Photographic R Magnitude of Object</DESCRIPTION>\n");
	printf ("</FIELD>\n");
	printf ("<FIELD ucd=\"INST_PLATE_NUMBER\" datatype=\"int\" name=\"PlateID\">\n");
	printf ("  <DESCRIPTION>USNO Plate ID of star</DESCRIPTION>\n");
	printf ("</FIELD>\n");
 nf = 7;
 }
    else if (refcat == TYCHO2) {
	printf ("<FIELD name=\"BTmag\" ucd=\"PHOT_TYCHO_B\" datatype=\"float\" unit=\"mag\">\n");
	printf ("  <DESCRIPTION> Tycho-2 BT magnitude </DESCRIPTION>\n");
	printf ("</FIELD>\n");
	printf ("<FIELD name=\"VTmag\" ucd=\"PHOT_TYCHO_V\" datatype=\"float\" unit=\"mag\">\n");
	printf ("  <DESCRIPTION> Tycho-2 VT magnitude </DESCRIPTION>\n");
 nf = 8;
	}
    else if (refcat == GSC || refcat == GSCACT) {
	printf ("<FIELD name=\"Vmag\" ucd=\"PHOT_GSC_V\" datatype=\"float\" unit=\"mag\">\n");
	printf ("  <DESCRIPTION> GSC V magnitude </DESCRIPTION>\n");
	printf ("</FIELD>\n");
 nf = 8;
	}
    else if (refcat == GSC2) {
	}
    else if (refcat == TMPSC) {
	printf ("<FIELD name=\"Jmag\" ucd=\"PHOT_MAG_J\" datatype=\"float\" unit=\"mag\">\n");
	printf ("  <DESCRIPTION> Johnson J magnitude </DESCRIPTION>\n");
	printf ("</FIELD>\n");
	printf ("<FIELD name=\"Hmag\" ucd=\"PHOT_MAG_H\" datatype=\"float\" unit=\"mag\">\n");
	printf ("  <DESCRIPTION> Johnson H magnitude </DESCRIPTION>\n");
	printf ("</FIELD>\n");
	printf ("<FIELD name=\"Kmag\" ucd=\"PHOT_MAG_K\" datatype=\"float\" unit=\"mag\">\n");
	printf ("  <DESCRIPTION> Johnson K magnitude </DESCRIPTION>\n");
	printf ("</FIELD>\n");
 nf = 7;
	}
    else if (refcat == SAO) {
	printf ("<FIELD name=\"Vmag\" ucd=\"PHOT_MAG_V\" datatype=\"float\" unit=\"mag\">\n");
	printf ("  <DESCRIPTION> SAO Catalog V magnitude (7)</DESCRIPTION>\n");
	printf ("</FIELD>\n");
 nf = 8;
	} 
    else if (refcat == PPM) {
	printf ("<FIELD name=\"Vmag\" ucd=\"PHOT_MAG_V\" datatype=\"float\" unit=\"mag\">\n");
	printf ("  <DESCRIPTION> PPM Catalog V magnitude (7)</DESCRIPTION>\n");
	printf ("</FIELD>\n");
 nf = 8;
	} 
    if (typecol == 1) {
	printf ("<FIELD ucd=\"SPECT_TYPE_GENERAL\" name=\"Spectral Type\">\n");
	printf ("  <DESCRIPTION>Spectral Type from catalog</DESCRIPTION>\n");
	printf ("</FIELD>\n");
	}
    printf ("<FIELD ucd=\"POS_ANG_DIST_GENERAL\" datatype=\"float\" name=\"Offset\" unit=\"degrees\">\n");
    printf ("  <DESCRIPTION>Radial distance from requested position</DESCRIPTION>\n");
    printf ("</FIELD>\n");
    printf ("<DATA> <TABLEDATA>\n");

    return (nf);
}


void
vottail ()
{
    printf ("        </TABLEDATA> </DATA>\n");
    printf ("      </TABLE>\n");
    printf ("    </RESOURCE>\n");
    printf ("</VOTABLE>\n");
    return;
}


/*    Polynomial least squares fitting program, almost identical to the
 *    one in Bevington, "Data Reduction and Error Analysis for the
 *    Physical Sciences," page 141.  The argument list was changed and
 *    the weighting removed.
 *      y = a(1) + a(2)*(x-x0) + a(3)*(x-x0)**2 + a(3)*(x-x0)**3 + . . .
 */

static double determ();

void
polfit (x, y, x0, npts, nterms, a, stdev)

double	*x;		/* Array of independent variable points */
double	*y;		/* Array of dependent variable points */
double	x0;		/* Offset to independent variable */
int	npts;		/* Number of data points to fit */
int	nterms;		/* Number of parameters to fit */
double	*a;		/* Vector containing current fit values */
double	*stdev; 	/* Standard deviation of fit (returned) */
{
    double sigma2sum;
    double xterm,yterm,xi,yi;
    double *sumx, *sumy;
    double *array;
    int i,j,k,l,n,nmax;
    double delta;

    /* accumulate weighted sums */
    nmax = 2 * nterms - 1;
    sumx = (double *) calloc (nmax, sizeof(double));
    sumy = (double *) calloc (nterms, sizeof(double));
    for (n = 0; n < nmax; n++)
	sumx[n] = 0.0;
    for (j = 0; j < nterms; j++)
	sumy[j] = 0.0;
    for (i = 0; i < npts; i++) {
	xi = x[i] - x0;
	yi = y[i];
	xterm = 1.0;
	for (n = 0; n < nmax; n++) {
	    sumx[n] = sumx[n] + xterm;
	    xterm = xterm * xi;
	    }
	yterm = yi;
	for (n = 0; n < nterms; n++) {
	    sumy[n] = sumy[n] + yterm;
	    yterm = yterm * xi;
	    }
	}

    /* Construct matrices and calculate coeffients */
    array = (double *) calloc (nterms*nterms, sizeof(double));
    for (j = 0; j < nterms; j++) {
	for (k = 0; k < nterms; k++) {
	    n = j + k;
	    array[j+k*nterms] = sumx[n];
	    }
	}
    delta = determ (array, nterms);
    if (delta == 0.0) {
	*stdev = 0.;
	for (j = 0; j < nterms; j++)
	    a[j] = 0. ;
	free (array);
	free (sumx);
	free (sumy);
	return;
	}

    for (l = 0; l < nterms; l++) {
	for (j = 0; j < nterms; j++) {
	    for (k = 0; k < nterms; k++) {
		n = j + k;
		array[j+k*nterms] = sumx[n];
		}
	    array[j+l*nterms] = sumy[j];
	    }
	a[l] = determ (array, nterms) / delta;
	}

    /* Calculate sigma */
    sigma2sum = 0.0;
    for (i = 0; i < npts; i++) {
	yi = polcomp (x[i], x0, nterms, a);
	sigma2sum = sigma2sum + ((y[i] - yi) * (y[i] - yi));
	}
    *stdev = sqrt (sigma2sum / (double) (npts - 1));

    free (array);
    free (sumx);
    free (sumy);
    return;
}


/*--- Calculate the determinant of a square matrix
 *    This subprogram destroys the input matrix array
 *    From Bevington, page 294.
 */

static double
determ (array, norder)

double	*array;		/* Input matrix array */
int	norder;		/* Order of determinant (degree of matrix) */

{
    double save, det;
    int i,j,k,k1, zero;

    det = 1.0;
    for (k = 0; k < norder; k++) {

	/* Interchange columns if diagonal element is zero */
	if (array[k+k*norder] == 0) {
	    zero = 1;
	    for (j = k; j < norder; j++) {
		if (array[k+j*norder] != 0.0)
		    zero = 0;
		}
	    if (zero)
		return (0.0);

	    for (i = k; i < norder; i++) {
		save = array[i+j*norder]; 
		array[i+j*norder] = array[i+k*norder];
		array[i+k*norder] = save ;
		}
	    det = -det;
	    }

	/* Subtract row k from lower rows to get diagonal matrix */
	det = det * array[k+k*norder];
	if (k < norder - 1) {
	    k1 = k + 1;
	    for (i = k1; i < norder; i++) {
		for (j = k1; j < norder; j++) {
		    array[i+j*norder] = array[i+j*norder] -
				      (array[i+k*norder] * array[k+j*norder] /
				      array[k+k*norder]);
		    }
		}
	    }
	}
	return (det);
}

/* POLCOMP -- Polynomial evaluation
 *	Y = A(1) + A(2)*X + A(3)*X**2 + A(3)*X**3 + . . . */

double
polcomp (xi, x0, norder, a)

double	xi;	/* Independent variable */
double	x0;	/* Offset to independent variable */
int	norder;	/* Number of coefficients */
double	*a;	/* Vector containing coeffiecients */
{
    double xterm, x, y;
    int iterm;

    /* Accumulate polynomial value */
    x = xi - x0;
    y = 0.0;
    xterm = 1.0;
    for (iterm = 0; iterm < norder; iterm++) {
	y = y + a[iterm] * xterm;
	xterm = xterm * x;
	}
    return (y);
}

/* Mar  2 1998	Make number and second magnitude optional
 * Oct 21 1998	Add RefCat() to set reference catalog code
 * Oct 26 1998	Include object names in star catalog entry structure
 * Oct 29 1998	Return coordinate system and title from RefCat
 * Nov 20 1998	Add USNO A-2.0 catalog and return different code
 * Dec  9 1998	Add Hipparcos and Tycho catalogs
 *
 * Jan 26 1999	Add subroutines to deal with ranges of numbers
 * Feb  8 1999	Fix bug initializing ACT catalog
 * Feb 11 1999	Change starcat.insys to starcat.coorsys
 * May 19 1999	Separate catalog subroutines into separate file
 * May 19 1999	Add CatNum() to return properly formatted catalog number
 * May 20 1999	Add date/time conversion subroutines translated from Fortran
 * May 28 1999	Fix bug in CatNum() which omitted GSC
 * Jun  3 1999	Add return to CatNum()
 * Jun  3 1999	Add CatNumLen()
 * Jun 16 1999	Add SearchLim(), used by all catalog search subroutines
 * Jun 30 1999	Add isrange() to check to see whether a string is a range
 * Jul  1 1999	Move date and time utilities to dateutil.c
 * Jul 15 1999	Add getfilebuff()
 * Jul 23 1999	Add Bright Star Catalog
 * Aug 16 1999	Add RefLim() to set catalog search limits
 * Sep 21 1999	In isrange(), check for x
 * Oct  5 1999	Add setoken(), nextoken(), and getoken()
 * Oct 15 1999	Fix format eror in error message
 * Oct 20 1999	Use strchr() in range decoding
 * Oct 21 1999	Fix declarations after lint
 * Oct 21 1999	Fix arguments to catopen() and catclose() after lint
 * Nov  3 1999	Fix bug which lost last character on a line in getoken
 * Dec  9 1999	Add next_token(); set pointer to next token in first_token
 *
 * Jan 11 2000	Use nndec for Starbase files, too
 * Feb 10 2000	Read coordinate system, epoch, and equinox from Starbase files
 * Mar  1 2000	Add isfile() to tell whether string is name of readable file
 * Mar  1 2000	Add agets() to return value from keyword = value in string
 * Mar  1 2000	Add isfile() to tell if a string is the name of a readable file
 * Mar  1 2000	Add agets() to read a parameter from a comment line of a file
 * Mar  8 2000	Add ProgCat() to return catalog flag from program name
 * Mar 13 2000	Add PropCat() to return whether catalog has proper motions
 * Mar 27 2000	Clean up code after lint
 * May 22 2000	Add bv2sp() to approximate main sequence spectral type from B-V
 * May 25 2000	Add Tycho 2 catalog
 * May 26 2000	Add field size argument to CatNum() and CatNumLen()
 * Jun  2 2000	Set proper motion for all catalog types in RefCat()
 * Jun 26 2000	Add XY image coordinate system
 * Jul 26 2000	Include math.h to get strtod() on SunOS machines
 * Aug  2 2000	Allow up to 14 digits in catalog IDs
 * Sep  1 2000	Add option in CatNum to print leading zeroes if nnfld > 0
 * Sep 22 2000	Add br2sp() to approximate main sequence spectral type from B-R
 * Oct 24 2000	Add USNO option to RefCat()
 * Nov 21 2000	Clean up logic in RefCat()
 * Nov 28 2000	Try PPMra and SAOra in RefCat() as well as PPM and SAO
 * Dec 13 2000	Add StrNdec() to get number of decimal places in star numbers
 *
 * Jan 17 2001	Add vertical bar (|) as column separator
 * Feb 28 2001	Separate .usno stars from usa stars
 * Mar  1 2001	Add CatName()
 * Mar 19 2001	Fix setting of ra-sorted PPM catalog in RefCat()
 * Mar 27 2001	Add option to omit leading spaces in CatNum()
 * May  8 2001	Fix bug in setokens() which failed to deal with quoted tokens
 * May 18 2001	Fix bug in setokens() which returned on ntok < maxtok
 * May 22 2001	Add GSC-ACT catalog
 * May 24 2001	Add 2MASS Point Source Catalog
 * Jun  7 2001	Return proper motion flag and number of magnitudes from RefCat()
 * Jun 13 2001	Fix rounding problem in rgetr8()
 * Jun 13 2001	Use strncasecmp() instead of two calls to strncmp() in RefCat()
 * Jun 15 2001	Add CatName() and CatID()
 * Jun 18 2001	Add maximum length of returned string to getoken(), nextoken()
 * Jun 18 2001	Pad returned string in getoken(), nextoken()
 * Jun 19 2001	Treat "bar" like "tab" as special single character terminator
 * Jun 19 2001	Allow tab table options for named catalogs in RefCat()
 * Jun 19 2001	Change number format to integer for Hipparcos catalog
 * Jun 19 2001	Add refcatname as argument to CatName()
 * Jun 20 2001	Add GSC II
 * Jun 25 2001	Fix GSC II number padding
 * Aug 20 2001	Add NumNdec() and guess number of decimal places if needed
 * Sep 20 2001	Add CatMagName()
 * Sep 25 2001	Move isfile() to fileutil.c
 *
 * Feb 26 2002	Fix agets() to work with keywords at start of line
 * Feb 26 2002	Add option in agets() to return value to end of line or /
 * Mar 25 2002	Fix bug in agets() to find second occurence of string 
 * Apr 10 2002	Add CatMagNum() to translate single letters to mag sequence number
 * May 13 2002	In agets(), allow arbitrary number of spaces around : or =
 * Jun 10 2002	In isrange(), return 0 if string is null or empty
 * Aug  1 2002	In agets(), read through / if reading to end of line
 * Sep 18 2002	Add vothead() and vottail() for VOTable output from scat
 * Oct 26 2002	Fix bugs in vothead()
 *
 * Jan 23 2003	Add USNO-B1.0 Catalog
 * Jan 27 2003	Adjust dra in RefLimit to max width in RA seconds in region
 * Mar 10 2003	Clean up RefLim() to better represent region to be searched
 * Mar 24 2003	Add CatCode() to separate catalog type from catalog parameters
 * Apr 14 2003	Add setrevmsg() and getrevmsg()
 * Apr 24 2003	Add UCAC1 Catalog
 * Apr 24 2003	Return 5 magnitudes for GSC II, including epoch
 * Apr 24 2003	Fix bug dealing with HST GSC
 * May 21 2003	Add TMIDR2=2MASS IDR2, and new 2MASS=TMPSC
 * May 28 2003	Fix bug checking for TMIDR2=2MASS IDR2; 11 digits for TMPSC
 * May 30 2003	Add UCAC2 catalog
 * Sep 19 2003	Fix bug which shrank search width in RefLim()
 * Sep 26 2003	In RefLim() do not use cos(90)
 * Sep 29 2003	Add proper motion margins and wrap arguments to RefLim()
 * Oct  1 2003	Add code in RefLim() for all-sky images
 * Oct  6 2003	Add code in RefLim() to cover near-polar searches
 * Dec  4 2003	Implement GSC 2.3 and USNO-YB6
 * Dec 15 2003	Set refcat to 0 if no catalog name and refcatname to NULL
 *
 * Jan  5 2004	Add SDSS catalog
 * Jan 12 2004	Add 2MASS Extended Source Catalog
 * Jan 14 2004	Add CatSource()
 * Jan 22 2004	Add global flag degout to print limits in degrees
 *
 * May 12 2005	Add tmcid() to decode 2MASS ID strings
 * May 18 2005	Change Tycho-2 magnitudes to include B and V errors
 * Jul 27 2005	Add DateString() to convert epoch to desired format
 * Aug  2 2005	Fix setoken() to deal with whitespace before end of line
 * Aug  2 2005	Use static maxtokens set to header MAXTOKENS
 * Aug  5 2005	Add code to support magnitude errors in Tycho2 and 2MASS PSC
 * Aug 11 2005	Add setdateform() so date can be formatted anywhere
 * Aug 11 2005	Add full FITS ISO date as EP_ISO
 * Aug 16 2005	Make all string matches case-independent
 *
 * Mar 15 2006	Clean up VOTable code
 * Mar 17 2006	Return number of fields from vothead()
 * Apr  7 2006	Keep quoted character strings together as a single token
 * Jun  6 2006	Add SKY2000 catalog for wide fields
 * Jun 20 2006	In CatSource() increase catalog descriptor from 32 to 64 chars
 *
 * Jan 10 2007	Add polynomial fitting subroutines from polfit.c
 * Jan 11 2007	Move token access subroutines to fileutil.c
 * Mar 13 2007	Set title accordingly for gsc22 and gsc23 and gsc2 options
 * Jul  8 2007	Set up 8 magnitudes for GSC 2.3 from GALEX
 * Jul 13 2007	Add SkyBot solar system object search
 * Nov 28 2006	Add moveb() from binread.c
 *
 * Aug 19 2009	If pole is included, set RA range to 360 degrees in RefLim()
 * Sep 25 2009	Change name of moveb() to movebuff()
 * Sep 28 2009	For 2MASS Extended Source catalog, use 2mx_id, not 2mass_id
 * Sep 30 2009	Add UCAC3 catalog
 * Oct 26 2009	Do not wrap in RefLim() if dra=360
 * Nov  6 2009	Add UCAC3 catalog to ProgCat()
 * Nov 13 2009	Add UCAC3 and UCAC2 to CatMagName() and CatMagNum()
 *
 * Mar 31 2010	Fix south pole search
 * Apr 06 2010	Add fillblank argument to agets()
 * Apr 06 2010	In agets() search until keyword[: or =] or end of string
 * Sep 14 2010	Add BSC radius of 7200 to CatRad() and number field of 4
 *
 * May 16 2012	Save maximum value in range data structure
 * Jul 26 2012	Fix xterm computation in polcomp() from + to *
 *		(found by Raymond Carlberg of U.Toronto)
 * Oct 02 2012	Skip trailing right bracket in aget*()
 * Oct 23 2012	Add "of" as possible connector in aget*()
 *
 * Feb 15 2013	Add UCAC4 catalog
 * Sep 23 2013	Finish adding UCAC4 catalog
 *
 * Nov 25 2015	Add tab as an assignment character in agets()
 *
 * Jul 31 2018	Keep RA limits to +- 180 (suggested by Ed Los, Harvard)
 *
 * Oct 29 2019	Drop trailing commas as well as underscores and spaces
 *
 * Jul  6 2021	If keyword is surrounded by brackets, keep them.
 */
