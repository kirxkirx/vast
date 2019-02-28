#!/usr/bin/env bash

echo "Creating vast_image_details.log ... " >> /dev/stderr

if [ -f vast_image_details.log ];then
 rm -f vast_image_details.log
fi

for i in image*.log ;do 
 if [ ! -f $i ];then
  echo "ERROR in $0 -- cannot open file $i"
  exit 1
 fi
 cat $i >> vast_image_details.log
 rm -f $i 
done
