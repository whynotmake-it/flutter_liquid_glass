## 0.1.1-dev.10

> Note: This release has breaking changes.

 - **REFACTOR**: move shader to uniform arrays for better shape support.
 - **FIX**: transform children of liquid glass correctly.
 - **FEAT**: add saturation and brightness controls (#47).
 - **FEAT**: better light dispersion.
 - **FEAT**: support up to 64 shapes per layer.
 - **FEAT**: specular highlights now take the background color into account (#43).
 - **DOCS**: updated README with new parameters (#56).
 - **DOCS**: updated example gif (#55).
 - **BREAKING** **FEAT**: cheat lighting that is independent from thickness.

## 0.1.1-dev.9

 - **DOCS**: fix errors in README (#31).

## 0.1.1-dev.8

 - **FEAT**: added experimental `Glassify` widget that turns any child shape into liquid glass.
 - **FIX**: glass now also renders when blend is set to 0.
 - **FIX**: sharper glass edges whithout background shining through.
 - **FEAT**: added refractive index to settings and show values in example.
 - **FEAT**: nicer specular highlights.
 - **DOCS**: update README.md and add better examples (#28)

## 0.1.1-dev.7

 - **FIX**: throw `AssertionError` when used without Impeller.
 - **DOCS**: update pubspec.yaml to reflect minimum SDK and supported platforms.

## 0.1.1-dev.6

 - **FIX**: liquid glass not repainting in route transitions (#16).

## 0.1.1-dev.5

> Note: This release has breaking changes.

 - **FEAT**: decrease precision in shader to mediump, which should increase performance.
 - **BREAKING** **FIX**: shader compilation and removed unused outline strength parameter.

## 0.1.1-dev.4

 - **FIX**: fix shader on flutter stable.
 - **DOCS**: new shape names.

## 0.1.1-dev.3

 - **DOCS**: new shape names.

## 0.1.1-dev.2

> Note: This release has breaking changes.

 - **REFACTOR**: cleaned up shaders.
 - **FIX**: squircle can handle zero radius.
 - **FEAT**: add `clipBehavior` to `LiquidGlass`.
 - **FEAT**: flutter-approved SDF for squircles.
 - **FEAT**: support three shapes per layer.
 - **FEAT**: support all shapes.
 - **FEAT**: better chromatic abberation.
 - **DOCS**: added pub badge to README.
 - **BREAKING** **FEAT**: renamed liquid glass shapes to match their OutlinedBorder counterparts.

## 0.1.1-dev.1

 - **DOCS**: update pubspec and readme.

## 0.1.1-dev.0

 - **FEAT**: initial release.

## 0.1.0

- feat: initial commit 🎉
