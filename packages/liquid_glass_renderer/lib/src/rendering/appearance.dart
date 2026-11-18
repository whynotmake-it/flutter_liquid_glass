import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:liquid_glass_renderer/src/painting/glass_color_parameters.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_appearance.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:liquid_glass_renderer/src/painting/shader_constants.dart';
import 'package:liquid_glass_renderer/src/rendering/final_shader_variant.dart';
import 'package:liquid_glass_renderer/src/rendering/geometry_tiling.dart';

/// An appearance as glass of one size wears it ([WearAppearance.wear]): its
/// color model resolved for that size and its tint, its visibility the
/// drawn one ([drawnVisibility]).
@internal
@immutable
final class WornAppearance {
  /// The worn appearance of these values.
  const WornAppearance({
    required this.tint,
    required this.visibility,
    required this.colorModel,
  });

  /// The tint ([LiquidGlassAppearance.tint]).
  final Color tint;

  /// The drawn visibility, within zero to one.
  final double visibility;

  /// The color model at the size and under the tint.
  final WornColorModel colorModel;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WornAppearance &&
          other.tint == tint &&
          other.visibility == visibility &&
          other.colorModel == colorModel;

  @override
  int get hashCode => Object.hash(tint, visibility, colorModel);

  /// Untinted glass of the plain direct model at full visibility.
  static const plain = WornAppearance(
    tint: Color(0x00000000),
    visibility: 1,
    colorModel: WornColorModel.direct(),
  );

  @override
  String toString() => 'WornAppearance($tint, $visibility, $colorModel)';
}

/// Wears an appearance at a size: the one way glass asks what its size
/// makes of its look.
@internal
extension WearAppearance on LiquidGlassAppearance {
  /// This appearance as glass of [size] wears it.
  WornAppearance wear(Size size) => WornAppearance(
    tint: tint,
    visibility: drawnVisibility(visibility),
    colorModel: colorModel.wornAt(size.shortestSide, tint: tint),
  );

  /// This appearance where no shape wears it: its color model a panel's,
  /// whatever its tint.
  WornAppearance get wornByNone => WornAppearance(
    tint: tint,
    visibility: drawnVisibility(visibility),
    colorModel: colorModel.wornAt(double.infinity),
  );
}

/// The appearance glass shows: its [own], else its layer's [layerDefault],
/// faded by the [visibility] around it.
@internal
LiquidGlassAppearance shownAppearance(
  LiquidGlassAppearance? own, {
  required LiquidGlassAppearance layerDefault,
  required double visibility,
}) => fadedAppearance(own ?? layerDefault, visibility);

/// [appearance] faded by the [visibility] around it.
@internal
LiquidGlassAppearance fadedAppearance(
  LiquidGlassAppearance appearance,
  double visibility,
) => appearance.copyWith(visibility: appearance.visibility * visibility);

/// How the appearances of a layer's shapes differ: not at all (`uniform` is
/// the one), by tint alone (`tintOnly`, `uniform` the first), or otherwise
/// (`mixed` without `uniform`).
@internal
typedef AppearanceKind = ({
  bool mixed,
  bool tintOnly,
  WornAppearance? uniform,
});

/// How [appearances] differ; [fallback] stands for none.
@internal
AppearanceKind classifyAppearances(
  List<WornAppearance> appearances,
  WornAppearance fallback,
) {
  final first = appearances.isEmpty ? fallback : appearances.first;
  final mixed = appearances.any((appearance) => appearance != first);
  final tintOnly =
      mixed &&
      appearances.every(
        (appearance) =>
            appearance.visibility == first.visibility &&
            appearance.colorModel == first.colorModel,
      );
  return (
    mixed: mixed,
    tintOnly: tintOnly,
    uniform: tintOnly || !mixed ? first : null,
  );
}

/// The adaptive color models of [appearances], then of [fallback], in
/// shader slot order.
@internal
List<GlassColorParameters> colorModelSlots(
  List<WornAppearance> appearances,
  WornAppearance fallback,
) {
  final slots = <GlassColorParameters>[];
  void add(WornAppearance appearance) {
    final parameters = appearance.colorModel.parameters;
    if (parameters != null &&
        !slots.contains(parameters) &&
        slots.length < colorModelSlotCount) {
      slots.add(parameters);
    }
  }

  appearances.forEach(add);
  add(fallback);
  return List.unmodifiable(slots);
}

/// The shader's model code for [model]: 0 direct, else its slot, from 1.
@internal
double colorModelCode(
  WornColorModel model,
  List<GlassColorParameters> slots,
) {
  final parameters = model.parameters;
  if (parameters == null) return 0;
  // The slots hold the appearances' own parameter objects, so a model
  // finds its slot by identity before a field-by-field comparison.
  var index = slots.indexWhere((slot) => identical(slot, parameters));
  if (index < 0) index = slots.indexOf(parameters);
  return (index.clamp(0, colorModelSlotCount - 1) + 1).toDouble();
}

/// The color models [shaded] needs: the direct model alone, one iOS 27
/// model in the first slot, or any.
@internal
FinalShaderModels colorModelFamily(List<WornAppearance> shaded) {
  final first = shaded.first.colorModel.parameters;
  for (final appearance in shaded) {
    if (appearance.colorModel.parameters != first) {
      return FinalShaderModels.all;
    }
  }
  return first == null ? FinalShaderModels.direct : FinalShaderModels.ios27;
}

/// The looks of a buffer's shapes, one appearance a shape, their color
/// models in the slots [colorModels] holds (colorModelSlots); [tintOnly]
/// where only their tints differ.
@internal
ShapeLooks shapeLooks(
  List<WornAppearance> appearances, {
  required List<GlassColorParameters> colorModels,
  required bool tintOnly,
}) {
  return ShapeLooks([
    for (final appearance in appearances)
      ...laneBlock(LookLane.values, {
        LookLane.tint: [
          appearance.tint.r,
          appearance.tint.g,
          appearance.tint.b,
          appearance.tint.a,
        ],
        LookLane.saturation: [appearance.colorModel.saturation],
        LookLane.transmissionGamma: [appearance.colorModel.transmissionGamma],
        LookLane.vibrancy: [appearance.colorModel.vibrancy],
        LookLane.visibilityAndModel: [
          lookVisibilityAndModel(
            appearance.visibility,
            colorModelCode(appearance.colorModel, colorModels),
          ),
        ],
      }),
  ], tintOnly: tintOnly);
}
