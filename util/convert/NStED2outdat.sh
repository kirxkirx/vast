#!/usr/bin/env bash

for TBLFILENAME in *_lc.tbl ;do

 OUTFILENAME="out"`basename $TBLFILENAME "_lc.tbl"`.dat

 echo -n "Converting $TBLFILENAME to $OUTFILENAME "

 if [ ! -f $OUTFILENAME ];then

  RA=`grep RA $TBLFILENAME |grep -v Right |awk '{print $3}'`
  Dec=`grep Dec $TBLFILENAME |grep -v Declination |awk '{print $3}'`

  HEADER=1
  while read HJD Relative_HJD MAG MERR ;do
   if [ "$Relative_HJD" = "HJD|" ];then
    read MUSOR MUSOR
    read MUSOR MUSOR
    read HJD Relative_HJD MAG MERR
    HEADER=0
   fi
   if [ $HEADER -eq 0 ];then
    echo $HJD $MAG $MERR $RA $Dec 5.0 $TBLFILENAME  
   fi
  done < $TBLFILENAME > $OUTFILENAME
 
  echo Ok
 
 else
  echo "File already exist"
 fi
 
done
