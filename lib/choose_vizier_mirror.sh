#!/usr/bin/env bash

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

#for vizier_mirror in vizier.u-strasbg.fr vizier.cfa.harvard.edu vizier.hia.nrc.ca vizier.nao.ac.jp data.bao.ac.cn vizier.ast.cam.ac.uk www.ukirt.jach.hawaii.edu vizier.inasan.ru ;do
for vizier_mirror in vizier.u-strasbg.fr vizier.cfa.harvard.edu vizier.hia.nrc.ca vizier.nao.ac.jp ;do
 # 1252-0378302 is the USNO-B1.0 number of the test star
 `"$VAST_PATH"lib/find_timeout_command.sh` 30 "$VAST_PATH"lib/vizquery -site=$vizier_mirror -mime=text -out.form=mini -source=USNO-B1 -out.add=_r -sort=_r -c="HD 226868" -c.rs=2 2>/dev/null | grep --quiet "1252-0378302"
 if [ $? -eq 0 ];then
  echo $vizier_mirror
  exit 0
  #break
 fi
done

# If we are still here - somthing is wrong
echo "ERROR in $0
No VizieR mirrors could be reached!
Please check your internet connection." >> /dev/stderr

# Print the default mirror in a faint hope that the internet connection will restore
sleep 1
echo "vizier.u-strasbg.fr"

exit 1
