#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# lib/find_candidates_MAG_SIGMA_MAG.sh 
GDE=`dirname $PWD/save.sh`
MY=`basename $GDE`
if [ "$MY" = "util" ];then
 cd ..
fi
if [ ! -d selected ];then
mkdir selected
fi
rm -f selected/*
if [ ! -f data.m_sigma ];then
 lib/find_candidates_MAG_SIGMA_MAG.sh
fi
lib/m_sigma_bin > m_sigma_bin.tmp
while read A B C D NAME ;do
 cp $NAME selected/
done < m_sigma_bin.tmp
rm -f m_sigma_bin.tmp
