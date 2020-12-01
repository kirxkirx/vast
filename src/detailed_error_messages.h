// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_DETAILED_ERROR_MESSAGE_INCLUDE_FILE

#include "vast_limits.h"

void report_lightcurve_statistics_computation_problem() {
 fprintf(stderr, "\n**************************************************************\nThis error might be a bug, but it is far more likely that it is caused by \ninappropriate input data. A few simple things to check in the diagnostic\nmessages printed above (or the vast*.log files):\n * How many of the input images are matched?\n * Does the number of detected stars on each image look reasonable?\n * Do images have a sufficient overlap of at least about %.0lf percent?\n\nYou may run\n ./sextract_single_image /path/to/my/image/file.fit\nto see how well VaST detects stars with the current SExtractor settings\n(star detection settings can be changed in the default.sex configuration\nfile, see various examples in the VaST directory).\n\nIf you cannot identify the problem, please e-mail Kirill Sokolovsky <kirx@kirx.net>\nPlease try to describe the problem in details and, if possible, attach vast_summary.log\nfile and a few example images. If the images are too big to be sent by e-mail, please \nupload them through a web-form http://scan.sai.msu.ru/upload/\n**************************************************************\n\n", MIN_FRACTION_OF_MATCHED_STARS * 100.0);
}

// The macro below will tell the pre-processor that this header file is already included
#define VAST_DETAILED_ERROR_MESSAGE_INCLUDE_FILE

#endif
// VAST_DETAILED_ERROR_MESSAGE_INCLUDE_FILE
