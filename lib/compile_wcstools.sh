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
LIBRARY_SOURCE=$VAST_DIR/src/wcstools-3.9.5

#
PATH_TO_THIS_SCRIPT=`readlink -f $0`
PATH_TO_LIB_DIR=`dirname $PATH_TO_THIS_SCRIPT`
#

echo " "
echo -e "Starting script \033[01;32m$0 $1\033[00m"


echo -e "\033[01;34mCompiling the local copy of WCSTools\033[00m"
echo "Using C compiler: $C_COMPILER"

cd $LIBRARY_SOURCE
make clean
make -j9
if [ ! $? ];then
 echo "VaST installation problem: an error occurred while compiling WCSTools
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru>. 
Thank you and sorry for the inconvenience."
 exit 1
fi

#
cp bin/* "$TARGET_DIR"/bin/

# Clean the source tree to save space
make clean

cd $VAST_DIR

# Test if executable files were actually created?
COMPILATION_ERROR=0
echo -n "Checking library files:   "
for TEST_FILE in $TARGET_DIR/bin/xy2sky ;do
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

echo -e "\033[01;34mFinished compiling WCSTools\033[00m"
echo " "
