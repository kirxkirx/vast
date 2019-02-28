#!/usr/bin/env bash
#
# This script will conduct all the computations needed for the variability search.
# No PGPlot-related programs are requiered (hence the script name). All computations may 
# be conducted on a computer without PGPlot and saved for future display on another  
# computer.
#
#

# Check if any lightcurve files are actually present in the directory
for i in out*dat ;do if [ -f $i ]; then break ;else echo "ERROR: There are no light curve files!!!" && exit 1 ;fi ;done

# Create the lightcurve statistics files
lib/create_data 
export LANG="POSIX"
sort -n data | awk '{printf "%10.6f %.6f %9.3f %9.3f %s\n", $1, $2, $3, $4, $5}' > data.tmp
mv data.tmp data.m_sigma
lib/index_vs_mag

# Generate (a very optimistic) list of stars with large rms
lib/m_sigma_bin > m_sigma_bin.tmp
cp m_sigma_bin.tmp vast_stars_with_large_sigma.log

if [ "$1" = "-q" ];then
 # Quiet mode: exit without printing out the log file
 exit
fi

#echo " " >>/dev/stderr
echo "util/nopgplot.sh is done with computations! =)
 
### vast_summary.log ###
####################################################################################"
if [ -f vast_summary.log ] ;then
 cat vast_summary.log #>>/dev/stderr
else
 echo "WARNING! Something may be terribly wrong: the main log file vast_summary.log is not found." #>>/dev/stderr
fi
echo "####################################################################################

"
