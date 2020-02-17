#!/usr/bin/env bash

# Default values
SEARCH_AREA_RADIUS_DEGREES=0.5
INDIVIDUAL_OBJECT_SEARCH_RADIUS_ARCMIN=0.1
R2_BRIGHTEST_STARS_IN_USNOB1=13.0
R2_FAINTEST_STARS_IN_USNOB1=19.0

CATALINA_SERVER_URL="http://nunuku.caltech.edu/cgi-bin/getcssconedb_release_img.cgi"
#CATALINA_SERVER_URL="http://nunuku.cacr.caltech.edu/cgi-bin/getcssconedb_release_img.cgi"

if [ -z $2 ];then
 echo "This script will search CSS photometric database around a specified position,
USNO-B1.0 catalog is used as a proxy.

Note that the script works very slowly! It may take hours to download data for a large sky area.

 Script usage: $0 01:02:03.00 04:05:06.0 [0.5]" 
 exit
fi

# Clean old files
util/clean_data.sh
rm all_in_one$$.dat center$$.txt vizquerry$$.txt &>/dev/null 
for i in out*.dat ;do rm -f $i &>/dev/null ;done

#
TARGET_AREA=`lib/hms2deg $1 $2`
echo ${TARGET_AREA//'\n'/} > center$$.txt
#

if [ -z $3 ];then
 # Single-star mode
 echo "A B 0.0 $1 $2 15" > vizquerry$$.txt
else
 # Cone search mode
 # Querry VizieR
 echo -n "Querry USNO-B1 through VizieR... "
 lib/vizquery -mime=text -source=USNO-B1 -out.max=999999 -out.add=_1 -out.add=_r -out.form=mini -out=RAJ2000,DEJ2000,R2mag -sort=_r -c.rd=$SEARCH_AREA_RADIUS_DEGREES -list=center$$.txt 2>/dev/null |grep -v \# | grep -v "_" | grep -v "\-\-\-" |grep -v "sec"  |grep -v "RAJ" |grep -v "R" > vizquerry$$.txt
 echo "Done"
 echo "######################################################"
 cat vizquerry$$.txt
 echo "######################################################"
fi

cat vizquerry$$.txt | while read A B RAD RA DEC R ;do if [ -z $R ];then continue ;fi 
 TEST=`echo "$R<$R2_FAINTEST_STARS_IN_USNOB1" | bc -ql`
 if [ $TEST -eq 0 ];then
  continue
 fi
 TEST=`echo "$R>$R2_BRIGHTEST_STARS_IN_USNOB1" | bc -ql`
 if [ $TEST -eq 0 ];then
  continue
 fi

 # Querry Catalina
 echo -n "Querry Catalina: $RA $DEC ... "
 CSV_FILE_LINK=`curl --silent --max-time 10 --data "RA=$RA&Dec=$DEC&Rad=$INDIVIDUAL_OBJECT_SEARCH_RADIUS_ARCMIN&IMG=nun&DB=photcat&.submit=Submit&OUT=csv&SHORT=short" $CATALINA_SERVER_URL | grep ">download<" | awk '{print $1}' FS='>download<' | awk '{print $2}' FS='href='`
 # Download the Catalina result
 curl --silent --max-time 10 "$CSV_FILE_LINK" | grep -v MasterID | awk '{printf "%.5f %.2f %.2f %d %s\n",$6+2400000.5,$2,$3,$7,$1}' FS=',' >> all_in_one$$.dat
 echo "OK"

done

# Prepare lightcurves in VaST format
echo -n "Converting lightcurves to VaST format... "
while read JD MAG MAGERR FLAG ID ;do
 echo "$JD $MAG $MAGERR 0.0 0.0 1.0 $FLAG"_"$ID" >> out"$ID".dat
done < all_in_one$$.dat
echo "Done"

rm all_in_one$$.dat center$$.txt vizquerry$$.txt

