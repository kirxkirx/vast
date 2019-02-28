#!/usr/bin/env bash

############################################################
# This script will make some nice plots for the HST/WFC3 M4 dataset
############################################################

# Set path to the image folder here
LIGHTCURVES_BAND1=/home/kirx/current_work/HCV/test/M4/5/resultsM4_3600/F775W

## compute stats on BAND1
util/clean_data.sh
for i in $LIGHTCURVES_BAND1/* ;do
 tail -n 15 $i | awk '{print $1" "$2-25.0" "$3" "$4" "$5" "$6" "$7}' > `basename $i`
done
util/nopgplot.sh
lib/new_lightcurve_sigma_filter 2.0
util/nopgplot.sh

echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'mag-sigma_plot_psf-app.eps'
#unset key
set key top left
set xlabel 'Instrumental magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'           
set format y '%5.2f'
plot [][0.0:0.3] 'aperture_vast_lightcurve_statistics.log' ps 0.5 title 'aperture', 'psf_vast_lightcurve_statistics.log' title 'PSF' ps 0.5 lc 3, 'vast_lightcurve_statistics.log' title 'HSC' ps 0.5 lc 4 pt 4
" > mag-sigma_plot_psf-app.gnuplot
gnuplot mag-sigma_plot_psf-app.gnuplot

echo "

Results plotted in mag-sigma_plot_psf-app.eps
" >> /dev/stderr


