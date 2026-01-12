#!/usr/bin/env bash

#if [ ! -d simulations_compare_variability_indices_results ];then
# mkdir simulations_compare_variability_indices_results
#fi

for FILE_TO_REMOVE in simulations__* ;do
 if [ -f "$FILE_TO_REMOVE" ];then
  rm -f "$FILE_TO_REMOVE"
 fi
done

#AMPLITUDE=0.05
#N_LIGHTCURVE_POINTS=100

for AMPLITUDE in 0.1 0.2 0.5 1.0 ;do
#for AMPLITUDE in 0.01 ;do


N_LIGHTCURVE_POINTS=2
while [ $N_LIGHTCURVE_POINTS -le 200 ] ;do

#for N_LIGHTCURVE_POINTS in 178 179 180 181 ;do

#################
# Reformat
AMPLITUDE=`echo $AMPLITUDE | awk '{printf "%5.3f",$1}'`
N_LIGHTCURVE_POINTS_STR=`echo $N_LIGHTCURVE_POINTS | awk '{printf "%04d",$1}'`
#################

# Remove any old data
util/clean_data.sh

# Simulate lightcurves
lib/noise_lightcurve_simulator $N_LIGHTCURVE_POINTS

# compute stats for noise-only lightcurves
util/nopgplot.sh
cp vast_lightcurve_statistics.log simulations__noise-only__"$N_LIGHTCURVE_POINTS_STR"__"$AMPLITUDE"__vast_lightcurve_statistics.log

echo -n "$N_LIGHTCURVE_POINTS_STR " >> simulations__"$AMPLITUDE"__N__idx01_wSTD.txt
echo -n "$N_LIGHTCURVE_POINTS_STR " >> simulations__"$AMPLITUDE"__N__idx09_MAD.txt
echo -n "$N_LIGHTCURVE_POINTS_STR " >> simulations__"$AMPLITUDE"__N__idx14_Vp2p.txt
echo -n "$N_LIGHTCURVE_POINTS_STR " >> simulations__"$AMPLITUDE"__N__idx25_IQR.txt
echo -n "$N_LIGHTCURVE_POINTS_STR " >> simulations__"$AMPLITUDE"__N__idx17_Jtim.txt
echo -n "$N_LIGHTCURVE_POINTS_STR " >> simulations__"$AMPLITUDE"__N__idx21_eta.txt
echo -n "$N_LIGHTCURVE_POINTS_STR " >> simulations__"$AMPLITUDE"__N__idx23_S_B.txt
echo -n "$N_LIGHTCURVE_POINTS_STR " >> simulations__"$AMPLITUDE"__N__idx11_RoMS.txt

# Extract stats on the index before injecting variability
# idx01_wSTD
cat vast_lightcurve_statistics.log | awk '{print $6}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo -n "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx01_wSTD.txt
# idx09_MAD
cat vast_lightcurve_statistics.log | awk '{print $14}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo -n "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx09_MAD.txt
# idx14_Vp2p
cat vast_lightcurve_statistics.log | awk '{print $19}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo -n "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx14_Vp2p.txt
# idx25_IQR
cat vast_lightcurve_statistics.log | awk '{print $30}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo -n "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx25_IQR.txt
# idx17_Jtim
cat vast_lightcurve_statistics.log | awk '{print $22}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo -n "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx17_Jtim.txt
# idx21_eta
cat vast_lightcurve_statistics.log | awk '{print $26}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo -n "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx21_eta.txt
# idx23_S_B
cat vast_lightcurve_statistics.log | awk '{print $28}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo -n "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx23_S_B.txt
# idx11_RoMS
cat vast_lightcurve_statistics.log | awk '{print $16}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo -n "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx11_RoMS.txt

# Inject artificial variability
for i in out*.dat ;do 
 lib/lightcurve_simulator $i $AMPLITUDE
done

# compute stats for variability lightcurves
util/nopgplot.sh
cp vast_lightcurve_statistics.log simulations__variability__"$N_LIGHTCURVE_POINTS_STR"__"$AMPLITUDE"__vast_lightcurve_statistics.log

# Extract stats on the index after injecting variability
# idx01_wSTD
cat vast_lightcurve_statistics.log | awk '{print $6}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx01_wSTD.txt
# idx09_MAD
cat vast_lightcurve_statistics.log | awk '{print $14}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx09_MAD.txt
# idx14_Vp2p
cat vast_lightcurve_statistics.log | awk '{print $19}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx14_Vp2p.txt
# idx25_IQR
cat vast_lightcurve_statistics.log | awk '{print $30}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx25_IQR.txt
# idx17_Jtim
cat vast_lightcurve_statistics.log | awk '{print $22}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx17_Jtim.txt
# idx21_eta
cat vast_lightcurve_statistics.log | awk '{print $26}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx21_eta.txt
# idx23_S_B
cat vast_lightcurve_statistics.log | awk '{print $28}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx23_S_B.txt
# idx11_RoMS
cat vast_lightcurve_statistics.log | awk '{print $16}' | util/colstat | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script.tmp
. script.tmp
echo "$MEDIAN $MADx148 " >> simulations__"$AMPLITUDE"__N__idx11_RoMS.txt
rm -f script.tmp

N_LIGHTCURVE_POINTS=$((N_LIGHTCURVE_POINTS+1))
done

done
