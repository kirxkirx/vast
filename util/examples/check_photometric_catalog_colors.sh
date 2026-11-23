#!/usr/bin/env bash
#
# Check that the photometry in plate solver output catalogs (the *.wcscat.ucac5 files written
# by util/solve_plate_with_UCAC5) follows the colours of real stars. This check does not
# depend on numbers taken from VaST: it compares with the colours of stars. Two checks:
#
# 1. Rc-Ic against V-Rc, for the stars with 0.25 <= V-Rc < 0.60 (F to K stars): from F to K
#    stars Rc-Ic is nearly equal to V-Rc (the Sun: V-Rc 0.356, Rc-Ic 0.345, Ramirez et al.
#    2012, ApJ 752, 5; K0 stars about 0.47 and 0.42), and interstellar reddening moves stars
#    almost along that line, so the median of (Rc-Ic) - (V-Rc) has to lie between -0.15 and
#    +0.10. It needs no B magnitude, which APASS measures poorly for faint stars. Measured on
#    2026-11-23: -0.024 (APASS) and -0.003 (Gaia synthetic photometry) in the TESS field around
#    Nova Vul 2024, -0.032 (APASS) in the reddened field of Nova Cas 2021.
# 2. V-Rc, V-Ic and Rc-Ic of the stars with 0.55 <= B-V < 0.75 (late F and G stars, the Sun
#    has B-V = 0.65) and with B and V errors of 0.05 mag or less: the medians have to lie in
#      V-Rc   0.27 to 0.52     (the Sun: 0.356)
#      V-Ic   0.58 to 0.98     (the Sun: 0.701)
#      Rc-Ic  0.25 to 0.52     (the Sun: 0.345)
#    The ranges allow for the spread of spectral types within the B-V range and for reddening,
#    which makes the medians up to about 0.1 mag redder in Milky Way fields (in the TESS field
#    0.41, 0.80, 0.39 with APASS). Without the error limit a field like that of Nova Cas 2021,
#    whose faint stars have APASS B errors of 0.27 mag, fills the B-V range with red stars.
#
# Each check needs 20 stars; a catalog with fewer is not checked that way. An error of 0.2 mag
# or more in a colour transformation fails: the sign error that made the APASS Cousins I
# magnitudes 0.42 mag too faint until 2026-11-23 gave (Rc-Ic) - (V-Rc) = -0.44 and, in the B-V
# range, V-Ic 0.35 and Rc-Ic -0.05 in the TESS field. No test had noticed it for seven years,
# because the expected values of the tests had been taken from VaST itself.
#
# The catalog columns used (missing magnitudes are 0.000): 13 B, 14 its error, 15 V, 16 its
# error, 21 Rc, 23 Ic.
#
# Usage: util/examples/check_photometric_catalog_colors.sh CATALOG [CATALOG ...]
# One line per catalog goes to stdout. Exit code: 0 - every check that could be made passes;
# 1 - a check fails, or a catalog does not exist; 2 - no catalog had enough stars for either
# check, so nothing could be checked.
#

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

if [ $# -lt 1 ];then
 echo "Usage: $0 CATALOG [CATALOG ...]" >&2
 exit 1
fi

MIN_STARS=20
# The median of the numbers on stdin
median_of_input() {
 sort -n | awk '{ x[NR] = $1 } END { if (NR == 0) print "none" ; else if (NR % 2) printf "%.4f\n", x[(NR + 1) / 2] ; else printf "%.4f\n", (x[NR / 2] + x[NR / 2 + 1]) / 2 }'
}
# Print 1 if $1 lies between $2 and $3
# (no comparison inside a print argument list: mawk may take a > there for a redirection)
inside() {
 echo "$1 $2 $3" | awk '{ if ($1 + 0 >= $2 + 0 && $1 + 0 <= $3 + 0) print 1 ; else print 0 }'
}

EXIT_CODE=2
for CATALOG in "$@" ;do
 if [ ! -s "$CATALOG" ];then
  echo "$CATALOG: FAILED (no such catalog or an empty one)"
  EXIT_CODE=1
  continue
 fi
 RESULT=""
 FAILED=0
 CHECKED=0
 # 1. (Rc-Ic) - (V-Rc) for 0.25 <= V-Rc < 0.60
 N_FK=$(awk 'NF >= 24 && $15 + 0 != 0 && $21 + 0 != 0 && $23 + 0 != 0 && $15 - $21 >= 0.25 && $15 - $21 < 0.60' "$CATALOG" | wc -l | awk '{print $1}')
 if [ "$N_FK" -ge "$MIN_STARS" ];then
  CHECKED=1
  DIFFERENCE=$(awk 'NF >= 24 && $15 + 0 != 0 && $21 + 0 != 0 && $23 + 0 != 0 && $15 - $21 >= 0.25 && $15 - $21 < 0.60 { d = ($21 - $23) - ($15 - $21) ; print d }' "$CATALOG" | median_of_input)
  RESULT=$(echo "$N_FK $DIFFERENCE" | awk '{ printf "%d stars with 0.25 <= V-Rc < 0.60, median (Rc-Ic)-(V-Rc) %+.3f", $1, $2 }')
  if [ "$(inside "$DIFFERENCE" -0.15 0.10)" != "1" ];then
   RESULT="$RESULT (FAILED: outside -0.15..+0.10)"
   FAILED=1
  fi
 else
  RESULT="only $N_FK stars with V, Rc, Ic and 0.25 <= V-Rc < 0.60"
 fi
 # 2. V-Rc, V-Ic, Rc-Ic for 0.55 <= B-V < 0.75 with B and V errors up to 0.05 mag
 # (the stars of the B-V range, then the colour number $1 of them: 1 V-Rc, 2 V-Ic, 3 Rc-Ic)
 g_star_colors() {
  awk -v color="$1" 'NF >= 24 && $13 + 0 != 0 && $15 + 0 != 0 && $21 + 0 != 0 && $23 + 0 != 0 && $14 + 0 <= 0.05 && $16 + 0 <= 0.05 && $13 - $15 >= 0.55 && $13 - $15 < 0.75 {
   if (color == 1) print $15 - $21
   if (color == 2) print $15 - $23
   if (color == 3) print $21 - $23
  }' "$CATALOG"
 }
 N_G=$(g_star_colors 1 | wc -l | awk '{print $1}')
 if [ "$N_G" -ge "$MIN_STARS" ];then
  CHECKED=1
  VR=$(g_star_colors 1 | median_of_input)
  VI=$(g_star_colors 2 | median_of_input)
  RI=$(g_star_colors 3 | median_of_input)
  RESULT="$RESULT; $(echo "$N_G $VR $VI $RI" | awk '{ printf "%d stars with 0.55 <= B-V < 0.75 and B, V errors <= 0.05, median V-Rc %.3f, V-Ic %.3f, Rc-Ic %.3f", $1, $2, $3, $4 }')"
  OUTSIDE=""
  if [ "$(inside "$VR" 0.27 0.52)" != "1" ];then
   OUTSIDE="$OUTSIDE V-Rc"
  fi
  if [ "$(inside "$VI" 0.58 0.98)" != "1" ];then
   OUTSIDE="$OUTSIDE V-Ic"
  fi
  if [ "$(inside "$RI" 0.25 0.52)" != "1" ];then
   OUTSIDE="$OUTSIDE Rc-Ic"
  fi
  if [ -n "$OUTSIDE" ];then
   RESULT="$RESULT (FAILED: outside the range of real stars:$OUTSIDE)"
   FAILED=1
  fi
 else
  RESULT="$RESULT; only $N_G stars with 0.55 <= B-V < 0.75 and B, V errors <= 0.05"
 fi
 if [ "$FAILED" -eq 1 ];then
  echo "$CATALOG: $RESULT: FAILED"
  EXIT_CODE=1
 elif [ "$CHECKED" -eq 1 ];then
  echo "$CATALOG: $RESULT: OK"
  if [ "$EXIT_CODE" -eq 2 ];then
   EXIT_CODE=0
  fi
 else
  echo "$CATALOG: $RESULT: not checked (at least $MIN_STARS stars are needed for a check)"
 fi
done
exit "$EXIT_CODE"
