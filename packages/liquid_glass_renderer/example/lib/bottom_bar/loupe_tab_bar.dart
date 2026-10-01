import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/listenable_transform.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/tab_selection.dart';
import 'package:liquid_glass_renderer_example/bottom_bar/vibrant_tint.dart';
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
/// refract the capsule and the icons painted beneath it. Like Apple's, it
/// shows the bar a little smaller through its `backdropShrink`, and the
/// tinted icons under it are scaled up by the same amount so they keep their
/// size.
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
    this.pressScale = 1.042,
    this.tint,
    this.tintBrightness,
    this.loupeSettings = defaultLoupeSettings,
    this.loupeIconScale = 1.1,
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

  /// How much the whole bar grows while held; the iOS 27 tab bar grows by
  /// 4.2%.
  final double pressScale;

  /// Color of the selected tab, or `null` for the theme's primary color.
  ///
  /// It blends with the glass per pixel ([vibrantTintPaints]), so it
  /// follows the backdrop instantly and shows its detail.
  final Color? tint;

  /// The appearance the [tint] is matched to, or `null` for the theme's.
  ///
  /// Pass the app's appearance when the theme around the bar follows an
  /// estimated backdrop brightness: the blend already adapts per pixel, and
  /// the estimate lags behind the backdrop.
  final Brightness? tintBrightness;

  /// Settings of the loupe's own glass layer.
  ///
  /// Its `backdropShrink` is how much smaller the bar looks inside the loupe.
  final LiquidGlassSettings loupeSettings;

  /// How much larger the tinted icons in the loupe look than the others.
  ///
  /// Grows in with the loupe, so the resting platter's icons keep their
  /// size.
  final double loupeIconScale;

  /// A clear, unfrosted lens like the iOS 27 tab bar's: it shows the bar
  /// 14% smaller and bends and splits the colors only in a 3–4 pt band along
  /// its rim, strongly enough there to fold the content, like Apple's.
  static const defaultLoupeSettings = LiquidGlassSettings(
    refractionHeight: 15,
    refractionAmount: 10,
    refractionFitsShape: false,
    dispersion: -.3,
    frost: 0,
    contourStrength: .3,
    backdropShrink: 0.14,
  );

  static const loupeKey = ValueKey('loupe-tab-bar-loupe');

  @override
  State<LoupeTabBar> createState() => _LoupeTabBarState();
}

class _LoupeTabBarState extends State<LoupeTabBar>
    with TickerProviderStateMixin {
  /// Inset of the tab row from the capsule, as on iOS 27: 9 pt from the
  /// ends to the first and last slot, and 4 pt from the top and bottom,
  /// which leaves the 54 pt platter about 4.5 pt of glass on every side.
  static const _padding = EdgeInsets.symmetric(horizontal: 9, vertical: 4);

  /// The resting platter over light glass: 231 over white glass, as on
  /// iOS 27.
  static const _lightPlatter = [(Color(0x14000000), BlendMode.srcOver)];

  /// The resting platter over dark glass, which iOS 27 darkens more the
  /// darker the glass is: 185 → 143 over white content and 32 → 10 over
  /// black. Multiplying by 0.87 and then taking the difference to 0.07
  /// reproduces both.
  static const _darkPlatter = [
    (Color(0xFFDEDEDE), BlendMode.multiply),
    (Color(0xFF121212), BlendMode.difference),
  ];

  /// Pulling past either end stretches the bar sideways by at most
  /// `1 / _stretchResistance` points, 10–12 pt for a long pull as on iOS 27.
  static const _stretchResistance = 1 / 12;

  static const _follow = Motion.interactiveSpring(snapToEnd: true);
  static const _settle = Motion.bouncySpring(snapToEnd: true);

  /// Grows the loupe and swells the bar without overshooting; the loupe only
  /// wobbles when it moves.
  static const _thickness = Motion.smoothSpring(
    duration: Duration(milliseconds: 300),
    snapToEnd: true,
  );

  /// Flattens the loupe as the indicator speeds up.
  static const _squash = Motion.cupertino(
    duration: Duration(milliseconds: 150),
  );

  /// Springs the loupe's shape back to rest, fitted to the iOS 27 loupe
  /// timeline in `tool/apple_match/references/ios27-iphone17pro-bottom-bar/`
  /// (`loupe-dynamics/`): damping
  /// ratio 0.55 with a 0.74 s period (1.35 Hz), so it passes rest once and
  /// comes back with an undershoot 1/7.8 the size of the overshoot.
  static const _recover = Motion.cupertino(
    duration: Duration(milliseconds: 618),
    bounce: .45,
  );
  late final _position = SingleMotionController(
    motion: _settle,
    vsync: this,
    initialValue: widget.selectedIndex.toDouble(),
  );
  late final _press = SingleMotionController(motion: _thickness, vsync: this);
  late final _jelly = SingleMotionController(motion: _recover, vsync: this);
  double _jellyTarget = 0;

  /// The strongest flattening since the loupe last sprang back.
  double _speedPeak = 0;
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
    iconScale: widget.loupeIconScale,
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
  double get _slot => (_size.width - _padding.horizontal) / widget.tabs.length;

  /// How far the indicator may still be from its tab when the loupe settles
  /// back into the platter: 0.3 in the original bar's alignment units.
  double get _arrivalDistance => .15 * math.max(_lastTab, 1);

  @override
  void initState() {
    super.initState();
    _position
      ..addListener(_onPositionTick)
      ..addStatusListener(_onPositionStatus);
    _press.addListener(_onPressTick);
  }

  @override
  void didUpdateWidget(LoupeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selection
      ..tabCount = widget.tabs.length
      ..backdropShrink = widget.loupeSettings.backdropShrink
      ..iconScale = widget.loupeIconScale;
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
      ..removeStatusListener(_onPositionStatus)
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
    final speed = _position.velocity.abs() * _slot;
    final target = TabSelection.jellyTarget(speed);
    if (target > _speedPeak && target > .05) {
      // Flattening follows the indicator while it speeds up.
      _speedPeak = target;
      if (target - _jellyTarget > .01) {
        _jellyTarget = target;
        _springTo(_jelly, _squash, target);
      }
    } else if (_jellyTarget != 0 && target < _speedPeak * .85) {
      // Once it slows down, the shape springs straight back to rest instead
      // of following the speed down, so it overshoots and rings out.
      _speedPeak = 0;
      _jellyTarget = 0;
      _springTo<double>(_jelly, _recover, 0);
    }
    _updatePress();
  }

  /// The indicator has come to rest, so the loupe springs back even if the
  /// last tick still reported some speed.
  void _onPositionStatus(AnimationStatus status) {
    if (status.isAnimating || _jellyTarget == 0) return;
    _speedPeak = 0;
    _jellyTarget = 0;
    _springTo<double>(_jelly, _recover, 0);
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
    final scale = _swell;
    final center = _size.width / 2;
    final x = center + (local.dx - center) / scale;
    return (x - _padding.left) / _slot - .5;
  }

  int _tabAt(Offset local) => _positionAt(local).round().clamp(0, _lastTab);

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
    // The loupe stays within the bar.
    _springTo(_position, motion, clamped);

    // Pulling past either end gives the capsule a little toward that side.
    final dx = local.dx;
    final past = dx < 0 ? dx : math.max(dx - _size.width, 0).toDouble();
    _springTo(
      _stretch,
      _follow,
      Offset(past, 0).withResistance(_stretchResistance),
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

  double get _swell => 1 + (widget.pressScale - 1) * math.max(_press.value, 0);

  /// The bar's swell and stretch, both about its center.
  Matrix4 _barMatrix(Size size) {
    final swell = _swell;
    final stretch = _stretch.value;
    final (x, y) = _stretchScale(stretch, size);
    // Half the stretch keeps the far edge in place.
    final center = size.center(Offset.zero) + stretch / 2;
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
    final tint = widget.tint ?? CupertinoTheme.of(context).primaryColor;
    final tintBrightness =
        widget.tintBrightness ?? CupertinoTheme.brightnessOf(context);
    final platter = CupertinoTheme.brightnessOf(context) == Brightness.dark
        ? _darkPlatter
        : _lightPlatter;
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
                padding: _padding,
                child: RepaintBoundary(
                  child: _buildRows(
                    label: label,
                    tint: tint,
                    tintBrightness: tintBrightness,
                    platter: platter,
                  ),
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
    required Brightness tintBrightness,
    required List<(Color, BlendMode)> platter,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: TabPlatterPainter(_selection, layers: platter)),
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
                child: _buildRow(
                  tint,
                  foregrounds: vibrantTintPaints(tint, tintBrightness),
                  magnify: true,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(
    Color color, {
    bool semantics = false,
    List<Paint>? foregrounds,
    bool magnify = false,
  }) {
    Widget item(BottomBarTab tab) {
      final child = RepaintBoundary(
        child: _TabItem(tab: tab, color: color, foregrounds: foregrounds),
      );
      if (!magnify) return child;
      return ListenableTransform(
        listenable: _press,
        transform: (size) =>
            scaleAbout(size.center(Offset.zero), _selection.iconGrowth),
        child: child,
      );
    }

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
              child: item(tab),
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
                  builder: (context, visibility, child) => CustomPaint(
                    painter: _LoupeShadowPainter(visibility),
                    child: LiquidGlass.withOwnLayer(
                      key: LoupeTabBar.loupeKey,
                      settings: widget.loupeSettings,
                      fake: widget.fake,
                      appearance: LiquidGlassAppearance(
                        visibility: visibility,
                      ),
                      shape: const LiquidRoundedSuperellipse(
                        borderRadius: 64,
                      ),
                      child: const SizedBox.expand(),
                    ),
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

/// The loupe's soft shadow, painted only outside it.
///
/// A glass shadow would lie beneath the loupe's own layer, which captures
/// and shows it, dimming the whole lens; Apple's loupe is as bright inside
/// as the bar.
class _LoupeShadowPainter extends CustomPainter {
  const _LoupeShadowPainter(this.visibility);

  final double visibility;

  static const _shadow = BoxShadow(color: Color(0x1A000000), blurRadius: 30);

  @override
  void paint(Canvas canvas, Size size) {
    final opacity = visibility.clamp(0.0, 1.0);
    if (opacity == 0) return;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(size.shortestSide / 2),
    );
    final paint = _shadow.toPaint()
      ..color = _shadow.color.withValues(alpha: _shadow.color.a * opacity);
    canvas
      ..save()
      ..clipPath(
        Path()
          ..addRect(rrect.outerRect.inflate(_shadow.blurRadius * 2))
          ..addRRect(rrect)
          ..fillType = PathFillType.evenOdd,
      )
      ..drawRRect(rrect, paint)
      ..restore();
  }

  @override
  bool shouldRepaint(_LoupeShadowPainter oldDelegate) =>
      oldDelegate.visibility != visibility;
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.tab, required this.color, this.foregrounds});

  final BottomBarTab tab;
  final Color color;

  /// Paints the glyphs are drawn with, one over the other, or `null` to
  /// paint [color] over what is beneath them.
  final List<Paint>? foregrounds;

  @override
  Widget build(BuildContext context) {
    final paints = foregrounds ?? <Paint?>[null];
    final icon = tab.icon;
    Widget layered(Widget Function(Paint? foreground) glyph) =>
        paints.length == 1
        ? glyph(paints.single)
        : Stack(
            alignment: Alignment.center,
            children: [for (final paint in paints) glyph(paint)],
          );
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // An Icon cannot take a paint, so the glyph is laid out as Icon does.
        SizedBox.square(
          dimension: 24,
          child: layered(
            (foreground) => Center(
              child: Text(
                String.fromCharCode(icon.codePoint),
                overflow: TextOverflow.visible,
                style: TextStyle(
                  inherit: false,
                  color: foreground == null ? color : null,
                  foreground: foreground,
                  fontSize: 24,
                  fontFamily: icon.fontFamily,
                  package: icon.fontPackage,
                  fontFamilyFallback: icon.fontFamilyFallback,
                  height: 1,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        layered(
          (foreground) => Text(
            tab.label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: TextStyle(
              color: foreground == null ? color : null,
              foreground: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0,
            ),
          ),
        ),
      ],
    );
  }
}
