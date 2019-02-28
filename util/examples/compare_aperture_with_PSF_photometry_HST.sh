#!/usr/bin/env bash

############################################################
# This script will perform both aperture and PSF photometry
# of images specified in the IMAGE_DIR and will make plots
# to compare the results.
############################################################

# Set path to the image folder here
IMAGE_DIR=../sample_data

# Performe aperture photometry with standard settings
./vast -x2 -b 200 -u -f /home/kirx/current_work/HCV/test/M4_WFC3_F775W_HLA_level1/*
util/nopgplot.sh
lib/new_lightcurve_sigma_filter 2.0
util/nopgplot.sh
cp vast_lightcurve_statistics.log aperture_vast_lightcurve_statistics.log

# Perform PSF photometry
./vast -x2 -b 200 -u -f -P /home/kirx/current_work/HCV/test/M4_WFC3_F775W_HLA_level1/*
util/nopgplot.sh
lib/new_lightcurve_sigma_filter 2.0
util/nopgplot.sh
cp vast_lightcurve_statistics.log psf_vast_lightcurve_statistics.log

echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'mag-sigma_plot_psf-app.eps'
#unset key
set key top left
set xlabel 'Instrumental magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
plot [][0.0:0.3] 'aperture_vast_lightcurve_statistics.log' ps 0.5 title 'aperture', 'psf_vast_lightcurve_statistics.log' title 'PSF' ps 0.5 lc 3
" > mag-sigma_plot_psf-app.gnuplot
gnuplot mag-sigma_plot_psf-app.gnuplot

echo "

Results plotted in mag-sigma_plot_psf-app.eps
" >> /dev/stderr
