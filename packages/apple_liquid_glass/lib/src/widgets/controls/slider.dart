import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/state_colors.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// The look of a [GlassSlider], like Flutter's `ButtonStyle`.
///
/// Every field but [builder] is resolved against the slider's states. A
/// slider looks a field up in its own style, then in the theme's, then in
/// its defaults, state by state: a property that gives null for a state
/// leaves that state to the next one. [merge] combines two styles the same
/// way.
@immutable
class GlassSliderStyle extends GlassStyle<GlassSliderStyle> {
  /// Creates a style.
  const GlassSliderStyle({
    this.thumbColor,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.tickColor,
    this.focusColor,
    this.hoverColor,
    this.builder,
  });

  /// The theme's [GlassSliderStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassSliderStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassSliderStyle>(context);

  /// The fill of the resting thumb (UIKit `thumbTintColor`); white in both
  /// appearances by default (slider passport).
  final WidgetStateProperty<Color?>? thumbColor;

  /// The track below the value (UIKit `minimumTrackTintColor`); the theme's
  /// primary color by default, else [GlassColors.systemBlue].
  final WidgetStateProperty<Color?>? activeTrackColor;

  /// The track above the value (UIKit `maximumTrackTintColor`); by default
  /// black or white at 10 percent (slider passport).
  final WidgetStateProperty<Color?>? inactiveTrackColor;

  /// The tick marks of a stepped slider; [GlassColors.opaqueSeparator] by
  /// default, the dot color the slider passport measured.
  final WidgetStateProperty<Color?>? tickColor;

  /// The ring around the thumb of a slider focused from the keyboard; null
  /// derives it from the thumb's color as Flutter's Cupertino controls do,
  /// from systemBlue for a white or gray thumb, and a transparent color
  /// draws none.
  final Color? focusColor;

  /// What a mouse over the slider adds to its track and thumb; null for a
  /// pressed glass's wash at half strength, and a transparent color shows
  /// none.
  final Color? hoverColor;

  /// Builds the slider's look in place of the default one; the slider then
  /// ignores the other fields. Null leaves it to the theme's builder, then
  /// the default look.
  final GlassSliderBuilder? builder;

  /// This style over [other], state by state.
  @override
  GlassSliderStyle merge(GlassSliderStyle? other) {
    if (other == null) return this;
    return GlassSliderStyle(
      thumbColor: GlassStyle.mergeStates(thumbColor, other.thumbColor),
      activeTrackColor: GlassStyle.mergeStates(
        activeTrackColor,
        other.activeTrackColor,
      ),
      inactiveTrackColor: GlassStyle.mergeStates(
        inactiveTrackColor,
        other.inactiveTrackColor,
      ),
      tickColor: GlassStyle.mergeStates(tickColor, other.tickColor),
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      builder: builder ?? other.builder,
    );
  }

  /// The style between this one and [other] at [t]; the builder switches
  /// at the middle.
  @override
  GlassSliderStyle lerp(GlassSliderStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpStateColors(t);
    return GlassSliderStyle(
      thumbColor: color(thumbColor, other.thumbColor),
      activeTrackColor: color(activeTrackColor, other.activeTrackColor),
      inactiveTrackColor: color(inactiveTrackColor, other.inactiveTrackColor),
      tickColor: color(tickColor, other.tickColor),
      focusColor: GlassDynamicColor.lerp(focusColor, other.focusColor, t),
      hoverColor: GlassDynamicColor.lerp(hoverColor, other.hoverColor, t),
      builder: t < 0.5 ? builder : other.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSliderStyle &&
      other.thumbColor == thumbColor &&
      other.activeTrackColor == activeTrackColor &&
      other.inactiveTrackColor == inactiveTrackColor &&
      other.tickColor == tickColor &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    thumbColor,
    activeTrackColor,
    inactiveTrackColor,
    tickColor,
    focusColor,
    hoverColor,
    builder,
  );
}

/// An iOS 27 slider: a value between [min] and [max], set by dragging a
/// thumb that turns into glass.
///
/// UIKit: `UISlider`. SwiftUI: `Slider`. Flutter: `CupertinoSlider`.
///
/// The app holds the value: pass it as [value] and set it again in
/// [onChanged]; a null [onChanged] disables the slider. [onChangeStart]
/// and [onChangeEnd] bracket a drag. With [ticks] the value snaps to
/// evenly spaced stops, and [animated] moves the thumb to a new [value]
/// from outside on a spring instead of jumping. [style], usually built
/// with [styleFrom], changes its colors. It fills the width it is given,
/// or takes 200 points without a bounded width.
///
/// ```dart
/// GlassSlider(
///   value: volume,
///   onChanged: (value) => setState(() => volume = value),
/// )
/// ```
///
/// The track and the fill are plain fills on every renderer, and the thumb
/// an opaque platter at rest. While a finger lifts the thumb, the liquid
/// renderer turns it into liquid glass and the fake renderer into blurred
/// glass; the flat renderer, which also draws when no `GlassScope` is
/// above, fades the platter and gives it a rim.
///
/// Its touch, keys, haptics and motion are [RawGlassSlider]'s. A disabled
/// slider draws at half opacity. Focused from the keyboard its thumb draws
/// the renderer's focus ring, and under a mouse its track and thumb take
/// the renderer's hover response.
///
/// Fidelity. The disabled opacity matches UIKit on an iPhone 16 Pro, in
/// light and dark. The 200 point width and the focus ring and hover
/// response are not measured; the latter two are approximations of the
/// platform.
class GlassSlider extends StatefulWidget {
  /// Creates a slider showing [value] between [min] and [max].
  const GlassSlider({
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0,
    this.max = 1,
    this.ticks = 0,
    this.animated = false,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// See [RawGlassSlider.value].
  final double value;

  /// See [RawGlassSlider.onChanged].
  final ValueChanged<double>? onChanged;

  /// See [RawGlassSlider.onChangeStart].
  final ValueChanged<double>? onChangeStart;

  /// See [RawGlassSlider.onChangeEnd].
  final ValueChanged<double>? onChangeEnd;

  /// See [RawGlassSlider.min].
  final double min;

  /// See [RawGlassSlider.max].
  final double max;

  /// See [RawGlassSlider.ticks].
  final int ticks;

  /// See [RawGlassSlider.animated].
  final bool animated;

  /// The look, over the theme's and the slider's defaults.
  final GlassSliderStyle? style;

  /// Where the slider writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The slider's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the slider takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the slider.
  final String? semanticLabel;

  /// A style from plain colors; a null color leaves the field to the
  /// theme, then the default.
  static GlassSliderStyle styleFrom({
    Color? thumbColor,
    Color? activeTrackColor,
    Color? inactiveTrackColor,
    Color? tickColor,
  }) => GlassSliderStyle(
    thumbColor: GlassStyle.allOrNull(thumbColor),
    activeTrackColor: GlassStyle.allOrNull(activeTrackColor),
    inactiveTrackColor: GlassStyle.allOrNull(inactiveTrackColor),
    tickColor: GlassStyle.allOrNull(tickColor),
  );

  static const _inactiveTrack = GlassDynamicColor.withBrightness(
    color: Color(0x1A000000),
    darkColor: Color(0x1AFFFFFF),
  );

  @override
  State<GlassSlider> createState() => _GlassSliderState();
}

class _GlassSliderState extends State<GlassSlider> {
  GlassSliderStyle? _look;
  late GlassSliderBuilder _builder;

  // One builder per look: the core keeps the look it built until the
  // builder changes, so a style or theme change reaches it through a new
  // builder; brightness and contrast reach it through [_SliderLook].
  GlassSliderBuilder _builderFor(GlassSliderStyle look) {
    if (look == _look) return _builder;
    _look = look;
    return _builder =
        look.builder ??
        (context, details) => _SliderLook(details: details, look: look);
  }

  @override
  Widget build(BuildContext context) {
    final look = (widget.style ?? const GlassSliderStyle()).merge(
      GlassSliderStyle.maybeOf(context),
    );
    return RawGlassSlider(
      value: widget.value,
      onChanged: widget.onChanged,
      onChangeStart: widget.onChangeStart,
      onChangeEnd: widget.onChangeEnd,
      min: widget.min,
      max: widget.max,
      ticks: widget.ticks,
      animated: widget.animated,
      statesController: widget.statesController,
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      semanticLabel: widget.semanticLabel,
      builder: _builderFor(look),
    );
  }
}

/// A small lens that shows its track unchanged under it, and rests on a
/// shadow: black at 0.14, a Gaussian of sigma 5, 1 pt down.
///
/// Measured on the iPhone 16 Pro references: under a resting thumb the
/// light page reads 224, 233 and 238 of 242 at 0.3, 3 and 6.7 pt below it,
/// where this shadow under a straight edge gives 223, 230 and 238. Neither
/// a switch's knob nor a selection casts one at rest.
const _thumbLens = GlassLens(
  small: true,
  restingShadow: BoxShadow(
    color: Color(0x24000000),
    offset: Offset(0, 1),
    // A sigma of 5 (BoxShadow.convertRadiusToSigma).
    blurRadius: 7.794,
  ),
);

class _SliderLook extends StatelessWidget {
  const _SliderLook({required this.details, required this.look});

  final GlassSliderDetails details;
  final GlassSliderStyle look;

  @override
  Widget build(BuildContext context) {
    final states = details.states;
    final color = StateColors(context, states);
    final active = color(
      look.activeTrackColor,
      GlassTheme.primaryColorOf(context) ?? GlassColors.systemBlue,
    );
    // The ring goes around the thumb alone; the hover shows on every part,
    // as a white thumb takes the wash without a visible change.
    Widget surface(
      GlassRole role,
      MotionSelection<GlassFrame> frame,
      Color tint, {
      GlassLens lens = const GlassLens(),
      bool ring = false,
    }) => Positioned.fill(
      child: GlassSurface.live(
        role: role,
        lens: lens,
        glass: Glass.regular(tint: tint),
        frame: frame,
        states: details.statesListenable,
        focusColor: ring ? look.focusColor : GlassHighlights.noRing,
        hoverColor: look.hoverColor,
        child: const SizedBox.expand(),
      ),
    );
    return Opacity(
      opacity: states.contains(WidgetState.disabled) ? 0.5 : 1,
      child: Stack(
        children: [
          surface(
            GlassRole.track,
            details.track,
            color(look.inactiveTrackColor, GlassSlider._inactiveTrack),
          ),
          surface(GlassRole.track, details.fill, active),
          if (details.ticks.isNotEmpty)
            Positioned.fill(
              child: CustomPaint(
                painter: _TickPainter(
                  details.ticks,
                  color(look.tickColor, GlassColors.opaqueSeparator),
                ),
              ),
            ),
          surface(
            GlassRole.lens,
            details.thumb,
            color(look.thumbColor, const Color(0xFFFFFFFF)),
            lens: _thumbLens,
            ring: true,
          ),
        ],
      ),
    );
  }
}

class _TickPainter extends CustomPainter {
  _TickPainter(this.ticks, this.color);

  final List<Offset> ticks;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    paint.color = color;
    for (final center in ticks) {
      canvas.drawCircle(center, RawGlassSlider.tickSize / 2, paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter oldDelegate) =>
      !listEquals(oldDelegate.ticks, ticks) || oldDelegate.color != color;
}
