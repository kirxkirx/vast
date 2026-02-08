#!/usr/bin/env bash
#
# Alternative Gaia DR2 cone search using ESA TAP endpoint
# Drop-in replacement for vizquery when querying I/345/gaia2
# Output format matches vizquery: dist_arcsec Source RA_ICRS DE_ICRS Gmag RPmag Var
#

#################################
# Set the safe locale
LC_ALL=C
LANGUAGE=C
export LANGUAGE LC_ALL
#################################

# Default values
MAX_RESULTS=3
SEARCH_RADIUS_ARCSEC=""
MAG_BRIGHT=0.0
MAG_FAINT=99.0
RA_DEG=""
DEC_DEG=""
SORT_BY="phot_g_mean_mag"
TIMEOUT_SEC=30

# Function to convert HMS to degrees
hms_to_deg() {
 local hms="$1"
 local h m s
 # Handle formats like "06:13:37.32" or "06 13 37.32"
 h=$(echo "$hms" | awk -F'[: ]' '{print $1}')
 m=$(echo "$hms" | awk -F'[: ]' '{print $2}')
 s=$(echo "$hms" | awk -F'[: ]' '{print $3}')
 echo "$h $m $s" | awk '{printf "%.9f", ($1 + $2/60 + $3/3600) * 15}'
}

# Function to convert DMS to degrees
dms_to_deg() {
 local dms="$1"
 local sign d m s
 # Handle formats like "+21:54:26.0" or "-21:54:26.0" or "21:54:26.0"
 sign=1
 if [[ "$dms" == -* ]]; then
  sign=-1
  dms="${dms:1}"
 elif [[ "$dms" == +* ]]; then
  dms="${dms:1}"
 fi
 d=$(echo "$dms" | awk -F'[: ]' '{print $1}')
 m=$(echo "$dms" | awk -F'[: ]' '{print $2}')
 s=$(echo "$dms" | awk -F'[: ]' '{print $3}')
 echo "$sign $d $m $s" | awk '{printf "%.9f", $1 * ($2 + $3/60 + $4/3600)}'
}

# Parse arguments (mimicking vizquery style)
while [[ $# -gt 0 ]]; do
 case "$1" in
  -c=*)
   # Coordinates: "-c=06:13:37.32 +21:54:26.0"
   COORDS="${1#-c=}"
   RA_HMS=$(echo "$COORDS" | awk '{print $1}')
   DEC_DMS=$(echo "$COORDS" | awk '{print $2}')
   RA_DEG=$(hms_to_deg "$RA_HMS")
   DEC_DEG=$(dms_to_deg "$DEC_DMS")
   shift
   ;;
  -c.rs=*)
   # Search radius in arcsec
   SEARCH_RADIUS_ARCSEC="${1#-c.rs=}"
   shift
   ;;
  -out.max=*)
   MAX_RESULTS="${1#-out.max=}"
   shift
   ;;
  Gmag=*|phot_g_mean_mag=*)
   # Magnitude range: "Gmag=0.0..13.13"
   MAG_RANGE="${1#*=}"
   MAG_BRIGHT=$(echo "$MAG_RANGE" | awk -F'[.][.]' '{print $1}')
   MAG_FAINT=$(echo "$MAG_RANGE" | awk -F'[.][.]' '{print $2}')
   shift
   ;;
  -sort=*)
   SORT_FIELD="${1#-sort=}"
   if [[ "$SORT_FIELD" == "Gmag" ]]; then
    SORT_BY="phot_g_mean_mag"
   elif [[ "$SORT_FIELD" == "RPmag" ]]; then
    SORT_BY="phot_rp_mean_mag"
   else
    echo "ERROR: Unknown sort field '$SORT_FIELD'. Supported values: Gmag, RPmag" >&2
    exit 1
   fi
   shift
   ;;
  -timeout=*)
   TIMEOUT_SEC="${1#-timeout=}"
   shift
   ;;
  -source=*|-site=*|-mime=*|-out.add=*|-out.form=*|-out=*)
   # Ignore vizquery-specific options
   shift
   ;;
  *)
   shift
   ;;
 esac
done

# Validate required parameters
if [[ -z "$RA_DEG" ]] || [[ -z "$DEC_DEG" ]] || [[ -z "$SEARCH_RADIUS_ARCSEC" ]]; then
 echo "ERROR: Missing required parameters (coordinates or search radius)" >&2
 exit 1
fi

# Convert search radius from arcsec to degrees
SEARCH_RADIUS_DEG=$(echo "$SEARCH_RADIUS_ARCSEC" | awk '{printf "%.9f", $1/3600}')

# Build ADQL query
# Note: DISTANCE returns degrees, multiply by 3600 to get arcsec
ADQL_QUERY="SELECT TOP ${MAX_RESULTS} source_id, ra, dec, phot_g_mean_mag, phot_rp_mean_mag, phot_variable_flag, DISTANCE(POINT('ICRS', ra, dec), POINT('ICRS', ${RA_DEG}, ${DEC_DEG})) * 3600 AS dist_arcsec FROM gaiadr2.gaia_source WHERE 1=CONTAINS(POINT('ICRS', ra, dec), CIRCLE('ICRS', ${RA_DEG}, ${DEC_DEG}, ${SEARCH_RADIUS_DEG})) AND phot_g_mean_mag >= ${MAG_BRIGHT} AND phot_g_mean_mag <= ${MAG_FAINT} ORDER BY ${SORT_BY}"

# Query ESA TAP endpoint
RESPONSE=$(curl -s --max-time "$TIMEOUT_SEC" "https://gea.esac.esa.int/tap-server/tap/sync" \
 -d "REQUEST=doQuery" \
 -d "LANG=ADQL" \
 -d "FORMAT=csv" \
 --data-urlencode "QUERY=${ADQL_QUERY}" 2>/dev/null)

if [[ -z "$RESPONSE" ]]; then
 exit 1
fi

# Check for error response
if echo "$RESPONSE" | grep -E -q "ERROR|Exception"; then
 echo "$RESPONSE" >&2
 exit 1
fi

# Convert CSV output to vizquery-like format
# Input:  source_id,ra,dec,phot_g_mean_mag,phot_rp_mean_mag,phot_variable_flag,dist_arcsec
# Output: dist_arcsec source_id RA_deg Dec_deg Gmag RPmag Var
echo "$RESPONSE" | tail -n +2 | while IFS=',' read -r source_id ra dec gmag rpmag varflag dist_arcsec; do
 # Handle empty/null values
 if [[ -z "$varflag" ]] || [[ "$varflag" == "" ]]; then
  varflag="NOT_AVAILABLE"
 fi
 if [[ -z "$rpmag" ]] || [[ "$rpmag" == "" ]]; then
  rpmag="99.9999"
 fi
 # Format to match vizquery output format
 # dist: 3 decimal places, RA: 11 decimal places with leading zeros, Dec: signed with 11 decimals, mags: 4 decimals
 printf " %.3f %s %015.11f %+.11f %.4f %.4f %s\n" "$dist_arcsec" "$source_id" "$ra" "$dec" "$gmag" "$rpmag" "$varflag"
done

echo "#END#"
