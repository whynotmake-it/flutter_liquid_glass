# Liquid Glass Renderer

<!-- [![Code Coverage](./coverage.svg)](./test/) -->
[![Pub Version](https://img.shields.io/pub/v/liquid_glass_renderer)](https://pub.dev/packages/liquid_glass_renderer)
[![Code Coverage](./coverage.svg)](./test/)
[![lints by lintervention][lintervention_badge]][lintervention_link]


> ## ⚠️ **EXPERIMENTAL - USE WITH CAUTION**
>
> **This package is still experimental and should not be blindly added to production apps for all devices.** While performance has improved significantly, liquid glass effects in Flutter are computationally intensive due to the limited access to the GPUand may not perform well on all hardware configurations. 
> 
> **Before deploying to production:**
> - **Take a look at the [Limitations](#limitations) and [Performance](#-a-word-on-performance) sections** before even thinking about using this package in production.
> - **Make sure your App is built on Impeller**. Skia is unsupported for now
> - **Test thoroughly on your target devices**, especially lower-end and mid-range devices
> - **Monitor performance metrics** (memory usage, frame rates, power consumption, jank)
> - **Use `FakeGlass` strategically**: Swap out `LiquidGlass` widgets with `FakeGlass` when they're not highly visible, off-screen, or have low visual impact
>
> **We need your feedback!** Please test on your devices and report performance characteristics, issues, and suggestions.



A Flutter package for creating a stunning "liquid glass" or "frosted glass" effect. This package allows you to transform your widgets into beautiful, customizable glass-like surfaces that can blend and interact with each other.


![Showcase GIF](doc/showcase.gif)

## Features

-   🫧 **Implement Glass Effects**: Easily wrap any widget to give it a glass effect.
-   🔀 **Blending Layers**: Create layers where multiple glass shapes can blend together like liquid.
-   🎨 **Highly Customizable**: Adjust thickness, color tint, lighting, and more.
-   🔍 **Background Effects**: Apply background blur and refraction.
-   ✨ **Interactive Glow**: Add touch-responsive glow effects to glass surfaces.
-   🎭 **Fake Glass**: Lightweight glass appearance without expensive shaders for better performance.
-   🤸 **Stretch Effects**: Apply organic squash and stretch animations to glass widgets.

## Installation

**In order to start using Flutter Liquid Glass you must have the [Flutter SDK][flutter_install_link] installed on your machine.**

Install via `flutter pub add`:

```sh
flutter pub add liquid_glass_renderer
```

And import it in your Dart code:

```dart
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
```

## How To Use

![Example GIF](doc/example.gif)

The liquid glass effect is achieved by taking the pixels of the content *behind* the glass widget and distorting them. For the effect to be visible, you **must** place your glass widget on top of other content. The easiest way to do this is with a `Stack`.

Make sure to read the [Performance](#-a-word-on-performance) section for tips on getting the best performance out of the package.

```dart
Stack(
  children: [
    // 1. Your background content goes here
    MyBackgroundContent(),

    // 2. Create a layer for liquid glass effects
    LiquidGlassLayer(
      // 3. Add your LiquidGlass widgets here
      child: LiquidGlass(
        shape: LiquidRoundedSuperellipse(borderRadius: 30),
        child: const SizedBox.square(dimension: 100),
      ),
    ),
  ],
)
```

### What's in the box?

This package provides several widgets to create the glass effect:

| Widget                    | Use Case                                                                                   |
| ------------------------- | ------------------------------------------------------------------------------------------ |
| `LiquidGlassLayer`        | Container for all liquid glass effects. Required parent for `LiquidGlass` widgets.         |
| `LiquidGlass`             | Creates a single glass shape. Must be inside a `LiquidGlassLayer`.                         |
| `LiquidGlassBlendGroup`   | Groups multiple `LiquidGlass.grouped` shapes to blend them together seamlessly.            |
| `FakeGlass`               | Lightweight glass appearance without refraction. Better performance, less visual fidelity. |
| `GlassGlow`               | Add touch-responsive glow effects to glass surfaces.                                       |
| `LiquidStretch`           | Add interactive squash and stretch effects to glass widgets.                               |
| `Glassify` (Experimental) | To apply a glass effect to any arbitrary widget (e.g., text, icons). Less performant.      |

### ⚠️ Limitations

As this is a pre-release, there are a few things to keep in mind:

- **Only works on Impeller**, so Web, Windows, and Linux are entirely unsupported for now
- **Memory spike when animating shapes** There is a [bug in Flutter](https://github.com/flutter/flutter/issues/138627) that prevents us from disposing generated textures immediately, leading to temporary memory spikes when animating glass shapes. Read [A word on Performance](#-a-word-on-performance) for tips on minimizing this.
- **Maximum of 16 shapes** can be blended in a `LiquidGlassBlendGroup`, and performance will degrade significantly with the more shapes you add in the same group.
- **Blur** introduces artifacts when blending shapes, and is entirely unsupported for `Glassify`. Upvote [this issue](https://github.com/flutter/flutter/issues/170820) to get that fixed.


### 🚨 A word on Performance

The liquid glass effect is computationally intensive, especially on mobile devices. To save GPU cycles, `liquid_glass_renderer` will try to cache geometry in textures wherever possible.

#### Memory Usage
Unfortunately, due to a [Flutter bug](https://github.com/flutter/flutter/issues/138627), we cannot dispose of these textures immediately, which may lead to temporary memory spikes when animating glass shapes. Please upvote the issue to help get it fixed!

#### Best Practices
To ensure the best performance when using liquid glass effects, consider the following tips:
- **Use `LiquidGlassLayer` for shapes that share the same settings.** Creating many individual layers is expensive.
- **Minimize the amount of pixels covered by `LiquidGlassLayer` and `LiquidGlassBlendGroup`**: Both `LiquidGlassLayer` and `LiquidGlassBlendGroup` will create textures that cover their entire area. 
Try to keep these areas as small as possible.
If you have a large area with sparse glass shapes, consider splitting them into multiple smaller layers/groups.
- **Limit the number of blended shapes**: Each additional shape in a `LiquidGlassBlendGroup` increases the computational load. 
Try to keep the number of blended shapes low.
- **Limit animations**: The glass effect is almost free while shapes remain in the same position onscreen.
Moving shapes forces the package to re-render their glass effect every frame, which is expensive.
In a `LiquidGlassBlendGroup`, moving any shape forces all shapes in the group to re-render.

---

## Examples

### `LiquidGlass`: A Single Glass Shape

![Shapes Demo](doc/shapes.png)

To create glass shapes, you must wrap them in a `LiquidGlassLayer`. This layer manages the rendering of all glass effects within it.

```dart
import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

class MyGlassWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // This is the content that will be behind the glass
          Positioned.fill(
            child: Image.network(
              'https://picsum.photos/seed/glass/800/800',
              fit: BoxFit.cover,
            ),
          ),
          // The LiquidGlassLayer manages glass rendering
          Center(
            child: LiquidGlassLayer(
              settings: const LiquidGlassSettings(
                thickness: 20,
                blur: 10,
                glassColor: Color(0x33FFFFFF),
              ),
              child: LiquidGlass(
                shape: LiquidRoundedSuperellipse(
                  borderRadius: 50,
                ),
                child: const SizedBox(
                  height: 200,
                  width: 200,
                  child: Center(
                    child: FlutterLogo(size: 100),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
```

If you need a single glass shape with custom settings and don't want to create a separate `LiquidGlassLayer`, you can use `LiquidGlass.withOwnLayer`:

```dart
LiquidGlass.withOwnLayer(
  settings: const LiquidGlassSettings(
    thickness: 15,
    blur: 8,
  ),
  shape: LiquidRoundedSuperellipse(borderRadius: 30),
  child: const SizedBox.square(dimension: 100),
)
```

**Note:** Make sure you have read the [Performance](#-a-word-on-performance) section for tips on getting the best performance out of the package.

#### Supported Shapes

The LiquidGlass widget supports the following shapes:

-   `LiquidRoundedSuperellipse` (recommended) - A smooth, rounded squircle shape
-   `LiquidOval` - A perfect ellipse/circle
-   `LiquidRoundedRectangle` - A rounded rectangle

All shapes take a simple `double` for `borderRadius` instead of `BorderRasdius` or `Radius`, since they don't support non-uniform radii.


### `LiquidGlassBlendGroup`: Blending Multiple Shapes

![Blending Demo](doc/blended.png)

To blend multiple glass shapes together seamlessly, wrap them in a `LiquidGlassBlendGroup` inside a `LiquidGlassLayer`. Use `LiquidGlass.grouped()` for shapes that should blend together.

```dart
LiquidGlassLayer(
  settings: const LiquidGlassSettings(
    thickness: 20,
    blur: 10,
  ),
  child: LiquidGlassBlendGroup(
    blend: 20.0, // Controls how much shapes blend together
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        LiquidGlass.grouped(
          shape: LiquidRoundedSuperellipse(
            borderRadius: 40,
          ),
          child: const SizedBox.square(dimension: 100),
        ),
        const SizedBox(height: 50),
        LiquidGlass.grouped(
          shape: LiquidRoundedSuperellipse(
            borderRadius: 40,
          ),
          child: const SizedBox.square(dimension: 100),
        ),
      ],
    ),
  ),
)
```

You can have multiple `LiquidGlass` widgets in a `LiquidGlassLayer` without blending by using the default `LiquidGlass()` constructor (not `.grouped()`).

## Customization

### `LiquidGlassSettings`

You can customize the appearance of the glass by providing `LiquidGlassSettings` to a `LiquidGlassLayer` or `LiquidGlass.withOwnLayer()`. All glass widgets within that layer will share these settings.

```dart
LiquidGlassLayer(
  settings: const LiquidGlassSettings(
    thickness: 10,
    glassColor: Color(0x1AFFFFFF),
    lightIntensity: 1.5,
    outlineIntensity: 0.5,
    saturation: 1.2,
  ),
  child: LiquidGlassBlendGroup(
    blend: 40, // blend is now on LiquidGlassBlendGroup, not settings
    child: // ... your LiquidGlass.grouped widgets
  ),
)
```

Here's a breakdown of the key settings:

-   `glassColor`: The color tint of the glass. The alpha channel controls the intensity.
-   `thickness`: How much the glass refracts the background (higher = more distortion).
-   `blur`: Background blur strength (0 = no blur).
-   `refractiveIndex`: The refractive index of the glass material (1.0 = no refraction, ~1.5 = realistic glass).
-   `lightAngle`, `lightIntensity`: Control the direction and brightness of the virtual light source, creating highlights.
-   `ambientStrength`: The intensity of ambient light on the glass.
-   `outlineIntensity`: The visibility of the glass outline/edge.
-   `saturation`: Adjusts the color saturation of background pixels visible through the glass (1.0 = no change, <1.0 = desaturated, >1.0 = more saturated).

**Note:** The `blend` parameter has been moved from `LiquidGlassSettings` to the `LiquidGlassBlendGroup` constructor, as it specifically controls shape blending behavior.

Increasing saturation when using colored glass helps achieve an Apple-like aesthetic.

### Adding Blur

You can apply a background blur using the `blur` property in `LiquidGlassSettings`. This is independent of the glass refraction effect.

```dart
LiquidGlassLayer(
  settings: const LiquidGlassSettings(
    blur: 10.0,
    thickness: 20,
  ),
  child: // ... your glass widgets
)
```

**Note:** Blur is not supported in `Glassify` due to performance constraints.

### Child Placement

The `child` of a `LiquidGlass` widget can be rendered either "inside" the glass or on top of it using the `glassContainsChild` property.

-   `glassContainsChild: false` (default): The child is rendered normally on top of the glass effect.
-   `glassContainsChild: true`: The child is part of the glass, affected by color tint and refraction.

### `FakeGlass`: Lightweight Glass Alternative

For scenarios where performance is critical or you need a glass-like appearance without the computational cost of refraction, use `FakeGlass`. It provides a similar visual effect using backdrop filters instead of shaders.

```dart
FakeGlass(
  shape: LiquidRoundedSuperellipse(
    borderRadius: 20,
  ),
  settings: const LiquidGlassSettings(
    blur: 10,
    glassColor: Color(0x33FFFFFF),
  ),
  child: const SizedBox(
    height: 100,
    width: 100,
    child: Center(child: Text('Fast Glass')),
  ),
)
```

Alternatively, you can enable fake glass for an entire layer:

```dart
LiquidGlassLayer(
  fake: true,
  settings: const LiquidGlassSettings(
    blur: 10,
    glassColor: Color(0x33FFFFFF),
  ),
  child: // ... your glass widgets will automatically use FakeGlass
)
```

**Note:** `FakeGlass` does not support `thickness` or `refractiveIndex` properties since it doesn't perform actual refraction.

### `GlassGlow`: Interactive Touch Effects

Add responsive glow effects that follow user touches. Wrap your content with `GlassGlow` inside your glass widget. The `GlassGlowLayer` is automatically included by `LiquidGlass`.

```dart
LiquidGlassLayer(
  child: LiquidGlass(
    shape: LiquidRoundedSuperellipse(
      borderRadius: 20,
    ),
    child: GlassGlow(
      glowColor: Colors.white24,
      glowRadius: 1.0,
      child: const SizedBox(
        height: 100,
        width: 100,
        child: Center(child: Text('Touch Me')),
      ),
    ),
  ),
)
```

The glow effect automatically appears at touch locations and fades out smoothly when interaction ends.

### `LiquidStretch`: Organic Squash and Stretch

Add interactive squash and stretch effects that respond to user gestures, creating an organic, jelly-like feel:

```dart
LiquidStretch(
  stretch: 0.5,
  interactionScale: 1.05,
  child: LiquidGlass(
    shape: LiquidRoundedSuperellipse(
      borderRadius: 20,
    ),
    child: const SizedBox(
      height: 100,
      width: 100,
      child: Center(child: Text('Stretchy')),
    ),
  ),
)
```

The widget listens to drag gestures and applies smooth squash and stretch transformations without interfering with other gestures.


### `Glassify`: Glass Effect on Any Shape (Experimental)



> ⚠️ `Glassify` is experimental. It is significantly less performant and will produce lower-quality results than `LiquidGlass`. 
>
> **Don't use it in production unless you have clearly tested and validated it on your target devices.**
> 
> **Never use it for primitive shapes that could be rendered with `LiquidGlass`!**

![Glassify Demo](doc/clock.gif)

The `Glassify` widget can apply the glass effect to any child widget, not just a predefined shape. This is useful for text, icons, or custom-painted widgets.

Apple themselves barely use this effect, one of their uses is the time on the lock screen. 
To make it look best, consider a few key tips:

- Try to limit the use of these widgets on each screen, to keep the performance good
- **Note: Blur is not supported in `Glassify`** due to performance constraints. The shader has been optimized to remove blur to improve mobile GPU performance.
- The algorithm often falls apart for high thicknesses, try to keep it below 20px for best results
- Depending on the shape, you might need to adjust `lightIntensity` and `ambientStrength` to make it look best
- Colors help maintain readability

```dart
// Important: You need to import from experimental.dart
import 'package:liquid_glass_renderer/experimental.dart';

Center(
  child: Glassify(
    settings: const LiquidGlassSettings(
      thickness: 5,
      glassColor: Color(0x33FFFFFF),
    ),
    child: const Text(
      'Liquid',
      style: TextStyle(
        fontSize: 120,
        fontWeight: FontWeight.bold,
        color: Colors.black,
      ),
    ),
  ),
)
```

---

---

For more details, check out the API documentation in the source code.

---

[mason_link]: https://github.com/felangel/mason
[mason_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Ftinyurl.com%2Fmason-badge
[lintervention_link]: https://github.com/whynotmake-it/lintervention
[lintervention_badge]: https://img.shields.io/badge/lints_by-lintervention-3A5A40

[flutter_install_link]: https://docs.flutter.dev/get-started/install

