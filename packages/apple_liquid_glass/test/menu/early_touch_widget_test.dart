import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _titles = ['Copy', 'Share', 'Rename', 'Delete'];
const _frame = Duration(milliseconds: 16);
final _button = find.byKey(const Key('button'));

Widget _app(List<String> log) => WidgetsApp(
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) =>
      GlassScope(renderer: const FlatGlassRenderer(), child: child!),
  home: Stack(
    children: [
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => log.add('page'),
          child: const SizedBox.expand(),
        ),
      ),
      Align(
        alignment: const Alignment(0, -0.6),
        child: GlassMenuAnchor(
          menuChildren: [
            for (final title in _titles)
              GlassMenuItem(title: title, onPressed: () => log.add(title)),
          ],
          builder: (context, controller, child) => GlassButton(
            key: const Key('button'),
            onPressed: controller.open,
            child: const Text('More'),
          ),
        ),
      ),
    ],
  ),
);

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(_frame);
  }
}

void main() {
  setUp(MotionClock.debugReset);

  final haptics = <String>[];

  setUp(() {
    haptics.clear();
    TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add(call.arguments as String);
          }
          return null;
        });
  });

  tearDown(
    () => TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null),
  );

  void phone(WidgetTester tester) {
    tester.view.physicalSize = const Size(402, 874) * 3;
    tester.view.devicePixelRatio = 3;
    tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
    addTearDown(tester.view.reset);
  }

  // Opens the menu once by a tap and returns the centres of its rows, then
  // closes it.
  Future<Map<String, Offset>> rows(WidgetTester tester) async {
    await tester.tap(_button);
    await _frames(tester, 90);
    final centres = {
      for (final title in _titles) title: tester.getCenter(find.text(title)),
    };
    await tester.tapAt(const Offset(380, 860));
    await _frames(tester, 120);
    expect(find.text('Copy'), findsNothing);
    return centres;
  }

  testWidgets('a finger put down between the tap and the opening belongs to '
      'the menu: lifted on a row once it shows, it chooses that row', (
    tester,
  ) async {
    phone(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(log));
    final centres = await rows(tester);
    log.clear();
    await tester.tap(_button);
    await tester.pump(_frame);
    expect(find.text('Rename'), findsNothing);
    final finger = await tester.startGesture(centres['Rename']!);
    await _frames(tester, 30);
    expect(find.text('Rename'), findsOneWidget);
    await finger.up();
    await _frames(tester, 120);
    // No barrier shows yet, so the page under the finger hears it too.
    expect(log, ['page', 'Rename']);
    expect(find.text('Rename'), findsNothing);
  });

  testWidgets('a tap outside between the tap and the opening closes the '
      'menu with no action and reaches the page', (tester) async {
    phone(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(log));
    await tester.tap(_button);
    await tester.pump(_frame);
    await tester.tapAt(const Offset(380, 860));
    await _frames(tester, 150);
    expect(log, ['page']);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('an early finger that slides over the open menu clicks for the '
      'rows it comes onto and chooses the one it lifts from', (tester) async {
    phone(tester);
    final log = <String>[];
    await tester.pumpWidget(_app(log));
    final centres = await rows(tester);
    log.clear();
    haptics.clear();
    await tester.tap(_button);
    await tester.pump(_frame);
    final from = centres['Copy']!;
    final to = centres['Delete']!;
    final finger = await tester.startGesture(from);
    await _frames(tester, 30);
    for (var i = 1; i <= 10; i++) {
      await finger.moveTo(Offset.lerp(from, to, i / 10)!);
      await tester.pump(_frame);
    }
    await finger.up();
    await _frames(tester, 120);
    expect(haptics, hasLength(greaterThanOrEqualTo(2)));
    expect(haptics.toSet(), {'HapticFeedbackType.selectionClick'});
    expect(log, ['Delete']);
  });
}
