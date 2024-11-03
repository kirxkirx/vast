#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

function remove_all_report_transient_output_files() {
 for FILE_TO_REMOVE in transient_report/index.tmp2__report_transient_output__* exclusion_list_gaiadr2.txt__* exclusion_list_apass.txt__* exclusion_list_local.txt__* test.mpc__* ;do
  if [ -f "$FILE_TO_REMOVE" ];then
   rm -f "$FILE_TO_REMOVE"
  fi
 done
}

# MAKE_PNG_PLOTS should always be "yes" for producing finder chart images
if [ -z "$MAKE_PNG_PLOTS" ];then
 MAKE_PNG_PLOTS="yes"
 export MAKE_PNG_PLOTS
fi

if [ -z "$MPC_CODE" ];then
 # Default MPC code is C32 for tests
 MPC_CODE=C32
fi
# Check if MPC_CODE contains '@' symbol like 500@399
if [[ "$MPC_CODE" = *@* ]];then
 # No HORIZONS codes for astcheck - just the plain MPC codes please
 MPC_CODE=500
fi
# Check if the length of MPC_CODE is not equal to 3 characters
if [ ${#MPC_CODE} -ne 3 ];then
 MPC_CODE=500
fi


# Make sure there is a directory to put the report in
if [ ! -d transient_report/ ];then
# mkdir transient_report
 if ! mkdir transient_report; then
  echo "ERROR in $0: Failed to create directory transient_report/"
  exit 1
 fi
fi

if [ ! -s candidates-transients.lst ];then
 echo "No candidates found here"
 exit 0
fi

USE_JAVASCRIPT=0
grep --quiet "<script type='text/javascript'>" transient_report/index.html
if [ $? -eq 0 ];then
 USE_JAVASCRIPT=1
fi

# individual files cleanup
remove_all_report_transient_output_files

# Parallel run - ckeck candidates and create result files
# Limit the numbe of threads running in parallel
max_threads=5
thread_count=0
while read LIGHTCURVE_FILE_OUTDAT B C D E REFERENCE_IMAGE G H ;do
 
 if [ ! -s "$LIGHTCURVE_FILE_OUTDAT" ];then
  echo "WARNING: $LIGHTCURVE_FILE_OUTDAT lightcurve file does not exist!!!"
  continue
 fi
 
 {
  util/transients/report_transient.sh "$LIGHTCURVE_FILE_OUTDAT"  > transient_report/index.tmp2__report_transient_output__"$LIGHTCURVE_FILE_OUTDAT"
  if [ $? -eq 0 ];then
   touch transient_report/index.tmp2__report_transient_output__GOOD__"$LIGHTCURVE_FILE_OUTDAT"
  fi
 } &

 # Increment thread count and check if limit is reached
 thread_count=$[$thread_count+1]
 if [ "$thread_count" -ge "$max_threads" ]; then
  # Wait for all background jobs to finish before continuing
  wait
  thread_count=0
 fi
   
done < candidates-transients.lst

# Wait for all report_transient.sh processes to finish
wait

# combine all exclusion list entries from individual files created by report_transient.sh
for LISTFILE_COMBINED in exclusion_list_gaiadr2.txt exclusion_list_apass.txt exclusion_list_local.txt ;do
 for LISTFILE_INDIVIDUAL in ${LISTFILE_COMBINED}__* ;do
  if [ -f "$LISTFILE_INDIVIDUAL" ];then
   echo "Adding $LISTFILE_INDIVIDUAL to $LISTFILE_COMBINED"
   cat "$LISTFILE_INDIVIDUAL" >> "$LISTFILE_COMBINED"
   rm -f "$LISTFILE_INDIVIDUAL"
  fi
 done
done



# Searial run - read the results files and produce HTML output
while read LIGHTCURVE_FILE_OUTDAT B C D E REFERENCE_IMAGE G H ;do
 if ! rm -f transient_report/index.tmp; then
  echo "ERROR in $0: Failed to remove transient_report/index.tmp"
  exit 1
 fi
 #if ! rm -f transient_report/index.tmp2__report_transient_output; then
 # echo "ERROR in $0: Failed to remove transient_report/index.tmp2__report_transient_output"
 # exit 1
 #fi
 
 if [ ! -s "$LIGHTCURVE_FILE_OUTDAT" ];then
  echo "WARNING: $LIGHTCURVE_FILE_OUTDAT lightcurve file does not exist!!!"
  continue
 fi
 
 TRANSIENT_NAME=$(basename "$LIGHTCURVE_FILE_OUTDAT" .dat)
 TRANSIENT_NAME="${TRANSIENT_NAME/out/}"
 if [ -z "$TRANSIENT_NAME" ];then
  echo "ERROR in $0: failed to determine the transient name (1)"
  continue
 fi
 TRANSIENT_NAME="$TRANSIENT_NAME"_$(basename "$C" .fts)
 TRANSIENT_NAME=$(basename "$TRANSIENT_NAME" .fits)
 TRANSIENT_NAME=$(basename "$TRANSIENT_NAME" .fit)
 if [ -z "$TRANSIENT_NAME" ];then
  echo "ERROR in $0: failed to determine the transient name (2)"
  continue
 fi
 
 # Make nice-looking output
 echo "  "
 echo "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"
 echo "Considering the candidate $TRANSIENT_NAME"
 
 # Moved the final check here
 #util/transients/report_transient.sh "$LIGHTCURVE_FILE_OUTDAT"  > transient_report/index.tmp2__report_transient_output
 #if [ $? -ne 0 ];then
 if [ ! -f transient_report/index.tmp2__report_transient_output__GOOD__"$LIGHTCURVE_FILE_OUTDAT" ];then
  echo "The candidate $TRANSIENT_NAME did not pass the final checks"
  if [ -f transient_report/index.tmp2__report_transient_output__"$LIGHTCURVE_FILE_OUTDAT" ];then
   tail -n3 transient_report/index.tmp2__report_transient_output__"$LIGHTCURVE_FILE_OUTDAT"
   rm -f transient_report/index.tmp2__report_transient_output__"$LIGHTCURVE_FILE_OUTDAT"
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
 #####
 if [ -n "$MAKE_PNG_PLOTS" ];then
  if [ "$MAKE_PNG_PLOTS" == "yes" ];then
   # plot reference image - a zoomed-in view centered on the transient object.
   # Set PNG finding chart dimensions
   export PGPLOT_PNG_HEIGHT=400 ; export PGPLOT_PNG_WIDTH=400
   output_file="transient_report/${TRANSIENT_NAME}_reference.png"
   source_file="$(basename ${REFERENCE_IMAGE%.*}).png"
   max_attempts=3
   attempt=1
   success=false
   while [ $attempt -le $max_attempts ]; do
    # check if the file already exists somehow
    if [ -s "$output_file" ];then
     echo "The output file $output_file already exist"
     success=true
     break
    fi
    #
    if util/make_finding_chart "$REFERENCE_IMAGE" "$G" "$H" &>/dev/null; then
     #sleep 1
     if [ -f "$source_file" ]; then
      if mv "$source_file" "$output_file"; then
       echo "Successfully moved $source_file to $output_file"
       success=true
       break
      else
       echo "WARNING from $0 (attempt $attempt): Move failed. Source $source_file exists: Yes. Destination dir exists: $([ -d transient_report ] && echo 'Yes' || echo 'No')."
      fi
     else
      echo "WARNING from $0 (attempt $attempt): $source_file was not created. Retrying..."
     fi
    else
     echo "WARNING from $0 (attempt $attempt): make_finding_chart failed for $REFERENCE_IMAGE"
    fi
    attempt=$((attempt + 1))
    [ $attempt -le $max_attempts ] && echo "Retrying (attempt $attempt of $max_attempts)..." && sleep 5
   done
   if [ "$success" = false ]; then
    echo "ERROR in $0: (1) Failed to create or move $source_file to $output_file after $max_attempts attempts  util/make_finding_chart $REFERENCE_IMAGE $G $H"
   fi
   #
   unset PGPLOT_PNG_HEIGHT ; unset PGPLOT_PNG_WIDTH
  fi
 fi
 #####
 echo "<img src=\""$TRANSIENT_NAME"_reference.png\">" >> transient_report/index.tmp
 # plot reference image preview - full frame image to check for clouds, scattered light, etc
 BASENAME_REFERENCE_IMAGE=`basename $REFERENCE_IMAGE`
 REFERENCE_IMAGE_PREVIEW="$BASENAME_REFERENCE_IMAGE"_preview.png
 #####
 if [ -n "$MAKE_PNG_PLOTS" ];then
  if [ "$MAKE_PNG_PLOTS" == "yes" ];then
   # image size needs to match the one set in util/transients/transient_factory_test31.sh and below
   export PGPLOT_PNG_WIDTH=1000 ; export PGPLOT_PNG_HEIGHT=1000
   output_file="transient_report/$REFERENCE_IMAGE_PREVIEW"
   source_file="$(basename ${REFERENCE_IMAGE%.*}).png"
   max_attempts=3
   attempt=1
   success=false
   while [ $attempt -le $max_attempts ]; do
    # check if the file already exists somehow
    if [ -s "$output_file" ];then
     echo "The output file $output_file already exist"
     success=true
     break
    fi
    #
    if util/fits2png "$REFERENCE_IMAGE" &> /dev/null; then
     #sleep 1
     if [ -f "$source_file" ]; then
      if mv "$source_file" "$output_file"; then
       echo "Successfully moved $source_file to $output_file"
       success=true
       break
      else
       echo "WARNING from $0 (attempt $attempt): Move failed. Source $source_file exists: Yes. Destination dir exists: $([ -d transient_report ] && echo 'Yes' || echo 'No')."
      fi
     else
      echo "WARNING from $0 (attempt $attempt): $source_file was not created. Retrying..."
     fi
    else
     echo "WARNING from $0 (attempt $attempt): fits2png failed for $REFERENCE_IMAGE"
    fi
    attempt=$((attempt + 1))
    [ $attempt -le $max_attempts ] && echo "Retrying (attempt $attempt of $max_attempts)..." && sleep 5
   done
   if [ "$success" = false ]; then
     echo "ERROR in $0: (2) Failed to create or move $source_file to $output_file after $max_attempts attempts   util/fits2png $REFERENCE_IMAGE"
   fi
   #
   unset PGPLOT_PNG_WIDTH ; unset PGPLOT_PNG_HEIGHT
  fi
 fi
 #####                       

 #DATE=$(grep $REFERENCE_IMAGE vast_image_details.log |awk '{print $2" "$3"  "$7}')
 #rm -f tmp.description


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
   #DATE=$(grep $IMAGE vast_image_details.log |awk '{print $2" "$3"  "$7}')
   #####
   if [ -n "$MAKE_PNG_PLOTS" ];then
    if [ "$MAKE_PNG_PLOTS" == "yes" ];then
     # Set PNG finding chart dimensions
     export PGPLOT_PNG_HEIGHT=400 ; export PGPLOT_PNG_WIDTH=400
     output_file="transient_report/${TRANSIENT_NAME}_discovery${N}.png"
     source_file="$(basename ${IMAGE%.*}).png"
     max_attempts=3
     attempt=1
     success=false
     while [ $attempt -le $max_attempts ]; do
      # check if the file already exists somehow
      if [ -s "$output_file" ];then
       echo "The output file $output_file already exist"
       success=true
       break
      fi
      #
      if util/make_finding_chart "$IMAGE" "$X" "$Y" &>/dev/null; then
       # Wait for a short time to allow for I/O completion
       #sleep 1
    
       # Check if the source file exists
       if [ -f "$source_file" ]; then
        if mv "$source_file" "$output_file"; then
         echo "Successfully moved $source_file to $output_file"
         success=true
         break
        else
         echo "WARNING from $0 (attempt $attempt): Move failed. Source $source_file exists: Yes. Destination dir exists: $([ -d transient_report ] && echo 'Yes' || echo 'No')."
        fi
       else
        echo "WARNING from $0 (attempt $attempt): $source_file was not created. Retrying..."
       fi
      else
       echo "WARNING from $0 (attempt $attempt): make_finding_chart failed for $IMAGE"
      fi
      # Increment attempt counter and sleep before retry
      attempt=$((attempt + 1))
      if [ $attempt -le $max_attempts ]; then
       echo "Retrying (attempt $attempt of $max_attempts)..."
       sleep 5
      fi
     done
     if [ "$success" = false ]; then
      echo "ERROR in $0: (3) Failed to create or move $source_file to $output_file after $max_attempts attempts   util/make_finding_chart $IMAGE $X $Y"
      exit 1
     fi
     #
     unset PGPLOT_PNG_HEIGHT ; unset PGPLOT_PNG_WIDTH
    fi
   fi
   #####
   echo "<img src=\""$TRANSIENT_NAME"_discovery"$N".png\">" >> transient_report/index.tmp
   
  fi # if [ "$IMAGE" != "$REFERENCE_IMAGE" ];then
 done < $LIGHTCURVE_FILE_OUTDAT
 
 echo "</br>" >> transient_report/index.tmp
 #util/transients/report_transient.sh $LIGHTCURVE_FILE_OUTDAT  >> transient_report/index.tmp
 # if the final check passed well
 #if [ $? -eq 0 ];then

  cat transient_report/index.tmp2__report_transient_output__"$LIGHTCURVE_FILE_OUTDAT" >> transient_report/index.tmp

  #echo "</pre>" >> transient_report/index.tmp
  
  # Only do this if we are going for javascript
  if [ $USE_JAVASCRIPT -eq 1 ];then
  
   # Get constellation name
   CONSTELLATION=$(grep 'Second-epoch detections' transient_report/index.tmp | awk '{print $4}')
   if [ -z "$CONSTELLATION" ];then
    CONSTELLATION="Con"
   fi

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
      #####
      if [ -n "$MAKE_PNG_PLOTS" ];then
       if [ "$MAKE_PNG_PLOTS" == "yes" ];then
        # image size needs to match the one set in util/transients/transient_factory_test31.sh and above
        export PGPLOT_PNG_WIDTH=1000 ; export PGPLOT_PNG_HEIGHT=1000
        #
        #if [ ! -f transient_report/$PREVIEW_IMAGE ]; then
        # if util/fits2png "$IMAGE" &> /dev/null; then
        #  if ! mv "$(basename ${IMAGE%.*}).png" "transient_report/$PREVIEW_IMAGE"; then
        #   echo "ERROR in $0: Failed to move $(basename ${IMAGE%.*}).png to transient_report/$PREVIEW_IMAGE"
        #  fi # if ! mv pgplot.png "transient_report/$PREVIEW_IMAGE"; then
        # else
        #  echo "ERROR in $0: fits2png failed for $IMAGE"
        # fi # else if util/fits2png "$IMAGE" &> /dev/null; then
        #fi # if [ ! -f transient_report/$PREVIEW_IMAGE ]; then
        if [ ! -f "transient_report/$PREVIEW_IMAGE" ]; then
         max_attempts=3
         attempt=1
         success=false
         while [ $attempt -le $max_attempts ]; do
          if util/fits2png "$IMAGE" &> /dev/null; then
           if mv "$(basename ${IMAGE%.*}).png" "transient_report/$PREVIEW_IMAGE"; then
            echo "Successfully moved $(basename ${IMAGE%.*}).png to transient_report/$PREVIEW_IMAGE"
            success=true
            break
           else
            echo "WARNING from $0 (attempt $attempt): Move failed. Source $(basename ${IMAGE%.*}).png exists: $([ -f "$(basename ${IMAGE%.*}).png" ] && echo 'Yes' || echo 'No'). Destination dir exists: $([ -d transient_report ] && echo 'Yes' || echo 'No')."
           fi
          else
           echo "WARNING from $0 (attempt $attempt): fits2png failed for $IMAGE"
          fi
          attempt=$((attempt + 1))
          [ $attempt -le $max_attempts ] && echo "Retrying (attempt $attempt of $max_attempts)..." && sleep 5
         done
         if [ "$success" = false ]; then
          echo "ERROR in $0: Failed to create or move $(basename ${IMAGE%.*}).png to transient_report/$PREVIEW_IMAGE after $max_attempts attempts"
         fi
        fi # if [ ! -f transient_report/$PREVIEW_IMAGE ]; then
        #
        unset PGPLOT_PNG_WIDTH ; unset PGPLOT_PNG_HEIGHT
       fi
      fi
      #####
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
   # we are not using convert for some time now...
   # not sure if wait here is of any use now...
   #wait
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
export TELESCOP='$TELESCOP_NAME_KNOWN_TO_VaST_FOR_FOV_DETERMINATION'
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
   #if [ -f test.mpc ];then
   if [ -f test.mpc__"$LIGHTCURVE_FILE_OUTDAT" ];then
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
    #cat test.mpc | sed 's: 500: C32:g' >> transient_report/index.tmp
    #cat test.mpc__"$LIGHTCURVE_FILE_OUTDAT" | sed 's: 500: C32:g' >> transient_report/index.tmp
    # Maybe we don't need that as test.mpc__"$LIGHTCURVE_FILE_OUTDAT" should already include a correct MPC_CODE
    cat test.mpc__"$LIGHTCURVE_FILE_OUTDAT" | sed "s: 500: $MPC_CODE:g" >> transient_report/index.tmp
    echo "</pre>
Position measured on individual images:
<pre style='font-family:monospace;font-size:12px;'>" >> transient_report/index.tmp
    # We are getting DAYFRAC with fewer significant digits as we are getting it from the visual output
    grep 'Discovery image' transient_report/index.tmp | tail -n 2 | head -n1 | awk -F'>' '{print $5" "$11" "$9}' | sed 's:&nbsp;::g' | sed 's:</td::g' | sed 's:\:: :g' | awk -v mpccode="$MPC_CODE" '{printf "     TAU0008  C%s %02.0f %08.5f %02.0f %02.0f %05.2f %+03.0f %02.0f %04.1f          %4.1f R      %s\n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,mpccode}' >> transient_report/index.tmp
    grep 'Discovery image' transient_report/index.tmp | tail -n 1 | awk -F'>' '{print $5" "$11" "$9}' | sed 's:&nbsp;::g' | sed 's:</td::g' | sed 's:\:: :g' | awk -v mpccode="$MPC_CODE" '{printf "     TAU0008  C%s %02.0f %08.5f %02.0f %02.0f %05.2f %+03.0f %02.0f %04.1f          %4.1f R      %s\n",$1,$2,$3,$4,$5,$6,$7,$8,$9,$10,mpccode}' >> transient_report/index.tmp
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
    #cat test.mpc | sed 's: C2: 2:g' | awk -v val="$CONSTELLATION" '{printf "TCP %d %02d %07.4f*  %02d %02d %05.2f %+03d %02d %04.1f  %4.1f U             %s       9 0\n", $2, $3, $4,  $5, $6, $7,  $8, $9, $10,  $11,  val}' >> transient_report/index.tmp
    cat test.mpc__"$LIGHTCURVE_FILE_OUTDAT" | sed 's: C2: 2:g' | awk -v val="$CONSTELLATION" '{printf "TCP %d %02d %07.4f*  %02d %02d %05.2f %+03d %02d %04.1f  %4.1f U             %s       9 0\n", $2, $3, $4,  $5, $6, $7,  $8, $9, $10,  $11,  val}' >> transient_report/index.tmp
    echo "</pre>
<br>
</div>" >> transient_report/index.tmp
   else
    echo " ERROR: cannot find test.mpc__$LIGHTCURVE_FILE_OUTDAT <br>"
   fi
   #

   # Stub variable star reports
   echo "<a href=\"javascript:toggleElement('varstarstub_$TRANSIENT_NAME')\">Stub variable star reports</a> " >> transient_report/index.tmp  
   echo -n "<div id=\"varstarstub_$TRANSIENT_NAME\" style=\"display:none\">
Don't forget to change the observer code for the AAVSO and VSNET format data!<br>
<pre>" >> transient_report/index.tmp
if [ -z "$AAVSO_OBSCODE" ];then
 AAVSO_OBSCODE="SKA"
fi
if [ -z "$SOFTWARE_VERSION" ];then
 if [ -s vast_summary.log ];then
  SOFTWARE_VERSION=$(cat vast_summary.log | grep 'Software:' | awk '{print $2" "$3}')
 fi
 SOFTWARE_VERSION="$SOFTWARE_VERSION transient pipeline"
fi

# Reset VARIABLE_NAME 
VARIABLE_NAME=""
VARIABLE_NAME_NO_WHITESPACES=""

grep --quiet 'The object was <font color="red">found</font> in <font color="blue">VSX</font>' transient_report/index.tmp2__report_transient_output__"$LIGHTCURVE_FILE_OUTDAT"
if [ $? -eq 0 ];then
 VARIABLE_NAME=$(grep -A1 'The object was <font color="red">found</font> in <font color="blue">VSX</font>' transient_report/index.tmp2__report_transient_output__"$LIGHTCURVE_FILE_OUTDAT" | tail -n1 | awk -F'"' '{print $2}')
 # remove leading and trailing white spaces from string
 # VARIABLE_NAME will be somehting like:
 # #KR Sco                        </b>#
 VARIABLE_NAME_NO_WHITESPACES=$(echo "$VARIABLE_NAME" | awk -F'<' '{print $1}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
 VARIABLE_NAME="$VARIABLE_NAME_NO_WHITESPACES"
fi

if [ -z "$VARIABLE_NAME" ];then
 grep --quiet ' online_id ' transient_report/index.tmp2__report_transient_output__"$LIGHTCURVE_FILE_OUTDAT"
 if [ $? -eq 0 ];then
  VARIABLE_NAME=$(grep ' online_id ' transient_report/index.tmp2__report_transient_output__"$LIGHTCURVE_FILE_OUTDAT" | awk -F'|' '{print $2}')
  # remove leading and trailing white spaces from string
  VARIABLE_NAME_NO_WHITESPACES=$(echo "$VARIABLE_NAME" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  VARIABLE_NAME="$VARIABLE_NAME_NO_WHITESPACES" 
 fi
fi

# debug
#cp -v transient_report/index.tmp2__report_transient_output__"$LIGHTCURVE_FILE_OUTDAT" /tmp/"$TRANSIENT_NAME"__index.tmp2__report_transient_output

if [ -z "$VARIABLE_NAME" ];then
 VARIABLE_NAME="VARIABLE_NAME"
fi

if [ -z "$AAVSO_COMMENT_STRING" ];then
 AAVSO_COMMENT_STRING="na"
fi

# make sure there is no coma in the AAVSO notes string
AAVSO_COMMENT_STRING="${AAVSO_COMMENT_STRING//,/}"

echo   " **** AAVSO file format ****

#TYPE=EXTENDED
#OBSCODE=$AAVSO_OBSCODE
#SOFTWARE=$SOFTWARE_VERSION
#DELIM=,
#DATE=JD
#NAME,DATE,MAG,MERR,FILT,TRANS,MTYPE,CNAME,CMAG,KNAME,KMAG,AMASS,GROUP,CHART,NOTES"  >> transient_report/index.tmp
grep -A1 'Mean magnitude and position on the discovery images: ' transient_report/index.tmp | tail -n1 | awk -v val="$VARIABLE_NAME" -v aavsocomment="$AAVSO_COMMENT_STRING" '{printf "%s,%s,%s,0.05,CV,NO,STD,ENSEMBLE,na,na,na,na,1,na,%s\n", val, $4, $5, aavsocomment}' >> transient_report/index.tmp

echo   "

 **** VSNET file format ****

# Here are some valid formatiing examples:
#CETFZ 20230815.9829   <13.5CV NMW
#CETFZ 20230818.9746    12.5CV NMW
#CETFZ 20230819.9732    12.6CV NMW
#TCPJ17453768-1756253 20230831.7290 12.7CV NMW"  >> transient_report/index.tmp
grep -A1 'Mean magnitude and position on the discovery images: ' transient_report/index.tmp | tail -n1 | awk -v val="$VARIABLE_NAME" '{printf "%s %d%02d%07.4f %sCV NMW\n", val, $1, $2, $3, $5}' >> transient_report/index.tmp

echo "

The AAVSO data should be submitted to https://www.aavso.org/webobs

The VSNET data, depending on how interesting the target is, should be e-mailed to
vsnet-alert@ooruri.kusastro.kyoto-u.ac.jp
vsnet-outburst-wanted@ooruri.kusastro.kyoto-u.ac.jp
vsnet-obs@ooruri.kusastro.kyoto-u.ac.jp

" >> transient_report/index.tmp


   echo "</pre>
<br>
</div>" >> transient_report/index.tmp



   #
   TARGET_MEAN_POSITION=`grep -A1 'Mean magnitude and position on the discovery images: ' transient_report/index.tmp | tail -n1 | awk '{print $6" "$7}'`
   #
   echo "<a href=\"javascript:toggleElement('findercharts_$TRANSIENT_NAME')\">Make finder charts with VaST</a>" >> transient_report/index.tmp  
   echo -n "<div id=\"findercharts_$TRANSIENT_NAME\" style=\"display:none\">
<pre style='font-family:monospace;font-size:12px;'>
# Set SExtractor parameters file
cp default.sex.telephoto_lens_onlybrightstars_v1 default.sex
# Plate-solve the FITS images and produce the finder charts
export TELESCOP='$TELESCOP_NAME_KNOWN_TO_VaST_FOR_FOV_DETERMINATION'
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

 
 # remove_all_report_transient_output_files should take care of them
 #if [ -f transient_report/index.tmp2__report_transient_output__"$LIGHTCURVE_FILE_OUTDAT" ];then
 # rm -f transient_report/index.tmp2__report_transient_output__"$LIGHTCURVE_FILE_OUTDAT"
 #fi


done < candidates-transients.lst
if [ -f transient_report/index.tmp ];then
 rm -f transient_report/index.tmp
fi
#if [ -f transient_report/index.tmp2__report_transient_output ];then
# rm -f transient_report/index.tmp2__report_transient_output
#fi

# individual files cleanup
remove_all_report_transient_output_files

