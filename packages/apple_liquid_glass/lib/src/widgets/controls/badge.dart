import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:flutter/widgets.dart';

/// The look of a [GlassBadge]; a null field leaves it to the theme's
/// style, then the default.
@immutable
class GlassBadgeStyle extends GlassStyle<GlassBadgeStyle> {
  /// Creates a style.
  const GlassBadgeStyle({
    this.backgroundColor,
    this.foregroundColor,
    this.textStyle,
  });

  /// The theme's [GlassBadgeStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassBadgeStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassBadgeStyle>(context);

  /// The fill of the badge; [GlassColors.systemRed] by default.
  final Color? backgroundColor;

  /// The color of the text; white by default.
  final Color? foregroundColor;

  /// The text: 12 points, medium, by default. The badge sizes its capsule
  /// to it.
  final TextStyle? textStyle;

  /// This style over [other].
  @override
  GlassBadgeStyle merge(GlassBadgeStyle? other) {
    if (other == null) return this;
    return GlassBadgeStyle(
      backgroundColor: backgroundColor ?? other.backgroundColor,
      foregroundColor: foregroundColor ?? other.foregroundColor,
      textStyle: other.textStyle?.merge(textStyle) ?? textStyle,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassBadgeStyle lerp(GlassBadgeStyle other, double t) {
    if (identical(this, other)) return this;
    return GlassBadgeStyle(
      backgroundColor: GlassStyle.lerpNullable(GlassDynamicColor.lerp)(
        backgroundColor,
        other.backgroundColor,
        t,
      ),
      foregroundColor: GlassStyle.lerpNullable(GlassDynamicColor.lerp)(
        foregroundColor,
        other.foregroundColor,
        t,
      ),
      textStyle: GlassStyle.lerpNullable(TextStyle.lerp)(
        textStyle,
        other.textStyle,
        t,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassBadgeStyle &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor &&
      other.textStyle == textStyle;

  @override
  int get hashCode => Object.hash(backgroundColor, foregroundColor, textStyle);
}

/// A badge on a tab: a count, a short text or a dot.
///
/// UIKit: `UITabBarItem.badgeValue`, `UIBarButtonItem.Badge`. SwiftUI:
/// `badge(_:)`. Flutter: `Badge`.
///
/// It draws in [GlassColors.systemRed] with white text unless its [style] or
/// the theme's says otherwise: a capsule of 12 point medium text with 2
/// points above and below and 4 before and after, at least as wide as it is
/// tall and at most 64 points; the dot is 18 points across. Its text does
/// not follow the text size setting, as the bar items it sits on do not:
/// UIKit shows them through the large content viewer instead
/// (`UILargeContentViewerInteraction`). Its text runs in the ambient
/// direction. These metrics are read from UIKit (notes private); how a
/// badge appears, changes and leaves (UIKit fades it with the bar's update
/// animation) is not reproduced.
class GlassBadge extends StatelessWidget {
  /// A badge showing [count]; a count of zero or less shows no badge.
  const GlassBadge.count(int this.count, {this.style, super.key}) : text = null;

  /// A badge showing [text]; an empty text shows no badge.
  const GlassBadge.text(String this.text, {this.style, super.key})
    : count = null;

  /// A dot without text (UIKit `Badge.indicator()`).
  const GlassBadge.indicator({this.style, super.key})
    : count = null,
      text = null;

  /// The number shown, or null.
  final int? count;

  /// The text shown, or null.
  final String? text;

  /// The look, over the theme's and the badge's defaults.
  final GlassBadgeStyle? style;

  static const double _fontSize = 12;
  static const double _verticalPadding = 2;
  static const double _horizontalPadding = 4;
  static const double _maxWidth = 64;
  static const double _dotSize = 18;

  static const _text = TextStyle(
    fontSize: _fontSize,
    fontWeight: FontWeight.w500,
  );

  bool get _visible => switch ((count, text)) {
    (final int n, _) => n > 0,
    (_, final String t) => t.isNotEmpty,
    _ => true,
  };

  @override
  Widget build(BuildContext context) {
    if (!_visible) return const SizedBox.shrink();
    final label = count?.toString() ?? text;
    final look = (style ?? const GlassBadgeStyle()).merge(
      GlassBadgeStyle.maybeOf(context),
    );
    final fill = GlassDynamicColor.resolve(
      look.backgroundColor ?? GlassColors.systemRed,
      context,
    );
    if (label == null) {
      return Container(
        width: _dotSize,
        height: _dotSize,
        decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
      );
    }
    final scale = GlassTextScale.fixed(context);
    final drawn = scale.resolve(
      _text
          .merge(look.textStyle)
          .copyWith(
            color: GlassDynamicColor.resolve(
              look.foregroundColor ?? const Color(0xFFFFFFFF),
              context,
            ),
          ),
    );
    final line = scale
        .measure(
          label,
          drawn,
          textDirection: Directionality.of(context),
          maxLines: 1,
        )
        .size;
    final height = line.height + 2 * _verticalPadding;
    final width = math.max(
      height,
      math.min(line.width + 2 * _horizontalPadding, _maxWidth),
    );
    return Semantics(
      label: label,
      child: Container(
        width: width,
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: _horizontalPadding),
        decoration: ShapeDecoration(color: fill, shape: const StadiumBorder()),
        child: ExcludeSemantics(
          child: scale.apply(
            Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: drawn,
            ),
          ),
        ),
      ),
    );
  }
}
