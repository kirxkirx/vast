#!/usr/bin/env bash

# load the raw data
util/load.sh ../OGLE2__PSF_LMC_SC20_Pgood98_VaST/

# remove edited lightcurves (keep only the original ones)
rm -f out*edit.dat

# save a local copy, just in case
if [ -d SIMULATOR_reference ];then
 # Remove any possible remains of a previous simulator run
 rm -rf SIMULATOR_reference
fi
util/save.sh SIMULATOR_reference

#
if [ -d simulation_results ];then
 rm -f simulation_results/*
else
 mkdir simulation_results
fi

ITERATION=1
while [ $ITERATION -le 1000 ] ;do
 # load data
 util/load.sh SIMULATOR_reference

 # If there is a file with known variables
 if [ -f vast_autocandidates.log ];then
  # Remove known variables
  while read OUTFILE REST ;do
   rm -f $OUTFILE
  done < vast_autocandidates.log
  rm -f vast_autocandidates.log
 fi

 # Insert artificial sine variability
 for OUTFILE in out*.dat ;do
  lib/sine_wave_simulator "$OUTFILE" && echo "$OUTFILE" >> vast_autocandidates.log
  # lib/lightcurve_simulator "$OUTFILE" && echo "$OUTFILE" >> vast_autocandidates.log
 done

 #util/examples/detection_efficiency_v02.sh
 util/examples/detection_efficiency_v04.sh
 
 ITER_STR=`echo $ITERATION | awk '{printf "%06d",$1}'`
 
 cp vast_detection_efficiency.log simulation_results/ITERATION"$ITER_STR"_vast_detection_efficiency.log

 ITERATION=$((ITERATION+1))
done

