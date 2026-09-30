import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
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
/// snaps to a tab on release.
///
/// Must be inside a [LiquidGlassBlendGroup], which the capsule joins so it
/// can merge with neighboring bar segments. The loupe renders in its own
/// small glass layer, mounted only while it is visible, because it has to
/// refract the capsule and the icons painted beneath it.
///
/// While the indicator moves, nothing rebuilds or re-lays out: the platter,
/// the tint mask, the icon scale and the loupe transform read the motion
/// controllers at paint time. Only the loupe's own transform and fade go
/// through small builders.
class LoupeTabBar extends StatefulWidget {
  const LoupeTabBar({
    required this.tabs,
    this.selectedIndex = 0,
    this.onSelected,
    this.appearance,
    this.shadows = const [],
    this.fake = false,
    this.height = 62,
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

  /// Settings of the loupe's own glass layer.
  ///
  /// Apple's loupe appears to shrink what it covers slightly; set
  /// `magnification` here for that. Never enlarge: the
  /// icons already scale up while the bar is held.
  final LiquidGlassSettings loupeSettings;

  /// Clear, unfrosted lens with a wide bevel, after the loupe in the original
  /// example bottom bar (`test/support/bottom_bar.dart`), without its
  /// magnification.
  static const defaultLoupeSettings = LiquidGlassSettings(
    refractionHeight: 24,
    refractionAmount: 40,
    chromaticAberration: .1,
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
  static const _settle = Motion.snappySpring(
    duration: Duration(milliseconds: 450),
    extraBounce: .1,
    snapToEnd: true,
  );
  static const _pressIn = Motion.snappySpring(
    duration: Duration(milliseconds: 300),
    snapToEnd: true,
  );
  static const _pressOut = Motion.smoothSpring(
    duration: Duration(milliseconds: 400),
    snapToEnd: true,
  );
  static const _stretchBack = Motion.bouncySpring(snapToEnd: true);

  /// Movement before a press becomes a drag.
  static const _dragSlop = 4.0;

  /// The loupe's overdrag past the first and last tab approaches this many
  /// tabs.
  static const _overdragLimit = .3;

  late final _position = SingleMotionController(
    motion: _settle,
    vsync: this,
    initialValue: widget.selectedIndex.toDouble(),
  );
  late final _press = SingleMotionController(motion: _pressIn, vsync: this);
  late final _stretch = MotionController<Offset>(
    motion: _follow,
    vsync: this,
    converter: const OffsetMotionConverter(),
    initialValue: Offset.zero,
  );
  late final _selection = TabSelection(
    position: _position,
    press: _press,
    tabCount: widget.tabs.length,
  );
  final _showLoupe = ValueNotifier(false);

  late int _selected = widget.selectedIndex;
  double _rowWidth = 0;

  int? _pointer;
  Offset _down = Offset.zero;
  bool _dragging = false;
  VelocityTracker? _tracker;

  int get _lastTab => widget.tabs.length - 1;
  double get _slot => _rowWidth / widget.tabs.length;

  @override
  void initState() {
    super.initState();
    _press.addListener(_updateLoupe);
  }

  @override
  void didUpdateWidget(LoupeTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selection.tabCount = widget.tabs.length;
    if (widget.selectedIndex != oldWidget.selectedIndex) {
      _selected = widget.selectedIndex;
      if (_pointer == null) {
        _position
          ..motion = _settle
          ..animateTo(_selected.toDouble());
      }
    }
  }

  @override
  void dispose() {
    _press.removeListener(_updateLoupe);
    _position.dispose();
    _press.dispose();
    _stretch.dispose();
    _showLoupe.dispose();
    super.dispose();
  }

  void _updateLoupe() =>
      _showLoupe.value = _pointer != null || _press.value > .005;

  int _tabAt(Offset local) =>
      ((local.dx - _padding) / _slot).floor().clamp(0, _lastTab);

  double _positionAt(Offset local) => (local.dx - _padding) / _slot - .5;

  /// Resists overdrag like a scroll view edge: nearly 1:1 at first,
  /// approaching [_overdragLimit].
  static double _rubberBand(double overdrag) {
    final resisted = overdrag.abs() * .5;
    return overdrag.sign * resisted / (1 + resisted / _overdragLimit);
  }

  void _onDown(PointerDownEvent event) {
    if (_pointer != null || _rowWidth == 0) return;
    _pointer = event.pointer;
    _dragging = false;
    _down = event.localPosition;
    _tracker = VelocityTracker.withKind(event.kind)
      ..addPosition(event.timeStamp, event.localPosition);
    _updateLoupe();
    _press
      ..motion = _pressIn
      ..animateTo(1);
    _position
      ..motion = _settle
      ..animateTo(_tabAt(event.localPosition).toDouble());
  }

  void _onMove(PointerMoveEvent event) {
    if (event.pointer != _pointer) return;
    final local = event.localPosition;
    _tracker!.addPosition(event.timeStamp, local);
    if (!_dragging) {
      if ((local - _down).distance < _dragSlop) return;
      _dragging = true;
    }
    final raw = _positionAt(local);
    final clamped = raw.clamp(0.0, _lastTab.toDouble());
    final overdrag = raw - clamped;
    _position
      ..motion = _follow
      ..animateTo(clamped + _rubberBand(overdrag));

    // Pulling past the capsule stretches it toward that side, which is how it
    // reaches and merges with a neighboring segment.
    final below = local.dy - widget.height;
    final overY = local.dy < 0 ? local.dy : (below > 0 ? below : 0.0);
    _stretch
      ..motion = _follow
      ..animateTo(Offset(overdrag * _slot, overY).withResistance(.08) * .5);
  }

  void _onUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    if (!_dragging) {
      _release(_tabAt(_down));
      return;
    }
    final velocity = _tracker!.getVelocity().pixelsPerSecond.dx / _slot;
    final projected = _positionAt(event.localPosition) + velocity * .08;
    _release(projected.round().clamp(0, _lastTab));
  }

  void _onCancel(PointerCancelEvent event) {
    if (event.pointer != _pointer) return;
    _release(
      _dragging ? _position.value.round().clamp(0, _lastTab) : _selected,
    );
  }

  void _release(int tab) {
    _pointer = null;
    _tracker = null;
    _dragging = false;
    _position
      ..motion = _settle
      ..animateTo(tab.toDouble());
    _press
      ..motion = _pressOut
      ..animateTo(0);
    _stretch
      ..motion = _stretchBack
      ..animateTo(Offset.zero);
    _updateLoupe();
    _select(tab);
  }

  void _activate(int tab) {
    _position
      ..motion = _settle
      ..animateTo(tab.toDouble());
    _select(tab);
  }

  void _select(int tab) {
    if (tab == _selected) return;
    setState(() => _selected = tab);
    widget.onSelected?.call(tab);
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
          final size = Size(constraints.maxWidth, widget.height);
          _rowWidth = size.width - 2 * _padding;
          final rowSize = Size(_rowWidth, size.height - 2 * _padding);
          final bar = LiquidGlass.grouped(
            shape: LiquidRoundedSuperellipse(borderRadius: size.height / 2),
            clipBehavior: Clip.none,
            appearance: widget.appearance,
            shadows: widget.shadows,
            child: SizedBox.fromSize(
              size: size,
              child: Padding(
                padding: const EdgeInsets.all(_padding),
                child: RepaintBoundary(
                  child: _buildRows(label: label, tint: tint, platter: platter),
                ),
              ),
            ),
          );
          final loupe = _buildLoupe(rowSize);
          return Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onDown,
            onPointerMove: _onMove,
            onPointerUp: _onUp,
            onPointerCancel: _onCancel,
            child: ListenableBuilder(
              listenable: _stretch,
              builder: (context, child) =>
                  RawLiquidStretch(stretchPixels: _stretch.value, child: child),
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
              child: _buildRow(tint),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRow(Color color, {bool semantics = false}) {
    return Flow(
      delegate: TabRowDelegate(_selection),
      children: [
        for (final (index, tab) in widget.tabs.indexed)
          Semantics(
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
      ],
    );
  }

  Widget _buildLoupe(Size rowSize) {
    final loupeSize = _selection.restingRect(rowSize, pressAmount: 1).size;
    return Positioned(
      left: _padding,
      top: _padding,
      width: loupeSize.width,
      height: loupeSize.height,
      child: IgnorePointer(
        child: ValueListenableBuilder(
          valueListenable: _showLoupe,
          builder: (context, show, loupe) =>
              show ? loupe! : const SizedBox.shrink(),
          child: RepaintBoundary(
            child: ListenableBuilder(
              listenable: _selection.listenable,
              builder: (context, child) {
                final rect = _selection.rect(rowSize);
                return Transform(
                  transform: Matrix4.translationValues(rect.left, rect.top, 0)
                    ..scaleByDouble(
                      rect.width / loupeSize.width,
                      rect.height / loupeSize.height,
                      1,
                      1,
                    ),
                  child: child,
                );
              },
              child: ListenableBuilder(
                listenable: _press,
                builder: (context, _) => LiquidGlass.withOwnLayer(
                  key: LoupeTabBar.loupeKey,
                  settings: widget.loupeSettings,
                  fake: widget.fake,
                  appearance: LiquidGlassAppearance(
                    visibility: _press.value.clamp(0.0, 1.0),
                  ),
                  shape: LiquidRoundedSuperellipse(
                    borderRadius: loupeSize.height / 2,
                  ),
                  shadows: _loupeShadows,
                  child: const SizedBox.expand(),
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
