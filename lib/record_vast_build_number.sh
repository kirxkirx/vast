#!/usr/bin/env bash

# check if git is installed
command -v git &>/dev/null
if [ $? -ne 0 ];then
 exit 0
fi

# if yes, save the build number to file
git describe --tags > .cc.build

