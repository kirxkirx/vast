// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_GUESS_SATURATION_LIMIT_INCLUDE_FILE

int check_if_we_need_flag_image( char *fitsfilename, char *resulting_sextractor_cl_parameter_string, int *is_flag_image_used, char *flag_image_filename, char *weight_image_filename );

int guess_saturation_limit( char *fitsfilename, char *resulting_sextractor_cl_parameter_string, int operation_mode );

int guess_gain( char *fitsfilename, char *resulting_sextractor_cl_parameter_string, int operation_mode, int raise_unset_gain_warning );

// The macro below will tell the pre-processor that this header file is already included
#define VAST_GUESS_SATURATION_LIMIT_INCLUDE_FILE

#endif
// VAST_GUESS_SATURATION_LIMIT_INCLUDE_FILE
