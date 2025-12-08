#!/usr/bin/env bash

# Script for uploading FITS images to https://bh-tom2.astrolabs.pl/about/

# Before uploading an image, you'll need to register a user, register your observatory and get an API token as described below:

# Get the token
#curl -X 'POST' 'https://bh-tom2.astrolabs.pl/api/token-auth/' -H 'accept: application/json' -H 'Content-Type: application/json' \
#  -H 'X-CSRFToken: uUz2fRnXhPuvD9YuuiDW9cD1LsajeaQnE4hwtEAfR00SgV9bD5HCe5i8n4m4KcOr' \
#  -d '{
#  "username": "username",
#  "password": "password"
#}'
# Set the environment variable containing the token
#export BHTOM_TOKEN="token_from_the_curl_output"
# Get your observatory name from https://bh-tom2.astrolabs.pl/observatory/
#export BHTOM_OBSERVATORY_NAME="SET_OBSERVATORY_NAME"

# Test or live run?
#DRY_RUN="False"
DRY_RUN="True"



# Check if correct number of arguments provided
if [ "$#" -ne 2 ]; then
 echo "Usage: $0 <target_name> <fits_file>"
 exit 1
fi


if [ -z "$BHTOM_TOKEN" ];then
 echo "ERROR: the environment variable BHTOM_TOKEN is not set!"
 exit 1
elif [ -z "$BHTOM_OBSERVATORY_NAME" ];then
 echo "ERROR: the environment variable BHTOM_OBSERVATORY_NAME is not set!"
 exit 1
elif [ "$BHTOM_OBSERVATORY_NAME" = "SET_OBSERVATORY_NAME" ];then
 echo "ERROR: you must set BHTOM_OBSERVATORY_NAME  see https://bh-tom2.astrolabs.pl/observatory/"
 exit 1
else
 echo "Found BHTOM_TOKEN and BHTOM_OBSERVATORY_NAME variables..."
fi


# Get arguments
TARGET_NAME="$1"
FITS_FILE="$2"
FILTER_NAME="GaiaSP/any"

# Check if FITS file exists
if [ ! -f "$FITS_FILE" ]; then
 echo "ERROR: File '$FITS_FILE' not found"
 exit 1
fi

# Set default values
FILTER_NAME="GaiaSP/any"
DATA_PRODUCT_TYPE="fits_file"

echo "Uploading $FITS_FILE for target $TARGET_NAME..."

# Make the curl request
curl -X POST \
    -H "Authorization: Token $BHTOM_TOKEN" \
    -F "target=$TARGET_NAME" \
    -F "filter=$FILTER_NAME" \
    -F "data_product_type=$DATA_PRODUCT_TYPE" \
    -F "dry_run=$DRY_RUN" \
    -F "observatory=$BHTOM_OBSERVATORY_NAME" \
    -F "files=@$FITS_FILE" \
    https://uploadsvc2.astrolabs.pl/upload/
if [ $? -ne 0 ];then
 echo "ERROR running curl!"
 exit 1
fi

echo ""
echo "Upload complete."
