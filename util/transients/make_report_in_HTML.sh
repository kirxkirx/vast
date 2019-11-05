#!/usr/bin/env bash



# Set PNG finding chart dimensions
export PGPLOT_PNG_HEIGHT=400 ; export PGPLOT_PNG_WIDTH=400

# Make sure there is a directory to put the report in
if [ ! -d transient_report/ ];then
 mkdir transient_report
fi

if [ ! -f candidates-transients.lst ];then
 echo "No candidates found here"
 exit
fi

while read LIGHTCURVE_FILE_OUTDAT B C D E REFERENCE_IMAGE G H ;do
 rm -f transient_report/index.tmp
 TRANSIENT_NAME=`basename $LIGHTCURVE_FILE_OUTDAT .dat`
 TRANSIENT_NAME=${TRANSIENT_NAME/out/}
 TRANSIENT_NAME="$TRANSIENT_NAME"_`basename $C`
 echo "Preparing report for the candidate $TRANSIENT_NAME"
 echo "<h3>$TRANSIENT_NAME</h3>" >> transient_report/index.tmp
 # plot reference image
 util/make_finding_chart $REFERENCE_IMAGE $G $H &>/dev/null && mv pgplot.png transient_report/"$TRANSIENT_NAME"_reference.png
 echo "<img src=\""$TRANSIENT_NAME"_reference.png\"></img>" >> transient_report/index.tmp
 # plot reference image preview
 command -v convert &> /dev/null
 if [ $? -eq 0 ];then
  REFERENCE_IMAGE_PREVIEW=`basename $REFERENCE_IMAGE`_preview.png
  if [ ! -f transient_report/$REFERENCE_IMAGE_PREVIEW ];then
   convert $REFERENCE_IMAGE -brightness-contrast 30x30 -resize 10% transient_report/$REFERENCE_IMAGE_PREVIEW
  fi
 fi
                        

 DATE=`grep $REFERENCE_IMAGE vast_image_details.log |awk '{print $2" "$3"  "$7}'`
 rm -f tmp.description

 #echo "Reference image: $DATE  $REFERENCE_IMAGE  $G $H (pix)" >> tmp.description 
 # read the lightcurve file, plot discovery images
 N=0;
 while read JD MAG ERR X Y APP IMAGE REST ;do
  #echo "--- $TRANSIENT_NAME ---: $IMAGE $REFERENCE_IMAGE $JD"
  # If this is not the reference image again
  if [ "$IMAGE" != "$REFERENCE_IMAGE" ];then
   # Plot the discovery image
   N=`echo $N+1|bc -q`
   DATE=`grep $IMAGE vast_image_details.log |awk '{print $2" "$3"  "$7}'`
   #echo "Discovery image $N: $DATE  $IMAGE  $X $Y (pix)" >> tmp.description
   # convert -density 45 pgplot.ps pgplot.png
   util/make_finding_chart $IMAGE $X $Y &>/dev/null && mv pgplot.png transient_report/"$TRANSIENT_NAME"_discovery"$N".png
   echo "<img src=\""$TRANSIENT_NAME"_discovery"$N".png\"></img>" >> transient_report/index.tmp
  fi
 done < $LIGHTCURVE_FILE_OUTDAT
 
 echo "</br>" >> transient_report/index.tmp
 #echo "<pre>" >> transient_report/index.tmp
 #cat tmp.description >> transient_report/index.tmp
 #util/transients/report_transient.sh $LIGHTCURVE_FILE_OUTDAT 120 >> transient_report/index.tmp
 util/transients/report_transient.sh $LIGHTCURVE_FILE_OUTDAT  >> transient_report/index.tmp
 #echo "!!! $TRANSIENT_NAME !!!"
 #cat transient_report/index.tmp
 #echo "!!!!!!!!!!!!!!!!!!!!!!!"
 # if the final check passed well
 if [ $? -eq 0 ];then

  #echo "</pre>" >> transient_report/index.tmp

  # Only generate the full-frame previews if convert is installed
  command -v convert &> /dev/null
  if [ $? -eq 0 ];then
   echo "<a href=\"javascript:toggleElement('fullframepreview_$TRANSIENT_NAME')\">Preview of the reference image(s) and two 2nd epoch images</a></br>" >> transient_report/index.tmp  
   echo "<div id=\"fullframepreview_$TRANSIENT_NAME\" style=\"display:none\"><img src=\"$REFERENCE_IMAGE_PREVIEW\"></img>" >> transient_report/index.tmp
   while read JD MAG ERR X Y APP IMAGE REST ;do
    if [ "$IMAGE" != "$REFERENCE_IMAGE" ];then
     PREVIEW_IMAGE=`basename $IMAGE`_preview.png
     if [ ! -f transient_report/$PREVIEW_IMAGE ];then
      convert $IMAGE -brightness-contrast 30x30 -resize 10% transient_report/$PREVIEW_IMAGE &
     fi
     echo "<img src=\"$PREVIEW_IMAGE\"></img>" >> transient_report/index.tmp
    fi
   done < $LIGHTCURVE_FILE_OUTDAT
   wait # just to speed-up the convert thing a bit
   echo "</div>" >> transient_report/index.tmp
  fi # if [ $? -eq 0 ];then
 
  echo "</br>" >> transient_report/index.tmp

  echo "<HR>" >> transient_report/index.tmp
  cat transient_report/index.tmp >> transient_report/index$1.html
 else
  rm -f transient_report/index.tmp
 fi
done < candidates-transients.lst
rm -f transient_report/index.tmp
rm -f *_preview.png
