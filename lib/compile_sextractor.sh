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
#LIBRARY_SOURCE=$VAST_DIR/src/sextractor-2.19.5
#LIBRARY_SOURCE=$VAST_DIR/src/sextractor-2.25.0_fix_disable_model_fitting
LIBRARY_SOURCES="$VAST_DIR/src/sextractor-2.25.0_fix_disable_model_fitting $VAST_DIR/src/sextractor-2.19.5"

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

# If we are asked to clean the source
if [ "$1" = "clean" ];then
 echo -e "\033[01;34mRemoving the local copy of SExtractor\033[00m"
 for LIBRARY_SOURCE in $LIBRARY_SOURCES ;do
  cd $LIBRARY_SOURCE
  make clean
 done
 if [ -f $TARGET_DIR/bin/sex ];then
  rm -f $TARGET_DIR/bin/sex
 fi
 echo "Script $0 is done."
 echo " "
 exit
fi

# Do nothing if there is a system-wide installation of SExtractor
command -v sex &>/dev/null
if [ $? -eq 0 ];then
 echo "Found a system-wide installation of SExtractor, will do nothing"
 exit
fi

# If there is a system-wide installation of SExtractor with the executable called by other names
for POSSIBLE_SEXTRACTOR_NAME in source-extractor sourceextractor sextractor ;do
 command -v $POSSIBLE_SEXTRACTOR_NAME &>/dev/null
 if [ $? -eq 0 ];then
  cd $TARGET_DIR/bin/
  ln -s `command -v $POSSIBLE_SEXTRACTOR_NAME`
  echo "Found a system-wide installation of SExtractor ($POSSIBLE_SEXTRACTOR_NAME), will link it"
  exit
 fi
done


echo -e "\033[01;34mCompiling the local copy of SExtractor\033[00m"
echo "Using C compiler: $C_COMPILER"

# We maintain two versions of SExtractor
for LIBRARY_SOURCE in $LIBRARY_SOURCES ;do
 echo "######### Compiling $LIBRARY_SOURCE #########"
 sleep 2
 cd $LIBRARY_SOURCE
 make clean
 make distclean
 # for sextractor-2.25.0
 if [ -x ./autogen.sh ];then
  command -v autoconf &>/dev/null
  if [ $? -eq 0 ];then
   ./autogen.sh
   if [ $? -ne 0 ];then
    echo "ERROR running autogen.sh"
    continue
   fi # if [ $? -ne 0 ];then
  else
   echo "ERROR no autoconf"
   continue
  fi # if [ $? -eq 0 ];then
 fi # if [ -x ./autogen.sh ];then
 # --disable-model-fitting configure option turns-off model-fitting
 # features and allows compiling SExtractor without the ATLAS and FFTW libraries.
 ./configure --disable-model-fitting --prefix=$TARGET_DIR CFLAGS="$CFLAGS"
 if [ $? -ne 0 ];then
  echo "
########### VaST installation problem ###########
Failed command:
./configure --disable-model-fitting --prefix=$TARGET_DIR CFLAGS="$CFLAGS"
at
$LIBRARY_SOURCE
C compiler: $C_COMPILER

VaST installation problem: an error occurred while configuring SExtractor
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru>. 
Thank you and sorry for the inconvenience."
  #exit 1
  continue
 fi
 make -j9
 if [ $? -ne 0 ];then
  echo "
########### VaST installation problem ###########
Failed command:
make -j9
at
$LIBRARY_SOURCE
C compiler: $C_COMPILER

VaST installation problem: an error occurred while compiling SExtractor
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru>. 
Thank you and sorry for the inconvenience."
  #exit 1
  continue
 fi
 make install
 if [ $? -ne 0 ];then
  echo "
########### VaST installation problem ###########
Failed command:
make install
at
$LIBRARY_SOURCE
C compiler: $C_COMPILER

VaST installation problem: an error occurred while installing SExtractor
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru>. 
Thank you and sorry for the inconvenience."
  #exit 1
  continue
 fi

 # Clean the source tree to save space
 make clean
 make distclean  

 cd $VAST_DIR

 # if we are here - assume the current SExtractor version compiled alright
 break

done # for LIBRARY_SOURCE in $LIBRARY_SOURCES ;do

# Test if executable files were actually created?
COMPILATION_ERROR=0
echo -n "Checking library files:   "
for TEST_FILE in $TARGET_DIR/bin/sex ;do
 echo -n "$TEST_FILE - "
 if [ ! -f $TEST_FILE ];then
  COMPILATION_ERROR=1
  echo -ne "\033[01;31mERROR\033[00m,   "
 else
  echo -ne "\033[01;32mOK\033[00m,   "
 fi
done

if [ $COMPILATION_ERROR -eq 1 ];then
 echo -e "\033[01;31mCOMPILATION ERROR\033[00m"
 exit 1
fi 

echo "done!"


echo -e "\033[01;34mFinished compiling SExtractor\033[00m"
echo " "
