#!/usr/bin/env bash

# This script checks if all GitHub Actions tests are passing for the latest commit,
# and if so, pulls the latest version and runs make. Designed to run from cron.

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Configuration
GITHUB_REPO_OWNER="kirxkirx"
GITHUB_REPO_NAME="vast"

# Exit codes
EXIT_SUCCESS=0
EXIT_ALREADY_UPTODATE=0
EXIT_ERROR=1

#################################
# Helper functions
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

# Function to check if a command exists
command_exists() {
 command -v "$1" &> /dev/null
 return $?
}

#################################
# Pre-flight checks
#################################

# Check required commands
for cmd in git grep sed; do
 if ! command_exists "$cmd"; then
  echo "ERROR: required command '$cmd' is not installed" >&2
  exit $EXIT_ERROR
 fi
done

# Check that either curl or wget is available
if ! command_exists curl && ! command_exists wget; then
 echo "ERROR: neither curl nor wget is installed" >&2
 exit $EXIT_ERROR
fi

# Check that no other instances of this script are running
if command_exists ps; then
 SCRIPT_NAME=$(basename "$0")
 N_RUN=$(ps ax 2>/dev/null | grep -v grep | grep bash | grep -c "$SCRIPT_NAME")
 if [ "$N_RUN" -gt 2 ];then
  echo "Another instance of this script is already running, exiting"
  exit $EXIT_ALREADY_UPTODATE
 fi
fi

#################################
# Main logic
#################################

# Get VaST path and change to it
VAST_PATH=$(get_vast_path_ends_with_slash_from_this_script_name "$0")
export VAST_PATH

if [ ! -d "$VAST_PATH" ];then
 echo "ERROR: VaST directory not found: $VAST_PATH" >&2
 exit $EXIT_ERROR
fi

cd "$VAST_PATH" || exit $EXIT_ERROR

# Check if this is a git repository
if [ ! -d .git ];then
 echo "ERROR: $VAST_PATH is not a git repository" >&2
 exit $EXIT_ERROR
fi

# Get current local commit
CURRENT_LOCAL_COMMIT=$(git rev-parse HEAD 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$CURRENT_LOCAL_COMMIT" ];then
 echo "ERROR: cannot get current commit hash" >&2
 exit $EXIT_ERROR
fi

# Fetch latest info from remote (without updating working directory)
git fetch origin master &>/dev/null
if [ $? -ne 0 ];then
 echo "ERROR: git fetch failed" >&2
 exit $EXIT_ERROR
fi

# Get remote commit
REMOTE_COMMIT=$(git rev-parse origin/master 2>/dev/null)
if [ $? -ne 0 ] || [ -z "$REMOTE_COMMIT" ];then
 echo "ERROR: cannot get remote commit hash" >&2
 exit $EXIT_ERROR
fi

# Check if already up to date
if [ "$CURRENT_LOCAL_COMMIT" = "$REMOTE_COMMIT" ];then
 echo "Already up to date"
 exit $EXIT_ALREADY_UPTODATE
fi

echo "New version available: $REMOTE_COMMIT"
echo "Checking GitHub Actions status for this commit..."

# Check combined status using GitHub's status API (much simpler!)
# This endpoint returns a simple "state" field: "success", "pending", "failure", or "error"
STATUS_URL="https://api.github.com/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/commits/${REMOTE_COMMIT}/status"

if command_exists curl; then
 STATUS_RESPONSE=$(curl --silent --show-error --fail "$STATUS_URL" 2>/dev/null)
elif command_exists wget; then
 STATUS_RESPONSE=$(wget -q -O - "$STATUS_URL" 2>/dev/null)
fi

if [ $? -ne 0 ] || [ -z "$STATUS_RESPONSE" ];then
 echo "ERROR: failed to fetch commit status from GitHub API" >&2
 exit $EXIT_ERROR
fi

# Extract the state field - look for "state": "success" or similar
# This is much simpler than parsing the full workflow runs API
STATE=$(echo "$STATUS_RESPONSE" | grep -o '"state"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/"state"[[:space:]]*:[[:space:]]*"\([^"]*\)"/\1/' | head -n 1)

echo "Commit status: $STATE"

# Check if state is success
if [ "$STATE" != "success" ];then
 if [ "$STATE" = "pending" ];then
  echo "Tests are still running for commit $REMOTE_COMMIT"
  echo "Will try again later"
  exit $EXIT_ERROR
 else
  echo "ERROR: tests did not pass for commit $REMOTE_COMMIT (state: $STATE)" >&2
  echo "Will not update to this version" >&2
  exit $EXIT_ERROR
 fi
fi

echo "All tests passed. Proceeding with update."

# Pull the latest version
echo "Pulling latest version..."
git pull origin master
if [ $? -ne 0 ];then
 echo "ERROR: git pull failed" >&2
 exit $EXIT_ERROR
fi

# Maybe I don't want that if RECOMPILE_VAST_ONLY = yes is set in GNUmakefile (for fast compilation)
## Clean and compile
#echo "Cleaning previous build..."
#make clean &> /dev/null

echo "Compiling VaST..."
make > make.log 2>&1
if [ $? -ne 0 ];then
 echo "ERROR: make failed. See make.log for details" >&2
 tail -n 50 make.log >&2
 exit $EXIT_ERROR
fi

echo "VaST successfully updated and compiled"
exit $EXIT_SUCCESS
