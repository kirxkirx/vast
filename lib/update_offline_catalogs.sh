#!/usr/bin/env bash

# This script will update the copies of VSX and ASASSN-V catalogs for offline use

# Max total time for catalog download
# Assume the connection is fast enough for the catalog to be downlaoded in less than 
CATALOG_DOWNLOAD_TIMEOUT_SEC=1800

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

## Function to download Tycho2 dataset files
#get_tycho2_from_scan_with_curl() {
# local url="http://scan.sai.msu.ru/~kirx/data/tycho2/"
# 
# # Get the directory listing
# listing=$(curl $VAST_CURL_PROXY -s "$url" | grep -o 'href="[^"]*"' | cut -d'"' -f2)
# 
# for item in $listing; do
#  # Skip directory links
#  [[ "$item" == */ ]] && continue
#  # Check if file matches our patterns
#  if [[ "$item" == "ReadMe" || "$item" == *.gz || "$item" == "robots.txt" ]]; then
#   # Download file with continuation
#   echo "Downloading: $item"
#   curl $VAST_CURL_PROXY -C - -s --create-dirs -o "$item" "${url}${item}"
#  fi
# done
#}
get_tycho2_from_scan_with_curl() {
    local url="http://scan.sai.msu.ru/~kirx/data/tycho2/"
    local max_retries=5
    local retry_delay=2

    # Get the directory listing
    listing=$(curl $VAST_CURL_PROXY -s "$url" | grep -o 'href="[^"]*"' | cut -d'"' -f2)

    if [[ -z "$listing" ]]; then
        echo "Error: Could not retrieve directory listing"
        return 1
    fi

    for item in $listing; do
        # Skip directory links
        [[ "$item" == */ ]] && continue

        # Check if file matches the desired patterns
        if [[ "$item" == "ReadMe" || "$item" == *.gz || "$item" == "robots.txt" ]]; then
            echo "Downloading: $item"
            curl --silent --show-error --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC \
                $VAST_CURL_PROXY -C - --retry $max_retries --retry-delay $retry_delay \
                --create-dirs -o "$item" "${url}${item}"
            if [[ $? -ne 0 ]]; then
                echo "Failed to download: $item after $max_retries attempts"
                return 1
            fi
        fi
    done

    echo "All files downloaded successfully"
    return 0
}


function check_if_curl_is_too_old_to_attempt_HTTPS() {
    # Get the curl version
    curl_version=$(curl --version | head -n 1 | awk '{print $2}')

    # Minimum required version: 7.34.0
    required_version="7.34.0"

    # Compare versions
    if [[ $(printf '%s\n' "$required_version" "$curl_version" | sort -V | head -n 1) == "$required_version" ]]; then
        echo true
    else
        echo false
    fi
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
 echo "ERROR locating lib/catalogs" 
 exit 1
fi

# The older version of curl use a version of TLS protocol that may not be supported by modern web servers,
# so the connection may fail even before the certificate exchange when the --insecure option will take effect.
# Use plain HTTP if curl is old.
if [[ $(check_if_curl_is_too_old_to_attempt_HTTPS) == true ]]; then
 # curl is new enough to attempt HTTPS

 # Try to get the country code
 COUNTRY_CODE=$(curl $VAST_CURL_PROXY --silent --connect-timeout 10 --insecure https://ipinfo.io/ | grep '"country":' | awk -F'"country":' '{print $2}' | awk -F'"' '{print $2}')
 if [ -z "$COUNTRY_CODE" ];then
  # Set UN code for UNknown
  COUNTRY_CODE="UN"
 fi
 
 if [ "$COUNTRY_CODE" == "RU" ];then
  #LOCAL_SERVER="http://scan.sai.msu.ru/~kirx/vast_catalogs"
  # scan.sai.msu.ru is temporary down
  LOCAL_SERVER="https://kirx.net/~kirx/vast_catalogs"
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

cd "$VASTDIR"

for FILE_TO_UPDATE in ObsCodes.html astorb.dat lib/catalogs/vsx.dat lib/catalogs/asassnv.csv ;do
#for FILE_TO_UPDATE in astorb.dat ;do
 NEED_TO_UPDATE_THE_FILE=0

 # check if the file is there at all
 if [ ! -s "$FILE_TO_UPDATE" ];then
  echo "There is no file $FILE_TO_UPDATE or it is empty" 
  # I don't want any special treatment for asassnv
  ## Always update only lib/catalogs/asassnv.csv if it does not exist
  #if [ "$FILE_TO_UPDATE" == "lib/catalogs/asassnv.csv" ] || [ $DOWNLOAD_EVERYTHING -eq 1 ] ;then
  # NEED_TO_UPDATE_THE_FILE=1
  #else
  # continue
  #fi
  if [ $DOWNLOAD_EVERYTHING -eq 1 ] ;then
   NEED_TO_UPDATE_THE_FILE=1
  else
   continue
  fi 
  #
 else
  # First try Linux-style stat
  FILE_MODIFICATION_DATE=`stat -c "%Y" "$FILE_TO_UPDATE" 2>/dev/null`
  if [ $? -ne 0 ];then
   FILE_MODIFICATION_DATE=`stat -f "%m" "$FILE_TO_UPDATE" 2>/dev/null`
   if [ $? -ne 0 ];then
    echo "ERROR cannot get modification time for $FILE_TO_UPDATE" 
    exit 1
   fi
  fi
  # Check that FILE_MODIFICATION_DATE actually contains Unix seconds
  re='^[0-9]+$'
  if ! [[ $FILE_MODIFICATION_DATE =~ $re ]] ; then
   echo "ERROR inappropriate content of FILE_MODIFICATION_DATE=$FILE_MODIFICATION_DATE" 
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
 
 if [ "$1" == "force" ];then
  echo "Forcing the catalog update per user request"  
  NEED_TO_UPDATE_THE_FILE=1
 fi

 # Update the file if needed
 if [ $NEED_TO_UPDATE_THE_FILE -eq 1 ];then
  echo "######### Updating $FILE_TO_UPDATE #########" 
  CURL_COMMAND=""
  CURL_LOCAL_COMMAND=""
  UNPACK_COMMAND=""
  TMP_OUTPUT=""
  if [ "$FILE_TO_UPDATE" == "ObsCodes.html" ];then
   TMP_OUTPUT="ObsCodes.html_new"
   # curl https://www.minorplanetcenter.net/iau/lists/ObsCodes.html > ObsCodes.html
   CURL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --output $TMP_OUTPUT https://www.minorplanetcenter.net/iau/lists/ObsCodes.html"
   CURL_LOCAL_COMMAND="$CURL_COMMAND"
   UNPACK_COMMAND="ls $TMP_OUTPUT"
  fi
  if [ "$FILE_TO_UPDATE" == "astorb.dat" ];then
   TMP_OUTPUT="astorb_dat_new"
   CURL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --output $TMP_OUTPUT.gz https://ftp.lowell.edu/pub/elgb/astorb.dat.gz"
   CURL_LOCAL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --output $TMP_OUTPUT.gz $LOCAL_SERVER/astorb.dat.gz"
   UNPACK_COMMAND="gunzip $TMP_OUTPUT.gz"
  fi
  if [ "$FILE_TO_UPDATE" == "lib/catalogs/vsx.dat" ];then
   TMP_OUTPUT="vsx.dat"
   CURL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --output $TMP_OUTPUT.gz  $TMP_OUTPUT.gz ftp://cdsarc.u-strasbg.fr/pub/cats/B/vsx/vsx.dat.gz"
   CURL_LOCAL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --output $TMP_OUTPUT.gz $LOCAL_SERVER/vsx.dat.gz"
   UNPACK_COMMAND="gunzip $TMP_OUTPUT.gz"
  fi
  if [ "$FILE_TO_UPDATE" == "lib/catalogs/asassnv.csv" ];then
   TMP_OUTPUT="asassnv.csv"
   CURL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --output $TMP_OUTPUT \"https://asas-sn.osu.edu/variables.csv?action=index&controller=variables\""
   CURL_LOCAL_COMMAND="curl $VAST_CURL_PROXY --connect-timeout 10 --retry 1 --max-time $CATALOG_DOWNLOAD_TIMEOUT_SEC --insecure --output $TMP_OUTPUT $LOCAL_SERVER/asassnv.csv"
   UNPACK_COMMAND=""
  fi
  if [ -z "$CURL_COMMAND" ];then
   echo "ERROR CURL_COMMAND is not set" 
   exit 1
  fi
  if [ -z "$CURL_LOCAL_COMMAND" ];then
   echo "ERROR CURL_LOCAL_COMMAND is not set" 
   exit 1
  fi
  if [ -z "$TMP_OUTPUT" ];then
   echo "ERROR TMP_OUTPUT is not set" 
   exit 1
  fi
  
  
  if [ -f "$TMP_OUTPUT" ];then
   rm -f "$TMP_OUTPUT"
  fi
  if [ -f "$TMP_OUTPUT".gz ];then
   rm -f "$TMP_OUTPUT".gz
  fi

  # First try to download a catalog from the mirror
  echo "### CURL_LOCAL_COMMAND ###
$PWD" 
  echo "$CURL_LOCAL_COMMAND" 
  $CURL_LOCAL_COMMAND
  if [ $? -ne 0 ];then
   # if that failed, try to download the catalog from the original link
   echo "We are currently at $CURL_COMMAND" 
   $CURL_COMMAND
   if [ $? -ne 0 ];then
    echo "ERROR running the download command" 
    if [ -f "$TMP_OUTPUT" ];then
     rm -f "$TMP_OUTPUT"
    fi
    exit 1
   fi
   #
  fi # if that failed
  # The output of this ls run makes me nervous as on of the files does not exist
  #ls -lh $TMP_OUTPUT $TMP_OUTPUT.gz 
  # If we are still here, we downloaded the catalog, one way or the other
  if [ ! -z "$UNPACK_COMMAND" ];then
   echo "### UNPACK_COMMAND ###
We are currently at $PWD
Will run the unpack command: $UNPACK_COMMAND" 
   # The output of this ls run makes me nervous as on of the files does not exist
   $UNPACK_COMMAND
   if [ $? -ne 0 ];then
    echo "ERROR running $UNPACK_COMMAND" 
    exit 1
   else
    echo "Unpack complete" 
   fi
  fi
  if [ ! -s "$TMP_OUTPUT" ];then
   echo "ERROR: $TMP_OUTPUT is EMPTY!"  
   if [ -f "$TMP_OUTPUT" ];then
    rm -f "$TMP_OUTPUT"
   fi
   exit 1
  fi
  mv -v "$TMP_OUTPUT" "$FILE_TO_UPDATE"  && touch "$FILE_TO_UPDATE"
  echo "Successfully updated $FILE_TO_UPDATE"
 fi

done

### Check if the  Bright  Star  Catalogue  (BSC) has been downloaded
if [ ! -s "lib/catalogs/bright_star_catalog_original.txt" ] || [ ! -s "lib/catalogs/brightbright_star_catalog_radeconly.txt" ] ;then
 echo "Downloading the Bright Star Catalogue"
 # The CDS link is down
 #curl --silent ftp://cdsarc.u-strasbg.fr/pub/cats/V/50/catalog.gz | gunzip > lib/catalogs/bright_star_catalog_original.txt
 # Changed to local copy
 #curl --silent http://scan.sai.msu.ru/~kirx/data/bright_star_catalog_original.txt.gz | gunzip > lib/catalogs/bright_star_catalog_original.txt
 #curl --silent "$LOCAL_SERVER/bright_star_catalog_original.txt.gz" | gunzip > lib/catalogs/bright_star_catalog_original.txt
 curl $VAST_CURL_PROXY --connect-timeout 10 --insecure --silent --output lib/catalogs/bright_star_catalog_original.txt "$LOCAL_SERVER/bright_star_catalog_original.txt"
 if [ $? -eq 0 ];then
  echo "Extracting the R.A. Dec. list (all BSC)"
  cat lib/catalogs/bright_star_catalog_original.txt | grep -v -e 'NOVA' -e '47    Tuc' -e 'M 31' -e 'NGC 2281' -e 'M 67' -e 'NGC 2808' | while IFS= read -r STR ;do 
   echo "${STR:75:2}:${STR:77:2}:${STR:79:4} ${STR:83:3}:${STR:86:2}:${STR:88:2}" 
  done > lib/catalogs/bright_star_catalog_radeconly.txt
  echo "Extracting the R.A. Dec. list (stars brighter than mag 4)"
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
    echo "TEST ERROR: $MAG" 
    continue
   fi
   # Make sure we have the proper format
   MAG=`echo "$MAG" | awk '{printf "%.2f", $1}'`
   #TEST=`echo "$MAG > 4.0" | bc -ql`
   TEST=`echo "$MAG>4.0" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`   
   if [ $TEST -eq 1 ];then
    continue
   fi
   echo "${STR:75:2}:${STR:77:2}:${STR:79:4} ${STR:83:3}:${STR:86:2}:${STR:88:2}" 
  done > lib/catalogs/brightbright_star_catalog_radeconly.txt
 else
  echo "ERROR downloading/unpacking the Bright Star Catalogue"
 fi
fi

# Check if there is a copy of Tycho-2
TYCHO_PATH=lib/catalogs/tycho2
if [ ! -f $TYCHO_PATH/tyc2.dat.00 ];then
 echo "No local copy of Tycho-2 found (no $TYCHO_PATH/tyc2.dat.00)"
 # Check if there is a local copy of Tycho-2 in the top directory
 if [ -s ../tycho2/tyc2.dat.19 ];then
  echo "Found nonempty ../tycho2/tyc2.dat.19
  ln -s ../tycho2 $TYCHO_PATH"
  #ln -s `readlink -f ../tycho2` $TYCHO_PATH
  ln -s `vastrealpath ../tycho2` $TYCHO_PATH
 else
  #
  echo "Tycho-2 catalog was not found at $TYCHO_PATH"
  if [ ! -d $TYCHO_PATH ];then
   mkdir $TYCHO_PATH
  fi
  cd $TYCHO_PATH 
  # remove any incomplete copy of Tycho-2
  for i in tyc2.dat.* ;do
   if [ -f "$i" ];then
    rm -f "$i"
   fi
  done
  #
  # wget instead of curl !!!
  # No $VAST_CURL_PROXY support here!
  #wget -nH --cut-dirs=4 --no-parent -r -l0 -c -A 'ReadMe,*.gz,robots.txt' "http://scan.sai.msu.ru/~kirx/data/tycho2/"
  get_tycho2_from_scan_with_curl
  echo "Download complete. Unpacking..."
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
   gunzip $i
  done
  cd $VASTDIR
 fi # if [ -s ../tycho2/tyc2.dat.19 ];then 
fi
cd $VASTDIR
if [ ! -s lib/catalogs/list_of_bright_stars_from_tycho2.txt ];then
 # Create a list of stars brighter than mag 9.1 for filtering transient candidates
 # also in 
 lib/catalogs/create_tycho2_list_of_bright_stars_to_exclude_from_transient_search 9.1
fi

