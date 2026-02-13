#include <stdio.h>
#include <stdlib.h> // for calloc()
#include <math.h>

#include "vast_types.h"
#include "ident.h"
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
 int i;
 FILE *f;
 double x1, y1, x2, y2, x3, y3;

 f= fopen( fname, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "Cannot open %s\n", fname );
  return;
 }

 fprintf( f, "# Region file format: DS9 version 4.0\n"
             "global color=%s dashlist=8 3 width=1\n"
             "image\n",
          color );

 for ( i= 0; i < Ntri; i++ ) {
  x1= star[tr[i].a[0]].x_frame;
  y1= star[tr[i].a[0]].y_frame;
  x2= star[tr[i].a[1]].x_frame;
  y2= star[tr[i].a[1]].y_frame;
  x3= star[tr[i].a[2]].x_frame;
  y3= star[tr[i].a[2]].y_frame;

  /* three edges */
  fprintf( f, "line(%f,%f,%f,%f)\n", x1, y1, x2, y2 );
  fprintf( f, "line(%f,%f,%f,%f)\n", x2, y2, x3, y3 );
  fprintf( f, "line(%f,%f,%f,%f)\n", x3, y3, x1, y1 );
 }
 fclose( f );
}

/* Draw one triangle (e.g. the current candidate) – different colour   */
void write_single_Triangle_to_ds9( struct Triangle *tr, struct Star *star, const char *fname, const char *color ) {
 struct Triangle arr[1];
 arr[0]= *tr;
 write_Triangle_array_to_ds9( arr, 1, star, fname, color );
}

/* Write triangle matching statistics to a log file */
void write_triangle_matching_debug_log( struct Triangle *tr1, int Nt1, struct Triangle *tr2, int Nt2, struct Star *star1, struct Star *star2, struct Ecv_triangles *ecv_tr, const char *filename ) {
 FILE *f;
 int i;
 // int max_log_triangles;

 (void)star1; // Unused, kept for API consistency
 (void)star2; // Unused, kept for API consistency

 f= fopen( filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR: cannot open %s for writing\n", filename );
  return;
 }

 fprintf( f, "=== TRIANGLE MATCHING DEBUG LOG ===\n" );
 fprintf( f, "Reference triangles: %d\n", Nt1 );
 fprintf( f, "Current image triangles: %d\n", Nt2 );
 fprintf( f, "Equivalent triangles found: %d\n", ecv_tr->Number );
 fprintf( f, "\n" );

 /* Log triangle side statistics - output all triangles, not just first 10 */
 fprintf( f, "=== TRIANGLE SIDE STATISTICS ===\n" );
 fprintf( f, "Reference triangles:\n" );
 for ( i= 0; i < Nt1; i++ ) {
  fprintf( f, "Tri %d: sides=%.2f,%.2f,%.2f area_proxy=%.2f\n",
           i, sqrt( tr1[i].ab ), sqrt( tr1[i].bc ), sqrt( tr1[i].ac ),
           sqrt( tr1[i].ab_bc_ac ) );
 }

 fprintf( f, "\nCurrent triangles:\n" );
 for ( i= 0; i < Nt2; i++ ) {
  fprintf( f, "Tri %d: sides=%.2f,%.2f,%.2f area_proxy=%.2f\n",
           i, sqrt( tr2[i].ab ), sqrt( tr2[i].bc ), sqrt( tr2[i].ac ),
           sqrt( tr2[i].ab_bc_ac ) );
 }

 fprintf( f, "\n=== EQUIVALENT TRIANGLES ===\n" );
 /* Output all equivalent triangles, not just first 20 */
 for ( i= 0; i < ecv_tr->Number; i++ ) {
  fprintf( f, "Match %d: ref(%d,%d,%d) <-> cur(%d,%d,%d)\n", i,
           ecv_tr->tr[i].tr1.a[0], ecv_tr->tr[i].tr1.a[1], ecv_tr->tr[i].tr1.a[2],
           ecv_tr->tr[i].tr2.a[0], ecv_tr->tr[i].tr2.a[1], ecv_tr->tr[i].tr2.a[2] );
 }

 fclose( f );
}

/* Write stars used for triangle construction to DS9 region files */
void write_triangle_construction_stars_ds9( struct Star *star, int Number, const char *filename, const char *color, int max_stars ) {
 FILE *f;
 int i;
 int stars_to_write;

 (void)max_stars; // Intentionally ignored - output all stars

 f= fopen( filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR: cannot open %s for writing\n", filename );
  return;
 }

 fprintf( f, "# Region file format: DS9 version 4.0\n" );
 fprintf( f, "# Triangle construction stars\n" );
 fprintf( f, "global color=%s dashlist=8 3 width=2\n", color );
 fprintf( f, "image\n" );

 /* Output all stars, ignore max_stars limit */
 stars_to_write= Number;

 for ( i= 0; i < stars_to_write; i++ ) {
  fprintf( f, "circle(%.3f,%.3f,5)\n", star[i].x_frame, star[i].y_frame );
  fprintf( f, "# text(%.3f,%.3f) text={%d}\n",
           star[i].x_frame + 8, star[i].y_frame + 8, i );
 }

 fclose( f );
}

/* Write reference frame triangles to separate DS9 region file */
void write_reference_triangles_with_matches_ds9( struct Triangle *tr1, int Nt1, struct Star *star1, struct Ecv_triangles *ecv_tr, const char *filename ) {
 FILE *f;
 int i, j;
 int *ref_matched;
 double x1, y1, x2, y2, x3, y3;

 f= fopen( filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR: cannot open %s for writing\n", filename );
  return;
 }

 /* Allocate array to track which triangles are matched */
 ref_matched= calloc( Nt1, sizeof( int ) );
 if ( !ref_matched ) {
  fclose( f );
  return;
 }

 /* Mark matched triangles */
 for ( i= 0; i < ecv_tr->Number; i++ ) {
  for ( j= 0; j < Nt1; j++ ) {
   if ( tr1[j].a[0] == ecv_tr->tr[i].tr1.a[0] &&
        tr1[j].a[1] == ecv_tr->tr[i].tr1.a[1] &&
        tr1[j].a[2] == ecv_tr->tr[i].tr1.a[2] ) {
    ref_matched[j]= 1;
    break;
   }
  }
 }

 fprintf( f, "# Region file format: DS9 version 4.0\n" );
 fprintf( f, "# Reference frame triangles with match status\n" );
 fprintf( f, "image\n" );

 /* Write all reference triangles */
 for ( i= 0; i < Nt1; i++ ) {
  x1= star1[tr1[i].a[0]].x_frame;
  y1= star1[tr1[i].a[0]].y_frame;
  x2= star1[tr1[i].a[1]].x_frame;
  y2= star1[tr1[i].a[1]].y_frame;
  x3= star1[tr1[i].a[2]].x_frame;
  y3= star1[tr1[i].a[2]].y_frame;

  if ( ref_matched[i] ) {
   fprintf( f, "# color=green\n" );
  } else {
   fprintf( f, "# color=red\n" );
  }

  fprintf( f, "line(%.3f,%.3f,%.3f,%.3f)\n", x1, y1, x2, y2 );
  fprintf( f, "line(%.3f,%.3f,%.3f,%.3f)\n", x2, y2, x3, y3 );
  fprintf( f, "line(%.3f,%.3f,%.3f,%.3f)\n", x3, y3, x1, y1 );
  fprintf( f, "# text(%.3f,%.3f) text={R%d}\n",
           ( x1 + x2 + x3 ) / 3.0, ( y1 + y2 + y3 ) / 3.0, i );
 }

 free( ref_matched );
 fclose( f );
}

/* Write current frame triangles to separate DS9 region file */
void write_current_triangles_with_matches_ds9( struct Triangle *tr2, int Nt2, struct Star *star2, struct Ecv_triangles *ecv_tr, const char *filename ) {
 FILE *f;
 int i, j;
 int *cur_matched;
 double x1, y1, x2, y2, x3, y3;

 f= fopen( filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR: cannot open %s for writing\n", filename );
  return;
 }

 /* Allocate array to track which triangles are matched */
 cur_matched= calloc( Nt2, sizeof( int ) );
 if ( !cur_matched ) {
  fclose( f );
  return;
 }

 /* Mark matched triangles */
 for ( i= 0; i < ecv_tr->Number; i++ ) {
  for ( j= 0; j < Nt2; j++ ) {
   if ( tr2[j].a[0] == ecv_tr->tr[i].tr2.a[0] &&
        tr2[j].a[1] == ecv_tr->tr[i].tr2.a[1] &&
        tr2[j].a[2] == ecv_tr->tr[i].tr2.a[2] ) {
    cur_matched[j]= 1;
    break;
   }
  }
 }

 fprintf( f, "# Region file format: DS9 version 4.0\n" );
 fprintf( f, "# Current frame triangles with match status\n" );
 fprintf( f, "image\n" );

 /* Write all current image triangles */
 for ( i= 0; i < Nt2; i++ ) {
  x1= star2[tr2[i].a[0]].x_frame;
  y1= star2[tr2[i].a[0]].y_frame;
  x2= star2[tr2[i].a[1]].x_frame;
  y2= star2[tr2[i].a[1]].y_frame;
  x3= star2[tr2[i].a[2]].x_frame;
  y3= star2[tr2[i].a[2]].y_frame;

  if ( cur_matched[i] ) {
   fprintf( f, "# color=cyan\n" );
  } else {
   fprintf( f, "# color=magenta\n" );
  }

  fprintf( f, "line(%.3f,%.3f,%.3f,%.3f) # width=2\n", x1, y1, x2, y2 );
  fprintf( f, "line(%.3f,%.3f,%.3f,%.3f) # width=2\n", x2, y2, x3, y3 );
  fprintf( f, "line(%.3f,%.3f,%.3f,%.3f) # width=2\n", x3, y3, x1, y1 );
  fprintf( f, "# text(%.3f,%.3f) text={C%d}\n",
           ( x1 + x2 + x3 ) / 3.0, ( y1 + y2 + y3 ) / 3.0, i );
 }

 free( cur_matched );
 fclose( f );
}

/* DEPRECATED: Use separate functions above instead */
void write_all_triangles_with_matches_ds9( struct Triangle *tr1, int Nt1, struct Triangle *tr2, int Nt2, struct Star *star1, struct Star *star2, struct Ecv_triangles *ecv_tr, const char *filename ) {
 /* Split into separate files to avoid coordinate system mixing */
 char ref_filename[256];
 char cur_filename[256];

 snprintf( ref_filename, sizeof( ref_filename ), "ref_%s", filename );
 snprintf( cur_filename, sizeof( cur_filename ), "cur_%s", filename );

 write_reference_triangles_with_matches_ds9( tr1, Nt1, star1, ecv_tr, ref_filename );
 write_current_triangles_with_matches_ds9( tr2, Nt2, star2, ecv_tr, cur_filename );
}

/* Write the best triangle match and coordinate transformation info */
void write_best_triangle_match_ds9( struct Ecv_triangles *ecv_tr, int best_triangle_index, struct Star *star1, struct Star *star2, struct PixCoordinateTransformation *transform, const char *filename ) {
 FILE *f;
 double x1, y1, x2, y2, x3, y3;
 char ref_filename[256];
 char cur_filename[256];

 if ( best_triangle_index < 0 || best_triangle_index >= ecv_tr->Number ) {
  return;
 }

 /* Create separate files for reference and current frames */
 snprintf( ref_filename, sizeof( ref_filename ), "ref_%s", filename );
 snprintf( cur_filename, sizeof( cur_filename ), "cur_%s", filename );

 /* Write reference triangle */
 f= fopen( ref_filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR: cannot open %s for writing\n", ref_filename );
  return;
 }

 fprintf( f, "# Region file format: DS9 version 4.0\n" );
 fprintf( f, "# Best triangle match - reference frame\n" );
 fprintf( f, "# Rotation: %.3f degrees\n", transform->fi * 180.0 / M_PI );
 fprintf( f, "# Translation: (%.2f, %.2f)\n",
          transform->translate1[0] + transform->translate2[0],
          transform->translate1[1] + transform->translate2[1] );
 fprintf( f, "image\n" );

 /* Reference triangle in thick green */
 x1= star1[ecv_tr->tr[best_triangle_index].tr1.a[0]].x_frame;
 y1= star1[ecv_tr->tr[best_triangle_index].tr1.a[0]].y_frame;
 x2= star1[ecv_tr->tr[best_triangle_index].tr1.a[1]].x_frame;
 y2= star1[ecv_tr->tr[best_triangle_index].tr1.a[1]].y_frame;
 x3= star1[ecv_tr->tr[best_triangle_index].tr1.a[2]].x_frame;
 y3= star1[ecv_tr->tr[best_triangle_index].tr1.a[2]].y_frame;

 fprintf( f, "# color=green width=4\n" );
 fprintf( f, "line(%.3f,%.3f,%.3f,%.3f)\n", x1, y1, x2, y2 );
 fprintf( f, "line(%.3f,%.3f,%.3f,%.3f)\n", x2, y2, x3, y3 );
 fprintf( f, "line(%.3f,%.3f,%.3f,%.3f)\n", x3, y3, x1, y1 );
 fprintf( f, "# text(%.3f,%.3f) text={REF_BEST}\n", ( x1 + x2 + x3 ) / 3.0, ( y1 + y2 + y3 ) / 3.0 );

 fclose( f );

 /* Write current triangle */
 f= fopen( cur_filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR: cannot open %s for writing\n", cur_filename );
  return;
 }

 fprintf( f, "# Region file format: DS9 version 4.0\n" );
 fprintf( f, "# Best triangle match - current frame\n" );
 fprintf( f, "# Rotation: %.3f degrees\n", transform->fi * 180.0 / M_PI );
 fprintf( f, "# Translation: (%.2f, %.2f)\n",
          transform->translate1[0] + transform->translate2[0],
          transform->translate1[1] + transform->translate2[1] );
 fprintf( f, "image\n" );

 /* Current triangle in thick cyan */
 x1= star2[ecv_tr->tr[best_triangle_index].tr2.a[0]].x_frame;
 y1= star2[ecv_tr->tr[best_triangle_index].tr2.a[0]].y_frame;
 x2= star2[ecv_tr->tr[best_triangle_index].tr2.a[1]].x_frame;
 y2= star2[ecv_tr->tr[best_triangle_index].tr2.a[1]].y_frame;
 x3= star2[ecv_tr->tr[best_triangle_index].tr2.a[2]].x_frame;
 y3= star2[ecv_tr->tr[best_triangle_index].tr2.a[2]].y_frame;

 fprintf( f, "# color=cyan width=4\n" );
 fprintf( f, "line(%.3f,%.3f,%.3f,%.3f)\n", x1, y1, x2, y2 );
 fprintf( f, "line(%.3f,%.3f,%.3f,%.3f)\n", x2, y2, x3, y3 );
 fprintf( f, "line(%.3f,%.3f,%.3f,%.3f)\n", x3, y3, x1, y1 );
 fprintf( f, "# text(%.3f,%.3f) text={CUR_BEST}\n", ( x1 + x2 + x3 ) / 3.0, ( y1 + y2 + y3 ) / 3.0 );

 fclose( f );
}

/* Write matched star pairs after coordinate transformation */
void write_matched_stars_ds9( struct Star *star1, struct Star *star2, int *Pos1, int *Pos2, int num_matched, const char *filename ) {
 FILE *f;
 int i;
 char ref_filename[256];
 char cur_filename[256];
 double dx, dy, dist;

 /* Create separate files for reference and current frames */
 snprintf( ref_filename, sizeof( ref_filename ), "ref_%s", filename );
 snprintf( cur_filename, sizeof( cur_filename ), "cur_%s", filename );

 /* Write reference stars */
 f= fopen( ref_filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR: cannot open %s for writing\n", ref_filename );
  return;
 }

 fprintf( f, "# Region file format: DS9 version 4.0\n" );
 fprintf( f, "# Matched stars - reference frame\n" );
 fprintf( f, "# %d total matches\n", num_matched );
 fprintf( f, "image\n" );

 /* Output all matched stars, not just first 100 */
 for ( i= 0; i < num_matched; i++ ) {
  /* Reference star in green */
  fprintf( f, "# color=green\n" );
  fprintf( f, "circle(%.3f,%.3f,3)\n",
           star1[Pos1[i]].x_frame, star1[Pos1[i]].y_frame );

  /* Distance annotation for first 50 to avoid excessive clutter */
  if ( i < 50 ) {
   dx= star1[Pos1[i]].x_frame - star2[Pos2[i]].x_frame;
   dy= star1[Pos1[i]].y_frame - star2[Pos2[i]].y_frame;
   dist= sqrt( dx * dx + dy * dy );

   fprintf( f, "# text(%.3f,%.3f) text={%.1f}\n",
            star1[Pos1[i]].x_frame + 8, star1[Pos1[i]].y_frame + 8, dist );
  }
 }

 fclose( f );

 /* Write current stars */
 f= fopen( cur_filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR: cannot open %s for writing\n", cur_filename );
  return;
 }

 fprintf( f, "# Region file format: DS9 version 4.0\n" );
 fprintf( f, "# Matched stars - current frame\n" );
 fprintf( f, "# %d total matches\n", num_matched );
 fprintf( f, "image\n" );

 /* Output all matched stars */
 for ( i= 0; i < num_matched; i++ ) {
  /* Current star in yellow */
  fprintf( f, "# color=yellow\n" );
  fprintf( f, "circle(%.3f,%.3f,3)\n",
           star2[Pos2[i]].x_frame, star2[Pos2[i]].y_frame );

  /* Distance annotation for first 50 to avoid excessive clutter */
  if ( i < 50 ) {
   dx= star1[Pos1[i]].x_frame - star2[Pos2[i]].x_frame;
   dy= star1[Pos1[i]].y_frame - star2[Pos2[i]].y_frame;
   dist= sqrt( dx * dx + dy * dy );

   fprintf( f, "# text(%.3f,%.3f) text={%.1f}\n",
            star2[Pos2[i]].x_frame + 8, star2[Pos2[i]].y_frame + 8, dist );
  }
 }

 fclose( f );
}

/* Write triangle similarity analysis */
void write_triangle_similarity_analysis( struct Triangle *tr1, int Nt1, struct Triangle *tr2, int Nt2, float sigma_podobia, const char *filename ) {
 FILE *f;
 int i, j;
 int similar_count;
 float scale_factor, scale_diff;

 f= fopen( filename, "w" );
 if ( NULL == f ) {
  fprintf( stderr, "ERROR: cannot open %s for writing\n", filename );
  return;
 }

 similar_count= 0;

 fprintf( f, "=== TRIANGLE SIMILARITY ANALYSIS ===\n" );
 fprintf( f, "Similarity tolerance: %.4f\n", sigma_podobia );
 fprintf( f, "Reference triangles: %d\n", Nt1 );
 fprintf( f, "Current triangles: %d\n", Nt2 );
 fprintf( f, "\n" );

 /* Analyze all triangles, not just first few */
 for ( i= 0; i < Nt1; i++ ) {
  fprintf( f, "--- Reference triangle %d ---\n", i );
  fprintf( f, "Sides: %.2f, %.2f, %.2f\n",
           sqrt( tr1[i].ab ), sqrt( tr1[i].bc ), sqrt( tr1[i].ac ) );
  fprintf( f, "Area proxy: %.2f\n", sqrt( tr1[i].ab_bc_ac ) );

  /* Check for similar triangles */
  for ( j= 0; j < Nt2; j++ ) {
   scale_factor= tr1[i].ab_bc_ac / tr2[j].ab_bc_ac;
   scale_diff= fabs( scale_factor - 1.0 );

   if ( scale_diff < MAX_SCALE_FACTOR ) {
    fprintf( f, "  Potential match with current triangle %d (scale diff: %.4f)\n",
             j, scale_diff );
    similar_count++;
   }
  }
  fprintf( f, "\n" );
 }

 fprintf( f, "Total potential scale matches found: %d\n", similar_count );
 fclose( f );
}

int Podobie_debug( struct PixCoordinateTransformation *struct_pixel_coordinate_transformation, struct Ecv_triangles *ecv_tr, struct Triangle *tr1, int Nt1, struct Triangle *tr2, int Nt2, struct Star *star1, struct Star *star2, int Number1, int Number2 ) {
 int result;

 /* Call original function */
 result= Podobie( struct_pixel_coordinate_transformation, ecv_tr, tr1, Nt1, tr2, Nt2 );

 /* Add debugging output */
 write_triangle_matching_debug_log( tr1, Nt1, tr2, Nt2, star1, star2, ecv_tr,
                                    "triangle_matching_debug.log" );

 /* Output all stars using the actual star count, not triangle count */
 write_triangle_construction_stars_ds9( star1, Number1,
                                        "debug_reference_stars.reg", "green", Number1 );

 write_triangle_construction_stars_ds9( star2, Number2,
                                        "debug_current_stars.reg", "cyan", Number2 );

 /* Use separate files for reference and current triangles */
 write_reference_triangles_with_matches_ds9( tr1, Nt1, star1, ecv_tr,
                                             "debug_reference_triangles.reg" );

 write_current_triangles_with_matches_ds9( tr2, Nt2, star2, ecv_tr,
                                           "debug_current_triangles.reg" );

 write_triangle_similarity_analysis( tr1, Nt1, tr2, Nt2,
                                     struct_pixel_coordinate_transformation->sigma_podobia,
                                     "triangle_similarity_analysis.log" );

 return result;
}

int Very_Well_triangle_debug( struct Star *star1, int Number1, struct Star *star2, int Number2, struct Ecv_triangles *ecv_tr, struct PixCoordinateTransformation *struct_pixel_coordinate_transformation, int *nm, int control1 ) {
 int i;
 int star_idx;
 int result;
 FILE *f;

 /* Call original function */
 result= Very_Well_triangle( star1, Number1, star2, Number2, ecv_tr,
                             struct_pixel_coordinate_transformation, nm, control1 );

 /* Add debugging output */
 if ( result > 0 && *nm >= 0 && *nm < ecv_tr->Number ) {
  write_best_triangle_match_ds9( ecv_tr, *nm, star1, star2,
                                 struct_pixel_coordinate_transformation,
                                 "debug_best_triangle.reg" );

  /* Write detailed log about the best match */
  f= fopen( "best_triangle_match.log", "w" );
  if ( f ) {
   fprintf( f, "=== BEST TRIANGLE MATCH ANALYSIS ===\n" );
   fprintf( f, "Best triangle index: %d\n", *nm );
   fprintf( f, "Number of matched stars: %d\n", result );
   fprintf( f, "Rotation angle: %.3f degrees\n",
            struct_pixel_coordinate_transformation->fi * 180.0 / M_PI );
   fprintf( f, "Translation: (%.2f, %.2f)\n",
            struct_pixel_coordinate_transformation->translate1[0] +
                struct_pixel_coordinate_transformation->translate2[0],
            struct_pixel_coordinate_transformation->translate1[1] +
                struct_pixel_coordinate_transformation->translate2[1] );
   fprintf( f, "Linear transformation matrix:\n" );
   fprintf( f, "  %.6f  %.6f\n",
            struct_pixel_coordinate_transformation->line[0],
            struct_pixel_coordinate_transformation->line[1] );
   fprintf( f, "  %.6f  %.6f\n",
            struct_pixel_coordinate_transformation->line[2],
            struct_pixel_coordinate_transformation->line[3] );

   /* Log the stars in the best triangle */
   fprintf( f, "\nReference triangle stars:\n" );
   for ( i= 0; i < 3; i++ ) {
    star_idx= ecv_tr->tr[*nm].tr1.a[i];
    fprintf( f, "  Star %d: (%.2f, %.2f) mag=%.2f\n",
             star_idx, star1[star_idx].x_frame, star1[star_idx].y_frame,
             star1[star_idx].mag );
   }

   fprintf( f, "\nCurrent triangle stars:\n" );
   for ( i= 0; i < 3; i++ ) {
    star_idx= ecv_tr->tr[*nm].tr2.a[i];
    fprintf( f, "  Star %d: (%.2f, %.2f) mag=%.2f\n",
             star_idx, star2[star_idx].x_frame, star2[star_idx].y_frame,
             star2[star_idx].mag );
   }

   fclose( f );
  }
 }

 return result;
}
