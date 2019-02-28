#!/bin/bash

if [ -d mypodtest_results ];then
 rm -rf mypodtest_results/
fi
mkdir mypodtest_results/


if [ -d PoD_nobadimages ];then
 rm -rf PoD_nobadimages/
fi
if [ -d PoD_nobadimages_after_CI_filter ];then
 rm -rf PoD_nobadimages_after_CI_filter/
fi
util/load.sh /mnt/usb/photometryondemand/pod_lightcurve_output_v2_outodisk/whole_image_shift/sp8_mAB/
for i in out_lightcurve_*.dat ;do NUM=`echo "$i" | awk '{print $4}' FS='_'` ; mv "$i" out"$NUM".dat ;done
lib/remove_bad_images
lib/remove_lightcurves_with_small_number_of_points 80
util/nopgplot.sh
util/save.sh PoD_nobadimages
util/load.sh PoD_nobadimages
lib/MagSize_filter_standalone
lib/remove_lightcurves_with_small_number_of_points 80
util/nopgplot.sh
util/rescale_photometric_errors
util/save.sh PoD_nobadimages_after_CI_filter

BESTFITEQUATON=`cat PoD__nobadimages_after_CI_filter/vast_rescale_photometric_errors_linear_fit_coefs.log`
echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output 'PoD__errorsrescale.eps'
set xlabel '{/Symbol s}_{estimated}'
set ylabel '{/Symbol s}_{measured}'
set title 'PoD'
set key top left
plot [][] 'PoD__nobadimages_after_CI_filter/vast_rescale_photometric_errors.log' pt 7 lc 'red' title '', $BESTFITEQUATON lc 'black' title '$BESTFITEQUATON'" | gnuplot
convert -density 150 PoD__errorsrescale.eps  -background white -alpha remove PoD__errorsrescale.png

echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output 'PoD__magMAD_befor_and_after_CI_filter.eps'
set xlabel 'F775W'
set ylabel 'MAD'
set title 'PoD'
set key bottom right
plot [13:23][-0.07:0.3] 'PoD_nobadimages/vast_lightcurve_statistics.log' u 1:14 pt 7 lc 'red' title 'before filtering', 'PoD_nobadimages_after_CI_filter/vast_lightcurve_statistics.log' u 1:14 pt 1 lc 'blue' title 'after filtering'" | gnuplot
convert -density 150 PoD__magMAD_befor_and_after_CI_filter.eps  -background white -alpha remove PoD__magMAD_befor_and_after_CI_filter.png

echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output 'PoD__magCI_filter.eps'
set xlabel 'F775W'
set ylabel 'mag(5pix) - mag(8pix)'
set title 'PoD'
plot [][0:0.6] 'PoD_nobadimages_after_CI_filter/image00003.cat.magsizefilter_passed' pt 7 lc 'black' title 'passed', 'PoD_nobadimages_after_CI_filter/image00003.cat.magsizefilter_rejected' pt 7 lc 'red' title 'rejected'" | gnuplot
convert -density 150 PoD__magCI_filter.eps  -background white -alpha remove PoD__magCI_filter.png


#if [ -d HSC_D___nobadimages ];then
# rm -rf HSC_D___nobadimages/
#fi
#if [ -d HSC_D___nobadimages_after_CI_filter ];then
# rm -rf HSC_D___nobadimages_after_CI_filter/
#fi
#util/load.sh /mnt/usb/M4_CasJobs/casjobscsvparser_results__D/F775W
#for i in out_*.dat ;do NUM=`echo "$i" | awk '{print $2}' FS='_'` ; mv "$i" out"$NUM".dat ;done
#lib/remove_bad_images
#lib/remove_lightcurves_with_small_number_of_points 80
#util/nopgplot.sh
#util/save.sh HSC_D___nobadimages
#util/load.sh HSC_D___nobadimages
#lib/MagSize_filter_standalone
#lib/remove_lightcurves_with_small_number_of_points 80
#util/nopgplot.sh
#util/save.sh HSC_D___nobadimages_after_CI_filter

echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output 'HSC_D____magMAD_befor_and_after_CI_filter.eps'
set xlabel 'F775W'
set ylabel 'MAD'
set title 'HSC\_D'
set key bottom right
plot [13:23][-0.07:0.3] 'HSC_D___nobadimages/vast_lightcurve_statistics.log' u 1:14 pt 7 lc 'red' title 'before filtering', 'HSC_D___nobadimages_after_CI_filter/vast_lightcurve_statistics.log' u 1:14 pt 1 lc 'blue' title 'after filtering'" | gnuplot
convert -density 150 HSC_D____magMAD_befor_and_after_CI_filter.eps  -background white -alpha remove HSC_D____magMAD_befor_and_after_CI_filter.png

echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output 'HSC_D____magCI_filter.eps'
set xlabel 'F775W'
set ylabel 'D'
set title 'HSC\_D'
plot [][] 'HSC_D___nobadimages_after_CI_filter/image00003.cat.magsizefilter_passed' pt 7 lc 'black' title 'passed', 'HSC_D___nobadimages_after_CI_filter/image00003.cat.magsizefilter_rejected' pt 7 lc 'red' title 'rejected'" | gnuplot
convert -density 150 HSC_D____magCI_filter.eps  -background white -alpha remove HSC_D____magCI_filter.png



if [ -d HSC_CI___nobadimages ];then
 rm -rf HSC_CI___nobadimages/
fi
if [ -d HSC_CI___nobadimages_after_CI_filter ];then
 rm -rf HSC_CI___nobadimages_after_CI_filter/
fi
util/load.sh /mnt/usb/M4_CasJobs/casjobscsvparser_results__CI/F775W
for i in out_*.dat ;do NUM=`echo "$i" | awk '{print $2}' FS='_'` ; mv "$i" out"$NUM".dat ;done
lib/remove_bad_images
lib/remove_lightcurves_with_small_number_of_points 80
util/nopgplot.sh
util/save.sh HSC_CI___nobadimages
util/load.sh HSC_CI___nobadimages
lib/MagSize_filter_standalone
lib/remove_lightcurves_with_small_number_of_points 80
util/nopgplot.sh
util/rescale_photometric_errors
util/save.sh HSC_CI___nobadimages_after_CI_filter

BESTFITEQUATON=`cat HSC_CI___nobadimages_after_CI_filter/vast_rescale_photometric_errors_linear_fit_coefs.log`
echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output 'HSC_CI___errorsrescale.eps'
set xlabel '{/Symbol s}_{estimated}'
set ylabel '{/Symbol s}_{measured}'
set title 'HSC\_CI'
set key top left
plot [][] 'HSC_CI___nobadimages_after_CI_filter/vast_rescale_photometric_errors.log' pt 7 lc 'red' title '', $BESTFITEQUATON lc 'black' title '$BESTFITEQUATON'" | gnuplot
convert -density 150 HSC_CI___errorsrescale.eps  -background white -alpha remove HSC_CI___errorsrescale.png

echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output 'HSC_CI____magMAD_befor_and_after_CI_filter.eps'
set xlabel 'F775W'
set ylabel 'MAD'
set title 'HSC\_CI'
set key bottom right
plot [13:23][-0.07:0.3] 'HSC_CI___nobadimages/vast_lightcurve_statistics.log' u 1:14 pt 7 lc 'red' title 'before filtering', 'HSC_CI___nobadimages_after_CI_filter/vast_lightcurve_statistics.log' u 1:14 pt 1 lc 'blue' title 'after filtering'" | gnuplot
convert -density 150 HSC_CI____magMAD_befor_and_after_CI_filter.eps  -background white -alpha remove HSC_CI____magMAD_befor_and_after_CI_filter.png

echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output 'HSC_CI____magCI_filter.eps'
set xlabel 'F775W'
set ylabel 'CI'
set title 'HSC\_CI'
plot [][] 'HSC_CI___nobadimages_after_CI_filter/image00003.cat.magsizefilter_passed' pt 7 lc 'black' title 'passed', 'HSC_CI___nobadimages_after_CI_filter/image00003.cat.magsizefilter_rejected' pt 7 lc 'red' title 'rejected'" | gnuplot
convert -density 150 HSC_CI____magCI_filter.eps  -background white -alpha remove HSC_CI____magCI_filter.png


#if [ -d HSC_A_IMAGE___nobadimages ];then
# rm -rf HSC_A_IMAGE___nobadimages/
#fi
#if [ -d HSC_A_IMAGE___nobadimages_after_CI_filter ];then
# rm -rf HSC_A_IMAGE___nobadimages_after_CI_filter/
#fi
#util/load.sh /mnt/usb/M4_CasJobs/casjobscsvparser_results__A_IMAGE/F775W
#for i in out_*.dat ;do NUM=`echo "$i" | awk '{print $2}' FS='_'` ; mv "$i" out"$NUM".dat ;done
#lib/remove_bad_images
#lib/remove_lightcurves_with_small_number_of_points 80
#util/nopgplot.sh
#util/save.sh HSC_A_IMAGE___nobadimages
#util/load.sh HSC_A_IMAGE___nobadimages
#lib/MagSize_filter_standalone
#lib/remove_lightcurves_with_small_number_of_points 80
#util/nopgplot.sh
#util/save.sh HSC_A_IMAGE___nobadimages_after_CI_filter

echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output 'HSC_A_IMAGE____magMAD_befor_and_after_CI_filter.eps'
set xlabel 'F775W'
set ylabel 'MAD'
set title 'HSC\_A\_IMAGE'
set key bottom right
plot [13:23][-0.07:0.3] 'HSC_A_IMAGE___nobadimages/vast_lightcurve_statistics.log' u 1:14 pt 7 lc 'red' title 'before filtering', 'HSC_A_IMAGE___nobadimages_after_CI_filter/vast_lightcurve_statistics.log' u 1:14 pt 1 lc 'blue' title 'after filtering'" | gnuplot
convert -density 150 HSC_A_IMAGE____magMAD_befor_and_after_CI_filter.eps  -background white -alpha remove HSC_A_IMAGE____magMAD_befor_and_after_CI_filter.png

echo "set terminal postscript eps enhanced color solid 'Times' 22 linewidth 2
set output 'HSC_A_IMAGE____magCI_filter.eps'
set xlabel 'F775W'
set ylabel 'A\_IMAGE (pix)'
set title 'HSC\_A\_IMAGE'
plot [][0:10] 'HSC_A_IMAGE___nobadimages_after_CI_filter/image00003.cat.magsizefilter_passed' pt 7 lc 'black' title 'passed', 'HSC_A_IMAGE___nobadimages_after_CI_filter/image00003.cat.magsizefilter_rejected' pt 7 lc 'red' title 'rejected'" | gnuplot
convert -density 150 HSC_A_IMAGE____magCI_filter.eps  -background white -alpha remove HSC_A_IMAGE____magCI_filter.png


mv *.eps *.png mypodtest_results/
