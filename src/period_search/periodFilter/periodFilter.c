/*********************************************************************
 *
 * This utility filters out all but the high confidence light curves
 *
 * compile:  gcc periodFilter.c -o periodFilter -Wall -O4
 * run: periodFilter all.txt 6.5 200 all.filtered
 *
 **********************************************************************/

#include <stdio.h>
#include <stdlib.h> // for atof()
#include <string.h> // for strcmp()

//#define DEBUG
//#define THINNING 19

int main(int argc, char **argv) {
 FILE *finList, *fout= 0;
 double period, conf, minConf, maxPeriod;
 char strFilename[512];
 unsigned long counterAll= 0, counterGood= 0;

 if( (argc < 4) || (argc > 5) ) {
  printf("%s <period list file> <min periodicity strength> <max period> [output file]\n", argv[0]);
  return (1);
 }

 finList= fopen(argv[1], "rt");
 if( !finList ) {
  printf("ERROR: couldn't open input file '%s'\n", argv[1]);
  return (2);
 }

 minConf= atof(argv[2]);
 maxPeriod= atof(argv[3]);

 if( argc >= 5 ) {
  if( strcmp(argv[1], argv[4]) == 0 ) {
   printf("ERROR: the input and output files are the same ('%s')\n", argv[4]);
   fclose(finList);
   return (3);
  }

  fout= fopen(argv[4], "at");
  if( !fout ) {
   printf("ERROR: couldn't open output file '%s'\n", argv[4]);
   fclose(finList);
   return (4);
  }
 }

 while( fscanf(finList, "%s %lf %lf %*u %*f %*f\n", strFilename, &period, &conf) == 3 ) {
  counterAll++;

  if( conf < minConf )
   continue;
  if( period > maxPeriod )
   continue;

#ifdef THINNING
  if( counter % THINNING )
   continue;
#endif

  counterGood++;

  if( fout )
   fprintf(fout, "%s %.12f\n", strFilename, period);
  else
   printf("%s %.12f\n", strFilename, period);
 }

 if( argc >= 5 )
  printf("Listed %lu files out of %lu.\n", counterGood, counterAll);

 fclose(finList);
 if( fout )
  fclose(fout);
 return (0);
}
