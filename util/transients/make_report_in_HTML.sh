#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

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
 if [ -f transient_report/index.tmp ];then
  rm -f transient_report/index.tmp
 fi
 if [ -f transient_report/index.tmp2 ];then
  rm -f transient_report/index.tmp2
 fi
 
 if [ ! -s $LIGHTCURVE_FILE_OUTDAT ];then
  echo "WARNING: $LIGHTCURVE_FILE_OUTDAT lightcurve file does not exist!!!"
  continue
 fi
 
 TRANSIENT_NAME=`basename $LIGHTCURVE_FILE_OUTDAT .dat`
 TRANSIENT_NAME=${TRANSIENT_NAME/out/}
 TRANSIENT_NAME="$TRANSIENT_NAME"_`basename $C .fts`
 
 # Moved the final check here
 util/transients/report_transient.sh $LIGHTCURVE_FILE_OUTDAT  > transient_report/index.tmp2
 if [ $? -ne 0 ];then
  echo "The candidate $TRANSIENT_NAME did not pass the final checks"
  if [ -f transient_report/index.tmp2 ];then
   tail -n3 transient_report/index.tmp2
   rm -f transient_report/index.tmp2
  fi
  continue
 fi

 echo "Preparing report for the candidate $TRANSIENT_NAME"
 if [ $USE_JAVASCRIPT -eq 1 ];then
  echo "
<a name='$TRANSIENT_NAME'></a>
<script>printCandidateNameWithAbsLink('$TRANSIENT_NAME');</script>" >> transient_report/index.tmp
 else
  echo "<h3>$TRANSIENT_NAME</h3>" >> transient_report/index.tmp
 fi
 # plot reference image
 # Set PNG finding chart dimensions
 export PGPLOT_PNG_HEIGHT=400 ; export PGPLOT_PNG_WIDTH=400
 util/make_finding_chart $REFERENCE_IMAGE $G $H &>/dev/null && mv pgplot.png transient_report/"$TRANSIENT_NAME"_reference.png
 unset PGPLOT_PNG_HEIGHT ; unset PGPLOT_PNG_WIDTH
 echo "<img src=\""$TRANSIENT_NAME"_reference.png\">" >> transient_report/index.tmp
 # plot reference image preview
 BASENAME_REFERENCE_IMAGE=`basename $REFERENCE_IMAGE`
 REFERENCE_IMAGE_PREVIEW="$BASENAME_REFERENCE_IMAGE"_preview.png
 # image size needs to match the one set in util/transients/transient_factory_test31.sh and below
 export PGPLOT_PNG_WIDTH=1000 ; export PGPLOT_PNG_HEIGHT=1000
 util/fits2png $REFERENCE_IMAGE &> /dev/null && mv pgplot.png transient_report/$REFERENCE_IMAGE_PREVIEW
 unset PGPLOT_PNG_WIDTH ; unset PGPLOT_PNG_HEIGHT
 #command -v convert &> /dev/null
 #if [ $? -eq 0 ];then
 # REFERENCE_IMAGE_PREVIEW=`basename $REFERENCE_IMAGE`_preview.png
 # if [ ! -f transient_report/$REFERENCE_IMAGE_PREVIEW ];then
 #  convert $REFERENCE_IMAGE -brightness-contrast 30x30 -resize 10% transient_report/$REFERENCE_IMAGE_PREVIEW
 # fi
 #fi


                        

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
   #N=`echo $N+1|bc -q`
   N=$[$N+1]
   DATE=`grep $IMAGE vast_image_details.log |awk '{print $2" "$3"  "$7}'`
   #echo "Discovery image $N: $DATE  $IMAGE  $X $Y (pix)" >> tmp.description
   # convert -density 45 pgplot.ps pgplot.png
   # Set PNG finding chart dimensions
   export PGPLOT_PNG_HEIGHT=400 ; export PGPLOT_PNG_WIDTH=400
   util/make_finding_chart $IMAGE $X $Y &>/dev/null && mv pgplot.png transient_report/"$TRANSIENT_NAME"_discovery"$N".png
   unset PGPLOT_PNG_HEIGHT ; unset PGPLOT_PNG_WIDTH
   echo "<img src=\""$TRANSIENT_NAME"_discovery"$N".png\">" >> transient_report/index.tmp
   
  fi # if [ "$IMAGE" != "$REFERENCE_IMAGE" ];then
 done < $LIGHTCURVE_FILE_OUTDAT
 
 echo "</br>" >> transient_report/index.tmp
 #util/transients/report_transient.sh $LIGHTCURVE_FILE_OUTDAT  >> transient_report/index.tmp
 # if the final check passed well
 #if [ $? -eq 0 ];then

  cat transient_report/index.tmp2 >> transient_report/index.tmp

  #echo "</pre>" >> transient_report/index.tmp
  
  # Only do this if we are going for javascript
  if [ $USE_JAVASCRIPT -eq 1 ];then

   #echo "<a href=\"javascript:toggleElement('fullframepreview_$TRANSIENT_NAME')\">Preview of the reference image(s) and two 2nd epoch images</a> (are there clouds/trees in the view?)</br>" >> transient_report/index.tmp  
   echo "<a href=\"javascript:toggleElement('fullframepreview_$TRANSIENT_NAME')\">Preview of the reference image(s) and two 2nd epoch images</a> (are there clouds/trees in the view?)" >> transient_report/index.tmp  
   if [ ! -z "$URL_OF_DATA_PROCESSING_ROOT" ];then
    DIRNAME_2ND_EPOCH_IMAGES=`dirname $REFERENCE_IMAGE`
    DIRNAME_2ND_EPOCH_IMAGES=`basename $DIRNAME_2ND_EPOCH_IMAGES`
    echo "<div id=\"fullframepreview_$TRANSIENT_NAME\" style=\"display:none\"><a href='$URL_OF_DATA_PROCESSING_ROOT/$DIRNAME_2ND_EPOCH_IMAGES/$BASENAME_REFERENCE_IMAGE'>$BASENAME_REFERENCE_IMAGE</a><br><img src=\"$REFERENCE_IMAGE_PREVIEW\"><br>" >> transient_report/index.tmp
   else
    echo "<div id=\"fullframepreview_$TRANSIENT_NAME\" style=\"display:none\">$BASENAME_REFERENCE_IMAGE<br><img src=\"$REFERENCE_IMAGE_PREVIEW\"><br>" >> transient_report/index.tmp
   fi
   while read JD MAG ERR X Y APP IMAGE REST ;do
    if [ "$IMAGE" != "$REFERENCE_IMAGE" ];then
     BASENAME_IMAGE=`basename $IMAGE`
     PREVIEW_IMAGE="$BASENAME_IMAGE"_preview.png
     if [ ! -f transient_report/$PREVIEW_IMAGE ];then
      unset PGPLOT_PNG_WIDTH ; unset PGPLOT_PNG_HEIGHT
      # image size needs to match the one set in util/transients/transient_factory_test31.sh and above
      export PGPLOT_PNG_WIDTH=1000 ; export PGPLOT_PNG_HEIGHT=1000
      util/fits2png $IMAGE &> /dev/null && mv pgplot.png transient_report/$PREVIEW_IMAGE
      unset PGPLOT_PNG_WIDTH ; unset PGPLOT_PNG_HEIGHT
     fi # if [ ! -f transient_report/$PREVIEW_IMAGE ];then
     # Link to the images dir if $URL_OF_DATA_PROCESSING_ROOT is set
     if [ ! -z "$URL_OF_DATA_PROCESSING_ROOT" ];then
      DIRNAME_2ND_EPOCH_IMAGES=`dirname $IMAGE`
      DIRNAME_2ND_EPOCH_IMAGES=`basename $DIRNAME_2ND_EPOCH_IMAGES`
      echo "<br><a href='$URL_OF_DATA_PROCESSING_ROOT/$DIRNAME_2ND_EPOCH_IMAGES/$BASENAME_IMAGE'>$BASENAME_IMAGE</a><br><img src=\"$PREVIEW_IMAGE\"><br>" >> transient_report/index.tmp
     else
      echo "<br>$BASENAME_IMAGE<br><img src=\"$PREVIEW_IMAGE\"><br>" >> transient_report/index.tmp
     fi
    fi
   done < $LIGHTCURVE_FILE_OUTDAT
   wait # just to speed-up the convert thing a bit
   echo "</div>" >> transient_report/index.tmp

   if [ ! -z "$URL_OF_DATA_PROCESSING_ROOT" ];then
    echo -n " <a href='$URL_OF_DATA_PROCESSING_ROOT/$DIRNAME_2ND_EPOCH_IMAGES'>2nd epoch FITS</a> " >> transient_report/index.tmp
   fi

   echo "</br>" >> transient_report/index.tmp 
   
   #
   echo "<a href=\"javascript:toggleElement('manualvast_$TRANSIENT_NAME')\">Example VaST+ds9 commands for visual image inspection</a> (blink images in ds9). " >> transient_report/index.tmp  
   echo -n "<div id=\"manualvast_$TRANSIENT_NAME\" style=\"display:none\">
<pre style='font-family:monospace;font-size:12px;'>
# Set SExtractor parameters file
cp default.sex.telephoto_lens_onlybrightstars_v1 default.sex
# Plate-solve the FITS images
export TELESCOP='NMW_camera'
for i in $REFERENCE_IMAGE " >> transient_report/index.tmp
   while read JD MAG ERR X Y APP IMAGE REST ;do
    if [ "$IMAGE" != "$REFERENCE_IMAGE" ];then
     echo -n "$IMAGE "
    fi
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

   #
   echo "<a href=\"javascript:toggleElement('vastcommandline_$TRANSIENT_NAME')\">VaST command line</a> (re-run VaST)</br>" >> transient_report/index.tmp  
   echo -n "<div id=\"vastcommandline_$TRANSIENT_NAME\" style=\"display:none\">
<pre style='font-family:monospace;font-size:12px;'>
" >> transient_report/index.tmp
   cat vast_command_line.log >> transient_report/index.tmp
   echo " && util/transients/search_for_transients_single_field.sh
</pre>
</div>" >> transient_report/index.tmp
   #

   #
   grep --max-count=1 --quiet 'done by the script' transient_report/index.html
   if [ $? -eq 0 ];then
    echo "<a href=\"javascript:toggleElement('analysisscript_$TRANSIENT_NAME')\">The analysis script</a> (re-run the full search)" >> transient_report/index.tmp  
    echo -n "<div id=\"analysisscript_$TRANSIENT_NAME\" style=\"display:none\">
<pre style='font-family:monospace;font-size:12px;'>
REFERENCE_IMAGES="`dirname $REFERENCE_IMAGE` >> transient_report/index.tmp
    echo -n "  " >> transient_report/index.tmp
    grep --max-count=1 'done by the script' transient_report/index.html | awk -F'<code>' '{print $2}' | awk -F'</code>' '{print $1}' >> transient_report/index.tmp
    echo "</pre>
</div>" >> transient_report/index.tmp
   fi
   #


   #
   if [ -f test.mpc ];then
    # Stub MPC report
    echo "<a href=\"javascript:toggleElement('mpcstub_$TRANSIENT_NAME')\">Stub MPC report</a> (for online MPChecker) " >> transient_report/index.tmp  
    echo -n "<div id=\"mpcstub_$TRANSIENT_NAME\" style=\"display:none\">
Don't forget to copy the leading white spaces and change the observatory code! 
The code 'C32' is 'Ka-Dar Observatory, TAU Station, Nizhny Arkhyz', the code '500' is the geocenter.
Make sure there are no trailing white spaces after the observatory code. 
The string should be exactly 80 characters long to conform to the MPC format.<br>
Mean position:
<pre style='font-family:monospace;font-size:12px;'>
" >> transient_report/index.tmp
    cat test.mpc | sed 's: 500: C32:g' >> transient_report/index.tmp
    echo "</pre>
Position measured on individual images:
<pre style='font-family:monospace;font-size:12px;'>" >> transient_report/index.tmp
    grep 'Discovery image' transient_report/index.tmp | tail -n 2 | head -n1 | awk -F'>' '{print $5" "$11" "$9}' | sed 's:&nbsp;::g' | sed 's:</td::g' | sed 's:\:: :g' | awk '{printf "     TAU0008  C%s %02.0f %08.5f %02.0f %02.0f %05.2f %+03.0f %02.0f %05.2f         %4.1f R      C32\n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10}' >> transient_report/index.tmp
    grep 'Discovery image' transient_report/index.tmp | tail -n 1 | awk -F'>' '{print $5" "$11" "$9}' | sed 's:&nbsp;::g' | sed 's:</td::g' | sed 's:\:: :g' | awk '{printf "     TAU0008  C%s %02.0f %08.5f %02.0f %02.0f %05.2f %+03.0f %02.0f %05.2f         %4.1f R      C32\n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10}' >> transient_report/index.tmp
    echo "</pre>" >> transient_report/index.tmp
    echo "You may copy/paste the above measurements to the following online services:<br>
<a href='https://minorplanetcenter.net/cgi-bin/checkmp.cgi'>MPChecker</a> (in case the button does not work)<br>
<a href='https://minorplanetcenter.net/cgi-bin/checkneocmt.cgi'>NEOCMTChecker</a> (NEO's and comets)<br>
<a href='https://www.projectpluto.com/sat_id2.htm'>sat_id2</a> (artificial satellites; needs at least two observations to work)<br>
<a href='http://www.fitsblink.net/satellites/'>fitsblink_satellites</a> (art. sat.; you'll need to save the astrometry as a text file and upload it)
<br>
</div>" >> transient_report/index.tmp
    # Stub TOCP report
    echo "<a href=\"javascript:toggleElement('tocpstub_$TRANSIENT_NAME')\">Stub TOCP report</a> " >> transient_report/index.tmp  
    echo -n "<div id=\"tocpstub_$TRANSIENT_NAME\" style=\"display:none\">
Here is a stub line for <a href='http://www.cbat.eps.harvard.edu/tocp_report'>reporting a new transient to the TOCP</a>. 
Don't forget to set the constellation name and the number of days since the last non-detection!
<pre style='font-family:monospace;font-size:12px;'>
" >> transient_report/index.tmp
    cat test.mpc | sed 's: C2: 2:g' | awk '{printf "TCP %d %02d %07.4f*  %02d %02d %05.2f %+03d %02d %04.1f  %4.1f U             Con       9 0\n", $2, $3, $4,  $5, $6, $7,  $8, $9, $10,  $11}' >> transient_report/index.tmp
    echo "</pre>
<br>
</div>" >> transient_report/index.tmp
   fi
   #

   #
   TARGET_MEAN_POSITION=`grep -A1 'Mean magnitude and position on the discovery images: ' transient_report/index.tmp | tail -n1 | awk '{print $6" "$7}'`
   #
   echo "<a href=\"javascript:toggleElement('findercharts_$TRANSIENT_NAME')\">Make finder charts with VaST</a>" >> transient_report/index.tmp  
   echo -n "<div id=\"findercharts_$TRANSIENT_NAME\" style=\"display:none\">
<pre style='font-family:monospace;font-size:12px;'>
# Set SExtractor parameters file
cp default.sex.telephoto_lens_onlybrightstars_v1 default.sex
# Plate-solve the FITS images and produce the finder charts
export TELESCOP='NMW_camera'
for i in $REFERENCE_IMAGE " >> transient_report/index.tmp
   while read JD MAG ERR X Y APP IMAGE REST ;do
    if [ "$IMAGE" != "$REFERENCE_IMAGE" ];then
     echo -n "$IMAGE "
    fi
   done < $LIGHTCURVE_FILE_OUTDAT >> transient_report/index.tmp
   echo -n ";do util/wcs_image_calibration.sh \$i && util/make_finding_chart_script.sh wcs_\`basename \$i\` $TARGET_MEAN_POSITION ;done 
# Combine the finder charts into one image (note the '*' symbols meaning the command will work only if you have a single transient in that field)
montage " >> transient_report/index.tmp
ORIG_FITS_IMG="$REFERENCE_IMAGE"
BASENAME_RESAMPLE_WCS_FITS_IMG="resample_wcs_"`basename "$REFERENCE_IMAGE"`
# nope, we don't have a solved image when we run this
PIXEL_POSITION_TO_MARK="*"
FITSFILE=${BASENAME_RESAMPLE_WCS_FITS_IMG//./_}
FITSFILE=${FITSFILE//" "/_}
echo -n $FITSFILE"__"$PIXEL_POSITION_TO_MARK"pix.png" >> transient_report/index.tmp
#
ORIG_FITS_IMG=`tail -n1 $LIGHTCURVE_FILE_OUTDAT | awk '{print $7}'`
BASENAME_RESAMPLE_WCS_FITS_IMG="resample_wcs_"`basename "$ORIG_FITS_IMG"`
FITSFILE=${BASENAME_RESAMPLE_WCS_FITS_IMG//./_}
FITSFILE=${FITSFILE//" "/_}
#   echo -n " "$FITSFILE"__"$PIXEL_POSITION_TO_MARK"pix.png" >> transient_report/index.tmp
   echo -n " "$FITSFILE"__"$PIXEL_POSITION_TO_MARK"pix_nofov.png" >> transient_report/index.tmp
   echo " -tile 2x1 -geometry +0+0 finder_chart_v1.png" >> transient_report/index.tmp
### 2nd version of the finder chart
   echo -n "montage " >> transient_report/index.tmp
PIXEL_POSITION_TO_MARK="*"
ORIG_FITS_IMG="$REFERENCE_IMAGE"
BASENAME_RESAMPLE_WCS_FITS_IMG="resample_wcs_"`basename "$REFERENCE_IMAGE"`
FITSFILE=${BASENAME_RESAMPLE_WCS_FITS_IMG//./_}
FITSFILE=${FITSFILE//" "/_}
echo -n $FITSFILE"__"$PIXEL_POSITION_TO_MARK"pix.png" >> transient_report/index.tmp
#
ORIG_FITS_IMG=`tail -n2 $LIGHTCURVE_FILE_OUTDAT | head -n1 | awk '{print $7}'`
BASENAME_RESAMPLE_WCS_FITS_IMG="resample_wcs_"`basename "$ORIG_FITS_IMG"`
FITSFILE=${BASENAME_RESAMPLE_WCS_FITS_IMG//./_}
FITSFILE=${FITSFILE//" "/_}
#   echo -n " "$FITSFILE"__"$PIXEL_POSITION_TO_MARK"pix.png" >> transient_report/index.tmp
   echo -n " "$FITSFILE"__"$PIXEL_POSITION_TO_MARK"pix_nofov.png" >> transient_report/index.tmp
   echo " -tile 2x1 -geometry +0+0 finder_chart_v2.png" >> transient_report/index.tmp
### Animated GIF 
   echo -n "# Create GIF animation
convert -delay 50 -loop 0   " >> transient_report/index.tmp
ORIG_FITS_IMG="$REFERENCE_IMAGE"
BASENAME_RESAMPLE_WCS_FITS_IMG="resample_wcs_"`basename "$REFERENCE_IMAGE"`
# nope, we don't have a solved image when we run this
PIXEL_POSITION_TO_MARK="*"
FITSFILE=${BASENAME_RESAMPLE_WCS_FITS_IMG//./_}
FITSFILE=${FITSFILE//" "/_}
echo -n $FITSFILE"__"$PIXEL_POSITION_TO_MARK"pix.png" >> transient_report/index.tmp
#
ORIG_FITS_IMG=`tail -n1 $LIGHTCURVE_FILE_OUTDAT | awk '{print $7}'`
BASENAME_RESAMPLE_WCS_FITS_IMG="resample_wcs_"`basename "$ORIG_FITS_IMG"`
FITSFILE=${BASENAME_RESAMPLE_WCS_FITS_IMG//./_}
FITSFILE=${FITSFILE//" "/_}
   echo -n " "$FITSFILE"__"$PIXEL_POSITION_TO_MARK"pix.png" >> transient_report/index.tmp
   echo " animation_v1.gif" >> transient_report/index.tmp
### Animated GIF v2
   echo -n "convert -delay 50 -loop 0   " >> transient_report/index.tmp
PIXEL_POSITION_TO_MARK="*"
ORIG_FITS_IMG="$REFERENCE_IMAGE"
BASENAME_RESAMPLE_WCS_FITS_IMG="resample_wcs_"`basename "$REFERENCE_IMAGE"`
FITSFILE=${BASENAME_RESAMPLE_WCS_FITS_IMG//./_}
FITSFILE=${FITSFILE//" "/_}
echo -n $FITSFILE"__"$PIXEL_POSITION_TO_MARK"pix.png" >> transient_report/index.tmp
#
ORIG_FITS_IMG=`tail -n2 $LIGHTCURVE_FILE_OUTDAT | head -n1 | awk '{print $7}'`
BASENAME_RESAMPLE_WCS_FITS_IMG="resample_wcs_"`basename "$ORIG_FITS_IMG"`
FITSFILE=${BASENAME_RESAMPLE_WCS_FITS_IMG//./_}
FITSFILE=${FITSFILE//" "/_}
   echo -n " "$FITSFILE"__"$PIXEL_POSITION_TO_MARK"pix.png" >> transient_report/index.tmp
   echo " animation_v2.gif" >> transient_report/index.tmp

   echo "
</pre>
</div>" >> transient_report/index.tmp
   #

  fi # if [ $USE_JAVASCRIPT -eq 1 ];then

  echo "<HR>" >> transient_report/index.tmp
  cat transient_report/index.tmp >> transient_report/index$1.html
 #else
 # tail -n1 transient_report/index.tmp
 # echo "The candidate $TRANSIENT_NAME did not pass the final checks"
 # rm -f transient_report/index.tmp
 #fi
done < candidates-transients.lst
if [ -f transient_report/index.tmp ];then
 rm -f transient_report/index.tmp
fi
if [ -f transient_report/index.tmp2 ];then
 rm -f transient_report/index.tmp2
fi
rm -f *_preview.png
