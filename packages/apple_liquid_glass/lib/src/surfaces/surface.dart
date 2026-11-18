import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/src/surfaces/renderer.dart';
import 'package:apple_liquid_glass/src/surfaces/renderer_scope.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// A glass body behind [child], drawn by the ambient `GlassRenderer`.
///
/// UIKit: `UIVisualEffectView` with a `UIGlassEffect`. SwiftUI:
/// `.glassEffect(_:in:)`.
///
/// The child is drawn over the body and clipped to it. The same surface is
/// real glass, fake glass or flat depending on the renderer of the
/// enclosing [GlassRendererScope] (flat without one), so an app's own
/// panels follow its user's choice too; the child keeps its state when the
/// renderer changes.
class GlassSurface extends StatefulWidget {
  /// Creates a still body whose outline is `shape`, a capsule by default.
  const GlassSurface({
    required this.child,
    LiquidShape this._shape = LiquidRoundedSuperellipse.capsule,
    this.role = GlassRole.control,
    this.glass = const Glass.regular(),
    this.lens = const GlassLens(),
    this.states,
    this.focusColor,
    this.hoverColor,
    super.key,
  }) : frame = null,
       lensContent = null;

  /// Creates a body that follows [frame]: moved, scaled, lifted, tinted and
  /// lit frame by frame without a rebuild. Pass a selection of the motion
  /// that moves the body (`Motion.select`): the renderer hears it in the
  /// frame's publish phase, before build, or in its resolve phase after a
  /// layout commanded the motion, so the glass shows each step in the frame
  /// the motion takes it.
  const GlassSurface.live({
    required MotionSelection<GlassFrame> this.frame,
    required this.child,
    this.role = GlassRole.control,
    this.glass = const Glass.regular(),
    this.lens = const GlassLens(),
    this.states,
    this.focusColor,
    this.hoverColor,
    this.lensContent,
    super.key,
  }) : _shape = null;

  /// Creates a body that follows frames its owner writes in the frame's
  /// resolve phase: a bar writes its capsules' frames after its items are
  /// laid out, from what no selection can read.
  @internal
  const GlassSurface.written({
    required ValueListenable<GlassFrame> this.frame,
    required this.child,
    super.key,
  }) : _shape = null,
       role = GlassRole.control,
       glass = const Glass.regular(),
       lens = const GlassLens(),
       states = null,
       focusColor = null,
       hoverColor = null,
       lensContent = null;

  final LiquidShape? _shape;

  /// The frames of a live surface, or null for a still one.
  final ValueListenable<GlassFrame>? frame;

  /// The glass family of the surface.
  final GlassRole role;

  /// What a [GlassRole.lens] body asks of its glass; other roles ignore
  /// it.
  final GlassLens lens;

  /// The glass it is made of.
  final Glass glass;

  /// The content drawn over the body.
  final Widget child;

  /// The states of the control the body belongs to, or null for a body
  /// that shows neither the keyboard focus nor the pointer over it.
  ///
  /// The renderer follows them without rebuilding the surface: with
  /// [WidgetState.focused] it draws a focus ring around the body's shape,
  /// outside it and following its frame, and with [WidgetState.hovered] a
  /// hover response over the body. Pass the controller a control's
  /// `InputRegion` writes, which reports focus only while the keyboard
  /// focus should show and hover only from a mouse.
  final ValueListenable<Set<WidgetState>>? states;

  /// The color of the focus ring, or null for the renderer's; a
  /// transparent one draws none.
  final Color? focusColor;

  /// The color the hover response adds to the body, or null for the
  /// renderer's; a transparent one shows none.
  final Color? hoverColor;

  /// Where the renderer of a [GlassRole.lens] body reports how its lens
  /// shows the content drawn over it, or null; see
  /// [GlassSurfaceDetails.lensContent].
  final ValueNotifier<GlassLensContent?>? lensContent;

  @override
  State<GlassSurface> createState() => _GlassSurfaceState();
}

class _GlassSurfaceState extends State<GlassSurface> {
  final _child = GlobalKey(debugLabel: 'GlassSurface.child');

  Glass _resolved(BuildContext context) {
    final glass = widget.glass;
    final tint = glass.tint;
    if (tint is! GlassDynamicColor) return glass;
    final resolved = tint.resolveFrom(context);
    return glass.isClear
        ? Glass.clear(tint: resolved)
        : Glass.regular(tint: resolved);
  }

  @override
  Widget build(BuildContext context) {
    final frame =
        widget.frame ?? StillGlassFrame(GlassFrame(shape: widget._shape!));
    final body = GlassRendererScope.of(context).buildSurface(
      context,
      GlassSurfaceDetails(
        role: widget.role,
        lens: widget.lens,
        glass: _resolved(context),
        frame: frame,
        states: widget.states,
        focusColor: GlassDynamicColor.maybeResolve(widget.focusColor, context),
        hoverColor: GlassDynamicColor.maybeResolve(widget.hoverColor, context),
        lensContent: widget.lensContent,
        child: KeyedSubtree(key: _child, child: widget.child),
      ),
    );
    if (!GlassTraits.of(context).showBorders) return body;
    final label = GlassDynamicColor.resolve(
      GlassTheme.labelColorOf(context),
      context,
    );
    return CustomPaint(
      foregroundPainter: _Border(
        frame: frame,
        color: label.withValues(alpha: label.a * 0.35),
      ),
      child: body,
    );
  }
}

/// A frame that never changes.
@internal
@immutable
final class StillGlassFrame implements ValueListenable<GlassFrame> {
  /// Holds [value].
  const StillGlassFrame(this.value);

  @override
  final GlassFrame value;

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}

  @override
  bool operator ==(Object other) =>
      other is StillGlassFrame && other.value == value;

  @override
  int get hashCode => value.hashCode;
}

/// The hairline Show Borders draws around a glass body, where the frame
/// draws it, faded with it.
class _Border extends CustomPainter {
  _Border({required this.frame, required this.color}) : super(repaint: frame);

  final ValueListenable<GlassFrame> frame;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final now = frame.value;
    if (now.opacity <= 0) return;
    final paint = Paint();
    paint.style = PaintingStyle.stroke;
    paint.strokeWidth = 1;
    paint.color = color.withValues(
      alpha: color.a * now.opacity.clamp(0.0, 1.0),
    );
    final body = now.bodyIn(size);
    if (body.outline != null) {
      canvas.drawPath(body.edgeInBox, paint);
      return;
    }
    body.paintIn(
      canvas,
      Offset.zero,
      (canvas) => canvas.drawPath(
        body.shape.getOuterPath(body.bounds.deflate(0.5)),
        paint,
      ),
    );
  }

  @override
  bool shouldRepaint(_Border oldDelegate) =>
      oldDelegate.frame != frame || oldDelegate.color != color;
}
