#!/usr/bin/env bash
#
# Generate bright_star_blend_check.sex for tranisent search
# bright_star_blend_check.sex is generated from default sextractor file
# with more conservative DETECT_MINAREA DETECT_THRESH and ANALYSIS_THRESH
#

for DEGRADE_FACTOR in 0.7 1.5 3.0 7.0 ;do
if [ ! -z $1 ];then
 DEFAULT_SEX_FILE="$1"
else
 DEFAULT_SEX_FILE="default.sex"
fi
echo -n "Generating bright_star_blend_check_$DEGRADE_FACTOR.sex from $DEFAULT_SEX_FILE ...   "
if [ ! -f $DEFAULT_SEX_FILE ];then
 echo ERROR: Can\'t find file $DEFAULT_SEX_FILE
 exit 1
fi 
while read STR ;do
 PARAM=`echo $STR |awk '{print $1}'`
 if [ "$PARAM" = "DETECT_MINAREA" ];then
  VALUE=`echo $STR |awk '{print $2}'`
  VALUE=`echo $VALUE*$DEGRADE_FACTOR|bc -ql`
  STR="$PARAM $VALUE"
 elif [ "$PARAM" = "DETECT_THRESH" ];then
  VALUE=`echo $STR |awk '{print $2}'`
  VALUE=`echo $VALUE*$DEGRADE_FACTOR|bc -ql`
  STR="$PARAM $VALUE"
 elif [ "$PARAM" = "ANALYSIS_THRESH" ];then 
  VALUE=`echo $STR |awk '{print $2}'`
  VALUE=`echo $VALUE*$DEGRADE_FACTOR|bc -ql`
  STR="$PARAM $VALUE" 
 elif [ "$PARAM" = "SATUR_LEVEL" ];then
  STR="$PARAM 70000"
 fi
 echo "$STR" 
done < $DEFAULT_SEX_FILE > bright_star_blend_check_$DEGRADE_FACTOR.sex
echo "done"
done
