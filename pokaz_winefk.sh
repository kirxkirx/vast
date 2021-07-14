#!/usr/bin/env bash 
#################################
# This script will convert outXXXX.dat file to the WinEfk-readable format and will start WinEfk using wine.
# Please enter the path to WinEfk:
PATH_TO_WINEFK="$HOME/winefk"
#
# After WinEfk is started, open "POKAZs" file in the WinEfk directory or win-outXXXX.dat
# With the latest version of WinEfk the lightcurve file will be opened automatically.
#
#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################
#################################
# Check if $PATH_TO_WINEFK exist
if [ ! -d "$PATH_TO_WINEFK" ];then
 echo "ERROR: Can't locate WinEfk!"
 echo "Directory $PATH_TO_WINEFK doesn't exist!"
 echo " "
 echo "Download WinEfk from here:"
 echo "ftp://scan.sai.msu.ru/uploads/a/"
 echo "or from here"
 echo "http://vgoray.front.ru/software/"
 echo "unpack it to $PATH_TO_WINEFK"
 echo "You'll need wine to run WinEfk..."
 exit
fi
#################################
# Check if lightcurve file was supplied ($1) exist
if [ -z $1 ];then
 echo "ERROR: no lightcurve file name is supplied!"
 echo " "
 echo "Usage:  $0 outNNNN.dat"
 exit
fi
#################################
# Check if wine is available
if ! command -v wine &>/dev/null ;then
 echo "ERROR: can't find wine in PATH:"
 echo $PATH
 echo "You'll probably need wine to run WinEfk...

Or you may try to use the web-based period search insted:
press 'L' in the lightcurve inspection window or manually run ./pokaz_laflerkinman.sh"
 exit
fi
#################################
# Do the actual work
export LC_ALL=ru_RU.UTF-8
lib/formater_out_wfk $1 > "$PATH_TO_WINEFK"/POKAZ
cd $PATH_TO_WINEFK
sort -bn POKAZ > POKAZs
rm -f POKAZ
cp POKAZs win-`basename $1`
echo "Writing file in the WinEfk format: win-"`basename $1` 1>&2
echo "Open file POKAZs or win-"`basename $1`" in the WinEfk direcory when the WinEfk window will appear." 1>&2
echo "If the latest version of WinEfk is used - the file will be opened automatically." 1>&2
wine winefk.exe POKAZs &>/dev/null
