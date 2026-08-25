# example

Run the interactive renderer example from the repository root with:

```sh
cd packages/liquid_glass_renderer/example
fvm flutter run -d macos -t lib/basic_app.dart
```

For a deterministic grid background (useful for screenshots):

```sh
fvm flutter run -d macos -t lib/basic_app.dart \
  --dart-define=LIQUID_GLASS_EXAMPLE_TEST_BACKGROUND=true \
  --dart-define=LIQUID_GLASS_EXAMPLE_TEST_BLUR=0
```

Use `fvm flutter devices` to select an iOS or Android Impeller device instead
of `macos`. The running app's sidebar exposes material controls, backgrounds,
and the bundled YAML presets.
