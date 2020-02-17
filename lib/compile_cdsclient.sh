#!/usr/bin/env bash
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
LIBRARY_SOURCE=$VAST_DIR/src/cdsclient

echo " "
echo -e "Starting script \033[01;32m$0 $1\033[00m"


if [ "$1" = "clean" ];then
 echo -e "\033[01;34mRemoving the local copy of cdsclient\033[00m"
 cd $LIBRARY_SOURCE
 make clean
 echo "Script $0 is done."
 echo " "
 exit
fi


echo -e "\033[01;34mCompiling cdsclient library\033[00m"
echo "Using C compiler: $C_COMPILER" 


cd $LIBRARY_SOURCE
make clean
./configure --prefix=$TARGET_DIR
make
make install
make clean
cd $VAST_DIR

# Test if executable files were actually created?
COMPILATION_ERROR=0
echo -n "Checking library files:   "
#for TEST_FILE in $TARGET_DIR/bin/wwwget $TARGET_DIR/bin/vizquery ;do
for TEST_FILE in $TARGET_DIR/bin/vizquery ;do
 echo -n "$TEST_FILE - "
 if [ ! -f $TEST_FILE ];then
  COMPILATION_ERROR=1
  echo -ne "\033[01;31mERROR\033[00m,   "
 else
  echo -ne "\033[01;32mOK\033[00m,   "
 fi
done
echo "done!"

if [ $COMPILATION_ERROR -eq 1 ];then
 echo -e "\033[01;31mCOMPILATION ERROR\033[00m"
 exit 1
fi

cd lib/
ln -s bin/vizquery
cd -

echo -e "\033[01;34mFinished compiling cdsclient library\033[00m"
echo " "
