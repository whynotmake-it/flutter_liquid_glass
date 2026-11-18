import 'dart:ui' show ColorSpace;

import 'package:apple_liquid_glass/src/foundation/traits.dart';
import 'package:flutter/widgets.dart';

/// A color with a value for every appearance: light or dark, standard or
/// increased contrast, base or elevated.
///
/// UIKit: `UIColor(dynamicProvider:)`. Flutter: `CupertinoDynamicColor`.
///
/// It is a [Color] so it goes wherever one goes, but it has no channels
/// until it is resolved against the traits of a place in the tree
/// ([resolveFrom], [resolve]). Reading a channel of an unresolved color, or
/// deriving one from it (`withValues`, `withAlpha`), asserts in debug
/// builds and uses the light value in release builds. Glass widgets resolve
/// the colors they are given themselves.
@immutable
final class GlassDynamicColor implements Color {
  /// Creates a color with all eight values.
  const GlassDynamicColor({
    required this.color,
    required this.darkColor,
    required this.highContrastColor,
    required this.darkHighContrastColor,
    required this.elevatedColor,
    required this.darkElevatedColor,
    required this.highContrastElevatedColor,
    required this.darkHighContrastElevatedColor,
  }) : _resolved = null;

  /// Creates a color that differs only between light and dark.
  const GlassDynamicColor.withBrightness({
    required Color color,
    required Color darkColor,
  }) : this(
         color: color,
         darkColor: darkColor,
         highContrastColor: color,
         darkHighContrastColor: darkColor,
         elevatedColor: color,
         darkElevatedColor: darkColor,
         highContrastElevatedColor: color,
         darkHighContrastElevatedColor: darkColor,
       );

  /// Creates a color that differs between light and dark and between
  /// standard and increased contrast.
  const GlassDynamicColor.withBrightnessAndContrast({
    required Color color,
    required Color darkColor,
    required Color highContrastColor,
    required Color darkHighContrastColor,
  }) : this(
         color: color,
         darkColor: darkColor,
         highContrastColor: highContrastColor,
         darkHighContrastColor: darkHighContrastColor,
         elevatedColor: color,
         darkElevatedColor: darkColor,
         highContrastElevatedColor: highContrastColor,
         darkHighContrastElevatedColor: darkHighContrastColor,
       );

  GlassDynamicColor._resolvedTo(GlassDynamicColor from, Color resolved)
    : color = from.color,
      darkColor = from.darkColor,
      highContrastColor = from.highContrastColor,
      darkHighContrastColor = from.darkHighContrastColor,
      elevatedColor = from.elevatedColor,
      darkElevatedColor = from.darkElevatedColor,
      highContrastElevatedColor = from.highContrastElevatedColor,
      darkHighContrastElevatedColor = from.darkHighContrastElevatedColor,
      _resolved = resolved;

  /// The light value.
  final Color color;

  /// The dark value.
  final Color darkColor;

  /// The light value under increased contrast.
  final Color highContrastColor;

  /// The dark value under increased contrast.
  final Color darkHighContrastColor;

  /// The light value of elevated content.
  final Color elevatedColor;

  /// The dark value of elevated content.
  final Color darkElevatedColor;

  /// The light value of elevated content under increased contrast.
  final Color highContrastElevatedColor;

  /// The dark value of elevated content under increased contrast.
  final Color darkHighContrastElevatedColor;

  final Color? _resolved;

  /// [color] resolved at [context] when it is a [GlassDynamicColor];
  /// [color] itself otherwise.
  static Color resolve(Color color, BuildContext context) =>
      color is GlassDynamicColor ? color.resolveFrom(context) : color;

  /// [color] resolved for [traits] when it is a [GlassDynamicColor];
  /// [color] itself otherwise.
  static Color resolveWith(Color color, GlassTraits traits) =>
      color is GlassDynamicColor ? color.resolvedWith(traits) : color;

  /// [resolve] for a color that may be null.
  static Color? maybeResolve(Color? color, BuildContext context) =>
      color == null ? null : resolve(color, context);

  /// The color between [a] and [b] at [t]. Dynamic colors interpolate
  /// value by value and keep both appearances, so the result still
  /// resolves for every appearance. A null end stands for whatever lies
  /// under it (a theme's default), so the result jumps to the other end at
  /// the middle.
  static Color? lerp(Color? a, Color? b, double t) {
    if (a == null || b == null) return t < 0.5 ? a : b;
    if (a is! GlassDynamicColor && b is! GlassDynamicColor) {
      return Color.lerp(a, b, t);
    }
    final from = _asDynamic(a);
    final to = _asDynamic(b);
    Color mix(Color Function(GlassDynamicColor c) pick) =>
        Color.lerp(pick(from), pick(to), t)!;
    return GlassDynamicColor(
      color: mix((c) => c.color),
      darkColor: mix((c) => c.darkColor),
      highContrastColor: mix((c) => c.highContrastColor),
      darkHighContrastColor: mix((c) => c.darkHighContrastColor),
      elevatedColor: mix((c) => c.elevatedColor),
      darkElevatedColor: mix((c) => c.darkElevatedColor),
      highContrastElevatedColor: mix((c) => c.highContrastElevatedColor),
      darkHighContrastElevatedColor: mix(
        (c) => c.darkHighContrastElevatedColor,
      ),
    );
  }

  /// This color resolved against the traits at [context].
  GlassDynamicColor resolveFrom(BuildContext context) =>
      resolvedWith(GlassTraits.of(context));

  /// This color resolved against [traits].
  GlassDynamicColor resolvedWith(GlassTraits traits) {
    final dark = traits.brightness == Brightness.dark;
    final elevated = traits.interfaceLevel == GlassInterfaceLevel.elevated;
    final value = switch ((dark, traits.highContrast, elevated)) {
      (false, false, false) => color,
      (true, false, false) => darkColor,
      (false, true, false) => highContrastColor,
      (true, true, false) => darkHighContrastColor,
      (false, false, true) => elevatedColor,
      (true, false, true) => darkElevatedColor,
      (false, true, true) => highContrastElevatedColor,
      (true, true, true) => darkHighContrastElevatedColor,
    };
    return GlassDynamicColor._resolvedTo(this, value);
  }

  Color get _effective {
    assert(
      _resolved != null,
      'A GlassDynamicColor was read before it was resolved; resolve it with '
      'GlassDynamicColor.resolve(color, context) first.',
    );
    return _resolved ?? color;
  }

  @override
  double get a => _effective.a;

  @override
  double get r => _effective.r;

  @override
  double get g => _effective.g;

  @override
  double get b => _effective.b;

  @override
  ColorSpace get colorSpace => _effective.colorSpace;

  @override
  int toARGB32() => _effective.toARGB32();

  @override
  int get value => toARGB32();

  @override
  int get alpha => (toARGB32() >> 24) & 0xFF;

  @override
  int get red => (toARGB32() >> 16) & 0xFF;

  @override
  int get green => (toARGB32() >> 8) & 0xFF;

  @override
  int get blue => toARGB32() & 0xFF;

  @override
  double get opacity => alpha / 0xFF;

  @override
  double computeLuminance() => _effective.computeLuminance();

  @override
  Color withValues({
    double? alpha,
    double? red,
    double? green,
    double? blue,
    ColorSpace? colorSpace,
  }) => _effective.withValues(
    alpha: alpha,
    red: red,
    green: green,
    blue: blue,
    colorSpace: colorSpace,
  );

  @override
  Color withAlpha(int a) => _effective.withAlpha(a);

  @override
  Color withRed(int r) => _effective.withRed(r);

  @override
  Color withGreen(int g) => _effective.withGreen(g);

  @override
  Color withBlue(int b) => _effective.withBlue(b);

  @override
  Color withOpacity(double opacity) => withAlpha((255 * opacity).round());

  @override
  bool operator ==(Object other) =>
      other is GlassDynamicColor &&
      other._resolved == _resolved &&
      other.color == color &&
      other.darkColor == darkColor &&
      other.highContrastColor == highContrastColor &&
      other.darkHighContrastColor == darkHighContrastColor &&
      other.elevatedColor == elevatedColor &&
      other.darkElevatedColor == darkElevatedColor &&
      other.highContrastElevatedColor == highContrastElevatedColor &&
      other.darkHighContrastElevatedColor == darkHighContrastElevatedColor;

  @override
  int get hashCode => Object.hash(
    _resolved,
    color,
    darkColor,
    highContrastColor,
    darkHighContrastColor,
    elevatedColor,
    darkElevatedColor,
    highContrastElevatedColor,
    darkHighContrastElevatedColor,
  );

  @override
  String toString() =>
      'GlassDynamicColor(${_resolved ?? 'unresolved'}, '
      'light: $color, dark: $darkColor)';
}

GlassDynamicColor _asDynamic(Color color) => switch (color) {
  final GlassDynamicColor known => known,
  _ => GlassDynamicColor.withBrightness(color: color, darkColor: color),
};

/// The iOS system colors.
///
/// UIKit: `UIColor`'s system colors. Flutter: `CupertinoColors`.
///
/// Light and dark of systemBlue, systemRed and tertiarySystemFill are
/// measured on iOS 27 (states, lists and menu passports); their Increase
/// Contrast values and every value of systemGreen and systemFill are read
/// from iOS 27's UIKit color tables (states passport). tertiaryLabel and
/// systemGray4 are the catalogue values, matched by the iOS 27
/// measurements. Every other value, including the Increase Contrast values
/// of the labels and grays and every elevated value, is UIKit's catalogue
/// as Flutter's `CupertinoColors` carries it, not measured on iOS 27.
abstract final class GlassColors {
  /// The primary text.
  static const label = GlassDynamicColor.withBrightness(
    color: Color(0xFF000000),
    darkColor: Color(0xFFFFFFFF),
  );

  /// Secondary text.
  static const secondaryLabel = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x993C3C43),
    darkColor: Color(0x99EBEBF5),
    highContrastColor: Color(0xAD3C3C43),
    darkHighContrastColor: Color(0xADEBEBF5),
  );

  /// Tertiary text, and the label of a disabled button.
  static const tertiaryLabel = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x4C3C3C43),
    darkColor: Color(0x4CEBEBF5),
    highContrastColor: Color(0x603C3C43),
    darkHighContrastColor: Color(0x60EBEBF5),
  );

  /// The fill of thin and small shapes.
  static const systemFill = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x33787880),
    darkColor: Color(0x5C787880),
    highContrastColor: Color(0x47787880),
    darkHighContrastColor: Color(0x70787880),
  );

  /// The fill of large shapes, such as an alert's action buttons and the
  /// compact date picker's capsules.
  static const tertiarySystemFill = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x1F767680),
    darkColor: Color(0x3D767680),
    highContrastColor: Color(0x33767680),
    darkHighContrastColor: Color(0x52767680),
  );

  /// The background of a plain page.
  static const systemBackground = GlassDynamicColor(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF000000),
    highContrastColor: Color(0xFFFFFFFF),
    darkHighContrastColor: Color(0xFF000000),
    elevatedColor: Color(0xFFFFFFFF),
    darkElevatedColor: Color(0xFF1C1C1E),
    highContrastElevatedColor: Color(0xFFFFFFFF),
    darkHighContrastElevatedColor: Color(0xFF242426),
  );

  /// The background of a grouped list.
  static const systemGroupedBackground = GlassDynamicColor(
    color: Color(0xFFF2F2F7),
    darkColor: Color(0xFF000000),
    highContrastColor: Color(0xFFEBEBF0),
    darkHighContrastColor: Color(0xFF000000),
    elevatedColor: Color(0xFFF2F2F7),
    darkElevatedColor: Color(0xFF1C1C1E),
    highContrastElevatedColor: Color(0xFFEBEBF0),
    darkHighContrastElevatedColor: Color(0xFF242426),
  );

  /// The background of a grouped list's cells.
  static const secondarySystemGroupedBackground = GlassDynamicColor(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0xFF1C1C1E),
    highContrastColor: Color(0xFFFFFFFF),
    darkHighContrastColor: Color(0xFF242426),
    elevatedColor: Color(0xFFFFFFFF),
    darkElevatedColor: Color(0xFF2C2C2E),
    highContrastElevatedColor: Color(0xFFFFFFFF),
    darkHighContrastElevatedColor: Color(0xFF363638),
  );

  /// A thin line that hides what is behind it.
  static const opaqueSeparator = GlassDynamicColor.withBrightness(
    color: Color(0xFFC6C6C8),
    darkColor: Color(0xFF38383A),
  );

  /// The default accent, iOS 27's blue.
  static const systemBlue = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0xFF0088FF),
    darkColor: Color(0xFF0091FF),
    highContrastColor: Color(0xFF1E6EF4),
    darkHighContrastColor: Color(0xFF5CB8FF),
  );

  /// Green, the color of a switch that is on.
  static const systemGreen = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0xFF34C759),
    darkColor: Color(0xFF30D158),
    highContrastColor: Color(0xFF008932),
    darkHighContrastColor: Color(0xFF4AD968),
  );

  /// Red, the color of destructive actions.
  static const systemRed = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0xFFFF383C),
    darkColor: Color(0xFFFF4245),
    highContrastColor: Color(0xFFE9152D),
    darkHighContrastColor: Color(0xFFFF6165),
  );

  /// Orange.
  static const systemOrange = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0xFFFF9500),
    darkColor: Color(0xFFFF9F0A),
    highContrastColor: Color(0xFFC93400),
    darkHighContrastColor: Color(0xFFFFB340),
  );

  /// The mid gray.
  static const systemGray = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0xFF8E8E93),
    darkColor: Color(0xFF8E8E93),
    highContrastColor: Color(0xFF6C6C70),
    darkHighContrastColor: Color(0xFFAEAEB2),
  );

  /// The gray of a disabled prominent control.
  static const systemGray4 = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0xFFD1D1D6),
    darkColor: Color(0xFF3A3A3C),
    highContrastColor: Color(0xFFBCBCC0),
    darkHighContrastColor: Color(0xFF444446),
  );
}
