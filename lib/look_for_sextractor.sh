#!/usr/bin/env bash

echo -n "Checking write permissions for the current directory ($PWD)...  "

touch testfile$$.tmp
if [ $? -eq 0 ];then
 rm touch testfile$$.tmp &>/dev/null
 echo "Ok"
else
 echo "ERROR!
Please make sure you have write permissions for the current directory.

Maybe you need something like:
sudo chown -R $USER $PWD"
 exit 1
fi

echo -n "Checking the local copy of SExtractor...  "
if [ ! -f lib/bin/sex ];then
 echo "Warning: cannot find a local copy of SExtractor..."
else
 echo -n "found. "
fi
if [ ! -x lib/bin/sex ];then
 echo -n "Warning: the local copy of SExtractor is not an exacuable file Trying to fix... "
 chmod +x lib/bin/sex
 if [ ! -x lib/bin/sex ];then
  echo "Warning: the local copy of SExtractor in lib/bin/sex is not an executable file
 Something is very-very wrong!"
 else
  echo "fixed. "
 fi
fi

echo -n "Looking for SExtractor to be used for image processing...  "

command -v sex &>sex_path.tmp && cat sex_path.tmp && rm -f sex_path.tmp && exit 0

 echo "ERROR!"
 echo " "
 echo "Can't find a SExtractor executable in \$PATH"
 echo " "
cat sex_path.tmp

rm -f sex_path.tmp

exit 1
