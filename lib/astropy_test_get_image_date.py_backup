#!/usr/bin/env python3

import sys
import subprocess
import re
from astropy.io import fits
from astropy.time import Time

def run_c_program(c_program, fits_file):
    result = subprocess.run([c_program, fits_file], capture_output=True, text=True)
    
    # Combine stdout and stderr
    full_output = result.stdout + result.stderr
    
    # Search for the line containing JD information
    jd_match = re.search(r"         JD ([\d.]+)", full_output)
    exp_match = re.search(r"Exposure (\d+) sec, (\d{2}\.\d{2}\.\d{4} \d{2}:\d{2}:\d{2}(?:\.\d+)?) (\w+) = JD\((\w+)\) ([\d.]+)", full_output)
    
    if jd_match and exp_match:
        c_jd = float(jd_match.group(1))
        exposure = int(exp_match.group(1))
        date_time = exp_match.group(2)
        input_timesys = exp_match.group(3)
        output_timesys = exp_match.group(4)
        return c_jd, exposure, date_time, input_timesys, output_timesys
    else:
        print(f"Error: Could not find JD information in the output for {fits_file}")
        print("C program output:")
        print(full_output)
        return None, None, None, None, None
        
        
def process_fits_with_astropy(filename):
    with fits.open(filename) as hdul:
        header = hdul[0].header
        
        print(f"Astropy header analysis for {filename}:")
        print(f"DATE-OBS: {header.get('DATE-OBS')}")
        print(f"TIME-OBS: {header.get('TIME-OBS')}")
        print(f"DATE: {header.get('DATE')}")
        print(f"EXPTIME: {header.get('EXPTIME')}")
        print(f"JD: {header.get('JD')}")
        print(f"TIMESYS: {header.get('TIMESYS')}")
        
        date_obs = header.get('DATE-OBS')
        time_obs = header.get('TIME-OBS')
        exptime = header.get('EXPTIME', 0)
        
        if date_obs:
            if 'T' in date_obs:
                # DATE-OBS already includes time
                full_date_obs = date_obs
            elif time_obs:
                # DATE-OBS and TIME-OBS are separate
                full_date_obs = f"{date_obs}T{time_obs}"
            else:
                # Only DATE-OBS is present, assume start of day
                full_date_obs = f"{date_obs}T00:00:00"
            
            print(f"Parsed date_obs: {full_date_obs}")
            t = Time(full_date_obs, format='isot', scale='utc')
            t_mid = t + exptime/2/86400  # Add half the exposure time
            jd = t_mid.jd
            print(f"Calculated JD: {jd}")
        else:
            jd = header.get('JD')
            if jd is None:
                print("No date information found")
                return None, None
        
        timesys = header.get('TIMESYS', '').upper()
        if not timesys:
            # Check comments for DATE-OBS and TIME-OBS
            date_obs_comment = header.comments['DATE-OBS'] if 'DATE-OBS' in header else ''
            time_obs_comment = header.comments['TIME-OBS'] if 'TIME-OBS' in header else ''
            if 'UT' in date_obs_comment or 'UT' in time_obs_comment:
                timesys = 'UTC'
            else:
                timesys = 'UNKNOWN'
        
        if 'UT' in timesys:
            timesys = 'UTC'
        elif 'TT' in timesys:
            timesys = 'TT'
        elif 'TDB' in timesys:
            timesys = 'TDB'
        else:
            timesys = 'UNKNOWN'
        
        print(f"Identified time system: {timesys}")
        return jd, timesys
                
        
def main():
    # Check if any FITS files are provided as arguments
    if len(sys.argv) < 2:
        print("Usage: lib/astropy_test_get_image_date.py <fits_file1> [<fits_file2> ...]")
        print("Error: No FITS files provided.")
        sys.exit(1)
        
    c_program = "util/get_image_date"
    error_found = False
    
    for fits_file in sys.argv[1:]:
        # Process with C program
        result = subprocess.run([c_program, fits_file], capture_output=True, text=True)
        print("C program output:")
        print(result.stdout)
        print(result.stderr)
        
        c_jd, exposure, date_time, input_timesys, output_timesys = run_c_program(c_program, fits_file)
        
        if c_jd is None:
            error_found = True
            print(f"Error processing {fits_file} with C program")
            continue  # Skip to the next file if C program fails
        
        # Process with Astropy
        print("\n" + "="*50)
        astropy_jd, astropy_timesys = process_fits_with_astropy(fits_file)
        print("="*50 + "\n")
        
        if astropy_jd is None:
            error_found = True
            print(f"Error processing {fits_file} with Astropy")
            continue  # Skip to the next file if Astropy fails
        
        # Compare results
        jd_diff = abs(c_jd - astropy_jd)
        timesys_match = output_timesys == astropy_timesys
        
        print(f"File: {fits_file}")
        print(f"C Program:      JD = {c_jd:.8f}, Date/Time = {date_time}, Input Time System = {input_timesys}, Output Time System = {output_timesys}")
        print(f"                Exposure = {exposure} sec")
        print(f"Astropy:        JD = {astropy_jd:.8f}, Time System = {astropy_timesys}")
        print(f"JD Difference:  {jd_diff:.8f}")
        print(f"Time System Match: {'Yes' if timesys_match else 'No'}")
        
        if jd_diff > 1e-8 or not timesys_match:
            error_found = True
            if jd_diff > 1e-8:
                print(f"JD mismatch: C Program JD = {c_jd:.8f}, Astropy JD = {astropy_jd:.8f}")
            if not timesys_match:
                print(f"Time system mismatch: C Program = {output_timesys}, Astropy = {astropy_timesys}")
        
        print()
    
    if error_found:
        print("Errors or mismatches found during processing.")
        sys.exit(1)
    else:
        print("All files processed successfully with no mismatches.")
        sys.exit(0)        
        
if __name__ == "__main__":
    main()
    