#!/usr/bin/env bash

# This script will update the copies of VSX and ASASSN-V catalogs for offline use

# By default, do not download VSX and astorb.dat ifthey were not downloaded earlier
DOWNLOAD_EVERYTHING=0
if [ ! -z "$1" ];then
 DOWNLOAD_EVERYTHING=1
fi

if [ ! -d lib/catalogs ];then
 echo "ERROR locating lib/catalogs" >> /dev/stderr
 exit 1
fi

# Get current date from the system clock
CURRENT_DATE_UNIXSEC=`date +%s`

for FILE_TO_UPDATE in astorb.dat lib/catalogs/vsx.dat lib/catalogs/asassnv.csv ;do
 NEED_TO_UPDATE_THE_FILE=0

 # check if the file is there at all
 if [ ! -s "$FILE_TO_UPDATE" ];then
  echo "There is no file $FILE_TO_UPDATE or it is empty" >> /dev/stderr
  # Always update only lib/catalogs/asassnv.csv
  if [ "$FILE_TO_UPDATE" == "lib/catalogs/asassnv.csv" ] || [ $DOWNLOAD_EVERYTHING -eq 1 ] ;then
   NEED_TO_UPDATE_THE_FILE=1
  else
   continue
  fi
 else
  # First try Linux-style stat
  FILE_MODIFICATION_DATE=`stat -c "%Y" "$FILE_TO_UPDATE" 2>/dev/null`
  if [ $? -ne 0 ];then
   FILE_MODIFICATION_DATE=`stat -f "%m" "$FILE_TO_UPDATE" 2>/dev/null`
   if [ $? -ne 0 ];then
    echo "ERROR cannot get modification time for $FILE_TO_UPDATE" >> /dev/stderr
    exit 1
   fi
  fi
  # Check that FILE_MODIFICATION_DATE actually contains Unix seconds
  re='^[0-9]+$'
  if ! [[ $FILE_MODIFICATION_DATE =~ $re ]] ; then
   echo "ERROR inappropriate content of FILE_MODIFICATION_DATE=$FILE_MODIFICATION_DATE" >> /dev/stderr
   exit 1
  fi
 fi

 if [ $NEED_TO_UPDATE_THE_FILE -eq 0 ];then 
  # 2592000 is 30 days
  if [ $[$CURRENT_DATE_UNIXSEC-$FILE_MODIFICATION_DATE] -gt 2592000 ];then
   NEED_TO_UPDATE_THE_FILE=1
  fi
 fi
 
 # TEST !!!
 #NEED_TO_UPDATE_THE_FILE=1

 if [ "$1" == "force" ];then
  echo "Forcing the catalog update per user request"  >> /dev/stderr
  NEED_TO_UPDATE_THE_FILE=1
 fi

 # Update the file if needed
 if [ $NEED_TO_UPDATE_THE_FILE -eq 1 ];then
  echo "######### Updating $FILE_TO_UPDATE #########" >> /dev/stderr
  WGET_COMMAND=""
  WGET_LOCAL_COMMAND=""
  UNPACK_COMMAND=""
  TMP_OUTPUT=""
  if [ "$FILE_TO_UPDATE" == "astorb.dat" ];then
   TMP_OUTPUT="astorb.dat.new"
   WGET_COMMAND="wget -O $TMP_OUTPUT.gz --timeout=120 --tries=2 ftp://ftp.lowell.edu/pub/elgb/astorb.dat.gz"
   WGET_LOCAL_COMMAND="wget -O $TMP_OUTPUT.gz --timeout=120 --tries=2 http://scan.sai.msu.ru/~kirx/catalogs/compressed/astorb.dat.gz"
   UNPACK_COMMAND="gunzip $TMP_OUTPUT.gz && mv astorb.dat.new astorb.dat"
  fi
  if [ "$FILE_TO_UPDATE" == "lib/catalogs/vsx.dat" ];then
   TMP_OUTPUT="vsx.dat"
   WGET_COMMAND="wget -O $TMP_OUTPUT.gz --timeout=120 --tries=2 ftp://cdsarc.u-strasbg.fr/pub/cats/B/vsx/vsx.dat.gz"
   WGET_LOCAL_COMMAND="wget -O $TMP_OUTPUT.gz --timeout=120 --tries=2 http://scan.sai.msu.ru/~kirx/catalogs/compressed/vsx.dat.gz"
   UNPACK_COMMAND="gunzip $TMP_OUTPUT.gz"
  fi
  if [ "$FILE_TO_UPDATE" == "lib/catalogs/asassnv.csv" ];then
   TMP_OUTPUT="asassnv.csv"
   WGET_COMMAND="wget -O $TMP_OUTPUT --timeout=120 --tries=2 --no-check-certificate https://asas-sn.osu.edu/variables/catalog.csv"
   WGET_LOCAL_COMMAND="wget -O $TMP_OUTPUT --timeout=120 --tries=2 http://scan.sai.msu.ru/~kirx/catalogs/asassnv.csv"
   UNPACK_COMMAND=""
  fi
  if [ -z "$WGET_COMMAND" ];then
   echo "ERROR WGET_COMMAND is not set" >> /dev/stderr
   exit 1
  fi
  if [ -z "$WGET_LOCAL_COMMAND" ];then
   echo "ERROR WGET_LOCAL_COMMAND is not set" >> /dev/stderr
   exit 1
  fi
  if [ -z "$TMP_OUTPUT" ];then
   echo "ERROR TMP_OUTPUT is not set" >> /dev/stderr
   exit 1
  fi
  
  
  # First try to download a catalog from the mirror
  echo "$WGET_LOCAL_COMMAND" >> /dev/stderr
  $WGET_LOCAL_COMMAND
  if [ $? -ne 0 ];then
   # if that failed, try to download the catalog from the original link
   echo "$WGET_COMMAND" >> /dev/stderr
   $WGET_COMMAND  
   if [ $? -ne 0 ];then
    echo "ERROR running wget" >> /dev/stderr
    if [ -f "$TMP_OUTPUT" ];then
     rm -f "$TMP_OUTPUT"
    fi
    exit 1
   fi
   #
  fi # if that failed
  # If we are still here, we downloaded the catalog, one way or the other
  if [ ! -z "$UNPACK_COMMAND" ];then
   $UNPACK_COMMAND
   if [ $? -ne 0 ];then
    echo "ERROR running $UNPACK_COMMAND" >> /dev/stderr
    if [ -f "$TMP_OUTPUT" ];then
     rm -f "$TMP_OUTPUT"
    fi
    exit 1
   fi
  fi
  if [ ! -s "$TMP_OUTPUT" ];then
   echo "ERROR: $TMP_OUTPUT is EMPTY!"  >> /dev/stderr
   if [ -f "$TMP_OUTPUT" ];then
    rm -f "$TMP_OUTPUT"
   fi
   exit 1
  fi
  mv -v "$TMP_OUTPUT" "$FILE_TO_UPDATE" && touch "$FILE_TO_UPDATE"
  echo "Successfully updated $FILE_TO_UPDATE"
 #else
 # echo "No need to update $FILE_TO_UPDATE" >> /dev/stderr
 fi

done

### Check if the  Bright  Star  Catalogue  (BSC) has been downloaded
if [ ! -s "lib/catalogs/bright_star_catalog_original.txt" ] || [ ! -s "lib/catalogs/brightbright_star_catalog_radeconly.txt" ] ;then
 echo "Downloading the Bright Star Catalogue"
 # The CDS link is down
 #curl --silent ftp://cdsarc.u-strasbg.fr/pub/cats/V/50/catalog.gz | gunzip > lib/catalogs/bright_star_catalog_original.txt
 # Changed to local copy
 curl --silent http://scan.sai.msu.ru/~kirx/data/bright_star_catalog_original.txt.gz | gunzip > lib/catalogs/bright_star_catalog_original.txt
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
    echo "TEST ERROR: $MAG" >> /dev/stderr
    continue
   fi
   # Make sure we have the proper format
   MAG=`echo "$MAG" | awk '{printf "%.2f", $1}'`
   TEST=`echo "$MAG > 4.0" | bc -ql`
   if [ $TEST -eq 1 ];then
    continue
   fi
   echo "${STR:75:2}:${STR:77:2}:${STR:79:4} ${STR:83:3}:${STR:86:2}:${STR:88:2}" 
  done > lib/catalogs/brightbright_star_catalog_radeconly.txt
 else
  echo "ERROR downloading/unpacking the Bright Star Catalogue"
 fi
fi

