# Liquid Glass Shader Performance Optimization Plan (Conservative Revision)

## 1. Context & Cost Drivers

Current per-fragment work (worst typical configuration):
- SDF evaluation for N shapes (up to 4 common; 5–16 rarer).
- Normal derivation (dFdx/dFdy) + nonlinear adjustment (sqrt).
- Refraction (refract + displacement math).
- Optional chromatic aberration (3 separately displaced samples).
- Lighting (rim falloff + highlight color logic).
- Saturation/lightness & tint blending.

Dominant cost categories differ by scenario:
- Few shapes + chromatic aberration ON → texture bandwidth + ALU for refraction path.
- Many shapes (≥6) → SDF unions + gradient cost.
- Small/thin shapes → overdraw more relevant than per-pixel complexity.
- Large fullscreen usage → everything counts; instruction count & register pressure matter.

Unless you ship multiple glass layers stacked, overdraw is moderate; main target is fragment ALU & texture taps.

---

## 2. Assumptions Behind Estimates

| Assumption | Rationale |
| ---------- | --------- |
| Mobile-class GPU (e.g. Apple A14 / mid Android Mali) | Likely deployment for Flutter apps. |
| Typical number of shapes: 1–4 | Code already unrolls for this; >4 is special case. |
| Chromatic aberration often disabled or low | Aesthetic setting, not always required. |
| Blur radius usually 0 | Your earlier note; blur path rarely active. |
| Thickness moderate (5–12) | Extreme thinness forces early exit already. |

If actual usage skews heavier (many shapes, always chromatic aberration), gains trend toward upper ends; if lighter, toward lower ends. Where a range is given: “likely” = typical shipped scenario; “best case” = stress case that exercises the optimized portion.

---

## 3. Phase 1 (Low-Risk, Local Edits)

| Item | Change | Likely Gain | Best Case | Risk | Notes |
|------|--------|-------------|-----------|------|-------|
| 1. Replace trivial pow() & small exp() opportunities | Manual squaring & fast constants | 0–1% | 2% | Very low | Already partially done; just finish sweep. |
| 2. Cache reciprocals / reuse `1.0 / uSize`, avoid recomputing thickness-derived factors | Minor ALU pruning | 0–1% | 2% | Very low | Helps instruction count & register reuse. |
| 3. Combine small branches into masks (blur=0, ca=0) | Streamline control flow | 0–1% | 2% | Very low | Driver may already do similar; safe. |
| 4. Rim Gaussian → rational approx (`1/(1+k*x^2)`) | Replace exp + muls with a few muls | 1–3% | 5% | Low (visual tuning) | Must tune k so edge brightness curve matches. |
| 5. Highlight color: early reject when rimFactor very small OR lightIntensity≈0 | Skips saturation/luminance math | 1–2% | 4% | Low | Only in darker/low-light usage. |
| 6. Chromatic aberration path sample reuse (share blur work / derive R,B) | Reduces texture taps from 5–7 → ~3 | 2–5% | 8–10% | Medium (color shift fidelity) | Only when aberration + blur simultaneously ON. |
| 7. Early foregroundAlpha test -> optional discard (if blending allows) | Cuts overdraw ALU outside shapes | 0–3% | 6–8% (large shapes) | Medium (blending correctness) | Must validate premultiplied alpha path. |

Phase 1 aggregate (not additive): Likely 5–10% total; best case stacked scenario ~15–18%.  
Any claim above ~10% without measurements would be aggressive for these localized edits.

---

## 4. Phase 2 (Moderate Complexity / Adaptive)

| Item | Change | Likely Gain | Best Case | Risk | Notes |
|------|--------|-------------|-----------|------|-------|
| 1. Adaptive quality tiers (disable lighting & CA for very small on-screen area) | Skip heavy code for tiny shapes | 3–6% | 12% (UI full of small chips) | Medium | Needs area heuristic from CPU. |
| 2. Motion-based downgrade (if host supplies velocity) | Avoid dispersion on fast movement | 1–4% | 7% | Medium | Requires keeping prior frame state. |
| 3. Approximate refraction for near-normal angles (linear scale of normal.xy) | Replaces refract() and some divides | 1–3% | 5–6% | Low-Med (edge correctness) | Blend to full model on curvature. |
| 4. Mip-based blur substitute (LOD bias) for small radii | Removes Kawase taps entirely | 0–4% | 8% | Medium (texture chain needs mips) | Provide fallback define. |
| 5. Pack shape data more tightly (mat4 arrays or UBO struct) | Slight instruction & fetch reduction | 0–2% | 3–4% | Medium (API refactor) | Only if uniform pressure observed. |
| 6. Normal alternative: finite differences only when ≤2 shapes | Avoid dFdx/dFdy cost | 0–2% | 4% | Medium (double SDF calls vs derivatives) | Use heuristic threshold. |

Phase 2 aggregate (beyond Phase 1): Likely incremental +8–15%; worst-case heavy shape/motion scenario maybe +25%.  
Combined Phase 1 + 2 realistic total: 15–25% in mainstream use; 30–35% in stress tests.

---

## 5. Phase 3 (Structural / High Impact if Constraints Allow)

| Item | Change | Likely Gain | Best Case | Risk | Notes |
|------|--------|-------------|-----------|------|-------|
| 1. Pre-baked SDF atlas (static shapes) | Removes per-pixel shape unions & SDF ALU | 10–20% | 30–40% (many shapes) | High (pipeline complexity) | Only if shapes change rarely. |
| 2. Two-pass pipeline (downsample + refract, then composite) | Shares blur & displacement across instances | 5–15% | 25–30% (multiple glass layers) | High (extra passes, FBO mgmt) | Gains scale with instance count. |
| 3. Temporal reprojection (reuse prev displacement) | Allows reducing per-frame quality | 3–8% | 12–15% | High (ghosting risk) | Requires motion-compensated blending. |
| 4. Half precision (mediump) promotion for selected paths | ALU & bandwidth reduction | 2–5% | 8% | Medium (banding / precision) | Test on Android first. |
| 5. Simplified dispersion model (Y-only offset) | Fewer vector ops + samples | 1–3% | 5% | Low | If artistic tolerance ok. |

Phase 3 potential (if all applicable): Additional 15–25% on top of previous phases; upper bound (extreme multi-instance + static shapes) ~40%—but that’s a specialized scenario, not everyday UI.

---

## 6. Quality & Risk Mitigation

| Feature | Degradation Risk | Mitigation |
|---------|------------------|------------|
| Rim light approximation | Slight edge brightness curve drift | A/B screenshot diff (SSIM > 0.98 threshold) |
| Refraction approximation | Angle-dependent distortion error | Blend full model when |normal.z| < threshold |
| Adaptive tiering | Popping when crossing thresholds | Hysteresis (enter at size A, exit at size B) |
| Mip-based blur | Halo / over-softening | Clamp LOD bias; gamma-correct sample |
| SDF atlas | Stale shape if dynamic | Fallback to procedural path when dirty flag set |
| Lower precision | Banding in dark gradients | Dither or keep highp for final color |

---

## 7. Instrumentation & Validation Plan

1. Baseline capture:
	- Scenarios: (a) 1 shape no CA, (b) 4 shapes CA on, (c) small shapes cluster, (d) fullscreen.
	- Metrics: frame time (Flutter GPU), overdraw heat map, shader compile stats (instruction count / registers if tool available).
2. Introduce each optimization behind a compile-time define; measure delta individually (avoid stacking noise).
3. Visual regression tests:
	- Offscreen FBO compare (pre vs post) compute mean absolute error & SSIM.
	- Accept thresholds: MAE < 0.01, SSIM ≥ 0.985 for non-adaptive paths.
4. Logging:
	- Add a lightweight runtime struct (CPU side) collecting shape count, chosen quality tier → correlate with GPU time.

---

## 8. Implementation Order (Adjusted for Value vs Cost)

1. Finish micro ALU housekeeping (pow/exp removal, caching).
2. Rim light rational approximation + highlight early-exit.
3. Chromatic aberration sample consolidation (since dispersion is an optional visual flourish).
4. Adaptive small-shape fast path (skip lighting/dispersion).
5. Approximate refraction for low-angle normals.
6. Optional discard for out-of-shape pixels (verify blend correctness first).
7. Mip-based blur path (gated by availability).
8. Packed shape uniform layout (only if profiling shows register/uniform pressure).
9. Structural steps (SDF atlas, two-pass) only if required after measuring earlier gains.

---

## 9. Realistic Aggregate Expectations

| After Phase | Likely Cumulative | Stretch (Edge Case) | Comment |
|-------------|-------------------|----------------------|---------|
| Phase 1 | 5–10% | 15–18% | Low risk, do first. |
| Phase 1 + 2 | 15–25% | 30–35% | Adaptive wins depend on usage mix. |
| Phase 1 + 2 + 3 | 30–40% | 55–60% | Upper range only if shapes static + multiple instances + high original cost. |

Anything beyond ~40% in a standard single-instance UI scenario would require more radical design changes (e.g., pre-rendering entire glass panels to static textures).

---

## 10. Optional Macro Scaffold (Conceptual Sketch)

(Not applied yet—just reference.)

```glsl
//#define LIQUID_FAST_RIM
//#define LIQUID_APPROX_REFRACTION
//#define LIQUID_ADAPTIVE_TIERS
//#define LIQUID_USE_MIP_BLUR
//#define LIQUID_STATIC_SDF
//#define LIQUID_HALF_PRECISION
```

Each block isolated so you can bisect performance regressions quickly.

---

## 11. When to Stop Optimizing

Stop after Phase 2 if:
- GPU frame time margin ≥ 2–3 ms on target devices.
- Visual differences are below thresholds and no thermal throttling observed.
- Additional structural complexity would increase maintenance more than saved milliseconds.

Proceed to Phase 3 only if:
- Multiple overlapping glass widgets are planned OR
- Lower-tier Android devices still miss frame budget.

---

## 12. Summary

This revised plan targets measured, incremental shader performance gains without speculative overstatement. Early wins are modest but low risk; adaptive and structural strategies can compound improvements when justified by profiling. The largest headline gains require static shape assumptions or multi-pass restructuring—clearly separated to avoid premature complexity.

Let me know if you’d like this turned into a repo `PERFORMANCE.md`, or if you want help implementing the first batch of defines and changes.
