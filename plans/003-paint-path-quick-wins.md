# Plan 003: Eliminate per-frame allocations and redundant work in the paint hot path

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 85323b7..HEAD -- packages/liquid_glass_renderer/lib/src/rendering packages/liquid_glass_renderer/lib/src/liquid_glass_blend_group.dart packages/liquid_glass_renderer/lib/src/internal/render_liquid_glass_geometry.dart`
> Plans 001 and 002 are expected to have landed first; line numbers below
> are from before them, so re-locate excerpts by symbol name, not line
> number. On a structural mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M (a day-ish; six small independent fixes)
- **Risk**: LOW
- **Depends on**: plans/001-remove-glass-contains-child.md, plans/002-version-gate-composed-blur.md
- **Category**: perf
- **Planned at**: commit `85323b7`, 2026-06-11

## Why this matters

Every frame in which any glass is on screen, the layer render object
allocates fresh native `ImageFilter` objects, rebuilds clip `Path`s,
copies the shape map into new lists (several times), walks the ancestor
chain for transforms it already computed, clones matrices, and builds
logging strings that are thrown away. None of this changes the rendered
output; all of it costs CPU and GC pressure during exactly the situations
the package most needs headroom (animations, scrolling). These are the
no-regret optimizations before the bigger architectural work (Plan 006),
and they matter more as the package moves toward arbitrary bezier glass.

Each fix below is independent; do them in order, verifying after each.

## Current state

All paths relative to repo root. Locate by symbol if lines have shifted.

1. **Per-frame ImageFilter allocations** —
   `lib/src/rendering/liquid_glass_layer.dart`, `_pushGlassLayers`:
   `ImageFilter.blur(...)`, `ImageFilter.shader(...)` (passed in as
   `glassFilter` from `paintLiquidGlass`/`paintLiquidGlassDirect`), and
   `ImageFilter.compose(...)` are constructed on every call. Same pattern
   per component in `paintLiquidGlassComponents`.
2. **Per-frame clip Path rebuild** — same file: after Plan 002 the union
   shape `Path` is built per paint in the legacy-blur fallback; before
   Plan 002 it was built unconditionally. The `GeometryCache` objects it is
   built from (`geometry.$2.path`) only change when geometry rebuilds.
3. **`layout()` always dirties geometry** —
   `lib/src/rendering/liquid_glass_render_object.dart`:

   ```dart
   @override
   void layout(Constraints constraints, {bool parentUsesSize = false}) {
     needsGeometryUpdate = true;
     super.layout(constraints, parentUsesSize: parentUsesSize);
   }
   ```

   Any ancestor relayout reaching this render object forces
   `compositeNeedsRebuild` even when nothing changed.
4. **`shapeEntries` copies the map per access** —
   `lib/src/liquid_glass_blend_group.dart`, `GlassGroupLink`:
   `get shapeEntries => _shapes.entries.toList();` — called from
   `gatherShapeData`, `paintShapeContents`, `_buildDirectShapes`, and
   `gatherDirectComponents`, i.e. up to ~4 fresh lists per group per frame.
   Similarly `GeometryRenderLink.shapes`
   (`lib/src/rendering/liquid_glass_render_object.dart`) wraps the backing
   list in a new `UnmodifiableListView` per access and is read multiple
   times per paint.
5. **Logging StringBuffer built unconditionally** —
   `lib/src/rendering/liquid_glass_render_object.dart`,
   `_buildGeometryImage`: a `StringBuffer` is created and appended to in
   the per-shape loop, consumed only by `logger.fine(...)` at the end —
   even when logging is disabled (the default).
6. **Redundant transform walks and matrix clones** — same file, `paint()`:
   - `_directGroupSamplerTarget` calls `group.getTransformTo(null)` and
     `_resolveDirectGroupSampler` calls it again — per frame, on the
     single-group fast path that is specifically meant to be cheap.
   - `_previousMatteTransform = currentMatteTransform.clone();` allocates a
     `Matrix4` every frame even when the transform did not change.
   - `RenderLiquidGlassBlendGroup.paintShapeContents` calls
     `renderObject.getTransformTo(from)` per shape per pass.

Repo conventions: `@internal`/`@protected` annotations, trailing commas,
`lintervention` lints. There is an integration benchmark at
`packages/liquid_glass_renderer/example/integration_test/benchmark_test.dart`
(static, translating, and multi-widget scenarios).

## Commands you will need

| Purpose | Command (from repo root) | Expected on success |
|---------|--------------------------|---------------------|
| Analyze | `melos run analyze` | exit 0 |
| Tests (no goldens) | `melos run test-without-goldens` | all pass |
| Full tests | `melos run test` | all pass, zero golden diffs |

## Scope

**In scope**:
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_layer.dart`
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_render_object.dart`
- `packages/liquid_glass_renderer/lib/src/liquid_glass_blend_group.dart`

**Out of scope** (do NOT touch):
- Shader files — no shader change is part of this plan.
- `lib/src/internal/transform_tracking_repaint_boundary_mixin.dart` — the
  per-composite `getTransformTo` there is a separate finding (PERF-06),
  deliberately not planned; its invalidation semantics are subtle.
- The direct/component path *selection logic* — only allocation patterns.
- Texture lifecycle (`toImageSync` timing) — that is Plan 005.

## Git workflow

- One commit per step is preferred; messages like
  `perf: cache composed backdrop filters across frames`,
  `perf: avoid copying blend group shape entries per access`, etc.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Cache ImageFilters across frames

In `RenderLiquidGlassLayer` (`liquid_glass_layer.dart`):

- Add fields `ImageFilter? _cachedBlurFilter; double _cachedBlurSigma = -1;`.
  In `_pushGlassLayers` (and `paintLiquidGlassComponents`), replace the
  inline `ImageFilter.blur(...)` with a small helper:

  ```dart
  ImageFilter? _blurFilterFor(double sigma) {
    if (sigma <= 0) return null;
    if (_cachedBlurSigma != sigma) {
      _cachedBlurFilter = ImageFilter.blur(
        tileMode: TileMode.mirror,
        sigmaX: sigma,
        sigmaY: sigma,
      );
      _cachedBlurSigma = sigma;
    }
    return _cachedBlurFilter;
  }
  ```

- Cache the shader filter + composition the same way: the composed filter
  only changes when (a) the blur filter instance changes, (b) the shader
  instance changes, or (c) the gate from Plan 002 flips. Key the cache on
  those (`identical` checks are enough). IMPORTANT: `ImageFilter.shader`
  reads the shader's *uniforms at composite time* (see the comment on
  `_componentShaders` in this file), so reusing one `ImageFilter.shader`
  instance across frames is safe even while uniforms change — do NOT
  recreate it per frame to "refresh" uniforms.
- Invalidate the caches in the `settings` setter (the base class
  `LiquidGlassRenderObject.settings` setter already calls
  `markNeedsPaint()`; override or extend invalidation in
  `RenderLiquidGlassLayer` — simplest is to null the cached filters whenever
  `settings` changes and when `directRenderShader`/`componentShaders` are
  replaced).

**Verify**: `melos run test` → pass, zero golden diffs.

### Step 2: Cache the union clip Path

The union `Path` (used by the legacy blur fallback after Plan 002) is a pure
function of each shape's `GeometryCache.path` and its transform. Cache it on
`RenderLiquidGlassLayer`:

- Store `Path? _cachedClipPath;` plus a fingerprint:
  `List<(GeometryCache, Matrix4)>? _clipPathSource;` — rebuild the path only
  when length differs or any pair fails
  `identical(cache, old) && MatrixUtils.matrixEquals(transform, oldT)`.
- If after Plan 002 the union path is only needed on the legacy-blur branch,
  keep the caching inside that branch (Flutter < 3.44); the work is then
  skipped entirely on modern Flutter. Do not build the path at all when the
  composed branch is taken.

**Verify**: `melos run test` → pass.

### Step 3: Make `layout()` dirty geometry only on real change

In `LiquidGlassRenderObject` (`liquid_glass_render_object.dart`):

```dart
Constraints? _lastLayoutConstraints;

@override
void layout(Constraints constraints, {bool parentUsesSize = false}) {
  if (_lastLayoutConstraints != constraints) {
    needsGeometryUpdate = true;
    _lastLayoutConstraints = constraints;
  }
  super.layout(constraints, parentUsesSize: parentUsesSize);
}
```

Rationale: `BoxConstraints` implements `==`. If constraints are unchanged
the child layout is unchanged (size is a function of constraints here), so
the composite does not need a geometry rebuild from layout alone. Transform
changes are tracked separately via `TransformTrackingRenderObjectMixin`
(`onTransformChanged` sets `needsGeometryUpdate = true` in
`RenderLiquidGlassLayer`).

**Verify**: `melos run test` → pass. Additionally run the example app
(`cd packages/liquid_glass_renderer/example && flutter run --enable-impeller -d macos`)
and resize the window: glass must track layout correctly (resizing changes
constraints, so rebuilds still happen).

### Step 4: Stop copying shape collections per access

- `GlassGroupLink` (`liquid_glass_blend_group.dart`): cache the entries
  list, invalidated on mutation:

  ```dart
  List<MapEntry<RenderLiquidGlass, LiquidShape>>? _entriesCache;

  List<MapEntry<RenderLiquidGlass, LiquidShape>> get shapeEntries =>
      _entriesCache ??= List.unmodifiable(_shapes.entries);
  ```

  Set `_entriesCache = null` in `registerShape`, `unregisterShape`,
  `updateShape`, and `dispose`. (Type shown post-Plan-001; if 001 has not
  landed the value type is a record — STOP per drift rule.)
- `GeometryRenderLink.shapes` (`liquid_glass_render_object.dart`): same
  pattern — cache the `UnmodifiableListView`, invalidate in
  `registerGeometry`/`unregisterGeometry`/`dispose`. The backing list is
  only mutated through those methods.

**Verify**: `melos run test-without-goldens` → pass.

### Step 5: Guard the logging StringBuffer

In `_buildGeometryImage` (`liquid_glass_render_object.dart`), wrap the
buffer creation, the per-shape `writeln` calls, and the final
`logger.fine(buffer.toString())` in a single
`if (logger.isLoggable(Level.FINE)) { ... }` block (hoist the loop's
logging out of the drawing loop — keep drawing unconditional, logging
conditional; the simplest correct shape is a nullable
`StringBuffer? buffer = logger.isLoggable(Level.FINE) ? StringBuffer(...) : null;`
with `buffer?.writeln(...)` in the loop). `Level` comes from
`package:logging` (already imported via `src/logging.dart`).

**Verify**: `melos run analyze` → exit 0.

### Step 6: Reuse transforms, avoid per-frame clones

In `liquid_glass_render_object.dart`:

- `_directGroupSamplerTarget` already computes
  `group.getTransformTo(null)`; return it together with the group (change
  the helper to return `(RenderLiquidGlassGeometry, Matrix4)?`) and pass
  the matrix into `_resolveDirectGroupSampler` instead of calling
  `getTransformTo(null)` again.
- Replace the unconditional `_previousMatteTransform =
  currentMatteTransform.clone();` with: keep a single preallocated
  `Matrix4` and `setFrom(currentMatteTransform)` into it (no allocation),
  or only clone when `motionTransformChanged` is true. Preserve the exact
  semantics: `_previousMatteTransform` must reflect *this* frame's
  transform at the end of every paint.
- In `RenderLiquidGlassBlendGroup.paintShapeContents`
  (`liquid_glass_blend_group.dart`): the per-shape `getTransformTo(from)`
  is needed for correctness (each shape transforms independently); leave it
  but make sure it is not also recomputed in the same frame elsewhere for
  the same purpose — no change if no duplication is found.

**Verify**: `melos run test` → pass, zero golden diffs. Pay attention to
`liquid_glass_auto_test.dart` and blend-group tests — the motion heuristic
(`_consecutiveMotionFrames`) must behave identically; if any direct-mode
test starts flaking, STOP.

## Test plan

- No behavioral tests needed; the existing suite (especially goldens) is
  the regression net. All goldens must be byte-identical.
- Add one unit test in
  `packages/liquid_glass_renderer/test/src/liquid_glass_blend_group_test.dart`
  asserting `shapeEntries` returns the *same* list instance across two reads
  with no mutation, and a new instance after `registerShape` — this pins the
  cache-invalidation contract.
- Optional (do not block on it): run the integration benchmark before/after
  on a device and note frame-time deltas in the status row:
  `cd packages/liquid_glass_renderer/example && flutter test integration_test/benchmark_test.dart --enable-impeller -d macos`.

## Done criteria

- [ ] `melos run analyze` exits 0
- [ ] `melos run test` exits 0, zero golden diffs
- [ ] `rg -n "ImageFilter.blur" packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_layer.dart` shows construction only inside the cached helper
- [ ] `rg -n "entries.toList" packages/liquid_glass_renderer/lib` → no matches
- [ ] `_buildGeometryImage` builds no StringBuffer when FINE logging is off
- [ ] New `shapeEntries` caching test passes
- [ ] No files outside the in-scope list modified
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back if:

- Plans 001/002 have not landed (record types / blur layering don't match
  the excerpts).
- Any golden changes — every step here must be visually inert.
- Step 3 breaks window-resize tracking in the example app (constraints
  equality turns out not to cover a real invalidation source). Revert the
  step and report rather than adding heuristics.
- A cached `ImageFilter` produces stale rendering when settings change at
  runtime (toggle settings in the example app's controls to check) — the
  invalidation key is then incomplete; report what changed without being
  caught.

## Maintenance notes

- The filter/path caches add invalidation obligations: any future field
  that feeds `_pushGlassLayers` must also invalidate `_cachedComposedFilter`.
  Reviewer should check each new setter on `RenderLiquidGlassLayer`.
- PERF-06 (transform-tracking layers walking `getTransformTo(null)` on
  every composite) was found and deliberately deferred — revisit after
  Plan 006 settles the architecture.
- If Plan 006 replaces the composite bake, Steps 2 and 5 may be
  obsoleted — fine, they are cheap.
