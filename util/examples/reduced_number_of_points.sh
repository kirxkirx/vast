#!/usr/bin/env bash

TOTAL_TIME_START_UNIXSEC=`date -u +%s`

# load the raw data
util/load.sh ../comparing_varaibility_detection_indexes/data/OGLE2/OGLE2__PSF_LMC_SC20_Pgood98_VaST

# remove edited lightcurves (keep only the original ones)
rm -f out*edit.dat

# save a local copy, just in case
if [ -d SIMULATOR_reference ];then
 # Remove any possible remains of a previous simulator run
 rm -rf SIMULATOR_reference
fi
util/save.sh SIMULATOR_reference

for N_POINTS in `seq 2 300` ;do

N_POINTS_STR=`echo $N_POINTS | awk '{printf "%04d",$1}'`

#
SIMULATION_RESULTS_DIR=simulation_results_$N_POINTS_STR
#
if [ -d $SIMULATION_RESULTS_DIR ];then
 rm -f $SIMULATION_RESULTS_DIR/*
else
 mkdir $SIMULATION_RESULTS_DIR
fi

for ITERATION in `seq 1 10` ;do

 ITERATION_TIME_START_UNIXSEC=`date -u +%s`

 # load data
 util/load.sh SIMULATOR_reference
 
 lib/select_only_n_random_points_from_set_of_lightcurves $N_POINTS

 util/examples/detection_efficiency_v02.sh
 #util/examples/detection_efficiency_v04.sh
 
 ITER_STR=`echo $ITERATION | awk '{printf "%06d",$1}'`
 
 cp vast_detection_efficiency.log $SIMULATION_RESULTS_DIR/ITERATION"$ITER_STR"_vast_detection_efficiency.log
 
 ITERATION_TIME_STOP_UNIXSEC=`date -u +%s`
 
 ITERATION_TIME_MINUTES=`echo "($ITERATION_TIME_STOP_UNIXSEC-$ITERATION_TIME_START_UNIXSEC)/60" | bc -ql | awk '{printf "%.3f",$1}'`
 
 echo "#### Completed iteration $ITER_STR in $ITERATION_TIME_MINUTES minutes ####"

done

done # for N_POINTS in `seq 2 300` ;do

TOTAL_TIME_STOP_UNIXSEC=`date -u +%s`
TOTAL_TIME_RUNNING_DAYS=`echo "($TOTAL_TIME_STOP_UNIXSEC-$TOTAL_TIME_START_UNIXSEC)/86400" | bc -ql | awk '{printf "%.3f",$1}'`

echo "Analysis complete! Total running time: $TOTAL_TIME_RUNNING_DAYS days"

