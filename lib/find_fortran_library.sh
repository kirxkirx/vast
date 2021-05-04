#!/usr/bin/env bash
#
# This small script is used in Makefile
# It tries to find a C-Fortran library
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

CC=`lib/find_gcc_compiler.sh`

# and here is a really good one
GCC_MAJOR_VERSION=`$CC -dumpversion | cut -f1 -d.`
if [ $GCC_MAJOR_VERSION -ge 4 ];then
 echo "-lgfortran"
else
 echo "-lg2c"
fi
