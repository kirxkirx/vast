#!/usr/bin/env bash
#
# This script will compile The GNU Scientific Library (GSL) inside the VaST source tree.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# For compatibility with BSD Make:
# if the script is called by GNU Make MFLAGS="-w" will be set that confuses BSD Make.
export MAKEFLAGS=""
export MFLAGS=""
#

VAST_DIR=$PWD
TARGET_DIR=$VAST_DIR/lib
# Sextractor versions prior to sextractor-2.25.2 will not compile with gcc10
#LIBRARY_SOURCES="$VAST_DIR/src/sextractor-2.25.2_fix_disable_model_fitting $VAST_DIR/src/sextractor-2.25.0_fix_disable_model_fitting $VAST_DIR/src/sextractor-2.19.5"
#LIBRARY_SOURCES="$VAST_DIR/src/sextractor-2.25.2_fix_disable_model_fitting"
#LIBRARY_SOURCES="$VAST_DIR/src/sextractor-2.25.2_fix_disable_model_fitting $VAST_DIR/src/sextractor-2.19.5"
LIBRARY_SOURCES="$VAST_DIR/src/sextractor-2.25.2 $VAST_DIR/src/sextractor-2.19.5"

function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=`readlink -f "$1" 2>/dev/null`
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=`greadlink -f "$1" 2>/dev/null`
   if [ $? -ne 0 ];then
    REALPATH=`realpath "$1" 2>/dev/null`
    if [ $? -ne 0 ];then
     REALPATH=`grealpath "$1" 2>/dev/null`
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")"
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD"
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

#
#PATH_TO_THIS_SCRIPT=`readlink -f $0`
PATH_TO_THIS_SCRIPT=`vastrealpath $0`
PATH_TO_LIB_DIR=`dirname $PATH_TO_THIS_SCRIPT`
#
MARCH=`"$PATH_TO_LIB_DIR"/set_good_march.sh`
#CFLAGS="-O2 -Wno-error $MARCH"
# -fcommon is needed on Ubuntu 20.10 to compile SExtractor
CFLAGS="-O2 -Wno-error -fcommon $MARCH"
#

echo " "
echo -e "Starting script \033[01;32m$0 $1\033[00m"

# If we are asked to clean the source
if [ "$1" = "clean" ];then
 echo -e "\033[01;34mRemoving the local copy of SExtractor\033[00m"
 for LIBRARY_SOURCE in $LIBRARY_SOURCES ;do
  cd $LIBRARY_SOURCE
  make clean
 done
 if [ -f $TARGET_DIR/bin/sex ];then
  rm -f $TARGET_DIR/bin/sex
 fi
 echo "Script $0 is done."
 echo " "
 exit
fi

# Do nothing if there is a system-wide installation of SExtractor
command -v sex &>/dev/null
if [ $? -eq 0 ];then
 echo "Found a system-wide installation of SExtractor, will do nothing"
 exit
fi

# If there is a system-wide installation of SExtractor with the executable called by other names
for POSSIBLE_SEXTRACTOR_NAME in source-extractor sourceextractor sextractor ;do
 command -v $POSSIBLE_SEXTRACTOR_NAME &>/dev/null
 if [ $? -eq 0 ];then
  cd $TARGET_DIR/bin/
  ln -s `command -v $POSSIBLE_SEXTRACTOR_NAME` sex
  echo "Found a system-wide installation of SExtractor ($POSSIBLE_SEXTRACTOR_NAME), will link it"
  exit
 fi
done

# Set the right C compiler hoping SExtractor configuration process will pick it up
CC=`lib/find_gcc_compiler.sh`
export CC

# Alert user that we are going to compile things
echo -e "\033[01;34mCompiling the local copy of SExtractor\033[00m"
echo "Using C compiler: $CC"

# We maintain two versions of SExtractor
for LIBRARY_SOURCE in $LIBRARY_SOURCES ;do
 if [ ! -d "$LIBRARY_SOURCE" ];then
  continue
 fi
 echo "######### Compiling $LIBRARY_SOURCE #########"
 sleep 2
 cd "$LIBRARY_SOURCE"
 if [ -f Makefile ] || [ -f makefile ] ;then
  make clean
  make distclean
 fi
 
 CONFIGURE_OK=0

 # Try to circumvent the need for aclocal
 # https://stackoverflow.com/questions/33278928/how-to-overcome-aclocal-1-15-is-missing-on-your-system-warning
 # aclocal.m4
 #for FILE_TO_TOUCH in *.m4 configure Makefile.am Makefile.in autoconfig.h configure.ac config.h.in  autoconf autoconf/* autom4te.cache autom4te.cache/* debian debian/* doc doc/* m4 m4/* ;do
 for FILE_TO_TOUCH in *.m4 configure Makefile.in config.h.in  autoconf/*  autom4te.cache/*  debian/Makefile.in  doc/Makefile.in  m4/*  src/Makefile.in src/fits/Makefile.in src/levmar/Makefile.in src/wcs/Makefile.in  tests/Makefile.in ;do
  if [ -f $FILE_TO_TOUCH ];then
   touch $FILE_TO_TOUCH
  fi
 done
 
 if [ -x ./configure ];then
  # try to run configure right away if there is such script
  
  # --disable-model-fitting configure option turns-off model-fitting
  # features and allows compiling SExtractor without the ATLAS and FFTW libraries.
  ./configure --disable-model-fitting --prefix=$TARGET_DIR CFLAGS="$CFLAGS"
  if [ $? -eq 0 ];then
   CONFIGURE_OK=1
   echo "Configure phase went well"
  fi 
 fi # if [ -x ./configure ];then
 
 # for sextractor-2.25
 if [ -x ./autogen.sh ] && [ $CONFIGURE_OK -ne 1 ];then
  command -v autoconf &>/dev/null
  if [ $? -eq 0 ];then
   ./autogen.sh
   if [ $? -ne 0 ];then
    echo "ERROR running autogen.sh  -- make sure up-to-date autoconfautomake/libtool are installed"
    # continue to another SExtractor version
    continue
   fi # if [ $? -ne 0 ];then
   # --disable-model-fitting configure option turns-off model-fitting
   # features and allows compiling SExtractor without the ATLAS and FFTW libraries.
   ./configure --disable-model-fitting --prefix=$TARGET_DIR CFLAGS="$CFLAGS"
   if [ $? -eq 0 ];then
    CONFIGURE_OK=1
    echo "Configure phase went well"
   fi 
  else
   echo "ERROR no autoconf"
   # continue to another SExtractor version
   continue
  fi # if [ $? -eq 0 ];then
 fi # if [ -x ./autogen.sh ];then
 
 
 if [ $CONFIGURE_OK -ne 1 ];then
 
  echo "VaST code version/compiler version/compilation date:"
  for COMPILATION_INFO_FILE in .cc.build .cc.version .cc.date ;do
   if [ -f $COMPILATION_INFO_FILE ];then
    cat $COMPILATION_INFO_FILE
   fi
  done
 
  echo "
########### VaST installation problem ###########
Failed command:
./configure --disable-model-fitting --prefix=$TARGET_DIR CFLAGS="$CFLAGS"
at
$LIBRARY_SOURCE
C compiler: $CC

VaST installation problem: an error occurred while configuring SExtractor
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru> by e-mail or 
by creating GitHub issue at https://github.com/kirxkirx/vast

Thank you and sorry for the inconvenience."
  #exit 1
  continue
 fi
 make -j9
 if [ $? -ne 0 ];then

  echo "VaST code version/compiler version/compilation date:"
  for COMPILATION_INFO_FILE in .cc.build .cc.version .cc.date ;do
   if [ -f $COMPILATION_INFO_FILE ];then
    cat $COMPILATION_INFO_FILE
   fi
  done

  echo "
########### VaST installation problem ###########
Failed command:
make -j9
at
$LIBRARY_SOURCE
C compiler: $CC

VaST installation problem: an error occurred while compiling SExtractor
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru> by e-mail or 
by creating GitHub issue at https://github.com/kirxkirx/vast

Thank you and sorry for the inconvenience."
  #exit 1
  continue
 fi
 make install
 if [ $? -ne 0 ];then

  echo "VaST code version/compiler version/compilation date:"
  for COMPILATION_INFO_FILE in .cc.build .cc.version .cc.date ;do
   if [ -f $COMPILATION_INFO_FILE ];then
    cat $COMPILATION_INFO_FILE
   fi
  done
 
  echo "
########### VaST installation problem ###########
Failed command:
make install
at
$LIBRARY_SOURCE
C compiler: $CC

VaST installation problem: an error occurred while installing SExtractor
This should not have happened! Please report the problem (including the above error messages)
to the VaST developer Kirill Sokolovsky <kirx@scan.sai.msu.ru> by e-mail or 
by creating GitHub issue at https://github.com/kirxkirx/vast

Thank you and sorry for the inconvenience."
  #exit 1
  continue
 fi

 # Clean the source tree to save space
 make clean
 make distclean  

 cd $VAST_DIR

 # if we are here - assume the current SExtractor version compiled alright
 break

done # for LIBRARY_SOURCE in $LIBRARY_SOURCES ;do

# Test if executable files were actually created?
COMPILATION_ERROR=0
echo -n "Checking library files:   "
for TEST_FILE in $TARGET_DIR/bin/sex ;do
 echo -n "$TEST_FILE - "
 if [ ! -f $TEST_FILE ];then
  COMPILATION_ERROR=1
  echo -ne "\033[01;31mERROR\033[00m,   "
 else
  echo -ne "\033[01;32mOK\033[00m,   "
 fi
done

if [ $COMPILATION_ERROR -eq 1 ];then
 echo -e "\033[01;31mCOMPILATION ERROR\033[00m"
 exit 1
fi 

echo "done!"


echo -e "\033[01;34mFinished compiling SExtractor\033[00m"
echo " "
