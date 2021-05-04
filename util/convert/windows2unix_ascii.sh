#!/usr/bin/env bash
#
# Convert an ASCII file with the Window$ end of line
# to Unix end of line.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ -z $1 ];then
 echo Usage: $0 asciifile.txt
 exit
fi
INPUTFILE=$1
echo -n "Converting file $INPUTFILE ... "
while read STRING ;do
 echo $STRING | sed -e 's/\r/ /'
done < $INPUTFILE > unix2windows.tmp
mv unix2windows.tmp $INPUTFILE
echo "done"
