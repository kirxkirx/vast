#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=`readlink -f "$1" 2>/dev/null`
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=`greadlink -f "$1" 2>/dev/null`
   if [ $? -ne 0 ];then
    REALPATH=`realpath "$1" 2>/dev/null`
    if [ $? -ne 0 ];then
     REALPATH=`grealpath "$1" 2>/dev/null`
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")"
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD"
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

if [ -z "$VAST_PATH" ];then
 #VAST_PATH=`readlink -f $0`
 VAST_PATH=`vastrealpath $0`
 VAST_PATH=`dirname "$VAST_PATH"`
 VAST_PATH="${VAST_PATH/'util/'/}"
 VAST_PATH="${VAST_PATH/'lib/'/}"
 VAST_PATH="${VAST_PATH/'examples/'/}"
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH/examples/}"
 VAST_PATH="${VAST_PATH//'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi


SRC_FOLDER="$VAST_PATH"src
EXCLUDE_FOLDER=\(-path './cfitsio/*' -o -path './fitsverify/*' -o - path './gsl/*' -o -path './pgplot*' -o -path './sextractor-2.19.5/*' -o -path './sextractor-2.25.2_fix_disable_model_fitting/*' -o -path './wcstools-3.9.6/*' -o -path './astcheck/*'\)
FORMAT_FILES=`find "${SRC_FOLDER}" -type f "${EXCLUDE_FOLDER}" -prune -name "*.c" -o -name "*.h"

for FILE_TO_FORMAT in $FORMAT_FILES
do
  clang-format -i "$FILE_TO_FORMAT" -style="{IndentWidth : 1, ColumnLimit: 0, SpaceBeforeAssignmentOperators: false, SpacesInParentheses: true, SortIncludes: false}"
done

