#!/usr/bin/env bash
#
# This shell script is needed to correctly compile pgplot-related programs on stupid Ubuntu where,
# for some strange reason, pgplot-related programs segfault if compiled directly using make...
#
# This script is intended to be started automatically from the Makefile
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

# Check if C compiler name was supplied
if [ ! -z $1 ];then
 CC=$1
else
 CC=`lib/find_gcc_compiler.sh`
fi
# Check if location of CFITSIO lib was specified
if [ ! -z $2 ];then
 CFITSIO_LIB=$2 
else
 if [ ! -f lib/libcfitsio.a ];then
  echo "ERROR in $0  -- cannot find lib/libcfitsio.a" 1>&2
  exit 1
 fi
 CFITSIO_LIB=lib/libcfitsio.a
fi
# Check if location of X11 libs were specified
if [ ! -z $3 ];then
 X11_LIB=$3 
else
 if [ -d /opt/X11/lib ];then
  X11_LIB=/opt/X11/lib
 elif [ -d /usr/X11/lib ];then
  X11_LIB=/usr/X11/lib
 else
  X11_LIB=/usr/X11R6/lib
 fi
fi

OPT_LOCAL_LIB=""
if [ -d /opt/local/lib ];then
 OPT_LOCAL_LIB="-L/opt/local/lib"
fi

# Test C compiler
command -v $CC &>/dev/null
if [ $? -ne 0 ];then
 echo "ERROR: cannot find C compler: $CC in PATH ($PATH)"
 exit 1
fi

FC=`lib/find_fortran_compiler.sh`

# Check if gcc and gfortan versions match (only if using gcc version >=4)
lib/check_if_gcc_and_gfortran_versions_match.sh
if [ $? -ne 0 ];then
 echo "ERROR: version mismatch between gcc and gfortran"
 exit 1
fi

## MOVED TO lib/check_if_gcc_and_gfortran_versions_match.sh
## Check if gcc and gfortan versions match (only if using gcc version >=4)
#GCC_MAJOR_VERSION=`$CC -dumpversion | cut -f1 -d.`
#if [ $GCC_MAJOR_VERSION -ge 4 ];then
# # Check if gcc and gfortan versions match
# FORTRAN_VERSION=`$FC -dumpversion`
# GCC_VERSION=`$CC -dumpversion`
# # Check if we can actually perform this check
# # (some versions of gfortran do not react properly on gfortran -dumpversion)
# if [ ${#FORTRAN_VERSION} -lt 10 ];then
#  if [ "$FORTRAN_VERSION" != "$GCC_VERSION" ];then                                              
#   echo "ERROR: version mismatch between the C ($CC) and FORTRAN (gfortran) compilers!
#$CC version $GCC_VERSION
#gfortran version $FORTRAN_VERSION
#Please re-install both gcc and gfortran to make sure they have the same version."
#   exit 1
#  fi
# else
#  echo "WARNING: cannot compare gcc and gfortran versions. Will continue assuming everything is fine." 
# fi # if [ ${#FORTRAN_VERSION} -lt 10 ];then
#fi

########### Try to guess a non-standard X11 libray path ###########
# First test if the above-specified path actually exist
LX11=`lib/find_x11lib_include.sh`
if [ -d "$X11_LIB" ];then
 LX11="$LX11 -L$X11_LIB"
 X11INCLUDEPATH=`dirname $X11_LIB`/include
 if [ -d `dirname $X11_LIB`/include ];then
  LX11="$LX11 -I$X11INCLUDEPATH"
 else
  X11INCLUDEPATH=""
 fi
fi
if [ ! -z "$LX11" ];then
 echo "Adding the following to include and library path: $LX11"
fi
###################################################################

# Test if we have X11 include files
echo -e "#include <X11/Xos.h>
int main(){return 0;}" > test.c
$CC -o test.exe test.c $LX11 -lX11 &>/dev/null
if [ $? -ne 0 ];then
 echo "
 
ERROR: cannot find X11 include files!
Please install libx11-dev developement package.
"
 exit 1
fi
rm -f test.exe test.c

########### Create cpgplot.h symlink ###########
cd src/
ln -s ../lib/pgplot/cpgplot.h cpgplot.h
cd -
# we need this link in two places
cd src/pgfv
ln -s ../../lib/pgplot/cpgplot.h cpgplot.h
cd -

########### Get info about libpng ###########
LIBPNG=`lib/test_libpng.sh`

########### Compile PGPLOT library ###########
cd lib/pgplot/
#make -j9
make
make cpg CFLAGS='-O2 -Wno-error'
make clean
cd -

########### Compile VaST programs that use PGPLOT lib. ###########

# Decide if we want to use a system-wide or a local copy of PGPLOT
COMPILATION_ERROR=0
echo -n "Checking compiled files:   "
for TEST_FILE in lib/pgplot/libpgplot.a lib/pgplot/libcpgplot.a lib/pgplot/grfont.dat ;do
 echo -n "$TEST_FILE - "
 if [ ! -f $TEST_FILE ];then
  COMPILATION_ERROR=1
  echo -ne "\033[01;31mERROR\033[00m,   "
 else
  echo -ne "\033[01;32mOK\033[00m,   "
 fi
done
echo "done!"

if [ $COMPILATION_ERROR -eq 1 ];then
 # Fallback to system-wide PGPLOT installation
 echo -e "\033[01;31mPGPLOT COMPILATION ERROR\033[00m"
 echo "
 
Trying to fall-back to a system-wide PGPLOT installation!..

"
 PGPLOT_LIBS="-lcpgplot -lpgplot $LX11 $OPT_LOCAL_LIB -lX11 -lgcc `lib/find_fortran_library.sh` $LIBPNG"
else
 # Use the local copy of PGPLOT
 PGPLOT_LIBS="lib/pgplot/libcpgplot.a lib/pgplot/libpgplot.a $LX11 -lX11 -lgcc `lib/find_fortran_library.sh` $LIBPNG"
fi

GSL_LIB="lib/lib/libgsl.a lib/lib/libgslcblas.a"
GSL_INCLUDE="lib/include"

echo " "
echo -e "Starting script \033[01;32m$0\033[00m"
echo -e "\033[01;34mCompiling PGPLOT-related components\033[00m"
echo "Using C compiler: $CC" 
echo "Assuming X11 libraries can be linked with $LX11"
echo "Libraries needed to compile C PGPLOT programs: $PGPLOT_LIBS"
echo "Compiler flags: " `cat optflags_for_scripts.tmp`

## -g -Wall -Warray-bounds -Wextra -fno-omit-frame-pointer -fstack-protector-all -O0 

# Make sure old versions of the files are gone
for FILE_TO_REMOVE in lc find_candidates pgfv lib/fit_mag_calib lib/fit_linear lib/fit_robust_linear lib/fit_zeropoint lib/fit_photocurve ;do
 if [ -f "$FILE_TO_REMOVE" ];then
  rm -f "$FILE_TO_REMOVE"
 fi
done

# Older GCC versions complain about isnormal() unless -std=c99 is given explicitly
"$CC" `cat optflags_for_scripts.tmp` -c src/lc.c -std=c99 -I$GSL_INCLUDE
"$CC" `cat optflags_for_scripts.tmp` -o lc setenv_local_pgplot.o lc.o variability_indexes.o get_path_to_vast.o wpolyfit.o -lm $CFITSIO_LIB $GSL_LIB $PGPLOT_LIBS  -Wall
# Older GCC versions complain about isnormal() unless -std=c99 is given explicitly
"$CC" `cat optflags_for_scripts.tmp` `lib/check_builtin_functions.sh` -c src/find_candidates.c -std=c99 -D_POSIX_C_SOURCE=199309L -I$GSL_INCLUDE
"$CC" `cat optflags_for_scripts.tmp` -o find_candidates setenv_local_pgplot.o find_candidates.o $PGPLOT_LIBS -lm
"$CC" `cat optflags_for_scripts.tmp` -c -o photocurve.o src/photocurve.c -I$GSL_INCLUDE -Wall
"$CC" `cat optflags_for_scripts.tmp` -c src/pgfv/pgfv.c -I$GSL_INCLUDE
"$CC" `cat optflags_for_scripts.tmp` -o pgfv pgfv.o setenv_local_pgplot.o photocurve.o gettime.o autodetect_aperture.o guess_saturation_limit.o get_number_of_cpu_cores.o exclude_region.o replace_file_with_symlink_if_filename_contains_white_spaces.o variability_indexes.o get_path_to_vast.o is_point_close_or_off_the_frame_edge.o $CFITSIO_LIB -lm $GSL_LIB -I$GSL_INCLUDE $PGPLOT_LIBS
"$CC" `cat optflags_for_scripts.tmp` -c -o fit_mag_calib.o src/fit_mag_calib.c -I$GSL_INCLUDE
"$CC" `cat optflags_for_scripts.tmp` -o lib/fit_mag_calib fit_mag_calib.o setenv_local_pgplot.o wpolyfit.o photocurve.o $PGPLOT_LIBS -lm $GSL_LIB -Wall -Wextra
cd lib/ ; ln -s fit_mag_calib fit_linear ; ln -s fit_mag_calib fit_robust_linear ; ln -s fit_mag_calib fit_zeropoint ; ln -s fit_mag_calib fit_photocurve ; ln -s ../pgfv select_comparison_stars ; cd ..

# Test if executable files were actually created?
COMPILATION_ERROR=0
echo -n "Checking compiled files:   "
#for TEST_FILE in lib/pgplot/libpgplot.a lib/pgplot/libcpgplot.a lib/pgplot/grfont.dat lc find_candidates pgfv lib/fit_mag_calib ;do
for TEST_FILE in lc find_candidates pgfv lib/fit_mag_calib lib/fit_linear lib/fit_robust_linear lib/fit_photocurve ;do
 echo -n "$TEST_FILE - "
 if [ ! -f $TEST_FILE ];then
  COMPILATION_ERROR=1
  echo -ne "\033[01;31mERROR\033[00m,   "
 else
  echo -ne "\033[01;32mOK\033[00m,   "
 fi
done
echo "done!"

if [ $COMPILATION_ERROR -eq 1 ];then
 echo -e "\033[01;31mCOMPILATION ERROR\033[00m"
 exit 1
fi

echo -e "\033[01;34mFinished compiling PGPLOT-related components\033[00m"
echo " "
