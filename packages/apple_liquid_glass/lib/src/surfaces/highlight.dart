import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/surfaces/follow.dart';
import 'package:apple_liquid_glass/src/surfaces/renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// The one rule by which every interactive part shows the keyboard focus
/// and the pointer over it: a glass body through its renderer, a part that
/// is not glass (a list row, a page control's platter, a clear button)
/// through the same painter ([GlassHighlight.paint], in the colors of a
/// [GlassHighlightLook]).
///
/// The focus ring is Flutter's Cupertino one (`cupertino_ui` 1.1.4,
/// `CupertinoButton`'s focus outline in `lib/src/button.dart` and
/// `CupertinoFocusHalo` in `lib/src/cupertino_focus_halo.dart`, constants
/// in `lib/src/constants.dart`): a 3.5 point stroke outside the body's
/// shape in the body's color at 0.8 opacity with its lightness and
/// saturation set to 0.69 and 0.835; the color of an untinted body, or of
/// one without a hue (white, a gray, which Cupertino's rule turns red), is
/// derived from systemBlue, as Cupertino's from `activeBlue`. It is an
/// approximation of the platform pending a measurement. Under Increase
/// Contrast the ring is opaque and its base color takes its increased
/// contrast value: an approximation, not measured.
///
/// The hover response is a pressed body's wash at [hoverGain] of its
/// strength: the touch glow's wash offset added to every color channel
/// ([hoverColor]), eased in and out on the spring a press's glow fades on,
/// with no scale, lift or spot. It also lifts the content by the same
/// amount, where a press's wash lies under it. A part that is not glass
/// fills with [hoverGain] of its pressed fill instead. Both are
/// approximations, not measured on macOS. Under Reduce Motion the response
/// switches without motion. Only a mouse reports hover, so touch shows
/// none.
abstract final class GlassHighlights {
  /// The share of its pressed response a hovered part shows.
  static const double hoverGain = 0.5;

  /// The ring color that draws no ring: a control whose focus shows by
  /// other means passes it as its focus color.
  @internal
  static const Color noRing = Color(0x00000000);

  /// The color added to a hovered glass body by default: white at
  /// [hoverGain] of the touch glow's wash offset.
  static const Color hoverColor = Color.from(
    alpha: TouchGlowMotion.washOffset * hoverGain,
    red: 1,
    green: 1,
    blue: 1,
  );
}

/// The colors a part shows the keyboard focus and the pointer over it in,
/// resolved at a context by the rule of [GlassHighlights], and whether its
/// hover moves.
@immutable
final class GlassHighlightLook {
  const GlassHighlightLook._(
    this.focusColor,
    this.hoverColor, {
    required this.reduceMotion,
  });

  /// The look at [context]: the ring in [focusColor], or else the ring
  /// Cupertino derives from [base] (systemBlue by default, and for a base
  /// without a hue), opaque under Increase Contrast; the hover adds
  /// [hoverColor], by default [GlassHighlights.hoverColor]. Dynamic colors
  /// resolve at [context].
  factory GlassHighlightLook.of(
    BuildContext context, {
    Color? focusColor,
    Color? hoverColor,
    Color? base,
  }) {
    final traits = GlassTraits.of(context);
    return GlassHighlightLook._(
      _ringColor(focusColor, base, traits),
      GlassDynamicColor.resolveWith(
        hoverColor ?? GlassHighlights.hoverColor,
        traits,
      ),
      reduceMotion: traits.reduceMotion,
    );
  }

  /// The ring's color; a transparent one draws no ring.
  final Color focusColor;

  /// The color the hover adds over a glass body, or fills under a part
  /// that is not glass.
  final Color hoverColor;

  /// Whether the hover switches without motion.
  final bool reduceMotion;

  // `CupertinoButton`'s 3.5 point outside border (`cupertino_ui` 1.1.4,
  // `lib/src/button.dart:541`).
  static const double _ringWidth = 3.5;

  // `kCupertinoFocusColorOpacity` (`cupertino_ui` 1.1.4,
  // `lib/src/constants.dart:40`).
  static const double _ringOpacity = 0.8;

  // `kCupertinoFocusColorBrightness` (`lib/src/constants.dart:41`).
  static const double _ringLightness = 0.69;

  // `kCupertinoFocusColorSaturation` (`lib/src/constants.dart:42`).
  static const double _ringSaturation = 0.835;

  static const double _hueless = 0.05;

  static Color _ringColor(Color? given, Color? base, GlassTraits traits) {
    final Color color;
    if (given != null) {
      color = GlassDynamicColor.resolveWith(given, traits);
    } else {
      var tint = GlassDynamicColor.resolveWith(
        base ?? GlassColors.systemBlue,
        traits,
      );
      if (HSLColor.fromColor(tint).saturation < _hueless) {
        tint = GlassDynamicColor.resolveWith(GlassColors.systemBlue, traits);
      }
      color = HSLColor.fromColor(tint.withValues(alpha: _ringOpacity))
          .withLightness(_ringLightness)
          .withSaturation(_ringSaturation)
          .toColor();
    }
    return traits.highContrast && color.a > 0
        ? color.withValues(alpha: 1)
        : color;
  }

  @override
  bool operator ==(Object other) =>
      other is GlassHighlightLook &&
      other.focusColor == focusColor &&
      other.hoverColor == hoverColor &&
      other.reduceMotion == reduceMotion;

  @override
  int get hashCode => Object.hash(focusColor, hoverColor, reduceMotion);
}

/// Whether an interactive part shows the keyboard focus and how strongly it
/// shows the pointer over it, from its states, and how it paints both: the
/// hover strength eases on [PresenceMotion.hover].
///
/// A listener hears every change of either and of the [look], the hover
/// strength also in the frame's resolve phase; while nobody listens it
/// follows nothing.
final class GlassHighlight implements Listenable {
  /// Follows [states], or else the states [held], in [look].
  GlassHighlight({
    required GlassHighlightLook look,
    this._states,
    this._held = const {},
  }) : _look = look {
    _hover.traits = MotionTraits(reduceMotion: look.reduceMotion);
  }

  ValueListenable<Set<WidgetState>>? _states;

  /// The states of the part, or null for a part that shows neither.
  ValueListenable<Set<WidgetState>>? get states => _states;
  set states(ValueListenable<Set<WidgetState>>? value) {
    if (identical(value, _states)) return;
    if (_listeners.isNotEmpty) _states?.removeListener(_changed);
    _states = value;
    if (_listeners.isNotEmpty) {
      value?.addListener(_changed);
      _changed();
    }
  }

  Set<WidgetState> _held;

  /// The states of a part whose owner builds it again when they change,
  /// followed while [states] is null.
  Set<WidgetState> get held => _held;
  set held(Set<WidgetState> value) {
    if (setEquals(value, _held)) return;
    _held = value;
    if (_listeners.isNotEmpty && _states == null) _changed();
  }

  GlassHighlightLook _look;

  /// The colors the part shows its highlights in.
  GlassHighlightLook get look => _look;
  set look(GlassHighlightLook value) {
    if (value == _look) return;
    _look = value;
    _hover.traits = MotionTraits(reduceMotion: value.reduceMotion);
    _notify();
  }

  final _hover = PresenceMotion.hover();
  final _listeners = <VoidCallback>[];
  bool _focused = false;

  bool _has(WidgetState state) => (_states?.value ?? _held).contains(state);

  /// Whether the part shows the keyboard focus.
  bool get focused => _focused;

  /// How strongly the part shows the pointer over it, 0 to 1.
  double get hovered => _hover.presence.value.clamp(0.0, 1.0);

  @override
  void addListener(VoidCallback listener) {
    if (_listeners.isEmpty) {
      _states?.addListener(_changed);
      _focused = _has(WidgetState.focused);
      _hover.turn(
        _hover.clock.now,
        shown: _has(WidgetState.hovered),
        animated: false,
      );
    }
    _listeners.add(listener);
    _hover.presence.addRenderListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    _hover.presence.removeRenderListener(listener);
    if (_listeners.isEmpty) _states?.removeListener(_changed);
  }

  void _changed() {
    final focused = _has(WidgetState.focused);
    _hover.turn(_hover.clock.now, shown: _has(WidgetState.hovered));
    if (focused == _focused) return;
    _focused = focused;
    _notify();
  }

  void _notify() {
    for (final listener in List.of(_listeners)) {
      listener();
    }
  }

  /// Paints the part's highlights over a part of [shape] at [body]: the
  /// hover's wash, then the ring outside the part, or inside it when
  /// [inside]; an [outline] gives the part's edge in place of the shape.
  /// Both fade by [opacity]. Without [wash] the hover is the caller's, a
  /// fill under the part.
  void paint(
    Canvas canvas, {
    required LiquidShape shape,
    required Rect body,
    GlassOutline? outline,
    bool inside = false,
    bool wash = true,
    double opacity = 1,
  }) {
    final hovered = this.hovered * opacity;
    final hover = _look.hoverColor;
    if (wash && hovered > 0 && hover.a > 0) {
      final paint = Paint();
      paint.blendMode = BlendMode.plus;
      paint.color = hover.withValues(alpha: hover.a * hovered);
      canvas.drawPath(outline?.path ?? shape.getOuterPath(body), paint);
    }
    final ring = _look.focusColor;
    if (!_focused || ring.a <= 0 || opacity <= 0 || body.isEmpty) return;
    final paint = Paint();
    paint.color = ring.withValues(alpha: ring.a * opacity);
    const width = GlassHighlightLook._ringWidth;
    if (outline != null) {
      paint.style = PaintingStyle.stroke;
      paint.strokeWidth = width * 2;
      canvas.save();
      var clip = outline.path;
      if (!inside) {
        clip = Path();
        clip.fillType = PathFillType.evenOdd;
        clip.addRect(outline.bounds.inflate(width + 1));
        clip.addPath(outline.path, Offset.zero);
      }
      canvas.clipPath(clip);
      canvas.drawPath(outline.path, paint);
      canvas.restore();
      return;
    }
    final edge = shape.getOuterPath(body);
    final offset = _edgeGrownBy(shape, body, inside ? -width : width);
    final path = inside || offset == null ? edge : offset;
    if (offset != null) path.addPath(inside ? offset : edge, Offset.zero);
    path.fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  static Path? _edgeGrownBy(LiquidShape shape, Rect body, double by) {
    final box = body.inflate(by);
    if (box.isEmpty) return null;
    final drawn = glassCornerRadii(shape, body.size);
    double grown(double radius) => radius <= 0 ? 0 : math.max(0, radius + by);

    return switch (shape) {
      LiquidRoundedSuperellipse() => LiquidRoundedSuperellipse.vertical(
        top: grown(drawn.top),
        bottom: grown(drawn.bottom),
      ),
      LiquidRoundedRectangle() => LiquidRoundedRectangle(
        radius: grown(drawn.top),
      ),
      LiquidOval() => shape,
    }.getOuterPath(box);
  }
}

/// Draws the focus ring and hover response of the glass body [child] that
/// follows [frame]: the hover over the body, the ring outside it, both
/// where the frame draws the body and faded with it. Plain painting after
/// the body's own, so it reads nothing behind the glass.
@internal
class GlassHighlightBox extends SingleChildRenderObjectWidget {
  /// Draws the highlights of the body [child].
  const GlassHighlightBox({
    required this.frame,
    required this.states,
    required this.look,
    required super.child,
    super.key,
  });

  /// The body's frames.
  final ValueListenable<GlassFrame> frame;

  /// The body's states.
  final ValueListenable<Set<WidgetState>> states;

  /// The highlights' colors.
  final GlassHighlightLook look;

  /// Wraps [body] in the highlights [details] asks for, or returns it as
  /// it is when the surface reports no states.
  static Widget around(
    BuildContext context,
    GlassSurfaceDetails details,
    Widget body,
  ) {
    final states = details.states;
    if (states == null) return body;
    return GlassHighlightBox(
      frame: details.frame,
      states: states,
      look: GlassHighlightLook.of(
        context,
        focusColor: details.focusColor,
        hoverColor: details.hoverColor,
        base: details.glass.tint,
      ),
      child: body,
    );
  }

  @override
  RenderGlassHighlight createRenderObject(BuildContext context) =>
      RenderGlassHighlight(
        frame: frame,
        highlight: GlassHighlight(look: look, states: states),
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassHighlight renderObject,
  ) {
    renderObject.frame = frame;
    renderObject.highlight.states = states;
    renderObject.highlight.look = look;
  }
}

/// Paints a glass body's highlights over it; see [GlassHighlightBox].
@internal
class RenderGlassHighlight extends RenderProxyBox with ListenableFollower {
  /// Paints the highlights of a body that follows [frame].
  RenderGlassHighlight({required this._frame, required this.highlight});

  /// Whether the body shows focus and hover, and in what.
  final GlassHighlight highlight;

  ValueListenable<GlassFrame> _frame;

  /// The frames the body follows.
  ValueListenable<GlassFrame> get frame => _frame;
  set frame(ValueListenable<GlassFrame> value) {
    if (value == _frame) return;
    refollow(() => _frame = value);
    markNeedsPaint();
  }

  @override
  List<(Listenable, VoidCallback)> get followed => [
    (_frame, _framed),
    (highlight, markNeedsPaint),
  ];

  bool get _shows => highlight.focused || highlight.hovered > 0;

  void _framed() {
    if (_shows) markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!_shows) return;
    final frame = _frame.value;
    final opacity = frame.opacity.clamp(0.0, 1.0);
    if (opacity <= 0) return;
    final body = frame.bodyIn(size);
    final canvas = context.canvas;
    if (body.outline case final outline?) {
      canvas.save();
      canvas.translate(offset.dx, offset.dy);
      highlight.paint(
        canvas,
        shape: body.shape,
        body: body.drawnRect,
        outline: outline,
        opacity: opacity,
      );
      canvas.restore();
      return;
    }
    body.paintIn(
      canvas,
      offset,
      (canvas) => highlight.paint(
        canvas,
        shape: body.shape,
        body: body.bounds,
        opacity: opacity,
      ),
    );
  }
}

/// Draws the focus ring and hover response of a part that is not glass
/// (a list row, a page control, a clear button) by the rule of
/// [GlassHighlights]: the hover color fills the part's [shape] at the
/// hover's strength, under the part, or added over it as a glass body's
/// wash when [wash]; the ring follows the shape outside the part, or
/// inside it when [inside].
class GlassHighlightPaint extends SingleChildRenderObjectWidget {
  /// Draws the highlights of the part [child] in [look].
  const GlassHighlightPaint({
    required this.look,
    this.states,
    this.heldStates = const {},
    this.shape = LiquidRoundedSuperellipse.capsule,
    this.inside = false,
    this.wash = false,
    super.child,
    super.key,
  }) : assert(
         states == null || heldStates.length == 0,
         'Either the states or the held states.',
       );

  /// Draws the highlights of [child] in [GlassHighlightLook.of] the
  /// colors given and [base]. The part's states are [states], or
  /// [heldStates] when its owner builds it again as they change.
  static Widget of(
    BuildContext context, {
    required Widget child,
    ValueListenable<Set<WidgetState>>? states,
    Set<WidgetState> heldStates = const {},
    Color? focusColor,
    Color? hoverColor,
    Color? base,
    LiquidShape shape = LiquidRoundedSuperellipse.capsule,
    bool inside = false,
    bool wash = false,
  }) => GlassHighlightPaint(
    look: GlassHighlightLook.of(
      context,
      focusColor: focusColor,
      hoverColor: hoverColor,
      base: base,
    ),
    states: states,
    heldStates: heldStates,
    shape: shape,
    inside: inside,
    wash: wash,
    child: child,
  );

  /// The highlights' colors.
  final GlassHighlightLook look;

  /// The part's states, or null when [heldStates] are them.
  final ValueListenable<Set<WidgetState>>? states;

  /// The part's states when its owner builds it again as they change.
  final Set<WidgetState> heldStates;

  /// The part's shape in its box.
  final LiquidShape shape;

  /// Whether the ring lies inside the part, for a part clipped at its
  /// edge.
  final bool inside;

  /// Whether the hover adds to the part's colors over it, as a glass
  /// body's does, rather than filling under it.
  final bool wash;

  @override
  RenderGlassHighlightPaint createRenderObject(BuildContext context) =>
      RenderGlassHighlightPaint(
        highlight: GlassHighlight(
          look: look,
          states: states,
          held: heldStates,
        ),
        shape: shape,
        inside: inside,
        wash: wash,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    RenderGlassHighlightPaint renderObject,
  ) {
    renderObject.highlight.states = states;
    renderObject.highlight.held = heldStates;
    renderObject.highlight.look = look;
    renderObject.shape = shape;
    renderObject.inside = inside;
    renderObject.wash = wash;
  }
}

/// Paints the highlights of a part that is not glass; see
/// [GlassHighlightPaint].
@internal
class RenderGlassHighlightPaint extends RenderProxyBox with ListenableFollower {
  /// Paints the highlights a part's [highlight] shows.
  RenderGlassHighlightPaint({
    required this.highlight,
    required this._shape,
    required this._inside,
    required this._wash,
  });

  /// Whether the part shows focus and hover, and in what.
  final GlassHighlight highlight;

  LiquidShape _shape;

  /// The part's shape in its box.
  LiquidShape get shape => _shape;
  set shape(LiquidShape value) {
    if (value == _shape) return;
    _shape = value;
    markNeedsPaint();
  }

  bool _inside;

  /// Whether the ring lies inside the part.
  bool get inside => _inside;
  set inside(bool value) {
    if (value == _inside) return;
    _inside = value;
    markNeedsPaint();
  }

  bool _wash;

  /// Whether the hover adds to the part's colors over it.
  bool get wash => _wash;
  set wash(bool value) {
    if (value == _wash) return;
    _wash = value;
    markNeedsPaint();
  }

  @override
  List<(Listenable, VoidCallback)> get followed => [
    (highlight, markNeedsPaint),
  ];

  @override
  void paint(PaintingContext context, Offset offset) {
    final body = offset & size;
    final hovered = highlight.hovered;
    final hover = highlight.look.hoverColor;
    if (hovered > 0 && !_wash && hover.a > 0) {
      final paint = Paint();
      paint.color = hover.withValues(alpha: hover.a * hovered);
      context.canvas.drawPath(_shape.getOuterPath(body), paint);
    }
    super.paint(context, offset);
    highlight.paint(
      context.canvas,
      shape: _shape,
      body: body,
      inside: _inside,
      wash: _wash,
    );
  }
}
