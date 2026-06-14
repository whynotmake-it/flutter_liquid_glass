# Plan 005: Rasterize settle-frame mattes asynchronously, bridging with the direct render path

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 85323b7..HEAD -- packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_render_object.dart packages/liquid_glass_renderer/lib/src/internal/render_liquid_glass_geometry.dart`
> Plans 001–004 are expected to have landed; locate excerpts by symbol.
> On a structural mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: plans/004-fast-path-polish.md (component shaders must be synchronously available so the direct bridge is reliable)
- **Category**: perf
- **Planned at**: commit `85323b7`, 2026-06-11

## Why this matters

Every geometry change today blocks the UI isolate on `Picture.toImageSync`
(per-shape matte in `UnrenderedGeometryCache.render()`, plus the layer-wide
composite in `_buildGeometryImage`). Combined with delayed texture disposal
(flutter/flutter#138627), rapid geometry changes both jank the UI thread
and stack full-resolution textures in memory — the package's known memory
spike. An async API already exists (`UnrenderedGeometryCache.renderAsync`)
but nothing uses it.

**The stale-matte concern, addressed up front**: a matte only needs
re-baking when geometry actually changed, and during *sustained* change the
renderer is already on the texture-less direct path (no matte involved).
The risky moment is the settle frame — geometry stopped changing, a fresh
matte is needed. This plan makes that bake async and keeps rendering via
the direct path until the bake lands, so a stale matte is **never
displayed**: frames are either direct-rendered from current uniforms or
texture-rendered from a matte that matches current geometry. Where no
direct bridge exists (rotated shapes, multiple groups/layers geometry), the
bake stays synchronous — no behavior change there.

A generation counter guards against out-of-order completion: a bake that
finishes after geometry changed again is dropped (and its image disposed).

## Current state

All in `packages/liquid_glass_renderer/` (paths relative to repo root).

- `lib/src/rendering/liquid_glass_render_object.dart`, `paint()` — the
  decision ladder, in order: direct mode (sustained motion, ≥2 frames) →
  component splitting → single-group direct sampling → translation reuse →
  composite rebuild. The composite rebuild branch:

  ```dart
  } else if (compositeNeedsRebuild) {
    link.updateAllGeometries();
    _clearGeometryImage();
    link._dirty = false;
    needsGeometryUpdate = false;
    final (image, matteBounds) = _buildGeometryImage(
      shapesWithGeometry,
      boundingBox,
    );
    _geometryImage = image;
    _geometryMatteBounds = matteBounds;
    _lastBakedMatteTransform = currentMatteTransform;
  }
  ```

  `_buildGeometryImage` ends with `picture.toImageSync(...)` and runs when
  geometry settles after direct mode (which cleared the texture and
  consumed the flags) or on any one-off change.
- Direct mode exit: when motion stops, `_consecutiveMotionFrames` resets,
  `gatherDirectShapeUniforms()` is not consulted (`>= 2` gate), and the
  composite branch re-bakes synchronously. The capability check for direct
  rendering is `gatherDirectShapeUniforms()` returning non-null
  (`RenderLiquidGlassLayer` override: exactly one geometry in `link.shapes`
  and `gatherDirectShapeData` finds only axis-aligned transforms).
- `lib/src/internal/render_liquid_glass_geometry.dart`:
  - `UnrenderedGeometryCache.render()` — sync `toImageSync`, disposes the
    picture, returns `RenderedGeometryCache`.
  - `UnrenderedGeometryCache.renderAsync()` — same via `await
    matte.toImage(...)`; **currently unused** and, unlike `render()`, it
    does NOT call `dispose()` on itself — if you use it, the source picture
    must be disposed by the caller after success (check this when wiring;
    fix the asymmetry inside `renderAsync` by disposing the picture after
    the await, mirroring `render()`).
  - `maybeRebuildGeometry()` — per-shape path; for the *nine-slice* case it
    eagerly calls `.render()` (tiny texture — leave synchronous), otherwise
    returns an `UnrenderedGeometryCache` whose `render()` is deferred to
    composite/sampling time.
  - `ensureRenderedMatte()` — sync `render()` used by the single-group
    direct-sampling path.

## Commands you will need

| Purpose | Command (from repo root) | Expected on success |
|---------|--------------------------|---------------------|
| Analyze | `melos run analyze` | exit 0 |
| Tests (no goldens) | `melos run test-without-goldens` | all pass |
| Full tests | `melos run test` | all pass, zero golden diffs on static scenarios |
| Benchmark (manual) | `cd packages/liquid_glass_renderer/example && flutter test integration_test/benchmark_test.dart --enable-impeller -d macos` | completes; note numbers |

## Scope

**In scope**:
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_render_object.dart`
- `packages/liquid_glass_renderer/lib/src/internal/render_liquid_glass_geometry.dart`
- `packages/liquid_glass_renderer/test/src/liquid_glass_test.dart` (extend)

**Out of scope** (do NOT touch):
- The per-shape nine-slice eager render (tiny; not a spike source).
- `ensureRenderedMatte()` — the single-group sampling path renders at most
  once per geometry change and the direct bridge below already covers the
  settle frame; making it async too adds complexity for no measured win.
- Shaders, blend group logic, FakeGlass.
- Plan 006's architecture — this plan must not restructure the composite;
  it only changes *when* the existing bake happens.

## Git workflow

- Commit message: `perf: bake settle-frame composite asynchronously, bridging with direct rendering`
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Add an async composite bake with generation guard

In `LiquidGlassRenderObject` add:

```dart
int _bakeGeneration = 0;
bool _asyncBakeInFlight = false;
```

Add a method `_startAsyncCompositeBake(...)` that mirrors
`_buildGeometryImage` but ends with `picture.toImage(w, h)` instead of
`toImageSync`. Factor the shared picture-recording part of
`_buildGeometryImage` into a private helper returning
`(Picture, Rect matteBounds, int w, int h)` so sync and async paths cannot
drift. On completion:

```dart
final generation = ++_bakeGeneration;
_asyncBakeInFlight = true;
picture.toImage(w, h).then((image) {
  _asyncBakeInFlight = false;
  picture.dispose();
  if (generation != _bakeGeneration || !attached) {
    image.dispose();
    return;
  }
  _geometryImage?.dispose();
  _geometryImage = image;
  _geometryMatteBounds = matteBounds;
  _lastBakedMatteTransform = bakedTransform;
  markNeedsPaint();
});
```

Every code path that invalidates geometry (`_clearGeometryImage`, the
direct-mode entry, the rebuild branch) must bump `_bakeGeneration` so
stale completions are dropped. Put the bump inside `_clearGeometryImage`
plus at the top of the sync rebuild branch.

### Step 2: Bridge the settle frame through the direct path

In `paint()`, in the `compositeNeedsRebuild` branch, choose async only when
a same-frame fallback renderer exists:

```dart
} else if (compositeNeedsRebuild) {
  link.updateAllGeometries();
  link._dirty = false;
  needsGeometryUpdate = false;

  final bridgeUniforms = debugPaintLiquidGlassGeometry
      ? null
      : gatherDirectShapeUniforms();

  if (bridgeUniforms != null && !_asyncBakeInFlight) {
    // Async bake + direct-render this frame. No stale texture is shown:
    // until the bake lands we draw from current uniforms.
    _clearGeometryImage();
    _startAsyncCompositeBake(shapesWithGeometry, boundingBox,
        currentMatteTransform);
    paintLiquidGlassDirect(
        context, offset, shapesWithGeometry, _paintBounds, bridgeUniforms);
    super.paint(context, offset);
    return;
  }

  // No bridge available (rotation, multi-geometry, debug mode): keep the
  // synchronous bake exactly as before.
  _clearGeometryImage();
  final (image, matteBounds) = _buildGeometryImage(...);
  ...
}
```

Details that matter:
- While `_asyncBakeInFlight` and geometry changes *again*, the normal
  ladder applies on the next paint (likely direct mode); the generation
  guard discards the in-flight result.
- If the async bake is in flight and a paint happens with unchanged
  geometry (e.g. unrelated repaint), `compositeNeedsRebuild` is false
  (flags were consumed) and `_geometryImage` is null — the existing code
  at the sampler step handles a null image by skipping the glass pass.
  That would FLICKER. Prevent it: when `_geometryImage == null &&
  _asyncBakeInFlight`, render via `gatherDirectShapeUniforms()` again
  (add this guard before the sampler step). If uniforms are unavailable
  there (shouldn't happen — availability was just checked when the bake
  started), fall back to a synchronous bake; do not skip the frame.
- `_lastBakedMatteTransform` must be set from the transform captured at
  bake start (pass it into `_startAsyncCompositeBake`), not from the
  transform at completion time.

### Step 3: Fix `renderAsync`'s picture lifetime

In `render_liquid_glass_geometry.dart`, make
`UnrenderedGeometryCache.renderAsync()` dispose `matte` (and the scaled
intermediate, which it already does) after the image is produced, mirroring
`render()`. It remains unused by this plan's hot path (the composite bake
records its own picture), but it must not stay subtly leaky. Add a doc
comment stating the cache must not be used after calling it.

**Verify** (Steps 1–3 together): `melos run analyze` → exit 0;
`melos run test` → pass. Static goldens are bit-identical because static
scenes never hit the bridge (no motion → texture path with existing sync
behavior on first bake — note: the FIRST bake of a fresh layer goes through
`compositeNeedsRebuild` with `bridgeUniforms` likely available; in tests
each scenario pumps once and settles, so verify goldens still pass — the
direct render is designed to be pixel-identical to the texture path, and
the bake lands before the next pump with `markNeedsPaint`. If any golden
diffs appear, restrict the bridge to frames where a direct render is
strictly necessary: only use the async path when `_geometryImage == null`
*because direct mode just exited* — i.e. add `_wasDirectLastFrame` state —
and keep first-ever bakes synchronous.)

### Step 4: Regression test

Extend `test/src/liquid_glass_test.dart` with a non-golden widget test:

1. Pump a `LiquidGlassLayer` + `LiquidGlass` inside an
   `AnimatedPositioned`-style animation (or drive a `Transform.translate`
   via `AnimationController`) for 5 frames (`tester.pump` ×5 with
   16ms steps) — direct mode engages.
2. Stop the animation; pump one frame — the settle frame (async bake
   kicks off, direct bridge paints). Expect no exceptions.
3. `await tester.pump(const Duration(milliseconds: 50));` then
   `await tester.pumpAndSettle();` — bake landed, texture path resumed.
   Expect no exceptions and the render object's `geometryImage`-backing
   state non-null if accessible via `@visibleForTesting` members (the
   `geometry` field on `RenderLiquidGlassGeometry` is `@visibleForTesting`;
   for the layer's composite, assert indirectly: no exception + a further
   pump paints without scheduling another bake).
4. Rapid-change test: change the shape's size every frame for 10 frames
   while the bake is in flight; expect no exception (generation guard) and
   no `Image` double-dispose errors.

## Test plan

- New widget tests per Step 4 (settle-frame bridge, rapid-change guard).
- Full golden suite unchanged: `melos run test` → zero diffs.
- Manual: run the example app, animate a sheet/drag interaction, confirm
  no flicker at animation end (settle frame) and lower jank than before
  (DevTools frame chart; note observations in the status row).

## Done criteria

- [ ] `melos run analyze` exits 0
- [ ] `melos run test` exits 0, zero golden diffs
- [ ] `rg -n "toImageSync" packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_render_object.dart` shows it only in the no-bridge fallback path
- [ ] Settle-after-animation paints via the direct bridge (new test passes)
- [ ] Rapid-change test passes (no use-after-dispose / double-dispose)
- [ ] `renderAsync` disposes its picture
- [ ] No files outside the in-scope list modified
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back if:

- Plans 001–004 have not landed (the paint ladder doesn't match excerpts).
- Goldens diff after Step 3's verification *and* the `_wasDirectLastFrame`
  restriction described there doesn't resolve it — the direct/texture
  parity assumption would then be broken, which is a finding of its own.
- You observe a frame where neither a texture nor a direct render is
  available (blank glass) in any test or in the example app — the bridge
  has a hole; report the exact path through `paint()` that produced it.
- `picture.toImage` on Impeller turns out to still block the raster thread
  in a way that defeats the purpose (verify via DevTools timeline if
  results look surprising) — report findings; do not pile on workarounds.

## Maintenance notes

- Plan 006 (per-shape matte caching) will reshape `_buildGeometryImage`;
  the factored picture-recording helper from Step 1 is the integration
  point. Keep the generation-guard pattern — it transfers directly.
- Reviewer should scrutinize: every `_geometryImage` assignment/dispose
  site for interaction with the in-flight future; the
  `!attached` guard in the completion callback.
- Deferred: making `ensureRenderedMatte()` async (single-group sampling
  path) — revisit only if profiling shows it on the spike path.
