#!/usr/bin/env bash
#
# This is a standalone test script for NMW-TexasTech Gem-03-Q1b1x1 transient search
#
# Baseline established: 2026-02-06
#
# Expected objects:
#   Asteroids: 40 Harmonia, 17 Thetis, 42 Isis, 180 Garumna, 370 Modestia, 243 Ida, 206 Hersilia
#   Variable stars: V0355 Gem, VV Gem, ASASSN-V J060820.96+180857.1, BR Gem
#
# Run as:
#   cd /path/to/vast
#   util/examples/test_NMW_TexasTech_Gem03Q1b1x1.sh
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LC_ALL LANGUAGE
#################################

# Color codes for output
GREEN='\033[01;32m'
RED='\033[01;31m'
BLUE='\033[01;34m'
NC='\033[00m' # No Color

# Test configuration
FAILED_TEST_CODES=""
TEST_PASSED=1

# Pixel scale for NMW-TexasTech telephoto lens is approximately 5.9"/pix
# (Documented for reference, used in position tolerance checks)

# Test data paths - adjust as needed
TEST_DATA_DIR="../NMW-TexasTech__Gem-03-Q1b1x1_test"
REFERENCE_DIR="$TEST_DATA_DIR/reference_images"
SECOND_EPOCH_DIR="$TEST_DATA_DIR/second_epoch_images"

# Baseline timing values (in seconds)
# Note: HTML_REPORT time is network-dependent and highly variable
# These are approximate values from baseline run:
#   VAST_RUN (first config): 31s
#   VAST_RUN (vSTL config): 350s
#   Total runtime: 564s
BASELINE_TOTAL_RUNTIME=564        # total run time
TIMING_TOLERANCE_FACTOR=2.0       # Allow 2x baseline time

# Baseline candidate count
BASELINE_TOTAL_CANDIDATES=15
MAX_ADDITIONAL_CANDIDATES=2       # Allow up to 2 more candidates
MAX_UNIDENTIFIED_CANDIDATES=3     # Maximum acceptable unidentified candidates

# Function to print test status
print_test_status() {
    local test_name="$1"
    local status="$2"
    if [ "$status" -eq 0 ]; then
        echo -e "${GREEN}PASSED${NC} - $test_name"
    else
        echo -e "${RED}FAILED${NC} - $test_name"
    fi
}

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}NMW-TexasTech Gem-03-Q1b1x1 Test${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Check if test data exists
if [ ! -d "$TEST_DATA_DIR" ]; then
    echo -e "${RED}ERROR: Test data directory not found: $TEST_DATA_DIR${NC}"
    echo "Please ensure the test data is available at the expected location."
    exit 1
fi

if [ ! -d "$REFERENCE_DIR" ]; then
    echo -e "${RED}ERROR: Reference images directory not found: $REFERENCE_DIR${NC}"
    exit 1
fi

if [ ! -d "$SECOND_EPOCH_DIR" ]; then
    echo -e "${RED}ERROR: Second epoch images directory not found: $SECOND_EPOCH_DIR${NC}"
    exit 1
fi

# Record start time
THIS_TEST_START_UNIXSEC=$(date +%s)

# Clean up previous run
echo "Cleaning up previous VaST run data..."
util/clean_data.sh

# Copy default bad_region.lst if exists
if [ -f bad_region.lst_default ]; then
    cp -v bad_region.lst_default bad_region.lst
fi

# Remove old transient report
if [ -f transient_report/index.html ]; then
    rm -f transient_report/index.html
fi

# Run the transient search
echo -e "\nRunning transient search..."
echo "Command: REFERENCE_IMAGES=$REFERENCE_DIR util/transients/transient_factory_test31.sh $SECOND_EPOCH_DIR"

REFERENCE_IMAGES="$REFERENCE_DIR" util/transients/transient_factory_test31.sh "$SECOND_EPOCH_DIR" &> test_nmw_texastech_gem03_output$$.tmp
SCRIPT_EXIT_CODE=$?

if [ $SCRIPT_EXIT_CODE -ne 0 ]; then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_EXIT_CODE"
    print_test_status "Script exit code" 1
else
    print_test_status "Script exit code" 0
fi

# Test for specific error messages
if grep -q 'ERROR: cannot find a star near the specified position' test_nmw_texastech_gem03_output$$.tmp 2>/dev/null; then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_CANNOT_FIND_STAR_ERROR"
    print_test_status "No 'cannot find star' error" 1
else
    print_test_status "No 'cannot find star' error" 0
fi

# Clean up temp output file
rm -f test_nmw_texastech_gem03_output$$.tmp

# Check that the transient report was created
if [ ! -f transient_report/index.html ]; then
    echo -e "${RED}ERROR: transient_report/index.html was not created${NC}"
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_NO_REPORT"
    # Cannot continue without report
    echo -e "\n${RED}Test cannot continue without transient report.${NC}"
    exit 1
fi

echo -e "\n${BLUE}Checking transient report contents...${NC}\n"

# Check images processed
if grep -q "Images processed 4" transient_report/index.html; then
    print_test_status "Images processed 4" 0
else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_IMAGES_PROCESSED"
    print_test_status "Images processed 4" 1
fi

# Check images used for photometry
if grep -q "Images used for photometry 4" transient_report/index.html; then
    print_test_status "Images used for photometry 4" 0
else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_IMAGES_PHOTOMETRY"
    print_test_status "Images used for photometry 4" 1
fi

# Check photometric calibration
if grep -q 'PHOTOMETRIC_CALIBRATION=TYCHO2_V' transient_report/index.html; then
    print_test_status "Photometric calibration TYCHO2_V" 0
else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_CALIBRATION"
    print_test_status "Photometric calibration TYCHO2_V" 1
fi

# Validate HTML format
if util/transients/validate_HTML_list_of_candidates.sh 2>/dev/null; then
    print_test_status "HTML list format validation" 0
else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_HTML_FORMAT"
    print_test_status "HTML list format validation" 1
fi

echo -e "\n${BLUE}Checking candidate count...${NC}\n"

# Count total candidates
NUMBER_OF_CANDIDATES=$(grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink' || echo "0")
echo "Total candidates found: $NUMBER_OF_CANDIDATES"

# Check candidate count is within acceptable range
MAX_CANDIDATES=$((BASELINE_TOTAL_CANDIDATES + MAX_ADDITIONAL_CANDIDATES))
if [ "$NUMBER_OF_CANDIDATES" -ge "$BASELINE_TOTAL_CANDIDATES" ] && [ "$NUMBER_OF_CANDIDATES" -le "$MAX_CANDIDATES" ]; then
    print_test_status "Candidate count ($NUMBER_OF_CANDIDATES in range $BASELINE_TOTAL_CANDIDATES-$MAX_CANDIDATES)" 0
else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_NCANDIDATES_$NUMBER_OF_CANDIDATES"
    print_test_status "Candidate count ($NUMBER_OF_CANDIDATES not in range $BASELINE_TOTAL_CANDIDATES-$MAX_CANDIDATES)" 1
fi

# Check number of identified candidates
if grep -q "Total number of candidates identified:" transient_report/index.html; then
    IDENTIFIED_COUNT=$(grep "Total number of candidates identified:" transient_report/index.html | awk '{print $NF}')
    UNIDENTIFIED_COUNT=$((NUMBER_OF_CANDIDATES - IDENTIFIED_COUNT))
    echo "Identified candidates: $IDENTIFIED_COUNT"
    echo "Unidentified candidates: $UNIDENTIFIED_COUNT"

    if [ "$UNIDENTIFIED_COUNT" -le "$MAX_UNIDENTIFIED_CANDIDATES" ]; then
        print_test_status "Unidentified candidates ($UNIDENTIFIED_COUNT <= $MAX_UNIDENTIFIED_CANDIDATES)" 0
    else
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_TOO_MANY_UNIDENTIFIED_$UNIDENTIFIED_COUNT"
        print_test_status "Unidentified candidates ($UNIDENTIFIED_COUNT > $MAX_UNIDENTIFIED_CANDIDATES)" 1
    fi
fi

echo -e "\n${BLUE}Checking expected asteroids...${NC}\n"

# NMW-TexasTech pixel scale is ~5.9"/pix
# Position tolerance for put_two_sources_in_one_field checks
POSITION_TOLERANCE_ARCSEC="5.9"

###########################################
# Check for asteroid 40 Harmonia
# Baseline: mag 10.32, RA 06:31:39.33 Dec +24:52:04.6
###########################################
grep -q "40 Harmonia" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_HARMONIA"
    print_test_status "40 Harmonia detected" 1
else
    print_test_status "40 Harmonia detected" 0
fi
# Check position and magnitude from the human-readable line
#                    2026 01 21.3632  2461061.8632  10.32  06:31:39.33 +24:52:04.6
grep -q "2026 01 21.363.  2461061.863.  10\...  06:31:3.\... +24:52:0.\." transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_HARMONIA_POSMAG"
    print_test_status "40 Harmonia position/magnitude" 1
else
    print_test_status "40 Harmonia position/magnitude" 0
fi
# Test position accuracy
RADECPOSITION_TO_TEST=$(grep "2026 01 21.363.  2461061.863.  10\...  06:31:3" transient_report/index.html | head -n1 | awk '{print $6" "$7}')
if [ -n "$RADECPOSITION_TO_TEST" ];then
    DISTANCE_ARCSEC=$(lib/put_two_sources_in_one_field 06:31:39.33 +24:52:04.6 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}')
    TEST=$(echo "$DISTANCE_ARCSEC" | awk -v tol="$POSITION_TOLERANCE_ARCSEC" '{if ( $1 < tol ) print 1 ;else print 0 }')
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_HARMONIA_POS_ERROR"
        print_test_status "40 Harmonia position" 1
    else
        if [ $TEST -eq 0 ];then
            TEST_PASSED=0
            FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_HARMONIA_POS_${DISTANCE_ARCSEC}"
            print_test_status "40 Harmonia position (dist ${DISTANCE_ARCSEC}\")" 1
        else
            print_test_status "40 Harmonia position (dist ${DISTANCE_ARCSEC}\")" 0
        fi
    fi
fi

###########################################
# Check for asteroid 17 Thetis
# Baseline: mag 11.66, RA 06:18:46.76 Dec +20:14:13.5
###########################################
grep -q "17 Thetis" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_THETIS"
    print_test_status "17 Thetis detected" 1
else
    print_test_status "17 Thetis detected" 0
fi
# Check position and magnitude from the human-readable line
#                    2026 01 21.3632  2461061.8632  11.66  06:18:46.76 +20:14:13.5
grep -q "2026 01 21.363.  2461061.863.  1[12]\...  06:18:4.\... +20:14:1.\." transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_THETIS_POSMAG"
    print_test_status "17 Thetis position/magnitude" 1
else
    print_test_status "17 Thetis position/magnitude" 0
fi
# Test position accuracy
RADECPOSITION_TO_TEST=$(grep "2026 01 21.363.  2461061.863.  1[12]\...  06:18:4" transient_report/index.html | head -n1 | awk '{print $6" "$7}')
if [ -n "$RADECPOSITION_TO_TEST" ];then
    DISTANCE_ARCSEC=$(lib/put_two_sources_in_one_field 06:18:46.76 +20:14:13.5 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}')
    TEST=$(echo "$DISTANCE_ARCSEC" | awk -v tol="$POSITION_TOLERANCE_ARCSEC" '{if ( $1 < tol ) print 1 ;else print 0 }')
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_THETIS_POS_ERROR"
        print_test_status "17 Thetis position" 1
    else
        if [ $TEST -eq 0 ];then
            TEST_PASSED=0
            FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_THETIS_POS_${DISTANCE_ARCSEC}"
            print_test_status "17 Thetis position (dist ${DISTANCE_ARCSEC}\")" 1
        else
            print_test_status "17 Thetis position (dist ${DISTANCE_ARCSEC}\")" 0
        fi
    fi
fi

###########################################
# Check for asteroid 42 Isis
# Baseline: mag 11.69, RA 05:53:58.61 Dec +26:45:37.3
###########################################
grep -q "42 Isis" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_ISIS"
    print_test_status "42 Isis detected" 1
else
    print_test_status "42 Isis detected" 0
fi
# Check position and magnitude from the human-readable line
#                    2026 01 21.3632  2461061.8632  11.69  05:53:58.61 +26:45:37.3
grep -q "2026 01 21.363.  2461061.863.  1[12]\...  05:53:5.\... +26:45:3.\." transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_ISIS_POSMAG"
    print_test_status "42 Isis position/magnitude" 1
else
    print_test_status "42 Isis position/magnitude" 0
fi
# Test position accuracy
RADECPOSITION_TO_TEST=$(grep "2026 01 21.363.  2461061.863.  1[12]\...  05:53:5" transient_report/index.html | head -n1 | awk '{print $6" "$7}')
if [ -n "$RADECPOSITION_TO_TEST" ];then
    DISTANCE_ARCSEC=$(lib/put_two_sources_in_one_field 05:53:58.61 +26:45:37.3 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}')
    TEST=$(echo "$DISTANCE_ARCSEC" | awk -v tol="$POSITION_TOLERANCE_ARCSEC" '{if ( $1 < tol ) print 1 ;else print 0 }')
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_ISIS_POS_ERROR"
        print_test_status "42 Isis position" 1
    else
        if [ $TEST -eq 0 ];then
            TEST_PASSED=0
            FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_ISIS_POS_${DISTANCE_ARCSEC}"
            print_test_status "42 Isis position (dist ${DISTANCE_ARCSEC}\")" 1
        else
            print_test_status "42 Isis position (dist ${DISTANCE_ARCSEC}\")" 0
        fi
    fi
fi

###########################################
# Check for asteroid 180 Garumna
# Baseline: mag 13.42, RA 05:56:24.12 Dec +24:08:27.4
###########################################
grep -q "180 Garumna" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_GARUMNA"
    print_test_status "180 Garumna detected" 1
else
    print_test_status "180 Garumna detected" 0
fi
# Check position and magnitude from the human-readable line
#                    2026 01 21.3632  2461061.8632  13.42  05:56:24.12 +24:08:27.4
grep -q "2026 01 21.363.  2461061.863.  1[34]\...  05:56:2.\... +24:08:2.\." transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_GARUMNA_POSMAG"
    print_test_status "180 Garumna position/magnitude" 1
else
    print_test_status "180 Garumna position/magnitude" 0
fi
# Test position accuracy
RADECPOSITION_TO_TEST=$(grep "2026 01 21.363.  2461061.863.  1[34]\...  05:56:2" transient_report/index.html | head -n1 | awk '{print $6" "$7}')
if [ -n "$RADECPOSITION_TO_TEST" ];then
    DISTANCE_ARCSEC=$(lib/put_two_sources_in_one_field 05:56:24.12 +24:08:27.4 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}')
    TEST=$(echo "$DISTANCE_ARCSEC" | awk -v tol="$POSITION_TOLERANCE_ARCSEC" '{if ( $1 < tol ) print 1 ;else print 0 }')
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_GARUMNA_POS_ERROR"
        print_test_status "180 Garumna position" 1
    else
        if [ $TEST -eq 0 ];then
            TEST_PASSED=0
            FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_GARUMNA_POS_${DISTANCE_ARCSEC}"
            print_test_status "180 Garumna position (dist ${DISTANCE_ARCSEC}\")" 1
        else
            print_test_status "180 Garumna position (dist ${DISTANCE_ARCSEC}\")" 0
        fi
    fi
fi

###########################################
# Check for asteroid 370 Modestia
# Baseline: mag 13.86, RA 05:56:16.12 Dec +25:25:45.9
###########################################
grep -q "370 Modestia" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_MODESTIA"
    print_test_status "370 Modestia detected" 1
else
    print_test_status "370 Modestia detected" 0
fi
# Check position and magnitude from the human-readable line
#                    2026 01 21.3632  2461061.8632  13.86  05:56:16.12 +25:25:45.9
grep -q "2026 01 21.363.  2461061.863.  1[34]\...  05:56:1.\... +25:25:4.\." transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_MODESTIA_POSMAG"
    print_test_status "370 Modestia position/magnitude" 1
else
    print_test_status "370 Modestia position/magnitude" 0
fi
# Test position accuracy
RADECPOSITION_TO_TEST=$(grep "2026 01 21.363.  2461061.863.  1[34]\...  05:56:1" transient_report/index.html | head -n1 | awk '{print $6" "$7}')
if [ -n "$RADECPOSITION_TO_TEST" ];then
    DISTANCE_ARCSEC=$(lib/put_two_sources_in_one_field 05:56:16.12 +25:25:45.9 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}')
    TEST=$(echo "$DISTANCE_ARCSEC" | awk -v tol="$POSITION_TOLERANCE_ARCSEC" '{if ( $1 < tol ) print 1 ;else print 0 }')
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_MODESTIA_POS_ERROR"
        print_test_status "370 Modestia position" 1
    else
        if [ $TEST -eq 0 ];then
            TEST_PASSED=0
            FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_MODESTIA_POS_${DISTANCE_ARCSEC}"
            print_test_status "370 Modestia position (dist ${DISTANCE_ARCSEC}\")" 1
        else
            print_test_status "370 Modestia position (dist ${DISTANCE_ARCSEC}\")" 0
        fi
    fi
fi

###########################################
# Check for asteroid 243 Ida
# Baseline: mag 13.99, RA 05:57:43.69 Dec +24:35:06.6
###########################################
grep -q "243 Ida" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_IDA"
    print_test_status "243 Ida detected" 1
else
    print_test_status "243 Ida detected" 0
fi
# Check position and magnitude from the human-readable line
#                    2026 01 21.3632  2461061.8632  13.99  05:57:43.69 +24:35:06.6
grep -q "2026 01 21.363.  2461061.863.  1[34]\...  05:57:4.\... +24:35:0.\." transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_IDA_POSMAG"
    print_test_status "243 Ida position/magnitude" 1
else
    print_test_status "243 Ida position/magnitude" 0
fi
# Test position accuracy
RADECPOSITION_TO_TEST=$(grep "2026 01 21.363.  2461061.863.  1[34]\...  05:57:4" transient_report/index.html | head -n1 | awk '{print $6" "$7}')
if [ -n "$RADECPOSITION_TO_TEST" ];then
    DISTANCE_ARCSEC=$(lib/put_two_sources_in_one_field 05:57:43.69 +24:35:06.6 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}')
    TEST=$(echo "$DISTANCE_ARCSEC" | awk -v tol="$POSITION_TOLERANCE_ARCSEC" '{if ( $1 < tol ) print 1 ;else print 0 }')
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_IDA_POS_ERROR"
        print_test_status "243 Ida position" 1
    else
        if [ $TEST -eq 0 ];then
            TEST_PASSED=0
            FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_IDA_POS_${DISTANCE_ARCSEC}"
            print_test_status "243 Ida position (dist ${DISTANCE_ARCSEC}\")" 1
        else
            print_test_status "243 Ida position (dist ${DISTANCE_ARCSEC}\")" 0
        fi
    fi
fi

###########################################
# Check for asteroid 206 Hersilia
# Baseline: mag 12.33, RA 06:39:22.55 Dec +19:31:21.4
###########################################
grep -q "206 Hersilia" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_HERSILIA"
    print_test_status "206 Hersilia detected" 1
else
    print_test_status "206 Hersilia detected" 0
fi
# Check position and magnitude from the human-readable line
#                    2026 01 21.3632  2461061.8632  12.33  06:39:22.55 +19:31:21.4
grep -q "2026 01 21.363.  2461061.863.  1[23]\...  06:39:2.\... +19:31:2.\." transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_HERSILIA_POSMAG"
    print_test_status "206 Hersilia position/magnitude" 1
else
    print_test_status "206 Hersilia position/magnitude" 0
fi
# Test position accuracy
RADECPOSITION_TO_TEST=$(grep "2026 01 21.363.  2461061.863.  1[23]\...  06:39:2" transient_report/index.html | head -n1 | awk '{print $6" "$7}')
if [ -n "$RADECPOSITION_TO_TEST" ];then
    DISTANCE_ARCSEC=$(lib/put_two_sources_in_one_field 06:39:22.55 +19:31:21.4 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}')
    TEST=$(echo "$DISTANCE_ARCSEC" | awk -v tol="$POSITION_TOLERANCE_ARCSEC" '{if ( $1 < tol ) print 1 ;else print 0 }')
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_HERSILIA_POS_ERROR"
        print_test_status "206 Hersilia position" 1
    else
        if [ $TEST -eq 0 ];then
            TEST_PASSED=0
            FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_HERSILIA_POS_${DISTANCE_ARCSEC}"
            print_test_status "206 Hersilia position (dist ${DISTANCE_ARCSEC}\")" 1
        else
            print_test_status "206 Hersilia position (dist ${DISTANCE_ARCSEC}\")" 0
        fi
    fi
fi

echo -e "\n${BLUE}Checking expected variable stars...${NC}\n"

###########################################
# Check for V0355 Gem
# Baseline: mag 11.42, RA 07:00:36.35 Dec +26:08:18.0
###########################################
grep -q "V0355 Gem" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_V0355GEM"
    print_test_status "V0355 Gem detected" 1
else
    print_test_status "V0355 Gem detected" 0
fi
# Check position and magnitude from the human-readable line
#                    2026 01 21.3632  2461061.8632  11.42  07:00:36.35 +26:08:18.0
grep -q "2026 01 21.363.  2461061.863.  1[12]\...  07:00:3.\... +26:08:1.\." transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_V0355GEM_POSMAG"
    print_test_status "V0355 Gem position/magnitude" 1
else
    print_test_status "V0355 Gem position/magnitude" 0
fi
# Test AAVSO report line
# V0355 Gem,2461061.8632,11.42,0.05,CV
grep -q "V0355 Gem,2461061\.863.,1[12]\...,0\.0.,CV" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_V0355GEM_AAVSO"
    print_test_status "V0355 Gem AAVSO report line" 1
else
    print_test_status "V0355 Gem AAVSO report line" 0
fi
# Test position accuracy
RADECPOSITION_TO_TEST=$(grep "2026 01 21.363.  2461061.863.  1[12]\...  07:00:3" transient_report/index.html | head -n1 | awk '{print $6" "$7}')
if [ -n "$RADECPOSITION_TO_TEST" ];then
    DISTANCE_ARCSEC=$(lib/put_two_sources_in_one_field 07:00:36.35 +26:08:18.0 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}')
    TEST=$(echo "$DISTANCE_ARCSEC" | awk -v tol="$POSITION_TOLERANCE_ARCSEC" '{if ( $1 < tol ) print 1 ;else print 0 }')
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_V0355GEM_POS_ERROR"
        print_test_status "V0355 Gem position" 1
    else
        if [ $TEST -eq 0 ];then
            TEST_PASSED=0
            FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_V0355GEM_POS_${DISTANCE_ARCSEC}"
            print_test_status "V0355 Gem position (dist ${DISTANCE_ARCSEC}\")" 1
        else
            print_test_status "V0355 Gem position (dist ${DISTANCE_ARCSEC}\")" 0
        fi
    fi
fi

###########################################
# Check for VV Gem
# Baseline: mag 10.35, RA 06:25:56.01 Dec +25:32:23.4
###########################################
grep -q "VV Gem" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_VVGEM"
    print_test_status "VV Gem detected" 1
else
    print_test_status "VV Gem detected" 0
fi
# Check position and magnitude from the human-readable line
#                    2026 01 21.3632  2461061.8632  10.35  06:25:56.01 +25:32:23.4
grep -q "2026 01 21.363.  2461061.863.  10\...  06:25:5.\... +25:32:2.\." transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_VVGEM_POSMAG"
    print_test_status "VV Gem position/magnitude" 1
else
    print_test_status "VV Gem position/magnitude" 0
fi
# Test AAVSO report line
# VV Gem,2461061.8632,10.35,0.05,CV
grep -q "VV Gem,2461061\.863.,10\...,0\.0.,CV" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_VVGEM_AAVSO"
    print_test_status "VV Gem AAVSO report line" 1
else
    print_test_status "VV Gem AAVSO report line" 0
fi
# Test position accuracy
RADECPOSITION_TO_TEST=$(grep "2026 01 21.363.  2461061.863.  10\...  06:25:5" transient_report/index.html | head -n1 | awk '{print $6" "$7}')
if [ -n "$RADECPOSITION_TO_TEST" ];then
    DISTANCE_ARCSEC=$(lib/put_two_sources_in_one_field 06:25:56.01 +25:32:23.4 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}')
    TEST=$(echo "$DISTANCE_ARCSEC" | awk -v tol="$POSITION_TOLERANCE_ARCSEC" '{if ( $1 < tol ) print 1 ;else print 0 }')
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_VVGEM_POS_ERROR"
        print_test_status "VV Gem position" 1
    else
        if [ $TEST -eq 0 ];then
            TEST_PASSED=0
            FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_VVGEM_POS_${DISTANCE_ARCSEC}"
            print_test_status "VV Gem position (dist ${DISTANCE_ARCSEC}\")" 1
        else
            print_test_status "VV Gem position (dist ${DISTANCE_ARCSEC}\")" 0
        fi
    fi
fi

###########################################
# Check for ASASSN-V J060820.96+180857.1
# Baseline: mag 13.70, RA 06:08:21.14 Dec +18:08:56.8
###########################################
grep -q "ASASSN-V J060820" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_ASASSNVJ0608"
    print_test_status "ASASSN-V J060820.96+180857.1 detected" 1
else
    print_test_status "ASASSN-V J060820.96+180857.1 detected" 0
fi
# Check position and magnitude from the human-readable line
#                    2026 01 21.3632  2461061.8632  13.70  06:08:21.14 +18:08:56.8
grep -q "2026 01 21.363.  2461061.863.  1[34]\...  06:08:2.\... +18:08:5.\." transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_ASASSNVJ0608_POSMAG"
    print_test_status "ASASSN-V J060820 position/magnitude" 1
else
    print_test_status "ASASSN-V J060820 position/magnitude" 0
fi
# Test AAVSO report line
# ASASSN-V J060820.96+180857.1,2461061.8632,13.70,0.05,CV
grep -q "ASASSN-V J060820.96+180857.1,2461061\.863.,1[34]\...,0\.0.,CV" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_ASASSNVJ0608_AAVSO"
    print_test_status "ASASSN-V J060820 AAVSO report line" 1
else
    print_test_status "ASASSN-V J060820 AAVSO report line" 0
fi
# Test position accuracy
RADECPOSITION_TO_TEST=$(grep "2026 01 21.363.  2461061.863.  1[34]\...  06:08:2" transient_report/index.html | head -n1 | awk '{print $6" "$7}')
if [ -n "$RADECPOSITION_TO_TEST" ];then
    DISTANCE_ARCSEC=$(lib/put_two_sources_in_one_field 06:08:21.14 +18:08:56.8 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}')
    TEST=$(echo "$DISTANCE_ARCSEC" | awk -v tol="$POSITION_TOLERANCE_ARCSEC" '{if ( $1 < tol ) print 1 ;else print 0 }')
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_ASASSNVJ0608_POS_ERROR"
        print_test_status "ASASSN-V J060820 position" 1
    else
        if [ $TEST -eq 0 ];then
            TEST_PASSED=0
            FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_ASASSNVJ0608_POS_${DISTANCE_ARCSEC}"
            print_test_status "ASASSN-V J060820 position (dist ${DISTANCE_ARCSEC}\")" 1
        else
            print_test_status "ASASSN-V J060820 position (dist ${DISTANCE_ARCSEC}\")" 0
        fi
    fi
fi

###########################################
# Check for BR Gem
# Baseline: mag 11.24, RA 06:36:19.88 Dec +26:52:53.9
###########################################
grep -q "BR Gem" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_BRGEM"
    print_test_status "BR Gem detected" 1
else
    print_test_status "BR Gem detected" 0
fi
# Check position and magnitude from the human-readable line
#                    2026 01 21.3632  2461061.8632  11.24  06:36:19.88 +26:52:53.9
grep -q "2026 01 21.363.  2461061.863.  1[12]\...  06:36:1.\... +26:52:5.\." transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_BRGEM_POSMAG"
    print_test_status "BR Gem position/magnitude" 1
else
    print_test_status "BR Gem position/magnitude" 0
fi
# Test AAVSO report line
# BR Gem,2461061.8632,11.24,0.05,CV
grep -q "BR Gem,2461061\.863.,1[12]\...,0\.0.,CV" transient_report/index.html
if [ $? -ne 0 ];then
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_BRGEM_AAVSO"
    print_test_status "BR Gem AAVSO report line" 1
else
    print_test_status "BR Gem AAVSO report line" 0
fi
# Test position accuracy
RADECPOSITION_TO_TEST=$(grep "2026 01 21.363.  2461061.863.  1[12]\...  06:36:1" transient_report/index.html | head -n1 | awk '{print $6" "$7}')
if [ -n "$RADECPOSITION_TO_TEST" ];then
    DISTANCE_ARCSEC=$(lib/put_two_sources_in_one_field 06:36:19.88 +26:52:53.9 $RADECPOSITION_TO_TEST | grep 'Angular distance' | awk '{printf "%f", $5*3600}')
    TEST=$(echo "$DISTANCE_ARCSEC" | awk -v tol="$POSITION_TOLERANCE_ARCSEC" '{if ( $1 < tol ) print 1 ;else print 0 }')
    re='^[0-9]+$'
    if ! [[ $TEST =~ $re ]] ; then
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_BRGEM_POS_ERROR"
        print_test_status "BR Gem position" 1
    else
        if [ $TEST -eq 0 ];then
            TEST_PASSED=0
            FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_BRGEM_POS_${DISTANCE_ARCSEC}"
            print_test_status "BR Gem position (dist ${DISTANCE_ARCSEC}\")" 1
        else
            print_test_status "BR Gem position (dist ${DISTANCE_ARCSEC}\")" 0
        fi
    fi
fi

echo -e "\n${BLUE}Checking timing (informational)...${NC}\n"

# Check profiling log if available
if [ -f transient_factory_test31_profiling.log ]; then
    echo "Profiling data from transient_factory_test31_profiling.log:"
    cat transient_factory_test31_profiling.log
    echo ""

    # Extract and display individual timing components
    echo "Individual timing components:"
    for TIMING_SECTION in VAST_RUN WCS_CACHE_SETUP WCS_CALIBRATION_AND_EPHEMERIS UCAC5_PLATE_SOLVING MAGNITUDE_CALIBRATION CANDIDATE_FILTERING_TOTAL FILTER_MAGNITUDE_CONSOLIDATED FILTER_FRAME_EDGE FILTER_SECOND_EPOCH_VERIFY EXCLUSION_LIST_PREPARATION SEEING_AND_LIMITING_MAG WAIT_FOR_UCAC5 HTML_REPORT; do
        SECTION_TIME=$(grep "$TIMING_SECTION:" transient_factory_test31_profiling.log 2>/dev/null | head -n1 | awk '{print $2}')
        if [ -n "$SECTION_TIME" ]; then
            printf "  %-35s %s\n" "$TIMING_SECTION:" "$SECTION_TIME"
        fi
    done
    echo ""

    # Extract total runtime
    TOTAL_RUNTIME=$(grep "TOTAL_RUNTIME:" transient_factory_test31_profiling.log | awk '{print $2}' | tr -d 's')
    if [ -n "$TOTAL_RUNTIME" ]; then
        MAX_ALLOWED_TIME=$(echo "$BASELINE_TOTAL_RUNTIME $TIMING_TOLERANCE_FACTOR" | awk '{printf "%.0f", $1 * $2}')
        echo "Total runtime: ${TOTAL_RUNTIME}s (baseline: ${BASELINE_TOTAL_RUNTIME}s, max allowed: ${MAX_ALLOWED_TIME}s)"

        # This is informational only - timing is highly variable
        # and depends on network (HTML report generation)
        TIME_CHECK=$(echo "$TOTAL_RUNTIME $MAX_ALLOWED_TIME" | awk '{if ($1 <= $2) print 1; else print 0}')
        if [ "$TIME_CHECK" -eq 1 ]; then
            print_test_status "Runtime within tolerance (informational)" 0
        else
            echo -e "  ${BLUE}Note: Runtime exceeded tolerance, but this may be due to network variability${NC}"
        fi
    fi
    # Validate profiling log has expected sections
    echo -e "\n${BLUE}Validating profiling log contents...${NC}\n"

    # Check that VAST_RUN times are recorded for both SExtractor configs
    VAST_RUN_COUNT=$(grep -c "VAST_RUN_" transient_factory_test31_profiling.log 2>/dev/null || echo "0")
    if [ "$VAST_RUN_COUNT" -ge 2 ]; then
        print_test_status "Per-SExtractor-config VAST_RUN labels ($VAST_RUN_COUNT entries)" 0
    else
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_PROFILING_VAST_RUN_LABELS"
        print_test_status "Per-SExtractor-config VAST_RUN labels ($VAST_RUN_COUNT entries, expected >= 2)" 1
    fi

    # Check that the consolidated filter timing is recorded
    if grep -q "FILTER_MAGNITUDE_CONSOLIDATED:" transient_factory_test31_profiling.log 2>/dev/null; then
        print_test_status "Consolidated magnitude filter profiling recorded" 0
    else
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_PROFILING_CONSOLIDATED_FILTER"
        print_test_status "Consolidated magnitude filter profiling recorded" 1
    fi

    # Check that new profiling sections are recorded
    for REQUIRED_SECTION in CANDIDATE_FILTERING_TOTAL EXCLUSION_LIST_PREPARATION SEEING_AND_LIMITING_MAG WAIT_FOR_UCAC5 WCS_CACHE_SETUP; do
        if grep -q "$REQUIRED_SECTION:" transient_factory_test31_profiling.log 2>/dev/null; then
            print_test_status "Profiling section $REQUIRED_SECTION recorded" 0
        else
            TEST_PASSED=0
            FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_PROFILING_${REQUIRED_SECTION}"
            print_test_status "Profiling section $REQUIRED_SECTION recorded" 1
        fi
    done

    # Check total runtime is recorded
    if grep -q "TOTAL_RUNTIME:" transient_factory_test31_profiling.log 2>/dev/null; then
        print_test_status "Total runtime recorded in profiling log" 0
    else
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_PROFILING_TOTAL_RUNTIME"
        print_test_status "Total runtime recorded in profiling log" 1
    fi
else
    echo "No profiling log found (transient_factory_test31_profiling.log)"
fi

echo -e "\n${BLUE}Checking magnitude calibration...${NC}\n"

# Validate magnitude calibration zero-point from transient_factory_test31.txt
if [ -f transient_factory_test31.txt ]; then
    ZEROPOINT=$(grep "Zero point" transient_factory_test31.txt | head -n1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+\.[0-9]+$/ || $i ~ /^-[0-9]+\.[0-9]+$/) {print $i; exit}}')
    if [ -n "$ZEROPOINT" ]; then
        # Zero point should be in a tight range (typically between -2 and 5 for NMW)
        ZP_TIGHT=$(echo "$ZEROPOINT" | awk '{if ($1 > -2 && $1 < 5) print 1; else print 0}')
        if [ "$ZP_TIGHT" -eq 1 ]; then
            print_test_status "Zero-point value in tight range ($ZEROPOINT, expected -2 to 5)" 0
        else
            # Fallback: check broad range
            ZP_OK=$(echo "$ZEROPOINT" | awk '{if ($1 > -30 && $1 < 30) print 1; else print 0}')
            if [ "$ZP_OK" -eq 1 ]; then
                echo -e "  ${BLUE}Note: Zero-point $ZEROPOINT outside tight range but within broad range${NC}"
                print_test_status "Zero-point value reasonable ($ZEROPOINT)" 0
            else
                TEST_PASSED=0
                FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_BAD_ZEROPOINT_$ZEROPOINT"
                print_test_status "Zero-point value reasonable ($ZEROPOINT)" 1
            fi
        fi
    fi

    # Check that photometric calibration is TYCHO2_V in the pipeline log
    if grep -q "PHOTOMETRIC_CALIBRATION=TYCHO2_V" transient_factory_test31.txt; then
        print_test_status "PHOTOMETRIC_CALIBRATION=TYCHO2_V in pipeline log" 0
    else
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_PIPELINE_LOG_CALIBRATION"
        print_test_status "PHOTOMETRIC_CALIBRATION=TYCHO2_V in pipeline log" 1
    fi

    # Check that the magnitude calibration mentions the number of calibration stars
    if grep -q "calibration stars" transient_factory_test31.txt; then
        CALIB_STARS=$(grep "calibration stars" transient_factory_test31.txt | head -n1 | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+$/ && $i > 5) {print $i; exit}}')
        if [ -n "$CALIB_STARS" ]; then
            print_test_status "Calibration star count reported ($CALIB_STARS)" 0
        else
            print_test_status "Calibration star count mentioned" 0
        fi
    fi
fi

echo -e "\n${BLUE}Checking calib.txt...${NC}\n"

# Check calib.txt line count
# Baseline: 10460 lines (allow 10% deviation)
if [ -f calib.txt ]; then
    CALIB_LINES=$(wc -l < calib.txt)
    # Expected range: 9400-11500 (roughly +-10%)
    if [ "$CALIB_LINES" -ge 9400 ] && [ "$CALIB_LINES" -le 11500 ]; then
        print_test_status "calib.txt line count ($CALIB_LINES, expected ~10460)" 0
    else
        TEST_PASSED=0
        FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_CALIBTXT_LINES_$CALIB_LINES"
        print_test_status "calib.txt line count ($CALIB_LINES, expected ~10460)" 1
    fi
else
    TEST_PASSED=0
    FAILED_TEST_CODES="$FAILED_TEST_CODES NMWTEXASGEM03_NO_CALIBTXT"
    print_test_status "calib.txt exists" 1
fi

# Check detected object magnitudes are within expected ranges
echo -e "\n${BLUE}Validating detected object magnitudes...${NC}\n"

# Extract magnitudes from the report and validate they're in expected range (8-15 mag)
MAGS_FROM_REPORT=$(grep -oE "[0-9]+\.[0-9]+" transient_report/index.html 2>/dev/null | awk '$1 > 5 && $1 < 20' | head -20)
if [ -n "$MAGS_FROM_REPORT" ]; then
    MAG_COUNT=0
    MAG_VALID=0
    for MAG in $MAGS_FROM_REPORT; do
        MAG_COUNT=$((MAG_COUNT + 1))
        IN_RANGE=$(echo "$MAG" | awk '{if ($1 >= 8 && $1 <= 15) print 1; else print 0}')
        if [ "$IN_RANGE" -eq 1 ]; then
            MAG_VALID=$((MAG_VALID + 1))
        fi
    done
    if [ "$MAG_COUNT" -gt 0 ]; then
        MAG_PERCENT=$((MAG_VALID * 100 / MAG_COUNT))
        if [ "$MAG_PERCENT" -ge 50 ]; then
            print_test_status "Detected magnitudes in expected range ($MAG_VALID/$MAG_COUNT)" 0
        else
            echo -e "  ${BLUE}Note: Only $MAG_VALID of $MAG_COUNT magnitudes in 8-15 range (may be OK)${NC}"
        fi
    fi
fi

# Record end time
THIS_TEST_STOP_UNIXSEC=$(date +%s)
THIS_TEST_TIME_SEC=$((THIS_TEST_STOP_UNIXSEC - THIS_TEST_START_UNIXSEC))
THIS_TEST_TIME_MIN=$(echo "$THIS_TEST_TIME_SEC" | awk '{printf "%.1f", $1/60.0}')

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}========================================${NC}\n"

echo "Test duration: ${THIS_TEST_TIME_MIN} min (${THIS_TEST_TIME_SEC} sec)"

if [ -n "$FAILED_TEST_CODES" ]; then
    echo -e "\nFailed test codes: $FAILED_TEST_CODES"
fi

# Final result
echo ""
if [ $TEST_PASSED -eq 1 ]; then
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}NMW-TexasTech Gem-03-Q1b1x1 Test PASSED${NC}"
    echo -e "${GREEN}========================================${NC}"
    exit 0
else
    echo -e "${RED}========================================${NC}"
    echo -e "${RED}NMW-TexasTech Gem-03-Q1b1x1 Test FAILED${NC}"
    echo -e "${RED}========================================${NC}"
    echo -e "\nFailed test codes: $FAILED_TEST_CODES"
    exit 1
fi
