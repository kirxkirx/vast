#!/usr/bin/env bash
#
# This shell script compiles a static copy of zlib library
#
# This script is intended to be started automatically from the Makefile
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
ZLIB_SOURCE=$VAST_DIR/src/zlib-1.3.1

echo " "
echo -e "Starting script \033[01;32m$0 $1\033[00m"

if [ "$1" = "clean" ];then
 echo -e "\033[01;34mRemoving the local copy of zlib library\033[00m"
 if [ -d $ZLIB_SOURCE ];then
  cd $ZLIB_SOURCE || exit 1
  make clean 2>/dev/null || true
  make distclean 2>/dev/null || true
  cd $VAST_DIR || exit 1
 fi
 if [ -f $TARGET_DIR/libz.a ];then
  rm -f $TARGET_DIR/libz.a
 fi
 echo "Script $0 is done."
 echo " "
 exit
fi

C_COMPILER=$(lib/find_gcc_compiler.sh)

echo -e "\033[01;34mCompiling zlib library\033[00m"
echo "Using C compiler: $C_COMPILER" 

COMPILATION_ERROR=0

# Try to compile zlib if source directory exists
if [ -d $ZLIB_SOURCE ];then
 echo "Found zlib source at: $ZLIB_SOURCE"
 cd $ZLIB_SOURCE || exit 1
 
 # Clean any previous builds
 make clean 2>/dev/null || true
 make distclean 2>/dev/null || true
 
 # Configure for static library
 CC=$C_COMPILER ./configure --static --prefix="$TARGET_DIR"
 if [ $? -ne 0 ];then
  echo "WARNING: zlib configure failed, will rely on system zlib"
  cd $VAST_DIR || exit 1
 else
  # Try to compile
  make -j9
  if [ $? -ne 0 ];then
   echo "WARNING: zlib compilation failed, will rely on system zlib"
   cd $VAST_DIR || exit 1
  else
   # Check if static library was created
   if [ -f libz.a ];then
    # Copy static library to target directory
    cp -v libz.a "$TARGET_DIR/"
    if [ $? -eq 0 ];then
     echo "Successfully compiled and installed local zlib"
    else
     echo "WARNING: Failed to copy libz.a to $TARGET_DIR"
    fi
   else
    echo "WARNING: libz.a was not created"
   fi
   # Clean up build files but keep the source
   make clean 2>/dev/null || true
   cd $VAST_DIR || exit 1
  fi
 fi
else
 echo "INFO: zlib source not found at $ZLIB_SOURCE, will use system zlib"
fi

echo -e "\033[01;34mTesting zlib functionality\033[00m"

# Test zlib using our test script
ZLIB_TEST_RESULT=$(lib/check_zlib.sh 2>/dev/null)
ZLIB_EXIT_CODE=$?

if [ $ZLIB_EXIT_CODE -eq 0 ];then
 echo "SUCCESS: Zlib test passed with: $ZLIB_TEST_RESULT"
 echo -e "\033[01;34mFinished compiling zlib library\033[00m"
 echo " "
 exit 0
else
 echo -e "\033[01;31mERROR: Zlib test failed!\033[00m"
 echo "Neither local zlib compilation nor system zlib are working."
 echo "Please install zlib development packages (e.g., zlib-dev, zlib-devel) or"
 echo "ensure zlib source is available at: $ZLIB_SOURCE"
 echo " "
 exit 1
fi
