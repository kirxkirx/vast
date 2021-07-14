#!/usr/bin/env bash

PMAX=10.0
PMIN=0.1
PHASESTEP=0.001

ITERATIONS=1000

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ -z $1 ];then
 echo "Usage: $0 out12345.dat"
 exit 1
fi

INPUT_LIGHTCURVEFILE=$1

if [ ! -f $INPUT_LIGHTCURVEFILE ];then
 echo "ERROR: cannot open the input lightcurve file $INPUT_LIGHTCURVEFILE"
 exit 1
fi

echo "Checking if 'sort' understands the '--random-sort' option..."
echo -en "1\n2\n3\n" | sort --random-sort >/dev/null
if [ $? -ne 0 ];then
 echo "NO"
 echo "Unfortunately, sort does not understand the option '--random-sort'"
 exit 1
else
 echo "Yes"
fi


## This function will set the random session key in attempt to avoid 
## file collisions if other instances of the script are running at the same time.
function set_session_key {
 if [ -r /dev/urandom ];then
  local RANDOMFILE=/dev/urandom
 elif [ -r /dev/random ];then
  local RANDOMFILE=/dev/random
 else
  echo "ERROR: cannot find /dev/random" 1>&2
  local RANDOMFILE=""
 fi
 if [ "$RANDOMFILE" != "" ];then
  local SESSION_KEY="$$"_`tr -cd a-zA-Z0-9 < $RANDOMFILE | head -c 12`
 else
  local SESSION_KEY="$$"
 fi
 echo "$SESSION_KEY"
}

SESSION_KEY=$(set_session_key)

cp $INPUT_LIGHTCURVEFILE input_lightcurve_$SESSION_KEY.dat
cat input_lightcurve_$SESSION_KEY.dat | awk '{print " "$2}' > ordered_mag_$SESSION_KEY.dat

HIGHEST_PEAK=`lib/deeming_compute_periodogram input_lightcurve_$SESSION_KEY.dat $PMAX $PMIN $PHASESTEP | awk '{print $2}'`
HIGHEST_FAKE_PEAK=$HIGHEST_PEAK
N_PEAKS_ABOVE_THE_HIGHEST_PEAK=0;
for ITERATION in `seq 1 $ITERATIONS` ;do
 cat input_lightcurve_$SESSION_KEY.dat | awk '{print $1 }' | sort --random-sort > randomized_JD_$SESSION_KEY.dat
 #sort --random-sort input_lightcurve_$SESSION_KEY.dat > current_lightcurve_$SESSION_KEY.dat
 # <&3 tells bash to read a file at descriptor 3.
 # You would be aware that 0, 1 and 2 descriptors are used by Stdin, Stdout and Stderr.
 # So we should avoid using those. Also, descriptors after 9 are used by bash internally
 # so you can use any one from 3 to 9. 
 while read A && read STR <&3 ;do
  echo "$STR" "$A"
 done < ordered_mag_$SESSION_KEY.dat 3< randomized_JD_$SESSION_KEY.dat > current_lightcurve_$SESSION_KEY.dat

 PEAK=`lib/deeming_compute_periodogram current_lightcurve_$SESSION_KEY.dat $PMAX $PMIN $PHASESTEP | awk '{print $2}'`
 #TEST=`echo "$PEAK>=$HIGHEST_PEAK" | bc -ql`
 TEST=`echo "$PEAK<$HIGHEST_PEAK" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
 #if [ $TEST -eq 1 ];then
 if [ $TEST -eq 0 ];then
  N_PEAKS_ABOVE_THE_HIGHEST_PEAK=$[$N_PEAKS_ABOVE_THE_HIGHEST_PEAK+1]
  #TEST=`echo "$PEAK>=$HIGHEST_FAKE_PEAK" | bc -ql`
  TEST=`echo "$PEAK<$HIGHEST_FAKE_PEAK" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
  #if [ $TEST -eq 1 ];then
  if [ $TEST -eq 0 ];then
   cp current_lightcurve_$SESSION_KEY.dat shuffled_lightcurve.txt
   echo "Saving the best (or the worst) shuffled lightcurve in shuffled_lightcurve.txt"
  fi
 fi
 #FRACTION_OF_PEAKS_ABOVE_THE_HIGHEST_PEAK=`echo "$N_PEAKS_ABOVE_THE_HIGHEST_PEAK/$ITERATION" | bc -ql`
 FRACTION_OF_PEAKS_ABOVE_THE_HIGHEST_PEAK=`echo "$N_PEAKS_ABOVE_THE_HIGHEST_PEAK $ITERATION" | awk '{print $1/$2}'`
 echo "$FRACTION_OF_PEAKS_ABOVE_THE_HIGHEST_PEAK  $N_PEAKS_ABOVE_THE_HIGHEST_PEAK out of $ITERATION peaks are above the original highest peak of $HIGHEST_PEAK (current peak: $PEAK ). N iterations: $ITERATIONS"
done

FRACTION_OF_PEAKS_ABOVE_THE_HIGHEST_PEAK=`echo "$FRACTION_OF_PEAKS_ABOVE_THE_HIGHEST_PEAK" | awk '{printf "%.6f",$1}'`
echo "################## Final results ##################"
echo "$FRACTION_OF_PEAKS_ABOVE_THE_HIGHEST_PEAK  $N_PEAKS_ABOVE_THE_HIGHEST_PEAK out of $ITERATIONS peaks are above the original highest peak of $HIGHEST_PEAK"

rm -f input_lightcurve_$SESSION_KEY.dat current_lightcurve_$SESSION_KEY.dat randomized_JD_$SESSION_KEY.dat ordered_mag_$SESSION_KEY.dat

