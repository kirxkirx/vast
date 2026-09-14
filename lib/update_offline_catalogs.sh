#!/usr/bin/env bash

# This script will update the copies of VSX and ASASSN-V catalogs for offline use

# Max total time for catalog download
# Assume the connection is fast enough for the catalog to be downlaoded in less than
CATALOG_DOWNLOAD_TIMEOUT_SEC=3600

# Temporary-failure tolerance: how many times to (re)start each download
# command and how long to wait between the attempts. The curl commands use
# '--continue-at -', so every retry RESUMES the partial file left by the
# previous attempt instead of starting from zero - on an unstable connection
# a large transfer (astorb.dat.gz is >100 MB) then completes incrementally
# across the attempts even when no single attempt can pull the whole file.
# Both values are env-overridable for hosts with especially flaky links.
: "${CATALOG_DOWNLOAD_ATTEMPTS:=3}"
: "${CATALOG_DOWNLOAD_RETRY_DELAY_SEC:=60}"

# Run a download command up to CATALOG_DOWNLOAD_ATTEMPTS times, resuming the
# partial output file between the attempts. For .gz targets the completed
# file must also pass a gzip integrity test: a resumed download stitched
# from two different versions of the remote file (the mirror may have
# regenerated it between attempts or between script runs) produces a corrupt
# archive, which is discarded so the next attempt starts from scratch.
# $1 - the full download command
# $2 - the output file that command writes
# Size of a file in bytes, GNU stat then BSD stat; empty if neither works.
get_file_size_in_bytes() {
 FILE_SIZE_IN_BYTES=`stat -c '%s' "$1" 2>/dev/null`
 if [ -z "$FILE_SIZE_IN_BYTES" ];then
  FILE_SIZE_IN_BYTES=`stat -f '%z' "$1" 2>/dev/null`
 fi
 echo "$FILE_SIZE_IN_BYTES"
}

# The size a remote file advertises, or empty when the server sends no
# Content-Length (the live ASAS-SN endpoint streams the CSV without one).
get_remote_content_length() {
 curl $VAST_CURL_PROXY --connect-timeout 10 --max-time 60 --insecure --silent --head --location "$1" 2>/dev/null | grep -i '^content-length:' | tail -n1 | awk '{print $2}' | tr -d '\r\n'
}

# The smallest size we are ever willing to accept for a catalog, in bytes.
# This is the ONLY check that catches a well-formed but drastically incomplete
# catalog on a FRESH install, where there is no previous local file for the
# shrink check below to compare against. That is not hypothetical: in Sep 2026
# the kirx.net mirror served an asassnv.csv of 643888 bytes - a perfectly valid
# CSV with the right header, 79 fields per line and a complete final line, but
# only 1000 of the ~687000 records, i.e. one unpaginated page from the ASAS-SN
# web endpoint. Hosts that already had a good catalog were saved by the shrink
# check; ariel, which did not, installed the stub and its variable-star
# identification silently degraded.
# The floors are deliberately FAR below the real sizes (asassnv.csv ~443 MB,
# vsx.dat ~370 MB, astorb.dat ~110 MB, ObsCodes.html ~145 kB) so that a genuine
# new release can shrink a lot without tripping them.
get_catalog_minimum_expected_size_in_bytes() {
 case "$1" in
  *asassnv.csv)
   echo 100000000
   ;;
  *vsx.dat)
   echo 100000000
   ;;
  *astorb.dat)
   echo 30000000
   ;;
  *ObsCodes.html)
   echo 50000
   ;;
  *)
   echo 0
   ;;
 esac
}

# Structural check for a downloaded catalog: does the file end where a complete
# file is supposed to end? Catches a download cut off in the middle of a record.
# It does NOT catch a cut at a record boundary - that is what the size checks are
# for.
#
# There is no single rule that works for all four catalogs, because they have
# nothing in common beyond being text. Each one gets the test that matches what
# is actually invariant about it:
#
#  astorb.dat, vsx.dat  fixed-width records - every line is exactly the same
#                       length (267 and 205 characters), so a short final line
#                       means a cut mid-record. Their whitespace FIELD count is
#                       not constant, because object names hold a variable
#                       number of words ("1 Ceres" against "6331 P-L"), so
#                       counting fields would reject perfectly good files.
#  asassnv.csv          variable-length records, but exactly 79 comma-separated
#                       fields on every line.
#  ObsCodes.html        an HTML page, not a record file: the codes live inside
#                       <pre>...</pre> and the observatory name is an unpadded
#                       last column, so neither the line length nor the field
#                       count is constant. The only reliable end-of-file marker
#                       is the closing tag. Counting fields here rejected every
#                       single download - the last line "</pre>" has one field
#                       and the line above it has four - which broke catalog
#                       installation on every machine without a local copy.
#
# A format this function does not know gets no structural check at all: a check
# that misunderstands the format is worse than no check, because it refuses good
# data forever rather than only on a bad day.
#
# $1 is the file to inspect (usually the freshly downloaded temporary copy);
# $2 is the name of the catalog it will become, which selects the test.
verify_catalog_structure() {
 VERIFY_CATALOG_FILE="$1"
 VERIFY_CATALOG_NAME="$2"
 if [ -z "$VERIFY_CATALOG_NAME" ];then
  VERIFY_CATALOG_NAME="$1"
 fi
 if [ ! -s "$VERIFY_CATALOG_FILE" ];then
  return 1
 fi
 # A file not ending in a newline was cut mid-record. True of every format here,
 # the HTML page included.
 if [ -n "`tail -c 1 \"$VERIFY_CATALOG_FILE\" 2>/dev/null`" ];then
  echo "WARNING: $VERIFY_CATALOG_FILE does not end with a newline - it looks cut off in the middle of a record" >&2
  return 1
 fi
 case "$VERIFY_CATALOG_NAME" in
  *ObsCodes.html*)
   # tr -d '\r' so a CRLF-served copy is not mistaken for a truncated one.
   VERIFY_CATALOG_LAST_LINE=`awk 'NF>0 {last_line=$0} END {print last_line}' "$VERIFY_CATALOG_FILE" 2>/dev/null | tr -d '\r'`
   if [ "$VERIFY_CATALOG_LAST_LINE" != "</pre>" ];then
    echo "WARNING: $VERIFY_CATALOG_FILE does not end with the </pre> tag that closes the MPC observatory-code list (its last non-empty line is '$VERIFY_CATALOG_LAST_LINE') - it looks incomplete" >&2
    return 1
   fi
   ;;
  *.csv)
   # Files with fewer than two lines are skipped.
   if ! tail -n 2 "$VERIFY_CATALOG_FILE" 2>/dev/null | awk -F',' 'NR==1{first=NF} NR==2{second=NF} END{if (NR<2) exit 0; exit !(first==second)}' ;then
    echo "WARNING: the last line of $VERIFY_CATALOG_FILE has a different number of comma-separated fields than the line before it - it looks cut off in the middle of a record" >&2
    return 1
   fi
   ;;
  *astorb*|*vsx.dat*)
   if ! tail -n 2 "$VERIFY_CATALOG_FILE" 2>/dev/null | awk 'NR==1{first=length($0)} NR==2{second=length($0)} END{if (NR<2) exit 0; exit !(first==second)}' ;then
    echo "WARNING: the last line of $VERIFY_CATALOG_FILE is not the same length as the line before it - this is a fixed-width catalog, so it looks cut off in the middle of a record" >&2
    return 1
   fi
   ;;
  *)
   # Unknown format: no structural check rather than a wrong one.
   ;;
 esac
 return 0
}

# One catalog that cannot be updated must not stop the other three from being
# updated. ObsCodes.html is first in the update loop, so before this any failure
# on it - an MPC outage, a mirror hiccup, a bug in one of the checks above -
# also blocked astorb.dat, vsx.dat and asassnv.csv, which is how a single wrong
# structural test could leave a machine with no catalogs at all.
#
# The severity depends on what is already on disk. Failing to REFRESH a catalog
# we already hold is a warning; failing to OBTAIN one we do not hold is an
# error that the exit code must report, but even then the remaining catalogs are
# still attempted first. Call it and then `continue` to the next catalog.
CATALOG_UPDATE_HARD_FAILURE=0
note_catalog_update_failure() {
 NOTE_CATALOG_NAME="$1"
 if [ "$CATALOG_IS_OPTIONAL" -eq 1 ] 2>/dev/null ;then
  echo "ERROR: the optional catalog $NOTE_CATALOG_NAME could not be updated - continuing without updating it" >&2
  return 0
 fi
 if [ -s "$NOTE_CATALOG_NAME" ];then
  # Only an installed copy that is plausibly complete is worth keeping: a stub
  # left in place would degrade every run from now on, exactly as the 1000-record
  # asassnv.csv did on ariel.
  NOTE_INSTALLED_SIZE_BYTES=`get_file_size_in_bytes "$NOTE_CATALOG_NAME"`
  NOTE_MINIMUM_SIZE_BYTES=`get_catalog_minimum_expected_size_in_bytes "$NOTE_CATALOG_NAME"`
  if [ -z "$NOTE_INSTALLED_SIZE_BYTES" ] || [ "$NOTE_MINIMUM_SIZE_BYTES" -le 0 ] 2>/dev/null || [ "$NOTE_INSTALLED_SIZE_BYTES" -ge "$NOTE_MINIMUM_SIZE_BYTES" ] 2>/dev/null ;then
   echo "WARNING: $NOTE_CATALOG_NAME could not be updated - keeping the copy that is already installed and carrying on with the other catalogs" >&2
   return 0
  fi
  echo "ERROR: $NOTE_CATALOG_NAME could not be updated and the copy on disk is too small to be usable" >&2
 else
  echo "ERROR: $NOTE_CATALOG_NAME could not be updated and there is no copy installed" >&2
 fi
 CATALOG_UPDATE_HARD_FAILURE=1
 return 0
}

attempt_download_with_resume() {
 DOWNLOAD_ATTEMPT_COUNTER=1
 while true ;do
  $1
  DOWNLOAD_EXIT_CODE=$?
  if [ $DOWNLOAD_EXIT_CODE -eq 0 ];then
   case "$2" in
    *.gz)
     if gzip -t "$2" 2>/dev/null ;then
      return 0
     fi
     echo "WARNING: $2 fails the gzip integrity test - discarding it, the next attempt will re-download from scratch" >&2
     rm -f "$2"
     ;;
    *)
     return 0
     ;;
   esac
  else
   echo "WARNING: download attempt $DOWNLOAD_ATTEMPT_COUNTER of $CATALOG_DOWNLOAD_ATTEMPTS failed with curl exit code $DOWNLOAD_EXIT_CODE" >&2
  fi
  if [ "$DOWNLOAD_ATTEMPT_COUNTER" -ge "$CATALOG_DOWNLOAD_ATTEMPTS" ];then
   return 1
  fi
  DOWNLOAD_ATTEMPT_COUNTER=$((DOWNLOAD_ATTEMPT_COUNTER+1))
  echo "Waiting $CATALOG_DOWNLOAD_RETRY_DELAY_SEC seconds before download attempt $DOWNLOAD_ATTEMPT_COUNTER (a partial file, if any, will be resumed)" >&2
  sleep "$CATALOG_DOWNLOAD_RETRY_DELAY_SEC"
 done
}

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

#################################
# Determine the VaST root directory from this script's own location and cd into
# it, so the script works regardless of the directory it is launched from (e.g.
# an /etc/crontab entry that calls it by absolute path without cd-ing first).
# Everything below refers to the catalog files by paths relative to the VaST root.

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
function remove_last_occurrence() {
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
function get_vast_path_ends_with_slash_from_this_script_name() {
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

VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
cd "$VAST_PATH" || { echo "ERROR: update_offline_catalogs.sh cannot cd to the VaST directory '$VAST_PATH'" >&2; exit 1; }
#################################

if [ ! -x lib/catalogs/create_tycho2_list_of_bright_stars_to_exclude_from_transient_search ];then
 echo "Error: Could not find lib/catalogs/create_tycho2_list_of_bright_stars_to_exclude_from_transient_search" >&2
 echo "You need to compile VaST by running 'make' before running the script $0" >&2
 exit 1
fi

# Function to download the Tycho-2 dataset files.
# The Tycho-2 file set is fixed (a frozen catalog), so no directory listing
# is needed - the file names are hardcoded and tried against a chain of
# mirrors. A file that is already present and passes the gzip integrity
# test is never re-downloaded, so an interrupted run resumes where it
# stopped, possibly from the next mirror ('--continue-at -' extends partial
# files; a resume stitched across two different gzip copies of the same
# file fails the integrity test, is discarded and re-downloaded clean).
get_tycho2_from_scan_with_curl() {
    local mirror_base_url
    local item
    local n_missing
    local max_retries=5
    local retry_delay=2
    local tycho2_gz_files="tyc2.dat.00.gz tyc2.dat.01.gz tyc2.dat.02.gz tyc2.dat.03.gz tyc2.dat.04.gz tyc2.dat.05.gz tyc2.dat.06.gz tyc2.dat.07.gz tyc2.dat.08.gz tyc2.dat.09.gz tyc2.dat.10.gz tyc2.dat.11.gz tyc2.dat.12.gz tyc2.dat.13.gz tyc2.dat.14.gz tyc2.dat.15.gz tyc2.dat.16.gz tyc2.dat.17.gz tyc2.dat.18.gz tyc2.dat.19.gz"

    # cdsarc.u-strasbg.fr redirects (HTTP 301) to cdsarc.cds.unistra.fr,
    # so the latter is used directly as the authoritative upstream fallback.
    for mirror_base_url in "http://scan.sai.msu.ru/~kirx/data/tycho2/" "http://tau.kirx.net/vast_test_data/tycho2/" "https://cdsarc.cds.unistra.fr/ftp/I/259/" ; do
        echo "Trying Tycho-2 mirror $mirror_base_url" >&2
        # ReadMe is kept for provenance, but its absence is not fatal
        if [ ! -s ReadMe ]; then
            curl --silent --max-time 60 $VAST_CURL_PROXY --insecure -o ReadMe "${mirror_base_url}ReadMe" 2>/dev/null
        fi
        n_missing=0
        for item in $tycho2_gz_files ; do
            # keep a complete, integrity-checked file from a previous mirror or run
            if [ -s "$item" ] && gzip -t "$item" 2>/dev/null ; then
                continue
            fi
            echo "Downloading: $item" >&2
            curl --silent --show-error --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC \
                $VAST_CURL_PROXY --insecure --continue-at - --retry $max_retries --retry-delay $retry_delay \
                --create-dirs -o "$item" "${mirror_base_url}${item}"
            if [ $? -eq 0 ]; then
                if gzip -t "$item" 2>/dev/null ; then
                    continue
                fi
                # complete but corrupt (e.g. a resume stitched across mirrors):
                # discard so the next mirror downloads it from scratch
                echo "Warning: $item fails the gzip integrity test - discarding it" >&2
                rm -f "$item"
            fi
            # transfer failed: keep the partial file for resuming from the next mirror
            n_missing=$((n_missing+1))
        done
        if [ "$n_missing" -eq 0 ]; then
            echo "All Tycho-2 files downloaded successfully" >&2
            return 0
        fi
        echo "Warning: $n_missing Tycho-2 file(s) still missing after trying $mirror_base_url" >&2
    done
    echo "ERROR: could not obtain a complete Tycho-2 copy from any of the mirrors" >&2
    return 1
}


function check_if_curl_is_too_old_to_attempt_HTTPS() {
    # Get the curl version
    curl_version=$(curl --version | head -n 1 | awk '{print $2}')
    
    # Use awk to compare versions without relying on sort -V
    curl_too_old=$(echo "$curl_version" | awk -F. '
        BEGIN { min_maj=7; min_min=34; min_patch=0; result="false" }
        {
            maj = $1 + 0;
            min = $2 + 0;
            patch = $3 + 0;
            
            if (maj < min_maj) { result="true" }
            else if (maj == min_maj && min < min_min) { result="true" }
            else if (maj == min_maj && min == min_min && patch < min_patch) { result="true" }
        }
        END { print result }
    ')
    
    echo $curl_too_old
}


function vastrealpath() {
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
      cd "$(dirname "$1")"
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD"
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


VASTDIR=$(get_vast_path_ends_with_slash_from_this_script_name "$0")

cd "$VASTDIR" || exit 1

# By default, do not download VSX and astorb.dat if they were not downloaded earlier
DOWNLOAD_EVERYTHING=0
if [ ! -z "$1" ];then
 DOWNLOAD_EVERYTHING=1
fi

if [ ! -d lib/catalogs ];then
 echo "ERROR locating lib/catalogs" >&2
 exit 1
fi

# The older version of curl use a version of TLS protocol that may not be supported by modern web servers,
# so the connection may fail even before the certificate exchange when the --insecure option will take effect.
# Use plain HTTP if curl is old.
if [[ $(check_if_curl_is_too_old_to_attempt_HTTPS) == false ]]; then
 # curl is new enough to attempt HTTPS

 # Get the country code using the centralized script with caching
 if [ -z "$VAST_COUNTRY_CODE" ];then
  VAST_COUNTRY_CODE=$("${VASTDIR}lib/get_country_code.sh")
 fi
 if [ -z "$VAST_COUNTRY_CODE" ];then
  # Fallback in case the script fails
  VAST_COUNTRY_CODE="RU"
 fi
 
 if [ "$VAST_COUNTRY_CODE" == "RU" ];then
  #LOCAL_SERVER="http://scan.sai.msu.ru/~kirx/vast_catalogs"
  LOCAL_SERVER="https://scan.sai.msu.ru/~kirx/vast_catalogs"
  #LOCAL_SERVER="https://kirx.net/~kirx/vast_catalogs"
 else
  LOCAL_SERVER="https://kirx.net/~kirx/vast_catalogs"
 fi
else
 # curl is too old to attempt HTTPS, we'll do plain HTTP instead
 LOCAL_SERVER="http://scan.sai.msu.ru/~kirx/vast_catalogs"
fi

export LOCAL_SERVER

# Get current date from the system clock
CURRENT_DATE_UNIXSEC=`date +%s`

cd "$VASTDIR" || exit 1

for FILE_TO_UPDATE in ObsCodes.html astorb.dat lib/catalogs/vsx.dat lib/catalogs/asassnv.csv ;do

 #can't have output here as it goes straight to the transient candidates list
 #echo "$0 is checking $FILE_TO_UPDATE"

 NEED_TO_UPDATE_THE_FILE=0

 # check if the file is there at all
 if [ ! -s "$FILE_TO_UPDATE" ];then
  echo "There is no file $FILE_TO_UPDATE or it is empty" >&2
  if [ $DOWNLOAD_EVERYTHING -eq 1 ] ;then
   NEED_TO_UPDATE_THE_FILE=1
  else
   echo "No need to update $FILE_TO_UPDATE" >&2
   continue
  fi 
  #
 else
  # First try Linux-style stat
  FILE_MODIFICATION_DATE=`stat -c "%Y" "$FILE_TO_UPDATE" 2>/dev/null`
  if [ $? -ne 0 ];then
   FILE_MODIFICATION_DATE=`stat -f "%m" "$FILE_TO_UPDATE" 2>/dev/null`
   if [ $? -ne 0 ];then
    echo "ERROR cannot get modification time for $FILE_TO_UPDATE" >&2
    exit 1
   fi
  fi
  # Check that FILE_MODIFICATION_DATE actually contains Unix seconds
  re='^[0-9]+$'
  if ! [[ $FILE_MODIFICATION_DATE =~ $re ]] ; then
   echo "ERROR inappropriate content of FILE_MODIFICATION_DATE=$FILE_MODIFICATION_DATE" >&2
   exit 1
  fi
 fi

 if [ $NEED_TO_UPDATE_THE_FILE -eq 0 ];then 
  # 2592000 seconds is 30 days
  # 4320000 seconds is 50 days - astorb.dat is supposed to provide 1" accuracy 
  # asteroid positions for +/-50 days of the file download.
  # See details at https://asteroid.lowell.edu/main/astorb/
  if [ $[$CURRENT_DATE_UNIXSEC-$FILE_MODIFICATION_DATE] -gt 4320000 ];then
   NEED_TO_UPDATE_THE_FILE=1
  fi
 fi
 
 # Check the catalog that is ALREADY installed, not just the ones we download.
 # Nothing else ever re-examines an installed catalog, so a file that arrived
 # incomplete stays in place and degrades every run silently - which is exactly
 # what happened on ariel with the 1000-record asassnv.csv stub. An implausibly
 # small catalog is re-downloaded regardless of its age.
 if [ -s "$FILE_TO_UPDATE" ];then
  INSTALLED_CATALOG_SIZE_BYTES=`get_file_size_in_bytes "$FILE_TO_UPDATE"`
  MINIMUM_CATALOG_SIZE_BYTES=`get_catalog_minimum_expected_size_in_bytes "$FILE_TO_UPDATE"`
  if [ -n "$INSTALLED_CATALOG_SIZE_BYTES" ] && [ "$MINIMUM_CATALOG_SIZE_BYTES" -gt 0 ] 2>/dev/null ;then
   if [ "$INSTALLED_CATALOG_SIZE_BYTES" -lt "$MINIMUM_CATALOG_SIZE_BYTES" ] 2>/dev/null ;then
    echo "WARNING: the installed $FILE_TO_UPDATE is only $INSTALLED_CATALOG_SIZE_BYTES bytes, far below the $MINIMUM_CATALOG_SIZE_BYTES bytes expected - it is incomplete and will be re-downloaded" >&2
    NEED_TO_UPDATE_THE_FILE=1
   fi
  fi
 fi

 if [ "$1" == "force" ];then
  echo "Forcing the catalog update per user request" >&2
  NEED_TO_UPDATE_THE_FILE=1
 fi

 # Update the file if needed
 if [ $NEED_TO_UPDATE_THE_FILE -eq 1 ];then
  echo "######### Updating $FILE_TO_UPDATE #########" >&2 
  CURL_COMMAND=""
  CURL_LOCAL_COMMAND=""
  UNPACK_COMMAND=""
  TMP_OUTPUT=""
  # Optional catalogs are the ones the transient search can run without (it will just skip
  # the corresponding identification step). A failed/empty download of an optional catalog is
  # reported as an ERROR but is NOT fatal to the update run.
  CATALOG_IS_OPTIONAL=0
  if [ "$FILE_TO_UPDATE" == "ObsCodes.html" ];then
   TMP_OUTPUT="ObsCodes.html_new"
   # curl https://www.minorplanetcenter.net/iau/lists/ObsCodes.html > ObsCodes.html
   CURL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --retry-delay 30 --speed-limit 100 --speed-time 30 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --continue-at - --output $TMP_OUTPUT https://www.minorplanetcenter.net/iau/lists/ObsCodes.html"
   CURL_LOCAL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --retry-delay 30 --speed-limit 100 --speed-time 30 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --continue-at - --output $TMP_OUTPUT http://scan.sai.msu.ru/~kirx/vast_catalogs/ObsCodes.html"
   UNPACK_COMMAND="ls $TMP_OUTPUT"
   DOWNLOAD_TARGET_FILE="$TMP_OUTPUT"
  fi
  if [ "$FILE_TO_UPDATE" == "astorb.dat" ];then
   TMP_OUTPUT="astorb_dat_new"
   CURL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --retry-delay 30 --speed-limit 100 --speed-time 30 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --continue-at - --output $TMP_OUTPUT.gz https://ftp.lowell.edu/pub/elgb/astorb.dat.gz"
   CURL_LOCAL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --retry-delay 30 --speed-limit 100 --speed-time 30 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --continue-at - --output $TMP_OUTPUT.gz $LOCAL_SERVER/astorb.dat.gz"
   UNPACK_COMMAND="gunzip $TMP_OUTPUT.gz"
   DOWNLOAD_TARGET_FILE="$TMP_OUTPUT.gz"
  fi
  if [ "$FILE_TO_UPDATE" == "lib/catalogs/vsx.dat" ];then
   TMP_OUTPUT="vsx.dat"
   CURL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --retry-delay 30 --speed-limit 100 --speed-time 30 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --continue-at - --output $TMP_OUTPUT.gz ftp://cdsarc.u-strasbg.fr/pub/cats/B/vsx/vsx.dat.gz"
   CURL_LOCAL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --retry-delay 30 --speed-limit 100 --speed-time 30 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --continue-at - --output $TMP_OUTPUT.gz $LOCAL_SERVER/vsx.dat.gz"
   UNPACK_COMMAND="gunzip $TMP_OUTPUT.gz"
   DOWNLOAD_TARGET_FILE="$TMP_OUTPUT.gz"
  fi
  if [ "$FILE_TO_UPDATE" == "lib/catalogs/asassnv.csv" ];then
   # The ASASSN-V catalog is only used to annotate transient candidates; the search can proceed
   # without it, so a failed/empty download must not abort the whole run.
   CATALOG_IS_OPTIONAL=1
   TMP_OUTPUT="asassnv.csv"
   # NOTE: the URL must NOT be wrapped in escaped quotes. These command strings
   # are run as unquoted "$1" inside attempt_download_with_resume(), which word-
   # splits them but does NOT perform quote removal, so \" would reach curl as
   # part of the URL and curl rejects it outright:
   #   curl: (3) URL rejected: Port number was not a decimal number between 0 and 65535
   # That silently disabled this fallback, which is why a mirror serving an
   # incomplete asassnv.csv had nothing to fall back to. The '?' and '&' are
   # safe unquoted here: word splitting does not re-parse operators, and the
   # other three catalogs have always passed their URLs the same way.
   CURL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --retry-delay 30 --speed-limit 100 --speed-time 30 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --continue-at - --output $TMP_OUTPUT https://asas-sn.osu.edu/variables.csv?action=index&controller=variables"
   CURL_LOCAL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --retry-delay 30 --speed-limit 100 --speed-time 30 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --continue-at - --output $TMP_OUTPUT $LOCAL_SERVER/asassnv.csv"
   UNPACK_COMMAND=""
   DOWNLOAD_TARGET_FILE="$TMP_OUTPUT"
  fi
  if [ -z "$CURL_COMMAND" ];then
   echo "ERROR CURL_COMMAND is not set" >&2
   exit 1
  fi
  if [ -z "$CURL_LOCAL_COMMAND" ];then
   echo "ERROR CURL_LOCAL_COMMAND is not set" >&2
   exit 1
  fi
  if [ -z "$TMP_OUTPUT" ];then
   echo "ERROR TMP_OUTPUT is not set" >&2
   exit 1
  fi
  
  
  # Remove a stale unpacked temporary from a previous run. A partial .gz
  # download from a previous run is deliberately KEPT: the download commands
  # use '--continue-at -' so this run resumes it instead of starting over,
  # and the gzip integrity test in attempt_download_with_resume() protects
  # against resuming a file the remote server has regenerated since.
  if [ -f "$TMP_OUTPUT" ];then
   rm -f "$TMP_OUTPUT"
  fi

  # Remember which URL the file actually came from, so the size check below
  # can ask that same source what it thinks the file size is. The URL is the
  # last word of the curl command line.
  DOWNLOAD_URL_USED=`echo "$CURL_LOCAL_COMMAND" | awk '{print $NF}' | tr -d '"'`

  # First try to download a catalog from the mirror
  echo "### CURL_LOCAL_COMMAND ###
$PWD" >&2
  echo "$CURL_LOCAL_COMMAND" >&2
  attempt_download_with_resume "$CURL_LOCAL_COMMAND" "$DOWNLOAD_TARGET_FILE"
  if [ $? -ne 0 ];then
   DOWNLOAD_URL_USED=`echo "$CURL_COMMAND" | awk '{print $NF}' | tr -d '"'`
   # Clean up the possible incompele downlaod - we can't be sure if $CURL_LOCAL_COMMAND and $CURL_COMMAND point to exact same version of the file
   if [ -f "$TMP_OUTPUT" ];then
    rm -f "$TMP_OUTPUT"
   fi
   if [ -f "$TMP_OUTPUT".gz ];then
    rm -f "$TMP_OUTPUT".gz
   fi
   #
   # if that failed, try to download the catalog from the original link
   echo "Failed to download from the local link, fallig back to $CURL_COMMAND" >&2
   attempt_download_with_resume "$CURL_COMMAND" "$DOWNLOAD_TARGET_FILE"
   if [ $? -ne 0 ];then
    echo "ERROR running the download command" >&2
    # Keep the partial .gz download (if any): the next update run will resume
    # it, so even repeatedly failing runs make forward progress on a large
    # catalog over an unstable connection.
    if [ -f "$TMP_OUTPUT" ];then
     rm -f "$TMP_OUTPUT"
    fi
    note_catalog_update_failure "$FILE_TO_UPDATE"
    continue
   fi
   #
  fi # if that failed
  echo "TMP_OUTPUT=$TMP_OUTPUT" >&2
  # If we are still here, we downloaded the catalog, one way or the other
  if [ ! -z "$UNPACK_COMMAND" ];then
   echo "### UNPACK_COMMAND ###
We are currently at $PWD
Will run the unpack command: $UNPACK_COMMAND" >&2
   # The output of this ls run makes me nervous as on of the files does not exist
   $UNPACK_COMMAND
   if [ $? -ne 0 ];then
    echo "ERROR running $UNPACK_COMMAND" >&2
    note_catalog_update_failure "$FILE_TO_UPDATE"
    continue
   else
    echo "Unpack complete" >&2
   fi
  fi
  if [ ! -s "$TMP_OUTPUT" ];then
   echo "ERROR: $TMP_OUTPUT is EMPTY!" >&2
   if [ -f "$TMP_OUTPUT" ];then
    rm -f "$TMP_OUTPUT"
   fi
   note_catalog_update_failure "$FILE_TO_UPDATE"
   continue
  fi
  # Size sanity check for plain (non-gzip) catalog downloads. The .gz
  # catalogs are protected by the gzip integrity test in
  # attempt_download_with_resume(), but a plain-file download can be
  # truncated with curl still reporting success: the live ASAS-SN endpoint
  # streams the CSV with no Content-Length, so a stream that ends early but
  # cleanly looks like a complete download (this replaced a good asassnv.csv
  # with a truncated one on ariel in Aug 2026). Refuse to replace an
  # existing catalog with a new file smaller than 80 percent of the old one:
  # real catalog releases never shrink that much. To override a false alarm
  # (a genuinely much smaller new catalog version), remove the old file and
  # re-run the update.
  case "$DOWNLOAD_TARGET_FILE" in
   *.gz)
    ;;
   *)
    NEW_CATALOG_SIZE_BYTES=`get_file_size_in_bytes "$TMP_OUTPUT"`

    # (a) Did we receive everything the server promised? A short transfer with
    # a known Content-Length makes curl fail, but only when the server sends
    # one - so check explicitly rather than trusting the exit code. Skipped
    # when the server advertises no size (the live ASAS-SN endpoint).
    REMOTE_CATALOG_SIZE_BYTES=`get_remote_content_length "$DOWNLOAD_URL_USED"`
    if [ -n "$REMOTE_CATALOG_SIZE_BYTES" ] && [ -n "$NEW_CATALOG_SIZE_BYTES" ];then
     if [ "$REMOTE_CATALOG_SIZE_BYTES" -gt 0 ] 2>/dev/null ;then
      if [ "$NEW_CATALOG_SIZE_BYTES" -ne "$REMOTE_CATALOG_SIZE_BYTES" ] 2>/dev/null ;then
       echo "ERROR: the downloaded $TMP_OUTPUT is $NEW_CATALOG_SIZE_BYTES bytes but $DOWNLOAD_URL_USED advertises $REMOTE_CATALOG_SIZE_BYTES - the transfer is incomplete, keeping the old file" >&2
       rm -f "$TMP_OUTPUT"
       note_catalog_update_failure "$FILE_TO_UPDATE"
       continue
      fi
     fi
    fi

    # (b) Is the file cut off in the middle of a record? The test is chosen per
    # catalog - see verify_catalog_structure().
    if ! verify_catalog_structure "$TMP_OUTPUT" "$FILE_TO_UPDATE" ;then
     echo "ERROR: the downloaded $TMP_OUTPUT does not look like a complete catalog file - keeping the old file" >&2
     rm -f "$TMP_OUTPUT"
     note_catalog_update_failure "$FILE_TO_UPDATE"
     continue
    fi

    # (c) Is it implausibly small in absolute terms? This is the check that
    # catches a well-formed but drastically incomplete catalog served by a
    # mirror, including on a fresh install where (d) below has nothing to
    # compare against. See get_catalog_minimum_expected_size_in_bytes().
    MINIMUM_CATALOG_SIZE_BYTES=`get_catalog_minimum_expected_size_in_bytes "$FILE_TO_UPDATE"`
    if [ -n "$NEW_CATALOG_SIZE_BYTES" ] && [ "$MINIMUM_CATALOG_SIZE_BYTES" -gt 0 ] 2>/dev/null ;then
     if [ "$NEW_CATALOG_SIZE_BYTES" -lt "$MINIMUM_CATALOG_SIZE_BYTES" ] 2>/dev/null ;then
      echo "ERROR: the downloaded $TMP_OUTPUT is only $NEW_CATALOG_SIZE_BYTES bytes, far below the $MINIMUM_CATALOG_SIZE_BYTES bytes expected for $FILE_TO_UPDATE - the source is serving an incomplete catalog, keeping the old file" >&2
      rm -f "$TMP_OUTPUT"
      note_catalog_update_failure "$FILE_TO_UPDATE"
      continue
     fi
    fi

    # (d) Never replace a good catalog with a much smaller one. Real releases
    # do not shrink by 20 percent. To override a false alarm (a genuinely much
    # smaller new version), remove the old file and re-run the update.
    if [ -s "$FILE_TO_UPDATE" ];then
     OLD_CATALOG_SIZE_BYTES=`get_file_size_in_bytes "$FILE_TO_UPDATE"`
     # If the sizes cannot be determined, skip the check (fail open)
     if [ -n "$OLD_CATALOG_SIZE_BYTES" ] && [ -n "$NEW_CATALOG_SIZE_BYTES" ];then
      if ! echo "$NEW_CATALOG_SIZE_BYTES $OLD_CATALOG_SIZE_BYTES" | awk '{exit !($1+0 >= 0.8*$2)}' ;then
       echo "ERROR: the downloaded $TMP_OUTPUT ($NEW_CATALOG_SIZE_BYTES bytes) is suspiciously smaller than the current $FILE_TO_UPDATE ($OLD_CATALOG_SIZE_BYTES bytes) - looks like a truncated download, keeping the old file (remove $FILE_TO_UPDATE and re-run the update to override)" >&2
       rm -f "$TMP_OUTPUT"
       note_catalog_update_failure "$FILE_TO_UPDATE"
       continue
      fi
     fi
    fi
    ;;
  esac
  mv "$TMP_OUTPUT" "$FILE_TO_UPDATE" && touch "$FILE_TO_UPDATE" && echo "Moved $TMP_OUTPUT to $FILE_TO_UPDATE" >&2
  echo "Successfully updated $FILE_TO_UPDATE" >&2
 fi

done

### Check if the  Bright  Star  Catalogue  (BSC) has been downloaded
if [ ! -s "lib/catalogs/bright_star_catalog_original.txt" ] || [ ! -s "lib/catalogs/brightbright_star_catalog_radeconly.txt" ] ;then
 echo "Downloading the Bright Star Catalogue" >&2
 # The CDS link is down
 #curl --silent ftp://cdsarc.u-strasbg.fr/pub/cats/V/50/catalog.gz | gunzip > lib/catalogs/bright_star_catalog_original.txt
 # Changed to local copy
 #curl --silent http://scan.sai.msu.ru/~kirx/data/bright_star_catalog_original.txt.gz | gunzip > lib/catalogs/bright_star_catalog_original.txt
 #curl --silent "$LOCAL_SERVER/bright_star_catalog_original.txt.gz" | gunzip > lib/catalogs/bright_star_catalog_original.txt
 curl $VAST_CURL_PROXY --connect-timeout 10 --insecure --silent --output lib/catalogs/bright_star_catalog_original.txt "$LOCAL_SERVER/bright_star_catalog_original.txt"
 if [ $? -eq 0 ];then
  echo "Extracting the R.A. Dec. list (all BSC)" >&2
  cat lib/catalogs/bright_star_catalog_original.txt | grep -v -e 'NOVA' -e '47    Tuc' -e 'M 31' -e 'NGC 2281' -e 'M 67' -e 'NGC 2808' | while IFS= read -r STR ;do 
   echo "${STR:75:2}:${STR:77:2}:${STR:79:4} ${STR:83:3}:${STR:86:2}:${STR:88:2}" 
  done > lib/catalogs/bright_star_catalog_radeconly.txt
  echo "Extracting the R.A. Dec. list (stars brighter than mag 4)" >&2
  # Exact lines, no trimming, Without '-r' option, any backslashes in the input will be discarded. You should almost always use the -r option with read.
  cat lib/catalogs/bright_star_catalog_original.txt | grep -v -e 'NOVA' -e '47    Tuc' -e 'M 31' -e 'NGC 2281' -e 'M 67' -e 'NGC 2808' | while IFS= read -r STR ;do 
   #echo "#$STR#"
   MAG=${STR:102:4}
   if [ -z "$MAG" ];then
    continue
   fi
   # get rid of white spaces
   MAG=`echo $MAG`
   # https://stackoverflow.com/questions/806906/how-do-i-test-if-a-variable-is-a-number-in-bash
   re='^[+-]?[0-9]+([.][0-9]+)?$'
   if ! [[ $MAG =~ $re ]] ; then
    echo "TEST ERROR: $MAG" >&2
    continue
   fi
   # Make sure we have the proper format
   MAG=`echo "$MAG" | awk '{printf "%.2f", $1}'`
   TEST=`echo "$MAG>4.0" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`   
   if [ $TEST -eq 1 ];then
    continue
   fi
   echo "${STR:75:2}:${STR:77:2}:${STR:79:4} ${STR:83:3}:${STR:86:2}:${STR:88:2}" 
  done > lib/catalogs/brightbright_star_catalog_radeconly.txt
 else
  echo "ERROR in $0 while downloading/unpacking the Bright Star Catalogue" >&2
  exit 1
 fi
#can't have output here as it goes straight to the transient candidates list
#else
# echo "The Bright Star Catalogue copy looks good"
fi

# Check if there is a copy of Tycho-2
TYCHO_PATH=lib/catalogs/tycho2
# Test for exotic Tycho-2 corruption scenarios
# (I use the hardcoded path instead of TYCHO_PATH on purpose)
#
# Test if a path is a broken symbolic link
if [ -L "lib/catalogs/tycho2" ] && [ ! -e "lib/catalogs/tycho2" ] ;then
 rm -f "lib/catalogs/tycho2"
fi
# Test if a path is a file
if [ -f "lib/catalogs/tycho2" ] ;then
 rm -f "lib/catalogs/tycho2"
fi
# Test if a path is an empty directory
if [ -d "lib/catalogs/tycho2" ] && [ -z "$(ls -A "lib/catalogs/tycho2")" ] ;then
 rm -rf "lib/catalogs/tycho2"
fi
#
if [ ! -f "$TYCHO_PATH/tyc2.dat.00" ];then
 echo "No local copy of Tycho-2 found (no $TYCHO_PATH/tyc2.dat.00)" >&2
 # Check if there is a local copy of Tycho-2 in the top directory
 if [ -s ../tycho2/tyc2.dat.19 ];then
  echo "Found nonempty ../tycho2/tyc2.dat.19
  ln -s ../tycho2 $TYCHO_PATH" >&2
  #ln -s `readlink -f ../tycho2` $TYCHO_PATH
  ln -s $(vastrealpath ../tycho2) "$TYCHO_PATH"
 else
  #
  echo "Tycho-2 catalog was not found at $TYCHO_PATH -- will try to download it" >&2
  if [ ! -d "$TYCHO_PATH" ];then
   mkdir "$TYCHO_PATH" || exit 1
  fi
  # Test if a path is a writable directory
  if [ ! -d "$TYCHO_PATH" ] || [ ! -w "$TYCHO_PATH" ];then
   echo "ERROR in $0: $TYCHO_PATH is not a writable directory!" >&2
   exit 1
  fi
  #
  cd "$TYCHO_PATH" || exit 1
  # Remove unpacked files of any incomplete copy of Tycho-2. Partial .gz
  # downloads are deliberately kept: get_tycho2_from_scan_with_curl resumes
  # them (and discards them if they fail the gzip integrity test).
  for i in tyc2.dat.?? ;do
   if [ -f "$i" ];then
    rm -f "$i"
   fi
  done
  #
  # wget instead of curl !!!
  # No $VAST_CURL_PROXY support here!
  #wget -nH --cut-dirs=4 --no-parent -r -l0 -c -A 'ReadMe,*.gz,robots.txt' "http://scan.sai.msu.ru/~kirx/data/tycho2/"
  if ! get_tycho2_from_scan_with_curl ; then
   echo "ERROR in $0: failed to download the Tycho-2 catalog copy from scan.sai.msu.ru" >&2
   cd "$VASTDIR" || exit 1
   exit 1
  fi
  echo "Download complete. Unpacking..." >&2
  for i in tyc2.dat.*gz ;do
   # handle a very special case: `basename $i .gz` is a broken symlink
   if [ -L `basename $i .gz` ];then
    # if this is a symlink
    if [ ! -e `basename $i .gz` ];then
     # if it is broken
     rm -f `basename $i .gz`
     # remove that symlink
    fi
   fi
   #
   gunzip "$i"
  done
  cd "$VASTDIR" || exit 1
 fi # if [ -s ../tycho2/tyc2.dat.19 ];then 
fi
# Check if Tycho-2 copy looks healthy
for i in 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19; do
 if [ ! -f "$TYCHO_PATH"/tyc2.dat."$i" ];then
  echo "ERROR in $0 while checking Tycho-2 copy: file $TYCHO_PATH/tyc2.dat.$i is not found" >&2
  exit 1
 fi
 if [ ! -s "$TYCHO_PATH"/tyc2.dat."$i" ];then
  echo "ERROR in $0 while checking Tycho-2 copy: file $TYCHO_PATH/tyc2.dat.$i is empty" >&2
  exit 1
 fi
done
#can't have output here as it goes straight to the transient candidates list
#echo "Tycho-2 copy looks healthy"
# Just to be sure we are at the top level dir
cd "$VASTDIR" || exit 1
if [ ! -s lib/catalogs/list_of_bright_stars_from_tycho2.txt ];then
 # Create a list of stars brighter than mag 9.1 for filtering transient candidates
 # also in 
 lib/catalogs/create_tycho2_list_of_bright_stars_to_exclude_from_transient_search 9.1
 if [ $? -ne 0 ];then
  echo "ERROR in $0: non-zero exit code from running 'lib/catalogs/create_tycho2_list_of_bright_stars_to_exclude_from_transient_search 9.1'" >&2
  exit 1
 fi
 if [ ! -s lib/catalogs/list_of_bright_stars_from_tycho2.txt ];then
  echo "ERROR in $0: lib/catalogs/list_of_bright_stars_from_tycho2.txt is empty" >&2
  exit 1
 fi
fi
#can't have output here as it goes straight to the transient candidates list
#echo "The Tycho-2 list of bright stars looks good"

# A catalog we could neither update nor find already installed is reported here,
# at the very end, rather than where it happened: the loop above deliberately
# carries on so that one unreachable source cannot cost us the other three, and
# the Bright Star Catalogue and Tycho-2 above are installed either way. The
# caller still sees a non-zero exit code, which is what it acts on.
if [ "$CATALOG_UPDATE_HARD_FAILURE" -ne 0 ] 2>/dev/null ;then
 echo "ERROR: one or more required catalogs are missing and could not be downloaded - see the messages above" >&2
 exit 1
fi

exit 0
