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
- Pinned sim BOOTED: AppleMatch-iPhone17Pro-iOS27 DB4F41F3-1C36-476D-B775-AFDC3686C75B
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
- Current bests: toolbar 85.8822; holdout tab bar 33.4020 (unfitted); frozen-RI
  REJECTED (small capsule flow err 1.5× toolbar)
- preapproved_renderer_baseline.json = richer fresnel/caustics/env-light forward
  model (prior sign-off artifact, only consumed by generalization.py; NOT in shipped
  shader) — prior art for the new model design

## Current renderer pipeline (as-is)
- render.glsl: getHeight(sd,thickness) circular arc profile; calculateLighting
  main+opposite(0.8) dual directional rim; refract() displacement; CA 3-sample path
- liquid_glass_final_render.frag uniforms: uOpticalProps(RI,CA,thickness),
  uLightConfig(intensity,ambient,saturation), uHighlightColor, uEdgeColor,
  uOuterContour*, uSpecularConfig(edgeWidth,edgeInset,bleed,wrap), uMaterialConfig
  (transmissionGamma,vibrancy), uFaceShading*, uInnerShadow* trio, uGlassColor
- Settings has 25 knobs (see liquid_glass_settings.dart)

## Execution order
- [x] Orientation complete
- [~] 1. Loupe scene: native trigger + capture + Flutter pre-shader counterpart; fresh pinned composition score pending simulator recovery
- [ ] 2. Perf baseline (before any renderer change)
- [x] 3. New model design doc (mapping Apple layers → our stages)
- [x] 4. Implement: shaders + Settings + Dart pipeline + match-app mapping + optimizer stages
- [~] 5. Re-fit toolbar/small/large/holdout + loupe + slider {0,.5,1}; generalization evidence is partial
- [ ] 6. Perf after-audit
- [ ] 7. Example app: sidebar, ≥4 backgrounds, YAML presets in docs dir, seed presets
- [ ] 8. Tests (settings model, YAML round-trip), analyzer clean
- [ ] 9. README rewrite + final scorecard commit
- [ ] 10. Gate audit vs contract → complete_goal

## Progress log
- 2026-08-25: goal activated; env verified; venv built; orientation reads done.
