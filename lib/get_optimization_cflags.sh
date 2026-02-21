#!/usr/bin/env bash
#
# This script outputs all optimization CFLAGS used for VaST compilation
# It combines flags from various detection scripts to ensure consistency
# across the main build and library builds (CFITSIO, etc.)
#
# Usage: get_optimization_cflags.sh [nolto]
#   nolto - Skip LTO flags (useful for libraries with compatibility issues)
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=$(readlink -f "$1" 2>/dev/null)
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=$(greadlink -f "$1" 2>/dev/null)
   if [ $? -ne 0 ];then
    REALPATH=$(realpath "$1" 2>/dev/null)
    if [ $? -ne 0 ];then
     REALPATH=$(grealpath "$1" 2>/dev/null)
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")" || exit 1
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit 1
     fi
    fi
   fi
  fi
  echo "$REALPATH"
}

# Find the directory containing this script
PATH_TO_THIS_SCRIPT=$(vastrealpath "$0")
PATH_TO_LIB_DIR=$(dirname "$PATH_TO_THIS_SCRIPT")

# Collect optimization flags from various scripts
OPTIMIZATION_CFLAGS=""

# Base optimization level
OPTIMIZATION_CFLAGS="$OPTIMIZATION_CFLAGS -O2"

# Architecture-specific optimizations (-march=native on Linux)
MARCH_FLAGS=$("$PATH_TO_LIB_DIR"/set_good_march.sh)
if [ -n "$MARCH_FLAGS" ];then
 OPTIMIZATION_CFLAGS="$OPTIMIZATION_CFLAGS $MARCH_FLAGS"
fi

# Link-Time Optimization (skip if 'nolto' argument provided)
if [ "$1" != "nolto" ];then
 LTO_FLAGS=$("$PATH_TO_LIB_DIR"/set_lto.sh)
 if [ -n "$LTO_FLAGS" ];then
  OPTIMIZATION_CFLAGS="$OPTIMIZATION_CFLAGS $LTO_FLAGS"
 fi
fi

# OpenMP (if needed - though CFITSIO probably doesn't use it)
# OMP_FLAGS=$("$PATH_TO_LIB_DIR"/set_openmp.sh)
# if [ -n "$OMP_FLAGS" ];then
#  OPTIMIZATION_CFLAGS="$OPTIMIZATION_CFLAGS $OMP_FLAGS"
# fi

# Output the combined flags (remove leading/trailing whitespace)
echo "$OPTIMIZATION_CFLAGS" | awk '{$1=$1};1'
