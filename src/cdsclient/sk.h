/*++++++++++++++
 Copyright:    (C) 2008-2017 UDS/CNRS
 License:       GNU General Public License
.IDENTIFICATION skclient.h
.LANGUAGE       C
.AUTHOR         Francois Ochsenbein [CDS]
.ENVIRONMENT    
.KEYWORDS       
.VERSION  1.0   12-Nov-1992
.VERSION  2.0   10-May-1993: Client part only
.VERSION  2.1   02-Jul-1993: sk_error
.VERSION  3.9   05-Apr-2005: Cosmetic
.COMMENTS       Declarations of sk/Client routines
---------------*/

#ifndef sk_DEF
#define sk_DEF	0	/* To avoid recursive inclusions */

#ifndef _PARAMS
#ifdef __STDC__
#define _PARAMS(A)      A       /* ANSI */
#include <stdio.h>
#else
#define _PARAMS(A)      ()      /* Traditional */
#endif
#endif

extern int sk_open      _PARAMS((char *machine, char *service));
extern int sk_connect   _PARAMS((char *machine, char *service, 
			char *username, char *password));
extern int sk_obeyserver _PARAMS((int plug, 
			int (*digest)(char *, int), 
			int (*more)(char *, int)));
extern int sk_fromserver _PARAMS((int plug, int fput, int fget));

extern int sk_read     _PARAMS((int plug, char *buf, int len));
extern int sk_get      _PARAMS((int plug, char *buf, int len));
extern int sk_gets     _PARAMS((int plug, char *buf, int len));
extern int sk_getl     _PARAMS((int plug));
extern int sk_write    _PARAMS((int plug, char *buf, int len));
extern int sk_put      _PARAMS((int plug, char *buf));
extern int sk_puts     _PARAMS((int plug, char *buf));
extern int sk_putl     _PARAMS((int plug, int val));
extern int sk_close    _PARAMS((int plug));
extern int sk_iosave   _PARAMS((int plug, char *buf, int len));

extern int sk_setb     _PARAMS((int blocksize));
extern void *sk_setlog _PARAMS((FILE *newlog));
extern void *sk_iolog  _PARAMS((FILE *newlog));
extern char *sk_error  _PARAMS((void));

extern int sk_kill     _PARAMS((int plug, int sig));	/* INTERRUPT */
extern int sk_umatch   _PARAMS((char *string, char *template));	/* case-insen */
extern int sk_match    _PARAMS((char *string, char *template));
/* extern int sk_log   _PARAMS((int level, char *fmt, ...));	-- problems */
#endif /* sk_DEF */
