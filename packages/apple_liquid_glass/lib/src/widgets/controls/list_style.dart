import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/widgets/controls/list.dart';
import 'package:flutter/widgets.dart';

/// The look of an inset grouped list, like Flutter's `ButtonStyle`.
///
/// Each color property but [focusColor] and [hoverColor] resolves against
/// the row's states (pressed, focused, hovered, disabled) and falls
/// through, state by state, from the row's style to its section's to the
/// theme's to the defaults: a null for a state leaves that state to the
/// next one. The defaults are the iOS 27 system colors the table resolves
/// (list passport, light and dark).
@immutable
class GlassListStyle extends GlassStyle<GlassListStyle> {
  /// Creates a style.
  const GlassListStyle({
    this.backgroundColor,
    this.overlayColor,
    this.separatorColor,
    this.foregroundColor,
    this.secondaryColor,
    this.iconColor,
    this.disclosureColor,
    this.focusColor,
    this.hoverColor,
  });

  /// The theme's [GlassListStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassListStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassListStyle>(context);

  /// The fill of a section's card;
  /// [GlassColors.secondarySystemGroupedBackground] by default.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The fill of a pressed row; [GlassColors.systemGray4], the
  /// grouped cell's highlighted color, by default.
  final WidgetStateProperty<Color?>? overlayColor;

  /// The separators between rows; [GlassListSection.separator] by
  /// default.
  final WidgetStateProperty<Color?>? separatorColor;

  /// A row's title; [GlassColors.label] by default.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// A row's subtitle and detail, and a section's header and footer;
  /// [GlassColors.secondaryLabel] by default.
  final WidgetStateProperty<Color?>? secondaryColor;

  /// A row's leading symbol, checkmark and info button; the theme's
  /// primary color, else [GlassColors.systemBlue], by default.
  final WidgetStateProperty<Color?>? iconColor;

  /// The disclosure chevron; [GlassColors.tertiaryLabel] by default.
  final WidgetStateProperty<Color?>? disclosureColor;

  /// The ring inside a row, and around an info button, focused from the
  /// keyboard; null derives it from systemBlue as Flutter's Cupertino
  /// controls do, and a transparent color draws none.
  final Color? focusColor;

  /// What a mouse over a row or an info button fills under it; null for
  /// [overlayColor] at half strength, and a transparent color shows none.
  final Color? hoverColor;

  /// This style over [other], state by state.
  @override
  GlassListStyle merge(GlassListStyle? other) {
    if (other == null) return this;
    return GlassListStyle(
      backgroundColor: GlassStyle.mergeStates(
        backgroundColor,
        other.backgroundColor,
      ),
      overlayColor: GlassStyle.mergeStates(overlayColor, other.overlayColor),
      separatorColor: GlassStyle.mergeStates(
        separatorColor,
        other.separatorColor,
      ),
      foregroundColor: GlassStyle.mergeStates(
        foregroundColor,
        other.foregroundColor,
      ),
      secondaryColor: GlassStyle.mergeStates(
        secondaryColor,
        other.secondaryColor,
      ),
      iconColor: GlassStyle.mergeStates(iconColor, other.iconColor),
      disclosureColor: GlassStyle.mergeStates(
        disclosureColor,
        other.disclosureColor,
      ),
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassListStyle lerp(GlassListStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpStateColors(t);
    return GlassListStyle(
      backgroundColor: color(backgroundColor, other.backgroundColor),
      overlayColor: color(overlayColor, other.overlayColor),
      separatorColor: color(separatorColor, other.separatorColor),
      foregroundColor: color(foregroundColor, other.foregroundColor),
      secondaryColor: color(secondaryColor, other.secondaryColor),
      iconColor: color(iconColor, other.iconColor),
      disclosureColor: color(disclosureColor, other.disclosureColor),
      focusColor: GlassDynamicColor.lerp(focusColor, other.focusColor, t),
      hoverColor: GlassDynamicColor.lerp(hoverColor, other.hoverColor, t),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassListStyle &&
      other.backgroundColor == backgroundColor &&
      other.overlayColor == overlayColor &&
      other.separatorColor == separatorColor &&
      other.foregroundColor == foregroundColor &&
      other.secondaryColor == secondaryColor &&
      other.iconColor == iconColor &&
      other.disclosureColor == disclosureColor &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    overlayColor,
    separatorColor,
    foregroundColor,
    secondaryColor,
    iconColor,
    disclosureColor,
    focusColor,
    hoverColor,
  );
}
