/*

 The function described in this file will try to determine the number of CPU cores 
 on the local machine by parsing /proc/cpuinfo file (on Linux) 
 or running 'sysctl -n hw.ncpu' (on BSD-like systems).

 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "vast_limits.h" // for N_FORK which is defined in vast_limits.h

int get_number_of_cpu_cores() {
 char string[1024];           // string in the /proc/cpuinfo file
 int n_cores= DEFAULT_N_FORK; // default number of cores
 int i;                       // a counter
 FILE *proc_cpuinfo_file;

 // If the environment variable OMP_NUM_THREADS is set,
 // return the number of CPU cores as set in OMP_NUM_THREADS
 //
 // If OMP_NUM_THREADS is not set, getenv() will return NULL
 if ( NULL != getenv( "OMP_NUM_THREADS" ) ) {
  strncpy( string, getenv( "OMP_NUM_THREADS" ), 1024 );
  string[1024 - 1]= '\0';
  n_cores= atoi( string );
  // Check it it is a reasonable value
  // OK 4096 is a wild guess of the higest possible number of CPU cores
  if ( n_cores > 0 && n_cores < 4096 ) {
   return n_cores;
  } else {
   fprintf( stderr, "WARNING: the nummber of thread set in OMP_NUM_THREADS seems to be out of the reasnoable range: OMP_NUM_THREADS = %s (interpreted as %d)\nIgnoring this strange value...\n", string, n_cores );
  }
 } // if( NULL!=getenv("OMP_NUM_THREADS") ){

 if ( N_FORK < 0 ) {
  fprintf( stderr, "WARNING: incorrect value of N_FORK is set at compile time!\n Please edit src/vast_limits.h and recompile!\n" );
  n_cores= DEFAULT_N_FORK;
 } else {
  if ( N_FORK != 0 ) {
   // The number of threads is set by user at compile time - don't change it!
   return N_FORK;
  }
 } // if( N_FORK<0 ){

 proc_cpuinfo_file= fopen( "/proc/cpuinfo", "r" );
 if ( NULL == proc_cpuinfo_file ) {
  fprintf( stderr, "WARNING: cannot open /proc/cpuinfo !\n" );
  // Maybe this is not linux but FreeBSD or MacOS X?
  if ( 0 == system( "sysctl -n hw.ncpu > cpuinfo.txt" ) ) {
   proc_cpuinfo_file= fopen( "cpuinfo.txt", "r" );
  } else {
   proc_cpuinfo_file= NULL; // signal that sysctl thing did not work
  }
  if ( NULL != proc_cpuinfo_file ) {
   if ( 1 == fscanf( proc_cpuinfo_file, "%d", &n_cores ) ) {
    fprintf( stderr, "Ah, this is a BSD-style system with %d CPU cores.\n", n_cores );
    fclose( proc_cpuinfo_file );
    return n_cores;
   }
   fclose( proc_cpuinfo_file );
   n_cores= DEFAULT_N_FORK; // we could not parse the output of "sysctl -a | grep hw.ncpu" if we reach this point, so resort to the default value...
  }
  // end of BSD test
  fprintf( stderr, "The number of CPU cores is set to the default value of %d.\nThis default value is defined in src/vast_limits.h\n", n_cores );
  return n_cores;
 }
 n_cores= 0;
 // for each string in /proc/cpuinfo ...
 while ( NULL != fgets( string, 1024, proc_cpuinfo_file ) ) {
  // cut the first word out of the string
  for ( i= 0; i < (int)strlen( string ); i++ )
   if ( string[i] == ':' ) {
    string[i]= '\0';
    break;
   }
  // test if this the right key
  if ( 0 == strcmp( string, "processor\t" ) )
   n_cores++;
 }
 fclose( proc_cpuinfo_file );
 if ( n_cores == 0 ) {
  n_cores= DEFAULT_N_FORK;
  fprintf( stderr, "WARNING: cannot parse /proc/cpuinfo !\nThe number of CPU cores is set to the default value of %d.\nThis default value is defined in src/vast_limits.h\n", n_cores );
  return n_cores;
 }
 fprintf( stderr, "The number of processor cores determined from /proc/cpuinfo is %d.\n", n_cores );
 return n_cores;
}
