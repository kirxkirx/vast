#!/usr/bin/env bash

# Restore cached SExtractor catalogs from the global cache directory.
# Called by ./vast after clean_data.sh and write_images_catalogs_logfile(),
# right before the fork() loop that runs SExtractor on each image.
#
# Reads the VAST_SEXTRACTOR_CACHE_DIR environment variable (the top-level
# cache directory). Computes the MD5 hash of default.sex to locate the
# matching cache subdirectory, then copies any cached .cat and .cat.aperture
# files into the working directory for images listed in vast_images_catalogs.log.
#
# This makes autodetect_aperture() find valid catalogs and skip SExtractor
# for those images.
#
# IMPORTANT: this cache uses basename(fits_image) as the cache key.
# It relies on FITS image filenames being unique across all cached fields.
# This holds for NMW because filenames contain timestamps
# (e.g. Gem03Q1b1x1_2025-12-18_22-15-52_001.fits).
#
# This script is a no-op if VAST_SEXTRACTOR_CACHE_DIR is not set — there is
# zero overhead for non-cache users.

# Exit silently if cache directory is not configured or does not exist
if [ -z "$VAST_SEXTRACTOR_CACHE_DIR" ] || [ ! -d "$VAST_SEXTRACTOR_CACHE_DIR" ]; then
 exit 0
fi

# Both files must exist at this point (called after write_images_catalogs_logfile)
if [ ! -f default.sex ] || [ ! -f vast_images_catalogs.log ]; then
 exit 0
fi

# Compute MD5 hash of default.sex to find the right cache subdirectory.
# Portable: Linux has md5sum, macOS/FreeBSD have md5 -r.
if command -v md5sum > /dev/null 2>&1 ; then
 CONFIG_HASH=$(md5sum default.sex | awk '{print $1}')
elif command -v md5 > /dev/null 2>&1 ; then
 CONFIG_HASH=$(md5 -r default.sex | awk '{print $1}')
else
 # No md5 tool available — cannot identify cache subdirectory
 exit 0
fi

if [ -z "$CONFIG_HASH" ]; then
 exit 0
fi

CACHE_SUBDIR="$VAST_SEXTRACTOR_CACHE_DIR/$CONFIG_HASH"
if [ ! -d "$CACHE_SUBDIR" ]; then
 exit 0
fi

# Read vast_images_catalogs.log and restore cached catalogs.
# Each line has the format: imageNNNNN.cat /path/to/fits_image.fits
while read -r CATALOG_NAME FITS_IMAGE_PATH ; do
 FITS_BASENAME=$(basename "$FITS_IMAGE_PATH")
 CACHED_CAT="$CACHE_SUBDIR/${FITS_BASENAME}.cat"
 CACHED_APR="$CACHE_SUBDIR/${FITS_BASENAME}.cat.aperture"
 if [ -f "$CACHED_CAT" ] && [ -f "$CACHED_APR" ]; then
  cp "$CACHED_CAT" "$CATALOG_NAME"
  cp "$CACHED_APR" "${CATALOG_NAME}.aperture"
  # Touch so mtime is newer than default.sex — this is what makes
  # find_catalog_in_vast_images_catalogs_log() skip SExtractor.
  touch "$CATALOG_NAME" "${CATALOG_NAME}.aperture"
  echo "SExtractor catalog cache: restored ${FITS_BASENAME} catalog from cache" >&2
 fi
done < vast_images_catalogs.log
