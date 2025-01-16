#!/usr/bin/env python3

import pandas as pd
from skyfield.api import Loader, Topos, Time
from skyfield.data import mpc
from skyfield.constants import GM_SUN_Pitjeva_2005_km3_s2 as GM_SUN
import math, datetime, os, argparse, sys


DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data")
COMETS_DATA_URL = "https://www.minorplanetcenter.net/iau/MPCORB/CometEls.txt"
FILTERED_COMETS_FILE = os.path.join(DIR, "filtered_comets.csv")
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
        match args.command:
            case 'calc':
                calc(date, args.mag, args.lat, args.long, args.file, args.force)
            case 'prepare':
                prepare(date, args.mag, args.lat, args.long)       
            case _:
                print("→ Unknown command:", args.command, file=sys.stderr)        
                sys.exit(1) 
        
        end_time = datetime.datetime.now()
        echo(f"→ Execution time: {end_time - start_time}.")
    except Exception as e:
        echo(f"-> Error: {e}")
        exit(1)


def calc(date: Time, min_mag: float, lat: float, long: float, result_file_name: str, force: bool):
    if not os.path.exists(FILTERED_COMETS_FILE) or force: 
        filtered_comets = prepare(date, min_mag, lat, long)
    else:
        echo("→ Loading list of filtered comets.")
        filtered_comets = load_filtered_comets(FILTERED_COMETS_FILE)
        echo(f"→ Loaded filtered: '{len(filtered_comets)}' comets.")

    echo("→ Calculating of RA/Dec/Mag.")
    results = calc_ra_dec(filtered_comets, date, lat, long)

    if (result_file_name != None):
        echo(f"→ Save filtered comets to the file '{result_file_name}'.")
        save_results_to_file(results, result_file_name)
    else:
        print_results_to_stdout(results)


def prepare(date: Time, min_mag: float, lat: float, long: float):
    echo("→ Downloading comet data.")
    comets = fetch_cometas_data(COMETS_DATA_URL, True)
    echo(f"→ Loaded: '{len(comets)}' comets.")

    echo("→ Filter by magnitude.")
    filtered_comets = filter(comets, date, min_mag, lat, long)
    echo(f"→ Filtered '{len(filtered_comets)}' comets.")

    echo("→ Save filtered comets.")
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
            echo(f"→ Error processing object {row.designation}: {e}")

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
            echo(f"→ Error processing object {row.designation}: {e}")

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


def echo(text):
    if load.verbose: print(text)


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

    parser.add_argument(
        "-lat",
        type=float,
        help="Observer's latitude.",   
        default=43.6497
    )

    parser.add_argument(
        "-long",
        type=float,
        help="Observer's longitude.",   
        default=41.4258
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
