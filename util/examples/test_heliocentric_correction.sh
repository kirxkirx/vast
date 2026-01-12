#!/usr/bin/env bash

command -v vartools &>/dev/null
if [ $? -ne 0 ];then
 echo "'vartools' command is not found, please install VARTOOLS" 1>&2
 exit 1
fi

TEST_PASSED=1

# Repeat the following test 100 times
ITERATION=1
while [ $ITERATION -le 100 ] ;do


############ Generate a random sky position and JD ############

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

RANDOM_JD=`echo "$RANDOM" | awk '{printf "%06.2f",2458000+$1/32767*365.242}'`

echo "Random sky position $RA_DEC_HMS and JD $RANDOM_JD" 1>&2
############################################################

############ Conver HMS->deg using VaST ############
RA_DEC_DEG_VAST=`lib/hms2deg $RA_DEC_HMS`
if [ $? -ne 0 ];then
 echo "ERROR running lib/hms2deg $RA_DEC_HMS" 1>&2
 exit 1
fi
############ Generate fake lightcurve ############
if [ -f test_heliocentric_correction.tmp ];then
 rm -f test_heliocentric_correction.tmp
fi
LIGHTCURVEPOINT=1
while [ $LIGHTCURVEPOINT -le 100 ] ;do
 JD=`echo "$RANDOM_JD $LIGHTCURVEPOINT" | awk '{printf "%.5f",$1-$2}'`
 echo "$JD 11.11 0.01" >> test_heliocentric_correction.tmp
 LIGHTCURVEPOINT=$((LIGHTCURVEPOINT+1))
done

############ Apply VaST HJD correction ############
util/hjd_input_in_UTC test_heliocentric_correction.tmp $RA_DEC_DEG_VAST &> /dev/null
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTON001"
fi
if [ ! -f test_heliocentric_correction.tmp_hjdTT ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTON002"
fi
if [ ! -s test_heliocentric_correction.tmp_hjdTT ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTON003"
fi

############ Apply VARTOOLS HJD correction ############
vartools -i test_heliocentric_correction.tmp -quiet -converttime input jd inputsys-utc output hjd outputsys-tdb radec fix $RA_DEC_DEG_VAST leapsecfile ../vast_test_lightcurves/naif0012.tls -o test_heliocentric_correction.tmp_vartools
if [ $? -ne 0 ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTON001"
fi
if [ ! -f test_heliocentric_correction.tmp_vartools ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTON002"
fi
if [ ! -s test_heliocentric_correction.tmp_vartools ];then
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTON003"
fi

############ Compare the VARTOOLS file with the VaST file ############
if [ -f HJDCORRECTON_problem.tmp ];then
 rm -f HJDCORRECTON_problem.tmp
fi
while read -r A REST && read -r B REST <&3; do 
# echo "$A-$B" | bc -ql
 # 0.00010*86400=8.6400 - assume this is an acceptable difference
 #TEST=`echo "a=($A-$B);sqrt(a*a)<0.00010" | bc -ql`
 TEST=`echo "$A $B" | awk '{if ( sqrt( ($1-$2)*($1-$2) ) < 0.00010 ) print 1 ;else print 0 }'`
 if [ $TEST -ne 1 ];then
  touch HJDCORRECTON_problem.tmp
  break
 fi
done < test_heliocentric_correction.tmp_vartools 3< test_heliocentric_correction.tmp_hjdTT
if [ -f HJDCORRECTON_problem.tmp ];then
 rm -f HJDCORRECTON_problem.tmp
 TEST_PASSED=0
 FAILED_TEST_CODES="$FAILED_TEST_CODES HJDCORRECTON008"
fi

#TEST_PASSED=0
if [ $TEST_PASSED -ne 1 ];then
 echo "HJD conversion test failed!" 1>&2
 exit 1
fi

# cleanup
if [ -f test_heliocentric_correction.tmp ];then
 rm -f test_heliocentric_correction.tmp
fi
if [ -f test_heliocentric_correction.tmp_hjdTT ];then
 rm -f test_heliocentric_correction.tmp_hjdTT
fi
if [ -f test_heliocentric_correction.tmp_vartools ];then
 rm -f test_heliocentric_correction.tmp_vartools
fi

ITERATION=$((ITERATION+1))
done # while [ $ITERATION -le 100 ]
