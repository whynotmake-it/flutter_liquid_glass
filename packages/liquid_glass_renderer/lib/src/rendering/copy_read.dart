import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/composer.dart';
import 'package:liquid_glass_renderer/painting.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_frost.dart';
import 'package:liquid_glass_renderer/src/rendering/copy_haze.dart';
import 'package:liquid_glass_renderer/src/rendering/pinned_layer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';
import 'package:liquid_glass_renderer/src/rendering/scene_out.dart';
import 'package:meta/meta.dart';

/// How the final glass shader reads a copy: the one place that says where
/// its fragments lie and what its texture holds, written to the shader by
/// the glass alone.
///
/// The shader takes its fragments for the screen's device pixels, or for
/// [scale] of them where the glass is drawn inside a coarser copy. A copy
/// whose pixels are larger stands for a texture as many times larger
/// ([size]), or lies in the top-left share of a layer of the screen's pixels
/// ([reduced]).
@internal
@immutable
final class GlassSampling {
  /// Creates the sampling.
  const GlassSampling({
    required this.origin,
    required this.reduced,
    this.frost = 0,
    this.image,
    this.size,
    this.holds,
    this.scale = 1,
  });

  /// Where the shader's fragment coordinate zero lies on the screen, in
  /// device pixels.
  final Offset origin;

  /// How many device pixels along each side one fragment stands for: 1, or
  /// the share of the copy the glass is drawn in, whose pixels its layer is
  /// drawn at.
  final int scale;

  /// uBackdropReduced: 0 where every fragment reads its own texel of the
  /// copy; 1 for an image copy at fewer pixels than the screen, which [size]
  /// stretches; the share for a copy in the top-left share of a layer.
  final double reduced;

  /// uBackdropFrost: the sigma, in device pixels, the shader's taps frost
  /// the copy by, 0 for none. A reading takes the sigma of the Impeller blur
  /// the frost stands for, in the screen's logical pixels, and leaves out
  /// what the copy's pixels already blur by.
  final double frost;

  /// The image the shader samples, for glass painted over an image copy.
  /// Null where the glass filters a layer, whose texture the engine binds.
  final ui.Image? image;

  /// uSize for glass painted over [image]: the image as many times larger
  /// as the copy is smaller, so a texel spans as many fragments as device
  /// pixels. Null where the engine sets it to the filtered layer's size.
  final Size? size;

  /// The screen rect (logical pixels) past which the read holds nothing,
  /// and the shader mirrors at it. Null where the glass's own bounds say.
  final Rect? holds;
}

/// The sigma, in device pixels, taps still frost a copy that holds [held]
/// by for Impeller's blur by [frost] (both logical pixels), where [residual]
/// gives the taps' sigma for a frost on the copy's grid: none where the copy
/// holds that frost.
@internal
double tapFrost(
  double frost, {
  required double held,
  required double Function(double frost) residual,
}) {
  assert(
    held == 0 || frost == held,
    'A copy that holds a frost is read for that frost.',
  );
  return frost == held ? 0 : residual(frost);
}

/// How `backdrop_frost.frag` reads a copy, in the texture's pixels.
@internal
@immutable
final class FrostSampling {
  /// Creates the sampling.
  const FrostSampling({
    required this.size,
    required this.bounds,
    required this.frost,
    required this.scale,
    required this.shown,
    this.dissolve = FrostDissolve.none,
  });

  /// uSize: the size of the texture the shader reads, in its pixels.
  final Size size;

  /// uBounds: the copy in the texture, in the copy's pixels, half a pixel
  /// in from its edge.
  final Rect bounds;

  /// uFrost: the sigma, in the copy's pixels, the taps frost it by, as
  /// [GlassSampling.frost] says.
  final double frost;

  /// uScale: the copy's pixels per fragment.
  final double scale;

  /// uShown: the fragments the frost covers.
  final Rect shown;

  /// uDissolve: the fragment rows between which the frost dissolves.
  final FrostDissolve dissolve;
}

/// The rows between which a frost dissolves into what lies under it: whole
/// at [whole], gone at [gone], smoothly between them.
@internal
@immutable
final class FrostDissolve {
  /// Creates the rows.
  const FrostDissolve(this.whole, this.gone);

  /// The rows of a frost that is whole everywhere.
  static const none = FrostDissolve(-99999, -100000);

  /// The row where the frost is whole.
  final double whole;

  /// The row where the frost is gone.
  final double gone;

  /// Whether the frost is whole everywhere.
  bool get isNone => whole == none.whole && gone == none.gone;

  /// The rows moved by [offset] and then scaled by [scale].
  FrostDissolve mapped(double offset, double scale) => isNone
      ? this
      : FrostDissolve((whole + offset) * scale, (gone + offset) * scale);

  /// How much of the frost shows at [row].
  double at(double row) {
    final t = ((row - gone) / (whole - gone)).clamp(0.0, 1.0);
    return t * t * t * (t * (t * 6 - 15) + 10);
  }

  @override
  bool operator ==(Object other) =>
      other is FrostDissolve && other.whole == whole && other.gone == gone;

  @override
  int get hashCode => Object.hash(whole, gone);
}

/// The part [shown] (screen logical pixels) of a page that a surface paints
/// from its image.
@internal
final class PagePart {
  /// The part [shown] of [copy].
  PagePart(PageCopy copy, this.shown) : _copy = copy;

  final PageCopy _copy;

  /// The part painted, in the screen's logical pixels.
  final Rect shown;

  /// [shown] in the image's pixels.
  Rect get source {
    final pixels = _copy.geometry.lattice.pixels;
    final offset = _copy.offset;
    final rect = _copy.rect;
    return Rect.fromLTRB(
      (shown.left - rect.left) * pixels + offset.dx,
      (shown.top - rect.top) * pixels + offset.dy,
      (shown.right - rect.left) * pixels + offset.dx,
      (shown.bottom - rect.top) * pixels + offset.dy,
    );
  }

  /// Takes [canvas] from the screen's logical pixels to the image's, so
  /// that [source] drawn there lands on [shown].
  void toImage(Canvas canvas) {
    final source = this.source;
    canvas
      ..translate(shown.left, shown.top)
      ..scale(1 / _copy.geometry.lattice.pixels)
      ..translate(-source.left, -source.top);
  }

  /// How `backdrop_frost.frag` reads [source] drawn under [toImage] to frost
  /// it for Impeller's blur by [frost] (see [GlassSampling.frost]).
  ///
  /// [dissolve] is in the screen's logical rows.
  FrostSampling frostSampling(
    double frost, {
    FrostDissolve dissolve = FrostDissolve.none,
  }) {
    final geometry = _copy.geometry;
    final lattice = geometry.lattice;
    final pixels = lattice.pixels;
    final offset = _copy.offset;
    final image = _copy.image;
    return FrostSampling(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      bounds: Rect.fromLTRB(
        offset.dx + 0.5,
        offset.dy + 0.5,
        offset.dx + _copy.rect.width * pixels - 0.5,
        offset.dy + _copy.rect.height * pixels - 0.5,
      ),
      frost: _copy.frostLeft(frost) / lattice.share,
      scale: 1,
      // The rect drawn bounds the frost.
      shown: Rect.largest,
      dissolve: dissolve.mapped(-_copy.rect.top, pixels).mapped(offset.dy, 1),
    );
  }
}

/// One layer of the screen's pixels holding a read's copy for the part
/// of it inside a region: the layer's top-left share holds the copy at its
/// own pixels, and a filter on the layer sees fragments of the screen's
/// pixels from the layer's corner. The only code that lays a copy out so.
///
/// NEAR: past the copy the layer is empty, and reads mirror at the copy's
/// edge.
@internal
final class CornerRead {
  /// A part of a copy's layer (screen logical pixels), drawn into a target
  /// whose pixels each stand for a number of device pixels.
  /// The last rect is the clip the layer is drawn under, in the screen's
  /// logical pixels, or null for none.
  CornerRead(this._copy, this._cut, this._scale, this._under)
    : _grid = _copy.read.geometry.gridIn(_scale);

  /// The copy laid out over its whole layer in the frame's scene.
  factory CornerRead.inFrame(ReadCopy copy) {
    final geometry = copy.read.geometry;
    assert(
      !geometry.layer.isEmpty,
      'A read that draws holds some of the screen.',
    );
    return CornerRead(copy, geometry.layer, 1, geometry.clip);
  }

  final ReadCopy _copy;
  // The part of the copy's layer read, in the screen's logical pixels.
  final Rect _cut;
  // How many device pixels one pixel of the target the layer is drawn into
  // stands for.
  final int _scale;
  final Rect? _under;
  // The grid the copy is drawn at: its own, or the target's where that is
  // coarser.
  final Lattice _grid;
  // The layer, in the screen's device pixels, on [_grid]: a layer off the
  // target's pixels starts its fragments at the pixel it is rounded out to.
  late final Rect _device = _grid.toDevice(_cut);

  ReadGeometry get _geometry => _copy.read.geometry;
  double get _dpr => _grid.devicePixelRatio;
  // The device pixels along each side one pixel of the layer holds of the
  // copy, past the target's own.
  int get _share => _grid.share ~/ _scale;
  // The copy's pixels per logical pixel, in the layer.
  double get _pixels => _dpr / _share;

  // Where the copy's top left lies in the layer, in the copy's pixels.
  Offset get _at => Offset(
    (_geometry.band.left * _dpr - _device.left) / _share,
    (_geometry.band.top * _dpr - _device.top) / _share,
  );

  // The sigma, in device pixels, the taps frost the copy by for Impeller's
  // blur by [frost].
  double _residual(double frost) => _grid.residual(_geometry.frostFor(frost));

  /// What [glassSampling] stands for by the whole frost [sigma] of a band.
  double frostOf(double sigma) => _residual(sigma);

  /// What [glassSampling] stands for by the frost drawn into the copy: 0
  /// where it holds none.
  double get heldFrost => _residual(inPlace.sigma);

  double _frostLeft(double frost) =>
      tapFrost(frost, held: inPlace.sigma, residual: _residual);

  /// How the final shader reads the layer to frost it for Impeller's blur
  /// by [frost] (see [GlassSampling.frost]), less what the copy holds.
  GlassSampling glassSampling(double frost) => GlassSampling(
    origin: _device.topLeft,
    reduced: _share > 1 ? _share.toDouble() : 0,
    frost: _frostLeft(frost),
    scale: _scale,
    holds: Rect.fromLTRB(
      _device.left / _dpr,
      _device.top / _dpr,
      _device.right / _dpr,
      _device.bottom / _dpr,
    ).intersect(_geometry.band),
  );

  /// How `backdrop_frost.frag` reads the layer to cover [shown] (screen
  /// logical pixels) pixel by pixel, frosted for Impeller's blur by [frost]
  /// (see [GlassSampling.frost]) less what the copy holds, or null where
  /// none of [shown] lies in it.
  ///
  /// [dissolve] is in the screen's logical rows.
  FrostSampling? frostSampling(
    Rect shown,
    double frost, {
    FrostDissolve dissolve = FrostDissolve.none,
  }) {
    final fragments = fragmentsOf(shown);
    if (fragments == null) return null;
    final at = _at;
    final band = _geometry.band;
    final pixels = _pixels;
    return FrostSampling(
      size: _layerSize,
      bounds: Rect.fromLTRB(
        max(at.dx, 0) + 0.5,
        max(at.dy, 0) + 0.5,
        min(at.dx + band.width * pixels, _device.width / _share) - 0.5,
        min(at.dy + band.height * pixels, _device.height / _share) - 0.5,
      ),
      frost: _frostLeft(frost) / _share,
      scale: 1 / _share,
      shown: fragments,
      dissolve: dissolve.mapped(0, _dpr).mapped(-_device.top, 1),
    );
  }

  /// The fragments of the layer that [shown] (screen logical pixels) covers,
  /// or null where none of it lies in the layer.
  Rect? fragmentsOf(Rect shown) {
    final drawn = shown.intersect(_cut);
    if (drawn.isEmpty) return null;
    return drawn.scaled(_dpr).shift(-_device.topLeft);
  }

  // The part of the layer the copy's own pixels fill, in the layer's own
  // pixels.
  Size get _copySize {
    final at = _at;
    final band = _geometry.band;
    final pixels = _pixels;
    return Size(
      min(ceilPixels(max(at.dx, 0) + band.width * pixels), _device.width),
      min(ceilPixels(max(at.dy, 0) + band.height * pixels), _device.height),
    );
  }

  // The rect the copy fills in the layer, in the layer's own pixels.
  Rect get _copyRect {
    final at = _at;
    final size = _copySize;
    final band = _geometry.band;
    final pixels = _pixels;
    return Rect.fromLTRB(
      max(at.dx, 0),
      max(at.dy, 0),
      min(at.dx + band.width * pixels, size.width),
      min(at.dy + band.height * pixels, size.height),
    );
  }

  /// What frosts the copy where it lies in the layer, at its own pixels, by
  /// the frost its geometry holds there ([ReadGeometry.bakedIn]), which glass
  /// then reads as it is; no filter where the glass frosts it fragment by
  /// fragment.
  late final InPlaceFrost inPlace = frostInPlace(
    _geometry.bakedIn(_scale),
    () {
      final size = _copySize;
      return FrostSampling(
        size: size,
        bounds: _copyRect.deflate(0.5),
        frost: _residual(_geometry.bakedIn(_scale)) / _share,
        scale: 1,
        shown: Offset.zero & size,
      );
    },
  );

  /// What mixes the copy's haze into it where it lies in the layer, or null
  /// where it has none.
  ///
  /// Its filters see the pixels of the target the layer is drawn into, as
  /// many times fewer than the layer's own coordinates count as the target
  /// is coarser than the screen.
  late final CopyHaze? haze = () {
    final haze = _geometry.haze;
    if (haze == null) return null;
    final copy = Size(
      ceilPixels(_copySize.width / _scale),
      ceilPixels(_copySize.height / _scale),
    );
    final pixels = _pixels / _scale;
    if (!_keepsCorner(
      CopyHaze.sizeOf(haze, copy, pixels) * _scale.toDouble(),
    )) {
      return null;
    }
    return CopyHaze.of(
      haze,
      copy: copy,
      rect: _copyRect.scaled(1 / _scale),
      pixels: pixels,
    );
  }();

  // Whether the layer still starts at its own corner when a haze's layers of
  // [size] lie in it. A read's geometry leaves a haze its rows in the layer;
  // a layer drawn inside another copy, or one of a few pixels, has none, and
  // grows down by them, past the clip it is drawn under where it must: they
  // are a small part of the layer, which Impeller then still draws whole
  // (ImpellerLayers.keepsWhole). A layer that already lies past the clip at
  // its top or left as far as Impeller lets it would be cut to the clip with
  // them, and start at another pixel than the glass reads it from: it is
  // drawn with no haze. Cut at its bottom or right alone a layer only loses
  // the strip, which the mix sees.
  bool _keepsCorner(Size size) {
    final under = _under;
    if (under == null) return true;
    final bounds = under.scaled(_dpr);
    if (_device.left >= bounds.left && _device.top >= bounds.top) return true;
    return ImpellerLayers.keepsWhole(_device.topLeft & _sizeWith(size), bounds);
  }

  Size _sizeWith(Size haze) => Size(
    max(_device.width, haze.width),
    max(_device.height, haze.height),
  );

  // The layer's size in device pixels: the part of the screen it covers,
  // and under it the rows of a haze's strip where the layer has none for
  // them.
  Size get _layerSize => switch (haze) {
    final haze? => _sizeWith(haze.size * _scale.toDouble()),
    null => _device.size,
  };

  /// Adds the layer to [builder] with [filter] as its image filter, in
  /// coordinates [deviceToLocal] takes the screen's device pixels to. The
  /// copy passes through [inPlace] first, then through its [haze], and it
  /// keeps in [held] what holds between scenes ([ReadCopy.addTo]).
  /// Returns the outermost engine layer.
  ui.TransformEngineLayer addToScene(
    ui.SceneBuilder builder,
    ui.ImageFilter filter,
    Matrix4 deviceToLocal,
    HeldLayers held, {
    ui.Path? clip,
  }) {
    final inPlace = this.inPlace.filter;
    final haze = this.haze;
    final at = _at;
    final engine = builder.pushTransform(
      (deviceToLocal.clone()..translateByDouble(-_below, -_below, 0, 1))
          .storage,
    );
    if (clip != null) builder.pushClipPath(clip, clipBehavior: Clip.hardEdge);
    PinnedLayers.push(builder, filter, _device.topLeft, _layerSize);
    haze?.push(builder, _device.topLeft, scale: _scale);
    inPlace?.push(builder, _device.topLeft, _copySize);
    final lattice = _geometry.copyIn(_scale);
    final origin = Offset(_device.left + at.dx, _device.top + at.dy);
    final within = inPlace == null ? _device : _device.topLeft & _copySize;
    _copy.addTo(builder, lattice, origin, within, held);
    inPlace?.pop(builder);
    haze?.pop(builder);
    builder.pop();
    if (clip != null) builder.pop();
    builder.pop();
    return engine;
  }

  // How far above and left of its pixels a read's layers are added, in
  // device pixels.
  //
  // Impeller places a layer drawn inside another, such as the one a
  // paragraph that fades at its edge is painted through, by the floor of its
  // origin less the origin of the layer around it. Where the copy's edge
  // cuts such a layer the two origins are the same number, less what 32-bit
  // floats lose on the way: the copy's passes through the place of the glass
  // on the screen, a fraction that moves with it. A hair above a whole pixel
  // the floor is one pixel short, and the layer's content, all of the text,
  // stood one pixel of the copy aside, up to four of the screen's, for the
  // frames the glass spent there (a lens sweeping over faded text on a
  // Pixel 6a: 46 to 58 frames in 12 s, none without the fade). Drawn a
  // little below whole pixels the floor always falls the same way. The
  // read's own layers are placed by rounding, so nothing on the screen
  // moves.
  static const double _below = 1 / 32;
}
