#!/usr/bin/env bash

# Check OS
OS_NAME=`uname`
if [ "$OS_NAME" != "Linux" ];then
 echo -en "\n"
 exit
fi

# Need to set path to this script to make sure we'll find lib/find_gcc_compiler.sh
PATH_TO_THIS_SCRIPT=`readlink -f $0`
PATH_TO_LIB_DIR=`dirname $PATH_TO_THIS_SCRIPT`
#PATH_TO_VAST_DIR=`dirname $PATH_TO_LIB_DIR`
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

# if >gcc-4.8  -flto
if [ $GCC_MAJOR_VERSION -ge 4 ];then 
 if [ $GCC_MINOR_VERSION -ge 8 ];then
  GONOGO=1
 fi 
fi

if [ $GONOGO -eq 1 ];then
 # Try to use -flto
 echo "int main(){return 0;}" > test.c
 $CC -march=native -flto -o test test.c &>/dev/null
 if [ $? -eq 0 ];then
  echo -n "-flto "
 fi
 rm -f test test.c
fi

echo -en "\n"
