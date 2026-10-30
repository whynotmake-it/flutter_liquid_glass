# Issues to open on flutter/flutter

Engine and framework changes that would help glass (and other heavy effects)
in Flutter. Each entry is a draft: search for duplicates, confirm the claim
with a GPU capture where noted, then file it and add the link.

Status: `draft` (not verified), `verified` (confirmed with a capture or a
repro), `filed` (link added).

Engine references are to Flutter 3.47.1 (`engine/src/flutter/impeller/`).

## Existing issues to support

- [flutter/flutter#177133](https://github.com/flutter/flutter/issues/177133)
  (open, P2): `ImageFilter.combine(left, right, combiner)`, i.e. `f(x, g(x))`.
  Would let the glass shader see the sharp and the blurred backdrop at once,
  which is what Apple's clear glass appears to do, without a second backdrop
  pass. Comment with our use case and measurements.
- [flutter/flutter#190815](https://github.com/flutter/flutter/issues/190815)
  (open, P2): jank on iOS whenever a platform view is on screen. Blocks the
  native-glass route we recommend in the blog post.
- [flutter/flutter#127520](https://github.com/flutter/flutter/issues/127520)
  (open): EDR on macOS; related to the iOS EDR entry below.

## Rendering

### Write backdrop filter output straight to the parent pass

`draft` · needs a Metal capture to confirm the copies

A `BackdropFilter` with the default `srcOver` blend appears to draw its filter
result into a save layer and composite that layer back onto the parent, two
full-area copies that change no pixel. For the default blend mode (and no
opacity or clip that needs isolation) Impeller could draw the result directly
into the parent pass. Impeller already skips the layer in one special case.
Per layer this should remove two passes. Source: our audit,
`docs/perf-audit-2026-10.md` (branch `perf/deep-audit`).

### Share backdrop readbacks automatically when nothing in between overlaps

`draft`

Every independent backdrop filter splits the pass and redraws the backdrop
(about 21 MB of traffic per full-screen readback at Pixel 10 resolution;
about 115 mW of GPU power per filter in our measurements). `BackdropGroup`
shares one readback, but it is opt-in and requires identical filters to save
the filter work too. When no content drawn between two backdrop filters
overlaps the second filter's read bounds, the second one could reuse the first
readback. Impeller already tracks the bounds needed to decide this.

### Let a shader filter sample a downsampled blur directly

`draft` · needs a capture to confirm the upsample pass

`ImageFilter.compose(outer: ImageFilter.shader(...), inner: ImageFilter.blur(...))`
blurs at reduced resolution, then rasterizes the blurred snapshot back to full
size (`needs_rasterization_for_runtime_effects`,
`runtime_effect_filter_contents.cc`) before the shader runs. A shader that
samples with bilinear filtering would get the same result from the
low-resolution texture plus a UV transform, which saves a full-size pass.
Needs a way to pass the snapshot's transform (or a sampler that applies it) to
the runtime effect.

### Framebuffer fetch for color-filter-only backdrop filters

`draft`

A `BackdropFilter` whose filter is only a `ColorFilter` is a per-pixel function
of the destination. On GPUs with framebuffer fetch or tile memory (Metal
programmable blending; Vulkan input attachments /
`VK_EXT_rasterization_order_attachment_access`), Impeller could apply it in
the current pass instead of ending the pass, storing, and redrawing the
backdrop. Impeller already uses framebuffer fetch for advanced blend modes, so
the plumbing exists. This removes the readback entirely for tints, dimming
scrims, and our capture pass (an identity color matrix). Note that framebuffer
fetch is disabled on PowerVR in `workarounds_vk.cc`, so the Pixel 10 would
keep the current path.

### Fragment shaders that read the destination pixel (custom blend modes)

`draft` · follow-up to the framebuffer fetch entry

Let a `FragmentShader` used as a paint shader read the current destination
pixel and return the blended result, i.e. a custom blend mode. On
framebuffer-fetch hardware this costs no extra pass; elsewhere Impeller can
fall back to its existing advanced-blend path (copy the destination region,
then sample it). This would let effects like glass do per-pixel compositing
without a backdrop filter and its readback, and would let packages define
blend modes Flutter doesn't ship.

## Flutter GPU

### Report a texture's GPU allocation size to the Dart GC, or add `dispose()`

`draft`

`gpu.Texture` has no `dispose()`, and its native wrapper reports only
`sizeof` the C++ object as external size (`lib/gpu/texture.cc`,
tonic `dart_wrappable.cc`). Code that replaces textures frequently looks like
a few bytes of garbage to the GC; in one host test 1,200 replaced mattes left
570–700 MB allocated until an idle GC. Either an explicit `dispose()` or an
accurate external size would fix this. Note: `CLAUDE.md` currently cites
flutter/flutter#138627 for this, but that issue is about `toImageSync`
retaining display lists (closed); look for the right issue or file one.

### A way to know when a frame that used a texture has finished on the GPU

`draft`

Reusing a Flutter GPU texture safely needs to know that no in-flight frame
still samples it. Today we rely on the engine's two-frame pipeline depth
(`Animator` pipeline of 2), an internal detail. A completion signal per frame
(or a fence/callback when a recorded scene has been rasterized) would make
reuse safe without guessing.

### Backdrop effects in Flutter GPU (a recorded "backdrop node")

`draft` · large; frame it as a general capability, not a glass feature

Flutter GPU can only render offscreen: Dart records and submits passes during
paint, before the backdrop exists, which only appears when the raster thread
plays the frame back. Proposal: a layer whose Flutter GPU passes are recorded
at paint time against placeholders ("the backdrop texture", "the parent
pass"), then replayed by Impeller at raster time. Impeller would do the usual
backdrop split, bind the real backdrop texture, run the recorded passes, and
run the final draw directly inside the parent render pass. Flutter GPU already
shares Impeller's context and queue, so no cross-API synchronization is
needed.

That would let packages own the whole pipeline: downsample to any level, use
their own blur kernel, sample the low-resolution result without upscaling it,
draw straight into the parent pass, share one downsample chain across several
layers, and reuse blurred textures across frames when the backdrop is
unchanged. For glass that covers the first three rendering entries above in
package code. It does not remove the backdrop split itself; only framebuffer
fetch or fewer splits do that. Open questions: how these nodes compose with
clips, other backdrop filters and platform views, what a recorded program may
do, and fallback on Skia and web.

## iOS

### Request extended dynamic range on the Flutter layer

`draft` · related: flutter/flutter#127520 (macOS EDR, open)

With `FLTEnableWideGamut`, Flutter on iOS renders into an extended-range
`BGRA10_XR` surface, but never sets `wantsExtendedDynamicRangeContent`, so
values above SDR white are clipped on screen. Apps have to set it on the
`CAMetalLayer` from native code (our example's `AppDelegate`). An opt-in flag
(Info.plist or engine API) would make HDR highlights available without native
code.
