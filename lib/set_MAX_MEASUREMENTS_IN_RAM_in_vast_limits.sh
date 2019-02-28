#!/usr/bin/env bash

# This script will try to set a safe value of MAX_MEASUREMENTS_IN_RAM in src/vast_limits.h
# before compiling VaST

# default
PHYSMEM_BYTES=512000000
MAX_MEASUREMENTS_IN_RAM=12000

command -v sysctl &>/dev/null
if [ $? -eq 0 ];then
 NEWMEM=`sysctl hw.physmem | awk '{print $2}'`
 if [ ! -z "$NEWMEM" ];then
  if [ $NEWMEM -gt 0 ];then
   PHYSMEM_BYTES="$NEWMEM"
  fi
 fi
fi

command -v free &>/dev/null
if [ $? -eq 0 ];then
 NEWMEM=`free -b | grep 'Mem' | awk '{print $2}'`
 if [ ! -z "$NEWMEM" ];then
  if [ $NEWMEM -gt 0 ];then
   PHYSMEM_BYTES="$NEWMEM"
  fi
 fi
fi

if [ $PHYSMEM_BYTES -lt 1073741824 ];then
 MAX_MEASUREMENTS_IN_RAM=12000
elif [ $PHYSMEM_BYTES -lt 2147483648 ];then
 MAX_MEASUREMENTS_IN_RAM=24000
elif [ $PHYSMEM_BYTES -lt 4294967296 ];then
 MAX_MEASUREMENTS_IN_RAM=48000
elif [ $PHYSMEM_BYTES -lt 8589934592 ];then
 MAX_MEASUREMENTS_IN_RAM=96000
elif [ $PHYSMEM_BYTES -lt 17179869184 ];then
 MAX_MEASUREMENTS_IN_RAM=192000
else
 MAX_MEASUREMENTS_IN_RAM=384000
fi

echo "This system seems to have $PHYSMEM_BYTES bytes of physical memory 
Setting MAX_MEASUREMENTS_IN_RAM=$MAX_MEASUREMENTS_IN_RAM in src/vast_limits.h"

if [ ! -f src/vast_limits.h ];then
 echo "ERROR in $0 cannot find file src/vast_limits.h"
 exit 1
fi

N=`grep -c '#define MAX_MEASUREMENTS_IN_RAM' src/vast_limits.h`

if [ $N -ne 1 ];then
 echo "ERROR in $0 '#define MAX_MEASUREMENTS_IN_RAM' appears in src/vast_limits.h more than one time!"
 grep '#define MAX_MEASUREMENTS_IN_RAM' src/vast_limits.h
 exit 1
fi

LINE_TO_REPLACE=`grep '#define MAX_MEASUREMENTS_IN_RAM' src/vast_limits.h`
REPLACE_WITH="#define MAX_MEASUREMENTS_IN_RAM $MAX_MEASUREMENTS_IN_RAM  // PHYSMEM_BYTES=$PHYSMEM_BYTES"

cat src/vast_limits.h | sed "s:$LINE_TO_REPLACE:$REPLACE_WITH:g" > src/vast_limits.tmp
mv src/vast_limits.tmp src/vast_limits.h

# Check the replacement
grep '#define MAX_MEASUREMENTS_IN_RAM' src/vast_limits.h
if [ $? -ne 0 ];then
 echo "OHOH, somehting went wrong in $0"
 exit 1
fi


