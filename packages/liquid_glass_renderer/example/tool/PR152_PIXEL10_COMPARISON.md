# Pixel 10 comparison against PR #152

This report compares the current renderer stack at `8c36ad3c` with the raw
head of PR #152 at `1cf4a24c` (`fix/android-opengles-y-flip-3-47`). It measures
the complete renderer evolution between those revisions, not just the
coordinate conditional.

## Decisive result

The current fake renderer is dramatically faster and smaller than PR #152's
fake renderer. Current real glass has a more expensive raster tail, consistent
with its substantially richer optics and lighting, but still delivers a lower
end-to-end p95, more frames, and lower process memory than PR #152 real glass.

Medians of three balanced, interleaved profile runs:

| Material | Revision | Frames / 8 s | Build p95 | Raster p50 | Raster p95 | Raster p99 | Total p95 | PSS | RSS |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Real | Current | 480 | 5.52 ms | 9.02 ms | 18.30 ms | 19.79 ms | 23.65 ms | 245.1 MB | 364.5 MB |
| Real | PR #152 | 472 | 3.40 ms | 8.65 ms | 13.61 ms | 16.27 ms | 26.60 ms | 287.8 MB | 407.1 MB |
| Fake | Current | 480 | 3.24 ms | 9.98 ms | 14.49 ms | 17.63 ms | 19.64 ms | 235.5 MB | 355.0 MB |
| Fake | PR #152 | 379 | 6.27 ms | 11.13 ms | 38.88 ms | 53.45 ms | 69.03 ms | 285.4 MB | 404.8 MB |

Current versus PR #152:

| Material | Frames | Build p95 | Raster p95 | Raster p99 | Total p95 | PSS | RSS |
|---|---:|---:|---:|---:|---:|---:|---:|
| Real | +1.7% | +62.5% | +34.5% | +21.7% | **−11.1%** | **−14.8%** | **−10.5%** |
| Fake | **+26.6%** | **−48.3%** | **−62.7%** | **−67.0%** | **−71.6%** | **−17.5%** | **−12.3%** |

Within the current revision, fake versus real is 20.8% lower at raster p95,
17.0% lower at total p95, and 3.9% lower in PSS. In PR #152, fake versus real
is 185.6% higher at raster p95 and 159.5% higher at total p95.

## Method

- Device: Pixel 10 (`frankel`), Android 16,
  `google/frankel/frankel:16/CP1A.260505.005/15081906:user/release-keys`.
- Toolchain: Flutter 3.47.1 stable (`6655482ec0`), engine
  `11d79658c444477b06513d32b52c8c4ccb7276b0`, Dart 3.13.1.
- Every runtime log identified Impeller's **Vulkan** backend.
- Profile APKs were built once per revision/material, reinstalled before every
  sample, force-stopped between samples, and measured with a 3 s warm-up and
  8 s collection window.
- Three repetitions used balanced order:
  1. current real, PR real, current fake, PR fake;
  2. PR fake, current fake, PR real, current real;
  3. PR real, current real, PR fake, current fake.
- Each scene used the same two-second ping-pong animation, 220 px moving
  rounded superellipse, gradient/grid backdrop, and child content.
- The current revision used `LiquidGlassSettings.ios27ToolbarLight()`.
  PR #152 predates that API, so its closest semantic mapping used thickness
  12, blur 7, matching tint alpha/RGB, chromatic aberration `.005`, light
  intensity `.25`, refractive index `1.2`, and saturation `.9`.
- PR #152 did not track an Android runner. Its renderer source was built with
  the current revision's Android runner, ensuring identical Gradle, manifest,
  package, and Impeller configuration.
- PSS/RSS are immediate post-measurement `dumpsys meminfo` snapshots. They are
  process-level measurements, not Dart heap.

Raw samples are in
[`results/pixel10_pr152_comparison.tsv`](results/pixel10_pr152_comparison.tsv).

## Interpretation and limits

PR #152 changes an OpenGLES-only preprocessor branch. Because the Pixel 10 ran
Vulkan in all 12 samples, the coordinate-unflip conditional itself was not
executed and cannot explain any measured delta. These numbers answer the
broader question—what the complete current stack changed relative to that PR's
renderer—but they do not isolate the cost of the Y-flip fix. On Vulkan that
isolated cost is structurally zero because neither side compiles the OpenGLES
branch.

The real-glass result is a tradeoff, not a uniform speedup. Current real glass
does more work in build/raster, but its steadier pipeline produces 480 versus
472 median frames and an 11.1% lower total p95 while using materially less
memory. Current fake glass is an unambiguous performance improvement across
every reported timing and memory measure.

PR #152's build also emitted SkSL incompatibility warnings for its arbitrary,
geometry-blended, and filter shaders. The measured Pixel path was Impeller
Vulkan, so those warnings did not invalidate these samples, but they confirm
that PR #152 was not a working Skia fallback baseline.
