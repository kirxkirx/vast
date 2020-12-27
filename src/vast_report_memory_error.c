#include <stdio.h>
#include "vast_limits.h"

void vast_report_memory_error() {
 fprintf(stderr, "\nVaST has run out of memory during computations. This is something which is not supposed to happen.\n");
 if( MAX_NUMBER_OF_STARS != 150000 || MAX_NUMBER_OF_OBSERVATIONS != 120000 || MAX_MEASUREMENTS_IN_RAM != 400000 ) {
  fprintf(stderr, "The most likely cause is an incorrect choice of parameters MAX_NUMBER_OF_STARS , MAX_NUMBER_OF_OBSERVATIONS and MAX_MEASUREMENTS_IN_RAM which can be set in src/vast_limits.h .\nThe reasonable default values of the parameters are:\n");
  fprintf(stderr, "MAX_NUMBER_OF_STARS 150000\n");
  fprintf(stderr, "MAX_NUMBER_OF_OBSERVATIONS 120000\n");
  fprintf(stderr, "MAX_MEASUREMENTS_IN_RAM 400000\n");
  fprintf(stderr, "These values should work just fine for the majority of cases.\nCurrently, the parameters are set to:\n");
  fprintf(stderr, "MAX_NUMBER_OF_STARS %d\n", MAX_NUMBER_OF_STARS);
  fprintf(stderr, "MAX_NUMBER_OF_OBSERVATIONS %d\n", MAX_NUMBER_OF_OBSERVATIONS);
  fprintf(stderr, "MAX_MEASUREMENTS_IN_RAM %d\n", MAX_MEASUREMENTS_IN_RAM);
 }
 return;
}
