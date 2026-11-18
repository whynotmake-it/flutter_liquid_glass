import 'package:apple_liquid_glass/apple_liquid_glass.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

const _frame = Duration(milliseconds: 16);

const _wide = 300.0;
const _narrow = 100.0;

Widget _app(Widget child) => MediaQuery(
  data: const MediaQueryData(),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: GlassScope(
      renderer: const FlatGlassRenderer(),
      child: Center(child: child),
    ),
  ),
);

Widget _plain(BuildContext context, GlassButtonDetails details) =>
    GlassSurface.live(frame: details.body, child: details.label);

Future<void> _pressShrinkRelease(
  WidgetTester tester,
  Finder found,
  ValueNotifier<double> width,
  double past,
) async {
  final wide = tester.getRect(found);
  final gesture = await tester.startGesture(wide.center);
  await tester.pump(_frame);
  width.value = _narrow;
  await tester.pump(_frame);
  final narrow = tester.getRect(found);
  expect(narrow.center.dx, moreOrLessEquals(wide.center.dx, epsilon: 0.5));
  expect(narrow.width, lessThan(wide.width - 2 * (80 - 60)));
  final release = Offset(narrow.right + past, narrow.center.dy);
  expect(
    wide.inflate(glassButtonReach.slop).contains(release),
    isTrue,
    reason: 'the body as it was at the touch would hold every release',
  );
  await gesture.moveTo(release);
  await tester.pump(_frame);
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUp(MotionClock.debugReset);

  for (final (past, counts) in [(60.0, true), (80.0, false)]) {
    group('a release $past points past a body that shrank under the finger '
        '${counts ? 'counts' : 'does not count'}', () {
      testWidgets('on a glass button', (tester) async {
        var presses = 0;
        final width = ValueNotifier(_wide);
        addTearDown(width.dispose);
        await tester.pumpWidget(
          _app(
            ValueListenableBuilder(
              valueListenable: width,
              builder: (context, w, _) => RawGlassButton(
                onPressed: () => presses++,
                builder: _plain,
                child: SizedBox(width: w, height: 44),
              ),
            ),
          ),
        );
        await _pressShrinkRelease(
          tester,
          find.byType(RawGlassButton),
          width,
          past,
        );
        expect(presses, counts ? 1 : 0);
      });

      testWidgets('on a segment', (tester) async {
        final values = <String>[];
        final width = ValueNotifier(_wide);
        addTearDown(width.dispose);
        await tester.pumpWidget(
          _app(
            ValueListenableBuilder(
              valueListenable: width,
              builder: (context, w, _) => SizedBox(
                width: w,
                child: GlassSegmentedControl<String>(
                  segments: const [
                    GlassSegment(value: 'a', label: Text('One')),
                    GlassSegment(value: 'b', label: Text('Two')),
                    GlassSegment(value: 'c', label: Text('Three')),
                  ],
                  groupValue: 'a',
                  onChanged: values.add,
                ),
              ),
            ),
          ),
        );
        await _pressShrinkRelease(
          tester,
          find.byType(GlassSegmentedControl<String>),
          width,
          past,
        );
        expect(values, counts ? ['c'] : isEmpty);
      });

      test('on a menu source', () {
        const center = Offset(200, 400);
        const bounds = Size(402, 874);
        MenuSource source(double width) => MenuSource(
          Rect.fromCenter(center: center, width: width, height: 44),
        );
        final motion = MenuMotion(
          source: source(_wide),
          bounds: bounds,
          itemCount: 2,
        )..opensOnTap = false;
        motion.pointerDown(0, center);
        motion.relayout(source: source(_narrow), bounds: bounds);
        motion.pointerUp(
          0.1,
          center + const Offset(_narrow / 2, 0) + Offset(past, 0),
        );
        expect(
          motion.drainEvents().whereType<MenuTapped>(),
          hasLength(counts ? 1 : 0),
        );
        expect(motion.tuning.reach, same(glassButtonReach));
      });
    });
  }
}
