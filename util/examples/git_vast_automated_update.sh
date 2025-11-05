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
GITHUB_API_BASE="https://api.github.com"
REQUIRED_WORKFLOWS=("Ubuntu build and test" "macOS build and test" "FreeBSD build")

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

# Function to call GitHub API
github_api_call() {
 local endpoint="$1"
 local url="${GITHUB_API_BASE}${endpoint}"
 
 # Try curl first, then wget
 if command_exists curl; then
  curl --silent --show-error --fail "$url" 2>/dev/null
  return $?
 elif command_exists wget; then
  wget -q -O - "$url" 2>/dev/null
  return $?
 else
  echo "ERROR: neither curl nor wget is available" >&2
  return 1
 fi
}

# Function to extract JSON value (simple parser for specific fields)
extract_json_value() {
 local json="$1"
 local key="$2"
 
 # Use grep and sed for basic JSON parsing (portable, no jq dependency)
 echo "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\"/\1/" | head -n 1
}

# Function to extract JSON array values
extract_json_array_values() {
 local json="$1"
 local key="$2"
 
 echo "$json" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | sed "s/\"${key}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\"/\1/"
}

#################################
# Pre-flight checks
#################################

# Check required commands
for cmd in git grep sed awk; do
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
echo "Checking GitHub Actions status..."

# Get workflow runs for the latest commit
WORKFLOW_RUNS_JSON=$(github_api_call "/repos/${GITHUB_REPO_OWNER}/${GITHUB_REPO_NAME}/actions/runs?per_page=100&branch=master")
if [ $? -ne 0 ] || [ -z "$WORKFLOW_RUNS_JSON" ];then
 echo "ERROR: failed to fetch workflow runs from GitHub API" >&2
 exit $EXIT_ERROR
fi

# Check each required workflow
ALL_WORKFLOWS_PASSED=true

for workflow_name in "${REQUIRED_WORKFLOWS[@]}"; do
 echo "Checking workflow: $workflow_name"
 
 # Find workflow run for this name and commit
 # This is a simplified approach - we look for matching workflow names and check conclusions
 workflow_found=false
 workflow_passed=false
 
 # Extract all workflow names and conclusions
 IFS=$'\n'
 workflow_names=($(extract_json_array_values "$WORKFLOW_RUNS_JSON" "name"))
 workflow_conclusions=($(extract_json_array_values "$WORKFLOW_RUNS_JSON" "conclusion"))
 workflow_shas=($(extract_json_array_values "$WORKFLOW_RUNS_JSON" "head_sha"))
 unset IFS
 
 # Find matching workflow for our commit
 for i in "${!workflow_names[@]}"; do
  if [ "${workflow_names[$i]}" = "$workflow_name" ] && [ "${workflow_shas[$i]}" = "$REMOTE_COMMIT" ];then
   workflow_found=true
   if [ "${workflow_conclusions[$i]}" = "success" ];then
    workflow_passed=true
    echo "  Status: PASSED"
    break
   else
    echo "  Status: ${workflow_conclusions[$i]}"
    break
   fi
  fi
 done
 
 if [ "$workflow_found" = false ];then
  echo "  Status: NOT FOUND or still running"
  ALL_WORKFLOWS_PASSED=false
 elif [ "$workflow_passed" = false ];then
  ALL_WORKFLOWS_PASSED=false
 fi
done

# If any workflow failed or is not found, exit
if [ "$ALL_WORKFLOWS_PASSED" = false ];then
 echo "ERROR: not all required workflows passed for commit $REMOTE_COMMIT" >&2
 echo "Will not update to this version" >&2
 exit $EXIT_ERROR
fi

echo "All workflows passed. Proceeding with update."

# Pull the latest version
echo "Pulling latest version..."
git pull origin master
if [ $? -ne 0 ];then
 echo "ERROR: git pull failed" >&2
 exit $EXIT_ERROR
fi

# Clean and compile
echo "Cleaning previous build..."
make clean &> /dev/null

echo "Compiling VaST..."
make > make.log 2>&1
if [ $? -ne 0 ];then
 echo "ERROR: make failed. See make.log for details" >&2
 tail -n 50 make.log >&2
 exit $EXIT_ERROR
fi

echo "VaST successfully updated and compiled"
exit $EXIT_SUCCESS
