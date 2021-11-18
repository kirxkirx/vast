#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

echo -n "Checking write permissions for the current directory ($PWD)...  "

touch testfile$$.tmp
if [ $? -eq 0 ];then
 rm -f testfile$$.tmp &>/dev/null
 echo "OK"
else
 echo "ERROR!
Please make sure you have write permissions for the current directory.

Maybe you need something like:
sudo chown -R $USER $PWD"
 exit 1
fi

# Do nothing if there is a system-wide installation of SExtractor
command -v sex &>/dev/null
if [ $? -eq 0 ];then
 echo "Found a system-wide installation of SExtractor"
 exit 0
fi

echo -n "Checking the local copy of SExtractor...  "
if [ ! -f lib/bin/sex ];then
 echo "WARNING: cannot find a local copy of SExtractor..."
else
 echo -n "found. "
 # make sure SExtractor is in the PATH for the next test
 export PATH=$PATH:lib/bin/
fi
if [ ! -x lib/bin/sex ];then
 echo -n "WARNING: the local copy of SExtractor is not an exacuable file Trying to fix... "
 chmod +x lib/bin/sex
 if [ ! -x lib/bin/sex ];then
  echo "WARNING: the local copy of SExtractor in lib/bin/sex is not an executable file
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
