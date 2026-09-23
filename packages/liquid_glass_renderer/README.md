# Liquid Glass Renderer

[![Pub Version](https://img.shields.io/pub/v/liquid_glass_renderer)](https://pub.dev/packages/liquid_glass_renderer)
[![Code Coverage](./coverage.svg)](./test/)
[![lints by lintervention][lintervention_badge]][lintervention_link]

> **Experimental prerelease**
>
> This package is not production-ready. The full renderer depends on Impeller
> and the beta Flutter GPU API. APIs and rendering behavior may change. Profile
> your actual screens on physical target devices before shipping them.

Liquid Glass Renderer provides iOS 27-style glass for Flutter. It supports
refraction, frost, tint, directional lighting, contours, shadows, and smoothly
blended shapes. It reproduces the visual style; it does not use Apple's private
material or rendering APIs.

![Liquid Glass Renderer showcase](doc/generated/renderershowcase.png)

## Requirements

- Flutter 3.47 or newer.
- Impeller and Flutter GPU for full refraction.
- Android, iOS, or macOS for the tested prerelease path. Web builds compile
  and render `FakeGlass`.

Unsupported renderer paths automatically use `FakeGlass`, which preserves the
main surface treatment but omits refraction.

```sh
flutter pub add liquid_glass_renderer
```

## Quick start

Glass samples pixels behind it. Put the background and glass in a `Stack`.

```dart
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

Stack(
  children: [
    const Positioned.fill(child: MyBackground()),
    Center(
      child: LiquidGlassLayer(
        settings: LiquidGlassSettings.ios27Toolbar(
          brightness: MediaQuery.platformBrightnessOf(context),
        ),
        child: LiquidGlass(
          shape: const LiquidRoundedSuperellipse(borderRadius: 28),
          child: const SizedBox(width: 220, height: 64),
        ),
      ),
    ),
  ],
)
```

Shaders load on first use, so the first glass on screen paints its fallback
for a frame or two. Load them up front instead:

```dart
await LiquidGlass.precache();
runApp(const MyApp());
```

## Mental model

| Type | Responsibility |
| --- | --- |
| `LiquidGlassLayer` | Captures one backdrop and renders its descendant glass shapes. |
| `LiquidGlassSettings` | Shared optics and lighting, such as frost, refraction, contour, and bevel. |
| `LiquidGlassAppearance` | Per-shape tint, color response, and material visibility. |
| `LiquidGlassVisibility` | Multiplies visibility through a widget subtree. |
| `LiquidGlassBlendGroup` | Smoothly joins nearby grouped shapes. |
| `LiquidGlass` | Registers one shape with a layer. |
| `FakeGlass` | Portable no-refraction fallback. |

`LiquidGlassSettings` remains intentionally broad. Calling it a “material”
would imply that it owns tint and color, while those values can vary per shape
through `LiquidGlassAppearance`. Calling it “optics” would omit its lighting and
contour controls.

## Choosing a constructor

| Constructor | Use it when |
| --- | --- |
| `LiquidGlass(...)` | A `LiquidGlassLayer` is always present. The shape stays independent. |
| `LiquidGlass.grouped(...)` | The shape is inside a `LiquidGlassBlendGroup` and should join nearby shapes. |
| `LiquidGlass.auto(...)` | Reusable code may or may not have a parent layer. |
| `LiquidGlass.withOwnLayer(...)` | One shape needs a separate backdrop sample or different shared settings. |

Prefer one explicit layer for sibling shapes. Each independent layer may add a
backdrop capture, filter, texture, and compositing cost.

`LiquidGlass.auto` uses its `settings`, `fake`, and backdrop options only when
it cannot find a parent layer. A parent layer always owns those values.

## Shared settings and per-shape appearance

The layer owns the expensive shared configuration:

```dart
final brightness = MediaQuery.platformBrightnessOf(context);

LiquidGlassLayer(
  settings: LiquidGlassSettings.ios27Toolbar(brightness: brightness),
  defaultAppearance: LiquidGlassAppearance.ios27Toolbar(
    brightness: brightness,
  ),
  child: const MyGlassControls(),
)
```

The toolbar presets are fitted starting points, not universal Apple materials.
Use `LiquidGlassAppearance.ios27Regular` for a SwiftUI-style `.regular` glass
material. Apple changes its treatment with control role, size, appearance, and
accessibility settings.

Override inexpensive color controls on individual shapes:

```dart
LiquidGlass.grouped(
  appearance: const LiquidGlassAppearance.ios27ToolbarLight(
    tint: Color(0x663B82F6),
  ),
  shape: const LiquidOval(),
  child: const SizedBox.square(dimension: 72),
)
```

The iOS 27 presets use a sealed `LiquidGlassColorModel.ios27` model. Tint
opacity selects how far the material moves from its neutral appearance toward
a backdrop-luminance-conditioned range of tint tones, matching Apple's public
single-tint API more closely than a flat source-over color. Use the direct
model when you want to tune every transfer independently:

```dart
const LiquidGlassAppearance(
  colorModel: LiquidGlassColorModel.direct(),
  tint: Color(0x663B82F6),
  saturation: 1.4,
  transmissionGamma: 0.9,
  vibrancy: 0.15,
)
```

Adjacent grouped shapes interpolate their appearances while they merge. This
uses the same shared backdrop capture. A layer with one uniform appearance
keeps the smaller fast path.

### Visibility

Visibility is not a layer setting. Use `LiquidGlassAppearance.visibility` for
one shape, or animate `LiquidGlassVisibility` around a subtree:

```dart
LiquidGlassVisibility(
  visibility: animation.value,
  child: const Row(
    children: [
      LiquidGlass(shape: LiquidOval(), child: SizedBox.square(dimension: 64)),
      LiquidGlass(shape: LiquidOval(), child: SizedBox.square(dimension: 64)),
    ],
  ),
)
```

Nested visibility scopes multiply. A value of `0.5` inside `0.4` produces an
effective multiplier of `0.2`. Ordinary child content remains visible and
interactive. At zero, the glass material, contour, shadow, and blend-union
contribution disappear; a fully invisible layer releases its backdrop filter.

## Blending shapes

Use `LiquidGlass.grouped` only for shapes that should form one surface.

![Two shapes merging into one glass surface](doc/generated/rendererblending.png)

```dart
LiquidGlassLayer(
  child: LiquidGlassBlendGroup(
    blend: 18,
    child: const Row(
      children: [
        LiquidGlass.grouped(
          shape: LiquidOval(),
          child: SizedBox.square(dimension: 72),
        ),
        SizedBox(width: 12),
        LiquidGlass.grouped(
          shape: LiquidRoundedSuperellipse(borderRadius: 24),
          child: SizedBox(width: 160, height: 72),
        ),
      ],
    ),
  ),
)
```

Independent `LiquidGlass` children may share a layer without blending.

## Settings reference

`LiquidGlassSettings` groups controls by purpose:

- Optics: `thickness`, `edgeRefraction`, `refractionSpread`,
  `backdropScale`, and `chromaticAberration`.
- Frost: `frost`, expressed as a logical-pixel blur sigma.
- Highlight: `highlight`, `highlightWidth`, `highlightWrap`,
  `highlightOppositeStrength`, and `curvatureLighting`.
- Outline: `contourStrength`, `contourWidth`, `contourOffset`, and
  `contourTransmittance`.
- Inner shading: `bevelShadowStrength`, `bevelShadowDepth`,
  `bevelShadowOffset`, `bevelShadowDirectionality`, and
  `bevelShadowSizeResponse`.
- Exterior shadow response: `exteriorShadowSizeResponse`.

`LiquidGlassAppearance` contains `tint`, `colorModel`, `saturation`,
`transmissionGamma`, `vibrancy`, and `visibility`. The sealed color model owns
its transfer function; the remaining fields stay available for custom looks
and for fitting materials that are not covered by the toolbar presets.

Keep `backdropScale` near `1`. Strong magnification enlarges an already
captured image and loses detail. Build a loupe with Flutter's `RawMagnifier`
before applying glass, then use glass only for edge optics and lighting.

## Shapes, children, and shadows

Supported shapes:

- `LiquidRoundedSuperellipse` for smooth squircles and capsules.
- `LiquidOval` for circles and ellipses.
- `LiquidRoundedRectangle` for conventional rounded rectangles.

Rounded shapes use one radius. Non-uniform corner radii are not supported.

A glass widget paints its child above the material, with the configured shape
clipping. Its child is not blurred, tinted, or refracted by its own glass.

Pass exterior shadows to the shape:

```dart
LiquidGlass(
  shape: const LiquidRoundedSuperellipse(borderRadius: 28),
  shadows: const [
    BoxShadow(
      color: Color(0x24000000),
      offset: Offset(0, 6),
      blurRadius: 20,
    ),
  ],
  child: const SizedBox(width: 220, height: 64),
)
```

The renderer cuts offset shadows out behind the translucent shape.
`BoxShadow.blurStyle` is ignored.

## FakeGlass fallback

`LiquidGlassLayer` selects `FakeGlass` automatically when the full renderer is
unavailable. Set `fake: true` on a layer to test that path explicitly.

![Full glass and FakeGlass fallback](doc/generated/rendererfallback.png)

`FakeGlass` keeps frost, tint, saturation, gamma, highlights, contours, bevel
shading, visibility, and exterior shadows. It omits edge refraction,
refraction spread, backdrop scale, chromatic aberration, vibrancy, and
curvature lighting.

The fallback is not guaranteed to be faster. It avoids Flutter GPU geometry
and refraction, but still pays for backdrop blur and Flutter compositing. Its
main purpose is predictable rendering on unsupported backends.

## Performance

The expensive unit is a backdrop *capture*, not a glass widget. Impeller reads
the screen back once per independent `BackdropFilter` / `BackdropKey`. Count
those captures per frame; that is the cost.

Share one `LiquidGlassLayer` between compatible siblings, keep geometry
static when the renderer can cache it, and profile animated and settled
states separately.

### Android GPU power

Measured on a Pixel 10 (Impeller/Vulkan, 120 Hz) from the SoC GPU power
rail. Each independent `BackdropFilter` costs ~115 mW just for that
readback, before blur or glass work.

| Workload | GPU |
| --- | --- |
| Impeller backdrop readback alone | ~115 mW |
| Plain `BackdropFilter` blur σ7 | ≈165 mW / element |
| FakeGlass | ≈230 mW |
| Real glass | ≈335 mW |
| Two real layers, independent → shared `BackdropGroup` | 797 → 688 mW |
| Two plain σ7 blurs, independent → shared `BackdropGroup` | 426 → 312 mW |
| Glass shadow (`saveLayer` + punch) | ~75 mW / shape |
| Blend-group geometry animating every frame | ~120 mW CPU; can miss 120 Hz |

Rules:

- Count backdrop captures per frame. Layers that share one `BackdropGroup`
  or `BackdropKey` pay the readback once.
- Share a `BackdropGroup` across chrome that sits over the same content
  plane (`useBackdropGroup: true`, or an explicit `BackdropKey`). Shared
  members do not see content painted between them.
- Keep frost around the presets (5–8). σ≤4 disables Impeller's downsample
  and costs more than σ7; σ20 costs about 3× σ7.
- Avoid glass shadows, or keep them small.
- Glass that must sit on other glass: see "Glass on glass" below.
- Do not animate blend-group geometry continuously.
- `FakeGlass` is not cheaper on Android: it pays the same readback and
  blur as real glass. The only real low-power tier is not sampling the
  backdrop at all: render the surface opaque (for example a tinted
  `DecoratedBox` in place of the glass) when the device or power state calls
  for it.
- To measure: see [example/tool/README.md](example/tool/README.md)
  "Android GPU power harness".

See the [performance audit](example/tool/PERFORMANCE_AUDIT.md) for the
full evidence, including ClickUp Inbox scroll (glass off 88 / fake 224 /
real 247 mW GPU; CPU ≈1.34 W in every state).

## Glass on glass

Apple's guidelines say not to stack glass on glass: glass is the control
layer that floats above content, and one glass element should not sit on
another. Follow that where you can. Sometimes you can't, for example a tab
indicator that has to slide over its tab bar. You then have four options.

Every `BackdropFilter` (each `LiquidGlassLayer` is one) has to read the
pixels behind it. On Impeller that means copying the whole current render
pass into a texture, the entire screen at the top level. We call that a
**full-screen readback**. It costs about 115 mW GPU on a Pixel 10 at 120 Hz,
before any blur or glass work. It is the unit to count.

| | Full-screen readbacks | The top glass shows | Drawback |
| --- | --- | --- | --- |
| Shapes in one `LiquidGlassLayer` | 1 | The content below | Shapes share the layer's settings and cannot refract each other. Use a `LiquidGlassBlendGroup` if they should merge. |
| Separate layers in one `BackdropGroup` (`useBackdropGroup: true`) | 1, shared by all layers; each layer still runs its own blur and shader | The content below, not the other glass | The indicator does not look like it sits on the bar. |
| Separate layers, each reading back on its own (default) | 1 per layer | The glass below it | Cost grows with every layer. |
| Separate layers inside a `LiquidGlassCapture` | 1 for the capture; inside it each layer reads back only the capture | The glass below it | You must paint the content outside the capture. |

Measured on the example's tab bar with a sliding indicator, list scrolling
at 120 Hz on a Pixel 10: own readbacks 910 mW GPU, shared `BackdropGroup`
751–783, `LiquidGlassCapture` 736. In ClickUp's bottom bar the capture saved
about 5 % GPU. Real screens have more going on than a benchmark, so measure
your own.

### Using `LiquidGlassCapture`

Wrap the glass that belongs together. Paint the content the glass should
refract below it, not inside it.

```dart
Stack(
  children: [
    content,
    Align(
      alignment: Alignment.bottomCenter,
      child: LiquidGlassCapture(
        child: LiquidGlassLayer(
          // the bar
          child: LiquidGlassLayer(
            // the indicator, refracting the bar
          ),
        ),
      ),
    ),
  ],
)
```

The capture sizes itself to the glass inside it plus its blur, refraction
and shadow. Pass `bleed` to size it yourself, for example when the child
paints something that reaches further out than the glass. Keep captures
small; a capture the size of the screen saves nothing.

## Limitations

- The package is experimental and not battle-tested.
- Full glass requires Impeller and Flutter GPU.
- The tested prerelease platforms are Android, iOS, and macOS. The web only
  renders `FakeGlass`.
- One layer supports at most 16 shapes.
- FakeGlass does not refract the backdrop.
- The renderer cannot reproduce Apple's private mixed clear/blur pipeline
  without an additional backdrop pass. A measured prototype was rejected
  because it substantially increased frame time and memory.

## Example

Run the workbench with the full renderer:

```sh
cd packages/liquid_glass_renderer/example
flutter run --enable-impeller --enable-flutter-gpu
```

The example exposes the fitted light and dark presets, per-shape tint and
visibility, blending, real/fake switching, backgrounds, and persistent custom
presets.

[lintervention_link]: https://github.com/whynotmake-it/lintervention
[lintervention_badge]: https://img.shields.io/badge/lints_by-lintervention-3A5A40
