#ifndef VAST_TYPES_H
#define VAST_TYPES_H

#include "vast_limits.h"

struct Observation {
 int star_num;
 double JD; // on a 64-bit system, both a double and a double* take 8 bytes each
 double mag;
 double mag_err;
 double X;
 double Y;
 float APER;
 char *filename;                                    // Pointer instead of array
 char *fits_header_keywords_to_be_recorded_in_lightcurve; // Pointer instead of array
 char is_used; 
 float float_parameters[NUMBER_OF_FLOAT_PARAMETERS];
};

struct Frame {
 double X_centre;
 double Y_centre;
};

/*
  Structure describes the order of vertices
  of a triangle from the set of initial points star[n]
*/
struct Triangle {
 int a[3];
 float ab;
 float ac;
 float bc;
 float ab_bc_ac;
};

struct Ecv_Triangle {
 struct Triangle tr1;
 struct Triangle tr2;
};

/*
  Description of a sequence of similar triangles
*/
struct Ecv_triangles {
 struct Ecv_Triangle *tr;
 int Number; // Number of pairs
};

struct Star {
 int n;
 float x;                    // X coordinate in pixels. WILL BE TRANSFORMED TO THE REFERENCE IMAGE COORDINATE FRAME
 float y;                    // Y coordinate in pixels. WILL BE TRANSFORMED TO THE REFERENCE IMAGE COORDINATE FRAME
 double flux;                // Brightness in counts
 double flux_err;            // Error of brightness in counts -- NEW
 float mag;                  // Brightness in magnitudes
 float sigma_mag;            // Error of brightness estimation (mag.)
 double JD;                  // Julian Date of observation // on a 64-bit system, both a double and a double* take 8 bytes each
 float x_frame;              // X coordinate in pixels. WILL NOT BE TRANSFORMED TO THE REFERENCE IMAGE COORDINATE FRAME
 float y_frame;              // Y coordinate in pixels. WILL NOT BE TRANSFORMED TO THE REFERENCE IMAGE COORDINATE FRAME
 char detected_on_ref_frame; // 1 - detected, 0 - not detected
 short sextractor_flag;      // Sextractor flag
 short vast_flag;            // VaST's own flag which is a sum of
                             //  1 - semimajor axis of the object (A) is larger than the aperture size
                             //  2 - the object is an outlier in mag-chi2 plot (defined only in PSF-fitting mode)
                             //  4 - the object is an outlier in mag-A plot
                             //  8 - the object is an outlier in mag-FWHM plot
                             // 16 - the object is an outlier in mag-MagAuto plot
                             // and so on

 float star_size;                                    // Semimajor axis of the star's image (A)
 float star_psf_chi2;                                // chi2 of PSF-fitting
 float float_parameters[NUMBER_OF_FLOAT_PARAMETERS]; // Array of additional star parameters for filtering
                                                     // 0 - FWHM_IMAGE
                                                     // 1 - MAG_AUTO
                                                     // ... and many more!
 int n_detected;                                     // how many times this star was detected
 int n_rejected;                                     // how many times this star was detected, but rejected according to the quality flags (mag-size, etc)
 char moving_object;    // manually match a moving object
};

/*
 Transformation of the second frame to the first
 First similarity
 Then translate
 Then linear transformation Line_Preobr
 Then translate
*/
struct PixCoordinateTransformation {
 //double podobie;       // Similarity coefficient of the first frame to the second
 double translate1[2];       // translate along xy axes
 double line[4];             // Linear transformation matrix
 double translate2[2];       // translate along xy axes
 double fi;                  // Angle by which frame 2 had to be rotated to frame 1 clockwise
 double sigma_podobia;       // Selection criterion for similar triangles
 int Number_of_ecv_triangle; // Number of similar triangles to be processed
 double sigma_popadaniya;    // Distance at which two stars from two frames are perceived as one
 double sigma_popadaniya_multiple;
 double persent_popadaniy_of_ecv_triangle;
 int method;
 int Number_of_main_star; // Number of reference stars
};

/* Photometric calibration type constants */
#define PHOTOMETRIC_LINEAR        0
#define PHOTOMETRIC_PARABOLA      1
#define PHOTOMETRIC_ZEROPOINT     2
#define PHOTOMETRIC_PHOTOCURVE    3
#define PHOTOMETRIC_ROBUST_LINEAR 4

/* Optional: Helper macros for validation and strings */
#define IS_VALID_PHOTOMETRIC_TYPE(x) ((x) >= 0 && (x) <= 4)

/* Optional: Macro to get string representation */
#define PHOTOMETRIC_TYPE_STRING(x) \
    ((x) == PHOTOMETRIC_LINEAR ? "linear" : \
     (x) == PHOTOMETRIC_PARABOLA ? "parabola" : \
     (x) == PHOTOMETRIC_ZEROPOINT ? "zeropoint" : \
     (x) == PHOTOMETRIC_PHOTOCURVE ? "photocurve" : \
     (x) == PHOTOMETRIC_ROBUST_LINEAR ? "robust_linear" : "unknown")

#endif
// VAST_TYPES_H
