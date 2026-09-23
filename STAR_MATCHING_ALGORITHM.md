# VaST star matching (similar-triangle algorithm): description, evaluation, and improvement ideas

This document describes how VaST cross-identifies stars between two images of the
same field, evaluates the algorithm's behaviour, and proposes concrete ways to
get **more correct matches and fewer false matches** - with particular attention
to the wide-field transient-search use case, to the situation where the new image
is much shallower than the reference, and to images affected by distortion (e.g.
atmospheric refraction at low altitude). Speed-up ideas are collected at the end.

The core matcher is `src/ident_lib.c`, driven from the per-image loop in
`src/vast.c`. Line numbers below refer to the current working tree and may drift.

---

## 1. Where matching sits in the transient pipeline

For a single NMW/NMW-TexasTech field, `vast` is run on a list of FITS images:
two (or more) archival reference-epoch frames followed by the new-epoch frames,
e.g. (from a real Cas-03 run):

```
./vast --norotation --noflagimage --starmatchraius 3.5 --matchstarnumber 500 \
       --selectbestaperture --sysrem 0 --type 4 --maxsextractorflag 99 \
       --UTC --nofind --nojdkeyword  ref1.fits ref2.fits new1.fits new2.fits
```

- SExtractor detects stars on every image, producing a per-image list of
  `(x, y, mag, flags, ...)`.
- **The first image is the reference frame.** Its star list is fixed. Every
  other frame is matched **independently against the reference** (matches are
  never chained frame-to-frame). Loop: `vast.c:3298`.
- Matching returns, per new frame, a coordinate transformation (new-frame pixels
  -> reference-frame pixels) and a list of matched star index pairs. VaST then
  builds each star's lightcurve from the matched detections across frames, and
  the transient search compares reference-epoch vs new-epoch brightness per star.

So **star matching is the backbone of transient detection**: a star that fails
to be matched, or is matched to the wrong neighbour, produces a spurious
brightness change and a false candidate (or a missed real one). The downstream
forced-photometry step (Section 9) is an independent absolute-WCS measurement
used to *reject* matcher-induced false positives - it does not repair the match.

---

## 2. Inputs to the matcher

Three star arrays are prepared (`Ident()`, `ident_lib.c:~2246`; comment at 2235):

- **STAR1 / NUMBER1** - all "considered" reference-frame stars.
- **STAR3 / NUMBER3** - the *clean* subset of reference stars (SExtractor flag 0,
  i.e. unblended/unsaturated). STAR3 is used to build the **initial** transform;
  STAR1 is used afterward to match the full list.
- **STAR2 / NUMBER2** - the current (new) frame's stars.

Two preparation steps matter for everything below:

1. **Magnitude sort, brightest first.** `Sort_in_mag_of_stars()` (`ident_lib.c:184`)
   qsorts by ascending magnitude and *pushes blended/saturated stars to the back*
   so they never appear among "the brightest". Reference lists are sorted once
   (`vast.c:3089,3092`), each new frame at `vast.c:3703`.
2. **Brightest-N cap.** Only the brightest `Number_of_main_star` stars are used to
   build triangles. Default 100 (`ident_lib.c:90`); set by `-b`/`--matchstarnumber`
   (500 in the command above). Inside `Ident()` the reference count is *scaled by
   the detected-star ratio*:
   `Number1 = Number_of_main_star * NUMBER2 / NUMBER3` (`ident_lib.c:~2263`), with
   the comment "if we have more stars on one frame than on the other - it is
   likely that this frame is just taken with a longer exposure". This is VaST's
   built-in first defence against depth differences (see Section 7.1). It is
   clamped to `>= MATCH_MIN_NUMBER_OF_REFERENCE_STARS` (100) and to availability.

---

## 3. The algorithm, step by step

VaST uses the classical **similar-triangle** approach (in the lineage of
Groth 1986 / Valdes et al. 1995 / Pal & Bakos 2006): triangles of stars are
rotation-, translation-, and scale-invariant up to their side-length *ratios*,
so a triangle on one image can be matched to its counterpart on the other without
knowing the transform in advance; a set of matched triangles then votes for the
geometric transformation.

### 3.1 Triangle construction - `Separate_to_triangles()` (`ident_lib.c:314`)

For each star, **11 triangles** are built (`TRIANGLES_PER_STAR = 11`), using two
complementary strategies:

- **One "small" triangle from the 3 nearest neighbours**
  (`Create_One_Triangle_from_Nearby_Stars`, `ident_lib.c:211`): star *n* plus its
  closest and second-closest neighbours. This produces small, local triangles
  spread across the field. Run only when `NUMBER < 700`
  (`MATCH_MAX_NUMBER_OF_STARS_FOR_SMALL_TRIANGLES`) because the nearest-neighbour
  search is O(N) per star.
- **Ten "brightness-neighbour" triangles**: because the list is magnitude-sorted,
  stars at indices *n, n+1, ... n+5* have *similar brightness*. The code enumerates
  10 combinations - `(n,n+1,n+2), (n,n+1,n+3), (n,n+2,n+3), (n,n+1,n+4),
  (n,n+2,n+4), (n,n+3,n+4), (n,n+1,n+5), (n,n+2,n+5), (n,n+3,n+5), (n,n+4,n+5)` -
  giving large triangles spanning the field but anchored on stars of comparable
  magnitude. (`1 + 1 + 2 + 3 + 4 = 11`.)

**Descriptor** (`Compute_sides_of_triangles`, `ident_lib.c:285`): each triangle
stores its three side lengths as **squared** pixel distances `ab, bc, ac`, plus
their product `ab_bc_ac = ab*bc*ac`. The product is `(linear scale)^6` and serves
as a fast overall-size key. There is **no active minimum/maximum triangle-size or
"thin-triangle" rejection** - those guards exist but are commented out
(`ident_lib.c:223-224` etc.), and the descriptor is *not* the fully
scale-invariant (ratio, ratio) pair used by some implementations; scale is instead
gated globally (next step).

### 3.2 Similarity search - `Podobie()` (`ident_lib.c:549`; "podobie" = similarity)

Brute-force O(Nt1 x Nt2) over all triangle pairs (the code notes that sorting +
binary search was tried and did not help because of qsort overhead, `:545`):

1. **Overall-scale gate:** `podobie = ab_bc_ac(tr1) / ab_bc_ac(tr2)`; accept only
   if `|podobie - 1| < MAX_SCALE_FACTOR` (`= 0.05`). Since `ab_bc_ac` is scale^6,
   this admits pairs whose linear scale agrees to ~+/-0.8%.
2. **Per-side match:** for each of the **6 vertex permutations**, require both
   `(ab1/ab2)^3 ~ podobie` and `(bc1/bc2)^3 ~ podobie` to within
   `sigma_podobia` (`= 0.01`, relaxed to `0.02` for <10-star frames). A pass
   records the specific vertex-to-vertex correspondence via `Add_ecv_triangles()`
   - i.e. a **vote** for "star tr1.a[i] is the same star as tr2.a[j]".

The output is `ecv_tr`, a list of candidate matched-triangle pairs, each carrying
a concrete three-star correspondence hypothesis.

### 3.3 Consensus / RANSAC - `Very_Well_triangle()` (`ident_lib.c:799`)

For up to `Number_of_ecv_triangle` (default 100) candidate triangle pairs:

1. **Compute a transform from one triangle pair**
   (`Star2_to_star1_on_main_triangle`, `ident_lib.c:911`). Three point
   correspondences determine an exact **6-parameter affine**: translate the
   triangle-2 anchor to the origin, solve the 2x2 linear matrix `line[0..3]` from
   the two edge vectors, translate onto the triangle-1 anchor. Rotation angle
   `fi = atan2(-line[1], line[0])`.
2. **Apply it to all STAR2** (`Translate` / `Line_Preobr` / `Translate`) and
   **count how many stars land within `sigma_popadaniya` of a reference star**
   (`Popadanie_star1_to_star2__with_mean_distance`).
3. **Guards:** reject the candidate if `--norotation` is set and the implied
   rotation exceeds `MAX_NOROTATION_ANGLE_RAD` (15 deg), and reject *degenerate*
   transforms via a minimum-area-per-star test
   (`Ploshad1/Number2 < (sigma_popadaniya_multiple * sigma_popadaniya)^2`,
   `sigma_popadaniya_multiple = 3.0`) - this stops a collapsed transform from
   making everything spuriously "match".
4. **Keep the candidate with the most matched stars**, ties broken by smallest
   mean residual distance.

This is textbook RANSAC: each triangle-match is a minimal hypothesis, and the one
with the largest positional-consensus wins. **The whole field is described by a
single global affine.**

### 3.4 Match expansion - the live `Ident_on_sigma()` (`ident_lib.c:1295`)

Under the winning transform, build the full matched-star list. The live version
(four older variants are `/* */`-commented out) uses a **uniform spatial grid**
(`createGrid`, ~1 star per cell, +/-1 cell search, `STAR_MATCH_GRID_PADDING_PIXELS
= 128` margin) so neighbour lookup is ~O(N) rather than O(N^2). A pair is accepted
when the squared separation `R < sigma_popadaniya^2`. An **ambiguity filter**
discards the whole solution if too many new-frame stars claim the same reference
star (`fraction > MAX_FRACTION_OF_AMBIGUOUS_MATCHES = 0.05` **and** count `> 5`).

### 3.5 Residual refinement (`Ident()`, `ident_lib.c:2409-2585`)

After the initial match, VaST tries to remove systematic residuals - but only to
**first order**. It fits two planes by least squares (`fit_plane_lin`,
`z = A*x + B*y + C`):

```
dx = Ax*x_frame + Bx*y_frame + Cx
dy = Ay*x_frame + By*y_frame + Cy
```

applies the correction to *all* new-frame stars, re-matches, and iterates this
**3 times**. Moving objects are excluded from the fit. Because `dx, dy` are linear
in position, this is an affine correction on top of the affine transform - it can
absorb a residual linear tilt/skew but **cannot represent any curvature** (radial
distortion, differential refraction, higher-order optical distortion).

### 3.6 Acceptance, retry, and failure handling (`vast.c`)

- **Positional tolerance `sigma_popadaniya`** is fixed per image: default
  `0.6 * aperture` (`AUTO_SIGMA_POPADANIYA_COEF = 0.6`), or the user value from
  `--starmatchraius` (3.5 px in the Cas-03 run). **It is never widened on
  failure.**
- **Retry cascade** (`vast.c:3714-4040`, capped at `MAX_MATCH_TRIALS = 5`): on a
  failed match, VaST only varies *how many* bright stars/triangles are used -
  doubling/halving `Number_of_main_star` and `Number_of_ecv_triangle`, sweeping
  from `MATCH_MIN..MAX_NUMBER_OF_REFERENCE_STARS` (100..3000) in steps of 500, and
  a special "focus change/saturation" test that *excludes the brightest N stars*
  from whichever frame saturated them.
- **Acceptance gate:** a frame is kept only if matched stars
  `>= MIN_FRACTION_OF_MATCHED_STARS * min(NUMBER3, NUMBER2)`
  (`MIN_FRACTION_OF_MATCHED_STARS = 0.20`, deliberately lowered from 0.41 to
  tolerate small overlaps).
- **On failure** the frame is dropped: `status=ERROR` is logged, the frame
  contributes **no lightcurve points**, and the run continues. It is *not* added
  to a persistent bad-image list. (A separate `mark_images_with_elongated_stars_as_bad`
  path exists but is independent of the triangle match.)

---

## 4. Parameter reference (matching-critical, high to low)

| Parameter | Value | Location | Role |
|---|---|---|---|
| `sigma_popadaniya` | `0.6*aperture` (auto) / user (`--starmatchraius`) | `vast.c:2662,3350,2305` | positional match radius; accept if `R^2 < r^2`; **never widened on retry** |
| `AUTO_SIGMA_POPADANIYA_COEF` | `0.6` | `vast_limits.h:50` | auto radius = coef x aperture |
| `sigma_podobia` | `0.01` (`0.02` if <10 stars) | `ident_lib.c:84`; `vast.c:3711` | per-side triangle-similarity tolerance |
| `MAX_SCALE_FACTOR` | `0.05` | `vast_limits.h:203` | overall triangle-scale gate (~+/-0.8% linear) |
| `Number_of_main_star` | 100 default / `--matchstarnumber` | `ident_lib.c:90` | # brightest stars used to build triangles |
| `MATCH_MIN/MAX_NUMBER_OF_REFERENCE_STARS` | 100 / 3000 | `vast_limits.h:182,186` | floor/ceiling of that count across retries |
| `MATCH_REFERENCE_STARS_NUMBER_STEP` | 500 | `vast_limits.h:184` | retry sweep step |
| `TRIANGLES_PER_STAR` | 11 | `vast_limits.h:187` | triangles built per star |
| `MATCH_MAX_NUMBER_OF_STARS_FOR_SMALL_TRIANGLES` | 700 | `vast_limits.h:189` | below this, also build nearest-neighbour triangles |
| `Number_of_ecv_triangle` | 100 default | `ident_lib.c:85` | # candidate triangle pairs RANSAC scores |
| `sigma_popadaniya_multiple` | 3.0 | `ident_lib.c:87` | degeneracy/area guard in consensus |
| `MAX_NOROTATION_ANGLE_RAD` | 15 deg | `vast_limits.h:181` | `--norotation` cap |
| `MIN_FRACTION_OF_MATCHED_STARS` | 0.20 | `vast_limits.h:176` | min matched fraction to accept a frame |
| `MAX_FRACTION_OF_AMBIGUOUS_MATCHES` / count | 0.05 / 5 | `vast_limits.h:172,173` | reject solution if too many many-to-one matches |
| `MAX_MATCH_TRIALS` | 5 | `vast_limits.h:175` | retry-loop cap |
| `STAR_MATCH_GRID_PADDING_PIXELS` | 128 | `vast_limits.h:51` | grid margin for out-of-frame stars |

**Model:** 6-DOF global affine from one best triangle, refined by 3 iterations of a
first-order residual-plane fit. Linear throughout; no higher-order distortion,
no local/tiled solution.

---

## 5. Complexity / performance profile

Let `N` = stars used (`Number_of_main_star`), `Nt ~ 11N` = triangles, `E` =
candidate triangle pairs (`Number_of_ecv_triangle`).

- Triangle construction: O(N) (plus O(N^2) nearest-neighbour when `N < 700`).
- **`Podobie` similarity: O(Nt1 x Nt2) ~ O((11N)^2)** - the dominant cost as N grows.
- **`Very_Well_triangle` consensus: O(E x N1 x N2)** - for each of E candidates it
  applies the transform and scores by **brute-force** positional match (this inner
  count does **not** use the grid, unlike the final `Ident_on_sigma`).
- Final expansion `Ident_on_sigma`: ~O(N) via the grid.

So the two hot spots are the O(N^2) triangle-similarity double loop and the
E-times brute-force consensus scoring. Both are addressable (Section 8).

---

## 6. Strengths (what the design gets right)

- **Invariant matching without a prior guess** - the classic triangle method is
  robust to arbitrary translation, rotation, and modest scale change, which is
  exactly what you want for uncalibrated frames.
- **Brightest-first + count cap + ratio scaling** already targets the bright stars
  common to both frames, the single most important trick for cross-depth matching.
- **RANSAC consensus** with a degeneracy guard is inherently robust to a large
  fraction of wrong triangle votes.
- **Ambiguity rejection** and the **mutual-proximity/uniqueness** acceptance guard
  the crowded-field case where several stars fall inside one match radius.
- **Grid-accelerated** final matching keeps the common path near-linear.
- **Tolerant acceptance (0.20)** lets partially-overlapping frames still register,
  which is valuable for the wide-field NMW pointing jitter.

---

## 7. Failure modes and how to reduce them

### 7.1 New image much shallower than the reference

**A correction on magnitudes (this matters).** Before matching *and* before
magnitude calibration, the two frames are on **different photometric zero-points**
- the instrumental magnitudes from SExtractor differ by the (unknown) relative
zero-point of the two exposures. So the magnitude *values* cannot be compared
across frames; only the *rank* can. Crucially, **a shallower image does not break
the rank**: a monotonic zero-point offset preserves order, so the brightest star is
still the brightest on both frames. The shallow frame simply *truncates* the list -
its faint stars fall below the detection limit - it does not reshuffle the bright
end. (An earlier draft of this document wrongly suggested truncating both lists "at
a common limiting magnitude"; there is no common magnitude scale at this stage, so
that idea is withdrawn. The right invariant is rank, not magnitude.)

**What this means for the algorithm.** Because rank is preserved, the correct way to
handle a depth difference is to compare the two lists **by rank** - use the brightest
*N* of each, where *N* is small enough to stay above the shallow frame's limit. This
is exactly what VaST already does: brightest-first sort + `Number_of_main_star` cap
+ `Number1 = Number_of_main_star * NUMBER2/NUMBER3`, which shrinks the reference set
toward the shallow frame's count. In the reproduced Cas-03 case the new frames are
~2x shallower (~14.4k vs ~31.4k detections) and VaST correctly used only ~230 of the
requested 500 reference stars, matching ~97-99%. **So the shallow case is largely a
solved problem in VaST**, and the residual weakness is narrow:

- Near the *faint end of the truncated list*, photon noise perturbs the ordering,
  so two stars of nearly equal brightness can swap rank between frames. The
  "brightness-neighbour" triangles (indices `n..n+5`) built right at that boundary
  can then join slightly different physical stars. This is a small, edge-of-list
  effect, not a wholesale rank scramble.

**Improvements (small, and secondary to the transform work below):**

1. **Keep the matching count comfortably above the shallow limit.** The failure
   above only bites if *N* reaches into the noisy faint tail of the shallow frame.
   A depth-aware cap - reduce the effective `Number_of_main_star` when the detected
   counts differ a lot (large `NUMBER3/NUMBER2`) - keeps the matched set in the
   rank-stable regime. The `NUMBER2/NUMBER3` scaling already approximates this;
   making it a touch more conservative when the ratio is extreme is the whole fix.
2. **Lean on the nearest-neighbour (small) triangles for shallow frames.** Those are
   built from spatial proximity, not magnitude rank, so they are immune to
   faint-end rank reshuffling - but they are only enabled below 700 stars. Allowing
   them (to *seed* the transform) when a large depth ratio is detected adds
   rank-independent constraints. (Care: local triangles are more ambiguous in
   crowded fields; use them to seed, then expand.)
3. **Do not chase faint-end matches at all.** The transient search only needs a
   good geometric transform, which the bright common stars already provide; there
   is no benefit to reaching for marginal faint matches that a shallow frame cannot
   support. The real leverage for shallow *wide-field low-altitude* frames is
   getting the transform right where stars *are* present (Sections 7.2-7.3), not
   squeezing more matches out of the faint tail.

### 7.2 Getting the best possible LINEAR transform first (before any non-linear step)

This is the right priority: a non-linear model layered on a mediocre linear fit
inherits its biases and adds instability. Two properties decide linear-fit quality -
**how the fit is computed** and **which stars constrain it**.

**How it is computed today.** The base affine comes from a *single* triangle (3
points); the refinement then least-squares-fits a first-order residual plane over
*all* matched stars and re-matches, 3 times (Section 3.5). Iterating the plane fit
does converge toward the least-squares affine, but it is (a) seeded by one triangle,
(b) **unweighted** - every matched star counts equally - and (c) not explicitly a
single robust affine solve. Improvements:

1. **Replace triangle-seed + plane-correction with an explicit robust affine
   least-squares** over all inliers, with iterative sigma-clipping (reject
   >N-sigma residual pairs - mismatches or real movers - then refit). This yields
   the provably-best 6-parameter linear transform and cleanly separates "find the
   transform" from "reject outliers". It is cheap (a 6x6 normal-equation solve).
2. **Weight/uniformise the fit spatially.** This directly answers *"can we make
   sure enough well-distributed stars are used?"* - and it is not hypothetical here.
   In the reproduced Cas-03 field the matched stars are strongly **non-uniform**: a
   3x3 spatial binning gives ~13,200 matched stars in the top third of the frame vs
   ~6,646 in the bottom third - a **~2:1 density gradient** (consistent with the
   low-altitude side losing faint stars to extinction). An unweighted least-squares
   fit is therefore pulled ~2x harder by the dense side, so the sparse side - where
   distortion is *worst* - is the *least* constrained. Fixes:
   - **Per-cell brightest-K selection** instead of global brightest-N: tile the
     frame into a coarse grid and take the brightest ~K stars *per cell*. This
     guarantees the sparse/low-altitude side contributes constraints even though its
     stars are globally fainter - the single most effective change for well-behaved
     wide-field fits.
   - **Inverse-local-density weighting** in the least-squares fit, so a star in a
     dense region counts less than a star in a sparse region.
3. **Require and report spatial coverage.** Before trusting the transform, check
   that inliers span the frame (e.g. >=1 well-populated cell per quadrant, or a
   convex-hull area above a threshold). If a side is empty, the transform there is
   *extrapolation* - flag it rather than silently trusting it. This is also the gate
   that decides whether a non-linear term is even admissible (Section 7.3).

Getting these right typically removes most edge residuals on their own, because much
of what looks like "distortion" at the edges of a poorly-fit frame is actually a
**tilted/biased affine** from a centre-heavy star sample. Only the residual that
survives a well-distributed robust affine is true non-linear distortion.

### 7.3 Distortion - atmospheric refraction / low altitude / optical field distortion

**Prerequisite: fix the linear transform first (Section 7.2).** Do not reach for a
non-linear model until the linear fit is robust and spatially balanced. Much of the
apparent "distortion" at frame edges is really a biased affine from a centre-heavy
star sample; only the residual that survives a well-distributed robust affine is
genuine non-linear distortion. Everything below assumes 7.2 is in place.

**The genuine non-linear limitation.** Once the affine is as good as it can be, a
real residual remains for wide-field frames, because real distortions are **not**
affine:

- **Optical field distortion** of a fast wide-field lens is predominantly radial
  (barrel/pincushion), i.e. a displacement that grows as r^2/r^3 from the optical
  axis.
- **Differential atmospheric refraction** compresses the field toward the horizon;
  at low altitude the compression is large and varies non-linearly across a
  multi-degree field, and its axis (the parallactic direction) is not aligned with
  the detector axes and rotates through the night.

An affine transform (plus a linear residual plane) can match the *centre* of such a
field well, but the residuals grow toward the edges. Once the edge residual exceeds
`sigma_popadaniya` (0.6 x aperture, ~a few pixels), those stars **fail to match**.
The consequences for transient search:

- Edge stars appear only on one epoch -> spurious "appeared/disappeared" candidates
  clustered near the frame edges.
- Correctly-matched central stars can still carry a small systematic astrometric
  offset that leaks into photometry via aperture centring.
- Only in a severe case does the global match fraction fall below the 0.20 gate and
  drop the *whole frame*; the common damage is per-star, at the edges.

**Empirical grounding - the Cas-03 case (reproduced).** The Cas-03 field (Dec +59
deg, imaged from Texas at ~01 UTC in July) sits low in the north - a textbook
differential-refraction case. Re-running the exact pipeline command on those images
shows the match did **not** collapse globally:

```
reference frame:  31359 detected, 29166 matched  (~93%)
new frame 1:      14476 detected, using 231/500 reference stars, 13988 matched (~97%)
new frame 2:      14389 detected, using 230/500 reference stars, 14354 matched (~99.8%)
```

Two things stand out. (1) The new frames are **~2x shallower** than the reference
(~14.4k vs ~31.4k detected stars), and VaST's depth heuristic engaged correctly -
it used only ~230 of the requested 500 reference stars (`Number_of_main_star *
NUMBER2/NUMBER3`), so the shallow-image adaptation of Section 7.1 is *working*.
(2) The match still leaves a residual ~3% of new-frame stars (and, more importantly,
many bright reference stars near the edges) unmatched. **Those few-percent per-star
failures - not a whole-frame drop - are what generate the problematic candidates**
that forced photometry must then vet. This is exactly why the problem is easy to
miss: the summary says "Success!" and 97-99% matched, while the residual
distortion-driven edge mismatches quietly seed false candidates. A second-order
residual model (below) targets precisely that residual few percent; the whole-frame
0.20 gate is not the binding constraint here.

**The stability worry is the right worry.** A higher-order model can *reduce* edge
residuals or *blow them up*, depending entirely on whether the data constrain it
where it is applied. This is not hypothetical for VaST: it is the exact lesson of
`util/solve_plate_with_best_sip_order.sh`, which exists because SIP order 3
*over-fits* low-distortion fields and has to be dropped to order 2. The same
discipline must apply here. Two concrete failure conditions:

- **Extrapolation into empty regions.** A 2nd-order 2D polynomial has 6 coefficients
  per axis. Fit it on a star sample that is dense on one side and sparse on the
  other (the Cas-03 ~2:1 gradient, Section 7.2) and it is well-pinned on the dense
  side but *unconstrained* on the sparse side - where it will happily produce a
  large, wrong correction (Runge/extrapolation behaviour). That is precisely the
  low-altitude edge where you most need it to be right, so a naive quadratic can
  make matching **worse** there than the affine.
- **"Enough stars" is about distribution, not count.** *Is ~230 stars enough for a
  non-linear fit?* In raw count, yes - 230 >> the 12 coefficients. But count is the
  wrong question: 230 stars clustered on the dense half constrain the polynomial no
  better at the sparse edge than 12 would. A quadratic needs stars **spanning the
  field, including the corners**. So 230 *well-distributed* stars are ample; 230
  *centre-heavy* stars are dangerous.

**Improvements (most effective first), all built to be stable:**

1. **Add a second-order (or radial) residual term, but choose the order
   adaptively.** Fit `dx = a0 + a1*x + a2*y + a3*x^2 + a4*xy + a5*y^2` (and likewise
   `dy`) as a *candidate*, and accept it over the linear fit only if it improves
   **held-out** residuals (fit on a random half of the matched stars, evaluate on
   the other half; keep the higher order only if the out-of-sample scatter drops).
   This is exactly the cross-validation philosophy of the SIP-order chooser and is
   what prevents over-fitting. Default to linear; escalate only when the data pay
   for it. A radial form `dr = k1*r^2 + k2*r^3` about a fitted centre is the most
   parsimonious model for pure optical distortion and the safest first non-linear
   step (2 parameters, not 12).
2. **Gate the non-linear step on spatial coverage.** Only admit a quadratic if
   matched inliers populate all field regions (e.g. every cell of a 3x3 or 4x4 grid
   above a minimum count, and corners represented). If coverage is one-sided, stay
   linear on the empty side - never extrapolate a polynomial into a region with no
   stars. Report when this happens.
3. **Bound and regularise the correction.** Reject (or damp) any non-linear solution
   whose implied pixel correction exceeds a sane cap anywhere in the *populated*
   frame, and prefer a small ridge/Tikhonov penalty so sparse-side coefficients
   relax toward zero rather than swinging wild. Iterate with sigma-clipping (reject
   >N-sigma pairs - mismatches or real movers - and refit) so a few bad pairs cannot
   define the distortion.
4. **Local / tiled affine as an alternative to a global polynomial.** Divide the
   frame into a coarse grid, solve a local affine per *populated* tile (seeded by
   the global affine), and match each star with its local transform. This handles
   arbitrary smooth distortion and *degrades gracefully*: an empty tile simply
   inherits the global affine instead of extrapolating. It is often more robust than
   a global polynomial for exactly the imbalanced-coverage case.
5. **Distortion-aware acceptance and logging.** Compute the match fraction and mean
   residual *per field region*. A "centre fine, edges bad" pattern is a distortion
   signature: log it, and prefer to accept the frame with edge stars flagged rather
   than drop the whole frame at the 0.20 gate. This turns a silent per-star failure
   into a visible, diagnosable one.

**Net answer on non-linear stability:** it is safe *iff* it is adaptive
(cross-validated order), coverage-gated (no extrapolation), and bounded/regularised
- and it should always sit on top of the best linear fit (7.2), never replace it.
The linear model is inherently stable (an affine cannot diverge; it is bounded by
the data span), which is why "nail the linear first" is the correct instinct.

### 7.4 False matches (wrong star matched, or spurious transform accepted)

**What the live matcher actually does** (`Ident_on_sigma`, `ident_lib.c:1295-1474`),
because the fixes depend on it:

- Matching is **asymmetric, new -> reference**: for each new-frame star it searches
  the grid neighbourhood and keeps the **nearest** reference star within
  `sigma_popadaniya` (`R_best` starts at the radius squared, line 1337; it is
  *nearest*, not first-within-radius).
- The **isolation / de-blend guard is commented out** (line 1373): the intended
  extra condition `R < star1.distance_to_neighbor_squared &&
  R < star2.distance_to_neighbor_squared` (accept only if the pair is closer to each
  other than either is to its own nearest neighbour) is disabled in the live path.
- **Mutual-nearest-neighbour (MNN) is not enforced** in the live path - an MNN
  variant of `Ident_on_sigma` exists but is one of the `/* */`-commented copies.
- When two new stars claim the same reference star, the conflict is resolved
  **first-come-first-served, not by best distance**; the loser is dropped as
  "ambiguous". The source itself flags this as suboptimal ("WHY DO YOU THINK THE
  PREVIOUS MATCH IS THE BETTER ONE?", `ident_lib.c:1427-1431`).

**The specific failure mode you asked about** - a faint star on the deep reference
getting matched to a nearby bright star on the new image - is a direct consequence:

Let A be a faint reference star at position pA and B a bright star at pB, with pA and
pB closer together than `sigma_popadaniya`. On a shallow new frame A is often absent
(below the limit), so only B is detected, near pB. Matching is new -> reference, so
new-B looks for its nearest reference star. If the transform were perfect, that is
reference-B (near-zero distance) and all is well. **But if a residual offset displaces
reference-B's predicted position** - because of un-modelled distortion (Section 7.3),
a centre-biased affine (Section 7.2), or simply the larger centroid error of a
shallow-frame detection - **the nearest reference star to new-B can become faint
reference-A instead of bright reference-B.** Then:

- Reference-A (faint) is paired with new-B (bright) -> A appears to have brightened
  by many magnitudes -> a **false "new/brightened" candidate**.
- Bright reference-B, having lost its rightful partner, is claimed by no new star ->
  it appears to have **disappeared** -> a second false candidate. (If another new
  detection sits near pB, B may instead be mis-paired further, propagating the
  error.)

So one positional slip near a close faint/bright pair produces *two* spurious
candidates, and the shallow frame makes it more likely (A absent, B's centroid
noisier). This is the mechanism the forced-photometry cross-check is designed to
catch downstream - but it is far cheaper to prevent.

**How to minimise it (most effective first):**

1. **Get the transform right (Sections 7.2-7.3).** This is the root cause: with
   small residuals, new-B's nearest reference star is reliably bright reference-B,
   not a faint neighbour. Better linear distribution + adaptive distortion directly
   shrink this mode. Everything else below is a safety net on top.
2. **Enforce mutual nearest neighbour.** Accept A<->B only if B is A's nearest *and*
   A is B's nearest. Bright reference-B's nearest new star is new-B, so MNN rejects
   the new-B -> faint-reference-A pairing outright. VaST already has an MNN
   implementation (currently commented out); re-enabling/adapting it is the most
   targeted fix for this exact mode.
3. **Re-enable the isolation guard** (`R < distance_to_neighbor_squared`, line 1373).
   Because A and B are close, the guard fails for the A-B pairing and the ambiguous
   match is refused rather than accepted wrongly. Trade-off: genuinely crowded stars
   (closer than the match radius) will not match - but those are unreliable anyway,
   and for transient search a missed crowded star is safer than a false candidate.
4. **Resolve many-to-one by best distance, not first-come.** When several new stars
   claim one reference star, keep the nearest and re-queue the others; this alone
   removes a class of arbitrary mis-assignments the code comment already distrusts.
5. **Two-stage tolerance.** Find the transform with a generous `sigma_popadaniya`,
   then finalise pairs with a *tight* radius so distinct A and B are not both inside
   it. (Note `sigma_popadaniya` is currently fixed per image and never tightened.)
6. **Brightness-rank sanity (not magnitude value).** Since the two frames have
   different zero-points (Section 7.1), brightness *values* are not comparable, but
   *rank* is. Flag or de-prioritise a match that pairs a high-rank (bright) new star
   with a low-rank (faint) reference star when a better-ranked reference star sits
   nearby - a rank inversion is a red flag for exactly this mode.

**Two field-independent gates that also cut false matches:**

- **Statistical (density-based) acceptance** instead of the fixed 0.20 fraction. In
  sparse/shallow fields, 20% of a small N can be reached by chance under a wrong
  affine. Compare the achieved match count against the number expected from random
  alignment (~ `N1 * N2 * pi * r^2 / field_area`) and require it to exceed that by
  many sigma - a scale-free gate that a fixed fraction cannot provide.
- **Consensus depth.** Only `Number_of_ecv_triangle = 100` candidate triangles are
  scored; in a hard field the true one may rank beyond 100. Raising it (as
  `--matchstarnumber` already does) or ranking candidates by descriptor quality
  before scoring reduces missed-but-present solutions.

### 7.5 Sparse and crowded extremes

- **Very sparse** (few stars, e.g. through cloud): few triangles, weak consensus,
  and the fixed-fraction gate is easily fooled -> the statistical gate above helps.
- **Very crowded** (galactic plane): many stars within a match radius -> the
  ambiguity/uniqueness guards are essential; a tighter final `sigma_popadaniya`
  and mutual matching reduce cross-pairing.

---

## 8. Speed-up opportunities (secondary to quality, but real)

1. **Grid-accelerate the RANSAC scoring.** `Very_Well_triangle` scores each
   candidate transform by a brute-force O(N1 x N2) positional count. Reusing the
   same uniform grid the final `Ident_on_sigma` already builds would make each
   score ~O(N), turning O(E x N1 x N2) into ~O(E x N). This is the largest easy win
   for large N (e.g. `--matchstarnumber 500`).
2. **Bin/hash the triangle descriptors for `Podobie`.** Quantise the scale-invariant
   descriptor (e.g. the two side-length ratios) into a hash table and only compare
   triangles that fall in the same (or neighbouring) bin, turning O(Nt^2) into
   ~O(Nt). The code comment notes a *sort + binary search* attempt that didn't pay
   off due to qsort overhead - a hash avoids the sort entirely and is the standard
   fix (astrometry.net-style geometric hashing).
3. **RANSAC early-out.** Stop scoring candidates once one matches, say, >60% of
   stars - the true transform is found; the rest of the E loop is wasted work.
4. **Rank candidates before scoring.** Evaluate `ecv` candidates in order of
   triangle-descriptor agreement (best first) so the early-out fires sooner.

None of these change results; they only reduce runtime, which in turn makes it
affordable to *raise* `Number_of_main_star`/`Number_of_ecv_triangle` for quality.

---

## 9. Relationship to forced photometry (why fixing matching still matters)

Forced photometry (`src/forced_photometry.c`) measures flux at a **commanded pixel
position** derived from the candidate's mean RA/Dec via each image's **absolute WCS**
(`sky2xy` inverting the per-image UCAC5 plate solution). It performs **no triangle
cross-identification**. In `report_transient.sh` it runs for every 2-4 point
candidate and *rejects* the candidate unless the reference epoch is genuinely
fainter - so it **exposes and removes** matcher false positives (e.g. a reference
detection mis-associated with a nearby star) rather than hiding them.

But it is a downstream *filter on candidates*, not a cure:

- It only sees candidates that were *already produced*. Stars the matcher dropped
  (e.g. distortion-unmatched edge stars) never become candidates to be checked, so
  genuine transients near the edges can be lost before forced photometry ever runs.
- Every distortion-induced spurious candidate still costs a full plate-solve +
  forced-photometry cross-check per candidate - improving matching reduces that
  load directly.
- Better matching means cleaner lightcurves and photometric zero-points for *all*
  stars, not just the flagged candidates.

So the forced-photometry trick makes the pipeline *robust* to matcher failures, but
minimising those failures (Sections 7.1-7.4) improves completeness (fewer missed
transients), purity (fewer spurious candidates to vet), and cost.

---

## 10. Prioritised recommendations

For the wide-field transient use case, in order of expected impact-to-effort. The
ordering deliberately front-loads **getting the linear transform right**, because it
is both the largest single quality lever and the prerequisite for any non-linear step.

1. **Best possible linear transform, spatially balanced** (Section 7.2): an explicit
   robust affine least-squares with sigma-clipping, fed by a **per-cell brightest-K**
   star selection (not a global brightest-N) plus a spatial-coverage check. This
   fixes the ~2:1 density-gradient bias measured in the Cas-03 field and, on its own,
   removes much of what currently looks like edge "distortion". Prerequisite for #3.
2. **Mutual-nearest-neighbour + best-distance conflict resolution** in the final
   matching pass (Section 7.4): re-enable the MNN/isolation logic that already exists
   (commented out) and stop resolving many-to-one conflicts first-come-first-served.
   This is the targeted cure for the faint-reference / bright-new-star mis-match that
   generates paired false candidates.
3. **Adaptive, coverage-gated non-linear residual term** (Section 7.3): a radial or
   2nd-order correction accepted only when cross-validated held-out residuals improve
   and inliers cover the field - never extrapolated into empty regions. Sits on top
   of #1; captures true optical/refraction distortion without the over-fitting risk.
4. **Statistical (density-based) acceptance** replacing the fixed 0.20 fraction
   (Section 7.4) - fewer false accepts in sparse/shallow fields.
5. **Grid-accelerate RANSAC scoring** (Section 8.1) - makes it affordable to raise
   star/triangle counts, which itself improves robustness.

Items 1-2 target correctness of matches and reduction of false candidates most
directly (and are the "make the linear thing as good as possible" work); 3 adds the
non-linear capability *safely*; 4-5 harden the edges and the runtime. All are
compatible with the existing affine bootstrap and the forced-photometry safety net.

---

## 11. Step-by-step implementation and testing plan

The plan is built around one idea: **you cannot claim "improved, degraded nowhere"
without an objective, ground-truth quality metric**, so the first step builds the
measurement, and every later step is gated by it. Each step is a single,
independently useful, independently revertible change; if work stops after any step,
what shipped is still a net improvement.

### Guiding principles (apply to every step)

- **One change per step, one commit per step**, on a feature branch, so a regression
  can be `git bisect`-ed to the exact change.
- **Runtime toggle per new behaviour** (an environment variable, in the spirit of
  `VAST_TWEAK_ORDER`), defaulting to the *old* behaviour until the step passes. This
  lets you A/B the old and new paths on the *same binary and same inputs*, isolating
  the change from run-to-run and build-to-build noise. Flip the default to "new" only
  after the step passes; remove the toggle once the change is trusted.
- **"No degradation" is judged on precision/recall vs ground truth, not on raw match
  count.** This is the subtle, essential point: several steps *deliberately remove
  false matches*, which lowers the match count while improving quality. A count-only
  gate would wrongly block exactly the improvements we want. See Step 0.
- **Portability/style unchanged:** full `make` (never `make -j`), C89 declarations at
  the top of functions, `//` comments, ASCII only, no new dependencies; every step
  must still build on the reference-legacy toolchain (gcc 4.1 / SL 5.6) and the
  Alpine/musl, FreeBSD, macOS targets. The changes are all in `src/ident_lib.c` /
  `src/vast.c` and reuse the existing GSL fit helpers, so this is achievable.
- Keep the **forced-photometry safety net** in place throughout; it is the backstop
  while the matcher is being changed.

### Step 0 - Measurement harness and regression corpus (NO algorithm change)

Goal: be able to say, quantitatively, "matching got better here and worse nowhere."

Build:

1. **Ground-truth cross-match.** Every image already gets an absolute UCAC5 WCS
   solution (the one forced photometry uses). For an image pair, define the *true*
   correspondence independently of the triangle algorithm: a reference detection and
   a new detection are the same star iff their sky positions (RA/Dec via each image's
   own WCS) agree within a tolerance (~1-2 arcsec, comfortably larger than the
   pixel-level effect under test). `lib/bin/xy2sky` on each `.cat` gives the sky
   positions; a short script produces the truth pairing.
2. **Extract VaST's frame-to-frame matched pairs.** Reconstruct (reference x,y <->
   new x,y) from the lightcurve files (`outNNNN.dat`, keyed by reference-frame
   position) joined with the per-image SExtractor catalogs; or add a *test-only*,
   off-by-default dump of `Pos1`/`Pos2` to a file for convenience.
3. **Score:** true positives (VaST-matched and same sky position), false positives
   (VaST-matched but *different* sky positions - the mis-matches, including the
   faint/bright mode of Section 7.4), false negatives (same sky position present in
   both but not matched). Report **precision, recall, false-match count**, matched
   count, residual scatter, and the end-to-end spurious-candidate count.
4. **Regression corpus:** a fixed set of ~6 real image pairs with recorded baselines,
   one per failure regime - easy/high-altitude/similar-depth (the *invariance
   control*), shallow (Cas-03 ~2x depth), low-altitude/distortion, crowded (reuse the
   in-repo `NMW_Sgr9_crash_test` case referenced in `ident_lib.c:1460`), sparse/cloudy,
   and large-offset (the case the 0.20 gate was lowered for).
5. **Synthetic generator (deterministic):** from one real star list, apply a *known*
   transform (pure affine; affine + radial distortion; + shift/rotation), optionally
   drop the faintest X% (shallow), add centroid noise and spurious detections. Truth
   is exact, so this is the fast per-step gate with zero real-data ambiguity.

Test of the harness itself: it must score a known-correct synthetic match at ~100%
precision/recall and a deliberately corrupted one lower, and reproduce the Cas-03
numbers already observed (97-99% matched, ~2:1 spatial gradient). Nothing in the
matcher changed, so degradation is impossible - this step only enables the rest.

### Standard per-step test protocol (run after EVERY step below)

1. **Build & static checks:** full `make`; `gcc -fsyntax-only -I src` on changed C;
   `shellcheck` on changed scripts; confirm the link still succeeds.
2. **Synthetic suite (seconds):** precision/recall/transform-error on the controlled
   cases; require the *targeted* case to improve and every other case to hold.
3. **Corpus (real images):** re-run all pairs; compare to the recorded baseline:
   - **Invariance control (easy field):** the matched-pair set must be essentially
     unchanged (>99.9% identical) for any step not intended to touch it. Divergence
     here is a red flag, investigated before proceeding.
   - **Targeted field(s):** precision up and/or recall up, as the step intends.
   - **No-degradation rule:** for *every* field, precision must not fall (beyond a
     small epsilon). Recall/match-count may fall *only* if fully accounted for by
     removed false matches (i.e. precision rises correspondingly); a recall drop with
     flat precision is a regression and blocks the step.
   - **End-to-end:** spurious transient-candidate count on 1-2 real fields must not
     rise; frames currently accepted must not start being dropped (unless correctly
     rejected).
4. **A/B via the toggle:** old vs new on the same binary and corpus, to attribute the
   delta to this step alone.
5. **Commit** the step by itself; update the recorded baseline only after it passes.

### Step 1 - Best linear transform, part A: explicit robust affine least-squares

Change: after the RANSAC bootstrap, replace the "iterated first-order residual plane"
refinement (Section 3.5) with a single explicit **6-parameter affine least-squares
over all inliers with sigma-clipping** (fit, reject >N-sigma pairs, refit). Keep the
triangle bootstrap that *finds* the transform untouched - only the refinement changes.
Risk: low (mathematically this should equal-or-beat the iterated plane). 
Improve-test: residual scatter drops on imbalanced fields; matched count holds.
No-regression: easy-field invariance; precision never falls. Rollback: toggle off.

### Step 2 - Best linear transform, part B: spatial uniformity of the fit

Change: feed the Step-1 least-squares fit a **per-cell brightest-K** inlier selection
(tile the frame, take the brightest ~K per cell) plus optional inverse-local-density
weighting, so the ~2:1 dense/sparse gradient no longer biases the affine. **Keep the
global brightest-N for the RANSAC bootstrap** - only the final fit is uniformised, so
the transform-finding step is unchanged and low-risk.
Improve-test: on the low-altitude/gradient field, residual on the *sparse* side drops
and edge recall rises. No-regression: easy field unchanged; no precision drop anywhere.

### Step 3 - Spatial-coverage check and logging (diagnostic only)

Change: compute and log per-region match fraction and residual; flag one-sided
coverage. No effect on accepted matches (pure instrumentation).
Test: it correctly flags the imbalanced field; matched-pair sets are byte-identical to
Step 2 on every corpus field (this step must change *nothing* but the logs). This gate
also becomes the precondition that Step 9 reads.

### Step 4 - Best-distance conflict resolution (replace first-come-first-served)

Change: in `Ident_on_sigma`, when several new stars claim one reference star, keep the
**nearest** and re-queue the rest, instead of first-come-first-served
(`ident_lib.c:1403-1437`). Trivially more correct; the source comment already
distrusts the current behaviour.
Improve-test: false-match count drops (esp. crowded/faint-bright field); recall holds
or rises. No-regression: precision up, never down; easy field ~unchanged.

### Step 5 - Mutual nearest neighbour (MNN)

Change: accept A<->B only if each is the other's nearest within radius (adapt the
existing commented-out MNN variant). This is the targeted cure for the
faint-reference/bright-new mis-match (Section 7.4): bright reference-B is new-B's
nearest, so MNN rejects the faint-A pairing.
Risk: medium - may reduce matches in genuinely crowded regions. Improve-test:
false-match count drops sharply on the crowded and shallow fields. No-regression:
watch recall on the crowded field - a recall drop is acceptable ONLY if precision
rises to match (removed pairs were false); if recall drops with flat precision, keep
MNN behind the toggle and do not flip the default.

### Step 6 - Isolation guard (re-enable, tunable)

Change: re-enable the disabled `R < distance_to_neighbor_squared` guard
(`ident_lib.c:1373`), as a tunable (scale factor) defaulting to a conservative value.
Risk: medium-high (drops genuinely crowded matches). Improve-test: further
false-match reduction. No-regression: this is the step most likely to cost recall;
tune the scale so precision rises without a net recall loss on the corpus, and leave
it default-off if the crowded field cannot tolerate it. Fully optional.

### Step 7 - Two-stage match tolerance

Change: find the transform with the current (generous) `sigma_popadaniya`, then
finalise pairs with a *tighter* radius so distinct close stars are not both in range.
Improve-test: false-match count drops on crowded/faint-bright fields. No-regression:
recall on well-separated fields unchanged (tightening only bites where stars are
closer than the loose radius).

### Step 8 - Statistical (density-based) acceptance gate (additive)

Change: alongside the fixed 0.20 fraction, require the matched count to exceed the
random-coincidence expectation (~ `N1*N2*pi*r^2/area`) by many sigma. Additive - it
can only *reject* spurious accepts, never invent them.
Improve-test: a deliberately mis-solved sparse field is now rejected. No-regression:
every corpus field that currently passes *correctly* still passes (verify each).

### Step 9 - Adaptive non-linear distortion term (LAST, most guarded)

Change: add a radial (`dr = k1*r^2 + k2*r^3`) or 2nd-order residual term as a
*candidate*, accepted over the linear fit **only if cross-validated held-out residuals
improve** (fit on a random half, evaluate on the other half) **and** Step-3 coverage
is adequate; otherwise fall back to linear. Bound/regularise the correction; never
extrapolate into empty regions.
Risk: highest - hence last and heavily gated. Improve-test: on the low-altitude/
distortion field, edge recall rises and residual drops. **No-regression (the decisive
one):** on the low-distortion/easy fields the cross-validation gate must *choose
linear*, leaving those fields bit-for-bit identical to Step 8. Verify explicitly that
no easy/low-distortion corpus field changes. This gate is what makes non-linear safe.

### Step 10 - Speed-ups (result-neutral; anytime after Step 0)

Change: grid-accelerate the RANSAC scoring in `Very_Well_triangle`; optionally hash
the triangle descriptors in `Podobie` (Section 8). These must not change *which* stars
match. Test: the matched-pair set is identical (or >99.9% identical) to the pre-change
run on every corpus field, at lower wall-clock. Any change in the match set means a
logic bug, not a speed-up - block until identical.

### Ordering rationale and stop points

Steps 1-3 (best linear transform) come first: highest leverage, and a prerequisite
for Step 9. Steps 4-7 (robust final matching) remove the false-match modes and are
low-to-medium risk. Step 8 (acceptance) is purely protective. Step 9 (non-linear) is
last because it is riskiest and depends on 1-3. Step 10 is orthogonal. Natural
stopping points where the result is already a clear net win: after Step 3 (edges
better constrained), after Step 5 (false matches largely gone), or after Step 8
(robust everywhere) - the non-linear Step 9 is optional polish for the hardest
low-altitude frames.

---

## Appendix: key source locations

- `src/ident_lib.c` - `Separate_to_triangles` (314), `Create_One_Triangle_from_Nearby_Stars` (211),
  `Compute_sides_of_triangles` (285), `Podobie` (549), `Very_Well_triangle` (799),
  `Star2_to_star1_on_main_triangle` (911, the affine solve), live `Ident_on_sigma` (1295),
  grid (`createGrid` 1050, `getListFromGrid` 1126), residual refinement in `Ident` (2409-2585).
- `src/vast.c` - reference prep and sort (3089-3092), per-image loop (3298), sigma choice
  (2662/3350/2305), retry cascade (3714-4040), acceptance gate (4098).
- `src/vast_limits.h` - the constants in Section 4.
- `src/fit_plane_lin.c` - the first-order residual fit (would be extended for the
  adaptive non-linear residual model, Section 7.3).
- `src/forced_photometry.c` - the independent absolute-WCS measurement (Section 9).
</content>
