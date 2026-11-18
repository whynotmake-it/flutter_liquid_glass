part of 'input_zones.dart';

class _ZonesHost<T extends Object> extends MultiChildRenderObjectWidget {
  const _ZonesHost({
    required this.state,
    required this.excludeChildSemantics,
    required super.children,
  });

  final _InputZonesState<T> state;
  final bool excludeChildSemantics;

  @override
  _RenderZones<T> createRenderObject(BuildContext context) {
    final box = _RenderZones<T>(
      state,
      excludeChildSemantics: excludeChildSemantics,
    );
    state._box = box;
    return box;
  }

  @override
  void updateRenderObject(BuildContext context, _RenderZones<T> renderObject) {
    renderObject.state = state;
    renderObject.excludeChildSemantics = excludeChildSemantics;
    state._box = renderObject;
    renderObject.markNeedsSemanticsUpdate();
  }
}

/// The host's box: the size of its first child, which it paints; the
/// zones' anchors after it paint nothing and lie where their zones are,
/// placed by paint transform.
class _RenderZones<T extends Object> extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ZoneParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ZoneParentData> {
  _RenderZones(this.state, {required this._excludeChildSemantics});

  _InputZonesState<T> state;

  bool _excludeChildSemantics;
  bool get excludeChildSemantics => _excludeChildSemantics;
  set excludeChildSemantics(bool value) {
    if (value == _excludeChildSemantics) return;
    _excludeChildSemantics = value;
    markNeedsSemanticsUpdate();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ZoneParentData) {
      child.parentData = _ZoneParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      firstChild?.getMinIntrinsicWidth(height) ?? 0;

  @override
  double computeMaxIntrinsicWidth(double height) =>
      firstChild?.getMaxIntrinsicWidth(height) ?? 0;

  @override
  double computeMinIntrinsicHeight(double width) =>
      firstChild?.getMinIntrinsicHeight(width) ?? 0;

  @override
  double computeMaxIntrinsicHeight(double width) =>
      firstChild?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      firstChild?.getDistanceToActualBaseline(baseline);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      firstChild?.getDryLayout(constraints) ?? constraints.smallest;

  @override
  void performLayout() {
    final content = firstChild;
    if (content == null) {
      size = constraints.smallest;
      return;
    }
    content.layout(constraints, parentUsesSize: true);
    size = content.size;
    // Each anchor sizes itself and is its own relayout boundary.
    var anchor = childAfter(content);
    while (anchor != null) {
      anchor.layout(const BoxConstraints());
      anchor = childAfter(anchor);
    }
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    if (child is! _RenderZoneAnchor<T>) {
      return super.applyPaintTransform(child, transform);
    }
    final bounds = child.zone.bounds;
    transform.translateByDouble(bounds.left, bounds.top, 0, 1);
    final laid = child.size;
    // Until it is laid out to a new size, the anchor is scaled to it.
    if (laid != bounds.size && !laid.isEmpty) {
      transform.scaleByDouble(
        bounds.width / laid.width,
        bounds.height / laid.height,
        1,
        1,
      );
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (firstChild case final content?) context.paintChild(content, offset);
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final content = firstChild;
    final zone = state._zoneAt(position);
    if (zone == null) {
      if (content == null || !size.contains(position)) return false;
      final hit = content.hitTest(result, position: position);
      if (state.widget.interactions.isEmpty) return hit;
      // The host's own interactions hear a touch between the zones.
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    content?.hitTest(result, position: position);
    // In the host's coordinates: the zone's events are read in them.
    if (zone._anchor case final anchor? when anchor.attached) {
      result.add(BoxHitTestEntry(anchor, position));
    }
    return true;
  }

  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (state.mounted) state._pointer(event);
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var child = firstChild;
    if (child == null) return;
    if (!_excludeChildSemantics) visitor(child);
    child = childAfter(child);
    while (child != null) {
      if (child is! _RenderZoneAnchor<T> || child.zone.present) visitor(child);
      child = childAfter(child);
    }
  }
}

class _ZoneParentData extends ContainerBoxParentData<RenderBox> {}

class _ZoneAnchor<T extends Object> extends LeafRenderObjectWidget {
  const _ZoneAnchor({required this.state});

  final _ZoneState<T> state;

  @override
  _RenderZoneAnchor<T> createRenderObject(BuildContext context) {
    final anchor = _RenderZoneAnchor<T>(
      state,
      properties: state.zone.semantics ?? const SemanticsProperties(),
      textDirection: Directionality.maybeOf(context),
    );
    state._anchor = anchor;
    return anchor;
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderZoneAnchor<T> renderObject,
  ) {
    renderObject.zone = state;
    renderObject.properties =
        state.zone.semantics ?? const SemanticsProperties();
    renderObject.textDirection = Directionality.maybeOf(context);
    state._anchor = renderObject;
    renderObject.markNeedsLayout();
    renderObject.markNeedsSemanticsUpdate();
  }
}

/// A zone's place in the render tree: a box of the zone's hit size,
/// which the host places on the zone by paint transform, so a frame where
/// the zone only moves lays nothing out. It is what a pointer on the zone
/// hits (its cursor and hover for the mouse tracker), the box its focus
/// node reports, and it describes the zone to accessibility.
class _RenderZoneAnchor<T extends Object> extends RenderBox
    with SemanticsAnnotationsMixin
    implements MouseTrackerAnnotation {
  _RenderZoneAnchor(
    this.zone, {
    required SemanticsProperties properties,
    required TextDirection? textDirection,
  }) {
    initSemanticsAnnotations(
      properties: properties,
      container: true,
      explicitChildNodes: false,
      excludeSemantics: false,
      blockUserActions: false,
      localeForSubtree: null,
      textDirection: textDirection,
    );
  }

  _ZoneState<T> zone;

  /// The size to lay out to: its zone's when the frame began.
  Size wanted = Size.zero;

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(wanted);

  @override
  void performLayout() => size = constraints.constrain(wanted);

  // A zone that appears after its anchor was laid out empty (its first
  // frame comes after the layout that places it) has no size to scale: its
  // bounds stand for it until it is laid out.
  Rect get _local => Offset.zero & (size.isEmpty ? zone.bounds.size : size);

  @override
  Rect get paintBounds => _local;

  @override
  Rect get semanticBounds => _local;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) => false;

  // The host adds the anchor to a hit at the host's coordinates.
  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (zone.mounted) zone.host._pointer(event);
  }

  @override
  MouseCursor get cursor => zone.mounted ? zone.cursor : MouseCursor.defer;

  @override
  PointerEnterEventListener? get onEnter =>
      (event) => zone.target.hover(event.localPosition, inside: true);

  @override
  PointerExitEventListener? get onExit =>
      (event) => zone.target.hover(event.localPosition, inside: false);

  @override
  bool get validForMouseTracker => attached && zone.mounted;

  @override
  void describeSemanticsConfiguration(SemanticsConfiguration config) {
    super.describeSemanticsConfiguration(config);
    zone.target.describe(config);
  }
}
