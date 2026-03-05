#!/usr/bin/env bash

# This script determines the user's country code (2-letter ISO 3166-1 alpha-2)
# and caches it in .vast_country_code in the VaST root directory.
# The cache is valid for 7 days (604800 seconds).
#
# Usage: VAST_COUNTRY_CODE=$(lib/get_country_code.sh)
#
# The country code can be overridden by setting the VAST_COUNTRY_CODE
# environment variable before calling this script.

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Cache validity in seconds (7 days)
CACHE_MAX_AGE_SEC=604800

# If VAST_COUNTRY_CODE is already set upstream, just print it and exit
# (do not update the cache -- the user knows what they are doing)
if [ -n "$VAST_COUNTRY_CODE" ];then
 echo "$VAST_COUNTRY_CODE"
 exit 0
fi

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
     cd "$(dirname "$1")" || return 1
     REALPATH="$PWD/$(basename "$1")"
     cd "$OURPWD" || return 1
    fi # grealpath
   fi # realpath
  fi # greadlink -f
 fi # readlink -f
 echo "$REALPATH"
}

# Function to remove the last occurrence of a directory from a path
remove_last_occurrence() {
 echo "$1" | awk -F/ -v dir="$2" '{
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
 VAST_PATH=$(vastrealpath "$0")
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

# Get the portable file modification time in Unix seconds
# Works on Linux (stat -c), macOS and FreeBSD (stat -f)
get_file_mtime_unixsec() {
 local FILE_TO_CHECK="$1"
 local MTIME
 MTIME=$(stat -c "%Y" "$FILE_TO_CHECK" 2>/dev/null)
 if [ $? -ne 0 ];then
  MTIME=$(stat -f "%m" "$FILE_TO_CHECK" 2>/dev/null)
  if [ $? -ne 0 ];then
   echo ""
   return 1
  fi
 fi
 echo "$MTIME"
 return 0
}

# Validate that a string is a 2-letter uppercase country code
is_valid_country_code() {
 local CODE="$1"
 # Remove any trailing whitespace/newline
 CODE=$(echo "$CODE" | tr -d '[:space:]')
 if echo "$CODE" | grep -qE '^[A-Z][A-Z]$' ;then
  echo "$CODE"
  return 0
 fi
 return 1
}

# Try to determine country code from a web service
try_web_service() {
 local URL="$1"
 local PARSE_MODE="$2"
 local RESPONSE
 local CODE

 # shellcheck disable=SC2086
 RESPONSE=$(curl $VAST_CURL_PROXY --silent --connect-timeout 10 --max-time 15 --insecure "$URL" 2>/dev/null)
 if [ $? -ne 0 ] || [ -z "$RESPONSE" ];then
  return 1
 fi

 if [ "$PARSE_MODE" = "plain" ];then
  CODE=$(echo "$RESPONSE" | tr -d '[:space:]')
 elif [ "$PARSE_MODE" = "json_country" ];then
  # Parse JSON like {"ip":"...","country":"US"}
  CODE=$(echo "$RESPONSE" | grep -o '"country":"[A-Z][A-Z]"' | awk -F'"' '{print $4}')
 fi

 is_valid_country_code "$CODE"
 return $?
}

# Check if the system timezone suggests Russia
check_timezone_for_russia() {
 local TZ_NAME=""

 # Try to read the timezone from /etc/timezone (Debian/Ubuntu)
 if [ -f /etc/timezone ];then
  TZ_NAME=$(cat /etc/timezone 2>/dev/null)
 fi

 # Try timedatectl (systemd-based Linux)
 if [ -z "$TZ_NAME" ];then
  TZ_NAME=$(timedatectl 2>/dev/null | grep -i 'time zone' | awk '{print $3}')
 fi

 # Try readlink on /etc/localtime (works on Linux, macOS, FreeBSD)
 if [ -z "$TZ_NAME" ];then
  TZ_NAME=$(readlink /etc/localtime 2>/dev/null | sed 's|.*/zoneinfo/||')
 fi

 # Try the TZ environment variable
 if [ -z "$TZ_NAME" ];then
  TZ_NAME="$TZ"
 fi

 if [ -z "$TZ_NAME" ];then
  return 1
 fi

 # Check against known Russian timezones
 case "$TZ_NAME" in
  Europe/Moscow|Europe/Kaliningrad|Europe/Samara|Europe/Volgograd|\
  Europe/Saratov|Europe/Kirov|Europe/Astrakhan|Europe/Ulyanovsk|\
  Asia/Yekaterinburg|Asia/Omsk|Asia/Novosibirsk|Asia/Barnaul|\
  Asia/Tomsk|Asia/Novokuznetsk|Asia/Krasnoyarsk|Asia/Irkutsk|\
  Asia/Chita|Asia/Yakutsk|Asia/Khandyga|Asia/Vladivostok|\
  Asia/Ust-Nera|Asia/Magadan|Asia/Sakhalin|Asia/Srednekolymsk|\
  Asia/Kamchatka|Asia/Anadyr)
   echo "RU"
   return 0
   ;;
 esac

 return 1
}


########################################
# Main script logic
########################################

VASTDIR=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
CACHE_FILE="${VASTDIR}.vast_country_code"

# Check if the cache file exists and is fresh enough
if [ -s "$CACHE_FILE" ];then
 CURRENT_DATE_UNIXSEC=$(date +%s)
 FILE_MODIFICATION_DATE=$(get_file_mtime_unixsec "$CACHE_FILE")
 if [ -n "$FILE_MODIFICATION_DATE" ];then
  # Check that FILE_MODIFICATION_DATE actually contains Unix seconds
  re='^[0-9]+$'
  if [[ $FILE_MODIFICATION_DATE =~ $re ]];then
   CACHE_AGE=$((CURRENT_DATE_UNIXSEC - FILE_MODIFICATION_DATE))
   if [ "$CACHE_AGE" -lt "$CACHE_MAX_AGE_SEC" ];then
    # Cache is fresh, use it
    CACHED_CODE=$(cat "$CACHE_FILE" | tr -d '[:space:]')
    VALID_CODE=$(is_valid_country_code "$CACHED_CODE")
    if [ $? -eq 0 ];then
     echo "$VALID_CODE"
     exit 0
    fi
    # Cache content is invalid, fall through to re-determine
   fi
  fi
 fi
fi

# Cache is missing, expired, or invalid -- determine country code
COUNTRY_CODE=""

# Try web services in order (stop at first success)
if [ -z "$COUNTRY_CODE" ];then
 COUNTRY_CODE=$(try_web_service "https://ipinfo.io/country" "plain")
fi
if [ -z "$COUNTRY_CODE" ];then
 COUNTRY_CODE=$(try_web_service "http://ip-api.com/line/?fields=countryCode" "plain")
fi
if [ -z "$COUNTRY_CODE" ];then
 COUNTRY_CODE=$(try_web_service "https://ipapi.co/country/" "plain")
fi
if [ -z "$COUNTRY_CODE" ];then
 COUNTRY_CODE=$(try_web_service "https://api.country.is/" "json_country")
fi

# If all web services failed, try timezone heuristic
if [ -z "$COUNTRY_CODE" ];then
 COUNTRY_CODE=$(check_timezone_for_russia)
fi

# If everything failed, default to RU
# (conservative: Russian users need special routing;
#  for non-Russian users, Russian servers still work, just slower)
if [ -z "$COUNTRY_CODE" ];then
 COUNTRY_CODE="RU"
fi

# Write the result to cache atomically
# Use a temp file with PID and RANDOM to avoid collisions
TMP_CACHE_FILE="${CACHE_FILE}.tmp_$$_${RANDOM}"
if echo "$COUNTRY_CODE" > "$TMP_CACHE_FILE" 2>/dev/null ;then
 if ! mv -f "$TMP_CACHE_FILE" "$CACHE_FILE" 2>/dev/null ;then
  # mv failed (e.g. read-only filesystem), clean up
  rm -f "$TMP_CACHE_FILE" 2>/dev/null
 fi
else
 # Could not write temp file, clean up
 rm -f "$TMP_CACHE_FILE" 2>/dev/null
fi

echo "$COUNTRY_CODE"
exit 0
