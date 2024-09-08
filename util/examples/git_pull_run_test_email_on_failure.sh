#!/usr/bin/env bash

# This script is for automated VaST testing that can be run form a cron job.
# It will 'git pull' the latest version of VaST and if there is an update,
# the script will compile it and run the test reporting the results to the developer by e-mail.


#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# A more portable realpath wrapper
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
      cd "$(dirname "$1")" || exit 1
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit 1
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

# Function to remove the last occurrence of a directory from a path
remove_last_occurrence() {
    echo "$1" | awk -F/ -v dir=$2 '{
        found = 0;
        for (i=NF; i>0; i--) {
            if ($i == dir && found == 0) {
                found = 1;
                continue;
            }
            res = (i==NF ? $i : $i "/" res);
        }
        print res;
    }'
}

# Function to get full path to vast main directory from the script name
get_vast_path_ends_with_slash_from_this_script_name() {
 VAST_PATH=$(vastrealpath $0)
 VAST_PATH=$(dirname "$VAST_PATH")

 # Remove last occurrences of util, lib, examples
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "util")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "lib")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "examples")
 VAST_PATH=$(remove_last_occurrence "$VAST_PATH" "transients")

 # Make sure no '//' are left in the path (they look ugly)
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")

 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")

 # Check that VAST_PATH ends with '/'
 LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
 if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
  VAST_PATH="$VAST_PATH/"
 fi

 echo "$VAST_PATH"
}


command -v ps &> /dev/null
if [ $? -ne 0 ];then
 echo "ERROR: ps is not installed"
 exit 1
fi

command -v grep &> /dev/null
if [ $? -ne 0 ];then
 echo "ERROR: grep is not installed"
 exit 1
fi

# Check that no other instances of the script are running
N_RUN=`ps ax | grep combine_reports.sh | grep -v grep | grep bash | grep -c git_pull_run_test_email_on_failure.sh`
# This is conter-intuitive but the use of the construct N_RUN=`` will create a second copy of "bash ./git_pull_run_test_email_on_failure.sh" in the ps output
# So one running copy of the script corresponds to N_RUN=2
if [ $N_RUN -gt 2 ];then
# echo "ERROR: another instance of this script is already running"
 exit 0
fi

# Check that no other test_vast.sh is running (could have been started manually)
N_RUN=`ps ax | grep combine_reports.sh | grep -v grep | grep bash | grep -c test_vast.sh`
# So one running copy of the script corresponds to N_RUN=2
if [ $N_RUN -gt 1 ];then
# echo "ERROR: another instance of 'test_vast.sh' is already running"
 exit 0
fi

command -v git &> /dev/null
if [ $? -ne 0 ];then
 echo "ERROR: git is not installed"
 exit 1
fi

VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
export VAST_PATH
# Check if we are in the VaST root directory
if [ "$VAST_PATH" != "$PWD/" ];then
 echo "WARNING: we are currently at the wrong directory: $PWD while we should be at $VAST_PATH
Changing directory"
 cd "$VAST_PATH"
fi


# update VaST
#LANG=C git remote update &>/dev/null
#if [ $? -ne 0 ];then
# echo "ERROR: cannot run 'git remote update'"
# exit 1
#fi
#
## Does not work with old git that will not say 'Your branch is up to date with'
#LANG=C git status -uno 2>&1 | grep --quiet 'Your branch is up to date with'
#if [ $? -ne 0 ];then
## echo "We are up to date - no updates needed"
# exit 0
#fi

LANG=C git pull 2>&1 | grep --quiet 'Updating'
if [ $? -ne 0 ];then
# echo "ERROR: 'git pull' reports 'Already up to date.'"
 exit 0
fi

#LANG=C git pull 2>&1 | grep --quiet 'Already up to date.'
#if [ $? -eq 0 ];then
# echo "ERROR: 'git pull' reports 'Already up to date.'"
# exit 1
#fi

if [ -f make.log ];then
 rm -f make.log
fi

if [ -f vast_test_email_message.log ];then
 rm -f vast_test_email_message.log
fi

# compile VaST
make &> make.log
if [ $? -ne 0 ];then
 HOST=`hostname`
 HOST="@$HOST"
 NAME="$USER$HOST"
# DATETIME=`LANG=C date --utc`
# bsd dae doesn't know '--utc', but accepts '-u'
 DATETIME=`LANG=C date -u`
 SCRIPTNAME=`basename $0`
 LOG=`cat vast_test_report.txt`
 MSG="A make error occured while running $0 has finished on $DATETIME at $PWD $LOG $DEBUG_OUTPUT"
 echo "
$MSG
#########################################################
" > vast_test_email_message.log
 cat make.log >> vast_test_email_message.log
 echo "#########################################################" >> vast_test_email_message.log
 # send e-mail
 curl --silent 'http://scan.sai.msu.ru/vast/vasttestreport.php' --data-urlencode "name=$NAME running $SCRIPTNAME" --data-urlencode message@vast_test_email_message.log --data-urlencode 'submit=submit'
 # Failure is an option
 exit 0
fi

# if we are still here - run the VaST test
#touch ../THIS_IS_HPCC__email_only_on_failure
touch ../THIS_IS_HPCC
util/examples/test_vast.sh &>/dev/null
#rm -f ../THIS_IS_HPCC__email_only_on_failure
rm -f ../THIS_IS_HPCC
# it will take care of reporting results on failure



