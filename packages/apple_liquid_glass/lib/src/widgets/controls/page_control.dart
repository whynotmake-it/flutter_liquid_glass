import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/state_colors.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// The look of a [GlassPageControl], like Flutter's `ButtonStyle`. The
/// indicator and platter colors resolve against the control's states
/// ([WidgetState.disabled] while it ignores input); a null leaves a field
/// to the theme's style, then the default.
///
/// The defaults are approximations, not measured, except the dots'
/// Increase Contrast colors, read from UIKit (notes private); the platter
/// is a flat color on every renderer where UIKit uses a material (page
/// control passport).
@immutable
class GlassPageControlStyle extends GlassStyle<GlassPageControlStyle> {
  /// Creates a style.
  const GlassPageControlStyle({
    this.pageIndicatorColor,
    this.currentPageIndicatorColor,
    this.platterColor,
    this.platterIndicatorColor,
    this.focusColor,
    this.hoverColor,
    this.builder,
  });

  /// The theme's [GlassPageControlStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassPageControlStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassPageControlStyle>(context);

  /// The dots of the other pages (UIKit `pageIndicatorTintColor`).
  final WidgetStateProperty<Color?>? pageIndicatorColor;

  /// The dot of the current page and a progress's fill (UIKit
  /// `currentPageIndicatorTintColor`).
  final WidgetStateProperty<Color?>? currentPageIndicatorColor;

  /// The platter behind the dots.
  final WidgetStateProperty<Color?>? platterColor;

  /// The dots of the other pages over the platter.
  final WidgetStateProperty<Color?>? platterIndicatorColor;

  /// The ring around a control focused from the keyboard; null derives it
  /// from systemBlue as Flutter's Cupertino controls do, and a transparent
  /// color draws none.
  final Color? focusColor;

  /// What a mouse over the control fills under its dots; null for the
  /// platter at half strength, and a transparent color shows none.
  final Color? hoverColor;

  /// Builds the control in place of its default look, which then ignores
  /// the other fields. Null leaves it to the theme's builder, then the
  /// default look.
  final GlassPageControlBuilder? builder;

  /// This style over [other], state by state.
  @override
  GlassPageControlStyle merge(GlassPageControlStyle? other) {
    if (other == null) return this;
    return GlassPageControlStyle(
      pageIndicatorColor: GlassStyle.mergeStates(
        pageIndicatorColor,
        other.pageIndicatorColor,
      ),
      currentPageIndicatorColor: GlassStyle.mergeStates(
        currentPageIndicatorColor,
        other.currentPageIndicatorColor,
      ),
      platterColor: GlassStyle.mergeStates(platterColor, other.platterColor),
      platterIndicatorColor: GlassStyle.mergeStates(
        platterIndicatorColor,
        other.platterIndicatorColor,
      ),
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      builder: builder ?? other.builder,
    );
  }

  /// The style between this one and [other] at [t]; the builder switches
  /// at the half.
  @override
  GlassPageControlStyle lerp(GlassPageControlStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpStateColors(t);
    return GlassPageControlStyle(
      pageIndicatorColor: color(pageIndicatorColor, other.pageIndicatorColor),
      currentPageIndicatorColor: color(
        currentPageIndicatorColor,
        other.currentPageIndicatorColor,
      ),
      platterColor: color(platterColor, other.platterColor),
      platterIndicatorColor: color(
        platterIndicatorColor,
        other.platterIndicatorColor,
      ),
      focusColor: GlassDynamicColor.lerp(focusColor, other.focusColor, t),
      hoverColor: GlassDynamicColor.lerp(hoverColor, other.hoverColor, t),
      builder: t < 0.5 ? builder : other.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassPageControlStyle &&
      other.pageIndicatorColor == pageIndicatorColor &&
      other.currentPageIndicatorColor == currentPageIndicatorColor &&
      other.platterColor == platterColor &&
      other.platterIndicatorColor == platterIndicatorColor &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    pageIndicatorColor,
    currentPageIndicatorColor,
    platterColor,
    platterIndicatorColor,
    focusColor,
    hoverColor,
    builder,
  );
}

/// A page control that looks and steps like iOS 27's `UIPageControl`.
///
/// UIKit: `UIPageControl`. SwiftUI: the page style of a `TabView`.
/// Flutter: none.
///
/// Dots for [count] pages, the current one opaque; with [progress] the
/// current indicator is a capsule whose fill shows how far the page has
/// progressed. Its motion and input are [RawGlassPageControl]'s. A
/// disabled control looks like an enabled one and ignores input, as
/// UIKit's does.
///
/// Focused from the keyboard it draws Flutter's Cupertino focus ring
/// around its capsule, and a mouse over it shows the platter at half
/// strength (the rule of the glass controls; an approximation, not
/// measured).
class GlassPageControl extends StatelessWidget {
  /// Creates a page control of [count] pages showing [page].
  const GlassPageControl({
    required this.count,
    required this.page,
    required this.onChanged,
    this.progress,
    this.backgroundStyle = GlassPageControlBackground.automatic,
    this.style,
    this.semanticLabel,
    this.semanticValueFormatter,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  /// The number of pages.
  final int count;

  /// The current page.
  final int page;

  /// Called with the page the user picks; null disables the control. A
  /// control whose [page] does not follow returns to it.
  final ValueChanged<int>? onChanged;

  /// How far the current page has progressed, 0 to 1, or null for plain
  /// dots.
  final double? progress;

  /// When the platter shows.
  final GlassPageControlBackground backgroundStyle;

  /// The look, over the theme's and the control's defaults.
  final GlassPageControlStyle? style;

  /// What accessibility reads for the control.
  final String? semanticLabel;

  /// Formats the adjustable value from a one-based page and the page count;
  /// null reads "page n of count". An empty control has no value.
  final String Function(int page, int count)? semanticValueFormatter;

  /// See [RawGlassPageControl.statesController].
  final WidgetStatesController? statesController;

  /// The control's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the control takes focus when it first appears.
  final bool autofocus;

  /// A style from plain colors; a null color leaves the field to the
  /// theme, then the default.
  static GlassPageControlStyle styleFrom({
    Color? pageIndicatorColor,
    Color? currentPageIndicatorColor,
    Color? platterColor,
    Color? platterIndicatorColor,
  }) => GlassPageControlStyle(
    pageIndicatorColor: GlassStyle.allOrNull(pageIndicatorColor),
    currentPageIndicatorColor: GlassStyle.allOrNull(currentPageIndicatorColor),
    platterColor: GlassStyle.allOrNull(platterColor),
    platterIndicatorColor: GlassStyle.allOrNull(platterIndicatorColor),
  );

  static const _pageIndicator = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x73FFFFFF),
    darkColor: Color(0x73FFFFFF),
    highContrastColor: Color(0x8CFFFFFF),
    darkHighContrastColor: Color(0x8CFFFFFF),
  );
  static const _platter = GlassDynamicColor.withBrightness(
    color: Color(0xFFF0F0F2),
    darkColor: Color(0xFF1F1F1F),
  );
  static const _platterIndicator = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x40000000),
    darkColor: Color(0x4DFFFFFF),
    highContrastColor: Color(0x73000000),
    darkHighContrastColor: Color(0x73FFFFFF),
  );

  @override
  Widget build(BuildContext context) {
    final look = (style ?? const GlassPageControlStyle()).merge(
      GlassPageControlStyle.maybeOf(context),
    );
    return RawGlassPageControl(
      count: count,
      page: page,
      onChanged: onChanged,
      progress: progress,
      backgroundStyle: backgroundStyle,
      semanticLabel: semanticLabel,
      semanticValueFormatter: semanticValueFormatter,
      statesController: statesController,
      focusNode: focusNode,
      autofocus: autofocus,
      builder:
          look.builder ??
          (context, details) => _defaultBody(context, details, look),
    );
  }

  Widget _defaultBody(
    BuildContext context,
    GlassPageControlDetails details,
    GlassPageControlStyle look,
  ) {
    final color = StateColors(context, details.states);
    final platter = color(look.platterColor, _platter);
    final painted = CustomPaint(
      painter: _PageControlPainter(
        pose: details.pose,
        rtl: Directionality.maybeOf(context) == TextDirection.rtl,
        progress: details.progress,
        pageIndicator: color(look.pageIndicatorColor, _pageIndicator),
        currentPageIndicator: color(
          look.currentPageIndicatorColor,
          const Color(0xFFFFFFFF),
        ),
        platterColor: platter,
        platterIndicator: color(
          look.platterIndicatorColor,
          _platterIndicator,
        ),
      ),
    );
    final states = details.statesListenable;
    if (states == null) return painted;
    return GlassHighlightPaint.of(
      context,
      states: states,
      focusColor: look.focusColor,
      hoverColor:
          look.hoverColor ??
          platter.withValues(alpha: platter.a * GlassHighlights.hoverGain),
      child: painted,
    );
  }
}

class _PageControlPainter extends CustomPainter {
  _PageControlPainter({
    required this.pose,
    required this.rtl,
    required this.progress,
    required this.pageIndicator,
    required this.currentPageIndicator,
    required this.platterColor,
    required this.platterIndicator,
  }) : super(repaint: pose);

  final ValueListenable<GlassPageControlPose> pose;
  final bool rtl;
  final double? progress;
  final Color pageIndicator;
  final Color currentPageIndicator;
  final Color platterColor;
  final Color platterIndicator;

  @override
  void paint(Canvas canvas, Size size) {
    final frame = pose.value;
    final shown = frame.platter;
    if (shown > 0) {
      final paint = Paint();
      paint.color = platterColor.withValues(alpha: platterColor.a * shown);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height / 2),
        ),
        paint,
      );
    }
    final other = Color.lerp(pageIndicator, platterIndicator, shown)!;
    for (var i = 0; i < frame.indicators.length; i++) {
      final rect = frame.indicators[i];
      final radius = Radius.circular(rect.height / 2);
      final base = Paint();
      base.color = progress == null && i == frame.page
          ? currentPageIndicator
          : other;
      canvas.drawRRect(RRect.fromRectAndRadius(rect, radius), base);
      final fill = progress == null ? 0.0 : frame.fills[i];
      if (fill <= 0) continue;
      final fraction = i == frame.page ? (progress ?? 0) : 1.0;
      final fillWidth =
          rect.height + (rect.width - rect.height) * fraction.clamp(0, 1);
      final left = rtl ? rect.right - fillWidth : rect.left;
      final paint = Paint();
      paint.color = currentPageIndicator.withValues(
        alpha: currentPageIndicator.a * fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, rect.top, fillWidth, rect.height),
          radius,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PageControlPainter oldDelegate) =>
      oldDelegate.pose != pose ||
      oldDelegate.rtl != rtl ||
      oldDelegate.progress != progress ||
      oldDelegate.pageIndicator != pageIndicator ||
      oldDelegate.currentPageIndicator != currentPageIndicator ||
      oldDelegate.platterColor != platterColor ||
      oldDelegate.platterIndicator != platterIndicator;
}
