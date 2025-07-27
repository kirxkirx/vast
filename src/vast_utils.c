#include <stdio.h> // for fprintf(), fopen(), fclose(), fgets()
#include <stdlib.h>     // malloc, free, exit codes
#include <string.h>     // strcmp, strlen, strdup, sprintf, strncpy
#include <dirent.h>     // DIR, opendir, readdir, closedir, struct dirent
#include <sys/types.h>  // DIR, struct stat
#include <sys/stat.h>   // stat, lstat, struct stat, S_ISDIR
#include <unistd.h>     // unlink, rmdir

#include "vast_utils.h"
#include "vast_limits.h"
#include "vast_is_file.h"
#include "safely_encode_user_input_string.h"

void version( char *version_string ) {
 strncpy( version_string, "VaST 1.0rc88", 32 );
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
 int slashes_only= 1;
 size_t i;
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
 char **dir_stack= malloc( MAX_DIR_DEPTH * sizeof( char * ) );
 int stack_ptr= 0;

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
  char *curr_path= dir_stack[stack_ptr];

  DIR *d= opendir( curr_path );
  if ( d ) {
   struct dirent *p;
   while ( ( p= readdir( d ) ) ) {
    // Skip "." and ".."
    if ( !strcmp( p->d_name, "." ) || !strcmp( p->d_name, ".." ) )
     continue;

    // Construct full path
    size_t curr_len= strlen( curr_path );
    size_t name_len= strlen( p->d_name );
    size_t path_len= curr_len + name_len + 2; // +2 for '/' and '\0'

    char *full_path= malloc( path_len );
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

    struct stat statbuf;
    if ( !stat( full_path, &statbuf ) ) {
     if ( S_ISDIR( statbuf.st_mode ) ) {
      // If directory, add to stack if we haven't reached max depth
      if ( stack_ptr < MAX_DIR_DEPTH ) {
       dir_stack[stack_ptr++]= full_path; // Will process later
      } else {
       fprintf( stderr, "ERROR: Maximum directory depth exceeded\n" );
       free( full_path );
       error= 1;
       break;
      }
     } else {
      // If regular file, remove it
      if ( unlink( full_path ) != 0 ) {
       fprintf( stderr, "ERROR removing file: %s\n", full_path );
       error= 1;
      }
      free( full_path );
     }
    } else {
     // Handle broken symlink case
     if ( !lstat( full_path, &statbuf ) ) {
      unlink( full_path );
     } else {
      fprintf( stderr, "ERROR in vast_remove_directory(): Could not stat: %s\n", full_path );
      error= 1;
     }
     free( full_path );
    }
   }
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

// TODO: replace with memove
// a housekeeping function to exclude i'th element from three arrays
void exclude_from_3_double_arrays( double *array1, double *array2, double *array3, int i, int *N ) {
 int j;
 if ( i < 0 || i >= ( *N ) ) {
  fprintf( stderr, "ERROR in exclude_from_3_double_arrays(): i=%d\n", i );
  return;
 }
 for ( j= i; j < ( *N ) - 1; j++ ) {
  array1[j]= array1[j + 1];
  array2[j]= array2[j + 1];
  array3[j]= array3[j + 1];
 }
 ( *N )= ( *N ) - 1;
 return;
}
// a housekeeping function to exclude i'th element from six arrays
void exclude_from_6_double_arrays( double *array1, double *array2, double *array3, double *array4, double *array5, double *array6, int i, int *N ) {
 int j;
 if ( i < 0 || i >= ( *N ) ) {
  fprintf( stderr, "ERROR in exclude_from_6_double_arrays(): i=%d\n", i );
  return;
 }
 for ( j= i; j < ( *N ) - 1; j++ ) {
  array1[j]= array1[j + 1];
  array2[j]= array2[j + 1];
  array3[j]= array3[j + 1];
  array4[j]= array4[j + 1];
  array5[j]= array5[j + 1];
  array6[j]= array6[j + 1];
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
 f= fopen( "vast_images_catalogs.log", "r" );
 if ( f == NULL ) {
  strcpy( catalogfilename, "image00000.cat" );
  return 1; // not only this image has not been processed, even "vast_images_catalogs.log" is not created yet!
 }
 int found= 0;
 while ( -1 < fscanf( f, "%s %s", local_catalogfilename, fitsfilename_to_test ) ) {
  if ( 0 == strcmp( fitsfilename_to_test, fitsfilename ) ) {
   safely_encode_user_input_string( catalogfilename, local_catalogfilename, FILENAME_LENGTH - 1 );
   found= 1;
   break;
  }
 }
 fclose( f );
 if ( found == 0 ) {
  strcpy( catalogfilename, "image00000.cat" );
  return 1; // it is possible that image00000.cat is referring to another image, so we'll recompute...
 }
 // Check if the catalog already exist
 f= fopen( catalogfilename, "r" );
 if ( f == NULL ) {
  return 1;
 } else {
  fclose( f );
  // Check if default.sex was modified after catalog's creation
  struct stat defSex;
  struct stat cat;
  stat( "default.sex", &defSex );
  stat( catalogfilename, &cat );
  if ( defSex.st_mtime > cat.st_mtime ) {
   fprintf( stderr, "Image will be processed again since default.sex was modified\n" );
   return 1;
  };
 }
 return 0;
}
