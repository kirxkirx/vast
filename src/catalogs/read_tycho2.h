// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_READTYCHO2_HEADER_FILE

// Wide-field camera
//#define MIN_VT  0.0
//#define MAX_VT  8.0
//#define MAX_DISTANCE_ARCSEC  90

#define MIN_VT 9.0
#define MAX_VT 12.5
#define MAX_DISTANCE_ARCSEC 5

#define MAX_DISTANCE_DEGREES MAX_DISTANCE_ARCSEC / 3600.0

#define STARS_IN_TYC2 2539913
#define TYCHOSTRING 256
#define TYCHONUMBER 18

#include "../vast_limits.h"

#define MAX_NUMBER_OF_STARS_ON_IMAGE MAX_NUMBER_OF_STARS // Just to make syntax more convoluted and complex ;)

struct Star {
 int good_star;
 char catnumber[TYCHONUMBER]; // start name
                              // char imagfilename[LONGEST_FILENAME]; // FITS image name
 double computed_mag;         // star magnitude after correction
 double distance_from_catalog_position;
 // Parameters taken from the sextractor catalog
 int NUMBER; // inernal star number in the Sextractor catalog
 double FLUX_APER;
 double FLUXERR_APER;
 double MAG_APER;
 double MAGERR_APER;
 double X_IMAGE;
 double Y_IMAGE;
 double ALPHA_SKY;
 double DELTA_SKY;
 //double A_IMAGE;
 //double ERRA_IMAGE;
 //double B_IMAGE;
 //double ERRB_IMAGE;
 //double A_WORLD;
 //double B_WORLD;
 int FLAGS;
 //double CLASS_STAR;
 // Parameters from the Tycho2 catalog
 int matched_with_catalog;
 double ALPHA_catalog;
 double DELTA_catalog;
 double BT;  // Tycho B mag
 double VT;  // Tycho V mag
 double V;   // V   = VT -0.090*(BT-VT)
 double B_V; // B-V = 0.850*(BT-VT)
 // Consult Sect 1.3 of Vol 1 of "The Hipparcos and Tycho Catalogues", ESA SP-1200, 1997, for details.
};

struct CatStar {
 char catnumber[TYCHONUMBER]; // start name
 double ALPHA_catalog;
 double DELTA_catalog;
 double BT; // Tycho B mag
 double VT; // Tycho V mag
};

double get_RA_from_string(char *str);

double get_Dec_from_string(char *str);

double get_BT_from_string(char *str);

double get_VT_from_string(char *str);

void get_catnumber_from_string(char *str, char *str2);

int match_stars_with_catalog(struct Star *arrStar, int N, struct CatStar *arrCatStar, long M);

int read_tycho_cat(struct CatStar *arrCatStar, long *M, double *image_boundaries_radec);

int read_sextractor_cat(char *catalog_name, struct Star *arrStar, int *N, double *image_boundaries_radec);

int create_tycho2_list_of_bright_stars_to_exclude_from_transient_search(double faint_mag_limit_for_the_list);

// The macro below will tell the pre-processor that limits.h is already included
#define VAST_READTYCHO2_HEADER_FILE

#endif
// VAST_READTYCHO2_HEADER_FILE
