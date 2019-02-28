#!/usr/bin/env bash

######### BLS parameters #########
export BLS_MIN_FRACTIONAL_TRANSIT_DURATION=0.01
export BLS_MAX_FRACTIONAL_TRANSIT_DURATION=0.1
export BLS_PMIN_DAYS=0.1
export BLS_PMAX_DAYS=2.0
export BLS_NFREQ=100000
export BLS_NPHASEBINS=200
#
export BLS_SNR_CUTOFF=50.0
export BLS_MAX_LIGHTCURVE_RMS=0.05
##################################
SCRIPTNAME=`basename $0 .sh`
#

function set_number_of_threads {
 # Uncomment to disable multithreading
 #echo "1"
 #return 0
 #
 
 local DEFAULT_NUMBER_OF_THREADS=4

 SYSTEM_TYPE=`uname`
 if [ "$SYSTEM_TYPE" = "Linux" ];then
  NUMBER_OF_THREADS=`cat /proc/cpuinfo | grep -c 'processor'`
 else
  NUMBER_OF_THREADS=`sysctl -a | grep "hw.ncpu" | awk '{print $2}'`
 fi

 # If $OMP_NUM_THREADS is set - stick with this value
 if [ ! -z "$OMP_NUM_THREADS" ];then
  NUMBER_OF_THREADS="$OMP_NUM_THREADS"
 fi
 
 # check that NUMBER_OF_THREADS is areasonable number
 if [ -z "$NUMBER_OF_THREADS" ];then
  NUMBER_OF_THREADS=$DEFAULT_NUMBER_OF_THREADS
 fi
 TEST=`echo "$NUMBER_OF_THREADS > 0" | bc -q 2>/dev/null`
 re='^[0-9]+$'
 if ! [[ $TEST =~ $re ]] ; then
  NUMBER_OF_THREADS=$DEFAULT_NUMBER_OF_THREADS
 elif [ $TEST -eq 0 ];then
  NUMBER_OF_THREADS=$DEFAULT_NUMBER_OF_THREADS
 fi
 
 echo "$NUMBER_OF_THREADS"
 
 return 0;
}

## This function will set the random session key in attempt to avoid 
## file collisions if other instances of the script are running at the same time.
function set_session_key {
 if [ -r /dev/urandom ];then
  local RANDOMFILE=/dev/urandom
 elif [ -r /dev/random ];then  
  local RANDOMFILE=/dev/random
 else
  echo "ERROR: cannot find /dev/random" >> /dev/stderr
  local RANDOMFILE=""
 fi
 if [ "$RANDOMFILE" != "" ];then
  local SESSION_KEY="$$"_`tr -cd a-zA-Z0-9 < $RANDOMFILE | head -c 12`
 else
  local SESSION_KEY="$$"
 fi
 echo "$SESSION_KEY"
}

function function_to_fork {
 local LIGHTCURVEFILE=$1
 if [ ! -s "$LIGHTCURVEFILE" ];then
  echo "Skipping the lightcurve file $LIGHTCURVEFILE" >> /dev/stderr
  return 0;
 fi
 echo "Processing lightcurve $LIGHTCURVEFILE" >> /dev/stderr
 local BLS_SNR=`vartools -i "$LIGHTCURVEFILE" -ascii -oneline  -clip 3.0 0    -BLS q $BLS_MIN_FRACTIONAL_TRANSIT_DURATION $BLS_MAX_FRACTIONAL_TRANSIT_DURATION $BLS_PMIN_DAYS $BLS_PMAX_DAYS $BLS_NFREQ $BLS_NPHASEBINS 0 1         0 0 0 fittrap | grep BLS_SN | awk '{printf "%.2f",$3}'`
 echo "$LIGHTCURVEFILE $BLS_SNR" >> run_vartools_bls_results/run_vartools_bls.out
 echo "$LIGHTCURVEFILE $BLS_SNR" >> /dev/stderr
 TEST=`echo "$BLS_SNR>$BLS_SNR_CUTOFF" | bc -ql`
 if [ $TEST -eq 1 ];then
  # Recompute and plot
  #vartools -i "$LIGHTCURVEFILE" -ascii -oneline  -clip 3.0 0   -BLS q $BLS_MIN_FRACTIONAL_TRANSIT_DURATION $BLS_MAX_FRACTIONAL_TRANSIT_DURATION $BLS_PMIN_DAYS $BLS_PMAX_DAYS $BLS_NFREQ $BLS_NPHASEBINS 0 1         1 run_vartools_bls_results/ 1 run_vartools_bls_results/ 0 fittrap        ophcurve run_vartools_bls_results/ -0.1 1.1 0.001 > run_vartools_bls_results/"$LIGHTCURVEFILE".bls.summary
  vartools -i "$LIGHTCURVEFILE" -ascii -oneline  -clip 3.0 0   -BLS q $BLS_MIN_FRACTIONAL_TRANSIT_DURATION $BLS_MAX_FRACTIONAL_TRANSIT_DURATION $BLS_PMIN_DAYS $BLS_PMAX_DAYS $BLS_NFREQ $BLS_NPHASEBINS 0 1         0 1 run_vartools_bls_results/ 0 fittrap        ophcurve run_vartools_bls_results/ -0.1 1.1 0.001 > run_vartools_bls_results/"$LIGHTCURVEFILE".bls.summary
  cd run_vartools_bls_results/
  local BLS_Period=`grep BLS_Period "$LIGHTCURVEFILE".bls.summary | head -n1 | awk '{printf "%.7f",$3}'`
  # Reject period that are likely to be daily aliases
  TEST=`echo "a=$BLS_Period-0.5;sqrt(a*a)<0.05" | bc -ql`
  if [ $TEST -eq 1 ];then
   rm -f "$LIGHTCURVEFILE".bls*
   return 0
  fi
  TEST=`echo "a=$BLS_Period-1.0;sqrt(a*a)<0.05" | bc -ql`
  if [ $TEST -eq 1 ];then
   rm -f "$LIGHTCURVEFILE".bls*
   return 0
  fi
  TEST=`echo "a=$BLS_Period-1.5;sqrt(a*a)<0.05" | bc -ql`
  if [ $TEST -eq 1 ];then
   rm -f "$LIGHTCURVEFILE".bls*
   return 0
  fi
  TEST=`echo "a=$BLS_Period-2.0;sqrt(a*a)<0.05" | bc -ql`
  if [ $TEST -eq 1 ];then
   rm -f "$LIGHTCURVEFILE".bls*
   return 0
  fi
  #
  local BLS_Tc=`grep BLS_Tc "$LIGHTCURVEFILE".bls.summary | awk '{printf "%.5f",$3}'` 
  local GNUPLOTFILENAME="$LIGHTCURVEFILE".bls.model.gnuplot
  local EPSFILENAME="$LIGHTCURVEFILE".bls.model.eps
  local PNGFILENAME="$LIGHTCURVEFILE".bls.model.png
  local BLSMODELFILENAME="$LIGHTCURVEFILE".bls.model
  local STARNAME=${LIGHTCURVEFILE//.dat/}
  STARNAME=${STARNAME//out/}
  echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output '$EPSFILENAME'
set xlabel 'phase'
set ylabel 'm'
set title '$STARNAME    $BLS_Tc + $BLS_Period x E   SNR=$BLS_SNR'
set yrange [] reverse
plot '$BLSMODELFILENAME' u (\$5 > 0.5 ? \$5-1:\$5):2 title '', '$BLSMODELFILENAME' u (\$5 > 0.5 ? \$5-1:\$5):3 title ''
!convert -density 150 $EPSFILENAME  -background white -alpha remove $PNGFILENAME
" > "$GNUPLOTFILENAME"
  gnuplot "$GNUPLOTFILENAME"
  cd "$WORKDIR"
 fi
 
 return 0
}


########## Main script ##########
# Check the necessary programs
command -v vartools &>/dev/null
if [ $? -ne 0 ];then
 echo "Please install vartools" >> /dev/stderr
 exit 1
fi
command -v gnuplot &>/dev/null
if [ $? -ne 0 ];then
 echo "Please install gnuplot" >> /dev/stderr
 exit 1
fi
command -v convert &>/dev/null
if [ $? -ne 0 ];then
 echo "Please install convert (imagemagick)" >> /dev/stderr
 exit 1
fi

# Clean-up the output directory
if [ -d run_vartools_bls_results ];then
 rm -rf run_vartools_bls_results/
fi
mkdir run_vartools_bls_results

# Set session key
export SESSION_KEY=$(set_session_key) # or SESSION_KEY=`set_session_key`        
# Remember the current path
export WORKDIR="$PWD"
# Set the number of threads
NUMBER_OF_THREADS=$(set_number_of_threads)

# Check the input files and create them if needed
if [ ! -f vast_list_of_likely_constant_stars.log ];then
 util/nopgplot.sh
 if [ $? -ne 0 ];then
  exit 1
 fi
fi
if [ ! -f vast_lightcurve_statistics.log ];then
 util/nopgplot.sh
 if [ $? -ne 0 ];then
  exit 1
 fi
fi

# Go through all the lightcurves satisfying selection criterea
for LIGHTCURVEFILE in `cat vast_list_of_likely_constant_stars.log` ;do
 LIGHTCURVEFILE_RMS=`grep "$LIGHTCURVEFILE" vast_lightcurve_statistics.log | awk '{print $2}'`
 TEST=`echo "$LIGHTCURVEFILE_RMS>$BLS_MAX_LIGHTCURVE_RMS" |bc -ql`
 if [ $TEST -eq 1 ];then
  continue
 fi
 # Go multithread
 function_to_fork "$LIGHTCURVEFILE" &
 PIDS="$PIDS $! "
 NPROC=$[$NPROC+1]
 while [ $NPROC -gt $[$NUMBER_OF_THREADS-1] ] ;do
  # check each running process
  #echo "$PIDS"
  for PID in $PIDS ;do
   ps -p $PID &> /dev/null
   if [ $? -ne 0 ];then   
    PIDS=${PIDS/" $PID "/}
    NPROC=$[$NPROC-1]
   fi
  done
  sleep 0.01
 done
 # Now we are sure no more than NUMBER_OF_THREADS processes are runnning
 echo "$PIDS" > /tmp/"$SCRIPTNAME"_"$SESSION_KEY"_pids.tmp
done

# Wait for the remeining processes to finish
for PID in `cat /tmp/"$SCRIPTNAME"_"$SESSION_KEY"_pids.tmp` ;do
 while true ;do
  ps -p $PID &> /dev/null
  if [ $? -ne 0 ];then   
   break
  fi
  sleep 0.01
 done
done 
# In case something above fails...
wait
rm -f /tmp/"$SCRIPTNAME"_"$SESSION_KEY"_pids.tmp &


echo "#####################" >> /dev/stderr
NCANDIDATES=0
for CANDIDATE in run_vartools_bls_results/*.bls.summary ;do
 grep `basename "$CANDIDATE" .bls.summary` run_vartools_bls_results/run_vartools_bls.out >> /dev/stderr
 NCANDIDATES=$[$NCANDIDATES+1]
done
echo "#####################
Identified $NCANDIDATES transit candidates.

The results are written to run_vartools_bls_results/
" >> /dev/stderr
