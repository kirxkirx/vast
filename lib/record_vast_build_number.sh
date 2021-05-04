#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# check if git is installed
command -v git &>/dev/null
if [ $? -ne 0 ];then
 exit 0
fi

# if yes, save the build number to file
git describe --tags > .cc.build

# exit with success regardless of the result
# if the source tree was not cloned with git, the build number will not be available
exit 0
