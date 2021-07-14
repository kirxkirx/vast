#!/usr/bin/env bash                                              
########### Try to guess a non-standard X11 libray path ###########

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Test other possible library paths
for POSSIBLE_LIBRARY_PATH in /opt/X11/lib /usr/X11R6/lib /usr/lib/X11 /usr/local/lib/X11 /usr/lib64/X11 /usr/local/lib64/X11 /usr/lib32/X11 /usr/local/lib32/X11 /opt/local/lib ;do
 if [ -d "$POSSIBLE_LIBRARY_PATH" ];then
  LX11="$LX11 -L$POSSIBLE_LIBRARY_PATH"
  break
 fi
done
# Test other possible include paths
for POSSIBLE_LIBRARY_PATH in /opt/X11/include /usr/X11R6/include /usr/include/X11 /usr/local/include/X11 /opt/local/include ;do
 if [ -d "$POSSIBLE_LIBRARY_PATH" ];then
  LX11="$LX11 -I$POSSIBLE_LIBRARY_PATH"
  break
 fi
done
if [ ! -z "$LX11" ];then
 echo "Adding the following to include and library path: $LX11" 1>&2
fi

# Print result
echo "$LX11"
