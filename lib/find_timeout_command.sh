#!/usr/bin/env bash
#
# This small script tries to find if we need timeout or gtimeout
#

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
   VAST_PATH=`readlink -f $0`
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

