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

if [ -z "$VAST_PATH" ];then
 VAST_PATH=`vastrealpath $0`
 VAST_PATH=`dirname "$VAST_PATH"`
 VAST_PATH="${VAST_PATH/'util/'/}"
 VAST_PATH="${VAST_PATH/'lib/'/}"
 VAST_PATH="${VAST_PATH/'examples/'/}"
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH/examples/}"
 VAST_PATH="${VAST_PATH//'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=`echo "$VAST_PATH" | sed "s:'::g"`
 export VAST_PATH
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi


if [ -z "$2" ];then
 echo "Usage: $0 image.fit V"
 exit 1
fi
FITSFILE="$1"
FILTER="$2"

# Check if FITSFILE variable is set correctly
if [ -z "$FITSFILE" ];then
 echo "ERROR: FITSFILE variable is not set while it is supposed to be set befor reaching this point in the script."
 exit 1
fi

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
 echo "$FITSFILE" | grep  -e ".fits"  -e ".FITS"  -e ".fts" -e ".FTS"  -e ".fit"  -e ".FIT" && "$VAST_PATH"util/listhead "$FITSFILE" | grep -e "SIMPLE  =                    T" -e "TELESCOP= 'Aristarchos'" && "$VAST_PATH"util/listhead "$FITSFILE" | grep -e "NAXIS   =                    2" -e "NAXIS3  =                    1" -e "TELESCOP= 'Aristarchos'"
 if [ $? -eq 0 ];then
  echo "OK, let's assume this is a valid FITS file"
 else
  echo "ERROR: the input image file $FITSFILE did not pass verification as a valid FITS file"
  exit 1
 fi
fi


BASENAME_FITSFILE=`basename "$FITSFILE"`
UCAC5_CATALOG_NAME="wcs_$BASENAME_FITSFILE.cat.ucac5"
UCAC5_CATALOG_NAME="${UCAC5_CATALOG_NAME/wcs_wcs_/wcs_}"


# If there is an UCAC5 file already
if [ -s "$UCAC5_CATALOG_NAME" ];then
 # Test if the UCAC5 file has the photometric calibration in if
 TEST=`grep -v '0.000 0.000   0.000 0.000   0.000 0.000' "$UCAC5_CATALOG_NAME" | wc -l | awk '{print $1}'`
 if [ $TEST -lt 5 ];then
  echo "The existing UCAC5 file $UCAC5_CATALOG_NAME has no photometric info"
  rm -f "$UCAC5_CATALOG_NAME"
 fi
fi


util/solve_plate_with_UCAC5 "$FITSFILE"
if [ $? -ne 0 ];then
 echo "ERROR in $0  -- plate solving $FITSFILE"
 exit 1
fi


if [ ! -f "$UCAC5_CATALOG_NAME" ];then
 echo "ERROR in $0  -- no $UCAC5_CATALOG_NAME"
 exit
fi
if [ ! -s "$UCAC5_CATALOG_NAME" ];then
 echo "ERROR in $0  -- empty $UCAC5_CATALOG_NAME"
 exit
fi

#                                insmag catmag insmagerr
if [ "$FILTER" == "B" ];then
 cat "$UCAC5_CATALOG_NAME" | awk '{if ( $13 > 0.0 ) printf "%+7.4f %7.4f %6.4f\n", $8, $13, sqrt($9*$9+$14*$14)}' > calib.txt
elif [ "$FILTER" == "V" ];then
 cat "$UCAC5_CATALOG_NAME" | awk '{if ( $15 > 0.0 ) printf "%+7.4f %7.4f %6.4f\n", $8, $15, sqrt($9*$9+$16*$16)}' > calib.txt
elif [ "$FILTER" == "r" ];then
 cat "$UCAC5_CATALOG_NAME" | awk '{if ( $17 > 0.0 ) printf "%+7.4f %7.4f %6.4f\n", $8, $17, sqrt($9*$9+$18*$18)}' > calib.txt
elif [ "$FILTER" == "i" ];then
 cat "$UCAC5_CATALOG_NAME" | awk '{if ( $19 > 0.0 ) printf "%+7.4f %7.4f %6.4f\n", $8, $19, sqrt($9*$9+$20*$20)}' > calib.txt
elif [ "$FILTER" == "R" ] || [ "$FILTER" == "Rc" ] ;then
 cat "$UCAC5_CATALOG_NAME" | awk '{if ( $21 > 0.0 ) printf "%+7.4f %7.4f %6.4f\n", $8, $21, sqrt($9*$9+$22*$22)}' > calib.txt
elif [ "$FILTER" == "I" ] || [ "$FILTER" == "Ic" ] ;then
 cat "$UCAC5_CATALOG_NAME" | awk '{if ( $23 > 0.0 ) printf "%+7.4f %7.4f %6.4f\n", $8, $23, sqrt($9*$9+$24*$24)}' > calib.txt
elif [ "$FILTER" == "g" ];then
 cat "$UCAC5_CATALOG_NAME" | awk '{if ( $25 > 0.0 ) printf "%+7.4f %7.4f %6.4f\n", $8, $25, sqrt($9*$9+$26*$26)}' > calib.txt
else 
 echo "ERROR: unrecognized filter $FILTER"
 exit 1
fi

if [ ! -s "calib.txt" ];then
 echo "ERROR in $0  -- empty calib.txt"
 exit 1
else
 echo "calib.txt is written"
fi
