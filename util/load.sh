#!/usr/bin/env bash
#
# This small script will copy all content of the directory REGION_NAME (previously created bu util/save.sh script)
# to the current directory. Useful to load previously saved work to the VsST working directory.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

##########################################################################
# function definitions
function check_if_two_files_are_the_same {
 FILE1="$1"
 FILE2="$2"
 # Test if 'md5sum' is installed 
 command -v md5sum &> /dev/null
 if [ $? -eq 0 ];then
  # md5sum is the standard Linux tool to compute MD5 sums
  MD5COMMAND="md5sum"
 else
  command -v md5 &> /dev/null
  if [ $? -eq 0 ];then
   # md5 is the standard BSD tool to compute MD5 sums
   MD5COMMAND="md5 -q"
  else
   # None of the two is found
   MD5COMMAND="none"
  fi
 fi
 if [ "$MD5COMMAND" = "none" ];then
  echo "Cannot find the commands: md5sum or md5"
  echo "Assuming files $FILE1 and $FILE2 are different"
  return 0
 fi
 if [ ! -f "$FILE1" ];then
  return 0
 fi
 if [ ! -f "$FILE2" ];then
  return 0
 fi
 MD5SUM_OF_FILE1=`$MD5COMMAND $FILE1 | awk '{print $1}'`
 MD5SUM_OF_FILE2=`$MD5COMMAND $FILE2 | awk '{print $1}'`
 if [ "$MD5SUM_OF_FILE1" != "$MD5SUM_OF_FILE2" ];then
  echo "Files $FILE1 and $FILE2 are not identical"
  return 0
 fi
 return 1
}
##########################################################################

if [ ! -z $1 ];then
 REGION_NAME="$1"
else
 echo "Name of a region to load?"
 read REGION_NAME
fi

# In case it was an unsucessfull read
if [ -z "$REGION_NAME" ];then
 echo "You must specify the directory containing VaST lightcurve files (out*.dat)"
 exit 1
fi

# Remove trailing / from $REGION_NAME
LAST_CHAR_OF_REGION_NAME="${REGION_NAME: -1}"
if [ "$LAST_CHAR_OF_REGION_NAME" == "/" ];then
 REGION_NAME="${REGION_NAME%?}"
fi

# Test if the data directory exist at all
if [ ! -d "$REGION_NAME" ];then
 echo "ERROR: cannot find directory $REGION_NAME"
 if [ -f "$REGION_NAME" ];then
  echo "ERROR: $REGION_NAME is a file, not a directory."
 fi
 exit 1
fi   

echo "Checking if $REGION_NAME contains VaST lightcurve data ... "

# Test if the directory contains lightcurve files
for i in "$REGION_NAME"/out*.dat ;do
 # If there is not a sigle file with the proper (out*.dat) name - things are bad
 if [ ! -f $i ];then
  break
 fi
 #echo "DEBUG checking file $i"
 # If this is a non empty file
 if [ -s $i ];then
  #echo "DEBUG checking file $i nonempty"
  # That includes ASCII text
  file $i | grep "ASCII text" &>/dev/null
  if [ $? -eq 0 ];then
   #echo "DEBUG checking file $i nonempty contains ASCII text"
   # And this file is a readable lightcurve
   util/cute_lc $i &> /dev/null
   if [ $? -eq 0 ];then
    #echo "DEBUG checking file $i nonempty contains ASCII text passes cute_lc"
    # At least one readable lightcurve found
    echo "DIR_CONTAINS_AT_LEAST_ONE_GOOD_LIGHTCURVE_FILE"
    break
   fi
  fi
 fi
done | grep --quiet "DIR_CONTAINS_AT_LEAST_ONE_GOOD_LIGHTCURVE_FILE"
if [ $? -eq 0 ];then
 echo "The directory $REGION_NAME seems to contain VaST-formated lightcurve files ... "
else
 echo "ERROR: the directory $REGION_NAME does not contain VaST-formated lightcurve files"
 exit 1
fi

# Check if we have enough disk space to load the data
FREE_DISK_SPACE_MB=`df -l -P . | tail -n1 | awk '{printf "%.0f",$4/(1024)}'`
# If we managed to get the disk space info
if [ $? -eq 0 ];then
 SIZE_OF_DATA_TO_BE_LOADED_MB=`du -s "$REGION_NAME"/ | awk '{printf "%.0f",$1/1024}'`
 if [ $? -eq 0 ];then
  if [ $FREE_DISK_SPACE_MB -le $SIZE_OF_DATA_TO_BE_LOADED_MB ] && [ $SIZE_OF_DATA_TO_BE_LOADED_MB -ge 0 ] ;then
   echo "ERROR: not enough disk space to load  $REGION_NAME
the dataset size is $SIZE_OF_DATA_TO_BE_LOADED_MB MB while only $FREE_DISK_SPACE_MB MB is free on the current disk." >> /dev/stderr
   exit 1
  fi # if [ $FREE_DISK_SPACE_MB -le $SIZE_OF_DATA_TO_BE_LOADED_MB ];then
 fi # if [ $? -eq 0 ];then
fi # if [ $? -eq 0 ];then


# Remove old data from the current directory in order not to mix up two different data sets
util/clean_data.sh all 

echo "Loading data from $REGION_NAME ... "

#### Copy data - the new fast and insecure way ####
# Check if cp supports the -t option (it does not on BSD systems)
echo " " > "$REGION_NAME"/testfile
cp -t . "$REGION_NAME"/testfile
if [ $? -eq 0 ];then
 command -v find &>/dev/null
 if [ $? -eq 0 ];then
  echo "Trying to copy files the fast way using find"
  #find "$REGION_NAME" ! -name "$REGION_NAME" -exec cp -r -t . {} \+
  # The above command copies also the directory itself, something we don't want
  find "$REGION_NAME" ! -wholename "$REGION_NAME" -exec cp -r -t . {} \+
  if [ $? -eq 0 ];then
   # it worked! Exit the scrip
   echo "Done"
   exit 0
  else
   echo "Oh, find returned a non-zero exit code"
  fi
 fi
fi
rm -f "$REGION_NAME"/testfile
if [ -f testfile ];then
 rm -f testfile
fi

echo "Trying to copy files the old way using the for cycle"

#### Copy data - the old, slow and secure way ####
for i in "$REGION_NAME"/* ;do
 # do not copy edited files
 echo `basename $i` | grep "_edit.dat" &>/dev/null
 if [ $? -eq 0 ];then
  echo "skipping the edited lightcurve file $i "
  continue
 fi
 # do not copy the source code
 if [ "$i" = "$REGION_NAME/vast_src_$REGION_NAME" ];then
  continue
 fi
 ### interactive copy for some files
 if [ "$i" = "$REGION_NAME/default.sex.PHOTO" ];then
  check_if_two_files_are_the_same $i default.sex.PHOTO
  if [ $? -ne 1 ];then
   cp -i $i .
  fi
 elif [ "$i" = "$REGION_NAME/default.sex" ];then
  check_if_two_files_are_the_same $i default.sex
  if [ $? -ne 1 ];then
   cp -i $i .
  fi
 elif [ "$i" = "$REGION_NAME/default.psfex" ];then
  check_if_two_files_are_the_same $i default.psfex
  if [ $? -ne 1 ];then
   cp -i $i .
  fi
 elif [ "$i" = "$REGION_NAME/manually_selected_comparison_stars.lst" ];then
  check_if_two_files_are_the_same $i manually_selected_comparison_stars.lst
  if [ $? -ne 1 ];then
   cp -i $i .
  fi
 elif [ "$i" = "$REGION_NAME/exclude.lst" ];then
  check_if_two_files_are_the_same $i exclude.lst
  if [ $? -ne 1 ];then
   cp -i $i .
  fi
 elif [ "$i" = "$REGION_NAME/bad_region.lst" ];then
  check_if_two_files_are_the_same $i bad_region.lst
  if [ $? -ne 1 ];then
   cp -i $i .
  fi
 elif [ "$i" = "$REGION_NAME/vast_list_of_input_images_with_time_corrections.txt" ];then
  check_if_two_files_are_the_same $i vast_list_of_input_images_with_time_corrections.txt
  if [ $? -ne 1 ];then
   cp -i $i .
  fi
 elif [ "$i" = "$REGION_NAME/vast_list_of_FITS_keywords_to_record_in_lightcurves.txt" ];then
  check_if_two_files_are_the_same $i vast_list_of_FITS_keywords_to_record_in_lightcurves.txt
  if [ $? -ne 1 ];then
   cp -i $i .
  fi
 elif [ "$i" = "$REGION_NAME/default.conv" ];then
  check_if_two_files_are_the_same $i default.conv
  if [ $? -ne 1 ];then
   cp -i $i .
  fi
 elif [[ $i =~ .*conv.* ]];then
  check_if_two_files_are_the_same $i `basename $i`
  if [ $? -ne 1 ];then
   cp -i $i .
  fi
 elif [[ $i =~ .*_saved_limits.h.* ]];then
  # We don't want to copy back the VaST settings file
  continue
 elif [ "$i" = "$REGION_NAME/"`basename $REGION_NAME`_saved_limits.h ];then
  # An older version of the above
  # We don't want to copy back the VaST settings file
  continue
 else
  cp -r $i .
 fi
done && echo Done
