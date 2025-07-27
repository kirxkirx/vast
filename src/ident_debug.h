#ifndef IDENT_DEBUG_H
#define IDENT_DEBUG_H

void write_Star_struct_to_ds9_region_file( struct Star *star, int N_start, int N_stop, char *filename, double aperture );
void write_single_Star_from_struct_to_ds9_region_file( struct Star *star, int N_start, int N_stop, char *filename, double aperture );
void write_Star_struct_to_ASCII_file( struct Star *star, int N_start, int N_stop, char *filename, double aperture );

void write_Triangle_array_to_ds9( struct Triangle *tr, int Ntri, struct Star *star, const char *fname, const char *color );
void write_single_Triangle_to_ds9( struct Triangle *tr, struct Star *star, const char *fname, const char *color );


void write_triangle_matching_debug_log(struct Triangle *tr1, int Nt1, struct Triangle *tr2, int Nt2, struct Star *star1, struct Star *star2, struct Ecv_triangles *ecv_tr, const char *filename);
void write_triangle_construction_stars_ds9(struct Star *star, int Number, const char *filename, const char *color, int max_stars);
void write_all_triangles_with_matches_ds9(struct Triangle *tr1, int Nt1, struct Triangle *tr2, int Nt2, struct Star *star1, struct Star *star2, struct Ecv_triangles *ecv_tr, const char *filename);
void write_best_triangle_match_ds9(struct Ecv_triangles *ecv_tr, int best_triangle_index, struct Star *star1, struct Star *star2, struct PixCoordinateTransformation *transform, const char *filename);
void write_matched_stars_ds9(struct Star *star1, struct Star *star2, int *Pos1, int *Pos2, int num_matched, const char *filename);
void write_triangle_similarity_analysis(struct Triangle *tr1, int Nt1, struct Triangle *tr2, int Nt2, float sigma_podobia, const char *filename);

int Podobie_debug(struct PixCoordinateTransformation *struct_pixel_coordinate_transformation, struct Ecv_triangles *ecv_tr, struct Triangle *tr1, int Nt1, struct Triangle *tr2, int Nt2, struct Star *star1, struct Star *star2, int Number1, int Number2);
int Very_Well_triangle_debug(struct Star *star1, int Number1, struct Star *star2, int Number2, struct Ecv_triangles *ecv_tr, struct PixCoordinateTransformation *struct_pixel_coordinate_transformation, int *nm, int control1);


#endif
// IDENT_DEBUG_H