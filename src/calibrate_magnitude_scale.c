#include <stdio.h>
#include <math.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#include "vast_limits.h"
#include "photocurve.h"
#include "lightcurve_io.h"

int main( int argc, char **argv ) {
 DIR *dp;
 struct dirent *ep;

 /* Mag conversion */
 double a, b, c;
 a= b= c= 0.0;
 FILE *lightcurvefile;
 FILE *outlightcurvefile;
 double jd, mag, merr, x, y, app, newmag;
 char string[FILENAME_LENGTH];
 char comments_string[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];

 double maxmag, minmag, newmerr;

 int operation_mode= 0; // 0 - polynome (or straight line) , 4 and 5 - special "photocurve" mode

 double a_[4]; // for parameters of "photocurve"

 int emergency_stop;

 if ( argc != 4 && argc != 6 ) {
  fprintf( stderr, "Magnitude converter\n" );
  fprintf( stderr, "Usage:\n" );
  fprintf( stderr, "util/calibrate_magnitude_scale A B C\n" );
  fprintf( stderr, " magnitude will be calibrated using relation Mout=A*Min*Min+B*Min+C\n" );
  fprintf( stderr, "\n" );
  fprintf( stderr, "There is also an alternative operation mode for use with lib/fit_mag_calib\n" );
  exit( 1 );
 }

 if ( argc == 4 ) {
  operation_mode= 0; // just in case
  a= atof( argv[1] );
  b= atof( argv[2] );
  c= atof( argv[3] );
  fprintf( stderr, "a=%lf b=%lf c=%lf\n", a, b, c );

#ifdef VAST_USE_BUILTIN_FUNCTIONS
// Make a proper check the input values if isnormal() is defined
#if defined _ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L
// We use __builtin_isnormal() as we know it is working if VAST_USE_BUILTIN_FUNCTIONS is defined
// Othervise even with the '_ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L' check
// isnormal() doesn't work on Ubuntu 14.04 trusty (vast.sai.msu.ru)
// BEWARE 0.0 is also not considered normal by isnormal() !!!
  if ( 0 == __builtin_isnormal( ( a ) ) && a != 0.0 ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
  if ( 0 == __builtin_isnormal( ( b ) ) && b != 0.0 ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
  if ( 0 == __builtin_isnormal( ( c ) ) && c != 0.0 ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
#endif
#else
  // a simplified check using isnan
  if ( 0 != isnan( ( a ) ) ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
  if ( 0 != isnan( ( b ) ) ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
  if ( 0 != isnan( ( c ) ) ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
#endif

 }

 if ( argc == 6 ) {
  operation_mode= atoi( argv[1] );
  a_[0]= atof( argv[2] );
  a_[1]= atof( argv[3] );
  a_[2]= atof( argv[4] );
  a_[3]= atof( argv[5] );
  fprintf( stderr, "Using the 'photocurve' calibration with the parameters a_[0]=%lg a_[1]=%lg a_[2]=%lg a_[3]=%lg\n", a_[0], a_[1], a_[2], a_[3] );

#ifdef VAST_USE_BUILTIN_FUNCTIONS
// Make a proper check the input values if isnormal() is defined
#if defined _ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L
// We use __builtin_isnormal() as we know it is working if VAST_USE_BUILTIN_FUNCTIONS is defined
// Othervise even with the '_ISOC99_SOURCE || _POSIX_C_SOURCE >= 200112L' check
// isnormal() doesn't work on Ubuntu 14.04 trusty (vast.sai.msu.ru)
// BEWARE 0.0 is also not considered normal by isnormal() !!!
  if ( 0 == __builtin_isnormal( ( a_[0] ) ) && a_[0] != 0.0 ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
  if ( 0 == __builtin_isnormal( ( a_[1] ) ) && a_[1] != 0.0 ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
  if ( 0 == __builtin_isnormal( ( a_[2] ) ) && a_[2] != 0.0 ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
  if ( 0 == __builtin_isnormal( ( a_[3] ) ) && a_[3] != 0.0 ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
#endif
#else
  // a simplified check using isnan
  if ( 0 != isnan( (  a_[0] ) ) ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
  if ( 0 != isnan( (  a_[1] ) ) ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
  if ( 0 != isnan( (  a_[2] ) ) ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
  if ( 0 != isnan( (  a_[3] ) ) ) {
   fprintf( stderr, "The coefficient value is out of range!\n");
   return 1;
  }
#endif

 }

 // internal check
 if ( operation_mode != 0 && operation_mode != 4 && operation_mode != 5 ) {
  fprintf( stderr, "ERROR in calibrate_magnitude_scale: incorrect operation_mode=%d\nAborting!\n", operation_mode );
  return 1;
 }

 dp= opendir( "./" );
 if ( dp != NULL ) {
  fprintf( stderr, "Working...\nPlease, PLEASE, be patient!!!\n" );
  while ( ( ep= readdir( dp ) ) != NULL ) {
   if ( strlen( ep->d_name ) < 8 )
    continue; // make sure the filename is not too short for the following tests
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {
    emergency_stop= 0; // reset the emergency stop flag
    //puts (ep->d_name);
    lightcurvefile= fopen( ep->d_name, "r" );
    if ( NULL == lightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file %s\n", ep->d_name );
     exit( 1 );
    }
    outlightcurvefile= fopen( "lightcurve.tmp", "w" );
    if ( NULL == outlightcurvefile ) {
     fprintf( stderr, "ERROR: Can't open file lightcurve.tmp\n" );
     exit( 1 );
    }
    while ( -1 < read_lightcurve_point( lightcurvefile, &jd, &mag, &merr, &x, &y, &app, string, comments_string ) ) {
     if ( jd == 0.0 ) {
      continue; // if this line could not be parsed, try the next one
     }

     newmag= maxmag= minmag= 0.0; // reset

     if ( operation_mode == 0 ) {
      newmag= a * mag * mag + b * mag + c;
      maxmag= a * ( mag + merr ) * ( mag + merr ) + b * ( mag + merr ) + c;
      minmag= a * ( mag - merr ) * ( mag - merr ) + b * ( mag - merr ) + c;
     }
     if ( operation_mode == 4 || operation_mode == 5 ) {
      newmag= eval_photocurve( mag, a_, operation_mode );
      maxmag= eval_photocurve( mag + merr, a_, operation_mode );
      minmag= eval_photocurve( mag - merr, a_, operation_mode );
     }
     //newmerr=(maxmag-minmag)/2.0;
     if ( 0 != isnan( maxmag ) ) {
      maxmag= 0.0;
     }
     if ( 0 != isnan( minmag ) ) {
      minmag= 0.0;
     }
     newmerr= MAX( maxmag - newmag, newmag - minmag ); // fallback option
     if ( maxmag != 0.0 && minmag != 0.0 ) {
      // Normal option
      newmerr= ( ( maxmag - newmag ) + ( newmag - minmag ) ) / 2.0;
     }
     if ( newmerr > MAX_MAG_ERROR ) {
      continue; // drop measurements with very large error bars
     }
     if ( newmag > FAINTEST_STARS_ANYMAG || newmag < BRIGHTEST_STARS ) {
      fprintf( stderr, "Magnitude conversion ERROR: %lf>%lf or %lf<%lf\n", newmag, FAINTEST_STARS_ANYMAG, newmag, BRIGHTEST_STARS );
      if ( operation_mode == 0 ) {
       fprintf( stderr, "newmag=a*mag*mag+b*mag+c; %lf=%lf*%lf*%lf+%lf*%lf+%lf;\n\n", newmag, a, mag, mag, b, mag, c );
      }
      emergency_stop= 1;
      break;
      // In some strange circumstances on BSD systems it seems the same lightcurve file may be
      // opened multiple times triggering the above magnitude conversion error.
      // Try to circument it by just going to the next file [I know this is not really a solution]
     }
     write_lightcurve_point( outlightcurvefile, jd, newmag, newmerr, x, y, app, string, comments_string );
    }
    fclose( outlightcurvefile );
    fclose( lightcurvefile );
    if ( emergency_stop != 0 ) {
     rename( "lightcurve.tmp", "lightcurve.tmp_emergency_stop_debug" );
     continue;
    }
    // do this only if there was no emergency stop
    unlink( ep->d_name );                   /* delete old lightcurve file */
    rename( "lightcurve.tmp", ep->d_name ); /* move lightcurve.tmp to lightcurve file */
   }
  }
  (void)closedir( dp );
 } else {
  perror( "Couldn't open the directory" );
  return -1;
 }

 fprintf( stderr, "All lightcurves processed!  =)\n" );

 return 0;
}
