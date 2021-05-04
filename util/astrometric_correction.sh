#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

RA=$2
DEC=$3

# Make up names
CATALOG_NAME=$1
VIZQUERY_RESULTS_NAME="$CATALOG_NAME".vizquery

# If this is the first time we vizquery that file
if [ ! -f $VIZQUERY_RESULTS_NAME ];then
 # Querry VizieR
 cat $CATALOG_NAME | awk '{print $2" "$3}' > a.txt

 lib/vizquery -mime=text -source=USNO-B1 -out.max=1 -out.add=_1,_2,_x,_y -out.form=mini -out=RAJ2000,DECJ2000 -sort=B2mag -list=a.txt -c.rs=15 |grep -v \# | grep -v "_" | grep -v "\-\-\-" | while read RA DEC DX DY REST ;do
  if [ ! -z $RA ];then
   echo $RA $DEC " $DX $DY" | awk '{printf "%10.6f %+10.6f %+6.2f %+6.2f\n",$1,$2,$3,$4}'
  fi
 done > $VIZQUERY_RESULTS_NAME
fi

lib/astrometry/astrometry_spline $RA $DEC < $VIZQUERY_RESULTS_NAME