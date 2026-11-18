import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/layout_item.dart';
import 'package:kinesis/src/widgets/resolve.dart';
import 'package:kinesis/src/widgets/scope.dart';

/// A lazy list that animates whatever a change of its data did to its
/// rows: the sliver counterpart of `MotionLayout`.
///
/// UIKit: `UITableView.performBatchUpdates`. SwiftUI: a `List` under
/// `withAnimation`. Flutter: `SliverAnimatedList`, without telling it what
/// changed.
///
/// [ids] is the order of the whole data; [itemBuilder] builds a row by its
/// id while it is in view. After a change the rows that moved slide from
/// where they were drawn to where the list puts them, rows inserted in view
/// enter with the planner's insert effect, and a row deleted in view stays
/// drawn where it was, taking no room, while it leaves with the remove
/// effect; its element and state live until it has gone. Rows that scroll
/// into view are placed without motion, and changes out of view move
/// nothing. The frame's transaction decides as in `MotionLayout`: after a
/// `withSpring` the change follows its spring, after a `withoutAnimation`
/// and under a muted `TickerMode` it jumps, with neither a row at rest jumps
/// and a row in flight is carried along.
///
/// Rects are in the list's scroll offsets, so a scroll during a change moves
/// the rows together and neither starts nor bends a motion. Rows are hit
/// where the list puts them, drawn where they slide, and read by
/// accessibility where they are drawn once they rest; a leaving row is
/// neither hit nor read. A row keeps its laid out size and is drawn centered
/// on its item's rect. `MotionLayout.itemOf` and `MotionLayout.adoptItem`
/// work inside a row. The list grows down or right; a reversed axis is not
/// supported.
class SliverMotionList extends StatefulWidget {
  /// Creates a list of the rows of [ids].
  const SliverMotionList({
    required this.ids,
    required this.itemBuilder,
    this.planner = const LayoutPlanner.flip(),
    this.motion,
    this.onLayout,
    super.key,
  });

  /// The rows' ids, in order: the whole data, built or not.
  final List<Object> ids;

  /// Builds the row of an id.
  final Widget Function(BuildContext context, Object id) itemBuilder;

  /// How a change animates, when the list keeps its own motion.
  final LayoutPlanner planner;

  /// The motion the list drives, kept by an owner that also reads it; the
  /// list keeps one of its own on [planner] when null.
  final LayoutMotion? motion;

  /// Called with each change of the rows in view, after the planner planned
  /// it, in the frame's resolve phase before paint: it must not rebuild;
  /// what it marks for layout is laid out again in that frame.
  final ValueChanged<LayoutChange>? onLayout;

  @override
  State<SliverMotionList> createState() => _SliverMotionListState();
}

class _SliverMotionListState extends State<SliverMotionList>
    with LayoutMotionOwner<SliverMotionList> {
  @override
  final Map<Object, LayoutItemEntry> entries = {};
  List<Object> _ids = const [];
  List<Object> _order = const [];
  Set<Object> _fresh = const {};
  final Map<Key, int> _indexOf = {};

  @override
  LayoutMotion? get givenMotion => widget.motion;

  @override
  LayoutPlanner get givenPlanner => widget.planner;

  @override
  void didUpdateWidget(SliverMotionList oldWidget) {
    super.didUpdateWidget(oldWidget);
    motionUpdated(oldWidget.motion);
  }

  // A ghost keeps its place after the row that preceded it in the last
  // order, or the order's start.
  List<Object> _merge(List<Object> ids) {
    final order = List<Object>.of(ids);
    for (var i = 0; i < _order.length; i++) {
      final id = _order[i];
      if (!ghosts.contains(id) || order.contains(id)) continue;
      var at = 0;
      for (var j = i - 1; j >= 0; j--) {
        final before = order.indexOf(_order[j]);
        if (before >= 0) {
          at = before + 1;
          break;
        }
      }
      order.insert(at, id);
    }
    return order;
  }

  @override
  Widget build(BuildContext context) {
    muted = !TickerMode.valuesOf(context).enabled;
    final ids = widget.ids;
    final present = ids.toSet();
    final before = _ids.toSet();
    for (final id in _ids) {
      if (present.contains(id) || ghosts.contains(id)) continue;
      final entry = entries[id];
      if (animates && entry?.probe != null && motion.hostLaidOut(id) != null) {
        ghosts.add(id);
      } else {
        entries.remove(id);
      }
    }
    ghosts.removeAll(present);
    _fresh = present.difference(before);
    _ids = ids;
    final order = _order = _merge(ids);
    _indexOf.clear();
    var semantic = 0;
    final semantics = <int?>[];
    for (var i = 0; i < order.length; i++) {
      final id = order[i];
      final entry = entries[id] ??= LayoutItemEntry(motion, id);
      _indexOf[entry.key] = i;
      semantics.add(ghosts.contains(id) ? null : semantic++);
    }
    return MotionScope(
      motion: motion,
      child: _SliverHost(
        state: this,
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, i) => _probe(context, order[i]),
            childCount: order.length,
            findChildIndexCallback: (key) => _indexOf[key],
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: false,
            semanticIndexCallback: (_, i) => semantics[i],
          ),
        ),
      ),
    );
  }

  Widget _probe(BuildContext context, Object id) {
    final entry = entries[id]!;
    final ghost = ghosts.contains(id);
    final child = ghost
        ? entry.last ?? const SizedBox.shrink()
        : entry.last = widget.itemBuilder(context, id);
    return _Probe(
      key: entry.key,
      motion: motion,
      entry: entry,
      ghost: ghost,
      child: LayoutItemScope(entry: entry, child: child),
    );
  }

  void _resolve(_RenderSliverHost host) {
    final rects = <Object, Rect>{
      for (final probe in host.probes)
        if (!probe.ghost && probe.hasSize) probe.id: probe.listFrame(),
    };
    final ghosts = {
      for (final probe in host.probes)
        if (probe.ghost) probe.id,
    };
    final motion = this.motion;
    for (final id in motion.ids.toList()) {
      if (!rects.containsKey(id) && !ghosts.contains(id)) motion.forget(id);
    }
    final layout = MotionTransaction.layout;
    final jump = jumps;
    final planner = motion.planner;
    motion.planner = _ListPlanner(planner, _fresh);
    final LayoutChange? change;
    try {
      change = motion.layout(
        motion.clock.now,
        rects,
        spring: jump ? null : layout?.spring,
        carry: layout == null,
        jump: jump,
      );
    } finally {
      motion.planner = planner;
      _fresh = const {};
    }
    if (change == null) return;
    widget.onLayout?.call(change);
    host.markProbesChanged();
  }
}

/// Plans with [inner], except that a row entering because it came into
/// view, not because the data gained it, is placed at once.
final class _ListPlanner extends LayoutPlanner {
  const _ListPlanner(this.inner, this.fresh);

  final LayoutPlanner inner;
  final Set<Object> fresh;

  @override
  Spring? get spring => inner.spring;

  @override
  Map<Object, LayoutPlan> plan(LayoutChange change) {
    final plans = inner.plan(change);
    return {
      for (final MapEntry(:key, :value) in change.entries.entries)
        key: value.phase == LayoutPhase.entering && !fresh.contains(key)
            ? const LayoutPlan()
            : plans[key] ?? LayoutPlan(spring: change.spring),
    };
  }
}

class _SliverHost extends SingleChildRenderObjectWidget {
  const _SliverHost({required this.state, required Widget sliver})
    : super(child: sliver);

  final _SliverMotionListState state;

  @override
  _RenderSliverHost createRenderObject(BuildContext context) =>
      _RenderSliverHost(state);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSliverHost renderObject,
  ) {
    renderObject.state = state;
  }
}

class _RenderSliverHost extends RenderProxySliver with MotionResolveHost {
  _RenderSliverHost(this.state);

  _SliverMotionListState state;
  final Set<_RenderProbe> _probes = {};

  Iterable<_RenderProbe> get probes => _probes;

  void markProbesChanged() {
    for (final probe in _probes) {
      probe.markNeedsCompositedLayerUpdate();
    }
  }

  @override
  void performLayout() {
    assert(
      constraints.growthDirection == GrowthDirection.forward &&
          (constraints.axisDirection == AxisDirection.down ||
              constraints.axisDirection == AxisDirection.right),
      'SliverMotionList grows down or right only.',
    );
    super.performLayout();
    scheduleResolve();
  }

  @override
  void resolve() => state._resolve(this);
}

class _Probe extends SingleChildRenderObjectWidget {
  const _Probe({
    required this.motion,
    required this.entry,
    required this.ghost,
    required super.child,
    super.key,
  });

  final LayoutMotion motion;
  final LayoutItemEntry entry;
  final bool ghost;

  @override
  _RenderProbe createRenderObject(BuildContext context) =>
      _RenderProbe(motion, entry, ghost: ghost);

  @override
  void updateRenderObject(BuildContext context, _RenderProbe renderObject) {
    renderObject.motion = motion;
    renderObject.entry = entry;
    if (renderObject.ghost == ghost) return;
    renderObject.ghost = ghost;
    renderObject.markNeedsLayout();
    renderObject.markNeedsSemanticsUpdate();
  }
}

class _RenderProbe extends LayoutProbeBox {
  _RenderProbe(super.motion, super.entry, {required super.ghost});

  _RenderSliverHost? _host;
  BoxConstraints? _lastConstraints;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    var ancestor = parent;
    while (ancestor != null && ancestor is! _RenderSliverHost) {
      ancestor = ancestor.parent;
    }
    _host = ancestor as _RenderSliverHost?;
    _host?._probes.add(this);
    follow();
  }

  @override
  void detach() {
    unfollow();
    _host?._probes.remove(this);
    _host = null;
    super.detach();
  }

  bool get _vertical => _host?.constraints.axis != Axis.horizontal;

  @override
  void performLayout() {
    final child = this.child;
    if (!ghost) {
      _lastConstraints = constraints;
      super.performLayout();
      _host?.scheduleResolve();
      return;
    }
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_lastConstraints ?? constraints, parentUsesSize: true);
    size = constraints.constrain(
      _vertical ? Size(child.size.width, 0) : Size(0, child.size.height),
    );
  }

  /// The child's size: a ghost takes no room but keeps what it drew.
  Size get _drawnSize => child?.size ?? size;

  /// Where the list puts this row, in the list's scroll offsets.
  Rect listFrame() {
    var main = 0.0;
    var cross = 0.0;
    RenderObject node = this;
    while (node is RenderBox) {
      final data = node.parentData;
      if (data is SliverMultiBoxAdaptorParentData) {
        main += data.layoutOffset ?? 0;
        break;
      }
      if (data is BoxParentData) {
        main += _vertical ? data.offset.dy : data.offset.dx;
        cross += _vertical ? data.offset.dx : data.offset.dy;
      }
      final parent = node.parent;
      if (parent == null) break;
      node = parent;
    }
    final origin = _vertical ? Offset(cross, main) : Offset(main, cross);
    return origin & _drawnSize;
  }

  @override
  Matrix4? get itemTransform {
    if (!drawsItem || !hasSize) return null;
    final item = entry.item.value;
    if (motion.hostLaidOut(id) == null) return null;
    final here = listFrame();
    final shift = item.rect.center - here.center;
    final scale = item.scale;
    if (shift == Offset.zero && scale == 1) return null;
    return LayoutProbeBox.shiftAndScale(
      shift,
      scale,
      _drawnSize.center(Offset.zero),
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) =>
      !ghost && super.hitTest(result, position: position);

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    if (!ghost) super.visitChildrenForSemantics(visitor);
  }
}
