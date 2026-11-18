import 'dart:async';
import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/gallery_bar.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

enum _Pattern { pulse, wave, rain }

/// Sixteen glass pads to play with every finger at once. A pressed pad
/// sinks, fills with its color and glows under the finger, and springs back
/// with a ring that spreads over the floor under the glass, where the pads
/// around it bend it. A finger that slides plays every pad it crosses. The
/// play button runs a pattern over the pads, so the page moves untouched.
///
/// Each pad is a `Motion` of two values, how pressed it is and where its
/// finger lies, and its surface reads its frame from them without a
/// rebuild.
class PadsPage extends StatefulWidget {
  const PadsPage({super.key});

  @override
  State<PadsPage> createState() => _PadsPageState();
}

class _PadsPageState extends State<PadsPage>
    with SingleTickerProviderStateMixin {
  static const _side = 4;
  static const _gap = 10.0;
  static const _notes = ['C', 'D', 'E', 'G', 'A'];

  late final List<_Pad> _pads = [
    for (var i = 0; i < _side * _side; i++)
      _Pad(
        color: HSVColor.fromAHSV(1, (196 + i * 11.5) % 360, 0.78, 1).toColor(),
        note: _notes[i % _notes.length],
      ),
  ];
  late final _board = _Board(_pads);
  late final _floor = _Floor();
  late final Ticker _ticker = createTicker(_tick);
  final _held = <int, int>{};
  final _random = math.Random(3);
  Timer? _player;
  var _pattern = _Pattern.pulse;
  var _step = 0;
  Size _grid = Size.zero;

  @override
  void dispose() {
    _player?.cancel();
    _ticker.dispose();
    _floor.dispose();
    super.dispose();
  }

  double get _cell => (_grid.width - (_side - 1) * _gap) / _side;

  // Runs while a ring is spreading.
  void _tick(Duration elapsed) {
    _floor.tick(elapsed.inMicroseconds / 1e6);
    if (_floor.rings.isEmpty) {
      _ticker.stop();
      _floor.now = 0;
    }
  }

  Rect _rectOf(int pad) {
    final cell = _cell;
    return Rect.fromLTWH(
      (pad % _side) * (cell + _gap),
      (pad ~/ _side) * (cell + _gap),
      cell,
      cell,
    );
  }

  int? _padAt(Offset position) {
    final cell = _cell;
    final column = (position.dx / (cell + _gap)).floor();
    final row = (position.dy / (cell + _gap)).floor();
    if (column < 0 || column >= _side || row < 0 || row >= _side) return null;
    final pad = row * _side + column;
    return _rectOf(pad).contains(position) ? pad : null;
  }

  void _ring(int pad) {
    _floor.add(_rectOf(pad).center, _pads[pad].color);
    if (!_ticker.isActive) unawaited(_ticker.start());
  }

  void _touch(PointerEvent event) {
    final t = MotionClock.instance.now;
    final pad = _padAt(event.localPosition);
    final before = _held[event.pointer];
    if (pad != before) {
      if (before != null) _pads[before].release(t);
      if (pad == null) {
        _held.remove(event.pointer);
      } else {
        _held[event.pointer] = pad;
        _pads[pad].press(t);
        _ring(pad);
        unawaited(HapticFeedback.selectionClick());
      }
    }
    if (pad != null) {
      _pads[pad].touchAt(
        t,
        event.localPosition - _rectOf(pad).topLeft,
        _cell,
      );
    }
  }

  void _lift(PointerEvent event) {
    final pad = _held.remove(event.pointer);
    if (pad != null) _pads[pad].release(MotionClock.instance.now);
  }

  Timer _start() => Timer.periodic(const Duration(milliseconds: 140), (_) {
    if (_grid.isEmpty) return;
    for (final pad in _struck(_step++)) {
      _pads[pad].strike(MotionClock.instance.now, _cell);
      _ring(pad);
    }
  });

  void _play() {
    if (_player != null) {
      _player!.cancel();
      setState(() => _player = null);
      return;
    }
    setState(() => _player = _start());
  }

  // The pads the pattern strikes at [step].
  Iterable<int> _struck(int step) => switch (_pattern) {
    _Pattern.pulse => [
      for (var row = 0; row < _side; row++)
        if ((step + row).isEven) row * _side + step % _side,
    ],
    _Pattern.wave => [
      for (var pad = 0; pad < _side * _side; pad++)
        if ((pad % _side + pad ~/ _side) == step % (2 * _side - 1)) pad,
    ],
    _Pattern.rain => [
      _random.nextInt(_side * _side),
      if (step.isEven) _random.nextInt(_side * _side),
    ],
  };

  @override
  Widget build(BuildContext context) => AnnotatedRegion(
    value: SystemUiOverlayStyle.light,
    child: GlassTheme(
      data: const GlassThemeData(brightness: Brightness.dark),
      child: GlassPageScaffold(
        backgroundColor: const Color(0xFF000000),
        navigationBar: GlassNavigationBar(
          title: const Text('Pads'),
          previousPageTitle: 'Surface',
          backButtonDisplayMode: GlassBackButtonDisplayMode.minimal,
          trailing: galleryItems(context),
        ),
        child: Builder(
          builder: (context) {
            final padding = MediaQuery.paddingOf(context);
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                padding.top + 12,
                16,
                padding.bottom + 12,
              ),
              child: Column(
                children: [
                  Expanded(child: Center(child: _padGrid())),
                  const SizedBox(height: 16),
                  _controls(),
                ],
              ),
            );
          },
        ),
      ),
    ),
  );

  Widget _padGrid() => AspectRatio(
    aspectRatio: 1,
    child: LayoutBuilder(
      builder: (context, constraints) {
        _grid = constraints.biggest;
        return MotionScope(
          motion: _board,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _touch,
            onPointerMove: _touch,
            onPointerUp: _lift,
            onPointerCancel: _lift,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The rings lie under the glass and reach past the grid.
                Positioned.fill(
                  left: -60,
                  top: -60,
                  right: -60,
                  bottom: -60,
                  child: CustomPaint(
                    painter: _Rings(_floor, const Offset(60, 60), [
                      for (final (index, pad) in _pads.indexed)
                        (_rectOf(index).center, pad.color),
                    ], _cell),
                  ),
                ),
                for (final (index, pad) in _pads.indexed)
                  Positioned.fromRect(
                    rect: _rectOf(index),
                    child: GlassSurface.live(
                      frame: pad.frame,
                      glass: const Glass.clear(),
                      child: Center(
                        child: Text(
                          pad.note,
                          style: const TextStyle(
                            color: Color(0x8CFFFFFF),
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    ),
  );

  Widget _controls() => Row(
    children: [
      GlassButton(
        onPressed: _play,
        semanticLabel: _player == null ? 'Play' : 'Stop',
        child: Icon(
          _player == null ? CupertinoIcons.play_fill : CupertinoIcons.stop_fill,
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: GlassSegmentedControl<_Pattern>(
          segments: const [
            GlassSegment(value: _Pattern.pulse, label: Text('Pulse')),
            GlassSegment(value: _Pattern.wave, label: Text('Wave')),
            GlassSegment(value: _Pattern.rain, label: Text('Rain')),
          ],
          groupValue: _pattern,
          onChanged: (pattern) => setState(() {
            _pattern = pattern;
            _step = 0;
          }),
        ),
      ),
    ],
  );
}

/// The pads, one motion on screen.
final class _Board extends Motion {
  _Board(List<_Pad> pads) {
    for (final pad in pads) {
      own(pad);
    }
  }
}

/// A pad: how pressed it is and where its finger lies on it.
final class _Pad extends Motion {
  _Pad({required this.color, required this.note});

  final Color color;
  final String note;

  late final _press = own(MotionValue<double>(0));
  late final _touch = own(MotionValue(Offset.zero));
  double _side = 0;

  late final MotionSelection<GlassFrame> frame = select((pad) {
    final t = pad.now;
    final pressed = pad._press.valueAt(t);
    final lit = pressed.clamp(0.0, 1.0);
    return GlassFrame(
      shape: const LiquidRoundedSuperellipse(radius: 26),
      scaleX: 1 - 0.08 * pressed,
      scaleY: 1 - 0.08 * pressed,
      tint: pad.color,
      tintAmount: 0.9 * lit,
      glow: lit < 0.01
          ? null
          : GlassTouchGlow(
              wash: 0.06 * lit,
              center: pad._touch.valueAt(t),
              radius: 0.6 * pad._side,
              spot: 0.6 * lit,
            ),
    );
  });

  void press(double t) {
    advance(t);
    _press.retarget(t, 1, spring: Spring.snappy);
  }

  void touchAt(double t, Offset position, double side) {
    advance(t);
    _side = side;
    _touch.snap(t, position);
  }

  void release(double t) {
    advance(t);
    _press.retarget(t, 0, spring: Spring.bouncy);
  }

  /// A press in the middle that lets go by itself.
  void strike(double t, double side) {
    advance(t);
    _side = side;
    _touch.snap(t, Offset(side / 2, side / 2));
    _press.retarget(t, 1, spring: Spring.snappy);
    at(t + 0.11, release);
  }
}

/// The rings spreading over the floor, each for [_life] seconds.
final class _Floor extends ChangeNotifier {
  static const _life = 1.1;

  final rings = <({Offset center, Color color, double born})>[];
  double now = 0;

  void add(Offset center, Color color) =>
      rings.add((center: center, color: color, born: now));

  void tick(double seconds) {
    now = seconds;
    rings.removeWhere((ring) => now - ring.born > _life);
    notifyListeners();
  }
}

class _Rings extends CustomPainter {
  _Rings(this.floor, this.origin, this.lamps, this.cell)
    : super(repaint: floor);

  final _Floor floor;
  final Offset origin;

  /// A light of each pad's color on the floor under it, [cell] wide.
  final List<(Offset, Color)> lamps;
  final double cell;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (center, color) in lamps) {
      final light = Rect.fromCircle(center: center + origin, radius: cell / 2);
      canvas.drawRect(
        light,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.5),
              color.withValues(alpha: 0),
            ],
          ).createShader(light),
      );
    }
    final stroke = Paint()..style = PaintingStyle.stroke;
    for (final ring in floor.rings) {
      final age = ((floor.now - ring.born) / _Floor._life).clamp(0.0, 1.0);
      final eased = 1 - math.pow(1 - age, 3).toDouble();
      canvas.drawCircle(
        ring.center + origin,
        24 + 190 * eased,
        stroke
          ..strokeWidth = 14 * (1 - age) + 2
          ..color = ring.color.withValues(alpha: 0.85 * (1 - age)),
      );
    }
  }

  @override
  bool shouldRepaint(_Rings old) =>
      old.floor != floor || old.origin != origin || old.cell != cell;
}
