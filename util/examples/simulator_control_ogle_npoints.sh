#!/usr/bin/env bash

# load the raw data
#util/load.sh ../OGLE2__PSF_LMC_SC20_Pgood98_VaST
util/load.sh ../OGLE2__PSF_LMC_SC20_Pgood98_VaST_corrected_list_of_variables

# remove edited lightcurves (keep only the original ones)
rm -f out*edit.dat

# save a local copy, just in case
if [ -d SIMULATOR_reference ];then
 # Remove any possible remains of a previous simulator run
 rm -rf SIMULATOR_reference
fi
util/save.sh SIMULATOR_reference

for N_POINTS in `seq 2 260` ;do
#for N_POINTS in `seq 201 265` ;do

#
if [ -d simulation_results ];then
 rm -f simulation_results/*
else
 mkdir simulation_results
fi

for OLDDIR in reduced_N_points_* ;do
 if [ -d "$OLDDIR/" ];then
  rm -rf "$OLDDIR"
 fi
done


#for ITERATION in `seq 1 1000` ;do
for ITERATION in `seq 1 100` ;do
 # load data
 util/load.sh SIMULATOR_reference
 
 lib/select_only_n_random_points_from_set_of_lightcurves $N_POINTS

 ## If there is a file with known variables
 #if [ -f vast_autocandidates.log ];then
 # # Remove known variables
 # while read OUTFILE REST ;do
 #  rm -f $OUTFILE
 # done < vast_autocandidates.log
 # rm -f vast_autocandidates.log
 #fi

 ## Insert artificial sine variability
 #for OUTFILE in out*.dat ;do
 # #lib/sine_wave_simulator "$OUTFILE" && echo "$OUTFILE" >> vast_autocandidates.log
 # lib/lightcurve_simulator "$OUTFILE" && echo "$OUTFILE" >> vast_autocandidates.log
 #done

 util/examples/detection_efficiency_v02.sh
 #util/examples/detection_efficiency_v04.sh
 
 ITER_STR=`echo $ITERATION | awk '{printf "%06d",$1}'`
 
 cp vast_detection_efficiency.log simulation_results/ITERATION"$ITER_STR"_vast_detection_efficiency.log

done

mv simulation_results reduced_N_points_"$N_POINTS"_simulation_results

done # N_POINTS

