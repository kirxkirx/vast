#!/usr/bin/env bash

#exit 0

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# This script will try to set a safe value of MAX_MEASUREMENTS_IN_RAM in src/vast_max_measurements_in_ram.h
# before compiling VaST

# default conservative values
PHYSMEM_BYTES=512000000
MAX_MEASUREMENTS_IN_RAM=12000

# try to get the RAM size BSD-style
command -v sysctl &>/dev/null
if [ $? -eq 0 ];then
 NEWMEM=$(sysctl hw.physmem | awk '{print $2}')
 if [ ! -z "$NEWMEM" ];then
  if [ $NEWMEM -gt 0 ];then
   PHYSMEM_BYTES="$NEWMEM"
  fi
 fi
fi

# try to get the RAM size Linux-style
command -v free &>/dev/null
if [ $? -eq 0 ];then
 NEWMEM=$(free -b | grep 'Mem' | awk '{print $2}')
 if [ ! -z "$NEWMEM" ];then
  if [ $NEWMEM -gt 0 ];then
   PHYSMEM_BYTES="$NEWMEM"
  fi
 fi
fi

# Based on how much RAM we have, set the maximum number of observations
if [ $PHYSMEM_BYTES -lt 1073741824 ];then
 MAX_MEASUREMENTS_IN_RAM=12000
elif [ $PHYSMEM_BYTES -lt 2147483648 ];then
 MAX_MEASUREMENTS_IN_RAM=24000
elif [ $PHYSMEM_BYTES -lt 4294967296 ];then
 MAX_MEASUREMENTS_IN_RAM=48000
elif [ $PHYSMEM_BYTES -lt 8589934592 ];then
 MAX_MEASUREMENTS_IN_RAM=96000
#elif [ $PHYSMEM_BYTES -lt 17179869184 ];then
# MAX_MEASUREMENTS_IN_RAM=192000
else
# MAX_MEASUREMENTS_IN_RAM=384000
 MAX_MEASUREMENTS_IN_RAM=192000
fi

# report the result
echo "This system seems to have $PHYSMEM_BYTES bytes of physical memory 
Setting MAX_MEASUREMENTS_IN_RAM=$MAX_MEASUREMENTS_IN_RAM in src/vast_max_measurements_in_ram.h"

if [ ! -s src/vast_max_measurements_in_ram.h ];then
 # If there is no such file - write a default one 
 echo "
// The following line is just to make sure this file is not included twice in the code
#ifndef VAST_MAX_MEASUREMENTS_IN_RAM_INCLUDE_FILE


#define MAX_MEASUREMENTS_IN_RAM 96000


// The macro below will tell the pre-processor that this header file is already included
#define VAST_MAX_MEASUREMENTS_IN_RAM_INCLUDE_FILE

#endif
// VAST_MAX_MEASUREMENTS_IN_RAM_INCLUDE_FILE
" > src/vast_max_measurements_in_ram.h
fi

N=$(grep -c '#define MAX_MEASUREMENTS_IN_RAM' src/vast_max_measurements_in_ram.h)

if [ $N -ne 1 ];then
 echo "ERROR in $0 '#define MAX_MEASUREMENTS_IN_RAM' appears in src/vast_max_measurements_in_ram.h more than one time!"
 grep '#define MAX_MEASUREMENTS_IN_RAM' src/vast_max_measurements_in_ram.h
 exit 1
fi

LINE_TO_REPLACE=$(grep '#define MAX_MEASUREMENTS_IN_RAM' src/vast_max_measurements_in_ram.h)
REPLACE_WITH="#define MAX_MEASUREMENTS_IN_RAM $MAX_MEASUREMENTS_IN_RAM  // set automatically at compile time based on PHYSMEM_BYTES=$PHYSMEM_BYTES by $0"

cat src/vast_max_measurements_in_ram.h | sed "s:$LINE_TO_REPLACE:$REPLACE_WITH:g" > src/vast_max_measurements_in_ram.tmp
mv src/vast_max_measurements_in_ram.tmp src/vast_max_measurements_in_ram.h

# Check the replacement
grep '#define MAX_MEASUREMENTS_IN_RAM' src/vast_max_measurements_in_ram.h
if [ $? -ne 0 ];then
 echo "OHOH, somehting went wrong in $0"
 exit 1
fi


