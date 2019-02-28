#!/usr/bin/env bash

FILE_WITH_FILEAMES_OF_KNOWN_VARS="vast_autocandidates.log"

# 
while read A ;do
 grep $A vast_lightcurve_statistics.log
done < $FILE_WITH_FILEAMES_OF_KNOWN_VARS > vast_lightcurve_statistics_known_variables.log

# Compute the selection urves and stats
lib/index_vs_mag > vast_index_vs_mag.txt

# For each index...
for INDEX in idx00_STD idx01_wSTD idx02_skew idx03_kurt idx04_I idx05_J idx06_K idx07_L idx08_Npts idx09_MAD idx10_lag1 idx11_RoMS idx12_rCh2 idx13_Isgn idx14_Vp2p idx15_Jclp idx16_Lclp idx17_Jtim idx18_Ltim idx19_N3 idx20_excr idx21_eta idx22_E_A idx23_S_B idx24_NXS ;do
 INDEX_NAME_FOR_TITLE=`echo "$INDEX" | awk '{print $2}' FS='_'`
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
  echo "set terminal postscript eps enhanced color solid \"Times\" 22 linewidth 1.5
set output \"vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE"_"$PARAMETER".eps\"
set title '$INDEX_NAME_FOR_TITLE'
set xlabel 'Cut-off in {/Symbol s}'
set ylabel '$PARAMETER'
plot \"vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE".txt\" u $COLUMNS_FOR_GNUPLOT title ''
" | gnuplot
 done
 
 # Make the index plots
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
  elif [ "$INDEX" == "idx05_J" ];then
   COLUMNS_FOR_GNUPLOT="1:10" 
  elif [ "$INDEX" == "idx06_K" ];then
   COLUMNS_FOR_GNUPLOT="1:11"
  elif [ "$INDEX" == "idx07_L" ];then
   COLUMNS_FOR_GNUPLOT="1:12" 
  elif [ "$INDEX" == "idx08_Npts" ];then
   COLUMNS_FOR_GNUPLOT="1:13" 
  elif [ "$INDEX" == "idx09_MAD" ];then
   COLUMNS_FOR_GNUPLOT="1:14" 
  elif [ "$INDEX" == "idx10_lag1" ];then
   COLUMNS_FOR_GNUPLOT="1:15"
  elif [ "$INDEX" == "idx11_RoMS" ];then
   COLUMNS_FOR_GNUPLOT="1:16" 
  elif [ "$INDEX" == "idx12_rCh2" ];then
   COLUMNS_FOR_GNUPLOT="1:17" 
  elif [ "$INDEX" == "idx13_Isgn" ];then
   COLUMNS_FOR_GNUPLOT="1:18" 
  elif [ "$INDEX" == "idx14_Vp2p" ];then
   COLUMNS_FOR_GNUPLOT="1:19" 
  elif [ "$INDEX" == "idx15_Jclp" ];then
   COLUMNS_FOR_GNUPLOT="1:20" 
  elif [ "$INDEX" == "idx16_Lclp" ];then
   COLUMNS_FOR_GNUPLOT="1:21"
  elif [ "$INDEX" == "idx17_Jtim" ];then
   COLUMNS_FOR_GNUPLOT="1:22" 
  elif [ "$INDEX" == "idx18_Ltim" ];then
   COLUMNS_FOR_GNUPLOT="1:23"
  elif [ "$INDEX" == "idx19_N3" ];then
   COLUMNS_FOR_GNUPLOT="1:24" 
  elif [ "$INDEX" == "idx20_excr" ];then
   COLUMNS_FOR_GNUPLOT="1:25"
  elif [ "$INDEX" == "idx21_eta" ];then
   COLUMNS_FOR_GNUPLOT="1:26" 
  elif [ "$INDEX" == "idx22_E_A" ];then
   COLUMNS_FOR_GNUPLOT="1:27" 
  elif [ "$INDEX" == "idx23_S_B" ];then
   COLUMNS_FOR_GNUPLOT="1:28"
  elif [ "$INDEX" == "idx24_NXS" ];then
   COLUMNS_FOR_GNUPLOT="1:29"
  fi
 echo "set terminal postscript eps enhanced color solid \"Times\" 22 linewidth 1.5
set output \"vast_index_vs_mag_"$INDEX_NAME_FOR_TITLE"_mag.eps\"
#set title '$INDEX_NAME_FOR_TITLE'
set xlabel 'mag.'
set ylabel '$INDEX_NAME_FOR_TITLE'
plot \"vast_lightcurve_statistics.log\" u $COLUMNS_FOR_GNUPLOT title '', \"vast_lightcurve_statistics_known_variables.log\" u $COLUMNS_FOR_GNUPLOT title 'known var.', \"vast_lightcurve_statistics_expected.log\" u $COLUMNS_FOR_GNUPLOT w l title '', \"vast_lightcurve_statistics_expected_plus_spread.log\" u $COLUMNS_FOR_GNUPLOT w l title ''
" | gnuplot
 

done
