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
 echo "ERROR: cannot find vast_summary.log to determine the JD time system"
 exit 1
fi
grep --quiet 'JD time system (TT/UTC/UNKNOWN): UTC' vast_summary.log
if [ $? -ne 0 ];then
 echo "ERROR: cannot confirm that the JD time system is UTC from vast_summary.log"
 exit 1
fi

# Get the observing date for the header
JD_FIRST_OBS=`util/cute_lc "$INPUT_VAST_LIGHTCURVE" | head -n1 | awk '{printf "%.3lf", $1}'`
JD_LAST_OBS=`util/cute_lc "$INPUT_VAST_LIGHTCURVE" | tail -n1 | awk '{printf "%.3lf", $1}'`
UNIXTIME_FIRST_OBS=`util/get_image_date "$JD_FIRST_OBS" 2>/dev/null | grep 'Unix Time' | awk '{print $3}'`
DATE_FOR_CBA_HEADER_FIRST_OBS=`LANG=C date -d @"$UNIXTIME_FIRST_OBS" +"%d%b%Y"`
DATE_FOR_CBA_MESSAGE_SUBJECT_FIRST_OBS=`LANG=C date -d @"$UNIXTIME_FIRST_OBS" +"%d %B %Y"`

# Get the exposure time for the header
if [ -s vast_image_details.log ];then
 #MEDIAN_EXPOSURE_TIME_SEC=`cat vast_image_details.log | awk '{print $2}' FS='exp=' | awk '{print $1}' | util/colstat 2> /dev/null | grep 'MEDIAN=' | awk '{printf "%.0f\n", $2}'`
 MEDIAN_EXPOSURE_TIME_SEC=`cat vast_image_details.log | awk -F 'exp=' '{print $2}' | awk '{print $1}' | util/colstat 2> /dev/null | grep 'MEDIAN=' | awk '{printf "%.0f\n", $2}'`
else
 echo "WARNING: cannot get the exposure time from vast_image_details.log"
fi

if [ ! -s CBA_previously_used_header.txt ];then
 echo "# Variable: AM CVn
# Date: $DATE_FOR_CBA_HEADER_FIRST_OBS
# Comp star: 144_AAVSO_(V= 14.357 )
# Check star: 157_AAVSO_(V= 15.663 )
# Exp time (s): $MEDIAN_EXPOSURE_TIME_SEC s
# Filter: CV
# Observatory: Michigan State Campus Observatory
# East Lansing, MI, USA
# Observers: Kirill Sokolovsky
# Comments: Clear most of the night.
# JD              Var_Mag     Var_eMag" > CBA_previously_used_header.txt
fi
#cp CBA_previously_used_header.txt CBA_report.txt
grep '# Variable: ' CBA_previously_used_header.txt > CBA_report.txt
echo "# Date: $DATE_FOR_CBA_HEADER_FIRST_OBS" >> CBA_report.txt
grep '# Comp star: ' CBA_previously_used_header.txt >> CBA_report.txt
grep '# Check star: ' CBA_previously_used_header.txt >> CBA_report.txt
echo "# Exp time (s): $MEDIAN_EXPOSURE_TIME_SEC " >> CBA_report.txt
grep '# Filter: ' CBA_previously_used_header.txt >> CBA_report.txt
grep -A4 '# Observatory: ' CBA_previously_used_header.txt | grep '#' >> CBA_report.txt

#
util/cute_lc "$INPUT_VAST_LIGHTCURVE" | while read JD MAG ERR ;do
 echo "$JD     $MAG      $ERR"
done >> CBA_report.txt
if [ $? -ne 0 ];then
 echo "Something went WRONG with the lightcurve conversion!"
 exit 1
fi

 echo "The stub report is written to CBA_report.txt
You may need to edit the header before submitting the file to the CBA!"

# Try to find a sensible editor
if [ ! -z "$EDITOR" ];then
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
 $EDITOR CBA_report.txt
fi

#VARIABLE_STAR_NAME=`head CBA_report.txt | grep 'Variable: ' | awk '{print $2}' FS='Variable: '`
VARIABLE_STAR_NAME=`head CBA_report.txt | grep 'Variable: ' | awk -F 'Variable: ' '{print $2}'`
if [ -z "$VARIABLE_STAR_NAME" ];then
 echo "ERROR in CBA_report.txt : cannot find the variable star name"
 exit 1
fi
VARIABLE_STAR_NAME_NO_WHITESPACES="${VARIABLE_STAR_NAME//' '/'_'}"

#OBSERVATORY_NAME=`head CBA_report.txt | grep 'Observatory: ' | awk '{print $2}' FS='Observatory: '`
OBSERVATORY_NAME=`head CBA_report.txt | grep 'Observatory: ' | awk -F 'Observatory: ' '{print $2}'`
if [ -z "$OBSERVATORY_NAME" ];then
 echo "ERROR in CBA_report.txt : cannot find the observatory name"
 exit 1
fi

#OBSERVER_NAMES=`head CBA_report.txt | grep 'Observers: ' | awk '{print $2}' FS='Observers: '`
OBSERVER_NAMES=`head CBA_report.txt | grep 'Observers: ' | awk -F 'Observers: ' '{print $2}'`
if [ -z "$OBSERVER_NAMES" ];then
 echo "ERROR in CBA_report.txt : cannot find the observer name"
 exit 1
fi


FINAL_OUTPUT_FILENAME=CBA_"$VARIABLE_STAR_NAME_NO_WHITESPACES"_"$DATE_FOR_CBA_HEADER_FIRST_OBS"_measurements.txt
echo "Renaming the final report file:"
cp -v CBA_report.txt "$FINAL_OUTPUT_FILENAME"
grep '# ' CBA_report.txt > CBA_previously_used_header.txt

#Subject: AM CVn, 03 June 2019 (JD 2458638.61434 to 2458638.77528)"
SUBJECT="$VARIABLE_STAR_NAME, $DATE_FOR_CBA_MESSAGE_SUBJECT_FIRST_OBS (JD $JD_FIRST_OBS to $JD_LAST_OBS)"
MESSAGE="Hi,

Please find attached the observations of $VARIABLE_STAR_NAME on $DATE_FOR_CBA_MESSAGE_SUBJECT_FIRST_OBS from $OBSERVATORY_NAME.

Best wishes,
$OBSERVER_NAMES
"
echo " ### Suggested message subject and text 
To: cba-data@cbastro.org

Subject: $SUBJECT

$MESSAGE"
