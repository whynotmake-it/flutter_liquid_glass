# Plan 002: Lower the Flutter constraint to >=3.32.4 and gate composed blur behind a runtime version check

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 85323b7..HEAD -- packages/liquid_glass_renderer/lib/src/rendering packages/liquid_glass_renderer/pubspec.yaml packages/apple_liquid_glass/pubspec.yaml`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition. Plan 001 is expected to have
> landed first — its changes to `liquid_glass_layer.dart` (removal of the
> `pushClipPath` block and `insideGlass`) are accounted for below.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/001-remove-glass-contains-child.md
- **Category**: migration / compatibility
- **Planned at**: commit `85323b7`, 2026-06-11

## Why this matters

Commit `683b6c9` raised the package's minimum Flutter from 3.32.4 to 3.44.0.
The only feature on this branch that genuinely requires Flutter 3.44 is
composing the background blur into the glass shader's backdrop filter
(`ImageFilter.compose(inner: blur, outer: ImageFilter.shader(...))` inside a
single `BackdropFilterLayer`, introduced in commit `b761e0c`); on older
Flutter this composition does not render correctly on Impeller. Everything
else (the `sdf.glsl` refactor, direct render, nine-slice, component
splitting) compiles and runs on 3.32.4.

Forcing every consumer onto Flutter 3.44 for a one-layer-per-glass saving is
a bad trade. This plan restores `flutter: ">=3.32.4"` and selects the blur
strategy at runtime: composed single-layer on Flutter >= 3.44, the
pre-`b761e0c` two-layer structure (separate blur `BackdropFilterLayer`)
otherwise.

## Current state

All paths relative to repo root `/Users/tim/Developer/flutter_liquid_glass`.

- `packages/liquid_glass_renderer/pubspec.yaml:18-20` — current constraint:

  ```yaml
  environment:
    sdk: ">=3.12.0 <4.0.0"
    flutter: ">=3.44.0"
  ```

  The pre-branch values (commit `683b6c9~1`) were `sdk: ">=3.0.0 <4.0.0"`,
  `flutter: ">=3.32.4"`.
- `packages/apple_liquid_glass/pubspec.yaml:8-10` — same `>=3.12.0` /
  `>=3.44.0` pair; restore the same way.
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_layer.dart`
  — two places compose blur into the shader filter:
  1. `_pushGlassLayers` (lines 496–523 at plan time):

     ```dart
     // liquid_glass_layer.dart:503-523 (current)
     final blurFilter = settings.effectiveBlur > 0
         ? ImageFilter.blur(
             tileMode: TileMode.mirror,
             sigmaX: settings.effectiveBlur,
             sigmaY: settings.effectiveBlur,
           )
         : null;
     final composedFilter = switch (blurFilter) {
       final blur? => ImageFilter.compose(inner: blur, outer: glassFilter),
       null => glassFilter,
     };
     final shaderLayer = (_shaderHandle.layer ??= BackdropFilterLayer())
       ..filter = composedFilter
       ..backdropKey = backdropKey;
     ```

  2. `paintLiquidGlassComponents` (lines 366–400 at plan time): per-component
     loop builds `composedFilter` the same way (lines 391–395).
- The pre-`b761e0c` structure, for reference (recoverable via
  `git show b761e0c~1:packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_layer.dart`):
  a `_blurLayerHandle = LayerHandle<BackdropFilterLayer>()` whose layer had
  `filter = ImageFilter.blur(...)` and `backdropKey = backdropKey`, pushed
  inside the clip before the shader layer; the shader layer carried only
  `ImageFilter.shader(renderShader)`.
  NOTE: at that time the blur layer lived inside the (now deleted by Plan
  001) `pushClipPath` block. In the fallback you will instead push it inside
  the existing `pushClipRect` block, before the shader layer — see Step 3 for
  the exact target structure and why a path clip is needed around the blur.
- There is no existing version/feature gate utility in the package
  (`rg -n "Platform.version" packages/liquid_glass_renderer/lib` → no
  matches).
- Dart-to-Flutter version pairing: Flutter 3.44 ships Dart 3.12 (this is
  exactly why the sdk constraint was bumped to 3.12 in the same commit).
  Earlier Flutter stable releases ship Dart < 3.12. Parsing the Dart runtime
  version from `Platform.version` is therefore a reliable stable-channel
  proxy for "Flutter >= 3.44".

## Commands you will need

| Purpose | Command (from repo root) | Expected on success |
|---------|--------------------------|---------------------|
| Analyze | `melos run analyze` | exit 0 |
| Tests (no goldens) | `melos run test-without-goldens` | all pass |
| Full tests | `melos run test` | all pass |
| Resolve on old Flutter (optional, if fvm available) | `fvm install 3.32.4 && cd packages/liquid_glass_renderer && fvm spawn 3.32.4 pub get` | resolves without constraint errors |

## Scope

**In scope**:
- `packages/liquid_glass_renderer/pubspec.yaml` (environment block only)
- `packages/apple_liquid_glass/pubspec.yaml` (environment block only)
- `packages/liquid_glass_renderer/lib/src/internal/flutter_feature_support.dart` (create)
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_layer.dart`
- `packages/liquid_glass_renderer/test/src/flutter_feature_support_test.dart` (create)

**Out of scope** (do NOT touch):
- `.fvmrc`, `.vscode/settings.json`, CI workflows — the development
  environment stays on Flutter 3.44.x; only the *package constraint* is
  lowered.
- `packages/liquid_glass_renderer/lib/assets/shaders/**` — the `sdf.glsl`
  changes from `683b6c9` are SkSL-compatibility fixes, not 3.44-dependent.
- `CHANGELOG.md` — generated by melos.
- The direct-render and component fast paths' *logic* — only their blur
  layering is touched.

## Git workflow

- Commit message: `fix: lower minimum Flutter to 3.32.4 and gate composed backdrop blur behind a version check`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Create the feature gate

Reliability note: the Dart-version proxy is exact on the stable channel
(each stable Flutter pins a unique Dart minor; the mapping within this
gate's window is 3.32→3.8 … 3.44→3.12). It can misjudge on beta/master
(Dart 3.12 can precede or follow the engine fix by weeks there) and on
custom/forked engines — accepted: the failure mode is visual only, and the
gate stays internal with a test-only override.

Create `packages/liquid_glass_renderer/lib/src/internal/flutter_feature_support.dart`:

```dart
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

/// Feature gates for engine behavior that depends on the Flutter version.
///
/// Flutter does not expose its own version at runtime, but each stable
/// Flutter release pins a specific Dart SDK, so the Dart runtime version
/// (from [Platform.version]) is an exact proxy on the stable channel.
@internal
abstract final class FlutterFeatureSupport {
  /// Overrides [composedBackdropShader] in tests.
  @visibleForTesting
  static bool? debugComposedBackdropShaderOverride;

  /// Whether `ImageFilter.compose(inner: blur, outer: ImageFilter.shader)`
  /// renders correctly inside a [BackdropFilterLayer].
  ///
  /// Fixed in Flutter 3.44, which ships Dart >= 3.12.
  static bool get composedBackdropShader =>
      debugComposedBackdropShaderOverride ?? _dartIsAtLeast(3, 12);

  static bool _dartIsAtLeast(int major, int minor) {
    if (kIsWeb) return false;
    final match = RegExp(r'^(\d+)\.(\d+)').firstMatch(Platform.version);
    if (match == null) return false;
    final actualMajor = int.parse(match.group(1)!);
    final actualMinor = int.parse(match.group(2)!);
    return actualMajor > major ||
        (actualMajor == major && actualMinor >= minor);
  }
}
```

Notes for the executor:
- `Platform.version` returns e.g. `3.12.0 (stable) ... on "macos_arm64"`;
  the regex reads only the leading `major.minor`.
- `kIsWeb` short-circuits because `dart:io` Platform is unavailable on web
  (the package does not support web, but the import must not crash analysis).

**Verify**: `melos run analyze` → exit 0.

### Step 2: Restore the lower constraints

In `packages/liquid_glass_renderer/pubspec.yaml` set:

```yaml
environment:
  sdk: ">=3.0.0 <4.0.0"
  flutter: ">=3.32.4"
```

Apply the same environment block to `packages/apple_liquid_glass/pubspec.yaml`.

**Verify**: `cd packages/liquid_glass_renderer && flutter pub get` → exit 0.

### Step 3: Add the layered-blur fallback to `_pushGlassLayers`

In `liquid_glass_layer.dart`, `RenderLiquidGlassLayer`:

- Re-add a blur layer handle field:
  `final _blurLayerHandle = LayerHandle<BackdropFilterLayer>();` and a
  clip handle for it:
  `final _blurClipHandle = LayerHandle<ClipPathLayer>();`
  Null both out in `dispose()`.
- In `_pushGlassLayers`, branch on the gate:

  ```dart
  final useComposedBlur =
      FlutterFeatureSupport.composedBackdropShader;
  final blurFilter = settings.effectiveBlur > 0
      ? ImageFilter.blur(
          tileMode: TileMode.mirror,
          sigmaX: settings.effectiveBlur,
          sigmaY: settings.effectiveBlur,
        )
      : null;

  final composedFilter = switch ((blurFilter, useComposedBlur)) {
    (final blur?, true) =>
      ImageFilter.compose(inner: blur, outer: glassFilter),
    _ => glassFilter,
  };
  ```

- When `blurFilter != null && !useComposedBlur`, push the legacy blur pass
  *before* the shader layer, clipped to the union of the glass shape paths
  (the blur must not paint outside the glass): build the union `Path` from
  `shapes` exactly as the pre-Plan-001 code did —

  ```dart
  final clipPath = Path();
  for (final geometry in shapes) {
    if (!geometry.$1.attached) continue;
    clipPath.addPath(
      geometry.$2.path,
      Offset.zero,
      matrix4: geometry.$3.storage,
    );
  }
  final blurLayer = (_blurLayerHandle.layer ??= BackdropFilterLayer())
    ..filter = blurFilter
    ..backdropKey = backdropKey;
  _blurClipHandle.layer = context.pushClipPath(
    needsCompositing, offset, boundingBox, clipPath,
    (context, offset) {
      context.pushLayer(blurLayer, (context, offset) {}, offset);
    },
    oldLayer: _blurClipHandle.layer,
  );
  ```

  When the composed path is used (or blur is zero), release both handles
  (`_blurLayerHandle.layer = null; _blurClipHandle.layer = null;`).
- The existing `pushClipRect` + shader-layer block is unchanged apart from
  using `composedFilter`.

**Verify**: `melos run analyze` → exit 0; `melos run test-without-goldens` →
pass (tests run on Flutter 3.44 where the gate selects the composed path, so
goldens must be byte-identical — run `melos run test` to confirm no golden
diffs).

### Step 4: Gate the component path

`paintLiquidGlassComponents` composes blur per component but has no shape
`Path` available per component (components are defined by uniforms + a clip
rect, so a correct legacy blur pass cannot be clipped to the glass shape).
Instead of replicating the fallback there, disable component splitting when
it cannot compose:

In `RenderLiquidGlassLayer.gatherDirectComponents` (lines 341–351 at plan
time), add at the top:

```dart
if (settings.effectiveBlur > 0 &&
    !FlutterFeatureSupport.composedBackdropShader) {
  return null;
}
```

Returning null makes the renderer fall back to the texture pipeline, which
now handles blur via Step 3's layered path. Add a one-line comment saying
why.

Note: `paintLiquidGlassDirect` needs no change — it funnels through
`_pushGlassLayers`, which Step 3 already gates.

**Verify**: `melos run analyze` → exit 0.

### Step 5: Unit-test the gate

Create `packages/liquid_glass_renderer/test/src/flutter_feature_support_test.dart`:

- Test that `FlutterFeatureSupport.composedBackdropShader` returns true on
  the current runtime (tests run on Flutter >= 3.44 / Dart >= 3.12).
- Test that `debugComposedBackdropShaderOverride = false` forces false, and
  reset it in `tearDown`.
- Widget test: pump a `LiquidGlassLayer` with
  `settings: LiquidGlassSettings(blur: 5)` and a `LiquidGlass` child with
  the override forced to `false`; expect no exceptions and that a
  `BackdropFilterLayer` whose `filter` is a blur exists in the layer tree
  (model the pump structure after the existing tests in
  `test/src/liquid_glass_test.dart`).

**Verify**: `melos run test-without-goldens` → all pass including the new
file.

## Test plan

- New: `flutter_feature_support_test.dart` (3 tests, see Step 5).
- Existing golden suite must be unchanged on Flutter 3.44 (composed path
  remains default there).
- Manual/optional: if `fvm` has a 3.32.4 SDK available, run the example app
  with it and visually confirm frosted glass renders (blurred backdrop, no
  black/empty glass): `cd packages/liquid_glass_renderer/example && fvm spawn 3.32.4 run --enable-impeller`.
  If no old SDK is available, note that in the status row — do not block.

## Done criteria

- [ ] `packages/liquid_glass_renderer/pubspec.yaml` has `flutter: ">=3.32.4"` and `sdk: ">=3.0.0 <4.0.0"`
- [ ] `packages/apple_liquid_glass/pubspec.yaml` matches
- [ ] `rg -n "composedBackdropShader" packages/liquid_glass_renderer/lib` shows the gate used in both `_pushGlassLayers` and `gatherDirectComponents`
- [ ] `melos run analyze` exits 0
- [ ] `melos run test` exits 0 with zero golden diffs
- [ ] No files outside the in-scope list modified
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Plan 001 has not landed (the `pushClipPath`/`insideGlass` code is still
  present in `_pushGlassLayers`) — this plan's Step 3 instructions assume
  the post-001 shape of the file.
- Goldens change on Flutter 3.44 after Step 3 (the composed path must be
  bit-identical to before; a diff means the branch refactor altered it).
- You discover other APIs in `lib/` that fail to compile against Flutter
  3.32.4 / Dart 3.0 (e.g. newer dart:ui members). List them and stop —
  the constraint floor may need to be something between 3.32.4 and 3.44.
- The `Platform.version` parse fails in tests.

## Maintenance notes

- When the package eventually requires Flutter >= 3.44 for other reasons,
  delete `FlutterFeatureSupport` and the layered fallback in one commit —
  grep for `composedBackdropShader`.
- The Dart-version proxy misidentifies master/beta-channel Flutters that
  ship Dart 3.12 before 3.44; the `debugComposedBackdropShaderOverride`
  escape hatch exists for that. Consider promoting it to public API if users
  report it.
- Reviewer should scrutinize: layer handle lifecycle when toggling between
  composed and layered paths at runtime (hot reload with override flipped).
