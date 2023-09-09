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

echo "SCRIPT_NAME= $SCRIPT_NAME   WCS_OPERATION_MODE= $WCS_OPERATION_MODE"


echo "Working..."

# If we whant to draw only one star
if [ -n "$3" ];then

 FITSFILE=$1
 if [ $WCS_OPERATION_MODE -eq 0 ];then
  # pixel position mode
  X=$2
  Y=$3
  if [ ! -z "$4" ];then
   AP=`echo "$4/2"|bc -ql`
   #FILENAME=$5
   #head -n 1 $FILENAME > /tmp/read"$$""$USER".tmp
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
  echo "point($X,$Y) # point=x" >> /tmp/reg"$$""$USER".reg
  #echo "circle($X,$Y,$AP)" >> /tmp/reg"$$""$USER".reg
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
    echo "circle($X2,$Y2,$AP)" >> /tmp/reg"$$""$USER".reg
    #X2=`echo $X2+2.0*$AP| bc -ql`
    X2=`echo "$X2 $AP" | awk '{print $1+2.0*$2}'`
    #Y2=`echo $Y2+2.0*$AP| bc -ql`
    Y2=`echo "$Y2 $AP" | awk '{print $1+2.0*$2}'`
    echo "# text($X2,$Y2) text={$CLOSEST_STAR_NUMBER}" >> /tmp/reg"$$""$USER".reg
    #echo "point($X2,$Y2) # point=x" >> /tmp/reg"$$""$USER".reg
   fi
  fi
 fi
 if [ $WCS_OPERATION_MODE -eq 1 ];then
  #X=`echo $X+2.0*$AP| bc -ql`
  X=`echo "$X $AP" | awk '{print $1+2.0*$2}'`
  #Y=`echo $Y+2.0*$AP| bc -ql` 
  Y=`echo "$Y $AP" | awk '{print $1+2.0*$2}'` 
 fi
 echo "# text($X,$Y) text={$StringW}
circle($X,$Y,$AP)" >> /tmp/reg"$$""$USER".reg
 

else
 # Else - draw all stars from data.m_sigma
 WCS_OPERATION_MODE=0 # only works in pixel position mode
 if [ ! -f data.m_sigma ];then
  # if there is no file - make it now!
  #./find_candidates  
  util/nopgplot.sh
 fi
 # read the file data.m_sigma
 while read TMP TMP2 TMP3 TMP4 FILENAME ;do
  head -n 1 $FILENAME > /tmp/read"$$""$USER".tmp
  read JD MAG MERR X Y AP FITSFILE REST < /tmp/read"$$""$USER".tmp
  # Check if this star was actually detected on the reference image or not
  grep "Ref.  image:" vast_summary.log > /tmp/read"$$""$USER".grp
  read A B C D E F < /tmp/read"$$""$USER".grp
  rm -f /tmp/read"$$""$USER".grp
  if [ "$F" = "$FITSFILE" ];then
  
   AP=`echo "$AP/2"|bc -ql`
   echo "circle($X,$Y,$AP)" >> /tmp/reg"$$""$USER".reg
   #Y=`echo $Y+1.8*$AP| bc -ql`
   Y=`echo "$Y $AP" | awk '{print $1+1.8*$2}'`
   FILENAME=`basename $FILENAME .dat`
 
   case $1 in
     -h | --h | --help )
      echo "Usage:"
      echo "$0 [OPTION]"
      echo "or"
      echo "$0 image.fit X_star Y_star Ap_size outNNNN.dat"
      echo " -l near each star write it's number and its instrumental magnitude"
      echo " -s near each star write it's number only"
      echo " -h print this message"
      exit 1;;
      -l | --l )
    FILENAME=`echo ${FILENAME/"out"/""}`
    StringW=`echo "$FILENAME $MAG"` ;;
     -s | --s | * )
    StringW=`echo $FILENAME | awk -F out '{print $2}'` ;;
   esac  
   echo "# text($X,$Y) text={$StringW}" >> /tmp/reg"$$""$USER".reg
  fi
 done < data.m_sigma
 # Make sure that we'll display the reference image, not the last one
 FITSFILE=$F
fi

# Check if WCS-solved image is available
WCSFITSFILE=wcs_`basename $FITSFILE`
if [ -f $WCSFITSFILE ];then
 FITSFILE=$WCSFITSFILE
 echo "Found WCS-solved image $WCSFITSFILE, will use it instead!"
fi

# Prepare a header for DS9 region file 
echo "Writing DS9 region file " /tmp/reg2"$$""$USER".reg
echo "# Region file format: DS9 version 4.0" > /tmp/reg2"$$""$USER".reg
echo "# Filename: $FITSFILE" >> /tmp/reg2"$$""$USER".reg
echo "global color=green font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source" >> /tmp/reg2"$$""$USER".reg
if [ $WCS_OPERATION_MODE -eq 0 ];then
 echo "image" >> /tmp/reg2"$$""$USER".reg
else
 echo "fk5" >> /tmp/reg2"$$""$USER".reg
fi
cat /tmp/reg"$$""$USER".reg >> /tmp/reg2"$$""$USER".reg
rm -f /tmp/reg"$$""$USER".reg /tmp/read"$$""$USER".tmp
#echo "#### DS9 region file ####"
#echo "####################################################"
#cat /tmp/reg2"$$""$USER".reg
#echo "####################################################"
echo "Starting DS9 on image $FITSFILE with region file" /tmp/reg2"$$""$USER".reg
ds9 $FITSFILE -region /tmp/reg2"$$""$USER".reg -xpa no 
rm -f /tmp/reg2"$$""$USER".reg /tmp/reg"$$""$USER".reg /tmp/read"$$""$USER".tmp
echo "All done =)"
