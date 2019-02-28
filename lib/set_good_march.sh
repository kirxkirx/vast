#!/usr/bin/env bash

# Check OS
OS_NAME=`uname`
if [ "$OS_NAME" != "Linux" ];then
 echo -en "\n"
 exit
fi

# Need to set path to this script to make sure we'll find lib/find_gcc_compiler.sh and src/
PATH_TO_THIS_SCRIPT=`readlink -f $0`
PATH_TO_LIB_DIR=`dirname $PATH_TO_THIS_SCRIPT`
PATH_TO_VAST_DIR=`dirname $PATH_TO_LIB_DIR`
#

# Check GCC version
#CC=`lib/find_gcc_compiler.sh`
CC=`"$PATH_TO_LIB_DIR"/find_gcc_compiler.sh`
GCC_MAJOR_VERSION=`$CC -dumpversion | cut -f1 -d.` ; 
GCC_MINOR_VERSION=`$CC -dumpversion | cut -f2 -d.` ;

GONOGO=0 # 0 - no-go; 1 - go
                     
if [ $GCC_MAJOR_VERSION -gt 4 ];then
 GONOGO=1
fi


# if >gcc-4.2  -march=native
if [ $GCC_MAJOR_VERSION -ge 4 ];then 
 if [ $GCC_MINOR_VERSION -ge 2 ];then
  GONOGO=1
 fi 
fi

# Simple test, check if the C compiler understands the parameter "-march=native" at all
if [ $GONOGO -eq 1 ];then
 # Try to use -march=native
 echo "int main(){return 0;}" > test.c
 $CC -march=native -o test test.c &>/dev/null
 if [ $? -ne 0 ];then
  GONOGO=0
 fi
 rm -f test test.c
fi

# Yes, this works only now when lib/set_good_march.sh runs only once befoe
# the actual compilation starts.
#
# A more complicated test that is supposed to catch the misterious bug
# that apperas with some combination of an older gcc and newer processor(???)
if [ $GONOGO -eq 1 ];then
 # On the machine were the bug was discovered, compilation was crashing on this file
 # (lib/include contains the GSL include files)
 $CC -O2 -march=native -c -o photocurve.o "$PATH_TO_VAST_DIR/"src/photocurve.c -I"$PATH_TO_VAST_DIR/"lib/include &>/dev/null
 if [ $? -ne 0 ];then
  GONOGO=0
 fi
 # Remove photocurve.o as who knows with which compiler flags the user wants it to be actually compiled
 rm -f photocurve.o
fi

# If we are still go
if [ $GONOGO -eq 1 ];then
 # Print-out the string with the desired compiler option
 echo -n "-march=native "
fi

echo -en "\n"
