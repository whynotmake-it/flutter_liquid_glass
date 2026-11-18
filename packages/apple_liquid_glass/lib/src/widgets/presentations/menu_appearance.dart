import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

/// The look of a glass menu's rows; a null field leaves it to the theme's
/// style, then the default, which follows the brightness (iPhone 16 Pro,
/// iOS 27).
@immutable
class GlassMenuStyle extends GlassStyle<GlassMenuStyle> {
  /// Creates a style.
  const GlassMenuStyle({
    this.textStyle,
    this.destructiveColor,
    this.highlightColor,
    this.secondaryColor,
    this.disabledColor,
    this.separatorColor,
    this.paletteSelectionColor,
  });

  /// The theme's [GlassMenuStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassMenuStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassMenuStyle>(context);

  /// The row titles, whose color also draws row glyphs, over the default
  /// 17 points in label at 96 percent. The menu measures its titles in it
  /// to lay out the rows.
  final TextStyle? textStyle;

  /// The titles and glyphs of destructive rows; systemRed by default.
  final Color? destructiveColor;

  /// The pill under the highlighted row.
  final Color? highlightColor;

  /// Subtitles and section headers; secondaryLabel by default.
  final Color? secondaryColor;

  /// Disabled rows and the loading row; tertiaryLabel by default.
  final Color? disabledColor;

  /// The hairline between groups of rows.
  final Color? separatorColor;

  /// The platter under the selected palette cell.
  final Color? paletteSelectionColor;

  /// This style over [other].
  @override
  GlassMenuStyle merge(GlassMenuStyle? other) {
    if (other == null) return this;
    return GlassMenuStyle(
      textStyle: other.textStyle?.merge(textStyle) ?? textStyle,
      destructiveColor: destructiveColor ?? other.destructiveColor,
      highlightColor: highlightColor ?? other.highlightColor,
      secondaryColor: secondaryColor ?? other.secondaryColor,
      disabledColor: disabledColor ?? other.disabledColor,
      separatorColor: separatorColor ?? other.separatorColor,
      paletteSelectionColor:
          paletteSelectionColor ?? other.paletteSelectionColor,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassMenuStyle lerp(GlassMenuStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpNullable(GlassDynamicColor.lerp);
    return GlassMenuStyle(
      textStyle: GlassStyle.lerpNullable(TextStyle.lerp)(
        textStyle,
        other.textStyle,
        t,
      ),
      destructiveColor: color(destructiveColor, other.destructiveColor, t),
      highlightColor: color(highlightColor, other.highlightColor, t),
      secondaryColor: color(secondaryColor, other.secondaryColor, t),
      disabledColor: color(disabledColor, other.disabledColor, t),
      separatorColor: color(separatorColor, other.separatorColor, t),
      paletteSelectionColor: color(
        paletteSelectionColor,
        other.paletteSelectionColor,
        t,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassMenuStyle &&
      other.textStyle == textStyle &&
      other.destructiveColor == destructiveColor &&
      other.highlightColor == highlightColor &&
      other.secondaryColor == secondaryColor &&
      other.disabledColor == disabledColor &&
      other.separatorColor == separatorColor &&
      other.paletteSelectionColor == paletteSelectionColor;

  @override
  int get hashCode => Object.hash(
    textStyle,
    destructiveColor,
    highlightColor,
    secondaryColor,
    disabledColor,
    separatorColor,
    paletteSelectionColor,
  );
}

/// The colors of a glass menu, light and dark (iPhone 16 Pro).
@internal
@immutable
class MenuAppearance {
  /// Creates an appearance; the defaults are the iOS 27 light appearance.
  const MenuAppearance({
    this.textStyle = const TextStyle(fontSize: 17, color: Color(0xF5000000)),
    this.destructiveColor = const Color(0xFFFF383C),
    this.highlightColor = const Color(0x1F000000),
    this.secondaryColor = const Color(0x993C3C43),
    this.disabledColor = const Color(0x4C3C3C43),
    this.separatorColor = const Color(0x14000000),
    this.paletteSelectionColor = const Color(0x10000000),
  });

  /// The table for the brightness at [context] under [style] and the
  /// theme's style.
  factory MenuAppearance.of(BuildContext context, GlassMenuStyle? style) {
    final table = switch (GlassTraits.of(context).brightness) {
      Brightness.dark => dark,
      Brightness.light => light,
    };
    final look = (style ?? const GlassMenuStyle()).merge(
      GlassMenuStyle.maybeOf(context),
    );
    if (look == const GlassMenuStyle()) return table;
    Color color(Color? override, Color fallback) =>
        GlassDynamicColor.maybeResolve(override, context) ?? fallback;
    final text = table.textStyle.merge(look.textStyle);
    return MenuAppearance(
      textStyle: text.copyWith(
        color: color(text.color, table.textStyle.color!),
      ),
      destructiveColor: color(look.destructiveColor, table.destructiveColor),
      highlightColor: color(look.highlightColor, table.highlightColor),
      secondaryColor: color(look.secondaryColor, table.secondaryColor),
      disabledColor: color(look.disabledColor, table.disabledColor),
      separatorColor: color(look.separatorColor, table.separatorColor),
      paletteSelectionColor: color(
        look.paletteSelectionColor,
        table.paletteSelectionColor,
      ),
    );
  }

  /// The style of row titles, whose color also draws row glyphs.
  ///
  /// The menu shows in an overlay, outside the text style of the screen
  /// the button sits on, so this is the whole style of its titles: it
  /// replaces the overlay's ambient text style instead of merging into it.
  final TextStyle textStyle;

  /// The color of destructive rows.
  final Color destructiveColor;

  /// The fill of the pill under the highlighted row.
  final Color highlightColor;

  /// The color of subtitles and section headers: secondaryLabel.
  final Color secondaryColor;

  /// The color of disabled rows and of the loading row: tertiaryLabel.
  final Color disabledColor;

  /// The color of the hairline between groups of rows (rendered 229 on
  /// the 249 light platter, 50 on the 32 dark one).
  final Color separatorColor;

  /// The platter under the selected palette cell (sampled: 233 on 249
  /// light, 53 on 32 dark).
  final Color paletteSelectionColor;

  /// The row glyph size from the iOS 27 menu view tree, in points.
  static const double rowIconSize = 20;

  /// The gap below a row title, from the 60-point subtitle row view tree.
  static const double subtitleGap = 2.67;

  /// The checkmark bounds from the iOS 27 menu view tree.
  static const Size checkSize = Size(13.33, 12.33);

  /// The mixed-state dash bounds from the iOS 27 menu view tree.
  static const Size mixedSize = Size(12.67, 3.67);

  /// The submenu chevron bounds from the iOS 27 menu view tree.
  static const Size chevronSize = Size(9.33, 12.67);

  /// The selection glyph slot; a layout default, not measured.
  static const double markSlot = 16;

  /// The row image slot; a layout default, not measured.
  static const double imageSlot = 30;

  /// The horizontal inset of the highlight pill from the menu's sides.
  static const double highlightInset = 10;

  /// The cell highlight radius; a rendering default, not measured.
  static const double cellHighlightRadius = 12;

  /// The menu scroll indicator width; a rendering default, not measured.
  static const double scrollThickness = 3;

  /// The menu scroll indicator edge inset; a rendering default, not measured.
  static const double scrollInset = 4;

  /// The light appearance.
  static const light = MenuAppearance();

  /// The dark appearance, sampled from the iOS 27 dark menu.
  static const dark = MenuAppearance(
    textStyle: TextStyle(fontSize: 17, color: Color(0xF5FFFFFF)),
    destructiveColor: Color(0xFFFF4245),
    highlightColor: Color(0x29FFFFFF),
    secondaryColor: Color(0x99EBEBF5),
    disabledColor: Color(0x4CEBEBF5),
    separatorColor: Color(0x14FFFFFF),
    paletteSelectionColor: Color(0x18FFFFFF),
  );

  @override
  bool operator ==(Object other) =>
      other is MenuAppearance &&
      other.textStyle == textStyle &&
      other.destructiveColor == destructiveColor &&
      other.highlightColor == highlightColor &&
      other.secondaryColor == secondaryColor &&
      other.disabledColor == disabledColor &&
      other.separatorColor == separatorColor &&
      other.paletteSelectionColor == paletteSelectionColor;

  @override
  int get hashCode => Object.hash(
    textStyle,
    destructiveColor,
    highlightColor,
    secondaryColor,
    disabledColor,
    separatorColor,
    paletteSelectionColor,
  );
}
