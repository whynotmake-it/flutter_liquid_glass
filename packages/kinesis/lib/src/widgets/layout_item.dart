import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:kinesis/motion.dart';
import 'package:kinesis/src/widgets/scope.dart';
import 'package:kinesis/src/widgets/transition.dart';

/// One item of a layout host: where it is drawn, and which descendants
/// draw it themselves.
@internal
final class LayoutItemEntry {
  /// Follows [id] of [motion].
  LayoutItemEntry(LayoutMotion motion, this.id)
    : item = motion.select((m) => m.hostItemAt(id));

  /// The item's key.
  final Object id;

  /// Where the item is drawn.
  final MotionSelection<LayoutItem> item;

  /// The probe's key, which keeps the item's element through moves.
  final GlobalKey key = GlobalKey();

  final Set<Element> _adopters = {};

  /// The probe that draws the item, told when adoption changes.
  RenderObject? probe;

  /// The widget the item last built, which a leaving item keeps.
  Widget? last;

  /// Whether a descendant draws the item itself.
  bool get adopted => _adopters.isNotEmpty;

  /// Records whether [adopter] draws the item.
  void adopt(Element adopter, {required bool adopts}) {
    final was = adopted;
    if (adopts) {
      _adopters.add(adopter);
    } else {
      _adopters.remove(adopter);
    }
    if (adopted != was) probe?.markNeedsCompositedLayerUpdate();
  }
}

/// The aspect under which a descendant adopts its item.
@internal
const Object adoptsItem = #adopts;

/// Hands an item's [entry] to the item's content.
@internal
class LayoutItemScope extends InheritedWidget {
  /// Scopes [child] to [entry].
  const LayoutItemScope({required this.entry, required super.child, super.key});

  /// The item.
  final LayoutItemEntry entry;

  /// Where the item is drawn.
  ValueListenable<LayoutItem> get item => entry.item;

  /// The item around [context], or null; with [adopt] the dependent draws
  /// it itself.
  static ValueListenable<LayoutItem>? of(
    BuildContext context, {
    bool adopt = false,
  }) => context
      .dependOnInheritedWidgetOfExactType<LayoutItemScope>(
        aspect: adopt ? adoptsItem : null,
      )
      ?.item;

  @override
  bool updateShouldNotify(LayoutItemScope oldWidget) =>
      !identical(oldWidget.entry, entry);

  @override
  InheritedElement createElement() => _LayoutItemScopeElement(this);
}

class _LayoutItemScopeElement extends InheritedElement {
  _LayoutItemScopeElement(super.widget);

  LayoutItemEntry get _entry => (widget as LayoutItemScope).entry;

  @override
  void updateDependencies(Element dependent, Object? aspect) {
    super.updateDependencies(dependent, aspect);
    if (identical(aspect, adoptsItem)) _entry.adopt(dependent, adopts: true);
  }

  @override
  void removeDependent(Element dependent) {
    _entry.adopt(dependent, adopts: false);
    super.removeDependent(dependent);
  }

  @override
  void updated(LayoutItemScope oldWidget) {
    if (!identical(oldWidget.entry, _entry)) {
      for (final adopter in oldWidget.entry._adopters.toList()) {
        oldWidget.entry.adopt(adopter, adopts: false);
        _entry.adopt(adopter, adopts: true);
      }
    }
    super.updated(oldWidget);
  }
}

/// What `MotionLayout` and `SliverMotionList` keep the same way: the
/// motion (given, or one of their own), the items by id, and the ghosts of
/// items that left while they are still drawn leaving.
@internal
mixin LayoutMotionOwner<W extends StatefulWidget> on State<W> {
  /// The motion the widget was given, or null.
  LayoutMotion? get givenMotion;

  /// The planner of the motion the widget keeps itself.
  LayoutPlanner get givenPlanner;

  /// The items by id, ghosts included.
  Map<Object, LayoutItemEntry> get entries;

  /// The ids of items that left and are drawn leaving.
  final Set<Object> ghosts = {};

  /// Whether a muted `TickerMode` holds the widget.
  bool muted = false;

  LayoutMotion? _kept;
  late MotionSelection<int> _drawn;
  bool _leftPending = false;

  /// The motion the widget drives.
  LayoutMotion get motion =>
      givenMotion ??
      (_kept ??= LayoutMotion(
        planner: givenPlanner,
        clock: MotionClockScope.of(context),
      ));

  /// Whether the frame's layout jumps instead of moving.
  bool get jumps {
    final layout = MotionTransaction.layout;
    return muted || (layout != null && layout.spring.isImmediate);
  }

  /// Whether a leaving item is kept drawn for its motion.
  bool get animates =>
      !jumps &&
      (motion.planner.spring != null || MotionTransaction.layout != null);

  /// Follows a change of the given motion from [previous].
  void motionUpdated(LayoutMotion? previous) {
    final kept = _kept;
    if (givenMotion == null && kept != null) kept.planner = givenPlanner;
    if (identical(previous, givenMotion)) return;
    _unbind();
    entries.clear();
    ghosts.clear();
    _bind();
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void dispose() {
    _unbind();
    super.dispose();
  }

  void _bind() {
    _drawn = motion.select((m) => m.ids.length);
    _drawn.addRenderListener(_dropped);
  }

  void _unbind() => _drawn.removeRenderListener(_dropped);

  // Heard in the resolve phase too, where nothing may rebuild: the rebuild
  // that lets the ghosts go waits for the clock's coming publish phase.
  void _dropped() {
    if (_leftPending || ghosts.every(motion.contains)) return;
    _leftPending = true;
    motion.clock.schedulePublish(() {
      _leftPending = false;
      _left();
    });
  }

  void _left() {
    if (!mounted) return;
    final gone = ghosts.where((id) => !motion.contains(id)).toList();
    if (gone.isEmpty) return;
    setState(() {
      ghosts.removeAll(gone);
      gone.forEach(entries.remove);
    });
  }
}

/// The render object of one item of a layout host: it draws the item
/// where its motion puts it, through one composited layer, unless a
/// descendant draws the item itself.
@internal
abstract class LayoutProbeBox extends RenderProxyBox {
  /// Draws the item [entry] of [motion].
  LayoutProbeBox(this.motion, this._entry, {required this.ghost});

  /// The motion that places the item.
  LayoutMotion motion;

  /// Whether the item left and is drawn leaving.
  bool ghost;

  LayoutItemEntry _entry;

  /// The item.
  LayoutItemEntry get entry => _entry;
  set entry(LayoutItemEntry value) {
    if (identical(value, _entry)) return;
    unfollow();
    _entry = value;
    follow();
    markNeedsCompositedLayerUpdate();
  }

  /// The item's key.
  Object get id => _entry.id;

  /// Whether the probe draws the item: no descendant adopted it.
  bool get drawsItem => !_entry.adopted;

  /// The move and scale the item's motion gives the child, or null at
  /// identity or while a descendant draws the item.
  Matrix4? get itemTransform;

  /// Follows the item while attached.
  @protected
  void follow() {
    if (!attached) return;
    _entry.item.addRenderListener(_itemChanged);
    _entry.probe = this;
  }

  /// Stops following the item.
  @protected
  void unfollow() {
    _entry.item.removeRenderListener(_itemChanged);
    if (identical(_entry.probe, this)) _entry.probe = null;
  }

  void _itemChanged() {
    if (drawsItem) markNeedsCompositedLayerUpdate();
    if (motion.itemRests(id)) markNeedsSemanticsUpdate();
  }

  /// The transform that moves a child centred at [center] by [shift] and
  /// scales it about that centre.
  @protected
  static Matrix4 shiftAndScale(Offset shift, double scale, Offset center) {
    final transform = Matrix4.translationValues(
      shift.dx + center.dx,
      shift.dy + center.dy,
      0,
    );
    transform.scaleByDouble(scale, scale, 1, 1);
    transform.translateByDouble(-center.dx, -center.dy, 0, 1);
    return transform;
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant MotionTransitionLayer? oldLayer,
  }) {
    final layer = oldLayer ?? MotionTransitionLayer();
    if (!drawsItem) {
      layer.update(transform: null, clip: null, alpha: null, blur: 0);
      return layer;
    }
    final item = _entry.item.value;
    final alpha = (item.opacity.clamp(0.0, 1.0) * 255).round();
    layer.update(
      transform: itemTransform,
      clip: null,
      alpha: alpha == 255 ? null : alpha,
      blur: math.max(0, item.blur),
    );
    return layer;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    super.applyPaintTransform(child, transform);
    if (itemTransform case final move?) transform.multiply(move);
  }
}
