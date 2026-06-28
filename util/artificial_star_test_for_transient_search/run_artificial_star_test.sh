#!/usr/bin/env bash

# general settings
N_ARTSTARS_PER_ITER=100
N_ITERATIONS=1

function print_usage_and_exit() {
 echo "Usage:
 REFERENCE_IMAGES=../NMW__NovaVul24_Stas_test/reference_images/ $0 ../NMW__NovaVul24_Stas_test/second_epoch_images_wcs [N_ITERATIONS]
where ../NMW__NovaVul24_Stas_test/reference_images/ is the reference images directory,
../NMW__NovaVul24_Stas_test/second_epoch_images_wcs is the new images directory, and
the optional N_ITERATIONS (default 1) is the number of insert-and-recover iterations per trial flux.
The input should be similar to that of util/transients/transient_factory_test31.sh script."
 exit 1
}

if [ -z "$REFERENCE_IMAGES" ];then
 REFERENCE_IMAGES="../NMW__NovaVul24_Stas_test/reference_images/"
fi
export REFERENCE_IMAGES

THIS_IS_ARTIFICIAL_STAR_TEST_DO_NO_ONLINE_VSX_SEARCH=1
export THIS_IS_ARTIFICIAL_STAR_TEST_DO_NO_ONLINE_VSX_SEARCH

if [ -z "$1" ];then
 print_usage_and_exit
fi
INPUT_IMAGE_DIR="$1"
# Remove the trailing shash from the input directory path if present
INPUT_IMAGE_DIR=${INPUT_IMAGE_DIR%/}
#
if [ ! -d "$INPUT_IMAGE_DIR" ];then
 echo "ERROR in $0: $INPUT_IMAGE_DIR is not a directory"
 print_usage_and_exit
fi

# Optional second argument: number of insert-and-recover iterations per trial flux (default 1)
if [ -n "$2" ];then
 case "$2" in
  *[!0-9]*|"") echo "ERROR in $0: N_ITERATIONS must be a positive integer, got '$2'" ; print_usage_and_exit ;;
 esac
 if [ "$2" -lt 1 ];then
  echo "ERROR in $0: N_ITERATIONS must be >= 1, got '$2'" ; print_usage_and_exit
 fi
 N_ITERATIONS="$2"
fi
echo "Number of insert-and-recover iterations per trial flux: N_ITERATIONS=$N_ITERATIONS"

# Clean the working directory from any remains of previous runs
util/clean_data.sh

# Create the new input directory where the input images will surely be platesolved
PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR="$INPUT_IMAGE_DIR"__wcs
if [ -d "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR" ];then
 rm -rf "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"
fi
mkdir "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR" || exit 1

# Plate-solve the images
for FITS_IMAGE_TO_PLATESOLVE in "$INPUT_IMAGE_DIR"/*.fits "$INPUT_IMAGE_DIR"/*.fit "$INPUT_IMAGE_DIR"/*.fts ;do
 if [ ! -f "$FITS_IMAGE_TO_PLATESOLVE" ];then
  continue
 fi
 util/wcs_image_calibration.sh "$FITS_IMAGE_TO_PLATESOLVE" 
done
for FITS_IMAGE_TO_PLATESOLVE in wcs_*.fits wcs_*.fit wcs_*.fts ;do
 mv -v "$FITS_IMAGE_TO_PLATESOLVE" "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR/${FITS_IMAGE_TO_PLATESOLVE/wcs_/}"
done

#PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR=../NMW__NovaVul24_Stas_test/second_epoch_images_wcs

# Determine star FWHMs and amplitudes
FIRST_IMAGE_TO_BE_MODIFIED=$(ls "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"/*.fits "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"/*.fit "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"/*.fts | head -n1)
if [ -z "$FIRST_IMAGE_TO_BE_MODIFIED" ];then
 echo "ERROR in $0: noe FITS images found in PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR=$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR
Have the plate solution failed?"
 exit 1
fi
if [ ! -s "$FIRST_IMAGE_TO_BE_MODIFIED" ];then
 echo "ERROR in $0: cannot find the first input FITS image $FIRST_IMAGE_TO_BE_MODIFIED"
 print_usage_and_exit
fi

# Baseline (control) run: run the transient search on the clean (un-injected) images to
# locate the genuine astrophysical transients in the field. We assume every real transient
# is a known variable star or a Solar System object, so the local-catalog check
# (VSX / ASASSN-V / astcheck) is applied HERE, on the baseline ONLY, to identify them; their
# positions are saved and later excluded from the purity denominator. The catalog check is
# intentionally NOT applied to the insert-and-recovery runs: an injected star that happens
# to land on a known source must still be counted as recovered. Deterministic false
# detections of the field are NOT saved, so they keep counting as false positives.
#
# The baseline must run BEFORE the flux/FWHM determination below: transient_factory_test31.sh
# selects the camera-appropriate SExtractor config and copies it onto default.sex, so the
# subsequent fits2cat pass measures the injected-flux scale with the SAME default.sex the
# transient search uses (rather than whatever stale default.sex was left in the directory).
TRUE_TRANSIENTS_FILE="$PWD"/true_transients.txt
echo "Running the baseline (no artificial stars) transient search to map real transients..."
util/transients/transient_factory_test31.sh "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"/
if [ $? -ne 0 ];then
 echo "ERROR running the baseline util/transients/transient_factory_test31.sh"
 exit 1
fi
# Save positions (X Y on the discovery image) of candidates that ARE catalog-matched,
# i.e. their block does NOT report "not found" in all of VSX, ASASSN-V and astcheck.
awk '/Processing complete!/{exit}
 function flush(){ if(have && !(nf_vsx && nf_as && nf_ast)) print x, y }
 /<a name=/ { flush(); have=0; nf_vsx=0; nf_as=0; nf_ast=0 }
 /Discovery image 2/ { split($0,a,"<td>"); split(a[7],xy," "); x=xy[1]; y=xy[2]; have=1 }
 /not found/ && /VSX/ { nf_vsx=1 }
 /not found/ && /ASASSN-V/ { nf_as=1 }
 /not found/ && /astcheck/ { nf_ast=1 }
 END{ flush() }' transient_report/index.html | sort | uniq > "$TRUE_TRANSIENTS_FILE"
echo "Saved $(wc -l < "$TRUE_TRANSIENTS_FILE") real (catalog-matched) transient position(s) to $TRUE_TRANSIENTS_FILE"

# do a SE run to determine stars FWHM and calibrate star fluxes.
# This runs AFTER the baseline so default.sex is the config the transient search selected.
# fits2cat runs the same SExtraction as sextract_single_image_noninteractive
# but also prints the resulting catalog filename to stdout. The standalone
# catalog name is PID-based (e.g. image_pid12345.cat), not image00000.cat.
SOURCE_CATALOG=$(lib/fits2cat "$FIRST_IMAGE_TO_BE_MODIFIED")
if [ $? -ne 0 ];then
 echo "ERROR in $0: non-zero exit code of lib/fits2cat $FIRST_IMAGE_TO_BE_MODIFIED"
 exit 1
fi
if [ -z "$SOURCE_CATALOG" ] || [ ! -s "$SOURCE_CATALOG" ];then
 echo "ERROR in $0: no useful source catalog ($SOURCE_CATALOG) created"
 exit 1
fi
FLUX=$(cat "$SOURCE_CATALOG" | awk '{print $2}' | util/colstat | grep 'percen80=' | awk '{print $2}')
FWHM=$(cat "$SOURCE_CATALOG" | awk '{print $23}' | util/colstat | grep 'MEDIAN=' | awk '{print $2}')
echo "Results from the preliminary SE run: 
FLUX= $FLUX  FWHM=$FWHM"

# Check if FLUX is reasonable
awk -v n="$FLUX" 'BEGIN{exit !(n ~ /^[0-9]*\.?[0-9]+$/ && n < 200000000)}'
if [ $? -ne 0 ];then
 echo "ERROR in $0: unreasonable FLUX value of $FLUX"
 exit 1
fi


# Check if FWHM is reasonable
awk -v n="$FWHM" 'BEGIN{exit !(n ~ /^[0-9]*\.?[0-9]+$/ && n < 20)}'
if [ $? -ne 0 ];then
 echo "ERROR in $0: unreasonable FWHM value of $FWHM"
 exit 1
fi

# FLUX is assumed to be the flux corresponding to the limiting magnitude:
# the one at which we reliably detect sources (and appparently transients),
echo $0 | grep -q 'run_artificial_star_test_oneflux.sh'
if [ $? -eq 0 ];then
 # try only one flux value
 #
 # faint transients
 TRIAL_FLUXES="$FLUX"
 # bright hard-to-miss transients
 #TRIAL_FLUXES="$(echo $FLUX | awk '{print 8*$1}')"
else
 # try both higher and lower fluxes
 #TRIAL_FLUXES="$(echo $FLUX | awk '{print 16*$1" "12*$1" "8*$1" "6*$1" "4*$1" "3*$1" "2*$1" "$1" "$1/2" "$1/3" "$1/4" "$1/6" "$1/8" "$1/12" "$1/16}')"
 TRIAL_FLUXES="$(echo $FLUX | awk '{print 8*$1" "6*$1" "4*$1" "3*$1" "2*$1" "$1" "$1/2" "$1/3" "$1/4" "$1/6" "$1/8}')"
fi

echo "Trial fluxes:
$TRIAL_FLUXES"
#exit 1 #!!!!

if [ -f artificial_star_test_results.txt ];then
 rm -f artificial_star_test_results.txt
fi

for FLUX in $TRIAL_FLUXES ;do

 # run the test inserting N_ARTSTARS_PER_ITER artificial stars each run
 N_ARTSTARS_INSERTED_TOTAL=0
 N_FALSE_POSITIVES_TOTAL=0
 IDENTIFIED_ARTSTARS_FOR_THIS_ITERATION_TMPFILE=$(mktemp)
 ITERATION=1
 while [ $ITERATION -le $N_ITERATIONS ] ;do

  # Insert artificial stars
  util/artificial_star_test_for_transient_search/insert_artificial_stars_in_image.py "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"/ $FLUX $N_ARTSTARS_PER_ITER --fwhm "$FWHM"
  if [ $? -ne 0 ];then
   echo "ERROR running insert_artificial_stars_in_image.py"
   exit 1
  fi

  # Run the transient search
  #REFERENCE_IMAGES=../NMW__NovaVul24_Stas_test/reference_images/ 
  util/transients/transient_factory_test31.sh "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"__artificialstars/
  if [ $? -ne 0 ];then
   echo "ERROR running util/transients/transient_factory_test31.sh"
   exit 1
  fi
  cat transient_factory_test31.txt | grep 'ERROR'
  if [ $? -eq 0 ];then
   echo "ERROR reported in transient_factory_test31.txt"
   continue
   #exit 1
  fi

  # Create the list of candidate transients and their magnitudes.
  # Only the candidates table ABOVE the '<H2>Processing complete!</H2>' marker holds
  # the actual candidates. 'Discovery image 2' also appears further down inside the
  # collapsible "Processing log" block (log echoes), which must NOT be counted or
  # matched. The leading awk stops reading at the marker line. The 'Processing complete!'
  # string (with the '!') uniquely matches that <H2> marker - the page-top instruction
  # text says 'Processing complete' without '!', and the footer says 'Processing completed'.
  # WARNING: cannot use 'Discovery image 1' as this will be first-epoch image for the transients detected via the flare channel
  # 'Discovery image 2' should be one of the second-epoch images for both 'transients' and 'flares'
  # in awk, the NF condition checks if there are any fields in the line (NF = Number of Fields).
  # NO catalog check is applied here: an injected star must be counted as recovered even if
  # it coincides with a known source. Real transients are handled via the baseline run
  # (TRUE_TRANSIENTS_FILE) when computing purity below.
  # The trailing awk collapses candidates that lie within 3 px of one another into a single
  # entry (greedy, keeping the first occurrence). The same physical candidate may be reported
  # more than once - e.g. detected in both SExtractor-config passes with slightly different
  # centroids - so without this dedup the false-positive count would be inflated.
  ARTSTARS_DIR="$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"__artificialstars
  CAND_ALL="$ARTSTARS_DIR"/candidate_coordinates_and_magnitudes.txt
  awk '/Processing complete!/{exit} 1' transient_report/index.html | grep 'Discovery image 2' | awk -F'<td>' '{print $5" "$7}' | awk 'NF {print $3" "$4" "$1}' | sort | uniq | awk '{
    keep = 1;
    for ( j = 1; j <= n; j++ ) {
     d = sqrt(($1 - kx[j])^2 + ($2 - ky[j])^2);
     if ( d <= 3 ) { keep = 0; break; }
    }
    if ( keep ) { n++; kx[n] = $1; ky[n] = $2; print; }
   }' > "$CAND_ALL"

  # Recovery (completeness): for each injected star keep its nearest candidate within 3 px,
  # so each injected star is counted at most once regardless of catalog status.
  while read -r x1 y1; do
   awk -v x1="$x1" -v y1="$y1" '{
    x2 = $1; y2 = $2; magnitude = $3;
    dist = sqrt((x2 - x1)^2 + (y2 - y1)^2);
    if (dist <= 3 && (best == "" || dist < bestd)) {
      bestd = dist; best = x2" "y2" "magnitude;
    }
   } END { if (best != "") print best }' "$CAND_ALL"
  done < "$ARTSTARS_DIR"/coordinates.txt > "$ARTSTARS_DIR"/identified_artificial_stars.txt
  cat "$ARTSTARS_DIR"/identified_artificial_stars.txt >> "$IDENTIFIED_ARTSTARS_FOR_THIS_ITERATION_TMPFILE"

  # False positives (for purity): candidates that are neither within 3 px of an injected
  # star nor within 3 px of a baseline real (catalog-matched) transient. Real transients
  # are thus excluded from the purity denominator, while spurious detections still count.
  N_FALSE_POSITIVES_TOTAL=$[$N_FALSE_POSITIVES_TOTAL + $(awk -v injf="$ARTSTARS_DIR/coordinates.txt" -v ttf="$TRUE_TRANSIENTS_FILE" '
    FILENAME==injf { ix[++ni]=$1; iy[ni]=$2; next }
    FILENAME==ttf  { tx[++nt]=$1; ty[nt]=$2; next }
    {
     for ( i=1; i<=ni; i++ ) if ( sqrt(($1-ix[i])^2+($2-iy[i])^2) <= 3 ) next;
     for ( i=1; i<=nt; i++ ) if ( sqrt(($1-tx[i])^2+($2-ty[i])^2) <= 3 ) next;
     fp++;
    }
    END { print fp+0 }' "$ARTSTARS_DIR/coordinates.txt" "$TRUE_TRANSIENTS_FILE" "$CAND_ALL")]

  N_ARTSTARS_INSERTED_TOTAL=$[$N_ARTSTARS_INSERTED_TOTAL + $N_ARTSTARS_PER_ITER]

  ITERATION=$((ITERATION+1))
 done

 # Only run colstat when at least one injected star was recovered, otherwise colstat
 # divides by zero on empty input.
 if [ -s "$IDENTIFIED_ARTSTARS_FOR_THIS_ITERATION_TMPFILE" ];then
  COLSTAT_OUTPUT=$(awk '{print $3}' "$IDENTIFIED_ARTSTARS_FOR_THIS_ITERATION_TMPFILE" | util/colstat)
  N_FOUND=$(echo "$COLSTAT_OUTPUT" | grep 'N=' | head -n1 | awk '{print $2}')
  MEADIAN_MAG=$(echo "$COLSTAT_OUTPUT" | grep 'MEDIAN=' | awk '{print $2}')
 else
  N_FOUND=0
  MEADIAN_MAG=0.0000
 fi

 # C (completeness) = recovered injected stars / inserted injected stars.
 # P (purity) = recovered injected stars / (recovered injected stars + false positives),
 # where false positives exclude the field's real (catalog-matched) transients, identified
 # once by the baseline run. Real transients therefore corrupt neither C nor P.
 RECOVERED_FRACTION=$(echo "$N_FOUND $N_ARTSTARS_INSERTED_TOTAL" | awk '{ if($2>0) printf "%.4f",$1/$2; else printf "0.0000" }')
 C="$RECOVERED_FRACTION"
 P=$(echo "$N_FOUND $N_FALSE_POSITIVES_TOTAL" | awk '{ if($1+$2>0) printf "%.4f",$1/($1+$2); else printf "0.0000" }')
 F1=$(echo "$C $P" | awk '{ s=$1+$2; if(s>0) printf "%.4f",2*$1*$2/s; else printf "0.0000" }')
 F10=$(echo "$C $P" | awk -v beta=10 '{ s=$1+beta*beta*$2; if(s>0) printf "%.4f",(1+beta*beta)*$1*$2/s; else printf "0.0000" }')

 # Print the results only if some of the inserted stars were recovered
 if [ $N_FOUND -gt 0 ] && [ "$MEADIAN_MAG" != "0.0000" ] ;then
  echo "$MEADIAN_MAG $RECOVERED_FRACTION $N_FOUND / $N_ARTSTARS_INSERTED_TOTAL recovered (false_positives=$N_FALSE_POSITIVES_TOTAL)"
  printf "%5.2f %6.4f %4d %4d %6.4f %6.4f %6.4f\n" "$MEADIAN_MAG" "$RECOVERED_FRACTION" "$N_FOUND" "$N_ARTSTARS_INSERTED_TOTAL" "$P" "$F1" "$F10" >> artificial_star_test_results.txt
 fi
 
 rm -f "$IDENTIFIED_ARTSTARS_FOR_THIS_ITERATION_TMPFILE"

done # iteration over fluxes

echo "Test completed!
The results are saved to artificial_star_test_results.txt"

# Write the column-name header to a separate file. It is kept separate from the
# data file so that artificial_star_test_results.txt stays purely numeric and can
# be fed directly to gnuplot/awk, while the header can still be printed above it.
printf "%5s %6s %4s %4s %6s %6s %6s\n" "mag" "frac" "Ndet" "Nins" "P" "F1" "F10" > artificial_star_test_results_header.txt

# Print the column names above the values so the table is readable on stdout
cat artificial_star_test_results_header.txt
cat artificial_star_test_results.txt

echo "Trying to make a plot using gnuplot..."

echo "set terminal postscript eps enhanced color solid 'Times' 24 linewidth 2
set output 'artificial_star_test_results.eps'
set xlabel '(mag.)'
set ylabel 'Recovery fraction'
set yrange [0.5:1.0]
set format x '%4.1f'
set format y '%4.2f'
plot 'artificial_star_test_results.txt' u 1:2 pt 7 ps 1 lc '#33a02c' title ''
! convert -density 150 artificial_star_test_results.eps  -background white -alpha remove  artificial_star_test_results.png
" > artificial_star_test_results.gnuplot
cat artificial_star_test_results.gnuplot | gnuplot

if [ -s artificial_star_test_results.png ];then
 echo "gnuplot succeeded: the recovery-fraction plot is saved to artificial_star_test_results.png"
else
 echo "WARNING: gnuplot did not produce artificial_star_test_results.png (is gnuplot and ImageMagick 'convert'/'magick' installed?)"
fi
