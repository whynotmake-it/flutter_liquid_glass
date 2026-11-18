// The app bench: one launch drives the gallery through a scripted journey
// with synthesized touches, the way a person uses it, and measures every
// step for BENCH_SCENE_S. Each step prints a `GLASS_BENCH <step> a..b` line
// and its frame timings, in the glass bench's format, so the same Mac side
// splits the phone's rail energy by step.
//
// With BENCH_CENSUS the steps run short and, instead of timing, the bench
// walks the layer tree after every frame and prints what each step asks the
// GPU for: layers by type and the renderer's offscreen images.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:apple_liquid_glass_example/app.dart';
import 'package:apple_liquid_glass_example/settings.dart';
import 'package:apple_liquid_glass_example/stand/stand_home.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:liquid_glass_renderer/src/rendering/glass_composer.dart';
import 'package:liquid_glass_renderer/src/rendering/read.dart';

const _census = bool.fromEnvironment('BENCH_CENSUS');
const _measured = Duration(
  seconds: int.fromEnvironment(
    'BENCH_SCENE_S',
    defaultValue: _census ? 4 : 20,
  ),
);
const _settle = Duration(milliseconds: 2500);
const _only = String.fromEnvironment('BENCH_STEPS');

// Every glass reads its backdrop live, for the whole run.
const _live = bool.fromEnvironment('BENCH_LIVE');

// A build with BENCH_RENDERER=flat prices glass against flat in the real
// gallery.
final _settings = GallerySettings(
  renderer: GalleryRenderer.values.byName(
    const String.fromEnvironment('BENCH_RENDERER', defaultValue: 'liquid'),
  ),
);

// The crowd: BENCH_CROWD glass buttons in a grid over every page, so builds
// with different counts price glass by count.
const _crowd = int.fromEnvironment('BENCH_CROWD');

// A spread crowd stands 4 to a row with wide gaps, so no glass lies in
// another's copy.
const _spread = bool.fromEnvironment('BENCH_CROWD_SPREAD');

// A grouped crowd sits in one GlassGroup: one glass layer that reads what
// lies behind it once.
const _grouped = bool.fromEnvironment('BENCH_CROWD_GROUPED');

class _Crowd extends StatelessWidget {
  const _Crowd();

  @override
  Widget build(BuildContext context) {
    final crowd = Stack(
      children: [
        for (var i = 0; i < _crowd; i++)
          Positioned(
            left: _spread ? 16.0 + (i % 4) * 100 : 20.0 + (i % 5) * 76,
            top: _spread ? 120.0 + (i ~/ 4) * 130 : 150.0 + (i ~/ 5) * 80,
            child: GlassButton(
              onPressed: () {},
              semanticLabel: 'Crowd $i',
              child: const Icon(CupertinoIcons.heart),
            ),
          ),
      ],
    );
    return IgnorePointer(
      child: _grouped ? GlassGroup(child: crowd) : crowd,
    );
  }
}

final _clock = Stopwatch();

double _seconds() => _clock.elapsedMicroseconds / 1e6;

void main() {
  _clock.start();
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(precacheLiquidGlass());
  runApp(
    GalleryApp(settings: _settings, home: const StandHome()),
  );
  unawaited(_Journey().run());
}

class _Window {
  _Window(this.step, this.start)
    : wallStart = DateTime.now().millisecondsSinceEpoch / 1e3;

  final String step;
  final double start;
  final double wallStart;
  double end = 0;
  double wallEnd = 0;
  final raster = <double>[];
  final build = <double>[];
  int images = 0;
  int walked = 0;
  final layers = <String, int>{};
  final misses = <String, int>{};
}

/// One step of the journey: [enter] brings the app to the screen, [act]
/// keeps using it until the window closes.
class _Step {
  const _Step(this.name, {this.enter, this.act});

  final String name;
  final Future<void> Function(_Journey)? enter;
  final Future<void> Function(_Journey, bool Function() open)? act;
}

final _steps = <_Step>[
  _Step('photos_still', enter: (j) => j.tapTab('Photos')),
  _Step('photos_scroll', act: (j, open) => j.scrolling(open)),
  // Scrolls at a speed that repeats run to run: a drag that eases in and
  // out leaves no fling, so every run draws the same frames.
  _Step(
    'photos_drag',
    act: (j, open) async {
      final x = j.screen.width * 0.5;
      final top = j.screen.height * 0.3;
      final bottom = j.screen.height * 0.75;
      while (open()) {
        await j.drag(Offset(x, bottom), Offset(x, top), 1500);
        await j.drag(Offset(x, top), Offset(x, bottom), 1500);
      }
    },
  ),
  _Step(
    'photo_zoom',
    act: (j, open) async {
      while (open()) {
        await j.tap(j.center(j.find<GlassZoomSource>(index: 4)));
        await j.wait(1400);
        await j.back();
        await j.wait(1400);
      }
    },
  ),
  _Step('controls_still', enter: (j) => j.tapTab('Controls')),
  _Step('controls_scroll', act: (j, open) => j.scrolling(open)),
  _Step(
    'controls_slider',
    enter: (j) => j.scrollTo<GlassSlider>(),
    act: (j, open) async {
      final slider = j.rect(j.find<GlassSlider>());
      while (open()) {
        await j.drag(
          slider.centerLeft + const Offset(24, 0),
          slider.centerRight - const Offset(24, 0),
          900,
        );
        await j.drag(
          slider.centerRight - const Offset(24, 0),
          slider.centerLeft + const Offset(24, 0),
          900,
        );
      }
    },
  ),
  _Step(
    'controls_switch',
    enter: (j) => j.scrollTo<GlassSwitch>(),
    act: (j, open) async {
      while (open()) {
        await j.tap(j.center(j.find<GlassSwitch>()));
        await j.wait(700);
      }
    },
  ),
  _Step(
    'tabbar_drag',
    act: (j, open) async {
      while (open()) {
        await j.drag(j.tabCenter('Liquid'), j.tabCenter('Photos'), 1100);
        await j.wait(500);
        await j.drag(j.tabCenter('Photos'), j.tabCenter('Controls'), 1100);
        await j.wait(500);
      }
    },
  ),
  _Step('present_still', enter: (j) => j.tapTab('Present')),
  _Step(
    'present_menu',
    act: (j, open) async {
      while (open()) {
        await j.tap(j.center(j.findLabel('More')));
        await j.wait(1200);
        await j.tap(Offset(j.screen.width - 12, j.screen.height * 0.45));
        await j.wait(1000);
      }
    },
  ),
  _Step(
    'present_sheet',
    enter: (j) => j.scrollToText('Sheet with detents'),
    act: (j, open) async {
      while (open()) {
        await j.tap(j.center(j.findText('Sheet with detents')));
        await j.wait(1500);
        await j.back();
        await j.wait(1200);
      }
    },
  ),
  _Step(
    'music_scroll',
    enter: (j) async {
      await j.scrollToText('Music app');
      await j.tap(j.center(j.findText('Music app')));
    },
    act: (j, open) => j.scrolling(open),
  ),
  _Step(
    'liquid_still',
    enter: (j) async {
      await j.back();
      await j.wait(800);
      await j.tapTab('Liquid');
      await j.wait(6000);
    },
  ),
  _Step(
    'liquid_drag',
    act: (j, open) async {
      final drop = j.screen.center;
      while (open()) {
        await j.drag(drop, drop + const Offset(-90, 140), 700);
        await j.wait(1500);
      }
    },
  ),
  _Step('motion_still', enter: (j) => j.tapTab('Motion')),
  _Step('motion_scroll', act: (j, open) => j.scrolling(open)),
];

class _Journey {
  final _windows = <_Window>[];
  _Window? _open;
  var _pointer = 1;
  late final Rect screen;

  Future<void> run() async {
    if (_live) glassReadsCopies = false;
    SchedulerBinding.instance.addTimingsCallback(_timings);
    if (_census) SchedulerBinding.instance.addPersistentFrameCallback(_frame);
    await wait(4000);
    final view = WidgetsBinding.instance.platformDispatcher.implicitView!;
    screen = Offset.zero & (view.physicalSize / view.devicePixelRatio);
    final root = _elements()
        .whereType<StatefulElement>()
        .map((e) => e.state)
        .whereType<NavigatorState>()
        .first;
    root.overlay!.insert(OverlayEntry(builder: (_) => const _Crowd()));
    final only = _only.isEmpty ? null : _only.split(',').toSet();
    for (final step in _steps) {
      try {
        await _take(step, only);
      } on Object catch (error) {
        _open = null;
        debugPrint('APP_BENCH_SKIP ${step.name}: $error');
      }
    }
    _report();
    debugPrint('GLASS_BENCH done');
  }

  Future<void> _take(_Step step, Set<String>? only) async {
    await step.enter?.call(this);
    await wait(_settle.inMilliseconds);
    if (only != null && !only.contains(step.name)) {
      await step.act?.call(this, () => false);
      return;
    }
    final window = _Window(step.name, _seconds());
    debugPrint('APP_BENCH_START ${step.name}');
    final images = GlassCopies.debugImagesDrawn;
    final composed = _composed();
    _open = window;
    final end = window.start + _measured.inMicroseconds / 1e6;
    bool open() => _seconds() < end;
    if (step.act case final act?) {
      await act(this, open);
    }
    while (open()) {
      await wait(100);
    }
    _open = null;
    window.end = _seconds();
    window.wallEnd = DateTime.now().millisecondsSinceEpoch / 1e3;
    window.images = GlassCopies.debugImagesDrawn - images;
    final (frames, sites) = _composed();
    if (frames > composed.$1) {
      window.misses['composer frames'] = frames - composed.$1;
      window.misses['composer sites'] = sites - composed.$2;
    }
    _windows.add(window);
    debugPrint('GLASS_BENCH ${step.name} ${window.start}..${window.end}');
  }

  (int, int) _composed() {
    var frames = 0;
    var sites = 0;
    for (final composer in GlassComposer.debugAllUnder(
      RendererBinding.instance.rootPipelineOwner,
    )) {
      frames += composer.census.frames;
      sites += composer.census.sites;
    }
    return (frames, sites);
  }

  void _timings(List<FrameTiming> timings) {
    final open = _open;
    if (open == null || _census) return;
    for (final t in timings) {
      open.raster.add(t.rasterDuration.inMicroseconds / 1e3);
      open.build.add(t.buildDuration.inMicroseconds / 1e3);
    }
  }

  void _frame(Duration _) {
    final open = _open;
    if (open == null) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_open != open) return;
      open.walked++;
      for (final view in RendererBinding.instance.renderViews) {
        _walk(view.layer, open.layers);
      }
    });
  }

  static void _walk(Layer? layer, Map<String, int> counts) {
    if (layer == null) return;
    final name = switch (layer) {
      OpacityLayer(:final alpha?) when alpha == 255 => null,
      OffsetLayer() when layer.runtimeType == OffsetLayer => null,
      ClipRectLayer(clipBehavior: Clip.hardEdge) => null,
      PictureLayer() => 'PictureLayer',
      _ => '${layer.runtimeType}',
    };
    if (name != null) counts[name] = (counts[name] ?? 0) + 1;
    if (name == 'BackdropFilterLayer') {
      final chain = <String>[];
      for (
        var up = layer.parent;
        up != null && chain.length < 7;
        up = up.parent
      ) {
        chain.add('${up.runtimeType}');
      }
      final key = '$name < ${chain.join(' < ')}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        _walk(child, counts);
      }
    }
  }

  void _report() {
    double pct(List<double> v, double p) {
      if (v.isEmpty) return 0;
      final s = [...v];
      s.sort();
      return s[math.min(s.length - 1, (s.length * p).floor())];
    }

    final lines = <Map<String, Object?>>[];
    for (final w in _windows) {
      final seconds = w.end - w.start;
      final line = {
        'scene': w.step,
        'start': w.start,
        'end': w.end,
        'wall_start': w.wallStart,
        'wall_end': w.wallEnd,
        'frames': w.raster.length,
        'raster_p50': pct(w.raster, 0.5),
        'raster_p90': pct(w.raster, 0.9),
        'build_p50': pct(w.build, 0.5),
        'images_per_s': w.images / seconds,
      };
      lines.add(line);
      debugPrint('GLASS_BENCH_WINDOW ${jsonEncode(line)}', wrapWidth: 1 << 20);
      if (_census && w.walked > 0) {
        final per = {
          for (final MapEntry(:key, :value) in w.layers.entries)
            key: (value / w.walked).toStringAsFixed(1),
        };
        debugPrint(
          'APP_CENSUS ${w.step} frames=${w.walked} '
          'images/frame=${(w.images / w.walked).toStringAsFixed(2)} '
          'misses=${jsonEncode(w.misses)} '
          '${jsonEncode(per)}',
          wrapWidth: 1 << 20,
        );
      }
    }
    // The iPhone's bench reads the windows from a file: its log is not at hand.
    final dir = Directory('${Directory.systemTemp.path}/glass_bench');
    dir.createSync();
    File(
      '${dir.path}/report.json',
    ).writeAsStringSync(jsonEncode({'windows': lines}));
    final anchor = _windows.first;
    final first = {
      'scene': anchor.step,
      'start': anchor.start,
      'end': anchor.end,
      'wall_start': anchor.wallStart,
    };
    debugPrint(
      'GLASS_BENCH_REPORT ${jsonEncode({
        'windows': [first],
      })}',
      wrapWidth: 1 << 20,
    );
  }

  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  Iterable<Element> _elements() sync* {
    final stack = <Element>[WidgetsBinding.instance.rootElement!];
    while (stack.isNotEmpty) {
      final element = stack.removeLast();
      yield element;
      final children = <Element>[];
      element.visitChildren(children.add);
      stack.addAll(children.reversed);
    }
  }

  bool _onScreen(Element element) {
    final box = element.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    if (!rect.overlaps(screen.deflate(1))) return false;
    final own = <RenderObject>{};
    void collect(Element e) {
      if (e.renderObject case final RenderObject node) own.add(node);
      e.visitChildren(collect);
    }

    collect(element);
    return _hits(rect.center).any((entry) => own.contains(entry.target));
  }

  Iterable<HitTestEntry> _hits(Offset at) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(
      result,
      at,
      WidgetsBinding.instance.platformDispatcher.implicitView!.viewId,
    );
    return result.path;
  }

  Element _first(bool Function(Widget) test, String what, int index) {
    final found = _elements()
        .where((e) => test(e.widget) && _onScreen(e))
        .toList();
    if (found.length <= index) {
      final all = [
        for (final e in _elements().where((e) => test(e.widget)))
          if (e.findRenderObject() case final RenderBox box when box.hasSize)
            _describe(box),
      ];
      throw StateError('app bench: no $what on screen (off screen: $all)');
    }
    return found[index];
  }

  String _describe(RenderBox box) {
    final r = box.localToGlobal(Offset.zero) & box.size;
    final path = _hits(r.center)
        .take(40)
        .map((e) => e.target.runtimeType)
        .join(" < ");
    return 'routes ${_routes()} ${r.left.round()},${r.top.round()} '
        '${r.width.round()}x${r.height.round()} hits $path';
  }

  List<String> _routes() => [
    for (final e in _elements())
      if (e is StatefulElement && e.state is NavigatorState)
        _top(e.state as NavigatorState),
  ];

  String _top(NavigatorState navigator) {
    Route<Object?>? top;
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    return '${top.runtimeType}';
  }

  Element find<T extends Widget>({int index = 0}) =>
      _first((w) => w is T, '$T', index);

  Element findText(String text) =>
      _first((w) => w is Text && w.data == text, 'text "$text"', 0);

  Element findLabel(String label) => _first(
    (w) => switch (w) {
      Semantics(:final properties) => properties.label == label,
      GlassButton(:final semanticLabel) => semanticLabel == label,
      _ => false,
    },
    'label "$label"',
    0,
  );

  Rect rect(Element element) {
    final box = element.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Offset center(Element element) => rect(element).center;

  Offset tabCenter(String label) {
    final tabs = _elements()
        .where((e) => e.widget is Text && (e.widget as Text).data == label)
        .map(rect)
        .where((r) => r.center.dy > screen.height * 0.8)
        .toList();
    if (tabs.isEmpty) throw StateError('app bench: no tab "$label"');
    return tabs.last.center;
  }

  Future<void> tapTab(String label) async {
    await tap(tabCenter(label));
    await wait(900);
  }

  Future<void> back() async {
    final navigator = _elements()
        .where((e) => e is StatefulElement && e.state is NavigatorState)
        .last;
    await ((navigator as StatefulElement).state as NavigatorState).maybePop();
  }

  void _send(PointerEvent event) =>
      GestureBinding.instance.handlePointerEvent(event);

  Duration get _now => Duration(microseconds: _clock.elapsedMicroseconds);

  Future<void> tap(Offset at) async {
    final pointer = _pointer++;
    _send(PointerDownEvent(pointer: pointer, position: at, timeStamp: _now));
    await wait(60);
    _send(PointerUpEvent(pointer: pointer, position: at, timeStamp: _now));
    await wait(16);
  }

  Future<void> drag(Offset from, Offset to, int ms) =>
      _move(from, to, ms, Curves.easeInOut);

  Future<void> fling(Offset from, Offset to, int ms) =>
      _move(from, to, ms, Curves.linear);

  Future<void> _move(Offset from, Offset to, int ms, Curve curve) async {
    final pointer = _pointer++;
    final start = _seconds();
    var last = from;
    _send(PointerDownEvent(pointer: pointer, position: from, timeStamp: _now));
    while (true) {
      await SchedulerBinding.instance.endOfFrame;
      final t = math.min<double>(1, (_seconds() - start) * 1000 / ms);
      final at = Offset.lerp(from, to, curve.transform(t))!;
      _send(
        PointerMoveEvent(
          pointer: pointer,
          position: at,
          delta: at - last,
          timeStamp: _now,
        ),
      );
      last = at;
      if (t >= 1) break;
    }
    _send(PointerUpEvent(pointer: pointer, position: to, timeStamp: _now));
  }

  /// Flings the page up and back down, with a pause to let it coast, until
  /// [open] says the window closed.
  Future<void> scrolling(bool Function() open) async {
    final x = screen.width * 0.5;
    final top = screen.height * 0.35;
    final bottom = screen.height * 0.7;
    while (open()) {
      await fling(Offset(x, bottom), Offset(x, top), 180);
      await wait(1300);
      await fling(Offset(x, top), Offset(x, bottom), 180);
      await wait(1300);
    }
  }

  Future<void> scrollTo<T extends Widget>() =>
      _scrollUntil((w) => w is T, '$T');

  Future<void> scrollToText(String text) =>
      _scrollUntil((w) => w is Text && w.data == text, '"$text"');

  /// Moves the page's own scroll position, not a finger: getting to a
  /// control is not what a step measures.
  Future<void> _scrollUntil(bool Function(Widget) test, String what) async {
    for (var i = 0; i < 30; i++) {
      final found = _elements().where((e) => test(e.widget)).where((e) {
        final box = e.findRenderObject();
        return box is RenderBox && box.attached && box.hasSize;
      });
      for (final element in found) {
        if (_onScreen(element) && rect(element).bottom < screen.height * 0.75) {
          return;
        }
      }
      if (found.isNotEmpty) {
        await Scrollable.ensureVisible(
          found.first,
          alignment: 0.4,
          duration: const Duration(milliseconds: 300),
        );
        await wait(500);
        if (_onScreen(found.first)) return;
      }
      final position = _page().position;
      await position.animateTo(
        math.min(
          position.maxScrollExtent,
          position.pixels + screen.height * 0.4,
        ),
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
      await wait(300);
    }
    throw StateError('app bench: no $what after scrolling');
  }

  ScrollableState _page() {
    final pages = _elements()
        .whereType<StatefulElement>()
        .map((e) => e.state)
        .whereType<ScrollableState>()
        .where(
          (s) =>
              s.position.axis == Axis.vertical &&
              _onScreen(s.context as Element),
        )
        .toList();
    if (pages.isEmpty) throw StateError('app bench: no page scrolls');
    pages.sort(
      (a, b) => rect(b.context as Element).height.compareTo(
        rect(a.context as Element).height,
      ),
    );
    return pages.first;
  }
}
