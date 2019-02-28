#include <stdio.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <math.h>

#include "vast_limits.h"
#include "lightcurve_io.h"

void write_fake_log_file( double *jd, int *Nobs );

void get_dates_from_lightcurve_files( double *jd, int *Nobs );

void get_dates( double *jd, int *Nobs );
