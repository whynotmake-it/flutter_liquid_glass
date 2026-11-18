import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/raw.dart';
import 'package:apple_liquid_glass/src/widgets/controls/search_glyphs.dart';
import 'package:apple_liquid_glass/src/widgets/controls/state_colors.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/input.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// The size of the clear button.
const double _clearSize = 20;

/// The space between the clear button and the field's trailing edge.
const double _clearInset = 13.33;

/// The look of a [GlassSearchField], like Flutter's `ButtonStyle`.
///
/// Every property but [focusColor], [hoverColor] and [builder] resolves
/// against the field's states (focused, pressed, hovered, disabled) and
/// falls through, state by state, from this style to the theme's to the
/// field's defaults: a null for a state leaves that state to the next one.
@immutable
class GlassSearchFieldStyle extends GlassStyle<GlassSearchFieldStyle> {
  /// Creates a style.
  const GlassSearchFieldStyle({
    this.backgroundColor,
    this.foregroundColor,
    this.placeholderColor,
    this.iconColor,
    this.cursorColor,
    this.textStyle,
    this.focusColor,
    this.hoverColor,
    this.builder,
  });

  /// The theme's [GlassSearchFieldStyle] at [context], or null without one:
  /// the look between a widget's own style and its defaults.
  static GlassSearchFieldStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassSearchFieldStyle>(context);

  /// A tint over the field's glass, or, disabled, the plain fill that
  /// replaces it; [GlassSearchField.disabledFill] when disabled and no tint
  /// otherwise, by default.
  final WidgetStateProperty<Color?>? backgroundColor;

  /// The color of the text; [GlassColors.label] by default.
  final WidgetStateProperty<Color?>? foregroundColor;

  /// The color of the placeholder; [GlassSearchField.placeholderColors]
  /// by default.
  final WidgetStateProperty<Color?>? placeholderColor;

  /// The color of the magnifier and of the clear button's disc;
  /// [GlassColors.label] by default.
  final WidgetStateProperty<Color?>? iconColor;

  /// The color of the text cursor; by default bluer than the accent (an
  /// iPhone 16 Pro's screen: 66, 106, 243 light and 64, 107, 248 dark).
  final WidgetStateProperty<Color?>? cursorColor;

  /// The text style of the text and the placeholder: 17 points, medium,
  /// by default.
  final WidgetStateProperty<TextStyle?>? textStyle;

  /// The ring around the clear button focused from the keyboard; null
  /// derives it from systemBlue as Flutter's Cupertino controls do, and a
  /// transparent color draws none. The field itself shows its focus by its
  /// cursor.
  final Color? focusColor;

  /// What a mouse over the field adds to its glass, and over the clear
  /// button to its disc; null for a pressed glass's wash at half strength,
  /// and a transparent color shows none.
  final Color? hoverColor;

  /// Builds the field in place of its default look, which then ignores the
  /// other fields. Null leaves it to the theme's builder, then the default
  /// look.
  final GlassSearchFieldBuilder? builder;

  /// This style over [other], state by state.
  @override
  GlassSearchFieldStyle merge(GlassSearchFieldStyle? other) {
    if (other == null) return this;
    return GlassSearchFieldStyle(
      backgroundColor: GlassStyle.mergeStates(
        backgroundColor,
        other.backgroundColor,
      ),
      foregroundColor: GlassStyle.mergeStates(
        foregroundColor,
        other.foregroundColor,
      ),
      placeholderColor: GlassStyle.mergeStates(
        placeholderColor,
        other.placeholderColor,
      ),
      iconColor: GlassStyle.mergeStates(iconColor, other.iconColor),
      cursorColor: GlassStyle.mergeStates(cursorColor, other.cursorColor),
      textStyle: GlassStyle.mergeStates(textStyle, other.textStyle),
      focusColor: focusColor ?? other.focusColor,
      hoverColor: hoverColor ?? other.hoverColor,
      builder: builder ?? other.builder,
    );
  }

  /// The style between this one and [other] at [t]; the builder switches
  /// at the half.
  @override
  GlassSearchFieldStyle lerp(GlassSearchFieldStyle other, double t) {
    if (identical(this, other)) return this;
    final color = GlassStyle.lerpStateColors(t);
    return GlassSearchFieldStyle(
      backgroundColor: color(backgroundColor, other.backgroundColor),
      foregroundColor: color(foregroundColor, other.foregroundColor),
      placeholderColor: color(placeholderColor, other.placeholderColor),
      iconColor: color(iconColor, other.iconColor),
      cursorColor: color(cursorColor, other.cursorColor),
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
      other is GlassSearchFieldStyle &&
      other.backgroundColor == backgroundColor &&
      other.foregroundColor == foregroundColor &&
      other.placeholderColor == placeholderColor &&
      other.iconColor == iconColor &&
      other.cursorColor == cursorColor &&
      other.textStyle == textStyle &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.builder == builder;

  @override
  int get hashCode => Object.hash(
    backgroundColor,
    foregroundColor,
    placeholderColor,
    iconColor,
    cursorColor,
    textStyle,
    focusColor,
    hoverColor,
    builder,
  );
}

/// An iOS 27 search field: a glass capsule with a magnifier, the query and
/// a clear button.
///
/// UIKit: `UISearchTextField`. SwiftUI: the field of `searchable`. Flutter:
/// `CupertinoSearchTextField`.
///
/// Read the query from [onChanged] and [onSubmitted], or from a
/// [controller] the app owns; [placeholder] replaces the localized
/// "Search". [enabled] false disables the field. It stands anywhere a text
/// field does, or under a navigation bar's large title as
/// `GlassNavigationBar.searchField`.
///
/// ```dart
/// GlassSearchField(
///   placeholder: const Text('Search plants'),
///   onChanged: (query) => setState(() => filter = query),
/// )
/// ```
///
/// The capsule is a [GlassSurface]: liquid glass on the liquid renderer,
/// blurred and lit glass on the fake renderer, and a translucent fill with
/// a hairline rim and a soft shadow on the flat renderer, which also draws
/// when no `GlassScope` is above.
///
/// The field is 48 points tall and shows the clear button while it holds
/// text; its lift and input are [RawGlassSearchField]'s. Disabled, the
/// field drops its glass for a plain fill on every renderer and keeps its
/// magnifier and placeholder.
///
/// Fidelity. The disabled look matches UIKit's on an iPhone 16 Pro with
/// iOS 27.0.1.
class GlassSearchField extends StatelessWidget {
  /// Creates a search field.
  const GlassSearchField({
    this.controller,
    this.focusNode,
    this.placeholder,
    this.onChanged,
    this.onSubmitted,
    this.enabled = true,
    this.autofocus = false,
    this.style,
    this.semanticLabel,
    this.clearSemanticLabel,
    this.statesController,
    super.key,
  });

  /// The text, or null for the field's own.
  final TextEditingController? controller;

  /// The field's focus node, or null for its own.
  final FocusNode? focusNode;

  /// What the empty field shows; the localized "Search" when null.
  final Widget? placeholder;

  /// Called with the text as the user edits it or clears it.
  final ValueChanged<String>? onChanged;

  /// Called with the text when the user submits it from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Whether the field takes input.
  final bool enabled;

  /// Whether the field takes focus when it first appears.
  final bool autofocus;

  /// The look, over the theme's and the field's defaults.
  final GlassSearchFieldStyle? style;

  /// What accessibility reads for the field; the localized "Search" when
  /// null.
  final String? semanticLabel;

  /// What accessibility reads for the clear button; the localized "Clear
  /// text" when null.
  final String? clearSemanticLabel;

  /// The field's states, or null for its own: the field writes focused,
  /// pressed, hovered and disabled to it.
  final WidgetStatesController? statesController;

  /// The space between the field's leading edge and the magnifier (iPhone
  /// 16 Pro screen).
  static const double glyphInset = 12;

  /// The space between the field's leading edge and its text (iPhone 16 Pro
  /// screen).
  static const double textInset = 40.67;

  /// The plain fill of a disabled field: 0x767680 at 6 percent in light
  /// and 12 percent in dark (iPhone 16 Pro, iOS 27.0.1).
  static const disabledFill = GlassDynamicColor.withBrightness(
    color: Color(0x0F767680),
    darkColor: Color(0x1F767680),
  );

  /// The placeholder: secondaryLabel while the field has the focus, and
  /// lighter on the glass without it (an iPhone 16 Pro's screen: 149 on
  /// 252 light, 110 on 32 dark, where the focused placeholder reads 133 and
  /// 142).
  static final WidgetStateProperty<Color?> placeholderColors =
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused)
            ? const GlassDynamicColor.withBrightness(
                color: Color(0x993C3C43),
                darkColor: Color(0x8AEBEBF5),
              )
            : const GlassDynamicColor.withBrightness(
                color: Color(0x69000000),
                darkColor: Color(0x59FFFFFF),
              ),
      );

  static const _cursor = GlassDynamicColor.withBrightness(
    color: Color(0xFF426AF3),
    darkColor: Color(0xFF406BF8),
  );

  static const _text = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w500,
    height: 1.2,
  );

  @override
  Widget build(BuildContext context) {
    final look = (style ?? const GlassSearchFieldStyle()).merge(
      GlassSearchFieldStyle.maybeOf(context),
    );
    return RawGlassSearchField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      enabled: enabled,
      autofocus: autofocus,
      semanticLabel: semanticLabel,
      statesController: statesController,
      builder:
          look.builder ??
          (context, details) => _SearchFieldLook(
            details: details,
            style: look.merge(_defaults(context)),
            placeholder: placeholder,
            clearSemanticLabel: clearSemanticLabel,
          ),
    );
  }

  static GlassSearchFieldStyle _defaults(BuildContext context) {
    final label = GlassTheme.labelColorOf(context);
    return GlassSearchFieldStyle(
      backgroundColor: const WidgetStateMapper<Color?>({
        WidgetState.disabled: GlassSearchField.disabledFill,
        WidgetState.any: null,
      }),
      foregroundColor: WidgetStatePropertyAll(label),
      placeholderColor: GlassSearchField.placeholderColors,
      iconColor: WidgetStatePropertyAll(label),
      cursorColor: const WidgetStatePropertyAll(GlassSearchField._cursor),
      textStyle: const WidgetStatePropertyAll(GlassSearchField._text),
    );
  }
}

class _SearchFieldLook extends StatefulWidget {
  const _SearchFieldLook({
    required this.details,
    required this.style,
    required this.placeholder,
    required this.clearSemanticLabel,
  });

  final GlassSearchFieldDetails details;
  final GlassSearchFieldStyle style;
  final Widget? placeholder;
  final String? clearSemanticLabel;

  @override
  State<_SearchFieldLook> createState() => _SearchFieldLookState();
}

class _SearchFieldLookState extends State<_SearchFieldLook> {
  late final List<Interaction> _clearInteractions = [
    PressInteraction(onTap: (t) => widget.details.clear?.call()),
  ];
  final _clearStates = WidgetStatesController();
  MotionSelection<GlassFrame>? _scaledBy;
  late MotionSelection<double> _scaleX;
  late MotionSelection<double> _scaleY;

  void _scaleOf(MotionSelection<GlassFrame> frame) {
    if (identical(frame, _scaledBy)) return;
    _scaledBy = frame;
    _scaleX = MotionSelection(() => frame.value.scaleX);
    _scaleY = MotionSelection(() => frame.value.scaleY);
  }

  @override
  void dispose() {
    _clearStates.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final details = widget.details;
    final look = widget.style;
    final states = details.states;
    final controller = details.controller;
    final color = StateColors(context, states);
    final background = look.backgroundColor?.resolve(states);
    final icon = color(look.iconColor);
    final placeholderColor = color(look.placeholderColor);
    final scale = GlassTextScale.of(
      context,
      max: RawGlassSearchField.maxTextScale,
    );
    final text = scale.resolve(
      look.textStyle!
          .resolve(states)!
          .copyWith(
            color: color(look.foregroundColor),
          ),
    );
    final placeholder = ListenableBuilder(
      listenable: controller,
      builder: (context, _) => controller.text.isEmpty
          ? ExcludeSemantics(
              child: DefaultTextStyle(
                style: text.copyWith(color: placeholderColor),
                maxLines: 1,
                softWrap: false,
                child: scale.apply(
                  widget.placeholder ??
                      Text(GlassLocalizations.of(context).searchLabel),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
    final clear = Padding(
      padding: const EdgeInsetsDirectional.only(
        start: 8,
        end: _clearInset,
      ),
      // The target reaches past the glyph only inside its parents' boxes.
      child: SizedBox(
        height: glassMinimumTargetExtent,
        child: Center(
          child: InputRegion(
            interactions: _clearInteractions,
            enabled: details.clear != null,
            statesController: _clearStates,
            reach: glassTargetReach,
            semantics: SemanticsProperties(
              label:
                  widget.clearSemanticLabel ??
                  GlassLocalizations.of(context).clearTextLabel,
              button: true,
            ),
            child: ExcludeSemantics(
              child: SizedBox.square(
                dimension: _clearSize,
                child: Padding(
                  padding: const EdgeInsets.all(
                    (_clearSize - GlassCloseIcon.ink) / 2,
                  ),
                  child: GlassHighlightPaint.of(
                    context,
                    states: _clearStates,
                    focusColor: look.focusColor,
                    hoverColor: look.hoverColor,
                    shape: const LiquidOval(),
                    wash: true,
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _ClearPainter(
                        fill: icon,
                        cross: GlassDynamicColor.resolve(
                          const GlassDynamicColor.withBrightness(
                            color: Color(0xFFFFFFFF),
                            darkColor: Color(0xFF000000),
                          ),
                          context,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final content = Padding(
      padding: const EdgeInsetsDirectional.only(
        start: GlassSearchField.glyphInset,
      ),
      child: Row(
        children: [
          GlassSearchIcon(color: icon),
          SizedBox(
            width:
                GlassSearchField.textInset -
                GlassSearchField.glyphInset -
                GlassSearchIcon.defaultSize.width,
          ),
          Expanded(
            child: Stack(
              alignment: AlignmentDirectional.centerStart,
              children: [
                placeholder,
                details.text(
                  style: text,
                  cursorColor: color(look.cursorColor),
                  backgroundCursorColor: placeholderColor,
                ),
              ],
            ),
          ),
          ListenableBuilder(
            listenable: controller,
            builder: (context, child) => controller.text.isEmpty
                ? const SizedBox(width: _clearInset)
                : child!,
            child: clear,
          ),
        ],
      ),
    );
    final glass = Glass.regular(tint: background);
    if (states.contains(WidgetState.disabled)) {
      return GlassSurface(role: GlassRole.track, glass: glass, child: content);
    }
    if (GlassSearchFieldHost.maybeOf(context)?.glass == null) {
      return GlassSurface.live(
        frame: details.frame,
        glass: glass,
        states: details.statesListenable,
        focusColor: GlassHighlights.noRing,
        hoverColor: look.hoverColor,
        child: content,
      );
    }
    _scaleOf(details.frame);
    // A surface fades its content with its glass, and a stacked field's
    // glyph and text stay while its glass comes and goes.
    return Stack(
      fit: StackFit.expand,
      children: [
        GlassSurface.live(
          frame: details.frame,
          glass: glass,
          states: details.statesListenable,
          focusColor: GlassHighlights.noRing,
          hoverColor: look.hoverColor,
          child: const SizedBox.expand(),
        ),
        MotionTransition(scaleX: _scaleX, scaleY: _scaleY, child: content),
      ],
    );
  }
}

class _ClearPainter extends CustomPainter {
  const _ClearPainter({required this.fill, required this.cross});

  final Color fill;
  final Color cross;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2;
    final disc = Paint();
    disc.color = fill;
    canvas.drawCircle(c, r, disc);
    final x = Paint();
    x.color = cross;
    x.style = PaintingStyle.stroke;
    x.strokeWidth = r * 0.2;
    x.strokeCap = StrokeCap.round;
    final d = r * 0.36;
    canvas.drawLine(c + Offset(-d, -d), c + Offset(d, d), x);
    canvas.drawLine(c + Offset(d, -d), c + Offset(-d, d), x);
  }

  @override
  bool shouldRepaint(_ClearPainter oldDelegate) =>
      oldDelegate.fill != fill || oldDelegate.cross != cross;
}
