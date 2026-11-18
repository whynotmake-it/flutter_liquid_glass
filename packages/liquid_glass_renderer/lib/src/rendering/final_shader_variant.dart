import 'dart:ui' as ui;

import 'package:liquid_glass_renderer/src/rendering/atlas_shaders.dart';
import 'package:liquid_glass_renderer/src/rendering/shaders.dart';
import 'package:meta/meta.dart';

/// What a final shader variant reads its geometry and appearance from.
@internal
enum FinalShaderKind {
  /// The geometry atlas, one appearance.
  single('', AtlasLooks.none),

  /// The atlas and the tint beside it: appearances that differ only by tint.
  tint('_tint', AtlasLooks.tint),

  /// The atlas and every look beside it: any appearances.
  material('_material', AtlasLooks.all);

  const FinalShaderKind(this.suffix, this.looks);

  /// The file name part of the kind.
  final String suffix;

  /// What it reads beside the atlas.
  final AtlasLooks looks;
}

/// The color models a final shader variant shades.
@internal
enum FinalShaderModels {
  /// Every model, blended by weight.
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
/// the one-appearance iOS 27 variant over an atlas, which fits a Mali-G52's
/// 32 work registers only without that: its frosted twin draws frosted glass
/// ([frost]). The other variants take the same register class with the frost
/// loop as without it (test/shader_registers.txt), so they always carry it.
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

  /// Whether the variant can frost an unblurred copy itself
  /// (uBackdropFrost): every variant but the one whose frost is a twin.
  bool get frosts => frost || !_frostTwins.contains((kind, models, shape));

  /// Whether the variant parts colors (uBackdropAberration). Its six reads
  /// take the 32-register variants to 46 registers and more on the
  /// Mali-G78, so only the variants that shade every color model do.
  bool get aberrates => models == FinalShaderModels.all;

  /// Whether the variant draws the touch glow. The variant of per-shape
  /// appearances does not: the glow would spill its registers on Mali GPUs.
  bool get glows => kind != FinalShaderKind.material;

  /// Whether the face in the middle of the glass has a fixed shape, which
  /// the variant takes in a few 16-bit operations: one iOS 27 model and one
  /// appearance.
  bool get plainInterior =>
      models == FinalShaderModels.ios27 && kind == FinalShaderKind.single;

  /// What the variant's file defines for liquid_glass_final_render_core.glsl.
  Map<String, String> get defines {
    String flag(bool value) => value ? '1' : '0';
    return {
      'KIND': 'KIND_${kind.name.toUpperCase()}',
      'COLOR_MODELS': 'COLOR_MODELS_${models.name.toUpperCase()}',
      'COMPUTED_SHAPE': flag(shape),
      'FROST': flag(frosts),
      'FROST_BAND': flag(band),
      'ABERRATION': flag(aberrates),
      'GLOW': flag(glows),
      'PLAIN_INTERIOR': flag(plainInterior),
    };
  }

  /// The variant's file: its [defines] over the core.
  String get source => [
    '// Copyright 2025, Tim Lehmann for whynotmake.it',
    '//',
    '// Generated from FinalShaderVariant by',
    '// test/src/final_shader_variant_test.dart: do not edit.',
    '',
    '#version 460 core',
    '',
    for (final MapEntry(:key, :value) in defines.entries) '#define $key $value',
    '#include "liquid_glass_final_render_core.glsl"',
    '',
  ].join('\n');

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

  // The variants whose frost is a twin, by kind, models and shape: on a
  // Mali-G52 it holds 32 work registers without the frost loop and 49 with
  // it.
  static const _frostTwins = {
    (FinalShaderKind.single, FinalShaderModels.ios27, false),
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
        if (_frostTwins.contains((kind, models, shape)))
          FinalShaderVariant._(kind, models, frost: true, shape: shape),
        if (kind == FinalShaderKind.single && models == FinalShaderModels.ios27)
          FinalShaderVariant._(
            kind,
            models,
            frost: _frostTwins.contains((kind, models, shape)),
            band: true,
            shape: shape,
          ),
      ],
  ];

  /// The index in [all] of the cheapest variant that draws [kind] with
  /// [models], frosts an unblurred copy when [frost] and parts colors when
  /// [aberrates]; with [shape] the one that works one shape out itself,
  /// which is of [FinalShaderKind.single].
  static int indexOf(
    FinalShaderKind kind,
    FinalShaderModels models, {
    bool frost = false,
    bool shape = false,
    bool aberrates = false,
  }) {
    assert(
      !shape || kind == FinalShaderKind.single,
      'One shape has one appearance.',
    );
    final index =
        _indices[_code(
          kind,
          models,
          frost: frost,
          band: false,
          shape: shape,
          aberrates: aberrates,
        )];
    assert(index >= 0, 'No final shader for $kind $models.');
    return index;
  }

  /// The index in [all] of the variant that draws [kind] with [models]
  /// beside the scroll edge's band leading its read, as [indexOf] picks, or
  /// null where none does.
  static int? bandIndexOf(
    FinalShaderKind kind,
    FinalShaderModels models, {
    required bool frost,
    bool shape = false,
    bool aberrates = false,
  }) {
    if (!frost) return null;
    final index =
        _indices[_code(
          kind,
          models,
          frost: true,
          band: true,
          shape: shape,
          aberrates: aberrates,
        )];
    return index < 0 ? null : index;
  }

  // Every answer of [indexOf], worked out once: glass asks for its variant
  // several times a frame.
  static final List<int> _indices = [
    for (final kind in FinalShaderKind.values)
      for (final models in FinalShaderModels.values)
        for (final aberrates in const [false, true])
          for (final frost in const [false, true])
            for (final band in const [false, true])
              for (final shape in const [false, true])
                _find(
                  kind,
                  models,
                  frost: frost,
                  band: band,
                  shape: shape,
                  aberrates: aberrates,
                ),
  ];

  static int _code(
    FinalShaderKind kind,
    FinalShaderModels models, {
    required bool frost,
    required bool band,
    required bool shape,
    required bool aberrates,
  }) =>
      (kind.index * FinalShaderModels.values.length + models.index) * 16 +
      (aberrates ? 8 : 0) +
      (frost ? 4 : 0) +
      (band ? 2 : 0) +
      (shape ? 1 : 0);

  static int _find(
    FinalShaderKind kind,
    FinalShaderModels models, {
    required bool frost,
    required bool band,
    required bool shape,
    required bool aberrates,
  }) {
    bool draws(FinalShaderVariant variant, FinalShaderModels shaded) =>
        variant.kind == kind &&
        variant.models == shaded &&
        variant.frost ==
            (frost && _frostTwins.contains((kind, shaded, shape))) &&
        variant.band == band &&
        variant.shape == shape &&
        (variant.aberrates || !aberrates);
    final index = all.indexWhere((variant) => draws(variant, models));
    if (index >= 0) return index;
    return all.indexWhere(
      (variant) => draws(variant, FinalShaderModels.all),
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
