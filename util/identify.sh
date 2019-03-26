#!/usr/bin/env bash
#
# This script will conduct astrometric calibration of an image. It may also identify a star using this calibrated image.
#
# ERROR_STATUS indicates error conditions
# 0 - OK
# 1 - field not solved, no need to retry
# 2 - possible server communication error, retry with another plate solve server
ERROR_STATUS=0

# 0 - no, unknown telescope - have to plate-solve the image in the normal way
# 1 - yes, we trust WCS solution in images from this telescope
function check_if_we_know_the_telescope_and_can_blindly_trust_wcs_from_the_image {
 if [ -z "$1" ];then
  return 0
 fi
 FITS_IMAGE_TO_CHECK="$1"
 if [ -z "$VAST_PATH" ];then
  VAST_PATH=`readlink -f $0`
  VAST_PATH=`dirname "$VAST_PATH"`
  VAST_PATH="${VAST_PATH/'util/'/}"
  VAST_PATH="${VAST_PATH/'lib/'/}"
  VAST_PATH="${VAST_PATH/'examples/'/}"
  VAST_PATH="${VAST_PATH/util/}"
  VAST_PATH="${VAST_PATH/lib/}"
  VAST_PATH="${VAST_PATH/examples/}"
  VAST_PATH="${VAST_PATH//'//'/'/'}"
  # In case the above line didn't work
  VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
 fi
 # Check that VAST_PATH ends with '/'
 LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
 if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
  VAST_PATH="$VAST_PATH/"
 fi
 #
 FITS_IMAGE_TO_CHECK_HEADER=`"$VAST_PATH"util/listhead "$FITS_IMAGE_TO_CHECK"`
 # Check if it has WCS keywords
 for TYPICAL_WCS_KEYWORD in CTYPE1 CTYPE2 CRVAL1 CRVAL2 CRPIX1 CRPIX2 CD1_1 CD1_2 CD2_1 CD2_2 ;do
  echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep --quiet "$TYPICAL_WCS_KEYWORD"
  if [ $? -ne 0 ];then
   return 0
  fi
 done
 
 ### Some keywords identifying specific telescopes are to be added here in the future
 ### But for now...
 
 ### !!! Blindly trust WCS if it was created by Astrometry.net code !!! ###
 echo "$FITS_IMAGE_TO_CHECK_HEADER" | grep --quiet -e 'HISTORY Created by the Astrometry.net suite.' -e 'HISTORY WCS created by AIJ link to Astronomy.net website'
 if [ $? -eq 0 ];then
  return 1
 fi
 
 return 0
}


# Decide if we want to use local installation of Astrometry.net software or a remote one
#ASTROMETRYNET_LOCAL_OR_REMOTE="remote"
# Check the default Astrometry.net install location
if [ -d /usr/local/astrometry/bin ];then
 echo "$PATH" | grep --quiet '/usr/local/astrometry/bin'
 if [ $? -ne 0 ];then
  export PATH=$PATH:/usr/local/astrometry/bin
 fi
fi
# Check another default Astrometry.net install location
if [ -d /usr/share/astrometry/bin ];then
 echo "$PATH" | grep --quiet '/usr/share/astrometry/bin'
 if [ $? -ne 0 ];then
  export PATH=$PATH:/usr/share/astrometry/bin
 fi
fi

# if ASTROMETRYNET_LOCAL_OR_REMOTE was not set externally to the script
if [ -z "$ASTROMETRYNET_LOCAL_OR_REMOTE" ];then
 command -v solve-field &>/dev/null
 if [ $? -eq 0 ];then
  # Check that this is an executable file
  if [ -x `command -v solve-field` ];then
   echo "Using the local copy of Astrometry.net software..."
   ASTROMETRYNET_LOCAL_OR_REMOTE="local"
  else
   echo "WARNING: solve-field is found, but it is not an executable file!"
   echo "Using a remote server hosting Astrometry.net software..."
   ASTROMETRYNET_LOCAL_OR_REMOTE="remote"
  fi
 else
  echo "Using a remote server hosting Astrometry.net software..."
  ASTROMETRYNET_LOCAL_OR_REMOTE="remote"
 fi
else
 echo "environment variable set: ASTROMETRYNET_LOCAL_OR_REMOTE=$ASTROMETRYNET_LOCAL_OR_REMOTE"
fi


#### REMOVE BEFORE PRODUCTION: this is to debug the remote plate solve server access
#ASTROMETRYNET_LOCAL_OR_REMOTE="remote"
####

HOST_WE_ARE_RUNNING_AT=`hostname`

PLATE_SOLVE_SERVERS="scan.sai.msu.ru polaris.kirx.net vast.sai.msu.ru"

if [ "$ASTROMETRYNET_LOCAL_OR_REMOTE" = "remote" ];then

 # Check if we are requested to use a specific plate solve server
 if [ ! -z "$FORCE_PLATE_SOLVE_SERVER" ];then
  if [ "$FORCE_PLATE_SOLVE_SERVER" != "none" ];then
   echo "WARNING: using the user-specified plate solve server $FORCE_PLATE_SOLVE_SERVER"
   PLATE_SOLVE_SERVER="$FORCE_PLATE_SOLVE_SERVER"
   PLATE_SOLVE_SERVERS="$PLATE_SOLVE_SERVER"
  fi
 fi


 ###################################################
 echo -n "Checking if we can reach any plate solve servers... "
 # Decide on which plate solve server to use
 # first - set the initial list of servers
 rm -f server$$_*.ping_ok
 for i in $PLATE_SOLVE_SERVERS ;do
  # make sure we'll not remotely connect to ourselves
  if [ ! -z "$HOST_WE_ARE_RUNNING_AT" ];then
   echo "$i" | grep --quiet "$HOST_WE_ARE_RUNNING_AT"
   if [ $? -eq 0 ];then
    continue
   fi
  fi
  #
  ping -c1 -n "$i" &>/dev/null && echo "$i" > server$$_"$i".ping_ok &
  echo -n "$i "
 done

 wait
 ### The ping test will not work if we are behind a firewall that doesn't let ping out
 # If no servers could be reached, try to test for this possibility
 ########################################
 for SERVER_PING_OK_FILE in server$$_*.ping_ok ;do
  if [ -f $SERVER_PING_OK_FILE ];then
   # OK we could ping at least one server
   break
  fi
  # If we are still here, that means we are either offline or behind a firewall that doesn't let ping out
  for i in $PLATE_SOLVE_SERVERS ;do
   # make sure we'll not remotely connect to ourselves
   if [ ! -z "$HOST_WE_ARE_RUNNING_AT" ];then
    echo "$i" | grep --quiet "$HOST_WE_ARE_RUNNING_AT"
    if [ $? -eq 0 ];then
     continue
    fi
   fi
   #
   curl --max-time 10 --silent http://"$i"/astrometry_engine/files/ | grep --quiet 'Parent Directory' && echo "$i" > server$$_"$i".ping_ok &
   echo -n "$i "
  done
  wait
 done
 ########################################

 cat server$$_*.ping_ok > servers$$.ping_ok

 echo "
The reachable servers are:"
 cat servers$$.ping_ok

 if [ ! -s servers$$.ping_ok ];then
  echo "ERROR: no servers could be reached"
  exit 1
 fi

 # Choose a random server among the available ones
 PLATE_SOLVE_SERVER=`$("$VAST_PATH"lib/find_timeout_command.sh) 10  sort --random-sort --random-source=/dev/urandom servers$$.ping_ok | sort -R | head -n1`
 # If the above fails because sort doesn't understand the '--random-sort' option
 if [ "$PLATE_SOLVE_SERVER" = "" ];then
  PLATE_SOLVE_SERVER=`head -n1 servers$$.ping_ok`
 fi

 # Update the list of available servers
 PLATE_SOLVE_SERVERS=""
 while read SERVER ;do
  PLATE_SOLVE_SERVERS="$PLATE_SOLVE_SERVERS $SERVER"
 done < servers$$.ping_ok
 echo "Updated list of available servers: $PLATE_SOLVE_SERVERS"

 rm -f server$$_*.ping_ok servers$$.ping_ok

# Moved up
# # Check if we are requested to use a specific plate solve server
# if [ ! -z "$FORCE_PLATE_SOLVE_SERVER" ];then
#  if [ "$FORCE_PLATE_SOLVE_SERVER" != "none" ];then
#   echo "WARNING: using the user-specified plate solve server $FORCE_PLATE_SOLVE_SERVER"
#   PLATE_SOLVE_SERVER="$FORCE_PLATE_SOLVE_SERVER"
#   PLATE_SOLVE_SERVERS="$PLATE_SOLVE_SERVER"
#  fi
# fi

 if [ "$PLATE_SOLVE_SERVER" = "" ];then
  echo "Error choosing the plate solve server"
  exit 1
 fi
 ###################################################

 # Find curl
 CURL=`command -v curl`
 if [ $? -ne 0 ];then
  echo "ERROR: cannot find curl in PATH"
  exit 1
 else
  # Set max time for all network communications
  # note that this is ALSO acomplished by the timeout command before curl
  # AND at the server side
  #CURL="$CURL --max-time 299 "
  # Needed for POST queries to work with cURL
  CURL="$CURL --max-time 299 -H 'Expect:'"
 fi 

fi # if [ "$ASTROMETRYNET_LOCAL_OR_REMOTE" = "remote" ];then

VAST_PATH=`readlink -f $0`
VAST_PATH=`dirname "$VAST_PATH"`
VAST_PATH="${VAST_PATH/util/}"
VAST_PATH="${VAST_PATH/lib/}"
VAST_PATH="${VAST_PATH/'//'/'/'}"
export VAST_PATH
OLDDDIR_TO_CHECK_INPUT_FILE="$PWD"
cd "$VAST_PATH"

# Set SExtractor executable
SEXTRACTOR=sex
echo "$PATH" | grep --quiet "$VAST_PATH"lib/bin/
if [ $? -ne 0 ];then
 export PATH=$PATH:"$VAST_PATH"lib/bin/
fi

# Determine working mode: star identification or image WCS calibration
START_NAME=`basename $0`
if [ "$START_NAME" = "wcs_image_calibration.sh" ];then
 echo "Entering WCS image calibration mode."
 if [ -z "$1" ]; then
  echo "
Usage: $0 image.fit
 or
       $0 image.fit FIELD_OF_VIEW_IN_ARCMIN"
  exit 1
 fi
 FITSFILE="$1"
 if [ ! -f "$FITSFILE" ];then
  if [ -f "$OLDDDIR_TO_CHECK_INPUT_FILE"/"$FITSFILE" ];then
   FITSFILE="$OLDDDIR_TO_CHECK_INPUT_FILE/$FITSFILE"
  else
   echo "ERROR cannot find the input FITS image $FITSFILE"
   exit 1
  fi
 fi
 APP=6.0 
else
 echo "Entering star identification mode."
 if [ -z "$1" ]; then
  echo "
Usage: $0 outNUMBER.dat
 or
       $0 outNUMBER.dat FIELD_OF_VIEW_IN_ARCMIN"
  exit 1
 fi
 LIGHTCURVEFILE="$1"
 # Check if that file actually exists
 if [ ! -f "$LIGHTCURVEFILE" ];then
  if [ -f "$OLDDDIR_TO_CHECK_INPUT_FILE"/"$LIGHTCURVEFILE" ];then
   LIGHTCURVEFILE="$OLDDDIR_TO_CHECK_INPUT_FILE/$LIGHTCURVEFILE"
  else
   echo "ERROR: the lightcurve file $LIGHTCURVEFILE does not exist!"
   exit 1
  fi
 fi
 # Get the image name from the lightcurve file (first line, last column)
 echo -ne "reading light curve $LIGHTCURVEFILE - "
 read JD MAG MERR X Y APP FITSFILE REST < $LIGHTCURVEFILE && echo "ok"
 # TRAP!! If we whant to identify a flare, there will be no sence to search for an asteroid on the reference image.
 # Use the first discovery image instead!
 REFERENCE_IMAGE=`cat "$VAST_PATH"vast_summary.log |grep "Ref.  image:" | awk '{print $6}'`
 if [ "$START_NAME" = "identify_transient.sh" ];then
  while read JD MAG MERR X Y APP FITSFILE REST ;do
  if [ "$FITSFILE" != "$REFERENCE_IMAGE" ] ;then 
   break
  fi
  done < "$LIGHTCURVEFILE"
 fi
fi

# Check if FITSFILE variable is set correctly
if [ -z "$FITSFILE" ];then
 echo "ERROR: FITSFILE variable is not set while it is supposed to be set befor reaching this point in the script."
 exit 1
fi

# Check if the image actually exists
if [ ! -f "$FITSFILE" ];then
 echo "ERROR: cannot find the image file $FITSFILE"
 exit 1
fi
# Check if the image file is not empty
if [ ! -s "$FITSFILE" ];then
 echo "ERROR: the input image file $FITSFILE is empty"
 exit 1
fi
# Verify that the input file is a valid FITS file
"$VAST_PATH"lib/fitsverify -q -e "$FITSFILE"
if [ $? -ne 0 ];then
 echo "WARNING: the input file $FITSFILE seems to be a FITS image that does not fully comply with the FITS standard.
Checking if the filename extension and FITS header look reasonable..."
 ## Exampt from the rule for files that have at least some correct keywords
 echo "$FITSFILE" | grep  -e ".fits"  -e ".FITS"  -e ".fts" -e ".FTS"  -e ".fit"  -e ".FIT" && "$VAST_PATH"util/listhead "$FITSFILE" | grep -e "SIMPLE  =                    T" -e "TELESCOP= 'Aristarchos'" && "$VAST_PATH"util/listhead "$FITSFILE" | grep -e "NAXIS   =                    2" -e "TELESCOP= 'Aristarchos'"
 if [ $? -eq 0 ];then
  echo "OK, let's assume this is a valid FITS file"
 else
  echo "ERROR: the input image file $FITSFILE did not pass verification as a valid FITS file"
  exit 1
 fi
fi


# Test if the original image is already a calibrated one
# (Test by checking the file name)
TEST_SUBSTRING=`basename "$FITSFILE"`
TEST_SUBSTRING="${TEST_SUBSTRING:0:4}"
#TEST_SUBSTRING=`expr substr $TEST_SUBSTRING  1 4`
if [ "$TEST_SUBSTRING" = "wcs_" ];then
 cp -v "$FITSFILE" .
 WCS_IMAGE_NAME=`basename "$FITSFILE"`
else
 WCS_IMAGE_NAME=wcs_`basename "$FITSFILE"`
 # Test if the original image has a WCS header and we should just blindly trust it
 check_if_we_know_the_telescope_and_can_blindly_trust_wcs_from_the_image "$FITSFILE"
 if [ $? -eq 1 ];then
  echo "The input image has a WCS header - will blindly trust it is good..."
  cp -v "$FITSFILE" "$WCS_IMAGE_NAME" 
 fi
fi



SEXTRACTOR_CATALOG_NAME="$WCS_IMAGE_NAME".cat

# Check if vast_summary.log file is present
if [ ! -f "$VAST_PATH"vast_summary.log ];then
 echo "vast_summary.log not found! Creating a fake one..."
 # Note, we set default.sex.PHOTO instead of default.sex file because the situation when we have
 # a dataset reduced with an old version of vast which does not write the log file is more likely
 # to occur with photographic data
 #echo "SExtractor parameter file: default.sex.PHOTO " > vast_summary.log 
 # No, this was stupid! The data loading script will make sure the proper default.sex file is in the directory!
 echo "SExtractor parameter file: default.sex " > "$VAST_PATH"vast_summary.log 
fi


# Parse the command line arguments
if [ -z $2 ];then 
 #FIELD_OF_VIEW_ARCMIN=40
 #FIELD_OF_VIEW_ARCMIN=62
 #echo "Field of view was not set. Retreating to a default value $FIELD_OF_VIEW_ARCMIN'..."
 echo "Field of view for the image $FITSFILE was not set. Trying to guess..."
 FIELD_OF_VIEW_ARCMIN=`"$VAST_PATH"lib/try_to_guess_image_fov $FITSFILE`
 if [ -z "$FIELD_OF_VIEW_ARCMIN" ];then
  echo "ERROR guessing the field of view, assuming the default value"
  FIELD_OF_VIEW_ARCMIN=40
 else
  echo "The guess is $FIELD_OF_VIEW_ARCMIN arcmin."
 fi
 #TEST=`echo "$FIELD_OF_VIEW_ARCMIN<15.0"|bc -ql`
 #TEST=`echo "$FIELD_OF_VIEW_ARCMIN<3.0"|bc -ql`
 TEST=`echo "$FIELD_OF_VIEW_ARCMIN<1.0"|bc -ql`
 if [ $TEST -eq 1 ];then
  # If we know FIELD_OF_VIEW_ARCMIN is so small we have no hope to blindly solve it 
  # - try to rely on WCS information that may be already inserted in the image
  if [ ! -f $WCS_IMAGE_NAME ];then
   # Check if the file already contains a WCS-header
   echo $SEXTRACTOR -c `grep "SExtractor parameter file:" "$VAST_PATH"vast_summary.log |awk '{print $4}'` -PARAMETERS_NAME "$VAST_PATH"wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME -PHOT_APERTURES `"$VAST_PATH"lib/autodetect_aperture_main $FITSFILE 2>/dev/null` $FITSFILE 
   $SEXTRACTOR -c "$VAST_PATH"`grep "SExtractor parameter file:" "$VAST_PATH"vast_summary.log |awk '{print $4}'` -PARAMETERS_NAME "$VAST_PATH"wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME -PHOT_APERTURES `"$VAST_PATH"lib/autodetect_aperture_main $FITSFILE 2>/dev/null` $FITSFILE && echo "Using WCS information from the original image" >>/dev/stderr && cp $FITSFILE $WCS_IMAGE_NAME
   "$VAST_PATH"lib/correct_sextractor_wcs_catalog_using_xy2sky.sh "$WCS_IMAGE_NAME" "$SEXTRACTOR_CATALOG_NAME"
  fi
  
 fi # if [ $TEST -eq 1 ];then
else
 FIELD_OF_VIEW_ARCMIN=$2
fi

# Now the interesting part...

if [ ! -f "$WCS_IMAGE_NAME" ];then
 echo "No image with WCS calibration found."
 echo -n "Starting SExtractor...  "
 IMAGE_SIZE=`"$VAST_PATH"lib/astrometry/get_image_dimentions $FITSFILE | awk '{print "width="$2" -F hight="$4}'`
 # EXPERIMENTAL STUFF 
 CATALOG_NAME=`"$VAST_PATH"lib/fits2cat $FITSFILE`
 if [ -f "$CATALOG_NAME".apphot ];then
  CATALOG_NAME="$CATALOG_NAME".apphot
 fi
 "$VAST_PATH"lib/make_outxyls_for_astrometric_calibration "$CATALOG_NAME" out$$.xyls `"$VAST_PATH"lib/astrometry/get_image_dimentions $FITSFILE | awk '{print $2" "$4}'`
 if [ $? -ne 0 ];then
  echo "ERROR running $VAST_PATH""lib/make_outxyls_for_astrometric_calibration!"
  exit 1
 fi
 if [ ! -f out$$.xyls ];then
  echo "ERROR: out$$.xyls not found!"
  exit 1
 fi
 echo " 
This service uses tools provided by Astrometry.net.
For more information visit http://astrometry.net/ .

Please note, the automatic identification usually works fine with a large field 
of view (say, >40 arcmin). If the images are smaller than 20', the automatic 
field identification have good chances to fail. Sorry... :(
"

# Try to solve the image with a range of trial FIELD_OF_VIEW_ARCMINs

 #for TRIAL_FIELD_OF_VIEW_ARCMIN in $FIELD_OF_VIEW_ARCMIN `echo "3/4*$FIELD_OF_VIEW_ARCMIN" | bc -ql | awk '{printf "%.1f",$1}'` `echo "2*$FIELD_OF_VIEW_ARCMIN" | bc -ql | awk '{printf "%.1f",$1}'` `echo "10*$FIELD_OF_VIEW_ARCMIN" | bc -ql | awk '{printf "%.1f",$1}'` ;do
 for TRIAL_FIELD_OF_VIEW_ARCMIN in $FIELD_OF_VIEW_ARCMIN `echo "3*$FIELD_OF_VIEW_ARCMIN" | bc -ql | awk '{printf "%.1f",$1}'` `echo "3/4*$FIELD_OF_VIEW_ARCMIN" | bc -ql | awk '{printf "%.1f",$1}'` ;do
 
 echo "######### Trying to solve plate assuming $TRIAL_FIELD_OF_VIEW_ARCMIN' field of view #########"

 ############################################################################
 # Local plate-solving software
 if [ "$ASTROMETRYNET_LOCAL_OR_REMOTE" = "local" ];then
  IMAGE_SIZE=`"$VAST_PATH"lib/astrometry/get_image_dimentions $FITSFILE`
  SCALE_LOW=`echo "0.3*$TRIAL_FIELD_OF_VIEW_ARCMIN" | bc -ql | awk '{printf "%.1f",$1}'`
  # Yes, works fine with 1.2*$TRIAL_FIELD_OF_VIEW_ARCMIN but does not work with 1.0*$TRIAL_FIELD_OF_VIEW_ARCMIN
  #SCALE_HIGH=`echo "1.2*$TRIAL_FIELD_OF_VIEW_ARCMIN" | bc -ql`
  SCALE_HIGH=`echo "1.6*$TRIAL_FIELD_OF_VIEW_ARCMIN" | bc -ql | awk '{printf "%.1f",$1}'`
  #
  # Blind solve
  `"$VAST_PATH"lib/find_timeout_command.sh` 600 solve-field --objs 1000 --depth 10,20,30,40,50,60,70,80  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  # HACK Hack hack -- manually specify the field center and size
  # SOAR observations of ASASSN-19gt
  #`"$VAST_PATH"lib/find_timeout_command.sh` 600 solve-field --pixel-error 3 --ra 11:40:33.13 --dec -62:50:17.4 --radius 0.2   --objs 50 --depth 10,20,30,40,50,60,70,80  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  # SOAR observations of ASASSN-19cq
  #`"$VAST_PATH"lib/find_timeout_command.sh` 600 solve-field --ra 17:47:05.77 --dec -13:31:42.5 --radius 0.2   --objs 50 --depth 10,20,30,40,50,60,70,80  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  # RA tracking at MSU 2019-01-14
  #`"$VAST_PATH"lib/find_timeout_command.sh` 600 solve-field --ra 06:25:29.247 --dec -17:23:42.98 --radius 3.0   --objs 50 --depth 10,20,30,40,50,60,70,80  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  # ASASSN-17gs
  #`"$VAST_PATH"lib/find_timeout_command.sh` 600 solve-field  --ra 15:44:19.671 --dec -06:49:15.35 --radius 0.2  --objs 1000 --depth 10,20,30,40,50,60,70,80  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  # CSSJ0458
  #`"$VAST_PATH"lib/find_timeout_command.sh` 600 solve-field  --ra 04:58:39.6 --dec +35:05:43 --radius 0.2  --objs 1000 --depth 10,20,30,40,50,60,70,80  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  # Gaia16aye
  #`"$VAST_PATH"lib/find_timeout_command.sh` 600 solve-field  --ra 19:40:01.14 --dec +30:07:53.36 --radius 0.2  --objs 1000 --depth 10,20,30,40,50,60,70,80  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  # Gaia16bnz
  #`"$VAST_PATH"lib/find_timeout_command.sh` 600 solve-field  --ra 03:40:17.98 --dec +49:21:32.15 --radius 0.2  --objs 1000 --depth 10,20,30,40,50,60,70,80  --overwrite --no-plots --x-column X_IMAGE --y-column Y_IMAGE --sort-column FLUX_APER $IMAGE_SIZE --scale-units arcminwidth --scale-low $SCALE_LOW --scale-high $SCALE_HIGH out$$.xyls
  #
  # The if below doesn't work, dont know why
  #if [ $? -ge 130 ];then
  # # Exit if solve-field was killed by user
  # exit 1
  #fi
  if [ $? -ne 0 ];then
   echo "ERROR running solve-field locally. Retrying with a remote plate-solve server."
   ASTROMETRYNET_LOCAL_OR_REMOTE="remote"
   if [ "$PLATE_SOLVE_SERVER" = "" ];then
    # Not checking, just assuming this server is reachable
    PLATE_SOLVE_SERVER="scan.sai.msu.ru"
   fi
   CURL="curl"
   IMAGE_SIZE=`"$VAST_PATH"lib/astrometry/get_image_dimentions $FITSFILE | awk '{print "width="$2" -F hight="$4}'`

   #continue
   ##exit 1
  else
   # solve-field didn't crash
   if [ ! -f out$$.solved ];then
    echo "The field could not be sloved :("
    continue
    #exit 1
   fi
   if [ -f out$$.wcs ];then
    cp $FITSFILE `basename $FITSFILE`
    echo -n "Inserting WCS header...  "
    "$VAST_PATH"lib/astrometry/insert_wcs_header out$$.wcs `basename $FITSFILE`
    if [ $? -ne 0 ];then
     # This is a bad one, just exit
     echo " ERROR inserting WCS header! Aborting further actions! "
     exit 1
    else   
     ERROR_STATUS=0
     echo "The WCS header appears to be added with no errors."
    fi
    # clean up
    rm -f `basename $FITSFILE` out$$.wcs out$$.axy out$$.corr out$$.match out$$.rdls out$$.solved out$$.xyls out$$-indx.xyls
   else
    echo "ERROR: cannot find out$$.wcs "
    ERROR_STATUS=2
   fi
   # Clean-up
   #cp out*.xyls /tmp/
   #rm -f out*.axy out*.xyls
   rm -f out$$.axy out$$.xyls
   # end of clean-up
  fi # solve-field didn't crash
 fi # if [ "$ASTROMETRYNET_LOCAL_OR_REMOTE" = "local" ];then
 ############################################################################


 if [ "$ASTROMETRYNET_LOCAL_OR_REMOTE" = "remote" ];then
  # Web-based processing
  while true ;do
   #################### Check if we want to retry with another server ####################
   if [ $ERROR_STATUS -eq 2 ];then
    # Remove the current server from the list
    PLATE_SOLVE_SERVERS=${PLATE_SOLVE_SERVERS//$PLATE_SOLVE_SERVER/}
    # Pick the next server in line
    PLATE_SOLVE_SERVER=`echo $PLATE_SOLVE_SERVERS | awk '{print $1}'`
    # break if there are no more servers left
    if [ "$PLATE_SOLVE_SERVER" = "" ];then
     break
    fi
   fi
   #################### Start of single-server communication ####################
   echo -e "Submitting the plates solving job to the server \033[01;34m $PLATE_SOLVE_SERVER \033[00m"
   echo -e "This may take \033[01;31mup to a few minutes\033[00m..."
   if [ ! -f out$$.xyls ];then
    echo "ERROR: the file out$$.xyls is lost somewhere on the way!"
    exit 1
   fi
   #`lib/find_timeout_command.sh` 300 $CURL -F file=@out$$.xyls -F submit="Upload Image" -F fov=$TRIAL_FIELD_OF_VIEW_ARCMIN -F $IMAGE_SIZE "http://$PLATE_SOLVE_SERVER/cgi-bin/process_file/process_sextractor_list.py" --user vast48:khyzbaojMhztNkWd > server_reply$$.html
   #echo $CURL -F file=@out$$.xyls -F submit="Upload Image" -F fov=$TRIAL_FIELD_OF_VIEW_ARCMIN -F $IMAGE_SIZE "http://$PLATE_SOLVE_SERVER/cgi-bin/process_file/process_sextractor_list.py" --user vast48:khyzbaojMhztNkWd
   # Note that the timeout is also enforced at the server side
   `"$VAST_PATH"lib/find_timeout_command.sh` 300 $CURL -F file=@out$$.xyls -F submit="Upload Image" -F fov=$TRIAL_FIELD_OF_VIEW_ARCMIN -F $IMAGE_SIZE "http://$PLATE_SOLVE_SERVER/cgi-bin/process_file/process_sextractor_list.py" --user vast48:khyzbaojMhztNkWd > server_reply$$.html
   if [ $? -ne 0 ];then
    echo "An ERROR has occured while uploading the star list to the server!"
    ERROR_STATUS=2
    continue
   fi
   if [ ! -s server_reply$$.html ];then
    echo "ERROR: the server reply is empty!"
    ERROR_STATUS=2
    continue
   fi
   EXPECTED_WCS_HEAD_URL=`grep WCS_HEADER_FILE= server_reply$$.html |awk '{print $2}'`
   if [ "$EXPECTED_WCS_HEAD_URL" = "" ];then
    echo "ERROR: cannot parse the server reply!"
    echo "#### Server reply listing ####"
    cat server_reply$$.html
    echo "##############################"
    ERROR_STATUS=2
    continue
   fi
   echo "#### Plate solution log ####"
   SOLVE_PROGRAM_LOG_URL=${EXPECTED_WCS_HEAD_URL//out.wcs/program.log}
   `"$VAST_PATH"lib/find_timeout_command.sh` 300 $CURL "$SOLVE_PROGRAM_LOG_URL" --user vast48:khyzbaojMhztNkWd
   if [ $? != 0 ];then
    echo "ERROR: getting processing log from the server $PLATE_SOLVE_SERVER"
    ERROR_STATUS=2
    continue
   fi
   echo "############################"
   SOLVE_FILE_URL=${EXPECTED_WCS_HEAD_URL//out.wcs/out.solved}
   `"$VAST_PATH"lib/find_timeout_command.sh` 300 $CURL "$SOLVE_FILE_URL" --user vast48:khyzbaojMhztNkWd 2>/dev/null |grep "404 Not Found" >/dev/null
   # Nope, this interfers with the if statement below
   #if [ $? -ge 130 ];then
   # # Exit if the process is killed by user
   # exit 1
   #fi
   if [ $? -eq 1 ];then
    echo -e "Field \033[01;32mSOLVED\033[00m =)"
    rm -f out.solved
    echo -n "Downloading WCS header...  "
    `"$VAST_PATH"lib/find_timeout_command.sh` 300 $CURL "$EXPECTED_WCS_HEAD_URL" -o out$$.wcs --user vast48:khyzbaojMhztNkWd &>/dev/null  && echo "done"
    # This one should not interfere with the if below
    if [ $? -ge 130 ];then
     # Exit if the process is killed by user
     exit 1
    fi
    if [ -f out$$.wcs ];then
     cp $FITSFILE `basename $FITSFILE`
     echo -n "Inserting WCS header...  "
     "$VAST_PATH"lib/astrometry/insert_wcs_header out$$.wcs `basename $FITSFILE`
     if [ $? -ne 0 ];then
      # This is a bad one, just exit
      echo " ERROR inserting WCS header! Aborting further actions! "
      exit 1
     else
      ERROR_STATUS=0
      echo "The WCS header appears to be added with no errors."
     fi
     # The output plate-solved image wcs_`basename $FITSFILE` will be produced by lib/astrometry/insert_wcs_header
     for FILE_TO_REMOVE in `basename $FITSFILE` out$$.wcs ;do
      if [ -f "$FILE_TO_REMOVE" ];then
       rm -f "$FILE_TO_REMOVE"
      else
       echo "Hmmm, the file $FILE_TO_REMOVE that we wanted to remove does not exist!"
      fi
     done
    else
     echo "ERROR: cannot download out.wcs "
     ERROR_STATUS=2
     continue
    fi
   else
    echo -e "Sadly, the field was \033[01;31mNOT SOLVED\033[00m. :("
    echo "Try to set a smaller field of view size, for example:  $0 $1 " `echo "$TRIAL_FIELD_OF_VIEW_ARCMIN/2"|bc -ql`
    ERROR_STATUS=1
   fi
   # At this point we should remove the completed job from the server
   SERVER_JOB_ID=`grep "Job ID:" server_reply$$.html |head -n1 |awk '{print $3}'`
   if [ "$SERVER_JOB_ID" != "" ];then
    echo "Sending request to remove job $SERVER_JOB_ID from the server...  "
    VaSTID="XGkbtHTGfTPVLrZLBdtIDPzGAEAjaZWW"
    # Web-based processing - remove completed plate-solveing job from the server
    `"$VAST_PATH"lib/find_timeout_command.sh` 300 $CURL -F JobID="$SERVER_JOB_ID" -F VaSTID=$VaSTID "http://$PLATE_SOLVE_SERVER/cgi-bin/process_file/remove_job.py" --user vast48:khyzbaojMhztNkWd 
    if [ $? -ne 0 ];then
     echo "Hmm... Some error?"
    fi
   else
    echo "ERROR: cannot get Job ID from server_reply$$.html"
    cat server_reply$$.html
   fi
   rm -f server_reply$$.html #out$$.xyls
   #################### End of single-server communication ####################
   # Check exit conditions
   if [ $ERROR_STATUS -eq 0 ];then
    break
   fi
   if [ $ERROR_STATUS -eq 1 ];then
    break
   fi
   ############################################################################
  done
 fi # if [ "$ASTROMETRYNET_LOCAL_OR_REMOTE" = "remote" ];then
 
 
 # if the wcs-calibrated image is created one way or another...
 if [ -f $WCS_IMAGE_NAME ];then
  # Success
  break
 fi
 
 done # for TRIAL_FIELD_OF_VIEW_ARCMIN in ...

 ########## Special clean-up for multiple tries with a remote server
 if [ -f out$$.xyls ];then
  #cp out$$.xyls /tmp
  rm -f out$$.xyls
 fi

else
 echo "WCS calibrated image found: $WCS_IMAGE_NAME"
fi

# Check if the wcs-solved image could not be created
if [ ! -f "$WCS_IMAGE_NAME" ];then
 # Failure
 exit 1
fi

# Check if the wcs-solved image could not be created
if [ ! -s "$WCS_IMAGE_NAME" ];then
 # Failure
 echo "The output plate-solved image $WCS_IMAGE_NAME exist, but its empty!"
 exit 1
fi

# Check for errors on previous steps
if [ $ERROR_STATUS -ne 0 ];then
 echo "ERROR: $ERROR_STATUS"
 exit $ERROR_STATUS
fi

########## NEW: Check if PV keywords aare present in the plate-solved image header and if not - try to insert them ##########
"$VAST_PATH"util/listhead "$WCS_IMAGE_NAME" | grep --quiet -e 'PV1_1' -e 'PV2_1' -e 'PV1_2' -e 'PV2_2'
if [ $? -ne 0 ];then
 echo "Note that the $WCS_IMAGE_NAME plate-solved image header has no TPV-convention distortions in it..."
 # Check if the local copy of wcs-addpv.py is working (unlike hte rest of the VaST code it relies on python)
 "$VAST_PATH"lib/wcs-addpv.py -h &>/dev/null
 if [ $? -eq 0 ];then
  echo "Trying to insert TPV-convention distortions"
  "$VAST_PATH"lib/wcs-addpv.py "$WCS_IMAGE_NAME"
  if [ $? -ne 0 ];then
   echo "There was an error in lib/wcs-addpv.py while trying to insert the TPV keywords."
  fi
 else
  echo "Well, not much we can do..."
 fi 
fi
#############################################################################################################################


 # At this point, we should somehow have a WCS calibrated image named $WCS_IMAGE_NAME
 if [ ! -f "$SEXTRACTOR_CATALOG_NAME" ];then
  # Try to generate the catalog without re-running SExtractor
  "$VAST_PATH"lib/reformat_existing_sextractor_catalog_according_to_wcsparam.sh "$FITSFILE" "$WCS_IMAGE_NAME" "$SEXTRACTOR_CATALOG_NAME"
  if [ $? -ne 0 ];then
   echo "Starting SExtractor" >> /dev/stderr
   echo -ne "Starting SExtractor - "
   $SEXTRACTOR -c "$VAST_PATH"`grep "SExtractor parameter file:" "$VAST_PATH"vast_summary.log |awk '{print $4}'` -PARAMETERS_NAME "$VAST_PATH"wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME -PHOT_APERTURES `"$VAST_PATH"lib/autodetect_aperture_main $WCS_IMAGE_NAME 2>/dev/null` $WCS_IMAGE_NAME && echo "ok"
  fi
  echo "Catalog $SEXTRACTOR_CATALOG_NAME corresponding to the image $WCS_IMAGE_NAME created."
  "$VAST_PATH"lib/correct_sextractor_wcs_catalog_using_xy2sky.sh "$WCS_IMAGE_NAME" "$SEXTRACTOR_CATALOG_NAME"
 else
  echo "Catalog $SEXTRACTOR_CATALOG_NAME corresponding to the image $WCS_IMAGE_NAME found." 
  
  # Check if the catalog looks big enough
  TEST=`cat $SEXTRACTOR_CATALOG_NAME | wc -l`
  if [ $TEST -lt 100 ];then
   echo "The catalog seems suspiciously small (only $TEST lines), re-generating the catalog..."
   $SEXTRACTOR -c "$VAST_PATH"`grep "SExtractor parameter file:" "$VAST_PATH"vast_summary.log |awk '{print $4}'` -PARAMETERS_NAME "$VAST_PATH"wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME -PHOT_APERTURES `"$VAST_PATH"lib/autodetect_aperture_main $WCS_IMAGE_NAME 2>/dev/null` $WCS_IMAGE_NAME && echo "ok"
   if [ -f $SEXTRACTOR_CATALOG_NAME ];then
    echo "Catalog $SEXTRACTOR_CATALOG_NAME corresponding to the image $WCS_IMAGE_NAME created."
    "$VAST_PATH"lib/correct_sextractor_wcs_catalog_using_xy2sky.sh "$WCS_IMAGE_NAME" "$SEXTRACTOR_CATALOG_NAME"
   else
    echo "ERROR running SExtractor on $WCS_IMAGE_NAME to create catalog $SEXTRACTOR_CATALOG_NAME"
   fi
  fi
  
  # Checking the catalog format
  TEST=`head -n1 "$SEXTRACTOR_CATALOG_NAME" | awk '{print $6}'`
  if [ "$TEST" = "" ];then
   echo "The catalog is in the old format, re-generating the catalog..."
   $SEXTRACTOR -c "$VAST_PATH"`grep "SExtractor parameter file:" "$VAST_PATH"vast_summary.log |awk '{print $4}'` -PARAMETERS_NAME "$VAST_PATH"wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME -PHOT_APERTURES `"$VAST_PATH"lib/autodetect_aperture_main $WCS_IMAGE_NAME 2>/dev/null` $WCS_IMAGE_NAME && echo "ok"
   if [ -f "$SEXTRACTOR_CATALOG_NAME" ];then
    echo "Catalog $SEXTRACTOR_CATALOG_NAME corresponding to the image $WCS_IMAGE_NAME created."
    "$VAST_PATH"lib/correct_sextractor_wcs_catalog_using_xy2sky.sh "$WCS_IMAGE_NAME" "$SEXTRACTOR_CATALOG_NAME"
   else
    echo "ERROR running SExtractor on $WCS_IMAGE_NAME to create catalog $SEXTRACTOR_CATALOG_NAME"
   fi
  else
   echo "The catalog is in the new format, as expected."  
  fi
  
 fi
 #rm -f tmp$$.cat


# If we are in the star identification mode - identify the star!
if [ "$START_NAME" != "wcs_image_calibration.sh" ];then
 # Check if ucac5 plate solution is available
 UCAC5_SOLUTION_NAME="$SEXTRACTOR_CATALOG_NAME".ucac5
 if [ ! -f $UCAC5_SOLUTION_NAME ];then
  echo "Performing plate solution with UCAC5..."
  "$VAST_PATH"util/solve_plate_with_UCAC5 $WCS_IMAGE_NAME $FIELD_OF_VIEW_ARCMIN
  if [ $? -ne 0 ];then
   echo "ERROR matching the stars with UCAC5"
   exit 1
  fi
  if [ ! -f $UCAC5_SOLUTION_NAME ];then
   echo "ERROR: cannot find the UCAC5 plate solution file $UCAC5_SOLUTION_NAME"
   exit 1
  fi
 else
  echo "Found the UCAC5 plate solution file $UCAC5_SOLUTION_NAME"
 fi

 STARNUM=`basename $LIGHTCURVEFILE .dat`
 echo "Looking for a star near the position $X $Y (pix) in $UCAC5_SOLUTION_NAME ..."
  RADEC=`"$VAST_PATH"lib/find_star_in_wcs_catalog $X $Y < $UCAC5_SOLUTION_NAME`
  if [ $? -ne 0 ];then
   echo "ERROR searching for the target star in the WCS catalog $UCAC5_SOLUTION_NAME"
   exit 1
  fi
  echo " "
  echo "#########################################################################"
  echo "Star:   RA(J2000)   Dec(J2000)    X(pix)   Y(pix)   WCS_calibrated_image"
  ##################################################################################
  # Experimental feature: if you want to use spline correction for astrometry, uncomment
  # the following lines. The spline correction is useful for photographic plates
  # digitized using a flatbed scanner.
  ##################################################################################
  #RADEC_CORRECTED=`util/astrometric_correction.sh $SEXTRACTOR_CATALOG_NAME $RADEC`
  #RADEC=$RADEC_CORRECTED
  ##################################################################################
  #     00148  22:53:44.63 +16:09:08.1   283.894  280.149 wcs_3C454.3_R_20101127_0119.00027019.3C454.3.fts
  "$VAST_PATH"lib/deg2hms $RADEC &>/dev/null
  if [ $? -ne 0 ];then
   echo "ERROR parsing the coordinates string \"$RADEC\""
   exit 1
  fi
  echo ${STARNUM//out/" "} `"$VAST_PATH"lib/deg2hms $RADEC` $X $Y $WCS_IMAGE_NAME |awk '{printf "%s  %s %s  %8.3f %8.3f %s\n",$1,$2,$3,$4,$5,$6}'
  if [ "$START_NAME" = "identify_for_catalog.sh" ];then
   #rm -f tmp$$.cat
   exit 0
  fi
  echo " "
  if [ "$START_NAME" = "identify_transient.sh" ];then
   # This will stop util/search_databases_with_curl.sh from using terminal colors
   "$VAST_PATH"util/search_databases_with_curl.sh `"$VAST_PATH"lib/deg2hms $RADEC` H
   UNCALIBRATED_IMAGE_NAME=`echo ${WCS_IMAGE_NAME//"wcs_"/}`
   DATEANDTIME=`grep "$UNCALIBRATED_IMAGE_NAME" "$VAST_PATH"vast_image_details.log | head -n1 |awk '{print $2" "$3}'`
   "$VAST_PATH"util/transients/MPCheck.sh `"$VAST_PATH"lib/deg2hms $RADEC` $DATEANDTIME H
  else
   "$VAST_PATH"util/search_databases_with_curl.sh `"$VAST_PATH"lib/deg2hms $RADEC`
   ### Give user a chance to interrupt the script
   if [ $? -ne 0 ];then
    exit 1
   fi
   ###
   echo " "
   "$VAST_PATH"util/search_databases_with_vizquery.sh `"$VAST_PATH"lib/deg2hms $RADEC` ${STARNUM//out/" "} $FIELD_OF_VIEW_ARCMIN
   ###################################
   # If USNO-B1 identification failed, try to find this star on another image
   if [ $? -ne 0 ];then
    ####
    #if [ $? -ne 100 ];then
    # exit 1
    #fi
    ##
    echo -e "\n\nTrying to measure this star on another image... "
    tail -n1 "$LIGHTCURVEFILE" > lightcurve.tmp
    read JD MAG MERR X Y APP FITSFILE REST < lightcurve.tmp && echo "ok $FITSFILE"
    # Tesit if the original image is already a calibrated one
    TEST_SUBSTRING=`basename "$FITSFILE"`
    TEST_SUBSTRING="${TEST_SUBSTRING:0:4}"
    #TEST_SUBSTRING=`expr substr $TEST_SUBSTRING  1 4`
    if [ "$TEST_SUBSTRING" = "wcs_" ];then
     cp $FITSFILE .
     WCS_IMAGE_NAME=`basename "$FITSFILE"`
    else
     WCS_IMAGE_NAME=wcs_`basename "$FITSFILE"`
    fi
    SEXTRACTOR_CATALOG_NAME="$WCS_IMAGE_NAME".cat
    # Check if ucac5 plate solution is available
    UCAC5_SOLUTION_NAME="$SEXTRACTOR_CATALOG_NAME".ucac5
    if [ ! -f $UCAC5_SOLUTION_NAME ];then
     echo "Performing plate solution with UCAC5..."
     "$VAST_PATH"util/solve_plate_with_UCAC5 $FITSFILE $FIELD_OF_VIEW_ARCMIN
     ### Give user a chance to interrupt the script
     if [ $? -ne 0 ];then
      exit 1
     fi
     ###
    else
     echo "Found the UCAC5 plate solution file $UCAC5_SOLUTION_NAME"
    fi
    RADEC=`"$VAST_PATH"lib/find_star_in_wcs_catalog $X $Y < $UCAC5_SOLUTION_NAME`
    "$VAST_PATH"util/search_databases_with_curl.sh `"$VAST_PATH"lib/deg2hms $RADEC`
    ### Give user a chance to interrupt the script
    if [ $? -ne 0 ];then
     exit 1
    fi
    ###
    echo " "
    "$VAST_PATH"util/search_databases_with_vizquery.sh `"$VAST_PATH"lib/deg2hms $RADEC` ${STARNUM//out/" "}  $FIELD_OF_VIEW_ARCMIN
   fi 
   ###################################
  fi
  echo "#########################################################################"
  #rm -f tmp$$.cat 
 if [ "$START_NAME" = "identify.sh" ];then
  echo -e "The identified star is marked with the cross. Please compare the image with Aladin sky chart to make sure the identification is correct.\n"
  # Write Aladin script
  echo -n "rm all; load $WCS_IMAGE_NAME/;" `"$VAST_PATH"lib/deg2hms $RADEC`" ; zoom 5 arcmin ; stick ; get Aladin(POSSII J,JPEG)" `"$VAST_PATH"lib/deg2hms $RADEC`" ; get VizieR(USNO-B1)" `"$VAST_PATH"lib/deg2hms $RADEC`" 1'; get Simbad " `"$VAST_PATH"lib/deg2hms $RADEC`" 1'; get VizieR(2MASS)" `"$VAST_PATH"lib/deg2hms $RADEC`" 1' ;" > Aladin.script
  # If the star is matched with USNO-B1.0 - mark the USNO-B1.0 star in Aladin
  if [ -f search_databases_with_vizquery_USNOB_ID_OK.tmp ];then
   echo -n " draw green circle("`cat search_databases_with_vizquery_USNOB_ID_OK.tmp`" 2.5arcsec) ;" >> Aladin.script
  fi
  echo "" >> Aladin.script
  export PATH=$PATH:$HOME # Aladin is often saved in the home directory
  command -v Aladin &>/dev/null
  if [ $? -ne 0 ];then
   echo "Here is the Aladin script for you (copy it to Aladin console):"
   echo " "
   cat Aladin.script
   echo " "
   echo "Please note, that you may also put the Aladin executable and the Aladin.jar archive" 
   echo "into your home directory ( $HOME ) to let $0 start Aladin automatically."
  else
   echo "Aladin is starting..."
   if [ "$START_NAME" != "identify_noninteractive.sh" ];then
    Aladin < Aladin.script &>/dev/null &
   fi
  fi 
  echo " "
  if [ "$START_NAME" != "identify_noninteractive.sh" ];then
   "$VAST_PATH"pgfv $WCS_IMAGE_NAME $X $Y
  fi
 fi
fi

