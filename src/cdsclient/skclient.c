/*++++++++++++++
 Copyright:    (C) 2008-2017 UDS/CNRS
 License:       GNU General Public License
.IDENTIFICATION skclient.c
.LANGUAGE       C
.AUTHOR         Francois Ochsenbein [CDS]
.ENVIRONMENT    Internet
.KEYWORDS       Client/Server
.VERSION  1.0   04-Aug-1992
.VERSION  1.1   20-Aug-1992: Added sk_obeyserver
.VERSION  1.2   21-Oct-1992: Added sk_fromclient. sk_obeyserver now requires
			functions.
.VERSION  2.0   10-May-1993: 
.VERSION  2.1   02-Jul-1993: Added sk_error, sk_setlog
.VERSION  2.2   03-Mar-1994: ! marks root
.VERSION  2.3   08-Jul-1994: sk_connect returns -2 when connection refused
			by peer.
.VERSION  2.4   03-Nov-1994: Bufferization
.VERSION  2.5   16-Jan-1995: BASIC option; sk_setlog put in skio.c
.VERSION  2.6   07-Nov-1995: Use REMOTE_HOST + REMOTE_USER
				if existing, indicated by +USER@HOST
.VERSION  2.7   21-Jan-1997: Use SYSV gethostname
.VERSION  2.8   29-Jun-1998: Modified err2
.VERSION  2.81  16-Aug-2006: One bug in authentication!
.VERSION  2.82  20-Nov-2006: Limit size of remote_host
.COMMENTS       Client routines
---------------*/

#ifndef NSOCKS
#define NSOCKS 64
#endif
#include <sk.h>
#include <stdio.h>
#include <ctype.h>
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <netdb.h>
#ifdef VMS /* All definition files in single directory */
#include <types.h>
#include <socket.h>
#include <in.h>
#else                    /* Assume standard Unix */
#include <sys/utsname.h> /* for gethostname	*/
#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netinet/tcp.h> /* Internet sockets definitions	*/
#endif
#define mexp( b, l ) ( b ? realloc( b, l ) : malloc( l ) ) /* Reallocation */

typedef struct {
 char interrupt; /* Interrupt Signal */
 char unused[3];
 char *server; /* Server Information: Host/Service:pid.plug */
} PLUG;
typedef struct {     /* Buffer */
 int abytes, ubytes; /* Allocated, Used */
 char *buffer;
} ABUF;

extern char *getlogin();
extern FILE *sk_getlog();
extern void ( *sk_errfct() )();

static PLUG plugs[NSOCKS];
static ABUF errs;    /* Error message */
static char in_open; /* Set to 1 if in sk_open */

/*==================================================================
		BSD Utilities
 *==================================================================*/
static int getHostname( host, len )
    /*++++++++++++++++
.PURPOSE  Get name of host
.RETURNS  0 (OK) / 1 (truncated) /-1(error)
.REMARKS  BSD compatibility routine
-----------------*/
    char *host; /* OUT: Name of host 	*/
int len;        /* IN: Size of name	*/
{
 struct utsname name;
 int status;
 status= uname( &name );
 if ( status < 0 )
  return ( status );
 strncpy( host, name.nodename, len );
 if ( (int)strlen( name.nodename ) >= len )
  status= 1;
 return ( 0 );
}

/*============================================================================
 *		Error routines
 *============================================================================*/
static int cat_err( msg )
    /*++++++++++++++++
.PURPOSE  Append error to error buffer
.RETURNS  Length of full message
-----------------*/
    char *msg; /* IN: Message to append	*/
{
 int len;
 len= errs.ubytes + strlen( msg );
 if ( len >= errs.abytes ) { /* Have to expand error buffer */
  errs.abytes= ( len + 1 + 63 ) & ~63;
  errs.buffer= mexp( errs.buffer, errs.abytes );
 }
 strcpy( errs.buffer + errs.ubytes, msg );
 errs.ubytes= len;
 return ( errs.ubytes );
}

static void err2( msg, text )
    /*++++++++++++++++
.PURPOSE  Write msg: text to log file
.RETURNS  ---
-----------------*/
    char *msg; /* IN: Message to append	*/
char *text;    /* IN: Second message		*/
{
 FILE *logfile;

 errs.ubytes= 0; /* Free error message */
 cat_err( msg );
 if ( text )
  cat_err( ": " ), cat_err( text );
 if ( ( logfile= sk_getlog() ) ) {
  fprintf( logfile, "%s\n", errs.buffer );
  fflush( logfile );
 }
}

static void put_err( msg )
    /*++++++++++++++++
.PURPOSE  Write msg: error message
.RETURNS  ---
-----------------*/
    char *msg; /* IN: Message to append	*/
{
 char buf[32], *errmsg;
 errmsg= strerror( errno );
 if ( !errmsg )
  sprintf( errmsg= buf, "[unknown errno #%d]", errno );
 err2( msg, errmsg );
}

/*============================================================================
 *		Internal routines
 *============================================================================*/
static int set_slot( plug, val )
    /*++++++++++++++++
.PURPOSE  Set the plug slot to a value
.RETURNS  Previous value of the slot
-----------------*/
    int plug; /* IN: Started Socket Number 	*/
int val;      /* IN: Value to set to slot	*/
{
 int ret;
 if ( plug < 0 )
  return ( -1 );
 if ( plug >= NSOCKS )
  return ( -1 );
 ret= plugs[plug].interrupt;
 plugs[plug].interrupt= val;
 return ( ret );
}

/*============================================================================
 *		Public routines
 *============================================================================*/
char *sk_error()
/*++++++++++++++++
.PURPOSE  Get the last error message
.RETURNS  The error message
-----------------*/
{
 return ( errs.buffer );
}

int sk_kill( plug, sig )
    /*++++++++++++++++
.PURPOSE  Interrupt the exchange with Server
.RETURNS  Number of bytes transmitted (1) / Error
-----------------*/
    int plug; /* IN: Started Socket Number 	*/
int sig;      /* IN: Signal to send to Server */
{
 static char bsig[2];
 int stat;

 bsig[0]= sig ? sig : SIGINT;
#ifdef DEBUG
 fprintf( stderr, "send(%d, ^%c, 1, %d)\n", plug, bsig[0] | 0100, MSG_OOB );
#endif
 stat= send( plug, bsig, 1, MSG_OOB );
 if ( stat < 0 )
  put_err( "Send OOB" );
 return ( stat );
}

/*============================================================================*/

int sk_obeyserver( plug, digest, more )
    /*++++++++++++++++
.PURPOSE  Dialog with the server using two routines, 
	. digest which gets what comes from the Server, and
	. more which is called when the Server requires more data.
	These functions have two parameters (buffer, length), 
	    and return a number of bytes processed.
	The following conventions are used:
	^D = End of transfer from Server (return from this function)
	^B = Start of Buffer Mode (server will send length + data)
	^C = Error Message as a Buffer 
	^F = Server asks to send a Buffer (length + data)
	     In this case, data acquired from more file are sent to Server.
.RETURNS  Number of bytes transferred / -1=Error 
-----------------*/
    int plug;      /* IN: Started Socket Number 	*/
int ( *digest )(); /* IN: Routine getting what's sent by Server */
int ( *more )();   /* IN: Routine generating data    for Server */
{

 char bufop, eof, c;
 int lb, stat, bytes, i;
 char *b, *p, buf[BUFSIZ];

 /* WRITE a file, i.e. READ the socket.
	   The Server may send in BUFFERED mode indicated by ^B
	*/

 bytes= stat= lb= 0;
 b= (char *)0;
 set_slot( plug, 0 ); /* Clear Interrupt */
 for ( eof= bufop= 0; !eof; ) {
  if ( bufop ) {          /* Get in BUFFER mode */
   stat= sk_getl( plug ); /* Size  */
#ifdef DEBUG
   fprintf( stderr, "\nHave to read %d bytes\n", stat );
#endif
   if ( stat < 0 )
    break;
   if ( stat == 0 ) {
    bufop= 0;
    continue;
   }
   if ( lb < stat ) {
    lb= ( stat + 1023 ) & ( ~1023 );
    b= mexp( b, lb );
   }
   if ( sk_get( plug, b, stat ) != stat ) {
    stat= -1;
    break;
   }
   if ( bufop == 2 ) { /* Error msg */
    if ( stat < lb )
     b[stat]= 0;
    err2( b, (char *)0 );
    bufop= 0; /* Error is a single buffer  */
    continue;
   }
   p= b;
  } else {
   stat= sk_read( plug, buf, sizeof buf );
   if ( stat < 0 ) {
    stat= -1;
    break;
   }
   if ( stat == 0 ) {
    if ( !in_open )
     err2( "++++Server closed connection", (char *)0 );
    stat= -1;
    break;
   }
   /* More than what's required may have been read. 
		   Therefore locate first control char with octal \00x
		   which has a meaning in the protocol
		*/
   for ( i= 0; ( i < stat ) && ( buf[i] & ( ~7 ) ); i++ )
    ;
   if ( i < stat ) { /* Special char located. 
				   Put back what's over-read. */
    if ( ++i < stat )
     sk_iosave( plug, buf + i, stat - i );
    stat= i;
   }
   switch ( c= buf[stat - 1] ) {
   case '\04':
    eof= 1;
    --stat;
    break;
   case '\06': /* TRANSMIT data from more in Buffer Mode */
    if ( --stat )
     ( *digest )( buf, stat );
    if ( !b ) {
     lb= 60 * 1024;
     b= malloc( lb );
    }
    stat= ( *more )( b, lb );
    if ( stat < 0 ) {
     eof= 1;
     continue;
    } /* Will stop */
    if ( sk_putl( plug, stat ) < 0 ) {
     stat= -1;
     eof= 1; /* Will stop */
    }
    if ( stat <= 0 )
     continue;
    if ( sk_write( plug, b, stat ) != stat ) {
     stat= -1;
     eof= 1; /* Will stop */
    }
    continue;
   case '\03': /* Error msg */
   case '\02':
    bufop= c - 1;
    --stat;
    sk_write( plug, "\06", 1 ); /* Send Ack  */
    break;
   }
   p= buf;
  }
  if ( ( *digest )( p, stat ) < 0 ) {
   stat= -1;
   break;
  }
  if ( stat > 0 )
   bytes+= stat;
 }

 if ( b )
  free( b );
 return ( stat < 0 ? stat : bytes );
}

static int fdigest= 1; /* File number from sk_fromserver */
static int fmore= 0;   /* File number from sk_fromserver */

static int mydigest( buf, len )
    /*++++++++++++++++
.PURPOSE  Function to write to fdigest
.RETURNS  Number of bytes written
-----------------*/
    char *buf; /* IN: Buffer to write   */
int len;       /* IN: Bytes written out */
{
 int n;

 n= write( fdigest, buf, len );
 if ( n < 0 )
  put_err( "****sk_fromserver Writing File" );
 return ( n );
}

static int mymore( buf, len )
    /*++++++++++++++++
.PURPOSE  Function to write to fmore
.RETURNS  Number of bytes written
-----------------*/
    char *buf; /* IN: Buffer to write   */
int len;       /* IN: Bytes written out */
{
 int n;

 n= read( fmore, buf, len );
 if ( n < 0 )
  put_err( "****sk_fromserver Reading File" );
 return ( n );
}

int sk_fromserver( plug, fh, fsend )
    /*++++++++++++++++
.PURPOSE  Copy what comes from server to fh file. This function obey to
	the following conventions:
	^D = End of transfer from Server (return from this function)
	^B = Start of Buffer Mode (server will send length + data)
	^F = Server asks to send a Buffer (length + data)
	     In this case, data from fsend file are sent to Server.
.RETURNS  Number of bytes transferred / -1=Error 
-----------------*/
    int plug; /* IN: Started Socket Number 	*/
int fh;       /* IN: OUTput file handle	*/
int fsend;    /* IN: INput file to send if Server asks to */
{
 fdigest= fh;
 fmore= fsend;
 return ( sk_obeyserver( plug, mydigest, mymore ) );
}

/*===========================================================================*
		Connection to Server
 *===========================================================================*/
static char *user; /* Set by sk_connect */
static char *pswd; /* Set by sk_connect */

static int open_digest( buf, len )
    /*++++++++++++++++
.PURPOSE  At Open, writes what comes from Server
.RETURNS  0 = OK
.REMARKS  At this connection level, what comes is just written on stderr.
-----------------*/
    char *buf; /* IN: Buffer to write   */
int len;       /* IN: Bytes written out */
{
 if ( len <= 0 )
  return ( len );
 buf[len]= 0;
#ifdef DEBUG
 printf( "++++open_digest, received <%s>\n", buf );
 err2( buf, (char *)0 );
#endif
 return ( len );
}

static int open_more( buf, len )
    /*++++++++++++++++
.PURPOSE  At Open (Connect), write the Password
.RETURNS  Number of bytes 
-----------------*/
    char *buf; /* IN: Buffer to write   */
int len;       /* IN: Size of  buf	 */
{
 int n;
#ifdef DEBUG
 printf( "++++open_more called\n" );
#endif
 n= pswd ? strlen( pswd ) : 0;
 if ( n )
  strcpy( buf, pswd ), pswd= (char *)0;
 return ( n );
}

int sk_open( machine, service )
    /*++++++++++++++++
.PURPOSE  Start a client connecting to a machine / Service
.RETURNS  File number; -1 when can't connect, -2 when connection refused
.REMARKS  Machine and Service can be symbolic (letters) or numeric
	Non-numeric services are to be found in /etc/services.
	At the prompt (\n-terminated) sent by the Server, the client
	replies with User@Machine
-----------------*/
    char *machine; /* IN: Machine to connect to */
char *service;     /* IN: Service to connect to */
{
 int plug;                      /* socket to "plug" into the socket */
 struct sockaddr_in socketname; /* mode, addr, and port for socket */
 struct hostent *remote_host;   /* internet numbers, names   */
 struct servent *ps;            /* Returned by getservbyname */
 char buf[120];
 int len, stat;
 char *p, *pu;

 sk_errfct( put_err ); /* Save & Print error messages */
 /* make an internet-transmitted, file-i/o-style, protocol-whatever plug */
 if ( ( plug= socket( AF_INET, SOCK_STREAM, 0 ) ) < 0 ) {
  put_err( "****sk_open: can't start socket" );
  return ( -1 );
 }
 if ( plug >= NSOCKS ) {
  sprintf( buf, "%d", plug );
  err2( "****(Client)Too many opened sockets", buf );
  return ( -1 );
 }
 if ( plugs[plug].server )
  free( plugs[plug].server );
#ifdef NODELAY
 stat= TCP_NODELAY;
 if ( setsockopt( plug, IPPROTO_TCP, TCP_NODELAY,
                  (char *)&stat, sizeof( stat ) ) < 0 ) {
  put_err( "Can't setsockopt(TCP_NODELAY)" );
  return ( -1 );
 }
#endif

 /* Fill in the socket structure with Host and Service */
 memset( socketname.sin_zero, 0, sizeof( socketname.sin_zero ) );
 socketname.sin_family= AF_INET;
 if ( isalpha( *machine ) ) {
  if ( !( remote_host= gethostbyname( machine ) ) ) {
   err2( "****sk_open: unknown host", machine );
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
   err2( "****sk_open: unknown service", service );
   return ( -1 );
  }
  socketname.sin_port= ps->s_port;
 } else
  socketname.sin_port= htons( atoi( service ) );

 /* plug into the listening socket */
 if ( connect( plug, (struct sockaddr *)&socketname,
               sizeof( socketname ) ) < 0 ) {
  put_err( "****sk_open: can't connect" );
  return ( -1 );
 }

 /* Server sends an Identification line (host/service:pid.plug);
    	   keep it in the PLUG */
 len= sk_gets( plug, buf, sizeof( buf ) );
 if ( len <= 0 )
  return ( -1 );
 buf[len - 1]= 0; /* Remove \n */
 plugs[plug].server= malloc( len );
 strcpy( plugs[plug].server, buf );

 /* Find out UserName as  REMOTE_USER (if defined) or Local */
 p= buf;
 if ( ( pu= getenv( "REMOTE_USER" ) ) )
  *( p++ )= '+';
 if ( !pu )
  pu= getenv( "USER" );
 if ( !pu )
  pu= getlogin();
 if ( !pu )
  pu= "daemon";
 strncpy( p, pu, 10 );
 p[10]= 0; /* V2.82: Limit */
 p+= strlen( p );
 if ( !getuid() )
  *( p++ )= '!'; /* Indicates root privilege */

 /* Find out REMOTE_HOST; otherwise, get current hostname    */
 *( p++ )= '@';
 if ( ( pu= getenv( "REMOTE_ADDR" ) ) ) {
  strcpy( p, pu );
  p+= strlen( p );
  *( p++ )= '=';
  *p= 0;                                   /* V2.81 */
  if ( ( pu= getenv( "REMOTE_HOST" ) ) ) { /* V2.82 */
   strncpy( p, pu, 36 );                   /* V2.82 */
   p[36]= 0;
   if ( strlen( pu ) > 36 )
    p[35]= p[34]= p[33]= '.';
  }
 } else
  getHostname( p, ( buf + sizeof( buf ) ) - p );
 p+= strlen( p );

 /* Append the 'user' argument, if any	*/
 if ( user )
  *( p++ )= ':', strcpy( p, user );

 /* Send Username + Machine */
 sk_puts( plug, buf );
 /* err2("#...sk_put", buf); */
 /* printf("sk_put(%s)\n", buf); */

 /* Wait for OK from Server (normally ^D).
	   The Server may ask for a Password (^F),
	   passed through standard communications */
 in_open= 1;
 if ( sk_obeyserver( plug, open_digest, open_more ) < 0 ) {
  close( plug );
  return ( -2 );
 }
 in_open= 0;
 return ( plug );
}

int sk_connect( machine, service, username, password )
    /*++++++++++++++++
.PURPOSE  Start a client connecting to a machine / Service,
		and send User/Password
.RETURNS  Plug number ; -1 when can't connect, -2 when connection refused
.REMARKS  Upon successful identification, Server sends ^D;
	it sends otherwise an error message which is reproduced
	on stderr.
-----------------*/
    char *machine; /* IN: Machine to connect to */
char *service;     /* IN: Service to connect to */
char *username;    /* IN: A username for Server */
char *password;    /* IN: A password for Server */
{
 int plug; /* socket to "plug" into the socket */

 user= username;
 pswd= password;
 plug= sk_open( machine, service );
 user= pswd= (char *)0;

 return ( plug );
}
