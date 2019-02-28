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
LIBRARY_SOURCE=$VAST_DIR/src/astcheck

echo " "
echo -e "Starting script \033[01;32m$0 $1\033[00m"


if [ "$1" = "clean" ];then
# echo " "
# echo -e "Starting script \033[01;32m$0\033[00m"
 echo -e "\033[01;34mRemoving the local copy of ASTCHECK\033[00m"
 cd $LIBRARY_SOURCE
 rm -f *.a  *.o astcheck astephem get_test jd riseset3
 echo "Script $0 is done."
 echo " "
 exit
fi

SYSTEM_TYPE=`uname`
if [ "$SYSTEM_TYPE" = "Linux" ];then
 MAKE_COMMAND="make"
else
 command -v gmake &>/dev/null
 if [ $? -eq 0 ];then
  MAKE_COMMAND="gmake"
 else
  echo "ERROR: cannot find 'gmake' while being on a nin-Linux system ($SYSTEM_TYPE)!
The VaST compilation may fail. If it does, please install 'gmake' and try again."
  MAKE_COMMAND="make"
 fi
fi

echo -e "\033[01;34mCompiling ASTCHECK\033[00m"
echo "Using $MAKE_COMMAND to compile ASTCHECK..." 


cd $LIBRARY_SOURCE
$MAKE_COMMAND -f linlunar.mak
cp astcheck $VAST_DIR/lib
rm -f *.a  *.o astcheck astephem get_test jd riseset3
cd $VAST_DIR

# Test if executable files were actually created?
COMPILATION_ERROR=0
echo -n "Checking executable files:   "
for TEST_FILE in $TARGET_DIR/astcheck ;do
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

echo -e "\033[01;34mFinished compiling ASTCHECK\033[00m"
echo " "
