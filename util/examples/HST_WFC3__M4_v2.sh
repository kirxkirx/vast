#!/usr/bin/env bash

############################################################
# This script will make some nice plots for the HST/WFC3 M4 dataset
############################################################

# Set path to the image folder here
LIGHTCURVES_BAND1=/home/kirx/current_work/HCV/test/M4/5/resultsM4_3600/F775W
LIGHTCURVES_BAND2=/home/kirx/current_work/HCV/test/M4/5/resultsM4_3600/F467M

## compute stats on BAND1
util/load.sh $LIGHTCURVES_BAND1
# Save sky positions
for i in out*.dat ;do cat $i | head -n1 | awk '{print $4"  "$5}' ;done > sky_positions.data
rm -f EB_sky_positions.data
for i in out2500.dat out909.dat out1828.dat out3910.dat ;do
 cat $i | head -n1 | awk '{print $4"  "$5}' >> EB_sky_positions.data
done

util/nopgplot.sh
cp vast_lightcurve_statistics.log vast_lightcurve_statistics_BAND1.data
rm -f EB_vast_lightcurve_statistics_BAND1.data
for i in out2500.dat out909.dat out1828.dat out3910.dat ;do
 grep $i vast_lightcurve_statistics.log >> EB_vast_lightcurve_statistics_BAND1.data
done

lib/new_lightcurve_sigma_filter 3.0
util/nopgplot.sh
cp vast_lightcurve_statistics.log vast_lightcurve_statistics_BAND1_sigmaclip.data
rm -f EB_vast_lightcurve_statistics_BAND1_sigmaclip.data
for i in out2500.dat out909.dat out1828.dat out3910.dat ;do
 grep $i vast_lightcurve_statistics.log >> EB_vast_lightcurve_statistics_BAND1_sigmaclip.data
done

util/sysrem
util/nopgplot.sh
cp vast_lightcurve_statistics.log vast_lightcurve_statistics_BAND1_sysrem01.data
rm -f EB_vast_lightcurve_statistics_BAND1_sysrem01.data
for i in out2500.dat out909.dat out1828.dat out3910.dat ;do
 grep $i vast_lightcurve_statistics.log >> EB_vast_lightcurve_statistics_BAND1_sysrem01.data
done

util/sysrem
util/sysrem
util/sysrem
util/sysrem
util/sysrem
util/nopgplot.sh
cp vast_lightcurve_statistics.log vast_lightcurve_statistics_BAND1_sysrem06.data
rm -f EB_vast_lightcurve_statistics_BAND1_sysrem06.data
for i in out2500.dat out909.dat out1828.dat out3910.dat ;do
 grep $i vast_lightcurve_statistics.log >> EB_vast_lightcurve_statistics_BAND1_sysrem06.data
done

#
#
#
#
# compute stats on BAND2
util/load.sh $LIGHTCURVES_BAND2
util/nopgplot.sh
cp vast_lightcurve_statistics.log vast_lightcurve_statistics_BAND2.data
rm -f EB_vast_lightcurve_statistics_BAND2.data
for i in out2500.dat out909.dat out1828.dat out3910.dat ;do
 grep $i vast_lightcurve_statistics.log >> EB_vast_lightcurve_statistics_BAND2.data
done

lib/new_lightcurve_sigma_filter 3.0
util/nopgplot.sh
cp vast_lightcurve_statistics.log vast_lightcurve_statistics_BAND2_sigmaclip.data
rm -f EB_vast_lightcurve_statistics_BAND2_sigmaclip.data
for i in out2500.dat out909.dat out1828.dat out3910.dat ;do
 grep $i vast_lightcurve_statistics.log >> EB_vast_lightcurve_statistics_BAND2_sigmaclip.data
done

util/sysrem
util/nopgplot.sh
cp vast_lightcurve_statistics.log vast_lightcurve_statistics_BAND2_sysrem01.data
rm -f EB_vast_lightcurve_statistics_BAND2_sysrem01.data
for i in out2500.dat out909.dat out1828.dat out3910.dat ;do
 grep $i vast_lightcurve_statistics.log >> EB_vast_lightcurve_statistics_BAND2_sysrem01.data
done

util/sysrem
util/sysrem
util/sysrem
util/sysrem
util/sysrem
util/nopgplot.sh
cp vast_lightcurve_statistics.log vast_lightcurve_statistics_BAND2_sysrem06.data
rm -f EB_vast_lightcurve_statistics_BAND2_sysrem06.data
for i in out2500.dat out909.dat out1828.dat out3910.dat ;do
 grep $i vast_lightcurve_statistics.log >> EB_vast_lightcurve_statistics_BAND2_sysrem06.data
done


# Plot sky positions
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'sky_positions.eps'
unset key
set xlabel 'R.A. [deg]'
set ylabel 'Dec. [deg]'
set size square
set xtics 0.02
set ytics 0.01
set format x '%7.2f'
set format y '%7.2f'
plot [][-26.56:-26.49] 'sky_positions.data' title '' pt 1, 'EB_sky_positions.data'  title '' pt 4 lc 7
" > sky_positions.gnuplot
gnuplot sky_positions.gnuplot

# RMS band1 vs band2
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'sigma_m_band1_vs_band2.eps'
set xlabel 'magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
set key top left
plot 'vast_lightcurve_statistics_BAND1.data' title 'F775W' pt 7, 'vast_lightcurve_statistics_BAND2.data' title 'F467M' pt 7, 'EB_vast_lightcurve_statistics_BAND1.data' title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND2.data' title '' pt 4 lc 7
" > sigma_m_band1_vs_band2.gnuplot
gnuplot sigma_m_band1_vs_band2.gnuplot

# RMS band1 vs band2
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'sigma_m_band1_vs_band2_sigmaclip.eps'
set xlabel 'magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
set key top left
plot 'vast_lightcurve_statistics_BAND1_sigmaclip.data' title 'F775W' pt 7, 'vast_lightcurve_statistics_BAND2_sigmaclip.data' title 'F467M' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND2_sigmaclip.data' title '' pt 4 lc 7
" > sigma_m_band1_vs_band2_sigmaclip.gnuplot
gnuplot sigma_m_band1_vs_band2_sigmaclip.gnuplot


# RMS band1
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'sigma_m_band1.eps'
unset key
set xlabel 'F775W magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
plot 'vast_lightcurve_statistics_BAND1.data' title '' pt 7, 'EB_vast_lightcurve_statistics_BAND1.data' title '' pt 4 lc 7
" > sigma_m_band1.gnuplot
gnuplot sigma_m_band1.gnuplot

# RMS band1
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'sigma_m_band1_sigmaclip.eps'
unset key
set xlabel 'F775W magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
plot 'vast_lightcurve_statistics_BAND1_sigmaclip.data' title '' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' title '' pt 4 lc 7
" > sigma_m_band1_sigmaclip.gnuplot
gnuplot sigma_m_band1_sigmaclip.gnuplot

# RMS band1
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'sigma_m_band1_sigmaclip_vs_noclip.eps'
set key top left
set xlabel 'F775W magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
plot 'vast_lightcurve_statistics_BAND1.data' title 'no clip' pt 7, 'vast_lightcurve_statistics_BAND1_sigmaclip.data' title '3 sigma-clip' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND1.data' title '' pt 4 lc 7
" > sigma_m_band1_sigmaclip_vs_noclip.gnuplot
gnuplot sigma_m_band1_sigmaclip_vs_noclip.gnuplot

# MAD band1
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'MAD_m_band1_sigmaclip_vs_noclip.eps'
set key top left
set xlabel 'F775W magnitude'
set ylabel 'MAD'
set format x '%4.1f'
set format y '%5.2f'
plot 'vast_lightcurve_statistics_BAND1.data' u 1:14 title 'no clip' pt 7, 'vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:14 title '3 sigma-clip' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:14 title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND1.data' u 1:14 title '' pt 4 lc 7
" > MAD_m_band1_sigmaclip_vs_noclip.gnuplot
gnuplot MAD_m_band1_sigmaclip_vs_noclip.gnuplot



# RMS band1 SysRem
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'sigma_m_band1_sysrem.eps'
set xlabel 'F775W magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
set key top left
plot [14.5:21.5][0.0:0.1] 'vast_lightcurve_statistics_BAND1_sigmaclip.data' title 'Before SysRem' pt 7, 'vast_lightcurve_statistics_BAND1_sysrem01.data' title 'SysRem x1' pt 7, 'vast_lightcurve_statistics_BAND1_sysrem06.data' title 'SysRem x6' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND1_sysrem01.data' title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND1_sysrem06.data' title '' pt 4 lc 7
" > sigma_m_band1_sysrem.gnuplot
gnuplot sigma_m_band1_sysrem.gnuplot


# MAD band1 SysRem
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'MAD_m_band1_sysrem.eps'
set xlabel 'F775W magnitude'
set ylabel 'MAD'
set format x '%4.1f'
set format y '%5.2f'
set key top left
plot [14.5:21.5][0.0:0.1] 'vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:14 title 'Before SysRem' pt 7, 'vast_lightcurve_statistics_BAND1_sysrem01.data' u 1:14 title 'SysRem x1' pt 7, 'vast_lightcurve_statistics_BAND1_sysrem06.data' u 1:14 title 'SysRem x6' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:14 title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND1_sysrem01.data' u 1:14 title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND1_sysrem06.data' u 1:14 title '' pt 4 lc 7
" > MAD_m_band1_sysrem.gnuplot
gnuplot MAD_m_band1_sysrem.gnuplot



# RoMS band1
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'roms_band1.eps'
unset key
set xlabel 'F775W magnitude'
set ylabel 'RoMS'
set format x '%4.1f'
set format y '%5.2f'
plot 'vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:16 title '' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:16 title '' pt 4 lc 7
" > roms_band1.gnuplot
gnuplot roms_band1.gnuplot

# Chi2 band1
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'chi2_band1.eps'
unset key
set xlabel 'F775W magnitude'
set ylabel 'reduced {/Symbol c}^2'
set format x '%4.1f'
set format y '%5.2f'
plot 'vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:17 title '' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:17 title '' pt 4 lc 7
" > chi2_band1.gnuplot
gnuplot chi2_band1.gnuplot

# Chi2 band1 zoom
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'chi2_band1_zoom.eps'
unset key
set xlabel 'F775W magnitude'
set ylabel 'reduced {/Symbol c}^2'
set format x '%4.1f'
set format y '%5.2f'
plot [][0:50] 'vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:17 title '' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:17 title '' pt 4 lc 7
" > chi2_band1_zoom.gnuplot
gnuplot chi2_band1_zoom.gnuplot

# Chi2 band1 zoom SysRem
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'chi2_band1_zoom_sysrem.eps'
set xlabel 'F775W magnitude'
set ylabel 'reduced {/Symbol c}^2'
set format x '%4.1f'
set format y '%5.2f'
plot [][0:50] 'vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:17 title 'Before SysRem' pt 7, 'vast_lightcurve_statistics_BAND1_sysrem01.data' u 1:17 title 'SysRem x1' pt 7, 'vast_lightcurve_statistics_BAND1_sysrem06.data' u 1:17 title 'SysRem x6' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:17 title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND1_sysrem01.data' u 1:17 title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND1_sysrem06.data' u 1:17 title '' pt 4 lc 7
" > chi2_band1_zoom_sysrem.gnuplot
gnuplot chi2_band1_zoom_sysrem.gnuplot


# L band1
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'L_band1.eps'
unset key
set xlabel 'F775W magnitude'
set ylabel 'L'
set format x '%4.1f'
set format y '%5.2f'
plot [][] 'vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:12 title '' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:12 title '' pt 4 lc 7
" > L_band1.gnuplot
gnuplot L_band1.gnuplot

# J band1
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'J_band1.eps'
unset key
set xlabel 'F775W magnitude'
set ylabel 'J'
set format x '%4.1f'
set format y '%5.2f'
plot [][] 'vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:10 title '' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:10 title '' pt 4 lc 7
" > J_band1.gnuplot
gnuplot J_band1.gnuplot


# L band1 SysRem
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'L_band1_sysrem.eps'
set xlabel 'F775W magnitude'
set ylabel 'L'
set format x '%4.1f'
set format y '%5.2f'
plot [][] 'vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:12 title 'Before SysRem' pt 7, 'vast_lightcurve_statistics_BAND1_sysrem01.data' u 1:12 title 'SysRem x1' pt 7, 'vast_lightcurve_statistics_BAND1_sysrem06.data' u 1:12 title 'SysRem x6' pt 7, 'EB_vast_lightcurve_statistics_BAND1_sigmaclip.data' u 1:12 title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND1_sysrem01.data' u 1:12 title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND1_sysrem06.data' u 1:12 title '' pt 4 lc 7
" > L_band1_sysrem.gnuplot
gnuplot L_band1_sysrem.gnuplot

##############################################################################
# RMS band2
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'sigma_m_band2.eps'
unset key
set xlabel 'F467M magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
plot 'vast_lightcurve_statistics_BAND2.data' title '' pt 7, 'EB_vast_lightcurve_statistics_BAND2.data' title '' pt 4 lc 7
" > sigma_m_band2.gnuplot
gnuplot sigma_m_band2.gnuplot

# RMS band2
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'sigma_m_band2_sigmaclip.eps'
unset key
set xlabel 'F467M magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
plot 'vast_lightcurve_statistics_BAND2_sigmaclip.data' title '' pt 7, 'EB_vast_lightcurve_statistics_BAND2_sigmaclip.data' title '' pt 4 lc 7
" > sigma_m_band2_sigmaclip.gnuplot
gnuplot sigma_m_band2_sigmaclip.gnuplot


# RMS band2
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'sigma_m_band2_sigmaclip_vs_noclip.eps'
set key top left
set xlabel 'F467M magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
plot 'vast_lightcurve_statistics_BAND2.data' title 'no clip' pt 7, 'vast_lightcurve_statistics_BAND2_sigmaclip.data' title '3 sigma-clip' pt 7, 'EB_vast_lightcurve_statistics_BAND2_sigmaclip.data' title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND2.data' title '' pt 4 lc 7
" > sigma_m_band2_sigmaclip_vs_noclip.gnuplot
gnuplot sigma_m_band2_sigmaclip_vs_noclip.gnuplot

# RMS band2 SysRem
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'sigma_m_band2_sysrem.eps'
set xlabel 'F467M magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
set key top left
plot [][0.0:0.1] 'vast_lightcurve_statistics_BAND2_sigmaclip.data' title 'Before SysRem' pt 7, 'vast_lightcurve_statistics_BAND2_sysrem01.data' title 'SysRem x1' pt 7, 'vast_lightcurve_statistics_BAND2_sysrem06.data' title 'SysRem x6' pt 7, 'EB_vast_lightcurve_statistics_BAND2_sigmaclip.data' title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND2_sysrem01.data' title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND2_sysrem06.data' title '' pt 4 lc 7
" > sigma_m_band2_sysrem.gnuplot
gnuplot sigma_m_band2_sysrem.gnuplot

# RoMS band2
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'roms_band2.eps'
unset key
set xlabel 'F467M magnitude'
set ylabel 'RoMS'
set format x '%4.1f'
set format y '%5.2f'
plot 'vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:16 title '' pt 7, 'EB_vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:16 title '' pt 4 lc 7
" > roms_band2.gnuplot
gnuplot roms_band2.gnuplot

# Chi2 band2
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'chi2_band2.eps'
unset key
set xlabel 'F467M magnitude'
set ylabel 'reduced {/Symbol c}^2'
set format x '%4.1f'
set format y '%5.2f'
plot 'vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:17 title '' pt 7, 'EB_vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:17 title '' pt 4 lc 7
" > chi2_band2.gnuplot
gnuplot chi2_band2.gnuplot

# Chi2 band2 zoom
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'chi2_band2_zoom.eps'
unset key
set xlabel 'F467M magnitude'
set ylabel 'reduced {/Symbol c}^2'
set format x '%4.1f'
set format y '%5.2f'
plot [][0:50] 'vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:17 title '' pt 7, 'EB_vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:17 title '' pt 4 lc 7
" > chi2_band2_zoom.gnuplot
gnuplot chi2_band2_zoom.gnuplot

# Chi2 band2 zoom SysRem
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'chi2_band2_zoom_sysrem.eps'
set xlabel 'F467M magnitude'
set ylabel 'reduced {/Symbol c}^2'
set format x '%4.1f'
set format y '%5.2f'
plot [][0:50] 'vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:17 title 'Before SysRem' pt 7, 'vast_lightcurve_statistics_BAND2_sysrem01.data' u 1:17 title 'SysRem x1' pt 7, 'vast_lightcurve_statistics_BAND2_sysrem06.data' u 1:17 title 'SysRem x6' pt 7, 'EB_vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:17 title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND2_sysrem01.data' u 1:17 title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND2_sysrem06.data' u 1:17 title '' pt 4 lc 7
" > chi2_band2_zoom_sysrem.gnuplot
gnuplot chi2_band2_zoom_sysrem.gnuplot


# L band2
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'L_band2.eps'
unset key
set xlabel 'F467M magnitude'
set ylabel 'L'
set format x '%4.1f'
set format y '%5.2f'
plot [][] 'vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:12 title '' pt 7, 'EB_vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:12 title '' pt 4 lc 7
" > L_band2.gnuplot
gnuplot L_band2.gnuplot


# L band2 SysRem
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'L_band2_sysrem.eps'
set xlabel 'F467M magnitude'
set ylabel 'L'
set format x '%4.1f'
set format y '%5.2f'
plot [][] 'vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:12 title 'Before SysRem' pt 7, 'vast_lightcurve_statistics_BAND2_sysrem01.data' u 1:12 title 'SysRem x1' pt 7, 'vast_lightcurve_statistics_BAND2_sysrem06.data' u 1:12 title 'SysRem x6' pt 7, 'EB_vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:12 title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND2_sysrem01.data' u 1:12 title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND2_sysrem06.data' u 1:12 title '' pt 4 lc 7
" > L_band2_sysrem.gnuplot
gnuplot L_band2_sysrem.gnuplot

# J band2
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'J_band2.eps'
unset key
set xlabel 'F467M magnitude'
set ylabel 'J'
set format x '%4.1f'
set format y '%5.2f'
plot [][] 'vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:10 title '' pt 7, 'EB_vast_lightcurve_statistics_BAND2_sigmaclip.data' u 1:10 title '' pt 4 lc 7
" > J_band2.gnuplot
gnuplot J_band2.gnuplot


# RMS band2 SysRem
echo "set terminal postscript eps enhanced color solid 'Helvetica' 20 lw 2
set output 'sigma_m_band2_sysrem.eps'
set xlabel 'F467M magnitude'
set ylabel 'Standard deviation'
set format x '%4.1f'
set format y '%5.2f'
set key top left
plot [14.5:21.5][0.0:0.1] 'vast_lightcurve_statistics_BAND2_sigmaclip.data' title 'Before SysRem' pt 7, 'vast_lightcurve_statistics_BAND2_sysrem01.data' title 'SysRem x1' pt 7, 'vast_lightcurve_statistics_BAND2_sysrem06.data' title 'SysRem x6' pt 7, 'EB_vast_lightcurve_statistics_BAND2_sigmaclip.data' title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND2_sysrem01.data' title '' pt 4 lc 7, 'EB_vast_lightcurve_statistics_BAND2_sysrem06.data' title '' pt 4 lc 7
" > sigma_m_band2_sysrem.gnuplot
gnuplot sigma_m_band2_sysrem.gnuplot

for i in *.eps ;do
 convert -density 600 $i `basename $i .eps`.jpg
done

echo "

Results plotted in .eps and converted to .jpg files. 

Enjoy! :)
" 

