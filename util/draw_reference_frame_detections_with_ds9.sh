#!/usr/bin/env bash
#
# This script will draw all stars detected on the reference image *BY SExtractor* 
# using DS9 FITS viewer. These stars will NOT necessary pass all VaST tests
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

echo "Working..."

if [ ! -f "vast_summary.log" ];then
 echo "Can't open file vast_summary.log"
 echo "Aborting!"
 exit 1
fi

# Get reference image name
FITSFILE=`grep "Ref.  image:" vast_summary.log | awk '{print $6}'`
echo "Reference image: $FITSFILE"

# Get aperture size
AP=`head -n 1 vast_image_details.log | awk '{print $9}'`
echo "Aperture size: $AP"
#AP=`echo "$AP/2"|bc -ql`
AP=`echo "$AP"| awk '{print $1/2}'`


# Read ref_frame_sextractor.cat
while read NUM FLUX FLUX_ERR MAG MAG_ERR X Y MUSOR ;do
 echo "circle($X,$Y,$AP)" >> /tmp/reg"$$""$USER".reg
done < ref_frame_sextractor.cat

# Prepare a header for DS9 region file 
echo "# Region file format: DS9 version 4.0" > /tmp/reg2"$$""$USER".reg
echo "# Filename: $FITSFILE" >> /tmp/reg2"$$""$USER".reg
echo "global color=green font=\"sans 10 normal\" select=1 highlite=1 edit=1 move=1 delete=1 include=1 fixed=0 source" >> /tmp/reg2"$$""$USER".reg
echo "image" >> /tmp/reg2"$$""$USER".reg
cat /tmp/reg"$$""$USER".reg >> /tmp/reg2"$$""$USER".reg
rm -f /tmp/reg"$$""$USER".reg

# Start DS9
echo "Starting DS9 on image $FITSFILE"
ds9 -xpa no $FITSFILE -region /tmp/reg2"$$""$USER".reg

# Remove last temporary file
rm -f /tmp/reg2"$$""$USER".reg
echo "All done =)"
