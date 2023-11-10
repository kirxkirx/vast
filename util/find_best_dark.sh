#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

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
      cd "$(dirname "$1")"
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD"
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

VAST_PATH=`vastrealpath $0`
VAST_PATH=`dirname "$VAST_PATH"`
VAST_PATH="${VAST_PATH/util/}"
VAST_PATH="${VAST_PATH/lib/}"
VAST_PATH="${VAST_PATH/'//'/'/'}"
# In case the above line didn't work
VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
# Make sure no quotation marks are left in VAST_PATH
VAST_PATH=`echo "$VAST_PATH" | sed "s:'::g"`
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
export VAST_PATH
OLDDDIR_TO_CHECK_INPUT_FILE="$PWD"
cd "$VAST_PATH"



if [ -z "$1" ];then
 echo "Usage: 
 export DARK_FRAMES_DIR=/path/to/dark/frames/for/this/camera
 $0 uncorrected_image.fits"
 exit 1
fi

if [ -z "$DARK_FRAMES_DIR" ];then
 echo "DARK_FRAMES_DIR is not set"
 exit 1
fi

############### Input image ###############

FITSFILE="$1"

# Check if the image actually exists
if [ ! -f "$FITSFILE" ];then
 echo "ERROR: cannot find the image file $FITSFILE"
 exit 1
fi
# Check if the image file is not empty
if [ ! -s "$FITSFILE" ];then
 echo "ERROR: the input image file $FITSFILE is empty"
 exit 1
fi
###############
# On-the fly convert the input image if necessary
FITSFILE=`"$VAST_PATH"lib/on_the_fly_symlink_or_convert "$FITSFILE"`
###############
# Verify that the input file is a valid FITS file
"$VAST_PATH"lib/fitsverify -q -e "$FITSFILE"
if [ $? -ne 0 ];then
 echo "WARNING: the input file $FITSFILE seems to be a FITS image that does not fully comply with the FITS standard.
Checking if the filename extension and FITS header look reasonable..."
 ## Exampt from the rule for files that have at least some correct keywords
 echo "$FITSFILE" | grep  -e ".fits"  -e ".FITS"  -e ".fts" -e ".FTS"  -e ".fit"  -e ".FIT" && "$VAST_PATH"util/listhead "$FITSFILE" | grep -e "SIMPLE  =                    T" -e "TELESCOP= 'Aristarchos'" && "$VAST_PATH"util/listhead "$FITSFILE" | grep -e "NAXIS   =                    2"  -e "NAXIS3  =                    1" -e "TELESCOP= 'Aristarchos'"
 if [ $? -eq 0 ];then
  echo "OK, let's assume this is a valid FITS file"
 else
  echo "ERROR: the input image file $FITSFILE did not pass verification as a valid FITS file"
  exit 1
 fi
fi

###
BASENAME_FITSFILE=$(basename "$FITSFILE")
###

OUTPUT_OF_GET_IMAGE_DATE=$("$VAST_PATH"util/get_image_date "$FITSFILE" 2>&1)
if [ -z "$OUTPUT_OF_GET_IMAGE_DATE" ];then
 echo "ERROR: empty OUTPUT_OF_GET_IMAGE_DATE"
 exit 1
fi

IMAGE_JD=$(echo "$OUTPUT_OF_GET_IMAGE_DATE" | grep '  JD ' | awk '{print $2}' | head -n1)
if [ -z "$IMAGE_JD" ];then
 echo "ERROR: empty IMAGE_JD"
 exit 1
fi
IMAGE_EXPTIME=$(echo "$OUTPUT_OF_GET_IMAGE_DATE" | grep 'EXPTIME = ' | awk '{print $3}' | head -n1)
if [ -z "$IMAGE_EXPTIME" ];then
 echo "ERROR: empty IMAGE_EXPTIME"
 exit 1
fi
IMAGE_NAXIS1=$(echo "$OUTPUT_OF_GET_IMAGE_DATE" | grep ' FITS image ' | grep 'x' | awk '{print $1}' | awk -F'x' '{print $1}' | head -n1)
if [ -z "$IMAGE_NAXIS1" ];then
 echo "ERROR: empty IMAGE_NAXIS1"
 exit 1
fi
IMAGE_NAXIS2=$(echo "$OUTPUT_OF_GET_IMAGE_DATE" | grep ' FITS image ' | grep 'x' | awk '{print $1}' | awk -F'x' '{print $2}' | head -n1)
if [ -z "$IMAGE_NAXIS2" ];then
 echo "ERROR: empty IMAGE_NAXIS2"
 exit 1
fi

IMAGE_SETTEMP=$("$VAST_PATH"util/listhead "$FITSFILE" | grep 'SET-TEMP=' | head -n1 | awk '{printf "%.1f",$2}')
if [ -z "$IMAGE_SETTEMP" ];then
 echo "ERROR: empty IMAGE_SETTEMP"
 exit 1
fi

echo "################ $0 Input image ################"
echo "$IMAGE_JD $IMAGE_EXPTIME  $IMAGE_NAXIS1 $IMAGE_NAXIS2  $IMAGE_SETTEMP  $FITSFILE"


# Initialize a variable to hold the minimum JD difference and the corresponding dark image file name
MIN_JD_DIFF=9999999999
SELECTED_DARK_IMAGE=""

echo "################ $0 Dark frames ################"
############### Characterize dark frames ###############
for DARK in "$DARK_FRAMES_DIR"/* ;do
 if [ ! -f "$DARK" ];then
  continue
 fi
 if [ ! -s "$DARK" ];then
  continue
 fi

 ###############
 # On-the fly convert the input image if necessary
 DARK=`"$VAST_PATH"lib/on_the_fly_symlink_or_convert "$DARK"`
 ###############
 # Verify that the input file is a valid FITS file
 "$VAST_PATH"lib/fitsverify -q -e "$DARK"
 if [ $? -ne 0 ];then
  echo "WARNING: the input file $DARK seems to be a FITS image that does not fully comply with the FITS standard.
Checking if the filename extension and FITS header look reasonable..."
  ## Exampt from the rule for files that have at least some correct keywords
  echo "$DARK" | grep  -e ".fits"  -e ".FITS"  -e ".fts" -e ".FTS"  -e ".fit"  -e ".FIT" && "$VAST_PATH"util/listhead "$DARK" | grep -e "SIMPLE  =                    T" -e "TELESCOP= 'Aristarchos'" && "$VAST_PATH"util/listhead "$DARK" | grep -e "NAXIS   =                    2"  -e "NAXIS3  =                    1" -e "TELESCOP= 'Aristarchos'"
  if [ $? -eq 0 ];then
   echo "OK, let's assume this is a valid FITS file"
  else
   echo "ERROR: the input image file $DARK did not pass verification as a valid FITS file"
   exit 1
  fi
 fi

 ###
 BASENAME_DARK=$(basename "$DARK")
 ###

 OUTPUT_OF_GET_DARK_DATE=$("$VAST_PATH"util/get_image_date "$DARK" 2>&1)
 if [ -z "$OUTPUT_OF_GET_DARK_DATE" ];then
  echo "ERROR: empty OUTPUT_OF_GET_DARK_DATE"
  exit 1
 fi

 DARK_JD=$(echo "$OUTPUT_OF_GET_DARK_DATE" | grep '  JD ' | awk '{print $2}' | head -n1)
 if [ -z "$DARK_JD" ];then
  echo "ERROR: empty DARK_JD"
  exit 1
 fi
 DARK_EXPTIME=$(echo "$OUTPUT_OF_GET_DARK_DATE" | grep 'EXPTIME = ' | awk '{print $3}' | head -n1)
 if [ -z "$DARK_EXPTIME" ];then
  echo "ERROR: empty DARK_EXPTIME"
  exit 1
 fi
 DARK_NAXIS1=$(echo "$OUTPUT_OF_GET_DARK_DATE" | grep ' FITS image ' | grep 'x' | awk '{print $1}' | awk -F'x' '{print $1}' | head -n1)
 if [ -z "$DARK_NAXIS1" ];then
  echo "ERROR: empty DARK_NAXIS1"
  exit 1
 fi
 DARK_NAXIS2=$(echo "$OUTPUT_OF_GET_DARK_DATE" | grep ' FITS image ' | grep 'x' | awk '{print $1}' | awk -F'x' '{print $2}' | head -n1)
 if [ -z "$DARK_NAXIS2" ];then
  echo "ERROR: empty DARK_NAXIS2"
  exit 1
 fi

 DARK_SETTEMP=$("$VAST_PATH"util/listhead "$DARK" | grep 'SET-TEMP=' | head -n1 | awk '{printf "%.1f",$2}')
 if [ -z "$DARK_SETTEMP" ];then
  echo "ERROR: empty DARK_SETTEMP"
  exit 1
 fi

 echo "$DARK_JD $DARK_EXPTIME  $DARK_NAXIS1 $DARK_NAXIS2  $DARK_SETTEMP  $DARK"

 if [ "$IMAGE_NAXIS1" != "$DARK_NAXIS1" ];then
  continue
 fi
 if [ "$IMAGE_NAXIS2" != "$DARK_NAXIS2" ];then
  continue
 fi
 if [ "$IMAGE_EXPTIME" != "$DARK_EXPTIME" ];then
  continue
 fi
 if [ "$IMAGE_SETTEMP" != "$DARK_SETTEMP" ];then
  continue
 fi
 

 # Calculate the absolute JD difference
 JD_DIFF=$(echo "$DARK_JD $IMAGE_JD" | awk '{print ($1 > $2) ? $1 - $2 : $2 - $1}')

 # Update the minimum JD difference and selected dark image if the current one is closer
 if [ $(echo "$JD_DIFF < $MIN_JD_DIFF" | bc) -ne 0 ];then
  MIN_JD_DIFF=$JD_DIFF
  SELECTED_DARK_IMAGE="$DARK"
 fi

 echo "This one might work: $DARK  JD_DIFF=$JD_DIFF MIN_JD_DIFF=$MIN_JD_DIFF"

done

echo "################ $0 Selected dark frame ################"
# Output the selected dark image
if [ -n "$SELECTED_DARK_IMAGE" ];then
 echo "Best matching dark image: 
$SELECTED_DARK_IMAGE"
else
 echo "No matching dark image found"
 exit 1
fi


