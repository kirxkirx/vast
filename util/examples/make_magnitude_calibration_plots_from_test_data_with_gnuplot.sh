#!/usr/bin/env bash

# Magnitude calibration

#cp default.sex.beta_Cas_photoplates default.sex              
#./vast -u -o -j -f ../test_data_photo/SCA*
#lib/remove_lightcurves_with_small_number_of_points 40
#util/magnitude_calibration.sh B

for CALIBFILE_TO_PLOT in calib.txt vast_magnitude_calibration_details_log/SCA1168S_17445_09545__00_00.calib ;do

# DISABLE ME
continue

PARAMFILE="$CALIBFILE_TO_PLOT"_param

##############
if [ "$CALIBFILE_TO_PLOT" = "calib.txt" ];then
 RANGE="[-16.5:-13.3]"
 XLABEL="m_{inst 1}"
 YLABEL="B_{APASS}"
else
 RANGE="[-16.5:-13.3][-16.5:-13.3]"
 XLABEL="m_{inst 2}"
 YLABEL="m_{inst 1}"
fi
EPSFILENAME=`basename "$CALIBFILE_TO_PLOT" .txt`
EPSFILENAME=`basename "$EPSFILENAME" .calib`
EPSFILENAME="$EPSFILENAME".eps
##############

# Get parameters
A4=`cat $PARAMFILE | awk '{printf "%.0f",$1}'`
A3=`cat $PARAMFILE | awk '{print $2}'`
A2=`cat $PARAMFILE | awk '{print $3}'`
A1=`cat $PARAMFILE | awk '{print $4}'`
A0=`cat $PARAMFILE | awk '{print $5}'`

if [ $A4 -eq 4 ];then
 CURVEEQ="$A0*log10( 10**($A1*(x-$A2) ) + 1.0 ) + $A3"
else
 CURVEEQ="1.0/$A1*log10( 10**( (x-$A3)/$A0 ) - 1.0 ) + $A2"
fi

#cat $PARAMFILE
#echo "$CURVEEQ"

echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output '$EPSFILENAME'
set size square
set xlabel '$XLABEL'
set ylabel '$YLABEL'
set format x '%4.1f'
set format y '%4.1f'
set ytics 0.5
set xtics 0.5
plot $RANGE '$CALIBFILE_TO_PLOT' linecolor 'royalblue' pointtype 7 pointsize 0.5  title '', $CURVEEQ linecolor 'black' title ''
" | gnuplot
gv $EPSFILENAME

done

# Photographic plates shift plots
# make sure DEBUGFILES are enabled for make
rm -f solve_plate_debug.txt 
#make 
util/clean_data.sh 
cp default.sex.beta_Cas_photoplates default.sex
util/solve_plate_with_UCAC4 ../test_data_photo/SCA12604S_13926_08169__00_00.fit
if [ ! -f solve_plate_debug.txt ];then
 echo "ERROR: enable DEBUGFILES and recompile vast"
 exit 1
fi

#cos(58.007571/180*pi)=0.52981
COS_DELTA=0.52981
EPSFILENAME=photoplate_shift.eps
RANGE="[0:2050]"
XLABEL="X (pix)"
YLABEL="{/Symbol D}R.A. (arcsec)"
echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output '$EPSFILENAME'
#set size square
set xlabel '$XLABEL'
set ylabel '$YLABEL'
#set format x '%4.1f'
#set format y '%4.1f'
#set ytics 0.5
#set xtics 0.5
set arrow from 1550,-4 to 1550,-3 nohead lw 4 linecolor 'red'
set arrow from 1900,-4 to 1900,-3 nohead lw 4 linecolor 'red'
plot $RANGE 'solve_plate_debug.txt' using 1:(\$9*$COS_DELTA) linecolor 'red' pointtype 7 pointsize 0.75  title 'uncorrected' , 'solve_plate_debug.txt' using 1:(\$7*$COS_DELTA) linecolor 'royalblue' pointtype 7 pointsize 0.75  title 'corrected'
" | gnuplot
gv $EPSFILENAME
EPSFILENAME=photoplate_hacksaw.eps
XLABEL="Y (pix)"
YLABEL="{/Symbol D}Dec. (arcsec)"
echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output '$EPSFILENAME'
#set size square
set xlabel '$XLABEL'
set ylabel '$YLABEL'
#set format x '%4.1f'
#set format y '%4.1f'
#set ytics 0.5
#set xtics 0.5
plot $RANGE 'solve_plate_debug.txt' using 2:10 linecolor 'red' pointtype 7 pointsize 0.75  title 'uncorrected' , 'solve_plate_debug.txt' using 2:8 linecolor 'royalblue' pointtype 7 pointsize 0.75  title 'corrected'
" | gnuplot
gv $EPSFILENAME


# DISABLE ME
#exit 1

## PSF fitting photometry
cp default.sex.ccd_example default.sex
./vast -u -f ../sample_data/f_72-0*
#lib/remove_lightcurves_with_small_number_of_points 80
util/nopgplot.sh
grep -v out20094.dat vast_lightcurve_statistics.log > /tmp/vast_lightcurve_statistics_ap_sysrem0.log
util/sysrem2
util/nopgplot.sh
util/sysrem2
util/nopgplot.sh
util/sysrem2
util/nopgplot.sh
#util/sysrem2
#util/nopgplot.sh
#util/sysrem2
#util/nopgplot.sh
cp vast_lightcurve_statistics.log /tmp/vast_lightcurve_statistics_ap_sysrem3.log
cp default.sex.ccd_example default.sex
cp default.psfex.small_FoV default.psfex
./vast -u -P -f ../sample_data/f_72-0*
#lib/remove_lightcurves_with_small_number_of_points 80
util/nopgplot.sh
grep -v out20094.dat vast_lightcurve_statistics.log > /tmp/vast_lightcurve_statistics_psf_sysrem0.log
util/sysrem2
util/nopgplot.sh
util/sysrem2
util/nopgplot.sh
util/sysrem2
util/nopgplot.sh
#util/sysrem2
#util/nopgplot.sh
#util/sysrem2
#util/nopgplot.sh
cp vast_lightcurve_statistics.log /tmp/vast_lightcurve_statistics_psf_sysrem3.log

XLABEL="m_{inst}"
YLABEL="{/Symbol s}"
#RANGE="[-13:-8.3][0.001:0.12]"
RANGE="[][0.001:0.25]"
for SYSREMITER in sysrem0 sysrem3 ;do
EPSFILENAME="ap_vs_psf_$SYSREMITER.eps"
echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output '$EPSFILENAME'
#set size square
set xlabel '$XLABEL'
set ylabel '$YLABEL'
set format x '%+2.0f'
#set format y '%5.2f'
#set ytics 0.01
set xtics 1.0
set key top left
set logscale y
plot $RANGE '/tmp/vast_lightcurve_statistics_ap_$SYSREMITER.log' u 1:14 linecolor 'red' pointtype 4 pointsize 1.0  title 'PSF', '/tmp/vast_lightcurve_statistics_psf_$SYSREMITER.log' u 1:14 linecolor 'forest-green' pointtype 7 pointsize 0.75  title 'aperture'
" | gnuplot
gv $EPSFILENAME
done
