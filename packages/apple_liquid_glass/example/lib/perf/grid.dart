// The scenes of the grid and the run over them: one kind of content under one
// kind of glass, moving at a fixed speed with no touches, while the renderer
// flips between flat (A) and glass (B) every window, in ABBA order. A cell
// takes seconds, so a run covers more content than a walk through the gallery
// does in the same time.
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/backdrop.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

/// What lies under the glass.
enum GridContent {
  /// A grid of photos.
  photos,

  /// A list of text.
  text,

  /// A list of solid rows.
  solid,

  /// A new picture over the whole screen every frame.
  video,

  /// Rows of text and photos, glass in some of them.
  mixedList,

  /// Rows with a texture and a glass button over it.
  videoList,

  /// One boundary of 12 rows, each painting a background under its glass.
  settingsCard,
}

/// The glass over it.
enum GridGlass {
  /// A navigation bar and a tab bar.
  chrome,

  /// 12 buttons scattered over the content.
  crowd,

  /// A sheet over the chrome.
  sheet,

  /// Four panes of glass, each over the one before.
  nest,

  /// A page of buttons fading in and out over the content.
  fade,

  /// Two unfrosted panes in one layer that differ only by tint, which the
  /// final shader's tint variant draws.
  tint,
}

/// One scene of the grid.
@immutable
class GridCell {
  /// A scene of [content] under [glass]; [speed] is in logical pixels a
  /// second, and zero holds it still.
  const GridCell(this.content, this.glass, {this.speed = 600});

  /// What lies under the glass.
  final GridContent content;

  /// The glass over it.
  final GridGlass glass;

  /// How fast the content scrolls.
  final double speed;

  /// The cell's name in reports.
  String get name =>
      '${content.name}_${glass.name}${speed == 0 ? '_still' : ''}';
}

/// The cells of a run, cheapest content first in each glass.
const gridCells = [
  GridCell(GridContent.solid, GridGlass.chrome),
  GridCell(GridContent.text, GridGlass.chrome),
  GridCell(GridContent.photos, GridGlass.chrome),
  GridCell(GridContent.video, GridGlass.chrome),
  GridCell(GridContent.photos, GridGlass.chrome, speed: 0),
  GridCell(GridContent.text, GridGlass.crowd),
  GridCell(GridContent.photos, GridGlass.crowd),
  GridCell(GridContent.text, GridGlass.sheet),
  GridCell(GridContent.photos, GridGlass.sheet),
  GridCell(GridContent.mixedList, GridGlass.chrome),
  GridCell(GridContent.videoList, GridGlass.chrome),
  GridCell(GridContent.settingsCard, GridGlass.chrome),
  GridCell(GridContent.photos, GridGlass.nest),
  GridCell(GridContent.photos, GridGlass.fade),
  GridCell(GridContent.photos, GridGlass.tint),
];

/// The scene a [GridStage] shows and what moves it.
class GridStageController {
  final _cell = ValueNotifier<GridCell>(gridCells.first);
  final _scroll = ScrollController();
  BuildContext? _context;
}

/// The root both ways of running the grid share, so that what they measure
/// holds the same tree: nothing of the gallery stays behind it.
class GridApp extends StatelessWidget {
  /// An app that shows [home] with the glass of [renderer].
  const GridApp({required this.renderer, required this.home, super.key});

  /// Holds flat or glass; a change reaches the scene and its sheet in one
  /// frame.
  final ValueListenable<GlassRenderer> renderer;

  /// The first page.
  final Widget home;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: renderer,
    builder: (context, renderer, _) => WidgetsApp(
      color: const Color(0xFF007AFF),
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(settings, builder) =>
          GlassPageRoute<T>(builder: builder, settings: settings),
      builder: (context, child) => GlassScope(
        renderer: renderer,
        child: Builder(
          builder: (context) => DefaultTextStyle(
            style: TextStyle(
              color: GlassDynamicColor.resolve(GlassColors.label, context),
            ),
            child: child!,
          ),
        ),
      ),
      home: home,
    ),
  );
}

/// Shows the current cell of [controller].
class GridStage extends StatelessWidget {
  /// Creates a stage.
  const GridStage({required this.controller, super.key});

  /// The scene to show.
  final GridStageController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: controller._cell,
    builder: (context, cell, _) => _Scene(
      key: ValueKey(cell),
      cell: cell,
      controller: controller,
    ),
  );
}

class _Scene extends StatelessWidget {
  const _Scene({required this.cell, required this.controller, super.key});

  final GridCell cell;
  final GridStageController controller;

  @override
  Widget build(BuildContext context) {
    controller._context = context;
    final scroll = controller._scroll;
    final content = switch (cell.content) {
      GridContent.photos => GridView.builder(
        controller: scroll,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
        ),
        itemCount: 600,
        itemBuilder: (context, index) => Image(
          image: ResizeImage(
            Wallpaper.values[index % Wallpaper.values.length].image,
            width: 400,
          ),
          fit: BoxFit.cover,
        ),
      ),
      GridContent.text => ListView.builder(
        controller: scroll,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 600,
        itemExtent: 44,
        itemBuilder: (context, index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Text('Row $index of the list under the glass'),
        ),
      ),
      GridContent.solid => ListView.builder(
        controller: scroll,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 600,
        itemExtent: 44,
        itemBuilder: (context, index) =>
            const ColoredBox(color: Color(0xFFEDEDF2)),
      ),
      GridContent.video => const _Video(),
      GridContent.mixedList => ListView.builder(
        controller: scroll,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 600,
        itemExtent: 72,
        itemBuilder: (context, index) => _MixedRow(index),
      ),
      GridContent.videoList => ListView.builder(
        controller: scroll,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 600,
        itemExtent: 180,
        itemBuilder: (context, index) => const _VideoRow(),
      ),
      GridContent.settingsCard => ListView.builder(
        controller: scroll,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: 60,
        itemExtent: 12 * 56 + 32,
        itemBuilder: (context, index) => const _SettingsCard(),
      ),
    };
    final flat = GlassRendererScope.of(context) is FlatGlassRenderer;
    return switch (cell.glass) {
      GridGlass.nest || GridGlass.tint when flat => content,
      GridGlass.chrome || GridGlass.sheet => GlassTabScaffold(
        tabBar: GlassTabBar(
          destinations: const [
            GlassTabDestination(
              icon: Icon(CupertinoIcons.drop),
              label: Text('One'),
            ),
            GlassTabDestination(
              icon: Icon(CupertinoIcons.wind),
              label: Text('Two'),
            ),
            GlassTabDestination(
              icon: Icon(CupertinoIcons.photo),
              label: Text('Three'),
            ),
          ],
          selectedIndex: 0,
          onDestinationSelected: (_) {},
        ),
        tabBuilder: (context, _) => GlassPageScaffold(
          navigationBar: GlassNavigationBar(
            title: const Text('Grid'),
            trailing: [
              GlassBarItem(
                icon: const Icon(CupertinoIcons.search),
                semanticLabel: 'Search',
                onPressed: () {},
              ),
            ],
          ),
          child: GlassContentScroll(child: content),
        ),
      ),
      GridGlass.crowd => Stack(
        fit: StackFit.expand,
        children: [
          content,
          for (var i = 0; i < 12; i++)
            Positioned(
              left: 24.0 + (i % 4) * 90,
              top: 140.0 + (i ~/ 4) * 170,
              child: GlassButton(
                onPressed: () {},
                semanticLabel: 'Crowd $i',
                child: const Icon(CupertinoIcons.heart),
              ),
            ),
        ],
      ),
      GridGlass.nest => Stack(
        fit: StackFit.expand,
        children: [
          content,
          for (var i = 0; i < 4; i++)
            Positioned(
              left: 24.0 + i * 24,
              top: 160.0 + i * 56,
              width: 240,
              height: 150,
              child: const LiquidGlassLayer(
                settings: LiquidGlassSettings.ios27Regular(
                  brightness: Brightness.light,
                ),
                child: LiquidGlass(
                  shape: LiquidRoundedSuperellipse(radius: 28),
                  child: SizedBox.expand(),
                ),
              ),
            ),
        ],
      ),
      GridGlass.tint => Stack(
        fit: StackFit.expand,
        children: [
          content,
          Positioned(
            left: 24,
            right: 24,
            top: 160,
            height: 420,
            child: LiquidGlassLayer(
              settings:
                  const LiquidGlassSettings.ios27Regular(
                    brightness: Brightness.light,
                  ).copyWith(
                    frost: const LiquidGlassFrost.sigma(0),
                  ),
              child: Column(
                children: [
                  for (final tint in const [
                    Color(0x3300A0FF),
                    Color(0x33FF6A00),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: LiquidGlass(
                          shape: const LiquidRoundedSuperellipse(
                            radius: 28,
                          ),
                          appearance: const LiquidGlassAppearance.ios27Regular(
                            brightness: Brightness.light,
                          ).copyWith(tint: tint),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
      GridGlass.fade => Stack(
        fit: StackFit.expand,
        children: [content, const _FadingPage()],
      ),
    };
  }
}

class _MixedRow extends StatelessWidget {
  const _MixedRow(this.index);

  final int index;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Row(
      children: [
        if (index.isEven)
          SizedBox.square(
            dimension: 56,
            child: Image(
              image: ResizeImage(
                Wallpaper.values[index % Wallpaper.values.length].image,
                width: 200,
              ),
              fit: BoxFit.cover,
            ),
          ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text('Row $index of mixed content'),
          ),
        ),
        if (index % 3 != 2)
          GlassButton(
            onPressed: () {},
            semanticLabel: 'Row $index',
            child: const Icon(CupertinoIcons.heart),
          ),
      ],
    ),
  );
}

class _VideoRow extends StatelessWidget {
  const _VideoRow();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(8),
    child: Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(
          color: Color(0xFF203040),
          child: Texture(textureId: 1),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: GlassButton(
            onPressed: () {},
            semanticLabel: 'Play',
            child: const Icon(CupertinoIcons.play),
          ),
        ),
      ],
    ),
  );
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        for (var i = 0; i < 12; i++)
          SizedBox(
            height: 56,
            child: ColoredBox(
              color: const Color(0xFFFFFFFF),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text('Setting $i'),
                    ),
                  ),
                  GlassButton(
                    onPressed: () {},
                    semanticLabel: 'Setting $i',
                    child: const Icon(CupertinoIcons.heart),
                  ),
                ],
              ),
            ),
          ),
      ],
    ),
  );
}

class _FadingPage extends StatefulWidget {
  const _FadingPage();

  @override
  State<_FadingPage> createState() => _FadingPageState();
}

class _FadingPageState extends State<_FadingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    );
    unawaited(_fade.repeat(reverse: true));
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _fade,
    child: Stack(
      children: [
        for (var i = 0; i < 6; i++)
          Positioned(
            left: 24.0 + (i % 3) * 110,
            top: 200.0 + (i ~/ 3) * 180,
            child: GlassButton(
              onPressed: () {},
              semanticLabel: 'Fading $i',
              child: const Icon(CupertinoIcons.star),
            ),
          ),
      ],
    ),
  );
}

class _Video extends StatefulWidget {
  const _Video();

  @override
  State<_Video> createState() => _VideoState();
}

class _VideoState extends State<_Video> with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _time = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _time.value = elapsed.inMicroseconds / 1e6;
    });
    unawaited(_ticker.start());
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _VideoPainter(_time));
}

class _VideoPainter extends CustomPainter {
  _VideoPainter(this.time) : super(repaint: time);

  final ValueNotifier<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    final t = time.value;
    final paint = Paint();
    paint.shader = ui.Gradient.linear(
      Offset(size.width * (0.5 + 0.5 * math.sin(t)), 0),
      Offset(size.width * (0.5 - 0.5 * math.cos(t * 0.7)), size.height),
      const [Color(0xFF12355B), Color(0xFFD72638), Color(0xFFFFBA08)],
      const [0, 0.5, 1],
    );
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_VideoPainter oldDelegate) => false;
}

// The frames right after a flip still show what the flip rebuilt.
const _dropMs = 200;

// A frame is late when a thread took longer than a frame at 60 Hz. The GPU's
// part shows in the frame rate only.
const _lateMs = 16.67;

class _Arm {
  final build = <double>[];
  final raster = <double>[];
  int late = 0;

  int get frames => raster.length;
}

class _Pair {
  late _Arm a;
  late _Arm b;
}

final _armOf = <int, _Arm>{};
_Arm? _current;
var _tagging = false;

void _tagFrames() {
  if (_tagging) return;
  _tagging = true;
  SchedulerBinding.instance.addPersistentFrameCallback((_) {
    if (_current case final arm?) {
      _armOf[ui.PlatformDispatcher.instance.frameData.frameNumber] = arm;
    }
  });
}

/// One run over cells of a [GridStage].
class GridRunner {
  /// A run on [stage]. [setGlass] switches the renderer between flat and
  /// glass, whichever theme holds it.
  GridRunner({required this.stage, required this.setGlass});

  /// The stage the cells show on.
  final GridStageController stage;

  /// Switches the renderer: glass when true, flat when not.
  final void Function({required bool on}) setGlass;

  /// Errors the framework reported since [start].
  int errors = 0;

  /// Frames rastered since [start].
  int rastered = 0;

  FlutterExceptionHandler? _previous;

  /// Starts following frames and errors.
  void start() {
    _previous = FlutterError.onError;
    FlutterError.onError = (details) {
      errors++;
      _previous?.call(details);
    };
    _tagFrames();
    SchedulerBinding.instance.addTimingsCallback(_timings);
  }

  /// Stops following frames and errors.
  void stop() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    FlutterError.onError = _previous;
  }

  void _timings(List<FrameTiming> timings) {
    rastered += timings.length;
    for (final timing in timings) {
      final arm = _armOf.remove(timing.frameNumber);
      if (arm == null) continue;
      final build = timing.buildDuration.inMicroseconds / 1e3;
      final raster = timing.rasterDuration.inMicroseconds / 1e3;
      arm.build.add(build);
      arm.raster.add(raster);
      if (build > _lateMs || raster > _lateMs) arm.late++;
    }
  }

  /// Shows [cell] and flips the renderer for [pairs] pairs of windows of
  /// [windowMs], then returns what the app saw. With [proxyRounds] it also
  /// times work the GPU has to finish ([_gpuProxy]). With [snapshot] the
  /// report holds a small picture of the cell under glass.
  Future<Map<String, Object?>> runCell(
    GridCell cell, {
    int windowMs = 1000,
    int pairs = 8,
    int settleMs = 1500,
    int proxyRounds = 0,
    int proxySamples = 3,
    bool snapshot = false,
  }) async {
    setGlass(on: false);
    stage._cell.value = cell;
    await _nextFrame();
    final navigator = cell.glass == GridGlass.sheet
        ? Navigator.of(stage._context!)
        : null;
    if (navigator != null) {
      unawaited(
        showGlassSheet<void>(
          navigator.context,
          builder: (context) => const SizedBox(height: 420),
        ),
      );
    }
    final mover = _Mover(cell.speed, stage._scroll);
    mover.start();
    await _wait(settleMs);
    final done = <_Pair>[];
    for (var n = 0; n < pairs * 2; n++) {
      final on = const [false, true, true, false][n % 4];
      setGlass(on: on);
      final arm = _Arm();
      debugPrint(
        'GLASS_BENCH_AB ${cell.name} ${on ? 'B' : 'A'} $n '
        '${DateTime.now().microsecondsSinceEpoch / 1e6} $rastered',
      );
      await _wait(_dropMs);
      _current = arm;
      await _wait(windowMs - _dropMs);
      _current = null;
      if (n.isEven) done.add(_Pair());
      if (on) {
        done.last.b = arm;
      } else {
        done.last.a = arm;
      }
    }
    debugPrint(
      'GLASS_BENCH_AB_END ${cell.name} '
      '${DateTime.now().microsecondsSinceEpoch / 1e6} $rastered',
    );
    setGlass(on: false);
    // Timings come in batches, about one every 100 ms.
    await _wait(300);
    mover.stop();
    final proxy = proxyRounds > 0
        ? await _gpuProxy(proxyRounds, proxySamples)
        : null;
    final picture = snapshot ? await _snapshot() : null;
    mover.dispose();
    if (navigator != null) {
      navigator.pop();
      await _wait(1000);
    }
    double fps(_Arm arm) => arm.frames * 1000 / (windowMs - _dropMs);
    double late(_Arm arm) => arm.frames == 0 ? 0 : 100 * arm.late / arm.frames;
    return {
      'cell': cell.name,
      'build_ms': _summary(done, (arm) => _median(arm.build)),
      'raster_ms': _summary(done, (arm) => _median(arm.raster)),
      'fps': _summary(done, fps),
      'late_pct': _summary(done, late),
      'frames_a': done.fold<int>(0, (sum, pair) => sum + pair.a.frames),
      'frames_b': done.fold<int>(0, (sum, pair) => sum + pair.b.frames),
      'proxy': ?proxy,
      'snapshot': ?picture,
    };
  }

  /// Holds [cell] under glass for [seconds] and returns what the frames did
  /// in each step of [stepSeconds], with whatever [sample] reads alongside.
  Future<List<Map<String, Object?>>> sustain(
    GridCell cell, {
    required int seconds,
    required int stepSeconds,
    required Future<Map<String, Object?>?> Function() sample,
  }) async {
    setGlass(on: true);
    stage._cell.value = cell;
    final mover = _Mover(cell.speed, stage._scroll);
    await _nextFrame();
    mover.start();
    final steps = <Map<String, Object?>>[];
    for (var t = 0; t < seconds; t += stepSeconds) {
      final arm = _Arm();
      _current = arm;
      await _wait(stepSeconds * 1000);
      _current = null;
      await _wait(150);
      steps.add({
        't': t + stepSeconds,
        'build_ms': _finite(_median(arm.build)),
        'raster_ms': _finite(_median(arm.raster)),
        'fps': arm.frames / stepSeconds,
        'late_pct': arm.frames == 0 ? 0 : 100 * arm.late / arm.frames,
        'device': await sample(),
      });
    }
    mover.dispose();
    return steps;
  }

  Future<ui.Image> _viewImage(double pixelRatio) {
    final view = RendererBinding.instance.renderViews.first;
    final layer = view.layer! as OffsetLayer;
    final size = view.flutterView.physicalSize;
    return layer.toImage(Offset.zero & size, pixelRatio: pixelRatio);
  }

  // Timed work the GPU has to finish before the app can read a pixel of it,
  // so the time holds the GPU's part, which FrameTiming does not, and the
  // raster thread's too. Nothing else draws. On a Pixel 6a it follows the Mali
  // counters for changes of 2 ms and more, with a standard error of 0.4 - 1 ms
  // at 20 rounds of 5 samples: the sign of a large change, no finer.
  Future<Map<String, Object?>> _gpuProxy(int rounds, int samples) async {
    await _wait(200);
    final all = {false: <double>[], true: <double>[]};
    final deltas = <double>[];
    Future<double> sample() async {
      final watch = Stopwatch();
      watch.start();
      final image = await _viewImage(1);
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint(),
      );
      final small = await recorder.endRecording().toImage(1, 1);
      await small.toByteData();
      watch.stop();
      small.dispose();
      image.dispose();
      return watch.elapsedMicroseconds / 1e3;
    }

    for (var round = 0; round < rounds; round++) {
      final times = {false: <double>[], true: <double>[]};
      final order = round.isEven ? const [false, true] : const [true, false];
      for (final on in order) {
        setGlass(on: on);
        await _nextFrame();
        await _nextFrame();
        await sample();
        for (var i = 0; i < samples; i++) {
          times[on]!.add(await sample());
        }
        all[on]!.addAll(times[on]!);
      }
      deltas.add(_median(times[true]!) - _median(times[false]!));
    }
    setGlass(on: false);
    return {
      'a_ms': _finite(_median(all[false]!)),
      'b_ms': _finite(_median(all[true]!)),
      'delta_ms': _finite(_median(deltas)),
      'se_ms': _finite(_standardError(deltas)),
    };
  }

  Future<String> _snapshot() async {
    setGlass(on: true);
    await _nextFrame();
    await _nextFrame();
    final image = await _viewImage(0.25);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    setGlass(on: false);
    return base64Encode(bytes!.buffer.asUint8List());
  }

  Future<void> _nextFrame() {
    SchedulerBinding.instance.scheduleFrame();
    return SchedulerBinding.instance.endOfFrame;
  }

  Future<void> _wait(int ms) => Future.delayed(Duration(milliseconds: ms));
}

double? _finite(double value) => value.isNaN ? null : value;

Map<String, Object?> _summary(List<_Pair> pairs, double Function(_Arm) of) {
  final complete = [
    for (final pair in pairs)
      if (pair.a.frames > 0 && pair.b.frames > 0) pair,
  ];
  final deltas = [for (final pair in complete) of(pair.b) - of(pair.a)];
  return {
    'a': _finite(_median([for (final pair in complete) of(pair.a)])),
    'b': _finite(_median([for (final pair in complete) of(pair.b)])),
    'delta': _finite(_median(deltas)),
    'se': _finite(_standardError(deltas)),
    'up': deltas.where((d) => d > 0).length,
    'n': deltas.length,
  };
}

double _median(List<double> values) {
  if (values.isEmpty) return double.nan;
  final sorted = [...values];
  sorted.sort();
  final mid = sorted.length ~/ 2;
  return sorted.length.isOdd
      ? sorted[mid]
      : (sorted[mid - 1] + sorted[mid]) / 2;
}

double _standardError(List<double> values) {
  if (values.length < 2) return double.nan;
  final mean = values.reduce((a, b) => a + b) / values.length;
  final sum = values.fold<double>(
    0,
    (sum, value) => sum + (value - mean) * (value - mean),
  );
  return math.sqrt(sum / (values.length - 1) / values.length);
}

// Moves the content at a fixed speed, back and forth over its extent, from
// the frame's own clock.
class _Mover {
  _Mover(this.speed, this.scroll);

  final double speed;
  final ScrollController scroll;
  Ticker? _ticker;

  void start() {
    if (speed == 0) return;
    final ticker = Ticker((elapsed) {
      if (!scroll.hasClients) return;
      final position = scroll.position;
      final extent = position.maxScrollExtent;
      if (extent <= 0) return;
      final travelled = speed * elapsed.inMicroseconds / 1e6;
      final phase = travelled % (2 * extent);
      position.jumpTo(phase <= extent ? phase : 2 * extent - phase);
    });
    _ticker = ticker;
    unawaited(ticker.start());
  }

  void stop() => _ticker?.stop();

  void dispose() => _ticker?.dispose();
}
