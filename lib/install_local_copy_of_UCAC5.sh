#!/usr/bin/env bash

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
#wget -c --no-dir ftp://cdsarc.u-strasbg.fr/0/more/UCAC5/u5z/*
wget -r -Az* -c --no-dir "http://scan.sai.msu.ru/~kirx/data/ucac5"
if [ $? -eq 0 ];then
 echo "Download complete"
else
 echo "ERROR running wget"
fi
