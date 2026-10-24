import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/internal/running_under_flutter_test.dart';

/// Whether the engine renders with Impeller (shader image filters are only
/// supported there). Never on the web.
@internal
bool get impellerRenders => !kIsWeb && ui.ImageFilter.isShaderFilterSupported;

/// Whether the Impeller-only optimization ([liquidGlassNativeSeed]) is on
/// unless set otherwise: wherever Impeller renders, but not under
/// `flutter test`.
///
/// Its output is not bit for bit what the plain path draws, so a golden test
/// of an app that renders with `--enable-impeller` would shift with the
/// default. Under `flutter test` (which sets `FLUTTER_TEST`) it is off unless
/// a test turns it on or a `--dart-define` forces it.
@internal
bool get impellerDefaults => impellerRenders && !runningUnderFlutterTest;

/// How a glass pass is seeded natively; see [liquidGlassNativeSeed].
enum LiquidGlassNativeSeed {
  /// No pass: the glass filter reads the backdrop itself, as it always did.
  none,

  /// The pass is seeded by an identity backdrop filter, and the glass filter
  /// (blur and shader, or blur and color transfer) then runs over the small
  /// pass instead of over the whole backdrop texture.
  identity,

  /// The pass is seeded by a plain blur of the backdrop, which Impeller crops
  /// to the pass, and the glass filter in it is only the shader (or the color
  /// transfer).
  blur,
}

LiquidGlassNativeSeed _nativeSeedFromEnvironment() =>
    switch (const String.fromEnvironment('LIQUID_GLASS_NATIVE_SEED')) {
      'none' => LiquidGlassNativeSeed.none,
      'identity' => LiquidGlassNativeSeed.identity,
      'blur' => LiquidGlassNativeSeed.blur,
      _ =>
        impellerDefaults
            ? LiquidGlassNativeSeed.blur
            : LiquidGlassNativeSeed.none,
    };

/// Experimental: run the glass filter over a small, natively seeded pass
/// instead of over the whole backdrop.
///
/// Impeller runs `ImageFilter.compose(blur, shader)` over the whole backdrop
/// texture, because a runtime-effect or color-matrix filter does not forward
/// the coverage it is clipped to, and only a plain blur as the outermost
/// backdrop filter is cropped to its clip. With
/// [LiquidGlassNativeSeed.identity] the glass is painted inside a pass of
/// exactly the rect planned for it (the glass plus what its blur reads),
/// seeded by an identity backdrop filter, so the glass filter's blur only
/// covers that pass. With [LiquidGlassNativeSeed.blur] the seed is the blur
/// itself (a plain, cropped blur) and the glass filter is blur free.
///
/// Impeller only crops that blur when the pass, grown by the blur's padding,
/// lies inside the screen. A pass that reaches a screen edge (a bar, say) is
/// seeded by an identity filter in `blur` mode too, as its blur would not be
/// cropped.
///
/// A glass without a blur is left alone in both modes: with nothing to crop, a
/// pass would only add a copy. A glass whose whole filter is a blur (fake
/// glass without a color transfer) is also left alone, as it is already
/// cropped natively.
///
/// Every un-keyed backdrop filter costs a full-screen read-back, so seeds that
/// can read the same snapshot share one `BackdropKey`: Impeller reads the root
/// once and hands each seed the cached texture. Seeds that would see a stale
/// backdrop (they overlap what an earlier seed or other content painted in
/// between, or the content cannot be bounded) get a key of their own. A glass
/// with its own `backdropKey`, or one that uses a `BackdropGroup`, keeps that
/// key for its seed. Seeds that share a key are made unequal on purpose (by a
/// sigma offset above the engine's equality tolerance, or by a tiny scale in a
/// color matrix): when every filter of a key is equal Impeller runs that filter
/// once over the whole texture with no coverage hint, which would bring back a
/// full-screen blur.
///
/// Shader coordinates map to the pass origin whenever the pass is in effect.
/// Defaults to [LiquidGlassNativeSeed.blur] wherever Impeller renders
/// ([LiquidGlassNativeSeed.none] elsewhere, and under `flutter test`, see
/// [impellerDefaults]): on a Pixel 10 it cut GPU time 34-37% and SoC power
/// 19-23% while scrolling under glass. Read whenever glass paints. It can be
/// forced at build time with `--dart-define=LIQUID_GLASS_NATIVE_SEED=none`,
/// `=identity` or `=blur`.
LiquidGlassNativeSeed liquidGlassNativeSeed = _nativeSeedFromEnvironment();
