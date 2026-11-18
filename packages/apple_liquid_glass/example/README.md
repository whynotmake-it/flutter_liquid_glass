# apple_liquid_glass gallery

A catalog of `apple_liquid_glass`: every control, menu and presentation,
live, over photographs so the glass has something to bend.

## Run it

```sh
cd packages/apple_liquid_glass/example
flutter run --release
```

It runs on iOS, Android and macOS with liquid glass. Flutter GPU and Impeller
are turned on in `ios/Runner/Info.plist`, `macos/Runner/Info.plist` and
`android/app/src/main/AndroidManifest.xml`, so no extra flags are needed. On
the web (`flutter run -d chrome`) it draws fake glass.

## Tabs

- **Components**: every component of the package, grouped as material,
  controls, content, menus and presentations, and bars. A row opens the
  component live, with its parameters to change and ideas of what to build
  with it.
- **Glass**: the material, one property at a time, each with one control to
  try it.
- **Motion**: what kinesis gives an app: layouts that animate,
  presentations, a control of its own, and a replay of a touch, with a
  Reduce Motion switch.
- **Search**: the tab bar's search tab, which searches the gallery.

## Switching the renderer

Every page's navigation bar has two items at its trailing end. The drop
switches the whole app between glass and flat. The gear opens the settings
sheet, where the **Renderer** row picks Liquid, Fake or Flat, next to the
appearance, the accent color, the Liquid Glass slider, the accessibility
traits (Reduce Transparency, Show Borders, Prefer Cross-Fade) and a frame
meter.

In code, `lib/settings.dart` maps the choice to `LiquidGlassRenderer`,
`FakeGlassRenderer` or `FlatGlassRenderer`, and `lib/app.dart` passes it to
the `GlassScope` at the root.

The gallery also uses `apple_liquid_glass_accessibility` from this
repository, which feeds the iOS and macOS accessibility settings Flutter does
not report into the widgets.
