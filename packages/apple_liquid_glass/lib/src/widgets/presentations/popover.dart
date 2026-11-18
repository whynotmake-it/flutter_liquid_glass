import 'dart:math' as math;

import 'package:apple_liquid_glass/foundation.dart';
import 'package:apple_liquid_glass/motions.dart';
import 'package:apple_liquid_glass/src/widgets/presentations/sheet.dart';
import 'package:apple_liquid_glass/surfaces.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/kinesis.dart';
import 'package:liquid_glass_renderer/painting.dart';

/// The corner radius of a popover's content, measured on an action sheet
/// presented from a source view on iOS 27.
@internal
const double popoverCornerRadius = 34;

/// The look of popovers; a null field leaves it to the theme's style,
/// then the default. A popover that adapts to a sheet draws in the
/// sheet's style with this style's text.
@immutable
class GlassPopoverStyle extends GlassStyle<GlassPopoverStyle> {
  /// Creates a style.
  const GlassPopoverStyle({this.textStyle});

  /// The theme's [GlassPopoverStyle] at [context], or null without one: the
  /// look between a widget's own style and its defaults.
  static GlassPopoverStyle? maybeOf(BuildContext context) =>
      GlassTheme.styleOf<GlassPopoverStyle>(context);

  /// The default text of the content, over 17 points in label.
  final TextStyle? textStyle;

  /// This style over [other].
  @override
  GlassPopoverStyle merge(GlassPopoverStyle? other) {
    if (other == null) return this;
    return GlassPopoverStyle(
      textStyle: other.textStyle?.merge(textStyle) ?? textStyle,
    );
  }

  /// The style between this one and [other] at [t].
  @override
  GlassPopoverStyle lerp(GlassPopoverStyle other, double t) {
    if (identical(this, other)) return this;
    return GlassPopoverStyle(
      textStyle: GlassStyle.lerpNullable(TextStyle.lerp)(
        textStyle,
        other.textStyle,
        t,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is GlassPopoverStyle && other.textStyle == textStyle;

  @override
  int get hashCode => textStyle.hashCode;
}

/// Shows [builder]'s content in an iOS 27 popover next to its source and
/// completes with the result it is closed with.
///
/// UIKit: a view controller presented with `.popover`. SwiftUI: `popover`.
/// Flutter: none.
///
/// The source is [anchor], a context inside the widget the popover points
/// at, which must be laid out, or [anchorRect] in global coordinates. The
/// content sizes itself up to the screen less 10 points a side; the
/// popover places it above, below, after or before the source as UIKit
/// does and joins an arrow to it, glass and arrow one body. It grows out
/// of the arrow's tip on UIKit's spring of response 0.345 and shrinks back
/// into it on one of 0.373 (read from UIKit, replayed on the iPhone 16
/// Pro); under Reduce Motion it only fades. A tap outside, Escape, Back
/// (Android's predictive back shrinking it with the gesture) and a screen
/// reader's dismiss close it, and so does a scroll of what it was shown
/// from. Screen readers hear a dialog, named by [semanticLabel] when given,
/// and find the dimming as [GlassLocalizations.popoverDismissLabel].
///
/// On a phone (a screen whose shorter side is under 600 points, an
/// engineering stand-in for UIKit's compact width) the popover presents as
/// a sheet at its large detent, as UIKit adapts one, unless
/// [adaptsToSheet] is false.
Future<T?> showGlassPopover<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  BuildContext? anchor,
  Rect? anchorRect,
  bool adaptsToSheet = true,
  GlassPopoverStyle? style,
  String? semanticLabel,
  PresentationLevel level = PresentationLevel.window,
}) {
  if (adaptsToSheet && MediaQuery.sizeOf(context).shortestSide < 600) {
    final look = (style ?? const GlassPopoverStyle()).merge(
      GlassPopoverStyle.maybeOf(context),
    );
    return showGlassSheet<T>(
      context,
      builder: builder,
      style: GlassSheetStyle(textStyle: look.textStyle),
      semanticLabel: semanticLabel,
      level: level,
    );
  }
  final source = popoverSource(
    anchor: anchor,
    anchorRect: anchorRect,
    caller: 'showGlassPopover',
  );
  return showPresentation(
    context,
    PresentationRoute(
      presentation: Presentation<T, PopoverMotion>(
        motion: (_) => PopoverMotion(),
        builder: (context, motion) => _PopoverView(
          motion: motion,
          source: source,
          style: style,
          builder: builder,
        ),
        semanticsLabel: semanticLabel,
        semanticsRole: SemanticsRole.dialog,
        barrierLabel: GlassLocalizations.of(context).popoverDismissLabel,
        dismissesOnScroll: true,
        dismissesOnOutsideTap: true,
      ),
    ),
    level: level,
  );
}

/// The rect in global coordinates of [anchor], or [anchorRect] when given.
@internal
Rect popoverSource({
  required BuildContext? anchor,
  required Rect? anchorRect,
  required String caller,
}) {
  if (anchorRect != null) return anchorRect;
  if (anchor == null) {
    throw FlutterError('$caller needs an anchor or an anchorRect.');
  }
  if (!anchor.mounted) {
    throw FlutterError('The anchor of $caller is no longer mounted.');
  }
  final box = anchor.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) {
    throw FlutterError('The anchor of $caller must be laid out.');
  }
  return MatrixUtils.transformRect(
    box.getTransformTo(null),
    Offset.zero & box.size,
  );
}

class _PopoverView extends StatefulWidget {
  const _PopoverView({
    required this.motion,
    required this.source,
    required this.style,
    required this.builder,
  });

  final PopoverMotion motion;
  final Rect source;
  final GlassPopoverStyle? style;
  final WidgetBuilder builder;

  @override
  State<_PopoverView> createState() => _PopoverViewState();
}

class _PopoverViewState extends State<_PopoverView> {
  late final MotionSelection<double> _scale = widget.motion.select(
    (m) => m.scale,
  );
  late final MotionSelection<double> _opacity = widget.motion.select(
    (m) => m.opacity,
  );

  TextStyle _textStyle(Color label, BuildContext context) {
    final look = (widget.style ?? const GlassPopoverStyle()).merge(
      GlassPopoverStyle.maybeOf(context),
    );
    final text = TextStyle(fontSize: 17, color: label).merge(look.textStyle);
    return text.copyWith(
      color: GlassDynamicColor.resolve(text.color!, context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final label = GlassTheme.labelColorOf(context);
    return PopoverLayout(
      source: widget.source,
      scale: _scale,
      opacity: _opacity,
      maxWidth: media.size.width - 2 * PopoverMotion.margin,
      padding: media.paddingAboveKeyboard,
      direction: Directionality.of(context),
      card: MotionTransition(
        opacity: _opacity,
        child: ClipRSuperellipse(
          borderRadius: BorderRadius.circular(popoverCornerRadius),
          child: DefaultTextStyle(
            style: GlassTextScale.of(context)
                .resolve(_textStyle(label, context)),
            child: Builder(builder: widget.builder),
          ),
        ),
      ),
    );
  }
}

/// Lays out a popover: its card at its own size within [maxWidth], the
/// placement from it ([placePopover]) next to [source], and the glass at
/// the placement's shape; both paint scaled by [scale] about the arrow's
/// tip, and nothing paints or takes touches while [opacity] is 0.
@internal
class PopoverLayout extends MultiChildRenderObjectWidget {
  /// Creates the layout of a popover pointing at [source], in global
  /// coordinates.
  PopoverLayout({
    required this.source,
    required this.scale,
    required this.opacity,
    required this.maxWidth,
    required this.padding,
    required this.direction,
    required Widget card,
    super.key,
  }) : super(
         children: [
           LayoutBuilder(
             builder: (context, box) => _PopoverGlass(
               shape: (box as _PopoverConstraints).shape,
               opacity: opacity,
             ),
           ),
           card,
         ],
       );

  /// The rect the popover points at, in global coordinates.
  final Rect source;

  /// The popover's scale about its arrow's tip.
  final ValueListenable<double> scale;

  /// The opacity the popover's glass paints at; at 0 the popover neither
  /// paints nor takes touches.
  final MotionSelection<double> opacity;

  /// The widest the card may be.
  final double maxWidth;

  /// The insets the popover stays inside: the safe area and the keyboard.
  final EdgeInsets padding;

  /// The direction that orders the sides the popover tries.
  final TextDirection direction;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderPopover(
    source: source,
    scale: scale,
    opacity: opacity,
    maxWidth: maxWidth,
    padding: padding,
    direction: direction,
  );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderPopover).update(
      source: source,
      maxWidth: maxWidth,
      padding: padding,
      direction: direction,
    );
  }
}

/// The glass of a popover: its content box and arrow as one outline.
class _PopoverGlass extends StatefulWidget {
  const _PopoverGlass({required this.shape, required this.opacity});

  final PopoverShape shape;
  final MotionSelection<double> opacity;

  @override
  State<_PopoverGlass> createState() => _PopoverGlassState();
}

class _PopoverGlassState extends State<_PopoverGlass> {
  late MotionSelection<GlassFrame> _frame = _frameNow();

  @override
  void didUpdateWidget(_PopoverGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    // A selection hears only the motions it reads, never a new shape: a new
    // selection is what makes the glass take the shape in this frame. The
    // old one, which the glass stops following, tracks nothing and needs no
    // dispose.
    if (oldWidget.shape != widget.shape) {
      _frame = _frameNow();
    }
  }

  MotionSelection<GlassFrame> _frameNow() {
    final opacity = widget.opacity;
    final outline = widget.shape.outline;
    return MotionSelection(
      () => GlassFrame(
        shape: const LiquidRoundedSuperellipse(
          radius: popoverCornerRadius,
        ),
        opacity: opacity.value,
        outline: outline,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => GlassSurface.live(
    role: GlassRole.panel,
    frame: _frame,
    child: const SizedBox.expand(),
  );
}

class _PopoverConstraints extends BoxConstraints {
  _PopoverConstraints(this.shape) : super.tight(shape.bounds.size);

  final PopoverShape shape;

  @override
  bool operator ==(Object other) =>
      other is _PopoverConstraints &&
      other.shape.content == shape.content &&
      other.shape.direction == shape.direction &&
      other.shape.arrowCenter == shape.arrowCenter;

  @override
  int get hashCode =>
      Object.hash(shape.content, shape.direction, shape.arrowCenter);
}

class _PopoverParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderPopover extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _PopoverParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _PopoverParentData>,
        MotionResolveHost {
  _RenderPopover({
    required this._source,
    required this.scale,
    required this.opacity,
    required this._maxWidth,
    required this._padding,
    required this._direction,
  });

  // The view's own selections, which live as long as the view.
  final ValueListenable<double> scale;
  final ValueListenable<double> opacity;

  Rect _source;
  double _maxWidth;
  EdgeInsets _padding;
  TextDirection _direction;

  void update({
    required Rect source,
    required double maxWidth,
    required EdgeInsets padding,
    required TextDirection direction,
  }) {
    if (source == _source &&
        maxWidth == _maxWidth &&
        padding == _padding &&
        direction == _direction) {
      return;
    }
    _source = source;
    _maxWidth = maxWidth;
    _padding = padding;
    _direction = direction;
    markNeedsLayout();
  }

  PopoverPlacement? _placement;

  // Where the frame's resolve phase found the popover's box, which layout
  // places the popover by: no box's position can be read during layout.
  Offset _seen = Offset.zero;
  Offset _laidOutAt = Offset.zero;
  final _glassLayer = LayerHandle<TransformLayer>();
  final _cardLayer = LayerHandle<TransformLayer>();

  RenderBox get _glass => firstChild!;
  RenderBox get _card => lastChild!;

  bool get _shown => opacity.value > 0 && _placement != null;

  // Every frame of the motion repaints the popover alone.
  @override
  bool get isRepaintBoundary => true;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _PopoverParentData) {
      child.parentData = _PopoverParentData();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    scale.addListener(markNeedsPaint);
    opacity.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    scale.removeListener(markNeedsPaint);
    opacity.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _glassLayer.layer = null;
    _cardLayer.layer = null;
    super.dispose();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    _card.layout(
      BoxConstraints(
        maxWidth: math.max(0, _maxWidth),
        maxHeight: math.max(0, size.height - _padding.vertical),
      ),
      parentUsesSize: true,
    );
    _laidOutAt = _seen;
    final placement = _placement = placePopover(
      size: _card.size,
      source: _source.shift(-_laidOutAt),
      screen: size,
      padding: _padding,
      textDirection: _direction,
    );
    final bounds = placement.bounds;
    final vertical =
        placement.arrowDirection == PopoverArrowDirection.down ||
        placement.arrowDirection == PopoverArrowDirection.up;
    _glass.layout(
      _PopoverConstraints(
        PopoverShape(
          content: placement.content.shift(-bounds.topLeft),
          direction: placement.arrowDirection,
          arrowCenter:
              placement.arrowCenter - (vertical ? bounds.left : bounds.top),
          cornerRadius: popoverCornerRadius,
        ),
      ),
    );
  }

  Matrix4 _around(Offset at) {
    final anchor = _placement!.anchor;
    final s = scale.value;
    final m = Matrix4.translationValues(anchor.dx, anchor.dy, 0);
    m.multiply(Matrix4.diagonal3Values(s, s, 1));
    m.multiply(
      Matrix4.translationValues(at.dx - anchor.dx, at.dy - anchor.dy, 0),
    );
    return m;
  }

  Matrix4 _transformOf(RenderBox child) => _around(
    identical(child, _glass)
        ? _placement!.bounds.topLeft
        : _placement!.content.topLeft,
  );

  // The box can move without laying the popover out: an overlay moved, a
  // nested navigator's page sliding.
  @override
  bool get resolvesEveryFrame => true;

  // Laid out for another position of its box, the popover lays out again
  // in the same frame, before it paints.
  @override
  void resolve() {
    final seen = localToGlobal(Offset.zero);
    if (seen == _laidOutAt) return;
    _seen = seen;
    markNeedsLayout();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (!_shown) {
      _glassLayer.layer = null;
      _cardLayer.layer = null;
      return;
    }
    _glassLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _transformOf(_glass),
      (context, offset) => context.paintChild(_glass, offset),
      oldLayer: _glassLayer.layer,
    );
    _cardLayer.layer = context.pushTransform(
      needsCompositing,
      offset,
      _transformOf(_card),
      (context, offset) => context.paintChild(_card, offset),
      oldLayer: _cardLayer.layer,
    );
  }

  // The popover takes taps across its frame, the arrow's strip included,
  // as UIKit's popover view does; the card takes its own first.
  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (!_shown) return false;
    final hit = result.addWithPaintTransform(
      transform: _transformOf(_card),
      position: position,
      hitTest: (result, position) => _card.hitTest(result, position: position),
    );
    if (hit) return true;
    final toGlass = Matrix4.tryInvert(_transformOf(_glass));
    if (toGlass == null) return false;
    return (Offset.zero & _glass.size).contains(
      MatrixUtils.transformPoint(toGlass, position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (_placement == null) return;
    transform.multiply(_transformOf(child));
  }
}
