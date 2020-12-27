#!/usr/bin/env bash

if [ -z "$1" ];then
 echo "Usage: $0 out01234.dat"
 exit 1
fi

INPUT_VAST_LIGHTCURVE="$1"

if [ ! -f "$INPUT_VAST_LIGHTCURVE" ];then
 echo "ERROR: cannot find the lightcurve file $INPUT_VAST_LIGHTCURVE"
 exit 1
fi
if [ ! -s "$INPUT_VAST_LIGHTCURVE" ];then
 echo "ERROR: the lightcurve file $INPUT_VAST_LIGHTCURVE is empty"
 exit 1
fi
# Check that the lightcurve is readable
util/cute_lc "$INPUT_VAST_LIGHTCURVE" > /dev/null
if [ $? -ne 0 ];then
 echo "ERROR: parsing the lightcurve file $INPUT_VAST_LIGHTCURVE"
 exit 1
fi

# Check that the magnitudes are reasonable
if [ 1 -ne `util/cute_lc "$INPUT_VAST_LIGHTCURVE" | awk '{print $2}' | util/colstat 2>/dev/null | grep 'MEAN=' | awk '{if ( $2 > 5 ) print 1 ;else print 0 }'` ];then
 echo "The magnitudes seem too small! Are you forgetting to convert the instrumental magnitudes to the absolute scale?"
 exit 1
fi
# Check that the magnitudes are reasonable
if [ 1 -ne `util/cute_lc "$INPUT_VAST_LIGHTCURVE" | awk '{print $2}' | util/colstat 2>/dev/null | grep 'MEAN=' | awk '{if ( $2 < 25 ) print 1 ;else print 0 }'` ];then
 echo "The magnitudes seem too large!"
 exit 1
fi

# Check that the time system is UTC
if [ ! -s vast_summary.log ];then
 echo "ERROR: cannot find vast_summary.log to determine the JD time system, assuming UTC"
 SOFTWARE_VERSION=`./vast --version 2>/dev/null`
else
 grep --quiet 'JD time system (TT/UTC/UNKNOWN): UTC' vast_summary.log
 if [ $? -ne 0 ];then
  echo "ERROR: cannot confirm that the JD time system is UTC from vast_summary.log"
  exit 1
 fi
 SOFTWARE_VERSION=`grep 'Software: ' vast_summary.log  | awk '{print $2" "$3}'`
fi

# Get the observing date for the header
JD_FIRST_OBS=`util/cute_lc "$INPUT_VAST_LIGHTCURVE" | head -n1 | awk '{print $1}'`
JD_LAST_OBS=`util/cute_lc "$INPUT_VAST_LIGHTCURVE" | tail -n1 | awk '{print $1}'`
UNIXTIME_FIRST_OBS=`util/get_image_date "$JD_FIRST_OBS" 2>/dev/null | grep 'Unix Time' | awk '{print $3}'`
DATE_FOR_AAVSO_HEADER_FIRST_OBS=`LANG=C date -d @"$UNIXTIME_FIRST_OBS" +"%d%b%Y"`
DATE_FOR_AAVSO_MESSAGE_SUBJECT_FIRST_OBS=`LANG=C date -d @"$UNIXTIME_FIRST_OBS" +"%d %B %Y"`

# Get the exposure time for the header
if [ -s vast_image_details.log ];then
 #MEDIAN_EXPOSURE_TIME_SEC=`cat vast_image_details.log | awk '{print $2}' FS='exp=' | awk '{print $1}' | util/colstat 2> /dev/null | grep 'MEDIAN=' | awk '{printf "%.0f\n", $2}'`
 MEDIAN_EXPOSURE_TIME_SEC=`cat vast_image_details.log | awk -F 'exp=' '{print $2}' | awk '{print $1}' | util/colstat 2> /dev/null | grep 'MEDIAN=' | awk '{printf "%.0f\n", $2}'`
else
 echo "WARNING: cannot get the exposure time from vast_image_details.log"
fi

# the default filter name should be manually edited by the user!
FILTER="X"
# the default star name should be manually edited by the user!
VARIABLE_STAR_NAME="XX Xxx"
# but we can try to guess satre and filter name from the CBA file, if present
if [ -s CBA_previously_used_header.txt ];then
 echo "Importing the variable star info from CBA_previously_used_header.txt" >> /dev/stderr
 VARIABLE_STAR_NAME=`cat CBA_previously_used_header.txt | grep '# Variable: ' | awk -F '# Variable: ' '{print $2}'`
 FILTER=`cat CBA_previously_used_header.txt | grep '# Filter: ' | awk -F '# Filter: ' '{print $2}'`
fi

# if automated magnitude calibration was performed,
# there should be a plate-solved FITS corresonding to the reference image
# note that we checked above that vast_summary.log exist
REFERENCE_IMAGE=`grep 'Ref.  image:' vast_summary.log | awk '{print $6}'`
PLATE_SOLVED_REFERENCE_IMAGE=wcs_`basename $REFERENCE_IMAGE`
if [ -f "$PLATE_SOLVED_REFERENCE_IMAGE" ];then
 echo "Found a plate-solved reference image $PLATE_SOLVED_REFERENCE_IMAGE
Trying to automatically ID the star $INPUT_VAST_LIGHTCURVE"
 STAR_NUMBER=`echo "${INPUT_VAST_LIGHTCURVE/out/}"`
 STAR_NUMBER=`echo "${STAR_NUMBER/.dat/}"`
 # '| while read A ;do echo $A ;done' is to remove the trailing white space if the variable name is from GCVS
 AUTOMATIC_VARIABLE_STAR_NAME=`util/identify_justname.sh $INPUT_VAST_LIGHTCURVE | grep -A100 'Star:' | grep -v "$STAR_NUMBER  " | tail -n1 | while read A ;do echo $A ;done` 
 if [ ! -z "$AUTOMATIC_VARIABLE_STAR_NAME" ];then
  echo "Automatically setting the variable star name $AUTOMATIC_VARIABLE_STAR_NAME"
  VARIABLE_STAR_NAME="$AUTOMATIC_VARIABLE_STAR_NAME"
 else
  echo "Something wen wrong while trying to ID the star, keeping the name $VARIABLE_STAR_NAME"
 fi
fi

# the default obscode should be changed by the user
AAVSO_OBSCODE="SKA"
# the previous AAVSO file header should contain the correct OBSCODE
if [ -s AAVSO_previously_used_header.txt ];then
 AAVSO_OBSCODE=`grep '#OBSCODE=' AAVSO_previously_used_header.txt | awk -F'=' '{print $2}'`
 if [ -z "$AAVSO_OBSCODE" ];then
  echo "ERROR: cannot get OBSCODE from AAVSO_previously_used_header.txt"
  AAVSO_OBSCODE="XXX"
 fi
fi

echo "#TYPE=EXTENDED
#OBSCODE=$AAVSO_OBSCODE
#SOFTWARE=$SOFTWARE_VERSION
#DELIM=,
#DATE=JD
#NAME,DATE,MAG,MERR,FILT,TRANS,MTYPE,CNAME,CMAG,KNAME,KMAG,AMASS,GROUP,CHART,NOTES" > AAVSO_previously_used_header.txt

cp AAVSO_previously_used_header.txt AAVSO_report.txt
util/cute_lc "$INPUT_VAST_LIGHTCURVE" | while read JD MAG ERR ;do
      ##NAME,DATE,MAG,MERR,FILT,TRANS,MTYPE,CNAME,CMAG,KNAME,KMAG,AMASS,GROUP,CHART,NOTES
      #SS CYG,2450702.1234,11.235,0.003,B,NO,STD,ENSEMBLE,na,105,10.593,1.561,1,X16382L,na
 echo "$VARIABLE_STAR_NAME,$JD,$MAG,$ERR,$FILTER,NO,STD,ENSEMBLE,na,na,na,na,1,na,na"
done >> AAVSO_report.txt
if [ $? -ne 0 ];then
 echo "Something went WRONG with the lightcurve conversion!"
 exit 1
fi

 echo "The stub report is written to AAVSO_report.txt
You may need to edit the header before submitting the file to the AAVSO!"

# Try to find a sensible editor
if [ -z "$EDITOR" ];then
 for EDITOR_TO_TRY in joe nano vim emacs ;do
  command -v $EDITOR_TO_TRY &>/dev/null
  if [ $? -eq 0 ];then
   EDITOR=joe
   break
  fi
 done
fi

# Manually edit the report
if [ ! -z "$EDITOR" ];then
 $EDITOR AAVSO_report.txt
fi

# Update the variable star name as the user might have changed it
VARIABLE_STAR_NAME=`cat AAVSO_report.txt | grep -v \# | awk -F',' '{print $1}' | head -n1`

if [ -z "$VARIABLE_STAR_NAME" ];then
 echo "ERROR in AAVSO_report.txt : cannot find the variable star name"
 exit 1
fi

# Check that this file contains only observations of this one star
# (i.e. there are no lines where the star name is misspelled)
N_LINES_STARNAME=`grep -c "$VARIABLE_STAR_NAME" AAVSO_report.txt`
N_LINES_MEASUREMENTS=`cat AAVSO_report.txt | grep -v \# | grep -c ','`
if [ $N_LINES_STARNAME -ne $N_LINES_MEASUREMENTS ];then
 echo "ERROR in AAVSO_report.txt : N_LINES_STARNAME != N_LINES_MEASUREMENTS : $N_LINES_STARNAME != $N_LINES_MEASUREMENTS"
 exit 1
fi


VARIABLE_STAR_NAME_NO_WHITESPACES="${VARIABLE_STAR_NAME// /_}"

# Filter name
FILTER_NAME=`cat AAVSO_report.txt | grep -v \# | awk -F',' '{print $5}' | head -n1`
if [ -z "$FILTER_NAME" ];then
 echo "ERROR in AAVSO_report.txt : cannot find the filter name"
 exit 1
fi
# Check that this file contains only observations in one filter
# (i.e. there are no lines where the filter name is misspelled)
N_LINES_FILTERNAME=`grep -c ",$FILTER_NAME," AAVSO_report.txt`
N_LINES_MEASUREMENTS=`cat AAVSO_report.txt | grep -v \# | grep -c ','`
if [ $N_LINES_FILTERNAME -ne $N_LINES_MEASUREMENTS ];then
 echo "ERROR in AAVSO_report.txt : N_LINES_FILTERNAME != N_LINES_MEASUREMENTS : $N_LINES_FILTERNAME != $N_LINES_MEASUREMENTS"
 exit 1
fi


FINAL_OUTPUT_FILENAME=AAVSO_"$VARIABLE_STAR_NAME_NO_WHITESPACES"_"$DATE_FOR_AAVSO_HEADER_FIRST_OBS"_"$FILTER_NAME"_measurements.txt
echo "Renaming the final report file:"
cp -v AAVSO_report.txt "$FINAL_OUTPUT_FILENAME"
grep '# ' AAVSO_report.txt > AAVSO_previously_used_header.txt

