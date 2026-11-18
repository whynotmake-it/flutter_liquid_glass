# Liquid Glass Renderer

[![Pub Version](https://img.shields.io/pub/v/liquid_glass_renderer)](https://pub.dev/packages/liquid_glass_renderer)
[![Code Coverage](./coverage.svg)](./test/)
[![lints by lintervention][lintervention_badge]][lintervention_link]

iOS 27-style Liquid Glass for Flutter: refraction through a rounded bevel,
frost, tint, a directional glint, a dark contour, and shapes that melt into each
other. It is fitted against captures of Apple's own glass, and it ships presets
for the regular and clear materials, including the Settings Liquid Glass
slider.

It reproduces the look with Flutter's own rendering; it does not use Apple's
private material APIs.

| Light | Dark |
| --- | --- |
| ![Tab bar in light mode](doc/readme/bottom-bar-light.jpg) | ![Tab bar in dark mode](doc/readme/bottom-bar-dark.jpg) |
| ![Toolbar buttons in light mode](doc/readme/controls-light.jpg) | ![Toolbar buttons in dark mode](doc/readme/controls-dark.jpg) |

> **1.0 prerelease: the renderer was rewritten.**
>
> `1.0.0-dev` replaces the whole API of `0.2.x`. There are no deprecations;
> see the [changelog](CHANGELOG.md) for what moved where. Full glass needs
> Impeller and the Flutter GPU API, which is still in preview. APIs and
> rendering may change before 1.0. Profile your real screens on physical
> devices before shipping.

## Contents

- [Requirements](#requirements)
- [Quick start](#quick-start)
- [The widgets](#the-widgets)
- [Blending shapes](#blending-shapes)
- [Custom outlines](#custom-outlines)
- [iOS 27 presets and the Liquid Glass slider](#ios-27-presets-and-the-liquid-glass-slider)
- [Tint and color](#tint-and-color)
- [Refraction](#refraction)
- [Glint](#glint)
- [Visibility](#visibility)
- [FakeGlass](#fakeglass)
- [Glass on glass](#glass-on-glass)
- [Performance](#performance)
- [Example playground](#example-playground)
- [Upgrading from 1.0.0-dev.2](#upgrading-from-100-dev2)

## Requirements

- The Flutter version `pubspec.yaml` names, or newer.
- Impeller and Flutter GPU for full glass. Pass `--enable-flutter-gpu` to
  `flutter run`, or turn it on in the app: `FLTEnableFlutterGPU` in
  `Info.plist` (iOS, macOS) and the
  `io.flutter.embedding.android.EnableFlutterGPU` meta-data in
  `AndroidManifest.xml`. The example app shows both.
- iOS, Android and macOS are the platforms the renderer is tested on. Web
  builds compile and render [FakeGlass](#fakeglass). Windows and Linux are
  untested.

Wherever full glass is unavailable, layers switch to `FakeGlass`
automatically.

```sh
flutter pub add liquid_glass_renderer
```

## Quick start

Glass samples the pixels behind it, so put your content and the glass in a
`Stack`:

```dart
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

class GlassPill extends StatelessWidget {
  const GlassPill({super.key});

  @override
  Widget build(BuildContext context) {
    return const Stack(
      children: [
        Positioned.fill(child: MyContent()),
        Center(
          child: LiquidGlassLayer(
            child: LiquidGlass(
              shape: LiquidRoundedSuperellipse(radius: 28),
              child: SizedBox(width: 220, height: 56),
            ),
          ),
        ),
      ],
    );
  }
}
```

A layer given no settings draws iOS 27 regular glass for the platform
brightness. [iOS 27 presets](#ios-27-presets-and-the-liquid-glass-slider)
shows how to choose the glass yourself.

Shaders and the GPU pipeline load on first use, so the first glass on screen
paints `FakeGlass` for a frame or two. Optionally load them before `runApp`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await precacheLiquidGlass();
  runApp(const MyApp());
}
```

Awaiting precache trades startup time for having glass resources ready when
the UI mounts.
It does not eliminate all first-use GPU work; omit it if showing an initial
fallback is preferable to delaying startup.

The first glass frame also creates the GPU pipelines that glass draws with. On
a mid-range Android phone, that stalls the frame the first time an installed
app shows glass. Later launches load the pipelines from the disk cache.
`precacheLiquidGlass(warmUp: true)` creates them offscreen during the
precache instead, at the cost of one offscreen frame on every launch.

### Is full glass available?

Layers fall back to `FakeGlass` by themselves. To know before you build them,
for example to pick an opaque look on a weak GPU, read the
`LiquidGlassSupport` that `precacheLiquidGlass()` returns:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final support = await precacheLiquidGlass();
  if (support case LiquidGlassUnavailableSupport(:final reason)) {
    debugPrint('Fake glass: $reason');
  }
  runApp(MyApp(fullGlass: support is LiquidGlassAvailableSupport));
}
```

A `LiquidGlassSupport` is one of three:

- `LiquidGlassAvailableSupport`: every full-glass program and the Flutter GPU
  geometry bundle loaded, so layers draw full glass. Its `deviceClass` is the
  kind of GPU, a `LiquidGlassDeviceClass`: `capable` (Vulkan, Metal on a Mac
  or an Apple GPU from the A13, or OpenGL ES on a desktop), `gles` (Impeller's
  OpenGL ES fallback on an Android device without a usable Vulkan driver,
  where full glass costs more frame time) or `appleBeforeA13`.
- `LiquidGlassUnavailableSupport`: full glass does not draw, and `reason`
  says why: the engine has no shader filters (Skia or the web), or full glass
  did not load, for example because Flutter GPU is not enabled.
- `LiquidGlassPendingSupport`: full glass has not loaded yet.
  `precacheLiquidGlass()` never returns it; `liquidGlassSupport`, a
  `ValueListenable` of the same answer for code that would rather listen than
  await, holds it until the precache or the first glass layer has loaded full
  glass.

## The widgets

| Widget | What it does |
| --- | --- |
| `LiquidGlassLayer` | Draws every glass shape below it together. Owns the shared `LiquidGlassSettings`. |
| `LiquidGlass` | One glass shape. Its child paints on top of the glass, clipped to the shape. |
| `LiquidGlassBlendGroup` | Melts the `LiquidGlass` shapes inside it into one surface. |
| `LiquidGlassVisibility` | Fades the glass in a subtree in and out. |
| `FakeGlass` | The fallback without refraction, used automatically where full glass is unavailable. |
| `LiquidGlassSettings` | Refraction, frost, glint, contour and inner shadow, shared by a layer. |
| `LiquidGlassAppearance` | Tint, color model and visibility, per shape or as a layer default. |
| `LiquidGlassMaterial` | Settings, an appearance and shadows that match: one iOS 27 glass for a brightness. |

`LiquidGlass` draws where the tree puts it:

| Where it sits | Where it draws |
| --- | --- |
| Under a `LiquidGlassLayer` | On that layer, beside the layer's other shapes. There must be a layer above it. |
| Under a `LiquidGlassBlendGroup` | In the group: it blends with the group's other shapes. |
| In the child of another `LiquidGlass` | On a layer of its own, with the settings of the layer around it, see [Glass on glass](#glass-on-glass). |

A shape that needs settings of its own goes in a `LiquidGlassLayer` of its
own.

`LiquidGlass.live(frame: ...)` is a shape whose geometry, appearance and
shadows follow a `ValueListenable<LiquidGlassShapeFrame>`, for glass that
moves every frame. Each new frame goes straight into the render objects
without a rebuild. Hit testing follows the box the widget was laid out in.

Put sibling shapes in one layer. A layer draws all its shapes together and
pays its per-layer work once. [Performance](#performance) says what glass
costs.

Shapes are `LiquidRoundedSuperellipse` (squircles and capsules), `LiquidOval`
and `LiquidRoundedRectangle`. A rounded rectangle has one corner radius. A
superellipse has one radius, or one for its two top corners and another for
its two bottom corners with `LiquidRoundedSuperellipse.vertical`. Two shapes
of one kind lerp into each other. Exterior shadows go on the shape as
`LiquidGlassShadow`s, and the renderer cuts them out behind the translucent
glass:

```dart
LiquidGlass(
  shape: const LiquidRoundedSuperellipse(radius: 28),
  shadows: const [
    LiquidGlassShadow(
      color: Color(0x24000000),
      offset: Offset(0, 6),
      blurRadius: 20,
    ),
  ],
  child: const SizedBox(width: 220, height: 56),
)
```

The renderer animates nothing. Touch glows, squash and stretch and other
motion belong to the widget library on top: it moves glass with
`LiquidGlass.live` frames and lights it with the `LiquidGlassGlow` each frame
carries (`LiquidGlassShapeFrame.glow`).

The main import holds what every app needs: the values in `painting.dart` and
the widgets in `widgets.dart`. A package that builds on the renderer imports
`rendering.dart` by name: the layers that carry a frame's plan out, and
`GlassFrameReport`, which tells what a frame's glass took.

## Blending shapes

| Light | Dark |
| --- | --- |
| ![A button and a toolbar melting together](doc/readme/blend-light.jpg) | ![The same in dark mode](doc/readme/blend-dark.jpg) |

Shapes in a `LiquidGlassBlendGroup` join like drops of water once they come
within `blend` logical pixels of each other (default `20`). Straight edges that
touch stay straight; only the gap between them rounds, as in iOS 27's
`GlassEffectContainer`.

```dart
LiquidGlassLayer(
  child: LiquidGlassBlendGroup(
    blend: 24,
    child: Row(
      children: const [
        LiquidGlass(
          shape: LiquidOval(),
          child: SizedBox.square(dimension: 56),
        ),
        SizedBox(width: 8),
        LiquidGlass(
          shape: LiquidRoundedSuperellipse(radius: 28),
          child: SizedBox(width: 180, height: 56),
        ),
      ],
    ),
  ),
)
```

A layer renders any number of shapes, as long as no more than 16 of them blend
or sit within a few pixels of each other, whether or not they have appearances
of their own. A field takes the looks of its body from at most 16 shapes.
Shapes of the same layer that sit outside the group don't blend with it.

## Custom outlines

A layer can shade a body of any outline in place of its shapes' own: give it
the body's signed distance field. `LiquidGlassField.fromPath` computes one
from any closed `Path`, in the layer's coordinates:

```dart
final star = Path()..addPolygon(points, true);

LiquidGlassLayer(
  field: LiquidGlassField.fromPath(star),
  child: Stack(
    children: [
      Positioned.fromRect(
        rect: star.getBounds(),
        child: const LiquidGlass(
          shape: LiquidRoundedRectangle(radius: 0),
          child: SizedBox.expand(),
        ),
      ),
    ],
  ),
)
```

The shape under the field still supplies the appearance, the shadow, the
content clip and the bounds of the glass, which must contain the body. A layer
shades one field, so every custom body takes a layer of its own. Building a
field measures every node against the whole edge (about 90 ms in a debug build
for 300 x 200 at the default step of 2): compute it when the path changes and
keep it, not once a frame. A widget that knows its outline analytically can
fill a `LiquidGlassField` itself instead.

## iOS 27 presets and the Liquid Glass slider

Glass is configured in three parts. `LiquidGlassSettings` on the layer holds
the optics and lighting. `LiquidGlassAppearance` holds the color, either as
the layer's `defaultAppearance` or per shape. A shape's `shadows` are a list
of `LiquidGlassShadow`. `LiquidGlassMaterial` gives all three for one iOS 27
glass:

```dart
final glass = LiquidGlassMaterial.ios27Regular(
  brightness: MediaQuery.platformBrightnessOf(context),
);

LiquidGlassLayer(
  settings: glass.settings,
  defaultAppearance: glass.appearance,
  child: LiquidGlass(
    shape: const LiquidRoundedSuperellipse(radius: 28),
    shadows: glass.shadows,
    child: const SizedBox(width: 220, height: 56),
  ),
)
```

Every type names the two iOS 27 glasses the same way:

| Material | Regular (`.regular`: toolbars, tab bars, `.glass` buttons) | Clear (`.clear`) |
| --- | --- | --- |
| `LiquidGlassMaterial` | `ios27Regular(brightness:)` | `ios27Clear()` |
| `LiquidGlassSettings` | `ios27Regular(brightness:)` | `ios27Clear()` |
| `LiquidGlassAppearance` | `ios27Regular(brightness:)` | `ios27Clear()` |
| `LiquidGlassShadow` | `ios27Regular(brightness:)` | none: clear glass casts no shadow |
| `LiquidGlassFrost`, `LiquidGlassHaze` | `ios27Regular(...)` | `ios27Clear()` |

A layer given no `settings` and no `defaultAppearance` draws regular glass for
the platform brightness: light glass in light mode, dark glass in dark mode.

The presets are fitted to Apple's glass at toolbar and button size. They are a
starting point: Apple also varies its glass with the control's role, size and
accessibility settings.

### `sliderPosition`: the Liquid Glass slider

iOS 27 has a Liquid Glass slider in Settings, from Clear (`0`) to Tinted
(`1`). Pass its position as `sliderPosition`. The renderer does not read the
system setting; your app decides.

```dart
LiquidGlassSettings.ios27Regular(brightness: brightness, sliderPosition: 0.5)
```

The settings store the position once, and everything fitted to iOS 27 follows
it, so `settings.copyWith(sliderPosition: 1)` is the tinted glass:

- **Wash.** The iOS 27 color model makes its neutral wash more opaque, and
  dark glass denser.
- **Contour.** The dark contour gets stronger.
- **Blur.** A fitted `frost` (`LiquidGlassFrost.ios27Regular()`,
  `LiquidGlassFrost.ios27Clear()`) and a fitted `haze` follow the slider, and
  the frost also grows with the glass's short side; its dartdoc lists the
  measured values.

The glint doesn't change. The direct color model ignores `sliderPosition`,
and it never changes a frost or a haze you give as numbers:
`LiquidGlassFrost.sigma(12)` is 12 logical pixels at every position and size.

## Tint and color

| Light | Dark |
| --- | --- |
| ![Light, dark, clear and blue glass melting together](doc/readme/colors-light.jpg) | ![The same over a night backdrop](doc/readme/colors-dark.jpg) |

Tint a single shape through its appearance. Neighbors in a blend group
cross-fade their colors where they meet, from the same backdrop sample:

```dart
LiquidGlass(
  appearance: const LiquidGlassAppearance.ios27Regular(
    brightness: Brightness.light,
    tint: Color(0xFF0A84FF),
  ),
  shape: const LiquidOval(),
  child: const SizedBox.square(dimension: 72),
)
```

The iOS 27 presets use `LiquidGlassColorModel.ios27Regular`. It turns one tint color
and its opacity into tones that depend on the brightness of the backdrop,
like Apple's single-tint API. Clear glass (`LiquidGlassColorModel.ios27Clear`)
is the same in light and dark.

For full control, use the direct model and tune each transfer yourself:

```dart
const LiquidGlassAppearance(
  tint: Color(0x663B82F6),
  colorModel: LiquidGlassColorModel.direct(
    saturation: 1.4,
    transmissionGamma: 0.9,
    vibrancy: 0.15,
  ),
)
```

A layer where every shape has the same appearance keeps a smaller shader path.

## Refraction

Glass is modeled as a flat face with a rounded bevel along its edge. Only the
bevel refracts; the face shows the backdrop undisplaced.

- `refractionHeight`: the bevel width in logical pixels.
- `refractionAmount`: how far inside the silhouette the outermost pixel samples
  the backdrop. The displacement falls off across the bevel as
  a quarter circle. Above a ratio of 1 to `refractionHeight`, content near the
  rim is mirrored, as on Apple's glass. `0` turns refraction off.
- `refractionFitsShape` (default `true`): small shapes shrink the lens like
  iOS 27 regular glass. The bevel is at most a quarter of the short side, and
  the rim samples no deeper than the center line. Clear glass sets it to
  `false`.
- `backdropShrink`: shrinks the backdrop seen through the whole face. `0`
  keeps its size and `0.08` shows it at 92%. It never enlarges, so the glass
  never pixelates the backdrop. All glass in a layer shrinks about the center
  of the layer's glass; give a shape its own layer to shrink it about itself.
- `backdropPull` and `backdropPullDepth`: the edge reads the backdrop up to
  `backdropPull` logical pixels outside the glass, falling to nothing
  `backdropPullDepth` from the edge. Glass deeper than that shows its middle
  in place and at its own size, where `backdropShrink` shows all of it smaller.
- `dispersion`: splits the colors in the refracted edge. Red moves by
  `1 + dispersion / 2` and blue by `1 - dispersion / 2` times the edge
  displacement; negative values bend blue more, as real glass does. iOS 27
  regular and clear glass show none, so it defaults to `0`, which is also the
  cheapest setting to render.
- `aberration` and `aberrationDepth`: parts the colors of everything the glass
  shows, not only of the bevel: red shows what lies up to `aberration` logical
  pixels one way and blue what lies as far the other way, along the direction
  iOS 27 parts them in (the dartdoc of `aberration` gives it), in full at the
  edge and fading to nothing `aberrationDepth` from it. Glass that
  parts colors draws with a larger shader variant, so leave it at `0` where it
  is not wanted.

`backdropPull` and `aberration` give a lifted iOS lens its look. Both default
to `0`.

The backdrop is always sampled bilinearly, so refracted lines move smoothly
instead of snapping to whole pixels.

### Magnifiers

`backdropShrink` never magnifies, because enlarging a captured backdrop makes
it blurry. The [example playground](#example-playground) shows how to build an
iOS 27 text loupe instead: it re-renders the content under the lens at the
magnified resolution and draws a `LiquidGlass` on a layer of its own on top,
so text stays sharp. The loupe is example code, not part of the package; copy
[`example/lib/loupe/liquid_glass_loupe.dart`](example/lib/loupe/liquid_glass_loupe.dart)
if you need one.

| Light | Dark |
| --- | --- |
| ![A text loupe and a round magnifier over an article](doc/readme/loupe-light.jpg) | ![The same loupes in dark mode](doc/readme/loupe-dark.jpg) |

## Glint

The glint is the thin bright line along the rim, on the two walls facing
along the light. It recolors the glass instead of adding white: glass over color glints in that
color.

`glintStrength` sets its strength; the presets keep it as soft as the rim of iOS 27
glass. The line is a hairline, equally bright on both walls, and fades around
corners as on iOS 27.

Two more strengths shape the rim: `contourStrength` is the thin dark contour
just outside the silhouette (`contourDirectionality` concentrates it where the
glint fades), and `bevelShadowStrength` is the faint inner shadow the rim casts
on the face. The defaults and presets set all of them.

### HDR

The glint aims at a color brighter than SDR white. Full glass writes that value
unclamped, so whether it reaches the display depends on the surface Flutter
renders into:

- **iOS**: set `FLTEnableWideGamut` to `true` in `Info.plist`. The surface then
  holds values up to about 1.25, so the brightest part of the glint is
  compressed. Flutter's layer doesn't request extended dynamic range, so the
  values above 1.0 only reach the display once the app sets
  `wantsExtendedDynamicRangeContent` on the Flutter view's `CAMetalLayer`; the
  example app does this in its app delegate.
- **macOS**: with `FLTEnableWideGamut` on capable hardware, the surface keeps
  the full range.
- **Android**: 8-bit surfaces, so the glint is SDR.

`FakeGlass` writes the same glint headroom into an opaque surface. It reaches
above SDR white on the same extended-range surfaces; elsewhere it clamps to
white like the real renderer.

## Visibility

Visibility is per shape, not a layer setting. Set
`LiquidGlassAppearance.visibility` for one shape, or animate
`LiquidGlassVisibility` around a subtree:

```dart
LiquidGlassVisibility(
  visibility: animation.value,
  child: const Row(
    children: [
      LiquidGlass(shape: LiquidOval(), child: SizedBox.square(dimension: 56)),
      LiquidGlass(shape: LiquidOval(), child: SizedBox.square(dimension: 56)),
    ],
  ),
)
```

As visibility falls, the glass dissolves: refraction goes to zero, lighting and
blur fade, and the shape's child fades with it. Children stay mounted and
interactive. Nested scopes multiply (`0.5` inside `0.4` gives `0.2`). A layer
whose shapes are all invisible stops sampling the backdrop.

Don't fade glass with `Opacity` or `FadeTransition` between the layer and its
shapes; that only fades the children. `Opacity` above a whole
`LiquidGlassLayer` works.

## FakeGlass

| Full glass | `FakeGlass` |
| --- | --- |
| ![Full glass tab bar](doc/readme/bottom-bar-light.jpg) | ![The same tab bar with FakeGlass](doc/readme/bottom-bar-fake-light.jpg) |
| ![Full glass tab bar in dark mode](doc/readme/bottom-bar-dark.jpg) | ![The same tab bar with FakeGlass in dark mode](doc/readme/bottom-bar-fake-dark.jpg) |

Full glass bends the backdrop at the rim; `FakeGlass` keeps everything else.

`FakeGlass` renders glass with a backdrop filter instead of the Flutter GPU
pipeline. Layers use it automatically where full glass is unavailable (Skia,
the web, no Flutter GPU). Set `fake: true` on a layer to use it on purpose, or
to test that path.

It keeps frost, tint, the color model, the glint, the contour, the inner
shadow, visibility and exterior shadows. It leaves out refraction,
`backdropShrink`, `dispersion` and the direct model's vibrancy.

`FakeGlass` is not a cheaper mode: it pays for the same backdrop readback and
blur as full glass (see below).

## Glass on glass

Apple's guidance is not to stack glass on glass. Sometimes you have to, for
example with an indicator that slides over its tab bar and should refract it.

Where it can, glass doesn't read the screen live. Each layer paints over a
copy of what lies under it, drawn from the layer tree while the frame
composites and kept while that content stays the same. Glass that sits close
together shares one copy. Glass on glass works the same way: the copy under
the indicator holds the bar, so the indicator refracts it, and the frame draws
that copy after the bar's.

| | The top glass shows | Trade-off |
| --- | --- | --- |
| Shapes in one `LiquidGlassLayer` | The content below | Shared settings. The shapes can't refract each other. |
| A `LiquidGlass` in the child of another, or a layer over a layer | The glass below | One more copy for the glass on top. |

## Performance

The unit of cost is the backdrop read, not the glass widget. Glass paints
over a copy of what lies under it (see [Glass on glass](#glass-on-glass)), and
a frame whose glass all paints over copies skips Impeller's offscreen pass and
its screen readbacks. Glass reads the backdrop itself only where no copy can be
drawn: over a platform view, a backdrop filter (glass that reads its backdrop
is one), or a layer type the renderer does not know
(`LiquidGlassUnderlay.registerLayer` teaches it one). Over a texture the copy is
drawn again each frame instead of held. On
top of that, a plain blur, `FakeGlass` and full glass each cost progressively
more, and every glass shadow adds its own cost.

Best practices:

- **Put siblings in one layer.** A layer draws all its shapes together and
  pays its own per-layer work once.
- **Keep layers small.** A layer's cost grows with the area its glass covers.
- **Don't animate blend-group geometry every frame.** Moving one shape in a
  group re-renders the whole group's geometry, which can drop frames. Static
  geometry is cached.
- **Keep shadows few and small.**
- **Mind the blur.** Larger blurs cost more, but Impeller picks a power-of-two
  downsample factor from the blur's device-space size and only starts
  downsampling past a few device pixels, so very small blurs can cost more than
  moderate ones. A frost fitted to iOS 27, the default, is raised to that
  point per device and scaled by the glass's short side; a
  `LiquidGlassFrost.sigma` is used as given.
- **For low power, don't sample the backdrop.** `FakeGlass` pays the same copy
  and blur as full glass. When the device or power state calls for it, draw an
  opaque surface instead.
- **Optionally await `precacheLiquidGlass()` before `runApp`.**

Measurements are in the
[performance audit](example/tool/results/performance-audit.md), and the
[Android GPU power harness](example/tool/README.md#android-pixel-10)
measures your own screens.

## Example playground

```sh
cd packages/liquid_glass_renderer/example
flutter run --enable-impeller --enable-flutter-gpu
```

The playground has an iOS-style tab bar and toolbar, blending and color
scenes, the text loupe, every preset in light and dark, the Liquid Glass
slider, full/fake switching and several backdrops. **Copy as Dart** gives the
settings you tune as code.

## Upgrading from 1.0.0-dev.2

Run `dart fix --apply` after the upgrade. It handles most of the breaking
changes:

- `debugPaintLiquidGlassGeometry` now comes from `rendering.dart`. The fix
  adds the import.
- `LiquidGlassSettings.of(context)` becomes
  `LiquidGlassLayer.settingsOf(context)`.
- `LiquidGlass.precache()` becomes `precacheLiquidGlass()`.
- `LiquidGlass.grouped(...)` becomes `LiquidGlass(...)`. The fix skips a call
  written with its own `const`.
- On `LiquidGlassSettings`, `tintAmount` becomes `sliderPosition` and
  `highlight` becomes `glintStrength`.
- `ios27RegularLight(...)` and `ios27RegularDark(...)` on
  `LiquidGlassSettings` and `LiquidGlassAppearance` become
  `ios27Regular(brightness: ...)`.
- `LiquidGlassColorModel.ios27` becomes `LiquidGlassColorModel.ios27Regular`.

  The fix skips a call of these three written with its own `const`
  (`const LiquidGlassColorModel.ios27(...)`): change those by hand.
- On `LiquidRoundedSuperellipse` and `LiquidRoundedRectangle`, the
  `borderRadius` argument becomes `radius`.
- `useBackdropGroup` and `backdropKey` are dropped from `LiquidGlassLayer`,
  `FakeGlass` and calls of `LiquidGlass.auto` and `LiquidGlass.withOwnLayer`,
  which then need the hand change below. The renderer now decides which glass
  shares a backdrop read. A `BackdropKey` you made only for the glass is left
  unused, delete it.

A few changes need a hand:

- A `LiquidGlass` draws where the tree puts it, and no constructor says it a
  second time. Any `LiquidGlass` inside a `LiquidGlassBlendGroup` now blends
  with the group: move a shape that should not blend out of the group.
- `LiquidGlass.withOwnLayer(settings: s, fake: f, appearance: a, ...)` becomes
  `LiquidGlassLayer(settings: s, fake: f, defaultAppearance: a, child:
  LiquidGlass(...))`.
- `LiquidGlass.auto(...)` becomes `LiquidGlass(...)` under a layer. Code that
  may be built without one asks `LiquidGlassLayer.maybeSettingsOf(context)`
  and wraps its glass in a `LiquidGlassLayer` when that is null.
- `GlassGlow`, `GestureMode`, `LiquidStretch`, `RawLiquidStretch` and
  `GlassGlowLayer` are gone: the renderer no longer animates. Drive the glass
  from your own motion through `LiquidGlass.live` and `LiquidGlassGlow`, or
  take these widgets from a widget library built on the renderer.
- Remove `LiquidGlassCapture` and keep its child. Glass over glass refracts
  the glass below without it, see [Glass on glass](#glass-on-glass).
- `LgrLogs` is gone, along with the dependency on `logging`.
- `LiquidGlassBlendGroup.maxShapesPerLayer` is gone. The limit is still 16,
  see [Limitations](#limitations).
- `LiquidGlassLayer.existsIn(context)` is gone: write
  `LiquidGlassLayer.maybeSettingsOf(context) != null`.
- `FakeGlass.inLayer` is gone. For fake glass on a layer, put a `LiquidGlass`
  in a `LiquidGlassLayer(fake: true)`; a `FakeGlass` is a lone shape with its
  own `settings` and `appearance`, neither of which is nullable any more.
- `precacheLiquidGlass()` returns a `LiquidGlassSupport` where
  `LiquidGlass.precache()` returned nothing: see
  [Is full glass available?](#is-full-glass-available).
- `Offset.withResistance` is gone. It computed
  `offset * (1 / (1 + offset.distance * resistance))`.
- `LiquidGlassSettings`, `LiquidGlassAppearance`, `LiquidGlassColorModel` and
  the shapes no longer mix in `Equatable`, so `props` is gone. `==` and
  `hashCode` still compare values.
- `LiquidGlassSettings.frost` is a `LiquidGlassFrost`: write `frost: 12` as
  `frost: LiquidGlassFrost.sigma(12)`. Leave it out for the frost fitted to
  iOS 27, which now follows `sliderPosition`, as the settings' haze does: a
  `copyWith(sliderPosition:)` moves both.
- `LiquidGlassSettings.ios27RegularFrost`, `ios27ClearFrost` and
  `frostSigmaAt` are gone: `LiquidGlassFrost.ios27Regular()` and
  `LiquidGlassFrost.ios27Clear()` are those blurs.
- `toJson` and `fromJson` are gone from `LiquidGlassSettings`,
  `LiquidGlassAppearance` and `LiquidGlassColorModel`. Read and write the
  fields you store yourself.
- `LiquidGlassColorModel` is sealed: `direct(...)`, `ios27Regular(...)` and
  `ios27Clear()` build a `LiquidGlassDirectColorModel`, a
  `LiquidGlassIos27RegularColorModel` and a `LiquidGlassIos27ClearColorModel`.
  `saturation` and `vibrancy` are on the direct model alone, so read them
  after a type test or compare models with `==`.
- `LiquidGlassColorModel(parameters)` and `LiquidGlassColorModel.parameters`
  are gone, with the parameter types they took from `src`: the fitted
  constants follow the final shader and change with it. Use the direct model
  or an iOS 27 one.
- Every `LiquidGlassAppearance` constructor now defaults `tint` to
  `Color(0x00000000)`. The presets used a transparent blue and the unnamed
  constructor a transparent white, none of which draws; code that only raised
  the alpha of a default tint now names its color.
- Shadows of glass are `LiquidGlassShadow`s, no longer `BoxShadow`s: write
  `BoxShadow(color: c, offset: o, blurRadius: b, spreadRadius: s)` as
  `LiquidGlassShadow(color: c, offset: o, blurRadius: b, spreadRadius: s)`
  in `LiquidGlass.shadows` and `FakeGlass.shadows`.
- `borderRadius` on a `LiquidRoundedSuperellipse` and a
  `LiquidRoundedRectangle` is now a `BorderRadius`; the number is `topRadius`
  or `radius`. `copyWith(borderRadius: r)` on a superellipse set all four
  corners; build `LiquidRoundedSuperellipse(radius: r)` instead.
- A `LiquidGlassLayer` without `settings` now draws the regular glass of the
  platform brightness, as it did for its default appearance: in dark mode its
  haze and contour are the dark ones. Pass `const LiquidGlassSettings()` to
  keep the light ones.

## Limitations

- Experimental: not yet battle-tested in production apps.
- Full glass needs Impeller and Flutter GPU; the web renders `FakeGlass`.
- At most 16 shapes that blend or touch; a field takes its looks from at most
  16 shapes.
- One corner radius per shape, except a superellipse's top and bottom pair
  (`LiquidRoundedSuperellipse.vertical`).
- A glass widget's child is painted on top of the glass, never refracted by
  it.

[lintervention_link]: https://github.com/whynotmake-it/lintervention
[lintervention_badge]: https://img.shields.io/badge/lints_by-lintervention-3A5A40
