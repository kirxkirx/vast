#!/usr/bin/env bash

#FILE_WITH_FILEAMES_OF_KNOWN_VARS="vast_autocandidates.log"
FILE_WITH_FILEAMES_OF_KNOWN_VARS="vast_list_of_previously_known_variables.log"

####### Set color scheme for gnuplot 5.0 or above
GNUPLOT5_COLOR_SCHEME_COMMAND="set colors classic"
GNUPLOT5_DASHED_LINE_TYPE="dashtype 2"
GNUPLOT_VERSION=`gnuplot --version | awk '{print $2}' | awk '{print $1}' FS='.'`
if [ $GNUPLOT_VERSION -ge 5 ];then
 COLOR_SCHEME_COMMAND="$GNUPLOT5_COLOR_SCHEME_COMMAND"
 GNUPLOT5_DASHED_LINE_TYPE="dashtype 2"
else
 COLOR_SCHEME_COMMAND=""
 GNUPLOT5_DASHED_LINE_TYPE=""
fi
#######

# recompute stats, just in case we changed something in the code
util/nopgplot.sh

# 
while read A B ;do 
 grep $A vast_lightcurve_statistics.log
done < $FILE_WITH_FILEAMES_OF_KNOWN_VARS > vast_lightcurve_statistics_known_variables.log

# Compute the selection curves and stats
lib/index_vs_mag > vast_index_vs_mag.txt

# For each index...
for INDEX in idx00_STD idx01_wSTD idx02_skew idx03_kurt idx04_I idx05_J idx06_K idx07_L idx08_Npts idx09_MAD idx10_lag1 idx11_RoMS idx12_rCh2 idx13_Isgn idx14_Vp2p idx15_Jclp idx16_Lclp idx17_Jtim idx18_Ltim idx19_N3 idx20_excr idx21_eta idx22_E_A idx23_S_B idx24_NXS idx25_IQR ;do
 INDEX_NAME_FOR_TITLE=`echo "$INDEX" | awk '{print $2}' FS='_'`
 INDEX_NAME_FOR_TITLE_GNUPLOT="$INDEX_NAME_FOR_TITLE"
 if [ "$INDEX_NAME_FOR_TITLE" == "wSTD" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="{/Symbol s}_w"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "rCh2" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="{/Symbol c}^2_{red}"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "skew" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="skewness"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "kurt" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="kurtosis"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "excr" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="Excursions"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "eta" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="1/{/Symbol h}"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "S" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="S_B"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "E" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="E_A"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "N3" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="CSSD"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "Vp2p" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="peak-to-peak"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "lag1" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="l_1"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "Jclp" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="J(clip)"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "Lclp" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="L(clip)"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "Jtim" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="J(time)"
 fi
 if [ "$INDEX_NAME_FOR_TITLE" == "Ltim" ];then
  INDEX_NAME_FOR_TITLE_GNUPLOT="L(time)"
 fi

 grep "$INDEX" vast_index_vs_mag.txt > vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE".txt
 for PARAMETER in C P F Nvar Nobj ;do
  COLUMNS_FOR_GNUPLOT="1:3"
  if [ "$PARAMETER" == "C" ];then
   COLUMNS_FOR_GNUPLOT="1:3"
  elif [ "$PARAMETER" == "P" ];then
   COLUMNS_FOR_GNUPLOT="1:4"
  elif [ "$PARAMETER" == "F" ];then
   COLUMNS_FOR_GNUPLOT="1:5"
  elif [ "$PARAMETER" == "Nvar" ];then
   COLUMNS_FOR_GNUPLOT="1:6"
  elif [ "$PARAMETER" == "Nobj" ];then 
   COLUMNS_FOR_GNUPLOT="1:7"
  fi

  # Make the selection efficiency plots   
  echo "Making the selection efficiency plot $INDEX_NAME_FOR_TITLE $PARAMETER"
  echo "set terminal postscript eps enhanced color solid \"Times\" 24 linewidth 2.0
$GNUPLOT5_COLOR_SCHEME_COMMAND
set output \"vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE"_"$PARAMETER".eps\"
set title '$INDEX_NAME_FOR_TITLE'
set xlabel 'Cut-off in {/Symbol s}'
set ylabel '$PARAMETER'
plot \"vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE".txt\" u $COLUMNS_FOR_GNUPLOT title ''
" | gnuplot
 done

 STRING_FOR_CPF_PLOT_TITLE=`grep "$INDEX" vast_detection_efficiency.log | awk '{printf "C(F_{max})=%.3f   P(F_{max})=%.3f   F_{max}=%.3f   at %4.1f{/Symbol s}",$4,$5,$6,$2}'`
 STRING_SIGMA_FOR_MAG_PLOT=`grep "$INDEX" vast_detection_efficiency.log | awk '{printf "%.1f{/Symbol s}",$2}'`
 STRING_SIGMA_CMAX_FOR_MAG_PLOT=`grep "$INDEX" vast_detection_efficiency.log | awk '{printf "%.1f{/Symbol s}",$3}'`
 
 # Make a combined CPF plot
 echo "Making the combined selection efficiency plot $INDEX_NAME_FOR_TITLE CPF"
 echo "set terminal postscript eps enhanced color solid \"Times\" 24 linewidth 2.0
#$GNUPLOT5_COLOR_SCHEME_COMMAND
set output \"vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE"_CPF.eps\"
set title '$STRING_FOR_CPF_PLOT_TITLE'
set xlabel '$INDEX_NAME_FOR_TITLE_GNUPLOT cut-off in {/Symbol s}'
set ylabel ''
plot \"vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE".txt\" u 1:3 w l title 'C', \"vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE".txt\" u 1:4 w l title 'P', \"vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE".txt\" u 1:5 w l title 'F',
" | gnuplot

 
 # Make the index plots
  STRING_TO_SET_KEY_POSITION="set key top left"
  COLUMNS_FOR_GNUPLOT="1:2"
  if [ "$INDEX" == "idx00_STD" ];then
   COLUMNS_FOR_GNUPLOT="1:2"
  elif [ "$INDEX" == "idx01_wSTD" ];then
   COLUMNS_FOR_GNUPLOT="1:6"
  elif [ "$INDEX" == "idx02_skew" ];then
   COLUMNS_FOR_GNUPLOT="1:7"
  elif [ "$INDEX" == "idx03_kurt" ];then
   COLUMNS_FOR_GNUPLOT="1:8"
  elif [ "$INDEX" == "idx04_I" ];then 
   COLUMNS_FOR_GNUPLOT="1:9"
   STRING_TO_SET_KEY_POSITION="set key top right
set format y \"%g\"
set logscale y
set key bottom left"
  elif [ "$INDEX" == "idx05_J" ];then
   COLUMNS_FOR_GNUPLOT="1:10" 
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx06_K" ];then
   COLUMNS_FOR_GNUPLOT="1:11"
  elif [ "$INDEX" == "idx07_L" ];then
   COLUMNS_FOR_GNUPLOT="1:12"
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx08_Npts" ];then
   COLUMNS_FOR_GNUPLOT="1:13" 
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx09_MAD" ];then
   COLUMNS_FOR_GNUPLOT="1:14" 
  elif [ "$INDEX" == "idx10_lag1" ];then
   COLUMNS_FOR_GNUPLOT="1:15"
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx11_RoMS" ];then
   COLUMNS_FOR_GNUPLOT="1:16" 
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx12_rCh2" ];then
   COLUMNS_FOR_GNUPLOT="1:17" 
   STRING_TO_SET_KEY_POSITION="set key top right
set logscale y"
  elif [ "$INDEX" == "idx13_Isgn" ];then
   COLUMNS_FOR_GNUPLOT="1:18" 
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx14_Vp2p" ];then
   COLUMNS_FOR_GNUPLOT="1:19" 
  elif [ "$INDEX" == "idx15_Jclp" ];then
   COLUMNS_FOR_GNUPLOT="1:20" 
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx16_Lclp" ];then
   COLUMNS_FOR_GNUPLOT="1:21"
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx17_Jtim" ];then
   COLUMNS_FOR_GNUPLOT="1:22" 
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx18_Ltim" ];then
   COLUMNS_FOR_GNUPLOT="1:23"
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx19_N3" ];then
   COLUMNS_FOR_GNUPLOT="1:24" 
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx20_excr" ];then
   COLUMNS_FOR_GNUPLOT="1:25"
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx21_eta" ];then
   COLUMNS_FOR_GNUPLOT="1:26" 
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx22_E_A" ];then
   COLUMNS_FOR_GNUPLOT="1:27" 
   STRING_TO_SET_KEY_POSITION="set key top right"
  elif [ "$INDEX" == "idx23_S_B" ];then
   COLUMNS_FOR_GNUPLOT="1:28"
   STRING_TO_SET_KEY_POSITION="set key top right
set logscale y"
  elif [ "$INDEX" == "idx24_NXS" ];then
   COLUMNS_FOR_GNUPLOT="1:29"
   STRING_TO_SET_KEY_POSITION="set key top right
set format y \"%g\"
set logscale y
set key bottom left"
  elif [ "$INDEX" == "idx25_IQR" ];then          
   COLUMNS_FOR_GNUPLOT="1:30"  
   STRING_TO_SET_KEY_POSITION="set key top right"
  fi
 echo "Making $INDEX_NAME_FOR_TITLE_GNUPLOT vs. mag plot"
 echo "set terminal postscript eps enhanced color solid \"Times\" 24 linewidth 2.0
$GNUPLOT5_COLOR_SCHEME_COMMAND
set output \"vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE"_mag.eps\"
set xlabel 'mag.'
set ylabel '$INDEX_NAME_FOR_TITLE_GNUPLOT'
$STRING_TO_SET_KEY_POSITION
plot \"vast_lightcurve_statistics.log\" u $COLUMNS_FOR_GNUPLOT ps 0.75 pt 7 lc 'red' title '', \"vast_lightcurve_statistics_known_variables.log\" u $COLUMNS_FOR_GNUPLOT lc 'blue' title '', \"vast_lightcurve_statistics_expected.log\" u $COLUMNS_FOR_GNUPLOT w l lc 'black' $GNUPLOT5_DASHED_LINE_TYPE title '', \"vast_lightcurve_statistics_expected_plus_spread.log\" u $COLUMNS_FOR_GNUPLOT w l lc 'green' title 'F_{max} cut-off at $STRING_SIGMA_FOR_MAG_PLOT'
" > vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE"_mag.gnuplot
gnuplot vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE"_mag.gnuplot
 

done


util/examples/put_variable_and_nonvariable_objs_in_separate_files.sh

# And make some special plots
COLUMNS_FOR_GNUPLOT="1:30:26"
STRING_SIGMA_FOR_MAG_PLOT=`grep "idx25_IQR" vast_detection_efficiency.log | awk '{printf "%.1f{/Symbol s}",$2}'`
A=`grep "idx21_eta" vast_detection_efficiency.log | awk '{printf "%.1f{/Symbol s}",$2}'`
STRING_SIGMA_FOR_MAG_PLOT="$STRING_SIGMA_FOR_MAG_PLOT / $A"
echo "Making mag vs. IQR vs. 1/eta plot"
echo "set terminal postscript eps enhanced color solid \"Times\" 24 linewidth 2.0
$GNUPLOT5_COLOR_SCHEME_COMMAND
set output \"vast_index_vs_mag_magIQReta_mag.eps\"
set xlabel 'mag.'
set ylabel 'IQR'
set zlabel \"01/{/Symbol h}\"
splot \"vast_lightcurve_statistics.log\" u $COLUMNS_FOR_GNUPLOT ps 0.75 pt 7 lc 'red' title '', \"vast_lightcurve_statistics_known_variables.log\" u $COLUMNS_FOR_GNUPLOT lc 'blue' title '', \"vast_lightcurve_statistics_expected.log\" u $COLUMNS_FOR_GNUPLOT w l lc 'black' $GNUPLOT5_DASHED_LINE_TYPE title '', \"vast_lightcurve_statistics_expected_plus_spread.log\" u $COLUMNS_FOR_GNUPLOT w l lc 'green' title 'F_{max} cut-off at $STRING_SIGMA_FOR_MAG_PLOT'
" | gnuplot
  

