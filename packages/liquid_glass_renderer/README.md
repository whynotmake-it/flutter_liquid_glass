# Liquid Glass Renderer

<!-- [![Code Coverage](./coverage.svg)](./test/) -->
[![Pub Version](https://img.shields.io/pub/v/liquid_glass_renderer)](https://pub.dev/packages/liquid_glass_renderer)
[![Code Coverage](./coverage.svg)](./test/)
[![lints by lintervention][lintervention_badge]][lintervention_link]


> **Note:** This package is currently in a pre-release stage. The API may change, and there are some limitations. Feedback and contributions are highly welcome!

A Flutter package for creating a stunning "liquid glass" or "frosted glass" effect. This package allows you to transform your widgets into beautiful, customizable glass-like surfaces that can blend and interact with each other.


![Example GIF](doc/example.gif)
> The actual performance of this effect is much better, the GIFs in this README just have a low framerate.

## Features

-   🫧 **Implement Glass Effects**: Easily wrap any widget to give it a glass effect.
-   🔀 **Blending Layers**: Create layers where multiple glass shapes can blend together like liquid.
-   🎨 **Highly Customizable**: Adjust thickness, color tint, lighting, and more.
-   🔍 **Background Effects**: Apply background blur and refraction.
-   🚀 **Performant**: Built on top of Flutter's shader support for great performance.

## ⚠️ Limitations

As this is a pre-release, there are a few things to keep in mind:

- **Only works on Impeller**, so Web, Windows, and Linux are entirely unsupported for now
- **Maximum of three shapes** can be blended in a `LiquidGlassLayer`.
- The experimental `Glassify` widget has lower performance and visual quality than `LiquidGlass`.

## Acknowledgements

A huge shoutout to [Renan Aurujo (@renancaraujo)](https://github.com/renancaraujo) for contributing key ideas to the implementation of [`Glassify`](#glassify-glass-effect-on-any-shape-experimental).
Check out is work, he's pretty cool and nice too :)

Also, thank you to [Tong Mu (@dkwingsmt)](https://github.com/dkwingsmt) for helping me with rounded superellipses.

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

![Showcase](doc/showcase.gif)
> Demo by [Souvik Biswas](https://github.com/sbis04/liquid_glass_demo)

The liquid glass effect is achieved by taking the pixels of the content *behind* the glass widget and distorting them. For the effect to be visible, you **must** place your glass widget on top of other content. The easiest way to do this is with a `Stack`.

```dart
Stack(
  children: [
    // 1. Your background content goes here
    MyBackgroundContent(),

    // 2. The glass widget goes on top
    LiquidGlass(...)
  ],
)
```

### Choosing the Right Widget

This package provides three main widgets to create the glass effect:

| Widget               | Use Case                                                                              |
| -------------------- | ------------------------------------------------------------------------------------- |
| `LiquidGlass`        | For a single, high-quality glass shape. Best performance and quality.                 |
| `LiquidGlassLayer`   | To blend multiple `LiquidGlass` shapes together seamlessly.                           |
| `Glassify` (Experimental) | To apply a glass effect to any arbitrary widget (e.g., text, icons). Less performant. |

---

## Examples

### `LiquidGlass`: A Single Glass Shape

![Shapes Demo](doc/shapes.png)


The quickest way to get started is to wrap your widget with `LiquidGlass`. This creates a single glass object with a defined shape.

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
          // The LiquidGlass widget sits on top
          Center(
            child: LiquidGlass(
              shape: LiquidRoundedSuperellipse(
                borderRadius: Radius.circular(50),
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
        ],
      ),
    );
  }
}
```

#### Supported Shapes (in order of appearance)

The LiquidGlass widget supports the following shapes at the moment:

-   `LiquidRoundedSuperellipse` (recommended)
-   `LiquidOval`
-   `LiquidRoundedRectangle`

All shapes only support uniform `Radius.circular` for now.



### `LiquidGlassLayer`: Blending Multiple Shapes

![Blending Demo](doc/blended.png)

For shapes to blend, they must be children of the same `LiquidGlassLayer`. Use `LiquidGlass.inLayer` for each shape.

```dart
LiquidGlassLayer(
  child: Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      LiquidGlass.inLayer(
        shape: LiquidRoundedSuperellipse(
          borderRadius: Radius.circular(40),
        ),
        child: const SizedBox.square(dimension: 100),
      ),
      const SizedBox(height: 100),
      LiquidGlass.inLayer(
        shape: LiquidRoundedSuperellipse(
          borderRadius: Radius.circular(40),
        ),
        child: const SizedBox.square(dimension: 100),
      ),
    ],
  ),
)
```

### `Glassify`: Glass Effect on Any Shape (Experimental)



> ⚠️ `Glassify` is experimental. It is significantly less performant and will produce lower-quality results than `LiquidGlass`. 
> 
> **Never use it for primitive shapes that could be rendered with `LiquidGlass`!**

![Glassify Demo](doc/clock.gif)

The `Glassify` widget can apply the glass effect to any child widget, not just a predefined shape. This is useful for text, icons, or custom-painted widgets.

Apple themselves barely use this effect, one of their uses is the time on the lock screen. 
To make it look best, consider a few key tips:

- Try to limit the use of these widgets on each screen, to keep the performance good
- Always apply at least a subtle blur (5-10px)to hide potential artifacts
- The algorithm often falls apart for high thicknesses, try to keep it below 20px for best results
- Depending on the shape, you might need to adjust `lightIntensity` and `ambientStrength` to make it look best
- Colors help maintain readability

```dart
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
        color: Colors.black, // The color here is only for the shape
      ),
    ),
  ),
)
```

---

## Customization

### `LiquidGlassSettings`

You can customize the appearance of the glass by providing `LiquidGlassSettings` to either a `LiquidGlass`, `LiquidGlassLayer`, or `Glassify` widget.

```dart
LiquidGlassLayer(
  settings: const LiquidGlassSettings(
    thickness: 10,
    glassColor: Color(0x1AFFFFFF), // A subtle white tint
    lightIntensity: 1.5,
    blend: 40,
    outlineIntensity: 0.5,
  ),
  child: // ... your LiquidGlass.inLayer widgets
)
```

Here's a breakdown of the key settings:

-   `glassColor`: The color tint of the glass. The alpha channel controls the intensity.
-   `thickness`: How much the glass refracts the background.
-   `blend`: How smoothly two shapes merge when they are close.
-   `lightAngle`, `lightIntensity`: Control the direction and brightness of the virtual light source, creating highlights.
-   `ambientStrength`: The intensity of ambient light.
-   `outlineIntensity`: The visibility of the glass outline.

### Adding Blur

You can apply a background blur using the `blur` property. This is independent of the glass refraction effect. Note that on `Glassify`, the blur quality is currently limited.

```dart
LiquidGlass(
  blur: 5.0,
  shape: //...
  child: //...
)
```

### Child Placement

The `child` of a `LiquidGlass` widget can be rendered either "inside" the glass or on top of it using the `glassContainsChild` property.

-   `glassContainsChild: true` (default): The child is part of the glass, affected by color tint and refraction.
-   `glassContainsChild: false`: The child is rendered normally on top of the glass effect.

---

For more details, check out the API documentation in the source code.

---

[mason_link]: https://github.com/felangel/mason
[mason_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Ftinyurl.com%2Fmason-badge
[lintervention_link]: https://github.com/whynotmake-it/lintervention
[lintervention_badge]: https://img.shields.io/badge/lints_by-lintervention-3A5A40

[flutter_install_link]: https://docs.flutter.dev/get-started/install

