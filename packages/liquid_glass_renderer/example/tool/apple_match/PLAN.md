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
- Current evidence: toolbar 91.7814; small capsule 86.3452; large capsule
  80.6343; tab-bar holdout 43.0289 after adding deterministic harness-only
  foreground; paired A/B flow metric is now authoritative. A fresh pinned
  loupe composition score and final performance ratio remain open.
- preapproved_renderer_baseline.json = richer fresnel/caustics/env-light forward
  model (prior sign-off artifact, only consumed by generalization.py; NOT in shipped
  shader) — prior art for the new model design

## Current renderer pipeline (as-is)
- `gpu/geometry_fragment.glsl`: shared SDF geometry matte, generalized profile
  reach, cached displacement encoding, and the existing one-pass `refract()`
  field; the narrow profile remains the `refractionSpread == 0` special case.
- `liquid_glass_final_render.frag`: one backdrop sample path (three channel
  samples only when chromatic aberration is non-zero), unified tint/transmission
  transform, paired directional highlights, and an SDF-derived dark contour.
- `LiquidGlassSettings` exposes the evidence-gated vector: visibility, tint,
  thickness, edgeRefraction, refractionSpread, frost, chromaticAberration,
  saturation, transmissionGamma, vibrancy, highlight, contourStrength, and
  contourWidth. Legacy face-shading, independent rim, and inner-shadow weights
  are not shipped.

## Execution order
- [x] Orientation complete
- [~] 1. Loupe scene: native trigger + capture + Flutter pre-shader counterpart; fresh pinned composition score pending simulator recovery
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
  coverage is 35 tests (one simulator smoke skipped without a device).
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
- 2026-08-25: annotated every surviving `LiquidGlassSettings` material field
  with its evidence-scene scope in the shipped API documentation; `visibility`
  is explicitly marked as a transition utility rather than a fit knob.
