import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _titles = ['Copy', 'Share', 'Rename', 'Delete'];

Widget _app({bool haptics = true}) => WidgetsApp(
  color: const Color(0xFF000000),
  pageRouteBuilder: <T>(settings, builder) =>
      GlassPageRoute<T>(builder: builder, settings: settings),
  builder: (context, child) => MotionHapticScope(
    enabled: haptics,
    child: GlassScope(renderer: const FlatGlassRenderer(), child: child!),
  ),
  home: Align(
    alignment: const Alignment(0, -0.6),
    child: GlassMenuAnchor(
      menuChildren: [
        for (final title in _titles)
          GlassMenuItem(title: title, onPressed: () {}),
      ],
      builder: (context, controller, child) => GlassButton(
        key: const Key('button'),
        onPressed: controller.open,
        child: const Text('More'),
      ),
    ),
  ),
);

Future<void> _frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

Future<void> _slide(
  WidgetTester tester,
  TestGesture gesture,
  Offset from,
  Offset to,
) async {
  for (var i = 1; i <= 10; i++) {
    await gesture.moveTo(Offset.lerp(from, to, i / 10)!);
    await tester.pump(const Duration(milliseconds: 16));
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
    addTearDown(tester.view.reset);
  }

  testWidgets('the finger that held the button open clicks once for every '
      'row it slides onto', (tester) async {
    phone(tester);
    await tester.pumpWidget(_app());
    final button = find.byKey(const Key('button'));
    final gesture = await tester.startGesture(tester.getCenter(button));
    await _frames(tester, 30);
    expect(find.text('Rename'), findsOneWidget);
    await _slide(
      tester,
      gesture,
      tester.getCenter(button),
      tester.getCenter(find.text('Rename')),
    );
    final clicks = haptics.length;
    expect(clicks, greaterThanOrEqualTo(2));
    expect(haptics.toSet(), {'HapticFeedbackType.selectionClick'});
    await gesture.up();
    await _frames(tester, 30);
  });

  testWidgets('a new finger on the open menu clicks for every row it slides '
      'onto, and nothing plays where haptics are off', (tester) async {
    phone(tester);
    for (final on in [true, false]) {
      haptics.clear();
      await tester.pumpWidget(_app(haptics: on));
      await tester.tap(find.byKey(const Key('button')));
      await _frames(tester, 60);
      expect(find.text('Copy'), findsOneWidget);
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('Copy')),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await _slide(
        tester,
        gesture,
        tester.getCenter(find.text('Copy')),
        tester.getCenter(find.text('Delete')),
      );
      await gesture.up();
      await _frames(tester, 60);
      if (on) {
        expect(haptics, hasLength(greaterThanOrEqualTo(3)));
        expect(haptics.toSet(), {'HapticFeedbackType.selectionClick'});
      } else {
        expect(haptics, isEmpty);
      }
      await tester.pumpWidget(const SizedBox());
      await _frames(tester, 10);
    }
  });
}
