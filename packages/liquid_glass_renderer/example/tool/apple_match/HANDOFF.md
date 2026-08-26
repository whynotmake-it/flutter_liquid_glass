# Liquid Glass renderer redesign — agent handoff

## Status

**Active multi-hour goal; not complete.** The renderer has been moved onto the
unified material vector and the example loupe now uses a clear pre-shader
composition. The remaining work is evidence closure: pinned loupe capture,
full performance/transparency audit, and final gate-by-gate verification.

Read these companion files first:

- [`PLAN.md`](PLAN.md) — durable checklist, environment, and verification gates
- [`MODEL_DESIGN.md`](MODEL_DESIGN.md) — Apple-internals mapping and proposed API
- [`README.md`](README.md) — existing matching harness and historical results

## Objective

Deconstruct Apple's iOS 27 Liquid Glass and redesign
`liquid_glass_renderer` around Apple's apparent architecture:

1. SDF/profile-driven refraction.
2. Dual directional edge highlights.
3. One unified tint/transparency axis.
4. Fewer public knobs; every surviving knob must measurably improve at least
   two scenes.
5. No renderer performance regression.
6. Deterministic evidence from the pinned iOS 27 simulator.
7. Example app with a settings sidebar, image/black/white/grid backgrounds,
   and YAML presets in the app documents directory.

Breaking API changes are approved. Private/undocumented APIs or defaults are
allowed **only in the reference harness**, never in shipped package/example
code.

## User decisions

- Full settings/shader model redesign is approved.
- Parameter count has no arbitrary cap, but every knob is evidence-gated.
- Performance is paramount: do not add passes, textures, or per-frame CPU work.
- Use the system text-selection **loupe**, not a pill above a tab bar; the tab
  bar underneath would pollute the comparator.
- iOS 27 simulator references are hard gates. Dark appearance and physical
  device parity are follow-ups, not completion gates.
- YAML presets live in the example app documents directory, with bundled seed
  presets.

## Environment

- Pinned simulator: `AppleMatch-iPhone17Pro-iOS27`
- UDID: `DB4F41F3-1C36-476D-B775-AFDC3686C75B`
- Runtime: iOS 27.0 `24A5408d`
- Xcode: `/Applications/Xcode-27.0.0-Beta.5.app`
- Flutter: `/Users/tim/fvm/default/bin/flutter`; harness default 3.47.1 exists
- Python venv: `compare/.venv`
- `agent-device 0.17.5` and `/opt/homebrew/bin/ffmpeg` are installed
- macOS does not have GNU `timeout`; use tool-level timeouts or `gtimeout` if
  added later.

Typical environment:

```bash
cd packages/liquid_glass_renderer/example/tool/apple_match
export IOS_27_UDID=DB4F41F3-1C36-476D-B775-AFDC3686C75B
export DEVELOPER_DIR=/Applications/Xcode-27.0.0-Beta.5.app/Contents/Developer
```

## Research findings

### Apple's public controls

Apple exposes very few material axes:

- SwiftUI `Glass.regular`, `.clear`, `.identity`
- `.tint(...)`
- `.interactive()`
- shape/container/morphing APIs
- UIKit `UIGlassEffect` tint and interactivity

The iOS 27 Settings transparency/tint slider is backed by the undocumented
`com.apple.UIKit UIViewGlassTintAmount` default. Existing harness tooling and
references already cover positions `0`, `.25`, `.5`, `.75`, and `1`.

### Decompiled architecture

`ShatteredGlass`' macOS 26 deconstruction found:

- `CASDFElementLayer` / `CASDFOutputEffect` producing an SDF texture
- `CABackdropLayer` with private `glassBackground` filter for refraction,
  blur, vibrancy, and tone mapping
- two opposite-angle `CASDFGlassHighlightEffect` layers
- a `vibrantColorMatrix` tone pass

This maps closely to the existing Flutter pipeline; the main problem is its
parameterization and fixed refraction profile, not its number of passes.

### Current Flutter renderer

`LiquidGlassSettings` currently exposes roughly 25 knobs, including multiple
rim, contour, face-shading, and inner-shadow controls.

The geometry shader already computes an SDF circular-arc profile:

```text
height = sqrt(thickness² - (thickness - inwardDistance)²)
```

It then applies `refract()` and encodes displacement into the geometry matte.
The final shader already has main and opposite-direction highlights.

### Critical loupe discovery

The iOS 27 text-selection loupe is intentionally a **background magnifier**:
the grid is enlarged across the interior by roughly 1.55× because that is the
purpose of the interaction. That observation must not be used as evidence that
ordinary glass should zoom its backdrop or that the refraction field is broken.

The renderer must not implement that magnification by scaling the final shader
sample: doing so magnifies already filtered pixels and produces pixelation.
Ordinary glass keeps only its SDF/profile refraction controls. An example-only
loupe should magnify the painted backdrop first (Flutter's `Magnifier`/painted
subtree technique), then pass that higher-resolution result through the normal
liquid-glass shader for edge refraction, tint, and lighting.

The loupe fit is therefore a composition/example concern, not a new shipped
material knob. Ordinary toolbar, tab, and capsule gates remain unchanged and
cannot be hidden by a shader-level zoom axis.

The refraction model remains one shader pass; the loupe's pre-shader painted
magnification is an example composition layered before that pass.

### Refraction strength reparameterization

Separately, replace public `refractiveIndex` with observable
`edgeRefraction`/peak displacement in logical pixels.

This is deliberately a reparameterization, not a claim that one scalar has
replaced two. The public controls become:

- profile width/depth (`thickness`)
- peak displacement (`edgeRefraction`)
- profile reach (`refractionSpread`)

A small Dart-side monotonic solve maps requested peak displacement back to the
internal RI uniform. The reason is attribution and compatibility: at the old
reach, it can reproduce the existing `refract()` displacement field exactly,
so score changes can be attributed to the new reach model or removed knobs,
not to an accidentally different field curve. The solve runs only when settings
change and must be cached; it is not per-frame work.

Peak displacement was verified to be strictly monotonic in RI over practical
ranges (`1.001...3.0`) for thicknesses 6, 10, and 28.

An alternative direct-amplitude GLSL formula was considered and rejected for
now because it would silently change all previously fitted field curves.

## Files changed so far

### Added

- `PLAN.md`
- `MODEL_DESIGN.md`
- `HANDOFF.md` (this file)
- `scenes/loupe.json`
- `apple/capture_loupe.sh`
- `seed_scan.py`

### Modified

- `apple/Sources/AppleMatchApp.swift`
  - Added transparent `UITextView` host for the system loupe.
  - Suppresses edit menus and software keyboard.
  - Overrides `caretRect` so a blinking caret does not pollute registration.
- `scenes/schema.json`
  - Added `loupe` profile.
- `hotloop_staged.py`
  - Added `--scene-id`; default remains `toolbar_capsule`.

Shipped renderer code now contains the unified material vector and cached
size-normalized frost mapping; the harness-only loupe composition is kept out
of the renderer shader.

## Loupe capture evidence

References were captured successfully at:

```text
references/ios27-iphone17pro-light/loupe/
```

Files include `A.png`, `B.png`, `C.png`, `D.png`, raw frames, background
controls, and `metadata.json`.

The capture command is:

```bash
IOS_27_UDID="$IOS_27_UDID" FORCE_REFERENCE=1 \
  bash apple/capture_loupe.sh
```

Capture details:

- System `UITextView` long-press driven by `agent-device`
- Fixed touch point `(201, 620)` logical points
- Three pixel-identical frames medianed per probe
- Loupe capsule measured around:
  - x `142.7`
  - y `502.0`
  - width `116.3`
  - height `85.7`
  - center approximately `(200.8, 544.8)`
- Caret region now has `0.000` mean difference from background.
- Loupe-region mean absolute differences from background:
  - A: `52.43`
  - B: `57.63`
  - C: `1.53` (subtle black rim; max difference ~74)
  - D: `2.91` (subtle white material; max difference ~76)

If `agent-device` reports a stale runner/device lease, terminate stale daemons
and retry:

```bash
pkill -f 'agent-device/dist/src/internal/daemon.js'
```

Do not do this while another intentional agent-device run is active.

## Pre-redesign loupe baseline — current state

### First staged attempt

Output:

```text
out/loupe-baseline-pre-redesign/
```

The optimizer completed all selected stages but crashed during final
registration before writing `summary.json`. It did write:

```text
out/loupe-baseline-pre-redesign/final/scorecard.json
```

That score is only `3.0526` and is **not a fair S0**. The toolbar material seed
was milky (`glassAlpha ~.53`, blur 7), while Apple's loupe is clear and
strongly magnifying. Coordinate descent remained in the wrong local basin.

The original registration failure was caused by a blinking caret outside the
crop. That root cause is fixed and references were recaptured; do not weaken
the registration gate.

### Multi-seed scan

`seed_scan.py` was added to find a fair current-renderer basin across clear,
low-blur, high-refraction candidates. The typed `MetricResult` access is now
fixed, and the scan validates the pinned reference metadata before starting.
It emits an explicit `loupe-example-composition-seed-scan` summary and best
scorecard, records the RawMagnifier composition, and marks the shader-level S0
as retired. It must still be run against the pinned simulator after
CoreSimulatorService recovers.

No seed scan process is currently running.

After repair:

```bash
IOS_27_UDID="$IOS_27_UDID" \
  compare/.venv/bin/python seed_scan.py \
  --scene-id loupe \
  --out out/loupe-seed-scan-pre-redesign
```

Then seed a short staged refinement from the best candidate if composition
optimization is still useful. The resulting score is composition evidence for
the example loupe; it is not a renderer-only S0 and must not be compared using
the retired fair-S0+10 gate.

## Planned new settings surface

Final names are evidence-gated, but the current design is:

- `visibility` — retained transition utility
- `thickness`
- `edgeRefraction`
- `refractionSpread`
- `chromaticAberration` — retain only if it helps at least two scenes
- `frost` — replaces `blur`
- `tint` — replaces `glassColor`
- `saturation`
- `transmissionGamma`
- `vibrancy`
- `highlight`
- `contourStrength`
- `contourWidth`

Candidate removals/fold-ins:

- `refractiveIndex`
- `lightAngle` (fixed top light)
- `ambientStrength`
- public `highlightColor`
- `edgeColor`, `edgeWidth`, `edgeInset`
- `outerContourColor`, `outerContourWidth`
- `specularWrap`, `bleedStrength`
- `faceShadingStrength`, `faceShadingDepth`
- entire `innerShadow*` trio

Do not merely bake scene-specific workaround constants into shaders. If a
removed effect causes a systematic residual, derive one profile/contour
primitive from the SDF instead of reintroducing independent knobs.

## Proposed shader implementation

Geometry shader: `lib/assets/shaders/gpu/geometry_fragment.glsl`

1. Add profile reach to the reflected uniform block.
2. Generalize the current arc exactly:

```text
current: reach = thickness
new:     reach = function(refractionSpread, shape scale)
height = thickness * sqrt(1 - ((reach - inwardDistance) / reach)^2)
height = thickness once inwardDistance >= reach
```

3. Compute normal from the same generalized profile.
4. Keep the existing `refract()` field for backwards-compatible narrow reach.
5. Pass/derive a safe displacement-encoding scale shared by geometry and final
   decode; do not let edge displacement clip.

Likely affected shipped files:

- `lib/src/liquid_glass_settings.dart`
- `lib/assets/shaders/gpu/geometry_fragment.glsl`
- `lib/assets/shaders/liquid_glass_final_render.frag`
- `lib/src/internal/flutter_gpu_geometry_renderer.dart`
- `lib/src/rendering/liquid_glass_render_object.dart`
- `test/src/liquid_glass_settings_test.dart`
- harness `flutter/lib/scene_view.dart`
- `hotloop_staged.py` stage map and baseline JSON files

Uniform offsets in the GPU renderer are reflection-derived; add the new member
cleanly rather than repacking unrelated semantics into `uNumShapes`.

## Performance invariants

The redesign must keep:

- same geometry pass count
- same final filter pass count
- same texture/sample count unless measured evidence proves otherwise
- no new backdrop capture
- no per-frame numerical solve

The RI/amplitude solve belongs in Dart, cached when settings change.

Existing benchmark tooling:

```text
example/tool/benchmark.sh
example/tool/parse_benchmark_results.dart
example/tool/PERFORMANCE_AUDIT.md
```

Capture a macOS profile-mode pre-change baseline **before modifying shipped
renderer code**. Final mean frame time must remain within +5%.

## Transparency axis

Pinned references already exist at:

```text
references/ios27-iphone17pro-light-transparency/slider-000/
references/ios27-iphone17pro-light-transparency/slider-050/
references/ios27-iphone17pro-light-transparency/slider-100/
```

Metadata pins the same iOS 27 runtime and UDID. `transparency_sweep.py` now
copies the exact baseline tint RGB into one shared vector and fits no more than
the two documented per-position scalars `tint alpha` and `frost`. Its emitted
constraint audit rejects unauthorized material drift; fresh pinned endpoint
visuals remain required after CoreSimulatorService recovery.

## Example app work — not started

Current example already has `SettingsSheet`, `Grid`, stripes, and image helpers
in `example/lib/shared.dart`, but the requested shell is not implemented.

Plan:

1. Replace modal settings sheet with a persistent sidebar.
2. Add background selector: image, black, white, primary grid, holdout grid.
3. Add `yaml` and `path_provider` dependencies.
4. Add `LiquidGlassSettings.toJson/fromJson` as the canonical preset dialect.
5. Save one YAML file per preset in the app documents directory.
6. Load all presets on startup; bundle seed preset assets.
7. Unit-test settings JSON and YAML round trips.

## Verification contract

The goal is complete only when all of these hold:

1. `melos run analyze` exits 0.
2. `melos run test-without-goldens` exits 0, including settings-model and YAML
   round-trip tests.
3. Superseded workaround parameter names are absent from shipped `lib/src`;
   `liquid_glass_settings.dart` documents every surviving knob and the ≥2 scenes
   it improves.
4. Final committed score summary:
   - toolbar ≥ `85.88`
   - tab-bar holdout > `33.40`
   - small/large capsules ≥ historical bests
   - loupe is evaluated as an example composition: pre-shader painted-backdrop
     magnification plus the ordinary glass shader's edge refraction; the old
     fair-S0+10 gate is retired because it conflated intentional magnification
     with ordinary refraction quality
   - pinned iOS 27 runtime and UDID metadata
5. Slider positions `0/.5/1` use one shared vector except ≤2 documented scalars.
6. Frozen-parameter generalization: small-capsule combined error ≤1.25× toolbar
   (previously >1.5×).
7. Performance before/after audit: post-change ≤ baseline ×1.05.
8. Harness README includes Apple-layer→pipeline mapping, final scores, loupe,
   and rewritten escalation contract. Example is analyze-clean and demonstrates
   sidebar, ≥4 backgrounds, and persistent presets.

## Immediate next steps

1. Run the hardened `seed_scan.py` composition scan once CoreSimulatorService
   recovers; record its pinned metadata and composition score separately from
   ordinary-glass gates.
2. Re-capture pinned loupe/transparency visuals and post comparison images.
3. Run the existing macOS performance benchmark for the pre-change baseline.
4. Implement `refractionSpread` + displacement-amplitude parameterization; do
   not add a shader-level loupe scale.
5. Collapse the public settings surface and update match-app JSON mapping.
6. Run tests/analyzer before fitting.
7. Re-fit toolbar, capsules, holdout, loupe, and slider axis.
8. Iterate only from measured residuals; every new knob needs ≥2-scene evidence.
9. Build example sidebar/background/preset workflow.
10. Run final verification contract and independent audit.

## Continuation update (2026-08-25)

The active renderer/example state is now:

- The loupe is an example/harness composition: `RawMagnifier` paints a 1.55×
  backdrop first, followed by the ordinary liquid-glass layer. The loupe path
  forcibly neutralizes tint, frost, face reach, saturation, gamma, and vibrancy;
  `refractionSpread` is not a loupe zoom control.
- Small-control frost is derived from rendered height, clamped at the 94 px
  toolbar reference. This is one cached compositor scalar, not a new public
  setting, pass, texture, or per-frame solve.
- The corrected paired A/B optical-flow metric is used for current evidence;
  comparing A against an all-zero image incorrectly counted foreground glyphs
  and material response as flow.
- Current frozen-vector scorecards are toolbar 91.7814, small capsule 85.2647,
  large capsule 89.4927, and tab holdout 43.0289. The historical standalone
  small/large fits (86.3452/80.6343) are retained for comparison only. A fresh
  pinned loupe composition score is still required.
- `melos run analyze`, `melos run test-without-goldens`, focused harness tests,
  package GPU tests, and comparator tests pass with the pinned Flutter 3.47.1
  toolchain.
- The example's focused basic-app/YAML/loupe tests pass (6 tests), and both
  `flutter build apk --debug` and `flutter build macos --profile` succeed with
  Impeller/Flutter GPU enabled. The macOS benchmark ratio gate is still open;
  existing benchmark artifacts are historical evidence, not a fresh before /
  after pair for this exact final state.

The final loupe capture/fit must use Xcode 27.0 beta 5 and the pinned UDID. On
the latest attempt CoreSimulatorService became unavailable; no other simulator
was shut down. Do not weaken the pinned-device gate or accept stale pre-shader
scan outputs as final evidence. Once the service is healthy, run the bounded
scan and staged validation described in `PLAN.md`, keeping magnification and
focal offset fixed while fitting only ordinary edge optics.

## Continuation update (2026-08-26)

Sol reviewed the small-capsule residual and identified a registration overhang:
the candidate was 450 physical pixels wide while Apple was 446, with matching
center and height. A pinned seven-value width sweep found the exact-registration
candidate at `shapeWidth=148.667`; three repeated captures were identical and
shape/flow errors improved materially. The candidate's combined error regressed
2.6%, however, so it is not a valid shared-vector or renderer change. Keep the
current 150 px setting as the authoritative frozen-vector run and retain the
captures under `out/small-width-registration/` for future scene-specific
registration work. Do not fit a new shader profile until registration and the
combined/flow gates agree.

The current macOS trace probe found that xctrace's windowed mode can truncate
an 8-second recording to roughly one second before the gated workload. The
benchmark harness now defaults `LIQUID_GLASS_BENCHMARK_TRACE_WINDOW_SECONDS=0`
(no `--window`), which produced a valid grouped16 trace. Independent16 still
timed out during xctrace finalization twice at the 308-second watchdog, so the
native grouped-vs-independent comparison and final ≤5% performance gate remain
open. Do not treat in-process GPU numbers or a timed-out trace as native Metal
evidence.

The benchmark also supports `TRACE_WAIT_FOR_READY=false` for short,
high-density traces. It waits for the app's post-warmup measurement marker
before attaching xctrace; the parser still rejects overlap failures and
interval-loss CV above 30%. Current three-repetition probes had one valid
independent16 trace and two rejected, while grouped16 had two valid and one
rejected. The mode is a reliability improvement, not final performance-gate
evidence.
