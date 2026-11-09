#!/usr/bin/env bash
#
# Test of the UV Ceti check util/transients/check_nearby_red_dwarf.sh: a nearby red dwarf
# at the position of a transient candidate, found among the Gaia DR3 stars closer than
# 200 pc after moving them with their proper motions to the epoch of the observation.
#
# Without arguments the test builds a small synthetic copy of the nearby-star catalog with
# lib/catalogs/local_star_catalog and checks the proper-motion propagation, the match
# radius, the epoch formats, the exit codes and the verdicts (a main-sequence red dwarf, a
# star far below the main sequence, a blue dwarf, a white dwarf, a giant, a star with an
# uncertain parallax, a pair of stars, no star at all). It needs no network and no real
# catalog, so it runs everywhere, GitHub Actions included.
#
# With the argument 'online' it also asks the ESA Gaia archive (and VizieR, when a mirror
# answers) about the Aur-05 candidate of 2026-11-08 (Gaia DR3 158334278606721152, a star
# 135 pc away and 5 mag below the main sequence) and about an empty position.
#
# Usage: util/examples/test_nearby_red_dwarf_check.sh [online]
# Exit codes: 0 all checks passed, 1 a check failed, 3 the ESA archive gave no reply,
# 4 VizieR gave no usable reply (3 and 4 are outages of the service, not failures).

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

FAILED_CODES=""
fail() {
 FAILED_CODES="$FAILED_CODES $1"
 echo "FAILED: $1 $2"
}

if [ ! -x lib/catalogs/local_star_catalog ];then
 echo "FAILED: UVCETI_LOCALSTARCAT_NOT_BUILT lib/catalogs/local_star_catalog is not built (run make)"
 exit 1
fi
if [ ! -x util/transients/check_nearby_red_dwarf.sh ];then
 echo "FAILED: UVCETI_SCRIPT_MISSING util/transients/check_nearby_red_dwarf.sh is not executable"
 exit 1
fi

WORK_DIR=$(mktemp -d 2>/dev/null || echo "nearby_red_dwarf_check_test_$$")
mkdir -p "$WORK_DIR" || exit 1
CATALOG_DIR="$WORK_DIR/gaia_dr3_nearby"

##### The synthetic catalog (ESA archive column names) #####
# 1001  M4 dwarf on the main sequence 20 pc away, moving 5"/yr (3"/yr east, 4"/yr south)
# 1002  the Aur-05 star: 135 pc, BP-RP 1.79, M_G 13.2 - far below the main sequence
# 1003  a blue (BP-RP 0.6) dwarf 50 pc away
# 1004  an uncertain parallax (6.0 +/- 2.5 mas): not considered
# 1005  too distant (parallax 2 mas): not in the catalog
# 1006  a red giant (M_G = -2) 125 pc away
# 1007  an overluminous M dwarf (young or binary) 33 pc away, without a proper motion
# 1008  a white dwarf 25 pc away
# 1009  a red dwarf 1.6 mag below the main sequence (a subdwarf) 100 pc away, moving 0.7"/yr
# 1010, 1011  two red dwarfs 1.8" apart, 50 pc away
# 1012  an AD Leo-like M3 dwarf 5 pc away: a parallax of 201 mas (the first version of the check
#       took every parallax above 99 mas for the 'unknown' placeholder and lost all such stars)
cat > "$WORK_DIR/nearby.csv" << 'EOF'
source_id,ra,dec,parallax,parallax_error,pmra,pmdec,phot_g_mean_mag,phot_bp_mean_mag,phot_rp_mean_mag,ruwe,phot_variable_flag
1001,150.0,20.0,50.0,0.05,3000.0,-4000.0,13.0,14.6,11.7,1.0,NOT_AVAILABLE
1002,72.34396294,29.43373748,7.4255,0.2274,15.6316,-25.8164,18.868677,19.67902,17.885542,1.022,VARIABLE
1003,200.0,-30.0,20.0,0.02,100.0,50.0,8.0,8.3,7.7,1.0,NOT_AVAILABLE
1004,10.0,10.0,6.0,2.5,0.0,0.0,20.5,21.0,19.5,1.2,NOT_AVAILABLE
1005,10.0,10.0,2.0,0.1,0.0,0.0,16.0,17.0,15.0,1.0,NOT_AVAILABLE
1006,30.0,30.0,8.0,0.1,0.0,0.0,3.5,4.07,2.77,1.0,NOT_AVAILABLE
1007,60.0,-60.0,30.0,0.1,,,14.0,16.21,12.51,1.0,NOT_AVAILABLE
1008,90.0,45.0,40.0,0.1,-200.0,300.0,15.0,15.1,14.9,1.0,NOT_AVAILABLE
1009,120.0,-10.0,10.0,0.1,500.0,-500.0,17.5,18.94,16.24,1.0,NOT_AVAILABLE
1010,240.0,0.0,20.0,0.1,0.0,0.0,12.0,12.95,10.95,1.0,NOT_AVAILABLE
1011,240.0005,0.0,20.0,0.1,0.0,0.0,12.3,13.25,11.25,1.0,NOT_AVAILABLE
1012,330.0,5.0,201.4,0.03,-500.0,-40.0,8.2,9.55,6.98,1.15,NOT_AVAILABLE
EOF
lib/catalogs/local_star_catalog nearby-extract "$WORK_DIR/staging" chunk 5.0 < "$WORK_DIR/nearby.csv" 2>/dev/null || fail UVCETI_EXTRACT
lib/catalogs/local_star_catalog finalize "$WORK_DIR/staging" "$CATALOG_DIR" gaia_dr3_nearby "synthetic nearby stars for the UV Ceti check test" 1 2>/dev/null || fail UVCETI_FINALIZE
grep -q '^records=11$' "$CATALOG_DIR/catalog_info.txt" 2>/dev/null || fail UVCETI_CATALOG_RECORDS "expected 11 of the 12 sources (the 2 mas one is out)"

# run the check against the synthetic copy; the output goes to CHECK_OUTPUT, the exit code to CHECK_EXIT
check() {
 CHECK_OUTPUT=$(UVCETI_SOURCE=local UVCETI_LOCAL_CATALOG="$CATALOG_DIR" util/transients/check_nearby_red_dwarf.sh "$@" 2>/dev/null)
 CHECK_EXIT=$?
}
expect_exit() {
 if [ "$CHECK_EXIT" -ne "$1" ];then
  fail "$2" "exit code $CHECK_EXIT, expected $1: $CHECK_OUTPUT"
  return 1
 fi
 return 0
}
expect_text() {
 if ! echo "$CHECK_OUTPUT" | grep -q -F -- "$1" ;then
  fail "$2" "missing '$1' in: $CHECK_OUTPUT"
 fi
}
expect_no_marker_phrases() {
 # the phrases the report parsers key on must never appear in the line
 if echo "$CHECK_OUTPUT" | grep -q -e 'The object was' -e 'found in' -e 'not found' -e 'mag brighter than the' ;then
  fail "$1" "a parser marker phrase in: $CHECK_OUTPUT"
 fi
}

##### 1001: the proper motion moves the star 50" in ten years #####
# at the position of 2026.0 (3"/yr east and 4"/yr south for 10 years), tolerance 3"
check 150.0088681 19.9888889 2026.0 3.0
if expect_exit 0 UVCETI_MS_EXIT ;then
 expect_text 'Gaia DR3 1001 at 0.0"' UVCETI_MS_SEPARATION
 expect_text '(50" at 2016.0)' UVCETI_MS_SEPARATION_2016
 expect_text 'd = 20 +/- 0 pc' UVCETI_MS_DISTANCE
 expect_text 'BP-RP = 2.90' UVCETI_MS_COLOUR
 expect_text 'M_G = 11.5' UVCETI_MS_ABSMAG
 expect_text 'on the main sequence (about M4 dwarf)' UVCETI_MS_VERDICT
 expect_text 'UV Ceti-type flare is likely' UVCETI_MS_FLARE
 expect_text 'positions at 2026.000' UVCETI_MS_EPOCH
 expect_text 'local copy' UVCETI_MS_SOURCE
 expect_no_marker_phrases UVCETI_MS_MARKERS
fi
MS_LINE="$CHECK_OUTPUT"
# the same epoch as a JD and as a date must give the same line
check 150.0088681 19.9888889 2461041.5 3.0
[ "$CHECK_OUTPUT" = "$MS_LINE" ] || fail UVCETI_EPOCH_JD "got: $CHECK_OUTPUT"
check 150.0088681 19.9888889 2026-01-01T00:00:00 3.0
[ "$CHECK_OUTPUT" = "$MS_LINE" ] || fail UVCETI_EPOCH_DATE "got: $CHECK_OUTPUT"
# at the catalog position of 2016.0 the star is 50" away by 2026.0: no match
check 150.0 20.0 2026.0 3.0
if expect_exit 1 UVCETI_PM_NOMATCH_EXIT ;then
 expect_text 'no such star within 3.0" of the position (the nearest is 50" away)' UVCETI_PM_NOMATCH_TEXT
 expect_no_marker_phrases UVCETI_PM_NOMATCH_MARKERS
fi
# at the catalog position and the catalog epoch it matches
check 150.0 20.0 2016.0 3.0
expect_exit 0 UVCETI_EPOCH2016_EXIT

##### 1002: the Aur-05 star, sexagesimal input, the TTU tolerance and the JD of the discovery #####
check 04:49:22.53 +29:26:01.6 2461353.7293 5.9
if expect_exit 2 UVCETI_COMPOSITE_EXIT ;then
 expect_text 'Gaia DR3 1002 at 0.6" (0.3" at 2016.0)' UVCETI_COMPOSITE_SEPARATION
 expect_text 'd = 135 +/- 4 pc' UVCETI_COMPOSITE_DISTANCE
 expect_text 'M_G = 13.2' UVCETI_COMPOSITE_ABSMAG
 expect_text 'below the main sequence' UVCETI_COMPOSITE_BELOW
 expect_text 'white dwarf + red dwarf binary or a cataclysmic variable' UVCETI_COMPOSITE_VERDICT
 expect_text 'positions at 2026.855' UVCETI_COMPOSITE_EPOCH
 expect_no_marker_phrases UVCETI_COMPOSITE_MARKERS
fi

##### 1003: a blue dwarf (the position of 2026.0) #####
check 200.0003208 -29.9998611 2026.0 3.0
if expect_exit 2 UVCETI_BLUE_EXIT ;then
 expect_text 'dwarf earlier than K0' UVCETI_BLUE_VERDICT
 expect_text 'BP-RP = 0.60' UVCETI_BLUE_COLOUR
fi

##### 1004 and 1005: an uncertain parallax and a distant star are not nearby stars #####
check 10.0 10.0 2026.0 3.0
if expect_exit 1 UVCETI_UNCERTAIN_EXIT ;then
 expect_text 'no such star within 113" of the position.' UVCETI_UNCERTAIN_TEXT
fi

##### 1006: a red giant #####
check 30.0 30.0 2026.0 3.0
if expect_exit 2 UVCETI_GIANT_EXIT ;then
 expect_text 'giant or subgiant' UVCETI_GIANT_VERDICT
 expect_text 'M_G = -2.0' UVCETI_GIANT_ABSMAG
fi

##### 1007: an overluminous red dwarf without a proper motion #####
check 60.0 -60.0 2026.0 3.0
if expect_exit 0 UVCETI_YOUNG_EXIT ;then
 expect_text 'no proper motion in Gaia' UVCETI_YOUNG_NOPM
 expect_text 'above the main sequence (a young star or an unresolved binary' UVCETI_YOUNG_VERDICT
 expect_text 'UV Ceti-type flare is likely' UVCETI_YOUNG_FLARE
fi

##### 1008: a white dwarf (the position of 2026.0) #####
check 89.9992143 45.0008333 2026.0 3.0
if expect_exit 2 UVCETI_WD_EXIT ;then
 expect_text 'white dwarf (blue and faint)' UVCETI_WD_VERDICT
fi

##### 1009: a red dwarf 1.6 mag below the main sequence, 7" of proper motion in ten years #####
check 120.0014103 -10.0013889 2026.0 3.0
if expect_exit 0 UVCETI_SUBDWARF_EXIT ;then
 expect_text 'below the main sequence (a metal-poor subdwarf or a composite system' UVCETI_SUBDWARF_VERDICT
 expect_text 'UV Ceti-type flare is plausible' UVCETI_SUBDWARF_FLARE
fi
check 120.0 -10.0 2026.0 3.0
if expect_exit 1 UVCETI_SUBDWARF_2016_EXIT ;then
 expect_text 'the nearest is 7.1" away' UVCETI_SUBDWARF_2016_TEXT
fi

##### 1010 and 1011: two red dwarfs within the tolerance #####
check 240.0 0.0 2026.0 3.0
if expect_exit 0 UVCETI_PAIR_EXIT ;then
 expect_text 'Gaia DR3 1010 at 0.0"' UVCETI_PAIR_CLOSEST
 expect_text '(and 1 more within 3.0")' UVCETI_PAIR_MORE
 expect_text 'about M1 dwarf' UVCETI_PAIR_TYPE
fi

##### 1012: a star 5 pc away with a parallax of 201 mas, 5" of proper motion in ten years #####
check 329.9986058 4.9998889 2026.0 3.0
if expect_exit 0 UVCETI_HIGHPLX_EXIT ;then
 expect_text 'Gaia DR3 1012 at 0.0"' UVCETI_HIGHPLX_STAR
 expect_text 'd = 5 +/- 0 pc' UVCETI_HIGHPLX_DISTANCE
 expect_text 'on the main sequence (about M3 dwarf)' UVCETI_HIGHPLX_VERDICT
fi

##### an empty position #####
check 300.0 50.0 2026.0 3.0
if expect_exit 1 UVCETI_EMPTY_EXIT ;then
 expect_text 'no such star within 113" of the position.' UVCETI_EMPTY_TEXT
fi

##### the default epoch (now) and the default tolerance #####
check 240.0 0.0
expect_exit 0 UVCETI_DEFAULTS_EXIT

##### no local copy and no online services allowed: not performed #####
CHECK_OUTPUT=$(UVCETI_SOURCE=local UVCETI_LOCAL_CATALOG="$WORK_DIR/no_such_catalog" util/transients/check_nearby_red_dwarf.sh 240.0 0.0 2026.0 3.0 2>/dev/null)
CHECK_EXIT=$?
if expect_exit 3 UVCETI_NOTPERFORMED_EXIT ;then
 expect_text 'UV Ceti check: not performed' UVCETI_NOTPERFORMED_TEXT
fi

##### usage errors #####
check
expect_exit 4 UVCETI_USAGE_NOARGS
check 240.0 0.0 yesterday 3.0
expect_exit 4 UVCETI_USAGE_EPOCH
check 240.0 0.0 2026.0 -1
expect_exit 4 UVCETI_USAGE_RADIUS
check 24:00:00 0.0 2026.0 3.0
expect_exit 4 UVCETI_USAGE_RA

rm -rf "${WORK_DIR:?}"

##### online: the ESA Gaia archive and VizieR on the real sky #####
ONLINE_STATUS=0
if [ "$1" = "online" ];then
 echo "Asking the ESA Gaia archive about the Aur-05 candidate"
 CHECK_OUTPUT=$(UVCETI_SOURCE=esa_tap util/transients/check_nearby_red_dwarf.sh 04:49:22.53 +29:26:01.6 2461353.7293 5.9 2>/dev/null)
 CHECK_EXIT=$?
 if [ "$CHECK_EXIT" -eq 3 ];then
  echo "The ESA Gaia archive gave no reply: $CHECK_OUTPUT"
  ONLINE_STATUS=3
 else
  if expect_exit 2 UVCETI_ONLINE_ESA_EXIT ;then
   expect_text 'Gaia DR3 158334278606721152 at 0.6" (0.3" at 2016.0)' UVCETI_ONLINE_ESA_STAR
   expect_text 'd = 135 +/- 4 pc' UVCETI_ONLINE_ESA_DISTANCE
   expect_text 'below the main sequence' UVCETI_ONLINE_ESA_VERDICT
   expect_text 'ESA archive' UVCETI_ONLINE_ESA_SOURCE
  fi
  # a position near the north galactic pole without a star closer than 200 pc around it
  CHECK_OUTPUT=$(UVCETI_SOURCE=esa_tap util/transients/check_nearby_red_dwarf.sh 192.85949 27.12835 2026.0 5.0 2>/dev/null)
  CHECK_EXIT=$?
  if [ "$CHECK_EXIT" -eq 3 ];then
   echo "The ESA Gaia archive gave no reply: $CHECK_OUTPUT"
   ONLINE_STATUS=3
  elif expect_exit 1 UVCETI_ONLINE_ESA_EMPTY_EXIT ;then
   expect_text 'no such star within' UVCETI_ONLINE_ESA_EMPTY_TEXT
  fi
  # UV Cet itself (Gl 65 A+B, 2.7 pc, 3.4"/yr): both components land within 3" of this
  # position at epoch 2026.9 after moving 38" from their Gaia positions; a M5-M6 dwarf on
  # the main sequence by BP-RP (by G-RP it would sit 1.6 mag below it, which is why G-RP is
  # not a cross-check)
  CHECK_OUTPUT=$(UVCETI_SOURCE=esa_tap util/transients/check_nearby_red_dwarf.sh 24.7826 -17.9459 2026.9 10.0 2>/dev/null)
  CHECK_EXIT=$?
  if [ "$CHECK_EXIT" -eq 3 ];then
   echo "The ESA Gaia archive gave no reply: $CHECK_OUTPUT"
   ONLINE_STATUS=3
  elif expect_exit 0 UVCETI_ONLINE_ESA_UVCET_EXIT ;then
   expect_text '(and 1 more within 10")' UVCETI_ONLINE_ESA_UVCET_PAIR
   expect_text 'd = 3 +/- 0 pc' UVCETI_ONLINE_ESA_UVCET_DISTANCE
   expect_text 'on the main sequence (about M' UVCETI_ONLINE_ESA_UVCET_VERDICT
   expect_text 'UV Ceti-type flare is likely' UVCETI_ONLINE_ESA_UVCET_FLARE
  fi
 fi
 echo "Asking VizieR about the Aur-05 candidate"
 CHECK_OUTPUT=$(UVCETI_SOURCE=vizquery util/transients/check_nearby_red_dwarf.sh 04:49:22.53 +29:26:01.6 2461353.7293 5.9 2>/dev/null)
 CHECK_EXIT=$?
 if [ "$CHECK_EXIT" -eq 3 ];then
  echo "VizieR gave no usable reply: $CHECK_OUTPUT"
  if [ "$ONLINE_STATUS" -eq 0 ];then
   ONLINE_STATUS=4
  fi
 elif expect_exit 2 UVCETI_ONLINE_VIZIER_EXIT ;then
  expect_text 'Gaia DR3 158334278606721152 at 0.6" (0.3" at 2016.0)' UVCETI_ONLINE_VIZIER_STAR
  expect_text 'VizieR' UVCETI_ONLINE_VIZIER_SOURCE
 fi
fi

if [ -n "$FAILED_CODES" ];then
 echo "Failed checks:$FAILED_CODES"
 exit 1
fi
if [ "$ONLINE_STATUS" -ne 0 ];then
 exit "$ONLINE_STATUS"
fi
echo "All UV Ceti check tests passed"
exit 0
