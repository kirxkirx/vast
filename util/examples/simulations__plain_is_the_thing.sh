#!/usr/bin/env bash

AMPLITUDE_MAG=1.0

#PERIOD_DAYS=0.15214325

for PERIOD_DAYS in 0.15214325 0.215777125 0.40270300 1.53644566666667 3.30190879166667 ;do
 SIM_FREQ_CPD=`echo "$PERIOD_DAYS" | awk '{printf "%.10lf", 1/$1}'`
 
 # remove any old simulations
 util/clean_data.sh

 # Simulate noise lightcurves
 lib/noise_lightcurve_simulator

 rm -f simulations_results_P"$PERIOD_DAYS"d.txt
 
 for OUTFILE in out*.dat ;do
  lib/sine_wave_simulator $OUTFILE $AMPLITUDE_MAG $PERIOD_DAYS
  PERIOD_SEARCH_RESULT=`lib/deeming_compute_periodogram $OUTFILE 10 0.1 0.1`
  DFT_FREQ=`echo "$PERIOD_SEARCH_RESULT" | awk '{print $1}'`
  DFT_FREQ_FRAC_DIFF=`echo "$SIM_FREQ_CPD $DFT_FREQ" | awk '{printf "%+.10lf", ($1-$2)/$1}'`
  echo "$SIM_FREQ_CPD $DFT_FREQ  $DFT_FREQ_FRAC_DIFF  $OUTFILE $AMPLITUDE_MAG $PERIOD_DAYS" >> simulations_results_P"$PERIOD_DAYS"d.txt
 done

done
