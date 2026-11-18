import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/surfaces/follow.dart';
import 'package:apple_liquid_glass/src/surfaces/renderer.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// The flat renderer: a fill per role and glass, a hairline rim on all but
/// a track and a resting lens or knob, a soft shadow under floating roles;
/// no backdrop reads, no glow. A lens or knob is an opaque platter that
/// rests on the shadow its control gives it ([GlassLens.restingShadow]),
/// and fades and gains a rim as it lifts.
///
/// The fills, rims and shadows are an approximation of the glass's average
/// look, not a measurement. A track is a plain fill on every renderer;
/// untinted, it takes iOS systemFill, a default no control measured. A
/// color scheme's surfaces replace the fills per role.
///
/// A shadow is Impeller's analytic blur of the body's shape, clipped to the
/// outside of the body so a translucent body shows what is under it. NEAR:
/// at most 6 of 255 levels from a Gaussian blur of its path, 2 on average,
/// at 2.625 and 3 device pixels per point, and no offscreen passes. A body
/// with an outline blurs its path offscreen.
///
/// A body whose control is focused from the keyboard draws Flutter's
/// Cupertino focus ring outside its shape, and a hovered one a pressed
/// body's wash at half strength over it ([GlassSurfaceDetails.states]).
///
/// It is the renderer of glass with no `GlassRendererScope` above, and it
/// draws without liquid glass: no shader, no backdrop read.
final class FlatGlassRenderer extends GlassRenderer {
  /// Creates the flat renderer.
  const FlatGlassRenderer();

  @override
  Widget buildSurface(BuildContext context, GlassSurfaceDetails details) =>
      buildHighlights(context, details, flatSurface(context, details));

  /// The flat body of [details]; [underGlass] for a lens or knob whose
  /// liquid glass covers it while it is lifted.
  @internal
  static Widget flatSurface(
    BuildContext context,
    GlassSurfaceDetails details, {
    bool underGlass = false,
  }) => _FlatSurface(
    frame: details.frame,
    look: FlatGlassLook.of(
      details.role,
      details.glass,
      GlassTraits.of(context),
      scheme: GlassTheme.colorSchemeOf(context),
      lens: details.lens,
      underGlass: underGlass,
    ),
    child: details.child,
  );

  @override
  bool operator ==(Object other) => other is FlatGlassRenderer;

  @override
  int get hashCode => (FlatGlassRenderer).hashCode;
}

/// How the flat renderer paints one surface.
@internal
@immutable
final class FlatGlassLook {
  /// Creates a look.
  const FlatGlassLook({
    required this.fill,
    this.rim,
    this.shadow,
    this.restingShadow,
    this.liftRim,
    this.underGlass = false,
  });

  /// The look of a surface of [role] made of [glass] under [traits]: the
  /// glass's tint, else the [scheme]'s surface for the role, else the
  /// renderer's own fill. A lens rests on the shadow of its [lens].
  factory FlatGlassLook.of(
    GlassRole role,
    Glass glass,
    GlassTraits traits, {
    GlassColorScheme? scheme,
    GlassLens lens = const GlassLens(),
    bool underGlass = false,
  }) {
    final tint = glass.tint;
    final surface = scheme?.surfaces[role];
    switch (role) {
      case GlassRole.lens:
        return FlatGlassLook(
          fill: GlassDynamicColor.resolveWith(
            tint ?? surface ?? _platter,
            traits,
          ),
          restingShadow: lens.restingShadow,
          liftRim: GlassDynamicColor.resolveWith(_liftRim, traits),
          underGlass: underGlass,
        );
      case GlassRole.track:
        return FlatGlassLook(
          fill: GlassDynamicColor.resolveWith(
            tint ?? surface ?? GlassColors.systemFill,
            traits,
          ),
        );
      case GlassRole.control || GlassRole.panel || GlassRole.bar:
        final floating = role != GlassRole.bar;
        return FlatGlassLook(
          fill: GlassDynamicColor.resolveWith(
            tint ?? surface ?? (glass.isClear ? _clear : _fill),
            traits,
          ),
          rim: tint != null
              ? _tintedRim
              : GlassDynamicColor.resolveWith(_rim, traits),
          shadow: floating
              ? GlassDynamicColor.resolveWith(_shadow, traits)
              : null,
        );
    }
  }

  static const _fill = GlassDynamicColor.withBrightness(
    color: Color(0xD9FFFFFF),
    darkColor: Color(0xB82C2C2E),
  );
  static const _clear = GlassDynamicColor.withBrightness(
    color: Color(0x40FFFFFF),
    darkColor: Color(0x402C2C2E),
  );
  static const _rim = GlassDynamicColor.withBrightness(
    color: Color(0x1F000000),
    darkColor: Color(0x33FFFFFF),
  );
  static const _tintedRim = Color(0x33FFFFFF);
  static const _platter = Color(0xFFFFFFFF);
  static const _liftRim = GlassDynamicColor.withBrightness(
    color: Color(0x2E000000),
    darkColor: Color(0x47FFFFFF),
  );
  static const _shadow = GlassDynamicColor.withBrightness(
    color: Color(0x1A000000),
    darkColor: Color(0x40000000),
  );

  /// The fill of the body.
  final Color fill;

  /// The hairline along the outline, or null for none.
  final Color? rim;

  /// The color of the shadow under a body that does not lift, or null for
  /// none.
  final Color? shadow;

  /// The shadow under a lifting body at rest, or null for none. As the
  /// body lifts its shadow darkens by a tenth and spreads, from this one or
  /// from none.
  final BoxShadow? restingShadow;

  /// The rim of a fully lifted lens or knob, or null for a surface that
  /// does not lift.
  ///
  /// A lifting look fades its fill to a fifth of its opacity as the frame
  /// lifts ([liftedOpacity]), this rim fades in, and the shadow darkens and
  /// spreads. Not measured.
  final Color? liftRim;

  /// Whether liquid glass covers this lifting body while it is lifted: its
  /// fill and shadow then fade as the glass appears
  /// ([GlassFrame.glassnessAt]), and the glass draws the rim.
  final bool underGlass;

  /// The share of its opacity a lens's fill keeps at [lift]: all at rest, a
  /// fifth fully lifted.
  static double liftedOpacity(double lift) => 1 - 0.8 * lift.clamp(0.0, 1.0);

  @override
  bool operator ==(Object other) =>
      other is FlatGlassLook &&
      other.fill == fill &&
      other.rim == rim &&
      other.shadow == shadow &&
      other.restingShadow == restingShadow &&
      other.liftRim == liftRim &&
      other.underGlass == underGlass;

  @override
  int get hashCode =>
      Object.hash(fill, rim, shadow, restingShadow, liftRim, underGlass);
}

class _FlatSurface extends SingleChildRenderObjectWidget {
  const _FlatSurface({
    required this.frame,
    required this.look,
    required super.child,
  });

  final ValueListenable<GlassFrame> frame;
  final FlatGlassLook look;

  @override
  RenderFlatGlass createRenderObject(BuildContext context) =>
      RenderFlatGlass(frame: frame, look: look);

  @override
  void updateRenderObject(BuildContext context, RenderFlatGlass renderObject) {
    renderObject.frame = frame;
    renderObject.look = look;
  }
}

/// Paints a flat glass body under its child where the frame draws it.
@internal
class RenderFlatGlass extends RenderProxyBox with ListenableFollower {
  /// Creates a body that follows [frame].
  RenderFlatGlass({
    required this._frame,
    required this._look,
  });

  // The offset and blur sigma of the shadow under a body that does not
  // lift. Not measured.
  static const Offset _shadowOffset = Offset(0, 2);
  static const double _shadowSigma = 6;

  // The width of the rim, stroked just inside the outline.
  static const double _rimWidth = 0.5;

  ValueListenable<GlassFrame> _frame;

  /// The frames the body follows.
  ValueListenable<GlassFrame> get frame => _frame;
  set frame(ValueListenable<GlassFrame> value) {
    if (value == _frame) return;
    refollow(() => _frame = value);
    _framed();
  }

  @override
  List<(Listenable, VoidCallback)> get followed => [(_frame, _framed)];

  bool _fading = false;

  // A partly present body draws through an opacity layer of its own.
  void _framed() {
    final fading = _frame.value.opacity < 1;
    if (fading != _fading) {
      _fading = fading;
      markNeedsCompositingBitsUpdate();
    }
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _fading;

  FlatGlassLook _look;

  /// How the body is painted.
  FlatGlassLook get look => _look;
  set look(FlatGlassLook value) {
    if (value == _look) return;
    _look = value;
    markNeedsPaint();
  }

  final _clip = LayerHandle<ClipPathLayer>();
  final _transform = LayerHandle<TransformLayer>();
  final _opacity = LayerHandle<OpacityLayer>();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _fading = _frame.value.opacity < 1;
  }

  @override
  void dispose() {
    _clip.layer = null;
    _transform.layer = null;
    _opacity.layer = null;
    super.dispose();
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final content = _frame.value.bodyIn(size).childToBox;
    if (content != null) transform.multiply(content);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final opacity = _frame.value.opacity;
    if (opacity >= 1) {
      _opacity.layer = null;
      _paintSurface(context, offset);
      return;
    }
    if (opacity <= 0) {
      _opacity.layer = null;
      return;
    }
    _opacity.layer = context.pushOpacity(
      offset,
      (opacity * 255).round(),
      _paintSurface,
      oldLayer: _opacity.layer,
    );
  }

  void _paintSurface(PaintingContext context, Offset offset) {
    final frame = _frame.value;
    final body = frame.bodyIn(size);
    final tint = frame.tint;
    final color = tint == null
        ? _look.fill
        : Color.lerp(_look.fill, tint, frame.tintAmount.clamp(0.0, 1.0))!;
    final liftRim = _look.liftRim;
    body.paintIn(context.canvas, offset, (canvas) {
      if (liftRim != null) {
        _paintLifting(canvas, frame, body, color, liftRim);
      } else {
        _paintBody(canvas, body, color);
      }
    });
    final child = this.child;
    if (child == null) return;
    _clip.layer = context.pushClipPath(
      needsCompositing,
      offset,
      Offset.zero & size,
      body.edgeInBox,
      (context, offset) => _paintContent(context, offset, body),
      oldLayer: _clip.layer,
    );
  }

  void _paintLifting(
    Canvas canvas,
    GlassFrame frame,
    GlassBody body,
    Color color,
    Color liftRim,
  ) {
    final lift = frame.lift.clamp(0.0, 1.0);
    final shown = _look.underGlass ? 1 - GlassFrame.glassnessAt(lift) : 1.0;
    if (shown <= 0) return;
    final resting = _look.restingShadow;
    final darkness = ((resting?.color.a ?? 0) + 0.1 * lift) * shown;
    if (darkness > 0) {
      _drawShadow(
        canvas,
        body,
        (resting?.color ?? const Color(0xFF000000)).withValues(
          alpha: darkness,
        ),
        sigma: (resting?.blurSigma ?? 2) + 4 * lift,
        shift: resting?.offset ?? const Offset(0, 1.5),
      );
    }
    final fill = Paint();
    fill.color = color.withValues(
      alpha: color.a * FlatGlassLook.liftedOpacity(lift) * shown,
    );
    body.silhouette.fill(canvas, fill);
    if (_look.underGlass || lift <= 0.01) return;
    final rim = Paint();
    rim.style = PaintingStyle.stroke;
    rim.strokeWidth = 0.75;
    rim.color = liftRim.withValues(alpha: liftRim.a * lift);
    canvas.drawPath(_rimPath(body, 0.4), rim);
  }

  void _paintBody(Canvas canvas, GlassBody body, Color color) {
    if (_look.shadow case final shadow?) {
      _drawShadow(
        canvas,
        body,
        shadow,
        sigma: _shadowSigma,
        shift: _shadowOffset,
      );
    }
    final fill = Paint();
    fill.color = color;
    body.silhouette.fill(canvas, fill);
    if (_look.rim case final rim?) {
      final stroke = Paint();
      stroke.style = PaintingStyle.stroke;
      stroke.strokeWidth = _rimWidth;
      stroke.color = rim;
      canvas.drawPath(_rimPath(body, _rimWidth / 2), stroke);
    }
  }

  // A shadow takes the radius Flutter turns into this sigma
  // (Shadow.convertRadiusToSigma).
  static void _drawShadow(
    Canvas canvas,
    GlassBody body,
    Color color, {
    required double sigma,
    required Offset shift,
  }) => body.silhouette.paintShadows(canvas, [
    LiquidGlassShadow(
      color: color,
      offset: shift,
      blurRadius: (sigma - 0.5) / 0.57735,
    ),
  ]);

  // An outline body strokes its own edge: the rim is too thin for the
  // stroke's straddle of the edge to show.
  static Path _rimPath(GlassBody body, double inset) => body.outline != null
      ? body.edge
      : body.shape.getOuterPath(body.bounds.deflate(inset));

  void _paintContent(PaintingContext context, Offset offset, GlassBody body) {
    final transform = body.childToBox;
    if (transform == null) {
      _transform.layer = null;
      context.paintChild(child!, offset);
      return;
    }
    _transform.layer = context.pushTransform(
      needsCompositing,
      offset,
      transform,
      (context, offset) => context.paintChild(child!, offset),
      oldLayer: _transform.layer,
    );
  }
}
