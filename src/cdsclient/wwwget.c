/*++++++++++++++
 Copyright:    (C) 2008-2017 UDS/CNRS
 License:       GNU General Public License
.IDENTIFICATION wwwget.c
.LANGUAGE       C
.AUTHOR         Francois Ochsenbein [CDS]
.ENVIRONMENT    HTTP Protocol
.KEYWORDS       
.VERSION  1.0   25-Feb-1997
.VERSION  1.1   03-Sep-1997: Can give directly a http:// ...
.VERSION  1.2   03-Sep-1998: Accept userid/pwd
.VERSION  1.3   16-Oct-1998
.VERSION  1.4   22-Jul-1999: Acceept POST
.VERSION  1.5   04-Nov-1999: DO NOT Keep-Alive
.VERSION  1.6   30-Dec-2002: Cookie (-c) 
.VERSION  1.7   06-Jan-2003: Host added always
.VERSION  1.8   05-May-2003: -F option (from)
.VERSION  1.9   07-Jul-2003: Option -p (prompt)
.VERSION  2.0   06-Aug-2003: -q option
.VERSION  2.1   29-Aug-2003: Default: write header to stderr
.VERSION  2.2   15-Dec-2003: Options -r -o
.VERSION  2.3   24-Jan-2004: Option -mxxx for Mozilla
.VERSION  2.4   01-Sep-2004: a couple of bugs found by Aymeric Sauvageon ; -i
				from Thomas Erben terben(at)astro.uni-bonn(de)
.VERSION  2.5   16-Feb-2005: Bug communicated by rcorlan@pcnet.ro
.VERSION  2.51  14-Apr-2005: Bug communicated by Armin Rest
.VERSION  2.52  24-May-2005: Lines starting by blank/tab = CONTINUATION
.VERSION  2.6   13-Aug-2005: Introduction of a time-out in socket read.
				(in option -q)
.VERSION  2.61  04-Mar-2006: Better edition in verbose mode
.VERSION  2.62  16-Jan-2007: 64-bit machine
.VERSION  2.7   10-Feb-2007: Option -redirect
.VERSION  2.8   13-Jun-2007: strndup exists in __GNUC__ 
.VERSION  2.9   19-Dec-2007: -redirect bug.
.VERSION  2.91  04-Mar-2008: (bug)
.VERSION  3.0   06-Mar-2008: safe_strndup, from Juan Cabanela (for MacOS)
.VERSION  3.01  13-May-2009: HEAD method, don't try to continue
.VERSION  3.02  23-Aug-2009: HEAD method, result to stdout
.VERSION  3.03  28-Feb-2010: multiple queries forbidden if POST method
			(syndrome: http://aegis.ucolick.org returns a
			  Content-Length: 19264 in HEAD method ! )
.VERSION  3.04  07-Jun-2010: mystrndup: allocate 2 chars more
.VERSION  3.05  01-Sep-2010: By default, header not issued
.VERSION  3.06  16-Mar-2011: 
.VERSION  3.07  25-Mar-2011: bug if // missing in hostname
.VERSION  3.08  09-Jun-2011: Don't ignore result fo 'write'
.VERSION  3.09  02-Nov-2011: Faster if length specified in header.
.VERSION  3.10  13-Nov-2011: Pb with HEAD method
.VERSION  3.11  19-Jan-2012: sk_open can return a plug#0 !!!
.VERSION  3.12  06-Jun-2012: Pb with -m option
.VERSION  3.13  16-Aug-2012: Pb with content length
.VERSION  3.14  05-Dec-2012: Read text to send from stdin if not in arguments
.VERSION  3.15  25-Jun-2014: -A option
.COMMENTS       This stand-alone program can send HTTP requests, and
		displays the result on the standard output.
	To compile:  cc wwwget.c -o wwwget  
	   on Sun-Solaris, add the socket libraries, i.e.
		     cc wwwget.c -o wwwget -lsocket -lnsl
	To run it: wwwget -help   ---> displays help
		   wwwget -strip [URL] , e.g.
		   wwwget -strip http://vizier.u-strasbg.fr/cgi-bin/Echo

The HTTP Statuses are:
   10.1  Informational 1xx ...........................................57
   10.1.1   100 Continue .............................................58
   10.1.2   101 Switching Protocols ..................................58

   10.2  Successful 2xx ..............................................58
   10.2.1   200 OK ...................................................58
   10.2.2   201 Created ..............................................59
   10.2.3   202 Accepted .............................................59
   10.2.4   203 Non-Authoritative Information ........................59
   10.2.5   204 No Content ...........................................60
   10.2.6   205 Reset Content ........................................60
   10.2.7   206 Partial Content ......................................60

   10.3  Redirection 3xx .............................................61
   10.3.1   300 Multiple Choices .....................................61
   10.3.2   301 Moved Permanently ....................................62
   10.3.3   302 Found ................................................62
   10.3.4   303 See Other ............................................63
   10.3.5   304 Not Modified .........................................63
   10.3.6   305 Use Proxy ............................................64
   10.3.7   306 (Unused) .............................................64
   10.3.8   307 Temporary Redirect ...................................65

   10.4  Client Error 4xx ............................................65
   10.4.1    400 Bad Request .........................................65
   10.4.2    401 Unauthorized ........................................66
   10.4.3    402 Payment Required ....................................66
   10.4.4    403 Forbidden ...........................................66
   10.4.5    404 Not Found ...........................................66
   10.4.6    405 Method Not Allowed ..................................66
   10.4.7    406 Not Acceptable ......................................67
   10.4.8    407 Proxy Authentication Required .......................67
   10.4.9    408 Request Timeout .....................................67
   10.4.10   409 Conflict ............................................67
   10.4.11   410 Gone ................................................68
   10.4.12   411 Length Required .....................................68
   10.4.13   412 Precondition Failed .................................68
   10.4.14   413 Request Entity Too Large ............................69
   10.4.15   414 Request-URI Too Long ................................69
   10.4.16   415 Unsupported Media Type ..............................69
   10.4.17   416 Requested Range Not Satisfiable .....................69
   10.4.18   417 Expectation Failed ..................................70

   10.5  Server Error 5xx ............................................70
   10.5.1   500 Internal Server Error ................................70
   10.5.2   501 Not Implemented ......................................70
   10.5.3   502 Bad Gateway ..........................................70
   10.5.4   503 Service Unavailable ..................................70
   10.5.5   504 Gateway Timeout ......................................71
   10.5.6   505 HTTP Version Not Supported ...........................71
---------------*/

#define VERSION "3.14  (2014-06-25)"

#define NODELAY 1
#define isquote( c ) ( ( c ) == '"' ) || ( ( c ) == '\'' ) || ( ( c ) == '`' )

#ifndef MAX_REDIRECT
#define MAX_REDIRECT 8
#endif

#ifndef int4
#define int4 int
#endif
#ifndef int8
#define int8 long long
#endif

#ifdef __GNUC__ /* Added V2.8 */
#define _GNU_SOURCE
#endif

#include <stdio.h>
#include <ctype.h>
#include <errno.h>
#include <unistd.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef __MSDOS__ /* For tests */
#else
#include <netdb.h>
#ifdef VMS /* All definition files in single directory */
#include <types.h>
#include <socket.h>
#include <in.h>
#else /* Assume standard Unix */
#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <netinet/in.h>
#include <netinet/tcp.h> /* Internet sockets definitions	*/
#include <arpa/inet.h>
#include <sys/select.h>
#include <fcntl.h>
#endif
#endif

static char usage[]= "\
Usage: wwwget [-v] [-s] [-m...] [-abs] [-post|-head|-get|-redirect] [-q]\n\
       [-nostrip] [-c cookie] [-Ddomain] [-Uuser] [-Ppasswd] [-Ffrom] \n\
       [-i file] [-o file] [-p# prompt] [-r range] [-to secs]\n\
       [//]host[:port][/doc] [args]\n\
         -v: Verbose option\n\
         -s: silent (default is to display headers on stderr)\n\
      -m...: emulate Mozilla (add User-Agent etc) defaut is 3.0\n\
       -abs: Convert relative anchors into absolute ones\n\
         -q: a non-encoded Query is included as args or in Input file (*)\n\
      -post: Use the POST method\n\
      -head: Use the HEAD method (Redirect directive is NOT executed)\n\
       -get: Use the GET method (default)\n\
  -redirect: Generate a Redirect header (Status: 302 Moved Temporarily)\n\
   -nostrip: keep the header (with HTTP code, Content-Type, etc) in output\n\
  -c cookie: send the specified cookie\n\
    -Aagent: specifies the user-agent (as User-agent: wwwget/agent)\n\
             (can also be specified with the AGENT environment variable)\n\
   -Ddomain: domain to specify (in WWW-Authenticate)\n\
             (Domain is specified in WWW-Authenticate answer from server)\n\
     -Uuser: Userid to specify (in Authorization)\n\
     -Ppswd: Passowrd to specify for Authentification\n\
     -Ffrom: Email address of sender\n\
    -i file: specifies the Input file (defaut stdin)\n\
    -o file: specifies the Output file (append to existing file)\n\
      -p# p: stop (exit) when a specific prompt is found at #th time\n\
   -r range: Specifes a range of Bytes\n\
   -to secs: define a reading time-out between reception of 2 packets [1200s]\n\
       host: Internet name or number, default port is 80\n\
       args: other arguments, used in the -q option\n\
  When document(s) are not specified on the command lines, they are assuned\n\
  to be specified in the standard input.\n\
  The returned status is 0 (OK), 1 (error contacting host), 2 (non-OK reply)\n\
(*) A Non-encoded query consists in a set of parameters saved as one\n\
    parameter per line; each line is encoded, and preceded by a & to generate\n\
    the actual query.\n\
";

static char *addr[]= {
    "HREF=", "SRC=", (char *)0};

static char *url[7];       /* Components of an URL	*/
static char hostname[256]; /* //node.domain	*/
#define URL_PROTOCOL 0
#define URL_NODE 1   /* e.g. cdsarc */
#define URL_DOMAIN 2 /* e.g. .u-strasbg.fr */
#define URL_PORT 3   /* e.g. :80 */
#define URL_PATH 4   /* Terminates by a / */
#define URL_FILE 5   /* May be empty      */
#define URL_QUERY 6  /* Starts by ?       */

static char ostrip= 0; /* No Header to stderr	*/
static char osilent;   /* -s(ilent) option	*/
static char ov;
static char oabs;
static char *omoz;   /* Emulate Mozilla */
static char oq;      /* -query Option    */
static char *aD;     /* Domain */
static char *aU;     /* UserID */
static char *aA;     /* UserAgent */
static char *aP;     /* Passwd */
static char *aR;     /* Range  */
static char *aF;     /* From:  */
static char *cookie; /* -c opt */
static char *prompt; /* Where to stop (not just line starting by) */
static int promptno;
static FILE *ofile; /* Output File */
static FILE *ifile; /*  Input File */
static int ofno= 1; /* Output file */
static int redirect_count= 0;
static int redirect_max= MAX_REDIRECT;
static int reading_timeout= 1200;

/* Socket Read/Write */
static int plug;
static char skbuf[4097];
static char *skp, *ske;
static int8 skbytes, content_length; /* To go to 64 bytes */
#define CONTENT_LENGTH_MAX ( 1LL << 60 )
#define GetChar() skp < ske ? *( skp++ ) : get_char()
#define PeekChar() skp < ske ? *skp : peek_char()
time_t starting_time, printing_time;

static char cv64[65]= /* To convert to 64-encoding */
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
static char mozilla_def[]= "\
User-Agent: Mozilla/5.0 (X11; U; Linux x86 generic)\r\n\
Accept: image/gif, image/x-xbitmap, image/jpeg, image/pjpeg, */*\r\n\
";
static char keep_alive[]= "Connection: Keep-Alive\r\n";

static char fmt_redirect[]= "\
Status: 302 Moved Temporarily\r\n\
Location: %s\r\n\
Connection: close\r\n\
Content-Type: text/html\r\n\
\r\n\
<HTML><HEAD><TITLE>302 Moved Temporarily</TITLE></HEAD><BODY>\n\
<H1>Moved Temporarily</H1>\n\
The document requested is available from <A HREF='%s'>%s</A>\n\
</BODY></HTML>\r\n\
";

/*==================================================================
		BSD Utilities
 *==================================================================*/
#ifdef __MSDOS__ /* For tests */
static int gethostname( buf, len ) char *buf;
int len;
{
 strcpy( buf, "PC-DOS" );
 return ( 0 );
}
char *getdomain() {
 return ( "" );
}
#else                    /* == Standard Unix */
#include <sys/utsname.h> /* for gethostname	*/
char *getdomain()
/*++++++++++++++++
.PURPOSE  Get name of domain (e.g. u-strasbg.fr)
.RETURNS  The domain (no starting dot)
.REMARKS  From /etc/resolv.conf
-----------------*/
{
 static char *domain= (char *)0;
 char buf[80], *p;
 FILE *resolv;

 if ( domain )
  return ( domain );

 if ( !( resolv= fopen( "/etc/resolv.conf", "r" ) ) )
  return ( "" );
 while ( fgets( buf, sizeof( buf ), resolv ) ) {
  if ( strncmp( buf, "domain", 6 ) && strncmp( buf, "search", 6 ) )
   continue;
  p= buf + 6;
  while ( isspace( *p ) )
   p++;
  domain= strdup( p );
  for ( p= domain; isgraph( *p ); p++ )
   ;
  *p= 0;
  break;
 }
 fclose( resolv );
 if ( !domain )
  domain= ""; /* Added V2.51, from Armin Rest */
 return ( domain );
}

static int mygethostname( char *host, int len )
/*++++++++++++++++
.PURPOSE  Get name of host
.RETURNS  0 (OK) / 1 (truncated) /-1(error)
.REMARKS  BSD compatibility routine. Add the domain name if required.
-----------------*/
/* char *host;	-- OUT: Name of host 	*/
/* int len;		-- IN: Size of name	*/
{
 struct utsname name;
 int status, i;
 char *domain, *p;
 status= uname( &name );
 if ( status < 0 )
  return ( status );

 for ( p= name.nodename; *p && ( *p != '.' ); p++ )
  ;
 if ( *p )
  domain= "";
 else
  domain= getdomain();

 /* Copy the result */
 status= 0;
 i= strlen( name.nodename );
 strncpy( host, name.nodename, len );
 if ( i >= len )
  host[i= len - 1]= 0, status= 1;

 /* Append the domain */
 if ( domain && *domain ) { /* V2.5 */
  p= host + i, len-= i;
  if ( len > 0 )
   *( p++ )= '.', len--;
  strncpy( p, domain, len );
  i= strlen( p );
  if ( i >= len )
   p[i= len - 1]= 0, status= 1;
 }
 return ( status );
}
#endif

/*============================================================================
 *		Internal routines
 *============================================================================*/

static int strloc( char *text, int c )
/*++++++++++++++++
.PURPOSE  Locate specified character
.RETURNS  Index of located char
-----------------*/
{
 char *s;
 for ( s= text; *s; s++ )
  if ( *s == c )
   break;
 return ( s - text );
}

/* #ifndef __GNUC__	-- V2.8, removed V3.0 */
static char *mystrndup( char *text, int n )
/*++++++++++++++++
.PURPOSE  Keep a copy of a string
.RETURNS  Newly allocated string
-----------------*/
/* char *text;     -- IN: String to interpret */
/* int  n;         -- IN: Length to duplicate */
{
 char *s;
 if ( n < 0 )
  n= strlen( text );
 s= malloc( n + 3 ); /* V3.04: room for // */
 memcpy( s, text, n );
 s[n]= 0;
 return ( s );
}
/* #endif		-- V2.8, removed V3.0 */

static char *enc64( char *str )
/*++++++++++++++++
.PURPOSE  Encode str in 64-mode 
.RETURNS  Encoded value -- limited to 76 bytes !
.REMARKS  When str has not a length which is a multiple of 3, 
	  == added.
	  But no newline added.
-----------------*/
/* str: IN: String to write out */
{
 static char enc[80];
 char *b4, *p, *e;
 int c, c3;
 p= str;
 b4= enc;
 e= enc + sizeof( enc ) - 4;
 while ( *p ) {
  if ( b4 >= e ) {
   fprintf( stderr, "#***String to encode too long: '%s'\n", str );
   break;
  }
  c= *( p++ ) & 0xff;
  c3= c << 16;
  b4[2]= b4[3]= '=';
  if ( ( c= *( p++ ) & 0xff ) ) {
   c3|= ( c << 8 );
   b4[2]= 0;
   if ( ( c= *( p++ ) & 0xff ) ) {
    c3|= c;
    b4[3]= 0;
   }
  }
  if ( !b4[3] )
   b4[3]= cv64[c3 & 63];
  c3>>= 6;
  if ( !b4[2] )
   b4[2]= cv64[c3 & 63];
  c3>>= 6;
  b4[1]= cv64[c3 & 63];
  c3>>= 6;
  b4[0]= cv64[c3 & 63];
  b4+= 4;
 }
 b4[0]= 0;
 return ( enc );
}

#if 0 /* Not used... */
static int put64(str, opt)
/*++++++++++++++++
.PURPOSE  Write (to stdout) the string in 64-base
.RETURNS  Number of bytes written out.
.REMARKS  When str has not a length which is a multiple of 3, 
	  == added.
	  But no newline added.
-----------------*/
  char *str; 	/* IN: String to write out */
  int opt;	/* IN: Unsued option */
{
  static char b4[4] ;
  int c, c3, nb ; char *p ;
    nb = 0 ;
    p = str ;
    while (*p) {
	c = *(p++)&0xff ;
	c3 = c<<16 ; b4[2] = b4[3] = '=' ;
	if ((c = *(p++)&0xff)) {
	    c3 |= (c<<8) ;  b4[2]=0 ;
	    if ((c = *(p++)&0xff)) {
		c3 |=  c ;  b4[3]=0 ;
	    }
	}
	if (!b4[3]) b4[3] = cv64[c3&63] ; c3 >>= 6 ;
	if (!b4[2]) b4[2] = cv64[c3&63] ; c3 >>= 6 ;
	b4[1] = cv64[c3&63] ; c3 >>= 6 ;
	b4[0] = cv64[c3&63] ; nb += 4;
	putchar(b4[0]) ; putchar(b4[1]) ;
	putchar(b4[2]) ; putchar(b4[3]) ;
	if ((nb%76)==0) putchar('\n') ;
    }
    return(nb) ;
}
#endif

static int check_prompt( char *text )
/*++++++++++++++++
.PURPOSE  Verifies the presence of a prompt.
.RETURNS  Number of bytes until end-of-prompt
.REMARKS  promptno is decreased when prompt found
-----------------*/
{
 static int found;
 char *p;
 p= strstr( text, prompt );
 while ( p ) {
  if ( ov )
   fprintf( stderr, "#...Prompt found for %dth time: %s\n",
            ++found, prompt );
  p+= strlen( prompt );
  if ( --promptno <= 0 ) {
   return ( ( p - text ) );
  }
  p= strstr( p, prompt );
 }
 return ( strlen( text ) );
}

/*===========================================================================*
		Get a full line of input
 *===========================================================================*/
static char *get1line( FILE *file )
/*++++++++++++++++
.PURPOSE  Get a full line.
.RETURNS  The line, \n\r stripped out / NULL for end
.REMARKS  Allocated only once
-----------------*/
{
 static char buf[BUFSIZ];
 static char *line;
 static int abytes, ubytes;
 int i;
 ubytes= 0;
 if ( !fgets( buf, sizeof( buf ), file ) ) /* End of File	*/
  return ( (char *)0 );
 while ( 1 ) {
  i= strloc( buf, '\n' );
  if ( ubytes + i >= abytes ) { /* Must alloc	*/
   abytes= ubytes + i + 1;
   abytes|= 1023; /* K-multiple	*/
   abytes++;
   if ( line )
    line= realloc( line, abytes );
   else
    line= malloc( abytes );
  }
  strcpy( line + ubytes, buf );
  ubytes+= i;
  if ( buf[i] )
   break; /* \n is there	*/
  if ( !fgets( buf, sizeof( buf ), file ) )
   break;
 }
 /* Remove the trailing \r\n	*/
 while ( ( ubytes > 0 ) && ( iscntrl( line[ubytes - 1] ) ) )
  ubytes--;
 line[ubytes]= 0;
 return ( line );
}

/*===========================================================================*
		Append a string, URL-encode
 *===========================================================================*/
static char *Baline;
static int Bbline, Bcline;

static char *append( char *text, int encode )
/*++++++++++++++++
.PURPOSE  Append a text, eventuelly URL-encoded
.RETURNS  The (expanded) text
.REMARKS  Use Baline Bbline (allocated bytes) Bcline (used bytes)
-----------------*/
{
 static char *charok= "=-_.,/:@";
 char *t, *p;
 int i;
 i= strlen( text );
 if ( encode )
  i*= 3;
 i+= 1 + Bbline;

 if ( i >= Bbline ) {       /* Must expand  */
  Bbline= ( i | 1023 ) + 1; /* Multiple of K*/
  if ( Baline )
   Baline= realloc( Baline, Bbline );
  else
   Baline= malloc( Bbline );
 }
 p= Baline + Bcline;
 if ( encode )
  for ( t= text; *t; t++ ) {
   if ( isalnum( *t ) ) {
    *( p++ )= *t;
    continue;
   }
   if ( strchr( charok, *t ) ) {
    *( p++ )= *t;
    continue;
   }
   *( p++ )= '%';
   sprintf( p, "%02x", ( *t ) & 255 );
   p+= strlen( p );
  }
 else {
  strcpy( p, text );
  p+= strlen( p );
 }
 *p= 0;
 Bcline= p - Baline;
 return ( Baline );
}

/*===========================================================================*
		Connection to Server
 *===========================================================================*/

int sk_open( char *machine, char *service )
/*++++++++++++++++
.PURPOSE  Start a client connecting to a machine / Service
.RETURNS  File number; -1 when can't connect, -2 when connection refused
.REMARKS  Machine and Service can be symbolic (letters) or numeric
	Non-numeric services are to be found in /etc/services.
-----------------*/
{
 int plug;                      /* socket to "plug" into the socket */
 struct sockaddr_in socketname; /* mode, addr, and port for socket */
 struct hostent *remote_host;   /* internet numbers, names   */
 struct servent *ps;            /* Returned by getservbyname */
 int stat;

 /* make an internet-transmitted, file-i/o-style, protocol-whatever plug */
 if ( ( plug= socket( AF_INET, SOCK_STREAM, 0 ) ) < 0 ) {
  perror( "#***can't start socket" );
  return ( -1 );
 }

#ifdef NODELAY
 stat= TCP_NODELAY;
 if ( setsockopt( plug, IPPROTO_TCP, TCP_NODELAY,
                  (char *)&stat, sizeof( stat ) ) < 0 ) {
  perror( "#***Can't setsockopt(TCP_NODELAY)" );
  return ( -1 );
 }
#endif

 /* Fill in the socket structure with Host and Service */
 socketname.sin_family= AF_INET;
 if ( isalpha( *machine ) ) {
  if ( !( remote_host= gethostbyname( machine ) ) ) {
   if ( !osilent )
    fprintf( stderr, "#***Unknown host: %s\n", machine );
   /*perror(machine);*/
   return ( -1 );
  }
  (void)memcpy(
      (char *)&socketname.sin_addr,
      (char *)remote_host->h_addr,
      remote_host->h_length );
 } else
  socketname.sin_addr.s_addr= inet_addr( machine );
 if ( isalpha( *service ) ) {
  ps= getservbyname( service, (char *)0 );
  if ( !ps ) {
   perror( service );
   return ( -1 );
  }
  socketname.sin_port= ps->s_port;
 } else
  socketname.sin_port= htons( atoi( service ) );

 /* plug into the listening socket */
 if ( connect( plug, (struct sockaddr *)&socketname,
               sizeof( socketname ) ) < 0 ) {
  perror( machine );
  return ( -1 );
 }

 return ( plug );
}

int skread()
/*++++++++++++++++
.PURPOSE  Read on opened connection (plug)
.RETURNS  Number of bytes read / 0 (end) / -1 (error)
-----------------*/
{
 int m0, n;
 time_t now;
 int4 sec;
 double rate;
 static int4 counter= 0;

 if ( reading_timeout )
  alarm( reading_timeout );
 n= read( plug, skbuf, sizeof( skbuf ) - 1 );
 alarm( 0 );
 if ( n >= 0 )
  skbuf[n]= 0;

 /* Seems to be end... Try however ! */
 for ( m0= 0; ( n < 0 ) && ( m0 < 25 ); m0++ ) {
  if ( skbytes >= content_length )
   break;
  sec= reading_timeout ? reading_timeout / 5 : 9999;
  if ( sec > 15 )
   sec= 15;
  else if ( sec == 0 )
   sec= 1;
  sleep( sec );
  if ( ov )
   fprintf( stderr,
            " (stalled %2d)\b\b\b\b\b\b\b\b\b\b\b\b\b", m0 );
  if ( reading_timeout )
   alarm( reading_timeout );
  n= read( plug, skbuf, sizeof( skbuf ) );
  alarm( 0 );
 }
 if ( n < 0 ) {
  fprintf( stderr, "#***" );
  perror( hostname );
 }
 if ( n > 0 ) {
  skbytes+= n;
  if ( ov ) {
   now= time( 0 );
   sec= ( now - starting_time );
   if ( counter == 0 )
    fputc( '\n', stderr );
   counter++;
   /* fprintf(stderr, "skbytes=%lld\n", skbytes); */
   if ( sec > 0 )
    rate= skbytes / sec / 1024.;
   else
    rate= skbytes;
   /* Verbose mode: print every 5sec */
   if ( ( now - printing_time ) >= 5 ) {
    fprintf( stderr, "\r %10lld %7.1fKb/s", skbytes, rate );
    printing_time= now;
   }
   fflush( stderr );
  }
  skp= skbuf;
  ske= skp + n;
 }
 return ( n );
}

int peek_char()
/*++++++++++++++++
.PURPOSE  Tell what's the next char
.RETURNS  The Char
-----------------*/
{
 if ( skp >= ske )
  skread();
 if ( skp >= ske )
  return ( EOF );
 return ( *skp );
}

int get_char()
/*++++++++++++++++
.PURPOSE  Tell what's the next char
.RETURNS  The Char
-----------------*/
{
 int c;
 if ( skp >= ske )
  skread();
 if ( skp >= ske )
  return ( EOF );
 c= *( skp++ );
 return ( c );
}

/*==================================================================
		Convert relative Anchors to Absolute Ones
 *==================================================================*/

static int cut_url( char *text, int *len7, int has_host )
/*++++++++++++++++
.PURPOSE  Decompose the URL into parts
.RETURNS  Number of components (normally 7) / 0 when not applicable
		(nor http neither ftp protocol, or internal anchor)
-----------------*/
/* char *text;	-- IN: String to interpret */
/* int  *len7;	-- OUT: 7 numbers with lengths of components */
/* int has_host;	-- IN: Option 1 when test MUST include host  */
{
 int len, i;
 char *p, *e;

 if ( *text == '#' ) /* Internal Anchor */
  return ( 0 );

 len= strloc( text, '?' );
 p= text;
 e= p + len;

 i= 0;
 /* Protocol: only alphabetic */
 while ( isalpha( *p ) )
  p++;
 if ( *p == ':' ) {
  len7[i]= ( ++p - text );
  if ( ( tolower( text[0] ) != 'h' ) && ( tolower( text[0] ) != 'f' ) )
   return ( 0 ); /* Can't be http, nor ftp ...	*/
  text= p;
 } else { /* No protocol... */
  len7[i]= 0;
  p= text;
 }

 len7[++i]= 0; /* Nodename */
 /* Hostname: starts by // */
 if ( ( p[0] == '/' ) && ( p[1] == '/' ) )
  has_host= 1, p+= 2;
 if ( has_host ) {
  while ( isgraph( *p ) && ( p < e ) && ( *p != '.' ) && ( *p != '/' ) && ( *p != ':' ) )
   p++;
  len7[i]= ( p - text );
  text= p;
  while ( isgraph( *p ) && ( p < e ) && ( *p != '/' ) && ( *p != ':' ) )
   p++;
  len7[++i]= ( p - text );
  text= p;
  if ( *p == ':' ) { /* Port number */
   for ( ++p; isdigit( *p ); p++ )
    ;
   len7[++i]= ( p - text );
   text= p;
  } else
   len7[++i]= 0;
 } else {
  len7[++i]= 0; /* Domain.. */
  len7[++i]= 0; /* Port ... */
 }

 /* What remains is PATH/FILE */
 for ( p= e - 1; ( p >= text ) && ( *p != '/' ); p-- )
  ;
 if ( p < text )
  p= text;
 if ( *p == '/' )
  ++p;
 len7[++i]= ( p - text ); /* PATH/ */
 len7[++i]= ( e - p );    /* FILE  */
 len7[++i]= strlen( e );  /* QUERY */

 return ( ++i );
}

static void set_url( char *text, int has_host )
/*++++++++++++++++
.PURPOSE  Set the URL parts
.RETURNS  ---
.REMARKS  Static url[] set up.
-----------------*/
/* char *text;	-- IN: String to interpret */
/* int has_host;	-- IN: 1 when text must represent a host */
{
 static char *protodef= "http:";
 static char *empty= "";
 int i, len7[7];
 char *p;

 /* Set URL components */
 if ( !hostname[0] ) {
  hostname[0]= hostname[1]= '/';
  mygethostname( hostname + 2, sizeof( hostname ) - 2 );
 }
 /* Free allocated parts */
 if ( ( url[0] ) && ( url[0] != protodef ) )
  free( url[0] );
 for ( i= 1; i < 7; i++ ) {
  if ( ( url[i] ) && ( url[i] != empty ) )
   free( url[i] );
  url[i]= empty;
 }

 p= text;
 if ( cut_url( p, len7, has_host ) == 0 ) {
  fprintf( stderr, "#+++URL is neither HTTP nor FTP: %s\n%s\n",
           text, usage );
  url[0]= url[1]= url[2]= url[3]= url[4]= empty;
  return;
 }
 if ( !len7[0] )
  url[0]= protodef;
 else
  url[0]= mystrndup( p, len7[0] ), p+= len7[0];
#if 0
    if (!len7[1]) url[1] = mystrndup(hostname, strloc(hostname, '.')) ;
    else url[1] = mystrndup(p, len7[1]+2), url[1][len7[1]] = 0, p += len7[1] ;
    if (!len7[2]) url[2] = mystrndup(hostname+strloc(hostname, '.'), -1) ;
    else url[2] = mystrndup(p, len7[2]), p += len7[2] ;
#endif

 /* Add the other components */
 for ( i= 1; i < 7; i++ ) {
  if ( len7[i] == 0 )
   continue;
  url[i]= mystrndup( p, len7[i] );
  if ( ov )
   printf( "#...set_url: i=%d: strndup(%s,%d)\n",
           i, url[i], len7[i] );
  p+= len7[i];
 }
 if ( url[URL_PATH] == empty )
  url[URL_PATH]= strdup( "/" );

 /* Save the current definitions of node + domain in hostname 
       Be sure also that the node contains the leading //
    */
 if ( has_host ) {
  if ( url[1] == empty ) { /* Local node (fixed V3.06) */
   url[1]= strdup( hostname );
   if ( ov )
    printf( "#...set_url: Mod#1 => url[1]=%s\n", url[1] );
  } else if ( ( url[1][0] != '/' ) && ( url[1][1] != '/' ) ) {
   /* Node given, the // is missing... */
   i= strlen( url[1] ) + 1;
   memmove( url[1] + 2, url[1], i );
   url[1][0]= url[1][1]= '/';
   if ( ov )
    printf( "#...set_url: Mod#1 => url[1]=%s\n", url[1] );
  }
  strncpy( hostname, url[1] + 2, sizeof( hostname ) );
  strcat( hostname, url[2] ); /* V3.06 */
 }
}

static char *paste_url( char **url, int nelem )
/*++++++++++++++++
.PURPOSE  Merge the nelem 
.RETURNS  ---
.REMARKS  Static url[] set up.
-----------------*/
{
 char *a, *p;
 int i, len;

 for ( len= i= 0; i < nelem; i++ ) {
  if ( url[i] )
   len+= strlen( url[i] );
 }
 a= p= malloc( len + 1 );
 for ( i= 0; i < nelem; i++ ) {
  if ( url[i] )
   strcpy( p, url[i] );
  p+= strlen( p );
 }
 return ( a );
}

static int match_string( int sep, char *buf, int size )
/*++++++++++++++++
.PURPOSE  Match a complete string
.RETURNS  Last byte read (EOF or " or \n)
.REMARKS  Quote may be doubled to indicate a quote.
-----------------*/
/* int  sep;  -- IN: Char just read (' or ") */
/* char *buf;	-- OUT: string stored 	*/
/* int  size;	-- IN: Size of buf	*/
{
 int c= 0;
 char *b, *e;
 for ( b= buf, e= buf + size - 1; b < e; b++ ) {
  c= GetChar();
  if ( c == sep ) { /* Another Quote */
   c= PeekChar();
   if ( c != sep ) {
    c= sep;
    break;
   }
   *b= sep;
   c= GetChar();
   continue;
  }
  if ( c == '\n' )
   break;
  if ( c == EOF )
   break;
  *b= c;
 }
 *b= 0;
 return ( c );
}

static int match_tag()
/*++++++++++++++++
.PURPOSE  Match a complete tag, and replace the URL.
.RETURNS  Character found ('>' or EOF)
.REMARKS  '<' just read.
-----------------*/
{
 int c, i, n, change, len7[7];
 char name[12];
 char string[1025], *s;
 char **a;

 c= GetChar();
 if ( ( c == '!' ) || ( c == '%' ) || ( c == '&' ) || ( c == '/' ) )
  change= -1; /* Can't have an URL */
 else
  change= 0;

 while ( ( c != '>' ) && ( c != EOF ) ) {
  while ( isspace( c ) ) {
   putchar( c );
   c= GetChar();
   continue;
  }
  n= change; /* Number of chars loaded for HREF= */
  while ( isgraph( c ) ) {
   if ( c == '>' )
    break;
   if ( isquote( c ) ) {
    putchar( c );
    c= match_string( c, string, sizeof( string ) );
    printf( "%s", string );
    if ( c != EOF )
     putchar( c ), c= GetChar();
    n= -1;
    continue;
   }
   putchar( c );
   if ( ( n >= 0 ) && ( n < sizeof( name ) - 1 ) )
    name[n++]= toupper( c );
   else {
    c= GetChar();
    n= -1;
    continue;
   }
   if ( c != '=' ) {
    c= GetChar();
    continue;
   }

   /* A word terminated by = : is a HTML parameter */
   name[n]= 0;
   for ( a= addr; *a && strcmp( *a, name ); a++ )
    ;
   if ( !*a ) {
    c= GetChar();
    n= -1;
    continue;
   }

   /*** Here start replacement of Anchor ***/
   c= GetChar();
   if ( isquote( c ) ) {
    putchar( c );
    c= match_string( c, string, sizeof( string ) );
   } else { /* Get Word */
    for ( i= 0; ( i < sizeof( string ) - 1 ) && isgraph( c ); i++ ) {
     if ( c == '>' )
      break;
     string[i]= c;
     c= GetChar();
    }
    string[i]= 0;
   }
   /*** Translate string into a complete Anchor */
   if ( cut_url( string, len7, 0 ) ) {
    for ( i= 0, s= string; i < 4; s+= len7[i++] ) {
     if ( len7[i] == 0 )
      printf( "%s", url[i] );
     else
      fwrite( s, 1, len7[i], stdout );
    }
    if ( *s != '/' )
     printf( "%s", url[4] ); /* PATH */
    printf( "%s", s );
   } else
    printf( "%s", string );

   if ( isquote( c ) ) {
    putchar( c );
    c= GetChar();
   }
   n= -1;
  }
 }
 return ( c );
}

static void exec_abs( FILE *f )
/*++++++++++++++++
.PURPOSE  Execute translation relative --> absolute anchors on open file
.RETURNS  ---
-----------------*/
{
 int c;
 c= 0;
 while ( c != EOF ) {
  if ( c )
   fputc( c, f );
  if ( c == '<' )
   c= match_tag();
  else
   c= GetChar();
 }
}

/*===========================================================================*
		MAIN Procedure
 *===========================================================================*/
static void onIntr( int s )
/*++++++++++++++++
.PURPOSE  Activated when INTR
.RETURNS  toOS
-----------------*/
/* IN: s=Signal number */
{
 if ( ov )
  fprintf( stderr, " (INTR signal#%d)\n", s );
 if ( ( skp >= skbuf ) && ( skp < ( skbuf + sizeof( skbuf ) ) ) )
  write( fileno( ofile ), skbuf, skp - skbuf );
 fprintf( stderr, "\n****INTR exit\n" );
 exit( 1 );
}

static void tooLong( int s )
/*++++++++++++++++
.PURPOSE  Activated when ALARM
.RETURNS  toOS
-----------------*/
/* IN: s=Signal number */
{
 int bytes;
 fprintf( stderr, "#***(ALARM signal (timeout=%ds)\n", reading_timeout );
 if ( ( skp >= skbuf ) && ( skp < ( skbuf + sizeof( skbuf ) ) ) ) {
  bytes= skp - skbuf;
  fprintf( stderr, "  [%d last bytes written out]\n", bytes );
  write( fileno( ofile ), skbuf, skp - skbuf );
 }
 fprintf( stderr, "\n****INTR exit\n" );
 exit( 1 );
}

int main( int argc, char **argv ) {
 char *p, *q, *host, *port, *body, *location, *qstring;
 int from_arg, i, n, len7[7], len, path_len, http_status, st= 0, sec, completed;
 static char sep[2];
 static char *method= "GET ";
 static char *buf= (char *)0;
 static int head_len= 0;
 static int status= 0; /* Returned Status */
 static int count= 0;
 int mult_query= 1; /* Accept several queries */
 struct stat sbuf;
 /* static char buf[BUFSIZ+160+sizeof(mozilla_def)] = "GET " */;

 /* Look for options */
 while ( ( argc > 1 ) && ( argv[1][0] == '-' ) ) {
  p= *++argv;
  --argc;
  switch ( p[1] ) {
  case 'h':
   if ( strcmp( p, "-head" ) == 0 ) {
    method= "HEAD ";
    ostrip= 1;       /* V3.02 */
    redirect_max= 0; /* V2.7: no redirection at all... */
    continue;
   }
   printf( "%s", usage );
   exit( 0 );
  case 'c':
   cookie= *++argv;
   --argc;
   if ( cookie )
    head_len+= 20 + strlen( cookie );
   continue;
  case 'r':                                /* Range  */
   if ( strncmp( p, "-redir", 6 ) == 0 ) { /* V2.7: -redirect */
    method= "Redirect ";
    mult_query= 0; /* Simgle output */
    redirect_max= 0;
    continue;
   }
   aR= *++argv;
   --argc;
   if ( aR )
    head_len+= 20 + strlen( aR );
   continue;
  case 'i': /*  Input File */
   if ( ifile )
    fclose( ifile );
   p= *++argv;
   --argc;
   /* Accept "-" as stdin. */
   if ( *p == '-' )
    ifile= stdin;
   else
    ifile= fopen( p, "r" );
   if ( !ifile ) {
    fprintf( stderr, "#***" );
    perror( p );
    exit( 1 );
   }
   continue;
  case 'o': /* Output File */
   p= *++argv;
   --argc;
   if ( stat( p, &sbuf ) ) { /* Output File only */
    ofile= fopen( p, "w" );
    if ( !ofile ) {
     fprintf( stderr, "#***" );
     perror( p );
     exit( 1 );
    }
    continue;
   }
   /* The file does exist -- if a directory, error */
   if ( S_ISDIR( sbuf.st_mode ) ) {
    fprintf( stderr, "#***Output file is a directory: %s\n", p );
    exit( 1 );
   }
   if ( S_ISREG( sbuf.st_mode ) ) { /* Regular File --> Add Range */
    if ( ov )
     fprintf( stderr,
              "#...Output file has %ld bytes: %s\n",
              sbuf.st_size, p );
    aR= malloc( 24 );
    sprintf( aR, "%ld-", sbuf.st_size );
    head_len+= 20 + strlen( aR );
   }
   ofile= fopen( p, "a" );
   if ( !ofile ) {
    fprintf( stderr, "#***" );
    perror( p );
    exit( 1 );
   }
   continue;
  case 'D': /* Domain */
   aD= p + 2;
   if ( aD )
    head_len+= 40 + strlen( aD );
   continue;
  case 'F': /* From:  */
   aF= p + 2;
   if ( aF )
    head_len+= 10 + strlen( aF );
   continue;
  case 'A': /* User-Agent */
   aA= p + 2;
   if ( aA )
    head_len+= strlen( aA );
   continue;
  case 'U': /* UserID */
   aU= p + 2;
   if ( aU )
    head_len+= 40 + strlen( aU );
   continue;
  case 'p':                                  /* -post / prompt */
   if ( isdigit( p[2] ) || ( p[2] == 0 ) ) { /* PROMPT */
    promptno= atoi( p + 2 );
    if ( promptno == 0 )
     promptno= 1;
    prompt= *++argv;
    --argc;
    continue;
   }
   if ( strcmp( p, "-post" ) )
    goto case_default;
   method= "POST ";
   mult_query= 0; /* Added V3.03 */
   continue;
  case 'q':
   oq= 1;
   mult_query= 0; /* Only 1 query acceptable */
   continue;
  case 't':
   p= *++argv;
   --argc;
   if ( p )
    reading_timeout= atoi( p );
   else
    reading_timeout= 0, fprintf( stderr,
                                 "#+++time-out not specified (-t option), set to infinite\n" );
   continue;
  case 'g':
   if ( strcmp( p, "-get" ) )
    goto case_default;
   method= "GET ";
   continue;
  case 'P': /* Passwd */
   aP= p + 2;
   if ( aP )
    head_len+= 40 + strlen( aP );
   continue;
  case 'm': /* Mozilla */
   omoz= p + 2;
   continue;
  case 'n': /* nostrip / Netscape */
   if ( p[2] == 'o' ) {
    ostrip= 1;               /* nostrip */
   } else if ( p[2] == 's' ) /* Compatibility V1.5 */
    omoz= p + 2;
   else
    goto case_default;
   continue;
  case 's': /* Strip or Silent */
   osilent= 1;
   if ( ostrip == 2 )
    ostrip= 0;
   continue;
  case 'v': /* Verbose */
   if ( strncmp( p, "-ver", 4 ) == 0 ) {
    printf( "wwwget (CDS), Version %s\n", VERSION );
    exit( 0 );
   }
   ov= 1;
   if ( ostrip == 0 )
    ostrip= 2;
   continue;
  case 'a': /* AbsAnch */
   oabs= 1;
   continue;
  case_default:
  default:
   fprintf( stderr, "#***Unknown argument: %s\n", p );
   fprintf( stderr, "%s", usage );
   exit( 1 );
  }
 }
 if ( argc < 2 ) {
  printf( "%s", usage );
  exit( 1 );
 }
 --argc;
 host= *++argv;
 if ( strncmp( host, "/http:/", 7 ) == 0 )
  host++;
 if ( strncmp( host, "http://", 7 ) == 0 ) /* Embedded host/file */
  host+= 7;
 if ( ( p= strchr( host, '/' ) ) ) { /* A document is specified */
  if ( mult_query ) {                /* Earch argument is a query */
   ++argc;
   --argv; /* Will be re-read in loop */
  }
 }
 set_url( host, 1 ); /* Set hostname + url[]	*/
 path_len= strlen( url[URL_PATH] );

 /* V2.7: if URL contains already the question mark, don't add */
 if ( strchr( url[URL_QUERY], '?' ) ) { /* Useful in -q option */
  p= url[URL_QUERY];
  sep[0]= p[strlen( p ) - 1];
  if ( ispunct( sep[0] ) ) /* Terminates by e.g. / & .. */
   sep[0]= 0;
  else
   sep[0]= '&';
 } else
  sep[0]= '?';

 if ( argc > 1 ) { /* Input in argument */
  from_arg= 1, argc--;
 } else {
  from_arg= 0;
  if ( oq && ( !ifile ) ) /* More arguments required */
   ifile= stdin;
  argc= 1; /* Force the loop    */
 }
 qstring= (char *)0; /* Used in -q option */

 while ( argc > 0 ) {
  if ( from_arg ) {
   p= *++argv, argc--;
   if ( strncmp( p, "/http:/", 7 ) == 0 )
    p++;
  } else if ( ifile )
   p= get1line( ifile );
  else
   p= (char *)0;
  if ( mult_query == 0 ) { /* Concatenate arguments */
   if ( p ) {              /* Append this argument */
    if ( !qstring )
     qstring= append( url[URL_QUERY], 0 );
    /* V2.52: Lines starting by non-char are a continuation */
    if ( isspace( *p ) ) {
     /* Remove trailing blanks */
     for ( q= qstring + strlen( qstring ) - 1;
           ( q >= qstring ) && isspace( *q );
           --q )
      ;
     *++q= 0;
    } else if ( sep[0] )
     qstring= append( sep, 0 );
    sep[0]= '&';
    qstring= append( p, 1 );     /* Code the argument  */
    if ( ifile || ( argc > 0 ) ) /* Get next parameter */
     continue;
   } else
    argc= 0; /* Asks looping stop! */
   p= qstring;
   from_arg= 0;
   if ( ov )
    fprintf( stderr, "#...Created QUERY argument: %s\n", p );
  }
  if ( !p ) {
   argc= 0;
   if ( count )
    continue; /* First call => GET / */
   p= "/";
  }
 Query_fullHTTP:
  count++;
  if ( mult_query == 0 ) { /* V2.7: Concatenates arguments */
   if ( !qstring )
    qstring= "";
   url[URL_QUERY]= strdup( qstring ); /* Update V2.91 */
   p= paste_url( url, 7 );
  }
  if ( method[0] == 'R' ) { /* V2.7: Generate only Redirect */
   if ( !ofile )
    ofile= stdout;
   fprintf( ofile, fmt_redirect, p, p, p );
   fflush( ofile );
   continue;
  }

  if ( cut_url( p, len7, 0 ) == 0 ) {
   if ( !osilent )
    fprintf( stderr,
             "#+++URL is neither HTTP nor FTP: %s (ignored)\n", p );
   continue;
  }
  p+= len7[0] + len7[1] + len7[2] + len7[3]; /* Keep PATH only */
  port= *url[URL_PORT] ? url[URL_PORT] + 1 : "80";

  /* Allocate a buffer for whole text to send.
	   In POST method, add the "Content-length"
	*/
  if ( buf )
   free( buf );
  /* V2.9: Replace spaces in URL (i = number of spaces) */
  /* n = strlen(p) ; */
  for ( i= n= 0; p[n]; n++ ) {
   if ( isspace( p[n] ) )
    i++;
  }
  n+= 24                                                        /*POST HTTP/1.0 */
      + 30                                                      /*Content-length*/
      + 20                                                      /*Host:         */
      + sizeof( keep_alive ) + sizeof( mozilla_def ) + head_len /* Cookie, authentificate, etc */
      + path_len + i * 2 /* Blanks converted to %20 */;
  buf= malloc( n );

  /* Fill the buffer: method path... HTTP/1.0 */
  strcpy( buf, method );
  len= strlen( buf ); /* Length of method */
#if 0
	if (!qstring) 		/* Beginning of url */
	    qstring = buf+len;
#endif
  if ( *p != '/' ) { /* Relative Address */
   strcpy( buf + len, url[URL_PATH] );
   len+= path_len;
  }
  /* strcpy(buf+len, p) ; */
  while ( *p ) {
   if ( isspace( *p ) ) {
    buf[len++]= '%';
    i= ( *p >> 4 ) & 0xf;
    buf[len++]= i < 10 ? '0' + i : ( 'A' - 10 ) + i;
    i= ( *p ) & 0xf;
    buf[len++]= i < 10 ? '0' + i : ( 'A' - 10 ) + i;
   } else
    buf[len++]= *p;
   p++;
  }
  buf[len]= 0;
  if ( ( buf[0] == 'P' ) && ( body= strchr( buf, '?' ) ) ) {
   len= body - buf;
   *( body++ )= 0; /* Skip the ? in POST */
   body= strdup( body );
  } else
   body= (char *)0;
  p= buf + len;
  sprintf( p, " HTTP/1.0\r\nHost: %s%s\r\n", hostname,
           strcmp( url[URL_PORT], ":80" ) ? url[URL_PORT] : "" );
  p+= strlen( p );
  if ( aD ) {
   sprintf( p, "WWW-Authenticate: Basic realm=\"%s\"\r\n", aD );
   p+= strlen( p );
  }
  if ( aU ) {
   strcpy( p, "Authorization: Basic " );
   p+= strlen( p );
   strcpy( p, aU );
   if ( aP )
    strcat( p, ":" ), strcat( p, aP );
   strcpy( p, enc64( p ) );
   strcat( p, "\r\n" );
   p+= strlen( p );
  }
  if ( aF ) {
   strcpy( p, "From: " );
   strcat( p, aF );
   strcat( p, "\r\n" );
   p+= strlen( p );
  }
  if ( aR ) {
   strcpy( p, "Range: bytes=" );
   strcat( p, aR );
   strcat( p, "\r\n" );
   p+= strlen( p );
  }
  if ( omoz ) {                       /* Emulate Netscape Query */
   i= strloc( mozilla_def, '/' ) + 1; /* Mozilla version */
   if ( isdigit( omoz[0] ) ) {
    mozilla_def[i]= omoz[0];
    if ( isdigit( omoz[2] ) )
     mozilla_def[i + 2]= omoz[2];
   }
   strcat( p, mozilla_def );
  } else {
   strcat( p, "User-Agent: " );
   if ( !aA )
    aA= getenv( "AGENT" );
   if ( aA && *aA == ':' ) {
    for ( ++aA; *aA == ' '; aA++ )
     ;
    strcat( p, aA );
   } else {
    if ( !aA )
     aA= VERSION;
    strcat( p, "wwwget/" );
    strcat( p, aA );
   }
   strcat( p, "\r\nAccept: */*\r\n" );
  }
#if 0
	     strcat(p, "User-Agent: wwwget/2.3\r\nAccept: */*\r\n");
#endif
  p+= strlen( p );
  if ( cookie ) {
   strcpy( p, "Cookie: " );
   strcat( p, cookie );
   strcat( p, "\r\n" );
   p+= strlen( p );
  }
  if ( body ) { /* Content-length */
   sprintf( p, "Content-length: %d\r\n", n= strlen( body ) );
   p+= strlen( p );
  }
  strcat( p, keep_alive );
  strcat( p, "\r\n" );
  if ( body ) { /* Body of posted text	*/
   p+= strlen( p );
   strcpy( p, body );
   p+= strlen( p );
   strcpy( p, "\r\n" );
   free( body );
   body= (char *)0;
  }

  /* Open the Connection */
 Query_HTTP:
  if ( !ofile )
   ofile= stdout;
  ofno= fileno( ofile );
  if ( ov )
   fprintf( stderr, "#...Contacting %s:%s", hostname, port ),
       fflush( stderr );
  plug= sk_open( hostname, port );

  if ( plug < 0 ) {
   status= 1;
   continue;
  } /* Modif V3.11 */

  if ( ov )
   fprintf( stderr, "\n#...Sending the message:\n%s", buf );

  /* Issue the Question  */
  for ( p= buf; *p; p+= n ) {
   n= write( plug, p, strlen( p ) );
   if ( n < 0 ) {
    perror( hostname );
    break;
   }
  }
  if ( n < 0 )
   continue;

  /* Get the Header as answer */
  skp= skbuf, ske= skbuf + sizeof( skbuf ) - 1;
  starting_time= time( 0 );
  if ( ov )
   fprintf( stderr, "#...Reading first block:    0" ),
       fflush( stderr );
  signal( SIGINT, onIntr );
  signal( SIGALRM, tooLong );
  i= 0; /* Indicates number of tests header is read */
  while ( skp < ske ) {
   n= read( plug, skp, ske - skp );
   if ( n <= 0 )
    break;
   skp+= n;
   *skp= 0;
   if ( ov )
    fprintf( stderr, "\b\b\b\b%4d", (int)( skp - skbuf ) ),
        fflush( stderr );
   if ( i == 0 ) { /* Normally, the second call should indicate end,
			   but it may be slow... */
    if ( strstr( skbuf, "\r\n\r\n" ) )
     break; /*i=1;*/
   } else
    break;
  }
  if ( n < 0 ) {
   perror( hostname );
   status= 2;
   continue;
  }
  if ( ov )
   fprintf( stderr, ".\n" );
  completed= ( n == 0 ) || ( method[0] == 'H' );
  ske= skp;
  skp= skbuf;
  content_length= CONTENT_LENGTH_MAX;
  location= (char *)0;

  /* Find the returned status */
  if ( ( ( ske - skbuf ) > 13 ) && ( strncmp( skbuf, "HTTP", 4 ) == 0 ) ) {
   for ( p= skp; isgraph( *p ); p++ )
    ;
   while ( *p == ' ' )
    p++;
   http_status= atoi( p );
  } else
   http_status= 503; /* Service Unavailable */

  /* Interpret the header */
  while ( skp < ske ) {
   while ( isgraph( *skp ) )
    skp++;
   i= 0;
   if ( skp[0] == '\r' && skp[1] == '\n' && skp[2] == '\r' && skp[3] == '\n' )
    i= 4;
   else if ( skp[0] == '\n' ) {
    if ( skp[1] == '\n' )
     i= 2;
    else if ( strncmp( skp + 1, "Content-Length:", 15 ) == 0 )
     content_length= atoll( skp + 16 );
    else if ( strncmp( skp + 1, "Location:", 9 ) == 0 )
     for ( location= skp + 10; *location == ' '; location++ )
      ;
   }
   if ( i ) { /* Is the End of the Header */
    if ( ostrip ) {
     FILE *of;
     of= ostrip == 1 ? ofile : stderr;
     fflush( of );
     if ( write( fileno( of ), skbuf, ( skp + ( i >> 1 ) ) - skbuf ) < 0 )
      fprintf( stderr, "#***write socket error: %s\n",
               strerror( errno ) );
     fprintf( of, "Host: %s%s (wwwget", hostname, url[URL_PORT] );
     if ( oabs )
      fprintf( of, " -abs" );
     fprintf( of, ")\r\nDocument: " );
     p= buf + strloc( buf, ' ' );
     if ( *p )
      p++;
     fwrite( p, 1, strloc( p, ' ' ), of );
     fputc( ' ', of );
     fputc( '(', of );
     for ( p= buf; isgraph( *p ); p++ )
      fputc( *p, of );
     fputc( ')', of );
     fwrite( skp, 1, i, of );
     fflush( of );
    }
    skp+= i;
    break;
   }
   skp++;
  }

  if ( http_status >= 400 ) { /* An error occured... */
   close( plug );
   status= 2;
   if ( osilent ) /* Silent: don't display anything... */
    continue;
#if 0
	    if (!isatty(ofno)) {
		write(ofno, "#***", 4);
	        write(ofno, skbuf, ske-skbuf);
	    }
#endif
   fprintf( stderr, "#***Error %d****\n", http_status );
   if ( ov )
    continue;
   fwrite( skbuf, 1, ske - skbuf, stderr );
   fputc( '\n', stderr );
   fflush( stderr );
   continue;
  }

  if ( ov && ( skp > skbuf ) && ( !completed ) && ( !isatty( ofno ) ) ) {
   fprintf( stderr, "#...Header%s is:\n", ostrip ? " (stripped)" : "" );
   fflush( stderr );
   if ( ostrip != 2 ) /* V2.4: don't rewrite a 2nd time... */
    write( 2, skbuf, skp - skbuf - 1 );
  }

  /* REDIRECT ... Do It ! */
  if ( ( http_status >= 300 ) && ( http_status < 400 ) ) {
   redirect_count++;
   if ( !location ) {
    if ( !osilent )
     fprintf( stderr,
              "#***Missing 'Location:' in answer %d\n", http_status );
    status= 2;
    continue;
   }
   if ( buf )
    free( buf );
   n= strloc( location, '\n' );
   while ( isspace( location[n] ) )
    n--;
   location[++n]= 0;
   if ( osilent )
    ;
   else {
    if ( ostrip || ov )
     fprintf( stderr, "#---Redirecting" );
    if ( ov )
     fprintf( stderr, "#---\n" );
    else if ( ostrip )
     fprintf( stderr, ": " );
    if ( ostrip || ov )
     fprintf( stderr, "%s\n", location );
   }
   if ( redirect_max == 0 ) { /* V2.7: HEAD does not redirect */
    p= "Location: ";
    st= write( ofno, p, strlen( p ) );
    if ( st >= 0 )
     st= write( ofno, location, strlen( location ) );
    if ( st >= 0 )
     st= write( ofno, "\r\n", 2 );
    if ( st < 0 )
     fprintf( stderr, "#***Redirect error: %s\n",
              strerror( errno ) );
    continue;
   }
   buf= malloc( n + 22 );
   strcpy( buf, method /*"GET "*/ );
   strcat( buf, location );
   strcat( buf, " HTTP/1.0\r\n\r\n" );
   if ( redirect_count > redirect_max ) {
    if ( !osilent )
     fprintf( stderr,
              "#***Too many (%d) redirections -- loop? %s\n",
              redirect_count, location );
   }
   if ( strncmp( location, "http:", 5 ) == 0 ) {
    p= location;
    set_url( p, 1 );
    goto Query_fullHTTP;
   }
   goto Query_HTTP;
  }

  redirect_count= 0;
  /*if (ov && isatty(ofno)) ov = 0 ;*/
  skbytes= ( ske - skbuf );
  if ( ov )
   fprintf( stderr, "#...Reading bytes from host: %8lld", skbytes ),
       fflush( stderr );

  if ( oabs ) {
   exec_abs( ofile );
   fflush( ofile );
  } else {
   len= prompt ? check_prompt( skp ) : ske - skp;
   if ( write( ofno, skp, len ) < 0 )
    fprintf( stderr,
             "#***write(%d bytes) [%s]\n", len, strerror( errno ) );
  }

  /* Get the rest of Answer 	*/
  if ( completed ) { /* Normal that it's end */
   close( plug );
   continue;
  }
  /* Is the Content-Length known ? */
  if ( content_length == CONTENT_LENGTH_MAX ) {
   if ( ov )
    fprintf( stderr, "#+++No Content-Length+++#\n" );
   /*content_length = 1; content_length <<= 50;*/
  } else if ( skbytes >= content_length ) /* Everything read... */
   completed= 1;
  while ( !completed /*skbytes < content_length*/ ) {
   if ( prompt && ( promptno <= 0 ) )
    break;
   n= skread();
   if ( n <= 0 )
    break;                               /* Error */
   completed= skbytes >= content_length; /* V3.13 */
   len= prompt ? check_prompt( skbuf ) : n;
   if ( oabs )
    exec_abs( ofile );
   else
    st= write( ofno, skbuf, len ); /* Error corrected, thanks to
					            Aymeric SAUVAGEON */
   if ( st < 0 ) {
    fprintf( stderr, "#**write buffer of %d bytes: %s\n",
             len, strerror( errno ) );
    break;
   }
  }
  if ( ov ) {
   double rate;
   sec= ( time( 0 ) - starting_time );
   if ( sec > 0 )
    rate= skbytes / sec / 1024.;
   else
    rate= skbytes;
   fprintf( stderr, "\r %10lld %7.1fKb/s", skbytes, rate );
   fprintf( stderr, " (End)         \n" );
   fflush( stderr );
  }
  if ( ( content_length != CONTENT_LENGTH_MAX ) && ( skbytes < content_length ) && ( !osilent ) )
   fprintf( stderr,
            "#+++Getting %s: read %lld/%lld bytes\n",
            hostname, skbytes, content_length );
  close( plug );
  /* write(1, "\n", 1) ; */
 }

 exit( status );
}
