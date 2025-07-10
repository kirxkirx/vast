#!/usr/bin/env bash
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
LIBRARY_SOURCE=$VAST_DIR/src/cdsclient

echo " "
echo -e "Starting script \033[01;32m$0 $1\033[00m"

cd "$TARGET_DIR" || exit 1

if [ "$1" = "clean" ];then
 echo -e "\033[01;34mRemoving vizquery\033[00m"
 cd $LIBRARY_SOURCE
 make clean
 echo "Script $0 is done."
 echo " "
 exit
fi


ln -s my_vizquery.sh vizquery


# Test if executable files were actually created?
COMPILATION_ERROR=0
echo -n "Checking library files:   "
for TEST_FILE in $TARGET_DIR/vizquery ;do
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

echo -e "\033[01;34mFinished compiling cdsclient library\033[00m"
echo " "
