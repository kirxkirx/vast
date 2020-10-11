#!/usr/bin/env bash
#
# This small script tries to find if we need timeout or gtimeout
#

function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=`readlink -f "$1" 2>/dev/null`
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=`greadlink -f "$1" 2>/dev/null`
   if [ $? -ne 0 ];then
    # If not, resort to the black magic from
    # https://stackoverflow.com/questions/3572030/bash-script-absolute-path-with-os-x
    OURPWD=$PWD
    cd "$(dirname "$1")"
    LINK=$(readlink "$(basename "$1")")
    while [ "$LINK" ]; do
      cd "$(dirname "$LINK")"
      LINK=$(readlink "$(basename "$1")")
    done
    REALPATH="$PWD/$(basename "$1")"
    cd "$OURPWD"
   fi
  fi
  echo "$REALPATH"
}


# Find the GNU timeout executable: 'timeout' on Linux, 'gtimeout' on Mac 
command -v gtimeout &>/dev/null
if [ $? -eq 0 ];then
 echo gtimeout
else
 command -v timeout &>/dev/null
 if [ $? -eq 0 ];then
  echo timeout
 else
  # Last resort -- the included timeout script
  #
  if [ -z "$VAST_PATH" ];then
   #VAST_PATH=`readlink -f $0`
   VAST_PATH=`vastrealpath $0`
   VAST_PATH=`dirname "$VAST_PATH"`
   VAST_PATH="${VAST_PATH/'util/'/}"
   VAST_PATH="${VAST_PATH/'lib/'/}"
   VAST_PATH="${VAST_PATH/util/}"
   VAST_PATH="${VAST_PATH/lib/}"
   VAST_PATH="${VAST_PATH//'//'/'/'}"
   # In case the above line didn't work
   VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
  fi
  # Check that VAST_PATH ends with '/'
  LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
  if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
   VAST_PATH="$VAST_PATH/"
  fi
  #
  echo "$VAST_PATH"lib/timeout
 fi
fi

