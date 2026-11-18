// Records the README animations: each scene plays a short script of touches
// on a widget in light and dark, under the code that builds it, with the
// liquid renderer, and writes one PNG per frame. tool/readme/render.dart runs
// it and encodes the frames; run that instead of this file.
//
// The clock of a widget test only moves when the test pumps, so a scene
// plays the same way on every run. That lets render.dart start again from
// the first missing frame after the tester process dies, which it sometimes
// does while it reads back a frame.
//
// fonts/ holds Inter (SIL Open Font License, Inter-OFL.txt), Roboto Mono
// (Apache 2.0) and CupertinoIcons (MIT, CupertinoIcons-LICENSE.txt), each cut
// down to the glyphs the scenes draw.

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:cupertino_ui/cupertino_ui.dart' show CupertinoIcons;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _out = String.fromEnvironment('README_FRAMES');
const _only = String.fromEnvironment('README_SCENE');
const _from = int.fromEnvironment('README_FROM');
const _fonts = String.fromEnvironment('README_FONTS');
const _fps = int.fromEnvironment('README_FPS', defaultValue: 30);

/// The view's height. The tester crashes reading some scenes back at one
/// height and not at another, so render.dart changes it between retries;
/// the canvas sits at the top and the frames are cut to it either way.
const _viewHeight = int.fromEnvironment('README_VIEW', defaultValue: 1600);

const _font = 'ReadmeSans';
const _mono = 'ReadmeMono';

/// The frames' pixels per point: sharp on a retina screen at a third of the
/// weight of 2x.
const _ratio = 1.5;
const _pad = 24.0;
const _gap = 12.0;
const _tick = Duration(milliseconds: 16);

/// How long the capture waits after a frame before reading it back, so the
/// host's software Vulkan finishes drawing the frame first. Reading back
/// while it still draws crashed the tester in a pipeline the frame used.
const _drain = Duration(milliseconds: 40);

void main() {
  for (final scene in _scenes) {
    if (_only.isNotEmpty && _only != scene.name) continue;
    testWidgets(scene.name, (tester) async {
      await _loadFonts(tester);
      tester.view.physicalSize =
          Size(scene.width, _viewHeight.toDouble()) * _ratio;
      tester.view.devicePixelRatio = _ratio;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_Canvas(scene: scene));
      for (var i = 0; i < 20; i++) {
        await tester.pump(_tick);
      }

      final frames = (scene.seconds * _fps).round();
      final dir = Directory('$_out/${scene.name}');
      dir.createSync(recursive: true);
      File('${dir.path}/count').writeAsStringSync('$frames');
      final size = tester.getSize(find.byKey(const ValueKey('canvas')));
      final layer = tester.binding.renderViews.first.debugLayer! as OffsetLayer;
      const step = Duration(microseconds: 1000000 ~/ _fps);
      final cues = [
        for (var cell = 0; cell < 2; cell++)
          _Cue(find.byKey(ValueKey(('cell', cell)))),
      ];

      for (var frame = 0; frame < frames; frame++) {
        for (final cue in cues) {
          for (final action in scene.script) {
            await action.play(tester, cue, frame);
          }
        }
        await tester.pump(step);
        if (frame < _from) continue;
        await tester.runAsync(() => Future<void>.delayed(_drain));
        final image = (await tester.runAsync(
          () => layer.toImage(Offset.zero & size * _ratio),
        ))!;
        final bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.png),
        ))!;
        image.dispose();
        File(
          '${dir.path}/${frame.toString().padLeft(4, '0')}.png',
        ).writeAsBytesSync(Uint8List.sublistView(bytes));
      }
    }, skip: !ui.ImageFilter.isShaderFilterSupported);
  }
}

Future<void> _loadFonts(WidgetTester tester) async {
  for (final (family, path) in [
    (_font, '$_fonts/Inter.ttf'),
    (_mono, '$_fonts/RobotoMono-Regular.ttf'),
    ('packages/cupertino_icons/CupertinoIcons', '$_fonts/CupertinoIcons.ttf'),
  ]) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    await tester.runAsync(
      () => ui.loadFontFromList(bytes, fontFamily: family),
    );
  }
}

/// One scene: the code over a widget in light and dark, and the script the
/// widget plays.
final class _Scene {
  const _Scene({
    required this.name,
    required this.code,
    required this.cell,
    required this.seconds,
    required this.script,
    required this.build,
    this.screen = false,
    this.plain = false,
  });

  final String name;
  final String code;
  final Size cell;
  final double seconds;
  final List<_Action> script;
  final WidgetBuilder build;

  /// Whether a cell is a piece of a phone screen, with its own navigator
  /// that presentations stay inside, rather than a backdrop of stripes.
  final bool screen;

  /// Whether a cell lies on a plain background, for a control without glass.
  final bool plain;

  double get width => _pad * 2 + cell.width * 2 + _gap;
}

/// The touches of one cell.
final class _Cue {
  _Cue(this.cell);

  final Finder cell;
  final Map<_Action, (TestGesture, Offset, Offset)> held = {};
  static var _pointer = 1;

  int nextPointer() => _pointer++;

  Finder within(Finder what) => find.descendant(of: cell, matching: what).first;

  BuildContext anchor(WidgetTester tester) =>
      tester.element(within(find.byKey(const ValueKey('anchor'))));
}

/// A step of a scene's script, from [start] to [end] seconds.
sealed class _Action {
  const _Action(this.start, this.end);

  final double start;
  final double end;

  /// Plays the part of the action that falls on [frame].
  Future<void> play(WidgetTester tester, _Cue cue, int frame);
}

int _frameAt(double seconds) => (seconds * _fps).round();

/// Puts a finger down on [target] at [start], moves it by [by], or onto
/// the center of [to], from [lift] seconds after that until [end] with an
/// ease, and lifts it at [end].
final class _Drag extends _Action {
  const _Drag(
    super.start,
    super.end,
    this.target, {
    this.by = Offset.zero,
    this.to,
    this.at,
    this.lift = 0.15,
    this.curve = Curves.easeInOut,
  });

  final _Target target;
  final Offset by;
  final _Target? to;

  /// Where on the target the finger lands, from its rect; its center when
  /// null.
  final Offset Function(Rect rect)? at;
  final double lift;

  /// How the finger moves; one that ends fast lets go in a flick.
  final Curve curve;

  @override
  Future<void> play(WidgetTester tester, _Cue cue, int frame) async {
    if (frame == _frameAt(start)) {
      final rect = tester.getRect(target(cue.cell));
      final from = at?.call(rect) ?? rect.center;
      final onto = to;
      final path = onto == null ? by : tester.getCenter(onto(cue.cell)) - from;
      final gesture = await tester.startGesture(
        from,
        pointer: cue.nextPointer(),
      );
      cue.held[this] = (gesture, from, path);
    }
    final held = cue.held[this];
    if (held == null) return;
    final (gesture, from, path) = held;
    final moveStart = _frameAt(start + lift);
    final last = _frameAt(end);
    if (frame > moveStart && path != Offset.zero) {
      final p = ((frame - moveStart) / (last - moveStart)).clamp(0.0, 1.0);
      final eased = curve.transform(p);
      await gesture.moveTo(from + path * eased);
    }
    if (frame == last) {
      await gesture.up();
      cue.held.remove(this);
    }
  }
}

/// A quick tap on [target] at [start].
final class _Tap extends _Drag {
  const _Tap(double start, _Target target, {super.at})
    : super(start, start + 0.1, target, lift: 0.1);
}

/// Runs [run] once at [start].
final class _Do extends _Action {
  const _Do(double start, this.run) : super(start, start);

  final void Function(WidgetTester tester, _Cue cue) run;

  @override
  Future<void> play(WidgetTester tester, _Cue cue, int frame) async {
    if (frame == _frameAt(start)) run(tester, cue);
  }
}

/// Finds what a step acts on inside one cell.
typedef _Target = Finder Function(Finder cell);

Finder _first(Finder cell, Finder what) =>
    find.descendant(of: cell, matching: what).first;

_Target _text(String text) =>
    (cell) => _first(cell, find.text(text));

Finder _type<T>(Finder cell) => _first(cell, find.byType(T));

final _scenes = <_Scene>[
  _Scene(
    name: 'switch',
    code: '''
GlassSwitch(
  value: wifi,
  onChanged: (value) => setState(() => wifi = value),
  style: GlassSwitch.styleFrom(
    activeTrackColor: GlassColors.systemBlue,
  ),
)''',
    cell: const Size(300, 150),
    seconds: 3.4,
    script: [
      _Drag(
        0.4,
        1.3,
        _type<GlassSwitch>,
        at: (rect) => rect.centerLeft + Offset(rect.height / 2, 0),
        by: const Offset(24, 0),
      ),
      const _Tap(2.2, _type<GlassSwitch>),
    ],
    build: (context) => const _Toggle(),
  ),
  _Scene(
    name: 'button',
    code: '''
GlassButton(onPressed: later, child: Text('Later'))
GlassButton.prominent(onPressed: water, child: Text('Water'))''',
    cell: const Size(300, 150),
    seconds: 3.4,
    script: [
      _Drag(0.4, 1.3, _text('Later'), by: const Offset(14, 4)),
      _Drag(1.8, 2.7, _text('Water'), by: const Offset(-14, 4)),
    ],
    build: (context) => Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GlassButton(onPressed: () {}, child: const Text('Later')),
        const SizedBox(width: 16),
        GlassButton.prominent(onPressed: () {}, child: const Text('Water')),
      ],
    ),
  ),
  _Scene(
    name: 'slider',
    code: '''
GlassSlider(
  value: volume,
  onChanged: (value) => setState(() => volume = value),
  style: GlassSlider.styleFrom(
    activeTrackColor: GlassColors.systemOrange,
  ),
)''',
    cell: const Size(300, 150),
    seconds: 3.6,
    script: [
      _Drag(
        0.4,
        1.5,
        _type<GlassSlider>,
        at: (rect) => rect.centerLeft + Offset(rect.width * 0.3, 0),
        by: const Offset(110, 0),
      ),
      _Drag(
        2,
        3,
        _type<GlassSlider>,
        at: (rect) => rect.centerLeft + Offset(rect.width * 0.75, 0),
        by: const Offset(-110, 0),
      ),
    ],
    build: (context) => const SizedBox(width: 240, child: _Slider()),
  ),
  _Scene(
    name: 'stepper',
    code: '''
GlassStepper(
  value: plants,
  max: 40,
  onChanged: (value) => setState(() => plants = value),
)''',
    cell: const Size(300, 150),
    seconds: 3.6,
    script: [
      for (final start in [0.4, 0.8, 1.2])
        _Tap(start, _type<GlassStepper>, at: _plus),
      for (final start in [2.0, 2.4, 2.8])
        _Tap(start, _type<GlassStepper>, at: _minus),
    ],
    build: (context) => const _Counter(),
  ),
  _Scene(
    name: 'segmented_control',
    code: '''
GlassSegmentedControl<Light>(
  segments: [
    for (final light in Light.values)
      GlassSegment(value: light, label: Text(light.title)),
  ],
  groupValue: light,
  onChanged: (value) => setState(() => light = value),
)''',
    cell: const Size(300, 150),
    seconds: 3.6,
    script: [
      _Drag(
        0.4,
        1.6,
        _type<GlassSegmentedControl<int>>,
        at: (rect) => rect.centerLeft + Offset(rect.width / 6, 0),
        to: _text('Sun'),
        lift: 0.3,
      ),
      _Tap(2.4, _text('Shade')),
    ],
    build: (context) => const _Segments(),
  ),
  _Scene(
    name: 'search_field',
    code: '''
GlassSearchField(
  controller: query,
  placeholder: Text('Search plants'),
)''',
    cell: const Size(300, 150),
    seconds: 3.2,
    script: [
      for (final (index, start) in [0.5, 0.65, 0.8, 0.95].indexed)
        _Do(
          start,
          (tester, cue) => _query(tester, cue, 'Fern'.substring(0, index + 1)),
        ),
      _Do(2.2, (tester, cue) => _query(tester, cue, '')),
    ],
    build: (context) => const SizedBox(width: 260, child: _Search()),
  ),
  _Scene(
    name: 'date_picker',
    code: '''
GlassDatePicker(
  value: repot,
  onChanged: (date) => setState(() => repot = date),
)''',
    cell: const Size(352, 360),
    plain: true,
    seconds: 4.4,
    script: [
      _Tap(0.4, _text('20')),
      _Tap(1.2, _arrow, at: (rect) => rect.center),
      _Tap(2.4, _arrowBack, at: (rect) => rect.center),
      _Tap(3.2, _text('13')),
    ],
    build: (context) => const _Calendar(),
  ),
  _Scene(
    name: 'list',
    code: '''
GlassSwipeActions(
  trailing: [
    GlassSwipeAction(title: 'Done', destructive: true, onPressed: done),
    GlassSwipeAction(title: 'Later', onPressed: later),
  ],
  child: GlassListRow(title: Text('Fern'), subtitle: Text('Kitchen')),
)''',
    screen: true,
    cell: const Size(402, 330),
    seconds: 3.2,
    script: [
      _Drag(
        0.4,
        1,
        _text('Fern'),
        by: const Offset(-150, 0),
        lift: 0.05,
      ),
      _Drag(
        2,
        2.5,
        _text('Monstera'),
        at: (rect) => rect.center - const Offset(0, 55),
        by: const Offset(150, 0),
        lift: 0.05,
      ),
    ],
    build: (context) => const _ListScreen(),
  ),
  _Scene(
    name: 'navigation_bar',
    code: '''
GlassPageScaffold(
  navigationBar: GlassNavigationBar(
    largeTitle: Text('Journal'),
    trailing: [GlassBarItem.prominent(label: Text('Done'), onPressed: done)],
  ),
  toolbar: GlassToolbar(items: [...]),
  child: GlassContentScroll(child: ListView(...)),
)''',
    screen: true,
    cell: const Size(402, 520),
    seconds: 4,
    script: [
      _Drag(
        0.4,
        1.2,
        _text('Pothos'),
        by: const Offset(0, -260),
        lift: 0.05,
      ),
      _Drag(
        2.2,
        3,
        _text('Peace lily'),
        by: const Offset(0, 300),
        lift: 0.05,
      ),
    ],
    build: (context) => const _JournalScreen(),
  ),
  _Scene(
    name: 'tab_bar',
    code: '''
GlassTabBar(
  destinations: [
    GlassTabDestination(icon: Icon(CupertinoIcons.tree), label: Text('Plants')),
    GlassTabDestination(icon: Icon(CupertinoIcons.drop), label: Text('Water')),
    GlassTabDestination(icon: Icon(CupertinoIcons.sun_max), label: Text('Light')),
  ],
  selectedIndex: tab,
  onDestinationSelected: (index) => setState(() => tab = index),
)''',
    screen: true,
    cell: const Size(402, 400),
    seconds: 4,
    script: [
      const _Drag(0.4, 1.8, _tabPlants, to: _tabLight, lift: 0.3),
      const _Tap(2.8, _tabPlants),
    ],
    build: (context) => const _TabScreen(),
  ),
  _Scene(
    name: 'menu',
    code: '''
GlassMenuAnchor(
  menuChildren: [
    GlassMenuItem(title: 'Water', icon: Icon(CupertinoIcons.drop), onPressed: water),
    GlassSubmenu(title: 'Sort by', children: [...]),
    GlassMenuItem(title: 'Compost', destructive: true, onPressed: compost),
  ],
  builder: (context, controller, child) =>
      GlassButton(onPressed: controller.open, child: Text('Options')),
)''',
    screen: true,
    cell: const Size(402, 600),
    seconds: 4.4,
    script: [
      _Tap(0.4, _text('Options')),
      _Tap(1.6, _text('Sort by')),
      _Tap(3.2, _text('Plants'), at: (rect) => rect.topLeft),
    ],
    build: (context) => const _MenuScreen(),
  ),
  _Scene(
    name: 'sheet',
    code: '''
showGlassSheet(
  context,
  detents: [GlassSheetDetent.medium, GlassSheetDetent.large],
  showDragHandle: true,
  builder: (context) => PlantDetails(plant),
)''',
    screen: true,
    cell: const Size(402, 720),
    seconds: 5,
    script: [
      const _Do(0.3, _openSheet),
      const _Drag(
        1.5,
        2.1,
        _grabber,
        by: Offset(0, -300),
        lift: 0.05,
      ),
      const _Drag(
        2.8,
        3.1,
        _grabber,
        by: Offset(0, 420),
        lift: 0.05,
        curve: Curves.easeIn,
      ),
      const _Drag(
        3.7,
        4,
        _grabber,
        by: Offset(0, 380),
        lift: 0.05,
        curve: Curves.easeIn,
      ),
    ],
    build: (context) => const _PlantsScreen(),
  ),
  _Scene(
    name: 'alert',
    code: '''
showGlassAlert(
  context,
  title: Text('The fern has dried out'),
  message: Text('It has had no water for three weeks.'),
  actions: [
    GlassAlertAction.cancel(child: Text('Cancel')),
    GlassAlertAction(isDefaultAction: true, child: Text('Keep'), onPressed: keep),
  ],
)''',
    screen: true,
    cell: const Size(402, 640),
    seconds: 5,
    script: [
      const _Do(0.3, _openAlert),
      _Drag(1.3, 1.9, _text('Keep'), by: const Offset(-8, 0)),
      _Do(2.5, (tester, cue) => _openAlert(tester, cue, sheet: true)),
      _Tap(3.8, _text('Cancel')),
    ],
    build: (context) => const _PlantsScreen(),
  ),
];

Offset _plus(Rect rect) => rect.centerRight - Offset(rect.width / 4, 0);

Offset _minus(Rect rect) => rect.centerLeft + Offset(rect.width / 4, 0);

Finder _arrows() => find.byWidgetPredicate(
  (widget) => widget.runtimeType.toString() == '_Arrow',
);

Finder _arrow(Finder cell) =>
    find.descendant(of: cell, matching: _arrows()).last;

Finder _arrowBack(Finder cell) => _first(cell, _arrows());

Finder _tab(String name) =>
    find.descendant(of: find.byType(GlassTabBar), matching: find.text(name));

Finder _tabPlants(Finder cell) => _first(cell, _tab('Plants'));

Finder _tabLight(Finder cell) => _first(cell, _tab('Light'));

Finder _grabber(Finder cell) => _first(
  cell,
  find.byWidgetPredicate(
    (widget) =>
        widget is InputRegion && widget.semantics?.label == 'Sheet grabber',
  ),
);

void _query(WidgetTester tester, _Cue cue, String text) {
  tester.state<_SearchState>(cue.within(find.byType(_Search))).query.text =
      text;
}

void _openSheet(WidgetTester tester, _Cue cue) {
  showGlassSheet<void>(
    cue.anchor(tester),
    detents: const [GlassSheetDetent.medium, GlassSheetDetent.large],
    showDragHandle: true,
    builder: (context) => const _PlantDetails(),
  );
}

void _openAlert(WidgetTester tester, _Cue cue, {bool sheet = false}) {
  final context = cue.anchor(tester);
  const title = Text('The fern has dried out');
  const message = Text('It has had no water for three weeks.');
  if (sheet) {
    showGlassActionSheet(
      context,
      title: title,
      message: message,
      actions: [
        GlassAlertAction(child: const Text('Give away'), onPressed: () {}),
        GlassAlertAction.destructive(
          child: const Text('Compost'),
          onPressed: () {},
        ),
        const GlassAlertAction.cancel(child: Text('Cancel')),
      ],
    );
  } else {
    showGlassAlert(
      context,
      title: title,
      message: message,
      actions: [
        const GlassAlertAction.cancel(child: Text('Cancel')),
        GlassAlertAction(
          isDefaultAction: true,
          child: const Text('Keep'),
          onPressed: () {},
        ),
      ],
    );
  }
}

class _Canvas extends StatelessWidget {
  const _Canvas({required this.scene});

  final _Scene scene;

  @override
  Widget build(BuildContext context) => WidgetsApp(
    color: const Color(0xFFFFFFFF),
    debugShowCheckedModeBanner: false,
    builder: (context, _) => GlassScope(
      renderer: const LiquidGlassRenderer(),
      data: const GlassThemeData(
        brightness: Brightness.light,
        fontFamily: _font,
      ),
      child: ColoredBox(
        color: const Color(0xFFF2F2F7),
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            key: const ValueKey('canvas'),
            padding: const EdgeInsets.all(_pad),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: scene.width - _pad * 2,
                  child: _Code(scene.code),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _Cell(
                      key: const ValueKey(('cell', 0)),
                      scene: scene,
                      brightness: Brightness.light,
                    ),
                    const SizedBox(width: _gap),
                    _Cell(
                      key: const ValueKey(('cell', 1)),
                      scene: scene,
                      brightness: Brightness.dark,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.scene,
    required this.brightness,
    super.key,
  });

  final _Scene scene;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final dark = brightness == Brightness.dark;
    final body = GlassTheme(
      data: GlassThemeData(brightness: brightness, fontFamily: _font),
      child: DefaultTextStyle(
        style: TextStyle(
          fontFamily: _font,
          fontSize: 17,
          color: dark ? const Color(0xFFFFFFFF) : const Color(0xFF000000),
        ),
        child: scene.screen
            ? MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  size: scene.cell,
                  padding: const EdgeInsets.only(top: 12, bottom: 12),
                  viewPadding: const EdgeInsets.only(top: 12, bottom: 12),
                ),
                child: PresentationContext(
                  child: Navigator(
                    onGenerateRoute: (settings) => PageRouteBuilder<void>(
                      settings: settings,
                      pageBuilder: (context, _, _) => KeyedSubtree(
                        key: const ValueKey('anchor'),
                        child: Builder(builder: scene.build),
                      ),
                    ),
                  ),
                ),
              )
            : Stack(
                fit: StackFit.expand,
                children: [
                  if (scene.plain)
                    ColoredBox(
                      color: dark
                          ? const Color(0xFF1C1C1E)
                          : const Color(0xFFFFFFFF),
                    )
                  else
                    CustomPaint(painter: _Backdrop(dark: dark)),
                  Center(child: Builder(builder: scene.build)),
                ],
              ),
      ),
    );
    final radius = BorderRadius.circular(scene.screen ? 34 : 20);
    return SizedBox.fromSize(
      size: scene.cell,
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: radius,
          border: scene.screen
              ? Border.all(color: const Color(0x24000000))
              : null,
        ),
        child: ClipRRect(borderRadius: radius, child: body),
      ),
    );
  }
}

class _Toggle extends StatefulWidget {
  const _Toggle();

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  var _value = false;

  @override
  Widget build(BuildContext context) => GlassSwitch(
    style: GlassSwitch.styleFrom(activeTrackColor: GlassColors.systemBlue),
    value: _value,
    onChanged: (value) => setState(() => _value = value),
  );
}

class _Slider extends StatefulWidget {
  const _Slider();

  @override
  State<_Slider> createState() => _SliderState();
}

class _SliderState extends State<_Slider> {
  var _value = 0.3;

  @override
  Widget build(BuildContext context) => GlassSlider(
    value: _value,
    style: GlassSlider.styleFrom(activeTrackColor: GlassColors.systemOrange),
    onChanged: (value) => setState(() => _value = value),
  );
}

class _Counter extends StatefulWidget {
  const _Counter();

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  var _plants = 3.0;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      SizedBox(
        width: 90,
        child: Text(
          '${_plants.round()} plants',
          style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
        ),
      ),
      GlassStepper(
        value: _plants,
        max: 40,
        onChanged: (value) => setState(() => _plants = value),
      ),
    ],
  );
}

class _Segments extends StatefulWidget {
  const _Segments();

  @override
  State<_Segments> createState() => _SegmentsState();
}

class _SegmentsState extends State<_Segments> {
  var _picked = 0;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 260,
    child: GlassSegmentedControl<int>(
      segments: [
        for (final (index, name) in const ['Shade', 'Partial', 'Sun'].indexed)
          GlassSegment(value: index, label: Text(name)),
      ],
      groupValue: _picked,
      onChanged: (value) => setState(() => _picked = value),
    ),
  );
}

class _Search extends StatefulWidget {
  const _Search();

  @override
  State<_Search> createState() => _SearchState();
}

class _SearchState extends State<_Search> {
  final query = TextEditingController();

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => GlassSearchField(
    controller: query,
    placeholder: const Text('Search plants'),
  );
}

class _Calendar extends StatefulWidget {
  const _Calendar();

  @override
  State<_Calendar> createState() => _CalendarState();
}

class _CalendarState extends State<_Calendar> {
  var _date = DateTime(2026, 11, 13);

  @override
  Widget build(BuildContext context) => GlassDatePicker(
    value: _date,
    today: DateTime(2026, 11, 13),
    onChanged: (date) => setState(() => _date = date),
  );
}

const _plants = [
  ('Fern', 'Kitchen'),
  ('Monstera', 'Living room'),
  ('Pothos', 'Bedroom'),
  ('Calathea', 'Bathroom'),
  ('Ficus', 'Office'),
  ('Aloe', 'Balcony'),
  ('Peace lily', 'Hall'),
  ('Snake plant', 'Bedroom'),
  ('Orchid', 'Kitchen'),
  ('Cactus', 'Office'),
  ('Jade', 'Hall'),
  ('Basil', 'Kitchen'),
];

class _ListScreen extends StatelessWidget {
  const _ListScreen();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: GlassDynamicColor.resolve(
      GlassColors.systemGroupedBackground,
      context,
    ),
    child: ListView(
      padding: const EdgeInsets.only(top: 12),
      children: [
        GlassListSection(
          header: const Text('Thirsty'),
          children: [
            for (final (name, room) in _plants.take(4))
              GlassSwipeActions(
                trailing: [
                  GlassSwipeAction(
                    title: 'Done',
                    destructive: true,
                    onPressed: () {},
                  ),
                  GlassSwipeAction(
                    title: 'Later',
                    backgroundColor: GlassColors.systemOrange,
                    onPressed: () {},
                  ),
                ],
                child: GlassListRow(
                  title: Text(name),
                  subtitle: Text(room),
                  onPressed: () {},
                ),
              ),
          ],
        ),
      ],
    ),
  );
}

class _JournalScreen extends StatelessWidget {
  const _JournalScreen();

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    navigationBar: GlassNavigationBar(
      largeTitle: const Text('Journal'),
      trailing: [
        GlassBarItem.prominent(label: const Text('Done'), onPressed: () {}),
      ],
    ),
    toolbar: GlassToolbar(
      items: [
        GlassBarItem(
          icon: const Icon(CupertinoIcons.camera),
          semanticLabel: 'Add a photo',
          onPressed: () {},
        ),
        const GlassBarSpacer.flexible(),
        GlassBarItem(
          icon: const Icon(CupertinoIcons.square_pencil),
          semanticLabel: 'Write',
          onPressed: () {},
        ),
      ],
    ),
    child: const _Plants(),
  );
}

class _TabScreen extends StatefulWidget {
  const _TabScreen();

  @override
  State<_TabScreen> createState() => _TabScreenState();
}

class _TabScreenState extends State<_TabScreen> {
  var _tab = 0;

  static const _titles = ['Plants', 'Water', 'Light'];

  @override
  Widget build(BuildContext context) => GlassTabScaffold(
    backgroundColor: GlassColors.systemGroupedBackground,
    tabBar: GlassTabBar(
      destinations: const [
        GlassTabDestination(
          icon: Icon(CupertinoIcons.tree),
          label: Text('Plants'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.drop),
          label: Text('Water'),
        ),
        GlassTabDestination(
          icon: Icon(CupertinoIcons.sun_max),
          label: Text('Light'),
        ),
      ],
      selectedIndex: _tab,
      onDestinationSelected: (index) => setState(() => _tab = index),
    ),
    tabBuilder: (context, index) => _PlantsScreen(title: _titles[index]),
  );
}

class _PlantsScreen extends StatelessWidget {
  const _PlantsScreen({this.title = 'Plants'});

  final String title;

  @override
  Widget build(BuildContext context) => GlassPageScaffold(
    navigationBar: GlassNavigationBar(largeTitle: Text(title)),
    child: const _Plants(),
  );
}

class _Plants extends StatelessWidget {
  const _Plants();

  @override
  Widget build(BuildContext context) => GlassContentScroll(
    child: ListView(
      children: [
        for (final (name, room) in _plants)
          GlassListRow(
            leading: _Swatch(name),
            title: Text(name),
            subtitle: Text(room),
            onPressed: () {},
          ),
      ],
    ),
  );
}

class _MenuScreen extends StatelessWidget {
  const _MenuScreen();

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const _PlantsScreen(),
      Align(
        alignment: const Alignment(0.8, 0.9),
        child: GlassMenuAnchor(
          menuChildren: [
            GlassMenuItem(
              title: 'Water',
              icon: const Icon(CupertinoIcons.drop),
              onPressed: () {},
            ),
            GlassMenuItem(
              title: 'Move',
              icon: const Icon(CupertinoIcons.arrow_right_arrow_left),
              onPressed: () {},
            ),
            GlassSubmenu(
              title: 'Sort by',
              subtitle: 'Thirst',
              icon: const Icon(CupertinoIcons.arrow_up_arrow_down),
              singleSelection: true,
              children: [
                for (final sort in const ['Thirst', 'Name', 'Room'])
                  GlassMenuItem(title: sort, onPressed: () {}),
              ],
            ),
            GlassMenuItem(
              title: 'Compost',
              icon: const Icon(CupertinoIcons.trash),
              destructive: true,
              onPressed: () {},
            ),
          ],
          builder: (context, controller, child) => GlassButton(
            onPressed: controller.open,
            child: const Text('Options'),
          ),
        ),
      ),
    ],
  );
}

class _PlantDetails extends StatelessWidget {
  const _PlantDetails();

  @override
  Widget build(BuildContext context) => ListView(
    controller: GlassSheet.scrollControllerOf(context),
    padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
    children: const [
      GlassDefaultTextStyle(
        role: GlassTextRole.title2,
        child: Text('Fern'),
      ),
      SizedBox(height: 6),
      Text('Water every three days. Keep out of the noon sun.'),
      SizedBox(height: 16),
      GlassListSection(
        children: [
          GlassListRow(
            title: Text('Room'),
            detail: Text('Kitchen'),
          ),
          GlassListRow(
            title: Text('Light'),
            detail: Text('Partial'),
          ),
        ],
      ),
    ],
  );
}

class _Swatch extends StatelessWidget {
  const _Swatch(this.name);

  final String name;

  static const _colors = [
    Color(0xFF34C759),
    Color(0xFF30B0C7),
    Color(0xFFFF9500),
    Color(0xFFAF52DE),
    Color(0xFFFF2D55),
  ];

  @override
  Widget build(BuildContext context) => Container(
    width: 30,
    height: 30,
    decoration: BoxDecoration(
      color: _colors[name.length % _colors.length],
      borderRadius: BorderRadius.circular(8),
    ),
    alignment: Alignment.center,
    child: const Icon(CupertinoIcons.tree, size: 18, color: Color(0xFFFFFFFF)),
  );
}

/// Dart code, colored the way Xcode colors Swift.
class _Code extends StatelessWidget {
  const _Code(this.code);

  final String code;

  static const _plain = Color(0xFF1F1F24);
  static const _type = Color(0xFF0B4F79);
  static const _name = Color(0xFF326D74);
  static const _string = Color(0xFFC41A16);
  static const _keyword = Color(0xFF9B2393);
  static const _keywords = {'final', 'for', 'in', 'true', 'false', 'null'};
  static final _token = RegExp("'[^']*'|[A-Za-z_][A-Za-z_0-9]*|[^A-Za-z_']+");
  static final _upper = RegExp('^[A-Z]');
  static final _lower = RegExp('^[a-z]');

  List<TextSpan> _spans() => [
    for (final match in _token.allMatches(code))
      _span(match[0]!, code.substring(match.end)),
  ];

  TextSpan _span(String text, String rest) {
    final color = switch (text) {
      _ when text.startsWith("'") => _string,
      _ when _keywords.contains(text) => _keyword,
      _ when _upper.hasMatch(text) => _type,
      _
          when _lower.hasMatch(text) &&
              (rest.startsWith(':') || rest.startsWith('(')) =>
        _name,
      _ => _plain,
    };
    return TextSpan(
      text: text,
      style: color == _plain ? null : TextStyle(color: color),
    );
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: const Color(0xFFFFFFFF),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE5E5EA)),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(
            fontFamily: _mono,
            fontSize: 13,
            height: 1.5,
            color: _plain,
          ),
          children: _spans(),
        ),
      ),
    ),
  );
}

/// Diagonal stripes under a control, so its glass has something to bend.
class _Backdrop extends CustomPainter {
  const _Backdrop({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topLeft,
          rect.bottomRight,
          dark
              ? const [Color(0xFF1B1F3B), Color(0xFF3A1C4A)]
              : const [Color(0xFFFFE3D1), Color(0xFFD9E7FF)],
        ),
    );
    final colors = dark
        ? const [Color(0xFF5E5CE6), Color(0xFFFF375F), Color(0xFF30D158)]
        : const [Color(0xFFFF9F0A), Color(0xFF0A84FF), Color(0xFFFF2D55)];
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-math.pi / 7);
    final count = (size.longestSide / 16).ceil();
    for (var i = -count; i <= count; i++) {
      canvas.drawRect(
        Rect.fromLTWH(i * 16.0, -size.longestSide, 5, size.longestSide * 2),
        Paint()
          ..color = colors[(i + count) % 3].withValues(
            alpha: dark ? 0.45 : 0.4,
          ),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Backdrop oldDelegate) => oldDelegate.dark != dark;
}
