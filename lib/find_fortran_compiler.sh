#!/usr/bin/env bash
#
# This script is used in Makefile
# It tries to find C, Fortran and C++ compilers
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Default guess
CC="gcc"
CXX="g++"
FC="gfortran"
RPATH_OPTION=""

######################################################################################
# 0 - yes, 1 - no
function check_if_the_input_file_is_a_working_C_compiler {
 if [ -z "$1" ];then
  return 1
 fi
 COMPILER_TO_TEST="$1"
 if [ ! -f "$COMPILER_TO_TEST" ];then
  return 1
 fi
 if [ ! -x "$COMPILER_TO_TEST" ];then
  return 1
 fi

 # Test without the header files
 echo "int main(){return 0;}" > test$$.c
 "$COMPILER_TO_TEST" -o test$$.exe test$$.c &>/dev/null
 if [ $? -ne 0 ];then
  for TESTFILE_TO_CLEAN in test$$.exe test$$.c ;do
   rm -f "$TESTFILE_TO_CLEAN"
  done
  return 1
 fi
 if [ ! -f test$$.exe ];then
  for TESTFILE_TO_CLEAN in test$$.exe test$$.c ;do
   rm -f "$TESTFILE_TO_CLEAN"
  done
  return 1
 fi
 if [ ! -x test$$.exe ];then
  for TESTFILE_TO_CLEAN in test$$.exe test$$.c ;do
   rm -f "$TESTFILE_TO_CLEAN"
  done
  return 1
 fi
 for TESTFILE_TO_CLEAN in test$$.exe test$$.c ;do
  rm -f "$TESTFILE_TO_CLEAN"
 done
 
 # Test with the header files
 for HEADER_FILE_TO_TEST in sys/types.h dirent.h ctype.h getopt.h libgen.h math.h stdio.h stdlib.h string.h strings.h unistd.h ;do
  echo "#include <$HEADER_FILE_TO_TEST>
int main(){return 0;}" > test$$.c
  "$COMPILER_TO_TEST" -o test$$.exe test$$.c &>/dev/null
  if [ $? -ne 0 ];then
   for TESTFILE_TO_CLEAN in test$$.exe test$$.c ;do
    rm -f "$TESTFILE_TO_CLEAN"
   done
   return 1
  fi
  if [ ! -f test$$.exe ];then
   for TESTFILE_TO_CLEAN in test$$.exe test$$.c ;do
    rm -f "$TESTFILE_TO_CLEAN"
   done
   return 1
  fi
  if [ ! -x test$$.exe ];then
   for TESTFILE_TO_CLEAN in test$$.exe test$$.c ;do
    rm -f "$TESTFILE_TO_CLEAN"
   done
   return 1
  fi
  for TESTFILE_TO_CLEAN in test$$.exe test$$.c ;do
   rm -f "$TESTFILE_TO_CLEAN"
  done
 done

 # If we are still here, than everything is fine
 for TESTFILE_TO_CLEAN in test$$.exe test$$.c ;do
  rm -f "$TESTFILE_TO_CLEAN"
 done
 return 0
}

######################################################################################

SCRIPT_NAME=$(basename $0)

command -v uname &> /dev/null
if [ $? -eq 0 ];then
 OS_TYPE=$(uname)
else
 OS_TYPE="unknown"
fi


#
# If we are not on Linux, we are likely to have crazy things like Clang posig as gcc
# or a gcc with no corresponding gfortran version. If a normal GCC is installed 
# on FreeBSD or Mac OS it is likely to be found in /usr/local/bin/ so let's check there
#
if [ "$OS_TYPE" != "Linux" ];then
 # some Macs have macports istalled under /usr while others under /opt
 for USR_OR_OPT in usr opt ;do
  # Special FreeBSD case
  LOCAL_GCC=$(ls /"$USR_OR_OPT"/local/bin/gcc?? 2>/dev/null | tail -n1)
  check_if_the_input_file_is_a_working_C_compiler "$LOCAL_GCC"
  if [ $? -ne 0 ];then
   LOCAL_GCC=""
  fi
  if [ "$LOCAL_GCC" = "" ];then
   LOCAL_GCC=$(ls /"$USR_OR_OPT"/local/bin/gcc-mp-* 2>/dev/null | tail -n1)
   check_if_the_input_file_is_a_working_C_compiler "$LOCAL_GCC"
   if [ $? -ne 0 ];then
    LOCAL_GCC=""
   fi
  fi
  if [ "$LOCAL_GCC" = "" ];then
   LOCAL_GCC=$(ls /"$USR_OR_OPT"/local/bin/gcc1[0-9] 2>/dev/null | tail -n1)
   check_if_the_input_file_is_a_working_C_compiler "$LOCAL_GCC"
   if [ $? -ne 0 ];then
    LOCAL_GCC=""
   fi
  fi
  if [ "$LOCAL_GCC" = "" ];then
   LOCAL_GCC=$(ls /"$USR_OR_OPT"/local/bin/gcc[4-9] 2>/dev/null | tail -n1)
   check_if_the_input_file_is_a_working_C_compiler "$LOCAL_GCC"
   if [ $? -ne 0 ];then
    LOCAL_GCC=""
   fi
  fi
  if [ "$LOCAL_GCC" = "" ];then
   LOCAL_GCC=$(ls /"$USR_OR_OPT"/local/bin/gcc-1[0-9] 2>/dev/null | tail -n1)
   check_if_the_input_file_is_a_working_C_compiler "$LOCAL_GCC"
   if [ $? -ne 0 ];then
    LOCAL_GCC=""
   fi
  fi
  if [ "$LOCAL_GCC" = "" ];then
   LOCAL_GCC=$(ls /"$USR_OR_OPT"/local/bin/gcc-[4-9] 2>/dev/null | tail -n1)
   check_if_the_input_file_is_a_working_C_compiler "$LOCAL_GCC"
   if [ $? -ne 0 ];then
    LOCAL_GCC=""
   fi
  fi
  # If no gcc?? there - try another name, likely to be on Mac
  if [ "$LOCAL_GCC" = "" ];then
   if [ -x /"$USR_OR_OPT"/local/bin/gcc ];then
    LOCAL_GCC="/$USR_OR_OPT/local/bin/gcc"
    check_if_the_input_file_is_a_working_C_compiler "$LOCAL_GCC"
    if [ $? -ne 0 ];then
     LOCAL_GCC=""
    fi
   fi
  fi
  if [ "$LOCAL_GCC" != "" ];then
   if [ -x "$LOCAL_GCC" ];then
    CC="$LOCAL_GCC"
    LOCAL_GFORTRAN=$(ls /"$USR_OR_OPT"/local/bin/gfortran?? 2>/dev/null | tail -n1)
    RPATH_OPTION=$(ls -d /"$USR_OR_OPT"/local/lib/gcc?? 2>/dev/null | tail -n1)
    if [ "$LOCAL_GFORTRAN" = "" ];then
     LOCAL_GFORTRAN=$(ls /"$USR_OR_OPT"/local/bin/gfortran-mp-* 2>/dev/null | tail -n1)
     RPATH_OPTION=$(ls -d /"$USR_OR_OPT"/local/lib/gcc-mp-* 2>/dev/null | tail -n1)
    fi
    if [ "$LOCAL_GFORTRAN" = "" ];then
     LOCAL_GFORTRAN=$(ls /"$USR_OR_OPT"/local/bin/gfortran1[0-9] 2>/dev/null | tail -n1)
     RPATH_OPTION=$(ls -d /"$USR_OR_OPT"/local/lib/gcc1[0-9] 2>/dev/null | tail -n1)
    fi
    if [ "$LOCAL_GFORTRAN" = "" ];then
     LOCAL_GFORTRAN=$(ls /"$USR_OR_OPT"/local/bin/gfortran[4-9] 2>/dev/null | tail -n1)
     RPATH_OPTION=$(ls -d /"$USR_OR_OPT"/local/lib/gcc[4-9] 2>/dev/null | tail -n1)
    fi
    if [ "$LOCAL_GFORTRAN" = "" ];then
     LOCAL_GFORTRAN=$(ls /"$USR_OR_OPT"/local/bin/gfortran-1[0-9] 2>/dev/null | tail -n1)
     RPATH_OPTION=$(ls -d /"$USR_OR_OPT"/local/lib/gcc-1[0-9] 2>/dev/null | tail -n1)
    fi
    if [ "$LOCAL_GFORTRAN" = "" ];then
     LOCAL_GFORTRAN=$(ls /"$USR_OR_OPT"/local/bin/gfortran-[4-9] 2>/dev/null | tail -n1)
     RPATH_OPTION=$(ls -d /"$USR_OR_OPT"/local/lib/gcc-[4-9] 2>/dev/null | tail -n1)
    fi
    if [ "$LOCAL_GFORTRAN" = "" ];then
     if [ -x /"$USR_OR_OPT"/local/bin/gfortran ];then
      LOCAL_GFORTRAN="/$USR_OR_OPT/local/bin/gfortran"
      RPATH_OPTION=$(ls -d /"$USR_OR_OPT"/local/lib/gcc* 2>/dev/null | tail -n1)
     fi
    fi
    if [ -x "$LOCAL_GFORTRAN" ];then
     FC="$LOCAL_GFORTRAN"
     if [ "$SCRIPT_NAME" = "find_gcc_compiler.sh" ];then
      echo "$CC"
      exit 0
     elif [ "$SCRIPT_NAME" = "find_rpath.sh" ];then
      if [ ! -z "$RPATH_OPTION" ];then
       if [ -d "$RPATH_OPTION" ];then 
        #echo "-rpath $RPATH_OPTION"
        echo "-Wl,-rpath,$RPATH_OPTION"
        exit 0
       fi
      fi
     elif [ "$SCRIPT_NAME" = "find_cpp_compiler.sh" ];then
      LOCAL_CXX=$(ls /"$USR_OR_OPT"/local/bin/g++?? 2>/dev/null | tail -n1)
      if [ "$LOCAL_CXX" = "" ];then
       LOCAL_CXX=$(ls /"$USR_OR_OPT"/local/bin/g++-mp-* 2>/dev/null | tail -n1)
      fi
      if [ "$LOCAL_CXX" = "" ];then
       LOCAL_CXX=$(ls /"$USR_OR_OPT"/local/bin/g++1[0-9] 2>/dev/null | tail -n1)
      fi
      if [ "$LOCAL_CXX" = "" ];then
       LOCAL_CXX=$(ls /"$USR_OR_OPT"/local/bin/g++[4-9] 2>/dev/null | tail -n1)
      fi
      if [ "$LOCAL_CXX" = "" ];then
       LOCAL_CXX=$(ls /"$USR_OR_OPT"/local/bin/g++-1[0-9] 2>/dev/null | tail -n1)
      fi
      if [ "$LOCAL_CXX" = "" ];then
       LOCAL_CXX=$(ls /"$USR_OR_OPT"/local/bin/g++-[4-9] 2>/dev/null | tail -n1)
      fi
      if [ -x "$LOCAL_CXX" ];then
       CXX="$LOCAL_CXX"
      elif [ -x /"$USR_OR_OPT"/local/bin/g++ ];then
       CXX="/$USR_OR_OPT/local/bin/g++"
      fi
      echo "$CXX"
     else
      echo "$FC"
     fi
     exit 0 # we are OK
    else
     # No local gfortran - don't use local gcc
     CC="gcc"
    fi # if [ -x "$LOCAL_GFORTRAN" ];then
   fi # if [ -x "$LOCAL_GCC" ];then
  fi # if [ "$LOCAL_GCC" != "" ];then
 done # for USR_OR_OPT in usr opt ;do
fi # if [ "$OS_TYPE" != "Linux" ];then

# General case
FC="gfortran"
GCC_MAJOR_VERSION=$($CC -dumpversion | cut -f1 -d.)
if [ $? -ne 0 ];then
 echo "ERROR in $0 -- failed to get the GCC version: non-zero exit code for '$CC -dumpversion | cut -f1 -d.'" 1>&2
fi
if [ ! -z "$GCC_MAJOR_VERSION" ];then
 if [ $GCC_MAJOR_VERSION -lt 4 ];then
  FC="g77"
 else
  FC="gfortran"
  # Do not perform gcc/g77 versions match check - it's too complex and who needs gcc-3.x anyway?
 fi
else
 echo "ERROR in $0 -- failed to get the GCC version: empty version string" 1>&2
fi

# Consistency check along the way:
if [ -z "$FC" ];then
 # This should not be happening
 echo "ERROR in $0 script: FC is not set" 1>&2
 FC="gfortran"
fi

# Check if there is a C compiler in the same dir as Fortran compiler
# - if there is - their versions most likely match
FORTRANBINDIR=$(command -v $FC)
if [ -n "$FORTRANBINDIR" ];then
 FORTRANBINDIR=$(dirname $FORTRANBINDIR)
 if [ -x $FORTRANBINDIR/gcc ];then
  CC="$FORTRANBINDIR/gcc"
 else
  # Don't get distracted by the gcc-ar gcc-ranlib gcc-nm executable that often accompany gcc
  LOCAL_GCC=$(ls $FORTRANBINDIR/gcc* 2>/dev/null | grep -v -e '-ar' -e '-ranlib' -e '-nm' | tail -n1)
  if [ "$LOCAL_GCC" != "" ];then
   CC="$LOCAL_GCC"
  fi
 fi
fi # if [ -n "$FORTRANBINDIR" ];then

# Report result
if [ "$SCRIPT_NAME" = "find_gcc_compiler.sh" ];then
 echo "$CC"
elif [ "$SCRIPT_NAME" = "find_cpp_compiler.sh" ];then
 echo "$CXX"
elif [ "$SCRIPT_NAME" = "find_rpath.sh" ];then
 echo "$RPATH_OPTION"
else
 echo "$FC"
fi
