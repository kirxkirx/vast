#!/usr/bin/env bash
#
# This script will create a catalog of detected stars with teir equatorial coordinates
#

#REF_IMAGE=`grep "Ref.  image:" vast_summary.log |awk '{print $6}'`
#REF_IMAGE_CATALOG=`util/wcs_image_calibration.sh $REF_IMAGE |grep ".cat" | awk '{print $2}'`
#cat $REF_IMAGE_CATALOG | awk '{printf "%05d  %.5f %.5f ",$1,$2,$3}' | while read N RA DEC ;do
# STR=`grep out"$N".dat data.m_sigma`
# MAG=`echo "$STR" | awk '{print $1}'`
# SIGMA=`echo "$STR" | awk '{print $2}'`
# X=`echo "$STR" | awk '{print $3}'`
# Y=`echo "$STR" | awk '{print $4}'`
# if [ $? ] ;then
#  echo "$MAG $SIGMA  $N  $RA $DEC $X $Y"
# fi
#done | sort -n > vast_star_catalog.log
   

while read MAG SIGMA X Y LIGHTCURVEFILE ;do
 echo -n "$MAG $SIGMA  "
 util/identify_for_catalog.sh $LIGHTCURVEFILE $1 |grep Star -A 1 |grep -v Star > tmp_util_star_catalog_sh$$.dat
 if [ $? ] ;then
  cat tmp_util_star_catalog_sh$$.dat
 fi
done < data.m_sigma |grep -v "\-\-" | sort -n > vast_star_catalog.log
rm -f tmp_util_star_catalog_sh$$.dat
