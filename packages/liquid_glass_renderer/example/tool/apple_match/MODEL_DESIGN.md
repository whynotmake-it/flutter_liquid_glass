# Model design — deconstructing Apple's Liquid Glass into our pipeline

Working notes for the renderer model redesign. Becomes the README mapping
table once the model lands and scores are in.

## Evidence: Apple internals → our pipeline stages

| Apple internal (evidence) | Our pipeline stage | Status |
|---|---|---|
| `CASDFElementLayer` → `CASDFOutputEffect` SDF texture feeding the backdrop (ShatteredGlass macOS 26 dump) | Geometry matte pass (`render_liquid_glass_geometry.dart`), SDF + displacement encoding | Already matches architecturally |
| `CABackdropLayer` + private `glassBackground` CAFilter: "refraction, blur, vibrancy, and tone mappings" | `liquid_glass_final_render.frag`: displacement sampling, backdrop blur, vibrancy lift, `transmissionGamma` | Matches; parameter surface to simplify |
| Two `CASDFLayer` highlight layers at opposite angles (`CASDFGlassHighlightEffect`) + `vibrantColorMatrix` 4×5 tone | `calculateLighting` / `applySpecularHighlights`: main + opposite (0.8×) directional rim | Already dual-directional like Apple |
| iOS 27 Settings "Tint Amount" slider → `UIViewGlassTintAmount` default (0…1) | Unified tint/transparency axis: tint color alpha + frost, one user-facing axis | New: single axis replaces ad-hoc alpha knobs |
| No public thickness/IOR-style physical knobs; system looks differ by geometry + discrete internal scales (harness: thickness ∈ {6,8,10,12} per control size) | `thickness` stays per-shape; refraction amplitude becomes a direct px scalar | New: `edgeRefraction` replaces `refractiveIndex` |

Key insight: Apple does not expose (and apparently does not parameterize by)
a physical refractive index. Displacement is SDF-profile-driven with a
per-surface amplitude. Our `refractiveIndex` + `thickness` pair is a physical
re-parameterization of that amplitude — and the frozen-RI generalization
rejection (small-capsule flow error 1.5× toolbar) is the symptom. Fitting the
amplitude directly (px of rim displacement) should generalize across control
sizes without per-look RI hacks.

## New parameter surface (evidence-gated)

Material knobs on `LiquidGlassSettings`:

| Knob | Replaces | Evidence gate |
|---|---|---|
| `thickness` | (kept) | discrete per control size in harness fits |
| `edgeRefraction` | `refractiveIndex` | frozen-RI rejection; amplitude fits pending |
| `refractionSpread` | (new) | SDF profile reach for ordinary glass; loupe magnification is composed before the shader and never uses this as a zoom control |
| `frost` | `blur` | size-normalized blur fit on toolbar + small capsule |
| `tint` (Color) | `glassColor` | tintColor stage gains on ≥2 scenes |
| `saturation` | (kept) | vibrancy stage fits 0.7–1.5 across scenes |
| `transmissionGamma` | (kept) | toneResponse stage |
| `vibrancy` | (kept) | vibrancy stage (vibrantColorMatrix analog) |
| `highlight` (double) | `lightIntensity` (+`highlightColor` fixed white, `ambientStrength`, `bleedStrength`, `specularWrap` folded/removed) | highlight stage |
| `contourStrength` | `edgeColor`/`edgeAlpha` + `outerContourColor/Width` + `innerShadowStrength` | outline/darkOutline/materialContour stages |
| `contourWidth` | `edgeWidth`/`edgeInset` | outline stage |
| `chromaticAberration` | (kept only if ≥2-scene evidence) | refraction stage CA axis |
| `visibility` | (kept — public transition utility, not material model) | n/a |

Removed as public knobs (folded to fixed internals or dropped):
`lightAngle` (fixed π/2, Apple's top-light), `ambientStrength`,
`highlightColor`, `edgeColor`, `edgeWidth`, `edgeInset`, `specularWrap`,
`bleedStrength`, `faceShadingStrength`, `faceShadingDepth`,
`innerShadowStrength`, `innerShadowDepth`, `innerShadowDirectionality`,
`outerContourColor`, `outerContourWidth`, `refractiveIndex`.

Shader: uniform block layout unchanged (same vec4/vec2/vec3 packing, just
re-bound scalars) → zero performance delta. Geometry pass takes
`edgeRefraction` where it took `refractiveIndex`.

## Fit protocol per scene

1. Seed from previous best (or `settings/baseline.json` translated).
2. Stages: shape → refraction(thickness, edgeRefraction, CA) → blurMtf(frost)
   → tintColor(tint) → toneResponse → vibrancy → highlight → outline.
3. Accept knob only if its stage improves ≥2 scenes beyond noise (3-frame
   median, repeated run identical → noise ≈ 0).

## Performance invariants

- Same two-pass structure (geometry matte + final filter), same texture count,
  same uniform buffer size. No new passes, no new samples.
- Example app changes must not touch renderer hot path.
