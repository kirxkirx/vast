#!/usr/bin/env bash
#
# This shell script is needed to correctly compile pgplot-related programs on stupid Ubuntu where,
# by some strange reason, pgplot-related programs segfault if compiled directly using make...
#
# This script is intended to be started automatically from the Makefile
#

# For compatibility with BSD Make:
# if the script is called by GNU Make MFLAGS="-w" will be set that confuses BSD Make.
export MAKEFLAGS=""
export MFLAGS=""
#

VAST_DIR=$PWD
TARGET_DIR=$VAST_DIR/lib
LIBRARY_SOURCE=$VAST_DIR/src/cfitsio
FITSVERIFY_SOURCE=$VAST_DIR/src/fitsverify

echo " "
echo -e "Starting script \033[01;32m$0 $1\033[00m"


if [ "$1" = "clean" ];then
 echo -e "\033[01;34mRemoving the local copy of CFITSIO library\033[00m"
 cd $LIBRARY_SOURCE
 make clean
 make distclean
 rm -f *.pdf *.ps
 #
 if [ -f $VAST_DIR/util/listhead ];then
  rm -f $VAST_DIR/util/listhead
 fi
 #
 if [ -f $VAST_DIR/util/modhead ];then
  rm -f $VAST_DIR/util/modhead
 fi
 #
 echo "Script $0 is done."
 echo " "
 exit
fi

C_COMPILER=`lib/find_gcc_compiler.sh`

echo -e "\033[01;34mCompiling CFITSIO library\033[00m"
echo "Using C compiler: $C_COMPILER" 

COMPILATION_ERROR=0

# Compile the library
cd $LIBRARY_SOURCE
make clean
./configure --prefix=$TARGET_DIR
if [ $? -ne 0 ];then
 COMPILATION_ERROR=1
fi
if [ $COMPILATION_ERROR -eq 0 ];then
 make -j9
fi
if [ $? -ne 0 ];then
 COMPILATION_ERROR=1
fi
if [ $COMPILATION_ERROR -eq 0 ];then
 make fitscopy
fi
if [ $COMPILATION_ERROR -eq 0 ];then
 cp -f fitscopy $VAST_DIR/util
 cp -f libcfitsio.a $TARGET_DIR/libcfitsio.a
 cp -f fitsio.h longnam.h $VAST_DIR/src
 make clean
fi
cd $VAST_DIR

# Compile FITSVERIFY - A FITS File Format-Verification Tool
if [ $COMPILATION_ERROR -eq 0 ];then
 cd $FITSVERIFY_SOURCE
 $C_COMPILER -o $TARGET_DIR/fitsverify ftverify.c fvrf_data.c fvrf_file.c fvrf_head.c fvrf_key.c fvrf_misc.c -DSTANDALONE -I$LIBRARY_SOURCE  -L$TARGET_DIR -lcfitsio -lm #-lnsl
 if [ $? -ne 0 ];then
  echo "ERROR compiling fitsverify" >> /dev/stderr
  COMPILATION_ERROR=1
 fi
 cd $VAST_DIR
fi

# Compile listhead
if [ $COMPILATION_ERROR -eq 0 ];then
 $C_COMPILER -o util/listhead src/listhead.c -L$TARGET_DIR -lcfitsio -lm
 if [ $? -ne 0 ];then
  echo "ERROR compiling listhead" >> /dev/stderr
  COMPILATION_ERROR=1
 fi
fi

# Compile modhead
if [ $COMPILATION_ERROR -eq 0 ];then
 $C_COMPILER -o util/modhead src/modhead.c -L$TARGET_DIR -lcfitsio -lm
 if [ $? -ne 0 ];then
  echo "ERROR compiling modhead" >> /dev/stderr
  COMPILATION_ERROR=1
 fi
fi

# Test if executable files were actually created?
if [ $COMPILATION_ERROR -eq 0 ];then
echo -n "Checking library files:   "
 for TEST_FILE in $TARGET_DIR/libcfitsio.a $TARGET_DIR/fitsverify util/listhead util/modhead ;do
  echo -n "$TEST_FILE - "
  if [ ! -f $TEST_FILE ];then
   COMPILATION_ERROR=1
   echo -ne "\033[01;31mERROR\033[00m,   "
  else
   echo -ne "\033[01;32mOk\033[00m,   "
  fi
 done
 echo "done!"
fi

if [ $COMPILATION_ERROR -eq 1 ];then
 echo -e "\033[01;31mCOMPILATION ERROR\033[00m"
 exit 1
fi

echo -e "\033[01;34mFinished compiling CFITSIO library\033[00m"
echo " "
