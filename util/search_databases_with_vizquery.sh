#!/usr/bin/env bash

function vastrealpath {
  # On Linux, just go for the fastest option which is 'readlink -f'
  REALPATH=`readlink -f "$1" 2>/dev/null`
  if [ $? -ne 0 ];then
   # If we are on Mac OS X system, GNU readlink might be installed as 'greadlink'
   REALPATH=`greadlink -f "$1" 2>/dev/null`
   if [ $? -ne 0 ];then
    REALPATH=`realpath "$1" 2>/dev/null`
    if [ $? -ne 0 ];then
     REALPATH=`grealpath "$1" 2>/dev/null`
     if [ $? -ne 0 ];then
      # Something that should work well enough in practice
      OURPWD=$PWD
      cd "$(dirname "$1")"
      REALPATH="$PWD/$(basename "$1")"
      cd "$OURPWD"
     fi # grealpath
    fi # realpath
   fi # greadlink -f
  fi # readlink -f
  echo "$REALPATH"
}

if [ -z "$VAST_PATH" ];then
 #VAST_PATH=`readlink -f $0`
 VAST_PATH=`vastrealpath $0`
 VAST_PATH=`dirname "$VAST_PATH"`
 VAST_PATH="${VAST_PATH/util/}"
 VAST_PATH="${VAST_PATH/lib/}"
 VAST_PATH="${VAST_PATH/'//'/'/'}"
 # In case the above line didn't work
 VAST_PATH=`echo "$VAST_PATH" | sed "s:/'/:/:g"`
fi
# Check that VAST_PATH ends with '/'
LAST_CHAR_OF_VAST_PATH="${VAST_PATH: -1}"
if [ "$LAST_CHAR_OF_VAST_PATH" != "/" ];then
 VAST_PATH="$VAST_PATH/"
fi
#


#VIZIER_SITE=vizier.cfa.harvard.edu
#VIZIER_SITE=vizier.u-strasbg.fr
VIZIER_SITE=`"$VAST_PATH"lib/choose_vizier_mirror.sh`
#
echo -e "Starting $0" >> /dev/stderr

### Set path to wwwget in lib/bin/
#PATH_TO_THIS_SCRIPT=`readlink -f $0`
#PATH_TO_UTIL_DIR=`dirname $PATH_TO_THIS_SCRIPT`
#PATH_TO_VAST_DIR=`dirname $PATH_TO_UTIL_DIR`
#export PATH="$PATH:$PATH_TO_VAST_DIR/lib/bin/"
echo "$PATH" | grep --quiet "$VAST_PATH"lib/bin
if [ $? -ne 0 ];then
 export PATH="$VAST_PATH"lib/bin":$PATH"
fi

### 
TIMEOUTCOMMAND=`"$VAST_PATH"lib/find_timeout_command.sh`
if [ $? -ne 0 ];then
 echo "WARNING: cannot find timeout command"
else
 TIMEOUTCOMMAND="$TIMEOUTCOMMAND 300 "
fi


###### Test the command line arguments #####
if [ -z $2 ];then
 echo " "
 echo "ERROR: search coordinates are not given! :(

Usage: $0 RA DEC [STAR_NAME] [FOV_arcmin]

Example: $0 18:38:06.47677 +39:40:05.9835

"
 exit 1
fi   
RA=$1
DEC=$2

# Check if the input coordinates are good
if "$VAST_PATH"lib/hms2deg "$RA" "$DEC" &>/dev/null || "$VAST_PATH"lib/deg2hms "$RA" "$DEC" &>/dev/null ;then echo YES ;fi | grep --quiet 'YES'
if [ $? -ne 0 ];then
 echo "ERROR parsing the input coordinates!"
 exit 1
fi


if [ -z $3 ];then
 echo "The object name is not specified on the command line, using the default one"
 STAR_NAME="object"
else
 STAR_NAME=$3
fi

if [ -z $4 ];then
 echo "The field of view is not specified on the command line, using the default one"
 FOV=1.0
else
 FOV=$4
fi

###### 2MASS #####
R_SEARCH_ARCSEC=2.5
echo "Searching 2MASS $R_SEARCH_ARCSEC\" around $RA $DEC"
$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=2MASS  -out.max=1 -out.add=_r -out.form=mini  -sort=_r  -c="$RA $DEC" -c.rs=$R_SEARCH_ARCSEC -out=Jmag,e_Jmag,Kmag,e_Kmag  2>/dev/null |grep -v \# | grep -v "_" | grep -v "\-\-\-" |grep -v "sec"  | while read R J eJ K eK REST ;do
 if [ ! -z "$R" ];then
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
  J_K=`echo "$J $K" | awk '{printf "%.3f",$1-$2}'`
  if [[ $eJ =~ $re ]] && [[ $eK =~ $re ]] ; then
   #eJ_K=`echo "sqrt($eJ*$eJ+$eK*$eK)" | bc -ql | awk '{printf "%.3f",$1}'`  
   eJ_K=`echo "$eJ $eK" | awk '{printf "%.3f", sqrt( $1*$1 + $2*$2 ) }'`  
  else
   eJ_K="     "
  fi
  if [ ! -z "$J_K" ];then
   # Guess spectral type *assuming zero extinction*
   #
   # The old color boundaries between the spectral types were based on http://adsabs.harvard.edu/abs/1988PASP..100.1134B
   #
   # The new ones are from
   # "A Modern Mean Dwarf Stellar Color and Effective Temperature Sequence"
   # http://www.pas.rochester.edu/~emamajek/EEM_dwarf_UBVIJHK_colors_Teff.txt
   # Eric Mamajek
   # Version 2019.3.22
   # 
   SECTRAL_TYPE="unrealisitic color!"
   # Wild guess
   TEST=`echo "$J_K > -1.0"|bc -ql`
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="Very blue!"
   fi
   TEST=`echo "$J_K > -0.3"|bc -ql`
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="O"
   fi
   #TEST=`echo "$J_K > -0.230"|bc -ql`
   TEST=`echo "$J_K > -0.228"|bc -ql`
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="B"
   fi
   #TEST=`echo "$J_K > 0.0"|bc -ql`
   TEST=`echo "$J_K > -0.0135"|bc -ql`
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="A"
   fi
   #TEST=`echo "$J_K > 0.16"|bc -ql`
   TEST=`echo "$J_K > 0.132"|bc -ql`
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="F"
   fi
   #TEST=`echo "$J_K > 0.36"|bc -ql`
   TEST=`echo "$J_K > 0.3215"|bc -ql`
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="G"
   fi
   #TEST=`echo "$J_K > 0.53"|bc -ql`
   TEST=`echo "$J_K > 0.465"|bc -ql`
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="K"
   fi
   #TEST=`echo "$J_K > 0.86"|bc -ql`
   TEST=`echo "$J_K > 0.814"|bc -ql`
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="M"
   fi
   TEST=`echo "$J_K > 1.5"|bc -ql`
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="Very red!"
   fi
   TEST=`echo "$J_K > 4.0"|bc -ql`
   if [ $TEST -eq 1 ];then
    SECTRAL_TYPE="unrealisitic color!"
   fi
  else
   SECTRAL_TYPE="Sorry, cannot get 2MASS color"
  fi # if [ ! -z $J_K ];then
  # Print results
  echo "r=$R\" J = $J +/-$eJ  Ks = $K +/-$eK  J-Ks =  $J_K +/-$eJ_K  ($SECTRAL_TYPE)"
  #echo "Spectral type is according to Bessell & Brett (1988, PASP, 100, 1134) *assuming zero extinction*."
  echo "Spectral type is according to the table
'A Modern Mean Dwarf Stellar Color and Effective Temperature Sequence'
http://www.pas.rochester.edu/~emamajek/EEM_dwarf_UBVIJHK_colors_Teff.txt
Version 2019.3.22 by Eric Mamajek
http://adsabs.harvard.edu/abs/2013ApJS..208....9P

This is the spectral type *assuming zero extinction*"
  echo "J-Ks=$J_K+/-$eJ_K ($SECTRAL_TYPE)" > 2mass.tmp
 fi
done

# clean-up after vizquery
if [ -f wget-log ];then
 rm -f wget-log
fi

###### USNO-B1 #####
# by default we don't have an ID
if [ -f search_databases_with_vizquery_USNOB_ID_OK.tmp ];then
 rm -f search_databases_with_vizquery_USNOB_ID_OK.tmp
fi
####
#R_SEARCH_ARCSEC=`echo "3.0*($FOV/60)" | bc -ql | awk '{printf "%.1f",$1}'`
R_SEARCH_ARCSEC=`echo "$FOV" | awk '{printf "%.1f",3.0*($1/60)}'`
B2MAG_RANGE="B2mag=1.0..12.5"
#TEST=`echo "$FOV<400.0" | bc -ql`
TEST=`echo "$FOV<400.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
if [ $TEST -eq 1 ];then
# R_SEARCH_ARCSEC=`echo "3.0*($FOV/60)" | bc -ql | awk '{printf "%.1f",$1}'`
 B2MAG_RANGE="B2mag=1.0..15.5"
fi
#TEST=`echo "$FOV<240.0" | bc -ql`
TEST=`echo "$FOV<240.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
if [ $TEST -eq 1 ];then
# R_SEARCH_ARCSEC=`echo "3.0*($FOV/60)" | bc -ql | awk '{printf "%.1f",$1}'`
 B2MAG_RANGE="B2mag=1.0..16.5"
fi
#TEST=`echo "$FOV<120.0" | bc -ql`
TEST=`echo "$FOV<120.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
if [ $TEST -eq 1 ];then
 R_SEARCH_ARCSEC=3.0
 B2MAG_RANGE="B2mag=1.0..17.5"
fi
#TEST=`echo "$FOV<60.0" | bc -ql`
TEST=`echo "$FOV<60.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
if [ $TEST -eq 1 ];then
 R_SEARCH_ARCSEC=3.0
 B2MAG_RANGE="B2mag=1.0..18.5"
fi
#TEST=`echo "$FOV<30.0" | bc -ql`
TEST=`echo "$FOV<30.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
if [ $TEST -eq 1 ];then
 R_SEARCH_ARCSEC=1.5
 B2MAG_RANGE="B2mag=1.0..20.5"
fi
####
#DOUBLE_R_SEARCH_ARCSEC=`echo "$R_SEARCH_ARCSEC*2" | bc -ql`
DOUBLE_R_SEARCH_ARCSEC=`echo "$R_SEARCH_ARCSEC" | awk '{print 2*$1}'`
echo " "
echo "Searching USNO-B1.0 for the brightest objects within $R_SEARCH_ARCSEC\" around $RA $DEC in the range of $B2MAG_RANGE"
#echo " "
echo "$TIMEOUTCOMMAND $VAST_PATH""lib/vizquery -site=$VIZIER_SITE -mime=text -source=USNO-B1 -out.max=10 -out.add=_r -out.form=mini -sort=B2mag  -c="$RA $DEC" $B2MAG_RANGE -c.rs=$R_SEARCH_ARCSEC -out=USNO-B1.0,RAJ2000,DEJ2000,B2mag,B1mag"
$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=USNO-B1 -out.max=10 -out.add=_r -out.form=mini -sort=B2mag  -c="$RA $DEC" $B2MAG_RANGE -c.rs=$R_SEARCH_ARCSEC -out=USNO-B1.0,RAJ2000,DEJ2000,B2mag,B1mag  2>/dev/null |grep -v \# | grep -v "_" | grep -v "\-\-\-" |grep -v "sec"  |grep -v "RAJ" |grep -v "B" | while read R USNOB1 CATRA_DEG CATDEC_DEG B2 B1 REST ;do
 # skip stars with unknown B2mag
 if [ -z $B2 ] ;then
  continue
 fi
 # skip stars with unknown B1mag
 if [ -z $B1 ] ;then
  continue
 fi
 # skip empty lines if for whatever reason they were not caught before
 if [ ! -z $R ] ;then
  # Skip too faint stars
  TEST=`echo "($B2+$B1)/2.0>18.0"|bc -ql`
  if [ $TEST -eq 1 ];then
   continue
  fi
  GOOD_CATALOG_POSITION=`"$VAST_PATH"lib/deg2hms $CATRA_DEG $CATDEC_DEG` 
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


###### GAIA DR2 #####
# by default we don't have an ID
if [ -f search_databases_with_vizquery_GAIA_ID_OK.tmp ];then
 rm -f search_databases_with_vizquery_GAIA_ID_OK.tmp
fi
####
#R_SEARCH_ARCSEC=`echo "3.0*($FOV/60)" | bc -ql | awk '{printf "%.1f",$1}'`
R_SEARCH_ARCSEC=`echo "$FOV" | awk '{printf "%.1f",3.0*($1/60)}'`
GMAG_RANGE="Gmag=1.0..12.5"
#TEST=`echo "$FOV<400.0" | bc -ql`
TEST=`echo "$FOV<400.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
if [ $TEST -eq 1 ];then
# R_SEARCH_ARCSEC=`echo "3.0*($FOV/60)" | bc -ql | awk '{printf "%.1f",$1}'`
 GMAG_RANGE="Gmag=1.0..15.5"
fi
#TEST=`echo "$FOV<240.0" | bc -ql`
TEST=`echo "$FOV<240.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
if [ $TEST -eq 1 ];then
# R_SEARCH_ARCSEC=`echo "3.0*($FOV/60)" | bc -ql | awk '{printf "%.1f",$1}'`
 GMAG_RANGE="Gmag=1.0..16.5"
fi
#TEST=`echo "$FOV<120.0" | bc -ql`
TEST=`echo "$FOV<120.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
if [ $TEST -eq 1 ];then
 R_SEARCH_ARCSEC=3.0
 GMAG_RANGE="Gmag=1.0..17.5"
fi
#TEST=`echo "$FOV<60.0" | bc -ql`
TEST=`echo "$FOV<60.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
if [ $TEST -eq 1 ];then
 R_SEARCH_ARCSEC=3.0
 GMAG_RANGE="Gmag=1.0..18.5"
fi
#TEST=`echo "$FOV<30.0" | bc -ql`
TEST=`echo "$FOV<30.0" | awk -F'<' '{if ( $1 < $2 ) print 1 ;else print 0 }'`
if [ $TEST -eq 1 ];then
 R_SEARCH_ARCSEC=1.5
 GMAG_RANGE="Gmag=1.0..20.5"
fi
####
#DOUBLE_R_SEARCH_ARCSEC=`echo "$R_SEARCH_ARCSEC*2" | bc -ql`
DOUBLE_R_SEARCH_ARCSEC=`echo "$R_SEARCH_ARCSEC" | awk '{print 2*$1}'`
echo " "
echo "Searching Gaia DR2 for the brightest objects within $R_SEARCH_ARCSEC\" around $RA $DEC in the range of $GMAG_RANGE"
echo "$TIMEOUTCOMMAND $VAST_PATH""lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/gaia2 -out.max=10 -out.add=_r -out.form=mini -sort=Gmag  -c='$RA $DEC' $GMAG_RANGE -c.rs=$R_SEARCH_ARCSEC -out=Source,RA_ICRS,DE_ICRS,Gmag,Var"
$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/gaia2 -out.max=10 -out.add=_r -out.form=mini -sort=Gmag  -c="$RA $DEC" $GMAG_RANGE -c.rs=$R_SEARCH_ARCSEC -out=Source,RA_ICRS,DE_ICRS,Gmag,Var 2>/dev/null |grep -v \# | grep -v "\-\-\-" |grep -v "sec" | grep -v 'Gma' |grep -v "RA_ICRS" | grep -e 'NOT_AVAILABLE' -e 'CONSTANT' -e 'VARIABLE' | while read R GAIA_SOURCE GAIA_CATRA_DEG GAIA_CATDEC_DEG GMAG VARFLAG REST ;do
 # skip stars with unknown Gmag
 if [ -z $GMAG ] ;then
  continue
 fi
 # skip empty lines if for whatever reason they were not caught before
 if [ ! -z $R ] ;then
  # Skip too faint stars
  TEST=`echo "$GMAG>18.0"|bc -ql`
  if [ $TEST -eq 1 ];then
   continue
  fi
  GOOD_CATALOG_POSITION_GAIA=`"$VAST_PATH"lib/deg2hms $GAIA_CATRA_DEG $GAIA_CATDEC_DEG` 
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






# Exit if therere is no reliable ID with astrometric catalog
if [ ! -f search_databases_with_vizquery_USNOB_ID_OK.tmp ];then
 echo "Could not match the source with USNO-B1.0 :("
else
 GOOD_CATALOG_POSITION_USNOB=`head -n1 search_databases_with_vizquery_USNOB_ID_OK.tmp`
 GOOD_CATALOG_POSITION="$GOOD_CATALOG_POSITION_USNOB"
 GOOD_CATALOG_NAME_USNOB=`tail -n1 search_databases_with_vizquery_USNOB_ID_OK.tmp`
 GOOD_CATALOG_NAME="B1.0 $GOOD_CATALOG_NAME_USNOB"
 rm -f search_databases_with_vizquery_USNOB_ID_OK.tmp
fi
# Exit if therere is no reliable ID with astrometric catalog
if [ ! -f search_databases_with_vizquery_GAIA_ID_OK.tmp ];then
 echo "Could not match the source with Gaia DR2 :("
else
 GOOD_CATALOG_POSITION_GAIA=`head -n1 search_databases_with_vizquery_GAIA_ID_OK.tmp`
 GOOD_CATALOG_POSITION="$GOOD_CATALOG_POSITION_GAIA"
 GOOD_CATALOG_NAME_GAIA=`head -n2 search_databases_with_vizquery_GAIA_ID_OK.tmp | tail -n1`
 GOOD_CATALOG_NAME="Gaia DR2 $GOOD_CATALOG_NAME_GAIA"
 VARFLAG=`tail -n1 search_databases_with_vizquery_GAIA_ID_OK.tmp`
 while [ ${#VARFLAG} -lt 13 ];do
  VARFLAG="$VARFLAG "
 done

 SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING Gaia2var=$VARFLAG "
 rm -f search_databases_with_vizquery_GAIA_ID_OK.tmp
 # Get additional variability info from Gaia
 # Gaia short-time var
 $TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/shortts -out.max=10 -out.form=mini Source="$GOOD_CATALOG_NAME_GAIA" 2>/dev/null | grep -v \# | grep --quiet "$GOOD_CATALOG_NAME_GAIA"
 if [ $? -eq 0 ];then
  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING Gaia2_SHORTTS "
 fi
 # Gaia Cepheids
 $TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/cepheid -out.max=10 -out.form=mini Source="$GOOD_CATALOG_NAME_GAIA" 2>/dev/null | grep -v \# | grep --quiet "$GOOD_CATALOG_NAME_GAIA"
 if [ $? -eq 0 ];then
  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING Gaia2_CEPHEID "
 fi
 # Gaia RR Lyrae
 $TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/rrlyrae -out.max=10 -out.form=mini Source="$GOOD_CATALOG_NAME_GAIA" 2>/dev/null | grep -v \# | grep --quiet "$GOOD_CATALOG_NAME_GAIA"
 if [ $? -eq 0 ];then
  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING Gaia2_RRLYR "
 fi
 # Gaia LPV
 $TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=I/345/lpv -out.max=10 -out.form=mini Source="$GOOD_CATALOG_NAME_GAIA" 2>/dev/null | grep -v \# | grep --quiet "$GOOD_CATALOG_NAME_GAIA"
 if [ $? -eq 0 ];then
  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING Gaia2_LPV "
 fi
 #
fi

###### ID with variability catalogs and write summary string #####
KNOWN_VARIABLE=0
echo "
Summary string:"

# Local catalogs
if [ $KNOWN_VARIABLE -eq 0 ];then
 GOOD_CATALOG_POSITION_DEG=`lib/hms2deg $GOOD_CATALOG_POSITION 2>/dev/null`
 if [ $? -ne 0 ];then
  # The input position is already in decimal degrees
  GOOD_CATALOG_POSITION_DEG="$GOOD_CATALOG_POSITION"
 fi
 LOCAL_CATALOG_SEARCH_RESULTS=`lib/catalogs/check_catalogs_offline $GOOD_CATALOG_POSITION_DEG 2>/dev/null`
 if [ $? -eq 0 ];then
  # The object is found in local catalogs
  # Mac doesn't allow '-m1 -A1' combination for grep (!!!)
  #LOCAL_NAME=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep -m1 -A1 '>found<' | tail -n1 | awk '{print $2}' FS='"' | sed 's:MASTER OT:MASTER_OT:g'`  
  # | awk '{$1=$1;print}' Would trim leading and trailing space or tab characters and also squeeze sequences of tabs and spaces into a single space. https://unix.stackexchange.com/questions/102008/how-do-i-trim-leading-and-trailing-whitespace-from-each-line-of-some-output
  #LOCAL_NAME=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep -A 1 '>found<' | tail -n 1 | awk '{print $2}' FS='"' | sed 's:MASTER OT:MASTER_OT:g' | awk '{$1=$1;print}'`  
  LOCAL_NAME=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep -A 1 '>found<' | tail -n 1 | awk -F '"' '{print $2}' | sed 's:MASTER OT:MASTER_OT:g' | awk '{$1=$1;print}'`  
  #LOCAL_TYPE=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep 'Type:' | awk '{print $2}' FS='Type:' | awk '{$1=$1;print}'`
  LOCAL_TYPE=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep 'Type:' | awk -F 'Type:' '{print $2}' | awk '{$1=$1;print}'`
  #LOCAL_PERIOD=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep -m1 -A1 '#   Max.' | tail -n1 | sed 's:)::g' | sed 's:(::g' | awk '{print $6}'`
  LOCAL_PERIOD=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep -A 1 '#   Max.' | tail -n 1 | sed 's:)::g' | sed 's:(::g' | awk '{print $6}'`
  if [ -z "$LOCAL_PERIOD" ];then
   #LOCAL_PERIOD=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep 'Period' | awk '{print $2}' FS='Period' | awk '{print $1}'`
   LOCAL_PERIOD=`echo "$LOCAL_CATALOG_SEARCH_RESULTS" | grep 'Period' | awk -F 'Period' '{print $2}' | awk '{print $1}'`
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
 GCVS_RESULT=`$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=B/gcvs -out.max=1 -out.form=mini   -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs=$DOUBLE_R_SEARCH_ARCSEC -out=GCVS,VarType,Period 2>/dev/null  |grep -v \# | grep -v "_" | grep -v "\-\-\-" |grep -v "GCVS" |head -n2 |tail -n 1`
 GCVS_V=`echo "$GCVS_RESULT" | awk '{print $1}'`
 if [ "$GCVS_V" != "" ] ;then
  # STAR FROM GCVS
  GCVS_CONSTEL=`echo "$GCVS_RESULT" | awk '{print $2}'`
  GCVS_TYPE=`echo "$GCVS_RESULT" | awk '{print $3}'`
  GCVS_PERIOD=`echo "$GCVS_RESULT" | awk '{print $4}'`
  #echo -n " $STAR_NAME | $GCVS_V $GCVS_CONSTEL | $GOOD_CATALOG_POSITION | $GCVS_TYPE (GCVS) | $GCVS_PERIOD (GCVS) | "
  SUGGESTED_NAME_STRING="$GCVS_V $GCVS_CONSTEL"
  SUGGESTED_TYPE_STRING="$GCVS_TYPE (GCVS)"
  SUGGESTED_PERIOD_STRING="$GCVS_PERIOD (GCVS)"
  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING "
  KNOWN_VARIABLE=1
 fi
fi
if [ $KNOWN_VARIABLE -eq 0 ];then
 VSX_RESULT=`$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=B/vsx -out.max=1 -out.form=mini   -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs=$DOUBLE_R_SEARCH_ARCSEC -out=Name,Type,Period 2>/dev/null |grep -v \# | grep -v "_" | grep -v "\-\-\-" |grep -A 1 Name | tail -n1 | sed 's:MASTER OT:MASTER_OT:g'`
 #echo "########$VSX_RESULT#########"
 VSX_V=`echo "$VSX_RESULT" | awk '{print $1}'`
 if [ "$VSX_V" != "" ] ;then
  # STAR FROM VSX
  VSX_NAME=`echo "$VSX_RESULT" | awk '{print $2}'`
  VSX_TYPE=`echo "$VSX_RESULT" | awk '{print $3}'`
  VSX_PERIOD=`echo "$VSX_RESULT" | awk '{print $4}'`
  # Special case - OGLE one-word variable names
  echo "$VSX_V" | grep --quiet 'OGLE-'
  if [ $? -eq 0 ];then
   VSX_V=""
   VSX_NAME=`echo "$VSX_RESULT" | awk '{print $1}'`
   VSX_TYPE=`echo "$VSX_RESULT" | awk '{print $2}'`
   VSX_PERIOD=`echo "$VSX_RESULT" | awk '{print $3}'`
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
  VSX_ONLINE_NAME=`"$VAST_PATH"util/search_databases_with_curl.sh $RA $DEC 2>/dev/null | grep -v "not found" | grep -A 1 "The object was" | grep -A 1 "found" | grep -A 1 "VSX" | tail -n1`
  if [ "$VSX_ONLINE_NAME" != "" ] ;then
   #echo -n " $STAR_NAME | $VSX_ONLINE_NAME | $GOOD_CATALOG_POSITION | T | P | "
   SUGGESTED_NAME_STRING="$VSX_ONLINE_NAME"
   SUGGESTED_TYPE_STRING="T (VSX)"
   SUGGESTED_PERIOD_STRING="P (VSX)"
   KNOWN_VARIABLE=1
   if [ ! -z "$B2" ];then
    SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING B2=$B2 "
   fi
  else
   # The least likely, but possible case:
   # check if this is a previously-published MDV star?
   MDV_NAME=""
   # SA9
   MDV_RESULT=`$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=J/AZh/91/382 -out.max=1 -out.form=mini   -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=MDV,Type,Per 2>/dev/null |grep -v \# | grep -v "_" | grep -v "\-\-\-" |grep -A 1 MDV | tail -n1`
   if [ "$MDV_RESULT" != "" ] ;then
    MDV_NAME=`echo "$MDV_RESULT" | awk '{print $1}'`
    MDV_TYPE=`echo "$MDV_RESULT" | awk '{print $2}'`
    MDV_PERIOD=`echo "$MDV_RESULT" | awk '{print $3}'`
   fi
   if [ "$MDV_NAME" == "" ];then
    MDV_RESULT=`$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=J/AZh/87/1087/table2 -out.max=1 -out.form=mini   -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=MDV,Type,Per 2>/dev/null |grep -v \# | grep -v "_" | grep -v "\-\-\-" |grep -A 1 MDV | tail -n1`
    if [ "$MDV_RESULT" != "" ] ;then
     MDV_NAME=`echo "$MDV_RESULT" | awk '{print $1}'`
     MDV_TYPE=`echo "$MDV_RESULT" | awk '{print $2}'`
     MDV_PERIOD=`echo "$MDV_RESULT" | awk '{print $3}'`
    fi
   fi
   if [ "$MDV_NAME" == "" ];then
    MDV_RESULT=`$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=$VIZIER_SITE -mime=text -source=J/AZh/87/1087/table1 -out.max=1 -out.form=mini   -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=MDV,Type 2>/dev/null |grep -v \# | grep -v "_" | grep -v "\-\-\-" |grep -A 1 MDV | tail -n1`
    if [ "$MDV_RESULT" != "" ] ;then
     MDV_NAME=`echo "$MDV_RESULT" | awk '{print $1}'`
     MDV_TYPE=`echo "$MDV_RESULT" | awk '{print $2}'`
     MDV_PERIOD="0.0"
    fi
   fi
   if [ "$MDV_NAME" != "" ];then
    # MDV var
    #echo -n " $STAR_NAME | MDV $MDV_NAME | $GOOD_CATALOG_POSITION | $MDV_TYPE (MDV) | $MDV_PERIOD (MDV) | "
    SUGGESTED_NAME_STRING="MDV $MDV_NAME"
    SUGGESTED_TYPE_STRING="$MDV_TYPE (MDV)"
    SUGGESTED_PERIOD_STRING="$MDV_PERIOD (MDV)"
    SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING "
    KNOWN_VARIABLE=1
#   else
#    # NEW var
#    #echo -n " $STAR_NAME | B1.0 $GOOD_CATALOG_NAME | $GOOD_CATALOG_POSITION | T | P | B2=$B2 "
#    SUGGESTED_NAME_STRING="$GOOD_CATALOG_NAME"
#    SUGGESTED_TYPE_STRING="T"
#    SUGGESTED_PERIOD_STRING="P"
#    SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING B2=$B2"
   #
   fi # if [ "$MDV_NAME" != "" ];then
   ### Check other large variable star lists
   # OGLE Bulge LPV
   if [ $KNOWN_VARIABLE -eq 0 ];then
    OGLE_LPV_RESULTS=`$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=vizier.u-strasbg.fr -mime=text -source=J/AcA/63/21/catalog -out.max=10 -out.form=mini  -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=Star,Type,Per 2>/dev/null |grep -v \# | grep -v "_" | grep -v "\-\-\-" | grep -A 1 'Star' | tail -n1`
    if [ ! -z "$OGLE_LPV_RESULTS" ];then
     OGLENAME=`echo "$OGLE_LPV_RESULTS" | awk '{print $1}'`
     OGLETYPE=`echo "$OGLE_LPV_RESULTS" | awk '{print $2}'`
     OGLEPERIOD=`echo "$OGLE_LPV_RESULTS" | awk '{print $3}'`
     SUGGESTED_NAME_STRING="OGLE BLG-LPV-$OGLENAME"
     SUGGESTED_TYPE_STRING="$OGLETYPE (OGLE)"
     SUGGESTED_PERIOD_STRING="$OGLEPERIOD (OGLE)"
     KNOWN_VARIABLE=1
    fi
   fi   
   # ATLAS
   if [ $KNOWN_VARIABLE -eq 0 ];then
    ATLAS_RESULTS=`$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=vizier.u-strasbg.fr -mime=text -source=J/AJ/156/241/table4 -out.max=10 -out.form=mini  -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=ATOID,Class 2>/dev/null |grep -v \# | grep -v "_" | grep -v "\-\-\-" | grep J | tail -n1`
    if [ ! -z "$ATLAS_RESULTS" ];then
     ATLASNAME=`echo "$ATLAS_RESULTS" | awk '{print $1}'`
     ATLASTYPE=`echo "$ATLAS_RESULTS" | awk '{print $2}'`
     ATLASPERIOD=" "
     SUGGESTED_NAME_STRING="ATOID $ATLASNAME"
     SUGGESTED_TYPE_STRING="$ATLASTYPE (ATLAS)"
     SUGGESTED_PERIOD_STRING="$ATLASPERIOD (ATLAS)"
     KNOWN_VARIABLE=1
    fi
   fi
   # OGLE Bulge RR Lyr
   #if [ $KNOWN_VARIABLE -eq 0 ];then
   # OGLE_LPV_RESULTS=`$TIMEOUTCOMMAND "$VAST_PATH"lib/vizquery -site=vizier.u-strasbg.fr -mime=text -source=J/AcA/61/1/ident -out.max=10 -out.form=mini  -sort=_r -c="$GOOD_CATALOG_POSITION" -c.rs="$DOUBLE_R_SEARCH_ARCSEC" -out=Star,Type 2>/dev/null |grep -v \# | grep -v "_" | grep -v "\-\-\-" | grep -A 1 'Star' | tail -n1`
   # echo "#$OGLE_LPV_RESULTS#"
   # if [ ! -z "$OGLE_LPV_RESULTS" ];then
   #  OGLENAME=`echo "$OGLE_LPV_RESULTS" | awk '{print $1}'`
   #  OGLETYPE=`echo "$OGLE_LPV_RESULTS" | awk '{print $2}'`
   #  OGLEPERIOD="P"
   #  SUGGESTED_NAME_STRING="OGLE-BLG-RRLYR-$OGLENAME"
   #  SUGGESTED_TYPE_STRING="$OGLETYPE (OGLE)"
   #  SUGGESTED_PERIOD_STRING="$OGLEPERIOD"
   #  KNOWN_VARIABLE=1
   # fi
   #fi   
  fi
 fi
fi

if [ $KNOWN_VARIABLE -eq 0 ];then
 # NEW var
 #echo -n " $STAR_NAME | B1.0 $GOOD_CATALOG_NAME | $GOOD_CATALOG_POSITION | T | P | B2=$B2 "
 SUGGESTED_NAME_STRING="$GOOD_CATALOG_NAME"
 SUGGESTED_TYPE_STRING="T"
 SUGGESTED_PERIOD_STRING="P"
 if [ ! -z "$B2" ];then
  SUGGESTED_COMMENT_STRING="$SUGGESTED_COMMENT_STRING B2=$B2 "
 fi
fi

# Print the summary string
if [ ! -z "$GOOD_CATALOG_NAME_USNOB" ];then
 echo -n " $STAR_NAME | $SUGGESTED_NAME_STRING | $GOOD_CATALOG_POSITION_USNOB(USNO-B1.0) | $SUGGESTED_TYPE_STRING | $SUGGESTED_PERIOD_STRING | $SUGGESTED_COMMENT_STRING"
 # Add 2MASS color and spectral type guess as a final comment
 if [ -f 2mass.tmp ];then
  cat 2mass.tmp
 else
  echo " "
 fi
fi
if [ ! -z "$GOOD_CATALOG_NAME_GAIA" ];then
 ### Make the columns have an approximately same width ###
 while [ ${#STAR_NAME} -lt 16 ];do
  STAR_NAME="$STAR_NAME "
 done
 while [ ${#SUGGESTED_NAME_STRING} -lt 28 ];do
  SUGGESTED_NAME_STRING="$SUGGESTED_NAME_STRING "
 done
 SUGGESTED_TYPE_STRING=`echo "$SUGGESTED_TYPE_STRING" | sed 's:|:/:g'`
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
 echo -n " $STAR_NAME | $SUGGESTED_NAME_STRING | $GOOD_CATALOG_POSITION_GAIA(Gaia DR2)  | $SUGGESTED_TYPE_STRING | $SUGGESTED_PERIOD_STRING | $SUGGESTED_COMMENT_STRING"
 # Add 2MASS color and spectral type guess as a final comment
 if [ -f 2mass.tmp ];then
  cat 2mass.tmp
 else
  echo "                      "
 fi
 echo "$SUGGESTED_COMMENT_STRING" | grep --quiet -e 'CONSTANT' -e 'VARIABLE'
 if [ $? -eq 0 ];then
  echo "

You may get Gaia time-resolved photometry for this source by running

util/get_gaia_lc.sh $GOOD_CATALOG_NAME_GAIA
" >> /dev/stderr
  # Automatically get the lightcurve
  "$VAST_PATH"util/get_gaia_lc.sh $GOOD_CATALOG_NAME_GAIA
  #
 fi
fi


# clean-up after vizquery
for TMP_FILE_TO_REMOVE in wget-log 2mass.tmp ;do
 if [ -f "$TMP_FILE_TO_REMOVE" ];then
  rm -f "$TMP_FILE_TO_REMOVE"
 fi
done

