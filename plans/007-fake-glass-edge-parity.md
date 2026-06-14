# Plan 007: Make FakeGlass's edge outline extend past the highlight, matching the shader

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 85323b7..HEAD -- packages/liquid_glass_renderer/lib/src/fake_glass.dart packages/liquid_glass_renderer/lib/assets/shaders/liquid_glass_final_render.frag`
> If `_paintSpecular` no longer matches the excerpt below, STOP.

## Status

- **Priority**: P3
- **Effort**: M
- **Risk**: MED (visual change by design; goldens will diff)
- **Depends on**: none (independent; if Plan 008 lands first, the
  settings member may be named `highlightInset` — adapt names accordingly)
- **Category**: bug / visual parity
- **Planned at**: commit `85323b7`, 2026-06-11

## Why this matters

`FakeGlass` is the cheap stand-in for the shader-based glass (used on Skia
and via `LiquidGlassLayer.fake`). The real shader renders two distinct rim
features:

1. an **edge outline** (`edgeColor`) occupying the outermost band of the
   rim, `[0, edgeWidth]` measured inward from the shape boundary, drawn all
   the way around (ducked only where the specular highlight is strong), and
2. a **specular highlight** (`highlightColor`) that starts *inset* from the
   boundary by `edgeWidth * edgeInset` and falls off inward.

So the edge sits OUTSIDE the highlight and extends past it. FakeGlass
currently draws a single centered stroke (~1–2 px) carrying both colors in
one gradient, so the edge never extends past the highlight and `edgeWidth`
/ `edgeInset` have no geometric effect at all. The maintainer wants the
fake rendering to match the outline+highlight structure.

## Current state

- `packages/liquid_glass_renderer/lib/src/fake_glass.dart`,
  `_RenderFakeGlass._paintSpecular` (lines ~356–448) — the part to replace:

  ```dart
  // fake_glass.dart (current, abbreviated)
  final shader = LinearGradient(
    colors: [highlightColor, softEdgeColor, softEdgeColor, highlightColor],
    stops: [inset, edgeStart, edgeEnd, 1 - inset],
    begin: Alignment(x, y),
    end: Alignment(-x, -y),
  ).createShader(squareBounds);

  final paint = Paint()
    ..shader = shader
    ..style = PaintingStyle.stroke
    ..strokeWidth = ui.lerpDouble(1, 2, lightIntensity)!
    ..blendMode = BlendMode.hardLight;
  canvas.drawPath(path, paint);

  final overlay = Paint()
    ..shader = shader
    ..style = PaintingStyle.stroke
    ..strokeWidth = (settings.effectiveThickness / 24)
    ..blendMode = BlendMode.overlay;
  canvas.drawPath(path, overlay);
  ```

  Geometry facts about this call site:
  - The canvas is already clipped to the shape (`FakeGlass.build` wraps
    everything in `OptimizedClip(shape: shape, ...)`), so a centered stroke
    of width `2w` on `path` renders as an inward band of width `w`.
  - `path` is `shape.getOuterPath(offset & size)`; `bounds` is
    `offset & size`. `LiquidShape.getOuterPath` exists for all three shape
    types (see `lib/src/liquid_shape.dart`); insetting via
    `shape.getOuterPath(bounds.deflate(d))` is valid for all of them.
  - The existing gradient construction (light-angle alignment, aspect-ratio
    compensation via `squareBounds`, `lightCoverage`, `gradientScale`) is
    good and should be REUSED for the highlight stroke — only the
    color list changes (no `edgeColor` in the highlight gradient anymore).
- Shader reference for the target structure
  (`lib/assets/shaders/liquid_glass_final_render.frag`,
  `applySpecularHighlights`):

  ```glsl
  float edgeWidth = min(max(uEdgeWidth, 0.0), opticalThickness * 0.5);
  float highlightInset = edgeWidth * clamp(uEdgeInset, 0.0, 1.0);
  // outline: band [0, edgeWidth] from the boundary, alpha uEdgeColor.a,
  //          "ducked" (faded) where the highlight is strong
  // highlight: starts at highlightInset, falls off inward over ~thickness
  ```

- Relevant settings (`lib/src/liquid_glass_settings.dart`):
  `edgeColor`/`effectiveEdgeColor`, `edgeWidth`/`effectiveEdgeWidth`,
  `edgeInset` (0..1, default 0.5), `highlightColor`,
  `effectiveLightIntensity`, `specularWrap`, `ambientStrength`,
  `lightAngle`, `effectiveThickness`.
- Existing FakeGlass tests:
  `packages/liquid_glass_renderer/test/src/fake_glass_test.dart` with
  goldens `fake_glass_*.png` under `test/src/goldens/macos/`.

## Commands you will need

| Purpose | Command (from repo root) | Expected on success |
|---------|--------------------------|---------------------|
| Analyze | `melos run analyze` | exit 0 |
| Tests (no goldens) | `melos run test-without-goldens` | all pass |
| Update goldens | `melos run update-goldens` | rewrites fake-glass PNGs |
| Full tests | `melos run test` | all pass after golden update |
| Visual compare | run example app, toggle `fake` on a layer with `edgeColor`/`edgeWidth` set | edge visibly outside highlight, like the shader |

## Scope

**In scope**:
- `packages/liquid_glass_renderer/lib/src/fake_glass.dart` (only
  `_paintSpecular` and small private helpers it needs)
- `packages/liquid_glass_renderer/test/src/fake_glass_test.dart` (extend)
- `packages/liquid_glass_renderer/test/src/goldens/macos/fake_glass_*.png`
  (regenerated)

**Out of scope** (do NOT touch):
- The real shader (`liquid_glass_final_render.frag` etc.) — it is the
  reference, not the patient.
- `GlassShadow`, `OptimizedClip`, blur/saturation layers in
  `fake_glass.dart` — only the specular painting changes.
- `LiquidGlassSettings` — no new settings. (Plan 008 renames a member;
  independent.)

## Git workflow

- Commit message: `fix: FakeGlass edge outline now extends past the inset highlight to match the shader`
- The goldens label is required for golden CI on PRs (see CLAUDE.md);
  note that in the PR description if one is opened.
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Compute the band geometry like the shader does

In `_paintSpecular`, derive (all logical px):

```dart
final opticalThickness = math.max(settings.effectiveThickness, 1.0);
final edgeWidth = settings.effectiveEdgeWidth
    .clamp(0.0, opticalThickness * 0.5);
final highlightInset = edgeWidth * settings.edgeInset.clamp(0.0, 1.0);
```

(If Plan 008 has landed, the last line reads `settings.highlightInset`.)

### Step 2: Draw the edge outline as the outermost ring

Replacing the current single-stroke approach, first draw the edge ring
(only when `edgeWidth > 0 && edgeColor.a > 0`):

- Stroke `path` with `strokeWidth = edgeWidth * 2` — the clip keeps the
  inner half, giving exactly the `[0, edgeWidth]` inward band.
- Color: keep today's derived `softEdgeColor`/`edgeColor` alpha treatment
  (the `0.95 * easeOut(lerp(0.35, 1, specularWrap))` and ambient terms in
  the current code) so overall intensity tuning is preserved — but paint it
  as a UNIFORM ring (plain color, no gradient): in the shader the outline
  goes all the way around.
- Approximate the shader's "edge ducking" (outline fading where the
  highlight is strong): draw the ring with a gradient whose alpha dips at
  the two light poles — reuse the existing gradient stop machinery with
  colors `[duckedEdge, edge, edge, duckedEdge]` where
  `duckedEdge = edgeColor.withValues(alpha: edgeColor.a * 0.35)` and the
  pole stops align with the highlight coverage (`lightCoverage`). This is
  an approximation; eyeball against the real shader in the example app and
  tune the 0.35 factor.
- BlendMode: `BlendMode.srcOver` for the edge ring (the shader `mix`es the
  edge color in, it does not hard-light it).
- When `edgeWidth == 0`: skip the ring entirely (shader behaves the same —
  `outlineCoverage = 0`).

### Step 3: Draw the highlight inset inward

- Build the highlight stroke on the inset path:
  `final highlightPath = highlightInset > 0 ? shape.getOuterPath(bounds.deflate(highlightInset)) : path;`
- Keep the existing light-angle gradient construction but with highlight
  colors only: `[highlightColor, transparent, transparent, highlightColor]`
  using the existing stop computation (`inset`, `edgeStart`, `edgeEnd`)
  so directionality and `specularWrap` behavior are unchanged.
- Keep the two existing strokes (crisp `hardLight` stroke at
  `lerpDouble(1, 2, lightIntensity)` width, soft `overlay` stroke at
  `thickness / 24` width) — both now drawn on `highlightPath`.
- Ambient term: the current code folds ambient into the edge color's alpha;
  after the split, fold it into the ring's alpha (Step 2), not the
  highlight.

### Step 4: Regenerate goldens and add a dedicated scenario

- Add a golden scenario to `fake_glass_test.dart` named
  `fake_glass_edge_outline` exercising: `edgeColor` opaque dark,
  `edgeWidth: 6`, `edgeInset: 1.0` (maximal separation), `thickness: 20`,
  light from the default angle — side-by-side scenarios with
  `edgeInset: 0.0` and `0.5`. Model the test structure on the existing
  groups in `fake_glass_test.dart`.
- `melos run update-goldens` — expect diffs in existing `fake_glass_*`
  goldens (intended) plus the new file.
- Manually compare against the real shader: run the example app
  (`packages/liquid_glass_renderer/example`), find or add a screen showing
  the same settings with `fake: false` vs `fake: true`, and confirm the
  edge ring extends visibly outside the highlight in both.

**Verify**: `melos run test` → all pass with regenerated goldens.

## Test plan

- New golden scenario(s) per Step 4 pinning the edge/highlight separation
  at `edgeInset` 0.0 / 0.5 / 1.0.
- Existing fake-glass goldens regenerated; every diff must be explainable
  as "edge ring now outside highlight" — any other change (blur, shadow,
  color fill) is a regression.
- `melos run test-without-goldens` must pass without modification (no
  non-golden behavior changes).

## Done criteria

- [ ] `melos run analyze` exits 0
- [ ] `melos run test` exits 0 with regenerated goldens
- [ ] New `fake_glass_edge_outline` golden exists and shows the edge band outside the highlight
- [ ] With `edgeWidth: 0`, output is unchanged vs before this plan (no ring drawn; verify via the existing zero-edge goldens being diff-free if any, or add one scenario with `edgeWidth: 0` and confirm it matches the pre-change rendering)
- [ ] No files outside the in-scope list modified
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back if:

- `shape.getOuterPath(bounds.deflate(...))` produces self-intersecting or
  degenerate paths for small shapes (deflate larger than half the short
  side) — clamp `highlightInset` to `shortestSide / 2 - 1` and if that
  still misbehaves, report with the failing geometry.
- The visual result diverges badly from the shader in the side-by-side
  (e.g. the ducking approximation looks wrong at high `specularWrap`) after
  two tuning attempts — capture screenshots of both and report; the
  gradient approximation may need maintainer input on the tradeoff.
- Goldens outside `fake_glass_*` diff.

## Maintenance notes

- This painter approximates the shader; whenever
  `applySpecularHighlights` in the shaders changes materially (new terms,
  different falloffs), `_paintSpecular` needs a matching pass. Consider a
  comment in both files cross-referencing each other (the shader file
  already centralizes the logic duplicated between final_render and
  direct_render).
- Plan 008 renames `edgeInset` → `highlightInset`; whichever lands second
  must update the other's identifiers (mechanical).
- Reviewer: check the `edgeWidth` clamp matches the shader
  (`opticalThickness * 0.5`) so fake and real saturate identically.
