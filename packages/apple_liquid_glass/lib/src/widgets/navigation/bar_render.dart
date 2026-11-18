part of 'bar.dart';

class _BarItems extends MultiChildRenderObjectWidget {
  const _BarItems({
    required this.bar,
    required this.zones,
    required super.children,
  });

  final _Bar bar;
  final InputZonesController<Object> zones;

  @override
  _RenderBarItems createRenderObject(BuildContext context) => _RenderBarItems(
    bar,
    rtl: context.isRightToLeft,
    zones: zones,
    look: GlassHighlightLook.of(context),
  );

  // The bar rebuilds only for a change, which its layout applies.
  @override
  void updateRenderObject(BuildContext context, _RenderBarItems renderObject) {
    renderObject.rtl = context.isRightToLeft;
    renderObject.zones = zones;
    renderObject.look = GlassHighlightLook.of(context);
    renderObject.markNeedsLayout();
  }
}

class _ItemData extends ContainerBoxParentData<RenderBox> {}

/// Lays the bar's buttons out to measure them, hands the widths to the
/// host, and paints each where the host's motion puts it: moved, scaled,
/// faded and blurred, without a layout per frame, with the keyboard focus
/// ring and the hover response of its zone by the rule of
/// [GlassHighlights]: the ring outside the button's capsule, the hover a
/// glass body's wash over it (approximations, not measured). The zones
/// take the buttons' input; a custom item's own widget is hit, and read
/// by assistive technology, while its zone frame is live.
class _RenderBarItems extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ItemData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ItemData>,
        MotionResolveHost {
  _RenderBarItems(
    this.bar, {
    required this._rtl,
    required this._zones,
    required this._look,
  });

  final _Bar bar;

  bool _rtl;
  bool get rtl => _rtl;
  set rtl(bool value) {
    if (value == _rtl) return;
    _rtl = value;
    markNeedsLayout();
  }

  InputZonesController<Object> _zones;
  InputZonesController<Object> get zones => _zones;
  set zones(InputZonesController<Object> value) {
    if (identical(value, _zones)) return;
    _zones = value;
    for (final MapEntry(key: id, value: highlight) in _shown.entries) {
      highlight.states = value.states(id);
    }
  }

  GlassHighlightLook _look;
  GlassHighlightLook get look => _look;
  set look(GlassHighlightLook value) {
    if (value == _look) return;
    _look = value;
    for (final highlight in _shown.values) {
      highlight.look = value;
    }
  }

  final Map<RenderBox, LayerHandle<ContainerLayer>> _layers = {};
  final Map<Object, GlassHighlight> _shown = {};

  GlassHighlight _highlightOf(Object id) => _shown.putIfAbsent(id, () {
    final highlight = GlassHighlight(look: _look, states: _zones.states(id));
    if (attached) highlight.addListener(markNeedsPaint);
    return highlight;
  });

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ItemData) child.parentData = _ItemData();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    bar.items = this;
    for (final highlight in _shown.values) {
      highlight.addListener(markNeedsPaint);
    }
  }

  @override
  void detach() {
    if (identical(bar.items, this)) bar.items = null;
    for (final highlight in _shown.values) {
      highlight.removeListener(markNeedsPaint);
    }
    super.detach();
  }

  @override
  void dropChild(covariant RenderBox child) {
    _layers.remove(child)?.layer = null;
    super.dropChild(child);
  }

  @override
  void dispose() {
    for (final handle in _layers.values) {
      handle.layer = null;
    }
    super.dispose();
  }

  Object _idOf(RenderBox child) => (child as _RenderItemBox).id;

  @override
  void performLayout() {
    bar.host._drainWithdrawals();
    size = constraints.biggest;
    final widths = <Object, double>{};
    var child = firstChild;
    while (child != null) {
      child.layout(
        BoxConstraints(maxHeight: size.height),
        parentUsesSize: true,
      );
      final id = _idOf(child);
      widths[id] = child.size.width;
      if (bar.buttons[id]?.item is! GlassBarCustomItem) _highlightOf(id);
      child = childAfter(child);
    }
    for (final id in _shown.keys.toList()) {
      if (widths.containsKey(id)) continue;
      if (attached) _shown[id]!.removeListener(markNeedsPaint);
      _shown.remove(id);
    }
    bar.measured(widths, size.width, rtl: _rtl);
    if (bar.pendingRooms.isNotEmpty) scheduleResolve();
  }

  @override
  void resolve() => bar.resolve();

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final frame = bar.itemFrames[_idOf(child)];
    if (frame == null) return;
    final c = frame.center;
    transform.translateByDouble(c.dx, c.dy, 0, 1);
    transform.scaleByDouble(frame.scale, frame.scale, 1, 1);
    final half = child.size.center(Offset.zero);
    transform.translateByDouble(-half.dx, -half.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final frame = bar.zoneFrameOf(_idOf(child));
      if (frame != null && frame.live) {
        final rect = frame.rect;
        if (glassButtonReach.takes(rect).contains(position)) {
          final origin = rect.center - child.size.center(Offset.zero);
          final local = position - origin;
          final inside = Offset(
            local.dx.clamp(0, math.max(0, child.size.width - 0.01)),
            local.dy.clamp(0, math.max(0, child.size.height - 0.01)),
          );
          final hit = result.addWithPaintOffset(
            offset: origin,
            position: origin + inside,
            hitTest: (result, transformed) =>
                child!.hitTest(result, position: transformed),
          );
          if (hit) return true;
        }
      }
      child = childBefore(child);
    }
    return false;
  }

  // The items assistive technology reads: those whose zone frame is live.
  Set<Object> _read = const {};

  /// The motion moved the items: they paint again, and assistive
  /// technology hears of an item that came or went.
  void moved() {
    markNeedsPaint();
    final read = <Object>{};
    var child = firstChild;
    while (child != null) {
      final id = _idOf(child);
      if (bar.zoneFrameOf(id)?.live ?? false) read.add(id);
      child = childAfter(child);
    }
    if (setEquals(read, _read)) return;
    _read = read;
    markNeedsSemanticsUpdate();
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var child = firstChild;
    while (child != null) {
      if (_read.contains(_idOf(child))) visitor(child);
      child = childAfter(child);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final id = _idOf(child);
      final frame = bar.itemFrames[id];
      final handle = _layers.putIfAbsent(child, LayerHandle.new);
      if (frame == null ||
          frame.presence <= 0 ||
          frame.scale <= 0 ||
          bar.inMenuCapsule(id)) {
        handle.layer = null;
        child = childAfter(child);
        continue;
      }
      final box = child;
      final origin = offset + frame.center - box.size.center(Offset.zero);
      // The lift and the scale, in the coordinates of the item's origin.
      Matrix4? transform;
      if (bar.liftOf(id) case final lift?) {
        transform = Matrix4.translationValues(
          offset.dx - origin.dx,
          offset.dy - origin.dy,
          0,
        );
        transform.multiply(lift);
        transform.translateByDouble(
          origin.dx - offset.dx,
          origin.dy - offset.dy,
          0,
          1,
        );
      }
      if (frame.scale != 1) {
        final c = box.size.center(Offset.zero);
        transform ??= Matrix4.identity();
        transform.translateByDouble(c.dx, c.dy, 0, 1);
        transform.scaleByDouble(frame.scale, frame.scale, 1, 1);
        transform.translateByDouble(-c.dx, -c.dy, 0, 1);
      }
      final alpha = (frame.presence * 255).round();
      // The item's capsule, in the layer's coordinates.
      final body = Rect.fromCenter(
        center: box.size.center(Offset.zero),
        width: frame.size.width,
        height: bar.metrics.buttonHeight,
      );
      final highlight = _shown[id];
      // One layer whose blur the glass over the bar knows the reach of: an
      // item that blurs in then lies in the copies of the glass it is under,
      // not in every copy of the frame.
      final held = handle.layer;
      final layer = held is MotionTransitionLayer
          ? held
          : MotionTransitionLayer();
      layer.offset = origin;
      layer.update(
        transform: transform,
        clip: null,
        alpha: alpha >= 255 ? null : alpha,
        blur: frame.blur <= 0.05 ? 0 : frame.blur / 2,
      );
      handle.layer = layer;
      context.pushLayer(layer, (context, _) {
        context.paintChild(box, Offset.zero);
        highlight?.paint(
          context.canvas,
          shape: LiquidRoundedSuperellipse.capsule,
          body: body,
        );
      }, Offset.zero);
      child = childAfter(child);
    }
  }

  @override
  bool get alwaysNeedsCompositing => true;
}

/// An item's source under its menu anchor: its own tap, and the capsule
/// look the menu's glass carries as it grows out of the glyph.
class _ItemSource extends StatefulWidget {
  const _ItemSource({
    required this.onPressed,
    required this.semanticLabel,
    required this.look,
    required this.child,
  });

  final VoidCallback onPressed;
  final String? semanticLabel;
  final Widget look;
  final Widget child;

  @override
  State<_ItemSource> createState() => _ItemSourceState();
}

class _ItemSourceState extends State<_ItemSource> {
  late final List<Interaction> _tap = [
    PressInteraction(
      onTap: (_) => widget.onPressed(),
    ),
  ];

  @override
  Widget build(BuildContext context) => InputRegion(
    interactions: _tap,
    semantics: SemanticsProperties(label: widget.semanticLabel),
    reach: glassButtonReach,
    child: GlassSource(
      description: GlassSourceDescription(look: widget.look),
      child: widget.child,
    ),
  );
}

/// Reads its child, a menu and its source, to assistive technology only
/// while the menu shows: the item's zone speaks for the source otherwise.
class _OpenMenuSemantics extends SingleChildRenderObjectWidget {
  const _OpenMenuSemantics({
    required this.bar,
    required this.id,
    required super.child,
  });

  final _Bar bar;
  final Object id;

  @override
  _RenderOpenMenuSemantics createRenderObject(BuildContext context) =>
      _RenderOpenMenuSemantics(bar, id);
}

class _RenderOpenMenuSemantics extends RenderProxyBox {
  _RenderOpenMenuSemantics(this.bar, this.id);

  final _Bar bar;

  // The item's element is keyed by its id, so the id never changes.
  final Object id;

  bool _open = false;

  void _check() {
    final open = bar.menuShows(id);
    if (open == _open) return;
    _open = open;
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _open = bar.menuShows(id);
    bar.frames.addListener(_check);
  }

  @override
  void detach() {
    bar.frames.removeListener(_check);
    super.detach();
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (_open) super.visitChildrenForSemantics(visitor);
  }
}

class _ItemBox extends SingleChildRenderObjectWidget {
  const _ItemBox({required this.id, required super.child});

  final Object id;

  @override
  _RenderItemBox createRenderObject(BuildContext context) => _RenderItemBox(id);

  @override
  void updateRenderObject(BuildContext context, _RenderItemBox renderObject) {
    renderObject.id = id;
  }
}

class _RenderItemBox extends RenderProxyBox {
  _RenderItemBox(this.id);

  Object id;
}
