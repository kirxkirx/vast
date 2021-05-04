#!/usr/bin/env bash
#
# Convert an ASCII file with the unix end of line
# to Window$ end of line.
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
 echo -ne "$STRING\r\n"
done < $INPUTFILE > unix2windows.tmp
mv unix2windows.tmp $INPUTFILE
echo "done"
