#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Check if WCSTools are installed
command -v xy2sky &> /dev/null
if [ $? -ne 0 ];then
 echo "ERROR: cannot find xy2sky in the PATH
Please install WCSTools"
 exit 1
fi

# Check if the log fail containing pixel positions 
# of ALL stars in the system of the reference image
# is present
if [ ! -f vast_list_of_all_stars.log ];then
 echo "ERROR: cannot find vast_list_of_all_stars.log"
 exit 1
fi

# Check if the log fail containing good stars is here
if [ ! -f vast_lightcurve_statistics.log ];then
 echo "ERROR: cannot find vast_lightcurve_statistics.log"
 exit 1
fi

# Checl if the main log file is here
if [ ! -f vast_summary.log ];then
 echo "ERROR: cannot find vast_summary.log"
 exit 1
fi

# Get the reference image
REFERENCE_IMAGE=`grep "Ref.  image:" vast_summary.log | awk '{print $6}'`
if [ "$REFERENCE_IMAGE" = "" ];then
 echo "ERROR: cannot get the reference image name from vast_summary.log"
 exit 1
fi

# Plate-solve the reference image
util/wcs_image_calibration.sh $REFERENCE_IMAGE
if [ $? -ne 0 ];then
 echo "ERROR: cannot plate-solve the reference image"
 exit 1
fi
WCS_SOLVED_REFERENCE_IMAGE=`basename $REFERENCE_IMAGE`
# this if is a workaround of the "wcs_wcs_*" problem
if [ ! -f $WCS_SOLVED_REFERENCE_IMAGE ];then
 WCS_SOLVED_REFERENCE_IMAGE="wcs_"$WCS_SOLVED_REFERENCE_IMAGE
fi
if [ ! -f $WCS_SOLVED_REFERENCE_IMAGE ];then
 echo "ERROR: cannot find the plate-solved reference image
I expect it to be named $WCS_SOLVED_REFERENCE_IMAGE , but..."
 exit 1
fi

echo "Processing (may take A LOT OF TIME)" 1>&2
while read STARNUM X Y ;do
 LIGHTCURVEFILENAME="out$STARNUM.dat"
 grep "$LIGHTCURVEFILENAME" vast_lightcurve_statistics.log &> /dev/null
 if [ $? -ne 0 ];then
  # This is not one of the good stars
  continue
 fi
 echo -n "$LIGHTCURVEFILENAME  "
 xy2sky $WCS_SOLVED_REFERENCE_IMAGE $X $Y
 echo -n "." 1>&2
done < vast_list_of_all_stars.log > vast_approximate_astrometry_from_reference_image.log
echo "
All done! 
The results are written to vast_approximate_astrometry_from_reference_image.log" 1>&2

