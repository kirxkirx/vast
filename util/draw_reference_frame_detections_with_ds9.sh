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
# 
REF_FRAME_CATALOG=`grep "$FITSFILE" vast_images_catalogs.log | awk '{print $1}'`
if [ ! -f "$REF_FRAME_CATALOG" ];then
 echo "ERROR: cannot open $REF_FRAME_CATALOG"
fi
#          1     12533.28     346.8921 -10.2452 -10.2452 -10.1869 -10.2850 -10.3134 -10.3424   0.0301   0.0301   0.0286   0.0318   0.0338   0.0359    219.3718     76.6184     1.601   0.05378     1.442   0.04632   0     4.16 -10.3581         0

while read NUM FLUX FLUX_ERR MAG1 MAG2 MAG3 MAG4 MAG5 MAG6 MAG_ERR1 MAG_ERR2 MAG_ERR3 MAG_ERR4 MAG_ERR5 MAG_ERR6 X Y MUSOR ;do
 echo "circle($X,$Y,$AP)" >> /tmp/reg"$$""$USER".reg
done < $REF_FRAME_CATALOG

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
