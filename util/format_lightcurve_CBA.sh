#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

TRY_THESE_TEXT_EDITORS_IN_ORDER="joe nano vim emacs"

if [ -z "$1" ];then
 echo "Usage: $0 out01234.dat"
 exit 1
fi

TEST_MODE_WITH_NO_INTERACTIVE_EDITOR=0
if [ -n "$2" ];then
 if [ "$2" = "test" ];then
  TEST_MODE_WITH_NO_INTERACTIVE_EDITOR=1
 fi
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
JD_FIRST_OBS=$(util/cute_lc "$INPUT_VAST_LIGHTCURVE" | head -n1 | awk '{printf "%.3f", $1}')
JD_LAST_OBS=$(util/cute_lc "$INPUT_VAST_LIGHTCURVE" | tail -n1 | awk '{printf "%.3f", $1}')
UNIXTIME_FIRST_OBS=$(util/get_image_date "$JD_FIRST_OBS" 2>/dev/null | grep 'Unix Time' | awk '{print $3}')
DATE_FOR_CBA_HEADER_FIRST_OBS=$(LANG=C date -d @"$UNIXTIME_FIRST_OBS" +"%d%b%Y")
DATE_FOR_CBA_MESSAGE_SUBJECT_FIRST_OBS=$(LANG=C date -d @"$UNIXTIME_FIRST_OBS" +"%d %B %Y")
if [ -z "$DATE_FOR_CBA_HEADER_FIRST_OBS" ] || [ -z "$DATE_FOR_CBA_MESSAGE_SUBJECT_FIRST_OBS" ];then
 # if that didn't work - try BSD date
 DATE_FOR_CBA_HEADER_FIRST_OBS=$(LANG=C date -r "$UNIXTIME_FIRST_OBS" +"%d%b%Y")
 DATE_FOR_CBA_MESSAGE_SUBJECT_FIRST_OBS=$(date -r "$UNIXTIME_FIRST_OBS" +"%d %B %Y")
fi

# Get the exposure time for the header
if [ -s vast_image_details.log ];then
 MEDIAN_EXPOSURE_TIME_SEC=`cat vast_image_details.log | awk -F 'exp=' '{print $2}' | awk '{print $1}' | util/colstat 2> /dev/null | grep 'MEDIAN=' | awk '{printf "%.0f\n", $2}'`
else
 echo "WARNING: cannot get the exposure time from vast_image_details.log"
fi

VARIABLE_STAR_NAME="XX Xxx"
# if automated magnitude calibration was performed,
# there should be a plate-solved FITS corresonding to the reference image
# note that we checked above that vast_summary.log exist
REFERENCE_IMAGE=$(grep 'Ref.  image:' vast_summary.log | awk '{print $6}')
PLATE_SOLVED_REFERENCE_IMAGE=wcs_$(basename $REFERENCE_IMAGE)
PLATE_SOLVED_REFERENCE_IMAGE="${PLATE_SOLVED_REFERENCE_IMAGE/wcs_wcs_/wcs_}"
if [ -f "$PLATE_SOLVED_REFERENCE_IMAGE" ];then
 echo "Found a plate-solved reference image $PLATE_SOLVED_REFERENCE_IMAGE
Trying to automatically ID the star $INPUT_VAST_LIGHTCURVE"
 STAR_NUMBER=$(echo "${INPUT_VAST_LIGHTCURVE/out/}")
 STAR_NUMBER=$(echo "${STAR_NUMBER/.dat/}")
 # '| while read A ;do echo $A ;done' is to remove the trailing white space if the variable name is from GCVS
 AUTOMATIC_VARIABLE_STAR_NAME=$(util/identify_justname.sh $INPUT_VAST_LIGHTCURVE | grep -A100 'Star:' | grep -v "$STAR_NUMBER  " | tail -n1 | while read A ;do echo $A ;done)
 # Handle 'V* BT Mon -- Nova' this kind of names appear when Simbad (if GCVS is down)
 AUTOMATIC_VARIABLE_STAR_NAME="${AUTOMATIC_VARIABLE_STAR_NAME/"V* "}"
 AUTOMATIC_VARIABLE_STAR_NAME=$(echo "$AUTOMATIC_VARIABLE_STAR_NAME" | awk -F' --' '{print $1}')
 #
 if [ -n "$AUTOMATIC_VARIABLE_STAR_NAME" ];then
  echo "$AUTOMATIC_VARIABLE_STAR_NAME" | grep --silent -e 'Network error:' -e 'cannot connect'
  if [ $? -ne 0 ];then
   echo "Automatically setting the variable star name $AUTOMATIC_VARIABLE_STAR_NAME"
   VARIABLE_STAR_NAME="$AUTOMATIC_VARIABLE_STAR_NAME"
  else
   echo "A network error has occurred while trying to ID the star, keeping the name $VARIABLE_STAR_NAME"
  fi
 else
  echo "Something went wrong while trying to ID the star, keeping the name $VARIABLE_STAR_NAME"
 fi
fi

if [ ! -s CBA_previously_used_header.txt ];then
 echo "# Variable: $VARIABLE_STAR_NAME
# Date: $DATE_FOR_CBA_HEADER_FIRST_OBS
# Comp star: 144_AAVSO_(V= 14.357 )
# Check star: 157_AAVSO_(V= 15.663 )
# Exp time (s): $MEDIAN_EXPOSURE_TIME_SEC s
# Filter: CV
# Observatory: Michigan State Campus Observatory
# East Lansing, MI, USA
# Observers: Kirill Sokolovsky
# Comments: Clear most of the night.
#    JD              Var_Mag        Var_eMag" > CBA_previously_used_header.txt
fi
#cp CBA_previously_used_header.txt CBA_report.txt
if [ "$VARIABLE_STAR_NAME" = "XX Xxx" ];then
 echo "Trying to get variable star name from CBA_previously_used_header.txt"
 grep '# Variable: ' CBA_previously_used_header.txt
 grep '# Variable: ' CBA_previously_used_header.txt > CBA_report.txt
else
 echo "# Variable: $VARIABLE_STAR_NAME" > CBA_report.txt
fi
echo "# Date: $DATE_FOR_CBA_HEADER_FIRST_OBS" >> CBA_report.txt
grep '# Comp star: ' CBA_previously_used_header.txt >> CBA_report.txt
grep '# Check star: ' CBA_previously_used_header.txt >> CBA_report.txt
echo "# Exp time (s): $MEDIAN_EXPOSURE_TIME_SEC " >> CBA_report.txt
grep '# Filter: ' CBA_previously_used_header.txt >> CBA_report.txt
grep -A4 '# Observatory: ' CBA_previously_used_header.txt | grep '#' >> CBA_report.txt

#
#util/cute_lc "$INPUT_VAST_LIGHTCURVE" | while read JD MAG ERR ;do
util/cute_lc_fullJD "$INPUT_VAST_LIGHTCURVE" | while read JD MAG ERR ;do
 echo "$JD     $MAG      $ERR"
done >> CBA_report.txt
if [ $? -ne 0 ];then
 echo "Something went WRONG with the lightcurve conversion!"
 exit 1
fi

 echo "The stub report is written to CBA_report.txt
You may need to edit the header before submitting the file to the CBA!"

# Try to find a sensible editor
if [ -z "$EDITOR" ] || ! command -v "$EDITOR" &>/dev/null ;then
 #for EDITOR_TO_TRY in joe nano vim emacs ;do
 for EDITOR_TO_TRY in $TRY_THESE_TEXT_EDITORS_IN_ORDER ;do
  command -v $EDITOR_TO_TRY &>/dev/null
  if [ $? -eq 0 ];then
   EDITOR="$EDITOR_TO_TRY"
   break
  fi
 done
fi

# Manually edit the report
if [ ! -z "$EDITOR" ];then
 if [ $TEST_MODE_WITH_NO_INTERACTIVE_EDITOR -ne 1 ];then
  $EDITOR CBA_report.txt || echo "ERROR: failed to start the interactive text editor $EDITOR"
 else
  echo "Running in the test mode - not starting an interactive text editor!"
 fi
fi

VARIABLE_STAR_NAME=`head CBA_report.txt | grep 'Variable: ' | awk -F 'Variable: ' '{print $2}'`
if [ -z "$VARIABLE_STAR_NAME" ];then
 echo "ERROR in CBA_report.txt : cannot find the variable star name"
 exit 1
fi
VARIABLE_STAR_NAME_NO_WHITESPACES="${VARIABLE_STAR_NAME// /_}"

OBSERVATORY_NAME=`head CBA_report.txt | grep 'Observatory: ' | awk -F 'Observatory: ' '{print $2}'`
if [ -z "$OBSERVATORY_NAME" ];then
 echo "ERROR in CBA_report.txt : cannot find the observatory name"
 exit 1
fi

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
#To: cba-data@cbastro.org # Old address
To: cbastro-data@googlegroups.com

Subject: $SUBJECT

$MESSAGE"
