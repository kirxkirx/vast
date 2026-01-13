#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <dirent.h>

#include "vast_limits.h"

// Structure to hold the data from the files
typedef struct {
 double julian_date;
 char *line;
} Data;

// Comparator function for qsort()
int compare_julian_date( const void *a, const void *b ) {
 double date_a= ( (Data *)a )->julian_date;
 double date_b= ( (Data *)b )->julian_date;
 return ( date_a > date_b ) - ( date_a < date_b );
}

// Function to sort the content of a file after checking if the file is already sorted (if it is - do nothing)
void sort_file( const char *file_name ) {
 Data data_arr[MAX_NUMBER_OF_OBSERVATIONS];
 size_t data_count;
 char line[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 double julian_date;
 size_t i;
 int is_sorted= 1; // Assume sorted initially

 FILE *file= fopen( file_name, "r" );
 if ( !file ) {
  sprintf( line, "sort_file() ERROR opening file %s", file_name );
  perror( line );
  return;
 }

 data_count= 0;
 while ( fgets( line, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, file ) ) {
  sscanf( line, "%lf", &julian_date );

  data_arr[data_count].julian_date= julian_date;
  data_arr[data_count].line= malloc( MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE * sizeof( char ) );
  if ( NULL == data_arr[data_count].line ) {
   fprintf( stderr, "ERROR: NULL == data_arr[data_count].line \n" );
   fclose( file );
   return;
  }
  strncpy( data_arr[data_count].line, line, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE );
  data_arr[data_count].line[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE - 1] = '\0'; // just in case

  // Check if the current entry is out of order
  if ( data_count > 0 && julian_date < data_arr[data_count - 1].julian_date ) {
   is_sorted= 0;
  }

  data_count++;
  
  // Check for the unlikely case where the lightcurve may have more than MAX_NUMBER_OF_OBSERVATIONS
  if (data_count >= MAX_NUMBER_OF_OBSERVATIONS) {
   fprintf(stderr, "ERROR: too many lines in %s (>%d)\n", file_name, MAX_NUMBER_OF_OBSERVATIONS);
   break; // or return
  }
  
 }
 fclose( file );

 // If the data is already sorted, free memory and return
 if ( is_sorted ) {
  for ( i= 0; i < data_count; i++ ) {
   free( data_arr[i].line );
  }
  return;
 }

 // If not sorted, continue with the existing sorting and file operations
 qsort( data_arr, data_count, sizeof( Data ), compare_julian_date );

 // Write sorted data to the output file
 char output_file_name[OUTFILENAME_LENGTH];
 snprintf( output_file_name, sizeof( output_file_name ), "%s.sorted", file_name );
 FILE *output_file= fopen( output_file_name, "w" );

 if ( !output_file ) {
  fprintf( stderr, "ERROR opening output file %s\n", output_file_name );
  return;
 }

 for ( i= 0; i < data_count; i++ ) {
  fprintf( output_file, "%s", data_arr[i].line );
  free( data_arr[i].line );
 }

 fclose( output_file );

 // Replace the original file with the sorted file
 if ( remove( file_name ) != 0 ) {
  perror( "sort_file() ERROR deleting original file" );
  return;
 }
 if ( rename( output_file_name, file_name ) != 0 ) {
  perror( "sort_file() ERROR renaming sorted file" );
  return;
 }

 return;
}

// Function to sort the content of a file
void sort_file_old( const char *file_name ) {

 Data data_arr[MAX_NUMBER_OF_OBSERVATIONS]; // Assuming max MAX_NUMBER_OF_OBSERVATIONS rows per file
 size_t data_count;
 char line[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 // char line_copy[MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE];
 double julian_date;

 size_t i;
 FILE *file= fopen( file_name, "r" );
 if ( !file ) {
  sprintf( line, "sort_file() ERROR opening file %s", file_name );
  perror( line );
  return;
 }

 data_count= 0;
 while ( fgets( line, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE, file ) ) {
  sscanf( line, "%lf", &julian_date );

  data_arr[data_count].julian_date= julian_date;
  data_arr[data_count].line= malloc( MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE * sizeof( char ) );
  if ( NULL == data_arr[data_count].line ) {
   fprintf( stderr, "ERROR: NULL == data_arr[data_count].line \n" );
   fclose( file );
   return;
  }
  strncpy( data_arr[data_count].line, line, MAX_STRING_LENGTH_IN_LIGHTCURVE_FILE );
  data_count++;
 }
 fclose( file );

 // Sort the data array
 qsort( data_arr, data_count, sizeof( Data ), compare_julian_date );

 // Write sorted data to the output file
 char output_file_name[OUTFILENAME_LENGTH];
 snprintf( output_file_name, sizeof( output_file_name ), "%s.sorted", file_name );
 FILE *output_file= fopen( output_file_name, "w" );

 if ( !output_file ) {
  fprintf( stderr, "ERROR opening output file %s\n", output_file_name );
  return;
 }

 for ( i= 0; i < data_count; i++ ) {
  fprintf( output_file, "%s", data_arr[i].line );
  free( data_arr[i].line );
 }

 fclose( output_file );

 // Replace the original file with the sorted file
 if ( remove( file_name ) != 0 ) {
  perror( "sort_file() ERROR deleting original file" );
  return;
 }
 if ( rename( output_file_name, file_name ) != 0 ) {
  perror( "sort_file() ERROR renaming sorted file" );
  return;
 }

 return;
}

int main() {

 int i;
 DIR *dir;
 struct dirent *ent;
 const char *dir_path= "./"; // Your directory path here
 long filenamelen;
 int file_count;
 char **file_list;

 if ( ( dir= opendir( dir_path ) ) != NULL ) {

  // Allocate memory only if we successfully opened the directory
  file_list= malloc( sizeof( char * ) * MAX_NUMBER_OF_STARS );
  if ( NULL == file_list ) {
   fprintf( stderr, "ERROR: NULL == file_list \n" );
   return EXIT_FAILURE;
  }

  for ( i= 0; i < MAX_NUMBER_OF_STARS; i++ ) {
   // allocate memoery for each file name
   file_list[i]= malloc( sizeof( char ) * OUTFILENAME_LENGTH );
   if ( NULL == file_list[i] ) {
    fprintf( stderr, "ERROR: NULL == file_list[i] \n" );
    return EXIT_FAILURE;
   }
   // reset the file name string to '\0'
   memset( file_list[i], '\0', sizeof( char ) * OUTFILENAME_LENGTH );
  }

  // List all outNNNNN.dat files
  file_count= 0;
  while ( ( ent= readdir( dir ) ) != NULL ) {
   filenamelen= strlen( ent->d_name );
   if ( filenamelen < 8 ) {
    continue; // make sure the filename is not too short for the following tests
   }
   if ( ent->d_name[0] == 'o' && ent->d_name[1] == 'u' && ent->d_name[2] == 't' && ent->d_name[filenamelen - 1] == 't' && ent->d_name[filenamelen - 2] == 'a' && ent->d_name[filenamelen - 3] == 'd' ) {
    strncpy( file_list[file_count], ent->d_name, OUTFILENAME_LENGTH - 1 ); // the last character is supposed to always stay '\0'
    file_count++;
   }
  }

  closedir( dir );

// Process the outNNNNN.dat files listed in file_list[] in parallel using OpenMP
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i )
#endif
#endif
  for ( i= 0; i < file_count; i++ ) {
   sort_file( file_list[i] );
  }

  // Free-up memory (it was allocated only if the directory was open successfully)
  for ( i= 0; i < MAX_NUMBER_OF_STARS; i++ ) {
   free( file_list[i] );
  }
  free( file_list );

 } else {
  fprintf( stderr, "sort_all_lightcurve_files_in_jd: ERROR opening directory %s\n", dir_path );
  return EXIT_FAILURE;
 }

 return EXIT_SUCCESS;
}
