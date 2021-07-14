#!/usr/bin/env bash

#
# You MUST enable '#define DEBUGFILES' in src/vast_limits.h
# and recompile VaST with 'make' in order for this script to work!
#


JD0="2457000.0"

echo "2457001.50000 11.497 0.025
2457001.70000 11.517 0.028
2457002.40000 11.305 0.025
2457002.60000 11.246 0.018
2457004.60000 10.517 0.016
2457006.40000 11.032 0.021
2457006.50000 11.111 0.020
2457006.60000 11.143 0.023
2457008.30000 10.451 0.023
2457008.40000 11.408 0.023
2457009.30000 11.054 0.022" > test_lightcurve.txt

grep -v "2457008.30000 10.451 0.023" test_lightcurve.txt > test_lightcurve_without_outlier.txt
echo "2457008.30000 10.451 0.023" > test_lightcurve_outlier.txt

make stetson_test
lib/test/stetson_test test_lightcurve.txt | grep mean_magnitude > test_lightcurve.tmp

for INDEX in I J ;do

echo "set terminal postscript eps enhanced color solid \"Times\" 22 linewidth 2
set output \"test_lightcurve_$INDEX.eps\"
set xlabel 'JD-$JD0'
set ylabel 'm'
set yrange [] reverse
set format y \"%4.1f\"
set ytics 0.2
set xtics 1.0" > test_lightcurve_$INDEX.gnuplot

for BACK in 0 1 ;do
 if [ $BACK -eq 1 ];then
  BACK_STRING="_back"
  BLABEL="B"
  VLABEL="V"
  TEXTCOLOR='royalblue'
 else
  BACK_STRING=""
  BLABEL="b"
  VLABEL="v"
  TEXTCOLOR='red'
 fi

 for INPUTFILE in debugfile"$BACK_STRING"_stetson"$INDEX"pair1.dat debugfile"$BACK_STRING"_stetson"$INDEX"pair2.dat debugfile"$BACK_STRING"_stetson"$INDEX"isolated.dat ;do

  # No isolated points for the I index
  if [ "$INDEX" == "I" ];then
   if [ "$INPUTFILE" == "debugfile"$BACK_STRING"_stetson"$INDEX"isolated.dat" ];then
    continue
   fi
  fi
  
  MEAN_MAG=`grep "mean_magnitude($INDEX)=" test_lightcurve.tmp | head -n1 | awk '{print $2}'`

  echo "Plotting $INPUTFILE BLABEL=$BLABEL VLABEL=$VLABEL" 1>&2
  while read JD MAG ERR ;do
 
   JD_OFFSET="-0.09"
   
   if [ $BACK -eq 1 ];then
    MAG_OFFSET="-0.10"
    if [ "$JD" == "2457006.500000" ];then
     JD_OFFSET="-0.2"
    fi
   else
    MAG_OFFSET="0.10"
    if [ "$JD" == "2457006.500000" ];then
     JD_OFFSET="0.0"
    fi
   fi
 
   X=`echo "$JD-$JD0+($JD_OFFSET)"| bc -ql`
   Y=`echo "$MAG-($MAG_OFFSET)"`
   if [ "$INPUTFILE" == "debugfile"$BACK_STRING"_stetson"$INDEX"pair1.dat" ] ;then
    echo "set label '$BLABEL' at $X,$Y font 'Times,22' textcolor '$TEXTCOLOR'" >> test_lightcurve_$INDEX.gnuplot
   elif [ "$INPUTFILE" == "debugfile"$BACK_STRING"_stetson"$INDEX"pair2.dat" ] ;then
    echo "set label '$VLABEL' at $X,$Y font 'Times,22' textcolor '$TEXTCOLOR'" >> test_lightcurve_$INDEX.gnuplot
   #else
   # echo "set label 's' at $X,$Y font 'Times,22' textcolor '$TEXTCOLOR'" >> test_lightcurve_$INDEX.gnuplot
   fi
  done < $INPUTFILE
 done

done



echo "set arrow from 0.5,10.4 to 2.0,10.4 linecolor 'red'
set label 'forward' at 0.55,10.45 font 'Times,22' textcolor 'red'
set arrow from 9.5,11.58 to 8.0,11.58 linecolor 'royalblue'
set label 'REVERSE' at 8.0,11.63 font 'Times,22' textcolor 'royalblue'
plot [0:10][11.7:10.3] $MEAN_MAG linecolor 3 dashtype 2 title '', 11.0+0.5*sin(x) linecolor 2 title '', \"test_lightcurve_without_outlier.txt\" using (\$1-$JD0):2:3 with errorbars pointtype 7 pointsize 1.0 linecolor 'black' title '', \"test_lightcurve_outlier.txt\" using (\$1-$JD0):2:3 with errorbars pointtype 6 pointsize 1.0 linecolor 'black' title '', \"test_lightcurve_outlier.txt\" using (\$1-$JD0):2 pointtype 7 pointsize 0.8 linecolor 'white' title ''" >> test_lightcurve_$INDEX.gnuplot


gnuplot test_lightcurve_$INDEX.gnuplot
gv test_lightcurve_$INDEX.eps &

done

# Make LaTeX table
echo "\begin{table}
 \centering
 \caption{Simulated lightcurve divided into subsamples.}
 \label{tab:simlc}
 \begin{tabular}{cccc}
 \hline
 JD & m & $\sigma_m$ & sub-sample \\\\
 \hline" > test_lightcurve.tex
while read JD MAG ERR ;do
 SUBSAMLE=""
 grep "$JD" debugfile_stetsonIpair1.dat 
 if [ $? -eq 0 ];then
  SUBSAMLE="b"
 fi
 grep "$JD" debugfile_stetsonIpair2.dat 
 if [ $? -eq 0 ];then
  SUBSAMLE="v"
 fi
 grep "$JD" debugfile_back_stetsonIpair1.dat 
 if [ $? -eq 0 ];then
  SUBSAMLE=$SUBSAMLE"B"
 fi
 grep "$JD" debugfile_back_stetsonIpair2.dat 
 if [ $? -eq 0 ];then
  SUBSAMLE=$SUBSAMLE"V"
 fi
 echo " $JD & $MAG & $ERR & $SUBSAMLE \\\\" >> test_lightcurve.tex
done < test_lightcurve.txt
echo " \hline
 \end{tabular}
\end{table}" >> test_lightcurve.tex

cat test_lightcurve.tex

# Cleanup
rm -f test_lightcurve.tmp

