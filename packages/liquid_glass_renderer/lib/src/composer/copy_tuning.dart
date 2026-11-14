import 'package:flutter/foundation.dart';

/// How copies of the backdrop are drawn: the measured trades the renderer
/// ships with.
///
/// Release builds read the shipped values as constants. Other builds read
/// what [debugOverride] last set, which tests use to draw the other side of
/// a trade.
abstract final class GlassCopyTuning {
  static const bool _shippedShaderFrost = true;
  static const int _shippedMaxCopyShare = 2;

  static bool _debugShaderFrost = _shippedShaderFrost;
  static int _debugMaxCopyShare = _shippedMaxCopyShare;

  /// Whether a frost is drawn from an unblurred copy through a shader;
  /// without, the copy is blurred or filtered as the backdrop is. Glass
  /// picks its final shader by it, and fake glass and scroll edge bands
  /// their copies.
  ///
  /// NEAR, for glass: the final shader's 12 taps, turned over a 2 x 2 cell
  /// of pixels except in the tinted variants, are not Impeller's blur, and a
  /// thin hard edge under the frost shows a faint dither. Over the white
  /// bars of the host test they differ from the live filter by at most 22
  /// channel levels over a half-size copy and 36 over a quarter-size one,
  /// where the blurred half-size copy differs by 4, and by 30 for glass
  /// scaled 1.2 over a quarter-size copy. In return a frosted copy takes no
  /// blur passes.
  ///
  /// NEAR, for a frost of a copy: the shader weighs every pixel of the copy
  /// the frost reaches (latticeTaps in copy_frost.dart), so a point under
  /// the frost stays one point. Over the colored rows and white lines of
  /// apple_liquid_glass's scroll edge frost host test, the bands differ from
  /// the copy filtered as the backdrop by at most 11 channel levels at a
  /// device pixel ratio of 2.625 and 6 at 3. Fake glass with 6 px of frost
  /// over the test font's white blocks, the hardest edges a frost meets,
  /// differs by at most 20 at 2.625 (13 for the filtered copy); at 3 the
  /// frost is too wide for the shader and the copy stays filtered. In return
  /// the copy takes no blur passes and, once the frost spans 3.6 device px,
  /// holds a quarter of the pixels or fewer; a change of the color matrix
  /// alone, as a band or a glass fades in, keeps it.
  static bool get shaderFrost =>
      kReleaseMode ? _shippedShaderFrost : _debugShaderFrost;

  /// How many device pixels along each side one pixel of a copy that
  /// Impeller blurs stands for at most; a copy the shader frosts takes its
  /// size from the frost.
  ///
  /// NEAR: a copy drawn at half size differs from the full one by at most 10
  /// channel levels on the Pixel 6a (5 in the scroll scene, 10 under the
  /// crowd of buttons), and by 4 in the host test of white text under 8 px
  /// of frost at dpr 1. In return the Pixel's rails spend 7 % less on a dot
  /// or the Liquid tab and 32 % less under the crowd. A quarter size differs
  /// by 15 on the Liquid tab and saves no more.
  static int get maxCopyShare =>
      kReleaseMode ? _shippedMaxCopyShare : _debugMaxCopyShare;

  /// Sets [shaderFrost] and [maxCopyShare] outside release builds; called
  /// without arguments, it restores the shipped values.
  @visibleForTesting
  static void debugOverride({
    bool shaderFrost = _shippedShaderFrost,
    int maxCopyShare = _shippedMaxCopyShare,
  }) {
    _debugShaderFrost = shaderFrost;
    _debugMaxCopyShare = maxCopyShare;
  }
}
