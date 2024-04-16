/*****************************************************************************
 *
 *  IDENT LIB MODULE: ident_lib.c
 *
 *  Copyright(C) 2005-2023 Lebedev Alexander <lebedev@xray.sai.msu.ru>,
 *                         Sokolovsky Kirill <idkfa@sai.msu.ru>.
 *
 *  This program is free software ; you can redistribute it and/or modify
 *  it under the terms of the GNU General Public License as published by
 *  the Free Software Foundation ; either version 2 of the License, or
 *  (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY ; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with this program ; if not, write to the Free Software
 *  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
 *
 * $Id$
 *
 ****************************************************************************/

#include <stdlib.h>
#include <stdio.h>
#include <math.h>

#include "ident.h"
#include "vast_limits.h"
#include "vast_report_memory_error.h"
#include "fit_plane_lin.h"

// no this is not faster
/*
static inline int compare_two_floats_to_absolute_accuracy(float x1, float x2, float delta) {
 if( x1 - x2 > delta )return 1;
 if( x2 - x1 > delta )return 1;
 return 0;
}
*/

// a hacked version is actually 10% (overall performance) faster than whatever is below
static inline int compare_two_floats_to_absolute_accuracy( float x1, float x2, float delta ) {
 if ( fabs( x1 - x2 ) < delta )
  return 0;
 return 1;
}

// A proper version of the function
// static inline int compare_two_floats_to_absolute_accuracy(float x1, float x2, float delta) {
// float difference = x1 - x2;
// if (difference > delta)
//  return 1; /* x1 > x2 */
// else if (difference < -delta)
//  return -1;  /* x1 < x2 */
// else /* -delta <= difference <= delta */
//  return 0;  /* x1 == x2 */
//}

struct Preobr_Sk *New_Preobr_Sk() {
 struct Preobr_Sk *preobr;
 preobr= malloc( sizeof( struct Preobr_Sk ) );
 if ( preobr == NULL ) {
  fprintf( stderr, "ERROR in New_Preobr_Sk():\n preobr = malloc(sizeof(struct Preobr_Sk)); - failed\n" );
  vast_report_memory_error();
  exit( EXIT_FAILURE );
 }
 // preobr->podobie = 1;
 preobr->translate1[0]= 0;
 preobr->translate1[1]= 0;
 preobr->translate2[0]= 0;
 preobr->translate2[1]= 0;
 preobr->line[0]= 1;
 preobr->line[1]= 0;
 preobr->line[2]= 0;
 preobr->line[3]= 1;
 preobr->fi= 0;

 preobr->sigma_podobia= 0.01;
 preobr->Number_of_ecv_triangle= 100;
 preobr->sigma_popadaniya= 1.0;
 preobr->sigma_popadaniya_multiple= 3.0;
 preobr->persent_popadaniy_of_ecv_triangle= 0.6;
 preobr->method= MAXIMUM_POPADANIY;
 preobr->Number_of_main_star= 100;
 return ( preobr );
}

void Delete_Preobr_Sk( struct Preobr_Sk *preobr ) {
 free( preobr );
}

void Star_Copy( struct Star *copy, struct Star *star ) {
 copy->x= star->x;
 copy->y= star->y;
 copy->flux= star->flux;
 copy->n= star->n;
 copy->mag= star->mag;
 copy->sigma_mag= star->sigma_mag;
 copy->JD= star->JD;
 copy->x_frame= star->x_frame;
 copy->y_frame= star->y_frame;
 copy->detected_on_ref_frame= star->detected_on_ref_frame;
 copy->sextractor_flag= star->sextractor_flag;
 copy->vast_flag= star->vast_flag;
 copy->star_size= star->star_size;
 //
 copy->star_psf_chi2= star->star_psf_chi2;
 //
 int i;
 for ( i= NUMBER_OF_FLOAT_PARAMETERS; i--; ) {
  copy->float_parameters[i]= star->float_parameters[i];
 }
 //
 copy->n_detected= star->n_detected;
 copy->n_rejected= star->n_rejected;
 //
 copy->moving_object= star->moving_object;
 //
}

static inline void Ecv_Triangle_Copy( struct Ecv_Triangle *ecv_tr1, struct Ecv_Triangle *ecv_tr2 ) {
 ecv_tr1->tr1.a[0]= ecv_tr2->tr1.a[0];
 ecv_tr1->tr1.a[1]= ecv_tr2->tr1.a[1];
 ecv_tr1->tr1.a[2]= ecv_tr2->tr1.a[2];
 ecv_tr1->tr2.a[0]= ecv_tr2->tr2.a[0];
 ecv_tr1->tr2.a[1]= ecv_tr2->tr2.a[1];
 ecv_tr1->tr2.a[2]= ecv_tr2->tr2.a[2];
}

struct Ecv_triangles *Init_ecv_triangles() {
 struct Ecv_triangles *ecv_tr;
 ecv_tr= malloc( sizeof( struct Ecv_triangles ) );
 if ( ecv_tr == NULL ) {
  fprintf( stderr, "ERROR in Init_ecv_triangles:\n ecv_tr = malloc(sizeof(struct Ecv_triangles)); - failed\n" );
  vast_report_memory_error();
  exit( EXIT_FAILURE );
 }
 ecv_tr->tr= NULL;
 ecv_tr->Number= 0;
 return ( ecv_tr );
}

static inline void Add_ecv_triangles( struct Ecv_triangles *ecv_tr, int a1, int b1, int c1,
                                      int a2, int b2, int c2 ) {
 int n;
 ecv_tr->Number++;
 n= ecv_tr->Number;
 ecv_tr->tr= realloc( ecv_tr->tr, sizeof( struct Ecv_Triangle ) * n ); /// !!!!! THIS IS MAD, USE MALLOC !!!!
 if ( ecv_tr->tr == NULL ) {
  fprintf( stderr, "ERROR in Add_ecv_triangles:\n ecv_tr->tr = realloc(ecv_tr->tr, sizeof(struct Ecv_Triangle) * n); - failed\n" );
  exit( EXIT_FAILURE );
 }
 ecv_tr->tr[n - 1].tr1.a[0]= a1;
 ecv_tr->tr[n - 1].tr1.a[1]= b1;
 ecv_tr->tr[n - 1].tr1.a[2]= c1;
 ecv_tr->tr[n - 1].tr2.a[0]= a2;
 ecv_tr->tr[n - 1].tr2.a[1]= b2;
 ecv_tr->tr[n - 1].tr2.a[2]= c2;
}

void Delete_Ecv_triangles( struct Ecv_triangles *ecv_tr ) {
 free( ecv_tr->tr );
 free( ecv_tr );
}

static inline void Translate( struct Star *star, int Number, double dx, double dy ) {
 int n;
 for ( n= Number; n--; ) {
  star[n].x+= dx;
  star[n].y+= dy;
 }
}

static inline void Rotate( struct Star *star, int Number, double fi ) {
 double X, Y;
 int n;
 for ( n= Number; n--; ) {
  X= star[n].x * cos( fi ) - star[n].y * sin( fi );
  Y= star[n].x * sin( fi ) + star[n].y * cos( fi );
  star[n].x= X;
  star[n].y= Y;
 }
}

static inline void Line_Preobr( struct Star *star, int Number, const double *line ) {
 double X, Y;
 int n;
 for ( n= Number; n--; ) {
  X= star[n].x * line[0] + star[n].y * line[1];
  Y= star[n].x * line[2] + star[n].y * line[3];
  star[n].x= X;
  star[n].y= Y;
 }
}

/*
 This function compares magnitudes two stars described by struct Star.
 It is used by Sort_in_mag_of_stars()...
 */
static int compare_star_on_mag( const void *a1, const void *a2 ) {
 struct Star *s1, *s2;
 s1= (struct Star *)a1;
 s2= (struct Star *)a2;
 //// trap!!! do not let blended or saturated stars be listed as the brightest (despite it's true), put them in the back of the list!
 if ( s1->vast_flag != 0 )
  return 1;
 if ( s2->vast_flag != 0 )
  return -1;
 //// end of trap
 if ( s1->mag < s2->mag ) {
  return -1;
 }
 return 1;
}

/*
 This function will sort a list of stars according to their magnitude.
 */
void Sort_in_mag_of_stars( struct Star *star, int Number ) {
 qsort( star, Number, sizeof( struct Star ), compare_star_on_mag );
}

/*
 This function creates a triangle from a given star ("a0" in the array of structures "star") and two stars closest to it.
 "star" is n array of Star-type structures containing "Number" reference stars.
 */
struct Triangle Create_One_Triangle_from_Nearby_Stars( struct Star *star, int Number, int a0 ) {
 struct Triangle tr;
 int b, Number_of_Rmin= -1, N_old;
 double Rab, Rmin, Rmin_old;

 // Find the closest star.
 tr.a[0]= a0;
 for ( Rmin= -1, b= 0; b < Number; b++ ) {
  if ( ( b == tr.a[0] ) )
   continue;
  Rab= ( star[a0].x - star[b].x ) * ( star[a0].x - star[b].x ) +
       ( star[a0].y - star[b].y ) * ( star[a0].y - star[b].y );
  // if( Rab < MATCH__MIN_SIZE_OF_TRIANGLE_PIX_SQUARED )continue;
  // if( Rab > MATCH__MAX_SIZE_OF_SMALL_TRIANGLE_PIX_SQUARED )continue;
  if ( Rmin == -1 ) {
   Rmin= Rab;
   Number_of_Rmin= b;
  }
  if ( Rmin > Rab ) {
   Rmin= Rab;
   Number_of_Rmin= b;
  }
 }
 tr.a[1]= Number_of_Rmin;

 // Now find the second-closest star.
 // First case: second-closest to the first star,
 // Second case: second-closest to the second star.
 // and then decide which one is closer to the corresponding
 // star and take it for the triangle.

 for ( Rmin= -1, b= 0; b < Number; b++ ) {
  if ( ( b == tr.a[0] ) || ( b == tr.a[1] ) )
   continue;
  Rab= ( star[a0].x - star[b].x ) * ( star[a0].x - star[b].x ) +
       ( star[a0].y - star[b].y ) * ( star[a0].y - star[b].y );
  // if( Rab < MATCH__MIN_SIZE_OF_TRIANGLE_PIX_SQUARED )continue;
  // if( Rab > MATCH__MAX_SIZE_OF_SMALL_TRIANGLE_PIX_SQUARED )continue;
  if ( Rmin == -1 ) {
   Rmin= Rab;
   Number_of_Rmin= b;
  }
  if ( Rmin > Rab ) {
   Rmin= Rab;
   Number_of_Rmin= b;
  }
 }
 N_old= Number_of_Rmin;
 Rmin_old= Rmin;
 a0= tr.a[1];
 for ( Rmin= -1, b= 0; b < Number; b++ ) {
  if ( ( b == tr.a[0] ) || ( b == tr.a[1] ) )
   continue;
  Rab= ( star[a0].x - star[b].x ) * ( star[a0].x - star[b].x ) +
       ( star[a0].y - star[b].y ) * ( star[a0].y - star[b].y );
  // if( Rab < MATCH__MIN_SIZE_OF_TRIANGLE_PIX_SQUARED )continue;
  // if( Rab > MATCH__MAX_SIZE_OF_SMALL_TRIANGLE_PIX_SQUARED )continue;
  if ( Rmin == -1 ) {
   Rmin= Rab;
   Number_of_Rmin= b;
  }
  if ( Rmin > Rab ) {
   Rmin= Rab;
   Number_of_Rmin= b;
  }
 }
 if ( Rmin_old < Rmin )
  tr.a[2]= N_old;
 else
  tr.a[2]= Number_of_Rmin;
 return ( tr );
}

// This function will pre-compute sides of triangles in the array, so we don't waste time on it later...
static inline void Compute_sides_of_triangles( struct Triangle *tr, int Nt, struct Star *star ) {
 int n;
 float x1, x2, y1, y2;
 // for (n = 0; n < Nt; n++) {
 for ( n= Nt; n--; ) {
  x1= star[tr[n].a[0]].x;
  x2= star[tr[n].a[1]].x;
  y1= star[tr[n].a[0]].y;
  y2= star[tr[n].a[1]].y;
  tr[n].ab= ( x1 - x2 ) * ( x1 - x2 ) + ( y1 - y2 ) * ( y1 - y2 ); // first side of the first triangle
  x1= star[tr[n].a[1]].x;
  x2= star[tr[n].a[2]].x;
  y1= star[tr[n].a[1]].y;
  y2= star[tr[n].a[2]].y;
  tr[n].bc= ( x1 - x2 ) * ( x1 - x2 ) + ( y1 - y2 ) * ( y1 - y2 ); // second side of the first triangle
  x1= star[tr[n].a[2]].x;
  x2= star[tr[n].a[0]].x;
  y1= star[tr[n].a[2]].y;
  y2= star[tr[n].a[0]].y;
  tr[n].ac= ( x1 - x2 ) * ( x1 - x2 ) + ( y1 - y2 ) * ( y1 - y2 ); // third side of the first triangle
  tr[n].ab_bc_ac= tr[n].ab * tr[n].bc * tr[n].ac;
 }
 return;
}

/*
 This function will create a list of triangles from the input list of stars.
 These triangles may be used later to match star fields.
 */
struct Triangle *Separate_to_triangles( struct Star *star, int Number, int *Ntriangles ) {
 int n, m, *iskl;
 struct Triangle tr, *triangles= NULL;
 iskl= malloc( sizeof( int ) * Number );
 if ( iskl == NULL ) {
  fprintf( stderr, "ERROR in Separate_to_triangles:\n iskl = malloc(sizeof(int)*Number); - failed\n" );
  vast_report_memory_error();
  exit( EXIT_FAILURE );
 }
 for ( n= 0; n < Number; n++ ) {
  iskl[n]= n;
 }

 // Allocate memory for the array of Triangle-type structures which will contain... well, yaah, triangles...
 triangles= malloc( MATCH_MAX_NUMBER_OF_TRIANGLES * sizeof( struct Triangle ) );
 if ( triangles == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for triangles(ident_lib.c)\n" );
 }

 // For each star in the structure we create a few triangles containitng this star.
 // We need to create only few triangles, not all possible triangles containing this star.
 // Otherwise it would be a computational nightmare...

 // why 11 ? For each star we make 11 triangles
 // for ( n= 0, m= 0; n < Number - 11; n++ ) {
 for ( n= 0, m= 0; n < Number; n++ ) {

  // Special case: only three stars on image - make a single triangle of them and exit the loop
  if ( n == 0 && 3 == Number ) {
   fprintf( stderr, "Wow, this image actually has only three stars on it! Making a single triangle...\n" );
   m= 1;
   triangles[0].a[0]= iskl[0];
   triangles[0].a[1]= iskl[0 + 1];
   triangles[0].a[2]= iskl[0 + 2];
   break;
  }

  // If there only three stars left
  if ( n + 2 == Number ) {
   break;
  }
  //

  //  if ( m > MATCH_MAX_NUMBER_OF_TRIANGLES - 11 ) {
  //  if ( m > MATCH_MAX_NUMBER_OF_TRIANGLES - 22 ) {
  if ( m > MATCH_MAX_NUMBER_OF_TRIANGLES - TRIANGLES_PER_STAR ) {
   fprintf( stderr, "WARNING: upper limit for the number of triangles reached!\nMaybe you want to change the line \n#define MATCH_MAX_NUMBER_OF_TRIANGLES %d \nin src/vast_limits.h (you'll need to recompile the program with \"make\" for the change to take effect)\n", MATCH_MAX_NUMBER_OF_TRIANGLES );
   break;
  }

  // TRIANGLES_PER_STAR should match the code below!!!

  // We use a mixed strategy of separating list of stars to triangles.
  // First, for each reference star we construct a triangle from it and two closest reference stars.
  // This will produce a number of small triangles across the field of view.
  // Second, we construct triangles from reference stars with similar brightness.
  // This will produce a number of large triangles across the field.

  // Add triangles consisting of spatially close (reference) stars

  // If we have not too many reference stars... (otherwise this will take too long)
  if ( Number < MATCH_MAX_NUMBER_OF_STARS_FOR_SMALL_TRIANGLES ) {

   // This function will make a trianglefrom three nearby reference stars.
   tr= Create_One_Triangle_from_Nearby_Stars( star, Number, iskl[n] );

   m++;
   if ( triangles == NULL ) {
    fprintf( stderr, "ERROR in Separate_to_triangles:\n triangles = realloc(triangles, sizeof(struct Triangle) * m); - failed\n" );
    exit( EXIT_FAILURE );
   } // ???
   triangles[m - 1].a[0]= tr.a[0];
   triangles[m - 1].a[1]= tr.a[1];
   triangles[m - 1].a[2]= tr.a[2];
  }

  // fprintf(stderr,"DEBUUUG01: n=%d m=%d\n", n, m);

  // Add triangles consisting of stars with close brightness

  if ( n + 1 == Number ) {
   break;
  }

  // fprintf(stderr,"DEBUUUG02: n=%d m=%d\n", n, m);

  if ( n + 2 == Number ) {
   break;
  }

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 1];
  triangles[m - 1].a[2]= iskl[n + 2];

  // fprintf(stderr,"DEBUUUG03: n=%d m=%d\n", n, m);

  if ( n + 3 == Number ) {
   continue;
  }

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 1];
  triangles[m - 1].a[2]= iskl[n + 3];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 2];
  triangles[m - 1].a[2]= iskl[n + 3];

  // fprintf(stderr,"DEBUUUG04: n=%d m=%d\n", n, m);

  if ( n + 4 == Number ) {
   continue;
  }

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 1];
  triangles[m - 1].a[2]= iskl[n + 4];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 2];
  triangles[m - 1].a[2]= iskl[n + 4];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 3];
  triangles[m - 1].a[2]= iskl[n + 4];

  if ( n + 5 == Number ) {
   continue;
  }

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 1];
  triangles[m - 1].a[2]= iskl[n + 5];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 2];
  triangles[m - 1].a[2]= iskl[n + 5];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 3];
  triangles[m - 1].a[2]= iskl[n + 5];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 4];
  triangles[m - 1].a[2]= iskl[n + 5];

  /*
  // experimental stuff
  if ( n + 6 == Number ){
   continue;
  }

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 1];
  triangles[m - 1].a[2]= iskl[n + 6];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 2];
  triangles[m - 1].a[2]= iskl[n + 6];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 3];
  triangles[m - 1].a[2]= iskl[n + 6];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 4];
  triangles[m - 1].a[2]= iskl[n + 6];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 5];
  triangles[m - 1].a[2]= iskl[n + 6];

  if ( n + 7 == Number ){
   continue;
  }

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 1];
  triangles[m - 1].a[2]= iskl[n + 7];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 2];
  triangles[m - 1].a[2]= iskl[n + 7];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 3];
  triangles[m - 1].a[2]= iskl[n + 7];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 4];
  triangles[m - 1].a[2]= iskl[n + 7];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 5];
  triangles[m - 1].a[2]= iskl[n + 7];

  m++;
  triangles[m - 1].a[0]= iskl[n];
  triangles[m - 1].a[1]= iskl[n + 6];
  triangles[m - 1].a[2]= iskl[n + 7];

*/
 }
 // Fill-in .ab .ac .bc .ab_bc_ac fields in triangles array of structures.
 Compute_sides_of_triangles( triangles, m, star );
 //
 *Ntriangles= m;
 free( iskl );
 return ( triangles );
}

int Podobie( struct Preobr_Sk *preobr, struct Ecv_triangles *ecv_tr,
             struct Triangle *tr1, int Nt1,
             struct Triangle *tr2, int Nt2 ) {
 int n1, n2;
 float sigma, podobie, podobie1, ab1, bc1, ab2, bc2, ac2;

 sigma= preobr->sigma_podobia;
 for ( n1= 0; n1 < Nt1; n1++ ) {
  ab1= tr1[n1].ab;
  bc1= tr1[n1].bc;
  // fprintf(stderr,"\nDEBUUUG: tr1 %d-%d-%d \n", tr1[n1].a[0], tr1[n1].a[1], tr1[n1].a[2]);
  for ( n2= 0; n2 < Nt2; n2++ ) {

   // fprintf(stderr,"DEBUUUG: tr2 %d-%d-%d \n", tr2[n2].a[0], tr2[n2].a[1], tr2[n2].a[2]);

   // First, check if the triangles overall have the same scale
   // .ab_bc_ac is pre-computed by Compute_sides_of_triangles()
   podobie= tr1[n1].ab_bc_ac / tr2[n2].ab_bc_ac;
   if ( 0 != compare_two_floats_to_absolute_accuracy( podobie, 1.0, MAX_SCALE_FACTOR ) ) {
    continue;
   }
   // Once the overall scale is established to be the same, we need to match two specific sides
   // fprintf(stderr,"DEBUUUGtriangle 0\n");

   // Now try to match the specific sides of the triangles
   ab2= tr2[n2].ab;
   bc2= tr2[n2].bc;
   ac2= tr2[n2].ac;

   podobie1= ab1 / ab2;
   podobie1= podobie1 * podobie1 * podobie1;
   if ( 0 == compare_two_floats_to_absolute_accuracy( podobie1, podobie, sigma ) ) {
    podobie1= bc1 / bc2;
    podobie1= podobie1 * podobie1 * podobie1;
    if ( 0 == compare_two_floats_to_absolute_accuracy( podobie1, podobie, sigma ) ) {
     Add_ecv_triangles( ecv_tr, tr1[n1].a[0], tr1[n1].a[1], tr1[n1].a[2],
                        tr2[n2].a[0], tr2[n2].a[1], tr2[n2].a[2] ); //,
     continue;
    }
   }
   // fprintf(stderr,"DEBUUUGtriangle 1 %lf %lf %lf\n",podobie1, podobie, sigma);

   podobie1= ab1 / bc2;
   podobie1= podobie1 * podobie1 * podobie1;
   if ( 0 == compare_two_floats_to_absolute_accuracy( podobie1, podobie, sigma ) ) {
    podobie1= bc1 / ac2;
    podobie1= podobie1 * podobie1 * podobie1;
    if ( 0 == compare_two_floats_to_absolute_accuracy( podobie1, podobie, sigma ) ) {
     Add_ecv_triangles( ecv_tr, tr1[n1].a[0], tr1[n1].a[1], tr1[n1].a[2],
                        tr2[n2].a[1], tr2[n2].a[2], tr2[n2].a[0] ); //,
     continue;
    }
   }
   // fprintf(stderr,"DEBUUUGtriangle 2\n");

   podobie1= ab1 / bc2;
   podobie1= podobie1 * podobie1 * podobie1;
   if ( 0 == compare_two_floats_to_absolute_accuracy( podobie1, podobie, sigma ) ) {
    podobie1= bc1 / ab2;
    podobie1= podobie1 * podobie1 * podobie1;
    if ( 0 == compare_two_floats_to_absolute_accuracy( podobie1, podobie, sigma ) ) {
     Add_ecv_triangles( ecv_tr, tr1[n1].a[0], tr1[n1].a[1], tr1[n1].a[2],
                        tr2[n2].a[2], tr2[n2].a[0], tr2[n2].a[1] ); //,
     continue;
    }
   }
   // fprintf(stderr,"DEBUUUGtriangle 3\n");

   // new
   podobie1= ab1 / ac2;
   podobie1= podobie1 * podobie1 * podobie1;
   if ( 0 == compare_two_floats_to_absolute_accuracy( podobie1, podobie, sigma ) ) {
    podobie1= bc1 / ab2;
    podobie1= podobie1 * podobie1 * podobie1;
    if ( 0 == compare_two_floats_to_absolute_accuracy( podobie1, podobie, sigma ) ) {
     Add_ecv_triangles( ecv_tr, tr1[n1].a[0], tr1[n1].a[1], tr1[n1].a[2],
                        tr2[n2].a[2], tr2[n2].a[1], tr2[n2].a[0] ); //,
     continue;
    }
   }
   // fprintf(stderr,"DEBUUUGtriangle 4\n");

   podobie1= ab1 / ac2;
   podobie1= podobie1 * podobie1 * podobie1;
   if ( 0 == compare_two_floats_to_absolute_accuracy( podobie1, podobie, sigma ) ) {
    podobie1= bc1 / bc2;
    podobie1= podobie1 * podobie1 * podobie1;
    if ( 0 == compare_two_floats_to_absolute_accuracy( podobie1, podobie, sigma ) ) {
     Add_ecv_triangles( ecv_tr, tr1[n1].a[0], tr1[n1].a[1], tr1[n1].a[2],
                        tr2[n2].a[0], tr2[n2].a[2], tr2[n2].a[1] ); //,
     continue;
    }
   }
   // fprintf(stderr,"DEBUUUGtriangle 5\n");

   podobie1= ab1 / ab2;
   podobie1= podobie1 * podobie1 * podobie1;
   if ( 0 == compare_two_floats_to_absolute_accuracy( podobie1, podobie, sigma ) ) {
    podobie1= bc1 / ac2;
    podobie1= podobie1 * podobie1 * podobie1;
    if ( 0 == compare_two_floats_to_absolute_accuracy( podobie1, podobie, sigma ) ) {
     Add_ecv_triangles( ecv_tr, tr1[n1].a[0], tr1[n1].a[1], tr1[n1].a[2],
                        tr2[n2].a[1], tr2[n2].a[0], tr2[n2].a[2] ); //,
     continue;
    }
   }
   // fprintf(stderr,"DEBUUUGtriangle 6\n");
   //
  }
 }
 if ( ecv_tr->Number == 0 ) {
  return 0;
 }
 return 1;
}

/*
 This function computes how many stars can be matched between the two structures star1 and star2 containing
 Number1 and Number2 stars if the positional accuracy is sigma_popadaniya.
 */
static inline int Popadanie_star1_to_star2( struct Star *star1, int Number1, struct Star *star2, int Number2,
                                            double sigma_popadaniya ) {
 int n, m, popadanie= 0;

 float float_sigma_popadaniya= (float)sigma_popadaniya;

 float float_sigma_popadaniya_squared= float_sigma_popadaniya * float_sigma_popadaniya;

 // for (n = 0; n < Number1; n++)
 for ( n= Number1; n--; ) {
  // for (m = 0; m < Number2; m++) {
  for ( m= Number2; m--; ) {
   // the quick and dirty check
   // yes, check fabsf(a-b)>x is faster than checking if (a-b)>x and (b-a)>x
   if ( fabsf( star1[n].x - star2[m].x ) > float_sigma_popadaniya )
    continue;
   if ( fabsf( star1[n].y - star2[m].y ) > float_sigma_popadaniya )
    continue;
   // the correct check
   if ( ( star1[n].x - star2[m].x ) * ( star1[n].x - star2[m].x ) + ( star1[n].y - star2[m].y ) * ( star1[n].y - star2[m].y ) > float_sigma_popadaniya_squared )
    continue;
   popadanie++;
   break; // assume the first match is the right one
  }
 }
 return ( popadanie );
}

static inline float mean_distance__Popadanie_star1_to_star2( struct Star *star1, int Number1, struct Star *star2, int Number2,
                                                             double sigma_popadaniya ) {
 int n, m, popadanie= 0;

 float float_sigma_popadaniya= (float)sigma_popadaniya;

 float float_sigma_popadaniya_squared= float_sigma_popadaniya * float_sigma_popadaniya;

 float mean_distance= 0.0;

 // for (n = 0; n < Number1; n++)
 for ( n= Number1; n--; ) {
  // for (m = 0; m < Number2; m++) {
  for ( m= Number2; m--; ) {
   // the quick and dirty check
   // yes, check fabsf(a-b)>x is faster than checking if (a-b)>x and (b-a)>x
   if ( fabsf( star1[n].x - star2[m].x ) > float_sigma_popadaniya )
    continue;
   if ( fabsf( star1[n].y - star2[m].y ) > float_sigma_popadaniya )
    continue;
   // the correct check
   if ( ( star1[n].x - star2[m].x ) * ( star1[n].x - star2[m].x ) + ( star1[n].y - star2[m].y ) * ( star1[n].y - star2[m].y ) > float_sigma_popadaniya_squared )
    continue;
   popadanie++;
   mean_distance+= ( star1[n].x - star2[m].x ) * ( star1[n].x - star2[m].x ) + ( star1[n].y - star2[m].y ) * ( star1[n].y - star2[m].y );
   break; // assume the first match is the right one
  }
 }
 return ( sqrtf( mean_distance ) / (float)popadanie );
}

static inline int Popadanie_star1_to_star2__with_mean_distance( struct Star *star1, int Number1, struct Star *star2, int Number2,
                                                                double sigma_popadaniya, float *output_mean_distance ) {
 int n, m, popadanie= 0;

 float float_sigma_popadaniya= (float)sigma_popadaniya;

 float float_sigma_popadaniya_squared= float_sigma_popadaniya * float_sigma_popadaniya;

 float float_mean_distance_squared= 0.0;
 float float_distance_squared;

 // for (n = 0; n < Number1; n++)
 for ( n= Number1; n--; ) {
  // for (m = 0; m < Number2; m++) {
  for ( m= Number2; m--; ) {
   // the quick and dirty check
   // yes, check fabsf(a-b)>x is faster than checking if (a-b)>x and (b-a)>x
   if ( fabsf( star1[n].x - star2[m].x ) > float_sigma_popadaniya )
    continue;
   if ( fabsf( star1[n].y - star2[m].y ) > float_sigma_popadaniya )
    continue;
   // the correct check
   float_distance_squared= ( star1[n].x - star2[m].x ) * ( star1[n].x - star2[m].x ) + ( star1[n].y - star2[m].y ) * ( star1[n].y - star2[m].y );
   // if ( ( star1[n].x - star2[m].x ) * ( star1[n].x - star2[m].x ) + ( star1[n].y - star2[m].y ) * ( star1[n].y - star2[m].y ) > float_sigma_popadaniya_squared ) {
   if ( float_distance_squared > float_sigma_popadaniya_squared ) {
    continue;
   }
   popadanie++;
   // float_mean_distance_squared+=( star1[n].x - star2[m].x ) * ( star1[n].x - star2[m].x ) + ( star1[n].y - star2[m].y ) * ( star1[n].y - star2[m].y );
   float_mean_distance_squared+= float_distance_squared;
   break; // assume the first match is the right one
  }
 }
 //(*output_mean_distance)= sqrtf(float_mean_distance_squared)/(float)popadanie; // that's one funny way to output the accuracy
 ( *output_mean_distance )= sqrtf( float_mean_distance_squared / ( (float)popadanie ) ); // that's one funny way to output the accuracy
 return ( popadanie );
}

/*
// The old quick and dirty version
static inline int Popadanie_star1_to_star2(struct Star *star1, int Number1, struct Star *star2, int Number2,
                             double sigma_popadaniya) {
        int n, m, popadanie = 0;

        float float_sigma_popadaniya=(float)sigma_popadaniya;

        //for (n = 0; n < Number1; n++)
        for (n = Number1; n--; )
                //for (m = 0; m < Number2; m++) {
                for (m = Number2; m--; ) {
                        // yes, check fabsf(a-b)>x is faster than checking if (a-b)>x and (b-a)>x
                        if( fabsf(star1[n].x - star2[m].x) > float_sigma_popadaniya )continue;
                        if( fabsf(star1[n].y - star2[m].y) > float_sigma_popadaniya )continue;
                        popadanie++;
                        break; // assume the first match is the right one
                }
        return(popadanie);
}
*/

/*
 This function selects the best triangle and uses it to determine the coordinate transformation between the two frames.
 The best triangle is the one which allows to match the greatest number of reference stars.
 */
int Very_Well_triangle( struct Star *star1, int Number1, struct Star *star2, int Number2,
                        struct Ecv_triangles *ecv_tr,
                        struct Preobr_Sk *preobr, int *nm, int control1 ) {
 int n, Popadanie, Popadanie_max, m;
 double xmin, xmax, ymin, ymax, Ploshad, Ploshad1, sigma2;
 struct Star *copy_star1, *copy_star2;
 int N_ecv= 0;

 float mean_distance, mean_distance_best;

 copy_star1= malloc( sizeof( struct Star ) * Number1 );
 copy_star2= malloc( sizeof( struct Star ) * Number2 );

 if ( copy_star1 == NULL || copy_star2 == NULL ) {
  fprintf( stderr, "ERROR in Very_Well_triangle(): Out of memory while allocating copy_star1 or copy_star2\n" );
  vast_report_memory_error();
  exit( EXIT_FAILURE );
 }

 N_ecv= preobr->Number_of_ecv_triangle;
 if ( N_ecv > ecv_tr->Number )
  N_ecv= ecv_tr->Number;

 // for (n = 0; n < Number1; n++)
 for ( n= Number1; n--; )
  Star_Copy( copy_star1 + n, star1 + n );
 // for (n = 0; n < Number2; n++)
 for ( n= Number2; n--; )
  Star_Copy( copy_star2 + n, star2 + n );

 xmin= xmax= ymin= ymax= 0.0; // just to make compiler happy

 for ( n= 0; n < Number2; n++ ) {
  if ( n == 0 ) {
   xmin= copy_star2[n].x;
   xmax= copy_star2[n].x;
   ymin= copy_star2[n].y;
   ymax= copy_star2[n].y;
  } else {
   if ( xmin > copy_star2[n].x )
    xmin= copy_star2[n].x;
   if ( xmax < copy_star2[n].x )
    xmax= copy_star2[n].x;
   if ( ymin > copy_star2[n].y )
    ymin= copy_star2[n].y;
   if ( ymax < copy_star2[n].y )
    ymax= copy_star2[n].y;
  }
 }

 // Sort_Ecv_triangles(ecv_tr);

 Ploshad= ( xmax - xmin ) * ( ymax - ymin );
 ( *nm )= 0;
 Popadanie_max= 0;
 sigma2= preobr->sigma_popadaniya_multiple * preobr->sigma_popadaniya_multiple * preobr->sigma_popadaniya * preobr->sigma_popadaniya;
 mean_distance_best= 1e9; // to silance the gcc warning. Popadanie_max= 0; is what protects us from using mean_distance_best uninitialized

 // Cycle through triangles to identify the best one
 for ( n= 0; n < N_ecv; n++ ) {

  // Compute a linear transformation using a pair of ecvivalent triangles
  Star2_to_star1_on_main_triangle( preobr, copy_star1, Number1, copy_star2, Number2, ecv_tr, n );

  // Do not select triangles which imply large rotation if the user told us the frames are not rotated with respect to each other
  if ( control1 == 1 && fabs( preobr->fi ) > 0.052353 && fabs( preobr->fi - M_PI ) > 0.052353 )
   continue;

  // Scale(copy_star2, Number2, preobr->podobie);
  Translate( copy_star2, Number2, preobr->translate1[0], preobr->translate1[1] );
  Line_Preobr( copy_star2, Number2, preobr->line );
  Translate( copy_star2, Number2, preobr->translate2[0], preobr->translate2[1] );

  // Ploshad1 = Ploshad * preobr->podobie * fabs(preobr->line[0] * preobr->line[3] - preobr->line[1] * preobr->line[2]);
  Ploshad1= Ploshad * fabs( preobr->line[0] * preobr->line[3] - preobr->line[1] * preobr->line[2] );

  if ( Ploshad1 / (double)Number2 < sigma2 )
   continue;

  // Compute how many reference stars are successfully matched using the current triangle as the reference one
  // Popadanie= Popadanie_star1_to_star2( copy_star1, Number1, copy_star2, Number2, preobr->sigma_popadaniya );
  Popadanie= Popadanie_star1_to_star2__with_mean_distance( copy_star1, Number1, copy_star2, Number2, preobr->sigma_popadaniya, &mean_distance );
  // If we match the same number of stars, check if this is a better match (smaller position deviations)
  if ( Popadanie == Popadanie_max ) {
   // mean_distance= mean_distance__Popadanie_star1_to_star2( copy_star1, Number1, copy_star2, Number2, preobr->sigma_popadaniya );
   if ( mean_distance < mean_distance_best ) {
    Popadanie_max= Popadanie;
    ( *nm )= n;
    mean_distance_best= mean_distance;
   }
  }
  // If we can mutch more stars with this triangle - take it
  if ( Popadanie > Popadanie_max ) {
   Popadanie_max= Popadanie;
   ( *nm )= n;
   // mean_distance_best= mean_distance__Popadanie_star1_to_star2( copy_star1, Number1, copy_star2, Number2, preobr->sigma_popadaniya );
   mean_distance_best= mean_distance;
  }
  // for (m = 0; m < Number2; m++)
  for ( m= Number2; m--; )
   Star_Copy( copy_star2 + m, star2 + m );
 }

 if ( Popadanie_max != 0 ) {
  Star2_to_star1_on_main_triangle( preobr, star1, Number1, star2, Number2, ecv_tr, *nm );
 }
 free( copy_star1 );
 free( copy_star2 );
 return ( Popadanie_max );
}

int Star2_to_star1_on_main_triangle( struct Preobr_Sk *preobr, struct Star *star1, int Number1, struct Star *star2,
                                     int Number2, struct Ecv_triangles *ecv_tr, int nm ) {
 struct Star *star_copy;
 double X, Y, x, y, x1[2], y1[2], x2[2], y2[2];
 double d;
 int n;
 star_copy= malloc( sizeof( struct Star ) * Number2 );
 if ( star_copy == NULL ) {
  fprintf( stderr, "ERROR in Star2_to_star1_on_main_triangle(): star_copy = malloc(sizeof(struct Star) * Number2); - failed!\n" );
  vast_report_memory_error();
  exit( EXIT_FAILURE );
 }
 // for (n = 0; n < Number2; n++)
 for ( n= Number2; n--; )
  Star_Copy( star_copy + n, star2 + n );

 x= -star_copy[ecv_tr->tr[nm].tr2.a[0]].x;
 y= -star_copy[ecv_tr->tr[nm].tr2.a[0]].y;
 preobr->translate1[0]= x;
 preobr->translate1[1]= y;
 Translate( star_copy, Number2, x, y );

 X= -star1[ecv_tr->tr[nm].tr1.a[0]].x;
 Y= -star1[ecv_tr->tr[nm].tr1.a[0]].y;
 Translate( star1, Number1, X, Y );

 x1[1]= star1[ecv_tr->tr[nm].tr1.a[1]].x;
 y1[1]= star1[ecv_tr->tr[nm].tr1.a[1]].y;
 x2[1]= star1[ecv_tr->tr[nm].tr1.a[2]].x;
 y2[1]= star1[ecv_tr->tr[nm].tr1.a[2]].y;

 x1[0]= star_copy[ecv_tr->tr[nm].tr2.a[1]].x;
 y1[0]= star_copy[ecv_tr->tr[nm].tr2.a[1]].y;
 x2[0]= star_copy[ecv_tr->tr[nm].tr2.a[2]].x;
 y2[0]= star_copy[ecv_tr->tr[nm].tr2.a[2]].y;

 d= x1[0] * y2[0] - x2[0] * y1[0];
 preobr->line[0]= ( x1[1] * y2[0] - x2[1] * y1[0] ) / d;
 preobr->line[1]= -( x1[1] * x2[0] - x2[1] * x1[0] ) / d;
 preobr->line[2]= ( y1[1] * y2[0] - y2[1] * y1[0] ) / d;
 preobr->line[3]= -( y1[1] * x2[0] - y2[1] * x1[0] ) / d;

 preobr->fi= -atan( preobr->line[1] / preobr->line[0] );
 if ( ( preobr->fi >= 0 ) && ( preobr->line[1] >= 0 ) )
  preobr->fi+= M_PI;
 else if ( ( preobr->fi < 0 ) && ( preobr->line[1] < 0 ) )
  preobr->fi+= M_PI;

 preobr->translate2[0]= -X;
 preobr->translate2[1]= -Y;

 Translate( star1, Number1, -X, -Y );
 free( star_copy );
 return ( 1 );
}

typedef struct Point {
 int i;
 float x;
 float y;
 int moving_object;
} point;

typedef struct List {
 point p;
 struct List *next;
} *list;

typedef struct Frame1 {
 float minX;
 float minY;
 float sizeX;
 float sizeY;
 list points;
 int count;
} frame;

typedef struct Grid {
 list **array;
 int columns;
 int rows;
 float cellSize;
 float minX;
 float minY;
} *grid;

list emptyList( void ) {
 return NULL;
}

list addToList( point p, list l ) {
 list newL;
 newL= malloc( sizeof( struct List ) );
 if ( newL == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for newL(ident_lib.c)\n" );
  exit( EXIT_FAILURE );
 };
 newL->p= p;
 newL->next= l;
 return newL;
}

point disjoinList( list *l ) {
 point p;
 p= ( *l )->p;
 *l= ( *l )->next;
 return ( p );
}

int lengthList( list l ) {
 int j= 0;
 while ( l != NULL ) {
  j++;
  disjoinList( &l );
 }
 return j;
}

int isEmpty( list l ) {
 if ( l == NULL )
  return 1;
 else
  return 0;
}

void freeList( list l ) {
 list x;
 while ( isEmpty( l ) == 0 ) {
  x= l->next;
  free( l );
  l= x;
 }
}

void pointToCell( grid gr, double x, double y, int *col, int *row ) {
 *col= (int)( x - gr->minX ) / gr->cellSize;
 *row= (int)( y - gr->minY ) / gr->cellSize;
}

grid createGrid( frame f ) {
 grid gr;
 float minX, minY, maxX, maxY, cellSize;
 int columns, rows, i, j;
 list points;
 point p;

 gr= malloc( sizeof( struct Grid ) );
 if ( gr == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for gr(ident_lib.c)\n" );
  exit( EXIT_FAILURE );
 };
 cellSize= sqrtf( f.sizeX * f.sizeY / ( (float)f.count ) );

 minX= f.minX - f.sizeX;
 minY= f.minY - f.sizeY;
 maxX= minX + 3 * f.sizeX;
 maxY= minY + 3 * f.sizeY;

 gr->minX= minX;
 gr->minY= minY;
 gr->cellSize= cellSize;

 pointToCell( gr, maxX, maxY, &columns, &rows );
 columns++;
 rows++;

 gr->columns= columns;
 gr->rows= rows;

 if ( gr->columns <= 0 ) {
  fprintf( stderr, "ERROR: Trying allocate zero or negative bytes amount(ident_lib.c)\n" );
  exit( EXIT_FAILURE );
 };

 // fprintf(stderr,"minX: %lf, minY: %lf, maxX: %lf, maxY: %lf, cellSize: %lf, columns: %d, rows: %d, count: %d\n", minX, minY, maxX, maxY, cellSize, columns, rows, f.count);

 gr->array= malloc( sizeof( list ** ) * columns );
 if ( gr->array == NULL ) {
  fprintf( stderr, "ERROR: Couldn't allocate memory for gr->array(ident_lib.c)\n" );
  exit( EXIT_FAILURE );
 };
 for ( i= 0; i < columns; i++ ) {
  gr->array[i]= malloc( sizeof( list * ) * rows );
  if ( gr->array[i] == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for gr->array[i](ident_lib.c)\n" );
   exit( EXIT_FAILURE );
  };
  for ( j= 0; j < rows; j++ ) {
   gr->array[i][j]= emptyList();
  }
 }

 points= f.points;
 while ( isEmpty( points ) == 0 ) {
  p= disjoinList( &points );
  pointToCell( gr, p.x, p.y, &i, &j );
  gr->array[i][j]= addToList( p, gr->array[i][j] );
 }
 return gr;
}

list getListFromGrid( grid gr, double x, double y ) {
 int ic, jc, i_min, j_min, i_max, j_max;
 int i, j;
 list ps1, ps2;
 point p;

 pointToCell( gr, x, y, &ic, &jc );
 i_min= MAX( ic - 1, 0 );
 j_min= MAX( jc - 1, 0 );
 i_max= MIN( ic + 1, gr->columns - 1 );
 j_max= MIN( jc + 1, gr->rows - 1 );

 ps2= emptyList();
 for ( i= i_min; i <= i_max; i++ ) {
  for ( j= j_min; j <= j_max; j++ ) {
   ps1= gr->array[i][j];
   while ( isEmpty( ps1 ) == 0 ) {
    p= disjoinList( &ps1 );
    ps2= addToList( p, ps2 );
   }
  }
 }
 // printf("i = %d, j = %d\n", ic, jc);
 return ( ps2 );
}

// we are getting all stars, so no need for x,y
list getListFromGrid__getAllStarsNevermindGrid( grid gr ) {
 // int ic, jc, i_min, j_min, i_max, j_max;
 int i_min, j_min, i_max, j_max;
 int i, j;
 list ps1, ps2;
 point p;

 i_min= 0;               // MAX(ic - 1, 0);
 j_min= 0;               // MAX(jc - 1, 0);
 i_max= gr->columns - 1; // MIN(ic + 1, gr->columns - 1);
 j_max= gr->rows - 1;    // MIN(jc + 1, gr->rows - 1);

 ps2= emptyList();
 for ( i= i_min; i <= i_max; i++ ) {
  for ( j= j_min; j <= j_max; j++ ) {
   ps1= gr->array[i][j];
   while ( isEmpty( ps1 ) == 0 ) {
    p= disjoinList( &ps1 );
    ps2= addToList( p, ps2 );
   }
  }
 }
 // printf("i = %d, j = %d\n", ic, jc);
 return ( ps2 );
}

void freeGrid( grid gr ) {
 int i, j;
 //  list ps;
 //  point p;
 for ( i= 0; i < gr->columns; i++ ) {
  // if(NULL==gr->array[i]){fprintf(stderr, "FUCK YEAH: %d\n", i);continue;} // !!!
  for ( j= 0; j < gr->rows; j++ ) {
   freeList( gr->array[i][j] );
  }
  // fprintf(stderr, "Free iarray: %d\n", i);
  free( gr->array[i] );
 }
 // fprintf(stderr, "Free array\n");
 // if(NULL!=gr->array) // !!!
 free( gr->array );
 // fprintf(stderr, "Free gr\n");
 free( gr );
}

list loadPoint( struct Star *star, int number ) {
 list l;
 point p;
 int i= 0;
 for ( l= emptyList(), i= 0; i < number; i++ ) {
  p.x= star[i].x;
  p.y= star[i].y;
  p.i= i;
  p.moving_object= star[i].moving_object;
  l= addToList( p, l );
 }
 return ( l );
}

frame createFrame( double minX, double minY, double sizeX, double sizeY, list points ) {
 frame f;
 f.minX= minX;
 f.minY= minY;
 f.sizeX= sizeX;
 f.sizeY= sizeY;
 f.points= points;
 f.count= lengthList( points );
 return f;
}

void change( int *a, int *b ) {
 int q;
 q= *a;
 *a= *b;
 *b= q;
}

/* NO, sadly this is not faster
static inline int isNumberInIntArray(int *array, int n_elements, int number_to_check){
 int i,return_value;
 return_value=-1;
 #ifdef VAST_ENABLE_OPENMP
  #ifdef _OPENMP
   #pragma omp parallel for private(i)
  #endif
 #endif
 for(i=0;i<n_elements;i++){
  if( array[i] == number_to_check ){
   return_value=i;
  }
 }
 return return_value;
}
*/
/*
static inline int isNumberInIntArray(int *array, int n_elements, int number_to_check){
    int return_value = -1;
    int i;

    #pragma omp parallel for private(i) shared(return_value)
    for(i = 0; i < n_elements; i++) {
        #pragma omp flush(return_value)
        if(return_value != -1) {
            continue; // skip iteration if another thread has found the number
        }

        if(array[i] == number_to_check) {
            #pragma omp critical
            {
                // Update return_value if not already set
                if(return_value == -1) {
                    return_value = i;
                }
            }
            #pragma omp flush(return_value)
        }
    }
    return return_value;
}
*/

// The reference version that works fine
static inline int isNumberInIntArray( int *array, int n_elements, int number_to_check ) {
 int i;
 // Actually tests show that we make fewer operations when going from 0 to n_elements, not the other way
 // for(i=n_elements;i--;){
 for ( i= 0; i < n_elements; i++ ) {
  if ( array[i] == number_to_check ) {
   return i;
  }
 }
 return -1;
}


/*

 This function will match stars in two strctures (star1 and star2) based on their positional coincidence.
 The coordinate transformation needs to be applied to the structure star2 before running this function, so coordinates in
 star1 and star2 are in the same frame and may be directly compared.

*/

int Ident_on_sigma( struct Star *star1, int Number1, struct Star *star2, int Number2, int *Pos1, int *Pos2, double sigma_popadaniya, double image_size_X, double image_size_Y ) {
 float R_best, R, epsilon;
 int find_flag, number_of_matched_stars, q;
 frame fr;
 grid gr;
 list points1, points2, points_2, ps, ps_1;
 list xs_matched, ys_matched, ys_unmatched;
 list xs_matched_, ys_matched_, ys_unmatched_;

 point p1, p2, p_best;

 int previous_number_in_array;

 int number_of_ambiguous_matches= 0;
 double fraction_of_ambiguous_matches;

 epsilon= sigma_popadaniya * sigma_popadaniya;

 points1= loadPoint( star1, Number1 );
 points2= loadPoint( star2, Number2 );

 // Create frame with stars on it
 fr= createFrame( 0, 0, image_size_X, image_size_Y, points1 );
 // Create the spatial indexin grid
 gr= createGrid( fr );

 points_2= points2;

 xs_matched= emptyList();
 ys_matched= emptyList();
 ys_unmatched= emptyList();

 //  number_of_matched_stars=0;
 while ( isEmpty( points_2 ) == 0 ) {
  R_best= epsilon;
  find_flag= 0;
  p2= disjoinList( &points_2 );
  // ps= getListFromGrid(gr, p2.x, p2.y);
  // ps_1= ps;
  //  First, check the user-specified moving object
  if ( p2.moving_object == 1 ) {
   // If this is a moving object - we want to match it against all objects on the reference frame without using the spatial indexing.
   // The moving object might have moved out of its original indexing square by now.
   ps= getListFromGrid__getAllStarsNevermindGrid( gr );
   ps_1= ps;
   // fprintf(stderr, "\n\n\nDEBUG: YES HERE IS THE MOVING OBJECT IN P2  (%f,%f)\n\n\n",p2.x,p2.y);
   while ( isEmpty( ps_1 ) == 0 ) {
    p1= disjoinList( &ps_1 );
    // WE NEED TO CHECK ALL STARS, NOT JUST THE ONES IN THE SAME SPATIAL SEGMENT
    // Manually match the moving object using the flag (we assume there is only one moving object on the series of images)
    if ( p1.moving_object == 1 ) {
     find_flag= 1;
     p_best= p1;
     R_best= 0.0;
     // fprintf(stderr, "DEBUG: --- HERE IT IS IN P1  (%f,%f)\n\n\n",p1.x,p1.y);
     // break; // we probably can break here as we need to empty ps_1
    }
   }
  } else {
   // Second - the normal route - coordinate-based match
   ps= getListFromGrid( gr, p2.x, p2.y );
   ps_1= ps;
   while ( isEmpty( ps_1 ) == 0 ) {
    p1= disjoinList( &ps_1 );
    // do not allow moving object to participate in positional match!
    if ( p1.moving_object == 1 ) {
     continue;
    }
    //
    R= ( p2.x - p1.x ) * ( p2.x - p1.x ) + ( p2.y - p1.y ) * ( p2.y - p1.y );
    if ( R < R_best ) { // && R<star1[p1.i].distance_to_neighbor_squared && R<star2[p2.i].distance_to_neighbor_squared) {
     find_flag= 1;
     p_best= p1;
     R_best= R;
    }
   }
  }
  if ( find_flag == 1 ) {
   xs_matched= addToList( p_best, xs_matched );
   ys_matched= addToList( p2, ys_matched );
  } else {
   //
   // if ( fabs(p1.x - 1494.6) < 1.0 && fabs(p1.y - 2081.4) < 1.0 ){
   // fprintf( stderr, "\n--- NO MATCH!!!   p2.i=%d R=%lf R_best=%lf  p2.x=%lf p2.x=%lf  \n", p2.i, sqrt(R), sqrt(R_best), p2.x, p2.y );
   // exit( EXIT_FAILURE );
   //}
   //
   ys_unmatched= addToList( p2, ys_unmatched );
  }
  freeList( ps );
 }

 xs_matched_= xs_matched;
 ys_matched_= ys_matched;
 number_of_matched_stars= 0;
 while ( isEmpty( xs_matched_ ) == 0 ) {
  p1= disjoinList( &xs_matched_ );
  p2= disjoinList( &ys_matched_ );
  // if the star was not matched with another star before
  previous_number_in_array= isNumberInIntArray( Pos1, number_of_matched_stars, p1.i );
  if ( -1 == previous_number_in_array ) {
   //
   if ( number_of_matched_stars >= Number1 ) {
    fprintf( stderr, "ERROR in Ident_on_sigma(): number_of_matched_stars>=Number1 while it shouldn't\n" );
    exit( EXIT_FAILURE );
   }
   if ( number_of_matched_stars >= Number2 ) {
    fprintf( stderr, "ERROR in Ident_on_sigma(): number_of_matched_stars>=Number2 while it shouldn't\n" );
    exit( EXIT_FAILURE );
   }
   //
   //
   //   if ( fabs(p1.x - 1125.732) < 1.0 && fabs(p1.y - 1675.50) < 1.0 ){
   //     fprintf( stderr, "\nmmm p1.x=%lf p1.y=%lf  p2.i=%d R=%lf R_best=%lf  p2.x=%lf p2.x=%lf\n", p1.x, p1.y, p2.i, sqrt(R), sqrt(R_best), p2.x, p2.y );
   //   }
   //
   // write it as matched
   Pos1[number_of_matched_stars]= p1.i;
   Pos2[number_of_matched_stars]= p2.i;
   number_of_matched_stars++;
  } else {
   // this star has a better match, so this match is wrong
   // WHY DO YOU THINK THE PREVIOUS MATCH IS THE BETTER ONE?
   ys_unmatched= addToList( p2, ys_unmatched );
   //
   // fprintf(stderr, "AMBIGUOUS MATCH: p1.i=%d p1.x=%lf p1.y=%lf   p2.i=%d p2.x=%lf p2.y=%lf\n", p1.i, p1.x, p1.y, p2.i, p2.x, p2.y);
   number_of_ambiguous_matches++;
   //
  }
 }

 ys_unmatched_= ys_unmatched;

 q= number_of_matched_stars;
 while ( isEmpty( ys_unmatched_ ) == 0 ) {
  p2= disjoinList( &ys_unmatched_ );
  Pos2[q]= p2.i;
  q++;
 }

 freeList( xs_matched );
 freeList( ys_matched );
 freeList( ys_unmatched );

 freeGrid( gr );
 freeList( points2 );
 freeList( points1 );

 if ( number_of_matched_stars > 0 ) {
  // fraction_of_ambiguous_matches= (double)number_of_ambiguous_matches / (double)number_of_matched_stars;
  //  The above does not work well if the new frame is much better than the reference frame, as one may get lots of ambiguous matches.
  //  The test case is NMWSGR9CRASH_ERROR_MESSAGE_IN_index_html
  //  cp default.sex.telephoto_lens_v5 default.sex
  //  ./vast --starmatchraius 4.0 --matchstarnumber 500 --selectbestaperture --sysrem 1 --poly --maxsextractorflag 99 --UTC --nofind --nojdkeyword ../NMW_Sgr9_crash_test/reference_images//Sgr9_2012-4-13_1-2-28_001.fts ../NMW_Sgr9_crash_test/reference_images//Sgr9_2012-4-18_0-37-34_003.fts ../NMW_Sgr9_crash_test/second_epoch_images/Sgr9_2020-9-1_17-35-4_002.fts ../NMW_Sgr9_crash_test/second_epoch_images/Sgr9_2020-9-1_17-35-35_003.fts
  fraction_of_ambiguous_matches= (double)number_of_ambiguous_matches / (double)MAX( Number1, Number2 );
 } else {
  // things are bad anyhow - we have zero matched stars
  fraction_of_ambiguous_matches= 0.0;
 }
 if ( fraction_of_ambiguous_matches > MAX_FRACTION_OF_AMBIGUOUS_MATCHES && number_of_ambiguous_matches > MIN_NUMBER_OF_AMBIGUOUS_MATCHES_TO_TAKE_ACTION ) {
  fprintf( stderr, "ERROR: ambiguous match for too many stars!!!\n" );
  fprintf( stderr, "fraction_of_ambiguous_matches= %lf, number_of_ambiguous_matches=%d \n", fraction_of_ambiguous_matches, number_of_ambiguous_matches );
  number_of_matched_stars= 0;
 }
 //
 fprintf( stderr, "fraction_of_ambiguous_matches= %lf, number_of_ambiguous_matches=%d \n", fraction_of_ambiguous_matches, number_of_ambiguous_matches );
 //

 return number_of_matched_stars;
}

/*
void set_distance_to_neighbor_in_struct_Star(struct Star *star, int NUMBER, double aperture, double image_size_X, double image_size_Y){
 float R_best, R, epsilon;
 frame fr;
 grid gr;
 list points1, points2, points_2, ps, ps_1;
 point p1, p2;//, p_best;

 epsilon = 4.0*(float)aperture*(float)aperture;

 points1 = loadPoint (star, NUMBER);
 points2 = loadPoint (star, NUMBER);

 fr = createFrame(0, 0, image_size_X, image_size_Y, points1);
 gr = createGrid(fr);

 points_2 = points2;

 while(isEmpty (points_2) == 0){
  R_best = epsilon;
  p2 = disjoinList(&points_2);
  ps = getListFromGrid(gr, p2.x, p2.y);
  ps_1 = ps;
  while (isEmpty (ps_1) == 0) {
   p1 = disjoinList(&ps_1);
   R = (p2.x - p1.x) * (p2.x - p1.x) + (p2.y - p1.y) * (p2.y - p1.y);
   if (R < R_best && p1.i!=p2.i ) {
    star[p1.i].distance_to_neighbor_squared = R_best = R;
   }
  }
  freeList (ps);
 }

 freeGrid (gr);
 freeList (points2);
 freeList (points1);

 return;
}
*/

/*

 This function will match stars in two strctures (star1 and star2) based on their positional coincidence.
 The coordinate transformation needs to be applied to sthe structure star2 before running this function, so coordinates in
 star1 and star2 are in the same system and may be directly compared.

  OLD VERSION KEPT FOR REFERENCE

*/

/*
int Ident_on_sigma(struct Star *star1, int Number1, struct Star *star2, int Number2, int *St1, int *St2, double sigma_popadaniya, double image_size_X, double image_size_Y) {
        struct Star s, *copy_star1, *copy_star2;

        int n, m, Num, q;
        double R, sigma;

        double R_best; // distance to the best match (in pixels)

        copy_star1 = malloc(sizeof(struct Star) * Number1);
        copy_star2 = malloc(sizeof(struct Star) * Number2);

        if( copy_star1==NULL || copy_star2==NULL ){fprintf(stderr,"ERROR in Ident_on_sigma(): Out of memory while allocating copy_star1 or copy_star2\n");vast_report_memory_error();exit( EXIT_FAILURE );}

        //for (n = 0; n < Number1; n++)
        for (n = Number1; n--; )
                (St1)[n] = n;
        //for (n = 0; n < Number2; n++)
        for (n = Number2; n--; )
                (St2)[n] = n;

        //for (n = 0; n < Number1; n++)
        for (n = Number1; n--; )
                Star_Copy(copy_star1 + n, star1 + n);
        //for (n = 0; n < Number2; n++)
        for (n = Number2; n--; )
                Star_Copy(copy_star2 + n, star2 + n);

        sigma = sigma_popadaniya * sigma_popadaniya;
        Num = 0;
        int j_detect;
        for (n = 0; n < Number1 && n < Number2; n++) {
                j_detect = 0;
                R_best = -1.0;
                for (m = Num; m < Number2; m++) {
                        // A miserable attempt to make some optimization
                        // !!! compare_float??? !!!
                        if( copy_star1[n].x - copy_star2[m].x > sigma_popadaniya )continue;
                        if( copy_star2[m].x - copy_star1[n].x > sigma_popadaniya )continue;
                        if( copy_star1[n].y - copy_star2[m].y > sigma_popadaniya )continue;
                        if( copy_star2[m].y - copy_star1[n].y > sigma_popadaniya )continue;
                        // end of the miserable attempt to make some optimization
                        R = (copy_star1[n].x - copy_star2[m].x) * (copy_star1[n].x - copy_star2[m].x) + (copy_star1[n].y - copy_star2[m].y) * (copy_star1[n].y - copy_star2[m].y);
                        if ( R<=sigma && R<copy_star1[n].distance_to_neighbor_squared && R<copy_star2[m].distance_to_neighbor_squared ) {
                                // If this is the first star which falls inside the search circle
                                if (R_best == -1.0) {
                                        R_best = R;
                                        Num++;
                                }
                                // If this is the current best match...
                                if (R <= R_best) {
                                        R_best = R;
                                        Star_Copy(&s, copy_star2 + n);
                                        Star_Copy(copy_star2 + n, copy_star2 + m);
                                        Star_Copy(copy_star2 + m, &s);
                                        q = (St2)[n];
                                        (St2)[n] = (St2)[m];
                                        (St2)[m] = q;
                                        j_detect = 1;
                                }
                        }
                }

                // If the star was not matched...
                if (j_detect == 0) {
                        Star_Copy(&s, copy_star1 + n);
                        q = St1[n];
                        for (m = 0; m < Number1 - 1 - n; m++) {
                                Star_Copy(copy_star1 + n + m, copy_star1 + n + m + 1);
                                (St1)[n+m] = (St1)[n+m+1];
                        }
                        Number1--;
                        n--;
                        Star_Copy(copy_star1 + Number1, &s);
                        St1[Number1] = q;
                }
        }

        free(copy_star1);
        free(copy_star2);
        return(Num);
}
*/

/*

 Ident() is the main function for star identification. It takes three arrays of Star type structures as an input:
 STAR1, NUMBER1 - all stars considered in the analysis (detected on the reference frame with all acceptable SExtractor
 flags + stars detected on other frames);
 STAR2, NUMBER2 - stars detected on the current frame;
 STAR3, NUMBER3 - structure of reference stars, it contains only good (SExtractor flag =0) stars detected on the reference frame.
 It is better to use the clean list of reference stars (STAR3) for the initial image matching to make the process more stable.
 After the initial coordinate transformation has been established, the stars are matched against the full list of considered stars (STAR1).

 */
// int Ident(struct Preobr_Sk *preobr, struct Star *STAR1, int NUMBER1, struct Star *STAR2, int NUMBER2, int START_NUMBER2,
//         struct Frame frame1, struct Frame frame2, int *Pos1, int *Pos2, int control1, struct Star *STAR3, int NUMBER3, int START_NUMBER3, int *match_retry, int min_number_of_matched_stars, double image_size_X, double image_size_Y ) {
int Ident( struct Preobr_Sk *preobr, struct Star *STAR1, int NUMBER1, struct Star *STAR2, int NUMBER2, int START_NUMBER2,
           int *Pos1, int *Pos2, int control1, struct Star *STAR3, int NUMBER3, int START_NUMBER3, int *match_retry, int min_number_of_matched_stars, double image_size_X, double image_size_Y ) {

 struct Star *star1= NULL, *star2= NULL;
 struct Triangle *tr1, *tr2;
 struct Ecv_triangles *ecv_tr;
 int Number1, Number2, key, n, Nt1, Nt2, nm;

 // Set the number of reference stars based on the requested nuber supplied to his function as preobr->Number_of_main_star .
 Number1= (int)( (double)( preobr->Number_of_main_star ) * (double)NUMBER2 / (double)NUMBER3 ); // if we have more stars on one frame than on the other - it is likely that this frame is just taken with a longer exposure...
 if ( Number1 < MATCH_MIN_NUMBER_OF_REFERENCE_STARS ) {
  Number1= MATCH_MIN_NUMBER_OF_REFERENCE_STARS;
 }
 Number2= preobr->Number_of_main_star;
 // New test for very few star images
 if ( Number2 == 0 ) {
  ( *match_retry )= 0;
  return 0;
 }
 //
 if ( Number1 > NUMBER3 - START_NUMBER3 ) {
  Number1= NUMBER3 - START_NUMBER3;
 }
 if ( Number2 > NUMBER2 - START_NUMBER2 ) {
  Number2= NUMBER2 - START_NUMBER2;
 }

 // Just a test
 if ( Number1 == 0 || Number2 == 0 ) {
  ( *match_retry )= 1;
  return 0;
 }

 // Here we create arrays of stars detected on the two frames (3 - reference frame, 2 - current frame).
 // Number - number of reference stars. NUMBER - number of all detected stars (Number<=NUMBER).
 star1= malloc( sizeof( struct Star ) * NUMBER3 );
 star2= malloc( sizeof( struct Star ) * NUMBER2 );
 if ( ( star1 == NULL ) || ( star2 == NULL ) ) {
  fprintf( stderr, "ERROR in Ident(): No enough memory for two arrays of stars!\n" );
  vast_report_memory_error();
  exit( EXIT_FAILURE );
 }
 // Now we make local copies of the reference star list (STAR3) and the list of stars detected on the current image
 // (STAR2). We may be requested to skip the first START_NUMBER3 or START_NUMBER2 stars in the structure if needed.
 int m;
 for ( n= START_NUMBER3, m= 0; n < NUMBER3; n++, m++ )
  Star_Copy( star1 + m, STAR3 + n );
 for ( n= START_NUMBER2, m= 0; n < NUMBER2; n++, m++ )
  Star_Copy( star2 + m, STAR2 + n );

 ecv_tr= Init_ecv_triangles(); // Initialize tructure which will store similar triangles.
 // fprintf(stderr,"DEBUUUG - tr1= Separate_to_triangles(star1, Number1, &Nt1); \n");
 tr1= Separate_to_triangles( star1, Number1, &Nt1 ); // Create a list of triangles from stars detected on the reference frame.
 // fprintf(stderr,"DEBUUUG - tr2= Separate_to_triangles(star2, Number2, &Nt2); \n");
 tr2= Separate_to_triangles( star2, Number2, &Nt2 ); // Create a list of triangles from stars detected on the current frame.
 // fprintf(stderr,"DEBUUUG - write_Star_struct_to_ds9_region_file() \n");
 // fprintf(stderr,"DEBUUUG - Nt1=%d Nt2=%d\n", Nt1, Nt2);
 //  DEBUG !!!
 // write_Star_struct_to_ds9_region_file(star1, 0, Number1, "star1.reg", 6.6);
 // write_Star_struct_to_ds9_region_file(star2, 0, Number2, "star2.reg", 6.6);

 // Search for similar triangles
 key= Podobie( preobr, ecv_tr, tr1, Nt1, tr2, Nt2 );
 // fprintf(stderr,"DEBUUUG Podobie()=%d", key);
 fprintf( stderr, "    %5d * detected, using %4d/%4d * for reference/current image matching, ", NUMBER2, Number1, Number2 );

 // Select the best trianle which allows to match the largest number of reference stars and determine the corrdinate transormation
 // using this best triangle. This coordinate tresformation is returned as the structure preobr .
 if ( key != 0 ) {
  key= Very_Well_triangle( star1, Number1, star2, Number2, ecv_tr, preobr, &nm, control1 );
 }

 // Free-up memory related to the triangles.
 Delete_Ecv_triangles( ecv_tr );
 free( tr1 );
 free( tr2 );

 // QUICK FIX !!!
 // This is needed if star1 or star2 are not exact copies of the corresponding structure arrays STAR3 and STAR2
 // but are missing the first START_NUMBER3 or START_NUMBER2 stars (this trick may be needed for correct image identification).
 if ( START_NUMBER2 != 0 ) {
  for ( n= 0, m= 0; n < NUMBER2; n++, m++ )
   Star_Copy( star2 + m, STAR2 + n );
 }
 if ( START_NUMBER3 != 0 ) {
  for ( n= 0, m= 0; n < NUMBER3; n++, m++ )
   Star_Copy( star1 + m, STAR3 + n );
 }

 // Apply the coordinate transformation to the list of stars detected on the current frame.
 Translate( star2, NUMBER2, preobr->translate1[0], preobr->translate1[1] );
 Line_Preobr( star2, NUMBER2, preobr->line );
 Translate( star2, NUMBER2, preobr->translate2[0], preobr->translate2[1] );

 // User may inicate that the frames are not rotated with trespect to each other. Here is the bad place to check it.
 // For the good check, control1 parameter is transmitted to the function Very_Well_triangle()
 if ( control1 == 1 && fabs( preobr->fi ) > 0.052353 && fabs( preobr->fi - M_PI ) > 0.052353 ) {
  fprintf( stderr, " rotation is large! Retrying...  %lf\n", 180 * preobr->fi / M_PI );

  // We don't want to exit without freeing the memory allocated for te sturctures
  free( star1 );
  free( star2 );

  ( *match_retry )= 1; // !!
  return 0;
 }

 // Check if the current frame is the same as the reference frame. This will be apparent by the rotation probr->fi=180.0 degrees.
 if ( fabs( 180 * preobr->fi / M_PI - 180.0 ) < 0.0001 ) {
  fprintf( stderr, " rotation is exactly 180 degrees! Is this a reference image again? Dropping image!  %lf\n", 180 * preobr->fi / M_PI );

  // We don't want to exit without freeing the memory allocated for te sturctures
  free( star1 );
  free( star2 );

  return 0;
 }

 // If enough stars are detected on the current frame... (If not, it may be a bad frame with clouds etc.)
 if ( NUMBER2 > MIN_NUMBER_OF_STARS_ON_FRAME ) {
  // star1 -> STAR1
  // Note, at this point we assume we have a reasonably good coordinate transofrmation
  // based on the best similar triangle constructed from the reference stars. The following
  // function will apply the transformation to match stars in structures STAR2 and STAR1.
  nm= Ident_on_sigma( STAR1, NUMBER1, star2, NUMBER2, Pos1, Pos2, preobr->sigma_popadaniya, image_size_X, image_size_Y );

  // If the match is bad - exit and retry.
  if ( nm < min_number_of_matched_stars ) {
   fprintf( stderr, "Too few * matched: %d < %d ! Retrying...\n", nm, min_number_of_matched_stars );
   ( *match_retry )= 1; // !!

   // We don't want to exit without freeing the memory allocated for the sturctures
   free( star1 );
   free( star2 );

   return nm; // 0;
  }

  // Now, if the match is good - we try to further refine the coordinate transoformation
  // if ( nm >= min_number_of_matched_stars ) {
  fprintf( stderr, "refining the coordinate transformation... " );
  float dx, dy;                                                // coordinate corrections for a given star
  unsigned int ii, iii;                                        // counters
  double Ax, Bx, Cx, Ay, By, Cy;                               // coefficients for the two planes which will describe the residuals
                                                               // in x (dx=Ax*x+Bx*y+Cx) and y (dy=Ay*x+By*y+Cy).
                                                               // We will fit these two planes to the remaining systematic
                                                               // residuals (dx,dy) and will compensate for them.
  double *x= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) ); // x coordinate of stars on the current frame
  if ( x == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for x(ident_lib.c)\n" );
   exit( EXIT_FAILURE );
  };
  double *y= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) ); // y coordinate of stars on the current frame
  if ( y == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for x(ident_lib.c)\n" );
   exit( EXIT_FAILURE );
  };
  double *z= malloc( MAX_NUMBER_OF_STARS * sizeof( double ) ); // difference between the measured coordinates
                                                               // and thouse assumed to be correct (measured
                                                               // on the reference frame or avarage star position
                                                               // from multiple frames (in the reference frame coordinate system).

  if ( z == NULL ) {
   fprintf( stderr, "ERROR: Couldn't allocate memory for x(ident_lib.c)\n" );
   exit( EXIT_FAILURE );
  };

  // Fit a plane to x residuals
  for ( iii= 0, ii= 0; ii < (unsigned int)nm; ii++ ) {
   if ( star2[Pos2[ii]].moving_object == 0 ) {
    x[iii]= star2[Pos2[ii]].x_frame;
    y[iii]= star2[Pos2[ii]].y_frame;
    z[iii]= star2[Pos2[ii]].x - STAR1[Pos1[ii]].x;
    iii++;
   }
  }
  fit_plane_lin( x, y, z, iii, &Ax, &Bx, &Cx );
  // fprintf(stderr,"dx=(%lf)*x+(%lf)*y+(%lf)\n",Ax,Bx,Cx);

  // Fit a plane to y residuals
  for ( iii= 0, ii= 0; ii < (unsigned int)nm; ii++ ) {
   if ( star2[Pos2[ii]].moving_object == 0 ) {
    z[iii]= star2[Pos2[ii]].y - STAR1[Pos1[ii]].y;
    iii++;
   }
  }
  fit_plane_lin( x, y, z, iii, &Ay, &By, &Cy );
  // fprintf(stderr,"dy=(%lf)*x+(%lf)*y+(%lf)\n",Ay,By,Cy);

  // Now, apply the coordinate correction to ALL stars on the new (= current = star2) frame.
  // fprintf(stderr,"Applying coordinate corrections...\n");
  for ( ii= 0; ii < (unsigned int)NUMBER2; ii++ ) {
   dx= (float)( Ax * star2[Pos2[ii]].x_frame + Bx * star2[Pos2[ii]].y_frame + Cx );
   dy= (float)( Ay * star2[Pos2[ii]].x_frame + By * star2[Pos2[ii]].y_frame + Cy );
   star2[Pos2[ii]].x-= dx;
   star2[Pos2[ii]].y-= dy;
  }
  // And now match stars again
  nm= Ident_on_sigma( STAR1, NUMBER1, star2, NUMBER2, Pos1, Pos2, preobr->sigma_popadaniya, image_size_X, image_size_Y );
  // fprintf(stderr,"%d * matched after the coordinate correction. ",nm);
  fprintf( stderr, "%d * matched, ", nm );
  // Check the match sucess, otherwise VaST wil crash when reaching fit_plane_lin()
  // If the match is bad - exit and retry.
  if ( nm < min_number_of_matched_stars ) {
   fprintf( stderr, "Too few * matched: %d < %d ! Retrying...\n", nm, min_number_of_matched_stars );
   ( *match_retry )= 1; // !!

   // We don't want to exit without freeing the memory allocated for the sturctures
   free( star1 );
   free( star2 );

   free( z );
   free( y );
   free( x );

   return nm; // 0;
  }

  /// Second iteration
  // Fit a plane to x residuals
  for ( iii= 0, ii= 0; ii < (unsigned int)nm; ii++ ) {
   if ( star2[Pos2[ii]].moving_object == 0 ) {
    x[iii]= star2[Pos2[ii]].x_frame;
    y[iii]= star2[Pos2[ii]].y_frame;
    z[iii]= star2[Pos2[ii]].x - STAR1[Pos1[ii]].x;
    iii++;
   }
  }
  fit_plane_lin( x, y, z, iii, &Ax, &Bx, &Cx );

  // Fit a plane to y residuals
  for ( iii= 0, ii= 0; ii < (unsigned int)nm; ii++ ) {
   if ( star2[Pos2[ii]].moving_object == 0 ) {
    z[iii]= star2[Pos2[ii]].y - STAR1[Pos1[ii]].y;
    iii++;
   }
  }
  fit_plane_lin( x, y, z, iii, &Ay, &By, &Cy );

  // Now, apply the coordinate correction to ALL stars on the new (= current = star2) frame.
  for ( ii= 0; ii < (unsigned int)NUMBER2; ii++ ) {
   dx= (float)( Ax * star2[Pos2[ii]].x_frame + Bx * star2[Pos2[ii]].y_frame + Cx );
   dy= (float)( Ay * star2[Pos2[ii]].x_frame + By * star2[Pos2[ii]].y_frame + Cy );
   star2[Pos2[ii]].x-= dx;
   star2[Pos2[ii]].y-= dy;
  }
  // And now match stars again
  nm= Ident_on_sigma( STAR1, NUMBER1, star2, NUMBER2, Pos1, Pos2, preobr->sigma_popadaniya, image_size_X, image_size_Y );
  // fprintf(stderr,"%d * matched after the coordinate correction. ",nm);
  fprintf( stderr, "%d * matched (2nd iteration). ", nm );

  // If the match is bad - exit and retry.
  if ( nm < min_number_of_matched_stars ) {
   fprintf( stderr, "Too few * matched: %d < %d ! Retrying...\n", nm, min_number_of_matched_stars );
   ( *match_retry )= 1; // !!

   // We don't want to exit without freeing the memory allocated for the sturctures
   free( star1 );
   free( star2 );

   free( z );
   free( y );
   free( x );

   return nm; // 0;
  }

  /// Third iteration
  // Fit a plane to x residuals
  for ( iii= 0, ii= 0; ii < (unsigned int)nm; ii++ ) {
   if ( star2[Pos2[ii]].moving_object == 0 ) {
    x[iii]= star2[Pos2[ii]].x_frame;
    y[iii]= star2[Pos2[ii]].y_frame;
    z[iii]= star2[Pos2[ii]].x - STAR1[Pos1[ii]].x;
    iii++;
   }
  }
  fit_plane_lin( x, y, z, iii, &Ax, &Bx, &Cx );

  // Fit a plane to y residuals
  for ( iii= 0, ii= 0; ii < (unsigned int)nm; ii++ ) {
   if ( star2[Pos2[ii]].moving_object == 0 ) {
    z[iii]= star2[Pos2[ii]].y - STAR1[Pos1[ii]].y;
    iii++;
   }
  }
  fit_plane_lin( x, y, z, iii, &Ay, &By, &Cy );

  // Now, apply the coordinate correction to ALL stars on the new (= current = star2) frame.
  for ( ii= 0; ii < (unsigned int)NUMBER2; ii++ ) {
   dx= (float)( Ax * star2[Pos2[ii]].x_frame + Bx * star2[Pos2[ii]].y_frame + Cx );
   dy= (float)( Ay * star2[Pos2[ii]].x_frame + By * star2[Pos2[ii]].y_frame + Cy );
   star2[Pos2[ii]].x-= dx;
   star2[Pos2[ii]].y-= dy;
  }
  // And now match stars again
  nm= Ident_on_sigma( STAR1, NUMBER1, star2, NUMBER2, Pos1, Pos2, preobr->sigma_popadaniya, image_size_X, image_size_Y );
  // fprintf(stderr,"%d * matched after the coordinate correction. ",nm);
  fprintf( stderr, "%d * matched (3rd iteration). ", nm );

  // If the match is bad - exit and retry.
  if ( nm < min_number_of_matched_stars ) {
   fprintf( stderr, "Too few * matched: %d < %d ! Retrying...\n", nm, min_number_of_matched_stars );
   ( *match_retry )= 1; // !!

   // We don't want to exit without freeing the memory allocated for the sturctures
   free( star1 );
   free( star2 );

   free( z );
   free( y );
   free( x );

   return nm; // 0;
  }

  // Free memory if everything is OK

  free( z );
  free( y );
  free( x );

  //} // if enough stars matched

  for ( n= 0; n < NUMBER2; n++ )
   Star_Copy( STAR2 + n, star2 + n ); // Copy stars (with new coordinates) back to struct STAR2
  fprintf( stderr, "Success!\n" );
  ( *match_retry )= 0;
 } else {
  fprintf( stderr, "Too few * detected: %d!\n", nm );
  nm= 0;
 }

 // Free-up memory
 free( star1 );
 free( star2 );

 return ( nm ); // return the number of matched stars
}
