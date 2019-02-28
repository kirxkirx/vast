#!/usr/bin/env bash

FILE_WITH_FILEAMES_OF_KNOWN_VARS="vast_autocandidates.log"

for STATISTICSFILE in vast_lightcurve_statistics.log vast_lightcurve_statistics_normalized.log ;do
 VARIABLESFILE=${STATISTICSFILE/.log/_variables_only.log}
 NONVARIABLESFILE=${STATISTICSFILE/.log/_constant_only.log}
 for i in $VARIABLESFILE $NONVARIABLESFILE ;do
  if [ -f $i ];then
   rm -f $i
  fi
 done
 cp "$STATISTICSFILE" "$NONVARIABLESFILE"
 while read LCFILENAME REST ;do
  grep "$LCFILENAME" "$STATISTICSFILE" >> "$VARIABLESFILE"
  grep -v "$LCFILENAME" "$NONVARIABLESFILE" > tmp.log
  mv tmp.log "$NONVARIABLESFILE"
 done < "$FILE_WITH_FILEAMES_OF_KNOWN_VARS"
done

