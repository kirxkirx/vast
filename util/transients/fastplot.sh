#!/usr/bin/env bash

# Function to check if a file exists
function check_file_exists {
    if [ ! -f "$1" ]; then
        echo "ERROR: File $1 does not exist."
        exit 1
    fi
}

# Function to check if a directory exists
function check_directory_exists {
    if [ ! -d "$1" ]; then
        echo "ERROR: Directory $1 does not exist."
        exit 1
    fi
}

# Function to check if a file was successfully created
function check_file_created {
    if [ ! -f "$1" ]; then
        echo "ERROR: Failed to create file $1."
        exit 1
    fi
}

# Function to check if a directory was successfully created
function check_directory_created {
    if [ ! -d "$1" ]; then
        echo "ERROR: Failed to create directory $1."
        exit 1
    fi
}

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# A more portable realpath wrapper
function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=`readlink -f "$1" 2>/dev/null`
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=`greadlink -f "$1" 2>/dev/null`
   if [ $? -ne 0 ];then
    REALPATH=`realpath "$1" 2>/dev/null`
    if [ $? -ne 0 ];then
     REALPATH=`grealpath "$1" 2>/dev/null`
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")" || exit 1
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit 1
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

# Function to remove the last occurrence of a directory from a path
remove_last_occurrence() {
    echo "$1" | awk -F/ -v dir=$2 '{
        found = 0;
        for (i=NF; i>0; i--) {
            if ($i == dir && found == 0) {
                found = 1;
                continue;
            }
            res = (i==NF ? $i : $i "/" res);
        }
        print res;
    }'
}

# Function to get full path to vast main directory from the script name
get_vast_path_ends_with_slash_from_this_script_name() {
 VAST_PATH=$(vastrealpath $0)
 VAST_PATH=$(dirname "$VAST_PATH")

 # Remove last occurrences of util, lib, examples
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "util")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "lib")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "examples")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "transients")

 # Make sure no '//' are left in the path (they look ugly)
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")

 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")

 # Check that VAST_PATH ends with '/'
 LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
 if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
  VAST_PATH="$VAST_PATH/"
 fi

 echo "$VAST_PATH"
}

VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
VAST_DIR="$VAST_PATH"


# check if all the needed programs are installed
for TESTED_PROGRAM in convert montage swarp ;do
 if ! command -v $TESTED_PROGRAM &>/dev/null ;then
  echo "Cannot find $TESTED_PROGRAM"
  if [ "$TESTED_PROGRAM" = "convert" ] || [ "$TESTED_PROGRAM" = "montage" ] ;then
   echo "Please install ImageMagick ($TESTED_PROGRAM is a part of it)"
  fi
  exit 1
 fi
done


if [ -z "$1" ];then
 echo "Usage: $0 http://kirx.net:8888/unmw/uploads/20231114_evening_STL-11000M.html#21474_047_2023-11-14_18-35-58_002"
 exit 1
fi

echo "$1" | grep --quiet '#'
if [ $? -ne 0 ];then
 echo "The input URL doesn't have '#' - it doesn't point to a specific source in the HTML report"
 echo "Usage: $0 http://kirx.net:8888/unmw/uploads/20231114_evening_STL-11000M.html#21474_047_2023-11-14_18-35-58_002"
 exit 1
fi

INPUT_TRANSIENT_URL="$1"


TRANSIENT_ID=$(echo "$INPUT_TRANSIENT_URL" | awk -F'#' '{print $2}')





# Get transient info from the results web page
# some web servers may want to conver all HTML tags to lowercase
CURL_REPLY=$(curl --insecure --silent "$INPUT_TRANSIENT_URL" | grep -A5000 "printCandidateNameWithAbsLink..$TRANSIENT_ID" | awk 'tolower($0) ~ /<hr>/{exit} {print}')
#CURL_REPLY=$(curl --insecure --silent "$INPUT_TRANSIENT_URL" | grep -A5000 "printCandidateNameWithAbsLink..$TRANSIENT_ID" | awk '/<HR>/{exit} {print}')
if [ -z "$CURL_REPLY" ];then
 echo "ERROR: empty CURL_REPLY"
 exit 1
fi

TARET_RADEC=$(echo "$CURL_REPLY" | grep -A1 'Mean magnitude and position on the discovery images:' | tail -n1 | awk '{print $6" "$7}')
TARET_RA=$(echo "$TARET_RADEC" | awk '{print $1}')
TARET_DEC=$(echo "$TARET_RADEC" | awk '{print $2}')
if [ -z "$TARET_DEC" ];then
 echo "ERROR: cannot get TARET_DEC"
 exit 1
fi

# some web servers change '&&' to '&amp;&amp;' while others don't 
THE_FOUR_IMAGE_FILES=$(echo "$CURL_REPLY" | grep './vast ' | awk -F'&&' '{print $1}' | awk -F'&amp;&amp;' '{print $1}' | awk -F'--nojdkeyword' '{print $2}')
if [ -z "$THE_FOUR_IMAGE_FILES" ];then
 echo "ERROR: cannot get THE_FOUR_IMAGE_FILES"
 exit 1
fi
N_FILE=0
for FILE_TO_CHECK in $THE_FOUR_IMAGE_FILES ;do
 echo "Checking $FILE_TO_CHECK"
 check_file_exists "$FILE_TO_CHECK"
 N_FILE=$[$N_FILE + 1]
done
if [ $N_FILE -ne 4 ];then
 echo "ERROR: N_FILE = $N_FILE != 4"
 exit 1
fi
# We want to include the new epoch directory name in the output dir name as it contains the camera name in it
IMG_DIR_WITH_CAMERA_NAME=$(echo "$THE_FOUR_IMAGE_FILES" | awk '{print $4}')
IMG_DIR_WITH_CAMERA_NAME=$(dirname "$IMG_DIR_WITH_CAMERA_NAME")
IMG_DIR_WITH_CAMERA_NAME=$(basename "$IMG_DIR_WITH_CAMERA_NAME")

#######################
check_directory_exists "$VAST_DIR"
cd "$VAST_DIR"
util/clean_data.sh
rm -f *.gif *.png
cp default.sex.telephoto_lens_onlybrightstars_v1 default.sex

OUTUT_DIR="fastplot__$IMG_DIR_WITH_CAMERA_NAME"__"$TRANSIENT_ID"
if [ -d "$OUTUT_DIR" ];then
 rm -rf "$OUTUT_DIR"
fi
mkdir "$OUTUT_DIR"
check_directory_created "$OUTUT_DIR"
mkdir "$OUTUT_DIR"/reference_platesolved_FITS
mkdir "$OUTUT_DIR"/new_platesolved_FITS
mkdir "$OUTUT_DIR"/resampled_FITS
mkdir "$OUTUT_DIR"/finder_charts_PNG
mkdir "$OUTUT_DIR"/animation_GIF

# write a ds9 region file, handy to find the transient in FITS images
echo "# Region file format: DS9 version 4.1
global color=green dashlist=8 3 width=1 font=\"helvetica 10 normal roman\" select=1 highlite=1 dash=0 fixed=0 edit=1 move=1 delete=1 include=1 source=1
fk5
circle($TARET_RA,$TARET_DEC,60\")
circle($TARET_RA,$TARET_DEC,300\")
" > "$OUTUT_DIR"/ds9.reg

# write summary
TRANSIENT_SUMMARY=$(echo "$CURL_REPLY" | grep -A2 'Mean magnitude and position on the discovery images:' | sed 's/<[^>]*>//g' | sed 's/galactic/galactic coordinates.  Constellation:/g')
echo "*** Transient detection summary ***

$TRANSIENT_SUMMARY

Both reference and new epochs have two images each. 
The images are shifted with respect to each other to aid in distinguishing stars from image artifacts.
The transient position and magnitude listed above are the average of the values measured on the two second-epoch images.


*** Directory structure *** 
 * reference_platesolved_FITS/ - plate solved (WCS-calibrated) FITS images for the reference epoch, when the transient was weak or invisible.
 * new_platesolved_FITS/ - plate solved (WCS-calibrated) FITS images for the new epoch, when the transient was bright.
 * resampled_FITS/ - reference and new-epoch FITS images resampled to the standard 'North is Up, East is Left' orientation.
 * finder_charts_PNG/ - PNG finder charts generated from the reference and new-epoch images cantered on the transient.
 * animation_GIF/ - GIF animation of the reference and new-epoch images centered on the transient's location.
 * ds9.reg - DS9 region file marking the transient's position.
 * readme.txt - this file


*** Examples ***

1. Blink the images in DS9 marking the transient position:

ds9 reference_platesolved_FITS/* new_platesolved_FITS/* -region ds9.reg -frame lock wcs

After starting the ds9 zoom out, locate and center the transient marked with the green circles defined in the region file,
then compare the four images by clicking frame->blink


2. Re-run transient search with VaST:

cd vast
REFERENCE_IMAGES=/tmp/$OUTUT_DIR/reference_platesolved_FITS util/transients/transient_factory_test31.sh /tmp/$OUTUT_DIR/new_platesolved_FITS

The above example assumes that VaST is installed in vast/ folder and this directory $OUTUT_DIR is located at /tmp/
More information about VaST may be found at http://scan.sai.msu.ru/vast/
" > "$OUTUT_DIR"/readme.txt

# make plate solved and resampled FITS images and finder charts
INPUTFILE=$(echo "$THE_FOUR_IMAGE_FILES" | awk '{print $1}')
check_file_exists "$INPUTFILE"
INPUTFILE_BASENAME=$(basename "$INPUTFILE")
WCS_INPUTFILE=wcs_$(basename "$INPUTFILE")
util/wcs_image_calibration.sh "$INPUTFILE"
if [ $? -ne 0 ];then
 echo "ERROR running util/wcs_image_calibration.sh $INPUTFILE"
 exit 1
fi
check_file_created "$WCS_INPUTFILE"
cp -v "$WCS_INPUTFILE" "$OUTUT_DIR"/reference_platesolved_FITS
util/make_finding_chart_script.sh "$WCS_INPUTFILE" "$TARET_RA" "$TARET_DEC"
if [ $? -ne 0 ];then
 echo "ERROR running util/make_finding_chart_script.sh $WCS_INPUTFILE $TARET_RA $TARET_DEC"
 exit 1
fi
check_file_created resample_"$WCS_INPUTFILE"
CHARTS_REF1_BASENAME="${INPUTFILE_BASENAME//./_}"
cp -v resample_"$WCS_INPUTFILE" "$OUTUT_DIR"/resampled_FITS

INPUTFILE=$(echo "$THE_FOUR_IMAGE_FILES" | awk '{print $2}')
check_file_exists "$INPUTFILE"
INPUTFILE_BASENAME=$(basename "$INPUTFILE")
WCS_INPUTFILE=wcs_$(basename "$INPUTFILE")
util/wcs_image_calibration.sh "$INPUTFILE"
if [ $? -ne 0 ];then
 echo "ERROR running util/wcs_image_calibration.sh $INPUTFILE"
 exit 1
fi
check_file_created "$WCS_INPUTFILE"
cp -v "$WCS_INPUTFILE" "$OUTUT_DIR"/reference_platesolved_FITS
util/make_finding_chart_script.sh "$WCS_INPUTFILE" "$TARET_RA" "$TARET_DEC"
if [ $? -ne 0 ];then
 echo "ERROR running util/make_finding_chart_script.sh $WCS_INPUTFILE $TARET_RA $TARET_DEC"
 exit 1
fi
check_file_created resample_"$WCS_INPUTFILE"
CHARTS_REF2_BASENAME="${INPUTFILE_BASENAME//./_}"
cp -v resample_"$WCS_INPUTFILE" "$OUTUT_DIR"/resampled_FITS

INPUTFILE=$(echo "$THE_FOUR_IMAGE_FILES" | awk '{print $3}')
check_file_exists "$INPUTFILE"
INPUTFILE_BASENAME=$(basename "$INPUTFILE")
WCS_INPUTFILE=wcs_$(basename "$INPUTFILE")
util/wcs_image_calibration.sh "$INPUTFILE"
if [ $? -ne 0 ];then
 echo "ERROR running util/wcs_image_calibration.sh $INPUTFILE"
 exit 1
fi
check_file_created "$WCS_INPUTFILE"
cp -v "$WCS_INPUTFILE" "$OUTUT_DIR"/new_platesolved_FITS
util/make_finding_chart_script.sh "$WCS_INPUTFILE" "$TARET_RA" "$TARET_DEC"
if [ $? -ne 0 ];then
 echo "ERROR running util/make_finding_chart_script.sh $WCS_INPUTFILE $TARET_RA $TARET_DEC"
 exit 1
fi
check_file_created resample_"$WCS_INPUTFILE"
CHARTS_NEW1_BASENAME="${INPUTFILE_BASENAME//./_}"
cp -v resample_"$WCS_INPUTFILE" "$OUTUT_DIR"/resampled_FITS

INPUTFILE=$(echo "$THE_FOUR_IMAGE_FILES" | awk '{print $4}')
check_file_exists "$INPUTFILE"
INPUTFILE_BASENAME=$(basename "$INPUTFILE")
WCS_INPUTFILE=wcs_$(basename "$INPUTFILE")
util/wcs_image_calibration.sh "$INPUTFILE"
if [ $? -ne 0 ];then
 echo "ERROR running util/wcs_image_calibration.sh $INPUTFILE"
 exit 1
fi
check_file_created "$WCS_INPUTFILE"
cp -v "$WCS_INPUTFILE" "$OUTUT_DIR"/new_platesolved_FITS
util/make_finding_chart_script.sh "$WCS_INPUTFILE" "$TARET_RA" "$TARET_DEC"
if [ $? -ne 0 ];then
 echo "ERROR running util/make_finding_chart_script.sh $WCS_INPUTFILE $TARET_RA $TARET_DEC"
 exit 1
fi
check_file_created resample_"$WCS_INPUTFILE"
CHARTS_NEW2_BASENAME="${INPUTFILE_BASENAME//./_}"
cp -v resample_"$WCS_INPUTFILE" "$OUTUT_DIR"/resampled_FITS

# Combine the finder charts into one image (note the '*' symbols meaning the command will work only if you have a single transient in that field)
#
montage finder_0032pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix.png finder_0032pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov.png -tile 2x1 -geometry +0+0 finder_chart_0032pix_targetmark_v11.png
montage finder_0032pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix.png finder_0032pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov.png -tile 2x1 -geometry +0+0 finder_chart_0032pix_targetmark_v12.png
montage finder_0064pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix.png finder_0064pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov.png -tile 2x1 -geometry +0+0 finder_chart_0064pix_targetmark_v11.png
montage finder_0064pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix.png finder_0064pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov.png -tile 2x1 -geometry +0+0 finder_chart_0064pix_targetmark_v12.png
montage finder_0128pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix.png finder_0128pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov.png -tile 2x1 -geometry +0+0 finder_chart_0128pix_targetmark_v11.png
montage finder_0128pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix.png finder_0128pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov.png -tile 2x1 -geometry +0+0 finder_chart_0128pix_targetmark_v12.png
#
montage finder_0020pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0020pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0020pix_v11.png
montage finder_0020pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0020pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0020pix_v12.png
montage finder_0032pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0032pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0032pix_v11.png
montage finder_0032pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0032pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0032pix_v12.png
montage finder_0064pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0064pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0064pix_v11.png
montage finder_0064pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0064pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0064pix_v12.png
montage finder_0128pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0128pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0128pix_v11.png
montage finder_0128pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0128pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0128pix_v12.png
#
#
montage finder_0032pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix.png finder_0032pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov.png -tile 2x1 -geometry +0+0 finder_chart_0032pix_targetmark_v21.png
montage finder_0032pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix.png finder_0032pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov.png -tile 2x1 -geometry +0+0 finder_chart_0032pix_targetmark_v22.png
montage finder_0064pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix.png finder_0064pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov.png -tile 2x1 -geometry +0+0 finder_chart_0064pix_targetmark_v21.png
montage finder_0064pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix.png finder_0064pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov.png -tile 2x1 -geometry +0+0 finder_chart_0064pix_targetmark_v22.png
montage finder_0128pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix.png finder_0128pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov.png -tile 2x1 -geometry +0+0 finder_chart_0128pix_targetmark_v21.png
montage finder_0128pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix.png finder_0128pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov.png -tile 2x1 -geometry +0+0 finder_chart_0128pix_targetmark_v22.png
#
montage finder_0020pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0020pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0020pix_v21.png
montage finder_0020pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0020pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0020pix_v22.png
montage finder_0032pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0032pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0032pix_v21.png
montage finder_0032pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0032pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0032pix_v22.png
montage finder_0064pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0064pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0064pix_v21.png
montage finder_0064pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0064pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0064pix_v22.png
montage finder_0128pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0128pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0128pix_v21.png
montage finder_0128pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0128pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_nofov_notargetmark.png -tile 2x1 -geometry +0+0 finder_chart_0128pix_v22.png

# Create GIF animation
#
convert -delay 50 -loop 0   finder_0020pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0020pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_notargetmark.png animation_0020pix_v11.gif
convert -delay 50 -loop 0   finder_0020pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0020pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_notargetmark.png animation_0020pix_v12.gif
convert -delay 50 -loop 0   finder_0032pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0032pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_notargetmark.png animation_0032pix_v11.gif
convert -delay 50 -loop 0   finder_0032pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0032pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_notargetmark.png animation_0032pix_v12.gif
convert -delay 50 -loop 0   finder_0064pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0064pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_notargetmark.png animation_0064pix_v11.gif
convert -delay 50 -loop 0   finder_0064pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0064pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_notargetmark.png animation_0064pix_v12.gif
convert -delay 50 -loop 0   finder_0128pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0128pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_notargetmark.png animation_0128pix_v11.gif
convert -delay 50 -loop 0   finder_0128pix_resample_wcs_"$CHARTS_REF1_BASENAME"__*pix_notargetmark.png finder_0128pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_notargetmark.png animation_0128pix_v12.gif
#
convert -delay 50 -loop 0   finder_0020pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0020pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_notargetmark.png animation_0020pix_v21.gif
convert -delay 50 -loop 0   finder_0020pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0020pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_notargetmark.png animation_0020pix_v22.gif
convert -delay 50 -loop 0   finder_0032pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0032pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_notargetmark.png animation_0032pix_v21.gif
convert -delay 50 -loop 0   finder_0032pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0032pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_notargetmark.png animation_0032pix_v22.gif
convert -delay 50 -loop 0   finder_0064pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0064pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_notargetmark.png animation_0064pix_v21.gif
convert -delay 50 -loop 0   finder_0064pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0064pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_notargetmark.png animation_0064pix_v22.gif
convert -delay 50 -loop 0   finder_0128pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0128pix_resample_wcs_"$CHARTS_NEW1_BASENAME"__*pix_notargetmark.png animation_0128pix_v21.gif
convert -delay 50 -loop 0   finder_0128pix_resample_wcs_"$CHARTS_REF2_BASENAME"__*pix_notargetmark.png finder_0128pix_resample_wcs_"$CHARTS_NEW2_BASENAME"__*pix_notargetmark.png animation_0128pix_v22.gif

# save visual inspection plots
mv -v *.png "$OUTUT_DIR"/finder_charts_PNG
mv -v *.gif "$OUTUT_DIR"/animation_GIF

#
echo "###############################
The files are saved to: $OUTUT_DIR
###############################"

if [ -f "$OUTUT_DIR".tar.bz2 ];then
 rm -f "$OUTUT_DIR".tar.bz2
fi
tar -cjf "$OUTUT_DIR".tar.bz2 "$OUTUT_DIR"

ls -lhdt "$OUTUT_DIR" "$OUTUT_DIR".tar.bz2
echo "###############################
Full path to the archive file: 
$PWD/"$OUTUT_DIR".tar.bz2
###############################"

