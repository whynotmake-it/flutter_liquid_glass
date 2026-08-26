# Goal ledger — renderer model redesign (20260825101909-8ei3kw)

Objective: rebuild the effect model to match Apple internals (SDF-profile refraction,
dual directional highlights, unified tint/transparency axis), evidence-gated knobs,
extend harness with a separately modeled loupe composition + transparency axis
{0,.5,1}, re-fit all scenes, rebuild example shell (sidebar/backgrounds/YAML
presets), performance non-regressing.

## User decisions (grilling, 2026-08-25)
- Full breaking redesign approved (supersedes README escalation contract).
- Harness-only private probing OK (UIViewGlassTintAmount etc.). Never shipped code.
- Param budget: evidence-gated, NO numeric cap. Every knob must earn ≥2 scenes.
- PERFORMANCE PARAMOUNT: no regressions.
- Loupe scene instead of pill-over-tab-bar (tab bar underlay pollutes error signal).
- Dark appearance + physical device parity = recorded follow-ups, NOT gates.

## Gates (verification contract)
1. `melos run analyze` exit 0
2. `melos run test-without-goldens` exit 0 (+ settings model tests + YAML round-trip)
3. lib/src grep: zero blur-mix mixers / innerShadow* trio / independent rim RGB triplets;
   settings doc table maps every surviving knob → ≥2 improving scenes
4. out/<final-run>/summary.json: toolbar ≥85.88, tab_bar_holdout >33.40,
   capsules ≥ pre-change bests, loupe has a pinned example-composition score
   using pre-shader magnification (not the retired pre-redesign S0+10 comparison),
   metadata pins iOS 27 runtime + UDID
5. Slider-axis {0,.5,1}: shared param vector except ≤2 documented scalars
6. Frozen-parameter generalization: small-capsule combined error ≤1.25× toolbar (was >1.5×)
7. Perf audit before/after mean frame times, ≤ +5%
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
- Score = 100×(1−weighted err): appearance 30% / radial-flow 25% / edge 15% /
  specular(black probe) 15% / tint(white probe) 15%
- Current shared-vector evidence: toolbar 91.7814; small capsule 85.2647;
  large capsule 89.4927; tab-bar holdout 43.0289 after adding deterministic
  harness-only foreground. Historical standalone fits were small 86.3452 and
  large 80.6343; they are not the frozen-vector gate. The paired A/B flow
  metric is authoritative. A fresh pinned loupe composition score and final
  performance ratio remain open.
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
  directional highlights, and an SDF-derived dark contour.
- `LiquidGlassSettings` exposes the evidence-gated vector: visibility, tint,
  thickness, edgeRefraction, refractionSpread, frost, chromaticAberration,
  saturation, transmissionGamma, vibrancy, highlight, contourStrength, and
  contourWidth. Legacy face-shading, independent rim, and inner-shadow weights
  are not shipped.

## Execution order
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
- 2026-08-25: goal activated; env verified; venv built; orientation reads done.
- 2026-08-25: clear loupe example composition verified in both entry points;
  focused example tests/analyzer pass. Simulator service remains unavailable,
  so fresh pinned loupe and slider evidence is still pending.
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
