/*
  This script will quickly remove all out*dat files.
*/

#include <stdio.h>
#include <math.h>
#include <sys/types.h>
#include <dirent.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main() {
 DIR *dp;
 struct dirent *ep;

 dp= opendir( "./" );
 if ( dp != NULL ) {
  // ACTUALLY, if we just cycle through the directory that we are modifying (by deleting files)
  // we are at risk of missing some files. But here I'll consider this tolearble, as the higher-level
  // BASH script should take care of the remaining files.
  // while( ep=readdir(dp) ){
  while ( ( ep= readdir( dp ) ) != NULL ) {
   if ( strlen( ep->d_name ) < 12 ) {
    continue; // make sure the filename is not too short for the following tests
   }
   // out01234.dat
   if ( ep->d_name[0] == 'o' && ep->d_name[1] == 'u' && ep->d_name[2] == 't' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'd' ) {
    unlink( ep->d_name );
    continue;
   }
   // image01234.cat
   if ( ep->d_name[0] == 'i' && ep->d_name[1] == 'm' && ep->d_name[2] == 'a' && ep->d_name[3] == 'g' && ep->d_name[4] == 'e' && ep->d_name[strlen( ep->d_name ) - 1] == 't' && ep->d_name[strlen( ep->d_name ) - 2] == 'a' && ep->d_name[strlen( ep->d_name ) - 3] == 'c' ) {
    unlink( ep->d_name );
    continue;
   }
   // image*.cat.*
   if ( ep->d_name[0] == 'i' && ep->d_name[1] == 'm' && ep->d_name[2] == 'a' && ep->d_name[3] == 'g' && ep->d_name[4] == 'e' ) {
    if ( NULL != strstr( ep->d_name, ".cat." ) ) {
     unlink( ep->d_name );
     continue;
    }
   }
   /*
   if ( ep->d_name[0] == 'i' && ep->d_name[1] == 'm' && ep->d_name[2] == 'a' && ep->d_name[3] == 'g' && ep->d_name[4] == 'e' && ep->d_name[strlen( ep->d_name ) - 1] == 'e' && ep->d_name[strlen( ep->d_name ) - 2] == 'r' && ep->d_name[strlen( ep->d_name ) - 3] == 'u' && ep->d_name[strlen( ep->d_name ) - 4] == 't' && ep->d_name[strlen( ep->d_name ) - 5] == 'r' && ep->d_name[strlen( ep->d_name ) - 6] == 'e' && ep->d_name[strlen( ep->d_name ) - 7] == 'p' && ep->d_name[strlen( ep->d_name ) - 8] == 'a' ) {
    unlink( ep->d_name );
    continue;
   }
   // image00055.cat.info
   if ( ep->d_name[0] == 'i' && ep->d_name[1] == 'm' && ep->d_name[2] == 'a' && ep->d_name[3] == 'g' && ep->d_name[4] == 'e' && ep->d_name[strlen( ep->d_name ) - 1] == 'o' && ep->d_name[strlen( ep->d_name ) - 2] == 'f' && ep->d_name[strlen( ep->d_name ) - 3] == 'n' && ep->d_name[strlen( ep->d_name ) - 4] == 'i' && ep->d_name[strlen( ep->d_name ) - 5] == '.' ) {
    unlink( ep->d_name );
    continue;
   }
   // image00055.cat.mag*
   // TBA
*/
  }
  (void)closedir( dp );
 } else {
  perror( "Couldn't open the directory" );
 }

 return 0;
}
