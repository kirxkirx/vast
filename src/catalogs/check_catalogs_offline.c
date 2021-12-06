#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

//#define VSX_SEARCH_RADIUS_DEG 120.0/3600.0
#define VSX_SEARCH_RADIUS_DEG 35.0 / 3600.0

/* Auxiliary definitions */
#define MAX(a, b) (((a) > (b)) ? (a) : (b))
#define MIN(a, b) (((a) < (b)) ? (a) : (b))

void download_vsx() {
 FILE *f;
 f= fopen("lib/catalogs/vsx.dat", "r");
 if( f == NULL ) {
  fprintf(stderr, "Downloading VSX catalog!\n");
  if( 0 != system("cd lib/catalogs/ ; rm -f vsx.dat.gz ; wget ftp://cdsarc.u-strasbg.fr/pub/cats/B/vsx/vsx.dat.gz ; gunzip vsx.dat.gz") ) {
   fprintf(stderr, "ERROR downloading the VSX catalog!\n");
  }
 } else {
  fclose(f);
  return;
 }

 return;
}

int search_vsx(double target_RA_deg, double target_Dec_deg) {
 FILE *vsx_dat;
 char name[32];
 char RA_char[32];
 char Dec_char[32];
 double RA_deg, Dec_deg, RA1_rad, RA2_rad, DEC1_rad, DEC2_rad;
 char type[32];
 char descr[128];
 char string[256];
 int i, j;

 double distance_deg;

 double best_distance_deg= 90.0;
 char best_name[32];
 char best_type[32];
 char best_descr[128];

 int is_found= 0;

 // Initialize memory, otherwise valgrind complains about uninitialized 'type'
 memset(name, '\0', 32);
 memset(RA_char, '\0', 32);
 memset(Dec_char, '\0', 32);
 memset(type, '\0', 32);
 memset(descr, '\0', 128);
 memset(string, '\0', 256);
 memset(best_name, '\0', 32);
 memset(best_type, '\0', 32);
 memset(best_descr, '\0', 128);

 //download_vsx();
 vsx_dat= fopen("lib/catalogs/vsx.dat", "r");
 if( NULL == vsx_dat ) {
  fprintf(stderr, "ERROR: Cannot open vsx.dat\n");
  return -1;
 }
 while( NULL != fgets(string, 256, vsx_dat) ) {

  for( j= 0, i= 51; i < 60; i++, j++ )
   Dec_char[j]= string[i];
  Dec_char[j]= '\0';

  Dec_deg= atof(Dec_char);
  if( fabs(target_Dec_deg - Dec_deg) > VSX_SEARCH_RADIUS_DEG )
   continue;

  for( j= 0, i= 8; i < 38; i++, j++ )
   name[j]= string[i];
  name[j]= '\0';

  for( j= 0, i= 41; i < 50; i++, j++ )
   RA_char[j]= string[i];
  RA_char[j]= '\0';
  for( j= 0, i= 61; i < 70; i++, j++ )
   type[j]= string[i];
  for( j= 0; j < 32; j++ )
   if( type[j] == ' ' ) {
    type[j]= '\0';
    break;
   }
  //  for ( j= 0; j < 92 - 61; j++ )
  //   if ( type[j] == ' ' )
  //    type[j]= '\0';
  for( j= 0, i= 91; i < (int)strlen(string); i++, j++ )
   descr[j]= string[i];
  descr[j]= '\0';

  RA_deg= atof(RA_char);

  RA1_rad= RA_deg * 3600 / 206264.8;
  RA2_rad= target_RA_deg * 3600 / 206264.8;
  DEC1_rad= Dec_deg * 3600 / 206264.8;
  DEC2_rad= target_Dec_deg * 3600 / 206264.8;

  // yes, it mathces the definition in src/put_two_sources_in_one_field.c
  distance_deg= acos(cos(DEC1_rad) * cos(DEC2_rad) * cos(MAX(RA1_rad, RA2_rad) - MIN(RA1_rad, RA2_rad)) + sin(DEC1_rad) * sin(DEC2_rad)) * 206264.8 / 3600.0;

  if( distance_deg < VSX_SEARCH_RADIUS_DEG ) {
   if( is_found == 0 )
    fprintf(stdout, "The object was <font color=\"green\">found</font> in <font color=\"blue\">VSX</font>\n");
   is_found= 1;
   //fprintf(stdout,"%2.0lf\"  %s\nType: %s\n#   Max.           Min./Amp.       JD0           Period\n%s",distance_deg*3600.0,name,type,descr);
   if( distance_deg < best_distance_deg ) {
    best_distance_deg= distance_deg;
    strncpy(best_name, name, 32);
    best_name[31 - 1]= '\0';
    strncpy(best_type, type, 32);
    best_type[31 - 1]= '\0';
    strncpy(best_descr, descr, 128);
    best_descr[128 - 1]= '\0';
   }
  }
 }
 if( is_found == 0 ) {
  fprintf(stdout, "The object was <font color=\"red\">not found</font> in <font color=\"blue\">VSX</font>\n");
 } else {
  fprintf(stdout, "%2.0lf\"  %s\nType: %s\n#   Max.           Min./Amp.       JD0           Period\n%s", best_distance_deg * 3600.0, best_name, best_type, best_descr);
 }

 fclose(vsx_dat);

 return is_found;
}

void download_asassnv() {
 FILE *f;
 f= fopen("lib/catalogs/asassnv.csv", "r");
 if( f == NULL ) {
  fprintf(stderr, "Downloading ASASSN-V catalog!\n");
  if( 0 != system("cd lib/catalogs/ ; rm -f  asassnv.csv ; wget -O 'asassnv.csv' 'https://asas-sn.osu.edu/variables/catalog.csv'") ) {
   fprintf(stderr, "ERROR downloading the ASASSN-V catalog!\n");
  }
 } else {
  fclose(f);
  return;
 }

 return;
}

const char *getfield_from_csv_string(char *line, int num) {
 const char *tok;
 for( tok= strtok(line, ",");
      tok && *tok;
      tok= strtok(NULL, ",\n") ) {
  if( !--num )
   return tok;
 }
 return NULL;
}

int search_asassnv(double target_RA_deg, double target_Dec_deg) {
 FILE *vsx_dat;
 char name[32];
 // char RA_char[32];
 // char Dec_char[32];
 double RA_deg, Dec_deg, RA1_rad, RA2_rad, DEC1_rad, DEC2_rad;
 char type[32];
 char MeanMag[32];
 char Amplitude[32];
 char Period[32];
 char Url[32];
 //char descr[128];
 char string[4096];
 char string_noemptycells[4096];
 char string_to_be_ruined_by_strok[4096];
 int i, j;

 double distance_deg;

 int is_found= 0;

 download_asassnv();
 vsx_dat= fopen("lib/catalogs/asassnv.csv", "r");
 if( NULL == vsx_dat ) {
  fprintf(stderr, "ERROR: Cannot open asassnv.csv\n");
  exit(1);
 }
 while( NULL != fgets(string, 4096 - 1, vsx_dat) ) {
  if( NULL == string ) {
   continue;
  }
  if( strlen(string) < 180 ) {
   // That happens all too often!
   //   fprintf(stderr,"WARNING from search_asassnv() a string in lib/catalogs/asassnv.csv is too short:\n%s\n",string);
   continue;
  }
  // fix the FIRST PART of string for strtok() as it cannot handle empty cells ",,"
  // Assume Name RA and Dec will all fit within the first 100 characters
  //for( i= 0, j= 0; i < 4096 - 1; i++, j++ ) {
  for( i= 0, j= 0; i < 100; i++, j++ ) {
   if( j == 4096 - 1 ) {
    string_noemptycells[j]= '\0';
    break;
   }
   string_noemptycells[j]= string[i];
   //if( i < 4096 - 1 ) {
   if( i < 4096 - 2 ) {
    if( string[i] == ',' ) {
     if( string[i + 1] == ',' ) {
      j++;
      string_noemptycells[j]= ' '; // add empty cell
     }
    }
   }
  }
  //
  string_noemptycells[j]= '\0'; // !!
  //
  if( NULL == string_noemptycells ) {
   fprintf(stderr, "ERROR in search_asassnv(): string_noemptycells==NULL\n");
   exit(1);
  }
  // We should do this before each invocation of getfield_from_csv_string() !!!
  strncpy(string_to_be_ruined_by_strok, string_noemptycells, 4096 - 1);
  string_to_be_ruined_by_strok[4096 - 1]= '\0'; // just in case
  // Skip the header line
  if( 0 == strncmp("ASAS-SN Name", getfield_from_csv_string(string_to_be_ruined_by_strok, 1), strlen("ASAS-SN Name")) ) {
   continue;
  }
  //

  //// Dec
  // We should do this before each invocation of getfield_from_csv_string() !!!
  strncpy(string_to_be_ruined_by_strok, string_noemptycells, 4096 - 1);
  string_to_be_ruined_by_strok[4096 - 1]= '\0'; // just in case
  Dec_deg= atof(getfield_from_csv_string(string_to_be_ruined_by_strok, 5));
  if( fabs(target_Dec_deg - Dec_deg) > VSX_SEARCH_RADIUS_DEG )
   continue;

  //// RA
  // We should do this before each invocation of getfield_from_csv_string() !!!
  strncpy(string_to_be_ruined_by_strok, string_noemptycells, 4096 - 1);
  string_to_be_ruined_by_strok[4096 - 1]= '\0'; // just in case
  RA_deg= atof(getfield_from_csv_string(string_to_be_ruined_by_strok, 4));

  RA1_rad= RA_deg * 3600 / 206264.8;
  RA2_rad= target_RA_deg * 3600 / 206264.8;
  DEC1_rad= Dec_deg * 3600 / 206264.8;
  DEC2_rad= target_Dec_deg * 3600 / 206264.8;

  // yes, it mathces the definition in src/put_two_sources_in_one_field.c
  distance_deg= acos(cos(DEC1_rad) * cos(DEC2_rad) * cos(MAX(RA1_rad, RA2_rad) - MIN(RA1_rad, RA2_rad)) + sin(DEC1_rad) * sin(DEC2_rad)) * 206264.8 / 3600.0;

  if( distance_deg < VSX_SEARCH_RADIUS_DEG ) {

   ////// Do the nasty conversions only if this is our star //////

   // fix the FULL string for strtok() as it cannot handle empty cells ",,"
   for( i= 0, j= 0; i < 4096 - 1; i++, j++ ) {
    if( j == 4096 - 1 ) {
     string_noemptycells[j]= '\0';
     break;
    }
    string_noemptycells[j]= string[i];
    //if( i < 4096 - 1 ) {
    if( i < 4096 - 2 ) {
     if( string[i] == ',' ) {
      if( string[i + 1] == ',' ) {
       j++;
       string_noemptycells[j]= ' '; // add empty cell
      }
     }
    }
   }
   //
   string_noemptycells[j]= '\0'; // !!
   //

   //// Name
   // We should do this before each invocation of getfield_from_csv_string() !!!
   strncpy(string_to_be_ruined_by_strok, string_noemptycells, 4096 - 1);
   string_to_be_ruined_by_strok[4096 - 1]= '\0'; // just in case
   strncpy(name, getfield_from_csv_string(string_to_be_ruined_by_strok, 1), 32);
   name[32 - 1]= '\0'; // just in case

   //// Type
   // We should do this before each invocation of getfield_from_csv_string() !!!
   strncpy(string_to_be_ruined_by_strok, string_noemptycells, 4096 - 1);
   string_to_be_ruined_by_strok[4096 - 1]= '\0'; // just in case
   strncpy(type, getfield_from_csv_string(string_to_be_ruined_by_strok, 9), 32);
   type[32 - 1]= '\0'; // just in case

   //// MeanMag
   // We should do this before each invocation of getfield_from_csv_string() !!!
   strncpy(string_to_be_ruined_by_strok, string_noemptycells, 4096 - 1);
   string_to_be_ruined_by_strok[4096 - 1]= '\0'; // just in case
   strncpy(MeanMag, getfield_from_csv_string(string_to_be_ruined_by_strok, 6), 32);
   MeanMag[32 - 1]= '\0'; // just in case

   //// Amplitude
   // We should do this before each invocation of getfield_from_csv_string() !!!
   strncpy(string_to_be_ruined_by_strok, string_noemptycells, 4096 - 1);
   string_to_be_ruined_by_strok[4096 - 1]= '\0'; // just in case
   strncpy(Amplitude, getfield_from_csv_string(string_to_be_ruined_by_strok, 7), 32);
   Amplitude[32 - 1]= '\0'; // just in case

   //// Period
   // We should do this before each invocation of getfield_from_csv_string() !!!
   strncpy(string_to_be_ruined_by_strok, string_noemptycells, 4096 - 1);
   string_to_be_ruined_by_strok[4096 - 1]= '\0'; // just in case
   strncpy(Period, getfield_from_csv_string(string_to_be_ruined_by_strok, 8), 32);
   Period[32 - 1]= '\0'; // just in case

   //// Url
   // We should do this before each invocation of getfield_from_csv_string() !!!
   strncpy(string_to_be_ruined_by_strok, string_noemptycells, 4096 - 1);
   string_to_be_ruined_by_strok[4096 - 1]= '\0'; // just in case
   strncpy(Url, getfield_from_csv_string(string_to_be_ruined_by_strok, 10), 32);
   Url[32 - 1]= '\0'; // just in case
   ///////////////////////////////////////////////////////////////

   if( is_found == 0 )
    fprintf(stdout, "The object was <font color=\"green\">found</font> in <font color=\"green\">ASASSN-V</font>\n");
   is_found= 1;
   fprintf(stdout, "%2.0lf\"  %s\nType: %s\nMeanMag %s m  Amp. %s m  Period %s d\n<a href=\"https://asas-sn.osu.edu%s\">ASASSN lightcurve</a>\n", distance_deg * 3600.0, name, type, MeanMag, Amplitude, Period, Url);
   break; // find one and be happy
  }
 }
 if( is_found == 0 ) {
  fprintf(stdout, "The object was <font color=\"red\">not found</font> in <font color=\"green\">ASASSN-V</font>\n");
 }

 fclose(vsx_dat);

 return is_found;
}

int main(int argc, char **argv) {

 int is_found;
 double target_RA_deg;
 double target_Dec_deg;

 if( argc < 3 ) {
  fprintf(stderr, "Usage: %s 12.345 67.890\n", argv[0]);
  return 1;
 }

 target_RA_deg= atof(argv[1]);
 if( target_RA_deg < 0.0 || target_RA_deg > 360.0 ) {
  fprintf(stderr, "ERROR: the input RA (%s interpreted as %lf) is our of range!\n", argv[1], target_RA_deg);
  return 2;
 }
 target_Dec_deg= atof(argv[2]);
 if( target_Dec_deg < -90.0 || target_Dec_deg > 90.0 ) {
  fprintf(stderr, "ERROR: the input Dec (%s interpreted as %lf) is our of range!\n", argv[2], target_Dec_deg);
  return 2;
 }

 // This script should take care of updating the catalogs
 if( 0 != system("lib/update_offline_catalogs.sh") ) {
  fprintf(stderr, "WARNING: an error occured while updating the catalogs with lib/update_offline_catalogs.sh\n");
 }

 is_found= 0; // init

 is_found= search_vsx(target_RA_deg, target_Dec_deg);
 if( is_found != 1 ) {
  is_found= search_asassnv(target_RA_deg, target_Dec_deg);
 }

 // Return 0 if the sourceis found
 if( is_found == 1 ) {
  return 0;
 }

 return 1;
}
