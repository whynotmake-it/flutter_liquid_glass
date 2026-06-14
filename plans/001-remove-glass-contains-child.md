# Plan 001: Remove `glassContainsChild` and the vestigial `blend` parameter from the public API

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 85323b7..HEAD -- packages/liquid_glass_renderer/lib packages/liquid_glass_renderer/test packages/liquid_glass_renderer/README.md`
> If any in-scope file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: tech-debt (breaking API removal)
- **Planned at**: commit `85323b7`, 2026-06-11

## Why this matters

`glassContainsChild` lets a `LiquidGlass` child render "inside" the glass
(below the refraction shader, affected by tint). The maintainer has decided to
remove it entirely. Concretely this pays off in three ways:

1. It deletes an entire paint pass: the `insideGlass: true` traversal and the
   `ClipPathLayer` that exists solely to clip inside-glass children — one
   fewer engine layer per `LiquidGlassLayer` per frame.
2. It deletes a known rendering bug: since blur was composed into the glass
   shader filter (commit `b761e0c`), inside-glass children get blurred by the
   composed filter instead of rendering sharp above the blur. Removing the
   feature removes the bug.
3. It unblocks Plan 002 (Flutter-version-gated blur fallback) and Plan 006
   (per-shape matte caching), both of which get simpler when the inside-glass
   path no longer exists.

Additionally, `LiquidGlassSettings.copyWith` still accepts a `double? blend`
parameter that is silently ignored (blend moved to `LiquidGlassBlendGroup` in
0.2.0-dev.1). It must be removed.

The package is at `0.2.0-dev.4`; breaking changes are acceptable and must be
recorded as such in the changelog (this repo uses conventional commits and
melos changelog generation — see Git workflow).

## Current state

All paths relative to repo root `/Users/tim/Developer/flutter_liquid_glass`.

- `packages/liquid_glass_renderer/lib/src/liquid_glass.dart` — the public
  `LiquidGlass` widget. All four constructors take `this.glassContainsChild =
  false` (lines 41, 66, 83, 104), field declared at line 131, passed to
  `_RawLiquidGlass` at line 280. `RenderLiquidGlass` has a
  `_glassContainsChild` field + setter (lines 349–355) and passes it in
  `_registerWithLink`/`_updateBlendGroupLink` (lines 380–400).
- `packages/liquid_glass_renderer/lib/src/liquid_glass_blend_group.dart` —
  `GlassGroupLink._shapes` is typed
  `Map<RenderLiquidGlass, (LiquidShape shape, bool glassContainsChild)>`
  (lines 599–600). `registerShape`/`updateShape` take a required
  `glassContainsChild` named arg (lines 611–634). Consumers:
  - `gatherDirectComponents` line 291:
    `if (link.shapeEntries.any((e) => e.value.$2)) return null;` — component
    splitting bails when any shape draws its child inside the glass. This
    check must be deleted (always proceed).
  - `gatherShapeData` destructures `value: (shape, glassContainsChild)`
    (line 491) and forwards to `_computeShapeInfo` (lines 498–502, 553–587).
  - `paintShapeContents` (lines 532–551) filters on
    `renderObject.glassContainsChild != insideGlass`.
- `packages/liquid_glass_renderer/lib/src/internal/render_liquid_glass_geometry.dart`
  — abstract `paintShapeContents(..., {required bool insideGlass})` (lines
  188–193); `ShapeGeometry` carries `glassContainsChild` (field line 694,
  ctor line 665, equatable props line 702).
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_render_object.dart`
  — `paintShapeContents` helper (lines 618–633) with `insideGlass` param.
  Call sites with `insideGlass: true` (which paint inside-glass children):
  lines 219–235 (thickness <= 0 early path), 408–421 (debug-geometry path).
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_layer.dart`
  — `_pushGlassLayers` (lines 496–573). The `pushClipPath` block (lines
  525–552) exists ONLY to paint `insideGlass: true` children clipped to the
  union of shape paths:

  ```dart
  // liquid_glass_layer.dart:525-552 (current)
  final clipPath = Path();
  for (final geometry in shapes) {
    if (!geometry.$1.attached) continue;
    clipPath.addPath(
      geometry.$2.path,
      Offset.zero,
      matrix4: geometry.$3.storage,
    );
  }
  _clipPathLayerHandle.layer = context
      .pushClipPath(
        needsCompositing, offset, boundingBox, clipPath,
        (context, offset) {
          paintShapeContents(context, offset, shapes, insideGlass: true);
        },
        oldLayer: _clipPathLayerHandle.layer,
      );
  ```

  The whole block, the `_clipPathLayerHandle` field (line 290), and its
  disposal (line 578) go away. The `insideGlass: false` call inside the
  shader layer (lines 561–567) and in `paintLiquidGlassComponents`
  (line 415) become plain `paintShapeContents(context, offset, shapes)`.
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_filter.dart`
  — experimental, exported via `lib/experimental.dart`. Calls
  `paintShapeContents(..., insideGlass: true/false)` at lines 159–171. Both
  calls collapse into one without the parameter.
- `packages/liquid_glass_renderer/lib/src/liquid_glass_settings.dart` —
  `copyWith` has unused `double? blend` parameter at line 220. There is no
  `blend` field; nothing else references it.
- Tests: `packages/liquid_glass_renderer/test/src/liquid_glass_test.dart`
  uses `glassContainsChild: true` at lines 64 and 93 inside golden test
  groups ("square shape radius …" and "wide shape radius …" scenarios with a
  red container child).
- README: `packages/liquid_glass_renderer/README.md` lines ~312–318, the
  "### Child Placement" section documents the property.

Repo conventions: very_good_analysis-style lints via `lintervention`,
trailing commas, `@internal` on non-public classes. Match surrounding style.

## Commands you will need

| Purpose | Command (from repo root) | Expected on success |
|---------|--------------------------|---------------------|
| Analyze | `melos run analyze` | exit 0, no issues |
| Tests (no goldens) | `melos run test-without-goldens` | all pass |
| Full tests incl. goldens | `melos run test` | all pass (macOS + Impeller required) |
| Update goldens | `melos run update-goldens` | exits 0, rewrites PNGs |
| Grep gate | `rg -n "glassContainsChild|insideGlass" packages/liquid_glass_renderer/lib packages/liquid_glass_renderer/test` | no matches |

## Scope

**In scope** (the only files you should modify):
- `packages/liquid_glass_renderer/lib/src/liquid_glass.dart`
- `packages/liquid_glass_renderer/lib/src/liquid_glass_blend_group.dart`
- `packages/liquid_glass_renderer/lib/src/internal/render_liquid_glass_geometry.dart`
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_render_object.dart`
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_layer.dart`
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_filter.dart`
- `packages/liquid_glass_renderer/lib/src/liquid_glass_settings.dart`
- `packages/liquid_glass_renderer/test/src/liquid_glass_test.dart`
- `packages/liquid_glass_renderer/test/src/goldens/**` (regenerated only)
- `packages/liquid_glass_renderer/README.md`

**Out of scope** (do NOT touch):
- `packages/liquid_glass_renderer/lib/assets/shaders/**` — no shader reads
  inside-glass state; nothing to change there.
- `packages/liquid_glass_renderer/lib/src/fake_glass.dart` — FakeGlass never
  had `glassContainsChild`.
- `packages/apple_liquid_glass/**`.
- `CHANGELOG.md` — generated by melos on version; do not hand-edit.
- Pubspec version numbers.

## Git workflow

- Branch: work on the current branch unless the operator says otherwise.
- Commit message (conventional commits, matching `git log` style):
  `refactor!: remove glassContainsChild and unused blend copyWith parameter`
- Do NOT push or open a PR unless the operator instructed it.

## Steps

### Step 1: Remove the field from the `LiquidGlass` widget and render object

In `lib/src/liquid_glass.dart`:
- Delete the `glassContainsChild` parameter from all four constructors and
  the field + doc comment (lines 41, 66, 83, 104, 125–131).
- Delete it from `_RawLiquidGlass` (field, ctor, `createRenderObject`,
  `updateRenderObject`).
- In `RenderLiquidGlass`: delete `_glassContainsChild`, its getter/setter,
  and the named argument at the `registerShape`/`updateShape` call sites
  (`_registerWithLink`, `_updateBlendGroupLink`).

**Verify**: `rg -n "glassContainsChild" packages/liquid_glass_renderer/lib/src/liquid_glass.dart` → no matches.

### Step 2: Simplify `GlassGroupLink` and `ShapeGeometry`

In `lib/src/liquid_glass_blend_group.dart`:
- Change `GlassGroupLink._shapes` to `Map<RenderLiquidGlass, LiquidShape>`;
  drop the `glassContainsChild` named parameter from `registerShape` and
  `updateShape`; adjust `shapeEntries`'s type accordingly.
- Delete the bail-out in `gatherDirectComponents`
  (`if (link.shapeEntries.any((e) => e.value.$2)) return null;`, line 291)
  and its comment.
- Update `gatherShapeData` and `_computeShapeInfo` to stop destructuring and
  forwarding the flag.
- In `paintShapeContents`, remove the
  `renderObject.glassContainsChild != insideGlass` filter (keep the
  `!renderObject.attached` check) and remove the `insideGlass` parameter
  (after Step 3 changes the abstract signature).

In `lib/src/internal/render_liquid_glass_geometry.dart`:
- Remove `glassContainsChild` from `ShapeGeometry` (constructor, field,
  `props`).
- Remove `{required bool insideGlass}` from the abstract
  `paintShapeContents`.

**Verify**: `rg -n "glassContainsChild" packages/liquid_glass_renderer/lib` → no matches.

### Step 3: Delete the inside-glass paint pass

In `lib/src/rendering/liquid_glass_render_object.dart`:
- Remove the `insideGlass` parameter from the protected
  `paintShapeContents` helper (lines 618–633) and from every call site.
  Where a path currently calls it twice (`insideGlass: true` then `false`
  — lines 219–235 and 408–421), collapse to a single call.

In `lib/src/rendering/liquid_glass_layer.dart`:
- In `_pushGlassLayers`: delete the `clipPath` construction and the entire
  `pushClipPath` block (lines 525–552); delete `_clipPathLayerHandle`
  (declaration line 290 and disposal line 578). Keep the `pushClipRect` +
  shader layer block; its inner `paintShapeContents` call loses the
  `insideGlass:` argument. Also update the stale comment "If glass contains
  child we paint it above blur but below shader" — children now always paint
  above the glass.
- In `paintLiquidGlassComponents`: drop `insideGlass: false` (line 415) and
  update the comment about component splitting no longer being conditional
  on child placement.

In `lib/src/rendering/liquid_glass_filter.dart`:
- Collapse the two `paintShapeContents` calls (lines 159–171) into one
  without the parameter.

**Verify**: `rg -n "insideGlass" packages/liquid_glass_renderer/lib` → no matches; `melos run analyze` → exit 0.

### Step 4: Remove `blend` from `LiquidGlassSettings.copyWith`

Delete the `double? blend,` parameter (line 220 of
`lib/src/liquid_glass_settings.dart`). It is read nowhere in the body.

**Verify**: `rg -n "blend" packages/liquid_glass_renderer/lib/src/liquid_glass_settings.dart` → no matches.

### Step 5: Update tests and README, regenerate goldens

- In `test/src/liquid_glass_test.dart`, remove `glassContainsChild: true`
  at lines 64 and 93. The scenarios remain (the red child now renders on top
  of the glass instead of inside it).
- Delete the "### Child Placement" section from
  `packages/liquid_glass_renderer/README.md` (lines ~312–318).
- Regenerate goldens: `melos run update-goldens`. The affected goldens are
  the rounded-superellipse radius/thickness groups under
  `test/src/goldens/macos/` — expect visual diffs ONLY in scenarios that
  previously used `glassContainsChild: true` (the child will no longer be
  tinted/refracted).

**Verify**:
- `rg -n "glassContainsChild" packages/liquid_glass_renderer` → no matches.
- `melos run test` → all pass.

## Test plan

- No new tests: this removes behavior. The existing golden suite
  (`test/src/liquid_glass_test.dart`) is the regression net — confirm the
  regenerated goldens only differ where inside-glass children were used.
- `melos run test-without-goldens` must pass without any golden update,
  proving non-golden behavior is unchanged.

## Done criteria

- [ ] `melos run analyze` exits 0
- [ ] `melos run test` exits 0 (goldens regenerated where expected)
- [ ] `rg -rn "glassContainsChild|insideGlass" packages/liquid_glass_renderer/lib packages/liquid_glass_renderer/test` returns no matches
- [ ] `_clipPathLayerHandle` no longer exists in `liquid_glass_layer.dart`
- [ ] `LiquidGlassSettings.copyWith` has no `blend` parameter
- [ ] README has no "Child Placement" section
- [ ] No files outside the in-scope list modified (`git status`)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- Any "Current state" excerpt no longer matches the live code (drift).
- Removing the `pushClipPath` block changes goldens in scenarios that did
  NOT use `glassContainsChild: true` (this would mean the clip had a side
  effect this plan didn't account for).
- You find another consumer of `glassContainsChild` outside the in-scope
  files (e.g. in `example/`); report it rather than editing out-of-scope
  files. (Recon found none, but the example app is large.)
- Tests fail for reasons unrelated to golden diffs after two fix attempts.

## Maintenance notes

- Plan 002 (Flutter version gate for composed blur) assumes the inside-glass
  pass is gone; execute this plan first.
- Plan 006 (per-shape matte caching) also assumes single-pass child painting.
- Reviewer should scrutinize: the `gatherDirectComponents` bail-out removal —
  component splitting now engages in layouts it previously skipped; verify
  the sparse blend-group golden (`sparse_blend_group.png`) is unchanged.
- Deferred: none.
