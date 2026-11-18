import 'dart:async';

import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);
const _size = Size(402, 874);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 150; i++) {
    await tester.pump(_frame);
  }
}

final class _Case {
  const _Case(this.name, this.open, this.close);

  final String name;

  // Shows the presentation holding the text 'Content'.
  final Future<void> Function(WidgetTester tester, BuildContext context) open;

  // Starts its close.
  final Future<void> Function(WidgetTester tester, BuildContext context) close;
}

Future<void> _tapOutside(WidgetTester tester, BuildContext context) =>
    tester.tapAt(const Offset(350, 800));

Future<void> _pop(WidgetTester tester, BuildContext context) async {
  Navigator.of(context, rootNavigator: true).pop();
}

final _cases = [
  _Case('menu', (tester, context) async {
    await tester.tap(find.text('Menu'));
  }, _tapOutside),
  _Case('context menu', (tester, context) async {
    final finger = await tester.startGesture(
      tester.getCenter(find.byKey(const Key('held'))),
    );
    for (var i = 0; i < 60; i++) {
      await tester.pump(_frame);
    }
    await finger.up();
  }, _tapOutside),
  _Case('alert', (tester, context) async {
    unawaited(
      showGlassAlert(
        context,
        title: const Text('Content'),
        actions: [const GlassAlertAction(child: Text('OK'))],
      ),
    );
  }, (tester, context) => tester.tap(find.text('OK'))),
  _Case('action sheet', (tester, context) async {
    unawaited(
      showGlassActionSheet(
        context,
        title: const Text('Content'),
        actions: [const GlassAlertAction(child: Text('OK'))],
      ),
    );
  }, (tester, context) => tester.tap(find.text('OK'))),
  _Case('sheet', (tester, context) async {
    unawaited(
      showGlassSheet<void>(
        context,
        builder: (context) => const Text('Content'),
      ),
    );
  }, _pop),
  _Case('popover', (tester, context) async {
    unawaited(
      showGlassPopover<void>(
        context,
        anchorRect: const Rect.fromLTWH(180, 400, 40, 40),
        adaptsToSheet: false,
        builder: (context) => const Text('Content'),
      ),
    );
  }, _tapOutside),
];

void main() {
  setUp(MotionClock.debugReset);

  for (final kase in _cases) {
    for (final ms in [100, 200, 300, 500, 800, 1500]) {
      testWidgets('$ms ms into its close, a ${kase.name} lets a tap reach what '
          'is below and leaves nothing running', (tester) async {
        tester.view.physicalSize = _size * 3;
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        var taps = 0;
        late BuildContext page;
        await tester.pumpWidget(
          MediaQuery(
            data: const MediaQueryData(
              size: _size,
              devicePixelRatio: 3,
              padding: EdgeInsets.only(top: 62, bottom: 34),
            ),
            child: GlassScope(
              renderer: const FlatGlassRenderer(),
              child: WidgetsApp(
                color: const Color(0xFFFFFFFF),
                textStyle: const TextStyle(fontSize: 17),
                pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
                  settings: settings,
                  pageBuilder: (context, _, _) => builder(context),
                ),
                home: Builder(
                  builder: (context) {
                    page = context;
                    return Stack(
                      children: [
                        Positioned(
                          left: 16,
                          top: 100,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => taps++,
                            child: const SizedBox(
                              key: Key('below'),
                              width: 100,
                              height: 60,
                            ),
                          ),
                        ),
                        const Align(
                          alignment: Alignment(0, 0.5),
                          child: GlassContextMenu(
                            menuChildren: [GlassMenuItem(title: 'Content')],
                            child: SizedBox(
                              key: Key('held'),
                              width: 120,
                              height: 44,
                            ),
                          ),
                        ),
                        Center(
                          child: GlassMenuAnchor(
                            menuChildren: const [
                              GlassMenuItem(title: 'Content'),
                            ],
                            builder: (context, controller, child) =>
                                GlassButton(
                                  onPressed: controller.open,
                                  child: const Text('Menu'),
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
        );
        await tester.pump();
        await kase.open(tester, page);
        await _settle(tester);
        expect(find.text('Content'), findsOneWidget);
        await kase.close(tester, page);
        for (var e = 0; e < ms; e += 16) {
          await tester.pump(_frame);
        }
        await tester.tapAt(tester.getCenter(find.byKey(const Key('below'))));
        await _settle(tester);
        expect(taps, 1);
        expect(find.text('Content'), findsNothing);
        expect(tester.binding.hasScheduledFrame, isFalse);
      });
    }
  }
}
