#!/usr/bin/env python3
"""
Planet position calculator using skyfield library.
Computes apparent positions of major planets for a given Julian Date.

Usage: python3 main.py calc -d JD [-observatory CODE] [-q]

Output format matches util/planets.sh:
  HH:MM:SS.SS +DD:MM:SS.S Planet_Name (X.Xmag)
"""

import os
import sys
import argparse
import math
import fcntl
import time

# Attempt imports - will fail gracefully if not available
try:
    from skyfield.api import Loader, Topos
    from skyfield.magnitudelib import planetary_magnitude
    SKYFIELD_AVAILABLE = True
except ImportError:
    SKYFIELD_AVAILABLE = False

# Data directory - shared with comet_finder to avoid duplicate ephemeris downloads
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
COMET_FINDER_DATA_DIR = os.path.join(SCRIPT_DIR, "..", "comet_finder", "data")
LOCAL_DATA_DIR = os.path.join(SCRIPT_DIR, "data")

# Ephemeris file
EPHEMERIDES_FILE = "de421.bsp"

# MPC observatory data
LOCAL_OBSERVATORY_FILE = "ObsCodes.html"
OBSERVATORY_CACHE_FILE = "observatory_codes.csv"
MPC_OBSERVATORY_URL = "https://www.minorplanetcenter.net/iau/lists/ObsCodes.html"
MPC_OBSERVATORY_URL_BACKUP = "http://kirx.net/iau/lists/ObsCodes.html"

# Planets to compute (matching planets.sh)
PLANETS = [
    ("mercury", "Mercury"),
    ("venus", "Venus"),
    ("mars", "Mars"),
    ("jupiter barycenter", "Jupiter"),
    ("saturn barycenter", "Saturn"),
    ("uranus barycenter", "Uranus"),
    ("neptune barycenter", "Neptune"),
    ("pluto barycenter", "Pluto"),
    ("moon", "Moon"),
]

# Global loader
load = None


def main():
    global load

    if not SKYFIELD_AVAILABLE:
        echo("ERROR: skyfield library not available", force_output=True)
        sys.exit(1)

    args = parse_args()

    # Initialize loader with appropriate data directory
    data_dir = get_data_directory()
    load = Loader(data_dir)
    load.verbose = not args.quiet

    # Create timescale and date
    # Input JD is in UT, not TT - use utc or ut1 for proper handling
    ts = load.timescale()
    if args.date != 0:
        # Input is JD(UT) - use ut1 for better accuracy with UT input
        # Note: ut1 and utc are very close (within 0.9 seconds)
        date = ts.ut1_jd(args.date)
    else:
        date = ts.now()

    try:
        # Get observer position
        lat, lon = get_observer_position(args.lat, args.long, args.observatory)

        if args.command == 'calc':
            calc_planets(date, lat, lon, ts)
        else:
            echo(f"Unknown command: {args.command}", force_output=True)
            sys.exit(1)

    except Exception as e:
        echo(f"ERROR: {e}", force_output=True)
        sys.exit(1)


def get_data_directory():
    """
    Determine data directory for ephemeris files.
    Prefers comet_finder's data directory if it exists (to share de421.bsp).
    Creates local data directory if needed.
    """
    # Check if comet_finder data directory exists and has ephemeris
    comet_eph = os.path.join(COMET_FINDER_DATA_DIR, EPHEMERIDES_FILE)
    if os.path.exists(comet_eph):
        echo(f"Using shared ephemeris from comet_finder: {COMET_FINDER_DATA_DIR}")
        return COMET_FINDER_DATA_DIR

    # Check if comet_finder data directory exists (ephemeris may be downloaded later)
    if os.path.exists(COMET_FINDER_DATA_DIR):
        echo(f"Using comet_finder data directory: {COMET_FINDER_DATA_DIR}")
        return COMET_FINDER_DATA_DIR

    # Fall back to local data directory
    if not os.path.exists(LOCAL_DATA_DIR):
        os.makedirs(LOCAL_DATA_DIR)
    echo(f"Using local data directory: {LOCAL_DATA_DIR}")
    return LOCAL_DATA_DIR


def load_ephemeris():
    """
    Load ephemeris with file locking to handle concurrent access.
    """
    global load

    eph_path = os.path.join(load.directory, EPHEMERIDES_FILE)
    lock_path = eph_path + ".lock"

    # If ephemeris exists, just load it
    if os.path.exists(eph_path):
        return load(EPHEMERIDES_FILE)

    # Need to download - use file locking to prevent race conditions
    echo("Ephemeris not found, downloading...")

    # Create lock file directory if needed
    lock_dir = os.path.dirname(lock_path)
    if lock_dir and not os.path.exists(lock_dir):
        os.makedirs(lock_dir)

    # Try to acquire lock
    max_wait = 300  # 5 minutes max wait
    wait_time = 0

    try:
        lock_file = open(lock_path, 'w')
        while wait_time < max_wait:
            try:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                # Got the lock - check if another process downloaded it while we waited
                if os.path.exists(eph_path):
                    echo("Ephemeris downloaded by another process")
                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                    lock_file.close()
                    return load(EPHEMERIDES_FILE)

                # Download ephemeris
                eph = load(EPHEMERIDES_FILE)
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                lock_file.close()
                return eph

            except IOError:
                # Another process has the lock - wait
                echo(f"Waiting for ephemeris download (another process)... {wait_time}s")
                time.sleep(5)
                wait_time += 5

                # Check if it's now available
                if os.path.exists(eph_path):
                    lock_file.close()
                    return load(EPHEMERIDES_FILE)

        lock_file.close()
        raise TimeoutError("Timeout waiting for ephemeris download")

    except Exception as e:
        # Clean up lock file on error
        try:
            os.remove(lock_path)
        except:
            pass
        raise


def calc_planets(date, lat, lon, ts):
    """Calculate and print positions of all planets."""
    eph = load_ephemeris()

    earth = eph['earth']
    sun = eph['sun']

    # Create observer location
    # If lat=0 and lon=0 (default geocentric), use Earth center directly
    # This matches HORIZONS behavior with MPC code 500
    if lat == 0.0 and lon == 0.0:
        observer = earth
        echo("Using geocentric observer (Earth center)")
    else:
        observer = earth + Topos(latitude_degrees=lat, longitude_degrees=lon)

    for skyfield_name, display_name in PLANETS:
        try:
            planet = eph[skyfield_name]

            # Compute apparent position from observer
            astrometric = observer.at(date).observe(planet)
            apparent = astrometric.apparent()
            ra, dec, distance = apparent.radec()

            # Compute magnitude
            mag = compute_magnitude(skyfield_name, date, observer, planet, sun, eph)

            # Format output to match planets.sh
            ra_str = format_ra(ra)
            dec_str = format_dec(dec)

            print(f"{ra_str} {dec_str} {display_name} ({mag:.1f}mag)")

        except Exception as e:
            echo(f"Error computing {display_name}: {e}")


def compute_magnitude(planet_name, date, observer, planet, sun, eph):
    """
    Compute apparent magnitude of a planet.
    Uses skyfield's planetary_magnitude where available, otherwise estimates.
    """
    earth = eph['earth']

    # Get distances
    sun_to_planet = sun.at(date).observe(planet).distance().au
    earth_to_planet = observer.at(date).observe(planet).distance().au
    sun_to_earth = sun.at(date).observe(earth).distance().au

    # For Moon, use a simple formula
    if planet_name == "moon":
        # Moon apparent magnitude varies roughly from -2.5 to -12.7
        # Simplified formula based on phase and distance
        # Full moon at mean distance ~ -12.7, new moon not visible
        # This is approximate - real magnitude depends on phase angle
        phase_angle = compute_phase_angle(sun_to_planet, earth_to_planet, sun_to_earth)
        # Very rough approximation
        if phase_angle > 170:  # Near new moon
            return 99.9  # Not visible
        mag = -12.7 + 0.026 * phase_angle  # Rough linear approximation
        return max(-13.0, min(mag, 0.0))

    # For Pluto, use simple formula
    if planet_name == "pluto barycenter":
        # Pluto has H=15.1, G=0.15 approximately
        H = -1.0  # Absolute magnitude (adjusted for Pluto's actual brightness)
        phase_angle = compute_phase_angle(sun_to_planet, earth_to_planet, sun_to_earth)
        # Standard HG magnitude formula (simplified)
        mag = H + 5 * math.log10(sun_to_planet * earth_to_planet)
        return mag

    # Try skyfield's planetary_magnitude for major planets
    try:
        # planetary_magnitude expects the apparent position
        astrometric = observer.at(date).observe(planet)
        apparent = astrometric.apparent()
        mag = planetary_magnitude(apparent)
        return mag
    except Exception:
        pass

    # Fallback: approximate magnitudes using standard formulas
    # Absolute magnitudes (H) for planets at 1 AU from Sun and Earth
    abs_mags = {
        "mercury": -0.36,
        "venus": -4.40,
        "mars": -1.52,
        "jupiter barycenter": -9.40,
        "saturn barycenter": -8.88,
        "uranus barycenter": -7.19,
        "neptune barycenter": -6.87,
    }

    if planet_name in abs_mags:
        H = abs_mags[planet_name]
        phase_angle = compute_phase_angle(sun_to_planet, earth_to_planet, sun_to_earth)

        # Simple magnitude formula
        mag = H + 5 * math.log10(sun_to_planet * earth_to_planet)

        # Phase angle correction (approximate)
        if planet_name in ["mercury", "venus"]:
            # Inner planets have significant phase effects
            mag += 0.01 * phase_angle

        return mag

    # Default fallback
    return 99.9


def compute_phase_angle(r_sun_planet, r_earth_planet, r_sun_earth):
    """Compute phase angle in degrees using law of cosines."""
    # cos(phase) = (r_sp^2 + r_ep^2 - r_se^2) / (2 * r_sp * r_ep)
    try:
        cos_phase = (r_sun_planet**2 + r_earth_planet**2 - r_sun_earth**2) / (2 * r_sun_planet * r_earth_planet)
        cos_phase = max(-1, min(1, cos_phase))  # Clamp to valid range
        return math.degrees(math.acos(cos_phase))
    except:
        return 0.0


def format_ra(ra):
    """Format RA as HH:MM:SS.SS"""
    h, m, s = ra.hms()
    return f"{int(h):02d}:{int(m):02d}:{s:05.2f}"


def format_dec(dec):
    """Format Dec as +DD:MM:SS.S"""
    sign, d, m, s = dec.signed_dms()
    sign_char = '+' if sign >= 0 else '-'
    return f"{sign_char}{int(d):02d}:{int(m):02d}:{s:04.1f}"


def get_observer_position(lat, lon, observatory_code):
    """Get observer position from direct coordinates or MPC observatory code."""
    if observatory_code:
        echo(f"Using MPC observatory code: {observatory_code}")
        lat, lon = get_observatory_coordinates(observatory_code)
        echo(f"Observatory coordinates: Lat {lat}, Lon {lon}")

    return lat, lon


def get_observatory_coordinates(code):
    """Get observatory coordinates from MPC code."""
    import pandas as pd

    global load
    cache_path = os.path.join(load.directory, OBSERVATORY_CACHE_FILE)

    # Try to load from local ObsCodes.html first
    if os.path.exists(LOCAL_OBSERVATORY_FILE):
        echo(f"Using local observatory file: {LOCAL_OBSERVATORY_FILE}")
        with open(LOCAL_OBSERVATORY_FILE, 'r', encoding='utf-8') as f:
            observatories = parse_observatory_data(f.read())
    elif os.path.exists(cache_path):
        echo("Using cached observatory data")
        observatories = pd.read_csv(cache_path)
    else:
        echo("Downloading observatory data...")
        observatories = fetch_observatory_data_with_lock(cache_path)

    # Find observatory
    obs = observatories[observatories['code'].str.upper() == code.upper()]

    if obs.empty:
        raise ValueError(f"Observatory code '{code}' not found")

    lat = obs.iloc[0]['latitude']
    lon = obs.iloc[0]['longitude']

    echo(f"Found observatory: {obs.iloc[0].get('name', 'Unknown')}")
    return lat, lon


def fetch_observatory_data_with_lock(cache_path):
    """
    Fetch observatory data with file locking to prevent race conditions
    when planet_finder and comet_finder run simultaneously.
    """
    import pandas as pd

    lock_path = cache_path + ".lock"

    # Create directory if needed
    cache_dir = os.path.dirname(cache_path)
    if cache_dir and not os.path.exists(cache_dir):
        os.makedirs(cache_dir)

    # Check if cache already exists (another process might have created it)
    if os.path.exists(cache_path):
        echo("Using cached observatory data (created by another process)")
        return pd.read_csv(cache_path)

    max_wait = 60  # 1 minute max wait
    wait_time = 0

    try:
        lock_file = open(lock_path, 'w')
        while wait_time < max_wait:
            try:
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                # Got the lock - check if another process created cache while we waited
                if os.path.exists(cache_path):
                    echo("Using cached observatory data (created by another process)")
                    fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                    lock_file.close()
                    return pd.read_csv(cache_path)

                # Download and cache
                observatories = fetch_observatory_data()
                observatories.to_csv(cache_path, index=False)
                fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
                lock_file.close()
                return observatories

            except IOError:
                # Another process has the lock - wait
                echo(f"Waiting for observatory data download... {wait_time}s")
                time.sleep(2)
                wait_time += 2

                # Check if it's now available
                if os.path.exists(cache_path):
                    lock_file.close()
                    return pd.read_csv(cache_path)

        lock_file.close()
        raise TimeoutError("Timeout waiting for observatory data download")

    except TimeoutError:
        raise
    except Exception as e:
        # Clean up lock file on error
        try:
            os.remove(lock_path)
        except:
            pass
        raise


def fetch_observatory_data():
    """Fetch MPC observatory data with fallback."""
    import requests

    for url in [MPC_OBSERVATORY_URL, MPC_OBSERVATORY_URL_BACKUP]:
        try:
            echo(f"Trying {url}")
            response = requests.get(url, timeout=30)
            if response.status_code == 200:
                return parse_observatory_data(response.text)
        except Exception as e:
            echo(f"Failed: {e}")

    raise ConnectionError("Cannot download observatory data")


def parse_observatory_data(data_text):
    """Parse MPC observatory data."""
    import pandas as pd

    data = []
    for line in data_text.splitlines():
        if len(line) >= 30:
            try:
                code = line[0:3].strip()
                if not code:
                    continue

                longitude = float(line[4:13])
                cos_phi = float(line[13:21])
                sin_phi = float(line[21:30])

                # Geocentric latitude
                geocentric_lat = math.degrees(math.atan2(sin_phi, cos_phi))

                # Convert to geodetic latitude
                f = 1/298.257223563  # WGS84 flattening
                geodetic_lat = math.degrees(math.atan(math.tan(math.radians(geocentric_lat)) / ((1 - f) ** 2)))

                name = line[30:].strip()

                data.append({
                    'code': code,
                    'longitude': longitude,
                    'latitude': geodetic_lat,
                    'name': name
                })
            except (ValueError, IndexError):
                continue

    return pd.DataFrame(data)


def echo(text, force_output=False):
    """Print message to stderr if verbose or forced."""
    global load
    if load is None or load.verbose or force_output:
        print(text, file=sys.stderr)


def parse_args():
    parser = argparse.ArgumentParser(
        prog='planet_finder',
        description='Calculate positions of major planets using skyfield.'
    )

    parser.add_argument(
        'command',
        type=str,
        help='Command: calc'
    )

    parser.add_argument(
        '-date', '-d',
        type=float,
        help='Date in JD (TT) format',
        default=0.0
    )

    parser.add_argument(
        '-observatory', '-obs',
        type=str,
        help='MPC observatory code',
        default=None
    )

    parser.add_argument(
        '-lat',
        type=float,
        help='Observer latitude (degrees, North positive)',
        default=0.0
    )

    parser.add_argument(
        '-long',
        type=float,
        help='Observer longitude (degrees, East positive)',
        default=0.0
    )

    parser.add_argument(
        '--quiet', '-q',
        action='store_true',
        help='Suppress verbose output'
    )

    if len(sys.argv) == 1:
        parser.print_help(sys.stderr)
        sys.exit(1)

    return parser.parse_args()


if __name__ == "__main__":
    main()
