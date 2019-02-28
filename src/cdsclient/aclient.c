/*++++++++++++++
 Copyright:    (C) 2008-2017 UDS/CNRS
 License:       GNU General Public License
.IDENTIFICATION aclient.c
.LANGUAGE       C
.AUTHOR         Francois Ochsenbein [CDS]
.ENVIRONMENT
.KEYWORDS
.VERSION  1.0   23-Jul-1992
.VERSION  1.1   12-Nov-1992: Added parameters -b -p
.VERSION  2.0   10-May-1993: File Redirection, parameters -U -P
.VERSION  2.1   18-Aug-1993: Possible Interruption.
.VERSION  2.2   25-Sep-1993: Allow pipes as intput/output
.VERSION  2.3   06-Feb-2003: Accept commands from stdin
.VERSION  2.4   12-avr-2003: Add a timeout (default 60sec) for the connection.
.VERSION  2.5   09-Jun-2004: Use the getpass function by default.
.VERSION  2.6   10-Mar-2006: -version option
.VERSION  2.7   06-Mar-2010: -% option; readline
.COMMENTS       Dialogue with a server, using the ^D / ^B / ^F Conventions.
		(see "sk" man pages)
---------------*/

#define VERSION "2.7"

#include <sk.h>
#include <ctype.h>
#include <string.h>
#include <strings.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>
#include <signal.h>    /* INTR is sent to Server */
#include <setjmp.h>    /* To exit from Interrupt */
#include <stdlib.h>    /* malloc */
#include <sys/types.h> /* malloc */
#include <sys/stat.h>  /* malloc */
#ifdef USE_TERMIO
#include <termio.h> /* The following is for TermIO */
#ifdef TCGETS
#define termio termios
#define TCget TCGETS
#define TCset TCSETSW
#else
#define TCget TCGETA
#define TCset TCSETAW
#endif
#endif

#ifndef TIME_MAX
#define TIME_MAX 60 /* max. time to connect */
#endif

#define MIN( a, b ) ( ( a ) < ( b ) ? ( a ) : ( b ) )
#define ITEMS( a ) ( sizeof( a ) / sizeof( a[0] ) )
#ifndef HAS_READLINE
#define HAS_READLINE 0
#endif
#if HAS_READLINE
#include <readline/readline.h>
#include <readline/history.h>
#define HISTORY_FILE ".aclient"
char *history_file;
#endif

static char usage[]= "\
Usage: aclient [-b bsiz] [-bsk sksiz] [-p prompt] [-%|-@] host service [cmd..]";
static char help[]= "\
 -b blksiz: size of blocks to send to Server\n\
 -bsk blks: size of socket blocks (default $SK_bsk)\n\
 -p prompt: prompt to be used in interactive mode\n\
        -%: ask to %-encode special characters in all arguments\n\
        -@: ask to @-encode special characters in all arguments\n\
      host: Name of Internet Number of service's host\n\
   service: service name or number\n\
       cmd: commands to execute on specified service (default in stdin)\n\
By default, calls to the remote service are in stdin.\n\
In the argument list, a percent (%) alone asks to code the arguments in hexa.\n\
";
/*  -Uname: Username for the Server\n\
    -Ppass: Password for the Server\n\ */
int i;
static char pgm[]= "aclient";
static int fdigest= 1;    /* File number where to write */
static int fmore= 0;      /* File number where to get   */
static int blksize= 4096; /* Standard blocksize	      */
static char *username;
static char *password;
static jmp_buf jmp_env;
static int interrupted;
static char *connect_err[]= {
    "can't connect",     /* -1 */
    "connection refused" /* -2 */
};

static char to_escape_list[]= "%@$*?&|\\!;'\"`~\\<>[]() \r\n\t\f";
static char to_escape[256];
static int escape= 0;

#define hexa2( s, c ) s[0]= c < 0xa0 ? ( c >> 4 ) | '0' : ( c >> 4 ) + ( 'a' - 10 ), \
                      s[1]= ( c & 15 ) < 10 ? ( c & 15 ) | '0' : ( c & 15 ) + ( 'a' - 10 );

/*===========================================================================*/
static char *getpasswd()
/*++++++++++++++++
.PURPOSE  Get a pawwsord at Terminal
.RETURNS  Number of characters
-----------------*/
{
#ifdef USE_TERMIO
 static char buf[20]; /* Buffer which will contain Password, limited */
 static char pass[]= "Password: ";
 struct termio tty0, tty1;
 int n;

 ioctl( 0, TCget, &tty0 );
 ioctl( 0, TCget, &tty1 );
 tty1.c_lflag&= ~ECHO;
 ioctl( 0, TCset, &tty1 ); /* Turn ECHO off */
 write( 1, pass, strlen( pass ) );
 n= read( 0, buf, sizeof( buf ) );
 ioctl( 0, TCset, &tty0 ); /* Reset to previous */
 if ( n <= 0 )
  perror( "****Get Password" ), n= 1;
 buf[--n]= 0;
 return ( buf );
#else
 char *getpass();
 return ( getpass( "Password: " ) );
#endif
}

/*===========================================================================*/

static int digest( char *buf, int len )
/*++++++++++++++++
.PURPOSE  Function to write to fdigest
.RETURNS  Number of bytes written
    (IN) buf	Buffer with data
    (IN) len	How many bytes
-----------------*/
{
 int n;
 if ( interrupted )
  return ( 0 ); /* don't write... */
 if ( len > 0 )
  n= write( fdigest, buf, len );
 else
  n= 0;
 if ( n < 0 )
  perror( "****aClient Digest" );
 return ( n );
}

static int more( char *buf, int len )
/*++++++++++++++++
.PURPOSE  Function to read blocks
.RETURNS  Number of bytes written
  (IN)  buf	Buffer to write
  (IN)  len	Bytes written out
-----------------*/
{
 int n;
 char *p, *pe;
 if ( interrupted )
  return ( 0 ); /* Emulate End of File */
 pe= buf + MIN( blksize, len );
 for ( p= buf; p < pe; p+= n ) {
  n= read( fmore, p, pe - p );
  if ( n < 0 )
   perror( "****aClient / More" );
  if ( n <= 0 )
   break;
 }
 return ( p - buf );
}

static int my_copy( char *buf, char *eob, char *text, int escape )
/*++++++++++++++++
.PURPOSE  Copy to buf the text specified, escaping it if necessary
.RETURNS  0 = OK, 1 = error
 (OUT) buf;	Buffer (destination)
  (IN) eob;	end of buffer
  (IN) text;	text to escape & copy
-----------------*/
{
 char *b= buf;
 char *t= text;
 if ( escape ) {
  int c;
  while ( *t && ( b < eob ) ) {
   if ( ( *t ) & 0x80 )
    *( b++ )= *( t++ );
   else if ( to_escape[(int)( *t )] ) {
    if ( ( b + 3 ) >= eob ) {
     b+= 3;
     break;
    }
    *( b++ )= '%';
    c= ( *t ) & 0xff;
    hexa2( b, c );
    b+= 2;
    t++;
   } else
    *( b++ )= *( t++ );
  }
  *b= 0;
 } else
  while ( *t && ( b < eob ) )
   *( b++ )= *( t++ );
 if ( *t )
  *eob= 0;
 else
  *b= 0;
 return ( *t );
}

static char *escape_args( char *buf, int skip_cmd )
/*++++++++++++++++
.PURPOSE  Apply the %-escaping:
	skip_cmd is 1 if buffer contains the command
.RETURNS  Newly allocated string, or buf (no escape)
-----------------*/
{
 char *b= buf;
 char *p, *abuf;
 int n= 0, brace= 0;
 int esc= escape & ( ~3 );

 /* Skip first word = command */
 if ( skip_cmd ) {
  while ( isgraph( *b ) )
   b++;
  while ( *b == ' ' )
   b++;
  if ( !*b )
   return ( (char *)0 );
 }

 /* Is there a necessity to encode ? */
 for ( p= b; *p; p++ ) {
  if ( esc ) {
   if ( esc & 1 ) {
    if ( *p == '}' ) {
     if ( brace > 0 )
      --brace;
     if ( brace == 0 )
      esc&= ~1;
    } else if ( *p == '{' )
     brace++;
    else
     n++;
   } else if ( to_escape[(int)( *p )] )
    n++;
  } else if ( *p == '%' ) {
   if ( p[1] == '{' ) {
    brace++;
    esc|= 1;
    n++;
    p++;
   }
   if ( ( p[-1] == ' ' ) && ( p[1] == ' ' ) ) {
    esc|= 2;
    n++;
    p+= 2;
   }
  }
 }
 if ( n == 0 )
  return ( (char *)0 ); /* Nothing to escape... */

 abuf= b= malloc( strlen( buf ) + 2 * n + 1 );
 p= buf;
 esc= escape & ( ~3 );

 if ( skip_cmd ) {
  while ( isgraph( *p ) )
   *( b++ )= *( p++ ); /* Command name */
  while ( *p == ' ' )
   p++;
  *( b++ )= ' ';
  /* First argument must be set to "%", indicating %-conding */
  *( b++ )= '%';
  *( b++ )= ' ';
 }

 while ( *p ) {
  if ( esc ) {
   if ( esc & 1 ) { /* Within a %{...} expression */
    if ( *p == '}' ) {
     if ( brace > 0 )
      --brace;
     if ( brace == 0 ) {
      p++;
      esc&= ~1;
      continue;
     }
    } else if ( *p == '{' )
     brace++;
   }
   if ( to_escape[(int)( *p )] )
    ; /* Yes, must code */
   else {
    *( b++ )= *( p++ );
    continue;
   }
  } else if ( *p == '%' ) {
   if ( p[1] == '{' ) {
    brace++;
    esc|= 1;
    p+= 2;
    continue;
   }
   if ( ( p[-1] == ' ' ) && ( p[1] == ' ' ) ) {
    esc|= 2;
    p+= 2;
    continue;
   }
   *( b++ )= *( p++ );
   continue; /* Just transmit the % */
  } else {
   *( b++ )= *( p++ );
   continue;
  }

  /* In escape mode: use %-convention */
  n= *( p++ ) & 0xff;
  if ( to_escape[n] ) {
   *( b++ )= '%';
   hexa2( b, n );
   b+= 2;
  } else
   *( b++ )= n;
 }
 *b= 0;
 return ( abuf );
}

static int myopen( char *fname, int mode, int *scanned )
/*++++++++++++++++
.PURPOSE  Open a file with error report
.RETURNS  File Handle. The length used is stored on output.
  (IN) fname;	File name (only first word)
  (IN) mode;	Mode (Read/Write/Append)
  (IN) scanned;	How many bytes have been scanned
-----------------*/
{
 char *p, *pname, x, quote;
 int fh;
 static char *popmode[2]= {"r", "w"};
 FILE *popfile;

 pname= fname;
 quote= *pname;
 if ( ( quote == '\'' ) || ( quote == '"' ) ) { /* Quoted filename */
  for ( p= ++pname; *p && ( *p != quote ); p++ )
   ;
 } else {
  quote= ' ';
  for ( p= pname; isgraph( *p ); p++ )
   ;
 }
 if ( *pname == '|' ) { /* We've to open a PIPE */
  popfile= (FILE *)1;
  while ( *++pname == ' ' )
   ;
 } else
  popfile= (FILE *)0;
 x= *p;
 *p= 0;

 if ( popfile ) {
  popfile= popen( pname, popmode[mode & 1] );
  if ( popfile )
   fh= fileno( popfile );
  else
   fh= -1;
 } else
  fh= open( pname, mode );
 *p= x;
 *scanned= p - fname;
 if ( x == quote )
  *scanned+= 1;
 if ( fh < 0 ) {
  perror( fname );
  exit( 1 );
 }
 return ( fh );
}

static int theplug; /* For communication by signals */
/*===========================================================================*/
static void onIntr( int s /*sig.num*/ )
/*++++++++++++++++
.PURPOSE  Activated when INTR
.RETURNS  --
-----------------*/
{
#ifdef DEBUG
 printf( "+++ onIntr called, signal %d, theplug=%d\n", s, theplug );
#endif
 signal( s, onIntr );
 sk_kill( theplug, 0 );
 interrupted= 1;
 /* longjmp(jmp_env, 1); */
}

static void tooLong( int s /*sig.num*/ )
/*++++++++++++++++
.PURPOSE  Activated when timeout away
.RETURNS  --
-----------------*/
{
 static int ncalls= 0;
 ncalls++;
#ifdef DEBUG
 printf( "+++ tooLong#%d called, signal %d, theplug=%d\n",
         ncalls, s, theplug );
#endif
 fprintf( stderr, "****aclient: too long to connect (TIME_MAX=%d)\n",
          TIME_MAX );
 exit( 1 );
}

/*===========================================================================*/
int main( int argc, char **argv ) {
 int plug; /* socket to "plug" into the socket */
 char buf[BUFSIZ], *p, *b, *eob, *host, *service, *parm, *prompt, *abuf;
 int i, tty, exec_0, blk, fop, got_command, scanned;
 char *tofree= 0;
 char bs;

 prompt= host= service= (char *)0;
 /* sk_setlog(NULL); */

 /* Define umask for file creation */
 umask( 022 );

 /* List of characters to escape */
 for ( i= 0; to_escape_list[i]; i++ )
  to_escape[(int)to_escape_list[i]]= 1;
 eob= buf + sizeof( buf ) - 1;

 /* SK_bsk env. variable may tell the Physical Blocksize */
 if ( ( p= getenv( "SK_bsk" ) ) ) {
  i= atoi( p );
  while ( isdigit( *p ) )
   p++;
  if ( tolower( *p ) == 'K' )
   i*= 2;
  sk_setb( i );
 }

 /* Examine Arguments */
 while ( --argc > 0 ) {
  parm= *++argv;
  /* fprintf(stderr, "... Examine %s\n", parm); */
  if ( *parm == '-' )
   switch ( *++parm ) {
   case 'b':     /* Blocksize */
    bs= parm[1]; /* bs = 's' for Socket Blksize */
    parm= *++argv;
    --argc;
    for ( p= parm; isdigit( *p ); p++ )
     ; /* Terminates by k or b */
    blk= atoi( parm );
    switch ( *p ) {
    case 'k':
    case 'K':
     blk*= 1024;
     break;
    case 'b':
    case 'B':
     blk*= 512;
     break;
    case '\0':
     break;
    default:
     blk= 0;
     break;
    }
    if ( blk <= 0 ) {
     printf( "*** %s: Bad b (blocksize) parameter: %s\n", pgm, parm );
     exit( __LINE__ );
    }
    if ( bs == 's' )
     sk_setb( blk );
    else
     blksize= blk;
    continue;
   case 'p': /* Prompt    */
    prompt= *++argv;
    --argc;
    continue;
   case 'h':
    printf( "%s\n%s", usage, help );
    exit( 0 );
   case 'U': /* UserName */
    username= parm + 1;
    continue;
   case 'P': /* Password */
    password= parm + 1;
    *parm= 0; /* Hide it  */
    continue;
   case '%': /* Encode special characters */
    escape= 0x10;
    continue;
   case 'v':
    if ( strncmp( parm, "ver", 3 ) == 0 ) {
     printf( "aclient (CDS) Version %s\n", VERSION );
     exit( 0 );
    }
    goto bad_option;
   default:
    if ( host && service )
     break;
   bad_option:
    printf( "****%s: which option is -%s ? ", pgm, parm );
    printf( "%s\n", usage );
    exit( __LINE__ );
   }
  if ( strcmp( parm, "%" ) == 0 )
   escape= 0x10;
  else if ( !host )
   host= parm;
  else if ( !service )
   service= parm;
  else {
   --argv;
   ++argc;
   break;
  } /* We've now commands */
 }

 /* Be sure the connection does not wait for ever ! */
 signal( SIGALRM, tooLong );
 alarm( TIME_MAX );

 /* Check the information */
 if ( ( !host ) || ( !service ) ) {
  printf( usage, pgm );
  exit( __LINE__ );
 }
 if ( !prompt ) {
  prompt= malloc( strlen( host ) + strlen( service ) + 5 );
  strcpy( prompt, host );
  strcat( prompt, "/" );
  strcat( prompt, service );
  strcat( prompt, "> " );
 }

 if ( username ) { /* Prompt for a Password if necessary */
  if ( !password && isatty( 0 ) )
   password= getpasswd();
  plug= sk_connect( host, service, username, password );
 } else
  plug= sk_open( host, service );
 if ( plug < 0 ) {
  printf( "****Returned code = %d", plug );
  /*	printf("   (Returned code = %d", plug);*/
  plug= -1 - plug;
  if ( plug < ITEMS( connect_err ) )
   printf( ": %s", connect_err[plug] );
  printf( "\n" );
  /*	printf(")\n");*/
  exit( __LINE__ );
 }
 theplug= plug;
 alarm( 0 ); /* Stop the alarm */

 /* Take command from argument line */
 exec_0= argc <= 1; /* Indicator to get commands from stdin */
 tty= isatty( 0 );

 /* If no command found in Argument line, get one now */
GetCommand:
 signal( SIGINT, onIntr );
 setjmp( jmp_env );
 interrupted= 0;
 if ( tofree ) {
  free( tofree );
  tofree= (char *)0;
 }
 abuf= b= buf;  /* buf[0] = '\04';	-- END indicator */
 escape&= 0x10; /* Keep escape only when specified as arg. */

 if ( exec_0 ) { /* ==== Input from stdin   */
  if ( tty ) {
#if HAS_READLINE
   if ( !history_file ) { /* Use the history */
    using_history();
    stifle_history( 1000 );
    p= getenv( "HOME" );
    i= p ? strlen( p ) + 1 : 0;
    history_file= malloc( i + 1 + sizeof( HISTORY_FILE ) );
    if ( p ) {
     strcpy( history_file, p );
     strcat( history_file, "/" );
    } else
     *history_file= 0;
    strcat( history_file, HISTORY_FILE );
    if ( read_history( history_file ) ) /* error, ~/.aclient not here */
     write_history( history_file );
   }
   abuf= tofree= readline( prompt );
#else
   printf( "%s", prompt );
   abuf= fgets( buf, sizeof( buf ), stdin );
   /*if (!fgets(buf, sizeof(buf), stdin)) buf[0] = '\04'; */
#endif
  } else
   abuf= fgets( buf, sizeof( buf ), stdin );
  if ( !abuf ) {
   fop= 0;
   goto Final;
  }
#if HAS_READLINE
  add_history( abuf );
#endif
  /* Remove the newlines */
  for ( p= abuf + strlen( abuf ) - 1; ( p >= abuf ) && iscntrl( *p ); p-- )
   *p= 0;

  /* Redirections at beginning of command, or comments */
  b= abuf;
  fdigest= 1;
  fmore= 0;
  for ( got_command= 0; !got_command; ) {
   while ( isspace( *b ) )
    b++;
   switch ( *b ) {
   /*case '\04': exit(0); */
   case '<': /* Input from a file */
    b++;
    while ( isspace( *b ) )
     b++;
    fmore= myopen( b, 0, &scanned );
    b+= scanned;
    continue;
   case '>': /* Output Redirection */
    fop= 1;  /* Write  */
    if ( *++b == '>' ) {
     fop= 2; /* Append */
     b++;
    }
    while ( isspace( *b ) )
     b++;
    fdigest= myopen( b, fop | O_CREAT, &scanned );
    b+= scanned;
    continue;
   case '#': /* Comment */
    puts( b );
    goto GetCommand;
   default:
    got_command= 1;
   }
  }

  /* Encode the argument is asked */
  if ( ( p= escape_args( b, 1 ) ) ) { /* option 1 ==> b contains command */
   if ( tofree )
    free( tofree );
   tofree= b= p;
  }
 } else if ( argc > 1 )
  for ( p= buf, fop= 0; --argc > 0; p+= strlen( p ) ) {
   parm= *++argv;
   if ( escape )
    ;
   else if ( strcmp( parm, ";" ) == 0 ) {
    *p= 0;
    break;
   }
   if ( p == buf ) { /* 1st word = command to execute */
    my_copy( p, eob, parm, 0 );
    p+= strlen( p );
    if ( escape )
     my_copy( p, eob, " %", 0 );
    else
     my_copy( p, eob, "  ", 0 );
   } else {
    *( p++ )= ' ';
    if ( ( b= escape_args( parm, 0 ) ) ) {
     my_copy( p, eob, b, 0 );
     free( b );
     fop++;
    } else {
     my_copy( p, eob, parm, escape );
     if ( ( escape == 0 ) && ( strcmp( parm, "%" ) == 0 ) )
      escape|= 0x10;
    }
   }
   /* There are escaped sequences. Install the "%" which indices this 
	 * (several blanks were inserted after 1st argument)
	 */
   if ( fop && ( escape == 0 ) ) {
    for ( p= buf; isgraph( *p ); p++ )
     ;
    if ( *p == ' ' )
     p++;
    if ( *p == ' ' )
     *p= '%';
   }
   b= abuf= buf;
  }
 else
  abuf= (char *)0;

 if ( !abuf ) { /* EOF found */
  fop= 0;
  goto Final;
 }

#ifdef DEBUG
 printf( ".... sk_puts(%d, \"%s\")\n", plug, b );
#endif
 if ( sk_puts( plug, b ) < 0 ) {
  fop= __LINE__;
  goto Final;
 }
 /* fprintf(stderr, ".... Execute <%s>\n", buf); */

 if ( sk_obeyserver( plug, digest, more ) < 0 ) {
  fop= 1;
  goto Final;
 }
 if ( fdigest > 2 )
  close( fdigest );
 if ( fmore > 2 )
  close( fmore );

 /* Loop to next command */
 goto GetCommand;

Final:
#if HAS_READLINE
 if ( history_file )
  write_history( history_file );
#endif
 exit( fop );
}
