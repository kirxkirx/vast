#!/usr/bin/env bash

# This script will get Gaia lightcurves from VizieR

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Check that the Gaia ID is set
if [ -z "$1" ];then
 echo "Usage:  $0 4064863289398606208
Here 4064863289398606208 is the Gaia DR2 ID" 1>&2
 exit 1
fi

GAIA_ID="$1"

# Check that the argument indeed looks like a Gaia DR2 ID
re='^[0-9]+$'
if ! [[ $GAIA_ID =~ $re ]] ; then
 echo "ERROR: $GAIA_ID doesn't look like a Gaia ID" 1>&2
 exit 1
fi

#TEST=`echo "$GAIA_ID>100000" | bc -ql`
TEST=`echo "$GAIA_ID>100000" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
if [ $TEST -ne 1 ];then
 echo "ERROR: $GAIA_ID doesn't look like a Gaia ID (the value looks suspiciously small)" 1>&2
 exit 1
fi

####################################################
# here goes the usual VaST script init chain

# A more portable realpath wrapper
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
      cd "$(dirname "$1")" || exit 1
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit 1
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

# Function to remove the last occurrence of a directory from a path
remove_last_occurrence() {
    echo "$1" | awk -F/ -v dir=$2 '{
        found = 0;
        for (i=NF; i>0; i--) {
            if ($i == dir && found == 0) {
                found = 1;
                continue;
            }
            res = (i==NF ? $i : $i "/" res);
        }
        print res;
    }'
}

# Function to get full path to vast main directory from the script name
get_vast_path_ends_with_slash_from_this_script_name() {
 VAST_PATH=$(vastrealpath $0)
 VAST_PATH=$(dirname "$VAST_PATH")

 # Remove last occurrences of util, lib, examples
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "util")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "lib")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "examples")

 # Make sure no '//' are left in the path (they look ugly)
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")

 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")

 # Check that VAST_PATH ends with '/'
 LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
 if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
  VAST_PATH="$VAST_PATH/"
 fi

 echo "$VAST_PATH"
}


if [ -z "$VAST_PATH" ];then
 VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
#
VIZIER_SITE=`"$VAST_PATH"lib/choose_vizier_mirror.sh`
#
TIMEOUTCOMMAND=`"$VAST_PATH"lib/find_timeout_command.sh`
if [ $? -ne 0 ];then
 echo "WARNING: cannot find timeout command" 1>&2
else
 TIMEOUTCOMMAND="$TIMEOUTCOMMAND 300 "
fi
####################################################

# Check if the output directory exist
if [ ! -d "$VAST_PATH"gaia_lightcurves ];then
 mkdir "$VAST_PATH"gaia_lightcurves
fi

if [ ! -s "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_G.txt ];then
 G_BAND_LIGHTCURVE=`$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/transits -out.max=1000 -out.form=mini Source="$GAIA_ID" -out=TimeG,Gmag,e_Gmag 2>/dev/null | grep -A 1000 'TimeG (d)' | grep -v -e 'Time' -e '\-\-\-'  -e '=======' -e '#INFO' | sed '/^\s*$/d' | awk '{printf "%.8f %9.6f %8.6f\n", $1+2455197.5, $2, $3}' | grep -v '2455197.5'`
 if [ $? -ne 0 ];then
  echo "ERROR running vizquery"
  exit 1
 fi
 if [ -z "$G_BAND_LIGHTCURVE" ];then
  echo "ERROR: the G_BAND_LIGHTCURVE is empty"
  exit 1
 fi
 echo "$G_BAND_LIGHTCURVE" > "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_G.txt
fi
echo "############### G band ###############"
cat "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_G.txt

if [ ! -s "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_BP.txt ];then
 BP_BAND_LIGHTCURVE=`$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/transits -out.max=1000 -out.form=mini Source="$GAIA_ID" -out=TimeBP,BPmag,e_BPmag 2>/dev/null | grep -A 1000 'TimeBP (d)' | grep -v -e 'Time' -e '\-\-\-'  -e '=======' -e '#INFO' | sed '/^\s*$/d' | awk '{printf "%.8f %9.6f %8.6f\n", $1+2455197.5, $2, $3}' | grep -v '2455197.5'`
 if [ $? -ne 0 ];then
  echo "ERROR running vizquery"
  exit 1
 fi
 if [ -z "$BP_BAND_LIGHTCURVE" ];then
  echo "ERROR: the BP_BAND_LIGHTCURVE is empty"
  exit 1
 fi
 echo "$BP_BAND_LIGHTCURVE" > "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_BP.txt
fi
echo "
############### BP band ###############"
cat "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_BP.txt

if [ ! -s "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_RP.txt ];then
 RP_BAND_LIGHTCURVE=`$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/transits -out.max=1000 -out.form=mini Source="$GAIA_ID" -out=TimeRP,RPmag,e_RPmag 2>/dev/null | grep -A 1000 'TimeRP (d)' | grep -v -e 'Time' -e '\-\-\-'  -e '=======' -e '#INFO' | sed '/^\s*$/d' | awk '{printf "%.8f %9.6f %8.6f\n", $1+2455197.5, $2, $3}' | grep -v '2455197.5'`
 if [ $? -ne 0 ];then
  echo "ERROR running vizquery"
  exit 1
 fi
 if [ -z "$RP_BAND_LIGHTCURVE" ];then
  echo "ERROR: the RP_BAND_LIGHTCURVE is empty"
  exit 1
 fi
 echo "$RP_BAND_LIGHTCURVE" > "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_RP.txt
fi
echo "
############### RP band ###############"
cat "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_RP.txt

# 
#./lc "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_G.txt

#exit 0

###### Plot Gaia lightcurve using gnuplot
command -v gnuplot &>/dev/null
if [ $? -eq 0 ];then
 JD0=`cat "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_G.txt "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_BP.txt "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_RP.txt | awk -F '.' '{print $1}' | sort | uniq | head -n 1`
 JD1=`cat "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_G.txt "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_BP.txt "$VAST_PATH"gaia_lightcurves/"$GAIA_ID"_RP.txt | awk -F '.' '{print $1}' | sort | uniq | tail -n 1`
# PLOT_MIN=`echo "-1*($JD1-$JD0)/10" | bc -ql | awk '{printf "%.1f",$1}'`
 PLOT_MIN=`echo "$JD1 $JD0" | awk '{printf "%.1f",($2-$1)/10}'`
# PLOT_MAX=`echo "($JD1-$JD0)+($JD1-$JD0)/10" | bc -ql | awk '{printf "%.1f",$1}'`
 PLOT_MAX=`echo "$JD1 $JD0" | awk '{printf "%.1f", $1 - $2 + ($1-$2)/10}'`

 cd "$VAST_PATH"gaia_lightcurves/
echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output '"$GAIA_ID".eps'
set xlabel 'JD-$JD0.0'
set ylabel 'm'
set yrange [] reverse
plot [$PLOT_MIN:$PLOT_MAX] \
'"$GAIA_ID"_G.txt' using (\$1-$JD0):2:3 with errorbars pointtype 7 pointsize 1.0 linecolor 'forest-green' title 'G', \
'"$GAIA_ID"_BP.txt' using (\$1-$JD0):2:3 with errorbars pointtype 7 pointsize 1.0 linecolor 'royalblue' title 'BP', \
'"$GAIA_ID"_RP.txt' using (\$1-$JD0):2:3 with errorbars pointtype 7 pointsize 1.0 linecolor 'red' title 'RP'
" > "$GAIA_ID".gnuplot
 gnuplot "$GAIA_ID".gnuplot
 command -v convert &>/dev/null
 if [ $? -eq 0 ];then
  convert -density 150 "$GAIA_ID".eps  -background white -alpha remove  "$GAIA_ID".png
 fi # command -v convert
fi # command -v gnuplot
