#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Check GCC version
CC=`lib/find_gcc_compiler.sh`
GCC_MAJOR_VERSION=`$CC -dumpversion | cut -f1 -d.` ; 
GCC_MINOR_VERSION=`$CC -dumpversion | cut -f2 -d.` ;

GONOGO=0 # 0 - no-go; 1 - go

if [ $GCC_MAJOR_VERSION -gt 4 ];then
 GONOGO=1
fi

# if >gcc-4.3  
if [ $GCC_MAJOR_VERSION -ge 4 ];then 
 if [ $GCC_MINOR_VERSION -ge 3 ];then
  GONOGO=1
 fi 
fi

# Disable OpenMP on systems with small physical memory as it may cause problems there
if [ $GONOGO -eq 1 ];then
 RAM_SIZE_BYTES=""
 command -v uname &> /dev/null
 if [ $? -eq 0 ];then
  OS=`uname`
 else
  OS="unknown"
 fi
 if [ "$OS" != "Linux" ];then 
  # FreeBSD or Mac
  command -v sysctl &> /dev/null
  if [ $? -eq 0 ];then
   RAM_SIZE_BYTES=`sysctl -n hw.physmem`
   if [ $? -ne 0 ] || [ -z "$RAM_SIZE_BYTES" ] ;then
    RAM_SIZE_BYTES=`sysctl -n hw.memsize`
   fi
  fi # sysctl
 else 
  # Linux
  if [ -f /proc/meminfo ];then 
   # Check that the memory size is written in units of kB
   grep MemTotal /proc/meminfo | grep --quiet kB
   if [ $? -eq 0 ];then
    RAM_SIZE_KBYTES=`grep MemTotal /proc/meminfo | awk '{print $2}'`
    if [ ! -z "$RAM_SIZE_KBYTES" ];then
     #RAM_SIZE_BYTES=`echo "$RAM_SIZE_KBYTES*1024" | bc -q`
     RAM_SIZE_BYTES=`echo "$RAM_SIZE_KBYTES*1024" | awk '{print $1*1024}'`
    fi
   fi
  fi
 fi # if [ "$OS" != "Linux" ];then
 # OK, supposedly we got the memory size, now compare it with 1GB
 if [ ! -z "$RAM_SIZE_BYTES" ] ;then
  #echo "Derived RAM size: $RAM_SIZE_BYTES B" >> /dev/stderr
  #TEST=`echo "$RAM_SIZE_BYTES<1024*1024*1024" | bc -ql`
  TEST=`echo "$RAM_SIZE_BYTES<1073741824" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
  # Test if the bc output looks suitable for BASH comparison
  re='^[0-9]+$'
  if [[ $TEST =~ $re ]] ; then
   if [ $TEST -eq 1 ];then
    GONOGO=0
   fi
  fi
  #    
 fi
fi # if [ $GONOGO -eq 1 ];then

if [ $GONOGO -eq 1 ];then
 # Try to use -fopenmp
 echo "
/*
  OpenMP example program Hello World.
  The master thread forks a parallel region.
  All threads in the team obtain their thread number and print it.
  Only the master thread prints the total number of threads.
  Compile with: gcc -O3 -fopenmp omp_hello.c -o omp_hello
*/

#include <omp.h>
#include <stdio.h>
#include <stdlib.h>

int main (int argc, char *argv[]) {
  
  int nthreads, tid;

  /* Fork a team of threads giving them their own copies of variables */
#pragma omp parallel private(nthreads, tid)
  {
    /* Get thread number */
    tid = omp_get_thread_num();
    fprintf(stderr,\"Hello World from thread = %d\n\", tid);
    
    /* Only master thread does this */
    if (tid == 0) {
      nthreads = omp_get_num_threads();
      fprintf(stderr,\"Number of threads = %d\n\", nthreads);
    }
  }  /* All threads join master thread and disband */
  exit(0);
}
" > test.c
 $CC -march=native -fopenmp -o test test.c &>/dev/null
 if [ $? -eq 0 ];then
  # Ahaha, if it compiles, doesn't mean that it works
  ./test &> /dev/null
  if [ $? -eq 0 ];then
   echo -n "-fopenmp -DVAST_ENABLE_OPENMP "
  fi
 fi
 rm -f test test.c
fi

echo -en "\n"
