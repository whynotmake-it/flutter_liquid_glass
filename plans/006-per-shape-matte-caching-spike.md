# Plan 006: Design spike — per-shape matte caching and incremental compositing

> **Executor instructions**: This is a DESIGN SPIKE, not a build plan. The
> deliverable is a written design document plus a throwaway prototype branch
> measurement — NOT production code. Follow the steps, answer the listed
> questions with evidence, and write the design doc. If anything in the
> "STOP conditions" section occurs, stop and report. When done, update the
> status row in `plans/README.md`.
>
> **Drift check (run first)**: `git diff --stat 85323b7..HEAD -- packages/liquid_glass_renderer/lib`
> This spike reads broadly; drift in the rendering pipeline files means
> re-verify the "Current state" claims before measuring.

## Status

- **Priority**: P2 (highest-leverage long-term; gated on the smaller plans landing first)
- **Effort**: L (spike itself: ~2 days; the build that follows: larger)
- **Risk**: spike LOW; eventual change HIGH (visual parity)
- **Depends on**: plans/003-paint-path-quick-wins.md, plans/005-async-matte-rasterization.md
- **Category**: perf / architecture
- **Planned at**: commit `85323b7`, 2026-06-11

## Why this matters

Two structural costs dominate multi-shape animation today, and both scale
badly toward the maintainer's stated goal of rendering **arbitrary bezier
paths** as glass:

1. **Group-level rebake**: when any one shape in a
   `LiquidGlassBlendGroup` moves, `gatherShapeData` flags the whole group
   changed and the geometry shader re-renders the **union AABB** of all
   shapes into a fresh matte texture
   (`render_liquid_glass_geometry.dart`, `maybeRebuildGeometry` →
   full dispose/rebuild path).
2. **Layer-level recomposite**: any matte rebake dirties
   `GeometryRenderLink`, which makes `LiquidGlassRenderObject.paint()`
   re-record and re-rasterize the **entire layer composite** texture
   (`_buildGeometryImage` + `toImageSync`) covering the union of all
   geometry in the layer.

The existing fast paths (direct render, nine-slice, component splitting,
translation reuse) each carve exceptions out of this, but they are all
conditional escape hatches around the same architecture: monolithic
union-AABB textures with all-or-nothing invalidation. Arbitrary bezier
glass cannot use the analytic-SDF escape hatches at all (no closed-form
SDF in the shader), so it will land on the slowest path — per-frame
union-AABB rebakes. The architecture itself has to get incremental before
that feature is viable.

This spike decides the shape of that architecture before anyone writes it.

## Current state (verified facts to build on)

- Geometry mattes encode displacement+edge data in RGBA
  (`displacement_encoding.glsl`); the final shader samples one texture per
  layer (`uGeometryTexture` in `liquid_glass_final_render.frag`) with a
  nine-slice remap path already in place (`ninePatchCoord`).
- Blending between shapes happens in the **geometry shader** via
  `smoothUnion` over analytic SDFs (`sdf.glsl`), up to 16 shapes per group.
  Blended shapes' displacement fields interact — per-shape mattes are NOT
  independent where blend regions overlap.
- The layer composite exists because the final shader wants one texture in
  screen space; `_buildGeometryImage` re-draws each group's matte
  (`drawImage`/`drawImageNine`/`drawImageRect`) into one picture and bakes
  it.
- Component splitting (`gatherDirectComponents`) already implements
  union-find proximity clustering with the blend distance as threshold —
  the exact math needed to know which shapes' mattes are independent.
- `GeometryRenderLink` dirty tracking is boolean and link-wide
  (`_dirty`, `_hadFullRebuild`) — no per-geometry granularity.
- Audit finding PERF-03: the final backdrop pass clips to the union
  bounding box, paying backdrop capture + shader cost for empty space
  between sparse shapes.

## Commands you will need

| Purpose | Command (from repo root) | Expected on success |
|---------|--------------------------|---------------------|
| Tests | `melos run test` | baseline green before measuring |
| Benchmark | `cd packages/liquid_glass_renderer/example && flutter test integration_test/benchmark_test.dart --enable-impeller -d macos` | numbers for the report |
| Example app profiling | `cd packages/liquid_glass_renderer/example && flutter run --profile --enable-impeller -d macos` | DevTools timeline |

## Scope

**In scope** (spike outputs):
- `plans/006-design-doc.md` (create — the deliverable)
- A throwaway branch for prototype measurements (never merged; name it
  `spike/per-shape-mattes`, delete after measuring or leave for reference)

**Out of scope**:
- Merging ANY production code from this spike.
- Changing public API.
- The arbitrary-bezier feature itself (this spike only ensures the
  architecture won't preclude it).

## Git workflow

- All prototype work on `spike/per-shape-mattes`, branched from the current
  branch after Plans 003/005 landed. Commit freely there; it will not be
  merged.
- The design doc is committed to the main working branch:
  `docs: add per-shape matte caching design doc`.

## Steps

### Step 1: Quantify the baseline

On the current architecture, measure and record in the design doc:

1. Frame time and allocated texture bytes for: (a) one of 5 grouped shapes
   animating, group blended (blend > 0, shapes near each other); (b) same
   but sparse (component splitting active); (c) 5 *ungrouped* shapes in one
   layer, one animating. Use the integration benchmark where it covers
   these, extend it on the spike branch where it doesn't (per the audit,
   it currently covers static single, translating single, and 5 static
   widgets).
2. The texture sizes involved: per-group matte AABB vs layer composite AABB
   for each scenario (log them from `_buildGeometryImage` /
   `maybeRebuildGeometry` on the spike branch).

### Step 2: Answer the design questions with evidence

Each answer goes in the design doc with the experiment or code reference
that decided it:

1. **Can the final shader consume per-shape mattes directly?** The blocker
   for killing the layer composite is one-texture-per-layer sampling.
   Options to evaluate: (a) multiple sampler uniforms (Impeller limit on
   sampler count? — test empirically with a toy shader); (b) one atlas
   texture the composite becomes a cheap GPU `drawImage` pass into
   (atlasing kills the *re-record* cost but keeps one bake); (c) one
   backdrop pass **per component** (extends component splitting from the
   direct path to the texture path — PERF-03's fix falls out of this).
2. **Where does blending break per-shape independence?** Within a blend
   component, displacement fields interact; the union-find clustering
   (threshold `blend * 1.2`) already computes independence. Proposal to
   validate: cache per *component*, not per shape — a component's matte
   rebakes only when one of ITS shapes changes. Measure how often
   real-world layouts (example app screens) produce multi-shape components.
3. **Incremental dirty tracking**: replace link-wide `_dirty` with a
   per-geometry generation (int) and a layer-side map of last-consumed
   generations. Sketch the data flow; confirm nothing needs the boolean
   semantics (check every `_dirty` / `markRebuilt` / `markFullRebuild`
   reader).
4. **Bezier path forward-compatibility**: for an arbitrary `Path`, the
   geometry matte cannot be produced by the analytic SDF shader. Evaluate
   CPU-side SDF generation: rasterize the path to a coverage bitmap and
   run a distance transform (jump flooding on GPU via repeated shader
   passes, or CPU EDT at reduced resolution), cached per path geometry.
   The spike answers: at what resolution/cost is a one-off SDF bake of a
   ~400×400 logical path acceptable (<2ms? <8ms?), and does the existing
   displacement encoding have the range/precision to be driven from a
   precomputed SDF texture instead of analytic evaluation? (Read
   `displacement_encoding.glsl` for the encoding contract.)
5. **Interaction with existing fast paths**: which of nine-slice,
   translation reuse, direct mode, component splitting survive, merge, or
   die in the proposed architecture? (Goal: fewer special cases, not more.
   E.g. if the texture path becomes per-component, "component splitting"
   stops being a special case of direct mode and becomes the architecture.)

### Step 3: Prototype the riskiest assumption

Build the smallest prototype on the spike branch that de-risks the chosen
direction — expected to be: per-component texture passes feeding the final
shader (question 1c + 2). Acceptance for the prototype: scenario (a)/(b)
from Step 1 with one shape animating rebakes ONLY that shape's component
matte, and frame time + texture bytes improve measurably. Visual output
need not be pixel-perfect in the prototype (note deviations).

### Step 4: Write the design doc

`plans/006-design-doc.md` with: baseline numbers; answers to the five
questions with evidence; the chosen architecture (diagram of textures,
passes, and invalidation flow); migration steps sized S/M/L as future
plans; explicit list of what gets deleted (special cases removed); risks
and visual-parity test strategy (golden coverage needed before migrating).

## Test plan

- The spike merges no production code, so no tests are required to pass
  beyond the suite staying green on the working branch (untouched).
- The design doc must specify the golden-test additions the build-out will
  need (multi-shape partial-motion scenarios are currently untested —
  audit note: the benchmark covers none of the blend/component paths).

## Done criteria

- [ ] `plans/006-design-doc.md` exists and answers all five design questions with evidence
- [ ] Baseline + prototype measurements recorded (frame time, texture bytes, matte/composite dimensions)
- [ ] Prototype demonstrates component-granular rebake on the spike branch (or the doc explains why the direction was rejected and what replaces it)
- [ ] Follow-up build plans listed with effort estimates
- [ ] No production code changed on the working branch
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back if:

- Impeller cannot sample more than the current sampler count AND atlasing
  AND per-component passes all measure worse than baseline — i.e. all three
  candidate directions fail; the report then recommends staying monolithic
  and investing in Plan 005-style mitigation instead.
- The displacement encoding turns out to lack precision for
  SDF-texture-driven displacement (question 4) — that changes the bezier
  story fundamentally and the maintainer should weigh in before more spike
  time.

## Maintenance notes

- PERF-03 (union-AABB backdrop cost), PERF-07 (direct-path SDF cost), and
  audit finding BUG-08 (>16 shapes crash) should all be re-evaluated
  against the chosen architecture in the design doc rather than fixed
  separately first.
- The 16-shape uniform cap (`MAX_SHAPES` in `sdf.glsl`, Impeller uniform
  buffer limit) is a constraint on analytic paths only; texture-driven
  geometry has no such cap — worth stating in the doc as a bezier-era
  bonus.
