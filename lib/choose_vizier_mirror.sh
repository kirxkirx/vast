#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

function is_ssh_or_vnc() {
  # Check environment variables for clues
  command -v env &>/dev/null
  if [ $? -eq 0 ];then
   # vnc
   env | grep --quiet VNCDESKTOP
   if [ $? -eq 0 ];then
    # Yes, we are over VNC
    return 0
   fi
   # ssh
   env | grep --quiet -e SSH_CLIENT -e SSH_CONNECTION
   if [ $? -eq 0 ];then
    # Yes, we are over ssh
    return 0
   fi
  fi
  ### ecursively search for sshd through the parent processes
  ### The /proc thing obviously works only on linux
  if [ -f /proc/$p/stat ];then
   p=${1:-$PPID}
   read pid name x ppid y < <( cat /proc/$p/stat )
   # or: read pid name ppid < <(ps -o pid= -o comm= -o ppid= -p $p) 
   [[ "$name" =~ sshd ]] && { return 0; }
   [ "$ppid" -le 1 ]    && { return 1; }
   is_ssh_or_vnc $ppid
  else
   # just assume the thing is running locally
   return 1
  fi # if [ -f /proc/$p/stat ];then
}

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
 VAST_PATH=`vastrealpath $0`
 VAST_PATH=`dirname "$VAST_PATH"`
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
#

for vizier_mirror in vizier.u-strasbg.fr vizier.cfa.harvard.edu vizier.hia.nrc.ca vizier.nao.ac.jp ;do
 # 1252-0378302 is the USNO-B1.0 number of the test star
 `"$VAST_PATH"lib/find_timeout_command.sh` 30 "$VAST_PATH"lib/vizquery -site=$vizier_mirror -mime=text -out.form=mini -source=USNO-B1 -out.add=_r -sort=_r -c="HD 226868" -c.rs=2 2>/dev/null | grep --quiet "1252-0378302"
 if [ $? -eq 0 ];then
  echo $vizier_mirror
  exit 0
 fi
done

# If we are still here - somthing is wrong
echo "ERROR in $0
No VizieR mirrors could be reached!" 1>&2

# Make sure we are not confusing the user with "check internet connection"
# message if the user is already connected remorely
if [ ! -z "$PPID" ];then
 is_ssh_or_vnc $PPID
 if [ $? -ne 0 ];then
  echo "Please check your internet connection." 1>&2
 fi
fi # if [ ! -z "$PPID" ];then

# Print the default mirror in a faint hope that the connection will restore itself
sleep 1
echo "vizier.u-strasbg.fr"

exit 1
