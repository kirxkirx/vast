
#include <stdio.h>

#include "vast_types.h"
#include "ident_debug.h"

//
// This function is useful for debugging. It will create a DS9 region file from an rray of structures (type struct Star)
// containing a list of stars.
//
void write_Star_struct_to_ds9_region_file( struct Star *star, int N_start, int N_stop, char *filename, double aperture ) {
 int i;
 FILE *f;
 f= fopen( filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR in write_Star_struct_to_ds9_region_file() while opening file %s for writing!\n", filename );
  return;
 }
 fprintf( f, "# Region file format: DS9 version 4.0\n" );
 fprintf( f, "# Filename:\n" );
 fprintf( f, "global color=green font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source\n" );
 fprintf( f, "image\n" );
 for ( i= N_start; i < N_stop; i++ ) {
  fprintf( f, "circle(%f,%f,%lf)\n", star[i].x_frame, star[i].y_frame, aperture * 0.5 );
 }
 fclose( f );
 return;
}

void write_single_Star_from_struct_to_ds9_region_file( struct Star *star, int N_start, int N_stop, char *filename, double aperture ) {
 int i;
 FILE *f;
 // try to open the file
 f= fopen( filename, "r" );
 if ( f == NULL ) {
  // write header
  f= fopen( filename, "w" );
  if ( NULL == f ) {
   fprintf( stderr, "ERROR in write_single_Star_from_struct_to_ds9_region_file() while opening file %s for writing\n", filename );
   return;
  }
  fprintf( f, "# Region file format: DS9 version 4.0\n" );
  fprintf( f, "# Filename:\n" );
  fprintf( f, "global color=green font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source\n" );
  fprintf( f, "image\n" );
 }
 fclose( f );
 f= fopen( filename, "a" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR in write_single_Star_from_struct_to_ds9_region_file() while opening file %s for addition\n", filename );
  return;
 }
 for ( i= N_start; i < N_stop; i++ ) {
  fprintf( f, "circle(%f,%f,%lf)\n", star[i].x_frame, star[i].y_frame, aperture * 0.5 );
 }
 fclose( f );
 return;
}

void write_Star_struct_to_ASCII_file( struct Star *star, int N_start, int N_stop, char *filename, double aperture ) {
 int i;
 FILE *f;
 f= fopen( filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR in write_Star_struct_to_ASCII_file() while opening file %s for writing\n", filename );
  return;
 }
 for ( i= N_start; i < N_stop; i++ ) {
  fprintf( f, "%f  %f   %lf\n", star[i].x, star[i].y, aperture * 0.5 );
 }
 fclose( f );
 return;
}


/* Draw a set of triangles */
void write_Triangle_array_to_ds9( struct Triangle *tr, int Ntri, struct Star *star, const char *fname, const char *color ) {
    int    i;
    FILE  *f;
    double x1, y1, x2, y2, x3, y3;

    f = fopen(fname, "w");
    if (NULL == f) { fprintf(stderr, "Cannot open %s\n", fname); return; }

    fprintf(f, "# Region file format: DS9 version 4.0\n"
               "global color=%s dashlist=8 3 width=1\n"
               "image\n", color);

    for (i = 0; i < Ntri; i++) {
        x1 = star[tr[i].a[0]].x_frame;  y1 = star[tr[i].a[0]].y_frame;
        x2 = star[tr[i].a[1]].x_frame;  y2 = star[tr[i].a[1]].y_frame;
        x3 = star[tr[i].a[2]].x_frame;  y3 = star[tr[i].a[2]].y_frame;

        /* three edges */
        fprintf(f, "line(%f,%f,%f,%f)\n", x1, y1, x2, y2);
        fprintf(f, "line(%f,%f,%f,%f)\n", x2, y2, x3, y3);
        fprintf(f, "line(%f,%f,%f,%f)\n", x3, y3, x1, y1);
    }
    fclose(f);
}

/* Draw one triangle (e.g. the current candidate) – different colour   */
void write_single_Triangle_to_ds9( struct Triangle *tr, struct Star *star, const char *fname, const char *color ) {
    struct Triangle arr[1];
    arr[0] = *tr;
    write_Triangle_array_to_ds9(arr, 1, star, fname, color);
}

