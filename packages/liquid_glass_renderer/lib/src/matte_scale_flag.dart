import 'package:meta/meta.dart';

/// The matte scale of a layer drawn at [devicePixelRatio] when
/// [liquidGlassMatteScale] is left automatic: 4 at a ratio of 2 or more, else
/// 2.
@internal
int automaticMatteScale(double devicePixelRatio) =>
    devicePixelRatio >= 2 ? 4 : 2;

/// The matte scale (2 or 4) a layer drawn at [devicePixelRatio] uses:
/// [liquidGlassMatteScale] when set, else [automaticMatteScale].
@internal
int resolveMatteScale({required double devicePixelRatio}) =>
    liquidGlassMatteScale ?? automaticMatteScale(devicePixelRatio);

/// Experimental: how many matte pixels one low-res matte texel covers in each
/// direction.
///
/// Working out the distance to each shape for every pixel of a layer's matte
/// is a large part of the GPU energy that glass uses while its shapes move or
/// resize. So the geometry pass draws a low-res matte instead: one texel for
/// every 2 x 2 or 4 x 4 block of pixels, which is 4 or 16 times less work.
/// Each texel holds the distance to the edge, the direction the surface faces
/// and half of the shape's shorter side, in an RGBA16F texture.
///
/// The final shader reads it with linear filtering, which blends the four
/// nearest texels, and works out the antialiased edge and the refraction for
/// each pixel from the blended values. So edges stay one pixel wide and the
/// refraction is as smooth as before. Blending distances is exact along
/// straight edges, and off by a small fraction of a pixel on curves larger
/// than a texel.
///
/// `null` (the default) picks a scale for each layer from its device pixel
/// ratio: 4 at a ratio of 2 or more, otherwise 2. On a Pixel 10, 4 uses 41%
/// less GPU time and 18% less SoC power than 2 on moving blended shapes, and
/// 24% / 13% less on a resizing sheet. It makes no difference on static and
/// loupe scenes. Compared with a full-resolution matte on the Mac, the average
/// error was under one 8-bit color level. A scale of 4 only looked wrong on
/// small shapes at a ratio of 1, which is why those use 2.
///
/// A value of 2 or 4 forces one scale for every layer, whatever its ratio. It
/// can be set at build time with `--dart-define=LIQUID_GLASS_MATTE_SCALE=2` (or
/// 4; any other value means automatic) and is read whenever a layer builds.
@experimental
int? liquidGlassMatteScale = _matteScaleFromEnvironment();

int? _matteScaleFromEnvironment() {
  const requested = int.fromEnvironment('LIQUID_GLASS_MATTE_SCALE');
  return requested == 2 || requested == 4 ? requested : null;
}
