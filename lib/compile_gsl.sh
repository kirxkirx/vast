#!/usr/bin/env bash
#
# This script will compile The GNU Scientific Library (GSL) inside the VaST source tree.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# For compatibility with BSD Make:
# if the script is called by GNU Make MFLAGS="-w" will be set that confuses BSD Make.
export MAKEFLAGS=""
export MFLAGS=""
#

VAST_DIR=$PWD
TARGET_DIR=$VAST_DIR/lib
LIBRARY_SOURCE=$VAST_DIR/src/gsl

echo " "
echo -e "Starting script \033[01;32m$0 $1\033[00m"


if [ "$1" = "clean" ];then
 echo -e "\033[01;34mRemoving the local copy of GSL library\033[00m"
 cd $LIBRARY_SOURCE
 make uninstall
 make clean
 make distclean  
 rm -f *.pdf *.ps
 echo "Script $0 is done."
 echo " "
 exit
fi

echo -e "\033[01;34mCompiling GSL library\033[00m"
echo "Using C compiler: $C_COMPILER"

cd $LIBRARY_SOURCE
make clean
./configure --prefix=$TARGET_DIR
if [ ! $? ];then

 echo "VaST code version/compiler version/compilation date:"
 for COMPILATION_INFO_FILE in .cc.build .cc.version .cc.date ;do
  if [ -f $COMPILATION_INFO_FILE ];then
   cat $COMPILATION_INFO_FILE
  fi
 done

 echo "
VaST installation problem: an error occurred while configuring The GNU Scientific Library (GSL).
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru> by e-mail or 
by creating GitHub issue at https://github.com/kirxkirx/vast

Thank you and sorry for the inconvenience."
 exit 1
fi
make -j9
if [ ! $? ];then

 echo "VaST code version/compiler version/compilation date:"
 for COMPILATION_INFO_FILE in .cc.build .cc.version .cc.date ;do
  if [ -f $COMPILATION_INFO_FILE ];then
   cat $COMPILATION_INFO_FILE
  fi
 done

 echo "
VaST installation problem: an error occurred while compiling The GNU Scientific Library (GSL).
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru> by e-mail or 
by creating GitHub issue at https://github.com/kirxkirx/vast

Thank you and sorry for the inconvenience."
 exit 1
fi
make install
if [ ! $? ];then

 echo "VaST code version/compiler version/compilation date:"
 for COMPILATION_INFO_FILE in .cc.build .cc.version .cc.date ;do
  if [ -f $COMPILATION_INFO_FILE ];then
   cat $COMPILATION_INFO_FILE
  fi
 done

 echo "
VaST installation problem: an error occurred while installing The GNU Scientific Library (GSL).
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru> by e-mail or 
by creating GitHub issue at https://github.com/kirxkirx/vast

Thank you and sorry for the inconvenience."
 exit 1
fi

# Clean the source tree to save space
make clean
make distclean  

cd $VAST_DIR

# Test if executable files were actually created?
COMPILATION_ERROR=0
echo -n "Checking library files:   "
for TEST_FILE in $TARGET_DIR/lib/libgsl.a $TARGET_DIR/lib/libgslcblas.a lib/include/gsl/gsl_blas.h lib/include/gsl/gsl_errno.h lib/include/gsl/gsl_fit.h lib/include/gsl/gsl_linalg.h lib/include/gsl/gsl_multifit.h lib/include/gsl/gsl_multifit_nlin.h lib/include/gsl/gsl_randist.h lib/include/gsl/gsl_rng.h lib/include/gsl/gsl_roots.h lib/include/gsl/gsl_sort_double.h lib/include/gsl/gsl_sort_float.h lib/include/gsl/gsl_sort.h lib/include/gsl/gsl_spline.h lib/include/gsl/gsl_statistics_double.h lib/include/gsl/gsl_statistics_float.h lib/include/gsl/gsl_statistics.h lib/include/gsl/gsl_vector.h ;do
 echo -n "$TEST_FILE - "
 if [ ! -f $TEST_FILE ];then
  COMPILATION_ERROR=1
  echo -ne "\033[01;31mERROR\033[00m,   "
 else
  echo -ne "\033[01;32mOk\033[00m,   "
 fi
done
echo "done!"

if [ $COMPILATION_ERROR -eq 1 ];then
 echo -e "\033[01;31mCOMPILATION ERROR\033[00m"
 exit 1
fi 

echo -e "\033[01;34mFinished compiling GSL library\033[00m"
echo " "
