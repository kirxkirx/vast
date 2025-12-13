#!/usr/bin/env bash
#
# Convert all files in a specified directory to the VaST lightcurve 
# format *assuming* all files in the directory are ASCII lightcurves 
# in the "JD mag err" format.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

###################################
SCRIPTNAME=`basename $0`
###################################
# Check input
if [ -z $1 ];then
 echo "The script $SCRIPTNAME will convert all files in a specified directory to the VaST lightcurve
format *assuming* all files in the directory are ASCII lightcurves in the \"JD mag err\" format.
The coma-separated \"JD,mag,err\" format is also acceptable, additional columns after \"err\" are 
tolerated, but not used. If a value in \"JD\" coumn is less than 2400000.5, the script will assume
this is an MJD and add 2400000.5 to it to convert the date to JD.
 
Usage: $0 /path/to/directory/with/ascii/lightcurves"
 exit 1
fi
ASCII_LC_DIR="$1"
if [ ! -d "$ASCII_LC_DIR" ];then
 echo "ERROR: the specified path $ASCII_LC_DIR is no a directory"
 exit 1
fi
###################################
# Clean-up the current directory so new lightcurve files will not mix with the old ones if there are any
util/clean_data.sh
###################################
# Run the conversion for each file in the dir
for ASCII_LC_FILE in "$ASCII_LC_DIR"/* ;do
 if [ ! -f "$ASCII_LC_FILE" ];then
  echo "WARNING: $ASCII_LC_FILE is not a regular file and will not be converted!"
  continue
 fi
 file "$ASCII_LC_FILE" | grep "ASCII text"
 if [ $? -ne 0 ];then
  echo "WARNING: $ASCII_LC_FILE is not an ASCII text and will not be converted!"
  continue
 fi
 # Determine if this is a csv or space-separated file
 tail -n3 "$ASCII_LC_FILE" | grep ',' -q
 if [ $? -eq 0 ];then
  #FS="FS=,"
  FS="-F ','"
 else
  FS=" "
 fi
 # Make-up an out*.dat name for the output file
 NEW_NAME=`basename "$ASCII_LC_FILE" .dat`
 NEW_NAME=`basename "$NEW_NAME" .txt`
 NEW_NAME=`basename "$NEW_NAME" .csv`
 NEW_NAME="${NEW_NAME//./_}"
 NEW_NAME=out_"$NEW_NAME".dat
 # Test if this is an HCV data file 
 grep -q 'hst_' "$ASCII_LC_FILE"
 if [ $? -eq 0 ];then
  # This is an HCV data file
  cat "$ASCII_LC_FILE" | grep -v 'nan' | awk $FS '{ jd=$1 ; mag=$2 ; err=$3; CI=$4 ; RA=$5; DEC=$6; filename=$7; if ( jd<2400000.5 )jd=jd+2400000.5; printf "%.6f %7.4f %.4f %.7f %.7f %.7f %s\n", jd , mag, err, RA, DEC, CI, filename}' | grep -v "#" | grep -v "%" > "$NEW_NAME"
  # All this is the old stuff
  ## corrected LC
  ##cat "$ASCII_LC_FILE" | awk '{ jd=$1 ; mag=$3 ; err=$4; filename=$5; if ( jd<2400000.5 )jd=jd+2400000.5; printf "%.6f %7.4f %.4f 0.1 0.1 1.0 %s\n", jd , mag, err, filename}' $FS | grep -v "#" | grep -v "%" > "$NEW_NAME"
  ## original LC
  ##cat "$ASCII_LC_FILE" | awk '{ jd=$1 ; mag=$2 ; err=$4; filename=$5; if ( jd<2400000.5 )jd=jd+2400000.5; printf "%.6f %7.4f %.4f 0.1 0.1 1.0 %s\n", jd , mag, err, filename}' $FS | grep -v "#" | grep -v "%" > "$NEW_NAME"
 else
  # A generic parser
  ### Try to guess if the file includes numbers in exponential form
  #head -n10 "$ASCII_LC_FILE" | head -n +2 | awk '{print $2" "$3}' $FS | grep -q 'e-0'
  head -n10 "$ASCII_LC_FILE" | head -n +2 | awk $FS '{print $2" "$3}' | grep -q 'e-0'
  if [ $? -eq 0 ];then
   # Write lightcurve in the exponential format
   #cat "$ASCII_LC_FILE" | awk '{ jd=$1 ; mag=$2 ; err=$3; if ( jd<2400000.5 )jd=jd+2400000.5; printf "%.6f %g %g 0.1 0.1 1.0 none\n", jd , mag, err}' $FS | grep -v "#" | grep -v "%" > "$NEW_NAME"
   cat "$ASCII_LC_FILE" | awk $FS '{ jd=$1 ; mag=$2 ; err=$3; if ( jd<2400000.5 )jd=jd+2400000.5; printf "%.6f %g %g 0.1 0.1 1.0 none\n", jd , mag, err}' | grep -v "#" | grep -v "%" > "$NEW_NAME"
  else
   # Write lightcurve in the usual fixed-point format
   #cat "$ASCII_LC_FILE" | awk '{ jd=$1 ; mag=$2 ; err=$3; if ( jd<2400000.5 )jd=jd+2400000.5; printf "%.6f %7.4f %.4f 0.1 0.1 1.0 none\n", jd , mag, err}' $FS | grep -v "#" | grep -v "%" > "$NEW_NAME"
   cat "$ASCII_LC_FILE" | awk $FS '{ jd=$1 ; mag=$2 ; err=$3; if ( jd<2400000.5 )jd=jd+2400000.5; printf "%.6f %7.4f %.4f 0.1 0.1 1.0 none\n", jd , mag, err}' | grep -v "#" | grep -v "%" > "$NEW_NAME"
  fi # exp. form
 fi
done

# Special trap to remove the directory index if present
if [ -f out_index.dat ];then
 rm -f out_index.dat
fi
