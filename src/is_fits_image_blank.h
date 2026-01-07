// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_IS_FITS_IMAGE_BLANK_INCLUDE_FILE

// Check if a FITS image is blank (all pixels have constant or near-constant values)
// Returns:
//   0 - image is NOT blank (has variation/noise/stars)
//   1 - image IS blank (all pixels are constant or nearly constant)
//  -1 - error reading the image
int is_fits_image_blank( char *fitsfilename );

// The macro below will tell the pre-processor that this header file is already included
#define VAST_IS_FITS_IMAGE_BLANK_INCLUDE_FILE
#endif
// VAST_IS_FITS_IMAGE_BLANK_INCLUDE_FILE
