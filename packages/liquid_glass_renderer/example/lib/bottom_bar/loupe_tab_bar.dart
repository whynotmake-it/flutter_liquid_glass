import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/listenable_transform.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/tab_selection.dart';
import 'package:motor/motor.dart';

@immutable
class BottomBarTab {
  const BottomBarTab({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// An iOS 27 tab bar: a glass capsule whose selection platter turns into a
/// clear loupe while the bar is held, follows the finger across the tabs and
/// snaps to a tab on release. The whole bar swells while held.
///
/// Must be inside a [LiquidGlassBlendGroup], which the capsule joins so it
/// can merge with neighboring bar segments. The loupe renders in its own
/// small glass layer, mounted only while it is visible, because it has to
/// refract the capsule and the icons painted beneath it. Its
/// `backdropShrink` shows the bar smaller inside it; the tinted icons under
/// it are scaled up by the same amount so they keep their size.
///
/// The drag and motion follow the original example bottom bar: pointer
/// positions from a horizontal drag, an interactive spring while dragging,
/// a bouncy spring to the chosen tab, and a loupe that stays up until the
/// indicator has nearly arrived. Nothing rebuilds while the finger moves:
/// the bar transform, platter, tint mask and loupe placement read the motion
/// controllers at paint and layout time.
class LoupeTabBar extends StatefulWidget {
  const LoupeTabBar({
    required this.tabs,
    this.selectedIndex = 0,
    this.onSelected,
    this.appearance,
    this.shadows = const [],
    this.fake = false,
    this.height = 62,
    this.pressScale = .05,
    this.loupeSettings = defaultLoupeSettings,
    super.key,
  }) : assert(tabs.length > 0, 'A tab bar needs at least one tab.');

  final List<BottomBarTab> tabs;

  /// The initially selected tab. Changing it moves the selection.
  final int selectedIndex;

  final ValueChanged<int>? onSelected;

  /// Appearance of the capsule, or `null` to inherit the layer's.
  final LiquidGlassAppearance? appearance;

  final List<BoxShadow> shadows;

  /// Whether the loupe renders as [FakeGlass], to match a fake parent layer.
  final bool fake;

  final double height;

  /// How much the whole bar grows while held.
  final double pressScale;

  /// Settings of the loupe's own glass layer.
  ///
  /// Its `backdropShrink` is how much smaller the bar looks inside the loupe.
  final LiquidGlassSettings loupeSettings;

  /// A clear, unfrosted lens with a wide bevel, after the loupe in the
  /// original example bottom bar (`test/support/bottom_bar.dart`), shrinking
  /// the backdrop enough that the swollen bar's edges show inside it.
  static const defaultLoupeSettings = LiquidGlassSettings(
    refractionHeight: 24,
    refractionAmount: 40,
    backdropShrink: .25,
    dispersion: .1,
    frost: 0,
    contourStrength: .1,
    contourWidth: 1,
  );

  static const loupeKey = ValueKey('loupe-tab-bar-loupe');

  @override
  State<LoupeTabBar> createState() => _LoupeTabBarState();
}

class _LoupeTabBarState extends State<LoupeTabBar>
    with TickerProviderStateMixin {
  static const _padding = 4.0;

  static const _platterColor = CupertinoDynamicColor.withBrightness(
    color: Color(0x14000000),
    darkColor: Color(0x24FFFFFF),
  );

  static const _loupeShadows = [
    BoxShadow(color: Color(0x1A000000), blurRadius: 30),
  ];

  static const _follow = Motion.interactiveSpring(snapToEnd: true);
  static const _settle = Motion.bouncySpring(snapToEnd: true);
  static const _thickness = Motion.snappySpring(
    duration: Duration(milliseconds: 300),
    snapToEnd: true,
  );
  static const _wobble = Motion.bouncySpring(
    duration: Duration(milliseconds: 600),
  );

  /// The loupe's overdrag past the first and last tab approaches this many
  /// tabs.
  static const _overdragLimit = .3;

  late final _position = SingleMotionController(
    motion: _settle,
    vsync: this,
    initialValue: widget.selectedIndex.toDouble(),
  );
  late final _press = SingleMotionController(motion: _thickness, vsync: this);
  late final _jelly = SingleMotionController(motion: _wobble, vsync: this);
  late final _stretch = MotionController<Offset>(
    motion: _follow,
    vsync: this,
    converter: const OffsetMotionConverter(),
    initialValue: Offset.zero,
  );
  late final _selection = TabSelection(
    position: _position,
    press: _press,
    jelly: _jelly,
    tabCount: widget.tabs.length,
    backdropShrink: widget.loupeSettings.backdropShrink,
  );
  late final _barTransform = Listenable.merge([_press, _stretch]);
  final _showLoupe = ValueNotifier(false);
  final _loupeVisibility = ValueNotifier<double>(0);

  late int _selected = widget.selectedIndex;
  late int _target = widget.selectedIndex;
  Size _size = Size.zero;

  bool _held = false;
  bool _dragging = false;
  double _pressTarget = 0;

  /// The finger's last position in tabs, without rubber banding.
  double _finger = 0;

  /// The latest drag position the springs have not been retargeted to yet.
  Offset? _pendingDrag;
  int? _pendingDragFrame;

  int get _lastTab => widget.tabs.length - 1;
  double get _slot => (_size.width - 2 * _padding) / widget.tabs.length;

  /// How far the indicator may still be from its tab when the loupe settles
  /// back into the platter: 0.3 in the original bar's alignment units.
  double get _arrivalDistance => .15 * math.max(_lastTab, 1);

  @override
  void initState() {
    super.initState();
    _position.addListener(_onPositionTick);
    _press.addListener(_onPressTick);
  }

  @override
  void didUpdateWidget(LoupeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selection
      ..tabCount = widget.tabs.length
      ..backdropShrink = widget.loupeSettings.backdropShrink;
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _selected = widget.selectedIndex;
      if (!_held) _moveTo(_selected);
    }
  }

  @override
  void dispose() {
    _cancelPendingDrag();
    _position
      ..removeListener(_onPositionTick)
      ..dispose();
    _press
      ..removeListener(_onPressTick)
      ..dispose();
    _jelly.dispose();
    _stretch.dispose();
    _showLoupe.dispose();
    _loupeVisibility.dispose();
    super.dispose();
  }

  void _onPositionTick() {
    _jelly.animateTo(_position.velocity);
    _updatePress();
  }

  void _onPressTick() {
    _loupeVisibility.value = _press.value.clamp(0.0, 1.0);
    _showLoupe.value = _pressTarget == 1 || _press.value > .005;
  }

  /// Keeps the loupe up while held and until the indicator has nearly
  /// reached its tab.
  void _updatePress() {
    final show = _held || (_position.value - _target).abs() > _arrivalDistance;
    final target = show ? 1.0 : 0.0;
    if (target == _pressTarget) return;
    _pressTarget = target;
    _press.animateTo(target);
    _onPressTick();
  }

  /// The tab position under [local], undoing the bar's swell about its
  /// center.
  double _positionAt(Offset local) {
    final scale = 1 + widget.pressScale * math.max(_press.value, 0);
    final center = _size.width / 2;
    final x = center + (local.dx - center) / scale;
    return (x - _padding) / _slot - .5;
  }

  int _tabAt(Offset local) => _positionAt(local).round().clamp(0, _lastTab);

  /// Resists overdrag like a scroll view edge: nearly 1:1 at first,
  /// approaching [_overdragLimit].
  static double _rubberBand(double overdrag) {
    final resisted = overdrag.abs() * .5;
    return overdrag.sign * resisted / (1 + resisted / _overdragLimit);
  }

  /// Retargets [controller], switching to [motion] only if it differs:
  /// setting a motion restarts the running simulation.
  static void _springTo<T extends Object>(
    MotionController<T> controller,
    Motion motion,
    T target,
  ) {
    if (controller.motion != motion) controller.motion = motion;
    controller.animateTo(target);
  }

  void _track(Offset local, {required Motion motion}) {
    _finger = _positionAt(local);
    final clamped = _finger.clamp(0.0, _lastTab.toDouble());
    final overdrag = _finger - clamped;
    _springTo(_position, motion, clamped + _rubberBand(overdrag));

    // Pulling past the capsule stretches it toward that side, which is how it
    // reaches and merges with a neighboring segment.
    final below = local.dy - widget.height;
    final overY = local.dy < 0 ? local.dy : (below > 0 ? below : 0.0);
    _springTo(
      _stretch,
      _follow,
      Offset(overdrag * _slot, overY).withResistance(.08) * .5,
    );
  }

  void _onDown(DragDownDetails details) {
    if (_size.isEmpty) return;
    _cancelPendingDrag();
    _held = true;
    _dragging = false;
    _track(details.localPosition, motion: _settle);
    _updatePress();
  }

  void _onDragUpdate(Offset local) {
    if (!_held) return;
    _dragging = true;
    _finger = _positionAt(local);
    final scheduled = _pendingDrag != null;
    _pendingDrag = local;
    if (!scheduled) {
      _pendingDragFrame = SchedulerBinding.instance.scheduleFrameCallback(
        _flushDrag,
      );
    }
  }

  /// Retargets the springs to the latest drag position, once per frame.
  ///
  /// `animateTo` restarts a spring, and one restarted outside a frame starts
  /// its clock on the next frame, which still shows the start value. Drag
  /// updates arrive about once per frame, so retargeting on each of them
  /// held the loupe still until the finger stopped. Restarted during a
  /// frame, the spring advances on the very next one.
  void _flushDrag(Duration timeStamp) {
    final local = _pendingDrag;
    _pendingDrag = null;
    _pendingDragFrame = null;
    if (local != null && _held) _track(local, motion: _follow);
  }

  void _cancelPendingDrag() {
    if (_pendingDragFrame case final id?) {
      SchedulerBinding.instance.cancelFrameCallbackWithId(id);
    }
    _pendingDrag = null;
    _pendingDragFrame = null;
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_held) return;
    final velocity = details.velocity.pixelsPerSecond.dx / _slot;
    final nearest = _finger.round().clamp(0, _lastTab);
    var target = nearest;
    // A flick carries at least one tab further, projected 0.3 s ahead.
    if (velocity.abs() > .5 * math.max(_lastTab, 1)) {
      target = (_finger + velocity * .3).round().clamp(0, _lastTab);
      if (velocity > 0 && target <= nearest && nearest < _lastTab) {
        target = nearest + 1;
      } else if (velocity < 0 && target >= nearest && nearest > 0) {
        target = nearest - 1;
      }
    }
    _release(target);
  }

  void _onCancel() {
    if (!_held) return;
    _release(_dragging ? _finger.round().clamp(0, _lastTab) : _selected);
  }

  void _release(int tab) {
    _cancelPendingDrag();
    _held = false;
    _dragging = false;
    _springTo(_stretch, _settle, Offset.zero);
    _moveTo(tab);
    _select(tab);
  }

  void _moveTo(int tab) {
    _target = tab;
    _springTo(_position, _settle, tab.toDouble());
    _updatePress();
  }

  void _select(int tab) {
    if (tab == _selected) return;
    setState(() => _selected = tab);
    widget.onSelected?.call(tab);
  }

  void _activate(int tab) {
    _moveTo(tab);
    _select(tab);
  }

  /// The bar's swell and stretch, both about its center.
  Matrix4 _barMatrix(Size size) {
    final swell = 1 + widget.pressScale * math.max(_press.value, 0);
    final stretch = _stretch.value;
    final (x, y) = _stretchScale(stretch, size);
    final center = size.center(Offset.zero) + stretch * 1.5;
    return Matrix4.translationValues(center.dx, center.dy, 0)
      ..scaleByDouble(x * swell, y * swell, 1, 1)
      ..translateByDouble(-size.width / 2, -size.height / 2, 0, 1);
  }

  /// Volume-preserving stretch for an offset in pixels, as
  /// [RawLiquidStretch] computes it.
  static (double, double) _stretchScale(Offset stretch, Size size) {
    if (stretch == Offset.zero || size.isEmpty) return (1, 1);
    final rx = stretch.dx.abs() / size.width;
    final ry = stretch.dy.abs() / size.height;
    final baseX = 1 + rx;
    final baseY = 1 + ry;
    final volume = 1 + math.sqrt(rx * rx + ry * ry) * .5;
    final correction = math.sqrt(volume / (baseX * baseY));
    return (baseX * correction, baseY * correction);
  }

  @override
  Widget build(BuildContext context) {
    final tint = CupertinoTheme.of(context).primaryColor;
    final platter = _platterColor.resolveFrom(context);
    return MotionBuilder(
      motion: const CupertinoMotion.smooth(),
      converter: const ColorRgbMotionConverter(),
      value: CupertinoColors.label.resolveFrom(context),
      builder: (context, label, _) => LayoutBuilder(
        builder: (context, constraints) {
          _size = Size(constraints.maxWidth, widget.height);
          final bar = LiquidGlass.grouped(
            shape: LiquidRoundedSuperellipse(borderRadius: widget.height / 2),
            clipBehavior: Clip.none,
            appearance: widget.appearance,
            shadows: widget.shadows,
            child: SizedBox.fromSize(
              size: _size,
              child: Padding(
                padding: const EdgeInsets.all(_padding),
                child: RepaintBoundary(
                  child: _buildRows(label: label, tint: tint, platter: platter),
                ),
              ),
            ),
          );
          final loupe = _buildLoupe();
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _release(_tabAt(details.localPosition)),
            onHorizontalDragDown: _onDown,
            onHorizontalDragStart: (details) =>
                _onDragUpdate(details.localPosition),
            onHorizontalDragUpdate: (details) =>
                _onDragUpdate(details.localPosition),
            onHorizontalDragEnd: _onDragEnd,
            onHorizontalDragCancel: _onCancel,
            child: ListenableTransform(
              listenable: _barTransform,
              transform: _barMatrix,
              // Fake glass cannot sample what is painted above its own
              // backdrop filter, so a fake loupe sits beneath the capsule.
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  if (widget.fake) loupe,
                  bar,
                  if (!widget.fake) loupe,
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRows({
    required Color label,
    required Color tint,
    required Color platter,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: TabPlatterPainter(_selection, color: platter)),
        ClipPath(
          clipper: TabSelectionClipper(_selection, inverse: true),
          child: _buildRow(label, semantics: true),
        ),
        IgnorePointer(
          child: ExcludeSemantics(
            child: ClipPath(
              clipper: TabSelectionClipper(_selection),
              child: ListenableTransform(
                listenable: _selection.listenable,
                transform: (size) => scaleAbout(
                  _selection.rect(size).center,
                  _selection.tintScale,
                ),
                child: _buildRow(tint),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(Color color, {bool semantics = false}) {
    return Row(
      children: [
        for (final (index, tab) in widget.tabs.indexed)
          Expanded(
            child: Semantics(
              container: semantics,
              button: semantics,
              selected: semantics && index == _selected,
              label: semantics ? tab.label : null,
              onTap: semantics ? () => _activate(index) : null,
              excludeSemantics: true,
              child: RepaintBoundary(
                child: _TabItem(tab: tab, color: color),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildLoupe() {
    return Positioned.fill(
      child: IgnorePointer(
        child: ValueListenableBuilder(
          valueListenable: _showLoupe,
          builder: (context, show, loupe) =>
              show ? loupe! : const SizedBox.shrink(),
          child: CustomSingleChildLayout(
            delegate: LoupeLayoutDelegate(_selection, padding: _padding),
            child: ListenableTransform(
              listenable: _jelly,
              transform: (size) {
                final (:x, :y) = _selection.jellyScale;
                return scaleAbout(size.center(Offset.zero), x, y);
              },
              child: RepaintBoundary(
                child: ValueListenableBuilder(
                  valueListenable: _loupeVisibility,
                  builder: (context, visibility, child) =>
                      LiquidGlass.withOwnLayer(
                        key: LoupeTabBar.loupeKey,
                        settings: widget.loupeSettings,
                        fake: widget.fake,
                        appearance: LiquidGlassAppearance(
                          visibility: visibility,
                        ),
                        shape: const LiquidRoundedSuperellipse(
                          borderRadius: 64,
                        ),
                        shadows: _loupeShadows,
                        child: const SizedBox.expand(),
                      ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.color});

  final BottomBarTab tab;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(tab.icon, color: color, size: 24),
        const SizedBox(height: 2),
        Text(
          tab.label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.visible,
          style: TextStyle(
            color: color,
            fontSize: 10,
            fontWeight: FontWeight.w600,
            letterSpacing: 0,
          ),
        ),
      ],
    );
  }
}
