import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'paint_probe.dart';

/// The presentations that break the invariant today, each with what the
/// check observes. A presentation leaves the list when it passes.
const Map<String, String> known = {};

const _probeKey = Key('source probe');

/// A presentation that grows out of a source: how to build the source
/// around a probe, and how to open and close what grows out of it.
final class _Case {
  const _Case(
    this.name, {
    required this.build,
    required this.open,
    required this.close,
    required this.marker,
  });

  final String name;
  final Widget Function(_Handles handles, Widget probe) build;
  final Future<void> Function(WidgetTester tester, _Handles handles) open;
  final Future<void> Function(WidgetTester tester, _Handles handles) close;

  /// Finds what is on screen only while the presentation is open.
  final Finder marker;
}

/// What a case's source and its opening share.
final class _Handles {
  final navigator = GlobalKey<NavigatorState>();
  final menu = GlassMenuController();
  final zoom = MotionSource();
}

List<GlassMenuEntry> _entries() => [
  GlassMenuItem(title: 'Copy', onPressed: () {}),
  GlassMenuItem(title: 'Share', onPressed: () {}),
];

final _menuOpen = find.text('Copy');

Future<void> _tapProbe(WidgetTester tester, _Handles handles) =>
    tester.tap(find.byKey(_probeKey).first);

Future<void> _escape(WidgetTester tester, _Handles handles) =>
    tester.sendKeyEvent(LogicalKeyboardKey.escape);

final _cases = [
  _Case(
    'GlassMenuAnchor around a GlassButton',
    build: (handles, probe) => GlassMenuAnchor(
      controller: handles.menu,
      menuChildren: _entries(),
      child: GlassButton(onPressed: handles.menu.open, child: probe),
    ),
    open: _tapProbe,
    close: (tester, handles) async => handles.menu.close(),
    marker: _menuOpen,
  ),
  _Case(
    'GlassMenuAnchor around a plain widget',
    build: (handles, probe) => GlassMenuAnchor(
      controller: handles.menu,
      menuChildren: _entries(),
      child: probe,
    ),
    open: (tester, handles) async => handles.menu.open(),
    close: (tester, handles) async => handles.menu.close(),
    marker: _menuOpen,
  ),
  _Case(
    'GlassBarItem with a menu in a toolbar',
    build: (handles, probe) => GlassPageScaffold(
      toolbar: GlassToolbar(
        items: [GlassBarItem(label: probe, menuChildren: _entries())],
      ),
      child: const SizedBox.expand(),
    ),
    open: _tapProbe,
    close: _escape,
    marker: _menuOpen,
  ),
  _Case(
    'GlassBarItem with a menu in a navigation bar',
    build: (handles, probe) => GlassPageScaffold(
      navigationBar: GlassNavigationBar(
        title: const Text('Inbox'),
        trailing: [GlassBarItem(label: probe, menuChildren: _entries())],
      ),
      child: const SizedBox.expand(),
    ),
    open: _tapProbe,
    close: _escape,
    marker: _menuOpen,
  ),
  _Case(
    'GlassContextMenu',
    build: (handles, probe) =>
        GlassContextMenu(menuChildren: _entries(), child: probe),
    open: (tester, handles) async {
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(_probeKey).first),
      );
      await _rest(tester);
      await gesture.up();
    },
    close: _escape,
    marker: _menuOpen,
  ),
  _Case(
    'GlassPageRoute zooming out of a GlassZoomSource',
    build: (handles, probe) => GlassZoomSource(
      source: handles.zoom,
      borderRadius: 16,
      child: probe,
    ),
    open: (tester, handles) async {
      handles.navigator.currentState!.push(
        GlassPageRoute<void>(
          source: handles.zoom,
          builder: (context) => const ColoredBox(
            color: Color(0xFFFFFFFF),
            child: Center(child: Text('Detail')),
          ),
        ),
      );
    },
    close: (tester, handles) async => handles.navigator.currentState!.pop(),
    marker: find.text('Detail'),
  ),
];

void main() {
  setUp(MotionClock.debugReset);

  for (final c in _cases) {
    testWidgets('${c.name}: the source is not painted while what grows out '
        'of it is open, and is painted again once it closes', (tester) async {
      String? reason;
      try {
        await _invariant(tester, c);
      } on TestFailure catch (failure) {
        reason = failure.message;
      } finally {
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
      }
      final listed = known[c.name];
      if (listed == null) {
        if (reason != null) fail('${c.name}: $reason');
        return;
      }
      if (reason == null) fail('${c.name} passes now; remove it from `known`');
      expect(reason, listed, reason: '${c.name} fails for another reason');
    });
  }
}

Future<void> _rest(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _invariant(WidgetTester tester, _Case c) async {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  final handles = _Handles();
  final painted = <RenderObject>{};
  // A presentation may draw a copy of its source as it grows; only the
  // render objects of the source itself, found before anything opens,
  // count.
  final probe = SizedBox(
    width: 60,
    height: 30,
    child: Builder(
      builder: (context) => CustomPaint(
        key: _probeKey,
        painter: PaintProbe(() => painted.add(context.findRenderObject()!)),
      ),
    ),
  );
  await tester.pumpWidget(
    WidgetsApp(
      navigatorKey: handles.navigator,
      color: const Color(0xFF000000),
      pageRouteBuilder: <T>(settings, builder) =>
          GlassPageRoute<T>(builder: builder, settings: settings),
      builder: (context, child) =>
          GlassScope(renderer: const FlatGlassRenderer(), child: child!),
      home: ColoredBox(
        color: const Color(0xFFF2F2F7),
        child: Align(
          alignment: const Alignment(0, -0.3),
          child: c.build(handles, probe),
        ),
      ),
    ),
  );
  await _rest(tester);

  Future<Set<RenderObject>> paintsOf(Set<RenderObject>? only) async {
    painted.clear();
    await repaint(tester, find.byKey(_probeKey));
    return only == null ? {...painted} : painted.intersection(only);
  }

  final source = await paintsOf(null);
  if (source.isEmpty) throw TestFailure('the source does not paint at rest');

  await c.open(tester, handles);
  await _rest(tester);
  if (c.marker.evaluate().isEmpty) throw TestFailure('it did not open');
  if (source.any((object) => !object.attached)) {
    throw TestFailure('the source was rebuilt as it opened');
  }
  if ((await paintsOf(source)).isNotEmpty) {
    throw TestFailure('the source paints while it is open');
  }

  await c.close(tester, handles);
  await _rest(tester);
  if (c.marker.evaluate().isNotEmpty) throw TestFailure('it did not close');
  if ((await paintsOf(null)).isEmpty) {
    throw TestFailure('the source does not paint once it closed');
  }
}
