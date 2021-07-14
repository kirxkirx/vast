#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Make sure this is not a file
if [ -f vast_magnitude_calibration_details_log ];then
 rm -f vast_magnitude_calibration_details_log
fi

# Check if the vast_magnitude_calibration_details_log directory exist
if [ ! -d vast_magnitude_calibration_details_log ]; then
 # If it doesn't - create it
 mkdir vast_magnitude_calibration_details_log
else
 # Else clean it
 for i in vast_magnitude_calibration_details_log/* ;do
  rm -f $i
 done
fi

# Check that this is a directory
if [ ! -d vast_magnitude_calibration_details_log ];then
 echo "ERROR: cannot create directory vast_magnitude_calibration_details_log" 1>&2
 exit 1
fi

# Save magnitude calibration details
for i in *.calib *.calib2 *calib_plane* *.calib_param ;do
 # Check if the file we want to remove exist so a user will not be disturbed by harmless error messages
 if [ -f $i ];then
  mv $i vast_magnitude_calibration_details_log/
 fi
done
