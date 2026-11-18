import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/selector_glass.dart';
import 'package:apple_liquid_glass/src/widgets/controls/state_colors.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/widgets.dart';

/// One segment of a [GlassSegmentedControl].
///
/// UIKit: a segment of `UISegmentedControl`. SwiftUI: a tagged view in a
/// `Picker`. Flutter: `ButtonSegment`.
@immutable
final class GlassSegment<T> {
  /// Creates a segment that stands for [value].
  const GlassSegment({
    required this.value,
    required this.label,
    this.enabled = true,
    this.width,
    this.semanticLabel,
  });

  /// The value the segment stands for.
  final T value;

  /// What the segment shows, usually a [Text] or an icon.
  final Widget label;

  /// Whether the segment can be selected (UIKit
  /// `setEnabled(_:forSegmentAt:)`). A disabled segment draws its label at
  /// half opacity (not measured); a touch on it selects nothing and the
  /// arrow keys skip it.
  final bool enabled;

  /// The width of the segment in points, or null to share the room with
  /// the other segments (UIKit `setWidth(_:forSegmentAt:)`).
  final double? width;

  /// What accessibility reads for the segment; null reads the text of its
  /// label: a [Text]'s, or an `Icon`'s semantic label.
  final String? semanticLabel;
}

/// The look of a [GlassSegmentedControl], like Flutter's `ButtonStyle`.
///
/// [backgroundColor] and [thumbColor] are resolved against the control's
/// states, [foregroundColor] and [textStyle] against each segment's, which
/// include [WidgetState.selected]. A control looks a field up in its own
/// style, then in the theme's, then in its defaults, state by state: a
/// property that gives null for a state leaves that state to the next one.
@immutable
class GlassSegmentedStyle extends GlassStyle<GlassSegmentedStyle> {
  /// Creates a style.
  const GlassSegmentedStyle({
    this.backgroundColor,
    this.thumbColor,
    this.foregroundColor,
    this.textStyle,
    this.focusColor,
    this.hoverColor,
    this.builder,
  });

  /// The theme's [GlassSegmentedStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassSegmentedStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassSegmentedStyle>(context);

  /// The track (UIKit `backgroundColor`); [GlassColors.tertiarySystemFill]
  /// by default.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The resting lens (UIKit `selectedSegmentTintColor`); by default
  /// white, and in the dark [GlassColors.tertiaryLabel]'s dark colors, a
  /// white the track shows through. Measured on the iOS 27 simulator over
  /// two backgrounds, with and without Increase Contrast.
  final WidgetStateProperty<Color?>? thumbColor;

  /// The color of a segment's label; [GlassColors.label] by default.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The text style of a segment's label: 13 points, regular, and medium
  /// when selected, by default (segmented control passport).
  final WidgetStateProperty<TextStyle?>? textStyle;

  /// The ring inside a segment focused from the keyboard; null derives it
  /// from systemBlue as Flutter's Cupertino controls do, and a transparent
  /// color draws none.
  final Color? focusColor;

  /// What a mouse over a segment adds to its colors; null for the wash of
  /// a glass body at half a press's strength, and a transparent color
  /// shows none.
  final Color? hoverColor;

  /// Builds the control's look in place of the default one; the control
  /// then ignores [backgroundColor] and [thumbColor]. Null leaves it to the
  /// theme's builder, then the default look.
  final GlassSelectorBuilder? builder;

  /// This style over [other], state by state.
  @override
  GlassSegmentedStyle merge(GlassSegmentedStyle? other) {
    if (other == null) return this;
    return GlassSegmentedStyle(
      backgroundColor: GlassStyle.mergeStates(
        backgroundColor,
        other.backgroundColor,
      ),
      thumbColor: GlassStyle.mergeStates(thumbColor, other.thumbColor),
      foregroundColor: GlassStyle.mergeStates(
        foregroundColor,
        other.foregroundColor,
      ),
      textStyle: GlassStyle.mergeStates(textStyle, other.textStyle),
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      builder: builder ?? other.builder,
    );
  }

  /// The style between this one and [other] at [t]; the builder switches
  /// at the middle.
  @override
  GlassSegmentedStyle lerp(GlassSegmentedStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpStateColors(t);
    return GlassSegmentedStyle(
      backgroundColor: color(backgroundColor, other.backgroundColor),
      thumbColor: color(thumbColor, other.thumbColor),
      foregroundColor: color(foregroundColor, other.foregroundColor),
      textStyle: WidgetStateProperty.lerp<TextStyle?>(
        textStyle,
        other.textStyle,
        t,
        GlassStyle.lerpNullable(TextStyle.lerp),
      ),
      focusColor: GlassDynamicColor.lerp(focusColor, other.focusColor, t),
      hoverColor: GlassDynamicColor.lerp(hoverColor, other.hoverColor, t),
      builder: t < 0.5 ? builder : other.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSegmentedStyle &&
      other.backgroundColor == backgroundColor &&
      other.thumbColor == thumbColor &&
      other.foregroundColor == foregroundColor &&
      other.textStyle == textStyle &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    thumbColor,
    foregroundColor,
    textStyle,
    focusColor,
    hoverColor,
    builder,
  );
}

/// An iOS 27 segmented control: a row of segments, one of them selected
/// under a sliding lens.
///
/// UIKit: `UISegmentedControl`. SwiftUI: `Picker` with
/// `.pickerStyle(.segmented)`. Flutter: `CupertinoSlidingSegmentedControl`.
///
/// Pass one [GlassSegment] per choice, each with its value and label, and
/// the selected value as [groupValue] (null selects none); set it again in
/// [onChanged], or the control returns to it. With [onChanged] and
/// [onReselected] both null the control is disabled; a single
/// [GlassSegment] turns off through its `enabled`. Segments share the
/// width equally, or take their labels' widths with [proportionalWidth].
/// [style], usually built with [styleFrom], changes colors and label
/// styles.
///
/// ```dart
/// GlassSegmentedControl<String>(
///   segments: const [
///     GlassSegment(value: 'day', label: Text('Day')),
///     GlassSegment(value: 'week', label: Text('Week')),
///   ],
///   groupValue: range,
///   onChanged: (value) => setState(() => range = value),
/// )
/// ```
///
/// The track is a plain fill on every renderer, and the lens a plain
/// platter at rest. While a finger drags the lens, the liquid renderer
/// turns it into clear liquid glass and the fake renderer into blurred
/// glass; the flat renderer, which also draws when no `GlassScope` is
/// above, fades the platter and gives it a rim.
///
/// The lifted lens bends the labels under its rim but does not magnify
/// them, and the label inside it takes the selected style. The motion,
/// keys and semantics are [RawGlassSelector]'s with
/// [GlassSelectorMotion.segmented]. Labels follow the text scale up to
/// 1.4, and a segment is as wide as the wider of its label's regular and
/// selected styles. A disabled control draws at half opacity. Segments are
/// told apart by their values: a change of [segments] inside `withSpring`
/// slides the segments that stay, fades new ones in and old ones out, and
/// the lens moves with its segment ([RawGlassSelector.itemKeys]). Focused
/// from the keyboard, a segment draws Flutter's Cupertino focus ring
/// inside its cell, and a mouse over a segment washes its cell as a glass
/// body's hover does.
///
/// Fidelity. The lens that bends without magnifying is measured on iOS 27,
/// and the disabled opacity matches UIKit on an iPhone 16 Pro in light and
/// dark. Not measured: the text scale limit of 1.4, the change of
/// [segments] (UIKit's animated insertSegment was not captured), and the
/// focus ring and hover response, which are approximations of the
/// platform.
class GlassSegmentedControl<T> extends StatelessWidget {
  /// Creates a segmented control showing [groupValue] selected.
  const GlassSegmentedControl({
    required this.segments,
    required this.groupValue,
    required this.onChanged,
    this.onReselected,
    this.proportionalWidth = false,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// The segments, in reading order.
  final List<GlassSegment<T>> segments;

  /// The value of the selected segment, or null for none
  /// (`UISegmentedControl.noSegment`); see [RawGlassSelector.selectedIndex].
  final T? groupValue;

  /// Called with the value of the segment the user selects; with
  /// [onReselected] null too, the control is disabled. A control whose
  /// [groupValue] does not follow returns to it.
  final ValueChanged<T>? onChanged;

  /// Called with the selected segment's value when the user selects it
  /// again: to deselect it, set [groupValue] to null.
  final ValueChanged<T>? onReselected;

  /// Whether segments are as wide as their labels rather than equal (UIKit
  /// `apportionsSegmentWidthsByContent`).
  final bool proportionalWidth;

  /// The look, over the theme's and the control's defaults.
  final GlassSegmentedStyle? style;

  /// Where the control writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The control's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the control takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the control as a whole.
  final String? semanticLabel;

  static const double _maxTextScale = 1.4;

  static const _thumb = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0xFFFFFFFF),
    darkColor: Color(0x4CEBEBF5),
    highContrastColor: Color(0xFFFFFFFF),
    darkHighContrastColor: Color(0x60EBEBF5),
  );

  static const _label = TextStyle(fontSize: 13, fontWeight: FontWeight.w400);
  static const _selectedLabel = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
  );

  /// A style from plain colors and text styles; a null value leaves the
  /// field to the theme, then the default.
  static GlassSegmentedStyle styleFrom({
    Color? backgroundColor,
    Color? thumbColor,
    Color? foregroundColor,
    TextStyle? textStyle,
    TextStyle? selectedTextStyle,
  }) => GlassSegmentedStyle(
    backgroundColor: GlassStyle.allOrNull(backgroundColor),
    thumbColor: GlassStyle.allOrNull(thumbColor),
    foregroundColor: GlassStyle.allOrNull(foregroundColor),
    textStyle: textStyle == null && selectedTextStyle == null
        ? null
        : WidgetStateMapper<TextStyle?>({
            WidgetState.selected: selectedTextStyle,
            WidgetState.any: textStyle,
          }),
  );

  GlassSegmentedStyle _defaults(BuildContext context) => GlassSegmentedStyle(
    backgroundColor: const WidgetStatePropertyAll(
      GlassColors.tertiarySystemFill,
    ),
    thumbColor: const WidgetStatePropertyAll(_thumb),
    foregroundColor: WidgetStatePropertyAll(
      GlassTheme.labelColorOf(context),
    ),
    textStyle: const WidgetStateMapper<TextStyle?>({
      WidgetState.selected: _selectedLabel,
      WidgetState.any: _label,
    }),
  );

  int? get _selectedIndex {
    for (var i = 0; i < segments.length; i++) {
      if (segments[i].value == groupValue) return i;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final themed = GlassSegmentedStyle.maybeOf(context);
    final look = (style ?? const GlassSegmentedStyle())
        .merge(themed)
        .merge(_defaults(context));
    final onChanged = this.onChanged;
    final onReselected = this.onReselected;
    return RawGlassSelector(
      itemCount: segments.length,
      itemKeys: [for (final segment in segments) ValueKey<T>(segment.value)],
      selectedIndex: groupValue == null ? null : _selectedIndex,
      onChanged: onChanged == null
          ? null
          : (index) => onChanged(segments[index].value),
      onReselected: onReselected == null
          ? null
          : (index) => onReselected(segments[index].value),
      disabledItems: {
        for (var i = 0; i < segments.length; i++)
          if (!segments[i].enabled) i,
      },
      itemWidths: segments.any((segment) => segment.width != null)
          ? [for (final segment in segments) segment.width]
          : null,
      proportionalWidth: proportionalWidth,
      statesController: statesController,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      itemLabels: [
        for (final segment in segments)
          segment.semanticLabel ?? glassLabelTextOf(segment.label),
      ],
      itemBuilder: (context, index, states) =>
          _SegmentLabel(segment: segments[index], look: look, states: states),
      builder:
          look.builder ??
          (context, details) => Opacity(
            opacity: details.states.contains(WidgetState.disabled) ? 0.5 : 1,
            child: SelectorGlass(
              details: details,
              role: GlassRole.track,
              background: look.backgroundColor,
              thumb: look.thumbColor,
            ),
          ),
    );
  }
}

/// A segment's label in its style, as wide as the wider of its regular and
/// selected looks.
class _SegmentLabel extends StatelessWidget {
  const _SegmentLabel({
    required this.segment,
    required this.look,
    required this.states,
  });

  final GlassSegment<Object?> segment;
  final GlassSegmentedStyle look;
  final Set<WidgetState> states;

  Widget _styled(
    BuildContext context,
    GlassTextScale scale,
    Set<WidgetState> states,
  ) {
    final color = StateColors(context, states)(look.foregroundColor);
    return IconTheme.merge(
      data: IconThemeData(color: color),
      child: DefaultTextStyle.merge(
        style: scale.resolve(
          look.textStyle!.resolve(states)!.copyWith(color: color),
        ),
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        child: segment.label,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = states.contains(WidgetState.selected);
    final other = selected
        ? states.difference({WidgetState.selected})
        : {...states, WidgetState.selected};
    final scale = GlassTextScale.of(
      context,
      max: GlassSegmentedControl._maxTextScale,
    );
    final label = scale.apply(
      IndexedStack(
        alignment: Alignment.center,
        children: [
          _styled(context, scale, states),
          _styled(context, scale, other),
        ],
      ),
    );
    return GlassHighlightPaint.of(
      context,
      heldStates: states,
      focusColor: look.focusColor,
      hoverColor: look.hoverColor,
      inside: true,
      wash: true,
      child: SizedBox.expand(
        child: Center(
          child: segment.enabled ? label : Opacity(opacity: 0.5, child: label),
        ),
      ),
    );
  }
}
