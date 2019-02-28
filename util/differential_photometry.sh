#!/usr/bin/env bash

if [ -z $2 ];then
 echo "!!IMPORTANT NOTE!!"
 echo -e "You need to run VaST on your dataset with \"-n\" option activated" 
 echo -e "(for example: ./vast -n ../images/image*.fit )"
 echo -e "before this differential photometry script may be used."
 echo -e "The \"-n\" option will prevent VaST from trying to conduct its own"
 echo -e " magnitude calibration using all stars on each image."
 echo " "
 echo "Usage: $0 outVAR_STAR.dat outCOMP_STAR.dat"
 echo "or"
 echo "       $0 outVAR_STAR.dat outCOMP_STAR1.dat outCOMP_STAR2.dat"
 echo "You may use up to 5 comparison stars with this script."
 exit
fi

NUMBER_OF_COMPARISON_STARS=$[$#-1]

TARGET=$1

while read JD MAG MAG_ERR X Y APP IMAGE ;do
  COMP_MAG=""
  COMP=$2
  if [ $NUMBER_OF_COMPARISON_STARS -eq 1 ];then
   COMP_MAG=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR=`grep "$IMAGE" $COMP |awk '{print $3}'`
  fi
  if [ $NUMBER_OF_COMPARISON_STARS -eq 2 ];then
   COMP_MAG1=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR1=`grep "$IMAGE" $COMP |awk '{print $3}'`
   COMP=$3
   COMP_MAG2=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR2=`grep "$IMAGE" $COMP |awk '{print $3}'`
   if [ "$COMP_MAG1" != "" ];then
    if [ "$COMP_MAG2" != "" ];then
     COMP_MAG=`echo "(($COMP_MAG1/$COMP_MAG_ERR1^2)+($COMP_MAG2/$COMP_MAG_ERR2^2))/(1/$COMP_MAG_ERR1^2+1/$COMP_MAG_ERR2^2)" |bc -ql |awk '{printf "%7.4f",$1}'`
     COMP_MAG_ERR=`echo "sqrt(($COMP_MAG_ERR1)^2+($COMP_MAG_ERR2)^2)" |bc -ql |awk '{printf "%6.4f",$1}'`
    fi
   fi
  fi
  if [ $NUMBER_OF_COMPARISON_STARS -eq 3 ];then
   COMP_MAG1=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR1=`grep "$IMAGE" $COMP |awk '{print $3}'`
   COMP=$3
   COMP_MAG2=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR2=`grep "$IMAGE" $COMP |awk '{print $3}'`
   COMP=$4
   COMP_MAG3=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR3=`grep "$IMAGE" $COMP |awk '{print $3}'`
   if [ "$COMP_MAG1" != "" ];then
    if [ "$COMP_MAG2" != "" ];then
     if [ "$COMP_MAG3" != "" ];then
      COMP_MAG=`echo "(($COMP_MAG1/$COMP_MAG_ERR1^2)+($COMP_MAG2/$COMP_MAG_ERR2^2)+($COMP_MAG3/$COMP_MAG_ERR3^2))/(1/$COMP_MAG_ERR1^2+1/$COMP_MAG_ERR2^2+1/$COMP_MAG_ERR3^2)" |bc -ql |awk '{printf "%7.4f",$1}'`
      COMP_MAG_ERR=`echo "sqrt(($COMP_MAG_ERR1)^2+($COMP_MAG_ERR2)^2+($COMP_MAG_ERR3)^2)" |bc -ql |awk '{printf "%6.4f",$1}'`
     fi
    fi
   fi
  fi
  if [ $NUMBER_OF_COMPARISON_STARS -eq 4 ];then
   COMP_MAG1=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR1=`grep "$IMAGE" $COMP |awk '{print $3}'`
   COMP=$3
   COMP_MAG2=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR2=`grep "$IMAGE" $COMP |awk '{print $3}'`
   COMP=$4
   COMP_MAG3=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR3=`grep "$IMAGE" $COMP |awk '{print $3}'`
   COMP=$5
   COMP_MAG4=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR4=`grep "$IMAGE" $COMP |awk '{print $3}'`
   if [ "$COMP_MAG1" != "" ];then
    if [ "$COMP_MAG2" != "" ];then
     if [ "$COMP_MAG3" != "" ];then
      if [ "$COMP_MAG4" != "" ];then
       COMP_MAG=`echo "(($COMP_MAG1/$COMP_MAG_ERR1^2)+($COMP_MAG2/$COMP_MAG_ERR2^2)+($COMP_MAG3/$COMP_MAG_ERR3^2)+($COMP_MAG4/$COMP_MAG_ERR4^2))/(1/$COMP_MAG_ERR1^2+1/$COMP_MAG_ERR2^2+1/$COMP_MAG_ERR3^2+1/$COMP_MAG_ERR4^2)" |bc -ql |awk '{printf "%7.4f",$1}'`
       COMP_MAG_ERR=`echo "sqrt(($COMP_MAG_ERR1)^2+($COMP_MAG_ERR2)^2+($COMP_MAG_ERR3)^2+($COMP_MAG_ERR4)^2)" |bc -ql |awk '{printf "%6.4f",$1}'`
      fi
     fi
    fi
   fi
  fi
  if [ $NUMBER_OF_COMPARISON_STARS -eq 5 ];then
   COMP_MAG1=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR1=`grep "$IMAGE" $COMP |awk '{print $3}'`
   COMP=$3
   COMP_MAG2=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR2=`grep "$IMAGE" $COMP |awk '{print $3}'`
   COMP=$4
   COMP_MAG3=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR3=`grep "$IMAGE" $COMP |awk '{print $3}'`
   COMP=$5
   COMP_MAG4=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR4=`grep "$IMAGE" $COMP |awk '{print $3}'`
   COMP=$6
   COMP_MAG5=`grep "$IMAGE" $COMP |awk '{print $2}'`
   COMP_MAG_ERR5=`grep "$IMAGE" $COMP |awk '{print $3}'`
   if [ "$COMP_MAG1" != "" ];then
    if [ "$COMP_MAG2" != "" ];then
     if [ "$COMP_MAG3" != "" ];then
      if [ "$COMP_MAG4" != "" ];then
       if [ "$COMP_MAG5" != "" ];then
        COMP_MAG=`echo "(($COMP_MAG1/$COMP_MAG_ERR1^2)+($COMP_MAG2/$COMP_MAG_ERR2^2)+($COMP_MAG3/$COMP_MAG_ERR3^2)+($COMP_MAG4/$COMP_MAG_ERR4^2)+($COMP_MAG5/$COMP_MAG_ERR5^2))/(1/$COMP_MAG_ERR1^2+1/$COMP_MAG_ERR2^2+1/$COMP_MAG_ERR3^2+1/$COMP_MAG_ERR4^2+1/$COMP_MAG_ERR5^2)" |bc -ql |awk '{printf "%7.4f",$1}'`
        COMP_MAG_ERR=`echo "sqrt(($COMP_MAG_ERR1)^2+($COMP_MAG_ERR2)^2+($COMP_MAG_ERR3)^2+($COMP_MAG_ERR4)^2+($COMP_MAG_ERR5)^2)" |bc -ql |awk '{printf "%6.4f",$1}'`
       fi
      fi
     fi
    fi
   fi
  fi

  # Compute and print results
  if [ "$COMP_MAG" != "" ];then
   DIFF_MAG=`echo "($MAG)-($COMP_MAG)" |bc -ql |awk '{printf "%7.4f",$1}'`
   DIFF_MAG_ERR=`echo "sqrt(($MAG_ERR)^2+($COMP_MAG_ERR)^2)" |bc -ql |awk '{printf "%6.4f",$1}'`
   echo "$JD  $DIFF_MAG $DIFF_MAG_ERR"
  fi
  
done < $TARGET
