/* File wcstools/libwcs/fileutil.c
 * February 2, 2022
 * By Jessica Mink, SAO Telescope Data Center

 * Copyright (C) 1999-2022
 * Smithsonian Astrophysical Observatory, Cambridge, MA, USA
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

/** ASCII file utilities
/** Read, parse, and find out things about ASCII files
 *
 ** Read an entire file
 *
 * Subroutine:	getfilebuff (filename)
 *		Return entire file contents in a character string
 * Subroutine:	putfilebuff (filename, string)
 *		Save a character string into a file
 *
 ** Find out features of a file
 *
 * Subroutine:	getfilesize (filepath)
 *		Return size of a binary or ASCII file
 * Subroutine:	getfilelines (filepath)
 *		Return number of lines in an ASCII file
 * Subroutine:	getmaxlength (filepath)
 *		Return length of longest line in file
 * Subroutine:	isimlist (filepath)
 *		Return 1 if file is list of FITS or IRAF image files, else 0
 * Subroutine:	isimlistd (filename, rootdir)
 *		Return 1 if file is list of FITS or IRAF image files, else 0
 * Subroutine:	isfilelist (filepath, rootdir)
 *		Return 1 if file is list of readable files, else 0
 * Subroutine:	isfile (filepath)
 *		Return 1 if file is a readable file, else 0
 * Subroutine:	istiff (filepath)
 *		Return 1 if file is a readable TIFF graphics file, else 0
 * Subroutine:	isjpeg (filepath)
 *		Return 1 if file is a readable JPEG graphics file, else 0
 *
 ** Parsing strings
 *
 * Subroutine:	first_token (diskfile, ncmax, token)
 *		Return the first token from the next line of an ASCII file
 * Subroutine:	next_line (diskfile, ncmax, line)
 *		Read the next line of an ASCII file and return its length
 * Subroutine:  stc2s (spchar, string)
 *		Replace character in string with space
 * Subroutine:  sts2c (spchar, string)
 *		Replace spaces in string with character
 * Subroutine:	setoken (tokens, string, cwhite)
 *		Tokenize a string for easy decoding
 * Subroutine:	nextoken (tokens, token, maxchars)
 *		Get next token from tokenized string
 * Subroutine:	getoken (tokens, itok, token, maxchars)
 *		Get specified token from tokenized string
 *
 ** Ranges
 *
 * Subroutine:	RangeInit (string, ndef)
 *		Return structure containing ranges of numbers
 * Subroutine:	isrange (string)
 *		Return 1 if string is a range, else 0
 * Subroutine:	rstart (range)
 *		Restart at beginning of range
 * Subroutine:	rgetn (range)
 *		Return number of values from range structure
 * Subroutine:	rgeti4 (range)
 *		Return next number from range structure as 4-byte integer
 * Subroutine:	rgetr8 (range)
 *		Return next number from range structure as 8-byte floating point number
 *
 ** Values from any ASCII keyword = value string in a file
 *
 * Subroutine:	agetl (string, iline, line, lline)
		Return one line from an ASCII string with LF, CR, EOS line termination
 * Subroutine:	ageti4 (string, keyword, ival)
 *		Read int value from a file where keyword=value, anywhere on a line
 * Subroutine:	agetr8 (string, keyword, dval)
 *		Read double value from a file where keyword=value, anywhere on a line
 * Subroutine:  agetw (string, keyword, word, maxlength)
 *		Read first word of string where keyword=word, anywhere on a line
 * Subroutine:	agets (string, keyword, lval, fillblank, value)
 *		Read value from a file where keyword=value, anywhere on a line
 *
 ** Polynomials
 *
 * Subroutine:	polfit (x, y, x0, npts, nterms, a, stdev)
 *		Polynomial least squares fitting program
 * Subroutine:	determ (array, norder)
 *		Calculate the determinant of a square matrix (Bevington, page 294)
 * Subroutine:	polcomp (xi, x0, norder, a)
 *		Polynomial evaluation Y = A(1) + A(2)*X + A(3)*X^2 + A(3)*X^3 + ...
 */

#include <stdlib.h>
#ifndef VMS
#include <unistd.h>
#endif
#include <stdio.h>
#include <fcntl.h>
#include <sys/file.h>
#include <errno.h>
#include <string.h>
#include "fitsfile.h"
#include <sys/types.h>
#include <sys/stat.h>
#define SZ_PATHNAME	128


/* GETFILELINES -- Return number of lines in one file */

int
getfilelines (filepath)

char    *filepath;      /* Pathname of file for which to find number of lines */
{

    char *buffer, *bufline;
    int nlines = 0;
    char newline = 10;

    /* Read file */
    buffer = getfilebuff (filepath);

    /* Count lines in file */
    if (buffer != NULL) {
	bufline = buffer;
	nlines = 0;
	while ((bufline = strchr (bufline, newline)) != NULL) {
            bufline = bufline + 1;
            nlines++;
	    }
	free (buffer);
	return (nlines);
	}
    else {
	return (0);
	}
}


/* GETMAXLENGTH -- Return length of longest line in file */

int
getmaxlength (filepath)

char    *filepath;      /* Pathname of file for which to find number of lines */
{

    char *buffer, *bufline, *buff0;
    int thislength;
    int nlines = 0;
    int maxlength = 0;
    char newline = 10;

    /* Read file */
    buffer = getfilebuff (filepath);

    /* Find longest line in file */
    if (buffer != NULL) {
	bufline = buffer;
	buff0 = buffer;
	while ((bufline = strchr (bufline, newline)) != NULL) {
            bufline = bufline + 1;
	    thislength = bufline - buff0;
	    if (thislength > maxlength)
		maxlength = thislength;
	    buff0 = bufline;
	    }
	free (buffer);
	return (maxlength);
	}
    else {
	return (0);
	}
}


/* GETFILEBUFF -- return entire file contents in one character string */

char *
getfilebuff (filepath)

char    *filepath;      /* Name of file from which to read */
{

    FILE *diskfile;
    int lfile, nr, lbuff, ipt, ibuff;
    char *buffer, *newbuff, *nextbuff;

    /* Treat stdin differently */
    if (!strcmp (filepath, "stdin")) {
	lbuff = 5000;
	lfile = lbuff;
	buffer = NULL;
	ipt = 0;
	for (ibuff = 0; ibuff < 10; ibuff++) {
	    if ((newbuff = realloc (buffer, lfile+1)) != NULL) {
		buffer = newbuff;
		nextbuff = buffer + ipt;
        	nr = fread (nextbuff, 1, lbuff, stdin);
		if (nr == lbuff)
		    break;
		else {
		    ipt = ipt + lbuff;
		    lfile = lfile + lbuff;
		    }
		}
	    else {
		fprintf (stderr,"GETFILEBUFF: No room for %d-byte buffer\n",
			 lfile);
		break;
		}
	    }
	return (buffer);
	}

    /* Open file */
    if ((diskfile = fopen (filepath, "rb")) == NULL)
        return (NULL);

   /* Find length of file */
    if (fseek (diskfile, 0, 2) == 0)
        lfile = ftell (diskfile);
    else
        lfile = 0;
    if (lfile < 1) {
	fprintf (stderr,"GETFILEBUFF: File %s is empty\n", filepath);
	fclose (diskfile);
	return (NULL);
	}

    /* Allocate buffer to hold entire file and read it */
    if ((buffer = calloc (1, lfile+1)) != NULL) {
 	fseek (diskfile, 0, 0);
        nr = fread (buffer, 1, lfile, diskfile);
	if (nr < lfile) {
	    fprintf (stderr,"GETFILEBUFF: File %s: read %d / %d bytes\n",
		     filepath, nr, lfile);
	    free (buffer);
	    fclose (diskfile);
	    return (NULL);
	    }
	buffer[lfile] = (char) 0;
	fclose (diskfile);
	return (buffer);
	}
    else {
	fprintf (stderr,"GETFILEBUFF: File %s: no room for %d-byte buffer\n",
		 filepath, lfile);
	fclose (diskfile);
	return (NULL);
	}
}


/* PUTFILEBUFF -- Write a character string to a file */

int
putfilebuff (filepath, buffer)

char    *filepath;      /* Pathname of file to which to write */
char	*buffer;	/* Character string to write to the file */
{

    FILE *diskfile;
    int nw, lbuff, nbytes;

    /* Open file */
    if ((diskfile = fopen (filepath, "w+b")) == NULL) {
	fprintf (stderr,"PUTFILEBUFF: Could not open %s to write\n", filepath);
        return (1);
	}

    /* Find length of string */
    lbuff = strlen (buffer);
    if (lbuff < 1) {
	fprintf (stderr,"PUTFILEBUFF: String is empty; %s not written.\n", filepath);
	fclose (diskfile);
	return (1);
	}

    /* Write entire string to file */
    nbytes = lbuff + 1;
    nw = fwrite (buffer, 1, nbytes, diskfile);
    if (nw < nbytes) {
	fprintf (stderr,"PUTFILEBUFF: File %s: wrote %d / %d bytes\n",
		     filepath, nw, nbytes);
	fclose (diskfile);
	return (1);
	}
    fclose (diskfile);
    return (0);
}


/* GETFILESIZE -- return size of one file in bytes */

int
getfilesize (filepath)

char    *filepath;      /* Name of file for which to find size */
{
    struct stat statbuff;

    if (stat (filepath, &statbuff))
	return (0);
    else
	return ((int) statbuff.st_size);
}

int
getfilesize0 (filepath)

char    *filepath;      /* Name of file for which to find size */
{
    FILE *diskfile;
    long filesize;

    /* Open file */
    if ((diskfile = fopen (filepath, "rb")) == NULL)
        return (-1);

    /* Move to end of the file */
    if (fseek (diskfile, 0, 2) == 0)

        /* Position is the size of the file */
        filesize = ftell (diskfile);

    else
        filesize = -1;

    fclose (diskfile);

    return ((int) filesize);
}


/* ISIMLIST -- Return 1 if list of FITS or IRAF files, else 0 */
int
isimlist (filepath)

char    *filepath;      /* Name of possible list file */
{
    FILE *diskfile;
    char token[SZ_PATHNAME];
    int ncmax = 127;

    if ((diskfile = fopen (filepath, "r")) == NULL)
	return (0);
    else {
	first_token (diskfile, ncmax, token);
	fclose (diskfile);
	if (isfits (token) | isiraf (token))
	    return (1);
	else
	    return (0);
	}
}


/* ISIMLISTD -- Return 1 if list of FITS or IRAF files, else 0 */
int
isimlistd (filename, rootdir)

char    *filename;	/* Name of possible list file */
char    *rootdir;	/* Name of root directory for files in list */
{
    FILE *diskfile;
    char token[SZ_PATHNAME];
    char filepath[SZ_PATHNAME];
    int ncmax = 127;

    if ((diskfile = fopen (filename, "r")) == NULL)
	return (0);
    else {
	first_token (diskfile, ncmax, token);
	fclose (diskfile);
	if (rootdir != NULL) {
	    strcpy (filepath, rootdir);
	    strcat (filepath, "/");
	    strcat (filepath, token);
	    }
	else
	    strcpy (filepath, token);
	if (isfits (filepath) | isiraf (filepath))
	    return (1);
	else
	    return (0);
	}
}


/* ISFILELIST -- Return 1 if list of readable files, else 0 */
int
isfilelist (filename, rootdir)

char    *filename;      /* Name of possible list file */
char    *rootdir;	/* Name of root directory for files in list */
{
    FILE *diskfile;
    char token[SZ_PATHNAME];
    char filepath[SZ_PATHNAME];
    int ncmax = 127;

    if ((diskfile = fopen (filename, "r")) == NULL)
	return (0);
    else {
	first_token (diskfile, ncmax, token);
	fclose (diskfile);
	if (rootdir != NULL) {
	    strcpy (filepath, rootdir);
	    strcat (filepath, "/");
	    strcat (filepath, token);
	    }
	else
	    strcpy (filepath, token);
	if (isfile (filepath))
	    return (1);
	else
	    return (0);
	}
}


/* ISFILE -- Return 1 if file is a readable file, else 0 */

int
isfile (filepath)

char    *filepath;      /* Name of file to check */
{
    struct stat statbuff;

    if (!strcasecmp (filepath, "stdin"))
	return (1);
    else if (access (filepath, R_OK))
	return (0);
    else if (stat (filepath, &statbuff))
        return (0);
    else {
        if (S_ISDIR(statbuff.st_mode) && S_IFDIR)
	    return (2);
	else
	    return (1);
	}
}


/* NEXT_LINE -- Read the next line of an ASCII file, returning length */
/*              Lines beginning with # are ignored*/

int
next_line (diskfile, ncmax, line)

FILE	*diskfile;		/* File descriptor for ASCII file */
int	ncmax;			/* Maximum number of characters returned */
char	*line;			/* Next line (returned) */
{
    char *lastchar;

    /* If line can be read, add null at the end of the first token */
    if (fgets (line, ncmax, diskfile) != NULL) {
	while (line[0] == '#') {
	    (void) fgets (line, ncmax, diskfile);
	    }

	/* If only character is a control character, return a NULL string */
	if ((strlen(line)==1) && (line[0]<32)){
	    line[0] = (char)0;
	    return (1);
	    }
	lastchar = line + strlen (line) - 1;

	/* Remove trailing spaces or control characters */
	while (*lastchar <= 32)
	    *lastchar-- = 0;

	return (strlen (line));
	}
    else
	return (0);
}


/* FIRST_TOKEN -- Return first token from the next line of an ASCII file */
/*                Lines beginning with # are ignored */

int
first_token (diskfile, ncmax, token)

FILE	*diskfile;		/* File descriptor for ASCII file */
int	ncmax;			/* Maximum number of characters returned */
char	*token;			/* First token on next line (returned) */
{
    char *lastchar, *lspace;

    /* If line can be read, add null at the end of the first token */
    if (fgets (token, ncmax, diskfile) != NULL) {
	while (token[0] == '#') {
	    (void) fgets (token, ncmax, diskfile);
	    }

	/* If only character is a control character, return a NULL */
	if ((strlen(token)==1) && (token[0]<32)){
	    token[0]=0;
	    return (1);
	    }
	lastchar = token + strlen (token) - 1;

	/* Remove trailing spaces or control characters */
	while (*lastchar <= 32)
	    *lastchar-- = 0;

	if ((lspace = strchr (token, ' ')) != NULL) {
	    *lspace = (char) 0;
	    }
	return (1);
	}
    else
	return (0);
}


/* Replace character in string with space */

int
stc2s (spchar, string)

char	*spchar;	/* Character to replace with spaces */
char	*string;
{
    int i, lstr, n;
    lstr = strlen (string);
    n = 0;
    for (i = 0; i < lstr; i++) {
	if (string[i] == spchar[0]) {
	    n++;
	    string[i] = ' ';
	    }
	}
    return (n);
}


/* Replace spaces in string with character */

int
sts2c (spchar, string)

char	*spchar;	/* Character with which to replace spaces */
char	*string;
{
    int i, lstr, n;
    lstr = strlen (string);
    n = 0;
    for (i = 0; i < lstr; i++) {
	if (string[i] == ' ') {
	    n++;
	    string[i] = spchar[0];
	    }
	}
    return (n);
}


/* ISTIFF -- Return 1 if TIFF file, else 0 */
int
istiff (filepath)

char    *filepath;      /* Name of file to check */
{
    int diskfile;
    char keyword[16];
    int nbr;

    /* First check to see if this is an assignment */
    if (strchr (filepath, '='))
        return (0);

    /* Check file extension */
    if (strsrch (filepath, ".tif") ||
        strsrch (filepath, ".tiff") ||
        strsrch (filepath, ".TIFF") ||
        strsrch (filepath, ".TIF"))
        return (1);

 /* If no TIFF file suffix, try opening the file */
    else {
        if ((diskfile = open (filepath, O_RDONLY)) < 0)
            return (0);
        else {
            nbr = read (diskfile, keyword, 4);
            close (diskfile);
            if (nbr < 4)
                return (0);
            else if (!strncmp (keyword, "II", 2))
                return (1);
            else if (!strncmp (keyword, "MM", 2))
                return (1);
            else
                return (0);
            }
        }
}


/* ISJPEG -- Return 1 if JPEG file, else 0 */
int
isjpeg (filepath)

char    *filepath;      /* Name of file to check */
{
    int diskfile;
    char keyword[16];
    int nbr;

    /* First check to see if this is an assignment */
    if (strchr (filepath, '='))
        return (0);

    /* Check file extension */
    if (strsrch (filepath, ".jpg") ||
        strsrch (filepath, ".jpeg") ||
        strsrch (filepath, ".JPEG") ||
        strsrch (filepath, ".jfif") ||
        strsrch (filepath, ".jfi") ||
        strsrch (filepath, ".JFIF") ||
        strsrch (filepath, ".JFI") ||
        strsrch (filepath, ".JPG"))
        return (1);

 /* If no JPEG file suffix, try opening the file */
    else {
        if ((diskfile = open (filepath, O_RDONLY)) < 0)
            return (0);
        else {
            nbr = read (diskfile, keyword, 2);
            close (diskfile);
            if (nbr < 4)
                return (0);
            else if (keyword[0] == (char) 0xFF &&
		     keyword[1] == (char) 0xD8)
                return (1);
            else
                return (0);
            }
        }
}


/* ISGIF -- Return 1 if GIF file, else 0 */
int
isgif (filepath)

char    *filepath;      /* Name of file to check */
{
    int diskfile;
    char keyword[16];
    int nbr;

    /* First check to see if this is an assignment */
    if (strchr (filepath, '='))
        return (0);

    /* Check file extension */
    if (strsrch (filepath, ".gif") ||
        strsrch (filepath, ".GIF"))
        return (1);

 /* If no GIF file suffix, try opening the file */
    else {
        if ((diskfile = open (filepath, O_RDONLY)) < 0)
            return (0);
        else {
            nbr = read (diskfile, keyword, 6);
            close (diskfile);
            if (nbr < 4)
                return (0);
            else if (!strncmp (keyword, "GIF", 3))
                return (1);
            else
                return (0);
            }
        }
}


static int maxtokens = MAXTOKENS; /* Set maximum number of tokens from wcscat.h*/

/* -- SETOKEN -- tokenize a string for easy decoding */

int
setoken (tokens, string, cwhite)

struct Tokens *tokens;	/* Token structure returned */
char	*string;	/* character string to tokenize */
char	*cwhite;	/* additional whitespace characters
			 * if = tab, disallow spaces and commas */
{
    char squote, dquote, jch, newline;
    char *iq, *stri, *wtype, *str0, *inew;
    int i,j,naddw, ltok;

    newline = (char) 10;
    squote = (char) 39;
    dquote = (char) 34;
    if (string == NULL)
	return (0);

    /* Line is terminated by newline or NULL */
    inew = strchr (string, newline);
    if (inew != NULL)
	tokens->lline = inew - string - 1;
    else
	tokens->lline = strlen (string);

    /* Save current line in structure */
    tokens->line = string;

    /* Add extra whitespace characters */
    if (cwhite == NULL)
	naddw = 0;
    else
	naddw = strlen (cwhite);

    /* if character is tab, allow only tabs and nulls as separators */
    if (naddw > 0 && !strncmp (cwhite, "tab", 3)) {
	tokens->white[0] = (char) 9;	/* Tab */
	tokens->white[1] = (char) 0;	/* NULL (end of string) */
	tokens->nwhite = 2;
	}

    /* if character is bar, allow only bars and nulls as separators */
    else if (naddw > 0 && !strncmp (cwhite, "bar", 3)) {
	tokens->white[0] = '|';		/* Bar */
	tokens->white[1] = (char) 0;	/* NULL (end of string) */
	tokens->nwhite = 2;
	}

    /* otherwise, allow spaces, tabs, commas, nulls, and cwhite */
    else {
	tokens->nwhite = 4 + naddw;;
	tokens->white[0] = ' ';		/* Space */
	tokens->white[1] = (char) 9;	/* Tab */
	tokens->white[2] = ',';		/* Comma */
	tokens->white[3] = (char) 124;	/* Vertical bar */
	tokens->white[4] = (char) 0;	/* Null (end of string) */
	if (tokens->nwhite > 20)
	    tokens->nwhite = 20;
	if (naddw > 0) {
	    i = 0;
	    for (j = 4; j < tokens->nwhite; j++) {
		tokens->white[j] = cwhite[i];
		i++;
		}
	    }
	}
    tokens->white[tokens->nwhite] = (char) 0;

    tokens->ntok = 0;
    tokens->itok = 0;
    iq = string - 1;
    for (i = 0; i < maxtokens; i++) {
	tokens->tok1[i] = NULL;
	tokens->ltok[i] = 0;
	}

    /* Process string one character at a time */
    stri = string;
    str0 = string;
    while (stri < string+tokens->lline) {

	/* Keep stuff between quotes in one token */
	if (stri <= iq)
	    continue;
	jch = *stri;

	/* Handle quoted strings */
	if (jch == squote)
	    iq = strchr (stri+1, squote);
	else if (jch == dquote)
	    iq = strchr (stri+1, dquote);
	else
	    iq = stri;
	if (iq > stri) {
	    tokens->ntok = tokens->ntok + 1;
	    if (tokens->ntok > maxtokens) return (maxtokens);
	    tokens->tok1[tokens->ntok] = stri + 1;
	    tokens->ltok[tokens->ntok] = (iq - stri) - 1;
	    stri = iq + 1;
	    str0 = iq + 1;
	    continue;
	    }

	/* Search for unquoted tokens */
	wtype = strchr (tokens->white, jch);

	/* If this is one of the additional whitespace characters,
	 * pass as a separate token */
	if (wtype > tokens->white + 3) {

	    /* Terminate token before whitespace */
	    if (stri > str0) {
		tokens->ntok = tokens->ntok + 1;
		if (tokens->ntok > maxtokens) return (maxtokens);
		tokens->tok1[tokens->ntok] = str0;
		tokens->ltok[tokens->ntok] = stri - str0;
		}

	    /* Make whitespace character next token; start new one */
	    tokens->ntok = tokens->ntok + 1;
	    if (tokens->ntok > maxtokens) return (maxtokens);
	    tokens->tok1[tokens->ntok] = stri;
	    tokens->ltok[tokens->ntok] = 1;
	    stri++;
	    str0 = stri;
	    }

	/* Pass previous token if regular whitespace or NULL */
	else if (wtype != NULL || jch == (char) 0) {

	    /* Ignore leading whitespace */
	    if (stri == str0) {
		stri++;
		str0 = stri;
		}

	    /* terminate token before whitespace; start new one */
	    else {
		tokens->ntok = tokens->ntok + 1;
		if (tokens->ntok > maxtokens) return (maxtokens);
		tokens->tok1[tokens->ntok] = str0;
		tokens->ltok[tokens->ntok] = stri - str0;
		stri++;
		str0 = stri;
		}
	    }

	/* Keep going if not whitespace */
	else
	    stri++;
	}

    /* Add token terminated by end of line */
    if (str0 < stri) {
	tokens->ntok = tokens->ntok + 1;
	if (tokens->ntok > maxtokens)
	    return (maxtokens);
	tokens->tok1[tokens->ntok] = str0;
	ltok = stri - str0 + 1;
	tokens->ltok[tokens->ntok] = ltok;

	/* Deal with white space just before end of line */
	jch = str0[ltok-1];
	if (strchr (tokens->white, jch)) {
	    ltok = ltok - 1;
	    tokens->ltok[tokens->ntok] = ltok;
	    tokens->ntok = tokens->ntok + 1;
	    tokens->tok1[tokens->ntok] = str0 + ltok;
	    tokens->ltok[tokens->ntok] = 0;
	    }
	}

    tokens->itok = 0;

    return (tokens->ntok);
}


/* NEXTOKEN -- get next token from tokenized string */

int
nextoken (tokens, token, maxchars)
 
struct Tokens *tokens;	/* Token structure returned */
char	*token;		/* token (returned) */
int	maxchars;	/* Maximum length of token */
{
    int ltok;		/* length of token string (returned) */
    int it, i;
    int maxc = maxchars - 1;

    tokens->itok = tokens->itok + 1;
    it = tokens->itok;
    if (it > tokens->ntok)
	it = tokens->ntok;
    else if (it < 1)
	it = 1;
    ltok = tokens->ltok[it];
    if (ltok > maxc)
	ltok = maxc;
    strncpy (token, tokens->tok1[it], ltok);
    for (i = ltok; i < maxc; i++)
	token[i] = (char) 0;
    return (ltok);
}


/* GETOKEN -- get specified token from tokenized string */

int
getoken (tokens, itok, token, maxchars)

struct Tokens *tokens;	/* Token structure returned */
int	itok;		/* token sequence number of token
			 * if <0, get whole string after token -itok
			 * if =0, get whole string */
char	*token;		/* token (returned) */
int	maxchars;	/* Maximum length of token */
{
    int ltok;		/* length of token string (returned) */
    int it, i;
    int maxc = maxchars - 1;

    it = itok;
    if (it > 0 ) {
	if (it > tokens->ntok)
	    it = tokens->ntok;
	ltok = tokens->ltok[it];
	if (ltok > maxc)
	    ltok = maxc;
	strncpy (token, tokens->tok1[it], ltok);
	}
    else if (it < 0) {
	if (it < -tokens->ntok)
	    it  = -tokens->ntok;
	ltok = tokens->line + tokens->lline - tokens->tok1[-it];
	if (ltok > maxc)
	    ltok = maxc;
	strncpy (token, tokens->tok1[-it], ltok);
	}
    else {
	ltok = tokens->lline;
	if (ltok > maxc)
	    ltok = maxc;
	strncpy (token, tokens->tok1[1], ltok);
	}
    for (i = ltok; i < maxc; i++)
	token[i] = (char) 0;

    return (ltok);
}

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


/* AGETL -- Get one LF- or CR-terminated line from an ASCII string */

int
agetl (string, iline, line, lline)

char *string;	/* Character string containing <keyword>= <value> info */
int iline;	/* Sequential line to return with 0=first line */
char *line;	/* Line (returned) */
int lline;	/* Maximum length for line */
{
    char *line1, *cchar1, *llf, *lcr;
    char *cchar2, *lastchar;
    int ichar, jline, lstring;
    int ilf = 10;
    int icr = 13;
    char clf = (char) 10;
    char ccr = (char) 13;
    int ieos = 0;
    char ceos = (char) 0;

/* If first line is desired, simply start at beginning of string */
    line1 = string;

/* Otherwise, determine line termination and find start of desired line */
    if (iline > 0) {
	llf = strchr (string, ilf);
	lcr = strchr (string, icr);
	lstring = strlen (string);
	jline = 0;
	if (llf) {
	    while (llf && jline < iline) {
		line1 = llf + 1;
		if (*line1 == ccr)
		    line1 = line1 + 1;
		llf = strchr (line1, ilf);
		jline++;
		}
	    }
	else if (lcr) {
	    while (lcr && jline < iline) {
		line1 = lcr + 1;
		if (*line1 == clf)
		    line1 = line1 + 1;
		llf = strchr (line1, icr);
		jline++;
		}
	    }

/* Pad out returned line with zeroes */
	else {
	    lastchar = line + lline;
	    cchar2 = line + strlen (line);
	    while (cchar2 < lastchar) {
		*cchar2 = ceos;
		cchar2++;
		}
	    return (0);
	    }
	}

/* Copy line to output string */
    cchar1 = line1;
    cchar2 = line;
    lastchar = line + lline - 1;	/* Leave space for terminating 0 */
    while (*cchar1 != clf && *cchar1 != ccr &&
	   *cchar1 != ceos && cchar2 < lastchar) {
	*cchar2 = *cchar1;
	cchar1++;
	cchar2++;
	}

/* Pad out returned line with zeroes */
    lastchar = line + lline;
    do {
	*cchar2 = ceos;
	cchar2++;
	} while (cchar2 < lastchar);
    return (1);
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
    char kw[32];

    strcpy (kw,keyword);
    strcat (kw,"[1]");
    if (agets (string, kw, 31, 0, value)) {
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
    char kw[32];

    strcpy (kw,keyword);
    strcat (kw,"[1]");
    if (agets (string, kw, 31, 0, value)) {
	*dval = atof (value);
	return (1);
	}
    else
	return (0);
}


/* AGETW -- Get first word of ASCII string where keyword=value anywhere */
int
agetw (string, keyword, word, maxlength)

char	*string;	/* character string containing <keyword>= <value> */
char	*keyword;	/* character string containing the name of the keyword
			   the value of which is returned.  hget searches for a
                 	   line beginning with this string.  if "[n]" or ",n" is
			   present, the n'th token in the value is returned. */
char	*word;		/* First word of string value */
int	maxlength;	/* Maximum number of characters in word */
{
    char *value;
    char kw[32];

    strcpy (kw,keyword);
    strcat (kw,"[1]");
    if (agets (string, kw, maxlength, 0, word)) {
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
    char cend, *lineend;
    int ipar, i, lkey, fkey;
    int ntok, ltok;
    struct Tokens valtok;

    char ceos = (char) 0;
    char clf = (char) 10;
    char ccr = (char) 13;

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

/* Find length of variable name, eliminating token choice */
    strncpy (keyword,keyword0, sizeof(keyword)-1);
    brack1 = strsrch (keyword,lbracket);
    if (brack1 == keyword) {
	brack1 = NULL;
	}
    brack2 = NULL;
    if (brack1 == NULL)
	brack1 = strsrch (keyword,comma);
    else {
        brack2 = strsrch (brack1,rbracket);
        if (brack2 != NULL)
            *brack2 = '\0';
	}

    if (brack1 != NULL) {
	*brack1 = '\0';
	brack1++;
	}
    lkey = strlen (keyword);

/* If keyword has brackets, figure out which token to extract */
    if (brack1 != NULL) {
        ipar = atoi (brack1);
	}
    else {
	ipar = 1;
	}

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

/* If no value, return */
    if (pval == NULL) {
	return (0);
	}

/* Parse value */

/* Drop leading spaces */
    while (*pval == ' ') pval++;

/* Change end of line to EOS */
    cend = ceos;
    if ((lineend = strchr (pval, clf))) {
	cend = *lineend;
	*lineend = ceos;
	}
    else if ((lineend = strchr (pval, ccr))) {
	cend = *lineend;
	*lineend = ceos;
	}
    else if ((lineend = strchr (pval, ceos))) {
	cend = *lineend;
	}

/* Parse string */
    ntok = setoken (&valtok, pval, "");

/* Exit if requested token of value is beyond actual number */
    if (ipar > ntok) {
	return (0);
	}

/* Extract appropriate token */
    ltok = getoken (&valtok, ipar, value, lval);

/* Change blanks to underscores if requested */
    if (fillblank) {
	for (ival = pval; ival < value+ltok; ival++) {
	    if (*ival == ' ') {
		*ival = '_';
		}
	    }
	}

/* Fix input string */
    if (lineend) {
	*lineend = cend;
	}

/* Fix keyword */
    if (brack1 != NULL) {
	*brack1 = lbracket[0];
	}
    if (brack2 != NULL) {
	*brack2 = rbracket[0];
	}

    return (1);
}


/*    Polynomial least squares fitting program, almost identical to the
 *    one in Bevington, "Data Reduction and Error Analysis for the
 *    Physical Sciences," page 141.  The argument list was changed and
 *    the weighting removed.
 *      y = a(1) + a(2)*(x-x0) + a(3)*(x-x0)**2 + a(3)*(x-x0)**3 + . . .
 */

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

double
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
 *	Y = a(0) + a(1)*X + a(2)*X**2 + a(3)*X**3 + . . . */

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

/*
 * Jul 14 1999	New subroutines
 * Jul 15 1999	Add getfilebuff()
 * Oct 15 1999	Fix format eror in error message
 * Oct 21 1999	Fix declarations after lint
 * Dec  9 1999	Add next_token(); set pointer to next token in first_token
 *
 * Sep 25 2001	Add isfilelist(); move isfile() from catutil.c
 *
 * Jan  4 2002	Allow getfilebuff() to read from stdin
 * Jan  8 2002	Add sts2c() and stc2s() for space-replaced strings
 * Mar 22 2002	Clean up isfilelist()
 * Aug  1 2002	Return 1 if file is stdin in isfile()
 *
 * Feb  4 2003	Open catalog file rb instead of r (Martin Ploner, Bern)
 * Mar  5 2003	Add isimlistd() to check image lists with root directory
 * May 27 2003	Use file stat call in getfilesize() instead of opening file
 * Jul 17 2003	Add root directory argument to isfilelist()
 *
 * Sep 29 2004	Drop next_token() to avoid conflict with subroutine in catutil.c
 *
 * Sep 26 2005	In first_token, return NULL if token is only control character
 *
 * Feb 23 2006	Add istiff(), isjpeg(), isgif() to check TIFF, JPEG, GIF files
 * Jun 20 2006	Cast call to fgets() void
 *
 * Jan  5 2007	Change stc2s() and sts2c() to pass single character as pointer
 * Jan 11 2007	Move token access subroutines from catutil.c
 *
 * Aug 28 2014	Return length from  next_line(): 0=unsuccessful
 *
 * Aug 31 2021	Add range, aget*, and polynomial subroutines from catutil.c
 *
 * Jan 20 2022	Add agetw() to read arbitrarily-sized space-less string
 * Jan 20 2022	Separate subroutine list by topic at top of file
 * Feb  1 2022	Add putfilebuff() and agetl()
 * Feb  2 2022	Use token subroutines to parse value strings in agets()
 */
