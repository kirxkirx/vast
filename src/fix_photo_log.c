#include <stdio.h>
#include "vast_limits.h"

int main() {
 char str[MAX_LOG_STR_LENGTH];
 int i;
 while( NULL != fgets(str, MAX_LOG_STR_LENGTH, stdin) ) {
  for( i= 17; i < 21; i++ )
   if( str[i] == ' ' )
    str[i]= '0';
  fputs(str, stdout);
 }
 return 0;
}
