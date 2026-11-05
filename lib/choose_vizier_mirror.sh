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
   env | grep -q VNCDESKTOP
   if [ $? -eq 0 ];then
    # Yes, we are over VNC
    return 0
   fi
   # ssh
   env | grep -q -e SSH_CLIENT -e SSH_CONNECTION
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

# A more portable realpath wrapper
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
      cd "$(dirname "$1")" || exit 1
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit 1
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

# Function to remove the last occurrence of a directory from a path
remove_last_occurrence() {
    echo "$1" | awk -F/ -v dir=$2 '{
        found = 0;
        for (i=NF; i>0; i--) {
            if ($i == dir && found == 0) {
                found = 1;
                continue;
            }
            res = (i==NF ? $i : $i "/" res);
        }
        print res;
    }'
}

# Function to get full path to vast main directory from the script name
get_vast_path_ends_with_slash_from_this_script_name() {
 VAST_PATH=$(vastrealpath $0)
 VAST_PATH=$(dirname "$VAST_PATH")

 # Remove last occurrences of util, lib, examples
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "util")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "lib")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "examples")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "transients")

 # Make sure no '//' are left in the path (they look ugly)
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")

 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")

 # Check that VAST_PATH ends with '/'
 LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
 if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
  VAST_PATH="$VAST_PATH/"
 fi

 echo "$VAST_PATH"
}

if [ -z "$VAST_PATH" ];then
 VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
#

################# !!!!!!!!!!!!!!!!!! #################
#echo "vizier.cds.unistra.fr"
#exit 0
################# !!!!!!!!!!!!!!!!!! #################

# VizieR mirrors are incomplete: some catatlogs are available on some mirrors but not the others
# The user may specify which catalog to use for the test
CATALOG_TO_TEST="GAIADR2"
if [ -n "$1" ];then
 if [ "$1" = "APASS" ];then
  CATALOG_TO_TEST="APASS"
 fi
fi


# Shared, short-lived record of the probe result. The transient search runs this script
# once per field, the online identification once per candidate, and the plate solver
# before each remote UCAC5 or APASS query; when the mirrors are down every probe costs
# minutes (162 s on 2026-11-03). The record is kept next to the offline catalogs, which
# all VaST working copies of an unmw installation share, so the runs on one machine
# reuse a recent answer: a success for VIZIER_MIRROR_RECORD_OK_SEC (default 900 s), a
# failure only for VIZIER_MIRROR_RECORD_FAIL_SEC (default 300 s), so that a recovered
# service is noticed within minutes. VIZIER_MIRROR_RECORD=no skips the record and probes
# (the test suite's internet-connection check does that); the result is still recorded.
# VIZIER_MIRROR_RECORD_ONLY=yes never probes: it reports a recent recorded result, or prints
# the main CDS site and exits with code 2 when there is none (the transient search does that
# when its known-star check reads a local catalog and needs no VizieR mirror up front).
VIZIER_MIRROR_RECORD_FILE="${VAST_PATH}lib/catalogs/.vizier_mirror_probe_${CATALOG_TO_TEST}"
VIZIER_MIRROR_RECORD_OK_SEC="${VIZIER_MIRROR_RECORD_OK_SEC:-900}"
VIZIER_MIRROR_RECORD_FAIL_SEC="${VIZIER_MIRROR_RECORD_FAIL_SEC:-300}"
if [ "$VIZIER_MIRROR_RECORD" != "no" ] && [ -s "$VIZIER_MIRROR_RECORD_FILE" ];then
 read -r RECORD_UNIXSEC RECORD_EXIT_CODE RECORD_MIRROR < "$VIZIER_MIRROR_RECORD_FILE"
 if [[ "$RECORD_UNIXSEC" =~ ^[0-9]+$ ]] && [[ "$RECORD_EXIT_CODE" =~ ^[01]$ ]] && [ -n "$RECORD_MIRROR" ];then
  RECORD_AGE_SEC=$(( $(date +%s) - RECORD_UNIXSEC ))
  if [ "$RECORD_EXIT_CODE" -eq 0 ];then
   RECORD_MAX_AGE_SEC="$VIZIER_MIRROR_RECORD_OK_SEC"
  else
   RECORD_MAX_AGE_SEC="$VIZIER_MIRROR_RECORD_FAIL_SEC"
  fi
  # a record from the future (clock change) is not trusted
  if [ "$RECORD_AGE_SEC" -ge 0 ] && [ "$RECORD_AGE_SEC" -lt "$RECORD_MAX_AGE_SEC" ] 2>/dev/null ;then
   echo "$RECORD_MIRROR"
   exit "$RECORD_EXIT_CODE"
  fi
 fi
fi
if [ "$VIZIER_MIRROR_RECORD_ONLY" = "yes" ];then
 echo "vizier.cds.unistra.fr"
 exit 2
fi

# Write the record atomically; silently skip it where lib/catalogs is not writable
remember_probe_result() {
 local RECORD_TMP_FILE="${VIZIER_MIRROR_RECORD_FILE}.tmp$$"
 if [ -d "${VAST_PATH}lib/catalogs" ] && [ -w "${VAST_PATH}lib/catalogs" ];then
  if echo "$(date +%s) $1 $2" > "$RECORD_TMP_FILE" 2>/dev/null ;then
   mv -f "$RECORD_TMP_FILE" "$VIZIER_MIRROR_RECORD_FILE" 2>/dev/null || rm -f "$RECORD_TMP_FILE"
  fi
 fi
}

# New code: choose VizieR mirror that serves Gaia DR2
for vizier_mirror in vizier.cds.unistra.fr vizier.china-vo.org vizier.nao.ac.jp ;do
 if [ "$CATALOG_TO_TEST" = "APASS" ];then
  "${VAST_PATH}"lib/vizquery -site="$vizier_mirror" -mime=text -source=II/336/apass9 -out.max=1 -out.add=_1 -out.add=_r -out.form=mini -out=RAJ2000,DEJ2000,Bmag,e_Bmag,Vmag,e_Vmag,r\'mag,e_r\'mag,i\'mag,e_i\'mag,g\'mag,e_g\'mag Vmag=7.0..16.5 -sort=Vmag -c="23:24:47.70 +61:11:14.3" -c.rs=1.0 | grep ' 15.7' | grep ' 15.2' | grep -q ' 15.0'
  if [ $? -eq 0 ];then
   remember_probe_result 0 "$vizier_mirror"
   echo "$vizier_mirror"
   exit 0
  fi
 else
  "${VAST_PATH}"lib/vizquery -site="$vizier_mirror" -mime=text -source=I/345/gaia2 -out.max=3 -out.add=_r -out.form=mini -sort=Gmag Gmag=0.0..13.52 -c="18:02:32.82 -29:50:13.9" -c.rs=34.50 -out="Source,RA_ICRS,DE_ICRS,Gmag,RPmag,Var" | grep -q ' 4050254215686154112 '
  if [ $? -eq 0 ];then
   remember_probe_result 0 "$vizier_mirror"
   echo "$vizier_mirror"
   exit 0
  fi
 fi # catalog
done
# If no mirror passed the catalog-specific test, fall back to the primary mirror
remember_probe_result 1 "vizier.cds.unistra.fr"
echo "vizier.cds.unistra.fr"
exit 1


# The old code that returned the first responsive VizieR mirror
##for vizier_mirror in vizier.u-strasbg.fr vizier.cfa.harvard.edu vizier.hia.nrc.ca vizier.nao.ac.jp ;do
#for vizier_mirror in vizier.u-strasbg.fr vizier.cfa.harvard.edu vizier.nao.ac.jp ;do
# # 1252-0378302 is the USNO-B1.0 number of the test star
# `"$VAST_PATH"lib/find_timeout_command.sh` 30 "$VAST_PATH"lib/vizquery -site=$vizier_mirror -mime=text -out.form=mini -source=USNO-B1 -out.add=_r -sort=_r -c="HD 226868" -c.rs=2 2>/dev/null | grep -q "1252-0378302"
# if [ $? -eq 0 ];then
#  echo $vizier_mirror
#  exit 0
# fi
#done

# The new code that should return the fastest VizieR mirror
fastest_vizier_mirror=''
fastest_time=30000000000

temp_file=choose_vizier_mirror$$.tmp
if [ -f $temp_file ];then
 rm -f $temp_file
fi

#for vizier_mirror in vizier.u-strasbg.fr vizier.cfa.harvard.edu vizier.nao.ac.jp ;do
for vizier_mirror in vizier.u-strasbg.fr vizier.cfa.harvard.edu ;do
 (
  # We are limited to 1sec accuracy if %N is not supported
  #start_time=$(date +%s%N)
  start_time=$(date +%s)
  $("$VAST_PATH"lib/find_timeout_command.sh) 30 "$VAST_PATH"lib/vizquery -site=$vizier_mirror -mime=text -out.form=mini -source=USNO-B1 -out.add=_r -sort=_r -c="HD 226868" -c.rs=2 2>/dev/null | grep -q "1252-0378302"
  if [ $? -eq 0 ];then
   #end_time=$(date +%s%N)
   end_time=$(date +%s)
   elapsed_time=$((end_time - start_time))
   echo $elapsed_time $vizier_mirror >> $temp_file
  fi
 ) &
done

# wait for all background jobs to finish
wait

# find the fastest server
if [ -s "$temp_file" ]; then
 fastest_vizier_mirror=$(sort -n -k1 $temp_file | head -n1 | awk '{print $2}')
else
 echo "No server responded"
fi

# clean up
rm $temp_file

# print the fastest server
if [ -n "$fastest_vizier_mirror" ]; then
 echo $fastest_vizier_mirror
 exit 0
fi

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
