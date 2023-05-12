#!/usr/bin/env bash

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=$(readlink -f "$1" 2>/dev/null)
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=$(greadlink -f "$1" 2>/dev/null)
   if [ $? -ne 0 ];then
    REALPATH=$(realpath "$1" 2>/dev/null)
    if [ $? -ne 0 ];then
     REALPATH=$(grealpath "$1" 2>/dev/null)
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")" || exit
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD" || exit
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

function print_usage {
 echo "
Usage: $0 RA DEC [STAR_NAME] [FOV_arcmin]

Example: $0 18:38:06.47677 +39:40:05.9835

"
}

if [ -z "$VAST_PATH" ];then
 #VAST_PATH=`readlink -f $0`
 VAST_PATH=$(vastrealpath $0)
 VAST_PATH=$(dirname "$VAST_PATH")
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:/'/:/:g")
 # Make sure no quotation marks are left in VAST_PATH
 VAST_PATH=$(echo "$VAST_PATH" | sed "s:'::g")
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
#

#VIZIER_SITE=vizier.u-strasbg.fr
VIZIER_SITE=$("$VAST_PATH"lib/choose_vizier_mirror.sh)
#
echo -e "Starting $0" 1>&2

### Set path to wwwget in lib/bin/
echo "$PATH" | grep --quiet "$VAST_PATH"lib/bin
if [ $? -ne 0 ];then
 #export PATH="$VAST_PATH"lib/bin":$PATH"
 NEWPATH="$VAST_PATH"lib/bin
 #export PATH="$VAST_PATH:$PATH"
 export PATH="$NEWPATH:$PATH"
fi

### 
TIMEOUTCOMMAND=$("$VAST_PATH"lib/find_timeout_command.sh)
if [ $? -ne 0 ];then
 echo "WARNING: cannot find timeout command"
 LONGTIMEOUTCOMMAND=""
else
 LONGTIMEOUTCOMMAND="$TIMEOUTCOMMAND 300 "
 TIMEOUTCOMMAND="$TIMEOUTCOMMAND 100 "
fi

######
RA=$1
# Handle coma as RA Dec separator
if [ -z "$2" ];then
 echo "$RA" | grep --quiet -e ',+' -e ',-' -e ',[0-9]'
 DEC=$(echo $RA | awk -F',' '{print $2}')
 RA=$(echo $RA | awk -F',' '{print $1}')
 echo "RA=#$RA#  DEC=#$DEC#"
else
 DEC=$2
fi
# Handle a coma in RA
RA=${RA/','/''}
# Get rid of any remaining white spaces
RA=${RA//' '/''}
DEC=${DEC//' '/''}
#
###### Test the command line arguments #####
if [ -z "$RA" ] || [ -z "$DEC" ];then
 echo "ERROR: search coordinates are not given! :("
 print_usage
 exit 1
fi   

# Check if the input coordinates are good
if "$VAST_PATH"lib/hms2deg "$RA" "$DEC" &>/dev/null || "$VAST_PATH"lib/deg2hms "$RA" "$DEC" &>/dev/null ;then echo YES ;fi | grep --quiet 'YES'
if [ $? -ne 0 ];then
 echo "ERROR parsing the input coordinates!"
 exit 1
fi


if [ -z "$3" ];then
 echo "The object name is not specified on the command line, using the default one"
 STAR_NAME="object"
else
 STAR_NAME=$3
fi

if [ -z "$4" ];then
 echo "The field of view is not specified on the command line, using the default one"
 FOV=1.0
else
 # Check if $4 looks like a field of view in arcminutes
 re='^[0-9]+([.][0-9]+)?$'
 if ! [[ $4 =~ $re ]] ; then
  echo "ERROR: argument 4 #$4# does not look like a field of view in arcminutes, using the default value instead"
  FOV=1.0
 else
  TEST=$(echo "$4<1.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
  if [ $TEST -eq 1 ];then
   echo "ERROR: the specified field of view ($4 arcmin) seems too small, using the default value instead"
   FOV=1.0
  else
   TEST=$(echo "$4>2700" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    echo "ERROR: the specified field of view ($4 arcmin) seems too large, using the default value instead"
    FOV=1.0
   else
    echo "Setting the field of view ($4 arcmin) specified on the command line"
    FOV=$4
   fi
  fi
 fi
fi

###### 2MASS #####
R_SEARCH_ARCSEC=2.5
echo "Searching 2MASS $R_SEARCH_ARCSEC\" around $RA $DEC"
$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=2MASS  -out.max=1 -out.add=_r -out.form=mini  -sort=_r  -c="$RA $DEC" -c.rs=$R_SEARCH_ARCSEC -out=Jmag,e_Jmag,Kmag,e_Kmag  2>/dev/null |grep -v \# | grep -v "_" | grep -v "\---" |grep -v "sec"  | while read -r R J eJ K eK REST ;do
 if [ -n "$R" ];then
  if [ -z "$J" ];then
   continue
  fi
  re='^[+-]?[0-9]+([.][0-9]+)?$'
  if ! [[ $J =~ $re ]] ; then
   continue
  fi
  if [ -z "$K" ];then
   continue
  fi
  if ! [[ $K =~ $re ]] ; then
   continue
  fi
  # Compute J-K
  #J_K=`echo "($J)-($K)" | bc -ql | awk '{printf "%.3f",$1}'`
  J_K=$(echo "$J $K" | awk '{printf "%.3f",$1-$2}')
  if [[ $eJ =~ $re ]] && [[ $eK =~ $re ]] ; then
   #eJ_K=`echo "sqrt($eJ*$eJ+$eK*$eK)" | bc -ql | awk '{printf "%.3f",$1}'`  
   eJ_K=$(echo "$eJ $eK" | awk '{printf "%.3f", sqrt( $1*$1 + $2*$2 ) }')
  else
   eJ_K="     "
  fi
  if [ -n "$J_K" ];then
   # Guess spectral type *assuming zero extinction*
   #
   # The old color boundaries between the spectral types were based on http://adsabs.harvard.edu/abs/1988PASP..100.1134B
   #
   # The new ones are from
   # "A Modern Mean Dwarf Stellar Color and Effective Temperature Sequence"
   # http://www.pas.rochester.edu/~emamajek/EEM_dwarf_UBVIJHK_colors_Teff.txt
   # Eric Mamajek
   # Version 2021.03.02
   # 
   SECTRAL_TYPE="unrealisitic color!"
   # Wild guess
   #TEST=`echo "$J_K > -1.0"|bc -ql`
   TEST=$(echo "$J_K>-1.0" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="Very blue!"
   fi
   #TEST=`echo "$J_K > -0.3"|bc -ql`
   TEST=$(echo "$J_K>-0.3" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="O"
   fi
   #TEST=`echo "$J_K > -0.230"|bc -ql`
   #TEST=`echo "$J_K > -0.228"|bc -ql`
   TEST=$(echo "$J_K>-0.228" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="B"
   fi
   #TEST=`echo "$J_K > 0.0"|bc -ql`
   #TEST=`echo "$J_K > -0.0135"|bc -ql`
   TEST=$(echo "$J_K>-0.0135" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="A"
   fi
   #TEST=`echo "$J_K > 0.16"|bc -ql`
   #TEST=`echo "$J_K > 0.132"|bc -ql`
   #TEST=`echo "$J_K>0.132" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
   TEST=$(echo "$J_K>0.1355" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="F"
   fi
   #TEST=`echo "$J_K > 0.36"|bc -ql`
   #TEST=`echo "$J_K > 0.3215"|bc -ql`
   TEST=$(echo "$J_K>0.3215" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="G"
   fi
   #TEST=`echo "$J_K > 0.53"|bc -ql`
   #TEST=`echo "$J_K > 0.465"|bc -ql`
   #TEST=`echo "$J_K>0.465" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
   TEST=$(echo "$J_K>0.46450" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="K"
   fi
   #TEST=`echo "$J_K > 0.86"|bc -ql`
   #TEST=`echo "$J_K > 0.814"|bc -ql`
   TEST=$(echo "$J_K>0.814" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="M"
   fi
   TEST=$(echo "$J_K>1.2575" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="Very red! L if it's a dwarf"
   fi
   #TEST=`echo "$J_K > 1.5"|bc -ql`
   #TEST=`echo "$J_K>1.5" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }'`
   TEST=$(echo "$J_K>1.77" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="Very red!"
   fi
   #TEST=`echo "$J_K > 4.0"|bc -ql`
   TEST=$(echo "$J_K>4.0" | awk -F'>' '{if ( $1 > $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="unrealisitic color!"
   fi
  else
   SECTRAL_TYPE="Sorry, cannot get 2MASS color"
  fi # if [ -n $J_K ];then
  # Print results
  echo "r=$R\" J = $J +/-$eJ  Ks = $K +/-$eK  J-Ks =  $J_K +/-$eJ_K  ($SECTRAL_TYPE)"
  #echo "Spectral type is according to Bessell & Brett (1988, PASP, 100, 1134) *assuming zero extinction*."
  echo "Spectral type is according to the table
'A Modern Mean Dwarf Stellar Color and Effective Temperature Sequence'
http://www.pas.rochester.edu/~emamajek/EEM_dwarf_UBVIJHK_colors_Teff.txt
Version 2021.03.02 by Eric Mamajek
http://adsabs.harvard.edu/abs/2013ApJS..208....9P

This is the spectral type *assuming zero extinction*"
  echo "J-Ks=$J_K+/-$eJ_K ($SECTRAL_TYPE)" > 2mass.tmp
 fi
done

# clean-up after vizquery
if [ -f wget-log ];then
 rm -f wget-log
fi

echo "Image field of view: $FOV"

###### USNO-B1 #####
# by default we don't have an ID
if [ -f search_databases_with_vizquery_USNOB_ID_OK.tmp ];then
 rm -f search_databases_with_vizquery_USNOB_ID_OK.tmp
fi
####
#R_SEARCH_ARCSEC=`echo "3.0*($FOV/60)" | bc -ql | awk '{printf "%.1f",$1}'`
R_SEARCH_ARCSEC=$(echo "$FOV" | awk '{printf "%.1f",3.0*($1/60)}')
B2MAG_RANGE="B2mag=1.0..12.5"
#TEST=`echo "$FOV<400.0" | bc -ql`
TEST=$(echo "$FOV<400.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
# R_SEARCH_ARCSEC=`echo "3.0*($FOV/60)" | bc -ql | awk '{printf "%.1f",$1}'`
 B2MAG_RANGE="B2mag=1.0..15.5"
fi
#TEST=`echo "$FOV<240.0" | bc -ql`
TEST=$(echo "$FOV<240.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
# R_SEARCH_ARCSEC=`echo "3.0*($FOV/60)" | bc -ql | awk '{printf "%.1f",$1}'`
 B2MAG_RANGE="B2mag=1.0..16.5"
fi
#TEST=`echo "$FOV<120.0" | bc -ql`
TEST=$(echo "$FOV<120.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
 R_SEARCH_ARCSEC=3.0
 B2MAG_RANGE="B2mag=1.0..17.5"
fi
#TEST=`echo "$FOV<60.0" | bc -ql`
TEST=$(echo "$FOV<60.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
 R_SEARCH_ARCSEC=3.0
 B2MAG_RANGE="B2mag=1.0..18.5"
fi
#TEST=`echo "$FOV<30.0" | bc -ql`
TEST=$(echo "$FOV<30.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
 R_SEARCH_ARCSEC=1.5
 B2MAG_RANGE="B2mag=1.0..20.5"
fi
####
#echo "#### DEBUG R_SEARCH_ARCSEC=$R_SEARCH_ARCSEC FOV=$FOV" 1>&2
####
#DOUBLE_R_SEARCH_ARCSEC=`echo "$R_SEARCH_ARCSEC*2" | bc -ql`
DOUBLE_R_SEARCH_ARCSEC=$(echo "$R_SEARCH_ARCSEC" | awk '{print 2*$1}')
echo " "
echo "Searching USNO-B1.0 for the brightest objects within $R_SEARCH_ARCSEC\" around $RA $DEC in the range of $B2MAG_RANGE"
#echo " "
echo "$LONGTIMEOUTCOMMAND $VAST_PATH""lib/vizquery -site=$VIZIER_SITE -mime=text -source=USNO-B1 -out.max=10 -out.add=_r -out.form=mini -sort=B2mag  -c="$RA $DEC" $B2MAG_RANGE -c.rs=$R_SEARCH_ARCSEC -out=USNO-B1.0,RAJ2000,DEJ2000,B2mag,B1mag"
$LONGTIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=USNO-B1 -out.max=10 -out.add=_r -out.form=mini -sort=B2mag  -c="$RA $DEC" $B2MAG_RANGE -c.rs=$R_SEARCH_ARCSEC -out=USNO-B1.0,RAJ2000,DEJ2000,B2mag,B1mag  2>/dev/null | grep -v \# | grep -v "_" | grep -v "\---" |grep -v "sec"  |grep -v "RAJ" |grep -v "B" | while read -r R USNOB1 CATRA_DEG CATDEC_DEG B2 B1 REST ;do
 # skip stars with unknown B2mag
 if [ -z "$B2" ] ;then
  continue
 fi
 # skip stars with unknown B1mag
 if [ -z "$B1" ] ;then
  continue
 fi
 # skip empty lines if for whatever reason they were not caught before
 if [ -n "$R" ] ;then
  # Skip too faint stars
  #TEST=`echo "($B2+$B1)/2.0>18.0"|bc -ql`
  TEST=$(echo "$B2 $B1"| awk '{if ( ($1+$2)/2.0 > 18.0 ) print 1 ;else print 0 }')
  if [ $TEST -eq 1 ];then
   continue
  fi
  GOOD_CATALOG_POSITION=$("$VAST_PATH"lib/deg2hms "$CATRA_DEG" "$CATDEC_DEG")
  GOOD_CATALOG_POSITION_REF="(USNO-B1.0)"
  #
  GOOD_CATALOG_NAME_USNOB=$USNOB1
  # mark that we have an ID
  echo "$GOOD_CATALOG_POSITION 
$GOOD_CATALOG_NAME_USNOB" > search_databases_with_vizquery_USNOB_ID_OK.tmp
  echo "***************************************"
  echo "r=$R\" $USNOB1 $GOOD_CATALOG_POSITION B2=$B2"
  echo "***************************************"
  break
 fi
done


###### GAIA DR3 #####
# by default we don't have an ID
if [ -f search_databases_with_vizquery_GAIA_ID_OK.tmp ];then
 rm -f search_databases_with_vizquery_GAIA_ID_OK.tmp
fi
####
#R_SEARCH_ARCSEC=`echo "3.0*($FOV/60)" | bc -ql | awk '{printf "%.1f",$1}'`
R_SEARCH_ARCSEC=$(echo "$FOV" | awk '{printf "%.1f",3.0*($1/60)}')
GMAG_RANGE="Gmag=1.0..12.5"
#TEST=`echo "$FOV<400.0" | bc -ql`
TEST=$(echo "$FOV<400.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
# R_SEARCH_ARCSEC=`echo "3.0*($FOV/60)" | bc -ql | awk '{printf "%.1f",$1}'`
 GMAG_RANGE="Gmag=1.0..15.5"
fi
#TEST=`echo "$FOV<240.0" | bc -ql`
TEST=$(echo "$FOV<240.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
# R_SEARCH_ARCSEC=`echo "3.0*($FOV/60)" | bc -ql | awk '{printf "%.1f",$1}'`
 GMAG_RANGE="Gmag=1.0..16.5"
fi
#TEST=`echo "$FOV<120.0" | bc -ql`
TEST=$(echo "$FOV<120.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
 R_SEARCH_ARCSEC=3.0
 GMAG_RANGE="Gmag=1.0..17.5"
fi
#TEST=`echo "$FOV<60.0" | bc -ql`
TEST=$(echo "$FOV<60.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
 R_SEARCH_ARCSEC=3.0
 GMAG_RANGE="Gmag=1.0..18.5"
fi
#TEST=`echo "$FOV<30.0" | bc -ql`
TEST=$(echo "$FOV<30.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
if [ $TEST -eq 1 ];then
 R_SEARCH_ARCSEC=1.5
 GMAG_RANGE="Gmag=1.0..20.5"
fi
####
#DOUBLE_R_SEARCH_ARCSEC=`echo "$R_SEARCH_ARCSEC*2" | bc -ql`
DOUBLE_R_SEARCH_ARCSEC=$(echo "$R_SEARCH_ARCSEC" | awk '{print 2*$1}')
echo " "
echo "Searching Gaia DR3 for the brightest objects within $R_SEARCH_ARCSEC\" around $RA $DEC in the range of $GMAG_RANGE"
echo "$LONGTIMEOUTCOMMAND $VAST_PATH""lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/355/gaiadr3 -out.max=10 -out.add=_r -out.form=mini -sort=Gmag  -c='$RA $DEC' $GMAG_RANGE -c.rs=$R_SEARCH_ARCSEC -out=Source,RA_ICRS,DE_ICRS,Gmag,VarFlag"
$LONGTIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=I/355/gaiadr3 -out.max=10 -out.add=_r -out.form=mini -sort=Gmag  -c="$RA $DEC" $GMAG_RANGE -c.rs=$R_SEARCH_ARCSEC -out=Source,RA_ICRS,DE_ICRS,Gmag,VarFlag 2>/dev/null | grep -v \# | grep -v "\---" |grep -v "sec" | grep -v 'Gma' |grep -v "RA_ICRS" | grep -e 'NOT_AVAILABLE' -e 'CONSTANT' -e 'VARIABLE' | while read -r R GAIA_SOURCE GAIA_CATRA_DEG GAIA_CATDEC_DEG GMAG VARFLAG REST ;do
 # skip stars with unknown Gmag
 if [ -z "$GMAG" ] ;then
  continue
 fi
 # skip empty lines if for whatever reason they were not caught before
 if [ -n "$R" ] ;then
  ######################################################################################
  # Do not drop faint Gaia stars if we have good astrometry
  SHOULD_WE_DROP_FAINT_GAIA_STARS=1
  TEST=$(echo "$FOV<30.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
  if [ $TEST -eq 1 ];then
   TEST=$(echo "$R<0.2" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    SHOULD_WE_DROP_FAINT_GAIA_STARS=0
   fi
  fi
  if [ $SHOULD_WE_DROP_FAINT_GAIA_STARS -eq 1 ];then
   # Skip too faint stars
   #TEST=`echo "$GMAG>18.0"|bc -ql`
   TEST=$(echo "$GMAG"| awk -F'>' '{if ( $1 > 18.0 ) print 1 ;else print 0 }')
   if [ $TEST -eq 1 ];then
    continue
   fi
  fi # if [ $SHOULD_WE_DROP_FAINT_GAIA_STARS -eq 1 ];then
  ######################################################################################
  GOOD_CATALOG_POSITION_GAIA=$("$VAST_PATH"lib/deg2hms $GAIA_CATRA_DEG $GAIA_CATDEC_DEG)
  GOOD_CATALOG_POSITION_REF="(Gaia DR3)"
  #
  GOOD_CATALOG_NAME_GAIA=$GAIA_SOURCE
  # mark that we have an ID
  echo "$GOOD_CATALOG_POSITION_GAIA 
$GOOD_CATALOG_NAME_GAIA
$VARFLAG" > search_databases_with_vizquery_GAIA_ID_OK.tmp
  echo "***************************************"
  echo "r=$R\" $GAIA_SOURCE $GOOD_CATALOG_POSITION_GAIA G=$GMAG Variability_flag=$VARFLAG"
  echo "***************************************"
  break
 fi
done






# Check if we have the USNO-B1.0 ID
if [ ! -f search_databases_with_vizquery_USNOB_ID_OK.tmp ];then
 echo "Could not match the source with USNO-B1.0 :("
else
 GOOD_CATALOG_POSITION_USNOB=$(head -n1 search_databases_with_vizquery_USNOB_ID_OK.tmp)
 GOOD_CATALOG_POSITION="$GOOD_CATALOG_POSITION_USNOB"
 GOOD_CATALOG_NAME_USNOB=$(tail -n1 search_databases_with_vizquery_USNOB_ID_OK.tmp)
 GOOD_CATALOG_NAME="B1.0 $GOOD_CATALOG_NAME_USNOB"
 rm -f search_databases_with_vizquery_USNOB_ID_OK.tmp
fi
# Check if we have the Gaia ID
if [ ! -f search_databases_with_vizquery_GAIA_ID_OK.tmp ];then
 echo "Could not match the source with Gaia DR3 :("
else
 GOOD_CATALOG_POSITION_GAIA=$(head -n1 search_databases_with_vizquery_GAIA_ID_OK.tmp)
 GOOD_CATALOG_POSITION="$GOOD_CATALOG_POSITION_GAIA"
 GOOD_CATALOG_POSITION_REF="(Gaia DR3)"
 GOOD_CATALOG_NAME_GAIA=$(head -n2 search_databases_with_vizquery_GAIA_ID_OK.tmp | tail -n1)
 GOOD_CATALOG_NAME="Gaia DR3 $GOOD_CATALOG_NAME_GAIA"
 VARFLAG=$(tail -n1 search_databases_with_vizquery_GAIA_ID_OK.tmp)
 while [ ${#VARFLAG} -lt 13 ];do
  VARFLAG="$VARFLAG "
 done

 SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING Gaia3var=$VARFLAG "
 rm -f search_databases_with_vizquery_GAIA_ID_OK.tmp
 # Get additional variability info from Gaia
# # Gaia short-time var
# $TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/shortts -out.max=10 -out.form=mini Source="$GOOD_CATALOG_NAME_GAIA" 2>/dev/null | grep -v \# | grep --quiet "$GOOD_CATALOG_NAME_GAIA"
# if [ $? -eq 0 ];then
#  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING Gaia2_SHORTTS "
# fi
# # Gaia Cepheids
# $TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/cepheid -out.max=10 -out.form=mini Source="$GOOD_CATALOG_NAME_GAIA" 2>/dev/null | grep -v \# | grep --quiet "$GOOD_CATALOG_NAME_GAIA"
# if [ $? -eq 0 ];then
#  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING Gaia2_CEPHEID "
# fi
# # Gaia RR Lyrae
# $TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/rrlyrae -out.max=10 -out.form=mini Source="$GOOD_CATALOG_NAME_GAIA" 2>/dev/null | grep -v \# | grep --quiet "$GOOD_CATALOG_NAME_GAIA"
# if [ $? -eq 0 ];then
#  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING Gaia2_RRLYR "
# fi
# # Gaia LPV
# $TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/lpv -out.max=10 -out.form=mini Source="$GOOD_CATALOG_NAME_GAIA" 2>/dev/null | grep -v \# | grep --quiet "$GOOD_CATALOG_NAME_GAIA"
# if [ $? -eq 0 ];then
#  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING Gaia2_LPV "
# fi
 #
fi

# Handle the case where there is no good catalog match
if [ -z "$GOOD_CATALOG_POSITION" ];then
 GOOD_CATALOG_POSITION="$RA $DEC"
 echo "Will use the input corrdicates as the target position (as there is no deep catalog match)
$GOOD_CATALOG_POSITION"
 GOOD_CATALOG_POSITION_GAIA="$GOOD_CATALOG_POSITION"
 GOOD_CATALOG_POSITION_REF=" (user input)"
 GOOD_CATALOG_NAME="target"
 GOOD_CATALOG_NAME_GAIA="$GOOD_CATALOG_NAME"
 SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING (position from user input) "
fi

###### ID with variability catalogs and write summary string #####
KNOWN_VARIABLE=0
echo "
Summary string (old format):"

# Local catalogs
if [ $KNOWN_VARIABLE -eq 0 ];then
 GOOD_CATALOG_POSITION_DEG=$("$VAST_PATH"lib/hms2deg $GOOD_CATALOG_POSITION 2>/dev/null)
 if [ $? -ne 0 ];then
  # The input position is already in decimal degrees
  GOOD_CATALOG_POSITION_DEG="$GOOD_CATALOG_POSITION"
 fi
 # Warn the user that lib/catalogs/check_catalogs_offline might need to download a catalog
 if [ ! -f "$VAST_PATH"lib/catalogs/asassnv.csv ] || [ ! -f "$VAST_PATH"lib/catalogs/vsx.dat ];then
  echo "
WARNING: cannot find catalogs lib/catalogs/asassnv.csv and/or lib/catalogs/vsx.dat
The script will try to download these catalogs now - it will take some time!
" >&2
 fi
 ######
 ######
 LOCAL_CATALOG_SEARCH_RESULTS=$("$VAST_PATH"lib/catalogs/check_catalogs_offline $GOOD_CATALOG_POSITION_DEG 2>/dev/null)
 if [ $? -eq 0 ];then
  # The object is found in local catalogs
  # Mac doesn't allow '-m1 -A1' combination for grep (!!!)
  #LOCAL_NAME=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep -m1 -A1 '>found<' | tail -n1 | awk '{print $2}' FS='"' | sed 's:MASTER OT:MASTER_OT:g'`  
  # | awk '{$1=$1;print}' Would trim leading and trailing space or tab characters and also squeeze sequences of tabs and spaces into a single space. https://unix.stackexchange.com/questions/102008/how-do-i-trim-leading-and-trailing-whitespace-from-each-line-of-some-output
  #LOCAL_NAME=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep -A 1 '>found<' | tail -n 1 | awk '{print $2}' FS='"' | sed 's:MASTER OT:MASTER_OT:g' | awk '{$1=$1;print}'`  
  LOCAL_NAME=$(echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep -A 1 '>found<' | tail -n 1 | awk -F '"' '{print $2}' | sed 's:MASTER OT:MASTER_OT:g' | awk '{$1=$1;print}')
  #LOCAL_TYPE=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep 'Type:' | awk '{print $2}' FS='Type:' | awk '{$1=$1;print}'`
  LOCAL_TYPE=$(echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep 'Type:' | awk -F 'Type:' '{print $2}' | awk '{$1=$1;print}')
  #LOCAL_PERIOD=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep -m1 -A1 '#   Max.' | tail -n1 | sed 's:)::g' | sed 's:(::g' | awk '{print $6}'`
  LOCAL_PERIOD=$(echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep -A 1 '#   Max.' | tail -n 1 | sed 's:)::g' | sed 's:(::g' | awk '{print $6}')
  if [ -z "$LOCAL_PERIOD" ];then
   #LOCAL_PERIOD=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep 'Period' | awk '{print $2}' FS='Period' | awk '{print $1}'`
   LOCAL_PERIOD=$(echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep 'Period' | awk -F 'Period' '{print $2}' | awk '{print $1}')
  fi
  SUGGESTED_NAME_STRING="$LOCAL_NAME"
  SUGGESTED_TYPE_STRING="$LOCAL_TYPE (local)"
  SUGGESTED_PERIOD_STRING="$LOCAL_PERIOD (local)"
  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING "
  KNOWN_VARIABLE=1
 fi
fi

# GCVS
if [ $KNOWN_VARIABLE -eq 0 ];then 
 GCVS_RESULT=$($TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=B/gcvs -out.max=1 -out.form=mini   -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=GCVS,VarType,Period 2>/dev/null  | grep -v \# | grep -v "_" | grep -v "\---" | grep -v "GCVS" |head -n2 |tail -n 1)
 GCVS_V=$(echo "$GCVS_RESULT" | awk '{print $1}')
 if [ "$GCVS_V" != "" ] ;then
  # STAR FROM GCVS
  GCVS_CONSTEL=$(echo "$GCVS_RESULT" | awk '{print $2}')
  GCVS_TYPE=$(echo "$GCVS_RESULT" | awk '{print $3}')
  GCVS_PERIOD=$(echo "$GCVS_RESULT" | awk '{print $4}')
  #echo -n " $STAR_NAME | $GCVS_V $GCVS_CONSTEL | $GOOD_CATALOG_POSITION | $GCVS_TYPE (GCVS) | $GCVS_PERIOD (GCVS) | "
  SUGGESTED_NAME_STRING="$GCVS_V $GCVS_CONSTEL"
  SUGGESTED_TYPE_STRING="$GCVS_TYPE (GCVS)"
  SUGGESTED_PERIOD_STRING="$GCVS_PERIOD (GCVS)"
  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING "
  KNOWN_VARIABLE=1
 fi
fi
if [ $KNOWN_VARIABLE -eq 0 ];then
 VSX_RESULT=$($TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=B/vsx -out.max=1 -out.form=mini   -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=Name,Type,Period 2>/dev/null | grep -v \# | grep -v "_" | grep -v "\---" | grep -A 1 Name | tail -n1 | sed 's:MASTER OT:MASTER_OT:g')
 #echo "########$VSX_RESULT#########"
 VSX_V=$(echo "$VSX_RESULT" | awk '{print $1}')
 if [ "$VSX_V" != "" ] ;then
  # STAR FROM VSX
  VSX_NAME=$(echo "$VSX_RESULT" | awk '{print $2}')
  VSX_TYPE=$(echo "$VSX_RESULT" | awk '{print $3}')
  VSX_PERIOD=$(echo "$VSX_RESULT" | awk '{print $4}')
  # Special case - OGLE one-word variable names
  echo "$VSX_V" | grep --quiet 'OGLE-'
  if [ $? -eq 0 ];then
   VSX_V=""
   VSX_NAME=$(echo "$VSX_RESULT" | awk '{print $1}')
   VSX_TYPE=$(echo "$VSX_RESULT" | awk '{print $2}')
   VSX_PERIOD=$(echo "$VSX_RESULT" | awk '{print $3}')
  fi
  #
  #echo -n " $STAR_NAME | $VSX_V $VSX_NAME | $GOOD_CATALOG_POSITION | $VSX_TYPE (VSX) | $VSX_PERIOD (VSX) | "
  SUGGESTED_NAME_STRING="$VSX_V $VSX_NAME"
  SUGGESTED_TYPE_STRING="$VSX_TYPE (VSX)"
  SUGGESTED_PERIOD_STRING="$VSX_PERIOD (VSX)"
  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING "
  KNOWN_VARIABLE=1
 else
  # Handle the special case: the stars is in the VSX database but not in the VSX copy at CDS
  VSX_ONLINE_NAME=$("$VAST_PATH"util/search_databases_with_curl.sh "$RA" "$DEC" 2>/dev/null | grep -v "not found" | grep -A 1 "The object was" | grep -A 1 "found" | grep -A 1 "VSX" | tail -n1)
  if [ "$VSX_ONLINE_NAME" != "" ] ;then
   #echo -n " $STAR_NAME | $VSX_ONLINE_NAME | $GOOD_CATALOG_POSITION | T | P | "
   SUGGESTED_NAME_STRING="$VSX_ONLINE_NAME"
   SUGGESTED_TYPE_STRING="T (VSX)"
   SUGGESTED_PERIOD_STRING="P (VSX)"
   KNOWN_VARIABLE=1
   # seems to have no effect
   #if [ -n "$B2" ];then
   # SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING B2=$B2 "
   #fi
  else
   ###### MOVED to built-in offline catalog ######
   # The least likely, but possible case:
   # check if this is a previously-published MDV star?
   #MDV_NAME=""
   ## SA9
   #MDV_RESULT=$($TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=J/AZh/91/382 -out.max=1 -out.form=mini   -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=MDV,Type,Per 2>/dev/null | grep -v \# | grep -v "_" | grep -v "\---" | grep -A 1 MDV | tail -n1)
   #if [ "$MDV_RESULT" != "" ] ;then
   # MDV_NAME=$(echo "$MDV_RESULT" | awk '{print $1}')
   # MDV_TYPE=$(echo "$MDV_RESULT" | awk '{print $2}')
   # MDV_PERIOD=$(echo "$MDV_RESULT" | awk '{print $3}')
   #fi
   #if [ "$MDV_NAME" == "" ];then
   # MDV_RESULT=$($TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=J/AZh/87/1087/table2 -out.max=1 -out.form=mini   -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=MDV,Type,Per 2>/dev/null | grep -v \# | grep -v "_" | grep -v "\---" | grep -A 1 MDV | tail -n1)
   # if [ "$MDV_RESULT" != "" ] ;then
   #  MDV_NAME=$(echo "$MDV_RESULT" | awk '{print $1}')
   #  MDV_TYPE=$(echo "$MDV_RESULT" | awk '{print $2}')
   #  MDV_PERIOD=$(echo "$MDV_RESULT" | awk '{print $3}')
   # fi
   #fi
   #if [ "$MDV_NAME" == "" ];then
   # MDV_RESULT=$($TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=J/AZh/87/1087/table1 -out.max=1 -out.form=mini   -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=MDV,Type 2>/dev/null | grep -v \# | grep -v "_" | grep -v "\---" | grep -A 1 MDV | tail -n1)
   # if [ "$MDV_RESULT" != "" ] ;then
   #  MDV_NAME=$(echo "$MDV_RESULT" | awk '{print $1}')
   #  MDV_TYPE=$(echo "$MDV_RESULT" | awk '{print $2}')
   #  MDV_PERIOD="0.0"
   # fi
   #fi
   #if [ "$MDV_NAME" != "" ];then
   # # MDV var
   # #echo -n " $STAR_NAME | MDV $MDV_NAME | $GOOD_CATALOG_POSITION | $MDV_TYPE (MDV) | $MDV_PERIOD (MDV) | "
   # SUGGESTED_NAME_STRING="MDV $MDV_NAME"
   # SUGGESTED_TYPE_STRING="$MDV_TYPE (MDV)"
   # SUGGESTED_PERIOD_STRING="$MDV_PERIOD (MDV)"
   # SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING "
   # KNOWN_VARIABLE=1
   #fi # if [ "$MDV_NAME" != "" ];then
   ### Check other large variable star lists
   # OGLE Bulge LPV
   if [ $KNOWN_VARIABLE -eq 0 ];then
    OGLE_LPV_RESULTS=$($TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=J/AcA/63/21/catalog -out.max=10 -out.form=mini  -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=Star,Type,Per 2>/dev/null | grep -v \# | grep -v "_" | grep -v "\---" | grep -A 1 'Star' | tail -n1)
    if [ -n "$OGLE_LPV_RESULTS" ];then
     OGLENAME=$(echo "$OGLE_LPV_RESULTS" | awk '{print $1}')
     OGLETYPE=$(echo "$OGLE_LPV_RESULTS" | awk '{print $2}')
     OGLEPERIOD=$(echo "$OGLE_LPV_RESULTS" | awk '{print $3}')
     SUGGESTED_NAME_STRING="OGLE BLG-LPV-$OGLENAME"
     SUGGESTED_TYPE_STRING="$OGLETYPE (OGLE)"
     SUGGESTED_PERIOD_STRING="$OGLEPERIOD (OGLE)"
     KNOWN_VARIABLE=1
    fi
   fi   
   # ATLAS
   if [ $KNOWN_VARIABLE -eq 0 ];then
    ATLAS_RESULTS=$($TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=J/AJ/156/241/table4 -out.max=10 -out.form=mini  -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=ATOID,Class 2>/dev/null | grep -v \# | grep -v "_" | grep -v "\---" | grep J | tail -n1)
    if [ -n "$ATLAS_RESULTS" ];then
     ATLASNAME=$(echo "$ATLAS_RESULTS" | awk '{print $1}')
     ATLASTYPE=$(echo "$ATLAS_RESULTS" | awk '{print $2}')
     ATLASPERIOD=" "
     SUGGESTED_NAME_STRING="ATO $ATLASNAME"
     SUGGESTED_TYPE_STRING="$ATLASTYPE (ATLAS)"
     SUGGESTED_PERIOD_STRING="$ATLASPERIOD (ATLAS)"
     KNOWN_VARIABLE=1
    fi
   fi
   # OGLE Bulge RR Lyr
   #if [ $KNOWN_VARIABLE -eq 0 ];then
   # OGLE_LPV_RESULTS=`$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=J/AcA/61/1/ident -out.max=10 -out.form=mini  -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=Star,Type 2>/dev/null |grep -v \# | grep -v "_" | grep -v "\---" | grep -A 1 'Star' | tail -n1`
   # echo "#$OGLE_LPV_RESULTS#"
   # if [ -n "$OGLE_LPV_RESULTS" ];then
   #  OGLENAME=`echo "$OGLE_LPV_RESULTS" | awk '{print $1}'`
   #  OGLETYPE=`echo "$OGLE_LPV_RESULTS" | awk '{print $2}'`
   #  OGLEPERIOD="P"
   #  SUGGESTED_NAME_STRING="OGLE-BLG-RRLYR-$OGLENAME"
   #  SUGGESTED_TYPE_STRING="$OGLETYPE (OGLE)"
   #  SUGGESTED_PERIOD_STRING="$OGLEPERIOD"
   #  KNOWN_VARIABLE=1
   # fi
   #fi   
   # Gaia DR3 variable
   if [ $KNOWN_VARIABLE -eq 0 ];then
    GAIA_DR3_VAR_RESULTS=$($LONGTIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=I/358/varisum -out.max=1 -out.form=mini  -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" 2>/dev/null | grep -B2 '#END#' | head -n1 | awk '{print $1}' | grep -v \#)
    if [ -n "$GAIA_DR3_VAR_RESULTS" ];then
     SUGGESTED_NAME_STRING="Gaia DR3 varaible $GAIA_DR3_VAR_RESULTS"
     SUGGESTED_TYPE_STRING=""
     GAIA_DR3_VAR_TYPE_RESULTS=$($LONGTIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=I/358/vclassre -out.max=1 -out.form=mini  Source="$GAIA_DR3_VAR_RESULTS" 2>/dev/null | grep -B2 '#END#' | head -n1 | awk '{print $4}' | grep -v \#)
     if [ -n "$GAIA_DR3_VAR_TYPE_RESULTS" ];then
      SUGGESTED_TYPE_STRING="$GAIA_DR3_VAR_TYPE_RESULTS (Gaia DR3)"
     fi
     SUGGESTED_PERIOD_STRING="2022yCat.1358....0G"
     SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING Gaia DR3 varaible (the VSX policy as of July 2022 is to regard variables from Gaia DR3 as 'known')  "
     KNOWN_VARIABLE=1
    fi
   fi
   #
   # Gaia DR2 large amplitude variable
   if [ $KNOWN_VARIABLE -eq 0 ];then
    GAIA_DR2_LARGE_AMP_VAR_RESULTS=$($LONGTIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=J/A+A/648/A44/tabled1 -out.max=1 -out.form=mini  -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" 2>/dev/null | grep -B2 '#END#' | head -n1 | awk '{print $1}' | grep -v \#)
    if [ -n "$GAIA_DR2_LARGE_AMP_VAR_RESULTS" ];then
     SUGGESTED_NAME_STRING="Large-amplitude variable Gaia DR2 $GAIA_DR2_LARGE_AMP_VAR_RESULTS"
     SUGGESTED_TYPE_STRING="2021A&A...648A..44M"
     SUGGESTED_PERIOD_STRING=""
     SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING (the VSX policy as of May 2022 seems to be NOT to regard variables from 2021A&A...648A..44M as 'known' for the lack of classification)  "
     KNOWN_VARIABLE=1
    fi
   fi
   #
   # Generic VizieR search for the word 'variable'
   if [ $KNOWN_VARIABLE -eq 0 ];then
    GENERIC_VIZIER_SEARCH_VARIABLE_RESULTS=$($LONGTIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -words='variable' -meta -mime=text  -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" 2>/dev/null | grep Title | grep 'ariable' | sed 's:#Title\: ::g')
    if [ -n "$GENERIC_VIZIER_SEARCH_VARIABLE_RESULTS" ];then
     SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING may be a known variable - check VizieR  "
    fi
   fi
   #
  fi
 fi
fi
if [ $KNOWN_VARIABLE -eq 0 ];then
 # NEW var
 #echo -n " $STAR_NAME | B1.0 $GOOD_CATALOG_NAME | $GOOD_CATALOG_POSITION | T | P | B2=$B2 "
 SUGGESTED_NAME_STRING="$GOOD_CATALOG_NAME"
 SUGGESTED_TYPE_STRING="T"
 SUGGESTED_PERIOD_STRING="P"
 # seems to have no effect
 #if [ -n "$B2" ];then
 # SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING B2=$B2 "
 #fi
fi

# Try to get a spectral type
SPECTRAL_TYPE=""
# First try Skiff
SKIFF_RESULTS=$($TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=B/mk/mktypes  -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=SpType,Bibcode,Name -out.max=1 2>/dev/null | grep -B2 '#END#' | head -n1 | grep -v \# | sed 's:  : :g' | sed 's:  : :g' | sed 's:  : :g' | sed 's:  : :g' | sed 's:  : :g')
if [ -n "$SKIFF_RESULTS" ];then
 SPECTRAL_TYPE="$SKIFF_RESULTS"
 SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING SpType: $SKIFF_RESULTS  "
fi
# Then try LAMOST
if [ -z "$SPECTRAL_TYPE" ];then
 LAMOST_RESULTS=$($TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site="$VIZIER_SITE" -mime=text -source=V/164/dr5  -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=SubClass,Class -out.max=1 2>/dev/null | grep -B2 '#END#' | head -n1 | grep -v \# | grep 'STAR' | awk '{print $1}')
 if [ -n "$LAMOST_RESULTS" ];then
  SPECTRAL_TYPE="$LAMOST_RESULTS"
  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING SpType: $LAMOST_RESULTS (LAMOST DR5)  "
 fi
fi


# Print the summary string
if [ -n "$GOOD_CATALOG_NAME_USNOB" ];then
 echo -n " $STAR_NAME | $SUGGESTED_NAME_STRING | $GOOD_CATALOG_POSITION_USNOB(USNO-B1.0) | $SUGGESTED_TYPE_STRING | $SUGGESTED_PERIOD_STRING | $SUGGESTED_COMMENT_STRING"
 # Add 2MASS color and spectral type guess as a final comment
 if [ -f 2mass.tmp ];then
  cat 2mass.tmp
 else
  echo " "
 fi
fi
if [ -n "$GOOD_CATALOG_NAME_GAIA" ];then
 ### Make the columns have an approximately same width ###
 while [ ${#STAR_NAME} -lt 16 ];do
  STAR_NAME="$STAR_NAME "
 done
 while [ ${#SUGGESTED_NAME_STRING} -lt 28 ];do
  SUGGESTED_NAME_STRING="$SUGGESTED_NAME_STRING "
 done
 SUGGESTED_TYPE_STRING=$(echo "$SUGGESTED_TYPE_STRING" | sed 's:|:/:g')
 while [ ${#SUGGESTED_TYPE_STRING} -lt 16 ];do
  SUGGESTED_TYPE_STRING="$SUGGESTED_TYPE_STRING "
 done
 while [ ${#SUGGESTED_PERIOD_STRING} -lt 20 ];do
  SUGGESTED_PERIOD_STRING="$SUGGESTED_PERIOD_STRING "
 done
 while [ ${#SUGGESTED_COMMENT_STRING} -lt 55 ];do
  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING "
 done
 

 #########################################################
 echo "New summary string:"
 #echo -n " $STAR_NAME | $SUGGESTED_NAME_STRING | $GOOD_CATALOG_POSITION_GAIA(Gaia DR3)  | $SUGGESTED_TYPE_STRING | $SUGGESTED_PERIOD_STRING | $SUGGESTED_COMMENT_STRING"
 echo -n " $STAR_NAME | $SUGGESTED_NAME_STRING | $GOOD_CATALOG_POSITION_GAIA$GOOD_CATALOG_POSITION_REF  | $SUGGESTED_TYPE_STRING | $SUGGESTED_PERIOD_STRING | $SUGGESTED_COMMENT_STRING"
 # Add 2MASS color and spectral type guess as a final comment
 if [ -f 2mass.tmp ];then
  cat 2mass.tmp
 else
  echo "                      "
 fi
 
 if [ -n "$GENERIC_VIZIER_SEARCH_VARIABLE_RESULTS" ];then
  echo "
This may be a know variable star according to the titles of VizieR catalogs it is listed in:
$GENERIC_VIZIER_SEARCH_VARIABLE_RESULTS"
 fi

# Temporary disable Gaia lightcurve download before I figure out how to get Gaia DR3 epoch photometry
# 
# echo "$SUGGESTED_COMMENT_STRING" | grep --quiet -e 'CONSTANT' -e 'VARIABLE'
# if [ $? -eq 0 ];then
#  echo "
#
#You may get Gaia time-resolved photometry for this source by running
#
#util/get_gaia_lc.sh $GOOD_CATALOG_NAME_GAIA
#" 1>&2
#  # Automatically get the lightcurve
#  "$VAST_PATH"util/get_gaia_lc.sh $GOOD_CATALOG_NAME_GAIA
#  #
# fi

fi


# clean-up after vizquery
for TMP_FILE_TO_REMOVE in wget-log 2mass.tmp ;do
 if [ -f "$TMP_FILE_TO_REMOVE" ];then
  rm -f "$TMP_FILE_TO_REMOVE"
 fi
done

