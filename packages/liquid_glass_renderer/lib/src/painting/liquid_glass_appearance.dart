import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/src/painting/liquid_glass_color_model.dart';
import 'package:meta/meta.dart';

/// Lightweight color and materialization controls for one glass shape.
///
/// Optical geometry and surface lighting belong to the containing
/// `LiquidGlassLayer`. These values may differ between shapes that share a
/// layer.
///
/// Colors and color transfers are display-referred. The defaults of the
/// unnamed constructor may be retuned before 1.0; the version-named presets
/// (`ios27*`) track Apple's appearance on that OS version.
@immutable
final class LiquidGlassAppearance {
  /// Creates a per-shape glass appearance.
  ///
  /// The defaults may be retuned before 1.0.
  const LiquidGlassAppearance({
    this.tint = const Color.fromARGB(0, 255, 255, 255),
    this.visibility = 1,
    this.colorModel = const LiquidGlassColorModel.direct(),
  });

  /// Restores an appearance produced by [toJson].
  ///
  /// The JSON schema is experimental and may change between releases.
  @experimental
  factory LiquidGlassAppearance.fromJson(Map<String, Object?> json) {
    double number(String key, double fallback) =>
        (json[key] as num?)?.toDouble() ?? fallback;
    final tint = json['tint'];
    return LiquidGlassAppearance(
      tint: tint is num ? Color(tint.toInt()) : const Color(0x00FFFFFF),
      visibility: number('visibility', 1),
      colorModel: LiquidGlassColorModel.fromJson(json['colorModel']),
    );
  }

  /// The light iOS 27 regular material (`Glass.regular`, which Apple also
  /// uses for toolbars and `.glass` buttons). Its face follows the size of
  /// the shape that wears it ([at]).
  const LiquidGlassAppearance.ios27RegularLight({
    this.tint = const Color(0x00007AFF),
    this.visibility = 1,
  }) : colorModel = const LiquidGlassColorModel.ios27(
         brightness: Brightness.light,
       );

  /// The dark iOS 27 regular material. Its face follows the size of the
  /// shape that wears it ([at]).
  const LiquidGlassAppearance.ios27RegularDark({
    this.tint = const Color(0x00007AFF),
    this.visibility = 1,
  }) : colorModel = const LiquidGlassColorModel.ios27(
         brightness: Brightness.dark,
       );

  /// Creates the iOS 27 regular material for [brightness].
  factory LiquidGlassAppearance.ios27Regular({
    required Brightness brightness,
    Color tint = const Color(0x00007AFF),
    double visibility = 1,
  }) => brightness == Brightness.dark
      ? LiquidGlassAppearance.ios27RegularDark(
          tint: tint,
          visibility: visibility,
        )
      : LiquidGlassAppearance.ios27RegularLight(
          tint: tint,
          visibility: visibility,
        );

  /// The iOS 27 `Glass.clear` appearance, identical in light and dark and
  /// at every size.
  const LiquidGlassAppearance.ios27Clear({
    this.tint = const Color(0x00007AFF),
    this.visibility = 1,
  }) : colorModel = const LiquidGlassColorModel.ios27Clear();

  /// Material tint; alpha controls how strongly it mixes with the backdrop.
  final Color tint;

  /// Shape materialization progress, conventionally from zero to one.
  final double visibility;

  /// The transfer model used to combine [tint] with the backdrop.
  ///
  /// [LiquidGlassColorModel.direct] carries its own saturation, gamma and
  /// vibrancy; the iOS 27 models derive the accompanying tonal response
  /// automatically from their fitted parameters.
  final LiquidGlassColorModel colorModel;

  /// The appearance as a shape of [size] wears it: its [colorModel] at the
  /// shape's shorter side and under its [tint] (see
  /// [LiquidGlassColorModel.at]).
  ///
  /// Returns this appearance itself where neither changes anything.
  LiquidGlassAppearance at(Size size) {
    final worn = colorModel.at(size.shortestSide, tint: tint);
    return identical(worn, colorModel) ? this : copyWith(colorModel: worn);
  }

  /// Returns a copy with the supplied appearance controls replaced.
  LiquidGlassAppearance copyWith({
    Color? tint,
    double? visibility,
    LiquidGlassColorModel? colorModel,
  }) => LiquidGlassAppearance(
    tint: tint ?? this.tint,
    visibility: visibility ?? this.visibility,
    colorModel: colorModel ?? this.colorModel,
  );

  /// Serializes this lightweight appearance for presets and tooling.
  ///
  /// The JSON schema is experimental and may change between releases.
  @experimental
  Map<String, Object> toJson() => {
    'tint': tint.toARGB32(),
    'visibility': visibility,
    'colorModel': colorModel.toJson(),
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other.runtimeType == runtimeType &&
          other is LiquidGlassAppearance &&
          other.tint == tint &&
          other.visibility == visibility &&
          other.colorModel == colorModel;

  @override
  int get hashCode => Object.hash(tint, visibility, colorModel);

  @override
  String toString() => 'LiquidGlassAppearance($tint, $visibility, $colorModel)';
}
