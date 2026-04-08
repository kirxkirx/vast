#!/usr/bin/env bash
#
# This script will check if the external programs (mostly standard *nix tools) are present in the $PATH
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

MISSING_PROGRAM=0
LIST_OF_MISSING_PROGRAMS=""
echo " "
echo -e "Starting script \033[01;32m$0\033[00m"
# Check if C compiler name was supplied
if [ ! -z $1 ];then
 CC=$1
else
 CC=`lib/find_gcc_compiler.sh`
fi

FC=`lib/find_fortran_compiler.sh`
CXX=`lib/find_cpp_compiler.sh`


# Test if 'md5sum' is installed 
command -v md5sum &> /dev/null
if [ $? -eq 0 ];then
 # md5sum is the standard Linux tool to compute MD5 sums
 MD5COMMAND="md5sum"
else
 command -v md5 &> /dev/null
 if [ $? -eq 0 ];then
  # md5 is the standard BSD tool to compute MD5 sums
  MD5COMMAND="md5"
 else
  # None of the two is found, assuming the default
  MD5COMMAND="md5sum"
 fi
fi

# Test if the C compiler works at all
# do the following test only if we found the C compiler in order not to confuse the user if we have a bigger problem
command -v $CC &> /dev/null
if [ $? -eq 0 ];then
 echo "int main(){return 0;}" > test.c
 $CC -o test.exe test.c &>/dev/null
 if [ $? -ne 0 ];then
  if [ -f test.exe ];then
   rm -f test.exe
  else
   echo "ERROR: test.exe was not created by the C compiler $CC"
  fi
  rm -f test.c
  echo -e "
\033[01;31mThe development environment seems to be seriously broken!\033[00m"
  echo "The C compiler $CC "
  ls -l $CC
  echo "failed while producing a test executable file.

Please make sure you have a working GCC before compiling VaST."
  exit 1
 fi
 rm -f test.exe test.c
fi

# Test if we have some commonly used include files
C_HEADER_FILES=""
# do the following test only if we found the C compiler in order not to confuse the user if we have a bigger problem
command -v $CC &> /dev/null
if [ $? -eq 0 ];then
 for HEADER_FILE_TO_TEST in sys/types.h dirent.h ctype.h getopt.h libgen.h math.h stdio.h stdlib.h string.h strings.h unistd.h ;do
  echo "#include <$HEADER_FILE_TO_TEST>
int main(){return 0;}" > test.c
  $CC -o test.exe test.c &>/dev/null
  if [ $? -ne 0 ];then
   C_HEADER_FILES="$C_HEADER_FILES $HEADER_FILE_TO_TEST"
  fi
  rm -f test.exe test.c
 done
fi

if [ ! -z "$C_HEADER_FILES" ];then
 echo -e "
\033[01;31mThe development environment seems to be seriously broken!\033[00m
The C compiler $CC 
fails to locate the following (standard) header files:
$C_HEADER_FILES

Please fix this before compiling VaST."
 exit 1
fi


# Test if we have X11 include files
X11_DEVELOPEMENT_PACKAGE=""
X11_TEST_LOG_OUTPUT=""
# do the following test only if we found the C compiler in order not to confuse the user if we have a bigger problem
command -v $CC &> /dev/null
if [ $? -eq 0 ];then
 echo "#include <X11/Xos.h>
int main(){return 0;}" > test.c
 CUSTOM_X11_INCLUDE_AND_LIB=`lib/find_x11lib_include.sh`
 $CC -o test.exe test.c $CUSTOM_X11_INCLUDE_AND_LIB -lX11 &> .x11test.log
 if [ $? -ne 0 ];then
  SYSTEM_TYPE=$(uname)
  if [ "$SYSTEM_TYPE" = "Linux" ];then   
   # RedHat-style distributions tend to split headers into spearate -dev packages
   # Hope the users of normal Linux distributions will figure out the proper package name,
   # but we'll try to guess.
   # default - Ubuntu, Debian: libx11-dev
   X11_DEVELOPEMENT_PACKAGE="libx11-dev"
   # Mageia: libx11-devel
   command -v urpmi &> /dev/null
   if [ $? -eq 0 ];then
    X11_DEVELOPEMENT_PACKAGE="libx11-devel"
   fi
   # Arch Linux, Manjaro: libx11
   command -v pacman &> /dev/null
   if [ $? -eq 0 ];then
    X11_DEVELOPEMENT_PACKAGE="libx11"
   fi
   # openSUSE: libX11-devel
   command -v zypper &> /dev/null
   if [ $? -eq 0 ];then
    X11_DEVELOPEMENT_PACKAGE="libX11-devel"
   fi
   # Gentoo: x11-libs/libX11
   command -v emerge &> /dev/null
   if [ $? -eq 0 ];then
    X11_DEVELOPEMENT_PACKAGE="x11-libs/libX11"
   fi
   # AlmaLinux, CentOS, RHEL, Fedora: libX11-devel
   command -v dnf &> /dev/null
   if [ $? -eq 0 ];then
    X11_DEVELOPEMENT_PACKAGE="libX11-devel"
   fi
  else
   # If we are not even on Linux, do not confuse user with -dev in the suggested package name
   X11_DEVELOPEMENT_PACKAGE="libx11"
  fi
  X11_TEST_LOG_OUTPUT=`cat .x11test.log`
  X11_TEST_LOG_OUTPUT="$CC -o test.exe test.c $CUSTOM_X11_INCLUDE_AND_LIB -lX11 &> .x11test.log
$X11_TEST_LOG_OUTPUT"
 fi
 rm -f test.exe test.c
fi



for TESTED_PROGRAM in $CC $FC $CXX awk sed bc wc cat cut sort uniq touch head tail grep basename ping curl wget $(lib/find_timeout_command.sh) find readlink file $MD5COMMAND df du gzip gunzip mktemp tee tr $C_HEADER_FILES $X11_DEVELOPEMENT_PACKAGE ;do
 echo -n "Looking for $TESTED_PROGRAM - "
 if ! command -v $TESTED_PROGRAM &>/dev/null ;then
  MISSING_PROGRAM=1
  LIST_OF_MISSING_PROGRAMS="$LIST_OF_MISSING_PROGRAMS  $TESTED_PROGRAM"
  echo -e "\033[01;31mNOT found\033[00m"
 else
  echo -e "\033[01;32mFound\033[00m"
 fi
done


# Check for a web browser (not needed in CI environments like GitHub Actions)
if [ "$GITHUB_ACTIONS" != "true" ] && [ "$CI" != "true" ];then
 BROWSER_FOUND=0
 BROWSER_FOUND_NAME=""
 # Check the $BROWSER environment variable first
 if [ -n "$BROWSER" ];then
  if command -v "$BROWSER" &>/dev/null ;then
   BROWSER_FOUND=1
   BROWSER_FOUND_NAME="$BROWSER"
  fi
 fi
 # Check for actual browser binaries (not dispatchers like sensible-browser/xdg-open that may have no real browser behind them, and not curl)
 if [ $BROWSER_FOUND -eq 0 ];then
  for BROWSER_TO_TEST in firefox firefox-bin chromium chromium-browser google-chrome-stable google-chrome-unstable google-chrome-beta google-chrome chrome vivaldi-stable vivaldi brave-browser-stable brave-browser microsoft-edge-stable microsoft-edge opera midori epiphany-browser epiphany falkon konqueror torbrowser w3m links lynx ;do
   if command -v "$BROWSER_TO_TEST" &>/dev/null ;then
    BROWSER_FOUND=1
    BROWSER_FOUND_NAME="$BROWSER_TO_TEST"
    break
   fi
  done
 fi
 # On WSL, explorer.exe can open URLs in the default Windows browser
 if [ $BROWSER_FOUND -eq 0 ];then
  if grep -qi microsoft /proc/version 2>/dev/null ;then
   if command -v explorer.exe &>/dev/null ;then
    BROWSER_FOUND=1
    BROWSER_FOUND_NAME="explorer.exe (WSL)"
   fi
  fi
 fi
 # On macOS, check 'open' and application bundles
 if [ $BROWSER_FOUND -eq 0 ];then
  SYSTEM_TYPE=$(uname)
  if [ "$SYSTEM_TYPE" = "Darwin" ];then
   if command -v open &>/dev/null ;then
    BROWSER_FOUND=1
    BROWSER_FOUND_NAME="open"
   fi
  fi
 fi
 if [ $BROWSER_FOUND -eq 0 ];then
  echo -e "Looking for a web browser - \033[01;33mNOT found (optional - needed only at runtime to display transient search results)\033[00m"
 else
  echo -e "Looking for a web browser - \033[01;32mFound ($BROWSER_FOUND_NAME)\033[00m"
 fi
else
 echo "Skipping web browser check (running in CI)"
fi


if [ $MISSING_PROGRAM -eq 1 ] ;then
 echo -e "
ERROR: some external programs, packages or header files needed for VaST were not found.
Some of these programs may be installed, but missing from the the \$PATH=$PATH

\033[01;31mPlease install the following programs before compiling VaST:

$LIST_OF_MISSING_PROGRAMS\033[00m
"
  if [ ! -z "$X11_TEST_LOG_OUTPUT" ];then
    echo "Specifically, the test script failed to compile the test X11 program:
$X11_TEST_LOG_OUTPUT"
  fi
 exit 1
else
 echo "All the external programs were found!"
fi


# Check gcc\gfortran version match
lib/check_if_gcc_and_gfortran_versions_match.sh
if [ $? -ne 0 ];then
 echo "ERROR: version mismatch between gcc and gfortran"
 exit 1
fi

######### Apart from just checking external programs do some other useful actions #########

# Do this only if there are no data loaded, otherwise touch may be increadably slow if there are tens of thousands of files
for i in out*.dat ;do
 if [ -f "$i" ];then
  # found a lightcurve file, exit now
  exit 0
 fi
done

# Remove leftover test artifacts from previous test runs
if [ -d test_artifacts ];then
 rm -rf test_artifacts
fi

# Touch all files to circumvent the clock skew (often found in virtual machines after the stop-resume cycle)
# Exclude .git, test_artifacts, node_modules and other large directories not needed for the build.
# Use -exec + to batch files into fewer touch invocations instead of spawning one process per file.
find . -not -path './.git/*' -not -path './test_artifacts/*' -not -path './node_modules/*' -not -path './fastplot__*' -type f -exec touch {} + 2>/dev/null
find . -not -path './.git/*' -not -path './test_artifacts/*' -not -path './node_modules/*' -not -path './fastplot__*' -type d -exec touch {} + 2>/dev/null

