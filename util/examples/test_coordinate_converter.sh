#!/usr/bin/env bash

command -v skycoor &>/dev/null
if [ $? -ne 0 ];then
 echo "'skycoor' command is not found, please install WCSTools" >> /dev/stderr
 exit 1
fi

# Repeat the following test 1000 times
for ITERATION in `seq 1 1000` ;do


############ Generate a random sky position ############

# $RANDOM returns a different random integer at each invocation.
# Nominal range: 0 - 32767 (signed 16-bit integer).

HH=`echo "$RANDOM" | awk '{printf "%02.0f",$1/32767*23}'`
MM=`echo "$RANDOM" | awk '{printf "%02.0f",$1/32767*59}'`
SS=`echo "$RANDOM" | awk '{printf "%05.2f",$1/32767*59}'`

DD=`echo "$RANDOM" | awk '{printf "%02.0f",$1/32767*89}'`
if [ $RANDOM -ge 16383 ];then
 DD="-$DD"
fi
DM=`echo "$RANDOM" | awk '{printf "%02.0f",$1/32767*59}'`
DS=`echo "$RANDOM" | awk '{printf "%04.1f",$1/32767*59}'`

#RA_DEC_HMS="01:56:24.93 -71:04:15.7"
RA_DEC_HMS="$HH:$MM:$SS $DD:$DM:$DS"

echo "Random sky position $RA_DEC_HMS"
############################################################

############ Conver HMS->deg using WCSTools ############
RA_DEC_DEG_SKYCOOR=`skycoor -d -j $RA_DEC_HMS J2000 | awk '{print $1" "$2}'`
if [ $? -ne 0 ];then
 echo "ERROR running skycoor -d -j $RA_DEC_HMS J2000" >> /dev/stderr
 exit 1
fi
############ Conver HMS->deg using VaST ############
RA_DEC_DEG_VAST=`lib/hms2deg $RA_DEC_HMS`
if [ $? -ne 0 ];then
 echo "ERROR running lib/hms2deg $RA_DEC_HMS" >> /dev/stderr
 exit 1
fi

############ Compute distance using WCSTools, input in deg ############
DISTANCE_ARCSEC_SKYCOOR=`skycoor -r $RA_DEC_DEG_SKYCOOR $RA_DEC_DEG_VAST`
if [ $? -ne 0 ];then
 echo "ERROR running skycoor -r $RA_DEC_DEG_SKYCOOR $RA_DEC_DEG_VAST" >> /dev/stderr
 exit 1
fi
TEST=`echo "$DISTANCE_ARCSEC_SKYCOOR>0.1" | bc -ql`
if  [ $TEST -eq 1 ];then
 echo "TEST1 failed on $RA_DEC_HMS" >> /dev/stderr
 exit 1
fi
############ Compute distance using VaST, input in deg ############
DISTANCE_ARCSEC_VAST=`lib/put_two_sources_in_one_field $RA_DEC_DEG_SKYCOOR $RA_DEC_DEG_VAST 2>/dev/null | grep 'Angular distance' | awk '{print $5*3600}'`
if [ $? -ne 0 ];then
 echo "ERROR running lib/put_two_sources_in_one_field $RA_DEC_DEG_SKYCOOR $RA_DEC_DEG_VAST" >> /dev/stderr
 exit 1
fi
TEST=`echo "$DISTANCE_ARCSEC_VAST>0.1" | bc -ql`
if  [ $TEST -eq 1 ];then
 echo "TEST2 failed on $RA_DEC_HMS" >> /dev/stderr
 exit 1
fi

############ Convert deg back to HMS using VaST ############
RA_DEC_HMS_converted_back_from_deg_with_VAST=`lib/deg2hms $RA_DEC_DEG_VAST`

############ Compute distance using WCSTools, input in HMS ############
DISTANCE_ARCSEC_SKYCOOR=`skycoor -r $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_VAST`
if [ $? -ne 0 ];then
 echo "ERROR running skycoor -r $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_VAST" >> /dev/stderr
 exit 1
fi
TEST=`echo "$DISTANCE_ARCSEC_SKYCOOR>0.1" | bc -ql`
if  [ $TEST -eq 1 ];then
 echo "TEST3 failed on $RA_DEC_HMS" >> /dev/stderr
 exit 1
fi
############ Compute distance using VaST, input in HMS ############
DISTANCE_ARCSEC_VAST=`lib/put_two_sources_in_one_field $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_VAST 2>/dev/null | grep 'Angular distance' | awk '{print $5*3600}'`
if [ $? -ne 0 ];then
 echo "ERROR running lib/put_two_sources_in_one_field $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_VAST" >> /dev/stderr
 exit 1
fi
TEST=`echo "$DISTANCE_ARCSEC_VAST>0.1" | bc -ql`
if  [ $TEST -eq 1 ];then
 echo "TEST4 failed on $RA_DEC_HMS" >> /dev/stderr
 exit 1
fi

############ Convert deg back to HMS using WCSTools ############
RA_DEC_HMS_converted_back_from_deg_with_WCSTOOLS=`skycoor -j  $RA_DEC_DEG_VAST J2000 | awk '{print $1" "$2}'`

############ Compute distance using WCSTools, input in HMS ############
DISTANCE_ARCSEC_SKYCOOR=`skycoor -r $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_WCSTOOLS`
if [ $? -ne 0 ];then
 echo "ERROR running skycoor -r $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_WCSTOOLS" >> /dev/stderr
 exit 1
fi
TEST=`echo "$DISTANCE_ARCSEC_SKYCOOR>0.1" | bc -ql`
if  [ $TEST -eq 1 ];then
 echo "TEST5 failed on $RA_DEC_HMS" >> /dev/stderr
 exit 1
fi
############ Compute distance using VaST, input in HMS ############
DISTANCE_ARCSEC_VAST=`lib/put_two_sources_in_one_field $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_WCSTOOLS 2>/dev/null | grep 'Angular distance' | awk '{print $5*3600}'`
if [ $? -ne 0 ];then
 echo "ERROR running lib/put_two_sources_in_one_field $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_WCSTOOLS" >> /dev/stderr
 exit 1
fi
TEST=`echo "$DISTANCE_ARCSEC_VAST>0.1" | bc -ql`
if  [ $TEST -eq 1 ];then
 echo "TEST6 failed on $RA_DEC_HMS" >> /dev/stderr
 exit 1
fi



############ Convert deg back to HMS using VaST ############
RA_DEC_HMS_converted_back_from_deg_with_VAST=`lib/deg2hms $RA_DEC_DEG_SKYCOOR`

############ Compute distance using WCSTools, input in HMS ############
DISTANCE_ARCSEC_SKYCOOR=`skycoor -r $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_VAST`
if [ $? -ne 0 ];then
 echo "ERROR running skycoor -r $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_VAST" >> /dev/stderr
 exit 1
fi
TEST=`echo "$DISTANCE_ARCSEC_SKYCOOR>0.1" | bc -ql`
if  [ $TEST -eq 1 ];then
 echo "TEST7 failed on $RA_DEC_HMS" >> /dev/stderr
 exit 1
fi
############ Compute distance using VaST, input in HMS ############
DISTANCE_ARCSEC_VAST=`lib/put_two_sources_in_one_field $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_VAST 2>/dev/null | grep 'Angular distance' | awk '{print $5*3600}'`
if [ $? -ne 0 ];then
 echo "ERROR running lib/put_two_sources_in_one_field $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_VAST" >> /dev/stderr
 exit 1
fi
TEST=`echo "$DISTANCE_ARCSEC_VAST>0.1" | bc -ql`
if  [ $TEST -eq 1 ];then
 echo "TEST8 failed on $RA_DEC_HMS" >> /dev/stderr
 exit 1
fi

############ Convert deg back to HMS using WCSTools ############
RA_DEC_HMS_converted_back_from_deg_with_WCSTOOLS=`skycoor -j  $RA_DEC_DEG_SKYCOOR J2000 | awk '{print $1" "$2}'`

############ Compute distance using WCSTools, input in HMS ############
DISTANCE_ARCSEC_SKYCOOR=`skycoor -r $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_WCSTOOLS`
if [ $? -ne 0 ];then
 echo "ERROR running skycoor -r $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_WCSTOOLS" >> /dev/stderr
 exit 1
fi
TEST=`echo "$DISTANCE_ARCSEC_SKYCOOR>0.1" | bc -ql`
if  [ $TEST -eq 1 ];then
 echo "TEST9 failed on $RA_DEC_HMS" >> /dev/stderr
 exit 1
fi
############ Compute distance using VaST, input in HMS ############
DISTANCE_ARCSEC_VAST=`lib/put_two_sources_in_one_field $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_WCSTOOLS 2>/dev/null | grep 'Angular distance' | awk '{print $5*3600}'`
if [ $? -ne 0 ];then
 echo "ERROR running lib/put_two_sources_in_one_field $RA_DEC_HMS $RA_DEC_HMS_converted_back_from_deg_with_WCSTOOLS" >> /dev/stderr
 exit 1
fi
TEST=`echo "$DISTANCE_ARCSEC_VAST>0.1" | bc -ql`
if  [ $TEST -eq 1 ];then
 echo "TEST10 failed on $RA_DEC_HMS" >> /dev/stderr
 exit 1
fi





done # ITERATION
