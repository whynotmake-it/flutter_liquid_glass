import 'dart:ui' as ui;

import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:meta/meta.dart';

/// What a final shader variant reads its geometry and appearance from.
@internal
enum FinalShaderKind {
  /// The geometry atlas, one appearance.
  single(''),

  /// The atlas and the tint beside it: appearances that differ only by tint.
  tint('_tint'),

  /// The atlas and every look beside it: any appearances.
  material('_material');

  const FinalShaderKind(this.suffix);

  /// The file name part of the kind.
  final String suffix;
}

/// The color models a final shader variant shades.
@internal
enum FinalShaderModels {
  /// Every model, blended by share.
  all(''),

  /// One iOS 27 model, in the first color model slot.
  ios27('_ios27'),

  /// The direct model alone.
  direct('_direct');

  const FinalShaderModels(this.suffix);

  /// The file name part of the models.
  final String suffix;
}

/// One compiled specialization of the final glass shader.
///
/// A variant that shades one color model family drops the other family's
/// arithmetic and the slot loop's uniform reads. On a Mali-G78 that halves
/// the registers of the one-appearance shader, which doubles its fragments
/// in flight; the tint variants keep their occupancy and spill less. The
/// general variants serve mixed models and [FinalShaderKind.material].
///
/// Every variant can frost an unblurred copy of the backdrop itself, except
/// the ones that fit in 32 registers only without that: a frosted twin of
/// each draws frosted glass ([frost]).
@immutable
final class FinalShaderVariant {
  const FinalShaderVariant._(
    this.kind,
    this.models, {
    this.frost = false,
    this.band = false,
    this.shape = false,
  });

  /// Where the variant reads its geometry and appearance from.
  final FinalShaderKind kind;

  /// The color models it shades.
  final FinalShaderModels models;

  /// Whether this is the frosted twin of a variant that cannot frost.
  final bool frost;

  /// Whether the variant also draws a scroll edge beside the glass.
  final bool band;

  /// Whether the variant works the geometry of glass that is one shape out
  /// at each fragment, where the others read an atlas (ComputedGeometry).
  final bool shape;

  /// The shader's file name without its extension.
  String get name =>
      'liquid_glass_final_render${shape ? '_shape' : ''}${kind.suffix}'
      '${models.suffix}${frost ? '_frost' : ''}${band ? '_band' : ''}';

  /// The asset key of the compiled shader.
  String get assetKey => ShaderKeys.finalRender(name);

  /// The asset keys of [all], in its order.
  static final List<String> assetKeys = [
    for (final variant in all) variant.assetKey,
  ];

  // The variants whose frost is a twin: on a Mali-G78 they hold 32 work
  // registers without the frost loop and 46 to 52 with it.
  static const _frostTwins = {
    (FinalShaderKind.single, FinalShaderModels.ios27),
    (FinalShaderKind.tint, FinalShaderModels.ios27),
    (FinalShaderKind.tint, FinalShaderModels.direct),
  };

  /// Every variant, in the order a layer holds their shaders: the ones
  /// that read an atlas, then their twins for one shape, which has one
  /// appearance.
  static final List<FinalShaderVariant> all = [
    for (final kind in FinalShaderKind.values) ..._of(kind, shape: false),
    ..._of(FinalShaderKind.single, shape: true),
  ];

  static List<FinalShaderVariant> _of(
    FinalShaderKind kind, {
    required bool shape,
  }) => [
    if (kind == FinalShaderKind.material)
      FinalShaderVariant._(kind, FinalShaderModels.all)
    else
      for (final models in FinalShaderModels.values) ...[
        FinalShaderVariant._(kind, models, shape: shape),
        if (_frostTwins.contains((kind, models)))
          FinalShaderVariant._(kind, models, frost: true, shape: shape),
        if (kind == FinalShaderKind.single && models == FinalShaderModels.ios27)
          FinalShaderVariant._(
            kind,
            models,
            frost: true,
            band: true,
            shape: shape,
          ),
      ],
  ];

  /// The index in [all] of the cheapest variant that draws [kind] with
  /// [models], and frosts an unblurred copy when [frost]; with [shape] the
  /// one that works one shape out itself, which is of
  /// [FinalShaderKind.single].
  static int indexOf(
    FinalShaderKind kind,
    FinalShaderModels models, {
    bool frost = false,
    bool band = false,
    bool shape = false,
  }) {
    assert(
      !shape || kind == FinalShaderKind.single,
      'One shape has one appearance.',
    );
    final index =
        _indices[_code(kind, models, frost: frost, band: band, shape: shape)];
    assert(index >= 0, 'No final shader for $kind $models.');
    return index;
  }

  // Every answer of [indexOf], worked out once: glass asks for its variant
  // several times a frame.
  static final List<int> _indices = [
    for (final kind in FinalShaderKind.values)
      for (final models in FinalShaderModels.values)
        for (final frost in const [false, true])
          for (final band in const [false, true])
            for (final shape in const [false, true])
              _find(kind, models, frost: frost, band: band, shape: shape),
  ];

  static int _code(
    FinalShaderKind kind,
    FinalShaderModels models, {
    required bool frost,
    required bool band,
    required bool shape,
  }) =>
      (kind.index * FinalShaderModels.values.length + models.index) * 8 +
      (frost ? 4 : 0) +
      (band ? 2 : 0) +
      (shape ? 1 : 0);

  static int _find(
    FinalShaderKind kind,
    FinalShaderModels models, {
    required bool frost,
    required bool band,
    required bool shape,
  }) {
    final general = kind == FinalShaderKind.material;
    final shaded = general ? FinalShaderModels.all : models;
    return all.indexWhere(
      (variant) =>
          variant.kind == kind &&
          variant.models == shaded &&
          variant.frost == (frost && _frostTwins.contains((kind, shaded))) &&
          variant.band == band &&
          variant.shape == shape,
    );
  }
}

/// The filter a final shader's sampler of the atlas's table is bound with.
///
/// The table is read texel by texel, so unfiltered. Impeller's OpenGL ES
/// backend gives a texture one filter for every sampler it is bound to, and
/// the table's won over the strips', which the same texture holds and which
/// are read filtered: glass over a copy read its geometry texel by texel
/// and drew its rim in blocks. There the table is bound filtered too; it is
/// read at texel centers, where a filtered read returns the texel. On Metal
/// that is not exact enough (two goldens of blended shapes moved by 34 and
/// 301 pixels), so the other backends keep the table unfiltered.
///
/// The geometry renderer sets it when it learns the backend, before any
/// atlas is shaded.
ui.FilterQuality atlasTableFilter = ui.FilterQuality.none;
