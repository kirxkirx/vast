#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Parse the command line arguments
if [ -z $2 ];then 
 FOV=40
 echo "Field of view was not set. Retreating to a default value $FOV'..."
else
 FOV=$2
fi
     
if [ -z $1 ]; then
 echo "Usage: $0 outNUMBER.dat"
 echo "or"
 echo "       $0 outNUMBER.dat FIELD_OF_VIEW_IN_ARCMIN"
 exit
fi
LIGHTCURVEFILE=$1


rm -f coordinates.tmp
N=0
while read JD MAG MERR X Y APP FITSFILE ;do
 util/wcs_image_calibration.sh $FITSFILE $FOV
 WCS_IMAGE_NAME=wcs_`basename $FITSFILE`
 SEXTRACTOR_CATALOG_NAME="$WCS_IMAGE_NAME".cat

 #N=`echo "$N+1"|bc -q`
 N=$((N+1))
 if [ $N -gt 30 ];then
  break
 fi
 echo "*** Image $N $WCS_IMAGE_NAME ***"

 RADEC=`lib/find_star_in_wcs_catalog $X $Y < $SEXTRACTOR_CATALOG_NAME`
 #echo "------------------- $RADEC"
 RADEC_CORRECTED=`util/astrometric_correction.sh $SEXTRACTOR_CATALOG_NAME $RADEC`
 #echo "util/astrometric_correction.sh $SEXTRACTOR_CATALOG_NAME $RADEC"
 echo $RADEC_CORRECTED >> coordinates.tmp 
done < $LIGHTCURVEFILE
cat coordinates.tmp

