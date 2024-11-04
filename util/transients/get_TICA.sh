#!/usr/bin/env bash

function construct_url(){
 SECTOR=$1
 CAM=$2
 CCD=$3
 ORBIT=$4
 IMGNUMBER=$5
 CONSTRUCTED_URL="https://mast.stsci.edu/api/v0.1/Download/file/?uri=mast:HLSP/tica/s$SECTOR/cam$CAM-ccd$CCD/hlsp_tica_tess_ffi_s$SECTOR-o$ORBIT-$IMGNUMBER-cam$CAM-ccd${CCD}_tess_v01_img.fits"
 echo "$CONSTRUCTED_URL"
}

# expect something like https://kirx.net/ticaariel/uploads/20240208_morning_TICA_TESS_filtered.html#24396_s0075-o1a-cam1-ccd1__hlsp_tica_tess_ffi_s0075-o1-00912742-cam1-ccd1_tess_v01_img
INPUT_TRANSIENT_URL="$1"
#echo "Please input directory"
#read DIRECTORY

if [ -z "$INPUT_TRANSIENT_URL" ];then
 echo "Usgae:   $0 https://kirx.net/ticaariel/uploads/20240208_morning_TICA_TESS_filtered.html#24396_s0075-o1a-cam1-ccd1__hlsp_tica_tess_ffi_s0075-o1-00912742-cam1-ccd1_tess_v01_img"
 exit
fi

TRANSIENT_NAME=$(echo "$INPUT_TRANSIENT_URL" | awk -F'#' '{print $2}')
IMAGE_NAME=$(echo "$TRANSIENT_NAME" | awk -F'__' '{print $2".fits"}')

# example image URL
# https://mast.stsci.edu/api/v0.1/Download/file/?uri=mast:HLSP/tica/s0075/cam1-ccd1/hlsp_tica_tess_ffi_s0075-o2-00921309-cam1-ccd1_tess_v01_img.fits
SECTOR=$(echo "$IMAGE_NAME" | awk -F'_s' '{print $2}' | awk -F'-' '{print $1}')
#echo $SECTOR

CAM=$(echo "$IMAGE_NAME" | awk -F'-cam' '{print $2}' | awk -F'-' '{print $1}')
#echo $CAM

CCD=$(echo "$IMAGE_NAME" | awk -F'-ccd' '{print $2}' | awk -F'_' '{print $1}')
#echo $CCD

ORBIT=$(echo "$IMAGE_NAME" | awk -F'-o' '{print $2}' | awk -F'-' '{print $1}')
#echo $ORBIT

IMGNUMBER=$(echo "$IMAGE_NAME" | awk -F"-o$ORBIT-" '{print $2}' | awk -F'-' '{print $1}')
#echo $IMGNUMBER

DATA_DIR_NAME="data_$TRANSIENT_NAME"
if [ ! -d "$DATA_DIR_NAME" ];then
 mkdir "$DATA_DIR_NAME"
fi

cd "$DATA_DIR_NAME" || exit 1

NEM_IMGNUMBER=$(echo "$IMGNUMBER" | awk '{printf "%08d", $1-108}')
for COUNTER in $(seq 0 216) ;do
 NEM_IMGNUMBER=$(echo "$NEM_IMGNUMBER" | awk '{printf "%08d", $1+1}')
 CONSTRUCTED_URL=$(construct_url $SECTOR $CAM $CCD $ORBIT $NEM_IMGNUMBER)
 echo "Downloading image number $COUNTER  $CONSTRUCTED_URL"
 wget -O $(basename "$CONSTRUCTED_URL") "$CONSTRUCTED_URL"
done


