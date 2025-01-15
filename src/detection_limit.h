#ifndef VAST_DETECTION_LIMIT_INCLUDE_FILE
#define VAST_DETECTION_LIMIT_INCLUDE_FILE

#include <stddef.h>  // for size_t

/*
  This code implements the technique of magnitude limit determination
  based on fitting a model to the SNR-magnitude plot as suggested by Sergey Karpov
  https://ui.adsabs.harvard.edu/abs/2024arXiv241116470K/abstract
*/

/* Calculates the detection limit based on signal-to-noise ratio analysis.
* 
* Input parameters:
* mag - Array of magnitude values
* mag_sn - Array of signal-to-noise ratio values corresponding to magnitudes
* n - Number of elements in the arrays
* target_sn - Target signal-to-noise ratio for detection limit
* success - Pointer to int that will be set to 1 if calculation succeeded, 0 otherwise
* 
* Returns: Detection limit magnitude if successful, GSL_NAN otherwise
*/
double get_detection_limit_sn(double *mag, double *mag_sn, size_t n, double target_sn, int *success);

#endif /* VAST_DETECTION_LIMIT_INCLUDE_FILE */
