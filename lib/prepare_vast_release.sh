#!/usr/bin/env bash

#
# This script will clean the VaST source tree and make it look like a freshly unpacked release tarball.
# The defaule SExtractor settings will be restored.
#

#### Restore default settings ####
cp default.sex.ccd_example default.sex
cp default.conv.backup default.conv
cp default.psfex.wide_FoV default.psfex
##################################

#### Remove all temporary files ####
rm image?????.cat*
rm test.dat test2.dat TEST
rm saved_period_search_lightcurves/*
rm run_vartools_bls_results/*
rm wcscache/*
rm astorb.dat 
rm -rf test_data
rm -rf lib/catalogs/*
rm astorb.dat
rm transient_report/*
util/clean_data.sh
#
make clean
#
rm vizquerry*.txt center*.txt all_in_one*.dat
rm -f vast_list_of_input_images_with_time_corrections.txt
rm -rf symlinks_to_images/
rm -f ds91.reg ds9.reg
rm -f vast_test_report.txt vast_test_increpmental_list_of_failed_test_codes.txt
rm -f calib.txt calib.txt_param calib.txt_param_backup
rm -f cpuinfo.txt
rm -f check.fits
rm -f transient_factory.log
rm -rf wcscache
rm -f *.gnuplot
rm -f *.eps
rm -f *.png
rm -f *_saved_limits.h
rm -f octave-workspace
rm -f vast_index_vs_mag*.txt
rm -rf candidates_report/
rm -f debugfile_*.dat
rm -f randomized_JD_*.dat
rm -f ordered_mag_*.dat
rm -f input_lightcurve_*.dat
rm -f images_sent_to_CPCS.txt
rm -f wget-log wget-log.*
rm -f `find . -name '*~'`
rm -f `find . -name '*.c_merge'`
rm -f `find . -name 'DEADJOE'`
rm -f vast_test_incremental_list_of_failed_test_codes.txt
rm -f pgplot.png pgplot.ps
rm -f rm -rf servers*.ping_ok
rm -f vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
rm -f lightcurve.tmp_emergency_stop_debug
####################################
for BADFILE in shuffled_lightcurve.txt test_lightcurve_outlier.txt test_lightcurve.tex test_lightcurve_without_outlier.txt lk.periodogram deeming.periodogram out_Cepheid_TDB_HJD_VARTOOLS.tmp out_Cepheid_TT_HJD_VaST.tmp test_heliocentric_correction.tmp test_heliocentric_correction.tmp_hjdTT test_heliocentric_correction.tmp_vartools valgrind_test.out magcalibdebug.txt A 2mass.tmp script.tmp ;do
 if [ -f "$BADFILE" ];then
  rm -f "$BADFILE"
 fi
done
####################################
if [ -d run_vartools_bls_results ];then
 rm -rf run_vartools_bls_results/
fi
####################################
if [ -d gaia_lightcurves/ ];then
 rm -rf gaia_lightcurves/
fi
####################################
# Possible leftover from the test script
if [ -d PHOTOPLATE010 ];then
 rm -rf PHOTOPLATE010/
fi
####################################
# Possible leftover dir from an aborted test
if [ -d PHOTOPLATE_TEST_SAVE ];then
 rm -rf PHOTOPLATE_TEST_SAVE/
fi
####################################
# Remove PSFEx diagnostic plots, if any
for DIAGNOSTIC_PLOT_FILE in chi2_image*.* countfrac_image*.* counts_image*.* ellipticity_image*.* fwhm_image*.* resi_image*.* *.calib2 *.calib_plane ;do
 if [ -f "$DIAGNOSTIC_PLOT_FILE" ];then
  rm -f "$DIAGNOSTIC_PLOT_FILE"
 fi
done
####################################
# Remove fake_image_hack files, if any
for DIAGNOSTIC_PLOT_FILE in fake_image_hack_*.fits ;do
 if [ -f "$DIAGNOSTIC_PLOT_FILE" ];then
  rm -f "$DIAGNOSTIC_PLOT_FILE"
 fi
done
####################################
# Remove exclusion_list files, if any
for EXCLUSION_LIST_FILE in exclusion_list.txt exclusion_list_tycho2.txt exclusion_list_bsc.txt ;do
 if [ -f "$EXCLUSION_LIST_FILE" ];then
  rm -f "$EXCLUSION_LIST_FILE"
 fi
done
####################################
# Remove core files, if any
for CORE_FILE in core.* ;do
 if [ -f "$CORE_FILE" ];then
  rm -f "$CORE_FILE"
 fi
done
####################################
# Remove fake_image_hack files, if any
for BADDIR in SIMULATOR_reference simulation_results ;do
 if [ -d "$BADDIR" ];then
  rm -rf "$BADDIR"
 fi
done


####################################
#### Update VaST documentation file ####
VASTDIR="$PWD"
cd doc
wget -c --no-parent -nd --convert-links -A".css,.html,.jpg,.gif" -p http://scan.sai.msu.ru/vast/index.html
cat index.html | sed 's:</td></tr><tr><td bgcolor="#f5f5ff">:</td></tr><tr><td bgcolor="#f5f5ff">\n\n<h2><a href="http\://scan.sai.msu.ru/vast/">The up-to-date version of this document is avaliable at http\://scan.sai.msu.ru/vast/</a></h2>:g' | sed 's:index.html:README.html:g' | sed '/<!-- CUT HERE START --!>/,/<!-- CUT HERE STOP --!>/d' > README.html
rm -f robots.txt index.html
cd "$VASTDIR"
########################################

# Update the leap seconds file
lib/update_tai-utc.sh

# Check that the fast compile option is disabled
grep -v "\#" GNUmakefile | grep --quiet 'RECOMPILE_VAST_ONLY = yes'
if [ $? -eq 0 ];then
 echo "

ERROR: please comment-out the line
RECOMPILE_VAST_ONLY = yes
in GNUmakefile before release!
"
fi

# Check that the flag image removal is enabled
grep -v '//' src/vast_limits.h | grep --quiet '#define REMOVE_FLAG_IMAGES_TO_SAVE_SPACE'
if [ $? -ne 0 ];then
 echo "
ERROR: please uncomment the line
#define REMOVE_FLAG_IMAGES_TO_SAVE_SPACE
in src/vast_limits.h before release!
"
fi

# Check that the strict magnitude and JD range check is enabled
grep -v '//' src/vast_limits.h | grep --quiet '#define STRICT_CHECK_OF_JD_AND_MAG_RANGE'
if [ $? -ne 0 ];then
 echo "
ERROR: please uncomment the line
#define STRICT_CHECK_OF_JD_AND_MAG_RANGE
in src/vast_limits.h before release!
"
fi

# Check DEBUGMESSAGES
grep -v '//' src/vast_limits.h | grep --quiet '#define DEBUGMESSAGES'
if [ $? -eq 0 ];then
 echo "
ERROR: please comment the line
#define DEBUGMESSAGES
in src/vast_limits.h before release!
"
fi

# Check DEBUGFILES
grep -v '//' src/vast_limits.h | grep --quiet '#define DEBUGFILES'
if [ $? -eq 0 ];then
 echo "
ERROR: please comment the line
#define DEBUGFILES
in src/vast_limits.h before release!
"
fi

N_LINES_BAD_REGION=`cat bad_region.lst | wc -l`
if [ $N_LINES_BAD_REGION -ne 1 ];then
 echo "
ERROR: please set up the default bad_region.lst before release!
"
fi

grep --quiet '0 0 0 0' bad_region.lst
if [ $? -ne 0 ];then
 echo "
ERROR: please set up the default bad_region.lst before release!
"
fi

# Check that no binary files are left in the source tree
for i in `find .` ;do 
 file $i | grep --quiet ELF 
 if [ $? -eq 0 ];then
  file $i >> /dev/stderr
  echo "BINARY_FILE_FOUND"
 fi
done | grep --quiet "BINARY_FILE_FOUND"
if [ $? -eq 0 ];then
 echo "ERROR: please remove the above binary file(s) from the source tree"
fi

grep -A1 'Blind solve' util/identify.sh | tail -n1 | grep --quiet '\#'
if [ $? -eq 0 ];then
 echo "
ERROR: please set up the blind plate solve mode in util/identify.sh !
"
fi


