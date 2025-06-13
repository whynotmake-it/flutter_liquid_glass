# Liquid Glass Renderer

<!-- [![Code Coverage](./coverage.svg)](./test/) -->
[![lints by lintervention][lintervention_badge]][lintervention_link]

A Flutter package for creating a stunning "liquid glass" or "frosted glass" effect. This package allows you to transform your widgets into beautiful, customizable glass-like surfaces that can blend and interact with each other.

> **Note:** This package is currently in a pre-release stage. The API may change, and there are some limitations. Feedback and contributions are highly welcome!



![Example GIF](doc/example.gif)
> Note that the actual performance of this effect is much better, the GIF just has a low framerate.

## Features

-   **Standalone Glass Widgets**: Easily wrap any widget to give it a glass effect.
-   **Blending Layers**: Create layers where multiple glass shapes can blend together like liquid.
-   **Highly Customizable**: Adjust thickness, color tint, lighting, and more.
-   **Background Effects**: Apply background blur and refraction.
-   **Performant**: Built on top of Flutter's shader support for great performance.

## Limitations

As this is a pre-release, there are a few things to keep in mind:

- **Only works on Impeller**, so Web, Windows, and Linux are entirely unsupported for now
- **Maximum of two shapes** can be blended in a `LiquidGlassLayer`.

## Installation 💻

**❗ In order to start using Flutter Liquid Glass you must have the [Flutter SDK][flutter_install_link] installed on your machine.**

Install via `flutter pub add`:

```sh
flutter pub add liquid_glass_renderer
```

And import it in your Dart code:

```dart
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
```

## Getting Started

The quickest way to use the liquid glass effect is to wrap your widget with the `LiquidGlass` widget. For the effect to be visible, you must place it on top of other content. A `Stack` is a great way to achieve this.

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
              shape: LiquidGlassSquircle(
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

This creates a single glass object on its own layer, refracting the image behind it.

## How It Works: Positioning the Glass

The liquid glass effect is achieved by taking the pixels of the content *behind* the `LiquidGlass` widget and distorting them. This means that for the refraction to be visible, you must place your `LiquidGlass` or `LiquidGlassLayer` on top of other widgets.

The easiest way to do this is with a `Stack`. Place your background content as the first child of the `Stack`, and then place the `LiquidGlass` widget on top of it.

```dart
Stack(
  children: [
    // Widgets in the background
    MyBackgroundContent(),

    // The glass layer on top
    LiquidGlassLayer(...)
  ],
)
```

If you place a `LiquidGlass` widget directly inside a `Scaffold` body without a `Stack`, there will be nothing behind it to refract but the `Scaffold`'s background color.

## Usage

### Blending Multiple Shapes

For shapes to blend together, they must be part of the same `LiquidGlassLayer`. Just like with a single `LiquidGlass` widget, you'll want to place the layer inside a `Stack` to see the effect.

```dart
Widget build(BuildContext context) {
  return Stack(
    alignment: Alignment.center,
    children: [
      // This is the content that will be behind the glass
      Positioned.fill(
        child: Image.network(
          'https://picsum.photos/seed/glass/800/800',
          fit: BoxFit.cover,
        ),
      ),
      // The LiquidGlassLayer renders the blending shapes
      LiquidGlassLayer(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LiquidGlass.inLayer(
              shape: LiquidGlassSquircle(
                borderRadius: Radius.circular(40),
              ),
              child: const SizedBox.square(dimension: 100),
            ),
            const SizedBox(height: 100),
            LiquidGlass.inLayer(
              shape: LiquidGlassSquircle(
                borderRadius: Radius.circular(40),
              ),
              child: const SizedBox.square(dimension: 100),
            ),
          ],
        ),
      ),
    ],
  );
}
```

### Customizing the Effect

You can customize the appearance of the glass by providing `LiquidGlassSettings` to either a standalone `LiquidGlass` widget or a `LiquidGlassLayer`.

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

### Child Placement

The `child` of a `LiquidGlass` widget can be rendered either "inside" the glass or on top of it using the `glassContainsChild` property.

-   `glassContainsChild: true` (default): The child is part of the glass, affected by color tint and refraction.
-   `glassContainsChild: false`: The child is rendered normally on top of the glass effect.

### Adding Blur

You can apply a background blur to a `LiquidGlass` widget using the `blur` property. This is independent of the glass refraction effect.

```dart
LiquidGlass(
  blur: 5.0,
  shape: //...
  child: //...
)
```

## API Reference

The main components of this package are:

-   **`LiquidGlass`**: The primary widget for creating a glass effect.
-   **`LiquidGlassLayer`**: A widget that enables blending between multiple `LiquidGlass` shapes.
-   **`LiquidGlassSettings`**: A class to configure the visual properties of the glass.
-   **`LiquidGlassShape`**: The base class for shapes. Currently, only `LiquidGlassSquircle` is implemented.

For more details, check out the API documentation in the source code.

---

[mason_link]: https://github.com/felangel/mason
[mason_badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Ftinyurl.com%2Fmason-badge
[lintervention_link]: https://github.com/whynotmake-it/lintervention
[lintervention_badge]: https://img.shields.io/badge/lints_by-lintervention-3A5A40

[flutter_install_link]: https://docs.flutter.dev/get-started/install

