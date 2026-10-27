import 'package:liquid_glass_renderer/src/shaders.dart';
import 'package:meta/meta.dart';

/// What a final shader variant reads its geometry and appearance from.
@internal
enum FinalShaderKind {
  /// A matte, one appearance.
  single(''),

  /// A matte and a tint map: appearances that differ only by tint.
  tint('_tint'),

  /// A matte and a material map: any appearances.
  material('_material'),

  /// Shapes evaluated per fragment, one appearance.
  analytic('_analytic');

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
/// in flight; the tint and analytic variants keep their occupancy and spill
/// less. The general variants stay for mixed models and the material map.
@internal
@immutable
final class FinalShaderVariant {
  const FinalShaderVariant._(this.kind, this.models);

  /// Where the variant reads its geometry and appearance from.
  final FinalShaderKind kind;

  /// The color models it shades.
  final FinalShaderModels models;

  /// The shader's file name without its extension.
  String get name => 'liquid_glass_final_render${kind.suffix}${models.suffix}';

  /// The asset key of the compiled shader.
  String get assetKey => ShaderKeys.finalRender(name);

  /// The asset keys of [all], in its order.
  static final List<String> assetKeys = [
    for (final variant in all) variant.assetKey,
  ];

  /// Every variant, in the order a layer holds their shaders.
  static final List<FinalShaderVariant> all = [
    for (final kind in FinalShaderKind.values)
      if (kind == FinalShaderKind.material)
        FinalShaderVariant._(kind, FinalShaderModels.all)
      else
        for (final models in FinalShaderModels.values)
          FinalShaderVariant._(kind, models),
  ];

  /// The index in [all] of the cheapest variant that draws [kind] with
  /// [models].
  static int indexOf(FinalShaderKind kind, FinalShaderModels models) {
    final general = kind == FinalShaderKind.material;
    final index = all.indexWhere(
      (variant) =>
          variant.kind == kind &&
          variant.models == (general ? FinalShaderModels.all : models),
    );
    assert(index >= 0, 'No final shader for $kind $models.');
    return index;
  }
}
