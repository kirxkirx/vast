#!/usr/bin/env bash
#
# This script will compile The GNU Scientific Library (GSL) inside the VaST source tree.
#

# For compatibility with BSD Make:
# if the script is called by GNU Make MFLAGS="-w" will be set that confuses BSD Make.
export MAKEFLAGS=""
export MFLAGS=""
#

VAST_DIR=$PWD
TARGET_DIR=$VAST_DIR/lib
LIBRARY_SOURCE=$VAST_DIR/src/sextractor-2.19.5

#
PATH_TO_THIS_SCRIPT=`readlink -f $0`
PATH_TO_LIB_DIR=`dirname $PATH_TO_THIS_SCRIPT`
#PATH_TO_VAST_DIR=`dirname $PATH_TO_LIB_DIR`
#
MARCH=`"$PATH_TO_LIB_DIR"/set_good_march.sh`
CFLAGS="-O2 -Wno-error $MARCH"
#

echo " "
echo -e "Starting script \033[01;32m$0 $1\033[00m"


if [ "$1" = "clean" ];then
 echo -e "\033[01;34mRemoving the local copy of SExtractor\033[00m"
 cd $LIBRARY_SOURCE
 make clean
 rm -f $TARGET_DIR/bin/sex
 echo "Script $0 is done."
 echo " "
 exit
fi

echo -e "\033[01;34mCompiling the local copy of SExtractor\033[00m"
echo "Using C compiler: $C_COMPILER"

cd $LIBRARY_SOURCE
make clean
# --disable-model-fitting configure option turns-off model-fitting
# features and allows compiling SExtractor without the ATLAS and FFTW libraries.
./configure --disable-model-fitting --prefix=$TARGET_DIR CFLAGS="$CFLAGS"
if [ ! $? ];then
 echo "VaST installation problem: an error occurred while configuring SExtractor
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru>. 
Thank you and sorry for the inconvenience."
 exit 1
fi
make -j9
if [ ! $? ];then
 echo "VaST installation problem: an error occurred while compiling SExtractor
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru>. 
Thank you and sorry for the inconvenience."
 exit 1
fi
make install
if [ ! $? ];then
 echo "VaST installation problem: an error occurred while installing SExtractor
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru>. 
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
for TEST_FILE in $TARGET_DIR/bin/sex ;do
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

echo -e "\033[01;34mFinished compiling SExtractor\033[00m"
echo " "
