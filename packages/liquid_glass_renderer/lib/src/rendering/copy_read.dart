import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:liquid_glass_renderer/src/plan/copy_place.dart';
import 'package:liquid_glass_renderer/src/plan/impeller.dart';
import 'package:liquid_glass_renderer/src/plan/read_layout.dart';
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
/// [targetShare] of them where the glass is drawn inside a coarser copy. A copy
/// whose pixels are larger stands for a texture as many times larger
/// ([size]), or lies in the top-left corner of a layer of the screen's pixels
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
    this.targetShare = 1,
  });

  /// Where the shader's fragment coordinate zero lies on the screen, in
  /// device pixels.
  final Offset origin;

  /// How many device pixels along each side one fragment stands for: 1, or
  /// the share of the copy the glass is drawn in, whose pixels its layer is
  /// drawn at.
  final int targetShare;

  /// uBackdropReduced: 0 where every fragment reads its own texel of the
  /// copy; 1 for an image copy at fewer pixels than the screen, which [size]
  /// stretches; its fragments per texel for a copy in the top-left corner of
  /// a layer.
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

/// The part [shown] (screen logical pixels) of an image copy that a surface
/// paints from its image.
@internal
final class ImagePart {
  /// The part [shown] of [copy].
  ImagePart(ImageCopy copy, this.shown) : _copy = copy;

  final ImageCopy _copy;

  /// The part painted, in the screen's logical pixels.
  final Rect shown;

  /// [shown] in the image's pixels.
  Rect get source => _copy.place.texelsOf(shown);

  /// Takes [canvas] from the screen's logical pixels to the image's, so
  /// that [source] drawn there lands on [shown].
  void toImage(Canvas canvas) {
    final source = this.source;
    canvas
      ..translate(shown.left, shown.top)
      ..scale(1 / _copy.place.pixels)
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
    final image = _copy.image;
    return _copy.place.frostSampling(
      Size(image.width.toDouble(), image.height.toDouble()),
      _copy._frostLeft(frost),
      dissolve: dissolve,
    );
  }
}

/// A read's copy where glass reads it: laid out over a layer of the frame's
/// scene ([CornerRead]) or held in an image ([ImageCopy]).
@internal
sealed class PlacedCopy {
  const PlacedCopy();

  /// Where the copy lies.
  CopyPlace get place;

  double get _held;

  /// What [glassSampling] stands for by the frost drawn into the copy: 0
  /// where it holds none.
  double get heldFrost => place.residual(_held);

  double _frostLeft(double frost) => place.tapFrost(frost, held: _held);

  /// How the final shader reads the copy to frost it for Impeller's blur by
  /// [frost] (see [GlassSampling.frost]), less what the copy holds.
  GlassSampling glassSampling(double frost);
}

/// A read's copy in an image held between frames: [rect] of the screen, in
/// logical pixels. A surface paints the part [readOf] gives.
@internal
final class ImageCopy extends PlacedCopy {
  /// The copy at [place] in [image], with the frost drawn into it.
  ImageCopy(this.image, this.place, this._held);

  /// The image, shared with other copies of its frame.
  final ui.Image image;

  @override
  final ImagePlace place;

  @override
  final double _held;

  /// The screen rect the copy holds, in logical pixels.
  Rect get rect => place.rect;

  /// Where the copy lies in [image].
  @visibleForTesting
  Offset get debugOffset => place.at;

  /// Equal while the copy lies at the same place on the same grid.
  Object get placement => (place.at, place.share);

  /// The copy is painted in the screen's device pixels; one at fewer pixels
  /// than the screen stands for an image as many times larger.
  @override
  GlassSampling glassSampling(double frost) {
    final share = place.share;
    return GlassSampling(
      origin: place.zero,
      reduced: share > 1 ? 1 : 0,
      frost: _frostLeft(frost),
      image: image,
      size: Size(
        image.width * share.toDouble(),
        image.height * share.toDouble(),
      ),
    );
  }

  /// The part [shown] (screen logical pixels, inside [rect]) of the copy.
  ImagePart readOf(Rect shown) => ImagePart(this, shown);
}

/// One layer of the screen's pixels holding a read's copy for the part
/// of it inside a region, laid out as its [place] says.
@internal
final class CornerRead extends PlacedCopy {
  /// The copy [_copy] laid out at [place].
  CornerRead(this._copy, this.place);

  /// The copy laid out over its whole layer in the frame's scene.
  factory CornerRead.inFrame(ReadCopy copy) =>
      CornerRead(copy, CornerPlace.inFrame(copy.read.layout));

  final ReadCopy _copy;

  @override
  final CornerPlace place;

  @override
  double get _held => inPlace.sigma;

  /// The copy lies in the top-left corner of its layer, at the screen's
  /// pixels or coarser.
  @override
  GlassSampling glassSampling(double frost) {
    final perTexel = place.fragmentsPerTexel;
    return GlassSampling(
      origin: place.zero,
      reduced: perTexel > 1 ? perTexel.toDouble() : 0,
      frost: _frostLeft(frost),
      targetShare: place.targetShare,
      holds: place.holds,
    );
  }

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
  }) => place.frostSampling(
    shown,
    _frostLeft(frost),
    size: _layerSize,
    dissolve: dissolve,
  );

  /// What frosts the copy where it lies in the layer, at its own pixels, by
  /// the frost its layout holds there ([ReadLayout.bakedIn]), which glass
  /// then reads as it is; no filter where the glass frosts it fragment by
  /// fragment.
  late final InPlaceFrost inPlace = frostInPlace(place);

  /// What mixes the copy's haze into it where it lies in the layer, or null
  /// where it has none.
  ///
  /// Its filters see the pixels of the target the layer is drawn into, as
  /// many times fewer than the layer's own coordinates count as the target
  /// is coarser than the screen.
  late final CopyHaze? haze = switch ((place.layout.haze, place.haze)) {
    (final haze?, final layout?) => CopyHaze.of(haze, layout),
    _ => null,
  };

  Size get _layerSize => switch (haze) {
    final haze? => place.sizeWith(haze.size * place.targetShare.toDouble()),
    null => place.device.size,
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
    final device = place.device;
    final copySize = place.copySize;
    final engine = builder.pushTransform(
      (deviceToLocal.clone()..translateByDouble(
            -ImpellerLayers.nestedOriginBias,
            -ImpellerLayers.nestedOriginBias,
            0,
            1,
          ))
          .storage,
    );
    if (clip != null) builder.pushClipPath(clip, clipBehavior: Clip.hardEdge);
    PinnedLayers.push(builder, filter, device.topLeft, _layerSize);
    haze?.push(builder, device.topLeft, targetShare: place.targetShare);
    inPlace?.push(builder, device.topLeft, copySize);
    final within = inPlace == null ? device.rect : device.topLeft & copySize;
    _copy.addTo(builder, place, within, held);
    inPlace?.pop(builder);
    haze?.pop(builder);
    builder.pop();
    if (clip != null) builder.pop();
    builder.pop();
    return engine;
  }
}
