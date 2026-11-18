import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/state_colors.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';

/// The look of a [GlassSwitch], like Flutter's `ButtonStyle`.
///
/// Every field but [builder] is resolved against the switch's states. A
/// switch looks a field up in its own style, then in the theme's, then in
/// its defaults, state by state: a property that gives null for a state
/// leaves that state to the next one. [merge] combines two styles the same
/// way.
@immutable
class GlassSwitchStyle extends GlassStyle<GlassSwitchStyle> {
  /// Creates a style.
  const GlassSwitchStyle({
    this.thumbColor,
    this.activeTrackColor,
    this.inactiveTrackColor,
    this.focusColor,
    this.hoverColor,
    this.builder,
  });

  /// The theme's [GlassSwitchStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassSwitchStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassSwitchStyle>(context);

  /// The fill of the resting knob (UIKit `thumbTintColor`).
  final WidgetStateProperty<Color?>? thumbColor;

  /// The track when on (UIKit `onTintColor`).
  final WidgetStateProperty<Color?>? activeTrackColor;

  /// The track when off; by default 0x3C3C43 in light and 0xEBEBF5 in dark
  /// at 30 percent ([GlassColors.tertiaryLabel]'s colors), and under
  /// Increase Contrast at 70 and 55 percent. Measured on the iOS 27
  /// simulator over two backgrounds in each appearance, and matched by the
  /// iPhone 16 Pro references.
  final WidgetStateProperty<Color?>? inactiveTrackColor;

  /// The ring around a switch focused from the keyboard; null derives it
  /// from systemBlue as Flutter's Cupertino controls do, and a transparent
  /// color draws none.
  final Color? focusColor;

  /// What a mouse over the switch adds to its track; null for a pressed
  /// glass's wash at half strength, and a transparent color shows none.
  final Color? hoverColor;

  /// Builds the switch's look in place of the default one; the switch then
  /// ignores the other fields. Null leaves it to the theme's builder, then
  /// the default look.
  final GlassSwitchBuilder? builder;

  /// This style over [other], state by state.
  @override
  GlassSwitchStyle merge(GlassSwitchStyle? other) {
    if (other == null) return this;
    return GlassSwitchStyle(
      thumbColor: GlassStyle.mergeStates(thumbColor, other.thumbColor),
      activeTrackColor: GlassStyle.mergeStates(
        activeTrackColor,
        other.activeTrackColor,
      ),
      inactiveTrackColor: GlassStyle.mergeStates(
        inactiveTrackColor,
        other.inactiveTrackColor,
      ),
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      builder: builder ?? other.builder,
    );
  }

  /// The style between this one and [other] at [t]; the builder switches
  /// at the middle.
  @override
  GlassSwitchStyle lerp(GlassSwitchStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpStateColors(t);
    return GlassSwitchStyle(
      thumbColor: color(thumbColor, other.thumbColor),
      activeTrackColor: color(activeTrackColor, other.activeTrackColor),
      inactiveTrackColor: color(inactiveTrackColor, other.inactiveTrackColor),
      focusColor: GlassDynamicColor.lerp(focusColor, other.focusColor, t),
      hoverColor: GlassDynamicColor.lerp(hoverColor, other.hoverColor, t),
      builder: t < 0.5 ? builder : other.builder,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassSwitchStyle &&
      other.thumbColor == thumbColor &&
      other.activeTrackColor == activeTrackColor &&
      other.inactiveTrackColor == inactiveTrackColor &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    thumbColor,
    activeTrackColor,
    inactiveTrackColor,
    focusColor,
    hoverColor,
    builder,
  );
}

/// UIKit's lifted knob: on the iPhone 16 Pro references it shows the
/// track's edges 0.755 of its height apart.
const _knobLens = GlassLens.lifted(small: true);

/// An iOS 27 on/off switch whose knob turns into glass under the finger.
///
/// UIKit: `UISwitch`. SwiftUI: `Toggle` with the switch style. Flutter:
/// `CupertinoSwitch`.
///
/// The app holds the state: pass it as [value] and set it again in
/// [onChanged]; a switch whose [value] does not follow returns to it. A
/// null [onChanged] disables the switch. [style], usually built with
/// [styleFrom], changes the knob and track colors. A switch often stands
/// as the `trailing` control of a `GlassListRow`.
///
/// ```dart
/// GlassSwitch(
///   value: wifi,
///   onChanged: (on) => setState(() => wifi = on),
/// )
/// ```
///
/// The track is a plain fill on every renderer, and the knob an opaque
/// platter at rest. While a finger lifts the knob, the liquid renderer
/// turns it into liquid glass and the fake renderer into blurred glass;
/// the flat renderer, which also draws when no `GlassScope` is above,
/// fades the platter and gives it a rim.
///
/// Its touch, keys, haptics and motion are [RawGlassSwitch]'s. A disabled
/// switch draws at half opacity. Focused from the keyboard its track draws
/// the renderer's focus ring, and under a mouse it takes the renderer's
/// hover response.
///
/// Fidelity. The disabled opacity matches UIKit on an iPhone 16 Pro, in
/// light and dark, on and off. The lifted knob is close to UIKit's but not
/// identical: it shows the track's edges 0.77 of its height apart on the
/// liquid renderer, where the iPhone shows 0.755. The focus ring and the
/// hover response are approximations of the platform, not measured.
class GlassSwitch extends StatelessWidget {
  /// Creates a switch showing [value].
  const GlassSwitch({
    required this.value,
    required this.onChanged,
    this.style,
    this.statesController,
    this.focusNode,
    this.autofocus = false,
    this.semanticLabel,
    super.key,
  });

  /// Whether the switch is on.
  final bool value;

  /// Called with the new value when the user toggles the switch; null
  /// disables it.
  final ValueChanged<bool>? onChanged;

  /// The look, over the theme's and the switch's defaults.
  final GlassSwitchStyle? style;

  /// Where the switch writes its states, or null for its own.
  final WidgetStatesController? statesController;

  /// The switch's focus node, or null for its own.
  final FocusNode? focusNode;

  /// Whether the switch takes focus when it first appears.
  final bool autofocus;

  /// What accessibility reads for the switch.
  final String? semanticLabel;

  /// A style from plain colors; a null color leaves the field to the
  /// theme, then the default.
  static GlassSwitchStyle styleFrom({
    Color? thumbColor,
    Color? activeTrackColor,
    Color? inactiveTrackColor,
  }) => GlassSwitchStyle(
    thumbColor: GlassStyle.allOrNull(thumbColor),
    activeTrackColor: GlassStyle.allOrNull(activeTrackColor),
    inactiveTrackColor: GlassStyle.allOrNull(inactiveTrackColor),
  );

  static const _inactiveTrack = GlassDynamicColor.withBrightnessAndContrast(
    color: Color(0x4C3C3C43),
    darkColor: Color(0x4CEBEBF5),
    highContrastColor: Color(0xB23C3C43),
    darkHighContrastColor: Color(0x8CEBEBF5),
  );

  static const _disabledOpacity = 0.5;

  @override
  Widget build(BuildContext context) {
    final look = (style ?? const GlassSwitchStyle()).merge(
      GlassSwitchStyle.maybeOf(context),
    );
    return RawGlassSwitch(
      value: value,
      onChanged: onChanged,
      statesController: statesController,
      focusNode: focusNode,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      builder:
          look.builder ??
          (context, details) => _defaultBody(context, details, look),
    );
  }

  Widget _defaultBody(
    BuildContext context,
    GlassSwitchDetails details,
    GlassSwitchStyle look,
  ) {
    final states = details.states;
    final color = StateColors(context, states);
    final off = color(look.inactiveTrackColor, _inactiveTrack);
    final on = color(look.activeTrackColor, GlassColors.systemGreen);
    final body = Stack(
      children: [
        Positioned.fill(
          child: _SwitchTrack(
            off: off,
            on: on,
            progress: details.progress,
            states: details.statesListenable,
            focusColor: look.focusColor,
            hoverColor: look.hoverColor,
          ),
        ),
        Positioned.fill(
          child: GlassSurface.live(
            role: GlassRole.lens,
            lens: _knobLens,
            glass: Glass.regular(
              tint: color(look.thumbColor, const Color(0xFFFFFFFF)),
            ),
            frame: details.thumb,
            child: const SizedBox.expand(),
          ),
        ),
      ],
    );
    return Opacity(
      opacity: states.contains(WidgetState.disabled) ? _disabledOpacity : 1,
      child: body,
    );
  }
}

class _SwitchTrack extends StatefulWidget {
  const _SwitchTrack({
    required this.off,
    required this.on,
    required this.progress,
    required this.states,
    required this.focusColor,
    required this.hoverColor,
  });

  final Color off;
  final Color on;
  final MotionSelection<double> progress;
  final ValueListenable<Set<WidgetState>>? states;
  final Color? focusColor;
  final Color? hoverColor;

  @override
  State<_SwitchTrack> createState() => _SwitchTrackState();
}

class _SwitchTrackState extends State<_SwitchTrack> {
  late MotionSelection<GlassFrame> _frame = _tint();

  // The colors are not motion reads, so a selection made for other colors
  // cannot notice them change.
  MotionSelection<GlassFrame> _tint() {
    final off = widget.off;
    final on = widget.on;
    final progress = widget.progress;
    return MotionSelection(
      () => GlassFrame(
        tint: Color.lerp(off, on, progress.value.clamp(0.0, 1.0)),
      ),
    );
  }

  @override
  void didUpdateWidget(_SwitchTrack old) {
    super.didUpdateWidget(old);
    if (old.off != widget.off ||
        old.on != widget.on ||
        old.progress != widget.progress) {
      _frame = _tint();
    }
  }

  @override
  Widget build(BuildContext context) => GlassSurface.live(
    role: GlassRole.track,
    states: widget.states,
    focusColor: widget.focusColor,
    hoverColor: widget.hoverColor,
    frame: _frame,
    child: const SizedBox.expand(),
  );
}
