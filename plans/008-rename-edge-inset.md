# Plan 008: Rename `edgeInset` to `highlightInset` (deprecate the old name)

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 85323b7..HEAD -- packages/liquid_glass_renderer/lib/src/liquid_glass_settings.dart`
> If `edgeInset` has already been renamed or the class shape changed,
> STOP and reconcile with whoever did it.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (coordinate with Plan 007 — whichever lands second
  updates the other's identifier usage; both plans note this)
- **Category**: tech-debt / API clarity
- **Planned at**: commit `85323b7`, 2026-06-11

## Why this matters

`LiquidGlassSettings.edgeInset` does not inset the edge — it insets the
**specular highlight** within the edge width (the edge outline, defined by
`edgeColor`/`edgeWidth`, stays at the outer boundary). The name actively
misleads: a user trying to move the edge outline reaches for `edgeInset`
and gets a moving highlight instead. Rename the property to
`highlightInset`, keeping behavior identical, with a deprecated forwarding
member for one release cycle (the package is `0.2.0-dev.x`; deprecation is
courtesy, not obligation).

The shader uniform packing slot and internal names (`uEdgeInset` in two
.frag files) are also renamed for consistency — purely internal, no
functional change.

## Current state

- `packages/liquid_glass_renderer/lib/src/liquid_glass_settings.dart`:
  - constructor param `this.edgeInset = 0.5` (line ~23)
  - field + doc (lines ~167–174):

    ```dart
    /// How far the specular highlight is inset into the edge width.
    ///
    /// `0` means the highlight starts at the outer edge. `0.5` means it
    /// starts halfway through [edgeWidth]. `1` means it starts after the
    /// full edge width.
    final double edgeInset;
    ```

  - `copyWith` param + forwarding (lines ~227, 244)
  - `props` entry (line ~264)
- Dart consumers of the value (all read `settings.edgeInset`):
  - `lib/src/rendering/liquid_glass_render_object.dart`
    (`_updateShaderSettings`, in the `setFloats` block after
    `effectiveEdgeWidth`)
  - `lib/src/rendering/liquid_glass_layer.dart`
    (`_updateDirectShaderSettingsOn`, same packing)
  - `lib/src/fake_glass.dart` does NOT read it today (it will after Plan
    007 — see coordination note).
- Shader internal names (cosmetic rename):
  - `lib/assets/shaders/liquid_glass_final_render.frag:41` —
    `float uEdgeInset = uSpecularConfig.y;` and its use
    `clamp(uEdgeInset, ...)` (~line 85)
  - `lib/assets/shaders/liquid_glass_direct_render.frag:46` — same pair
    (~lines 46, 75). The comment on `uSpecularConfig` in that file
    (`// edgeWidth, edgeInset, bleedStrength, specularWrap`) also updates.
- Example app: `packages/liquid_glass_renderer/example/lib/shared.dart`
  lines ~116–117 and ~273–280 (slider labeled via
  `settings.edgeInset.toStringAsFixed(2)` and `copyWith(edgeInset: ...)`).
- Tests: `rg -n "edgeInset" packages/liquid_glass_renderer/test` — none at
  plan time; re-check at execution.
- README: `rg -n "edgeInset" packages/liquid_glass_renderer/README.md` —
  none at plan time; re-check.

## Commands you will need

| Purpose | Command (from repo root) | Expected on success |
|---------|--------------------------|---------------------|
| Analyze | `melos run analyze` | exit 0 (deprecation usage must not trip `--fatal-infos` — see Step 1) |
| Tests | `melos run test` | all pass, zero golden diffs |
| Grep gate | `rg -n "edgeInset" packages --glob '!*.md'` | matches only the deprecated member + its doc |

## Scope

**In scope**:
- `packages/liquid_glass_renderer/lib/src/liquid_glass_settings.dart`
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_render_object.dart`
- `packages/liquid_glass_renderer/lib/src/rendering/liquid_glass_layer.dart`
- `packages/liquid_glass_renderer/lib/assets/shaders/liquid_glass_final_render.frag`
- `packages/liquid_glass_renderer/lib/assets/shaders/liquid_glass_direct_render.frag`
- `packages/liquid_glass_renderer/example/lib/shared.dart`
- `packages/liquid_glass_renderer/test/src/` (new small test)
- `packages/liquid_glass_renderer/lib/src/fake_glass.dart` (ONLY if Plan
  007 landed first and introduced `settings.edgeInset` reads there)

**Out of scope**:
- Any behavioral change — the value's meaning, default (`0.5`), clamping,
  and uniform slot are untouched.
- `CHANGELOG.md` (melos-generated).
- `apple_liquid_glass` (re-exports; nothing to rename —
  verify with `rg -n "edgeInset" packages/apple_liquid_glass`).

## Git workflow

- Commit message: `refactor: rename edgeInset to highlightInset, deprecate the old name`
  (if the deprecated member is dropped instead — see Step 1 fallback — use
  `refactor!:` to mark it breaking).
- Do NOT push or open a PR unless instructed.

## Steps

### Step 1: Rename in `LiquidGlassSettings` with deprecation

- Add the new field `highlightInset` carrying the existing doc comment
  (reworded to lead with "How far the specular highlight is inset…" — it
  already does) plus a line clarifying: "The edge outline itself
  ([edgeColor], [edgeWidth]) always starts at the outer boundary; this
  only moves the highlight."
- Constructor: accept `this.highlightInset = 0.5` AND a deprecated
  optional `@Deprecated('Use highlightInset instead') double? edgeInset`
  parameter; in the initializer, `highlightInset = edgeInset ??
  highlightInset` is not expressible for a const constructor with both —
  so use this pattern instead:

  ```dart
  const LiquidGlassSettings({
    ...
    double highlightInset = 0.5,
    @Deprecated('Use highlightInset instead.') double? edgeInset,
    ...
  }) : highlightInset = edgeInset ?? highlightInset, ...
  ```

  (Const-constructor initializers permit `??`. Verify it compiles; if the
  class's existing style makes this awkward, the FALLBACK is a clean
  break: remove `edgeInset` entirely, no deprecation — the package is in
  dev, and the maintainer prefers clean over compat. Note which route was
  taken in the status row.)
- Add a deprecated getter: `@Deprecated('Use highlightInset instead.')
  double get edgeInset => highlightInset;`
- `copyWith`: add `highlightInset` param; keep a deprecated `edgeInset`
  param that forwards (`highlightInset: highlightInset ?? edgeInset ??
  this.highlightInset`).
- `props`: replace the entry with `highlightInset`.
- IMPORTANT (analyze gate): the repo analyzes with `--fatal-infos`. The
  package's own code must not reference the deprecated members anywhere
  (steps below remove all internal uses); `deprecated_member_use_from_same_package`
  would otherwise fail the build. The deprecated members themselves are
  fine to declare.

### Step 2: Update internal readers

In `liquid_glass_render_object.dart` (`_updateShaderSettings`) and
`liquid_glass_layer.dart` (`_updateDirectShaderSettingsOn`): change
`settings.edgeInset` → `settings.highlightInset`. The uniform packing
order is unchanged.

If Plan 007 landed first: also update `fake_glass.dart`'s
`settings.edgeInset` reads.

### Step 3: Rename shader-internal aliases

In both `liquid_glass_final_render.frag` and
`liquid_glass_direct_render.frag`: rename the GLSL global
`uEdgeInset` → `uHighlightInset` (declaration reading
`uSpecularConfig.y` and the single `clamp(...)` use in each file), and
update the `uSpecularConfig` layout comment in
`liquid_glass_direct_render.frag` to
`// edgeWidth, highlightInset, bleedStrength, specularWrap`.
No uniform indices change; this is text-level renaming inside the shaders.

**Verify**: `melos run test` → pass, zero golden diffs (shader output is
identical; a golden diff means an accidental semantic edit — STOP).

### Step 4: Update the example app

`example/lib/shared.dart`: switch the local variable, the slider's
`copyWith(edgeInset: ...)` call, and the
`settings.edgeInset.toStringAsFixed(2)` label to `highlightInset`. Update
any visible slider caption text if it says "Edge inset" (search
`rg -n "Edge inset|edgeInset" packages/liquid_glass_renderer/example`).

### Step 5: Pin the alias with a test

Add to an existing settings-adjacent test file (or create
`test/src/liquid_glass_settings_test.dart`):

- `LiquidGlassSettings(highlightInset: 0.8).highlightInset == 0.8`
- equality: two instances differing only in `highlightInset` are unequal.
- If the deprecation route was taken: `// ignore: deprecated_member_use_from_same_package`
  on a check that `LiquidGlassSettings(edgeInset: 0.3).highlightInset == 0.3`
  and `settings.copyWith(edgeInset: 0.2).highlightInset == 0.2`.

**Verify**: `melos run analyze` → exit 0; `melos run test-without-goldens`
→ all pass.

## Test plan

- New unit tests per Step 5.
- Full suite green with ZERO golden diffs — this plan must be visually
  inert.

## Done criteria

- [ ] `melos run analyze` exits 0
- [ ] `melos run test` exits 0, zero golden diffs
- [ ] `rg -n "edgeInset" packages/liquid_glass_renderer/lib` matches only the deprecated members in `liquid_glass_settings.dart` (or nothing, if the clean-break fallback was taken)
- [ ] `rg -n "uEdgeInset" packages/liquid_glass_renderer/lib` → no matches
- [ ] Example app slider drives `highlightInset`
- [ ] No files outside the in-scope list modified
- [ ] `plans/README.md` status row updated (note deprecation vs clean break)

## STOP conditions

Stop and report back if:

- The const-constructor deprecation pattern fails to compile AND the
  clean-break fallback is unacceptable because external packages in this
  repo (`apple_liquid_glass`, example) can't be updated atomically — list
  the blockers.
- Any golden diffs after Step 3.
- Plan 007 is mid-flight on the same files (coordinate ordering instead of
  merging conflicting renames).

## Maintenance notes

- Remove the deprecated members in the next minor/breaking release; grep
  `Deprecated('Use highlightInset` to find them.
- The audit also flagged (not planned): `edgeWidth` doc says "The highlight
  is moved inward by this amount" — after this rename, re-read the
  `edgeWidth` doc and tighten it ("Width of the [edgeColor] outline at the
  outer boundary; the highlight starts inside it, controlled by
  [highlightInset]"). Cheap to do in the same commit.
