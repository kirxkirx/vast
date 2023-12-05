#!/usr/bin/env bash

# When adapting this script for a new dataset, watch for the signs
### ===> MAGNITUDE LIMITS HARDCODED HERE <===
### ===> APERTURE LIMITS HARDCODED HERE <===
### ===> POINTING ACCURACY LIMITS HARDCODED HERE <===

# Also watch for
### ===> SExtractor config file <===
### ===> IMAGE EDGE OFFSET HARDCODED HERE <===
### ===> ASSUMED MAX NUMBER OF CANDIDATES <===
### ===> FIELD NAME HARDCODED HERE <===

#
# This script is used to run transient search in the NMW survey http://scan.sai.msu.ru/nmw/
# It is intended as an example of how an automated transient-detection pipeline may be set up using VaST.
# Note, that in this example there are two reference and two second-epoch images.
# The results will be presented as an HTML page transient_report/index.html
#
#################################

# We need to check the input early as we may need to set camera settings based on the input path
if [ -z "$1" ]; then
 echo "Usage: $0 PATH_TO_DIRECTORY_WITH_IMAGE_PAIRS"
 echo "Usage: $0 PATH_TO_DIRECTORY_WITH_IMAGE_PAIRS" >> transient_factory_test31.txt
 exit 1
fi
INPUT_PATH_FOR_DETERMINING_CAMERA_SETTING="$1"
if [[ "$INPUT_PATH_FOR_DETERMINING_CAMERA_SETTING" == *"Stas"* ]] ; then
 echo "The input indicates the images are from Stas ST-8300M camera"
 export CAMERA_SETTINGS="Stas"
fi
if [[ "$INPUT_PATH_FOR_DETERMINING_CAMERA_SETTING" == *"STL-11000M"* ]] || [[ "$INPUT_PATH_FOR_DETERMINING_CAMERA_SETTING" == *"NMW-STL"* ]] ; then
 echo "The input indicates the images are from STL-11000M camera"
 export CAMERA_SETTINGS="STL-11000M"
fi
if [[ "$INPUT_PATH_FOR_DETERMINING_CAMERA_SETTING" == *"TICA_TESS"* ]] ; then
 echo "The input indicates the images are TICA TESS FFIs"
 export CAMERA_SETTINGS="TICA_TESS_FFI"
fi


########### Default settings describing the old NMW camera:
# Canon 135 mm f/2.0 telephoto lens + SBIG ST-8300M CCD, 20 sec exposures

# Normally should be YES,
# if set to NO '===> POINTING ACCURACY LIMITS HARDCODED HERE <===' will be ignored.
CHECK_POINTING_ACCURACY="YES"

FILTER_MIN_APERTURE_STAR_SIZE_PIX=2.0
FILTER_MAX_APERTURE_STAR_SIZE_PIX=9.5
FILTER_MAX_ELONGATION_AminusB_PIX=0.55

FILTER_BRIGHT_MAG_CUTOFF="-5"
export FILTER_FAINT_MAG_CUTOFF_TRANSIENT_SEARCH="14.0"
#export FILTER_FAINT_MAG_CUTOFF_TRANSIENT_SEARCH="13.5"

MAX_NUMBER_OF_CANDIDATES_PER_FIELD=40

# Default values
NUMBER_OF_DETECTED_TRANSIENTS_BEFORE_FILTERING_SOFT_LIMIT=800
NUMBER_OF_DETECTED_TRANSIENTS_BEFORE_FILTERING_HARD_LIMIT=1000

# allow SEXTRACTOR_CONFIG_FILES to be set externally
if [ -z "$SEXTRACTOR_CONFIG_FILES" ];then
 # One or more Source Extractor configuration files to run the analysis with
 # Typically, the first run is optimized to detect bright targets while the second one is optimized for faint targets
 SEXTRACTOR_CONFIG_FILES="default.sex.telephoto_lens_onlybrightstars_v1 default.sex.telephoto_lens_v4"
 #SEXTRACTOR_CONFIG_FILES="default.sex.telephoto_lens_onlybrightstars_v1 default.sex.telephoto_lens_v4 default.sex.telephoto_lens_v5"
fi
# The first SExtractor config file in the list should be optimized for detecting bright stars
SEXTRACTOR_CONFIG_BRIGHTSTARPASS=$(echo $SEXTRACTOR_CONFIG_FILES | awk '{print $1}')

# Note that this is an additional (normally more strict) filter to the FRAME_EDGE_INDENT_PIXELS parameter defined in src/vast_limits.h
FRAME_EDGE_OFFSET_PIX=30

# Comment-out TELESCOP_NAME_KNOWN_TO_VaST_FOR_FOV_DETERMINATION if unsure
TELESCOP_NAME_KNOWN_TO_VaST_FOR_FOV_DETERMINATION="NMW_camera"

EXCLUSION_LIST="../exclusion_list.txt"
SYSREM_ITERATIONS=1
UCAC5_PLATESOLVE_ITERATIONS=1

# CAMERA_SETTINGS environment vairable may be set to override the default settings with the ones needed for a different camera
if [ -n "$CAMERA_SETTINGS" ];then
 if [ "$CAMERA_SETTINGS" = "Stas" ];then
  # Canon 135 mm f/2.0 telephoto lens + SBIG ST-8300M CCD, 20 sec exposures
  TELESCOP_NAME_KNOWN_TO_VaST_FOR_FOV_DETERMINATION="NMW_camera"
  BAD_REGION_FILE="../Stas_bad_region.lst"
  EXCLUSION_LIST="../exclusion_list.txt"
  # Calibration data
  if [ -z "$DARK_FRAMES_DIR" ];then
   export DARK_FRAMES_DIR=/dataX/cgi-bin/unmw/uploads/darks
  fi
  if [ -z "$FLAT_FIELD_FILE" ];then
   export FLAT_FIELD_FILE=/dataX/cgi-bin/unmw/uploads/flats/mff_0013_tail1_notbad.fit
  fi
 fi
 if [ "$CAMERA_SETTINGS" = "STL-11000M" ];then
  # Canon 135 mm f/2.0 telephoto lens + SBIG STL-11000 CCD, 20 sec exposures
  echo "### Using search settings for $CAMERA_SETTINGS camera ###"
  # The input images will be calibrated
  # DARK_FRAMES_DIR has to be pointed at directory containing dark frames,
  # the script will try to find the most appropriate one based on temperature and time
  if [ -z "$DARK_FRAMES_DIR" ];then
   export DARK_FRAMES_DIR=/home/apache/darks
  fi
  # we don't usually have a luxury of multiple flat field frames to chhose from
  # FLAT_FIELD_FILE has to point to one specific file that will be used for flat-fielding
  if [ -z "$DARK_FRAMES_DIR" ];then
   export FLAT_FIELD_FILE=/home/apache/flats/mff_2023-07-14.fit
  fi
  #
  TELESCOP_NAME_KNOWN_TO_VaST_FOR_FOV_DETERMINATION="STL-11000M"
  export TELESCOP_NAME_KNOWN_TO_VaST_FOR_FOV_DETERMINATION
  NUMBER_OF_DETECTED_TRANSIENTS_BEFORE_FILTERING_SOFT_LIMIT=1000
  NUMBER_OF_DETECTED_TRANSIENTS_BEFORE_FILTERING_HARD_LIMIT=1500
  export FILTER_FAINT_MAG_CUTOFF_TRANSIENT_SEARCH="13.5"
  FILTER_MAX_APERTURE_STAR_SIZE_PIX=12.5
  if [ -z "$SEXTRACTOR_CONFIG_FILES" ];then
   # You will likely need custom SEXTRACTOR_CONFIG_FILES because GAIN is different
   SEXTRACTOR_CONFIG_FILES="default.sex.telephoto_lens_onlybrightstars_v1 default.sex.telephoto_lens_vSTL"
  fi
  # REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES rejects candidates with exactly the same pixel coordinates on two new images
  # as these are likely to be hot pixels sneaking into the list of candidates if no shift has been applied between the two second-epoch images.
  export REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES="yes"
  BAD_REGION_FILE="../STL_bad_region.lst"
  EXCLUSION_LIST="../exclusion_list_STL.txt"
  export OMP_NUM_THREADS=4
  SYSREM_ITERATIONS=0
  UCAC5_PLATESOLVE_ITERATIONS=2
  # The funny ghost image seems to be no more than 80pix away from frame edge
  FRAME_EDGE_OFFSET_PIX=100
 fi
 #
 if [ "$CAMERA_SETTINGS" = "TICA_TESS_FFI" ];then
  # TICA TESS FFIs downloaded from https://archive.stsci.edu/hlsp/tica#section-c34b9669-b0be-40b2-853e-a59997d1b7c5
  echo "### Using search settings for $CAMERA_SETTINGS camera ###"
  NUMBER_OF_DETECTED_TRANSIENTS_BEFORE_FILTERING_SOFT_LIMIT=1000
  NUMBER_OF_DETECTED_TRANSIENTS_BEFORE_FILTERING_HARD_LIMIT=1500
  export FILTER_FAINT_MAG_CUTOFF_TRANSIENT_SEARCH="15.0"
  SEXTRACTOR_CONFIG_FILES="default.sex.TICA_TESS"
  # REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES rejects candidates with exactly the same pixel coordinates on two new images
  # as these are likely to be hot pixels sneaking into the list of candidates if no shift has been applied between the two second-epoch images.
  export REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES="no"
  BAD_REGION_FILE="../TICA_TESS_bad_region.lst"
  EXCLUSION_LIST="../exclusion_list_TICATESS.txt"
  SYSREM_ITERATIONS=0
  UCAC5_PLATESOLVE_ITERATIONS=1
  PHOTOMETRIC_CALIBRATION="APASS_I"
  export GAIA_BAND_FOR_CATALOGED_SOURCE_CHECK="RPmag"
 fi
fi

# You probably don't need to change anything below this line
#################################

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################



#################################
# Homogenize optional variables
if [ -n "$CHECK_POINTING_ACCURACY" ];then
 if [ "$CHECK_POINTING_ACCURACY" = "y" ] || [ "$CHECK_POINTING_ACCURACY" = "Y" ] || [ "$CHECK_POINTING_ACCURACY" = "yes" ] || [ "$CHECK_POINTING_ACCURACY" = "Yes" ] || [ "$CHECK_POINTING_ACCURACY" = "YES" ] || [ "$CHECK_POINTING_ACCURACY" = "true" ] || [ "$CHECK_POINTING_ACCURACY" = "True" ] || [ "$CHECK_POINTING_ACCURACY" = "TRUE" ];then
  CHECK_POINTING_ACCURACY="yes"
  export CHECK_POINTING_ACCURACY
 fi
fi

if [ -n "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" ];then
 if [ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" = "y" ] || [ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" = "Y" ] || [ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" = "yes" ] || [ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" = "Yes" ] || [ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" = "YES" ] || [ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" = "true" ] || [ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" = "True" ] || [ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" = "TRUE" ];then
  REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES="yes"
  export REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES
 fi
fi

#################################

if [ -n "$TELESCOP_NAME_KNOWN_TO_VaST_FOR_FOV_DETERMINATION" ];then
 export TELESCOP="$TELESCOP_NAME_KNOWN_TO_VaST_FOR_FOV_DETERMINATION"
fi

# Are we on Linux or something else?
SYSTEM_TYPE="$(uname)"

function try_to_calibrate_the_input_frame {

 # check if we have calibration data at all
 if [ -z "$DARK_FRAMES_DIR" ];then
  echo "try_to_calibrate_the_input_frame(): DARK_FRAMES_DIR is not set - not attempting to dark-subtract the input frames" 1>&2
  return 1
 fi
 if [ ! -d "$DARK_FRAMES_DIR" ];then
  echo "try_to_calibrate_the_input_frame(): DARK_FRAMES_DIR=$DARK_FRAMES_DIR is not not a directory" 1>&2
  return 1
 fi

 # check the input image
 INPUT_FRAME_PATH="$1"
 if [ -z "$INPUT_FRAME_PATH" ];then
  echo "try_to_calibrate_the_input_frame(): INPUT_FRAME_PATH is not set" 1>&2
  return 1
 fi
 if [ ! -s "$INPUT_FRAME_PATH" ];then
  echo "try_to_calibrate_the_input_frame(): INPUT_FRAME_PATH=$INPUT_FRAME_PATH is empty or does not exist" 1>&2
  return 1
 fi
 # util/ccd/ms will write HISTORY Dark frame subtraction in the dark-frame-subtracted file
 # We test this in order not to do the dark frame subtraction twice
 util/listhead "$INPUT_FRAME_PATH" | grep --quiet 'Dark frame subtraction'
 if [ $? -eq 0 ];then
  echo "try_to_calibrate_the_input_frame(): the dark frame has already been subtracted from the input image" 1>&2
  return 1
 fi
 
 # figure out the input and output file names
 INPUT_FRAME_BASENAME=$(basename "$INPUT_FRAME_PATH")
 INPUT_FRAME_DIRNAME=$(dirname "$INPUT_FRAME_PATH")
 OUTPUT_DARK_SUBTRACTED_FRAME_BASENAME=d_"$INPUT_FRAME_BASENAME"
 OUTPUT_DARK_SUBTRACTED_FRAME_PATH="$INPUT_FRAME_DIRNAME/$OUTPUT_DARK_SUBTRACTED_FRAME_BASENAME"
 OUTPUT_FLATFIELDED_FRAME_BASENAME=fd_"$INPUT_FRAME_BASENAME"
 OUTPUT_FLATFIELDED_FRAME_PATH="$INPUT_FRAME_DIRNAME/$OUTPUT_FLATFIELDED_FRAME_BASENAME"
 
 # check if the input image directory is writable
 if [ ! -w "$INPUT_FRAME_DIRNAME" ];then
  echo "try_to_calibrate_the_input_frame(): the input directory $INPUT_FRAME_DIRNAME is not writable - cannot perform image calibration" 1>&2
  return 1
 fi
 
 # Print the temperature keywords SET-TEMP and CCD-TEMP
 util/listhead "$INPUT_FRAME_PATH" | grep 'TEMP' 1>&2
 
 # find the best dark
 DARK_FRAME=$(util/find_best_dark.sh "$INPUT_FRAME_PATH")
 if [ $? -ne 0 ];then
  echo "try_to_calibrate_the_input_frame(): cannot find a good dark frame" 1>&2
  return 1
 fi
 if [ ! -f "$DARK_FRAME" ];then
  echo "try_to_calibrate_the_input_frame(): dark frame file does not exist: DARK_FRAME=$DARK_FRAME" 1>&2
  return 1
 fi
 if [ ! -s "$DARK_FRAME" ];then
  echo "try_to_calibrate_the_input_frame(): dark frame file is empty: DARK_FRAME=$DARK_FRAME" 1>&2
  return 1
 fi
 
 # clean-up if this is not the first run
 if [ -f "$OUTPUT_DARK_SUBTRACTED_FRAME_PATH" ];then
  rm -f "$OUTPUT_DARK_SUBTRACTED_FRAME_PATH" 1>&2
 fi
 
 # subtract dark frame from the input frame
 util/ccd/ms "$INPUT_FRAME_PATH" "$DARK_FRAME" "$OUTPUT_DARK_SUBTRACTED_FRAME_PATH" 1>&2
 if [ $? -ne 0 ];then
  echo "try_to_calibrate_the_input_frame(): a problem occurred while running util/ccd/ms $INPUT_FRAME_PATH $DARK_FRAME $OUTPUT_DARK_SUBTRACTED_FRAME_PATH" 1>&2
  return 1
 fi
 
 OUTPUT_CALIBRATED_FRAME_PATH="$OUTPUT_DARK_SUBTRACTED_FRAME_PATH"
 
 # now attempt flat fielding
 if [ -n "$FLAT_FIELD_FILE" ];then
  if [ -s "$FLAT_FIELD_FILE" ];then
   # clean-up if this is not the first run
   if [ -f "$OUTPUT_FLATFIELDED_FRAME_PATH" ];then
    rm -f "$OUTPUT_FLATFIELDED_FRAME_PATH" 1>&2
   fi
   # divide the dark-subtracted frame by the flat field
   util/ccd/md "$OUTPUT_DARK_SUBTRACTED_FRAME_PATH" "$FLAT_FIELD_FILE" "$OUTPUT_FLATFIELDED_FRAME_PATH" 1>&2
   if [ $? -ne 0 ];then
    echo "try_to_calibrate_the_input_frame(): a problem occurred while running util/ccd/md $OUTPUT_DARK_SUBTRACTED_FRAME_PATH $FLAT_FIELD_FILE $OUTPUT_FLATFIELDED_FRAME_PATH" 1>&2
    # do not return: if things are bad we'll got with dark-only corrected frame
    #return 1
   else
    # remove the non-flat-fielded dark-subtracted image to save space
    rm -f "$OUTPUT_DARK_SUBTRACTED_FRAME_PATH"
    # use flat-fielded image
    OUTPUT_CALIBRATED_FRAME_PATH="$OUTPUT_FLATFIELDED_FRAME_PATH"
   fi
  else
   echo "try_to_calibrate_the_input_frame(): FLAT_FIELD_FILE=$FLAT_FIELD_FILE does not exist or is empty" 1>&2
  fi
 else 
  echo "try_to_calibrate_the_input_frame(): FLAT_FIELD_FILE is not set" 1>&2
 fi
 
 echo "$OUTPUT_CALIBRATED_FRAME_PATH"
 
 return 0
}

function print_image_date_for_logs_in_case_of_emergency_stop {
 # $hell4eck says $@ needs to be double-quotted
 for INTPUT_IMAGE in "$@" ;do
  if [ -f "$INTPUT_IMAGE" ];then
   util/get_image_date "$INTPUT_IMAGE" 2>&1 | grep 'Exposure' | awk '{printf "Last  image: %s %s %s %s\n", $9, $4, $5, $6}'
   break
  fi
 done
 return 0
}

function check_if_vast_install_looks_reasonably_healthy {
 for FILE_TO_CHECK in ./vast GNUmakefile makefile lib/autodetect_aperture_main lib/bin/xy2sky lib/catalogs/check_catalogs_offline lib/choose_vizier_mirror.sh lib/deeming_compute_periodogram lib/deg2hms_uas lib/drop_bright_points lib/drop_faint_points lib/fit_robust_linear lib/guess_saturation_limit_main lib/hms2deg lib/lk_compute_periodogram lib/new_lightcurve_sigma_filter lib/put_two_sources_in_one_field lib/remove_bad_images lib/remove_lightcurves_with_small_number_of_points lib/select_only_n_random_points_from_set_of_lightcurves lib/sextract_single_image_noninteractive lib/try_to_guess_image_fov lib/update_offline_catalogs.sh lib/update_tai-utc.sh lib/vizquery util/calibrate_magnitude_scale util/calibrate_single_image.sh util/ccd/md util/ccd/mk util/ccd/ms util/clean_data.sh util/examples/test_coordinate_converter.sh util/examples/test__dark_flat_flag.sh util/examples/test_heliocentric_correction.sh util/fov_of_wcs_calibrated_image.sh util/get_image_date util/hjd_input_in_UTC util/load.sh util/magnitude_calibration.sh util/make_finding_chart util/nopgplot.sh util/rescale_photometric_errors util/save.sh util/search_databases_with_curl.sh util/search_databases_with_vizquery.sh util/solve_plate_with_UCAC5 util/stat_outfile util/sysrem2 util/transients/transient_factory_test31.sh util/wcs_image_calibration.sh ;do
  if [ ! -s "$FILE_TO_CHECK" ];then
   echo "
ERROR: cannot find a proper VaST installation in the current directory
$PWD

check_if_vast_install_looks_reasonably_healthy() failed while checking the file $FILE_TO_CHECK
CANCEL TEST"
   return 1
  fi
 done
 return 0
}


# Find the real path to VaST home directory
function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=$(readlink -f "$1" 2>/dev/null)
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=$(greadlink -f "$1" 2>/dev/null)
   if [ $? -ne 0 ];then
    REALPATH=$(realpath "$1" 2>/dev/null)
    if [ $? -ne 0 ];then
     REALPATH=$(grealpath "$1" 2>/dev/null)
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")" || exit 1
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit 1
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

if [ -z "$VAST_PATH" ];then
 VAST_PATH=$(vastrealpath $0)
 VAST_PATH=$(dirname "$VAST_PATH")
 VAST_PATH="${VAST_PATH/transients/}"
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 #VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")
 VAST_PATH=${VAST_PATH//\'\//\/}
 # Make sure no quotation marks are left in VAST_PATH
 #VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")
 VAST_PATH=${VAST_PATH//\'/}
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
#

# Go to VaST working directory
cd "$VAST_PATH" || exit 1
# Make sure the current directly has compiled VaST installation
check_if_vast_install_looks_reasonably_healthy
if [ $? -ne 0 ];then
 exit 1
fi

# Set the directory with reference images
# You may set a few alternative locations, but only the first one that exist will be used
# The best way is to set the environment variable REFERENCE_IMAGES pointing to the reference image directory
#
if [ -z "$REFERENCE_IMAGES" ];then
 REFERENCE_IMAGES=/mnt/usb/NMW_NG/NMW_reference_images_2012
 # scan
 if [ ! -d "$REFERENCE_IMAGES" ];then
  REFERENCE_IMAGES=/home/NMW_reference_images_2012
 fi
 # vast
 if [ ! -d "$REFERENCE_IMAGES" ];then
  REFERENCE_IMAGES=/dataX/kirx/NMW_reference_images_2012 
 fi
 if [ ! -d "$REFERENCE_IMAGES" ];then
  REFERENCE_IMAGES=/dataY/kirx/NMW_reference_images_2012 
 fi
 if [ ! -d "$REFERENCE_IMAGES" ];then
  REFERENCE_IMAGES=/home/kirx/current_work/NMW_crashtest/ref 
 fi
fi

# Clean whatever may remain from a possible incomplete previous run
if [ -f transient_factory_test31.txt ];then
 rm -f transient_factory_test31.txt
fi
# clean up the local cache (just in case - the proper cache cleaning is done for every new field below)
for FILE_TO_REMOVE in local_wcs_cache/* exclusion_list.txt exclusion_list_bsc.txt exclusion_list_bbsc.txt exclusion_list_tycho2.txt exclusion_list_gaiadr2.txt exclusion_list_apass.txt ;do
 if [ -f "$FILE_TO_REMOVE" ];then
  rm -f "$FILE_TO_REMOVE"
 fi
done

# Check the reference images
if [ ! -d "$REFERENCE_IMAGES" ];then
 echo "ERROR: cannot find the reference image directory REFERENCE_IMAGES=$REFERENCE_IMAGES"
 echo "ERROR: cannot find the reference image directory REFERENCE_IMAGES=$REFERENCE_IMAGES" >> transient_factory_test31.txt
 exit 1
else
 # make sure the reference image directory is not empty
 for FILE_TO_TEST in "$REFERENCE_IMAGES"/* ;do
  # If the content of the direcotry is no a regular file and is not a symlink
  if [ ! -f "$FILE_TO_TEST" ] && [ ! -L "$FILE_TO_TEST" ];then
   echo "ERROR: empty reference image directory REFERENCE_IMAGES=$REFERENCE_IMAGES"
   echo "ERROR: empty reference image directory REFERENCE_IMAGES=$REFERENCE_IMAGES" >> transient_factory_test31.txt
   exit 1
  else
   break
  fi
 done
fi

# Check for a local copy of UCAC5
# (this is specific to our in-house setup)
if [ ! -d lib/catalogs/ucac5 ];then
 for TEST_THIS_DIR in /mnt/usb/UCAC5 /dataX/kirx/UCAC5 /home/kirx/UCAC5 /home/apache/ucac5 $HOME/UCAC5 $HOME/ucac5 ../UCAC5 ../ucac5 ;do
  if [ -d $TEST_THIS_DIR ];then
   ln -s $TEST_THIS_DIR lib/catalogs/ucac5
   echo "Linking the local copy of UCAC5 from $TEST_THIS_DIR"
   echo "Linking the local copy of UCAC5 from $TEST_THIS_DIR" >> transient_factory_test31.txt
   break
  fi
 done
fi
#### Even more specific case: /mnt/usb/UCAC5 is present but the link is set to /dataX/kirx/UCAC5 ####
if [ -d /mnt/usb/UCAC5 ];then
 # This will not work on Mac OS X, but I don't care as this trap is specific to my Linux box
 LINK_POINTS_TO=$(readlink -f lib/catalogs/ucac5)
 if [ "$LINK_POINTS_TO" = "/dataX/kirx/UCAC5" ];then
  rm -f lib/catalogs/ucac5
  ln -s /mnt/usb/UCAC5 lib/catalogs/ucac5
 fi
fi
#####################################################################################################
if [ ! -d lib/catalogs/ucac5 ];then
 echo "WARNING: no local copy of UCAC5 was found (will be using a remote one)"
fi
#####################################################################################################
# This script should take care of updating astorb.dat and other catalogs
lib/update_offline_catalogs.sh all

echo "Reference image directory is set to $REFERENCE_IMAGES"
echo "Reference image directory is set to $REFERENCE_IMAGES" >> transient_factory_test31.txt
if [ -z "$1" ]; then
 echo "Usage: $0 PATH_TO_DIRECTORY_WITH_IMAGE_PAIRS"
 echo "Usage: $0 PATH_TO_DIRECTORY_WITH_IMAGE_PAIRS" >> transient_factory_test31.txt
 exit 1
fi

# We may need it for the new transients check in util/transients/report_transient.sh
VIZIER_SITE=$(lib/choose_vizier_mirror.sh)
export VIZIER_SITE
### 
TIMEOUTCOMMAND=$("$VAST_PATH"lib/find_timeout_command.sh)
if [ $? -ne 0 ];then
 echo "WARNING: cannot find timeout command"
else
 TIMEOUTCOMMAND="$TIMEOUTCOMMAND 100 "
fi
export TIMEOUTCOMMAND

# Remove filenames that will confuse vast command line parser
for SUSPICIOUS_FILE in 1 2 3 4 5 6 7 8 9 10 11 12 ;do
 if [ -f "$SUSPICIOUS_FILE" ];then
  rm -f "$SUSPICIOUS_FILE"
 fi
done

# Check if we are expected to produce PNG images or just text
MAKE_PNG_PLOTS="yes"
if [ -x lib/test_libpng_justtest_nomovepgplot.sh ];then
 lib/test_libpng_justtest_nomovepgplot.sh
 if [ $? -ne 0 ];then
  MAKE_PNG_PLOTS="no"
 fi
fi
export MAKE_PNG_PLOTS

# do this only if transient_report is not a symlink
if [ ! -L transient_report ];then
 if [ ! -d transient_report ];then
  mkdir transient_report
 fi
fi

# remove any remanants of a previous run
rm -f transient_report/* transient_factory.log
# clean up the local cache
# We should not remove exclusion_list_gaiadr2.txt and exclusion_list_apass.txt as we want to use them later
for FILE_TO_REMOVE in local_wcs_cache/* exclusion_list.txt exclusion_list_bsc.txt exclusion_list_bbsc.txt exclusion_list_tycho2.txt ;do
 if [ -f "$FILE_TO_REMOVE" ];then
  rm -f "$FILE_TO_REMOVE"
  echo "Removing $FILE_TO_REMOVE" >> transient_factory_test31.txt
 fi
done

# Convert the array of arguments to string so shellcheck does not complain
# Use * instead of @ to concatenate the array elements into a single string, like this:
string_command_line_argumants="$*"

# Write the HTML report header
echo "<HTML>

<HEAD>
<style>
 body {
       font-family:monospace;
       font-size:12px;'
      }
</style>

<script type='text/javascript'>
function toggleElement(id)
{
    if(document.getElementById(id).style.display == 'none')
    {
        document.getElementById(id).style.display = '';
    }
    else
    {   
        document.getElementById(id).style.display = 'none';
    }
}

function printCandidateNameWithAbsLink( transientname) {

 var currentLocation = window.location.href;
 
 var n = currentLocation.indexOf('#');
 currentLocation = currentLocation.substring(0, n != -1 ? n : currentLocation.length);
 var transientLink = \"#\";
 transientLink = transientLink.concat(transientname);
 var targetURL = currentLocation.concat(transientLink);
 
 var outputString = \"<h3><a href='\";
 outputString = outputString.concat(targetURL);
 outputString = outputString.concat(\"'>\");
 outputString = outputString.concat(transientname);
 outputString = outputString.concat(\"</a></h3>\");

 document.write(outputString); 

}

</script>

</HEAD>

<BODY>
<h2>NMW transient search results</h2>
This analysis is done by the script  <code>$0 $string_command_line_argumants</code><br><br>
The list of candidates will appear below. Please <b>manually reload the page</b> every few minutes untill the 'Processing complete' message appears.
<br><br>" >> transient_report/index.html

# Allow for multiple image directories to be specified on the command line
for NEW_IMAGES in "$@" ;do

if [ ! -d "$NEW_IMAGES" ];then
 echo "ERROR: $NEW_IMAGES is not a directory"
 echo "ERROR: $NEW_IMAGES is not a directory" >> transient_factory_test31.txt
 continue
fi

# Figure out fits file extension for this dataset
FITS_FILE_EXT=$(for POSSIBLE_FITS_FILE_EXT in fts fits fit ;do for IMGFILE in "$NEW_IMAGES"/*."$POSSIBLE_FITS_FILE_EXT" ;do if [ -f "$IMGFILE" ];then echo "$POSSIBLE_FITS_FILE_EXT"; break; fi ;done ;done)
if [ -z "$FITS_FILE_EXT" ];then
 FITS_FILE_EXT="fts"
fi
export FITS_FILE_EXT
echo "FITS_FILE_EXT=$FITS_FILE_EXT"

LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR=$(for IMGFILE in "$NEW_IMAGES"/*."$FITS_FILE_EXT" ;do if [ -f "$IMGFILE" ];then basename "$IMGFILE" ;fi ;done | awk '{if (length($1) >= 3) print $1}' FS='_' | sort | uniq)

echo "Fields in the data directory: 
$LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR"

echo "Processing fields $LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR <br>" >> transient_report/index.html

if [ -z "$LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR" ];then
 echo "ERROR: cannot find image files obeying the assumed naming convention in $string_command_line_argumants"
 echo "ERROR: cannot find image files obeying the assumed naming convention in $string_command_line_argumants" >> transient_factory_test31.txt
 continue
fi

echo "$LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR" >> transient_factory_test31.txt

# Make sure there are no pleantes/comets/transients files
for FILE_TO_REMOVE in planets.txt comets.txt moons.txt asassn_transients_list.txt tocp_transients_list.txt ;do
 if [ -f "$FILE_TO_REMOVE" ];then
  rm -f "$FILE_TO_REMOVE"
 fi
done

# Moved down
## Update planet and bright comet positions taking the date of the first input image
#JD_FIRSTIMAGE_FOR_PLANET_POSITIONS=$(for IMGFILE in "$NEW_IMAGES"/*."$FITS_FILE_EXT" ;do if [ -f "$IMGFILE" ];then util/get_image_date "$IMGFILE" 2>&1 | grep ' JD ' | awk '{print $2}' ; break ;fi ;done)
#if [ -z "$JD_FIRSTIMAGE_FOR_PLANET_POSITIONS" ];then
# echo "ERROR getting reference JD(UT) for computing planet and comet positions"
# continue
#fi
#echo "The reference JD(UT) for computing planet and comet positions: $JD_FIRSTIMAGE_FOR_PLANET_POSITIONS"
#echo "The reference JD(UT) for computing planet and comet positions: $JD_FIRSTIMAGE_FOR_PLANET_POSITIONS" >> transient_factory_test31.txt
#$TIMEOUTCOMMAND util/planets.sh "$JD_FIRSTIMAGE_FOR_PLANET_POSITIONS" > planets.txt &
#$TIMEOUTCOMMAND util/comets.sh "$JD_FIRSTIMAGE_FOR_PLANET_POSITIONS" > comets.txt &
#$TIMEOUTCOMMAND lib/asassn_transients_list.sh > asassn_transients_list.txt &
#$TIMEOUTCOMMAND lib/tocp_transients_list.sh > tocp_transients_list.txt &

PREVIOUS_FIELD="none"

for FIELD in $LIST_OF_FIELDS_IN_THE_NEW_IMAGES_DIR ;do
 
 echo "########### Starting $FIELD ###########" >> transient_factory_test31.txt

 echo "Processing $FIELD" >> transient_factory_test31.txt
 if [ "$FIELD" == "$PREVIOUS_FIELD" ];then
  echo "Script ERROR! This field has been processed just before!"
  echo "Script ERROR! This field has been processed just before!" >> transient_factory_test31.txt
  continue
 fi
 PREVIOUS_FIELD="$FIELD"


 # clean up the local cache
 for FILE_TO_REMOVE in local_wcs_cache/* exclusion_list.txt exclusion_list_bsc.txt exclusion_list_bbsc.txt exclusion_list_tycho2.txt ;do
  if [ -f "$FILE_TO_REMOVE" ];then
   rm -f "$FILE_TO_REMOVE"
   echo "Removing $FILE_TO_REMOVE" >> transient_factory_test31.txt
  fi
 done

 ############## Two reference images and two second-epoch images # check if all images are actually there
 # check if all images are actually there
 N=$(ls "$REFERENCE_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" | wc -l)
 if [ $N -lt 2 ];then
  # Save image date for it to be displayed in the summary file
  print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
  echo "ERROR: too few refereence images for the field $FIELD"
  echo "ERROR: too few refereence images for the field $FIELD" >> transient_factory_test31.txt
  continue
 fi
 N=$(ls "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" | wc -l)
 if [ $N -lt 2 ];then
  # Save image date for it to be displayed in the summary file
  print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
  echo "ERROR: too few new images for the field $FIELD"
  echo "ERROR: too few new images for the field $FIELD" >> transient_factory_test31.txt
  continue
 fi
 echo "Checking input images ($N new)" >> transient_factory_test31.txt
 ################################
 # Choose first epoch images
 # We assume there are two first epoch images, both of them are supposedly good
 REFERENCE_EPOCH__FIRST_IMAGE=$(ls "$REFERENCE_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" | head -n1)
 echo "REFERENCE_EPOCH__FIRST_IMAGE= $REFERENCE_EPOCH__FIRST_IMAGE" >> transient_factory_test31.txt
 REFERENCE_EPOCH__SECOND_IMAGE=$(ls "$REFERENCE_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" | tail -n1)
 echo "REFERENCE_EPOCH__SECOND_IMAGE= $REFERENCE_EPOCH__SECOND_IMAGE" >> transient_factory_test31.txt
 
 # Choose second epoch images
 # first, count how many there are
 NUMBER_OF_SECOND_EPOCH_IMAGES=$(ls "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" | wc -l)
  
 if [ $NUMBER_OF_SECOND_EPOCH_IMAGES -gt 1 ];then
  # Make image previews
  echo "Previews of the second-epoch images:<br>" >> transient_factory_test31.txt
  for FITS_IMAGE_TO_PREVIEW in "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" ;do
   BASENAME_FITS_IMAGE_TO_PREVIEW=$(basename $FITS_IMAGE_TO_PREVIEW)
   PREVIEW_IMAGE="$BASENAME_FITS_IMAGE_TO_PREVIEW"_preview.png
   ######
   if [ -n "$MAKE_PNG_PLOTS" ];then
    if [ "$MAKE_PNG_PLOTS" == "yes" ];then
     # image size needs to match the one set in util/transients/make_report_in_HTML.sh
     export PGPLOT_PNG_WIDTH=1000 ; export PGPLOT_PNG_HEIGHT=1000
     util/fits2png $FITS_IMAGE_TO_PREVIEW &> /dev/null && mv pgplot.png transient_report/$PREVIEW_IMAGE
     unset PGPLOT_PNG_WIDTH ; unset PGPLOT_PNG_HEIGHT
    fi
   fi
   ######
   echo "<br>$BASENAME_FITS_IMAGE_TO_PREVIEW<br><img src=\"$PREVIEW_IMAGE\"><br>" >> transient_factory_test31.txt
  done
  echo "<br>" >> transient_factory_test31.txt
 fi
 
 # The following three if statements should cover all the possibilities:
 # less than 2 images, 2 images, mere than 2 images
 if [ $NUMBER_OF_SECOND_EPOCH_IMAGES -lt 2 ];then
  # Save image date for it to be displayed in the summary file
  print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
  echo "ERROR processing the image series - only $NUMBER_OF_SECOND_EPOCH_IMAGES second-epoch images found"
  echo "ERROR processing the image series - only $NUMBER_OF_SECOND_EPOCH_IMAGES second-epoch images found" >> transient_factory_test31.txt
  continue
 fi
 if [ $NUMBER_OF_SECOND_EPOCH_IMAGES -eq 2 ];then
  SECOND_EPOCH__FIRST_IMAGE=$(ls "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" | head -n1)
  SECOND_EPOCH__SECOND_IMAGE=$(ls "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" | tail -n1)
 fi
 if [ $NUMBER_OF_SECOND_EPOCH_IMAGES -gt 2 ];then
  # There are more than two second-epoch images - do a preliminary VaST run to choose the two images with best seeing
  #cp -v default.sex.telephoto_lens_onlybrightstars_v1 default.sex >> transient_factory_test31.txt
  cp -v $SEXTRACTOR_CONFIG_BRIGHTSTARPASS default.sex >> transient_factory_test31.txt
  echo "Preliminary VaST run on the second-epoch images only" >> transient_factory_test31.txt
  echo "./vast --autoselectrefimage --matchstarnumber 100 --UTC --nofind --failsafe --nomagsizefilter --noerrorsrescale --notremovebadimages --no_guess_saturation_limit"  "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
  ./vast --autoselectrefimage --matchstarnumber 100 --UTC --nofind --failsafe --nomagsizefilter --noerrorsrescale --notremovebadimages --no_guess_saturation_limit  "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" > prelim_vast_run.log 2>&1  
  echo "wait"   >> transient_factory_test31.txt
  wait
  ## Special test for stuck camera ##
  if [ -s vast_image_details.log ];then
   N_SAME_IMAGE=$(grep -c ' rotation= 180.000 ' vast_image_details.log)
   if [ $N_SAME_IMAGE -gt 1 ];then
    # Save image date for it to be displayed in the summary file
    print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
    # Stuck camera
    echo "ERROR the camera is stuck repeatedly sending the same image!"
    echo "***** ACTION NEEDED - RESET CAMERA!!! *****   IMAGE PROCESSING ERROR (stuck camera repeatedly sending the same image) " >> transient_factory.log
    echo "###################################################################################" >> transient_factory.log
    echo "ERROR the camera is stuck repeatedly sending the same image!" >> transient_factory_test31.txt
    rm -f prelim_vast_run.log
    continue
   fi
  fi
  cat prelim_vast_run.log | grep 'Bad reference image...' >> transient_factory.log
  if [ $? -eq 0 ];then
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   # Bad reference image
   echo "ERROR clouds on second-epoch images?"
   echo "***** IMAGE PROCESSING ERROR (clouds?) *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   echo "ERROR clouds on second-epoch images?" >> transient_factory_test31.txt
   rm -f prelim_vast_run.log
   continue
  fi
  if [ -f prelim_vast_run.log ];then
   rm -f prelim_vast_run.log
  fi
  if [ ! -s vast_summary.log ];then
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   echo "ERROR: vast_summary.log is not created during the preliminary VaST run" >> transient_factory_test31.txt
   continue
  fi
  N_PROCESSED_IMAGES_PRELIM_RUN=$(cat vast_summary.log | grep 'Images processed' | awk '{print $3}')
  if [ $N_PROCESSED_IMAGES_PRELIM_RUN -lt 2 ];then
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   echo "ERROR processing second-epoch images!"
   echo "***** IMAGE PROCESSING ERROR (preliminary VaST run) *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   echo "ERROR processing second-epoch images (preliminary VaST run 01)!" >> transient_factory_test31.txt
   continue   
  fi
  N_PROCESSED_IMAGES_PRELIM_RUN=$(cat vast_summary.log | grep 'Images used for photometry' | awk '{print $5}')
  if [ $N_PROCESSED_IMAGES_PRELIM_RUN -lt 2 ];then
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   echo "ERROR processing second-epoch images!"
   echo "***** IMAGE PROCESSING ERROR (preliminary VaST run) *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   echo "ERROR processing second-epoch images (preliminary VaST run 02)!" >> transient_factory_test31.txt
   continue   
  fi
  if [ ! -s vast_image_details.log ];then
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   echo "ERROR: vast_image_details.log is not created (preliminary VaST run)" >> transient_factory_test31.txt
   continue
  fi
  # we can't print the content of vast_image_details.log to transient_factory_test31.txt
  # as it may contain status=ERROR message that will trigger the log parser
  #echo "___ vast_image_details.log from the preliminary VaST run ___" >> transient_factory_test31.txt
  #cat vast_image_details.log >> transient_factory_test31.txt
  #
  # column 9 in vast_image_details.log is the aperture size in pixels
  #### In the following the exclusion of ' ap=  0.0 ' ' ap= 99.0 ' ' status=ERROR ' is needed to handle the case where one new image is bad while the other two are good.
  ### ===> APERTURE LIMITS HARDCODED HERE <===
  #NUMBER_OF_IMAGES_WITH_REASONABLE_SEEING=$(cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' -e ' status=ERROR ' | awk '{if ( $9 > 2 ) print }' | awk '{if ( $9 < 8.5 ) print }' | wc -l)
  #NUMBER_OF_IMAGES_WITH_REASONABLE_SEEING=$(cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' -e ' status=ERROR ' | awk '{if ( $9 > 2 ) print }' | awk -v var="$FILTER_MAX_APERTURE_STAR_SIZE_PIX" '{if ( $9 < var ) print }' | wc -l)
  NUMBER_OF_IMAGES_WITH_REASONABLE_SEEING=$(cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' -e ' status=ERROR ' | awk -v min_var="$FILTER_MIN_APERTURE_STAR_SIZE_PIX" -v max_var="$FILTER_MAX_APERTURE_STAR_SIZE_PIX" '{if ( $9 > min_var && $9 < max_var ) print }' | wc -l)
  if [ $NUMBER_OF_IMAGES_WITH_REASONABLE_SEEING -lt 2 ];then
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   echo "ERROR: seeing on second-epoch images is out of range"
   echo "***** ERROR: seeing on second-epoch images is out of range *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   echo "ERROR: seeing on second-epoch images is out of range" >> transient_factory_test31.txt
   # We are throwing ERROR message anyway, so it's OK to print out vast_image_details.log content that may include the word 'ERROR'
   cat vast_image_details.log >> transient_factory_test31.txt
   continue
  fi
  # Many (like 1 in 3) images are affected by bad tracking and bad pointing (being centered away from the target field center)
  # Bad tracking will result in elongated stars and degraded "seeing"
  ###### All that sounds reasonable but doesn't do any good to pass NMW_find_NovaCas21_test
  # Check if the seeing (reflected in the aperture size) is the same for the three images
  SEEING_AP_FIRST_IMG=$(cat vast_image_details.log | grep 'status=OK' | awk '{if ( $9 > 2 ) print $9}' | head -n1)
  N_IMAGES_WITH_EXACTLY_THIS_SEEING_AP=$(cat vast_image_details.log | grep 'status=OK' | awk '{if ( $9 > 2 ) print $9}' | grep -c "$SEEING_AP_FIRST_IMG")
  if [ $N_IMAGES_WITH_EXACTLY_THIS_SEEING_AP -eq $NUMBER_OF_IMAGES_WITH_REASONABLE_SEEING ];then
   # Consider a special case where the seeing is the same to within 0.1pix on all three images
   # Sort the images on JD and take the two latest ones assuming it's the first image that is most likely affected by bad pointing
   echo "INFO: same seeing for all $NUMBER_OF_IMAGES_WITH_REASONABLE_SEEING images with reasonable seeing" >> transient_factory_test31.txt
   # Take the second-to-last image as SECOND_EPOCH__FIRST_IMAGE
   ### ===> APERTURE LIMITS HARDCODED HERE <===
   #SECOND_EPOCH__FIRST_IMAGE=$(cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' -e ' status=ERROR ' | awk '{if ( $9 > 2 ) print }' | awk '{if ( $9 < 8.5 ) print }' | sort -nk7 | tail -n2 | head -n1 | awk '{print $17}')
   SECOND_EPOCH__FIRST_IMAGE=$(cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' -e ' status=ERROR ' | awk -v min_var="$FILTER_MIN_APERTURE_STAR_SIZE_PIX" -v max_var="$FILTER_MAX_APERTURE_STAR_SIZE_PIX" '{if ( $9 > min_var && $9 < max_var ) print }' | sort -nk7 | tail -n2 | head -n1 | awk '{print $17}')
   echo "SECOND_EPOCH__FIRST_IMAGE= $SECOND_EPOCH__FIRST_IMAGE" >> transient_factory_test31.txt
   # Take the last image as SECOND_EPOCH__SECOND_IMAGE
   ### ===> APERTURE LIMITS HARDCODED HERE <===
   #SECOND_EPOCH__SECOND_IMAGE=$(cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' -e ' status=ERROR ' | awk '{if ( $9 > 2 ) print }' | awk '{if ( $9 < 8.5 ) print }' | sort -nk7 | tail -n1 | awk '{print $17}')
   SECOND_EPOCH__SECOND_IMAGE=$(cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' -e ' status=ERROR ' | awk -v min_var="$FILTER_MIN_APERTURE_STAR_SIZE_PIX" -v max_var="$FILTER_MAX_APERTURE_STAR_SIZE_PIX" '{if ( $9 > min_var && $9 < max_var ) print }' | sort -nk7 | tail -n1 | awk '{print $17}')
   echo "SECOND_EPOCH__SECOND_IMAGE= $SECOND_EPOCH__SECOND_IMAGE" >> transient_factory_test31.txt
  else
   # Consider the usual case where the seeing is somewhat different - pick the two images with the best seeing
   echo "INFO: selecting two second-epoch images with best seeing" >> transient_factory_test31.txt
   #### In the following the exclusion of ' ap=  0.0 ' ' ap= 99.0 ' ' status=ERROR ' is needed to handle the case where one new image is bad while the other two are good.
   ### ===> APERTURE LIMITS HARDCODED HERE <===
   #SECOND_EPOCH__FIRST_IMAGE=$(cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' -e ' status=ERROR ' | awk '{if ( $9 > 2 ) print }' | awk '{if ( $9 < 8.5 ) print }' | sort -nk9 | head -n1 | awk '{print $17}')
   SECOND_EPOCH__FIRST_IMAGE=$(cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' -e ' status=ERROR ' | awk -v min_var="$FILTER_MIN_APERTURE_STAR_SIZE_PIX" -v max_var="$FILTER_MAX_APERTURE_STAR_SIZE_PIX" '{if ( $9 > min_var && $9 < max_var ) print }' | sort -nk9 | head -n1 | awk '{print $17}')
   echo "SECOND_EPOCH__FIRST_IMAGE= $SECOND_EPOCH__FIRST_IMAGE" >> transient_factory_test31.txt
   ### ===> APERTURE LIMITS HARDCODED HERE <===
   #SECOND_EPOCH__SECOND_IMAGE=$(cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' -e ' status=ERROR ' | awk '{if ( $9 > 2 ) print }' | awk '{if ( $9 < 8.5 ) print }' | sort -nk9 | head -n2 | tail -n1 | awk '{print $17}')
   SECOND_EPOCH__SECOND_IMAGE=$(cat vast_image_details.log | grep -v -e ' ap=  0.0 ' -e ' ap= 99.0 ' -e ' status=ERROR ' | awk -v min_var="$FILTER_MIN_APERTURE_STAR_SIZE_PIX" -v max_var="$FILTER_MAX_APERTURE_STAR_SIZE_PIX" '{if ( $9 > min_var && $9 < max_var ) print }' | sort -nk9 | head -n2 | tail -n1 | awk '{print $17}')
   echo "SECOND_EPOCH__SECOND_IMAGE= $SECOND_EPOCH__SECOND_IMAGE" >> transient_factory_test31.txt
  fi
  # Make sure SECOND_EPOCH__FIRST_IMAGE and SECOND_EPOCH__SECOND_IMAGE are set
  if [ -z "$SECOND_EPOCH__FIRST_IMAGE" ];then
   echo "ERROR: SECOND_EPOCH__FIRST_IMAGE is not defined!" >> transient_factory_test31.txt
   cat vast_image_details.log >> transient_factory_test31.txt
   continue
  fi
  if [ -z "$SECOND_EPOCH__SECOND_IMAGE" ];then
   echo "ERROR: SECOND_EPOCH__SECOND_IMAGE is not defined!" >> transient_factory_test31.txt
   cat vast_image_details.log >> transient_factory_test31.txt
   continue
  fi
  if [ "$SECOND_EPOCH__FIRST_IMAGE" = "$SECOND_EPOCH__SECOND_IMAGE" ];then
   echo "ERROR: SECOND_EPOCH__FIRST_IMAGE = SECOND_EPOCH__SECOND_IMAGE"
   cat vast_image_details.log >> transient_factory_test31.txt
   continue
  fi
  ###
  # Check for elliptical star images (tracking error)
  SE_CATALOG_FOR_SECOND_EPOCH__FIRST_IMAGE=$(grep "$SECOND_EPOCH__FIRST_IMAGE" vast_images_catalogs.log | awk '{print $1}')
  MEDIAN_DIFFERENCE_AminusB_PIX=$(cat $SE_CATALOG_FOR_SECOND_EPOCH__FIRST_IMAGE | awk '{print $18-$20}' | util/colstat 2> /dev/null | grep 'MEDIAN=' | awk '{printf "%.2f", $2}')
  ### ===> APERTURE LIMITS HARDCODED HERE <=== (this is median difference in pixels between semi-major and semi-minor axes of the source)
  #TEST=`echo "$MEDIAN_DIFFERENCE_AminusB_PIX < 0.45" | bc -ql`
  #TEST=`echo "$MEDIAN_DIFFERENCE_AminusB_PIX<0.45" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
  #TEST=$(echo "$MEDIAN_DIFFERENCE_AminusB_PIX<0.30" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
  TEST=$(echo "$MEDIAN_DIFFERENCE_AminusB_PIX<$FILTER_MAX_ELONGATION_AminusB_PIX" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
  if [ $TEST -eq 0 ];then
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   echo "ERROR: tracking error (elongated stars), median(A-B)=$MEDIAN_DIFFERENCE_AminusB_PIX pix  $(basename $SECOND_EPOCH__FIRST_IMAGE)" >> transient_factory_test31.txt
   continue
  else
   echo "The star elongation is within the allowed range: median(A-B)=$MEDIAN_DIFFERENCE_AminusB_PIX pix  $(basename $SECOND_EPOCH__FIRST_IMAGE)" >> transient_factory_test31.txt
  fi
  SE_CATALOG_FOR_SECOND_EPOCH__SECOND_IMAGE=$(grep "$SECOND_EPOCH__SECOND_IMAGE" vast_images_catalogs.log | awk '{print $1}')
  MEDIAN_DIFFERENCE_AminusB_PIX=$(cat $SE_CATALOG_FOR_SECOND_EPOCH__SECOND_IMAGE | awk '{print $18-$20}' | util/colstat 2> /dev/null | grep 'MEDIAN=' | awk '{printf "%.2f", $2}')
  ### ===> APERTURE LIMITS HARDCODED HERE <=== (this is median difference in pixels between semi-major and semi-minor axes of the source)
  #TEST=$(echo "$MEDIAN_DIFFERENCE_AminusB_PIX<0.30" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
  TEST=$(echo "$MEDIAN_DIFFERENCE_AminusB_PIX<$FILTER_MAX_ELONGATION_AminusB_PIX" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
  if [ $TEST -eq 0 ];then
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   echo "ERROR: tracking error (elongated stars) median(A-B)=$MEDIAN_DIFFERENCE_AminusB_PIX pix  $(basename $SECOND_EPOCH__SECOND_IMAGE)" >> transient_factory_test31.txt
   continue
  else
   echo "The star elongation is within the allowed range: median(A-B)=$MEDIAN_DIFFERENCE_AminusB_PIX pix  $(basename $SECOND_EPOCH__SECOND_IMAGE)" >> transient_factory_test31.txt
  fi
  ###
 fi # above was the procedure for handling more than two second-epoch images
 
 ################################
 # double-check the files
 for FILE_TO_CHECK in "$REFERENCE_EPOCH__FIRST_IMAGE" "$REFERENCE_EPOCH__SECOND_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE" ;do
  ls "$FILE_TO_CHECK" 
  if [ $? -ne 0 ];then
   echo "ERROR opening file $FILE_TO_CHECK" 1>&2
   echo "ERROR opening file $FILE_TO_CHECK"
  fi
 done | grep "ERROR opening file"
 if [ $? -eq 0 ];then
  # Save image date for it to be displayed in the summary file
  print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
  echo "ERROR processing the image series"
  echo "ERROR processing the image series" >> transient_factory_test31.txt
  continue
 fi
 ################################
 
 # I guess we should be including the calibration attempt here resetting SECOND_EPOCH__FIRST_IMAGE and SECOND_EPOCH__SECOND_IMAGE
 ################################
 echo "Calibration settings: DARK_FRAMES_DIR=$DARK_FRAMES_DIR FLAT_FIELD_FILE=$FLAT_FIELD_FILE"
 echo "Calibration settings: DARK_FRAMES_DIR=$DARK_FRAMES_DIR FLAT_FIELD_FILE=$FLAT_FIELD_FILE" >> transient_factory_test31.txt
 CALIBRATED_SECOND_EPOCH__FIRST_IMAGE=$(try_to_calibrate_the_input_frame "$SECOND_EPOCH__FIRST_IMAGE" 2>> transient_factory_test31.txt)
 if [ $? -eq 0 ];then
  if [ -n "$CALIBRATED_SECOND_EPOCH__FIRST_IMAGE" ];then
   echo "Using calibrated image CALIBRATED_SECOND_EPOCH__FIRST_IMAGE=$CALIBRATED_SECOND_EPOCH__FIRST_IMAGE"
   echo "Using calibrated image CALIBRATED_SECOND_EPOCH__FIRST_IMAGE=$CALIBRATED_SECOND_EPOCH__FIRST_IMAGE" >> transient_factory_test31.txt
   SECOND_EPOCH__FIRST_IMAGE="$CALIBRATED_SECOND_EPOCH__FIRST_IMAGE"
  fi
 fi
 CALIBRATED_SECOND_EPOCH__SECOND_IMAGE=$(try_to_calibrate_the_input_frame "$SECOND_EPOCH__SECOND_IMAGE" 2>> transient_factory_test31.txt)
 if [ $? -eq 0 ];then
  if [ -n "$CALIBRATED_SECOND_EPOCH__SECOND_IMAGE" ];then
   echo "Using calibrated image CALIBRATED_SECOND_EPOCH__SECOND_IMAGE=$CALIBRATED_SECOND_EPOCH__SECOND_IMAGE"
   echo "Using calibrated image CALIBRATED_SECOND_EPOCH__SECOND_IMAGE=$CALIBRATED_SECOND_EPOCH__SECOND_IMAGE" >> transient_factory_test31.txt
   SECOND_EPOCH__SECOND_IMAGE="$CALIBRATED_SECOND_EPOCH__SECOND_IMAGE"
  fi
 fi
 echo "after the calibration attempt:
SECOND_EPOCH__FIRST_IMAGE=$SECOND_EPOCH__FIRST_IMAGE
SECOND_EPOCH__SECOND_IMAGE=$SECOND_EPOCH__SECOND_IMAGE" >> transient_factory_test31.txt
 ################################

 

 ################################
 # triple-check the files as they may have been altered by calibration
 for FILE_TO_CHECK in "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE" ;do
  ls "$FILE_TO_CHECK" 
  if [ $? -ne 0 ];then
   echo "ERROR opening file $FILE_TO_CHECK" 1>&2
   echo "ERROR opening file $FILE_TO_CHECK"
  fi
 done | grep "ERROR opening file"
 if [ $? -eq 0 ];then
  # Save image date for it to be displayed in the summary file
  print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
  echo "ERROR processing the image series"
  echo "ERROR processing the image series" >> transient_factory_test31.txt
  continue
 fi
 ################################

 
 ###############################################
 # Update neverexclude_list.txt
 if [ -f ../neverexclude_list.txt ];then
  echo "Updating neverexclude_list.txt"
  cp -v ../neverexclude_list.txt .
 fi
 ###############################################
 # We may have images from two different cameras that require two different bad region lists
 # ./Nazar_bad_region.lst and ../bad_region.lst
 echo "Choosing bad regions list" >> transient_factory_test31.txt
 # Set custom bad_region.lst if there is one
 # the camera name should be present in the input file (directory) name
 KNOW_THIS_CAMERA_NAME_FOR_BAD_REGION_FILE=0
 echo "$SECOND_EPOCH__FIRST_IMAGE" | grep --quiet -e "Nazar" -e "nazar" -e "NAZAR"
 if [ $? -eq 0 ];then
  KNOW_THIS_CAMERA_NAME_FOR_BAD_REGION_FILE=1
  if [ -f ../Nazar_bad_region.lst ];then
   cp -v ../Nazar_bad_region.lst bad_region.lst >> transient_factory_test31.txt
  fi
 fi
 echo "$SECOND_EPOCH__FIRST_IMAGE" | grep --quiet -e "Planeta" -e "planeta" -e "PLANETA"
 if [ $? -eq 0 ];then
  KNOW_THIS_CAMERA_NAME_FOR_BAD_REGION_FILE=1
  if [ -f ../Planeta_bad_region.lst ];then
   cp -v ../Planeta_bad_region.lst bad_region.lst >> transient_factory_test31.txt
  fi
 fi
 echo "$SECOND_EPOCH__FIRST_IMAGE" | grep --quiet -e "Stas" -e "stas" -e "STAS"
 if [ $? -eq 0 ];then
  KNOW_THIS_CAMERA_NAME_FOR_BAD_REGION_FILE=1
  if [ -f ../Stas_bad_region.lst ];then
   cp -v ../Stas_bad_region.lst bad_region.lst >> transient_factory_test31.txt
  fi
 fi
 echo "$SECOND_EPOCH__FIRST_IMAGE" | grep --quiet -e "STL-11000M" -e "NMW-STL"
 if [ $? -eq 0 ];then
  KNOW_THIS_CAMERA_NAME_FOR_BAD_REGION_FILE=1
  if [ -f ../STL_bad_region.lst ];then
   cp -v ../STL_bad_region.lst bad_region.lst >> transient_factory_test31.txt
  fi
 fi
 if [ -n "$BAD_REGION_FILE" ];then
  if [ -f "$BAD_REGION_FILE" ];then
   KNOW_THIS_CAMERA_NAME_FOR_BAD_REGION_FILE=1
   cp -v "$BAD_REGION_FILE" bad_region.lst >> transient_factory_test31.txt
  fi
 fi
 if [ $KNOW_THIS_CAMERA_NAME_FOR_BAD_REGION_FILE -eq 0 ];then
  if [ -f ../bad_region.lst ];then
   cp -v ../bad_region.lst . >> transient_factory_test31.txt
  else
   echo "No bad regions file found ../bad_region.lst" >> transient_factory_test31.txt
  fi
 fi
 ###############################################

 # We need a local exclusion list not to find the same things in multiple SExtractor runs
 if [ -f exclusion_list_local.txt ];then
  rm -f exclusion_list_local.txt
 fi 

 # Make multiple VaST runs with different SExtractor config files
 ### ===> SExtractor config file <===
 #for SEXTRACTOR_CONFIG_FILE in default.sex.telephoto_lens_onlybrightstars_v1 default.sex.telephoto_lens_v4 ;do
 for SEXTRACTOR_CONFIG_FILE in $SEXTRACTOR_CONFIG_FILES ;do

  # make sure nothing is left running from the previous run (in case it ended early with 'continue')
  echo "wait"   >> transient_factory_test31.txt
  wait
  #
  
  # just to make sure all the child loops will see it
  export SEXTRACTOR_CONFIG_FILE
  
  echo "*------ $SEXTRACTOR_CONFIG_FILE ------*" >> transient_factory_test31.txt
  
  ## Set the SExtractor parameters file
  if [ ! -f "$SEXTRACTOR_CONFIG_FILE" ];then
   echo "ERROR finding $SEXTRACTOR_CONFIG_FILE" >> transient_factory_test31.txt
   continue
  fi
  cp -v "$SEXTRACTOR_CONFIG_FILE" default.sex >> transient_factory_test31.txt

  echo "Starting VaST with $SEXTRACTOR_CONFIG_FILE" >> transient_factory_test31.txt
  # Run VaST
  echo "
  ./vast --starmatchraius 4.0 --matchstarnumber 500 --selectbestaperture --sysrem $SYSREM_ITERATIONS --poly --maxsextractorflag 99 --UTC --nofind --nojdkeyword $REFERENCE_EPOCH__FIRST_IMAGE $REFERENCE_EPOCH__SECOND_IMAGE $SECOND_EPOCH__FIRST_IMAGE $SECOND_EPOCH__SECOND_IMAGE
  " >> transient_factory_test31.txt
  ./vast --starmatchraius 4.0 --matchstarnumber 500 --selectbestaperture --sysrem $SYSREM_ITERATIONS --poly --maxsextractorflag 99 --UTC --nofind --nojdkeyword "$REFERENCE_EPOCH__FIRST_IMAGE" "$REFERENCE_EPOCH__SECOND_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE"
  if [ $? -ne 0 ];then
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   echo "ERROR running VaST on the field $FIELD"
   echo "ERROR running VaST on the field $FIELD" >> transient_factory_test31.txt
   echo "ERROR running VaST on the field $FIELD" >> transient_factory.log
   # drop this field and continue to the next one
   # We want to break from the SExtractor settings files loop here
   break
  fi
  echo "VaST run complete with $SEXTRACTOR_CONFIG_FILE" >> transient_factory_test31.txt
  echo "The four input images were $REFERENCE_EPOCH__FIRST_IMAGE" "$REFERENCE_EPOCH__SECOND_IMAGE" "$SECOND_EPOCH__FIRST_IMAGE" "$SECOND_EPOCH__SECOND_IMAGE"  >> transient_factory_test31.txt
  cat vast_summary.log >> transient_factory.log
  # double-check that the VaST run was OK
  grep --quiet 'Images used for photometry 4' vast_summary.log
  if [ $? -ne 0 ];then
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   echo "***** IMAGE PROCESSING ERROR (less than 4 images processed) *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   echo "ERROR running VaST on the field $FIELD (less than 4 images processed)" >> transient_factory_test31.txt
   cat vast_image_details.log >> transient_factory_test31.txt
   continue
  fi
  echo "############################################################" >> transient_factory.log
  
  # Use cache if possible to speed-up WCS calibration
  for WCSCACHEDIR in "local_wcs_cache" "/mnt/usb/NMW_NG/solved_reference_images" "/home/NMW_web_upload/solved_reference_images" "/dataX/kirx/NMW_NG_rt3_autumn2019/solved_reference_images" ;do
   echo "Checking WCS cache directory $WCSCACHEDIR" >> transient_factory_test31.txt
   if [ -d "$WCSCACHEDIR" ];then
    echo "Found WCS cache directory $WCSCACHEDIR" >> transient_factory_test31.txt
    for i in "$WCSCACHEDIR"/wcs_"$FIELD"_*."$FITS_FILE_EXT" "$WCSCACHEDIR"/wcs_fd_"$FIELD"_*."$FITS_FILE_EXT" "$WCSCACHEDIR"/exclusion_list*; do
     if [ -s "$i" ];then
      # We need some quality check before trusting the solved reference images
      # It may be one of the NMW archive images with broken WCS
      # (pubdate this check - some problematic NMW archive images have no 'A_0_0')
      FITS_IMAGE_TO_CHECK_HEADER=$("$VAST_PATH"util/listhead "$i")
      echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep --quiet -e 'A_0_0' -e 'A_2_0' && echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep --quiet 'PV1_1'
      if [ $? -eq 0 ];then
       echo "$0  -- WARNING, the input image has both SIP and PV distortions kewords! Will try to re-solve the image."
      else
       #
       echo "Creating symlink $i" >> transient_factory_test31.txt
       ln -s $i
      fi
     fi # if [ -s "$i" ];then
    done # for i in "$WCSCACHEDIR"/wcs_"$FIELD"_*."$FITS_FILE_EXT" "$WCSCACHEDIR"/exclusion_list*; do
   fi # if [ -d "$WCSCACHEDIR" ];then
  done # for WCSCACHEDIR in 

  if [ ! -f planets.txt ];then
   JD_FIRSTIMAGE_FOR_PLANET_POSITIONS=$(util/get_image_date "$SECOND_EPOCH__FIRST_IMAGE" 2>&1 | grep ' JD ' | tail -n1 | awk '{print $2}')
   echo "The reference JD(UT) for computing planet and comet positions: $JD_FIRSTIMAGE_FOR_PLANET_POSITIONS"
   echo "The reference JD(UT) for computing planet and comet positions: $JD_FIRSTIMAGE_FOR_PLANET_POSITIONS" >> transient_factory_test31.txt
   $TIMEOUTCOMMAND util/planets.sh "$JD_FIRSTIMAGE_FOR_PLANET_POSITIONS" > planets.txt &
   $TIMEOUTCOMMAND util/comets.sh "$JD_FIRSTIMAGE_FOR_PLANET_POSITIONS" > comets.txt &
   $TIMEOUTCOMMAND util/moons.sh "$JD_FIRSTIMAGE_FOR_PLANET_POSITIONS" > moons.txt &
   $TIMEOUTCOMMAND lib/asassn_transients_list.sh > asassn_transients_list.txt &
   $TIMEOUTCOMMAND lib/tocp_transients_list.sh > tocp_transients_list.txt &
  fi
  
  echo "Plate-solving the images" >> transient_factory_test31.txt
  # WCS-calibration (plate-solving)
  for i in $(cat vast_image_details.log | awk '{print $17}' | sort | uniq) ;do
   util/wcs_image_calibration.sh $i &
  done

  # Wait for all children to end processing
  if [ "$SYSTEM_TYPE" = "Linux" ];then
   # --forest will not fly if we are not on Linux
   ps --forest $(ps -e --no-header -o pid,ppid|awk -vp=$$ 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')  >> transient_factory_test31.txt
  fi
  #####
  echo "wait"   >> transient_factory_test31.txt
  wait
  #####
  if [ "$SYSTEM_TYPE" = "Linux" ];then
   # --forest will not fly if we are not on Linux
   ps --forest $(ps -e --no-header -o pid,ppid|awk -vp=$$ 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')  >> transient_factory_test31.txt
  fi
  
  # Check that the plates were actually solved
  for i in $(cat vast_image_details.log |awk '{print $17}') ;do 
   WCS_IMAGE_NAME_FOR_CHECKS=wcs_"$(basename $i)"
   # make sure we do not have wcs_wcs_
   WCS_IMAGE_NAME_FOR_CHECKS=${WCS_IMAGE_NAME_FOR_CHECKS/wcs_wcs_/wcs_}
   #
   if [ ! -s "$WCS_IMAGE_NAME_FOR_CHECKS" ];then
    echo "***** PLATE SOLVE PROCESSING ERROR *****" >> transient_factory.log
    echo "***** cannot find $WCS_IMAGE_NAME_FOR_CHECKS  *****" >> transient_factory.log
    echo "############################################################" >> transient_factory.log
    echo 'UNSOLVED_PLATE'
   else
    echo "$WCS_IMAGE_NAME_FOR_CHECKS exists and is non-empty" >> transient_factory_test31.txt
    if [ ! -d local_wcs_cache/ ];then
     mkdir local_wcs_cache
    fi
    if [ ! -L "$WCS_IMAGE_NAME_FOR_CHECKS" ];then
     ### ===> SExtractor config file <===
     #if [ "$SEXTRACTOR_CONFIG_FILE" != "default.sex.telephoto_lens_v4" ];then
     if [ "$SEXTRACTOR_CONFIG_FILE" == "$SEXTRACTOR_CONFIG_BRIGHTSTARPASS" ];then
      # save the solved plate to local cache, but only if it's not already a symlink
      echo "Saving $WCS_IMAGE_NAME_FOR_CHECKS to local_wcs_cache/" >> transient_factory_test31.txt
      cp -v "$WCS_IMAGE_NAME_FOR_CHECKS" local_wcs_cache/ >> transient_factory_test31.txt 2>&1
     else
      echo "NOT SAVING $WCS_IMAGE_NAME_FOR_CHECKS to local_wcs_cache/ as this is the run with $SEXTRACTOR_CONFIG_FILE" >> transient_factory_test31.txt
     fi
    fi
   fi
  done | grep --quiet 'UNSOLVED_PLATE'
  if [ $? -eq 0 ];then
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   echo "ERROR found an unsoved plate in the field $FIELD" >> transient_factory.log
   echo "ERROR found an unsoved plate in the field $FIELD" >> transient_factory_test31.txt
   continue
  fi

  # Determine image FoV to compute limits on the pointing accuracy
  WCS_IMAGE_NAME_FOR_CHECKS=wcs_"$(basename $REFERENCE_EPOCH__FIRST_IMAGE)"
  WCS_IMAGE_NAME_FOR_CHECKS="${WCS_IMAGE_NAME_FOR_CHECKS/wcs_wcs_/wcs_}"
  IMAGE_FOV_ARCMIN=$(util/fov_of_wcs_calibrated_image.sh $WCS_IMAGE_NAME_FOR_CHECKS | grep 'Image size:' | awk '{print $3}' | awk -F"'" '{print $1}')

  ##### Set astrometric match limits
  IMAGE_SCALE_ARCSECPIX_STRING=$(util/fov_of_wcs_calibrated_image.sh $WCS_IMAGE_NAME_FOR_CHECKS | grep 'Image scale:' | awk '{print $3}')
  IMAGE_SCALE_ARCSECPIX=$(echo "$IMAGE_SCALE_ARCSECPIX_STRING" | awk -F'"' '{print $1}')
  # MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_HARDLIMIT and MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_OFTLIMIT
  # are used for filtering candidates in util/transients/report_transient.sh
  export MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_SOFTLIMIT=$(echo "$IMAGE_SCALE_ARCSECPIX" | awk '{printf "%.1f",$1}')
  export MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_HARDLIMIT=$(echo "$IMAGE_SCALE_ARCSECPIX" | awk '{printf "%.1f",$1*1.5}')
  export MAX_ANGULAR_DISTANCE_BETWEEN_MEASURED_POSITION_AND_CATALOG_MATCH_ARCSEC=$(echo "$IMAGE_SCALE_ARCSECPIX" | awk '{printf "%.1f",$1*2.0}')
  echo "The image scale is $IMAGE_SCALE_ARCSECPIX_STRING, setting the soft and hard astrometric limits for filtering second-epoch detections: $MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_SOFTLIMIT pix and $MAX_ANGULAR_DISTANCE_BETWEEN_SECOND_EPOCH_DETECTIONS_ARCSEC_HARDLIMIT pix" >> transient_factory_test31.txt

  ##### Set pointing accuracy limits
  ## 1 deg hard limit for the NMW camera
  #FOV_DEG_LIMIT_HARD=$(echo "$IMAGE_FOV_ARCMIN" | awk '{printf "%.3f",$1/466.5*1.0}')
  ## 0.25 deg soft limit for the NMW camera
  #FOV_DEG_LIMIT_SOFT=$(echo "$IMAGE_FOV_ARCMIN" | awk '{printf "%.3f",$1/466.5*0.25}')
  # Relax the pointing limits
  #FOV_DEG_LIMIT_HARD=$(echo "$IMAGE_FOV_ARCMIN" | awk '{printf "%.3f",$1/466.5*1.0}')
  #FOV_DEG_LIMIT_SOFT=$(echo "$IMAGE_FOV_ARCMIN" | awk '{printf "%.3f",$1/466.5*0.5}')
  FOV_DEG_LIMIT_HARD=$(echo "$IMAGE_FOV_ARCMIN" | awk '{val = $1/466.5*1.0; if (val < 0.2) val = 0.2; else if (val > 1.0) val = 1.0; printf "%.3f", val}')
  FOV_DEG_LIMIT_SOFT=$(echo "$IMAGE_FOV_ARCMIN" | awk '{val = $1/466.5*0.5; if (val < 0.1) val = 0.1; else if (val > 0.5) val = 0.5; printf "%.3f", val}')

  # Compare image centers of the reference and second-epoch image
  WCS_IMAGE_NAME_FOR_CHECKS=wcs_"$(basename $REFERENCE_EPOCH__FIRST_IMAGE)"
  WCS_IMAGE_NAME_FOR_CHECKS="${WCS_IMAGE_NAME_FOR_CHECKS/wcs_wcs_/wcs_}"
  IMAGE_CENTER__REFERENCE_EPOCH__FIRST_IMAGE=$(util/fov_of_wcs_calibrated_image.sh $WCS_IMAGE_NAME_FOR_CHECKS | grep 'Image center:' | awk '{print $3" "$4}')

  #### Do the pointing check for the first image of the second epoch
  WCS_IMAGE_NAME_FOR_CHECKS=wcs_"$(basename $SECOND_EPOCH__FIRST_IMAGE)"
  WCS_IMAGE_NAME_FOR_CHECKS="${WCS_IMAGE_NAME_FOR_CHECKS/wcs_wcs_/wcs_}"
  IMAGE_CENTER__SECOND_EPOCH__FIRST_IMAGE=$(util/fov_of_wcs_calibrated_image.sh $WCS_IMAGE_NAME_FOR_CHECKS | grep 'Image center:' | awk '{print $3" "$4}')
  DISTANCE_BETWEEN_IMAGE_CENTERS_DEG=$(lib/put_two_sources_in_one_field $IMAGE_CENTER__REFERENCE_EPOCH__FIRST_IMAGE $IMAGE_CENTER__SECOND_EPOCH__FIRST_IMAGE 2>/dev/null | grep 'Angular distance' | awk '{printf "%.2f", $5}')
  echo "###################################
# Check the image center offset between the reference and the first second-epoch image (pointing accuracy)
Reference image center $IMAGE_CENTER__REFERENCE_EPOCH__FIRST_IMAGE
Second-epoch image center $IMAGE_CENTER__SECOND_EPOCH__FIRST_IMAGE
Angular distance between the image centers $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg.
Soft limit: $FOV_DEG_LIMIT_SOFT deg.  Hard limit: $FOV_DEG_LIMIT_HARD deg.
###################################" >> transient_factory_test31.txt
  ### ===> POINTING ACCURACY LIMITS HARDCODED HERE <===
  #TEST=`echo "$DISTANCE_BETWEEN_IMAGE_CENTERS_DEG>1.0" | bc -ql`
  TEST=$(echo "$DISTANCE_BETWEEN_IMAGE_CENTERS_DEG>$FOV_DEG_LIMIT_HARD" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
  if [ $TEST -eq 1 ];then
   if [ "$CHECK_POINTING_ACCURACY" = "yes" ] ;then  
    # Save image date for it to be displayed in the summary file
    print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
    echo "ERROR: (NO CANDIDATES LISTED) distance between 1st reference and 1st second-epoch image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg. (Hard limit: $FOV_DEG_LIMIT_HARD deg.)"
    echo "ERROR: (NO CANDIDATES LISTED) distance between 1st reference and 1st second-epoch image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg. (Hard limit: $FOV_DEG_LIMIT_HARD deg.)" >> transient_factory_test31.txt
    break
    # This should break us form the SEXTRACTOR_CONFIG_FILE cycle
   fi
  fi
  ### ===> POINTING ACCURACY LIMITS HARDCODED HERE <===
  # Note that the sister parameter is also set below
  # Relax the reference-new image pointing difference threshold for raising the error
  TEST=$(echo "$DISTANCE_BETWEEN_IMAGE_CENTERS_DEG>$FOV_DEG_LIMIT_SOFT" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
  if [ $TEST -eq 1 ];then
   if [ "$CHECK_POINTING_ACCURACY" = "yes" ] ;then  
    echo "ERROR: distance between 1st reference and 1st second-epoch image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg. (Soft limit: $FOV_DEG_LIMIT_SOFT deg.)"
    echo "ERROR: distance between 1st reference and 1st second-epoch image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg. (Soft limit: $FOV_DEG_LIMIT_SOFT deg.)" >> transient_factory_test31.txt
    #break
    # Not break'ing here, the offset is not hopelessly large and we want to keep candidates from this field
   fi
  fi


  #### Do the pointing check for the second image of the second epoch
  WCS_IMAGE_NAME_FOR_CHECKS=wcs_"$(basename $SECOND_EPOCH__SECOND_IMAGE)"
  WCS_IMAGE_NAME_FOR_CHECKS="${WCS_IMAGE_NAME_FOR_CHECKS/wcs_wcs_/wcs_}"
  IMAGE_CENTER__SECOND_EPOCH__SECOND_IMAGE=$(util/fov_of_wcs_calibrated_image.sh $WCS_IMAGE_NAME_FOR_CHECKS | grep 'Image center:' | awk '{print $3" "$4}')
  DISTANCE_BETWEEN_IMAGE_CENTERS_DEG=$(lib/put_two_sources_in_one_field $IMAGE_CENTER__REFERENCE_EPOCH__FIRST_IMAGE $IMAGE_CENTER__SECOND_EPOCH__SECOND_IMAGE 2>/dev/null | grep 'Angular distance' | awk '{printf "%.2f", $5}')
  echo "###################################
# Check the image center offset between the reference and the second second-epoch image (pointing accuracy)
Reference image center $IMAGE_CENTER__REFERENCE_EPOCH__FIRST_IMAGE
Second-epoch image center $IMAGE_CENTER__SECOND_EPOCH__SECOND_IMAGE
Angular distance between the image centers $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg.
###################################" >> transient_factory_test31.txt
  ### ===> POINTING ACCURACY LIMITS HARDCODED HERE <===
  #TEST=`echo "$DISTANCE_BETWEEN_IMAGE_CENTERS_DEG>1.0" | bc -ql`
  TEST=$(echo "$DISTANCE_BETWEEN_IMAGE_CENTERS_DEG>$FOV_DEG_LIMIT_HARD" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
  if [ $TEST -eq 1 ];then
   if [ "$CHECK_POINTING_ACCURACY" = "yes" ] ;then  
    # Save image date for it to be displayed in the summary file
    print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
    echo "ERROR: (NO CANDIDATES LISTED) distance between 1st reference and 2nd second-epoch image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg. (Hard limit: $FOV_DEG_LIMIT_HARD deg.)"
    echo "ERROR: (NO CANDIDATES LISTED) distance between 1st reference and 2nd second-epoch image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg. (Hard limit: $FOV_DEG_LIMIT_HARD deg.)" >> transient_factory_test31.txt
    break
    # This should break us form the SEXTRACTOR_CONFIG_FILE cycle
   fi
  fi
  ### ===> POINTING ACCURACY LIMITS HARDCODED HERE <===
  #TEST=`echo "$DISTANCE_BETWEEN_IMAGE_CENTERS_DEG>0.2" | bc -ql`
  #TEST=`echo "$DISTANCE_BETWEEN_IMAGE_CENTERS_DEG>0.2" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
  ## Note that this is also set above!
  TEST=$(echo "$DISTANCE_BETWEEN_IMAGE_CENTERS_DEG>$FOV_DEG_LIMIT_SOFT" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
  if [ $TEST -eq 1 ];then
   if [ "$CHECK_POINTING_ACCURACY" = "yes" ] ;then  
    echo "ERROR: distance between 1st reference and 2nd second-epoch image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg. (Soft limit: $FOV_DEG_LIMIT_SOFT deg.)"
    echo "ERROR: distance between 1st reference and 2nd second-epoch image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg. (Soft limit: $FOV_DEG_LIMIT_SOFT deg.)" >> transient_factory_test31.txt
    #break
    # Not break'ing here, the offset is not hopelessly large and we want to keep candidates from this field
   fi
  fi
  
  # Check if shift is applied to secondepoch images
  if [ -n "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" ];then
   if [ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" = "yes" ];then
    ### ===> POINTING ACCURACY LIMITS HARDCODED HERE <===
    # Require a 3 pixel shift, but no less than 1"
    MIN_IMAGE_SHIFT_ARCSEC=$(echo "$IMAGE_SCALE_ARCSECPIX" | awk '{val = 3*$1; printf "%.1f", (val<1.0?1.0:val)}')
    MIN_IMAGE_SHIFT_DEG=$(echo "$MIN_IMAGE_SHIFT_ARCSEC" | awk '{printf "%.5f", $1/3600}')
    #
    DISTANCE_BETWEEN_IMAGE_CENTERS_DEG=$(lib/put_two_sources_in_one_field $IMAGE_CENTER__SECOND_EPOCH__FIRST_IMAGE $IMAGE_CENTER__SECOND_EPOCH__SECOND_IMAGE 2>/dev/null | grep 'Angular distance' | awk '{printf "%.5f", $5}')
    echo "###################################
# Check the image center offset between the first and the second second-epoch image (ahift should be applied between the second-epoch images)
Second-epoch first image center  $IMAGE_CENTER__SECOND_EPOCH__FIRST_IMAGE
Second-epoch second image center $IMAGE_CENTER__SECOND_EPOCH__SECOND_IMAGE
Angular distance between the image centers $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg.
###################################" >> transient_factory_test31.txt
    TEST=$(echo "$DISTANCE_BETWEEN_IMAGE_CENTERS_DEG<$MIN_IMAGE_SHIFT_DEG" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
    if [ $TEST -eq 1 ];then
     if [ "$CHECK_POINTING_ACCURACY" = "yes" ] ;then  
      echo "ERROR: no shift applied between second-epoch images! The distance between image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg. (min. required shift: $MIN_IMAGE_SHIFT_DEG deg.)"
      echo "ERROR: no shift applied between second-epoch images! The distance between image centers is $DISTANCE_BETWEEN_IMAGE_CENTERS_DEG deg. (min. required shift: $MIN_IMAGE_SHIFT_DEG deg.)" >> transient_factory_test31.txt
      #break
      # Not break'ing here
     fi # if [ "$CHECK_POINTING_ACCURACY" = "YES"
    fi
    #
    
    #
    
   fi # if [ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" = "yes" ]
  fi # if [ -n "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" ];then


  # Here we need to know if we need photometic calibration for hte astrometic catalog - it's slow
  if [ -z "$PHOTOMETRIC_CALIBRATION" ];then
   if [ $IMAGE_FOV_ARCMIN -lt 240 ];then
    # APASS magnitude calibration for narrow-field images
    PHOTOMETRIC_CALIBRATION="APASS_V"
   else
    # Tycho-2 magnitude calibration for wide-field images
    # (Tycho-2 is relatively small, so it's convenient to have a local copy of the catalog)
    PHOTOMETRIC_CALIBRATION="TYCHO2_V"
   fi
  fi

  
  echo "Running solve_plate_with_UCAC5" >> transient_factory_test31.txt
  
    
  # We need photometric info for the referenc image 
  if [ "$PHOTOMETRIC_CALIBRATION" != "TYCHO2_V" ];then
   util/solve_plate_with_UCAC5 --iterations $UCAC5_PLATESOLVE_ITERATIONS $REFERENCE_EPOCH__FIRST_IMAGE
  fi
  # Now solve all images in parallel with no photomeric calibration
  for i in $(cat vast_image_details.log | awk '{print $17}' | sort | uniq) ;do
   util/solve_plate_with_UCAC5 --no_photometric_catalog --iterations $UCAC5_PLATESOLVE_ITERATIONS  $i &
  done
    
  # Calibrate magnitude scale with Tycho-2 or APASS stars in the field
  # In order for this to work, we need the plate-solved reference image 
  echo "Calibrating the magnitude scale" >> transient_factory_test31.txt
  if [ -f 'lightcurve.tmp_emergency_stop_debug' ];then
   rm -f 'lightcurve.tmp_emergency_stop_debug'
  fi
  WCS_IMAGE_NAME_FOR_CHECKS=wcs_"$(basename $REFERENCE_EPOCH__FIRST_IMAGE)"
  WCS_IMAGE_NAME_FOR_CHECKS="${WCS_IMAGE_NAME_FOR_CHECKS/wcs_wcs_/wcs_}"
  if [ ! -s "$WCS_IMAGE_NAME_FOR_CHECKS" ];then
   echo "$WCS_IMAGE_NAME_FOR_CHECKS does not exist or is empty: waiting for solve_plate_with_UCAC5" >> transient_factory_test31.txt
   # Wait here hoping util/solve_plate_with_UCAC5 will plate-solve the reference image
   if [ "$SYSTEM_TYPE" = "Linux" ];then
    echo "xxxxxxxxxx process tree ($WCS_IMAGE_NAME_FOR_CHECKS does not exist or is empty) xxxxxxxxxx" >> transient_factory_test31.txt
    # --forest will not fly if we are not on Linux
    ps --forest $(ps -e --no-header -o pid,ppid|awk -vp=$$ 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')  >> transient_factory_test31.txt
    echo "xxxxxxxxxx xxxxxxxxxx" >> transient_factory_test31.txt
   fi
   #####
   echo "wait"   >> transient_factory_test31.txt
   wait
   #####
   if [ "$SYSTEM_TYPE" = "Linux" ];then
    echo "xxxxxxxxxx process tree (after wait) xxxxxxxxxx" >> transient_factory_test31.txt
    # --forest will not fly if we are not on Linux
    ps --forest $(ps -e --no-header -o pid,ppid|awk -vp=$$ 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')  >> transient_factory_test31.txt
    echo "xxxxxxxxxx xxxxxxxxxx" >> transient_factory_test31.txt
   fi
  else
   echo "Found non-empty $WCS_IMAGE_NAME_FOR_CHECKS" >> transient_factory_test31.txt
  fi
  # Print the process tree
  if [ "$SYSTEM_TYPE" = "Linux" ];then
   echo "xxxxxxxxxx process tree (before magnitude calibration) xxxxxxxxxx" >> transient_factory_test31.txt
   # --forest will not fly if we are not on Linux 
   ps --forest $(ps -e --no-header -o pid,ppid|awk -vp=$$ 'function r(s){print s;s=a[s];while(s){sub(",","",s);t=s;sub(",.*","",t);sub("[0-9]+","",s);r(t)}}{a[$2]=a[$2]","$1}END{r(p)}')  >> transient_factory_test31.txt
   echo "xxxxxxxxxx xxxxxxxxxx" >> transient_factory_test31.txt
  fi
  echo "____ Start of magnitude calibration ____" >> transient_factory_test31.txt
  # Decide which catalog to use for magnitude calibration depending on the image filed of view
  if [ -z "$PHOTOMETRIC_CALIBRATION" ];then
   if [ $IMAGE_FOV_ARCMIN -lt 240 ];then
    # APASS magnitude calibration for narrow-field images
    PHOTOMETRIC_CALIBRATION="APASS_V"
   else
    # Tycho-2 magnitude calibration for wide-field images
    # (Tycho-2 is relatively small, so it's convenient to have a local copy of the catalog)
    PHOTOMETRIC_CALIBRATION="TYCHO2_V"
   fi
  fi
  echo "PHOTOMETRIC_CALIBRATION=$PHOTOMETRIC_CALIBRATION" >> transient_factory_test31.txt
  case $PHOTOMETRIC_CALIBRATION in
   "APASS_B")
    echo "Calibrating the magnitude scale with APASS B stars" >> transient_factory_test31.txt
    util/magnitude_calibration.sh B zero_point >> transient_factory_test31.txt
    MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=$?
    ;;
   "APASS_g")
    echo "Calibrating the magnitude scale with APASS g stars" >> transient_factory_test31.txt
    util/magnitude_calibration.sh g zero_point >> transient_factory_test31.txt
    MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=$?
    ;;
   "APASS_V")
    echo "Calibrating the magnitude scale with APASS V stars" >> transient_factory_test31.txt
    util/magnitude_calibration.sh V zero_point >> transient_factory_test31.txt
    MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=$?
    ;;
   "APASS_r")
    echo "Calibrating the magnitude scale with APASS r stars" >> transient_factory_test31.txt
    util/magnitude_calibration.sh r zero_point >> transient_factory_test31.txt
    MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=$?
    ;;
   "APASS_R")
    echo "Calibrating the magnitude scale with APASS R stars" >> transient_factory_test31.txt
    util/magnitude_calibration.sh R zero_point >> transient_factory_test31.txt
    MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=$?
    ;;
   "APASS_I")
    echo "Calibrating the magnitude scale with APASS I stars" >> transient_factory_test31.txt
    util/magnitude_calibration.sh I zero_point >> transient_factory_test31.txt
    MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=$?
    ;;
   "TYCHO2_V")
    echo "Calibrating the magnitude scale with Tycho-2 stars" >> transient_factory_test31.txt
    #############
    #
    # Make sure the WCS-calibrated reference image and the corresponding catalog are here
    # - they will be used by util/transients/calibrate_current_field_with_tycho2.sh
    # (if not present calibrate_current_field_with_tycho2.sh may try to recreate them and collide with a plate solution launched by $0)
    REFERENCE_IMAGE=$(cat vast_summary.log | grep "Ref.  image:" |awk '{print $6}')
    TEST_SUBSTRING=$(basename $REFERENCE_IMAGE)
    TEST_SUBSTRING="${TEST_SUBSTRING:0:4}"
    if [ "$TEST_SUBSTRING" = "wcs_" ];then
     WCS_CALIBRATED_REFERENCE_IMAGE=$(basename $REFERENCE_IMAGE)
    else
     WCS_CALIBRATED_REFERENCE_IMAGE=wcs_$(basename $REFERENCE_IMAGE)
    fi
    SEXTRACTOR_CATALOG_NAME="$WCS_CALIBRATED_REFERENCE_IMAGE".cat
    echo "$0 is checking for the presence of non-empty $WCS_CALIBRATED_REFERENCE_IMAGE and $SEXTRACTOR_CATALOG_NAME " >> transient_factory_test31.txt
    if [ ! -s "$WCS_CALIBRATED_REFERENCE_IMAGE" ] || [ ! -s "$SEXTRACTOR_CATALOG_NAME" ] ;then
     echo "$0 has not found non-empty $WCS_CALIBRATED_REFERENCE_IMAGE and $SEXTRACTOR_CATALOG_NAME" >> transient_factory_test31.txt
     echo "wait" >> transient_factory_test31.txt
     wait
    fi
    #############
    echo "y" | util/transients/calibrate_current_field_with_tycho2.sh >> transient_factory_test31.txt 2>&1
    MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=$?
    ;;
   *)
    echo "ERROR: unknown value PHOTOMETRIC_CALIBRATION=$PHOTOMETRIC_CALIBRATION" >> transient_factory_test31.txt
    MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=1
    ;;
  esac
  grep 'Estimated ref. image limiting mag.:' vast_summary.log >> transient_factory_test31.txt
  echo "____ End of magnitude calibration ____" >> transient_factory_test31.txt
  # Check that the magnitude calibration actually worked
  for i in $(cat candidates-transients.lst | awk '{print $1}') ;do 
   ### ===> MAGNITUDE LIMITS HARDCODED HERE <===
   #cat "$i" | awk '{print $2}' | util/colstat 2>&1 | grep 'MEAN=' | awk '{if ( $2 < -5 && $2 >18 ) print "ERROR"}' | grep 'ERROR' && break
   # The reference frame might be a few magnitudes deeper than the new frames
   cat "$i" | awk '{print $2}' | util/colstat 2>&1 | grep 'MEAN=' | awk -v var="$FILTER_BRIGHT_MAG_CUTOFF" -v var2="$FILTER_FAINT_MAG_CUTOFF_TRANSIENT_SEARCH" '{if ( $2 < var && $2 > var2+5.0 ) print "ERROR"}' | grep 'ERROR' && break
  done | grep --quiet 'ERROR'
  #
  if [ $? -eq 0 ];then
   # Wait for the solve_plate_with_UCAC5 stuff to finish
   echo "wait"   >> transient_factory_test31.txt
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   wait
   # Throw an error
   echo "ERROR calibrating magnitudes in the field $FIELD (mean mag outside of range)"
   echo "ERROR calibrating magnitudes in the field $FIELD (mean mag outside of range)" >> transient_factory_test31.txt
   echo "***** MAGNITUDE CALIBRATION ERROR (candidate mag is out of the expected range) *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   # continue to the next field
   continue
  fi
  if [ $MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE -ne 0 ];then
   # Wait for the solve_plate_with_UCAC5 stuff to finish
   echo "wait"   >> transient_factory_test31.txt
   wait
   # Save image date for it to be displayed in the summary file
   print_image_date_for_logs_in_case_of_emergency_stop "$NEW_IMAGES"/"$FIELD"_*_*."$FITS_FILE_EXT" >> transient_factory_test31.txt
   # Throw an error
   echo "ERROR calibrating magnitudes in the field $FIELD MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=$MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE"
   echo "ERROR calibrating magnitudes in the field $FIELD MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE=$MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE" >> transient_factory_test31.txt
   echo "***** MAGNITUDE CALIBRATION ERROR (mag calibration script exited with code $MAGNITUDE_CALIBRATION_SCRIPT_EXIT_CODE) *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   # continue to the next field
   continue
  fi
  if [ -f 'lightcurve.tmp_emergency_stop_debug' ];then
   # Wait for the solve_plate_with_UCAC5 stuff to finish
   echo "wait"   >> transient_factory_test31.txt
   wait
   # Throw an error
   echo "ERROR calibrating magnitudes in the field $FIELD (found lightcurve.tmp_emergency_stop_debug)"
   echo "ERROR calibrating magnitudes in the field $FIELD (found lightcurve.tmp_emergency_stop_debug)" >> transient_factory_test31.txt
   echo "############################################################" >> transient_factory_test31.txt
   cat lightcurve.tmp_emergency_stop_debug >> transient_factory_test31.txt
   echo "############################################################" >> transient_factory_test31.txt
   echo "***** MAGNITUDE CALIBRATION ERROR (lightcurve.tmp_emergency_stop_debug) *****" >> transient_factory.log
   echo "############################################################" >> transient_factory.log
   # continue to the next field
   continue
  fi

  ################## Quality cuts applied to calibrated magnitudes of the candidate transients ##################
  cp -v candidates-transients.lst DEBUG_BACKUP_candidates-transients.lst
  echo "Filter-out faint candidates..." >> transient_factory_test31.txt
  echo "Filter-out faint candidates..."
  # Filter-out faint candidates
  ### ===> MAGNITUDE LIMITS HARDCODED HERE <===
  #for i in $(cat candidates-transients.lst | awk '{print $1}') ;do A=$(tail -n2 $i | awk '{print $2}') ; TEST=$(echo ${A//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2">13.5"}'|bc -ql) ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
  for i in $(cat candidates-transients.lst | awk '{print $1}') ;do A=$(tail -n2 $i | awk '{print $2}') ; TEST=$(echo ${A//[$'\t\r\n ']/ } | awk -v var="$FILTER_FAINT_MAG_CUTOFF_TRANSIENT_SEARCH" '{print ((($1+$2)/2>var)?1:0)}' ) ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

  echo "Filter-out suspiciously bright candidates..." >> transient_factory_test31.txt
  echo "Filter-out suspiciously bright candidates..."
  # Filter-out suspiciously bright candidates
  ### ===> MAGNITUDE LIMITS HARDCODED HERE <===
  #for i in $(cat candidates-transients.lst | awk '{print $1}') ;do A=$(tail -n2 $i | awk '{print $2}') ; TEST=$(echo ${A//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2"<-5.0"}'|bc -ql) ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
  for i in $(cat candidates-transients.lst | awk '{print $1}') ;do A=$(tail -n2 $i | awk '{print $2}') ; TEST=$(echo ${A//[$'\t\r\n ']/ } | awk -v var="$FILTER_BRIGHT_MAG_CUTOFF" '{print ((($1+$2)/2<var)?1:0)}' ) ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

  echo "Filter-out candidates with large difference between measured mags in one epoch..." >> transient_factory_test31.txt
  echo "Filter-out candidates with large difference between measured mags in one epoch..."
  # 2nd epoch
  # Filter-out candidates with large difference between measured mags
  for i in $(cat candidates-transients.lst | awk '{print $1}') ;do A=$(tail -n2 $i | awk '{print $2}') ; TEST=$(echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($1-$2)>0.4 ) print 1; else print 0 }') ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
  # Filter-out candidates with large difference between measured mags
  for i in $(cat candidates-transients.lst | awk '{print $1}') ;do A=$(tail -n2 $i | awk '{print $2}') ; TEST=$(echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($2-$1)>0.4 ) print 1; else print 0 }') ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
  # 1st epoch (only for sources detected on two reference images)
  # Filter-out candidates with large difference between measured mags
  for i in $(cat candidates-transients.lst | awk '{print $1}') ;do if [ $(cat $i | wc -l) -lt 4 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=$(head -n2 $i | awk '{print $2}') ; TEST=$(echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($1-$2)>1.0 ) print 1; else print 0 }') ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
  # Filter-out candidates with large difference between measured mags
  for i in $(cat candidates-transients.lst | awk '{print $1}') ;do if [ $(cat $i | wc -l) -lt 4 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=$(head -n2 $i | awk '{print $2}') ; TEST=$(echo ${A//[$'\t\r\n ']/ } | awk '{if ( ($2-$1)>1.0 ) print 1; else print 0 }') ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

  ############################################
  # Remove candidates close to frame edge
  # here we assume that all images are the samesize as $SECOND_EPOCH__SECOND_IMAGE
  DIMX=$(util/listhead "$SECOND_EPOCH__SECOND_IMAGE" | grep NAXIS1 | awk '{print $3}' | head -n1)
  DIMY=$(util/listhead "$SECOND_EPOCH__SECOND_IMAGE" | grep NAXIS2 | awk '{print $3}' | head -n1)
  ### ===> IMAGE EDGE OFFSET HARDCODED HERE <===
  for i in $(cat candidates-transients.lst | awk '{print $1}') ;do 
   cat $i | awk "{if ( \$4>$FRAME_EDGE_OFFSET_PIX && \$4<$DIMX-$FRAME_EDGE_OFFSET_PIX && \$5>$FRAME_EDGE_OFFSET_PIX && \$5<$DIMY-$FRAME_EDGE_OFFSET_PIX ) print \"YES\"; else print \"NO\" }" | grep --quiet 'NO'
   if [ $? -ne 0 ];then
    # If there was no "NO" answer for any of the lines
    grep $i candidates-transients.lst | head -n1 
   fi
  done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst
  ############################################

  echo "Filter-out small-amplitude flares..." >> transient_factory_test31.txt
  echo "Filter-out small-amplitude flares..."
  # Filter-out small-amplitude flares
  for i in $(cat candidates-transients.lst | awk '{print $1}') ;do if [ $(cat $i | wc -l) -eq 2 ];then grep $i candidates-transients.lst | head -n1 ;continue ;fi ; A=$(head -n1 $i | awk '{print $2}') ; B=$(tail -n2 $i | awk '{print $2}') ; MEANMAGSECONDEPOCH=$(echo ${B//[$'\t\r\n ']/ } | awk '{print ($1+$2)/2}') ; TEST=$(echo $A $MEANMAGSECONDEPOCH | awk '{if ( ($1-$2)<0.5 ) print 1; else print 0 }') ; if [ $TEST -eq 0 ];then grep $i candidates-transients.lst | head -n1 ;fi ;done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

  # Make sure each candidate is detected on the two second-epoch images, not any other combination
  for i in $(cat candidates-transients.lst | awk '{print $1}') ;do 
   grep --quiet "$SECOND_EPOCH__FIRST_IMAGE" "$i"
   if [ $? -ne 0 ];then
    continue
   fi
   grep --quiet "$SECOND_EPOCH__SECOND_IMAGE" "$i"
   if [ $? -ne 0 ];then
    continue
   fi
   grep $i candidates-transients.lst | head -n1 
  done > candidates-transients.tmp ; mv candidates-transients.tmp candidates-transients.lst

  ### Prepare the exclusion lists for this field
  echo "Preparing the exclusion lists for this field" >> transient_factory_test31.txt
  # Exclude the previously considered candidates
  if [ ! -s exclusion_list.txt ];then
   if [ -s "$EXCLUSION_LIST" ];then
    SECOND_EPOCH_IMAGE_ONE=$(cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1)
    WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE=wcs_"$(basename $SECOND_EPOCH_IMAGE_ONE)"
    lib/bin/sky2xy $WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE @$EXCLUSION_LIST | grep -v -e 'off image' -e 'offscale' | awk '{print $1" "$2}' > exclusion_list.txt
    cp -v exclusion_list.txt local_wcs_cache/ >> transient_factory_test31.txt 2>&1
   fi
  fi
  # Exclude stars from the Bright Star Catalog with magnitudes < 3
  if [ ! -s exclusion_list_bbsc.txt ];then
   if [ -s lib/catalogs/brightbright_star_catalog_radeconly.txt ];then
    SECOND_EPOCH_IMAGE_ONE=$(cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1)
    WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE=wcs_"$(basename $SECOND_EPOCH_IMAGE_ONE)"
    lib/bin/sky2xy $WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE @lib/catalogs/brightbright_star_catalog_radeconly.txt | grep -v -e 'off image' -e 'offscale' | awk '{print $1" "$2}' > exclusion_list_bbsc.txt
    cp -v exclusion_list_bbsc.txt local_wcs_cache/ >> transient_factory_test31.txt 2>&1
   fi
  fi
  # Exclude stars from the Bright Star Catalog with magnitudes < 7
  if [ ! -s exclusion_list_bsc.txt ];then
   if [ -s lib/catalogs/bright_star_catalog_radeconly.txt ];then
    SECOND_EPOCH_IMAGE_ONE=$(cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1)
    WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE=wcs_"$(basename $SECOND_EPOCH_IMAGE_ONE)"
    lib/bin/sky2xy $WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE @lib/catalogs/bright_star_catalog_radeconly.txt | grep -v -e 'off image' -e 'offscale' | awk '{print $1" "$2}' > exclusion_list_bsc.txt
    cp -v exclusion_list_bsc.txt local_wcs_cache/ >> transient_factory_test31.txt 2>&1
   fi
  fi
  # Exclude bright Tycho-2 stars, by default the magnitude limit is set to vt < 9
  if [ ! -s exclusion_list_tycho2.txt ];then
   if [ -s lib/catalogs/list_of_bright_stars_from_tycho2.txt ];then
    SECOND_EPOCH_IMAGE_ONE=$(cat vast_image_details.log | awk '{print $17}' | head -n3 | tail -n1)
    WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE=wcs_"$(basename $SECOND_EPOCH_IMAGE_ONE)"
    lib/bin/sky2xy $WCS_SOLVED_SECOND_EPOCH_IMAGE_ONE @lib/catalogs/list_of_bright_stars_from_tycho2.txt | grep -v -e 'off image' -e 'offscale' | awk '{print $1" "$2}' | while read -r A ;do lib/deg2hms $A ;done > exclusion_list_tycho2.txt
    cp -v exclusion_list_tycho2.txt local_wcs_cache/ >> transient_factory_test31.txt 2>&1
   fi
  fi
  ###
  echo "Done with filtering" >> transient_factory_test31.txt
  echo "Done with filtering! =)"
  ###############################################################################################################

  ###############################################################################################################
  # Check if the number of detected transients is suspiciously large
  NUMBER_OF_DETECTED_TRANSIENTS=$(cat candidates-transients.lst | wc -l)
  echo "Found $NUMBER_OF_DETECTED_TRANSIENTS candidate transients before the final filtering." >> transient_factory_test31.txt
  if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt $NUMBER_OF_DETECTED_TRANSIENTS_BEFORE_FILTERING_HARD_LIMIT ];then
   echo "ERROR Too many candidates before filtering ($NUMBER_OF_DETECTED_TRANSIENTS)... Skipping SE run ($SEXTRACTOR_CONFIG_FILE)"
   echo "ERROR Too many candidates before filtering ($NUMBER_OF_DETECTED_TRANSIENTS)... Skipping SE run ($SEXTRACTOR_CONFIG_FILE)" >> transient_factory_test31.txt
   # this is for UCAC5 plate solver
   echo "wait"   >> transient_factory_test31.txt
   wait
   #
   #continue
   # The NUMBER_OF_DETECTED_TRANSIENTS limit may be reached at the first SE run,
   # In that case, we want to drop this run and continue with the second run hoping it will be better
  else
   if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt $NUMBER_OF_DETECTED_TRANSIENTS_BEFORE_FILTERING_SOFT_LIMIT ];then
    echo "ERROR Too many candidates before filtering ($NUMBER_OF_DETECTED_TRANSIENTS)... Dropping flares..."
    echo "ERROR Too many candidates before filtering ($NUMBER_OF_DETECTED_TRANSIENTS)... Dropping flares..." >> transient_factory_test31.txt
    # if yes, remove flares, keep only new objects
    while read -r FLAREOUTFILE A B ;do
     grep -v $FLAREOUTFILE candidates-transients.lst > candidates-transients.tmp
     mv candidates-transients.tmp candidates-transients.lst
    done < candidates-flares.lst
   fi

   echo "Waiting for UCAC5 plate solver" >> transient_factory_test31.txt  
   echo "Waiting for UCAC5 plate solver"
   # this is for UCAC5 plate solver
   echo "wait"   >> transient_factory_test31.txt
   wait
   echo "Preparing the HTML report for the field $FIELD with $SEXTRACTOR_CONFIG_FILE" >> transient_factory_test31.txt
   echo "Preparing the HTML report for the field $FIELD with $SEXTRACTOR_CONFIG_FILE"
   util/transients/make_report_in_HTML.sh >> transient_factory_test31.txt
   echo "Prepared the HTML report for the field $FIELD with $SEXTRACTOR_CONFIG_FILE" >> transient_factory_test31.txt
   echo "Prepared the HTML report for the field $FIELD with $SEXTRACTOR_CONFIG_FILE"
  fi # else if [ $NUMBER_OF_DETECTED_TRANSIENTS -gt 500 ];then
  
  echo "*------ done with $SEXTRACTOR_CONFIG_FILE ------*" >> transient_factory_test31.txt
  echo "*------ done with $SEXTRACTOR_CONFIG_FILE ------*"

  # Update the local exclusion list (but actually util/transients/report_transient.sh is supposed to take care of that already)
  echo "Updating exclusion_list_local.txt" >> transient_factory_test31.txt
  echo "Updating exclusion_list_local.txt"
  grep -A1 'Mean magnitude and position on the discovery images:' transient_report/index.html | grep -v 'Mean magnitude and position on the discovery images:' | awk '{print $6" "$7}' | sed '/^\s*$/d' >> exclusion_list_local.txt
  echo "#### The local exclusion list is exclusion_list_local.txt ####" >> transient_factory_test31.txt
  cat exclusion_list_local.txt >> transient_factory_test31.txt
  #
  
 done # for SEXTRACTOR_CONFIG_FILE in default.sex.telephoto_lens_onlybrightstars_v1 default.sex.telephoto_lens_v4 ;do

 # We need a local exclusion list not to find the same things in multiple SExtractor runs
 if [ -f exclusion_list_local.txt ];then
  rm -f exclusion_list_local.txt
 fi
 
 echo "########### Completed $FIELD ###########" >> transient_factory_test31.txt
 
done # for i in "$NEW_IMAGES"/ ...

done # for NEW_IMAGES in $@ ;do




## Automatically update the exclusion list if we are on a production server
HOST=$(hostname)
echo "The analysis was running at $HOST" >> transient_factory_test31.txt
# remove restrictions on host for exclusion list update
#if [ "$HOST" = "scan" ] || [ "$HOST" = "vast" ] || [ "$HOST" = "eridan" ];then
 echo "We are allowed to update the exclusion list at $HOST host" >> transient_factory_test31.txt
 IS_THIS_TEST_RUN="NO"
 # if we are not in the test directory
 echo "$PWD" "$@" | grep --quiet -e 'vast_test' -e 'saturn_test' -e 'test' -e 'Test' -e 'TEST'
 if [ $? -eq 0 ] ;then
  IS_THIS_TEST_RUN="YES"
  echo "The names $PWD $string_command_line_argumants suggest this is a test run"
  echo "The names $PWD $string_command_line_argumants suggest this is a test run" >> transient_factory_test31.txt
 fi
 echo "$1" | grep --quiet -e 'NMW_Vul2_magnitude_calibration_exit_code_test' -e 'NMW_Sgr9_crash_test'
 if [ $? -eq 0 ] ;then
  IS_THIS_TEST_RUN="NO"
  echo "Allowing the exclusion list update for $1"
  echo "Allowing the exclusion list update for $1" >> transient_factory_test31.txt
 fi
 ALLOW_EXCLUSION_LIST_UPDATE="YES"
 if [ "$IS_THIS_TEST_RUN" != "YES" ];then
  # the NMW_Vul2_magnitude_calibration_exit_code_test tests for exclusion listupdate
  # and ../NMW_Sgr9_crash_test/second_epoch_images is for that purpose too
  echo "This does not look like a test run" >> transient_factory_test31.txt
  if [ -f "$EXCLUSION_LIST" ];then
   echo "Found $EXCLUSION_LIST" >> transient_factory_test31.txt
   grep -A1 'Mean magnitude and position on the discovery images:' transient_report/index.html | grep -v 'Mean magnitude and position on the discovery images:' | awk '{print $6" "$7}' | sed '/^\s*$/d' > exclusion_list_index_html.txt
   # Filter-out asteroids
   echo "#### The exclusion list before filtering-out asteroids, bad pixels and adding Gaia sources ####" >> transient_factory_test31.txt
   cat exclusion_list_index_html.txt >> transient_factory_test31.txt
   echo "###################################################################################" >> transient_factory_test31.txt
   while read -r RADECSTR ;do
    # The following line should match that in util/transients/report_transient.sh
    grep -A8 "$RADECSTR" transient_report/index.html | grep 'neverexclude_list.txt' | grep --quiet 'This object is listed in'
    if [ $? -eq 0 ];then
     echo "$RADECSTR  -- listed in neverexclude_list.txt (will NOT add it to exclusion list)" >> transient_factory_test31.txt
     continue
    fi
    # Mac OS X grep does not handle well the combination --max-count=1 -A8
    #grep --max-count=1 -A8 "$RADECSTR" transient_report/index.html | grep 'astcheck' | grep --quiet 'not found'
    grep -A8 "$RADECSTR" transient_report/index.html | grep 'astcheck' | grep --quiet 'not found'
    if [ $? -eq 0 ];then
     echo "$RADECSTR"
     echo "$RADECSTR  -- not an asteroid (will add it to exclusion list)" >> transient_factory_test31.txt
    else
     echo "$RADECSTR  -- asteroid (will NOT add it to exclusion list)" >> transient_factory_test31.txt
    fi
   done < exclusion_list_index_html.txt > exclusion_list_index_html.txt_noasteroids
   mv -v exclusion_list_index_html.txt_noasteroids exclusion_list_index_html.txt >> transient_factory_test31.txt
   #
   while read -r RADECSTR ;do
    grep -A8 "$RADECSTR" transient_report/index.html | grep 'galactic' | grep --quiet -e '<font color="red">0.0</font></b> pix' -e '<font color="red">0.1</font></b> pix' -e '<font color="red">0.2</font></b> pix'
    if [ $? -ne 0 ] || ( [[ ! -z "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" ]] &&
     [[ "$REQUIRE_PIX_SHIFT_BETWEEN_IMAGES_FOR_TRANSIENT_CANDIDATES" == "no" ]] ); then
     # assume there are no hot pixels in TICA TESS images
     echo "$RADECSTR"
     echo "$RADECSTR  -- does not seem to be a hot pixel (will add it to exclusion list)" >> transient_factory_test31.txt
    else
     echo "$RADECSTR  -- seems to be a hot pixel (will NOT add it to exclusion list)" >> transient_factory_test31.txt
    fi
   done < exclusion_list_index_html.txt > exclusion_list_index_html.txt_nohotpixels
   mv -v exclusion_list_index_html.txt_nohotpixels exclusion_list_index_html.txt >> transient_factory_test31.txt
   #
   echo "###################################################################################" >> transient_factory_test31.txt
   ALLOW_EXCLUSION_LIST_UPDATE="YES"
   N_CANDIDATES_EXCLUDING_ASTEROIDS_AND_HOT_PIXELS=$(cat exclusion_list_index_html.txt | wc -l)
   echo "$N_CANDIDATES_EXCLUDING_ASTEROIDS_AND_HOT_PIXELS candidates found (excluding asteroids and hot pixels)" >> transient_factory_test31.txt
   # Do this check only if we are processing a single field
   if [ -z "$2" ];then
    ### ===> ASSUMED MAX NUMBER OF CANDIDATES <===
    ### ===> FIELD NAME HARDCODED HERE <===
    # drop the limit no the number of candidates for the all-important Galactic Center field
    #if [ $N_CANDIDATES_EXCLUDING_ASTEROIDS_AND_HOT_PIXELS -gt 20 ] && [ "$FIELD" != "Sco6" ] ;then
    if [ $N_CANDIDATES_EXCLUDING_ASTEROIDS_AND_HOT_PIXELS -gt $MAX_NUMBER_OF_CANDIDATES_PER_FIELD ] && [ "$FIELD" != "Sco6" ] ;then
     echo "ERROR: too many candidates -- $N_CANDIDATES_EXCLUDING_ASTEROIDS_AND_HOT_PIXELS (excluding asteroids and hot pixels), not updating the exclusion list!"
     echo "ERROR: too many candidates -- $N_CANDIDATES_EXCLUDING_ASTEROIDS_AND_HOT_PIXELS (excluding asteroids and hot pixels), not updating the exclusion list!" >> transient_factory_test31.txt
     ALLOW_EXCLUSION_LIST_UPDATE="NO"
    fi
   fi
   echo "###################################################################################" >> transient_factory_test31.txt
   if [ "$ALLOW_EXCLUSION_LIST_UPDATE" = "YES" ];then
    #
    if [ -f exclusion_list_gaiadr2.txt ];then
     if [ -s exclusion_list_gaiadr2.txt ];then
      echo "Adding identified Gaia sources from exclusion_list_gaiadr2.txt" >> transient_factory_test31.txt
      cat exclusion_list_gaiadr2.txt >> exclusion_list_index_html.txt
     else
      echo "exclusion_list_gaiadr2.txt is empty - nothing to add to the exclusion list" >> transient_factory_test31.txt
     fi
     rm -f exclusion_list_gaiadr2.txt
    else
     echo "exclusion_list_gaiadr2.txt NOT FOUND" >> transient_factory_test31.txt
    fi
    #
    if [ -f exclusion_list_apass.txt ];then
     if [ -s exclusion_list_apass.txt ];then
      echo "Adding identified Gaia sources from exclusion_list_apass.txt" >> transient_factory_test31.txt
      cat exclusion_list_apass.txt >> exclusion_list_index_html.txt
     else
      echo "exclusion_list_apass.txt is empty - nothing to add to the exclusion list" >> transient_factory_test31.txt
     fi
     rm -f exclusion_list_apass.txt
    else
     echo "exclusion_list_apass.txt NOT FOUND" >> transient_factory_test31.txt
    fi
    #
    # Write to ../exclusion_list.txt in a single operation in a miserable attempt to minimize chances of a race condition
    if [ -f exclusion_list_index_html.txt ];then
     if [ -s exclusion_list_index_html.txt ];then
      echo "IS_THIS_TEST_RUN= $IS_THIS_TEST_RUN   ALLOW_EXCLUSION_LIST_UPDATE= $ALLOW_EXCLUSION_LIST_UPDATE
#### Adding the following to the exclusion list ####"
      cat exclusion_list_index_html.txt >> transient_factory_test31.txt
      echo "####################################################" >> transient_factory_test31.txt
      cat exclusion_list_index_html.txt >> "$EXCLUSION_LIST"
     else
      echo "IS_THIS_TEST_RUN=$IS_THIS_TEST_RUN  ALLOW_EXCLUSION_LIST_UPDATE= $ALLOW_EXCLUSION_LIST_UPDATE
#### Nothing to add to the exclusion list ####" >> transient_factory_test31.txt
     fi # if [ -s exclusion_list_index_html.txt ];then
     rm -f exclusion_list_index_html.txt
    else
     echo "IS_THIS_TEST_RUN=$IS_THIS_TEST_RUN  ALLOW_EXCLUSION_LIST_UPDATE= $ALLOW_EXCLUSION_LIST_UPDATE
exclusion_list_index_html.txt NOT FOUND" >> transient_factory_test31.txt
    fi # if [ -f exclusion_list_index_html.txt ];then
   else
    echo "Not allowed to update the exclusion list IS_THIS_TEST_RUN=$IS_THIS_TEST_RUN  ALLOW_EXCLUSION_LIST_UPDATE= $ALLOW_EXCLUSION_LIST_UPDATE" >> transient_factory_test31.txt
   fi # if [ "$ALLOW_EXCLUSION_LIST_UPDATE" = "YES" ];then
  else
   echo "No $EXCLUSION_LIST so we are not updating exclusion list IS_THIS_TEST_RUN=$IS_THIS_TEST_RUN  ALLOW_EXCLUSION_LIST_UPDATE= $ALLOW_EXCLUSION_LIST_UPDATE" >> transient_factory_test31.txt
  fi # if [ -f $EXCLUSION_LIST ];then
 else
  echo "This looks like a test run so we are not updating exclusion list  IS_THIS_TEST_RUN=$IS_THIS_TEST_RUN  ALLOW_EXCLUSION_LIST_UPDATE= $ALLOW_EXCLUSION_LIST_UPDATE" >> transient_factory_test31.txt
  echo "$PWD" | grep --quiet -e 'vast_test' -e 'saturn_test' -e 'test' -e 'Test' -e 'TEST' >> transient_factory_test31.txt
 fi # if [ "$IS_THIS_TEST_RUN" != "YES" ];then
#fi # host
## exclusion list update

###############################################################################################################
# Moved here as we run HORIZONS script in parallel to the main script
echo "############################################################
Planet positions from JPL HORIZONS for JD(UT)$JD_FIRSTIMAGE_FOR_PLANET_POSITIONS:"
cat planets.txt
echo "############################################################
Planet positions from JPL HORIZONS for JD(UT)$JD_FIRSTIMAGE_FOR_PLANET_POSITIONS:" >> transient_factory_test31.txt
cat planets.txt >> transient_factory_test31.txt
#
echo "############################################################
Positions of slected moons from JPL HORIZONS for JD(UT)$JD_FIRSTIMAGE_FOR_PLANET_POSITIONS:"
cat moons.txt
echo "############################################################
Positions of slected moons from JPL HORIZONS for JD(UT)$JD_FIRSTIMAGE_FOR_PLANET_POSITIONS:" >> transient_factory_test31.txt
cat moons.txt >> transient_factory_test31.txt
#
echo "############################################################
Positions of bright comets (listed at http://astro.vanbuitenen.nl/comets and http://aerith.net/comet/weekly/current.html ) from JPL HORIZONS for JD(UT)$JD_FIRSTIMAGE_FOR_PLANET_POSITIONS:"
cat comets.txt
echo "############################################################
Positions of bright comets (listed at http://astro.vanbuitenen.nl/comets and http://aerith.net/comet/weekly/current.html ) from JPL HORIZONS for JD(UT)$JD_FIRSTIMAGE_FOR_PLANET_POSITIONS:" >> transient_factory_test31.txt
cat comets.txt >> transient_factory_test31.txt
#
echo "############################################################
List of recent ASAS-SN transients:"
cat asassn_transients_list.txt
echo "############################################################
List of recent ASAS-SN transients:" >> transient_factory_test31.txt
cat asassn_transients_list.txt >> transient_factory_test31.txt
#
echo "############################################################
List of TOCP transients:"
cat tocp_transients_list.txt
echo "############################################################
List of TOCP transients:" >> transient_factory_test31.txt
cat tocp_transients_list.txt >> transient_factory_test31.txt
###############################################################################################################

## Finalize the HTML report
echo "<H2>Processig complete!</H2>" >> transient_report/index.html

TOTAL_NUMBER_OF_CANDIDATES=$(grep 'script' transient_report/index.html | grep -c 'printCandidateNameWithAbsLink')
echo "Total number of candidates identified: $TOTAL_NUMBER_OF_CANDIDATES" >> transient_report/index.html

echo "<H3>Processing log:</H3>
<pre>" >> transient_report/index.html
cat transient_factory.log >> transient_report/index.html
echo "</pre>" >> transient_report/index.html

echo "<H3>Filtering log:</H3>
<pre>" >> transient_report/index.html
cat transient_factory_test31.txt >> transient_report/index.html
echo "</pre>" >> transient_report/index.html

echo "</BODY></HTML>" >> transient_report/index.html

for FILE_TO_REMOVE in planets.txt comets.txt moons.txt asassn_transients_list.txt tocp_transients_list.txt ;do
 if [ -f "$FILE_TO_REMOVE" ];then
  rm -f "$FILE_TO_REMOVE"
 fi
done

# The uncleaned directory is needed for the test script!!!
#util/clean_data.sh

