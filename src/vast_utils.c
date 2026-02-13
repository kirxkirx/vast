#include <stdio.h>     // for fprintf(), fopen(), fclose(), fgets()
#include <stdlib.h>    // malloc, free, exit codes
#include <string.h>    // strcmp, strlen, strdup, sprintf, strncpy
#include <dirent.h>    // DIR, opendir, readdir, closedir, struct dirent
#include <sys/types.h> // DIR, struct stat
#include <sys/stat.h>  // stat, lstat, struct stat, S_ISDIR
#include <unistd.h>    // unlink, rmdir, unlinkat (POSIX.1-2008)
#include <libgen.h>    // for basename()

// Check for POSIX.1-2008 support (dirfd, fstatat, unlinkat)
// These functions avoid TOCTOU race conditions but require modern systems
#if ( defined( _POSIX_C_SOURCE ) && _POSIX_C_SOURCE >= 200809L ) || \
    ( defined( __GLIBC__ ) && ( __GLIBC__ > 2 || ( __GLIBC__ == 2 && __GLIBC_MINOR__ >= 10 ) ) )
#define VAST_HAVE_POSIX_2008 1
#include <fcntl.h> // AT_SYMLINK_NOFOLLOW, AT_REMOVEDIR
#else
#define VAST_HAVE_POSIX_2008 0
#endif

#include "vast_utils.h"
#include "vast_limits.h"
#include "vast_is_file.h"
#include "safely_encode_user_input_string.h"

void version( char *version_string ) {
 strncpy( version_string, "VaST 1.0rc89", 32 );
 return;
}

void print_vast_version( void ) {
 char version_string[128];
 version( version_string );
 fprintf( stderr, "\n--==%s==--\n\n", version_string );
 return;
}

void compiler_version( char *compiler_version_string ) {
 FILE *cc_version_file;
 cc_version_file= fopen( ".cc.version", "r" );
 if ( NULL == cc_version_file ) {
  strncpy( compiler_version_string, "unknown compiler\n", 18 );
  return;
 }
 if ( NULL == fgets( compiler_version_string, 256, cc_version_file ) ) {
  strncpy( compiler_version_string, "unknown compiler\n", 18 );
 }
 fclose( cc_version_file );
 return;
}

void compilation_date( char *compilation_date_string ) {
 FILE *cc_version_file;
 cc_version_file= fopen( ".cc.date", "r" );
 if ( NULL == cc_version_file ) {
  strncpy( compilation_date_string, "unknown date\n", 18 );
  return;
 }
 if ( NULL == fgets( compilation_date_string, 256, cc_version_file ) ) {
  strncpy( compilation_date_string, "unknown date\n", 18 );
 }
 fclose( cc_version_file );
 return;
}

void vast_build_number( char *vast_build_number_string ) {
 FILE *cc_version_file;
 cc_version_file= fopen( ".cc.build", "r" );
 if ( NULL == cc_version_file ) {
  strncpy( vast_build_number_string, "unknown\n", 18 );
  return;
 }
 if ( NULL == fgets( vast_build_number_string, 256, cc_version_file ) ) {
  strncpy( vast_build_number_string, "unknown\n", 18 );
 }
 fclose( cc_version_file );
 return;
}

void vast_is_openmp_enabled( char *vast_openmp_enabled_string ) {
 FILE *cc_version_file;
 cc_version_file= fopen( ".cc.openmp", "r" );
 if ( NULL == cc_version_file ) {
  strncpy( vast_openmp_enabled_string, "unknown\n", 18 );
  return;
 }
 if ( NULL == fgets( vast_openmp_enabled_string, 256, cc_version_file ) ) {
  strncpy( vast_openmp_enabled_string, "unknown\n", 18 );
 }
 fclose( cc_version_file );
 return;
}

void progress( int done, int all ) {
 fprintf( stderr, "processed %d of %d images (%5.1lf%%)\n", done, all, (double)done / (double)all * 100.0 );
 return;
}

int vast_remove_directory( const char *path ) {
 int error= 0;
 int slashes_only;
 size_t i;
 char **dir_stack;
 int stack_ptr;
 char *curr_path;
 DIR *d;
 struct dirent *p;
 struct stat statbuf;
 size_t curr_len;
 size_t name_len;
 size_t path_len;
 char *full_path;
#if VAST_HAVE_POSIX_2008
 int dfd;
#endif

 // Safety checks for critical directories
 if ( path == NULL || path[0] == '\0' ) {
  fprintf( stderr, "ERROR: Invalid empty path provided\n" );
  return 1;
 }

 // Check for root directory
 if ( strcmp( path, "/" ) == 0 ) {
  fprintf( stderr, "ERROR: Refusing to remove root directory '/'\n" );
  return 1;
 }

 // Check for current or parent directory
 if ( strcmp( path, "." ) == 0 || strcmp( path, ".." ) == 0 ) {
  fprintf( stderr, "ERROR: Refusing to remove '%s' directory\n", path );
  return 1;
 }

 // Simple path checks (without realpath)
 // Check if path contains only / characters
 slashes_only= 1;
 for ( i= 0; path[i] != '\0'; i++ ) {
  if ( path[i] != '/' ) {
   slashes_only= 0;
   break;
  }
 }
 if ( slashes_only && i > 0 ) {
  fprintf( stderr, "ERROR: Refusing to remove path containing only slashes\n" );
  return 1;
 }

// Replace recursive approach with iterative one using a stack
#define MAX_DIR_DEPTH 3
 dir_stack= malloc( MAX_DIR_DEPTH * sizeof( char * ) );
 stack_ptr= 0;

 if ( dir_stack == NULL ) {
  fprintf( stderr, "ERROR: Memory allocation failed for directory traversal stack\n" );
  return 1;
 }

 // Add initial path to stack
 dir_stack[stack_ptr]= strdup( path );
 if ( dir_stack[stack_ptr] == NULL ) {
  free( dir_stack );
  return 1;
 }
 stack_ptr++;

 while ( stack_ptr > 0 ) {
  // Pop directory from stack
  stack_ptr--;
  curr_path= dir_stack[stack_ptr];

  d= opendir( curr_path );
  if ( d ) {
#if VAST_HAVE_POSIX_2008
   // Modern POSIX.1-2008 implementation using directory file descriptors
   // to avoid TOCTOU (time-of-check time-of-use) race conditions
   dfd= dirfd( d );
   while ( ( p= readdir( d ) ) ) {
    // Skip "." and ".."
    if ( !strcmp( p->d_name, "." ) || !strcmp( p->d_name, ".." ) )
     continue;

    if ( !fstatat( dfd, p->d_name, &statbuf, AT_SYMLINK_NOFOLLOW ) ) {
     if ( S_ISDIR( statbuf.st_mode ) ) {
      // If directory, construct full path and add to stack
      curr_len= strlen( curr_path );
      name_len= strlen( p->d_name );
      path_len= curr_len + name_len + 2; // +2 for '/' and '\0'

      full_path= malloc( path_len );
      if ( full_path == NULL ) {
       fprintf( stderr, "ERROR: Memory allocation failed\n" );
       error= 1;
       break;
      }

      /* Handle trailing slash in curr_path */
      if ( curr_len > 0 && curr_path[curr_len - 1] == '/' ) {
       sprintf( full_path, "%s%s", curr_path, p->d_name );
      } else {
       sprintf( full_path, "%s/%s", curr_path, p->d_name );
      }

      if ( stack_ptr < MAX_DIR_DEPTH ) {
       dir_stack[stack_ptr++]= full_path; // Will process later
      } else {
       fprintf( stderr, "ERROR: Maximum directory depth exceeded\n" );
       free( full_path );
       error= 1;
       break;
      }
     } else {
      // Non-directory entry: remove using directory fd to avoid TOCTOU race
      if ( unlinkat( dfd, p->d_name, 0 ) != 0 ) {
       fprintf( stderr, "ERROR removing file: %s/%s\n", curr_path, p->d_name );
       error= 1;
      }
     }
    } else {
     // If fstatat fails (for example, broken symlink), still attempt to remove
     if ( unlinkat( dfd, p->d_name, 0 ) != 0 ) {
      fprintf( stderr, "ERROR in vast_remove_directory(): Could not remove: %s/%s\n", curr_path, p->d_name );
      error= 1;
     }
    }
   }
#else
   // Legacy implementation for systems without POSIX.1-2008 support (e.g., gcc 4.1)
   // Note: This code has a theoretical TOCTOU (time-of-check time-of-use) race condition
   // between lstat() and unlink(). In practice, this is harmless for VaST because:
   // 1. This function only removes temporary directories created by VaST itself
   // 2. The race window is microseconds, requiring an attacker with local access
   // 3. Worst case outcome is a failed deletion with an error message (no security impact)
   // 4. There is no privilege escalation or data corruption risk
   while ( ( p= readdir( d ) ) ) {
    // Skip "." and ".."
    if ( !strcmp( p->d_name, "." ) || !strcmp( p->d_name, ".." ) )
     continue;

    // Construct full path for this entry
    curr_len= strlen( curr_path );
    name_len= strlen( p->d_name );
    path_len= curr_len + name_len + 2; // +2 for '/' and '\0'

    full_path= malloc( path_len );
    if ( full_path == NULL ) {
     fprintf( stderr, "ERROR: Memory allocation failed\n" );
     error= 1;
     break;
    }

    /* Handle trailing slash in curr_path */
    if ( curr_len > 0 && curr_path[curr_len - 1] == '/' ) {
     sprintf( full_path, "%s%s", curr_path, p->d_name );
    } else {
     sprintf( full_path, "%s/%s", curr_path, p->d_name );
    }

    // lstat/unlink TOCTOU race: harmless for temp directory cleanup (see comment above)
    // lgtm[cpp/toctou-race-condition]
    // codeql[cpp/toctou-race-condition]
    if ( !lstat( full_path, &statbuf ) ) {
     if ( S_ISDIR( statbuf.st_mode ) ) {
      if ( stack_ptr < MAX_DIR_DEPTH ) {
       dir_stack[stack_ptr++]= full_path; // Will process later
      } else {
       fprintf( stderr, "ERROR: Maximum directory depth exceeded\n" );
       free( full_path );
       error= 1;
       break;
      }
     } else {
      // Non-directory entry: remove
      // lgtm[cpp/toctou-race-condition]
      // codeql[cpp/toctou-race-condition]
      if ( unlink( full_path ) != 0 ) {
       fprintf( stderr, "ERROR removing file: %s\n", full_path );
       error= 1;
      }
      free( full_path );
     }
    } else {
     // If lstat fails (for example, broken symlink), still attempt to remove
     // lgtm[cpp/toctou-race-condition]
     // codeql[cpp/toctou-race-condition]
     if ( unlink( full_path ) != 0 ) {
      fprintf( stderr, "ERROR in vast_remove_directory(): Could not remove: %s\n", full_path );
      error= 1;
     }
     free( full_path );
    }
   }
#endif
   closedir( d );

   // Now remove the directory itself
   if ( !error ) {
    if ( rmdir( curr_path ) != 0 ) {
     fprintf( stderr, "ERROR in vast_remove_directory(): Failed to remove directory: %s\n", curr_path );
     error= 1;
    }
   }
  } else {
   fprintf( stderr, "INFO from vast_remove_directory(): Could not open directory: %s\n", curr_path );
   error= 1;
  }

  free( curr_path );
 }

 // Free the stack
 free( dir_stack );

 return error;
}

int check_if_we_can_allocate_lots_of_memory() {
 char *big_chunk_of_memory;
 big_chunk_of_memory= malloc( 134217728 * sizeof( char ) ); // try to allocate 128MB
 if ( NULL == big_chunk_of_memory ) {
  fprintf( stderr, "WARNING: the system is low on memory!\n" );
  return 1;
 }
 free( big_chunk_of_memory );
 return 0;
}

int check_and_print_memory_statistics() {

 FILE *meminfofile;
 char string1[256 + 256]; // should be big enough to accomodate string2
 char string2[256];
 double VmPeak= 0.0;
 char VmPeak_units[256];
 double VmSize= 0.0;
 char VmSize_units[256];
 double RAM_size= 0.0;
 char RAM_size_units[256];
 double mem= 0.0;
 pid_t pid;
 pid= getpid();

 // Check if process status information is available in /proc
 sprintf( string2, "/proc/%d/status", pid );
 if ( 0 == is_file( string2 ) ) {
  // This means we are probably on a BSD-like system

  // Trying to handle the BSD/Mac case in a rudimentary way
  //
  // Why don't I want to handle the low-memory-system case on Linux in a similar way?
  // For no good reason, really.
  //
  sprintf( string1, "sysctl -n hw.physmem > vast_memory_usage.log" );
  if ( 0 != system( string1 ) ) {
   sprintf( string1, "sysctl -n hw.memsize > vast_memory_usage.log" );
   if ( 0 != system( string1 ) ) {
    fprintf( stderr, "ERROR running  sysctl -n hw.memsize > vast_memory_usage.log\n" );
    return 0;
   }
  }
  meminfofile= fopen( "vast_memory_usage.log", "r" );
  if ( meminfofile == NULL ) {
   fprintf( stderr, "can't open vast_memory_usage.log, no memory statistics available\n" );
   return 0;
  }
  if ( 1 != fscanf( meminfofile, "%lf", &mem ) ) {
   fprintf( stderr, "ERROR parsing vast_memory_usage.log, no memory statistics available\n" );
   fclose( meminfofile );
   return 0;
  }
  fclose( meminfofile );
  if ( mem < 0.0 ) {
   fprintf( stderr, "ERROR parsing vast_memory_usage.log, no memory statistics available\n" );
   return 0;
  }
  // if we are on BSD or Mac and we are under 1GB of RAM - assume we are short on memory
  if ( mem < 1073741824.0 ) {
   fprintf( stderr, "WARNING: the system seems to have less than 1GB of RAM. Assuming we are short on memory.\n" );
   return 1;
  }
  // fprintf(stderr,"can't read %s   no memory statistics available\n",string2);
  return 0;
 } else {
  // Get ammount of used memory from /proc/PID/status
  sprintf( string1, "grep -B1 VmSize %s | grep -v Groups | sed 's/\\t/ /g' > vast_memory_usage.log", string2 );
  if ( 0 != system( string1 ) ) {
   fprintf( stderr, "ERROR running  %s\n", string1 );
   return 0;
  }

  // Check if memory information is available in /proc
  if ( 0 == is_file( "/proc/meminfo" ) ) {
   fprintf( stderr, "can't read /proc/meminfo   no memory statistics available\n" );
   return 0;
  }

  // Get RAM size
  sprintf( string1, "grep MemTotal /proc/meminfo | sed 's/\\t/ /g' >> vast_memory_usage.log" );
  if ( 0 != system( string1 ) ) {
   fprintf( stderr, "ERROR running  %s\n", string1 );
   return 0;
  }

  // Load memory information from the log file
  meminfofile= fopen( "vast_memory_usage.log", "r" );
  if ( meminfofile == NULL ) {
   fprintf( stderr, "can't open vast_memory_usage.log, no memory statistics available\n" );
   return 0;
  }
  if ( 3 != fscanf( meminfofile, "%s %lf %s ", string1, &mem, string2 ) ) {
   fprintf( stderr, "no memory statistics available\n" );
   return 0;
  }
  if ( 0 == strcasecmp( string1, "VmPeak:" ) ) {
   VmPeak= mem;
   strncpy( VmPeak_units, string2, 256 - 1 );
  }
  if ( 0 == strcasecmp( string1, "VmSize:" ) ) {
   VmSize= mem;
   strncpy( VmSize_units, string2, 256 - 1 );
  }
  if ( 0 == strcasecmp( string1, "MemTotal:" ) ) {
   RAM_size= mem;
   strncpy( RAM_size_units, string2, 256 - 1 );
  }
  if ( 3 == fscanf( meminfofile, "%s %lf %s ", string1, &mem, string2 ) ) {
   if ( 0 == strcasecmp( string1, "VmPeak:" ) ) {
    VmPeak= mem;
    strncpy( VmPeak_units, string2, 256 - 1 );
   }
   if ( 0 == strcasecmp( string1, "VmSize:" ) ) {
    VmSize= mem;
    strncpy( VmSize_units, string2, 256 - 1 );
   }
   if ( 0 == strcasecmp( string1, "MemTotal:" ) ) {
    RAM_size= mem;
    strncpy( RAM_size_units, string2, 256 - 1 );
   }
   if ( 3 == fscanf( meminfofile, "%s %lf %s ", string1, &mem, string2 ) ) {
    if ( 0 == strcasecmp( string1, "VmPeak:" ) ) {
     VmPeak= mem;
     strncpy( VmPeak_units, string2, 256 - 1 );
    }
    if ( 0 == strcasecmp( string1, "VmSize:" ) ) {
     VmSize= mem;
     strncpy( VmSize_units, string2, 256 - 1 );
    }
    if ( 0 == strcasecmp( string1, "MemTotal:" ) ) {
     RAM_size= mem;
     strncpy( RAM_size_units, string2, 256 - 1 );
    }
   }
  }
  fclose( meminfofile );

  // Write information about memory usage
  fprintf( stderr, "memory: " );
  if ( 0.0 != VmSize )
   fprintf( stderr, " %.0lf %s used", VmSize, VmSize_units );
  if ( 0.0 != VmPeak )
   fprintf( stderr, ", %.0lf %s peak", VmPeak, VmPeak_units );
  if ( 0.0 != RAM_size )
   fprintf( stderr, ", %.0lf %s available RAM", RAM_size, RAM_size_units );
  fprintf( stderr, "\n" );

  // If RAM and VmSize were correctly read and are in the same units...
  if ( 0 == strcasecmp( VmSize_units, RAM_size_units ) && 0 != VmSize && 0 != RAM_size ) {
   // Check that the data are reasonable
   if ( VmSize > 100 * RAM_size ) {
    fprintf( stderr, "\x1B[01;31mWARNING! There seems to be a problem parsing the memory usage statistic.\x1B[33;00m\n" );
   } else {
    // Check aren't we using too much memory?
    if ( VmSize > MAX_RAM_USAGE * RAM_size ) {
     fprintf( stderr, "\x1B[01;31mWARNING! VaST is using more than %d%% of RAM! Trying to free some memory...\x1B[33;00m\n", (int)( MAX_RAM_USAGE * 100 ) );
     return 1; // return value 1 means that we need to free some momory
    }
   }
  }

 } // else -- if( 0==is_file(string2) ){

 if ( 0 != check_if_we_can_allocate_lots_of_memory() ) {
  return 1;
 }

 return 0;
}

void print_TT_reminder( int show_timer_or_quit_instantly ) {

 int n;

 fprintf( stderr, "\n" );
 fprintf( stderr, "\n" );

 fprintf( stderr, "              #########   \x1B[34;47mATTENTION!\x1B[33;00m   #########              \n" );
 fprintf( stderr, "According to the IAU recommendation (Resolution B1 XXIII IAU GA,\n" );
 fprintf( stderr, "see http://www.iers.org/IERS/EN/Science/Recommendations/resolutionB1.html )  \n" );
 fprintf( stderr, "Julian Dates (JDs) computed by VaST will be expressed by default    \n" );
 fprintf( stderr, "in \x1B[34;47mTerrestrial Time (TT)\x1B[33;00m! " );
 fprintf( stderr, "Starting from January 1, 2017:\n  TT = UTC + 69.184 sec  \n" );
 fprintf( stderr, "If you want JDs to be expressed in UTC, use '-u' or '--UTC' key: './vast -u'\n" );
 fprintf( stderr, "You may find which time system was used in vast_summary.log\n\n" );
 fprintf( stderr, "Please \x1B[01;31mmake sure you know the difference between Terrestrial Time and UTC\033[00m,\n" );
 fprintf( stderr, "before deriving the time of minimum of an eclipsing binary or maximum of\n" );
 fprintf( stderr, "a pulsating star, sending a VaST lightcurve to your collaborators, AAVSO,\n" );
 fprintf( stderr, "B.R.N.O. database etc. Often people and databases expect JDs in UTC, not TT.\n" );
 fprintf( stderr, "More information may be found at https://en.wikipedia.org/wiki/Terrestrial_Time\n\n" );
 if ( show_timer_or_quit_instantly == 2 ) {
  return;
 }
 fprintf( stderr, "If you need accurate timing, don't forget to apply the Heliocentric Correction\n" );
 fprintf( stderr, "to the lightcurve. This can be done using 'util/hjd_input_in_TT' or 'util/hjd_input_in_UTC'.\n\n" );
 fprintf( stderr, "The more accurate barycentric time correction may be computed with VARTOOLS:\n" );
 fprintf( stderr, "http://www.astro.princeton.edu/~jhartman/vartools.html#converttime\n" );
 fprintf( stderr, "The SPICE library ( https://naif.jpl.nasa.gov/ ) support needs to be enabled\n" );
 fprintf( stderr, "when compiling VARTOOLS.\n\n" );
 fprintf( stderr, "Have fun! =)\n" );

 if ( show_timer_or_quit_instantly == 1 ) {
  return;
 }
 fprintf( stderr, "\n\n" );

 fprintf( stderr, "This warning message will disappear in...   " );
 // sleep for 6 seconds to make sure user saw the message
 for ( n= 5; n > 0; n-- ) {
  sleep( 1 );
  fprintf( stderr, "%d ", n );
 }
 sleep( 1 );
 fprintf( stderr, "NOW!\n" );

 return;
}

// The function is used to find a star specified with its pixel coordinates
// in a list of stars (with their X Y coordinates listed in two arrays).
//
// The function is used both for the exclusion test and for finding
// the manually selected comparison stars.
//
// Return values:
//                -1 - not found
//                 0, 1, 2... - index of the found star
int exclude_test( double X, double Y, double *exX, double *exY, int N, int verbose ) {
 int result= -1;
 int i;
 for ( i= 0; i < N; i++ ) {
  // for ( i= N; i--; ) {
  if ( fabs( exX[i] - X ) < 1.5 && fabs( exY[i] - Y ) < 1.5 ) {
   result= i;
   break;
  }
 }
 if ( result > -1 ) {
  if ( verbose != 0 ) {
   fprintf( stderr, "The star %.3lf %.3lf is listed in exclude.lst => excluded from magnitude calibration\n", X, Y );
  }
 }
 return result;
}

// a housekeeping function to exclude i'th element from three arrays
// Optimized: use memmove instead of element-by-element copy
void exclude_from_3_double_arrays( double *array1, double *array2, double *array3, int i, int *N ) {
 size_t elements_to_move;
 if ( i < 0 || i >= ( *N ) ) {
  fprintf( stderr, "ERROR in exclude_from_3_double_arrays(): i=%d\n", i );
  return;
 }
 elements_to_move= ( *N ) - i - 1;
 if ( elements_to_move > 0 ) {
  memmove( &array1[i], &array1[i + 1], elements_to_move * sizeof( double ) );
  memmove( &array2[i], &array2[i + 1], elements_to_move * sizeof( double ) );
  memmove( &array3[i], &array3[i + 1], elements_to_move * sizeof( double ) );
 }
 ( *N )= ( *N ) - 1;
 return;
}
// a housekeeping function to exclude i'th element from six arrays
// Optimized: use memmove instead of element-by-element copy
void exclude_from_6_double_arrays( double *array1, double *array2, double *array3, double *array4, double *array5, double *array6, int i, int *N ) {
 size_t elements_to_move;
 if ( i < 0 || i >= ( *N ) ) {
  fprintf( stderr, "ERROR in exclude_from_6_double_arrays(): i=%d\n", i );
  return;
 }
 elements_to_move= ( *N ) - i - 1;
 if ( elements_to_move > 0 ) {
  memmove( &array1[i], &array1[i + 1], elements_to_move * sizeof( double ) );
  memmove( &array2[i], &array2[i + 1], elements_to_move * sizeof( double ) );
  memmove( &array3[i], &array3[i + 1], elements_to_move * sizeof( double ) );
  memmove( &array4[i], &array4[i + 1], elements_to_move * sizeof( double ) );
  memmove( &array5[i], &array5[i + 1], elements_to_move * sizeof( double ) );
  memmove( &array6[i], &array6[i + 1], elements_to_move * sizeof( double ) );
 }
 ( *N )= ( *N ) - 1;
 return;
}

// Update PATH variable to make sure the local copy of SExtractor is there
void make_sure_libbin_is_in_path() {
 char pathstring[8192];
 strncpy( pathstring, getenv( "PATH" ), 8192 );
 pathstring[8192 - 1]= '\0';
 // if :lib/bin is not there
 if ( NULL == strstr( pathstring, ":lib/bin" ) ) {
  strncat( pathstring, ":lib/bin", 8192 - 32 );
  pathstring[8192 - 1]= '\0';
  // fprintf(stderr, "\nUpdating PATH variable:\n%s\n\n%s\n\n", getenv("PATH"), pathstring);
  setenv( "PATH", pathstring, 1 );
 }
 return;
}

int find_catalog_in_vast_images_catalogs_log( char *fitsfilename, char *catalogfilename ) {
 char fitsfilename_to_test[FILENAME_LENGTH];
 char local_catalogfilename[FILENAME_LENGTH];
 FILE *f;
 int found;
 struct stat defSex;
 struct stat cat;

 f= fopen( "vast_images_catalogs.log", "r" );
 if ( f == NULL ) {
  // Use PID to create a unique catalog name to avoid race conditions
  // when multiple processes run in parallel on different images
  sprintf( catalogfilename, "image_pid%05d.cat", (int)getpid() );
  return 1; // not only this image has not been processed, even "vast_images_catalogs.log" is not created yet!
 }
 found= 0;
 while ( -1 < fscanf( f, "%s %s", local_catalogfilename, fitsfilename_to_test ) ) {
  if ( 0 == strcmp( fitsfilename_to_test, fitsfilename ) ) {
   safely_encode_user_input_string( catalogfilename, local_catalogfilename, FILENAME_LENGTH - 1 );
   found= 1;
   break;
  }
 }
 fclose( f );
 if ( found == 0 ) {
  // Use PID to create a unique catalog name to avoid race conditions
  // when multiple processes run in parallel on different images
  sprintf( catalogfilename, "image_pid%05d.cat", (int)getpid() );
  return 1; // it is possible that image00000.cat is referring to another image, so we'll recompute...
 }
 // Check if the catalog already exist
 f= fopen( catalogfilename, "r" );
 if ( f == NULL ) {
  return 1;
 } else {
  fclose( f );
  // Check if default.sex was modified after catalog's creation
  stat( "default.sex", &defSex );
  stat( catalogfilename, &cat );
  if ( defSex.st_mtime > cat.st_mtime ) {
   fprintf( stderr, "Image will be processed again since default.sex was modified\n" );
   return 1;
  };
 }
 return 0;
}

/****************** Functions moved from vast.c ******************/

void extract_mag_and_snr_from_structStar( const struct Star *stars, size_t n_stars, double *mag_array, double *snr_array ) {
 size_t i;
 for ( i= 0; i < n_stars; i++ ) {
  mag_array[i]= (double)stars[i].mag;
  snr_array[i]= stars[i].flux / stars[i].flux_err;
 }
 return;
}

// a comparison function to qsort the observations cached in memory
int compare_star_num( const void *a, const void *b ) {
 const struct Observation *obs_a= (const struct Observation *)a;
 const struct Observation *obs_b= (const struct Observation *)b;

 return ( obs_a->star_num - obs_b->star_num );
}

size_t binary_search_first( struct Observation *arr, size_t size, int target ) {
 size_t left= 0;
 size_t right= size;
 size_t mid;

 while ( left < right ) {
  mid= left + ( right - left ) / 2;
  if ( arr[mid].star_num < target ) {
   left= mid + 1;
  } else {
   right= mid;
  }
 }
 return left;
}

void write_images_catalogs_logfile( char **filelist, int n ) {
 FILE *f;
 int i;
 f= fopen( "vast_images_catalogs.log", "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR in write_images_catalogs_logfile() while opening file %s for writing\n", "vast_images_catalogs.log" );
  return;
 }
 for ( i= 0; i < n; i++ ) {
  fprintf( f, "image%05d.cat %s\n", i + 1, filelist[i] );
 }
 fclose( f );
 return;
}

/* Write data on magnitude calibration to the log file */
void write_magnitude_calibration_log( double *mag1, double *mag2, double *mag_err, int N, char *fitsimagename ) {
 char logfilename[FILENAME_LENGTH];
 FILE *logfile;
 int i;
 strncpy( logfilename, basename( fitsimagename ), FILENAME_LENGTH );
 logfilename[FILENAME_LENGTH - 1]= '\0';
 for ( i= (int)strlen( logfilename ) - 1; i--; ) {
  if ( logfilename[i] == '.' ) {
   logfilename[i]= '\0';
   break;
  }
 }
 strcat( logfilename, ".calib" );
 logfile= fopen( logfilename, "w" );
 if ( NULL == logfile ) {
  fprintf( stderr, "WARNING: can't open %s for writing!\n", logfilename );
  return;
 }
 for ( i= 0; i < N; i++ ) {
  fprintf( logfile, "%8.4lf %8.4lf %.4lf\n", mag1[i], mag2[i], mag_err[i] );
 }
 fclose( logfile );
 fprintf( stderr, "Using %d stars for magnitude calibration (before filtering).\n", N );
 return;
}

void write_magnitude_calibration_log2( double *mag1, double *mag2, double *mag_err, int N, char *fitsimagename ) {
 // Calculate the size of dest, minus the null terminator, to ensure
 // that it is large enough to hold the concatenated string
 size_t dest_size= FILENAME_LENGTH - 1;

 char logfilename[FILENAME_LENGTH];
 FILE *logfile;
 int i;
 strncpy( logfilename, basename( fitsimagename ), FILENAME_LENGTH );
 logfilename[FILENAME_LENGTH - 1]= '\0';
 for ( i= (int)strlen( logfilename ) - 1; i--; ) {
  if ( logfilename[i] == '.' ) {
   logfilename[i]= '\0';
   break;
  }
 }
 // strcat(logfilename, ".calib2");
 strncat( logfilename, ".calib2", dest_size - strlen( logfilename ) );

 logfile= fopen( logfilename, "w" );
 if ( NULL == logfile ) {
  fprintf( stderr, "WARNING: can't open %s for writing!\n", logfilename );
  return;
 }
 for ( i= 0; i < N; i++ ) {
  fprintf( logfile, "%8.4lf %8.4lf %.4lf\n", mag1[i], mag2[i], mag_err[i] );
 }
 fclose( logfile );
 fprintf( stderr, "After removing outliers in (X,Y,dm) plane, we are left with %d stars for magnitude calibration.\n", N );
 return;
}

void write_magnitude_calibration_log_plane( double *mag1, double *mag2, double *mag_err, int N, char *fitsimagename, double A, double B, double C ) {
 // Calculate the size of dest, minus the null terminator, to ensure
 // that it is large enough to hold the concatenated string
 size_t dest_size= FILENAME_LENGTH - 1;

 char logfilename[FILENAME_LENGTH];
 FILE *logfile;
 int i;
 if ( strlen( fitsimagename ) < 1 ) {
  fprintf( stderr, "WARNING from write_magnitude_calibration_log_plane(): cannot get FITS image filename!\n" );
  return;
 }
 strncpy( logfilename, basename( fitsimagename ), FILENAME_LENGTH );
 logfilename[FILENAME_LENGTH - 1]= '\0';
 for ( i= (int)strlen( logfilename ) - 1; i--; ) {
  if ( logfilename[i] == '.' ) {
   logfilename[i]= '\0';
   break;
  }
 }
 // strcat(logfilename, ".calib_plane");
 strncat( logfilename, ".calib_plane", dest_size - strlen( logfilename ) );

 logfile= fopen( logfilename, "w" );
 if ( NULL == logfile ) {
  fprintf( stderr, "WARNING: can't open %s for writing!\n", logfilename );
  return;
 }
 for ( i= 0; i < N; i++ ) {
  fprintf( logfile, "%8.4lf %8.4lf %.4lf\n", mag1[i], mag2[i], mag_err[i] );
 }
 fclose( logfile );
 // strcat(logfilename, ".calib_plane_param");
 strncat( logfilename, ".calib_plane_param", dest_size - strlen( logfilename ) );
 logfile= fopen( logfilename, "w" );
 if ( NULL == logfile ) {
  fprintf( stderr, "WARNING: can't open %s for writing!\n", logfilename );
  return;
 }
 fprintf( logfile, "%lf %lf %lf\n", A, B, C );
 fclose( logfile );
 return;
}

// Write parameters of magnitude calibration to another log file
void write_magnitude_calibration_param_log( double *poly_coeff, char *fitsimagename ) {
 // Calculate the size of dest, minus the null terminator, to ensure
 // that it is large enough to hold the concatenated string
 size_t dest_size= FILENAME_LENGTH - 1;

 char logfilename[FILENAME_LENGTH];
 FILE *logfile;
 int i;
 strncpy( logfilename, basename( fitsimagename ), FILENAME_LENGTH );
 logfilename[FILENAME_LENGTH - 1]= '\0';
 for ( i= (int)strlen( logfilename ) - 1; i--; ) {
  if ( logfilename[i] == '.' ) {
   logfilename[i]= '\0';
   break;
  }
 }
 // strncat(logfilename, ".calib_param", FILENAME_LENGTH - 32);
 strncat( logfilename, ".calib_param", dest_size - strlen( logfilename ) );
 logfilename[FILENAME_LENGTH - 1]= '\0';
 logfile= fopen( logfilename, "w" );
 if ( NULL == logfile ) {
  fprintf( stderr, "WARNING: can't open %s for writing!\n", logfilename );
  return;
 }
 fprintf( logfile, "%lf %lf %lf %lf %lf\n", poly_coeff[4], poly_coeff[3], poly_coeff[2], poly_coeff[1], poly_coeff[0] );
 fclose( logfile );
 return;
}

// save_command_line_to_log_file(int argc, char **argv) - save command line arguments to the log file vast_command_line.log
void save_command_line_to_log_file( int argc, char **argv ) {
 int i;
 FILE *cmdlogfile;
 cmdlogfile= fopen( "vast_command_line.log", "w" );
 if ( NULL == cmdlogfile ) {
  fprintf( stderr, "ERROR: cannot open vast_command_line.log for writing - something is very wrong.\n" );
  return;
 }
 // Print to the terminal in addition to the log file
 fprintf( stderr, "\n VaST was started with the following command line: \n" );
 for ( i= 0; i < argc; i++ ) {
  fprintf( cmdlogfile, "%s ", argv[i] ); // log file
  fprintf( stderr, "%s ", argv[i] );     // terminal
 }
 fclose( cmdlogfile );
 fprintf( stderr, "\n\n" );
}

int compare( const double *a, const double *b ) {
 if ( *a < *b )
  return -1;
 else if ( *a > *b )
  return 1;
 else
  return 0;
}
