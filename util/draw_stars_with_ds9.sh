#!/usr/bin/env bash
#
# This script will draw all detected stars or a single star using DS9 FITS viewer.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Determine operation mode
SCRIPT_NAME=$0
if [ "$SCRIPT_NAME" = "util/mark_wcs_position_with_ds9.sh" ];then
 # WCS position mode
 WCS_OPERATION_MODE=1
 if [ -z $3 ];then
  echo "Usage: $0 wcs_calibrated_image.fits hh:mm:ss dd:mm:ss"
  echo "Example: $0 wcs_3C345_R.00017216.16h42m58.8s._39d48m37s.FIT 16:42:58.8 39:48:37"
  exit
 fi
else
 # pixel position mode
 WCS_OPERATION_MODE=0
fi

RANDOM_TMPFILE_SUFFIX="${$}${USER:0:8}"

echo "SCRIPT_NAME= $SCRIPT_NAME   WCS_OPERATION_MODE= $WCS_OPERATION_MODE   RANDOM_TMPFILE_SUFFIX= $RANDOM_TMPFILE_SUFFIX"


echo "Working..."

# If we whant to draw only one star
if [ -n "$3" ];then

 echo "Marking position of a single star."

 FITSFILE=$1
 if [ $WCS_OPERATION_MODE -eq 0 ];then
  # pixel position mode
  X=$2
  Y=$3
  if [ ! -z "$4" ];then
   AP=`echo "$4/2"|bc -ql`
   #FILENAME=$5
   #head -n 1 $FILENAME > /tmp/read"$RANDOM_TMPFILE_SUFFIX".tmp
   #FILENAME=`basename $FILENAME .dat`
   if [ ! -z "$5" ];then
    StringW=$(echo $5 | awk -F'out' '{print $2}' | awk -F'.dat' '{print $1}') 
   else
    StringW="OBJECT"
   fi
   #StringW=`echo $FILENAME | awk -F out '{print $2}'`
  else
   AP=5
   StringW="OBJECT"
  fi
 else
  # WCS position mode
  X=`lib/hms2deg $2 $3 |head -n1`
  Y=`lib/hms2deg $2 $3 |tail -n1 |awk '{print $1+0.0}'` # get rid of '+' sign if it's there
  AP=0.005
  StringW="MARKED_POSITION"
  echo "Marking WCS position:  $2 $3  ($X, $Y)"
  echo "point($X,$Y) # point=x" >> /tmp/reg"$RANDOM_TMPFILE_SUFFIX".reg
  #echo "circle($X,$Y,$AP)" >> /tmp/reg"$RANDOM_TMPFILE_SUFFIX".reg
  if [ -f vast_star_catalog.log ] ;then
   echo "vast_star_catalog.log found!"
   BEST_DIST=1.0
   while read M MERR N RA DEC REST ;do
    DIST=`lib/put_two_sources_in_one_field $2 $3 $RA $DEC 2>/dev/null |grep Angular | awk '{print $5}'`
    TEST=`echo "$DIST<$BEST_DIST"|bc -ql`
    if [ $TEST -eq 1 ] ;then
     BEST_DIST=$DIST
     BEST_RA=$RA
     BEST_DEC=$DEC
    fi
   done < vast_star_catalog.log
   if [ ! -z $BEST_RA ];then
    echo "########################################"
    echo -n "The closest star to the selected position is at "
    lib/put_two_sources_in_one_field $2 $3 $BEST_RA $BEST_DEC 2>/dev/null |grep Angular
    STRING=`grep "$BEST_RA" vast_star_catalog.log | grep "$BEST_DEC"`
    echo "  Mag.    Mag_err. NUMBER   RA(J2000)   Dec(J2000)   X(pix)   Y(pix)      IMAGE"
    #     21.913500 0.750400  00021  10:50:57.69 +56:13:44.0  2498.132  226.197 wcs_IMG_9195.fit
    echo "$STRING"
    echo "########################################"
    CLOSEST_STAR_NUMBER=`echo "$STRING"|awk '{print $3}'`
    X2=`lib/hms2deg $BEST_RA $BEST_DEC |head -n1`
    Y2=`lib/hms2deg $BEST_RA $BEST_DEC |tail -n1 |awk '{print $1+0.0}'` # get rid of '+' sign if it's there
    echo "circle($X2,$Y2,$AP)" >> /tmp/reg"$RANDOM_TMPFILE_SUFFIX".reg
    X2=`echo "$X2 $AP" | awk '{print $1+2.0*$2}'`
    Y2=`echo "$Y2 $AP" | awk '{print $1+2.0*$2}'`
    echo "# text($X2,$Y2) text={$CLOSEST_STAR_NUMBER}" >> /tmp/reg"$RANDOM_TMPFILE_SUFFIX".reg
   fi
  fi
 fi
 if [ $WCS_OPERATION_MODE -eq 1 ];then
  X=`echo "$X $AP" | awk '{print $1+2.0*$2}'`
  Y=`echo "$Y $AP" | awk '{print $1+2.0*$2}'` 
 fi
 echo "# text($X,$Y) text={$StringW}
circle($X,$Y,$AP)" >> /tmp/reg"$RANDOM_TMPFILE_SUFFIX".reg
 

else
 # Else - draw all stars from vast_lightcurve_statistics.log
 echo "Marking positions of all stars for which lightcurves were computed (stars listed in 'vast_lightcurve_statistics.log')."
 WCS_OPERATION_MODE=0 # only works in pixel position mode
 if [ ! -f vast_lightcurve_statistics.log ];then
  # if there is no file - make it now!
  echo "No lightcurve statistics file 'vast_lightcurve_statistics.log' let's recompute it!"
  util/nopgplot.sh
  if [ $? -ne 0 ];then
   echo "ERROR running 'util/nopgplot.sh'"
   exit 1
  fi
 fi
 if [ ! -s vast_lightcurve_statistics.log ];then
  echo "ERROR in $0 : cannot read 'vast_lightcurve_statistics.log'"
  exit 1
 fi
 if [ ! -s vast_summary.log ];then
  echo "ERROR in $0 : cannot read 'vast_summary.log'"
  exit 1
 fi
 # Get the reference image name
 export REFERENCE_IMAGE=$(cat vast_summary.log | grep 'Ref.  image:' | awk '{print $6}')
 if [ -z "$REFERENCE_IMAGE" ];then
  echo "ERROR in $0 : cannot get reference image from 'vast_summary.log'"
  exit 1
 else
  echo "Got the reference image name from 'vast_summary.log': $REFERENCE_IMAGE"
 fi
 # Check if the reference image exist
 if [ ! -s "$REFERENCE_IMAGE" ];then
  echo "ERROR in $0 : cannot display reference image $REFERENCE_IMAGE"
  exit 1
 fi
 if [ ! -s "vast_image_details.log" ];then
  echo "ERROR in $0 : cannot read the log file 'vast_image_details.log'"
  exit 1
 fi
 #AP=$(grep "$REFERENCE_IMAGE" vast_image_details.log | head -n1 | awk '{print $9}')
 echo "Reading pixel positions of stars from 'vast_lightcurve_statistics.log' (accepting only the ones that were detected at the reference image)..."
 # read the file vast_lightcurve_statistics.log
 TOTAL_STAR_COUNTER=0
 GOOD_STAR_COUNTER=0
 while read TMP TMP2 TMP3 TMP4 FILENAME REST ;do
  #head -n 1 $FILENAME > /tmp/read"$RANDOM_TMPFILE_SUFFIX".tmp
  #read JD MAG MERR X Y AP FITSFILE REST < /tmp/read"$RANDOM_TMPFILE_SUFFIX".tmp
  # The <<< operator was introduced in Bash version 2.05b, released in 2002.
  #read JD MAG MERR X Y AP FITSFILE REST <<< $(head -n 1 $FILENAME)
  read JD MAG MERR X Y AP FITSFILE REST <<< $(grep "$REFERENCE_IMAGE" "$FILENAME" | head -n1)
  # Check if this star was actually detected on the reference image or not
  # This is an ugly way to check it with grep feeding read now, but it works
  if [ "$REFERENCE_IMAGE" = "$FITSFILE" ];then
  
   #AP=`echo "$AP/2"|bc -ql`
   AP=`echo "$AP" | awk '{print $1/2}'`
   echo "circle($X,$Y,$AP)" >> /tmp/reg"$RANDOM_TMPFILE_SUFFIX".reg
   Y=`echo "$Y $AP" | awk '{print $1+1.8*$2}'`
   FILENAME=`basename $FILENAME .dat`
 
   case $1 in
     -h | --h | --help )
      echo "Usage:"
      echo "$0 [OPTION]"
      echo "or"
      echo "$0 image.fit X_star Y_star Ap_size outNNNN.dat"
      echo " -l near each star write it's number and its instrumental magnitude"
      echo " -s near each star write it's number only (default)"
      echo " -h print this message"
      exit 1;;
      -l | --l )
    FILENAME=`echo ${FILENAME/"out"/""}`
    StringW=`echo "$FILENAME $MAG"` ;;
     -s | --s | * )
    StringW=`echo $FILENAME | awk -F out '{print $2}'` ;;
   esac  
   echo "# text($X,$Y) text={$StringW}" >> /tmp/reg"$RANDOM_TMPFILE_SUFFIX".reg
   GOOD_STAR_COUNTER=$[$GOOD_STAR_COUNTER + 1 ]
  fi
  TOTAL_STAR_COUNTER=$[$TOTAL_STAR_COUNTER + 1 ]
 done < vast_lightcurve_statistics.log
 echo "Processed $TOTAL_STAR_COUNTER stars listed in 'vast_lightcurve_statistics.log', $GOOD_STAR_COUNTER of them were detected on the reference image (so they are added to the DS9 region file for display)"
 if [ $GOOD_STAR_COUNTER -eq 0 ];then
  echo "ERROR: no good stars written to the region file"
  exit 1
 fi
 if [ ! -s /tmp/reg"$RANDOM_TMPFILE_SUFFIX".reg ];then
  echo "ERROR: cannot read the region file /tmp/reg"$RANDOM_TMPFILE_SUFFIX".reg"
  exit 1
 fi
 # Make sure that we'll display the reference image, not the last one
 FITSFILE=$REFERENCE_IMAGE
fi

# Check if WCS-solved image is available
WCSFITSFILE=wcs_`basename $FITSFILE`
if [ -f $WCSFITSFILE ];then
 FITSFILE=$WCSFITSFILE
 echo "Found WCS-solved image $WCSFITSFILE, will use it instead!"
fi

# Prepare a header for DS9 region file 
echo "Writing DS9 region file " /tmp/reg2"$RANDOM_TMPFILE_SUFFIX".reg
echo "# Region file format: DS9 version 4.0" > /tmp/reg2"$RANDOM_TMPFILE_SUFFIX".reg
echo "# Filename: $FITSFILE" >> /tmp/reg2"$RANDOM_TMPFILE_SUFFIX".reg
echo "global color=green font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source" >> /tmp/reg2"$RANDOM_TMPFILE_SUFFIX".reg
if [ $WCS_OPERATION_MODE -eq 0 ];then
 echo "image" >> /tmp/reg2"$RANDOM_TMPFILE_SUFFIX".reg
else
 echo "fk5" >> /tmp/reg2"$RANDOM_TMPFILE_SUFFIX".reg
fi
cat /tmp/reg"$RANDOM_TMPFILE_SUFFIX".reg >> /tmp/reg2"$RANDOM_TMPFILE_SUFFIX".reg
for FILE_TO_BE_REMOVED in /tmp/reg"$RANDOM_TMPFILE_SUFFIX".reg /tmp/read"$RANDOM_TMPFILE_SUFFIX".tmp ;do
 if [ -f "$FILE_TO_BE_REMOVED" ];then
  rm -f "$FILE_TO_BE_REMOVED"
 fi
done
echo "#### head of the DS9 region file /tmp/reg2"$RANDOM_TMPFILE_SUFFIX".reg ####"
echo "####################################################"
head /tmp/reg2"$RANDOM_TMPFILE_SUFFIX".reg
# Print " ..... " if the region file is long (as expected)
if [ -n "$GOOD_STAR_COUNTER" ];then
 if [ $GOOD_STAR_COUNTER -gt 3 ];then
  echo " ..... ($GOOD_STAR_COUNTER objects in the region file)"
 fi
fi
echo "####################################################"
echo "Starting DS9 on image $FITSFILE with region file" /tmp/reg2"$RANDOM_TMPFILE_SUFFIX".reg
ds9 $FITSFILE -region /tmp/reg2"$RANDOM_TMPFILE_SUFFIX".reg -xpa no 
echo -n "Removing temporary files... "
rm -fv /tmp/reg2"$RANDOM_TMPFILE_SUFFIX".reg /tmp/reg"$RANDOM_TMPFILE_SUFFIX".reg /tmp/read"$RANDOM_TMPFILE_SUFFIX".tmp
echo "All done =)"
