#!/usr/bin/env bash

# general settings
N_ARTSTARS_PER_ITER=100
N_ITERATIONS=1

function print_usage_and_exit() {
 echo "Usage: 
 REFERENCE_IMAGES=../NMW__NovaVul24_Stas_test/reference_images/ $0 ../NMW__NovaVul24_Stas_test/second_epoch_images_wcs
where ../NMW__NovaVul24_Stas_test/reference_images/ is the reference images directory and 
../NMW__NovaVul24_Stas_test/second_epoch_images_wcs is the new images directory. 
The input should be similar to that of util/transients/transient_factory_test31.sh script."
 exit 1
}

if [ -z "$REFERENCE_IMAGES" ];then
 REFERENCE_IMAGES="../NMW__NovaVul24_Stas_test/reference_images/"
fi
export REFERENCE_IMAGES

THIS_IS_ARTIFICIAL_STAR_TEST_DO_NO_ONLINE_SEARCH=1
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

# do a SE run to determine stars FWHM and calibrate star fluxes
lib/sextract_single_image_noninteractive "$FIRST_IMAGE_TO_BE_MODIFIED"
if [ $? -ne 0 ];then
 echo "ERROR in $0: non-zero exit code of lib/sextract_single_image_noninteractive $FIRST_IMAGE_TO_BE_MODIFIED"
 exit 1
fi
if [ ! -s "image00000.cat" ];then
 echo "ERROR in $0: no useful image00000.cat created"
 exit 1
fi
FLUX=$(cat image00000.cat | awk '{print $2}' | util/colstat | grep 'percen80=' | awk '{print $2}')
FWHM=$(cat image00000.cat | awk '{print $23}' | util/colstat | grep 'MEDIAN=' | awk '{print $2}')
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
echo $0 | grep --quiet 'run_artificial_star_test_oneflux.sh'
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
 N_CANDIDATES_FOUND_TOTAL=0
 N_ARTSTARS_INSERTED_TOTAL=0
 IDENTIFIED_ARTSTARS_FOR_THIS_ITERATION_TMPFILE=$(mktemp)
 for ITERATION in $(seq 1 $N_ITERATIONS) ;do

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

  # Create the list of candidate transients and their magnitudes
  # WARNING: cannot use 'Discovery image 1' as this will be first-epoch image for the transients detected via the flare channel
  # 'Discovery image 2' should be one of the second-epoch images for both 'transients' and 'flares'
  # WARNING: 'Discovery image 2' appears in the processing log, not only in the candidates list!
  # in awk, the NF condition checks if there are any fields in the line (NF = Number of Fields).
  grep -B100000 'Processig complete' transient_report/index.html | grep 'Discovery image 2' | awk -F'<td>' '{print $5" "$7}' | awk 'NF {print $3" "$4" "$1}' | sort | uniq > "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"__artificialstars/candidate_coordinates_and_magnitudes.txt
  N_CANDIDATES_FOUND_TOTAL=$[$N_CANDIDATES_FOUND_TOTAL + $(cat "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"__artificialstars/candidate_coordinates_and_magnitudes.txt | wc -l)]
 
  # Loop over each point in coordinates.txt
  while read -r x1 y1; do
   # For each point in coordinates.txt, compare with points in candidate_coordinates_and_magnitudes.txt
   awk -v x1="$x1" -v y1="$y1" '{
    x2 = $1; y2 = $2; magnitude = $3;
    dist = sqrt((x2 - x1)^2 + (y2 - y1)^2);
    if (dist <= 3) {
      print x2, y2, magnitude;
    }
   }' "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"__artificialstars/candidate_coordinates_and_magnitudes.txt
  done < "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"__artificialstars/coordinates.txt > "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"__artificialstars/identified_artificial_stars.txt
 
  cat "$PLATE_SOLVED_SECOND_EPOCH_IMAGES_DIR"__artificialstars/identified_artificial_stars.txt >> "$IDENTIFIED_ARTSTARS_FOR_THIS_ITERATION_TMPFILE"
 
  N_ARTSTARS_INSERTED_TOTAL=$[$N_ARTSTARS_INSERTED_TOTAL + $N_ARTSTARS_PER_ITER]

 done

 COLSTAT_OUTPUT=$(cat "$IDENTIFIED_ARTSTARS_FOR_THIS_ITERATION_TMPFILE" | awk '{print $3}' | util/colstat)
 N_FOUND=$(echo "$COLSTAT_OUTPUT" | grep 'N=' | head -n1 | awk '{print $2}')
 MEADIAN_MAG=$(echo "$COLSTAT_OUTPUT" | grep 'MEDIAN=' | awk '{print $2}')

 RECOVERED_FRACTION=$(echo "$N_FOUND $N_ARTSTARS_INSERTED_TOTAL" | awk '{printf "%.4f",$1/$2}')

 # The C P F1 F10 are computed assuming there are no real transients in the input data!
 C="$RECOVERED_FRACTION"
 P=$(echo "$N_FOUND $N_CANDIDATES_FOUND_TOTAL" | awk '{printf "%.4f",$1/$2}')
 F1=$(echo "$C $P" | awk '{printf "%.4f",2*$1*$2/($1+$2)}')
 F10=$(echo "$C $P" | awk -v beta=10 '{printf "%.4f",(1+beta*beta)*$1*$2/($1+beta*beta*$2)}')

 # Print the results only if some of the inserted stars were recovered
 if [ $N_FOUND -gt 0 ] && [ "$MEADIAN_MAG" != "0.0000" ] ;then
  echo $MEADIAN_MAG $RECOVERED_FRACTION $N_FOUND / $N_ARTSTARS_INSERTED_TOTAL
  echo $MEADIAN_MAG $RECOVERED_FRACTION $N_FOUND $N_ARTSTARS_INSERTED_TOTAL  $P $F1 $F10 >> artificial_star_test_results.txt
 fi
 
 rm -f "$IDENTIFIED_ARTSTARS_FOR_THIS_ITERATION_TMPFILE"

done # iteration over fluxes

echo "Test completed!
The results are saved to artificial_star_test_results.txt"
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
