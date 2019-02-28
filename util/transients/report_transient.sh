#!/usr/bin/env bash
#
# This script writes out a short summary about the possible transient
#
# Parse the command line arguments
if [ -z $1 ]; then
 echo "Usage: $0 outNUMBER.dat"
fi
LIGHTCURVEFILE=$1

. util/transients/transient_factory_setup.sh

# Find SExtractor
SEXTRACTOR=`command -v sex 2>/dev/null`
if [ "" = "$SEXTRACTOR" ];then
 SEXTRACTOR=lib/bin/sex
fi


# TRAP!! If we whant to identify a flare, there will be no sence to search for an asteroid on the reference image.
# Use the first discovery image instead!
REFERENCE_IMAGE=`cat vast_summary.log |grep "Ref.  image:" | awk '{print $6}'`
#     Reference image    2010 12 10.0833  2455540.5834  13.61  06:29:12.25 +26:24:19.4
echo "<table>"
echo "<tr><th></th><th>                     Date (UTC)   </th><th>    JD(UTC)  </th><th>    mag. </th><th> R.A. & Dec.(J2000)   </th><th>X & Y (pix)</th><th>    Image</th></tr>"
N=0

# Make sure there are no files with names we want to use
rm -f ra$$.dat dec$$.dat mag$$.dat dayfrac$$.dat jd$$.dat

while read JD MAG MERR X Y APP FITSFILE REST ;do
 #util/wcs_image_calibration.sh $FITSFILE $FOV &>/dev/null
 # At this point, we should somehow have a WCS calibrated image named $WCS_IMAGE_NAME
 WCS_IMAGE_NAME=wcs_`basename $FITSFILE`
 if [ ! -f $WCS_IMAGE_NAME ];then
  echo "ERROR: cannot find plate-solved image $WCS_IMAGE_NAME" >> /dev/stderr
  exit 1
 fi
 SEXTRACTOR_CATALOG_NAME="$WCS_IMAGE_NAME".cat
 if [ ! -f $SEXTRACTOR_CATALOG_NAME ];then
  $SEXTRACTOR -c `grep "SExtractor parameter file:" vast_summary.log |awk '{print $4}'` -PARAMETERS_NAME wcs.param -CATALOG_NAME $SEXTRACTOR_CATALOG_NAME $WCS_IMAGE_NAME
 fi # if [ ! -f $SEXTRACTOR_CATALOG_NAME ];then
 DATETIMEJD=`grep $FITSFILE vast_image_details.log |awk '{print $2" "$3"  "$5"  "$7}'`
 DATE=`echo $DATETIMEJD|awk '{print $1}'`
 TIME=`echo $DATETIMEJD|awk '{print $2}'`
 EXPTIME=`echo $DATETIMEJD|awk '{print $3}'`
 JD=`echo $DATETIMEJD|awk '{print $4}'`
 echo "$JD" >> jd$$.dat
 DAY=`echo $DATE |awk -F"." '{print $1}'`
 MONTH=`echo $DATE |awk -F"." '{print $2}'`
 YEAR=`echo $DATE |awk -F"." '{print $3}'` 
 TIMEH=`echo $TIME |awk -F":" '{print $1}'`
 TIMEM=`echo $TIME |awk -F":" '{print $2}'`
 TIMES=`echo $TIME |awk -F":" '{print $3}'`
 DAYFRAC=`echo "$DAY+$TIMEH/24+$TIMEM/1440+$TIMES/86400+$EXPTIME/(2*86400)" |bc -ql`
 echo "$DAYFRAC" >> dayfrac$$.dat
 RADEC=`lib/find_star_in_wcs_catalog $X $Y < $SEXTRACTOR_CATALOG_NAME`
 RA=`echo $RADEC | awk '{print $1}'`
 DEC=`echo $RADEC | awk '{print $2}'`
 echo "$RA" >> ra$$.dat
 echo "$DEC" >> dec$$.dat
 echo "$MAG" >> mag$$.dat
 MAG=`echo $MAG|awk '{printf "%.2f",$1}'`
 
 if [ "$FITSFILE" != "$REFERENCE_IMAGE" ] ;then
  #N=`echo $N+1|bc -q`
  N=$[$N+1]
  echo -n "<tr><td>Discovery image $N   &nbsp;&nbsp;</td>"
 else
  echo -n "<tr><td>Reference image     &nbsp;&nbsp;</td>"
 fi # if [ "$FITSFILE" != "$REFERENCE_IMAGE" ] ;then
 DAYFRAC=`echo $DAYFRAC |awk '{printf "%07.4f\n",$1}'` # purely for visualisation purposes
 JD=`echo $JD|awk '{printf "%.4f",$1}'` # purely for visualisation purposes
 X=`echo "$X" |awk '{printf "%04.0f",$1}'` # purely for visualisation purposes
 Y=`echo "$Y" |awk '{printf "%04.0f",$1}'` # purely for visualisation purposes
 echo "<td>$YEAR $MONTH $DAYFRAC &nbsp;&nbsp;</td><td> $JD &nbsp;&nbsp;</td><td> $MAG &nbsp;&nbsp;</td><td>" `lib/deg2hms $RADEC` "&nbsp;&nbsp;</td><td>$X $Y &nbsp;&nbsp;</td><td>$FITSFILE</td></tr>"
done < $LIGHTCURVEFILE
echo "</table>"

#lib/stat_array < ra$$.dat > script$$.dat
# We need to reformat util/colstat output to make it look like a small shell script
util/colstat < ra$$.dat 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script$$.dat
# AAAA ###################
#cp script$$.dat /tmp/
###################
if [ $? -ne 0 ];then
 echo "ERROR0001 in $0" >> /dev/strderr
 exit 1
fi
. script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0002 in $0" >> /dev/strderr
 exit 1
fi
RA_MEAN=$MEAN
# We remove '+' because bc doesn't like it
RA_MEAN=${RA_MEAN//"+"/}
RA_MAX=$MAX
RA_MAX=${RA_MAX//"+"/}
RA_MIN=$MIN
RA_MIN=${RA_MIN//"+"/}

#lib/stat_array < dec$$.dat > script$$.dat
util/colstat < dec$$.dat 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0003 in $0" >> /dev/strderr
 exit 1
fi
. script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0004 in $0" >> /dev/strderr
 exit 1
fi
DEC_MEAN=$MEAN
DEC_MEAN=${DEC_MEAN//"+"/}
DEC_MAX=$MAX
DEC_MAX=${DEC_MAX//"+"/}
DEC_MIN=$MIN
DEC_MIN=${DEC_MIN//"+"/}

#lib/stat_array < mag$$.dat > script$$.dat
util/colstat < mag$$.dat 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0005 in $0" >> /dev/strderr
 exit 1
fi
. script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0006 in $0" >> /dev/strderr
 exit 1
fi
MAG_MEAN=`echo $MEAN|awk '{printf "%.2f",$1}'`
MAG_MEAN=${MAG_MEAN//"+"/}

#lib/stat_array < dayfrac$$.dat > script$$.dat
util/colstat < dayfrac$$.dat 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0007 in $0" >> /dev/strderr
 exit 1
fi
. script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0008 in $0" >> /dev/strderr
 exit 1
fi
DAYFRAC_MEAN=`echo $MEAN|awk '{printf "%07.4f",$1}'`
DAYFRAC_MEAN_SHORT=`echo $MEAN|awk '{printf "%05.2f",$1}'`


#lib/stat_array < jd$$.dat > script$$.dat
util/colstat < jd$$.dat 2>/dev/null | sed 's: ::g' | sed 's:MAX-MIN:MAXtoMIN:g' | sed 's:MAD\*1.48:MADx148:g' | sed 's:IQR/1.34:IQRd134:g' > script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0009 in $0" >> /dev/strderr
 exit 1
fi
##########################
cp script$$.dat /tmp/script_test.tmp
cp jd$$.dat /tmp/jd_test.tmp
##########################
. script$$.dat
if [ $? -ne 0 ];then
 echo "ERROR0010 in $0" >> /dev/strderr
 exit 1
fi
JD_MEAN=`echo $MEAN |awk '{printf "%.4f",$1}'`

#### Test for float numbers ####
for STRING_TO_TEST in "$RA_MEAN" "$RA_MAX" "$RA_MIN" "$DEC_MEAN" "$DEC_MAX" "$DEC_MIN" "$MAG_MEAN" "$DAYFRAC_MEAN" "$DAYFRAC_MEAN_SHORT" "$JD_MEAN" ;do
 re='^[+-]?[0-9]+([.][0-9]+)?$'
 if ! [[ $STRING_TO_TEST =~ $re ]] ; then
  echo "ERROR in $0 : the string #$STRING_TO_TEST# is not a floating point number" >> /dev/stderr
  exit 1
 fi
done
################################


# Remove temporary files in case the script will exit after the final check
for TMP_FILE_TO_REMOVE in ra$$.dat dec$$.dat mag$$.dat script$$.dat dayfrac$$.dat jd$$.dat ;do
 if [ -f "$TMP_FILE_TO_REMOVE" ];then
  rm -f "$TMP_FILE_TO_REMOVE"
 fi
done

echo "Mean magnitude and position on the discovery images: "
echo "                   $YEAR $MONTH $DAYFRAC_MEAN  $JD_MEAN  $MAG_MEAN " `lib/deg2hms $RA_MEAN $DEC_MEAN`
#     Reference image    2010 12 10.0833  2455540.5834  13.61  06:29:12.25 +26:24:19.4

RA_MEAN_SPACES=`lib/deg2hms $RA_MEAN $DEC_MEAN | awk '{print $1}'`
RA_MEAN_SPACES=${RA_MEAN_SPACES//:/ }
DEC_MEAN_SPACES=`lib/deg2hms $RA_MEAN $DEC_MEAN | awk '{print $2}'`
DEC_MEAN_SPACES=${DEC_MEAN_SPACES//:/ }

### FINAL CHECK: make sure the transient is not jumping in RA or DEC ###
#EXTREME_POSITION_1=`lib/deg2hms $RA_MAX $DEC_MAX`
#EXTREME_POSITION_2=`lib/deg2hms $RA_MIN $DEC_MIN`
#JUMP=`lib/put_two_sources_in_one_field $EXTREME_POSITION_1 $EXTREME_POSITION_2 |grep "Angular distance" | awk '{print $5}'`
#JUMP_ARCSEC=`echo "$JUMP*3600"|bc -ql`
#echo "Maximum position difference between discovery images is $JUMP degrees ($JUMP_ARCSEC arcsec)."
# CONSERVATIVE_ASTROMETRIC_ACCURACY_ARCSEC is not defined!!!
#TEST=`echo "$JUMP_ARCSEC>$CONSERVATIVE_ASTROMETRIC_ACCURACY_ARCSEC"|bc -ql`
#if [ $TEST -eq 1 ];then
# exit 1
#fi  
### end of FINAL CHECK ###

#
# !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
#
RADEC_MEAN_HMS=`lib/deg2hms $RADEC`
RADEC_MEAN_HMS=${RADEC_MEAN_HMS//'\n'/}
RA_HMS=`echo "$RADEC_MEAN_HMS" | awk '{print $1}'`
DEC_HMS=`echo "$RADEC_MEAN_HMS" | awk '{print $2}'`

############
### Apply the exclusion list
# It may be generated from the previous-day report file using
EXCLUSION_LIST_FILE="exclusion_list.txt"
if [ ! -s "$EXCLUSION_LIST_FILE" ];then
 EXCLUSION_LIST_FILE="../exclusion_list.txt"
fi
if [ -s "$EXCLUSION_LIST_FILE" ];then
 echo "Checking $RA_HMS $DEC_HMS in the exclusion list"
 while read RA_EXLUSION_LIST DEC_EXLUSION_LIST REST_JUST_IN_CASE ;do
  lib/put_two_sources_in_one_field "$RA_EXLUSION_LIST" "$DEC_EXLUSION_LIST" "$RA_HMS" "$DEC_HMS" 2>/dev/null | grep 'Angular distance' | awk '{if ( $5 < 15/3600.0 ) print "FOUND" }' | grep "FOUND" && break
 done < "$EXCLUSION_LIST_FILE" | grep --quiet "FOUND" && echo "**** FOUND  $RA_HMS $DEC_HMS in the exclusion list ****" >> /dev/stderr && exit 1
fi 
############

lib/catalogs/check_catalogs_offline $RA_MEAN $DEC_MEAN
#util/search_databases_with_curl.sh `lib/deg2hms $RA_MEAN $DEC_MEAN` H |grep -v "Starting" |grep -v "Searching"
#util/transients/MPCheck.sh `lib/deg2hms $RADEC` $DATE $TIME H |grep -v "Starting"
util/transients/MPCheck.sh $RADEC_MEAN_HMS $DATE $TIME H |grep -v "Starting"
echo -n "<a href=\"http://simbad.u-strasbg.fr/simbad/sim-coo?Coord=$RA_MEAN%20$DEC_MEAN&CooDefinedFrames=J2000&Radius=1.0&Radius.unit=arcmin\" target=\"_blank\">Search this object in <font color=\"maroon\">SIMBAD</font>.</a>
<a href=\"http://vizier.u-strasbg.fr/viz-bin/VizieR?-source=&-out.add=_r&-out.add=_RAJ%2C_DEJ&-sort=_r&-to=&-out.max=20&-meta.ucd=2&-meta.foot=1&-c=$RA_MEAN+$DEC_MEAN&-c.rs=60\" target=\"_blank\">Search this object in <font color=\"FF9900\">VizieR</font> catalogs.</a>
<a href=\"http://skydot.lanl.gov/nsvs/cone_search.php?ra=$RA_MEAN&dec=$DEC_MEAN&rad=1&saturated=on&nocorr=on&lonpts=on&hiscat=on&hicorr=on&hisigcorr=on&radecflip=on\" target=\"_blank\">Search for previous observations of this object in the <font color=#006600>NSVS</font> database.</a>
<a href=\"http://irsa.ipac.caltech.edu/applications/wise/#id=Hydra_wise_wise_1&RequestClass=ServerRequest&DoSearch=true&schema=allsky-4band&intersect=CENTER&subsize=0.16666666800000002&mcenter=mcen&band=1,2,3,4&dpLevel=3a&UserTargetWorldPt=$RA_MEAN;$DEC_MEAN;EQ_J2000&SimpleTargetPanel.field.resolvedBy=nedthensimbad&preliminary_data=no&coaddId=&projectId=wise&searchName=wise_1&shortDesc=Position&isBookmarkAble=true&isDrillDownRoot=true&isSearchResult=true\" target=\"_blank\">Show this position in <font color=\"#FF0033\">WISE</font> atlas</a>
<a href=\"http://irsa.ipac.caltech.edu/cgi-bin/FinderChart/nph-finder?locstr=$RA_MEAN+$DEC_MEAN&markervis_shrunk=true\" target=\"_blank\"><font color=\"#339999\">2MASS</font>, <font color=\"#339999\">SDSS</font>, and <font color=\"#339999\">DSS</font> Finder Chart</a>

<FORM NAME=\"$$FORMMPC$1\" METHOD=POST TARGET=\"_blank\" ACTION=\"http://www.minorplanetcenter.net/cgi-bin/mpcheck.cgi\"><font color=\"#33CC99\">MPChecker:</font> <input type=submit value=\" Produce list \"><input type=\"hidden\" name=\"year\" maxlength=4 size=4 value=\"$YEAR\" style=\"display:none;\"><input type=\"hidden\" name=\"month\" maxlength=2 size=2 value=\"$MONTH\" style=\"display:none;\"><input type=\"hidden\" name=\"day\" maxlength=5 size=5 value=\"$DAYFRAC_MEAN_SHORT\" style=\"display:none;\"><input type=\"radio\"  name=\"which\" VALUE=\"pos\" CHECKED style=\"display:none;\"><input type=\"hidden\" name=\"ra\" maxlength=12 size=12 value=\"$RA_MEAN_SPACES\" style=\"display:none;\"><input type=\"hidden\" name=\"decl\" maxlength=12 size=12 value=\"$DEC_MEAN_SPACES\" style=\"display:none;\"><input type=\"radio\"  name=\"which\" VALUE=\"obs\" style=\"display:none;\"><textarea name=\"TextArea\" cols=81 rows=10 style=\"display:none;\"></textarea><input type=\"hidden\" name=\"radius\" maxlength=3 size=3 VALUE=\"15\" style=\"display:none;\"><input type=\"hidden\" name=\"limit\" maxlength=4 size=4 VALUE=\"16.0\" style=\"display:none;\"><input type=\"hidden\" name=\"oc\" maxlength=3 size=3 VALUE=\"500\" style=\"display:none;\"><input type=\"radio\"  name=\"sort\" VALUE=\"r\" style=\"display:none;\"><input type=\"radio\"  name=\"sort\" VALUE=\"d\" CHECKED style=\"display:none;\"><input type=\"radio\"  name=\"mot\" VALUE=\"m\" style=\"display:none;\"><input type=\"radio\"  name=\"mot\" VALUE=\"h\" CHECKED style=\"display:none;\"><input type=\"radio\"  name=\"mot\" value=\"d\" style=\"display:none;\"><input type=\"radio\"  name=\"tmot\" VALUE=\"t\" style=\"display:none;\"><input type=\"radio\"  name=\"tmot\" VALUE=\"s\" CHECKED style=\"display:none;\"><input type=\"radio\"  name=\"pdes\" VALUE=\"u\" CHECKED style=\"display:none;\"><input type=\"radio\"  name=\"pdes\" VALUE=\"p\" style=\"display:none;\"><input type=\"radio\"  name=\"needed\" VALUE=\"f\" CHECKED style=\"display:none;\"><input type=\"radio\"  name=\"needed\" VALUE=\"t\" style=\"display:none;\"><input type=\"radio\"  name=\"needed\" VALUE=\"n\" style=\"display:none;\"><input type=\"radio\"  name=\"needed\" VALUE=\"u\" style=\"display:none;\"><input type=\"radio\"  name=\"needed\" VALUE=\"N\" style=\"display:none;\"><input type=\"hidden\"  name=\"ps\" VALUE=\"n\" style=\"display:none;\"><input type=\"radio\"  name=\"type\" VALUE=\"p\" CHECKED style=\"display:none;\"><input type=\"radio\"  name=\"type\" VALUE=\"m\" style=\"display:none;\"></FORM><form NAME=\"$$FORMCATALINA$1\" method=\"post\" TARGET=\"_blank\" action=\"http://nunuku.caltech.edu/cgi-bin/getcssconedb_release_img.cgi\" enctype=\"multipart/form-data\"><font color=\"#33CC99\">Catalina photometry: </font><input type=\"hidden\" name=\"RA\"  size=\"12\" maxlength=\"20\" value=\"$RA_MEAN\" /><input type=\"hidden\" name=\"Dec\"  size=\"12\" maxlength=\"20\" value=\"$DEC_MEAN\" /><input type=\"hidden\" name=\"Rad\"  size=\"5\" maxlength=\"10\" value=\"0.1\" /><input type=\"hidden\" name=\"IMG\" value=\"dss\" /><input type=\"hidden\" name=\"IMG\" value=\"nun\" checked=\"checked\" /><input type=\"hidden\" name=\"IMG\" value=\"sdss\" /><input type=\"hidden\" name=\"DB\" value=\"photcat\" checked=\"checked\" /><input type=\"hidden\" name=\"D=0>value=\"orphancat\" /><input type=\"submit\" name=\".submit\" value=\"Submit\" /><input type=\"hidden\" name=\"OUT\" value=\"web\" /><input type=\"hidden\" name=\"OUT\" value=\"csv\" checked=\"checked\" /><input type=\"hidden\" name=\"OUT\" value=\"vot\" /><input type=\"hidden\" name=\"SHORT\" value=\"short\" checked=\"checked\" /><input type=\"hidden\" name=\"SHORT\" value=\"long\" /><input type=\"hidden\" name=\"PLOT\" value=\"plot\" checked=\"checked\" /></form><form NAME=\"$$FORMNMW$1\" method=\"get\" TARGET=\"_blank\" action=\"http://scan.sai.msu.ru/cgi-bin/nmw/sky_archive\" enctype=\"application/x-www-form-urlencoded\"><font color=\"#33CC99\">NMW image archive: </font><input id=\"h2\" name=\"ra\" type=\"hidden\" required value=\"$RA_HMS\"><input id=\"h3\" name=\"dec\" type=\"hidden\" required value=\"$DEC_HMS\">image size <input id=\"h4\" name=\"r\" type=\"text\" required=\"\" value=\"32\" size=\"3\">(pix) <input type=\"submit\"></form>"
# Show the ASAS only for sources with declination below +28 
TEST=`echo "($DEC_MEAN)<28" |bc -ql`
re='^[0-9]+$'
if ! [[ $TEST =~ $re ]] ; then
 echo "TEST ERROR in ($DEC_MEAN)<28" >> /dev/stderr
 exit 1
else
 if [ $TEST -eq 1 ];then
  echo -n "<form NAME=\"$$FORMASAS$1\" ACTION='http://www.astrouw.edu.pl/cgi-asas/asas_cat_input' METHOD=POST TARGET=\"data_list\">Get <font color=\"#33CC00\">ASAS</font> lightcurve: <input type='radio' name='source' value='asas3' CHECKED style=\"display:none;\"><TEXTAREA NAME='coo' ROWS=1 COLS=30 WRAP=virtual style=\"display:none;\">$RADEC_MEAN_HMS</TEXTAREA><INPUT NAME=equinox VALUE=2000 SIZE=4 style=\"display:none;\"><INPUT NAME=nmin VALUE=4 SIZE=4 style=\"display:none;\"><INPUT NAME=box VALUE=15 SIZE=4 style=\"display:none;\"><INPUT TYPE=submit NAME=submit VALUE=\"Search\" ></form>"
 fi
fi

exit 0
# everything is fine!
