import 'dart:async';
import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:apple_liquid_glass_example/widgets.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Glass drops floating over a drifting wallpaper. A finger lifts a drop and
/// drags it; drops that come close fuse into one body, and a released drop
/// flies home on a bouncy spring with the finger's momentum. Each drop is a
/// `Motion` of its own that follows its finger through an `InputRegion`,
/// every command at the input's stamp.
///
/// The drops and the wallpaper move for a while after the page shows or a
/// finger touches it, then come to rest, so a page nobody touches draws no
/// frames.
class LiquidPage extends StatefulWidget {
  const LiquidPage({super.key});

  @override
  State<LiquidPage> createState() => _LiquidPageState();
}

class _LiquidPageState extends State<LiquidPage> {
  static const _float = Spring(duration: Duration(milliseconds: 3200));
  static const _awake = Duration(seconds: 12);

  final _random = math.Random(7);
  var _wallpaper = Wallpaper.aurora;
  var _clear = true;
  var _fusion = 28.0;
  late final List<_Drop> _drops = [
    _Drop(
      home: const Alignment(-0.45, -0.22),
      size: (w) => Size.square(w * 0.36),
      child: const Icon(
        CupertinoIcons.drop_fill,
        size: 44,
        color: Color(0xFFFFFFFF),
      ),
    ),
    _Drop(
      home: const Alignment(0.55, -0.3),
      size: (w) => Size.square(w * 0.22),
      shape: const LiquidRoundedSuperellipse(radius: 26),
      child: const Icon(
        CupertinoIcons.sparkles,
        size: 30,
        color: Color(0xFFFFFFFF),
      ),
    ),
    _Drop(
      home: const Alignment(0.3, 0.08),
      size: (w) => Size(w * 0.52, 68),
      child: const PhotoText('Liquid', size: 26, weight: FontWeight.w600),
    ),
    _Drop(
      home: const Alignment(-0.55, 0.4),
      size: (w) => Size.square(w * 0.2),
      child: const Icon(
        CupertinoIcons.heart_fill,
        size: 26,
        color: Color(0xFFFFFFFF),
      ),
    ),
    _Drop(
      home: const Alignment(0.35, 0.5),
      size: (w) => Size.square(w * 0.28),
      child: const Icon(
        CupertinoIcons.moon_stars_fill,
        size: 34,
        color: Color(0xFFFFFFFF),
      ),
    ),
  ];
  late final _pool = _Pool(_drops);
  late final List<Interaction> _wakers = [FollowInteraction(_Waker(this))];
  Size _size = Size.zero;
  Timer? _floating;
  Timer? _asleep;
  var _drifting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (TickerMode.valuesOf(context).enabled) {
      _wake();
    } else {
      _rest();
    }
  }

  @override
  void dispose() {
    _floating?.cancel();
    _asleep?.cancel();
    super.dispose();
  }

  void _wake() {
    _asleep?.cancel();
    _asleep = Timer(_awake, () => setState(_rest));
    if (_drifting) return;
    _drifting = true;
    _floating = Timer.periodic(
      const Duration(milliseconds: 2600),
      (_) => _drift(),
    );
    _drift();
  }

  void _rest() {
    _floating?.cancel();
    _asleep?.cancel();
    if (!_drifting) return;
    _drifting = false;
    final t = MotionClock.instance.now;
    for (final drop in _drops) {
      drop.driftTo(t, Offset.zero, _float);
    }
  }

  void _drift() {
    final t = MotionClock.instance.now;
    for (final drop in _drops) {
      drop.driftTo(
        t,
        Offset(_random.nextDouble() * 18 - 9, _random.nextDouble() * 18 - 9),
        _float,
      );
    }
  }

  void _layout(Size size) {
    if (size == _size) return;
    _size = size;
    final t = MotionClock.instance.now;
    for (final drop in _drops) {
      drop.measure(t, size);
    }
  }

  void _touched() {
    if (_drifting) {
      _wake();
    } else {
      setState(_wake);
    }
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: SystemUiOverlayStyle.light,
    child: GlassPageScaffold(
      navigationBar: GlassNavigationBar(
        largeTitle: const Text('Liquid'),
        trailing: [
          GlassBarItem(
            icon: const Icon(CupertinoIcons.paintbrush),
            semanticLabel: 'Look',
            menuChildren: _menu(context),
          ),
          settingsItem(context),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DriftingWallpaper(wallpaper: _wallpaper, drifts: false),
          Builder(builder: _area),
        ],
      ),
    ),
  );

  // Below the navigation bar, above the fusion row.
  Widget _area(BuildContext context) {
    final media = MediaQuery.of(context);
    final glass = _clear ? const Glass.clear() : const Glass.regular();
    return Padding(
      padding: EdgeInsets.only(
        top: media.padding.top,
        bottom: media.padding.bottom + 16,
      ),
      child: Column(
        children: [
          Expanded(
            child: MotionScope(
              motion: _pool,
              child: InputRegion(
                interactions: _wakers,
                child: ColoredBox(
                  color: const Color(0x00000000),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      _layout(constraints.biggest);
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          GlassGroup(
                            merge: _fusion < 1
                                ? const GlassMerge.none()
                                : GlassMerge.spacing(_fusion),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                for (final drop in _drops)
                                  Positioned.fromRect(
                                    rect: drop.origin & drop.size,
                                    child: GlassSurface.live(
                                      frame: drop.frame,
                                      glass: glass,
                                      child: Center(child: drop.child),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          for (final drop in _drops)
                            Positioned.fromRect(
                              rect: drop.grabArea,
                              child: MotionTransition(
                                offset: drop.shift,
                                child: InputRegion(
                                  interactions: drop.interactions,
                                  child: const ColoredBox(
                                    color: Color(0x00000000),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                const Icon(
                  CupertinoIcons.circle_grid_hex,
                  color: Color(0xFFFFFFFF),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GlassSlider(
                    value: _fusion,
                    max: 60,
                    semanticLabel: 'Fusion',
                    onChanged: (value) => setState(() => _fusion = value),
                  ),
                ),
                const SizedBox(width: 12),
                const Icon(
                  CupertinoIcons.drop_fill,
                  color: Color(0xFFFFFFFF),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<GlassMenuEntry> _menu(BuildContext context) {
    final renderer = GallerySettingsScope.of(context).value.renderer;
    return [
      GlassMenuSection(
        title: 'Wallpaper',
        singleSelection: true,
        children: [
          for (final wallpaper in Wallpaper.values)
            GlassMenuItem(
              title: wallpaper.title,
              state: wallpaper == _wallpaper
                  ? GlassMenuItemState.on
                  : GlassMenuItemState.off,
              onPressed: () => setState(() => _wallpaper = wallpaper),
            ),
        ],
      ),
      GlassMenuSection(
        title: 'Glass',
        singleSelection: true,
        elementSize: GlassMenuElementSize.medium,
        children: [
          GlassMenuItem(
            title: 'Regular',
            icon: const Icon(CupertinoIcons.drop_fill),
            state: _clear ? GlassMenuItemState.off : GlassMenuItemState.on,
            onPressed: () => setState(() => _clear = false),
          ),
          GlassMenuItem(
            title: 'Clear',
            icon: const Icon(CupertinoIcons.drop),
            state: _clear ? GlassMenuItemState.on : GlassMenuItemState.off,
            onPressed: () => setState(() => _clear = true),
          ),
        ],
      ),
      GlassSubmenu(
        title: 'Renderer',
        subtitle: renderer.title,
        icon: const Icon(CupertinoIcons.cube),
        singleSelection: true,
        children: [
          for (final option in GalleryRenderer.values)
            GlassMenuItem(
              title: option.title,
              state: option == renderer
                  ? GlassMenuItemState.on
                  : GlassMenuItemState.off,
              onPressed: () => GallerySettingsScope.update(
                context,
                (s) => s.copyWith(renderer: option),
              ),
            ),
        ],
      ),
    ];
  }
}

/// The drops, one motion on screen.
final class _Pool extends Motion {
  _Pool(List<_Drop> drops) {
    for (final drop in drops) {
      own(drop);
    }
  }
}

/// Wakes the page on any touch.
final class _Waker implements PointerFollower {
  _Waker(this._page);

  final _LiquidPageState _page;

  @override
  void down(PointerDownInput input) => _page._touched();

  @override
  void move(PointerMoveInput input) {}

  @override
  void up(PointerUpInput input) {}

  @override
  void cancel(PointerCancelInput input) {}

  @override
  void hover(PointerHoverInput input) {}
}

/// A drop: where it floats, how far it drifts, how pressed it is and where
/// its finger is, each a value of its own motion. It follows one finger at
/// a time, in the coordinates of its grab area.
final class _Drop extends Motion implements PointerFollower {
  _Drop({
    required this.home,
    required Size Function(double width) size,
    required this.child,
    this.shape = LiquidRoundedSuperellipse.capsule,
  }) : _sizeFor = size;

  /// How far outside its body a finger still grabs the drop.
  static const _reach = 10.0;

  final Alignment home;
  final Size Function(double width) _sizeFor;
  final LiquidShape shape;
  final Widget child;
  Size size = Size.zero;

  late final center = own(MotionValue(Offset.zero));
  late final drift = own(MotionValue(Offset.zero));
  late final press = own(MotionValue<double>(0));
  late final touch = own(MotionValue(Offset.zero));
  late final List<Interaction> interactions = [FollowInteraction(this)];
  Offset _homeCenter = Offset.zero;
  Offset _grab = Offset.zero;
  Offset _area = Offset.zero;

  /// The top left of the box the drop is laid out in, at home. The body
  /// moves inside a box of its own size, where every renderer moves the
  /// content with it the same way.
  Offset origin = Offset.zero;

  /// Where a finger grabs the drop at home; [shift] moves it with the body.
  Rect get grabArea => (origin & size).inflate(_reach);

  Offset _shiftAt(double t) =>
      center.valueAt(t) + drift.valueAt(t) - _homeCenter;

  /// How far the body stands from home.
  late final MotionSelection<Offset> shift = select((d) => d._shiftAt(d.now));

  late final MotionSelection<GlassFrame> frame = select((d) {
    final t = d.now;
    final pressed = d.press.valueAt(t);
    final scale = 1 + 0.14 * pressed;
    final local = d.center.valueAt(t) + d.drift.valueAt(t) - d.origin;
    final middle = d.size.center(Offset.zero);
    return GlassFrame(
      shape: d.shape,
      rect: Rect.fromCenter(
        center: local,
        width: d.size.width,
        height: d.size.height,
      ),
      scaleX: scale,
      scaleY: scale,
      glow: pressed < 0.01
          ? null
          : GlassTouchGlow(
              wash: 0.03 * pressed,
              center: middle + (d.touch.valueAt(t) - d.origin - local) / scale,
              radius: 0.568 * d.size.shortestSide,
              spot: 0.22 * pressed,
            ),
    );
  });

  void measure(double t, Size area) {
    advance(t);
    size = _sizeFor(area.width);
    _homeCenter = home.alongSize(area);
    origin = _homeCenter - size.center(Offset.zero);
    center.snap(t, _homeCenter);
  }

  void driftTo(double t, Offset to, Spring spring) {
    advance(t);
    drift.retarget(t, to, spring: spring);
  }

  // A finger's position in the page: its grab area stood where the body
  // stood when the finger touched.
  Offset _inPage(Offset position) => _area + position;

  @override
  void down(PointerDownInput input) {
    final t = input.time;
    advance(t);
    _area = grabArea.topLeft + _shiftAt(t);
    final finger = _inPage(input.position);
    _grab = finger - center.valueAt(t);
    touch.snap(t, finger);
    press.retarget(t, 1, spring: Spring.snappy);
    unawaited(HapticFeedback.selectionClick());
  }

  @override
  void move(PointerMoveInput input) {
    final t = input.time;
    advance(t);
    final finger = _inPage(input.position);
    touch.snap(t, finger);
    center.retarget(
      t,
      finger - _grab,
      spring: Spring.interactive,
      tracking: true,
    );
  }

  @override
  void up(PointerUpInput input) => _release(input.time, input.velocity);

  @override
  void cancel(PointerCancelInput input) => _release(input.time, Offset.zero);

  @override
  void hover(PointerHoverInput input) {}

  void _release(double t, Offset velocity) {
    advance(t);
    center.setVelocity(t, velocity);
    center.retarget(t, _homeCenter, spring: Spring.bouncy);
    press.retarget(t, 0, spring: Spring.bouncy);
  }
}
