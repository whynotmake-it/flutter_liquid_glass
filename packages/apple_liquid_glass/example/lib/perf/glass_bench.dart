// The glass heat bench: one launch walks fixed scenes, each 2.5 s still and
// then measured for BENCH_SCENE_S, and writes the scene windows and frame
// timings to tmp/glass_bench/report.json. The Mac side samples the phone's
// power and, optionally, a Metal System Trace over the same launch.
// The parity run switches the renderer's copies off and on through its
// test hook.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/rendering.dart' show glassReadsCopies;

enum Scene {
  /// Nothing moves: the cost of a screen of glass that is only shown.
  idle,

  /// Everything still but a 6 px dot outside the glass.
  dot,

  /// Five clear drops in one group move over a still wallpaper.
  drops,

  /// Moving drops over a drifting wallpaper.
  liquid,

  /// A list of photos scrolls under a navigation bar and a tab bar.
  scroll,

  /// The scroll scene under 24 more glass buttons.
  crowd,

  /// The dot over the wallpaper with no glass on screen.
  bare,

  /// The dot scene on the flat renderer.
  flat,

  /// The idle scene with the tab bar stretched along the axes, as a drag
  /// stretches it.
  stretch,
}

const _still = Duration(milliseconds: 2500);

/// 8 s for a Metal System Trace; 45 s or more for energy, whose telemetry
/// the phone updates every 20 s.
const _measured = Duration(
  seconds: int.fromEnvironment('BENCH_SCENE_S', defaultValue: 8),
);
const _lead = Duration(seconds: 4);

/// Instead of timing, renders every scene still with the renderer's copies
/// off and on and reports how far the two frames differ.
const _parity = bool.fromEnvironment('BENCH_PARITY');

/// Every glass scene on the fake renderer instead of the liquid one.
const _fake = bool.fromEnvironment('BENCH_FAKE');

final _clock = Stopwatch();

double _seconds() => _clock.elapsedMicroseconds / 1e6;

void main() {
  _clock.start();
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(precacheLiquidGlass());
  const fixed = String.fromEnvironment('BENCH_FIXED');
  runApp(
    GlassBenchApp(fixed: fixed.isEmpty ? null : Scene.values.byName(fixed)),
  );
}

class _Window {
  _Window(this.scene, this.start)
    : wallStart = DateTime.now().millisecondsSinceEpoch / 1e3;

  final String scene;
  final double start;
  final double wallStart;
  double end = 0;
  double wallEnd = 0;
  final raster = <double>[];
  final build = <double>[];
}

/// The bench; [fixed] shows one scene moving, for a host probe.
class GlassBenchApp extends StatefulWidget {
  const GlassBenchApp({super.key, this.fixed});

  final Scene? fixed;

  @override
  State<GlassBenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<GlassBenchApp>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker = createTicker(_tick);
  final _t = ValueNotifier<double>(0);
  final _windows = <_Window>[];
  _Window? _open;
  var _scene = Scene.idle;
  var _moving = false;
  var _epoch = 0;
  final _screen = GlobalKey();

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    if (widget.fixed case final scene?) {
      _scene = scene;
      _moving = true;
      _ticker.start();
    } else {
      unawaited(_parity ? _runParity() : _run());
    }
  }

  void _timings(List<FrameTiming> timings) {
    final open = _open;
    if (open == null) return;
    for (final t in timings) {
      open.raster.add(t.rasterDuration.inMicroseconds / 1e3);
      open.build.add(t.buildDuration.inMicroseconds / 1e3);
    }
  }

  Future<void> _runParity() async {
    await Future<void>.delayed(_lead);
    final results = <String, Object?>{};
    for (final scene in [
      Scene.idle,
      Scene.dot,
      Scene.drops,
      Scene.liquid,
      Scene.scroll,
      Scene.crowd,
      Scene.stretch,
    ]) {
      final shots = <ByteData>[];
      for (final on in [false, true]) {
        glassReadsCopies = on;
        setState(() {
          _scene = scene;
          _moving = true;
          _epoch++;
        });
        _t.value = 2.2;
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        final boundary =
            _screen.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final image = await boundary.toImage(
          pixelRatio: View.of(_screen.currentContext!).devicePixelRatio,
        );
        shots.add((await image.toByteData())!);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        final dir = Directory('${Directory.systemTemp.path}/glass_bench');
        await dir.create(recursive: true);
        await File(
          '${dir.path}/parity_${scene.name}_${on ? 'on' : 'off'}.png',
        ).writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
      }
      final a = shots[0].buffer.asUint8List();
      final b = shots[1].buffer.asUint8List();
      var largest = 0;
      var over2 = 0;
      final width =
          (a.length /
                  4 /
                  (_screen.currentContext!.size!.height *
                      View.of(_screen.currentContext!).devicePixelRatio))
              .round();
      var x0 = 1 << 30;
      var y0 = 1 << 30;
      var x1 = -1;
      var y1 = -1;
      for (var i = 0; i < a.length; i++) {
        final d = (a[i] - b[i]).abs();
        if (d > largest) largest = d;
        if (d > 2) over2++;
        if (d > 4) {
          final px = (i ~/ 4) % width;
          final py = (i ~/ 4) ~/ width;
          if (px < x0) x0 = px;
          if (px > x1) x1 = px;
          if (py < y0) y0 = py;
          if (py > y1) y1 = py;
        }
      }
      debugPrint(
        'GLASS_PARITY_BOX ${scene.name} w=$width x $x0..$x1 y $y0..$y1',
      );
      results[scene.name] = {'max': largest, 'over2': over2};
      debugPrint('GLASS_PARITY ${scene.name} max=$largest over2=$over2');
    }
    final dir = Directory('${Directory.systemTemp.path}/glass_bench');
    await File('${dir.path}/report.json').writeAsString(jsonEncode(results));
    debugPrint('GLASS_BENCH done');
  }

  Future<void> _run() async {
    await Future<void>.delayed(_lead);
    for (final scene in Scene.values) {
      setState(() {
        _scene = scene;
        _moving = false;
        _epoch++;
      });
      await Future<void>.delayed(_still);
      final window = _Window(scene.name, _seconds());
      _open = window;
      setState(() => _moving = scene != Scene.idle);
      if (_moving) _ticker.start();
      await Future<void>.delayed(_measured);
      _ticker.stop();
      window.end = _seconds();
      window.wallEnd = DateTime.now().millisecondsSinceEpoch / 1e3;
      _open = null;
      _windows.add(window);
      debugPrint('GLASS_BENCH ${scene.name} ${window.start}..${window.end}');
    }
    setState(() => _moving = false);
    await _write();
    debugPrint('GLASS_BENCH done');
  }

  Future<void> _write() async {
    double pct(List<double> v, double p) {
      if (v.isEmpty) return 0;
      final s = [...v];
      s.sort();
      return s[math.min(s.length - 1, (s.length * p).floor())];
    }

    final dir = Directory('${Directory.systemTemp.path}/glass_bench');
    await dir.create(recursive: true);
    final windows = [
      for (final w in _windows)
        {
          'scene': w.scene,
          'start': w.start,
          'end': w.end,
          'wall_start': w.wallStart,
          'wall_end': w.wallEnd,
          'frames': w.raster.length,
          'raster_p50': pct(w.raster, 0.5),
          'raster_p90': pct(w.raster, 0.9),
          'build_p50': pct(w.build, 0.5),
        },
    ];
    final report = jsonEncode({'windows': windows});
    await File('${dir.path}/report.json').writeAsString(report);
    // The Android log cuts a long message: each window gets a line.
    for (final w in windows) {
      debugPrint('GLASS_BENCH_WINDOW ${jsonEncode(w)}', wrapWidth: 1 << 20);
    }
    // A profile build on Android cannot be read through run-as: the Mac side
    // takes the report from the log.
    debugPrint('GLASS_BENCH_REPORT $report', wrapWidth: 1 << 20);
  }

  void _tick(Duration elapsed) {
    _t.value = elapsed.inMicroseconds / 1e6;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: _screen,
    child: KeyedSubtree(key: ValueKey(_epoch), child: _app()),
  );

  Widget _stretched(Widget child) => _scene == Scene.stretch
      ? Transform(
          alignment: Alignment.center,
          transform: Matrix4.diagonal3Values(1.08, 0.9, 1),
          child: child,
        )
      : child;

  Widget _app() => WidgetsApp(
    color: const Color(0xFF007AFF),
    debugShowCheckedModeBanner: false,
    pageRouteBuilder: <T>(routeSettings, builder) =>
        GlassPageRoute<T>(builder: builder, settings: routeSettings),
    builder: (context, child) => GlassScope(
      renderer: _scene == Scene.flat
          ? const FlatGlassRenderer()
          : _fake
          ? const FakeGlassRenderer()
          : const LiquidGlassRenderer(),
      child: DefaultTextStyle(
        style: const TextStyle(color: Color(0xFFFFFFFF)),
        child: child!,
      ),
    ),
    home: _scene == Scene.bare
        ? Stack(
            fit: StackFit.expand,
            children: [
              const DriftingWallpaper(
                wallpaper: Wallpaper.aurora,
                drifts: false,
              ),
              _Dot(t: _t, visible: _moving),
            ],
          )
        : _stretched(
            GlassTabScaffold(
              tabBar: GlassTabBar(
                destinations: const [
                  GlassTabDestination(
                    icon: Icon(CupertinoIcons.drop),
                    label: Text('Liquid'),
                  ),
                  GlassTabDestination(
                    icon: Icon(CupertinoIcons.slider_horizontal_3),
                    label: Text('Controls'),
                  ),
                  GlassTabDestination(
                    icon: Icon(CupertinoIcons.square_stack_3d_up),
                    label: Text('Present'),
                  ),
                  GlassTabDestination(
                    icon: Icon(CupertinoIcons.photo_on_rectangle),
                    label: Text('Photos'),
                  ),
                ],
                selectedIndex: _scene == Scene.scroll || _scene == Scene.crowd
                    ? 3
                    : 0,
                onDestinationSelected: (_) {},
              ),
              tabBuilder: (context, index) => index == 3
                  ? _ScrollPage(
                      t: _t,
                      moving: _moving,
                      crowd: _scene == Scene.crowd,
                    )
                  : _LiquidScene(scene: _scene, t: _t, moving: _moving),
            ),
          ),
  );
}

class _LiquidScene extends StatelessWidget {
  const _LiquidScene({
    required this.scene,
    required this.t,
    required this.moving,
  });

  final Scene scene;
  final ValueNotifier<double> t;
  final bool moving;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    const shadow = [Shadow(color: Color(0x66000000), blurRadius: 12)];
    TextStyle style(double size, [FontWeight? weight]) => TextStyle(
      color: const Color(0xFFFFFFFF),
      fontSize: size,
      fontWeight: weight,
      shadows: shadow,
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        DriftingWallpaper(
          wallpaper: Wallpaper.aurora,
          drifts: moving && scene == Scene.liquid,
        ),
        LayoutBuilder(
          builder: (context, constraints) => _Drops(
            area: constraints.biggest,
            t: t,
            moving: moving && (scene == Scene.drops || scene == Scene.liquid),
            style: style(26, FontWeight.w600),
          ),
        ),
        Positioned(
          top: media.padding.top + 8,
          left: 16,
          right: 16,
          child: Row(
            children: [
              GlassButton(
                onPressed: () {},
                semanticLabel: 'Settings',
                child: const Icon(CupertinoIcons.gear),
              ),
              const Spacer(),
              GlassButton(
                onPressed: () {},
                semanticLabel: 'Look',
                child: const Icon(CupertinoIcons.paintbrush),
              ),
            ],
          ),
        ),
        Positioned(
          top: media.padding.top + 64,
          left: 24,
          right: 24,
          child: Column(
            children: [
              Text('Liquid Glass', style: style(34, FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Grab a drop. Bring two together.', style: style(15)),
            ],
          ),
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: media.padding.bottom + 16,
          child: GlassSlider(value: 28, max: 60, onChanged: (_) {}),
        ),
        _Dot(
          t: t,
          visible: moving && (scene == Scene.dot || scene == Scene.flat),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.t, required this.visible});

  final ValueNotifier<double> t;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return Positioned(
      left: 8,
      top: MediaQuery.paddingOf(context).top + 140,
      child: ValueListenableBuilder(
        valueListenable: t,
        builder: (context, t, _) {
          final dot = Transform.translate(
            offset: Offset(math.sin(t * 3) * 4, 0),
            child: const SizedBox.square(
              dimension: 6,
              child: ColoredBox(color: Color(0xFFFFFFFF)),
            ),
          );
          return const bool.fromEnvironment('BENCH_DOT_BOUNDARY')
              ? RepaintBoundary(child: dot)
              : dot;
        },
      ),
    );
  }
}

const _homes = [
  Alignment(-0.45, -0.22),
  Alignment(0.55, -0.3),
  Alignment(0.3, 0.08),
  Alignment(-0.55, 0.4),
  Alignment(0.35, 0.5),
];

class _Drops extends StatefulWidget {
  const _Drops({
    required this.area,
    required this.t,
    required this.moving,
    required this.style,
  });

  final Size area;
  final ValueNotifier<double> t;
  final bool moving;
  final TextStyle style;

  @override
  State<_Drops> createState() => _DropsState();
}

class _DropsState extends State<_Drops> {
  final _phase = MotionValue<double>(0);
  late List<MotionSelection<GlassFrame>> _frames = _framesIn(widget.area);

  Size _size(int i, double w) => switch (i) {
    0 => Size.square(w * 0.36),
    1 => Size.square(w * 0.22),
    2 => Size(w * 0.52, 68),
    3 => Size.square(w * 0.2),
    _ => Size.square(w * 0.28),
  };

  @override
  void initState() {
    super.initState();
    widget.t.addListener(_update);
    _update();
  }

  @override
  void didUpdateWidget(_Drops old) {
    super.didUpdateWidget(old);
    if (old.area != widget.area) _frames = _framesIn(widget.area);
    _update();
  }

  @override
  void dispose() {
    widget.t.removeListener(_update);
    super.dispose();
  }

  void _update() => _phase.snap(
    MotionClock.instance.now,
    widget.moving ? widget.t.value : 0.0,
  );

  List<MotionSelection<GlassFrame>> _framesIn(Size area) => [
    for (var i = 0; i < 5; i++)
      MotionSelection(() {
        final t = _phase.value;
        final size = _size(i, area.width);
        final drift = Offset(
          math.sin(t * 1.3 + i) * 30,
          math.cos(t * 1.1 + i * 2) * 24,
        );
        return GlassFrame(
          shape: i == 1
              ? const LiquidRoundedSuperellipse(radius: 26)
              : LiquidRoundedSuperellipse.capsule,
          rect: Rect.fromCenter(
            center: size.center(Offset.zero) + drift,
            width: size.width,
            height: size.height,
          ),
        );
      }),
  ];

  @override
  Widget build(BuildContext context) {
    final area = widget.area;
    return GlassGroup(
      merge: const GlassMerge.spacing(28),
      child: Stack(
        fit: StackFit.expand,
        children: [
          for (var i = 0; i < 5; i++)
            Positioned.fromRect(
              rect:
                  (_homes[i].alongSize(area) -
                      _size(i, area.width).center(Offset.zero)) &
                  _size(i, area.width),
              child: GlassSurface.live(
                frame: _frames[i],
                glass: const Glass.clear(),
                child: Center(
                  child: i == 2
                      ? Text('Liquid', style: widget.style)
                      : const Icon(
                          CupertinoIcons.drop_fill,
                          size: 34,
                          color: Color(0xFFFFFFFF),
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ScrollPage extends StatefulWidget {
  const _ScrollPage({
    required this.t,
    required this.moving,
    required this.crowd,
  });

  final ValueNotifier<double> t;
  final bool moving;
  final bool crowd;

  @override
  State<_ScrollPage> createState() => _ScrollPageState();
}

class _ScrollPageState extends State<_ScrollPage> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.t.addListener(_scroll);
  }

  @override
  void dispose() {
    widget.t.removeListener(_scroll);
    _controller.dispose();
    super.dispose();
  }

  // A steady 600 pt/s back and forth, like a slow continuous finger drag.
  void _scroll() {
    if (!widget.moving || !_controller.hasClients) return;
    final position = _controller.position;
    final span = math.min(position.maxScrollExtent, 2400);
    final phase = (widget.t.value * 600 / span) % 2;
    _controller.jumpTo(span * (phase < 1 ? phase : 2 - phase));
  }

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      _page(),
      if (widget.crowd)
        for (var i = 0; i < 24; i++)
          Positioned(
            left: 24.0 + (i % 4) * 88,
            top: 180.0 + (i ~/ 4) * 96,
            child: GlassButton(
              onPressed: () {},
              semanticLabel: 'Crowd $i',
              child: const Icon(CupertinoIcons.heart),
            ),
          ),
    ],
  );

  Widget _page() => GlassPageScaffold(
    backgroundColor: GlassColors.systemGroupedBackground,
    navigationBar: const GlassNavigationBar(largeTitle: Text('Photos')),
    child: GlassContentScroll(
      child: ListView.builder(
        controller: _controller,
        padding: const EdgeInsets.all(12),
        itemCount: 60,
        itemBuilder: (context, i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipRSuperellipse(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 220,
              child: Image(
                image: Wallpaper.values[i % Wallpaper.values.length].image,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
