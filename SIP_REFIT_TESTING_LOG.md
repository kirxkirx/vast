# Plate-solution refit policy: testing and bug-fixing log

Started 2026-07-24. Machine: the main development box (`/home/kirx/vast_test/vast`),
local Astrometry.net at `/usr/local/astrometry/bin`.

## What is being tested

The refit policy settled in the preceding work:

1. A WCS that VaST trusts is **kept**, never refit. Trust is decided in one place,
   `check_if_we_know_the_telescope_and_can_blindly_trust_wcs_from_the_image()` in
   `util/identify.sh`, and covers Astrometry.net / SCAMP / SWarp provenance as well as
   the mission pipelines (ZTF, TESS, ATLAS, ASTAP). The decision reaches
   `util/solve_plate_with_UCAC5` through a `<plate-solved image>.blindly_trusted_wcs`
   marker file.
2. An image with **no** trusted WCS is solved, and then its distortion model is
   determined from the UCAC5 cross-matches: SIP orders 2 and 3 are each fitted and the
   better one wins, with order 3 required to beat order 2 by more than
   `SIP_REFIT_HIGHER_ORDER_GAIN` (0.95).
3. A refit of a trusted solution happens only on explicit request,
   `VAST_FORCE_SIP_REFIT=1`, which `util/solve_plate_with_best_sip_order.sh` sets.
4. `util/solve_plate_with_UCAC5` never rewrites the caller's input image and never
   writes through a symbolic link.

Plus the earlier refit guards: the acceptance gate compares against
`min(raw, corrected)` baselines, and a frame-coverage guard rejects a refit fitted on
only part of the frame.

## Test programs

- `util/examples/test_sip_refit_policy.sh` - new, dedicated, asserts the policy itself
  per camera (NMW/ST-8300, NMW-STL/STL-11000M, NMW-TTU/QHY600M, TICA TESS) using the
  `SIP_refit_policy_test` dataset.
- `util/examples/test_vast.sh` - the full system test, several hours.

## Goal

No failing tests other than the known-optional / environmental ones.

---

## Run log

(entries appended below as runs complete)

### Predictions before the first run

Written down before seeing any result, so that a surprise is recognisable as a surprise.

- `test_vast.sh` "NMW-STL plate solve failure test" should go back to PASSING. Its reference
  image carries an Astrometry.net solution, which is now trusted, so the refit no longer runs
  and the deliberately broken solution stays broken - which is the test's whole premise. This
  is the policy change fixing `NMWSTLPLATESOLVEFAILURE_NO_BROKEN_SOLUTION_ERROR` at the root
  rather than by relaxing the assertion.
- "Forced photometry test" should go back to `mean ~ -0.004 / RMS ~ 0.015`, because sky2xy now
  runs on the same plate-solved copy the `.wcscat` describes.
- The Cas-02 test still exercises the refit: it strips the WCS first
  (`lib/astrometry/strip_wcs_keywords`, which also removes the Astrometry.net provenance
  cards), so the frame is untrusted and gets solved, refit and order-selected.
- Nova Sgr and TICA TESS: TICA is now never refit, so its position should return to the green
  value; Nova Sgr's reference is trusted so it is no longer refit either, and its magnitude
  should return to the pre-regression value. Both assertions were also widened.

### Known-optional codes (not counted as failures)

Auto-stripped by `test_vast.sh` itself: `PSFEX_NOT_INSTALLED`, `WCSTOOLS_NOT_INSTALLED`,
`VARTOOLS_NOT_INSTALLED`, `AUXWEB_WWWU_003`, `STANDALONEDBSCRIPT001a/001b_GCVS`,
`scan.sai.msu.ru_REMOTEPLATESOLVE007-009`, `none_REMOTEPLATESOLVE007-009`,
`*_SELENIUM_TEST`, `LIBPNG_DISABLED`, the various `NOT_PERFORMED_*` codes.

NOT auto-stripped but known-environmental on this box (see the project memory):
`tau.kirx.net_REMOTEPLATESOLVE001/003/005/007` - remote plate solving against tau.kirx.net.

### Run 1 - `test_sip_refit_policy.sh`, first execution ever

**Result: 68 of 77 checks passed.** Nine failure codes, but only **three** distinct causes - one
real VaST bug and two defects in the brand-new test:

```
SIPPOLICY_NMW_STRIPPED_INPUT_MODIFIED            <- real bug (strip_wcs_keywords)
SIPPOLICY_NMWSTL_FORCED_REFIT_NOT_ATTEMPTED      <- test bug (assertion too strict)
SIPPOLICY_TICATESS_ORDER2_NOT_TRIED              <- test bug (TESS FFI is not blind-solvable);
SIPPOLICY_TICATESS_ORDER3_NOT_TRIED                 all seven TICATESS codes are this one cause
SIPPOLICY_TICATESS_NO_ORDER_SELECTED
SIPPOLICY_TICATESS_REFIT_NOT_APPLIED
SIPPOLICY_TICATESS_ORDER_MISMATCH__vs_
SIPPOLICY_TICATESS_NOT_TAN_SIP_
SIPPOLICY_TICATESS_RESIDUAL_none
```

Per camera: NMW 18/19, NMW-STL 18/19, **NMW-TTU 19/19**, TICA TESS 9/16 with all seven failures
downstream of the one blind solve that could not converge.

Every core policy assertion passed on real data:

- trusted WCS recognized and kept, no refit applied, marker file written
- the input image left byte-identical, and the plate-solved copy carrying the original WCS
- `VAST_FORCE_SIP_REFIT=1` bypassing the trusted-WCS rule
- a shared file reached through a symbolic link not rewritten
- for an unsolved image: orders 2 and 3 both tried, one selected, the header carrying the
  selected order, `RA---TAN-SIP` produced, and the residual well inside the limit
  (NMW **0.776 arcsec**, NMW-STL **1.563 arcsec**)

Three separate problems came out of this run.

#### BUG 1 (real, in VaST): `lib/astrometry/strip_wcs_keywords` removes only the FIRST card of each keyword

Symptom: `SIPPOLICY_NMW_STRIPPED_INPUT_MODIFIED` - the NMW working image changed during a run
that should not have touched it, while the NMW-STL image did not.

Isolated it away from any plate solving: stripping the same file twice and comparing checksums.

```
Sco6_2012-4-18_0-30-54_002.fts : CHANGES ON 2nd STRIP
025_2022-8-27_20-27-36_002.fts : IDEMPOTENT
```

Header diff between the two passes: a single surviving `WCSAXES` card, removed only by the
second pass. The card count across the whole dataset matches the symptom exactly - Sco6 is the
only frame with a duplicate, and NMW was the only camera whose check failed:

```
025_2022-8-27_20-27-36_002.fts     WCSAXES cards: 1
Aql-03-Q1b1x1_2026-05-15_03-45-29  WCSAXES cards: 1
Sco6_2012-4-18_0-30-54_002.fts     WCSAXES cards: 2
s0081-...tica_tess_ffi...fits      WCSAXES cards: 0
```

Cause: the Sco6 header carries **two** `WCSAXES` cards (the STL one carries one),
and `strip_wcs_sip_keywords()` in `src/astrometry/strip_wcs_keywords.c` did one
`fits_read_card()` + `fits_delete_key()` per keyword name - and cfitsio's `fits_delete_key()`
removes only the first match. Duplicate cards therefore survived a pass.

Why it matters beyond idempotency: the same single-shot pattern was used for every keyword in
the list, including `CTYPE1`, `CRVAL1` and `CD1_1`, and for the TPV, TR and SIP-coefficient
keywords. A duplicated card could leave a partial WCS in an image that is supposed to look
unsolved - and `util/identify.sh` decides "already solved" by looking for exactly these
keywords, so a survivor can defeat the forced re-solve that
`util/solve_plate_with_best_sip_order.sh` depends on. A header ends up with duplicate WCS
cards whenever a solution is inserted into a header that already had one, which is routine.

Fix: new bounded helper `delete_all_cards_with_this_keyword()` that loops until
`KEY_NO_EXIST`, used for all 13 deletion sites in the file. Cap
`STRIP_WCS_MAX_DUPLICATE_CARDS` 1000 so a delete that silently fails cannot spin.

Verified by compiling the fixed tool standalone (so the running test's binaries were not
disturbed) and stripping each frame type twice:

```
Sco6_2012-4-18_0-30-54_002.fts : IDEMPOTENT ; WCS cards left after 1st pass: 0
025_2022-8-27_20-27-36_002.fts : IDEMPOTENT ; WCS cards left after 1st pass: 0
s0081-...tica_tess_ffi...fits   : IDEMPOTENT ; WCS cards left after 1st pass: 0
```

#### BUG 2 (in the new test): the forced-refit assertion was too strict

Symptom: `SIPPOLICY_NMWSTL_FORCED_REFIT_NOT_ATTEMPTED`. The log shows why, and it is the
frame-coverage guard doing exactly its job on the real NMW-STL problem frame:

```
SIP_REFIT: VAST_FORCE_SIP_REFIT is set - refitting regardless of whether the input WCS is trusted
SIP_REFIT: the 467 catalog matches do not cover the frame (9/9/208/241 per quadrant, need 29 in each)
WCS_QUALITY_DIAG: ... sigma_q1=14.079 sigma_q2=44.508 sigma_q3=3.788 sigma_q4=4.424
                  n_q1=9 n_q2=9 n_q3=208 n_q4=241 worst_quadrant_to_overall_ratio=10.194
```

That is an independent confirmation, on this machine and on real data, of the pathology
originally found in the CI logs (there 6/9/194/223). Forcing a refit bypasses the *trust*
check; it does not and should not bypass the later quality guards. The assertion now checks
that the trusted-WCS skip was bypassed and that the refit reached a decision, where a
coverage-guard or too-few-matches refusal counts as a decision.

#### BUG 3 (in the new test): the unsolved image was placed in the working directory

The untrusted case put its working copy in the VaST directory. `util/identify.sh:759` then
legitimately treats it as its own scratch file - it says so out loud: *"Not creating a local
copy of the FITS image as the input image is already in the current directory. The input image
will be modified!"* - and strips its WCS in place. The test now keeps the unsolved image in a
`sip_refit_policy_input/` subdirectory, which is also how VaST is normally used.

#### BUG 4 (in the new test): a TESS FFI cannot be blind-solved, so the "no trusted WCS" case is not applicable to it

The TICA case stripped the mission WCS and expected VaST to re-solve the frame. It cannot. A
TICA full frame image spans about 12.5 degrees, and over a field that wide the quads
astrometry.net builds from the detected stars no longer match the index quads. This box does
have the right scale range installed (`index-4117` covers 680-1000 arcmin and the frame is
about 750 arcmin), and every index from `index-4205` down to `index-4113` was tried, each
reporting `Field 1 did not solve`, until the 900 s `timeout` on the solve expired.

Not a VaST defect - and a neat illustration of why this policy exists in the first place: for a
TESS FFI the mission solution is the only practical astrometry available, so it must be trusted
rather than recomputed. The test now carries a per-camera "blind-solvable" flag and skips the
no-trusted-WCS case for TICA with that reason printed.

Also added while here: an optional camera-tag argument
(`util/examples/test_sip_refit_policy.sh NMW`) so a single frame can be re-checked quickly
instead of re-running the whole set.

#### FINDING (pre-existing, NOT changed): VaST modifies an input image that sits in its working directory

Independent of the bug above: running VaST on an image located in the VaST directory strips
that image's WCS keywords in place. It is announced in the output and long-standing, but it is
worth knowing, because the documented convention is that outputs are `wcs_<basename>` and the
input is left alone. Left as is - changing it touches the main solve path and is outside the
scope of this work.

#### Where the duplicate cards come from (background to BUG 1)

`src/astrometry/insert_wcs_header.c:510` writes the new WCS
cards with `fits_write_record()`, which appends unconditionally rather than replacing. Since
`util/identify.sh` always strips before inserting, that is safe on its own - but combined with
the strip bug above it formed a ratchet: each solve could leave a card behind and append a new
one. The strip fix breaks the loop, so `insert_wcs_header.c` is deliberately left alone (the raw
cards it writes include HISTORY and COMMENT, which legitimately repeat, so switching it to
`fits_update_card` would need care for no benefit here).

Checked for the same delete-only-the-first-match pattern elsewhere: `src/ccd/mk.c` and
`src/ccd/mk_fast.c` also call `fits_delete_key()` once per name, but on mandatory structural
keywords (`SIMPLE`, `BITPIX`, `NAXIS*`) of a header they are building themselves, where a
duplicate cannot arise. Not the same bug.

### What run 1 already tells us about the original CI failures

The policy test exercises exactly the frames behind three of the four CI regressions, so it
provides direct evidence ahead of the `test_vast.sh` run:

- `NMWSTLPLATESOLVEFAILURE_NO_BROKEN_SOLUTION_ERROR`: the reference frame of that dataset is
  `025_2022-8-27_20-27-36_002.fts`, and run 1 shows it is now recognized as trusted, gets a
  marker, and is **not** refit. Its deliberately broken solution therefore stays broken, which
  is the test's premise - so the assertion should pass again, fixed at the root rather than by
  relaxing it.
- `TICATESSFINDNVUL240110a`: the TICA frame is trusted and not refit, so the nova's position
  should return to its pre-regression value.
- `NMWNSGR24N10110a`: the Nova Sgr reference `Sco6_2012-4-18_0-30-54_002.fts` is trusted
  (`astrometrynet`) and not refit, so the Tycho-2 zero point should return to its previous value
  and the magnitude to 11.1x. The widened window covers it either way.
- `FORCEDPHOT010`: the forced-photometry frame is also Astrometry.net-solved, hence trusted and
  not refit, so the `.wcscat` sky coordinates again describe the same solution the input image
  carries and the round trip closes. The `sky2xy`-on-the-solved-copy change remains correct and
  is what keeps this right whenever a refit *does* happen.

### Run 2 - after the fixes

Rebuilt with the `strip_wcs_keywords` fix and the corrected test script.

- NMW: **20/20**, including `the unsolved input image is left byte-identical` - the check that
  exposed the strip bug - and the refit residual again 0.776 arcsec with order 3 selected.
- NMW-STL: **20/20**, residual 1.563 arcsec, order 3 selected, and the new
  `the trusted-WCS skip is bypassed` / `the forced refit reaches a refit decision` assertions
  both passing (the coverage guard still declines the refit on this frame, which is correct).
- NMW-TTU: 20/20, residual 0.701 arcsec, order 3 selected.
- TICA TESS: 11/11, with the no-trusted-WCS cases correctly skipped and the reason printed.

**Result: 71 of 71 checks passed - ALL CHECKS PASSED, exit code 0.**

So the policy holds on all four cameras: NMW/ST-8300, NMW-STL/STL-11000M, NMW-TTU/QHY600M and
TICA TESS. The one real-bug fix and all three test fixes are confirmed by re-running.

### Run 3 - `test_vast.sh`, the full system test

Started automatically once run 2 came back clean. Expect several hours.

Progress, no failures so far. The section that was red in CI as `CAS02RA0SIP002` now passes
locally, which is the newly gated Cas-02 test exercising a real blind solve plus the new SIP
order selection:

```
NMW-TexasTech Aur-02-Q2b1x1 variables test                 PASSED (8.5 min)
NMW-TexasTech Aql-03-Q1b1x1 asteroid-variable cross-check  PASSED (9.4 min)
NMW-TexasTech Cas-04 plate-solve failure test              PASSED (9.4 min)
NMW-TexasTech Cas-02 RA=0 wraparound plate-solve test      PASSED (3.4 min)
NMW find Nova Sgr 2024 N1 test                             PASSED (1.5 min)
NMW find Nova Vul 2024 ST test                             PASSED (5.6 min)
```

That is `CAS02RA0SIP002` and `NMWNSGR24N10110a` both green again, and the Nova Vul selenium
section passing too (it is an umbrella for external-web flakiness and does not gate CI anyway).

Note on log noise: the run prints `verification FAILED: ../NMW_Sgr9_crash_test/reference_images/
...fts, 1 errors` for two 2012-vintage NMW frames. That is VaST's own FITS-standard check, it is
followed by a WARNING and processing continues normally - it is not a test-section failure. Any
automated watch on this log needs to exclude the string `verification FAILED`.

**Run 3 result: 263.1 minutes, exactly one failing section** - "Plate solving with remote
servers", with codes `tau.kirx.net_REMOTEPLATESOLVE001/003/005/007`. Everything else passed,
including all four sections that were red in CI:

```
NMW-TexasTech Cas-02 RA=0 wraparound plate-solve test  PASSED   (was CAS02RA0SIP002)
NMW find Nova Sgr 2024 N1 test                         PASSED   (was NMWNSGR24N10110a)
TICA TESS find Nova Vul 2024 test                      PASSED   (was TICATESSFINDNVUL240110a)
NMW-STL plate solve failure test                       PASSED   (was NMWSTLPLATESOLVE...ERROR)
Forced photometry test                                 PASSED   (was FORCEDPHOT010)
```

Forced photometry is back to its pre-regression numbers exactly:
`N=100 mean=-0.0038 RMS=0.0145` (it had been `mean=0.0235 RMS=0.0696`).

#### BUG 5 (real, in VaST): a host whose name is a substring of a server's name loses that server

My earlier note recorded `tau.kirx.net_REMOTEPLATESOLVE*` as a known-environmental failure on
this box, blamed on kirx.net storage being full. **That was wrong.** The real cause:

`setup_remote_astrometry()` in `util/identify.sh` decides reachability by ICMP `ping -c1 -W1`.
On this network ICMP is filtered, so *no* server answers - verified directly: both
`tau.kirx.net` and `scan.sai.msu.ru` fail `ping` yet return HTTP 200. There is a fallback for
exactly that case, an HTTP probe of `http://<server>/lk/`, and that probe succeeds for both
servers when run by hand. But the fallback loop first skips any server that looks like
"ourselves":

```sh
echo "$i" | grep -q "$HOST_WE_ARE_RUNNING_AT"   # substring match!
```

This machine's hostname is **`tau`**, which is a substring of **`tau.kirx.net`**, so the only
candidate server was skipped and the run ended with `ERROR: no servers could be reached`. The
two are definitely different machines: `tau.kirx.net` resolves to 188.226.149.203 while this
box's external address is 129.118.254.21.

The heuristic cannot distinguish "I am running ON tau.kirx.net" (where skipping is right, and
is presumably why it was written - the production server's hostname is `tau`) from "I am on a
different machine that merely happens to be called tau". Only comparing addresses could, and
that is not portable enough to do casually in this path.

Fix applied - conservative, and it cannot make the production case worse: the self-exclusion is
now applied only while at least one *other* candidate server remains. Talking to ourselves still
works; having no server at all does not.

Verified both directions:
- forcing `tau.kirx.net` as the only server (what the test does) now solves:
  exit 0, `VAST003 = 'tau.kirx.net'`, solved image produced, `xy2sky` on it OK.
- with both servers listed, `tau.kirx.net` is still excluded as self and `scan.sai.msu.ru`
  is probed - the original intent is preserved.

Any host called `scan` or `vast` would hit the same bug against `scan.sai.msu.ru` /
`vast.sai.msu.ru`. Worth considering a proper address-based self-check later.

### Run 4 - `test_vast.sh` again, with the remote-server fix

**269.5 minutes, exit code 0, zero failing sections.**

```
Test for plate solving with remote servers   PASSED (2.1 min)     <- was the last failure
Forced photometry test                       PASSED (2.5 min)
Forced photometry --list mode test           PASSED (2.4 min)
Solar System info test                       PASSED (1.5 min)
Failed test codes:  NOT_PERFORMED_SOLAR_SYSTEM_INFO_COMET_LOCAL_REMOTE_POSITION_noskyfield
                    NOT_PERFORMED_SOLAR_SYSTEM_INFO_PLANET_LOCAL_REMOTE_POSITION_noskyfield
                    VARTOOLS_NOT_INSTALLED
```

The three remaining codes are the optional ones: the `skyfield` Python module and `vartools`
are not installed on this machine. All three are in `test_vast.sh`'s own auto-strip list, which
is why the suite exits 0.

---

## Summary

Goal reached: `util/examples/test_sip_refit_policy.sh` 71/71, and `util/examples/test_vast.sh`
exit 0 with no failing sections and only optional codes left.

**Two real bugs in VaST, found by the tests and fixed:**

1. `src/astrometry/strip_wcs_keywords.c` removed only the first card of each WCS keyword name,
   so duplicated cards survived. Non-idempotent, and able to leave a partial WCS in an image
   meant to look unsolved - which `util/identify.sh` reads as "already solved". Fixed with a
   bounded delete-all helper at all 13 deletion sites.
2. `util/identify.sh` excluded a remote plate-solve server whenever the local hostname was a
   *substring* of the server name, so this box (hostname `tau`) lost `tau.kirx.net` and, with
   ICMP filtered on this network, ended up with no server at all. Fixed by applying the
   self-exclusion only while another candidate server remains.

**Three defects in the new policy test, fixed:** an over-strict forced-refit assertion (forcing
bypasses the trust check, not the quality guards); the unsolved image being placed in the
working directory, where `identify.sh` legitimately claims it as scratch; and the attempt to
blind-solve a TICA TESS FFI, which is not possible over a 12.5 degree field.

**A correction to earlier project notes:** the `tau.kirx.net_REMOTEPLATESOLVE*` failures were
recorded as known-environmental, caused by full storage on kirx.net. That was wrong - they were
this hostname-substring bug all along, and they are now fixed rather than tolerated.

**One pre-existing behaviour documented but deliberately not changed:** VaST strips the WCS of
an input image that sits in its own working directory, announcing it in the output. Changing
that touches the main solve path and was out of scope here.
