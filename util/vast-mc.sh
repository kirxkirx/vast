#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

key=$1
case $key in
 -h | --h | --help )
 echo "VaST star match calculator."
 echo "This small program analyze vast_image_details.log and calculate"
 echo "average amount of stars, detected on all images,"
 echo "average amount of stars, matched on all images and"
 echo "average percent of matched stars."
 echo "Also it can calculate matching persent for given star"
 echo "Usage:"
 echo "vast-mc [log-file-name]"
 echo "if name of log-file is missing, vast-mc trying to analyze"
 echo "vast_image_detals.log in current directory"
 echo "with -n [number] it calculate matching persent for star # [number]"
 echo "vast photometry file out[number].dat must be placed in current directory"
 exit 1;;
 "")
 WantToCalcStarStat=N
 filename="vast_image_details.log";;
 -n | --n )
 filename="vast_image_details.log"
 WantToCalcStarStat=Y
 StarNumber=$2;;
 * )
 filename=$key
 case $2 in
   -n | --n )
    WantToCalcStarStat=Y
    StarNumber=$3;;
   "")
    WantToCalcStarStat=N
 esac ;;
esac

if [ "$WantToCalcStarStat" = Y ];
  then
    StarFileName="out$StarNumber.dat"
    if [ -e $StarFileName ];
      then
        TotalImages=`grep -v status=ERROR $filename |wc -l`
        TotalMeasurements=`cat $StarFileName|wc -l`
        #Pers=$(echo "scale=2; 100*$TotalMeasurements/$TotalImages"|bc -ql)
        Pers=$(echo "$TotalMeasurements $TotalImages" | awk '{printf "%.2f", 100*$1/$2}')
        echo "Matching persent of star #$StarNumber - $Pers"
        exit
     else
        echo "Star #$StarNumber does not exist in this session."
	exit 1
    fi
fi

if [ -e $filename ] ;
  then
    grep -v status=ERROR $filename \
    |awk '{d +=$13; m +=$15} END {AD=d/NR; AM=m/NR; AMP=100*(AM/AD);\
     print "Average stars detected per image: "AD "\n" "Average stars matched: "AM " ("AMP" %)"}'
  else
    echo "file $filename does not exist"
  exit 1
fi
