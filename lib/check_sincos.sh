#!/usr/bin/env bash

# Check GCC version
CC=`lib/find_gcc_compiler.sh`
GONOGO=1

# Try to use __builtin_isnormal
echo "#define _GNU_SOURCE
#include <math.h>
int main(){
 double S,C;
 double angle=M_PI;
 sincos(angle, &S, &C);
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
 echo -n "-DVAST_USE_SINCOS "
fi

echo -en "\n"
