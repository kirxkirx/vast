#!/usr/bin/env bash
while read A B C D E F G H ;do 
 echo $A $B
 if [ ! -z $1 ];then
  if [ "$1" = "-9" ];then
   util/draw_stars_with_ds9.sh $F $G $H &>/dev/null
  fi
  if [ "$1" = "--ds9" ];then
   util/draw_stars_with_ds9.sh $F $G $H &>/dev/null
  fi
 else
  ./pgfv $F $G $H &>/dev/null 
 fi
done < candidates-transients.lst
