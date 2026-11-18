part of 'navigation_bar.dart';

/// A search field stacked under the navigation bar's titles: folded away
/// by the content's scroll, presented under the status bar while focused,
/// ended by its close button.
class _StackedSearch extends StatefulWidget {
  const _StackedSearch({
    required this.field,
    required this.offset,
    required this.travel,
    required this.lift,
    required this.fade,
  });

  final Widget field;

  // How far the content has scrolled from its start.
  final MotionSelection<double> offset;

  // How far the field rises to sit under the status bar.
  final double travel;

  // The page's lift, which this search writes.
  final ValueNotifier<double>? lift;

  // The navigation bar's fade, which this search drives.
  final MotionValue<double> fade;

  @override
  State<_StackedSearch> createState() => _StackedSearchState();
}

class _StackedSearchState extends State<_StackedSearch> with SearchLaw {
  late final MotionClock _clock;
  late final _motion = StackedSearchMotion(
    barFade: widget.fade,
    clock: _clock,
  );
  MotionValue<double> get _shown => _motion.shown;
  MotionValue<double> get _glass => _motion.glass;

  double get _now => _clock.now;

  @override
  bool get followsKeyboard => false;

  @override
  void initState() {
    super.initState();
    _clock = MotionClockScope.of(context);
    _shown.addListener(_lifted);
  }

  @override
  void dispose() {
    _shown.removeListener(_lifted);
    widget.lift?.value = 0;
    widget.fade.snap(_now, 1);
    super.dispose();
  }

  void _lifted() => widget.lift?.value = -widget.travel * _shown.value;

  @override
  void begin(double t, {required double keyboard}) => _motion.present(t);

  @override
  void end(double t) => _motion.dismiss(t);

  @override
  Widget build(BuildContext context) => SizedBox(
    height: GlassNavigationBar.searchFieldHeight,
    child: SearchHost(
      law: this,
      field: widget.field,
      fieldHeight: _StackedMetrics.fieldHeight,
      fieldGlass: _glass,
      builder: (context, parts) => _StackedLayout(
        shown: _shown,
        glass: _glass,
        offset: widget.offset,
        fill: GlassDynamicColor.resolve(_StackedMetrics.fill, context),
        children: [parts.field, parts.close],
      ),
    ),
  );
}

abstract final class _StackedMetrics {
  /// The height of a stacked field (iOS 27 simulator: 44 points at rest
  /// and presented).
  static const double fieldHeight = 44;

  /// The space between the screen's sides and the field.
  static const double sideInset = navigationSideInset;

  /// The space between the field and the content below it (search
  /// passport).
  static const double bottomGap = 10;

  /// The space between the presented field and its close button.
  static const double closeGap = 10;

  /// How far toward the trailing side the close button starts.
  static const double closeTravel = 40;

  /// The plain fill of the field at rest: 0x767680 at 12 percent on white
  /// (simulator); the dark 24 percent is not measured.
  static const fill = GlassDynamicColor.withBrightness(
    color: Color(0x1F767680),
    darkColor: Color(0x3D767680),
  );

  /// The share of the field's fold at which its text is gone (read from
  /// UIKit).
  static const double textGone = 0.2;

  /// The share of the field's fold at which its fill starts to fade, and
  /// the share over which it does (read from UIKit).
  static const double fillFadeStart = 0.8;

  /// See [fillFadeStart].
  static const double fillFade = 0.15;
}

class _StackedLayout extends MultiChildRenderObjectWidget {
  const _StackedLayout({
    required this.shown,
    required this.glass,
    required this.offset,
    required this.fill,
    required super.children,
  });

  final ValueListenable<double> shown;
  final ValueListenable<double> glass;
  final MotionSelection<double> offset;
  final Color fill;

  @override
  _RenderStackedLayout createRenderObject(BuildContext context) =>
      _RenderStackedLayout(
        shown: shown,
        glass: glass,
        offset: offset,
        fill: fill,
        rtl: context.isRightToLeft,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderStackedLayout renderObject,
  ) {
    renderObject.fill = fill;
    renderObject.rtl = context.isRightToLeft;
  }
}

class _StackedData extends ContainerBoxParentData<RenderBox> {}

/// Lays the field out as wide as the presentation leaves it and paints it
/// folded by the scroll, over its plain fill, with the close button
/// arriving beside it; nothing builds per frame.
class _RenderStackedLayout extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _StackedData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _StackedData> {
  _RenderStackedLayout({
    required this.shown,
    required this.glass,
    required this._offset,
    required this._fill,
    required this._rtl,
  });

  final ValueListenable<double> shown;
  final ValueListenable<double> glass;
  final MotionSelection<double> _offset;

  final _layers = LayerHandle<OpacityLayer>();
  final _clip = LayerHandle<ClipRRectLayer>();
  final _closeLayer = LayerHandle<OpacityLayer>();

  Color _fill;
  Color get fill => _fill;
  set fill(Color value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  bool _rtl;
  bool get rtl => _rtl;
  set rtl(bool value) {
    if (value == _rtl) return;
    _rtl = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StackedData) child.parentData = _StackedData();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    shown.addListener(markNeedsLayout);
    glass.addListener(markNeedsPaint);
    _offset.addRenderListener(markNeedsPaint);
  }

  @override
  void detach() {
    shown.removeListener(markNeedsLayout);
    glass.removeListener(markNeedsPaint);
    _offset.removeRenderListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _layers.layer = null;
    _clip.layer = null;
    _closeLayer.layer = null;
    super.dispose();
  }

  double get _shown => shown.value.clamp(0.0, 1.0);

  // How far the field has folded, 0 to its height; a presented field does
  // not fold.
  double get _fold =>
      _offset.value.clamp(0.0, _StackedMetrics.fieldHeight) * (1 - _shown);

  double get _pull => math.max(0, -_offset.value);

  Rect get _field {
    const side = _StackedMetrics.sideInset;
    const h = _StackedMetrics.fieldHeight;
    final width =
        size.width - 2 * side - (h + _StackedMetrics.closeGap) * shown.value;
    final left = _rtl ? size.width - side - width : side;
    return Rect.fromLTWH(left, 0, math.max(0, width), h);
  }

  Rect get _close {
    const side = _StackedMetrics.sideInset;
    const h = _StackedMetrics.fieldHeight;
    final away = _StackedMetrics.closeTravel * (1 - shown.value);
    final left = _rtl ? side - away : size.width - side - h + away;
    return Rect.fromLTWH(left, 0, h, h);
  }

  @override
  void performLayout() {
    size = constraints.constrain(
      Size(constraints.maxWidth, GlassNavigationBar.searchFieldHeight),
    );
    final field = firstChild!;
    final close = childAfter(field)!;
    field.layout(BoxConstraints.tight(_field.size));
    close.layout(BoxConstraints.tight(_close.size));
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final field = firstChild!;
    final close = childAfter(field)!;
    final down = Offset(0, _pull);
    if (_shown > 0.5) {
      final at = _close.topLeft + down;
      if (result.addWithPaintOffset(
        offset: at,
        position: position,
        hitTest: (result, local) => close.hitTest(result, position: local),
      )) {
        return true;
      }
    }
    if (_fold / _StackedMetrics.fieldHeight >= 0.5) return false;
    final at = _field.topLeft + down;
    return result.addWithPaintOffset(
      offset: at,
      position: position,
      hitTest: (result, local) => field.hitTest(result, position: local),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final at = (identical(child, firstChild) ? _field : _close).topLeft;
    transform.translateByDouble(at.dx, at.dy + _pull, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final field = firstChild!;
    final close = childAfter(field)!;
    final rest = _field.shift(offset + Offset(0, _pull));
    final fold = _fold;
    final r = fold / _StackedMetrics.fieldHeight;
    final body = Rect.fromLTWH(
      rest.left,
      rest.top,
      rest.width,
      rest.height - fold,
    );
    final capsule = RRect.fromRectAndRadius(
      body,
      Radius.circular(body.height / 2),
    );
    final fillShown =
        (1 - glass.value.clamp(0.0, 1.0)) *
        (1 -
            ((r - _StackedMetrics.fillFadeStart) / _StackedMetrics.fillFade)
                .clamp(0.0, 1.0));
    if (fillShown > 0 && body.height > 0) {
      final paint = Paint();
      paint.color = _fill.withValues(alpha: _fill.a * fillShown);
      context.canvas.drawRRect(capsule, paint);
    }
    final text = 1 - (r / _StackedMetrics.textGone).clamp(0.0, 1.0);
    if (text <= 0) {
      _layers.layer = null;
      _clip.layer = null;
    } else {
      void drawField(PaintingContext context, Offset at) =>
          context.paintChild(field, at);
      void clipped(PaintingContext context, Offset at) {
        if (fold <= 0) {
          _clip.layer = null;
          drawField(context, at);
          return;
        }
        _clip.layer = context.pushClipRRect(
          needsCompositing,
          at,
          Offset.zero & body.size,
          RRect.fromRectAndRadius(
            Offset.zero & body.size,
            Radius.circular(body.height / 2),
          ),
          drawField,
          oldLayer: _clip.layer,
        );
      }

      if (text >= 1) {
        _layers.layer = null;
        clipped(context, rest.topLeft);
      } else {
        _layers.layer = context.pushOpacity(
          rest.topLeft,
          (text * 255).round(),
          clipped,
          oldLayer: _layers.layer,
        );
      }
    }
    final present = _shown;
    if (present <= 0.001) {
      _closeLayer.layer = null;
      return;
    }
    _closeLayer.layer = context.pushOpacity(
      _close.shift(offset + Offset(0, _pull)).topLeft,
      (present * 255).round(),
      (context, at) => context.paintChild(close, at),
      oldLayer: _closeLayer.layer,
    );
  }

  @override
  bool get alwaysNeedsCompositing => true;
}
