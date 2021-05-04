#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Check if C compiler name was supplied
if [ ! -z $1 ];then
 CC=$1
else
 CC=`lib/find_gcc_compiler.sh`
fi

FC=`lib/find_fortran_compiler.sh`


# Check if gcc and gfortan versions match (only if using gcc version >=4)
GCC_MAJOR_VERSION=`$CC -dumpversion | cut -f1 -d.`
if [ $GCC_MAJOR_VERSION -ge 4 ];then
 # Check if gcc and gfortan versions match
 FORTRAN_VERSION=`$FC -dumpversion`
 GCC_VERSION=`$CC -dumpversion`
 # Check if we can actually perform this check
 # (some versions of gfortran do not react properly on gfortran -dumpversion)
 if [ ${#FORTRAN_VERSION} -lt 10 ];then
  if [ "$FORTRAN_VERSION" != "$GCC_VERSION" ];then                                              
   echo "ERROR: version mismatch between the C ($CC) and FORTRAN ($FC) compilers!
$CC version $GCC_VERSION is found in"
command -v $CC
echo "$FC version $FORTRAN_VERSION is found in"
command -v $FC
echo "Please re-install both gcc and gfortran to make sure they have the same version."
   exit 1
  fi
 else
  echo "WARNING: cannot compare gcc and gfortran versions. Will continue assuming everything is fine." 
 fi # if [ ${#FORTRAN_VERSION} -lt 10 ];then
fi
