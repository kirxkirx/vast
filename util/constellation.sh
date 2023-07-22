#!/usr/bin/env bash

function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=$(readlink -f "$1" 2>/dev/null)
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=$(greadlink -f "$1" 2>/dev/null)
   if [ $? -ne 0 ];then
    REALPATH=$(realpath "$1" 2>/dev/null)
    if [ $? -ne 0 ];then
     REALPATH=$(grealpath "$1" 2>/dev/null)
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")" || exit
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}


if [ -z "$2" ];then
 echo "Usage: $0 R.A.[J2000] Dec.[J2000]"
 exit 1
fi

if [ -z "$VAST_PATH" ];then
 #VAST_PATH=`readlink -f $0`
 VAST_PATH=$(vastrealpath $0)
 VAST_PATH=$(dirname "$VAST_PATH")
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")
 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
#


RA_DEC_B1875_DEG=$("$VAST_PATH"lib/bin/skycoor -d -q B1875.0 $1 $2 J2000 | awk '{print $1" "$2}')
RA_B1875_H=$(echo "$RA_DEC_B1875_DEG" | awk '{printf "%11.8f", $1/15}')
DEC_B1875_DEG=$(echo "$RA_DEC_B1875_DEG" | awk '{printf "%10.7f", $2}')

"$VAST_PATH"lib/ConstellationBoundaries "$RA_B1875_H" "$DEC_B1875_DEG"
