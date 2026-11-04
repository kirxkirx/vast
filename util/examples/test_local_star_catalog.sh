#!/usr/bin/env bash
#
# Unit test of lib/catalogs/local_star_catalog on small synthetic catalogs: the Gaia
# gaia_source CSV extraction (DR2 and DR3 file formats), the Tycho-2 extraction, the
# zone files and their RA index, cone searches across RA=0/360, near the poles and at
# zone boundaries, magnitude limits, sorting, the vizquery-like output, searching
# VaST's native UCAC5 zone files, and merging catalogs. Needs no network and no real
# catalog, so it runs everywhere, GitHub Actions included. Run it from the VaST
# directory; it prints the failed check codes and exits with code 1 if any check fails.
#
# Usage: util/examples/test_local_star_catalog.sh

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
 echo "FAILED: LOCALSTARCAT_NOT_BUILT lib/catalogs/local_star_catalog is not built (run make)"
 exit 1
fi

WORK_DIR=$(mktemp -d 2>/dev/null || echo "local_star_catalog_test_$$")
mkdir -p "$WORK_DIR" || exit 1

# The data lines (dist source RA Dec G RP Var) of a search, exactly as the known-star
# check in util/transients/report_transient.sh selects them
search() {
 lib/catalogs/local_star_catalog search "$@" | grep -B10 '#END#' | grep -vE "#|---|sec|Gma|RA_ICRS" | grep -E "NOT_AVAILABLE|CONSTANT|VARIABLE"
}
ids() {
 awk '{printf "%s ", $2}' | sed 's/ $//'
}

##### Synthetic Gaia gaia_source CSV: two chunks in the DR3 format, one in the DR2 format #####
cat > "$WORK_DIR/chunk1.csv" << 'EOF'
# %ECSV 1.0
# ---
# a commented-out header line like the ones of the real files
solution_id,designation,source_id,ra,dec,phot_g_mean_mag,phot_bp_mean_mag,phot_rp_mean_mag,phot_variable_flag
1,"Gaia DR3 1001",1001,359.9995,10.0,12.0,12.5,11.5,"NOT_AVAILABLE"
1,"Gaia DR3 1002",1002,0.0005,10.0,13.0,null,null,"VARIABLE"
1,"Gaia DR3 1003",1003,0.0,10.01,18.5,19.0,18.0,"NOT_AVAILABLE"
1,"Gaia DR3 1004",1004,180.0,89.995,11.0,11.5,10.5,"NOT_AVAILABLE"
1,"Gaia DR3 1005",1005,0.0,89.995,11.2,11.7,10.7,"NOT_AVAILABLE"
EOF
cat > "$WORK_DIR/chunk2.csv" << 'EOF'
solution_id,designation,source_id,ra,dec,phot_g_mean_mag,phot_bp_mean_mag,phot_rp_mean_mag,phot_variable_flag
1,"Gaia DR3 1006, a quoted field with a comma",1006,45.0,-45.0,19.5,20.0,19.0,"NOT_AVAILABLE"
1,"Gaia DR3 1007",1007,45.0,-45.0,null,null,null,"NOT_AVAILABLE"
1,"Gaia DR3 1008",1008,45.0002,-45.0,14.0,14.5,13.5,"NOT_AVAILABLE"
1,"Gaia DR3 1009",1009,45.0,-89.999,9.0,9.5,8.5,"NOT_AVAILABLE"
1,"Gaia DR3 1010",1010,120.0,0.0,10.0,10.5,9.5,"NOT_AVAILABLE"
1,"Gaia DR3 1011",1011,120.0,-0.0000001,10.1,10.6,9.6,"NOT_AVAILABLE"
EOF
lib/catalogs/local_star_catalog gaia-extract "$WORK_DIR/gaia_staging" chunk1 19.0 < "$WORK_DIR/chunk1.csv" 2>/dev/null || fail LOCALSTARCAT_GAIA_EXTRACT1
lib/catalogs/local_star_catalog gaia-extract "$WORK_DIR/gaia_staging" chunk2 19.0 < "$WORK_DIR/chunk2.csv" 2>/dev/null || fail LOCALSTARCAT_GAIA_EXTRACT2
# The DR2 files have other columns in another order, no quotes and empty fields for nulls
cat > "$WORK_DIR/chunk3.csv" << 'EOF'
solution_id,designation,source_id,random_index,ref_epoch,ra,ra_error,dec,dec_error,phot_g_mean_flux,phot_g_mean_mag,phot_bp_mean_mag,phot_rp_mean_mag,phot_bp_rp_excess_factor,phot_variable_flag,teff_val
1635721458409799680,Gaia DR2 2001,2001,1,2015.5,200.0,0.04,-30.0,0.05,1000.0,12.5,13.0,12.0,1.2,NOT_AVAILABLE,
1635721458409799680,Gaia DR2 2002,2002,2,2015.5,200.0003,0.04,-30.0,0.05,800.0,13.5,,,,VARIABLE,4500.0
1635721458409799680,Gaia DR2 2003,2003,3,2015.5,200.0,0.04,-30.0002,0.05,,,,,,NOT_AVAILABLE,
EOF
lib/catalogs/local_star_catalog gaia-extract "$WORK_DIR/gaia_staging" chunk3 19.0 < "$WORK_DIR/chunk3.csv" 2>/dev/null || fail LOCALSTARCAT_GAIA_EXTRACT3
lib/catalogs/local_star_catalog finalize "$WORK_DIR/gaia_staging" "$WORK_DIR/gaia" gaia_dr2 "synthetic test catalog" 1 2>/dev/null || fail LOCALSTARCAT_GAIA_FINALIZE
GAIA="-cat=gaia_dr2:$WORK_DIR/gaia"

if ! grep -q '^records=11$' "$WORK_DIR/gaia/catalog_info.txt" 2>/dev/null ;then
 fail LOCALSTARCAT_GAIA_RECORDS "the G<19 limit and the null G should leave 11 of 14 sources"
fi
if [ "$(ls "$WORK_DIR"/gaia/z[0-9][0-9][0-9] 2>/dev/null | wc -l | awk '{print $1}')" != "900" ];then
 fail LOCALSTARCAT_GAIA_ZONES "expected 900 zone files"
fi

# RA=0/360: the stars on both sides of RA=0, sorted by G, the 36" star outside the radius
RESULT=$(search "$GAIA" -c="00:00:00.00 +10:00:00.0" -c.rs=5 -out.max=3 -sort=Gmag Gmag=0.0..20.0 | ids)
[ "$RESULT" = "1001 1002" ] || fail LOCALSTARCAT_RA0 "got #$RESULT#"
DIST=$(search "$GAIA" -c="00:00:00.00 +10:00:00.0" -c.rs=5 -out.max=3 -sort=Gmag Gmag=0.0..20.0 | head -n1 | awk '{print $1}')
echo "$DIST" | awk '{exit ($1 > 1.76 && $1 < 1.78) ? 0 : 1}' || fail LOCALSTARCAT_DISTANCE "got #$DIST# expected 1.77 arcsec"
# the magnitude limit
RESULT=$(search "$GAIA" -c="00:00:00.00 +10:00:00.0" -c.rs=5 -out.max=3 -sort=Gmag Gmag=0.0..12.5 | ids)
[ "$RESULT" = "1001" ] || fail LOCALSTARCAT_GMAG_LIMIT "got #$RESULT#"
# the RP band: a star without RP is not listed
RESULT=$(search "$GAIA" -c="00:00:00.00 +10:00:00.0" -c.rs=5 -out.max=3 -sort=RPmag RPmag=0.0..20.0 | ids)
[ "$RESULT" = "1001" ] || fail LOCALSTARCAT_RPMAG "got #$RESULT#"
# the variability flag
search "$GAIA" -c="00:00:00.00 +10:00:00.0" -c.rs=5 -out.max=3 -sort=Gmag Gmag=0.0..20.0 | grep ' 1002 ' | grep -q 'VARIABLE$' || fail LOCALSTARCAT_VARFLAG
# -out.max
RESULT=$(search "$GAIA" -c="00:00:00.00 +10:00:00.0" -c.rs=5 -out.max=1 -sort=Gmag Gmag=0.0..20.0 | ids)
[ "$RESULT" = "1001" ] || fail LOCALSTARCAT_OUTMAX "got #$RESULT#"
# near the north pole: two stars on opposite sides of the pole, 8" and 28" away
RESULT=$(search "$GAIA" -c="12:00:00.00 +89:59:50.0" -c.rs=30 -out.max=3 -sort=Gmag Gmag=0.0..20.0 | ids)
[ "$RESULT" = "1004 1005" ] || fail LOCALSTARCAT_NORTH_POLE "got #$RESULT#"
# decimal-degree input; the G=19.5 and the null-G stars at the same position are not in the catalog
RESULT=$(search "$GAIA" -c="45.0001 -45.0" -c.rs=3 -out.max=3 -sort=Gmag Gmag=0.0..25.0 | ids)
[ "$RESULT" = "1008" ] || fail LOCALSTARCAT_DECIMAL_INPUT "got #$RESULT#"
# the southernmost zone
RESULT=$(search "$GAIA" -c="45.0 -89.999" -c.rs=1 -out.max=3 -sort=Gmag Gmag=0.0..20.0 | ids)
[ "$RESULT" = "1009" ] || fail LOCALSTARCAT_SOUTH_POLE "got #$RESULT#"
# a zone boundary at Dec=0
RESULT=$(search "$GAIA" -c="120.0 0.0" -c.rs=5 -out.max=3 -sort=Gmag Gmag=0.0..20.0 | ids)
[ "$RESULT" = "1010 1011" ] || fail LOCALSTARCAT_ZONE_BOUNDARY "got #$RESULT#"
# the DR2-format chunk: the star without G is not in the catalog, the unquoted flag is read,
# and the star with an empty RP field is not listed in the RP band
RESULT=$(search "$GAIA" -c="200.0 -30.0" -c.rs=3 -out.max=3 -sort=Gmag Gmag=0.0..20.0 | ids)
[ "$RESULT" = "2001 2002" ] || fail LOCALSTARCAT_DR2_FORMAT "got #$RESULT#"
search "$GAIA" -c="200.0 -30.0" -c.rs=3 -out.max=3 -sort=Gmag Gmag=0.0..20.0 | grep ' 2002 ' | grep -q 'VARIABLE$' || fail LOCALSTARCAT_DR2_VARFLAG
RESULT=$(search "$GAIA" -c="200.0 -30.0" -c.rs=3 -out.max=3 -sort=RPmag RPmag=0.0..20.0 | ids)
[ "$RESULT" = "2001" ] || fail LOCALSTARCAT_DR2_RP_NULL "got #$RESULT#"
# nothing there: a complete reply with no star, and exit code 0
OUTPUT=$(lib/catalogs/local_star_catalog search "$GAIA" -c="06:00:00 +30:00:00" -c.rs=10 -out.max=3 -sort=Gmag Gmag=0.0..20.0)
if [ $? -ne 0 ] || ! echo "$OUTPUT" | grep -q '#END#' || [ -n "$(echo "$OUTPUT" | grep -E 'NOT_AVAILABLE|VARIABLE')" ];then
 fail LOCALSTARCAT_EMPTY_REPLY
fi
# a missing or incomplete catalog is exit code 2, so the caller asks an online service
lib/catalogs/local_star_catalog search -cat=gaia_dr2:"$WORK_DIR/no_such_catalog" -c="00:00:00 +10:00:00" -c.rs=5 > /dev/null 2>&1
[ $? -eq 2 ] || fail LOCALSTARCAT_MISSING_CATALOG_EXIT_CODE
mkdir -p "$WORK_DIR/incomplete" && cp "$WORK_DIR"/gaia/z* "$WORK_DIR/incomplete/" 2>/dev/null
lib/catalogs/local_star_catalog search -cat=gaia_dr2:"$WORK_DIR/incomplete" -c="00:00:00 +10:00:00" -c.rs=5 > /dev/null 2>&1
[ $? -eq 2 ] || fail LOCALSTARCAT_INCOMPLETE_CATALOG_EXIT_CODE

##### Tycho-2: a star with a mean position and proper motion, and one with only an observed position #####
cat > "$WORK_DIR/tyc2.dat.00" << 'EOF'
0001 00008 1| |  2.31750494|  2.23184345|  -16.3|   -9.0| 68| 73| 1.7| 1.8|1958.89|1951.94| 4|1.0|1.0|0.9|1.0|12.146|0.158|12.146|0.223|999| |         |  2.31754222|  2.23186444|1.67|1.54| 88.0|100.8| |-0.2
0001 00041 1|X|            |            |       |       |   |   |    |    |       |       |  |   |   |   |   |13.035|0.320|12.235|0.220|999| |         |  1.80874194|  2.31573611|1.75|1.77|112.2|148.2| | 0.0
EOF
# the staging directory is nested in a directory that does not exist yet, as in the factory
lib/catalogs/local_star_catalog tycho2-extract "$WORK_DIR/tycho2/.staging.$$" tycho2 "$WORK_DIR/tyc2.dat.00" 2>/dev/null || fail LOCALSTARCAT_TYCHO2_EXTRACT
lib/catalogs/local_star_catalog finalize "$WORK_DIR/tycho2/.staging.$$" "$WORK_DIR/tycho2" tycho2 "synthetic Tycho-2" 2>/dev/null || fail LOCALSTARCAT_TYCHO2_FINALIZE
rm -rf "$WORK_DIR/tycho2/.staging.$$"
TYCHO2="-cat=tycho2:$WORK_DIR/tycho2"
# TYC 1-8-1 moved by its proper motion to epoch 2016.0: RA 2.3174324, Dec 2.2318035; V = VT for BT = VT
LINE=$(search "$TYCHO2" -c="2.3174324 2.2318035" -c.rs=1 -out.max=3 -sort=Gmag Gmag=0.0..20.0 | head -n1)
echo "$LINE" | awk '$2 == 1000081 && $1 < 0.05 && $5 > 12.145 && $5 < 12.147 {ok=1} END {exit ok ? 0 : 1}' || fail LOCALSTARCAT_TYCHO2_PM "got #$LINE#"
# TYC 1-41-1 at its observed position, V = VT - 0.090 (BT - VT) = 12.163
LINE=$(search "$TYCHO2" -c="1.80874194 2.31573611" -c.rs=1 -out.max=3 -sort=Gmag Gmag=0.0..20.0 | head -n1)
echo "$LINE" | awk '$2 == 1000411 && $1 < 0.05 && $5 > 12.162 && $5 < 12.164 {ok=1} END {exit ok ? 0 : 1}' || fail LOCALSTARCAT_TYCHO2_XFLAG "got #$LINE#"

##### VaST's native UCAC5 zone files (52-byte records sorted by RA) #####
if command -v python3 &>/dev/null ;then
 mkdir -p "$WORK_DIR/ucac5"
 python3 - "$WORK_DIR/ucac5" << 'EOF'
import struct, sys
d = sys.argv[1]
fmt = '<qiihhbbhiihhhhhhhhhh'
def rec(srcid, ra, dec, gmag, fmag):
    mas = lambda x: int(round(x * 3.6e6))
    return struct.pack(fmt, srcid, mas(ra), mas(dec), 0, 0, 0, 0, 0, mas(ra), mas(dec), 0, 0, 0, 0, int(round(gmag * 1000)), int(round(fmag * 1000)), 0, 0, 0, 0)
open(d + '/z001', 'wb').close()
# zone 462: Dec +2.2..+2.4, sorted by RA; 5001 is TYC 1-8-1 0.5" away, 5002 a fainter star 4" away
with open(d + '/z462', 'wb') as f:
    f.write(rec(5003, 1.0, 2.3, 10.0, 10.5))
    f.write(rec(5001, 2.3174324 + 0.5 / 3600, 2.2318035, 12.05, 12.4))
    f.write(rec(5002, 2.3174324, 2.2318035 + 4.0 / 3600, 13.0, 13.3))
    f.write(rec(5004, 300.0, 2.3, 9.0, 9.5))
EOF
 UCAC5="-cat=ucac5:$WORK_DIR/ucac5"
 RESULT=$(search "$UCAC5" -c="2.3174324 2.2318035" -c.rs=5 -out.max=3 -sort=Gmag Gmag=0.0..20.0 | ids)
 [ "$RESULT" = "5001 5002" ] || fail LOCALSTARCAT_UCAC5 "got #$RESULT#"
 # merged with Tycho-2: TYC 1-8-1 and UCAC5 5001 are one star, reported once
 RESULT=$(search "$TYCHO2" "$UCAC5" -c="2.3174324 2.2318035" -c.rs=5 -out.max=3 -sort=Gmag Gmag=0.0..20.0 | ids)
 [ "$RESULT" = "5001 5002" ] || fail LOCALSTARCAT_MERGE_DEDUP "got #$RESULT#"
else
 echo "python3 is not available - skipping the UCAC5 part of the test"
fi

rm -rf "$WORK_DIR"
if [ -n "$FAILED_CODES" ];then
 echo "Failed checks:$FAILED_CODES"
 exit 1
fi
echo "All local star catalog checks passed"
exit 0
