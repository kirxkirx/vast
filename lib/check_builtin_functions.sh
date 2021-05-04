#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Check GCC version
CC=`lib/find_gcc_compiler.sh`
GONOGO=1

# Try to use __builtin_isnormal
echo "#include <math.h>
int main(){
 __builtin_isnormal(28.0);
 return 0;
}" > test.c
$CC -o test test.c -lm &>/dev/null
if [ $? -ne 0 ];then
 GONOGO=0
fi
rm -f test test.c

# If we are still go
if [ $GONOGO -eq 1 ];then
 # Print-out the string with the desired compiler option
 echo -n "-DVAST_USE_BUILTIN_FUNCTIONS "
fi

echo -en "\n"
