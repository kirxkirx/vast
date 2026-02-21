#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Check OS - allow Linux and Darwin (Mac)
OS_TYPE=$(uname)
if [ "$OS_TYPE" != "Linux" ] && [ "$OS_TYPE" != "Darwin" ];then
 echo -en "\n"
 exit
fi

function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=`readlink -f "$1" 2>/dev/null`
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=`greadlink -f "$1" 2>/dev/null`
   if [ $? -ne 0 ];then
    REALPATH=`realpath "$1" 2>/dev/null`
    if [ $? -ne 0 ];then
     REALPATH=`grealpath "$1" 2>/dev/null`
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")"
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD"
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

# Need to set path to this script to make sure we'll find lib/find_gcc_compiler.sh
#PATH_TO_THIS_SCRIPT=`readlink -f $0`
PATH_TO_THIS_SCRIPT=`vastrealpath $0`
PATH_TO_LIB_DIR=`dirname $PATH_TO_THIS_SCRIPT`
#

# Check GCC version
#CC=`lib/find_gcc_compiler.sh`
CC=`"$PATH_TO_LIB_DIR"/find_gcc_compiler.sh`
GCC_MAJOR_VERSION=`$CC -dumpversion | cut -f1 -d.` ; 
GCC_MINOR_VERSION=`$CC -dumpversion | cut -f2 -d.` ;

GONOGO=0 # 0 - no-go; 1 - go

if [ $GCC_MAJOR_VERSION -gt 4 ];then
 LTO_OPTION="-flto=4 "
 GONOGO=1
fi

# if >gcc-4.9  -flto=4
if [ $GCC_MAJOR_VERSION -eq 4 ];then 
 if [ $GCC_MINOR_VERSION -ge 9 ];then
  LTO_OPTION="-flto=4 "
  GONOGO=1
 fi 
fi


# if =gcc-4.8  -flto
if [ $GCC_MAJOR_VERSION -eq 4 ];then 
 if [ $GCC_MINOR_VERSION -eq 8 ];then
  LTO_OPTION="-flto "
  GONOGO=1
 fi 
fi

if [ $GONOGO -eq 1 ];then
 # Try to use -flto
 echo "int main(){return 0;}" > test.c
 $CC -march=native -flto -o test test.c &>/dev/null
 if [ $? -eq 0 ];then
  echo -n "$LTO_OPTION"
 fi
 rm -f test test.c
fi

echo -en "\n"
