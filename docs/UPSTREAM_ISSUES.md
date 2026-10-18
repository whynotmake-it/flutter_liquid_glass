# Issues to open on flutter/flutter

Engine and framework changes that would help glass (and other heavy effects)
in Flutter. Each entry is a draft: search for duplicates, confirm the claim
with a GPU capture where noted, then file it and add the link.

Status: `draft` (not verified), `verified` (confirmed with a capture or a
repro), `filed` (link added).

Engine references are to Flutter 3.47.1 (`engine/src/flutter/impeller/`).

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

## iOS

### Request extended dynamic range on the Flutter layer

`draft` · related: flutter/flutter#127520 (macOS EDR, open)

With `FLTEnableWideGamut`, Flutter on iOS renders into an extended-range
`BGRA10_XR` surface, but never sets `wantsExtendedDynamicRangeContent`, so
values above SDR white are clipped on screen. Apps have to set it on the
`CAMetalLayer` from native code (our example's `AppDelegate`). An opt-in flag
(Info.plist or engine API) would make HDR highlights available without native
code.
