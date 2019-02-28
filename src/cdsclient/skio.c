/*++++++++++++++
 Copyright:    (C) 2008-2017 UDS/CNRS
 License:       GNU General Public License
.IDENTIFICATION skio.c
.LANGUAGE       C
.AUTHOR         Francois Ochsenbein [CDS]
.ENVIRONMENT    
.KEYWORDS       
.VERSION  1.0   04-Aug-1992
.VERSION  1.1   20-Aug-1992: Added sk_getl, sk_putl
.VERSION  1.2   12-Dec-1992: Added sk_setb
.VERSION  2.0   10-May-1993:
.VERSION  2.1   03-Nov-1994: Added sk_iolog
.VERSION  2.2   16-Jan-1995: BASIC option; added sk_setlog
.VERSION  2.3   21-Mar-2000: Gnu C compiler dones't accept iinit stderr
.VERSION  2.4   27-Oct-2005: log functions... confusion with math !!
.COMMENTS       Read/Write on Sockets
---------------*/

#ifndef NSOCKS
#define NSOCKS 256
#endif

#include <stdio.h>
#include <ctype.h>

#ifdef VMS /* Special definitions for VAXes (as always) */
#include <types.h>
#include <in.h>
#else
#include <unistd.h>     /* ntohl */
#include <sys/types.h>  /* ntohl */
#include <netinet/in.h> /* Byte order */
#endif
static FILE *logfile= (FILE *)( -1 ); /* VAX and GNU can't assign stderr !! */

typedef void ( *FCT )();
typedef struct {   /* A buffer to save what's read */
 int size, offset; /* Size of buf, position in buf */
 char *buf;        /* Buffer 			*/
} BUF;
extern void perror();

static BUF *inputs[NSOCKS];
static FCT errfct= perror; /* Function used to report errors */
static int sksize= 0;      /* Individual size of sockets */

#include <string.h> /* For memcpy */
#include <stdlib.h> /* For malloc */

static FILE *iologfile; /* Debugging Log-file (set by sk_iolog) */

static void log_b( fct, buf, len )
    /*++++++++++++++++
.PURPOSE  Log what's comes in
.RETURNS  ---
-----------------*/
    char *fct,
    *buf;
int len;
{
 int i;
 char c;
 if ( !iologfile )
  return;
 fprintf( iologfile, "....%8s:%5d bytes \"", fct, len );
 for ( i= 0; i < len; i++ ) {
  if ( i == 24 ) { /* Skip remaining */
   fprintf( iologfile, "\"..." );
   i= len - 1;
  }
  switch ( c= buf[i] ) {
  case '\\':
   fprintf( iologfile, "\\\\" );
   continue;
  case '"':
   fprintf( iologfile, "\\\"" );
   continue;
  case '\n':
   fprintf( iologfile, "\\n" );
   continue;
  case '\r':
   fprintf( iologfile, "\\r" );
   continue;
  case '\t':
   fprintf( iologfile, "\\t" );
   continue;
  default:
   if ( isprint( c ) )
    fputc( c, iologfile );
   else
    fprintf( iologfile, "\\%03o", c & 0xff );
   continue;
  }
 }
 if ( i <= 24 )
  fputc( '\"', iologfile );
 fputc( '\n', iologfile );
 fflush( iologfile );
 return;
}

static void log_l( fct, val )
    /*++++++++++++++++
.PURPOSE  Log what's comes in
.RETURNS  0
-----------------*/
    char *fct;
int val;
{
 if ( !iologfile )
  return;
 fprintf( iologfile, "....%8s= %d\n", fct, val );
 fflush( iologfile );
 return;
}

static int err3( ssp, plug, len )
    /*++++++++++++++++
.PURPOSE  Error report
.RETURNS  0
-----------------*/
    char *ssp; /* IN: Subroutine name */
int plug;      /* IN: Socket number */
int len;       /* IN: Length variable */
{
 char buffer[128];
 sprintf( buffer, "****%s plug#%d for %d bytes", ssp, plug, len );
 ( *errfct )( buffer );
 return ( 0 );
}

static int bread( fno, buf, len )
    /*++++++++++++++++
.PURPOSE  Internal read from associated buffer
.RETURNS  Length of what's read
-----------------*/
    int fno; /* IN: File Descriptor */
char *buf;   /* OUT: Buffer filled  */
int len;     /* IN: Max len to read */
{
 int bytes;
 BUF *b;
 b= inputs[fno];
 if ( !b )
  return ( 0 );
 bytes= ( b->offset + len ) > b->size ? b->size - b->offset : len;
 memcpy( buf, b->buf + b->offset, bytes );
 b->offset+= bytes;
 if ( b->offset >= b->size )
  free( b ), inputs[fno]= (BUF *)0;
 if ( iologfile )
  log_b( "sk_read(from saved buffer)", buf, bytes );
 return ( bytes );
}

int sk_setb( block )
    /*++++++++++++++++
.PURPOSE  Set the size of blocks for socket transfer
.RETURNS  The previous value of the socket size
.REMARKS  A value < 1 does not change the socket blocksize.
-----------------*/
    int block; /* IN: Size of socket blocks in bytes (< 511) of blocks */
{
 int ob;
 ob= sksize;
 if ( block > 0 ) {
  sksize= block;
  if ( sksize < 511 )
   sksize*= 512;
 }
 return ( ob );
}

FCT sk_errfct( f )
    /*++++++++++++++++
.PURPOSE  Set the error function
.RETURNS  The previous errfct function
.REMARKS  Default is perror.
-----------------*/
    FCT f; /* IN: New errfct function */
{
 FCT o;
 o= errfct;
 errfct= f ? f : perror;
 return ( o );
}

FILE *sk_getlog()
/*++++++++++++++++
.PURPOSE  Retrieve the current LogFile
.RETURNS  The current logfile
-----------------*/
{
 if ( logfile == (FILE *)( -1 ) )
  logfile= stderr;
 return ( logfile );
}

FILE *sk_setlog( f )
    /*++++++++++++++++
.PURPOSE  Set the logfile (where to write errors)
.RETURNS  The previous DEBUG logfile
.REMARKS  Default is no debugging log
-----------------*/
    FILE *f; /* IN: New log file	*/
{
 FILE *o;
 if ( logfile == (FILE *)( -1 ) )
  logfile= stderr;
 o= logfile;
 logfile= f;
 return ( o );
}

FILE *sk_iolog( f )
    /*++++++++++++++++
.PURPOSE  Set the DEBUG logfile
.RETURNS  The previous DEBUG logfile
.REMARKS  Default is no debugging log
-----------------*/
    FILE *f; /* IN: New log file; value -1 to get only current */
{
 FILE *o;
 o= iologfile;
 if ( f != (FILE *)( -1 ) )
  iologfile= f;
 return ( o );
}

int sk_iosave( fno, buf, len )
    /*++++++++++++++++
.PURPOSE  Save in a buffer the provided data
.RETURNS  Number of bytes in buffer associated to fno
.REMARKS  Can't save in existing buffer
-----------------*/
    int fno; /* IN: File Descriptor 	*/
char *buf;   /* IN: Data to save    	*/
int len;     /* IN: Length of data 	*/
{
 BUF *b;
 if ( len <= 0 )
  return ( 0 );
 if ( fno >= NSOCKS ) {
  err3( "sk_iosave", fno, len );
  return ( -1 );
 }
 if ( iologfile )
  log_b( "sk_iosave", buf, len );
 if ( ( b= inputs[fno] ) ) { /* Buffer already exists.	*/
  if ( b->offset < len )
   err3(
       "sk_iosave/existing buffer with too small offset", fno, len );
  else
   b->offset-= len, memcpy( b->buf + b->offset, buf, len );
 } else { /* New buffer			*/
  inputs[fno]= b= (BUF *)malloc( len + sizeof( BUF ) );
  b->offset= 0;
  b->size= len;
  b->buf= (char *)( b + 1 );
  memcpy( b->buf, buf, len );
 }
 return ( b->size - b->offset );
}

int sk_read( fno, buf, len )
    /*++++++++++++++++
.PURPOSE  Read up to a specified number of bytes on a socket.
.RETURNS  Number of bytes read
.REMARKS  No attempt to fill the buffer.
-----------------*/
    int fno; /* IN: File Descriptor */
char *buf;   /* OUT: Buffer filled  */
int len;     /* IN: Max len to read */
{
 int i;
 if ( inputs[fno] )
  i= bread( fno, buf, len );
 else
  i= read( fno, buf, len );
 if ( i < 0 )
  err3( "sk_read", fno, len );
 if ( iologfile )
  log_b( "sk_read", buf, i );
 return ( i );
}

int sk_get( fno, buf, len )
    /*++++++++++++++++
.PURPOSE  Read the specified number of bytes on a socket.
.RETURNS  Number of bytes read. Is normally equal to len.
-----------------*/
    int fno; /* IN: File Descriptor */
char *buf;   /* OUT: Buffer filled  */
int len;     /* IN: Max len to read */
{
 char *p, *pe;
 int i;

 for ( p= buf, pe= p + len; p < pe; p+= i ) {
  if ( inputs[fno] )
   i= bread( fno, p, pe - p );
  else
   i= read( fno, p, pe - p );
  if ( i < 0 )
   err3( "sk_get", fno, len );
  if ( i <= 0 )
   break;
 }
 if ( iologfile )
  log_b( "sk_get", buf, p - buf );
 return ( p - buf );
}

int sk_gets( fno, buf, len )
    /*++++++++++++++++
.PURPOSE  Read a line (terminated by a newline) on a socket
.RETURNS  Number of bytes read, including the \n. 
.REMARKS  No NUL character appended.
-----------------*/
    int fno; /* IN: File Descriptor */
char *buf;   /* OUT: Buffer filled  */
int len;     /* IN: Max len to read */
{
 char *p, *n, *pe;
 int i;

 for ( p= n= buf, pe= p + len; p < pe; ) {
  if ( inputs[fno] )
   i= bread( fno, p, pe - p );
  else
   i= read( fno, p, pe - p );
  if ( i < 0 )
   err3( "sk_gets", fno, len );
  if ( i <= 0 )
   break; /* End of File */
  for ( n= p + i; ( p < n ) && ( *p != '\n' ); p++ )
   ;
  if ( ( p < n ) && ( *p == '\n' ) ) {
   p++;
   break;
  }
 }
 if ( p < n )
  sk_iosave( fno, p, n - p ); /* I read too much ... */
 if ( iologfile )
  log_b( "sk_gets", buf, p - buf );
 return ( p - buf );
}

int sk_getl( fno )
    /*++++++++++++++++
.PURPOSE  Read a 32-bit integer on a socket
.RETURNS  What's read; -1 when error
-----------------*/
    int fno; /* IN: opened socket */
{
 int stat;
 if ( sk_get( fno, &stat, sizeof( stat ) ) < 0 )
  return ( -1 );
 if ( iologfile )
  log_l( "sk_getl", ntohl( stat ) );
 return ( ntohl( stat ) );
}

/*============================================================================*/

int sk_write( fno, buf, len )
    /*++++++++++++++++
.PURPOSE  Write a specified number of bytes on a socket.
.RETURNS  Number of bytes written, normally identical to len
.REMARKS  Several trials if necessary
-----------------*/
    int fno; /* IN: File Descriptor */
char *buf;   /* IN: Buffer to send  */
int len;     /* IN: Max len to read */
{
 char *p, *pe;
 int i, b;

 for ( p= buf, pe= p + len; p < pe; p+= i ) {
  b= pe - p;
  if ( sksize && ( b > sksize ) )
   b= sksize;
  i= write( fno, p, b );
  if ( i <= 0 ) {
   if ( i < 0 )
    err3( "sk_write", fno, len );
   break;
  }
 }
 if ( iologfile )
  log_b( "sk_write", buf, p - buf );
 return ( p - buf );
}

int sk_put( fno, buf )
    /*++++++++++++++++
.PURPOSE  Write a text terminated by a NUL character
.RETURNS  Number of bytes written
.REMARKS  Several trials if necessary
-----------------*/
    int fno; /* IN: File Descriptor */
char *buf;   /* IN: Buffer to send  */
{
 return ( sk_write( fno, buf, strlen( buf ) ) );
}

int sk_puts( fno, buf )
    /*++++++++++++++++
.PURPOSE  Write a line (followed by a \n)
.RETURNS  Number of bytes written
.REMARKS  Several trials if necessary
-----------------*/
    int fno; /* IN: File Descriptor */
char *buf;   /* IN: Buffer to send  */
{
 char *p;
 int i;

 p= buf + strlen( buf );
 *p= '\n';
 i= sk_write( fno, buf, 1 + ( p - buf ) );
 *p= 0;
 return ( i );
}

int sk_putl( fno, val )
    /*++++++++++++++++
.PURPOSE  Write a 32-bit integer on a socket
.RETURNS  Number of bytes written
-----------------*/
    int fno; /* IN: opened socket */
int val;     /* IN: Value to write */
{
 int nval;
 int stat;

 if ( iologfile )
  log_l( "sk_putl", val );
 nval= htonl( val );
 stat= sk_write( fno, &nval, sizeof( nval ) );
 return ( stat != 4 ? -1 : stat );
}

int sk_close( fno )
    /*++++++++++++++++
.PURPOSE  Close the opened socket
.RETURNS  -1 = error
-----------------*/
    int fno; /* IN: socket to close */
{
 int stat;
 stat= close( fno );
 if ( stat < 0 )
  err3( "sk_close", fno, 0 );
 if ( iologfile )
  log_l( "sk_close", fno );
 return ( stat );
}
