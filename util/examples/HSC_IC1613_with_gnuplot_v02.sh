#!/usr/bin/env bash

################ Input parameters ################
FIELD_NAME="HSC_M4_at_least_19_points_drop_2brightest_and_2faintest"
#LIST_OF_FILTERS="F775W F467M"
LIST_OF_FILTERS="F467M"
DIRECTORY_WITH_FILER_NAMED_DATADIR="/home/kirx/current_work/HCV/test/M4/5/resultsM4_3600_expfilter"
#DIRECTORY_WITH_FILER_NAMED_DATADIR="/home/kirx/current_work/HCV/test/M4/M4_dataset_from_ValerioNascimbeni"
#FIELD_NAME="HSC_IC1613"
#LIST_OF_FILTERS="F475W F814W"
#DIRECTORY_WITH_FILER_NAMED_DATADIR="/home/kirx/current_work/HCV/test/IC1613/new_test"
#LIST_OF_KNOWN_VAR_IDS="$DIRECTORY_WITH_FILER_NAMED_DATADIR/known_var_ids.txt"
#OUTDAT_LIST_OF_CANDIDATES="$DIRECTORY_WITH_FILER_NAMED_DATADIR/candidate_var_outdat.txt"
#FIELD_NAME="HSC_SEXA"
#LIST_OF_FILTERS="F555W F814W"
#DIRECTORY_WITH_FILER_NAMED_DATADIR="/home/kirx/current_work/HCV/test/SEXA/new_test"
LIST_OF_KNOWN_VAR_IDS="$DIRECTORY_WITH_FILER_NAMED_DATADIR/known_var_ids.txt"
OUTDAT_LIST_OF_CANDIDATES="$DIRECTORY_WITH_FILER_NAMED_DATADIR/candidate_var_outdat.txt"
##################################################

# Check input parameters
if [ ! -d $DIRECTORY_WITH_FILER_NAMED_DATADIR ];then
 echo "ERROR: cannot find directory $DIRECTORY_WITH_FILER_NAMED_DATADIR"
 exit 1
fi

for FILTER in $LIST_OF_FILTERS ;do
 if [ ! -d $DIRECTORY_WITH_FILER_NAMED_DATADIR/$FILTER ];then
  echo "ERROR: cannot find data directory $DIRECTORY_WITH_FILER_NAMED_DATADIR/$FILTER/"
  exit 1
 fi
done

if [ ! -f $LIST_OF_KNOWN_VAR_IDS ];then
 echo "ERROR: cannot find the list of known variables $LIST_OF_KNOWN_VAR_IDS"
 exit 1
fi

if [ -z "$FIELD_NAME" ];then
 echo "ERROR: please set a proper field name!"
 exit 1
fi

################ Processing ################
rm -f thefirstday.txt

for SYSREMCORR in nosysrem sysrem ;do
#for SYSREMCORR in nosysrem ;do

 for LOCALCORR in nocorr localcorr ;do
 #for LOCALCORR in nocorr ;do

  for FILTER in $LIST_OF_FILTERS ;do
  
   if [ ! -d $DIRECTORY_WITH_FILER_NAMED_DATADIR/$FILTER ];then
    echo "ERROR: cannot find data directory $DIRECTORY_WITH_FILER_NAMED_DATADIR/$FILTER/"
    continue
   fi
   
   # Load data
   util/load.sh $DIRECTORY_WITH_FILER_NAMED_DATADIR/$FILTER

   ###### FILTERING
   lib/drop_bright_points 2
   lib/drop_faint_points 2
   lib/remove_lightcurves_with_small_number_of_points 19
 
   # Compute indexes
   util/nopgplot.sh

   # Apply local correction if needed
   if [ "$LOCALCORR" = "localcorr" ];then
    util/local_zeropoint_correction
    util/nopgplot.sh
   fi
 
   # Apply three iterations of SysRem if needed
   if [ "$SYSREMCORR" = "sysrem" ];then
    util/sysrem
    util/sysrem
    util/sysrem
    util/nopgplot.sh
   fi
  
   # Select known variables
   if [ -f "$FIELD_NAME"_known_vars.txt ];then
    rm -f "$FIELD_NAME"_known_vars.txt
   fi
   for KNOWN in `grep -v Match $LIST_OF_KNOWN_VAR_IDS` ;do
    grep "out$KNOWN.dat" vast_lightcurve_statistics.log >> "$FIELD_NAME"_known_vars.txt
   done
   # Select candidates (note the different format - these are out*.dat files, not just IDs)
   if [ -f "$FIELD_NAME"_candidate_vars.txt ];then
    rm -f "$FIELD_NAME"_candidate_vars.txt
   fi
   while read CANDIDATEOUTDATFILE ;do
    grep "$CANDIDATEOUTDATFILE" vast_lightcurve_statistics.log >> "$FIELD_NAME"_candidate_vars.txt
   done < $OUTDAT_LIST_OF_CANDIDATES

   # Plot lightcurves for the candidates
   #for LCOBJECTCLASS in candidates known_var ;do
   for LCOBJECTCLASS in known_var ;do
    if [ "$LCOBJECTCLASS" = "candidates" ];then
     LIST_OF_LCOBJECTIDS=`cat "$FIELD_NAME"_candidate_vars.txt | awk '{print $5}'`
    else
     LIST_OF_LCOBJECTIDS=`cat "$FIELD_NAME"_known_vars.txt | awk '{print $5}'`
     if [ "$FIELD_NAME" = "HSC_SEXA" ];then
      # No identified vars in HSC_SEXA
      continue
     fi
    fi
    LIST_OF_LCOBJECTIDS="${LIST_OF_LCOBJECTIDS//out/}"
    LIST_OF_LCOBJECTIDS="${LIST_OF_LCOBJECTIDS//.dat/}"
    for LCOBJECTID in $LIST_OF_LCOBJECTIDS ;do
     LCFILE="out$LCOBJECTID.dat"
     if [ ! -f $LCFILE ];then
      continue
     fi

     # Get the first day for lightcurve plots
     cat out*.dat | awk '{printf "%.0lf\n",$1*100000}' | sort -n | uniq | awk '{printf "%.0lf\n",$1/100000}' > thefirstday.txt
     FIRST_DAY=`cat thefirstday.txt | head -n1`
     LAST_DAY=`cat thefirstday.txt | tail -n1`
     DURATION=`echo "$LAST_DAY+1-$FIRST_DAY" | bc -q`
     FIRST_DAY_FOR_LC_PLOTS=`echo "-0.05*$DURATION" | bc -ql`
     LAST_DAY_FOR_LC_PLOTS=`echo "0.05*$DURATION" | bc -ql`

     # Make sure the plot is nicely labeled
     TEST=`echo "$FIRST_DAY>2451123.0" | bc -q`
     if [ $TEST -eq 1 ] ;then
      MJD_OR_JD_STRING="JD"
     else
      MJD_OR_JD_STRING="MJD"
     fi
     LCOBJECTID_FOR_TITLE_STRING="${LCOBJECTID//lc/}"
     LCOBJECTID_FOR_TITLE_STRING="${LCOBJECTID_FOR_TITLE_STRING//_/}"

     MINMAG=`cat $LCFILE | awk '{printf "%.0lf\n",$2*10000}' | sort -n | uniq | awk '{printf "%.4lf\n",$1/10000}' | head -n1`
     MAXMAG=`cat $LCFILE | awk '{printf "%.0lf\n",$2*10000}' | sort -n | uniq | awk '{printf "%.4lf\n",$1/10000}' | tail -n1`
     MAGRANGE=`echo "($MAXMAG)-($MINMAG)" | bc -ql`
     MINMAGPLOT=`echo "($MINMAG-0.05*$MAGRANGE)" | bc -ql`
     MAXMAGPLOT=`echo "($MAXMAG+0.05*$MAGRANGE)" | bc -ql`
     echo "set terminal postscript eps enhanced color solid \"Times\" 22 linewidth 1.5
set output \""$FIELD_NAME"_"$FILTER"_$LCOBJECTCLASS"_"$LCOBJECTID"_"$LOCALCORR"_"$SYSREMCORR.eps\"
set title '$LCOBJECTID_FOR_TITLE_STRING'
set xlabel '$MJD_OR_JD_STRING-$FIRST_DAY'
set ylabel '$FILTER'
set format y '%5.2f'
set yrange [$MAXMAGPLOT:$MINMAGPLOT]
plot '$LCFILE' using (\$1-$FIRST_DAY):2:3 w e linecolor 'blue' pointtype 5 pointsize 1.0  title ''" > "$FIELD_NAME"_"$FILTER"_$LCOBJECTCLASS"_"$LCOBJECTID"_"$LOCALCORR"_"$SYSREMCORR.gnuplot 
     gnuplot "$FIELD_NAME"_"$FILTER"_$LCOBJECTCLASS"_"$LCOBJECTID"_"$LOCALCORR"_"$SYSREMCORR.gnuplot
    done
   done # LCOBJECTCLASS
   
   # Save data files for future reference
   cp vast_lightcurve_statistics.log "$FIELD_NAME"_$FILTER"_"$LOCALCORR"_"$SYSREMCORR.dat
   if [ -f "$FIELD_NAME"_known_vars.txt ];then
    cp "$FIELD_NAME"_known_vars.txt "$FIELD_NAME"_$FILTER"_"$LOCALCORR"_"$SYSREMCORR.known.dat
   fi
   if [ -f "$FIELD_NAME"_candidate_vars.txt ];then
    cp "$FIELD_NAME"_candidate_vars.txt "$FIELD_NAME"_$FILTER"_"$LOCALCORR"_"$SYSREMCORR.candidates.dat
   fi
   util/save.sh "$FIELD_NAME"_$FILTER"_"$LOCALCORR"_"$SYSREMCORR"_lightcurves"
 
   # Plot everything
   for INDEX in 2 7 8 9 10 11 12 14 15 16 17 19 20 21 22 23 24 25 26 27 28 ;do
    SPECIAL_GNUPLOT_COMMANDS=""
    # Set index name
    case "$INDEX" in
     "2")
      INDEX_NAME="{/Symbol s}"
     ;;
     "7")
      INDEX_NAME="skewness"
     ;; 
     "8")
      INDEX_NAME="kurtosis"
     ;;
     "9")
      INDEX_NAME="I"
     ;;
     "10")
      INDEX_NAME="J"
     ;;
     "11")
      INDEX_NAME="K"
      SPECIAL_GNUPLOT_COMMANDS="set key bottom left"
     ;;
     "12")
      INDEX_NAME="L"
     ;;
     "14")
      INDEX_NAME="MAD"
     ;;
     "15")
      INDEX_NAME="autocorr."
     ;;
     "16")
      INDEX_NAME="RoMS"
     ;;
     "17")
      INDEX_NAME="reduced {/Symbol c}^2"
      SPECIAL_GNUPLOT_COMMANDS="set logscale y"
     ;;
     "19")
      INDEX_NAME="peak-to-peak"
      SPECIAL_GNUPLOT_COMMANDS="set key bottom left"
     ;;
     "20")
      INDEX_NAME="J(clip)"
     ;;
     "21")
      INDEX_NAME="L(clip)"
     ;;
     "22")
      INDEX_NAME="J(time)"
     ;;
     "23")
      INDEX_NAME="L(time)"
     ;;
     "24")
      INDEX_NAME="N_3"
     ;;
     "25")
      INDEX_NAME="excursions"
     ;;
     "26")
      INDEX_NAME="{/Symbol h}"
     ;;
     "27")
      INDEX_NAME="E_A"
     ;;
     "28")
      INDEX_NAME="S_B"
      SPECIAL_GNUPLOT_COMMANDS="set logscale y"
     ;;
     *)
      INDEX_NAME="$INDEX"
     ;;
    esac
 
  echo "set terminal postscript eps enhanced color solid \"Times\" 22 linewidth 1.5
set output \""$FIELD_NAME"_$FILTER"_"$INDEX"_"$LOCALCORR"_"$SYSREMCORR.eps\"
set xlabel '$FILTER'
set ylabel '$INDEX_NAME'
$SPECIAL_GNUPLOT_COMMANDS
plot '"$FIELD_NAME"_$FILTER"_"$LOCALCORR"_"$SYSREMCORR.dat' u 1:$INDEX pt 7 lc 'red' title '', '"$FIELD_NAME"_$FILTER"_"$LOCALCORR"_"$SYSREMCORR.known.dat' u 1:$INDEX pt 4 lc 'black' lw 0.75 title 'known var.', '"$FIELD_NAME"_$FILTER"_"$LOCALCORR"_"$SYSREMCORR.candidates.dat' u 1:$INDEX pt 7 lc 'blue' title 'candidates'" > "$FIELD_NAME"_$FILTER"_"$INDEX"_"$LOCALCORR"_"$SYSREMCORR.gnuplot

   gnuplot "$FIELD_NAME"_$FILTER"_"$INDEX"_"$LOCALCORR"_"$SYSREMCORR.gnuplot
   
   # Plot lightcurves for the candidates
   
   done # INDEX


  done # FILTER
 done # LOCALCORR
done # SYSREMCORR

################ End of processing ################

# Save results

if [ -d "$FIELD_NAME"_results ];then
 rm -rf "$FIELD_NAME"_results/*
else
 mkdir "$FIELD_NAME"_results 
fi

mv "$FIELD_NAME"_* "$FIELD_NAME"_results
mv thefirstday.txt "$FIELD_NAME"_results/

echo "All good! =)
The results are saved to the folder "$FIELD_NAME"_results"

