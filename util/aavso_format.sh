#!/usr/bin/env bash
echo "Welcome to VaST to AAVSO format convertor!"
echo " "
echo "Please, do not forget to select a comparison star"
echo "and convert instrumental magnitudes to standart system"
echo "using script util/magnitude_calibration.sh ! :)"
echo " " 
if [ -z $1 ];then
 echo "Please, enter lightcurve file name (outNNNN.dat) which you want to convert..."
 read INPUTFILE
else
 INPUTFILE=$1
fi
echo "Convsering $INPUTFILE to AAVSO format..."
AAVSOFILE="aavso_$INPUTFILE"
echo "Formated lightcurve will be written to $AAVSOFILE ..."
# write output file
echo \#TYPE=Extended > $AAVSOFILE
echo -n "Enter your observer code (OBSCODE): "
read OBSCODE
echo \#OBSCODE=$OBSCODE >> $AAVSOFILE
echo \#SOFTWARE=VaST >> $AAVSOFILE
echo \#DELIM="," >> $AAVSOFILE 
echo \#DATE=JD >> $AAVSOFILE
echo \#OBSTYPE=CCD >> $AAVSOFILE
echo -n "Enter filter (FILTER): "
read FILTER
echo -n "Enter the variable star name (NAME): "
read NAME
echo -n "Enter the comparison star name (CNAME): "
read CNAME
echo -n "Enter the comparison star magnitude (CMAG): "
read CMAG
echo -n "Enter the chart name (CHART): "
read CHART_NAME
echo -n "Override VaST error estimation (if no - just hit Return): "
read MANUAL_ERR
echo -n "Enter some comments (NOTES): "
read NOTES
if [ ! -z $NOTES ];then
 NOTES="na"
fi
while read JD MAG MERR REST ;do
 if [ ! -z $MANUAL_ERR ];then
  MERR=$MANUAL_ERR
 fi
 echo $NAME,$JD,$MAG,$MERR,$FILTER,NO,ABS,$CNAME,$CMAG,na,na,na,na,$CHART_NAME,$NOTES >> $AAVSOFILE
done < $INPUTFILE
cat $AAVSOFILE
echo "Output is written to $AAVSOFILE"
echo "All done! =)"
