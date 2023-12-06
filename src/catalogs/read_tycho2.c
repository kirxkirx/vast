#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include <gsl/gsl_statistics.h>

#include "../vast_limits.h"

#include "../count_lines_in_ASCII_file.h" // for count_lines_in_ASCII_file()

#include "read_tycho2.h"

double get_RA_from_string( char *str ) {
 char str2[256];
 unsigned int i, j, nomer_v;
 nomer_v= 0;
 for ( i= 0, j= 0; i < strlen( str ); i++ ) {
  str2[j]= str[i];
  if ( str2[j] == '|' ) {
   str2[j]= '\0';
   j= 0;
   nomer_v++;
   if ( nomer_v == 3 )
    break;
  } else {
   j++;
  }
 }
 return atof( str2 );
}

// wcs_mag.param
double get_Dec_from_string( char *str ) {
 char str2[256];
 unsigned int i, j, nomer_v;
 nomer_v= 0;
 for ( i= 0, j= 0; i < strlen( str ); i++ ) {
  str2[j]= str[i];
  if ( str2[j] == '|' ) {
   str2[j]= '\0';
   j= 0;
   nomer_v++;
   if ( nomer_v == 4 )
    break;
  } else {
   j++;
  }
 }
 return atof( str2 );
}

double get_BT_from_string( char *str ) {
 char str2[256];
 unsigned int i, j, nomer_v;
 nomer_v= 0;
 for ( i= 0, j= 0; i < strlen( str ); i++ ) {
  str2[j]= str[i];
  if ( str2[j] == '|' ) {
   str2[j]= '\0';
   j= 0;
   nomer_v++;
   if ( nomer_v == 18 )
    break;
  } else {
   j++;
  }
 }
 return atof( str2 );
}

double get_VT_from_string( char *str ) {
 char str2[256];
 unsigned int i, j, nomer_v;
 nomer_v= 0;
 for ( i= 0, j= 0; i < strlen( str ); i++ ) {
  str2[j]= str[i];
  if ( str2[j] == '|' ) {
   str2[j]= '\0';
   j= 0;
   nomer_v++;
   if ( nomer_v == 20 )
    break;
  } else {
   j++;
  }
 }
 return atof( str2 );
}

void get_catnumber_from_string( char *str, char *str2 ) {
 int i;
 for ( i= 0; i < 14; i++ ) {
  str2[i]= str[i];
  if ( str2[i] == ' ' )
   str2[i]= '-';
  if ( str2[i] == '|' ) {
   str2[i]= '\0';
   break;
  }
 }
 return;
}

static int compare_star_on_mag_to_sort_arrStar( const void *a1, const void *a2 ) {
 struct Star *s1, *s2;
 s1= (struct Star *)a1;
 s2= (struct Star *)a2;
 if ( s1->MAG_APER < s2->MAG_APER ) {
  return -1;
 }
 return 1;
}

static int compare_star_on_mag_to_sort_arrCatStar( const void *a1, const void *a2 ) {
 struct CatStar *s1, *s2;
 s1= (struct CatStar *)a1;
 s2= (struct CatStar *)a2;
 if ( s1->VT < s2->VT ) {
  return -1;
 }
 return 1;
}

int match_stars_with_catalog( struct Star *arrStar, int N, struct CatStar *arrCatStar, long M ) {
 double *mag_zeropoint; //=malloc(MAX_NUMBER_OF_STARS_ON_IMAGE*sizeof(double));
 int mag_zeropoint_counter= 0;
 FILE *calibfile;
 int N_mantch= 0;
 long i, j;
 // long max_M=0; // for debug
 double distance;
 double best_distance;
 int match_only_N_brightest_stars;

 mag_zeropoint= malloc( N * sizeof( double ) );
 if ( NULL == mag_zeropoint ) {
  fprintf( stderr, "ERROR allocating memory in match_stars_with_catalog()\n" );
  return 0;
 }

 // sort arrays in magnitude
 qsort( arrStar, N, sizeof( struct Star ), compare_star_on_mag_to_sort_arrStar );
 qsort( arrCatStar, M, sizeof( struct CatStar ), compare_star_on_mag_to_sort_arrCatStar );

 // match_only_N_brightest_stars= MIN(N, 3*M);
 match_only_N_brightest_stars= N;
 // for each SExtractor catalog star
#ifdef VAST_ENABLE_OPENMP
#ifdef _OPENMP
#pragma omp parallel for private( i, j, best_distance, distance )
#endif
#endif
 for ( i= 0; i < match_only_N_brightest_stars; i++ ) {
  // Check distances to all other stars
  // best_distance= 90;
  best_distance= MAX_DISTANCE_DEGREES;
  for ( j= 0; j < M; j++ ) {
   //   if( max_M<M )max_M=M;
   // First rough check
   if ( arrCatStar[j].ALPHA_catalog == 0.0 )
    continue;
   if ( arrCatStar[j].DELTA_catalog == 0.0 )
    continue;
   if ( arrCatStar[j].VT == 0.0 )
    continue;
   if ( arrCatStar[j].BT == 0.0 )
    continue;
   if ( arrCatStar[j].VT > MAX_VT || arrCatStar[j].VT < MIN_VT )
    continue;
   // if( fabs(arrStar[i].DELTA_SKY-arrCatStar[j].DELTA_catalog)>MIN( MAX_DISTANCE_DEGREES, arrStar[i].A_WORLD) )continue;
   if ( fabs( arrStar[i].DELTA_SKY - arrCatStar[j].DELTA_catalog ) > MAX_DISTANCE_DEGREES )
    continue;
   if ( fabs( arrStar[i].ALPHA_SKY - arrCatStar[j].ALPHA_catalog ) > 1.0 )
    continue;
   distance= 180.0 / M_PI * acos( cos( arrStar[i].DELTA_SKY * M_PI / 180.0 ) * cos( arrCatStar[j].DELTA_catalog * M_PI / 180.0 ) * cos( MAX( arrStar[i].ALPHA_SKY * M_PI / 180.0, arrCatStar[j].ALPHA_catalog * M_PI / 180.0 ) - MIN( arrStar[i].ALPHA_SKY * M_PI / 180.0, arrCatStar[j].ALPHA_catalog * M_PI / 180.0 ) ) + sin( arrStar[i].DELTA_SKY * M_PI / 180.0 ) * sin( arrCatStar[j].DELTA_catalog * M_PI / 180.0 ) );
   if ( distance < best_distance ) {
    best_distance= distance;
    // If the distance is acceptable - remember star parameters
    // if( distance<MAX( MAX_DISTANCE_DEGREES, arrStar[i].A_WORLD) ){
    if ( distance < MAX_DISTANCE_DEGREES ) {
     arrStar[i].matched_with_catalog= 1;
     arrStar[i].distance_from_catalog_position= distance;
     arrStar[i].ALPHA_catalog= arrCatStar[j].ALPHA_catalog;
     arrStar[i].DELTA_catalog= arrCatStar[j].DELTA_catalog;
     arrStar[i].BT= arrCatStar[j].BT;
     arrStar[i].VT= arrCatStar[j].VT;
     arrStar[i].V= arrStar[i].VT - 0.090 * ( arrStar[i].BT - arrStar[i].VT );
     arrStar[i].B_V= 0.850 * ( arrStar[i].BT - arrStar[i].VT );
     // strcpy(arrStar[i].catnumber,arrCatStar[i].catnumber);
     memset( arrStar[i].catnumber, 0, TYCHONUMBER ); // just in case
     strncpy( arrStar[i].catnumber, arrCatStar[j].catnumber, TYCHONUMBER );
     // fprintf(stderr,"arrStar[i].catnumber=_%s_ arrCatStar[i].catnumber=_%s_\n",arrStar[i].catnumber,arrCatStar[i].catnumber);
     //  The positional coincidence is so good that we accept this mathc with no further consideration
     //     if( distance < ACCEPT_DISTANCE_DEGREES ) {
     //      break;
     //     }
    }
   }
  }
  //  fprintf(stderr,"max_M=%ld\n",max_M);
 }
 // So, how many stars we have matched?
 // And wirite the output file BTW...
 calibfile= fopen( "calib.txt", "w" );
 if ( NULL == calibfile ) {
  fprintf( stderr, "ERROR! Cannot open calib.txt for writing!\n" );
  exit( EXIT_FAILURE );
 }
 for ( i= 0; i < N; i++ ) {
  if ( arrStar[i].matched_with_catalog == 1 ) {
   // fprintf(stderr,"%s %lf %lf %d  %lf\n",arrStar[i].catnumber,arrStar[i].ALPHA_catalog,arrStar[i].DELTA_catalog,arrStar[i].good_star,arrStar[i].distance_from_catalog_position);
   // fprintf(calibfile,"%.5lf %.5lf %.5lf\n", arrStar[i].MAG_APER, arrStar[i].V, arrStar[i].MAGERR_APER);
   if ( arrStar[i].good_star == 1 ) {
    // fprintf(stderr,"good star!\n");
    fprintf( calibfile, "%.4lf %.4lf %.4lf\n", arrStar[i].MAG_APER, arrStar[i].V, 0.01 ); // write it out for the magnitude calibration!
    // Ok, actually we write this file for backward compatibility with lib/fit_mag_calib
    // here is what we actually use
    mag_zeropoint[mag_zeropoint_counter]= arrStar[i].V - arrStar[i].MAG_APER;
    // fprintf(stdout,"%lf\n",mag_zeropoint[mag_zeropoint_counter]);
    mag_zeropoint_counter++;
   }
   N_mantch++;
  }
 }
 fclose( calibfile );
 fprintf( stderr, "Relation between the catalog and instrumental magnitudes is written to calib.txt\n" );
 fprintf( stdout, "0.000000 1.000000 %9.6lf\n", gsl_stats_mean( mag_zeropoint, 1, mag_zeropoint_counter ) );
 free( mag_zeropoint );
 return N_mantch;
}

int read_tycho_cat( struct CatStar *arrCatStar, long *M, double *image_boundaries_radec ) {
 long i= 0;
 FILE *tychofile;
 int tychofilecounter;
 char tychofiles[20][32]= { "lib/catalogs/tycho2/tyc2.dat.00", "lib/catalogs/tycho2/tyc2.dat.01", "lib/catalogs/tycho2/tyc2.dat.02", "lib/catalogs/tycho2/tyc2.dat.03", "lib/catalogs/tycho2/tyc2.dat.04",
                            "lib/catalogs/tycho2/tyc2.dat.05", "lib/catalogs/tycho2/tyc2.dat.06", "lib/catalogs/tycho2/tyc2.dat.07", "lib/catalogs/tycho2/tyc2.dat.08", "lib/catalogs/tycho2/tyc2.dat.09", "lib/catalogs/tycho2/tyc2.dat.10",
                            "lib/catalogs/tycho2/tyc2.dat.11", "lib/catalogs/tycho2/tyc2.dat.12", "lib/catalogs/tycho2/tyc2.dat.13", "lib/catalogs/tycho2/tyc2.dat.14", "lib/catalogs/tycho2/tyc2.dat.15", "lib/catalogs/tycho2/tyc2.dat.16",
                            "lib/catalogs/tycho2/tyc2.dat.17", "lib/catalogs/tycho2/tyc2.dat.18", "lib/catalogs/tycho2/tyc2.dat.19" };
 char tychostr[TYCHOSTRING];
 for ( tychofilecounter= 0; tychofilecounter < 20; tychofilecounter++ ) {
  fprintf( stderr, "Reading Tycho2 catalog file %s\n", tychofiles[tychofilecounter] );
  tychofile= fopen( tychofiles[tychofilecounter], "r" );
  if ( tychofile == NULL ) {
   fprintf( stderr, "ERROR: cannot open Tycho2 catalog file %s\n", tychofiles[tychofilecounter] );
   exit( EXIT_FAILURE );
  }
  memset( tychostr, 0, TYCHOSTRING ); // reset the string just in case
  while ( NULL != fgets( tychostr, TYCHOSTRING, tychofile ) ) {
   tychostr[TYCHOSTRING - 1]= '\0'; // just in case
   arrCatStar[i].ALPHA_catalog= get_RA_from_string( tychostr );
   if ( arrCatStar[i].ALPHA_catalog < image_boundaries_radec[0] )
    continue;
   if ( arrCatStar[i].ALPHA_catalog > image_boundaries_radec[1] )
    continue;
   arrCatStar[i].DELTA_catalog= get_Dec_from_string( tychostr );
   if ( arrCatStar[i].DELTA_catalog < image_boundaries_radec[2] )
    continue;
   if ( arrCatStar[i].DELTA_catalog > image_boundaries_radec[3] )
    continue;
   arrCatStar[i].VT= get_VT_from_string( tychostr );
   if ( arrCatStar[i].VT == 0.0 )
    continue;
   arrCatStar[i].BT= get_BT_from_string( tychostr );
   if ( arrCatStar[i].BT == 0.0 )
    continue;
   memset( arrCatStar[i].catnumber, 0, TYCHONUMBER ); // reset the string just in case
   get_catnumber_from_string( tychostr, arrCatStar[i].catnumber );
   //   fprintf(stderr,"%s  %lf %lf  %lf %lf\n",arrCatStar[i].catnumber,arrCatStar[i].ALPHA_catalog,arrCatStar[i].DELTA_catalog,arrCatStar[i].BT,arrCatStar[i].VT);
   i++;
  }
  fclose( tychofile );
 }
 ( *M )= i;
 return 0;
}

int read_sextractor_cat( char *catalog_name, struct Star *arrStar, int *N, double *image_boundaries_radec ) {
 double *RA_array; // need this to compute image center
 double *DEC_array;
 int N_lines_in_catalog;
 int i= 0;
 FILE *sexcatfile;

 N_lines_in_catalog= count_lines_in_ASCII_file( catalog_name );
 if ( N_lines_in_catalog < MIN_NUMBER_OF_STARS_ON_FRAME ) {
  fprintf( stderr, "ERROR in read_sextractor_cat(): too few lines in %s!\n", catalog_name );
  exit( EXIT_FAILURE );
 }
 // RA_array=malloc(MAX_NUMBER_OF_STARS_ON_IMAGE*sizeof(double));
 RA_array= malloc( N_lines_in_catalog * sizeof( double ) );
 // DEC_array=malloc(MAX_NUMBER_OF_STARS_ON_IMAGE*sizeof(double));
 DEC_array= malloc( N_lines_in_catalog * sizeof( double ) );

 if ( NULL == RA_array || NULL == DEC_array ) {
  fprintf( stderr, "ERROR: allocating memory in read_sextractor_cat()\n" );
  exit( EXIT_FAILURE );
 }

 sexcatfile= fopen( catalog_name, "r" );
 if ( sexcatfile == NULL ) {
  fprintf( stderr, "ERROR: cannot open %s!\n", catalog_name );
  exit( EXIT_FAILURE );
 }
 // while(-1<fscanf(sexcatfile,"%d  %lf %lf  %lf %lf  %lf %lf %lf %lf  %lf %lf %lf %lf %lf %lf  %d %lf", &arrStar[i].NUMBER, &arrStar[i].FLUX_APER, &arrStar[i].FLUXERR_APER,
 //  &arrStar[i].MAG_APER, &arrStar[i].MAGERR_APER, &arrStar[i].X_IMAGE, &arrStar[i].Y_IMAGE, &arrStar[i].ALPHA_SKY, &arrStar[i].DELTA_SKY,
 //  &arrStar[i].A_IMAGE, &arrStar[i].ERRA_IMAGE, &arrStar[i].B_IMAGE, &arrStar[i].ERRB_IMAGE, &arrStar[i].A_WORLD, &arrStar[i].B_WORLD, &arrStar[i].FLAGS,&arrStar[i].CLASS_STAR)){
 while ( -1 < fscanf( sexcatfile, "%d  %lf %lf  %lf %lf  %lf %lf %lf %lf  %d",
                      &arrStar[i].NUMBER,
                      &arrStar[i].ALPHA_SKY, &arrStar[i].DELTA_SKY,
                      &arrStar[i].X_IMAGE, &arrStar[i].Y_IMAGE,
                      &arrStar[i].FLUX_APER,
                      &arrStar[i].FLUXERR_APER,
                      &arrStar[i].MAG_APER,
                      &arrStar[i].MAGERR_APER,
                      &arrStar[i].FLAGS ) ) {

  //&arrStar[i].A_IMAGE, &arrStar[i].ERRA_IMAGE,
  //&arrStar[i].B_IMAGE, &arrStar[i].ERRB_IMAGE,
  //&arrStar[i].A_WORLD, &arrStar[i].B_WORLD,
  //&arrStar[i].CLASS_STAR)){
  // Some basic setup
  arrStar[i].matched_with_catalog= 0;
  arrStar[i].good_star= 1;

  // Check star quality
  if ( arrStar[i].FLAGS > 0 )
   arrStar[i].good_star= 0;
  if ( arrStar[i].FLUX_APER / arrStar[i].FLUXERR_APER < 5.0 )
   arrStar[i].good_star= 0;
  if ( arrStar[i].MAG_APER > 0.0 )
   arrStar[i].good_star= 0;
  if ( arrStar[i].MAG_APER < -30.0 )
   arrStar[i].good_star= 0;
  // if( arrStar[i].CLASS_STAR>0.9 )arrStar[i].good_star=0;
  if ( arrStar[i].MAGERR_APER > 1.0 )
   arrStar[i].good_star= 0;

  RA_array[i]= arrStar[i].ALPHA_SKY;
  DEC_array[i]= arrStar[i].DELTA_SKY;

  i++;
 }
 fclose( sexcatfile );
 ( *N )= i;
 image_boundaries_radec[0]= gsl_stats_min( RA_array, 1, i );
 image_boundaries_radec[1]= gsl_stats_max( RA_array, 1, i );
 image_boundaries_radec[2]= gsl_stats_min( DEC_array, 1, i );
 image_boundaries_radec[3]= gsl_stats_max( DEC_array, 1, i );
 free( RA_array );
 free( DEC_array );
 return 0;
}

int create_tycho2_list_of_bright_stars_to_exclude_from_transient_search( double faint_mag_limit_for_the_list ) {
 double star_VT, star_RA, star_Dec;
 long i= 0;
 FILE *outputradeclist;
 FILE *tychofile;
 int tychofilecounter;
 char tychofiles[20][32]= { "lib/catalogs/tycho2/tyc2.dat.00", "lib/catalogs/tycho2/tyc2.dat.01", "lib/catalogs/tycho2/tyc2.dat.02", "lib/catalogs/tycho2/tyc2.dat.03", "lib/catalogs/tycho2/tyc2.dat.04",
                            "lib/catalogs/tycho2/tyc2.dat.05", "lib/catalogs/tycho2/tyc2.dat.06", "lib/catalogs/tycho2/tyc2.dat.07", "lib/catalogs/tycho2/tyc2.dat.08", "lib/catalogs/tycho2/tyc2.dat.09", "lib/catalogs/tycho2/tyc2.dat.10",
                            "lib/catalogs/tycho2/tyc2.dat.11", "lib/catalogs/tycho2/tyc2.dat.12", "lib/catalogs/tycho2/tyc2.dat.13", "lib/catalogs/tycho2/tyc2.dat.14", "lib/catalogs/tycho2/tyc2.dat.15", "lib/catalogs/tycho2/tyc2.dat.16",
                            "lib/catalogs/tycho2/tyc2.dat.17", "lib/catalogs/tycho2/tyc2.dat.18", "lib/catalogs/tycho2/tyc2.dat.19" };
 char tychostr[TYCHOSTRING];

 fprintf( stderr, "Creating a list of Tycho2 stars with VT<%.2lf \n", faint_mag_limit_for_the_list );

 outputradeclist= fopen( "lib/catalogs/list_of_bright_stars_from_tycho2.txt", "w" );
 if ( outputradeclist == NULL ) {
  fprintf( stderr, "ERROR: cannot open lib/catalogs/list_of_bright_stars_from_tycho2.txt for wrigting!\n" );
  return 1;
 }

 for ( tychofilecounter= 0; tychofilecounter < 20; tychofilecounter++ ) {
  fprintf( stderr, "Reading Tycho2 catalog file %s\n", tychofiles[tychofilecounter] );
  tychofile= fopen( tychofiles[tychofilecounter], "r" );
  if ( tychofile == NULL ) {
   fprintf( stderr, "ERROR: cannot open Tycho2 catalog file %s\n", tychofiles[tychofilecounter] );
   exit( EXIT_FAILURE );
  }
  memset( tychostr, 0, TYCHOSTRING ); // reset the string just in case
  while ( NULL != fgets( tychostr, TYCHOSTRING, tychofile ) ) {
   tychostr[TYCHOSTRING - 1]= '\0'; // just in case
   star_VT= get_VT_from_string( tychostr );
   if ( star_VT > faint_mag_limit_for_the_list ) {
    continue;
   }
   if ( star_VT == 0.0 ) {
    continue;
   }
   star_RA= get_RA_from_string( tychostr );
   if ( star_RA == 0.0 ) {
    continue;
   }
   star_Dec= get_Dec_from_string( tychostr );
   if ( star_Dec == 0.0 ) {
    continue;
   }
   fprintf( outputradeclist, "%lf %lf \n", star_RA, star_Dec );
   i++;
  }
  fclose( tychofile );
 }

 fclose( outputradeclist );

 fprintf( stderr, "The list of Tycho2 stars with VT<%.2lf is written to lib/catalogs/list_of_bright_stars_from_tycho2.txt \n", faint_mag_limit_for_the_list );
 return 0;
}
