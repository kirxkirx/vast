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

# Do nothing if there is a system-wide installation of SExtractor
command -v sex &>/dev/null
if [ $? -eq 0 ];then
 echo "Found a system-wide installation of SExtractor, will do nothing"
 exit
fi


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
  ./autogen.sh
  if [ $? -ne 0 ];then
   echo "ERROR running autogen.sh"
   continue
  fi
 fi
 # --disable-model-fitting configure option turns-off model-fitting
 # features and allows compiling SExtractor without the ATLAS and FFTW libraries.
 ./configure --disable-model-fitting --prefix=$TARGET_DIR CFLAGS="$CFLAGS"
 if [ $? -ne 0 ];then
  echo "VaST installation problem: an error occurred while configuring SExtractor
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru>. 
Thank you and sorry for the inconvenience."
  #exit 1
  continue
 fi
 make -j9
 if [ $? -ne 0 ];then
  echo "VaST installation problem: an error occurred while compiling SExtractor
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru>. 
Thank you and sorry for the inconvenience."
  #exit 1
  continue
 fi
 make install
 if [ $? -ne 0 ];then
  echo "VaST installation problem: an error occurred while installing SExtractor
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
  echo -ne "\033[01;32mOk\033[00m,   "
 fi
done

if [ $COMPILATION_ERROR -eq 1 ];then
 echo -e "\033[01;31mCOMPILATION ERROR\033[00m"
 exit 1
fi 

echo "done!"


echo -e "\033[01;34mFinished compiling SExtractor\033[00m"
echo " "
