#!/usr/bin/env bash
#
# This script will try to calibrate the current field using V magnitudes (transformed to Johnson, not vt)
# of Tycho-2 stars in the field. This is useful mostly for wide-field images with blue-sensitive CCD chips.
#
#########################################################
# SET APPROXIMAE FIELD OF VIEW IN ARCMINUTES HERE
#FIELD_OF_VIEW=120
# NOT NEEDED ANYMORE
#########################################################

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

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
      cd "$(dirname "$1")" || return
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || return
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

##### Check if a local copy of Tycho-2 is available and if its usable?
VASTDIR=$(vastrealpath "$PWD")
TYCHO_PATH=lib/catalogs/tycho2

# Check if there is a symbolic link, but it is broken
if [ -L "$TYCHO_PATH/tyc2.dat.00" ];then
 # test if symlink is broken (by seeing if it links to an existing file)
 if [ ! -e "$TYCHO_PATH/tyc2.dat.00" ] ; then
  # code if the symlink is broken
  echo "The symbolic link to Tycho-2 is broken!"
  rm -rf "$TYCHO_PATH"
 fi
fi

# Check if there is a copy of Tycho-2
if [ ! -f "$TYCHO_PATH/tyc2.dat.00" ];then
 echo "No local copy of Tycho-2 found (no $TYCHO_PATH/tyc2.dat.00)"
 # Check if there is a local copy of Tycho-2 in the top directory
 if [ -s ../tycho2/tyc2.dat.19 ];then
  echo "Found nonempty ../tycho2/tyc2.dat.19, creating symlink to $TYCHO_PATH"
  #ln -s `readlink -f ../tycho2` $TYCHO_PATH
  ln -s "$(vastrealpath ../tycho2)" "$TYCHO_PATH"
 else
  #
  echo "Tycho-2 catalog was not found at $TYCHO_PATH"
  echo "Would you like to download it now (it's big, ~160M)? (y/n)"
  read -r ANSWER
  if [ "$ANSWER" = "n" ];then
   echo "Well, maybe next time..."
   exit 1
  else
   if [ ! -d "$TYCHO_PATH" ];then
    mkdir "$TYCHO_PATH"
   fi
   cd "$TYCHO_PATH" || exit 1
   # remove any incomplete copy of Tycho-2
   for i in tyc2.dat.* ;do
    if [ -f "$i" ];then
     rm -f "$i"
    fi
   done
   #
   #wget -nH --cut-dirs=4 --no-parent -r -l0 -c -R 'guide.*,*.gif' "ftp://cdsarc.u-strasbg.fr/pub/cats/I/259/"
   wget -nH --cut-dirs=4 --no-parent -r -l0 -c -A 'ReadMe,*.gz,robots.txt' "http://scan.sai.msu.ru/~kirx/data/tycho2/"
   echo "Download complete. Unpacking..."
   for i in tyc2.dat.*gz ;do
    # handle a very special case: `basename $i .gz` is a broken symlink
    if [ -L "$(basename "$i" .gz)" ];then
     # if this is a symlink
     if [ ! -e "$(basename "$i" .gz)" ];then
      # if it is broken
      rm -f "$(basename "$i" .gz)"
      # remove that symlink
     fi
    fi
    #
    gunzip "$i"
   done
   cd "$VASTDIR" || exit 1
  fi
 fi # if [ -s ../tycho2/tyc2.dat.19 ];then 
else
 echo "Tycho-2 catalog is found at $TYCHO_PATH"
 # Make sure the catalog is fully downloaded and unpacked
 if [ ! -f "$TYCHO_PATH/tyc2.dat.19" ] ;then
  echo "WARNING! One of the catalog files was not found! Will attempt to re-download the catalog."
  cd "$TYCHO_PATH" || exit 1
  # remove any incomplete copy of Tycho-2
  for i in tyc2.dat.* ;do
   if [ -f "$i" ];then
    rm -f "$i"
   fi
  done
  #
  #wget -nH --cut-dirs=4 --no-parent -r -l0 -c -R 'guide.*,*.gif' "ftp://cdsarc.u-strasbg.fr/pub/cats/I/259/"
  wget -nH --cut-dirs=4 --no-parent -r -l0 -c -R 'guide.*,*.gif' "http://scan.sai.msu.ru/~kirx/data/tycho2/"
  echo "Download complete. Unpacking..."
  for i in tyc2.dat.*gz ;do
   # handle a very special case: `basename $i .gz` is a broken symlink
   if [ -L "$(basename "$i" .gz)" ];then
    # if this is a symlink
    if [ ! -e "$(basename "$i" .gz)" ];then
     # if it is broken
     rm -f "$(basename "$i" .gz)"
     # remove that symlink
    fi
   fi
   #
   gunzip "$i"
  done
  cd "$VASTDIR" || exit 1
 fi
fi

if [ ! -s lib/catalogs/list_of_bright_stars_from_tycho2.txt ];then
 # Create a list of stars brighter than mag 9.1 for filtering transient candidates
 # also in lib/update_offline_catalogs.sh !!!
 lib/catalogs/create_tycho2_list_of_bright_stars_to_exclude_from_transient_search 9.1
fi

echo "Tycho-2 catalog and the derived bright star exclusion list are ready"

# WCS-calibrate the reference image if it has not been done
REFERENCE_IMAGE=$(grep "Ref.  image:" vast_summary.log | awk '{print $6}')
TEST_SUBSTRING=$(basename "$REFERENCE_IMAGE")
TEST_SUBSTRING="${TEST_SUBSTRING:0:4}"
if [ "$TEST_SUBSTRING" = "wcs_" ];then
 cp "$REFERENCE_IMAGE" .
 WCS_CALIBRATED_REFERENCE_IMAGE=$(basename "$REFERENCE_IMAGE")
else
 WCS_CALIBRATED_REFERENCE_IMAGE=wcs_$(basename "$REFERENCE_IMAGE")
fi
SEXTRACTOR_CATALOG_NAME="$WCS_CALIBRATED_REFERENCE_IMAGE".cat
echo "Checking for the presence of non-empty $WCS_CALIBRATED_REFERENCE_IMAGE and $SEXTRACTOR_CATALOG_NAME "
if [ ! -s "$WCS_CALIBRATED_REFERENCE_IMAGE" ] || [ ! -s "$SEXTRACTOR_CATALOG_NAME" ] ;then
 util/wcs_image_calibration.sh "$REFERENCE_IMAGE"
 if [ $? -ne 0 ];then
  echo "ERROR in $0 : cannot plate-solve the reference image $REFERENCE_IMAGE"
  exit 1
 fi
else
 echo "Found non-empty $WCS_CALIBRATED_REFERENCE_IMAGE and $SEXTRACTOR_CATALOG_NAME"
fi # if [ ! -s "$WCS_CALIBRATED_REFERENCE_IMAGE" ] || [ ! -s "$SEXTRACTOR_CATALOG_NAME" ] ;then


# Final check for $WCS_CALIBRATED_REFERENCE_IMAGE and $SEXTRACTOR_CATALOG_NAME
if [ ! -s "$WCS_CALIBRATED_REFERENCE_IMAGE" ];then
 echo "ERROR in $0 : cannot find the WCS-calibrated image $WCS_CALIBRATED_REFERENCE_IMAGE which was supposed to be created by util/wcs_image_calibration.sh"
 exit 1
fi
if [ ! -s "$SEXTRACTOR_CATALOG_NAME" ];then
 echo "ERROR in $0 : cannot find the catalog file $SEXTRACTOR_CATALOG_NAME which was supposed to be created by util/wcs_image_calibration.sh"
 exit 1
fi

# If we are still here
echo "The reference image ($WCS_CALIBRATED_REFERENCE_IMAGE) and catalog ($SEXTRACTOR_CATALOG_NAME) found"

cp -v "$SEXTRACTOR_CATALOG_NAME" wcsmag.cat

#valgrind -v --tool=memcheck --leak-check=full  --show-reachable=yes --track-origins=yes lib/catalogs/read_tycho2
lib/catalogs/read_tycho2
if [ $? -ne 0 ];then
 echo "ERROR running lib/catalogs/read_tycho2"
 exit 1
fi
MAGNITUDE_CALIBRATION_PARAMETERS=$(lib/fit_zeropoint)
if [ $? -ne 0 ];then
 echo "ERROR fitting the magnitude scale with lib/fit_zeropoint"
 exit 1
fi
echo "util/calibrate_magnitude_scale $MAGNITUDE_CALIBRATION_PARAMETERS"
util/calibrate_magnitude_scale $MAGNITUDE_CALIBRATION_PARAMETERS
if [ $? -ne 0 ];then
 echo "ERROR: non-zero exit code of util/calibrate_magnitude_scale"
fi
echo "1.0 0.0 $MAGNITUDE_CALIBRATION_PARAMETERS" > calib.txt_param_tycho2

# Update the "Magnitude scale:" line in vast_summary.log
if [ -f vast_summary.log ];then
 # 'sed -i' works differently on MacOS
 #sed -i "s/Magnitude scale: instrumental/Magnitude scale: CV/" vast_summary.log
 sed 's/Magnitude scale: instrumental/Magnitude scale: CV/' vast_summary.log > vast_summary.log.tmp && mv vast_summary.log.tmp vast_summary.log
fi
