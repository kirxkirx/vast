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

USE_JAVASCRIPT=0
grep --quiet "<script type='text/javascript'>" transient_report/index.html
if [ $? -eq 0 ];then
 USE_JAVASCRIPT=1
fi

while read LIGHTCURVE_FILE_OUTDAT B C D E REFERENCE_IMAGE G H ;do
 rm -f transient_report/index.tmp
 TRANSIENT_NAME=`basename $LIGHTCURVE_FILE_OUTDAT .dat`
 TRANSIENT_NAME=${TRANSIENT_NAME/out/}
 TRANSIENT_NAME="$TRANSIENT_NAME"_`basename $C .fts`
 echo "Preparing report for the candidate $TRANSIENT_NAME"
 if [ $USE_JAVASCRIPT -eq 1 ];then
  echo "
<a name='$TRANSIENT_NAME'></a>
<script>printCandidateNameWithAbsLink('$TRANSIENT_NAME');</script>" >> transient_report/index.tmp
 else
  echo "<h3>$TRANSIENT_NAME</h3>" >> transient_report/index.tmp
 fi
 # plot reference image
 util/make_finding_chart $REFERENCE_IMAGE $G $H &>/dev/null && mv pgplot.png transient_report/"$TRANSIENT_NAME"_reference.png
 echo "<img src=\""$TRANSIENT_NAME"_reference.png\">" >> transient_report/index.tmp
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
   echo "<img src=\""$TRANSIENT_NAME"_discovery"$N".png\">" >> transient_report/index.tmp
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
  
  # Only do this if we are going for javascript
  if [ $USE_JAVASCRIPT -eq 1 ];then

   # Only generate the full-frame previews if convert is installed
   command -v convert &> /dev/null
   if [ $? -eq 0 ];then
    echo "<a href=\"javascript:toggleElement('fullframepreview_$TRANSIENT_NAME')\">Preview of the reference image(s) and two 2nd epoch images</a> (are there clouds/trees in the field of view?)</br>" >> transient_report/index.tmp  
    echo "<div id=\"fullframepreview_$TRANSIENT_NAME\" style=\"display:none\"><img src=\"$REFERENCE_IMAGE_PREVIEW\">" >> transient_report/index.tmp
    while read JD MAG ERR X Y APP IMAGE REST ;do
     if [ "$IMAGE" != "$REFERENCE_IMAGE" ];then
      PREVIEW_IMAGE=`basename $IMAGE`_preview.png
      if [ ! -f transient_report/$PREVIEW_IMAGE ];then
       convert $IMAGE -brightness-contrast 30x30 -resize 10% transient_report/$PREVIEW_IMAGE &
      fi
      echo "<img src=\"$PREVIEW_IMAGE\">" >> transient_report/index.tmp
     fi
    done < $LIGHTCURVE_FILE_OUTDAT
    wait # just to speed-up the convert thing a bit
    echo "</div>" >> transient_report/index.tmp
   fi # if [ $? -eq 0 ];then
 
   #
   echo "<a href=\"javascript:toggleElement('manualvast_$TRANSIENT_NAME')\">Example VaST+ds9 commands for visual image inspection</a> (blink the images in ds9)</br>" >> transient_report/index.tmp  
   echo -n "<div id=\"manualvast_$TRANSIENT_NAME\" style=\"display:none\">
<pre>
# Plate-solve the FITS images
export TELESCOP='NMW_camera'
for i in $REFERENCE_IMAGE " >> transient_report/index.tmp
   while read JD MAG ERR X Y APP IMAGE REST ;do
    echo -n "$IMAGE "
   done < $LIGHTCURVE_FILE_OUTDAT >> transient_report/index.tmp
   echo -n ";do util/wcs_image_calibration.sh \$i ;done
# Display the solved FITS images
ds9 -frame lock wcs  " >> transient_report/index.tmp
   # We should always display the reference image, even if it's not in the lightcurve file
   grep --quiet "$REFERENCE_IMAGE" $LIGHTCURVE_FILE_OUTDAT
   if [ $? -ne 0 ];then
    echo -n "wcs_"`basename "$REFERENCE_IMAGE"`" " >> transient_report/index.tmp
   fi
   while read JD MAG ERR X Y APP IMAGE REST ;do
    echo -n " wcs_"`basename "$IMAGE"`" -crosshair $X $Y image   "
   done < $LIGHTCURVE_FILE_OUTDAT >> transient_report/index.tmp
   echo "
</pre>
</div>" >> transient_report/index.tmp
   #
   #echo "</br>" >> transient_report/index.tmp

   #
   echo "<a href=\"javascript:toggleElement('vastcommandline_$TRANSIENT_NAME')\">VaST command line</a> (re-run the analysis for testing)</br>" >> transient_report/index.tmp  
   echo -n "<div id=\"vastcommandline_$TRANSIENT_NAME\" style=\"display:none\">
<pre>
" >> transient_report/index.tmp
   cat vast_command_line.log >> transient_report/index.tmp
   echo " && util/transients/search_for_transients_single_field.sh
</pre>
</div>" >> transient_report/index.tmp
   #
   #echo "</br>" >> transient_report/index.tmp

  fi # if [ $USE_JAVASCRIPT -eq 1 ];then

  echo "<HR>" >> transient_report/index.tmp
  cat transient_report/index.tmp >> transient_report/index$1.html
 else
  tail -n1 transient_report/index.tmp
  echo "The candidate $TRANSIENT_NAME did not pass the final checks"
  rm -f transient_report/index.tmp
 fi
done < candidates-transients.lst
rm -f transient_report/index.tmp
rm -f *_preview.png
