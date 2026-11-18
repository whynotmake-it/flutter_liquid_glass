import 'dart:ui' show Tristate;

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'paint_probe.dart';

Widget _app(Widget anchor) => WidgetsApp(
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) =>
      GlassScope(renderer: const FlatGlassRenderer(), child: child!),
  home: Align(alignment: const Alignment(0, -0.6), child: anchor),
);

List<GlassMenuEntry> _entries(List<String> log) => [
  for (final title in ['Copy', 'Share'])
    GlassMenuItem(title: title, onPressed: () => log.add(title)),
];

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(402, 874) * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 120; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUp(MotionClock.debugReset);

  testWidgets('what the menu grows out of leaves the screen while the menu '
      'is open and comes back when it closes, a button or not', (tester) async {
    for (final button in [true, false]) {
      _phone(tester);
      final controller = GlassMenuController();
      var paints = 0;
      // The menu's glass carries a copy of a button's label as it grows;
      // the probe counts only the paints of the one in the source.
      final label = SizedBox(
        width: 60,
        height: 30,
        child: Builder(
          builder: (context) => CustomPaint(
            key: const Key('probe'),
            painter: PaintProbe(() {
              if (!button ||
                  context.findAncestorWidgetOfExactType<GlassButton>() !=
                      null) {
                paints++;
              }
            }),
          ),
        ),
      );
      await tester.pumpWidget(
        _app(
          GlassMenuAnchor(
            controller: controller,
            menuChildren: _entries(<String>[]),
            child: button
                ? GlassButton(onPressed: controller.open, child: label)
                : label,
          ),
        ),
      );
      Future<bool> painted() async {
        paints = 0;
        await repaint(tester, find.byKey(const Key('probe')));
        return paints > 0;
      }

      expect(await painted(), isTrue, reason: 'button $button');
      controller.open();
      await _settle(tester);
      expect(find.text('Copy'), findsOneWidget);
      expect(await painted(), isFalse, reason: 'button $button');
      controller.close();
      await _settle(tester);
      expect(await painted(), isTrue, reason: 'button $button');
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('a button whose action opens the menu opens it on a tap after '
      'the measured delay, and the builder sees it open', (tester) async {
    _phone(tester);
    final open = <bool>[];
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          menuChildren: _entries(<String>[]),
          builder: (context, controller, child) {
            open.add(controller.isOpen);
            return GlassButton(
              key: const Key('button'),
              onPressed: controller.open,
              child: child!,
            );
          },
          child: const Text('More'),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('button')));
    await tester.pump();
    expect(find.text('Copy'), findsNothing);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Copy'), findsOneWidget);
    await _settle(tester);
    expect(open.last, isTrue);
  });

  testWidgets('onOpen and onClose bracket the menu', (tester) async {
    _phone(tester);
    final calls = <String>[];
    final controller = GlassMenuController();
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          controller: controller,
          onOpen: () => calls.add('open'),
          onClose: () => calls.add('close'),
          menuChildren: _entries(<String>[]),
          builder: (context, controller, child) => GlassButton(
            onPressed: controller.open,
            child: const Text('More'),
          ),
        ),
      ),
    );
    controller.open();
    await _settle(tester);
    expect(calls, ['open']);
    controller.close();
    await _settle(tester);
    expect(calls, ['open', 'close']);
  });

  testWidgets('plain text in a raw button is a source: a tap opens the menu '
      'and a row closes it', (tester) async {
    _phone(tester);
    final log = <String>[];
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          menuChildren: _entries(log),
          builder: (context, controller, child) => RawGlassButton(
            onPressed: controller.open,
            builder: (context, details) => details.label,
            child: child!,
          ),
          child: const SizedBox(
            width: 100,
            height: 44,
            child: Center(child: Text('Sort')),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sort'));
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    await tester.tap(find.text('Share'));
    await _settle(tester);
    expect(log, ['Share']);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('a button with an action of its own runs it on a tap, Space '
      'and Enter, and a hold opens the menu', (tester) async {
    _phone(tester);
    final log = <String>[];
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          menuChildren: _entries(log),
          builder: (context, controller, child) => GlassButton(
            key: const Key('button'),
            focusNode: focus,
            onPressed: () => log.add('pressed'),
            child: const Text('Share'),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const Key('button')));
    await _settle(tester);
    expect(log, ['pressed']);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _settle(tester);
    expect(log, ['pressed', 'pressed']);
    expect(find.text('Copy'), findsNothing);
    final gesture = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('button'))),
    );
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('Copy'), findsOneWidget);
    await gesture.up();
    await _settle(tester);
    expect(log, ['pressed', 'pressed']);
  });

  testWidgets('the control reads as an expandable button named by its label, '
      'and the focus comes back to it when the menu closes', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          menuChildren: _entries(<String>[]),
          builder: (context, controller, child) => GlassButton(
            focusNode: focus,
            onPressed: controller.open,
            semanticLabel: 'More',
            child: const Text('...'),
          ),
        ),
      ),
    );
    final node = tester
        .getSemantics(find.bySemanticsLabel('More'))
        .getSemanticsData();
    expect(node.flagsCollection.isExpanded, Tristate.isFalse);
    expect(node.flagsCollection.isButton, isTrue);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await _settle(tester);
    expect(find.text('Copy'), findsOneWidget);
    expect(focus.hasFocus, isFalse);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await _settle(tester);
    expect(find.text('Copy'), findsNothing);
    expect(focus.hasFocus, isTrue);
    handle.dispose();
  });

  testWidgets('a menu its source does not name reads "Menu" over a barrier '
      'read as "Dismiss menu"', (tester) async {
    _phone(tester);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      _app(
        GlassMenuAnchor(
          menuChildren: _entries(<String>[]),
          builder: (context, controller, child) => RawGlassButton(
            onPressed: controller.open,
            builder: (context, details) => details.label,
            child: child!,
          ),
          child: const SizedBox(width: 100, height: 44, child: Text('Sort')),
        ),
      ),
    );
    await tester.tap(find.text('Sort'));
    await _settle(tester);
    expect(find.bySemanticsLabel('Menu'), findsOneWidget);
    expect(find.bySemanticsLabel('Dismiss menu'), findsOneWidget);
    handle.dispose();
  });
}
