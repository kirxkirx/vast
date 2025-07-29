// The following line is just to make sure this file is not included twice in the code
#ifndef FILTER_MAGSIZE_INCLUDE_FILE

#include <math.h>   // for fabs() and fabsf()
#include <stdlib.h> // for exit() and something else
#include <stdio.h>

// GSL header files
#include <gsl/gsl_statistics.h>
#include <gsl/gsl_sort.h>
#include <gsl/gsl_errno.h>

#include "vast_types.h"
#include "ident.h"
#include "variability_indexes.h"
#include "vast_limits.h"

#include "erfinv.h"

int filter_MagSize(struct Star *STAR, int NUMBER, char *sextractor_catalog);

int filter_MagPSFchi2(struct Star *STAR, int NUMBER, char *sextractor_catalog);

int filter_on_float_parameters(struct Star *STAR, int NUMBER, char *sextractor_catalog, int parameter_number);

// The macro below will tell the pre-processor that this header file is already included
#define FILTER_MAGSIZE_INCLUDE_FILE

#endif
// VAST_STETSON_VARIABILITY_INDEXES_INCLUDE_FILE
