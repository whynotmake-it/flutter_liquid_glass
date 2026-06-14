# Plan 004: Fix three small defects in the new direct/component fast paths

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 85323b7..HEAD -- packages/liquid_glass_renderer/lib/src/liquid_glass_blend_group.dart packages/liquid_glass_renderer/lib/src/rendering`
> Locate excerpts by symbol; line numbers may have shifted after Plans
> 001–003. On a structural mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S–M
- **Risk**: LOW
- **Depends on**: plans/001-remove-glass-contains-child.md (Fix B touches code 001 modifies)
- **Category**: bug
- **Planned at**: commit `85323b7`, 2026-06-11

## Why this matters

The branch's performance fast paths (texture-less direct rendering during
animation, connected-component splitting, translation reuse) carry three
small defects: a wrong blend scale when grouped shapes have different
scales, a renderer "pop" when the asynchronously loaded component shaders
arrive, and a redundant composite re-bake when a translation ends. Each is
cheap to fix and tightens the paths the rest of the perf work builds on.

## Current state

All in `packages/liquid_glass_renderer/` (paths relative to repo root).

**Fix A — direct-mode blend uses only the first shape's scale.**
`lib/src/liquid_glass_blend_group.dart`, `gatherDirectShapeData`:

```dart
final referenceScale = shapes.first.meanScale;
...
final blendPhysical = blend * devicePixelRatio * referenceScale;
return [shapes.length.toDouble(), blendPhysical, ...data];
```

`blend` is a single scalar uniform for the whole group
(`uShapeConfig.y` in `lib/assets/shaders/liquid_glass_direct_render.frag`),
but each shape may be under a different ancestor scale. The per-component
path has the same single-scalar shape (`group.first.meanScale` in
`gatherDirectComponents`). Since the shader accepts only one blend value,
the correct single choice is the mean of the participating shapes'
`meanScale`s rather than whichever shape happens to be first (order is map
insertion order — arbitrary from the user's perspective).

**Fix B — component splitting silently off until async shader load.**
`lib/src/rendering/liquid_glass_layer.dart`,
`_LiquidGlassLayerState`:

```dart
@override
void initState() {
  super.initState();
  _loadComponentShaders();
}

Future<void> _loadComponentShaders() async {
  try {
    final program = await FragmentProgram.fromAsset(
      ShaderKeys.liquidGlassDirectRender,
    );
    if (!mounted) return;
    setState(() {
      _componentShaders = List.generate(
        _maxComponentPasses,
        (_) => program.fragmentShader(),
      );
    });
  ...
```

Meanwhile the same program is *also* loaded by `MultiShaderBuilder` in
`build()` (asset key `ShaderKeys.liquidGlassDirectRender` is `assetKeys[1]`,
yielding the `directRenderShader`). Until `_loadComponentShaders` completes,
`RenderLiquidGlassLayer.gatherDirectComponents` returns null
(`if (shaders == null) return null;`) and sparse layouts render via the
union-AABB composite, then visibly switch strategy a frame or two later.
`MultiShaderBuilder` is at
`lib/src/internal/multi_shader_builder.dart` — read it before this fix; it
exposes loaded `FragmentShader`s to its builder callback. `FragmentProgram`
instances per asset are cached by the engine, and additional
`fragmentShader()` instances can be created synchronously from a loaded
program. The clean fix: derive the component shader instances inside the
`MultiShaderBuilder` callback (which already has the loaded program's
shader) instead of a second async load. `MultiShaderBuilder` may need to
expose the `FragmentProgram` (not just one `FragmentShader`) — check its
implementation; if it only stores shaders, extend it to also provide
programs.

**Fix C — `link._dirty` survives the translation-reuse path.**
`lib/src/rendering/liquid_glass_render_object.dart`, `paint()`:

```dart
} else if (canReuseByTranslation) {
  needsGeometryUpdate = false;
  _geometryMatteBounds = _shiftMatteBounds(...);
  _lastBakedMatteTransform = currentMatteTransform;
} else if (compositeNeedsRebuild) {
  link.updateAllGeometries();
  _clearGeometryImage();
  link._dirty = false;
  ...
```

The reuse branch leaves `link._dirty == true` (it can be set by a deferred
matte bake via `markRebuilt` without any visible geometry change). Result:
on the first frame after the translation stops, `compositeNeedsRebuild` is
still true and the composite re-bakes a texture identical to the one it
already has. The reuse branch should consume the dirty flag the same way
the rebuild branch does, *but only when* no full rebuild happened this
frame (`link._hadFullRebuild == false` — which is already guaranteed by
`canReuseByTranslation`'s definition:
`compositeNeedsRebuild && _geometryImage != null && !link._hadFullRebuild && translationOnlyChange`).

## Commands you will need

| Purpose | Command (from repo root) | Expected on success |
|---------|--------------------------|---------------------|
| Analyze | `melos run analyze` | exit 0 |
| Tests (no goldens) | `melos run test-without-goldens` | all pass |
| Full tests | `melos run test` | all pass |

## Scope

**In scope**:
- `packages/liquid_glass_renderer/lib/src/liquid_glass_blend_group.dart`
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_layer.dart`
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_render_object.dart`
- `packages/liquid_glass_renderer/lib/src/internal/multi_shader_builder.dart`
- `packages/liquid_glass_renderer/test/src/liquid_glass_blend_group_test.dart` (extend)

**Out of scope** (do NOT touch):
- Shader files.
- The direct-mode entry/exit heuristic (`_consecutiveMotionFrames`) — the
  hysteresis question (BUG-05 in the audit) is deliberately not in scope.
- `GeometryCache` lifecycle (Plan 005).

## Git workflow

- Suggested commits:
  `fix: scale direct-mode blend by the group's mean scale`,
  `fix: create component shaders synchronously from the loaded program`,
  `fix: consume link dirty flag on translation reuse`.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1 (Fix A): Mean scale for the direct blend uniform

In `gatherDirectShapeData` (`liquid_glass_blend_group.dart`), replace
`shapes.first.meanScale` with the arithmetic mean of all shapes'
`meanScale`. Apply the same change in `gatherDirectComponents` where
`group.first.meanScale` is used per component (mean over that component's
shapes). Keep everything else identical.

**Verify**: `melos run test` → pass (goldens use uniform scale, so no diffs
expected; if a golden diffs, STOP).

### Step 2 (Fix B): Synchronous component shader creation

1. Read `lib/src/internal/multi_shader_builder.dart`.
2. Extend it minimally so the builder callback can access the loaded
   `FragmentProgram` for each asset key (e.g. provide
   `List<FragmentProgram> programs` alongside the existing shaders, or a
   record). Keep the existing callback signature working for other call
   sites (`rg -n "MultiShaderBuilder" packages/liquid_glass_renderer/lib`
   to find them all).
3. In `_LiquidGlassLayerState`: delete `_loadComponentShaders`, the
   `initState` override, and the `_componentShaders` state field. Inside
   the `MultiShaderBuilder` callback, create the component shaders once
   (memoize on the program instance — recreate only if the program changes,
   e.g. on hot restart):

   ```dart
   _componentShaders ??= List.generate(
     _maxComponentPasses,
     (_) => directRenderProgram.fragmentShader(),
   );
   ```

   Where `_componentShaders` is now a plain field on the State (no
   setState needed — it is available before the first frame paints because
   `MultiShaderBuilder` only invokes the builder once assets are loaded).
4. Keep `_maxComponentPasses = 4` where it is.

**Verify**:
- `melos run test` → pass.
- `rg -n "_loadComponentShaders" packages/liquid_glass_renderer` → no
  matches.

### Step 3 (Fix C): Consume the dirty flag on translation reuse

In the `canReuseByTranslation` branch of
`LiquidGlassRenderObject.paint()` add `link._dirty = false;`:

```dart
} else if (canReuseByTranslation) {
  needsGeometryUpdate = false;
  link._dirty = false;
  _geometryMatteBounds = _shiftMatteBounds(...);
  _lastBakedMatteTransform = currentMatteTransform;
}
```

Add a brief comment: the texture was reused as-is, so any pending
deferred-bake dirtiness is satisfied; a genuine shape change would have set
`link._hadFullRebuild`, which excludes this branch.

**Verify**: `melos run test` → pass, especially
`test/src/liquid_glass_test.dart` and `liquid_glass_auto_test.dart` (these
exercise translation scenarios).

## Test plan

- Extend `test/src/liquid_glass_blend_group_test.dart`:
  - A widget test with two grouped shapes under different `Transform.scale`
    ancestors driving an animation for ≥3 pumped frames (to engage direct
    mode), asserting it renders without exceptions. (Asserting the exact
    blend value is impractical in a widget test; the unit-level contract is
    pinned by reviewing `gatherDirectShapeData`'s return — if the repo's
    test utilities expose `RenderLiquidGlassBlendGroup` (it is
    `@visibleForTesting`), add a direct unit test:
    build the render object, register two shapes with scales 1.0 and 3.0,
    and assert the returned `blendPhysical` equals
    `blend * dpr * 2.0` (the mean).)
  - For Fix C: pump a glass widget, translate it for several frames, stop,
    and assert via `LiquidGlassRenderObject` internals
    (`@visibleForTesting geometry`/state where exposed) that no additional
    composite bake occurred on the settle frame. If internals are not
    reachable cleanly, skip this assertion and note it in the status row —
    do not add new test-only hooks beyond `@visibleForTesting` on an
    existing member.
- All existing tests must stay green with zero golden diffs.

## Done criteria

- [ ] `melos run analyze` exits 0
- [ ] `melos run test` exits 0, zero golden diffs
- [ ] `rg -n "first.meanScale" packages/liquid_glass_renderer/lib` → no matches
- [ ] Component shaders are created synchronously in the builder (no async load, no setState)
- [ ] Translation-reuse branch clears `link._dirty`
- [ ] New/extended blend-group tests pass
- [ ] No files outside the in-scope list modified
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back if:

- `MultiShaderBuilder` turns out not to retain the `FragmentProgram` and
  extending it would require reworking its public contract used elsewhere —
  report the call sites and the smallest viable change instead of doing a
  large refactor.
- Any golden diffs (all three fixes must be visually inert in the test
  scenarios).
- Fix C causes a test to observe a *missing* rebake (i.e. a scenario where
  the dirty flag being left set was actually load-bearing). Revert Fix C
  and report the scenario.

## Maintenance notes

- Fix B makes component splitting active from the first frame; profiling
  comparisons before/after this branch should account for that.
- If the 16-shape cap is ever revisited (audit finding BUG-08: the 17th
  grouped shape throws on the texture path but silently degrades on direct
  paths), `_buildDirectShapes`'s early return is the place both paths
  should converge on a single failure mode. Deferred, not planned.
- Reviewer should scrutinize: shader instance lifetime in Fix B across hot
  restart (program identity change must recreate the four instances).
