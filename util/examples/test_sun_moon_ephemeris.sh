#!/usr/bin/env bash
#
# Check util/sun_moon (src/sun_moon.c: own code for the Sun, the Moon and the moonlight at a
# target) against astropy, which computes the same quantities independently: the altitudes of
# the Sun, the Moon and a target, the Moon's illuminated fraction and its distance from the
# target, for a few hundred random times between 2000 and 2026 at three sites (NMW-TexasTech,
# NMW Classic and a southern one). The moonlight model of Krisciunas & Schaefer (1991, PASP
# 103, 1033) is implemented a second time in Python here and applied to astropy's geometry,
# which checks the C implementation of the formulae, and the model's verdicts are checked for
# plausibility: no brightening without the Moon, a bright full Moon brightens a dark sky by
# well over a magnitude.
#
# astropy uses its built-in ephemerides (no downloads, also no IERS tables): the comparison has
# to run offline, on GitHub Actions too.
#
# Usage: util/examples/test_sun_moon_ephemeris.sh
# Run it from the VaST directory after 'make'. It prints "FAILED: CODE description" lines for
# the failed checks. Exit codes: 0 all checks passed, 1 a check failed, 2 not performed
# (no python3 with astropy, or util/sun_moon is not built; a "NOT_PERFORMED: CODE" line says why).

#################################
# Set the safe locale that should be available on any POSIX system
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Work from the VaST directory: this script lives in util/examples/
VAST_DIR=$(cd "$(dirname "$0")/../.." && pwd)
if [ -z "$VAST_DIR" ] || ! cd "$VAST_DIR" ;then
 echo "ERROR: cannot change to the VaST directory"
 exit 1
fi

if [ ! -x util/sun_moon ];then
 echo "NOT_PERFORMED: SUNMOON_NOT_BUILT util/sun_moon is not built - run 'make' first"
 exit 2
fi
if ! command -v python3 &>/dev/null || ! python3 -c "import astropy, numpy" &>/dev/null ;then
 echo "NOT_PERFORMED: SUNMOON_NO_ASTROPY python3 with astropy and numpy is needed for this test"
 exit 2
fi

# Tolerances: the Sun to 0.05 deg and the Moon to 0.1 deg in altitude (the algorithms are
# good to 0.01 deg and 10 arcsec; nutation and aberration, below 0.01 deg, are left out on
# purpose), the illuminated fraction to 0.01, the moonlight brightening to 0.05 mag
TOLERANCE_SUN_ALT_DEG=0.05
TOLERANCE_MOON_ALT_DEG=0.1
TOLERANCE_TARGET_ALT_DEG=0.05
TOLERANCE_SEPARATION_DEG=0.1
TOLERANCE_ILLUMINATED_FRACTION=0.01
TOLERANCE_BRIGHTENING_MAG=0.05
# the moonlight model parameters used for all the test cases
EXTINCTION_MAG=0.20
DARK_SKY_V_MAG_ARCSEC2=21.0

WORK_DIR=$(mktemp -d 2>/dev/null || echo "test_sun_moon_ephemeris_$$")
mkdir -p "$WORK_DIR" || exit 1
REFERENCE_FILE="$WORK_DIR/astropy_reference.txt"
COMPARISON_FILE="$WORK_DIR/comparison.txt"

# The reference values: one line per case
#   jd lat lon height ra dec sun_alt moon_alt illuminated_fraction separation target_alt
#   phase_angle brightening_mag
# Python runs in the empty work directory, so that nothing is imported from the current
# directory (python3 -I would also hide the user's site-packages, where astropy often is)
( cd "$WORK_DIR" && python3 - "$EXTINCTION_MAG" "$DARK_SKY_V_MAG_ARCSEC2" ) > "$REFERENCE_FILE" 2> "$WORK_DIR/astropy_stderr.txt" << 'PYTHON_END'
import sys
import warnings
import numpy as np
from astropy.time import Time
from astropy.coordinates import EarthLocation, AltAz, SkyCoord, get_body
import astropy.units as u
from astropy.utils import iers

warnings.simplefilter('ignore')
# Offline: no IERS downloads; UT1-UTC is below 0.9 s, which does not matter here
iers.conf.auto_download = False
try:
    iers.conf.auto_max_age = None
except Exception:
    pass
try:
    iers.conf.iers_degraded_accuracy = 'ignore'
except Exception:
    pass

extinction = float(sys.argv[1])
dark_sky_v = float(sys.argv[2])


def ks1991_brightening(phase_angle_deg, separation_deg, moon_alt_deg, target_alt_deg, k, v_zen):
    # Krisciunas & Schaefer 1991, PASP 103, 1033: eqs. 1, 2, 3, 15, 20, 21
    if moon_alt_deg <= 0.0 or target_alt_deg <= 0.0:
        return 0.0
    alpha = abs(phase_angle_deg)
    rho = np.radians(separation_deg)
    illuminance = 10.0 ** (-0.4 * (3.84 + 0.026 * alpha + 4.0e-9 * alpha ** 4))
    scattering = 10.0 ** 5.36 * (1.06 + np.cos(rho) ** 2) + 10.0 ** (6.15 - separation_deg / 40.0)
    x_moon = (1.0 - 0.96 * np.sin(np.radians(90.0 - moon_alt_deg)) ** 2) ** -0.5
    x_target = (1.0 - 0.96 * np.sin(np.radians(90.0 - target_alt_deg)) ** 2) ** -0.5
    b_moon = scattering * illuminance * 10.0 ** (-0.4 * k * x_moon) * (1.0 - 10.0 ** (-0.4 * k * x_target))
    b_zenith = 34.08 * np.exp(20.7233 - 0.92104 * v_zen)
    b_sky = b_zenith * 10.0 ** (-0.4 * k * (x_target - 1.0)) * x_target
    return 2.5 * np.log10((b_moon + b_sky) / b_sky)


# NMW-TexasTech, NMW Classic, and a southern site
sites = [(33.7480556, -101.9583333, 1015.0), (43.6495869, 41.4253233, 2000.0), (-30.2446, -70.7494, 2650.0)]
rng = np.random.RandomState(20261123)
n_per_site = 150
for lat, lon, height in sites:
    location = EarthLocation(lat=lat * u.deg, lon=lon * u.deg, height=height * u.m)
    # 2000-01-01 to 2026-12-31
    jd = rng.uniform(2451544.5, 2461406.5, n_per_site)
    ra = rng.uniform(0.0, 360.0, n_per_site)
    dec = np.degrees(np.arcsin(rng.uniform(-1.0, 1.0, n_per_site)))
    times = Time(jd, format='jd', scale='utc')
    frame = AltAz(obstime=times, location=location)
    sun_altaz = get_body('sun', times, location).transform_to(frame)
    moon_altaz = get_body('moon', times, location).transform_to(frame)
    target_altaz = SkyCoord(ra=ra * u.deg, dec=dec * u.deg, frame='icrs').transform_to(frame)
    # the phase angle from the geocentric positions
    sun_geo = get_body('sun', times)
    moon_geo = get_body('moon', times)
    elongation = sun_geo.separation(moon_geo).radian
    r_sun = sun_geo.distance.to(u.km).value
    r_moon = moon_geo.distance.to(u.km).value
    phase_angle = np.arctan2(r_sun * np.sin(elongation), r_moon - r_sun * np.cos(elongation))
    illuminated_fraction = (1.0 + np.cos(phase_angle)) / 2.0
    separation = moon_altaz.separation(target_altaz).deg
    for i in range(n_per_site):
        brightening = ks1991_brightening(np.degrees(phase_angle[i]), separation[i], moon_altaz.alt.deg[i],
                                         target_altaz.alt.deg[i], extinction, dark_sky_v)
        print('%.6f %.7f %.7f %.1f %.6f %.6f %.5f %.5f %.6f %.5f %.5f %.5f %.5f' % (
            jd[i], lat, lon, height, ra[i], dec[i], sun_altaz.alt.deg[i], moon_altaz.alt.deg[i],
            illuminated_fraction[i], separation[i], target_altaz.alt.deg[i], np.degrees(phase_angle[i]),
            brightening))
PYTHON_END
if [ $? -ne 0 ] || [ ! -s "$REFERENCE_FILE" ];then
 echo "FAILED: SUNMOON_ASTROPY_ERROR astropy could not compute the reference values:"
 tail -n 5 "$WORK_DIR/astropy_stderr.txt"
 rm -rf "${WORK_DIR:?}"
 exit 1
fi

# util/sun_moon for every case, next to astropy's values
while read -r JD LAT LON HEIGHT RA DEC REF_SUN_ALT REF_MOON_ALT REF_ILLUMINATED REF_SEPARATION REF_TARGET_ALT REF_PHASE_ANGLE REF_BRIGHTENING ;do
 SUN_MOON_OUTPUT=$(util/sun_moon "$JD" "$LAT" "$LON" "$HEIGHT" "$RA" "$DEC" "$EXTINCTION_MAG" "$DARK_SKY_V_MAG_ARCSEC2")
 if [ $? -ne 0 ];then
  echo "FAILED: SUNMOON_RUN util/sun_moon $JD $LAT $LON $HEIGHT $RA $DEC failed"
  rm -rf "${WORK_DIR:?}"
  exit 1
 fi
 echo "$JD $REF_SUN_ALT $REF_MOON_ALT $REF_ILLUMINATED $REF_SEPARATION $REF_TARGET_ALT $REF_PHASE_ANGLE $REF_BRIGHTENING $(echo "$SUN_MOON_OUTPUT" | awk -F'=' '{v[$1] = $2} END {print v["sun_alt_deg"], v["moon_alt_deg"], v["moon_illuminated_fraction"], v["moon_target_separation_deg"], v["target_alt_deg"], v["moon_sky_brightening_mag"]}')"
done < "$REFERENCE_FILE" > "$COMPARISON_FILE"

N_CASES=$(wc -l < "$COMPARISON_FILE" | tr -d ' ')
if [ "$N_CASES" -lt 400 ];then
 echo "FAILED: SUNMOON_TOO_FEW_CASES only $N_CASES cases were compared"
 rm -rf "${WORK_DIR:?}"
 exit 1
fi

# The largest differences. The brightening is compared only where the Moon and the target are
# clearly above the horizon: right at the horizon a tiny difference in altitude switches the
# model between zero and a finite value.
# Fields: 1 jd, 2-8 astropy (sun_alt moon_alt illum sep target_alt phase_angle brightening),
# 9-14 util/sun_moon (sun_alt moon_alt illum sep target_alt brightening)
MAX_DIFFERENCES=$(awk 'function absval(x) { if (x < 0) return -x ; return x }
{
 d = absval($2 - $9) ; if (d > max_sun) max_sun = d
 d = absval($3 - $10) ; if (d > max_moon) max_moon = d
 d = absval($4 - $11) ; if (d > max_illum) max_illum = d
 d = absval($5 - $12) ; if (d > max_sep) max_sep = d
 d = absval($6 - $13) ; if (d > max_target) max_target = d
 if (absval($3) > 0.5 && $6 > 5.0) {
  d = absval($8 - $14) ; if (d > max_bright) max_bright = d
  n_bright++
 }
}
END { printf "%.5f %.5f %.5f %.5f %.5f %.5f %d\n", max_sun, max_moon, max_illum, max_sep, max_target, max_bright, n_bright }' "$COMPARISON_FILE")
read -r MAX_SUN_ALT MAX_MOON_ALT MAX_ILLUMINATED MAX_SEPARATION MAX_TARGET_ALT MAX_BRIGHTENING N_BRIGHTENING <<< "$MAX_DIFFERENCES"
echo "util/sun_moon vs astropy, $N_CASES cases at three sites, 2000-2026; largest differences:"
echo " Sun altitude $MAX_SUN_ALT deg (tolerance $TOLERANCE_SUN_ALT_DEG)"
echo " Moon altitude $MAX_MOON_ALT deg (tolerance $TOLERANCE_MOON_ALT_DEG)"
echo " Moon illuminated fraction $MAX_ILLUMINATED (tolerance $TOLERANCE_ILLUMINATED_FRACTION)"
echo " Moon-target separation $MAX_SEPARATION deg (tolerance $TOLERANCE_SEPARATION_DEG)"
echo " target altitude $MAX_TARGET_ALT deg (tolerance $TOLERANCE_TARGET_ALT_DEG)"
echo " moonlight brightening $MAX_BRIGHTENING mag in $N_BRIGHTENING cases with the Moon and the target up (tolerance $TOLERANCE_BRIGHTENING_MAG)"

TEST_FAILED=0
check_tolerance() {
 # Arguments: CODE VALUE TOLERANCE DESCRIPTION
 if awk -v v="$2" -v t="$3" 'BEGIN { if (v + 0 <= t + 0) exit 0 ; exit 1 }' ;then
  return 0
 fi
 echo "FAILED: $1 $4 differs from astropy by $2, more than $3"
 TEST_FAILED=1
 return 1
}
check_tolerance SUNMOON_SUN_ALT "$MAX_SUN_ALT" "$TOLERANCE_SUN_ALT_DEG" "the Sun altitude"
check_tolerance SUNMOON_MOON_ALT "$MAX_MOON_ALT" "$TOLERANCE_MOON_ALT_DEG" "the Moon altitude"
check_tolerance SUNMOON_ILLUMINATED_FRACTION "$MAX_ILLUMINATED" "$TOLERANCE_ILLUMINATED_FRACTION" "the Moon illuminated fraction"
check_tolerance SUNMOON_SEPARATION "$MAX_SEPARATION" "$TOLERANCE_SEPARATION_DEG" "the Moon-target separation"
check_tolerance SUNMOON_TARGET_ALT "$MAX_TARGET_ALT" "$TOLERANCE_TARGET_ALT_DEG" "the target altitude"
check_tolerance SUNMOON_BRIGHTENING "$MAX_BRIGHTENING" "$TOLERANCE_BRIGHTENING_MAG" "the moonlight brightening"
if [ "$N_BRIGHTENING" -lt 50 ];then
 echo "FAILED: SUNMOON_FEW_MOONLIT_CASES only $N_BRIGHTENING cases with the Moon and the target above the horizon"
 TEST_FAILED=1
fi

# Plausibility of the moonlight model verdicts (util/sun_moon values):
# - the Moon below the horizon brightens nothing;
# - a nearly full Moon (illuminated > 0.95) more than 30 deg up, with the target also more than
#   30 deg up and 30-100 deg away from it, brightens a 21.0 mag/arcsec^2 sky by more than 1.5 mag;
# - a thin crescent (illuminated < 0.05) brightens it by less than 0.1 mag.
PLAUSIBILITY=$(awk '{
 if ($10 < -0.5 && $14 != 0) bad_down++
 if ($11 > 0.95 && $10 > 30 && $13 > 30 && $12 > 30 && $12 < 100) { n_full++ ; if ($14 <= 1.5) bad_full++ }
 if ($11 < 0.05 && $14 >= 0.1) bad_thin++
}
END { printf "%d %d %d %d\n", bad_down, n_full, bad_full, bad_thin }' "$COMPARISON_FILE")
read -r BAD_DOWN N_FULL BAD_FULL BAD_THIN <<< "$PLAUSIBILITY"
echo "Moonlight plausibility: $BAD_DOWN brightened skies with the Moon down, $BAD_FULL of $N_FULL bright-full-Moon cases below 1.5 mag, $BAD_THIN thin-crescent cases above 0.1 mag"
if [ "$BAD_DOWN" -ne 0 ];then
 echo "FAILED: SUNMOON_BRIGHTENING_MOON_DOWN the sky is brightened with the Moon below the horizon"
 TEST_FAILED=1
fi
if [ "$BAD_FULL" -ne 0 ];then
 echo "FAILED: SUNMOON_BRIGHTENING_FULL_MOON a bright full Moon brightens the dark sky by less than 1.5 mag"
 TEST_FAILED=1
fi
if [ "$BAD_THIN" -ne 0 ];then
 echo "FAILED: SUNMOON_BRIGHTENING_THIN_CRESCENT a thin crescent brightens the dark sky by 0.1 mag or more"
 TEST_FAILED=1
fi

rm -rf "${WORK_DIR:?}"
if [ "$TEST_FAILED" -ne 0 ];then
 exit 1
fi
echo "All Sun and Moon checks passed"
exit 0
