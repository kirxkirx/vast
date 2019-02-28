#!/usr/bin/env bash

# This script will read a list of candidate variables from vast_autocandidates.log
# and create an HTML page candidates_report/index.html with a thumbnail image and
# a lightcurve plot for each object. It will also mark object's position on a few
# "index-vs-mag" plots.
#
# Still unsure how useful it is for variability search in practice.
#

# Set PNG finding chart dimensions
export PGPLOT_PNG_HEIGHT=400 ; export PGPLOT_PNG_WIDTH=600


command -v gnuplot &> /dev/null
if [ $? -ne 0 ];then
 echo "ERROR: please install gnuplot"
 exit 1
fi

####### Set color scheme for gnuplot 5.0 or above
GNUPLOT5_COLOR_SCHEME_COMMAND="set colors classic"
GNUPLOT_VERSION=`gnuplot --version | awk '{print $2}' | awk '{print $1}' FS='.'`
if [ $GNUPLOT_VERSION -ge 5 ];then
 COLOR_SCHEME_COMMAND="$GNUPLOT5_COLOR_SCHEME_COMMAND"
else
 COLOR_SCHEME_COMMAND=""
fi
#######



if [ ! -s vast_autocandidates.log ];then
 echo "ERROR: cannot find list of candidates in vast_autocandidates.log"
 exit 1
fi

# Make sure there is a directory to put the report in
if [ ! -d candidates_report/ ];then
 mkdir candidates_report/
else
 rm -f candidates_report/*
fi

echo "<HTML><center>" > candidates_report/index.html

while read LCFILE NAME ;do

if [ ! -f $LCFILE ];then
 echo "ERROR: cannot open file $LCFILE"
 continue
fi

echo "Preparing report for the candidate $LCFILE $NAME"
echo "<center><h3>$LCFILE &nbsp;&nbsp;&nbsp;&nbsp;&nbsp; $NAME</h3></center>" >> candidates_report/index.html

# Make a finding chart
while read JD MAG ERR X Y AP IMAGEFILE REST ;do
 # Make plot only if the filename is foun
 if [ ! -z $IMAGEFILE ];then
  # And the file exist
  if [ -f $IMAGEFILE ];then
   util/make_finding_chart $IMAGEFILE $X $Y $AP &>/dev/null && mv pgplot.png candidates_report/"$LCFILE"_chart.png
   IMAGEFILE_TRUE_PATH=`readlink -f $IMAGEFILE`
   echo "<a href=\"file://$IMAGEFILE_TRUE_PATH\"><img src=\""$LCFILE"_chart.png\"></img></a>" >> candidates_report/index.html
   #echo "<br><a href=\"file://$IMAGEFILE_TRUE_PATH\">$IMAGEFILE</a><br>" >> candidates_report/index.html
  fi
 fi
 break # we are reaing only the first line
done < $LCFILE



# Make lightcurve plot
LCFILE_TRUE_PATH=`readlink -f $LCFILE`
START_DATE=`head -n1 $LCFILE | awk '{printf "%.0f",$1}'`
echo "set term png size 600,$PGPLOT_PNG_HEIGHT medium
$COLOR_SCHEME_COMMAND
set output \"candidates_report/"$LCFILE"_lc.png\"
set xlabel \"JD-$START_DATE\"
set ylabel \"mag\"
set format y \"%5.2f\"
set yrange [] reverse
plot \"$LCFILE\" using (\$1-$START_DATE):2 linecolor 2 pointtype 5 pointsize 0.7  title ''" | gnuplot

if [ -f candidates_report/"$LCFILE"_lc.png ];then
 echo "<a href=\"file://$LCFILE_TRUE_PATH\"><img src=\""$LCFILE"_lc.png\"></img></a>" >> candidates_report/index.html
else
 echo "ERROR plotting the lightcurve file candidates_report/"$LCFILE"_lc.png"
 exit
fi

# Make index plots
if [ -f vast_lightcurve_statistics.log ];then
 grep $LCFILE vast_lightcurve_statistics.log > var.tmp
 if [ $? -ne 0 ];then
  echo "WARNING: $LCFILE is not found in vast_lightcurve_statistics.log"
  echo "<br><hr>" >> candidates_report/index.html
  continue
 fi
 echo "set term png size 600,$PGPLOT_PNG_HEIGHT medium
$COLOR_SCHEME_COMMAND
set output \"candidates_report/"$LCFILE"_STD.png\"
set xlabel \"mag\"
set ylabel \"sigma\"
set format y \"%5.2f\"
plot \"vast_lightcurve_statistics.log\" using 1:2 linecolor 1 pointtype 6 pointsize 0.3  title '', 'var.tmp' using 1:2 linecolor 3 pointtype 3 pointsize 1.5 title ''" | gnuplot
 if [ -f candidates_report/"$LCFILE"_STD.png ];then
  echo "<img src=\""$LCFILE"_STD.png\"></img>" >> candidates_report/index.html
 else
  echo "ERROR while plotting the file "$LCFILE"_wSTD.png"
  exit
 fi
 echo "set term png size 600,$PGPLOT_PNG_HEIGHT medium
$COLOR_SCHEME_COMMAND
set output \"candidates_report/"$LCFILE"_MAD.png\"
set xlabel \"mag\"
set ylabel \"MAD\"
set format y \"%5.2f\"
plot \"vast_lightcurve_statistics.log\" using 1:14 linecolor 1 pointtype 6 pointsize 0.3  title '', 'var.tmp' using 1:14 linecolor 3 pointtype 3 pointsize 1.5 title ''" | gnuplot
 if [ -f candidates_report/"$LCFILE"_MAD.png ];then
  echo "<img src=\""$LCFILE"_MAD.png\"></img>" >> candidates_report/index.html
 else
  echo "ERROR while plotting the file "$LCFILE"_wSTD.png"
  exit
 fi
 echo "set term png size 600,$PGPLOT_PNG_HEIGHT medium
$COLOR_SCHEME_COMMAND
set output \"candidates_report/"$LCFILE"_Ltim.png\"
set xlabel \"mag\"
set ylabel \"L(time)\"
set format y \"%5.2f\"
plot \"vast_lightcurve_statistics.log\" using 1:23 linecolor 1 pointtype 6 pointsize 0.3  title '', 'var.tmp' using 1:23 linecolor 3 pointtype 3 pointsize 1.5 title ''" | gnuplot
 if [ -f candidates_report/"$LCFILE"_Ltim.png ];then
  echo "<img src=\""$LCFILE"_Ltim.png\"></img>" >> candidates_report/index.html
 else
  echo "ERROR while plotting the file "$LCFILE"_wSTD.png"
  exit
 fi
 echo "set term png size 600,$PGPLOT_PNG_HEIGHT medium
$COLOR_SCHEME_COMMAND
set output \"candidates_report/"$LCFILE"_eta.png\"
set xlabel \"mag\"
set ylabel \"1/eta\"
set format y \"%5.2f\"
plot \"vast_lightcurve_statistics.log\" using 1:26 linecolor 1 pointtype 6 pointsize 0.3  title '', 'var.tmp' using 1:26 linecolor 3 pointtype 3 pointsize 1.5 title ''" | gnuplot
 if [ -f candidates_report/"$LCFILE"_eta.png ];then
  echo "<img src=\""$LCFILE"_eta.png\"></img>" >> candidates_report/index.html
 else
  echo "ERROR while plotting the file "$LCFILE"_wSTD.png"
  exit
 fi
 
fi


echo "<br><hr>" >> candidates_report/index.html

done < vast_autocandidates.log

echo "</center></HTML>" >> candidates_report/index.html
