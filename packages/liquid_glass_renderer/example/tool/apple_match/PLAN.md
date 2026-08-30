# Goal ledger — renderer model redesign (20260825101909-8ei3kw)

Objective: recover and then exceed the last proven Apple lighting match before
continuing the broader renderer redesign. The immediate target is the clear
(`frost=0`) black/white material response: dark
dielectric contour, highlight-over-contour occlusion, inner bevel shadow, and
exterior shadow. The weighted headline score is diagnostic only during this
recovery; no setting or shader simplification may be promoted when the annotated
black/white residual or an edge-region metric regresses. Once that floor is
restored, continue the SDF-profile refraction, unified tint/transparency, loupe
composition, example shell, generalization, and non-regressing performance work.

## User decisions (grilling, 2026-08-25)
- Full breaking redesign approved (supersedes README escalation contract).
- Harness-only private probing OK (UIViewGlassTintAmount etc.). Never shipped code.
- Param budget: evidence-gated, NO numeric cap. Every knob must earn ≥2 scenes.
- PERFORMANCE PARAMOUNT: no regressions.
- Loupe scene instead of pill-over-tab-bar (tab bar underlay pollutes error signal).
- Dark appearance + physical device parity = recorded follow-ups, NOT gates.

## Gates (verification contract)
0. Visual-first lighting recovery on the pinned toolbar reference with `frost=0`:
   every iteration posts an annotated Apple / Flutter / residual composite for
   black and white; the pre-redesign solid-probe baseline is a hard floor
   (black response ≤.001302, white response ≤.001199, black specular ≤.003641),
   and C/D rim, lip, and face regions must not regress. Patterned RGBW/specular
   measurements remain reported but cannot gate a `frost=0` lighting candidate
   against a historical `frost=7` capture. A higher aggregate score cannot
   override this gate.
1. `melos run analyze` exit 0
2. `melos run test-without-goldens` exit 0 (+ settings model tests + YAML round-trip)
3. lib/src grep: zero blur-mix mixers / arbitrary independent rim RGB triplets;
   settings doc table maps every surviving knob → ≥2 improving scenes. Face
   gradient, bevel shadow, contour transmission, and highlight occlusion may be
   restored as renderer features when black/white evidence proves them; do not
   collapse them into one contour multiplier merely to reduce the public API.
4. out/<final-run>/summary.json: toolbar ≥85.88, tab_bar_holdout >33.40,
   capsules ≥ pre-change bests, loupe has a pinned example-composition score
   using pre-shader magnification (not the retired pre-redesign S0+10 comparison),
   metadata pins iOS 27 runtime + UDID
5. Slider-axis {0,.5,1}: shared param vector except ≤2 documented scalars
6. Frozen-parameter generalization: small-capsule combined error ≤1.25× toolbar (was >1.5×)
7. Perf audit before/after mean frame times, ≤ +5%; focused lighting A/B is
   complete (+.5% independent raster p95, +4.1% GPU/frame), while the final
   full-suite/native-trace audit remains open
8. README updated (Apple-layer→pipeline mapping table, scorecards incl. loupe,
   escalation section rewritten); example analyze-clean, sidebar + ≥4 backgrounds +
   preset persistence

## Environment facts
- Pinned sim configured: AppleMatch-iPhone17Pro-iOS27 DB4F41F3-1C36-476D-B775-AFDC3686C75B
  (CoreSimulatorService was unavailable during the latest capture retry; do not
  replace it or close unrelated simulators.)
- Xcode-27.0.0-Beta.5.app installed; DEVELOPER_DIR needed for builds
- compare/.venv READY (numpy/opencv/jsonschema + Pillow/scipy added)
- flutter: /Users/tim/fvm/default/bin/flutter
- Harness layout: apple_match/{apple(SwiftUI ref app),flutter(match app),compare(py),
  scenes,settings,references,out}
- Candidate JSON keys → LiquidGlassSettings mapping: flutter/lib/scene_view.dart
  matchGlassSettings()
- Optimizer stages: hotloop_staged.py STAGES dict (line 35+)
- Score = 100×(1−weighted err): shape 25% / combined transmission 15% /
  radial-flow 15% / blur-MTF 10% / tint-channel 15% / specular 10% /
  holdout 10% (the `metrics.py` WEIGHTS map is authoritative).
- Current shared-vector evidence: toolbar 91.7814; small capsule 85.2647;
  large capsule 89.4927; tab-bar holdout 43.0289 after adding deterministic
  harness-only foreground. Historical standalone fits were small 86.3452 and
  large 80.6343; they are not the frozen-vector gate. The paired A/B flow
  metric is authoritative. The pinned loupe composition score is recorded;
  slider endpoint evidence and the final performance ratio remain open.
  The current scorecards recover thickness per geometry (12 px toolbar, 8 px
  capsules), so they do not yet prove a strict all-parameters-frozen
  generalization gate; a thickness-frozen rerun or an explicit geometry
  exemption is still required.
- preapproved_renderer_baseline.json = richer fresnel/caustics/env-light forward
  model (prior sign-off artifact, only consumed by generalization.py; NOT in shipped
  shader) — prior art for the new model design

## Current renderer pipeline (as-is)
- `gpu/geometry_fragment.glsl`: shared SDF geometry matte, generalized profile
  reach, cached displacement encoding, and the existing one-pass `refract()`
  field; the narrow profile remains the `refractionSpread == 0` special case.
- `liquid_glass_final_render.frag`: one backdrop sample path for subpixel
  chromatic separation (three channel samples only when the displacement-bound
  CA threshold is exceeded), unified tint/transmission transform, paired
  directional highlights, and SDF-derived contour and inner-bevel shadow
  layers. Lighting recovery adds uniform-coherent ALU
  only: no texture sample, backdrop capture, saveLayer, or CPU solve.
- `LiquidGlassSettings` exposes the evidence-gated vector: visibility, tint,
  thickness, edgeRefraction, refractionSpread, frost, chromaticAberration,
  saturation, transmissionGamma, vibrancy, highlight, contourStrength, and
  contourWidth, contourTransmittance, and bevelShadowStrength/Depth.
  Independent rim RGB weights are not shipped.

## Execution order
- [x] Fast fitting backend: macOS Impeller/Flutter-GPU golden A/B/C/D capture,
  host-only corner registration profile, and adjacent-candidate ranking
  calibration. Use iOS simulator only for promoted/final candidates.
- [~] 0. Recover pre-redesign lighting floor with frost disabled; iteration 15
  removes the unsupported contact halo and improves D-rim, but five solid
  regional floors remain open. RGBA16F and 2×/3× DPR outline diagnostics are
  required before changing the SDF/codec.
- [x] Orientation complete
- [x] 1. Loupe scene: native trigger + capture + Flutter pre-shader counterpart; fresh pinned composition score recorded
- [x] 2. Perf baseline captured; final same-runner before/after ratio remains open
- [x] 3. New model design doc (mapping Apple layers → our stages)
- [x] 4. Implement: shaders + Settings + Dart pipeline + match-app mapping + optimizer stages
- [~] 5. Re-fit toolbar/small/large/holdout + loupe + slider {0,.5,1}; generalization evidence is partial
- [ ] 6. Perf after-audit
- [x] 7. Example app: sidebar, ≥4 backgrounds, YAML presets in docs dir, seed presets
- [x] 8. Tests (settings model, YAML round-trip), analyzer clean
- [x] 9. README rewrite + current evidence ledger committed; final scorecard remains open
- [ ] 10. Gate audit vs contract → complete_goal

## Progress log
- 2026-08-31: recaptured the expanded frost-free light/dark solid-palette
  references with 14 declared probes (hues, neutral ramp, black/white) and
  passed the stability/provenance gate. Added bounded normalized SPSA fitting
  for coupled host-golden evaluations. The first dark joint scalar fit reduced
  palette mean error 11.12→9.25 but worsened worst hue 15.77→16.52; the light
  fit similarly worsened neutral guards. A luminance-centered vibrancy shader
  candidate improved light saturation but regressed dark mean 11.12→16.00 and
  was reverted. No unproven color model has been promoted.
- 2026-08-31: added same-API toolbar solid palettes and a mixed-color gradient
  holdout. The Apple gradient capture passed repeated-frame stability after
  allowing the documented SwiftUI/Flutter interpolation difference in the
  registration gate; solid/grid registration remains strict. A short coupled
  SPSA fit over toolbar solids plus the gradient improved the host score only
  89.10→89.94 with gamma 1.30→1.2655, so it remains diagnostic rather than a
  public-default change. The lower-error alpha/gamma/saturation candidate still
  produced an over-bright rim on the gradient (score ~61.9) and was rejected.
  A shader-order experiment that saturated transmission before tint mixing was
  also rejected (worst solid hue and gradient edge error regressed) and fully
  reverted. Annotated evidence is under `out/color-model/toolbar-*`.
- 2026-08-31: tested removing the post-saturation clamp as a possible source of
  blue/cyan loss. The toolbar solid metrics and gradient score were byte-identical
  to the clamped baseline for the current settings, so the experiment was
  reverted and no extra shader path was retained.
- 2026-08-31: measured the shipped light preset (`saturation=.9`,
  `transmissionGamma=.9`) separately from the fitting vector: its gradient
  score is 93.83 but solid-palette mean/worst transmission error is
  31.56/52.68. A fixed `saturation=1.9`, `gamma=1.25` vector improves those
  solids to 12.15/20.23 and the gradient to 90.24, but is not a public-default
  change until dark and mixed-scene gates agree. A luminance-adaptive
  saturation experiment improved the light solid worst hue to 18.65 but
  regressed the dark palette (12.29/15.79 → 12.92/16.83), so it was reverted.
- 2026-08-31: tested a chroma-adaptive boost that preserved the shipped
  low-chroma gradient response while increasing saturation only for vivid light
  swatches. It was effectively neutral on the gradient (93.83) and only a
  marginal solid improvement (31.56/52.68 → 30.48/51.42); the dark capture did
  not improve. The hidden boost was reverted rather than adding an unproven
  public control.
- 2026-08-31: tested decoupling the contour/bevel input from the saturated face
  color. It produced no measurable change in the toolbar gradient or solid
  metrics (the rim residual is not caused by the bevel luminance input), so the
  extra shader plumbing was reverted.
- 2026-08-31: tested a stronger chroma-adaptive saturation boost against the
  shipped light preset. It reduced numeric solid error (27.25/45.61 in the
  palette objective) while leaving the gradient score unchanged at 93.83, but
  the annotated atlas visibly over-saturated cyan/green/purple faces and did
  not improve dark evidence. It was reverted; the numeric gain is not accepted
  without a perceptual/held-out match.
- 2026-08-31: re-ran the chroma-adaptive model after fixing shader-include cache
  invalidation (both the capture app and path-dependent package must be cleaned).
  With the current frost-free corpus, a smooth chroma boost of 0.4 lowered light
  palette mean/worst transmission error from 14.95/25.63 to 12.36/19.92 and
  dark mean/worst from 11.24/15.79 to 10.93/15.49. Neutral, black, and white
  guards were unchanged; the held-out gradient score was effectively unchanged
  (89.0959 → 89.0945). The annotated atlases are retained under
  `out/color-model/toolbar-chroma-adaptive04/` and
  `out/color-model/material-dark-chroma-adaptive04/`. Promotion remains gated
  on a same-runner profile A/B and Real/Fake overlap review because FakeGlass's
  native affine color filter cannot express a per-pixel chroma-dependent gain.
- 2026-08-31: fixed compact profile benchmark collection: long JSON reports
  were emitted through `debugPrint`, which chunks them before the shell parser
  can read a complete record. Machine-readable summary/JSON lines now use
  `stdout.writeln`; a regression test locks this contract. A compact adaptive
  profile run captured 247 baseline frames (raster p95 1.739 ms) and 234
  real-saturation frames (raster p95 1.847 ms, GPU busy 1.49 ms/frame); it was
  intentionally a short diagnostic repetition, not the full performance gate.
- 2026-08-31: captured a matching one-repetition stable-binary control for
  `realSaturationOnly`: 246 frames, raster p95/p99 2.06/2.69 ms, total p95
  3.11 ms, in-process GPU 1.71 ms/frame, and 415.6 MB footprint peak. The
  adaptive run was 234 frames at 1.847/2.373 ms raster p95/p99 and 1.49 ms
  GPU/frame, but these are separate short runs rather than a repeated paired
  gate; no performance regression is indicated, while the required paired
  repetitions remain open.
- 2026-08-31: tested applying the same +0.4 vivid-saturation midpoint to
  FakeGlass's existing affine filter. Light solid error was unchanged at the
  worst hue and slightly regressed in mean (20.00 → 20.19); neutral/black/white
  guards were unchanged. The approximation was reverted; RealGlass keeps the
  measured per-pixel boost while FakeGlass retains its cheaper affine contract.
- 2026-08-31: replaced the smooth chroma weight with an equivalent linear clamp
  to remove polynomial work from the hot fragment pass. The linear candidate
  scored light/dark solid mean/worst 12.33/20.25 and 10.47/14.92, with held-out
  gradient score 89.085 (smooth: 89.095); neutral, black, and white guards were
  unchanged. Two interleaved four-second profile pairs measured linear raster
  p95 median 2.194 ms versus stable 2.169 ms (+1.2%), within the 2% gate; GPU
  busy/frame was lower for linear (1.438 vs 1.640 ms). Keep the linear model;
  retain the smooth candidate only as diagnostic evidence.
- 2026-08-31: marked the example bottom-bar pixel tests with the repository's
  `golden` tag so `melos run test-without-goldens` no longer executes image
  comparisons accidentally. The pinned 3.47.1 non-golden workspace suite now
  passes (122 tests), package Impeller/Flutter-GPU tests pass (105 tests), the
  analyzer is clean across all four packages, and the comparator suite passes
  (69 tests, one expected simulator skip). The dedicated example golden job
  initially reported renderer-dependent pixel drift and occasional
  `flutter_tester` SIG-10 finalization failures; the bounded warm-up and
  teardown fix below addresses the example cases without hiding fixture drift.
- 2026-08-31: made the fake-surface golden helper wait four bounded frames after
  shader publication, eliminating the first-frame fallback capture. The real
  and fake drag tests now dispose their GPU-backed subtree before finalization;
  all three example goldens pass in one process. Their images remain separate
  regression fixtures and are not used as color-fit evidence.
- 2026-08-31: the example bottom-bar synchronization/teardown fix was then
  verified end-to-end: all three tagged goldens pass in one process. The
  package's separate `--tags=golden`-only invocation still trips Flutter 3.47's
  `flutter_tester` SIG-10 during the Alchemist fake-glass variant suite, while
  the normal Impeller/Flutter-GPU package run remains green (105 tests).
- 2026-08-31: recorded the current work in JJ as
  `fix: fit color transmission and stabilize GPU goldens`, directly on top of
  `codex/fake-glass-fallback`. Added the example failure-output ignore and
  raised the local JJ snapshot ceiling only enough to retain the validated
  1206×2622 gradient reference probes; no remote bookmark or push was changed.
- 2026-08-31: tested max-channel-anchored saturation for the high-saturation
  vector, based on Apple's dominant-channel plateau. It worsened both the
  toolbar solid objective (19.49/33.68) and gradient score (89.11), so the
  Rec.709 luminance-pivot implementation remains unchanged.
- 2026-08-31: fit a constrained 3×3 affine transform offline across light/dark
  solid and gradient pixels. Although the post-hoc image transform lowered
  several offline errors, inserting it before the shader lighting stage caused
  a real host score collapse to 43.96, confirming that output-space fits cannot
  be promoted without modeling the pre-lighting color stage. The matrix was
  reverted.
- 2026-08-25: goal activated; env verified; venv built; orientation reads done.
- 2026-08-25: clear loupe example composition verified in both entry points;
  focused example tests/analyzer pass. Simulator service remains unavailable,
  so fresh slider endpoint evidence is still pending; the pinned loupe
  composition score is recorded separately.
- 2026-08-25: tested a conservative smooth-union cull and shared coordinate
  atlas as performance candidates. The cull's first unsigned bound was
  corrected during review, but neither candidate produced a proven end-to-end
  frame-time or memory win; both experiments were reverted to preserve the
  no-new-per-frame-work invariant. Their measurements remain in the audit as
  rejected evidence.
- 2026-08-25: reran the repository contract with the pinned Flutter 3.47.1
  toolchain: `melos run analyze`, `melos run test-without-goldens`, harness
  analyzer/tests, comparator tests, and the Android debug build all pass.
  CoreSimulatorService still refuses connections, so fresh pinned loupe,
  slider, and post-change image evidence remain blocked by infrastructure;
  existing shader-level loupe scans are explicitly not used as the retired
  pre-shader composition gate.
- 2026-08-25: completed a focused three-repetition macOS run for
  `baselineMotion`, `grouped16Motion`, `independent16Motion`, and `layerChurn`
  without xctrace. Median raster means were 1.27/1.36/3.33/1.48 ms and median
  raster p95 values were 1.53/1.91/5.28/2.08 ms respectively; repeatability
  failed (CV 16–49%), so this is diagnostic evidence only, not the final ≤5%
  performance gate. Independent16 peak footprint remained about 0.93–1.12 GB.
- 2026-08-25: repaired the transparency sweep contract: exact baseline tint
  RGB is shared across every position, only `tintAlpha` and `frost` are fit,
  and a structural audit now fails on unauthorized material drift. Comparator
  coverage is 40 tests (one simulator smoke skipped without a device).
- 2026-08-25: hardened `seed_scan.py` for the pending loupe composition scan:
  it validates pinned reference metadata, records the RawMagnifier composition,
  derives the actual search axes, and emits a self-describing summary and best
  scorecard. The historical shader-level S0 is explicitly retired. No seed
  scan was run while CoreSimulatorService was unavailable.
- 2026-08-26: audited the proposed shader-branch optimization against Flutter
  3.47.1's Impeller `uber_sdf.frag`. Flutter uses the same bounded SDF and
  piecewise branches, so the renderer keeps the mathematically required SDF
  branches; only uniform branches that skip real texture or bookkeeping work
  are treated as fast paths. No SDF bottleneck claim is made without a stable,
  targeted geometry-pass A/B measurement.
- 2026-08-26: ran the focused shared `refractionSpread` grid on the pinned
  iOS 27 simulator, freshly rendering toolbar, small, and large capsules for
  each value `{0,.0625,.125,.25,.5}` twice. The baseline (`0`) remained the
  best small-capsule combined error (0.063668); the apparent best at `.25`
  improved it only to 0.063511 (0.25%), while toolbar and large changes stayed
  within noise. Small remained 1.90x toolbar combined error and below the
  recorded 86.3452 pre-change score at every value; the 1.25x generalization
  gate therefore failed for the entire existing axis. No renderer change or
  performance claim was inferred. Full rows and captures are in
  `out/spread-grid-current/summary.json`.
- 2026-08-26: completed the coupled existing-model scan recommended by review:
  shared spread `{0,.25,.5,.75,1}` with independently selected thickness from
  `{2,4,6,8,10,12,16}` for toolbar/small/large, one fresh pinned render per
  candidate, and retained A-D captures for every row. The best small combined
  error was 0.063221 (spread .25, thickness 2), still about 2.01x the same
  candidate's toolbar error and below the 86.3452 historical capsule score.
  The coupled axis is rejected as a generalization fix; no new public knob or
  shader change was justified. Evidence is in
  `out/coupled-spread-scan/summary.json`.
- 2026-08-26: ran shared existing-material attribution probes for frost,
  transmission gamma, and edge refraction. Frost's small-capsule score peaked
  at 86.4094 but worsened flow and combined error; gamma improved small
  combined error only 0.4% with no flow movement; edge refraction was flat
  within noise. All three failed Sol's retention thresholds, so defaults and
  renderer code remain unchanged. A-D captures and diagnostics are retained
  under `out/material-attribution-{frost,gamma,edge}`.
- 2026-08-26: reviewed and rejected a proposed superlinear height-to-frost
  normalization. Choosing exponent 1.84 exactly replayed the already measured
  small-capsule frost=5 image while preserving the clamped toolbar/large
  controls; its combined error worsened 0.063668→0.064354 and flow worsened
  0.036286→0.049595. The existing linear normalization remains the only
  evidence-backed shared-size mapping; future work should target the small
  capsule's core-flow residual instead of a score-only frost fit.
- 2026-08-26: ran one fresh pinned small-capsule capture with the existing
  shared material and thickness 10 (the historical small-fit value). It moved
  score only 85.2647→85.2782 and combined error worsened 0.063668→0.063952;
  thickness alone is not the missing generalization fix. The candidate and
  diagnostics are retained in `out/one-off-small-thickness10/`.
- 2026-08-26: completed the attribution ledger with vibrancy and tint alpha.
  Vibrancy's best small combined/flow movement was only 0.8%/2.2%; tint's was
  0.6%/3.3% while regressing toolbar/large and perturbing the transparency
  contract. Both failed retention thresholds; all five existing shared axes
  therefore remain at their validated defaults.
- 2026-08-26: reran the pinned Flutter 3.47.1 repository gates on the current
  stack. `melos run analyze` and `melos run test-without-goldens` both exited 0;
  analyzer output remains informational lint debt only. The simulator-free
  comparator suite remains 42 tests with one expected device smoke skip.
- 2026-08-26: the first macOS profile build exposed a stale generated workspace:
  `Runner.xcworkspace` listed only `Runner.xcodeproj`, so Xcode never built the
  existing `path_provider_foundation` pod and Swift could not import it. Running
  `pod install` restored the `Pods/Pods.xcodeproj` workspace reference; a fresh
  Flutter 3.47.1/Xcode 27 Profile build then passed. No simulator was opened or
  closed.
- 2026-08-26: ran a focused three-repetition grouped16 native trace with the
  GPU and Metal Application instruments only. All app metrics were repeatable
  (raster-p95 CV 1.9%, in-process GPU CV 10.7%, footprint CV 0.8%), but every
  xctrace export was rejected because most retained windows had zero GPU
  intervals. A one-run Metal-Application-only probe produced no GPU table at
  all, confirming that removing the GPU instrument cannot repair this capture
  path. The traces remain diagnostic and no native Metal gate is claimed.
- 2026-08-26: wired the existing trace-start handshake in `benchmark.sh` so
  the trace workload begins only after xctrace posts its readiness notification.
  A gated 8-second grouped capture still retained only one sound window and
  was rejected for the same fixed-event-buffer starvation; the handshake fixes
  timestamp ordering but not Instruments' event-density limit. No shader/SDF
  optimization was inferred from these rejected captures.
- 2026-08-26: the trace benchmark now also holds the expensive animated scene
  behind the readiness gate, so startup frames cannot fill the rolling event
  buffer before Instruments attaches. A targeted 8-second `grouped16Motion`
  capture passed all retained-window checks; three repetitions remained sound
  (traced-GPU utilization CV 6.1%, raster-p95 CV 3.2%, in-process GPU/frame CV
  7.3%, footprint-peak CV 1.7%). This validates the harness attribution path,
  not a renderer/SDF optimization or the final cross-revision perf gate.
- 2026-08-26: repaired `seed_scan.py` so the loupe scan reports only its
  effective `thickness`/`edgeRefraction` axes and records the clear settings
  forced by `_MatchLoupe`; added simulator-free candidate-grid contracts. The
  pinned 12-candidate scan completed with best score 13.5557. Full-frame
  registration then passed after the harness reproduced the reference Dynamic
  Island and explicitly excluded that device chrome plus the simulator corner
  artifact from RGBW controls. The score is composition evidence, not a
  renderer-only zoom claim.
- 2026-08-25: annotated every surviving `LiquidGlassSettings` material field
  with its evidence-scene scope in the shipped API documentation; `visibility`
  is explicitly marked as a transition utility rather than a fit knob.
- 2026-08-26: ran the shared `chromaticAberration` probe on the pinned iOS 27
  simulator with values `{0,.001,.0025,.005,.01,.025,.05,.1}`. Values 0 through
  `.01` produced byte-identical A captures in toolbar, small, and large scenes;
  larger values changed only a few pixels and did not improve score. The final
  shader therefore uses one backdrop sample when `abs(CA) * maxDisplacement`
  is below 0.25 source pixels, preserving three-channel sampling for larger
  surfaces. Evidence is in
  `out/material-attribution-chromaticAberration-cutoff/summary.json`; this is
  a visual attribution result and still needs repeated same-runner perf A/B.
- 2026-08-26: re-registered the small capsule with a frozen shared material
  vector using a seven-value width sweep `{148.0, 148.333, 148.667, 149.0,
  149.333, 149.667, 150.0}` logical pixels. `148.667` produces the Apple
  detected 446 px width (versus the prior 450 px), reduces shape error
  `0.017853→0.009236`, and reduces flow error `0.036286→0.028248`; three
  repeated captures were byte-stable. Its combined error nevertheless worsens
  `0.063668→0.065295` (2.6%), and the shared-vector 1.25× generalization gate
  remains failed. This is useful scene-registration evidence, not a renderer or
  default-material change. Captures and scorecards are in
  `out/small-width-registration/`.
- 2026-08-26: the current focused Metal probe showed xctrace windowed mode
  (`--window 21s`) truncating the retained timeline to about one second before
  the gated workload. Omitting the window yielded a valid grouped16 trace
  (35.3% traced GPU utilization, 2.93 ms/frame); independent16 still exceeded
  the 308 s finalization watchdog twice. `benchmark.sh` now defaults its
  opt-in trace window to `0`; the independent event-density limitation remains
  open and no final cross-revision performance gate is claimed.
- 2026-08-26: added an opt-in prewarmed trace mode that waits for the app's
  post-warmup measurement marker before xctrace attaches. A three-repetition
  independent16 probe produced one sound trace (51.4% traced GPU utilization,
  4.31 ms/frame) and two strict event-loss rejections; grouped16 produced two
  sound traces and one rejection. This improves attachment ordering but does
  not close the native reliability or final performance gates.
- 2026-08-26: annotated the comparison composites with explicit `APPLE GROUND
  TRUTH`, `FLUTTER CANDIDATE`, and `DIFF / RESIDUAL` labels. The previously
  shared small-capsule image used `frost=7`; the retained attribution scan shows
  `frost=5` is the small-scene score peak, while `frost=7` remains required by
  the shared toolbar/large vector. The frost attribution grid now includes the
  clear endpoint `{0,1,2,...,9}` so the user's zero-blur hypothesis is tested
  explicitly when the pinned simulator service is available; no default was
  changed from stale/unavailable-device evidence.
- 2026-08-26: reran `melos run analyze` and `melos run
  test-without-goldens` through the pinned Flutter/Dart 3.47.1 SDK. Both
  completed successfully; analyzer output remains informational lint debt only.
- 2026-08-26: Sol reviewed the frost concern and recommended deferring any
  shared default or size-normalization change. Moving the small scene toward
  its frost-5 headline-score row worsens combined error (`.063668→.064354`)
  and flow (`.036286→.049595`), while lowering the shared value regresses the
  toolbar/large fits. Await the pinned `0…9` scan before making a mapping change.
- 2026-08-26: corrected a provenance error in the demo defaults. The harness
  shared-vector fit (`18.3/.4/.65`) had been promoted into the named preset
  before visual acceptance and made the example's contour too dark. Restored
  the last user-accepted named values (`27.42/.5/.1`), kept the bundled seed in
  parity, and added the private example default with `frost=0`. The center and
  bottom bar now consume one live settings source; focused tests assert the
  no-frost path and exact YAML parity.
- 2026-08-27: added `settings/evidence_manifest.json` and
  `validate_evidence_manifest.py`. The structural audit enumerates every public
  settings field and makes pending/rejected two-scene evidence explicit; strict
  mode remains red until the actual visual gate is closed. Comparator coverage
  is now 44 tests with one expected simulator smoke skip.
- 2026-08-27: corrected `generalization.py` so thickness is frozen from the
  toolbar card by default; independent per-scene thickness fitting is now an
  explicit `--fit-thickness` diagnostic. Summaries emit the formal small/
  toolbar combined-error ratio and policy, preventing a per-geometry fit from
  being mislabeled as frozen-parameter evidence. No simulator rerun was done.
- 2026-08-31: tested a max-channel saturation pivot in the one-pass material
  shader. It reduced the light toolbar solid-palette transmission mean from
  14.79 to 10.47 code points, but the held-out gradient score fell from 93.83
  to 86.06 and red/green/purple hues regressed; it was rejected. A
  chroma-gated pivot preserved neutral guards but produced severe saturated
  hue blowouts (palette mean 32.23), and an HSL/lightness pivot regressed the
  palette to 20.45. All experimental pivots and settings were removed; the
  Rec.709 luminance-pivot implementation remains the active baseline.
- 2026-08-31: found and repaired a host-harness correctness issue: Flutter's
  runtime-effect cache could retain a compiled shader when only an included
  `.glsl` file changed. `flutter/host_capture.sh` now hashes all renderer
  shader sources and runs `flutter clean` for both the generated capture app
  and its path-dependent renderer package when that digest changes. A clean
  rebuild reproduced the stable Rec.709 baseline; future fitting results are
  no longer trusted from stale include binaries.
- 2026-08-31: reran the compact four-iteration scalar SPSA fit after cache
  repair. The best probe lowered light solid-palette mean error 15.08→13.40,
  but worsened the held-out gradient score 89.10→87.02 and neutral-ramp error
  12.67→14.98, so no defaults changed. Fixed the SPSA summary to report the
  actual minimum evaluation (including rejected probes) rather than the last
  accepted iterate's internal loss.
- 2026-08-31: reran the linear-light saturation candidate after invalidating
  both app and package shader caches. It improved the light solid palette
  (mean 14.95→9.08, worst 25.63→19.24) but lowered the fresh gradient score
  89.10→88.70 and left neutral-ramp error at 12.74; the candidate was
  rejected and the Rec.709 shader restored.
