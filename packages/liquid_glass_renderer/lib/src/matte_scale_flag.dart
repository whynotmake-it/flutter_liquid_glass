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

/// Experimental: how coarse the geometry matte is, in matte pixels per texel.
///
/// The geometry pass shades every pixel of a layer's matte with the
/// shape-distance solvers, which is a large part of the GPU energy of glass
/// whose shapes move or resize. So the matte is not drawn per pixel: the pass
/// draws a smooth field on a lattice of one texel per 2 x 2 or 4 x 4 matte
/// pixels (4 or 16 times fewer fragments): the signed edge distance, the
/// optical normal and the shape's half short side, in an RGBA16F texture. The
/// final shader reads it through the sampler's hardware bilinear filtering and
/// rebuilds, at every pixel, the antialiased silhouette from the interpolated
/// distance, and the refraction profile from the distance, normal and half
/// short side, so edges stay one pixel wide and the optics stay unquantized.
/// Distance fields interpolate exactly across straight edges and to within a
/// small fraction of a pixel around curves wider than the lattice.
///
/// `null` (the default) is automatic, decided per layer from its device pixel
/// ratio: a layer at a ratio of 2 or more uses a scale of 4 and any other a
/// scale of 2. Measured on a Pixel 10, 4 saves 41% GPU time and 18% SoC power
/// on moving blended shapes and 24% / 13% on a resizing sheet, and is neutral
/// on static and loupe scenes. Against a full-resolution matte on the host the
/// mean error was under one 8-bit level; 4 showed visible error only on small
/// shapes at a ratio of 1, which is why those use 2.
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
