# Renderer power ideas — independent review (2026-09-16)

Produced by an unbiased "senior mobile graphics engineer" review of the
pipeline, the measured cost model and the rejected-ideas list. Nothing here is
implemented. Engine claims come from reading Impeller sources (Flutter 3.47.1)
and are marked where they are inferences. Cost units: Pixel 10 GPU-rail mW for
the 120 Hz example scene; ClickUp's frame is ~0.5–0.6× that in absolute terms.

## 0. Reconstructed per-frame pass list (steady state, real glass, bar + loupe)

| # | Pass | Size (device px) | Notes |
|---|------|------------------|-------|
| P0 | Root renders offscreen (any BackdropFilter sets `requires_readback_`) | 2.6 Mpx store | unavoidable while any BackdropFilter exists |
| P1 | Bar group flip #1 (end pass, full-screen texture becomes input, new pass re-draws it) | 2.6 Mpx store + read | the "≈115 mW per independent BackdropFilter" |
| P2 | Bar subpass = clip AABB (~0.3 Mpx): blur downsample, blur passes, then `RuntimeEffectFilterContents` re-rasterises the scaled blur into a **full-res intermediate** anchored at the pass origin | ≈(lx+W)×(ly+H) — for a bottom bar ~2.3 Mpx write (hypothesis, E1) | final shader shades ~0.3 Mpx |
| P3 | Icons / labels | small | |
| P4 | Loupe flip #2 (own capture) | 2.6 Mpx store + read | required for "lens on painted bar" as structured today |
| P5 | Loupe subpass (~0.03 Mpx), σ=0 | tiny | |
| P6 | Analytic shadows, rest of UI | small | |
| P7 | Final blit offscreen → swapchain | 2.6 Mpx read + write | consequence of P0 |

Glass-attributable cost is dominated by full-screen traffic (two flips, offscreen root, blit, mis-anchored intermediate), not by shading of glass pixels — consistent with shader-ALU changes measuring nothing. Caveat: PowerVR framebuffer compression makes raw Mpx overstate DRAM energy; run E1/E2 before valuing single items.

## 1. Top 5

### #1 Bounded, seeded subpass around bar + loupe ("LiquidGlassScope") — package + 1-line app change
Wrap bar layer and loupe layer in one scope: `ClipRect(pixel-snapped bar-region AABB)` → passthrough `BackdropFilterLayer` (identity filter) → children. The passthrough creates a bar-sized subpass seeded with the backdrop (same engine-layer sequence the package's `_RealScopeAlphaLayer` already uses for fades). Every BackdropFilter inside flips the *current* pass — the ~0.3 Mpx seed — not the root. The loupe's flip reads the seed after the bar painted into it → still refracts the painted bar.
Savings: remove one full-screen flip (−115 GPU, −~60 DDR — the same delta measured for the shared-capture variant, without its visual regression); shrink the runtime-effect intermediate because `local_position ≈ 0` (−40…60 GPU, hypothesis E1); add seed fill + composite + two small flips (+15…25). Net ≈ **−130…−160 GPU, −50…−60 DDR** (example scale); roughly −70…−90 GPU on ClickUp's scroll frame.
Risks: device-pixel snapping of the seed origin (else the whole bar resamples by a half pixel); seed padding ≥ 3σ + max displacement + shadow extent; shadows/fades ordering; nested fade-scope golden. Prototype ≈ 30 lines in a benchmark scenario (E3).

### #2 Analytic (matte-less) glass path for ≤ 4 shapes — package-only
Evaluate the smooth-union SDF in the final shader (normal from dFdx/dFdy exactly as the matte pass does, displacement inline), skipping `_buildGpuGeometryImage` for N ≤ 4 (loupe N=1, ClickUp bar group N=3). The final pass is memory-bound, so a few SDF evaluations per fragment over 0.3 Mpx are near free; removes the matte texture read, the matte render pass during travel/morph (+70 GPU), ~2 ms UI thread per rebuild, and the per-frame texture allocation churn (#138627 PSS spikes).
Savings: steady −5…10 GPU; loupe travel **−70 GPU, −2 ms UI, no PSS spike**; menu growth same. Risk: low but golden-verify (removes 8-bit quantisation → small corner diffs, strictly higher fidelity); dFdx noise where the union switches dominant shape (parity with today). Start with the loupe (N=1).

### #3 Designated-source backdrop via `toImageSync`, no BackdropFilter — package + app
Capture the bar-sized strip of the *list* each frame with `toImageSync` (in-frame, raster thread), sample it in the final shader as an image; blur in-shader (2-pass separable, σ13 device px, tuned to match Impeller's look); loupe samples the painted bar rendered to a second small image. If this removes the last BackdropFilter, P0/P1/P4/P7 all disappear.
Ceiling **−200…−250 GPU, −80…−100 DDR**; realistically −120…−180 after captures and blur. Risks: semantics change ("whatever is behind me" → "the subtree the app designated": snackbars, scrims, drag overlays not refracted), blur parity, texture churn (ring-buffer the images), correctness guarantees on composition order. Gate on E6.

### #4 Engine: anchor the runtime-effect intermediate at the filter coverage
`runtime_effect_filter_contents.cc`: when the input snapshot fails `ShouldRasterizeForRuntimeEffects` (always for a downsampled blur), it re-rasterises from the subpass-local backdrop position (negative) to the coverage's bottom-right → ~2.3 Mpx write for a 0.3 Mpx bottom-bar filter. Fix: rasterise only the coverage rect and rebase the quad's `position` (which is what `FlutterFragCoord()` returns). −40…60 GPU, −15…25 DDR for bottom bars; #1 obtains the same saving package-side. Companions: render the root onscreen when backdrops exist (swapchain `SAMPLED_BIT`/`framebufferOnly = NO`; −40…70 GPU, −30 DDR; driver-compat risk); coverage-limited flip (lower value on TBDR).

### #5 CPU rail (3× the GPU rail): retained layer tree, stable filters, matte ring buffer — package-only
(1) `alwaysNeedsAddToScene` on the transform-tracking mixin re-runs `addToScene` every frame; mark dirty only on transform/uniform/clip change so Flutter can `addRetained`. (2) Reuse `ImageFilter`/`FragmentShader` objects when uniforms are byte-identical (new `DlImageFilter`s per frame also defeat Impeller's equality-based backdrop sharing). (3) Ring-buffer ≥3 matte textures instead of `createTexture` per rebuild. (4) Fewer passes (#1/#6) also cut raster-thread CPU. Measure first (E5).

## 2. The rest

| # | Idea | Phase | Est. | Visual risk | Type |
|---|------|-------|------|-------------|------|
| 6 | Split the blend group into per-cluster BackdropFilters under one BackdropGroup with tight clips (bar vs floating buttons) when farther apart than the blend radius; the union AABB currently shades the empty gap | steady | −20…50 GPU | low | package |
| 7 | Fake glass: make all fake filters in a group byte-identical so Impeller's equal-filter backdrop sharing fires (measured precedent 426→312); move per-shape tint out of the compose | steady (fake) | −60…110 per extra element | medium | package |
| 8 | Translate the loupe as a whole layer (layer transform) instead of moving the shape inside its layer → matte stays valid | travel | −70 GPU, −2 ms UI | low | package + app |
| 9 | Partial matte update: `LoadAction.load` + scissor to the dirty rect on a ring-buffered matte | travel/menu | −40…60 of the 70 | low | package |
| 10 | iOS: check offscreen pixel format under wide gamut (64-bpp float doubles all flip/subpass bandwidth); disable `FLTEnableWideGamut` if not needed | iOS | up to −40 % iOS glass DDR | none | app |
| 11 | Seed/clip padding = exact reach `ceil(3σ + maxDisplacement + shadowExtent)` snapped to 8 px instead of 64 px buckets | steady | −5…15 | low | package |
| 12 | CA taps only where displacement > threshold (formalise) | steady | ~0 | none | package |
| 13 | Loupe samples a cached bar image when list and bar are idle | idle | ~0 at scroll | low | package |
| 14 | Verify blur `TileMode` choice keeps coverage growth minimal | steady | 0…5 | none | package |
| 15 | Stencil-limit shading to shape interiors — not worth it (subpass size, not fragment count, sets traffic) | — | ~0 | — | — |
| 16 | Engine: mipmapped flip texture for large σ | steady | −10…20 | medium | engine |

## 3. Tempting but wrong here
Sharing the loupe's capture (visual regression); cheaper shader ALU (measured noise; memory-bound); half-res matte or half-res final pass (corner artifacts / softened highlights); `RepaintBoundary` as GPU cache (Impeller has no raster cache); `toImageSync` of the bar subtree for the loupe (BackdropFilter has no backdrop inside a detached picture); lowering σ (≤4 device px disables downsample and costs more); nested blur→shader BackdropFilters (rejected: destructive `BlendMode.src`); `ClipPath` to shrink shading (subpass size matters, not the path); glass at 60 Hz under a 120 Hz list (judder); LUTs for the RSE solve (matte is retained; trades ALU for a dependent read in a memory-bound pass); framebuffer fetch (same-pixel only; blur/refraction need neighbours); MSAA off on offscreen targets (TBDR resolves in tile memory; ~0).

## 4. Uncertainties and the cheapest experiment

| ID | Uncertainty | Experiment | Cost |
|----|-------------|------------|------|
| E1 | Intermediate spans pass origin → coverage? | Compare real−blur increments bottom pill vs top bar (`appScrollRealPillOnly`/`appScrollPlainBlur` pill-only vs `appScrollRealTopOnly`/`appScrollPlainBlurTopOnly`) | 4 runs |
| E2 | Exact pass list, target sizes, MSAA memory, flip count | One AGI/RenderDoc frame capture of the ClickUp scroll | 1 capture |
| E3 | Nested passthrough BackdropFilter makes inner flips subpass-sized and loupe still sees the painted bar? | Prototype the scope in one benchmark scenario; rails + golden | ~30 lines, 2 runs |
| E4 | Equal-filter backdrop sharing fires for fake glass? | Two fake elements, identical vs differing filter instances | 2 runs |
| E5 | Package share of the CPU rail; retained-tree win | Scroll with glass vs plain `Container` vs `alwaysNeedsAddToScene=false` hack | 3 runs |
| E6 | `toImageSync` strip capture cost and PSS at 120 Hz | Capture a 1000×170 px strip per frame, draw back; add 2-pass blur | small prototype |
| E7 | Blur receives the coverage hint through `compose`? | Fixed σ, vary clip area 1×/2×/4× | 3 runs |
| E8 | iOS offscreen pixel format under wide gamut | Metal frame capture; toggle `FLTEnableWideGamut` | 1 capture |

## 5. Recommended sequence
1. E1 + E2 to fix the cost anatomy. 2. #1 seeded scope (largest look-preserving win; subsumes #4 for ClickUp). 3. #2 analytic path, loupe first. 4. E5 then #5 (CPU rail). 5. #6/#7, #10 on iOS. 6. #3 as a prototype track gated on E6. 7. File #4 and the onscreen-root companion upstream.
