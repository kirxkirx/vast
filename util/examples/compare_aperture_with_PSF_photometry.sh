#!/usr/bin/env bash

############################################################
# This script will perform both aperture and PSF photometry
# of images specified in the IMAGE_DIR and will make plots
# to compare the results.
############################################################

# Set path to the image folder here
IMAGE_DIR=../sample_data

# Performe aperture photometry with standard settings
./vast -u -f ../sample_data/f_72-0*
cp vast_lightcurve_statistics.log aperture_vast_lightcurve_statistics.log

# Perform PSF photometry
./vast -u -f -P ../sample_data/f_72-0*
cp vast_lightcurve_statistics.log psf_vast_lightcurve_statistics.log

echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'mag-sigma_plot_psf-app.eps'
unset key
set xlabel 'Instrumental magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
plot 'aperture_vast_lightcurve_statistics.log' title 'aperture', 'psf_vast_lightcurve_statistics.log' title 'PSF'
" > mag-sigma_plot_psf-app.gnuplot
gnuplot mag-sigma_plot_psf-app.gnuplot

echo "

Results plotted in mag-sigma_plot_psf-app.eps
" 
