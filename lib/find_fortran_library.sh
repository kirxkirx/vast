#!/usr/bin/env bash
#
# This small script is used in Makefile
# It tries to find a C-Fortran library
#

CC=`lib/find_gcc_compiler.sh`

# and here is a really good one
GCC_MAJOR_VERSION=`$CC -dumpversion | cut -f1 -d.`
if [ $GCC_MAJOR_VERSION -ge 4 ];then
 echo "-lgfortran"
else
 echo "-lg2c"
fi
