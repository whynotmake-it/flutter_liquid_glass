import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/gallery_bar.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum _Palette {
  lava([Color(0xB3FF375F), Color(0xB3FF9F0A), Color(0xB3BF5AF2)]),
  ocean([Color(0xB30A84FF), Color(0xB364D2FF), Color(0xB330D158)]),
  aurora([Color(0xB330D158), Color(0xB3BF5AF2), Color(0xB364D2FF)]);

  const _Palette(this.tints);

  final List<Color> tints;
}

/// A lava lamp of glass. Drops warm at the bottom and rise, cool at the top
/// and sink, and fuse wherever two come close, their colors running into
/// one another across the join. A finger gathers the drops around it and
/// stirs them. The buttons add and take drops and change what they are
/// made of.
///
/// Nothing of the drops is drawn by the page: each is a glass surface that
/// reads its frame from the lamp's motion, a loop of sixty steps a second,
/// and one group fuses them and reads the lamp's light behind them once.
class LavaPage extends StatefulWidget {
  const LavaPage({super.key});

  @override
  State<LavaPage> createState() => _LavaPageState();
}

class _LavaPageState extends State<LavaPage> {
  final _lamp = _Lamp();
  var _palette = _Palette.lava;

  @override
  void initState() {
    super.initState();
    _lamp.light(MotionClock.instance.now);
  }

  void _add() => setState(_lamp.add);

  void _take() => setState(_lamp.take);

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: SystemUiOverlayStyle.light,
    child: GlassTheme(
      data: const GlassThemeData(brightness: Brightness.dark),
      child: GlassPageScaffold(
        backgroundColor: const Color(0xFF000000),
        navigationBar: GlassNavigationBar(
          title: const Text('Lava'),
          previousPageTitle: 'Surface',
          backButtonDisplayMode: GlassBackButtonDisplayMode.minimal,
          trailing: galleryItems(context),
        ),
        child: Builder(
          builder: (context) {
            final padding = MediaQuery.paddingOf(context);
            return Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: _Light(_lamp.time, _palette.tints.first),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    top: padding.top + 8,
                    bottom: padding.bottom + 76,
                  ),
                  child: _jarOf(),
                ),
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: padding.bottom + 12,
                  child: _controls(),
                ),
              ],
            );
          },
        ),
      ),
    ),
  );

  Widget _jarOf() => LayoutBuilder(
    builder: (context, constraints) {
      if (_lamp.fill(constraints.biggest)) {
        // The buttons were built before the lamp had drops to count.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() {});
        });
      }
      final tints = _palette.tints;
      return MotionScope(
        motion: _lamp,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _lamp.finger = event.localPosition,
          onPointerMove: (event) => _lamp.finger = event.localPosition,
          onPointerUp: (_) => _lamp.finger = null,
          onPointerCancel: (_) => _lamp.finger = null,
          child: GlassGroup(
            merge: const GlassMerge.spacing(30),
            child: Stack(
              fit: StackFit.expand,
              children: [
                for (final drop in _lamp.drops)
                  GlassSurface.live(
                    key: ObjectKey(drop),
                    frame: drop.selection,
                    glass: Glass.clear(
                      tint: tints[drop.color % tints.length],
                    ),
                    child: const SizedBox.expand(),
                  ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _controls() => Row(
    children: [
      GlassButton(
        onPressed: _lamp.drops.length > _Lamp.fewest ? _take : null,
        semanticLabel: 'Take a drop',
        child: const Icon(CupertinoIcons.minus),
      ),
      const SizedBox(width: 10),
      GlassButton(
        onPressed: _lamp.drops.length < _Lamp.most ? _add : null,
        semanticLabel: 'Add a drop',
        child: const Icon(CupertinoIcons.plus),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: GlassSegmentedControl<_Palette>(
          segments: const [
            GlassSegment(value: _Palette.lava, label: Text('Lava')),
            GlassSegment(value: _Palette.ocean, label: Text('Ocean')),
            GlassSegment(value: _Palette.aurora, label: Text('Aurora')),
          ],
          groupValue: _palette,
          onChanged: (palette) => setState(() => _palette = palette),
        ),
      ),
    ],
  );
}

/// The lamp: its drops and the loop that moves them, sixty steps a second
/// of motion time whatever the screen renders.
final class _Lamp extends Motion {
  _Lamp() {
    own(_loop);
  }

  static const most = 12;
  static const fewest = 2;

  late final _loop = _Convection(this);
  final _random = math.Random(11);
  final drops = <_Drop>[];
  Size _jar = Size.zero;

  /// Where a finger stirs, in the jar.
  Offset? finger;

  /// The seconds the lamp has burned, for what is painted behind it.
  late final MotionSelection<double> time = select((lamp) => lamp.now);

  void light(double t) {
    advance(t);
    _loop.wake(t);
  }

  /// Sizes the jar; true when that put the first drops in it.
  bool fill(Size jar) {
    if (jar == _jar) return false;
    final first = _jar.isEmpty;
    _jar = jar;
    if (!first) return false;
    for (var i = 0; i < 9; i++) {
      drops.add(_spawn(anywhere: true));
    }
    return true;
  }

  void add() {
    if (drops.length < most) drops.add(_spawn());
  }

  void take() {
    if (drops.length > fewest) drops.removeLast();
  }

  _Drop _spawn({bool anywhere = false}) {
    final radius = 30 + _random.nextDouble() * 34;
    return _Drop(
      this,
      radius: radius,
      color: drops.length,
      position: Offset(
        radius + _random.nextDouble() * (_jar.width - 2 * radius),
        anywhere
            ? radius + _random.nextDouble() * (_jar.height - 2 * radius)
            : _jar.height - radius,
      ),
      heat: anywhere ? _random.nextDouble() : 0.9,
    );
  }

  void _step(double dt) {
    if (_jar.isEmpty) return;
    final finger = this.finger;
    for (final drop in drops) {
      // Warm at the bottom, cool at the top; the lag between the two is
      // what keeps a lamp turning over.
      final depth = drop.position.dy / _jar.height;
      drop.heat = (drop.heat + (depth - 0.5) * 0.55 * dt).clamp(0.0, 1.0);
      var push = Offset(
        (_random.nextDouble() - 0.5) * 30,
        (0.5 - drop.heat) * 150,
      );
      if (finger != null) {
        final to = finger - drop.position;
        if (to.distance < 220) push += to * 7;
      }
      for (final other in drops) {
        if (identical(other, drop)) continue;
        final apart = drop.position - other.position;
        final near = (drop.radius + other.radius) * 0.74;
        final distance = math.max<double>(apart.distance, 1);
        // Two drops lean on each other once they share a quarter of their
        // width, so they fuse without one swallowing the other.
        if (distance < near) push += apart / distance * (near - distance) * 9;
      }
      drop.velocity = (drop.velocity + push * dt) * math.exp(-1.3 * dt);
      var at = drop.position + drop.velocity * dt;
      final r = drop.radius;
      if (at.dx < r || at.dx > _jar.width - r) {
        drop.velocity = Offset(-drop.velocity.dx * 0.3, drop.velocity.dy);
      }
      if (at.dy < r || at.dy > _jar.height - r) {
        drop.velocity = Offset(drop.velocity.dx, -drop.velocity.dy * 0.3);
      }
      at = Offset(
        at.dx.clamp(r, math.max(r, _jar.width - r)),
        at.dy.clamp(r, math.max(r, _jar.height - r)),
      );
      drop.position = at;
    }
  }
}

final class _Convection extends MotionLoop {
  // A lamp that was off the screen picks up where it stood.
  _Convection(this._lamp) : super(rate: 60, maxFrames: 4);

  final _Lamp _lamp;

  @override
  bool step(double t) {
    _lamp._step(frame);
    return true;
  }
}

/// A drop of the lamp: where it is, how fast it moves and how warm it is.
final class _Drop {
  _Drop(
    _Lamp lamp, {
    required this.radius,
    required this.color,
    required this.position,
    required this.heat,
  }) {
    selection = lamp.select((_) => _frame);
  }

  final double radius;
  final int color;
  late final MotionSelection<GlassFrame> selection;
  Offset position;
  Offset velocity = Offset.zero;
  double heat;

  // A moving drop draws out along its way.
  GlassFrame get _frame {
    final stretch = math.min(velocity.dy.abs() / 420, 0.16);
    return GlassFrame(
      shape: const LiquidOval(),
      rect: Rect.fromCircle(center: position, radius: radius),
      scaleX: 1 - stretch * 0.5,
      scaleY: 1 + stretch,
    );
  }
}

/// The lamp behind the drops: its light at the bottom and motes of dust
/// rising through it, for the glass to bend.
class _Light extends CustomPainter {
  _Light(this.time, this.light) : super(repaint: time);

  final ValueListenable<double> time;
  final Color light;

  @override
  void paint(Canvas canvas, Size size) {
    final glow = light.withValues(alpha: 1);
    final bounds = Offset.zero & size;
    canvas
      ..drawRect(bounds, Paint()..color = const Color(0xFF07040D))
      ..drawRect(
        bounds,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(0, 1.15),
            radius: 1.1,
            colors: [
              glow.withValues(alpha: 0.75),
              glow.withValues(alpha: 0.22),
              glow.withValues(alpha: 0),
            ],
            stops: const [0, 0.45, 1],
          ).createShader(bounds),
      );
    final mote = Paint();
    for (var i = 0; i < 48; i++) {
      // Each mote keeps a column and a pace of its own.
      final column = (i * 0.618034) % 1;
      final pace = 0.018 + (i * 0.37 % 1) * 0.03;
      final rise = (i * 0.271 + time.value * pace) % 1;
      final sway = math.sin(time.value * 0.4 + i) * 10;
      canvas.drawCircle(
        Offset(column * size.width + sway, (1 - rise) * size.height),
        1 + (i % 5) * 0.8,
        mote
          ..color = Color.lerp(
            glow,
            const Color(0xFFFFFFFF),
            0.5,
          )!.withValues(alpha: 0.12 + 0.3 * math.sin(rise * math.pi)),
      );
    }
  }

  @override
  bool shouldRepaint(_Light old) => old.light != light || old.time != time;
}
