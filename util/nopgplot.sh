#!/usr/bin/env bash
#
# This script will conduct all the computations needed for the variability search.
# No PGPlot-related programs are requiered (hence the script name). All computations may 
# be conducted on a computer without PGPlot and saved for future display on another  
# computer.
#
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Check if any lightcurve files are actually present in the directory
for i in out*dat ;do if [ -f $i ]; then break ;else echo "ERROR: There are no light curve files!!!" && exit 1 ;fi ;done

# Create the lightcurve statistics files
lib/create_data 
export LANG="POSIX"
sort -n data | awk '{printf "%10.6f %.6f %9.3f %9.3f %s\n", $1, $2, $3, $4, $5}' > data.tmp
mv data.tmp data.m_sigma
# Fitting the expected-variability-index-vs-magnitude curves is the most
# expensive step of this script on rich star fields (it re-reads all the
# lightcurves for 11 indexes over a 4-iteration 1000-point magnitude grid)
# and its output feeds VARIABLE-STAR candidate selection only - the
# transient-detection pipeline consumes the candidate list and
# vast_lightcurve_statistics.log, both of which are complete before this
# point. The transient factory therefore sets VAST_SKIP_INDEX_VS_MAG=1
# (on by default for the NMW-TTU cameras). Do NOT skip this when a SysRem
# workflow is in use: SysRem relies on the variability-index selection.
if [ -z "$VAST_SKIP_INDEX_VS_MAG" ];then
 lib/index_vs_mag > /dev/null # to supress the variable threshould output
else
 echo "VAST_SKIP_INDEX_VS_MAG is set - skipping the lib/index_vs_mag variability-index fitting"
fi

# Generate (a very optimistic) list of stars with large rms
lib/m_sigma_bin > m_sigma_bin.tmp
cp m_sigma_bin.tmp vast_stars_with_large_sigma.log

if [ "$1" = "-q" ];then
 # Quiet mode: exit without printing out the log file
 exit
fi

echo "util/nopgplot.sh is done with computations! =)
 
### vast_summary.log ###
####################################################################################"
if [ -f vast_summary.log ] ;then
 cat vast_summary.log
else
 echo "WARNING! Something may be terribly wrong: the main log file vast_summary.log is not found."
fi
echo "####################################################################################

"
