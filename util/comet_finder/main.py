#!/usr/bin/env python3

import pandas as pd
from skyfield.api import Loader, Topos, Time
from skyfield.data import mpc
from skyfield.constants import GM_SUN_Pitjeva_2005_km3_s2 as GM_SUN
import math, datetime, os, argparse, sys
import requests


DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
COMETS_DATA_URL = "https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt"
MPC_OBSERVATORY_URL = "https://www.minorplanetcenter.net/iau/lists/ObsCodes.html"
FILTERED_COMETS_FILE = os.path.join(DIR, "filtered_comets.csv")
OBSERVATORY_CACHE_FILE = os.path.join(DIR, "observatory_codes.csv")
LOCAL_OBSERVATORY_FILE = "ObsCodes.html"
EPHEMERIDES_FILE = "de421.bsp"


load = Loader(DIR)


def main():
    args = parse_args()
    
    load.verbose = args.quiet != True

    # Create date from argument
    ts = load.timescale()
    if args.date != 0:
        date = ts.tt_jd(args.date)
    else:
        date = ts.now()  
        
    start_time = datetime.datetime.now()

    try:
        # Get lat/long either from direct input or observatory code
        lat, long = get_observer_position(args.lat, args.long, args.observatory)
        
        if args.command == 'calc':
            calc(date, args.mag, lat, long, args.file, args.force)
        elif args.command == 'prepare':
            prepare(date, args.mag, lat, long)
        else:
            print("-> Unknown command:", args.command, file=sys.stderr)
            sys.exit(1)
                
        end_time = datetime.datetime.now()
        echo(f"-> Execution time: {end_time - start_time}.")
    except Exception as e:
        # Always show errors even in quiet mode
        echo(f"-> Error: {e}", force_output=True)
        exit(1)


def get_observer_position(lat, long, observatory_code):
    """Get observer's latitude and longitude either directly or via MPC observatory code"""
    if observatory_code:
        echo(f"-> Using MPC observatory code: {observatory_code}")
        lat, long = get_observatory_coordinates(observatory_code)
        echo(f"-> Observatory coordinates (geodetic): Lat {lat}, Long {long}")
    
    # Always print the final coordinates to stderr, regardless of source
    import sys
    print(f"Observer position (geodetic, East longitudes are positive): Latitude = {lat}, Longitude = {long}", file=sys.stderr)
    
    # Verify coordinates are within valid ranges
    if lat < -90 or lat > 90:
        echo(f"-> Warning: Latitude {lat} is outside valid range [-90, 90]", force_output=True)
    if long < -180 or long > 180:
        echo(f"-> Warning: Longitude {long} is outside valid range [-180, 180]", force_output=True)
    
    return lat, long


def get_observatory_coordinates(code):
    """Get observatory coordinates by MPC code"""
    # Check if we have observatory data
    observatories = None
    
    try:
        # First check if local file exists in current directory
        if os.path.exists(LOCAL_OBSERVATORY_FILE):
            echo(f"-> Using local observatory data file: {LOCAL_OBSERVATORY_FILE}")
            with open(LOCAL_OBSERVATORY_FILE, 'r', encoding='utf-8') as f:
                observatories = parse_observatory_data(f.read())
        # Then check if we have cached data
        elif os.path.exists(OBSERVATORY_CACHE_FILE):
            echo("-> Using cached observatory data")
            observatories = pd.read_csv(OBSERVATORY_CACHE_FILE)
        # Finally download if needed
        else:
            echo("-> Downloading MPC observatory data")
            observatories = fetch_observatory_data()
            # Cache for future use
            if not os.path.exists(DIR):
                os.makedirs(DIR)
            observatories.to_csv(OBSERVATORY_CACHE_FILE, index=False)
        
        # Add debugging info about available codes
        echo(f"-> Number of observatories loaded: {len(observatories)}")
        echo(f"-> First few observatory codes: {observatories['code'].head(5).tolist()}")
        
        # Find the observatory by code (case insensitive comparison)
        # Some MPC codes might be lowercase in the file but uppercase in user input or vice versa
        observatory = observatories[observatories['code'].str.upper() == code.upper()]
        
        if observatory.empty:
            raise ValueError(f"Observatory code '{code}' not found in MPC database")
        
        lat = observatory.iloc[0]['latitude']  # This is now geodetic latitude
        lon = observatory.iloc[0]['longitude']
        
        if 'geocentric_latitude' in observatory.iloc[0]:
            geocentric_lat = observatory.iloc[0]['geocentric_latitude']
            echo(f"-> Found observatory: {observatory.iloc[0]['name']}")
            echo(f"-> Geocentric lat={geocentric_lat}, Geodetic lat={lat}, lon={lon}")
        else:
            echo(f"-> Found observatory: {observatory.iloc[0]['name']}, lat={lat}, lon={lon}")
            
        return lat, lon
        
    except Exception as e:
        echo(f"-> Error in get_observatory_coordinates: {e}", force_output=True)
        echo(f"-> Debug info: Looking for code '{code}'", force_output=True)
        raise


def fetch_observatory_data():
    """Fetch and parse MPC observatory codes list"""
    response = requests.get(MPC_OBSERVATORY_URL)
    if response.status_code != 200:
        raise ConnectionError(f"Failed to download observatory data: {response.status_code}")
    
    return parse_observatory_data(response.text)


def parse_observatory_data(data_text):
    """Parse MPC observatory data from fixed-width text format
    
    Format: Code  Long.   cos      sin    Name
    Where cos and sin are parallax constants (rho*cos(phi) and rho*sin(phi))
    """
    data = []
    for line in data_text.splitlines():
        if len(line) >= 30:  # Make sure the line is long enough
            try:
                code = line[0:3].strip()
                if not code:  # Skip blank lines
                    continue
                    
                # Parse the longitude from MPC format
                longitude = float(line[4:13])
                
                # CRITICAL FIX: For C32 and default coordinates to match
                # Do NOT flip the sign - MPC appears to use East positive in this file
                # longitude = longitude  # No sign change
                
                # Get parallax constants
                cos_phi = float(line[13:21])
                sin_phi = float(line[21:30])
                
                # The MPC parallax constants give geocentric coordinates
                # First calculate the geocentric latitude
                geocentric_latitude = math.degrees(math.atan2(sin_phi, cos_phi))
                
                # Convert from geocentric to geodetic latitude
                # Earth flattening factor (WGS84)
                f = 1/298.257223563
                
                # Convert geocentric latitude to geodetic latitude
                # Formula from: https://en.wikipedia.org/wiki/Geographic_coordinate_conversion#From_geocentric_to_geodetic_coordinates
                # tan(geodetic) = tan(geocentric) / (1 - f)^2
                geocentric_latitude_rad = math.radians(geocentric_latitude)
                geodetic_latitude_rad = math.atan(math.tan(geocentric_latitude_rad) / ((1 - f) ** 2))
                geodetic_latitude = math.degrees(geodetic_latitude_rad)
                
                name = line[30:].strip()
                data.append({
                    'code': code, 
                    'longitude': longitude,  # Standard convention: East positive, West negative
                    'latitude': geodetic_latitude,  # Geodetic latitude
                    'geocentric_latitude': geocentric_latitude,
                    'cos_phi': cos_phi,
                    'sin_phi': sin_phi,
                    'name': name
                })
            except (ValueError, IndexError) as e:
                echo(f"-> Warning: Skipping line due to parsing error: {e}")
                continue  # Skip lines that don't parse properly
    
    return pd.DataFrame(data)


def calc(date: Time, min_mag: float, lat: float, long: float, result_file_name: str, force: bool):
    if not os.path.exists(FILTERED_COMETS_FILE) or force: 
        filtered_comets = prepare(date, min_mag, lat, long)
    else:
        echo("-> Loading list of filtered comets.")
        filtered_comets = load_filtered_comets(FILTERED_COMETS_FILE)
        echo(f"-> Loaded filtered: '{len(filtered_comets)}' comets.")

    echo("-> Calculating of RA/Dec/Mag.")
    results = calc_ra_dec(filtered_comets, date, lat, long)

    if (result_file_name != None):
        echo(f"-> Save filtered comets to the file '{result_file_name}'.")
        save_results_to_file(results, result_file_name)
    else:
        print_results_to_stdout(results)


def prepare(date: Time, min_mag: float, lat: float, long: float):
    echo("-> Downloading comet data.")
    comets = fetch_cometas_data(COMETS_DATA_URL, True)
    echo(f"-> Loaded: '{len(comets)}' comets.")

    echo("-> Filter by magnitude.")
    filtered_comets = filter(comets, date, min_mag, lat, long)
    echo(f"-> Filtered '{len(filtered_comets)}' comets.")

    echo("-> Save filtered comets.")
    save_filtered_comets(filtered_comets, FILTERED_COMETS_FILE)

    return filtered_comets


def calc_mag(g_absolute_mag, k_luminosity_index, earth_distance_au, sun_distance_au):
    return g_absolute_mag + \
           5 * math.log10(earth_distance_au) + \
           2.5 * k_luminosity_index * math.log10(sun_distance_au)


def filter(comets, date: Time, min_mag: float, lat: float, long: float):
    eph = load_eph()

    sun, earth = eph['sun'], eph['earth']
    observer = earth + Topos(latitude_degrees=lat, longitude_degrees=long)

    for idx, row in comets.iterrows():
        try:
            # Panda reads year as string for some resources
            if type(row.perihelion_year) == str:
                row.perihelion_year = clean_int(row.perihelion_year)
            
            comet = sun + mpc.comet_orbit(row, date.ts, GM_SUN)

            sun_comet_distance = sun.at(date).observe(comet).distance()
            earth_cometa_distance = observer.at(date).observe(comet).distance()

            mag = calc_mag(
                row.get('magnitude_g'),
                row.get('magnitude_k'),
                earth_cometa_distance.au,
                sun_comet_distance.au
            )

            if mag > min_mag:
                comets.drop(idx, axis=0, inplace=True)

        except Exception as e:
            echo(f"-> Error processing object {row.designation}: {e}")

    return comets


def calc_ra_dec(filtered_comets, date: Time, lat: float, long: float):
    eph = load_eph()

    sun, earth = eph['sun'], eph['earth']
    observer = earth + Topos(latitude_degrees=lat, longitude_degrees=long)

    results = []
    for _, row in filtered_comets.iterrows():
        try:
            # Panda reads year as string for some resources
            if type(row.perihelion_year) == str:
                row.perihelion_year = clean_int(row.perihelion_year)

            comet = sun + mpc.comet_orbit(row, date.ts, GM_SUN)
            ra, dec, earth_cometa_distance = observer.at(date).observe(comet).radec()  
            sun_comet_distance = sun.at(date).observe(comet).distance()

            mag = calc_mag(
                row.get('magnitude_g'),
                row.get('magnitude_k'),
                earth_cometa_distance.au,
                sun_comet_distance.au
            )

            results.append({
                "name": row.designation,
                "ra": ra.hstr(format="{0}{1:02}:{2:02}:{3:02}.{4:0{5}}"),
                "dec": dec.dstr(format="{0:+>1}{1:02}:{2:02}:{3:02}.{4}"),
                "mag": mag
            })

        except Exception as e:
            echo(f"-> Error processing object {row.designation}: {e}")

    return results


def fetch_cometas_data(url: str, reload=False):
    with load.open(url, reload=reload) as f:
        comets = mpc.load_comets_dataframe(f)
    return comets


def load_eph():
    eph = load(EPHEMERIDES_FILE)
    return eph


def clean_int(value: str):
    try:
        return int(value.replace(" ", ""))
    except (ValueError, AttributeError):
        return 0


def save_filtered_comets(filtered_comets, filepath):   
    filtered_comets.to_csv(os.path.join(DIR, filepath)) 


def load_filtered_comets(filepath):
    return pd.read_csv(os.path.join(DIR, filepath))


def save_results_to_file(results, filename):
    with open(os.path.join(DIR, filename), "w", encoding="utf-8") as file:
        for result in results:
            file.write(f"{result['ra']} {result['dec']} {result['mag']:.1f}mag {result['name']}\n")


def print_results_to_stdout(results):
    for result in results:
        print(f"{result['ra']} {result['dec']} {result['mag']:.1f}mag {result['name']}")


def echo(text, force_output=False):
    if load.verbose or force_output:
        print(text)


def parse_args():
    parser = argparse.ArgumentParser(
        prog='Cometas',
        description="Application for calculating the position and brightness of comets.",
    )

    parser.add_argument(
        "command",
        type=str,
        help="Launch command: calc — calculation of RA/Dec/Mag, \
        prepare — filtering comets by mag."
    )

    parser.add_argument(
        "--force", "-f",
        action='store_true',
        help="Complete recalculation of comet position and brightness values.",    
    )

    parser.add_argument(
        "-date", "-d",
        type=float,
        help="Date in JD format.",  
        default=0.0  
    )

    parser.add_argument(
        "-mag", "-m",
        type=float,
        help="Minimum required magnitud.",   
        default=18.0 
    )

    # Position specifying group
    position_group = parser.add_mutually_exclusive_group()
    
    position_group.add_argument(
        "-observatory", "-obs",
        type=str,
        help="MPC observatory code (e.g., '500' for Geocentric, 'C32' for custom sites).",
        default=None
    )
    
    # Keep the original arguments but put them in the same mutually exclusive group
    position_group.add_argument(
        "-lat",
        type=float,
        help="Observer's latitude in degrees (positive for North, negative for South).",   
        default=43.6497
    )

    parser.add_argument(
        "-long",
        type=float,
        help="Observer's longitude in degrees (positive for East, negative for West).",   
        default=41.4258  # Positive value representing East longitude
    )

    parser.add_argument(
        "--file", "-file",
        type=str,
        help="File name to save the result.",  
        default=None
    )

    parser.add_argument(
        "--quiet", "-q",
        action='store_true',
        help="Run without debugging output."
    )

    if len(sys.argv) == 1:
        parser.print_help(sys.stderr)
        sys.exit(1)

    return parser.parse_args()


if __name__ == "__main__":
    main()
