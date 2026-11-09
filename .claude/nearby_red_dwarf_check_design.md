# UV Ceti check: a nearby red dwarf at the position of a transient candidate

Implemented 2026-11-09. Tool: `util/transients/check_nearby_red_dwarf.sh`; catalog:
`lib/catalogs/gaia_dr3_nearby` built by `lib/install_local_copy_of_GaiaDR3_nearby_stars.sh`;
report integration: `util/transients/report_transient.sh`; tests:
`util/examples/test_nearby_red_dwarf_check.sh` and the nearby-catalog part of
`util/examples/test_local_star_catalog.sh`; unmw: `filter_report.py` (terminator and the
`uv_ceti_check` JSON field).

## Purpose

A flare of a K or M dwarf closer than 200 pc (a UV Ceti-type flare) is the most common
short-lived brightening the NMW/TTU transient search picks up. Until 2026-11 the check for a
nearby red dwarf was done by hand in CDS Aladin. CDS being down for days made a local tool
necessary. The check answers, for the position and epoch of a candidate: is there a Gaia DR3
star with parallax > 5 mas (closer than 200 pc) at the position once its proper motion is
applied, and what kind of star is it?

## Data flow

1. The stars with parallax > 5 mas and parallax_over_error > 3 within the search cone are
   taken from the first source that works:
   - the local copy `lib/catalogs/gaia_dr3_nearby` (`local_star_catalog search
     -cat=gaia_dr3_nearby:DIR -sort=_r`, wide output format, no network, instant);
   - the ESA Gaia archive (synchronous TAP, `gaiadr3.gaia_source`, 1-90 s);
   - the Gaia DR3 table I/355/gaiadr3 at a VizieR mirror through `lib/vizquery` (TSV, so
     empty fields keep their columns). A control query without constraints must list at
     least one Gaia star within 5' first: on 2026-11-09 vizier.cfa.harvard.edu answered every
     query with a complete but empty table, which would otherwise pass as "no nearby star".
2. The cone radius grows with the epoch difference: MATCH_RADIUS + 11"/yr x |epoch - 2016.0|,
   at least 60" (Barnard's star moves 10.4"/yr). About 130" in 2026.
3. Every star is moved from 2016.0 to the observation epoch (linear proper motion,
   pmRA*cos(Dec) divided by cos(Dec) in RA). The propagation was cross-checked against the
   archive's EPOCH_PROP_POS function on the Aur-05 field: 0.616" vs 0.62".
4. The star whose propagated position is within MATCH_RADIUS (in the pipeline the
   catalog-match tolerance, the image scale: 5.9" for TTU) is classified.

## Classification

- d = 1000/parallax, M_G = G + 5 log10(parallax_mas) - 10.
- Colour: BP-RP when BP is present and G <= 19.5, otherwise G-RP (BP of faint red stars is
  biased by background flux) and the line says so. G-RP is not a cross-check: the main
  sequence is so steep in G-RP for late M dwarfs that 0.1 mag of colour is 1.5 mag of M_G
  (UV Cet, BP-RP 3.83 and G-RP 1.39, sits on the locus by BP-RP and 1.6 mag below it by
  G-RP; the first version switched to G-RP on such a disagreement and called UV Cet a
  subdwarf or composite).
- "Red dwarf" means BP-RP >= 1.0 (K0V has 0.98) or G-RP >= 0.58 - all K and M dwarfs, as
  decided on 2026-11-09.
- The main-sequence locus (BP-RP, G-RP, M_G) is a 14-point table from K0 to M9 (Pecaut and
  Mamajek dwarf sequence with G-V from the Gaia DR2 photometric relations, about 0.3 mag
  accurate). The offset is quoted in sigmas with sigma = sqrt((2.17 e_plx/plx)^2 + 0.5^2),
  the 0.5 mag being the intrinsic width of the main sequence.
- Verdicts (exit code in brackets):
  - M_G < 4: giant or subgiant [2];
  - not red: a white dwarf when M_G > 10, otherwise a dwarf earlier than K0 [2];
  - red, more than 2.5 mag and 3 sigma below the locus: a white dwarf + red dwarf binary
    or a cataclysmic variable rather than a single red dwarf; a flare on the companion or a
    dwarf nova outburst is possible [2];
  - red, 1.0-2.5 mag below (3 sigma): a metal-poor subdwarf or a composite system, a UV
    Ceti-type flare is plausible [0];
  - red, more than 1.0 mag above: a young star or an unresolved binary, flare likely [0];
  - red, within 1.0 mag of the locus: on the main sequence, flare likely [0].
  - no star closer than 200 pc at the position [1]; check not performed [3]; usage [4].

Can Gaia tell that a star is below the main sequence? With parallax_over_error > 3 the
distance modulus error is below 0.7 mag, and usually far below (0.07 mag for the Aur-05
star), so a 5-mag offset is unambiguous. Offsets of 1-2 mag are not: the main sequence is
0.5 mag wide, metal-poor subdwarfs sit 1-2 mag below it, reddening (small within 200 pc, but
not zero at low latitude) moves a star down and to the right, and BP of faint red stars is
biased blue. Hence the 3-sigma and 2.5-mag requirements before the composite-system verdict,
and G-RP for the stars whose BP cannot be trusted.

Checked against the finished local copy on 2026-11-09: AD Leo (201 mas, 0.5"/yr) at its 2026.9
position is matched at 0.4" after a 5.9" proper-motion shift and called an M3 dwarf on the main
sequence (and is 14" away, unmatched, when the epoch is given as 2000.0); both components of
UV Cet (374 and 368 mas, 3.4"/yr) land within 3" of the propagated position after a 38" shift
and are called main-sequence M dwarfs; the Aur-05 star gets the same line as from the archive.

## The example that started this (2026-11-08, TTU Aur-05-Q2)

Candidate at 04:49:22.53 +29:26:01.6, 14.7 mag, VSX "Gaia DR3 158334278606721152" (type E,
P = 0.37 d, G = 18.8-19.0). The check finds that star 0.6" from the position (0.3" at
2016.0): d = 135 +/- 4 pc, G = 18.87, BP-RP = 1.79, M_G = 13.2, 4.9 mag (10 sigma) below the
main sequence: a white dwarf + red dwarf eclipsing binary (or a CV) rather than a single red
dwarf. The M dwarf 11" away (118 pc, BP-RP 3.76) is not the transient.

## The local catalog

Built on tau on 2026-11-09 in /data_ssd/GaiaDR3_nearby (linked as lib/catalogs/gaia_dr3_nearby):
4697159 records, 195 MB, equal to the whole-sky COUNT(*) of the selection, about 4 hours of
throttled downloading.

`local_star_catalog` got a second record layout, 40 bytes: the usual 24 (id, RA, Dec, G, BP,
RP, flags) followed by int32 parallax (microarcsec), uint16 parallax error (microarcsec,
65535 = unknown), int16 RUWE*1000, int32 pmRA and pmDec (microarcsec/yr). The record size is
a runtime variable (`g_rec_size`) chosen by the catalog name at `finalize` and read from
`record_size=` in catalog_info.txt at `search`; the first 24 bytes have the old layout, so
the zone sorting and the RA index are unchanged. `nearby-extract` reads a CSV with the ESA
column names. The search prints the wide format (BPmag, Plx, e_Plx, pmRA, pmDE, RUWE after
the usual columns) when any searched catalog has the 40-byte records, and `-sort=_r` orders
by distance.

The installer downloads the 4.7 million sources (parallax > 5 mas, parallax_over_error > 3;
190 MB as zones) from the ESA archive with synchronous TAP queries, one per equal-area
declination band (100 by default, about 47000 stars each). Each band is counted once with
COUNT(*); a band with more than 60000 sources is cut into equal RA pieces, twice as many as
the count alone would need (the Galactic plane and the Magellanic Clouds add many sources
with spurious parallaxes that pass parallax_over_error > 3, so the stars are not spread
evenly in RA), and the rows of the pieces must add up to the count, otherwise the band is
cleared and fetched in twice as many pieces on the next run. The count is essential: a TAP
reply cut at the row limit is otherwise indistinguishable from a complete one. An earlier
version counted every piece recursively, which doubled the throttled requests and took
5 min per southern band. Measured on 2026-11-09:
anonymous asynchronous jobs get executionDuration = 60 s and are ABORTED (empty error
summary) when the query runs longer, a request for a longer duration is ignored;
synchronous replies are cut at 50000 rows unless the request carries a larger MAXREC (the
installer asks for 1000000 and got 60000 rows back in a test); the archive returns these
rows at about 1500 per second, so a 768000-star band can never finish as an async job,
while a synchronous query of 39000 rows took 28 s and came back complete. Counting by
declination band takes seconds, counting by source_id range 48 s (no useful index), hence
declination bands. The archive refuses requests that follow each other within seconds, and
bursts of them, with HTTP 429, so the installer pauses 15 s after every reply and retries
every 60 s. The build is resumable (finished pieces stay in DESTINATION_DIR/.staging; keep
the band count). The transient factory links the copy from the usual catalog directories
(/data_ssd/GaiaDR3_nearby, ...) like the Gaia DR2 copy, and logs which source the check
will use.

## Report integration and parser safety

`report_transient.sh` starts the check in the background group with the VSX and asteroid
checks (so the ESA latency, when the local copy is missing, is hidden behind MPCheck), for
every surviving candidate including VSX matches, and prints the line after the
forced-photometry lines, before the TNS link. The line starts with `UV Ceti check` and never
contains 'The object was', 'found in', 'not found' or 'mag brighter than the'; a check that
could not be done prints `UV Ceti check: not performed (why)`, a disabled check prints
nothing. `UV_CETI_CHECK=no` disables it. In the test suite
(`THIS_IS_VAST_TEST` set) it runs only with the local copy, so the tests never send a query
per candidate to the online services. unmw's `filter_report.py` ends the astcheck match block
at the new prefix and exports the line as `uv_ceti_check`; both repositories must move
together when the prefix changes. The timing log gets `UVCETI_CHECK` entries.

## Known limitations

- Online sources are only as good as their answers: the ESA archive queues synchronous
  queries for up to 90 s under load; VizieR mirrors may serve empty tables (guarded by the
  control query) and vizier.cfa.harvard.edu needs the https redirect that `lib/my_vizquery.sh`
  follows since 2026-11-09.
- Stars with parallax_over_error <= 3 are never reported, so a few genuine nearby stars at
  G > 20.5 are missed; the 200 pc limit is on the inverse parallax, not on a distance prior.
- The locus table is approximate; metallicity, youth, binarity and reddening move stars by up
  to 1-2 mag, which the thresholds absorb, and a reddened distant star never enters (parallax).
- The line is informational: nothing is filtered on it.
