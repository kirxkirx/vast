#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ ! -d lib/catalogs ];then
 echo "ERROR locating lib/catalogs
should you start this script from the VaST home directory?"
 exit 1
fi

### Ask the user
while true ;do
 echo "Do you want to download the full UCAC5 catalog (5.3G)? (yes/no)"
 read USERS_ANSWER
 if [ "yes" = "$USERS_ANSWER" ] || [ "y" = "$USERS_ANSWER" ] || [ "ys" = "$USERS_ANSWER" ] || [ "Yes" = "$USERS_ANSWER" ] || [ "YES" = "$USERS_ANSWER" ] ;then
  USERS_ANSWER="yes"
  break
 elif [ "no" = "$USERS_ANSWER" ] || [ "n" = "$USERS_ANSWER" ] || [ "N" = "$USERS_ANSWER" ] || [ "NO" = "$USERS_ANSWER" ] ;then
  USERS_ANSWER="no"
  break
 fi
done

if [ "$USERS_ANSWER" = "no" ];then
 exit 0
else
 echo "Downloading the catalog"
fi

if [ ! -d lib/catalogs/ucac5 ];then
 mkdir lib/catalogs/ucac5
fi

cd lib/catalogs/ucac5

UCAC5_URL="http://scan.sai.msu.ru/~kirx/data/ucac5/"
DOWNLOAD_OK=0

# Try curl first: parse the HTML directory listing and fetch each z* file
if command -v curl >/dev/null 2>&1 ;then
 LISTING=$(curl $VAST_CURL_PROXY -s "$UCAC5_URL" | grep -o 'href="[^"]*"' | cut -d'"' -f2)
 if [ -n "$LISTING" ];then
  CURL_ALL_OK=1
  for ITEM in $LISTING ;do
   case "$ITEM" in
    */) continue ;;
    z*)
     echo "Downloading: $ITEM" >&2
     curl $VAST_CURL_PROXY --silent --show-error --max-time 1800 \
          --continue-at - --retry 5 --retry-delay 2 \
          -o "$ITEM" "${UCAC5_URL}${ITEM}"
     if [ $? -ne 0 ];then
      echo "curl failed on $ITEM" >&2
      CURL_ALL_OK=0
      break
     fi
     ;;
   esac
  done
  if [ "$CURL_ALL_OK" = "1" ];then
   DOWNLOAD_OK=1
  fi
 fi
 if [ "$DOWNLOAD_OK" != "1" ];then
  echo "curl-based download incomplete, falling back to wget" >&2
 fi
fi

# Fall back to wget if curl did not complete
if [ "$DOWNLOAD_OK" != "1" ];then
 if command -v wget >/dev/null 2>&1 ;then
  #wget -c --no-dir ftp://cdsarc.u-strasbg.fr/0/more/UCAC5/u5z/*
  wget -r -Az* -c --no-dir "$UCAC5_URL"
  if [ $? -eq 0 ];then
   DOWNLOAD_OK=1
  fi
 else
  echo "ERROR: neither curl nor wget is available to download UCAC5" >&2
 fi
fi

if [ "$DOWNLOAD_OK" = "1" ];then
 echo "Download complete"
else
 echo "ERROR downloading UCAC5"
fi
