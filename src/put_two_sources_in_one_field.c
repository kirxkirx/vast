#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "vast_limits.h"

int format_hms_or_deg(char *coordinatestring) {
 unsigned int i;
 for( i= 0; i < strlen(coordinatestring); i++ ) {
  if( coordinatestring[i] == ':' )
   return 1;
 }
 return 0;
}

int main(int argc, char **argv) {
 double hh, mm, ss;
 double RA1_deg, DEC1_deg, RA2_deg, DEC2_deg;

 double in, ss2;
 int hh2, mm2;

 double distance;

 if( argc < 5 ) {
  fprintf(stderr, "Usage: %s RA1 DEC1 RA2 DEC2\n", argv[0]);
  return 1;
 }

 if( format_hms_or_deg(argv[1]) ) {
  // Format HH:MM:SS.SS
  sscanf(argv[1], "%lf:%lf:%lf", &hh, &mm, &ss);
  hh+= mm / 60 + ss / 3600;
  hh*= 15;
  RA1_deg= hh;
 } else {
  // Format DD.DDDD
  RA1_deg= atof(argv[1]);
 }

 if( format_hms_or_deg(argv[2]) ) {
  // Format DD:MM:SS.S
  sscanf(argv[2], "%lf:%lf:%lf", &hh, &mm, &ss);
  if( hh >= 0 && argv[2][0] != '-' )
   hh+= mm / 60 + ss / 3600;
  else
   hh-= mm / 60 + ss / 3600;
  DEC1_deg= hh;
 } else {
  // Format DD.DDDD
  DEC1_deg= atof(argv[2]);
 }
 // Check the resulting values
 if( RA1_deg < 0.0 || RA1_deg > 360.0 ) {
  fprintf(stderr, "ERROR parsing input coordinates: '%s' understood as '%lf'\n", argv[1], RA1_deg);
  return 1;
 }
 if( DEC1_deg < -90.0 || DEC1_deg > 90.0 ) {
  fprintf(stderr, "ERROR parsing input coordinates: '%s' understood as '%lf'\n", argv[2], DEC1_deg);
  return 1;
 }

 if( format_hms_or_deg(argv[3]) ) {
  // Format HH:MM:SS.SS
  sscanf(argv[3], "%lf:%lf:%lf", &hh, &mm, &ss);
  hh+= mm / 60 + ss / 3600;
  hh*= 15;
  RA2_deg= hh;
 } else {
  // Format DD.DDDD
  RA2_deg= atof(argv[3]);
 }

 if( format_hms_or_deg(argv[4]) ) {
  // Format DD:MM:SS.S
  sscanf(argv[4], "%lf:%lf:%lf", &hh, &mm, &ss);
  if( hh >= 0 && argv[4][0] != '-' )
   hh+= mm / 60 + ss / 3600;
  else
   hh-= mm / 60 + ss / 3600;
  DEC2_deg= hh;
 } else {
  // Format DD.DDDD
  DEC2_deg= atof(argv[4]);
 }
 if( RA2_deg < 0.0 || RA2_deg > 360.0 ) {
  fprintf(stderr, "ERROR parsing input coordinates: '%s' understood as '%lf'\n", argv[3], RA2_deg);
  return 1;
 }
 if( DEC2_deg < -90.0 || DEC2_deg > 90.0 ) {
  fprintf(stderr, "ERROR parsing input coordinates: '%s' understood as '%lf'\n", argv[4], DEC2_deg);
  return 1;
 }

 fprintf(stderr, "%lf %lf  %lf %lf\n", RA1_deg, DEC1_deg, RA2_deg, DEC2_deg);

 if( MAX(RA1_deg, RA2_deg) > 180 && MIN(RA1_deg, RA2_deg) < 180 ) {
  //  fprintf(stderr,"CIRCLE ALERT\n",in);
  if( RA1_deg > 180 )
   RA1_deg-= 360;
  if( RA2_deg > 180 )
   RA1_deg-= 360;
 }
 in= RA1_deg + RA2_deg;
 in= in / 2.0;

 if( in < 0.0 )
  in+= 360;

 in= in / 15.0;
 hh2= (int)in;
 mm2= (int)((in - hh2) * 60);
 ss2= ((in - hh2) * 60 - mm2) * 60;
 if( fabs(ss2 - 60.0) < 0.01 ) {
  mm2+= 1;
  ss2= 0.0;
 }
 if( mm2 == 60 ) {
  hh2+= 1;
  mm2= 0.0;
 }
 fprintf(stdout, "Average position  %02d:%02d:%05.2lf ", hh2, mm2, ss2);

 in= (DEC1_deg + DEC2_deg) / 2.0;
 hh2= (int)in;
 // fprintf(stderr,"%lf %d\n",in,hh2);
 mm2= (int)((in - hh2) * 60);
 ss2= ((in - hh2) * 60 - mm2) * 60;
 if( in < 0.0 ) {
  mm2*= -1;
  ss2*= -1;
 }
 if( fabs(ss2 - 60.0) < 0.01 ) {
  mm2+= 1;
  ss2= 0.0;
 }
 if( mm2 == 60 ) {
  hh2+= 1;
  mm2= 0.0;
 }
 if( (hh2 == 0 && in < 0) || (hh2 == 0 && mm2 == 0 && in < 0) )
  fprintf(stdout, "-%02d:%02d:%04.1lf\n", hh2, mm2, fabs(ss2));
 else
  fprintf(stdout, "%+02d:%02d:%04.1lf\n", hh2, mm2, ss2);

 RA1_deg*= 3600 / 206264.8;
 RA2_deg*= 3600 / 206264.8;
 DEC1_deg*= 3600 / 206264.8;
 DEC2_deg*= 3600 / 206264.8;

 distance= acos(cos(DEC1_deg) * cos(DEC2_deg) * cos(MAX(RA1_deg, RA2_deg) - MIN(RA1_deg, RA2_deg)) + sin(DEC1_deg) * sin(DEC2_deg));

 in= distance * 206264.8 / 3600;
 hh2= (int)in;
 mm2= (int)((in - hh2) * 60);
 ss2= ((in - hh2) * 60 - mm2) * 60;
 if( fabs(ss2 - 60.0) < 0.01 ) {
  mm2+= 1;
  ss2= 0.0;
 }
 if( mm2 == 60 ) {
  hh2+= 1;
  mm2= 0.0;
 }

 fprintf(stdout, "Angular distance  %02d:%02d:%05.2lf = ", hh2, mm2, ss2);

 fprintf(stdout, "%lf degrees\n", distance * 206264.8 / 3600);

 return 0;
}
